#!/usr/bin/env python3
"""在所有 Swift 源文件顶部添加或更新版权说明。"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Iterable


COPYRIGHT_BASE_YEAR = 2024
COPYRIGHT_HOLDER = "Yuze Pan"
COPYRIGHT_SUFFIX = "保留一切权利。"


def current_header_line() -> str:
    year_range = f"{COPYRIGHT_BASE_YEAR}–{date.today().year}"
    return f"// Copyright © {year_range} {COPYRIGHT_HOLDER}. {COPYRIGHT_SUFFIX}"


def _read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _write_text(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")


@dataclass
class FileResult:
    path: Path
    changed: bool


def ensure_header(path: Path, header: str) -> FileResult:
    text = _read_text(path)
    bom = ""
    if text.startswith("\ufeff"):
        bom = "\ufeff"
        text = text[1:]

    lines = text.splitlines()
    if lines and lines[0].strip().startswith("// Copyright ©") and COPYRIGHT_HOLDER in lines[0]:
        if lines[0].strip() == header:
            return FileResult(path=path, changed=False)
        lines[0] = header
        joined = "\n".join(lines)
        if text.endswith("\n"):
            joined += "\n"
        _write_text(path, bom + joined)
        return FileResult(path=path, changed=True)

    new_text = f"{bom}{header}\n\n{text}"
    _write_text(path, new_text)
    return FileResult(path=path, changed=True)


def swift_files(root: Path) -> Iterable[Path]:
    yield from sorted(root.rglob("*.swift"))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="给 Deck 代码库中的 Swift 文件添加版权说明。")
    parser.add_argument(
        "root",
        nargs="?",
        default=".",
        help="Swift 源码所在的根目录（默认当前目录）。",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    root = Path(args.root).expanduser().resolve()
    header = current_header_line()
    results = [ensure_header(path, header) for path in swift_files(root)]
    changed = [r for r in results if r.changed]

    print("版权头已添加/更新：", len(changed))


if __name__ == "__main__":
    main()
