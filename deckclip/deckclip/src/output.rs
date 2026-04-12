use owo_colors::OwoColorize;
use serde_json::json;

use crate::i18n;
use deckclip_core::DeckError;

/// Output formatting mode.
#[derive(Debug, Clone, Copy)]
pub enum OutputMode {
    Text,
    Json,
}

impl OutputMode {
    /// Print a success message.
    pub fn print_success(&self, message: &str) {
        match self {
            OutputMode::Text => println!("{}", message.green()),
            OutputMode::Json => {
                println!("{}", json!({ "ok": true, "message": message }));
            }
        }
    }

    /// Print data — in text mode prints the string, in JSON mode prints the value.
    pub fn print_data(&self, text: &str, json_value: &serde_json::Value) {
        match self {
            OutputMode::Text => println!("{}", text),
            OutputMode::Json => println!("{}", json_value),
        }
    }

    /// Print a raw JSON response.
    pub fn print_response(&self, response: &deckclip_protocol::Response) {
        match self {
            OutputMode::Text => {
                if let Some(data) = &response.data {
                    if let Some(text) = data.get("text").and_then(|v| v.as_str()) {
                        println!("{}", text);
                    } else {
                        println!("{}", serde_json::to_string_pretty(data).unwrap_or_default());
                    }
                }
            }
            OutputMode::Json => {
                let out = json!({
                    "ok": response.ok,
                    "data": response.data,
                });
                println!("{}", serde_json::to_string(&out).unwrap_or_default());
            }
        }
    }

    /// Print an error.
    pub fn print_error(&self, err: &anyhow::Error) {
        let message = localized_error_message(err);
        match self {
            OutputMode::Text => {
                eprintln!("{} {}", i18n::t("label.error").red().bold(), message)
            }
            OutputMode::Json => {
                eprintln!("{}", json!({ "ok": false, "error": message }));
            }
        }
    }
}

fn localized_error_message(err: &anyhow::Error) -> String {
    if let Some(deck_err) = err.downcast_ref::<DeckError>() {
        return format_deck_error(deck_err);
    }
    err.to_string()
}

fn format_deck_error(err: &DeckError) -> String {
    match err {
        DeckError::NotRunning => i18n::t("err.not_running"),
        DeckError::Connection(message) => {
            if message == "连接已关闭" {
                i18n::t("err.conn_closed")
            } else {
                format_template("err.connection", &[message])
            }
        }
        DeckError::Auth(message) => {
            if message == "token 文件为空" {
                i18n::t("err.token_empty")
            } else if message == "认证被拒绝" {
                i18n::t("err.auth_rejected")
            } else if message == "无 session token" {
                i18n::t("err.no_session")
            } else if let Some((path, reason)) = parse_token_read_error(message) {
                format_template("err.token_read", &[&path, &reason])
            } else {
                format_template("err.auth", &[message])
            }
        }
        DeckError::TokenNotFound { path } => format_template("err.token_not_found", &[path]),
        DeckError::Timeout => i18n::t("err.timeout"),
        DeckError::Protocol(message) => {
            if let Some((expected, got)) = parse_id_mismatch_error(message) {
                format_template("err.id_mismatch", &[&expected, &got])
            } else {
                format_template("err.protocol", &[message])
            }
        }
        DeckError::Server { code, message } => format_template("err.server", &[code, message]),
        DeckError::Io(error) => format_template("err.io", &[&error.to_string()]),
        DeckError::Other(error) => error.to_string(),
    }
}

fn format_template(key: &str, values: &[&str]) -> String {
    let mut rendered = i18n::t(key);
    for value in values {
        rendered = rendered.replacen("{}", value, 1);
    }
    rendered
}

fn parse_token_read_error(message: &str) -> Option<(String, String)> {
    message
        .strip_prefix("无法读取 token 文件 ")
        .and_then(|rest| rest.rsplit_once(": "))
        .map(|(path, reason)| (path.to_string(), reason.to_string()))
}

fn parse_id_mismatch_error(message: &str) -> Option<(String, String)> {
    let rest = message.strip_prefix("响应 ID 不匹配: expected ")?;
    let (expected, got) = rest.split_once(", got ")?;
    Some((expected.to_string(), got.to_string()))
}

/// Read text from an optional argument or stdin.
pub fn read_text_or_stdin(text: Option<String>) -> anyhow::Result<String> {
    match text {
        Some(t) => Ok(t),
        None => {
            use std::io::{IsTerminal, Read};
            if std::io::stdin().is_terminal() {
                anyhow::bail!("{}", crate::i18n::t("err.stdin_hint"));
            }
            let mut buf = String::new();
            std::io::stdin().read_to_string(&mut buf)?;
            // Trim trailing newline from pipe
            if buf.ends_with('\n') {
                buf.pop();
                if buf.ends_with('\r') {
                    buf.pop();
                }
            }
            Ok(buf)
        }
    }
}
