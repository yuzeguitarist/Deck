use owo_colors::OwoColorize;
use serde_json::json;

use crate::i18n;

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
    pub fn print_error(&self, err: &dyn std::fmt::Display) {
        match self {
            OutputMode::Text => eprintln!("{} {}", i18n::t("label.error").red().bold(), err),
            OutputMode::Json => {
                eprintln!("{}", json!({ "ok": false, "error": err.to_string() }));
            }
        }
    }
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
