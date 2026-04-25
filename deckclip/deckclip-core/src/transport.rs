use std::path::Path;

use deckclip_protocol::codec::{self, CodecError};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::UnixStream;
use tracing::debug;

use crate::error::DeckError;

const MAX_BUFFER_SIZE: usize = 16 * 1024 * 1024 + 6;

/// A transport connection over Unix Domain Socket with frame codec.
pub struct Transport {
    stream: UnixStream,
    buf: Vec<u8>,
}

impl Transport {
    /// Connect to the Deck App's UDS.
    pub async fn connect(path: &Path) -> Result<Self, DeckError> {
        let stream = UnixStream::connect(path).await.map_err(|e| {
            if e.kind() == std::io::ErrorKind::NotFound
                || e.kind() == std::io::ErrorKind::ConnectionRefused
            {
                DeckError::NotRunning
            } else {
                DeckError::Connection(e.to_string())
            }
        })?;
        debug!("connected to {}", path.display());
        Ok(Self {
            stream,
            buf: Vec::with_capacity(4096),
        })
    }

    /// Send a framed message.
    pub async fn send<T: serde::Serialize>(&mut self, msg: &T) -> Result<(), DeckError> {
        let frame = codec::encode_frame(msg)?;
        self.stream.write_all(&frame).await?;
        self.stream.flush().await?;
        Ok(())
    }

    /// Receive a framed message. Blocks until a complete frame is available.
    pub async fn recv<T: serde::de::DeserializeOwned>(&mut self) -> Result<T, DeckError> {
        loop {
            // Try decoding from existing buffer
            match codec::decode_frame::<T>(&self.buf) {
                Ok((msg, consumed)) => {
                    self.buf.drain(..consumed);
                    return Ok(msg);
                }
                Err(CodecError::Incomplete { .. }) => {
                    // Need more data
                }
                Err(e) => return Err(e.into()),
            }

            // Read more data from socket
            let mut tmp = [0u8; 4096];
            let n = self.stream.read(&mut tmp).await?;
            if n == 0 {
                return Err(DeckError::Connection("连接已关闭".into()));
            }
            self.buf.extend_from_slice(&tmp[..n]);
            if self.buf.len() > MAX_BUFFER_SIZE {
                return Err(DeckError::Protocol("接收缓冲区过大".into()));
            }
        }
    }
}
