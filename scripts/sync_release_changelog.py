#!/usr/bin/env python3
"""
同步 GitHub Release 到仓库根目录：
- CHANGELOG.md：元数据 + Release notes 仅保留英文叙述
- CHANGELOG_CN.md：元数据 + Release notes 仅保留中文叙述

incremental：仅从 GITHUB_EVENT_PATH 处理当前 Release。
full：分页拉取全部 Release；以 CHANGELOG.md 为准做去重，只补缺失 tag（不覆盖已有条目）。
"""
from __future__ import annotations

import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Literal

CHANGELOG_EN = "CHANGELOG.md"
CHANGELOG_CN = "CHANGELOG_CN.md"
MARKER_AUTO = "<!-- release-changelog-bot:auto -->"
TAG_PREFIX = "<!-- release-changelog-bot:tag:"
GITHUB_API = "https://api.github.com"

CJK_RE = re.compile(r"[\u4e00-\u9fff]")
# 去掉反引号片段与 URL 后再判断语言，避免 `web_search`、链接干扰
_CODE_RE = re.compile(r"`[^`]*`")
_URL_RE = re.compile(r"https?://\S+")
_WORD_EN_RE = re.compile(r"[A-Za-z]{4,}")


def _probe_text(s: str) -> str:
    s = _CODE_RE.sub(" ", s)
    s = _URL_RE.sub(" ", s)
    return s


def primary_lang_line(line: str) -> Literal["zh", "en", "mixed", "neutral"]:
    raw = line.strip()
    if not raw or raw == "---":
        return "neutral"
    if raw.startswith("```"):
        return "neutral"
    if raw.startswith("<") and ">" in raw:
        return "neutral"
    probe = _probe_text(raw)
    has_cjk = bool(CJK_RE.search(probe))
    en_n = len(_WORD_EN_RE.findall(probe))
    if has_cjk and en_n == 0:
        return "zh"
    if has_cjk and en_n >= 1:
        return "mixed"
    if not has_cjk and en_n >= 1:
        return "en"
    return "neutral"


def split_mixed_line(text: str) -> tuple[str, str] | None:
    """单行内「中文句 + 空白 + 英文」拆成 (zh, en)。"""
    t = text.strip()
    m = re.match(
        r"^(.*?[\u4e00-\u9fff].*?[。！？…])\s{2,}([A-Za-z].*)$",
        t,
    )
    if m:
        return m.group(1).strip(), m.group(2).strip()
    m2 = re.match(
        r"^([A-Za-z][^.。!！?？\n]*[.!?。！？])\s{2,}(.*[\u4e00-\u9fff].*)$",
        t,
    )
    if m2:
        return m2.group(2).strip(), m2.group(1).strip()
    return None


def split_bilingual_heading_title(title: str) -> tuple[str, str] | None:
    """`### 新增 / Added` → (中文侧, 英文侧)。无法可靠拆分时返回 None。"""
    if " / " not in title:
        return None
    left, right = title.split(" / ", 1)
    left, right = left.strip(), right.strip()
    if not left or not right:
        return None
    l_cjk = bool(CJK_RE.search(left))
    r_cjk = bool(CJK_RE.search(right))
    if l_cjk and not r_cjk:
        return left, right
    if r_cjk and not l_cjk:
        return right, left
    return None


def localize_release_notes_heading(line: str, locale: str) -> str:
    """`## Release Notes v1.2.3` 在中文版改为「更新说明」。"""
    m = re.match(r"^(##)\s*Release Notes\s+(\S.*)$", line.rstrip())
    if m and locale == "zh":
        return f"{m.group(1)} 更新说明 {m.group(2).strip()}"
    return line.rstrip("\n")


def filter_release_notes_body(body: str, locale: Literal["en", "zh"]) -> str:
    if not body.strip():
        return ""
    lines = body.replace("\r\n", "\n").split("\n")
    out: list[str] = []
    i = 0
    n = len(lines)

    def emit(s: str) -> None:
        out.append(s)

    while i < n:
        line = lines[i]
        st = line.strip()

        if st == "":
            emit("")
            i += 1
            continue

        if st == "---":
            emit("---")
            i += 1
            continue

        # 多行 HTML（横幅图等）：原样写入两种语言文件
        if "<p" in line or "<picture" in line:
            while i < n:
                emit(lines[i])
                if "</p>" in lines[i] or "</picture>" in lines[i]:
                    i += 1
                    break
                i += 1
            continue

        # 折叠块（GitHub Release 内 <details>）：整块原样写入，避免块内表格/标题被按行拆中英
        if st.startswith("<details"):
            while i < n:
                emit(lines[i])
                if "</details>" in lines[i]:
                    i += 1
                    break
                i += 1
            continue

        if st.startswith("<") and ">" in st:
            emit(line)
            i += 1
            continue

        if re.match(r"^#+\s", line):
            m = re.match(r"^(#+)\s*(.*)$", line.rstrip())
            if m:
                level, title = m.group(1), m.group(2).strip()
                sp = split_bilingual_heading_title(title)
                if sp:
                    zh_t, en_t = sp
                    title_out = en_t if locale == "en" else zh_t
                    emit(f"{level} {title_out}")
                else:
                    ln = localize_release_notes_heading(line.rstrip(), locale)
                    emit(ln)
            i += 1
            continue

        m_bullet = re.match(r"^(\s*-\s+)(.*)$", line)
        if m_bullet:
            bullet_prefix = m_bullet.group(1)
            first_raw = m_bullet.group(2)
            cont: list[str] = []
            i += 1
            while i < n:
                L = lines[i]
                if L.strip() == "":
                    break
                if re.match(r"^-\s+", L) and not L.startswith(" ") and not L.startswith("\t"):
                    break
                if L.startswith("  ") or L.startswith("\t"):
                    cont.append(L)
                    i += 1
                    continue
                break

            segs: list[tuple[str, str]] = []

            def add_from_text(text: str, indent: str = "") -> None:
                sm = split_mixed_line(text)
                if sm:
                    segs.append(("zh", indent + sm[0]))
                    segs.append(("en", indent + sm[1]))
                    return
                pl = primary_lang_line(text)
                if pl == "mixed":
                    probe = _probe_text(text)
                    zc = len(CJK_RE.findall(probe))
                    ec = len(_WORD_EN_RE.findall(probe))
                    side: Literal["zh", "en"] = "zh" if zc >= ec else "en"
                    segs.append((side, indent + text))
                else:
                    segs.append((pl, indent + text))

            add_from_text(first_raw)
            for L in cont:
                indent_m = re.match(r"^(\s+)(.*)$", L)
                ind = indent_m.group(1) if indent_m else ""
                body_part = indent_m.group(2) if indent_m else L
                add_from_text(body_part, ind)

            want = "en" if locale == "en" else "zh"
            kept: list[str] = []
            for pl, chunk in segs:
                if pl in ("neutral", "mixed"):
                    kept.append(chunk)
                elif pl == want:
                    kept.append(chunk)

            if kept:
                emit(bullet_prefix + kept[0])
                for rest in kept[1:]:
                    if not rest[:1].isspace():
                        emit("  " + rest)
                    else:
                        emit(rest)
            continue

        pl = primary_lang_line(line)
        sm = split_mixed_line(line)
        if sm:
            emit(sm[1] if locale == "en" else sm[0])
        elif pl == "neutral":
            emit(line)
        elif pl == "mixed":
            probe = _probe_text(line)
            zc = len(CJK_RE.findall(probe))
            ec = len(_WORD_EN_RE.findall(probe))
            pick_zh = zc >= ec
            if (locale == "zh" and pick_zh) or (locale == "en" and not pick_zh):
                emit(line)
        elif pl == locale:
            emit(line)
        i += 1

    return collapse_extra_blank_lines("\n".join(out))


def collapse_extra_blank_lines(text: str) -> str:
    text = re.sub(r"\n{4,}", "\n\n\n", text)
    return text.strip() + ("\n" if text.strip() else "")


@dataclass
class ReleaseView:
    tag: str
    title: str
    body: str
    published_at: str
    assets: list[tuple[str, str]]


def _http_get_links(resp: Any) -> dict[str, str]:
    raw = resp.headers.get("Link", "")
    links: dict[str, str] = {}
    for part in raw.split(","):
        m = re.search(r'<([^>]+)>;\s*rel="(\w+)"', part.strip())
        if m:
            links[m.group(2)] = m.group(1)
    return links


def fetch_release_by_tag(repo: str, tag: str, token: str) -> dict[str, Any] | None:
    enc = urllib.parse.quote(tag, safe="")
    url = f"{GITHUB_API}/repos/{repo}/releases/tags/{enc}"
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "release-changelog-bot",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise


def fetch_all_releases(repo: str, token: str) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    url = f"{GITHUB_API}/repos/{repo}/releases?per_page=100"
    while url:
        req = urllib.request.Request(
            url,
            headers={
                "Accept": "application/vnd.github+json",
                "Authorization": f"Bearer {token}",
                "X-GitHub-Api-Version": "2022-11-28",
                "User-Agent": "release-changelog-bot",
            },
        )
        with urllib.request.urlopen(req, timeout=120) as resp:
            page = json.loads(resp.read().decode("utf-8"))
            links = _http_get_links(resp)
            out.extend(page)
            url = links.get("next")
    return out


def release_from_api_obj(obj: dict[str, Any]) -> ReleaseView | None:
    if obj.get("draft"):
        return None
    tag = obj.get("tag_name") or ""
    if not tag:
        return None
    assets: list[tuple[str, str]] = []
    for a in obj.get("assets") or []:
        name = a.get("name") or ""
        u = a.get("browser_download_url") or ""
        if name and u:
            assets.append((name, u))
    return ReleaseView(
        tag=tag,
        title=(obj.get("name") or "").strip() or tag,
        body=(obj.get("body") or "").strip(),
        published_at=obj.get("published_at") or "",
        assets=assets,
    )


def release_from_event_payload(payload: dict[str, Any]) -> ReleaseView | None:
    rel = payload.get("release") or {}
    if not isinstance(rel, dict):
        return None
    return release_from_api_obj(rel)


def format_block(r: ReleaseView, locale: Literal["en", "zh"]) -> str:
    raw_body = r.body if r.body else ""
    notes = filter_release_notes_body(raw_body, locale)
    if not notes.strip():
        notes = "_No release notes._" if locale == "en" else "_（无正文）_"

    lines: list[str] = [
        f"{TAG_PREFIX}{r.tag} -->",
        f"## {r.tag} — {r.title}",
        "",
        f"- **Tag:** `{r.tag}`",
        f"- **Published:** {r.published_at or '_unknown_'}",
        "",
        "### Release notes",
        "",
        notes.rstrip(),
        "",
        "### Assets",
        "",
    ]
    if r.assets:
        for name, url in r.assets:
            lines.append(f"- [`{name}`]({url})")
    else:
        lines.append("_（无附件）_" if locale == "zh" else "_No assets._")
    lines.append("")
    return "\n".join(lines)


def default_preamble_en() -> str:
    return "\n".join(
        [
            "# GitHub Releases Changelog",
            "",
            "This file is auto-generated from GitHub Releases by [release-changelog-bot](.github/workflows/release-changelog-bot.yml). **Do not hand-edit release entries** (you may edit this intro).",
            "",
            MARKER_AUTO,
            "",
        ]
    )


def default_preamble_cn() -> str:
    return "\n".join(
        [
            "# GitHub Releases 更新日志",
            "",
            "本文件由 [release-changelog-bot](.github/workflows/release-changelog-bot.yml) 根据 GitHub Release 自动生成；**请勿手动修改各版本条目**（可修改本说明）。",
            "",
            MARKER_AUTO,
            "",
        ]
    )


def parse_blocks_from_body(body: str) -> dict[str, str]:
    blocks: dict[str, str] = {}
    pattern = re.compile(
        re.escape(TAG_PREFIX) + r"(.+?) -->\r?\n(.*?)(?=" + re.escape(TAG_PREFIX) + r"|\Z)",
        re.DOTALL,
    )
    for m in pattern.finditer(body.strip() + "\n"):
        tag = m.group(1).strip()
        blocks[tag] = m.group(0).rstrip() + "\n"
    return blocks


def parse_existing(path: str, default_preamble: str) -> tuple[str, dict[str, str]]:
    if not os.path.isfile(path):
        return default_preamble, {}
    raw = open(path, encoding="utf-8").read()
    if MARKER_AUTO in raw:
        head, rest = raw.split(MARKER_AUTO, 1)
        preamble = head + MARKER_AUTO + "\n\n"
        rest = rest.lstrip("\n")
        blocks = parse_blocks_from_body(rest)
        return preamble, blocks
    preamble = default_preamble
    blocks = parse_blocks_from_body(raw)
    return preamble, blocks


def published_at_from_block(block: str) -> str:
    m = re.search(r"^\-\s\*\*Published:\*\*\s*(.+)$", block, re.MULTILINE)
    if not m:
        return ""
    s = m.group(1).strip()
    if s == "_unknown_":
        return ""
    return s


def parse_iso(dt: str) -> datetime:
    if not dt:
        return datetime.min.replace(tzinfo=None)
    try:
        d = datetime.fromisoformat(dt.replace("Z", "+00:00"))
        return d.replace(tzinfo=None)
    except ValueError:
        return datetime.min.replace(tzinfo=None)


def sort_blocks(blocks: dict[str, str]) -> list[str]:
    tags = list(blocks.keys())
    tags.sort(
        key=lambda t: parse_iso(published_at_from_block(blocks[t])),
        reverse=True,
    )
    return [blocks[t] for t in tags]


def write_changelog(path: str, preamble: str, ordered_blocks: list[str]) -> None:
    body = preamble.rstrip() + "\n\n"
    body += "\n".join(b.rstrip() + "\n" for b in ordered_blocks if b.strip())
    if not body.endswith("\n"):
        body += "\n"
    open(path, "w", encoding="utf-8").write(body)


def run_incremental(repo_root: str) -> bool:
    event_path = os.environ.get("GITHUB_EVENT_PATH")
    if not event_path or not os.path.isfile(event_path):
        print("incremental 模式需要 GITHUB_EVENT_PATH", file=sys.stderr)
        sys.exit(1)
    payload = json.load(open(event_path, encoding="utf-8"))
    rel = release_from_event_payload(payload)
    if rel is None:
        print("跳过：草稿/无 tag", file=sys.stderr)
        return False

    path_en = os.path.join(repo_root, CHANGELOG_EN)
    path_cn = os.path.join(repo_root, CHANGELOG_CN)
    preamble_en, blocks_en = parse_existing(path_en, default_preamble_en())
    preamble_cn, blocks_cn = parse_existing(path_cn, default_preamble_cn())

    if rel.tag in blocks_en:
        print(f"已存在 {rel.tag}（以 {CHANGELOG_EN} 为准），跳过（去重）")
        return False

    blocks_en[rel.tag] = format_block(rel, "en")
    blocks_cn[rel.tag] = format_block(rel, "zh")
    write_changelog(path_en, preamble_en, sort_blocks(blocks_en))
    write_changelog(path_cn, preamble_cn, sort_blocks(blocks_cn))
    print(f"已追加 Release: {rel.tag} → {CHANGELOG_EN} + {CHANGELOG_CN}")
    return True


def run_full(repo: str, repo_root: str, token: str) -> bool:
    path_en = os.path.join(repo_root, CHANGELOG_EN)
    path_cn = os.path.join(repo_root, CHANGELOG_CN)
    preamble_en, blocks_en = parse_existing(path_en, default_preamble_en())
    preamble_cn, blocks_cn = parse_existing(path_cn, default_preamble_cn())

    api_objs = fetch_all_releases(repo, token)
    views = [v for o in api_objs if (v := release_from_api_obj(o)) is not None]
    changed = False
    for v in views:
        if v.tag not in blocks_en:
            blocks_en[v.tag] = format_block(v, "en")
            blocks_cn[v.tag] = format_block(v, "zh")
            changed = True
    # 若曾只删过 CHANGELOG_CN.md，按 tag 单条补回中文档
    for t in list(blocks_en.keys()):
        if t not in blocks_cn:
            obj = fetch_release_by_tag(repo, t, token)
            if obj:
                v = release_from_api_obj(obj)
                if v:
                    blocks_cn[t] = format_block(v, "zh")
                    changed = True

    if not changed:
        print("全量扫描：无缺失 Release，文件未修改")
        return False
    write_changelog(path_en, preamble_en, sort_blocks(blocks_en))
    write_changelog(path_cn, preamble_cn, sort_blocks(blocks_cn))
    print(f"全量扫描完成，当前共 {len(blocks_en)} 条 Release 记录")
    return True


def main() -> None:
    mode = os.environ.get("SYNC_MODE", "").strip().lower()
    token = os.environ.get("GITHUB_TOKEN", "").strip()
    repo = os.environ.get("GITHUB_REPOSITORY", "").strip()
    repo_root = os.environ.get("GITHUB_WORKSPACE", os.getcwd()).strip()

    if not token or not repo:
        print("需要环境变量 GITHUB_TOKEN 与 GITHUB_REPOSITORY", file=sys.stderr)
        sys.exit(1)
    if mode not in ("incremental", "full"):
        print("SYNC_MODE 须为 incremental 或 full", file=sys.stderr)
        sys.exit(1)

    if mode == "incremental":
        changed = run_incremental(repo_root)
    else:
        changed = run_full(repo, repo_root, token)

    flag = os.path.join(repo_root, ".release-changelog-changed")
    if changed:
        open(flag, "w", encoding="utf-8").write("1")
    elif os.path.isfile(flag):
        os.remove(flag)


if __name__ == "__main__":
    main()
