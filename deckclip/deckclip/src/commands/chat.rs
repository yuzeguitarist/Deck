use std::collections::HashMap;
use std::io::{self, IsTerminal, Stdout};
use std::process::{Command, Stdio};
use std::sync::Arc;
use std::time::{Duration, Instant};

use anyhow::{anyhow, bail, Context, Result};
use crossterm::event::{
    self, DisableBracketedPaste, DisableMouseCapture, EnableBracketedPaste, EnableMouseCapture,
    Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers, KeyboardEnhancementFlags, MouseButton,
    MouseEvent, MouseEventKind, PopKeyboardEnhancementFlags, PushKeyboardEnhancementFlags,
};
use crossterm::execute;
use crossterm::terminal::{
    disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen,
};
use deckclip_core::{ChatStreamFrame, Config, DeckClient};
use deckclip_protocol::event as chat_event;
use ratatui_core::layout::{Constraint, Direction, Layout, Rect};
use ratatui_core::style::{Color, Modifier, Style};
use ratatui_core::terminal::{Frame, Terminal};
use ratatui_core::text::{Line, Span};
use ratatui_crossterm::CrosstermBackend;
use ratatui_widgets::block::Block;
use ratatui_widgets::borders::Borders;
use ratatui_widgets::clear::Clear;
use ratatui_widgets::list::{List, ListItem, ListState};
use ratatui_widgets::paragraph::Paragraph;
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use textwrap::Options;
use tokio::sync::mpsc::{unbounded_channel, UnboundedSender};
use tokio::sync::Mutex;
use unicode_width::UnicodeWidthChar;

mod approval;
mod render;

use approval::{ApprovalInputGuard, ApprovalOverlay};
use render::*;

use crate::commands::login;
use crate::{
    i18n,
    output::{self, OutputMode},
};

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ContextUsageData {
    estimated_tokens: usize,
    context_window_size: usize,
    usage_percent_text: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct BootstrapData {
    configured: bool,
    account: Option<String>,
    #[serde(default)]
    provider: Option<String>,
    #[serde(default)]
    model: Option<String>,
    #[serde(default)]
    session_id: Option<String>,
    #[serde(default)]
    conversation_id: Option<String>,
    busy: Option<bool>,
}

#[derive(Debug, Clone, Deserialize)]
struct ConversationMessageData {
    role: String,
    text: String,
    #[serde(default)]
    attachment: Option<ChatAttachmentData>,
    #[serde(default)]
    attachments: Vec<ChatAttachmentData>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct ChatAttachmentData {
    #[serde(rename = "type")]
    kind: String,
    display_text: String,
    full_content: String,
    #[serde(default)]
    ocr_text: Option<String>,
    #[serde(default)]
    source_item_id: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ClipboardPasteData {
    #[serde(default)]
    text: Option<String>,
    #[serde(default)]
    attachment: Option<ChatAttachmentData>,
    #[serde(default)]
    attachments: Vec<ChatAttachmentData>,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
struct PendingPasteData {
    placeholder: String,
    full_text: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
struct ComposerHistoryEntry {
    input: String,
    pending_pastes: Vec<PendingPasteData>,
}

impl ConversationMessageData {
    fn normalized_attachments(&self) -> Vec<ChatAttachmentData> {
        if !self.attachments.is_empty() {
            self.attachments.clone()
        } else {
            self.attachment.clone().into_iter().collect()
        }
    }
}

impl ClipboardPasteData {
    fn normalized_attachments(&self) -> Vec<ChatAttachmentData> {
        if !self.attachments.is_empty() {
            self.attachments.clone()
        } else {
            self.attachment.clone().into_iter().collect()
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
struct ConversationData {
    id: String,
    title: String,
    provider: String,
    model: String,
    messages: Vec<ConversationMessageData>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SessionData {
    session_id: String,
    conversation: ConversationData,
    context_usage: Option<ContextUsageData>,
    last_assistant_text: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct HistoryItemData {
    id: String,
    title: String,
    provider: String,
    #[serde(default)]
    model: Option<String>,
    message_count: usize,
    last_snippet: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct HistoryListData {
    items: Vec<HistoryItemData>,
    #[serde(default)]
    has_more: bool,
    #[serde(default)]
    next_cursor: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ToolEventData {
    call_id: String,
    tool: String,
    parameters: Value,
    #[allow(dead_code)]
    approved: Option<bool>,
    #[allow(dead_code)]
    result: Option<Value>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct CompactingEventData {
    attempt: usize,
    completed: Option<bool>,
    compressed_count: Option<usize>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DoneEventData {
    text: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum MetaTone {
    Info,
    Success,
    Warning,
    Error,
    Dim,
}

impl MetaTone {
    fn style(self) -> Style {
        match self {
            MetaTone::Info => Style::default().fg(Color::Cyan),
            MetaTone::Success => Style::default().fg(Color::Green),
            MetaTone::Warning => Style::default().fg(Color::Yellow),
            MetaTone::Error => Style::default().fg(Color::Red),
            MetaTone::Dim => Style::default().fg(Color::DarkGray),
        }
    }
}

#[derive(Debug, Clone)]
enum TranscriptEntry {
    User {
        text: String,
        attachments: Vec<ChatAttachmentData>,
    },
    Assistant(String),
    Meta {
        text: String,
        tone: MetaTone,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ChatMode {
    Ready,
    Streaming,
    AwaitingApproval,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ExecutionMode {
    Agent,
    Yolo,
}

impl ExecutionMode {
    fn toggle(self) -> Self {
        match self {
            Self::Agent => Self::Yolo,
            Self::Yolo => Self::Agent,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct AnimationState {
    spinner_frame: usize,
    elapsed_seconds: u64,
    quit_hint_active: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
enum TranscriptTailKey {
    #[default]
    None,
    Streaming {
        version: u64,
    },
    Meta {
        mode: ChatMode,
        spinner_frame: usize,
        elapsed_seconds: u64,
        busy_action: Option<String>,
    },
}

#[derive(Debug, Default)]
struct TranscriptRenderCache {
    width: usize,
    base_revision: u64,
    base_line_count: usize,
    combined_lines: Vec<Line<'static>>,
    tail_key: TranscriptTailKey,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum QuitHintTrigger {
    CtrlC,
    Esc,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum FooterTag {
    QuitHint(QuitHintTrigger),
    SlashSelected,
}

#[derive(Debug, Clone)]
struct HistoryOverlay {
    items: Vec<HistoryItemData>,
    selected: usize,
    visible_start: usize,
    next_cursor: Option<String>,
    has_more: bool,
    loading_more: bool,
}

#[derive(Debug, Clone)]
struct ModelEditorOverlay {
    provider: String,
    current_model: String,
    draft: String,
    cursor: usize,
    error: Option<String>,
}

impl ModelEditorOverlay {
    fn new(provider: String, current_model: String) -> Self {
        let cursor = char_count(&current_model);
        Self {
            provider,
            current_model: current_model.clone(),
            draft: current_model,
            cursor,
            error: None,
        }
    }

    fn normalized_model(&self) -> Option<String> {
        let trimmed = self.draft.trim();
        (!trimmed.is_empty()).then(|| trimmed.to_string())
    }

    fn clear_error(&mut self) {
        self.error = None;
    }

    fn set_error(&mut self, message: String) {
        self.error = Some(message);
    }

    fn delete_to_line_start(&mut self) {
        delete_to_line_start_in_text(&mut self.draft, &mut self.cursor);
        self.clear_error();
    }

    fn move_left(&mut self) {
        self.cursor = self.cursor.saturating_sub(1);
    }

    fn move_right(&mut self) {
        self.cursor = (self.cursor + 1).min(char_count(&self.draft));
    }

    fn move_home(&mut self) {
        self.cursor = 0;
    }

    fn move_end(&mut self) {
        self.cursor = char_count(&self.draft);
    }
}

#[derive(Debug, Clone)]
enum OverlayState {
    None,
    Approval(ApprovalOverlay),
    History(HistoryOverlay),
    ModelEditor(ModelEditorOverlay),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ToolLifecycle {
    Started,
    Finished,
}

#[derive(Debug, Clone)]
enum UiEvent {
    SessionOpened(SessionData),
    SessionAttached(SessionData),
    ConversationUpdated(SessionData),
    ModelUpdated(BootstrapData),
    AssistantDelta(String),
    TerminalPasteResolved {
        pasted_text: String,
        clipboard: Result<ClipboardPasteData, String>,
    },
    ToolStarted(ToolEventData),
    ToolFinished(ToolEventData),
    ApprovalRequested(ToolEventData),
    Compacting(CompactingEventData),
    Cancelled,
    Done(DoneEventData),
    HistoryLoaded {
        data: HistoryListData,
        append: bool,
    },
    FooterMessage(String, MetaTone),
    Error(String),
}

#[derive(Debug, Clone, Copy)]
struct SlashCommand {
    name: &'static str,
    aliases: &'static [&'static str],
    description: &'static str,
}

const SLASH_COMMANDS: &[SlashCommand] = &[
    SlashCommand {
        name: "/cost",
        aliases: &[],
        description: "chat.slash.cost.description",
    },
    SlashCommand {
        name: "/compact",
        aliases: &[],
        description: "chat.slash.compact.description",
    },
    SlashCommand {
        name: "/copy",
        aliases: &[],
        description: "chat.slash.copy.description",
    },
    SlashCommand {
        name: "/resume",
        aliases: &[],
        description: "chat.slash.resume.description",
    },
    SlashCommand {
        name: "/model",
        aliases: &[],
        description: "chat.slash.model.description",
    },
    SlashCommand {
        name: "/login",
        aliases: &[],
        description: "chat.slash.login.description",
    },
    SlashCommand {
        name: "/clear",
        aliases: &["/new"],
        description: "chat.slash.clear.description",
    },
    SlashCommand {
        name: "/sound",
        aliases: &[],
        description: "chat.slash.sound.description",
    },
    SlashCommand {
        name: "/help",
        aliases: &[],
        description: "chat.slash.help.description",
    },
];

const THINKING_FRAMES: &[&str] = &["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];
const HISTORY_PAGE_SIZE: u32 = 24;
const MAX_INPUT_VISIBLE_LINES: usize = 6;
const MAX_PENDING_ATTACHMENTS: usize = 2;
const ATTACHMENT_CARD_HEIGHT: u16 = 3;
const MIN_TWO_COLUMN_ATTACHMENT_WIDTH: u16 = 56;
const MIN_TOOL_STATUS_DISPLAY: Duration = Duration::from_millis(450);
const LARGE_PASTE_CHAR_THRESHOLD: usize = 800;
const LARGE_PASTE_LINE_THRESHOLD: usize = 8;

fn chat_text(key: &str) -> String {
    i18n::t(key)
}

fn chat_format(key: &str, replacements: &[(&str, String)]) -> String {
    let mut text = chat_text(key);
    for (placeholder, value) in replacements {
        text = text.replace(placeholder, value);
    }
    text
}

fn message_count_text(count: usize) -> String {
    match i18n::locale() {
        "en" => {
            if count == 1 {
                "1 message".to_string()
            } else {
                format!("{} messages", count)
            }
        }
        "de" => {
            if count == 1 {
                "1 Nachricht".to_string()
            } else {
                format!("{} Nachrichten", count)
            }
        }
        "fr" => {
            if count == 1 {
                "1 message".to_string()
            } else {
                format!("{} messages", count)
            }
        }
        "ja" => format!("{} 件のメッセージ", count),
        "ko" => format!("메시지 {}개", count),
        "zh-Hant" => format!("{} 條訊息", count),
        _ => format!("{} 条消息", count),
    }
}

fn pasted_text_line_count(text: &str) -> usize {
    if text.is_empty() {
        0
    } else {
        text.chars().filter(|ch| *ch == '\n').count() + 1
    }
}

fn should_collapse_pasted_text(text: &str) -> bool {
    let line_count = pasted_text_line_count(text);
    char_count(text) > LARGE_PASTE_CHAR_THRESHOLD || line_count >= LARGE_PASTE_LINE_THRESHOLD
}

fn format_pending_paste_placeholder(id: usize, text: &str) -> String {
    let line_count = pasted_text_line_count(text);
    let char_count = char_count(text);
    match i18n::locale() {
        "en" => {
            if line_count > 1 {
                format!("[Paste #{id} · {line_count} lines]")
            } else {
                format!("[Paste #{id} · {char_count} chars]")
            }
        }
        _ => {
            if line_count > 1 {
                format!("[粘贴 #{id} · {line_count} 行]")
            } else {
                format!("[粘贴 #{id} · {char_count} 字]")
            }
        }
    }
}

struct ChatApp {
    session_id: String,
    conversation_id: String,
    conversation_title: String,
    provider: String,
    model: String,
    account: Option<String>,
    context_usage: Option<ContextUsageData>,
    conversation_entries: Vec<TranscriptEntry>,
    activities: Vec<TranscriptEntry>,
    input: String,
    input_cursor: usize,
    pending_attachments: Vec<ChatAttachmentData>,
    pending_pastes: Vec<PendingPasteData>,
    next_pending_paste_id: usize,
    input_history: Vec<ComposerHistoryEntry>,
    input_history_index: Option<usize>,
    input_history_draft: ComposerHistoryEntry,
    input_visual_width: u16,
    input_text_area: Option<Rect>,
    slash_selected: usize,
    slash_popup_visible_start: usize,
    slash_popup_hitboxes: Vec<Rect>,
    history_hitboxes: Vec<Rect>,
    overlay: OverlayState,
    approval_input_guard: ApprovalInputGuard,
    mode: ChatMode,
    execution_mode: ExecutionMode,
    footer_message: Option<(String, MetaTone)>,
    footer_tag: Option<FooterTag>,
    busy_action: Option<String>,
    busy_started_at: Option<Instant>,
    busy_action_release_at: Option<Instant>,
    busy_call_id: Option<String>,
    streaming_text: String,
    transcript_revision: u64,
    streaming_revision: u64,
    transcript_cache: TranscriptRenderCache,
    last_assistant_text: Option<String>,
    tool_states: HashMap<String, ToolLifecycle>,
    search_call_count: usize,
    mode_started_at: Option<Instant>,
    auto_scroll: bool,
    scroll: usize,
    body_visible_lines: usize,
    body_total_lines: usize,
    body_scrollbar_area: Option<Rect>,
    dragging_body_scrollbar: bool,
    body_scrollbar_grab_offset: usize,
    created_at: Instant,
    quit_hint_until: Option<Instant>,
    pending_login_request: bool,
    completion_sound_enabled: bool,
    should_quit: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ApprovalDispatch {
    session_id: String,
    call_id: String,
    approved: bool,
    completion: Option<(String, MetaTone)>,
}

include!("chat/app_impl.rs");

struct TerminalGuard {
    terminal: Terminal<CrosstermBackend<Stdout>>,
}

impl TerminalGuard {
    fn enter() -> Result<Self> {
        enable_raw_mode().context(i18n::t("err.chat_raw_mode"))?;
        let mut stdout = io::stdout();
        execute!(
            stdout,
            EnterAlternateScreen,
            EnableMouseCapture,
            EnableBracketedPaste
        )
        .context(i18n::t("err.chat_enter_screen"))?;
        let _ = execute!(
            stdout,
            PushKeyboardEnhancementFlags(
                KeyboardEnhancementFlags::DISAMBIGUATE_ESCAPE_CODES
                    | KeyboardEnhancementFlags::REPORT_EVENT_TYPES
                    | KeyboardEnhancementFlags::REPORT_ALTERNATE_KEYS
            )
        );
        let backend = CrosstermBackend::new(stdout);
        let terminal = Terminal::new(backend).context(i18n::t("err.chat_terminal_init"))?;
        Ok(Self { terminal })
    }

    fn draw(&mut self, app: &mut ChatApp) -> Result<()> {
        match app.overlay {
            OverlayState::None | OverlayState::ModelEditor(_) => {
                let _ = self.terminal.show_cursor();
            }
            OverlayState::Approval(_) | OverlayState::History(_) => {
                let _ = self.terminal.hide_cursor();
            }
        }
        self.terminal.draw(|frame| render(frame, app))?;
        Ok(())
    }

    fn suspend_for_child_tui(&mut self) {
        {
            let backend = self.terminal.backend_mut();
            let _ = execute!(backend, PopKeyboardEnhancementFlags);
            let _ = execute!(backend, DisableBracketedPaste);
            let _ = execute!(backend, DisableMouseCapture, LeaveAlternateScreen);
        }
        while event::poll(Duration::from_millis(0)).unwrap_or(false) {
            let _ = event::read();
        }
        let _ = disable_raw_mode();
        let _ = self.terminal.show_cursor();
    }

    fn resume_after_child_tui(&mut self) -> Result<()> {
        enable_raw_mode().context(i18n::t("err.chat_raw_mode"))?;
        execute!(
            self.terminal.backend_mut(),
            EnterAlternateScreen,
            EnableMouseCapture,
            EnableBracketedPaste
        )
        .context(i18n::t("err.chat_enter_screen"))?;
        let _ = execute!(
            self.terminal.backend_mut(),
            PushKeyboardEnhancementFlags(
                KeyboardEnhancementFlags::DISAMBIGUATE_ESCAPE_CODES
                    | KeyboardEnhancementFlags::REPORT_EVENT_TYPES
                    | KeyboardEnhancementFlags::REPORT_ALTERNATE_KEYS
            )
        );
        self.terminal.clear()?;
        Ok(())
    }
}

impl Drop for TerminalGuard {
    fn drop(&mut self) {
        let _ = execute!(self.terminal.backend_mut(), PopKeyboardEnhancementFlags);
        let _ = execute!(self.terminal.backend_mut(), DisableBracketedPaste);
        let _ = execute!(
            self.terminal.backend_mut(),
            DisableMouseCapture,
            LeaveAlternateScreen
        );
        while event::poll(Duration::from_millis(0)).unwrap_or(false) {
            let _ = event::read();
        }
        let _ = disable_raw_mode();
        let _ = self.terminal.show_cursor();
    }
}

pub async fn run(output: OutputMode) -> Result<()> {
    if matches!(output, OutputMode::Json) {
        bail!(i18n::t("err.chat_json_unsupported"))
    }

    if !io::stdin().is_terminal() || !io::stdout().is_terminal() {
        bail!(i18n::t("err.chat_requires_tty"))
    }

    let primary_client = Arc::new(Mutex::new(DeckClient::new(Config::default())));
    let bootstrap = ensure_bootstrapped(primary_client.clone()).await?;
    let existing_session_id = bootstrap.session_id.clone();
    let existing_conversation_id = bootstrap.conversation_id.clone();
    let mut app = ChatApp::from_bootstrap(bootstrap);
    if let (Some(session_id), Some(conversation_id)) = (
        existing_session_id.as_deref(),
        existing_conversation_id.as_deref(),
    ) {
        let session =
            load_history(primary_client.clone(), Some(session_id), conversation_id).await?;
        handle_ui_event(&mut app, UiEvent::SessionAttached(session));
        app.set_footer(chat_text("chat.footer.session_ready"), MetaTone::Info);
    }
    let (ui_tx, mut ui_rx) = unbounded_channel();
    let mut terminal = TerminalGuard::enter()?;
    let mut needs_redraw = true;
    let mut last_animation_state = None;

    loop {
        needs_redraw |= app.tick();

        while let Ok(message) = ui_rx.try_recv() {
            if let Some(dispatch) = handle_ui_event(&mut app, message) {
                spawn_approval_dispatch(dispatch, ui_tx.clone());
            }
            needs_redraw = true;
        }

        if app.take_login_request() {
            terminal.suspend_for_child_tui();
            let login_result = login::run(OutputMode::Text).await;
            let resume_result = terminal.resume_after_child_tui();
            needs_redraw = true;

            if let Err(error) = resume_result {
                return Err(error);
            }

            match login_result {
                Ok(()) => match fetch_bootstrap(primary_client.clone()).await {
                    Ok(bootstrap) if bootstrap.configured => {
                        app.apply_bootstrap(bootstrap);
                        app.set_footer(chat_text("chat.footer.login_returned"), MetaTone::Success);
                    }
                    Ok(_) => {
                        app.set_footer(
                            chat_text("chat.footer.login_unconfigured"),
                            MetaTone::Warning,
                        );
                    }
                    Err(error) => {
                        app.set_footer(output::render_error_message(&error), MetaTone::Error);
                    }
                },
                Err(error) => {
                    app.set_footer(output::render_error_message(&error), MetaTone::Error);
                }
            }
            continue;
        }

        let animation_state = app.animation_state();
        if animation_state != last_animation_state {
            last_animation_state = animation_state;
            needs_redraw = true;
        }

        if needs_redraw {
            terminal.draw(&mut app)?;
            needs_redraw = false;
        }

        if app.should_quit {
            break;
        }

        if event::poll(app.poll_timeout()).context(i18n::t("err.chat_event_read"))? {
            match event::read().context(i18n::t("err.chat_event_read"))? {
                Event::Key(key) => {
                    handle_key_event(&mut app, key, primary_client.clone(), ui_tx.clone());
                    needs_redraw = true;
                }
                Event::Paste(text) => {
                    handle_paste(&mut app, text, primary_client.clone(), ui_tx.clone());
                    needs_redraw = true;
                }
                Event::Mouse(mouse) => {
                    handle_mouse_event(&mut app, mouse, primary_client.clone(), ui_tx.clone());
                    needs_redraw = true;
                }
                Event::Resize(_, _) => needs_redraw = true,
                _ => {}
            }
        }
    }

    if app.has_session() {
        let _ = close_chat_session(primary_client.clone(), &app.session_id).await;
    }
    Ok(())
}

fn is_mode_cycle_key(key: KeyEvent) -> bool {
    matches!(key.code, KeyCode::BackTab)
        || (matches!(key.code, KeyCode::Tab) && key.modifiers.contains(KeyModifiers::SHIFT))
}

fn handle_key_event(
    app: &mut ChatApp,
    key: KeyEvent,
    primary_client: Arc<Mutex<DeckClient>>,
    ui_tx: UnboundedSender<UiEvent>,
) {
    if matches!(key.kind, KeyEventKind::Release) {
        return;
    }

    if is_mode_cycle_key(key) && !matches!(app.overlay, OverlayState::ModelEditor(_)) {
        if let Some(dispatch) = toggle_execution_mode(app) {
            spawn_approval_dispatch(dispatch, ui_tx);
        }
        return;
    }

    match &mut app.overlay {
        OverlayState::Approval(overlay) => {
            if key.code == KeyCode::Char('c') && key.modifiers.contains(KeyModifiers::CONTROL) {
                app.set_footer(chat_text("chat.footer.approval_pending"), MetaTone::Warning);
                return;
            }

            match key.code {
                KeyCode::Up | KeyCode::Char('k') => {
                    overlay.scroll_up(1);
                }
                KeyCode::Down | KeyCode::Char('j') => {
                    overlay.scroll_down(1);
                }
                KeyCode::PageUp => {
                    overlay.page_up();
                }
                KeyCode::PageDown => {
                    overlay.page_down();
                }
                KeyCode::Home => {
                    overlay.scroll_home();
                }
                KeyCode::End => {
                    overlay.scroll_end();
                }
                KeyCode::Char('Y') | KeyCode::Char('y') | KeyCode::Enter => {
                    let session_id = app.session_id.clone();
                    let call_id = overlay.call_id.clone();
                    app.set_overlay(OverlayState::None);
                    app.mode = ChatMode::Streaming;
                    app.set_footer(
                        chat_text("chat.footer.tool_approved_continue"),
                        MetaTone::Info,
                    );
                    spawn_approval_dispatch(
                        ApprovalDispatch {
                            session_id,
                            call_id,
                            approved: true,
                            completion: Some((
                                chat_text("chat.footer.tool_approved"),
                                MetaTone::Info,
                            )),
                        },
                        ui_tx,
                    );
                }
                KeyCode::Char('N') | KeyCode::Char('n') | KeyCode::Esc => {
                    let session_id = app.session_id.clone();
                    let call_id = overlay.call_id.clone();
                    app.set_overlay(OverlayState::None);
                    app.mode = ChatMode::Streaming;
                    app.set_footer(chat_text("chat.footer.tool_rejected"), MetaTone::Warning);
                    spawn_approval_dispatch(
                        ApprovalDispatch {
                            session_id,
                            call_id,
                            approved: false,
                            completion: Some((
                                chat_text("chat.footer.tool_rejected"),
                                MetaTone::Warning,
                            )),
                        },
                        ui_tx,
                    );
                }
                _ => {}
            }
            return;
        }
        OverlayState::History(overlay) => {
            let mut moved = false;
            match key.code {
                KeyCode::Char('c') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                    app.set_overlay(OverlayState::None);
                    app.clear_quit_hint();
                    app.set_footer(chat_text("chat.footer.history_closed"), MetaTone::Dim);
                }
                KeyCode::Esc => {
                    app.set_overlay(OverlayState::None);
                    app.clear_quit_hint();
                    app.set_footer(chat_text("chat.footer.history_closed"), MetaTone::Dim);
                }
                KeyCode::Up | KeyCode::Char('k') => {
                    if overlay.selected > 0 {
                        overlay.selected -= 1;
                        moved = true;
                    }
                }
                KeyCode::Down | KeyCode::Char('j') => {
                    if overlay.selected + 1 < overlay.items.len() {
                        overlay.selected += 1;
                        moved = true;
                    }
                }
                KeyCode::PageUp => {
                    overlay.selected = overlay.selected.saturating_sub(8);
                    moved = true;
                }
                KeyCode::PageDown => {
                    overlay.selected =
                        (overlay.selected + 8).min(overlay.items.len().saturating_sub(1));
                    moved = true;
                }
                KeyCode::Home => {
                    overlay.selected = 0;
                    moved = true;
                }
                KeyCode::End => {
                    overlay.selected = overlay.items.len().saturating_sub(1);
                    moved = true;
                }
                KeyCode::Enter => {
                    if let Some(item) = overlay.items.get(overlay.selected).cloned() {
                        app.set_overlay(OverlayState::None);
                        app.set_busy_action(chat_text("chat.busy.restoring_history"));
                        let session_id = if app.has_session() {
                            Some(app.session_id.clone())
                        } else {
                            None
                        };
                        let load_client = primary_client.clone();
                        let load_tx = ui_tx.clone();
                        tokio::spawn(async move {
                            let event =
                                match load_history(load_client, session_id.as_deref(), &item.id)
                                    .await
                                {
                                    Ok(session) => UiEvent::SessionOpened(session),
                                    Err(error) => ui_error(error),
                                };
                            let _ = load_tx.send(event);
                        });
                    }
                }
                _ => {}
            }

            if moved {
                app.clear_quit_hint();
                maybe_request_more_history(app, primary_client, ui_tx);
            }
            return;
        }
        OverlayState::ModelEditor(overlay) => {
            if key.code == KeyCode::Char('c') && key.modifiers.contains(KeyModifiers::CONTROL) {
                app.set_overlay(OverlayState::None);
                app.clear_quit_hint();
                app.set_footer(chat_text("chat.footer.model_cancelled"), MetaTone::Dim);
                return;
            }

            match key.code {
                KeyCode::Esc => {
                    app.set_overlay(OverlayState::None);
                    app.clear_quit_hint();
                    app.set_footer(chat_text("chat.footer.model_cancelled"), MetaTone::Dim);
                }
                KeyCode::Enter => {
                    let Some(model) = overlay.normalized_model() else {
                        overlay.set_error(chat_text("chat.model.error.empty"));
                        return;
                    };

                    let provider = overlay.provider.clone();
                    app.set_overlay(OverlayState::None);
                    app.clear_quit_hint();
                    app.set_busy_action(chat_text("chat.busy.updating_model"));
                    tokio::spawn(async move {
                        let event = match update_current_provider_model(
                            primary_client.clone(),
                            &provider,
                            &model,
                        )
                        .await
                        {
                            Ok(bootstrap) => UiEvent::ModelUpdated(bootstrap),
                            Err(error) => ui_error(error),
                        };
                        let _ = ui_tx.send(event);
                    });
                }
                KeyCode::Backspace => {
                    if key.modifiers.contains(KeyModifiers::SUPER) {
                        overlay.delete_to_line_start();
                        return;
                    }
                    overlay.clear_error();
                    delete_before_cursor(&mut overlay.draft, &mut overlay.cursor);
                }
                KeyCode::Delete => {
                    if key.modifiers.contains(KeyModifiers::SUPER) {
                        overlay.delete_to_line_start();
                        return;
                    }
                    overlay.clear_error();
                    delete_at_cursor(&mut overlay.draft, overlay.cursor);
                }
                KeyCode::Left => {
                    overlay.move_left();
                }
                KeyCode::Right => {
                    overlay.move_right();
                }
                KeyCode::Home => {
                    overlay.move_home();
                }
                KeyCode::End => {
                    overlay.move_end();
                }
                KeyCode::Char('u') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                    overlay.delete_to_line_start();
                }
                KeyCode::Char(ch)
                    if !key.modifiers.contains(KeyModifiers::CONTROL)
                        && !key.modifiers.contains(KeyModifiers::ALT)
                        && !key.modifiers.contains(KeyModifiers::SUPER) =>
                {
                    overlay.clear_error();
                    insert_char_at(&mut overlay.draft, &mut overlay.cursor, ch);
                }
                _ => {}
            }
            return;
        }
        OverlayState::None => {}
    }

    if key.code == KeyCode::Char('c') && key.modifiers.contains(KeyModifiers::CONTROL) {
        if app.mode != ChatMode::Ready {
            if app.has_session() {
                let session_id = app.session_id.clone();
                app.set_footer(chat_text("chat.footer.interrupting"), MetaTone::Warning);
                tokio::spawn(async move {
                    if let Err(error) = cancel_stream(&session_id).await {
                        let _ = ui_tx.send(ui_error(error));
                    }
                });
            } else {
                app.set_footer(chat_text("chat.footer.creating_session"), MetaTone::Warning);
            }
            return;
        }

        if app.quit_hint_active() {
            app.should_quit = true;
        } else {
            app.arm_quit_hint(QuitHintTrigger::CtrlC);
        }
        return;
    }

    if key.code == KeyCode::Char('o') && key.modifiers.contains(KeyModifiers::CONTROL) {
        open_model_editor_if_available(app);
        return;
    }

    if !app.slash_matches().is_empty() && app.input_history_index.is_none() {
        match key.code {
            KeyCode::Up => {
                app.select_previous_slash();
                return;
            }
            KeyCode::Down => {
                app.select_next_slash();
                return;
            }
            KeyCode::Tab => {
                if let Some(command) = app.complete_selected_slash() {
                    app.set_tagged_footer(
                        chat_format(
                            "chat.footer.slash_selected",
                            &[("{command}", command.to_string())],
                        ),
                        MetaTone::Dim,
                        FooterTag::SlashSelected,
                    );
                }
                return;
            }
            KeyCode::Enter => {
                if app.busy_action.is_some() {
                    app.set_footer(chat_text("chat.footer.busy_wait"), MetaTone::Warning);
                    return;
                }

                let selected = app.selected_slash_command().map(|command| command.name);
                let submitted = app.input.trim().to_string();
                if submitted.is_empty() {
                    return;
                }

                if selected.is_some() && normalize_slash_command(&submitted).is_none() {
                    if let Some(command) = app.complete_selected_slash() {
                        app.set_tagged_footer(
                            chat_format(
                                "chat.footer.slash_selected",
                                &[("{command}", command.to_string())],
                            ),
                            MetaTone::Dim,
                            FooterTag::SlashSelected,
                        );
                    }
                    return;
                }
            }
            _ => {}
        }
    }

    match key.code {
        KeyCode::Enter
            if key.modifiers.contains(KeyModifiers::ALT)
                || key.modifiers.contains(KeyModifiers::SHIFT)
                || key.modifiers.contains(KeyModifiers::SUPER) =>
        {
            app.insert_text("\n");
        }
        KeyCode::Esc => {
            if app.slash_query().is_some() {
                app.clear_input_text();
                app.set_footer(chat_text("chat.footer.slash_cancelled"), MetaTone::Dim);
            } else if app.mode == ChatMode::Streaming || app.mode == ChatMode::AwaitingApproval {
                if app.has_session() {
                    let session_id = app.session_id.clone();
                    app.set_footer(chat_text("chat.footer.stopping"), MetaTone::Warning);
                    tokio::spawn(async move {
                        if let Err(error) = cancel_stream(&session_id).await {
                            let _ = ui_tx.send(ui_error(error));
                        }
                    });
                } else {
                    app.set_footer(chat_text("chat.footer.creating_session"), MetaTone::Warning);
                }
            } else {
                if app.quit_hint_active() {
                    app.should_quit = true;
                } else {
                    app.arm_quit_hint(QuitHintTrigger::Esc);
                }
            }
        }
        KeyCode::PageUp => {
            app.scroll_up(8);
        }
        KeyCode::PageDown => {
            app.scroll_down(8);
        }
        KeyCode::Up => {
            if app.input_history_index.is_some() || app.input.is_empty() {
                let _ = app.browse_input_history_up();
            } else {
                app.move_cursor_up_line();
            }
        }
        KeyCode::Down => {
            if app.input_history_index.is_some() || app.input.is_empty() {
                let _ = app.browse_input_history_down();
            } else {
                app.move_cursor_down_line();
            }
        }
        KeyCode::Home if key.modifiers.contains(KeyModifiers::CONTROL) => {
            app.auto_scroll = false;
            app.scroll = 0;
        }
        KeyCode::End if key.modifiers.contains(KeyModifiers::CONTROL) => app.follow_output(),
        KeyCode::Backspace => {
            if key.modifiers.contains(KeyModifiers::SUPER) {
                app.delete_to_line_start();
                return;
            }
            if app.input.is_empty() && app.clear_pending_attachment() {
                app.set_footer(chat_text("chat.footer.attachment_removed"), MetaTone::Dim);
                return;
            }
            app.backspace();
        }
        KeyCode::Char('u') if key.modifiers.contains(KeyModifiers::CONTROL) => {
            app.delete_to_line_start();
        }
        KeyCode::Delete => {
            if key.modifiers.contains(KeyModifiers::SUPER) {
                app.delete_to_line_start();
                return;
            }
            if app.input.is_empty() && app.clear_pending_attachment() {
                app.set_footer(chat_text("chat.footer.attachment_removed"), MetaTone::Dim);
                return;
            }
            app.delete_forward();
        }
        KeyCode::Left => {
            app.move_cursor_left();
        }
        KeyCode::Right => {
            app.move_cursor_right();
        }
        KeyCode::Home => {
            app.move_cursor_start();
        }
        KeyCode::End => {
            app.move_cursor_end();
        }
        KeyCode::Enter => {
            if app.busy_action.is_some() {
                app.set_footer(chat_text("chat.footer.busy_wait"), MetaTone::Warning);
                return;
            }

            let submitted_display = app.input.trim().to_string();
            let submitted = app.expand_input_with_pending_pastes().trim().to_string();
            let pending_attachments = app.pending_attachments.clone();
            if submitted.is_empty() && pending_attachments.is_empty() {
                return;
            }
            if !submitted.starts_with('/') && app.mode != ChatMode::Ready {
                app.set_footer(
                    chat_text("chat.footer.reply_incomplete_stop"),
                    MetaTone::Warning,
                );
                return;
            }
            app.remember_input(&submitted_display);
            app.clear_composer();

            if submitted.starts_with('/') {
                handle_slash_command(app, submitted, primary_client, ui_tx);
                return;
            }

            let existing_session_id = app.session_id.clone();
            app.begin_send();
            tokio::spawn(async move {
                let session_id = if existing_session_id.is_empty() {
                    match open_chat_session(primary_client.clone(), None, None, true).await {
                        Ok(session) => {
                            let session_id = session.session_id.clone();
                            let _ = ui_tx.send(UiEvent::SessionAttached(session));
                            session_id
                        }
                        Err(error) => {
                            let _ = ui_tx.send(ui_error(error));
                            return;
                        }
                    }
                } else {
                    existing_session_id
                };

                let event = match send_chat_message(
                    primary_client,
                    &session_id,
                    submitted,
                    pending_attachments,
                    ui_tx.clone(),
                )
                .await
                {
                    Ok(()) => return,
                    Err(error) => ui_error(error),
                };
                let _ = ui_tx.send(event);
            });
        }
        KeyCode::Char(ch)
            if !key.modifiers.contains(KeyModifiers::CONTROL)
                && !key.modifiers.contains(KeyModifiers::ALT)
                && !key.modifiers.contains(KeyModifiers::SUPER) =>
        {
            app.insert_char(ch);
        }
        _ => {}
    }
}

fn handle_paste(
    app: &mut ChatApp,
    text: String,
    primary_client: Arc<Mutex<DeckClient>>,
    ui_tx: UnboundedSender<UiEvent>,
) {
    if let OverlayState::ModelEditor(overlay) = &mut app.overlay {
        let sanitized: String = text
            .chars()
            .filter(|ch| *ch != '\n' && *ch != '\r')
            .collect();
        if !sanitized.is_empty() {
            overlay.clear_error();
            insert_text_at(&mut overlay.draft, &mut overlay.cursor, &sanitized);
        }
        return;
    }

    if !matches!(app.overlay, OverlayState::None) {
        return;
    }
    tokio::spawn(async move {
        let clipboard = read_chat_clipboard(primary_client)
            .await
            .map_err(|error| output::render_error_message(&error));
        let _ = ui_tx.send(UiEvent::TerminalPasteResolved {
            pasted_text: text,
            clipboard,
        });
    });
}

fn handle_mouse_event(
    app: &mut ChatApp,
    mouse: MouseEvent,
    primary_client: Arc<Mutex<DeckClient>>,
    ui_tx: UnboundedSender<UiEvent>,
) {
    match mouse.kind {
        MouseEventKind::Down(MouseButton::Left) => {
            if let Some(index) = app.history_hitbox_index(mouse.column, mouse.row) {
                if let OverlayState::History(overlay) = &mut app.overlay {
                    let item_index = overlay.visible_start + index;
                    if item_index < overlay.items.len() {
                        overlay.selected = item_index;
                        app.clear_quit_hint();
                        maybe_request_more_history(app, primary_client, ui_tx);
                    }
                }
                return;
            }

            if !matches!(app.overlay, OverlayState::None) {
                return;
            }

            if let Some(index) = app.slash_hitbox_index(mouse.column, mouse.row) {
                let matches_len = app.slash_matches().len();
                if matches_len == 0 {
                    return;
                }
                app.slash_selected =
                    (app.slash_popup_visible_start + index).min(matches_len.saturating_sub(1));
                if let Some(command) = app.complete_selected_slash() {
                    app.set_tagged_footer(
                        chat_format(
                            "chat.footer.slash_selected",
                            &[("{command}", command.to_string())],
                        ),
                        MetaTone::Dim,
                        FooterTag::SlashSelected,
                    );
                }
                return;
            }

            if app.start_body_scrollbar_drag(mouse.column, mouse.row) {
                return;
            }

            let _ = app.move_cursor_to_pointer(mouse.column, mouse.row);
        }
        MouseEventKind::Drag(MouseButton::Left) => {
            if matches!(app.overlay, OverlayState::None) {
                let _ = app.drag_body_scrollbar(mouse.row);
            }
        }
        MouseEventKind::Up(MouseButton::Left) => {
            app.stop_body_scrollbar_drag();
        }
        MouseEventKind::ScrollUp => match &mut app.overlay {
            OverlayState::History(overlay) => {
                if overlay.selected > 0 {
                    overlay.selected -= 1;
                }
                app.clear_quit_hint();
            }
            OverlayState::Approval(overlay) => {
                if overlay
                    .preview_area
                    .is_some_and(|rect| point_in_rect(mouse.column, mouse.row, rect))
                {
                    overlay.scroll_up(3);
                }
            }
            OverlayState::None => {
                if !app.slash_matches().is_empty()
                    && app.input_history_index.is_none()
                    && app.slash_hitbox_index(mouse.column, mouse.row).is_some()
                {
                    app.select_previous_slash();
                    app.clear_quit_hint();
                } else {
                    app.scroll_up(3);
                }
            }
            OverlayState::ModelEditor(_) => {}
        },
        MouseEventKind::ScrollDown => match &mut app.overlay {
            OverlayState::History(overlay) => {
                if overlay.selected + 1 < overlay.items.len() {
                    overlay.selected += 1;
                }
                app.clear_quit_hint();
                maybe_request_more_history(app, primary_client, ui_tx);
            }
            OverlayState::Approval(overlay) => {
                if overlay
                    .preview_area
                    .is_some_and(|rect| point_in_rect(mouse.column, mouse.row, rect))
                {
                    overlay.scroll_down(3);
                }
            }
            OverlayState::None => {
                if !app.slash_matches().is_empty()
                    && app.input_history_index.is_none()
                    && app.slash_hitbox_index(mouse.column, mouse.row).is_some()
                {
                    app.select_next_slash();
                    app.clear_quit_hint();
                } else {
                    app.scroll_down(3);
                }
            }
            OverlayState::ModelEditor(_) => {}
        },
        _ => {}
    }
}

fn handle_slash_command(
    app: &mut ChatApp,
    input: String,
    primary_client: Arc<Mutex<DeckClient>>,
    ui_tx: UnboundedSender<UiEvent>,
) {
    let command = match normalize_slash_command(input.trim()) {
        Some(command) => command,
        None => {
            app.set_footer(chat_text("chat.footer.unknown_command"), MetaTone::Warning);
            return;
        }
    };

    match command {
        "/help" => {
            app.push_activity(chat_text("chat.activity.help_commands"), MetaTone::Dim);
            app.set_footer(chat_text("chat.footer.help_shown"), MetaTone::Dim);
        }
        "/model" => {
            open_model_editor_if_available(app);
        }
        "/login" => {
            if app.mode != ChatMode::Ready {
                app.set_footer(
                    chat_text("chat.footer.cannot_login_while_replying"),
                    MetaTone::Warning,
                );
                return;
            }

            app.request_login();
        }
        "/cost" => {
            if let Some(usage) = &app.context_usage {
                app.set_footer(
                    chat_format(
                        "chat.footer.context_usage",
                        &[
                            ("{usage}", usage.usage_percent_text.clone()),
                            ("{tokens}", usage.estimated_tokens.to_string()),
                            ("{window}", usage.context_window_size.to_string()),
                        ],
                    ),
                    MetaTone::Info,
                );
            } else {
                app.set_footer(chat_text("chat.footer.no_context_usage"), MetaTone::Dim);
            }
        }
        "/copy" => match app.last_assistant_text.clone() {
            Some(text) if !text.trim().is_empty() => match copy_to_system_clipboard(&text) {
                Ok(()) => app.set_footer(
                    chat_text("chat.footer.copied_last_reply"),
                    MetaTone::Success,
                ),
                Err(error) => app.set_footer(error.to_string(), MetaTone::Error),
            },
            _ => app.set_footer(chat_text("chat.footer.no_reply_to_copy"), MetaTone::Warning),
        },
        "/clear" => {
            if app.mode != ChatMode::Ready {
                app.set_footer(
                    chat_text("chat.footer.cannot_clear_while_replying"),
                    MetaTone::Warning,
                );
                return;
            }

            let session_id = if app.has_session() {
                Some(app.session_id.clone())
            } else {
                None
            };
            app.reset_to_empty_conversation();
            app.set_footer(
                chat_text("chat.footer.cleared_new_message_creates_session"),
                MetaTone::Success,
            );

            if let Some(session_id) = session_id {
                app.set_busy_action(chat_text("chat.busy.clearing_session"));
                tokio::spawn(async move {
                    let _ = close_chat_session(primary_client, &session_id).await;
                    let _ = ui_tx.send(UiEvent::FooterMessage(
                        chat_text("chat.footer.blank_conversation_ready"),
                        MetaTone::Success,
                    ));
                });
            }
        }
        "/sound" => {
            app.completion_sound_enabled = !app.completion_sound_enabled;
            let key = if app.completion_sound_enabled {
                "chat.footer.sound_on"
            } else {
                "chat.footer.sound_off"
            };
            app.set_footer(chat_text(key), MetaTone::Success);
        }
        "/resume" => {
            if app.mode != ChatMode::Ready {
                app.set_footer(
                    chat_text("chat.footer.cannot_resume_while_replying"),
                    MetaTone::Warning,
                );
                return;
            }

            app.set_busy_action(chat_text("chat.busy.loading_history"));
            tokio::spawn(async move {
                let event =
                    match list_history(primary_client, None, None, Some(HISTORY_PAGE_SIZE)).await {
                        Ok(history) => UiEvent::HistoryLoaded {
                            data: history,
                            append: false,
                        },
                        Err(error) => ui_error(error),
                    };
                let _ = ui_tx.send(event);
            });
        }
        "/compact" => {
            if app.mode != ChatMode::Ready {
                app.set_footer(
                    chat_text("chat.footer.cannot_compact_while_replying"),
                    MetaTone::Warning,
                );
                return;
            }

            if !app.has_session() {
                app.set_footer(
                    chat_text("chat.footer.nothing_to_compact"),
                    MetaTone::Warning,
                );
                return;
            }

            app.set_busy_action(chat_text("chat.busy.compacting"));
            let session_id = app.session_id.clone();
            tokio::spawn(async move {
                let event = match compact_session(primary_client, &session_id).await {
                    Ok(session) => UiEvent::SessionOpened(session),
                    Err(error) => ui_error(error),
                };
                let _ = ui_tx.send(event);
            });
        }
        _ => app.set_footer(chat_text("chat.footer.unknown_command"), MetaTone::Warning),
    }
}

fn tool_display_text_by_name(tool: &str) -> String {
    match tool {
        "write_clipboard" => chat_text("chat.tool.writing_clipboard"),
        "delete_clipboard" => chat_text("chat.tool.deleting_clipboard"),
        "list_script_plugins" => chat_text("chat.tool.listing_plugins"),
        "read_script_plugin" => chat_text("chat.tool.reading_plugin"),
        "read_skill_detail" => chat_text("chat.tool.reading_skill"),
        "record_memory" => chat_text("chat.tool.saving_memory"),
        "delete_memory" => chat_text("chat.tool.deleting_memory"),
        "save_session_context" => chat_text("chat.tool.saving_session_context"),
        "read_session_context" => chat_text("chat.tool.reading_session_context"),
        "delete_session_context" => chat_text("chat.tool.deleting_session_context"),
        "run_script_transform" => chat_text("chat.tool.running_script_plugin"),
        "generate_script_plugin" => chat_text("chat.tool.creating_script_plugin"),
        "modify_script_plugin" => chat_text("chat.tool.modifying_script_plugin"),
        "delete_script_plugin" => chat_text("chat.tool.deleting_script_plugin"),
        "generate_smart_rule" => chat_text("chat.tool.creating_smart_rule"),
        "list_smart_rules" => chat_text("chat.tool.listing_smart_rules"),
        "read_smart_rule" => chat_text("chat.tool.reading_smart_rule"),
        "modify_smart_rule" => chat_text("chat.tool.modifying_smart_rule"),
        "delete_smart_rule" => chat_text("chat.tool.deleting_smart_rule"),
        _ => chat_format("chat.tool.running", &[("{tool}", tool.to_string())]),
    }
}

fn auto_approve_tool_call(app: &mut ChatApp, call_id: String) -> ApprovalDispatch {
    app.set_overlay(OverlayState::None);
    app.mode = ChatMode::Streaming;
    if app.mode_started_at.is_none() {
        app.mode_started_at = Some(Instant::now());
    }

    ApprovalDispatch {
        session_id: app.session_id.clone(),
        call_id,
        approved: true,
        completion: None,
    }
}

fn toggle_execution_mode(app: &mut ChatApp) -> Option<ApprovalDispatch> {
    app.execution_mode = app.execution_mode.toggle();
    app.clear_quit_hint();

    match app.execution_mode {
        ExecutionMode::Agent => {
            app.set_footer(chat_text("chat.footer.execution.agent"), MetaTone::Dim);
            None
        }
        ExecutionMode::Yolo => {
            let pending_approval = match &app.overlay {
                OverlayState::Approval(overlay) => Some(overlay.call_id.clone()),
                _ => None,
            };

            if let Some(call_id) = pending_approval {
                app.set_footer(chat_text("chat.footer.execution.yolo"), MetaTone::Warning);
                Some(auto_approve_tool_call(app, call_id))
            } else {
                app.set_footer(chat_text("chat.footer.execution.yolo"), MetaTone::Warning);
                None
            }
        }
    }
}

fn spawn_approval_dispatch(dispatch: ApprovalDispatch, ui_tx: UnboundedSender<UiEvent>) {
    tokio::spawn(async move {
        let event =
            match respond_to_approval(&dispatch.session_id, &dispatch.call_id, dispatch.approved)
                .await
            {
                Ok(()) => match dispatch.completion {
                    Some((message, tone)) => Some(UiEvent::FooterMessage(message, tone)),
                    None => None,
                },
                Err(error) => Some(ui_error(error)),
            };
        if let Some(event) = event {
            let _ = ui_tx.send(event);
        }
    });
}

fn handle_ui_event(app: &mut ChatApp, event: UiEvent) -> Option<ApprovalDispatch> {
    match event {
        UiEvent::SessionOpened(session) => {
            app.replace_session(session, true);
            app.clear_busy_action();
            app.set_footer(chat_text("chat.footer.session_ready"), MetaTone::Success);
        }
        UiEvent::SessionAttached(session) => {
            app.replace_session(session, false);
        }
        UiEvent::ConversationUpdated(session) => {
            app.conversation_updated(session);
        }
        UiEvent::ModelUpdated(bootstrap) => {
            app.clear_busy_action();
            app.apply_bootstrap(bootstrap);
            app.set_footer(
                chat_format(
                    "chat.footer.model_updated",
                    &[("{model}", app.model.clone())],
                ),
                MetaTone::Success,
            );
        }
        UiEvent::AssistantDelta(delta) => {
            app.streaming_text.push_str(&delta);
            app.bump_streaming_revision();
        }
        UiEvent::TerminalPasteResolved {
            pasted_text,
            clipboard,
        } => match clipboard {
            Ok(data) => {
                let attachments = data.normalized_attachments();
                let has_attachment = !attachments.is_empty();
                let pasted_text_is_path_payload =
                    !pasted_text.is_empty() && looks_like_path_payload(&pasted_text);

                if has_attachment {
                    let added = app.append_pending_attachments(attachments);
                    if added > 0 {
                        app.set_footer(
                            chat_text("chat.footer.attachment_ready"),
                            MetaTone::Success,
                        );
                    } else if app.pending_attachments_full() {
                        app.set_footer(
                            chat_text("chat.footer.attachment_limit_reached"),
                            MetaTone::Warning,
                        );
                    }
                } else if !pasted_text.is_empty() && !pasted_text_is_path_payload {
                    if app.insert_paste_text(&pasted_text) {
                        app.set_footer(
                            chat_text("chat.footer.clipboard_text_compact"),
                            MetaTone::Success,
                        );
                    }
                } else if pasted_text_is_path_payload {
                    if let Some(text) = data.text.filter(|text| !text.is_empty()) {
                        let collapsed = app.insert_paste_text(&text);
                        app.set_footer(
                            chat_text(if collapsed {
                                "chat.footer.clipboard_text_compact"
                            } else {
                                "chat.footer.clipboard_text_pasted"
                            }),
                            MetaTone::Success,
                        );
                    } else {
                        app.set_footer(chat_text("chat.footer.clipboard_empty"), MetaTone::Warning);
                    }
                } else if !pasted_text.is_empty() {
                    app.set_footer(chat_text("chat.footer.clipboard_empty"), MetaTone::Warning);
                }

                if has_attachment && !pasted_text.trim().is_empty() {
                    app.clear_quit_hint();
                }
            }
            Err(message) => {
                if !pasted_text.is_empty() && !looks_like_path_payload(&pasted_text) {
                    let _ = app.insert_paste_text(&pasted_text);
                }
                app.set_footer(message, MetaTone::Warning);
            }
        },
        UiEvent::ToolStarted(tool) => {
            if app.tool_states.contains_key(&tool.call_id) {
                return None;
            }
            app.tool_states
                .insert(tool.call_id.clone(), ToolLifecycle::Started);
            app.show_tool_status(&tool);
        }
        UiEvent::ToolFinished(tool) => {
            if matches!(
                app.tool_states.get(&tool.call_id),
                Some(ToolLifecycle::Finished)
            ) {
                return None;
            }
            app.tool_states
                .insert(tool.call_id.clone(), ToolLifecycle::Finished);
            app.finish_tool_status(&tool.call_id);
        }
        UiEvent::ApprovalRequested(tool) => {
            if app.execution_mode == ExecutionMode::Yolo {
                let call_id = tool.call_id;
                return Some(auto_approve_tool_call(app, call_id));
            }

            app.mode = ChatMode::AwaitingApproval;
            if app.mode_started_at.is_none() {
                app.mode_started_at = Some(Instant::now());
            }
            app.set_overlay(OverlayState::Approval(ApprovalOverlay::from_tool(&tool)));
            app.set_footer(
                chat_text("chat.footer.approval_required"),
                MetaTone::Warning,
            );
        }
        UiEvent::Compacting(data) => {
            if data.completed == Some(true) {
                let suffix = data
                    .compressed_count
                    .map(|count| {
                        chat_format(
                            "chat.footer.compact_done_suffix",
                            &[("{count}", count.to_string())],
                        )
                    })
                    .unwrap_or_default();
                app.set_footer(
                    chat_format("chat.footer.compact_done", &[("{suffix}", suffix)]),
                    MetaTone::Success,
                );
            } else if data.attempt > 0 {
                app.set_footer(
                    chat_format(
                        "chat.footer.compacting_attempt",
                        &[("{attempt}", data.attempt.to_string())],
                    ),
                    MetaTone::Info,
                );
            }
        }
        UiEvent::Cancelled => {
            app.finish_send();
            app.set_footer(chat_text("chat.footer.reply_cancelled"), MetaTone::Warning);
        }
        UiEvent::Done(done) => {
            app.last_assistant_text = Some(done.text);
            app.finish_send();
            app.set_footer(chat_text("chat.footer.round_done"), MetaTone::Success);
            if app.completion_sound_enabled {
                crate::completion_sound::play();
            }
        }
        UiEvent::HistoryLoaded { data, append } => {
            app.clear_busy_action();
            if data.items.is_empty() && !append {
                app.set_footer(chat_text("chat.footer.no_history"), MetaTone::Dim);
            } else if append {
                if let OverlayState::History(overlay) = &mut app.overlay {
                    overlay.loading_more = false;
                    overlay.has_more = data.has_more;
                    overlay.next_cursor = data.next_cursor;
                    overlay.items.extend(data.items);
                    app.set_footer(chat_text("chat.footer.history_loaded_more"), MetaTone::Dim);
                }
            } else {
                app.set_overlay(OverlayState::History(HistoryOverlay {
                    items: data.items,
                    selected: 0,
                    visible_start: 0,
                    next_cursor: data.next_cursor,
                    has_more: data.has_more,
                    loading_more: false,
                }));
                app.set_footer(chat_text("chat.footer.history_choose"), MetaTone::Info);
            }
        }
        UiEvent::FooterMessage(message, tone) => {
            app.clear_busy_action();
            app.set_footer(message, tone);
        }
        UiEvent::Error(message) => {
            if let OverlayState::History(overlay) = &mut app.overlay {
                overlay.loading_more = false;
            }
            app.clear_busy_action();
            app.finish_send();
            app.push_activity(message.clone(), MetaTone::Error);
            app.set_footer(message, MetaTone::Error);
        }
    }

    None
}

fn maybe_request_more_history(
    app: &mut ChatApp,
    primary_client: Arc<Mutex<DeckClient>>,
    ui_tx: UnboundedSender<UiEvent>,
) {
    let cursor = match &mut app.overlay {
        OverlayState::History(overlay)
            if overlay.has_more
                && !overlay.loading_more
                && overlay.items.len().saturating_sub(overlay.selected + 1) <= 4 =>
        {
            overlay.loading_more = true;
            overlay.next_cursor.clone()
        }
        _ => None,
    };

    let Some(cursor) = cursor else {
        return;
    };

    tokio::spawn(async move {
        let event = match list_history(
            primary_client,
            None,
            Some(cursor.as_str()),
            Some(HISTORY_PAGE_SIZE),
        )
        .await
        {
            Ok(history) => UiEvent::HistoryLoaded {
                data: history,
                append: true,
            },
            Err(error) => ui_error(error),
        };
        let _ = ui_tx.send(event);
    });
}

async fn ensure_bootstrapped(client: Arc<Mutex<DeckClient>>) -> Result<BootstrapData> {
    let bootstrap = fetch_bootstrap(client.clone()).await?;
    if bootstrap.busy == Some(true) && !has_resumable_session(&bootstrap) {
        bail!(i18n::t("err.chat_busy"))
    }
    if bootstrap.configured {
        return Ok(bootstrap);
    }

    login::run(OutputMode::Text).await?;

    let bootstrap = fetch_bootstrap(client).await?;
    if !bootstrap.configured {
        bail!(i18n::t("err.chat_provider_unconfigured"))
    }
    if bootstrap.busy == Some(true) && !has_resumable_session(&bootstrap) {
        bail!(i18n::t("err.chat_busy"))
    }
    Ok(bootstrap)
}

fn has_resumable_session(bootstrap: &BootstrapData) -> bool {
    bootstrap.session_id.is_some() && bootstrap.conversation_id.is_some()
}

fn ui_error(error: anyhow::Error) -> UiEvent {
    UiEvent::Error(output::render_error_message(&error))
}

async fn fetch_bootstrap(client: Arc<Mutex<DeckClient>>) -> Result<BootstrapData> {
    let response = {
        let mut client = client.lock().await;
        client.chat_bootstrap().await?
    };
    response_data(response)
}

async fn update_current_provider_model(
    client: Arc<Mutex<DeckClient>>,
    provider: &str,
    model: &str,
) -> Result<BootstrapData> {
    let provider = provider.to_string();
    let model = model.trim().to_string();
    tokio::task::spawn_blocking(move || persist_current_provider_model(&provider, &model))
        .await
        .context(i18n::t("err.chat_unexpected_stream_response"))??;
    fetch_bootstrap(client).await
}

fn persist_current_provider_model(provider: &str, model: &str) -> Result<()> {
    const DECK_PREFS_DOMAIN: &str = "com.yuzeguitar.Deck";

    let key = deck_model_defaults_key(provider)
        .ok_or_else(|| anyhow!(chat_text("chat.model.error.unsupported_provider")))?;
    if model.trim().is_empty() {
        bail!(chat_text("chat.model.error.empty"));
    }

    let output = Command::new("/usr/bin/defaults")
        .args(["write", DECK_PREFS_DOMAIN, key, "-string", model])
        .output()
        .context(chat_text("chat.model.error.write_failed"))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        if stderr.is_empty() {
            bail!(chat_text("chat.model.error.write_failed"));
        }
        bail!(stderr);
    }

    Ok(())
}

fn deck_model_defaults_key(provider: &str) -> Option<&'static str> {
    match provider {
        "chatgpt" => Some("aiChatGPTModel"),
        "openai_api" => Some("aiOpenAIModel"),
        "anthropic" => Some("aiAnthropicModel"),
        "ollama" => Some("aiOllamaModel"),
        _ => None,
    }
}

async fn open_chat_session(
    client: Arc<Mutex<DeckClient>>,
    session_id: Option<&str>,
    conversation_id: Option<&str>,
    create_new: bool,
) -> Result<SessionData> {
    let response = {
        let mut client = client.lock().await;
        client
            .chat_open(session_id, conversation_id, create_new)
            .await?
    };
    response_data(response)
}

async fn list_history(
    client: Arc<Mutex<DeckClient>>,
    query: Option<&str>,
    cursor: Option<&str>,
    limit: Option<u32>,
) -> Result<HistoryListData> {
    let response = {
        let mut client = client.lock().await;
        client.chat_history_list(query, cursor, limit).await?
    };
    response_data(response)
}

async fn load_history(
    client: Arc<Mutex<DeckClient>>,
    session_id: Option<&str>,
    conversation_id: &str,
) -> Result<SessionData> {
    open_chat_session(client, session_id, Some(conversation_id), false).await
}

async fn compact_session(client: Arc<Mutex<DeckClient>>, session_id: &str) -> Result<SessionData> {
    let response = {
        let mut client = client.lock().await;
        client.chat_compact(session_id).await?
    };
    response_data(response)
}

async fn read_chat_clipboard(client: Arc<Mutex<DeckClient>>) -> Result<ClipboardPasteData> {
    let response = {
        let mut client = client.lock().await;
        client.chat_clipboard_read().await?
    };
    response_data(response)
}

async fn close_chat_session(client: Arc<Mutex<DeckClient>>, session_id: &str) -> Result<()> {
    let mut client = client.lock().await;
    let _ = client.chat_close(session_id).await?;
    Ok(())
}

async fn respond_to_approval(session_id: &str, call_id: &str, approved: bool) -> Result<()> {
    let mut client = DeckClient::new(Config::default());
    let _ = client
        .chat_approval_respond(session_id, call_id, approved)
        .await?;
    Ok(())
}

async fn cancel_stream(session_id: &str) -> Result<()> {
    let mut client = DeckClient::new(Config::default());
    let _ = client.chat_cancel(session_id).await?;
    Ok(())
}

fn is_terminal_stream_event(event_name: &str) -> bool {
    matches!(
        event_name,
        chat_event::DONE | chat_event::ERROR | chat_event::CANCELLED
    )
}

async fn send_chat_message(
    client: Arc<Mutex<DeckClient>>,
    session_id: &str,
    text: String,
    attachments: Vec<ChatAttachmentData>,
    ui_tx: UnboundedSender<UiEvent>,
) -> Result<()> {
    let mut client = client.lock().await;
    let attachments = (!attachments.is_empty())
        .then(|| serde_json::to_value(&attachments))
        .transpose()
        .context(i18n::t("err.chat_unexpected_stream_response"))?;
    let _ = client.chat_send(session_id, &text, attachments).await?;

    loop {
        match client.recv_chat_frame().await? {
            ChatStreamFrame::Event(event) => {
                let should_stop = is_terminal_stream_event(event.event.as_str());
                let ui_event = parse_stream_event(event)?;
                let _ = ui_tx.send(ui_event);
                if should_stop {
                    break;
                }
            }
            ChatStreamFrame::Response(response) => {
                if !response.ok {
                    return Err(anyhow!(i18n::t("err.chat_unexpected_stream_response")));
                }
            }
        }
    }

    Ok(())
}

fn parse_stream_event(event: deckclip_protocol::EventFrame) -> Result<UiEvent> {
    let data = event.data.unwrap_or(Value::Object(Default::default()));
    match event.event.as_str() {
        chat_event::ASSISTANT_DELTA => {
            let text = data
                .get("text")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_string();
            Ok(UiEvent::AssistantDelta(text))
        }
        chat_event::CONVERSATION_UPDATED => {
            Ok(UiEvent::ConversationUpdated(serde_json::from_value(data)?))
        }
        chat_event::TOOL_STARTED => Ok(UiEvent::ToolStarted(serde_json::from_value(data)?)),
        chat_event::TOOL_FINISHED => Ok(UiEvent::ToolFinished(serde_json::from_value(data)?)),
        chat_event::APPROVAL_REQUEST => {
            Ok(UiEvent::ApprovalRequested(serde_json::from_value(data)?))
        }
        chat_event::COMPACTING => Ok(UiEvent::Compacting(serde_json::from_value(data)?)),
        chat_event::CANCELLED => Ok(UiEvent::Cancelled),
        chat_event::DONE => Ok(UiEvent::Done(serde_json::from_value(data)?)),
        chat_event::ERROR => {
            let message = data
                .get("message")
                .and_then(Value::as_str)
                .map(str::to_string)
                .unwrap_or_else(|| i18n::t("err.chat_unknown_stream_error"));
            Ok(UiEvent::Error(message))
        }
        other => Ok(UiEvent::FooterMessage(
            i18n::t("err.chat_unrecognized_event").replace("{}", other),
            MetaTone::Warning,
        )),
    }
}

fn response_data<T: DeserializeOwned>(response: deckclip_protocol::Response) -> Result<T> {
    let data = response
        .data
        .ok_or_else(|| anyhow!(i18n::t("err.response_missing_data")))?;
    serde_json::from_value(data).map_err(Into::into)
}

fn slash_command_matches(command: &SlashCommand, query: &str) -> bool {
    command.name.starts_with(query) || command.aliases.iter().any(|alias| alias.starts_with(query))
}

fn normalize_slash_command(command: &str) -> Option<&'static str> {
    let trimmed = command.trim();
    SLASH_COMMANDS.iter().find_map(|candidate| {
        if candidate.name == trimmed || candidate.aliases.iter().any(|alias| *alias == trimmed) {
            Some(candidate.name)
        } else {
            None
        }
    })
}

fn format_elapsed(duration: Duration) -> String {
    let seconds = duration.as_secs();
    if seconds < 60 {
        return format!("{}s", seconds);
    }
    if seconds < 3600 {
        return format!("{}m {:02}s", seconds / 60, seconds % 60);
    }
    format!(
        "{}h {:02}m {:02}s",
        seconds / 3600,
        (seconds % 3600) / 60,
        seconds % 60
    )
}

fn tool_status_text(tool: &ToolEventData, search_call_count: usize) -> String {
    if tool.tool == "search_clipboard" {
        let query = tool
            .parameters
            .get("query")
            .and_then(Value::as_str)
            .map(str::trim)
            .unwrap_or("");
        let base = if query.is_empty() {
            chat_text("chat.tool.searching_clipboard")
        } else {
            chat_format(
                "chat.tool.searching_clipboard_with_query",
                &[("{query}", query.to_string())],
            )
        };
        let suffix = if search_call_count > 1 {
            format!(" +{}", search_call_count - 1)
        } else {
            String::new()
        };
        return format!("{}{}", base, suffix);
    }

    tool_display_text_by_name(&tool.tool)
}

fn last_assistant_from_messages(messages: &[ConversationMessageData]) -> Option<String> {
    messages
        .iter()
        .rev()
        .find(|message| message.role == "assistant" && !message.text.trim().is_empty())
        .map(|message| message.text.clone())
}

fn copy_to_system_clipboard(text: &str) -> Result<()> {
    let mut child = Command::new("pbcopy")
        .stdin(Stdio::piped())
        .spawn()
        .context(i18n::t("err.clipboard_invoke_failed"))?;

    if let Some(stdin) = child.stdin.as_mut() {
        use std::io::Write;
        stdin
            .write_all(text.as_bytes())
            .context(i18n::t("err.clipboard_write_failed"))?;
    }

    let status = child.wait().context(i18n::t("err.clipboard_wait_failed"))?;
    if !status.success() {
        bail!(i18n::t("err.clipboard_copy_failed"))
    }
    Ok(())
}

#[cfg(test)]
#[path = "chat/tests.rs"]
mod tests;
