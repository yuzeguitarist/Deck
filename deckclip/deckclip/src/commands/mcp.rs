use std::borrow::Cow;
use std::env;
use std::fs;
use std::io::{stdout, IsTerminal, Stdout, Write};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{anyhow, bail, Result};
use crossterm::cursor::{Hide, MoveTo, Show};
use crossterm::event::{self, Event, KeyCode, KeyEventKind};
use crossterm::execute;
use crossterm::queue;
use crossterm::style::{
    Attribute, Color, ResetColor, SetAttribute, SetForegroundColor,
};
use crossterm::terminal::{
    disable_raw_mode, enable_raw_mode, size, Clear, ClearType, EnterAlternateScreen,
    LeaveAlternateScreen,
};
use deckclip_core::config::{default_socket_path, default_token_path};
use deckclip_core::{Config, DeckClient};
use deckclip_protocol::Response;
use rmcp::handler::server::wrapper::{Json, Parameters};
use rmcp::handler::server::ServerHandler;
use rmcp::model::{
    ErrorData, Implementation, ListToolsResult, ServerCapabilities, ServerInfo, Tool,
};
use rmcp::service::serve_server;
use rmcp::transport::io::stdio;
use rmcp::{tool, tool_handler, tool_router};
use schemars::{json_schema, JsonSchema, Schema, SchemaGenerator};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use textwrap::Options;
use unicode_width::UnicodeWidthStr;

use crate::cli::{McpAction, McpCommand, McpSetupArgs, McpSetupClient};
use crate::i18n;
use crate::output::{render_error_message, OutputMode};

const MCP_SERVER_KEY: &str = "deck";
const OPENCODE_SCHEMA_URL: &str = "https://opencode.ai/config.json";

const TOOL_HEALTH_STATUS: &str = "deck_health_status";
const TOOL_READ_LATEST: &str = "deck_read_latest_clipboard";
const TOOL_LIST_ITEMS: &str = "deck_list_clipboard_items";
const TOOL_WRITE_TEXT: &str = "deck_write_clipboard_text";
const TOOL_SEARCH_ITEMS: &str = "deck_search_clipboard_items";
const TOOL_SEARCH_HISTORY: &str = "deck_search_clipboard_history";
const TOOL_TRANSFORM_TEXT: &str = "deck_transform_clipboard_text";
const TOOL_LIST_SCRIPT_PLUGINS: &str = "deck_list_script_plugins";
const TOOL_READ_SCRIPT_PLUGIN: &str = "deck_read_script_plugin";
const TOOL_RUN_SCRIPT_TRANSFORM: &str = "deck_run_script_transform";

pub async fn run(command: McpCommand, output: OutputMode) -> Result<()> {
    match command.action {
        Some(McpAction::Serve) => serve().await,
        Some(McpAction::Tools) => run_tools(output),
        Some(McpAction::Doctor) => run_doctor(output).await,
        Some(McpAction::Setup(args)) => run_setup_entry(args, output),
        None => run_default_setup(output),
    }
}

async fn serve() -> Result<()> {
    let server = DeckMcpServer::new();
    let running = serve_server(server, stdio()).await?;
    let _ = running.waiting().await?;
    Ok(())
}

fn run_tools(output: OutputMode) -> Result<()> {
    let tools = tool_descriptors();
    let json_output = serde_json::to_value(&tools)?;
    output.print_data(&render_tool_catalog(&tools), &json_output);
    Ok(())
}

async fn run_doctor(output: OutputMode) -> Result<()> {
    let current_executable = env::current_exe().ok();
    let command_in_path = find_command_in_path("deckclip");
    let recommended_command = resolve_command(None);

    let socket_path = default_socket_path();
    let token_path = default_token_path();

    let health = match check_deck_health().await {
        Ok(_) => DoctorHealth {
            ok: true,
            message: i18n::t("health.ok"),
        },
        Err(err) => DoctorHealth {
            ok: false,
            message: err.to_string(),
        },
    };

    let report = DoctorReport {
        recommended_command,
        command_in_path: command_in_path.map(path_to_string),
        current_executable: current_executable.map(path_to_string),
        socket: DoctorPathStatus {
            path: path_to_string(&socket_path),
            exists: socket_path.exists(),
        },
        token: DoctorPathStatus {
            path: path_to_string(&token_path),
            exists: token_path.exists(),
        },
        health,
        targets: vec![
            DoctorTarget::new(McpSetupClient::ClaudeDesktop),
            DoctorTarget::new(McpSetupClient::Cursor),
            DoctorTarget::new(McpSetupClient::Codex),
            DoctorTarget::new(McpSetupClient::Opencode),
        ],
    };

    let json_output = serde_json::to_value(&report)?;
    output.print_data(&render_doctor_report(&report), &json_output);
    Ok(())
}

fn run_default_setup(output: OutputMode) -> Result<()> {
    if matches!(output, OutputMode::Json)
        || !std::io::stdin().is_terminal()
        || !std::io::stdout().is_terminal()
    {
        bail!("{}", i18n::t("err.mcp_setup_wizard_requires_terminal"));
    }

    let command = resolve_command(None);
    let detected = detect_setup_clients()?;

    if detected.is_empty() {
        let message = render_empty_setup_wizard();
        let json_output = json!({
            "message": i18n::t("mcp.setup.wizard.none_detected"),
            "detected_clients": [],
        });
        output.print_data(&message, &json_output);
        return Ok(());
    }

    match run_setup_wizard(&detected)? {
        SetupWizardResult::Cancelled => {
            output.print_success(&i18n::t("mcp.setup.wizard.cancelled"));
            Ok(())
        }
        SetupWizardResult::Submit(clients) if clients.is_empty() => {
            output.print_success(&i18n::t("mcp.setup.wizard.no_selection"));
            Ok(())
        }
        SetupWizardResult::Submit(clients) => {
            let entries = run_setup_clients(&clients, None, &command, true)?;
            let json_output = serde_json::to_value(&entries)?;
            output.print_data(&render_auto_setup_entries(&entries), &json_output);
            Ok(())
        }
    }
}

fn run_setup_entry(args: McpSetupArgs, output: OutputMode) -> Result<()> {
    if args.path.is_some() && args.client == McpSetupClient::All {
        bail!("{}", i18n::t("err.mcp_setup_path_requires_single_client"));
    }

    let command = resolve_command(args.command.as_deref());
    let clients = selected_clients(args.client);
    let entries = run_setup_clients(&clients, args.path.as_deref(), &command, args.write)?;

    let json_output = serde_json::to_value(&entries)?;
    output.print_data(&render_setup_entries(&entries), &json_output);
    Ok(())
}

fn run_setup_clients(
    clients: &[McpSetupClient],
    path_override: Option<&Path>,
    command: &str,
    write: bool,
) -> Result<Vec<SetupEntry>> {
    let mut entries = Vec::with_capacity(clients.len());

    for client in clients.iter().copied() {
        let plan = build_setup_plan(client, path_override, command)?;
        let (mode, backup_path) = if write {
            match write_setup_plan(&plan)? {
                SetupWriteOutcome::Written { backup_path } => (SetupMode::Written, backup_path),
                SetupWriteOutcome::AlreadyPresent => (SetupMode::AlreadyPresent, None),
            }
        } else {
            (SetupMode::Preview, None)
        };

        entries.push(plan.into_output(mode, command, backup_path));
    }

    Ok(entries)
}

fn selected_clients(client: McpSetupClient) -> Vec<McpSetupClient> {
    match client {
        McpSetupClient::All => vec![
            McpSetupClient::ClaudeDesktop,
            McpSetupClient::Cursor,
            McpSetupClient::Codex,
            McpSetupClient::Opencode,
        ],
        client => vec![client],
    }
}

fn client_label_key(client: McpSetupClient) -> &'static str {
    match client {
        McpSetupClient::ClaudeDesktop => "mcp.client.claude_desktop",
        McpSetupClient::Cursor => "mcp.client.cursor",
        McpSetupClient::Codex => "mcp.client.codex",
        McpSetupClient::Opencode => "mcp.client.opencode",
        McpSetupClient::All => unreachable!(),
    }
}

fn detect_setup_clients() -> Result<Vec<DetectedSetupClient>> {
    let mut detected = Vec::new();

    for client in selected_clients(McpSetupClient::All) {
        if is_client_installed(client) {
            let path = default_target_path(client)?;
            let inspection = inspect_target_config(client, &path);
            detected.push(DetectedSetupClient {
                client,
                label: i18n::t(client_label_key(client)),
                path: path_to_string(&path),
                status: inspection.status,
                selected: true,
            });
        }
    }

    Ok(detected)
}

fn is_client_installed(client: McpSetupClient) -> bool {
    if default_target_path(client)
        .map(|path| path.exists())
        .unwrap_or(false)
    {
        return true;
    }

    match client {
        McpSetupClient::ClaudeDesktop => {
            app_bundle_exists(&["/Applications/Claude.app", "/Applications/Claude Desktop.app"], &["Claude.app", "Claude Desktop.app"])
        }
        McpSetupClient::Cursor => app_bundle_exists(&["/Applications/Cursor.app"], &["Cursor.app"]),
        McpSetupClient::Codex => find_command_in_path("codex").is_some(),
        McpSetupClient::Opencode => find_command_in_path("opencode").is_some(),
        McpSetupClient::All => false,
    }
}

fn app_bundle_exists(system_paths: &[&str], user_app_names: &[&str]) -> bool {
    if system_paths.iter().any(|path| Path::new(path).exists()) {
        return true;
    }

    home_dir()
        .map(|home| {
            user_app_names
                .iter()
                .map(|name| home.join("Applications").join(name))
                .any(|path| path.exists())
        })
        .unwrap_or(false)
}

fn render_empty_setup_wizard() -> String {
    [
        i18n::t("mcp.setup.wizard.title"),
        String::new(),
        i18n::t("mcp.setup.wizard.none_detected"),
        i18n::t("mcp.setup.wizard.none_detected_hint"),
    ]
    .join("\n")
}

fn run_setup_wizard(detected: &[DetectedSetupClient]) -> Result<SetupWizardResult> {
    let mut terminal = SetupWizardTerminal::enter()?;
    let mut state = SetupWizardState::new(detected);

    loop {
        terminal.draw(&state)?;

        match event::read()? {
            Event::Key(key) => {
                if matches!(key.kind, KeyEventKind::Release) {
                    continue;
                }

                match key.code {
                    KeyCode::Up => state.move_up(),
                    KeyCode::Down => state.move_down(),
                    KeyCode::Char(' ') => state.toggle(),
                    KeyCode::Enter => {
                        return Ok(SetupWizardResult::Submit(state.selected_clients()));
                    }
                    KeyCode::Esc | KeyCode::Char('q') => {
                        return Ok(SetupWizardResult::Cancelled);
                    }
                    _ => {}
                }
            }
            _ => {}
        }
    }
}

fn render_tool_catalog(tools: &[ToolDescriptor]) -> String {
    let mut lines = vec![i18n::t("mcp.tools.title"), String::new()];

    for tool in tools {
        lines.push(tool.name.to_string());
        lines.push(format!(
            "  {} {}",
            i18n::t("mcp.tools.label.description"),
            tool.description
        ));
        lines.push(format!(
            "  {} {}",
            i18n::t("mcp.tools.label.input"),
            tool.input
        ));
        lines.push(format!(
            "  {} {}",
            i18n::t("mcp.tools.label.read_only"),
            if tool.read_only {
                i18n::t("mcp.common.yes")
            } else {
                i18n::t("mcp.common.no")
            }
        ));
        lines.push(String::new());
    }

    lines.push(i18n::t("mcp.tools.footer"));
    lines.join("\n")
}

struct SetupWizardTerminal {
    stdout: Stdout,
}

#[derive(Clone, Copy)]
struct SetupWizardLayout {
    terminal_height: u16,
    content_width: usize,
}

#[derive(Clone, Copy)]
enum SetupWizardTextStyle {
    Plain,
    Bold,
    Dim,
    Highlight,
}

struct SetupWizardScreenWriter<'a> {
    stdout: &'a mut Stdout,
    layout: SetupWizardLayout,
    row: u16,
}

impl SetupWizardLayout {
    fn detect() -> Self {
        let (width, height) = size().unwrap_or((80, 24));
        let terminal_width = width.max(1) as usize;

        Self {
            terminal_height: height.max(1),
            content_width: terminal_width.saturating_sub(1).max(1),
        }
    }
}

impl<'a> SetupWizardScreenWriter<'a> {
    fn new(stdout: &'a mut Stdout, layout: SetupWizardLayout, start_row: u16) -> Self {
        Self {
            stdout,
            layout,
            row: start_row,
        }
    }

    fn blank_line(&mut self) -> Result<()> {
        self.clear_current_line()?;
        self.row = self.row.saturating_add(1);
        Ok(())
    }

    fn clear_current_line(&mut self) -> Result<()> {
        if self.row >= self.layout.terminal_height {
            return Ok(());
        }

        queue!(
            self.stdout,
            MoveTo(0, self.row),
            Clear(ClearType::CurrentLine)
        )?;
        Ok(())
    }

    fn write_line(&mut self, line: &str, style: SetupWizardTextStyle) -> Result<()> {
        if self.row >= self.layout.terminal_height {
            return Ok(());
        }

        self.clear_current_line()?;
        queue!(self.stdout, MoveTo(0, self.row))?;

        match style {
            SetupWizardTextStyle::Plain => {}
            SetupWizardTextStyle::Bold => {
                queue!(self.stdout, SetAttribute(Attribute::Bold))?;
            }
            SetupWizardTextStyle::Dim => {
                queue!(self.stdout, SetForegroundColor(Color::DarkGrey))?;
            }
            SetupWizardTextStyle::Highlight => {
                queue!(
                    self.stdout,
                    SetForegroundColor(Color::Yellow),
                    SetAttribute(Attribute::Bold)
                )?;
            }
        }

        write!(self.stdout, "{line}")?;
        queue!(self.stdout, ResetColor, SetAttribute(Attribute::Reset))?;
        self.row = self.row.saturating_add(1);
        Ok(())
    }

    fn write_wrapped(
        &mut self,
        initial_indent: &str,
        subsequent_indent: &str,
        text: &str,
        style: SetupWizardTextStyle,
    ) -> Result<()> {
        let options = Options::new(self.layout.content_width)
            .initial_indent(initial_indent)
            .subsequent_indent(subsequent_indent)
            .break_words(true)
            .word_splitter(textwrap::WordSplitter::NoHyphenation);

        for line in textwrap::wrap(text, &options) {
            self.write_line(line.as_ref(), style)?;
        }

        Ok(())
    }
}

impl SetupWizardTerminal {
    fn enter() -> Result<Self> {
        enable_raw_mode()?;
        let mut stdout = stdout();
        execute!(stdout, EnterAlternateScreen, Hide)?;
        Ok(Self { stdout })
    }

    fn draw(&mut self, state: &SetupWizardState) -> Result<()> {
        queue!(self.stdout, MoveTo(0, 0), Clear(ClearType::All))?;
        let layout = SetupWizardLayout::detect();
        let mut screen = SetupWizardScreenWriter::new(&mut self.stdout, layout, 0);

        screen.write_wrapped(
            "",
            "",
            &i18n::t("mcp.setup.wizard.title"),
            SetupWizardTextStyle::Bold,
        )?;
        screen.blank_line()?;
        screen.write_wrapped(
            "",
            "",
            &i18n::t("mcp.setup.wizard.detected"),
            SetupWizardTextStyle::Plain,
        )?;
        screen.write_wrapped(
            "",
            "",
            &i18n::t("mcp.setup.wizard.hint"),
            SetupWizardTextStyle::Dim,
        )?;
        screen.blank_line()?;

        for (index, item) in state.items.iter().enumerate() {
            let cursor_prefix = if index == state.cursor { ">" } else { " " };
            let mark = if item.selected { "[x]" } else { "[ ]" };
            let title_prefix = format!("{cursor_prefix} {mark} ");
            let title_indent = " ".repeat(title_prefix.width());
            let title_style = if index == state.cursor {
                SetupWizardTextStyle::Highlight
            } else {
                SetupWizardTextStyle::Plain
            };

            screen.write_wrapped(&title_prefix, &title_indent, &item.label, title_style)?;

            let path_prefix = format!("    {} ", i18n::t("mcp.setup.label.path"));
            let path_indent = " ".repeat(path_prefix.width());
            screen.write_wrapped(
                &path_prefix,
                &path_indent,
                &item.path,
                SetupWizardTextStyle::Plain,
            )?;

            let status_prefix = format!("    {} ", i18n::t("mcp.setup.wizard.label.status"));
            let status_indent = " ".repeat(status_prefix.width());
            screen.write_wrapped(
                &status_prefix,
                &status_indent,
                &item.status,
                SetupWizardTextStyle::Plain,
            )?;

            if index + 1 < state.items.len() {
                screen.blank_line()?;
            }
        }

        self.stdout.flush()?;
        Ok(())
    }
}

impl Drop for SetupWizardTerminal {
    fn drop(&mut self) {
        let _ = execute!(self.stdout, Show, LeaveAlternateScreen);
        let _ = disable_raw_mode();
    }
}

struct SetupWizardState {
    items: Vec<DetectedSetupClient>,
    cursor: usize,
}

impl SetupWizardState {
    fn new(detected: &[DetectedSetupClient]) -> Self {
        Self {
            items: detected.to_vec(),
            cursor: 0,
        }
    }

    fn move_up(&mut self) {
        self.cursor = self.cursor.saturating_sub(1);
    }

    fn move_down(&mut self) {
        self.cursor = (self.cursor + 1).min(self.items.len().saturating_sub(1));
    }

    fn toggle(&mut self) {
        if let Some(item) = self.items.get_mut(self.cursor) {
            item.selected = !item.selected;
        }
    }

    fn selected_clients(&self) -> Vec<McpSetupClient> {
        self.items
            .iter()
            .filter(|item| item.selected)
            .map(|item| item.client)
            .collect()
    }
}

enum SetupWizardResult {
    Cancelled,
    Submit(Vec<McpSetupClient>),
}

fn render_doctor_report(report: &DoctorReport) -> String {
    let mut lines = vec![i18n::t("mcp.doctor.title"), String::new()];

    lines.push(i18n::t("mcp.doctor.section.bridge"));
    lines.push(format!(
        "  {} {}",
        i18n::t("mcp.doctor.label.recommended_command"),
        report.recommended_command
    ));
    lines.push(format!(
        "  {} {}",
        i18n::t("mcp.doctor.label.command_in_path"),
        report
            .command_in_path
            .clone()
            .unwrap_or_else(|| i18n::t("mcp.common.not_found"))
    ));
    lines.push(format!(
        "  {} {}",
        i18n::t("mcp.doctor.label.current_executable"),
        report
            .current_executable
            .clone()
            .unwrap_or_else(|| i18n::t("mcp.common.unavailable"))
    ));
    lines.push(String::new());

    lines.push(i18n::t("mcp.doctor.section.service"));
    lines.push(format!(
        "  {} {} ({})",
        i18n::t("mcp.doctor.label.socket_path"),
        report.socket.path,
        bool_label(report.socket.exists)
    ));
    lines.push(format!(
        "  {} {} ({})",
        i18n::t("mcp.doctor.label.token_path"),
        report.token.path,
        bool_label(report.token.exists)
    ));
    lines.push(format!(
        "  {} {} - {}",
        i18n::t("mcp.doctor.label.deck_health"),
        if report.health.ok {
            i18n::t("mcp.status.ok")
        } else {
            i18n::t("mcp.status.failed")
        },
        report.health.message
    ));
    lines.push(String::new());

    lines.push(i18n::t("mcp.doctor.section.targets"));
    for target in &report.targets {
        lines.push(format!(
            "  {}: {} — {}",
            target.client, target.path, target.status
        ));
    }
    lines.push(String::new());
    lines.push(i18n::t("mcp.doctor.footer"));

    lines.join("\n")
}

fn render_setup_entries(entries: &[SetupEntry]) -> String {
    let mut lines = vec![i18n::t("mcp.setup.title"), String::new()];

    for (index, entry) in entries.iter().enumerate() {
        lines.push(format!(
            "{} {}",
            i18n::t("mcp.setup.label.client"),
            entry.client
        ));
        lines.push(format!(
            "{} {}",
            i18n::t("mcp.setup.label.mode"),
            entry.mode
        ));
        lines.push(format!(
            "{} {}",
            i18n::t("mcp.setup.label.path"),
            entry.path
        ));
        lines.push(format!(
            "{} {}",
            i18n::t("mcp.setup.label.command"),
            entry.command
        ));
        if let Some(backup_path) = &entry.backup_path {
            lines.push(format!(
                "{} {}",
                i18n::t("mcp.setup.label.backup"),
                backup_path
            ));
        }
        lines.push(i18n::t("mcp.setup.label.snippet"));
        lines.push(entry.snippet.clone());

        if !entry.notes.is_empty() {
            lines.push(i18n::t("mcp.setup.label.notes"));
            for note in &entry.notes {
                lines.push(format!("  - {}", note));
            }
        }

        if index + 1 < entries.len() {
            lines.push(String::new());
        }
    }

    lines.join("\n")
}

fn render_auto_setup_entries(entries: &[SetupEntry]) -> String {
    let mut lines = vec![i18n::t("mcp.setup.title"), String::new()];

    for (index, entry) in entries.iter().enumerate() {
        lines.push(format!(
            "{} {}",
            i18n::t("mcp.setup.label.client"),
            entry.client
        ));
        lines.push(format!(
            "{} {}",
            i18n::t("mcp.setup.label.mode"),
            entry.mode
        ));
        lines.push(format!(
            "{} {}",
            i18n::t("mcp.setup.label.path"),
            entry.path
        ));

        if let Some(backup_path) = &entry.backup_path {
            lines.push(format!(
                "{} {}",
                i18n::t("mcp.setup.label.backup"),
                backup_path
            ));
        }

        if !entry.notes.is_empty() {
            lines.push(i18n::t("mcp.setup.label.notes"));
            for note in &entry.notes {
                lines.push(format!("  - {}", note));
            }
        }

        if index + 1 < entries.len() {
            lines.push(String::new());
        }
    }

    lines.join("\n")
}

async fn check_deck_health() -> Result<()> {
    let mut client = DeckClient::new(Config::default());
    client
        .health()
        .await
        .map(|_| ())
        .map_err(|err| anyhow!(render_error_message(&anyhow::Error::new(err))))
}

fn tool_descriptors() -> Vec<ToolDescriptor> {
    vec![
        ToolDescriptor::new(
            TOOL_HEALTH_STATUS,
            "mcp.tools.health.description",
            "mcp.tools.health.input",
            true,
        ),
        ToolDescriptor::new(
            TOOL_READ_LATEST,
            "mcp.tools.read_latest.description",
            "mcp.tools.read_latest.input",
            true,
        ),
        ToolDescriptor::new(
            TOOL_LIST_ITEMS,
            "mcp.tools.list_items.description",
            "mcp.tools.list_items.input",
            true,
        ),
        ToolDescriptor::new(
            TOOL_WRITE_TEXT,
            "mcp.tools.write_text.description",
            "mcp.tools.write_text.input",
            false,
        ),
        ToolDescriptor::new(
            TOOL_SEARCH_ITEMS,
            "mcp.tools.search_items.description",
            "mcp.tools.search_items.input",
            true,
        ),
        ToolDescriptor::new(
            TOOL_SEARCH_HISTORY,
            "mcp.tools.search_history.description",
            "mcp.tools.search_history.input",
            true,
        ),
        ToolDescriptor::new(
            TOOL_TRANSFORM_TEXT,
            "mcp.tools.transform_text.description",
            "mcp.tools.transform_text.input",
            true,
        ),
        ToolDescriptor::new(
            TOOL_LIST_SCRIPT_PLUGINS,
            "mcp.tools.list_script_plugins.description",
            "mcp.tools.list_script_plugins.input",
            true,
        ),
        ToolDescriptor::new(
            TOOL_READ_SCRIPT_PLUGIN,
            "mcp.tools.read_script_plugin.description",
            "mcp.tools.read_script_plugin.input",
            true,
        ),
        ToolDescriptor::new(
            TOOL_RUN_SCRIPT_TRANSFORM,
            "mcp.tools.run_script_transform.description",
            "mcp.tools.run_script_transform.input",
            false,
        ),
    ]
}

fn server_instructions() -> String {
    i18n::t("mcp.server.instructions")
}

fn tool_title_key(name: &str) -> Option<&'static str> {
    match name {
        TOOL_HEALTH_STATUS => Some("mcp.tool.health.title"),
        TOOL_READ_LATEST => Some("mcp.tool.read_latest.title"),
        TOOL_LIST_ITEMS => Some("mcp.tool.list_items.title"),
        TOOL_WRITE_TEXT => Some("mcp.tool.write_text.title"),
        TOOL_SEARCH_ITEMS => Some("mcp.tool.search_items.title"),
        TOOL_SEARCH_HISTORY => Some("mcp.tool.search_history.title"),
        TOOL_TRANSFORM_TEXT => Some("mcp.tool.transform_text.title"),
        TOOL_LIST_SCRIPT_PLUGINS => Some("mcp.tool.list_script_plugins.title"),
        TOOL_READ_SCRIPT_PLUGIN => Some("mcp.tool.read_script_plugin.title"),
        TOOL_RUN_SCRIPT_TRANSFORM => Some("mcp.tool.run_script_transform.title"),
        _ => None,
    }
}

fn tool_description_key(name: &str) -> Option<&'static str> {
    match name {
        TOOL_HEALTH_STATUS => Some("mcp.tools.health.description"),
        TOOL_READ_LATEST => Some("mcp.tools.read_latest.description"),
        TOOL_LIST_ITEMS => Some("mcp.tools.list_items.description"),
        TOOL_WRITE_TEXT => Some("mcp.tools.write_text.description"),
        TOOL_SEARCH_ITEMS => Some("mcp.tools.search_items.description"),
        TOOL_SEARCH_HISTORY => Some("mcp.tools.search_history.description"),
        TOOL_TRANSFORM_TEXT => Some("mcp.tools.transform_text.description"),
        TOOL_LIST_SCRIPT_PLUGINS => Some("mcp.tools.list_script_plugins.description"),
        TOOL_READ_SCRIPT_PLUGIN => Some("mcp.tools.read_script_plugin.description"),
        TOOL_RUN_SCRIPT_TRANSFORM => Some("mcp.tools.run_script_transform.description"),
        _ => None,
    }
}

fn localize_tool_definition(mut tool: Tool) -> Tool {
    if let Some(title_key) = tool_title_key(tool.name.as_ref()) {
        tool.title = Some(i18n::t(title_key));
    }

    if let Some(description_key) = tool_description_key(tool.name.as_ref()) {
        tool.description = Some(Cow::Owned(i18n::t(description_key)));
    }

    tool
}

fn localized_tool_catalog() -> Vec<Tool> {
    DeckMcpServer::tool_router()
        .list_all()
        .into_iter()
        .map(localize_tool_definition)
        .collect()
}

fn build_setup_plan(
    client: McpSetupClient,
    path_override: Option<&Path>,
    command: &str,
) -> Result<SetupPlan> {
    let path = match path_override {
        Some(path) => path.to_path_buf(),
        None => default_target_path(client)?,
    };

    match client {
        McpSetupClient::ClaudeDesktop => {
            let server_value = json!({
                "type": "stdio",
                "command": command,
                "args": ["mcp", "serve"],
            });
            let snippet = serde_json::to_string_pretty(&json_mcp_snippet(
                "mcpServers",
                server_value.clone(),
            ))?;

            Ok(SetupPlan {
                client_label_key: "mcp.client.claude_desktop",
                path,
                snippet,
                note_keys: vec!["mcp.setup.note.restart_client"],
                kind: SetupPlanKind::JsonMcpServers {
                    root_key: "mcpServers",
                    server_value,
                },
            })
        }
        McpSetupClient::Cursor => {
            let server_value = json!({
                "type": "stdio",
                "command": command,
                "args": ["mcp", "serve"],
            });
            let snippet = serde_json::to_string_pretty(&json_mcp_snippet(
                "mcpServers",
                server_value.clone(),
            ))?;

            Ok(SetupPlan {
                client_label_key: "mcp.client.cursor",
                path,
                snippet,
                note_keys: vec![
                    "mcp.setup.note.cursor_global",
                    "mcp.setup.note.restart_client",
                ],
                kind: SetupPlanKind::JsonMcpServers {
                    root_key: "mcpServers",
                    server_value,
                },
            })
        }
        McpSetupClient::Codex => {
            let snippet = build_codex_snippet(command);
            Ok(SetupPlan {
                client_label_key: "mcp.client.codex",
                path,
                snippet,
                note_keys: vec!["mcp.setup.note.restart_client"],
                kind: SetupPlanKind::CodexToml,
            })
        }
        McpSetupClient::Opencode => {
            let server_value = opencode_server_value(command);
            let snippet = serde_json::to_string_pretty(&opencode_snippet(command))?;

            Ok(SetupPlan {
                client_label_key: "mcp.client.opencode",
                path,
                snippet,
                note_keys: vec!["mcp.setup.note.restart_client"],
                kind: SetupPlanKind::OpencodeJson { server_value },
            })
        }
        McpSetupClient::All => unreachable!(),
    }
}

fn write_setup_plan(plan: &SetupPlan) -> Result<SetupWriteOutcome> {
    match &plan.kind {
        SetupPlanKind::JsonMcpServers {
            root_key,
            server_value,
        } => write_json_mcp_config(&plan.path, root_key, server_value),
        SetupPlanKind::CodexToml => write_codex_config(&plan.path, &plan.snippet),
        SetupPlanKind::OpencodeJson { server_value } => {
            write_opencode_config(&plan.path, server_value)
        }
    }
}

fn write_json_mcp_config(
    path: &Path,
    root_key: &str,
    server_value: &Value,
) -> Result<SetupWriteOutcome> {
    ensure_parent_dir(path)?;

    let mut root = if path.exists() {
        let text = fs::read_to_string(path)?;
        if text.trim().is_empty() {
            json!({})
        } else {
            serde_json::from_str::<Value>(&text).map_err(|err| {
                anyhow!(format_i18n(
                    "err.mcp_setup_invalid_json",
                    &[&path_to_string(path), &err.to_string()]
                ))
            })?
        }
    } else {
        json!({})
    };

    let root_object = root.as_object_mut().ok_or_else(|| {
        anyhow!(format_i18n(
            "err.mcp_setup_invalid_root",
            &[&path_to_string(path)]
        ))
    })?;

    let section = root_object
        .entry(root_key.to_string())
        .or_insert_with(|| json!({}));
    let section_object = section.as_object_mut().ok_or_else(|| {
        anyhow!(format_i18n(
            "err.mcp_setup_invalid_section",
            &[root_key, &path_to_string(path)]
        ))
    })?;

    if section_object.get(MCP_SERVER_KEY) == Some(server_value) {
        return Ok(SetupWriteOutcome::AlreadyPresent);
    }

    section_object.insert(MCP_SERVER_KEY.to_string(), server_value.clone());
    let rendered = format!("{}\n", serde_json::to_string_pretty(&root)?);
    let backup_path = create_backup_if_needed(path)?;
    fs::write(path, rendered)?;
    Ok(SetupWriteOutcome::Written { backup_path })
}

fn write_codex_config(path: &Path, snippet: &str) -> Result<SetupWriteOutcome> {
    ensure_parent_dir(path)?;

    let existing = if path.exists() {
        fs::read_to_string(path)?
    } else {
        String::new()
    };

    if existing.contains("[mcp_servers.deck]") {
        return Ok(SetupWriteOutcome::AlreadyPresent);
    }

    let mut rendered = existing;
    if !rendered.trim().is_empty() {
        if !rendered.ends_with('\n') {
            rendered.push('\n');
        }
        rendered.push('\n');
    }
    rendered.push_str(snippet);
    let backup_path = create_backup_if_needed(path)?;
    fs::write(path, rendered)?;
    Ok(SetupWriteOutcome::Written { backup_path })
}

fn write_opencode_config(path: &Path, server_value: &Value) -> Result<SetupWriteOutcome> {
    ensure_parent_dir(path)?;

    let mut root = if path.exists() {
        let text = fs::read_to_string(path)?;
        if text.trim().is_empty() {
            json!({})
        } else {
            serde_json::from_str::<Value>(&text).map_err(|err| {
                anyhow!(format_i18n(
                    "err.mcp_setup_invalid_json",
                    &[&path_to_string(path), &err.to_string()]
                ))
            })?
        }
    } else {
        json!({
            "$schema": OPENCODE_SCHEMA_URL,
        })
    };

    let root_object = root.as_object_mut().ok_or_else(|| {
        anyhow!(format_i18n(
            "err.mcp_setup_invalid_root",
            &[&path_to_string(path)]
        ))
    })?;
    root_object
        .entry("$schema".to_string())
        .or_insert_with(|| Value::String(OPENCODE_SCHEMA_URL.to_string()));

    let section = root_object
        .entry("mcp".to_string())
        .or_insert_with(|| json!({}));
    let section_object = section.as_object_mut().ok_or_else(|| {
        anyhow!(format_i18n(
            "err.mcp_setup_invalid_section",
            &["mcp", &path_to_string(path)]
        ))
    })?;

    if section_object.get(MCP_SERVER_KEY) == Some(server_value) {
        return Ok(SetupWriteOutcome::AlreadyPresent);
    }

    section_object.insert(MCP_SERVER_KEY.to_string(), server_value.clone());
    let rendered = format!("{}\n", serde_json::to_string_pretty(&root)?);
    let backup_path = create_backup_if_needed(path)?;
    fs::write(path, rendered)?;
    Ok(SetupWriteOutcome::Written { backup_path })
}

fn ensure_parent_dir(path: &Path) -> Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    Ok(())
}

fn create_backup_if_needed(path: &Path) -> Result<Option<PathBuf>> {
    if !path.exists() {
        return Ok(None);
    }

    let parent = path.parent().unwrap_or_else(|| Path::new("."));
    let file_name = path
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("config");
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    let mut backup_path = parent.join(format!("{}.deckclip.bak.{}", file_name, timestamp));
    let mut suffix = 1;

    while backup_path.exists() {
        backup_path = parent.join(format!(
            "{}.deckclip.bak.{}.{}",
            file_name, timestamp, suffix
        ));
        suffix += 1;
    }

    fs::copy(path, &backup_path)?;
    Ok(Some(backup_path))
}

fn default_target_path(client: McpSetupClient) -> Result<PathBuf> {
    match client {
        McpSetupClient::ClaudeDesktop => home_dir()
            .map(|home| {
                home.join("Library/Application Support/Claude")
                    .join("claude_desktop_config.json")
            })
            .ok_or_else(|| anyhow!(i18n::t("err.mcp_home_unavailable"))),
        McpSetupClient::Cursor => home_dir()
            .map(|home| home.join(".cursor/mcp.json"))
            .ok_or_else(|| anyhow!(i18n::t("err.mcp_home_unavailable"))),
        McpSetupClient::Codex => home_dir()
            .map(|home| home.join(".codex/config.toml"))
            .ok_or_else(|| anyhow!(i18n::t("err.mcp_home_unavailable"))),
        McpSetupClient::Opencode => home_dir()
            .map(|home| home.join(".config/opencode/opencode.json"))
            .ok_or_else(|| anyhow!(i18n::t("err.mcp_home_unavailable"))),
        McpSetupClient::All => unreachable!(),
    }
}

fn home_dir() -> Option<PathBuf> {
    env::var_os("HOME").map(PathBuf::from)
}

fn resolve_command(command_override: Option<&str>) -> String {
    if let Some(command) = command_override {
        if !command.trim().is_empty() {
            return command.to_string();
        }
    }

    if find_command_in_path("deckclip").is_some() {
        return "deckclip".to_string();
    }

    env::current_exe()
        .map(path_to_string)
        .unwrap_or_else(|_| "deckclip".to_string())
}

fn find_command_in_path(command: &str) -> Option<PathBuf> {
    let paths = env::var_os("PATH")?;
    env::split_paths(&paths)
        .map(|dir| dir.join(command))
        .find(|candidate| candidate.is_file())
}

fn build_codex_snippet(command: &str) -> String {
    format!(
        "[mcp_servers.{server}]\ncommand = {command}\nargs = [\"mcp\", \"serve\"]\n",
        server = MCP_SERVER_KEY,
        command = toml_string(command),
    )
}

fn json_mcp_snippet(root_key: &str, server_value: Value) -> Value {
    let mut servers = serde_json::Map::new();
    servers.insert(MCP_SERVER_KEY.to_string(), server_value);

    let mut root = serde_json::Map::new();
    root.insert(root_key.to_string(), Value::Object(servers));
    Value::Object(root)
}

fn opencode_snippet(command: &str) -> Value {
    let mut root = serde_json::Map::new();
    root.insert(
        "$schema".to_string(),
        Value::String(OPENCODE_SCHEMA_URL.to_string()),
    );

    let mut mcp = serde_json::Map::new();
    mcp.insert(MCP_SERVER_KEY.to_string(), opencode_server_value(command));

    root.insert("mcp".to_string(), Value::Object(mcp));
    Value::Object(root)
}

fn opencode_server_value(command: &str) -> Value {
    json!({
        "type": "local",
        "command": [command, "mcp", "serve"],
        "enabled": true,
    })
}

fn toml_string(value: &str) -> String {
    format!("{:?}", value)
}

fn bool_label(value: bool) -> String {
    if value {
        i18n::t("mcp.status.present")
    } else {
        i18n::t("mcp.status.missing")
    }
}

fn path_to_string(path: impl AsRef<Path>) -> String {
    path.as_ref().display().to_string()
}

fn format_i18n(key: &str, values: &[&str]) -> String {
    let mut rendered = i18n::t(key);
    for value in values {
        rendered = rendered.replacen("{}", value, 1);
    }
    rendered
}

fn response_payload(tool: &str, response: Response) -> ToolPayload {
    let text = response
        .data
        .as_ref()
        .and_then(|data| data.get("text"))
        .and_then(Value::as_str)
        .map(ToOwned::to_owned);

    ToolPayload {
        tool: tool.to_string(),
        text,
        data: normalize_tool_data(response.data),
    }
}

fn normalize_tool_data(data: Option<Value>) -> Option<serde_json::Map<String, Value>> {
    match data {
        Some(Value::Object(map)) => Some(map),
        Some(value) => {
            let mut map = serde_json::Map::new();
            map.insert("value".to_string(), value);
            Some(map)
        }
        None => None,
    }
}

fn latest_clipboard_text(response: &Response) -> Result<String, ErrorData> {
    response
        .data
        .as_ref()
        .and_then(|data| data.get("text"))
        .and_then(Value::as_str)
        .map(ToOwned::to_owned)
        .ok_or_else(|| {
            ErrorData::internal_error(i18n::t("err.mcp_latest_clipboard_missing_text"), None)
        })
}

fn tool_error(err: anyhow::Error) -> ErrorData {
    let message = render_error_message(&err);
    ErrorData::internal_error(message.clone(), Some(json!({ "message": message })))
}

struct DeckMcpServer {
    client: tokio::sync::Mutex<DeckClient>,
}

impl DeckMcpServer {
    fn new() -> Self {
        Self {
            client: tokio::sync::Mutex::new(DeckClient::new(Config::default())),
        }
    }
}

#[tool_router]
impl DeckMcpServer {
    #[tool(
        name = "deck_health_status",
        description = "Check whether the local Deck App bridge is available.",
        annotations(read_only_hint = true)
    )]
    pub async fn health_status(&self) -> Result<Json<ToolPayload>, ErrorData> {
        let mut client = self.client.lock().await;
        let response = client
            .health()
            .await
            .map_err(|err| tool_error(anyhow::Error::new(err)))?;
        Ok(Json(response_payload(TOOL_HEALTH_STATUS, response)))
    }

    #[tool(
        name = "deck_read_latest_clipboard",
        description = "Read the latest clipboard item from Deck.",
        annotations(read_only_hint = true)
    )]
    pub async fn read_latest_clipboard(&self) -> Result<Json<ToolPayload>, ErrorData> {
        let mut client = self.client.lock().await;
        let response = client
            .clipboard_latest()
            .await
            .map_err(|err| tool_error(anyhow::Error::new(err)))?;
        Ok(Json(response_payload(TOOL_READ_LATEST, response)))
    }

    #[tool(
        name = "deck_list_clipboard_items",
        description = "List recent clipboard items from Deck as structured metadata.",
        annotations(read_only_hint = true)
    )]
    pub async fn list_clipboard_items(
        &self,
        params: Parameters<ListClipboardItemsParams>,
    ) -> Result<Json<ToolPayload>, ErrorData> {
        let params = params.0;
        let mut client = self.client.lock().await;
        let response = client
            .clipboard_list(Some(params.limit))
            .await
            .map_err(|err| tool_error(anyhow::Error::new(err)))?;
        Ok(Json(response_payload(TOOL_LIST_ITEMS, response)))
    }

    #[tool(
        name = "deck_write_clipboard_text",
        description = "Write text into Deck's clipboard history."
    )]
    pub async fn write_clipboard_text(
        &self,
        params: Parameters<WriteClipboardTextParams>,
    ) -> Result<Json<ToolPayload>, ErrorData> {
        let params = params.0;
        let mut client = self.client.lock().await;
        let response = client
            .write(
                &params.text,
                params.tag.as_deref(),
                params.tag_id.as_deref(),
                params.raw,
            )
            .await
            .map_err(|err| tool_error(anyhow::Error::new(err)))?;
        Ok(Json(response_payload(TOOL_WRITE_TEXT, response)))
    }

    #[tool(
        name = "deck_search_clipboard_items",
        description = "Search clipboard history and return structured items instead of a natural-language summary.",
        annotations(read_only_hint = true)
    )]
    pub async fn search_clipboard_items(
        &self,
        params: Parameters<SearchClipboardItemsParams>,
    ) -> Result<Json<ToolPayload>, ErrorData> {
        let params = params.0;
        let mut client = self.client.lock().await;
        let response = client
            .clipboard_search(&params.query, params.mode.as_deref(), Some(params.limit))
            .await
            .map_err(|err| tool_error(anyhow::Error::new(err)))?;
        Ok(Json(response_payload(TOOL_SEARCH_ITEMS, response)))
    }

    #[tool(
        name = "deck_search_clipboard_history",
        description = "Search clipboard history using Deck AI.",
        annotations(read_only_hint = true)
    )]
    pub async fn search_clipboard_history(
        &self,
        params: Parameters<SearchClipboardHistoryParams>,
    ) -> Result<Json<ToolPayload>, ErrorData> {
        let params = params.0;
        let mut client = self.client.lock().await;
        let response = client
            .ai_search(&params.query, params.mode.as_deref(), Some(params.limit))
            .await
            .map_err(|err| tool_error(anyhow::Error::new(err)))?;
        Ok(Json(response_payload(TOOL_SEARCH_HISTORY, response)))
    }

    #[tool(
        name = "deck_transform_clipboard_text",
        description = "Transform text with Deck AI. If text is omitted, Deck uses the latest clipboard item.",
        annotations(read_only_hint = true)
    )]
    pub async fn transform_clipboard_text(
        &self,
        params: Parameters<TransformClipboardTextParams>,
    ) -> Result<Json<ToolPayload>, ErrorData> {
        let params = params.0;
        let mut client = self.client.lock().await;

        let text = match params.text {
            Some(text) => text,
            None => {
                let latest = client
                    .read()
                    .await
                    .map_err(|err| tool_error(anyhow::Error::new(err)))?;
                latest_clipboard_text(&latest)?
            }
        };

        let response = client
            .ai_transform(&params.prompt, Some(&text), params.plugin.as_deref())
            .await
            .map_err(|err| tool_error(anyhow::Error::new(err)))?;
        Ok(Json(response_payload(TOOL_TRANSFORM_TEXT, response)))
    }

    #[tool(
        name = "deck_list_script_plugins",
        description = "List installed Deck script plugins so external agents can discover available automation capabilities.",
        annotations(read_only_hint = true)
    )]
    pub async fn list_script_plugins(
        &self,
        params: Parameters<ListScriptPluginsParams>,
    ) -> Result<Json<ToolPayload>, ErrorData> {
        let params = params.0;
        let query = params.query.as_deref();
        let mut client = self.client.lock().await;
        let response = client
            .script_plugins_list(query, Some(params.limit))
            .await
            .map_err(|err| tool_error(anyhow::Error::new(err)))?;
        Ok(Json(response_payload(TOOL_LIST_SCRIPT_PLUGINS, response)))
    }

    #[tool(
        name = "deck_read_script_plugin",
        description = "Read a Deck script plugin manifest and main file contents for analysis or review.",
        annotations(read_only_hint = true)
    )]
    pub async fn read_script_plugin(
        &self,
        params: Parameters<ReadScriptPluginParams>,
    ) -> Result<Json<ToolPayload>, ErrorData> {
        let params = params.0;
        let mut client = self.client.lock().await;
        let response = client
            .script_plugin_read(&params.plugin_id)
            .await
            .map_err(|err| tool_error(anyhow::Error::new(err)))?;
        Ok(Json(response_payload(TOOL_READ_SCRIPT_PLUGIN, response)))
    }

    #[tool(
        name = "deck_run_script_transform",
        description = "Run an installed Deck script plugin to transform, clean, format, or template text."
    )]
    pub async fn run_script_transform(
        &self,
        params: Parameters<RunScriptTransformParams>,
    ) -> Result<Json<ToolPayload>, ErrorData> {
        let params = params.0;
        let mut client = self.client.lock().await;
        let response = client
            .script_transform_run(&params.plugin_id, &params.input)
            .await
            .map_err(|err| tool_error(anyhow::Error::new(err)))?;
        Ok(Json(response_payload(TOOL_RUN_SCRIPT_TRANSFORM, response)))
    }
}

#[tool_handler(
    name = "deckclip-mcp",
    instructions = "Bridge Deck's local clipboard and AI workflow tools into the Deck app running on this machine."
)]
impl ServerHandler for DeckMcpServer {
    fn get_info(&self) -> ServerInfo {
        ServerInfo::new(ServerCapabilities::builder().enable_tools().build())
            .with_server_info(Implementation::new(
                "deckclip-mcp",
                env!("CARGO_PKG_VERSION"),
            ))
            .with_instructions(server_instructions())
    }

    async fn list_tools(
        &self,
        _request: Option<rmcp::model::PaginatedRequestParams>,
        _context: rmcp::service::RequestContext<rmcp::RoleServer>,
    ) -> Result<ListToolsResult, ErrorData> {
        Ok(ListToolsResult {
            tools: localized_tool_catalog(),
            meta: None,
            next_cursor: None,
        })
    }

    fn get_tool(&self, name: &str) -> Option<Tool> {
        DeckMcpServer::tool_router()
            .get(name)
            .cloned()
            .map(localize_tool_definition)
    }
}

#[derive(Debug, Deserialize, JsonSchema)]
struct WriteClipboardTextParams {
    text: String,
    #[serde(default)]
    tag: Option<String>,
    #[serde(default)]
    tag_id: Option<String>,
    #[serde(default)]
    raw: bool,
}

#[derive(Debug, Deserialize, JsonSchema)]
struct ListClipboardItemsParams {
    #[serde(default = "default_list_limit")]
    limit: u32,
}

#[derive(Debug, Deserialize, JsonSchema)]
struct SearchClipboardItemsParams {
    query: String,
    #[serde(default)]
    mode: Option<String>,
    #[serde(default = "default_search_limit")]
    limit: u32,
}

#[derive(Debug, Deserialize, JsonSchema)]
struct SearchClipboardHistoryParams {
    query: String,
    #[serde(default)]
    mode: Option<String>,
    #[serde(default = "default_search_limit")]
    limit: u32,
}

#[derive(Debug, Deserialize, JsonSchema)]
struct TransformClipboardTextParams {
    prompt: String,
    #[serde(default)]
    text: Option<String>,
    #[serde(default)]
    plugin: Option<String>,
}

#[derive(Debug, Deserialize, JsonSchema)]
struct ListScriptPluginsParams {
    #[serde(default)]
    query: Option<String>,
    #[serde(default = "default_script_plugin_list_limit")]
    limit: u32,
}

#[derive(Debug, Deserialize, JsonSchema)]
struct ReadScriptPluginParams {
    plugin_id: String,
}

#[derive(Debug, Deserialize, JsonSchema)]
struct RunScriptTransformParams {
    plugin_id: String,
    input: String,
}

fn default_list_limit() -> u32 {
    20
}

fn default_search_limit() -> u32 {
    10
}

fn default_script_plugin_list_limit() -> u32 {
    30
}

#[derive(Debug, Serialize, JsonSchema)]
struct ToolPayload {
    tool: String,
    text: Option<String>,
    #[schemars(schema_with = "tool_data_schema")]
    data: Option<serde_json::Map<String, Value>>,
}

fn tool_data_schema(_gen: &mut SchemaGenerator) -> Schema {
    json_schema!({
        "type": "object",
        "additionalProperties": true
    })
}

#[derive(Debug, Serialize)]
struct ToolDescriptor {
    name: &'static str,
    description: String,
    input: String,
    read_only: bool,
}

impl ToolDescriptor {
    fn new(
        name: &'static str,
        description_key: &'static str,
        input_key: &'static str,
        read_only: bool,
    ) -> Self {
        Self {
            name,
            description: i18n::t(description_key),
            input: i18n::t(input_key),
            read_only,
        }
    }
}

#[derive(Debug, Serialize)]
struct DoctorReport {
    recommended_command: String,
    command_in_path: Option<String>,
    current_executable: Option<String>,
    socket: DoctorPathStatus,
    token: DoctorPathStatus,
    health: DoctorHealth,
    targets: Vec<DoctorTarget>,
}

#[derive(Debug, Serialize)]
struct DoctorPathStatus {
    path: String,
    exists: bool,
}

#[derive(Debug, Serialize)]
struct DoctorHealth {
    ok: bool,
    message: String,
}

#[derive(Debug, Serialize)]
struct DoctorTarget {
    client: String,
    path: String,
    file_exists: bool,
    configured: bool,
    status: String,
}

impl DoctorTarget {
    fn new(client: McpSetupClient) -> Self {
        let client_label = i18n::t(client_label_key(client));

        match default_target_path(client) {
            Ok(path) => {
                let inspection = inspect_target_config(client, &path);
                Self {
                    client: client_label,
                    path: path_to_string(&path),
                    file_exists: inspection.file_exists,
                    configured: inspection.configured,
                    status: inspection.status,
                }
            }
            Err(err) => Self {
                client: client_label,
                path: i18n::t("mcp.common.unavailable"),
                file_exists: false,
                configured: false,
                status: err.to_string(),
            },
        }
    }
}

struct DoctorTargetInspection {
    file_exists: bool,
    configured: bool,
    status: String,
}

fn inspect_target_config(client: McpSetupClient, path: &Path) -> DoctorTargetInspection {
    if !path.exists() {
        return DoctorTargetInspection {
            file_exists: false,
            configured: false,
            status: i18n::t("mcp.doctor.target.file_missing"),
        };
    }

    match client {
        McpSetupClient::ClaudeDesktop | McpSetupClient::Cursor => {
            inspect_json_target_config(path, "mcpServers")
        }
        McpSetupClient::Codex => inspect_text_target_config(path, "[mcp_servers.deck]"),
        McpSetupClient::Opencode => inspect_json_target_config(path, "mcp"),
        McpSetupClient::All => unreachable!(),
    }
}

fn inspect_json_target_config(path: &Path, root_key: &str) -> DoctorTargetInspection {
    let text = match fs::read_to_string(path) {
        Ok(text) => text,
        Err(err) => {
            return DoctorTargetInspection {
                file_exists: true,
                configured: false,
                status: format_i18n("mcp.doctor.target.read_failed", &[&err.to_string()]),
            };
        }
    };

    if text.trim().is_empty() {
        return DoctorTargetInspection {
            file_exists: true,
            configured: false,
            status: i18n::t("mcp.doctor.target.not_configured"),
        };
    }

    let root = match serde_json::from_str::<Value>(&text) {
        Ok(root) => root,
        Err(err) => {
            return DoctorTargetInspection {
                file_exists: true,
                configured: false,
                status: format_i18n("mcp.doctor.target.invalid_json", &[&err.to_string()]),
            };
        }
    };

    let configured = root
        .get(root_key)
        .and_then(Value::as_object)
        .map(|servers| servers.contains_key(MCP_SERVER_KEY))
        .unwrap_or(false);

    DoctorTargetInspection {
        file_exists: true,
        configured,
        status: if configured {
            i18n::t("mcp.doctor.target.configured")
        } else {
            i18n::t("mcp.doctor.target.not_configured")
        },
    }
}

fn inspect_text_target_config(path: &Path, needle: &str) -> DoctorTargetInspection {
    match fs::read_to_string(path) {
        Ok(text) => {
            let configured = text.contains(needle);
            DoctorTargetInspection {
                file_exists: true,
                configured,
                status: if configured {
                    i18n::t("mcp.doctor.target.configured")
                } else {
                    i18n::t("mcp.doctor.target.not_configured")
                },
            }
        }
        Err(err) => DoctorTargetInspection {
            file_exists: true,
            configured: false,
            status: format_i18n("mcp.doctor.target.read_failed", &[&err.to_string()]),
        },
    }
}

struct SetupPlan {
    client_label_key: &'static str,
    path: PathBuf,
    snippet: String,
    note_keys: Vec<&'static str>,
    kind: SetupPlanKind,
}

impl SetupPlan {
    fn into_output(
        self,
        mode: SetupMode,
        command: &str,
        backup_path: Option<PathBuf>,
    ) -> SetupEntry {
        SetupEntry {
            client: i18n::t(self.client_label_key),
            mode: i18n::t(mode.key()),
            path: path_to_string(self.path),
            command: command.to_string(),
            backup_path: backup_path.map(|path| path_to_string(&path)),
            snippet: self.snippet,
            notes: self.note_keys.into_iter().map(i18n::t).collect(),
        }
    }
}

enum SetupPlanKind {
    JsonMcpServers {
        root_key: &'static str,
        server_value: Value,
    },
    CodexToml,
    OpencodeJson {
        server_value: Value,
    },
}

enum SetupWriteOutcome {
    Written { backup_path: Option<PathBuf> },
    AlreadyPresent,
}

enum SetupMode {
    Preview,
    Written,
    AlreadyPresent,
}

impl SetupMode {
    fn key(&self) -> &'static str {
        match self {
            SetupMode::Preview => "mcp.setup.mode.preview",
            SetupMode::Written => "mcp.setup.mode.written",
            SetupMode::AlreadyPresent => "mcp.setup.mode.already_present",
        }
    }
}

#[derive(Debug, Serialize)]
struct SetupEntry {
    client: String,
    mode: String,
    path: String,
    command: String,
    backup_path: Option<String>,
    snippet: String,
    notes: Vec<String>,
}

#[derive(Clone)]
struct DetectedSetupClient {
    client: McpSetupClient,
    label: String,
    path: String,
    status: String,
    selected: bool,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn localized_tool_catalog_uses_i18n_metadata() {
        let tools = localized_tool_catalog();
        let health = tools
            .iter()
            .find(|tool| tool.name.as_ref() == TOOL_HEALTH_STATUS)
            .expect("expected localized health tool");
        let read_latest = tools
            .iter()
            .find(|tool| tool.name.as_ref() == TOOL_READ_LATEST)
            .expect("expected localized read_latest tool");
        let list_items = tools
            .iter()
            .find(|tool| tool.name.as_ref() == TOOL_LIST_ITEMS)
            .expect("expected localized list_items tool");
        let search_items = tools
            .iter()
            .find(|tool| tool.name.as_ref() == TOOL_SEARCH_ITEMS)
            .expect("expected localized search_items tool");
        let list_script_plugins = tools
            .iter()
            .find(|tool| tool.name.as_ref() == TOOL_LIST_SCRIPT_PLUGINS)
            .expect("expected localized list_script_plugins tool");
        let run_script_transform = tools
            .iter()
            .find(|tool| tool.name.as_ref() == TOOL_RUN_SCRIPT_TRANSFORM)
            .expect("expected localized run_script_transform tool");

        assert_eq!(
            health.title.as_deref(),
            Some(i18n::t("mcp.tool.health.title").as_str())
        );
        assert_eq!(
            health.description.as_deref(),
            Some(i18n::t("mcp.tools.health.description").as_str())
        );
        assert_eq!(
            read_latest.title.as_deref(),
            Some(i18n::t("mcp.tool.read_latest.title").as_str())
        );
        assert_eq!(
            read_latest.description.as_deref(),
            Some(i18n::t("mcp.tools.read_latest.description").as_str())
        );
        assert_eq!(
            list_items.title.as_deref(),
            Some(i18n::t("mcp.tool.list_items.title").as_str())
        );
        assert_eq!(
            search_items.description.as_deref(),
            Some(i18n::t("mcp.tools.search_items.description").as_str())
        );
        assert_eq!(
            list_script_plugins.title.as_deref(),
            Some(i18n::t("mcp.tool.list_script_plugins.title").as_str())
        );
        assert_eq!(
            run_script_transform.description.as_deref(),
            Some(i18n::t("mcp.tools.run_script_transform.description").as_str())
        );

        let output_schema = health
            .output_schema
            .as_ref()
            .expect("expected health output schema");
        assert_eq!(
            output_schema["properties"]["data"]["type"],
            Value::String("object".to_string())
        );
    }

    #[test]
    fn server_info_uses_localized_instructions() {
        let server = DeckMcpServer::new();
        let info = server.get_info();

        assert_eq!(
            info.instructions.as_deref(),
            Some(i18n::t("mcp.server.instructions").as_str())
        );
    }

    #[test]
    fn write_json_config_merges_existing_servers() {
        let temp_dir = std::env::temp_dir().join("deckclip-mcp-json-test");
        let file_path = temp_dir.join("claude_desktop_config.json");
        let _ = fs::remove_dir_all(&temp_dir);

        ensure_parent_dir(&file_path).unwrap();
        fs::write(
            &file_path,
            serde_json::to_string_pretty(&json!({
                "mcpServers": {
                    "existing": {
                        "command": "existing",
                        "args": ["serve"],
                    }
                }
            }))
            .unwrap(),
        )
        .unwrap();

        let outcome = write_json_mcp_config(
            &file_path,
            "mcpServers",
            &json!({ "command": "deckclip", "args": ["mcp", "serve"] }),
        )
        .unwrap();

        let backup_path = match outcome {
            SetupWriteOutcome::Written { backup_path } => backup_path,
            SetupWriteOutcome::AlreadyPresent => panic!("expected config write"),
        };
        match backup_path.as_ref() {
            Some(path) => assert!(path.exists()),
            None => panic!("expected backup path"),
        }

        let updated: Value =
            serde_json::from_str(&fs::read_to_string(&file_path).unwrap()).unwrap();
        assert!(updated["mcpServers"]["existing"].is_object());
        assert_eq!(updated["mcpServers"]["deck"]["command"], "deckclip");

        let _ = fs::remove_dir_all(&temp_dir);
    }

    #[test]
    fn write_codex_config_appends_once() {
        let temp_dir = std::env::temp_dir().join("deckclip-mcp-codex-test");
        let file_path = temp_dir.join("config.toml");
        let _ = fs::remove_dir_all(&temp_dir);

        ensure_parent_dir(&file_path).unwrap();
        fs::write(&file_path, "model = \"gpt-5\"\n").unwrap();

        let snippet = build_codex_snippet("deckclip");
        let outcome = write_codex_config(&file_path, &snippet).unwrap();
        let backup_path = match outcome {
            SetupWriteOutcome::Written { backup_path } => backup_path,
            SetupWriteOutcome::AlreadyPresent => panic!("expected config write"),
        };
        match backup_path.as_ref() {
            Some(path) => assert!(path.exists()),
            None => panic!("expected backup path"),
        }

        let second = write_codex_config(&file_path, &snippet).unwrap();
        assert!(matches!(second, SetupWriteOutcome::AlreadyPresent));

        let content = fs::read_to_string(&file_path).unwrap();
        assert!(content.contains("[mcp_servers.deck]"));

        let _ = fs::remove_dir_all(&temp_dir);
    }

    #[test]
    fn build_setup_plan_for_cursor_uses_stdio_transport() {
        let temp_dir = std::env::temp_dir().join("deckclip-mcp-cursor-plan");
        let file_path = temp_dir.join("mcp.json");
        let _ = fs::remove_dir_all(&temp_dir);

        let plan = build_setup_plan(McpSetupClient::Cursor, Some(&file_path), "deckclip").unwrap();
        assert!(plan.snippet.contains("\"type\": \"stdio\""));
        assert!(plan
            .note_keys
            .iter()
            .any(|key| *key == "mcp.setup.note.cursor_global"));

        let _ = fs::remove_dir_all(&temp_dir);
    }

    #[test]
    fn write_opencode_config_merges_existing_servers() {
        let temp_dir = std::env::temp_dir().join("deckclip-mcp-opencode-test");
        let file_path = temp_dir.join("opencode.json");
        let _ = fs::remove_dir_all(&temp_dir);

        ensure_parent_dir(&file_path).unwrap();
        fs::write(
            &file_path,
            serde_json::to_string_pretty(&json!({
                "$schema": OPENCODE_SCHEMA_URL,
                "mcp": {
                    "existing": {
                        "type": "local",
                        "command": ["existing", "serve"],
                    }
                }
            }))
            .unwrap(),
        )
        .unwrap();

        let outcome =
            write_opencode_config(&file_path, &opencode_server_value("deckclip")).unwrap();
        let backup_path = match outcome {
            SetupWriteOutcome::Written { backup_path } => backup_path,
            SetupWriteOutcome::AlreadyPresent => panic!("expected config write"),
        };
        match backup_path.as_ref() {
            Some(path) => assert!(path.exists()),
            None => panic!("expected backup path"),
        }

        let updated: Value =
            serde_json::from_str(&fs::read_to_string(&file_path).unwrap()).unwrap();
        assert!(updated["mcp"]["existing"].is_object());
        assert_eq!(updated["mcp"]["deck"]["type"], "local");
        assert_eq!(updated["mcp"]["deck"]["command"][0], "deckclip");

        let _ = fs::remove_dir_all(&temp_dir);
    }

    #[test]
    fn normalize_tool_data_wraps_non_object_values() {
        let wrapped = normalize_tool_data(Some(json!(["a", "b"]))).expect("expected wrapped data");
        assert_eq!(wrapped["value"], json!(["a", "b"]));

        let object =
            normalize_tool_data(Some(json!({ "text": "hello" }))).expect("expected object data");
        assert_eq!(object["text"], json!("hello"));
    }

    #[test]
    fn inspect_json_target_config_reports_configured_status() {
        let temp_dir = std::env::temp_dir().join("deckclip-mcp-doctor-json-configured");
        let file_path = temp_dir.join("cursor-mcp.json");
        let _ = fs::remove_dir_all(&temp_dir);

        ensure_parent_dir(&file_path).unwrap();
        fs::write(
            &file_path,
            serde_json::to_string_pretty(&json!({
                "mcpServers": {
                    "deck": {
                        "command": "deckclip",
                        "args": ["mcp", "serve"],
                    }
                }
            }))
            .unwrap(),
        )
        .unwrap();

        let inspection = inspect_json_target_config(&file_path, "mcpServers");
        assert!(inspection.file_exists);
        assert!(inspection.configured);
        assert_eq!(inspection.status, i18n::t("mcp.doctor.target.configured"));

        let _ = fs::remove_dir_all(&temp_dir);
    }

    #[test]
    fn inspect_json_target_config_reports_missing_entry() {
        let temp_dir = std::env::temp_dir().join("deckclip-mcp-doctor-json-missing");
        let file_path = temp_dir.join("cursor-mcp.json");
        let _ = fs::remove_dir_all(&temp_dir);

        ensure_parent_dir(&file_path).unwrap();
        fs::write(&file_path, "{\n  \"mcpServers\": {}\n}\n").unwrap();

        let inspection = inspect_json_target_config(&file_path, "mcpServers");
        assert!(inspection.file_exists);
        assert!(!inspection.configured);
        assert_eq!(
            inspection.status,
            i18n::t("mcp.doctor.target.not_configured")
        );

        let _ = fs::remove_dir_all(&temp_dir);
    }

    #[test]
    fn inspect_text_target_config_reports_configured_status() {
        let temp_dir = std::env::temp_dir().join("deckclip-mcp-doctor-text-configured");
        let file_path = temp_dir.join("config.toml");
        let _ = fs::remove_dir_all(&temp_dir);

        ensure_parent_dir(&file_path).unwrap();
        fs::write(
            &file_path,
            "[mcp_servers.deck]\ncommand = \"deckclip\"\nargs = [\"mcp\", \"serve\"]\n",
        )
        .unwrap();

        let inspection = inspect_text_target_config(&file_path, "[mcp_servers.deck]");
        assert!(inspection.file_exists);
        assert!(inspection.configured);
        assert_eq!(inspection.status, i18n::t("mcp.doctor.target.configured"));

        let _ = fs::remove_dir_all(&temp_dir);
    }
}
