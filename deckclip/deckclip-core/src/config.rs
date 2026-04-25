use std::path::PathBuf;

/// Default socket path: ~/Library/Application Support/Deck/deckclip.sock
pub fn default_socket_path() -> PathBuf {
    app_support_dir().join("deckclip.sock")
}

/// Default token path: ~/Library/Application Support/Deck/deckclip_token
pub fn default_token_path() -> PathBuf {
    app_support_dir().join("deckclip_token")
}

/// Deck's Application Support directory
pub fn app_support_dir() -> PathBuf {
    match dirs::home_dir().or_else(|| std::env::var_os("HOME").map(PathBuf::from)) {
        Some(home) => home.join("Library/Application Support/Deck"),
        None => std::env::temp_dir().join("Deck"),
    }
}

/// Runtime configuration for the CLI client.
#[derive(Debug, Clone)]
pub struct Config {
    pub socket_path: PathBuf,
    pub token_path: PathBuf,
    pub timeout_ms: u64,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            socket_path: default_socket_path(),
            token_path: default_token_path(),
            timeout_ms: 0, // No client-side timeout; backend controls request lifecycle
        }
    }
}
