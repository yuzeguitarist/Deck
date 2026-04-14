use super::*;

pub(super) use approval_input::ApprovalInputGuard;

#[derive(Debug, Clone)]
struct ApprovalSummaryItem {
    label: String,
    value: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ApprovalCodeMode {
    Plain,
    Diff,
    Json,
    JavaScript,
}

#[derive(Debug, Clone)]
enum ApprovalContentBlock {
    Note {
        title: String,
        text: String,
        tone: MetaTone,
    },
    List {
        title: String,
        items: Vec<String>,
    },
    Code {
        title: String,
        text: String,
        mode: ApprovalCodeMode,
    },
    Patch {
        title: String,
        document: ApprovalPatchDocument,
    },
}

#[derive(Debug, Clone)]
struct ApprovalPatchDocument {
    files: Vec<ApprovalPatchFile>,
}

#[derive(Debug, Clone)]
struct ApprovalPatchFile {
    path: String,
    action: ApprovalPatchFileAction,
    target_path: Option<String>,
    hunks: Vec<ApprovalPatchHunk>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ApprovalPatchFileAction {
    Update,
    Add,
    Delete,
    Move,
}

#[derive(Debug, Clone)]
struct ApprovalPatchHunk {
    header: String,
    lines: Vec<ApprovalPatchLine>,
}

#[derive(Debug, Clone)]
enum ApprovalPatchLine {
    Context(String),
    Add(String),
    Remove(String),
    Note(String),
}

#[derive(Debug, Clone, Default)]
struct ApprovalRenderCache {
    width: usize,
    lines: Vec<Line<'static>>,
}

#[derive(Debug, Clone)]
pub(super) struct ApprovalOverlay {
    pub(super) call_id: String,
    tool: String,
    title: String,
    summary: Vec<ApprovalSummaryItem>,
    content_blocks: Vec<ApprovalContentBlock>,
    pub(super) scroll: usize,
    visible_lines: usize,
    total_lines: usize,
    pub(super) preview_area: Option<Rect>,
    render_cache: ApprovalRenderCache,
}

impl ApprovalOverlay {
    pub(super) fn from_tool(tool: &ToolEventData) -> Self {
        let (title, summary, content_blocks) = approval_content(tool);
        Self {
            call_id: tool.call_id.clone(),
            tool: tool.tool.clone(),
            title,
            summary,
            content_blocks,
            scroll: 0,
            visible_lines: 0,
            total_lines: 0,
            preview_area: None,
            render_cache: ApprovalRenderCache::default(),
        }
    }

    pub(super) fn content_lines(&mut self, width: usize) -> &[Line<'static>] {
        let width = width.max(1);
        if self.render_cache.width != width {
            self.render_cache.width = width;
            self.render_cache.lines = build_approval_content_lines(&self.content_blocks, width);
        }
        &self.render_cache.lines
    }

    pub(super) fn update_viewport(&mut self, visible_lines: usize, total_lines: usize) {
        self.visible_lines = visible_lines;
        self.total_lines = total_lines;
        self.scroll = self.scroll.min(self.max_scroll());
    }

    fn max_scroll(&self) -> usize {
        self.total_lines.saturating_sub(self.visible_lines)
    }

    pub(super) fn scroll_up(&mut self, lines: usize) {
        self.scroll = self.scroll.saturating_sub(lines);
    }

    pub(super) fn scroll_down(&mut self, lines: usize) {
        self.scroll = (self.scroll + lines).min(self.max_scroll());
    }

    pub(super) fn page_up(&mut self) {
        self.scroll_up(self.visible_lines.saturating_sub(1).max(1));
    }

    pub(super) fn page_down(&mut self) {
        self.scroll_down(self.visible_lines.saturating_sub(1).max(1));
    }

    pub(super) fn scroll_home(&mut self) {
        self.scroll = 0;
    }

    pub(super) fn scroll_end(&mut self) {
        self.scroll = self.max_scroll();
    }
}

pub(super) fn render_approval_overlay(
    frame: &mut Frame<'_>,
    area: Rect,
    overlay: &mut ApprovalOverlay,
) {
    let popup = approval_popup_rect(area);
    frame.render_widget(Clear, popup);
    overlay.preview_area = None;

    let border_color = approval_border_color(&overlay.tool);
    let block = Block::default()
        .title(chat_text("chat.approval.title"))
        .borders(Borders::ALL)
        .border_style(Style::default().fg(border_color));
    let inner = block.inner(popup);
    frame.render_widget(block, popup);

    if inner.width == 0 || inner.height == 0 {
        return;
    }

    let summary_height = overlay.summary.len().clamp(1, 4) as u16;
    let layout = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(2),
            Constraint::Length(summary_height),
            Constraint::Min(6),
            Constraint::Length(1),
        ])
        .split(inner);

    let header = vec![
        Line::from(Span::styled(
            overlay.title.clone(),
            Style::default()
                .fg(border_color)
                .add_modifier(Modifier::BOLD),
        )),
        Line::from(Span::styled(
            chat_format("chat.approval.needs", &[("{tool}", overlay.tool.clone())]),
            Style::default().fg(Color::DarkGray),
        )),
    ];
    frame.render_widget(Paragraph::new(header), layout[0]);

    frame.render_widget(
        Paragraph::new(approval_summary_lines(
            &overlay.summary,
            layout[1].width as usize,
        )),
        layout[1],
    );

    let preview_block = Block::default()
        .title(" Preview ")
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::DarkGray));
    let preview_inner = preview_block.inner(layout[2]);
    frame.render_widget(preview_block, layout[2]);

    if preview_inner.width > 0 && preview_inner.height > 0 {
        let preview_chunks = if preview_inner.width > 2 {
            Layout::default()
                .direction(Direction::Horizontal)
                .constraints([Constraint::Min(1), Constraint::Length(1)])
                .split(preview_inner)
        } else {
            Layout::default()
                .direction(Direction::Horizontal)
                .constraints([Constraint::Min(1)])
                .split(preview_inner)
        };

        let content_area = preview_chunks[0];
        let scrollbar_area = (preview_chunks.len() > 1).then_some(preview_chunks[1]);
        overlay.preview_area = Some(content_area);
        let total_lines = overlay.content_lines(content_area.width as usize).len();
        overlay.update_viewport(content_area.height as usize, total_lines);
        let scroll = overlay.scroll.min(overlay.max_scroll());
        overlay.scroll = scroll;
        let visible_lines = {
            let lines = overlay.content_lines(content_area.width as usize);
            let end = (scroll + content_area.height as usize).min(lines.len());
            lines[scroll..end].to_vec()
        };

        frame.render_widget(Paragraph::new(visible_lines), content_area);

        if let Some(scrollbar_area) = scrollbar_area {
            render_scrollbar(
                frame,
                scrollbar_area,
                overlay.total_lines,
                overlay.visible_lines,
                overlay.scroll,
                Color::DarkGray,
                border_color,
            );
        }
    }

    frame.render_widget(
        Paragraph::new(approval_footer_line(overlay, border_color)),
        layout[3],
    );
}

fn approval_popup_rect(area: Rect) -> Rect {
    let max_width = area.width.saturating_sub(4).max(1);
    let max_height = area.height.saturating_sub(3).max(1);
    let preferred_width = (area.width.saturating_mul(58) / 100).max(52);
    let preferred_height = (area.height.saturating_mul(62) / 100).max(18);
    let width = preferred_width.min(78).min(max_width);
    let height = preferred_height.min(26).min(max_height);
    let x = area.x + area.width.saturating_sub(width);
    let y = area.y + area.height.saturating_sub(height + 1);

    Rect {
        x,
        y,
        width,
        height,
    }
}

fn approval_content(
    tool: &ToolEventData,
) -> (String, Vec<ApprovalSummaryItem>, Vec<ApprovalContentBlock>) {
    match tool.tool.as_str() {
        "generate_script_plugin" => {
            let plugin_name = approval_string_param(tool, "plugin_name")
                .unwrap_or_else(|| "Untitled plugin".to_string());
            let plugin_id =
                approval_string_param(tool, "plugin_id").unwrap_or_else(|| "-".to_string());
            let network = approval_bool_param(tool, "requires_network")
                .map(|value| if value { "On" } else { "Off" })
                .unwrap_or("Off");
            let overwrite = approval_bool_param(tool, "overwrite")
                .map(|value| if value { "Yes" } else { "No" })
                .unwrap_or("No");
            let manifest_json =
                approval_string_param(tool, "manifest_json").unwrap_or_else(|| "{}".to_string());
            let manifest = approval_pretty_json_string(&manifest_json).unwrap_or(manifest_json);
            let main_file = approval_manifest_main_file(&manifest);
            let script_code = approval_string_param(tool, "script_code")
                .unwrap_or_else(|| chat_text("chat.approval.write_text_default"));

            (
                "Create script plugin".to_string(),
                vec![
                    approval_summary_item("Plugin", plugin_name),
                    approval_summary_item("ID", plugin_id),
                    approval_summary_item("Network", network),
                    approval_summary_item("Overwrite", overwrite),
                ],
                vec![
                    ApprovalContentBlock::Code {
                        title: "manifest.json".to_string(),
                        text: manifest,
                        mode: ApprovalCodeMode::Json,
                    },
                    ApprovalContentBlock::Code {
                        title: main_file,
                        text: script_code,
                        mode: ApprovalCodeMode::JavaScript,
                    },
                ],
            )
        }
        "modify_script_plugin" => {
            let plugin_name = approval_string_param(tool, "plugin_name")
                .unwrap_or_else(|| "Unknown plugin".to_string());
            let plugin_id =
                approval_string_param(tool, "plugin_id").unwrap_or_else(|| "-".to_string());
            let touched_files = approval_string_array_param(tool, "touched_files");
            let raw_patch = approval_string_param(tool, "patch")
                .or_else(|| approval_string_param(tool, "patch_preview"))
                .unwrap_or_default();
            let patch_document = approval_patch_document(&raw_patch);
            let (file_count, added, removed) = patch_document
                .as_ref()
                .map(approval_patch_stats)
                .unwrap_or_else(|| approval_diff_stats(&raw_patch));
            let diff_summary = if raw_patch.is_empty() {
                format!("{} file(s)", touched_files.len())
            } else {
                format!(
                    "{} file(s) · +{} -{}",
                    file_count.max(touched_files.len()),
                    added,
                    removed
                )
            };
            let mut content_blocks = Vec::new();
            if patch_document.is_none() && !touched_files.is_empty() {
                content_blocks.push(ApprovalContentBlock::List {
                    title: "Files".to_string(),
                    items: touched_files,
                });
            }
            if let Some(document) = patch_document {
                content_blocks.push(ApprovalContentBlock::Patch {
                    title: "Patch".to_string(),
                    document,
                });
            } else if approval_is_machine_patch(&raw_patch) {
                content_blocks.push(ApprovalContentBlock::Note {
                    title: "Patch".to_string(),
                    text: "Patch preview is temporarily unavailable for this patch shape."
                        .to_string(),
                    tone: MetaTone::Warning,
                });
            } else if !raw_patch.is_empty() {
                content_blocks.push(ApprovalContentBlock::Code {
                    title: "Patch".to_string(),
                    text: raw_patch,
                    mode: ApprovalCodeMode::Diff,
                });
            } else {
                content_blocks.push(ApprovalContentBlock::Note {
                    title: "Patch".to_string(),
                    text: chat_text("chat.approval.generic"),
                    tone: MetaTone::Dim,
                });
            }

            (
                "Review plugin diff".to_string(),
                vec![
                    approval_summary_item("Plugin", plugin_name),
                    approval_summary_item("ID", plugin_id),
                    approval_summary_item("Files", diff_summary),
                ],
                content_blocks,
            )
        }
        "delete_script_plugin" => {
            let plugin_name = approval_string_param(tool, "plugin_name")
                .unwrap_or_else(|| "Unknown plugin".to_string());
            let plugin_id =
                approval_string_param(tool, "plugin_id").unwrap_or_else(|| "-".to_string());
            let plugin_path =
                approval_string_param(tool, "plugin_path").unwrap_or_else(|| "-".to_string());

            (
                "Delete script plugin".to_string(),
                vec![
                    approval_summary_item("Plugin", plugin_name),
                    approval_summary_item("ID", plugin_id),
                ],
                vec![
                    ApprovalContentBlock::Note {
                        title: "Warning".to_string(),
                        text: "This removes the whole plugin directory and cannot be undone."
                            .to_string(),
                        tone: MetaTone::Warning,
                    },
                    ApprovalContentBlock::Code {
                        title: "Path".to_string(),
                        text: plugin_path,
                        mode: ApprovalCodeMode::Plain,
                    },
                ],
            )
        }
        "run_script_transform" => {
            let plugin_name = approval_string_param(tool, "plugin_name")
                .unwrap_or_else(|| "Unknown plugin".to_string());
            let plugin_id =
                approval_string_param(tool, "plugin_id").unwrap_or_else(|| "-".to_string());
            let input_preview = approval_string_param(tool, "input_preview")
                .unwrap_or_else(|| chat_text("chat.approval.write_text_default"));

            (
                "Authorize plugin run".to_string(),
                vec![
                    approval_summary_item("Plugin", plugin_name),
                    approval_summary_item("ID", plugin_id),
                    approval_summary_item("Network", "Required"),
                ],
                vec![ApprovalContentBlock::Code {
                    title: "Input".to_string(),
                    text: input_preview,
                    mode: ApprovalCodeMode::Plain,
                }],
            )
        }
        "generate_smart_rule" => {
            let rule_name = approval_string_param(tool, "rule_name")
                .unwrap_or_else(|| "Untitled rule".to_string());
            let preview = tool
                .parameters
                .get("smart_rule_preview")
                .map(approval_pretty_value)
                .unwrap_or_else(|| approval_pretty_value(&tool.parameters));

            (
                "Create smart rule".to_string(),
                vec![approval_summary_item("Rule", rule_name)],
                vec![ApprovalContentBlock::Code {
                    title: "Preview".to_string(),
                    text: preview,
                    mode: ApprovalCodeMode::Json,
                }],
            )
        }
        "modify_smart_rule" => {
            let rule_name = approval_string_param(tool, "rule_name")
                .unwrap_or_else(|| "Untitled rule".to_string());
            let rule_id = approval_string_param(tool, "rule_id").unwrap_or_else(|| "-".to_string());
            let previous_rule_name =
                approval_string_param(tool, "existing_rule_name").unwrap_or_default();
            let change_summary = approval_string_array_param(tool, "smart_rule_change_summary");
            let preview = tool
                .parameters
                .get("smart_rule_preview")
                .map(approval_pretty_value)
                .unwrap_or_else(|| approval_pretty_value(&tool.parameters));

            let mut content_blocks = Vec::new();
            if !change_summary.is_empty() {
                content_blocks.push(ApprovalContentBlock::List {
                    title: "Changes".to_string(),
                    items: change_summary,
                });
            }
            content_blocks.push(ApprovalContentBlock::Code {
                title: "Preview".to_string(),
                text: preview,
                mode: ApprovalCodeMode::Json,
            });

            let mut summary = vec![
                approval_summary_item("Rule", rule_name.clone()),
                approval_summary_item("ID", rule_id),
            ];
            if !previous_rule_name.is_empty() && previous_rule_name != rule_name {
                summary.push(approval_summary_item("Previous", previous_rule_name));
            }

            ("Modify smart rule".to_string(), summary, content_blocks)
        }
        "delete_smart_rule" => {
            let rule_name = approval_string_param(tool, "rule_name")
                .unwrap_or_else(|| "Untitled rule".to_string());
            let rule_id = approval_string_param(tool, "rule_id").unwrap_or_else(|| "-".to_string());
            let preview = tool
                .parameters
                .get("smart_rule_preview")
                .map(approval_pretty_value)
                .unwrap_or_else(|| approval_pretty_value(&tool.parameters));

            (
                "Delete smart rule".to_string(),
                vec![
                    approval_summary_item("Rule", rule_name),
                    approval_summary_item("ID", rule_id),
                ],
                vec![
                    ApprovalContentBlock::Note {
                        title: "Warning".to_string(),
                        text: "This permanently removes the rule and cannot be undone."
                            .to_string(),
                        tone: MetaTone::Warning,
                    },
                    ApprovalContentBlock::Code {
                        title: "Preview".to_string(),
                        text: preview,
                        mode: ApprovalCodeMode::Json,
                    },
                ],
            )
        }
        "write_clipboard" => {
            let text = approval_string_param(tool, "text")
                .unwrap_or_else(|| chat_text("chat.approval.write_text_default"));

            (
                "Write clipboard text".to_string(),
                vec![approval_summary_item(
                    "Characters",
                    char_count(&text).to_string(),
                )],
                vec![ApprovalContentBlock::Code {
                    title: "Text".to_string(),
                    text,
                    mode: ApprovalCodeMode::Plain,
                }],
            )
        }
        "delete_clipboard" => {
            let item_id = tool
                .parameters
                .get("item_id")
                .and_then(Value::as_i64)
                .map(|value| value.to_string())
                .unwrap_or_else(|| "-".to_string());
            let preview = approval_string_param(tool, "item_text")
                .unwrap_or_else(|| chat_text("chat.approval.delete_default"));

            (
                "Delete clipboard item".to_string(),
                vec![approval_summary_item("Item", item_id)],
                vec![ApprovalContentBlock::Code {
                    title: "Preview".to_string(),
                    text: preview,
                    mode: ApprovalCodeMode::Plain,
                }],
            )
        }
        _ => (
            format!("Approve {}", tool.tool.replace('_', " ")),
            vec![approval_summary_item("Tool", tool.tool.clone())],
            vec![ApprovalContentBlock::Code {
                title: "Parameters".to_string(),
                text: approval_pretty_value(&tool.parameters),
                mode: ApprovalCodeMode::Json,
            }],
        ),
    }
}

fn approval_summary_item(
    label: impl Into<String>,
    value: impl Into<String>,
) -> ApprovalSummaryItem {
    ApprovalSummaryItem {
        label: label.into(),
        value: value.into(),
    }
}

fn approval_summary_lines(summary: &[ApprovalSummaryItem], width: usize) -> Vec<Line<'static>> {
    if summary.is_empty() {
        return vec![Line::from(Span::styled(
            chat_text("chat.approval.generic"),
            Style::default().fg(Color::DarkGray),
        ))];
    }

    summary
        .iter()
        .take(4)
        .map(|item| {
            let label = format!("{}: ", item.label);
            let value = truncate_text(
                &item.value,
                width.saturating_sub(display_width(&label)).max(1),
            );
            Line::from(vec![
                Span::styled(label, Style::default().fg(Color::DarkGray)),
                Span::styled(value, Style::default().add_modifier(Modifier::BOLD)),
            ])
        })
        .collect()
}

fn approval_footer_line(overlay: &ApprovalOverlay, allow_color: Color) -> Line<'static> {
    let scroll_state = if overlay.total_lines > overlay.visible_lines && overlay.visible_lines > 0 {
        format!(
            "{}-{} / {}",
            overlay.scroll + 1,
            (overlay.scroll + overlay.visible_lines).min(overlay.total_lines),
            overlay.total_lines,
        )
    } else {
        format!("{} line(s)", overlay.total_lines.max(1))
    };

    Line::from(vec![
        Span::styled(
            "Y approve",
            Style::default()
                .fg(allow_color)
                .add_modifier(Modifier::BOLD),
        ),
        Span::raw("  "),
        Span::styled(
            "N reject",
            Style::default().fg(Color::Red).add_modifier(Modifier::BOLD),
        ),
        Span::raw("  "),
        Span::styled("Up/Down scroll", Style::default().fg(Color::DarkGray)),
        Span::raw("  "),
        Span::styled(scroll_state, Style::default().fg(Color::DarkGray)),
    ])
}

fn approval_border_color(tool: &str) -> Color {
    match tool {
        "delete_clipboard" | "delete_script_plugin" | "delete_smart_rule" => Color::Red,
        "modify_script_plugin" | "modify_smart_rule" => Color::Yellow,
        "generate_script_plugin" | "generate_smart_rule" => Color::Cyan,
        "write_clipboard" => Color::Green,
        _ => Color::LightYellow,
    }
}

fn build_approval_content_lines(
    content_blocks: &[ApprovalContentBlock],
    width: usize,
) -> Vec<Line<'static>> {
    let mut lines = Vec::new();

    for (index, block) in content_blocks.iter().enumerate() {
        if index > 0 {
            lines.push(Line::from(""));
        }

        match block {
            ApprovalContentBlock::Note { title, text, tone } => {
                push_approval_block_title(&mut lines, title);
                push_wrapped_lines(&mut lines, width, "  ", "  ", text, tone.style());
            }
            ApprovalContentBlock::List { title, items } => {
                push_approval_block_title(&mut lines, title);
                for item in items {
                    push_wrapped_lines(
                        &mut lines,
                        width,
                        "  - ",
                        "    ",
                        item,
                        Style::default().fg(Color::Gray),
                    );
                }
            }
            ApprovalContentBlock::Code { title, text, mode } => {
                push_approval_block_title(&mut lines, title);
                if text.trim().is_empty() {
                    lines.push(Line::from(Span::styled(
                        "  (empty)",
                        Style::default().fg(Color::DarkGray),
                    )));
                    continue;
                }

                push_approval_code_lines(&mut lines, width, text, *mode);
            }
            ApprovalContentBlock::Patch { title, document } => {
                push_approval_block_title(&mut lines, title);
                push_approval_patch_lines(&mut lines, width, document);
            }
        }
    }

    if lines.is_empty() {
        lines.push(Line::from(Span::styled(
            chat_text("chat.approval.generic"),
            Style::default().fg(Color::DarkGray),
        )));
    }

    lines
}

fn push_approval_block_title(lines: &mut Vec<Line<'static>>, title: &str) {
    lines.push(Line::from(vec![Span::styled(
        format!(" {} ", title),
        Style::default()
            .fg(Color::White)
            .bg(Color::DarkGray)
            .add_modifier(Modifier::BOLD),
    )]));
}

fn push_approval_patch_lines(
    lines: &mut Vec<Line<'static>>,
    width: usize,
    document: &ApprovalPatchDocument,
) {
    for (file_index, file) in document.files.iter().enumerate() {
        if file_index > 0 {
            lines.push(Line::from(""));
        }

        let action = match file.action {
            ApprovalPatchFileAction::Update => "update",
            ApprovalPatchFileAction::Add => "add",
            ApprovalPatchFileAction::Delete => "delete",
            ApprovalPatchFileAction::Move => "move",
        };
        let (added, removed) = approval_patch_file_stats(file);
        let path_label = file
            .target_path
            .as_ref()
            .map(|target| format!("{} -> {}", file.path, target))
            .unwrap_or_else(|| file.path.clone());
        lines.push(Line::from(vec![
            Span::raw("  ".to_string()),
            Span::styled(
                path_label,
                Style::default()
                    .fg(Color::Cyan)
                    .add_modifier(Modifier::BOLD),
            ),
            Span::styled(
                format!("  [{}]  +{} -{}", action, added, removed),
                Style::default().fg(Color::DarkGray),
            ),
        ]));

        for hunk in &file.hunks {
            if let Some(header) = approval_patch_hunk_header(&hunk.header) {
                lines.push(Line::from(vec![
                    Span::raw("  ".to_string()),
                    Span::styled(
                        header,
                        Style::default()
                            .fg(Color::Yellow)
                            .add_modifier(Modifier::BOLD),
                    ),
                ]));
            }

            for diff_line in &hunk.lines {
                match diff_line {
                    ApprovalPatchLine::Context(text) => {
                        push_wrapped_lines(
                            lines,
                            width,
                            "   ",
                            "   ",
                            text,
                            Style::default().fg(Color::Gray),
                        );
                    }
                    ApprovalPatchLine::Add(text) => {
                        push_wrapped_lines(
                            lines,
                            width,
                            "  +",
                            "   ",
                            text,
                            Style::default().fg(Color::Green),
                        );
                    }
                    ApprovalPatchLine::Remove(text) => {
                        push_wrapped_lines(
                            lines,
                            width,
                            "  -",
                            "   ",
                            text,
                            Style::default().fg(Color::Red),
                        );
                    }
                    ApprovalPatchLine::Note(text) => {
                        push_wrapped_lines(
                            lines,
                            width,
                            "  ! ",
                            "    ",
                            text,
                            Style::default().fg(Color::DarkGray),
                        );
                    }
                }
            }
        }
    }
}

fn approval_patch_hunk_header(header: &str) -> Option<String> {
    let trimmed = header.trim();
    if trimmed == "@@" {
        None
    } else {
        Some(trimmed.to_string())
    }
}

fn approval_patch_file_stats(file: &ApprovalPatchFile) -> (usize, usize) {
    let mut added = 0usize;
    let mut removed = 0usize;

    for hunk in &file.hunks {
        for line in &hunk.lines {
            match line {
                ApprovalPatchLine::Add(_) => added += 1,
                ApprovalPatchLine::Remove(_) => removed += 1,
                ApprovalPatchLine::Context(_) | ApprovalPatchLine::Note(_) => {}
            }
        }
    }

    (added, removed)
}

fn push_approval_code_lines(
    lines: &mut Vec<Line<'static>>,
    width: usize,
    text: &str,
    mode: ApprovalCodeMode,
) {
    for raw_line in text.lines() {
        if raw_line.is_empty() {
            lines.push(Line::from(""));
            continue;
        }

        let highlighted = matches!(mode, ApprovalCodeMode::Json | ApprovalCodeMode::JavaScript)
            && display_width(raw_line).saturating_add(2) <= width;
        if highlighted {
            lines.push(approval_highlighted_code_line(mode, raw_line));
        } else {
            push_wrapped_lines(
                lines,
                width,
                "  ",
                "  ",
                raw_line,
                approval_code_fallback_style(mode, raw_line),
            );
        }
    }
}

fn approval_code_fallback_style(mode: ApprovalCodeMode, line: &str) -> Style {
    match mode {
        ApprovalCodeMode::Plain | ApprovalCodeMode::Json | ApprovalCodeMode::JavaScript => {
            Style::default().fg(Color::Gray)
        }
        ApprovalCodeMode::Diff => {
            if line.starts_with("@@") {
                Style::default()
                    .fg(Color::Yellow)
                    .add_modifier(Modifier::BOLD)
            } else if line.starts_with("diff --git")
                || line.starts_with("index ")
                || line.starts_with("--- ")
                || line.starts_with("+++ ")
            {
                Style::default().fg(Color::Cyan)
            } else if line.starts_with('+') && !line.starts_with("+++") {
                Style::default().fg(Color::Green)
            } else if line.starts_with('-') && !line.starts_with("---") {
                Style::default().fg(Color::Red)
            } else {
                Style::default().fg(Color::Gray)
            }
        }
    }
}

fn approval_highlighted_code_line(mode: ApprovalCodeMode, line: &str) -> Line<'static> {
    match mode {
        ApprovalCodeMode::Json => approval_highlight_json_line(line),
        ApprovalCodeMode::JavaScript => approval_highlight_javascript_line(line),
        _ => Line::from(vec![
            Span::raw("  ".to_string()),
            Span::styled(line.to_string(), approval_code_fallback_style(mode, line)),
        ]),
    }
}

fn approval_highlight_json_line(line: &str) -> Line<'static> {
    let chars: Vec<char> = line.chars().collect();
    let mut spans = vec![Span::raw("  ".to_string())];
    let mut index = 0usize;

    while index < chars.len() {
        let ch = chars[index];
        if ch.is_whitespace() {
            let start = index;
            while index < chars.len() && chars[index].is_whitespace() {
                index += 1;
            }
            spans.push(Span::raw(chars[start..index].iter().collect::<String>()));
            continue;
        }

        if matches!(ch, '{' | '}' | '[' | ']' | ':' | ',') {
            spans.push(Span::styled(
                ch.to_string(),
                Style::default().fg(Color::DarkGray),
            ));
            index += 1;
            continue;
        }

        if ch == '"' {
            let start = index;
            index += 1;
            let mut escaped = false;
            while index < chars.len() {
                let current = chars[index];
                index += 1;
                if escaped {
                    escaped = false;
                    continue;
                }
                if current == '\\' {
                    escaped = true;
                    continue;
                }
                if current == '"' {
                    break;
                }
            }

            let token = chars[start..index].iter().collect::<String>();
            let mut lookahead = index;
            while lookahead < chars.len() && chars[lookahead].is_whitespace() {
                lookahead += 1;
            }
            let style = if lookahead < chars.len() && chars[lookahead] == ':' {
                Style::default()
                    .fg(Color::Cyan)
                    .add_modifier(Modifier::BOLD)
            } else {
                Style::default().fg(Color::Green)
            };
            spans.push(Span::styled(token, style));
            continue;
        }

        let start = index;
        while index < chars.len()
            && !chars[index].is_whitespace()
            && !json_is_delimiter(chars[index])
        {
            index += 1;
        }
        let token = chars[start..index].iter().collect::<String>();
        let style = match token.as_str() {
            "true" | "false" | "null" => Style::default().fg(Color::Yellow),
            _ if token
                .chars()
                .all(|value| value.is_ascii_digit() || matches!(value, '.' | '-')) =>
            {
                Style::default().fg(Color::Yellow)
            }
            _ => Style::default().fg(Color::Gray),
        };
        spans.push(Span::styled(token, style));
    }

    Line::from(spans)
}

fn approval_highlight_javascript_line(line: &str) -> Line<'static> {
    let chars: Vec<char> = line.chars().collect();
    let mut spans = vec![Span::raw("  ".to_string())];
    let mut index = 0usize;

    while index < chars.len() {
        let ch = chars[index];
        if ch.is_whitespace() {
            let start = index;
            while index < chars.len() && chars[index].is_whitespace() {
                index += 1;
            }
            spans.push(Span::raw(chars[start..index].iter().collect::<String>()));
            continue;
        }

        if ch == '/' && index + 1 < chars.len() && chars[index + 1] == '/' {
            spans.push(Span::styled(
                chars[index..].iter().collect::<String>(),
                Style::default().fg(Color::DarkGray),
            ));
            break;
        }

        if matches!(ch, '\'' | '"' | '`') {
            let quote = ch;
            let start = index;
            index += 1;
            let mut escaped = false;
            while index < chars.len() {
                let current = chars[index];
                index += 1;
                if escaped {
                    escaped = false;
                    continue;
                }
                if current == '\\' {
                    escaped = true;
                    continue;
                }
                if current == quote {
                    break;
                }
            }
            spans.push(Span::styled(
                chars[start..index].iter().collect::<String>(),
                Style::default().fg(Color::Green),
            ));
            continue;
        }

        if js_is_identifier_start(ch) {
            let start = index;
            index += 1;
            while index < chars.len() && js_is_identifier_continue(chars[index]) {
                index += 1;
            }
            let token = chars[start..index].iter().collect::<String>();
            let style = if matches!(
                token.as_str(),
                "async"
                    | "await"
                    | "const"
                    | "default"
                    | "else"
                    | "export"
                    | "false"
                    | "function"
                    | "if"
                    | "let"
                    | "null"
                    | "return"
                    | "true"
                    | "var"
            ) {
                Style::default()
                    .fg(Color::Cyan)
                    .add_modifier(Modifier::BOLD)
            } else {
                Style::default().fg(Color::Gray)
            };
            spans.push(Span::styled(token, style));
            continue;
        }

        if ch.is_ascii_digit() {
            let start = index;
            index += 1;
            while index < chars.len()
                && (chars[index].is_ascii_digit() || matches!(chars[index], '.' | '_'))
            {
                index += 1;
            }
            spans.push(Span::styled(
                chars[start..index].iter().collect::<String>(),
                Style::default().fg(Color::Yellow),
            ));
            continue;
        }

        spans.push(Span::styled(
            ch.to_string(),
            Style::default().fg(Color::DarkGray),
        ));
        index += 1;
    }

    Line::from(spans)
}

fn json_is_delimiter(ch: char) -> bool {
    matches!(ch, '{' | '}' | '[' | ']' | ':' | ',')
}

fn js_is_identifier_start(ch: char) -> bool {
    ch == '_' || ch == '$' || ch.is_ascii_alphabetic()
}

fn js_is_identifier_continue(ch: char) -> bool {
    js_is_identifier_start(ch) || ch.is_ascii_digit()
}

fn approval_string_param(tool: &ToolEventData, key: &str) -> Option<String> {
    tool.parameters
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
}

fn approval_bool_param(tool: &ToolEventData, key: &str) -> Option<bool> {
    match tool.parameters.get(key) {
        Some(Value::Bool(value)) => Some(*value),
        Some(Value::Number(value)) => value.as_i64().map(|number| number != 0),
        Some(Value::String(value)) => {
            let normalized = value.trim().to_ascii_lowercase();
            match normalized.as_str() {
                "true" | "1" | "yes" | "on" => Some(true),
                "false" | "0" | "no" | "off" => Some(false),
                _ => None,
            }
        }
        _ => None,
    }
}

fn approval_string_array_param(tool: &ToolEventData, key: &str) -> Vec<String> {
    tool.parameters
        .get(key)
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(|value| value.as_str())
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
        .collect()
}

fn approval_pretty_json_string(raw: &str) -> Option<String> {
    serde_json::from_str::<Value>(raw)
        .ok()
        .and_then(|value| serde_json::to_string_pretty(&value).ok())
}

fn approval_pretty_value(value: &Value) -> String {
    serde_json::to_string_pretty(value).unwrap_or_else(|_| chat_text("chat.approval.generic"))
}

fn approval_manifest_main_file(manifest_json: &str) -> String {
    approval_pretty_json_string(manifest_json)
        .and_then(|json| serde_json::from_str::<Value>(&json).ok())
        .and_then(|value| {
            value
                .get("main")
                .and_then(Value::as_str)
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(str::to_owned)
        })
        .unwrap_or_else(|| "index.js".to_string())
}

fn approval_diff_stats(patch: &str) -> (usize, usize, usize) {
    let mut files = 0usize;
    let mut added = 0usize;
    let mut removed = 0usize;

    for line in patch.lines() {
        if line.starts_with("diff --git ") {
            files += 1;
        }
        if line.starts_with('+') && !line.starts_with("+++") {
            added += 1;
        }
        if line.starts_with('-') && !line.starts_with("---") {
            removed += 1;
        }
    }

    if files == 0 && !patch.trim().is_empty() {
        files = 1;
    }

    (files, added, removed)
}

fn approval_is_machine_patch(raw_patch: &str) -> bool {
    raw_patch
        .lines()
        .find(|line| !line.trim().is_empty())
        .is_some_and(|line| line.trim() == "*** Begin Patch")
}

fn approval_patch_document(raw_patch: &str) -> Option<ApprovalPatchDocument> {
    let normalized = raw_patch.replace("\r\n", "\n");
    let mut lines: Vec<&str> = normalized.lines().collect();
    while lines.first().is_some_and(|line| line.trim().is_empty()) {
        lines.remove(0);
    }
    while lines.last().is_some_and(|line| line.trim().is_empty()) {
        lines.pop();
    }
    if lines.first()?.trim() != "*** Begin Patch" || lines.last()?.trim() != "*** End Patch" {
        return None;
    }

    let mut files = Vec::new();
    let mut index = 1usize;
    let end_index = lines.len().saturating_sub(1);

    while index < end_index {
        let trimmed = lines[index].trim();
        if trimmed.is_empty() {
            index += 1;
            continue;
        }

        if let Some(path) = trimmed.strip_prefix("*** Update File: ") {
            let path = path.trim().to_string();
            index += 1;
            let mut target_path = None;
            if index < end_index {
                let move_trimmed = lines[index].trim();
                if let Some(path) = move_trimmed.strip_prefix("*** Move to: ") {
                    target_path = Some(path.trim().to_string());
                    index += 1;
                }
            }
            let mut hunks = Vec::new();

            while index < end_index {
                let current = lines[index];
                let current_trimmed = current.trim();
                if current_trimmed.starts_with("*** ") {
                    break;
                }
                if current_trimmed.is_empty() {
                    index += 1;
                    continue;
                }

                let header = if current_trimmed == "@@" || current_trimmed.starts_with("@@ ") {
                    index += 1;
                    current_trimmed.to_string()
                } else {
                    "@@".to_string()
                };

                let mut diff_lines = Vec::new();
                while index < end_index {
                    let diff_line = lines[index];
                    let diff_trimmed = diff_line.trim();
                    if matches!(diff_trimmed, "*** End of File") {
                        index += 1;
                        break;
                    }
                    if diff_line.starts_with("*** ")
                        || diff_trimmed == "@@"
                        || diff_trimmed.starts_with("@@ ")
                    {
                        break;
                    }
                    if diff_line == "\\ No newline at end of file" {
                        index += 1;
                        continue;
                    }
                    if diff_line.is_empty() {
                        diff_lines.push(ApprovalPatchLine::Context(String::new()));
                        index += 1;
                        continue;
                    }

                    let marker = diff_line.chars().next()?;
                    let payload = diff_line[marker.len_utf8()..].to_string();
                    let parsed = match marker {
                        ' ' => ApprovalPatchLine::Context(payload),
                        '+' => ApprovalPatchLine::Add(payload),
                        '-' => ApprovalPatchLine::Remove(payload),
                        _ => return None,
                    };
                    diff_lines.push(parsed);
                    index += 1;
                }

                if diff_lines.is_empty() {
                    return None;
                }

                hunks.push(ApprovalPatchHunk {
                    header,
                    lines: diff_lines,
                });
            }

            if hunks.is_empty() {
                return None;
            }

            files.push(ApprovalPatchFile {
                path,
                action: if target_path.is_some() {
                    ApprovalPatchFileAction::Move
                } else {
                    ApprovalPatchFileAction::Update
                },
                target_path,
                hunks,
            });
            continue;
        }

        if let Some(path) = trimmed.strip_prefix("*** Add File: ") {
            let path = path.trim().to_string();
            index += 1;
            let mut diff_lines = Vec::new();
            while index < end_index {
                let current = lines[index];
                if current.starts_with("*** ") {
                    break;
                }
                if !current.starts_with('+') {
                    return None;
                }
                diff_lines.push(ApprovalPatchLine::Add(current[1..].to_string()));
                index += 1;
            }

            if diff_lines.is_empty() {
                return None;
            }

            files.push(ApprovalPatchFile {
                path,
                action: ApprovalPatchFileAction::Add,
                target_path: None,
                hunks: vec![ApprovalPatchHunk {
                    header: "@@".to_string(),
                    lines: diff_lines,
                }],
            });
            continue;
        }

        if let Some(path) = trimmed.strip_prefix("*** Delete File: ") {
            files.push(ApprovalPatchFile {
                path: path.trim().to_string(),
                action: ApprovalPatchFileAction::Delete,
                target_path: None,
                hunks: vec![ApprovalPatchHunk {
                    header: "@@".to_string(),
                    lines: vec![ApprovalPatchLine::Note("file deleted".to_string())],
                }],
            });
            index += 1;
            continue;
        }

        return None;
    }

    (!files.is_empty()).then_some(ApprovalPatchDocument { files })
}

fn approval_patch_stats(document: &ApprovalPatchDocument) -> (usize, usize, usize) {
    let mut added = 0usize;
    let mut removed = 0usize;

    for file in &document.files {
        for hunk in &file.hunks {
            for line in &hunk.lines {
                match line {
                    ApprovalPatchLine::Add(_) => added += 1,
                    ApprovalPatchLine::Remove(_) => removed += 1,
                    ApprovalPatchLine::Context(_) | ApprovalPatchLine::Note(_) => {}
                }
            }
        }
    }

    (document.files.len(), added, removed)
}

#[cfg(target_os = "macos")]
mod approval_input {
    use std::ffi::{c_void, CStr};
    use std::ptr;

    use core_foundation_sys::array::{CFArrayGetCount, CFArrayGetValueAtIndex, CFArrayRef};
    use core_foundation_sys::base::{Boolean, CFRelease, CFRetain, CFTypeRef};
    use core_foundation_sys::dictionary::CFDictionaryRef;
    use core_foundation_sys::string::{
        kCFStringEncodingUTF8, CFStringGetCString, CFStringGetLength,
        CFStringGetMaximumSizeForEncoding, CFStringRef,
    };

    const APPROVAL_INPUT_SOURCE_IDS: &[&str] =
        &["com.apple.keylayout.ABC", "com.apple.keylayout.US"];

    type TISInputSourceRef = *const c_void;
    type OSStatus = i32;

    #[link(name = "Carbon", kind = "framework")]
    unsafe extern "C" {
        static kTISPropertyInputSourceID: CFStringRef;
        fn TISCopyCurrentASCIICapableKeyboardLayoutInputSource() -> TISInputSourceRef;
        fn TISCopyCurrentKeyboardInputSource() -> TISInputSourceRef;
        fn TISCreateInputSourceList(
            properties: CFDictionaryRef,
            include_all_installed: Boolean,
        ) -> CFArrayRef;
        fn TISGetInputSourceProperty(
            input_source: TISInputSourceRef,
            property_key: CFStringRef,
        ) -> CFTypeRef;
        fn TISSelectInputSource(input_source: TISInputSourceRef) -> OSStatus;
    }

    #[derive(Default)]
    pub struct ApprovalInputGuard {
        previous_source: Option<OwnedInputSource>,
    }

    impl ApprovalInputGuard {
        pub fn activate(&mut self) {
            if self.previous_source.is_some() {
                return;
            }

            let Some(current_source) = OwnedInputSource::current() else {
                return;
            };

            if current_source.matches_any(APPROVAL_INPUT_SOURCE_IDS) {
                return;
            }

            let Some(target_source) = OwnedInputSource::current_ascii_capable()
                .or_else(|| find_input_source(APPROVAL_INPUT_SOURCE_IDS))
            else {
                return;
            };

            if target_source.matches_pointer(current_source.as_ptr()) {
                return;
            }

            if target_source.select() {
                self.previous_source = Some(current_source);
            }
        }

        pub fn deactivate(&mut self) {
            let Some(previous_source) = self.previous_source.take() else {
                return;
            };

            let _ = previous_source.select();
        }
    }

    impl Drop for ApprovalInputGuard {
        fn drop(&mut self) {
            self.deactivate();
        }
    }

    struct OwnedInputSource {
        source: TISInputSourceRef,
    }

    impl OwnedInputSource {
        fn current() -> Option<Self> {
            let source = unsafe { TISCopyCurrentKeyboardInputSource() };
            (!source.is_null()).then_some(Self { source })
        }

        fn current_ascii_capable() -> Option<Self> {
            let source = unsafe { TISCopyCurrentASCIICapableKeyboardLayoutInputSource() };
            (!source.is_null()).then_some(Self { source })
        }

        fn select(&self) -> bool {
            unsafe { TISSelectInputSource(self.source) == 0 }
        }

        fn id(&self) -> Option<String> {
            input_source_id(self.source)
        }

        fn matches_any(&self, expected_ids: &[&str]) -> bool {
            self.id()
                .as_deref()
                .is_some_and(|id| expected_ids.iter().any(|candidate| *candidate == id))
        }

        fn matches_pointer(&self, other: TISInputSourceRef) -> bool {
            self.source == other
        }

        fn as_ptr(&self) -> TISInputSourceRef {
            self.source
        }

        unsafe fn retained(source: TISInputSourceRef) -> Option<Self> {
            if source.is_null() {
                return None;
            }

            unsafe { CFRetain(source as CFTypeRef) };
            Some(Self { source })
        }
    }

    impl Drop for OwnedInputSource {
        fn drop(&mut self) {
            unsafe { CFRelease(self.source as CFTypeRef) };
        }
    }

    struct OwnedInputSourceList {
        list: CFArrayRef,
    }

    impl OwnedInputSourceList {
        fn all() -> Option<Self> {
            let list = unsafe { TISCreateInputSourceList(ptr::null(), 0 as Boolean) };
            (!list.is_null()).then_some(Self { list })
        }

        fn len(&self) -> isize {
            unsafe { CFArrayGetCount(self.list) }
        }

        fn get(&self, index: isize) -> Option<OwnedInputSource> {
            let source = unsafe { CFArrayGetValueAtIndex(self.list, index) as TISInputSourceRef };
            unsafe { OwnedInputSource::retained(source) }
        }
    }

    impl Drop for OwnedInputSourceList {
        fn drop(&mut self) {
            unsafe { CFRelease(self.list as CFTypeRef) };
        }
    }

    fn find_input_source(expected_ids: &[&str]) -> Option<OwnedInputSource> {
        let sources = OwnedInputSourceList::all()?;
        for index in 0..sources.len() {
            let Some(source) = sources.get(index) else {
                continue;
            };

            if source.matches_any(expected_ids) {
                return Some(source);
            }
        }

        None
    }

    fn input_source_id(source: TISInputSourceRef) -> Option<String> {
        let value = unsafe { TISGetInputSourceProperty(source, kTISPropertyInputSourceID) };
        cf_string_to_string(value as CFStringRef)
    }

    fn cf_string_to_string(value: CFStringRef) -> Option<String> {
        if value.is_null() {
            return None;
        }

        let length = unsafe { CFStringGetLength(value) };
        let capacity = (unsafe { CFStringGetMaximumSizeForEncoding(length, kCFStringEncodingUTF8) }
            + 1)
        .max(1) as usize;
        let mut buffer = vec![0i8; capacity];
        let copied = unsafe {
            CFStringGetCString(
                value,
                buffer.as_mut_ptr(),
                capacity as isize,
                kCFStringEncodingUTF8,
            ) != 0
        };
        if !copied {
            return None;
        }

        unsafe { CStr::from_ptr(buffer.as_ptr()) }
            .to_str()
            .ok()
            .map(str::to_owned)
    }
}

#[cfg(not(target_os = "macos"))]
mod approval_input {
    #[derive(Default)]
    pub struct ApprovalInputGuard;

    impl ApprovalInputGuard {
        pub fn activate(&mut self) {}

        pub fn deactivate(&mut self) {}
    }
}