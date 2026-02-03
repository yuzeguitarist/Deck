<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="photos/deck-macOS-Dark-1024x1024@1x.png">
    <source media="(prefers-color-scheme: light)" srcset="photos/deck-macOS-Default-1024x1024@1x.png">
    <img src="photos/deck-macOS-Default-1024x1024@1x.png" alt="Deck Logo" width="128" height="128">
  </picture>
</p>

<h1 align="center">Deck</h1>

<p align="center">
  <strong>A modern, native, privacy-first clipboard OS for macOS</strong>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#install">Install</a> •
  <a href="#quick-start">Quick Start</a> •
  <a href="#screenshots">Screenshots</a> •
  <a href="#contributing">Contributing</a> •
  <a href="#license">License</a> •
  <a href="#中文说明">中文</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS_14+-blue?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/swift-5.9+-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/license-GPL--3.0-green?style=flat-square" alt="License">
</p>

<p align="center">
  <strong>更新计划 / Update Schedule</strong><br>
  因作者将参加 2026 Apple Swift Student Challenge，本项目将于 2026 年 2 月暂停常规更新，预计 2026 年 3 月恢复。<br>
  The author will be participating in the 2026 Apple Swift Student Challenge; regular updates will pause in February 2026 and are planned to resume in March 2026.
</p>

---

## Features

- Clipboard history for text, images, files, colors, and links.
- Fast search with keyword, regex, and type filters.
- Slash-triggered search rules for app/date/type filters (include/exclude + multi-values).
- Per-item custom titles that are searchable and sync across devices.
- Figma clipboard detection with a dedicated preview.
- Smart Rules can filter items with custom titles.
- Link previews include a one-tap QR code for URLs.
- Missing files show warnings and are auto-cleaned after closing the panel.
- Tags and smart categories.
- Smart rules + JavaScript script plugins for automation.
- Context-aware ordering per app.
- Queue mode and keyboard-first workflow (Vim optional).
- LAN sharing with end-to-end AES-GCM encryption.
- Local-first privacy with Touch ID unlock.
- Clipboard steganography (image and zero-width text).
- Link cleaner (removes tracking parameters).
- Instant calculation for math expressions.
- Migration from other clipboard apps.
- Auto updates (daily checks + manual check in Settings).
- CLI bridge for local automation and external integrations.

## Integrations

- Deck x Orbit: radial app switcher + file hub (cursor ring, long-press trigger, drag-to-quit, file AirDrop/trash). https://github.com/yuzeguitarist/Orbit

## Install

- Download the latest `.dmg` from [Releases](https://github.com/yuzeguitarist/Deck/releases).
- Drag `Deck.app` into Applications.
- First launch: Control+Click Deck -> Open, then confirm.
- Grant **Accessibility** (and **Input Monitoring** if prompted) in `System Settings -> Privacy & Security`.

> Source is partially published; building the full app from source is not supported yet.

## Requirements

- macOS 14.0+
- Apple Silicon or Intel

## Quick Start

1. Launch Deck.
2. Press `Cmd + P` to open the panel.
3. Navigate with arrow keys and press `Enter` to paste.

### Shortcuts (default)

| Shortcut | Action |
|----------|--------|
| `Cmd + P` | Open Deck |
| `Enter` | Paste selected |
| `Shift + Enter` | Paste as plain text |
| `Cmd + Number` | Quick paste (1-9) |
| `Cmd + Q` | Toggle queue mode |
| `Space` | Toggle preview |
| `Esc` | Close |

Interaction notes:
- Type directly after opening the panel to search.
- Use the mouse wheel on the history list to switch focus between items.

More shortcuts (and Vim mode) are available in Settings.

## Screenshots

<p align="center">
  <img src="photos/DeckView2.png" alt="Deck main view" width="720">
</p>
<p align="center">
  <img src="photos/DeckSettings.jpg" alt="Deck settings" width="720">
</p>

## Contributing

We welcome contributions to the open-sourced parts! Please read our [Contributing Guide](CONTRIBUTING.md) before submitting a PR.

> All PRs must target the `dev` branch, not `main`.

## License

This project is **partially open source** under **GPL-3.0 with Commons Clause** - see [LICENSE](LICENSE).

**TL;DR**
- Free for personal, non-commercial use.
- You can modify the open-sourced modules.
- Derivatives must use the same license.
- Commercial use requires permission.

For commercial licensing, contact: yuzeguitar@gmail.com.

## Support

- [Report Bug](https://github.com/yuzeguitarist/Deck/issues/new?template=bug_report.md)
- [Request Feature](https://github.com/yuzeguitarist/Deck/issues/new?template=feature_request.md)
- [Discussions](https://github.com/yuzeguitarist/Deck/discussions)

---

# 中文说明

<p align="center">
  <strong>一款原生、注重隐私的 macOS 剪贴板 OS</strong>
</p>

## 功能特性

- 记录文本、图片、文件、颜色、链接的剪贴板历史。
- 支持关键词、正则、类型筛选的快速搜索。
- 斜杠 / 触发的搜索规则过滤（app/date/type，支持排除与多值）。
- 每条记录支持自定义标题，可搜索并随同步保持一致。
- 识别 Figma 剪贴板内容并提供专用预览。
- 智能规则支持“有自定义标题”条件。
- 链接预览提供“一键二维码”入口。
- 文件缺失会提示并在面板关闭后自动清理。
- 标签与智能分类。
- 智能规则 + JavaScript 脚本插件自动化。
- 上下文感知排序（按应用）。
- 队列模式与键盘优先操作（可选 Vim）。
- 局域网共享，AES-GCM 端到端加密。
- 本地优先与 Touch ID 保护。
- 剪贴板隐写（图片/零宽文本）。
- 链接净化（移除跟踪参数）。
- 数学表达式即时计算。
- 从其他剪贴板应用迁移历史。
- 自动更新（每日检查 + 设置页手动检查）。
- CLI Bridge，用于本地自动化与外部联动。

## 联动

- Deck x Orbit：径向应用切换器 + 文件中转（鼠标附近呼出、长按触发、拖拽退出、文件 AirDrop/删除）。https://github.com/yuzeguitarist/Orbit

## 安装

- 从 [Releases](https://github.com/yuzeguitarist/Deck/releases) 下载最新 `.dmg`。
- 将 `Deck.app` 拖入 Applications。
- 首次启动：按住 Control 点击 Deck -> 打开。
- 在 `系统设置 -> 隐私与安全性` 中授予 **辅助功能**（及可能的 **输入监控**）。

> 当前仅部分源码公开，尚不支持完整从源码构建。

## 系统要求

- macOS 14.0+
- Apple Silicon 或 Intel

## 快速开始

1. 启动 Deck。
2. 使用 `Cmd + P` 打开面板。
3. 方向键选择，回车粘贴。

### 默认快捷键

| 快捷键 | 功能 |
|--------|------|
| `Cmd + P` | 打开 Deck |
| `Enter` | 粘贴选中项 |
| `Shift + Enter` | 粘贴为纯文本 |
| `Cmd + 数字` | 快速粘贴 (1-9) |
| `Cmd + Q` | 切换队列模式 |
| `Space` | 切换预览 |
| `Esc` | 关闭 |

交互说明：
- 打开面板后直接输入即可搜索。
- 在历史记录列表使用鼠标滚轮可切换聚焦条目。

更多快捷键与 Vim 模式可在设置中查看。

## 截图

<p align="center">
  <img src="photos/DeckView2.png" alt="Deck 主界面" width="720">
</p>
<p align="center">
  <img src="photos/DeckSettings.jpg" alt="Deck 设置" width="720">
</p>

## 参与贡献

欢迎为开源部分贡献代码！请先阅读 [贡献指南](CONTRIBUTING.md)。

> 所有 PR 必须提交到 `dev` 分支。

## 许可证

本项目为 **部分开源**，采用 **GPL-3.0 + Commons Clause** 许可证 - 详见 [LICENSE](LICENSE)。

**简单来说：**
- 个人/非商业免费使用
- 可修改开源部分
- 衍生作品需使用相同许可证
- 商业用途需获得许可

商业授权请联系：yuzeguitar@gmail.com

## 支持

- [报告 Bug](https://github.com/yuzeguitarist/Deck/issues/new?template=bug_report.md)
- [功能建议](https://github.com/yuzeguitarist/Deck/issues/new?template=feature_request.md)
- [讨论区](https://github.com/yuzeguitarist/Deck/discussions)

---

<p align="center">
  Made by <a href="https://github.com/yuzeguitarist">Yuze Pan (潘禹泽)</a>
</p>
