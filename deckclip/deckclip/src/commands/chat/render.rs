use super::approval::render_approval_overlay;
use super::*;

pub(super) fn render(frame: &mut Frame<'_>, app: &mut ChatApp) {
    let area = frame.area();
    app.clear_popup_hitboxes();
    let input_height = input_panel_height(app, area.width);
    let layout = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(4),
            Constraint::Min(8),
            Constraint::Length(input_height),
            Constraint::Length(1),
        ])
        .split(area);

    render_header(frame, layout[0], app);
    render_body(frame, layout[1], app);
    render_input(frame, layout[2], app);
    render_footer(frame, layout[3], app);

    match &mut app.overlay {
        OverlayState::Approval(overlay) => render_approval_overlay(frame, area, overlay),
        OverlayState::History(overlay) => {
            render_history_overlay(frame, area, overlay, &mut app.history_hitboxes)
        }
        OverlayState::ModelEditor(overlay) => render_model_overlay(frame, area, overlay),
        OverlayState::None => render_slash_popup(frame, layout[2], app),
    }
}

fn render_header(frame: &mut Frame<'_>, area: Rect, app: &ChatApp) {
    let block = Block::default()
        .title(" Deck AI ")
        .borders(Borders::ALL)
        .border_style(app.status_tone().style());
    let inner = block.inner(area);
    frame.render_widget(block, area);

    let rows = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Length(1), Constraint::Length(1)])
        .split(inner);

    let account = app
        .account
        .clone()
        .unwrap_or_else(|| chat_text("chat.header.account_hidden"));
    let usage = app
        .context_usage
        .as_ref()
        .map(|value| {
            chat_format(
                "chat.header.context_usage",
                &[("{usage}", value.usage_percent_text.clone())],
            )
        })
        .unwrap_or_else(|| chat_text("chat.header.context_usage_none"));
    let transcript_mode = if app.auto_scroll {
        chat_text("chat.header.mode.following")
    } else {
        chat_text("chat.header.mode.reviewing")
    };
    let left_title = format!("Deck AI · {}", app.conversation_title);
    let left_meta = format!("{} / {} · {}", app.provider, app.model, account);
    let header_right = vec![
        Span::styled(
            format!(" {} ", app.execution_mode_label()),
            app.execution_mode_badge_style(),
        ),
        Span::raw(" "),
        Span::styled(
            app.status_text(),
            app.status_tone().style().add_modifier(Modifier::BOLD),
        ),
    ];

    frame.render_widget(
        Paragraph::new(spaced_line_with_right_spans(
            &left_title,
            Style::default().add_modifier(Modifier::BOLD),
            header_right,
            rows[0].width as usize,
        )),
        rows[0],
    );

    frame.render_widget(
        Paragraph::new(spaced_line(
            &left_meta,
            Style::default().fg(Color::Gray),
            &format!("{} · {}", usage, transcript_mode),
            Style::default().fg(Color::DarkGray),
            rows[1].width as usize,
        )),
        rows[1],
    );
}

#[allow(clippy::if_same_then_else)]
fn render_body(frame: &mut Frame<'_>, area: Rect, app: &mut ChatApp) {
    let title = if app.auto_scroll {
        chat_text("chat.body.title.following")
    } else {
        chat_text("chat.body.title.reviewing")
    };
    let block = Block::default().title(title).borders(Borders::ALL);
    frame.render_widget(block.clone(), area);
    let inner = block.inner(area);
    if inner.width == 0 || inner.height == 0 {
        app.update_body_scrollbar_state(None, 0, 0);
        return;
    }

    let chunks = if inner.width > 2 {
        Layout::default()
            .direction(Direction::Horizontal)
            .constraints([
                Constraint::Min(1),
                Constraint::Length(1),
                Constraint::Length(1),
            ])
            .split(inner)
    } else if inner.width > 1 {
        Layout::default()
            .direction(Direction::Horizontal)
            .constraints([Constraint::Min(1), Constraint::Length(1)])
            .split(inner)
    } else {
        Layout::default()
            .direction(Direction::Horizontal)
            .constraints([Constraint::Min(1)])
            .split(inner)
    };

    let content_area = chunks[0];
    let scrollbar_area = if chunks.len() > 2 {
        Some(chunks[2])
    } else if chunks.len() > 1 {
        Some(chunks[1])
    } else {
        None
    };
    let total_lines = app.transcript_lines(content_area.width as usize).len();
    let max_scroll = total_lines.saturating_sub(content_area.height as usize);
    if app.auto_scroll {
        app.scroll = max_scroll;
    } else if app.scroll > max_scroll {
        app.scroll = max_scroll;
    }

    if !app.auto_scroll && app.scroll >= max_scroll {
        app.auto_scroll = true;
    }

    app.update_body_scrollbar_state(scrollbar_area, content_area.height as usize, total_lines);
    let visible_lines = transcript_view_lines(
        app,
        content_area.width as usize,
        content_area.height as usize,
    );
    let paragraph = Paragraph::new(visible_lines);
    frame.render_widget(paragraph, content_area);

    if let Some(scrollbar_area) = scrollbar_area {
        render_scrollbar(
            frame,
            scrollbar_area,
            total_lines,
            content_area.height as usize,
            app.scroll,
            Color::DarkGray,
            Color::Cyan,
        );
    }
}

fn render_input(frame: &mut Frame<'_>, area: Rect, app: &mut ChatApp) {
    let block = Block::default().borders(Borders::ALL);
    frame.render_widget(block.clone(), area);
    let inner = block.inner(area);
    if inner.width == 0 || inner.height == 0 {
        app.input_text_area = None;
        return;
    }

    let attachment_height =
        pending_attachment_preview_height(inner.width, app.pending_attachment_count());
    let pending_paste_height =
        pending_attachment_preview_height(inner.width, app.pending_paste_count());
    let sections = if attachment_height > 0 && pending_paste_height > 0 {
        Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(attachment_height),
                Constraint::Length(pending_paste_height),
                Constraint::Min(1),
            ])
            .split(inner)
    } else if attachment_height > 0 {
        Layout::default()
            .direction(Direction::Vertical)
            .constraints([Constraint::Length(attachment_height), Constraint::Min(1)])
            .split(inner)
    } else if pending_paste_height > 0 {
        Layout::default()
            .direction(Direction::Vertical)
            .constraints([Constraint::Length(pending_paste_height), Constraint::Min(1)])
            .split(inner)
    } else {
        Layout::default()
            .direction(Direction::Vertical)
            .constraints([Constraint::Min(1)])
            .split(inner)
    };

    let mut section_index = 0;
    if attachment_height > 0 {
        render_pending_attachments(frame, sections[section_index], app.pending_attachments());
        section_index += 1;
    }
    if pending_paste_height > 0 {
        render_pending_pastes(frame, sections[section_index], app.pending_pastes());
        section_index += 1;
    }

    let input_row = sections.get(section_index).copied().unwrap_or(inner);
    if input_row.width == 0 || input_row.height == 0 {
        app.input_text_area = None;
        return;
    }

    let row_sections = if input_row.width > 2 {
        Layout::default()
            .direction(Direction::Horizontal)
            .constraints([Constraint::Length(2), Constraint::Min(1)])
            .split(input_row)
    } else {
        Layout::default()
            .direction(Direction::Horizontal)
            .constraints([Constraint::Min(1)])
            .split(input_row)
    };

    let gutter_area = row_sections[0];
    let text_area = if row_sections.len() > 1 {
        row_sections[1]
    } else {
        row_sections[0]
    };
    if text_area.width == 0 || text_area.height == 0 {
        app.input_text_area = None;
        return;
    }
    app.update_input_text_area(text_area);
    let viewport = input_viewport(
        &app.input,
        app.input_cursor,
        text_area.width as usize,
        text_area.height as usize,
    );

    let prompt_color = if app.slash_query().is_some() {
        Color::Yellow
    } else {
        Color::Green
    };

    if row_sections.len() > 1 {
        let gutter_lines: Vec<Line<'_>> = (0..text_area.height)
            .map(|row| {
                let symbol = if row == 0 { ">" } else { "│" };
                let style = if row == 0 {
                    Style::default()
                        .fg(prompt_color)
                        .add_modifier(Modifier::BOLD)
                } else {
                    Style::default().fg(Color::DarkGray)
                };
                Line::from(Span::styled(symbol, style))
            })
            .collect();
        frame.render_widget(Paragraph::new(gutter_lines), gutter_area);
    }

    let text_lines: Vec<Line<'_>> = if app.input.is_empty() {
        let mut lines = vec![Line::from(Span::styled(
            chat_text("chat.input.placeholder"),
            Style::default().fg(Color::DarkGray),
        ))];
        while lines.len() < text_area.height as usize {
            lines.push(Line::from(""));
        }
        lines
    } else {
        viewport
            .visible_lines
            .iter()
            .map(|line| Line::from(Span::raw(line.clone())))
            .collect()
    };
    frame.render_widget(Paragraph::new(text_lines), text_area);

    if matches!(app.overlay, OverlayState::None) {
        frame.set_cursor_position((
            text_area.x + viewport.cursor_col as u16,
            text_area.y + viewport.cursor_row as u16,
        ));
    }
}

fn render_footer(frame: &mut Frame<'_>, area: Rect, app: &ChatApp) {
    let default_footer = if app.slash_query().is_some() {
        chat_text("chat.footer.default.slash")
    } else if app.auto_scroll {
        chat_text("chat.footer.default.following")
    } else {
        chat_text("chat.footer.default.reviewing")
    };
    let footer_message = match app.footer_tag {
        Some(FooterTag::QuitHint(_)) if !app.quit_hint_active() => None,
        Some(FooterTag::SlashSelected) if app.slash_query().is_none() => None,
        _ => app.footer_message.clone(),
    };
    let (text, tone) = footer_message.unwrap_or((default_footer, MetaTone::Dim));
    let line = Line::from(Span::styled(text, tone.style()));
    frame.render_widget(Paragraph::new(line), area);
}

fn render_model_overlay(frame: &mut Frame<'_>, area: Rect, overlay: &ModelEditorOverlay) {
    let popup = centered_rect(68, 34, area);
    frame.render_widget(Clear, popup);

    let block = Block::default()
        .title(chat_text("chat.model.title"))
        .borders(Borders::ALL)
        .border_style(Style::default().fg(Color::Cyan));
    let inner = block.inner(popup);
    frame.render_widget(block, popup);

    if inner.width == 0 || inner.height == 0 {
        return;
    }

    let layout = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(1),
            Constraint::Length(1),
            Constraint::Length(1),
            Constraint::Length(3),
            Constraint::Length(1),
            Constraint::Min(1),
        ])
        .split(inner);

    let provider_label = provider_display_name(&overlay.provider);
    let provider_line = Line::from(vec![
        Span::styled(
            format!("{} ", chat_text("chat.model.provider")),
            Style::default().fg(Color::DarkGray),
        ),
        Span::styled(
            provider_label,
            Style::default().add_modifier(Modifier::BOLD),
        ),
    ]);
    frame.render_widget(Paragraph::new(provider_line), layout[0]);

    let current_line = Line::from(vec![
        Span::styled(
            format!("{} ", chat_text("chat.model.current")),
            Style::default().fg(Color::DarkGray),
        ),
        Span::styled(
            overlay.current_model.clone(),
            Style::default()
                .fg(Color::Gray)
                .add_modifier(Modifier::BOLD),
        ),
    ]);
    frame.render_widget(Paragraph::new(current_line), layout[1]);

    frame.render_widget(
        Paragraph::new(Line::from(Span::styled(
            chat_text("chat.model.subtitle"),
            Style::default().fg(Color::DarkGray),
        ))),
        layout[2],
    );

    let input_block = Block::default()
        .title(chat_text("chat.model.input.title"))
        .borders(Borders::ALL)
        .border_style(if overlay.error.is_some() {
            Style::default().fg(Color::Red)
        } else {
            Style::default().fg(Color::Cyan)
        });
    let input_inner = input_block.inner(layout[3]);
    frame.render_widget(input_block, layout[3]);

    if input_inner.width > 0 && input_inner.height > 0 {
        let view =
            single_line_input_view(&overlay.draft, overlay.cursor, input_inner.width as usize);
        let line = if overlay.draft.is_empty() {
            Line::from(Span::styled(
                chat_text("chat.model.input.placeholder"),
                Style::default().fg(Color::DarkGray),
            ))
        } else {
            Line::from(Span::raw(view.visible_text))
        };
        frame.render_widget(Paragraph::new(line), input_inner);
        frame.set_cursor_position((input_inner.x + view.cursor_col as u16, input_inner.y));
    }

    let status_text = overlay
        .error
        .clone()
        .unwrap_or_else(|| chat_text("chat.model.hint"));
    let status_style = if overlay.error.is_some() {
        Style::default().fg(Color::Red)
    } else {
        Style::default().fg(Color::DarkGray)
    };
    frame.render_widget(
        Paragraph::new(Line::from(Span::styled(status_text, status_style))),
        layout[4],
    );
}

pub(super) fn open_model_editor_if_available(app: &mut ChatApp) {
    if app.mode != ChatMode::Ready {
        app.set_footer(
            chat_text("chat.footer.cannot_model_while_replying"),
            MetaTone::Warning,
        );
        return;
    }

    if app.busy_action.is_some() {
        app.set_footer(chat_text("chat.footer.busy_wait"), MetaTone::Warning);
        return;
    }

    app.open_model_editor();
}

fn render_slash_popup(frame: &mut Frame<'_>, input_area: Rect, app: &mut ChatApp) {
    let matches = app.slash_matches();
    if matches.is_empty() {
        return;
    }

    let max_visible = slash_popup_max_visible(input_area);
    let (visible_start, visible_count) =
        visible_list_window(app.slash_selected, matches.len(), max_visible);
    if visible_count == 0 {
        return;
    }

    app.slash_popup_visible_start = visible_start;

    let height = (visible_count as u16).saturating_mul(2).saturating_add(2);
    let popup_width = input_area.width.min(60);
    let popup = Rect {
        x: input_area.x,
        y: input_area.y.saturating_sub(height),
        width: popup_width,
        height,
    };
    let block = Block::default()
        .title(chat_text("chat.commands.title"))
        .borders(Borders::ALL);
    let inner = block.inner(popup);
    frame.render_widget(Clear, popup);

    let items: Vec<ListItem<'_>> = matches
        .iter()
        .skip(visible_start)
        .take(visible_count)
        .map(|command| {
            let alias = if command.aliases.is_empty() {
                String::new()
            } else {
                format!("  ({})", command.aliases.join(", "))
            };
            ListItem::new(vec![
                Line::from(vec![
                    Span::styled(command.name, Style::default().add_modifier(Modifier::BOLD)),
                    Span::styled(alias, Style::default().fg(Color::DarkGray)),
                ]),
                Line::from(Span::styled(
                    chat_text(command.description),
                    Style::default().fg(Color::Gray),
                )),
            ])
        })
        .collect();

    let mut state = ListState::default();
    state.select(Some(
        app.slash_selected
            .saturating_sub(visible_start)
            .min(visible_count.saturating_sub(1)),
    ));
    let list = List::new(items)
        .block(block)
        .highlight_style(
            Style::default()
                .bg(Color::Rgb(26, 26, 26))
                .fg(Color::Yellow),
        )
        .highlight_symbol("› ");
    frame.render_stateful_widget(list, popup, &mut state);

    for index in 0..visible_count {
        let y = inner.y.saturating_add((index as u16).saturating_mul(2));
        let height = inner
            .height
            .saturating_sub((index as u16).saturating_mul(2))
            .min(2);
        if height == 0 {
            break;
        }
        app.slash_popup_hitboxes.push(Rect {
            x: inner.x,
            y,
            width: inner.width,
            height,
        });
    }
}

fn slash_popup_max_visible(input_area: Rect) -> usize {
    input_area.y.saturating_sub(2) as usize / 2
}

pub(super) fn visible_list_window(
    selected: usize,
    total_items: usize,
    max_visible: usize,
) -> (usize, usize) {
    if total_items == 0 || max_visible == 0 {
        return (0, 0);
    }

    let visible_count = total_items.min(max_visible);
    let selected = selected.min(total_items.saturating_sub(1));
    let visible_start = if total_items <= visible_count {
        0
    } else {
        selected
            .saturating_sub(visible_count.saturating_sub(1))
            .min(total_items.saturating_sub(visible_count))
    };

    (visible_start, visible_count)
}

fn render_history_overlay(
    frame: &mut Frame<'_>,
    area: Rect,
    overlay: &mut HistoryOverlay,
    history_hitboxes: &mut Vec<Rect>,
) {
    let popup = centered_rect(76, 58, area);
    frame.render_widget(Clear, popup);

    let layout = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Min(6), Constraint::Length(1)])
        .split(popup);

    let line_width = layout[0].width.saturating_sub(6) as usize;
    let block = Block::default()
        .title(chat_format(
            "chat.resume.title",
            &[("{count}", overlay.items.len().to_string())],
        ))
        .borders(Borders::ALL);
    let inner = block.inner(layout[0]);
    let items: Vec<ListItem<'_>> = overlay
        .items
        .iter()
        .map(|item| {
            let title = if let Some(model) = &item.model {
                format!("{}  {} / {}", item.title, item.provider, model)
            } else {
                format!("{}  {}", item.title, item.provider)
            };
            let detail = if item.last_snippet.trim().is_empty() {
                message_count_text(item.message_count)
            } else {
                format!(
                    "{}  |  {}",
                    message_count_text(item.message_count),
                    item.last_snippet
                )
            };
            ListItem::new(vec![
                Line::from(Span::styled(
                    truncate_text(&title, line_width),
                    Style::default().add_modifier(Modifier::BOLD),
                )),
                Line::from(Span::styled(
                    truncate_text(&detail, line_width),
                    Style::default().fg(Color::DarkGray),
                )),
            ])
        })
        .collect();

    let mut state = ListState::default();
    state.select(Some(overlay.selected));
    let list = List::new(items)
        .block(block)
        .highlight_style(Style::default().bg(Color::Rgb(30, 30, 30)).fg(Color::Cyan))
        .highlight_symbol("› ");
    frame.render_stateful_widget(list, layout[0], &mut state);

    let visible_slots = (inner.height as usize) / 2;
    overlay.visible_start = if visible_slots == 0 || overlay.items.len() <= visible_slots {
        0
    } else {
        overlay
            .selected
            .saturating_sub(visible_slots.saturating_sub(1))
            .min(overlay.items.len().saturating_sub(visible_slots))
    };
    for index in 0..visible_slots.min(overlay.items.len().saturating_sub(overlay.visible_start)) {
        let y = inner.y.saturating_add((index as u16).saturating_mul(2));
        let height = inner
            .height
            .saturating_sub((index as u16).saturating_mul(2))
            .min(2);
        if height == 0 {
            break;
        }
        history_hitboxes.push(Rect {
            x: inner.x,
            y,
            width: inner.width,
            height,
        });
    }

    let status = if overlay.loading_more {
        chat_format(
            "chat.resume.loading_more",
            &[("{spinner}", THINKING_FRAMES[0].to_string())],
        )
    } else if overlay.has_more {
        chat_text("chat.resume.more_available")
    } else {
        chat_text("chat.resume.end")
    };
    frame.render_widget(
        Paragraph::new(Line::from(Span::styled(
            status,
            Style::default().fg(Color::DarkGray),
        ))),
        layout[1],
    );
}

pub(super) fn build_transcript_base_lines(
    conversation_entries: &[TranscriptEntry],
    activities: &[TranscriptEntry],
    width: usize,
) -> Vec<Line<'static>> {
    let mut lines = Vec::new();

    for entry in conversation_entries {
        push_transcript_entry_lines(&mut lines, width, entry);
    }

    for entry in activities {
        push_transcript_entry_lines(&mut lines, width, entry);
    }

    lines
}

pub(super) fn build_transcript_tail_lines(app: &ChatApp, width: usize) -> Vec<Line<'static>> {
    let mut lines = Vec::new();

    if !app.streaming_text.is_empty() {
        push_assistant_entry_lines(&mut lines, width, &app.streaming_text);
        return lines;
    }

    if let Some(action) = &app.busy_action {
        push_status_entry_lines(
            &mut lines,
            width,
            app.spinner_frame(),
            action,
            Style::default()
                .fg(Color::Gray)
                .add_modifier(Modifier::ITALIC),
        );
        return lines;
    }

    match app.mode {
        ChatMode::Streaming => push_status_entry_lines(
            &mut lines,
            width,
            app.spinner_frame(),
            "Thinking",
            Style::default()
                .fg(Color::Gray)
                .add_modifier(Modifier::ITALIC),
        ),
        ChatMode::AwaitingApproval => push_status_entry_lines(
            &mut lines,
            width,
            app.spinner_frame(),
            "Waiting approval",
            Style::default()
                .fg(Color::Yellow)
                .add_modifier(Modifier::ITALIC),
        ),
        ChatMode::Ready => {}
    }

    lines
}

fn push_status_entry_lines(
    lines: &mut Vec<Line<'static>>,
    width: usize,
    spinner: &str,
    text: &str,
    style: Style,
) {
    let prefix = format!("  {} ", spinner);
    push_wrapped_lines(lines, width, &prefix, "    ", text, style);
}

pub(super) fn transcript_view_lines(
    app: &mut ChatApp,
    width: usize,
    height: usize,
) -> Vec<Line<'static>> {
    if height == 0 {
        return Vec::new();
    }

    let scroll = app.scroll;
    let has_status_tail = app.auto_scroll
        && app.streaming_text.is_empty()
        && app.conversation_entries.is_empty()
        && app.activities.is_empty()
        && !matches!(app.current_tail_key(), TranscriptTailKey::None);
    let lines = app.transcript_lines(width);
    let end = (scroll + height).min(lines.len());
    let mut visible_lines = lines[scroll..end].to_vec();

    if has_status_tail && visible_lines.len() < height {
        let mut padded_lines = Vec::with_capacity(height);
        padded_lines
            .extend((0..height.saturating_sub(visible_lines.len())).map(|_| Line::from("")));
        padded_lines.append(&mut visible_lines);
        return padded_lines;
    }

    visible_lines
}

fn push_transcript_entry_lines(
    lines: &mut Vec<Line<'static>>,
    width: usize,
    entry: &TranscriptEntry,
) {
    match entry {
        TranscriptEntry::User { text, attachments } => {
            push_user_entry_lines(lines, width, text, attachments)
        }
        TranscriptEntry::Assistant(text) => push_assistant_entry_lines(lines, width, text),
        TranscriptEntry::Meta { text, tone } => push_meta_entry_lines(lines, width, text, *tone),
    }
}

fn push_user_entry_lines(
    lines: &mut Vec<Line<'static>>,
    width: usize,
    text: &str,
    attachments: &[ChatAttachmentData],
) {
    let line_start = lines.len();
    for attachment in attachments {
        lines.push(attachment_chip_line(attachment, width, false, "  "));
    }
    if !text.trim().is_empty() {
        push_wrapped_lines(
            lines,
            width,
            "> ",
            "  ",
            text,
            Style::default()
                .fg(Color::Green)
                .add_modifier(Modifier::BOLD),
        );
    }
    if lines.len() > line_start {
        lines.push(Line::from(""));
    }
}

fn push_assistant_entry_lines(lines: &mut Vec<Line<'static>>, width: usize, text: &str) {
    let line_start = lines.len();
    push_wrapped_lines(
        lines,
        width,
        "< ",
        "  ",
        text,
        Style::default().fg(Color::Cyan),
    );
    if lines.len() > line_start {
        lines.push(Line::from(""));
    }
}

fn push_meta_entry_lines(lines: &mut Vec<Line<'static>>, width: usize, text: &str, tone: MetaTone) {
    let line_start = lines.len();
    push_wrapped_lines(lines, width, "· ", "  ", text, tone.style());
    if lines.len() > line_start {
        lines.push(Line::from(""));
    }
}

pub(super) fn push_wrapped_lines(
    lines: &mut Vec<Line<'static>>,
    width: usize,
    first_prefix: &str,
    next_prefix: &str,
    text: &str,
    style: Style,
) {
    let prefix_width = display_width(first_prefix).max(display_width(next_prefix));
    let available_width = width.max(prefix_width + 4);
    let options = Options::new(available_width)
        .initial_indent(first_prefix)
        .subsequent_indent(next_prefix)
        .break_words(true)
        .word_splitter(textwrap::WordSplitter::NoHyphenation);

    for line in textwrap::wrap(text, &options) {
        lines.push(Line::from(Span::styled(line.into_owned(), style)));
    }
}

fn attachment_chip_line(
    attachment: &ChatAttachmentData,
    width: usize,
    removable: bool,
    left_padding: &str,
) -> Line<'static> {
    let hint = if removable {
        format!(" {}", chat_text("chat.input.attachment.remove_hint"))
    } else {
        String::new()
    };
    let label = attachment_inline_label(attachment, None);
    let prefix_width = display_width(left_padding);
    let available_width = width.saturating_sub(prefix_width);
    let hint_width = display_width(&hint);
    let body_budget = available_width
        .saturating_sub(display_width(&label))
        .saturating_sub(hint_width)
        .saturating_sub(4)
        .max(1);
    let body = truncate_text(&attachment_preview_text(attachment), body_budget);

    let mut spans = vec![Span::raw(left_padding.to_string())];
    spans.push(Span::styled("[", Style::default().fg(Color::DarkGray)));
    spans.push(Span::styled(
        label,
        attachment_label_style(attachment).add_modifier(Modifier::BOLD),
    ));
    spans.push(Span::styled("] ", Style::default().fg(Color::DarkGray)));
    spans.push(Span::styled(body, Style::default().fg(Color::Gray)));
    if !hint.is_empty() {
        spans.push(Span::styled(hint, Style::default().fg(Color::DarkGray)));
    }
    Line::from(spans)
}

fn render_pending_attachments(
    frame: &mut Frame<'_>,
    area: Rect,
    attachments: &[ChatAttachmentData],
) {
    if attachments.is_empty() || area.width == 0 || area.height == 0 {
        return;
    }

    let card_areas = attachment_card_areas(area, attachments.len());
    for (index, (attachment, card_area)) in attachments.iter().zip(card_areas.iter()).enumerate() {
        let title = attachment_inline_label(attachment, Some(index + 1));
        let block = Block::default()
            .borders(Borders::ALL)
            .border_style(attachment_card_border_style(attachment))
            .title(Line::from(vec![
                Span::raw(" "),
                Span::styled(
                    title,
                    attachment_label_style(attachment).add_modifier(Modifier::BOLD),
                ),
                Span::raw(" "),
            ]));
        frame.render_widget(block.clone(), *card_area);

        let inner = block.inner(*card_area);
        if inner.width == 0 || inner.height == 0 {
            continue;
        }

        let body_budget = inner.width.saturating_sub(1) as usize;
        let body = truncate_text(&attachment_preview_text(attachment), body_budget.max(1));
        let line = Line::from(vec![Span::styled(body, Style::default().fg(Color::Gray))]);
        frame.render_widget(Paragraph::new(line), inner);
    }
}

fn render_pending_pastes(frame: &mut Frame<'_>, area: Rect, pending_pastes: &[PendingPasteData]) {
    if pending_pastes.is_empty() || area.width == 0 || area.height == 0 {
        return;
    }

    let card_areas = attachment_card_areas(area, pending_pastes.len());
    for (index, (paste, card_area)) in pending_pastes.iter().zip(card_areas.iter()).enumerate() {
        let title = pending_paste_inline_label(index + 1);
        let block = Block::default()
            .borders(Borders::ALL)
            .border_style(Style::default().fg(Color::Yellow))
            .title(Line::from(vec![
                Span::raw(" "),
                Span::styled(
                    title,
                    Style::default()
                        .fg(Color::Yellow)
                        .add_modifier(Modifier::BOLD),
                ),
                Span::raw(" "),
            ]));
        frame.render_widget(block.clone(), *card_area);

        let inner = block.inner(*card_area);
        if inner.width == 0 || inner.height == 0 {
            continue;
        }

        let body_budget = inner.width.saturating_sub(1) as usize;
        let body = truncate_text(&pending_paste_preview_text(paste), body_budget.max(1));
        let line = Line::from(vec![Span::styled(body, Style::default().fg(Color::Gray))]);
        frame.render_widget(Paragraph::new(line), inner);
    }
}

fn attachment_card_areas(area: Rect, attachment_count: usize) -> Vec<Rect> {
    if attachment_count == 0 || area.width == 0 || area.height == 0 {
        return Vec::new();
    }

    if attachment_count == 1 {
        return vec![area];
    }

    if area.width >= MIN_TWO_COLUMN_ATTACHMENT_WIDTH {
        let cols = Layout::default()
            .direction(Direction::Horizontal)
            .constraints([
                Constraint::Fill(1),
                Constraint::Length(1),
                Constraint::Fill(1),
            ])
            .split(area);
        return vec![cols[0], cols[2]];
    }

    Layout::default()
        .direction(Direction::Vertical)
        .constraints(vec![
            Constraint::Length(ATTACHMENT_CARD_HEIGHT);
            attachment_count
        ])
        .split(area)
        .iter()
        .copied()
        .take(attachment_count)
        .collect()
}

fn pending_attachment_preview_height(width: u16, attachment_count: usize) -> u16 {
    if attachment_count == 0 {
        return 0;
    }

    if attachment_count == 1 || width >= MIN_TWO_COLUMN_ATTACHMENT_WIDTH {
        ATTACHMENT_CARD_HEIGHT
    } else {
        ATTACHMENT_CARD_HEIGHT.saturating_mul(attachment_count as u16)
    }
}

fn attachment_preview_text(attachment: &ChatAttachmentData) -> String {
    let source = if attachment.kind == "image_ocr" {
        attachment.full_content.as_str()
    } else {
        attachment.display_text.as_str()
    };
    let normalized = source.split_whitespace().collect::<Vec<_>>().join(" ");
    if normalized.is_empty() {
        attachment.display_text.clone()
    } else {
        normalized
    }
}

fn pending_paste_preview_text(paste: &PendingPasteData) -> String {
    let line_count = pasted_text_line_count(&paste.full_text);
    let char_count = char_count(&paste.full_text);
    let summary = match i18n::locale() {
        "en" => {
            if line_count > 1 {
                format!("{line_count} lines · {char_count} chars")
            } else {
                format!("{char_count} chars")
            }
        }
        _ => {
            if line_count > 1 {
                format!("{line_count} 行 · {char_count} 字")
            } else {
                format!("{char_count} 字")
            }
        }
    };
    let normalized = paste
        .full_text
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ");
    if normalized.is_empty() {
        summary
    } else {
        format!("{summary} · {normalized}")
    }
}

fn attachment_inline_label(attachment: &ChatAttachmentData, index: Option<usize>) -> String {
    let base = if attachment.kind == "image_ocr" {
        match i18n::locale() {
            "zh-Hans" | "zh-Hant" => "图片",
            _ => "Image",
        }
    } else {
        match i18n::locale() {
            "zh-Hans" | "zh-Hant" => "剪贴",
            _ => "Clip",
        }
    };
    index
        .map(|index| format!("{base} {index}"))
        .unwrap_or_else(|| base.to_string())
}

fn pending_paste_inline_label(index: usize) -> String {
    match i18n::locale() {
        "en" => format!("Paste {index}"),
        _ => format!("粘贴 {index}"),
    }
}

fn attachment_label_style(attachment: &ChatAttachmentData) -> Style {
    if attachment.kind == "image_ocr" {
        Style::default().fg(Color::LightCyan)
    } else {
        Style::default().fg(Color::Gray)
    }
}

fn attachment_card_border_style(attachment: &ChatAttachmentData) -> Style {
    if attachment.kind == "image_ocr" {
        Style::default().fg(Color::Cyan)
    } else {
        Style::default().fg(Color::DarkGray)
    }
}

pub(super) fn looks_like_path_payload(text: &str) -> bool {
    let parts: Vec<&str> = text
        .lines()
        .map(str::trim)
        .filter(|part| !part.is_empty())
        .collect();
    !parts.is_empty()
        && parts.iter().all(|part| {
            part.starts_with("file://") || part.starts_with('/') || part.starts_with("~/")
        })
}

fn centered_rect(percent_x: u16, percent_y: u16, rect: Rect) -> Rect {
    let vertical = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Percentage((100 - percent_y) / 2),
            Constraint::Percentage(percent_y),
            Constraint::Percentage((100 - percent_y) / 2),
        ])
        .split(rect);

    Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage((100 - percent_x) / 2),
            Constraint::Percentage(percent_x),
            Constraint::Percentage((100 - percent_x) / 2),
        ])
        .split(vertical[1])[1]
}

struct SingleLineInputView {
    visible_text: String,
    cursor_col: usize,
}

fn single_line_input_view(text: &str, cursor: usize, width: usize) -> SingleLineInputView {
    let width = width.max(1);
    let cursor = cursor.min(char_count(text));
    let chars: Vec<char> = text.chars().collect();

    let max_cursor_width = width.saturating_sub(1);
    let mut start = 0usize;
    let mut cursor_width = 0usize;

    for (index, ch) in chars.iter().enumerate().take(cursor) {
        cursor_width += char_display_width(*ch);
        while cursor_width > max_cursor_width && start <= index {
            cursor_width = cursor_width.saturating_sub(char_display_width(chars[start]));
            start += 1;
        }
    }

    let mut used = 0usize;
    let mut visible_text = String::new();
    for ch in chars.iter().skip(start) {
        let ch_width = char_display_width(*ch);
        if used + ch_width > width {
            break;
        }
        visible_text.push(*ch);
        used += ch_width;
    }

    SingleLineInputView {
        visible_text,
        cursor_col: cursor_width.min(used),
    }
}

fn provider_display_name(provider: &str) -> &str {
    match provider {
        "chatgpt" => "ChatGPT",
        "openai_api" => "OpenAI API",
        "anthropic" => "Anthropic API",
        "ollama" => "Ollama",
        _ => provider,
    }
}

#[derive(Debug)]
pub(super) struct WrappedInputRow {
    pub(super) text: String,
    pub(super) start_char: usize,
    pub(super) end_char: usize,
}

#[derive(Debug)]
pub(super) struct WrappedInputLayout {
    pub(super) rows: Vec<WrappedInputRow>,
    pub(super) cursor_row: usize,
    pub(super) cursor_col: usize,
}

pub(super) struct InputViewport {
    visible_lines: Vec<String>,
    cursor_row: usize,
    cursor_col: usize,
    pub(super) start_row: usize,
}

pub(super) fn input_panel_height(app: &ChatApp, width: u16) -> u16 {
    let input_width = width.saturating_sub(4) as usize;
    let layout = wrapped_input_layout(&app.input, app.input_cursor, input_width.max(1));
    let visible_lines = layout.rows.len().clamp(1, MAX_INPUT_VISIBLE_LINES);
    let attachment_height =
        pending_attachment_preview_height(width.saturating_sub(2), app.pending_attachment_count());
    let pending_paste_height =
        pending_attachment_preview_height(width.saturating_sub(2), app.pending_paste_count());
    visible_lines as u16 + 2 + attachment_height + pending_paste_height
}

pub(super) fn input_viewport(
    input: &str,
    cursor: usize,
    width: usize,
    height: usize,
) -> InputViewport {
    let width = width.max(1);
    let height = height.max(1);
    let layout = wrapped_input_layout(input, cursor, width);
    let max_start = layout.rows.len().saturating_sub(height);
    let start = layout
        .cursor_row
        .saturating_sub(height.saturating_sub(1))
        .min(max_start);
    let end = (start + height).min(layout.rows.len());
    let mut visible_lines: Vec<String> = layout.rows[start..end]
        .iter()
        .map(|row| row.text.clone())
        .collect();
    while visible_lines.len() < height {
        visible_lines.push(String::new());
    }

    InputViewport {
        visible_lines,
        cursor_row: layout.cursor_row.saturating_sub(start).min(height - 1),
        cursor_col: layout.cursor_col.min(width.saturating_sub(1)),
        start_row: start,
    }
}

pub(super) fn wrapped_input_layout(input: &str, cursor: usize, width: usize) -> WrappedInputLayout {
    let width = width.max(1);
    let cursor = cursor.min(char_count(input));
    let mut rows = vec![WrappedInputRow {
        text: String::new(),
        start_char: 0,
        end_char: 0,
    }];
    let mut row = 0usize;
    let mut col = 0usize;
    let mut offset = 0usize;
    let mut cursor_row = 0usize;
    let mut cursor_col = 0usize;

    for ch in input.chars() {
        if offset == cursor {
            cursor_row = row;
            cursor_col = col;
        }

        if ch == '\n' {
            rows[row].end_char = offset;
            row += 1;
            rows.push(WrappedInputRow {
                text: String::new(),
                start_char: offset + 1,
                end_char: offset + 1,
            });
            col = 0;
            offset += 1;
            continue;
        }

        let ch_width = char_display_width(ch);
        if !rows[row].text.is_empty() && col + ch_width > width {
            rows[row].end_char = offset;
            row += 1;
            rows.push(WrappedInputRow {
                text: String::new(),
                start_char: offset,
                end_char: offset,
            });
            col = 0;
            if offset == cursor {
                cursor_row = row;
                cursor_col = 0;
            }
        }

        rows[row].text.push(ch);
        col += ch_width;
        offset += 1;
        rows[row].end_char = offset;
    }

    if offset == cursor {
        cursor_row = row;
        cursor_col = col;
    }

    if rows[cursor_row].end_char == cursor && cursor_col >= width {
        if rows
            .get(cursor_row + 1)
            .is_some_and(|next_row| next_row.start_char == cursor)
        {
            cursor_row += 1;
            cursor_col = 0;
        } else {
            rows.insert(
                cursor_row + 1,
                WrappedInputRow {
                    text: String::new(),
                    start_char: cursor,
                    end_char: cursor,
                },
            );
            cursor_row += 1;
            cursor_col = 0;
        }
    }

    WrappedInputLayout {
        rows,
        cursor_row,
        cursor_col,
    }
}

fn char_display_width(ch: char) -> usize {
    UnicodeWidthChar::width(ch).unwrap_or(0).max(1)
}

pub(super) fn cursor_from_visual_position(
    layout: &WrappedInputLayout,
    row: usize,
    col: usize,
) -> usize {
    let Some(target_row) = layout.rows.get(row).or_else(|| layout.rows.last()) else {
        return 0;
    };

    let mut best_index = target_row.start_char;
    let mut best_distance = usize::MAX;
    let mut display_col = 0usize;
    let mut char_index = target_row.start_char;

    let mut consider = |candidate_col: usize, candidate_index: usize| {
        let distance = candidate_col.abs_diff(col);
        if distance <= best_distance {
            best_distance = distance;
            best_index = candidate_index;
        }
    };

    consider(0, target_row.start_char);
    for ch in target_row.text.chars() {
        display_col += char_display_width(ch);
        char_index += 1;
        consider(display_col, char_index);
    }

    best_index
}

fn current_line_bounds(text: &str, cursor: usize) -> (usize, usize) {
    let cursor = cursor.min(char_count(text));
    let chars: Vec<char> = text.chars().collect();
    let mut start = cursor;
    while start > 0 && chars[start - 1] != '\n' {
        start -= 1;
    }

    let mut end = cursor;
    while end < chars.len() && chars[end] != '\n' {
        end += 1;
    }

    (start, end)
}

pub(super) fn move_cursor_vertical(text: &str, cursor: usize, width: usize, delta: isize) -> usize {
    let layout = wrapped_input_layout(text, cursor, width.max(1));
    if layout.rows.is_empty() {
        return 0;
    }

    let target_row = if delta < 0 {
        layout.cursor_row.saturating_sub(delta.unsigned_abs())
    } else {
        (layout.cursor_row + delta as usize).min(layout.rows.len().saturating_sub(1))
    };

    if target_row == layout.cursor_row {
        return if delta < 0 {
            layout.rows[target_row].start_char
        } else {
            layout.rows[target_row].end_char
        };
    }

    cursor_from_visual_position(&layout, target_row, layout.cursor_col)
}

pub(super) fn point_in_rect(column: u16, row: u16, rect: Rect) -> bool {
    column >= rect.x
        && column < rect.x.saturating_add(rect.width)
        && row >= rect.y
        && row < rect.y.saturating_add(rect.height)
}

pub(super) fn scrollbar_thumb_metrics(
    total_lines: usize,
    visible_lines: usize,
    scroll: usize,
    track_height: usize,
) -> (usize, usize) {
    let total_lines = total_lines.max(1);
    let visible_lines = visible_lines.max(1).min(total_lines);
    let track_height = track_height.max(1);
    let max_scroll = total_lines.saturating_sub(visible_lines);
    let thumb_height =
        ((visible_lines * track_height) + total_lines.saturating_sub(1)) / total_lines;
    let thumb_height = thumb_height.clamp(1, track_height);
    let max_thumb_top = track_height.saturating_sub(thumb_height);
    let thumb_top = scroll
        .min(max_scroll)
        .saturating_mul(max_thumb_top)
        .checked_div(max_scroll)
        .unwrap_or(0);

    (thumb_top, thumb_height)
}

pub(super) fn render_scrollbar(
    frame: &mut Frame<'_>,
    area: Rect,
    total_lines: usize,
    visible_lines: usize,
    scroll: usize,
    track_color: Color,
    thumb_color: Color,
) {
    if area.width == 0 || area.height == 0 {
        return;
    }

    let total_lines = total_lines.max(1);
    let visible_lines = visible_lines.max(1).min(total_lines);
    if total_lines <= visible_lines {
        return;
    }
    let height = area.height as usize;
    let (thumb_top, thumb_height) =
        scrollbar_thumb_metrics(total_lines, visible_lines, scroll, height);

    let lines: Vec<Line<'_>> = (0..height)
        .map(|row| {
            let (symbol, color) = if row >= thumb_top && row < thumb_top + thumb_height {
                ("█", thumb_color)
            } else {
                ("│", track_color)
            };
            Line::from(Span::styled(symbol, Style::default().fg(color)))
        })
        .collect();
    frame.render_widget(Paragraph::new(lines), area);
}

pub(super) fn truncate_text(text: &str, width: usize) -> String {
    if width == 0 {
        return String::new();
    }

    if display_width(text) <= width {
        return text.to_string();
    }

    if width == 1 {
        return "…".to_string();
    }

    let mut truncated = String::new();
    let mut used = 0usize;
    for ch in text.chars() {
        let char_width = char_display_width(ch);
        if used + char_width > width.saturating_sub(1) {
            break;
        }
        truncated.push(ch);
        used += char_width;
    }
    truncated.push('…');
    truncated
}

pub(super) fn char_count(text: &str) -> usize {
    text.chars().count()
}

fn byte_index_from_char(text: &str, char_index: usize) -> usize {
    if char_index == 0 {
        return 0;
    }

    text.char_indices()
        .nth(char_index)
        .map(|(index, _)| index)
        .unwrap_or_else(|| text.len())
}

pub(super) fn insert_char_at(text: &mut String, cursor: &mut usize, ch: char) {
    let index = byte_index_from_char(text, *cursor);
    text.insert(index, ch);
    *cursor += 1;
}

pub(super) fn insert_text_at(text: &mut String, cursor: &mut usize, inserted: &str) {
    let index = byte_index_from_char(text, *cursor);
    text.insert_str(index, inserted);
    *cursor += char_count(inserted);
}

pub(super) fn delete_before_cursor(text: &mut String, cursor: &mut usize) {
    if *cursor == 0 {
        return;
    }

    let start = byte_index_from_char(text, (*cursor).saturating_sub(1));
    let end = byte_index_from_char(text, *cursor);
    text.replace_range(start..end, "");
    *cursor = (*cursor).saturating_sub(1);
}

pub(super) fn delete_to_line_start_in_text(text: &mut String, cursor: &mut usize) {
    let (start, end) = current_line_bounds(text, *cursor);
    if start == *cursor {
        let chars: Vec<char> = text.chars().collect();
        if end == *cursor && *cursor > 0 && chars[*cursor - 1] == '\n' {
            delete_before_cursor(text, cursor);
        }
        return;
    }

    let byte_start = byte_index_from_char(text, start);
    let byte_end = byte_index_from_char(text, *cursor);
    text.replace_range(byte_start..byte_end, "");
    *cursor = start;
}

pub(super) fn delete_at_cursor(text: &mut String, cursor: usize) {
    if cursor >= char_count(text) {
        return;
    }

    let start = byte_index_from_char(text, cursor);
    let end = byte_index_from_char(text, cursor + 1);
    text.replace_range(start..end, "");
}

/// Returns true for characters that count as part of a "word" for word-wise
/// cursor movement and deletion. ASCII alphanumerics and `_` follow the
/// readline / Emacs convention; non-ASCII characters (CJK, emoji, etc.) are
/// also treated as word characters because punctuation is the only thing
/// users typically expect a word jump to stop at.
fn is_word_char(ch: char) -> bool {
    ch.is_alphanumeric() || ch == '_'
}

/// Compute the cursor position one word to the left of `cursor`.
///
/// Skips trailing whitespace/punctuation, then skips the contiguous run of
/// word characters. The returned index points to the first character of
/// the previous word.
pub(super) fn previous_word_boundary(text: &str, cursor: usize) -> usize {
    if cursor == 0 {
        return 0;
    }
    let chars: Vec<char> = text.chars().collect();
    let mut idx = cursor.min(chars.len());
    while idx > 0 && !is_word_char(chars[idx - 1]) {
        idx -= 1;
    }
    while idx > 0 && is_word_char(chars[idx - 1]) {
        idx -= 1;
    }
    idx
}

/// Compute the cursor position one word to the right of `cursor`.
///
/// Skips the current run of word characters, then skips the run of
/// non-word characters. The returned index points to the first character of
/// the next word (or the end of `text`).
pub(super) fn next_word_boundary(text: &str, cursor: usize) -> usize {
    let chars: Vec<char> = text.chars().collect();
    let len = chars.len();
    let mut idx = cursor.min(len);
    while idx < len && is_word_char(chars[idx]) {
        idx += 1;
    }
    while idx < len && !is_word_char(chars[idx]) {
        idx += 1;
    }
    idx
}

/// Delete the word immediately preceding the cursor. No-op when at the start
/// of the buffer.
pub(super) fn delete_word_before_cursor(text: &mut String, cursor: &mut usize) {
    if *cursor == 0 {
        return;
    }
    let target = previous_word_boundary(text, *cursor);
    if target == *cursor {
        return;
    }
    let byte_start = byte_index_from_char(text, target);
    let byte_end = byte_index_from_char(text, *cursor);
    text.replace_range(byte_start..byte_end, "");
    *cursor = target;
}

/// Delete from the cursor to the end of the current line (not the buffer).
/// Mirrors readline's `kill-line` (Ctrl+K). When the cursor sits at the end
/// of a line that has a trailing newline, the newline itself is removed so
/// repeated Ctrl+K eventually empties the buffer.
pub(super) fn delete_to_line_end_in_text(text: &mut String, cursor: usize) {
    let chars: Vec<char> = text.chars().collect();
    let len = chars.len();
    if cursor >= len {
        return;
    }
    let mut end = cursor;
    while end < len && chars[end] != '\n' {
        end += 1;
    }
    if end == cursor {
        // We're on a newline; consume it so the line collapses upward.
        end = cursor + 1;
    }
    let byte_start = byte_index_from_char(text, cursor);
    let byte_end = byte_index_from_char(text, end);
    text.replace_range(byte_start..byte_end, "");
}

pub(super) fn display_width(text: &str) -> usize {
    text.chars()
        .map(|ch| match ch {
            '\t' => 4,
            _ if ch.is_ascii() => 1,
            _ => 2,
        })
        .sum()
}

pub(super) fn truncate_display(text: &str, max_width: usize) -> String {
    if max_width == 0 {
        return String::new();
    }

    if display_width(text) <= max_width {
        return text.to_string();
    }

    if max_width <= 3 {
        return ".".repeat(max_width);
    }

    let mut output = String::new();
    let mut used = 0;
    for ch in text.chars() {
        let width = if ch.is_ascii() { 1 } else { 2 };
        if used + width > max_width.saturating_sub(3) {
            break;
        }
        output.push(ch);
        used += width;
    }
    output.push_str("...");
    output
}

pub(super) fn spaced_line(
    left: &str,
    left_style: Style,
    right: &str,
    right_style: Style,
    width: usize,
) -> Line<'static> {
    let right_width = display_width(right);
    let left_budget = if right.is_empty() || width <= right_width + 1 {
        width
    } else {
        width.saturating_sub(right_width + 1)
    };
    let left = truncate_display(left, left_budget);
    let padding = if right.is_empty() || width <= right_width + display_width(&left) {
        String::new()
    } else {
        " ".repeat(width.saturating_sub(display_width(&left) + right_width))
    };

    Line::from(vec![
        Span::styled(left, left_style),
        Span::raw(padding),
        Span::styled(right.to_string(), right_style),
    ])
}

fn spans_display_width(spans: &[Span<'_>]) -> usize {
    spans
        .iter()
        .map(|span| display_width(span.content.as_ref()))
        .sum()
}

pub(super) fn spaced_line_with_right_spans(
    left: &str,
    left_style: Style,
    right_spans: Vec<Span<'static>>,
    width: usize,
) -> Line<'static> {
    let right_width = spans_display_width(&right_spans);
    let left_budget = if right_spans.is_empty() || width <= right_width + 1 {
        width
    } else {
        width.saturating_sub(right_width + 1)
    };
    let left = truncate_display(left, left_budget);
    let left_width = display_width(&left);
    let padding = if right_spans.is_empty() || width <= right_width + left_width {
        String::new()
    } else {
        " ".repeat(width.saturating_sub(left_width + right_width))
    };

    let mut spans = vec![Span::styled(left, left_style), Span::raw(padding)];
    spans.extend(right_spans);
    Line::from(spans)
}
