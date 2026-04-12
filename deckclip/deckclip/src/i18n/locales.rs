use std::collections::HashMap;
use std::sync::LazyLock;

type Map = HashMap<&'static str, &'static str>;
type Locales = HashMap<&'static str, Map>;

static LOCALES: LazyLock<Locales> = LazyLock::new(|| {
    let mut m = Locales::new();
    m.insert("zh-Hans", zh_hans());
    m.insert("en", en());
    m.insert("de", de());
    m.insert("fr", fr());
    m.insert("ja", ja());
    m.insert("ko", ko());
    m.insert("zh-Hant", zh_hant());
    m
});

pub fn get(locale: &str, key: &str) -> Option<String> {
    LOCALES
        .get(locale)
        .and_then(|m| m.get(key))
        .map(|s| s.to_string())
}

// ─── zh-Hans (source) ───

fn zh_hans() -> Map {
    let mut map = HashMap::from([
        // CLI top-level
        ("cli.about", "\u{1b}]8;;https://deckclip.app/zh-cn\u{1b}\\DeckClip@Deck\u{1b}]8;;\u{1b}\\"),
        ("cli.long_about", "\u{1b}]8;;https://deckclip.app/zh-cn\u{1b}\\DeckClip@Deck\u{1b}]8;;\u{1b}\\\n\nAI Agent 可直接调用命令操作 Deck 剪贴板。\n详细用法: deckclip <command> --help"),
        ("arg.json", "使用 JSON 格式输出"),

        // clap built-in overrides
        ("help.short", "显示帮助信息（使用 --help 查看更多）"),
        ("help.long", "显示帮助信息（使用 -h 查看摘要）"),
        ("version.short", "显示版本"),
        ("help.subcommand", "显示帮助信息或子命令的帮助"),

        // Subcommands
        ("cmd.health", "检查 Deck App 连接状态"),
        ("cmd.write", "写入文本到 Deck 剪贴板"),
        ("cmd.read", "读取最新剪贴板项"),
        ("cmd.paste", "快速粘贴面板项（1-9）"),
        ("cmd.panel", "控制面板显示"),
        ("cmd.chat", "交互式 AI 聊天"),
        ("cmd.login", "配置 AI 登录与模型提供商"),
        ("cmd.ai", "AI 功能（运行/搜索/转换）"),
        ("cmd.completion", "生成 shell 补全脚本"),
        ("cmd.version", "显示版本信息"),

        // Panel subcommands
        ("cmd.panel.toggle", "切换面板显示/隐藏"),
        ("arg.panel.action", "面板操作"),

        // AI subcommands
        ("cmd.ai.run", "运行 AI 处理"),
        ("cmd.ai.search", "AI 搜索剪贴板历史"),
        ("cmd.ai.transform", "AI 文本转换"),

        // Write args
        ("arg.write.text", "要写入的文本（省略则从 stdin 读取）"),
        ("arg.write.tag", "指定标签名"),
        ("arg.write.tag_id", "指定标签 ID"),
        ("arg.write.raw", "跳过智能规则"),

        // Paste args
        ("arg.paste.index", "面板项索引（1-9）"),
        ("arg.paste.plain", "纯文本粘贴"),
        ("arg.paste.target", "指定目标 App（Bundle ID）"),

        // AI args
        ("arg.ai.prompt", "AI 指令（prompt）"),
        ("arg.ai.text", "输入文本（省略则从 stdin 读取）"),
        ("arg.ai.save", "自动保存结果到剪贴板"),
        ("arg.ai.tag_id", "保存到指定标签 ID"),
        ("arg.ai.query", "搜索关键词"),
        ("arg.ai.mode", "搜索模式"),
        ("arg.ai.limit", "结果数量（默认 10，最大 50）"),
        ("arg.ai.transform_text", "待转换文本（省略则从 stdin 读取）"),
        ("arg.ai.plugin", "使用指定插件 ID"),
        ("arg.completion.shell", "Shell 类型"),

        // Command output
        ("label.error", "错误:"),
        ("health.ok", "ok — Deck App 连接正常"),
        ("write.ok", "已写入剪贴板"),
        ("paste.ok", "已粘贴第 {} 项"),
        ("panel.toggled", "面板已切换"),

        // Errors
        ("err.not_running", "Deck App 未运行或未启用 Deck CLI"),
        ("err.connection", "连接失败: {}"),
        ("err.auth", "认证失败: {}"),
        ("err.token_not_found", "Token 文件不存在: {}"),
        ("err.timeout", "请求超时"),
        ("err.protocol", "协议错误: {}"),
        ("err.server", "服务端错误 [{}]: {}"),
        ("err.io", "IO 错误: {}"),
        ("err.token_read", "无法读取 token 文件 {}: {}"),
        ("err.token_empty", "token 文件为空"),
        ("err.conn_closed", "连接已关闭"),
        ("err.auth_rejected", "认证被拒绝"),
        ("err.no_session", "无 session token"),
        ("err.id_mismatch", "响应 ID 不匹配: expected {}, got {}"),
        ("err.stdin_hint", "请提供文本参数，或通过管道传入（如: echo \"text\" | deckclip write）"),
        ("err.chat_json_unsupported", "deckclip chat 暂不支持 --json"),
        ("err.chat_requires_tty", "deckclip chat 需要交互式终端"),
        ("err.chat_raw_mode", "无法进入终端 raw mode"),
        ("err.chat_enter_screen", "无法进入终端全屏模式"),
        ("err.chat_terminal_init", "无法初始化终端 UI"),
        ("err.chat_event_read", "读取终端事件失败"),
        ("err.chat_busy", "Deck AI 当前正被另一个活动会话占用，请先关闭它"),
        ("err.chat_provider_unconfigured", "当前 AI Provider 尚未配置，无法进入 deckclip chat"),
        ("err.chat_unexpected_stream_response", "聊天流返回了意外响应"),
        ("err.chat_unknown_stream_error", "聊天流发生未知错误"),
        ("err.chat_unrecognized_event", "收到未识别事件: {}"),
        ("err.response_missing_data", "响应缺少 data 字段"),
        ("err.clipboard_invoke_failed", "无法调用 pbcopy"),
        ("err.clipboard_write_failed", "写入 pbcopy 失败"),
        ("err.clipboard_wait_failed", "等待 pbcopy 结束失败"),
        ("err.clipboard_copy_failed", "pbcopy 执行失败"),
    ]);
    map.extend(chat_zh_hans());
    map
}

// ─── English ───

fn en() -> Map {
    let mut map = HashMap::from([
        ("cli.about", "\u{1b}]8;;https://deckclip.app\u{1b}\\DeckClip@Deck\u{1b}]8;;\u{1b}\\"),
        ("cli.long_about", "\u{1b}]8;;https://deckclip.app\u{1b}\\DeckClip@Deck\u{1b}]8;;\u{1b}\\\n\nAI agents can call these commands to operate the Deck clipboard.\nUsage: deckclip <command> --help"),
        ("arg.json", "Output in JSON format"),

        ("help.short", "Print help (see more with '--help')"),
        ("help.long", "Print help (see a summary with '-h')"),
        ("version.short", "Print version"),
        ("help.subcommand", "Print this message or the help of the given subcommand(s)"),

        ("cmd.health", "Check Deck App connection status"),
        ("cmd.write", "Write text to Deck clipboard"),
        ("cmd.read", "Read latest clipboard entry"),
        ("cmd.paste", "Quick-paste a panel item (1-9)"),
        ("cmd.panel", "Control the panel"),
        ("cmd.chat", "Interactive AI chat"),
        ("cmd.login", "Configure AI login and model providers"),
        ("cmd.ai", "AI features (run/search/transform)"),
        ("cmd.completion", "Generate shell completion script"),
        ("cmd.version", "Show version info"),

        ("cmd.panel.toggle", "Toggle panel visibility"),
        ("arg.panel.action", "Panel action"),

        ("cmd.ai.run", "Run AI processing"),
        ("cmd.ai.search", "AI search clipboard history"),
        ("cmd.ai.transform", "AI text transformation"),

        ("arg.write.text", "Text to write (reads from stdin if omitted)"),
        ("arg.write.tag", "Tag name"),
        ("arg.write.tag_id", "Tag ID"),
        ("arg.write.raw", "Skip smart rules"),

        ("arg.paste.index", "Panel item index (1-9)"),
        ("arg.paste.plain", "Paste as plain text"),
        ("arg.paste.target", "Target app (Bundle ID)"),

        ("arg.ai.prompt", "AI prompt"),
        ("arg.ai.text", "Input text (reads from stdin if omitted)"),
        ("arg.ai.save", "Auto-save result to clipboard"),
        ("arg.ai.tag_id", "Save to tag ID"),
        ("arg.ai.query", "Search query"),
        ("arg.ai.mode", "Search mode"),
        ("arg.ai.limit", "Result count (default 10, max 50)"),
        ("arg.ai.transform_text", "Text to transform (reads from stdin if omitted)"),
        ("arg.ai.plugin", "Plugin ID"),
        ("arg.completion.shell", "Shell type"),

        ("label.error", "error:"),
        ("health.ok", "ok — Deck App connected"),
        ("write.ok", "Written to clipboard"),
        ("paste.ok", "Pasted item {}"),
        ("panel.toggled", "Panel toggled"),

        ("err.not_running", "Deck App is not running or Deck CLI is disabled"),
        ("err.connection", "Connection failed: {}"),
        ("err.auth", "Authentication failed: {}"),
        ("err.token_not_found", "Token file not found: {}"),
        ("err.timeout", "Request timed out"),
        ("err.protocol", "Protocol error: {}"),
        ("err.server", "Server error [{}]: {}"),
        ("err.io", "IO error: {}"),
        ("err.token_read", "Cannot read token file {}: {}"),
        ("err.token_empty", "Token file is empty"),
        ("err.conn_closed", "Connection closed"),
        ("err.auth_rejected", "Authentication rejected"),
        ("err.no_session", "No session token"),
        ("err.id_mismatch", "Response ID mismatch: expected {}, got {}"),
        ("err.stdin_hint", "Provide text as an argument or pipe it in (e.g.: echo \"text\" | deckclip write)"),
        ("err.chat_json_unsupported", "deckclip chat does not support --json yet"),
        ("err.chat_requires_tty", "deckclip chat requires an interactive terminal"),
        ("err.chat_raw_mode", "Failed to enable terminal raw mode"),
        ("err.chat_enter_screen", "Failed to enter the terminal alternate screen"),
        ("err.chat_terminal_init", "Failed to initialize terminal UI"),
        ("err.chat_event_read", "Failed to read terminal event"),
        ("err.chat_busy", "Deck AI is busy with another active session; close it first"),
        ("err.chat_provider_unconfigured", "No AI provider is configured yet, so deckclip chat cannot start"),
        ("err.chat_unexpected_stream_response", "Chat stream returned an unexpected response"),
        ("err.chat_unknown_stream_error", "An unknown error occurred in the chat stream"),
        ("err.chat_unrecognized_event", "Received an unrecognized event: {}"),
        ("err.response_missing_data", "Response is missing the data field"),
        ("err.clipboard_invoke_failed", "Failed to invoke pbcopy"),
        ("err.clipboard_write_failed", "Failed to write to pbcopy"),
        ("err.clipboard_wait_failed", "Failed while waiting for pbcopy to finish"),
        ("err.clipboard_copy_failed", "pbcopy failed"),
    ]);
    map.extend(chat_en());
    map
}

// ─── German ───

fn de() -> Map {
    let mut map = HashMap::from([
        ("cli.about", "\u{1b}]8;;https://deckclip.app\u{1b}\\DeckClip@Deck\u{1b}]8;;\u{1b}\\"),
        ("cli.long_about", "\u{1b}]8;;https://deckclip.app\u{1b}\\DeckClip@Deck\u{1b}]8;;\u{1b}\\\n\nKI-Agenten können diese Befehle direkt aufrufen.\nVerwendung: deckclip <command> --help"),
        ("arg.json", "Ausgabe im JSON-Format"),

        ("help.short", "Hilfe anzeigen (mehr mit '--help')"),
        ("help.long", "Hilfe anzeigen (Zusammenfassung mit '-h')"),
        ("version.short", "Version anzeigen"),
        ("help.subcommand", "Diese Nachricht oder die Hilfe eines Unterbefehls anzeigen"),

        ("cmd.health", "Deck App Verbindungsstatus prüfen"),
        ("cmd.write", "Text in die Deck-Zwischenablage schreiben"),
        ("cmd.read", "Letzten Eintrag lesen"),
        ("cmd.paste", "Panel-Eintrag schnell einfügen (1-9)"),
        ("cmd.panel", "Panel steuern"),
        ("cmd.chat", "Interaktiver KI-Chat"),
        ("cmd.login", "KI-Anmeldung und Modellanbieter konfigurieren"),
        ("cmd.ai", "KI-Funktionen (Ausführen/Suchen/Umwandeln)"),
        ("cmd.completion", "Shell-Vervollständigungsskript generieren"),
        ("cmd.version", "Versionsinformation anzeigen"),

        ("cmd.panel.toggle", "Panel ein-/ausblenden"),
        ("arg.panel.action", "Panel-Aktion"),

        ("cmd.ai.run", "KI-Verarbeitung ausführen"),
        ("cmd.ai.search", "KI-Suche im Verlauf"),
        ("cmd.ai.transform", "KI-Textumwandlung"),

        ("arg.write.text", "Zu schreibender Text (liest von stdin wenn weggelassen)"),
        ("arg.write.tag", "Tag-Name"),
        ("arg.write.tag_id", "Tag-ID"),
        ("arg.write.raw", "Intelligente Regeln überspringen"),

        ("arg.paste.index", "Panel-Eintrag-Index (1-9)"),
        ("arg.paste.plain", "Als reinen Text einfügen"),
        ("arg.paste.target", "Ziel-App (Bundle ID)"),

        ("arg.ai.prompt", "KI-Anweisung (Prompt)"),
        ("arg.ai.text", "Eingabetext (liest von stdin wenn weggelassen)"),
        ("arg.ai.save", "Ergebnis automatisch speichern"),
        ("arg.ai.tag_id", "In Tag-ID speichern"),
        ("arg.ai.query", "Suchbegriff"),
        ("arg.ai.mode", "Suchmodus"),
        ("arg.ai.limit", "Ergebnisanzahl (Standard 10, max 50)"),
        ("arg.ai.transform_text", "Umzuwandelnder Text (liest von stdin wenn weggelassen)"),
        ("arg.ai.plugin", "Plugin-ID"),
        ("arg.completion.shell", "Shell-Typ"),

        ("label.error", "Fehler:"),
        ("health.ok", "ok — Deck App verbunden"),
        ("write.ok", "In Zwischenablage geschrieben"),
        ("paste.ok", "Eintrag {} eingefügt"),
        ("panel.toggled", "Panel umgeschaltet"),

        ("err.not_running", "Deck App läuft nicht oder Deck CLI ist deaktiviert"),
        ("err.connection", "Verbindung fehlgeschlagen: {}"),
        ("err.auth", "Authentifizierung fehlgeschlagen: {}"),
        ("err.token_not_found", "Token-Datei nicht gefunden: {}"),
        ("err.timeout", "Zeitüberschreitung"),
        ("err.protocol", "Protokollfehler: {}"),
        ("err.server", "Serverfehler [{}]: {}"),
        ("err.io", "IO-Fehler: {}"),
        ("err.token_read", "Token-Datei {} kann nicht gelesen werden: {}"),
        ("err.token_empty", "Token-Datei ist leer"),
        ("err.conn_closed", "Verbindung geschlossen"),
        ("err.auth_rejected", "Authentifizierung abgelehnt"),
        ("err.no_session", "Kein Session-Token"),
        ("err.id_mismatch", "Antwort-ID stimmt nicht überein: erwartet {}, erhalten {}"),
        ("err.stdin_hint", "Bitte Text als Argument angeben oder per Pipe übergeben (z.B.: echo \"text\" | deckclip write)"),
        ("err.chat_json_unsupported", "deckclip chat unterstützt --json derzeit nicht"),
        ("err.chat_requires_tty", "deckclip chat benötigt ein interaktives Terminal"),
        ("err.chat_raw_mode", "Terminal-Raw-Mode konnte nicht aktiviert werden"),
        ("err.chat_enter_screen", "Der alternative Terminalbildschirm konnte nicht geöffnet werden"),
        ("err.chat_terminal_init", "Terminal-UI konnte nicht initialisiert werden"),
        ("err.chat_event_read", "Terminal-Ereignis konnte nicht gelesen werden"),
        ("err.chat_busy", "Deck AI wird derzeit von einer anderen aktiven Sitzung verwendet; bitte schließen Sie diese zuerst"),
        ("err.chat_provider_unconfigured", "Es ist noch kein KI-Anbieter konfiguriert; deckclip chat kann nicht gestartet werden"),
        ("err.chat_unexpected_stream_response", "Der Chat-Stream hat eine unerwartete Antwort zurückgegeben"),
        ("err.chat_unknown_stream_error", "Im Chat-Stream ist ein unbekannter Fehler aufgetreten"),
        ("err.chat_unrecognized_event", "Unbekanntes Ereignis empfangen: {}"),
        ("err.response_missing_data", "In der Antwort fehlt das Feld data"),
        ("err.clipboard_invoke_failed", "pbcopy konnte nicht aufgerufen werden"),
        ("err.clipboard_write_failed", "Schreiben an pbcopy fehlgeschlagen"),
        ("err.clipboard_wait_failed", "Warten auf pbcopy ist fehlgeschlagen"),
        ("err.clipboard_copy_failed", "pbcopy ist fehlgeschlagen"),
    ]);
    map.extend(chat_de());
    map
}

// ─── French ───

fn fr() -> Map {
    let mut map = HashMap::from([
        ("cli.about", "\u{1b}]8;;https://deckclip.app\u{1b}\\DeckClip@Deck\u{1b}]8;;\u{1b}\\"),
        ("cli.long_about", "\u{1b}]8;;https://deckclip.app\u{1b}\\DeckClip@Deck\u{1b}]8;;\u{1b}\\\n\nLes agents IA peuvent appeler ces commandes directement.\nUtilisation : deckclip <command> --help"),
        ("arg.json", "Sortie au format JSON"),

        ("help.short", "Afficher l'aide (plus avec '--help')"),
        ("help.long", "Afficher l'aide (résumé avec '-h')"),
        ("version.short", "Afficher la version"),
        ("help.subcommand", "Afficher ce message ou l'aide d'une sous-commande"),

        ("cmd.health", "Vérifier la connexion à Deck App"),
        ("cmd.write", "Écrire du texte dans le presse-papiers Deck"),
        ("cmd.read", "Lire la dernière entrée"),
        ("cmd.paste", "Collage rapide d'un élément du panneau (1-9)"),
        ("cmd.panel", "Contrôler le panneau"),
        ("cmd.chat", "Chat IA interactif"),
        ("cmd.login", "Configurer la connexion IA et les fournisseurs de modèles"),
        ("cmd.ai", "Fonctions IA (exécuter/rechercher/transformer)"),
        ("cmd.completion", "Générer le script de complétion shell"),
        ("cmd.version", "Afficher la version"),

        ("cmd.panel.toggle", "Afficher/masquer le panneau"),
        ("arg.panel.action", "Action du panneau"),

        ("cmd.ai.run", "Exécuter le traitement IA"),
        ("cmd.ai.search", "Recherche IA dans l'historique"),
        ("cmd.ai.transform", "Transformation de texte par IA"),

        ("arg.write.text", "Texte à écrire (lit depuis stdin si omis)"),
        ("arg.write.tag", "Nom du tag"),
        ("arg.write.tag_id", "ID du tag"),
        ("arg.write.raw", "Ignorer les règles intelligentes"),

        ("arg.paste.index", "Index de l'élément du panneau (1-9)"),
        ("arg.paste.plain", "Coller en texte brut"),
        ("arg.paste.target", "Application cible (Bundle ID)"),

        ("arg.ai.prompt", "Instruction IA (prompt)"),
        ("arg.ai.text", "Texte d'entrée (lit depuis stdin si omis)"),
        ("arg.ai.save", "Sauvegarder automatiquement le résultat"),
        ("arg.ai.tag_id", "Sauvegarder dans le tag ID"),
        ("arg.ai.query", "Mot-clé de recherche"),
        ("arg.ai.mode", "Mode de recherche"),
        ("arg.ai.limit", "Nombre de résultats (défaut 10, max 50)"),
        ("arg.ai.transform_text", "Texte à transformer (lit depuis stdin si omis)"),
        ("arg.ai.plugin", "ID du plugin"),
        ("arg.completion.shell", "Type de shell"),

        ("label.error", "erreur :"),
        ("health.ok", "ok — Deck App connecté"),
        ("write.ok", "Écrit dans le presse-papiers"),
        ("paste.ok", "Élément {} collé"),
        ("panel.toggled", "Panneau basculé"),

        ("err.not_running", "Deck App n'est pas en cours d'exécution ou Deck CLI est désactivé"),
        ("err.connection", "Échec de connexion : {}"),
        ("err.auth", "Échec d'authentification : {}"),
        ("err.token_not_found", "Fichier token introuvable : {}"),
        ("err.timeout", "Délai d'attente dépassé"),
        ("err.protocol", "Erreur de protocole : {}"),
        ("err.server", "Erreur serveur [{}] : {}"),
        ("err.io", "Erreur IO : {}"),
        ("err.token_read", "Impossible de lire le fichier token {} : {}"),
        ("err.token_empty", "Le fichier token est vide"),
        ("err.conn_closed", "Connexion fermée"),
        ("err.auth_rejected", "Authentification rejetée"),
        ("err.no_session", "Pas de token de session"),
        ("err.id_mismatch", "ID de réponse non concordant : attendu {}, reçu {}"),
        ("err.stdin_hint", "Fournissez le texte en argument ou par pipe (ex : echo \"text\" | deckclip write)"),
        ("err.chat_json_unsupported", "deckclip chat ne prend pas encore en charge --json"),
        ("err.chat_requires_tty", "deckclip chat nécessite un terminal interactif"),
        ("err.chat_raw_mode", "Impossible d'activer le mode brut du terminal"),
        ("err.chat_enter_screen", "Impossible d'ouvrir l'écran alternatif du terminal"),
        ("err.chat_terminal_init", "Impossible d'initialiser l'interface du terminal"),
        ("err.chat_event_read", "Impossible de lire un événement du terminal"),
        ("err.chat_busy", "Deck AI est déjà utilisé par une autre session active ; fermez-la d'abord"),
        ("err.chat_provider_unconfigured", "Aucun fournisseur IA n'est encore configuré ; deckclip chat ne peut pas démarrer"),
        ("err.chat_unexpected_stream_response", "Le flux de chat a renvoyé une réponse inattendue"),
        ("err.chat_unknown_stream_error", "Une erreur inconnue est survenue dans le flux de chat"),
        ("err.chat_unrecognized_event", "Événement non reconnu reçu : {}"),
        ("err.response_missing_data", "La réponse ne contient pas le champ data"),
        ("err.clipboard_invoke_failed", "Impossible d'invoquer pbcopy"),
        ("err.clipboard_write_failed", "Impossible d'écrire dans pbcopy"),
        ("err.clipboard_wait_failed", "Échec lors de l'attente de la fin de pbcopy"),
        ("err.clipboard_copy_failed", "Échec de pbcopy"),
    ]);
    map.extend(chat_fr());
    map
}

// ─── Japanese ───

fn ja() -> Map {
    let mut map = HashMap::from([
        ("cli.about", "\u{1b}]8;;https://deckclip.app\u{1b}\\DeckClip@Deck\u{1b}]8;;\u{1b}\\"),
        ("cli.long_about", "\u{1b}]8;;https://deckclip.app\u{1b}\\DeckClip@Deck\u{1b}]8;;\u{1b}\\\n\nAI エージェントはこれらのコマンドを直接呼び出すことができます。\n使い方: deckclip <command> --help"),
        ("arg.json", "JSON 形式で出力"),

        ("help.short", "ヘルプを表示（詳細は '--help'）"),
        ("help.long", "ヘルプを表示（概要は '-h'）"),
        ("version.short", "バージョン表示"),
        ("help.subcommand", "このメッセージまたはサブコマンドのヘルプを表示"),

        ("cmd.health", "Deck App の接続状態を確認"),
        ("cmd.write", "Deck クリップボードにテキストを書き込む"),
        ("cmd.read", "最新のクリップボード項目を読み取る"),
        ("cmd.paste", "パネル項目をクイックペースト（1-9）"),
        ("cmd.panel", "パネルの表示を制御"),
        ("cmd.chat", "対話型 AI チャット"),
        ("cmd.login", "AI ログインとモデルプロバイダーを設定"),
        ("cmd.ai", "AI 機能（実行/検索/変換）"),
        ("cmd.completion", "シェル補完スクリプトを生成"),
        ("cmd.version", "バージョン情報を表示"),

        ("cmd.panel.toggle", "パネルの表示/非表示を切り替え"),
        ("arg.panel.action", "パネル操作"),

        ("cmd.ai.run", "AI 処理を実行"),
        ("cmd.ai.search", "AI でクリップボード履歴を検索"),
        ("cmd.ai.transform", "AI テキスト変換"),

        ("arg.write.text", "書き込むテキスト（省略時は stdin から読み取り）"),
        ("arg.write.tag", "タグ名を指定"),
        ("arg.write.tag_id", "タグ ID を指定"),
        ("arg.write.raw", "スマートルールをスキップ"),

        ("arg.paste.index", "パネル項目のインデックス（1-9）"),
        ("arg.paste.plain", "プレーンテキストで貼り付け"),
        ("arg.paste.target", "ターゲットアプリ（Bundle ID）"),

        ("arg.ai.prompt", "AI 指示（プロンプト）"),
        ("arg.ai.text", "入力テキスト（省略時は stdin から読み取り）"),
        ("arg.ai.save", "結果を自動でクリップボードに保存"),
        ("arg.ai.tag_id", "指定タグ ID に保存"),
        ("arg.ai.query", "検索キーワード"),
        ("arg.ai.mode", "検索モード"),
        ("arg.ai.limit", "結果数（デフォルト 10、最大 50）"),
        ("arg.ai.transform_text", "変換するテキスト（省略時は stdin から読み取り）"),
        ("arg.ai.plugin", "プラグイン ID を指定"),
        ("arg.completion.shell", "シェルの種類"),

        ("label.error", "エラー:"),
        ("health.ok", "ok — Deck App 接続正常"),
        ("write.ok", "クリップボードに書き込みました"),
        ("paste.ok", "項目 {} を貼り付けました"),
        ("panel.toggled", "パネルを切り替えました"),

        ("err.not_running", "Deck App が起動していないか、Deck CLI が無効です"),
        ("err.connection", "接続に失敗: {}"),
        ("err.auth", "認証に失敗: {}"),
        ("err.token_not_found", "トークンファイルが見つかりません: {}"),
        ("err.timeout", "リクエストがタイムアウトしました"),
        ("err.protocol", "プロトコルエラー: {}"),
        ("err.server", "サーバーエラー [{}]: {}"),
        ("err.io", "IO エラー: {}"),
        ("err.token_read", "トークンファイル {} を読み取れません: {}"),
        ("err.token_empty", "トークンファイルが空です"),
        ("err.conn_closed", "接続が閉じられました"),
        ("err.auth_rejected", "認証が拒否されました"),
        ("err.no_session", "セッショントークンがありません"),
        ("err.id_mismatch", "レスポンス ID 不一致: 期待 {}、取得 {}"),
        ("err.stdin_hint", "テキストを引数で指定するか、パイプで入力してください（例: echo \"text\" | deckclip write）"),
        ("err.chat_json_unsupported", "deckclip chat はまだ --json をサポートしていません"),
        ("err.chat_requires_tty", "deckclip chat には対話型ターミナルが必要です"),
        ("err.chat_raw_mode", "ターミナルの raw mode を有効にできませんでした"),
        ("err.chat_enter_screen", "ターミナルの代替画面に入れませんでした"),
        ("err.chat_terminal_init", "ターミナル UI を初期化できませんでした"),
        ("err.chat_event_read", "ターミナルイベントの読み取りに失敗しました"),
        ("err.chat_busy", "Deck AI は別のアクティブなセッションで使用中です。先にそのセッションを閉じてください"),
        ("err.chat_provider_unconfigured", "AI プロバイダーがまだ設定されていないため、deckclip chat を開始できません"),
        ("err.chat_unexpected_stream_response", "チャットストリームから予期しない応答が返されました"),
        ("err.chat_unknown_stream_error", "チャットストリームで不明なエラーが発生しました"),
        ("err.chat_unrecognized_event", "認識できないイベントを受信しました: {}"),
        ("err.response_missing_data", "レスポンスに data フィールドがありません"),
        ("err.clipboard_invoke_failed", "pbcopy を呼び出せませんでした"),
        ("err.clipboard_write_failed", "pbcopy への書き込みに失敗しました"),
        ("err.clipboard_wait_failed", "pbcopy の終了待機に失敗しました"),
        ("err.clipboard_copy_failed", "pbcopy の実行に失敗しました"),
    ]);
    map.extend(chat_ja());
    map
}

// ─── Korean ───

fn ko() -> Map {
    let mut map = HashMap::from([
        ("cli.about", "\u{1b}]8;;https://deckclip.app\u{1b}\\DeckClip@Deck\u{1b}]8;;\u{1b}\\"),
        ("cli.long_about", "\u{1b}]8;;https://deckclip.app\u{1b}\\DeckClip@Deck\u{1b}]8;;\u{1b}\\\n\nAI 에이전트가 이 명령어를 직접 호출할 수 있습니다.\n사용법: deckclip <command> --help"),
        ("arg.json", "JSON 형식으로 출력"),

        ("help.short", "도움말 표시 ('--help'으로 자세히)"),
        ("help.long", "도움말 표시 ('-h'로 요약)"),
        ("version.short", "버전 표시"),
        ("help.subcommand", "이 메시지 또는 하위 명령의 도움말 표시"),

        ("cmd.health", "Deck App 연결 상태 확인"),
        ("cmd.write", "Deck 클립보드에 텍스트 쓰기"),
        ("cmd.read", "최신 클립보드 항목 읽기"),
        ("cmd.paste", "패널 항목 빠른 붙여넣기 (1-9)"),
        ("cmd.panel", "패널 표시 제어"),
        ("cmd.chat", "대화형 AI 채팅"),
        ("cmd.login", "AI 로그인 및 모델 제공자 구성"),
        ("cmd.ai", "AI 기능 (실행/검색/변환)"),
        ("cmd.completion", "셸 자동완성 스크립트 생성"),
        ("cmd.version", "버전 정보 표시"),

        ("cmd.panel.toggle", "패널 표시/숨기기 전환"),
        ("arg.panel.action", "패널 동작"),

        ("cmd.ai.run", "AI 처리 실행"),
        ("cmd.ai.search", "AI 클립보드 기록 검색"),
        ("cmd.ai.transform", "AI 텍스트 변환"),

        ("arg.write.text", "쓸 텍스트 (생략 시 stdin에서 읽기)"),
        ("arg.write.tag", "태그 이름"),
        ("arg.write.tag_id", "태그 ID"),
        ("arg.write.raw", "스마트 규칙 건너뛰기"),

        ("arg.paste.index", "패널 항목 인덱스 (1-9)"),
        ("arg.paste.plain", "일반 텍스트로 붙여넣기"),
        ("arg.paste.target", "대상 앱 (Bundle ID)"),

        ("arg.ai.prompt", "AI 지시 (프롬프트)"),
        ("arg.ai.text", "입력 텍스트 (생략 시 stdin에서 읽기)"),
        ("arg.ai.save", "결과를 클립보드에 자동 저장"),
        ("arg.ai.tag_id", "태그 ID에 저장"),
        ("arg.ai.query", "검색 키워드"),
        ("arg.ai.mode", "검색 모드"),
        ("arg.ai.limit", "결과 수 (기본 10, 최대 50)"),
        ("arg.ai.transform_text", "변환할 텍스트 (생략 시 stdin에서 읽기)"),
        ("arg.ai.plugin", "플러그인 ID"),
        ("arg.completion.shell", "셸 유형"),

        ("label.error", "오류:"),
        ("health.ok", "ok — Deck App 연결됨"),
        ("write.ok", "클립보드에 기록됨"),
        ("paste.ok", "항목 {} 붙여넣기 완료"),
        ("panel.toggled", "패널 전환됨"),

        ("err.not_running", "Deck App이 실행 중이 아니거나 Deck CLI가 비활성화되어 있습니다"),
        ("err.connection", "연결 실패: {}"),
        ("err.auth", "인증 실패: {}"),
        ("err.token_not_found", "토큰 파일을 찾을 수 없습니다: {}"),
        ("err.timeout", "요청 시간 초과"),
        ("err.protocol", "프로토콜 오류: {}"),
        ("err.server", "서버 오류 [{}]: {}"),
        ("err.io", "IO 오류: {}"),
        ("err.token_read", "토큰 파일 {}을 읽을 수 없습니다: {}"),
        ("err.token_empty", "토큰 파일이 비어 있습니다"),
        ("err.conn_closed", "연결이 닫혔습니다"),
        ("err.auth_rejected", "인증이 거부되었습니다"),
        ("err.no_session", "세션 토큰이 없습니다"),
        ("err.id_mismatch", "응답 ID 불일치: 예상 {}, 수신 {}"),
        ("err.stdin_hint", "텍스트를 인수로 제공하거나 파이프로 입력하세요 (예: echo \"text\" | deckclip write)"),
        ("err.chat_json_unsupported", "deckclip chat은 아직 --json을 지원하지 않습니다"),
        ("err.chat_requires_tty", "deckclip chat에는 대화형 터미널이 필요합니다"),
        ("err.chat_raw_mode", "터미널 raw mode를 활성화하지 못했습니다"),
        ("err.chat_enter_screen", "터미널 대체 화면으로 전환하지 못했습니다"),
        ("err.chat_terminal_init", "터미널 UI를 초기화하지 못했습니다"),
        ("err.chat_event_read", "터미널 이벤트를 읽지 못했습니다"),
        ("err.chat_busy", "Deck AI가 다른 활성 세션에서 사용 중입니다. 먼저 해당 세션을 닫아 주세요"),
        ("err.chat_provider_unconfigured", "아직 AI 제공자가 구성되지 않아 deckclip chat을 시작할 수 없습니다"),
        ("err.chat_unexpected_stream_response", "채팅 스트림이 예상하지 못한 응답을 반환했습니다"),
        ("err.chat_unknown_stream_error", "채팅 스트림에서 알 수 없는 오류가 발생했습니다"),
        ("err.chat_unrecognized_event", "인식할 수 없는 이벤트를 받았습니다: {}"),
        ("err.response_missing_data", "응답에 data 필드가 없습니다"),
        ("err.clipboard_invoke_failed", "pbcopy를 호출하지 못했습니다"),
        ("err.clipboard_write_failed", "pbcopy에 쓰지 못했습니다"),
        ("err.clipboard_wait_failed", "pbcopy 종료를 기다리는 중 실패했습니다"),
        ("err.clipboard_copy_failed", "pbcopy 실행에 실패했습니다"),
    ]);
    map.extend(chat_ko());
    map
}

// ─── zh-Hant ───

fn zh_hant() -> Map {
    let mut map = HashMap::from([
        ("cli.about", "\u{1b}]8;;https://deckclip.app/zh-cn\u{1b}\\DeckClip@Deck\u{1b}]8;;\u{1b}\\"),
        ("cli.long_about", "\u{1b}]8;;https://deckclip.app/zh-cn\u{1b}\\DeckClip@Deck\u{1b}]8;;\u{1b}\\\n\nAI Agent 可直接呼叫指令操作 Deck 剪貼簿。\n詳細用法: deckclip <command> --help"),
        ("arg.json", "使用 JSON 格式輸出"),

        ("help.short", "顯示說明（使用 '--help' 檢視更多）"),
        ("help.long", "顯示說明（使用 '-h' 檢視摘要）"),
        ("version.short", "顯示版本"),
        ("help.subcommand", "顯示此訊息或子指令的說明"),

        ("cmd.health", "檢查 Deck App 連線狀態"),
        ("cmd.write", "寫入文字到 Deck 剪貼簿"),
        ("cmd.read", "讀取最新剪貼簿項目"),
        ("cmd.paste", "快速貼上面板項目（1-9）"),
        ("cmd.panel", "控制面板顯示"),
        ("cmd.chat", "互動式 AI 聊天"),
        ("cmd.login", "設定 AI 登入與模型提供商"),
        ("cmd.ai", "AI 功能（執行/搜尋/轉換）"),
        ("cmd.completion", "產生 shell 自動完成腳本"),
        ("cmd.version", "顯示版本資訊"),

        ("cmd.panel.toggle", "切換面板顯示/隱藏"),
        ("arg.panel.action", "面板操作"),

        ("cmd.ai.run", "執行 AI 處理"),
        ("cmd.ai.search", "AI 搜尋剪貼簿歷史"),
        ("cmd.ai.transform", "AI 文字轉換"),

        ("arg.write.text", "要寫入的文字（省略則從 stdin 讀取）"),
        ("arg.write.tag", "指定標籤名稱"),
        ("arg.write.tag_id", "指定標籤 ID"),
        ("arg.write.raw", "跳過智慧規則"),

        ("arg.paste.index", "面板項目索引（1-9）"),
        ("arg.paste.plain", "純文字貼上"),
        ("arg.paste.target", "指定目標 App（Bundle ID）"),

        ("arg.ai.prompt", "AI 指令（prompt）"),
        ("arg.ai.text", "輸入文字（省略則從 stdin 讀取）"),
        ("arg.ai.save", "自動儲存結果到剪貼簿"),
        ("arg.ai.tag_id", "儲存到指定標籤 ID"),
        ("arg.ai.query", "搜尋關鍵字"),
        ("arg.ai.mode", "搜尋模式"),
        ("arg.ai.limit", "結果數量（預設 10，最大 50）"),
        ("arg.ai.transform_text", "待轉換文字（省略則從 stdin 讀取）"),
        ("arg.ai.plugin", "使用指定外掛 ID"),
        ("arg.completion.shell", "Shell 類型"),

        ("label.error", "錯誤:"),
        ("health.ok", "ok — Deck App 連線正常"),
        ("write.ok", "已寫入剪貼簿"),
        ("paste.ok", "已貼上第 {} 項"),
        ("panel.toggled", "面板已切換"),

        ("err.not_running", "Deck App 未執行或未啟用 Deck CLI"),
        ("err.connection", "連線失敗: {}"),
        ("err.auth", "認證失敗: {}"),
        ("err.token_not_found", "Token 檔案不存在: {}"),
        ("err.timeout", "請求逾時"),
        ("err.protocol", "協定錯誤: {}"),
        ("err.server", "伺服器錯誤 [{}]: {}"),
        ("err.io", "IO 錯誤: {}"),
        ("err.token_read", "無法讀取 token 檔案 {}: {}"),
        ("err.token_empty", "token 檔案為空"),
        ("err.conn_closed", "連線已關閉"),
        ("err.auth_rejected", "認證被拒絕"),
        ("err.no_session", "無 session token"),
        ("err.id_mismatch", "回應 ID 不符: 預期 {}，收到 {}"),
        ("err.stdin_hint", "請提供文字參數，或透過管道傳入（如: echo \"text\" | deckclip write）"),
        ("err.chat_json_unsupported", "deckclip chat 暫不支援 --json"),
        ("err.chat_requires_tty", "deckclip chat 需要互動式終端機"),
        ("err.chat_raw_mode", "無法進入終端 raw mode"),
        ("err.chat_enter_screen", "無法進入終端全螢幕模式"),
        ("err.chat_terminal_init", "無法初始化終端 UI"),
        ("err.chat_event_read", "讀取終端事件失敗"),
        ("err.chat_busy", "Deck AI 目前正被另一個活動會話占用，請先關閉它"),
        ("err.chat_provider_unconfigured", "目前尚未設定 AI Provider，無法進入 deckclip chat"),
        ("err.chat_unexpected_stream_response", "聊天串流返回了意外回應"),
        ("err.chat_unknown_stream_error", "聊天串流發生未知錯誤"),
        ("err.chat_unrecognized_event", "收到未識別事件: {}"),
        ("err.response_missing_data", "回應缺少 data 欄位"),
        ("err.clipboard_invoke_failed", "無法呼叫 pbcopy"),
        ("err.clipboard_write_failed", "寫入 pbcopy 失敗"),
        ("err.clipboard_wait_failed", "等待 pbcopy 結束失敗"),
        ("err.clipboard_copy_failed", "pbcopy 執行失敗"),
    ]);
    map.extend(chat_zh_hant());
    map
}

fn chat_zh_hans() -> Map {
    HashMap::from([
        ("chat.slash.cost.description", "查看当前上下文占用"),
        ("chat.slash.compact.description", "压缩当前会话上下文"),
        ("chat.slash.copy.description", "复制最后一条 AI 回复"),
        ("chat.slash.resume.description", "打开历史会话列表"),
        ("chat.slash.clear.description", "新建一个空白会话"),
        ("chat.slash.help.description", "显示可用命令说明"),
        ("chat.quit_hint", "再按一次 Ctrl+C 即可关闭"),
        ("chat.conversation.new", "新对话"),
        ("chat.model.not_started", "未开始"),
        ("chat.footer.ready", "Deck AI 已就绪，输入内容直接发送，输入 /help 查看命令。"),
        ("chat.footer.generating", "Deck AI 正在生成回复…"),
        ("chat.status.ready", "就绪"),
        ("chat.status.thinking", "{spinner} 思考中{elapsed}"),
        ("chat.status.waiting_approval", "{spinner} 等待审批{elapsed}"),
        ("chat.meta.thinking", "{spinner} Deck AI 正在思考{elapsed}"),
        ("chat.meta.waiting_approval", "{spinner} 工具调用正在等待你的确认{elapsed}"),
        ("chat.footer.approval_pending", "当前有待审批操作，请先按 Y 或 N。"),
        ("chat.footer.tool_approved_continue", "已批准工具调用，继续执行…"),
        ("chat.footer.tool_approved", "已批准工具调用。"),
        ("chat.footer.tool_rejected", "已拒绝工具调用。"),
        ("chat.footer.history_closed", "已关闭历史列表。"),
        ("chat.busy.restoring_history", "正在恢复会话历史…"),
        ("chat.footer.interrupting", "正在中断当前回复…"),
        ("chat.footer.interrupt_sent", "已发送中断请求。"),
        ("chat.footer.creating_session", "正在创建会话，请稍候…"),
        ("chat.footer.slash_selected", "已选择 {command}，按 Enter 执行。"),
        ("chat.footer.busy_wait", "当前仍有后台操作，请稍候。"),
        ("chat.footer.slash_cancelled", "已取消 slash 命令输入。"),
        ("chat.footer.stopping", "正在停止当前回复…"),
        ("chat.footer.stop_sent", "已发送停止请求。"),
        ("chat.footer.reply_incomplete_stop", "当前回复尚未完成，请先等待或按 ESC 停止。"),
        ("chat.footer.unknown_command", "未知命令。输入 /help 查看可用命令。"),
        ("chat.activity.help_commands", "/cost 查看上下文占用  /compact 手动压缩  /copy 复制最后一条回复  /resume 恢复历史会话  /clear 或 /new 新建会话"),
        ("chat.footer.help_shown", "可用命令已显示在消息区。"),
        ("chat.footer.context_usage", "上下文占用 {usage}  ({tokens} / {window})"),
        ("chat.footer.no_context_usage", "当前还没有上下文占用数据。"),
        ("chat.footer.copied_last_reply", "已复制最后一条回复到系统剪贴板。"),
        ("chat.footer.no_reply_to_copy", "当前还没有可复制的 AI 回复。"),
        ("chat.footer.cannot_clear_while_replying", "当前回复尚未完成，无法新建会话。"),
        ("chat.footer.cleared_new_message_creates_session", "已清空当前对话，下一条消息会创建新会话。"),
        ("chat.busy.clearing_session", "正在清理当前会话…"),
        ("chat.footer.blank_conversation_ready", "已准备新的空白对话。"),
        ("chat.footer.cannot_resume_while_replying", "当前回复尚未完成，无法恢复历史会话。"),
        ("chat.busy.loading_history", "正在读取会话历史…"),
        ("chat.footer.cannot_compact_while_replying", "当前回复尚未完成，无法压缩上下文。"),
        ("chat.footer.nothing_to_compact", "当前还没有可压缩的对话。"),
        ("chat.busy.compacting", "正在压缩上下文…"),
        ("chat.footer.session_ready", "会话已就绪。"),
        ("chat.footer.approval_required", "需要审批。按 Y 同意，按 N 拒绝。"),
        ("chat.footer.compact_done", "上下文压缩完成{suffix}。"),
        ("chat.footer.compact_done_suffix", "，压缩了 {count} 段历史"),
        ("chat.footer.compacting_attempt", "正在自动压缩上下文（第 {attempt} 次）…"),
        ("chat.footer.round_done", "本轮回复完成。"),
        ("chat.footer.no_history", "当前还没有可恢复的历史会话。"),
        ("chat.footer.history_loaded_more", "已加载更多历史会话。"),
        ("chat.footer.history_choose", "选择要恢复的历史会话。继续向下可加载更多。"),
        ("chat.header.account_hidden", "未显示账号"),
        ("chat.header.context_usage", "上下文 {usage}"),
        ("chat.header.context_usage_none", "上下文 --"),
        ("chat.header.mode.following", "跟随输出"),
        ("chat.header.mode.reviewing", "浏览历史"),
        ("chat.body.title.following", " 对话 · 跟随输出 "),
        ("chat.body.title.reviewing", " 对话 · 浏览历史 "),
        ("chat.input.title.prompt", " 输入 "),
        ("chat.input.title.prompt_slash", " 输入 · Slash "),
        ("chat.footer.default.slash", "↑/↓ 选择命令  Tab 补全  Enter 执行  Esc 取消"),
        ("chat.footer.default.following", "Enter 发送  Ctrl+C 双击退出  鼠标/↑↓/PgUp/PgDn 浏览  /help 命令"),
        ("chat.footer.default.reviewing", "正在浏览历史消息  Ctrl+End 回到底部继续跟随"),
        ("chat.approval.needs", "需要审批: {tool}"),
        ("chat.approval.actions", "按 Y 同意，按 N 拒绝"),
        ("chat.approval.title", " 审批 "),
        ("chat.commands.title", " 命令 "),
        ("chat.resume.title", " 恢复 · 已加载 {count} 条 "),
        ("chat.resume.loading_more", "{spinner} 正在加载更多历史会话…"),
        ("chat.resume.more_available", "继续向下浏览可自动加载更多 · Enter 恢复 · Esc 关闭"),
        ("chat.resume.end", "已到末尾 · Enter 恢复 · Esc 关闭"),
        ("chat.empty", "还没有消息，直接输入内容开始对话。"),
        ("chat.tool.searching_clipboard", "正在搜索剪贴板…"),
        ("chat.tool.searching_clipboard_with_query", "正在搜索剪贴板: {query}"),
        ("chat.tool.writing_clipboard", "正在写入 Deck 剪贴板…"),
        ("chat.tool.deleting_clipboard", "正在删除剪贴板项…"),
        ("chat.tool.running", "正在执行工具: {tool}"),
        ("chat.tool.rejected", "已拒绝工具调用: {tool}"),
        ("chat.tool.failed_default", "工具执行失败"),
        ("chat.tool.failed", "工具 {tool} 执行失败: {error}"),
        ("chat.tool.finished", "工具执行完成: {tool}"),
        ("chat.approval.write_text", "将写入以下文本:\n\n{text}"),
        ("chat.approval.write_text_default", "将写入新的文本内容。"),
        ("chat.approval.delete_item", "将删除 item_id = {id} 的剪贴板记录。"),
        ("chat.approval.delete_default", "将删除一条剪贴板记录。"),
        ("chat.approval.generic", "该工具请求需要你的确认。"),
    ])
}

fn chat_en() -> Map {
    HashMap::from([
        ("chat.slash.cost.description", "View current context usage"),
        ("chat.slash.compact.description", "Compact the current conversation context"),
        ("chat.slash.copy.description", "Copy the last AI reply"),
        ("chat.slash.resume.description", "Open the conversation history list"),
        ("chat.slash.clear.description", "Start a blank conversation"),
        ("chat.slash.help.description", "Show available command help"),
        ("chat.quit_hint", "Press Ctrl+C again to exit"),
        ("chat.conversation.new", "New Conversation"),
        ("chat.model.not_started", "Not started"),
        ("chat.footer.ready", "Deck AI is ready. Type to send directly, or use /help to view commands."),
        ("chat.footer.generating", "Deck AI is generating a reply…"),
        ("chat.status.ready", "Ready"),
        ("chat.status.thinking", "{spinner} Thinking{elapsed}"),
        ("chat.status.waiting_approval", "{spinner} Waiting approval{elapsed}"),
        ("chat.meta.thinking", "{spinner} Deck AI is thinking{elapsed}"),
        ("chat.meta.waiting_approval", "{spinner} A tool call is waiting for your approval{elapsed}"),
        ("chat.footer.approval_pending", "There is a pending approval. Press Y or N first."),
        ("chat.footer.tool_approved_continue", "Tool call approved. Continuing…"),
        ("chat.footer.tool_approved", "Tool call approved."),
        ("chat.footer.tool_rejected", "Tool call rejected."),
        ("chat.footer.history_closed", "History list closed."),
        ("chat.busy.restoring_history", "Restoring conversation history…"),
        ("chat.footer.interrupting", "Interrupting the current reply…"),
        ("chat.footer.interrupt_sent", "Interrupt request sent."),
        ("chat.footer.creating_session", "Creating a session, please wait…"),
        ("chat.footer.slash_selected", "Selected {command}. Press Enter to run it."),
        ("chat.footer.busy_wait", "A background action is still running. Please wait."),
        ("chat.footer.slash_cancelled", "Slash command input cancelled."),
        ("chat.footer.stopping", "Stopping the current reply…"),
        ("chat.footer.stop_sent", "Stop request sent."),
        ("chat.footer.reply_incomplete_stop", "The current reply is not finished yet. Wait, or press ESC to stop it."),
        ("chat.footer.unknown_command", "Unknown command. Use /help to see available commands."),
        ("chat.activity.help_commands", "/cost view context usage  /compact compact context manually  /copy copy the last reply  /resume restore a past conversation  /clear or /new start a new chat"),
        ("chat.footer.help_shown", "Available commands were shown in the message area."),
        ("chat.footer.context_usage", "Context usage {usage}  ({tokens} / {window})"),
        ("chat.footer.no_context_usage", "No context usage data is available yet."),
        ("chat.footer.copied_last_reply", "Copied the last reply to the system clipboard."),
        ("chat.footer.no_reply_to_copy", "There is no AI reply to copy yet."),
        ("chat.footer.cannot_clear_while_replying", "The current reply is not finished yet, so a new conversation cannot be created."),
        ("chat.footer.cleared_new_message_creates_session", "The current conversation was cleared. Your next message will create a new session."),
        ("chat.busy.clearing_session", "Cleaning up the current session…"),
        ("chat.footer.blank_conversation_ready", "A fresh blank conversation is ready."),
        ("chat.footer.cannot_resume_while_replying", "The current reply is not finished yet, so history cannot be restored."),
        ("chat.busy.loading_history", "Loading conversation history…"),
        ("chat.footer.cannot_compact_while_replying", "The current reply is not finished yet, so the context cannot be compacted."),
        ("chat.footer.nothing_to_compact", "There is no conversation to compact yet."),
        ("chat.busy.compacting", "Compacting context…"),
        ("chat.footer.session_ready", "Session is ready."),
        ("chat.footer.approval_required", "Approval required. Press Y to allow, or N to reject."),
        ("chat.footer.compact_done", "Context compaction finished{suffix}."),
        ("chat.footer.compact_done_suffix", ", compressed {count} history segments"),
        ("chat.footer.compacting_attempt", "Compacting context automatically (attempt {attempt})…"),
        ("chat.footer.round_done", "This reply is complete."),
        ("chat.footer.no_history", "There is no conversation history to restore yet."),
        ("chat.footer.history_loaded_more", "Loaded more conversation history."),
        ("chat.footer.history_choose", "Choose a conversation to restore. Keep scrolling down to load more."),
        ("chat.header.account_hidden", "Account hidden"),
        ("chat.header.context_usage", "Context {usage}"),
        ("chat.header.context_usage_none", "Context --"),
        ("chat.header.mode.following", "Following"),
        ("chat.header.mode.reviewing", "Reviewing"),
        ("chat.body.title.following", " Conversation · Following "),
        ("chat.body.title.reviewing", " Conversation · Reviewing "),
        ("chat.input.title.prompt", " Prompt "),
        ("chat.input.title.prompt_slash", " Prompt · Slash "),
        ("chat.footer.default.slash", "↑/↓ choose  Tab complete  Enter run  Esc cancel"),
        ("chat.footer.default.following", "Enter to send  Ctrl+C twice to exit  Mouse/↑↓/PgUp/PgDn to scroll  /help for commands"),
        ("chat.footer.default.reviewing", "Browsing history  Ctrl+End to jump back to live follow"),
        ("chat.approval.needs", "Approval required: {tool}"),
        ("chat.approval.actions", "Press Y to allow, or N to reject"),
        ("chat.approval.title", " Approval "),
        ("chat.commands.title", " Commands "),
        ("chat.resume.title", " Resume · {count} loaded "),
        ("chat.resume.loading_more", "{spinner} Loading more conversation history…"),
        ("chat.resume.more_available", "Keep scrolling down to load more · Enter to restore · Esc to close"),
        ("chat.resume.end", "End reached · Enter to restore · Esc to close"),
        ("chat.empty", "No messages yet. Type something to start the conversation."),
        ("chat.tool.searching_clipboard", "Searching the clipboard…"),
        ("chat.tool.searching_clipboard_with_query", "Searching the clipboard: {query}"),
        ("chat.tool.writing_clipboard", "Writing to the Deck clipboard…"),
        ("chat.tool.deleting_clipboard", "Deleting the clipboard item…"),
        ("chat.tool.running", "Running tool: {tool}"),
        ("chat.tool.rejected", "Tool call rejected: {tool}"),
        ("chat.tool.failed_default", "Tool execution failed"),
        ("chat.tool.failed", "Tool {tool} failed: {error}"),
        ("chat.tool.finished", "Tool finished: {tool}"),
        ("chat.approval.write_text", "The following text will be written:\n\n{text}"),
        ("chat.approval.write_text_default", "New text will be written."),
        ("chat.approval.delete_item", "The clipboard record with item_id = {id} will be deleted."),
        ("chat.approval.delete_default", "A clipboard record will be deleted."),
        ("chat.approval.generic", "This tool request needs your approval."),
    ])
}

fn chat_de() -> Map {
    chat_en()
}

fn chat_fr() -> Map {
    chat_en()
}

fn chat_ja() -> Map {
    chat_en()
}

fn chat_ko() -> Map {
    chat_en()
}

fn chat_zh_hant() -> Map {
    HashMap::new()
}
