use std::path::PathBuf;

use clap::{Parser, Subcommand, ValueEnum};
use clap_complete::Shell;

#[derive(Parser)]
#[command(
    name = "deckclip",
    about = "DeckClip — Deck 剪贴板管理工具的命令行接口",
    long_about = "DeckClip — Deck 剪贴板管理工具的命令行接口\n\n\
                  AI Agent 可直接调用上述命令操作 Deck 剪贴板。\n\
                  详细用法: deckclip <command> --help",
    version = env!("CARGO_PKG_VERSION"),
    propagate_version = true
)]
pub struct Cli {
    /// 所有输出使用 JSON 格式 (适用于编程调用)
    #[arg(long, global = true)]
    pub json: bool,

    #[command(subcommand)]
    pub command: Option<Commands>,
}

#[derive(Subcommand)]
pub enum Commands {
    /// 检查 Deck App 连接状态
    Health,

    /// 写入文本到 Deck 剪贴板
    Write(WriteArgs),

    /// 读取最新剪贴板项
    Read,

    /// 快速粘贴面板项 (1-9)
    Paste(PasteArgs),

    /// 控制面板显示
    Panel {
        /// 面板操作
        #[command(subcommand)]
        action: PanelAction,
    },

    /// AI 功能 (运行/搜索/转换)
    Ai(AiCommand),

    /// 交互式 AI 聊天
    Chat,

    /// 配置 AI 登录与模型提供商
    Login,

    /// Deck MCP bridge 与客户端配置
    Mcp(McpCommand),

    /// 生成 shell 补全脚本
    Completion {
        /// Shell 类型
        shell: Shell,
    },

    /// 显示版本信息
    Version,
}

// ─── Write ───

#[derive(clap::Args)]
pub struct WriteArgs {
    /// 要写入的文本 (省略则从 stdin 读取)
    pub text: Option<String>,

    /// 指定标签名
    #[arg(long)]
    pub tag: Option<String>,

    /// 指定标签 ID
    #[arg(long)]
    pub tag_id: Option<String>,

    /// 跳过智能规则
    #[arg(long)]
    pub raw: bool,
}

// ─── Paste ───

#[derive(clap::Args)]
pub struct PasteArgs {
    /// 面板项索引 (1-9)
    #[arg(value_parser = clap::value_parser!(u32).range(1..=9))]
    pub index: u32,

    /// 纯文本粘贴
    #[arg(long)]
    pub plain: bool,

    /// 指定目标 App (Bundle ID)
    #[arg(long)]
    pub target: Option<String>,
}

// ─── Panel ───

#[derive(Subcommand)]
pub enum PanelAction {
    /// 切换面板显示/隐藏
    Toggle,
}

// ─── AI ───

#[derive(clap::Args)]
pub struct AiCommand {
    #[command(subcommand)]
    pub action: AiAction,
}

#[derive(Subcommand)]
pub enum AiAction {
    /// 运行 AI 处理
    Run(AiRunArgs),

    /// AI 搜索剪贴板历史
    Search(AiSearchArgs),

    /// AI 文本转换
    Transform(AiTransformArgs),
}

// ─── MCP ───

#[derive(clap::Args)]
pub struct McpCommand {
    #[command(subcommand)]
    pub action: Option<McpAction>,
}

#[derive(Subcommand)]
pub enum McpAction {
    #[command(hide = true)]
    /// 以前台 stdio 方式运行 Deck MCP bridge
    Serve,

    /// 列出 MCP tools 与参数
    Tools,

    /// 检查 Deck MCP 运行与配置环境
    Doctor,

    /// 输出或写入 MCP 客户端配置片段
    Setup(McpSetupArgs),
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, ValueEnum)]
pub enum McpSetupClient {
    ClaudeDesktop,
    Cursor,
    Codex,
    Opencode,
    All,
}

#[derive(clap::Args)]
pub struct McpSetupArgs {
    /// 目标 MCP 客户端
    #[arg(long, value_enum, default_value = "all")]
    pub client: McpSetupClient,

    /// 直接写入默认配置文件
    #[arg(long)]
    pub write: bool,

    /// 覆盖默认配置文件路径
    #[arg(long)]
    pub path: Option<PathBuf>,

    /// 覆盖 deckclip 启动命令
    #[arg(long)]
    pub command: Option<String>,
}

#[derive(clap::Args)]
pub struct AiRunArgs {
    /// AI 指令 (prompt)
    pub prompt: String,

    /// 输入文本 (省略则从 stdin 读取)
    #[arg(long)]
    pub text: Option<String>,

    /// 自动保存结果到剪贴板
    #[arg(long)]
    pub save: bool,

    /// 保存到指定标签 ID
    #[arg(long)]
    pub tag_id: Option<String>,
}

#[derive(clap::Args)]
pub struct AiSearchArgs {
    /// 搜索关键词
    pub query: String,

    /// 搜索模式
    #[arg(long)]
    pub mode: Option<String>,

    /// 结果数量 (默认 10, 最大 50)
    #[arg(long, default_value = "10")]
    pub limit: u32,
}

#[derive(clap::Args)]
pub struct AiTransformArgs {
    /// AI 指令 (prompt)
    pub prompt: String,

    /// 待转换文本 (省略则从 stdin 读取)
    #[arg(long)]
    pub text: Option<String>,

    /// 使用指定插件 ID
    #[arg(long)]
    pub plugin: Option<String>,
}
