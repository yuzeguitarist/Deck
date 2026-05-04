use std::path::Path;

use deckclip_protocol::codec::{self, CodecError};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::UnixStream;
use tracing::debug;

use crate::error::DeckError;

/// Soft buffer ceiling. Allows a single full-size frame (16 MB) plus a small
/// margin without allowing pathological growth.
const MAX_BUFFER_SIZE: usize = 16 * 1024 * 1024 + 6;

/// Read chunk size used when pulling bytes off the UDS. 64 KiB amortises the
/// per-syscall overhead for large clipboard payloads and AI streaming events
/// while staying small enough to minimise wasted memory for tiny replies.
const READ_CHUNK_SIZE: usize = 64 * 1024;

/// Initial read-side buffer capacity. Sized to fit one chunk so the common
/// "small reply" case never re-allocates.
const INITIAL_BUFFER_CAPACITY: usize = READ_CHUNK_SIZE;

/// A transport connection over Unix Domain Socket with frame codec.
pub struct Transport {
    stream: UnixStream,
    buf: Vec<u8>,
}

impl Transport {
    /// Connect to the Deck App's UDS.
    pub async fn connect(path: &Path) -> Result<Self, DeckError> {
        let stream = UnixStream::connect(path)
            .await
            .map_err(DeckError::from_socket_io)?;
        debug!("connected to {}", path.display());
        Ok(Self {
            stream,
            buf: Vec::with_capacity(INITIAL_BUFFER_CAPACITY),
        })
    }

    /// Send a framed message.
    ///
    /// `encode_frame` builds the entire frame (magic + length + payload) in a
    /// single buffer, so a single `write_all` is enough — no extra `flush()`
    /// is required because Tokio's `UnixStream` does not buffer writes
    /// internally.
    pub async fn send<T: serde::Serialize>(&mut self, msg: &T) -> Result<(), DeckError> {
        let frame = codec::encode_frame(msg)?;
        self.stream
            .write_all(&frame)
            .await
            .map_err(DeckError::from_socket_io)?;
        Ok(())
    }

    /// Receive a framed message. Blocks until a complete frame is available.
    pub async fn recv<T: serde::de::DeserializeOwned>(&mut self) -> Result<T, DeckError> {
        let mut chunk = [0u8; READ_CHUNK_SIZE];
        loop {
            // Try decoding from existing buffer
            match codec::decode_frame::<T>(&self.buf) {
                Ok((msg, consumed)) => {
                    if consumed == self.buf.len() {
                        // Full buffer consumed — clear in O(1) instead of
                        // copying any remainder to the front.
                        self.buf.clear();
                    } else {
                        self.buf.drain(..consumed);
                    }
                    return Ok(msg);
                }
                Err(CodecError::Incomplete { .. }) => {
                    // Need more data
                }
                Err(CodecError::Io(io)) => return Err(DeckError::from_socket_io(io)),
                Err(e) => return Err(e.into()),
            }

            if self.buf.len() >= MAX_BUFFER_SIZE {
                return Err(DeckError::Protocol("接收缓冲区过大".into()));
            }

            let n = self
                .stream
                .read(&mut chunk)
                .await
                .map_err(DeckError::from_socket_io)?;
            if n == 0 {
                // Peer closed the socket cleanly. Keep the existing user-facing
                // message ("连接已关闭") so output.rs can map it to the
                // localised err.conn_closed string.
                return Err(DeckError::Connection("连接已关闭".into()));
            }
            self.buf.extend_from_slice(&chunk[..n]);
        }
    }
}
