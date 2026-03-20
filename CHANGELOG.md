# GitHub Releases Changelog

本文件由 [release-changelog-bot](.github/workflows/release-changelog-bot.yml) 根据 GitHub Release 自动生成与增量更新；**请勿手动修改各版本条目**（可修改本说明文字）。

<!-- release-changelog-bot:auto -->

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
- AI 助手新增联网搜索与网页抓取工具，并支持通过 OpenCode Zen 快速接入免费模型。  
  The AI assistant gains web search and page-fetch tools, plus a quick path to configure OpenCode Zen free models.  
- 可在设置中即时隐藏或显示菜单栏图标，无需重启；主面板支持 Cmd+F 聚焦搜索框。  
  Hide or show the menu bar icon instantly from Settings without restarting; use Cmd+F in the main panel to focus the search field.  
- 全局快捷键、Typing Paste 与光标助手触发键统一冲突检测，保存失败会回滚并提示，避免界面与注册状态不一致。  
  Global shortcuts, Typing Paste, and cursor-assistant triggers share conflict checks; failed saves roll back with a clear alert.  
- 局域网同步与发现逻辑在唤醒、重连与回调上更稳健，并修复多处界面漏翻与 OAuth 完成页体验。  
  Nearby sync and discovery are more stable around sleep/wake and reconnects; UI string gaps and the OAuth completion flow are improved.  

### 新增 / Added
- **联网搜索与网页抓取（AI）**  
  为 AI 助手新增 `web_search` 与 `web_fetch` 工具：支持向 Exa 端点发起搜索、抓取网页并转换为 Markdown 或纯文本，内容过长会自动截断；Smart Rule 自动化不包含这两项外网能力。  
  Adds `web_search` and `web_fetch` for the AI assistant: search via the Exa endpoint, fetch pages, and convert HTML to Markdown or plain text with safe size limits; Smart Rule automation does not include these web tools.  
- **OpenCode Zen 免费模型快速配置**  
  在 OpenAI API 配置区提供 Zen 入口与模型选择表，确认后自动填入 Base URL、API Key 与模型名称，便于零门槛试用免费模型。  
  Adds a Zen entry and model picker in the OpenAI API section to auto-fill base URL, API key placeholder, and model name for free-tier models.  

### 优化 / Improvements
- **菜单栏图标开关**  
  在「通用 > 启动」中可打开或关闭菜单栏图标，写入既有偏好并立即生效；再次显示时会同步当前暂停状态，图标语义不丢失。  
  A “Show menu bar icon” toggle under General › Startup updates the existing preference and applies immediately; when shown again, pause state stays in sync.  
- **主面板 Cmd+F 聚焦搜索**  
  在主面板按 Cmd+F 会显式将焦点移到搜索框；若规则列表弹层已打开会先收起，并与短暂焦点抑制逻辑配合，在开启或关闭 Vim 模式时均可使用；仍保留直接键入即可搜索的行为。  
  Cmd+F in the main panel focuses the search field, dismissing the rules popover if needed and working alongside brief focus suppression and Vim mode; typing to search still works as before.  
- **OAuth 完成页「打开 Deck」**  
  授权完成页主按钮改为「打开 Deck」，通过自定义 URL Scheme 唤起应用，替代仅关闭页面的体验。  
  The OAuth completion button now reads “Open Deck” and launches the app via its URL scheme instead of only closing the page.  
- **AI 设置界面**  
  移除「AI 助手」标题旁的 Beta 标签，界面更简洁。  
  Removes the Beta pill next to the AI Assistant title for a cleaner settings screen.  
- **Zen 配置界面与文案**  
  Zen 横幅复用既有配置行样式并与维护报告类 Sheet 视觉对齐；相关新增文案已补全多语言翻译。  
  The Zen banner reuses existing config-row styling and matches maintenance-style sheets; new strings are localized across supported languages.  
- **快捷键与触发键校验**  
  为全局快捷键、Typing Paste 录制与恢复默认、以及光标助手自定义触发键接入统一冲突检测（含为队列「依次粘贴」保留的 ⌘⇧V），录制与保存路径一致。  
  Adds unified conflict validation for global shortcuts, Typing Paste record/reset, and cursor-assistant triggers, including reserving ⌘⇧V for queue sequential paste.  
- **局域网同步稳定性**  
  监听系统睡眠与唤醒，唤醒后延迟再恢复发现以降低刚唤醒时的 browser/advertiser 抖动；为记住节点的自动重连增加去抖并尊重连接中与拒绝重试时间；为重复邀请与过期回调增加防护，并在刷新或停止时取消任务、清理委托。  
  Observes display sleep/wake, delays discovery after wake, debounces remembered-peer reconnects, avoids duplicate invites and stale callbacks, and cancels tasks plus clears delegates on refresh/stop.  
- **设置与主界面文案本地化**  
  补齐菜单栏与快捷键相关新文案，以及空剪贴板、队列提示、搜索占位、导入规则、预览与 AI 错误等多处此前会露出中文 fallback 的条目，覆盖项目当前支持的语言。  
  Localizes new settings strings and fills gaps for empty clipboard, queue hints, search placeholders, import rules, previews, and AI errors across supported languages.  

### 变更 / Changes
- **快捷键保存行为**  
  当系统未能成功注册新快捷键时，会自动回滚到先前已保存的组合并弹出说明，避免出现界面已改但实际未生效的情况。  
  If shortcut registration fails, the UI rolls back to the last saved combination and shows an explanation instead of appearing updated while inactive.  
- **AI 系统提示与工具说明**  
  系统提示中的工具数量与文档已更新，明确包含联网搜索与抓取工具及其使用边界（含无需单独授权、由助手自主判断等说明）。  
  Updates the system prompt tool count and documentation to include web search and fetch, including usage expectations such as no per-call approval.  

### 修复 / Fixes
- **Multipeer 状态与冷却**  
  在特定场景下保留对未连接状态的冷却，避免 `lostPeer` 误清；`lostPeer` 主要取消待执行的自动重连并清理发现相关 UI 状态。  
  Preserves not-connected cooldowns where appropriate so `lostPeer` does not clear them incorrectly; it cancels pending auto-reconnect and cleans discovery UI state.  
- **界面漏翻与硬编码中文**  
  修复主列表空状态、队列栏拼接、HUD 与搜索等区域在运行时仍显示中文或缺 key 的问题。  
  Fixes runtime Chinese fallbacks and missing keys in empty states, queue UI, HUD, and search-related copy.  

### 升级建议 / Upgrade Notes
- 若使用自定义 AI 基址与模型，可在「AI 设置」中查看 Zen 快速配置是否适合你的隐私与合规要求后再启用。  
  If you use custom AI endpoints, review Zen quick setup against your privacy and compliance needs before enabling.  

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

- **下载校验失败时自动恢复**  
  下载后遇到大小或哈希不匹配时，Deck 现在会先尝试恢复和重新确认，而不是直接报出致命错误。  
  When a downloaded package fails size or hash validation, Deck now attempts recovery and reconfirmation before surfacing a fatal error.

- **更新信息会在安装中动态刷新**  
  如果安装过程中可用更新已经发生变化，更新弹窗会自动切换到最新信息，避免继续安装过期快照。  
  If the available update changes during installation, the update prompt now refreshes to the latest info instead of continuing with a stale snapshot.

- **边缘缓存导致的误判更少**  
  针对旧缓存和边缘节点未同步完成的情况，Deck 会刷新元数据、追加 cache-bust 下载并自动重试一次。  
  Deck now refreshes metadata, adds cache-busting to retry downloads, and automatically retries once when stale cache or edge-node lag is suspected.

### 优化 / Improvements

- **恢复流程更贴近真实场景**  
  下载校验异常后，Deck 会重新拉取最新元数据并根据实际情况决定后续处理路径，让升级流程更稳健。  
  After a validation mismatch, Deck re-fetches the latest metadata and chooses the next step based on the current update state for a more resilient upgrade flow.

- **错误提示更易理解**  
  这类下载异常现在会显示更贴近场景的提示，不再只剩下笼统的“大小不一致”原始报错。  
  Download validation failures now show clearer, scenario-specific messaging instead of only a generic "size mismatch" style error.

### 变更 / Changes

- **版本变化需要重新确认**  
  如果恢复过程中发现远端版本已经变化，Deck 会更新本地记录，并提示你基于最新版本重新确认安装。  
  If recovery detects that the remote version has changed, Deck updates the local record and asks you to confirm installation again against the latest version.

- **同版本资源变更会切换到新包**  
  如果版本号未变但安装资源已更新，Deck 会刷新到新的安装包信息，并要求重新确认后继续。  
  If the version stays the same but the underlying asset changes, Deck refreshes to the new package information and requires reconfirmation before continuing.

### 修复 / Fixes

- **边缘节点延迟导致的校验误报**  
  当元数据没有变化时，Deck 会将其视为边缘节点同步延迟，短暂等待后自动重试下载一次。  
  When metadata is unchanged, Deck now treats the mismatch as likely edge propagation delay and automatically waits briefly before retrying the download once.

- **旧缓存包导致的重复下载失败**  
  重试下载现在会附带 cache-bust URL，尽量绕开陈旧缓存，减少反复命中旧安装包的问题。  
  Retry downloads now use cache-busting URLs to avoid stale caches and reduce repeated failures caused by outdated packages.

- **更新弹窗持有旧快照的问题**  
  如果安装途中发现可用更新已经变更，当前更新弹窗会切换到新的更新信息，而不是继续沿用旧快照。  
  If the available update changes mid-install, the current update prompt now switches to the new update info instead of holding onto the old snapshot.

### 升级建议 / Upgrade Notes

- **建议直接升级**  
  此更新主要提升更新下载与确认流程的稳定性，尤其能减少缓存或同步延迟造成的误报与卡死体验。  
  This release mainly improves the reliability of the update download and confirmation flow, especially for failures caused by cache staleness or propagation lag.

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
  横向 Deck 现在支持从顶部拖拽调整高度，并会记住你上次使用的面板尺寸。  
  Horizontal Deck can now be resized from the top edge, and it remembers your last panel height.
- **Cards scale with the panel**  
  横版卡片会跟随面板高度同步放大，图片、链接、文本与代码内容都能更舒展地展示。  
  Horizontal cards now scale with panel height, giving images, links, text, and code more room to breathe.
- **Navigation feels more natural across views**  
  横向/纵向 Deck 与 Cursor Assistant 的键盘导航语义进一步统一，输入态下也不会抢走文本编辑按键。  
  Keyboard navigation now feels more consistent across horizontal/vertical Deck and Cursor Assistant, without stealing editing keys while typing.
- **Preview stays in sync with selection**  
  预览打开后，切换标签或改变选中项时会立即跟随当前聚焦内容，不再出现内容不同步。  
  Open previews now stay synced with the current selection when you switch tabs or move focus.
- **Preview reading is cleaner and less cramped**  
  纯文本、Markdown、代码和单图预览改成更贴边、更沉浸的布局，并统一了更轻的滚动条样式。  
  Plain text, Markdown, code, and single-image previews now use a cleaner edge-to-edge layout with lighter, more consistent scrollbars.

### 新增 / Added
- **Panel height adjustment for horizontal Deck**  
  横向 Deck 新增顶部拖拽手柄，可直接向上拉伸主面板高度，并自动保存你的自定义尺寸。  
  Added a top resize handle for horizontal Deck so you can drag upward to expand the panel height and keep your preferred size.
- **Modifier-based quick number hints**  
  按住修饰键时，横版卡片现在会显示前 9 个可快速命中的编号提示，便于更快定位。  
  Added modifier-triggered quick number hints for the first 9 reachable horizontal cards to make fast targeting easier.

### 优化 / Improvements
- **Adaptive horizontal card layout**  
  横版卡片会根据面板高度动态调整尺寸、内容密度与截断策略，让放大后的空间真正转化为更好的可读性。  
  Horizontal cards now adapt their size, content density, and truncation rules to panel height so extra space improves readability instead of just scaling the frame.
- **Richer image and link presentation**  
  图片卡片补充了更清晰的信息排布与透明格背景，链接卡片的图片区和图标也会随尺寸自然放大。  
  Image cards now use clearer metadata layout and a checkerboard transparency background, while link cards scale their media area and icons more naturally.
- **Cleaner preview surfaces**  
  纯文本、Markdown、代码和单图预览改成更贴边的展示方式，滚动条更细、更轻，整体阅读压迫感更低。  
  Plain text, Markdown, code, and single-image previews now feel more immersive with edge-to-edge presentation and slimmer, lighter scrollbars.
- **Smaller and tidier card number badges**  
  横版卡片右下角的数字提示进一步收紧尺寸与位置，视觉上更轻，不容易干扰内容本身。  
  The quick number badges in the lower-right corner of horizontal cards are now smaller and better placed, making them less distracting.

### 变更 / Changes
- **Direction-first keyboard semantics**  
  横向 Deck 的快捷键现在更强调方向语义：Ctrl+N / Ctrl+P 对应下一项 / 上一项，Ctrl+F / Ctrl+B 对应右移 / 左移；开启 Vim mode 后，h / l 固定左右，j / k 继续兼容导航。  
  Horizontal Deck shortcuts now prioritize directional semantics: Ctrl+N / Ctrl+P move to next / previous, Ctrl+F / Ctrl+B move right / left, and Vim mode keeps h / l fixed to left / right while j / k remain as compatible navigation keys.
- **Vertical navigation stays intentionally simpler**  
  纵向 Deck 继续保留方向键与 Ctrl+N / Ctrl+P 的上下移动语义；Vim mode 下支持 j / k 上下，但不再额外引入 Ctrl+F / Ctrl+B。  
  Vertical Deck keeps a simpler navigation model with arrow keys and Ctrl+N / Ctrl+P for up/down movement, plus j / k in Vim mode without adding Ctrl+F / Ctrl+B.
- **Cursor Assistant follows the same input rules**  
  Cursor Assistant 现已支持 Ctrl+N / Ctrl+P，以及 Vim mode 下的 j / k 上下移动，并与主面板保持一致的输入态保护。  
  Cursor Assistant now supports Ctrl+N / Ctrl+P and j / k in Vim mode, following the same input-state protection rules as the main panel.

### 修复 / Fixes
- **Preview sync after selection changes**  
  修复了预览只在部分键盘移动场景下刷新、在标签切换或外部选中变化后可能不同步的问题。  
  Fixed a preview sync bug where updates only reliably followed certain keyboard moves and could fall out of sync after tab switches or other external selection changes.
- **Long-press preview throttling no longer overrides fresh focus**  
  修复了长按方向键时的延迟预览刷新可能覆盖较新选中项的问题，预览跟随现在更稳定。  
  Fixed an issue where delayed preview updates during long key presses could override newer focus changes, making preview following more reliable.
- **No more extra code warning block in preview**  
  修复了超长代码预览底部额外提示占位的问题，正文不再因此被压缩或截断。  
  Removed the extra warning block shown under very long code previews, so the main content no longer gets squeezed or visually cut off.

### 说明 / Notes
- **Large code still protects performance**  
  超长代码仍会保留关闭高亮等性能保护策略，但界面上不再额外显示打断阅读的提示块。  
  Very large code previews still keep their performance safeguards, such as disabling highlighting, but no longer show an intrusive extra notice in the UI.

### 兼容性与行为说明 / Compatibility & Behavior Notes
- **Resize applies to horizontal Deck only**  
  本次面板拖拽调高仅作用于横向 Deck，纵向列表的整体高度行为保持不变。  
  The new panel resize behavior applies only to horizontal Deck; overall height behavior for the vertical list remains unchanged.
- **Editing contexts still keep priority**  
  搜索框与编辑态下仍会优先保留原本的文本输入快捷键行为，不会因为新导航映射而被劫持。  
  Search fields and editing contexts still preserve normal text input shortcuts, so the new navigation mappings do not hijack editing behavior.

### 升级建议 / Upgrade Notes
- **Recommended for users who rely on horizontal Deck or preview workflows**  
  如果你主要使用横向 Deck、依赖键盘导航，或经常在面板里做预览浏览，这次更新值得优先升级。  
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
  AI 聊天的自动滚动、流式刷新和尾部渲染一起做了收敛，长回复时更顺，不再轻易把你从历史消息里拽走。  
  AI chat now feels much steadier, with smarter auto-follow, smoother streaming updates, and tail-only rendering that no longer yanks you away from message history.
- **Heavy AI work backs off the main thread**  
  AI 会话存储与部分刷新链路进一步避开主线程，明显减轻发送瞬间卡顿、主线程堵塞和内存抖动。  
  More AI persistence and refresh work now stays off the main thread, reducing send-time freezes, UI stalls, and memory churn.
- **Search panel state is more reliable**  
  搜索栏展开态、焦点同步和拼音输入残留问题已修复，面板反复开关时更稳定。  
  Search panel state is now more reliable, with fixes for expansion drift, focus sync, and leftover IME composition when reopening the panel.
- **Queue mode is more customizable**  
  队列模式新增数字映射起点设置，你可以继续从最左侧开始，也可以改成从当前聚焦项开始。  
  Queue mode now lets you choose where number-key mapping starts, either from the leftmost card or from the currently focused item.
- **Feedback and AI text are more polished**  
  反馈入口新增邮件/网页分流，AI 相关默认文案和提示也补齐了本地化。  
  Feedback now offers email or web reporting, and more AI-facing default labels and prompts are properly localized.

### 新增 / Added
- **Queue quick-select anchor setting**  
  设置里新增“数字映射起点”，队列模式下可选择数字键从最左侧卡片或当前聚焦卡片开始映射。  
  Added a new “Number Mapping Start Point” setting so queue mode can map number keys from either the leftmost card or the currently focused card.
- **Web feedback entry**  
  反馈入口新增网页报告方式，并会自动附带设备、系统、版本、语言和时区等诊断信息。  
  Added a web-based feedback flow that automatically attaches device, system, app version, locale, and time zone details.

### 优化 / Improvements
- **Smarter chat auto-follow**  
  聊天页现在会在你刚发送消息、AI 正在输出且你本来就在底部附近时持续贴底；如果你主动上翻历史，就不会再被普通输出强行拉回底部。  
  Chat now stays pinned only when you just sent a message, AI is actively replying, and you were already near the bottom; if you scroll up intentionally, normal streaming output no longer forces you back down.
- **Smoother streaming output**  
  流式刷新节奏与滚动触发策略进一步放缓并分层处理，长内容生成时的抖动、白屏和跳动感更低。  
  Streaming refresh and scroll triggering have been softened and layered more carefully, reducing jitter, blank flashes, and jumpiness during long responses.
- **Tail-only rendering for active responses**  
  正在输出的 AI 消息改为更聚焦的尾部更新方式，历史内容不会再随着每次流式输出被大范围重算。  
  Active AI responses now update through a more focused tail-rendering path, so stable history no longer gets broadly recomputed on each stream tick.
- **Lighter conversation persistence**  
  AI 会话保存和索引写入做了更聪明的合并与调度，连续操作时磁盘写入更克制。  
  AI conversation persistence and index updates are now merged and scheduled more intelligently, reducing unnecessary disk activity during bursts of activity.
- **More stable message layout**  
  消息文本的纵向布局更稳定，长文本持续生长时更不容易出现布局抖动。  
  Message text now uses a steadier vertical layout, making long streaming content less prone to layout instability.

### 变更 / Changes
- **Priority-based scroll behavior**  
  聊天滚动现在按事件类型分层：普通 AI 输出尽量不打断阅读，而权限请求、交互提示等更重要事件会优先确保可见。  
  Chat scrolling now uses event priorities: normal AI output avoids interrupting reading, while permission requests and interaction prompts are prioritized for visibility.
- **Queue mode status messaging**  
  队列模式状态栏会显示当前数字映射方式，减少忘记当前选择规则的情况。  
  Queue mode now shows the current number-mapping rule in its status area, making the active selection behavior easier to remember.
- **Feedback flow selection**  
  点击反馈时会先让你选择“使用邮件反馈”或“打开网页报告信息”，并按当前语言跳转对应页面。  
  Triggering feedback now lets you choose between email and web reporting first, and the web path follows the current app language.

### 修复 / Fixes
- **Chat view redraw pressure**  
  修复了聊天页在流式输出期间容易整页频繁重绘的问题，显著减轻发送瞬间卡死和滚动时掉帧。  
  Fixed excessive full-view redraw pressure during streaming replies, which significantly reduces send-time freezes and dropped frames while scrolling.
- **Search bar expansion drift**  
  修复了主面板重新打开后搜索栏偶发保持展开但未进入真实搜索态的问题。  
  Fixed an issue where the search bar could reopen in an expanded-looking but not truly active search state.
- **IME composition residue on close**  
  修复了拼音等输入法在候选未确认时关闭面板，重新打开后残留英文、吞键或焦点异常的问题。  
  Fixed issues where closing the panel during unfinished IME composition could leave stray Latin text, swallow key events, or break focus on reopen.
- **AI conversation logging calls**  
  修复了 AIConversationStore 中部分日志调用缺少异步等待的问题，避免相关保存与查询链路出现不稳定行为。  
  Fixed several missing async waits in AIConversationStore logging calls to avoid instability around save and query flows.
- **AI-facing fallback text consistency**  
  修复了部分 AI 默认标题、工具提示和错误提示未完整本地化的问题。  
  Fixed inconsistent localization across some AI default titles, tool prompts, and error messages.

### 说明 / Notes
- **Localization coverage expanded**  
  本次补齐了更多 AI 相关默认文案、工具结果提示、插件生成报错与新对话标题的本地化覆盖。  
  This release expands localization coverage for more AI defaults, tool result prompts, plugin generation errors, and new conversation titles.

### 兼容性与行为说明 / Compatibility & Behavior Notes
- **Existing queue users keep the old default**  
  队列模式的数字映射起点默认仍是“最左侧卡片”，现有用户升级后不会被突然改掉原有习惯。  
  Existing queue users keep the original default behavior, with number mapping still starting from the leftmost card unless changed manually.
- **Search opens in a cleaner default state**  
  面板每次重新打开时，搜索栏会优先回到更干净的默认收窄状态，只有进入真实搜索态后才展开。  
  Each time the panel reopens, the search bar now returns to a cleaner collapsed default state and expands only when truly entering search mode.

### 升级建议 / Upgrade Notes
- **Recommended for all users who rely on AI chat or search**  
  如果你经常使用 AI 对话、长回复阅读、搜索面板或队列模式快捷选择，建议尽快升级到 v1.3.3。  
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
  Deck 现在会把你在对话里分享的偏好、习惯和上下文，整理成持续成长的本地记忆，并且全程加密保存在你的设备上。  
  Deck now turns the preferences, habits, and context you share in chat into a growing local memory system, encrypted and stored on your device.  

- **Script Plugins for AI**  
  AI 现在既能直接调用已有脚本插件，也能在你批准后删除脚本插件；需要联网的插件会先走授权，再执行。  
  AI can now run existing script plugins directly and delete them after your approval; network-enabled plugins ask for permission before running.  

- **AI CLI Bridge**  
  Deck 新增了 `/ai/run`、`/ai/search` 和 `/ai/transform` 三个 AI 接口，让命令行和自动化接入更直接。  
  Deck adds `/ai/run`, `/ai/search`, and `/ai/transform` so AI workflows are easier to drive from the CLI and automation.  

- **AI Smart Rules**  
  Smart Rule 现在支持 AI 动作，但会自动收口权限范围，只处理触发当前规则的那一条内容。  
  Smart Rules now support AI actions, with automatic guardrails that keep each run scoped to the single triggering item.  

- **Faster AI Chat**  
  AI 聊天变得更轻更顺，流式刷新、历史索引和内存占用都做了明显收紧。  
  AI chat is now lighter and smoother, with leaner streaming updates, conversation indexing, and memory usage.  

- **Stability and Polish**  
  自定义存储、导入事务、粘贴回退、热键记忆、图片预览和窗口层级都做了一轮补强。  
  Custom storage, import transactions, paste fallbacks, hotkey persistence, image preview, and window layering all received a solid reliability pass.  

### 新增 / Added
- **AI Memory That Stays Local**  
  Deck AI Memory 会安静记录对话里出现的重要细节，逐步理解你的使用习惯，同时保持本地加密和私密。  
  Deck AI Memory quietly captures important details from conversations, learns your habits over time, and keeps everything local, encrypted, and private.  

- **Run and Delete Script Plugins with AI**  
  AI 现在可以直接运行已有脚本插件，也可以在你确认后删除插件；删除前会展示更明确的风险提醒和插件信息预览。  
  AI can now run existing script plugins and delete them after confirmation, with clearer risk warnings and plugin info shown before removal.  

- **AI Actions in Smart Rules**  
  Smart Rule 新增 AI 动作，创建和保存时都要求填写 Prompt，同时会展示高权限自动化的提示说明。  
  Smart Rules gain a new AI action that requires a prompt before creation or save, along with clear warnings for high-privilege automation.  

- **Zoomable Image Preview**  
  图片预览现在支持右上角缩放按钮、双击放大/还原和手势缩放，图片类预览窗默认也放大了一档。  
  Image preview now supports zoom buttons, double-click to zoom/reset, gesture zooming, and a larger default scale for image previews.  

- **Always-on-Top Toggle**  
  设置里新增“面板始终置顶”开关，关闭后像 Yoink 这类悬浮工具可以显示在 Deck 上方。  
  Settings now include an “always on top” toggle, so tools like Yoink can appear above Deck when you turn it off.  

### Deck × Orbit
- **Three New AI CLI Endpoints**  
  CLI Bridge 新增了运行、搜索和二次处理三条 AI 路径，并在设置页补上了示例和错误示范，接入方式更清楚。  
  The CLI Bridge now adds dedicated AI routes for run, search, and transform, with examples and failure cases documented directly in Settings.  

- **Search Results, Plugin Chaining, and Auto-Save**  
  `/ai/search` 可以回传搜索结果，`/ai/transform` 可以先跑脚本插件再交给 AI 处理，`/ai/run` 和 `/ai/transform` 也支持自动保存。  
  `/ai/search` can return search results, `/ai/transform` can run a script plugin before AI post-processing, and both `/ai/run` and `/ai/transform` support auto-save.  

### 优化 / Improvements
- **Smoother Streaming Replies**  
  AI 回复的流式刷新频率、自动滚动和文本渲染都做了减负，长回复时界面更稳，也更不容易卡。  
  Streaming reply updates, auto-scroll behavior, and text rendering were trimmed down so long AI replies feel steadier and less heavy.  

- **On-Demand Skill Loading**  
  AI 现在先拿到精简后的 skills 目录，再按需读取具体 `SKILL.md`，上下文更干净，工具选择也更精准。  
  AI now starts with a lighter skills directory and loads each `SKILL.md` only when needed, keeping context cleaner and tool choice more precise.  

- **Sharper AI Guidance and Safety Tone**  
  AI 的系统提示词、人格定义和安全约束做了整体重写，回复风格、边界感和稳定性都更统一。  
  The AI system prompt, personality framing, and safety rules were reworked to make responses more consistent, grounded, and stable.  

- **Settings Visual Polish**  
  存储、自检、迁移、安全模式、AI 提供商和辅助功能提示这些设置区域都做了样式统一和点击体验优化。  
  Storage, self-check, migration, security mode, AI provider, and accessibility permission areas in Settings were visually unified and made easier to use.  

- **Broader Localization Coverage**  
  这一版补齐了 AI、Smart Rules、CLI 教学、授权弹窗和窗口选项相关的新文案，并同步到现有多语言。  
  This release adds localization coverage for the new AI, Smart Rules, CLI guide, approval dialogs, and window option strings across the supported languages.  

### 变更 / Changes
- **Plugin Authorization Rules Are Now Explicit**  
  本地插件可直接运行，需要联网的插件会先请求授权，而删除脚本插件无论如何都必须先经过你的批准。  
  Local-only plugins run immediately, network-enabled plugins ask for permission first, and deleting a script plugin always requires your approval.  

- **Smart Rule AI Runs in a Narrow Automation Context**  
  Smart Rule 触发 AI 时不再弹确认框，但只允许处理当前触发的那条记录，也不能创建、修改或删除脚本插件。  
  When a Smart Rule triggers AI, it skips the confirmation dialog but stays limited to the current triggering item and cannot create, edit, or delete script plugins.  

- **Prompt Is Now Required for AI Bridge Requests**  
  `/ai/run`、`/ai/search` 和 `/ai/transform` 现在都要求传入非空 `prompt`，缺失时会直接返回 `400`。  
  `/ai/run`, `/ai/search`, and `/ai/transform` now require a non-empty `prompt`, and return `400` immediately when it is missing.  

- **Larger and Safer JSON Responses**  
  AI Bridge 的 JSON 响应能力做了扩展，同时加上了响应体大小保护，减少异常输出把链路撑爆的风险。  
  The AI Bridge now supports richer JSON responses and adds response-size protection to reduce the chance of oversized payload failures.  

### 修复 / Fixes
- **Custom Storage No Longer Fails Silently**  
  自定义存储目录现在会先迁移成功再写入设置；失败时会回滚界面状态并给出提示，也不会再悄悄退回默认目录。  
  Custom storage now writes settings only after a successful migration, rolls the UI back on failure, and no longer silently falls back to the default location.  

- **Imports Are Now Atomic**  
  导入流程改成先完整解析、再一次性事务入库，中途失败会整批回滚，不会再留下半截数据。  
  Imports now fully parse first and then write in a single transaction, so failures roll the whole batch back instead of leaving partial data behind.  

- **Paste and Activity Fallbacks Are Safer**  
  会话活跃通知接线错误、CGEvent tap 失败后的回退洞和“先吞快捷键再发现没文本”的问题都已经收紧。  
  Incorrect session activity wiring, risky CGEvent tap fallback behavior, and the “swallow shortcut before finding no text” issue have all been tightened up.  

- **Hotkey Reset Now Sticks**  
  清空热键后，重启应用也不会再偷偷恢复成默认值。  
  Cleared hotkeys no longer quietly come back as defaults after the app restarts.  

### 升级建议 / Upgrade Notes
- **Review Any CLI Integrations**  
  如果你接了 CLI Bridge，请确认所有 AI 请求都带上 `prompt`，并补上对 `400` 返回的处理。  
  If you use the CLI Bridge, make sure every AI request includes a `prompt` and that your integration handles `400` responses correctly.  

- **Revisit Smart Rules That Use AI**  
  如果你已经在自动化流程里用 AI，建议重新看一眼规则预期，确认“仅处理触发项”的新边界正符合你的用法。  
  If AI is part of your automation flow, revisit those rules and confirm the new “triggering item only” scope matches what you expect.  

- **Explore the New AI Workflow Features**  
  升级后可以重点试试 AI Memory、脚本插件调用、CLI AI 接口，以及新的图片预览和窗口层级开关。  
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
- **AI 助手设置中心上线**  
  新增 AI 助手设置页，支持 ChatGPT 订阅、OpenAI API、Anthropic API、Ollama 四种接入方式。  
  Added a dedicated AI Assistant settings page with support for ChatGPT Subscription, OpenAI API, Anthropic API, and Ollama.
- **更新安全性显著提升**  
  更新前后都加入版本与 SHA-256 校验，避免错误包或被篡改包被安装。  
  Update flow now verifies version and SHA-256 before and after download to block mismatched or tampered packages.
- **录制快捷键更安心**  
  录制期间会自动暂停全局热键与相关全局触发，避免误触和冲突。  
  Global hotkeys and related global triggers are now paused during shortcut recording to prevent conflicts.
- **AI 流式回复更稳**  
  网络抖动时会自动重试，并避免重连后重复刷出已显示内容。  
  Streaming AI responses now auto-retry on transient failures and avoid duplicate text after reconnect.
- **存储整理新增二进制瘦身**  
  支持扫描与整理可精简架构，并把结果展示在整理报告中。  
  One-click maintenance now includes binary slimming scan/cleanup with results shown in the maintenance report.

### 新增 / Added
- **AI 助手设置页与 Provider 配置**  
  设置中新增「AI 助手 / AI Assistant」Tab，包含 Provider 选择、地址与密钥配置、模型配置、快捷键说明和安全提示。  
  Added an "AI Assistant" tab in Settings with provider selection, endpoint/token/model configuration, shortcut reference, and safety notes.
- **二进制瘦身能力接入**  
  新增多架构二进制扫描与清理能力，可在启动时后台扫描，并可在一键整理时执行。  
  Added binary slimming support to scan removable architectures in the background at startup and clean them during one-click maintenance.
- **更新信息本地安全记录**  
  检测到新版本后会保存版本、大小和 SHA 信息，并在启动时自动恢复更新提示状态。  
  New local update records now store version, size, and SHA metadata and can restore pending update prompts on app startup.

### 优化 / Improvements
- **光标助手弹窗定位更准确**  
  弹窗会按当前坐标所在屏幕定位，插入点坐标异常时自动回退到鼠标位置。  
  Cursor assistant popup now positions by the actual target screen and falls back to mouse position when caret coordinates are unreliable.
- **主面板切换更稳定**  
  主面板弹出后加入短暂保护窗口，减少焦点抖动导致的瞬时关闭。  
  Added a short protection window after showing the main panel to reduce accidental instant close from focus jitter.
- **横板队列布局更紧凑**  
  横板队列栏高度调整为 33，避免挤压卡片底部内容；竖板保持原有高度。  
  Horizontal queue bar height is adjusted to 33 to avoid compressing card bottoms, while vertical layout keeps previous height.
- **AI 流式输出容错增强**  
  对超时、429、5xx 等临时错误增加自动退避重试，并在重试中保留上下文与工具链路。  
  Added backoff retries for transient errors (timeouts, 429, 5xx) while preserving conversation context and tool flow across retries.

### 变更 / Changes
- **数字快捷键修饰键可自选**  
  `1-9` 快捷键不再固定为 Command，可按偏好切换为 Command / Option / Control。  
  `1-9` shortcuts are no longer hardcoded to Command and can now use Command / Option / Control.
- **录制期间的全局行为调整**  
  快捷键录制期间会暂停全局热键、暂停 Option 双击监听，并放行模拟输入相关事件。  
  During shortcut recording, global hotkeys and Option double-click listening are paused, and simulated-input-related events are passed through.
- **更新来源与安全默认值调整**  
  更新与日志上传后端地址已更新；更新源改为仅走 Worker，代码签名校验默认开启。  
  Update and log-upload backend URLs were updated; updates now use Worker-only source with code signature enforcement enabled by default.
- **列表置顶同步策略调整**  
  置顶操作会同步更新最近缓存，保证主面板与光标助手看到一致顺序。  
  Move-to-top now also syncs recent cache so main panel and cursor assistant share the same ordering.
- **剪贴板搜索片段策略调整**  
  工具返回的片段增加长度上限与打码处理，减少敏感信息暴露风险。  
  Clipboard search snippets now apply length limits and masking to reduce sensitive data exposure risk.

### 修复 / Fixes
- **OAuth 回调重复参数崩溃**  
  修复重复 query key 触发的运行时崩溃问题，改为稳定覆盖逻辑。  
  Fixed runtime crash caused by duplicate OAuth query keys by switching to stable overwrite behavior.
- **插件覆盖安装中途失败风险**  
  修复覆盖安装时可能丢失旧数据的问题，失败时可回滚到安全状态。  
  Fixed potential data loss during overwrite install by adding safe replacement and rollback behavior.
- **授权请求悬挂问题**  
  修复会话切换后授权仍悬挂的问题，取消路径已统一收口。  
  Fixed hanging approval requests after conversation switches by unifying cancellation handling.
- **流式结果半截误判完成**  
  修复流提前断开时被当作完成的问题，未收到完成态会自动重试。  
  Fixed premature stream close being treated as completion; missing completion state now triggers retry.
- **存储整理相关稳定性问题**  
  修复 Swift 6 主线程隔离报错与整理报告参数不匹配问题。  
  Fixed Swift 6 MainActor isolation errors and maintenance report argument mismatch issues.
- **更新失败兜底恢复**  
  修复更新失败后的回退流程，失败时可拉回旧版本应用。  
  Fixed fallback recovery path after failed updates to restore previous app version.

### 说明 / Notes
- **多语言文案补全**  
  新增的 16 条文案已补齐 7 种语言，并完成结构有效性校验。  
  All 16 newly added strings were completed in 7 languages and validated for structure integrity.

### 兼容性与行为说明 / Compatibility & Behavior Notes
- **录制时全局触发暂不可用**  
  这是为了防止误触，录制结束后会自动恢复。  
  This is intentional to prevent accidental triggers; all related global actions auto-resume after recording ends.
- **更新校验更严格**  
  若同版本但 SHA 不一致会直接拒绝更新；若检测到新版本会提示你重新确认。  
  Updates are now stricter: same version with different SHA is rejected, and newly detected versions require a fresh confirmation.
- **二进制瘦身可能请求系统授权**  
  仅在执行需要权限的清理动作时才会触发管理员授权。  
  Admin permission is requested only when cleanup actions require elevated system access.

### 升级建议 / Upgrade Notes
- **升级后建议检查两处设置**  
  建议先在「设置 > 快捷键」确认数字快捷键修饰键，再在「设置 > 存储」确认二进制瘦身开关是否符合你的使用习惯。  
  After upgrading, review shortcut modifier settings in "Settings > Shortcuts" and binary slimming toggles in "Settings > Storage" to match your preference.

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

  - **智能规则能力大升级**
    动作类型升级为菜单结构，新增“转换”和“脚本插件”二级菜单，规则保存与执行全面兼容新旧值。
    Smart Rules received a major upgrade, with action types moved to menus and new "Transform" and "Script Plugin" submenus, while save/execute now fully support both new and legacy values.
  - **竖版模式正式可用**
    支持竖版停靠方向（靠左/靠右），并联动搜索规则弹窗、卡片预览、底部区域和交互布局。
    Vertical mode is now fully available, including left/right docking and coordinated behavior across search rule popup, card preview, bottom area, and overall interactions.
  - **插件体系更快更稳**
    脚本插件支持热更新、防抖刷新、缓存加速与监听策略优化，减少闪烁和重复重载。
    The plugin system is now faster and more stable, with hot reload, debounced refresh, caching improvements, and optimized watchers to reduce flicker and repeated reloads.
  - **导出与数据安全更可靠**
    导出改为“临时写入 + 原子替换”，并修复多项迁移/加密/握手/任务清理等高风险问题。
    Export and data safety are now more reliable through "staging write + atomic replace" and fixes for multiple high-risk paths such as migration, encryption, handshake, and task cleanup.
  - **预览与计算体验明显优化**
    预览改异步，智能计算提速提准，缓存一致性更好，减少卡顿与结果延迟。
    Preview and smart calculation are significantly improved with async preview, faster and more accurate computation, and better cache consistency to reduce lag and stale results.
  - **UI 交互细节打磨到位**
    多图展示、标签菜单、焦点行为、设置页动画、对比度与间距等均有系统性优化。
    UI interaction details were polished end-to-end, including multi-image display, tag menus, focus behavior, settings-page animation, contrast, and spacing.

  ### 新增 / Added

  - **动作类型新增“转换”二级菜单**
    规则编辑时可直接悬停展开转换项并点击选择。
    Added a new "Transform" submenu under action type so users can hover to expand and click specific transforms directly.
    SmartRulesView.swift:889
  - **转换动作持久化升级为稳定码**
    选择“转换”后会保存为稳定码，避免语言切换导致规则失效，并兼容旧值。
    Transform actions are now persisted with stable codes, preventing breakage after language switches while still supporting legacy values.
    SmartRulesView.swift:971, SmartRuleService.swift:155, DeckDataStore.swift:1151
  - **动作菜单新增“脚本插件”二级选择**
    可直接选择已安装插件作为规则动作，同时打通模型编码/解析与执行链路。
    Added a "Script Plugin" submenu in action menu, allowing installed plugins to be selected directly with full model encode/decode and execution integration.
    SmartRulesView.swift:814, SmartRuleService.swift:136, DeckDataStore.swift:1136, ScriptPluginService.swift:658
  - **新增 ASCII 艺术动画条（6 种场景）**
    新增 idle/empty/newCopy/searching/tagSelected/dataRich 场景、字符级过渡、60fps 驱动和动态宽度渲染。
    Added an ASCII animation bar with six scenes, character-level transitions, 60fps timeline driving, and dynamic-width rendering.
    ASCIIArtBarView.swift
  - **SmartRules 页面新增“使用指南”区块**
    增加工作原理、条件说明、动作说明和实用小贴士，降低上手门槛。
    Added a "Usage Guide" block in SmartRules with workflow explanation, condition/action references, and practical tips for easier onboarding.
    SmartRulesView.swift, Localizable.xcstrings
  - **新增数据库“立即恢复”能力**
    设置页新增“立即恢复”按钮与确认弹窗，满足条件时可手动触发恢复。
    Added an "Immediate Restore" capability with a settings button and confirmation dialog, allowing manual restore when required conditions are met.
    DeckSQLManager.swift:2196, SettingsView.swift:2089, SettingsView.swift:2327, SettingsView.swift:2333, SettingsView.swift:2559, SettingsView.swift:2566
  - **新增竖版停靠设置（靠左/靠右）**
    竖版模式可自定义停靠方向，并联动规则弹窗与预览窗口自动在外侧展示。
    Added vertical dock-side settings (left/right), with rule popup and preview window automatically placed on the outer side accordingly.
    SettingsView.swift, MainWindowController.swift, MainViewController.swift, SearchRulePickerPanelController.swift, PreviewWindowController.swift, UserDefaultsManager.swift,
    Constants.swift, DeckViewModel.swift
  - **脚本插件热更新机制上线**
    启动后自动监听插件目录，脚本/manifest/目录变化会自动刷新，且保留手动刷新入口。
    Script plugin hot reload is now live: plugin directories are auto-watched on startup, changes auto-refresh, and manual refresh is still available.
    ScriptPluginService.swift:141, ScriptPluginService.swift:241, ScriptPluginService.swift:555, ScriptPluginService.swift:607, ScriptPluginService.swift:693

  ### Deck × Orbit

  - **CLI /clip 默认接入智能规则**
    默认由规则入口处理，支持继续按参数切回旧直存模式。
    `CLI /clip` now uses Smart Rules by default, while still allowing parameter-based fallback to legacy direct-save behavior.
    CLIBridgeService.swift:608, CLIBridgeService.swift:629, CLIBridgeService.swift:672
  - **CLI Bridge 示例与别名说明增强**
    增加标签名/标签ID写入、空结果状态检查，并补充 health / last / write 别名示例与放置说明。
    CLI Bridge examples and alias docs were expanded with tag name/id writing, empty-result status checks, and clearer `health / last / write` alias usage.
    CLIBridgeSettingsView.swift:109, CLIBridgeSettingsView.swift:119, CLIBridgeSettingsView.swift:124, CLIBridgeSettingsView.swift:132, CLIBridgeSettingsView.swift:167
  - **脚本插件“创建步骤”文档升级**
    引导步骤更详细，示例 manifest/脚本更完整，并新增实测步骤与建议。
    The script-plugin "creation steps" guide is now more complete, with richer manifest/script examples plus a real-test step and recommendations.
    ScriptPluginsSettingsView.swift:17, ScriptPluginsSettingsView.swift:28, ScriptPluginsSettingsView.swift:220, ScriptPluginsSettingsView.swift:224
  - **Cloudflare 更新代理后端优化**
    提升性能、稳定性、实时性、速度和并发能力。
    The Cloudflare update-proxy backend was optimized for better performance, stability, real-time behavior, speed, and concurrency.

  ### 优化 / Improvements

  - **导出流程改为“临时文件写入 + 原子替换”**
    避免中断留下半截 JSON，失败只清理临时文件，不再删用户已有备份。
    Export now uses "staging write + atomic replace" to prevent partial JSON leftovers, and failures only clean temporary files instead of deleting existing user backups.
    DataExportService.swift:108, DataExportService.swift:123, DataExportService.swift:163
  - **导出大数据性能优化**
    写盘改为缓冲批量写（1MB 阈值），批次从 500 调整为 200，降低内存压力。
    Large-data export performance was improved via buffered batch writes (1MB threshold), and batch size was reduced from 500 to 200 to lower memory pressure.
    DataExportService.swift:180, DataExportService.swift:201
  - **导出链路减少重复 IO**
    已加载完整数据时避免重复读 blob。
    Reduced duplicate I/O in the export pipeline by avoiding repeated blob reads when full data is already loaded.
    DataExportService.swift:220
  - **LS/PS 清洗热路径提速**
    U+2028/U+2029 常量静态复用，并加入快速预检，命中才替换。
    LS/PS sanitization hot path was accelerated by reusing static U+2028/U+2029 constants and adding a fast pre-check so replacement runs only when needed.
    DataExportService.swift:123, DataExportService.swift:165
  - **脚本插件执行性能优化**
    增加插件索引、脚本文本缓存、网络授权缓存；执行路径改为缓存优先；仅在需要时计算脚本哈希。
    Script-plugin execution performance was improved with plugin indexing, script-text caching, and network-permission caching; execution now prefers cache, and script hash is computed only when required.
    ScriptPluginService.swift:136, ScriptPluginService.swift:247, ScriptPluginService.swift:730, ScriptPluginService.swift:755, ScriptPluginService.swift:836, ScriptPluginService.swift:937,
    ScriptPluginService.swift:1231, ScriptPluginService.swift:1236, ScriptPluginService.swift:1452
  - **预览与即时计算性能优化**
    预览中的同步热点改异步，减少主线程压力；关闭即时计算时行为更准确。
    Preview and instant-calculation performance improved by replacing synchronous hotspots with async flow, reducing main-thread pressure and fixing behavior accuracy when instant calc is disabled.
    PreviewOverlayView.swift:16, PreviewOverlayView.swift:103, PreviewWindowController.swift:330, PreviewWindowController.swift:382, PreviewWindowController.swift:461,
    ClipItemCardView.swift:1738, SmartContentCache.swift:276
  - **数学识别与计算能力提升**
    提升预检效率，支持等式左侧计算、多个/嵌套 sqrt，并优化数字格式化性能。
    Math recognition and calculation were upgraded with faster pre-checks, support for left-side equation evaluation, multiple/nested `sqrt`, and improved number-formatting performance.
    SmartTextService.swift:1846, SmartTextService.swift:1882, SmartTextService.swift:1928, SmartTextService.swift:1999, SmartTextService.swift:2032
  - **智能缓存一致性优化**
    OCR/文本更新与设置切换时主动失效缓存，卡片/行视图任务联动文本与开关变化。
    Smart-cache consistency was improved by proactively invalidating cache on OCR/text updates and settings toggles, and by binding card/row tasks to text and switch changes.
    DeckDataStore.swift:1414, SettingsView.swift:1211, ClipItemCardView.swift:42, ClipItemCardView.swift:558, ClipItemRowView.swift:21, ClipItemRowView.swift:104
  - **竖版图片显示优化**
    图片严格限制在方形区域，按接近方图/宽图/竖图分别处理，避免冲出卡片。
    Vertical-mode image display was refined by strictly constraining images to a square area with separate handling for near-square, wide, and tall images.
    ClipItemRowView.swift:117, ClipItemRowView.swift:173
  - **多图展示体验优化**
    多图记录仅展示首图，新增数量角标与“还有 N 张图片”提示，并修复预加载跳过问题。
    Multi-image display was improved by showing only the first image, adding count badges and an "N more images" hint, and fixing premature preload skipping.
    ClipItemCardView.swift, Localizable.xcstrings
  - **竖版多图信息展示优化**
    仅在多图时显示“共 X 张”，放在竖版右侧信息区中间。
    In vertical mode, "Total X images" is now shown only for multi-image items and placed in the middle of the right info area.
    ClipItemRowView.swift:290
  - **设置页交互与过渡动画优化**
    去掉内容区偏移 hack，切换 tab（点击/键盘）不再带整页动画，过渡更稳。
    Settings-page interactions and transitions were refined by removing the content offset hack and disabling full-page animation on tab switching (click/keyboard).
    SettingsView.swift:184, SettingsView.swift:232, SettingsView.swift:270
  - **视觉细节优化**
    迁移按钮改 Tonal 风格；textTertiary 对比度提升；标签编辑输入框改为随输入自动延长。
    Visual details were polished with a Tonal migration button style, improved `textTertiary` contrast, and auto-expanding tag editor input fields.
    NewTagChipView.swift, EditingTagChipView.swift
  - **面板重开滚动体验优化**
    重新激活时强制回到首项，复用现有平滑滚动逻辑。
    Reopen scrolling experience was improved by forcing selection back to the first item on reactivation while reusing existing smooth-scroll logic.
    HistoryListView.swift:135

  ### 变更 / Changes

  - **竖版顶部与底部交互逻辑重构**
    竖版顶部移除设置/暂停/关闭/反馈；底部区域按队列模式与按钮栏二选一展示。
    Vertical-mode top/bottom interaction logic was reworked: top controls (settings/pause/close/feedback) were removed, and the bottom area now toggles between queue bar and button bar.
    TopBarView.swift:1155, HistoryListView.swift:110, TopBarView.swift:958
  - **竖版搜索态布局调整**
    搜索聚焦/有输入/规则面板打开时，右侧标签区自动收起，避免布局被撑开。
    Vertical search layout was adjusted so the right tag area auto-collapses when search is focused, has input, or rule panel is open, preventing horizontal stretch.
    TopBarView.swift:18
  - **竖版底部高度统一**
    按钮区和队列区统一为同一高度，移除偏移补丁，视觉对齐一致。
    Vertical bottom heights were unified: button area and queue area now share the same height, with offset hacks removed for consistent alignment.
    HistoryListView.swift:86, HistoryListView.swift:255, HistoryListView.swift:266
  - **竖版搜索框展开宽度调整**
    竖版搜索宽度接近吃满可用空间，横版行为不变。
    Expanded search width in vertical mode now nearly fills available space, while horizontal-mode behavior remains unchanged.
    TopBarView.swift:123
  - **搜索规则弹窗定位策略调整**
    竖版下弹窗改为主面板外侧显示，并加边界保护，不遮挡输入与列表。
    Search-rule popup positioning was adjusted for vertical mode to render outside the main panel with boundary protection, avoiding overlap with input and list.
    SearchRulePickerPanelController.swift:95, SearchRulePickerPanelController.swift:102
  - **标签右键菜单改为 NSMenu**
    保留编辑/共享分组/删除，并新增颜色圆点选择与状态反馈，点击即持久化。
    Tag right-click menu was migrated to `NSMenu`, keeping edit/share-group/delete and adding color-dot selection with state feedback and immediate persistence.
    TopBarView.swift:1568
  - **打开面板后的初始选中策略调整**
    改为优先保证首项选中；已在首项时不重复设置，避免二次闪动感。
    Initial selection after opening panel was adjusted to prioritize the first item, and skip redundant resets when already on first item to avoid secondary flicker.
    HistoryListView.swift:1271
  - **自动检查更新改为北京时间 3 次/天**
    调整为 04:00 / 12:00 / 20:00。
    Automatic update checks were changed to three runs per day in Beijing time: 04:00, 12:00, and 20:00.
    UpdateCoordinator.swift:18, UpdateCoordinator.swift:80
  - **插件监听策略改为“目录/文件分离掩码”**
    目录保留 .attrib，文件移除 .attrib，并关闭高频 watcher 日志。
    Plugin watcher strategy now uses separate masks for directories/files: `.attrib` is kept for directories, removed for files, and high-frequency watcher logs are disabled.
    ScriptPluginService.swift:155, ScriptPluginService.swift:159, ScriptPluginService.swift:634, ScriptPluginService.swift:643
  - **监听范围扩展到脚本目录全部一级目录**
    新增候选目录收集逻辑，避免新增插件目录初期遗漏刷新。
    Watch scope now includes all first-level script directories via new candidate-directory collection logic, preventing missed refresh for newly created plugin folders.
    ScriptPluginService.swift:681, ScriptPluginService.swift:695

  ### 修复 / Fixes

  - **清理欢迎页未使用字段与常量**
    删除未使用的 tint、icon/iconColor、颜色常量及结构体冗余字段。
    Removed unused fields/constants in Welcome page, including `tint`, `icon/iconColor`, and redundant struct fields.
    WelcomeView.swift:22, WelcomeView.swift:49, WelcomeView.swift:102, WelcomeView.swift:514, WelcomeView.swift:606
  - **修复异步日志漏写 await 导致的 6 个报错**
    已补齐异步调用，恢复编译与运行稳定性。
    Fixed six errors caused by missing `await` in async logging calls, restoring compile and runtime stability.
    DeckDataStore.swift:1148, DeckDataStore.swift:1176
  - **修复规则弹窗数字键映射错误**
    不再用连续减法推算，改为固定映射，解决 5/6 错位及 7/8/9/0 无响应问题。
    Fixed numeric key mapping in rule popup by replacing subtraction-based inference with fixed mapping, resolving 5/6 mismatch and no-response on 7/8/9/0.
  - **修复搜索框抢焦点问题**
    焦点切到 .newTag/.editTag 时，跳过延迟 makeFirstResponder(nil)。
    Fixed search box focus stealing by skipping delayed `makeFirstResponder(nil)` when focus moves to `.newTag`/`.editTag`.
  - **修复新标签默认选中问题**
    新建标签时先确保拿到焦点，再自动全选“新标签”文字。
    Fixed default selection behavior for new tags by ensuring focus is obtained first, then auto-selecting the "新标签" text.
  - **修复粘贴后误吞下一次复制**
    改为只在“刚写入那次 changeCount”内跳过，不再无条件吞掉真实复制。
    Fixed accidental swallowing of the next real copy after paste by limiting skip behavior to the exact just-written `changeCount`.
    ClipboardService.swift:25, ClipboardService.swift:261, ClipboardService.swift:1645
  - **修复粘贴失败引发的剪贴板丢失风险**
    快照恢复支持更大预算和图片类型，恢复函数返回成功/失败并记录错误。
    Reduced clipboard-loss risk on paste failure by expanding snapshot restore budget/type coverage and returning explicit success/failure with error logs.
    ClipboardService.swift:1469, ClipboardService.swift:1514, ClipboardService.swift:1654
  - **修复加密迁移“假成功”问题**
    blob 迁移与 blob_path 更新改为强校验，任何一步失败都会整体失败。
    Fixed false-positive success in encryption migration by enforcing strict validation for blob migration and `blob_path` update, failing as a whole on any step error.
    DeckSQLManager.swift:5403, DeckSQLManager.swift:5425, BlobStorage.swift:178
  - **修复解密失败却写成明文状态的问题**
    解密分支新增严格检查，解不开直接失败，不再写 is_encrypted=false 假状态。
    Fixed incorrect plaintext state marking after decrypt failure: decryption branch now strictly checks and fails directly without writing fake `is_encrypted=false`.
    DeckSQLManager.swift:5245, DeckSQLManager.swift:5299
  - **修复 DirectConnect authSuccess 阶段绕过**
    增加 pendingAuthSuccess 阶段校验，仅在合法阶段接受成功握手。
    Fixed DirectConnect `authSuccess` phase bypass by adding `pendingAuthSuccess` state validation and accepting success handshake only in legal phases.
    DirectConnectService.swift:333, DirectConnectService.swift:980, DirectConnectService.swift:1025
  - **修复 Multipeer verify_success 绕过**
    必须存在活跃验证上下文才接受验证成功。
    Fixed Multipeer `verify_success` bypass by requiring an active verification context before accepting success.
    MultipeerService.swift:1541
  - **修复 Keychain 临时错误误建新密钥**
    仅 errSecItemNotFound 才创建新 key，其他错误直接上抛。
    Fixed unintended key regeneration on temporary Keychain errors: only `errSecItemNotFound` creates a new key, all other errors are returned directly.
    SecurityService.swift:111, SecurityService.swift:145, SecurityService.swift:177
  - **修复清空数据后旧任务回写 UI**
    clearAllData/clearAll 增加统一取消在飞任务入口。
    Fixed stale task write-backs after data clearing by adding a unified in-flight task cancellation entry for `clearAllData/clearAll`.
    DeckDataStore.swift:1441, DeckDataStore.swift:1518, DeckDataStore.swift:1721
  - **修复 stop() 未清空 streamStore**
    已补 streamStore.clearAll()。
    Fixed `stop()` not clearing `streamStore` by adding `streamStore.clearAll()`.
    DirectConnectService.swift:275, DirectConnectService.swift:544
  - **修复 deleteItemById 链路不完整**
    补齐 blob 清理与 totalCount 刷新。
    Fixed incomplete `deleteItemById` path by adding blob cleanup and `totalCount` refresh.
    DeckDataStore.swift:1764
  - **修复 blob 路径收集漏删风险**
    分页从 offset 改 cursor，并补稳定排序 ts desc, id desc。
    Fixed blob-path collection deletion risk by switching pagination from offset to cursor and adding stable sorting (`ts desc, id desc`).
    DeckDataStore.swift:1809, DeckSQLManager.swift:4378
  - **修复编译错误（await 放在 ?? 表达式内）**
    改为两步赋值，消除编译失败。
    Fixed compile error from placing `await` inside `??` expression by splitting into two-step assignment.
    DeckDataStore.swift:1764
  - **修复 Cmd+Q 提示文案语义错误**
    “光标助手功能”统一改为“队列模式功能”，并补齐多语言。
    Fixed Cmd+Q prompt wording by replacing "Cursor Assistant feature" with "Queue Mode feature" consistently across languages.
    Localizable.xcstrings:25502
  - **修复多处潜在崩溃（强解包/异常元素/空屏幕）**
    增加类型校验与 guard 兜底，移除 fatalError 风险路径。
    Fixed multiple potential crashes (force unwraps, abnormal elements, empty screen) by adding type checks and `guard` fallbacks, and removing risky `fatalError` paths.
    IDEAnchorService.swift:401, OrbitWindow.swift:74, OrbitWindow.swift:102, OrbitWindow.swift:149, OrbitWindow.swift:156, DeckDataStore.swift:1420, MainWindowController.swift:69,
    SettingsWindowController.swift:57, UpdatePromptWindowController.swift:34
  - **修复进程管道可能死锁问题**
    改为运行时持续读取 stdout/stderr，并在 wait 前正确关闭写端。
    Fixed potential process-pipe deadlocks by continuously reading stdout/stderr during execution and correctly closing write ends before waiting.
    LANFileArchiver.swift:324, IDEAnchorService.swift:575, OrbitInstaller.swift:192
  - **修复列表行编译/API 对接问题**
    修正 item.colorValue、缩略图生成、智能分析赋值、脚本插件调用与隐写 API 调用。
    Fixed row-view compile/API integration issues, including `item.colorValue`, thumbnail generation, smart analysis assignment, script-plugin calls, and steganography API usage.
    ClipItemRowView.swift

  ### 说明 / Notes

  - **本版本文案多语言已补齐**
    新增/更新文案覆盖 de/en/fr/ja/ko/zh-Hans/zh-Hant。
    Localization coverage was completed for new/updated strings across de/en/fr/ja/ko/zh-Hans/zh-Hant.
    Localizable.xcstrings:19297, Localizable.xcstrings:22815, Localizable.xcstrings:2944, Localizable.xcstrings:50219, Localizable.xcstrings:55241, Localizable.xcstrings:45788,
    Localizable.xcstrings:45835, Localizable.xcstrings:45882, Localizable.xcstrings:44852, Localizable.xcstrings:44899
  - **部分语种文案做了母语化重写**
    de/fr/ja/ko 的新增长文案改为更自然表达，脚本设置页长文本改为 NSLocalizedString。
    Some language content was rewritten with native phrasing (de/fr/ja/ko), and long script-settings text now uses `NSLocalizedString`.
    Localizable.xcstrings, ScriptPluginsSettingsView.swift
  - **本稿已完成路径脱敏**
    所有位置引用均仅保留 文件名:行号，不含任何绝对路径信息。
    This draft is path-sanitized: all references keep only `filename:line` without any absolute path information.

  ### 兼容性与行为说明 / Compatibility & Behavior Notes

  - **规则转换兼容新旧存储值**
    transform 同时兼容“稳定码 + 历史旧值”，展示与执行都可回溯兼容。
    Transform rules are compatible with both new stable codes and legacy values in both display and execution paths.
  - **CLI /clip 保持双行为兼容**
    默认走规则；raw=1 或 rules=0 可强制直存；rules=1 可显式开启规则。
    `CLI /clip` keeps dual behavior compatibility: rules by default, force direct-save with `raw=1` or `rules=0`, and explicit enable via `rules=1`.
  - **插件刷新支持“自动 + 手动”并存**
    自动监听持续生效，手动“刷新插件列表”按钮仍保留可用。
    Plugin refresh supports both automatic and manual modes: directory watching remains active, and manual "Refresh Plugin List" is still available.
  - **“立即恢复”带双重保护**
    必须同时满足“自动维护恢复备份已开启 + 恢复备份文件存在”才可执行。
    "Immediate Restore" uses dual safeguards and can run only when auto-maintenance restore backup is enabled and a restore backup file exists.

  ### 升级建议 / Upgrade Notes

  - **建议升级后优先检查智能规则**
    重点确认“转换动作”和“脚本插件动作”在你当前规则集中的展示与执行结果。
    After upgrading, prioritize validation of Smart Rules, especially how "Transform" and "Script Plugin" actions display and execute in your current rule set.
  - **若有外部 CLI 依赖旧直存行为**
    请在调用端显式加 raw=1 或 rules=0，避免行为变化影响自动化脚本。
    If external CLI workflows depend on legacy direct-save behavior, explicitly pass `raw=1` or `rules=0` to avoid automation regressions.
  - **建议升级后验证竖版布局偏好**
    可按使用习惯选择“靠左/靠右停靠”，并确认搜索弹窗与预览窗口位置符合预期。
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
- **快捷键交互更安全**  
  队列模式切换改为 `Option + Q`，面板内 `Command + Q` 会先弹出确认，减少误关应用。  
  Queue mode now uses `Option + Q`, and `Command + Q` in-panel now asks for confirmation to reduce accidental app exits.
- **触发键能力升级**  
  设置页新增“自定义触发键”，支持一键录制与清空，并和原有预设触发键并行生效。  
  A new custom trigger key can be recorded or cleared in Settings, and it works alongside the existing preset trigger key.
- **搜索与统计更流畅**  
  搜索采用自适应防抖，统计页改为后台并发计算并加入格式化缓存，整体响应更快。  
  Search now uses adaptive debounce, while Statistics runs concurrent background computation with formatter caching for faster response.
- **Apple 链接识别更准确**  
  Apple Music/Podcasts 识别规则加强，`apple.co` 会先等待元数据确认后再决定展示样式。  
  Apple Music/Podcasts detection is more accurate, and `apple.co` now waits for metadata confirmation before layout selection.
- **稳定性修复**  
  修复了链接预览和统计任务中的多处状态与并发问题，降低卡住或异常风险。  
  Multiple state and concurrency issues in link preview and statistics were fixed to reduce stuck states and runtime errors.

### 新增 / Added
- **自定义触发键**  
  触发键设置下新增“自定义触发键”，点击后按一次组合键即可保存，右侧支持一键清空。  
  Added a custom trigger key option: click to record one shortcut combo, with one-tap clear support.
- **双触发模式并行可用**  
  保留原有预设触发键逻辑的同时，自定义组合键也可单次触发，且会持久化保存。  
  Preset trigger behavior remains, while custom shortcut combos can also trigger actions and are persisted.

### 优化 / Improvements
- **搜索防抖策略自适应**  
  清空搜索时立即响应；大数据量或安全模式下自动延长防抖时间，兼顾速度与稳定。  
  Search now responds instantly on clear and automatically extends debounce under heavy data/safe mode for better balance.
- **搜索框动画节奏优化**  
  展开/收起动画节奏更干脆，同时移除全局动画副作用，交互更自然。  
  Expand/collapse animation timing is tighter, and global animation side effects were removed for cleaner interaction.
- **统计页性能优化**  
  统计计算迁移到后台并发执行，并复用格式化器，降低主线程压力与重复开销。  
  Statistics processing now runs concurrently in the background with formatter reuse to reduce main-thread pressure.
- **Apple 媒体元数据匹配优化**  
  Apple Music 优先按 track 精确匹配，再按 collection 回退；播客摘要文本也减少重复信息。  
  Apple Music now prioritizes track-level matching with collection fallback, and podcast summaries avoid duplicated details.

### 变更 / Changes
- **队列模式快捷键调整**  
  队列模式切换快捷键从 `Command + Q` 调整为 `Option + Q`。  
  Queue mode toggle shortcut changed from `Command + Q` to `Option + Q`.
- **面板内退出流程调整**  
  在面板内按 `Command + Q` 时，现改为先弹出“确认关闭”提示。  
  Pressing `Command + Q` in the panel now shows a close-confirmation prompt first.
- **Apple 流媒体样式触发条件调整**  
  `apple.co` 链接不再直接套用 Apple 流媒体样式，而是等待元数据确认后决定。  
  `apple.co` links no longer force Apple streaming layout immediately and now wait for metadata confirmation.

### 修复 / Fixes
- **链接预览加载状态卡住**  
  修复任务取消或页面消失后 `isLoading` 可能无法复位的问题，避免卡在 loading。  
  Fixed cases where `isLoading` could remain stuck after task cancellation or view disappearance.
- **URL 误判问题**  
  URL 解析规则收紧，减少将普通文本（如 `podcast:true`）误识别为链接的情况。  
  Tightened URL parsing to reduce false positives where plain text (for example `podcast:true`) was misdetected as a URL.
- **统计任务并发隔离问题**  
  修复统计页在后台任务中的主线程隔离调用问题，避免并发上下文报错。  
  Fixed main-thread isolation issues in statistics background tasks to avoid concurrency-context errors.

### 兼容性与行为说明 / Compatibility & Behavior Notes
- **快捷键行为提醒**  
  如果你习惯用 `Command + Q` 触发队列模式，请改用 `Option + Q`。  
  If you used `Command + Q` for queue mode before, please switch to `Option + Q`.

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
- **复制提示音已更新**  
  复制成功时的提示音已替换为新的音效，整体听感更清晰。  
  Replaced the copy-success sound with a new effect for a clearer confirmation cue.
- **Apple Music / Podcasts 链接预览增强**  
  链接卡片展示封面、标题、作者、发布时间与时长，支持 RSS 链接。  
  Link previews for Apple Music and Podcasts now show artwork, metadata, and RSS links.
- **Apple Music / Podcasts 预览视觉优化（仅这两类）**  
  仅针对 Apple Music / Podcasts 调整预览：底部空白区域缩减、链接超长截断（50 字符）、文本颜色根据封面亮暗自动切换。  
  Apple Music/Podcasts-only visual polish: reduced blank space, 50-char URL truncation, and auto contrast text color.
- **预览性能与体验优化**  
  大文本不截断、代码语法高亮优化、图片预览更高清。  
  Preview improvements: non-truncated text, optimized code highlighting, higher-resolution images.
- **预览回归问题修复**  
  修复图片预览无法最大显示、预览区留白，以及代码预览中的状态更新警告。  
  Fixed image preview sizing/padding regression and state-update warnings in code preview.
- **链接卡片网站图标放大**  
  链接记录预览中的网站 favicon 从 42x42 调整为 52x52，更易识别。  
  Increased website favicon in link record previews from 42x42 to 52x52 for better visibility.

### 变更 / Changes
- **默认复制音效调整**  
  默认复制提示音从原有音效调整为新音效，反馈更直接。  
  The default copy cue has been switched to a new sound for more direct feedback.
- **Apple Music / Apple Podcasts 元数据**  
  - 链接预览展示封面图、标题、作者、发布时间、时长  
  - 支持 apple.co 短链解析  
  - 支持 RSS 源链接  
  Apple Music/Podcasts link previews with artwork, metadata, and RSS support.
- **Apple Music / Apple Podcasts 预览样式优化（仅这两类）**  
  - 仅对 Apple Music / Podcasts 生效，普通链接预览保持原样  
  - 预览内容区域底部空白缩减约 `1/5`（不影响底部信息栏位置）  
  - 链接显示增加 `50` 字符限制，超出部分以 `...` 截断  
  - 标题/来源/链接文字颜色根据封面亮度自动切换，提升深浅封面下可读性  
  - “打开 RSS” 入口整合至底部信息栏（与二维码/类型/大小同一行）  
  Apple Music/Podcasts-only preview style updates: reduced bottom blank area, 50-char URL truncation, adaptive text contrast, and RSS action moved to the footer bar.
- **剪贴板与预览优化**  
  - 支持 `public.url` 类型，Safari/Notes/Music 等应用的链接可正确识别  
  - 链接记录预览中的网站 favicon 从 `42x42` 调整为 `52x52`，更易识别  
  - 预览窗口图片使用高分辨率解码，显示更清晰  
  - 大文本预览不截断（硬上限 200 万字符），支持 Cmd+F 搜索  
  - 代码预览使用 TextKit，不截断，超长代码时禁用语法高亮以保持流畅  
  Clipboard and preview: public.url support, high-res images, non-truncated text/code.
- **预览问题修复 / Preview Fixes**  
  - 修复单图预览被固定高度限制的问题，图片现在会尽量占满可用预览区域（保持比例）  
  - 修复单图预览外层内边距导致的额外留白，图片可在不裁切前提下最大显示  
  - 修复 `SmartContentView` 中 “Modifying state during view update” 警告，避免不确定刷新行为  
  - 拆分 `PreviewWindowContent` 复杂视图表达式，修复 “The compiler is unable to type-check this expression in reasonable time” 编译错误  
  - 修复 `frame` 参数写法导致的 “Extra argument 'height' in call” 编译错误  
  Fixed single-image previews being height-capped and resolved the SwiftUI "Modifying state during view update" warning in `SmartContentView`.
- **设置稳定性修复 / Settings Stability Fix**  
  修复在设置页切换“模拟键盘输入粘贴”开关时，因并发访问导致的崩溃问题。  @Wcowin
  Fixed a crash caused by simultaneous access when toggling "Paste by Typing" in Settings.

- **多语言完整补齐（真实翻译） / Localization Completion (Real Translations)**  
  - 已将 `Deck/Resources/Localizable.xcstrings` 中缺失的 `de / en / fr / ja / ko / zh-Hans / zh-Hant` 条目补齐到 `0` 缺口。  
  - 覆盖范围包括：更新提示、数据库健康状态、脚本插件默认名称与描述、错误提示、触发词引导、上传分析说明、图片/文件预览文案等。  
  - 本次补齐为真实译文，不是仅补空条目占位。  
  Completed all missing translations in `Deck/Resources/Localizable.xcstrings` to zero gaps across `de/en/fr/ja/ko/zh-Hans/zh-Hant`, including update/database/script/error/onboarding/preview strings with real translated text.

- **代码国际化改造 / i18n Code Refactor**
  - `Deck/Services/ScriptPluginService.swift`：默认脚本名称/描述、执行错误、超时提示等改为 `NSLocalizedString`。  
  - `Deck/Services/DeckSQLManager.swift`：数据库健康检查与安全模式错误提示改为本地化文案。  
  - `Deck/Models/ClipboardItem.swift`：图片/文件/链接/颜色等描述文案改为本地化文案。  
  Added localization lookups in `ScriptPluginService`, `DeckSQLManager`, and `ClipboardItem` for user-facing strings.

- **多语言资源收敛 / Localization Resource Cleanup**
  - 统一以 `Localizable.xcstrings` 作为多语言来源。  
  - 不再使用额外的 `Localizable.strings` 占位方案。  
  Standardized localization on `Localizable.xcstrings` only (no placeholder `.strings` files).

### 升级建议 / Upgrade Notes
- **建议更新后试听确认**  
  更新后可复制一段文本做一次试听，确认音量和听感符合你的习惯。  
  After upgrading, copy a short text once to confirm the new volume and tone fit your preference.

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
- **连接拒绝与重试**：拒绝/超时后立即显示"已拒绝"，冷却倒计时"X后重试"，冷却结束后需手动点击"重试"才再次连接。  
  Connection: immediate "Rejected" on decline/timeout; cooldown countdown; manual retry only after cooldown.

- **安装体验**：DMG 提供 `Deck Installer Tools` 文件夹，`install.command` 一键安装并清理隔离属性，`help.txt` 多语言说明，图标随系统明暗切换。  
  Install: single tools folder, one-click install with quarantine cleanup, multi-language help, auto dark/light icon.

- **Orbit 精简**：聚焦环形应用切换演示，移除黑洞/拖拽/Caps Lock 等路径，代码瘦身，交互更稳定。  
  Orbit: radial app-switching only; removed drag/black-hole paths; code cleanup; more stable.

- **传输与连接**：大内容改走资源/流式传输；直连支持多端口回退；单条共享同步标签；资源与清单乱序到达可正确处理；直连标签改用真实 ID。  
  Transfer: resource/stream for large payloads; multi-port fallback; tag sync on share; out-of-order resource/manifest handled; real tag IDs for direct connect.

- **关键修复**：标签接收后即时刷新；TOTP 验证码实时轮换，减少校验失败。  
  Fixes: tag list refreshes on receive; TOTP live-rotating to reduce verification failures.

- **Welcome 体验优化**：欢迎页圆角和按钮配色已优化，左侧文案切页更稳定；无可迁移内容时自动跳过第 7 页（6 直接到 8）。  
  Welcome onboarding polish: corner/button colors are refined with steadier text transitions, and page 7 is auto-skipped when no importable data is found (6 goes directly to 8).


### 新增 / Added
- **新增标签拖拽排序功能**  
  在弹出面板（⌘P）中，按住 Command 键后拖动标签即可自定义排列顺序。所有标签（系统标签与用户自定义标签）均支持拖拽排序，顺序会自动保存。  
  In the popup panel (⌘P), hold Command and drag any tag to reorder. All tags (system and user-defined) support drag reordering, and the order is persisted automatically.  

  - 拖拽时标签仅在水平轴移动，纵向位置锁定  
    Tags move only horizontally during drag; vertical position is locked.  
  - 标签完全跟随鼠标位置，无加速度或惯性  
    Tags follow the cursor exactly with no acceleration or inertia.  
  - 左右边界严格限制，标签不会超出显示区域  
    Left/right boundaries are strictly enforced; tags cannot exceed the visible area.  
  - 拖拽中释放 Command 键会取消操作并恢复原始顺序  
    Releasing Command during drag cancels the operation and restores the original order.  
  - 被拖拽标签有轻微放大和阴影效果，便于区分当前操作目标  
    The dragged tag shows a subtle scale-up and shadow effect for visual distinction.  
  - 拖拽标签与其他标签重叠时，被覆盖的标签会自动虚化（降低透明度），视觉层级更清晰  
    When the dragged tag overlaps another tag, the overlapped tag fades out (reduced opacity) for clearer visual hierarchy.  

- **新增安装工具文件夹结构**  
  原先分散的脚本改为统一收纳到 `Deck Installer Tools`，默认包含 `install.command` 与 `fix.command`。  
  Standalone scripts are now grouped into `Deck Installer Tools`, including `install.command` and `fix.command`.  

- **粘贴队列 HUD 胶囊支持拖拽并自动记忆位置**  
  右下角的粘贴队列 HUD 胶囊现在可以用鼠标拖拽到屏幕任意位置，位置会自动保存。鼠标悬停时显示小手光标提示可拖动，即使 App 不在前台也能正常显示。  
  The paste queue HUD capsule at the bottom-right can now be dragged to any position on screen. The position is automatically saved and restored. An open-hand cursor appears on hover to indicate draggability, even when the app is in the background.  

- **新增多语言帮助文档 `help.txt`**  
  帮助文档覆盖当前 App 支持语言，并明确“脚本用途 + 双击运行步骤”。  
  The new `help.txt` covers all currently supported app languages and explains script purpose plus double-click run steps.  

- **新增 LAN 文件归档工具 `LANFileArchiver`**  
  新增统一打包、解包、临时文件认领和清理能力，专门用于局域网资源传输路径。  
  Added `LANFileArchiver` for archiving, extraction, temp-resource claiming, and cleanup in LAN transfer flows.  

- **新增直连流式传输链路（大内容）**  
  直连模式新增 `stream_start / chunk / stream_end` 传输链路，用于大内容和文件归档发送。  
  Added a direct-connect streaming path (`stream_start / chunk / stream_end`) for large payload and archived file transfer.  

- **新增资源清单机制（Multipeer）**  
  新增 `resource_manifest` 元信息通道，在资源到达后可准确还原内容类型、时间、应用名和标签信息。  
  Added a `resource_manifest` metadata channel in Multipeer so type, timestamp, app name, and tag metadata are restored correctly after resource transfer.  

### 优化 / Improvements
- **Welcome 引导页细节优化**  
  圆角调整为 30pt，浅色模式下右侧按钮图标/文字改为黑色，切页观感更稳定。  
  Welcome refinements: 30pt corner radius, black right-side button text/icons in light mode, and steadier page transitions.  

- **首次启动引导页全面重设计**  
  引导页改为左右分栏沉浸式布局，左侧文字右侧配图。图片贴合右下角裁切露出局部。窗口改为无边框无红绿灯按钮，极简黑白风格，适配 Light/Dark Mode。导航按钮叠加在图片区底部，所有按钮统一使用毛玻璃材质。每页图片中央叠加对应 SF Symbol 动画图标（macOS 15+）。  
  Welcome view redesigned with a left-right split layout. Images are anchored bottom-right with overflow clipping. Borderless window with no traffic lights, minimalist black-and-white scheme, Light/Dark adaptive. Navigation buttons overlaid on the image panel with frosted glass material. Each page displays an animated SF Symbol overlay on the image (macOS 15+).  

- **菜单栏图标重绘**  
  图标改为 `document.on.clipboard`，默认单色渲染，暂停时使用分层渲染以区分状态。复制内容入库时触发 `.symbolEffect(.bounce.up.byLayer)` 动画，反馈更直观。  
  Menu bar icon now uses `document.on.clipboard`, with monochrome by default and hierarchical rendering when paused. Copy events trigger a bounce-up symbol effect for clearer feedback.  

- **菜单栏右键菜单增强**  
  顶部图标右键菜单新增“反馈意见”入口（与面板“告诉我们您的想法”一致，打开邮件并使用反馈 HTML 模板）；在“偏好设置...”与“退出 Deck”之间新增版本与更新分组，显示“版本 X.X.X”并提供“检查更新”，点击后复用“关于”页手动检查更新流程，检测到新版本会弹出更新窗口。  
  The status-bar icon context menu now includes a Feedback entry (same behavior as “Tell us your thoughts”, opening email with the HTML feedback template). A version/update section was also added between Preferences and Quit, showing “Version X.X.X” and a “Check for Updates” action that reuses the About page’s manual update-check flow and presents the update prompt window when a newer version is found.  

- **TagChips 顶栏布局与按钮状态优化**  
  标签栏改为更符合直觉的分布：添加标签按钮（+）和新建标签编辑器紧贴标签区内最后一个标签右侧；设置、暂停/恢复、退出和反馈按钮保留在右侧。相关按钮默认无背景，鼠标悬停时才显示高亮效果（与搜索按钮风格一致）。  
  Tag bar layout is now more intuitive: the Add Tag (+) button and new-tag inline editor sit inside the tag area directly after the last tag, while settings, pause/resume, quit, and feedback stay on the right. These controls are now transparent by default and show highlight only on hover, matching the search-button behavior.  

- **设置窗口侧边栏右侧圆角优化**  
  设置窗口左侧导航栏的右上角和右下角添加了圆角效果，侧边栏与右侧内容区之间的过渡更柔和，同时移除了原先的 1px 直线分隔线，改为右侧方向的柔和阴影分层。内容区域向左延伸填充圆角间隙，确保白色背景页面（如 Orbit）不会在圆角处露出灰色底色。  
  The right-top and right-bottom corners of the settings sidebar now have rounded corners for a softer transition between the sidebar and content area. The previous 1px straight divider line has been replaced with a subtle rightward shadow for depth. The content area extends slightly behind the sidebar to fill rounded-corner gaps, ensuring pages with white backgrounds (e.g. Orbit) don't expose gray corners.  

- **统计页面 UI 全面重设计**  
  统计页面采用极简风格重新设计：概览数据合并为单一卡片并加入千分位格式化；数据安全提示精简为标题旁的小胶囊标记；内容类型分布新增右侧图例列表显示百分比；常用应用每行加入水平进度条与百分比显示；7 天活动柱状图细化为窄柱大圆角渐变填充；存储信息融入概览卡片底部。  
  The statistics page has been redesigned with a minimalist style: overview stats merged into a single card with number formatting; the data security notice is now a compact capsule badge; type distribution chart now has a side legend with percentages; top apps rows feature inline progress bars with percentage display; the 7-day activity chart uses narrower bars with gradient fills; storage info is integrated into the overview card footer.  

- **模版库使用提示和描述优化**  
  模版库页面标题旁增加了"光标助手"胶囊标记，明确表示模版库是配合光标助手使用的功能。副标题和使用提示卡片重新编写，采用分步骤引导的形式清晰说明创建模版、设置触发词和快速调用的完整流程。  
  A "Cursor Assistant" capsule badge is now shown next to the Template Library title, clarifying its purpose. The subtitle and usage tips card have been rewritten with a step-by-step guide format explaining the full workflow of creating templates, setting trigger words, and quick invocation.  

- **触发词添加弹窗 UI 优化**  
  触发词添加 Sheet 重新设计：顶部增加图标和说明文字；输入框改为自定义样式；匹配类型选择器从系统分段控件替换为自定义按钮组；类型选择网格改为水平布局，选中态更简洁；底部按钮区域点击范围扩大至整个区域。  
  The Add Trigger Word sheet has been redesigned: header now includes an icon and description; text field uses a custom style; match type selector replaced with custom tab buttons; type selection grid uses a horizontal layout with cleaner selection states; bottom button hit area now covers the full region.  

- **智能规则编辑页面 UI 优化**  
  编辑规则页面中"全部满足/任一满足"的匹配模式选择器从系统分段控件替换为自定义胶囊按钮组；条件和动作项改为带图标的卡片式行布局，视觉层级更清晰；添加条件/动作页面移除冗余空白，Sheet 高度改为自适应内容。  
  The Smart Rules editor UI has been refined: the "All/Any" match mode selector is replaced with custom capsule-style buttons; condition and action items now use card-like rows with icons for better visual hierarchy; the Add Condition/Action sheets remove excess whitespace with content-adaptive height.  

- **存储整理与自检 UI 优化**  
  "会做的事情"说明从纯文本换成带彩色图标的分行展示，每项操作一目了然；整理完成报告弹窗的标题居中并使用圆形图标背景，卡片标题改为小号大写字母，数值使用等宽圆角字体，关闭按钮改为自定义样式。  
  The maintenance description now uses icon-labeled rows instead of plain text; the report sheet header is centered with a circular icon background, card titles use small-caps style, metric values use rounded monospace font, and the close button has a custom style.  

- **安全设置页面 UI 优化**  
  隐写密钥口令输入框添加前置图标（锁/钥匙），密码文本改为等宽字体；保存和清除按钮改为带填充背景的胶囊样式；安全模式说明从 bullet list 改为带彩色图标的分行展示；OCR 识别语言列表的图标按语言差异化显示；存储信息末行移除多余的分隔线。  
  Steganography passphrase field now has a leading icon (lock/key) with monospaced font; save and clear buttons use capsule-style with fill backgrounds; security mode info uses icon-labeled rows instead of bullet list; OCR language icons are now differentiated per language; storage info section removes the trailing divider.  

- **代码示例增加语法高亮（脚本插件 / CLI Bridge）**  
  设置页中的脚本插件创建示例（`manifest.json`、`index.js`）和 CLI Bridge 命令示例已增加颜色渲染，便于快速区分关键字、字符串、数字、注释与变量。  
  Added syntax highlighting to settings code samples (Script Plugins and CLI Bridge), improving readability for keywords, strings, numbers, comments, and variables.  

- **连接状态反馈更清晰**  
  右侧状态提示补齐颜色和文案语义：冷却中为红色拒绝提示，冷却结束后显示蓝色可重试动作。  
  The right-side status feedback is clearer: red reject/cooldown messaging while waiting, then a blue retry action when ready.  

- **关于页面 UI 优化**  
  版本号改为胶囊标签样式；"核心功能"和"智能功能"合并为单一"功能概览"卡片；快捷键标签改为仿键盘键帽样式（圆角 + 微阴影 + 描边）；"更新"和"反馈"合并为一个卡片。  
  Version number now uses a capsule badge style; "Core Features" and "Smart Features" are merged into a single "Features Overview" card; shortcut badges now mimic keyboard keycaps (rounded corners + subtle shadow + border); "Updates" and "Feedback" are merged into one card.  

- **搜索栏重构为收起/展开模式**  
  默认状态仅显示放大镜图标（扁平设计、无投影、悬停圆形高光），点击或键盘输入后平滑展开为胶囊搜索栏（宽度 300pt），失焦且无查询内容时自动收起。保留全局键盘捕获、中文输入法兼容和 `/` 斜杠命令功能。标签栏紧邻搜索图标排列；点击搜索栏以外的内容区域可自动退出搜索状态（点击标签栏和规则选择器弹窗时不影响搜索）。  
  Search bar refactored to a collapse/expand pattern: shows only a magnifying glass icon by default (flat, no shadow, circular hover highlight); smoothly expands into a capsule search bar (300pt) on click or keyboard input; auto-collapses when blurred with empty query. Global keyboard capture, Chinese IME compatibility, and `/` slash command all preserved. Tag chips now sit directly next to the search icon; clicking the content area outside the top bar exits search mode (clicking tags or the rule picker popup does not).  

- **空状态图标更新**  
  弹出面板的三种空状态（标签无记录、剪贴板为空、未找到结果）图标从 `clipboard` 替换为 `doc.on.clipboard`，使用分层渲染模式（`.hierarchical`），深色/浅色模式自动适配。  
  The three empty-state icons in the popup panel (tag has no records, clipboard is empty, no results found) now use `doc.on.clipboard` with hierarchical symbol rendering, automatically adapting to light and dark mode.  

- **多语言文案同步更新**  
  新状态文案已补齐多语言翻译，连接提示在不同语言下保持一致表达。  
  The new status copy is fully localized, keeping connection feedback consistent across supported languages.  

- **系统提示与更新流程文案多语言补齐**  
  已将导入导出弹窗（成功/失败/数量提示）、生物识别验证默认文案与取消按钮、更新通知标题与正文、更新流程状态文案、辅助功能权限弹窗、iCloud 同步错误提示、Orbit 安装错误提示统一接入多语言。  
  Localized system-facing copy across export/import dialogs (success/failure/count), biometric auth defaults and cancel label, update notification title/body, updater status texts, accessibility permission dialogs, iCloud sync error messages, and Orbit installer error prompts.  

- **首次安装路径更顺滑**  
  新增安装脚本会在执行安装时自动处理隔离属性，尽量减少用户进入系统“隐私与安全性”手动放行的频率。  
  The new installer script now clears quarantine during installation to reduce manual Security & Privacy unblock steps.  

- **DMG 布局进一步整理**  
  `Deck.app` 与 `Applications` 保持主区域展示，安装工具文件夹固定放在其下方，首次安装路径更直观。  
  `Deck.app` and `Applications` remain in the main area, with the tools folder placed below for a clearer first-install flow.  

- **安装器视觉一致性增强**  
  安装器图标默认使用 1024 Logo，并支持明暗外观自动匹配。  
  The installer icon now uses the 1024 logo by default and adapts automatically to dark/light appearance.  

- **Orbit 演示界面视觉层级简化**  
  Orbit 环形演示移除了黑洞/AirDrop 指示层与拖拽消散链路，保留点击、悬停、键盘切换等核心交互。  
  Orbit demo visuals were simplified by removing black-hole/AirDrop overlays and drag-dissolve chains, while keeping click/hover/keyboard core interactions.  

- **接收缓冲与帧解析容错优化**  
  接收链路加入更清晰的单条消息上限与总缓冲上限，异常包会更早拦截，减少卡死和误解析。  
  Receive flow now enforces clearer per-message and total-buffer limits, rejecting bad payloads earlier to reduce stalls and misparsing.  

- **面板弹出/收起动画优化**  
  缩短动画时长（show 0.16s、hide 0.18s），展示时改用 easeOut 曲线，收起更干脆、展开收尾更柔和。  
  Panel show/hide animation shortened (0.16s / 0.18s) with easeOut on show for snappier close and gentler expand stop.  

- **快捷键连发与动画期间防抖**  
  对 ⌘P 等全局快捷键增加节流与按键释放检测，避免长按或快速连按导致面板闪烁、卡顿；动画进行中不再响应新的 toggle 请求。  
  Hotkey throttling and key-release detection added to prevent panel flash and jank from key-repeat or rapid presses; toggle requests are ignored during active animation.  

- **面板关闭后延迟清理**  
  面板关闭时不再立即执行 purgeMissingFileItems 和 clearExpiredData，改为延迟约 0.6 秒后执行，避免快速开关面板时主线程被重任务抢占导致掉帧。  
  Panel close no longer runs purgeMissingFileItems and clearExpiredData immediately; cleanup is deferred ~0.6s to avoid main-thread stalls during rapid toggles.  

- **面板获得焦点时机优化**  
  调整 activateApp 与 makeKeyAndOrderFront 的调用顺序，面板展示前先激活应用，动画完成后仅在需要时再次激活，减少“面板已显示但未获得焦点”的停顿感。  
  Activation and makeKeyAndOrderFront order adjusted: app activates before panel animates; post-animation re-activation only when needed, reducing “panel visible but not focused” stalls.  

- **剪贴板 Copy/Cut 监听能耗优化**  
  全局按键监听仅在命中 ⌘C / ⌘X 时触发检测，其他按键在回调内直接过滤，避免每次按键都创建 Task 或切换主线程，降低后台能耗。  
  Copy/Cut monitor now filters key events in-place; only ⌘C and ⌘X trigger detection, avoiding Task creation and main-thread switches on every keystroke to reduce background energy use.  

- **粘贴队列快捷键监听能耗优化**  
  快捷键配置改为缓存读取，配合 UserDefaults 变更通知同步；按键回调增加 fast path，仅处理 V 键与 Typing Paste 自定义快捷键，无关按键直接返回，减少 JSON 解码与主线程切换开销。  
  Hotkey settings are now cached and synced via UserDefaults notifications; keyDown callbacks use a fast path to process only V key and Typing Paste shortcut, avoiding JSON decode and main-thread hops on unrelated keys.  

- **暂停倒计时 UI 能耗优化**  
  暂停指示器与标签栏倒计时由 Timer.publish 改为 .task + Task.sleep，仅在限时暂停时每秒刷新；无限期暂停不再持续唤醒，减少 CPU 唤醒。  
  Pause countdown UI now uses .task + Task.sleep instead of Timer.publish; tick only when paused with an end time; indefinite pause no longer triggers periodic wakeups, reducing CPU activity.  

- **搜索栏展开/收起动画与样式**  
  搜索栏展开/收起使用自定义 timingCurve 动画，背景从 Capsule/Circle 切换改为单一 RoundedRectangle 条件填充，图标用 scaleEffect 替代字体切换，过渡更顺滑。  
  Search bar expand/collapse now uses a custom timingCurve; background unified to RoundedRectangle with conditional fill; icon uses scaleEffect instead of font switching for smoother transitions.  

- **分组分享自动选择更稳路径**  
  当分组内包含文件 URL 或大内容时，会自动退化为逐条资源发送，避免分组大包失败。  
  Group sharing now automatically falls back to per-item resource transfer when file URLs or large payloads are included, avoiding oversized group-send failures.  

- **资源接收生命周期更稳**  
  资源文件到达后会先迁移到应用临时目录再处理，避免系统回收临时文件导致读取失败。  
  Received resource files are now moved into app-controlled temp storage before processing, preventing read failures from OS temp cleanup.  

### 变更 / Changes
- **Welcome 迁移页自动跳过**  
  欢迎窗口打开后会后台预扫描；无可迁移内容时自动隐藏第 7 页（6 直接到 8）。  
  Welcome now pre-scans in background and auto-hides page 7 when no importable content is found (6 goes directly to 8).  

- **移除光标助手和局域网共享的 Beta 标记**  
  光标助手与局域网共享设置页面标题旁的 Beta 标签已移除，这两项功能现已正式发布。  
  The Beta badge next to Cursor Assistant and LAN Sharing settings headers has been removed; both features are now considered stable.  

- **连接重试策略调整**  
  “X后重试”现在是操作提示而非自动行为，系统不会在倒计时结束后自动重连。  
  “Retry in X” is now an action hint rather than an automatic action; the app will not auto-reconnect after countdown.  

- **安装辅助入口改为文件夹形态**  
  DMG 中安装辅助内容从“直接展示两个脚本”调整为“展示一个工具文件夹”，减少界面噪音。  
  Installer helpers in the DMG are changed from two standalone scripts to a single tools folder to reduce visual clutter.  

- **Orbit 演示行为范围调整**  
  Orbit 现在默认走“单模式应用切换”路径，不再进入剪贴板环切换流程，也不再启用跳转预测排序。  
  Orbit now follows a single-mode app-switching flow by default, without clipboard-ring switching or jump-model prediction ordering.  

- **空状态图标更新**  
  弹出面板的三种空状态（标签无记录、剪贴板为空、未找到结果）图标从 `clipboard` 替换为 `doc.on.clipboard`，使用分层渲染模式（`.hierarchical`），深色/浅色模式自动适配。  
  The three empty-state icons in the popup panel (tag has no records, clipboard is empty, no results found) now use `doc.on.clipboard` with hierarchical symbol rendering, automatically adapting to light and dark mode.  

- **面板顶部间距优化**  
  顶部导航栏（搜索、标签、控制按钮）距面板上边缘间距从 14pt 减至 10pt，面板视觉更紧凑。  
  Top bar padding reduced from 14pt to 10pt for a more compact panel appearance.  

- **文件 URL 传输策略调整**  
  文件 URL 不再按普通内联数据发送，改为统一归档后传输并在接收端还原。  
  File URLs are no longer sent as inline blobs; they are archived for transfer and restored on the receiver.  

- **单条共享 payload 扩展元信息字段**  
  共享 payload 新增 `contentLength`、`timestamp`、`appName`、`tagName`、`tagColor`，用于更准确还原来源上下文。  
  Single-item payloads now include `contentLength`, `timestamp`, `appName`, `tagName`, and `tagColor` for better context restoration.  

- **大内容发送阈值行为调整**  
  超过阈值的内容会自动切到资源传输（Multipeer）或流式传输（直连），小内容仍走内联。  
  Payloads above threshold now auto-switch to resource transfer (Multipeer) or streaming (Direct), while small items stay inline.  

### 修复 / Fixes
- **修复 Welcome 切页时左侧文案漂移**  
  左侧文案不再因布局偏移出现明显横向移动。  
  Fixed visible horizontal drift of left text during onboarding page transitions.  

- **修复 Welcome 引导页索引越界崩溃**
  处理了 `WelcomeView` 在页面切换时偶发的数组越界访问（`pages[currentPage]`）问题，避免出现 `Swift/ContiguousArrayBuffer.swift:691: Fatal error: Index out of range` 崩溃。  
  Fixed an occasional index-out-of-range crash in `WelcomeView` page switching (`pages[currentPage]`), preventing `Swift/ContiguousArrayBuffer.swift:691: Fatal error: Index out of range`.

- **修复拒绝后仍显示连接中**  
  处理了对方拒绝或超时后发起端状态未及时更新的问题，避免界面误导。  
  Fixed the issue where sender-side status could remain “Connecting” after a decline or timeout.  

- **修复重复触发连接弹窗的问题**  
  通过冷却与手动重试流程，减少短时间内重复请求导致的连续弹窗。  
  Reduced repeated invitation popups by enforcing cooldown and manual retry flow.  

- **修复重复内容导致的列表 ID 冲突警告**  
  当智能识别结果里出现重复文本（如多个 `127.0.0.1`）时，不再触发 SwiftUI `ForEach` 的重复 ID 警告，列表渲染更稳定。  
  Fixed a SwiftUI `ForEach` duplicate-ID warning when detected content contains repeated values (such as multiple `127.0.0.1`), improving list rendering stability.  

- **修复打包脚本变量解析异常**  
  处理了 `release.sh` 在部分环境下可能触发的变量解析报错，提升打包稳定性。  
  Fixed a variable parsing issue in `release.sh` that could trigger an unbound-variable error in some environments.  

- **修复 Orbit 精简后窗口控制器的上下文进程获取编译问题**  
  调整了 Orbit 窗口控制器中的上下文进程获取实现，避免精简后出现返回类型不匹配导致的编译错误。  
  Fixed a compile issue in Orbit window controller context-process resolution after simplification by correcting the return-type implementation.  

- **修复关闭面板时的线程优先级反转告警**  
  优化了面板关闭时的焦点收尾流程，减少主线程等待低优先级任务导致的性能告警。  
  Reduced priority-inversion performance warnings when closing the panel by streamlining focus teardown and avoiding main-thread waits.  

- **修复极速按 ESC 时焦点未归还**  
  现在在弹出面板刚出现的极短时间内立刻按 ESC，焦点也会稳定返回到原来的应用，不再出现“面板已关闭但焦点仍停在 Deck”的情况。  
  Fixed a focus-return race when pressing ESC immediately after opening the panel; focus now reliably returns to the previous app instead of staying on Deck.  

- **修复自动更新后残留 `.Deck.app.old.*` 备份文件**  
  更新完成后新 App 启动时会自动删除 `/Applications` 下的旧版备份，不再累积残留。  
  Old app backups (`.Deck.app.old.*`) in `/Applications` are now automatically removed on startup after an update, preventing accumulation.  

- **修复单条资源接收时标签未即时显示**  
  接收端创建新标签后会立即刷新标签栏，内容和标签可同步可见。  
  Fixed delayed tag visibility for single-item resource receive by refreshing the tag list immediately after tag creation.  

- **修复大内容在局域网下偶发传输失败**  
  通过资源/流式链路替代单次大包发送，降低大图、安装包、文件夹分享失败概率。  
  Fixed intermittent LAN failures for heavy payloads by replacing one-shot large sends with resource/stream transfer.  

- **修复资源接收临时文件偶发丢失**  
  处理回调里先迁移临时文件再解码，避免文件在回调结束后被系统回收。  
  Fixed occasional temp-file loss on receive by moving resources before decode, avoiding cleanup after callback return.  

- **修复默认端口占用导致直连失败**  
  新增端口回退后，默认端口被占用时仍可自动连上。  
  Fixed direct-connect failures when the default port is occupied by adding automatic port fallback.  

- **修复 TOTP 弹窗验证码显示与验证窗口不同步**  
  验证码现在按当前时间窗口实时计算，避免倒计时变化但验证码不变化导致的偶发失败。  
  TOTP is now computed live against the current time window, preventing failures caused by countdown changes while code stayed static.  

- **修复验证请求早期失败时的 continuation 残留风险**  
  发送验证请求编码失败、会话不可用或发送异常时，会及时清理等待态，避免后续二次回调风险。  
  Continuation state is now cleared on early verify-request failures (encode/session/send), preventing later double-callback risks.  

- **修复资源先到但清单未到时被忽略的问题**  
  接收端新增“先收资源后补清单”的配对处理，不再因为到达顺序差异直接丢弃资源。  
  Fixed resource drops caused by arrival-order mismatch by adding resource-first then manifest matching on receiver side.  

- **修复资源接收失败场景的临时文件残留**  
  对接收失败、会话停止和过期缓存等路径补齐清理，减少临时目录堆积。  
  Added cleanup on receive-failure, service stop, and stale-cache paths to reduce temp-file buildup.  

- **修复未验证设备资源被缓存的安全边界问题**  
  在安全模式下，未完成验证的资源会被立即拒绝并清理，不再进入等待队列。  
  In security mode, unverified resources are now rejected and cleaned immediately instead of being queued.  

- **修复直连共享标签 ID 映射错误**  
  直连共享标签改为按真实标签 ID 读写，并同步维护标签显示顺序，避免标签错位。  
  Fixed direct-connect tag ID mapping by using real IDs and maintaining tag display order consistency.  

- **修复接收方验证码弹窗“取消后不关闭”**  
  接收方点击取消后会立即关闭弹窗，交互反馈更明确。  
  Receiver-side TOTP dialog now closes immediately when cancel is tapped.  

- **修复直连发送路径中的未使用变量编译告警**  
  清理了 `sendItem` 里无实际用途的弱引用绑定，消除无效警告。  
  Removed an unused weak-capture binding in direct-send `sendItem`, eliminating the compiler warning.  

- **修复 HotKeyManager 全局快捷键事件处理的类型不匹配编译错误**  
  统一 `InstallEventHandler` 参数类型：将 `paramErr` 显式转为 `OSStatus`，并把事件数量参数改为 `Int`，避免因类型不一致导致构建失败。  
  Fixed type-mismatch compile errors in HotKeyManager global hotkey event handling by aligning `InstallEventHandler` argument types: casting `paramErr` to `OSStatus` and passing event count as `Int`.  

- **修复“模拟键盘输入粘贴”快捷键取消按钮无反馈**  
  当快捷键已是默认值 `⌘⌥V` 时，取消按钮现在会显示为灰色不可点；只有在用户自定义过快捷键后才可点击并恢复默认，避免“点了没反应”的误解。  
  Fixed no-feedback behavior of the Typing Paste shortcut cancel button. When the shortcut is already the default `⌘⌥V`, the cancel button is now dimmed/disabled; it becomes clickable only after customization to reset back to default.  

- **修复规则选择面板布局递归告警**  
  调整规则选择面板的刷新时机，避免在布局过程中触发递归布局告警，弹层显示更稳定。  
  Adjusted rule-picker panel refresh timing to avoid layout-recursion warnings during active layout, improving popup stability.  

- **优化敏感窗口标题检测的系统日志噪声**  
  对不适合查询的系统进程做了过滤，减少 `task name port` 相关报错刷屏，同时保持常用场景检测能力。  
  Added filtering for system processes that are unsuitable for title queries, reducing `task name port` log noise while preserving normal detection behavior.  

- **归档解压路径越界防护（Zip Slip）**  
  解压前会先检查压缩包条目路径，解压后再校验输出路径与符号链接目标，避免越界落盘。  
  Added archive extraction boundary protection by validating zip entries before extraction and verifying output/symlink paths after extraction to prevent path escape.  

- **资源清单发送失败时的临时文件残留**  
  当 `resource_manifest` 发送失败时，会立即清理对应临时文件，避免积累。  
  Temp artifacts are now cleaned immediately when `resource_manifest` sending fails, preventing file buildup.  

- **安全模式协商上下文不一致**  
  连接邀请现在携带 `securityMode` 上下文，接收端会解析并同步对端安全模式状态。  
  Connection invitations now carry `securityMode` context, and the receiver parses it to keep peer security-mode state in sync.  

- **分组加密一致性问题**  
  分组发送时若任一条目加密失败会直接失败，接收端若解密任一条目失败会丢弃整组，避免“部分成功”造成数据错乱。  
  Group transfer is now all-or-nothing for encryption: send fails if any item fails to encrypt, and receive drops the whole group if any item fails to decrypt.  

- **验证流程并发覆盖与异常成功判定**  
  验证流程加入忙碌保护和对端绑定校验；`verify_success` 缺少或非法密钥时会判定失败，不再误报成功。  
  Verification flow now has busy protection and peer binding checks; `verify_success` without a valid secret now fails instead of being treated as success.  

- **直连异常包处理不及时导致状态错乱**  
  接收缓冲在追加前先做上限判断；遇到溢出或非法长度包会直接拒绝连接，减少 DoS 与状态错乱风险。  
  Direct receive buffer now enforces limits before append; overflow/invalid-length payloads trigger immediate connection rejection to reduce DoS and state corruption risks.  

- **直连拒绝/重连后的连接状态不同步**  
  拒绝和重连路径现在会先统一标记断开，避免 UI 长时间显示“已连接”假状态。  
  Reject/reconnect paths now mark disconnected first, preventing stale “connected” UI state.  

- **AES-GCM 空密文与 PSK 边界异常**  
  发送侧不再接受空 `combined` 密文；PSK fallback 改为合法长度密钥，挑战阶段 PSK 非法会直接拒绝连接。  
  Sender no longer accepts empty AES-GCM `combined` output; PSK fallback now uses valid key length, and invalid PSK during challenge handling now rejects the connection immediately.  

- **接收落盘目录使用远端 transferId 的路径风险**  
  接收归档落盘目录改为安全化 `transferId` 组件，降低路径注入风险。  
  Archive receive destination now uses sanitized `transferId` components to reduce path-injection risk.  

### 兼容性与行为说明 / Compatibility & Behavior Notes
- **macOS 安全限制下仍需手动触发脚本**  
  将 App 拖入 `Applications` 后，系统不会自动执行 DMG 内脚本；如需修复隔离属性，请手动双击对应脚本。  
  After dragging the app into `Applications`, macOS will not auto-run scripts inside the DMG; run the needed script manually.  

### 升级建议 / Upgrade Notes
- **建议尽快升级到 v1.2.7**  
  本版本覆盖局域网连接与传输（拒绝状态、冷却重试、大内容流式传输、多端口回退、标签同步）、安全验证（TOTP 实时轮换、加密一致性、Zip Slip 防护）、安装体验（工具文件夹、一键安装、多语言说明）及多处 UI 优化，建议所有用户升级。  
  v1.2.7 covers LAN connection and transfer (reject state, cooldown retry, large-payload streaming, multi-port fallback, tag sync), security and verification (live TOTP, encryption consistency, Zip Slip protection), install experience (tools folder, one-click install, multi-language help), and extensive UI improvements. Upgrade recommended for all users.

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
- **敏感检测更智能，减少误拦截**  
  优化银行卡号与证件号检测逻辑，降低长文本中的误判概率，复制报错/日志内容更容易正常入库。  
  Improved bank-card and identity-number detection to reduce false positives in long text, so copied error/log content is more reliably saved.  
- **标签记录稳定性修复**  
  修复重复复制同一内容时可能把已打标签记录重置成“未标签”的问题，标签不再容易莫名消失。  
  Fixed a tag-loss case where recopying the same content could reset a tagged item back to “untagged”.  
- **检测速度与稳定性提升**  
  调整匹配流程与前置判断，减少无效扫描，敏感检测在高频复制场景下更快更稳。  
  Refined matching flow and pre-checks to cut unnecessary scans, making detection faster and steadier under frequent copy events.  
- **隐私说明文案更透明**  
  在“设置 > 隐私”补充上传范围说明，明确仅上传最近 24 小时的内存曲线与相关报错信息，且均已脱敏。  
  Added clearer wording in "Settings > Privacy" to explain that only the last 24 hours of memory curves and related error info are uploaded, with anonymization applied.  
- **脚本插件联网授权更严格**  
  联网授权现在强绑定脚本哈希；脚本内容变化后不会继续沿用旧授权，需要重新授权。  
  Network permission for script plugins is now strictly hash-bound; changed scripts no longer reuse old authorization and must be re-approved.  
- **更新代理限流降级策略优化**  
  当 `RATE_LIMITER` 未配置或异常时，更新代理默认降级可用（避免直接 503）；如需严格拦截可开启 `RATE_LIMIT_FAIL_CLOSED=true`。  
  The update proxy now degrades gracefully when `RATE_LIMITER` is missing or unhealthy (instead of hard 503); set `RATE_LIMIT_FAIL_CLOSED=true` for strict blocking behavior.  
- **向量索引恢复后写入稳定性修复**  
  修复 vec 恢复完成后仍可能写回旧默认表，导致“恢复成功但紧接着 upsert 失败”的问题；恢复表现在会被优先选用。  
  Fixed a case where vec writes could still target an old default table right after recovery, causing “recovery completed but immediate upsert failure”; recovery tables are now preferred.  
- **向量旧表清理降噪与容错**  
  遇到 sqlite-vec 内部 shadow 表限制时，不再强行删除并反复刷 `may not be dropped`，改为延后清理，运行更稳定。  
  Improved vec cleanup resilience: when sqlite-vec shadow-table restrictions apply, cleanup is deferred instead of force-dropping, reducing repeated `may not be dropped` noise.  
- **存储整理与迁移安全保护增强**  
  在向量索引可用时跳过 `VACUUM`；存储迁移前若 `WAL checkpoint` 失败会中止迁移，降低向量索引结构不一致风险。  
  Added safer storage maintenance/migration guards: skip `VACUUM` when vec is active and abort migration if `WAL checkpoint` fails, reducing vec-structure inconsistency risk.  
- **向量回填判定与故障日志进一步修复**  
  backfill 调度只按 vec 虚拟表判断，避免 shadow 表误判为“无需回填”；同时修复 upsert 失败日志延后造成的时序误导，排障更准确。  
  Backfill scheduling now checks only vec virtual tables (excluding shadow tables), and upsert-failure log timing is corrected to avoid misleading recovery-order impressions.  

### 发布链路加固 / Security & Delivery Hardening
- **新增更新代理容错开关**  
  更新 Worker 新增 `RATE_LIMIT_FAIL_CLOSED`（默认 `false`），用于选择“限流器异常时放行”还是“严格拦截”。  
  The update Worker adds `RATE_LIMIT_FAIL_CLOSED` (default `false`) to choose between fail-open and fail-closed behavior when the rate limiter is unavailable.  

### 优化 / Improvements
- **统一敏感检测策略**  
  敏感检测不再依赖单一格式命中，而是结合上下文与内容形态做综合判断，整体可用性更好。  
  Sensitive detection now uses a combined decision based on context and content shape instead of single-pattern hits, improving overall usability.  
- **银行卡检测前置加速**  
  增加更轻量的前置校验，减少大文本场景下的不必要计算。  
  Added lightweight pre-checks for bank-card detection to avoid unnecessary computation on large text.  
- **呼出面板宽度与位置微调**  
  App 呼出面板左右各内收 7 像素，并整体上移 7 像素；高度保持不变，视觉更紧凑且继续居中。  
  Tuned the popup panel layout by insetting 7 px on both sides and shifting it up 7 px while keeping height unchanged, preserving centered alignment with a tighter look.  
- **队列模式状态栏对齐微调**  
  队列模式状态栏布局重新校准：左侧信息组整体右移 5 像素，右侧快捷提示与“清空/退出”整体左移 3 像素，视觉更平衡。  
  Refined queue-mode status bar alignment: the left info group shifts 5 px right, while right-side hints and Clear/Exit shift 3 px left for a more balanced layout.  
- **历史列表底层灰影与立体感移除**  
  去掉历史列表卡片下方的底层灰色衬底与立体阴影，列表区域改为更干净的平面观感。  
  Removed the gray underlay and depth shadow beneath history cards to give the list area a cleaner, flatter appearance.  

### 修复 / Fixes
- **修复深色模式“全部”标签圆点不可见问题**  
  修复深色模式下选中“全部”标签时左侧圆点过暗、几乎看不见的问题；现在会使用更清晰的浅灰指示色。  
  Fixed poor visibility of the "All" tag dot in dark mode when selected; it now uses a clearer light-gray indicator color.  
- **修复长文本误判导致“不保存”问题**  
  开启银行卡号检测或证件号检测时，部分 App 的长报错/日志文本可能被误判并拦截；现已显著缓解。  
  Fixed a false-positive issue where long app error/log text could be blocked when bank-card or identity-number detection was enabled.  
- **修复重复复制导致标签被覆盖问题**  
  当同一内容再次入库时，系统会保留原有手动标签，不再因为去重更新把标签清空。  
  Preserved existing manual tags during duplicate-content upserts, preventing tag overwrite to untagged.  
- **修复缺失文件自动清理误删问题（已打标签项）**  
  文件源路径失效时，已打标签的记录不再被自动清掉，只会标记为文件缺失。  
  Tagged items are no longer auto-deleted when source files go missing; they are kept and marked as missing-file entries.  
- **修复云端合并时本地标签被空标签覆盖问题**  
  云端记录为未打标签时，不再覆盖本地已有标签，减少多端同步后的标签丢失。  
  Cloud merge now avoids overwriting an existing local tag when the incoming cloud record is untagged.  
- **修复 vec 活跃表目标回退到默认表的问题**  
  维度映射不再持久化默认 vec 表；存在 recovery 表时会优先路由到 recovery，避免读写目标被错误切回旧表。  
  Fixed vec active-table fallback behavior by no longer persisting default-table mappings; recovery tables are now preferred for read/write routing when present.  
- **修复 vec 写入/搜索在切表窗口期命中旧表的问题**  
  向量写入与搜索前会重新解析当前活跃表，切表期间可自动自愈，减少 `vec upsert internal error` 的连锁失败。  
  Fixed vec write/search routing during table-switch windows by re-resolving the active table before operations, reducing chained `vec upsert internal error` failures.  
- **修复 vec 旧表清理触发内部表删除报错刷屏问题**  
  旧表清理不再直接处理 sqlite-vec shadow 子表（如 `_chunks/_info/_rowids`），失败场景会延后清理而非重复报错。  
  Fixed repeated cleanup spam by avoiding direct deletion of sqlite-vec shadow subtables (such as `_chunks/_info/_rowids`); failed cleanup is deferred instead.  
- **修复 vec 表枚举混入 shadow 表导致的误判问题**  
  vec 表枚举现已限定为 `CREATE VIRTUAL TABLE ... USING vec0`，避免把 `_chunks/_info/_rowids` 当成业务索引表参与判空、路由或清理。  
  Fixed shadow-table pollution in vec-table discovery by restricting enumeration to `CREATE VIRTUAL TABLE ... USING vec0`, preventing `_chunks/_info/_rowids` from being treated as active index tables.  
- **修复 vec 回填“无需执行”误判与失败日志时序误导**  
  回填判定改为基于真实 vec 虚拟表；同时将 upsert 失败日志判定前移到同次写入流程内，避免出现“恢复完成后才打印同次失败”的错觉。  
  Fixed false “backfill not needed” decisions by basing checks on real vec virtual tables, and moved failure-log decisions into the same write flow to avoid delayed same-failure logs after recovery completion.  

### 性能优化 / Performance
- **剪贴板主链路减负（减少主线程热区开销）**  
  合并规则判断路径，去掉重复 ignore 检查；同时把智能断行清理放到后台执行，降低高频复制时的主线程负担。  
  Streamlined clipboard hot-path by removing duplicate ignore checks and moving smart line-break cleanup off the main thread to reduce UI pressure during frequent copies.  
- **搜索兜底改为游标分页（替代 OFFSET 扫描）**  
  模糊搜索候选不足时，改用 keyset/cursor 分页补扫，避免数据量变大后 OFFSET 越查越慢。  
  Replaced OFFSET-based fallback scans with keyset/cursor pagination for fuzzy search expansion, improving scalability on large datasets.  
- **安全模式正则搜索降耗**  
  优化匹配流程，减少每条记录的临时字符串拼接；并按 limit 动态收敛扫描上限，降低 CPU 峰值。  
  Optimized regex matching in security mode by cutting per-row temporary string joins and using a limit-aware scan cap to reduce CPU spikes.  
- **批量行映射改后台并发执行**  
  `row -> ClipboardItem` 的批量转换不再占用数据库串行队列，减少分页与查询互相阻塞。  
  Moved batch `row -> ClipboardItem` mapping off the DB serial queue to a background concurrent queue, reducing contention between pagination and queries.  
- **存储统计后台化并加节流**  
  设置页“占用空间”目录遍历改为后台执行，并增加刷新节流与任务取消，减少设置页卡顿。  
  Storage-size directory traversal in Settings now runs in background with throttling and cancellation to avoid UI hitches.  
- **历史列表减少无效重排与赋值**  
  仅在确实需要时触发重排；并在顺序未变化时跳过数组重写，减少滚动与刷新时的额外开销。  
  Reduced unnecessary history-list reordering and array rewrites by gating reorder triggers and skipping assignments when order is unchanged.  

### 说明 / Notes
- **上传分析数据范围说明**  
  上传内容限定为诊断所需的最小范围，并保持脱敏处理，不包含其他个人信息。  
  Diagnostics uploads are limited to the minimum required scope and remain anonymized, without other personal information.  

### 升级建议 / Upgrade Notes
- **建议所有用户升级到 v1.2.6**  
  如果你经常复制调试日志、报错堆栈或长文本，升级后可明显降低被误拦截概率。  
  Recommended for all users, especially if you frequently copy debug logs, stack traces, or long text, to reduce false blocking.  

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
- **智能文件名识别更准**  
  新增高置信度文本格式识别，Diff/Patch、LilyPond、XML（含 SVG/Plist）会优先命中，减少扩展名误判。  
  Added high-confidence text format detection, so Diff/Patch, LilyPond, and XML family formats (including SVG/Plist) are recognized first with fewer wrong file extensions.  
- **存储维护默认更安全**  
  清理任务改为“先创建回滚快照再删记录”；快照创建失败时会跳过破坏性删除，避免误删后无法撤回。  
  Maintenance now follows a “snapshot first, deletion second” flow; if snapshot creation fails, destructive deletion is skipped to prevent irreversible loss.  
- **性能与耗电继续优化**  
  轮询、日志写盘、网络接口探测、权限轮询等路径做了减负，长时间运行更稳更省资源。  
  Polling, log writing, network interface probing, and permission timers were optimized for lower overhead and better long-running stability.  
- **同步与传输稳定性提升**  
  iCloud 同步状态管理和局域网传输容错加强，异常场景下更不容易中断。  
  iCloud sync state handling and LAN transfer fault tolerance were improved to reduce interruptions in edge cases.  
- **剪贴板图片/文件处理更可靠**  
  文件路径解析、缩略图、图片尺寸和 Base64 图像缓存链路更一致，减少错误判定和异常。  
  File-path parsing plus thumbnail/image-size/Base64 image caching flows are now more consistent, reducing misclassification and runtime issues.  
- **建议 1.2.4 用户升级**  
  本次 1.2.5 集中包含 4 组补丁（功能识别、性能、稳定性、维护安全），建议尽快升级。  
  Version 1.2.5 bundles four patch groups (detection, performance, stability, and maintenance safety); upgrading is strongly recommended.  

### 新增 / Added
- **Vim 导航方向可按习惯切换**  
  在 `设置 -> 快捷键 -> VIM 模式` 中新增 `j/k 导航方向` 选项，可切换 `j→ k←` 或 `j← k→`。  
  Added a `j/k navigation direction` option in `Settings -> Keyboard -> VIM Mode`, so you can switch between `j→ k←` and `j← k→`.  
- **智能文件名新增高置信度格式识别**  
  文本转文件名时，优先识别 Diff/Patch、LilyPond、XML 家族（含 SVG/Plist），减少被代码语言误判的情况。  
  Smart filename generation now prioritizes high-confidence formats such as Diff/Patch, LilyPond, and XML family types (including SVG/Plist), reducing language-based misclassification.  
- **补充智能文件名回归测试集**  
  新增覆盖 Diff、Unified Diff、Hunk 片段、Markdown 分隔线、LilyPond、XML、Swift/JSON/URL/纯文本等场景的回归测试。  
  Added regression coverage for Diff/Unified Diff/Hunk snippets, Markdown separators, LilyPond, XML, and Swift/JSON/URL/plain text scenarios.  

### 优化 / Improvements
- **剪贴板轮询与预览触发路径减负**  
  轮询边界计算增加短时缓存，链接预取与状态栏提示减少不必要的异步跳转，降低高频路径开销。  
  Poll-bound calculations now use short-lived caching, and link prefetch/status-bar pulse paths avoid unnecessary async hops to reduce hot-path overhead.  
- **iCloud 同步状态读取更轻量**  
  变更令牌增加锁与缓存，抓取状态队列复用，减少重复解码和临时队列创建。  
  Cloud change token handling now uses locking plus caching, and fetch-state queue reuse reduces repeated decoding and transient queue creation.  
- **上下文匹配与数据处理性能提升**  
  应用前缀匹配改为预排序缓存；导出、诊断、反馈邮件、文本转换中的日期/格式处理减少重复创建对象。  
  App-prefix matching now uses pre-sorted caching, while export/diagnostics/feedback/text-transform date formatting avoids repeated formatter allocation.  
- **局域网直连网络探测更平稳**  
  物理网卡缓存加入加锁与刷新去重，复用监控队列，避免短时间内重复创建探测任务。  
  LAN direct-connect interface caching now uses locking and refresh de-duplication with a reused monitor queue to avoid repeated probe tasks.  
- **日志系统加入节流与缓冲写盘**  
  Debug/Info 级日志按调用点节流，文件写入改为缓冲+批量落盘，降低日志风暴与磁盘 I/O 压力。  
  Debug/Info logs are now call-site throttled, and file logging uses buffered batch flushes to reduce log storms and disk I/O pressure.  
- **计时器容差策略优化**  
  局域网确认弹窗和权限轮询计时器增加 tolerance，减少无意义唤醒。  
  Timer tolerance is now set for LAN confirmation views and permission polling to reduce unnecessary wakeups.  

### 变更 / Changes
- **保留策略改为仅清理未标记内容**  
  按保留天数清理时，仅处理未打标签项（`tag_id == -1`），用户手动标记内容默认保留。  
  Retention-based cleanup now applies only to untagged items (`tag_id == -1`), while user-tagged content is preserved by default.  
- **维护清理改为“快照成功后再删记录”**  
  无法创建回滚快照时，会跳过记录删除，优先保证可回退与数据安全。  
  Record deletion now happens only after rollback snapshot creation succeeds; if snapshot creation fails, deletion is skipped for safety.  
- **快照替换顺序调整**  
  先持久化新快照，再清理旧快照，避免中途失败导致“新旧都不可用”。  
  Snapshot replacement now persists the new snapshot first and deletes the old one afterward, preventing rollback gaps on mid-process failure.  
- **全量同步触发行为调整**  
  手动全量同步会先清空同步错误并重置变更令牌，再走统一拉取流程，状态管理更一致。  
  Force full sync now clears sync errors and resets the change token before entering the standard fetch pipeline for more consistent state handling.  

### 修复 / Fixes
- **修复 IDE 上下文感知崩溃**  
  修复了复制文本时，读取 IDE 光标上下文偶发触发崩溃的问题。  
  Fixed an intermittent crash when reading IDE caret context during text copy capture.  
- **修复副屏分类切换误隐藏**  
  修复了 Deck 面板在外接显示器上点击分类标签（如“全部/文本/图片/文件”）后意外隐藏的问题。  
  Fixed an issue where Deck panel could unexpectedly hide after clicking category tags (such as “All/Text/Image/File”) on external displays.  
- **修复老系统面板无圆角**  
  修复了在 macOS 26 以下系统中，弹出面板外观为直角的问题。  
  Fixed an issue where the panel appeared with square corners on macOS versions below 26.  
- **修复删除后预览不同步**  
  在 `Command+P` 面板中使用空格预览时，删除当前条目后，预览会立刻同步到新的当前条目；如果列表为空则自动关闭预览。  
  Fixed a stale preview issue in the `Command+P` panel: when preview is open (via Space), deleting the current item now immediately updates preview to the new current item, or closes it when no items remain.  
- **修复跨应用文本误判无法解析**  
  针对 `public.html`、`public.utf16-plain-text`、`public.utf16-external-plain-text` 等文本类型增加兜底解析，降低在 Microsoft Edge、Kiro、微信等应用中出现“Deck 无法解析本剪贴板内容”的概率。  
  Added fallback parsing for text payload types like `public.html`, `public.utf16-plain-text`, and `public.utf16-external-plain-text`, reducing false “Deck can’t parse this clipboard content” cases in apps such as Microsoft Edge, Kiro, and WeChat.  
- **修复菜单项初始化可选值风险**  
  暂停菜单项加入前先做可选值判断，避免初始化阶段的强制解包崩溃。  
  Pause menu item insertion now checks optionals first, avoiding force-unwrapping crashes during initialization.  
- **修复剪贴板缓存并发读写稳定性**  
  URL、颜色、文件路径、缩略图、Base64 图片、图片尺寸等缓存链路补齐加锁与一致性更新，降低并发下异常概率。  
  Cache flows for URL/color/file paths/thumbnails/Base64 images/image size now use stronger locking and consistent updates, reducing concurrency-related failures.  
- **修复文件路径解析兼容性**  
  文件列表同时兼容 `file://` 和普通路径字符串，减少路径识别失败。  
  File list parsing now supports both `file://` URLs and plain path strings, reducing path resolution failures.  
- **修复筛选表达式构建中的崩溃风险**  
  多处条件拼接去除强制解包，避免过滤规则复杂时的空值崩溃。  
  Multiple filter-expression builders were changed to avoid force-unwrapping, preventing nil-related crashes in complex rule combinations.  
- **修复图片预览与预览图空值判断**  
  预览图是否为空的判断改为更安全写法，避免中大图场景下的异常分支。  
  Preview-thumbnail emptiness checks now use safer logic, preventing failure paths in medium/large image workflows.  
- **修复全局快捷键注册/卸载异常处理**  
  热键事件处理增加空指针保护与状态检查，安装/移除失败会记录错误并安全回收状态。  
  Global hotkey handling now validates pointers and status codes; install/remove failures are logged and state is safely recovered.  
- **修复局域网传输中的边界与空值问题**  
  TOTP 截断加入边界保护；共享密钥缺失时改为安全跳过，避免异常中断。  
  Added bounds checks in TOTP truncation and safe-guarded missing shared keys in LAN transfer to avoid runtime interruption.  
- **修复 Orbit 覆盖安装的静默失败**  
  备份已有应用失败时会明确抛错，不再悄悄继续导致状态不一致。  
  Orbit overwrite-install now surfaces backup failures explicitly instead of silently continuing with inconsistent state.  
- **修复图标缓存复制失败回退**  
  图标尺寸副本创建失败时会安全回退到基础图标，避免缓存链路崩溃。  
  Icon cache now safely falls back to base icons when sized-copy creation fails, avoiding cache-path crashes.  
- **修复维护扫描误判坏文件链接**  
  当记录中的存储路径文件仍存在时，扫描会直接跳过，避免误判为坏链接。  
  Maintenance scan now skips records whose stored blob path still exists, avoiding false broken-link detection.  
- **修复 Swift 6 下 DirectConnectService 并发隔离编译报错**  
 调整 `nonisolated` 网络接口探测中的队列使用方式，避免主线程隔离引用导致的编译错误。  
 Updated queue usage in `nonisolated` network-interface probing to avoid main-actor isolation compile errors under Swift 6.  

### 兼容性与行为说明 / Compatibility & Behavior Notes
- **异常上下文会自动降级处理**  
  当编辑器返回异常的行列信息时，Deck 会跳过异常位置信息而继续记录内容。  
  When an editor returns invalid line/column context, Deck now skips invalid position data and continues capturing content.  
- **打标签内容不参与保留期自动清理**  
  使用保留天数清理时，已打标签的内容默认保留，不会被自动删除。  
  Tagged items are excluded from retention-based automatic cleanup and remain preserved by default.  
- **快照创建失败时不会执行破坏性删除**  
  若维护任务无法创建回滚快照，会跳过记录删除，仅保留非破坏性流程。  
  If rollback snapshot creation fails during maintenance, destructive record deletion is skipped and only non-destructive flows continue.  

### 升级建议 / Upgrade Notes
- **建议从 1.2.4 升级到 1.2.5**  
  本次版本主要解决稳定性问题，建议所有受影响用户升级。  
  This release mainly addresses stability, and all affected users are encouraged to upgrade.  
  
  ---
  
### 作者寄语 / A Note from the Author

> **写在 2026 农历新春**
>
> 感谢每一位支持 Deck 的朋友。你们的反馈和耐心，让 Deck 一步步变得更稳、更好用。新的一年，愿你所想皆有回响，所行皆有收获。
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
- **更顺滑的历史滚动与焦点体验**  
  `NSScrollView` 滚轮增量映射 + 钳位 + 方向键焦点切换。  
  `NSScrollView` wheel-delta mapping + clamping + keyboard focus switching.  
  _HistoryListView.swift_  
- **搜索更快、更精准（支持 `lang:` / `len:`）**  
  分字段匹配（`title/text/appName`）+ `lang:`（Beta）/`len:` 规则。  
  Field-based matching (`title/text/appName`) + `lang:` (Beta) / `len:` rules.  
  _SearchService.swift_ _SearchRuleFilters.swift_ _TokenSearchTextView.swift_ _TopBarView.swift_  
- **超长文本与 Base64 处理不再“拖后腿”**  
  Base64 探测/解码后台化 + 快速否决/采样/上限。  
  Background Base64 detection/decoding with fast rejects, sampling, and hard caps.  
  _ClipItemCardView.swift_ _ClipboardItem.swift_  
- **图片卡片新增文件大小**  
  文件大小异步计算 + `NSCache` 缓存，滚动不阻塞。  
  Async file-size computation + `NSCache` caching to avoid scroll stalls.  
  _ClipItemCardView.swift_  
- **新增“一键整理/自检”（含可撤回快照）**  
  一键维护 + 报告弹窗 + 5 分钟可撤回快照。  
  One-click maintenance + report sheet + 5-minute rollback snapshot.  
  _StorageMaintenanceService.swift_ _DeckSQLManager.swift_ _SettingsView.swift_ _StorageMaintenanceReportSheet.swift_  

### 新增 / Added
- **图片卡片：文件大小展示**  
  图片卡片在尺寸下方新增“文件大小”一行；计算中显示“计算中…”，完成后自动刷新。大小计算走异步任务，并用 `NSCache` 缓存每条记录结果以避免重复计算。  
  Image cards now show file size under dimensions; displays “Calculating…” while processing and auto-refreshes when ready. Size is computed asynchronously and cached via `NSCache`.  
  _ClipItemCardView.swift_  
- **搜索规则：`lang:` / `-lang:`（Beta）**  
  支持按代码语言过滤/排除；大小写不敏感、支持 `+` 多选，并提供常见别名映射（如 js/ts/c#/cpp/yml/md）。规则选择器新增 Beta 标签与性能提示。  
  Filter/exclude by detected code language; case-insensitive, supports `+` multi-select with common aliases (e.g., js/ts/c#/cpp/yml/md). Adds a Beta badge and performance note in the rule picker.  
  _SearchRuleFilters.swift_ _SearchRulePickerView.swift_ _Localizable.xcstrings_  
- **设置页：一键整理 / 自检 + 可撤回快照**  
  新增维护入口与运行态展示、报告弹窗联动，并提供 5 分钟可撤回的快照恢复能力。  
  New maintenance entry with progress UI, a report sheet, and a rollback snapshot available for 5 minutes.  
  _StorageMaintenanceService.swift_ _DeckSQLManager.swift_ _SettingsView.swift_ _StorageMaintenanceReportSheet.swift_  
- **文件图标缓存**  
  新增图标缓存机制，减少系统图标查询开销，预览与列表渲染更稳定。  
  Adds icon caching to reduce system icon lookups for more stable rendering in lists and previews.  
  _IconCache.swift_ _PreviewWindowController.swift_ _PreviewOverlayView.swift_ _ClipboardItem.swift_ _ClipboardCardView.swift_ _ClipItemCardView.swift_ _PrivacySettingsView.swift_ _StatisticsView.swift_ _PDFPreviewView.swift_  
- **设置项：打开面板时隐藏 Dock**  
  新增设置项「通用 → 行为 → 打开面板时隐藏 Dock」，默认开启；关闭后恢复原行为（Dock 可随鼠标放大）。  
  Adds a new setting “General → Behavior → Hide Dock when panel opens”, enabled by default; turning it off restores the original Dock behavior (e.g., magnification on hover).  
  _SettingsView.swift_ _MainWindowController.swift_ _UserDefaultsManager.swift_ _Localizable.xcstrings_  

### 优化 / Improvements
- **历史列表滚动更顺滑**  
  支持将滚轮“垂直增量”映射为水平滚动，并加入滚动钳位与交互细节优化，浏览大量历史更跟手。  
  Smoother history scrolling with vertical-wheel-to-horizontal mapping, clamping, and interaction refinements for large histories.  
  _HistoryListView.swift_  
- **HistoryList：空 `contextTypes` 回退 DB 顺序 + 选中项兜底**  
  当 `contextTypes` 为空时直接回退到 DB 顺序，避免 `orderedItems` 与 `dataStore.items` 共享存储导致的 COW 全量复制；并确保 `selectedId` 一定落在当前列表内。  
  When `contextTypes` is empty, fall back to DB order to avoid a full-copy COW triggered by shared storage between `orderedItems` and `dataStore.items`, and ensure `selectedId` always resolves within the current list.  
  _HistoryListView.swift_  
- **键盘焦点切换更自然**  
  搜索框聚焦时按下方向键可把焦点移到列表且不清空搜索文本；列表聚焦时按上方向键回到搜索框（无修饰键时生效）。  
  Natural focus switching: Down moves focus from search to list without clearing text; Up returns to search (when no modifier keys are held).  
  _HistoryListView.swift_  
- **搜索匹配更高效（分字段匹配）**  
  匹配逻辑按 `title/text/appName` 分字段处理，exact/regex/fuzzy 分别匹配；避免把大文本拼成单个巨字符串再匹配，降低 CPU 与瞬时内存压力。  
  Field-based matching across `title/text/appName` for exact/regex/fuzzy; avoids concatenating huge strings, reducing CPU and transient memory pressure.  
  _SearchService.swift_  
- **语言过滤更稳、更省**  
  `lang:` 采用“先套牢前面规则、再二次筛选语言”的顺序；语言检测改走更轻量的检测接口，并引入缓存（含 signature 防误命中）与预热策略。  
  `lang:` now runs after non-language rules narrow candidates; language detection uses a lighter-weight path and adds signature-based caching + warming to reduce redundant work.  
  _SearchRuleFilters.swift_ _DeckDataStore.swift_  
- **大文件预览更轻量**  
  Markdown 文件预览仅读取前 16KB 并提示截断，避免大文件打开导致明显卡顿。  
  Markdown previews read only the first 16KB with a truncation hint to avoid stalls on large files.  
  _LargeTextPreviewView.swift_  
- **日志与格式化更省分配**  
  日志改为惰性字符串，并新增线程本地 `DeckFormatters` 复用 Number/Date/Relative formatter，减少滚动与日志热点的对象创建与格式化开销。  
  Lazy logging plus thread-local `DeckFormatters` reuse Number/Date/Relative formatters to reduce object churn and formatting costs on hot paths.  
  _AppLogger.swift_ _DeckFormatters.swift_  
- **图片卡片：Base64 任务轻量预检 + detached 取消处理**  
  增加极轻量 pre-check，普通文本不再启动 Base64 探测任务；`Task.detached` 增加取消处理，减少任务雨与无效计算。  
  Adds an ultra-light pre-check to avoid spawning Base64 tasks for normal text; adds cancellation handling for `Task.detached` to reduce task storms and wasted work.  
  _ClipItemCardView.swift_  
- **链接预览正则复用缓存**  
  Link 预览正则复用 RegexCache（含 options），减少重复编译带来的 CPU 抖动。  
  Link preview regex now reuses a RegexCache (with options) to avoid repeated compilation and CPU spikes.  
  _SmartRuleService.swift_ _LinkPreviewCard.swift_  
- **SmartTextService 热路径更轻量**  
  `isLikelyAssetFilename` 改为纯字符串判断以避免每次跑正则；裸域名校验改用已缓存的 regex；`matches(for:in:)` 改为 `enumerateMatches` 以减少中间数组分配（行为保持一致）。  
  Makes SmartTextService hot paths lighter: `isLikelyAssetFilename` now uses plain string checks instead of regex, bare-domain validation reuses cached regex, and `matches(for:in:)` uses `enumerateMatches` to reduce intermediate allocations (no behavior change).  
  _SmartTextService.swift_  
- **IconCache：分层缓存 + 新增 size API**  
  拆分 base/sized cache，并新增 `icon(forFile:size:)`；减少图标取用过程中的 `.copy()` 分配与重复工作，提升列表/预览渲染的稳定性。  
  Splits IconCache into base/sized caches and adds `icon(forFile:size:)`, reducing `.copy()` allocations and redundant work for more stable list/preview rendering.  
  _IconCache.swift_  
- **ClipboardItem 热路径进一步降分配**  
  增加 URL/`normalizedFilePaths` 缓存；`sampleText` 与富文本采样改为 index‑limited；文件名提取改走 `NSString`；PDF/文件图标改用新的 size API。  
  Further reduces allocations on ClipboardItem hot paths: caches URL/`normalizedFilePaths`, makes text/RTF sampling index-limited, extracts filenames via `NSString`, and routes PDF/file icons through the new size API.  
  _ClipboardItem.swift_ _IconCache.swift_  
- **ClipboardService：更快的前置判断与轻量缓存**  
  URL 清理增加快速前置判断；敏感标题加入 0.4s TTL 缓存；身份证采样改 index‑limited；银行卡前缀静态化以减少重复构造。  
  Adds faster pre-checks and lightweight caching: quick URL-sanitization guard, 0.4s TTL cache for sensitive-title checks, index-limited ID sampling, and static bank-card prefixes to reduce repeated setup.  
  _ClipboardService.swift_  
- **Semantic 文本截断更省开销**  
  semantic text 截断改为 index‑limited，避免长文本处理时的额外扫描与分配。  
  Makes semantic-text truncation index-limited to avoid extra scans/allocations on long content.  
  _SemanticSearchService.swift_  
- **拖拽图片类型检测更准确（WebP）**  
  拖拽图片类型检测改用 `withUnsafeBytes`，提升 WebP 识别准确性并减少不必要的解析开销。  
  Improves drag-and-drop image type detection (especially WebP) using `withUnsafeBytes`, reducing unnecessary parsing overhead.  
  _ClipItemCardView.swift_  
- **面板激活期间 Dock 不再抢响应**  
  在面板 show/hide 时保存/恢复 `NSApp.presentationOptions`，并临时切换 `.hideDock`，避免面板激活期间 Dock 响应干扰交互；同时加入延迟隐藏/恢复（`scheduleDockSuppression(...)`）以避免面板出现瞬间 Dock “闪一下”（系统 `.hideDock` 本身不支持渐隐动画）。默认：`dockHideDelay = -1`、`dockShowDelay = 0.10`。  
  Saves/restores `NSApp.presentationOptions` and temporarily toggles `.hideDock` during panel show/hide to prevent Dock interactions from interfering while the panel is active; adds delayed hide/restore (`scheduleDockSuppression(...)`) to avoid a quick Dock “flash” when the panel appears (macOS `.hideDock` has no fade animation). Defaults: `dockHideDelay = -1`, `dockShowDelay = 0.10`.  
  _MainWindowController.swift_  
- **剪贴板写入兼容性与内存护栏**  
  对 unsupported payload 增加总预算/单类型上限并跳过 image，避免内存暴涨；文件粘贴优先写 `NSURL`（兼容性更好），并保留原有 fallback 路径。  
  Adds memory guardrails for unsupported payloads (total budget + per-type caps, skipping images) and prefers writing `NSURL` for file pastes while keeping the existing fallbacks for compatibility.  
  _ClipboardService.swift_  
- **局域网接收数据的硬上限保护**  
  接收数据先做 30MB 上限拦截，超限直接丢弃并记录，避免异常包拖垮进程内存。  
  Adds a hard 30MB cap for incoming data; oversized payloads are dropped and logged to prevent memory blow-ups.  
  _MultipeerService.swift_  

### 变更 / Changes
- **长度规则统一为 `len:` / `-len:`**  
  原 `size:` 规则调整为 `len:`（仅数字+比较符）；文本类按长度参与过滤，非文本不排除但会降权排序。  
  The old `size:` rule is renamed to `len:` (numeric only); text-like items are filtered by length while non-text items are kept but de-ranked.  
  _SearchRuleFilters.swift_ _TokenSearchTextView.swift_ _TopBarView.swift_ _Localizable.xcstrings_  
- **长度过滤尽量下推到数据库**  
  在无关键词场景下减少内存扫描量，提升规则过滤的响应速度与一致性。  
  Pushes length filtering down to the database where possible to reduce in-memory scanning and improve responsiveness.  
  _DeckDataStore.swift_  
- **横向滚动方向修正**  
  主要是横向滑动的输入场景下，滚动方向已调整为更符合直觉的表现（如 Magic Mouse 左滑时内容向右移动显示）。  
  Horizontal scrolling direction is corrected for more intuitive behavior (e.g., Magic Mouse swipe-left moves content to the right).  
  _HistoryListView.swift_  

### 修复 / Fixes
- **Swift 6 编译问题修复**  
  修复多处并发捕获、主线程隔离访问与缺失 `await` 导致的编译错误/警告；并对关键路径做“最小侵入”的隔离调整，尽量不改变既有行为。  
  Fixes multiple Swift 6 build issues related to concurrency captures, main-actor isolation, and missing `await`, using minimal-intrusion adjustments to preserve behavior.  
  _BlobStorage.swift_ _DataExportService.swift_ _DeckDataStore.swift_ _SearchRuleFilters.swift_ _ClipItemCardView.swift_ _StorageMaintenanceService.swift_ _DeckSQLManager.swift_  
- **超长文本导致的卡顿风险降低**  
  Base64 探测与解码移出主线程，并加入快速否决与长度上限，减少滚动/搜索场景的掉帧。  
  Reduces stalls from extremely long content by moving Base64 checks/decoding off the main thread with fast rejects and hard limits.  
  _ClipItemCardView.swift_ _ClipboardItem.swift_  
- **颜色卡片兼容富文本来源**  
  颜色解析优先从纯文本内容提取并自动 trim，来自 RTF/RTFD 的复制内容也能正确显示色块。  
  Color parsing now prefers trimmed plain text, fixing cases where RTF/RTFD sources failed to render the color swatch.  
  _ClipboardItem.swift_  
- **剪贴板 URL 清理更保守**  
  清理 URL 时保留原有粘贴板类型，并新增复制大小上限，降低异常内容带来的风险。  
  URL sanitization now preserves original pasteboard types and enforces a copy size limit to reduce risk from abnormal content.  
  _ClipboardService.swift_  
- **粘贴失败不再“清空剪贴板”**  
  paste 失败时恢复原剪贴板快照，避免异常情况下用户剪贴板内容被意外清空。  
  Restores the original pasteboard snapshot when paste fails, preventing accidental clipboard clearing.  
  _ClipboardService.swift_  
- **维护功能相关稳定性修复**  
  修复维护流程中的并发隔离访问、SQLite 表达式运算符缺失与压缩流初始化问题。  
  Fixes maintenance flow issues including actor-isolation access, missing SQLite expression operators, and compression stream initialization.  
  _StorageMaintenanceService.swift_ _DeckSQLManager.swift_  
- **维护快照：过期计时“可取消即返回” + 重活移出 MainActor**  
  过期倒计时改为取消即返回，避免“取消=立刻过期”的误行为；同时将“扫描缺失文件/删除 blob”等重活从 `MainActor` 移出，降低维护期间 UI 受影响的概率。  
  Make snapshot expiry timers cancel-safe (cancel returns immediately) to avoid “cancel == expire now”; also move missing-file scans and blob deletion work off `MainActor` to reduce UI impact during maintenance.  
  _StorageMaintenanceService.swift_  
- **维护快照：并发隔离修复（4 处）**  
  在 `MainActor` 上快照 `ClipboardItem` 的 id/paths，将文件存在性检查移回后台；Blob 删除改回 `MainActor`，消除并发隔离相关的 4 处编译错误。  
  Fixes 4 concurrency-isolation build errors in maintenance snapshots by snapshotting `ClipboardItem` id/paths on `MainActor`, moving file-existence checks back to background work, and running blob deletions on `MainActor`.  
  _StorageMaintenanceService.swift_  
- **LAN 日志调用的并发隔离修复**  
  将 `log.warn` 放到 `MainActor` 的 `Task` 中执行，避免在 `nonisolated` 上下文直接访问主线程隔离的 logger，消除并发隔离编译报错。  
  Runs `log.warn` inside a `MainActor` task to avoid accessing the main-actor-isolated logger from a `nonisolated` context, fixing a concurrency-isolation build error.  
  _MultipeerService.swift_  
- **搜索防抖任务不再触发 Swift 6 捕获告警**  
  搜索防抖 `Task` 固定在 `MainActor` 上创建与运行，避免 Swift 6 `@Sendable` 捕获警告。  
  Pins the search debounce `Task` to `MainActor` to avoid Swift 6 `@Sendable` capture warnings.  
  _DeckViewModel.swift_  
- **窗口关闭后的清理逻辑主线程化**  
  关闭窗口后清理过期数据改为 `MainActor` `Task` 执行，避免跨隔离访问引发的不稳定行为。  
  Runs post-close expired-data cleanup as a `MainActor` task to avoid cross-isolation access and subtle instability.  
  _MainWindowController.swift_  
- **Orbit token 目录兜底，避免崩溃**  
  当 token 目录取不到时回退到 `Caches` / 临时目录，避免 `first!` 触发崩溃。  
  Adds a fallback to `Caches`/temporary directories when the token folder is unavailable, preventing a `first!` crash.  
  _OrbitBridgeAuth.swift_  
- **数据库错误监听补齐并正确移除**  
  补存 `.databaseError` observer，并在 `applicationWillTerminate` 里一并移除（含 pause/orbit），避免泄漏与重复回调。  
  Adds the missing `.databaseError` observer and removes all related observers on `applicationWillTerminate` (including pause/orbit) to avoid leaks and duplicate callbacks.  
  _AppDelegate.swift_  
- **Debug 预览拼接避免无谓开销**  
  debug 预览拼接改为 `log.isEnabled(.debug)` 保护，并新增 `isEnabled(_:)` 接口，避免在非 debug 场景做字符串拼接与格式化。  
  Guards debug preview string building behind `log.isEnabled(.debug)` and adds an `isEnabled(_:)` API to avoid unnecessary string formatting when debug logging is off.  
  _AppLogger.swift_ _DeckDataStore.swift_ _HistoryListView.swift_  
- **本地化覆盖率问题修复**  
  补齐缺失翻译并清理无引用 key，提升各语言的完整性与一致性。  
  Fixes localization coverage by filling missing translations and removing stale, unreferenced keys.  
  _Localizable.xcstrings_  
- **搜索规则解析错位修复（`size:`/`len:`）**  
  规则解析支持 `size:`/`len:` 兼容匹配，并返回真实前缀长度，避免 token 解析错位导致的体验问题。  
  Rule parsing supports `size:`/`len:` compatibility and returns the real prefix length to avoid token offset drift.  
  _SearchRuleFilters.swift_  
- **设置页：过期计时“取消即返回”**  
  UI 侧的过期倒计时逻辑同步改为取消即返回，避免清理/撤回交互中被误触发。  
  Mirrors the same cancel-safe expiry timer behavior in the Settings UI to avoid accidental triggers during cleanup/rollback interactions.  
  _SettingsView.swift_  

### 说明 / Notes
- **关于页版权信息**  
  “关于”页底部版权优先读取 `NSHumanReadableCopyright`，并保留原文本作为兜底。  
  The About page now prefers `NSHumanReadableCopyright` for the footer, with a fallback to the previous text.  
  _SettingsView.swift_  
- **`lang:` 规则为 Beta**  
  `lang:` 需要进行语言检测，数据量很大时仍可能带来额外开销；规则选择器已提供提示。  
  `lang:` is Beta and may add overhead on very large datasets due to language detection; the rule picker includes a warning.  
  _SearchRulePickerView.swift_ _Localizable.xcstrings_  

### 升级建议 / Upgrade Notes
- **推荐升级到 v1.2.4**  
  如果你在历史浏览/搜索时遇到滚动掉帧或卡顿，本版本的优化收益最明显，强烈推荐更新。
  Recommended if you experience scrolling/search stalls.  
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

### 新增 / Added
- **搜索规则过滤（/ 规则）**  
  重磅功能：在搜索框输入 / 即弹出规则面板（固定在搜索框上方）。列表模式显示 6 个规则，↑↓ / j/k / 1–6 切换高亮，回车插入前缀（app/date/type 或 -app/-date/-type），Esc 关闭面板。插入后光标停在前缀后，可直接输入值；空格结束该值并继续输入搜索词，/ 可继续叠加下一条规则；支持 + 多值与引号包裹含空格的应用名。Delete/Backspace 位于前缀或值边界时会整段删除规则（含值与尾随空格），提示模式下 Esc 也会删除当前规则并回到搜索。  
  Major feature: type / in the search box to open the rule panel above the field. The list mode shows 6 rules; navigate with ↑↓ / j/k / 1–6, press Enter to insert a prefix (app/date/type or -app/-date/-type), and Esc closes the panel. After insertion, the cursor stays after the prefix for immediate value input; Space ends the value and continues keywords, / chains another rule; supports + multi-values and quoted app names with spaces. Delete/Backspace at the prefix/value boundary removes the whole rule (value + trailing space), and Esc in hint mode deletes the current rule and returns to search.  
  _SearchRuleFilters.swift_, _TopBarView.swift_, _TokenSearchTextView.swift_, _SearchRulePickerView.swift_, _SearchRulePickerPanelController.swift_, _DeckViewModel.swift_, _Localizable.xcstrings_  
  ![搜索规则弹窗（1379×776）](https://github.com/user-attachments/assets/b5166844-d693-47db-8719-9d02bd8cf8b0)  
  ![搜索规则提示（1262×709）](https://github.com/user-attachments/assets/38da8c37-aed0-4b4d-b9a7-61af490c9ea5)

- **自定义标题（端到端）**  
  支持为每条记录设置自定义标题，贯通模型、存储、搜索与 UI，并在卡片/预览头部显示。  
  Add per-item custom titles across model, storage, search, and UI, shown in card/preview headers.  
  _DeckSQLManager.swift_, _ClipboardItem.swift_, _DeckDataStore.swift_, _SearchService.swift_, _ClipItemCardView.swift_

- **自定义标题同步与导出**  
  自定义标题会随同步、导出与快捷指令流转，保证跨设备一致。  
  Custom titles now flow through sync, export, and intents for cross-device consistency.  
  _CloudSyncService.swift_, _DataExportService.swift_, _DeckIntents.swift_

- **智能规则新增“有自定义标题”条件**  
  Smart Rules 可按“有自定义标题”筛选，并在编辑器中可选。  
  Smart Rules now include a “has custom title” condition selectable in the editor.  
  _SmartRuleService.swift_, _SmartRulesView.swift_, _Localizable.xcstrings_

- **Figma 剪贴板识别与专用预览**  
  识别 Figma 剪贴板内容，卡片与预览展示专用图标/信息视图，并仅在预览打开时解析。  
  Recognize Figma clipboard payloads with dedicated card/preview UI and parse only when the preview opens.  
  _ClipboardItem.swift_, _ClipItemCardView.swift_, _FigmaClipboardRenderService.swift_, _FigmaClipboardPreviewView.swift_, _PreviewWindowController.swift_

- **链接二维码入口**  
  预览底部信息条新增“显示二维码”按钮（仅链接项显示），行为与右键菜单一致。  
  Add a “Show QR Code” button in the preview info bar for links, matching the context menu behavior.  
  _PreviewWindowController.swift_

- **设置直达“局域网”栏目**  
  “前往设置添加设备”改为直达“局域网”页，并引入共享的设置导航状态。  
  “Go to Settings to add a device” now opens the LAN tab via shared settings navigation state.  
  _SettingsView.swift_, _SettingsWindowController.swift_, _ClipItemCardView.swift_

- **模拟键盘输入粘贴开关 + 自定义快捷键**  
  新增开关与可配置快捷键（默认 ⌘⌥V），关闭后不再拦截该组合键。  
  Add a toggle and configurable hotkey (default ⌘⌥V); when off, the combo is no longer intercepted.  
  _UserDefaultsManager.swift_, _HotKeyManager.swift_, _PasteQueueService.swift_, _SettingsView.swift_, _Localizable.xcstrings_

- **文件缺失提示与自动清理**  
  文件/图片缺失时显示警告提示，并在面板关闭后自动清理缺失记录。  
  Show missing-file warnings and auto-purge missing items after the panel closes.  
  _ClipboardItem.swift_, _ClipItemCardView.swift_, _PreviewOverlayView.swift_, _PreviewWindowController.swift_, _DeckDataStore.swift_, _MainWindowController.swift_

### Deck × Orbit
- **Orbit 摘要携带自定义标题**  
  Orbit 摘要输出包含 customTitle，保持 CLI/集成一致。  
  Orbit summaries now include customTitle for consistent CLI/integration output.  
  _OrbitCLIBridgeService.swift_

### 优化 / Improvements
- **搜索框与标签编辑快捷键**  
  搜索框支持 ⌘A 全选与 ⌘V 粘贴（仅在有搜索内容时全选），标签编辑也支持 ⌘A/⌘V。  
  Search supports ⌘A select-all (only with a non-empty query) and ⌘V paste; tag editing also supports ⌘A/⌘V.  
  _HistoryListView.swift_, _TopBarView.swift_, _DeckViewModel.swift_

- **搜索焦点与输入调度优化**  
  面板打开时抑制自动抢焦点，重命名期间不触发自动搜索；关键 UI 调度提升为 userInteractive。  
  Suppress auto-focus on panel open, avoid auto-search during rename, and elevate UI dispatch to userInteractive.  
  _MainWindowController.swift_, _HistoryListView.swift_, _TopBarView.swift_, _DeckViewModel.swift_

- **Figma 预览与图标细节**  
  Figma 预览改为两列布局、信息更简洁并支持多语言；暗黑模式下图标自动反白。  
  Figma preview uses a two-column layout with simplified localized info, and auto-inverts the icon in dark mode.  
  _FigmaClipboardPreviewView.swift_, _FigmaClipboardRenderService.swift_, _ClipItemCardView.swift_, _Localizable.xcstrings_

- **链接元数据缓存优化**  
  LinkMetadataService 加入 LRU + 上限（500），并在命中时刷新顺序以降低内存。  
  Add an LRU cache with a 500-item cap for link metadata and refresh order on hits to reduce memory.  
  _LinkPreviewCard.swift_

- **数据库备份一致性**  
  WAL checkpoint 与文件复制在同一 dbQueue 执行，避免备份期间写入穿插导致不一致。  
  Run WAL checkpoint and file copy in the same dbQueue to avoid inconsistent backups during writes.  
  _DeckSQLManager.swift_

### 变更 / Changes
- **标题长度上限与显示策略**  
  自定义标题限制为 12 个字符（保存时截断），标题过长会自动缩放以适配卡片头部。  
  Custom titles are capped at 12 characters (trimmed on save) and auto-scale to fit the header.  
  _ClipItemCardView.swift_, _Constants.swift_

- **搜索排序与匹配规则**  
  搜索会同时匹配自定义标题；标题命中项会稳定置顶，但保留原有排序。  
  Search now matches custom titles; title hits are stably promoted to the front without reordering within groups.  
  _DeckDataStore.swift_, _SearchService.swift_

- **标题重命名触发规则重评估**  
  保存标题后会重新评估智能规则，但 ignore/transform 仍仅在入库时触发。  
  Renaming a title re-evaluates Smart Rules, while ignore/transform actions remain ingestion-only.  
  _DeckDataStore.swift_

- **规则语法识别范围**  
  仅 / 插入的规则前缀会被解析，手动输入 app:/date:/type: 会视为普通搜索文本。  
  Only rule prefixes inserted via / are parsed; manually typed app:/date:/type: is treated as plain text.  
  _SearchRuleFilters.swift_, _TopBarView.swift_, _TokenSearchTextView.swift_

- **规则语义扩展**  
  规则支持 -app/-date/-type 排除与 + 多值叠加；type 去掉 email/phone，新增 color；app 多词需引号。  
  Rules now support -app/-date/-type exclusion and + multi-values; type drops email/phone and adds color; multi-word app names require quotes.  
  _SearchRuleFilters.swift_, _Localizable.xcstrings_, _DeckViewModel.swift_

- **模拟键盘粘贴换行策略**  
  模拟键盘输入粘贴遇到换行时改为发送 Shift+Enter，避免直接回车提交。  
  Simulated typing paste sends Shift+Enter for newlines instead of a direct Return.  
  _PasteQueueService.swift_

- **Focus 模式内容记录**  
  专注模式不再仅记录文本，富文本/文件/图片也会被保留。  
  Focus mode no longer records only text; rich text, files, and images are retained.  
  _ClipboardService.swift_

- **Figma 记录不进入搜索**  
  新产生的 Figma 记录不写入搜索文本，避免污染搜索结果。  
  New Figma entries no longer write search text to avoid polluting search results.  
  _ClipboardService.swift_

### 修复 / Fixes
- **SQL LIKE 可选值类型错误**  
  通过 IFNULL 处理 custom_title，避免 .like 的可选类型导致 Expression<Bool> 报错。  
  Wrap custom_title with IFNULL to keep .like as Expression<Bool> and avoid optional-type errors.  
  _DeckDataStore.swift_

- **重命名输入状态与焦点问题**  
  修复重命名时跳入搜索框、Esc 失效与关闭面板残留输入框；回车保存后 UI 立即刷新标题。  
  Fix rename focus jumps, Esc failures, and lingering edit fields on close; Enter now updates the title immediately in UI.  
  _DeckViewModel.swift_, _ClipItemCardView.swift_, _HistoryListView.swift_, _MainWindowController.swift_

- **file:// 解析与安全处理**  
  统一 file:// 归一化与本地解析逻辑，避免路径含空格解析失败，并移除不安全的 propertyList 回退。  
  Normalize and locally resolve file:// paths to handle spaces, and remove the unsafe propertyList fallback.  
  _Extensions.swift_, _ClipboardItem.swift_, _ClipboardService.swift_, _PreviewWindowController.swift_

- **文件/图片粘贴与缩略图稳定性**  
  修复 fileURL 大小计算错误、缩略图对不存在文件的生成，以及大图安全读取与去重。  
  Fix fileURL size calculation, skip thumbnails for missing files, and harden large-image reads and de-dup.  
  _ClipboardItem.swift_, _PreviewOverlayView.swift_, _ClipItemCardView.swift_

- **搜索规则输入与索引崩溃**  
  修复规则前缀带空格失效、UTF-16/Emoji 索引崩溃与删除范围不完整的问题。  
  Fix rule prefixes with trailing spaces, UTF-16/emoji index crashes, and incomplete delete ranges.  
  _SearchRuleFilters.swift_, _TopBarView.swift_, _TokenSearchTextView.swift_

- **搜索分页与缓存一致性**  
  修复新搜索未取消旧分页导致结果混入，并在结果不足时自动扩容拉取。  
  Fix result mixing from stale pagination and auto-expand fetches when results are insufficient.  
  _DeckDataStore.swift_

- **并发与主线程隔离编译报错**  
  修复 Swift 6 并发/隔离相关编译问题，包括主线程调用、非隔离上下文访问与必要 await。  
  Resolve Swift 6 concurrency/isolation compile errors, including main-thread access, nonisolated calls, and required awaits.  
  _PreviewWindowController.swift_, _SteganographyService.swift_, _BlobStorage.swift_, _DataExportService.swift_, _DeckDataStore.swift_, _SearchService.swift_, _DeckSQLManager.swift_

- **安全与稳定性修补**  
  防止 TOTP 计数下溢、停止在 UserDefaults 存 PSK、补齐 blob 文件回收与目录创建保护。  
  Prevent TOTP underflow, stop persisting PSK in UserDefaults, and tighten blob cleanup and directory creation.  
  _MultipeerService.swift_, _DirectConnectService.swift_, _DeckDataStore.swift_, _BlobStorage.swift_, _DirectConnectService.swift_

- **搜索缓存失效与内存压力**  
  标题/OCR 更新仅失效对应缓存，内存压力时正确清空缓存，避免旧结果残留。  
  Invalidate cache per updated item (title/OCR) and clear properly on memory pressure to avoid stale results.  
  _SearchService.swift_, _DeckDataStore.swift_

- **拖拽临时文件可靠性**  
  拖拽回退为同步生成临时文件，确保拖拽可用，并引入统一临时目录与自动清理。  
  Revert drag export to synchronous temp file creation for reliability, with unified temp storage and auto cleanup.  
  _TemporaryFileManager.swift_, _ClipItemCardView.swift_

- **Figma 解析鲁棒性**  
  增强 Figma HTML 容错解码与缓存策略，解析失败不再永久缓存为 false，并记录更清晰日志。  
  Improve tolerant HTML decoding and caching for Figma payloads, avoiding permanent false caches and adding clearer logs.  
  _UnsupportedPasteboardPayload.swift_, _ClipboardItem.swift_

- **设置与预览细节修补**  
  补齐 SettingsView.swift 的 Combine 引入与二维码按钮点击区域/间距修正。  
  Fix missing Combine import in SettingsView.swift and refine QR button hit area/spacing.  
  _SettingsView.swift_, _PreviewWindowController.swift_

- **存储路径初始化退避**  
  存储路径初始化失败后增加 60 秒退避，避免重复重试风暴。  
  Add a 60s backoff after storage path init failures to avoid retry storms.  
  _DeckSQLManager.swift_

### 说明 / Notes
- **规则提示已全面本地化**  
  规则提示/帮助文案覆盖德/英/法/日/韩/繁体/简体，并统一说明“输入值后空格继续搜索词，/ 添加下一规则”。  
  Rule hints/help text are localized across DE/EN/FR/JA/KO/zh-Hant/zh-Hans with consistent guidance on spacing and chaining.  
  _Localizable.xcstrings_

### 兼容性与行为说明 / Compatibility & Behavior Notes
- **规则使用示例**  
  示例：`app:\"Google Chrome\"+Safari -type:code+text -date:26-01-01+26-01-02`（+ 多值，- 排除）。  
  Example: `app:\"Google Chrome\"+Safari -type:code+text -date:26-01-01+26-01-02` (+ multi-values, - exclusion).  
  _SearchRuleFilters.swift_

- **Figma 预览范围**  
  当前仅展示基础信息列表，不进行图形/元素渲染。  
  The Figma preview currently shows basic info only, without rendering graphics/elements.  
  _FigmaClipboardPreviewView.swift_

### 升级建议 / Upgrade Notes
- **数据库迁移与索引重建**  
  升级后会迁移 SQLite 并重建 FTS，以支持自定义标题搜索；首次启动请等待索引完成。  
  Upgrade migrates SQLite and rebuilds FTS for custom-title search; allow time for initial indexing.  
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

### 新增 / Added
- **新增多语言：法语 / 韩语 / 日语**  
  Deck 增加法语、韩语、日语的多语言支持。  
  Deck adds French, Korean, and Japanese localization support.

- **新增反馈邮件撰写入口（关于设置 + 剪贴板面板顶部）**  
  在“关于”设置页新增「提交反馈」，并在剪贴板面板顶部栏加入反馈按钮；使用内置 HTML 模板并注入系统/应用诊断信息与本地化标签。  
  Added a feedback email composer and wired it into About settings and the clipboard panel top bar, using a bundled HTML template with live system/app diagnostics and localized labels.  
  _FeedbackEmailService.swift · SettingsView.swift · TopBarView.swift · feedback.html · Localizable.xcstrings_

- **新增反馈邮件多语言模板 + 工单号**  
  反馈邮件会根据 `Locale.preferredLanguages` 选择 `feedback_en` / `feedback_de` / `feedback_kr` / `feedback_fr` / `feedback_ja` / `feedback_zh_hant` / `feedback` 模板，并且每次生成随机 UUID 工单号。  
  Feedback email now selects a localized HTML template based on `Locale.preferredLanguages` and generates a random UUID ticket ID each time.  
  _FeedbackEmailService.swift · feedback_en.html · feedback_de.html · feedback_kr.html · feedback_fr.html · feedback_ja.html · feedback_zh_hant.html_

- **设置侧边栏 Tab/Shift+Tab 循环切换**  
  在设置窗口中支持 Tab/Shift+Tab 在左侧侧边栏标签间循环切换（含 wrap-around），且仅在无 Command/Control/Option 修饰键时生效。  
  Added Tab/Shift+Tab cycling with wrap-around for the settings sidebar, scoped to the settings window and only when no Command/Control/Option modifiers are held.  
  _SettingsView.swift_

- **新增 Cmd+Option+V「键盘逐字输入粘贴」**  
  新增全局 Cmd+Option+V：从系统剪贴板读取 string/rtf/rtfd/html 文本并用 CGEvent 逐字符输入（带轻微延迟以提升远程会话稳定性），适合 VNC 等不支持普通粘贴的场景；无辅助功能权限时不拦截按键。  
  Added global Cmd+Option+V “typing paste”: reads string/rtf/rtfd/html from the system pasteboard and types characters via CGEvent with a slight delay for remote-session stability (e.g., VNC); does not intercept the shortcut without Accessibility permission.  
  _PasteQueueService.swift_

- **修复键盘逐字输入的参数标签编译错误**  
  为 `keyboardSetUnicodeString` 调用补上 `stringLength:` 标签，消除编译错误。  
  Fixed a compile error by adding the `stringLength:` label to `keyboardSetUnicodeString` calls.  
  _PasteQueueService.swift_

- **Orbit 设置页与独立 Orbit 窗口集成**  
  新增 Orbit 设置页（引导/已安装/安装中等阶段）、Option 键交互、Orbit 窗口显示/隐藏与安装进度流；并将独立 Orbit 应用代码整合到 `Deck/Deck/Orbit`，使用其 window controller 管理独立环形窗口。  
  Added the Orbit settings tab UI (intro/guide/installed stages), option-key handling, Orbit window show/hide, and install progress flow; integrated standalone Orbit app code under `Deck/Deck/Orbit` and used its window controller for the separate ring window.  
  _OrbitSettingsView.swift · OrbitWindow.swift · Deck/Deck/Orbit/_

- **Orbit 安装器与资源加载**  
  实现内置图标/zip 资源的安装器与加载器，并支持安装检测；补充 Orbit 资源与纹理加载 fallback。  
  Implemented installer + resource loader for bundled icon/zip and install detection; added Orbit assets/resources and improved texture loading fallbacks.  
  _OrbitInstaller.swift · OrbitResources.swift · OrbitIcon.png · OrbitApp.zip · black_hole_texture.png · BlackHoleView.swift_

- **空间预览：多文件浏览**  
  支持在空间预览面板中浏览一个剪贴板项的多个文件（chips + 上一/下一项），并在文件之间平滑淡入淡出；每个文件可选择 PDF/Markdown/Office/Image 或不支持时的 fallback。  
  Implemented a multi-file preview flow in the space preview panel so a clipboard item with multiple files can be browsed in order, with per-file preview selection and a smooth fade between files.  
  _PreviewWindowController.swift_

### Deck × Orbit
- **Orbit 组件移植与模型冲突修正**  
  移植 Magic Keyboard 片段组件，调整 Option 键视觉，并解决剪贴板模型命名冲突；完善 ring 相关 view model 与分享/卡片等联动。  
  Ported the Magic Keyboard snippet component, adjusted Option key visuals, and resolved clipboard model name conflicts across ring-related models/services/views.  
  _OrbitMagicKeyboardView.swift · OrbitClipboardModels.swift · ClipboardRingViewModel.swift · ClipboardShareService.swift · ClipboardCardView.swift_

- **Orbit CLI Bridge 服务线程模型与保护**  
  Orbit CLI Bridge 请求处理不再整段 `@MainActor`；仅在必须操作（如 paste）切主线程，JSON 编码与响应在后台完成；增加高阈值速率限制与响应体上限（20MB）防止极端负载拖慢 UI。  
  Orbit CLI Bridge service avoids running the whole request pipeline on `@MainActor`; only switches to main for required UI operations (e.g. paste), keeps JSON encoding/responses off-main, and adds rate limiting plus a 20MB response cap to protect UI smoothness under load.  
  _OrbitCLIBridgeService.swift_

### 优化 / Improvements
- **CLI Bridge 代码块悬停复制按钮**  
  CLI Bridge 代码块右上角新增悬停态复制图标；仅当鼠标进入代码块时显示，点击使用 `NSPasteboard` 复制命令。  
  Added a hover-only copy icon in CLI Bridge code blocks (top-right overlay) and copy via `NSPasteboard` so it only shows when the cursor is inside the code block.  
  _CLIBridgeSettingsView.swift_

- **脚本插件创建代码块支持悬停复制**  
  在“创建脚本插件”的代码块右上角加入与 CLI Bridge 相同的复制按钮（悬停显示、点击线条动画变对勾）；新增 `CodeBlockView` 并替换两处代码片段为可复制样式，同时引入 AppKit 以使用剪贴板。  
  Added the same hover-copy button used in CLI Bridge to the “Create Script Plugin” code blocks (hover-only, line animation to checkmark); introduced `CodeBlockView`, replaced two code snippets with copyable blocks, and imported AppKit for pasteboard access.  
  _ScriptPluginsSettingsView.swift_

- **局域网 IP 复制按钮采用 CLI Bridge 动画样式**  
  Local Network IP 的复制按钮改为复用 CopyIconButton，并使用 CLI Bridge 同款 doc→check 动画与时序，同时保留原有强调色。  
  Updated the Local Network IP copy button to use the CLI Bridge–style animated doc→check icon with the same timing while keeping the accent color, by replacing the inline button with a reusable `CopyIconButton`.  
  _LANSharingSettingsView.swift_

- **“添加设备”按钮改为明确 CTA 样式**  
  “添加设备”按钮改为全宽强调填充、半粗体标签，并完善禁用态样式，使其不再像输入框。  
  Updated the “Add Device” button to read as a real CTA (full-width accented fill, semibold label, and disabled styling) so it no longer resembles an input field.  
  _LANSharingSettingsView.swift_

- **已连接设备空态优化**  
  移除“已连接设备”的加载提示与圈圈，空态改为多语言文案「暂无已连接的 Deck 设备」。  
  Removed the loading text/spinner from the “Connected Devices” section and replaced the empty state with a localized “No connected Deck devices” message.  
  _LANSharingSettingsView.swift_

- **面板动画更顺滑：延后重载与保留热缓存**  
  将数据 reload 延后到面板滑入动画完成后执行；关闭时不再完全清空列表而是保留少量 warm cache，避免动画与 DB/SwiftUI 重建竞争（UI 文件保持不改动）。  
  Moved data reload to run after the panel slide animation finishes, and changed close behavior to keep a small warm cache instead of fully purging, so animation doesn’t compete with heavy DB + SwiftUI rebuilds (UI files left untouched).  
  _MainWindowController.swift · DeckDataStore.swift_

- **面板动画与 Reduce Motion 细节打磨**  
  Reduce Motion 下强制动画时长为 0；hide 使用 `easeIn`、show 保持 `easeOut`；动画结束后移除残留动画状态。  
  Reduce Motion now forces duration 0; hide uses `easeIn` while show stays `easeOut`, and the slide animation is removed on completion to avoid residual state.  
  _MainViewController.swift_

- **弹出面板视觉统一**  
  增加弹出面板圆角、减少顶部间距，使整体观感更和谐统一。  
  Added popup panel corner radius and reduced top spacing for a more cohesive visual appearance.

- **弹出动画路径优化与旧系统 blur 降负担**  
  将重活移出 present 动画；简化 Spaces 行为；present easing 调整为更柔和的 `easeInEaseOut`；在较旧的 macOS 上移除多余的 behind-window blur（避免双层 blur）。  
  Optimized popup animation by moving heavy work out of the present animation, simplifying Spaces behavior, using gentler `easeInEaseOut` easing, and removing extra behind-window blur on older macOS to avoid double-blur work.  
  _MainWindowController.swift · MainViewController.swift · DeckContentView.swift_

- **数据准备更早提交，减少动画后抖动**  
  将“提交 UI”的时机提前到准备好就提交，让更新可发生在动画过程中；同时避免 `setPanelActive` 用缓存覆盖刚提交结果。  
  Submits UI updates as soon as data is ready (during animation) and prevents `setPanelActive` from overwriting freshly committed results via cache.  
  _DeckDataStore.swift · MainWindowController.swift_

- **历史列表初始选择更稳定，减少末尾闪动**  
  `resetInitialSelection(force:)` 增加 `force` 参数；上下文感知开启时切换应用后在 `refreshDisplayItems(...)` 后强制重置选择；并通过 `guard selectedId == nil` 避免后续提交/重排反复触发选中导致“末尾闪两下”。  
  Improved initial selection stability by adding `resetInitialSelection(force:)`, forcing selection reset after app switches when context-aware mode is on, and guarding on `selectedId == nil` to prevent repeated selection during commits/reorders.  
  _HistoryListView.swift_

- **搜索/粘贴/写入路径性能优化（UX 不变）**  
  大图 blob 写入改为异步存储以避免 UI 相关流程同步 IO；搜索 lowercasing 做上限并避免额外分配；粘贴板字符串只取一次，银行卡检测单次扫描并尽早退出。  
  Applied UX-neutral performance optimizations: large image blob writes now store asynchronously to avoid sync IO on UI-driven flows; search lowercasing is capped and avoids extra allocations; pasteboard string fetched once and bank-card detection is single-pass with early exit.  
  _DeckSQLManager.swift · SearchService.swift · ClipboardService.swift_

- **热路径最小化优化（保持交互与行为一致）**  
  SearchService 增加跨击键的 `prepareLowercasedText` 有界缓存与安全 range 转换、在安全模式/会话退到后台时失效缓存，并暴露 `clearPreparedTextCache()` 供内存压力清理；SmartContentCache 增加 inflight 去重、将 CPU 工作移到 detached task、避免竞态覆盖缓存，并在失效/清理/内存压力时取消 inflight；Cursor Assistant 将数字键映射提升为静态以减少每次事件分配；内存压力处理联动清理 SearchService 缓存。  
  Applied minimal, interaction-neutral optimizations across hot paths: SearchService adds a bounded cross-keystroke cache for `prepareLowercasedText`, safe range conversion, security-mode/session-resign cache invalidation, and exposes `clearPreparedTextCache()` for memory pressure; SmartContentCache adds inflight dedupe, moves CPU work to a detached task, avoids cache overwrites on races, and cancels inflight tasks on invalidation/clear/memory pressure; Cursor Assistant lifts the numeric key map to static; memory pressure now clears SearchService cache.  
  _SearchService.swift · SmartContentCache.swift · CursorAssistantService.swift · DeckDataStore.swift_

- **剪贴板检查合并与 OCR 读取优化**  
  合并重叠的剪贴板检测，`nil` item 也会消费 `changeCount`；为 CLI 预热 recent cache；OCR 避免全量 blob 读取。  
  Coalesced overlapping clipboard checks, consumed `changeCount` on nil items, warmed recent cache for CLI, and avoided full blob reads for OCR.  
  _ClipboardService.swift · DeckDataStore.swift · OCRService.swift_

- **设置窗口 Auto Layout 循环缓解**  
  通过在普通容器视图中承载 SwiftUI，缓解设置窗口的 Auto Layout loop。  
  Mitigated the settings window Auto Layout loop by hosting SwiftUI in a plain container view.  
  _SettingsWindowController.swift_

### 变更 / Changes
- **反馈邮件撰写：不再走 `mailto`，优先系统邮件撰写器**  
  反馈邮件流程不再使用会拉起浏览器的 `mailto`；始终优先用 `NSSharingService` 打开系统邮件撰写器；模板读取失败时也会打开邮件并填入纯文本占位，避免空页面；仅当服务不可用时才尝试打开 Mail 应用本身。  
  Feedback email no longer uses `mailto` (browser-triggering); it now prefers composing via `NSSharingService` and falls back to plain-text content if template loading fails to avoid a blank email; only tries opening the Mail app itself when the service is unavailable.  
  _FeedbackEmailService.swift_

- **设置布局重整与侧边栏顺序调整**  
  隐私相关项仅保留在「隐私」，通用行为开关集中到「通用」；同时调整侧边栏标签顺序（将隐私/安全/存储/统计置于功能标签之前，并按“上下文感知 > 智能规则 > Cursor Assistant > … > 统计 > Orbit > 关于”排序）。  
  Reorganized settings so privacy items live only under Privacy and general behavior toggles live under General, and reordered the sidebar tabs to a more logical grouping/order (context-aware before smart rules, Cursor Assistant under it, Statistics near the bottom with Orbit below, About last).  
  _SettingsView.swift · PrivacySettingsView.swift_

- **设置侧边栏顺序微调（Smart Rules / Cursor Assistant）**  
  侧边栏顺序更新为 Smart Rules 紧跟 Context Aware；同时让 Cursor Assistant 与 Template Library 相邻；顺序由 `SettingsTab` 的声明顺序与 `SettingsTab.allCases` 驱动。  
  Moved the settings sidebar order so Smart Rules now sits directly under Context Aware, and Cursor Assistant is adjacent to Template Library; order is driven by `SettingsTab` declaration order and `SettingsTab.allCases`.  
  _SettingsView.swift_

- **标准快捷键卡片新增 ⌘⌥V 说明与本地化**  
  在标准快捷键卡片新增 ⌘⌥V 行，并增加“模拟键盘逐字输入粘贴”的提示文案；补齐德/英/法及其他已有语言的翻译。  
  Added the ⌘⌥V row and a hint about simulated keyboard-typing paste in the Standard Shortcuts card, with full localization coverage (DE/EN/FR and existing locales).  
  _SettingsView.swift · Localizable.xcstrings_

- **移除 Focus 监测/恢复逻辑与相关依赖**  
  移除 Focus 轮询/监测相关定时器与恢复逻辑，并清理 Focus 状态权限/查询的辅助方法与 Intents 依赖。  
  Removed Focus polling/monitor timers and restore logic, and cleaned up Focus status helpers and Intents dependencies.  
  _AppDelegate.swift · DeckIntents.swift_

- **默认脚本插件更新与清理策略调整**  
  默认脚本逻辑为“先清理旧的默认插件，再写入新的默认插件（保留字数统计）”，且只会删除/覆盖作者为 Deck 的默认脚本以避免误伤用户自定义脚本；启动时清理旧默认目录（base64-encode/base64-decode/url-encode/url-decode/json-format）；新默认包含「字数统计 / 去除表情符号 / 去除 Markdown / 去空行 / 提取 URL / 提取邮箱 / 行号前缀」；新增 JSContext 桥接 `Deck.detectEmails`，内部调用 `SmartTextService.shared` 识别逻辑；去表情符号使用 Unicode emoji 匹配（含变体选择符/ZWJ），去 Markdown 移除常见语法与 HTML 标签并保留纯文本。  
  Default scripts now clean old defaults before writing new ones (keeping Word Count) and only delete/overwrite Deck-authored defaults to avoid touching user scripts; startup clears old default directories (base64-encode/base64-decode/url-encode/url-decode/json-format). The new defaults include Word Count, Remove Emoji, Remove Markdown, Remove Empty Lines, Extract URL, Extract Emails, and Line Number Prefix. Added a JSContext bridge `Deck.detectEmails` that calls `SmartTextService.shared` detection; emoji removal uses Unicode emoji matching (including variation selectors/ZWJ), and Markdown removal strips common syntax + HTML tags while keeping plain text.  
  _ScriptPluginService.swift_

- **Deck × Orbit 文案全面本地化**  
  Deck × Orbit 页面所有可见文案改为 `NSLocalizedString`，并补齐缺失词条「欢迎使用」的多语言翻译。  
  All visible strings on the Deck × Orbit page are now localized via `NSLocalizedString`, and the missing “Welcome” entry has been added to the string catalog.  
  _OrbitSettingsView.swift · Localizable.xcstrings_

- **设置项归属移动（保持原 UI 样式与逻辑）**  
  将“辅助功能权限”从隐私移到通用（并迁移权限刷新计时逻辑到 `SettingsView.swift`）；将“隐写密钥”从隐私移到安全并明确“用于文本隐写”，位置在安全信息之前；将“历史保留”从通用移到存储并放在存储信息之后。  
  Moved “Accessibility permission” from Privacy to General (including permission refresh timing logic), moved “Steganography key” from Privacy to Security with clearer “for text steganography” wording (before Security info), and moved “History retention” from General to Storage (after Storage info), keeping the original UI style and behavior.  
  _SettingsView.swift_

- **隐私页副标题更新并补齐多语言**  
  隐私页副标题更新为「隐私保护设置」，并补齐/同步英/德/法/日/韩/繁中翻译与新增文案。  
  Updated the Privacy page subtitle (“隐私保护设置”) and completed/synced translations for EN/DE/FR/JA/KR/zh-Hant for new/changed strings.  
  _Localizable.xcstrings_

- **字符串目录告警消除（保留翻译）**  
  通过将 7 条陈旧条目的 `extractionState` 设为 `manual`，清除 “no references” 警告且不删除翻译。  
  Cleared 7 “no references” string-catalog warnings without deleting translations by setting stale entries’ `extractionState` to `manual`.  
  _Localizable.xcstrings_

- **移除 3 条陈旧字符串键以清理 Xcode 警告**  
  删除 3 条已废弃的字符串键，避免 Xcode 报 “References to this key could not be found in source code.”：插件清单 JSON 模板、`transform(input) { return input.toUpperCase(); }` 示例片段，以及「正在搜索附近的 Deck 设备...」。  
  Removed three stale string entries to stop Xcode “References to this key could not be found in source code” warnings: the plugin manifest JSON template string, the `transform(input) { return input.toUpperCase(); }` snippet, and “正在搜索附近的 Deck 设备...”.  
  _Localizable.xcstrings_

- **Mail 启动方式切换到现代 NSWorkspace API**  
  将 `launchApplication("Mail")` 替换为通过 Mail bundle ID 的 `openApplication(at:configuration:completionHandler:)`。  
  Switched Mail launching to the modern NSWorkspace API (`openApplication(at:configuration:completionHandler:)`) via Mail’s bundle ID.  
  _FeedbackEmailService.swift_

- **Cursor Assistant「触发键」显示改为静态 Shift 键帽**  
  将“触发键”行改为静态 Shift keycap badge（不再用分段选择），匹配当前没有可选项的事实。  
  Updated the Cursor Assistant “Trigger key” row to show a static Shift keycap badge instead of a segmented selection, matching the fact there’s no choice right now.  
  _SettingsView.swift_

- **标签 Tab 循环顺序覆盖系统 + 用户标签**  
  Tab 切换改为按“系统标签 + 用户自定义标签”的完整顺序循环，越过「重要」后若存在用户标签则继续，否则回到系统标签起点；`cycleSystemTags` 现遍历 `vm.tags` 的整体顺序以支持前后循环。  
  Tab cycling now follows the full order of system + user tags, continuing to user tags after “Important” when present (otherwise wraps back to system tags); `cycleSystemTags` now iterates the overall `vm.tags` order to support forward/backward cycling.  
  _HistoryListView.swift_

### 修复 / Fixes
- **剪贴板分类误判降低（URL/电话/邮箱）与线程安全缓存**  
  更新剪贴板分类与识别逻辑，降低 URL/电话/邮箱的误判；收紧 URL 归一化并使分析缓存线程安全；同时补充 URL 边界用例测试。  
  Updated clipboard classification to reduce URL/phone/email false positives, tighten URL normalization, and make analysis caching thread-safe; added URL edge-case tests.  
  _Extensions.swift · SmartTextService.swift · ClipboardItem.swift · SmartContentCache.swift · ExtensionsTests.swift · SmartTextServiceTests.swift_

- **SmartTextService.swift 编译错误修复（保持改动收敛在单文件）**  
  将所有编译修复限定在 `SmartTextService.swift`：移除 `resourceSpecifier` 用法、修正 `Substring` trimming，并用本地 URL 归一化逻辑替换对 `asCompleteURL()` 的调用，避免在 `nonisolated` 上下文触发 MainActor 隔离问题。  
  Fixed compile errors while keeping all fixes inside `SmartTextService.swift`: removed `resourceSpecifier` usage, fixed `Substring` trimming, and replaced `asCompleteURL()` calls with a local URL normalizer to avoid main-actor isolation in nonisolated contexts.  
  _SmartTextService.swift_

- **测试修复：URL/@mention 去重与短 Swift 片段识别**  
  修复测试失败：收紧 URL/@mention 去重逻辑（URL 去重额外规范化 percent-encoding，mention 正则避开 email），改进短代码片段的 Swift 识别阈值/模式，并将假名（kana）用例改为明确断言 false 以避免 unused locals；同时将手机号去重对 `+86` 等变体做归一化。  
  Fixed test failures by tightening URL/@mention dedup (URL dedup now normalizes percent-encoding and mention regex avoids emails), improving Swift detection for short snippets, making the kana test explicitly assert false (avoids unused locals), and collapsing CN phone dedup for `+86` variants.  
  _SmartTextService.swift · ExtensionsTests.swift_

- **修正裸域名 URL 正则：避免在带 scheme 的 URL 内部再次匹配**  
  调整 bare-domain URL 正则，避免在 `http/https/ftp` 等已带 scheme 的 URL 内部再次命中导致重复。  
  Adjusted the bare-domain URL regex to avoid matching inside `http/https/ftp` URLs, which was causing duplicates.  
  _SmartTextService.swift_

- **URL 识别去重：NSDataDetector 命中时跳过额外正则扫描**  
  当 `NSDataDetector` 已识别出 URL 时，URL 检测将跳过后续正则 pass，减少重复计数与重复命中。  
  Changed URL detection to skip regex passes if `NSDataDetector` already found URLs, which should stop duplicate counts.  
  _SmartTextService.swift_

- **修复 XML/邮件识别去重：更少误判与重复计数**  
  将 XML 视为 data-like 内容，因此不再要求 `structureScore ≥ 2`；同时对 email 正则结果先做 percent-decoding 再去重，避免 `mailto` 场景重复计数。  
  XML is now treated as data-like (no longer requires `structureScore ≥ 2`), and email regex results are percent-decoded before dedup to prevent double-counting in `mailto` cases.  
  _SmartTextService.swift_

- **不支持的剪贴板兜底：避免条目被丢弃**  
  当剪贴板解析失败时构建兜底 `ClipboardItem`（使用自定义 pasteboard type 并写入本地化占位文本），历史卡片会居中显示「Deck 无法解析本剪贴板内容」。  
  Added an “unsupported clipboard” fallback so items aren’t dropped: builds a fallback `ClipboardItem` on parse failure (custom pasteboard type + localized placeholder text), and history cards render a centered “Deck 无法解析本剪贴板内容” message.  
  _ClipboardService.swift · ClipboardItem.swift · ClipItemCardView.swift · Localizable.xcstrings_

- **DirectConnect 与导入链路加固**  
  修复 DirectConnect 随机生成与接收清理；加强导入大小限制、后台插入与流式对象上限。  
  Fixed DirectConnect random generation and receive cleanup; hardened import sizing, background inserts, and streaming object limits.  
  _DirectConnectService.swift · DataExportService.swift_

- **迁移适配器 SQLite 句柄与表名查找保护**  
  为 sqlite 句柄/statement 增加 guard，并安全绑定表名查找以避免异常访问。  
  Guarded sqlite handles/statements and bound table-name lookups safely to prevent invalid access.  
  _PasteNowMigrationAdapter.swift · PasteBarMigrationAdapter.swift · MaccyMigrationAdapter.swift_

- **迁移适配器补齐 SQLITE_TRANSIENT 兼容 shim**  
  在使用 `sqlite3_bind_text` 的迁移适配器中加入本地 `SQLITE_TRANSIENT` shim，保持与 `PasteMigrationAdapter` 的用法一致，修复 “Cannot find SQLITE_TRANSIENT” 编译错误且不改变行为。  
  Added a local `SQLITE_TRANSIENT` shim in migration adapters that use `sqlite3_bind_text`, matching the pattern in `PasteMigrationAdapter` to fix the “Cannot find SQLITE_TRANSIENT” compile error without changing behavior.  
  _PasteNowMigrationAdapter.swift · PasteBarMigrationAdapter.swift_

- **Cloud Sync 数值解码规范化与插件发布线程修正**  
  统一 Cloud Sync 的数值解码；保留 group payload 的时间戳与应用名；插件列表发布切回主线程。  
  Normalized CloudSync numeric decoding, preserved group payload timestamps/app names, and moved plugin list publishing to main.  
  _CloudSyncService.swift · MultipeerService.swift · ScriptPluginService.swift_

- **多端接收元信息补齐：timestamp/appName 贯穿解码与投递**  
  扩展 `DecodedItemPayload` 包含 timestamp 与 appName，并在解码与投递路径贯通；`MultipeerService` 为 group items 写入这两项、单条使用默认值，并用其构建 `ClipboardItem`。  
  Extended `DecodedItemPayload` to include timestamp and appName, wiring them through decode and delivery; `MultipeerService` now sets these for group items, defaults them for single items, and uses the fields when building `ClipboardItem`.  
  _MultipeerService.swift_

- **生物识别类型检测更安全与 Application Support 路径兜底**  
  加强生物识别类型检测的安全性，并为 Application Support 路径增加 fallback。  
  Safer biometric type detection and an Application Support path fallback.  
  _SecurityService.swift · DeckSQLManager.swift_

- **持久化/迁移健壮性加固（不改交互体验）**  
  ManualPeer 持久化补写 psk；Multipeer `ifa_addr` 判空；ClipboardService 的 `isPaused` 过期恢复限定主线程；PasteMigrationAdapter `openDatabase` 针对 `db == nil` 提供更明确错误与关闭流程。导出改为 throwing 写入 API；加密迁移改为 id 游标分页；embedding 迁移采用批量事务；大 ID 集合查询分块以避开 SQLite 变量上限。  
  Hardened persistence/migration paths without UX changes: backfilled ManualPeer psk; guarded `ifa_addr` in Multipeer; ensured `isPaused` expiry restore runs on main; improved `openDatabase` error/close flow when `db == nil`; export writes now throw; encrypted migration uses id cursor paging; embedding migration batches in transactions; large ID queries are chunked to avoid SQLite variable limits.  
  _DirectConnectService.swift · MultipeerService.swift · ClipboardService.swift · PasteMigrationAdapter.swift · DataExportService.swift · DeckSQLManager.swift_

- **加密失败通知调用显式捕获**  
  将 `notifyEncryptionFailureIfNeeded()` 的调用改为显式捕获 `self`，修复相关编译/并发告警。  
  Made the `notifyEncryptionFailureIfNeeded()` call use an explicit `self` capture to fix the related compile/concurrency warning.  
  _DeckSQLManager.swift_

- **IDE 锚点发现更健壮（Cursor/VS Code）**  
  扩展 IDE anchor 发现逻辑：Cursor/VS Code 在缺失 `AXDocument` 时不再 hard-fail；AX 遍历更深并更适配 Electron 风格树；多属性提取带 proxy/title/value fallback，并对 `file://` 值做更宽松的 URL/path 归一化；集中路径校验（存在性 + 可选 `:line:col` 去除）减少误判。  
  Expanded IDE anchor discovery so Cursor/VS Code no longer hard-fails on missing `AXDocument`; AX traversal is deeper and more robust to Electron-style trees; added multi-attribute extraction with proxy/title/value fallbacks plus lenient URL/path normalization, and centralized file-path validation to avoid false positives.  
  _IDEAnchorService.swift_

- **替换不可用 AX 常量，避免 SDK 符号依赖导致编译失败**  
  将不可用的 AX 常量替换为基于字符串的 attribute，保留 navigation-order 遍历尝试且不再触发编译错误。  
  Swapped an unavailable AX constant for a string-based attribute so the build no longer depends on that SDK symbol, while keeping the navigation-order traversal attempt.  
  _IDEAnchorService.swift_

- **统计页存储信息计算修正**  
  存储大小改为统计 `Deck.sqlite3` 及其 `-wal/-shm` 的真实文件大小，平均记录大小随之修正。  
  Fixed storage calculations in Statistics by measuring the real file sizes of `Deck.sqlite3` and its `-wal/-shm` siblings, and updating average record size accordingly.  
  _StatisticsView.swift_

- **历史预览复制按钮改为对勾动画反馈**  
  代码区复制按钮改为与 CLI Bridge 同款对勾动画；点击代码复制不再弹绿色“已复制”，其他复制项仍保留原提示。  
  Updated the history preview code copy button to use the same checkmark animation as CLI Bridge; copying code no longer shows the green “Copied” toast, while other copy actions keep their existing feedback.  
  _SmartContentView.swift_

- **空间预览状态重置，避免重开面板复现旧预览**  
  面板激活/失活/消失时统一重置预览状态（state + task cancel + window hide），避免预览在重新打开后“自动浮现”。  
  Reset preview state on panel activation/deactivation/disappear (state + task cancel + window hide) so previews no longer resurface after reopening.  
  _HistoryListView.swift_

- **预览与 Orbit 相关 Swift 6 警告/错误清理**  
  将 `FilePreviewRules` 常量/函数标为 `nonisolated` 以适配 MainActor 默认隔离；fallback icon 调用切换为正确 API；并在 Orbit jump model 中显式捕获 `saveDebounce` 以避免 actor hop。  
  Cleaned up Swift 6 warnings/errors in preview/controller code and Orbit jump model by making `FilePreviewRules` constants/functions `nonisolated` under MainActor default isolation, fixing fallback icon API usage, and explicitly capturing `saveDebounce` to avoid actor hops.  
  _PreviewWindowController.swift · OrbitJumpModel.swift_

- **修正 NSWorkspace 图标 API 参数标签，消除 `forContentType:` 编译错误**  
  将 fallback icon 调用改为 `NSWorkspace.shared.icon(for: .data)` 以匹配当前 SDK 的 `icon(for:)` 签名。  
  Fixed NSWorkspace icon API parameter labels by switching the fallback icon call to `NSWorkspace.shared.icon(for: .data)`, eliminating the `forContentType:` compile error.  
  _PreviewWindowController.swift_

- **避免 RTF/RTFD 路径触发 Obj‑C decode warning（保留富文本粘贴）**  
  在 `ClipboardItem` 中优先缓存 plain-text 候选；当 plain text 非空时短路 RTF/RTFD 解码以避免 `NSAttributedString` 解码告警；同时保留原富文本 payload 作为粘贴与无 plain text 情况的 fallback。  
  Traced the Obj‑C decode warning to the RTF/RTFD path and added a plain-text short-circuit when a clean string already exists, avoiding `NSAttributedString` decoding warnings while preserving the original rich-text payload for pasting and fallback.  
  _ClipboardItem.swift_

- **输入过大/无效保护：防崩溃与竞态**  
  保持正常流程 UX 不变，仅对超大/无效输入做提前拒绝与日志记录，避免 crash 与 race：Cloud Sync/脚本插件/隐写/语义搜索/剪贴板等路径加入大小上限、锁与安全读取。  
  Kept normal UX unchanged, but now rejects oversized/invalid inputs early (with logs) to prevent crashes and races by adding caps/locks/safe reads across Cloud Sync, script plugins, steganography, semantic search, and clipboard paths.  
  _CloudSyncService.swift · ScriptPluginService.swift · ClipboardItem.swift · SteganographyService.swift · SemanticSearchService.swift_

- **Steganography Swift 6 隔离修复**  
  将 `loadCarrierImageData(from:)` 标注为 `nonisolated` 与调用方一致；并将 `maxCarrierFileBytes` 标为 `nonisolated`，修复静态属性在非隔离上下文访问的编译报错。  
  Fixed Swift 6 isolation compile errors by marking `loadCarrierImageData(from:)` `nonisolated` to match call sites and making `maxCarrierFileBytes` `nonisolated` to allow static access from nonisolated contexts.  
  _SteganographyService.swift_

- **Cloud Sync 同名遮蔽修复**  
  避免 `if let previewData` 同名遮蔽导致块内变为 `let`；改用局部 `previewBytes` 后可正常 `previewData = nil`。  
  Fixed a same-name shadowing bug (`if let previewData`) that made the value immutable inside the block; switching to a local `previewBytes` restores correct `previewData = nil` behavior.  
  _CloudSyncService.swift_

- **数据库/同步/可访问性/热键/导入导出等稳定性修复（保持行为一致）**  
  FTS 查询使用显式 `bm25` alias；历史遗留空 `unique_id` 安全回填；blob items 遵循 `loadFullData`；batch fetch 按 SQLite 限制分块；引入 cursor-based fetching 稳定分页并用于 Cloud Sync；修复 AX 强制解包/坐标换算与 window title cast；热键更新失败时回滚；粘贴队列加入可取消自动退出调度；Multipeer TOTP nil 安全处理；导出改用 cursor paging、导入重 IO 移出主线程、支持 JSON fragments、URL 编码收紧；并用 typeID 校验 helper 消除 CFTypeRef cast warnings。  
  Applied UX-neutral stability fixes: explicit `bm25` alias for FTS, safe backfill for legacy empty `unique_id`, blob items honor `loadFullData`, chunked batch fetch under SQLite limits, cursor-based paging used by Cloud Sync, safer AX handling and multi-monitor caret positioning, hotkey update rollback on failure, cancellable auto-exit for paste queue, nil-safe TOTP generation, export via cursor paging with import IO off-main, JSON fragments support, tighter URL encoding, and typeID-checked unwrap helpers to eliminate CFTypeRef cast warnings.  
  _DeckSQLManager.swift · CloudSyncService.swift · CursorAssistantService.swift · ClipboardService.swift · HotKeyManager.swift · PasteQueueService.swift · MultipeerService.swift · DataExportService.swift · TextTransformer.swift · SourceAnchor.swift_

- **Swift 6 编译错误修复（导出/导入与类型推断）**  
  修正 `append` 类型推断与未使用结果；将 export DTO 标为 `nonisolated + Sendable`，新增 `@MainActor` insert helper，并 await 主线程日志；为跨 Task 的 source-anchor 值类型补充 `Sendable`；并通过显式 `rows: [Row]` 修复 `append(contentsOf:)` 的剩余错误。  
  Resolved Swift 6 compile errors by tightening type inference and silencing unused results, making export DTOs `nonisolated` + `Sendable`, adding a `@MainActor` insert helper and awaiting main-actor logging, adding `Sendable` conformances for source-anchor value types used across tasks, and explicitly typing `rows: [Row]` to fix the remaining `append(contentsOf:)` error.  
  _DeckSQLManager.swift · DataExportService.swift · SourceAnchor.swift_

- **长网址导致卡片被拉长与二维码生成卡死问题**  
  弹窗卡片固定宽度 320；展示用 URL 改为去掉 `http(s)://` 后最多 20 个字符并追加省略号（悬停可看完整链接）；二维码生成失败时显示「链接过长，无法生成二维码」而非一直“生成中...”；超过 600 字节阈值时右键菜单不再显示「显示二维码」以避免生成无法扫码的二维码。  
  Fixed long-URL UI issues by fixing popup card width to 320, truncating displayed URLs (strip `http(s)://`, show up to 20 chars + ellipsis with full link on hover), showing a clear “link too long” message when QR generation fails (instead of spinning), and hiding “Show QR code” in the context menu when URL length exceeds 600 bytes.  
  _PreviewWindowController.swift · ClipItemCardView.swift_

- **翻译补齐至 100%**  
  `Localizable.xcstrings` 中那 25 个空/未翻译条目已补齐，翻译覆盖率恢复到 100%。  
  Filled the 25 empty/missing translation entries in `Localizable.xcstrings`, restoring 100% translation coverage.  
  _Localizable.xcstrings_

- **拖拽导出：单文件 `suggestedName` 去掉最后一个扩展名**  
  单文件拖拽导出时将 `suggestedName` 改为去掉最后一个扩展名的基名，避免 Finder 根据 UTType 再次追加后缀导致 `.py.py` / `.json.json`。  
  Updated single-file drag-export `suggestedName` to strip the last extension so Finder doesn’t append another one based on UTType (avoids `.py.py` / `.json.json`).  
  _ClipboardItem.swift_

### 说明 / Notes
- **反馈邮件文案与翻译覆盖**  
  新增并翻译「提交反馈」「告诉我们您的想法」与「Deck 反馈」邮件主题；并更新/补齐既有模板中的 subject/question/hint 行与缺失语言文件。  
  Added translations for “提交反馈”, “告诉我们您的想法”, and the “Deck 反馈” email subject; updated subject/question/hint lines in existing templates and added missing language template files.  
  _Localizable.xcstrings · feedback_en.html · feedback_de.html · feedback_kr.html · feedback_fr.html · feedback_ja.html · feedback_zh_hant.html_

### 兼容性与行为说明 / Compatibility & Behavior Notes
- **反馈邮件撰写依赖系统邮件服务可用性**  
  反馈邮件优先通过 `NSSharingService` 打开系统邮件撰写器；仅当该服务不可用时才尝试直接打开 Mail 应用。  
  Feedback email prefers composing via `NSSharingService` and only attempts to open the Mail app directly when the service is unavailable.  
  _FeedbackEmailService.swift_

### 升级建议 / Upgrade Notes
- **建议所有用户升级至 v1.2.2**  
  本版本包含反馈邮件流程完善、多语言补齐、预览与设置交互增强、稳定性/性能与安全防护的集中改进。  
  Recommended for all users: v1.2.2 includes improvements to feedback email flow, localization coverage, preview/settings interaction, and broad stability/performance/safety hardening.

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

### 新增 / Added
- **数据库自救备份开关与手动备份**  
  新增偏好项 `databaseAutoBackupEnabled` 并接入设置页；支持立即备份/删除入口，关闭时不再备份/恢复并清理 `.bak`。  
  Added a `databaseAutoBackupEnabled` preference with Settings UI; supports manual backup/delete, and when disabled it stops backup/restore and cleans up `.bak`.  
  _UserDefaultsManager.swift, SettingsView.swift, DeckSQLManager.swift_

### 优化 / Improvements
- **历史记录分页懒加载 payload，降低滚动内存与解密开销**  
  分页列表项默认保持轻量：仅在需要时才解密完整 payload，结合大小阈值与预览字段延迟加载。  
  Keeps paged history items lightweight: only decrypts full payload when needed, using size thresholds and previews to defer heavy loads.  
  _DeckSQLManager.swift_
- **历史列表减少 COW 峰值（避免数组镜像）**  
  当重排关闭/搜索/队列模式时保持 `orderedItems` 为空，避免共享缓冲区导致的 Copy-on-Write 峰值。  
  Keeps `orderedItems` empty when reordering is off/search/queue to avoid shared buffers and Copy-on-Write spikes.  
  _HistoryListView.swift_
- **上下文重排与模板保存减少拷贝并确保持久化完整数据**  
  重排结果在单一数组中构建以避免额外拷贝；保存模板前会先 materialize 完整 payload，确保存储的是全量内容。  
  Builds reorder results in a single array to avoid extra copies; materializes full payload before saving templates to ensure full data is persisted.  
  _ContextAwareService.swift, TemplateLibraryService.swift_
- **数据库队列 QoS 分层与后台化搜索排序**  
  将交互查询与后台维护拆分到不同队列（交互/后台），并将 in-memory fuzzy ranking 移出主线程以减少卡顿。  
  Splits DB work into interactive vs background queues and moves in-memory fuzzy ranking off the main actor to reduce UI stalls.  
  _DeckDataStore.swift, DeckSQLManager.swift_
- **搜索性能：候选扩展、扫描上限与可取消的 in-memory 路径**  
  mixed 模式优先 exact 命中，无命中时再触发模糊回退；加入 LIKE 候选扩展、`scanLimit` 上限与真正的 Task 取消；循环内增加协作取消检查。  
  Search now prefers exact hits in mixed mode and only falls back to fuzzy when needed; adds LIKE-based candidate expansion, a `scanLimit` cap, true cancellation for in-memory search, and cooperative cancellation checks in loops.  
  _DeckDataStore.swift, SearchService.swift_
- **CloudSync/Steganography/OCR 节能优化（不改热键行为）**  
  CloudSync 批处理延迟加大并对低电量更保守；stego 解码仅在更可能成功时运行；OCR 增加背压/去抖、低电量跳过与超大图片尺寸上限。  
  Energy optimizations for CloudSync, steganography, and OCR: larger/low-power-aware batching, conditional stego decode, and OCR back-pressure/debounce with Low Power Mode skip and size caps for huge images.  
  _CloudSyncService.swift, ClipboardService.swift, OCRService.swift_
- **文本/正则与缓存：降低 churn 与重复编译**  
  引入 O(1) LRU、`NSCache` 正则缓存与敏感内容匹配的小型 regex cache，减少频繁分配与重复编译。  
  Adds O(1) LRU, `NSCache` regex caching, and a small regex cache for sensitive-content matching to reduce churn and repeated compilation.  
  _SmartContentCache.swift, SmartTextService.swift, ClipboardService.swift_
- **IO/CPU 热点优化（采样、Blob、IDE 锚点、分页等）**  
  批量写入采样、序列化 Blob IO、OCR 热/低功耗降级、IDE 锚点 BFS 队列去 O(n)、分页改为 on-appear 触发等。  
  Reduces IO/CPU hotspots: batched sample saves, serialized blob IO, thermal/low-power OCR downsampling, BFS queue fix, and on-appear pagination.  
  _DiagnosticsMemorySampler.swift, BlobStorage.swift, OCRService.swift, IDEAnchorService.swift, HistoryListView.swift_
- **面板与 macOS 26 视觉：原生玻璃容器与更一致的圆角**  
  macOS 26 使用 `NSGlassEffectView` 作为主容器（`.regular`），并统一 `cornerRadius = Const.panelCornerRadius`；SwiftUI 背景改为 `Color.clear`，顶部间距改用 `Const.panelTopPadding`，搜索框圆角使用 `Const.searchFieldRadius`。  
  On macOS 26, uses `NSGlassEffectView` (`.regular`) as the main container with `cornerRadius = Const.panelCornerRadius`; SwiftUI background is `Color.clear`, top padding uses `Const.panelTopPadding`, and the search field radius uses `Const.searchFieldRadius`.  
  _MainViewController.swift, DeckContentView.swift, TopBarView.swift, Constants.swift_
- **面板打开优先级：交互查询更快、后台维护更省电**  
  将串行 DB 队列 QoS 提回 `.userInitiated`，并在后台维护路径中强制 `.utility`，避免交互查询被整体降级或排在维护任务之后。  
  Raises the serial DB queue QoS back to `.userInitiated` while enforcing `.utility` for background maintenance, preventing interactive queries from being deprioritized.  
  _DeckSQLManager.swift_

### 变更 / Changes
- **macOS 26 视图层级与裁切策略调整**  
  `HostingView` 改为放入 `glass.contentView`；在 26+ 上对 `view` 也设置圆角与 `cornerCurve = .continuous` 做裁切；窗口阴影在 macOS 26 开启（<26 维持关闭）。  
  Adjusts the macOS 26 view hierarchy and clipping: embeds the `HostingView` into `glass.contentView`, applies rounded clipping with `cornerCurve = .continuous` on 26+, and enables window shadow on macOS 26 (kept disabled on <26).  
  _MainViewController.swift, MainWindowController.swift_
- **常量更新：面板尺寸与圆角/间距参数**  
  新增 `panelCornerRadius = 26`、`panelTopPadding = Const.space12 + 5`、`searchFieldRadius = 12`；窗口高度调整为 `305`；`panelOverlay` 在 macOS 26 的配色变轻（但 26 上不再由 `DeckContentView` 使用）。  
  Updates constants: adds `panelCornerRadius = 26`, `panelTopPadding = Const.space12 + 5`, `searchFieldRadius = 12`; adjusts window height to `305`; and lightens `panelOverlay` colors on macOS 26 (though it’s no longer used by `DeckContentView` on 26).  
  _Constants.swift, DeckContentView.swift_
- **热键与队列行为回退为 CGEventTap**  
  将热键监听与 paste-queue 改回此前的基于 `CGEventTap` 的行为，确保 `Cmd+P` 与队列模式恢复正常。  
  Reverts hotkey listening and paste-queue behavior back to the previous `CGEventTap`-based implementation so `Cmd+P` and queue mode work again.  
  _HotKeyManager.swift, PasteQueueService.swift_
- **更新后清理与启动提示：按清理结果触发**  
  启动时清理更新残留并移除 `/Applications` 下 `.Deck.app.old.*` 备份（不进废纸篓），并使用清理结果决定是否触发 8 秒设置窗口提示。  
  Cleans update artifacts on launch and removes `.Deck.app.old.*` backups in `/Applications` (no Trash), and uses the cleanup result to decide whether to show the 8-second Settings window prompt.  
  _AppDelegate.swift, UpdateService.swift_
- **隐私设置：移除手动上传入口并优化 stego key 编辑交互**  
  移除“手动上传/上传一次”动作，分析区仅保留开关；stego passphrase 输入改为更接近真实输入框的样式，保存/清除状态更清晰，并支持回车提交保存。  
  Removes the manual analytics upload action so analytics only has the toggle; restyles stego passphrase input with clearer save/clear states and Enter-to-save flow.  
  _PrivacySettingsView.swift_
- **stego key 掩码与长度持久化**  
  掩码按真实长度渲染并右对齐；保存/清除时持久化长度，使 UI 一致反映当前状态。  
  Renders the stego key mask with the exact length and right alignment; persists the length on save/clear so the UI stays consistent.  
  _UserDefaultsManager.swift, SteganographyKeyStore.swift, PrivacySettingsView.swift_

### 修复 / Fixes
- **DB 队列初始化与编译问题修复**  
  将 `dbQueue`/`dbBackgroundQueue` 改为 `lazy`，避免属性初始化期间触发 `self`；清理未使用变量并修复相关编译报错。  
  Fixes build issues by making `dbQueue`/`dbBackgroundQueue` `lazy` to avoid touching `self` during property initialization and removing an unused variable.  
  _DeckSQLManager.swift_
- **键盘 unicode 读取调用签名修复**  
  为 `keyboardGetUnicodeString` 调用补齐 `maxStringLength:` label，修复编译错误。  
  Fixes the `keyboardGetUnicodeString` call by adding the `maxStringLength:` label.  
  _CursorAssistantService.swift_
- **SwiftUI 更新周期警告与优先级反转缓解**  
  避免在 SwiftUI 更新期间进行状态突变，程序性文本更新被忽略；焦点/失焦变更延迟到异步调度，降低告警与潜在阻塞。  
  Avoids state mutations during SwiftUI updates; ignores programmatic text updates and defers focus/blur asynchronously to reduce update warnings and priority inversions.  
  _TopBarView.swift_
- **主线程读取 UserDefaults 的 Actor 归属修复**  
  将 `sharedKeyMaskLength` 标注为 `@MainActor`，以在主线程读取 `DeckUserDefaults.stegoPassphraseLength`。  
  Marks `sharedKeyMaskLength` as `@MainActor` so it reads `DeckUserDefaults.stegoPassphraseLength` on the main actor.  
  _SteganographyKeyStore.swift_

### 说明 / Notes
- **BlobStorage 目录保持动态以支持运行时切换**  
  `BlobStorage.swift` 的 base directory 继续保持动态，以确保运行时切换存储位置安全；如需补丁里的 lazy cache，可新增失效钩子。  
  Keeps `BlobStorage.swift` base directory dynamic so runtime storage-location switches remain safe; if you want the patch’s lazy cache, add an invalidation hook.  
  _BlobStorage.swift_
- **Carbon 热键的取舍说明（已回退为 CGEventTap）**  
  Carbon 方案会全局占用 `Cmd+Shift+V`；如未来恢复 Carbon 并需要队列关闭时透传，可做条件注册或合成透传逻辑。  
  Carbon hotkeys reserve `Cmd+Shift+V` globally; if Carbon returns and you need pass-through when queue mode is off, conditional registration or synthetic pass-through can be added.  
  _PasteQueueService.swift_
- **更新后设置窗口触发条件说明**  
  更新后窗口仍仅在内置更新器设置了 `deck.pendingUpdateVersion` 时触发，手动 DMG 更新不会触发。  
  The post-update window still only shows when the built-in updater sets `deck.pendingUpdateVersion`; manual DMG updates won’t trigger it.  
  _AppDelegate.swift, UpdateService.swift_

### 兼容性与行为说明 / Compatibility & Behavior Notes
- **macOS 26 的玻璃效果由 AppKit 承担**  
  macOS 26 上 `DeckContentView` 不再在 SwiftUI 内绘制玻璃/叠加层（背景为 `Color.clear`），玻璃与圆角裁切交由 `NSGlassEffectView` 容器处理；<26 仍使用 `VisualEffectBackground + panelOverlay`。  
  On macOS 26, `DeckContentView` no longer draws glass/overlay in SwiftUI (`Color.clear` background); glass and rounded clipping are handled by the `NSGlassEffectView` container, while <26 still uses `VisualEffectBackground + panelOverlay`.  
  _DeckContentView.swift, MainViewController.swift_

### 升级建议 / Upgrade Notes
- **建议所有用户升级到 v1.2.1**  
  本版本聚焦滚动/分页/搜索/DB 交互性能与能耗优化，并包含 macOS 26 视觉容器调整与多处稳定性修复。  
  Recommended for all users: this release focuses on scroll/pagination/search/DB performance and energy improvements, includes macOS 26 container updates, and ships multiple stability fixes.  

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

### 新增 / Added
- **自动更新国内加速与兜底下载**  
  自动更新部署了 CF 反代，国内无法访问 GitHub 时也可稳定更新，并保留 GitHub 下载作为兜底。  
  Auto-update now uses a CF proxy for reliable access in mainland China, with GitHub downloads kept as a fallback.  

- **诊断上传与内存采样**  
  新增诊断上传与内存采样器：每日 15:00 本地时间上传 24 小时诊断报告，失败会去掉日志再试；每分钟采样内存，最多 1440 点，数据写入 `memory_samples.json`。  
  Added diagnostics upload and memory sampling: uploads a 24-hour report daily at 15:00 local time with a log-less fallback, and records minute-level memory samples up to 1440 points in `memory_samples.json`.  
  _DiagnosticsUploadService.swift, DiagnosticsMemorySampler.swift_

- **隐私设置中的分析数据入口**  
  隐私设置新增“分析数据”卡片与开关，开启后提供“手动上传”按钮。  
  Privacy settings add an “Analytics Data” card with a toggle and a manual upload action when enabled.  
  _PrivacySettingsView.swift_

- **新增繁体中文支持**  
  增加对繁体中文（zh-Hant）的本地化翻译支持。  
  Added Traditional Chinese (zh-Hant) localization support.  
  _Localizable.xcstrings_

### Deck × Orbit
- **每次安装唯一 Token 与安全兜底**  
  Orbit bridge token 改为每次安装随机生成并存储，`#if DEBUG` 仍兼容 legacy token；Release 不再接受硬编码 token。  
  Orbit bridge tokens are now per-install random values with a DEBUG legacy fallback; Release no longer accepts a hardcoded token.  
  _OrbitBridgeAuth.swift_

- **启动即准备 Token 与 401 重试**  
  启动时强制创建 token，并在 401 时从磁盘重载并重试一次。  
  Tokens are eagerly created at launch, and 401 responses trigger a disk reload and one retry.  
  _AppDelegate.swift, OrbitBridgeAuth.swift, OrbitBridgeClient.swift_

### 优化 / Improvements
- **预览渲染与缩略图网格增强**  
  预览始终显示电话行 + 全文并保留智能摘要；file URL 多图新增缩略图网格，历史卡片缩略图修复，预览对鼠标点击也会刷新。  
  Preview now always shows the phone line + full text while keeping smart details; added multi-image thumbnail grids for file URLs, fixed history card thumbnails, and made previews refresh on mouse clicks.  
  _PreviewWindowController.swift, PreviewOverlayView.swift, HistoryListView.swift_

- **多图卡片的布局与省略指示优化**  
  多图卡片仅显示首图，右侧独立省略指示条（固定高度与最小宽度），不再遮盖图片、也不会顶起标题。  
  Multi-image cards now show only the first image with a separate right-side ellipsis indicator of fixed height/min width, without overlaying the image or pushing titles.  
  _ClipItemCardView.swift_

- **安装/更新界面图标渲染稳定**  
  安装/更新 UI 强制使用原色应用图标，避免暗色模式出现模板色偏。  
  Install/update UI now forces original-color app icons to avoid dark-mode template tinting.  
  _SettingsView.swift_

- **统计视图轻量化与内存回收**  
  统计改为仅用元数据查询，退出视图时触发 SQLite shrink；Top Apps 使用 `appPath` 作为稳定 id。  
  Statistics now use metadata-only queries with a shrink-memory hook on exit, and Top Apps use `appPath` as a stable id.  
  _StatisticsView.swift, DeckSQLManager.swift_

- **数据库启动与向量索引性能优化**  
  PRAGMA `quick_check(1)` 以 24h 窗口限频，仅在备份恢复时强制；向量回填仅在 embeddings 存在且 vec 表为空时触发，并按最近数据分批带短暂休眠；`updateVecIndex` 避免重序列化并使用 `INSERT OR REPLACE`。  
  PRAGMA `quick_check(1)` is throttled to a 24h window and forced only on restore; vec backfill runs only when embeddings exist and vec tables are empty, favoring recent rows with short sleeps; `updateVecIndex` avoids heavy serialization and uses `INSERT OR REPLACE`.  
  _DeckSQLManager.swift_

- **隐写解码与导出任务离线化**  
  隐写解码改为后台任务执行并支持取消；导出认证在主线程，抓取/编码/写入在后台完成。  
  Stego decoding now runs off-main with cancellation support; export auth stays on main while fetch/encode/write run in a detached worker.  
  _ClipboardService.swift, SteganographyService.swift, DataExportService.swift_

- **自动删除调度器替换逐条 sleep**  
  用 `AutoDeleteScheduler` actor 统一调度自动删除，减少队列阻塞。  
  Auto-delete is now coordinated by an `AutoDeleteScheduler` actor instead of per-item sleeps.  
  _SmartRuleService.swift_

- **语义检索矩阵化与缓存**  
  引入矩阵化评分与向量范数缓存，保持阈值/排序语义不变，并用 `vDSP_mmul` 替代弃用的 `cblas_sgemv`。  
  Added matrixized scoring with norm caching while preserving threshold/sort semantics, and replaced deprecated `cblas_sgemv` with `vDSP_mmul`.  
  _SemanticSearchService.swift_

### 变更 / Changes
- **更新缓存清理与更新完成提示**  
  启动时清理 `~/Library/Caches/Deck/Updates/` 下所有版本前缀目录（含 `unknown-`），并记录 `pendingUpdateVersion`；满足条件时 8 秒后打开设置并提示“更新完成”，设置窗口新增 `showWindow()` 防止 toggle 误关。  
  On launch, clears all version-prefixed update caches (including `unknown-`) and records `pendingUpdateVersion`; when applicable, opens Settings after 8 seconds to show “Update complete,” with a new `showWindow()` to avoid toggle mis-close.  
  _UpdateService.swift, AppDelegate.swift, SettingsWindowController.swift_

- **更新服务的签名强制与安全约束**  
  Release 更新路径强制代码签名校验。  
  Release updates now enforce code signature validation.  
  _UpdateService.swift_

- **脚本执行队列策略调整**  
  脚本执行队列做过串行化以降低资源争用，现改为并发以避免单个脚本阻塞其他任务。  
  Script execution was serialized to reduce contention, and is now concurrent to avoid head-of-line blocking.  
  _ScriptPluginService.swift_

- **规则/模板持久化稳定码**  
  `TransformType` 持久化改用稳定 code，并兼容旧中文 rawValue。  
  `TransformType` persistence now uses a stable code with backward compatibility for legacy Chinese raw values.  
  _TextTransformer.swift_

- **加密迁移与行级状态跟踪**  
  数据库新增 `is_encrypted` 列并实现按字段幂等加解密与行级决策，检测阶段使用静默解密避免日志刷屏。  
  DB now tracks `is_encrypted` with idempotent per-field encrypt/decrypt and row-level decisions; detection uses silent decrypt to avoid log spam.  
  _DeckSQLManager.swift, SecurityService.swift_

- **导出路径与临时文件策略**  
  导出改为直接写入用户选择路径，并在启动时清理遗留临时导出文件。  
  Exports now write directly to the user-chosen path and clean leftover temp exports on launch.  
  _DataExportService.swift_

- **DirectConnect 明文接收限制**  
  没有确认回调时拒绝明文接收。  
  Plaintext receives are rejected when no confirmation callback is wired.  
  _DirectConnectService.swift_

### 修复 / Fixes
- **事件回调内存泄漏与 RunLoop 解绑问题**  
  所有 CGEventTap 回调返回 `passUnretained(event)`，并统一使用 `CFRunLoopGetMain()` 绑定/解绑，避免泄漏与 runloop 不一致导致的资源悬挂。  
  All CGEventTap callbacks now return `passUnretained(event)` and use `CFRunLoopGetMain()` for consistent attach/detach, preventing leaks and runloop mismatches.  
  _PasteQueueService.swift, CursorAssistantService.swift_

- **热键卸载遍历崩溃**  
  `unregisterAllHotKeys()` 改为遍历 `Array(hotKeys.keys)`，避免遍历中修改集合崩溃。  
  `unregisterAllHotKeys()` now iterates `Array(hotKeys.keys)` to avoid mutation-during-enumeration crashes.  
  _HotKeyManager.swift_

- **热键修饰键事件泄漏**  
  修饰键 event tap 回调改为返回 `passUnretained(event)`。  
  Modifier event tap callbacks now return `passUnretained(event)` to prevent leaks.  
  _HotKeyManager.swift_

- **剪贴板轮询定时器竞态**  
  轮询定时器的 schedule/cancel 全部在其所属队列执行，避免竞态和异常。  
  Poll timer scheduling/canceling now runs on its own queue to avoid races and odd behavior.  
  _ClipboardService.swift_

- **云同步回环与漏同步**  
  远端变更落库时支持 `shouldSyncToCloud=false`，避免上传回环；`moreComing` 拉取改为循环直到完成，并正确推进 token。  
  Remote changes now apply with `shouldSyncToCloud=false` to prevent echo uploads; `moreComing` fetches loop until complete with proper token advancement.  
  _CloudSyncService.swift, DeckDataStore.swift_

- **云端加密记录解密逻辑**  
  只要 record 标记为加密就强制解密，不再受本地开关影响。  
  Encrypted records are always decrypted regardless of local encryption toggle.  
  _CloudSyncService.swift_

- **云同步远端更新落地方式**  
  远端更新改为直接更新数据库，不再 delete+insert，避免重复与写放大。  
  Remote updates now write directly to the DB instead of delete+insert, preventing duplication and write amplification.  
  _CloudSyncService.swift, DeckSQLManager.swift_

- **CloudSync 竞争态修复**  
  `pendingUploadCount` 统一在主线程更新，避免后台修改可观察状态导致竞态。  
  `pendingUploadCount` now updates on the main thread to avoid races from background mutations.  
  _CloudSyncService.swift_

- **云同步编译错误清理**  
  移除 `ManagedCriticalState` 并补齐显式 tuple 类型，修复编译错误。  
  Removed `ManagedCriticalState` and added explicit tuple types to fix compile errors.  
  _CloudSyncService.swift_

- **唯一索引与重复去重**  
  `unique_id` 建立 UNIQUE 索引并在需要时去重重试，失败则降级为普通索引并报警。  
  `unique_id` now uses a UNIQUE index with dedupe-and-retry and a safe fallback to a normal index.  
  _DeckSQLManager.swift_

- **重复记录的稳定读取**  
  `fetchRow(uniqueId:)` 增加排序，确保重复时命中最新记录。  
  `fetchRow(uniqueId:)` now orders results to pick the most recent row deterministically.  
  _DeckSQLManager.swift_

- **Blob 更新一致性与磁盘清理**  
  更新时写入 `blob_path`，必要时转存大数据到 blob；旧 blob 路径在更新成功后清理。  
  Updates now persist `blob_path`, offload large data to blob storage when needed, and remove old blob files after successful updates.  
  _DeckSQLManager.swift, BlobStorage.swift_

- **Blob 路径与 symlink 安全**  
  `BlobStorage` 路径不再触碰 `@MainActor`；symlink 解析加强以避免路径穿越。  
  `BlobStorage` no longer depends on `@MainActor`, and symlink resolution is hardened to prevent path traversal.  
  _BlobStorage.swift_

- **文件 URL 缩略图解码错误**  
  避免将文件路径字符串当作图像数据解码，直接从 file URL 生成缩略图。  
  Avoids decoding file path strings as image data by generating thumbnails directly from file URLs.  
  _ClipItemCardView.swift_

- **JS 执行超时与兼容性**  
  JSCore 执行加入超时限制；不可用符号改用 `dlsym` 动态查找，仅在支持时生效。  
  JSCore execution now has a time limit; unavailable symbols are resolved via `dlsym` and applied only when present.  
  _ScriptPluginService.swift_

- **导出 OOM 修复**  
  大文件导出改为流式解析 `items`，避免一次性 decode 造成内存爆。  
  Large exports now stream-parse `items` to avoid OOM from full JSON decoding.  
  _DataExportService.swift_

- **Swift 6 并发与隔离修复**  
  日志方法标记 `nonisolated(unsafe)` 以支持后台调用；移除不必要的全局 logger `nonisolated`；隐写解码使用非隔离静态管线与预取 key；`SteganographyKeyStore` 访问改为 nonisolated。  
  Logging now uses `nonisolated(unsafe)` for background calls while removing unnecessary global logger isolation; stego decoding routes through nonisolated static helpers with pre-fetched keys; `SteganographyKeyStore` access is nonisolated.  
  _AppLogger.swift, SteganographyService.swift, SteganographyKeyStore.swift, ClipboardService.swift_

- **Swift 6 语义与线程安全修复**  
  主线程捕获隐写服务后再 detach，自动删除日志改到主线程，修复 Swift 6 隔离错误。  
  Stego services are captured on main before detaching and auto-delete logging is moved to main to satisfy Swift 6 isolation.  
  _ClipboardService.swift, SmartRuleService.swift_

- **统计 SQL 迭代与 shrinkMemory 异步化**  
  原生 SQL 遍历改为 Statement 行索引，`shrinkMemory()` 改为 async 并补齐调用点。  
  Raw SQL loops now use Statement row indexing, and `shrinkMemory()` is async with updated call sites.  
  _DeckSQLManager.swift, StatisticsView.swift, DeckDataStore.swift_

- **本地化警告清理**  
  16 个未引用 key 的 `extractionState` 改为 `manual`，保留翻译同时消除警告。  
  Set 16 unused localization keys to `manual` to keep translations and remove warnings.  
  _Localizable.xcstrings_

### 说明 / Notes
- **诊断上传内容范围**  
  上传日志不包含剪贴板数据，仅包含 App 版本、系统信息、用户 ID、24h 内存曲线与崩溃日志。  
  Diagnostic uploads exclude clipboard content and include only app version, system info, user ID, 24-hour memory curve, and crash logs.  

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

### 优化 / Improvements

- **安全模式性能大幅优化（CPU / IO）**  
  在加密模式下，对密钥处理、搜索扫描路径、文本分析、链接预取、Blob IO、语义排序等关键路径进行了系统性优化，显著降低 CPU 与 IO 开销。  
  Applied encryption-mode performance optimizations across key handling, search scan paths, text analysis, link preview prefetching, blob IO, and semantic ranking to reduce CPU/IO overhead.

- **Keychain 访问削减（短 TTL 内存缓存）**  
  为对称密钥引入短 TTL 的内存缓存，并在鉴权重置 / 密钥删除时主动清空，减少突发场景下的 Keychain 往返。  
  _SecurityService.swift_

- **搜索与向量计算优化**  
  - 正则扫描仅选择 `id / search_text`，再按需拉取完整行  
  - 安全模式下启用搜索缓存，并在 App / Session 失活时清空  
  - 向量归一化与查询范数计算统一使用 vDSP，避免重复计算  
  _DeckSQLManager.swift / SemanticSearchService.swift_

- **文本分析加速**  
  缓存 `NSDataDetector` 并加入快速预检查，在明显不匹配时跳过高成本检测。  
  _SmartTextService.swift_

- **链接预览与电量感知**  
  低电量模式下跳过图片预取，且预取逻辑迁移至 utility 队列，降低主线程与能耗压力。  
  _ClipboardService.swift_

- **大文件 IO 与内存峰值控制**  
  - 大 Blob 写入避免使用 `.atomic`  
  - 读取时优先使用 `.mappedIfSafe`，减少 IO 与内存抖动  
  _BlobStorage.swift_

---

### 内存 / 网络 / UI 深度优化

- **内存与生命周期管理**  
  - 缓存引入 LRU + 内存压力清理  
  - 数据层补齐内存压力降载  
  - 剪贴板解析与粘贴改为 lazy 读取大数据，避免 OOM  
  - 链接卡片快照加入总量 / 单类型预算，避免大图瞬时占用  
  _SmartContentCache.swift / DeckDataStore.swift / ClipboardService.swift_

- **网络与电量优化**  
  - 多端连接改为指数退避 + jitter  
  - 新增 sleep / wake 发现管理，已连接时停止扫描  
  - 编码 / 加密统一移至后台队列，主线程仅保留快路径  
  _MultipeerService.swift / DirectConnectService.swift_

- **列表与渲染性能**  
  - History 列表将高频交互状态移出 `@State`，避免滚动重算  
  - 缩略图 / 图标缓存 + 后台降采样  
  - Base64 检测仅执行一次  
  - 代码高亮异步缓存  
  - 大文本 / Markdown 预览支持取消与销毁清理  
  _HistoryListView.swift / ClipItemCardView.swift / SmartContentView.swift / LargeTextPreviewView.swift_

---

### 行为调整 / Behavior Changes

- **已连接时默认停止 Browsing（省电优先）**  
  如需恢复原行为，可通过开关控制。  
  _MultipeerService.swift_

- **大图片写入策略调整**  
  当已存在 `fileURL` 时，不再强制写入 inline bytes，降低瞬时内存峰值。  
  _ClipboardService.swift_

---

### 并发与 Swift 6 兼容性修复 / Swift 6 Fixes

- **Sendable 与隔离修正**  
  为多种 Payload / Snapshot / Decoded 类型补齐 `Sendable`，避免后台编解码触发主线程隔离错误。  
  _MultipeerService.swift_

- **日志与工具类型隔离调整**  
  - `AppLogger` 标记为 `@unchecked Sendable`  
  - 部分方法显式退出 `MainActor` 隔离，避免后台任务报错  
  _AppLogger.swift / MultipeerService.swift_

- **URL 检测彻底去除 NSDataDetector**  
  改为正则匹配并统一去除尾部标点，消除 Swift 6 主线程隔离问题，同时保持快速预检查与去重。  
  _SmartTextService.swift_

---

### 更新系统 / Updater

- **每日 20:00（北京时间）自动检查更新**  
  定时检查改为系统通知提醒，点击通知进入更新详情。  
  _UpdateCoordinator.swift_

- **更新提示 UI 升级**  
  - 完整 Markdown 渲染（标题 / 引用 / 列表 / 分割线）  
  - 保留自然换行并压缩多余空行  
  - 深色模式下按钮对比度优化  
  _UpdatePromptView.swift_

- **更新可靠性增强**  
  - 启动验证等待时间延长（2s → 8s）  
  - 旧进程等待加入超时与 PID 复用保护  
  - 下载临时文件先落盘到稳定路径，避免被系统清理  
  - 新版本启动后自动清理当前版本前缀的旧更新缓存  
  _UpdateService.swift / AppDelegate.swift_

---

### 修复 / Fixes

- **Finder 多文件复制回归修复**  
  修复从 Finder 复制多文件后，再复制文本并从历史记录粘贴时只剩第一个文件的问题。

- **面板关闭后焦点未恢复**  
  修复复制后关闭面板但焦点未返回之前 App 的问题，并补齐 ⌘W 关闭设置窗口行为。  
  _MainWindowController.swift / SettingsWindowController.swift_

- **PasteNow 剪贴板数据迁移支持**  
  新增对 PasteNow App 剪贴板数据的迁移兼容。

- **Markdown 预览任务修复**  
  修复 `parseTask` 重复声明与类型不匹配问题，并清理无效任务。  
  _LargeTextPreviewView.swift_

---

### 兼容性与说明 / Compatibility & Notes

- iCloud / CloudKit entitlement 已移除，避免签名依赖；同步功能代码仍保留但默认关闭。  
  _Deck.entitlements_

- 本版本包含大量性能、并发与稳定性改进，**强烈建议所有用户升级**。

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

### 新增 / Added

- **Paste 迁移适配与一键迁移流程**  
  新增 Paste 迁移适配，同时兼容旧版 `Paste.db` 与沙盒新版 `index.sqlite`，并加入 Maccy / Flycut / PasteBar 的一键迁移流程。  
  Added Paste migration support with compatibility for both legacy `Paste.db` and sandbox `index.sqlite`, plus one-click migration for Maccy / Flycut / PasteBar.

- **Storage 页面常驻迁移模块**  
  Storage 页面新增始终可见的迁移模块，复用欢迎页迁移流程与提示，进入页面即触发扫描。  
  Added an always-visible migration module to the Storage page, reusing the onboarding migration flow and auto-scanning on entry.  
  _SettingsView.swift_

- **本地 Orbit CLI Bridge 常驻服务**  
  Deck 新增本地 Orbit CLI Bridge 常驻服务（`127.0.0.1:53129`），提供：`/orbit/health`、`/orbit/recent`、`/orbit/item`、`/orbit/delete`、`/orbit/copy`。  
  Deck now includes a local Orbit CLI Bridge daemon (`127.0.0.1:53129`) exposing: `/orbit/health`, `/orbit/recent`, `/orbit/item`, `/orbit/delete`, `/orbit/copy`.

- **迁移来源名称本地化覆盖**  
  新增迁移来源名称（Maccy / Paste / Flycut / PasteBar）的中文 / 英文 / 德文覆盖。  
  Added localized migration source names (Maccy / Paste / Flycut / PasteBar) in Chinese / English / German.

- **引导页强制触发开关**  
  新增引导页强制触发的调试开关（代码布尔开关）。  
  Added a debug toggle (boolean flag) to force-trigger the onboarding flow.

---

### Deck × Orbit

> Orbit GitHub：  
> https://github.com/yuzeguitarist/Orbit

- **剪贴板记录环（Clipboard Ring）**  
  Orbit 现已与 Deck 深度联动，引入剪贴板记录环形态，将 Deck 的剪贴板能力以径向方式呈现。  
  Orbit now integrates deeply with Deck, bringing Deck’s clipboard history into a radial clipboard ring.

- **快速切换方式**  
  打开 Orbit 应用环后，按下 **Caps Lock（中 / 英切换键）** 即可切换到剪贴板环形态。  
  After summoning the Orbit app ring, press **Caps Lock (Input Source key)** to switch to the clipboard ring.

- **剪贴板环能力**  
  剪贴板环默认显示 9 张卡片，支持键盘切换、复制、删除，以及拖拽到中心进行分享或删除。  
  The clipboard ring shows 9 cards by default, supporting keyboard navigation, copy/delete actions, and drag-to-center share or delete.

- **文本 / 代码 AirDrop 支持**  
  文本与代码会以临时文件形式进行 AirDrop，自动匹配语言扩展名（Swift / Python / Plist / Shell），并在完成后自动清理。  
  Text and code are shared via AirDrop as temporary files with language-aware extensions and automatic cleanup.  
  _ClipboardShareService.swift_

---

### 优化 / Improvements

- **迁移导入性能优化**  
  迁移批量插入流程优化，减少事务次数与 UI 刷新压力，提升大数据量导入性能。  
  Improved migration bulk inserts by reducing transaction count and UI refresh overhead for faster large imports.

- **欢迎引导迁移页体验优化**  
  优化欢迎引导迁移页布局与间距；列表仅显示已检测到的 App；窗口高度调整为 450。  
  Refined onboarding migration page layout/spacing; list now shows only detected apps; window height set to 450.

- **Option 双击响应节奏优化**  
  调整窗口阈值与冷却时间，更快可再次隐藏/唤起。  
  Tuned the double-Option interaction (threshold + cooldown) to allow quicker hide/show cycles.  
  _HotKeyManager.swift_

---

### 变更 / Changes

- **鉴权方式调整为固定请求头**  
  Deck 鉴权改为固定 `X-Orbit-Token` 请求头，不再使用 Keychain / XPC 弹窗流程。  
  Deck authentication now uses a fixed `X-Orbit-Token` header, removing the Keychain/XPC prompt flow.

- **OrbitBridgeClient 改为 HTTP 调用**  
  OrbitBridgeClient 改为通过 HTTP 调用 CLI Bridge，移除 XPC 连接逻辑。  
  OrbitBridgeClient now talks to the CLI Bridge via HTTP and removes the XPC connection path.

- **面板显示位置跟随鼠标所在屏幕**  
  面板显示位置调整为跟随鼠标所在屏幕。  
  The panel now appears on the screen where the cursor is located.  
  _MainWindowController.swift_

---

### 修复 / Fixes

- **Flycut 迁移容错**  
  修复 Flycut 无历史数据时迁移流程不应报错的问题。  
  Fixed Flycut migration to gracefully handle cases with no history.

- **数据库 VACUUM 的 Swift 6 并发警告**  
  修复数据库 vacuum 相关的 Swift 6 并发警告。  
  Fixed Swift 6 concurrency warnings related to database VACUUM.

- **Finder PNG（fileURL）再次复制/拖拽异常**  
  修复 Finder 复制的 PNG 在再次复制/拖拽时无法粘贴、拖出文件损坏的问题：对 `fileURL` 图片读取真实图像数据并写入正确的图片类型。  
  Fixed an issue where PNGs copied from Finder could not be pasted after re-copy/drag and could produce corrupted dragged files, by reading actual image data for `fileURL` images and writing the correct image type.  
  _ClipboardItem.swift_

- **fileURL 图片粘贴/拖拽兼容性增强**  
  粘贴/拖拽 `fileURL` 图片时同时写入文件 URL 与图像数据，兼容更多目标应用。  
  Improved compatibility by writing both file URL and image data when pasting/dragging `fileURL` images.  
  _ClipboardService.swift_

---

### 说明 / Notes

- **迁移模块文案复用**  
  本次变更未新增文案，迁移模块继续复用现有中文 / 英文 / 德文翻译。  
  No new copy was added; the migration module continues to reuse existing Chinese/English/German translations.  
  _SettingsView.swift_

---

### 兼容性与行为说明 / Compatibility & Behavior Notes

- Paste 迁移支持同时识别旧库 `Paste.db` 与沙盒新版 `index.sqlite`。  
  Paste migration supports both legacy `Paste.db` and sandbox `index.sqlite`.

- Orbit Bridge 服务仅在本机回环地址提供能力，并通过固定请求头进行鉴权。  
  The Orbit Bridge service is exposed on localhost only and authenticated via a fixed request header.

---

### 升级建议 / Upgrade Notes

- 建议所有用户升级以获得更顺滑的迁移体验（更快的大数据量导入、Storage 常驻迁移入口）、更稳定的图片粘贴/拖拽兼容性，以及新的 Orbit CLI Bridge 能力与更简化的鉴权流程。  
  All users are recommended to upgrade for a smoother migration experience (faster large imports + always-available Storage entry), improved image paste/drag compatibility, and the new Orbit CLI Bridge with a simplified authentication flow.

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

### 修复 / Fixes

- **脚本插件「转换后粘贴」主线程阻塞**  
  将执行方式改为异步，避免主线程同步调用被系统拒绝而导致无响应。  
  Fixed an unresponsive issue by executing the “Paste After Transform” script plugin asynchronously instead of blocking the main thread.  
  _ClipItemCardView.swift_

- **NSExpression 非法格式导致崩溃**  
  非法表达式不再触发崩溃，新增 Objective-C 异常捕获并进行安全降级处理。  
  Prevented crashes caused by invalid `NSExpression` formats by adding Objective-C exception catching with safe fallback.  
  _SmartTextService.swift, ObjcExceptionCatcher.h/.m, Deck-Bridging-Header.h_

- **清空数据后数据库文件未实际释放**  
  在清空数据流程中执行 WAL checkpoint 与 VACUUM，确保数据库文件占用被真实回收。  
  Ensured database file space is fully released after clearing data by running WAL checkpoint and VACUUM.  
  _DeckSQLManager.swift_

- **上下文感知排序初始化时序问题**  
  修复初始化与 `preApp` 注入时机不当导致 `lastNonDeck` 为空的问题。  
  Fixed an initialization timing issue in context-aware sorting where `lastNonDeck` could be nil due to early `preApp` injection.  
  _AppDelegate.swift, MainWindowController.swift, ContextAwareService.swift_

- **Swift 6 并发捕获警告**  
  修复因表达式快照（expr capture）引发的 Swift 6 并发警告。  
  Resolved Swift 6 concurrency warnings related to expression snapshot capturing.  
  _SmartTextService.swift_

---

### 兼容性与行为说明 / Compatibility & Behavior Notes

- 本次更新仅包含稳定性与安全性修复，不引入行为破坏性变更。  
  This release contains stability and safety fixes only, with no breaking behavior changes.

- 数据库结构未变更，可直接覆盖升级。  
  No database schema changes; safe for in-place upgrade.

---

### 升级建议 / Upgrade Notes

- 强烈建议所有用户升级，以获得更稳定的脚本插件执行、更安全的智能文本处理以及更可靠的数据库空间回收行为。  
  All users are strongly recommended to upgrade for improved script execution stability, safer smart text handling, and reliable database space reclamation.

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

### 新增 / New

- **CLI Bridge 独立设置栏目**  
  新增左侧「CLI Bridge」独立栏目，用于集中管理配置与查看使用说明。  
  Added a dedicated “CLI Bridge” section in the sidebar for configuration and documentation.

- **CLI Bridge 使用与测试说明**  
  新增健康检查、写入/读取示例与可选 alias 配置说明。  
  Added usage and testing docs including health check, read/write examples, and optional aliases.

- **IDE 溯源锚点与深链跳转**  
  支持采集 file / line / col / IDE 信息，并在详情预览中提供“在 IDE 中打开”按钮。  
  Added IDE source anchors (file/line/col/IDE) with deep-linking and an “Open in IDE” action.

- **`source_anchor` 持久化与同步**  
  新增数据库字段，并支持导出 / 导入与 iCloud 同步。  
  Persisted `source_anchor` with DB storage, export/import support, and iCloud sync.

- **VS Code 系套壳支持**  
  支持 Cursor / Windsurf / Antigravity（bundleId 识别、CLI 与 URL scheme 跳转）。  
  Added support for Cursor, Windsurf, and Antigravity IDEs via bundle ID detection and deep links.

- **链接转图片（Cmd+Shift+V）**  
  将链接转换为可分享的预览卡片图片，包含标题、摘要、域名、站点图标与首图。  
  Convert links into shareable preview card images with title, summary, domain, favicon, and cover image.

---

### 优化 / Improvements

- **设置结构调整**  
  将 CLI Bridge 配置从「通用」迁移至独立栏目，减少设置混杂。  
  Moved CLI Bridge settings out of General into its own section.

- **来源捕捉策略改进**  
  优先使用 `preApp`，并将 AX 读取范围扩展到 MainWindow / Windows 子树搜索。  
  Source capture now prefers `preApp` and extends AX scanning into window subtrees.

- **Bundle ID 归一化**  
  自动将 helper 映射回主应用 bundleId，提升识别准确性。  
  Normalized helper bundle IDs to their parent apps.

- **链接卡片渲染体验**  
  去除白边、下移文字区域；图片自适应高度，长图完整展示，并用模糊背景填充。  
  Improved card layout with no white margins, adaptive height, full long-image rendering, and blurred fill.

- **快捷键与流程一致性**  
  Cmd+Shift+V 在光标助手开启时可用；队列模式仍优先处理队列。  
  Cmd+Shift+V now works with Cursor Assistant active; queue mode still takes precedence.

- **本地化补充**  
  为 CLI Bridge 与 “在 IDE 中打开”补充英 / 德文翻译。  
  Added English and German localizations for CLI Bridge and IDE actions.

---

### 修复 / Fixes

- 修复 CLI Bridge 本地 HTTP 服务无响应问题（连接处理器被释放导致无返回）。  
  Fixed a local HTTP server issue where released handlers caused no response.

- 修复 AX CFTypeRef / AXValue 转换警告与编译错误。  
  Fixed AX CFTypeRef/AXValue conversion warnings and build errors.

- 修复 iCloud 同步解密后 `sourceAnchor` 赋值缺失的问题。  
  Fixed missing `sourceAnchor` assignment after iCloud decryption.

- 修复 Cmd+Shift+V 生成图片后无法连续使用的问题。  
  Fixed repeated use of Cmd+Shift+V after image generation.

- 修复从富文本来源复制的链接预览为空白的问题。  
  Fixed blank previews when copying links from rich-text sources.

- 修复 Swift 6 并发环境下的锁警告，缓存读写改为异步安全访问。  
  Fixed Swift 6 concurrency lock warnings by switching cache access to async-safe patterns.

---

### 技术变更 / Technical Changelog

- **SourceAnchor Pipeline**  
  新增采集、持久化、同步与导出支持。  
  Implemented capture, persistence, sync, and export for source anchors.

- **Link Metadata Pipeline**  
  统一链接抓取、缓存与图片渲染管线，预览卡与图片生成复用同一数据源。  
  Unified link metadata fetch/cache/render pipelines for previews and images.

- **CLI Bridge Service**  
  强化连接生命周期管理，避免 handler 提前释放。  
  Improved connection lifecycle management in CLI Bridge.

---

### 本地化 / Localization

- 新增 CLI Bridge 与 IDE 操作相关的英文 / 德文翻译。  
  Added en/de localizations for CLI Bridge and IDE actions.

---

### 兼容性与行为说明 / Compatibility & Behavior Notes

- CLI Bridge 仅监听 127.0.0.1，保持原有安全边界不变。  
  CLI Bridge continues to listen only on 127.0.0.1.

- 本次更新不包含破坏性数据库结构变更，可直接覆盖升级。  
  No breaking database schema changes; safe for in-place upgrade.

---

### 升级建议 / Upgrade Notes

- 推荐升级以获得更完善的 IDE 溯源能力、更顺滑的链接分享体验与更稳定的 CLI Bridge。  
  All users are recommended to upgrade for improved IDE tracing, link sharing, and CLI Bridge stability.

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

### 新增 / New

- **隐私增强：证件号智能识别**  
  新增对身份证（中国 / 台湾 / 香港）、护照、德国税号、美国 SSN / ITIN 的识别能力；支持隐私开关，检测到后可自动跳过保存。  
  Added intelligent detection for ID numbers (CN/TW/HK ID, passport, German tax ID, US SSN/ITIN) with a privacy toggle to skip saving detected content.

- **临时剪贴板条目（Temporary Items）**  
  新增“临时”剪贴板项，粘贴一次后自动销毁；可在条目菜单中启用，并提供明确的视觉标识。  
  Added temporary clipboard items that self-destruct after a paste, accessible from the item menu with a clear visual indicator.

- **文本隐写（Steganography）**  
  支持将文本隐藏进图片（LSB）或文本（零宽字符），并在剪贴板历史中自动检测与解码；  
  采用 AES-GCM 加密，可选共享口令，安全存储于 Keychain。  
  Added text steganography: hide text in images (LSB) or text (zero-width chars), with auto-detect and decode in clipboard history; encrypted via AES-GCM with optional shared passphrase stored in Keychain.

- **OCR 设置面板**  
  通用设置中新增 OCR 设置区域，包含识别级别、语言纠错、最大文本长度与语言开关，UI 与现有设置体系保持一致。  
  Added an OCR settings section to General Settings, matching the existing design system and exposing recognition level, language correction, max text length, and language toggles.

---

### 优化 / Improvements

- **安全模式行为强化**  
  安全模式下加密失败将拒绝明文回退，仅触发一次用户可见提示；应用名称纳入加密 / 解密流程并参与迁移，确保隐私一致性。  
  Security mode now rejects plaintext fallback on encryption failures with a single user-facing alert; app name is encrypted/decrypted and included in migrations for consistent privacy.

- **数据库与同步稳定性**  
  数据库状态与重初始化流程完全序列化至 `dbQueue`；  
  iCloud 与局域网同步不再在 detached task 中捕获 `ClipboardItem`，一致性与稳定性提升。  
  DB state and reinitialization are fully serialized on `dbQueue`; iCloud and LAN group sync no longer capture `ClipboardItem` in detached tasks.

- **迁移与大图处理**  
  大图迁移采用 keyset pagination，仅在完成后提升 schema 版本；  
  嵌入式迁移在加密错误时安全失败，不破坏已有数据。  
  Large-image migration now uses keyset pagination and only bumps schema version after completion; embedding migration fails safe on encryption errors.

- **剪贴板与分享流程**  
  文件粘贴统一使用 `NSPasteboardItem + NSFilenamesPboardType`；  
  局域网接收写入通过 `dbQueue` 执行；  
  iCloud 同步可基于 DB id 重建条目。  
  File pasteboard writes now use `NSPasteboardItem + NSFilenamesPboardType`; LAN group receive inserts through `dbQueue`; iCloud sync can rebuild items from DB ids.

- **搜索与检测一致性**  
  FTS 与搜索路径统一读取 `dbQueue` 状态；  
  安全模式下搜索缓存会解密 `appName`；  
  修复文件名如 `deck-...@1x.png` 被误判为邮箱的问题。  
  Search paths now read `dbQueue` state consistently; search cache decrypts `appName` in security mode; filenames like `deck-...@1x.png` no longer trigger email detection.

- **导出与 UI 反馈**  
  导出成功弹窗显示真实导出数量，而非当前内存页大小。  
  Export success dialog now reports the actual exported count instead of the in-memory page size.

- **隐写体验改进**  
  隐写密钥 UI 自适应窄布局，确保保存 / 清除按钮始终可见；  
  自动解码发生在“仅聚焦文本”过滤之前；  
  新增“存储并复制（store & copy）”流程。  
  Stego key UI now adapts to narrow layouts; auto-decode happens before focus-text-only filtering; added a new “store & copy” flow for stego outputs.

---

### 修复 / Fixes

- 修复零宽字符隐写解码稳定性问题。  
  Fixed zero-width text decoding reliability issues.

- 修复透明 PNG 在图片隐写中的处理问题。  
  Fixed transparent PNG handling in image steganography.

- 修复本地化表冲突，统一整合至 `Localizable.xcstrings`。  
  Fixed localization table conflicts by consolidating into `Localizable.xcstrings`.

- 修复 Smart Rules 中的正则处理、忽略逻辑、标签创建与分享 URL 编码问题。  
  Fixed regex handling, ignore behavior, tag creation, and share URL encoding in Smart Rules.

- 修复 OCR 回调未保证主线程完成的问题。  
  Ensured OCR completion handlers always return on the main thread.

---

### 技术变更 / Technical Changelog

- **ScriptPluginService.swift**  
  新增基于 hash 的网络授权；  
  改进超时与中断处理；  
  执行逻辑移出主线程。  
  Added hash-based network authorization, safer timeout/interrupt handling, and moved execution off the main thread.

- **UserDefaultsManager.swift**  
  新增并迁移网络插件授权与 OCR 设置持久化。  
  Added persistence and migration for network plugin authorizations and OCR settings.

- **DirectConnectService.swift**  
  预共享密钥（PSK）迁移至 Keychain；  
  强化缓冲区解析与连接处理。  
  Moved PSKs to Keychain, hardened buffer parsing, and improved connection handling.

- **PasteQueueHUDController.swift**  
  队列 HUD 标签由 emoji 改为 ASCII 文本。  
  Replaced emoji labels with ASCII tags in the paste queue HUD.

---

### 本地化 / Localization

- 新增隐私、隐写与告警相关的英文 / 德文翻译。  
  Added English and German localizations for new privacy, stego, and alert UI.

- 新增队列模式帮助文案与操作标签的 en / de 翻译。  
  Added en/de localizations for queue-mode help text and action labels.

- 清理 17 个未使用 key（旧占位符、废弃 `%lld` 变体等），消除 “References to this key…” 警告。  
  Removed 17 unused keys to clear “References to this key…” warnings.

- 补全缺失翻译，标记 zh-Hans 的版本 / 导入确认文案为已翻译状态。  
  Filled missing translations and marked zh-Hans entries for version/import prompts as translated.

---

### 兼容性与行为说明 / Compatibility & Behavior Notes

- 本次更新不包含数据库结构破坏性变更，可直接覆盖升级。  
  This release introduces no breaking database schema changes and supports in-place upgrades.

- 所有隐私处理、检测与加密均在本地完成。  
  All privacy processing, detection, and encryption are performed locally.

---

### 升级建议 / Upgrade Notes

- 推荐所有用户升级，以获得更强的隐私保障、更稳定的同步与迁移流程，以及全新的临时剪贴板与隐写能力。  
  All users are recommended to upgrade for stronger privacy guarantees, more robust sync and migration, and the new temporary and steganography features.

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

### 新增 / New

- 链接右键菜单新增「在默认浏览器中打开」「显示二维码」。二维码以全屏毛玻璃遮罩显示，支持 ESC 或点击空白退出，退出后自动回到 Deck 面板。  
  Added “Open in Default Browser” and “Show QR Code” actions to link context menu. QR code is displayed in a full-screen frosted overlay, dismissible via ESC or background click, and returns focus to Deck.

- 新增二维码全屏遮罩 UI：毛玻璃背景、居中二维码 + 标题与链接信息，适合快速分享。  
  Added a full-screen QR overlay with frosted background and centered QR code plus title and URL for easy sharing.

- 文件与文件夹搜索支持按文件名匹配；历史数据后台无损回填，不修改表结构、不丢失记录。  
  File and folder search now includes file name indexing, with non-destructive background backfilling and no schema changes.

- Office 文件支持空格预览（QuickLook），与 PDF 预览保持统一的面板结构与交互。  
  Added QuickLook preview for Office documents, sharing the same panel framework as PDF preview.

- 欢迎引导新增「队列模式」介绍与快捷键说明。  
  Added queue mode introduction and shortcuts to the onboarding flow.

- 设置页新增队列模式快捷键与使用提示，提升功能可发现性。  
  Added queue mode shortcut hints and usage tips in Settings.

---

### 优化 / Improvements

- 链接预览 UI 重做：展示 favicon、站点标题、站点名与完整 URL，列表卡片与空格预览保持一致。  
  Redesigned link preview UI to show favicon, title, site name, and URL, consistent between list and preview panel.

- 预览系统复用列表缓存与 in-flight 请求，避免重复网络获取。  
  Preview now reuses list cache and in-flight requests to avoid duplicate fetches.

- 全屏与多屏场景下的面板显示稳定性提升：始终跟随前台应用所在屏幕与 Space。  
  Improved panel stability in full-screen and multi-display setups by following the active app’s screen and Space.

- 双击 Option 打开面板时键盘焦点更稳定，空格预览可靠性提升。  
  Improved keyboard focus stability when opening the panel via double-Option, and improved Space preview reliability.

- 面板开合时输入模式与搜索焦点恢复更符合直觉。  
  Input mode and search focus now restore more intuitively when opening or closing the panel.

- 顶栏四个圆形按钮点击区域扩大（添加标签 / 设置 / 暂停 / 退出），减少误触与漏点。  
  Increased hit areas of the four top buttons (Tag, Settings, Pause, Quit) for better usability.

- 新增并完善中 / 英 / 德多语言翻译（右键菜单、二维码提示、搜索空态文案等）。  
  Added and refined Chinese, English, and German localizations for context menus, QR hints, and empty state texts.

---

### 修复 / Fixes

- 修复设置页「存储信息」中剪贴板条目数显示为 0 的问题，现在显示数据库真实总数。  
  Fixed clipboard item count showing as 0 in Storage Info; it now reflects the actual database total.

- 修复面板关闭后输入模式与焦点恢复异常的问题。  
  Fixed incorrect input mode and focus restoration after closing the panel.

- 修复顶部按钮点击区域过小的问题。  
  Fixed overly small hit areas on the top buttons.

- 修复搜索无结果时空态提示文案误导的问题。  
  Fixed misleading empty-state messaging when search yields no results.

- 修复安全作用域书签在频繁路径检查时访问计数累积的问题。  
  Fixed security-scoped bookmarks accumulating access counts under frequent path checks.

- 修复数据库错误跟踪状态未序列化导致重复通知与重复恢复的问题。  
  Fixed DB error tracking not being serialized, causing duplicate notifications and recovery attempts.

- 修复大图卸载逻辑中 data 与 preview_data 同时存储缩略图的问题。  
  Fixed large image offload storing duplicate thumbnails in both data and preview_data.

- 修复 Swift 6 async 锁相关的数据库错误跟踪编译问题。  
  Fixed Swift 6 async lock issues in DB error tracking.

---

### 技术变更 / Technical Changelog

- DeckSQLManager.swift：补充完整类级注释，明确职责边界、线程模型与安全模式语义。  
  Added comprehensive class-level documentation clarifying responsibilities, threading model, and security semantics.

- DeckSQLManager.swift：补充存储策略说明，包括大图处理、blobPath、备份恢复与迁移顺序约束。  
  Documented storage strategies including large image handling, blobPath usage, backup/restore, and migration ordering.

- 数据库初始化逻辑统一在 dbQueue 执行，确保顺序与线程安全。  
  Moved DB initialization consistently onto dbQueue for safer sequencing.

- 安全模式加密失败时输出明确警告，提升可诊断性。  
  Added explicit warnings when security mode encryption fails.

---

### 兼容性与行为说明 / Compatibility & Behavior Notes

- 本次更新不包含数据库结构变更，可直接覆盖升级。  
  This release introduces no database schema changes and supports in-place upgrades.

- 所有处理逻辑均在本地完成，不上传、不存储任何用户数据。  
  All processing remains local with no data uploaded or stored remotely.

---

### 升级建议 / Upgrade Notes

- 推荐所有用户升级以获得更稳定的多屏体验、更直观的链接与二维码分享流程，以及更可靠的搜索与预览系统。  
  All users are recommended to upgrade for improved multi-display stability, smoother link and QR sharing workflows, and more reliable search and preview behavior.

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

### 新增 / New

- 面板内支持 ⌘, 打开设置（与齿轮按钮等效）。  
  Added support for ⌘, to open Settings directly from the panel, equivalent to the gear button.

- 面板新增“暂停”按钮（位于设置与退出之间），可一键暂停/恢复剪贴板记录。  
  Added a “Pause” button in the panel (between Settings and Quit) to quickly pause or resume clipboard recording.

- 暂停后按钮向右展开显示“已暂停 / 倒计时”，并与菜单栏暂停状态保持同步。  
  When paused, the button expands to show “Paused / Countdown” and stays in sync with the menu bar pause state.

- Vim 模式新增“默认进入插入模式”开关：打开面板不自动搜索，首次输入自动进入搜索并保留字符。  
  Added an option for Vim mode to default into Insert mode: opening the panel no longer auto-enters search; typing starts search and preserves the first character.

- 插入模式下按 Esc 仅回到 Normal，不清空搜索内容，便于使用 j/k 导航。  
  In Insert mode, pressing Esc now only returns to Normal mode without clearing the search, enabling smoother j/k navigation.

- 光标助手触发键精简为 Shift，移除空格与 Tab 作为触发选项。  
  Simplified Cursor Assistant trigger to Shift only, removing Space and Tab as trigger options.

---

### 优化 / Improvements

- 搜索框增加描边与阴影，在深色模式下与背景及标签区域区分更加明显。  
  Added border and shadow to the search field for better separation from the background and tag area, especially in dark mode.

- 暂停状态提示从搜索框右侧移除，统一收拢到暂停按钮内部显示，界面更简洁。  
  Moved pause status indicator into the Pause button instead of showing it beside the search field for a cleaner UI.

- 菜单栏图标改为 template 渲染，自动适配深色 / 浅色 / 半透明菜单栏背景。  
  Updated the menu bar icon to use template rendering so it adapts automatically to light, dark, and translucent menu bars.

- 暂停按钮改为胶囊样式并使用橙色高亮，状态变化更直观。  
  Updated the Pause button to a capsule style with orange highlight for clearer state feedback.

- 本地化完善：新增 Vim 插入模式相关文案的中 / 英 / 德翻译，“已暂停”等状态提示也补充英 / 德版本。  
  Improved localization by adding Chinese, English, and German translations for Vim Insert mode and pause-related status messages.

---

### 修复 / Fixes

- 修复使用 Ctrl 打开面板后，点击空白区域无法关闭的问题，使所有打开方式行为一致。  
  Fixed an issue where the panel could not be closed by clicking outside when opened via Ctrl.

- 修复清空搜索词后列表仍停留在过滤状态、未恢复默认排序的问题。  
  Fixed an issue where clearing the search did not restore the full list and default sorting.

- 修复开启 Vim 插入模式后首字符未进入搜索的问题，现在会自动进入并保留输入。  
  Fixed an issue where the first character was not captured when entering search in Vim Insert mode.

- 修复点击预览窗口时误触发面板关闭的问题。  
  Fixed an issue where clicking the preview window could unintentionally close the panel.

- 自动进入搜索时过滤特殊键，避免空格、回车等误触发搜索模式。  
  Filtered special keys when auto-entering search to avoid accidental triggers from Space or Enter.

- 修复正则搜索崩溃问题：SQLite 自定义 regexp 函数改为返回 Int64(0/1)，避免 Optional(true) 导致 “unsupported result type” 的 fatal error。  
  Fixed a crash in regex search by changing the SQLite custom regexp function to return Int64(0/1), avoiding “unsupported result type” fatal errors.

---

### 预览与搜索增强 / Preview & Search Enhancements

- 正则搜索结果高亮：在纯文本预览中以黄色荧光笔样式高亮匹配字符串，并适配浅色 / 深色模式。  
  Added regex match highlighting in plain text preview with a yellow marker style adapted for both light and dark modes.

- 自动滚动到首个匹配：预览区域会自动滚动至第一个匹配位置；若匹配位于超长文本后段，则截取包含该匹配的文本片段进行展示。  
  Automatically scrolls the preview to the first match. If the match is deep inside very long text, the preview is truncated to show the relevant segment.

---

### 技术变更 / Technical Changelog

- LargeTextPreviewView.swift：接入正则高亮与自动滚动到首个匹配的逻辑。  
  Implemented regex highlighting and first-match auto-scrolling in LargeTextPreviewView.swift.

- PreviewWindowController.swift / PreviewOverlayView.swift：接入预览匹配定位逻辑。  
  Wired preview match positioning into PreviewWindowController.swift and PreviewOverlayView.swift.

- DeckSQLManager.swift：修复 regexp 返回类型导致的崩溃问题。  
  Fixed regexp return type crash in DeckSQLManager.swift.

---

### 兼容性与行为说明 / Compatibility & Behavior Notes

- 本次更新不包含数据库结构变更，可直接覆盖升级。  
  This release introduces no database schema changes and supports in-place upgrades.

- 所有处理逻辑均在本地完成，不上传、不存储任何用户数据。  
  All processing remains local with no data uploaded or stored remotely.

---

### 升级建议 / Upgrade Notes

- 推荐所有用户升级以获得更流畅的 Vim 操作体验、更清晰的暂停状态反馈以及更稳定的搜索与预览行为。  
  All users are recommended to upgrade for smoother Vim workflows, clearer pause state feedback, and more stable search and preview behavior.

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

### 新增 / New

- 新增自动清理触发词功能：在插入模板内容前自动删除触发词（如 `num`），无需手动清理多余字符，插入过程更加干净流畅。  
  Added automatic trigger word cleanup. The app now deletes the trigger word (e.g. `num`) before inserting template content, ensuring clean insertion without manual cleanup.

- 新增“重要”系统标签：可在右键菜单中一键标记或取消标记。所有被打上任意标签（包括“重要”与自定义标签）的记录将不再参与自动清理与自动删除，除非手动删除。  
  Added a system “Important” tag, toggleable via right-click. Any item with a tag (system or custom) will be excluded from auto-clean and auto-delete, ensuring permanent retention unless manually removed.

- 模板库设置页「添加短语」改为按钮 + 弹窗交互，与“编辑 / 删除”保持一致，统一整体设计语言。  
  Changed “Add Phrase” in the template library settings to a button + modal interaction, matching Edit/Delete behavior for a more consistent UI language.

---

### 优化 / Improvements

- 优化中文输入体验：修复了在中文输入法下，触发词回车上屏后光标助手无法被唤起的问题。现在无论输入状态如何，识别均稳定可靠。  
  Improved Chinese IME handling. Fixed an issue where committing text with Enter would prevent the Cursor Assistant from triggering. Detection is now stable regardless of input state.

- 优化剪贴板弹出面板 UI：采用更符合视觉习惯的布局与排版，并增强文字可读性。  
  Improved the clipboard panel UI with more visually natural layout and enhanced text readability.

- 光标助手支持点击空白处立即关闭，并确保关闭后自动删除触发词。  
  The Cursor Assistant now closes immediately when clicking on empty space, and ensures the trigger word is removed upon closing.

- 预览更新改为合并刷新：快速切换时不再高频刷新，停止操作后再更新最终项，浏览更稳定、更省电。  
  Preview updates are now batched and merged. The UI updates only after navigation stops, reducing refresh frequency, improving stability and power efficiency.

---

### 修复 / Fixes

- 修复备忘录复制图片在 Deck 中不显示的问题，扩展图像粘贴类型并支持 RTFD / flat-RTFD 附件图像解析与占位符判定。  
  Fixed an issue where images copied from Notes were not displayed in Deck. Expanded supported image paste types and added RTFD / flat-RTFD attachment parsing.

- 修复长按左右键快速切换时预览窗口与滚动动画造成的高频窗口更新与唤醒，显著降低 Wakes / CPU 使用。  
  Fixed excessive window updates and wake-ups caused by rapid key navigation, significantly reducing CPU usage and wake events.

- 修复打开面板时首条记录偶发不显示聚焦环的问题，确保首条始终正确选中。  
  Fixed an issue where the first item occasionally lacked a focus ring when opening the panel.

- 修复 macOS 14 下 `activateIgnoringOtherApps` 的弃用警告，采用新系统推荐激活方式，同时保持旧系统兼容。  
  Fixed the deprecation warning for `activateIgnoringOtherApps` on macOS 14 by adopting the new activation strategy while maintaining backward compatibility.

---

### 技术变更 / Technical Changelog

- Fix: 修复中文输入法回车上屏导致上下文丢失的问题，引入 AXUIElement 屏幕读取作为兜底机制，从屏幕上下文识别触发词。  
  Fixed context loss when committing Chinese IME input. Added AXUIElement-based screen reading as a fallback trigger detection mechanism.

- Feat: 新增自动回退逻辑，根据触发词长度模拟 Delete 键事件，在粘贴前清理输入内容。  
  Added auto-backspace logic. The app now calculates trigger word length and simulates Delete key events before pasting.

- 完善本地化：补齐英语 / 德语缺失翻译，并修正统计页动态“次数”文案为标准格式化字符串。  
  Improved localization by completing missing English and German translations and fixing formatted count strings on the Statistics page.

---

### 兼容性与行为说明 / Compatibility & Behavior Notes

- 本次更新不包含破坏性数据库结构变更，可直接覆盖升级。  
  This release introduces no breaking database schema changes and supports in-place upgrades.

- 所有识别与处理逻辑均在本地完成，不上传、不存储任何敏感内容。  
  All recognition and processing is performed locally with no data uploaded or stored remotely.

---

### 升级建议 / Upgrade Notes

- 推荐所有用户升级以获得更稳定的输入体验、更低的功耗表现以及更一致的交互行为。  
  All users are recommended to upgrade for improved input stability, lower power usage, and more consistent interactions.

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

### 问题 / Issues

- 在「网络」页面点击已连接设备旁的刷新按钮时，应用会直接崩溃。  
  The app would crash when clicking the refresh button next to a connected device on the Network page.

- 在开启安全模式后，系统指纹认证弹窗点击“取消”会闪烁并不断重复出现，无法正常关闭。  
  In Secure Mode, the system fingerprint authentication dialog would flicker and repeatedly reappear after pressing “Cancel”.

- 缺少对银行卡号的系统性识别与校验逻辑，存在误识别与漏识别风险。  
  There was no systematic mechanism for recognizing and validating bank card numbers, leading to false positives and missed detections.

---

### 修复与改进 / Fixes & Improvements

- 修复了点击已连接设备刷新按钮导致应用崩溃的问题。  
  Fixed a crash when clicking the refresh button next to connected devices.

- 修复了安全模式下指纹认证弹窗取消后闪烁并重复弹出的异常行为。  
  Fixed an issue where the fingerprint authentication dialog would flicker and repeatedly appear after cancellation in Secure Mode.

- 新增银行卡号识别功能，并采用多策略校验以提高准确性与安全性：  
  Added bank card number recognition with multi-strategy validation for improved accuracy and safety:
  - 长度匹配  
    Length matching  
  - 前缀匹配（BIN 规则）  
    Prefix matching (BIN rules)  
  - 轻量级 Luhn 校验算法  
    Lightweight Luhn algorithm validation  

- 支持自定义模板库，并为每个模板库配置独立的光标助手触发词，实现快速调用与插入预设内容。  
  Added support for custom template libraries with per-library trigger keywords for the Cursor Assistant, enabling fast access and insertion of preset content.

---

### 兼容性与行为说明 / Compatibility & Behavior Notes

- 本次更新不引入数据库结构破坏性变更，可直接覆盖升级。  
  This release introduces no breaking database schema changes and can be installed as an in-place upgrade.

- 银行卡识别仅在本地进行，不会上传或记录任何敏感数据。  
  Bank card recognition is performed locally and does not upload or store any sensitive information.

- 模板库与触发词为本地配置，不会影响现有模板内容。  
  Template libraries and trigger keywords are local-only and do not affect existing templates.

---

### 升级建议 / Upgrade Notes

- 建议所有用户升级至此版本以避免崩溃问题并获得更稳定的安全模式体验。  
  All users are recommended to upgrade to avoid crashes and obtain a more stable Secure Mode experience.

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

本版本为紧急修复更新，重点解决主线程被数据库同步查询阻塞导致的异常耗电、频繁唤醒与卡顿问题。
This is a hotfix release focused on eliminating abnormal battery drain, frequent wake-ups, and stutters caused by synchronous DB work on the main thread.

* * *

### 优化 / Improvements

  * 数据库访问统一走串行 `dbQueue` 的异步执行，并通过 `await` 获取结果，显著降低主线程压力与能耗。
Unified DB access to run asynchronously on the serial `dbQueue` and `await` results, significantly reducing main-thread load and energy impact.

  * 异步闭包补充显式 `self` 捕获，线程/并发语义更清晰，避免隐式捕获带来的可读性与维护成本。
Async closures now explicitly capture `self` for clearer concurrency semantics and easier maintenance.

* * *

### 修复 / Fixes

  * 修复：主线程同步等待数据库队列执行 SQLite 查询导致 CPU 长时间繁忙与频繁唤醒（异常耗电）。
Fixed: The main thread synchronously waiting on the DB queue caused sustained CPU activity and frequent wake-ups (abnormal battery drain).

  * 修复：搜索、FTS、统计、导出等路径在 UI 线程触发同步 SQL，放大能耗与卡顿。
Fixed: Search, FTS, stats, and export paths triggering synchronous SQL on the UI thread amplified energy use and UI stutters.

  * 修复：搜索、FTS、向量检索与迁移等查询路径改为异步 DB 调用，阻断主线程 SQL 扫描与阻塞等待。
Fixed: Search, FTS, vector queries, and migration paths now use async DB calls to prevent main-thread SQL scans and blocking waits.

  * 修复：统计与导出改为异步读取数据库，UI 线程不再直接执行 SQL。
Fixed: Stats and export now read the DB asynchronously, so the UI thread no longer executes SQL directly.

* * *

### 技术变更 / Technical Changelog

  * 将原先可能发生在主线程上的同步 DB 查询/写入，统一改为通过 `dbQueue` 异步执行并 `await` 返回。
Reworked synchronous DB reads/writes that could occur on the main thread to run asynchronously on `dbQueue` and `await` results.

  * 将高频路径（搜索/FTS/统计/导出/迁移等）切换到异步 DB 调用，避免 UI 线程被同步等待拖住。
Moved high-frequency paths (search/FTS/stats/export/migrations) to async DB calls to avoid UI thread stalls.

* * *

### 兼容性与行为说明 / Compatibility & Behavior Notes

  * 本版本为性能与能耗修复更新，不引入新的用户交互流程。
This is a performance/energy hotfix and does not introduce new user interaction flows.

  * 所有处理逻辑均在本地完成，不上传、不存储任何用户数据。
All processing remains local with no data uploaded or stored remotely.

* * *

### 升级建议 / Upgrade Notes

  * 强烈建议所有 v1.1.0 用户升级至此版本，尤其是遇到明显耗电、频繁唤醒或面板卡顿的情况。
Strongly recommended for all v1.1.0 users, especially if you experienced battery drain, frequent wake-ups, or UI stutters.

* * *

### 致谢 / Notes

  * 祝大家新的一年身体健康，事业顺利，家庭和睦。
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

### 新增 / New

- 快速搜索：打开面板后直接输入文字即可自动进入搜索模式，无需先点击搜索框，支持中文输入法（Vim 模式下自动禁用）。  
  Quick Search: After opening the panel, simply type to automatically enter search mode without clicking the search field. Supports Chinese IME. Disabled in Vim mode.

### 优化 / Improvements

- 优化多语言支持，提升翻译覆盖率与准确性。  
  Improved multilingual support by expanding translation coverage and accuracy.

- 修复并优化内存与 CPU 占用，显著提升应用稳定性。  
  Fixed and optimized memory and CPU usage for significantly improved stability.

- 改进设置和欢迎界面的 UI 设计，采用类似 Material Design 的风格，提高文字可读性与可见性。  
  Enhanced the Settings and Welcome UI with a Material Design-inspired style, improving text readability and visibility.

- 修复打开面板后第一个卡片不显示选中状态的问题。  
  Fixed an issue where the first card wasn't displayed as selected upon opening the panel.

- 针对其他已知问题进行了若干优化。  
  Implemented several targeted optimizations for other known issues.

---

### 致谢 / Notes

- 这是 Deck 在 2026 新年前的最后一个版本更新，祝大家新年快乐！  
  This is Deck's final update before the New Year 2026. Happy New Year to everyone!

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

### 新增 / New

- **语义搜索引擎升级**：引入 Apple Sentence Embedding 并与 sqlite-vec 进行静态集成，排序逻辑下沉至数据库内部执行，响应更快、内存占用更低。  
  **Semantic search engine upgrade:** Integrated Apple Sentence Embedding with sqlite-vec (static), moving sorting into the database layer for faster responses and lower memory usage.

- **混合搜索模式优化**：文本搜索与语义搜索结果融合排序，提高相关性与召回稳定性。  
  **Smarter hybrid mode:** Merged text and semantic results for higher relevance and more stable recall.

- **中文检索体验增强**：引入 FTS5 trigram 分词策略，显著提升 CJK 文本搜索的准确度与性能。  
  **Enhanced Chinese search:** Enabled FTS5 trigram tokenization for more accurate and faster CJK retrieval.

---

### 优化 / Improvements

- **OCR 性能优化**：对超大图片进行下采样处理，降低卡顿概率并减少内存峰值。  
  **OCR performance optimization:** Downsamples large images to reduce UI lag and memory spikes.

- **同步与数据库稳定性增强**：优化 CloudKit 批量提交流程，并加入自动备份、完整性校验与恢复机制。  
  **Sync and database stability:** Improved CloudKit batch submission and added automatic backup, integrity checks, and recovery mechanisms.

- **内存占用大幅下降**：整体内存使用从约 300MB 降至约 50MB。  
  **Memory optimization:** Reduced memory usage from ~300MB to ~50MB.

---

### 技术变更 / Technical Changelog

- 引入 sqlite-vec 静态链接版本，避免动态扩展加载的不确定性并提升启动稳定性。  
  Integrated sqlite-vec as a static component to avoid dynamic extension issues and improve startup reliability.

- 搜索排序逻辑由应用层迁移至数据库层执行，减少数据拷贝与中间态内存占用。  
  Moved search result sorting into the database layer to reduce data copying and intermediate memory usage.

- FTS5 配置升级为 trigram tokenizer，更适配中文与日韩文本。  
  Updated FTS5 configuration to use trigram tokenizer for better CJK support.

---

### 兼容性与行为说明 / Compatibility & Behavior Notes

- 本次更新不包含数据库结构变更，可直接覆盖升级。  
  This release introduces no database schema changes and supports in-place upgrades.

- 所有搜索、识别与处理逻辑均在本地完成，不上传、不存储任何用户内容。  
  All processing is performed locally with no data uploaded or stored remotely.

---

### 升级建议 / Upgrade Notes

- 推荐所有用户升级以获得显著更快的搜索体验、更低的内存占用以及更稳定的数据同步行为。  
  All users are recommended to upgrade for significantly faster search, lower memory usage, and more stable syncing.

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

### 新增 / New

- **版本号更新**：内部版本标识与发布标签同步整理。  
  **Version number update:** Aligned internal version identifiers with the release tag.

- **图标尺寸优化**：调整应用图标在 Dock、菜单栏与设置界面的显示比例，提升视觉一致性。  
  **Icon size optimization:** Refined icon sizing across Dock, menu bar, and settings for better visual consistency.

---

### 兼容性与行为说明 / Compatibility & Behavior Notes

- 本次更新不包含功能与数据层变更，仅涉及外观与版本标识调整。  
  This release introduces no functional or data changes, only visual and versioning adjustments.

---

### 升级建议 / Upgrade Notes

- 建议所有用户升级以获得更一致的视觉体验与正确的版本标识。  
  All users are recommended to upgrade for improved visual consistency and correct version labeling.

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

### 新增 / New

- **应用图标更新**：替换为全新设计的应用图标，在 Dock、菜单栏与设置界面中呈现更清晰一致的视觉风格。  
  **New app icon:** Replaced the application icon with a new design for improved visual consistency across Dock, menu bar, and settings.

---

### 优化 / Improvements

- **数据库文件校验**：在执行数据库操作前增加文件有效性校验，防止异常文件导致崩溃。  
  **Database file validation:** Added validation before database operations to prevent crashes caused by corrupted or invalid files.

---

### 修复 / Fixes

- **PRAGMA 表结构遍历修复**：修复 `PRAGMA table_info` 使用 `failableNext()` 迭代时可能跳过结果的问题。  
  **PRAGMA iteration fix:** Fixed iteration over `PRAGMA table_info` using `failableNext()` to ensure all rows are processed correctly.

- **FTS 搜索绑定与遍历修复**：修复全文搜索语句参数绑定与结果遍历异常的问题。  
  **FTS binding and iteration fix:** Fixed issues with binding and iterating over FTS search statements.

---

### 兼容性与行为说明 / Compatibility & Behavior Notes

- 本次更新不涉及数据库结构变更，可直接覆盖升级。  
  This release introduces no database schema changes and supports in-place upgrades.

- 所有处理逻辑均在本地完成，不上传、不存储任何用户数据。  
  All processing remains local with no data uploaded or stored remotely.

---

### 升级建议 / Upgrade Notes

- 推荐所有用户升级以获得更稳定的运行表现与更安全的数据处理流程。  
  All users are recommended to upgrade for improved stability and safer data handling.

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

### 新增 / New

- **鼠标滚轮模式**：支持使用鼠标滚轮在剪贴板记录之间快速滚动浏览。  
  **Mouse wheel mode:** Added support for navigating clipboard items using the mouse wheel.

- **Vim 按键系统增强**：改进 Normal / Insert 状态切换与按键响应，提升键盘导航的流畅度与一致性。  
  **Vim key system enhancements:** Improved Normal/Insert mode transitions and key handling for smoother keyboard navigation.

---

### 兼容性与行为说明 / Compatibility & Behavior Notes

- 本次更新不涉及数据库结构变更，仅包含交互与输入系统层面的增强。  
  This release introduces no database schema changes and focuses on interaction and input system improvements.

---

### 升级建议 / Upgrade Notes

- 推荐所有用户升级以获得更顺畅的键盘与鼠标混合操作体验。  
  All users are recommended to upgrade for a smoother combined keyboard and mouse workflow.

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

### 修复 / Fixes

- **数据库文件有效性检查**：新增 `isDatabaseFileValid()`，在每次数据库操作前检查文件是否存在且可读，防止异常文件导致崩溃。  
  **Database file validity check:** Added `isDatabaseFileValid()` to verify that the database file exists and is readable before each operation.

- **withDB 执行流程加固**：在执行前校验数据库文件有效性；当文件无效或被删除时：
  - 记录警告日志  
  - 触发错误处理机制并通知用户  
  - 异步尝试重新初始化数据库  
  - 返回 `nil` 而不是触发崩溃  
  **Hardened withDB flow:** Validate the database file before execution. If invalid or missing, the app logs a warning, notifies the user, attempts async recovery, and returns `nil` instead of crashing.

- **SQL 遍历安全修复**：将 PRAGMA 与 FTS 查询从不安全的 `for-in` 迭代改为使用 `failableNext()`，避免 `try!` 引发致命错误。  
  **Safe SQL iteration:** Replaced unsafe `for-in` iteration with `failableNext()` for PRAGMA and FTS queries to avoid fatal errors caused by `try!`.

---

### 技术说明 / Technical Notes

- `db.prepare(Table query)` 返回 `AnySequence<Row>`，其内部迭代器使用 `try!`，无法在外部安全捕获错误。  
  `db.prepare(Table query)` returns `AnySequence<Row>`, whose internal iterator uses `try!` and cannot be safely controlled externally.

- `db.prepare(String SQL)` 返回 `Statement`，可直接调用 `failableNext()` 实现安全错误处理。  
  `db.prepare(String SQL)` returns `Statement`, which allows safe iteration via `failableNext()`.

- 在执行前增加文件有效性校验，可以防止绝大多数因数据库文件被删除或移动导致的崩溃。  
  Validating the database file before execution prevents most crashes caused by deleted or moved database files.

---

### 兼容性与行为说明 / Compatibility & Behavior Notes

- 本次更新不涉及数据库结构与数据格式变更，可直接覆盖升级。  
  This release introduces no database schema or data format changes and supports in-place upgrades.

- 所有处理逻辑均在本地完成，不上传、不存储任何用户数据。  
  All processing remains local with no data uploaded or stored remotely.

---

### 升级建议 / Upgrade Notes

- 强烈建议所有用户升级以避免潜在的数据损坏与程序崩溃风险。  
  All users are strongly recommended to upgrade to prevent potential crashes and data corruption.

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

### 新增 / New

- **首次发布**：Deck 正式发布，一个现代化、原生、隐私优先的 macOS 剪贴板系统。  
  **Initial release:** Deck is officially launched — a modern, native, privacy-first clipboard OS for macOS.

- **完整剪贴板历史记录**：自动记录文本、图片、链接与文件，防止重要内容丢失。  
  **Clipboard history:** Automatically stores text, images, links, and files.

- **高性能搜索与过滤**：支持模糊搜索与快速筛选，毫秒级定位内容。  
  **Fast search & filtering:** Fuzzy search and filters for instant retrieval.

- **富预览支持**：支持图片、PDF、链接等内容的内嵌预览。  
  **Rich previews:** Inline preview for images, PDFs, and links.

- **键盘优先设计**：支持全局快捷键与 Vim 风格导航。  
  **Keyboard-first workflow:** Global hotkeys and optional Vim-style navigation.

- **安全与隐私**：所有数据本地存储，支持加密与生物识别解锁。  
  **Privacy & security:** All data stays local with encryption and biometric protection.

- **脚本与自动化能力**：支持插件与规则系统扩展剪贴板工作流。  
  **Scriptable pipeline:** Plugins and rules for automation and extensibility.

- **局域网共享**：支持局域网内 P2P 传输，无需云服务。  
  **LAN sharing:** Peer-to-peer local sharing without the cloud.

---

### 兼容性与行为说明 / Compatibility & Behavior Notes

- 本版本为首次发布版本，后续更新将逐步增强稳定性、性能与可扩展性。  
  This is the initial public release; future updates will focus on stability, performance, and extensibility.

- 所有处理逻辑均在本地完成，不上传、不存储任何用户数据。  
  All processing remains local with no data uploaded or stored remotely.

---

### 系统要求 / System Requirements

- macOS 14.0 (Sonoma) 或更新版本  
- Apple Silicon 或 Intel Mac（Universal Binary）

---

### 安装 / Installation

1. 下载 `Deck.dmg`  
   Download `Deck.dmg`

2. 将 `Deck.app` 拖入 Applications 文件夹  
   Drag `Deck.app` into the Applications folder

3. 如首次打开被系统拦截：  
   前往 **系统设置 → 隐私与安全性 → 安全性**，在“已阻止的 App”处点击 **仍要打开 / 允许打开**  
   If the app is blocked on first launch:  
   Go to **System Settings → Privacy & Security → Security**, then click **Open Anyway / Allow**

4. 按提示授予辅助功能权限（Accessibility）  
   Grant Accessibility permission when prompted


---

### 升级建议 / Upgrade Notes

- 建议关注后续更新以获得更稳定、更强大的剪贴板体验。  
  Users are encouraged to follow future updates for continued improvements.

### Assets

- [`Deck.dmg`](https://github.com/yuzeguitarist/Deck/releases/download/v1.0.0/Deck.dmg)
