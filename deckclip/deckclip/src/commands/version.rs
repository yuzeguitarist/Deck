use std::sync::OnceLock;

use crate::output::OutputMode;
use serde_json::json;

const LOGO: &str = include_str!("../logo.ans");
const LOGO_SCALE: f32 = 0.75;

static SCALED_LOGO: OnceLock<String> = OnceLock::new();

#[derive(Clone, Copy, PartialEq, Eq)]
struct RgbColor {
    r: u8,
    g: u8,
    b: u8,
}

#[derive(Clone, Copy)]
struct LogoCell {
    ch: char,
    fg: Option<RgbColor>,
}

fn terminal_width() -> Option<u16> {
    unsafe {
        let mut ws: libc::winsize = std::mem::zeroed();
        if libc::ioctl(libc::STDOUT_FILENO, libc::TIOCGWINSZ, &mut ws) == 0 && ws.ws_col > 0 {
            Some(ws.ws_col)
        } else {
            None
        }
    }
}

pub fn run(output: OutputMode) {
    let version = env!("CARGO_PKG_VERSION");
    match output {
        OutputMode::Text => {
            if terminal_width().unwrap_or(80) >= 50 {
                print!("{}", scaled_logo());
            }
            println!("deckclip {}", version);
            println!("\x1b]8;;https://deckclip.app\x07DeckClip@Deck\x1b]8;;\x07");
            println!("© 2024-2026 Yuze Pan. All rights reserved.");
        }
        OutputMode::Json => {
            println!("{}", json!({ "version": version }));
        }
    }
}

fn scaled_logo() -> &'static str {
    SCALED_LOGO.get_or_init(|| {
        let parsed: Vec<Vec<LogoCell>> = LOGO.lines().map(parse_logo_line).collect();
        render_scaled_logo(&parsed, LOGO_SCALE)
    })
}

fn parse_logo_line(line: &str) -> Vec<LogoCell> {
    let bytes = line.as_bytes();
    let mut index = 0usize;
    let mut current_fg: Option<RgbColor> = None;
    let mut cells = Vec::new();

    while index < bytes.len() {
        if bytes[index] == 0x1b && index + 1 < bytes.len() && bytes[index + 1] == b'[' {
            if let Some(offset) = bytes[index + 2..].iter().position(|&byte| byte == b'm') {
                let end = index + 2 + offset;
                current_fg = parse_sgr_sequence(&line[index + 2..end], current_fg);
                index = end + 1;
                continue;
            }
        }

        cells.push(LogoCell {
            ch: bytes[index] as char,
            fg: current_fg,
        });
        index += 1;
    }

    cells
}

fn parse_sgr_sequence(sequence: &str, current_fg: Option<RgbColor>) -> Option<RgbColor> {
    if sequence.is_empty() {
        return None;
    }

    let parts: Vec<&str> = sequence.split(';').collect();
    if parts.len() == 1 && parts[0] == "0" {
        return None;
    }

    if parts.len() >= 5 && parts[0] == "38" && parts[1] == "2" {
        let r = parts[2].parse::<u8>().ok();
        let g = parts[3].parse::<u8>().ok();
        let b = parts[4].parse::<u8>().ok();
        if let (Some(r), Some(g), Some(b)) = (r, g, b) {
            return Some(RgbColor { r, g, b });
        }
    }

    current_fg
}

fn render_scaled_logo(source: &[Vec<LogoCell>], scale: f32) -> String {
    let source_height = source.len();
    let source_width = source.iter().map(|line| line.len()).max().unwrap_or(0);
    if source_height == 0 || source_width == 0 {
        return String::new();
    }

    let target_width = ((source_width as f32) * scale).round().max(1.0) as usize;
    let target_height = ((source_height as f32) * scale).round().max(1.0) as usize;
    let blank = LogoCell { ch: ' ', fg: None };
    let mut output = String::new();

    for target_y in 0..target_height {
        let source_y = ((target_y as f32) / scale)
            .floor()
            .clamp(0.0, (source_height.saturating_sub(1)) as f32) as usize;
        let mut line = Vec::with_capacity(target_width);

        for target_x in 0..target_width {
            let source_x = ((target_x as f32) / scale)
                .floor()
                .clamp(0.0, (source_width.saturating_sub(1)) as f32)
                as usize;
            let cell = source
                .get(source_y)
                .and_then(|row| row.get(source_x))
                .copied()
                .unwrap_or(blank);
            line.push(cell);
        }

        while matches!(line.last(), Some(LogoCell { ch: ' ', fg: _ })) {
            line.pop();
        }

        let mut current_fg: Option<RgbColor> = None;
        for cell in line {
            if cell.fg != current_fg {
                match cell.fg {
                    Some(color) => {
                        output.push_str(&format!("\x1b[38;2;{};{};{}m", color.r, color.g, color.b))
                    }
                    None => output.push_str("\x1b[0m"),
                }
                current_fg = cell.fg;
            }
            output.push(cell.ch);
        }

        if current_fg.is_some() {
            output.push_str("\x1b[0m");
        }
        output.push('\n');
    }

    output
}
