# DeckClip

DeckClip 是 Deck 的命令行接口，用于从终端或自动化脚本安全地访问 Deck 剪贴板、面板与 AI 能力。

[功能](#功能) · [架构](#架构) · [安装与构建](#安装与构建) · [快速开始](#快速开始) · [命令](#命令) · [通信机制](#通信机制) · [仓库结构](#仓库结构) · [开发](#开发)

---

## 功能

- **剪贴板读取与写入** — 读取 Deck 最新剪贴板项，或将文本写入 Deck。
- **快速粘贴** — 按面板索引触发粘贴，支持纯文本模式和指定目标应用。
- **面板控制** — 切换 Deck 面板显示状态。
- **AI 命令** — 运行 AI 处理、搜索剪贴板历史、执行文本转换。
- **脚本友好输出** — 同时支持人类可读文本输出与 `--json` 结构化输出。
- **本地鉴权通信** — 通过 Unix Domain Socket、令牌握手和 HMAC 签名调用 Deck App。

## 架构

DeckClip 是一个本地客户端，不直接暴露 HTTP 服务，也不直接访问 Deck 数据库。它的职责是将命令行输入转换为协议请求，再通过本地 IPC 转发给 Deck App 的 CLI Bridge。

- **`deckclip`** — 命令行入口，负责参数解析、输出格式和子命令调度。
- **`deckclip-core`** — 客户端核心库，负责连接、鉴权、签名、超时和请求发送。
- **`deckclip-protocol`** — 协议定义，包含消息结构、命令常量和帧编解码实现。
- **Deck App CLI Bridge** — 运行在 Deck App 内部的本地服务端，负责实际执行请求。

## 安装与构建

### 前提条件

- macOS
- Rust stable 工具链
- 已安装并运行 Deck App
- 已在 Deck App 中启用 CLI Bridge

启用 CLI Bridge 后，DeckClip 默认会使用以下本地路径：

- Socket：`~/Library/Application Support/Deck/deckclip.sock`
- Token：`~/Library/Application Support/Deck/deckclip_token`

### 构建

在仓库根目录执行：

```bash
cargo build --release -p deckclip
```

构建完成后，二进制产物位于：

```text
target/release/deckclip
```

如需长期使用，可将该文件加入你自己的 `PATH`。

## 快速开始

```bash
cargo build --release -p deckclip
./target/release/deckclip health
echo "Hello, Deck" | ./target/release/deckclip write
./target/release/deckclip read
```

如果 `health` 返回 “Deck App 未运行或未启用 CLI Bridge”，请先确认 Deck App 已启动，并且 `deckclip.sock` 与 `deckclip_token` 已生成。

## 命令

所有命令均支持全局参数：

```bash
deckclip --json <command>
```

### 命令概览

| 命令 | 说明 | 示例 |
| --- | --- | --- |
| `health` | 检查 Deck App 与 CLI Bridge 连接状态 | `deckclip health` |
| `read` | 读取最新剪贴板项 | `deckclip read` |
| `write` | 写入文本到 Deck | `echo "text" \| deckclip write` |
| `paste` | 粘贴面板项 `1-9` | `deckclip paste 1 --plain` |
| `panel toggle` | 切换 Deck 面板显示状态 | `deckclip panel toggle` |
| `ai run` | 运行 AI 处理，可选保存结果 | `deckclip ai run "总结这段内容" --text "..." --save` |
| `ai search` | 搜索剪贴板历史 | `deckclip ai search "合同" --limit 5` |
| `ai transform` | 执行 AI 文本转换 | `deckclip ai transform "翻译成英文" --text "你好"` |
| `completion` | 生成 shell 补全脚本 | `deckclip completion zsh` |
| `version` | 输出版本信息 | `deckclip version` |

### 写入文本

```bash
deckclip write "需要写入 Deck 的文本"
echo "来自 stdin 的文本" | deckclip write
deckclip write "带标签的文本" --tag "工作"
```

### 读取与粘贴

```bash
deckclip read
deckclip paste 1
deckclip paste 2 --plain
deckclip paste 3 --target com.apple.TextEdit
```

### AI 命令

```bash
deckclip ai run "总结下面的内容" --text "这里是一段文本"
deckclip ai search "发票" --mode semantic --limit 10
deckclip ai transform "改写成正式语气" --text "帮我看下这个"
```

### JSON 输出

```bash
deckclip --json read
deckclip --json ai search "日报"
```

## 通信机制

DeckClip 使用本地 IPC，而不是 TCP 端口或 HTTP API。

### 连接方式

客户端通过 Unix Domain Socket 连接 Deck App：

```text
~/Library/Application Support/Deck/deckclip.sock
```

如果该文件不存在，客户端会直接返回连接失败或 “Deck App 未运行或未启用 CLI Bridge”。

### 鉴权流程

1. 客户端读取本地令牌文件 `deckclip_token`
2. 向 Deck App 发送认证消息
3. 服务端返回 `session_token` 和过期时间
4. 后续请求使用 `session_token` 进行 HMAC-SHA256 签名

签名材料格式如下：

```text
{timestamp}|{nonce}|{body}
```

### 请求结构

完成认证后，CLI 会将命令封装为协议请求：

```json
{
  "v": 1,
  "id": "uuid",
  "ts": 1712345678,
  "nonce": "random_hex",
  "sig": "hmac_signature",
  "cmd": "read",
  "args": {}
}
```

其中：

- **`v`** — 协议版本
- **`id`** — 请求 ID，用于和响应匹配
- **`ts`** — 时间戳
- **`nonce`** — 随机串，避免重放
- **`sig`** — HMAC-SHA256 签名
- **`cmd`** — 具体命令，如 `health`、`read`、`write`、`ai.run`
- **`args`** — 命令参数

### 帧格式

协议层不是裸 JSON，而是带包头的帧格式：

```text
[MAGIC 0xDE 0xCC][LENGTH 4B][JSON PAYLOAD]
```

这使客户端能够在同一条本地连接上安全地解析完整消息帧。

## 仓库结构

```text
.
├── deckclip/            # CLI 二进制入口
├── deckclip-core/       # 连接、鉴权、签名、传输
├── deckclip-protocol/   # 协议消息与编解码
├── Cargo.toml           # Rust workspace 配置
└── rust-toolchain.toml  # Rust 工具链约束
```

## 开发

常用开发命令：

```bash
cargo fmt --all
cargo clippy --workspace --all-targets
cargo test --workspace
cargo build --release -p deckclip
```

建议在开发时优先验证以下路径：

1. `health` 是否能成功连接 Deck App
2. `write` 与 `read` 是否能完成基本收发
3. `--json` 输出是否满足脚本集成需求
