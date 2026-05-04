use super::*;
use std::hint::black_box;
use std::time::Instant;

fn test_app() -> ChatApp {
    ChatApp::from_bootstrap(BootstrapData {
        configured: true,
        account: None,
        provider: Some("AI".to_string()),
        model: Some("test".to_string()),
        session_id: None,
        conversation_id: None,
        busy: Some(false),
    })
}

fn test_attachment() -> ChatAttachmentData {
    ChatAttachmentData {
        kind: "image_ocr".to_string(),
        display_text: "截图文字".to_string(),
        full_content: "截图里的完整文字".to_string(),
        ocr_text: Some("截图里的完整文字".to_string()),
        source_item_id: Some("test-item".to_string()),
    }
}

fn synthetic_text(target_bytes: usize) -> String {
    const SEED: &str = "Deck benchmark mixed-width 文本 1234567890 ";
    let mut text = String::with_capacity(target_bytes.max(SEED.len()));
    while text.len() < target_bytes {
        text.push_str(SEED);
    }
    while text.len() > target_bytes {
        text.pop();
    }
    text
}

fn synthetic_transcript(entry_count: usize, bytes_per_entry: usize) -> Vec<TranscriptEntry> {
    (0..entry_count)
        .map(|index| {
            let text = synthetic_text(bytes_per_entry);
            if index % 2 == 0 {
                TranscriptEntry::User {
                    text,
                    attachments: Vec::new(),
                }
            } else {
                TranscriptEntry::Assistant(text)
            }
        })
        .collect()
}

fn env_usize(key: &str, default: usize) -> usize {
    std::env::var(key)
        .ok()
        .and_then(|value| value.parse().ok())
        .unwrap_or(default)
}

fn peak_rss_megabytes() -> Option<u64> {
    let mut usage = std::mem::MaybeUninit::<libc::rusage>::zeroed();
    let status = unsafe { libc::getrusage(libc::RUSAGE_SELF, usage.as_mut_ptr()) };
    if status != 0 {
        return None;
    }

    let usage = unsafe { usage.assume_init() };
    #[cfg(target_os = "macos")]
    let bytes = usage.ru_maxrss as u64;
    #[cfg(not(target_os = "macos"))]
    let bytes = (usage.ru_maxrss as u64) * 1024;
    Some(bytes / (1024 * 1024))
}

#[test]
#[ignore = "run manually for performance metrics"]
fn chat_render_perf_report() {
    let entry_count = env_usize("DECKCLIP_PERF_MESSAGES", 4_000);
    let bytes_per_entry = env_usize("DECKCLIP_PERF_CHARS", 256);
    let width = env_usize("DECKCLIP_PERF_WIDTH", 96);
    let viewport_height = env_usize("DECKCLIP_PERF_VIEWPORT_HEIGHT", 24);
    let cached_passes = env_usize("DECKCLIP_PERF_CACHED_PASSES", 1_000);
    let slice_passes = env_usize("DECKCLIP_PERF_SLICE_PASSES", 2_000);
    let stream_updates = env_usize("DECKCLIP_PERF_STREAM_DELTAS", 1_000);

    let mut app = test_app();
    app.conversation_entries = synthetic_transcript(entry_count, bytes_per_entry);
    app.bump_transcript_revision();

    let build_started = Instant::now();
    let total_lines = black_box(app.transcript_lines(width).len());
    let cold_build = build_started.elapsed();

    let cached_started = Instant::now();
    for _ in 0..cached_passes {
        black_box(app.transcript_lines(width).len());
    }
    let cached_lookup = cached_started.elapsed();

    let scroll = total_lines
        .saturating_sub(viewport_height)
        .saturating_div(2);
    let visible_started = Instant::now();
    for _ in 0..slice_passes {
        let lines = app.transcript_lines(width);
        let end = (scroll + viewport_height).min(lines.len());
        black_box(lines[scroll..end].to_vec());
    }
    let visible_slice = visible_started.elapsed();

    app.begin_send();
    let delta = synthetic_text((bytes_per_entry / 4).max(32));
    let stream_started = Instant::now();
    for _ in 0..stream_updates {
        app.streaming_text.push_str(&delta);
        app.bump_streaming_revision();
        black_box(app.transcript_lines(width).len());
    }
    let streaming_tail = stream_started.elapsed();

    eprintln!(
        "deckclip_chat_perf entries={} bytes_per_entry={} width={} total_lines={} cold_build_ms={:.2} cached_lookup_ms={:.2} visible_slice_ms={:.2} streaming_tail_ms={:.2} peak_rss_mb={}",
        entry_count,
        bytes_per_entry,
        width,
        total_lines,
        cold_build.as_secs_f64() * 1000.0,
        cached_lookup.as_secs_f64() * 1000.0,
        visible_slice.as_secs_f64() * 1000.0,
        streaming_tail.as_secs_f64() * 1000.0,
        peak_rss_megabytes()
            .map(|value| value.to_string())
            .unwrap_or_else(|| "n/a".to_string()),
    );

    assert!(total_lines > 0);
}

#[test]
fn wrapped_input_layout_tracks_cjk_cursor_columns() {
    let layout = wrapped_input_layout("你好", 2, 12);
    assert_eq!(layout.rows.len(), 1);
    assert_eq!(layout.cursor_row, 0);
    assert_eq!(layout.cursor_col, 4);
}

#[test]
fn wrapped_input_layout_keeps_ascii_after_cjk_at_visual_end() {
    let layout = wrapped_input_layout("你好我叫A", 5, 12);
    assert_eq!(layout.rows[0].text, "你好我叫A");
    assert_eq!(layout.cursor_col, 9);
}

#[test]
fn previous_word_boundary_skips_punctuation_then_word() {
    let text = "hello world  foo";
    assert_eq!(previous_word_boundary(text, text.chars().count()), 13);
    assert_eq!(previous_word_boundary(text, 13), 6);
    assert_eq!(previous_word_boundary(text, 6), 0);
    assert_eq!(previous_word_boundary(text, 0), 0);
}

#[test]
fn next_word_boundary_skips_word_then_punctuation() {
    let text = "hello world  foo";
    assert_eq!(next_word_boundary(text, 0), 6);
    assert_eq!(next_word_boundary(text, 6), 13);
    assert_eq!(next_word_boundary(text, 13), text.chars().count());
}

#[test]
fn word_boundary_handles_cjk() {
    let text = "你好 world";
    assert_eq!(next_word_boundary(text, 0), 3);
    assert_eq!(previous_word_boundary(text, text.chars().count()), 3);
}

#[test]
fn delete_word_before_cursor_removes_one_word() {
    let mut text = String::from("hello world foo");
    let mut cursor = text.chars().count();
    delete_word_before_cursor(&mut text, &mut cursor);
    assert_eq!(text, "hello world ");
    assert_eq!(cursor, 12);

    delete_word_before_cursor(&mut text, &mut cursor);
    assert_eq!(text, "hello ");
    assert_eq!(cursor, 6);

    delete_word_before_cursor(&mut text, &mut cursor);
    assert_eq!(text, "");
    assert_eq!(cursor, 0);
}

#[test]
fn delete_to_line_end_in_text_collapses_newline() {
    let mut text = String::from("first\nsecond");
    delete_to_line_end_in_text(&mut text, 5);
    assert_eq!(text, "firstsecond");

    let mut text = String::from("hello world");
    delete_to_line_end_in_text(&mut text, 5);
    assert_eq!(text, "hello");
}

#[test]
fn cursor_from_visual_position_prefers_nearest_boundary() {
    let layout = wrapped_input_layout("你好", 0, 12);
    assert_eq!(cursor_from_visual_position(&layout, 0, 0), 0);
    assert_eq!(cursor_from_visual_position(&layout, 0, 1), 1);
    assert_eq!(cursor_from_visual_position(&layout, 0, 4), 2);
}

#[test]
fn input_history_browses_multiple_entries_and_restores_draft() {
    let mut app = test_app();
    app.remember_input("你好");
    app.remember_input("/cost");

    assert!(app.browse_input_history_up());
    assert_eq!(app.input, "/cost");
    assert!(app.browse_input_history_up());
    assert_eq!(app.input, "你好");
    assert!(app.browse_input_history_down());
    assert_eq!(app.input, "/cost");
    assert!(app.browse_input_history_down());
    assert_eq!(app.input, "");
}

#[test]
fn delete_to_line_start_resets_slash_selected_footer() {
    let mut app = test_app();
    app.set_input("/help".to_string());
    app.set_tagged_footer(
        chat_format(
            "chat.footer.slash_selected",
            &[("{command}", "/help".to_string())],
        ),
        MetaTone::Dim,
        FooterTag::SlashSelected,
    );

    app.delete_to_line_start();

    assert_eq!(app.input, "");
    assert!(app.footer_message.is_none());
    assert!(app.footer_tag.is_none());
}

#[test]
fn delete_to_line_start_only_removes_text_before_cursor() {
    let mut app = test_app();
    app.set_input("hello\nworld".to_string());
    app.input_cursor = char_count("hello\nwo");

    app.delete_to_line_start();

    assert_eq!(app.input, "hello\nrld");
    assert_eq!(app.input_cursor, char_count("hello\n"));
}

#[test]
fn delete_to_line_start_on_empty_trailing_line_removes_previous_newline() {
    let mut app = test_app();
    app.set_input("hello\n\n".to_string());

    app.delete_to_line_start();

    assert_eq!(app.input, "hello\n");
    assert_eq!(app.input_cursor, char_count("hello\n"));
}

#[test]
fn delete_to_line_start_on_middle_empty_line_removes_previous_newline() {
    let mut app = test_app();
    app.set_input("hello\n\nworld".to_string());
    app.input_cursor = char_count("hello\n");

    app.delete_to_line_start();

    assert_eq!(app.input, "hello\nworld");
    assert_eq!(app.input_cursor, char_count("hello"));
}

#[test]
fn delete_to_line_start_at_non_empty_line_start_is_noop() {
    let mut app = test_app();
    app.set_input("hello\nworld".to_string());
    app.input_cursor = char_count("hello\n");

    app.delete_to_line_start();

    assert_eq!(app.input, "hello\nworld");
    assert_eq!(app.input_cursor, char_count("hello\n"));
}

#[test]
fn terminal_paste_empty_text_does_not_inject_clipboard_plain_text_into_slash_query() {
    let mut app = test_app();
    app.set_input("/cos".to_string());

    handle_ui_event(
        &mut app,
        UiEvent::TerminalPasteResolved {
            pasted_text: String::new(),
            clipboard: Ok(ClipboardPasteData {
                text: Some("最新剪贴板记录".to_string()),
                attachment: None,
                attachments: Vec::new(),
            }),
        },
    );

    assert_eq!(app.input, "/cos");
    assert_eq!(app.slash_query(), Some("/cos"));
    assert!(app
        .slash_matches()
        .iter()
        .any(|command| command.name == "/cost"));
    assert!(app.footer_message.is_none());
}

#[test]
fn terminal_paste_prefers_terminal_text_over_chat_clipboard_text() {
    let mut app = test_app();
    app.set_input("/".to_string());

    handle_ui_event(
        &mut app,
        UiEvent::TerminalPasteResolved {
            pasted_text: "cost".to_string(),
            clipboard: Ok(ClipboardPasteData {
                text: Some("最新剪贴板记录".to_string()),
                attachment: None,
                attachments: Vec::new(),
            }),
        },
    );

    assert_eq!(app.input, "/cost");
    assert_eq!(app.slash_query(), Some("/cost"));
    assert!(app.footer_message.is_none());
}

#[test]
fn long_paste_collapses_into_placeholder_and_expands_for_submission() {
    let mut app = test_app();
    let large = "x".repeat(LARGE_PASTE_CHAR_THRESHOLD + 32);

    assert!(app.insert_paste_text(&large));
    assert_eq!(app.pending_paste_count(), 1);
    assert_ne!(app.input, large);
    assert!(app.input.contains("粘贴 #1") || app.input.contains("Paste #1"));
    assert_eq!(app.expand_input_with_pending_pastes(), large);
}

#[test]
fn backspace_removes_entire_pending_paste_placeholder() {
    let mut app = test_app();
    let large = "x".repeat(LARGE_PASTE_CHAR_THRESHOLD + 10);

    app.insert_paste_text(&large);
    app.backspace();

    assert_eq!(app.input, "");
    assert_eq!(app.pending_paste_count(), 0);
}

#[test]
fn delete_forward_removes_entire_pending_paste_placeholder() {
    let mut app = test_app();
    let large = "x".repeat(LARGE_PASTE_CHAR_THRESHOLD + 10);

    app.insert_paste_text(&large);
    app.input_cursor = 0;
    app.delete_forward();

    assert_eq!(app.input, "");
    assert_eq!(app.pending_paste_count(), 0);
}

#[test]
fn input_history_restores_pending_paste_placeholder_and_payload() {
    let mut app = test_app();
    let large = "x".repeat(LARGE_PASTE_CHAR_THRESHOLD + 24);

    app.insert_paste_text(&large);
    let display = app.input.clone();
    app.remember_input(&display);
    app.set_input("draft".to_string());

    assert!(app.browse_input_history_up());
    assert_eq!(app.input, display);
    assert_eq!(app.pending_paste_count(), 1);
    assert_eq!(app.expand_input_with_pending_pastes(), large);
}

fn lines_text(lines: &[Line<'static>]) -> String {
    lines
        .iter()
        .map(|line| {
            line.spans
                .iter()
                .map(|span| span.content.as_ref())
                .collect::<String>()
        })
        .collect::<Vec<_>>()
        .join("\n")
}

fn tool_event(call_id: &str, tool: &str, parameters: Value) -> ToolEventData {
    ToolEventData {
        call_id: call_id.to_string(),
        tool: tool.to_string(),
        parameters,
        approved: None,
        result: None,
    }
}

#[test]
fn modify_plugin_approval_renders_full_diff_block() {
    let mut overlay = ApprovalOverlay::from_tool(&tool_event(
        "call-1",
        "modify_script_plugin",
        serde_json::json!({
            "plugin_name": "Weather",
            "plugin_id": "weather.fetch",
            "touched_files": ["index.js"],
            "patch_preview": "@@ old preview @@",
            "patch": "diff --git a/index.js b/index.js\n--- a/index.js\n+++ b/index.js\n@@ -1,1 +1,1 @@\n-console.log('old');\n+console.log('new');\n",
        }),
    ));

    let text = lines_text(overlay.content_lines(64));

    assert!(text.contains(" Patch "));
    assert!(text.contains("diff --git a/index.js b/index.js"));
    assert!(text.contains("-console.log('old');"));
    assert!(text.contains("+console.log('new');"));
    assert!(!text.contains("\"patch\":"));
}

#[test]
fn modify_plugin_approval_filters_machine_patch_markers() {
    let mut overlay = ApprovalOverlay::from_tool(&tool_event(
        "call-raw",
        "modify_script_plugin",
        serde_json::json!({
            "plugin_name": "Weather",
            "plugin_id": "weather.fetch",
            "touched_files": ["index.js"],
            "patch": "*** Begin Patch\n*** Update File: index.js\n@@\n-console.log('old')\n+console.log('new')\n*** End Patch",
        }),
    ));

    let text = lines_text(overlay.content_lines(64));

    assert!(text.contains("index.js  [update]  +1 -1"));
    assert!(text.contains("console.log('new')"));
    assert!(!text.contains("*** Begin Patch"));
    assert!(!text.contains("*** End Patch"));
    assert!(!text.contains("*** Update File: index.js"));
    assert!(!text.contains("\n  @@"));
}

#[test]
fn modify_plugin_approval_supports_move_headers() {
    let mut overlay = ApprovalOverlay::from_tool(&tool_event(
        "call-move",
        "modify_script_plugin",
        serde_json::json!({
            "plugin_name": "Weather",
            "plugin_id": "weather.fetch",
            "patch": "*** Begin Patch\n*** Update File: index.js\n*** Move to: src/index.js\n@@ -1,1 +1,1 @@\n-console.log('old')\n+console.log('new')\n*** End Patch",
        }),
    ));

    let text = lines_text(overlay.content_lines(72));

    assert!(text.contains("index.js -> src/index.js  [move]  +1 -1"));
    assert!(text.contains("@@ -1,1 +1,1 @@"));
}

#[test]
fn create_plugin_approval_renders_manifest_and_script_sections() {
    let mut overlay = ApprovalOverlay::from_tool(&tool_event(
        "call-2",
        "generate_script_plugin",
        serde_json::json!({
            "plugin_name": "Weather",
            "plugin_id": "weather.fetch",
            "requires_network": true,
            "overwrite": false,
            "manifest_json": "{\"name\":\"Weather\",\"main\":\"index.js\",\"permissions\":{\"network\":true}}",
            "script_code": "export default async function run() {\n  return 'ok'\n}",
        }),
    ));

    let text = lines_text(overlay.content_lines(64));

    assert!(text.contains(" manifest.json "));
    assert!(text.contains(" index.js "));
    assert!(text.contains("\"name\": \"Weather\""));
    assert!(text.contains("export default async function run()"));
}

#[test]
fn approval_overlay_scroll_clamps_to_viewport() {
    let mut overlay = ApprovalOverlay::from_tool(&tool_event(
        "call-3",
        "write_clipboard",
        serde_json::json!({
            "text": (0..20).map(|index| format!("line {index}")).collect::<Vec<_>>().join("\n"),
        }),
    ));

    let total_lines = overlay.content_lines(48).len();
    overlay.update_viewport(4, total_lines);

    overlay.scroll_end();
    assert_eq!(overlay.scroll, total_lines.saturating_sub(4));

    overlay.scroll_down(10);
    assert_eq!(overlay.scroll, total_lines.saturating_sub(4));

    overlay.scroll_home();
    assert_eq!(overlay.scroll, 0);
}

#[test]
fn streaming_tail_uses_plain_thinking_label() {
    let mut app = test_app();
    app.begin_send();

    let text = lines_text(&build_transcript_tail_lines(&app, 48));

    assert!(text.contains("Thinking"));
    assert!(!text.contains("Deck AI"));
}

#[test]
fn thinking_tail_has_right_offset() {
    let mut app = test_app();
    app.begin_send();

    let text = lines_text(&build_transcript_tail_lines(&app, 48));

    assert_eq!(text, format!("  {} Thinking", app.spinner_frame()));
}

#[test]
fn short_status_tail_stays_at_bottom() {
    let mut app = test_app();
    app.begin_send();

    let lines = transcript_view_lines(&mut app, 48, 4);
    let rendered = lines
        .iter()
        .map(|line| {
            line.spans
                .iter()
                .map(|span| span.content.as_ref())
                .collect::<String>()
        })
        .collect::<Vec<_>>();

    assert_eq!(
        rendered,
        vec![
            String::new(),
            String::new(),
            String::new(),
            format!("  {} Thinking", app.spinner_frame()),
        ]
    );
}

#[test]
fn existing_conversation_does_not_shift_down_while_streaming() {
    let mut app = test_app();
    app.conversation_entries.push(TranscriptEntry::User {
        text: "hello".to_string(),
        attachments: Vec::new(),
    });
    app.bump_transcript_revision();
    app.begin_send();

    let lines = transcript_view_lines(&mut app, 48, 6);
    let rendered = lines_text(&lines);

    assert!(rendered.starts_with("> hello"));
}

#[test]
fn slash_popup_mouse_wheel_requires_hover() {
    let mut app = test_app();
    app.input = "/".to_string();
    app.input_cursor = 1;
    app.slash_selected = 1;
    app.slash_popup_hitboxes = vec![Rect {
        x: 10,
        y: 10,
        width: 10,
        height: 3,
    }];
    let client = Arc::new(Mutex::new(DeckClient::new(Config::default())));
    let (ui_tx, _ui_rx) = unbounded_channel();

    handle_mouse_event(
        &mut app,
        MouseEvent {
            kind: MouseEventKind::ScrollDown,
            column: 0,
            row: 0,
            modifiers: KeyModifiers::empty(),
        },
        client,
        ui_tx,
    );

    assert_eq!(app.slash_selected, 1);
}

#[test]
fn tool_events_replace_thinking_without_appending_activity() {
    let mut app = test_app();
    app.begin_send();

    handle_ui_event(
        &mut app,
        UiEvent::ToolStarted(tool_event(
            "call-1",
            "record_memory",
            serde_json::json!({"memory": "Sam Altman"}),
        )),
    );

    assert_eq!(app.activities.len(), 0);
    let expected = chat_text("chat.tool.saving_memory");
    assert_eq!(app.busy_action.as_deref(), Some(expected.as_str()));
    assert!(app.status_text().contains(expected.as_str()));

    handle_ui_event(
        &mut app,
        UiEvent::ToolFinished(ToolEventData {
            call_id: "call-1".to_string(),
            tool: "record_memory".to_string(),
            parameters: serde_json::json!({"memory": "Sam Altman"}),
            approved: Some(true),
            result: Some(serde_json::json!({"ok": true})),
        }),
    );

    assert_eq!(app.activities.len(), 0);
    assert!(app.busy_action_release_at.is_some());
}

#[test]
fn repeated_search_tool_status_matches_app_style() {
    let mut app = test_app();
    app.begin_send();

    handle_ui_event(
        &mut app,
        UiEvent::ToolStarted(tool_event(
            "search-1",
            "search_clipboard",
            serde_json::json!({"query": "hello"}),
        )),
    );
    let expected = chat_format(
        "chat.tool.searching_clipboard_with_query",
        &[("{query}", "hello".to_string())],
    );
    assert_eq!(app.busy_action.as_deref(), Some(expected.as_str()));

    handle_ui_event(
        &mut app,
        UiEvent::ToolStarted(tool_event(
            "search-2",
            "search_clipboard",
            serde_json::json!({"query": "hello"}),
        )),
    );
    let repeated = format!("{} +1", expected);
    assert_eq!(app.busy_action.as_deref(), Some(repeated.as_str()));
}

#[test]
fn cancelled_is_terminal_stream_event() {
    assert!(is_terminal_stream_event(chat_event::CANCELLED));
    assert!(is_terminal_stream_event(chat_event::DONE));
    assert!(is_terminal_stream_event(chat_event::ERROR));
    assert!(!is_terminal_stream_event(chat_event::ASSISTANT_DELTA));
}

#[test]
fn cancelled_event_finishes_streaming_state() {
    let mut app = test_app();
    app.begin_send();
    app.set_footer(chat_text("chat.footer.stopping"), MetaTone::Warning);

    handle_ui_event(&mut app, UiEvent::Cancelled);

    assert_eq!(app.mode, ChatMode::Ready);
    assert_eq!(app.busy_action, None);
    assert_eq!(app.streaming_text, "");
    assert_eq!(
        app.footer_message.as_ref().map(|(text, _)| text.as_str()),
        Some(chat_text("chat.footer.reply_cancelled").as_str())
    );
}

#[test]
fn quit_hint_footer_uses_trigger_specific_text() {
    let mut app = test_app();

    app.arm_quit_hint(QuitHintTrigger::Esc);

    assert_eq!(
        app.footer_message.as_ref().map(|(text, _)| text.as_str()),
        Some(chat_text("chat.quit_hint.esc").as_str())
    );
    assert_eq!(
        app.footer_tag,
        Some(FooterTag::QuitHint(QuitHintTrigger::Esc))
    );
}

#[test]
fn input_panel_height_adds_attachment_row() {
    let mut app = test_app();
    let base = input_panel_height(&app, 48);

    app.set_pending_attachment(test_attachment());

    assert_eq!(input_panel_height(&app, 48), base + ATTACHMENT_CARD_HEIGHT);
}

#[test]
fn input_panel_height_adds_pending_paste_row() {
    let mut app = test_app();
    let base = input_panel_height(&app, 48);

    app.insert_paste_text(&"x".repeat(LARGE_PASTE_CHAR_THRESHOLD + 12));

    assert_eq!(input_panel_height(&app, 48), base + ATTACHMENT_CARD_HEIGHT);
}

#[test]
fn replace_session_restores_user_attachment() {
    let mut app = test_app();
    let attachment = test_attachment();

    app.replace_session(
        SessionData {
            session_id: "session-1".to_string(),
            conversation: ConversationData {
                id: "conversation-1".to_string(),
                title: "Test".to_string(),
                provider: "AI".to_string(),
                model: "test".to_string(),
                messages: vec![ConversationMessageData {
                    role: "user".to_string(),
                    text: "".to_string(),
                    attachment: Some(attachment.clone()),
                    attachments: Vec::new(),
                }],
            },
            context_usage: None,
            last_assistant_text: None,
        },
        false,
    );

    match &app.conversation_entries[0] {
        TranscriptEntry::User { text, attachments } => {
            assert!(text.is_empty());
            assert_eq!(attachments.len(), 1);
            assert_eq!(attachments[0].display_text, attachment.display_text);
        }
        other => panic!("unexpected transcript entry: {other:?}"),
    }
}

#[test]
fn slash_command_normalizes_model_alias() {
    assert_eq!(normalize_slash_command("/model"), Some("/model"));
    assert_eq!(normalize_slash_command("/login"), Some("/login"));
}

#[test]
fn slash_login_requests_login_screen() {
    let mut app = test_app();
    let client = Arc::new(Mutex::new(DeckClient::new(Config::default())));
    let (ui_tx, _ui_rx) = unbounded_channel();

    app.set_input("/login".to_string());
    handle_key_event(
        &mut app,
        KeyEvent::new(KeyCode::Enter, KeyModifiers::empty()),
        client,
        ui_tx,
    );

    assert!(app.take_login_request());
    assert!(app.input.is_empty());
}

#[test]
fn enter_while_streaming_preserves_draft_input() {
    let mut app = test_app();
    let client = Arc::new(Mutex::new(DeckClient::new(Config::default())));
    let (ui_tx, _ui_rx) = unbounded_channel();

    app.begin_send();
    app.set_input("继续分析这个片段".to_string());
    handle_key_event(
        &mut app,
        KeyEvent::new(KeyCode::Enter, KeyModifiers::empty()),
        client,
        ui_tx,
    );

    assert_eq!(app.input, "继续分析这个片段");
    assert_eq!(app.input_history.len(), 0);
    assert_eq!(
        app.footer_message.as_ref().map(|(text, _)| text.as_str()),
        Some(chat_text("chat.footer.reply_incomplete_stop").as_str())
    );
}

#[test]
fn defaults_key_maps_current_provider_model_keys() {
    assert_eq!(deck_model_defaults_key("chatgpt"), Some("aiChatGPTModel"));
    assert_eq!(deck_model_defaults_key("openai_api"), Some("aiOpenAIModel"));
    assert_eq!(
        deck_model_defaults_key("anthropic"),
        Some("aiAnthropicModel")
    );
    assert_eq!(deck_model_defaults_key("ollama"), Some("aiOllamaModel"));
    assert_eq!(deck_model_defaults_key("unknown"), None);
}

#[test]
fn visible_list_window_keeps_selected_slash_item_visible() {
    assert_eq!(visible_list_window(0, 6, 6), (0, 6));
    assert_eq!(visible_list_window(5, 6, 5), (1, 5));
    assert_eq!(visible_list_window(4, 8, 5), (0, 5));
    assert_eq!(visible_list_window(7, 8, 5), (3, 5));
}

#[test]
fn ctrl_o_opens_model_editor() {
    let mut app = test_app();
    let client = Arc::new(Mutex::new(DeckClient::new(Config::default())));
    let (ui_tx, _ui_rx) = unbounded_channel();

    handle_key_event(
        &mut app,
        KeyEvent::new(KeyCode::Char('o'), KeyModifiers::CONTROL),
        client,
        ui_tx,
    );

    assert!(matches!(app.overlay, OverlayState::ModelEditor(_)));
}

#[test]
fn shift_tab_toggles_execution_mode() {
    let mut app = test_app();
    let client = Arc::new(Mutex::new(DeckClient::new(Config::default())));
    let (ui_tx, _ui_rx) = unbounded_channel();

    handle_key_event(
        &mut app,
        KeyEvent::new(KeyCode::BackTab, KeyModifiers::SHIFT),
        client.clone(),
        ui_tx.clone(),
    );

    assert_eq!(app.execution_mode, ExecutionMode::Yolo);
    assert_eq!(
        app.footer_message.as_ref().map(|(text, _)| text.as_str()),
        Some(chat_text("chat.footer.execution.yolo").as_str())
    );

    handle_key_event(
        &mut app,
        KeyEvent::new(KeyCode::BackTab, KeyModifiers::SHIFT),
        client,
        ui_tx,
    );

    assert_eq!(app.execution_mode, ExecutionMode::Agent);
    assert_eq!(
        app.footer_message.as_ref().map(|(text, _)| text.as_str()),
        Some(chat_text("chat.footer.execution.agent").as_str())
    );
}

#[test]
fn yolo_auto_approves_without_overlay() {
    let mut app = test_app();
    app.begin_send();
    app.session_id = "session-1".to_string();
    app.execution_mode = ExecutionMode::Yolo;

    let dispatch = handle_ui_event(
        &mut app,
        UiEvent::ApprovalRequested(tool_event(
            "call-1",
            "write_clipboard",
            serde_json::json!({"text": "hello"}),
        )),
    )
    .expect("expected auto approval dispatch");

    assert_eq!(dispatch.session_id, "session-1");
    assert_eq!(dispatch.call_id, "call-1");
    assert!(dispatch.approved);
    assert_eq!(dispatch.completion, None);
    assert_eq!(app.mode, ChatMode::Streaming);
    assert!(matches!(app.overlay, OverlayState::None));
    assert_eq!(
        app.footer_message.as_ref().map(|(text, _)| text.as_str()),
        Some(chat_text("chat.footer.generating").as_str())
    );
    assert!(app.activities.is_empty());
}

#[test]
fn yolo_ready_status_stays_plain_because_header_badge_shows_mode() {
    let mut app = test_app();
    app.execution_mode = ExecutionMode::Yolo;

    assert_eq!(app.status_text(), chat_text("chat.status.ready"));
}

#[test]
fn sound_slash_toggles_completion_sound_for_current_chat() {
    let mut app = test_app();
    let client = Arc::new(Mutex::new(DeckClient::new(Config::default())));
    let (ui_tx, _ui_rx) = unbounded_channel();

    assert!(app.completion_sound_enabled);

    handle_slash_command(
        &mut app,
        "/sound".to_string(),
        client.clone(),
        ui_tx.clone(),
    );
    assert!(!app.completion_sound_enabled);
    assert_eq!(
        app.footer_message.as_ref().map(|(text, _)| text.as_str()),
        Some(chat_text("chat.footer.sound_off").as_str())
    );

    handle_slash_command(&mut app, "/sound".to_string(), client, ui_tx);
    assert!(app.completion_sound_enabled);
    assert_eq!(
        app.footer_message.as_ref().map(|(text, _)| text.as_str()),
        Some(chat_text("chat.footer.sound_on").as_str())
    );
}

#[test]
fn yolo_thinking_status_stays_plain_without_tool_call() {
    let mut app = test_app();
    app.begin_send();
    app.execution_mode = ExecutionMode::Yolo;

    assert_eq!(
        app.status_text(),
        format!(
            "{} {}",
            app.spinner_frame(),
            chat_text("chat.status.thinking_plain")
        )
    );
}

#[test]
fn yolo_status_prefixes_normal_tool_status_inline() {
    let mut app = test_app();
    app.begin_send();
    app.execution_mode = ExecutionMode::Yolo;

    handle_ui_event(
        &mut app,
        UiEvent::ToolStarted(tool_event(
            "call-1",
            "write_clipboard",
            serde_json::json!({"text": "hello"}),
        )),
    );

    let expected_tool = chat_text("chat.tool.writing_clipboard");
    assert_eq!(app.busy_action.as_deref(), Some(expected_tool.as_str()));
    let status = app.status_text();
    assert!(status.contains("YOLO MODE:"));
    assert!(status.contains(expected_tool.as_str()));
}
