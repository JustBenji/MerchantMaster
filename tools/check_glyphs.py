"""Validate UTF-8 Lua glyph allowlist across shipped MerchantMaster files."""

from __future__ import annotations

import pathlib
import sys

ALLOWED = {"\u00b7", "\u2014", "\u2013", "\u2026", "\u00d7", "\u00e9", "\u00ea", "\u00e8", "\u00c9", "\u00f4", "\u00e0"}
TOOLS_DIR = pathlib.Path(__file__).resolve().parent
MM_ROOT = TOOLS_DIR.parent
SKIP_TOP = {".git", ".release", "tests", "tools", "docs"}


def scan_lua_text(label: str, text: str) -> list[str]:
    bad: list[str] = []
    for line_no, line in enumerate(text.splitlines(), 1):
        for ch in line:
            if ord(ch) >= 128 and ch not in ALLOWED:
                bad.append(f"{label}:{line_no}: U+{ord(ch):04X}")
    return bad


def check_root(root: pathlib.Path = MM_ROOT) -> tuple[int, list[str]]:
    bad: list[str] = []
    files_checked = 0
    for p in sorted(root.rglob("*.lua")):
        rel = p.relative_to(root)
        if rel.parts and rel.parts[0] in SKIP_TOP:
            continue
        files_checked += 1
        text = p.read_text(encoding="utf-8")
        bad.extend(scan_lua_text(rel.as_posix(), text))
    return files_checked, bad


def main() -> int:
    files_checked, bad = check_root(MM_ROOT)
    print(f"FILES_CHECKED={files_checked} BAD_GLYPHS={len(bad)}")
    for item in bad[:30]:
        print("  BAD:", item)
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
