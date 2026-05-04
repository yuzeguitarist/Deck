use thiserror::Error;

#[derive(Debug, Error)]
pub enum DeckError {
    #[error("Deck App 未运行或未启用 Deck CLI")]
    NotRunning,

    #[error("连接失败: {0}")]
    Connection(String),

    #[error("认证失败: {0}")]
    Auth(String),

    #[error("Token 文件不存在: {path}")]
    TokenNotFound { path: String },

    #[error("请求超时")]
    Timeout,

    #[error("协议错误: {0}")]
    Protocol(String),

    #[error("服务端错误 [{code}]: {message}")]
    Server { code: String, message: String },

    #[error("IO 错误: {0}")]
    Io(#[from] std::io::Error),

    #[error("{0}")]
    Other(#[from] anyhow::Error),
}

impl DeckError {
    /// Map an `std::io::Error` produced while talking to the Deck App socket
    /// to the most accurate `DeckError` variant.
    ///
    /// All "the peer is gone" / "the socket is no longer usable" errors
    /// collapse to `NotRunning` so users see a clear, actionable message
    /// instead of low-level errno text.
    pub(crate) fn from_socket_io(err: std::io::Error) -> Self {
        use std::io::ErrorKind;
        match err.kind() {
            ErrorKind::NotFound
            | ErrorKind::ConnectionRefused
            | ErrorKind::ConnectionAborted
            | ErrorKind::ConnectionReset
            | ErrorKind::BrokenPipe
            | ErrorKind::UnexpectedEof
            | ErrorKind::NotConnected => DeckError::NotRunning,
            ErrorKind::TimedOut => DeckError::Timeout,
            _ => DeckError::Connection(err.to_string()),
        }
    }
}

impl From<deckclip_protocol::codec::CodecError> for DeckError {
    fn from(e: deckclip_protocol::codec::CodecError) -> Self {
        match e {
            deckclip_protocol::codec::CodecError::Io(io) => DeckError::from_socket_io(io),
            other => DeckError::Protocol(other.to_string()),
        }
    }
}
