# GitHub Releases Changelog

This file is auto-generated from GitHub Releases by [release-changelog-bot](.github/workflows/release-changelog-bot.yml). **Do not hand-edit release entries** (you may edit this intro).

<!-- release-changelog-bot:auto -->

<!-- release-changelog-bot:tag:v1.4.4 -->
## v1.4.4 — v1.4.4 | perlīmātus

- **Tag:** `v1.4.4`
- **Published:** 2026-05-05T11:29:24Z

### Release notes

<p align="center">
  <a href="https://deckclip.app/download" rel="noopener noreferrer" target="_blank">
    <img width="1525" height="896" alt="Deck" src="https://github.com/yuzeguitarist/Deck/raw/main/photos/Deck.webp" style="max-width: 100%; height: auto;" />
  </a>
</p>

---

## Release Notes v1.4.4

### Improvements

- Added LaTeX math rendering: horizontal Markdown card previews plus Markdown/plain-text preview panels now render inline, display, common equation/align/matrix/cases environments, and formula blocks inside TeX source; Markdown “Copy Plain Text” now exports formulas as readable Unicode text while preserving inline code and code blocks verbatim; rendered formulas are cached in memory to reduce repeated work during card and preview switches, preserving the existing preview scrolling behavior.

- Improved automatic update-check scheduling by keeping the existing check windows while assigning each device a stable randomized delay, spreading requests across a 30-minute window to smooth backend concurrency spikes and reduce peak-hour update service errors.

- Added an in-list survey feedback entry: once history exceeds 99 items in the default All view, Deck shows a non-focusable, non-draggable feedback card at the front of the list that never appears in search or tag-filtered results; it supports opening the survey, hiding for the session, or hiding permanently, with tuned horizontal/vertical and dark/light appearances.

- Improved the Settings > Statistics page responsiveness by applying statistics updates without unnecessary implicit animation and warming the top-app icon cache before rendering, reducing main-thread stalls while preserving the existing UI, charts, and interactions.

- Optimized background database maintenance scans by switching file-search backfill, vector-index backfill, and missing-file checks from OFFSET pagination to id-based keyset batching, keeping large-history maintenance time stable without changing the UI, search semantics, or cleanup behavior.

- Improved SQLite read/write scheduling with a dedicated read-only connection and reader queue, allowing history lists, search, statistics, and lightweight reads to avoid waiting behind writes, migrations, checkpoints, or background maintenance in WAL mode; writes and maintenance remain serialized on the writer queue, with automatic fallback if the reader is unavailable.

- Improved clipboard parsing and database write hot paths: clipboard monitoring now reads only an NSPasteboard snapshot on the main thread while rich-text, thumbnail, and type parsing run in the background; main-table inserts reuse a cached SQLite UPSERT statement with direct BLOB binding to reduce repeated prepare work and large-payload copies; background semantic embedding writes no longer hop back through the MainActor.

- Optimized semantic search and sqlite-vec indexing by storing, recovering, and querying vectors as native Float32 BLOBs instead of JSON strings; vector hits now fetch rows by candidate id and restore semantic-distance ordering without introducing timestamp sorting; security mode continues to disable vector indexing to preserve encryption semantics.

- Improved NL Embedding semantic-search quality by keeping Chinese queries and Chinese clipboard text in one CJK word-embedding averaged vector space, avoiding missed or mis-ranked results caused by comparing short queries and longer text across different embedding spaces; exact/contains recall and ranking fallbacks were also added without built-in synonym lists or external embedding models.

- Improved semantic embedding backfill scheduling by persisting the schema version immediately after an embedding-model cache reset and treating embedding population as resumable batched maintenance, avoiding repeated cache resets, repeated backups, and long CPU spikes on large histories.

- Improved SQLite WAL and read-path maintenance with a low-priority idle passive checkpoint plus `journal_size_limit` to keep WAL growth bounded after the panel becomes idle; list/export read paths no longer write legacy `unique_id` or temporary-flag repairs inline, moving those fixes to batched background maintenance to reduce write amplification during scrolling, search, and exports.

- Improved mixed-search performance in security mode by reusing decrypted exact matches from the encrypted-search fallback path, avoiding duplicate snapshot ranking and skipping ineffective SQL LIKE fallback queries against encrypted fields to reduce CPU and energy use.

- Improved large export and smart-text analysis performance by keeping JSON encoding and U+2028/U+2029 sanitization off the main thread, folding sanitization into a single scan, and using one pass to classify plain text for line length, Chinese ratio, and code markers, reducing CPU use and hitch risk during exports, search, and list scrolling.

- Improved LAN folder/app-bundle archive extraction security by allowing safe internal relative symlinks commonly used inside `.app` bundles and frameworks, while still rejecting absolute paths, `../../` escapes, duplicate archive entries, and any symlink target that normalizes outside the extraction root.

- Improved LAN / iOS sync connectivity under VPN, proxy enhanced mode, and multi-interface setups by discovering and displaying only real private LAN IPv4 candidates, accepting inbound listeners across available LAN interfaces, and constraining outbound direct connections only when the target IP matches the physical interface subnet.

- Improved LAN peer and manual direct-connect management by normalizing IPv4 input, merging duplicate manual and remembered peers, and cleaning stale credentials and metadata, reducing duplicate device entries, mismatched remembered ports, and stale peer records.

- Improved script-plugin and smart-rule execution performance by scheduling script timeouts independently so long-running scripts do not block the script queue or async callers, and by reusing per-item snapshots, compiled rule metadata, and search-text ranges to reduce repeated parsing during bulk clipboard processing.

- Improved script-plugin memory usage by running regular non-network transforms in a short-lived JavaScriptCore `jsc` subprocess, keeping the 4GB-scale `JS VM Gigacage` virtual-memory reservation out of Deck's long-lived app process while preserving the existing authorized `fetch` path for network plugins.

- Improved AI chat attachment memory usage by capping saved full attachment text and avoiding duplicate storage of the same large text in both message body and attachment content, reducing memory peaks and conversation size when long documents, OCR text, or large files are sent to AI.

- Improved the search field and rule picker experience by aligning the horizontal search width and rule popup to the card rhythm, adding a subtler hover state for rule rows, removing distracting rule tooltips, adding reliable Ctrl+U clearing in the search field, and preserving the existing vertical-mode popup spacing.

- Improved horizontal PDF card previews by filling the card preview area with the first page content, centering the filename at the bottom, and removing the separate PDF icon for a more continuous document-preview feel.

- Improved PDF preview controls by removing the separate zoom toolbar, moving the zoom buttons to the bottom info bar beside the timestamp, and preserving hover feedback to reduce visual layering at the bottom of PDF previews.

- Improved the image preview window footer by restoring the solid info-bar style and adding a “Copy OCR Text” button beside the file size; the button appears only when OCR text is available and reuses the context-menu copy behavior plus the footer button hover treatment.

### Fixes

- Fixed a crash when showing the Deck panel where SwiftUI's async DisplayLink renderer could resolve dynamic NSColor providers outside Swift 6 default MainActor isolation and terminate with `_dispatch_assert_queue_fail` / `EXC_BREAKPOINT`; dynamic light/dark adaptive colors now use a shared nonisolated helper while preserving the existing appearance.

- Fixed a crash when opening the sidebar with PDF file items on the first screen of history, where QuickLook thumbnail callbacks could violate Swift 6 default MainActor isolation and terminate with `_dispatch_assert_queue_fail` / `EXC_BREAKPOINT`; PDF thumbnails still use QuickLook, with results safely marshalled back to the main thread before updating cache and UI.

- Fixed pale square artifacts appearing in the four rounded corners of the main panel when Delete Confirmation was enabled and the system delete prompt appeared; the confirmation still uses the system NSAlert while avoiding the rectangular dimming layer automatically added by SwiftUI `.alert`.

- Fixed LAN receives of symlink-containing DMG/app-bundle archives where the UI could report failure while extracted files remained on disk; archives now extract into a transactional staging directory and are committed only after extraction and full safety validation succeed, with automatic cleanup on failure, rejection, or missing confirmation UI, plus startup cleanup for stale staging directories.

- Fixed AI chat spacing where the assistant's first reply line could sit too close to the user's message, and unified the vertical layout for the thinking dot, first streamed token, and regular messages so the first token no longer jumps upward toward the input field.

- Fixed a crash when searching under the Files tag where an FTS filtered query could trigger Swift 6 concurrency isolation checks and fail with `_dispatch_assert_queue_fail`; search results and filtering behavior are unchanged.

- Fixed noisy security-mode startup logs where tolerant reads of mixed plaintext/encrypted history could report expected decrypt-probe failures as errors; real migration, encrypted-blob, and cloud-sync decryption failures still report normally.

- Fixed fuzzy, regex, and mixed search reliability in security mode by ranking against decrypted lightweight search snapshots and preserving type/tag filters in the security-mode FTS fallback path, without changing the search UI or result presentation.

- Fixed semantic embedding backfill repeatedly rescheduling the same pending rows when encountering textless images, binary items, or temporarily unembeddable records; Deck now writes skip markers for those rows and continues advancing so later text items can still rebuild embeddings.

- Fixed semantic embedding backfill in security mode potentially indexing Base64 ciphertext as plaintext when background Keychain decryption is temporarily unavailable; decrypt failures are now kept retryable, preventing unusable ciphertext vectors and reducing background CPU churn during repeated retries.

- Fixed an unnecessary main-thread `NSImage(pasteboard:)` decode and PNG re-encode when copying PNG, TIFF, JPEG, or other supported image pasteboard data that already provides primary bytes; Deck now uses the image fallback only when primary image data is missing, reducing memory spikes and UI stalls for large image copies.

- Fixed legacy rows with empty `unique_id` potentially receiving a different UUID during background metadata backfill than the one already assigned to the visible item; backfill now reuses the pending UUID from the read path so later delete, sync, and lookup operations by unique id remain consistent.

- Fixed the cached UPSERT statement lifecycle when SQLite returns `SQLITE_SCHEMA`: Deck no longer finalizes the statement before the deferred reset / clear runs, and instead resets/clears first, finalizes the cached statement afterward, and prepares a fresh one on the next write to avoid undefined behavior during schema-change scenarios.

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.4.4/Deck.dmg)

<!-- release-changelog-bot:tag:v1.4.3 -->
## v1.4.3 — v1.4.3 | herculean

- **Tag:** `v1.4.3`
- **Published:** 2026-04-26T11:12:36Z

### Release notes

<p align="center">
  <a href="https://deckclip.app/download" rel="noopener noreferrer" target="_blank">
    <img width="1525" height="896" alt="Deck" src="https://github.com/yuzeguitarist/Deck/raw/main/photos/Deck.webp" style="max-width: 100%; height: auto;" />
  </a>
</p>

---

## Release Notes v1.4.3

## Improvements

-   Deck received a minimal P0 SQLite optimization pass for clipboard history. FTS now updates only when `search_text`, source app name, custom title, or encryption state actually changes, so lightweight operations such as tagging items or toggling temporary state no longer delete and rebuild full-text index entries. This reduces SQLite WAL write amplification, tokenizer work, and checkpoint pressure. In secure mode, Deck also stops maintaining unusable ciphertext FTS entries, and FTS rebuilds skip encrypted rows. Batch insert paths no longer run a per-item `SELECT count`, reducing database load during imports, sync, and restore flows. The secure-mode semantic-vector cache migration now probes encryption state silently as well, preventing expected plaintext-probe misses from being logged repeatedly as `authenticationFailure` errors.

-   Based on eight Instruments traces, Deck prioritizes the heaviest rule-search, code-language rule-search, encrypted-database rule-search, and SwiftUI update-storm hotspots. Language-rule filtering now narrows candidates with cheaper type, app, date, and size checks before warming the code-language detection cache only for text-like items that can still match, avoiding repeated `detectCodeLanguage` work for records that other rules will discard anyway. The bottom ambient bar also reduces per-frame string allocation and lowers its decorative animation cadence to a more conservative 10fps, cutting SwiftUI text-layout and AttributeGraph update pressure without changing behavior or functionality. The background-copy / pure-background traces were dominated by MultipeerConnectivity system send/wait threads, so those paths were intentionally left untouched to avoid regression risk in an OS-owned stack.

-   Based on cold-start panel query and memory traces, Deck now commits a smaller first-screen history snapshot first and defers total-count calculation until after the panel has rendered, preventing `COUNT(*)` from competing with the initial SQLite list query during panel open. Type/tag-filtered history pages also gain composite indexes matching the `timestamp DESC, id DESC` ordering to reduce extra scans and sorting during filtered pagination. At the same time, horizontal-card thumbnail cache limits have been tightened, while image file-size lookup, Base64 image detection, smart-text analysis, and link metadata loading now run later at lower priority. This avoids triggering image decoding, string scanning, network metadata parsing, and SwiftUI layout pressure all at once, making the cold-start panel appear faster with smoother CPU peaks and more bounded memory usage.

-   Deck has gone through a major Swift 6 concurrency cleanup pass: under `SWIFT_STRICT_CONCURRENCY = complete` with default `MainActor` isolation, more than 300 Swift Concurrency compiler diagnostics were eliminated across main-actor isolation, `Sendable` boundaries, `@Sendable` closure captures, SQLite background queues, Socket / LAN / iOS Sync / OCR / Script Plugin / Orbit Bridge paths, and other high-risk async code. Many places that previously “worked” but were already flagged by the compiler as potential data-race boundaries have been tightened with clearer actor ownership, immutable snapshots, queue-owned state, or controlled background-safe entry points; the final clean build now reports zero concurrency diagnostics.

-   After switching the main target to Swift 6, Deck received an additional runtime-isolation hardening pass for default `MainActor` isolation. Background entry points such as clipboard polling, DeckClip sockets, SQLite inserts and statistics queries, semantic-vector table recovery, code highlighting, OCR, NSItemProvider drag/share representations, iOS Sync, the AI OAuth callback server, CloudKit sync, DirectConnect, and Multipeer LAN transfer now avoid creating actor-isolated closures that libdispatch, Network.framework, or CloudKit later execute on background queues. These paths now use nonisolated closure factories, immutable snapshots, explicit `Task { @MainActor ... }` hops, or queue-owned nonisolated helpers, fixing Swift 6 runtime crashes such as `_dispatch_assert_queue_fail` / `_swift_task_checkIsolatedSwift`; the DeckClip socket path also avoids the read-event storm and memory blow-up that could happen when the socket callback returned before consuming data. Both Debug and Release main-target builds now pass under Swift 6.

-   Continued cleaning up low-risk compiler warnings: Accessibility-related `AXUIElement` / `AXValue` / `CFArray` casts now use the more explicit `unsafeDowncast` instead of generic `unsafeBitCast` across clipboard, context-aware ranking, cursor assistant, and IDE Anchor paths. Fixed-size C character buffers for process paths, hardware model names, and LAN addresses are now truncated at the null terminator and decoded as UTF-8 instead of using the deprecated array-based `String(cString:)`. These changes preserve behavior while keeping Xcode 26 / Swift build output cleaner and making low-level bridging boundaries clearer.

-   Deck’s smart text detection now prioritizes structured Markdown signals such as headings, lists, task lists, tables, and fenced code blocks, preventing Release Notes-style Markdown documents from being misclassified as Shell or TypeScript because of weak English words like `source`, `as`, `done`, or `fi`. Shell and TypeScript detection has also been tightened so those languages require clearer code evidence such as shebangs, command-line structure, `interface {}`, `type =`, or `: string;`. Long-text detection now uses a more stable sampling and cache strategy, with lightweight prechecks before Markdown regex work to reduce repeated string scanning, CPU spikes, and energy usage while scrolling, previewing, and analyzing content in the background.

-   Smart-content analysis cache entries are now tied to the content version, item type, and instant-calculation setting instead of only the clipboard item ID, preventing stale Markdown / code-language / calculation results after OCR, rule processing, or content updates. Markdown checks also reuse the code-language result from the same analysis pass to avoid duplicate scans. HTML / XML detection now requires stronger structural tag and attribute evidence, so short snippets, Markdown documents, and angle-bracket-wrapped URLs are less likely to be misclassified by weak HTML signals, improving both accuracy and CPU behavior while scrolling, previewing, and analyzing in the background.

-   Markdown space-bar previews now use a more efficient TextKit rendering path that preserves original line breaks and supports common syntax such as headings, dividers, lists, blockquotes, code blocks, bold / italic text, and links. Blockquotes are rendered as gray italic body text without an extra left quote bar or marker, avoiding broken or repeated visual noise when narrow previews wrap lines automatically. The preview area also matches the edge-to-edge layout and bottom gradient overlay used by text and code previews. In horizontal mode, Markdown cards render their Markdown content directly instead of exposing raw markers like `**`, remove the extra MD badge, and keep the bottom character-count metadata so the body starts higher with more readable space; the preview footer also adds a localized “Copy Plain Text” action with a tooltip so Markdown can be copied in a more readable plain-text form.

-   Markdown previews can now detect and render GitHub-style tables, including headers, separator rows, left / center / right alignment, escaped pipes, and pipes inside inline code, with lightweight truncation guards for large tables and localized labels for hidden rows and columns. Space-bar previews show tables as readable grids with horizontal scrolling and bottom scroll padding, while horizontal cards keep their existing Markdown card rendering instead of being converted into table cards, preventing list content from being rewritten incorrectly. Divider rendering has also been changed to a true single-line visual rule, fixing cases where `---` wrapped into several long lines, and spacing around tables and dividers has been tuned; table rows now adapt their height based on per-row content so short rows stay compact and longer rows can grow modestly, while the table layout is calculated once to avoid repeated column-width, row-height, and plain-text fallback work that could spike CPU during preview.

-   The Markdown preview footer’s “Copy Plain Text” action now uses a lightweight Markdown-to-text path instead of rerendering the document through the full rich-text pipeline just to extract plain text, reducing CPU churn from fonts, paragraph styles, AttributedString conversion, and table fallback rendering. The converted text is marked as Deck-derived when written to the system pasteboard so the clipboard poller does not reprocess it as an external copy and rerun type detection, smart-text analysis, or semantic-vector generation; Deck also inserts the derived plain-text item directly into history so the system pasteboard and Deck’s history stay in sync.

-   The shared custom hover tooltip used by the top-right button group and the vertical bottom button group now gets a stronger gray outline in Light Mode. When the app is docked at the top and the popup background is close to pure white, the outline improves contrast and visual separation. Dark Mode keeps the existing appearance unchanged.

-   DeckClip’s terminal login form now supports Ctrl+U and Command+Delete / Command+Backspace to clear the current input line instantly, so pasted API keys or base URLs no longer need to be deleted character by character; AI Chat also adds a new `/login` slash command that opens the login setup directly from chat, then returns to AI Chat and refreshes the current provider state when the login flow finishes or exits.

-   Deck MCP now adds `deck_list_clipboard_items` and `deck_search_clipboard_items`, returning structured `items` so AI clients can continue working with metadata such as `item_id`, type, source app, timestamp, tag, and text snippets. `deck_read_latest_clipboard` has also been upgraded to include full metadata for the latest item instead of text only. These read-only calls use lightweight list/search paths and bounded text payloads to keep large images, long text, and malformed JSON responses from affecting app stability.

-   Deck MCP now adds `deck_list_script_plugins`, `deck_read_script_plugin`, and `deck_run_script_transform`, allowing external agents to discover installed Deck script plugins, inspect a plugin’s `manifest.json` and primary files, then safely run existing script plugins for deterministic text transforms, cleanup, formatting, and templating. Plugin reads reuse Deck’s existing file-count, file-size, and total-character guards; script execution uses the async transform path so it does not block the main thread; unauthorized network plugins are refused with an explicit permission response instead of being silently authorized, keeping Deck’s local automation capabilities reusable within controlled boundaries.

-   DeckClip AI Chat now lets you press Shift+Tab to switch between the default Agent approval mode and YOLO auto-approval mode; the current mode stays visible in the header, and tool execution keeps the normal status flow in YOLO mode with an inline “YOLO mode” marker instead of extra approval messages.

-   Deck’s context-aware ranking is now smarter than a simple frontmost-app type preference pass: it expands the candidate window first, then applies weighted ranking using content type, freshness, detected code language, source app / IDE, source anchors, and task keywords extracted from the active window title so items that better match your current work are more likely to surface first. Deck now captures a context snapshot before the panel takes focus, and both the history list and Quick Paste reuse that same snapshot to avoid first-frame reorder jumps or mismatched paste order after the active window title drifts; code-language weighting in ranking also uses a lightweight sampled path instead of triggering the full smart-text analysis pipeline for a small scoring bonus.

-   Based on real profiling of list scrolling and text-analysis hotspots, Deck now avoids repeatedly hashing large text blocks for task keys by using a stable content-version token instead; it also caches code-language detection, reuses precompiled regexes for code-snippet checks, and limits long-text code classification to sampled content, reducing repeated string scanning and CPU churn while scrolling, previewing, and quickly browsing history.

-   Deck now reduces wakeups in global shortcut monitoring for copy detection, paste queue shortcuts, and Typing Paste. Normal typing no longer keeps Deck awake for every key press; instead, Deck first watches modifier changes and temporarily arms `keyDown` monitoring only while a Deck-relevant chord is possible, with current-modifier reconciliation and automatic cleanup as guardrails. On launch, Deck logs an `InputMonitoringStartup` line describing the active copy and Deck-shortcut monitoring strategy for easier verification.

-   Based on Instruments Allocations traces for large-image previews, Deck now avoids eagerly loading full image payloads on the main thread. File-based images and blob-backed images prefer background path/blob downsampling through controlled loading paths, while ImageIO source caching, maximum preview decode size, and the global image-preview cache have all been tightened to reduce transient CGImage, CG raster, CoreAnimation, and IOSurface memory. Viewing, zooming, and switching large images should now keep memory growth more bounded while preserving clear previews and reducing repeated decode-related CPU and energy spikes.

-   Based on a WLAN file-transfer CPU trace, Deck no longer resolves full payload data before sending file URLs over LAN sharing. It now snapshots only the file paths and lets the resource-transfer path handle the actual payload, avoiding extra large-file IO, memory pressure, and CPU churn before transfer starts. LAN-received file items also skip semantic-vector generation after being saved, preventing low-value `NLEmbedding` / CoreNLP work on file-path content while keeping regular filename/path keyword search available. This makes post-transfer CPU spikes and energy usage more controlled for large file transfers.

-   Regular keyword, fuzzy, and mixed search now rank candidates using lightweight database rows and search snapshots first, only materializing the `ClipboardItem` objects that are actually needed after the final hit order is known. This avoids building full clipboard-item graphs, type checks, and smart-analysis-related work for candidates that the fuzzy scorer will discard. FTS and SQL LIKE queries also push type and Tag filters down into SQLite where possible, with safer null handling for custom titles; the decrypted search cache now has a total-cost limit, and fuzzy lowercased-text lookup avoids per-search temporary dictionaries, keeping allocation and CPU churn more controlled during search, pagination, and fast typing.

-   Based on Xcode Instruments traces for encrypted mixed search, Deck now reuses the persisted content type from the database when materializing history and search results, instead of rerunning code-language detection, URL classification, and smart-text scans for every row. Secure-mode search also avoids repeated preference checks and redundant decrypt-branch work. Horizontal image cards no longer read or decrypt full-size images from SwiftUI body just to show dimensions; pixel size is collected during background downsampling instead, and both thumbnail decoding and smart-text analysis now use more conservative concurrency gates to reduce main-thread stalls, memory spikes, and energy churn while searching, scrolling, and opening the panel.

-   Based on Instruments traces for record export, database encryption/decryption, and the statistics page, Deck now exports clipboard history directly from persisted database metadata and full payloads instead of rebuilding full clipboard-item objects and rerunning type detection or code-language analysis for every row. Security-mode migration now only touches rows whose encryption state actually needs to change, while reusing a single resolved encryption key and prepared database update statement to reduce Keychain access, SQL compilation, and duplicate detection work. The statistics page also uses fewer aggregate SQL queries to compute total / today / week counts and the last-7-days activity distribution, with cached source-app name resolution to reduce database scanning, Bundle IO, allocations, and CPU churn when opening statistics.

-   Based on SwiftUI traces of AI Chat streaming replies, Deck now reduces the refresh and auto-scroll frequency for streamed text and avoids animating every small bottom-scroll update, cutting repeated `LazyVStack`, root-geometry, and SwiftUI transaction layout pressure. The streaming text accumulator now appends incrementally instead of rebuilding the full response with repeated `joined()` work, and the streaming message view no longer creates temporary `AIMessage` values for every refresh. The ChatGPT subscription SSE path also parses tool calls while reading the stream instead of caching the full response body and parsing it again at the end, keeping memory usage, CPU churn, and energy impact more controlled during long replies.

-   Deck now defers parts of its non-first-frame setup until they are actually needed, while also removing duplicate launch cleanup and redundant event-dispatch startup work for a lighter and more stable startup path.

-   Deck’s DMG installer now applies a custom icon to the final installer file and defaults to the light installer icon, avoiding dark installer shells being shipped to all users when the packaging machine is in Dark Mode.

-   In the vertical list, URL items now show the source app's icon by default; once the site's favicon loads it replaces the app icon automatically, and falls back gracefully if the favicon cannot be fetched.

-   URL preview cards now use the same subtle gray globe placeholder as the preview header when a site favicon cannot be fetched, replacing the bright blue link icon for a cleaner and more consistent card grid.

-   In vertical mode, the search-and-tag area now uses the same layered overlay structure as the bottom toolbar: the history list continues underneath, a stronger gradient blur material creates a soft transition in the middle, and the interactive search/tag controls stay on top; the bottom toolbar also gets a heavier gradient blur, cleaner queue-bar alignment, lighter copy density, and slimmer hover states for a more unified top-to-bottom experience.

-   Deck’s bottom ambient bar has been upgraded from ASCII to a more refined braille-style animation, using different motion effects in each state to create a more fluid and layered visual experience.

-   Plain-text previews now use the same bottom blurred overlay layout as code previews, creating a more unified and cleaner visual style across the preview area.

-   Refined the header hierarchy of horizontal cards: the source app icon on the left is now slightly larger, while the spacing between the app name and timestamp has been tightened a bit to make the card header feel clearer, more balanced, and more comfortable to scan.

-   Refined the Tag context menu alignment and rename flow: the bottom color picker now uses tighter insets, spacing, and dot sizing so its left and right edges align more cleanly with the menu items above; when renaming a Tag, clicking outside the inline text field now commits the edit in addition to Return, while Esc still cancels, making the interaction feel more natural and polished.

-   Improved the rename experience for history-item titles: the custom-title editor now supports longer names and restores standard editing shortcuts such as Command+A / C / V / X; it also fixes placeholder centering, the occasional invisible first pinyin keystroke when entering rename mode with a Chinese IME, and horizontal offset issues after editing long titles, making title editing feel more stable and natural in both Latin and CJK input methods.

## Fixes

-   Typing Paste is now a cancellable safety session with multiple panic-stop protections. While simulated typing is running, pressing Esc, Ctrl+C / Ctrl+X, Command+C / Command+X, Command+., triggering the Typing Paste shortcut again, or pressing Deck’s main-panel / AI Chat hotkeys immediately stops the active simulated input. Mouse clicks, scrolling, screen lock, display sleep, system sleep, and session switching also hard-stop the session. Deck marks and ignores its own synthetic input events so automated keystrokes do not cancel themselves, and oversized text is blocked before starting so an accidental shortcut no longer leaves the system stuck in a long, uncontrollable typing run.

-   DeckClip history reads now require the system authentication prompt in secure mode, so `read`, `clipboard.latest`, `clipboard.list`, and `clipboard.search` can no longer bypass user verification before accessing clipboard history; the new prompts are localized. `deck://paste` deep-link paste now also requires authentication and fixes a case where, after successful verification, Deck could fall back to a stale previous app and jump to or paste into the wrong window. With `targetBundleId`, Deck now pastes only into that explicit running target app and returns a clear error if it is unavailable; without a target, `deck://paste` safely copies the item to the system pasteboard instead of injecting Cmd+V. In parallel, background crypto now fails closed on Keychain errors and creates a key only when it is definitely missing; context-aware ranking clamps abnormal window-title lengths; DeckClip socket I/O, auth, and HMAC validation have moved off the main thread to keep high-frequency local CLI traffic from stalling the Deck UI. DeckClip AI Chat streaming-session state is now lock-protected as well, so disconnects, write failures, cancellation, and chat open/send/close commands no longer read or mutate the current session ID across queues unsafely, preventing leaked chat sessions and possible concurrent `String` access crashes.

-   Fixed a CPU hang where Markdown files or Markdown text containing extremely long continuous URLs, long unbroken tokens, or unusually large content could keep CoreText / TextKit busy during preview layout and make the preview window appear frozen. Markdown file preview, horizontal-card preview, and “Copy Plain Text” now all use bounded file reads; inline-link parsing limits label and URL scanning; rendering now display-truncates long unbroken tokens as “head + … + tail” instead of handing hundreds of thousands of characters directly to the system text layout engine. Large Markdown documents also avoid forced full TextKit layout on the main thread, warming only the visible leading range and estimating scroll height so pathological Markdown can still be opened, scrolled, and closed without stalling the UI.

-   Fixed an issue where a newly copied item might not appear at the top of the panel when the panel was opened immediately after copying, or while the panel was still animating in. Deck now treats the data layer as visible as soon as presentation begins; newly saved clipboard items are inserted into the live UI immediately and merged into the prepared first-screen snapshot so the animation-completion commit cannot overwrite fresh content. The sound feedback timing is unchanged.

-   Fixed an issue where the “Launch at Login” switch in Settings could jitter back and forth and drive high CPU usage after replacing `/Applications/Deck.app`, changing the version metadata, or while macOS was briefly refreshing login-item state. Deck now separates user-initiated switch changes from system-state synchronization: `SMAppService` register / unregister is called only when the user toggles the switch, while programmatic refreshes simply reflect the actual login-item status, preventing a SwiftUI `onChange` feedback loop. Startup Accessibility permission prompts also get an additional confirmation pass to reduce false “permission lost” alerts while LaunchServices / TCC is catching up after an app replacement.

-   Fixed an issue where pressing Enter during an AI streaming reply would accidentally clear the input draft; now messages are only sent when the input is not a slash command and the chat is in Ready state. If the reply is still streaming, pressing Enter shows a warning instead of clearing the input.

-   The DeckClip client now proactively resets broken connections when command execution encounters transport errors (response ID mismatch, read failure, etc.), preventing subsequent commands from reusing a damaged channel; quick commands get a 10-second timeout and regular commands a 30-second timeout to avoid hanging on unresponsive connections, while AI streaming commands remain un-timed to accommodate long replies.

-   The transport layer now enforces a maximum receive buffer size of 16 MB + 6 bytes (protocol header), preventing unbounded memory growth from abnormally large or malicious frames; exceeding the limit returns a clear protocol error and closes the connection. The App-side send path also adds a matching 16 MB payload-size check so it never sends a frame that exceeds the protocol definition.

-   Added localized strings for new protocol errors such as "receive buffer too large" across Chinese (Simplified / Traditional), English, Japanese, Korean, and other supported languages, preventing hardcoded Chinese error messages from appearing to non-Chinese users.

-   The `app_support_dir` function now falls back to `/tmp/deckclip` when the `HOME` environment variable is missing, preventing a crash from an empty path in unusual environments.

-   Tightened the security boundaries for AI web fetch, script-plugin fetch, and the DeckClip local protocol: plugin IDs can no longer escape the scripts directory through `.` / `..` normalization, DeckClip request signatures now cover the full args payload, and AI web_fetch plus plugin fetch now block localhost, private-network, link-local, and `.local` targets. The related rejection messages are also localized.

-   The preview window now repositions immediately when the main panel height changes in horizontal or vertical mode, instead of staying anchored to the old height and getting covered by the panel; reopening the preview still lands in the correct position as before.

-   Fixed a drag-preview cropping issue for the always-on-top panel: when dragging the currently focused clipboard card, Deck now captures the full outer shape of the card instead of clipping the selection halo, eliminating the extra edge artifacts that could appear around the four rounded corners.

-   Fixed a layering issue when dragging cards with the always-on-top panel enabled: Deck now temporarily relaxes the panel window level only during the drag so the system drag card can appear above the panel, then immediately restores the original always-on-top level afterward, preserving the normal behavior of staying above the Dock and regular windows.

-   Fixed a visual flicker affecting clipboard items both when a drag begins and when a cancelled drag animates back into place. Deck now removes the extra local opacity transition on the source item, making drag previews, cancel-return animations, and final settle states feel more stable and natural in both the card grid and vertical list layouts.

-   When quick actions such as “Open in IDE” or “Show QR Code” appear in the preview footer, the footer now keeps a consistent height instead of expanding the bottom area; these actions also now get the same hover highlight feedback as the rest of the panel controls.

-   The preview footer no longer shows type information for links, code, and other content, and non-image previews no longer show size; only image previews keep the size indicator, while the footer now shows the copied time using the system’s current regional and time preferences and removes the “Space to close” hint for a cleaner overall layout.

-   The space-bar link preview now uses the same bottom gradient overlay pattern as the code/text previews instead of a gray hard-cut footer; the image preview has also been restructured into three layers: a gray checkerboard transparency background at the bottom, the image content in the middle, and the bottom gradient with the top-right zoom controls on top. This keeps the exposed area visually continuous and softer when the image is scrolled downward or sits close to the footer, while also making transparent regions easier to read.

-   When switching previews between differently sized content such as images and text, Deck now uses a more stable direct transition to avoid incorrect scaling, drifting, or leftover transition artifacts.

-   Fixed an issue where switching from an image preview to a plain-text preview could cause the footer bar to overlap the last few lines of text. The text preview now preserves its bottom scrolling inset consistently through the first frame and subsequent geometry updates, ensuring the end of long text remains fully reachable and visible.

-   In vertical mode (left or right docked), expanding the search field no longer pushes the entire panel content horizontally, and content near the screen edge is no longer clipped out of the visible area.

-   Fixed several scrolling and navigation regressions introduced by layout changes: Ctrl+A / Ctrl+E now correctly scroll to the list head/tail with full visibility; reopening the panel automatically navigates back to the first item; the automatic centering scroll after clicking a history item is now delayed so the first click no longer shifts the target under your cursor and interferes with double-clicking; scroll wheel navigation in both horizontal and vertical modes has been restored.

-   Fixed a regression where panel shortcuts (such as Command + , to open settings) stopped working after switching between horizontal and vertical layouts. The root cause was that old and new view instances shared the same handler key during the transition, causing the old instance to accidentally remove the new instance’s listener; this is now resolved by using instance-unique keys.

-   Fixed a crash that occurred immediately after sending messages in all AI modes (assistant, subscription, API, and one-click configuration). The root cause was that the `AsyncThrowingStream` returned by `provider.sendMessage(...)` was created within a `TaskLocal.withValue` scope in `AIService.sendUserMessage`, causing task lifecycle interleaving and a `swift_task_dealloc` crash; this unnecessary `withExecutionContext` wrapper has been removed while preserving the execution context setup for actual tool execution.

-   Fixed a set of main-thread isolation and timer-boundary issues across the AI chat panel, preview window, and LAN sharing verification alerts, reducing related Swift concurrency build warnings and making panel resizing, scroll observation, and countdown updates more stable.

-   Continued addressing a batch of low-risk Swift concurrency boundary issues: tightened the clipboard service’s power-state observation, pause-resume timer, and feedback sound paths to avoid crossing non-main-thread boundaries; removed shared `ISO8601DateFormatter` concurrency risks from AI conversation storage and OAuth persistence; and moved smart rule import/export onto a cleaner codec-only boundary, reducing related build warnings and improving overall stability.

-   Tightened the IDE path recognition logic to no longer treat the root directory or directory paths as valid file anchors, preventing clicks on "Open in IDE" from unexpectedly opening the Macintosh HD root directory.

-   Fixed button tooltips being invisible under the always-on-top panel: when the panel is set above other apps, the native system `.help(...)` tooltips on panel buttons were rendered below the panel window and completely hidden. Deck now replaces these with an independent borderless floating window that is always ordered one level above the panel, so it can never be clipped or obscured; the tooltip defaults to showing directly above the button and automatically avoids screen edges. Short labels display in a single line at natural width, while long labels wrap automatically. The rounded bubble has its excess shadow removed and the gray square corners that leaked outside the rounded shape have been eliminated, giving the tooltip a cleaner, tighter edge. Missing localization entries such as "支持 Deck 开发" have also been added so tooltips display correctly in the English interface as well.

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.4.3/Deck.dmg)

<!-- release-changelog-bot:tag:v1.4.2 -->
## v1.4.2 — v1.4.2 | Oops

- **Tag:** `v1.4.2`
- **Published:** 2026-04-18T06:48:36Z

### Release notes

<p align="center">
  <a href="https://deckclip.app/download" rel="noopener noreferrer" target="_blank">
    <img width="1525" height="896" alt="Deck" src="https://github.com/yuzeguitarist/Deck/raw/main/photos/Deck.webp" style="max-width: 100%; height: auto;" />
  </a>
</p>

---

## Release Notes v1.4.2

### Added

-   Deck AI can now do more than create Smart Rules. It can also list, read, modify, and delete existing rules, and both the in-app approval sheet and the `deckclip chat` approval overlay now show rule previews, change summaries, and delete warnings.  

-   `deckclip chat` now shows an approval overlay for actions that require authorization, including creating, modifying, or deleting script plugins, writing or deleting clipboard items, and generating Smart Rules. You can review the summary and preview in the terminal, then approve with `Y / Enter` or reject with `N / Esc`.  

-   Patch previews for script plugin changes are now structured by file, hunk, and added or removed lines. Both regular diffs and `*** Begin Patch` style patches are supported, and file moves are recognized with old-to-new path mapping.  

-   The approval overlay now applies basic syntax highlighting to `manifest.json`, JSON, and JavaScript blocks, and long previews can be scrolled independently.  

### Improvements

-   “Auto delete after” now supports a minimum of 1 minute. Within the first 5 minutes, you can choose 1 / 2 / 3 / 4 / 5 minutes directly, while values above 5 minutes continue to use the original 5-minute step cadence. AI-generated or AI-modified rules now support the same 1-minute minimum.  

-   During clipboard search, memory saving, session context reads or writes, script plugin execution, and similar steps, the chat UI now shows clearer in-progress status text in both the header and transcript tail. Repeated searches also display an incrementing count to reduce the feeling that the session is stuck.  

-   When the approval overlay opens on macOS, Deck temporarily switches to an ASCII-capable keyboard layout and restores the previous input source afterward, making `Y / N` approval shortcuts more reliable under Chinese IMEs and similar input methods.  

-   The `deckclip chat` implementation has been split into `app_impl`, `approval`, `render`, and `tests` modules, making future iteration on chat and approval features easier to maintain.  

-   Rebalanced LAN sharing discovery behavior across background, display sleep, and connection state transitions. Instead of frequently pausing, resuming, or rebuilding networking objects, Deck now prefers to keep the discovery path stable, reducing crash risk first while also avoiding the overhead caused by repeated teardown and rebuild churn.  

-   Clipboard fallback polling now adapts its interval to user inactivity, Low Power Mode, and thermal state, and avoids redundant rescheduling when nothing changes, reducing unnecessary wakeups while Deck is idle in the background.  

### Changes

-   Changes to the LAN sharing device name now take effect externally the next time LAN sharing is turned back on, and “Refresh Search” now preserves the current session and discovery path instead of rebuilding the entire LAN sharing stack just to refresh the list.  

-   Deck now automatically scans for app binary architectures that are unnecessary for the current Mac right after launch and immediately cleans them up when removable content is found. This no longer depends on running database cleanup or one-click maintenance first. The related Settings copy has been updated to reflect automatic cleanup on launch, while the one-click maintenance path now serves as a fallback and secondary pass.  

-   When you clearly express an intent like delete, modify, write, or create, Deck AI now proceeds directly with the matching tool call and leaves the final confirmation to the system approval sheet. It no longer asks you to repeat yourself, type a fixed confirmation phrase, or go through extra rounds of verbal confirmation. Actions such as deleting a script plugin, deleting clipboard content, or overwriting an existing plugin now continue immediately when the target is clear and uniquely identified, and only ask follow-up questions when the target is ambiguous or has duplicate or near-matching candidates.  

### Fixes

-   Fixed an issue where Shortcuts / App Intents metadata could disappear, stop registering, or even crash during launch when complete strict concurrency checking was enabled together with default `MainActor` isolation. The related static metadata is now explicitly marked as nonisolated, and clipboard entity mapping only hops back to the main actor when reading truly UI-isolated properties, preserving both Swift 6 concurrency safety and stable Shortcuts registration.  

-   Updated and completed localization coverage for the binary slimming settings so the new semantics—automatic cleanup on launch and fallback slimming during one-click maintenance—stay consistent across languages, while removing the old wording that described launch-time scan-only behavior or slimming as part of maintenance only.  

-   Resolved `rand` and `lru` related security advisories in `deckclip` by replacing the aggregate `ratatui` dependency with direct `ratatui-core`, `ratatui-crossterm`, and `ratatui-widgets` dependencies, removing the old `termwiz` transitive chain. This is an internal security and compatibility update only and does not change the Swift app integration contract, runtime behavior, or UI.  

-   Fixed an issue where the Deck CLI PATH installer could guess the wrong zsh startup file, mistake a plain directory string for an existing PATH setup, or even create a new shell startup file when falling back to `~/.local/bin`. It now resolves the actual zsh startup file first and only appends Deck’s managed PATH line to an existing writable file; if the target cannot be determined safely, it skips the update instead of touching the user’s shell config.  

-   Fixed an abnormal memory growth issue in a specific background scheduling path, reducing memory usage from 56GB+ to around 30MB.  

-   Fixed a concurrency issue where Smart Rule auto-delete could retrigger during cancellation and rescheduling, preventing background task storms and abnormal resource usage.  

-   Improved the stability of update hash record write, read, and tamper-validation flows to reduce the risk of sporadic update verification issues.  

-   In `deckclip chat`, Command + Delete and Control + U now follow normal terminal behavior by deleting only the text before the cursor on the current line instead of wiping the whole line. If the cursor is already at the start of the line, the previous newline is no longer removed by mistake.  

-   Fixed an issue in `deckclip chat`/`deckclip` where switching input sources during unfinished Chinese IME composition after opening the `/` command palette could trigger an empty terminal paste event and incorrectly inject the latest clipboard text into the input field. When the terminal actually pastes normal text, Deck now prefers the terminal's real pasted content instead of the internal chat clipboard fallback. Slash suggestions now stay intact, and the newest clipboard entry is no longer pasted unexpectedly.  

-   In `deckclip chat`/`deckclip`, very large pasted text is now collapsed into a compact placeholder block inside the composer with a small summary card shown above the input, preventing the editor from being flooded by the full payload. The full original text is automatically restored on submit, so no context is lost and normal editing around the pasted block remains intact.  

-   Fixed an issue where `deckclip chat`/`deckclip` could intermittently hit a protocol error and abort the first reply in terminal follow-output mode when local models responded very quickly. Deck now completes the session acknowledgment before consuming later streaming events, making fast local setups such as LM Studio more reliable.  

-   Wrapper markers in machine-generated patches are now filtered out, so the approval overlay no longer dumps large blocks of raw patch wrapper text and is easier to read overall.  

-   Streaming output, approval waiting states, and short status prompts now stay aligned more consistently near the bottom of the viewport, and existing conversation content no longer shifts upward unexpectedly while generating.  

-   Fixed the double-scroll behavior in Space-triggered code previews and rebuilt the top language header. Code previews now use a single scrolling path, while the language strip has been refined into a tighter frosted bar with a more natural blur transition. Labels such as `TypeScript` were also fine-tuned to reduce hard clipping and visible edge artifacts near the top.  

-   Fixed an issue where LAN sharing could repeatedly cancel and rebuild the underlying system discovery chain after backgrounding, display sleep, manual refresh, or peer state changes, which could lead to unexpected exits or crashes. This update prioritizes reducing that high-risk lifecycle churn.  

### Tests

-   Added Smart Rule AI tool lifecycle tests covering list, read, modify, and delete flows, plus validation for the 1-minute `auto_delete` minimum to reduce regression risk around rule editing and auto-delete behavior.  

-   Added regression coverage for render performance, input layout, input history, attachment restoration, slash command normalization, approval overlays, streaming states, and line-deletion behavior to strengthen `deckclip chat` test coverage.  

-   Added regression tests for terminal paste handling to ensure that empty paste events triggered while switching input sources during unfinished Chinese IME composition do not corrupt slash queries, and that normal text pastes prefer the terminal's actual pasted text over the internal chat clipboard fallback text.  

-   Added regression tests for large paste handling in `deckclip chat`, covering placeholder collapse for oversized pasted text, full-text restoration before submit, whole-block deletion at placeholder boundaries, history restoration, and input panel height changes to reduce regression risk in both editing and submission flows.  

-   Added regression coverage for Smart Rule auto-delete scheduling and strengthened update hash record read/write and tamper-validation tests to reduce future regression risk.

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.4.2/Deck.dmg)

<!-- release-changelog-bot:tag:v1.4.1 -->
## v1.4.1 — v1.4.1 | contrite

- **Tag:** `v1.4.1`
- **Published:** 2026-04-13T03:38:10Z

### Release notes

<p align="center">
  <a href="https://deckclip.app/download" rel="noopener noreferrer" target="_blank">
    <img width="1525" height="896" alt="Deck" src="https://github.com/yuzeguitarist/Deck/raw/main/photos/Deck.webp" style="max-width: 100%; height: auto;" />
  </a>
</p>

---

## Release Notes v1.4.1

### Added

-   Add `/model` to `deckclip chat` to open the current provider’s model editor and change the model name directly; after saving, the next message uses the new model immediately. You can also press `Ctrl+O` to open the model editor directly.  

### Fixes

-   When the slash command list exceeds the visible rows, it now scrolls with the current selection so every command remains reachable via arrow keys, mouse wheel, and mouse clicks.  

-   The CLI installer now safely appends only to existing writable shell startup files; if `.zshrc` is read-only, it falls back to a writable `.zprofile`; missing files are created only when needed, and existing shell config files are no longer overwritten.

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.4.1/Deck.dmg)

<!-- release-changelog-bot:tag:v1.4.0 -->
## v1.4.0 — v1.4.0 | vinculum

- **Tag:** `v1.4.0`
- **Published:** 2026-04-12T11:43:43Z

### Release notes

<p align="center">
  <a href="https://deckclip.app/download" rel="noopener noreferrer" target="_blank">
    <img width="1525" height="896" alt="Deck" src="https://github.com/yuzeguitarist/Deck/raw/main/photos/Deck.webp" style="max-width: 100%; height: auto;" />
  </a>
</p>

---

## Release Notes v1.4.0

### Added

-   Turn on LAN plain-text sync in Mac settings: use Shortcuts to **pull** the latest downloadable text from your Mac to iPhone, or **push** the iPhone clipboard to the Mac (paste with safeguards against duplicate history entries).  

-   When you install Deck’s **Deck iOS Sync** shortcut, you’ll be **prompted for a pairing code once**; it stays valid afterward.  

-   The AI assistant adds **`save_session_context`**, **`read_session_context`**, and **`delete_session_context`**: each note is a **separate encrypted file on disk** (YAML front matter + long body); only **title + provenance** are injected each turn—load full text via tools to save tokens. Complements **cross-window memory** (≤30-char snippets, fully injected). Toggle per feature in **AI Assistant** settings, with counts and cleanup for expired entries.

-   With **Deck CLI** enabled in Settings, the `deckclip` command-line tool securely drives panels, clipboard, and AI features via a **Unix Domain Socket** — zero network exposure, three-layer local authentication (binary hash + token + HMAC-SHA256). The app auto-installs `/usr/local/bin/deckclip` (or `~/.local/bin`) on launch.

-   `deckclip health`: Check app connectivity.  
  `deckclip write <text>`: Write to the clipboard (supports stdin pipes and `--tag`).  
  `deckclip read`: Read the latest clipboard entry.  
  `deckclip paste <1-9>`: Quick paste by slot.  
  `deckclip panel toggle`: Toggle the panel.  
  `deckclip` (no args): Open the AI chat directly when launched in an interactive terminal.  
  `deckclip chat`: Enter the interactive AI chat with the same real conversation flow as the app, including `/cost`, `/compact`, `/copy`, `/resume`, and `/clear`.  
  `deckclip ai run <prompt>`: Run an AI prompt.  
  `deckclip ai search <query>`: AI semantic search.  
  `deckclip ai transform <prompt>`: AI transform clipboard content.  
  `deckclip completion <shell>`: Generate shell completions.  
  `deckclip login`: Configure Deck AI providers directly in the CLI, including ChatGPT, OpenAI API, Anthropic API, and Ollama.  
  `deckclip version`: Show version info with the ASCII art logo.
  `deckclip mcp serve`: Run the Deck MCP bridge in foreground stdio mode.  
  `deckclip mcp tools`: List the initial MCP tools and their arguments.  
  `deckclip mcp doctor`: Check the Deck App, local socket/token, and client config paths.  
  `deckclip mcp setup --client <claude-desktop|cursor|codex|opencode|all>`: Print or write MCP client config snippets.

-   All commands support the global `--json` flag for JSON output, ideal for scripting and AI agent integration. The CLI automatically follows the app's language (zh-Hans / zh-Hant / en / de / fr / ja / ko), including all `--help` and subcommand help text.


### Improvements

-   Copy-to-clipboard now uses **new sound effects** for clearer, more consistent audio feedback.

-   In **AI Assistant** settings, each provider shows its brand icon beside the label; ChatGPT subscription and OpenAI API use the same OpenAI mark.

-   For **ChatGPT subscription**, requests to the Codex backend now include consistent client identity and structured `User-Agent`, account/session headers, and per-conversation cache keys aligned with the official flow; when reasoning is enabled, encrypted reasoning content is requested like the reference client.

-   **Smart Rule** AI automation can now use **`web_search`** and **`web_fetch`** (same as the AI assistant) to look up or fetch public web content from URLs or keywords; scope stays limited to the triggering item without broader clipboard or local file access.

-   Embedded **sqlite-vec** updated to **v0.1.9** (DELETE and related stability fixes); still built in as a **static amalgamation**, no separate loadable extension required.

-   **AI chat panel** performance and stability: fewer redundant scroll-view resolves during streaming, cheaper newline scanning and full-text materialization in the accumulator, debounced context-usage estimates, safe teardown of tool-approval continuations when switching chats, starting a new chat, or closing the panel, and **lazy stacking** for long transcripts to reduce memory use.

-   **iCloud sync (compile-time flag + pipeline)**: add **`DeckBuildFlags.isCloudSyncCompiledIn`** (default **off**) so CloudKit isn’t touched—no `CKContainer`, no background sync tasks—unless you opt in; works alongside `UserDefaults`. When enabled: immutable **`CKContainer`**, coalesce pending item IDs and **`createRecord` at flush time** to cut duplicate work, and **strong captures** in the materialization path so the in-flight flag can’t stick.

-   **Search & list**: when returning to the default list, **skip redundant** `loadInitialData()` if already in the default state; when fuzzy search needs a wider scan, **scan lightweight `SearchSnapshot`s first** and materialize **`ClipboardItem` only for hits**; editing a custom title **invalidates that item’s cached text** instead of clearing the whole prepared-text cache.

-   **Link preview**: split the top preview into a **subview**; **cache** adaptive text tone (dark/light) per image **TIFF** to avoid repeated luminance sampling.

-   **Feedback email (plain text)**: removed bundled **HTML ticket templates**; composing feedback via the system mail UI now uses a **plain-text body** for easier editing across mail clients, while still auto-attaching **ticket ID**, source, and device/app diagnostics (with localized prompts).

### Fixes

-   When the AI chat panel stays open but you switch to another app or another Deck window, the global shortcut now **brings the panel forward and activates it** instead of hiding it. Press the shortcut again while the chat is focused to dismiss as before.

-   When third-party docs only provide an Anthropic-compatible base URL without `/v1` (e.g. MiniMax), Deck now completes the correct Messages path so requests work; a short hint was added in settings.

-   Fixed Swift 6 concurrency-isolation issues affecting iOS LAN sync, background fetches, and shortcut export, reducing build errors and improving sync stability.

-   **CloudSync & SQLite symbols**: `CloudSyncService` now imports **SQLite** for row `id` subscripts; disambiguate with **`Swift.Result`** when the SQLite module shadows `Result`; materialization uses a **strong capture** so **`isMaterializingPendingSync` can’t get stuck** and block future sync work.

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.4.0/Deck.dmg)

<!-- release-changelog-bot:tag:v1.3.9 -->
## v1.3.9 — v1.3.9 | artum

- **Tag:** `v1.3.9`
- **Published:** 2026-04-02T11:41:12Z

### Release notes

<p align="center">
  <a href="https://deckclip.app/download" rel="noopener noreferrer" target="_blank">
    <img width="1525" height="896" alt="Deck" src="https://github.com/yuzeguitarist/Deck/raw/main/photos/Deck.webp" style="max-width: 100%; height: auto;" />
  </a>
</p>

---

## Release Notes v1.3.9

### TL;DR
-   Deck now automatically compacts older conversation context when an AI chat approaches the context limit, allowing long sessions to continue without manually starting over.

-   While compaction is running, `Compacting...` appears beside the AI dot; once complete, the transcript shows a minimal divider that marks where earlier context was compacted.

-   Deck AI now carries forward the current task direction, key outcomes, and essential tool context after compaction, reducing long-session context breaks.

-   In the expanded AI chat panel, Deck now shows a restrained context usage indicator with a small ring and percentage so you can quickly gauge how close the current session is to the context limit.

-   Deck now batches independent read-only AI lookups within the same turn to reduce waiting time.

-   Clipboard search, plugin listing/reading, skill detail lookup, and web search/fetch can now work together so the AI can gather context faster.

-   Write, delete, plugin-edit, and other approval-sensitive actions remain sequential, so this optimization does not loosen the approval flow.

-   Deck AI is now more reliable during multi-step tasks: it diagnoses issues before changing strategy, reports tool outcomes more accurately, and applies better judgment about action risk levels.

-   When the AI creates or modifies a JavaScript script plugin, Deck now runs a native JSON/JavaScript preflight before showing approval, catching manifest errors, syntax issues, and common runtime incompatibilities earlier.

-   You can now ask Deck AI to generate Smart Rules directly. The AI structures the conditions, actions, and enabled state into a real rule, then saves it through the existing approval flow.

-   When Deck AI is searching the clipboard, reading a plugin, saving memory, or handling other tool steps, the left-side status area now shows the current action more clearly, making waits feel more transparent and polished.

-   Streaming AI replies now render in the final message slot from the start, so finishing a reply no longer causes downward flashes, rebound snaps, or sudden upward jumps of the whole text block.

-   Reduced repeated focus grabs in the AI chat composer, lowering noisy system input-method warnings during window activation or Chinese IME switching and making text entry feel more stable.

-   The AI composer now hides its placeholder promptly during Chinese IME composition and fixes cases where confirming a candidate could insert a number instead, making Chinese text entry cleaner and more stable.

-   The send button aligns to the bottom when the composer grows with multiple lines; it stays vertically centered with the single-line field when empty, keeping the default look consistent.

-   Onboarding and Settings → Storage can import CliperX history read-only (including common UsePasteAgain layouts) alongside other sources; rows use bundled brand artwork with continuous corner masking so each source is easy to recognize.

### Added
-   When an AI conversation approaches the context limit, Deck automatically condenses earlier context into a summary so long-running chats can continue.

-   Deck AI now includes a `generate_smart_rule` tool, allowing automation intents to be turned directly into Smart Rules instead of only generating Script Plugins.

-   While compaction is in progress, Deck shows `Compacting...`, then inserts a minimal “Conversation context compressed” divider into the transcript once the process completes.

-   Deck adds a lightweight context usage display for AI chat, using a small ring and percentage in the expanded panel to show the session's approximate context pressure.

-   Adds read-only scan/import for CliperX (including common UsePasteAgain `History.sqlite` + `Payloads` layouts), using the same authentication and batched write path as other migration adapters.

### Improvements
-   Compacted context now preserves the current task direction, key outcomes, and essential tool hints, reducing the feeling that the AI has lost the thread in longer chats.

-   Deck only shows the context usage indicator after you send a message or expand the chat panel, keeping the information useful without cluttering the default compact popup state.

-   When the composer grows with line breaks, the send button stays pinned to the bottom of the input area instead of floating in the middle; when the field is empty, it remains vertically centered with the single-line composer for a consistent default layout.

-   Deck AI now handles tool-heavy lookup flows more efficiently, especially when a request needs clipboard, plugin, and web context together.

-   While the AI is performing tool calls, the chat panel now makes the current step more visible on the left side — such as searching, reading a plugin, reading a skill, or saving memory — so the flow is easier to follow.

-   Independent read-only tool calls can now be issued together in the same turn, reducing unnecessary back-and-forth.

-   Legacy template-library migration and repair flows have been consolidated, making maintenance more direct and reducing the chance of drift in historical data recovery.

-   When a tool call fails or search results come back empty, the AI now analyzes the cause before adjusting its approach, rather than retrying blindly or giving up immediately.

-   The AI now has clearer risk-tiered awareness across its tools — acting more decisively on read-only operations and more cautiously on irreversible ones.

-   The AI no longer fabricates success when a tool fails, nor hedges unnecessarily when things go well — reporting is now more faithful to actual outcomes.

-   `generate_script_plugin` and `modify_script_plugin` now run native preflight checks on drafts or temporary patched copies first; when something fails, Deck returns structured file, severity, code, message, and line/column diagnostics so the model can repair and retry automatically.

-   The AI approval bubble in chat now recognizes Smart Rule creation requests and shows a minimal preview of the rule name, trigger logic, and short summary while preserving the original visual style.

-   Welcome “migrate clipboard” and Settings → Storage migration rows now use bundled brand PNGs under `MigrationSourceIcons`, masked with macOS continuous corners, instead of generic SF Symbols alone; loose PNGs ship in the app resource bundle and load via `Bundle` file URLs to avoid “missing in asset catalog” warnings; minor listing tweaks are omitted here. The repo also includes `scripts/normalize_migration_source_icons.py` to normalize icon canvases when updating artwork.

### Changes
-   Compaction only affects the runtime context sent to the AI; local conversation history remains fully preserved, and older messages do not disappear from the transcript.

-   This behavior triggers silently as the context approaches its limit, with no manual button or extra cleanup step required.

-   CliperX and related migrations are offered from onboarding and Settings → Storage only, not from JSON export/import flows, so the entry point stays consistent.

### Fixes
-   Local save paths for LAN pairing secrets, AI Memory keys, and shared keys have been tightened; when a relevant secret already exists, Deck now tries to update it in place first, reducing the risk of losing existing values during rare write failures.

-   If compaction cannot complete, Deck retries quietly once and then continues with the current request normally, avoiding hard interruptions when compaction fails.

-   Fixed the layout handoff between streaming and finalized AI messages; in short replies, compact windows, and bottom-pinned reading, finishing a reply no longer pushes the whole content upward at the last moment.

-   Fixed repeated first-responder requests in the AI chat composer when the window becomes active again. This reduces system-level warning noise during composed-input flows such as Chinese IMEs and keeps input focus behavior more stable.

-   Fixed issues where the AI composer placeholder could briefly overlap IME composition text and, in some cases, confirming a Chinese IME candidate could insert a number instead; sending or clearing the composer now also handles in-progress composition more reliably.

-   Fixed an issue where the context usage indicator could keep showing stale values after switching chats or starting a new conversation. Empty chats, different sessions, and restored chat states now recalculate and refresh correctly.

-   Fixed an issue where overly long Smart Rule approval content could inflate the AI chat panel to an extreme height and even trigger a constraints update loop; approval summaries are now kept restrained.

-   Fixed `modify_script_plugin` preflight creating a temporary directory before `copyItem`; `FileManager.copyItem` requires the destination not to exist, so the copy step always failed and surfaced as a misleading directory-creation error (often under `/var/folders/...`). The staging path is now created only as part of the copy into a unique temp URL.

### Compatibility & Behavior Notes
-   Deck prefers to keep the most recent turns verbatim and fold earlier context into a summary, so compacted sessions stay anchored in the latest exchange.

-   This applies only to independent read-only tool calls in the same turn; anything that writes data, requires approval, or depends on a prior result still runs sequentially.

-   Batching happens when the AI determines that multiple lookups are independent; tasks that require step-by-step reasoning or confirmation may still remain serial.

-   This check has no separate button or settings surface. It runs automatically inside the AI plugin generation pipeline, and Deck only proceeds to plugin add/modify approval once preflight passes.

### Upgrade Notes
-   Upgrade to v1.3.9 if you often keep Deck AI on longer tasks, follow up repeatedly, or continue pushing the same goal across many turns.

-   Upgrade to v1.3.9 if you often ask Deck AI to inspect clipboard history, script plugins, skill details, and web content in the same request.

-   If you used CliperX or similar tools and want history brought into Deck, start a read-only migration from onboarding or Settings → Storage after upgrading.

---

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.3.9/Deck.dmg)

<!-- release-changelog-bot:tag:v1.3.8 -->
## v1.3.8 — v1.3.8 | lūcidulus

- **Tag:** `v1.3.8`
- **Published:** 2026-03-30T03:39:03Z

### Release notes

<p align="center">
  <a href="https://deckclip.app/download" rel="noopener noreferrer" target="_blank">
    <img width="1525" height="896" alt="Deck" src="https://github.com/yuzeguitarist/Deck/raw/main/photos/Deck.webp" style="max-width: 100%; height: auto;" />
  </a>
</p>

---

## Release Notes v1.3.8

### TL;DR
-   The main panel (⌘P) now slides its content inside a fixed window frame; fullscreen dismiss no longer hitches at the edge, pop-in stays closer to the target size with less end-of-animation micro-jitter.
-   The history panel now animates as a complete floating surface instead of being hard-clipped by its final rectangular bounds during show and hide.
-   The macOS 26 dark-mode liquid-glass edge has been softened to reduce the double-outline look created by a bright outer rim plus the darkest outer edge.
-   Slash search can include or exclude items received via Deck LAN sharing.
-   Upgrades backfill LAN-received history where paths can be detected reliably.
-   Fixes LAN-received markers being cleared when the same content is captured again.
-   Refines top search bar main-thread scheduling to reduce QoS priority-inversion diagnostics and potential micro-stutters.
-   The AI chat composer now uses a macOS-native input component better suited for large text editing, significantly reducing lag with very large pasted text and Chinese IMEs.
-   Resolves [Issue #85](https://github.com/yuzeguitarist/Deck/issues/85): once you scroll up during an active AI reply, Deck stops auto-jumping back to the bottom for the rest of that reply.
-   Fixes incorrect shrink behavior in the compact AI window after multi-line input, preventing the top controls from being pushed toward the middle.
-   List thumbnails, LAN-received directory cleanup, and the Share submenu compile cleaner under Swift 6 concurrency checks, reducing related Xcode warnings.
-   Refines the AI assistant system prompts for more consistent replies and clearer behavioral boundaries.
-   Strengthens autonomous decision-making so the AI chooses tools and follow-ups more proactively with fewer unnecessary confirmation loops.
-   Improves end-to-end search performance with a faster query and indexing path.
-   Resolves [Issue #89](https://github.com/yuzeguitarist/Deck/issues/89): in terminals and other text-entry contexts, Cursor Assistant now prefers the insertion point so your eyes do not need to bounce between the mouse and the typing position.
-   Resolves [Issue #82](https://github.com/yuzeguitarist/Deck/issues/82): vertical layout now shows 1–9 quick-paste hints while the quick-paste modifier is held (⌘ by default).
-   Resolves [Issue #78](https://github.com/yuzeguitarist/Deck/issues/78): after long idle periods, reopening the history panel surfaces recent clips sooner and uses a lighter localized text-only loading hint.
-   Script plugins support **Upload to Store**: opens the Deck publish page in your browser with the current plugin pre-filled (no auto-submit).
-   Installed script plugins no longer show `v1.0.0`-style version badges; manifest examples in the guide and upload/publish error strings are fully localized (zh-Hans, zh-Hant, en, de, fr, ja, ko).

### Added
-   Use `type:lan` to show only items received on this Mac via Deck LAN sharing, and `-type:lan` to exclude them; combine with other `type:` values using `+`.
-   Search rule help and hints now document the `lan` type across zh-Hans, zh-Hant, en, de, fr, ja, and ko.
-   In vertical history, holding the quick-paste modifier shows `• #n` in the row subtitle (11pt bold)—same layout as vertical queue mode—with adaptive neutral gray, distinct from the orange queue `#` labels.
-   **Upload to Store** under Settings → Script Plugins encodes the manifest and UTF-8 text files into the URL fragment, opens `apps.deckclip.app/publish/#data=…` in your browser with the form pre-filled; nothing is auto-submitted—you finish publishing on the web.

### Improvements
-   Show/hide slides panel content inside a fixed window frame, avoiding fullscreen edge clipping/snap when animating the whole window off-screen; pop-in matches the target size with less micro-jitter at the end.
-   The history panel now separates its outer contour from the glass material, and show/hide transitions move the panel as one floating surface to reduce the rectangular clipped look and keep rounded edges more coherent.
-   Removes redundant User-interactive QoS on deferred main-queue work, passes tag-focus transition state from SwiftUI instead of re-reading global state inside `NSViewRepresentable` updates—reducing “User-interactive waiting on Default QoS” priority-inversion warnings and related hitch risk.
-   The AI chat composer now uses a native macOS multiline text component and reduces main-thread pressure during typing and pre-send processing, keeping the window more responsive when pasting very large text, using Chinese IMEs, and sending long prompts.
-   List-row thumbnails use a dedicated background blob read path; LAN-received expiry cleanup logs are marshaled to the main actor asynchronously to avoid default MainActor isolation conflicts.
-   Rewrites and tightens assistant-facing system prompts—role, capability bounds, output shape, and safety-related constraints are clearer, reducing vague-instruction drift and redundant back-and-forth.
-   Biases toward autonomous tool use (e.g. search, context reads) and task closure where appropriate, pausing mainly for material ambiguity or higher-risk actions.
-   Optimizes index updates and query execution to cut latency and main-thread work for common filters and full-text lookups.
-   In terminals and other text-entry contexts, Cursor Assistant now prefers the active text caret to reduce eye travel between the mouse and the typing position, while still falling back gracefully when an app does not expose reliable caret information.
-   Script plugin settings follow the standard Deck settings layout and components; the installed list omits per-plugin version badges to avoid confusion with store versioning; upload actions and help text match the current publish flow.
-   Upload-to-store, publish-page errors, link-generation failures, and validation messages are localized across zh-Hans, zh-Hant, en, de, fr, ja, and ko.

### Changes
-   The creation guide’s manifest sample and field list no longer include a `version` key (aligned with hiding local semver in the list); **Upload to Store** bundles only the manifest and UTF-8 text files, with per-file size limits—oversized or non-text files surface localized errors in the app.

### Fixes
-   Tunes the macOS 26 history panel edge rendering in dark mode to reduce the double-outline look caused by a bright outer rim plus a darker outer edge, while preserving the cleaner appearance already seen in light mode.
-   Re-capturing the same clipboard payload no longer clears the LAN-received flag when upserting by `unique_id`.
-   In the compact AI window, the first four line breaks now expand downward as intended, the fifth and later lines scroll inside the composer, and removing line breaks shrinks the outer window back cleanly without leaving extra empty space or pushing the top controls into the middle.
-   While an AI reply is still streaming, scrolling up to read earlier content now immediately disables auto-follow for the rest of that reply, so the view no longer keeps snapping back to the bottom; normal auto-follow resumes on the next reply.
-   Keeps the in-menu secondary sharing service list and existing share flow while avoiding direct calls to deprecated system listing APIs, removing related deprecation warnings.
-   Reopening the history panel after long idle periods now surfaces recent clips sooner; while fresh content is still being prepared, Deck shows a lighter localized text-only hint to reduce the blank-then-pop-in feel.

### Compatibility & Behavior Notes
-   Migration flags unencrypted rows whose stored text/data contains the LAN receive folder path; older plain or inline LAN items without that cue may remain unflagged.
-   Export may include `receivedFromLAN`; older export files without it import as false.

### Upgrade Notes
-   Upgrade as usual; for full historical coverage of LAN filtering, re-receive from peers where needed or verify edge cases manually.

---

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.3.8/Deck.dmg)

<!-- release-changelog-bot:tag:v1.3.7 -->
## v1.3.7 — v1.3.7 | fastidious

- **Tag:** `v1.3.7`
- **Published:** 2026-03-23T13:53:49Z

### Release notes

<p align="center">
  <a href="https://deckclip.app/download" rel="noopener noreferrer" target="_blank">
    <img width="1525" height="896" alt="Deck" src="https://github.com/yuzeguitarist/Deck/raw/main/photos/Deck.webp" style="max-width: 100%; height: auto;" />
  </a>
</p>

---

## Release Notes v1.3.7

### TL;DR
- **Homebrew Cask**  
  `brew tap yuzeguitarist/deck && brew install --cask deckclip` — two commands to install, versions auto-sync from GitHub Releases.  
- **⌃A / ⌃E**  
  History supports Emacs-style shortcuts to jump to the true newest or oldest page from the database.  
-   Tail jumps use one targeted fetch instead of paging through the middle; search tail jumps cap candidates on very large libraries.  
-   Fixes ⌃E stopping on repeat use and ⌃A after ⌃E leaving you stuck on the tail until reopening the panel.  
-   Paused recording no longer ingests clipboard changes that happened during pause when you resume.  
-   The feedback destination sheet opened from Settings › About works for Cancel and both options, matching the keyboard shortcut entry.  
-   About adds a Support section: the Deck icon opens the pricing page at Support Development, plus GitHub; the website locale follows app language (Chinese vs English site).  
-   Stricter DB init semantics; template items stored on disk with legacy migration/repair; iCloud sync improvements for encryption, file URLs, metadata, and crash recovery; Smart Rule no longer auto-authorizes networked script plugins; tighter permissions and safer Keychain updates for AI auth.  
-   Web fetch/search assembles large bodies more efficiently; removing a LAN manual peer clears outbound scheduling state for that IP so stale map entries do not accumulate.  

### Added
-   Deck is now available via Homebrew: `brew tap yuzeguitarist/deck` then `brew install --cask deckclip`. Future releases auto-sync from GitHub Releases.  
-   Card context menu adds a "System Share" submenu listing AirDrop, Messages, Mail, and all macOS sharing services — no need to drag to Finder first. Supported in both horizontal and vertical layout modes.  
-   With history focus, ⌃A reloads the newest page from the database and selects the chronologically newest item; ⌃E fetches the oldest page in one query and selects the chronologically oldest item, independent of context-aware visual order.  
-   Settings › About adds Support the Author: one row with the app icon opens the pricing page at the Support Development section; another opens the GitHub repository. Chinese app language uses the Chinese site; otherwise the English site.  

### Improvements
-   Jumping to the list end reads the oldest slice directly by sort order instead of paging forward from the middle.  
-   When the library is very large, tail jumps in search mode use a tighter one-shot candidate cap to avoid excessive work.  
-   Support-section icons share consistent sizing and alignment, with a clearer, smoother GitHub mark.  
-   Template payloads live under Application Support with metadata indices in UserDefaults; security mode encrypts template files; remove/move operations update indices only instead of rewriting every payload.  
-   `lastSyncDate` updates whenever a fetch attempt finishes (including early error exits), decoupled from whether the server change token advanced.  
-   Async response bytes are buffered in chunks before appending to `Data`, reducing CPU and allocation work for multi-megabyte bodies while keeping the 5 MB cap and overflow behavior.  

### Fixes
-   Subsequent ⌃E presses are no longer blocked by the shared loading flag used for “load more”; pagination marks loading only inside its async work.  
-   After ⌃E, ⌃A previously selected the first item of the in-memory tail slice, not the global newest, and newer items seemed missing until reopening; it now reloads the true head page symmetrically to ⌃E.  
-   Clipboard captures made while recording is paused are no longer saved the moment you resume; only copies after resuming are recorded.  
-   Feedback destination dialog is presented on the next main-loop turn so AppKit modal sessions started from Settings SwiftUI actions receive clicks in the content area, not only the title-bar close control.  
-   `isInitialized` flips true only after integrity, custom SQL functions, table creation, and migrations succeed; failed integrity recovery no longer leaves a false “ready” flag.  
-   Storage version advances only after a successful legacy decode and payload write; decode failures keep legacy data for retry. Orphan legacy blobs are repaired when indices are empty but old JSON remains.  
-   When a file-URL image is materialized to bytes for the template library, the stored pasteboard type matches the image payload.  
-   fileURL items upload only when local resolution yields real content (not just the path string); images use concrete image types; unresolvable items are skipped with logging.  
-   With iCloud encryption, app path/name follow the same rules as other fields: encrypt-or-omit with warnings, no silent plaintext; `encryptAppMeta` matches receiver decryption.  
-   Persisted in-flight upload names are cleared only for succeeded or cancelled records; failed records pending re-queue stay listed until the next successful completion path.  
- **iCloud：Server change token**  
  Corrupt server change token data in UserDefaults is removed after a decode failure.  
-   Smart Rule no longer auto-authorizes script plugins that require network access; users must approve in plugin settings.  
-   Tighter POSIX permissions on `auth.json` (700/600); API keys prefer `SecItemUpdate` over delete-then-add to avoid losing the previous secret on add failure.  
-   Removing a manual peer drops the outbound-connect epoch entry for that IP instead of retaining the key with an incremented counter, trimming stale entries when peers are added and removed over time.  

### Compatibility & Behavior Notes
-   Shortcuts use the Control modifier on macOS; the history list must have focus (not while typing in search, etc.).  
-   After ⌃E, the visible list is that tail page until ⌃A reloads the newest page or another action reloads the head (e.g. reopening the panel).  
-   On first launch after upgrade, template items migrate from the legacy UserDefaults blob to `~/Library/Application Support/Deck/TemplateItems/`; a repair pass may recover from a partially migrated state.

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.3.7/Deck.dmg)

<!-- release-changelog-bot:tag:v1.3.6 -->
## v1.3.6 — v1.3.6 | recherché

- **Tag:** `v1.3.6`
- **Published:** 2026-03-20T07:31:30Z

### Release notes

<p align="center">
  <a href="https://deckclip.app/download" rel="noopener noreferrer" target="_blank">
    <img width="1525" height="896" alt="Deck" src="https://github.com/yuzeguitarist/Deck/raw/main/photos/Deck.webp" style="max-width: 100%; height: auto;" />
  </a>
</p>

---

## Release Notes v1.3.6

### TL;DR
-   The AI assistant gains web search and page-fetch tools, plus a quick path to configure OpenCode Zen free models.  
-   Hide or show the menu bar icon instantly from Settings without restarting; use Cmd+F in the main panel to focus the search field.  
-   Global shortcuts, Typing Paste, and cursor-assistant triggers share conflict checks; failed saves roll back with a clear alert.  
-   Nearby sync and discovery are more stable around sleep/wake and reconnects; UI string gaps and the OAuth completion flow are improved.  

### Added
-   Adds `web_search` and `web_fetch` for the AI assistant: search via the Exa endpoint, fetch pages, and convert HTML to Markdown or plain text with safe size limits; Smart Rule automation does not include these web tools.  
-   Adds a Zen entry and model picker in the OpenAI API section to auto-fill base URL, API key placeholder, and model name for free-tier models.  

### Improvements
-   A “Show menu bar icon” toggle under General › Startup updates the existing preference and applies immediately; when shown again, pause state stays in sync.  
-   Cmd+F in the main panel focuses the search field, dismissing the rules popover if needed and working alongside brief focus suppression and Vim mode; typing to search still works as before.  
-   The OAuth completion button now reads “Open Deck” and launches the app via its URL scheme instead of only closing the page.  
-   Removes the Beta pill next to the AI Assistant title for a cleaner settings screen.  
-   The Zen banner reuses existing config-row styling and matches maintenance-style sheets; new strings are localized across supported languages.  
-   Adds unified conflict validation for global shortcuts, Typing Paste record/reset, and cursor-assistant triggers, including reserving ⌘⇧V for queue sequential paste.  
-   Observes display sleep/wake, delays discovery after wake, debounces remembered-peer reconnects, avoids duplicate invites and stale callbacks, and cancels tasks plus clears delegates on refresh/stop.  
-   Localizes new settings strings and fills gaps for empty clipboard, queue hints, search placeholders, import rules, previews, and AI errors across supported languages.  

### Changes
-   If shortcut registration fails, the UI rolls back to the last saved combination and shows an explanation instead of appearing updated while inactive.  
-   Updates the system prompt tool count and documentation to include web search and fetch, including usage expectations such as no per-call approval.  

### Fixes
-   Preserves not-connected cooldowns where appropriate so `lostPeer` does not clear them incorrectly; it cancels pending auto-reconnect and cleans discovery UI state.  
-   Fixes runtime Chinese fallbacks and missing keys in empty states, queue UI, HUD, and search-related copy.  

### Upgrade Notes
-   If you use custom AI endpoints, review Zen quick setup against your privacy and compliance needs before enabling.  

---

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.3.6/Deck.dmg)

<!-- release-changelog-bot:tag:v1.3.5 -->
## v1.3.5 — v1.3.5 | Apologies

- **Tag:** `v1.3.5`
- **Published:** 2026-03-15T05:30:36Z

### Release notes

<p align="center">
  <img width="2435" height="1219" alt="Deck" src="https://github.com/user-attachments/assets/f1f010f2-af6f-47a9-866a-c2e7520957c5" />
</p>

---

## Release Notes v1.3.5

### TL;DR

-   When a downloaded package fails size or hash validation, Deck now attempts recovery and reconfirmation before surfacing a fatal error.

-   If the available update changes during installation, the update prompt now refreshes to the latest info instead of continuing with a stale snapshot.

-   Deck now refreshes metadata, adds cache-busting to retry downloads, and automatically retries once when stale cache or edge-node lag is suspected.

### Improvements

-   After a validation mismatch, Deck re-fetches the latest metadata and chooses the next step based on the current update state for a more resilient upgrade flow.

-   Download validation failures now show clearer, scenario-specific messaging instead of only a generic "size mismatch" style error.

### Changes

-   If recovery detects that the remote version has changed, Deck updates the local record and asks you to confirm installation again against the latest version.

-   If the version stays the same but the underlying asset changes, Deck refreshes to the new package information and requires reconfirmation before continuing.

### Fixes

-   When metadata is unchanged, Deck now treats the mismatch as likely edge propagation delay and automatically waits briefly before retrying the download once.

-   Retry downloads now use cache-busting URLs to avoid stale caches and reduce repeated failures caused by outdated packages.

-   If the available update changes mid-install, the current update prompt now switches to the new update info instead of holding onto the old snapshot.

### Upgrade Notes

-   This release mainly improves the reliability of the update download and confirmation flow, especially for failures caused by cache staleness or propagation lag.

---

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.3.5/Deck.dmg)

<!-- release-changelog-bot:tag:v1.3.4 -->
## v1.3.4 — v1.3.4 | Responsive

- **Tag:** `v1.3.4`
- **Published:** 2026-03-14T05:08:10Z

### Release notes

<p align="center">
  <img width="2435" height="1219" alt="Deck" src="https://github.com/user-attachments/assets/f1f010f2-af6f-47a9-866a-c2e7520957c5" />
</p>

---

## Release Notes v1.3.4

### TL;DR
- **Resizable horizontal panel**  
  Horizontal Deck can now be resized from the top edge, and it remembers your last panel height.
- **Cards scale with the panel**  
  Horizontal cards now scale with panel height, giving images, links, text, and code more room to breathe.
- **Navigation feels more natural across views**  
  Keyboard navigation now feels more consistent across horizontal/vertical Deck and Cursor Assistant, without stealing editing keys while typing.
- **Preview stays in sync with selection**  
  Open previews now stay synced with the current selection when you switch tabs or move focus.
- **Preview reading is cleaner and less cramped**  
  Plain text, Markdown, code, and single-image previews now use a cleaner edge-to-edge layout with lighter, more consistent scrollbars.

### Added
- **Panel height adjustment for horizontal Deck**  
  Added a top resize handle for horizontal Deck so you can drag upward to expand the panel height and keep your preferred size.
- **Modifier-based quick number hints**  
  Added modifier-triggered quick number hints for the first 9 reachable horizontal cards to make fast targeting easier.

### Improvements
- **Adaptive horizontal card layout**  
  Horizontal cards now adapt their size, content density, and truncation rules to panel height so extra space improves readability instead of just scaling the frame.
- **Richer image and link presentation**  
  Image cards now use clearer metadata layout and a checkerboard transparency background, while link cards scale their media area and icons more naturally.
- **Cleaner preview surfaces**  
  Plain text, Markdown, code, and single-image previews now feel more immersive with edge-to-edge presentation and slimmer, lighter scrollbars.
- **Smaller and tidier card number badges**  
  The quick number badges in the lower-right corner of horizontal cards are now smaller and better placed, making them less distracting.

### Changes
- **Direction-first keyboard semantics**  
  Horizontal Deck shortcuts now prioritize directional semantics: Ctrl+N / Ctrl+P move to next / previous, Ctrl+F / Ctrl+B move right / left, and Vim mode keeps h / l fixed to left / right while j / k remain as compatible navigation keys.
- **Vertical navigation stays intentionally simpler**  
  Vertical Deck keeps a simpler navigation model with arrow keys and Ctrl+N / Ctrl+P for up/down movement, plus j / k in Vim mode without adding Ctrl+F / Ctrl+B.
- **Cursor Assistant follows the same input rules**  
  Cursor Assistant now supports Ctrl+N / Ctrl+P and j / k in Vim mode, following the same input-state protection rules as the main panel.

### Fixes
- **Preview sync after selection changes**  
  Fixed a preview sync bug where updates only reliably followed certain keyboard moves and could fall out of sync after tab switches or other external selection changes.
- **Long-press preview throttling no longer overrides fresh focus**  
  Fixed an issue where delayed preview updates during long key presses could override newer focus changes, making preview following more reliable.
- **No more extra code warning block in preview**  
  Removed the extra warning block shown under very long code previews, so the main content no longer gets squeezed or visually cut off.

### Notes
- **Large code still protects performance**  
  Very large code previews still keep their performance safeguards, such as disabling highlighting, but no longer show an intrusive extra notice in the UI.

### Compatibility & Behavior Notes
- **Resize applies to horizontal Deck only**  
  The new panel resize behavior applies only to horizontal Deck; overall height behavior for the vertical list remains unchanged.
- **Editing contexts still keep priority**  
  Search fields and editing contexts still preserve normal text input shortcuts, so the new navigation mappings do not hijack editing behavior.

### Upgrade Notes
- **Recommended for users who rely on horizontal Deck or preview workflows**  
  If you mainly use horizontal Deck, rely on keyboard navigation, or spend a lot of time browsing previews in the panel, this update is well worth installing.

---

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.3.4/Deck.dmg)

<!-- release-changelog-bot:tag:v1.3.3 -->
## v1.3.3 — v1.3.3 | Winsome

- **Tag:** `v1.3.3`
- **Published:** 2026-03-11T10:59:11Z

### Release notes

<p align="center">
  <img width="2435" height="1219" alt="Deck" src="https://github.com/user-attachments/assets/f1f010f2-af6f-47a9-866a-c2e7520957c5" />
</p>

---

## Release Notes v1.3.3

### TL;DR
- **AI Chat feels much steadier**  
  AI chat now feels much steadier, with smarter auto-follow, smoother streaming updates, and tail-only rendering that no longer yanks you away from message history.
- **Heavy AI work backs off the main thread**  
  More AI persistence and refresh work now stays off the main thread, reducing send-time freezes, UI stalls, and memory churn.
- **Search panel state is more reliable**  
  Search panel state is now more reliable, with fixes for expansion drift, focus sync, and leftover IME composition when reopening the panel.
- **Queue mode is more customizable**  
  Queue mode now lets you choose where number-key mapping starts, either from the leftmost card or from the currently focused item.
- **Feedback and AI text are more polished**  
  Feedback now offers email or web reporting, and more AI-facing default labels and prompts are properly localized.

### Added
- **Queue quick-select anchor setting**  
  Added a new “Number Mapping Start Point” setting so queue mode can map number keys from either the leftmost card or the currently focused card.
- **Web feedback entry**  
  Added a web-based feedback flow that automatically attaches device, system, app version, locale, and time zone details.

### Improvements
- **Smarter chat auto-follow**  
  Chat now stays pinned only when you just sent a message, AI is actively replying, and you were already near the bottom; if you scroll up intentionally, normal streaming output no longer forces you back down.
- **Smoother streaming output**  
  Streaming refresh and scroll triggering have been softened and layered more carefully, reducing jitter, blank flashes, and jumpiness during long responses.
- **Tail-only rendering for active responses**  
  Active AI responses now update through a more focused tail-rendering path, so stable history no longer gets broadly recomputed on each stream tick.
- **Lighter conversation persistence**  
  AI conversation persistence and index updates are now merged and scheduled more intelligently, reducing unnecessary disk activity during bursts of activity.
- **More stable message layout**  
  Message text now uses a steadier vertical layout, making long streaming content less prone to layout instability.

### Changes
- **Priority-based scroll behavior**  
  Chat scrolling now uses event priorities: normal AI output avoids interrupting reading, while permission requests and interaction prompts are prioritized for visibility.
- **Queue mode status messaging**  
  Queue mode now shows the current number-mapping rule in its status area, making the active selection behavior easier to remember.
- **Feedback flow selection**  
  Triggering feedback now lets you choose between email and web reporting first, and the web path follows the current app language.

### Fixes
- **Chat view redraw pressure**  
  Fixed excessive full-view redraw pressure during streaming replies, which significantly reduces send-time freezes and dropped frames while scrolling.
- **Search bar expansion drift**  
  Fixed an issue where the search bar could reopen in an expanded-looking but not truly active search state.
- **IME composition residue on close**  
  Fixed issues where closing the panel during unfinished IME composition could leave stray Latin text, swallow key events, or break focus on reopen.
- **AI conversation logging calls**  
  Fixed several missing async waits in AIConversationStore logging calls to avoid instability around save and query flows.
- **AI-facing fallback text consistency**  
  Fixed inconsistent localization across some AI default titles, tool prompts, and error messages.

### Notes
- **Localization coverage expanded**  
  This release expands localization coverage for more AI defaults, tool result prompts, plugin generation errors, and new conversation titles.

### Compatibility & Behavior Notes
- **Existing queue users keep the old default**  
  Existing queue users keep the original default behavior, with number mapping still starting from the leftmost card unless changed manually.
- **Search opens in a cleaner default state**  
  Each time the panel reopens, the search bar now returns to a cleaner collapsed default state and expands only when truly entering search mode.

### Upgrade Notes
- **Recommended for all users who rely on AI chat or search**  
  If you frequently use AI chat, read long responses, rely on the search panel, or use queue-mode shortcuts, upgrading to v1.3.3 is recommended.

---

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.3.3/Deck.dmg)

<!-- release-changelog-bot:tag:v1.3.2 -->
## v1.3.2 — v1.3.2 | Lucent

- **Tag:** `v1.3.2`
- **Published:** 2026-03-07T05:05:19Z

### Release notes

<p align="center">
  <img width="2435" height="1219" alt="Deck" src="https://github.com/user-attachments/assets/f1f010f2-af6f-47a9-866a-c2e7520957c5" />
</p>

---

## Release Notes v1.3.2

https://github.com/user-attachments/assets/a969e1f3-02c2-43ae-b25d-64b1f396db10

### TL;DR
- **AI Memory**  
  Deck now turns the preferences, habits, and context you share in chat into a growing local memory system, encrypted and stored on your device.  

- **Script Plugins for AI**  
  AI can now run existing script plugins directly and delete them after your approval; network-enabled plugins ask for permission before running.  

- **AI CLI Bridge**  
  Deck adds `/ai/run`, `/ai/search`, and `/ai/transform` so AI workflows are easier to drive from the CLI and automation.  

- **AI Smart Rules**  
  Smart Rules now support AI actions, with automatic guardrails that keep each run scoped to the single triggering item.  

- **Faster AI Chat**  
  AI chat is now lighter and smoother, with leaner streaming updates, conversation indexing, and memory usage.  

- **Stability and Polish**  
  Custom storage, import transactions, paste fallbacks, hotkey persistence, image preview, and window layering all received a solid reliability pass.  

### Added
- **AI Memory That Stays Local**  
  Deck AI Memory quietly captures important details from conversations, learns your habits over time, and keeps everything local, encrypted, and private.  

- **Run and Delete Script Plugins with AI**  
  AI can now run existing script plugins and delete them after confirmation, with clearer risk warnings and plugin info shown before removal.  

- **AI Actions in Smart Rules**  
  Smart Rules gain a new AI action that requires a prompt before creation or save, along with clear warnings for high-privilege automation.  

- **Zoomable Image Preview**  
  Image preview now supports zoom buttons, double-click to zoom/reset, gesture zooming, and a larger default scale for image previews.  

- **Always-on-Top Toggle**  
  Settings now include an “always on top” toggle, so tools like Yoink can appear above Deck when you turn it off.  

### Deck × Orbit
- **Three New AI CLI Endpoints**  
  The CLI Bridge now adds dedicated AI routes for run, search, and transform, with examples and failure cases documented directly in Settings.  

- **Search Results, Plugin Chaining, and Auto-Save**  
  `/ai/search` can return search results, `/ai/transform` can run a script plugin before AI post-processing, and both `/ai/run` and `/ai/transform` support auto-save.  

### Improvements
- **Smoother Streaming Replies**  
  Streaming reply updates, auto-scroll behavior, and text rendering were trimmed down so long AI replies feel steadier and less heavy.  

- **On-Demand Skill Loading**  
  AI now starts with a lighter skills directory and loads each `SKILL.md` only when needed, keeping context cleaner and tool choice more precise.  

- **Sharper AI Guidance and Safety Tone**  
  The AI system prompt, personality framing, and safety rules were reworked to make responses more consistent, grounded, and stable.  

- **Settings Visual Polish**  
  Storage, self-check, migration, security mode, AI provider, and accessibility permission areas in Settings were visually unified and made easier to use.  

- **Broader Localization Coverage**  
  This release adds localization coverage for the new AI, Smart Rules, CLI guide, approval dialogs, and window option strings across the supported languages.  

### Changes
- **Plugin Authorization Rules Are Now Explicit**  
  Local-only plugins run immediately, network-enabled plugins ask for permission first, and deleting a script plugin always requires your approval.  

- **Smart Rule AI Runs in a Narrow Automation Context**  
  When a Smart Rule triggers AI, it skips the confirmation dialog but stays limited to the current triggering item and cannot create, edit, or delete script plugins.  

- **Prompt Is Now Required for AI Bridge Requests**  
  `/ai/run`, `/ai/search`, and `/ai/transform` now require a non-empty `prompt`, and return `400` immediately when it is missing.  

- **Larger and Safer JSON Responses**  
  The AI Bridge now supports richer JSON responses and adds response-size protection to reduce the chance of oversized payload failures.  

### Fixes
- **Custom Storage No Longer Fails Silently**  
  Custom storage now writes settings only after a successful migration, rolls the UI back on failure, and no longer silently falls back to the default location.  

- **Imports Are Now Atomic**  
  Imports now fully parse first and then write in a single transaction, so failures roll the whole batch back instead of leaving partial data behind.  

- **Paste and Activity Fallbacks Are Safer**  
  Incorrect session activity wiring, risky CGEvent tap fallback behavior, and the “swallow shortcut before finding no text” issue have all been tightened up.  

- **Hotkey Reset Now Sticks**  
  Cleared hotkeys no longer quietly come back as defaults after the app restarts.  

### Upgrade Notes
- **Review Any CLI Integrations**  
  If you use the CLI Bridge, make sure every AI request includes a `prompt` and that your integration handles `400` responses correctly.  

- **Revisit Smart Rules That Use AI**  
  If AI is part of your automation flow, revisit those rules and confirm the new “triggering item only” scope matches what you expect.  

- **Explore the New AI Workflow Features**  
  After upgrading, it is worth trying AI Memory, script plugin execution, the new CLI AI endpoints, and the updated image preview and window layering controls.  

---

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.3.2/Deck.dmg)

<!-- release-changelog-bot:tag:v1.3.1 -->
## v1.3.1 — v1.3.1 | Adamantine

- **Tag:** `v1.3.1`
- **Published:** 2026-03-04T11:52:33Z

### Release notes

<p align="center">
  <img width="2435" height="1219" alt="Deck" src="https://github.com/user-attachments/assets/f1f010f2-af6f-47a9-866a-c2e7520957c5" />
</p>

---

## Release Notes v1.3.1

https://github.com/user-attachments/assets/9ad6fe8a-3427-4c23-bb97-34273820d436

### TL;DR
-   Added a dedicated AI Assistant settings page with support for ChatGPT Subscription, OpenAI API, Anthropic API, and Ollama.
-   Update flow now verifies version and SHA-256 before and after download to block mismatched or tampered packages.
-   Global hotkeys and related global triggers are now paused during shortcut recording to prevent conflicts.
-   Streaming AI responses now auto-retry on transient failures and avoid duplicate text after reconnect.
-   One-click maintenance now includes binary slimming scan/cleanup with results shown in the maintenance report.

### Added
-   Added an "AI Assistant" tab in Settings with provider selection, endpoint/token/model configuration, shortcut reference, and safety notes.
-   Added binary slimming support to scan removable architectures in the background at startup and clean them during one-click maintenance.
-   New local update records now store version, size, and SHA metadata and can restore pending update prompts on app startup.

### Improvements
-   Cursor assistant popup now positions by the actual target screen and falls back to mouse position when caret coordinates are unreliable.
-   Added a short protection window after showing the main panel to reduce accidental instant close from focus jitter.
-   Horizontal queue bar height is adjusted to 33 to avoid compressing card bottoms, while vertical layout keeps previous height.
-   Added backoff retries for transient errors (timeouts, 429, 5xx) while preserving conversation context and tool flow across retries.

### Changes
-   `1-9` shortcuts are no longer hardcoded to Command and can now use Command / Option / Control.
-   During shortcut recording, global hotkeys and Option double-click listening are paused, and simulated-input-related events are passed through.
-   Update and log-upload backend URLs were updated; updates now use Worker-only source with code signature enforcement enabled by default.
-   Move-to-top now also syncs recent cache so main panel and cursor assistant share the same ordering.
-   Clipboard search snippets now apply length limits and masking to reduce sensitive data exposure risk.

### Fixes
-   Fixed runtime crash caused by duplicate OAuth query keys by switching to stable overwrite behavior.
-   Fixed potential data loss during overwrite install by adding safe replacement and rollback behavior.
-   Fixed hanging approval requests after conversation switches by unifying cancellation handling.
-   Fixed premature stream close being treated as completion; missing completion state now triggers retry.
-   Fixed Swift 6 MainActor isolation errors and maintenance report argument mismatch issues.
-   Fixed fallback recovery path after failed updates to restore previous app version.

### Notes
-   All 16 newly added strings were completed in 7 languages and validated for structure integrity.

### Compatibility & Behavior Notes
-   This is intentional to prevent accidental triggers; all related global actions auto-resume after recording ends.
-   Updates are now stricter: same version with different SHA is rejected, and newly detected versions require a fresh confirmation.
-   Admin permission is requested only when cleanup actions require elevated system access.

### Upgrade Notes
-   After upgrading, review shortcut modifier settings in "Settings > Shortcuts" and binary slimming toggles in "Settings > Storage" to match your preference.

---

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.3.1/Deck.dmg)

<!-- release-changelog-bot:tag:v1.3.0 -->
## v1.3.0 — v1.3.0 | Palimpsestic

- **Tag:** `v1.3.0`
- **Published:** 2026-03-01T10:25:12Z

### Release notes

<p align="center">
    <img width="2435" height="1219" alt="Deck" src="https://github.com/user-attachments/assets/f1f010f2-af6f-47a9-866a-c2e7520957c5" />
  </p>

---

  ## Release Notes v1.3.0

  ### TL;DR

  -     Smart Rules received a major upgrade, with action types moved to menus and new "Transform" and "Script Plugin" submenus, while save/execute now fully support both new and legacy values.
    Vertical mode is now fully available, including left/right docking and coordinated behavior across search rule popup, card preview, bottom area, and overall interactions.
    The plugin system is now faster and more stable, with hot reload, debounced refresh, caching improvements, and optimized watchers to reduce flicker and repeated reloads.
    Export and data safety are now more reliable through "staging write + atomic replace" and fixes for multiple high-risk paths such as migration, encryption, handshake, and task cleanup.
    Preview and smart calculation are significantly improved with async preview, faster and more accurate computation, and better cache consistency to reduce lag and stale results.
    UI interaction details were polished end-to-end, including multi-image display, tag menus, focus behavior, settings-page animation, contrast, and spacing.


  -     Added a new "Transform" submenu under action type so users can hover to expand and click specific transforms directly.
    SmartRulesView.swift:889
    Transform actions are now persisted with stable codes, preventing breakage after language switches while still supporting legacy values.
    SmartRulesView.swift:971, SmartRuleService.swift:155, DeckDataStore.swift:1151
    Added a "Script Plugin" submenu in action menu, allowing installed plugins to be selected directly with full model encode/decode and execution integration.
    SmartRulesView.swift:814, SmartRuleService.swift:136, DeckDataStore.swift:1136, ScriptPluginService.swift:658
    Added an ASCII animation bar with six scenes, character-level transitions, 60fps timeline driving, and dynamic-width rendering.
    ASCIIArtBarView.swift
    Added a "Usage Guide" block in SmartRules with workflow explanation, condition/action references, and practical tips for easier onboarding.
    SmartRulesView.swift, Localizable.xcstrings
    Added an "Immediate Restore" capability with a settings button and confirmation dialog, allowing manual restore when required conditions are met.
    DeckSQLManager.swift:2196, SettingsView.swift:2089, SettingsView.swift:2327, SettingsView.swift:2333, SettingsView.swift:2559, SettingsView.swift:2566
    Added vertical dock-side settings (left/right), with rule popup and preview window automatically placed on the outer side accordingly.
    SettingsView.swift, MainWindowController.swift, MainViewController.swift, SearchRulePickerPanelController.swift, PreviewWindowController.swift, UserDefaultsManager.swift,
    Constants.swift, DeckViewModel.swift
    Script plugin hot reload is now live: plugin directories are auto-watched on startup, changes auto-refresh, and manual refresh is still available.
    ScriptPluginService.swift:141, ScriptPluginService.swift:241, ScriptPluginService.swift:555, ScriptPluginService.swift:607, ScriptPluginService.swift:693

  ### Deck × Orbit

  -     `CLI /clip` now uses Smart Rules by default, while still allowing parameter-based fallback to legacy direct-save behavior.
    CLIBridgeService.swift:608, CLIBridgeService.swift:629, CLIBridgeService.swift:672
    CLI Bridge examples and alias docs were expanded with tag name/id writing, empty-result status checks, and clearer `health / last / write` alias usage.
    CLIBridgeSettingsView.swift:109, CLIBridgeSettingsView.swift:119, CLIBridgeSettingsView.swift:124, CLIBridgeSettingsView.swift:132, CLIBridgeSettingsView.swift:167
    The script-plugin "creation steps" guide is now more complete, with richer manifest/script examples plus a real-test step and recommendations.
    ScriptPluginsSettingsView.swift:17, ScriptPluginsSettingsView.swift:28, ScriptPluginsSettingsView.swift:220, ScriptPluginsSettingsView.swift:224
    The Cloudflare update-proxy backend was optimized for better performance, stability, real-time behavior, speed, and concurrency.


  -     Export now uses "staging write + atomic replace" to prevent partial JSON leftovers, and failures only clean temporary files instead of deleting existing user backups.
    DataExportService.swift:108, DataExportService.swift:123, DataExportService.swift:163
    Large-data export performance was improved via buffered batch writes (1MB threshold), and batch size was reduced from 500 to 200 to lower memory pressure.
    DataExportService.swift:180, DataExportService.swift:201
    Reduced duplicate I/O in the export pipeline by avoiding repeated blob reads when full data is already loaded.
    DataExportService.swift:220
    LS/PS sanitization hot path was accelerated by reusing static U+2028/U+2029 constants and adding a fast pre-check so replacement runs only when needed.
    DataExportService.swift:123, DataExportService.swift:165
    Script-plugin execution performance was improved with plugin indexing, script-text caching, and network-permission caching; execution now prefers cache, and script hash is computed only when required.
    ScriptPluginService.swift:136, ScriptPluginService.swift:247, ScriptPluginService.swift:730, ScriptPluginService.swift:755, ScriptPluginService.swift:836, ScriptPluginService.swift:937,
    ScriptPluginService.swift:1231, ScriptPluginService.swift:1236, ScriptPluginService.swift:1452
    Preview and instant-calculation performance improved by replacing synchronous hotspots with async flow, reducing main-thread pressure and fixing behavior accuracy when instant calc is disabled.
    PreviewOverlayView.swift:16, PreviewOverlayView.swift:103, PreviewWindowController.swift:330, PreviewWindowController.swift:382, PreviewWindowController.swift:461,
    ClipItemCardView.swift:1738, SmartContentCache.swift:276
    Math recognition and calculation were upgraded with faster pre-checks, support for left-side equation evaluation, multiple/nested `sqrt`, and improved number-formatting performance.
    SmartTextService.swift:1846, SmartTextService.swift:1882, SmartTextService.swift:1928, SmartTextService.swift:1999, SmartTextService.swift:2032
    Smart-cache consistency was improved by proactively invalidating cache on OCR/text updates and settings toggles, and by binding card/row tasks to text and switch changes.
    DeckDataStore.swift:1414, SettingsView.swift:1211, ClipItemCardView.swift:42, ClipItemCardView.swift:558, ClipItemRowView.swift:21, ClipItemRowView.swift:104
    Vertical-mode image display was refined by strictly constraining images to a square area with separate handling for near-square, wide, and tall images.
    ClipItemRowView.swift:117, ClipItemRowView.swift:173
    Multi-image display was improved by showing only the first image, adding count badges and an "N more images" hint, and fixing premature preload skipping.
    ClipItemCardView.swift, Localizable.xcstrings
    In vertical mode, "Total X images" is now shown only for multi-image items and placed in the middle of the right info area.
    ClipItemRowView.swift:290
    Settings-page interactions and transitions were refined by removing the content offset hack and disabling full-page animation on tab switching (click/keyboard).
    SettingsView.swift:184, SettingsView.swift:232, SettingsView.swift:270
    Visual details were polished with a Tonal migration button style, improved `textTertiary` contrast, and auto-expanding tag editor input fields.
    NewTagChipView.swift, EditingTagChipView.swift
    Reopen scrolling experience was improved by forcing selection back to the first item on reactivation while reusing existing smooth-scroll logic.
    HistoryListView.swift:135


  -     Vertical-mode top/bottom interaction logic was reworked: top controls (settings/pause/close/feedback) were removed, and the bottom area now toggles between queue bar and button bar.
    TopBarView.swift:1155, HistoryListView.swift:110, TopBarView.swift:958
    Vertical search layout was adjusted so the right tag area auto-collapses when search is focused, has input, or rule panel is open, preventing horizontal stretch.
    TopBarView.swift:18
    Vertical bottom heights were unified: button area and queue area now share the same height, with offset hacks removed for consistent alignment.
    HistoryListView.swift:86, HistoryListView.swift:255, HistoryListView.swift:266
    Expanded search width in vertical mode now nearly fills available space, while horizontal-mode behavior remains unchanged.
    TopBarView.swift:123
    Search-rule popup positioning was adjusted for vertical mode to render outside the main panel with boundary protection, avoiding overlap with input and list.
    SearchRulePickerPanelController.swift:95, SearchRulePickerPanelController.swift:102
    Tag right-click menu was migrated to `NSMenu`, keeping edit/share-group/delete and adding color-dot selection with state feedback and immediate persistence.
    TopBarView.swift:1568
    Initial selection after opening panel was adjusted to prioritize the first item, and skip redundant resets when already on first item to avoid secondary flicker.
    HistoryListView.swift:1271
    Automatic update checks were changed to three runs per day in Beijing time: 04:00, 12:00, and 20:00.
    UpdateCoordinator.swift:18, UpdateCoordinator.swift:80
    Plugin watcher strategy now uses separate masks for directories/files: `.attrib` is kept for directories, removed for files, and high-frequency watcher logs are disabled.
    ScriptPluginService.swift:155, ScriptPluginService.swift:159, ScriptPluginService.swift:634, ScriptPluginService.swift:643
    Watch scope now includes all first-level script directories via new candidate-directory collection logic, preventing missed refresh for newly created plugin folders.
    ScriptPluginService.swift:681, ScriptPluginService.swift:695


  -     Removed unused fields/constants in Welcome page, including `tint`, `icon/iconColor`, and redundant struct fields.
    WelcomeView.swift:22, WelcomeView.swift:49, WelcomeView.swift:102, WelcomeView.swift:514, WelcomeView.swift:606
    Fixed six errors caused by missing `await` in async logging calls, restoring compile and runtime stability.
    DeckDataStore.swift:1148, DeckDataStore.swift:1176
    Fixed numeric key mapping in rule popup by replacing subtraction-based inference with fixed mapping, resolving 5/6 mismatch and no-response on 7/8/9/0.
    Fixed search box focus stealing by skipping delayed `makeFirstResponder(nil)` when focus moves to `.newTag`/`.editTag`.
    Fixed default selection behavior for new tags by ensuring focus is obtained first, then auto-selecting the "新标签" text.
    Fixed accidental swallowing of the next real copy after paste by limiting skip behavior to the exact just-written `changeCount`.
    ClipboardService.swift:25, ClipboardService.swift:261, ClipboardService.swift:1645
    Reduced clipboard-loss risk on paste failure by expanding snapshot restore budget/type coverage and returning explicit success/failure with error logs.
    ClipboardService.swift:1469, ClipboardService.swift:1514, ClipboardService.swift:1654
    Fixed false-positive success in encryption migration by enforcing strict validation for blob migration and `blob_path` update, failing as a whole on any step error.
    DeckSQLManager.swift:5403, DeckSQLManager.swift:5425, BlobStorage.swift:178
    Fixed incorrect plaintext state marking after decrypt failure: decryption branch now strictly checks and fails directly without writing fake `is_encrypted=false`.
    DeckSQLManager.swift:5245, DeckSQLManager.swift:5299
    Fixed DirectConnect `authSuccess` phase bypass by adding `pendingAuthSuccess` state validation and accepting success handshake only in legal phases.
    DirectConnectService.swift:333, DirectConnectService.swift:980, DirectConnectService.swift:1025
    Fixed Multipeer `verify_success` bypass by requiring an active verification context before accepting success.
    MultipeerService.swift:1541
    Fixed unintended key regeneration on temporary Keychain errors: only `errSecItemNotFound` creates a new key, all other errors are returned directly.
    SecurityService.swift:111, SecurityService.swift:145, SecurityService.swift:177
    Fixed stale task write-backs after data clearing by adding a unified in-flight task cancellation entry for `clearAllData/clearAll`.
    DeckDataStore.swift:1441, DeckDataStore.swift:1518, DeckDataStore.swift:1721
    Fixed `stop()` not clearing `streamStore` by adding `streamStore.clearAll()`.
    DirectConnectService.swift:275, DirectConnectService.swift:544
    Fixed incomplete `deleteItemById` path by adding blob cleanup and `totalCount` refresh.
    DeckDataStore.swift:1764
    Fixed blob-path collection deletion risk by switching pagination from offset to cursor and adding stable sorting (`ts desc, id desc`).
    DeckDataStore.swift:1809, DeckSQLManager.swift:4378
    Fixed compile error from placing `await` inside `??` expression by splitting into two-step assignment.
    DeckDataStore.swift:1764
    Fixed Cmd+Q prompt wording by replacing "Cursor Assistant feature" with "Queue Mode feature" consistently across languages.
    Localizable.xcstrings:25502
    Fixed multiple potential crashes (force unwraps, abnormal elements, empty screen) by adding type checks and `guard` fallbacks, and removing risky `fatalError` paths.
    IDEAnchorService.swift:401, OrbitWindow.swift:74, OrbitWindow.swift:102, OrbitWindow.swift:149, OrbitWindow.swift:156, DeckDataStore.swift:1420, MainWindowController.swift:69,
    SettingsWindowController.swift:57, UpdatePromptWindowController.swift:34
    Fixed potential process-pipe deadlocks by continuously reading stdout/stderr during execution and correctly closing write ends before waiting.
    LANFileArchiver.swift:324, IDEAnchorService.swift:575, OrbitInstaller.swift:192
    Fixed row-view compile/API integration issues, including `item.colorValue`, thumbnail generation, smart analysis assignment, script-plugin calls, and steganography API usage.
    ClipItemRowView.swift


  -     Localization coverage was completed for new/updated strings across de/en/fr/ja/ko/zh-Hans/zh-Hant.
    Localizable.xcstrings:19297, Localizable.xcstrings:22815, Localizable.xcstrings:2944, Localizable.xcstrings:50219, Localizable.xcstrings:55241, Localizable.xcstrings:45788,
    Localizable.xcstrings:45835, Localizable.xcstrings:45882, Localizable.xcstrings:44852, Localizable.xcstrings:44899
    Some language content was rewritten with native phrasing (de/fr/ja/ko), and long script-settings text now uses `NSLocalizedString`.
    Localizable.xcstrings, ScriptPluginsSettingsView.swift
    This draft is path-sanitized: all references keep only `filename:line` without any absolute path information.


  -     Transform rules are compatible with both new stable codes and legacy values in both display and execution paths.
    `CLI /clip` keeps dual behavior compatibility: rules by default, force direct-save with `raw=1` or `rules=0`, and explicit enable via `rules=1`.
    Plugin refresh supports both automatic and manual modes: directory watching remains active, and manual "Refresh Plugin List" is still available.
    "Immediate Restore" uses dual safeguards and can run only when auto-maintenance restore backup is enabled and a restore backup file exists.


  -     After upgrading, prioritize validation of Smart Rules, especially how "Transform" and "Script Plugin" actions display and execute in your current rule set.
    If external CLI workflows depend on legacy direct-save behavior, explicitly pass `raw=1` or `rules=0` to avoid automation regressions.
    After upgrading, verify vertical layout preference (left/right dock) and confirm search popup and preview window positions match expectations.

---

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.3.0/Deck.dmg)

<!-- release-changelog-bot:tag:v1.2.9 -->
## v1.2.9 — v1.2.9 | eutactic

- **Tag:** `v1.2.9`
- **Published:** 2026-02-28T11:39:09Z

### Release notes

<p align="center">
  <img width="2435" height="1219" alt="Deck" src="https://github.com/user-attachments/assets/f1f010f2-af6f-47a9-866a-c2e7520957c5" />
</p>

---

## Release Notes v1.2.9

### TL;DR
-   Queue mode now uses `Option + Q`, and `Command + Q` in-panel now asks for confirmation to reduce accidental app exits.
-   A new custom trigger key can be recorded or cleared in Settings, and it works alongside the existing preset trigger key.
-   Search now uses adaptive debounce, while Statistics runs concurrent background computation with formatter caching for faster response.
-   Apple Music/Podcasts detection is more accurate, and `apple.co` now waits for metadata confirmation before layout selection.
-   Multiple state and concurrency issues in link preview and statistics were fixed to reduce stuck states and runtime errors.

### Added
-   Added a custom trigger key option: click to record one shortcut combo, with one-tap clear support.
-   Preset trigger behavior remains, while custom shortcut combos can also trigger actions and are persisted.

### Improvements
-   Search now responds instantly on clear and automatically extends debounce under heavy data/safe mode for better balance.
-   Expand/collapse animation timing is tighter, and global animation side effects were removed for cleaner interaction.
-   Statistics processing now runs concurrently in the background with formatter reuse to reduce main-thread pressure.
-   Apple Music now prioritizes track-level matching with collection fallback, and podcast summaries avoid duplicated details.

### Changes
-   Queue mode toggle shortcut changed from `Command + Q` to `Option + Q`.
-   Pressing `Command + Q` in the panel now shows a close-confirmation prompt first.
-   `apple.co` links no longer force Apple streaming layout immediately and now wait for metadata confirmation.

### Fixes
-   Fixed cases where `isLoading` could remain stuck after task cancellation or view disappearance.
-   Tightened URL parsing to reduce false positives where plain text (for example `podcast:true`) was misdetected as a URL.
-   Fixed main-thread isolation issues in statistics background tasks to avoid concurrency-context errors.

### Compatibility & Behavior Notes
-   If you used `Command + Q` for queue mode before, please switch to `Option + Q`.

---

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.2.9/Deck.dmg)

<!-- release-changelog-bot:tag:v1.2.8 -->
## v1.2.8 — v1.2.8 | Crisper

- **Tag:** `v1.2.8`
- **Published:** 2026-02-26T14:18:00Z

### Release notes

<p align="center">
  <img width="2435" height="1219" alt="Deck" src="https://github.com/user-attachments/assets/f1f010f2-af6f-47a9-866a-c2e7520957c5" />
</p>

---

## Release Notes v1.2.8

### TL;DR
-   Replaced the copy-success sound with a new effect for a clearer confirmation cue.
-   Link previews for Apple Music and Podcasts now show artwork, metadata, and RSS links.
-   Apple Music/Podcasts-only visual polish: reduced blank space, 50-char URL truncation, and auto contrast text color.
-   Preview improvements: non-truncated text, optimized code highlighting, higher-resolution images.
-   Fixed image preview sizing/padding regression and state-update warnings in code preview.
-   Increased website favicon in link record previews from 42x42 to 52x52 for better visibility.

### Changes
-   The default copy cue has been switched to a new sound for more direct feedback.
- **Apple Music / Apple Podcasts 元数据**  
  Apple Music/Podcasts link previews with artwork, metadata, and RSS support.
-   Apple Music/Podcasts-only preview style updates: reduced bottom blank area, 50-char URL truncation, adaptive text contrast, and RSS action moved to the footer bar.
-   Clipboard and preview: public.url support, high-res images, non-truncated text/code.
-   Fixed single-image previews being height-capped and resolved the SwiftUI "Modifying state during view update" warning in `SmartContentView`.
-   Fixed a crash caused by simultaneous access when toggling "Paste by Typing" in Settings.

-   Completed all missing translations in `Deck/Resources/Localizable.xcstrings` to zero gaps across `de/en/fr/ja/ko/zh-Hans/zh-Hant`, including update/database/script/error/onboarding/preview strings with real translated text.

-   Added localization lookups in `ScriptPluginService`, `DeckSQLManager`, and `ClipboardItem` for user-facing strings.

-   Standardized localization on `Localizable.xcstrings` only (no placeholder `.strings` files).

### Upgrade Notes
-   After upgrading, copy a short text once to confirm the new volume and tone fit your preference.

---

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.2.8/Deck.dmg)

<!-- release-changelog-bot:tag:v1.2.7 -->
## v1.2.7 — v1.2.7 | Honed

- **Tag:** `v1.2.7`
- **Published:** 2026-02-25T11:15:27Z

### Release notes

<p align="center">
  <img width="2435" height="1219" alt="Deck" src="https://github.com/user-attachments/assets/f1f010f2-af6f-47a9-866a-c2e7520957c5" />
</p>

---

## Release Notes v1.2.7

### TL;DR
-   Connection: immediate "Rejected" on decline/timeout; cooldown countdown; manual retry only after cooldown.

-   Install: single tools folder, one-click install with quarantine cleanup, multi-language help, auto dark/light icon.

-   Orbit: radial app-switching only; removed drag/black-hole paths; code cleanup; more stable.

-   Transfer: resource/stream for large payloads; multi-port fallback; tag sync on share; out-of-order resource/manifest handled; real tag IDs for direct connect.

-   Fixes: tag list refreshes on receive; TOTP live-rotating to reduce verification failures.

-   Welcome onboarding polish: corner/button colors are refined with steadier text transitions, and page 7 is auto-skipped when no importable data is found (6 goes directly to 8).


### Added
-   In the popup panel (⌘P), hold Command and drag any tag to reorder. All tags (system and user-defined) support drag reordering, and the order is persisted automatically.  

  -     Tags move only horizontally during drag; vertical position is locked.  
    Tags follow the cursor exactly with no acceleration or inertia.  
    Left/right boundaries are strictly enforced; tags cannot exceed the visible area.  
    Releasing Command during drag cancels the operation and restores the original order.  
    The dragged tag shows a subtle scale-up and shadow effect for visual distinction.  
    When the dragged tag overlaps another tag, the overlapped tag fades out (reduced opacity) for clearer visual hierarchy.  

-   Standalone scripts are now grouped into `Deck Installer Tools`, including `install.command` and `fix.command`.  

-   The paste queue HUD capsule at the bottom-right can now be dragged to any position on screen. The position is automatically saved and restored. An open-hand cursor appears on hover to indicate draggability, even when the app is in the background.  

-   The new `help.txt` covers all currently supported app languages and explains script purpose plus double-click run steps.  

-   Added `LANFileArchiver` for archiving, extraction, temp-resource claiming, and cleanup in LAN transfer flows.  

-   Added a direct-connect streaming path (`stream_start / chunk / stream_end`) for large payload and archived file transfer.  

-   Added a `resource_manifest` metadata channel in Multipeer so type, timestamp, app name, and tag metadata are restored correctly after resource transfer.  

### Improvements
-   Welcome refinements: 30pt corner radius, black right-side button text/icons in light mode, and steadier page transitions.  

-   Welcome view redesigned with a left-right split layout. Images are anchored bottom-right with overflow clipping. Borderless window with no traffic lights, minimalist black-and-white scheme, Light/Dark adaptive. Navigation buttons overlaid on the image panel with frosted glass material. Each page displays an animated SF Symbol overlay on the image (macOS 15+).  

-   Menu bar icon now uses `document.on.clipboard`, with monochrome by default and hierarchical rendering when paused. Copy events trigger a bounce-up symbol effect for clearer feedback.  

-   The status-bar icon context menu now includes a Feedback entry (same behavior as “Tell us your thoughts”, opening email with the HTML feedback template). A version/update section was also added between Preferences and Quit, showing “Version X.X.X” and a “Check for Updates” action that reuses the About page’s manual update-check flow and presents the update prompt window when a newer version is found.  

-   Tag bar layout is now more intuitive: the Add Tag (+) button and new-tag inline editor sit inside the tag area directly after the last tag, while settings, pause/resume, quit, and feedback stay on the right. These controls are now transparent by default and show highlight only on hover, matching the search-button behavior.  

-   The right-top and right-bottom corners of the settings sidebar now have rounded corners for a softer transition between the sidebar and content area. The previous 1px straight divider line has been replaced with a subtle rightward shadow for depth. The content area extends slightly behind the sidebar to fill rounded-corner gaps, ensuring pages with white backgrounds (e.g. Orbit) don't expose gray corners.  

-   The statistics page has been redesigned with a minimalist style: overview stats merged into a single card with number formatting; the data security notice is now a compact capsule badge; type distribution chart now has a side legend with percentages; top apps rows feature inline progress bars with percentage display; the 7-day activity chart uses narrower bars with gradient fills; storage info is integrated into the overview card footer.  

-   A "Cursor Assistant" capsule badge is now shown next to the Template Library title, clarifying its purpose. The subtitle and usage tips card have been rewritten with a step-by-step guide format explaining the full workflow of creating templates, setting trigger words, and quick invocation.  

-   The Add Trigger Word sheet has been redesigned: header now includes an icon and description; text field uses a custom style; match type selector replaced with custom tab buttons; type selection grid uses a horizontal layout with cleaner selection states; bottom button hit area now covers the full region.  

-   The Smart Rules editor UI has been refined: the "All/Any" match mode selector is replaced with custom capsule-style buttons; condition and action items now use card-like rows with icons for better visual hierarchy; the Add Condition/Action sheets remove excess whitespace with content-adaptive height.  

-   The maintenance description now uses icon-labeled rows instead of plain text; the report sheet header is centered with a circular icon background, card titles use small-caps style, metric values use rounded monospace font, and the close button has a custom style.  

-   Steganography passphrase field now has a leading icon (lock/key) with monospaced font; save and clear buttons use capsule-style with fill backgrounds; security mode info uses icon-labeled rows instead of bullet list; OCR language icons are now differentiated per language; storage info section removes the trailing divider.  

-   Added syntax highlighting to settings code samples (Script Plugins and CLI Bridge), improving readability for keywords, strings, numbers, comments, and variables.  

-   The right-side status feedback is clearer: red reject/cooldown messaging while waiting, then a blue retry action when ready.  

-   Version number now uses a capsule badge style; "Core Features" and "Smart Features" are merged into a single "Features Overview" card; shortcut badges now mimic keyboard keycaps (rounded corners + subtle shadow + border); "Updates" and "Feedback" are merged into one card.  

-   Search bar refactored to a collapse/expand pattern: shows only a magnifying glass icon by default (flat, no shadow, circular hover highlight); smoothly expands into a capsule search bar (300pt) on click or keyboard input; auto-collapses when blurred with empty query. Global keyboard capture, Chinese IME compatibility, and `/` slash command all preserved. Tag chips now sit directly next to the search icon; clicking the content area outside the top bar exits search mode (clicking tags or the rule picker popup does not).  

-   The three empty-state icons in the popup panel (tag has no records, clipboard is empty, no results found) now use `doc.on.clipboard` with hierarchical symbol rendering, automatically adapting to light and dark mode.  

-   The new status copy is fully localized, keeping connection feedback consistent across supported languages.  

-   Localized system-facing copy across export/import dialogs (success/failure/count), biometric auth defaults and cancel label, update notification title/body, updater status texts, accessibility permission dialogs, iCloud sync error messages, and Orbit installer error prompts.  

-   The new installer script now clears quarantine during installation to reduce manual Security & Privacy unblock steps.  

-   `Deck.app` and `Applications` remain in the main area, with the tools folder placed below for a clearer first-install flow.  

-   The installer icon now uses the 1024 logo by default and adapts automatically to dark/light appearance.  

-   Orbit demo visuals were simplified by removing black-hole/AirDrop overlays and drag-dissolve chains, while keeping click/hover/keyboard core interactions.  

-   Receive flow now enforces clearer per-message and total-buffer limits, rejecting bad payloads earlier to reduce stalls and misparsing.  

-   Panel show/hide animation shortened (0.16s / 0.18s) with easeOut on show for snappier close and gentler expand stop.  

-   Hotkey throttling and key-release detection added to prevent panel flash and jank from key-repeat or rapid presses; toggle requests are ignored during active animation.  

-   Panel close no longer runs purgeMissingFileItems and clearExpiredData immediately; cleanup is deferred ~0.6s to avoid main-thread stalls during rapid toggles.  

-   Activation and makeKeyAndOrderFront order adjusted: app activates before panel animates; post-animation re-activation only when needed, reducing “panel visible but not focused” stalls.  

-   Copy/Cut monitor now filters key events in-place; only ⌘C and ⌘X trigger detection, avoiding Task creation and main-thread switches on every keystroke to reduce background energy use.  

-   Hotkey settings are now cached and synced via UserDefaults notifications; keyDown callbacks use a fast path to process only V key and Typing Paste shortcut, avoiding JSON decode and main-thread hops on unrelated keys.  

-   Pause countdown UI now uses .task + Task.sleep instead of Timer.publish; tick only when paused with an end time; indefinite pause no longer triggers periodic wakeups, reducing CPU activity.  

-   Search bar expand/collapse now uses a custom timingCurve; background unified to RoundedRectangle with conditional fill; icon uses scaleEffect instead of font switching for smoother transitions.  

-   Group sharing now automatically falls back to per-item resource transfer when file URLs or large payloads are included, avoiding oversized group-send failures.  

-   Received resource files are now moved into app-controlled temp storage before processing, preventing read failures from OS temp cleanup.  

### Changes
-   Welcome now pre-scans in background and auto-hides page 7 when no importable content is found (6 goes directly to 8).  

-   The Beta badge next to Cursor Assistant and LAN Sharing settings headers has been removed; both features are now considered stable.  

-   “Retry in X” is now an action hint rather than an automatic action; the app will not auto-reconnect after countdown.  

-   Installer helpers in the DMG are changed from two standalone scripts to a single tools folder to reduce visual clutter.  

-   Orbit now follows a single-mode app-switching flow by default, without clipboard-ring switching or jump-model prediction ordering.  

-   The three empty-state icons in the popup panel (tag has no records, clipboard is empty, no results found) now use `doc.on.clipboard` with hierarchical symbol rendering, automatically adapting to light and dark mode.  

-   Top bar padding reduced from 14pt to 10pt for a more compact panel appearance.  

-   File URLs are no longer sent as inline blobs; they are archived for transfer and restored on the receiver.  

-   Single-item payloads now include `contentLength`, `timestamp`, `appName`, `tagName`, and `tagColor` for better context restoration.  

-   Payloads above threshold now auto-switch to resource transfer (Multipeer) or streaming (Direct), while small items stay inline.  

### Fixes
-   Fixed visible horizontal drift of left text during onboarding page transitions.  

-   Fixed an occasional index-out-of-range crash in `WelcomeView` page switching (`pages[currentPage]`), preventing `Swift/ContiguousArrayBuffer.swift:691: Fatal error: Index out of range`.

-   Fixed the issue where sender-side status could remain “Connecting” after a decline or timeout.  

-   Reduced repeated invitation popups by enforcing cooldown and manual retry flow.  

-   Fixed a SwiftUI `ForEach` duplicate-ID warning when detected content contains repeated values (such as multiple `127.0.0.1`), improving list rendering stability.  

-   Fixed a variable parsing issue in `release.sh` that could trigger an unbound-variable error in some environments.  

-   Fixed a compile issue in Orbit window controller context-process resolution after simplification by correcting the return-type implementation.  

-   Reduced priority-inversion performance warnings when closing the panel by streamlining focus teardown and avoiding main-thread waits.  

-   Fixed a focus-return race when pressing ESC immediately after opening the panel; focus now reliably returns to the previous app instead of staying on Deck.  

-   Old app backups (`.Deck.app.old.*`) in `/Applications` are now automatically removed on startup after an update, preventing accumulation.  

-   Fixed delayed tag visibility for single-item resource receive by refreshing the tag list immediately after tag creation.  

-   Fixed intermittent LAN failures for heavy payloads by replacing one-shot large sends with resource/stream transfer.  

-   Fixed occasional temp-file loss on receive by moving resources before decode, avoiding cleanup after callback return.  

-   Fixed direct-connect failures when the default port is occupied by adding automatic port fallback.  

-   TOTP is now computed live against the current time window, preventing failures caused by countdown changes while code stayed static.  

-   Continuation state is now cleared on early verify-request failures (encode/session/send), preventing later double-callback risks.  

-   Fixed resource drops caused by arrival-order mismatch by adding resource-first then manifest matching on receiver side.  

-   Added cleanup on receive-failure, service stop, and stale-cache paths to reduce temp-file buildup.  

-   In security mode, unverified resources are now rejected and cleaned immediately instead of being queued.  

-   Fixed direct-connect tag ID mapping by using real IDs and maintaining tag display order consistency.  

-   Receiver-side TOTP dialog now closes immediately when cancel is tapped.  

-   Removed an unused weak-capture binding in direct-send `sendItem`, eliminating the compiler warning.  

-   Fixed type-mismatch compile errors in HotKeyManager global hotkey event handling by aligning `InstallEventHandler` argument types: casting `paramErr` to `OSStatus` and passing event count as `Int`.  

-   Fixed no-feedback behavior of the Typing Paste shortcut cancel button. When the shortcut is already the default `⌘⌥V`, the cancel button is now dimmed/disabled; it becomes clickable only after customization to reset back to default.  

-   Adjusted rule-picker panel refresh timing to avoid layout-recursion warnings during active layout, improving popup stability.  

-   Added filtering for system processes that are unsuitable for title queries, reducing `task name port` log noise while preserving normal detection behavior.  

-   Added archive extraction boundary protection by validating zip entries before extraction and verifying output/symlink paths after extraction to prevent path escape.  

-   Temp artifacts are now cleaned immediately when `resource_manifest` sending fails, preventing file buildup.  

-   Connection invitations now carry `securityMode` context, and the receiver parses it to keep peer security-mode state in sync.  

-   Group transfer is now all-or-nothing for encryption: send fails if any item fails to encrypt, and receive drops the whole group if any item fails to decrypt.  

-   Verification flow now has busy protection and peer binding checks; `verify_success` without a valid secret now fails instead of being treated as success.  

-   Direct receive buffer now enforces limits before append; overflow/invalid-length payloads trigger immediate connection rejection to reduce DoS and state corruption risks.  

-   Reject/reconnect paths now mark disconnected first, preventing stale “connected” UI state.  

-   Sender no longer accepts empty AES-GCM `combined` output; PSK fallback now uses valid key length, and invalid PSK during challenge handling now rejects the connection immediately.  

-   Archive receive destination now uses sanitized `transferId` components to reduce path-injection risk.  

### Compatibility & Behavior Notes
-   After dragging the app into `Applications`, macOS will not auto-run scripts inside the DMG; run the needed script manually.  

### Upgrade Notes
-   v1.2.7 covers LAN connection and transfer (reject state, cooldown retry, large-payload streaming, multi-port fallback, tag sync), security and verification (live TOTP, encryption consistency, Zip Slip protection), install experience (tools folder, one-click install, multi-language help), and extensive UI improvements. Upgrade recommended for all users.

---

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.2.7/Deck.dmg)

<!-- release-changelog-bot:tag:v1.2.6 -->
## v1.2.6 — v1.2.6 | Hardened

- **Tag:** `v1.2.6`
- **Published:** 2026-02-23T11:59:17Z

### Release notes

<p align="center">
  <img width="2435" height="1219" alt="Deck" src="https://github.com/user-attachments/assets/f1f010f2-af6f-47a9-866a-c2e7520957c5" />
</p>

---

## Release Notes v1.2.6

### TL;DR
-   Improved bank-card and identity-number detection to reduce false positives in long text, so copied error/log content is more reliably saved.  
-   Fixed a tag-loss case where recopying the same content could reset a tagged item back to “untagged”.  
-   Refined matching flow and pre-checks to cut unnecessary scans, making detection faster and steadier under frequent copy events.  
-   Added clearer wording in "Settings > Privacy" to explain that only the last 24 hours of memory curves and related error info are uploaded, with anonymization applied.  
-   Network permission for script plugins is now strictly hash-bound; changed scripts no longer reuse old authorization and must be re-approved.  
-   The update proxy now degrades gracefully when `RATE_LIMITER` is missing or unhealthy (instead of hard 503); set `RATE_LIMIT_FAIL_CLOSED=true` for strict blocking behavior.  
-   Fixed a case where vec writes could still target an old default table right after recovery, causing “recovery completed but immediate upsert failure”; recovery tables are now preferred.  
-   Improved vec cleanup resilience: when sqlite-vec shadow-table restrictions apply, cleanup is deferred instead of force-dropping, reducing repeated `may not be dropped` noise.  
-   Added safer storage maintenance/migration guards: skip `VACUUM` when vec is active and abort migration if `WAL checkpoint` fails, reducing vec-structure inconsistency risk.  
-   Backfill scheduling now checks only vec virtual tables (excluding shadow tables), and upsert-failure log timing is corrected to avoid misleading recovery-order impressions.  

### Security & Delivery Hardening
-   The update Worker adds `RATE_LIMIT_FAIL_CLOSED` (default `false`) to choose between fail-open and fail-closed behavior when the rate limiter is unavailable.  

### Improvements
-   Sensitive detection now uses a combined decision based on context and content shape instead of single-pattern hits, improving overall usability.  
-   Added lightweight pre-checks for bank-card detection to avoid unnecessary computation on large text.  
-   Tuned the popup panel layout by insetting 7 px on both sides and shifting it up 7 px while keeping height unchanged, preserving centered alignment with a tighter look.  
-   Refined queue-mode status bar alignment: the left info group shifts 5 px right, while right-side hints and Clear/Exit shift 3 px left for a more balanced layout.  
-   Removed the gray underlay and depth shadow beneath history cards to give the list area a cleaner, flatter appearance.  

### Fixes
-   Fixed poor visibility of the "All" tag dot in dark mode when selected; it now uses a clearer light-gray indicator color.  
-   Fixed a false-positive issue where long app error/log text could be blocked when bank-card or identity-number detection was enabled.  
-   Preserved existing manual tags during duplicate-content upserts, preventing tag overwrite to untagged.  
-   Tagged items are no longer auto-deleted when source files go missing; they are kept and marked as missing-file entries.  
-   Cloud merge now avoids overwriting an existing local tag when the incoming cloud record is untagged.  
-   Fixed vec active-table fallback behavior by no longer persisting default-table mappings; recovery tables are now preferred for read/write routing when present.  
-   Fixed vec write/search routing during table-switch windows by re-resolving the active table before operations, reducing chained `vec upsert internal error` failures.  
-   Fixed repeated cleanup spam by avoiding direct deletion of sqlite-vec shadow subtables (such as `_chunks/_info/_rowids`); failed cleanup is deferred instead.  
-   Fixed shadow-table pollution in vec-table discovery by restricting enumeration to `CREATE VIRTUAL TABLE ... USING vec0`, preventing `_chunks/_info/_rowids` from being treated as active index tables.  
-   Fixed false “backfill not needed” decisions by basing checks on real vec virtual tables, and moved failure-log decisions into the same write flow to avoid delayed same-failure logs after recovery completion.  

### Performance
-   Streamlined clipboard hot-path by removing duplicate ignore checks and moving smart line-break cleanup off the main thread to reduce UI pressure during frequent copies.  
-   Replaced OFFSET-based fallback scans with keyset/cursor pagination for fuzzy search expansion, improving scalability on large datasets.  
-   Optimized regex matching in security mode by cutting per-row temporary string joins and using a limit-aware scan cap to reduce CPU spikes.  
-   Moved batch `row -> ClipboardItem` mapping off the DB serial queue to a background concurrent queue, reducing contention between pagination and queries.  
-   Storage-size directory traversal in Settings now runs in background with throttling and cancellation to avoid UI hitches.  
-   Reduced unnecessary history-list reordering and array rewrites by gating reorder triggers and skipping assignments when order is unchanged.  

### Notes
-   Diagnostics uploads are limited to the minimum required scope and remain anonymized, without other personal information.  

### Upgrade Notes
-   Recommended for all users, especially if you frequently copy debug logs, stack traces, or long text, to reduce false blocking.  

---

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.2.6/Deck.dmg)

<!-- release-changelog-bot:tag:v1.2.5 -->
## v1.2.5 — v1.2.5 | Auspicious

- **Tag:** `v1.2.5`
- **Published:** 2026-02-16T04:58:40Z

### Release notes

<p align="center">
  <img width="2435" height="1219" alt="Deck" src="https://github.com/user-attachments/assets/1ce80c83-7dc5-43da-8007-c7e682cf6e71" />
</p>

---

## Release Notes v1.2.5

### TL;DR
-   Added high-confidence text format detection, so Diff/Patch, LilyPond, and XML family formats (including SVG/Plist) are recognized first with fewer wrong file extensions.  
-   Maintenance now follows a “snapshot first, deletion second” flow; if snapshot creation fails, destructive deletion is skipped to prevent irreversible loss.  
-   Polling, log writing, network interface probing, and permission timers were optimized for lower overhead and better long-running stability.  
-   iCloud sync state handling and LAN transfer fault tolerance were improved to reduce interruptions in edge cases.  
-   File-path parsing plus thumbnail/image-size/Base64 image caching flows are now more consistent, reducing misclassification and runtime issues.  
-   Version 1.2.5 bundles four patch groups (detection, performance, stability, and maintenance safety); upgrading is strongly recommended.  

### Added
-   Added a `j/k navigation direction` option in `Settings -> Keyboard -> VIM Mode`, so you can switch between `j→ k←` and `j← k→`.  
-   Smart filename generation now prioritizes high-confidence formats such as Diff/Patch, LilyPond, and XML family types (including SVG/Plist), reducing language-based misclassification.  
-   Added regression coverage for Diff/Unified Diff/Hunk snippets, Markdown separators, LilyPond, XML, and Swift/JSON/URL/plain text scenarios.  

### Improvements
-   Poll-bound calculations now use short-lived caching, and link prefetch/status-bar pulse paths avoid unnecessary async hops to reduce hot-path overhead.  
-   Cloud change token handling now uses locking plus caching, and fetch-state queue reuse reduces repeated decoding and transient queue creation.  
-   App-prefix matching now uses pre-sorted caching, while export/diagnostics/feedback/text-transform date formatting avoids repeated formatter allocation.  
-   LAN direct-connect interface caching now uses locking and refresh de-duplication with a reused monitor queue to avoid repeated probe tasks.  
-   Debug/Info logs are now call-site throttled, and file logging uses buffered batch flushes to reduce log storms and disk I/O pressure.  
-   Timer tolerance is now set for LAN confirmation views and permission polling to reduce unnecessary wakeups.  

### Changes
-   Retention-based cleanup now applies only to untagged items (`tag_id == -1`), while user-tagged content is preserved by default.  
-   Record deletion now happens only after rollback snapshot creation succeeds; if snapshot creation fails, deletion is skipped for safety.  
-   Snapshot replacement now persists the new snapshot first and deletes the old one afterward, preventing rollback gaps on mid-process failure.  
-   Force full sync now clears sync errors and resets the change token before entering the standard fetch pipeline for more consistent state handling.  

### Fixes
-   Fixed an intermittent crash when reading IDE caret context during text copy capture.  
-   Fixed an issue where Deck panel could unexpectedly hide after clicking category tags (such as “All/Text/Image/File”) on external displays.  
-   Fixed an issue where the panel appeared with square corners on macOS versions below 26.  
-   Fixed a stale preview issue in the `Command+P` panel: when preview is open (via Space), deleting the current item now immediately updates preview to the new current item, or closes it when no items remain.  
-   Added fallback parsing for text payload types like `public.html`, `public.utf16-plain-text`, and `public.utf16-external-plain-text`, reducing false “Deck can’t parse this clipboard content” cases in apps such as Microsoft Edge, Kiro, and WeChat.  
-   Pause menu item insertion now checks optionals first, avoiding force-unwrapping crashes during initialization.  
-   Cache flows for URL/color/file paths/thumbnails/Base64 images/image size now use stronger locking and consistent updates, reducing concurrency-related failures.  
-   File list parsing now supports both `file://` URLs and plain path strings, reducing path resolution failures.  
-   Multiple filter-expression builders were changed to avoid force-unwrapping, preventing nil-related crashes in complex rule combinations.  
-   Preview-thumbnail emptiness checks now use safer logic, preventing failure paths in medium/large image workflows.  
-   Global hotkey handling now validates pointers and status codes; install/remove failures are logged and state is safely recovered.  
-   Added bounds checks in TOTP truncation and safe-guarded missing shared keys in LAN transfer to avoid runtime interruption.  
-   Orbit overwrite-install now surfaces backup failures explicitly instead of silently continuing with inconsistent state.  
-   Icon cache now safely falls back to base icons when sized-copy creation fails, avoiding cache-path crashes.  
-   Maintenance scan now skips records whose stored blob path still exists, avoiding false broken-link detection.  
 Updated queue usage in `nonisolated` network-interface probing to avoid main-actor isolation compile errors under Swift 6.  

### Compatibility & Behavior Notes
-   When an editor returns invalid line/column context, Deck now skips invalid position data and continues capturing content.  
-   Tagged items are excluded from retention-based automatic cleanup and remain preserved by default.  
-   If rollback snapshot creation fails during maintenance, destructive record deletion is skipped and only non-destructive flows continue.  

### Upgrade Notes
-   This release mainly addresses stability, and all affected users are encouraged to upgrade.  

---

### A Note from the Author

>
>
> *To everyone who supports Deck: your feedback and patience have helped shape Deck into a more stable and more useful tool. Wishing you a rewarding and inspired Lunar New Year 2026.*

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.2.5/Deck.dmg)

<!-- release-changelog-bot:tag:v1.2.4 -->
## v1.2.4 — v1.2.4 | Efficient

- **Tag:** `v1.2.4`
- **Published:** 2026-01-30T01:31:59Z

### Release notes

<p align="center">
  <img width="2435" height="1219" alt="Deck" src="https://repository-images.githubusercontent.com/1111053300/a02138b8-d501-4d33-8c56-7a896d4ef6cb" />
</p>

---

## Release Notes v1.2.4

### TL;DR
-   `NSScrollView` wheel-delta mapping + clamping + keyboard focus switching.  
  _HistoryListView.swift_  
-   Field-based matching (`title/text/appName`) + `lang:` (Beta) / `len:` rules.  
  _SearchService.swift_ _SearchRuleFilters.swift_ _TokenSearchTextView.swift_ _TopBarView.swift_  
-   Background Base64 detection/decoding with fast rejects, sampling, and hard caps.  
  _ClipItemCardView.swift_ _ClipboardItem.swift_  
-   Async file-size computation + `NSCache` caching to avoid scroll stalls.  
  _ClipItemCardView.swift_  
-   One-click maintenance + report sheet + 5-minute rollback snapshot.  
  _StorageMaintenanceService.swift_ _DeckSQLManager.swift_ _SettingsView.swift_ _StorageMaintenanceReportSheet.swift_  

### Added
-   Image cards now show file size under dimensions; displays “Calculating…” while processing and auto-refreshes when ready. Size is computed asynchronously and cached via `NSCache`.  
  _ClipItemCardView.swift_  
-   Filter/exclude by detected code language; case-insensitive, supports `+` multi-select with common aliases (e.g., js/ts/c#/cpp/yml/md). Adds a Beta badge and performance note in the rule picker.  
  _SearchRuleFilters.swift_ _SearchRulePickerView.swift_ _Localizable.xcstrings_  
-   New maintenance entry with progress UI, a report sheet, and a rollback snapshot available for 5 minutes.  
  _StorageMaintenanceService.swift_ _DeckSQLManager.swift_ _SettingsView.swift_ _StorageMaintenanceReportSheet.swift_  
-   Adds icon caching to reduce system icon lookups for more stable rendering in lists and previews.  
  _IconCache.swift_ _PreviewWindowController.swift_ _PreviewOverlayView.swift_ _ClipboardItem.swift_ _ClipboardCardView.swift_ _ClipItemCardView.swift_ _PrivacySettingsView.swift_ _StatisticsView.swift_ _PDFPreviewView.swift_  
-   Adds a new setting “General → Behavior → Hide Dock when panel opens”, enabled by default; turning it off restores the original Dock behavior (e.g., magnification on hover).  
  _SettingsView.swift_ _MainWindowController.swift_ _UserDefaultsManager.swift_ _Localizable.xcstrings_  

### Improvements
-   Smoother history scrolling with vertical-wheel-to-horizontal mapping, clamping, and interaction refinements for large histories.  
  _HistoryListView.swift_  
-   When `contextTypes` is empty, fall back to DB order to avoid a full-copy COW triggered by shared storage between `orderedItems` and `dataStore.items`, and ensure `selectedId` always resolves within the current list.  
  _HistoryListView.swift_  
-   Natural focus switching: Down moves focus from search to list without clearing text; Up returns to search (when no modifier keys are held).  
  _HistoryListView.swift_  
-   Field-based matching across `title/text/appName` for exact/regex/fuzzy; avoids concatenating huge strings, reducing CPU and transient memory pressure.  
  _SearchService.swift_  
-   `lang:` now runs after non-language rules narrow candidates; language detection uses a lighter-weight path and adds signature-based caching + warming to reduce redundant work.  
  _SearchRuleFilters.swift_ _DeckDataStore.swift_  
-   Markdown previews read only the first 16KB with a truncation hint to avoid stalls on large files.  
  _LargeTextPreviewView.swift_  
-   Lazy logging plus thread-local `DeckFormatters` reuse Number/Date/Relative formatters to reduce object churn and formatting costs on hot paths.  
  _AppLogger.swift_ _DeckFormatters.swift_  
-   Adds an ultra-light pre-check to avoid spawning Base64 tasks for normal text; adds cancellation handling for `Task.detached` to reduce task storms and wasted work.  
  _ClipItemCardView.swift_  
-   Link preview regex now reuses a RegexCache (with options) to avoid repeated compilation and CPU spikes.  
  _SmartRuleService.swift_ _LinkPreviewCard.swift_  
-   Makes SmartTextService hot paths lighter: `isLikelyAssetFilename` now uses plain string checks instead of regex, bare-domain validation reuses cached regex, and `matches(for:in:)` uses `enumerateMatches` to reduce intermediate allocations (no behavior change).  
  _SmartTextService.swift_  
-   Splits IconCache into base/sized caches and adds `icon(forFile:size:)`, reducing `.copy()` allocations and redundant work for more stable list/preview rendering.  
  _IconCache.swift_  
-   Further reduces allocations on ClipboardItem hot paths: caches URL/`normalizedFilePaths`, makes text/RTF sampling index-limited, extracts filenames via `NSString`, and routes PDF/file icons through the new size API.  
  _ClipboardItem.swift_ _IconCache.swift_  
-   Adds faster pre-checks and lightweight caching: quick URL-sanitization guard, 0.4s TTL cache for sensitive-title checks, index-limited ID sampling, and static bank-card prefixes to reduce repeated setup.  
  _ClipboardService.swift_  
-   Makes semantic-text truncation index-limited to avoid extra scans/allocations on long content.  
  _SemanticSearchService.swift_  
-   Improves drag-and-drop image type detection (especially WebP) using `withUnsafeBytes`, reducing unnecessary parsing overhead.  
  _ClipItemCardView.swift_  
-   Saves/restores `NSApp.presentationOptions` and temporarily toggles `.hideDock` during panel show/hide to prevent Dock interactions from interfering while the panel is active; adds delayed hide/restore (`scheduleDockSuppression(...)`) to avoid a quick Dock “flash” when the panel appears (macOS `.hideDock` has no fade animation). Defaults: `dockHideDelay = -1`, `dockShowDelay = 0.10`.  
  _MainWindowController.swift_  
-   Adds memory guardrails for unsupported payloads (total budget + per-type caps, skipping images) and prefers writing `NSURL` for file pastes while keeping the existing fallbacks for compatibility.  
  _ClipboardService.swift_  
-   Adds a hard 30MB cap for incoming data; oversized payloads are dropped and logged to prevent memory blow-ups.  
  _MultipeerService.swift_  

### Changes
-   The old `size:` rule is renamed to `len:` (numeric only); text-like items are filtered by length while non-text items are kept but de-ranked.  
  _SearchRuleFilters.swift_ _TokenSearchTextView.swift_ _TopBarView.swift_ _Localizable.xcstrings_  
-   Pushes length filtering down to the database where possible to reduce in-memory scanning and improve responsiveness.  
  _DeckDataStore.swift_  
-   Horizontal scrolling direction is corrected for more intuitive behavior (e.g., Magic Mouse swipe-left moves content to the right).  
  _HistoryListView.swift_  

### Fixes
-   Fixes multiple Swift 6 build issues related to concurrency captures, main-actor isolation, and missing `await`, using minimal-intrusion adjustments to preserve behavior.  
  _BlobStorage.swift_ _DataExportService.swift_ _DeckDataStore.swift_ _SearchRuleFilters.swift_ _ClipItemCardView.swift_ _StorageMaintenanceService.swift_ _DeckSQLManager.swift_  
-   Reduces stalls from extremely long content by moving Base64 checks/decoding off the main thread with fast rejects and hard limits.  
  _ClipItemCardView.swift_ _ClipboardItem.swift_  
-   Color parsing now prefers trimmed plain text, fixing cases where RTF/RTFD sources failed to render the color swatch.  
  _ClipboardItem.swift_  
-   URL sanitization now preserves original pasteboard types and enforces a copy size limit to reduce risk from abnormal content.  
  _ClipboardService.swift_  
-   Restores the original pasteboard snapshot when paste fails, preventing accidental clipboard clearing.  
  _ClipboardService.swift_  
-   Fixes maintenance flow issues including actor-isolation access, missing SQLite expression operators, and compression stream initialization.  
  _StorageMaintenanceService.swift_ _DeckSQLManager.swift_  
-   Make snapshot expiry timers cancel-safe (cancel returns immediately) to avoid “cancel == expire now”; also move missing-file scans and blob deletion work off `MainActor` to reduce UI impact during maintenance.  
  _StorageMaintenanceService.swift_  
-   Fixes 4 concurrency-isolation build errors in maintenance snapshots by snapshotting `ClipboardItem` id/paths on `MainActor`, moving file-existence checks back to background work, and running blob deletions on `MainActor`.  
  _StorageMaintenanceService.swift_  
-   Runs `log.warn` inside a `MainActor` task to avoid accessing the main-actor-isolated logger from a `nonisolated` context, fixing a concurrency-isolation build error.  
  _MultipeerService.swift_  
-   Pins the search debounce `Task` to `MainActor` to avoid Swift 6 `@Sendable` capture warnings.  
  _DeckViewModel.swift_  
-   Runs post-close expired-data cleanup as a `MainActor` task to avoid cross-isolation access and subtle instability.  
  _MainWindowController.swift_  
-   Adds a fallback to `Caches`/temporary directories when the token folder is unavailable, preventing a `first!` crash.  
  _OrbitBridgeAuth.swift_  
-   Adds the missing `.databaseError` observer and removes all related observers on `applicationWillTerminate` (including pause/orbit) to avoid leaks and duplicate callbacks.  
  _AppDelegate.swift_  
-   Guards debug preview string building behind `log.isEnabled(.debug)` and adds an `isEnabled(_:)` API to avoid unnecessary string formatting when debug logging is off.  
  _AppLogger.swift_ _DeckDataStore.swift_ _HistoryListView.swift_  
-   Fixes localization coverage by filling missing translations and removing stale, unreferenced keys.  
  _Localizable.xcstrings_  
-   Rule parsing supports `size:`/`len:` compatibility and returns the real prefix length to avoid token offset drift.  
  _SearchRuleFilters.swift_  
-   Mirrors the same cancel-safe expiry timer behavior in the Settings UI to avoid accidental triggers during cleanup/rollback interactions.  
  _SettingsView.swift_  

### Notes
-   The About page now prefers `NSHumanReadableCopyright` for the footer, with a fallback to the previous text.  
  _SettingsView.swift_  
-   `lang:` is Beta and may add overhead on very large datasets due to language detection; the rule picker includes a warning.  
  _SearchRulePickerView.swift_ _Localizable.xcstrings_  

### Upgrade Notes
-   Recommended if you experience scrolling/search stalls.  
  _HistoryListView.swift_ _SearchService.swift_ _SearchRuleFilters.swift_ _ClipItemCardView.swift_ _AppLogger.swift_  

---

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.2.4/Deck.dmg)

<!-- release-changelog-bot:tag:v1.2.3 -->
## v1.2.3 — v1.2.3 | Monumental

- **Tag:** `v1.2.3`
- **Published:** 2026-01-27T07:15:38Z

### Release notes

<p align="center">
  <img width="2435" height="1219" alt="Deck" src="https://repository-images.githubusercontent.com/1111053300/a02138b8-d501-4d33-8c56-7a896d4ef6cb" />
</p>

---

## Release Notes v1.2.3

### Added
-   Major feature: type / in the search box to open the rule panel above the field. The list mode shows 6 rules; navigate with ↑↓ / j/k / 1–6, press Enter to insert a prefix (app/date/type or -app/-date/-type), and Esc closes the panel. After insertion, the cursor stays after the prefix for immediate value input; Space ends the value and continues keywords, / chains another rule; supports + multi-values and quoted app names with spaces. Delete/Backspace at the prefix/value boundary removes the whole rule (value + trailing space), and Esc in hint mode deletes the current rule and returns to search.  
  _SearchRuleFilters.swift_, _TopBarView.swift_, _TokenSearchTextView.swift_, _SearchRulePickerView.swift_, _SearchRulePickerPanelController.swift_, _DeckViewModel.swift_, _Localizable.xcstrings_  

-   Add per-item custom titles across model, storage, search, and UI, shown in card/preview headers.  
  _DeckSQLManager.swift_, _ClipboardItem.swift_, _DeckDataStore.swift_, _SearchService.swift_, _ClipItemCardView.swift_

-   Custom titles now flow through sync, export, and intents for cross-device consistency.  
  _CloudSyncService.swift_, _DataExportService.swift_, _DeckIntents.swift_

-   Smart Rules now include a “has custom title” condition selectable in the editor.  
  _SmartRuleService.swift_, _SmartRulesView.swift_, _Localizable.xcstrings_

-   Recognize Figma clipboard payloads with dedicated card/preview UI and parse only when the preview opens.  
  _ClipboardItem.swift_, _ClipItemCardView.swift_, _FigmaClipboardRenderService.swift_, _FigmaClipboardPreviewView.swift_, _PreviewWindowController.swift_

-   Add a “Show QR Code” button in the preview info bar for links, matching the context menu behavior.  
  _PreviewWindowController.swift_

-   “Go to Settings to add a device” now opens the LAN tab via shared settings navigation state.  
  _SettingsView.swift_, _SettingsWindowController.swift_, _ClipItemCardView.swift_

-   Add a toggle and configurable hotkey (default ⌘⌥V); when off, the combo is no longer intercepted.  
  _UserDefaultsManager.swift_, _HotKeyManager.swift_, _PasteQueueService.swift_, _SettingsView.swift_, _Localizable.xcstrings_

-   Show missing-file warnings and auto-purge missing items after the panel closes.  
  _ClipboardItem.swift_, _ClipItemCardView.swift_, _PreviewOverlayView.swift_, _PreviewWindowController.swift_, _DeckDataStore.swift_, _MainWindowController.swift_

### Deck × Orbit
-   Orbit summaries now include customTitle for consistent CLI/integration output.  
  _OrbitCLIBridgeService.swift_

### Improvements
-   Search supports ⌘A select-all (only with a non-empty query) and ⌘V paste; tag editing also supports ⌘A/⌘V.  
  _HistoryListView.swift_, _TopBarView.swift_, _DeckViewModel.swift_

-   Suppress auto-focus on panel open, avoid auto-search during rename, and elevate UI dispatch to userInteractive.  
  _MainWindowController.swift_, _HistoryListView.swift_, _TopBarView.swift_, _DeckViewModel.swift_

-   Figma preview uses a two-column layout with simplified localized info, and auto-inverts the icon in dark mode.  
  _FigmaClipboardPreviewView.swift_, _FigmaClipboardRenderService.swift_, _ClipItemCardView.swift_, _Localizable.xcstrings_

-   Add an LRU cache with a 500-item cap for link metadata and refresh order on hits to reduce memory.  
  _LinkPreviewCard.swift_

-   Run WAL checkpoint and file copy in the same dbQueue to avoid inconsistent backups during writes.  
  _DeckSQLManager.swift_

### Changes
-   Custom titles are capped at 12 characters (trimmed on save) and auto-scale to fit the header.  
  _ClipItemCardView.swift_, _Constants.swift_

-   Search now matches custom titles; title hits are stably promoted to the front without reordering within groups.  
  _DeckDataStore.swift_, _SearchService.swift_

-   Renaming a title re-evaluates Smart Rules, while ignore/transform actions remain ingestion-only.  
  _DeckDataStore.swift_

-   Only rule prefixes inserted via / are parsed; manually typed app:/date:/type: is treated as plain text.  
  _SearchRuleFilters.swift_, _TopBarView.swift_, _TokenSearchTextView.swift_

-   Rules now support -app/-date/-type exclusion and + multi-values; type drops email/phone and adds color; multi-word app names require quotes.  
  _SearchRuleFilters.swift_, _Localizable.xcstrings_, _DeckViewModel.swift_

-   Simulated typing paste sends Shift+Enter for newlines instead of a direct Return.  
  _PasteQueueService.swift_

-   Focus mode no longer records only text; rich text, files, and images are retained.  
  _ClipboardService.swift_

-   New Figma entries no longer write search text to avoid polluting search results.  
  _ClipboardService.swift_

### Fixes
-   Wrap custom_title with IFNULL to keep .like as Expression<Bool> and avoid optional-type errors.  
  _DeckDataStore.swift_

-   Fix rename focus jumps, Esc failures, and lingering edit fields on close; Enter now updates the title immediately in UI.  
  _DeckViewModel.swift_, _ClipItemCardView.swift_, _HistoryListView.swift_, _MainWindowController.swift_

-   Normalize and locally resolve file:// paths to handle spaces, and remove the unsafe propertyList fallback.  
  _Extensions.swift_, _ClipboardItem.swift_, _ClipboardService.swift_, _PreviewWindowController.swift_

-   Fix fileURL size calculation, skip thumbnails for missing files, and harden large-image reads and de-dup.  
  _ClipboardItem.swift_, _PreviewOverlayView.swift_, _ClipItemCardView.swift_

-   Fix rule prefixes with trailing spaces, UTF-16/emoji index crashes, and incomplete delete ranges.  
  _SearchRuleFilters.swift_, _TopBarView.swift_, _TokenSearchTextView.swift_

-   Fix result mixing from stale pagination and auto-expand fetches when results are insufficient.  
  _DeckDataStore.swift_

-   Resolve Swift 6 concurrency/isolation compile errors, including main-thread access, nonisolated calls, and required awaits.  
  _PreviewWindowController.swift_, _SteganographyService.swift_, _BlobStorage.swift_, _DataExportService.swift_, _DeckDataStore.swift_, _SearchService.swift_, _DeckSQLManager.swift_

-   Prevent TOTP underflow, stop persisting PSK in UserDefaults, and tighten blob cleanup and directory creation.  
  _MultipeerService.swift_, _DirectConnectService.swift_, _DeckDataStore.swift_, _BlobStorage.swift_, _DirectConnectService.swift_

-   Invalidate cache per updated item (title/OCR) and clear properly on memory pressure to avoid stale results.  
  _SearchService.swift_, _DeckDataStore.swift_

-   Revert drag export to synchronous temp file creation for reliability, with unified temp storage and auto cleanup.  
  _TemporaryFileManager.swift_, _ClipItemCardView.swift_

-   Improve tolerant HTML decoding and caching for Figma payloads, avoiding permanent false caches and adding clearer logs.  
  _UnsupportedPasteboardPayload.swift_, _ClipboardItem.swift_

-   Fix missing Combine import in SettingsView.swift and refine QR button hit area/spacing.  
  _SettingsView.swift_, _PreviewWindowController.swift_

-   Add a 60s backoff after storage path init failures to avoid retry storms.  
  _DeckSQLManager.swift_

### Notes
-   Rule hints/help text are localized across DE/EN/FR/JA/KO/zh-Hant/zh-Hans with consistent guidance on spacing and chaining.  
  _Localizable.xcstrings_

### Compatibility & Behavior Notes
-   Example: `app:\"Google Chrome\"+Safari -type:code+text -date:26-01-01+26-01-02` (+ multi-values, - exclusion).  
  _SearchRuleFilters.swift_

-   The Figma preview currently shows basic info only, without rendering graphics/elements.  
  _FigmaClipboardPreviewView.swift_

### Upgrade Notes
-   Upgrade migrates SQLite and rebuilds FTS for custom-title search; allow time for initial indexing.  
  _DeckSQLManager.swift_

---

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.2.3/Deck.dmg)

<!-- release-changelog-bot:tag:v1.2.2 -->
## v1.2.2 — v1.2.2 | Orchestrated

- **Tag:** `v1.2.2`
- **Published:** 2026-01-23T11:45:04Z

### Release notes

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://github.com/user-attachments/assets/1b523c6b-7785-4698-8931-db205e43d7be">
    <img width="256" height="256" alt="Deck" src="https://github.com/user-attachments/assets/883ebfa4-29a1-4dd7-a282-c2e9e5f66cac" />
  </picture>
</p>

<h1 align="center">Deck</h1>

<p align="center">A modern, native, privacy-first clipboard OS for macOS</p>

---

## Release Notes v1.2.2

### Added
-   Deck adds French, Korean, and Japanese localization support.

-   Added a feedback email composer and wired it into About settings and the clipboard panel top bar, using a bundled HTML template with live system/app diagnostics and localized labels.  
  _FeedbackEmailService.swift · SettingsView.swift · TopBarView.swift · feedback.html · Localizable.xcstrings_

-   Feedback email now selects a localized HTML template based on `Locale.preferredLanguages` and generates a random UUID ticket ID each time.  
  _FeedbackEmailService.swift · feedback_en.html · feedback_de.html · feedback_kr.html · feedback_fr.html · feedback_ja.html · feedback_zh_hant.html_

-   Added Tab/Shift+Tab cycling with wrap-around for the settings sidebar, scoped to the settings window and only when no Command/Control/Option modifiers are held.  
  _SettingsView.swift_

-   Added global Cmd+Option+V “typing paste”: reads string/rtf/rtfd/html from the system pasteboard and types characters via CGEvent with a slight delay for remote-session stability (e.g., VNC); does not intercept the shortcut without Accessibility permission.  
  _PasteQueueService.swift_

-   Fixed a compile error by adding the `stringLength:` label to `keyboardSetUnicodeString` calls.  
  _PasteQueueService.swift_

-   Added the Orbit settings tab UI (intro/guide/installed stages), option-key handling, Orbit window show/hide, and install progress flow; integrated standalone Orbit app code under `Deck/Deck/Orbit` and used its window controller for the separate ring window.  
  _OrbitSettingsView.swift · OrbitWindow.swift · Deck/Deck/Orbit/_

-   Implemented installer + resource loader for bundled icon/zip and install detection; added Orbit assets/resources and improved texture loading fallbacks.  
  _OrbitInstaller.swift · OrbitResources.swift · OrbitIcon.png · OrbitApp.zip · black_hole_texture.png · BlackHoleView.swift_

-   Implemented a multi-file preview flow in the space preview panel so a clipboard item with multiple files can be browsed in order, with per-file preview selection and a smooth fade between files.  
  _PreviewWindowController.swift_

### Deck × Orbit
-   Ported the Magic Keyboard snippet component, adjusted Option key visuals, and resolved clipboard model name conflicts across ring-related models/services/views.  
  _OrbitMagicKeyboardView.swift · OrbitClipboardModels.swift · ClipboardRingViewModel.swift · ClipboardShareService.swift · ClipboardCardView.swift_

-   Orbit CLI Bridge service avoids running the whole request pipeline on `@MainActor`; only switches to main for required UI operations (e.g. paste), keeps JSON encoding/responses off-main, and adds rate limiting plus a 20MB response cap to protect UI smoothness under load.  
  _OrbitCLIBridgeService.swift_

### Improvements
-   Added a hover-only copy icon in CLI Bridge code blocks (top-right overlay) and copy via `NSPasteboard` so it only shows when the cursor is inside the code block.  
  _CLIBridgeSettingsView.swift_

-   Added the same hover-copy button used in CLI Bridge to the “Create Script Plugin” code blocks (hover-only, line animation to checkmark); introduced `CodeBlockView`, replaced two code snippets with copyable blocks, and imported AppKit for pasteboard access.  
  _ScriptPluginsSettingsView.swift_

-   Updated the Local Network IP copy button to use the CLI Bridge–style animated doc→check icon with the same timing while keeping the accent color, by replacing the inline button with a reusable `CopyIconButton`.  
  _LANSharingSettingsView.swift_

-   Updated the “Add Device” button to read as a real CTA (full-width accented fill, semibold label, and disabled styling) so it no longer resembles an input field.  
  _LANSharingSettingsView.swift_

-   Removed the loading text/spinner from the “Connected Devices” section and replaced the empty state with a localized “No connected Deck devices” message.  
  _LANSharingSettingsView.swift_

-   Moved data reload to run after the panel slide animation finishes, and changed close behavior to keep a small warm cache instead of fully purging, so animation doesn’t compete with heavy DB + SwiftUI rebuilds (UI files left untouched).  
  _MainWindowController.swift · DeckDataStore.swift_

-   Reduce Motion now forces duration 0; hide uses `easeIn` while show stays `easeOut`, and the slide animation is removed on completion to avoid residual state.  
  _MainViewController.swift_

-   Added popup panel corner radius and reduced top spacing for a more cohesive visual appearance.

-   Optimized popup animation by moving heavy work out of the present animation, simplifying Spaces behavior, using gentler `easeInEaseOut` easing, and removing extra behind-window blur on older macOS to avoid double-blur work.  
  _MainWindowController.swift · MainViewController.swift · DeckContentView.swift_

-   Submits UI updates as soon as data is ready (during animation) and prevents `setPanelActive` from overwriting freshly committed results via cache.  
  _DeckDataStore.swift · MainWindowController.swift_

-   Improved initial selection stability by adding `resetInitialSelection(force:)`, forcing selection reset after app switches when context-aware mode is on, and guarding on `selectedId == nil` to prevent repeated selection during commits/reorders.  
  _HistoryListView.swift_

-   Applied UX-neutral performance optimizations: large image blob writes now store asynchronously to avoid sync IO on UI-driven flows; search lowercasing is capped and avoids extra allocations; pasteboard string fetched once and bank-card detection is single-pass with early exit.  
  _DeckSQLManager.swift · SearchService.swift · ClipboardService.swift_

-   Applied minimal, interaction-neutral optimizations across hot paths: SearchService adds a bounded cross-keystroke cache for `prepareLowercasedText`, safe range conversion, security-mode/session-resign cache invalidation, and exposes `clearPreparedTextCache()` for memory pressure; SmartContentCache adds inflight dedupe, moves CPU work to a detached task, avoids cache overwrites on races, and cancels inflight tasks on invalidation/clear/memory pressure; Cursor Assistant lifts the numeric key map to static; memory pressure now clears SearchService cache.  
  _SearchService.swift · SmartContentCache.swift · CursorAssistantService.swift · DeckDataStore.swift_

-   Coalesced overlapping clipboard checks, consumed `changeCount` on nil items, warmed recent cache for CLI, and avoided full blob reads for OCR.  
  _ClipboardService.swift · DeckDataStore.swift · OCRService.swift_

-   Mitigated the settings window Auto Layout loop by hosting SwiftUI in a plain container view.  
  _SettingsWindowController.swift_

### Changes
-   Feedback email no longer uses `mailto` (browser-triggering); it now prefers composing via `NSSharingService` and falls back to plain-text content if template loading fails to avoid a blank email; only tries opening the Mail app itself when the service is unavailable.  
  _FeedbackEmailService.swift_

-   Reorganized settings so privacy items live only under Privacy and general behavior toggles live under General, and reordered the sidebar tabs to a more logical grouping/order (context-aware before smart rules, Cursor Assistant under it, Statistics near the bottom with Orbit below, About last).  
  _SettingsView.swift · PrivacySettingsView.swift_

-   Moved the settings sidebar order so Smart Rules now sits directly under Context Aware, and Cursor Assistant is adjacent to Template Library; order is driven by `SettingsTab` declaration order and `SettingsTab.allCases`.  
  _SettingsView.swift_

-   Added the ⌘⌥V row and a hint about simulated keyboard-typing paste in the Standard Shortcuts card, with full localization coverage (DE/EN/FR and existing locales).  
  _SettingsView.swift · Localizable.xcstrings_

-   Removed Focus polling/monitor timers and restore logic, and cleaned up Focus status helpers and Intents dependencies.  
  _AppDelegate.swift · DeckIntents.swift_

-   Default scripts now clean old defaults before writing new ones (keeping Word Count) and only delete/overwrite Deck-authored defaults to avoid touching user scripts; startup clears old default directories (base64-encode/base64-decode/url-encode/url-decode/json-format). The new defaults include Word Count, Remove Emoji, Remove Markdown, Remove Empty Lines, Extract URL, Extract Emails, and Line Number Prefix. Added a JSContext bridge `Deck.detectEmails` that calls `SmartTextService.shared` detection; emoji removal uses Unicode emoji matching (including variation selectors/ZWJ), and Markdown removal strips common syntax + HTML tags while keeping plain text.  
  _ScriptPluginService.swift_

-   All visible strings on the Deck × Orbit page are now localized via `NSLocalizedString`, and the missing “Welcome” entry has been added to the string catalog.  
  _OrbitSettingsView.swift · Localizable.xcstrings_

-   Moved “Accessibility permission” from Privacy to General (including permission refresh timing logic), moved “Steganography key” from Privacy to Security with clearer “for text steganography” wording (before Security info), and moved “History retention” from General to Storage (after Storage info), keeping the original UI style and behavior.  
  _SettingsView.swift_

-   Updated the Privacy page subtitle (“隐私保护设置”) and completed/synced translations for EN/DE/FR/JA/KR/zh-Hant for new/changed strings.  
  _Localizable.xcstrings_

-   Cleared 7 “no references” string-catalog warnings without deleting translations by setting stale entries’ `extractionState` to `manual`.  
  _Localizable.xcstrings_

-   Removed three stale string entries to stop Xcode “References to this key could not be found in source code” warnings: the plugin manifest JSON template string, the `transform(input) { return input.toUpperCase(); }` snippet, and “正在搜索附近的 Deck 设备...”.  
  _Localizable.xcstrings_

-   Switched Mail launching to the modern NSWorkspace API (`openApplication(at:configuration:completionHandler:)`) via Mail’s bundle ID.  
  _FeedbackEmailService.swift_

-   Updated the Cursor Assistant “Trigger key” row to show a static Shift keycap badge instead of a segmented selection, matching the fact there’s no choice right now.  
  _SettingsView.swift_

-   Tab cycling now follows the full order of system + user tags, continuing to user tags after “Important” when present (otherwise wraps back to system tags); `cycleSystemTags` now iterates the overall `vm.tags` order to support forward/backward cycling.  
  _HistoryListView.swift_

### Fixes
-   Updated clipboard classification to reduce URL/phone/email false positives, tighten URL normalization, and make analysis caching thread-safe; added URL edge-case tests.  
  _Extensions.swift · SmartTextService.swift · ClipboardItem.swift · SmartContentCache.swift · ExtensionsTests.swift · SmartTextServiceTests.swift_

-   Fixed compile errors while keeping all fixes inside `SmartTextService.swift`: removed `resourceSpecifier` usage, fixed `Substring` trimming, and replaced `asCompleteURL()` calls with a local URL normalizer to avoid main-actor isolation in nonisolated contexts.  
  _SmartTextService.swift_

-   Fixed test failures by tightening URL/@mention dedup (URL dedup now normalizes percent-encoding and mention regex avoids emails), improving Swift detection for short snippets, making the kana test explicitly assert false (avoids unused locals), and collapsing CN phone dedup for `+86` variants.  
  _SmartTextService.swift · ExtensionsTests.swift_

-   Adjusted the bare-domain URL regex to avoid matching inside `http/https/ftp` URLs, which was causing duplicates.  
  _SmartTextService.swift_

-   Changed URL detection to skip regex passes if `NSDataDetector` already found URLs, which should stop duplicate counts.  
  _SmartTextService.swift_

-   XML is now treated as data-like (no longer requires `structureScore ≥ 2`), and email regex results are percent-decoded before dedup to prevent double-counting in `mailto` cases.  
  _SmartTextService.swift_

-   Added an “unsupported clipboard” fallback so items aren’t dropped: builds a fallback `ClipboardItem` on parse failure (custom pasteboard type + localized placeholder text), and history cards render a centered “Deck 无法解析本剪贴板内容” message.  
  _ClipboardService.swift · ClipboardItem.swift · ClipItemCardView.swift · Localizable.xcstrings_

-   Fixed DirectConnect random generation and receive cleanup; hardened import sizing, background inserts, and streaming object limits.  
  _DirectConnectService.swift · DataExportService.swift_

-   Guarded sqlite handles/statements and bound table-name lookups safely to prevent invalid access.  
  _PasteNowMigrationAdapter.swift · PasteBarMigrationAdapter.swift · MaccyMigrationAdapter.swift_

-   Added a local `SQLITE_TRANSIENT` shim in migration adapters that use `sqlite3_bind_text`, matching the pattern in `PasteMigrationAdapter` to fix the “Cannot find SQLITE_TRANSIENT” compile error without changing behavior.  
  _PasteNowMigrationAdapter.swift · PasteBarMigrationAdapter.swift_

-   Normalized CloudSync numeric decoding, preserved group payload timestamps/app names, and moved plugin list publishing to main.  
  _CloudSyncService.swift · MultipeerService.swift · ScriptPluginService.swift_

-   Extended `DecodedItemPayload` to include timestamp and appName, wiring them through decode and delivery; `MultipeerService` now sets these for group items, defaults them for single items, and uses the fields when building `ClipboardItem`.  
  _MultipeerService.swift_

-   Safer biometric type detection and an Application Support path fallback.  
  _SecurityService.swift · DeckSQLManager.swift_

-   Hardened persistence/migration paths without UX changes: backfilled ManualPeer psk; guarded `ifa_addr` in Multipeer; ensured `isPaused` expiry restore runs on main; improved `openDatabase` error/close flow when `db == nil`; export writes now throw; encrypted migration uses id cursor paging; embedding migration batches in transactions; large ID queries are chunked to avoid SQLite variable limits.  
  _DirectConnectService.swift · MultipeerService.swift · ClipboardService.swift · PasteMigrationAdapter.swift · DataExportService.swift · DeckSQLManager.swift_

-   Made the `notifyEncryptionFailureIfNeeded()` call use an explicit `self` capture to fix the related compile/concurrency warning.  
  _DeckSQLManager.swift_

-   Expanded IDE anchor discovery so Cursor/VS Code no longer hard-fails on missing `AXDocument`; AX traversal is deeper and more robust to Electron-style trees; added multi-attribute extraction with proxy/title/value fallbacks plus lenient URL/path normalization, and centralized file-path validation to avoid false positives.  
  _IDEAnchorService.swift_

-   Swapped an unavailable AX constant for a string-based attribute so the build no longer depends on that SDK symbol, while keeping the navigation-order traversal attempt.  
  _IDEAnchorService.swift_

-   Fixed storage calculations in Statistics by measuring the real file sizes of `Deck.sqlite3` and its `-wal/-shm` siblings, and updating average record size accordingly.  
  _StatisticsView.swift_

-   Updated the history preview code copy button to use the same checkmark animation as CLI Bridge; copying code no longer shows the green “Copied” toast, while other copy actions keep their existing feedback.  
  _SmartContentView.swift_

-   Reset preview state on panel activation/deactivation/disappear (state + task cancel + window hide) so previews no longer resurface after reopening.  
  _HistoryListView.swift_

-   Cleaned up Swift 6 warnings/errors in preview/controller code and Orbit jump model by making `FilePreviewRules` constants/functions `nonisolated` under MainActor default isolation, fixing fallback icon API usage, and explicitly capturing `saveDebounce` to avoid actor hops.  
  _PreviewWindowController.swift · OrbitJumpModel.swift_

-   Fixed NSWorkspace icon API parameter labels by switching the fallback icon call to `NSWorkspace.shared.icon(for: .data)`, eliminating the `forContentType:` compile error.  
  _PreviewWindowController.swift_

-   Traced the Obj‑C decode warning to the RTF/RTFD path and added a plain-text short-circuit when a clean string already exists, avoiding `NSAttributedString` decoding warnings while preserving the original rich-text payload for pasting and fallback.  
  _ClipboardItem.swift_

-   Kept normal UX unchanged, but now rejects oversized/invalid inputs early (with logs) to prevent crashes and races by adding caps/locks/safe reads across Cloud Sync, script plugins, steganography, semantic search, and clipboard paths.  
  _CloudSyncService.swift · ScriptPluginService.swift · ClipboardItem.swift · SteganographyService.swift · SemanticSearchService.swift_

-   Fixed Swift 6 isolation compile errors by marking `loadCarrierImageData(from:)` `nonisolated` to match call sites and making `maxCarrierFileBytes` `nonisolated` to allow static access from nonisolated contexts.  
  _SteganographyService.swift_

-   Fixed a same-name shadowing bug (`if let previewData`) that made the value immutable inside the block; switching to a local `previewBytes` restores correct `previewData = nil` behavior.  
  _CloudSyncService.swift_

-   Applied UX-neutral stability fixes: explicit `bm25` alias for FTS, safe backfill for legacy empty `unique_id`, blob items honor `loadFullData`, chunked batch fetch under SQLite limits, cursor-based paging used by Cloud Sync, safer AX handling and multi-monitor caret positioning, hotkey update rollback on failure, cancellable auto-exit for paste queue, nil-safe TOTP generation, export via cursor paging with import IO off-main, JSON fragments support, tighter URL encoding, and typeID-checked unwrap helpers to eliminate CFTypeRef cast warnings.  
  _DeckSQLManager.swift · CloudSyncService.swift · CursorAssistantService.swift · ClipboardService.swift · HotKeyManager.swift · PasteQueueService.swift · MultipeerService.swift · DataExportService.swift · TextTransformer.swift · SourceAnchor.swift_

-   Resolved Swift 6 compile errors by tightening type inference and silencing unused results, making export DTOs `nonisolated` + `Sendable`, adding a `@MainActor` insert helper and awaiting main-actor logging, adding `Sendable` conformances for source-anchor value types used across tasks, and explicitly typing `rows: [Row]` to fix the remaining `append(contentsOf:)` error.  
  _DeckSQLManager.swift · DataExportService.swift · SourceAnchor.swift_

-   Fixed long-URL UI issues by fixing popup card width to 320, truncating displayed URLs (strip `http(s)://`, show up to 20 chars + ellipsis with full link on hover), showing a clear “link too long” message when QR generation fails (instead of spinning), and hiding “Show QR code” in the context menu when URL length exceeds 600 bytes.  
  _PreviewWindowController.swift · ClipItemCardView.swift_

-   Filled the 25 empty/missing translation entries in `Localizable.xcstrings`, restoring 100% translation coverage.  
  _Localizable.xcstrings_

-   Updated single-file drag-export `suggestedName` to strip the last extension so Finder doesn’t append another one based on UTType (avoids `.py.py` / `.json.json`).  
  _ClipboardItem.swift_

### Notes
-   Added translations for “提交反馈”, “告诉我们您的想法”, and the “Deck 反馈” email subject; updated subject/question/hint lines in existing templates and added missing language template files.  
  _Localizable.xcstrings · feedback_en.html · feedback_de.html · feedback_kr.html · feedback_fr.html · feedback_ja.html · feedback_zh_hant.html_

### Compatibility & Behavior Notes
-   Feedback email prefers composing via `NSSharingService` and only attempts to open the Mail app directly when the service is unavailable.  
  _FeedbackEmailService.swift_

### Upgrade Notes
-   Recommended for all users: v1.2.2 includes improvements to feedback email flow, localization coverage, preview/settings interaction, and broad stability/performance/safety hardening.

---

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.2.2/Deck.dmg)

<!-- release-changelog-bot:tag:v1.2.1 -->
## v1.2.1 — v1.2.1 | Lean

- **Tag:** `v1.2.1`
- **Published:** 2026-01-18T04:00:20Z

### Release notes

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://github.com/user-attachments/assets/1b523c6b-7785-4698-8931-db205e43d7be">
    <img width="256" height="256" alt="Deck" src="https://github.com/user-attachments/assets/883ebfa4-29a1-4dd7-a282-c2e9e5f66cac" />
  </picture>
</p>

<h1 align="center">Deck</h1>

<p align="center">A modern, native, privacy-first clipboard OS for macOS</p>

---

## Release Notes v1.2.1

### Added
-   Added a `databaseAutoBackupEnabled` preference with Settings UI; supports manual backup/delete, and when disabled it stops backup/restore and cleans up `.bak`.  
  _UserDefaultsManager.swift, SettingsView.swift, DeckSQLManager.swift_

### Improvements
-   Keeps paged history items lightweight: only decrypts full payload when needed, using size thresholds and previews to defer heavy loads.  
  _DeckSQLManager.swift_
-   Keeps `orderedItems` empty when reordering is off/search/queue to avoid shared buffers and Copy-on-Write spikes.  
  _HistoryListView.swift_
-   Builds reorder results in a single array to avoid extra copies; materializes full payload before saving templates to ensure full data is persisted.  
  _ContextAwareService.swift, TemplateLibraryService.swift_
-   Splits DB work into interactive vs background queues and moves in-memory fuzzy ranking off the main actor to reduce UI stalls.  
  _DeckDataStore.swift, DeckSQLManager.swift_
-   Search now prefers exact hits in mixed mode and only falls back to fuzzy when needed; adds LIKE-based candidate expansion, a `scanLimit` cap, true cancellation for in-memory search, and cooperative cancellation checks in loops.  
  _DeckDataStore.swift, SearchService.swift_
-   Energy optimizations for CloudSync, steganography, and OCR: larger/low-power-aware batching, conditional stego decode, and OCR back-pressure/debounce with Low Power Mode skip and size caps for huge images.  
  _CloudSyncService.swift, ClipboardService.swift, OCRService.swift_
-   Adds O(1) LRU, `NSCache` regex caching, and a small regex cache for sensitive-content matching to reduce churn and repeated compilation.  
  _SmartContentCache.swift, SmartTextService.swift, ClipboardService.swift_
-   Reduces IO/CPU hotspots: batched sample saves, serialized blob IO, thermal/low-power OCR downsampling, BFS queue fix, and on-appear pagination.  
  _DiagnosticsMemorySampler.swift, BlobStorage.swift, OCRService.swift, IDEAnchorService.swift, HistoryListView.swift_
-   On macOS 26, uses `NSGlassEffectView` (`.regular`) as the main container with `cornerRadius = Const.panelCornerRadius`; SwiftUI background is `Color.clear`, top padding uses `Const.panelTopPadding`, and the search field radius uses `Const.searchFieldRadius`.  
  _MainViewController.swift, DeckContentView.swift, TopBarView.swift, Constants.swift_
-   Raises the serial DB queue QoS back to `.userInitiated` while enforcing `.utility` for background maintenance, preventing interactive queries from being deprioritized.  
  _DeckSQLManager.swift_

### Changes
-   Adjusts the macOS 26 view hierarchy and clipping: embeds the `HostingView` into `glass.contentView`, applies rounded clipping with `cornerCurve = .continuous` on 26+, and enables window shadow on macOS 26 (kept disabled on <26).  
  _MainViewController.swift, MainWindowController.swift_
-   Updates constants: adds `panelCornerRadius = 26`, `panelTopPadding = Const.space12 + 5`, `searchFieldRadius = 12`; adjusts window height to `305`; and lightens `panelOverlay` colors on macOS 26 (though it’s no longer used by `DeckContentView` on 26).  
  _Constants.swift, DeckContentView.swift_
-   Reverts hotkey listening and paste-queue behavior back to the previous `CGEventTap`-based implementation so `Cmd+P` and queue mode work again.  
  _HotKeyManager.swift, PasteQueueService.swift_
-   Cleans update artifacts on launch and removes `.Deck.app.old.*` backups in `/Applications` (no Trash), and uses the cleanup result to decide whether to show the 8-second Settings window prompt.  
  _AppDelegate.swift, UpdateService.swift_
-   Removes the manual analytics upload action so analytics only has the toggle; restyles stego passphrase input with clearer save/clear states and Enter-to-save flow.  
  _PrivacySettingsView.swift_
-   Renders the stego key mask with the exact length and right alignment; persists the length on save/clear so the UI stays consistent.  
  _UserDefaultsManager.swift, SteganographyKeyStore.swift, PrivacySettingsView.swift_

### Fixes
-   Fixes build issues by making `dbQueue`/`dbBackgroundQueue` `lazy` to avoid touching `self` during property initialization and removing an unused variable.  
  _DeckSQLManager.swift_
-   Fixes the `keyboardGetUnicodeString` call by adding the `maxStringLength:` label.  
  _CursorAssistantService.swift_
-   Avoids state mutations during SwiftUI updates; ignores programmatic text updates and defers focus/blur asynchronously to reduce update warnings and priority inversions.  
  _TopBarView.swift_
-   Marks `sharedKeyMaskLength` as `@MainActor` so it reads `DeckUserDefaults.stegoPassphraseLength` on the main actor.  
  _SteganographyKeyStore.swift_

### Notes
-   Keeps `BlobStorage.swift` base directory dynamic so runtime storage-location switches remain safe; if you want the patch’s lazy cache, add an invalidation hook.  
  _BlobStorage.swift_
-   Carbon hotkeys reserve `Cmd+Shift+V` globally; if Carbon returns and you need pass-through when queue mode is off, conditional registration or synthetic pass-through can be added.  
  _PasteQueueService.swift_
-   The post-update window still only shows when the built-in updater sets `deck.pendingUpdateVersion`; manual DMG updates won’t trigger it.  
  _AppDelegate.swift, UpdateService.swift_

### Compatibility & Behavior Notes
-   On macOS 26, `DeckContentView` no longer draws glass/overlay in SwiftUI (`Color.clear` background); glass and rounded clipping are handled by the `NSGlassEffectView` container, while <26 still uses `VisualEffectBackground + panelOverlay`.  
  _DeckContentView.swift, MainViewController.swift_

### Upgrade Notes
-   Recommended for all users: this release focuses on scroll/pagination/search/DB performance and energy improvements, includes macOS 26 container updates, and ships multiple stability fixes.  

---

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.2.1/Deck.dmg)

<!-- release-changelog-bot:tag:v1.2.0 -->
## v1.2.0 — v1.2.0 | Stabilized

- **Tag:** `v1.2.0`
- **Published:** 2026-01-16T06:33:02Z

### Release notes

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://github.com/user-attachments/assets/1b523c6b-7785-4698-8931-db205e43d7be">
    <img width="256" height="256" alt="Deck" src="https://github.com/user-attachments/assets/883ebfa4-29a1-4dd7-a282-c2e9e5f66cac" />
  </picture>
</p>

<h1 align="center">Deck</h1>

<p align="center">A modern, native, privacy-first clipboard OS for macOS</p>

---

## Release Notes v1.2.0

### Added
-   Auto-update now uses a CF proxy for reliable access in mainland China, with GitHub downloads kept as a fallback.  

-   Added diagnostics upload and memory sampling: uploads a 24-hour report daily at 15:00 local time with a log-less fallback, and records minute-level memory samples up to 1440 points in `memory_samples.json`.  
  _DiagnosticsUploadService.swift, DiagnosticsMemorySampler.swift_

-   Privacy settings add an “Analytics Data” card with a toggle and a manual upload action when enabled.  
  _PrivacySettingsView.swift_

-   Added Traditional Chinese (zh-Hant) localization support.  
  _Localizable.xcstrings_

### Deck × Orbit
-   Orbit bridge tokens are now per-install random values with a DEBUG legacy fallback; Release no longer accepts a hardcoded token.  
  _OrbitBridgeAuth.swift_

-   Tokens are eagerly created at launch, and 401 responses trigger a disk reload and one retry.  
  _AppDelegate.swift, OrbitBridgeAuth.swift, OrbitBridgeClient.swift_

### Improvements
-   Preview now always shows the phone line + full text while keeping smart details; added multi-image thumbnail grids for file URLs, fixed history card thumbnails, and made previews refresh on mouse clicks.  
  _PreviewWindowController.swift, PreviewOverlayView.swift, HistoryListView.swift_

-   Multi-image cards now show only the first image with a separate right-side ellipsis indicator of fixed height/min width, without overlaying the image or pushing titles.  
  _ClipItemCardView.swift_

-   Install/update UI now forces original-color app icons to avoid dark-mode template tinting.  
  _SettingsView.swift_

-   Statistics now use metadata-only queries with a shrink-memory hook on exit, and Top Apps use `appPath` as a stable id.  
  _StatisticsView.swift, DeckSQLManager.swift_

-   PRAGMA `quick_check(1)` is throttled to a 24h window and forced only on restore; vec backfill runs only when embeddings exist and vec tables are empty, favoring recent rows with short sleeps; `updateVecIndex` avoids heavy serialization and uses `INSERT OR REPLACE`.  
  _DeckSQLManager.swift_

-   Stego decoding now runs off-main with cancellation support; export auth stays on main while fetch/encode/write run in a detached worker.  
  _ClipboardService.swift, SteganographyService.swift, DataExportService.swift_

-   Auto-delete is now coordinated by an `AutoDeleteScheduler` actor instead of per-item sleeps.  
  _SmartRuleService.swift_

-   Added matrixized scoring with norm caching while preserving threshold/sort semantics, and replaced deprecated `cblas_sgemv` with `vDSP_mmul`.  
  _SemanticSearchService.swift_

### Changes
-   On launch, clears all version-prefixed update caches (including `unknown-`) and records `pendingUpdateVersion`; when applicable, opens Settings after 8 seconds to show “Update complete,” with a new `showWindow()` to avoid toggle mis-close.  
  _UpdateService.swift, AppDelegate.swift, SettingsWindowController.swift_

-   Release updates now enforce code signature validation.  
  _UpdateService.swift_

-   Script execution was serialized to reduce contention, and is now concurrent to avoid head-of-line blocking.  
  _ScriptPluginService.swift_

-   `TransformType` persistence now uses a stable code with backward compatibility for legacy Chinese raw values.  
  _TextTransformer.swift_

-   DB now tracks `is_encrypted` with idempotent per-field encrypt/decrypt and row-level decisions; detection uses silent decrypt to avoid log spam.  
  _DeckSQLManager.swift, SecurityService.swift_

-   Exports now write directly to the user-chosen path and clean leftover temp exports on launch.  
  _DataExportService.swift_

-   Plaintext receives are rejected when no confirmation callback is wired.  
  _DirectConnectService.swift_

### Fixes
-   All CGEventTap callbacks now return `passUnretained(event)` and use `CFRunLoopGetMain()` for consistent attach/detach, preventing leaks and runloop mismatches.  
  _PasteQueueService.swift, CursorAssistantService.swift_

-   `unregisterAllHotKeys()` now iterates `Array(hotKeys.keys)` to avoid mutation-during-enumeration crashes.  
  _HotKeyManager.swift_

-   Modifier event tap callbacks now return `passUnretained(event)` to prevent leaks.  
  _HotKeyManager.swift_

-   Poll timer scheduling/canceling now runs on its own queue to avoid races and odd behavior.  
  _ClipboardService.swift_

-   Remote changes now apply with `shouldSyncToCloud=false` to prevent echo uploads; `moreComing` fetches loop until complete with proper token advancement.  
  _CloudSyncService.swift, DeckDataStore.swift_

-   Encrypted records are always decrypted regardless of local encryption toggle.  
  _CloudSyncService.swift_

-   Remote updates now write directly to the DB instead of delete+insert, preventing duplication and write amplification.  
  _CloudSyncService.swift, DeckSQLManager.swift_

-   `pendingUploadCount` now updates on the main thread to avoid races from background mutations.  
  _CloudSyncService.swift_

-   Removed `ManagedCriticalState` and added explicit tuple types to fix compile errors.  
  _CloudSyncService.swift_

-   `unique_id` now uses a UNIQUE index with dedupe-and-retry and a safe fallback to a normal index.  
  _DeckSQLManager.swift_

-   `fetchRow(uniqueId:)` now orders results to pick the most recent row deterministically.  
  _DeckSQLManager.swift_

-   Updates now persist `blob_path`, offload large data to blob storage when needed, and remove old blob files after successful updates.  
  _DeckSQLManager.swift, BlobStorage.swift_

-   `BlobStorage` no longer depends on `@MainActor`, and symlink resolution is hardened to prevent path traversal.  
  _BlobStorage.swift_

-   Avoids decoding file path strings as image data by generating thumbnails directly from file URLs.  
  _ClipItemCardView.swift_

-   JSCore execution now has a time limit; unavailable symbols are resolved via `dlsym` and applied only when present.  
  _ScriptPluginService.swift_

-   Large exports now stream-parse `items` to avoid OOM from full JSON decoding.  
  _DataExportService.swift_

-   Logging now uses `nonisolated(unsafe)` for background calls while removing unnecessary global logger isolation; stego decoding routes through nonisolated static helpers with pre-fetched keys; `SteganographyKeyStore` access is nonisolated.  
  _AppLogger.swift, SteganographyService.swift, SteganographyKeyStore.swift, ClipboardService.swift_

-   Stego services are captured on main before detaching and auto-delete logging is moved to main to satisfy Swift 6 isolation.  
  _ClipboardService.swift, SmartRuleService.swift_

-   Raw SQL loops now use Statement row indexing, and `shrinkMemory()` is async with updated call sites.  
  _DeckSQLManager.swift, StatisticsView.swift, DeckDataStore.swift_

-   Set 16 unused localization keys to `manual` to keep translations and remove warnings.  
  _Localizable.xcstrings_

### Notes
-   Diagnostic uploads exclude clipboard content and include only app version, system info, user ID, 24-hour memory curve, and crash logs.  

---

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.2.0/Deck.dmg)

<!-- release-changelog-bot:tag:v1.1.9 -->
## v1.1.9 — v1.1.9 | Rock-Solid

- **Tag:** `v1.1.9`
- **Published:** 2026-01-15T01:40:49Z

### Release notes

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://github.com/user-attachments/assets/1b523c6b-7785-4698-8931-db205e43d7be">
    <img width="256" height="256" alt="Deck" src="https://github.com/user-attachments/assets/883ebfa4-29a1-4dd7-a282-c2e9e5f66cac" />
  </picture>
</p>

<h1 align="center">Deck</h1>

<p align="center">A modern, native, privacy-first clipboard OS for macOS</p>

---

## Release Notes v1.1.9

### Improvements

-   Applied encryption-mode performance optimizations across key handling, search scan paths, text analysis, link preview prefetching, blob IO, and semantic ranking to reduce CPU/IO overhead.

-   _SecurityService.swift_

-   _DeckSQLManager.swift / SemanticSearchService.swift_

-   _SmartTextService.swift_

-   _ClipboardService.swift_

-   _BlobStorage.swift_

---

### 内存 / 网络 / UI 深度优化

-   _SmartContentCache.swift / DeckDataStore.swift / ClipboardService.swift_

-   _MultipeerService.swift / DirectConnectService.swift_

-   _HistoryListView.swift / ClipItemCardView.swift / SmartContentView.swift / LargeTextPreviewView.swift_

---

### Behavior Changes

-   _MultipeerService.swift_

-   _ClipboardService.swift_

---

### Swift 6 Fixes

-   _MultipeerService.swift_

-   _AppLogger.swift / MultipeerService.swift_

-   _SmartTextService.swift_

---

### Updater

-   _UpdateCoordinator.swift_

-   _UpdatePromptView.swift_

-   _UpdateService.swift / AppDelegate.swift_

---

### Fixes


-   _MainWindowController.swift / SettingsWindowController.swift_


-   _LargeTextPreviewView.swift_

---

### Compatibility & Notes

-   _Deck.entitlements_

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.1.9/Deck.dmg)

<!-- release-changelog-bot:tag:v1.1.8 -->
## v1.1.8 — v1.1.8 | Grounded

- **Tag:** `v1.1.8`
- **Published:** 2026-01-13T05:28:11Z

### Release notes

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://github.com/user-attachments/assets/1b523c6b-7785-4698-8931-db205e43d7be">
    <img width="256" height="256" alt="Deck" src="https://github.com/user-attachments/assets/883ebfa4-29a1-4dd7-a282-c2e9e5f66cac" />
  </picture>
</p>

<h1 align="center">Deck</h1>

<p align="center">A modern, native, privacy-first clipboard OS for macOS</p>

---

## Release Notes v1.1.8

### Added

-   Added Paste migration support with compatibility for both legacy `Paste.db` and sandbox `index.sqlite`, plus one-click migration for Maccy / Flycut / PasteBar.

-   Added an always-visible migration module to the Storage page, reusing the onboarding migration flow and auto-scanning on entry.  
  _SettingsView.swift_

-   Deck now includes a local Orbit CLI Bridge daemon (`127.0.0.1:53129`) exposing: `/orbit/health`, `/orbit/recent`, `/orbit/item`, `/orbit/delete`, `/orbit/copy`.

-   Added localized migration source names (Maccy / Paste / Flycut / PasteBar) in Chinese / English / German.

-   Added a debug toggle (boolean flag) to force-trigger the onboarding flow.

---

### Deck × Orbit

> Orbit GitHub：  
> https://github.com/yuzeguitarist/Orbit

-   Orbit now integrates deeply with Deck, bringing Deck’s clipboard history into a radial clipboard ring.

-   After summoning the Orbit app ring, press **Caps Lock (Input Source key)** to switch to the clipboard ring.

-   The clipboard ring shows 9 cards by default, supporting keyboard navigation, copy/delete actions, and drag-to-center share or delete.

-   Text and code are shared via AirDrop as temporary files with language-aware extensions and automatic cleanup.  
  _ClipboardShareService.swift_

---

### Improvements

-   Improved migration bulk inserts by reducing transaction count and UI refresh overhead for faster large imports.

-   Refined onboarding migration page layout/spacing; list now shows only detected apps; window height set to 450.

-   Tuned the double-Option interaction (threshold + cooldown) to allow quicker hide/show cycles.  
  _HotKeyManager.swift_

---

### Changes

-   Deck authentication now uses a fixed `X-Orbit-Token` header, removing the Keychain/XPC prompt flow.

-   OrbitBridgeClient now talks to the CLI Bridge via HTTP and removes the XPC connection path.

-   The panel now appears on the screen where the cursor is located.  
  _MainWindowController.swift_

---

### Fixes

-   Fixed Flycut migration to gracefully handle cases with no history.

-   Fixed Swift 6 concurrency warnings related to database VACUUM.

-   Fixed an issue where PNGs copied from Finder could not be pasted after re-copy/drag and could produce corrupted dragged files, by reading actual image data for `fileURL` images and writing the correct image type.  
  _ClipboardItem.swift_

-   Improved compatibility by writing both file URL and image data when pasting/dragging `fileURL` images.  
  _ClipboardService.swift_

---

### Notes

-   No new copy was added; the migration module continues to reuse existing Chinese/English/German translations.  
  _SettingsView.swift_

---

### Compatibility & Behavior Notes

-   Paste migration supports both legacy `Paste.db` and sandbox `index.sqlite`.

-   The Orbit Bridge service is exposed on localhost only and authenticated via a fixed request header.

---

### Upgrade Notes

-   All users are recommended to upgrade for a smoother migration experience (faster large imports + always-available Storage entry), improved image paste/drag compatibility, and the new Orbit CLI Bridge with a simplified authentication flow.

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.1.8/Deck.dmg)

<!-- release-changelog-bot:tag:v1.1.7 -->
## v1.1.7 — v1.1.7 | Resilient

- **Tag:** `v1.1.7`
- **Published:** 2026-01-11T07:53:31Z

### Release notes

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://github.com/user-attachments/assets/1b523c6b-7785-4698-8931-db205e43d7be">
    <img width="256" height="256" alt="Deck" src="https://github.com/user-attachments/assets/883ebfa4-29a1-4dd7-a282-c2e9e5f66cac" />
  </picture>
</p>

<h1 align="center">Deck</h1>

<p align="center">A modern, native, privacy-first clipboard OS for macOS</p>

---

## Release Notes v1.1.7

### Fixes

-   Fixed an unresponsive issue by executing the “Paste After Transform” script plugin asynchronously instead of blocking the main thread.  
  _ClipItemCardView.swift_

-   Prevented crashes caused by invalid `NSExpression` formats by adding Objective-C exception catching with safe fallback.  
  _SmartTextService.swift, ObjcExceptionCatcher.h/.m, Deck-Bridging-Header.h_

-   Ensured database file space is fully released after clearing data by running WAL checkpoint and VACUUM.  
  _DeckSQLManager.swift_

-   Fixed an initialization timing issue in context-aware sorting where `lastNonDeck` could be nil due to early `preApp` injection.  
  _AppDelegate.swift, MainWindowController.swift, ContextAwareService.swift_

-   Resolved Swift 6 concurrency warnings related to expression snapshot capturing.  
  _SmartTextService.swift_

---

### Compatibility & Behavior Notes

-   This release contains stability and safety fixes only, with no breaking behavior changes.

-   No database schema changes; safe for in-place upgrade.

---

### Upgrade Notes

-   All users are strongly recommended to upgrade for improved script execution stability, safer smart text handling, and reliable database space reclamation.

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.1.7/Deck.dmg)

<!-- release-changelog-bot:tag:v1.1.6 -->
## v1.1.6 — v1.1.6 | Connected

- **Tag:** `v1.1.6`
- **Published:** 2026-01-06T10:44:18Z

### Release notes

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://github.com/user-attachments/assets/1b523c6b-7785-4698-8931-db205e43d7be">
    <img width="256" height="256" alt="Deck" src="https://github.com/user-attachments/assets/883ebfa4-29a1-4dd7-a282-c2e9e5f66cac" />
  </picture>
</p>

<h1 align="center">Deck</h1>

<p align="center">A modern, native, privacy-first clipboard OS for macOS</p>

---

## Release Notes v1.1.6

### New

-   Added a dedicated “CLI Bridge” section in the sidebar for configuration and documentation.

-   Added usage and testing docs including health check, read/write examples, and optional aliases.

-   Added IDE source anchors (file/line/col/IDE) with deep-linking and an “Open in IDE” action.

-   Persisted `source_anchor` with DB storage, export/import support, and iCloud sync.

-   Added support for Cursor, Windsurf, and Antigravity IDEs via bundle ID detection and deep links.

-   Convert links into shareable preview card images with title, summary, domain, favicon, and cover image.

---

### Improvements

-   Moved CLI Bridge settings out of General into its own section.

-   Source capture now prefers `preApp` and extends AX scanning into window subtrees.

-   Normalized helper bundle IDs to their parent apps.

-   Improved card layout with no white margins, adaptive height, full long-image rendering, and blurred fill.

-   Cmd+Shift+V now works with Cursor Assistant active; queue mode still takes precedence.

-   Added English and German localizations for CLI Bridge and IDE actions.

---

### Fixes

-   Fixed a local HTTP server issue where released handlers caused no response.

-   Fixed AX CFTypeRef/AXValue conversion warnings and build errors.

-   Fixed missing `sourceAnchor` assignment after iCloud decryption.

-   Fixed repeated use of Cmd+Shift+V after image generation.

-   Fixed blank previews when copying links from rich-text sources.

-   Fixed Swift 6 concurrency lock warnings by switching cache access to async-safe patterns.

---

### Technical Changelog

- **SourceAnchor Pipeline**  
  Implemented capture, persistence, sync, and export for source anchors.

- **Link Metadata Pipeline**  
  Unified link metadata fetch/cache/render pipelines for previews and images.

- **CLI Bridge Service**  
  Improved connection lifecycle management in CLI Bridge.

---

### Localization

-   Added en/de localizations for CLI Bridge and IDE actions.

---

### Compatibility & Behavior Notes

-   CLI Bridge continues to listen only on 127.0.0.1.

-   No breaking database schema changes; safe for in-place upgrade.

---

### Upgrade Notes

-   All users are recommended to upgrade for improved IDE tracing, link sharing, and CLI Bridge stability.

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.1.6/Deck.dmg)

<!-- release-changelog-bot:tag:v1.1.5 -->
## v1.1.5 — v1.1.5 | Fortified

- **Tag:** `v1.1.5`
- **Published:** 2026-01-05T05:07:30Z

### Release notes

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://github.com/user-attachments/assets/1b523c6b-7785-4698-8931-db205e43d7be">
    <img width="256" height="256" alt="Deck" src="https://github.com/user-attachments/assets/883ebfa4-29a1-4dd7-a282-c2e9e5f66cac" />
  </picture>
</p>

<h1 align="center">Deck</h1>

<p align="center">A modern, native, privacy-first clipboard OS for macOS</p>

---

## Release Notes v1.1.5

### New

-   Added intelligent detection for ID numbers (CN/TW/HK ID, passport, German tax ID, US SSN/ITIN) with a privacy toggle to skip saving detected content.

-   Added temporary clipboard items that self-destruct after a paste, accessible from the item menu with a clear visual indicator.

-   Added text steganography: hide text in images (LSB) or text (zero-width chars), with auto-detect and decode in clipboard history; encrypted via AES-GCM with optional shared passphrase stored in Keychain.

-   Added an OCR settings section to General Settings, matching the existing design system and exposing recognition level, language correction, max text length, and language toggles.

---

### Improvements

-   Security mode now rejects plaintext fallback on encryption failures with a single user-facing alert; app name is encrypted/decrypted and included in migrations for consistent privacy.

-   DB state and reinitialization are fully serialized on `dbQueue`; iCloud and LAN group sync no longer capture `ClipboardItem` in detached tasks.

-   Large-image migration now uses keyset pagination and only bumps schema version after completion; embedding migration fails safe on encryption errors.

-   File pasteboard writes now use `NSPasteboardItem + NSFilenamesPboardType`; LAN group receive inserts through `dbQueue`; iCloud sync can rebuild items from DB ids.

-   Search paths now read `dbQueue` state consistently; search cache decrypts `appName` in security mode; filenames like `deck-...@1x.png` no longer trigger email detection.

-   Export success dialog now reports the actual exported count instead of the in-memory page size.

-   Stego key UI now adapts to narrow layouts; auto-decode happens before focus-text-only filtering; added a new “store & copy” flow for stego outputs.

---

### Fixes

-   Fixed zero-width text decoding reliability issues.

-   Fixed transparent PNG handling in image steganography.

-   Fixed localization table conflicts by consolidating into `Localizable.xcstrings`.

-   Fixed regex handling, ignore behavior, tag creation, and share URL encoding in Smart Rules.

-   Ensured OCR completion handlers always return on the main thread.

---

### Technical Changelog

- **ScriptPluginService.swift**  
  Added hash-based network authorization, safer timeout/interrupt handling, and moved execution off the main thread.

- **UserDefaultsManager.swift**  
  Added persistence and migration for network plugin authorizations and OCR settings.

- **DirectConnectService.swift**  
  Moved PSKs to Keychain, hardened buffer parsing, and improved connection handling.

- **PasteQueueHUDController.swift**  
  Replaced emoji labels with ASCII tags in the paste queue HUD.

---

### Localization

-   Added English and German localizations for new privacy, stego, and alert UI.

-   Added en/de localizations for queue-mode help text and action labels.

-   Removed 17 unused keys to clear “References to this key…” warnings.

-   Filled missing translations and marked zh-Hans entries for version/import prompts as translated.

---

### Compatibility & Behavior Notes

-   This release introduces no breaking database schema changes and supports in-place upgrades.

-   All privacy processing, detection, and encryption are performed locally.

---

### Upgrade Notes

-   All users are recommended to upgrade for stronger privacy guarantees, more robust sync and migration, and the new temporary and steganography features.

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.1.5/Deck.dmg)

<!-- release-changelog-bot:tag:v1.1.4 -->
## v1.1.4 — v1.1.4 | Quietly Better

- **Tag:** `v1.1.4`
- **Published:** 2026-01-04T03:45:34Z

### Release notes

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://github.com/user-attachments/assets/1b523c6b-7785-4698-8931-db205e43d7be">
    <img width="256" height="256" alt="Deck" src="https://github.com/user-attachments/assets/883ebfa4-29a1-4dd7-a282-c2e9e5f66cac" />
  </picture>
</p>

<h1 align="center">Deck</h1>

<p align="center">A modern, native, privacy-first clipboard OS for macOS</p>

---

## Release Notes v1.1.4

### New

-   Added “Open in Default Browser” and “Show QR Code” actions to link context menu. QR code is displayed in a full-screen frosted overlay, dismissible via ESC or background click, and returns focus to Deck.

-   Added a full-screen QR overlay with frosted background and centered QR code plus title and URL for easy sharing.

-   File and folder search now includes file name indexing, with non-destructive background backfilling and no schema changes.

-   Added QuickLook preview for Office documents, sharing the same panel framework as PDF preview.

-   Added queue mode introduction and shortcuts to the onboarding flow.

-   Added queue mode shortcut hints and usage tips in Settings.

---

### Improvements

-   Redesigned link preview UI to show favicon, title, site name, and URL, consistent between list and preview panel.

-   Preview now reuses list cache and in-flight requests to avoid duplicate fetches.

-   Improved panel stability in full-screen and multi-display setups by following the active app’s screen and Space.

-   Improved keyboard focus stability when opening the panel via double-Option, and improved Space preview reliability.

-   Input mode and search focus now restore more intuitively when opening or closing the panel.

-   Increased hit areas of the four top buttons (Tag, Settings, Pause, Quit) for better usability.

-   Added and refined Chinese, English, and German localizations for context menus, QR hints, and empty state texts.

---

### Fixes

-   Fixed clipboard item count showing as 0 in Storage Info; it now reflects the actual database total.

-   Fixed incorrect input mode and focus restoration after closing the panel.

-   Fixed overly small hit areas on the top buttons.

-   Fixed misleading empty-state messaging when search yields no results.

-   Fixed security-scoped bookmarks accumulating access counts under frequent path checks.

-   Fixed DB error tracking not being serialized, causing duplicate notifications and recovery attempts.

-   Fixed large image offload storing duplicate thumbnails in both data and preview_data.

-   Fixed Swift 6 async lock issues in DB error tracking.

---

### Technical Changelog

-   Added comprehensive class-level documentation clarifying responsibilities, threading model, and security semantics.

-   Documented storage strategies including large image handling, blobPath usage, backup/restore, and migration ordering.

-   Moved DB initialization consistently onto dbQueue for safer sequencing.

-   Added explicit warnings when security mode encryption fails.

---

### Compatibility & Behavior Notes

-   This release introduces no database schema changes and supports in-place upgrades.

-   All processing remains local with no data uploaded or stored remotely.

---

### Upgrade Notes

-   All users are recommended to upgrade for improved multi-display stability, smoother link and QR sharing workflows, and more reliable search and preview behavior.

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.1.4/Deck.dmg)

<!-- release-changelog-bot:tag:v1.1.3 -->
## v1.1.3 — v1.1.3 | Handled with ease

- **Tag:** `v1.1.3`
- **Published:** 2026-01-03T06:31:18Z

### Release notes

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://github.com/user-attachments/assets/1b523c6b-7785-4698-8931-db205e43d7be">
    <img width="256" height="256" alt="Deck" src="https://github.com/user-attachments/assets/883ebfa4-29a1-4dd7-a282-c2e9e5f66cac" />
  </picture>
</p>

<h1 align="center">Deck</h1>

<p align="center">A modern, native, privacy-first clipboard OS for macOS</p>

---

## Release Notes v1.1.3

### New

-   Added support for ⌘, to open Settings directly from the panel, equivalent to the gear button.

-   Added a “Pause” button in the panel (between Settings and Quit) to quickly pause or resume clipboard recording.

-   When paused, the button expands to show “Paused / Countdown” and stays in sync with the menu bar pause state.

-   Added an option for Vim mode to default into Insert mode: opening the panel no longer auto-enters search; typing starts search and preserves the first character.

-   In Insert mode, pressing Esc now only returns to Normal mode without clearing the search, enabling smoother j/k navigation.

-   Simplified Cursor Assistant trigger to Shift only, removing Space and Tab as trigger options.

---

### Improvements

-   Added border and shadow to the search field for better separation from the background and tag area, especially in dark mode.

-   Moved pause status indicator into the Pause button instead of showing it beside the search field for a cleaner UI.

-   Updated the menu bar icon to use template rendering so it adapts automatically to light, dark, and translucent menu bars.

-   Updated the Pause button to a capsule style with orange highlight for clearer state feedback.

-   Improved localization by adding Chinese, English, and German translations for Vim Insert mode and pause-related status messages.

---

### Fixes

-   Fixed an issue where the panel could not be closed by clicking outside when opened via Ctrl.

-   Fixed an issue where clearing the search did not restore the full list and default sorting.

-   Fixed an issue where the first character was not captured when entering search in Vim Insert mode.

-   Fixed an issue where clicking the preview window could unintentionally close the panel.

-   Filtered special keys when auto-entering search to avoid accidental triggers from Space or Enter.

-   Fixed a crash in regex search by changing the SQLite custom regexp function to return Int64(0/1), avoiding “unsupported result type” fatal errors.

---

### Preview & Search Enhancements

-   Added regex match highlighting in plain text preview with a yellow marker style adapted for both light and dark modes.

-   Automatically scrolls the preview to the first match. If the match is deep inside very long text, the preview is truncated to show the relevant segment.

---

### Technical Changelog

-   Implemented regex highlighting and first-match auto-scrolling in LargeTextPreviewView.swift.

-   Wired preview match positioning into PreviewWindowController.swift and PreviewOverlayView.swift.

-   Fixed regexp return type crash in DeckSQLManager.swift.

---

### Compatibility & Behavior Notes

-   This release introduces no database schema changes and supports in-place upgrades.

-   All processing remains local with no data uploaded or stored remotely.

---

### Upgrade Notes

-   All users are recommended to upgrade for smoother Vim workflows, clearer pause state feedback, and more stable search and preview behavior.

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.1.3/Deck.dmg)

<!-- release-changelog-bot:tag:v1.1.2 -->
## v1.1.2 — v1.1.2 | More Intuitive

- **Tag:** `v1.1.2`
- **Published:** 2026-01-02T12:29:32Z

### Release notes

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://github.com/user-attachments/assets/1b523c6b-7785-4698-8931-db205e43d7be">
    <img width="256" height="256" alt="Deck" src="https://github.com/user-attachments/assets/883ebfa4-29a1-4dd7-a282-c2e9e5f66cac" />
  </picture>
</p>

<h1 align="center">Deck</h1>

<p align="center">A modern, native, privacy-first clipboard OS for macOS</p>

---

## Release Notes v1.1.2

### New

-   Added automatic trigger word cleanup. The app now deletes the trigger word (e.g. `num`) before inserting template content, ensuring clean insertion without manual cleanup.

-   Added a system “Important” tag, toggleable via right-click. Any item with a tag (system or custom) will be excluded from auto-clean and auto-delete, ensuring permanent retention unless manually removed.

-   Changed “Add Phrase” in the template library settings to a button + modal interaction, matching Edit/Delete behavior for a more consistent UI language.

---

### Improvements

-   Improved Chinese IME handling. Fixed an issue where committing text with Enter would prevent the Cursor Assistant from triggering. Detection is now stable regardless of input state.

-   Improved the clipboard panel UI with more visually natural layout and enhanced text readability.

-   The Cursor Assistant now closes immediately when clicking on empty space, and ensures the trigger word is removed upon closing.

-   Preview updates are now batched and merged. The UI updates only after navigation stops, reducing refresh frequency, improving stability and power efficiency.

---

### Fixes

-   Fixed an issue where images copied from Notes were not displayed in Deck. Expanded supported image paste types and added RTFD / flat-RTFD attachment parsing.

-   Fixed excessive window updates and wake-ups caused by rapid key navigation, significantly reducing CPU usage and wake events.

-   Fixed an issue where the first item occasionally lacked a focus ring when opening the panel.

-   Fixed the deprecation warning for `activateIgnoringOtherApps` on macOS 14 by adopting the new activation strategy while maintaining backward compatibility.

---

### Technical Changelog

-   Fixed context loss when committing Chinese IME input. Added AXUIElement-based screen reading as a fallback trigger detection mechanism.

-   Added auto-backspace logic. The app now calculates trigger word length and simulates Delete key events before pasting.

-   Improved localization by completing missing English and German translations and fixing formatted count strings on the Statistics page.

---

### Compatibility & Behavior Notes

-   This release introduces no breaking database schema changes and supports in-place upgrades.

-   All recognition and processing is performed locally with no data uploaded or stored remotely.

---

### Upgrade Notes

-   All users are recommended to upgrade for improved input stability, lower power usage, and more consistent interactions.

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.1.2/Deck.dmg)

<!-- release-changelog-bot:tag:v1.1.1 -->
## v1.1.1 — v1.1.1 | Safer

- **Tag:** `v1.1.1`
- **Published:** 2026-01-01T12:37:26Z

### Release notes

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://github.com/user-attachments/assets/1b523c6b-7785-4698-8931-db205e43d7be">
    <img width="256" height="256" alt="Deck" src="https://github.com/user-attachments/assets/883ebfa4-29a1-4dd7-a282-c2e9e5f66cac" />
  </picture>
</p>

<h1 align="center">Deck</h1>

<p align="center">A modern, native, privacy-first clipboard OS for macOS</p>

---

## Release Notes v1.1.1 (fix)

### Issues

-   The app would crash when clicking the refresh button next to a connected device on the Network page.

-   In Secure Mode, the system fingerprint authentication dialog would flicker and repeatedly reappear after pressing “Cancel”.

-   There was no systematic mechanism for recognizing and validating bank card numbers, leading to false positives and missed detections.

---

### Fixes & Improvements

-   Fixed a crash when clicking the refresh button next to connected devices.

-   Fixed an issue where the fingerprint authentication dialog would flicker and repeatedly appear after cancellation in Secure Mode.

-   Added bank card number recognition with multi-strategy validation for improved accuracy and safety:
    Length matching  
    Prefix matching (BIN rules)  
    Lightweight Luhn algorithm validation  

-   Added support for custom template libraries with per-library trigger keywords for the Cursor Assistant, enabling fast access and insertion of preset content.

---

### Compatibility & Behavior Notes

-   This release introduces no breaking database schema changes and can be installed as an in-place upgrade.

-   Bank card recognition is performed locally and does not upload or store any sensitive information.

-   Template libraries and trigger keywords are local-only and do not affect existing templates.

---

### Upgrade Notes

-   All users are recommended to upgrade to avoid crashes and obtain a more stable Secure Mode experience.

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.1.1/Deck.dmg)

<!-- release-changelog-bot:tag:v1.1.0(fix) -->
## v1.1.0(fix) — v1.1.0(fix) | Bug Fix

- **Tag:** `v1.1.0(fix)`
- **Published:** 2026-01-01T04:07:02Z

### Release notes

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://github.com/user-attachments/assets/1b523c6b-7785-4698-8931-db205e43d7be">
    <img width="256" height="256" alt="Deck" src="https://github.com/user-attachments/assets/883ebfa4-29a1-4dd7-a282-c2e9e5f66cac" />
  </picture>
</p>

<h1 align="center">Deck</h1>

<p align="center">A modern, native, privacy-first clipboard OS for macOS</p>

## Release Notes v1.1.0 (fix)

This is a hotfix release focused on eliminating abnormal battery drain, frequent wake-ups, and stutters caused by synchronous DB work on the main thread.

* * *

### Improvements

Unified DB access to run asynchronously on the serial `dbQueue` and `await` results, significantly reducing main-thread load and energy impact.

Async closures now explicitly capture `self` for clearer concurrency semantics and easier maintenance.

* * *

### Fixes

Fixed: The main thread synchronously waiting on the DB queue caused sustained CPU activity and frequent wake-ups (abnormal battery drain).

Fixed: Search, FTS, stats, and export paths triggering synchronous SQL on the UI thread amplified energy use and UI stutters.

Fixed: Search, FTS, vector queries, and migration paths now use async DB calls to prevent main-thread SQL scans and blocking waits.

Fixed: Stats and export now read the DB asynchronously, so the UI thread no longer executes SQL directly.

* * *

### Technical Changelog

Reworked synchronous DB reads/writes that could occur on the main thread to run asynchronously on `dbQueue` and `await` results.

Moved high-frequency paths (search/FTS/stats/export/migrations) to async DB calls to avoid UI thread stalls.

* * *

### Compatibility & Behavior Notes

This is a performance/energy hotfix and does not introduce new user interaction flows.

All processing remains local with no data uploaded or stored remotely.

* * *

### Upgrade Notes

Strongly recommended for all v1.1.0 users, especially if you experienced battery drain, frequent wake-ups, or UI stutters.

* * *

### Notes

Wishing everyone good health, a smooth career, and family harmony in the new year.

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.1.0%28fix%29/Deck.dmg)

<!-- release-changelog-bot:tag:v1.1.0 -->
## v1.1.0 — v1.1.0 | Huge Update!

- **Tag:** `v1.1.0`
- **Published:** 2025-12-29T07:05:34Z

### Release notes

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://github.com/user-attachments/assets/1b523c6b-7785-4698-8931-db205e43d7be">
    <img width="256" height="256" alt="Deck" src="https://github.com/user-attachments/assets/883ebfa4-29a1-4dd7-a282-c2e9e5f66cac" />
  </picture>
</p>

<h1 align="center">Deck</h1>

<p align="center">A modern, native, privacy-first clipboard OS for macOS</p>

---

## Release Notes v1.1.0

### New

-   Quick Search: After opening the panel, simply type to automatically enter search mode without clicking the search field. Supports Chinese IME. Disabled in Vim mode.

### Improvements

-   Improved multilingual support by expanding translation coverage and accuracy.

-   Fixed and optimized memory and CPU usage for significantly improved stability.

-   Enhanced the Settings and Welcome UI with a Material Design-inspired style, improving text readability and visibility.

-   Fixed an issue where the first card wasn't displayed as selected upon opening the panel.

-   Implemented several targeted optimizations for other known issues.

---

### Notes

-   This is Deck's final update before the New Year 2026. Happy New Year to everyone!

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.1.0/Deck.dmg)

<!-- release-changelog-bot:tag:v1.0.9 -->
## v1.0.9 — v1.0.9 | More composed

- **Tag:** `v1.0.9`
- **Published:** 2025-12-28T02:45:17Z

### Release notes

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://github.com/user-attachments/assets/1b523c6b-7785-4698-8931-db205e43d7be">
    <img width="256" height="256" alt="Deck" src="https://github.com/user-attachments/assets/883ebfa4-29a1-4dd7-a282-c2e9e5f66cac" />
  </picture>
</p>

<h1 align="center">Deck</h1>

<p align="center">A modern, native, privacy-first clipboard OS for macOS</p>

---

## Release Notes v1.0.9

### New

-   **Semantic search engine upgrade:** Integrated Apple Sentence Embedding with sqlite-vec (static), moving sorting into the database layer for faster responses and lower memory usage.

-   **Smarter hybrid mode:** Merged text and semantic results for higher relevance and more stable recall.

-   **Enhanced Chinese search:** Enabled FTS5 trigram tokenization for more accurate and faster CJK retrieval.

---

### Improvements

-   **OCR performance optimization:** Downsamples large images to reduce UI lag and memory spikes.

-   **Sync and database stability:** Improved CloudKit batch submission and added automatic backup, integrity checks, and recovery mechanisms.

-   **Memory optimization:** Reduced memory usage from ~300MB to ~50MB.

---

### Technical Changelog

-   Integrated sqlite-vec as a static component to avoid dynamic extension issues and improve startup reliability.

-   Moved search result sorting into the database layer to reduce data copying and intermediate memory usage.

-   Updated FTS5 configuration to use trigram tokenizer for better CJK support.

---

### Compatibility & Behavior Notes

-   This release introduces no database schema changes and supports in-place upgrades.

-   All processing is performed locally with no data uploaded or stored remotely.

---

### Upgrade Notes

-   All users are recommended to upgrade for significantly faster search, lower memory usage, and more stable syncing.

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.0.9/Deck.dmg)

<!-- release-changelog-bot:tag:v1.0.3 -->
## v1.0.3 — v1.0.3 | More elegant

- **Tag:** `v1.0.3`
- **Published:** 2025-12-25T08:55:14Z

### Release notes

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://github.com/user-attachments/assets/1b523c6b-7785-4698-8931-db205e43d7be">
    <img width="256" height="256" alt="Deck" src="https://github.com/user-attachments/assets/883ebfa4-29a1-4dd7-a282-c2e9e5f66cac" />
  </picture>
</p>

<h1 align="center">Deck</h1>

<p align="center">A modern, native, privacy-first clipboard OS for macOS</p>

---

## Release Notes v1.0.3

### New

-   **Version number update:** Aligned internal version identifiers with the release tag.

-   **Icon size optimization:** Refined icon sizing across Dock, menu bar, and settings for better visual consistency.

---

### Compatibility & Behavior Notes

-   This release introduces no functional or data changes, only visual and versioning adjustments.

---

### Upgrade Notes

-   All users are recommended to upgrade for improved visual consistency and correct version labeling.

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.0.3/Deck.dmg)

<!-- release-changelog-bot:tag:v1.0.2 -->
## v1.0.2 — v1.0.2 | More stable

- **Tag:** `v1.0.2`
- **Published:** 2025-12-25T04:16:17Z

### Release notes

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://github.com/user-attachments/assets/1b523c6b-7785-4698-8931-db205e43d7be">
    <img width="256" height="256" alt="Deck" src="https://github.com/user-attachments/assets/883ebfa4-29a1-4dd7-a282-c2e9e5f66cac" />
  </picture>
</p>

<h1 align="center">Deck</h1>

<p align="center">A modern, native, privacy-first clipboard OS for macOS</p>

---

## Release Notes v1.0.2

### New

-   **New app icon:** Replaced the application icon with a new design for improved visual consistency across Dock, menu bar, and settings.

---

### Improvements

-   **Database file validation:** Added validation before database operations to prevent crashes caused by corrupted or invalid files.

---

### Fixes

-   **PRAGMA iteration fix:** Fixed iteration over `PRAGMA table_info` using `failableNext()` to ensure all rows are processed correctly.

-   **FTS binding and iteration fix:** Fixed issues with binding and iterating over FTS search statements.

---

### Compatibility & Behavior Notes

-   This release introduces no database schema changes and supports in-place upgrades.

-   All processing remains local with no data uploaded or stored remotely.

---

### Upgrade Notes

-   All users are recommended to upgrade for improved stability and safer data handling.

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.0.2/Deck.dmg)

<!-- release-changelog-bot:tag:v1.0.1 -->
## v1.0.1 — v1.0.1 | Smoother

- **Tag:** `v1.0.1`
- **Published:** 2025-12-08T08:07:55Z

### Release notes

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://github.com/user-attachments/assets/1b523c6b-7785-4698-8931-db205e43d7be">
    <img width="256" height="256" alt="Deck" src="https://github.com/user-attachments/assets/883ebfa4-29a1-4dd7-a282-c2e9e5f66cac" />
  </picture>
</p>

<h1 align="center">Deck</h1>

<p align="center">A modern, native, privacy-first clipboard OS for macOS</p>

---

## Release Notes v1.0.1

### New

-   **Mouse wheel mode:** Added support for navigating clipboard items using the mouse wheel.

-   **Vim key system enhancements:** Improved Normal/Insert mode transitions and key handling for smoother keyboard navigation.

---

### Compatibility & Behavior Notes

-   This release introduces no database schema changes and focuses on interaction and input system improvements.

---

### Upgrade Notes

-   All users are recommended to upgrade for a smoother combined keyboard and mouse workflow.

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.0.1/Deck.dmg)

<!-- release-changelog-bot:tag:v1.0.0(fix) -->
## v1.0.0(fix) — v1.0.0(fix) | Hotfix

- **Tag:** `v1.0.0(fix)`
- **Published:** 2025-12-08T02:49:14Z

### Release notes

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://github.com/user-attachments/assets/1b523c6b-7785-4698-8931-db205e43d7be">
    <img width="256" height="256" alt="Deck" src="https://github.com/user-attachments/assets/883ebfa4-29a1-4dd7-a282-c2e9e5f66cac" />
  </picture>
</p>

<h1 align="center">Deck</h1>

<p align="center">A modern, native, privacy-first clipboard OS for macOS</p>

---

## Release Notes v1.0.0 (fix)

### Fixes

-   **Database file validity check:** Added `isDatabaseFileValid()` to verify that the database file exists and is readable before each operation.

-   **Hardened withDB flow:** Validate the database file before execution. If invalid or missing, the app logs a warning, notifies the user, attempts async recovery, and returns `nil` instead of crashing.

-   **Safe SQL iteration:** Replaced unsafe `for-in` iteration with `failableNext()` for PRAGMA and FTS queries to avoid fatal errors caused by `try!`.

---

### Technical Notes

-   `db.prepare(Table query)` returns `AnySequence<Row>`, whose internal iterator uses `try!` and cannot be safely controlled externally.

-   `db.prepare(String SQL)` returns `Statement`, which allows safe iteration via `failableNext()`.

-   Validating the database file before execution prevents most crashes caused by deleted or moved database files.

---

### Compatibility & Behavior Notes

-   This release introduces no database schema or data format changes and supports in-place upgrades.

-   All processing remains local with no data uploaded or stored remotely.

---

### Upgrade Notes

-   All users are strongly recommended to upgrade to prevent potential crashes and data corruption.

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.0.0%28fix%29/Deck.dmg)

<!-- release-changelog-bot:tag:v1.0.0 -->
## v1.0.0 — v1.0.0 | Deck Launches — A Privacy-First Clipboard for macOS

- **Tag:** `v1.0.0`
- **Published:** 2025-12-06T07:12:15Z

### Release notes

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://github.com/user-attachments/assets/1b523c6b-7785-4698-8931-db205e43d7be">
    <img width="256" height="256" alt="Deck" src="https://github.com/user-attachments/assets/883ebfa4-29a1-4dd7-a282-c2e9e5f66cac" />
  </picture>
</p>

<h1 align="center">Deck</h1>

<p align="center">A modern, native, privacy-first clipboard OS for macOS</p>

---

## Release Notes v1.0.0 | Deck Launches

### New

-   **Initial release:** Deck is officially launched — a modern, native, privacy-first clipboard OS for macOS.

-   **Clipboard history:** Automatically stores text, images, links, and files.

-   **Fast search & filtering:** Fuzzy search and filters for instant retrieval.

-   **Rich previews:** Inline preview for images, PDFs, and links.

-   **Keyboard-first workflow:** Global hotkeys and optional Vim-style navigation.

-   **Privacy & security:** All data stays local with encryption and biometric protection.

-   **Scriptable pipeline:** Plugins and rules for automation and extensibility.

-   **LAN sharing:** Peer-to-peer local sharing without the cloud.

---

### Compatibility & Behavior Notes

-   This is the initial public release; future updates will focus on stability, performance, and extensibility.

-   All processing remains local with no data uploaded or stored remotely.

---

### System Requirements

- Apple Silicon 或 Intel Mac（Universal Binary）

---

### Installation

   Download `Deck.dmg`

   Drag `Deck.app` into the Applications folder

   If the app is blocked on first launch:  
   Go to **System Settings → Privacy & Security → Security**, then click **Open Anyway / Allow**

   Grant Accessibility permission when prompted


---

### Upgrade Notes

-   Users are encouraged to follow future updates for continued improvements.

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.0.0/Deck.dmg)
