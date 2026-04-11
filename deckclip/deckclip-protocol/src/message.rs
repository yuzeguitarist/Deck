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

// ─── Command Constants ───

pub mod cmd {
    pub const HEALTH: &str = "health";
    pub const READ: &str = "read";
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
}
