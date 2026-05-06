use serde::{Deserialize, Serialize};

// ─── Handshake ───

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuthRequest {
    #[serde(rename = "type")]
    pub msg_type: String, // "auth"
    pub token: String,
}

impl AuthRequest {
    pub fn new(token: String) -> Self {
        Self {
            msg_type: "auth".into(),
            token,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuthResponse {
    #[serde(rename = "type")]
    pub msg_type: String, // "auth_ok" | "auth_err"
    #[serde(default)]
    pub session_token: Option<String>,
    #[serde(default)]
    pub expires_at: Option<u64>,
    #[serde(default)]
    pub error: Option<String>,
}

impl AuthResponse {
    pub fn is_ok(&self) -> bool {
        self.msg_type == "auth_ok"
    }
}

// ─── Request / Response ───

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Request {
    pub v: u32,
    pub id: String,
    pub ts: u64,
    pub nonce: String,
    pub sig: String,
    pub cmd: String,
    #[serde(default)]
    pub args: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Response {
    pub v: u32,
    pub id: String,
    pub ok: bool,
    #[serde(default)]
    pub data: Option<serde_json::Value>,
    #[serde(default)]
    pub error: Option<ErrorInfo>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ErrorInfo {
    pub code: String,
    pub message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventFrame {
    pub v: u32,
    pub id: String,
    pub event: String,
    #[serde(default)]
    pub data: Option<serde_json::Value>,
}

/// Wire payloads streamed after [`cmd::AI_CHAT_SEND`]: terminal [`Response`] or intermediate [`EventFrame`].
#[derive(Debug, Deserialize)]
#[serde(untagged)]
pub enum ChatStreamMessage {
    Event(EventFrame),
    Response(Response),
}

// ─── Command Constants ───

pub mod cmd {
    pub const HEALTH: &str = "health";
    pub const READ: &str = "read";
    pub const CLIPBOARD_LATEST: &str = "clipboard.latest";
    pub const CLIPBOARD_LIST: &str = "clipboard.list";
    pub const CLIPBOARD_SEARCH: &str = "clipboard.search";
    pub const SCRIPT_PLUGINS_LIST: &str = "script.plugins.list";
    pub const SCRIPT_PLUGIN_READ: &str = "script.plugin.read";
    pub const SCRIPT_TRANSFORM_RUN: &str = "script.transform.run";
    pub const WRITE: &str = "write";
    pub const PANEL_TOGGLE: &str = "panel.toggle";
    pub const PASTE: &str = "paste";
    pub const AI_RUN: &str = "ai.run";
    pub const AI_SEARCH: &str = "ai.search";
    pub const AI_TRANSFORM: &str = "ai.transform";
    pub const LOGIN_STATUS: &str = "login.status";
    pub const LOGIN_CLEAR: &str = "login.clear";
    pub const LOGIN_CHATGPT_START: &str = "login.chatgpt.start";
    pub const LOGIN_CHATGPT_WAIT: &str = "login.chatgpt.wait";
    pub const LOGIN_CHATGPT_CANCEL: &str = "login.chatgpt.cancel";
    pub const LOGIN_OPENAI_CONFIGURE: &str = "login.openai.configure";
    pub const LOGIN_ANTHROPIC_CONFIGURE: &str = "login.anthropic.configure";
    pub const LOGIN_OLLAMA_CONFIGURE: &str = "login.ollama.configure";
    pub const AI_CHAT_BOOTSTRAP: &str = "ai.chat.bootstrap";
    pub const AI_CHAT_OPEN: &str = "ai.chat.open";
    pub const AI_CHAT_CLIPBOARD_READ: &str = "ai.chat.clipboard.read";
    pub const AI_CHAT_SEND: &str = "ai.chat.send";
    pub const AI_CHAT_APPROVAL_RESPOND: &str = "ai.chat.approval.respond";
    pub const AI_CHAT_CANCEL: &str = "ai.chat.cancel";
    pub const AI_CHAT_HISTORY_LIST: &str = "ai.chat.history.list";
    pub const AI_CHAT_HISTORY_LOAD: &str = "ai.chat.history.load";
    pub const AI_CHAT_COMPACT: &str = "ai.chat.compact";
    pub const AI_CHAT_CLOSE: &str = "ai.chat.close";
}

pub mod event {
    pub const ASSISTANT_DELTA: &str = "assistant.delta";
    pub const TOOL_STARTED: &str = "tool.started";
    pub const TOOL_FINISHED: &str = "tool.finished";
    pub const APPROVAL_REQUEST: &str = "approval.request";
    pub const CONVERSATION_UPDATED: &str = "conversation.updated";
    pub const COMPACTING: &str = "compacting";
    pub const CANCELLED: &str = "cancelled";
    pub const DONE: &str = "done";
    pub const ERROR: &str = "error";
}
