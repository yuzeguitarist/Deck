#[allow(dead_code)] // referenced only on macOS non-test builds and in tests; harmless on other targets
const AI_DONE_WAV: &[u8] = include_bytes!("assets/ai_done.wav");

#[cfg(any(test, not(target_os = "macos")))]
pub(crate) fn play() {}

#[cfg(all(not(test), target_os = "macos"))]
pub(crate) fn play() {
    if std::env::var_os("DECKCLIP_DISABLE_COMPLETION_SOUND").is_some() {
        return;
    }

    if let Err(err) = std::thread::Builder::new()
        .name("deckclip-completion-sound".to_string())
        .spawn(|| {
            if let Err(err) = play_blocking() {
                tracing::debug!("failed to play deckclip completion sound: {err}");
            }
        })
    {
        tracing::debug!("failed to start deckclip completion sound thread: {err}");
    }
}

#[cfg(all(not(test), target_os = "macos"))]
fn play_blocking() -> std::io::Result<()> {
    use std::process::Command;
    use std::process::Stdio;

    let path = ensure_cached_sound_file()?;
    let mut child = Command::new("afplay")
        .arg(path)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()?;
    let _ = child.wait();
    Ok(())
}

#[cfg(all(not(test), target_os = "macos"))]
fn ensure_cached_sound_file() -> std::io::Result<std::path::PathBuf> {
    let path = std::env::temp_dir().join("deckclip-ai-done-04d-v1.wav");
    if should_refresh_cached_sound(&path) {
        std::fs::write(&path, AI_DONE_WAV)?;
    }
    Ok(path)
}

#[cfg(all(not(test), target_os = "macos"))]
fn should_refresh_cached_sound(path: &std::path::Path) -> bool {
    path.metadata()
        .map(|metadata| metadata.len() != AI_DONE_WAV.len() as u64)
        .unwrap_or(true)
}

#[cfg(test)]
mod tests {
    use super::AI_DONE_WAV;

    #[test]
    fn embeds_selected_completion_wav() {
        assert_eq!(&AI_DONE_WAV[..4], b"RIFF");
        assert_eq!(&AI_DONE_WAV[8..12], b"WAVE");
        assert_eq!(AI_DONE_WAV.len(), 67_076);
    }
}
