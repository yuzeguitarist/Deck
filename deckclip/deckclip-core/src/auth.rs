use std::path::Path;

use hmac::{Hmac, Mac};
use serde_json::Value;
use sha2::Sha256;
use tokio::fs;
use tracing::debug;

use crate::error::DeckError;

type HmacSha256 = Hmac<Sha256>;

/// Read the auth token from the token file.
pub async fn read_token(path: &Path) -> Result<String, DeckError> {
    if !path.exists() {
        return Err(DeckError::TokenNotFound {
            path: path.display().to_string(),
        });
    }
    let content = fs::read_to_string(path)
        .await
        .map_err(|e| DeckError::Auth(format!("无法读取 token 文件 {}: {}", path.display(), e)))?;
    let token = content.trim().to_string();
    if token.is_empty() {
        return Err(DeckError::Auth("token 文件为空".into()));
    }
    debug!("token loaded from {}", path.display());
    Ok(token)
}

/// Generate a random hex nonce (16 bytes → 32 hex chars).
pub fn generate_nonce() -> String {
    let bytes: [u8; 16] = rand::random();
    hex::encode(bytes)
}

/// Current unix timestamp in seconds.
pub fn current_timestamp() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("system clock before epoch")
        .as_secs()
}

/// Compute HMAC-SHA256 signature for a request.
///
/// Signing material: `{timestamp}|{nonce}|{cmd}|{canonical_json(args)}`
pub fn sign_request(
    session_key: &str,
    timestamp: u64,
    nonce: &str,
    cmd: &str,
    args: &Value,
) -> String {
    let mut mac =
        HmacSha256::new_from_slice(session_key.as_bytes()).expect("HMAC key can be any length");
    mac.update(timestamp.to_string().as_bytes());
    mac.update(b"|");
    mac.update(nonce.as_bytes());
    mac.update(b"|");
    mac.update(cmd.as_bytes());
    mac.update(b"|");
    mac.update(canonical_json(args).as_bytes());
    hex::encode(mac.finalize().into_bytes())
}

pub fn canonical_json(value: &Value) -> String {
    match value {
        Value::Null => "null".to_string(),
        Value::Bool(value) => value.to_string(),
        Value::Number(value) => value.to_string(),
        Value::String(value) => serde_json::to_string(value).expect("serializing string cannot fail"),
        Value::Array(values) => {
            let body = values
                .iter()
                .map(canonical_json)
                .collect::<Vec<_>>()
                .join(",");
            format!("[{body}]")
        }
        Value::Object(map) => {
            let mut entries = map.iter().collect::<Vec<_>>();
            entries.sort_by(|(left, _), (right, _)| left.cmp(right));
            let body = entries
                .into_iter()
                .map(|(key, value)| {
                    let key = serde_json::to_string(key).expect("serializing key cannot fail");
                    format!("{key}:{}", canonical_json(value))
                })
                .collect::<Vec<_>>()
                .join(",");
            format!("{{{body}}}")
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn nonce_length() {
        let nonce = generate_nonce();
        assert_eq!(nonce.len(), 32);
    }

    #[test]
    fn sign_deterministic() {
        let args = json!({});
        let sig1 = sign_request("secret", 1000, "abc", "health", &args);
        let sig2 = sign_request("secret", 1000, "abc", "health", &args);
        assert_eq!(sig1, sig2);
    }

    #[test]
    fn sign_differs_on_nonce() {
        let args = json!({});
        let sig1 = sign_request("secret", 1000, "aaa", "health", &args);
        let sig2 = sign_request("secret", 1000, "bbb", "health", &args);
        assert_ne!(sig1, sig2);
    }

    #[test]
    fn sign_differs_on_args() {
        let sig1 = sign_request("secret", 1000, "abc", "write", &json!({"text": "a"}));
        let sig2 = sign_request("secret", 1000, "abc", "write", &json!({"text": "b"}));
        assert_ne!(sig1, sig2);
    }

    #[test]
    fn sign_matches_known_args_vector() {
        let sig = sign_request("secret", 1000, "abc", "write", &json!({"text": "a"}));
        assert_eq!(
            sig,
            "2dc7ef3787bd6d167a924543cf8e38e7c3febb077763f9aeafa801ac8cb3c17c"
        );
    }

    #[test]
    fn canonical_json_sorts_object_keys() {
        let args = json!({"b": 2, "a": "x", "nested": {"z": true, "c": null}});
        assert_eq!(
            canonical_json(&args),
            r#"{"a":"x","b":2,"nested":{"c":null,"z":true}}"#
        );
    }
}
