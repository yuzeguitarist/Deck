use std::io;
use std::path::Path;

use hmac::{Hmac, Mac};
use serde_json::Value;
use sha2::Sha256;
use tokio::fs;
use tracing::debug;

use crate::error::DeckError;

type HmacSha256 = Hmac<Sha256>;

/// Read the auth token from the token file.
///
/// Reads the file directly to avoid the TOCTOU race that an `exists()` probe
/// would introduce. `NotFound` is mapped to `DeckError::TokenNotFound` so the
/// CLI can surface a precise error message; every other IO error becomes a
/// generic auth failure with the underlying reason.
pub async fn read_token(path: &Path) -> Result<String, DeckError> {
    match fs::read_to_string(path).await {
        Ok(content) => {
            let token = content.trim().to_string();
            if token.is_empty() {
                return Err(DeckError::Auth("token 文件为空".into()));
            }
            debug!("token loaded from {}", path.display());
            Ok(token)
        }
        Err(err) if err.kind() == io::ErrorKind::NotFound => Err(DeckError::TokenNotFound {
            path: path.display().to_string(),
        }),
        Err(err) => Err(DeckError::Auth(format!(
            "无法读取 token 文件 {}: {}",
            path.display(),
            err
        ))),
    }
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

/// Serialize `value` into the canonical JSON form used for signing.
///
/// Keys are sorted lexicographically and there is no insignificant
/// whitespace. The implementation streams output into a single `String`
/// buffer rather than collecting intermediate `Vec<String>` per nesting
/// level, which keeps allocations linear in input size and avoids the
/// O(n²) cost of recursive `Vec::join` calls on deep payloads.
pub fn canonical_json(value: &Value) -> String {
    let mut out = String::new();
    write_canonical_json(value, &mut out);
    out
}

fn write_canonical_json(value: &Value, out: &mut String) {
    match value {
        Value::Null => out.push_str("null"),
        Value::Bool(value) => {
            if *value {
                out.push_str("true");
            } else {
                out.push_str("false");
            }
        }
        Value::Number(value) => {
            // serde_json::Number's Display matches its serialised form.
            use std::fmt::Write;
            let _ = write!(out, "{value}");
        }
        Value::String(value) => {
            // Reuse serde_json's string escaping for full RFC 8259 compliance.
            out.push_str(&serde_json::to_string(value).expect("serializing string cannot fail"));
        }
        Value::Array(values) => {
            out.push('[');
            for (idx, item) in values.iter().enumerate() {
                if idx > 0 {
                    out.push(',');
                }
                write_canonical_json(item, out);
            }
            out.push(']');
        }
        Value::Object(map) => {
            out.push('{');
            let mut entries: Vec<(&String, &Value)> = map.iter().collect();
            entries.sort_by_key(|(key, _)| key.as_str());
            for (idx, (key, item)) in entries.into_iter().enumerate() {
                if idx > 0 {
                    out.push(',');
                }
                out.push_str(&serde_json::to_string(key).expect("serializing key cannot fail"));
                out.push(':');
                write_canonical_json(item, out);
            }
            out.push('}');
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

    #[test]
    fn canonical_json_handles_arrays_and_specials() {
        let args = json!([1, "a", null, true, false, {"k": "v"}]);
        assert_eq!(
            canonical_json(&args),
            r#"[1,"a",null,true,false,{"k":"v"}]"#
        );
    }

    #[test]
    fn canonical_json_escapes_strings() {
        let args = json!({"text": "hello \"world\"\n你好"});
        assert_eq!(canonical_json(&args), r#"{"text":"hello \"world\"\n你好"}"#);
    }
}
