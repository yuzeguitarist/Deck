use std::process::{Command, Output};

fn run_deckclip(args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_deckclip"))
        .args(args)
        .output()
        .expect("failed to run deckclip")
}

fn stdout(output: &Output) -> String {
    String::from_utf8(output.stdout.clone()).expect("stdout should be valid UTF-8")
}

fn stderr(output: &Output) -> String {
    String::from_utf8(output.stderr.clone()).expect("stderr should be valid UTF-8")
}

#[test]
fn version_flags_match_version_subcommand_output() {
    let version = run_deckclip(&["version"]);
    let short_flag = run_deckclip(&["-V"]);
    let long_flag = run_deckclip(&["--version"]);

    assert!(version.status.success());
    assert!(short_flag.status.success());
    assert!(long_flag.status.success());

    let version_stdout = stdout(&version);
    assert_eq!(stdout(&short_flag), version_stdout);
    assert_eq!(stdout(&long_flag), version_stdout);
}

#[test]
fn version_flags_match_version_subcommand_in_json_mode() {
    let version = run_deckclip(&["version", "--json"]);
    let short_flag = run_deckclip(&["--json", "-V"]);
    let long_flag = run_deckclip(&["--json", "--version"]);

    assert!(version.status.success());
    assert!(short_flag.status.success());
    assert!(long_flag.status.success());

    let version_stdout = stdout(&version);
    assert_eq!(stdout(&short_flag), version_stdout);
    assert_eq!(stdout(&long_flag), version_stdout);
}

#[test]
fn help_lists_login_subcommand() {
    let output = run_deckclip(&["help"]);

    assert!(output.status.success());
    assert!(stdout(&output).contains("login"));
    assert!(stdout(&output).contains("chat"));
}

#[test]
fn login_rejects_json_mode() {
    let output = run_deckclip(&["--json", "login"]);

    assert!(!output.status.success());
    assert!(stderr(&output).contains("login") || stderr(&output).contains("--json"));
}
