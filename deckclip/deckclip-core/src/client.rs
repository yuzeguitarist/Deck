use std::time::Duration;

use deckclip_protocol::message::{AuthRequest, AuthResponse, EventFrame, Request, Response};
use deckclip_protocol::version::PROTOCOL_VERSION;
use serde_json::{json, Value};
use tokio::time::timeout;
use tracing::debug;
use uuid::Uuid;

use crate::auth::{self, current_timestamp, generate_nonce, sign_request};
use crate::config::Config;
use crate::error::DeckError;
use crate::transport::Transport;

/// High-level client for communicating with the Deck App.
pub struct DeckClient {
    config: Config,
    transport: Option<Transport>,
    session_token: Option<String>,
    session_expires_at: u64,
}

pub enum ChatStreamFrame {
    Event(EventFrame),
    Response(Response),
}

impl DeckClient {
    pub fn new(config: Config) -> Self {
        Self {
            config,
            transport: None,
            session_token: None,
            session_expires_at: 0,
        }
    }

    /// Ensure we have an authenticated connection.
    async fn ensure_connected(&mut self) -> Result<(), DeckError> {
        let now = current_timestamp();

        // Reuse the current socket whenever possible so deckclip chat sessions
        // stay attached to a single long-lived UDS connection.
        if self.transport.is_some() && self.session_token.is_some() && now < self.session_expires_at
        {
            return Ok(());
        }

        if self.transport.is_some() {
            let token = auth::read_token(&self.config.token_path).await?;
            if self.handshake(&token).await.is_ok() {
                return Ok(());
            }

            self.transport = None;
            self.session_token = None;
            self.session_expires_at = 0;
        }

        // (Re)connect
        debug!("connecting to Deck App...");
        let transport = Transport::connect(&self.config.socket_path).await?;
        self.transport = Some(transport);

        // Read token and perform handshake
        let token = auth::read_token(&self.config.token_path).await?;
        self.handshake(&token).await?;

        Ok(())
    }

    /// Perform the authentication handshake.
    async fn handshake(&mut self, token: &str) -> Result<(), DeckError> {
        let transport = self.transport.as_mut().ok_or(DeckError::NotRunning)?;

        let auth_req = AuthRequest::new(token.to_string());
        transport.send(&auth_req).await?;

        let auth_resp: AuthResponse = transport.recv().await?;
        if !auth_resp.is_ok() {
            return Err(DeckError::Auth(
                auth_resp.error.unwrap_or_else(|| "认证被拒绝".into()),
            ));
        }

        self.session_token = auth_resp.session_token;
        self.session_expires_at = auth_resp.expires_at.unwrap_or(0);
        debug!(
            "authenticated, session expires at {}",
            self.session_expires_at
        );

        Ok(())
    }

    /// Send a command and wait for the response.
    /// `timeout_ms` overrides the default timeout. Use `0` for no timeout.
    async fn execute(
        &mut self,
        cmd: &str,
        args: Value,
        timeout_ms: u64,
    ) -> Result<Response, DeckError> {
        self.ensure_connected().await?;

        let session_key = self
            .session_token
            .as_deref()
            .ok_or_else(|| DeckError::Auth("无 session token".into()))?;

        let id = Uuid::new_v4().to_string();
        let ts = current_timestamp();
        let nonce = generate_nonce();
        let sig = sign_request(session_key, ts, &nonce, cmd);

        let request = Request {
            v: PROTOCOL_VERSION,
            id: id.clone(),
            ts,
            nonce,
            sig,
            cmd: cmd.to_string(),
            args,
        };

        let transport = self.transport.as_mut().ok_or(DeckError::NotRunning)?;
        transport.send(&request).await?;

        let effective_timeout = if timeout_ms > 0 {
            timeout_ms
        } else {
            self.config.timeout_ms
        };

        let response: Response = if effective_timeout > 0 {
            let duration = Duration::from_millis(effective_timeout);
            timeout(duration, transport.recv())
                .await
                .map_err(|_| DeckError::Timeout)??
        } else {
            // No timeout — wait indefinitely (for AI/long operations)
            transport.recv().await?
        };

        if response.id != id {
            return Err(DeckError::Protocol(format!(
                "响应 ID 不匹配: expected {}, got {}",
                id, response.id
            )));
        }

        if !response.ok {
            if let Some(err) = &response.error {
                return Err(DeckError::Server {
                    code: err.code.clone(),
                    message: err.message.clone(),
                });
            }
        }

        Ok(response)
    }

    // ─── Public API ───

    pub async fn health(&mut self) -> Result<Response, DeckError> {
        self.execute(deckclip_protocol::cmd::HEALTH, json!({}), 0)
            .await
    }

    pub async fn read(&mut self) -> Result<Response, DeckError> {
        self.execute(deckclip_protocol::cmd::READ, json!({}), 0)
            .await
    }

    pub async fn write(
        &mut self,
        text: &str,
        tag: Option<&str>,
        tag_id: Option<&str>,
        raw: bool,
    ) -> Result<Response, DeckError> {
        let mut args = json!({ "text": text });
        if let Some(t) = tag {
            args["tag"] = json!(t);
        }
        if let Some(id) = tag_id {
            args["tagId"] = json!(id);
        }
        if raw {
            args["raw"] = json!(true);
        }
        self.execute(deckclip_protocol::cmd::WRITE, args, 0).await
    }

    pub async fn paste(
        &mut self,
        index: u32,
        plain: bool,
        target: Option<&str>,
    ) -> Result<Response, DeckError> {
        let mut args = json!({ "index": index });
        if plain {
            args["plain"] = json!(true);
        }
        if let Some(t) = target {
            args["target"] = json!(t);
        }
        self.execute(deckclip_protocol::cmd::PASTE, args, 0).await
    }

    pub async fn panel_toggle(&mut self) -> Result<Response, DeckError> {
        self.execute(deckclip_protocol::cmd::PANEL_TOGGLE, json!({}), 0)
            .await
    }

    pub async fn ai_run(
        &mut self,
        prompt: &str,
        text: Option<&str>,
        save: bool,
        tag_id: Option<&str>,
    ) -> Result<Response, DeckError> {
        let mut args = json!({ "prompt": prompt });
        if let Some(t) = text {
            args["text"] = json!(t);
        }
        if save {
            args["save"] = json!(true);
        }
        if let Some(id) = tag_id {
            args["tagId"] = json!(id);
        }
        // AI commands: no client-side timeout (cloud computation can be slow)
        self.execute(deckclip_protocol::cmd::AI_RUN, args, 0).await
    }

    pub async fn ai_search(
        &mut self,
        query: &str,
        mode: Option<&str>,
        limit: Option<u32>,
    ) -> Result<Response, DeckError> {
        let mut args = json!({ "query": query });
        if let Some(m) = mode {
            args["mode"] = json!(m);
        }
        if let Some(l) = limit {
            args["limit"] = json!(l);
        }
        self.execute(deckclip_protocol::cmd::AI_SEARCH, args, 0)
            .await
    }

    pub async fn ai_transform(
        &mut self,
        prompt: &str,
        text: Option<&str>,
        plugin: Option<&str>,
    ) -> Result<Response, DeckError> {
        let mut args = json!({ "prompt": prompt });
        if let Some(t) = text {
            args["text"] = json!(t);
        }
        if let Some(p) = plugin {
            args["plugin"] = json!(p);
        }
        self.execute(deckclip_protocol::cmd::AI_TRANSFORM, args, 0)
            .await
    }

    pub async fn login_status(&mut self) -> Result<Response, DeckError> {
        self.execute(deckclip_protocol::cmd::LOGIN_STATUS, json!({}), 0)
            .await
    }

    pub async fn login_clear(&mut self, provider: &str) -> Result<Response, DeckError> {
        self.execute(
            deckclip_protocol::cmd::LOGIN_CLEAR,
            json!({ "provider": provider }),
            0,
        )
        .await
    }

    pub async fn login_chatgpt_start(&mut self) -> Result<Response, DeckError> {
        self.execute(deckclip_protocol::cmd::LOGIN_CHATGPT_START, json!({}), 0)
            .await
    }

    pub async fn login_chatgpt_wait(&mut self) -> Result<Response, DeckError> {
        self.execute(deckclip_protocol::cmd::LOGIN_CHATGPT_WAIT, json!({}), 0)
            .await
    }

    pub async fn login_chatgpt_cancel(&mut self) -> Result<Response, DeckError> {
        self.execute(deckclip_protocol::cmd::LOGIN_CHATGPT_CANCEL, json!({}), 0)
            .await
    }

    pub async fn login_openai_configure(
        &mut self,
        base_url: &str,
        model: &str,
        api_key: &str,
    ) -> Result<Response, DeckError> {
        self.execute(
            deckclip_protocol::cmd::LOGIN_OPENAI_CONFIGURE,
            json!({
                "base_url": base_url,
                "model": model,
                "api_key": api_key,
            }),
            0,
        )
        .await
    }

    pub async fn login_anthropic_configure(
        &mut self,
        base_url: &str,
        model: &str,
        api_key: &str,
    ) -> Result<Response, DeckError> {
        self.execute(
            deckclip_protocol::cmd::LOGIN_ANTHROPIC_CONFIGURE,
            json!({
                "base_url": base_url,
                "model": model,
                "api_key": api_key,
            }),
            0,
        )
        .await
    }

    pub async fn login_ollama_configure(
        &mut self,
        base_url: &str,
        model: &str,
    ) -> Result<Response, DeckError> {
        self.execute(
            deckclip_protocol::cmd::LOGIN_OLLAMA_CONFIGURE,
            json!({
                "base_url": base_url,
                "model": model,
            }),
            0,
        )
        .await
    }

    pub async fn chat_bootstrap(&mut self) -> Result<Response, DeckError> {
        self.execute(deckclip_protocol::cmd::AI_CHAT_BOOTSTRAP, json!({}), 0)
            .await
    }

    pub async fn chat_open(
        &mut self,
        session_id: Option<&str>,
        conversation_id: Option<&str>,
        new_conversation: bool,
    ) -> Result<Response, DeckError> {
        let mut args = json!({});
        if let Some(session_id) = session_id {
            args["sessionId"] = json!(session_id);
        }
        if let Some(conversation_id) = conversation_id {
            args["conversationId"] = json!(conversation_id);
        }
        if new_conversation {
            args["new"] = json!(true);
        }

        self.execute(deckclip_protocol::cmd::AI_CHAT_OPEN, args, 0)
            .await
    }

    pub async fn chat_clipboard_read(&mut self) -> Result<Response, DeckError> {
        self.execute(deckclip_protocol::cmd::AI_CHAT_CLIPBOARD_READ, json!({}), 0)
            .await
    }

    pub async fn chat_send(
        &mut self,
        session_id: &str,
        text: &str,
        attachments: Option<Value>,
    ) -> Result<Response, DeckError> {
        let mut args = json!({
            "sessionId": session_id,
            "text": text,
        });

        if let Some(attachments) = attachments {
            args["attachments"] = attachments;
        }

        self.execute(deckclip_protocol::cmd::AI_CHAT_SEND, args, 0)
            .await
    }

    pub async fn chat_approval_respond(
        &mut self,
        session_id: &str,
        call_id: &str,
        approved: bool,
    ) -> Result<Response, DeckError> {
        self.execute(
            deckclip_protocol::cmd::AI_CHAT_APPROVAL_RESPOND,
            json!({
                "sessionId": session_id,
                "callId": call_id,
                "approved": approved,
            }),
            0,
        )
        .await
    }

    pub async fn chat_cancel(&mut self, session_id: &str) -> Result<Response, DeckError> {
        self.execute(
            deckclip_protocol::cmd::AI_CHAT_CANCEL,
            json!({ "sessionId": session_id }),
            0,
        )
        .await
    }

    pub async fn chat_history_list(
        &mut self,
        query: Option<&str>,
        cursor: Option<&str>,
        limit: Option<u32>,
    ) -> Result<Response, DeckError> {
        let mut args = json!({});
        if let Some(query) = query {
            args["query"] = json!(query);
        }
        if let Some(cursor) = cursor {
            args["cursor"] = json!(cursor);
        }
        if let Some(limit) = limit {
            args["limit"] = json!(limit);
        }
        self.execute(deckclip_protocol::cmd::AI_CHAT_HISTORY_LIST, args, 0)
            .await
    }

    pub async fn chat_history_load(
        &mut self,
        session_id: &str,
        conversation_id: &str,
    ) -> Result<Response, DeckError> {
        self.execute(
            deckclip_protocol::cmd::AI_CHAT_HISTORY_LOAD,
            json!({
                "sessionId": session_id,
                "conversationId": conversation_id,
            }),
            0,
        )
        .await
    }

    pub async fn chat_compact(&mut self, session_id: &str) -> Result<Response, DeckError> {
        self.execute(
            deckclip_protocol::cmd::AI_CHAT_COMPACT,
            json!({ "sessionId": session_id }),
            0,
        )
        .await
    }

    pub async fn chat_close(&mut self, session_id: &str) -> Result<Response, DeckError> {
        self.execute(
            deckclip_protocol::cmd::AI_CHAT_CLOSE,
            json!({ "sessionId": session_id }),
            0,
        )
        .await
    }

    pub async fn recv_chat_frame(&mut self) -> Result<ChatStreamFrame, DeckError> {
        self.ensure_connected().await?;

        let transport = self.transport.as_mut().ok_or(DeckError::NotRunning)?;
        let value: Value = transport.recv().await?;

        if value.get("event").is_some() {
            let event = serde_json::from_value::<EventFrame>(value)
                .map_err(|error| DeckError::Protocol(error.to_string()))?;
            return Ok(ChatStreamFrame::Event(event));
        }

        let response = serde_json::from_value::<Response>(value)
            .map_err(|error| DeckError::Protocol(error.to_string()))?;
        Ok(ChatStreamFrame::Response(response))
    }
}
