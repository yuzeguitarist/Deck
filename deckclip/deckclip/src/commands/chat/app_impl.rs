impl ChatApp {
    fn from_bootstrap(bootstrap: BootstrapData) -> Self {
        Self {
            session_id: String::new(),
            conversation_id: String::new(),
            conversation_title: chat_text("chat.conversation.new"),
            provider: bootstrap.provider.unwrap_or_else(|| "AI".to_string()),
            model: bootstrap
                .model
                .unwrap_or_else(|| chat_text("chat.model.not_started")),
            account: bootstrap.account,
            context_usage: None,
            conversation_entries: Vec::new(),
            activities: Vec::new(),
            input: String::new(),
            input_cursor: 0,
            pending_attachments: Vec::new(),
            pending_pastes: Vec::new(),
            next_pending_paste_id: 1,
            input_history: Vec::new(),
            input_history_index: None,
            input_history_draft: ComposerHistoryEntry::default(),
            input_visual_width: 1,
            input_text_area: None,
            slash_selected: 0,
            slash_popup_visible_start: 0,
            slash_popup_hitboxes: Vec::new(),
            history_hitboxes: Vec::new(),
            overlay: OverlayState::None,
            approval_input_guard: ApprovalInputGuard,
            mode: ChatMode::Ready,
            execution_mode: ExecutionMode::Agent,
            footer_message: None,
            footer_tag: None,
            busy_action: None,
            busy_started_at: None,
            busy_action_release_at: None,
            busy_call_id: None,
            streaming_text: String::new(),
            transcript_revision: 0,
            streaming_revision: 0,
            transcript_cache: TranscriptRenderCache::default(),
            last_assistant_text: None,
            tool_states: HashMap::new(),
            search_call_count: 0,
            mode_started_at: None,
            auto_scroll: true,
            scroll: 0,
            body_visible_lines: 0,
            body_total_lines: 0,
            body_scrollbar_area: None,
            dragging_body_scrollbar: false,
            body_scrollbar_grab_offset: 0,
            created_at: Instant::now(),
            quit_hint_until: None,
            pending_login_request: false,
            completion_sound_enabled: true,
            should_quit: false,
        }
    }

    fn replace_session(&mut self, session: SessionData, clear_ephemeral: bool) {
        self.session_id = session.session_id;
        self.conversation_id = session.conversation.id.clone();
        self.conversation_title = session.conversation.title.clone();
        self.provider = session.conversation.provider.clone();
        self.model = session.conversation.model.clone();
        self.context_usage = session.context_usage.clone();
        self.last_assistant_text = session
            .last_assistant_text
            .or_else(|| last_assistant_from_messages(&session.conversation.messages));
        self.conversation_entries = session
            .conversation
            .messages
            .into_iter()
            .filter_map(|message| match message.role.as_str() {
                "user" => {
                    let attachments = message.normalized_attachments();
                    Some(TranscriptEntry::User {
                        text: message.text,
                        attachments,
                    })
                }
                "assistant" => Some(TranscriptEntry::Assistant(message.text)),
                _ => None,
            })
            .collect();

        if clear_ephemeral {
            self.activities.clear();
            self.tool_states.clear();
            self.search_call_count = 0;
            self.streaming_text.clear();
            self.set_overlay(OverlayState::None);
            self.mode = ChatMode::Ready;
            self.mode_started_at = None;
            self.clear_busy_action();
            self.clear_composer();
        }

        self.auto_scroll = true;
        self.bump_transcript_revision();
        self.bump_streaming_revision();
    }

    fn conversation_updated(&mut self, session: SessionData) {
        self.replace_session(session, false);
    }

    fn apply_bootstrap(&mut self, bootstrap: BootstrapData) {
        if let Some(provider) = bootstrap.provider {
            self.provider = provider;
        }
        if let Some(model) = bootstrap.model {
            self.model = model;
        }
        self.account = bootstrap.account;
        self.context_usage = None;
    }

    fn open_model_editor(&mut self) {
        self.set_overlay(OverlayState::ModelEditor(ModelEditorOverlay::new(
            self.provider.clone(),
            self.model.clone(),
        )));
        self.clear_quit_hint();
    }

    fn execution_mode_label(&self) -> String {
        chat_text(match self.execution_mode {
            ExecutionMode::Agent => "chat.execution.agent",
            ExecutionMode::Yolo => "chat.execution.yolo",
        })
    }

    fn execution_mode_badge_style(&self) -> Style {
        match self.execution_mode {
            ExecutionMode::Agent => Style::default()
                .fg(Color::White)
                .bg(Color::DarkGray)
                .add_modifier(Modifier::BOLD),
            ExecutionMode::Yolo => Style::default()
                .fg(Color::Black)
                .bg(Color::Yellow)
                .add_modifier(Modifier::BOLD),
        }
    }

    fn set_overlay(&mut self, overlay: OverlayState) {
        let had_approval = matches!(self.overlay, OverlayState::Approval(_));
        let will_have_approval = matches!(&overlay, OverlayState::Approval(_));

        if had_approval && !will_have_approval {
            self.approval_input_guard.deactivate();
        } else if !had_approval && will_have_approval {
            self.approval_input_guard.activate();
        }

        self.overlay = overlay;
    }

    fn push_activity(&mut self, text: impl Into<String>, tone: MetaTone) {
        self.activities.push(TranscriptEntry::Meta {
            text: text.into(),
            tone,
        });
        self.bump_transcript_revision();
    }

    fn set_footer(&mut self, text: impl Into<String>, tone: MetaTone) {
        self.footer_message = Some((text.into(), tone));
        self.footer_tag = None;
    }

    fn set_tagged_footer(&mut self, text: impl Into<String>, tone: MetaTone, tag: FooterTag) {
        self.footer_message = Some((text.into(), tone));
        self.footer_tag = Some(tag);
    }

    fn clear_footer(&mut self) {
        self.footer_message = None;
        self.footer_tag = None;
    }

    fn set_busy_action(&mut self, text: impl Into<String>) {
        self.busy_action = Some(text.into());
        self.busy_started_at = Some(Instant::now());
        self.busy_action_release_at = None;
        self.busy_call_id = None;
    }

    fn clear_busy_action(&mut self) {
        self.busy_action = None;
        self.busy_started_at = None;
        self.busy_action_release_at = None;
        self.busy_call_id = None;
    }

    fn show_tool_status(&mut self, tool: &ToolEventData) {
        if tool.tool == "search_clipboard" {
            self.search_call_count += 1;
        }

        self.busy_action = Some(tool_status_text(tool, self.search_call_count));
        self.busy_started_at = Some(Instant::now());
        self.busy_action_release_at = None;
        self.busy_call_id = Some(tool.call_id.clone());
    }

    fn finish_tool_status(&mut self, call_id: &str) {
        if self.busy_call_id.as_deref() != Some(call_id) {
            return;
        }

        let Some(started_at) = self.busy_started_at else {
            self.clear_busy_action();
            return;
        };

        let visible_until = started_at + MIN_TOOL_STATUS_DISPLAY;
        if visible_until <= Instant::now() {
            self.clear_busy_action();
            return;
        }

        self.busy_action_release_at = Some(visible_until);
    }

    fn bump_transcript_revision(&mut self) {
        self.transcript_revision = self.transcript_revision.wrapping_add(1);
    }

    fn bump_streaming_revision(&mut self) {
        self.streaming_revision = self.streaming_revision.wrapping_add(1);
    }

    fn clear_popup_hitboxes(&mut self) {
        self.slash_popup_visible_start = 0;
        self.slash_popup_hitboxes.clear();
        self.history_hitboxes.clear();
    }

    fn sync_footer_after_input_change(&mut self) {
        if matches!(self.footer_tag, Some(FooterTag::SlashSelected)) && self.slash_query().is_none()
        {
            self.clear_footer();
        }
    }

    fn history_hitbox_index(&self, column: u16, row: u16) -> Option<usize> {
        self.history_hitboxes
            .iter()
            .position(|rect| point_in_rect(column, row, *rect))
    }

    fn slash_hitbox_index(&self, column: u16, row: u16) -> Option<usize> {
        self.slash_popup_hitboxes
            .iter()
            .position(|rect| point_in_rect(column, row, *rect))
    }

    fn quit_hint_text(trigger: QuitHintTrigger) -> String {
        match trigger {
            QuitHintTrigger::CtrlC => chat_text("chat.quit_hint.ctrl_c"),
            QuitHintTrigger::Esc => chat_text("chat.quit_hint.esc"),
        }
    }

    fn begin_send(&mut self) {
        self.mode = ChatMode::Streaming;
        self.mode_started_at = Some(Instant::now());
        self.streaming_text.clear();
        self.activities.clear();
        self.tool_states.clear();
        self.search_call_count = 0;
        self.set_overlay(OverlayState::None);
        self.auto_scroll = true;
        self.clear_quit_hint();
        self.bump_transcript_revision();
        self.bump_streaming_revision();
        self.set_footer(chat_text("chat.footer.generating"), MetaTone::Info);
    }

    fn finish_send(&mut self) {
        self.mode = ChatMode::Ready;
        self.mode_started_at = None;
        self.search_call_count = 0;
        self.streaming_text.clear();
        self.set_overlay(OverlayState::None);
        self.clear_busy_action();
        self.bump_streaming_revision();
    }

    fn status_text(&self) -> String {
        let yolo_status =
            |status: String| -> String { chat_format("chat.status.yolo", &[("{status}", status)]) };

        if let Some(action) = &self.busy_action {
            let status =
                if self.execution_mode == ExecutionMode::Yolo && self.busy_call_id.is_some() {
                    yolo_status(action.clone())
                } else {
                    action.clone()
                };
            return format!("{} {}", self.spinner_frame(), status);
        }

        match self.mode {
            ChatMode::Ready => chat_text("chat.status.ready"),
            ChatMode::Streaming => {
                let thinking = chat_text("chat.status.thinking_plain");
                format!("{} {}", self.spinner_frame(), thinking)
            }
            ChatMode::AwaitingApproval => chat_format(
                "chat.status.waiting_approval",
                &[
                    ("{spinner}", self.spinner_frame().to_string()),
                    ("{elapsed}", self.elapsed_suffix()),
                ],
            ),
        }
    }

    fn status_tone(&self) -> MetaTone {
        if self.busy_action.is_some() {
            return MetaTone::Info;
        }
        match self.mode {
            ChatMode::Ready => match self.execution_mode {
                ExecutionMode::Agent => MetaTone::Success,
                ExecutionMode::Yolo => MetaTone::Warning,
            },
            ChatMode::Streaming => MetaTone::Info,
            ChatMode::AwaitingApproval => MetaTone::Warning,
        }
    }

    fn transcript_lines(&mut self, width: usize) -> &[Line<'static>] {
        let width = width.max(1);
        let tail_key = self.current_tail_key();
        let rebuild_base = self.transcript_cache.width != width
            || self.transcript_cache.base_revision != self.transcript_revision;

        if rebuild_base {
            self.transcript_cache.width = width;
            self.transcript_cache.base_revision = self.transcript_revision;
            self.transcript_cache.combined_lines =
                build_transcript_base_lines(&self.conversation_entries, &self.activities, width);
            self.transcript_cache.base_line_count = self.transcript_cache.combined_lines.len();
            self.transcript_cache.tail_key = TranscriptTailKey::None;
        }

        if rebuild_base || self.transcript_cache.tail_key != tail_key {
            let tail_lines = build_transcript_tail_lines(self, width);
            self.transcript_cache
                .combined_lines
                .truncate(self.transcript_cache.base_line_count);
            self.transcript_cache.combined_lines.extend(tail_lines);
            if self.transcript_cache.combined_lines.is_empty() {
                self.transcript_cache
                    .combined_lines
                    .push(Line::from(Span::styled(
                        chat_text("chat.empty"),
                        Style::default().fg(Color::DarkGray),
                    )));
            }
            self.transcript_cache.tail_key = tail_key;
        }

        &self.transcript_cache.combined_lines
    }

    fn current_tail_key(&self) -> TranscriptTailKey {
        if !self.streaming_text.is_empty() {
            return TranscriptTailKey::Streaming {
                version: self.streaming_revision,
            };
        }

        match self.mode {
            ChatMode::Streaming | ChatMode::AwaitingApproval => TranscriptTailKey::Meta {
                mode: self.mode,
                spinner_frame: self.spinner_frame_index(),
                elapsed_seconds: self
                    .mode_started_at
                    .or(self.busy_started_at)
                    .map(|started_at| started_at.elapsed().as_secs())
                    .unwrap_or(0),
                busy_action: self.busy_action.clone(),
            },
            ChatMode::Ready => {
                if self.busy_action.is_some() {
                    TranscriptTailKey::Meta {
                        mode: self.mode,
                        spinner_frame: self.spinner_frame_index(),
                        elapsed_seconds: self
                            .busy_started_at
                            .map(|started_at| started_at.elapsed().as_secs())
                            .unwrap_or(0),
                        busy_action: self.busy_action.clone(),
                    }
                } else {
                    TranscriptTailKey::None
                }
            }
        }
    }

    fn animation_state(&self) -> Option<AnimationState> {
        let animated = self.busy_action.is_some()
            || matches!(self.mode, ChatMode::Streaming | ChatMode::AwaitingApproval);
        let has_timed_footer = self.quit_hint_until.is_some();
        if !animated && !has_timed_footer {
            return None;
        }

        Some(AnimationState {
            spinner_frame: if animated {
                self.spinner_frame_index()
            } else {
                0
            },
            elapsed_seconds: if animated {
                self.mode_started_at
                    .or(self.busy_started_at)
                    .map(|started_at| started_at.elapsed().as_secs())
                    .unwrap_or(0)
            } else {
                0
            },
            quit_hint_active: self.quit_hint_active(),
        })
    }

    fn poll_timeout(&self) -> Duration {
        if self.animation_state().is_some() {
            Duration::from_millis(50)
        } else {
            Duration::from_millis(200)
        }
    }

    fn spinner_frame_index(&self) -> usize {
        let elapsed_ms = self.created_at.elapsed().as_millis() as usize;
        (elapsed_ms / 80) % THINKING_FRAMES.len()
    }

    fn spinner_frame(&self) -> &'static str {
        THINKING_FRAMES[self.spinner_frame_index()]
    }

    fn elapsed_suffix(&self) -> String {
        let started_at = self.mode_started_at.or(self.busy_started_at);
        started_at
            .map(|started_at| format!(" · {}", format_elapsed(started_at.elapsed())))
            .unwrap_or_default()
    }

    fn scroll_up(&mut self, lines: usize) {
        self.auto_scroll = false;
        self.scroll = self.scroll.saturating_sub(lines);
        self.clear_quit_hint();
    }

    fn scroll_down(&mut self, lines: usize) {
        self.auto_scroll = false;
        self.scroll = self.scroll.saturating_add(lines);
        self.clear_quit_hint();
    }

    fn follow_output(&mut self) {
        self.auto_scroll = true;
        self.clear_quit_hint();
    }

    fn clear_composer(&mut self) {
        self.clear_input_text();
        self.pending_attachments.clear();
    }

    fn clear_input_text(&mut self) {
        self.input.clear();
        self.input_cursor = 0;
        self.pending_pastes.clear();
        self.input_history_index = None;
        self.input_history_draft = ComposerHistoryEntry::default();
        self.slash_selected = 0;
        self.clear_quit_hint();
        self.sync_footer_after_input_change();
    }

    fn composer_history_entry(&self) -> ComposerHistoryEntry {
        ComposerHistoryEntry {
            input: self.input.clone(),
            pending_pastes: self.pending_pastes.clone(),
        }
    }

    fn apply_composer_history_entry(&mut self, entry: ComposerHistoryEntry) {
        self.input = entry.input;
        self.pending_pastes = entry.pending_pastes;
        self.prune_pending_pastes();
        self.input_cursor = char_count(&self.input);
        self.refresh_slash_selection();
        self.clear_quit_hint();
        self.sync_footer_after_input_change();
    }

    fn prune_pending_pastes(&mut self) {
        self.pending_pastes
            .retain(|paste| self.input.contains(&paste.placeholder));
    }

    fn input_byte_index_from_char(&self, char_index: usize) -> usize {
        if char_index == 0 {
            return 0;
        }
        self.input
            .char_indices()
            .nth(char_index)
            .map(|(index, _)| index)
            .unwrap_or(self.input.len())
    }

    fn remove_input_char_range(&mut self, start: usize, end: usize) {
        if start >= end {
            return;
        }
        let byte_start = self.input_byte_index_from_char(start);
        let byte_end = self.input_byte_index_from_char(end);
        self.input.replace_range(byte_start..byte_end, "");
        self.input_cursor = start;
        self.prune_pending_pastes();
    }

    fn pending_paste_range_ending_at_cursor(&self) -> Option<(usize, usize)> {
        for paste in &self.pending_pastes {
            for (byte_start, _) in self.input.match_indices(&paste.placeholder) {
                let start = char_count(&self.input[..byte_start]);
                let end = start + char_count(&paste.placeholder);
                if end == self.input_cursor {
                    return Some((start, end));
                }
            }
        }
        None
    }

    fn pending_paste_range_starting_at_cursor(&self) -> Option<(usize, usize)> {
        for paste in &self.pending_pastes {
            for (byte_start, _) in self.input.match_indices(&paste.placeholder) {
                let start = char_count(&self.input[..byte_start]);
                let end = start + char_count(&paste.placeholder);
                if start == self.input_cursor {
                    return Some((start, end));
                }
            }
        }
        None
    }

    fn append_pending_attachments(
        &mut self,
        attachments: impl IntoIterator<Item = ChatAttachmentData>,
    ) -> usize {
        let remaining = MAX_PENDING_ATTACHMENTS.saturating_sub(self.pending_attachments.len());
        if remaining == 0 {
            return 0;
        }

        let mut added = 0;
        for attachment in attachments.into_iter().take(remaining) {
            self.pending_attachments.push(attachment);
            added += 1;
        }

        if added > 0 {
            self.input_history_index = None;
            self.clear_quit_hint();
            self.sync_footer_after_input_change();
        }

        added
    }

    #[cfg(test)]
    fn set_pending_attachment(&mut self, attachment: ChatAttachmentData) {
        let _ = self.append_pending_attachments([attachment]);
    }

    fn pending_attachments(&self) -> &[ChatAttachmentData] {
        &self.pending_attachments
    }

    fn pending_attachment_count(&self) -> usize {
        self.pending_attachments.len()
    }

    fn pending_pastes(&self) -> &[PendingPasteData] {
        &self.pending_pastes
    }

    fn pending_paste_count(&self) -> usize {
        self.pending_pastes.len()
    }

    fn next_pending_paste_placeholder(&mut self, text: &str) -> String {
        let id = self.next_pending_paste_id;
        self.next_pending_paste_id = self.next_pending_paste_id.saturating_add(1);
        format_pending_paste_placeholder(id, text)
    }

    fn insert_paste_text(&mut self, text: &str) -> bool {
        if !should_collapse_pasted_text(text) {
            self.insert_text(text);
            return false;
        }

        let placeholder = self.next_pending_paste_placeholder(text);
        insert_text_at(&mut self.input, &mut self.input_cursor, &placeholder);
        self.pending_pastes.push(PendingPasteData {
            placeholder,
            full_text: text.to_string(),
        });
        self.input_history_index = None;
        self.refresh_slash_selection();
        self.clear_quit_hint();
        self.sync_footer_after_input_change();
        true
    }

    fn expand_input_with_pending_pastes(&self) -> String {
        let mut expanded = self.input.clone();
        for paste in &self.pending_pastes {
            expanded = expanded.replacen(&paste.placeholder, &paste.full_text, 1);
        }
        expanded
    }

    fn pending_attachments_full(&self) -> bool {
        self.pending_attachments.len() >= MAX_PENDING_ATTACHMENTS
    }

    fn clear_pending_attachment(&mut self) -> bool {
        let removed = self.pending_attachments.pop().is_some();
        if removed {
            self.clear_quit_hint();
            self.sync_footer_after_input_change();
        }
        removed
    }

    fn remember_input(&mut self, submitted: &str) {
        let submitted = submitted.trim();
        if submitted.is_empty() {
            return;
        }
        let entry = ComposerHistoryEntry {
            input: submitted.to_string(),
            pending_pastes: self.pending_pastes.clone(),
        };
        if self.input_history.last().is_some_and(|last| last == &entry) {
            self.input_history_index = None;
            self.input_history_draft = ComposerHistoryEntry::default();
            return;
        }
        self.input_history.push(entry);
        self.input_history_index = None;
        self.input_history_draft = ComposerHistoryEntry::default();
    }

    fn browse_input_history_up(&mut self) -> bool {
        if self.input_history.is_empty() {
            return false;
        }

        let next_index = match self.input_history_index {
            Some(0) => 0,
            Some(index) => index.saturating_sub(1),
            None => {
                self.input_history_draft = self.composer_history_entry();
                self.input_history.len() - 1
            }
        };

        self.input_history_index = Some(next_index);
        self.apply_composer_history_entry(self.input_history[next_index].clone());
        true
    }

    fn browse_input_history_down(&mut self) -> bool {
        let Some(index) = self.input_history_index else {
            return false;
        };

        if index + 1 >= self.input_history.len() {
            let draft = std::mem::take(&mut self.input_history_draft);
            self.apply_composer_history_entry(draft);
            self.input_history_index = None;
        } else {
            let next_index = index + 1;
            self.input_history_index = Some(next_index);
            self.apply_composer_history_entry(self.input_history[next_index].clone());
        }
        true
    }

    fn update_input_text_area(&mut self, area: Rect) {
        self.input_visual_width = area.width.max(1);
        self.input_text_area = Some(area);
    }

    fn update_body_scrollbar_state(
        &mut self,
        scrollbar_area: Option<Rect>,
        visible_lines: usize,
        total_lines: usize,
    ) {
        self.body_scrollbar_area = scrollbar_area;
        self.body_visible_lines = visible_lines;
        self.body_total_lines = total_lines;
        if scrollbar_area.is_none() || total_lines <= visible_lines {
            self.dragging_body_scrollbar = false;
            self.body_scrollbar_grab_offset = 0;
        }
    }

    #[allow(clippy::manual_checked_ops)]
    fn scroll_to_body_pointer(&mut self, row: u16) {
        let Some(area) = self.body_scrollbar_area else {
            return;
        };
        let max_scroll = self
            .body_total_lines
            .saturating_sub(self.body_visible_lines);
        if max_scroll == 0 || area.height <= 1 {
            self.scroll = 0;
            self.auto_scroll = true;
            return;
        }

        let relative_row = row
            .saturating_sub(area.y)
            .min(area.height.saturating_sub(1)) as usize;
        let (_thumb_top, thumb_height) = scrollbar_thumb_metrics(
            self.body_total_lines,
            self.body_visible_lines,
            self.scroll,
            area.height as usize,
        );
        let max_thumb_top = area.height.saturating_sub(thumb_height as u16) as usize;
        let desired_thumb_top = relative_row
            .saturating_sub(self.body_scrollbar_grab_offset)
            .min(max_thumb_top);
        self.auto_scroll = false;
        self.scroll = if max_thumb_top == 0 {
            max_scroll
        } else {
            desired_thumb_top * max_scroll / max_thumb_top
        };
        self.clear_quit_hint();
    }

    fn start_body_scrollbar_drag(&mut self, column: u16, row: u16) -> bool {
        let Some(area) = self.body_scrollbar_area else {
            return false;
        };
        if !point_in_rect(column, row, area) {
            return false;
        }

        let relative_row = row.saturating_sub(area.y) as usize;
        let (thumb_top, thumb_height) = scrollbar_thumb_metrics(
            self.body_total_lines,
            self.body_visible_lines,
            self.scroll,
            area.height as usize,
        );
        self.dragging_body_scrollbar = true;
        self.body_scrollbar_grab_offset =
            if relative_row >= thumb_top && relative_row < thumb_top + thumb_height {
                relative_row.saturating_sub(thumb_top)
            } else {
                thumb_height / 2
            };
        self.scroll_to_body_pointer(row);
        true
    }

    fn drag_body_scrollbar(&mut self, row: u16) -> bool {
        if !self.dragging_body_scrollbar {
            return false;
        }
        self.scroll_to_body_pointer(row);
        true
    }

    fn stop_body_scrollbar_drag(&mut self) {
        self.dragging_body_scrollbar = false;
        self.body_scrollbar_grab_offset = 0;
    }

    fn move_cursor_to_pointer(&mut self, column: u16, row: u16) -> bool {
        let Some(area) = self.input_text_area else {
            return false;
        };
        if !point_in_rect(column, row, area) {
            return false;
        }

        let viewport = input_viewport(
            &self.input,
            self.input_cursor,
            self.input_visual_width as usize,
            area.height as usize,
        );
        let layout = wrapped_input_layout(
            &self.input,
            self.input_cursor,
            self.input_visual_width as usize,
        );
        let target_row = viewport.start_row + row.saturating_sub(area.y) as usize;
        let target_col = column.saturating_sub(area.x) as usize;
        self.input_cursor = cursor_from_visual_position(&layout, target_row, target_col);
        self.clear_quit_hint();
        true
    }

    fn has_session(&self) -> bool {
        !self.session_id.is_empty()
    }

    fn reset_to_empty_conversation(&mut self) {
        self.session_id.clear();
        self.conversation_id.clear();
        self.conversation_title = chat_text("chat.conversation.new");
        self.context_usage = None;
        self.conversation_entries.clear();
        self.activities.clear();
        self.search_call_count = 0;
        self.streaming_text.clear();
        self.last_assistant_text = None;
        self.set_overlay(OverlayState::None);
        self.mode = ChatMode::Ready;
        self.mode_started_at = None;
        self.auto_scroll = true;
        self.scroll = 0;
        self.dragging_body_scrollbar = false;
        self.clear_busy_action();
        self.clear_composer();
        self.bump_transcript_revision();
        self.bump_streaming_revision();
    }

    fn set_input(&mut self, value: String) {
        self.input = value;
        self.pending_pastes.clear();
        self.input_cursor = char_count(&self.input);
        self.input_history_index = None;
        self.refresh_slash_selection();
        self.clear_quit_hint();
        self.sync_footer_after_input_change();
    }

    fn insert_char(&mut self, ch: char) {
        insert_char_at(&mut self.input, &mut self.input_cursor, ch);
        self.prune_pending_pastes();
        self.input_history_index = None;
        self.refresh_slash_selection();
        self.clear_quit_hint();
        self.sync_footer_after_input_change();
    }

    fn insert_text(&mut self, text: &str) {
        insert_text_at(&mut self.input, &mut self.input_cursor, text);
        self.prune_pending_pastes();
        self.input_history_index = None;
        self.refresh_slash_selection();
        self.clear_quit_hint();
        self.sync_footer_after_input_change();
    }

    fn backspace(&mut self) {
        if let Some((start, end)) = self.pending_paste_range_ending_at_cursor() {
            self.remove_input_char_range(start, end);
        } else {
            delete_before_cursor(&mut self.input, &mut self.input_cursor);
            self.prune_pending_pastes();
        }
        self.input_history_index = None;
        self.refresh_slash_selection();
        self.clear_quit_hint();
        self.sync_footer_after_input_change();
    }

    fn delete_forward(&mut self) {
        if let Some((start, end)) = self.pending_paste_range_starting_at_cursor() {
            self.remove_input_char_range(start, end);
        } else {
            delete_at_cursor(&mut self.input, self.input_cursor);
            self.prune_pending_pastes();
        }
        self.input_history_index = None;
        self.refresh_slash_selection();
        self.clear_quit_hint();
        self.sync_footer_after_input_change();
    }

    fn move_cursor_left(&mut self) {
        self.input_cursor = self.input_cursor.saturating_sub(1);
        self.clear_quit_hint();
    }

    fn move_cursor_right(&mut self) {
        self.input_cursor = (self.input_cursor + 1).min(char_count(&self.input));
        self.clear_quit_hint();
    }

    fn move_cursor_start(&mut self) {
        self.input_cursor = 0;
        self.clear_quit_hint();
    }

    fn move_cursor_end(&mut self) {
        self.input_cursor = char_count(&self.input);
        self.clear_quit_hint();
    }

    fn move_cursor_up_line(&mut self) {
        self.input_cursor = move_cursor_vertical(
            &self.input,
            self.input_cursor,
            self.input_visual_width as usize,
            -1,
        );
        self.clear_quit_hint();
    }

    fn move_cursor_down_line(&mut self) {
        self.input_cursor = move_cursor_vertical(
            &self.input,
            self.input_cursor,
            self.input_visual_width as usize,
            1,
        );
        self.clear_quit_hint();
    }

    fn delete_to_line_start(&mut self) {
        delete_to_line_start_in_text(&mut self.input, &mut self.input_cursor);
        self.prune_pending_pastes();
        self.input_history_index = None;
        self.refresh_slash_selection();
        self.clear_quit_hint();
        self.sync_footer_after_input_change();
    }

    fn request_login(&mut self) {
        self.pending_login_request = true;
        self.clear_quit_hint();
    }

    fn take_login_request(&mut self) -> bool {
        std::mem::take(&mut self.pending_login_request)
    }

    fn slash_query(&self) -> Option<&str> {
        if !matches!(self.overlay, OverlayState::None) {
            return None;
        }

        let trimmed = self.input.trim();
        if !trimmed.starts_with('/') || trimmed.chars().any(char::is_whitespace) {
            return None;
        }

        Some(trimmed)
    }

    fn slash_matches(&self) -> Vec<&'static SlashCommand> {
        let Some(query) = self.slash_query() else {
            return Vec::new();
        };

        SLASH_COMMANDS
            .iter()
            .filter(|command| slash_command_matches(command, query))
            .collect()
    }

    fn refresh_slash_selection(&mut self) {
        let matches = self.slash_matches();
        if matches.is_empty() {
            self.slash_selected = 0;
        } else {
            self.slash_selected = self.slash_selected.min(matches.len().saturating_sub(1));
        }
    }

    fn select_previous_slash(&mut self) {
        let matches = self.slash_matches();
        if matches.is_empty() {
            return;
        }
        if self.slash_selected == 0 {
            self.slash_selected = matches.len() - 1;
        } else {
            self.slash_selected -= 1;
        }
    }

    fn select_next_slash(&mut self) {
        let matches = self.slash_matches();
        if matches.is_empty() {
            return;
        }
        self.slash_selected = (self.slash_selected + 1) % matches.len();
    }

    fn selected_slash_command(&self) -> Option<&'static SlashCommand> {
        let matches = self.slash_matches();
        matches.get(self.slash_selected).copied()
    }

    fn complete_selected_slash(&mut self) -> Option<&'static str> {
        let selected = self.selected_slash_command()?.name;
        self.set_input(selected.to_string());
        Some(selected)
    }

    fn arm_quit_hint(&mut self, trigger: QuitHintTrigger) {
        self.quit_hint_until = Some(Instant::now() + Duration::from_secs(1));
        self.set_tagged_footer(
            Self::quit_hint_text(trigger),
            MetaTone::Warning,
            FooterTag::QuitHint(trigger),
        );
    }

    fn clear_quit_hint(&mut self) {
        self.quit_hint_until = None;
        if matches!(self.footer_tag, Some(FooterTag::QuitHint(_))) {
            self.clear_footer();
        }
    }

    fn quit_hint_active(&self) -> bool {
        self.quit_hint_until
            .is_some_and(|deadline| deadline > Instant::now())
    }

    fn tick(&mut self) -> bool {
        if self
            .busy_action_release_at
            .is_some_and(|deadline| deadline <= Instant::now())
        {
            self.clear_busy_action();
            return true;
        }

        if self
            .quit_hint_until
            .is_some_and(|deadline| deadline <= Instant::now())
        {
            self.clear_quit_hint();
            return true;
        }

        false
    }
}
