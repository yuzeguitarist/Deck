use crate::output::OutputMode;
use serde_json::json;

const LOGO: &str = include_str!("../logo.ans");

pub fn run(output: OutputMode) {
    let version = env!("CARGO_PKG_VERSION");
    match output {
        OutputMode::Text => {
            print!("{}", LOGO);
            println!("deckclip {}", version);
        }
        OutputMode::Json => {
            println!("{}", json!({ "version": version }));
        }
    }
}
