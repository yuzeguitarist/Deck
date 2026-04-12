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
use serde::Deserialize;
use serde_json::Value;
use textwrap::Options;
use tokio::sync::mpsc::{unbounded_channel, UnboundedSender};
use tokio::sync::Mutex;
use unicode_width::UnicodeWidthChar;

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
    approved: Option<bool>,
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
    User(String),
    Assistant(String),
    Meta { text: String, tone: MetaTone },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ChatMode {
    Ready,
    Streaming,
    AwaitingApproval,
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
    next_cursor: Option<String>,
    has_more: bool,
    loading_more: bool,
}

#[derive(Debug, Clone)]
enum OverlayState {
    None,
    Approval(ApprovalOverlay),
    History(HistoryOverlay),
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
    AssistantDelta(String),
    ToolStarted(ToolEventData),
    ToolFinished(ToolEventData),
    ApprovalRequested(ToolEventData),
    Compacting(CompactingEventData),
    Done(DoneEventData),
    HistoryLoaded { data: HistoryListData, append: bool },
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
    input_history: Vec<String>,
    input_history_index: Option<usize>,
    input_history_draft: String,
    input_visual_width: u16,
    input_text_area: Option<Rect>,
    slash_selected: usize,
    overlay: OverlayState,
    mode: ChatMode,
    footer_message: Option<(String, MetaTone)>,
    busy_action: Option<String>,
    busy_started_at: Option<Instant>,
    streaming_text: String,
    last_assistant_text: Option<String>,
    tool_states: HashMap<String, ToolLifecycle>,
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
            input_history: Vec::new(),
            input_history_index: None,
            input_history_draft: String::new(),
            input_visual_width: 1,
            input_text_area: None,
            slash_selected: 0,
            overlay: OverlayState::None,
            mode: ChatMode::Ready,
            footer_message: Some((chat_text("chat.footer.ready"), MetaTone::Dim)),
            busy_action: None,
            busy_started_at: None,
            streaming_text: String::new(),
            last_assistant_text: None,
            tool_states: HashMap::new(),
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
                "user" => Some(TranscriptEntry::User(message.text)),
                "assistant" => Some(TranscriptEntry::Assistant(message.text)),
                _ => None,
            })
            .collect();

        if clear_ephemeral {
            self.activities.clear();
            self.tool_states.clear();
            self.streaming_text.clear();
            self.overlay = OverlayState::None;
            self.mode = ChatMode::Ready;
            self.mode_started_at = None;
            self.clear_busy_action();
            self.clear_input();
        }

        self.auto_scroll = true;
    }

    fn conversation_updated(&mut self, session: SessionData) {
        self.replace_session(session, false);
    }

    fn push_activity(&mut self, text: impl Into<String>, tone: MetaTone) {
        self.activities.push(TranscriptEntry::Meta {
            text: text.into(),
            tone,
        });
    }

    fn set_footer(&mut self, text: impl Into<String>, tone: MetaTone) {
        self.footer_message = Some((text.into(), tone));
    }

    fn set_busy_action(&mut self, text: impl Into<String>) {
        self.busy_action = Some(text.into());
        self.busy_started_at = Some(Instant::now());
    }

    fn clear_busy_action(&mut self) {
        self.busy_action = None;
        self.busy_started_at = None;
    }

    fn begin_send(&mut self) {
        self.mode = ChatMode::Streaming;
        self.mode_started_at = Some(Instant::now());
        self.streaming_text.clear();
        self.activities.clear();
        self.tool_states.clear();
        self.overlay = OverlayState::None;
        self.auto_scroll = true;
        self.clear_quit_hint();
        self.set_footer(chat_text("chat.footer.generating"), MetaTone::Info);
    }

    fn finish_send(&mut self) {
        self.mode = ChatMode::Ready;
        self.mode_started_at = None;
        self.streaming_text.clear();
        self.overlay = OverlayState::None;
        self.clear_busy_action();
    }

    fn status_text(&self) -> String {
        if let Some(action) = &self.busy_action {
            return format!("{} {}", self.spinner_frame(), action);
        }
        match self.mode {
            ChatMode::Ready => chat_text("chat.status.ready"),
            ChatMode::Streaming => chat_format(
                "chat.status.thinking",
                &[
                    ("{spinner}", self.spinner_frame().to_string()),
                    ("{elapsed}", self.elapsed_suffix()),
                ],
            ),
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

    fn all_entries(&self) -> Vec<TranscriptEntry> {
        let mut entries = self.conversation_entries.clone();
        entries.extend(self.activities.clone());
        if !self.streaming_text.is_empty() {
            entries.push(TranscriptEntry::Assistant(self.streaming_text.clone()));
        } else if self.mode == ChatMode::Streaming {
            entries.push(TranscriptEntry::Meta {
                text: chat_format(
                    "chat.meta.thinking",
                    &[
                        ("{spinner}", self.spinner_frame().to_string()),
                        ("{elapsed}", self.elapsed_suffix()),
                    ],
                ),
                tone: MetaTone::Dim,
            });
        } else if self.mode == ChatMode::AwaitingApproval {
            entries.push(TranscriptEntry::Meta {
                text: chat_format(
                    "chat.meta.waiting_approval",
                    &[
                        ("{spinner}", self.spinner_frame().to_string()),
                        ("{elapsed}", self.elapsed_suffix()),
                    ],
                ),
                tone: MetaTone::Warning,
            });
        }
        entries
    }

    fn spinner_frame(&self) -> &'static str {
        let elapsed_ms = self.created_at.elapsed().as_millis() as usize;
        THINKING_FRAMES[(elapsed_ms / 80) % THINKING_FRAMES.len()]
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

    fn clear_input(&mut self) {
        self.input.clear();
        self.input_cursor = 0;
        self.input_history_index = None;
        self.input_history_draft.clear();
        self.slash_selected = 0;
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
        self.streaming_text.clear();
        self.last_assistant_text = None;
        self.overlay = OverlayState::None;
        self.mode = ChatMode::Ready;
        self.mode_started_at = None;
        self.auto_scroll = true;
        self.scroll = 0;
        self.dragging_body_scrollbar = false;
        self.clear_busy_action();
        self.clear_input();
    }

    fn set_input(&mut self, value: String) {
        self.input = value;
        self.input_cursor = char_count(&self.input);
        self.input_history_index = None;
        self.refresh_slash_selection();
    }

    fn insert_char(&mut self, ch: char) {
        insert_char_at(&mut self.input, &mut self.input_cursor, ch);
        self.input_history_index = None;
        self.refresh_slash_selection();
        self.clear_quit_hint();
    }

    fn insert_text(&mut self, text: &str) {
        insert_text_at(&mut self.input, &mut self.input_cursor, text);
        self.input_history_index = None;
        self.refresh_slash_selection();
        self.clear_quit_hint();
    }

    fn backspace(&mut self) {
        delete_before_cursor(&mut self.input, &mut self.input_cursor);
        self.input_history_index = None;
        self.refresh_slash_selection();
        self.clear_quit_hint();
    }

    fn delete_forward(&mut self) {
        delete_at_cursor(&mut self.input, self.input_cursor);
        self.input_history_index = None;
        self.refresh_slash_selection();
        self.clear_quit_hint();
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

    fn clear_current_line(&mut self) {
        let (start, end) = current_line_bounds(&self.input, self.input_cursor);
        let byte_start = byte_index_from_char(&self.input, start);
        let byte_end = byte_index_from_char(&self.input, end);
        self.input.replace_range(byte_start..byte_end, "");
        self.input_cursor = start;
        self.input_history_index = None;
        self.refresh_slash_selection();
        self.clear_quit_hint();
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

    fn arm_quit_hint(&mut self) {
        self.quit_hint_until = Some(Instant::now() + Duration::from_secs(1));
        self.set_footer(chat_text("chat.quit_hint"), MetaTone::Warning);
    }

    fn clear_quit_hint(&mut self) {
        self.quit_hint_until = None;
        let quit_hint = chat_text("chat.quit_hint");
        if self
            .footer_message
            .as_ref()
            .is_some_and(|(text, _)| text == &quit_hint)
        {
            self.footer_message = None;
        }
    }

    fn quit_hint_active(&self) -> bool {
        self.quit_hint_until
            .is_some_and(|deadline| deadline > Instant::now())
    }

    fn tick(&mut self) {
        if self
            .quit_hint_until
            .is_some_and(|deadline| deadline <= Instant::now())
        {
            self.clear_quit_hint();
        }
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

    loop {
        app.tick();

        while let Ok(message) = ui_rx.try_recv() {
            handle_ui_event(&mut app, message);
        }

        terminal.draw(&mut app)?;

        if app.should_quit {
            break;
        }

        if event::poll(Duration::from_millis(50)).context(i18n::t("err.chat_event_read"))? {
            match event::read().context(i18n::t("err.chat_event_read"))? {
                Event::Key(key) => {
                    handle_key_event(&mut app, key, primary_client.clone(), ui_tx.clone())
                }
                Event::Paste(text) => handle_paste(&mut app, text),
                Event::Mouse(mouse) => {
                    handle_mouse_event(&mut app, mouse, primary_client.clone(), ui_tx.clone())
                }
                Event::Resize(_, _) => {}
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
                KeyCode::Char('y') | KeyCode::Enter => {
                    let session_id = app.session_id.clone();
                    let call_id = overlay.call_id.clone();
                    app.overlay = OverlayState::None;
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
                KeyCode::Char('n') | KeyCode::Esc => {
                    let session_id = app.session_id.clone();
                    let call_id = overlay.call_id.clone();
                    app.overlay = OverlayState::None;
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
                    app.overlay = OverlayState::None;
                    app.clear_quit_hint();
                    app.set_footer(chat_text("chat.footer.history_closed"), MetaTone::Dim);
                }
                KeyCode::Esc => {
                    app.overlay = OverlayState::None;
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
                        app.overlay = OverlayState::None;
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
            app.arm_quit_hint();
        }
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
                    app.set_footer(
                        chat_format(
                            "chat.footer.slash_selected",
                            &[("{command}", command.to_string())],
                        ),
                        MetaTone::Dim,
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
                        app.set_footer(
                            chat_format(
                                "chat.footer.slash_selected",
                                &[("{command}", command.to_string())],
                            ),
                            MetaTone::Dim,
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
                app.clear_input();
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
                app.should_quit = true;
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
                app.clear_current_line();
                return;
            }
            app.backspace();
        }
        KeyCode::Char('u') if key.modifiers.contains(KeyModifiers::CONTROL) => {
            app.clear_current_line();
        }
        KeyCode::Delete => {
            if key.modifiers.contains(KeyModifiers::SUPER) {
                app.clear_current_line();
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
            if submitted.is_empty() {
                return;
            }
            app.remember_input(&submitted);
            app.clear_input();

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

                let event =
                    match send_chat_message(primary_client, &session_id, submitted, ui_tx.clone())
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

fn handle_paste(app: &mut ChatApp, text: String) {
    if !matches!(app.overlay, OverlayState::None) {
        return;
    }
    app.insert_text(&text);
}

fn handle_mouse_event(
    app: &mut ChatApp,
    mouse: MouseEvent,
    primary_client: Arc<Mutex<DeckClient>>,
    ui_tx: UnboundedSender<UiEvent>,
) {
    match mouse.kind {
        MouseEventKind::Down(MouseButton::Left) => {
            if !matches!(app.overlay, OverlayState::None) {
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
            OverlayState::None => app.scroll_up(3),
            OverlayState::Approval(_) => {}
        },
        MouseEventKind::ScrollDown => match &mut app.overlay {
            OverlayState::History(overlay) => {
                if overlay.selected + 1 < overlay.items.len() {
                    overlay.selected += 1;
                }
                app.clear_quit_hint();
                maybe_request_more_history(app, primary_client, ui_tx);
            }
            OverlayState::None => app.scroll_down(3),
            OverlayState::Approval(_) => {}
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
        UiEvent::AssistantDelta(delta) => {
            app.streaming_text.push_str(&delta);
        }
        UiEvent::ToolStarted(tool) => {
            if app.tool_states.contains_key(&tool.call_id) {
                return;
            }
            app.tool_states
                .insert(tool.call_id.clone(), ToolLifecycle::Started);
            app.push_activity(describe_tool_started(&tool), MetaTone::Info);
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
            app.push_activity(describe_tool_finished(&tool), tool_finish_tone(&tool));
        }
        UiEvent::ApprovalRequested(tool) => {
            app.mode = ChatMode::AwaitingApproval;
            if app.mode_started_at.is_none() {
                app.mode_started_at = Some(Instant::now());
            }
            app.overlay = OverlayState::Approval(ApprovalOverlay {
                call_id: tool.call_id.clone(),
                tool: tool.tool.clone(),
                preview: approval_preview(&tool),
            });
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
                app.overlay = OverlayState::History(HistoryOverlay {
                    items: data.items,
                    selected: 0,
                    next_cursor: data.next_cursor,
                    has_more: data.has_more,
                    loading_more: false,
                });
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
    ui_tx: UnboundedSender<UiEvent>,
) -> Result<()> {
    let mut client = client.lock().await;
    let _ = client.chat_send(session_id, &text).await?;

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

    match &app.overlay {
        OverlayState::Approval(overlay) => render_approval_overlay(frame, area, overlay),
        OverlayState::History(overlay) => render_history_overlay(frame, area, overlay),
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
    let lines = transcript_lines(app, content_area.width as usize);
    let max_scroll = lines.len().saturating_sub(content_area.height as usize);
    if app.auto_scroll {
        app.scroll = max_scroll;
    } else if app.scroll > max_scroll {
        app.scroll = max_scroll;
    }

    if !app.auto_scroll && app.scroll >= max_scroll {
        app.auto_scroll = true;
    }

    let total_lines = lines.len();
    app.update_body_scrollbar_state(scrollbar_area, content_area.height as usize, total_lines);
    let paragraph = Paragraph::new(lines).scroll((app.scroll as u16, 0));
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
    let title = if app.slash_query().is_some() {
        chat_text("chat.input.title.prompt_slash")
    } else {
        chat_text("chat.input.title.prompt")
    };
    let block = Block::default().title(title).borders(Borders::ALL);
    frame.render_widget(block.clone(), area);
    let inner = block.inner(area);
    if inner.width == 0 || inner.height == 0 {
        app.input_text_area = None;
        return;
    }

    let sections = if inner.width > 2 {
        Layout::default()
            .direction(Direction::Horizontal)
            .constraints([Constraint::Length(2), Constraint::Min(1)])
            .split(inner)
    } else {
        Layout::default()
            .direction(Direction::Horizontal)
            .constraints([Constraint::Min(1)])
            .split(inner)
    };

    let gutter_area = sections[0];
    let text_area = if sections.len() > 1 {
        sections[1]
    } else {
        sections[0]
    };
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

    if sections.len() > 1 {
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

    let text_lines: Vec<Line<'_>> = viewport
        .visible_lines
        .iter()
        .map(|line| Line::from(Span::raw(line.clone())))
        .collect();
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
    let (text, tone) = app
        .footer_message
        .clone()
        .unwrap_or_else(|| (default_footer, MetaTone::Dim));
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

fn render_slash_popup(frame: &mut Frame<'_>, input_area: Rect, app: &ChatApp) {
    let matches = app.slash_matches();
    if matches.is_empty() {
        return;
    }

    let height = (matches.len().min(5) as u16)
        .saturating_mul(2)
        .saturating_add(2);
    let popup_width = input_area.width.min(60);
    let popup = Rect {
        x: input_area.x,
        y: input_area.y.saturating_sub(height),
        width: popup_width,
        height,
    };
    frame.render_widget(Clear, popup);

    let items: Vec<ListItem<'_>> = matches
        .iter()
        .take(5)
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
            .min(matches.len().saturating_sub(1))
            .min(4),
    ));
    let list = List::new(items)
        .block(
            Block::default()
                .title(chat_text("chat.commands.title"))
                .borders(Borders::ALL),
        )
        .highlight_style(
            Style::default()
                .bg(Color::Rgb(26, 26, 26))
                .fg(Color::Yellow),
        )
        .highlight_symbol("› ");
    frame.render_stateful_widget(list, popup, &mut state);
}

fn render_history_overlay(frame: &mut Frame<'_>, area: Rect, overlay: &HistoryOverlay) {
    let popup = centered_rect(76, 58, area);
    frame.render_widget(Clear, popup);

    let layout = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Min(6), Constraint::Length(1)])
        .split(popup);

    let line_width = layout[0].width.saturating_sub(6) as usize;
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
        .block(
            Block::default()
                .title(chat_format(
                    "chat.resume.title",
                    &[("{count}", overlay.items.len().to_string())],
                ))
                .borders(Borders::ALL),
        )
        .highlight_style(Style::default().bg(Color::Rgb(30, 30, 30)).fg(Color::Cyan))
        .highlight_symbol("› ");
    frame.render_stateful_widget(list, layout[0], &mut state);

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

fn transcript_lines(app: &ChatApp, width: usize) -> Vec<Line<'static>> {
    let mut lines = Vec::new();

    for entry in app.all_entries() {
        match entry {
            TranscriptEntry::User(text) => push_wrapped_lines(
                &mut lines,
                width,
                "> ",
                "  ",
                &text,
                Style::default()
                    .fg(Color::Green)
                    .add_modifier(Modifier::BOLD),
            ),
            TranscriptEntry::Assistant(text) => push_wrapped_lines(
                &mut lines,
                width,
                "< ",
                "  ",
                &text,
                Style::default().fg(Color::Cyan),
            ),
            TranscriptEntry::Meta { text, tone } => {
                push_wrapped_lines(&mut lines, width, "· ", "  ", &text, tone.style())
            }
        }
        lines.push(Line::from(""));
    }

    if lines.is_empty() {
        lines.push(Line::from(Span::styled(
            chat_text("chat.empty"),
            Style::default().fg(Color::DarkGray),
        )));
    }

    lines
}

fn push_wrapped_lines(
    lines: &mut Vec<Line<'static>>,
    width: usize,
    first_prefix: &str,
    next_prefix: &str,
    text: &str,
    style: Style,
) {
    let available_width = width.max(first_prefix.len() + 4);
    let options = Options::new(available_width)
        .initial_indent(first_prefix)
        .subsequent_indent(next_prefix)
        .break_words(true)
        .word_splitter(textwrap::WordSplitter::NoHyphenation);

    for line in textwrap::wrap(text, &options) {
        lines.push(Line::from(Span::styled(line.into_owned(), style)));
    }
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
    visible_lines as u16 + 2
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

fn describe_tool_started(tool: &ToolEventData) -> String {
    match tool.tool.as_str() {
        "search_clipboard" => {
            let query = tool
                .parameters
                .get("query")
                .and_then(Value::as_str)
                .unwrap_or("");
            if query.is_empty() {
                chat_text("chat.tool.searching_clipboard")
            } else {
                chat_format(
                    "chat.tool.searching_clipboard_with_query",
                    &[("{query}", query.to_string())],
                )
            }
        }
        "write_clipboard" => chat_text("chat.tool.writing_clipboard"),
        "delete_clipboard" => chat_text("chat.tool.deleting_clipboard"),
        _ => chat_format("chat.tool.running", &[("{tool}", tool.tool.clone())]),
    }
}

fn describe_tool_finished(tool: &ToolEventData) -> String {
    if tool.approved == Some(false) {
        return chat_format("chat.tool.rejected", &[("{tool}", tool.tool.clone())]);
    }

    if let Some(result) = &tool.result {
        if result
            .get("ok")
            .and_then(Value::as_bool)
            .is_some_and(|ok| !ok)
        {
            let default_error = chat_text("chat.tool.failed_default");
            let error = result
                .get("error")
                .and_then(Value::as_str)
                .unwrap_or(default_error.as_str());
            return chat_format(
                "chat.tool.failed",
                &[
                    ("{tool}", tool.tool.clone()),
                    ("{error}", error.to_string()),
                ],
            );
        }
    }

    chat_format("chat.tool.finished", &[("{tool}", tool.tool.clone())])
}

fn tool_finish_tone(tool: &ToolEventData) -> MetaTone {
    if tool.approved == Some(false) {
        return MetaTone::Warning;
    }

    if let Some(result) = &tool.result {
        if result
            .get("ok")
            .and_then(Value::as_bool)
            .is_some_and(|ok| !ok)
        {
            return MetaTone::Error;
        }
    }

    MetaTone::Success
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
}
