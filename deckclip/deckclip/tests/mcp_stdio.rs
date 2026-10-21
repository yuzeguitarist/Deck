use std::process::Stdio;
use std::time::Duration;

use serde_json::Value;
use tokio::io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader};
use tokio::process::Command;
use tokio::time::timeout;

#[tokio::test]
async fn mcp_stdio_keeps_error_logs_off_stdout() {
    let mut child = Command::new(env!("CARGO_BIN_EXE_deckclip"))
        .args(["mcp", "serve"])
        .env("RUST_LOG", "warn")
        .env("DECKCLIP_MCP_INITIALIZE_TIMEOUT_SECONDS", "5")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true)
        .spawn()
        .expect("failed to start MCP server");

    timeout(Duration::from_secs(10), async {
        let mut stdin = child.stdin.take().expect("missing stdin");
        let mut stdout = BufReader::new(child.stdout.take().expect("missing stdout")).lines();
        let mut stderr = child.stderr.take().expect("missing stderr");

        stdin
            .write_all(
                concat!(
                    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",",
                    "\"params\":{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{},",
                    "\"clientInfo\":{\"name\":\"stdio-test\",\"version\":\"1\"}}}\n"
                )
                .as_bytes(),
            )
            .await
            .expect("failed to send initialize");
        let initialized: Value = serde_json::from_str(
            &stdout
                .next_line()
                .await
                .unwrap()
                .expect("missing initialize response"),
        )
        .expect("initialize response must be JSON");
        assert_eq!(initialized["id"], 1);
        assert_eq!(initialized["result"]["serverInfo"]["name"], "deckclip-mcp");

        stdin
            .write_all(
                concat!(
                    "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}\n",
                    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",",
                    "\"params\":{\"name\":\"nonexistent_tool\",\"arguments\":{}}}\n"
                )
                .as_bytes(),
            )
            .await
            .expect("failed to send tool call");
        let response: Value = serde_json::from_str(
            &stdout
                .next_line()
                .await
                .unwrap()
                .expect("missing tool response"),
        )
        .expect("tool response must be JSON without log output");
        assert_eq!(response["id"], 2);
        assert_eq!(response["error"]["code"], -32602);

        drop(stdin);
        assert!(child
            .wait()
            .await
            .expect("failed to wait for server")
            .success());
        assert!(stdout.next_line().await.unwrap().is_none());
        let mut logs = String::new();
        stderr.read_to_string(&mut logs).await.unwrap();
        assert!(
            logs.contains("response error"),
            "missing error log on stderr: {logs}"
        );
    })
    .await
    .expect("MCP stdio test timed out");
}
