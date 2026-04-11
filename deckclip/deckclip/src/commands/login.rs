use std::collections::HashMap;
use std::io::{self, stdout, IsTerminal, Stdout, Write};
use std::sync::OnceLock;
use std::time::Duration;
use std::time::Instant;

use anyhow::{anyhow, bail, Context, Result};
use crossterm::cursor::{Hide, MoveTo, Show};
use crossterm::event::{self, Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers};
use crossterm::execute;
use crossterm::queue;
use crossterm::style::{Attribute, Color, Print, ResetColor, SetAttribute, SetForegroundColor};
use crossterm::terminal::{
    disable_raw_mode, enable_raw_mode, size, Clear, ClearType, EnterAlternateScreen,
    LeaveAlternateScreen,
};
use deckclip_core::{Config, DeckClient};
use owo_colors::OwoColorize;
use serde::Deserialize;
use textwrap::Options;
use tokio::sync::mpsc::{unbounded_channel, UnboundedReceiver, UnboundedSender};

use crate::{i18n, output::OutputMode};

const LOGO: &str = include_str!("../logo.ans");
const LOGO_SCALE: f32 = 0.75;

static LOGO_RENDER_START: OnceLock<Instant> = OnceLock::new();
static PARSED_LOGO: OnceLock<Vec<Vec<LogoCell>>> = OnceLock::new();
static RENDERED_LOGO: OnceLock<Vec<Vec<LogoCell>>> = OnceLock::new();

#[derive(Clone, Copy)]
struct RgbColor {
    r: u8,
    g: u8,
    b: u8,
}

#[derive(Clone, Copy)]
struct LogoCell {
    ch: char,
    fg: Option<RgbColor>,
}

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
        provider_title(self)
    }

    fn description(self, status: &ProviderStatus) -> String {
        let mut text = provider_description(self, status);

        if status.selected {
            text.push_str("  ");
            text.push_str(login_text(LoginText::StatusCurrent));
        } else if status.configured {
            text.push_str("  ");
            text.push_str(login_text(LoginText::StatusConfigured));
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
        provider_success_title(self)
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
                    label: login_text(LoginText::FieldBaseUrl),
                    placeholder: provider.base_url_placeholder().unwrap_or_default(),
                    value: base_url,
                    secret: false,
                },
                InputField {
                    label: login_text(LoginText::FieldApiKey),
                    placeholder: login_text(LoginText::PlaceholderApiKey),
                    value: String::new(),
                    secret: true,
                },
                InputField {
                    label: login_text(LoginText::FieldModel),
                    placeholder: provider.model_placeholder().unwrap_or_default(),
                    value: model,
                    secret: false,
                },
            ],
            ProviderKind::Ollama => vec![
                InputField {
                    label: login_text(LoginText::FieldBaseUrl),
                    placeholder: provider.base_url_placeholder().unwrap_or_default(),
                    value: base_url,
                    secret: false,
                },
                InputField {
                    label: login_text(LoginText::FieldModel),
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
                                title: login_text(LoginText::ErrorChatGptFailed).to_string(),
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
            ContinueReplace(ProviderKind),
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
                        post_action = PostAction::ContinueReplace(*provider);
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
            PostAction::ContinueReplace(provider) => {
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
                                login_text(LoginText::ChatGptCompleted).to_string()
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
                    Some(login_text(LoginText::ErrorBaseUrlRequired).to_string())
                } else if values.get(1).is_none_or(|value| value.is_empty()) {
                    Some(login_text(LoginText::ErrorApiKeyRequired).to_string())
                } else if values.get(2).is_none_or(|value| value.is_empty()) {
                    Some(login_text(LoginText::ErrorModelRequired).to_string())
                } else {
                    None
                }
            }
            ProviderKind::Ollama => {
                if values.get(0).is_none_or(|value| value.is_empty()) {
                    Some(login_text(LoginText::ErrorBaseUrlRequired).to_string())
                } else if values.get(1).is_none_or(|value| value.is_empty()) {
                    Some(login_text(LoginText::ErrorModelRequired).to_string())
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
    last_content_signature: Option<String>,
    last_content_start_row: u16,
    last_content_end_row: u16,
    last_logo_rows: u16,
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
    fn new(stdout: &'a mut Stdout, layout: RenderLayout, start_row: u16) -> Self {
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

    fn write_logo(&mut self) -> Result<()> {
        let elapsed = logo_elapsed_seconds();
        let logo = rendered_logo();
        let logo_width = logo.iter().map(|line| line.len()).max().unwrap_or(0);
        let logo_height = logo.len();

        for (line_index, line) in logo.iter().enumerate() {
            if self.row >= self.layout.terminal_height {
                break;
            }
            self.clear_current_line()?;
            queue!(self.stdout, MoveTo(0, self.row))?;

            for (column, cell) in line.iter().enumerate() {
                let intensity =
                    shimmer_intensity(column, line_index, logo_width, logo_height, elapsed);
                match cell.fg {
                    Some(base) if cell.ch != ' ' => {
                        let color = shimmer_color(base, intensity);
                        let attribute = if intensity > 0.28 {
                            Attribute::Bold
                        } else {
                            Attribute::NormalIntensity
                        };
                        queue!(
                            self.stdout,
                            SetForegroundColor(Color::Rgb {
                                r: color.r,
                                g: color.g,
                                b: color.b,
                            }),
                            SetAttribute(attribute),
                            Print(cell.ch)
                        )?;
                    }
                    _ => {
                        queue!(
                            self.stdout,
                            ResetColor,
                            SetAttribute(Attribute::Reset),
                            Print(cell.ch)
                        )?;
                    }
                }
            }

            queue!(self.stdout, ResetColor, SetAttribute(Attribute::Reset))?;
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

        self.clear_current_line()?;
        queue!(self.stdout, MoveTo(column, self.row))?;
        write!(self.stdout, "{line}")?;
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
        enable_raw_mode().context(login_text(LoginText::ErrorRawMode))?;
        let mut stdout = stdout();
        execute!(stdout, EnterAlternateScreen, Hide)
            .context(login_text(LoginText::ErrorEnterScreen))?;
        Ok(Self {
            stdout,
            last_content_signature: None,
            last_content_start_row: 0,
            last_content_end_row: 0,
            last_logo_rows: 0,
        })
    }

    fn render(&mut self, app: &LoginApp) -> Result<()> {
        let layout = RenderLayout::detect();
        let logo_rows = if layout.show_logo {
            rendered_logo().len() as u16 + 1
        } else {
            0
        };

        let mut logo_screen = ScreenWriter::new(&mut self.stdout, layout, 0);
        if layout.show_logo {
            logo_screen.write_logo()?;
            logo_screen.blank_line()?;
        }
        for row in logo_rows
            ..self
                .last_logo_rows
                .max(logo_rows)
                .min(layout.terminal_height)
        {
            queue!(self.stdout, MoveTo(0, row), Clear(ClearType::CurrentLine))?;
        }
        self.last_logo_rows = logo_rows;

        let content_signature = format!(
            "{}|{}|{:?}|{:?}",
            layout.content_width, layout.show_logo, app.status, app.screen
        );
        let content_changed = self
            .last_content_signature
            .as_ref()
            .map(|previous| previous != &content_signature)
            .unwrap_or(true)
            || self.last_content_start_row != logo_rows;

        if content_changed {
            let mut screen = ScreenWriter::new(&mut self.stdout, layout, logo_rows);

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

            let content_end_row = screen.row;
            drop(screen);

            for row in content_end_row..self.last_content_end_row.min(layout.terminal_height) {
                queue!(self.stdout, MoveTo(0, row), Clear(ClearType::CurrentLine))?;
            }

            self.last_content_signature = Some(content_signature);
            self.last_content_start_row = logo_rows;
            self.last_content_end_row = content_end_row;
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
    screen.write_wrapped("", "", login_text(LoginText::MenuTitle), LineStyle::Bold)?;
    screen.write_wrapped(
        "",
        "",
        login_text(LoginText::MenuSubtitle),
        LineStyle::Plain,
    )?;
    screen.blank_line()?;

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
        screen.blank_line()?;
    }

    screen.write_wrapped(
        "",
        "",
        login_text(LoginText::ContinueOrExit),
        LineStyle::Dim,
    )?;
    if let Some(info) = info {
        screen.blank_line()?;
        screen.write_wrapped("", "", info, LineStyle::Cyan)?;
    }
    Ok(())
}

fn render_confirm(
    screen: &mut ScreenWriter<'_>,
    provider: ProviderKind,
    yes_selected: bool,
) -> Result<()> {
    screen.write_wrapped("", "", login_text(LoginText::ConfirmTitle), LineStyle::Bold)?;
    screen.write_wrapped(
        "",
        "",
        &replace_placeholder(
            login_text(LoginText::ConfirmReplaceAfterSave),
            "provider",
            provider.title(),
        ),
        LineStyle::Plain,
    )?;
    screen.write_wrapped(
        "",
        "",
        login_text(LoginText::ConfirmKeepCurrent),
        LineStyle::Dim,
    )?;
    screen.blank_line()?;

    let no_button = if yes_selected {
        format!("[ {} ]", login_text(LoginText::ButtonNo))
    } else {
        format!(
            "{}",
            format!("[ {} ]", login_text(LoginText::ButtonNo))
                .cyan()
                .bold()
        )
    };
    let yes_button = if yes_selected {
        format!(
            "{}",
            format!("[ {} ]", login_text(LoginText::ButtonYes))
                .cyan()
                .bold()
        )
    } else {
        format!("[ {} ]", login_text(LoginText::ButtonYes))
    };

    screen.write_padded_line(&format!("  {no_button}  {yes_button}"))?;
    screen.blank_line()?;
    screen.write_wrapped(
        "",
        "",
        login_text(LoginText::ContinueOrExit),
        LineStyle::Dim,
    )?;
    Ok(())
}

fn render_form(screen: &mut ScreenWriter<'_>, form: &FormState) -> Result<()> {
    screen.write_wrapped("", "", form.provider.title(), LineStyle::Bold)?;
    screen.write_wrapped(
        "",
        "",
        login_text(LoginText::FormSubtitle),
        LineStyle::Plain,
    )?;
    screen.blank_line()?;

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
        screen.blank_line()?;
    }

    screen.write_wrapped("", "", login_text(LoginText::SaveOrExit), LineStyle::Dim)?;
    if let Some(error) = &form.error {
        screen.blank_line()?;
        screen.write_wrapped("", "", error, LineStyle::Red)?;
    }
    Ok(())
}

fn render_chatgpt_waiting(
    screen: &mut ScreenWriter<'_>,
    auth_url: Option<&str>,
    browser_opened: bool,
) -> Result<()> {
    screen.write_wrapped("", "", login_text(LoginText::WaitTitle), LineStyle::Bold)?;
    screen.write_wrapped("", "", login_text(LoginText::WaitBrowser), LineStyle::Plain)?;
    screen.write_wrapped(
        "",
        "",
        login_text(LoginText::WaitSwitchToChatGpt),
        LineStyle::Plain,
    )?;
    if let Some(auth_url) = auth_url.filter(|value| !value.trim().is_empty()) {
        screen.blank_line()?;
        screen.write_wrapped(
            "  ",
            "  ",
            login_text(LoginText::WaitOpenLink),
            LineStyle::Plain,
        )?;
        screen.blank_line()?;
        screen.write_wrapped("  ", "  ", auth_url, LineStyle::CyanUnderline)?;
    }
    if !browser_opened {
        screen.blank_line()?;
        screen.write_wrapped(
            "  ",
            "  ",
            login_text(LoginText::WaitBrowserFailed),
            LineStyle::Dim,
        )?;
    }
    screen.blank_line()?;
    screen.write_wrapped(
        "",
        "",
        login_text(LoginText::WaitCancelOrExit),
        LineStyle::Dim,
    )?;
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
        screen.blank_line()?;
        screen.write_wrapped("", "", detail, LineStyle::Plain)?;
    }
    screen.blank_line()?;
    screen.write_wrapped(
        "",
        "",
        login_text(LoginText::ContinueOrExit),
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
        bail!(login_text(LoginText::ErrorJsonUnsupported))
    }

    if !io::stdin().is_terminal() || !io::stdout().is_terminal() {
        bail!(login_text(LoginText::ErrorInteractiveTerminal))
    }

    let status = fetch_login_status().await?;
    let mut app = LoginApp::new(status);
    let mut terminal = TerminalGuard::enter()?;

    loop {
        app.drain_async_events().await?;
        terminal.render(&app)?;

        if event::poll(Duration::from_millis(50))
            .context(login_text(LoginText::ErrorReadKeyPoll))?
        {
            match event::read().context(login_text(LoginText::ErrorReadEvent))? {
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
        .ok_or_else(|| anyhow!(login_text(LoginText::ErrorStatusDataMissing)))?;
    serde_json::from_value(data).context(login_text(LoginText::ErrorStatusParse))
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
        return Some(replace_placeholder(
            login_text(LoginText::DetailAccount),
            "account",
            account,
        ));
    }
    if let Some(provider) = data.get("provider").and_then(|value| value.as_str()) {
        return Some(replace_placeholder(
            login_text(LoginText::DetailProvider),
            "provider",
            provider,
        ));
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

#[derive(Clone, Copy)]
enum LoginText {
    StatusCurrent,
    StatusConfigured,
    FieldBaseUrl,
    FieldApiKey,
    FieldModel,
    PlaceholderApiKey,
    MenuTitle,
    MenuSubtitle,
    ContinueOrExit,
    ConfirmTitle,
    ConfirmReplaceAfterSave,
    ConfirmKeepCurrent,
    ButtonNo,
    ButtonYes,
    FormSubtitle,
    SaveOrExit,
    WaitTitle,
    WaitBrowser,
    WaitSwitchToChatGpt,
    WaitOpenLink,
    WaitBrowserFailed,
    WaitCancelOrExit,
    ErrorJsonUnsupported,
    ErrorInteractiveTerminal,
    ErrorRawMode,
    ErrorEnterScreen,
    ErrorReadKeyPoll,
    ErrorReadEvent,
    ErrorStatusDataMissing,
    ErrorStatusParse,
    ErrorBaseUrlRequired,
    ErrorApiKeyRequired,
    ErrorModelRequired,
    ErrorChatGptFailed,
    ChatGptCompleted,
    DetailAccount,
    DetailProvider,
}

fn login_text(key: LoginText) -> &'static str {
    match (i18n::locale(), key) {
        ("en", LoginText::StatusCurrent) => "[Current]",
        ("de", LoginText::StatusCurrent) => "[Aktiv]",
        ("fr", LoginText::StatusCurrent) => "[Actuel]",
        ("ja", LoginText::StatusCurrent) => "[現在使用中]",
        ("ko", LoginText::StatusCurrent) => "[현재 사용 중]",
        ("zh-Hant", LoginText::StatusCurrent) => "[目前使用]",
        (_, LoginText::StatusCurrent) => "[当前使用]",

        ("en", LoginText::StatusConfigured) => "[Configured]",
        ("de", LoginText::StatusConfigured) => "[Konfiguriert]",
        ("fr", LoginText::StatusConfigured) => "[Configuré]",
        ("ja", LoginText::StatusConfigured) => "[設定済み]",
        ("ko", LoginText::StatusConfigured) => "[구성됨]",
        ("zh-Hant", LoginText::StatusConfigured) => "[已設定]",
        (_, LoginText::StatusConfigured) => "[已配置]",

        ("de", LoginText::FieldBaseUrl) => "Basis-URL",
        ("fr", LoginText::FieldBaseUrl) => "URL de base",
        (_, LoginText::FieldBaseUrl) => "Base URL",

        (_, LoginText::FieldApiKey) => "API Key",
        (_, LoginText::FieldModel) => "Model",

        ("en", LoginText::PlaceholderApiKey) => "Enter your API key here",
        ("de", LoginText::PlaceholderApiKey) => "API-Schlüssel hier eingeben",
        ("fr", LoginText::PlaceholderApiKey) => "Saisissez votre clé API ici",
        ("ja", LoginText::PlaceholderApiKey) => "ここに API Key を入力",
        ("ko", LoginText::PlaceholderApiKey) => "여기에 API Key 입력",
        ("zh-Hant", LoginText::PlaceholderApiKey) => "在此輸入 API Key",
        (_, LoginText::PlaceholderApiKey) => "在这里输入 API Key",

        ("en", LoginText::MenuTitle) => "Configure Deck AI providers",
        ("de", LoginText::MenuTitle) => "Deck-AI-Anbieter konfigurieren",
        ("fr", LoginText::MenuTitle) => "Configurer les fournisseurs IA de Deck",
        ("ja", LoginText::MenuTitle) => "Deck AI プロバイダーを設定",
        ("ko", LoginText::MenuTitle) => "Deck AI 제공자 설정",
        ("zh-Hant", LoginText::MenuTitle) => "設定 Deck AI 提供商",
        (_, LoginText::MenuTitle) => "配置 Deck AI 提供商",

        ("en", LoginText::MenuSubtitle) => "Choose and configure an AI provider for Deck.",
        ("de", LoginText::MenuSubtitle) => "Wählen und konfigurieren Sie einen KI-Anbieter für Deck.",
        ("fr", LoginText::MenuSubtitle) => "Choisissez et configurez un fournisseur d'IA pour Deck.",
        ("ja", LoginText::MenuSubtitle) => "Deck 用の AI プロバイダーを選んで設定します。",
        ("ko", LoginText::MenuSubtitle) => "Deck용 AI 제공자를 선택하고 설정합니다.",
        ("zh-Hant", LoginText::MenuSubtitle) => "為 Deck 選擇並設定 AI 提供商。",
        (_, LoginText::MenuSubtitle) => "为 Deck 选择并配置 AI 提供商。",

        ("en", LoginText::ContinueOrExit) => "Press Enter to continue, or ESC to exit",
        ("de", LoginText::ContinueOrExit) => "Drücken Sie Enter, um fortzufahren, oder ESC zum Beenden",
        ("fr", LoginText::ContinueOrExit) => "Appuyez sur Entrée pour continuer, ou sur Échap pour quitter",
        ("ja", LoginText::ContinueOrExit) => "Enter で続行、ESC で終了",
        ("ko", LoginText::ContinueOrExit) => "Enter를 눌러 계속하거나 ESC로 종료",
        ("zh-Hant", LoginText::ContinueOrExit) => "按 Enter 繼續，或按 ESC 離開",
        (_, LoginText::ContinueOrExit) => "按 Enter 继续，或按 ESC 退出",

        ("en", LoginText::ConfirmTitle) => "Existing configuration detected. Continue?",
        ("de", LoginText::ConfirmTitle) => "Vorhandene Konfiguration erkannt. Fortfahren?",
        ("fr", LoginText::ConfirmTitle) => "Configuration existante détectée. Continuer ?",
        ("ja", LoginText::ConfirmTitle) => "既存の設定が見つかりました。続行しますか？",
        ("ko", LoginText::ConfirmTitle) => "기존 구성이 감지되었습니다. 계속하시겠습니까?",
        ("zh-Hant", LoginText::ConfirmTitle) => "偵測到既有設定，是否繼續？",
        (_, LoginText::ConfirmTitle) => "检测到已有配置，请问是否要继续？",

        ("en", LoginText::ConfirmReplaceAfterSave) => "The current {provider} configuration will be replaced after the new settings are saved.",
        ("de", LoginText::ConfirmReplaceAfterSave) => "Die aktuelle {provider}-Konfiguration wird ersetzt, sobald die neuen Einstellungen gespeichert sind.",
        ("fr", LoginText::ConfirmReplaceAfterSave) => "La configuration actuelle de {provider} sera remplacée une fois les nouveaux réglages enregistrés.",
        ("ja", LoginText::ConfirmReplaceAfterSave) => "新しい設定を保存すると、現在の {provider} 設定が置き換えられます。",
        ("ko", LoginText::ConfirmReplaceAfterSave) => "새 설정이 저장되면 현재 {provider} 구성이 교체됩니다.",
        ("zh-Hant", LoginText::ConfirmReplaceAfterSave) => "新設定儲存成功後，會取代目前的 {provider} 設定。",
        (_, LoginText::ConfirmReplaceAfterSave) => "继续后会在保存成功后用新设置替换当前 {provider} 配置。",

        ("en", LoginText::ConfirmKeepCurrent) => "Your current configuration stays unchanged until saving completes.",
        ("de", LoginText::ConfirmKeepCurrent) => "Ihre aktuelle Konfiguration bleibt unverändert, bis das Speichern abgeschlossen ist.",
        ("fr", LoginText::ConfirmKeepCurrent) => "Votre configuration actuelle reste inchangée jusqu'à la fin de l'enregistrement.",
        ("ja", LoginText::ConfirmKeepCurrent) => "保存が完了するまで、現在の設定は変更されません。",
        ("ko", LoginText::ConfirmKeepCurrent) => "저장이 완료될 때까지 현재 구성은 변경되지 않습니다.",
        ("zh-Hant", LoginText::ConfirmKeepCurrent) => "在儲存完成前，目前設定會保持不變。",
        (_, LoginText::ConfirmKeepCurrent) => "在你完成保存前，当前配置会保持不变。",

        ("ja", LoginText::ButtonNo) => "いいえ",
        ("ko", LoginText::ButtonNo) => "아니요",
        ("zh-Hant", LoginText::ButtonNo) => "否",
        (_, LoginText::ButtonNo) if i18n::locale() == "zh-Hans" => "否",
        (_, LoginText::ButtonNo) => "No",

        ("ja", LoginText::ButtonYes) => "はい",
        ("ko", LoginText::ButtonYes) => "예",
        ("zh-Hant", LoginText::ButtonYes) => "是",
        (_, LoginText::ButtonYes) if i18n::locale() == "zh-Hans" => "是",
        (_, LoginText::ButtonYes) => "Yes",

        ("en", LoginText::FormSubtitle) => "Fill in the fields below and Deck will switch to that provider immediately.",
        ("de", LoginText::FormSubtitle) => "Füllen Sie die folgenden Felder aus und Deck wechselt sofort zu diesem Anbieter.",
        ("fr", LoginText::FormSubtitle) => "Renseignez les champs ci-dessous et Deck basculera immédiatement vers ce fournisseur.",
        ("ja", LoginText::FormSubtitle) => "以下の項目を入力すると、Deck はすぐにそのプロバイダーへ切り替わります。",
        ("ko", LoginText::FormSubtitle) => "아래 항목을 입력하면 Deck가 즉시 해당 제공자로 전환됩니다.",
        ("zh-Hant", LoginText::FormSubtitle) => "填寫下列資訊後，Deck 會立即切換到對應提供商。",
        (_, LoginText::FormSubtitle) => "填写下列信息后，Deck 会立即切换到对应提供商。",

        ("en", LoginText::SaveOrExit) => "Press Tab to switch fields, Enter to save, or ESC to exit",
        ("de", LoginText::SaveOrExit) => "Drücken Sie Tab zum Wechseln, Enter zum Speichern oder ESC zum Beenden",
        ("fr", LoginText::SaveOrExit) => "Appuyez sur Tab pour changer de champ, Entrée pour enregistrer, ou Échap pour quitter",
        ("ja", LoginText::SaveOrExit) => "Tab で項目を切り替え、Enter で保存、ESC で終了",
        ("ko", LoginText::SaveOrExit) => "Tab으로 필드 전환, Enter로 저장, ESC로 종료",
        ("zh-Hant", LoginText::SaveOrExit) => "按 Tab 切換欄位，按 Enter 儲存，或按 ESC 離開",
        (_, LoginText::SaveOrExit) => "按 Tab 切换字段，按 Enter 保存，或按 ESC 退出",

        ("en", LoginText::WaitTitle) => "Sign in with ChatGPT",
        ("de", LoginText::WaitTitle) => "Mit ChatGPT anmelden",
        ("fr", LoginText::WaitTitle) => "Se connecter avec ChatGPT",
        ("ja", LoginText::WaitTitle) => "ChatGPT にサインイン",
        ("ko", LoginText::WaitTitle) => "ChatGPT로 로그인",
        ("zh-Hant", LoginText::WaitTitle) => "登入 ChatGPT",
        (_, LoginText::WaitTitle) => "登录 ChatGPT",

        ("en", LoginText::WaitBrowser) => "Finish signing in via your browser.",
        ("de", LoginText::WaitBrowser) => "Schließen Sie die Anmeldung in Ihrem Browser ab.",
        ("fr", LoginText::WaitBrowser) => "Terminez la connexion dans votre navigateur.",
        ("ja", LoginText::WaitBrowser) => "ブラウザでサインインを完了してください。",
        ("ko", LoginText::WaitBrowser) => "브라우저에서 로그인을 완료하세요.",
        ("zh-Hant", LoginText::WaitBrowser) => "請在瀏覽器中完成登入。",
        (_, LoginText::WaitBrowser) => "请在浏览器中完成登录。",

        ("en", LoginText::WaitSwitchToChatGpt) => "When it finishes, Deck will automatically switch Deck AI to ChatGPT.",
        ("de", LoginText::WaitSwitchToChatGpt) => "Nach Abschluss wechselt Deck Deck AI automatisch zu ChatGPT.",
        ("fr", LoginText::WaitSwitchToChatGpt) => "Une fois terminé, Deck basculera automatiquement Deck AI sur ChatGPT.",
        ("ja", LoginText::WaitSwitchToChatGpt) => "完了すると、Deck は Deck AI を自動的に ChatGPT に切り替えます。",
        ("ko", LoginText::WaitSwitchToChatGpt) => "완료되면 Deck가 Deck AI를 자동으로 ChatGPT로 전환합니다.",
        ("zh-Hant", LoginText::WaitSwitchToChatGpt) => "完成後，Deck 會自動將 Deck AI 切換到 ChatGPT 方案。",
        (_, LoginText::WaitSwitchToChatGpt) => "完成后 Deck 会自动切换 Deck AI 到 ChatGPT 方案。",

        ("en", LoginText::WaitOpenLink) => "If the link doesn't open automatically, open the following link to authenticate:",
        ("de", LoginText::WaitOpenLink) => "Wenn sich der Link nicht automatisch öffnet, verwenden Sie zur Anmeldung den folgenden Link:",
        ("fr", LoginText::WaitOpenLink) => "Si le lien ne s'ouvre pas automatiquement, ouvrez le lien suivant pour vous authentifier :",
        ("ja", LoginText::WaitOpenLink) => "リンクが自動で開かない場合は、次のリンクを開いて認証してください。",
        ("ko", LoginText::WaitOpenLink) => "링크가 자동으로 열리지 않으면 아래 링크를 열어 인증을 진행하세요.",
        ("zh-Hant", LoginText::WaitOpenLink) => "如果連結沒有自動打開，請開啟以下連結完成驗證：",
        (_, LoginText::WaitOpenLink) => "如果链接没有自动打开，请打开下面的链接完成验证：",

        ("en", LoginText::WaitBrowserFailed) => "Unable to open the browser automatically. Copy the link above to continue.",
        ("de", LoginText::WaitBrowserFailed) => "Der Browser konnte nicht automatisch geöffnet werden. Kopieren Sie den obigen Link, um fortzufahren.",
        ("fr", LoginText::WaitBrowserFailed) => "Impossible d'ouvrir automatiquement le navigateur. Copiez le lien ci-dessus pour continuer.",
        ("ja", LoginText::WaitBrowserFailed) => "ブラウザを自動で開けませんでした。上のリンクをコピーして続行してください。",
        ("ko", LoginText::WaitBrowserFailed) => "브라우저를 자동으로 열 수 없습니다. 위 링크를 복사해 계속하세요.",
        ("zh-Hant", LoginText::WaitBrowserFailed) => "無法自動開啟瀏覽器。請複製上方連結繼續。",
        (_, LoginText::WaitBrowserFailed) => "无法自动打开浏览器。请复制上方链接继续。",

        ("en", LoginText::WaitCancelOrExit) => "Press ESC to cancel and exit",
        ("de", LoginText::WaitCancelOrExit) => "Drücken Sie ESC, um abzubrechen und zu beenden",
        ("fr", LoginText::WaitCancelOrExit) => "Appuyez sur Échap pour annuler et quitter",
        ("ja", LoginText::WaitCancelOrExit) => "ESC でキャンセルして終了",
        ("ko", LoginText::WaitCancelOrExit) => "ESC를 눌러 취소하고 종료",
        ("zh-Hant", LoginText::WaitCancelOrExit) => "按 ESC 取消並離開",
        (_, LoginText::WaitCancelOrExit) => "按 ESC 取消并退出",

        ("en", LoginText::ErrorJsonUnsupported) => "deckclip login does not support --json yet",
        ("de", LoginText::ErrorJsonUnsupported) => "deckclip login unterstützt --json derzeit nicht",
        ("fr", LoginText::ErrorJsonUnsupported) => "deckclip login ne prend pas encore en charge --json",
        ("ja", LoginText::ErrorJsonUnsupported) => "deckclip login はまだ --json をサポートしていません",
        ("ko", LoginText::ErrorJsonUnsupported) => "deckclip login은 아직 --json을 지원하지 않습니다",
        ("zh-Hant", LoginText::ErrorJsonUnsupported) => "deckclip login 暫不支援 --json",
        (_, LoginText::ErrorJsonUnsupported) => "deckclip login 暂不支持 --json",

        ("en", LoginText::ErrorInteractiveTerminal) => "deckclip login requires an interactive terminal",
        ("de", LoginText::ErrorInteractiveTerminal) => "deckclip login benötigt ein interaktives Terminal",
        ("fr", LoginText::ErrorInteractiveTerminal) => "deckclip login nécessite un terminal interactif",
        ("ja", LoginText::ErrorInteractiveTerminal) => "deckclip login には対話型ターミナルが必要です",
        ("ko", LoginText::ErrorInteractiveTerminal) => "deckclip login에는 대화형 터미널이 필요합니다",
        ("zh-Hant", LoginText::ErrorInteractiveTerminal) => "deckclip login 需要互動式終端機",
        (_, LoginText::ErrorInteractiveTerminal) => "deckclip login 需要交互式终端",

        ("en", LoginText::ErrorRawMode) => "Failed to enter terminal raw mode",
        ("de", LoginText::ErrorRawMode) => "Terminal-Raw-Mode konnte nicht aktiviert werden",
        ("fr", LoginText::ErrorRawMode) => "Impossible d'activer le mode brut du terminal",
        ("ja", LoginText::ErrorRawMode) => "ターミナルの raw mode に入れませんでした",
        ("ko", LoginText::ErrorRawMode) => "터미널 raw mode로 전환하지 못했습니다",
        ("zh-Hant", LoginText::ErrorRawMode) => "無法進入終端 raw mode",
        (_, LoginText::ErrorRawMode) => "无法进入终端 raw mode",

        ("en", LoginText::ErrorEnterScreen) => "Failed to enter the terminal login screen",
        ("de", LoginText::ErrorEnterScreen) => "Die Terminal-Anmeldemaske konnte nicht geöffnet werden",
        ("fr", LoginText::ErrorEnterScreen) => "Impossible d'ouvrir l'écran de connexion du terminal",
        ("ja", LoginText::ErrorEnterScreen) => "ターミナルのログイン画面に入れませんでした",
        ("ko", LoginText::ErrorEnterScreen) => "터미널 로그인 화면으로 진입하지 못했습니다",
        ("zh-Hant", LoginText::ErrorEnterScreen) => "無法進入終端登入畫面",
        (_, LoginText::ErrorEnterScreen) => "无法进入终端登录界面",

        ("en", LoginText::ErrorReadKeyPoll) => "Failed to poll key events",
        ("de", LoginText::ErrorReadKeyPoll) => "Tastenereignisse konnten nicht abgefragt werden",
        ("fr", LoginText::ErrorReadKeyPoll) => "Impossible d'interroger les événements clavier",
        ("ja", LoginText::ErrorReadKeyPoll) => "キーイベントのポーリングに失敗しました",
        ("ko", LoginText::ErrorReadKeyPoll) => "키 이벤트를 확인하지 못했습니다",
        ("zh-Hant", LoginText::ErrorReadKeyPoll) => "讀取按鍵事件失敗",
        (_, LoginText::ErrorReadKeyPoll) => "读取按键事件失败",

        ("en", LoginText::ErrorReadEvent) => "Failed to read terminal event",
        ("de", LoginText::ErrorReadEvent) => "Terminal-Ereignis konnte nicht gelesen werden",
        ("fr", LoginText::ErrorReadEvent) => "Impossible de lire l'événement du terminal",
        ("ja", LoginText::ErrorReadEvent) => "ターミナルイベントの読み取りに失敗しました",
        ("ko", LoginText::ErrorReadEvent) => "터미널 이벤트를 읽지 못했습니다",
        ("zh-Hant", LoginText::ErrorReadEvent) => "讀取終端事件失敗",
        (_, LoginText::ErrorReadEvent) => "读取终端事件失败",

        ("en", LoginText::ErrorStatusDataMissing) => "Login status response is missing the data field",
        ("de", LoginText::ErrorStatusDataMissing) => "In der Antwort zum Anmeldestatus fehlt das Datenfeld",
        ("fr", LoginText::ErrorStatusDataMissing) => "La réponse d'état de connexion ne contient pas le champ data",
        ("ja", LoginText::ErrorStatusDataMissing) => "ログイン状態の応答に data フィールドがありません",
        ("ko", LoginText::ErrorStatusDataMissing) => "로그인 상태 응답에 data 필드가 없습니다",
        ("zh-Hant", LoginText::ErrorStatusDataMissing) => "登入狀態回應缺少 data 欄位",
        (_, LoginText::ErrorStatusDataMissing) => "登录状态响应缺少 data 字段",

        ("en", LoginText::ErrorStatusParse) => "Failed to parse the login status response",
        ("de", LoginText::ErrorStatusParse) => "Die Antwort zum Anmeldestatus konnte nicht verarbeitet werden",
        ("fr", LoginText::ErrorStatusParse) => "Impossible d'analyser la réponse d'état de connexion",
        ("ja", LoginText::ErrorStatusParse) => "ログイン状態の応答を解析できませんでした",
        ("ko", LoginText::ErrorStatusParse) => "로그인 상태 응답을 해석하지 못했습니다",
        ("zh-Hant", LoginText::ErrorStatusParse) => "無法解析登入狀態回應",
        (_, LoginText::ErrorStatusParse) => "无法解析登录状态响应",

        ("en", LoginText::ErrorBaseUrlRequired) => "Base URL cannot be empty",
        ("de", LoginText::ErrorBaseUrlRequired) => "Die Basis-URL darf nicht leer sein",
        ("fr", LoginText::ErrorBaseUrlRequired) => "L'URL de base ne peut pas être vide",
        ("ja", LoginText::ErrorBaseUrlRequired) => "Base URL は空にできません",
        ("ko", LoginText::ErrorBaseUrlRequired) => "Base URL은 비워둘 수 없습니다",
        ("zh-Hant", LoginText::ErrorBaseUrlRequired) => "Base URL 不能為空",
        (_, LoginText::ErrorBaseUrlRequired) => "Base URL 不能为空",

        ("en", LoginText::ErrorApiKeyRequired) => "API Key cannot be empty",
        ("de", LoginText::ErrorApiKeyRequired) => "Der API-Schlüssel darf nicht leer sein",
        ("fr", LoginText::ErrorApiKeyRequired) => "La clé API ne peut pas être vide",
        ("ja", LoginText::ErrorApiKeyRequired) => "API Key は空にできません",
        ("ko", LoginText::ErrorApiKeyRequired) => "API Key는 비워둘 수 없습니다",
        ("zh-Hant", LoginText::ErrorApiKeyRequired) => "API Key 不能為空",
        (_, LoginText::ErrorApiKeyRequired) => "API Key 不能为空",

        ("en", LoginText::ErrorModelRequired) => "Model cannot be empty",
        ("de", LoginText::ErrorModelRequired) => "Das Modell darf nicht leer sein",
        ("fr", LoginText::ErrorModelRequired) => "Le modèle ne peut pas être vide",
        ("ja", LoginText::ErrorModelRequired) => "Model は空にできません",
        ("ko", LoginText::ErrorModelRequired) => "Model은 비워둘 수 없습니다",
        ("zh-Hant", LoginText::ErrorModelRequired) => "Model 不能為空",
        (_, LoginText::ErrorModelRequired) => "Model 不能为空",

        ("en", LoginText::ErrorChatGptFailed) => "ChatGPT sign-in failed",
        ("de", LoginText::ErrorChatGptFailed) => "ChatGPT-Anmeldung fehlgeschlagen",
        ("fr", LoginText::ErrorChatGptFailed) => "Échec de la connexion ChatGPT",
        ("ja", LoginText::ErrorChatGptFailed) => "ChatGPT へのサインインに失敗しました",
        ("ko", LoginText::ErrorChatGptFailed) => "ChatGPT 로그인 실패",
        ("zh-Hant", LoginText::ErrorChatGptFailed) => "ChatGPT 登入失敗",
        (_, LoginText::ErrorChatGptFailed) => "ChatGPT 登录失败",

        ("en", LoginText::ChatGptCompleted) => "Browser authorization completed. Deck has switched to ChatGPT.",
        ("de", LoginText::ChatGptCompleted) => "Die Browser-Autorisierung ist abgeschlossen. Deck wurde zu ChatGPT gewechselt.",
        ("fr", LoginText::ChatGptCompleted) => "L'autorisation dans le navigateur est terminée. Deck est passé à ChatGPT.",
        ("ja", LoginText::ChatGptCompleted) => "ブラウザでの認証が完了し、Deck は ChatGPT に切り替わりました。",
        ("ko", LoginText::ChatGptCompleted) => "브라우저 인증이 완료되어 Deck가 ChatGPT로 전환되었습니다.",
        ("zh-Hant", LoginText::ChatGptCompleted) => "瀏覽器授權已完成，Deck 已切換到 ChatGPT。",
        (_, LoginText::ChatGptCompleted) => "浏览器授权已完成，Deck 已切换到 ChatGPT。",

        ("en", LoginText::DetailAccount) => "Current account: {account}",
        ("de", LoginText::DetailAccount) => "Aktuelles Konto: {account}",
        ("fr", LoginText::DetailAccount) => "Compte actuel : {account}",
        ("ja", LoginText::DetailAccount) => "現在のアカウント: {account}",
        ("ko", LoginText::DetailAccount) => "현재 계정: {account}",
        ("zh-Hant", LoginText::DetailAccount) => "目前帳號：{account}",
        (_, LoginText::DetailAccount) => "当前账号：{account}",

        ("en", LoginText::DetailProvider) => "Current provider: {provider}",
        ("de", LoginText::DetailProvider) => "Aktueller Anbieter: {provider}",
        ("fr", LoginText::DetailProvider) => "Fournisseur actuel : {provider}",
        ("ja", LoginText::DetailProvider) => "現在のプロバイダー: {provider}",
        ("ko", LoginText::DetailProvider) => "현재 제공자: {provider}",
        ("zh-Hant", LoginText::DetailProvider) => "目前提供商：{provider}",
        (_, LoginText::DetailProvider) => "当前提供商：{provider}",
    }
}

fn provider_title(provider: ProviderKind) -> &'static str {
    match (i18n::locale(), provider) {
        ("en", ProviderKind::ChatGpt) => {
            "Sign in with ChatGPT (usage included with your ChatGPT plan)"
        }
        ("de", ProviderKind::ChatGpt) => {
            "Mit ChatGPT anmelden (Nutzung in Ihrem ChatGPT-Tarif enthalten)"
        }
        ("fr", ProviderKind::ChatGpt) => {
            "Se connecter avec ChatGPT (utilisation incluse dans votre formule ChatGPT)"
        }
        ("ja", ProviderKind::ChatGpt) => {
            "ChatGPT でサインイン（利用量は ChatGPT プランに含まれます）"
        }
        ("ko", ProviderKind::ChatGpt) => "ChatGPT로 로그인(사용량은 ChatGPT 요금제에 포함됨)",
        ("zh-Hant", ProviderKind::ChatGpt) => {
            "使用 ChatGPT 登入（用量已包含於你的 ChatGPT 方案中）"
        }
        (_, ProviderKind::ChatGpt) => "登录 ChatGPT（用量包含在你的 ChatGPT 方案中）",

        ("en", ProviderKind::OpenAI) => "Provide your own OpenAI API key",
        ("de", ProviderKind::OpenAI) => "Eigenen OpenAI API-Schlüssel verwenden",
        ("fr", ProviderKind::OpenAI) => "Utiliser votre propre clé API OpenAI",
        ("ja", ProviderKind::OpenAI) => "自分の OpenAI API Key を使う",
        ("ko", ProviderKind::OpenAI) => "내 OpenAI API Key 사용",
        ("zh-Hant", ProviderKind::OpenAI) => "使用自己的 OpenAI API Key",
        (_, ProviderKind::OpenAI) => "使用自己的 OpenAI API Key",

        ("en", ProviderKind::Anthropic) => "Provide your own Anthropic API key",
        ("de", ProviderKind::Anthropic) => "Eigenen Anthropic API-Schlüssel verwenden",
        ("fr", ProviderKind::Anthropic) => "Utiliser votre propre clé API Anthropic",
        ("ja", ProviderKind::Anthropic) => "自分の Anthropic API Key を使う",
        ("ko", ProviderKind::Anthropic) => "내 Anthropic API Key 사용",
        ("zh-Hant", ProviderKind::Anthropic) => "使用自己的 Anthropic API Key",
        (_, ProviderKind::Anthropic) => "使用自己的 Anthropic API Key",

        ("en", ProviderKind::Ollama) => "Use Ollama",
        ("de", ProviderKind::Ollama) => "Ollama verwenden",
        ("fr", ProviderKind::Ollama) => "Utiliser Ollama",
        ("ja", ProviderKind::Ollama) => "Ollama を使う",
        ("ko", ProviderKind::Ollama) => "Ollama 사용",
        ("zh-Hant", ProviderKind::Ollama) => "使用 Ollama",
        (_, ProviderKind::Ollama) => "使用 Ollama",
    }
}

fn provider_description(provider: ProviderKind, status: &ProviderStatus) -> String {
    match provider {
        ProviderKind::ChatGpt => match (i18n::locale(), status.account.as_deref()) {
            ("en", Some(account)) => format!("Use ChatGPT OAuth. Current account: {account}"),
            ("de", Some(account)) => format!("ChatGPT OAuth verwenden. Aktuelles Konto: {account}"),
            ("fr", Some(account)) => format!("Utiliser OAuth ChatGPT. Compte actuel : {account}"),
            ("ja", Some(account)) => format!("ChatGPT OAuth を使用します。現在のアカウント: {account}"),
            ("ko", Some(account)) => format!("ChatGPT OAuth를 사용합니다. 현재 계정: {account}"),
            ("zh-Hant", Some(account)) => format!("使用 ChatGPT OAuth 授權。目前帳號：{account}"),
            (_, Some(account)) => format!("使用 ChatGPT OAuth 授权。当前账号：{account}"),
            ("en", None) => "Use ChatGPT OAuth and finish sign-in in your browser".to_string(),
            ("de", None) => "Mit ChatGPT OAuth anmelden und die Anmeldung im Browser abschließen".to_string(),
            ("fr", None) => "Utilisez l'authentification OAuth de ChatGPT et terminez la connexion dans votre navigateur".to_string(),
            ("ja", None) => "ChatGPT OAuth を使い、ブラウザでサインインを完了します".to_string(),
            ("ko", None) => "ChatGPT OAuth를 사용해 브라우저에서 로그인을 완료합니다".to_string(),
            ("zh-Hant", None) => "使用 ChatGPT OAuth 授權，並在瀏覽器中完成登入".to_string(),
            (_, None) => "使用 ChatGPT OAuth 授权，在浏览器中完成登录".to_string(),
        },
        ProviderKind::OpenAI => match i18n::locale() {
            "en" => "Use an OpenAI API key for model requests".to_string(),
            "de" => "Einen OpenAI-API-Schlüssel für Modellanfragen verwenden".to_string(),
            "fr" => "Utiliser une clé API OpenAI pour les requêtes au modèle".to_string(),
            "ja" => "OpenAI API Key を使ってモデルを呼び出します".to_string(),
            "ko" => "OpenAI API Key로 모델을 호출합니다".to_string(),
            "zh-Hant" => "使用 OpenAI API Key 進行模型呼叫".to_string(),
            _ => "使用 OpenAI API Key 进行模型调用".to_string(),
        },
        ProviderKind::Anthropic => match i18n::locale() {
            "en" => "Use an Anthropic API key for model requests".to_string(),
            "de" => "Einen Anthropic-API-Schlüssel für Modellanfragen verwenden".to_string(),
            "fr" => "Utiliser une clé API Anthropic pour les requêtes au modèle".to_string(),
            "ja" => "Anthropic API Key を使ってモデルを呼び出します".to_string(),
            "ko" => "Anthropic API Key로 모델을 호출합니다".to_string(),
            "zh-Hant" => "使用 Anthropic API Key 進行模型呼叫".to_string(),
            _ => "使用 Anthropic API Key 进行模型调用".to_string(),
        },
        ProviderKind::Ollama => match i18n::locale() {
            "en" => "Use local models through Ollama".to_string(),
            "de" => "Lokale Modelle über Ollama verwenden".to_string(),
            "fr" => "Utiliser des modèles locaux via Ollama".to_string(),
            "ja" => "Ollama 経由でローカルモデルを使います".to_string(),
            "ko" => "Ollama를 통해 로컬 모델을 사용합니다".to_string(),
            "zh-Hant" => "透過 Ollama 使用本地模型".to_string(),
            _ => "通过 Ollama 使用本地模型".to_string(),
        },
    }
}

fn provider_success_title(provider: ProviderKind) -> &'static str {
    match (i18n::locale(), provider) {
        ("en", ProviderKind::ChatGpt) => "ChatGPT signed in",
        ("de", ProviderKind::ChatGpt) => "Bei ChatGPT angemeldet",
        ("fr", ProviderKind::ChatGpt) => "Connexion ChatGPT réussie",
        ("ja", ProviderKind::ChatGpt) => "ChatGPT にサインインしました",
        ("ko", ProviderKind::ChatGpt) => "ChatGPT 로그인 완료",
        ("zh-Hant", ProviderKind::ChatGpt) => "ChatGPT 登入成功",
        (_, ProviderKind::ChatGpt) => "ChatGPT 登录成功",

        ("en", ProviderKind::OpenAI) => "OpenAI API configured",
        ("de", ProviderKind::OpenAI) => "OpenAI API konfiguriert",
        ("fr", ProviderKind::OpenAI) => "API OpenAI configurée",
        ("ja", ProviderKind::OpenAI) => "OpenAI API を設定しました",
        ("ko", ProviderKind::OpenAI) => "OpenAI API 구성 완료",
        ("zh-Hant", ProviderKind::OpenAI) => "OpenAI API 已設定",
        (_, ProviderKind::OpenAI) => "OpenAI API 已配置",

        ("en", ProviderKind::Anthropic) => "Anthropic API configured",
        ("de", ProviderKind::Anthropic) => "Anthropic API konfiguriert",
        ("fr", ProviderKind::Anthropic) => "API Anthropic configurée",
        ("ja", ProviderKind::Anthropic) => "Anthropic API を設定しました",
        ("ko", ProviderKind::Anthropic) => "Anthropic API 구성 완료",
        ("zh-Hant", ProviderKind::Anthropic) => "Anthropic API 已設定",
        (_, ProviderKind::Anthropic) => "Anthropic API 已配置",

        ("en", ProviderKind::Ollama) => "Ollama configured",
        ("de", ProviderKind::Ollama) => "Ollama konfiguriert",
        ("fr", ProviderKind::Ollama) => "Ollama configuré",
        ("ja", ProviderKind::Ollama) => "Ollama を設定しました",
        ("ko", ProviderKind::Ollama) => "Ollama 구성 완료",
        ("zh-Hant", ProviderKind::Ollama) => "Ollama 已設定",
        (_, ProviderKind::Ollama) => "Ollama 已配置",
    }
}

fn replace_placeholder(template: &str, key: &str, value: &str) -> String {
    template.replace(&format!("{{{key}}}"), value)
}

fn logo_elapsed_seconds() -> f32 {
    LOGO_RENDER_START
        .get_or_init(Instant::now)
        .elapsed()
        .as_secs_f32()
}

fn parsed_logo() -> &'static [Vec<LogoCell>] {
    PARSED_LOGO.get_or_init(|| LOGO.lines().map(parse_logo_line).collect())
}

fn rendered_logo() -> &'static [Vec<LogoCell>] {
    RENDERED_LOGO.get_or_init(scale_logo)
}

fn parse_logo_line(line: &str) -> Vec<LogoCell> {
    let bytes = line.as_bytes();
    let mut index = 0usize;
    let mut current_fg: Option<RgbColor> = None;
    let mut cells = Vec::new();

    while index < bytes.len() {
        if bytes[index] == 0x1b && index + 1 < bytes.len() && bytes[index + 1] == b'[' {
            if let Some(offset) = bytes[index + 2..].iter().position(|&byte| byte == b'm') {
                let end = index + 2 + offset;
                current_fg = parse_sgr_sequence(&line[index + 2..end], current_fg);
                index = end + 1;
                continue;
            }
        }

        cells.push(LogoCell {
            ch: bytes[index] as char,
            fg: current_fg,
        });
        index += 1;
    }

    cells
}

fn parse_sgr_sequence(sequence: &str, current_fg: Option<RgbColor>) -> Option<RgbColor> {
    if sequence.is_empty() {
        return None;
    }

    let parts: Vec<&str> = sequence.split(';').collect();
    if parts.len() == 1 && parts[0] == "0" {
        return None;
    }

    if parts.len() >= 5 && parts[0] == "38" && parts[1] == "2" {
        let r = parts[2].parse::<u8>().ok();
        let g = parts[3].parse::<u8>().ok();
        let b = parts[4].parse::<u8>().ok();
        if let (Some(r), Some(g), Some(b)) = (r, g, b) {
            return Some(RgbColor { r, g, b });
        }
    }

    current_fg
}

fn scale_logo() -> Vec<Vec<LogoCell>> {
    let source = parsed_logo();
    let source_height = source.len();
    let source_width = source.iter().map(|line| line.len()).max().unwrap_or(0);

    if source_height == 0 || source_width == 0 {
        return Vec::new();
    }

    let target_width = ((source_width as f32) * LOGO_SCALE).round().max(1.0) as usize;
    let target_height = ((source_height as f32) * LOGO_SCALE).round().max(1.0) as usize;
    let blank = LogoCell { ch: ' ', fg: None };
    let mut scaled = Vec::with_capacity(target_height);

    for target_y in 0..target_height {
        let source_y = ((target_y as f32) / LOGO_SCALE)
            .floor()
            .clamp(0.0, (source_height.saturating_sub(1)) as f32) as usize;
        let mut line = Vec::with_capacity(target_width);

        for target_x in 0..target_width {
            let source_x = ((target_x as f32) / LOGO_SCALE)
                .floor()
                .clamp(0.0, (source_width.saturating_sub(1)) as f32)
                as usize;

            let cell = source
                .get(source_y)
                .and_then(|row| row.get(source_x))
                .copied()
                .unwrap_or(blank);
            line.push(cell);
        }

        while matches!(line.last(), Some(LogoCell { ch: ' ', fg: _ })) {
            line.pop();
        }

        scaled.push(line);
    }

    while scaled
        .last()
        .is_some_and(|line| line.iter().all(|cell| cell.ch == ' '))
    {
        scaled.pop();
    }

    scaled
}

fn shimmer_intensity(
    column: usize,
    row: usize,
    width: usize,
    height: usize,
    elapsed_seconds: f32,
) -> f32 {
    let row_weight = 0.82f32;
    let sweep_width = ((width.max(height) as f32) * 0.18).max(5.5);
    let padding = sweep_width + 4.0;
    let period = 2.1f32;
    let sweep_extent = (width as f32) + ((height.saturating_sub(1)) as f32 * row_weight);
    let sweep_position =
        (elapsed_seconds.rem_euclid(period) / period) * (sweep_extent + padding * 2.0) - padding;
    let projected_position = (column as f32) + ((row as f32) * row_weight);
    let distance = (projected_position - sweep_position).abs();

    if distance > sweep_width {
        0.0
    } else {
        let normalized = distance / sweep_width;
        0.5 * (1.0 + (std::f32::consts::PI * normalized).cos())
    }
}

fn shimmer_color(base: RgbColor, intensity: f32) -> RgbColor {
    let intensity = intensity.clamp(0.0, 1.0) * 0.22;
    blend_toward(
        base,
        RgbColor {
            r: 255,
            g: 255,
            b: 255,
        },
        intensity,
    )
}

fn blend_toward(base: RgbColor, highlight: RgbColor, amount: f32) -> RgbColor {
    let blend_channel = |from: u8, to: u8| -> u8 {
        let from = from as f32;
        let to = to as f32;
        (from + (to - from) * amount).round().clamp(0.0, 255.0) as u8
    };

    RgbColor {
        r: blend_channel(base.r, highlight.r),
        g: blend_channel(base.g, highlight.g),
        b: blend_channel(base.b, highlight.b),
    }
}
