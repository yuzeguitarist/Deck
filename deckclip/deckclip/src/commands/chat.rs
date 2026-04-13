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
use ratatui::backend::CrosstermBackend;
use ratatui::layout::{Constraint, Direction, Layout, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Clear, List, ListItem, ListState, Paragraph};
use ratatui::{Frame, Terminal};
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use textwrap::Options;
use tokio::sync::mpsc::{unbounded_channel, UnboundedSender};
use tokio::sync::Mutex;
use unicode_width::UnicodeWidthChar;

use approval_input::ApprovalInputGuard;

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
struct ApprovalOverlay {
    call_id: String,
    tool: String,
    preview: String,
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
        name: "/clear",
        aliases: &["/new"],
        description: "chat.slash.clear.description",
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
    input_history: Vec<String>,
    input_history_index: Option<usize>,
    input_history_draft: String,
    input_visual_width: u16,
    input_text_area: Option<Rect>,
    slash_selected: usize,
    slash_popup_visible_start: usize,
    slash_popup_hitboxes: Vec<Rect>,
    history_hitboxes: Vec<Rect>,
    overlay: OverlayState,
    approval_input_guard: ApprovalInputGuard,
    mode: ChatMode,
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
    should_quit: bool,
}

impl ChatApp {
    fn from_bootstrap(bootstrap: BootstrapData) -> Self {
        Self {
            session_id: String::new(),
            conversation_id: String::new(),
            conversation_title: chat_text("chat.conversation.new"),
            provider: bootstrap.provider.unwrap_or_else(|| "AI".to_string()),
            model: bootstrap
                .model
                .unwrap_or_else(|| chat_text("chat.model.not_started")),
            account: bootstrap.account,
            context_usage: None,
            conversation_entries: Vec::new(),
            activities: Vec::new(),
            input: String::new(),
            input_cursor: 0,
            pending_attachments: Vec::new(),
            input_history: Vec::new(),
            input_history_index: None,
            input_history_draft: String::new(),
            input_visual_width: 1,
            input_text_area: None,
            slash_selected: 0,
            slash_popup_visible_start: 0,
            slash_popup_hitboxes: Vec::new(),
            history_hitboxes: Vec::new(),
            overlay: OverlayState::None,
            approval_input_guard: ApprovalInputGuard::default(),
            mode: ChatMode::Ready,
            footer_message: None,
            footer_tag: None,
            busy_action: None,
            busy_started_at: None,
            busy_action_release_at: None,
            busy_call_id: None,
            streaming_text: String::new(),
            transcript_revision: 0,
            streaming_revision: 0,
            transcript_cache: TranscriptRenderCache::default(),
            last_assistant_text: None,
            tool_states: HashMap::new(),
            search_call_count: 0,
            mode_started_at: None,
            auto_scroll: true,
            scroll: 0,
            body_visible_lines: 0,
            body_total_lines: 0,
            body_scrollbar_area: None,
            dragging_body_scrollbar: false,
            body_scrollbar_grab_offset: 0,
            created_at: Instant::now(),
            quit_hint_until: None,
            should_quit: false,
        }
    }

    fn replace_session(&mut self, session: SessionData, clear_ephemeral: bool) {
        self.session_id = session.session_id;
        self.conversation_id = session.conversation.id.clone();
        self.conversation_title = session.conversation.title.clone();
        self.provider = session.conversation.provider.clone();
        self.model = session.conversation.model.clone();
        self.context_usage = session.context_usage.clone();
        self.last_assistant_text = session
            .last_assistant_text
            .or_else(|| last_assistant_from_messages(&session.conversation.messages));
        self.conversation_entries = session
            .conversation
            .messages
            .into_iter()
            .filter_map(|message| match message.role.as_str() {
                "user" => {
                    let attachments = message.normalized_attachments();
                    Some(TranscriptEntry::User {
                        text: message.text,
                        attachments,
                    })
                }
                "assistant" => Some(TranscriptEntry::Assistant(message.text)),
                _ => None,
            })
            .collect();

        if clear_ephemeral {
            self.activities.clear();
            self.tool_states.clear();
            self.search_call_count = 0;
            self.streaming_text.clear();
            self.set_overlay(OverlayState::None);
            self.mode = ChatMode::Ready;
            self.mode_started_at = None;
            self.clear_busy_action();
            self.clear_composer();
        }

        self.auto_scroll = true;
        self.bump_transcript_revision();
        self.bump_streaming_revision();
    }

    fn conversation_updated(&mut self, session: SessionData) {
        self.replace_session(session, false);
    }

    fn apply_bootstrap(&mut self, bootstrap: BootstrapData) {
        if let Some(provider) = bootstrap.provider {
            self.provider = provider;
        }
        if let Some(model) = bootstrap.model {
            self.model = model;
        }
        self.account = bootstrap.account;
        self.context_usage = None;
    }

    fn open_model_editor(&mut self) {
        self.set_overlay(OverlayState::ModelEditor(ModelEditorOverlay::new(
            self.provider.clone(),
            self.model.clone(),
        )));
        self.clear_quit_hint();
    }

    fn set_overlay(&mut self, overlay: OverlayState) {
        let had_approval = matches!(self.overlay, OverlayState::Approval(_));
        let will_have_approval = matches!(&overlay, OverlayState::Approval(_));

        if had_approval && !will_have_approval {
            self.approval_input_guard.deactivate();
        } else if !had_approval && will_have_approval {
            self.approval_input_guard.activate();
        }

        self.overlay = overlay;
    }

    fn push_activity(&mut self, text: impl Into<String>, tone: MetaTone) {
        self.activities.push(TranscriptEntry::Meta {
            text: text.into(),
            tone,
        });
        self.bump_transcript_revision();
    }

    fn set_footer(&mut self, text: impl Into<String>, tone: MetaTone) {
        self.footer_message = Some((text.into(), tone));
        self.footer_tag = None;
    }

    fn set_tagged_footer(&mut self, text: impl Into<String>, tone: MetaTone, tag: FooterTag) {
        self.footer_message = Some((text.into(), tone));
        self.footer_tag = Some(tag);
    }

    fn clear_footer(&mut self) {
        self.footer_message = None;
        self.footer_tag = None;
    }

    fn set_busy_action(&mut self, text: impl Into<String>) {
        self.busy_action = Some(text.into());
        self.busy_started_at = Some(Instant::now());
        self.busy_action_release_at = None;
        self.busy_call_id = None;
    }

    fn clear_busy_action(&mut self) {
        self.busy_action = None;
        self.busy_started_at = None;
        self.busy_action_release_at = None;
        self.busy_call_id = None;
    }

    fn show_tool_status(&mut self, tool: &ToolEventData) {
        if tool.tool == "search_clipboard" {
            self.search_call_count += 1;
        }

        self.busy_action = Some(tool_status_text(tool, self.search_call_count));
        self.busy_started_at = Some(Instant::now());
        self.busy_action_release_at = None;
        self.busy_call_id = Some(tool.call_id.clone());
    }

    fn finish_tool_status(&mut self, call_id: &str) {
        if self.busy_call_id.as_deref() != Some(call_id) {
            return;
        }

        let Some(started_at) = self.busy_started_at else {
            self.clear_busy_action();
            return;
        };

        let visible_until = started_at + MIN_TOOL_STATUS_DISPLAY;
        if visible_until <= Instant::now() {
            self.clear_busy_action();
            return;
        }

        self.busy_action_release_at = Some(visible_until);
    }

    fn bump_transcript_revision(&mut self) {
        self.transcript_revision = self.transcript_revision.wrapping_add(1);
    }

    fn bump_streaming_revision(&mut self) {
        self.streaming_revision = self.streaming_revision.wrapping_add(1);
    }

    fn clear_popup_hitboxes(&mut self) {
        self.slash_popup_visible_start = 0;
        self.slash_popup_hitboxes.clear();
        self.history_hitboxes.clear();
    }

    fn sync_footer_after_input_change(&mut self) {
        if matches!(self.footer_tag, Some(FooterTag::SlashSelected)) && self.slash_query().is_none()
        {
            self.clear_footer();
        }
    }

    fn history_hitbox_index(&self, column: u16, row: u16) -> Option<usize> {
        self.history_hitboxes
            .iter()
            .position(|rect| point_in_rect(column, row, *rect))
    }

    fn slash_hitbox_index(&self, column: u16, row: u16) -> Option<usize> {
        self.slash_popup_hitboxes
            .iter()
            .position(|rect| point_in_rect(column, row, *rect))
    }

    fn quit_hint_text(trigger: QuitHintTrigger) -> String {
        match trigger {
            QuitHintTrigger::CtrlC => chat_text("chat.quit_hint.ctrl_c"),
            QuitHintTrigger::Esc => chat_text("chat.quit_hint.esc"),
        }
    }

    fn begin_send(&mut self) {
        self.mode = ChatMode::Streaming;
        self.mode_started_at = Some(Instant::now());
        self.streaming_text.clear();
        self.activities.clear();
        self.tool_states.clear();
        self.search_call_count = 0;
        self.set_overlay(OverlayState::None);
        self.auto_scroll = true;
        self.clear_quit_hint();
        self.bump_transcript_revision();
        self.bump_streaming_revision();
        self.set_footer(chat_text("chat.footer.generating"), MetaTone::Info);
    }

    fn finish_send(&mut self) {
        self.mode = ChatMode::Ready;
        self.mode_started_at = None;
        self.search_call_count = 0;
        self.streaming_text.clear();
        self.set_overlay(OverlayState::None);
        self.clear_busy_action();
        self.bump_streaming_revision();
    }

    fn status_text(&self) -> String {
        if let Some(action) = &self.busy_action {
            return format!("{} {}", self.spinner_frame(), action);
        }
        match self.mode {
            ChatMode::Ready => chat_text("chat.status.ready"),
            ChatMode::Streaming => format!("{} Thinking", self.spinner_frame()),
            ChatMode::AwaitingApproval => chat_format(
                "chat.status.waiting_approval",
                &[
                    ("{spinner}", self.spinner_frame().to_string()),
                    ("{elapsed}", self.elapsed_suffix()),
                ],
            ),
        }
    }

    fn status_tone(&self) -> MetaTone {
        if self.busy_action.is_some() {
            return MetaTone::Info;
        }
        match self.mode {
            ChatMode::Ready => MetaTone::Success,
            ChatMode::Streaming => MetaTone::Info,
            ChatMode::AwaitingApproval => MetaTone::Warning,
        }
    }

    fn transcript_lines(&mut self, width: usize) -> &[Line<'static>] {
        let width = width.max(1);
        let tail_key = self.current_tail_key();
        let rebuild_base = self.transcript_cache.width != width
            || self.transcript_cache.base_revision != self.transcript_revision;

        if rebuild_base {
            self.transcript_cache.width = width;
            self.transcript_cache.base_revision = self.transcript_revision;
            self.transcript_cache.combined_lines =
                build_transcript_base_lines(&self.conversation_entries, &self.activities, width);
            self.transcript_cache.base_line_count = self.transcript_cache.combined_lines.len();
            self.transcript_cache.tail_key = TranscriptTailKey::None;
        }

        if rebuild_base || self.transcript_cache.tail_key != tail_key {
            let tail_lines = build_transcript_tail_lines(self, width);
            self.transcript_cache
                .combined_lines
                .truncate(self.transcript_cache.base_line_count);
            self.transcript_cache.combined_lines.extend(tail_lines);
            if self.transcript_cache.combined_lines.is_empty() {
                self.transcript_cache
                    .combined_lines
                    .push(Line::from(Span::styled(
                        chat_text("chat.empty"),
                        Style::default().fg(Color::DarkGray),
                    )));
            }
            self.transcript_cache.tail_key = tail_key;
        }

        &self.transcript_cache.combined_lines
    }

    fn current_tail_key(&self) -> TranscriptTailKey {
        if !self.streaming_text.is_empty() {
            return TranscriptTailKey::Streaming {
                version: self.streaming_revision,
            };
        }

        match self.mode {
            ChatMode::Streaming | ChatMode::AwaitingApproval => TranscriptTailKey::Meta {
                mode: self.mode,
                spinner_frame: self.spinner_frame_index(),
                elapsed_seconds: self
                    .mode_started_at
                    .or(self.busy_started_at)
                    .map(|started_at| started_at.elapsed().as_secs())
                    .unwrap_or(0),
                busy_action: self.busy_action.clone(),
            },
            ChatMode::Ready => {
                if self.busy_action.is_some() {
                    TranscriptTailKey::Meta {
                        mode: self.mode,
                        spinner_frame: self.spinner_frame_index(),
                        elapsed_seconds: self
                            .busy_started_at
                            .map(|started_at| started_at.elapsed().as_secs())
                            .unwrap_or(0),
                        busy_action: self.busy_action.clone(),
                    }
                } else {
                    TranscriptTailKey::None
                }
            }
        }
    }

    fn animation_state(&self) -> Option<AnimationState> {
        let animated = self.busy_action.is_some()
            || matches!(self.mode, ChatMode::Streaming | ChatMode::AwaitingApproval);
        let has_timed_footer = self.quit_hint_until.is_some();
        if !animated && !has_timed_footer {
            return None;
        }

        Some(AnimationState {
            spinner_frame: if animated {
                self.spinner_frame_index()
            } else {
                0
            },
            elapsed_seconds: if animated {
                self.mode_started_at
                    .or(self.busy_started_at)
                    .map(|started_at| started_at.elapsed().as_secs())
                    .unwrap_or(0)
            } else {
                0
            },
            quit_hint_active: self.quit_hint_active(),
        })
    }

    fn poll_timeout(&self) -> Duration {
        if self.animation_state().is_some() {
            Duration::from_millis(50)
        } else {
            Duration::from_millis(200)
        }
    }

    fn spinner_frame_index(&self) -> usize {
        let elapsed_ms = self.created_at.elapsed().as_millis() as usize;
        (elapsed_ms / 80) % THINKING_FRAMES.len()
    }

    fn spinner_frame(&self) -> &'static str {
        THINKING_FRAMES[self.spinner_frame_index()]
    }

    fn elapsed_suffix(&self) -> String {
        let started_at = self.mode_started_at.or(self.busy_started_at);
        started_at
            .map(|started_at| format!(" · {}", format_elapsed(started_at.elapsed())))
            .unwrap_or_default()
    }

    fn scroll_up(&mut self, lines: usize) {
        self.auto_scroll = false;
        self.scroll = self.scroll.saturating_sub(lines);
        self.clear_quit_hint();
    }

    fn scroll_down(&mut self, lines: usize) {
        self.auto_scroll = false;
        self.scroll = self.scroll.saturating_add(lines);
        self.clear_quit_hint();
    }

    fn follow_output(&mut self) {
        self.auto_scroll = true;
        self.clear_quit_hint();
    }

    fn clear_composer(&mut self) {
        self.clear_input_text();
        self.pending_attachments.clear();
    }

    fn clear_input_text(&mut self) {
        self.input.clear();
        self.input_cursor = 0;
        self.input_history_index = None;
        self.input_history_draft.clear();
        self.slash_selected = 0;
        self.clear_quit_hint();
        self.sync_footer_after_input_change();
    }

    fn append_pending_attachments(
        &mut self,
        attachments: impl IntoIterator<Item = ChatAttachmentData>,
    ) -> usize {
        let remaining = MAX_PENDING_ATTACHMENTS.saturating_sub(self.pending_attachments.len());
        if remaining == 0 {
            return 0;
        }

        let mut added = 0;
        for attachment in attachments.into_iter().take(remaining) {
            self.pending_attachments.push(attachment);
            added += 1;
        }

        if added > 0 {
            self.input_history_index = None;
            self.clear_quit_hint();
            self.sync_footer_after_input_change();
        }

        added
    }

    #[cfg(test)]
    fn set_pending_attachment(&mut self, attachment: ChatAttachmentData) {
        let _ = self.append_pending_attachments([attachment]);
    }

    fn pending_attachments(&self) -> &[ChatAttachmentData] {
        &self.pending_attachments
    }

    fn pending_attachment_count(&self) -> usize {
        self.pending_attachments.len()
    }

    fn pending_attachments_full(&self) -> bool {
        self.pending_attachments.len() >= MAX_PENDING_ATTACHMENTS
    }

    fn clear_pending_attachment(&mut self) -> bool {
        let removed = self.pending_attachments.pop().is_some();
        if removed {
            self.clear_quit_hint();
            self.sync_footer_after_input_change();
        }
        removed
    }

    fn remember_input(&mut self, submitted: &str) {
        let submitted = submitted.trim();
        if submitted.is_empty() {
            return;
        }
        if self
            .input_history
            .last()
            .is_some_and(|last| last == submitted)
        {
            self.input_history_index = None;
            self.input_history_draft.clear();
            return;
        }
        self.input_history.push(submitted.to_string());
        self.input_history_index = None;
        self.input_history_draft.clear();
    }

    fn browse_input_history_up(&mut self) -> bool {
        if self.input_history.is_empty() {
            return false;
        }

        let next_index = match self.input_history_index {
            Some(0) => 0,
            Some(index) => index.saturating_sub(1),
            None => {
                self.input_history_draft = self.input.clone();
                self.input_history.len() - 1
            }
        };

        self.input_history_index = Some(next_index);
        self.input = self.input_history[next_index].clone();
        self.input_cursor = char_count(&self.input);
        self.refresh_slash_selection();
        self.clear_quit_hint();
        self.sync_footer_after_input_change();
        true
    }

    fn browse_input_history_down(&mut self) -> bool {
        let Some(index) = self.input_history_index else {
            return false;
        };

        if index + 1 >= self.input_history.len() {
            self.input = std::mem::take(&mut self.input_history_draft);
            self.input_cursor = char_count(&self.input);
            self.input_history_index = None;
        } else {
            let next_index = index + 1;
            self.input_history_index = Some(next_index);
            self.input = self.input_history[next_index].clone();
            self.input_cursor = char_count(&self.input);
        }

        self.refresh_slash_selection();
        self.clear_quit_hint();
        self.sync_footer_after_input_change();
        true
    }

    fn update_input_text_area(&mut self, area: Rect) {
        self.input_visual_width = area.width.max(1);
        self.input_text_area = Some(area);
    }

    fn update_body_scrollbar_state(
        &mut self,
        scrollbar_area: Option<Rect>,
        visible_lines: usize,
        total_lines: usize,
    ) {
        self.body_scrollbar_area = scrollbar_area;
        self.body_visible_lines = visible_lines;
        self.body_total_lines = total_lines;
        if scrollbar_area.is_none() || total_lines <= visible_lines {
            self.dragging_body_scrollbar = false;
            self.body_scrollbar_grab_offset = 0;
        }
    }

    fn scroll_to_body_pointer(&mut self, row: u16) {
        let Some(area) = self.body_scrollbar_area else {
            return;
        };
        let max_scroll = self
            .body_total_lines
            .saturating_sub(self.body_visible_lines);
        if max_scroll == 0 || area.height <= 1 {
            self.scroll = 0;
            self.auto_scroll = true;
            return;
        }

        let relative_row = row
            .saturating_sub(area.y)
            .min(area.height.saturating_sub(1)) as usize;
        let (_thumb_top, thumb_height) = scrollbar_thumb_metrics(
            self.body_total_lines,
            self.body_visible_lines,
            self.scroll,
            area.height as usize,
        );
        let max_thumb_top = area.height.saturating_sub(thumb_height as u16) as usize;
        let desired_thumb_top = relative_row
            .saturating_sub(self.body_scrollbar_grab_offset)
            .min(max_thumb_top);
        self.auto_scroll = false;
        self.scroll = if max_thumb_top == 0 {
            max_scroll
        } else {
            desired_thumb_top * max_scroll / max_thumb_top
        };
        self.clear_quit_hint();
    }

    fn start_body_scrollbar_drag(&mut self, column: u16, row: u16) -> bool {
        let Some(area) = self.body_scrollbar_area else {
            return false;
        };
        if !point_in_rect(column, row, area) {
            return false;
        }

        let relative_row = row.saturating_sub(area.y) as usize;
        let (thumb_top, thumb_height) = scrollbar_thumb_metrics(
            self.body_total_lines,
            self.body_visible_lines,
            self.scroll,
            area.height as usize,
        );
        self.dragging_body_scrollbar = true;
        self.body_scrollbar_grab_offset =
            if relative_row >= thumb_top && relative_row < thumb_top + thumb_height {
                relative_row.saturating_sub(thumb_top)
            } else {
                thumb_height / 2
            };
        self.scroll_to_body_pointer(row);
        true
    }

    fn drag_body_scrollbar(&mut self, row: u16) -> bool {
        if !self.dragging_body_scrollbar {
            return false;
        }
        self.scroll_to_body_pointer(row);
        true
    }

    fn stop_body_scrollbar_drag(&mut self) {
        self.dragging_body_scrollbar = false;
        self.body_scrollbar_grab_offset = 0;
    }

    fn move_cursor_to_pointer(&mut self, column: u16, row: u16) -> bool {
        let Some(area) = self.input_text_area else {
            return false;
        };
        if !point_in_rect(column, row, area) {
            return false;
        }

        let viewport = input_viewport(
            &self.input,
            self.input_cursor,
            self.input_visual_width as usize,
            area.height as usize,
        );
        let layout = wrapped_input_layout(
            &self.input,
            self.input_cursor,
            self.input_visual_width as usize,
        );
        let target_row = viewport.start_row + row.saturating_sub(area.y) as usize;
        let target_col = column.saturating_sub(area.x) as usize;
        self.input_cursor = cursor_from_visual_position(&layout, target_row, target_col);
        self.clear_quit_hint();
        true
    }

    fn has_session(&self) -> bool {
        !self.session_id.is_empty()
    }

    fn reset_to_empty_conversation(&mut self) {
        self.session_id.clear();
        self.conversation_id.clear();
        self.conversation_title = chat_text("chat.conversation.new");
        self.context_usage = None;
        self.conversation_entries.clear();
        self.activities.clear();
        self.search_call_count = 0;
        self.streaming_text.clear();
        self.last_assistant_text = None;
        self.set_overlay(OverlayState::None);
        self.mode = ChatMode::Ready;
        self.mode_started_at = None;
        self.auto_scroll = true;
        self.scroll = 0;
        self.dragging_body_scrollbar = false;
        self.clear_busy_action();
        self.clear_composer();
        self.bump_transcript_revision();
        self.bump_streaming_revision();
    }

    fn set_input(&mut self, value: String) {
        self.input = value;
        self.input_cursor = char_count(&self.input);
        self.input_history_index = None;
        self.refresh_slash_selection();
        self.clear_quit_hint();
        self.sync_footer_after_input_change();
    }

    fn insert_char(&mut self, ch: char) {
        insert_char_at(&mut self.input, &mut self.input_cursor, ch);
        self.input_history_index = None;
        self.refresh_slash_selection();
        self.clear_quit_hint();
        self.sync_footer_after_input_change();
    }

    fn insert_text(&mut self, text: &str) {
        insert_text_at(&mut self.input, &mut self.input_cursor, text);
        self.input_history_index = None;
        self.refresh_slash_selection();
        self.clear_quit_hint();
        self.sync_footer_after_input_change();
    }

    fn backspace(&mut self) {
        delete_before_cursor(&mut self.input, &mut self.input_cursor);
        self.input_history_index = None;
        self.refresh_slash_selection();
        self.clear_quit_hint();
        self.sync_footer_after_input_change();
    }

    fn delete_forward(&mut self) {
        delete_at_cursor(&mut self.input, self.input_cursor);
        self.input_history_index = None;
        self.refresh_slash_selection();
        self.clear_quit_hint();
        self.sync_footer_after_input_change();
    }

    fn move_cursor_left(&mut self) {
        self.input_cursor = self.input_cursor.saturating_sub(1);
        self.clear_quit_hint();
    }

    fn move_cursor_right(&mut self) {
        self.input_cursor = (self.input_cursor + 1).min(char_count(&self.input));
        self.clear_quit_hint();
    }

    fn move_cursor_start(&mut self) {
        self.input_cursor = 0;
        self.clear_quit_hint();
    }

    fn move_cursor_end(&mut self) {
        self.input_cursor = char_count(&self.input);
        self.clear_quit_hint();
    }

    fn move_cursor_up_line(&mut self) {
        self.input_cursor = move_cursor_vertical(
            &self.input,
            self.input_cursor,
            self.input_visual_width as usize,
            -1,
        );
        self.clear_quit_hint();
    }

    fn move_cursor_down_line(&mut self) {
        self.input_cursor = move_cursor_vertical(
            &self.input,
            self.input_cursor,
            self.input_visual_width as usize,
            1,
        );
        self.clear_quit_hint();
    }

    fn delete_to_line_start(&mut self) {
        delete_to_line_start_in_text(&mut self.input, &mut self.input_cursor);
        self.input_history_index = None;
        self.refresh_slash_selection();
        self.clear_quit_hint();
        self.sync_footer_after_input_change();
    }

    fn slash_query(&self) -> Option<&str> {
        if !matches!(self.overlay, OverlayState::None) {
            return None;
        }

        let trimmed = self.input.trim();
        if !trimmed.starts_with('/') || trimmed.chars().any(char::is_whitespace) {
            return None;
        }

        Some(trimmed)
    }

    fn slash_matches(&self) -> Vec<&'static SlashCommand> {
        let Some(query) = self.slash_query() else {
            return Vec::new();
        };

        SLASH_COMMANDS
            .iter()
            .filter(|command| slash_command_matches(command, query))
            .collect()
    }

    fn refresh_slash_selection(&mut self) {
        let matches = self.slash_matches();
        if matches.is_empty() {
            self.slash_selected = 0;
        } else {
            self.slash_selected = self.slash_selected.min(matches.len().saturating_sub(1));
        }
    }

    fn select_previous_slash(&mut self) {
        let matches = self.slash_matches();
        if matches.is_empty() {
            return;
        }
        if self.slash_selected == 0 {
            self.slash_selected = matches.len() - 1;
        } else {
            self.slash_selected -= 1;
        }
    }

    fn select_next_slash(&mut self) {
        let matches = self.slash_matches();
        if matches.is_empty() {
            return;
        }
        self.slash_selected = (self.slash_selected + 1) % matches.len();
    }

    fn selected_slash_command(&self) -> Option<&'static SlashCommand> {
        let matches = self.slash_matches();
        matches.get(self.slash_selected).copied()
    }

    fn complete_selected_slash(&mut self) -> Option<&'static str> {
        let selected = self.selected_slash_command()?.name;
        self.set_input(selected.to_string());
        Some(selected)
    }

    fn arm_quit_hint(&mut self, trigger: QuitHintTrigger) {
        self.quit_hint_until = Some(Instant::now() + Duration::from_secs(1));
        self.set_tagged_footer(
            Self::quit_hint_text(trigger),
            MetaTone::Warning,
            FooterTag::QuitHint(trigger),
        );
    }

    fn clear_quit_hint(&mut self) {
        self.quit_hint_until = None;
        if matches!(self.footer_tag, Some(FooterTag::QuitHint(_))) {
            self.clear_footer();
        }
    }

    fn quit_hint_active(&self) -> bool {
        self.quit_hint_until
            .is_some_and(|deadline| deadline > Instant::now())
    }

    fn tick(&mut self) -> bool {
        if self
            .busy_action_release_at
            .is_some_and(|deadline| deadline <= Instant::now())
        {
            self.clear_busy_action();
            return true;
        }

        if self
            .quit_hint_until
            .is_some_and(|deadline| deadline <= Instant::now())
        {
            self.clear_quit_hint();
            return true;
        }

        false
    }
}

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
        self.terminal.draw(|frame| render(frame, app))?;
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
            handle_ui_event(&mut app, message);
            needs_redraw = true;
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

fn handle_key_event(
    app: &mut ChatApp,
    key: KeyEvent,
    primary_client: Arc<Mutex<DeckClient>>,
    ui_tx: UnboundedSender<UiEvent>,
) {
    if matches!(key.kind, KeyEventKind::Release) {
        return;
    }

    match &mut app.overlay {
        OverlayState::Approval(overlay) => {
            if key.code == KeyCode::Char('c') && key.modifiers.contains(KeyModifiers::CONTROL) {
                app.set_footer(chat_text("chat.footer.approval_pending"), MetaTone::Warning);
                return;
            }

            match key.code {
                KeyCode::Char('Y') | KeyCode::Char('y') | KeyCode::Enter => {
                    let session_id = app.session_id.clone();
                    let call_id = overlay.call_id.clone();
                    app.set_overlay(OverlayState::None);
                    app.mode = ChatMode::Streaming;
                    app.set_footer(
                        chat_text("chat.footer.tool_approved_continue"),
                        MetaTone::Info,
                    );
                    tokio::spawn(async move {
                        let event = match respond_to_approval(&session_id, &call_id, true).await {
                            Ok(()) => UiEvent::FooterMessage(
                                chat_text("chat.footer.tool_approved"),
                                MetaTone::Info,
                            ),
                            Err(error) => ui_error(error),
                        };
                        let _ = ui_tx.send(event);
                    });
                }
                KeyCode::Char('N') | KeyCode::Char('n') | KeyCode::Esc => {
                    let session_id = app.session_id.clone();
                    let call_id = overlay.call_id.clone();
                    app.set_overlay(OverlayState::None);
                    app.mode = ChatMode::Streaming;
                    app.set_footer(chat_text("chat.footer.tool_rejected"), MetaTone::Warning);
                    tokio::spawn(async move {
                        let event = match respond_to_approval(&session_id, &call_id, false).await {
                            Ok(()) => UiEvent::FooterMessage(
                                chat_text("chat.footer.tool_rejected"),
                                MetaTone::Warning,
                            ),
                            Err(error) => ui_error(error),
                        };
                        let _ = ui_tx.send(event);
                    });
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
                    let event = match cancel_stream(&session_id).await {
                        Ok(()) => UiEvent::FooterMessage(
                            chat_text("chat.footer.interrupt_sent"),
                            MetaTone::Warning,
                        ),
                        Err(error) => ui_error(error),
                    };
                    let _ = ui_tx.send(event);
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
                        let event = match cancel_stream(&session_id).await {
                            Ok(()) => UiEvent::FooterMessage(
                                chat_text("chat.footer.stop_sent"),
                                MetaTone::Warning,
                            ),
                            Err(error) => ui_error(error),
                        };
                        let _ = ui_tx.send(event);
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

            let submitted = app.input.trim().to_string();
            let pending_attachments = app.pending_attachments.clone();
            if submitted.is_empty() && pending_attachments.is_empty() {
                return;
            }
            app.remember_input(&submitted);
            app.clear_composer();

            if submitted.starts_with('/') {
                handle_slash_command(app, submitted, primary_client, ui_tx);
                return;
            }

            if app.mode != ChatMode::Ready {
                app.set_footer(
                    chat_text("chat.footer.reply_incomplete_stop"),
                    MetaTone::Warning,
                );
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
            OverlayState::None => {
                if !app.slash_matches().is_empty() && app.input_history_index.is_none() {
                    app.select_previous_slash();
                    app.clear_quit_hint();
                } else {
                    app.scroll_up(3);
                }
            }
            OverlayState::Approval(_) | OverlayState::ModelEditor(_) => {}
        },
        MouseEventKind::ScrollDown => match &mut app.overlay {
            OverlayState::History(overlay) => {
                if overlay.selected + 1 < overlay.items.len() {
                    overlay.selected += 1;
                }
                app.clear_quit_hint();
                maybe_request_more_history(app, primary_client, ui_tx);
            }
            OverlayState::None => {
                if !app.slash_matches().is_empty() && app.input_history_index.is_none() {
                    app.select_next_slash();
                    app.clear_quit_hint();
                } else {
                    app.scroll_down(3);
                }
            }
            OverlayState::Approval(_) | OverlayState::ModelEditor(_) => {}
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

fn handle_ui_event(app: &mut ChatApp, event: UiEvent) {
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
                } else if let Some(text) = data.text {
                    app.insert_text(&text);
                    app.set_footer(
                        chat_text("chat.footer.clipboard_text_pasted"),
                        MetaTone::Success,
                    );
                } else if !pasted_text.is_empty() && !looks_like_path_payload(&pasted_text) {
                    app.insert_text(&pasted_text);
                } else {
                    app.set_footer(chat_text("chat.footer.clipboard_empty"), MetaTone::Warning);
                }

                if has_attachment && !pasted_text.trim().is_empty() {
                    app.clear_quit_hint();
                }
            }
            Err(message) => {
                if !pasted_text.is_empty() && !looks_like_path_payload(&pasted_text) {
                    app.insert_text(&pasted_text);
                }
                app.set_footer(message, MetaTone::Warning);
            }
        },
        UiEvent::ToolStarted(tool) => {
            if app.tool_states.contains_key(&tool.call_id) {
                return;
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
                return;
            }
            app.tool_states
                .insert(tool.call_id.clone(), ToolLifecycle::Finished);
            app.finish_tool_status(&tool.call_id);
        }
        UiEvent::ApprovalRequested(tool) => {
            app.mode = ChatMode::AwaitingApproval;
            if app.mode_started_at.is_none() {
                app.mode_started_at = Some(Instant::now());
            }
            app.set_overlay(OverlayState::Approval(ApprovalOverlay {
                call_id: tool.call_id.clone(),
                tool: tool.tool.clone(),
                preview: approval_preview(&tool),
            }));
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
        UiEvent::Done(done) => {
            app.last_assistant_text = Some(done.text);
            app.finish_send();
            app.set_footer(chat_text("chat.footer.round_done"), MetaTone::Success);
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
                let should_stop =
                    matches!(event.event.as_str(), chat_event::DONE | chat_event::ERROR);
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

fn render(frame: &mut Frame<'_>, app: &mut ChatApp) {
    let area = frame.area();
    app.clear_popup_hitboxes();
    let input_height = input_panel_height(app, area.width);
    let layout = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(4),
            Constraint::Min(8),
            Constraint::Length(input_height),
            Constraint::Length(1),
        ])
        .split(area);

    render_header(frame, layout[0], app);
    render_body(frame, layout[1], app);
    render_input(frame, layout[2], app);
    render_footer(frame, layout[3], app);

    match &mut app.overlay {
        OverlayState::Approval(overlay) => render_approval_overlay(frame, area, overlay),
        OverlayState::History(overlay) => {
            render_history_overlay(frame, area, overlay, &mut app.history_hitboxes)
        }
        OverlayState::ModelEditor(overlay) => render_model_overlay(frame, area, overlay),
        OverlayState::None => render_slash_popup(frame, layout[2], app),
    }
}

fn render_header(frame: &mut Frame<'_>, area: Rect, app: &ChatApp) {
    let block = Block::default()
        .title(" Deck AI ")
        .borders(Borders::ALL)
        .border_style(app.status_tone().style());
    let inner = block.inner(area);
    frame.render_widget(block, area);

    let rows = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Length(1), Constraint::Length(1)])
        .split(inner);

    let account = app
        .account
        .clone()
        .unwrap_or_else(|| chat_text("chat.header.account_hidden"));
    let usage = app
        .context_usage
        .as_ref()
        .map(|value| {
            chat_format(
                "chat.header.context_usage",
                &[("{usage}", value.usage_percent_text.clone())],
            )
        })
        .unwrap_or_else(|| chat_text("chat.header.context_usage_none"));
    let transcript_mode = if app.auto_scroll {
        chat_text("chat.header.mode.following")
    } else {
        chat_text("chat.header.mode.reviewing")
    };
    let left_title = format!("Deck AI · {}", app.conversation_title);
    let left_meta = format!("{} / {} · {}", app.provider, app.model, account);

    frame.render_widget(
        Paragraph::new(spaced_line(
            &left_title,
            Style::default().add_modifier(Modifier::BOLD),
            &app.status_text(),
            app.status_tone().style().add_modifier(Modifier::BOLD),
            rows[0].width as usize,
        )),
        rows[0],
    );

    frame.render_widget(
        Paragraph::new(spaced_line(
            &left_meta,
            Style::default().fg(Color::Gray),
            &format!("{} · {}", usage, transcript_mode),
            Style::default().fg(Color::DarkGray),
            rows[1].width as usize,
        )),
        rows[1],
    );
}

fn render_body(frame: &mut Frame<'_>, area: Rect, app: &mut ChatApp) {
    let title = if app.auto_scroll {
        chat_text("chat.body.title.following")
    } else {
        chat_text("chat.body.title.reviewing")
    };
    let block = Block::default().title(title).borders(Borders::ALL);
    frame.render_widget(block.clone(), area);
    let inner = block.inner(area);
    if inner.width == 0 || inner.height == 0 {
        app.update_body_scrollbar_state(None, 0, 0);
        return;
    }

    let chunks = if inner.width > 2 {
        Layout::default()
            .direction(Direction::Horizontal)
            .constraints([
                Constraint::Min(1),
                Constraint::Length(1),
                Constraint::Length(1),
            ])
            .split(inner)
    } else if inner.width > 1 {
        Layout::default()
            .direction(Direction::Horizontal)
            .constraints([Constraint::Min(1), Constraint::Length(1)])
            .split(inner)
    } else {
        Layout::default()
            .direction(Direction::Horizontal)
            .constraints([Constraint::Min(1)])
            .split(inner)
    };

    let content_area = chunks[0];
    let scrollbar_area = if chunks.len() > 2 {
        Some(chunks[2])
    } else if chunks.len() > 1 {
        Some(chunks[1])
    } else {
        None
    };
    let total_lines = app.transcript_lines(content_area.width as usize).len();
    let max_scroll = total_lines.saturating_sub(content_area.height as usize);
    if app.auto_scroll {
        app.scroll = max_scroll;
    } else if app.scroll > max_scroll {
        app.scroll = max_scroll;
    }

    if !app.auto_scroll && app.scroll >= max_scroll {
        app.auto_scroll = true;
    }

    app.update_body_scrollbar_state(scrollbar_area, content_area.height as usize, total_lines);
    let visible_lines = transcript_view_lines(
        app,
        content_area.width as usize,
        content_area.height as usize,
    );
    let paragraph = Paragraph::new(visible_lines);
    frame.render_widget(paragraph, content_area);

    if let Some(scrollbar_area) = scrollbar_area {
        render_scrollbar(
            frame,
            scrollbar_area,
            total_lines,
            content_area.height as usize,
            app.scroll,
            Color::DarkGray,
            Color::Cyan,
        );
    }
}

fn render_input(frame: &mut Frame<'_>, area: Rect, app: &mut ChatApp) {
    let block = Block::default().borders(Borders::ALL);
    frame.render_widget(block.clone(), area);
    let inner = block.inner(area);
    if inner.width == 0 || inner.height == 0 {
        app.input_text_area = None;
        return;
    }

    let attachment_height =
        pending_attachment_preview_height(inner.width, app.pending_attachment_count());
    let sections = if attachment_height > 0 {
        Layout::default()
            .direction(Direction::Vertical)
            .constraints([Constraint::Length(attachment_height), Constraint::Min(1)])
            .split(inner)
    } else {
        Layout::default()
            .direction(Direction::Vertical)
            .constraints([Constraint::Min(1)])
            .split(inner)
    };

    if attachment_height > 0 {
        render_pending_attachments(frame, sections[0], app.pending_attachments());
    }

    let input_row = *sections.last().unwrap_or(&inner);
    if input_row.width == 0 || input_row.height == 0 {
        app.input_text_area = None;
        return;
    }

    let row_sections = if input_row.width > 2 {
        Layout::default()
            .direction(Direction::Horizontal)
            .constraints([Constraint::Length(2), Constraint::Min(1)])
            .split(input_row)
    } else {
        Layout::default()
            .direction(Direction::Horizontal)
            .constraints([Constraint::Min(1)])
            .split(input_row)
    };

    let gutter_area = row_sections[0];
    let text_area = if row_sections.len() > 1 {
        row_sections[1]
    } else {
        row_sections[0]
    };
    if text_area.width == 0 || text_area.height == 0 {
        app.input_text_area = None;
        return;
    }
    app.update_input_text_area(text_area);
    let viewport = input_viewport(
        &app.input,
        app.input_cursor,
        text_area.width as usize,
        text_area.height as usize,
    );

    let prompt_color = if app.slash_query().is_some() {
        Color::Yellow
    } else {
        Color::Green
    };

    if row_sections.len() > 1 {
        let gutter_lines: Vec<Line<'_>> = (0..text_area.height)
            .map(|row| {
                let symbol = if row == 0 { ">" } else { "│" };
                let style = if row == 0 {
                    Style::default()
                        .fg(prompt_color)
                        .add_modifier(Modifier::BOLD)
                } else {
                    Style::default().fg(Color::DarkGray)
                };
                Line::from(Span::styled(symbol, style))
            })
            .collect();
        frame.render_widget(Paragraph::new(gutter_lines), gutter_area);
    }

    let text_lines: Vec<Line<'_>> = if app.input.is_empty() {
        let mut lines = vec![Line::from(Span::styled(
            chat_text("chat.input.placeholder"),
            Style::default().fg(Color::DarkGray),
        ))];
        while lines.len() < text_area.height as usize {
            lines.push(Line::from(""));
        }
        lines
    } else {
        viewport
            .visible_lines
            .iter()
            .map(|line| Line::from(Span::raw(line.clone())))
            .collect()
    };
    frame.render_widget(Paragraph::new(text_lines), text_area);

    if matches!(app.overlay, OverlayState::None) {
        frame.set_cursor_position((
            text_area.x + viewport.cursor_col as u16,
            text_area.y + viewport.cursor_row as u16,
        ));
    }
}

fn render_footer(frame: &mut Frame<'_>, area: Rect, app: &ChatApp) {
    let default_footer = if app.slash_query().is_some() {
        chat_text("chat.footer.default.slash")
    } else if app.auto_scroll {
        chat_text("chat.footer.default.following")
    } else {
        chat_text("chat.footer.default.reviewing")
    };
    let footer_message = match app.footer_tag {
        Some(FooterTag::QuitHint(_)) if !app.quit_hint_active() => None,
        Some(FooterTag::SlashSelected) if app.slash_query().is_none() => None,
        _ => app.footer_message.clone(),
    };
    let (text, tone) = footer_message.unwrap_or_else(|| (default_footer, MetaTone::Dim));
    let line = Line::from(Span::styled(text, tone.style()));
    frame.render_widget(Paragraph::new(line), area);
}

fn render_approval_overlay(frame: &mut Frame<'_>, area: Rect, overlay: &ApprovalOverlay) {
    let popup = centered_rect(72, 42, area);
    frame.render_widget(Clear, popup);

    let text = vec![
        Line::from(Span::styled(
            chat_format("chat.approval.needs", &[("{tool}", overlay.tool.clone())]),
            Style::default()
                .fg(Color::Yellow)
                .add_modifier(Modifier::BOLD),
        )),
        Line::from(Span::raw("")),
        Line::from(Span::raw(overlay.preview.clone())),
        Line::from(Span::raw("")),
        Line::from(Span::styled(
            chat_text("chat.approval.actions"),
            Style::default().fg(Color::DarkGray),
        )),
    ];

    frame.render_widget(
        Paragraph::new(text).block(
            Block::default()
                .title(chat_text("chat.approval.title"))
                .borders(Borders::ALL),
        ),
        popup,
    );
}

fn render_model_overlay(frame: &mut Frame<'_>, area: Rect, overlay: &ModelEditorOverlay) {
    let popup = centered_rect(68, 34, area);
    frame.render_widget(Clear, popup);

    let block = Block::default()
        .title(chat_text("chat.model.title"))
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::Cyan));
    let inner = block.inner(popup);
    frame.render_widget(block, popup);

    if inner.width == 0 || inner.height == 0 {
        return;
    }

    let layout = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(1),
            Constraint::Length(1),
            Constraint::Length(1),
            Constraint::Length(3),
            Constraint::Length(1),
            Constraint::Min(1),
        ])
        .split(inner);

    let provider_label = provider_display_name(&overlay.provider);
    let provider_line = Line::from(vec![
        Span::styled(
            format!("{} ", chat_text("chat.model.provider")),
            Style::default().fg(Color::DarkGray),
        ),
        Span::styled(
            provider_label,
            Style::default().add_modifier(Modifier::BOLD),
        ),
    ]);
    frame.render_widget(Paragraph::new(provider_line), layout[0]);

    let current_line = Line::from(vec![
        Span::styled(
            format!("{} ", chat_text("chat.model.current")),
            Style::default().fg(Color::DarkGray),
        ),
        Span::styled(
            overlay.current_model.clone(),
            Style::default()
                .fg(Color::Gray)
                .add_modifier(Modifier::BOLD),
        ),
    ]);
    frame.render_widget(Paragraph::new(current_line), layout[1]);

    frame.render_widget(
        Paragraph::new(Line::from(Span::styled(
            chat_text("chat.model.subtitle"),
            Style::default().fg(Color::DarkGray),
        ))),
        layout[2],
    );

    let input_block = Block::default()
        .title(chat_text("chat.model.input.title"))
        .borders(Borders::ALL)
        .border_style(if overlay.error.is_some() {
            Style::default().fg(Color::Red)
        } else {
            Style::default().fg(Color::Cyan)
        });
    let input_inner = input_block.inner(layout[3]);
    frame.render_widget(input_block, layout[3]);

    if input_inner.width > 0 && input_inner.height > 0 {
        let view =
            single_line_input_view(&overlay.draft, overlay.cursor, input_inner.width as usize);
        let line = if overlay.draft.is_empty() {
            Line::from(Span::styled(
                chat_text("chat.model.input.placeholder"),
                Style::default().fg(Color::DarkGray),
            ))
        } else {
            Line::from(Span::raw(view.visible_text))
        };
        frame.render_widget(Paragraph::new(line), input_inner);
        frame.set_cursor_position((input_inner.x + view.cursor_col as u16, input_inner.y));
    }

    let status_text = overlay
        .error
        .clone()
        .unwrap_or_else(|| chat_text("chat.model.hint"));
    let status_style = if overlay.error.is_some() {
        Style::default().fg(Color::Red)
    } else {
        Style::default().fg(Color::DarkGray)
    };
    frame.render_widget(
        Paragraph::new(Line::from(Span::styled(status_text, status_style))),
        layout[4],
    );
}

fn open_model_editor_if_available(app: &mut ChatApp) {
    if app.mode != ChatMode::Ready {
        app.set_footer(
            chat_text("chat.footer.cannot_model_while_replying"),
            MetaTone::Warning,
        );
        return;
    }

    if app.busy_action.is_some() {
        app.set_footer(chat_text("chat.footer.busy_wait"), MetaTone::Warning);
        return;
    }

    app.open_model_editor();
}

fn render_slash_popup(frame: &mut Frame<'_>, input_area: Rect, app: &mut ChatApp) {
    let matches = app.slash_matches();
    if matches.is_empty() {
        return;
    }

    let max_visible = slash_popup_max_visible(input_area);
    let (visible_start, visible_count) =
        visible_list_window(app.slash_selected, matches.len(), max_visible);
    if visible_count == 0 {
        return;
    }

    app.slash_popup_visible_start = visible_start;

    let height = (visible_count as u16).saturating_mul(2).saturating_add(2);
    let popup_width = input_area.width.min(60);
    let popup = Rect {
        x: input_area.x,
        y: input_area.y.saturating_sub(height),
        width: popup_width,
        height,
    };
    let block = Block::default()
        .title(chat_text("chat.commands.title"))
        .borders(Borders::ALL);
    let inner = block.inner(popup);
    frame.render_widget(Clear, popup);

    let items: Vec<ListItem<'_>> = matches
        .iter()
        .skip(visible_start)
        .take(visible_count)
        .map(|command| {
            let alias = if command.aliases.is_empty() {
                String::new()
            } else {
                format!("  ({})", command.aliases.join(", "))
            };
            ListItem::new(vec![
                Line::from(vec![
                    Span::styled(command.name, Style::default().add_modifier(Modifier::BOLD)),
                    Span::styled(alias, Style::default().fg(Color::DarkGray)),
                ]),
                Line::from(Span::styled(
                    chat_text(command.description),
                    Style::default().fg(Color::Gray),
                )),
            ])
        })
        .collect();

    let mut state = ListState::default();
    state.select(Some(
        app.slash_selected
            .saturating_sub(visible_start)
            .min(visible_count.saturating_sub(1)),
    ));
    let list = List::new(items)
        .block(block)
        .highlight_style(
            Style::default()
                .bg(Color::Rgb(26, 26, 26))
                .fg(Color::Yellow),
        )
        .highlight_symbol("› ");
    frame.render_stateful_widget(list, popup, &mut state);

    for index in 0..visible_count {
        let y = inner.y.saturating_add((index as u16).saturating_mul(2));
        let height = inner
            .height
            .saturating_sub((index as u16).saturating_mul(2))
            .min(2);
        if height == 0 {
            break;
        }
        app.slash_popup_hitboxes.push(Rect {
            x: inner.x,
            y,
            width: inner.width,
            height,
        });
    }
}

fn slash_popup_max_visible(input_area: Rect) -> usize {
    input_area.y.saturating_sub(2) as usize / 2
}

fn visible_list_window(selected: usize, total_items: usize, max_visible: usize) -> (usize, usize) {
    if total_items == 0 || max_visible == 0 {
        return (0, 0);
    }

    let visible_count = total_items.min(max_visible);
    let selected = selected.min(total_items.saturating_sub(1));
    let visible_start = if total_items <= visible_count {
        0
    } else {
        selected
            .saturating_sub(visible_count.saturating_sub(1))
            .min(total_items.saturating_sub(visible_count))
    };

    (visible_start, visible_count)
}

fn render_history_overlay(
    frame: &mut Frame<'_>,
    area: Rect,
    overlay: &mut HistoryOverlay,
    history_hitboxes: &mut Vec<Rect>,
) {
    let popup = centered_rect(76, 58, area);
    frame.render_widget(Clear, popup);

    let layout = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Min(6), Constraint::Length(1)])
        .split(popup);

    let line_width = layout[0].width.saturating_sub(6) as usize;
    let block = Block::default()
        .title(chat_format(
            "chat.resume.title",
            &[("{count}", overlay.items.len().to_string())],
        ))
        .borders(Borders::ALL);
    let inner = block.inner(layout[0]);
    let items: Vec<ListItem<'_>> = overlay
        .items
        .iter()
        .map(|item| {
            let title = if let Some(model) = &item.model {
                format!("{}  {} / {}", item.title, item.provider, model)
            } else {
                format!("{}  {}", item.title, item.provider)
            };
            let detail = if item.last_snippet.trim().is_empty() {
                message_count_text(item.message_count)
            } else {
                format!(
                    "{}  |  {}",
                    message_count_text(item.message_count),
                    item.last_snippet
                )
            };
            ListItem::new(vec![
                Line::from(Span::styled(
                    truncate_text(&title, line_width),
                    Style::default().add_modifier(Modifier::BOLD),
                )),
                Line::from(Span::styled(
                    truncate_text(&detail, line_width),
                    Style::default().fg(Color::DarkGray),
                )),
            ])
        })
        .collect();

    let mut state = ListState::default();
    state.select(Some(overlay.selected));
    let list = List::new(items)
        .block(block)
        .highlight_style(Style::default().bg(Color::Rgb(30, 30, 30)).fg(Color::Cyan))
        .highlight_symbol("› ");
    frame.render_stateful_widget(list, layout[0], &mut state);

    let visible_slots = (inner.height as usize) / 2;
    overlay.visible_start = if visible_slots == 0 || overlay.items.len() <= visible_slots {
        0
    } else {
        overlay
            .selected
            .saturating_sub(visible_slots.saturating_sub(1))
            .min(overlay.items.len().saturating_sub(visible_slots))
    };
    for index in 0..visible_slots.min(overlay.items.len().saturating_sub(overlay.visible_start)) {
        let y = inner.y.saturating_add((index as u16).saturating_mul(2));
        let height = inner
            .height
            .saturating_sub((index as u16).saturating_mul(2))
            .min(2);
        if height == 0 {
            break;
        }
        history_hitboxes.push(Rect {
            x: inner.x,
            y,
            width: inner.width,
            height,
        });
    }

    let status = if overlay.loading_more {
        chat_format(
            "chat.resume.loading_more",
            &[("{spinner}", THINKING_FRAMES[0].to_string())],
        )
    } else if overlay.has_more {
        chat_text("chat.resume.more_available")
    } else {
        chat_text("chat.resume.end")
    };
    frame.render_widget(
        Paragraph::new(Line::from(Span::styled(
            status,
            Style::default().fg(Color::DarkGray),
        ))),
        layout[1],
    );
}

fn build_transcript_base_lines(
    conversation_entries: &[TranscriptEntry],
    activities: &[TranscriptEntry],
    width: usize,
) -> Vec<Line<'static>> {
    let mut lines = Vec::new();

    for entry in conversation_entries {
        push_transcript_entry_lines(&mut lines, width, entry);
    }

    for entry in activities {
        push_transcript_entry_lines(&mut lines, width, entry);
    }

    lines
}

fn build_transcript_tail_lines(app: &ChatApp, width: usize) -> Vec<Line<'static>> {
    let mut lines = Vec::new();

    if !app.streaming_text.is_empty() {
        push_assistant_entry_lines(&mut lines, width, &app.streaming_text);
        return lines;
    }

    if let Some(action) = &app.busy_action {
        push_status_entry_lines(
            &mut lines,
            width,
            app.spinner_frame(),
            action,
            Style::default()
                .fg(Color::Gray)
                .add_modifier(Modifier::ITALIC),
        );
        return lines;
    }

    match app.mode {
        ChatMode::Streaming => push_status_entry_lines(
            &mut lines,
            width,
            app.spinner_frame(),
            "Thinking",
            Style::default()
                .fg(Color::Gray)
                .add_modifier(Modifier::ITALIC),
        ),
        ChatMode::AwaitingApproval => push_status_entry_lines(
            &mut lines,
            width,
            app.spinner_frame(),
            "Waiting approval",
            Style::default()
                .fg(Color::Yellow)
                .add_modifier(Modifier::ITALIC),
        ),
        ChatMode::Ready => {}
    }

    lines
}

fn push_status_entry_lines(
    lines: &mut Vec<Line<'static>>,
    width: usize,
    spinner: &str,
    text: &str,
    style: Style,
) {
    let prefix = format!("  {} ", spinner);
    push_wrapped_lines(lines, width, &prefix, "    ", text, style);
}

fn transcript_view_lines(app: &mut ChatApp, width: usize, height: usize) -> Vec<Line<'static>> {
    if height == 0 {
        return Vec::new();
    }

    let scroll = app.scroll;
    let has_status_tail = app.auto_scroll
        && app.streaming_text.is_empty()
        && !matches!(app.current_tail_key(), TranscriptTailKey::None);
    let lines = app.transcript_lines(width);
    let end = (scroll + height).min(lines.len());
    let mut visible_lines = lines[scroll..end].to_vec();

    if has_status_tail && visible_lines.len() < height {
        let mut padded_lines = Vec::with_capacity(height);
        padded_lines
            .extend((0..height.saturating_sub(visible_lines.len())).map(|_| Line::from("")));
        padded_lines.append(&mut visible_lines);
        return padded_lines;
    }

    visible_lines
}

#[cfg(target_os = "macos")]
mod approval_input {
    use std::ffi::{c_void, CStr};
    use std::ptr;

    use core_foundation_sys::array::{CFArrayGetCount, CFArrayGetValueAtIndex, CFArrayRef};
    use core_foundation_sys::base::{Boolean, CFRelease, CFRetain, CFTypeRef};
    use core_foundation_sys::dictionary::CFDictionaryRef;
    use core_foundation_sys::string::{
        kCFStringEncodingUTF8, CFStringGetCString, CFStringGetLength,
        CFStringGetMaximumSizeForEncoding, CFStringRef,
    };

    const APPROVAL_INPUT_SOURCE_IDS: &[&str] =
        &["com.apple.keylayout.ABC", "com.apple.keylayout.US"];

    type TISInputSourceRef = *const c_void;
    type OSStatus = i32;

    #[link(name = "Carbon", kind = "framework")]
    unsafe extern "C" {
        static kTISPropertyInputSourceID: CFStringRef;
        fn TISCopyCurrentKeyboardInputSource() -> TISInputSourceRef;
        fn TISCreateInputSourceList(
            properties: CFDictionaryRef,
            include_all_installed: Boolean,
        ) -> CFArrayRef;
        fn TISGetInputSourceProperty(
            input_source: TISInputSourceRef,
            property_key: CFStringRef,
        ) -> CFTypeRef;
        fn TISSelectInputSource(input_source: TISInputSourceRef) -> OSStatus;
    }

    #[derive(Default)]
    pub struct ApprovalInputGuard {
        previous_source: Option<OwnedInputSource>,
    }

    impl ApprovalInputGuard {
        pub fn activate(&mut self) {
            if self.previous_source.is_some() {
                return;
            }

            let Some(current_source) = OwnedInputSource::current() else {
                return;
            };

            if current_source.matches_any(APPROVAL_INPUT_SOURCE_IDS) {
                return;
            }

            let Some(target_source) = find_input_source(APPROVAL_INPUT_SOURCE_IDS) else {
                return;
            };

            if target_source.matches_pointer(current_source.as_ptr()) {
                return;
            }

            if target_source.select() {
                self.previous_source = Some(current_source);
            }
        }

        pub fn deactivate(&mut self) {
            let Some(previous_source) = self.previous_source.take() else {
                return;
            };

            let _ = previous_source.select();
        }
    }

    impl Drop for ApprovalInputGuard {
        fn drop(&mut self) {
            self.deactivate();
        }
    }

    struct OwnedInputSource {
        source: TISInputSourceRef,
    }

    impl OwnedInputSource {
        fn current() -> Option<Self> {
            let source = unsafe { TISCopyCurrentKeyboardInputSource() };
            (!source.is_null()).then_some(Self { source })
        }

        fn select(&self) -> bool {
            unsafe { TISSelectInputSource(self.source) == 0 }
        }

        fn id(&self) -> Option<String> {
            input_source_id(self.source)
        }

        fn matches_any(&self, expected_ids: &[&str]) -> bool {
            self.id()
                .as_deref()
                .is_some_and(|id| expected_ids.iter().any(|candidate| *candidate == id))
        }

        fn matches_pointer(&self, other: TISInputSourceRef) -> bool {
            self.source == other
        }

        fn as_ptr(&self) -> TISInputSourceRef {
            self.source
        }

        unsafe fn retained(source: TISInputSourceRef) -> Option<Self> {
            if source.is_null() {
                return None;
            }

            unsafe { CFRetain(source as CFTypeRef) };
            Some(Self { source })
        }
    }

    impl Drop for OwnedInputSource {
        fn drop(&mut self) {
            unsafe { CFRelease(self.source as CFTypeRef) };
        }
    }

    struct OwnedInputSourceList {
        list: CFArrayRef,
    }

    impl OwnedInputSourceList {
        fn all() -> Option<Self> {
            let list = unsafe { TISCreateInputSourceList(ptr::null(), 0 as Boolean) };
            (!list.is_null()).then_some(Self { list })
        }

        fn len(&self) -> isize {
            unsafe { CFArrayGetCount(self.list) }
        }

        fn get(&self, index: isize) -> Option<OwnedInputSource> {
            let source = unsafe { CFArrayGetValueAtIndex(self.list, index) as TISInputSourceRef };
            unsafe { OwnedInputSource::retained(source) }
        }
    }

    impl Drop for OwnedInputSourceList {
        fn drop(&mut self) {
            unsafe { CFRelease(self.list as CFTypeRef) };
        }
    }

    fn find_input_source(expected_ids: &[&str]) -> Option<OwnedInputSource> {
        let sources = OwnedInputSourceList::all()?;
        for index in 0..sources.len() {
            let Some(source) = sources.get(index) else {
                continue;
            };

            if source.matches_any(expected_ids) {
                return Some(source);
            }
        }

        None
    }

    fn input_source_id(source: TISInputSourceRef) -> Option<String> {
        let value = unsafe { TISGetInputSourceProperty(source, kTISPropertyInputSourceID) };
        cf_string_to_string(value as CFStringRef)
    }

    fn cf_string_to_string(value: CFStringRef) -> Option<String> {
        if value.is_null() {
            return None;
        }

        let length = unsafe { CFStringGetLength(value) };
        let capacity = (unsafe { CFStringGetMaximumSizeForEncoding(length, kCFStringEncodingUTF8) }
            + 1)
        .max(1) as usize;
        let mut buffer = vec![0i8; capacity];
        let copied = unsafe {
            CFStringGetCString(
                value,
                buffer.as_mut_ptr(),
                capacity as isize,
                kCFStringEncodingUTF8,
            ) != 0
        };
        if !copied {
            return None;
        }

        unsafe { CStr::from_ptr(buffer.as_ptr()) }
            .to_str()
            .ok()
            .map(str::to_owned)
    }
}

#[cfg(not(target_os = "macos"))]
mod approval_input {
    #[derive(Default)]
    pub struct ApprovalInputGuard;

    impl ApprovalInputGuard {
        pub fn activate(&mut self) {}

        pub fn deactivate(&mut self) {}
    }
}

fn push_transcript_entry_lines(
    lines: &mut Vec<Line<'static>>,
    width: usize,
    entry: &TranscriptEntry,
) {
    match entry {
        TranscriptEntry::User { text, attachments } => {
            push_user_entry_lines(lines, width, text, attachments)
        }
        TranscriptEntry::Assistant(text) => push_assistant_entry_lines(lines, width, text),
        TranscriptEntry::Meta { text, tone } => push_meta_entry_lines(lines, width, text, *tone),
    }
}

fn push_user_entry_lines(
    lines: &mut Vec<Line<'static>>,
    width: usize,
    text: &str,
    attachments: &[ChatAttachmentData],
) {
    let line_start = lines.len();
    for attachment in attachments {
        lines.push(attachment_chip_line(attachment, width, false, "  "));
    }
    if !text.trim().is_empty() {
        push_wrapped_lines(
            lines,
            width,
            "> ",
            "  ",
            text,
            Style::default()
                .fg(Color::Green)
                .add_modifier(Modifier::BOLD),
        );
    }
    if lines.len() > line_start {
        lines.push(Line::from(""));
    }
}

fn push_assistant_entry_lines(lines: &mut Vec<Line<'static>>, width: usize, text: &str) {
    let line_start = lines.len();
    push_wrapped_lines(
        lines,
        width,
        "< ",
        "  ",
        text,
        Style::default().fg(Color::Cyan),
    );
    if lines.len() > line_start {
        lines.push(Line::from(""));
    }
}

fn push_meta_entry_lines(lines: &mut Vec<Line<'static>>, width: usize, text: &str, tone: MetaTone) {
    let line_start = lines.len();
    push_wrapped_lines(lines, width, "· ", "  ", text, tone.style());
    if lines.len() > line_start {
        lines.push(Line::from(""));
    }
}

fn push_wrapped_lines(
    lines: &mut Vec<Line<'static>>,
    width: usize,
    first_prefix: &str,
    next_prefix: &str,
    text: &str,
    style: Style,
) {
    let prefix_width = display_width(first_prefix).max(display_width(next_prefix));
    let available_width = width.max(prefix_width + 4);
    let options = Options::new(available_width)
        .initial_indent(first_prefix)
        .subsequent_indent(next_prefix)
        .break_words(true)
        .word_splitter(textwrap::WordSplitter::NoHyphenation);

    for line in textwrap::wrap(text, &options) {
        lines.push(Line::from(Span::styled(line.into_owned(), style)));
    }
}

fn attachment_chip_line(
    attachment: &ChatAttachmentData,
    width: usize,
    removable: bool,
    left_padding: &str,
) -> Line<'static> {
    let hint = if removable {
        format!(" {}", chat_text("chat.input.attachment.remove_hint"))
    } else {
        String::new()
    };
    let label = attachment_inline_label(attachment, None);
    let prefix_width = display_width(left_padding);
    let available_width = width.saturating_sub(prefix_width);
    let hint_width = display_width(&hint);
    let body_budget = available_width
        .saturating_sub(display_width(&label))
        .saturating_sub(hint_width)
        .saturating_sub(4)
        .max(1);
    let body = truncate_text(&attachment_preview_text(attachment), body_budget);

    let mut spans = vec![Span::raw(left_padding.to_string())];
    spans.push(Span::styled("[", Style::default().fg(Color::DarkGray)));
    spans.push(Span::styled(
        label,
        attachment_label_style(attachment).add_modifier(Modifier::BOLD),
    ));
    spans.push(Span::styled("] ", Style::default().fg(Color::DarkGray)));
    spans.push(Span::styled(body, Style::default().fg(Color::Gray)));
    if !hint.is_empty() {
        spans.push(Span::styled(hint, Style::default().fg(Color::DarkGray)));
    }
    Line::from(spans)
}

fn render_pending_attachments(
    frame: &mut Frame<'_>,
    area: Rect,
    attachments: &[ChatAttachmentData],
) {
    if attachments.is_empty() || area.width == 0 || area.height == 0 {
        return;
    }

    let card_areas = attachment_card_areas(area, attachments.len());
    for (index, (attachment, card_area)) in attachments.iter().zip(card_areas.iter()).enumerate() {
        let title = attachment_inline_label(attachment, Some(index + 1));
        let block = Block::default()
            .borders(Borders::ALL)
            .border_style(attachment_card_border_style(attachment))
            .title(Line::from(vec![
                Span::raw(" "),
                Span::styled(
                    title,
                    attachment_label_style(attachment).add_modifier(Modifier::BOLD),
                ),
                Span::raw(" "),
            ]));
        frame.render_widget(block.clone(), *card_area);

        let inner = block.inner(*card_area);
        if inner.width == 0 || inner.height == 0 {
            continue;
        }

        let body_budget = inner.width.saturating_sub(1) as usize;
        let body = truncate_text(&attachment_preview_text(attachment), body_budget.max(1));
        let line = Line::from(vec![Span::styled(body, Style::default().fg(Color::Gray))]);
        frame.render_widget(Paragraph::new(line), inner);
    }
}

fn attachment_card_areas(area: Rect, attachment_count: usize) -> Vec<Rect> {
    if attachment_count == 0 || area.width == 0 || area.height == 0 {
        return Vec::new();
    }

    if attachment_count == 1 {
        return vec![area];
    }

    if area.width >= MIN_TWO_COLUMN_ATTACHMENT_WIDTH {
        let cols = Layout::default()
            .direction(Direction::Horizontal)
            .constraints([
                Constraint::Fill(1),
                Constraint::Length(1),
                Constraint::Fill(1),
            ])
            .split(area);
        return vec![cols[0], cols[2]];
    }

    Layout::default()
        .direction(Direction::Vertical)
        .constraints(vec![
            Constraint::Length(ATTACHMENT_CARD_HEIGHT);
            attachment_count
        ])
        .split(area)
        .iter()
        .copied()
        .take(attachment_count)
        .collect()
}

fn pending_attachment_preview_height(width: u16, attachment_count: usize) -> u16 {
    if attachment_count == 0 {
        return 0;
    }

    if attachment_count == 1 || width >= MIN_TWO_COLUMN_ATTACHMENT_WIDTH {
        ATTACHMENT_CARD_HEIGHT
    } else {
        ATTACHMENT_CARD_HEIGHT.saturating_mul(attachment_count as u16)
    }
}

fn attachment_preview_text(attachment: &ChatAttachmentData) -> String {
    let source = if attachment.kind == "image_ocr" {
        attachment.full_content.as_str()
    } else {
        attachment.display_text.as_str()
    };
    let normalized = source.split_whitespace().collect::<Vec<_>>().join(" ");
    if normalized.is_empty() {
        attachment.display_text.clone()
    } else {
        normalized
    }
}

fn attachment_inline_label(attachment: &ChatAttachmentData, index: Option<usize>) -> String {
    let base = if attachment.kind == "image_ocr" {
        match i18n::locale() {
            "zh-Hans" | "zh-Hant" => "图片",
            _ => "Image",
        }
    } else {
        match i18n::locale() {
            "zh-Hans" | "zh-Hant" => "剪贴",
            _ => "Clip",
        }
    };
    index
        .map(|index| format!("{base} {index}"))
        .unwrap_or_else(|| base.to_string())
}

fn attachment_label_style(attachment: &ChatAttachmentData) -> Style {
    if attachment.kind == "image_ocr" {
        Style::default().fg(Color::LightCyan)
    } else {
        Style::default().fg(Color::Gray)
    }
}

fn attachment_card_border_style(attachment: &ChatAttachmentData) -> Style {
    if attachment.kind == "image_ocr" {
        Style::default().fg(Color::Cyan)
    } else {
        Style::default().fg(Color::DarkGray)
    }
}

fn looks_like_path_payload(text: &str) -> bool {
    let parts: Vec<&str> = text
        .lines()
        .map(str::trim)
        .filter(|part| !part.is_empty())
        .collect();
    !parts.is_empty()
        && parts.iter().all(|part| {
            part.starts_with("file://") || part.starts_with('/') || part.starts_with("~/")
        })
}

fn centered_rect(percent_x: u16, percent_y: u16, rect: Rect) -> Rect {
    let vertical = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Percentage((100 - percent_y) / 2),
            Constraint::Percentage(percent_y),
            Constraint::Percentage((100 - percent_y) / 2),
        ])
        .split(rect);

    Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage((100 - percent_x) / 2),
            Constraint::Percentage(percent_x),
            Constraint::Percentage((100 - percent_x) / 2),
        ])
        .split(vertical[1])[1]
}

struct SingleLineInputView {
    visible_text: String,
    cursor_col: usize,
}

fn single_line_input_view(text: &str, cursor: usize, width: usize) -> SingleLineInputView {
    let width = width.max(1);
    let cursor = cursor.min(char_count(text));
    let chars: Vec<char> = text.chars().collect();

    let max_cursor_width = width.saturating_sub(1);
    let mut start = 0usize;
    let mut cursor_width = 0usize;

    for (index, ch) in chars.iter().enumerate().take(cursor) {
        cursor_width += char_display_width(*ch);
        while cursor_width > max_cursor_width && start <= index {
            cursor_width = cursor_width.saturating_sub(char_display_width(chars[start]));
            start += 1;
        }
    }

    let mut used = 0usize;
    let mut visible_text = String::new();
    for ch in chars.iter().skip(start) {
        let ch_width = char_display_width(*ch);
        if used + ch_width > width {
            break;
        }
        visible_text.push(*ch);
        used += ch_width;
    }

    SingleLineInputView {
        visible_text,
        cursor_col: cursor_width.min(used),
    }
}

fn provider_display_name(provider: &str) -> &str {
    match provider {
        "chatgpt" => "ChatGPT",
        "openai_api" => "OpenAI API",
        "anthropic" => "Anthropic API",
        "ollama" => "Ollama",
        _ => provider,
    }
}

struct WrappedInputRow {
    text: String,
    start_char: usize,
    end_char: usize,
}

struct WrappedInputLayout {
    rows: Vec<WrappedInputRow>,
    cursor_row: usize,
    cursor_col: usize,
}

struct InputViewport {
    visible_lines: Vec<String>,
    cursor_row: usize,
    cursor_col: usize,
    start_row: usize,
}

fn input_panel_height(app: &ChatApp, width: u16) -> u16 {
    let input_width = width.saturating_sub(4) as usize;
    let layout = wrapped_input_layout(&app.input, app.input_cursor, input_width.max(1));
    let visible_lines = layout.rows.len().clamp(1, MAX_INPUT_VISIBLE_LINES as usize);
    let attachment_height =
        pending_attachment_preview_height(width.saturating_sub(2), app.pending_attachment_count());
    visible_lines as u16 + 2 + attachment_height
}

fn input_viewport(input: &str, cursor: usize, width: usize, height: usize) -> InputViewport {
    let width = width.max(1);
    let height = height.max(1);
    let layout = wrapped_input_layout(input, cursor, width);
    let max_start = layout.rows.len().saturating_sub(height);
    let start = layout
        .cursor_row
        .saturating_sub(height.saturating_sub(1))
        .min(max_start);
    let end = (start + height).min(layout.rows.len());
    let mut visible_lines: Vec<String> = layout.rows[start..end]
        .iter()
        .map(|row| row.text.clone())
        .collect();
    while visible_lines.len() < height {
        visible_lines.push(String::new());
    }

    InputViewport {
        visible_lines,
        cursor_row: layout.cursor_row.saturating_sub(start).min(height - 1),
        cursor_col: layout.cursor_col.min(width.saturating_sub(1)),
        start_row: start,
    }
}

fn wrapped_input_layout(input: &str, cursor: usize, width: usize) -> WrappedInputLayout {
    let width = width.max(1);
    let cursor = cursor.min(char_count(input));
    let mut rows = vec![WrappedInputRow {
        text: String::new(),
        start_char: 0,
        end_char: 0,
    }];
    let mut row = 0usize;
    let mut col = 0usize;
    let mut offset = 0usize;
    let mut cursor_row = 0usize;
    let mut cursor_col = 0usize;

    for ch in input.chars() {
        if offset == cursor {
            cursor_row = row;
            cursor_col = col;
        }

        if ch == '\n' {
            rows[row].end_char = offset;
            row += 1;
            rows.push(WrappedInputRow {
                text: String::new(),
                start_char: offset + 1,
                end_char: offset + 1,
            });
            col = 0;
            offset += 1;
            continue;
        }

        let ch_width = char_display_width(ch);
        if !rows[row].text.is_empty() && col + ch_width > width {
            rows[row].end_char = offset;
            row += 1;
            rows.push(WrappedInputRow {
                text: String::new(),
                start_char: offset,
                end_char: offset,
            });
            col = 0;
            if offset == cursor {
                cursor_row = row;
                cursor_col = 0;
            }
        }

        rows[row].text.push(ch);
        col += ch_width;
        offset += 1;
        rows[row].end_char = offset;
    }

    if offset == cursor {
        cursor_row = row;
        cursor_col = col;
    }

    if rows[cursor_row].end_char == cursor && cursor_col >= width {
        if rows
            .get(cursor_row + 1)
            .is_some_and(|next_row| next_row.start_char == cursor)
        {
            cursor_row += 1;
            cursor_col = 0;
        } else {
            rows.insert(
                cursor_row + 1,
                WrappedInputRow {
                    text: String::new(),
                    start_char: cursor,
                    end_char: cursor,
                },
            );
            cursor_row += 1;
            cursor_col = 0;
        }
    }

    WrappedInputLayout {
        rows,
        cursor_row,
        cursor_col,
    }
}

fn char_display_width(ch: char) -> usize {
    UnicodeWidthChar::width(ch).unwrap_or(0).max(1)
}

fn cursor_from_visual_position(layout: &WrappedInputLayout, row: usize, col: usize) -> usize {
    let Some(target_row) = layout.rows.get(row).or_else(|| layout.rows.last()) else {
        return 0;
    };

    let mut best_index = target_row.start_char;
    let mut best_distance = usize::MAX;
    let mut display_col = 0usize;
    let mut char_index = target_row.start_char;

    let mut consider = |candidate_col: usize, candidate_index: usize| {
        let distance = candidate_col.abs_diff(col);
        if distance <= best_distance {
            best_distance = distance;
            best_index = candidate_index;
        }
    };

    consider(0, target_row.start_char);
    for ch in target_row.text.chars() {
        display_col += char_display_width(ch);
        char_index += 1;
        consider(display_col, char_index);
    }

    best_index
}

fn current_line_bounds(text: &str, cursor: usize) -> (usize, usize) {
    let cursor = cursor.min(char_count(text));
    let chars: Vec<char> = text.chars().collect();
    let mut start = cursor;
    while start > 0 && chars[start - 1] != '\n' {
        start -= 1;
    }

    let mut end = cursor;
    while end < chars.len() && chars[end] != '\n' {
        end += 1;
    }

    (start, end)
}

fn move_cursor_vertical(text: &str, cursor: usize, width: usize, delta: isize) -> usize {
    let layout = wrapped_input_layout(text, cursor, width.max(1));
    if layout.rows.is_empty() {
        return 0;
    }

    let target_row = if delta < 0 {
        layout.cursor_row.saturating_sub(delta.unsigned_abs())
    } else {
        (layout.cursor_row + delta as usize).min(layout.rows.len().saturating_sub(1))
    };

    if target_row == layout.cursor_row {
        return if delta < 0 {
            layout.rows[target_row].start_char
        } else {
            layout.rows[target_row].end_char
        };
    }

    cursor_from_visual_position(&layout, target_row, layout.cursor_col)
}

fn point_in_rect(column: u16, row: u16, rect: Rect) -> bool {
    column >= rect.x
        && column < rect.x.saturating_add(rect.width)
        && row >= rect.y
        && row < rect.y.saturating_add(rect.height)
}

fn scrollbar_thumb_metrics(
    total_lines: usize,
    visible_lines: usize,
    scroll: usize,
    track_height: usize,
) -> (usize, usize) {
    let total_lines = total_lines.max(1);
    let visible_lines = visible_lines.max(1).min(total_lines);
    let track_height = track_height.max(1);
    let max_scroll = total_lines.saturating_sub(visible_lines);
    let thumb_height =
        ((visible_lines * track_height) + total_lines.saturating_sub(1)) / total_lines;
    let thumb_height = thumb_height.clamp(1, track_height);
    let max_thumb_top = track_height.saturating_sub(thumb_height);
    let thumb_top = if max_scroll == 0 {
        0
    } else {
        scroll.min(max_scroll) * max_thumb_top / max_scroll
    };

    (thumb_top, thumb_height)
}

fn render_scrollbar(
    frame: &mut Frame<'_>,
    area: Rect,
    total_lines: usize,
    visible_lines: usize,
    scroll: usize,
    track_color: Color,
    thumb_color: Color,
) {
    if area.width == 0 || area.height == 0 {
        return;
    }

    let total_lines = total_lines.max(1);
    let visible_lines = visible_lines.max(1).min(total_lines);
    if total_lines <= visible_lines {
        return;
    }
    let height = area.height as usize;
    let (thumb_top, thumb_height) =
        scrollbar_thumb_metrics(total_lines, visible_lines, scroll, height);

    let lines: Vec<Line<'_>> = (0..height)
        .map(|row| {
            let (symbol, color) = if row >= thumb_top && row < thumb_top + thumb_height {
                ("█", thumb_color)
            } else {
                ("│", track_color)
            };
            Line::from(Span::styled(symbol, Style::default().fg(color)))
        })
        .collect();
    frame.render_widget(Paragraph::new(lines), area);
}

fn truncate_text(text: &str, width: usize) -> String {
    if width == 0 {
        return String::new();
    }

    if display_width(text) <= width {
        return text.to_string();
    }

    if width == 1 {
        return "…".to_string();
    }

    let mut truncated = String::new();
    let mut used = 0usize;
    for ch in text.chars() {
        let char_width = char_display_width(ch);
        if used + char_width > width.saturating_sub(1) {
            break;
        }
        truncated.push(ch);
        used += char_width;
    }
    truncated.push('…');
    truncated
}

fn char_count(text: &str) -> usize {
    text.chars().count()
}

fn byte_index_from_char(text: &str, char_index: usize) -> usize {
    if char_index == 0 {
        return 0;
    }

    text.char_indices()
        .nth(char_index)
        .map(|(index, _)| index)
        .unwrap_or_else(|| text.len())
}

fn insert_char_at(text: &mut String, cursor: &mut usize, ch: char) {
    let index = byte_index_from_char(text, *cursor);
    text.insert(index, ch);
    *cursor += 1;
}

fn insert_text_at(text: &mut String, cursor: &mut usize, inserted: &str) {
    let index = byte_index_from_char(text, *cursor);
    text.insert_str(index, inserted);
    *cursor += char_count(inserted);
}

fn delete_before_cursor(text: &mut String, cursor: &mut usize) {
    if *cursor == 0 {
        return;
    }

    let start = byte_index_from_char(text, (*cursor).saturating_sub(1));
    let end = byte_index_from_char(text, *cursor);
    text.replace_range(start..end, "");
    *cursor = (*cursor).saturating_sub(1);
}

fn delete_to_line_start_in_text(text: &mut String, cursor: &mut usize) {
    let (start, _) = current_line_bounds(text, *cursor);
    if start == *cursor {
        return;
    }

    let byte_start = byte_index_from_char(text, start);
    let byte_end = byte_index_from_char(text, *cursor);
    text.replace_range(byte_start..byte_end, "");
    *cursor = start;
}

fn delete_at_cursor(text: &mut String, cursor: usize) {
    if cursor >= char_count(text) {
        return;
    }

    let start = byte_index_from_char(text, cursor);
    let end = byte_index_from_char(text, cursor + 1);
    text.replace_range(start..end, "");
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

fn display_width(text: &str) -> usize {
    text.chars()
        .map(|ch| match ch {
            '\t' => 4,
            _ if ch.is_ascii() => 1,
            _ => 2,
        })
        .sum()
}

fn truncate_display(text: &str, max_width: usize) -> String {
    if max_width == 0 {
        return String::new();
    }

    if display_width(text) <= max_width {
        return text.to_string();
    }

    if max_width <= 3 {
        return ".".repeat(max_width);
    }

    let mut output = String::new();
    let mut used = 0;
    for ch in text.chars() {
        let width = if ch.is_ascii() { 1 } else { 2 };
        if used + width > max_width.saturating_sub(3) {
            break;
        }
        output.push(ch);
        used += width;
    }
    output.push_str("...");
    output
}

fn spaced_line(
    left: &str,
    left_style: Style,
    right: &str,
    right_style: Style,
    width: usize,
) -> Line<'static> {
    let right_width = display_width(right);
    let left_budget = if right.is_empty() || width <= right_width + 1 {
        width
    } else {
        width.saturating_sub(right_width + 1)
    };
    let left = truncate_display(left, left_budget);
    let padding = if right.is_empty() || width <= right_width + display_width(&left) {
        String::new()
    } else {
        " ".repeat(width.saturating_sub(display_width(&left) + right_width))
    };

    Line::from(vec![
        Span::styled(left, left_style),
        Span::raw(padding),
        Span::styled(right.to_string(), right_style),
    ])
}

fn tool_status_text(tool: &ToolEventData, search_call_count: usize) -> String {
    if tool.tool == "search_clipboard" {
        let query = tool
            .parameters
            .get("query")
            .and_then(Value::as_str)
            .map(str::trim)
            .unwrap_or("");
        let display_query = if query.is_empty() { "(empty)" } else { query };
        let suffix = if search_call_count > 1 {
            format!(" +{}", search_call_count - 1)
        } else {
            String::new()
        };
        return format!("Searching \"{}\"{}", display_query, suffix);
    }

    match tool.tool.as_str() {
        "write_clipboard" => "Writing to clipboard...".to_string(),
        "delete_clipboard" => "Deleting...".to_string(),
        "list_script_plugins" => "Listing plugins...".to_string(),
        "read_script_plugin" => "Reading plugin...".to_string(),
        "read_skill_detail" => "Reading skill...".to_string(),
        "record_memory" => "Saving memory...".to_string(),
        "delete_memory" => "Deleting memory...".to_string(),
        "save_session_context" => "Saving session context...".to_string(),
        "read_session_context" => "Reading session context...".to_string(),
        "delete_session_context" => "Deleting session context...".to_string(),
        "run_script_transform" => "Running script plugin...".to_string(),
        "generate_script_plugin" => "Creating script plugin...".to_string(),
        "modify_script_plugin" => "Modifying script plugin...".to_string(),
        "delete_script_plugin" => "Deleting script plugin...".to_string(),
        "generate_smart_rule" => "Creating smart rule...".to_string(),
        _ => format!("Running {}...", tool.tool),
    }
}

fn approval_preview(tool: &ToolEventData) -> String {
    match tool.tool.as_str() {
        "write_clipboard" => tool
            .parameters
            .get("text")
            .and_then(Value::as_str)
            .map(|text| {
                chat_format(
                    "chat.approval.write_text",
                    &[("{text}", trim_preview(text, 600))],
                )
            })
            .unwrap_or_else(|| chat_text("chat.approval.write_text_default")),
        "delete_clipboard" => tool
            .parameters
            .get("item_id")
            .and_then(Value::as_i64)
            .map(|id| chat_format("chat.approval.delete_item", &[("{id}", id.to_string())]))
            .unwrap_or_else(|| chat_text("chat.approval.delete_default")),
        _ => match serde_json::to_string_pretty(&tool.parameters) {
            Ok(json) => trim_preview(&json, 800),
            Err(_) => chat_text("chat.approval.generic"),
        },
    }
}

fn trim_preview(text: &str, max_chars: usize) -> String {
    let chars: Vec<char> = text.chars().collect();
    if chars.len() <= max_chars {
        return text.to_string();
    }
    chars.into_iter().take(max_chars).collect::<String>() + "..."
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
mod tests {
    use super::*;
    use std::hint::black_box;
    use std::time::Instant;

    fn test_app() -> ChatApp {
        ChatApp::from_bootstrap(BootstrapData {
            configured: true,
            account: None,
            provider: Some("AI".to_string()),
            model: Some("test".to_string()),
            session_id: None,
            conversation_id: None,
            busy: Some(false),
        })
    }

    fn test_attachment() -> ChatAttachmentData {
        ChatAttachmentData {
            kind: "image_ocr".to_string(),
            display_text: "截图文字".to_string(),
            full_content: "截图里的完整文字".to_string(),
            ocr_text: Some("截图里的完整文字".to_string()),
            source_item_id: Some("test-item".to_string()),
        }
    }

    fn synthetic_text(target_bytes: usize) -> String {
        const SEED: &str = "Deck benchmark mixed-width 文本 1234567890 ";
        let mut text = String::with_capacity(target_bytes.max(SEED.len()));
        while text.len() < target_bytes {
            text.push_str(SEED);
        }
        while text.len() > target_bytes {
            text.pop();
        }
        text
    }

    fn synthetic_transcript(entry_count: usize, bytes_per_entry: usize) -> Vec<TranscriptEntry> {
        (0..entry_count)
            .map(|index| {
                let text = synthetic_text(bytes_per_entry);
                if index % 2 == 0 {
                    TranscriptEntry::User {
                        text,
                        attachments: Vec::new(),
                    }
                } else {
                    TranscriptEntry::Assistant(text)
                }
            })
            .collect()
    }

    fn env_usize(key: &str, default: usize) -> usize {
        std::env::var(key)
            .ok()
            .and_then(|value| value.parse().ok())
            .unwrap_or(default)
    }

    fn peak_rss_megabytes() -> Option<u64> {
        let mut usage = std::mem::MaybeUninit::<libc::rusage>::zeroed();
        let status = unsafe { libc::getrusage(libc::RUSAGE_SELF, usage.as_mut_ptr()) };
        if status != 0 {
            return None;
        }

        let usage = unsafe { usage.assume_init() };
        #[cfg(target_os = "macos")]
        let bytes = usage.ru_maxrss as u64;
        #[cfg(not(target_os = "macos"))]
        let bytes = (usage.ru_maxrss as u64) * 1024;
        Some(bytes / (1024 * 1024))
    }

    #[test]
    #[ignore = "run manually for performance metrics"]
    fn chat_render_perf_report() {
        let entry_count = env_usize("DECKCLIP_PERF_MESSAGES", 4_000);
        let bytes_per_entry = env_usize("DECKCLIP_PERF_CHARS", 256);
        let width = env_usize("DECKCLIP_PERF_WIDTH", 96);
        let viewport_height = env_usize("DECKCLIP_PERF_VIEWPORT_HEIGHT", 24);
        let cached_passes = env_usize("DECKCLIP_PERF_CACHED_PASSES", 1_000);
        let slice_passes = env_usize("DECKCLIP_PERF_SLICE_PASSES", 2_000);
        let stream_updates = env_usize("DECKCLIP_PERF_STREAM_DELTAS", 1_000);

        let mut app = test_app();
        app.conversation_entries = synthetic_transcript(entry_count, bytes_per_entry);
        app.bump_transcript_revision();

        let build_started = Instant::now();
        let total_lines = black_box(app.transcript_lines(width).len());
        let cold_build = build_started.elapsed();

        let cached_started = Instant::now();
        for _ in 0..cached_passes {
            black_box(app.transcript_lines(width).len());
        }
        let cached_lookup = cached_started.elapsed();

        let scroll = total_lines
            .saturating_sub(viewport_height)
            .saturating_div(2);
        let visible_started = Instant::now();
        for _ in 0..slice_passes {
            let lines = app.transcript_lines(width);
            let end = (scroll + viewport_height).min(lines.len());
            black_box(lines[scroll..end].to_vec());
        }
        let visible_slice = visible_started.elapsed();

        app.begin_send();
        let delta = synthetic_text((bytes_per_entry / 4).max(32));
        let stream_started = Instant::now();
        for _ in 0..stream_updates {
            app.streaming_text.push_str(&delta);
            app.bump_streaming_revision();
            black_box(app.transcript_lines(width).len());
        }
        let streaming_tail = stream_started.elapsed();

        eprintln!(
            "deckclip_chat_perf entries={} bytes_per_entry={} width={} total_lines={} cold_build_ms={:.2} cached_lookup_ms={:.2} visible_slice_ms={:.2} streaming_tail_ms={:.2} peak_rss_mb={}",
            entry_count,
            bytes_per_entry,
            width,
            total_lines,
            cold_build.as_secs_f64() * 1000.0,
            cached_lookup.as_secs_f64() * 1000.0,
            visible_slice.as_secs_f64() * 1000.0,
            streaming_tail.as_secs_f64() * 1000.0,
            peak_rss_megabytes()
                .map(|value| value.to_string())
                .unwrap_or_else(|| "n/a".to_string()),
        );

        assert!(total_lines > 0);
    }

    #[test]
    fn wrapped_input_layout_tracks_cjk_cursor_columns() {
        let layout = wrapped_input_layout("你好", 2, 12);
        assert_eq!(layout.rows.len(), 1);
        assert_eq!(layout.cursor_row, 0);
        assert_eq!(layout.cursor_col, 4);
    }

    #[test]
    fn wrapped_input_layout_keeps_ascii_after_cjk_at_visual_end() {
        let layout = wrapped_input_layout("你好我叫A", 5, 12);
        assert_eq!(layout.rows[0].text, "你好我叫A");
        assert_eq!(layout.cursor_col, 9);
    }

    #[test]
    fn cursor_from_visual_position_prefers_nearest_boundary() {
        let layout = wrapped_input_layout("你好", 0, 12);
        assert_eq!(cursor_from_visual_position(&layout, 0, 0), 0);
        assert_eq!(cursor_from_visual_position(&layout, 0, 1), 1);
        assert_eq!(cursor_from_visual_position(&layout, 0, 4), 2);
    }

    #[test]
    fn input_history_browses_multiple_entries_and_restores_draft() {
        let mut app = test_app();
        app.remember_input("你好");
        app.remember_input("/cost");

        assert!(app.browse_input_history_up());
        assert_eq!(app.input, "/cost");
        assert!(app.browse_input_history_up());
        assert_eq!(app.input, "你好");
        assert!(app.browse_input_history_down());
        assert_eq!(app.input, "/cost");
        assert!(app.browse_input_history_down());
        assert_eq!(app.input, "");
    }

    #[test]
    fn delete_to_line_start_resets_slash_selected_footer() {
        let mut app = test_app();
        app.set_input("/help".to_string());
        app.set_tagged_footer(
            chat_format(
                "chat.footer.slash_selected",
                &[("{command}", "/help".to_string())],
            ),
            MetaTone::Dim,
            FooterTag::SlashSelected,
        );

        app.delete_to_line_start();

        assert_eq!(app.input, "");
        assert!(app.footer_message.is_none());
        assert!(app.footer_tag.is_none());
    }

    #[test]
    fn delete_to_line_start_only_removes_text_before_cursor() {
        let mut app = test_app();
        app.set_input("hello\nworld".to_string());
        app.input_cursor = char_count("hello\nwo");

        app.delete_to_line_start();

        assert_eq!(app.input, "hello\nrld");
        assert_eq!(app.input_cursor, char_count("hello\n"));
    }

    #[test]
    fn delete_to_line_start_at_line_start_is_noop() {
        let mut app = test_app();
        app.set_input("hello\n\n".to_string());

        app.delete_to_line_start();

        assert_eq!(app.input, "hello\n\n");
        assert_eq!(app.input_cursor, char_count("hello\n\n"));
    }

    fn lines_text(lines: &[Line<'static>]) -> String {
        lines
            .iter()
            .map(|line| {
                line.spans
                    .iter()
                    .map(|span| span.content.as_ref())
                    .collect::<String>()
            })
            .collect::<Vec<_>>()
            .join("\n")
    }

    fn tool_event(call_id: &str, tool: &str, parameters: Value) -> ToolEventData {
        ToolEventData {
            call_id: call_id.to_string(),
            tool: tool.to_string(),
            parameters,
            approved: None,
            result: None,
        }
    }

    #[test]
    fn streaming_tail_uses_plain_thinking_label() {
        let mut app = test_app();
        app.begin_send();

        let text = lines_text(&build_transcript_tail_lines(&app, 48));

        assert!(text.contains("Thinking"));
        assert!(!text.contains("Deck AI"));
    }

    #[test]
    fn thinking_tail_has_right_offset() {
        let mut app = test_app();
        app.begin_send();

        let text = lines_text(&build_transcript_tail_lines(&app, 48));

        assert_eq!(text, format!("  {} Thinking", app.spinner_frame()));
    }

    #[test]
    fn short_status_tail_stays_at_bottom() {
        let mut app = test_app();
        app.begin_send();

        let lines = transcript_view_lines(&mut app, 48, 4);
        let rendered = lines
            .iter()
            .map(|line| {
                line.spans
                    .iter()
                    .map(|span| span.content.as_ref())
                    .collect::<String>()
            })
            .collect::<Vec<_>>();

        assert_eq!(
            rendered,
            vec![
                String::new(),
                String::new(),
                String::new(),
                format!("  {} Thinking", app.spinner_frame()),
            ]
        );
    }

    #[test]
    fn tool_events_replace_thinking_without_appending_activity() {
        let mut app = test_app();
        app.begin_send();

        handle_ui_event(
            &mut app,
            UiEvent::ToolStarted(tool_event(
                "call-1",
                "record_memory",
                serde_json::json!({"memory": "Sam Altman"}),
            )),
        );

        assert_eq!(app.activities.len(), 0);
        assert_eq!(app.busy_action.as_deref(), Some("Saving memory..."));
        assert!(app.status_text().contains("Saving memory..."));

        handle_ui_event(
            &mut app,
            UiEvent::ToolFinished(ToolEventData {
                call_id: "call-1".to_string(),
                tool: "record_memory".to_string(),
                parameters: serde_json::json!({"memory": "Sam Altman"}),
                approved: Some(true),
                result: Some(serde_json::json!({"ok": true})),
            }),
        );

        assert_eq!(app.activities.len(), 0);
        assert!(app.busy_action_release_at.is_some());
    }

    #[test]
    fn repeated_search_tool_status_matches_app_style() {
        let mut app = test_app();
        app.begin_send();

        handle_ui_event(
            &mut app,
            UiEvent::ToolStarted(tool_event(
                "search-1",
                "search_clipboard",
                serde_json::json!({"query": "hello"}),
            )),
        );
        assert_eq!(app.busy_action.as_deref(), Some("Searching \"hello\""));

        handle_ui_event(
            &mut app,
            UiEvent::ToolStarted(tool_event(
                "search-2",
                "search_clipboard",
                serde_json::json!({"query": "hello"}),
            )),
        );
        assert_eq!(app.busy_action.as_deref(), Some("Searching \"hello\" +1"));
    }

    #[test]
    fn quit_hint_footer_uses_trigger_specific_text() {
        let mut app = test_app();

        app.arm_quit_hint(QuitHintTrigger::Esc);

        assert_eq!(
            app.footer_message.as_ref().map(|(text, _)| text.as_str()),
            Some(chat_text("chat.quit_hint.esc").as_str())
        );
        assert_eq!(
            app.footer_tag,
            Some(FooterTag::QuitHint(QuitHintTrigger::Esc))
        );
    }

    #[test]
    fn input_panel_height_adds_attachment_row() {
        let mut app = test_app();
        let base = input_panel_height(&app, 48);

        app.set_pending_attachment(test_attachment());

        assert_eq!(input_panel_height(&app, 48), base + ATTACHMENT_CARD_HEIGHT);
    }

    #[test]
    fn replace_session_restores_user_attachment() {
        let mut app = test_app();
        let attachment = test_attachment();

        app.replace_session(
            SessionData {
                session_id: "session-1".to_string(),
                conversation: ConversationData {
                    id: "conversation-1".to_string(),
                    title: "Test".to_string(),
                    provider: "AI".to_string(),
                    model: "test".to_string(),
                    messages: vec![ConversationMessageData {
                        role: "user".to_string(),
                        text: "".to_string(),
                        attachment: Some(attachment.clone()),
                        attachments: Vec::new(),
                    }],
                },
                context_usage: None,
                last_assistant_text: None,
            },
            false,
        );

        match &app.conversation_entries[0] {
            TranscriptEntry::User { text, attachments } => {
                assert!(text.is_empty());
                assert_eq!(attachments.len(), 1);
                assert_eq!(attachments[0].display_text, attachment.display_text);
            }
            other => panic!("unexpected transcript entry: {other:?}"),
        }
    }

    #[test]
    fn slash_command_normalizes_model_alias() {
        assert_eq!(normalize_slash_command("/model"), Some("/model"));
    }

    #[test]
    fn defaults_key_maps_current_provider_model_keys() {
        assert_eq!(deck_model_defaults_key("chatgpt"), Some("aiChatGPTModel"));
        assert_eq!(deck_model_defaults_key("openai_api"), Some("aiOpenAIModel"));
        assert_eq!(
            deck_model_defaults_key("anthropic"),
            Some("aiAnthropicModel")
        );
        assert_eq!(deck_model_defaults_key("ollama"), Some("aiOllamaModel"));
        assert_eq!(deck_model_defaults_key("unknown"), None);
    }

    #[test]
    fn visible_list_window_keeps_selected_slash_item_visible() {
        assert_eq!(visible_list_window(0, 6, 6), (0, 6));
        assert_eq!(visible_list_window(5, 6, 5), (1, 5));
        assert_eq!(visible_list_window(4, 8, 5), (0, 5));
        assert_eq!(visible_list_window(7, 8, 5), (3, 5));
    }

    #[test]
    fn ctrl_o_opens_model_editor() {
        let mut app = test_app();
        let client = Arc::new(Mutex::new(DeckClient::new(Config::default())));
        let (ui_tx, _ui_rx) = unbounded_channel();

        handle_key_event(
            &mut app,
            KeyEvent::new(KeyCode::Char('o'), KeyModifiers::CONTROL),
            client,
            ui_tx,
        );

        assert!(matches!(app.overlay, OverlayState::ModelEditor(_)));
    }
}
