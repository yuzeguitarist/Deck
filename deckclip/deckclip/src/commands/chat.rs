use std::collections::HashMap;
use std::io::{self, IsTerminal, Stdout};
use std::process::{Command, Stdio};
use std::sync::Arc;
use std::time::Duration;

use anyhow::{anyhow, bail, Context, Result};
use crossterm::event::{self, Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers};
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

use crate::commands::login;
use crate::output::OutputMode;

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
    message_count: usize,
    last_snippet: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct HistoryListData {
    items: Vec<HistoryItemData>,
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
    ConversationUpdated(SessionData),
    AssistantDelta(String),
    ToolStarted(ToolEventData),
    ToolFinished(ToolEventData),
    ApprovalRequested(ToolEventData),
    Compacting(CompactingEventData),
    Done(DoneEventData),
    HistoryLoaded(HistoryListData),
    FooterMessage(String, MetaTone),
    Error(String),
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
    overlay: OverlayState,
    mode: ChatMode,
    footer_message: Option<(String, MetaTone)>,
    busy_action: Option<String>,
    streaming_text: String,
    last_assistant_text: Option<String>,
    tool_states: HashMap<String, ToolLifecycle>,
    auto_scroll: bool,
    scroll: usize,
    should_quit: bool,
}

impl ChatApp {
    fn from_bootstrap(session: SessionData, account: Option<String>) -> Self {
        let mut app = Self {
            session_id: session.session_id.clone(),
            conversation_id: session.conversation.id.clone(),
            conversation_title: session.conversation.title.clone(),
            provider: session.conversation.provider.clone(),
            model: session.conversation.model.clone(),
            account,
            context_usage: session.context_usage.clone(),
            conversation_entries: Vec::new(),
            activities: Vec::new(),
            input: String::new(),
            overlay: OverlayState::None,
            mode: ChatMode::Ready,
            footer_message: Some((
                "Deck AI 已就绪，输入内容直接发送，输入 /help 查看命令。".to_string(),
                MetaTone::Dim,
            )),
            busy_action: None,
            streaming_text: String::new(),
            last_assistant_text: session.last_assistant_text.clone(),
            tool_states: HashMap::new(),
            auto_scroll: true,
            scroll: 0,
            should_quit: false,
        };
        app.replace_session(session, true);
        app
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
            self.busy_action = None;
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
        self.auto_scroll = true;
    }

    fn set_footer(&mut self, text: impl Into<String>, tone: MetaTone) {
        self.footer_message = Some((text.into(), tone));
    }

    fn begin_send(&mut self) {
        self.mode = ChatMode::Streaming;
        self.streaming_text.clear();
        self.activities.clear();
        self.tool_states.clear();
        self.overlay = OverlayState::None;
        self.auto_scroll = true;
        self.set_footer("Deck AI 正在生成回复…", MetaTone::Info);
    }

    fn finish_send(&mut self) {
        self.mode = ChatMode::Ready;
        self.streaming_text.clear();
        self.overlay = OverlayState::None;
        self.busy_action = None;
    }

    fn status_text(&self) -> String {
        if let Some(action) = &self.busy_action {
            return action.clone();
        }
        match self.mode {
            ChatMode::Ready => "Ready".to_string(),
            ChatMode::Streaming => "Streaming".to_string(),
            ChatMode::AwaitingApproval => "Awaiting approval".to_string(),
        }
    }

    fn all_entries(&self) -> Vec<TranscriptEntry> {
        let mut entries = self.conversation_entries.clone();
        entries.extend(self.activities.clone());
        if !self.streaming_text.is_empty() {
            entries.push(TranscriptEntry::Assistant(self.streaming_text.clone()));
        } else if self.mode == ChatMode::Streaming {
            entries.push(TranscriptEntry::Meta {
                text: "Deck AI 正在思考…".to_string(),
                tone: MetaTone::Dim,
            });
        }
        entries
    }
}

struct TerminalGuard {
    terminal: Terminal<CrosstermBackend<Stdout>>,
}

impl TerminalGuard {
    fn enter() -> Result<Self> {
        enable_raw_mode().context("无法进入终端 raw mode")?;
        let mut stdout = io::stdout();
        execute!(stdout, EnterAlternateScreen).context("无法进入终端全屏模式")?;
        let backend = CrosstermBackend::new(stdout);
        let terminal = Terminal::new(backend).context("无法初始化终端 UI")?;
        Ok(Self { terminal })
    }

    fn draw(&mut self, app: &mut ChatApp) -> Result<()> {
        self.terminal.draw(|frame| render(frame, app))?;
        Ok(())
    }
}

impl Drop for TerminalGuard {
    fn drop(&mut self) {
        let _ = disable_raw_mode();
        let _ = execute!(self.terminal.backend_mut(), LeaveAlternateScreen);
        let _ = self.terminal.show_cursor();
    }
}

pub async fn run(output: OutputMode) -> Result<()> {
    if matches!(output, OutputMode::Json) {
        bail!("deckclip chat 暂不支持 --json")
    }

    if !io::stdin().is_terminal() || !io::stdout().is_terminal() {
        bail!("deckclip chat 需要交互式终端")
    }

    let primary_client = Arc::new(Mutex::new(DeckClient::new(Config::default())));
    let bootstrap = ensure_bootstrapped(primary_client.clone()).await?;
    let session = open_chat_session(primary_client.clone(), None, true).await?;
    let mut app = ChatApp::from_bootstrap(session, bootstrap.account);
    let (ui_tx, mut ui_rx) = unbounded_channel();
    let mut terminal = TerminalGuard::enter()?;

    loop {
        while let Ok(message) = ui_rx.try_recv() {
            handle_ui_event(&mut app, message);
        }

        terminal.draw(&mut app)?;

        if app.should_quit {
            break;
        }

        if event::poll(Duration::from_millis(50)).context("读取终端事件失败")? {
            match event::read().context("读取终端事件失败")? {
                Event::Key(key) => {
                    handle_key_event(&mut app, key, primary_client.clone(), ui_tx.clone())
                }
                Event::Paste(text) => handle_paste(&mut app, text),
                Event::Resize(_, _) => {}
                _ => {}
            }
        }
    }

    let _ = close_chat_session(primary_client.clone(), &app.session_id).await;
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

    if key.code == KeyCode::Char('c') && key.modifiers.contains(KeyModifiers::CONTROL) {
        app.should_quit = true;
        return;
    }

    match &mut app.overlay {
        OverlayState::Approval(overlay) => {
            match key.code {
                KeyCode::Char('y') | KeyCode::Enter => {
                    let session_id = app.session_id.clone();
                    let call_id = overlay.call_id.clone();
                    app.overlay = OverlayState::None;
                    app.mode = ChatMode::Streaming;
                    app.set_footer("已批准工具调用，继续执行…", MetaTone::Info);
                    tokio::spawn(async move {
                        let event = match respond_to_approval(&session_id, &call_id, true).await {
                            Ok(()) => UiEvent::FooterMessage(
                                "已批准工具调用。".to_string(),
                                MetaTone::Info,
                            ),
                            Err(error) => UiEvent::Error(error.to_string()),
                        };
                        let _ = ui_tx.send(event);
                    });
                }
                KeyCode::Char('n') | KeyCode::Esc => {
                    let session_id = app.session_id.clone();
                    let call_id = overlay.call_id.clone();
                    app.overlay = OverlayState::None;
                    app.mode = ChatMode::Streaming;
                    app.set_footer("已拒绝工具调用。", MetaTone::Warning);
                    tokio::spawn(async move {
                        let event = match respond_to_approval(&session_id, &call_id, false).await {
                            Ok(()) => UiEvent::FooterMessage(
                                "已拒绝工具调用。".to_string(),
                                MetaTone::Warning,
                            ),
                            Err(error) => UiEvent::Error(error.to_string()),
                        };
                        let _ = ui_tx.send(event);
                    });
                }
                _ => {}
            }
            return;
        }
        OverlayState::History(overlay) => {
            match key.code {
                KeyCode::Esc => {
                    app.overlay = OverlayState::None;
                    app.set_footer("已关闭历史列表。", MetaTone::Dim);
                }
                KeyCode::Up | KeyCode::Char('k') => {
                    if overlay.selected > 0 {
                        overlay.selected -= 1;
                    }
                }
                KeyCode::Down | KeyCode::Char('j') => {
                    if overlay.selected + 1 < overlay.items.len() {
                        overlay.selected += 1;
                    }
                }
                KeyCode::Enter => {
                    if let Some(item) = overlay.items.get(overlay.selected).cloned() {
                        app.overlay = OverlayState::None;
                        app.busy_action = Some("正在恢复会话历史…".to_string());
                        let session_id = app.session_id.clone();
                        tokio::spawn(async move {
                            let event =
                                match load_history(primary_client, &session_id, &item.id).await {
                                    Ok(session) => UiEvent::SessionOpened(session),
                                    Err(error) => UiEvent::Error(error.to_string()),
                                };
                            let _ = ui_tx.send(event);
                        });
                    }
                }
                _ => {}
            }
            return;
        }
        OverlayState::None => {}
    }

    match key.code {
        KeyCode::Esc => {
            if app.mode == ChatMode::Streaming {
                let session_id = app.session_id.clone();
                app.set_footer("正在停止当前回复…", MetaTone::Warning);
                tokio::spawn(async move {
                    let event = match cancel_stream(&session_id).await {
                        Ok(()) => UiEvent::FooterMessage(
                            "已发送停止请求。".to_string(),
                            MetaTone::Warning,
                        ),
                        Err(error) => UiEvent::Error(error.to_string()),
                    };
                    let _ = ui_tx.send(event);
                });
            } else {
                app.should_quit = true;
            }
        }
        KeyCode::PageUp => {
            app.auto_scroll = false;
            app.scroll = app.scroll.saturating_sub(8);
        }
        KeyCode::PageDown => {
            app.scroll = app.scroll.saturating_add(8);
        }
        KeyCode::End => {
            app.auto_scroll = true;
        }
        KeyCode::Backspace => {
            app.input.pop();
        }
        KeyCode::Enter => {
            if app.busy_action.is_some() {
                app.set_footer("当前仍有后台操作，请稍候。", MetaTone::Warning);
                return;
            }

            let submitted = app.input.trim().to_string();
            if submitted.is_empty() {
                return;
            }
            app.input.clear();

            if submitted.starts_with('/') {
                handle_slash_command(app, submitted, primary_client, ui_tx);
                return;
            }

            if app.mode != ChatMode::Ready {
                app.set_footer(
                    "当前回复尚未完成，请先等待或按 ESC 停止。",
                    MetaTone::Warning,
                );
                return;
            }

            let session_id = app.session_id.clone();
            app.begin_send();
            tokio::spawn(async move {
                let event =
                    match send_chat_message(primary_client, &session_id, submitted, ui_tx.clone())
                        .await
                    {
                        Ok(()) => return,
                        Err(error) => UiEvent::Error(error.to_string()),
                    };
                let _ = ui_tx.send(event);
            });
        }
        KeyCode::Char(ch)
            if !key.modifiers.contains(KeyModifiers::CONTROL)
                && !key.modifiers.contains(KeyModifiers::ALT)
                && !key.modifiers.contains(KeyModifiers::SUPER) =>
        {
            app.input.push(ch);
        }
        _ => {}
    }
}

fn handle_paste(app: &mut ChatApp, text: String) {
    if !matches!(app.overlay, OverlayState::None) {
        return;
    }
    app.input.push_str(&text);
}

fn handle_slash_command(
    app: &mut ChatApp,
    input: String,
    primary_client: Arc<Mutex<DeckClient>>,
    ui_tx: UnboundedSender<UiEvent>,
) {
    let command = input.trim();

    match command {
        "/help" => {
            app.push_activity("/cost 查看上下文占用  /compact 手动压缩  /copy 复制最后一条回复  /resume 恢复历史会话  /clear 新建会话", MetaTone::Dim);
            app.set_footer("可用命令已显示在消息区。", MetaTone::Dim);
        }
        "/cost" => {
            if let Some(usage) = &app.context_usage {
                app.set_footer(
                    format!(
                        "上下文占用 {}  ({} / {})",
                        usage.usage_percent_text, usage.estimated_tokens, usage.context_window_size
                    ),
                    MetaTone::Info,
                );
            } else {
                app.set_footer("当前还没有上下文占用数据。", MetaTone::Dim);
            }
        }
        "/copy" => match app.last_assistant_text.clone() {
            Some(text) if !text.trim().is_empty() => match copy_to_system_clipboard(&text) {
                Ok(()) => app.set_footer("已复制最后一条回复到系统剪贴板。", MetaTone::Success),
                Err(error) => app.set_footer(error.to_string(), MetaTone::Error),
            },
            _ => app.set_footer("当前还没有可复制的 AI 回复。", MetaTone::Warning),
        },
        "/clear" => {
            if app.mode != ChatMode::Ready {
                app.set_footer("当前回复尚未完成，无法新建会话。", MetaTone::Warning);
                return;
            }

            app.busy_action = Some("正在新建会话…".to_string());
            let session_id = app.session_id.clone();
            tokio::spawn(async move {
                let event = match open_chat_session(primary_client, Some(&session_id), true).await {
                    Ok(session) => UiEvent::SessionOpened(session),
                    Err(error) => UiEvent::Error(error.to_string()),
                };
                let _ = ui_tx.send(event);
            });
        }
        "/resume" => {
            if app.mode != ChatMode::Ready {
                app.set_footer("当前回复尚未完成，无法恢复历史会话。", MetaTone::Warning);
                return;
            }

            app.busy_action = Some("正在读取会话历史…".to_string());
            tokio::spawn(async move {
                let event = match list_history(primary_client).await {
                    Ok(history) => UiEvent::HistoryLoaded(history),
                    Err(error) => UiEvent::Error(error.to_string()),
                };
                let _ = ui_tx.send(event);
            });
        }
        "/compact" => {
            if app.mode != ChatMode::Ready {
                app.set_footer("当前回复尚未完成，无法压缩上下文。", MetaTone::Warning);
                return;
            }

            app.busy_action = Some("正在压缩上下文…".to_string());
            let session_id = app.session_id.clone();
            tokio::spawn(async move {
                let event = match compact_session(primary_client, &session_id).await {
                    Ok(session) => UiEvent::SessionOpened(session),
                    Err(error) => UiEvent::Error(error.to_string()),
                };
                let _ = ui_tx.send(event);
            });
        }
        _ => {
            app.set_footer("未知命令。输入 /help 查看可用命令。", MetaTone::Warning);
        }
    }
}

fn handle_ui_event(app: &mut ChatApp, event: UiEvent) {
    match event {
        UiEvent::SessionOpened(session) => {
            app.replace_session(session, true);
            app.set_footer("会话已就绪。", MetaTone::Success);
        }
        UiEvent::ConversationUpdated(session) => {
            app.conversation_updated(session);
        }
        UiEvent::AssistantDelta(delta) => {
            app.streaming_text.push_str(&delta);
            app.auto_scroll = true;
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
            app.overlay = OverlayState::Approval(ApprovalOverlay {
                call_id: tool.call_id.clone(),
                tool: tool.tool.clone(),
                preview: approval_preview(&tool),
            });
            app.set_footer("需要审批。按 Y 同意，按 N 拒绝。", MetaTone::Warning);
        }
        UiEvent::Compacting(data) => {
            if data.completed == Some(true) {
                let suffix = data
                    .compressed_count
                    .map(|count| format!("，压缩了 {} 段历史", count))
                    .unwrap_or_default();
                app.set_footer(format!("上下文压缩完成{}。", suffix), MetaTone::Success);
            } else if data.attempt > 0 {
                app.set_footer(
                    format!("正在自动压缩上下文（第 {} 次）…", data.attempt),
                    MetaTone::Info,
                );
            }
        }
        UiEvent::Done(done) => {
            app.last_assistant_text = Some(done.text);
            app.finish_send();
            app.set_footer("本轮回复完成。", MetaTone::Success);
        }
        UiEvent::HistoryLoaded(history) => {
            app.busy_action = None;
            if history.items.is_empty() {
                app.set_footer("当前还没有可恢复的历史会话。", MetaTone::Dim);
            } else {
                app.overlay = OverlayState::History(HistoryOverlay {
                    items: history.items,
                    selected: 0,
                });
                app.set_footer("选择要恢复的历史会话。", MetaTone::Info);
            }
        }
        UiEvent::FooterMessage(message, tone) => {
            app.busy_action = None;
            app.set_footer(message, tone);
        }
        UiEvent::Error(message) => {
            app.busy_action = None;
            app.finish_send();
            app.push_activity(message.clone(), MetaTone::Error);
            app.set_footer(message, MetaTone::Error);
        }
    }
}

async fn ensure_bootstrapped(client: Arc<Mutex<DeckClient>>) -> Result<BootstrapData> {
    let bootstrap = fetch_bootstrap(client.clone()).await?;
    if bootstrap.busy == Some(true) {
        bail!("Deck AI 当前正被另一个活动会话占用，请先关闭它")
    }
    if bootstrap.configured {
        return Ok(bootstrap);
    }

    login::run(OutputMode::Text).await?;

    let bootstrap = fetch_bootstrap(client).await?;
    if !bootstrap.configured {
        bail!("当前 AI Provider 尚未配置，无法进入 deckclip chat")
    }
    if bootstrap.busy == Some(true) {
        bail!("Deck AI 当前正被另一个活动会话占用，请先关闭它")
    }
    Ok(bootstrap)
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
    create_new: bool,
) -> Result<SessionData> {
    let response = {
        let mut client = client.lock().await;
        client.chat_open(session_id, None, create_new).await?
    };
    response_data(response)
}

async fn list_history(client: Arc<Mutex<DeckClient>>) -> Result<HistoryListData> {
    let response = {
        let mut client = client.lock().await;
        client.chat_history_list(None, Some(12)).await?
    };
    response_data(response)
}

async fn load_history(
    client: Arc<Mutex<DeckClient>>,
    session_id: &str,
    conversation_id: &str,
) -> Result<SessionData> {
    let response = {
        let mut client = client.lock().await;
        client
            .chat_history_load(session_id, conversation_id)
            .await?
    };
    response_data(response)
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
                    return Err(anyhow!("聊天流返回了意外响应"));
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
                .unwrap_or("聊天流发生未知错误")
                .to_string();
            Ok(UiEvent::Error(message))
        }
        other => Ok(UiEvent::FooterMessage(
            format!("收到未识别事件: {}", other),
            MetaTone::Warning,
        )),
    }
}

fn response_data<T: DeserializeOwned>(response: deckclip_protocol::Response) -> Result<T> {
    let data = response.data.ok_or_else(|| anyhow!("响应缺少 data 字段"))?;
    serde_json::from_value(data).map_err(Into::into)
}

fn render(frame: &mut Frame<'_>, app: &mut ChatApp) {
    let area = frame.area();
    let layout = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(2),
            Constraint::Min(8),
            Constraint::Length(3),
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
        OverlayState::None => {}
    }
}

fn render_header(frame: &mut Frame<'_>, area: Rect, app: &ChatApp) {
    let title = format!(" deckclip chat  {}  {} ", app.provider, app.model);
    let right = format!(" {} ", app.status_text());
    let account = app
        .account
        .clone()
        .unwrap_or_else(|| "未显示账号".to_string());
    let usage = app
        .context_usage
        .as_ref()
        .map(|value| format!("上下文 {}", value.usage_percent_text))
        .unwrap_or_else(|| "上下文 --".to_string());

    let lines = vec![
        Line::from(vec![
            Span::styled(
                title,
                Style::default()
                    .fg(Color::Cyan)
                    .add_modifier(Modifier::BOLD),
            ),
            Span::raw("  "),
            Span::styled(
                app.conversation_title.clone(),
                Style::default().add_modifier(Modifier::BOLD),
            ),
            Span::raw("  "),
            Span::styled(right, Style::default().fg(Color::Yellow)),
        ]),
        Line::from(vec![
            Span::styled(account, Style::default().fg(Color::DarkGray)),
            Span::raw("  |  "),
            Span::styled(usage, Style::default().fg(Color::DarkGray)),
        ]),
    ];

    frame.render_widget(Paragraph::new(lines), area);
}

fn render_body(frame: &mut Frame<'_>, area: Rect, app: &mut ChatApp) {
    let block = Block::default()
        .title(" Conversation ")
        .borders(Borders::ALL);
    let inner = block.inner(area);
    let lines = transcript_lines(app, inner.width.saturating_sub(1) as usize);
    let max_scroll = lines.len().saturating_sub(inner.height as usize);
    if app.auto_scroll {
        app.scroll = max_scroll;
    } else if app.scroll > max_scroll {
        app.scroll = max_scroll;
    }

    let paragraph = Paragraph::new(lines)
        .block(block)
        .scroll((app.scroll as u16, 0));
    frame.render_widget(paragraph, area);
}

fn render_input(frame: &mut Frame<'_>, area: Rect, app: &ChatApp) {
    let block = Block::default().title(" Prompt ").borders(Borders::ALL);
    let inner = block.inner(area);
    let (visible_input, cursor_offset) =
        visible_input(&app.input, inner.width.saturating_sub(1) as usize);

    let paragraph = Paragraph::new(Line::from(vec![
        Span::styled(
            "> ",
            Style::default()
                .fg(Color::Green)
                .add_modifier(Modifier::BOLD),
        ),
        Span::raw(visible_input),
    ]))
    .block(block);
    frame.render_widget(paragraph, area);

    if matches!(app.overlay, OverlayState::None) {
        frame.set_cursor_position((inner.x + 2 + cursor_offset as u16, inner.y));
    }
}

fn render_footer(frame: &mut Frame<'_>, area: Rect, app: &ChatApp) {
    let default_footer = "Enter 发送  Esc 退出/停止  PageUp/PageDown 滚动  /help 命令";
    let (text, tone) = app
        .footer_message
        .clone()
        .unwrap_or_else(|| (default_footer.to_string(), MetaTone::Dim));
    let line = Line::from(Span::styled(text, tone.style()));
    frame.render_widget(Paragraph::new(line), area);
}

fn render_approval_overlay(frame: &mut Frame<'_>, area: Rect, overlay: &ApprovalOverlay) {
    let popup = centered_rect(72, 42, area);
    frame.render_widget(Clear, popup);

    let text = vec![
        Line::from(Span::styled(
            format!("需要审批: {}", overlay.tool),
            Style::default()
                .fg(Color::Yellow)
                .add_modifier(Modifier::BOLD),
        )),
        Line::from(Span::raw("")),
        Line::from(Span::raw(overlay.preview.clone())),
        Line::from(Span::raw("")),
        Line::from(Span::styled(
            "按 Y 同意，按 N 拒绝",
            Style::default().fg(Color::DarkGray),
        )),
    ];

    frame.render_widget(
        Paragraph::new(text).block(Block::default().title(" Approval ").borders(Borders::ALL)),
        popup,
    );
}

fn render_history_overlay(frame: &mut Frame<'_>, area: Rect, overlay: &HistoryOverlay) {
    let popup = centered_rect(76, 58, area);
    frame.render_widget(Clear, popup);

    let items: Vec<ListItem<'_>> = overlay
        .items
        .iter()
        .map(|item| {
            let title = format!("{}  {}", item.title, item.provider);
            let detail = if item.last_snippet.trim().is_empty() {
                format!("{} 条消息", item.message_count)
            } else {
                format!("{} 条消息  |  {}", item.message_count, item.last_snippet)
            };
            ListItem::new(vec![
                Line::from(Span::styled(
                    title,
                    Style::default().add_modifier(Modifier::BOLD),
                )),
                Line::from(Span::styled(detail, Style::default().fg(Color::DarkGray))),
            ])
        })
        .collect();

    let mut state = ListState::default();
    state.select(Some(overlay.selected));
    let list = List::new(items)
        .block(Block::default().title(" Resume ").borders(Borders::ALL))
        .highlight_style(Style::default().bg(Color::Rgb(30, 30, 30)).fg(Color::Cyan))
        .highlight_symbol("> ");
    frame.render_stateful_widget(list, popup, &mut state);
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
            "还没有消息，直接输入内容开始对话。",
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

fn visible_input(input: &str, width: usize) -> (String, usize) {
    if width == 0 {
        return (String::new(), 0);
    }

    let chars: Vec<char> = input.chars().collect();
    if chars.len() <= width {
        return (input.to_string(), chars.len());
    }

    let start = chars.len().saturating_sub(width);
    let visible: String = chars[start..].iter().collect();
    (visible, width)
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
                "正在搜索剪贴板…".to_string()
            } else {
                format!("正在搜索剪贴板: {}", query)
            }
        }
        "write_clipboard" => "正在写入 Deck 剪贴板…".to_string(),
        "delete_clipboard" => "正在删除剪贴板项…".to_string(),
        _ => format!("正在执行工具: {}", tool.tool),
    }
}

fn describe_tool_finished(tool: &ToolEventData) -> String {
    if tool.approved == Some(false) {
        return format!("已拒绝工具调用: {}", tool.tool);
    }

    if let Some(result) = &tool.result {
        if result
            .get("ok")
            .and_then(Value::as_bool)
            .is_some_and(|ok| !ok)
        {
            let error = result
                .get("error")
                .and_then(Value::as_str)
                .unwrap_or("工具执行失败");
            return format!("工具 {} 执行失败: {}", tool.tool, error);
        }
    }

    format!("工具执行完成: {}", tool.tool)
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
            .map(|text| format!("将写入以下文本:\n\n{}", trim_preview(text, 600)))
            .unwrap_or_else(|| "将写入新的文本内容。".to_string()),
        "delete_clipboard" => tool
            .parameters
            .get("item_id")
            .and_then(Value::as_i64)
            .map(|id| format!("将删除 item_id = {} 的剪贴板记录。", id))
            .unwrap_or_else(|| "将删除一条剪贴板记录。".to_string()),
        _ => match serde_json::to_string_pretty(&tool.parameters) {
            Ok(json) => trim_preview(&json, 800),
            Err(_) => "该工具请求需要你的确认。".to_string(),
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
        .context("无法调用 pbcopy")?;

    if let Some(stdin) = child.stdin.as_mut() {
        use std::io::Write;
        stdin
            .write_all(text.as_bytes())
            .context("写入 pbcopy 失败")?;
    }

    let status = child.wait().context("等待 pbcopy 结束失败")?;
    if !status.success() {
        bail!("pbcopy 执行失败")
    }
    Ok(())
}
