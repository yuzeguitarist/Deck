use std::collections::HashMap;
use std::io::{self, stdout, IsTerminal, Stdout, Write};
use std::time::Duration;

use anyhow::{anyhow, bail, Context, Result};
use crossterm::cursor::{Hide, MoveTo, Show};
use crossterm::event::{self, Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers};
use crossterm::execute;
use crossterm::queue;
use crossterm::terminal::{
    disable_raw_mode, enable_raw_mode, size, Clear, ClearType, EnterAlternateScreen,
    LeaveAlternateScreen,
};
use deckclip_core::{Config, DeckClient};
use owo_colors::OwoColorize;
use serde::Deserialize;
use textwrap::Options;
use tokio::sync::mpsc::{unbounded_channel, UnboundedReceiver, UnboundedSender};

use crate::output::OutputMode;

const LOGO: &str = include_str!("../logo.ans");

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ProviderKind {
    ChatGpt,
    OpenAI,
    Anthropic,
    Ollama,
}

impl ProviderKind {
    const ALL: [ProviderKind; 4] = [
        ProviderKind::ChatGpt,
        ProviderKind::OpenAI,
        ProviderKind::Anthropic,
        ProviderKind::Ollama,
    ];

    fn from_index(index: usize) -> Self {
        Self::ALL[index]
    }

    fn index(self) -> usize {
        match self {
            ProviderKind::ChatGpt => 0,
            ProviderKind::OpenAI => 1,
            ProviderKind::Anthropic => 2,
            ProviderKind::Ollama => 3,
        }
    }

    fn id(self) -> &'static str {
        match self {
            ProviderKind::ChatGpt => "chatgpt",
            ProviderKind::OpenAI => "openai_api",
            ProviderKind::Anthropic => "anthropic",
            ProviderKind::Ollama => "ollama",
        }
    }

    fn title(self) -> &'static str {
        match self {
            ProviderKind::ChatGpt => "Sign in with ChatGPT",
            ProviderKind::OpenAI => "Provide your own OpenAI API key",
            ProviderKind::Anthropic => "Provide your own Anthropic API key",
            ProviderKind::Ollama => "Use Ollama",
        }
    }

    fn description(self, status: &ProviderStatus) -> String {
        let mut text = match self {
            ProviderKind::ChatGpt => {
                if let Some(account) = status.account.as_deref() {
                    format!("Usage included with your ChatGPT plan. Current account: {account}")
                } else {
                    "Usage included with your ChatGPT plan".to_string()
                }
            }
            ProviderKind::OpenAI => "通过 OpenAI API key 进行模型调用".to_string(),
            ProviderKind::Anthropic => "通过 Anthropic API key 进行模型调用".to_string(),
            ProviderKind::Ollama => "使用本地模型".to_string(),
        };

        if status.selected {
            text.push_str("  [当前使用]");
        } else if status.configured {
            text.push_str("  [已配置]");
        }

        text
    }

    fn base_url_placeholder(self) -> Option<&'static str> {
        match self {
            ProviderKind::OpenAI => Some("https://api.openai.com/v1"),
            ProviderKind::Anthropic => Some("https://api.anthropic.com/v1"),
            ProviderKind::Ollama => Some("http://localhost:11434"),
            ProviderKind::ChatGpt => None,
        }
    }

    fn model_placeholder(self) -> Option<&'static str> {
        match self {
            ProviderKind::OpenAI => Some("gpt-5.3"),
            ProviderKind::Anthropic => Some("claude-sonnet-4-6"),
            ProviderKind::Ollama => Some("llama3.3"),
            ProviderKind::ChatGpt => None,
        }
    }

    fn success_title(self) -> &'static str {
        match self {
            ProviderKind::ChatGpt => "ChatGPT 登录成功",
            ProviderKind::OpenAI => "OpenAI API 已配置",
            ProviderKind::Anthropic => "Anthropic API 已配置",
            ProviderKind::Ollama => "Ollama 已配置",
        }
    }
}

#[derive(Debug, Clone, Default, Deserialize)]
struct ProviderStatus {
    #[serde(default)]
    configured: bool,
    #[serde(default)]
    selected: bool,
    #[serde(default)]
    account: Option<String>,
    #[serde(default)]
    base_url: Option<String>,
    #[serde(default)]
    model: Option<String>,
}

#[derive(Debug, Clone, Default, Deserialize)]
struct LoginStatusData {
    #[serde(default)]
    providers: HashMap<String, ProviderStatus>,
}

impl LoginStatusData {
    fn provider(&self, provider: ProviderKind) -> ProviderStatus {
        self.providers
            .get(provider.id())
            .cloned()
            .unwrap_or_default()
    }
}

#[derive(Debug, Clone)]
struct InputField {
    label: &'static str,
    placeholder: &'static str,
    value: String,
    secret: bool,
}

#[derive(Debug, Clone)]
struct FormState {
    provider: ProviderKind,
    fields: Vec<InputField>,
    focus: usize,
    error: Option<String>,
}

impl FormState {
    fn new(provider: ProviderKind, status: &ProviderStatus) -> Self {
        let base_url = status
            .base_url
            .clone()
            .filter(|value| !value.trim().is_empty())
            .unwrap_or_else(|| {
                provider
                    .base_url_placeholder()
                    .unwrap_or_default()
                    .to_string()
            });
        let model = status
            .model
            .clone()
            .filter(|value| !value.trim().is_empty())
            .unwrap_or_else(|| provider.model_placeholder().unwrap_or_default().to_string());

        let fields = match provider {
            ProviderKind::OpenAI | ProviderKind::Anthropic => vec![
                InputField {
                    label: "Base URL",
                    placeholder: provider.base_url_placeholder().unwrap_or_default(),
                    value: base_url,
                    secret: false,
                },
                InputField {
                    label: "API Key",
                    placeholder: "在这里输入 API Key",
                    value: String::new(),
                    secret: true,
                },
                InputField {
                    label: "Model",
                    placeholder: provider.model_placeholder().unwrap_or_default(),
                    value: model,
                    secret: false,
                },
            ],
            ProviderKind::Ollama => vec![
                InputField {
                    label: "Base URL",
                    placeholder: provider.base_url_placeholder().unwrap_or_default(),
                    value: base_url,
                    secret: false,
                },
                InputField {
                    label: "Model",
                    placeholder: provider.model_placeholder().unwrap_or_default(),
                    value: model,
                    secret: false,
                },
            ],
            ProviderKind::ChatGpt => Vec::new(),
        };

        Self {
            provider,
            fields,
            focus: 0,
            error: None,
        }
    }

    fn focused_mut(&mut self) -> Option<&mut InputField> {
        self.fields.get_mut(self.focus)
    }

    fn move_focus(&mut self, delta: isize) {
        if self.fields.is_empty() {
            return;
        }
        let len = self.fields.len() as isize;
        self.focus = (self.focus as isize + delta).rem_euclid(len) as usize;
    }

    fn values(&self) -> Vec<String> {
        self.fields
            .iter()
            .map(|field| field.value.trim().to_string())
            .collect()
    }
}

#[derive(Debug, Clone)]
enum Screen {
    Menu {
        selected: usize,
        info: Option<String>,
    },
    ConfirmOverwrite {
        provider: ProviderKind,
        yes_selected: bool,
    },
    Form(FormState),
    ChatGptWaiting {
        auth_url: Option<String>,
        browser_opened: bool,
    },
    Result {
        success: bool,
        title: String,
        detail: Option<String>,
    },
}

#[derive(Debug)]
enum AsyncEvent {
    ChatGptStarted {
        request_id: u64,
        auth_url: Option<String>,
        browser_opened: bool,
    },
    ChatGptFinished {
        request_id: u64,
        result: Result<String, String>,
    },
}

struct LoginApp {
    status: LoginStatusData,
    screen: Screen,
    events_tx: UnboundedSender<AsyncEvent>,
    events_rx: UnboundedReceiver<AsyncEvent>,
    next_request_id: u64,
    active_chatgpt_request_id: Option<u64>,
}

impl LoginApp {
    fn new(status: LoginStatusData) -> Self {
        let (events_tx, events_rx) = unbounded_channel();
        Self {
            status,
            screen: Screen::Menu {
                selected: 0,
                info: None,
            },
            events_tx,
            events_rx,
            next_request_id: 1,
            active_chatgpt_request_id: None,
        }
    }

    async fn drain_async_events(&mut self) -> Result<()> {
        while let Ok(event) = self.events_rx.try_recv() {
            match event {
                AsyncEvent::ChatGptStarted {
                    request_id,
                    auth_url,
                    browser_opened,
                } => {
                    if self.active_chatgpt_request_id != Some(request_id) {
                        continue;
                    }

                    self.screen = Screen::ChatGptWaiting {
                        auth_url,
                        browser_opened,
                    };
                }
                AsyncEvent::ChatGptFinished { request_id, result } => {
                    if self.active_chatgpt_request_id != Some(request_id) {
                        continue;
                    }

                    self.active_chatgpt_request_id = None;
                    match result {
                        Ok(detail) => {
                            self.status = fetch_login_status().await?;
                            self.screen = Screen::Result {
                                success: true,
                                title: ProviderKind::ChatGpt.success_title().to_string(),
                                detail: Some(detail),
                            };
                        }
                        Err(error) => {
                            self.screen = Screen::Result {
                                success: false,
                                title: "ChatGPT 登录失败".to_string(),
                                detail: Some(error),
                            };
                        }
                    }
                }
            }
        }

        Ok(())
    }

    async fn handle_key_event(&mut self, key: KeyEvent) -> Result<bool> {
        if matches!(key.kind, KeyEventKind::Release) {
            return Ok(false);
        }

        if key.code == KeyCode::Char('c') && key.modifiers.contains(KeyModifiers::CONTROL) {
            if matches!(self.screen, Screen::ChatGptWaiting { .. }) {
                let _ = cancel_chatgpt_login().await;
                self.active_chatgpt_request_id = None;
            }
            return Ok(true);
        }

        enum PostAction {
            None,
            SelectProvider,
            ClearAndContinue(ProviderKind),
            SubmitForm,
            CancelChatGptAndExit,
        }

        let mut should_exit = false;
        let mut post_action = PostAction::None;

        match &mut self.screen {
            Screen::Menu { selected, info } => match key.code {
                KeyCode::Esc => should_exit = true,
                KeyCode::Up | KeyCode::Char('k') => {
                    *selected = selected.saturating_sub(1);
                }
                KeyCode::Down | KeyCode::Char('j') => {
                    *selected = (*selected + 1).min(ProviderKind::ALL.len().saturating_sub(1));
                }
                KeyCode::Char(c) if ('1'..='4').contains(&c) => {
                    *selected = (c as u8 - b'1') as usize;
                    *info = None;
                    post_action = PostAction::SelectProvider;
                }
                KeyCode::Enter => {
                    *info = None;
                    post_action = PostAction::SelectProvider;
                }
                _ => {}
            },
            Screen::ConfirmOverwrite {
                provider,
                yes_selected,
            } => match key.code {
                KeyCode::Esc => should_exit = true,
                KeyCode::Left
                | KeyCode::Right
                | KeyCode::Tab
                | KeyCode::Up
                | KeyCode::Down
                | KeyCode::Char('h')
                | KeyCode::Char('l') => {
                    *yes_selected = !*yes_selected;
                }
                KeyCode::Enter => {
                    if *yes_selected {
                        post_action = PostAction::ClearAndContinue(*provider);
                    } else {
                        self.screen = Screen::Menu {
                            selected: provider.index(),
                            info: None,
                        };
                    }
                }
                _ => {}
            },
            Screen::Form(form) => match key.code {
                KeyCode::Esc => should_exit = true,
                KeyCode::Tab | KeyCode::Down => {
                    form.move_focus(1);
                }
                KeyCode::BackTab | KeyCode::Up => {
                    form.move_focus(-1);
                }
                KeyCode::Backspace => {
                    if let Some(field) = form.focused_mut() {
                        field.value.pop();
                        form.error = None;
                    }
                }
                KeyCode::Enter => {
                    post_action = PostAction::SubmitForm;
                }
                KeyCode::Char(c)
                    if !key.modifiers.contains(KeyModifiers::CONTROL)
                        && !key.modifiers.contains(KeyModifiers::ALT)
                        && !key.modifiers.contains(KeyModifiers::SUPER) =>
                {
                    if let Some(field) = form.focused_mut() {
                        field.value.push(c);
                        form.error = None;
                    }
                }
                _ => {}
            },
            Screen::ChatGptWaiting { .. } => {
                if key.code == KeyCode::Esc {
                    post_action = PostAction::CancelChatGptAndExit;
                }
            }
            Screen::Result { .. } => match key.code {
                KeyCode::Enter | KeyCode::Esc => should_exit = true,
                _ => {}
            },
        }

        match post_action {
            PostAction::None => {}
            PostAction::SelectProvider => self.select_provider().await?,
            PostAction::ClearAndContinue(provider) => {
                self.clear_provider(provider).await?;
                if provider == ProviderKind::ChatGpt {
                    self.start_chatgpt_login();
                } else {
                    let status = self.status.provider(provider);
                    self.screen = Screen::Form(FormState::new(provider, &status));
                }
            }
            PostAction::SubmitForm => self.submit_form().await?,
            PostAction::CancelChatGptAndExit => {
                let _ = cancel_chatgpt_login().await;
                self.active_chatgpt_request_id = None;
                should_exit = true;
            }
        }

        Ok(should_exit)
    }

    fn handle_paste(&mut self, pasted: String) {
        if let Screen::Form(form) = &mut self.screen {
            if let Some(field) = form.focused_mut() {
                field.value.push_str(&pasted);
                form.error = None;
            }
        }
    }

    async fn select_provider(&mut self) -> Result<()> {
        let selected = match &self.screen {
            Screen::Menu { selected, .. } => *selected,
            _ => return Ok(()),
        };
        let provider = ProviderKind::from_index(selected);
        let status = self.status.provider(provider);

        if status.configured {
            self.screen = Screen::ConfirmOverwrite {
                provider,
                yes_selected: false,
            };
            return Ok(());
        }

        if provider == ProviderKind::ChatGpt {
            self.start_chatgpt_login();
        } else {
            self.screen = Screen::Form(FormState::new(provider, &status));
        }

        Ok(())
    }

    async fn clear_provider(&mut self, provider: ProviderKind) -> Result<()> {
        let mut client = DeckClient::new(Config::default());
        client
            .login_clear(provider.id())
            .await
            .with_context(|| format!("无法清空 {} 配置", provider.id()))?;
        self.status = fetch_login_status().await?;
        Ok(())
    }

    fn start_chatgpt_login(&mut self) {
        let request_id = self.next_request_id;
        self.next_request_id += 1;
        self.active_chatgpt_request_id = Some(request_id);

        let tx = self.events_tx.clone();
        tokio::spawn(async move {
            let mut client = DeckClient::new(Config::default());
            let result = match client.login_chatgpt_start().await {
                Ok(response) => {
                    let _ = tx.send(AsyncEvent::ChatGptStarted {
                        request_id,
                        auth_url: response_auth_url(&response),
                        browser_opened: response_browser_opened(&response),
                    });

                    match client.login_chatgpt_wait().await {
                        Ok(response) => {
                            Ok(response_detail_message(&response).unwrap_or_else(|| {
                                "浏览器授权已完成，Deck 已切换到 ChatGPT。".to_string()
                            }))
                        }
                        Err(error) => Err(error.to_string()),
                    }
                }
                Err(error) => Err(error.to_string()),
            };
            let _ = tx.send(AsyncEvent::ChatGptFinished { request_id, result });
        });

        self.screen = Screen::ChatGptWaiting {
            auth_url: None,
            browser_opened: true,
        };
    }

    async fn submit_form(&mut self) -> Result<()> {
        let Screen::Form(form) = &mut self.screen else {
            return Ok(());
        };

        let provider = form.provider;
        let values = form.values();
        let validation_error = match provider {
            ProviderKind::OpenAI | ProviderKind::Anthropic => {
                if values.get(0).is_none_or(|value| value.is_empty()) {
                    Some("Base URL 不能为空".to_string())
                } else if values.get(1).is_none_or(|value| value.is_empty()) {
                    Some("API Key 不能为空".to_string())
                } else if values.get(2).is_none_or(|value| value.is_empty()) {
                    Some("Model 不能为空".to_string())
                } else {
                    None
                }
            }
            ProviderKind::Ollama => {
                if values.get(0).is_none_or(|value| value.is_empty()) {
                    Some("Base URL 不能为空".to_string())
                } else if values.get(1).is_none_or(|value| value.is_empty()) {
                    Some("Model 不能为空".to_string())
                } else {
                    None
                }
            }
            ProviderKind::ChatGpt => None,
        };

        if let Some(error) = validation_error {
            form.error = Some(error);
            return Ok(());
        }

        let mut client = DeckClient::new(Config::default());
        let result = match provider {
            ProviderKind::OpenAI => {
                client
                    .login_openai_configure(&values[0], &values[2], &values[1])
                    .await
            }
            ProviderKind::Anthropic => {
                client
                    .login_anthropic_configure(&values[0], &values[2], &values[1])
                    .await
            }
            ProviderKind::Ollama => client.login_ollama_configure(&values[0], &values[1]).await,
            ProviderKind::ChatGpt => unreachable!("ChatGPT does not use a local form"),
        };

        match result {
            Ok(response) => {
                self.status = fetch_login_status().await?;
                self.screen = Screen::Result {
                    success: true,
                    title: provider.success_title().to_string(),
                    detail: response_detail_message(&response),
                };
            }
            Err(error) => {
                if let Screen::Form(form) = &mut self.screen {
                    form.error = Some(error.to_string());
                }
            }
        }

        Ok(())
    }
}

struct TerminalGuard {
    stdout: Stdout,
}

#[derive(Debug, Clone, Copy)]
struct RenderLayout {
    terminal_height: u16,
    content_width: usize,
    left_pad: u16,
    show_logo: bool,
}

struct ScreenWriter<'a> {
    stdout: &'a mut Stdout,
    layout: RenderLayout,
    row: u16,
}

impl RenderLayout {
    fn detect() -> Self {
        let (width, height) = size().unwrap_or((80, 24));
        let terminal_width = width.max(1) as usize;
        let terminal_height = height.max(1);

        let content_width = terminal_width.saturating_sub(1).max(1);
        let left_pad = 0;

        let show_logo = terminal_width >= 50;

        Self {
            terminal_height,
            content_width,
            left_pad,
            show_logo,
        }
    }
}

impl<'a> ScreenWriter<'a> {
    fn new(stdout: &'a mut Stdout, layout: RenderLayout) -> Self {
        Self {
            stdout,
            layout,
            row: 0,
        }
    }

    fn blank_line(&mut self) {
        self.row = self.row.saturating_add(1);
    }

    fn write_logo(&mut self) -> Result<()> {
        for line in LOGO.lines() {
            if self.row >= self.layout.terminal_height {
                break;
            }
            queue!(self.stdout, MoveTo(0, self.row))?;
            write!(self.stdout, "{line}")?;
            self.row = self.row.saturating_add(1);
        }
        Ok(())
    }

    fn write_padded_line(&mut self, line: &str) -> Result<()> {
        self.write_line(self.layout.left_pad, line)
    }

    fn write_line(&mut self, column: u16, line: &str) -> Result<()> {
        if self.row >= self.layout.terminal_height {
            return Ok(());
        }

        queue!(self.stdout, MoveTo(column, self.row))?;
        write!(self.stdout, "{line}")?;
        self.row = self.row.saturating_add(1);
        Ok(())
    }

    fn write_wrapped(
        &mut self,
        initial_indent: &str,
        subsequent_indent: &str,
        text: &str,
        style: LineStyle,
    ) -> Result<()> {
        let options = Options::new(self.layout.content_width)
            .initial_indent(initial_indent)
            .subsequent_indent(subsequent_indent)
            .break_words(true)
            .word_splitter(textwrap::WordSplitter::NoHyphenation);

        for line in textwrap::wrap(text, &options) {
            let rendered = apply_line_style(style, line.as_ref());
            self.write_padded_line(&rendered)?;
        }

        Ok(())
    }
}

impl TerminalGuard {
    fn enter() -> Result<Self> {
        enable_raw_mode().context("无法进入终端 raw mode")?;
        let mut stdout = stdout();
        execute!(stdout, EnterAlternateScreen, Hide).context("无法进入终端登录界面")?;
        Ok(Self { stdout })
    }

    fn render(&mut self, app: &LoginApp) -> Result<()> {
        let layout = RenderLayout::detect();
        queue!(self.stdout, MoveTo(0, 0), Clear(ClearType::All))?;

        let mut screen = ScreenWriter::new(&mut self.stdout, layout);

        if layout.show_logo {
            screen.write_logo()?;
            screen.blank_line();
        }

        match &app.screen {
            Screen::Menu { selected, info } => {
                render_menu(&mut screen, &app.status, *selected, info.as_deref())?
            }
            Screen::ConfirmOverwrite {
                provider,
                yes_selected,
            } => render_confirm(&mut screen, *provider, *yes_selected)?,
            Screen::Form(form) => render_form(&mut screen, form)?,
            Screen::ChatGptWaiting {
                auth_url,
                browser_opened,
            } => render_chatgpt_waiting(&mut screen, auth_url.as_deref(), *browser_opened)?,
            Screen::Result {
                success,
                title,
                detail,
            } => render_result(&mut screen, *success, title, detail.as_deref())?,
        }

        self.stdout.flush()?;
        Ok(())
    }
}

impl Drop for TerminalGuard {
    fn drop(&mut self) {
        let _ = execute!(self.stdout, Show, LeaveAlternateScreen);
        let _ = disable_raw_mode();
    }
}

fn render_menu(
    screen: &mut ScreenWriter<'_>,
    status: &LoginStatusData,
    selected: usize,
    info: Option<&str>,
) -> Result<()> {
    screen.write_wrapped("", "", "配置 Deck AI 提供商", LineStyle::Bold)?;
    screen.write_wrapped(
        "",
        "",
        "为 Deck 选择或重新配置 AI 提供商。",
        LineStyle::Plain,
    )?;
    screen.blank_line();

    for (index, provider) in ProviderKind::ALL.iter().enumerate() {
        let provider_status = status.provider(*provider);
        let title_prefix = if index == selected {
            format!("> {}. ", index + 1)
        } else {
            format!("  {}. ", index + 1)
        };
        let description_prefix = "     ";
        let title_style = if index == selected {
            LineStyle::Cyan
        } else {
            LineStyle::Plain
        };
        let description_style = if index == selected {
            LineStyle::CyanDim
        } else {
            LineStyle::Dim
        };

        screen.write_wrapped(
            &title_prefix,
            description_prefix,
            provider.title(),
            title_style,
        )?;
        screen.write_wrapped(
            description_prefix,
            description_prefix,
            &provider.description(&provider_status),
            description_style,
        )?;
        screen.blank_line();
    }

    screen.write_wrapped(
        "",
        "",
        "Press Enter to continue, or ESC to exit",
        LineStyle::Dim,
    )?;
    if let Some(info) = info {
        screen.blank_line();
        screen.write_wrapped("", "", info, LineStyle::Cyan)?;
    }
    Ok(())
}

fn render_confirm(
    screen: &mut ScreenWriter<'_>,
    provider: ProviderKind,
    yes_selected: bool,
) -> Result<()> {
    screen.write_wrapped("", "", "检测到已有配置，请问是否要继续？", LineStyle::Bold)?;
    screen.write_wrapped(
        "",
        "",
        &format!(
            "继续后会清空当前 {} 配置，并重新开始设置。",
            provider.title()
        ),
        LineStyle::Plain,
    )?;
    screen.blank_line();

    let no_button = if yes_selected {
        "[ No ]".to_string()
    } else {
        format!("{}", "[ No ]".cyan().bold())
    };
    let yes_button = if yes_selected {
        format!("{}", "[ Yes ]".cyan().bold())
    } else {
        "[ Yes ]".to_string()
    };

    screen.write_padded_line(&format!("  {no_button}  {yes_button}"))?;
    screen.blank_line();
    screen.write_wrapped(
        "",
        "",
        "Press Enter to continue, or ESC to exit",
        LineStyle::Dim,
    )?;
    Ok(())
}

fn render_form(screen: &mut ScreenWriter<'_>, form: &FormState) -> Result<()> {
    screen.write_wrapped("", "", form.provider.title(), LineStyle::Bold)?;
    screen.write_wrapped(
        "",
        "",
        "填写下列信息后，Deck 会立即切换到对应提供商。",
        LineStyle::Plain,
    )?;
    screen.blank_line();

    for (index, field) in form.fields.iter().enumerate() {
        let selected = index == form.focus;
        let label_prefix = if selected { "> " } else { "  " };
        let value = if field.value.is_empty() {
            format!("<{}>", field.placeholder).dimmed().to_string()
        } else if field.secret {
            "•".repeat(field.value.chars().count())
        } else {
            field.value.clone()
        };

        screen.write_wrapped(
            label_prefix,
            "  ",
            field.label,
            if selected {
                LineStyle::Cyan
            } else {
                LineStyle::Plain
            },
        )?;
        screen.write_wrapped(
            "    ",
            "    ",
            &value,
            if selected {
                LineStyle::Cyan
            } else if field.value.is_empty() {
                LineStyle::Dim
            } else {
                LineStyle::Plain
            },
        )?;
        screen.blank_line();
    }

    screen.write_wrapped(
        "",
        "",
        "Press Tab to switch fields, Enter to save, or ESC to exit",
        LineStyle::Dim,
    )?;
    if let Some(error) = &form.error {
        screen.blank_line();
        screen.write_wrapped("", "", error, LineStyle::Red)?;
    }
    Ok(())
}

fn render_chatgpt_waiting(
    screen: &mut ScreenWriter<'_>,
    auth_url: Option<&str>,
    browser_opened: bool,
) -> Result<()> {
    screen.write_wrapped("", "", "Sign in with ChatGPT", LineStyle::Bold)?;
    screen.write_wrapped(
        "",
        "",
        "Finish signing in via your browser.",
        LineStyle::Plain,
    )?;
    screen.write_wrapped(
        "",
        "",
        "完成后 Deck 会自动切换到 ChatGPT。",
        LineStyle::Plain,
    )?;
    if let Some(auth_url) = auth_url.filter(|value| !value.trim().is_empty()) {
        screen.blank_line();
        screen.write_wrapped(
            "  ",
            "  ",
            "If the link doesn't open automatically, open the following link to authenticate:",
            LineStyle::Plain,
        )?;
        screen.blank_line();
        screen.write_wrapped("  ", "  ", auth_url, LineStyle::CyanUnderline)?;
    }
    if !browser_opened {
        screen.blank_line();
        screen.write_wrapped(
            "  ",
            "  ",
            "Unable to open the browser automatically. Copy the link above to continue.",
            LineStyle::Dim,
        )?;
    }
    screen.blank_line();
    screen.write_wrapped("", "", "Press ESC to cancel and exit", LineStyle::Dim)?;
    Ok(())
}

fn render_result(
    screen: &mut ScreenWriter<'_>,
    success: bool,
    title: &str,
    detail: Option<&str>,
) -> Result<()> {
    let icon = if success { "✓" } else { "!" };

    screen.write_wrapped(
        "",
        "",
        &format!("{icon} {title}"),
        if success {
            LineStyle::GreenBold
        } else {
            LineStyle::RedBold
        },
    )?;
    if let Some(detail) = detail.filter(|text| !text.trim().is_empty()) {
        screen.blank_line();
        screen.write_wrapped("", "", detail, LineStyle::Plain)?;
    }
    screen.blank_line();
    screen.write_wrapped(
        "",
        "",
        "Press Enter to continue, or ESC to exit",
        LineStyle::Dim,
    )?;
    Ok(())
}

#[derive(Clone, Copy)]
enum LineStyle {
    Plain,
    Bold,
    Dim,
    Cyan,
    CyanUnderline,
    CyanDim,
    Red,
    RedBold,
    GreenBold,
}

fn apply_line_style(style: LineStyle, line: &str) -> String {
    match style {
        LineStyle::Plain => line.to_string(),
        LineStyle::Bold => format!("{}", line.bold()),
        LineStyle::Dim => format!("{}", line.dimmed()),
        LineStyle::Cyan => format!("{}", line.cyan()),
        LineStyle::CyanUnderline => format!("{}", line.cyan().underline()),
        LineStyle::CyanDim => format!("{}", line.cyan().dimmed()),
        LineStyle::Red => format!("{}", line.red()),
        LineStyle::RedBold => format!("{}", line.red().bold()),
        LineStyle::GreenBold => format!("{}", line.green().bold()),
    }
}

pub async fn run(output: OutputMode) -> Result<()> {
    if matches!(output, OutputMode::Json) {
        bail!("`deckclip login` 暂不支持 --json")
    }

    if !io::stdin().is_terminal() || !io::stdout().is_terminal() {
        bail!("`deckclip login` 需要交互式终端")
    }

    let status = fetch_login_status().await?;
    let mut app = LoginApp::new(status);
    let mut terminal = TerminalGuard::enter()?;

    loop {
        app.drain_async_events().await?;
        terminal.render(&app)?;

        if event::poll(Duration::from_millis(50)).context("读取按键事件失败")? {
            match event::read().context("读取终端事件失败")? {
                Event::Key(key) => {
                    if app.handle_key_event(key).await? {
                        break;
                    }
                }
                Event::Paste(text) => app.handle_paste(text),
                Event::Resize(_, _) => {}
                _ => {}
            }
        }
    }

    Ok(())
}

async fn fetch_login_status() -> Result<LoginStatusData> {
    let mut client = DeckClient::new(Config::default());
    let response = client.login_status().await?;
    let data = response
        .data
        .ok_or_else(|| anyhow!("登录状态响应缺少 data 字段"))?;
    serde_json::from_value(data).context("无法解析登录状态响应")
}

async fn cancel_chatgpt_login() -> Result<()> {
    let mut client = DeckClient::new(Config::default());
    let _ = client.login_chatgpt_cancel().await?;
    Ok(())
}

fn response_detail_message(response: &deckclip_protocol::Response) -> Option<String> {
    let data = response.data.as_ref()?;
    if let Some(message) = data.get("message").and_then(|value| value.as_str()) {
        return Some(message.to_string());
    }
    if let Some(account) = data.get("account").and_then(|value| value.as_str()) {
        return Some(format!("当前账号：{account}"));
    }
    if let Some(provider) = data.get("provider").and_then(|value| value.as_str()) {
        return Some(format!("当前提供商：{provider}"));
    }
    None
}

fn response_auth_url(response: &deckclip_protocol::Response) -> Option<String> {
    response
        .data
        .as_ref()
        .and_then(|data| data.get("auth_url"))
        .and_then(|value| value.as_str())
        .map(|value| value.to_string())
}

fn response_browser_opened(response: &deckclip_protocol::Response) -> bool {
    response
        .data
        .as_ref()
        .and_then(|data| data.get("browser_opened"))
        .and_then(|value| value.as_bool())
        .unwrap_or(true)
}
