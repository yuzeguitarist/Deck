use std::borrow::Cow;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{anyhow, bail, Result};
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
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::cli::{McpAction, McpCommand, McpSetupArgs, McpSetupClient};
use crate::i18n;
use crate::output::{render_error_message, OutputMode};

const MCP_SERVER_KEY: &str = "deck";
const OPENCODE_SCHEMA_URL: &str = "https://opencode.ai/config.json";

const TOOL_READ_LATEST: &str = "deck_read_latest_clipboard";
const TOOL_WRITE_TEXT: &str = "deck_write_clipboard_text";
const TOOL_SEARCH_HISTORY: &str = "deck_search_clipboard_history";
const TOOL_TRANSFORM_TEXT: &str = "deck_transform_clipboard_text";

pub async fn run(command: McpCommand, output: OutputMode) -> Result<()> {
    match command.action {
        McpAction::Serve => serve().await,
        McpAction::Tools => run_tools(output),
        McpAction::Doctor => run_doctor(output).await,
        McpAction::Setup(args) => run_setup(args, output),
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

fn run_setup(args: McpSetupArgs, output: OutputMode) -> Result<()> {
    if args.write && args.client == McpSetupClient::All {
        bail!("{}", i18n::t("err.mcp_setup_write_requires_single_client"));
    }

    if args.path.is_some() && args.client == McpSetupClient::All {
        bail!("{}", i18n::t("err.mcp_setup_path_requires_single_client"));
    }

    let command = resolve_command(args.command.as_deref());
    let clients = selected_clients(args.client);
    let mut entries = Vec::with_capacity(clients.len());

    for client in clients {
        let plan = build_setup_plan(client, args.path.as_deref(), &command)?;
        let mode = if args.write {
            match write_setup_plan(&plan)? {
                SetupWriteOutcome::Written => SetupMode::Written,
                SetupWriteOutcome::AlreadyPresent => SetupMode::AlreadyPresent,
            }
        } else {
            SetupMode::Preview
        };

        entries.push(plan.into_output(mode, &command));
    }

    let json_output = serde_json::to_value(&entries)?;
    output.print_data(&render_setup_entries(&entries), &json_output);
    Ok(())
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
        lines.push(format!("  {}: {}", target.client, target.path));
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
            TOOL_READ_LATEST,
            "mcp.tools.read_latest.description",
            "mcp.tools.read_latest.input",
            true,
        ),
        ToolDescriptor::new(
            TOOL_WRITE_TEXT,
            "mcp.tools.write_text.description",
            "mcp.tools.write_text.input",
            false,
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
    ]
}

fn server_instructions() -> String {
    i18n::t("mcp.server.instructions")
}

fn tool_title_key(name: &str) -> Option<&'static str> {
    match name {
        TOOL_READ_LATEST => Some("mcp.tool.read_latest.title"),
        TOOL_WRITE_TEXT => Some("mcp.tool.write_text.title"),
        TOOL_SEARCH_HISTORY => Some("mcp.tool.search_history.title"),
        TOOL_TRANSFORM_TEXT => Some("mcp.tool.transform_text.title"),
        _ => None,
    }
}

fn tool_description_key(name: &str) -> Option<&'static str> {
    match name {
        TOOL_READ_LATEST => Some("mcp.tools.read_latest.description"),
        TOOL_WRITE_TEXT => Some("mcp.tools.write_text.description"),
        TOOL_SEARCH_HISTORY => Some("mcp.tools.search_history.description"),
        TOOL_TRANSFORM_TEXT => Some("mcp.tools.transform_text.description"),
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
                    "mcp.setup.note.cursor_project",
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
            let snippet = serde_json::to_string_pretty(&opencode_snippet(command))?;

            Ok(SetupPlan {
                client_label_key: "mcp.client.opencode",
                path,
                snippet,
                note_keys: vec!["mcp.setup.note.preview_only"],
                kind: SetupPlanKind::PreviewOnly,
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
        SetupPlanKind::PreviewOnly => bail!(
            "{}",
            format_i18n(
                "err.mcp_setup_write_unsupported",
                &[&i18n::t(plan.client_label_key)]
            )
        ),
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
    fs::write(path, rendered)?;
    Ok(SetupWriteOutcome::Written)
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
    fs::write(path, rendered)?;
    Ok(SetupWriteOutcome::Written)
}

fn ensure_parent_dir(path: &Path) -> Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    Ok(())
}

fn default_target_path(client: McpSetupClient) -> Result<PathBuf> {
    match client {
        McpSetupClient::ClaudeDesktop => home_dir()
            .map(|home| {
                home.join("Library/Application Support/Claude")
                    .join("claude_desktop_config.json")
            })
            .ok_or_else(|| anyhow!(i18n::t("err.mcp_home_unavailable"))),
        McpSetupClient::Cursor => Ok(env::current_dir()
            .unwrap_or_else(|_| PathBuf::from("."))
            .join(".cursor/mcp.json")),
        McpSetupClient::Codex => home_dir()
            .map(|home| home.join(".codex/config.toml"))
            .ok_or_else(|| anyhow!(i18n::t("err.mcp_home_unavailable"))),
        McpSetupClient::Opencode => home_dir()
            .map(|home| home.join(".config/opencode/opencode.jsonc"))
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
    mcp.insert(
        MCP_SERVER_KEY.to_string(),
        json!({
            "type": "local",
            "command": [command, "mcp", "serve"],
            "enabled": true,
        }),
    );

    root.insert("mcp".to_string(), Value::Object(mcp));
    Value::Object(root)
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
        data: response.data,
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
        name = "deck_read_latest_clipboard",
        description = "Read the latest clipboard item from Deck.",
        annotations(read_only_hint = true)
    )]
    pub async fn read_latest_clipboard(&self) -> Result<Json<ToolPayload>, ErrorData> {
        let mut client = self.client.lock().await;
        let response = client
            .read()
            .await
            .map_err(|err| tool_error(anyhow::Error::new(err)))?;
        Ok(Json(response_payload(TOOL_READ_LATEST, response)))
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

fn default_search_limit() -> u32 {
    10
}

#[derive(Debug, Serialize, JsonSchema)]
struct ToolPayload {
    tool: String,
    text: Option<String>,
    data: Option<Value>,
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
}

impl DoctorTarget {
    fn new(client: McpSetupClient) -> Self {
        let key = match client {
            McpSetupClient::ClaudeDesktop => "mcp.client.claude_desktop",
            McpSetupClient::Cursor => "mcp.client.cursor",
            McpSetupClient::Codex => "mcp.client.codex",
            McpSetupClient::Opencode => "mcp.client.opencode",
            McpSetupClient::All => unreachable!(),
        };

        let path = default_target_path(client)
            .map(path_to_string)
            .unwrap_or_else(|_| i18n::t("mcp.common.unavailable"));

        Self {
            client: i18n::t(key),
            path,
        }
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
    fn into_output(self, mode: SetupMode, command: &str) -> SetupEntry {
        SetupEntry {
            client: i18n::t(self.client_label_key),
            mode: i18n::t(mode.key()),
            path: path_to_string(self.path),
            command: command.to_string(),
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
    PreviewOnly,
}

enum SetupWriteOutcome {
    Written,
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
    snippet: String,
    notes: Vec<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn localized_tool_catalog_uses_i18n_metadata() {
        let tools = localized_tool_catalog();
        let read_latest = tools
            .into_iter()
            .find(|tool| tool.name.as_ref() == TOOL_READ_LATEST)
            .expect("expected localized read_latest tool");

        assert_eq!(
            read_latest.title.as_deref(),
            Some(i18n::t("mcp.tool.read_latest.title").as_str())
        );
        assert_eq!(
            read_latest.description.as_deref(),
            Some(i18n::t("mcp.tools.read_latest.description").as_str())
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

        assert!(matches!(outcome, SetupWriteOutcome::Written));

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
        assert!(matches!(outcome, SetupWriteOutcome::Written));

        let second = write_codex_config(&file_path, &snippet).unwrap();
        assert!(matches!(second, SetupWriteOutcome::AlreadyPresent));

        let content = fs::read_to_string(&file_path).unwrap();
        assert!(content.contains("[mcp_servers.deck]"));

        let _ = fs::remove_dir_all(&temp_dir);
    }
}
