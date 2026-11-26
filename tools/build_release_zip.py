#!/usr/bin/env python3
"""Build and verify standalone MerchantMaster release zips and repository hygiene gates."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import zipfile
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

from check_glyphs import scan_lua_text  # noqa: E402

ROOT = TOOLS_DIR.parent
TOC_PATH = ROOT / "MerchantMaster.toc"
DIST_DIR = ROOT / "tools" / "dist"

ALLOWED_STATIC_DIRS = ("Libs", "Analytics", "Textures", "Assets")
ALLOWED_ROOT_EXTRAS = (
    "MerchantMaster.toc",
    "LICENSE",
    "THIRD_PARTY_LICENSES.md",
    "README.md",
    "CHANGELOG.md",
)
FORBIDDEN_TOP_NAMES = {".git", ".github", ".gitignore", ".gitattributes", ".pkgmeta", ".previews", ".release", "AGENTS.md", "docs", "tests", "tools"}
ZIP_ALLOWED_EXTS = {".lua", ".toc", ".blp", ".tga", ".ttf", ".txt", ".md"}
ZIP_ALLOWED_EXACT_NAMES = {"LICENSE"}
ZIP_TEXT_EXTS = {".lua", ".toc", ".md", ".txt"}
REPO_TEXT_EXTS = {
    ".lua", ".toc", ".py", ".ps1", ".md", ".txt", ".yml", ".yaml",
    ".json", ".pkgmeta", ".xml", ".gitattributes", ".gitignore",
}
REPO_TEXT_EXACT_NAMES = {"LICENSE", ".gitignore", ".gitattributes", ".pkgmeta"}
REQUIRED_ZIP_FILES = (
    "MerchantMaster/MerchantMaster.toc",
    "MerchantMaster/LICENSE",
    "MerchantMaster/THIRD_PARTY_LICENSES.md",
    "MerchantMaster/Assets/fonts/OFL.txt",
    "MerchantMaster/Assets/fonts/Inter-Regular.ttf",
    "MerchantMaster/Assets/fonts/Inter-SemiBold.ttf",
)

WALK_SKIP_DIRS = {".git", ".release", "__pycache__"}
WALK_SKIP_REL_PREFIXES = ("tools/dist", "tools/scene_dumps", "tests/offline" + "_sv", "tests/logs")
WALK_SKIP_FILES = {".private_denylist.txt", "AGENTS.md"}
WALK_SKIP_EXTS = {".pyc", ".bak", ".orig", ".log", ".tsv"}

# Fragmented patterns prevent this scanner from matching its own source lines.
BUILTIN_TEXT_RULES: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("github_token_pattern", re.compile(r"\b(?:ghp|gho)_[A-Za-z0-9]{20,}\b|\bgithub_pat_[A-Za-z0-9_]{20,}\b")),
    ("aws_access_key", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("api_secret_key", re.compile(r"(?<![A-Za-z0-9_])sk-[A-Za-z0-9]{16,}")),
    ("jwt_token", re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}(?:\.[A-Za-z0-9_-]{5,})?\b")),
    ("bearer_auth_token", re.compile(r"\bBearer\s+[A-Za-z0-9._-]{16,}")),
    ("private_key_header", re.compile(r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----")),
    ("blizzard_secret_assignment", re.compile(r"(?i)BLIZZARD_CLIENT_SECRET\s*[:=]\s*[\"']?[A-Za-z0-9_.-]{8,}")),
    ("personal_email", re.compile(r"(?i)[A-Za-z0-9._%+-]+@(?:gmail|hotmail|outlook)\.com\b")),
    ("local_windows_path", re.compile(r"(?i)[A-Za-z]:[/\\]+(?:Users|Games|Second-Brain|AppData)(?:[/\\]|$)")),
    ("local_windows_fonts_path", re.compile(r"(?i)[A-Za-z]:[/\\]+Windows[/\\]+Fonts\b")),
    ("local_unix_user_path", re.compile(r"(?<![A-Za-z0-9_:/])/(?:Users|home)/[A-Za-z0-9._-]+")),
    ("questiedb_ref", re.compile(r"(?i)\bQuestie" + r"DB\b")),
    ("zygor_ref", re.compile(r"(?i)\bZy" + r"gor\b")),
    ("loadprofiler_ref", re.compile(r"!!!" + r"Load" + r"Profiler|zzz" + r"Load" + r"ProfilerTail|\bLoad" + r"Profiler(?:DB|Runs|Tail)?\b")),
    ("personal_migration_ref", re.compile(r"Migrate" + r"GreenLensDE")),
    ("legacy_standalone_analytics_ref", re.compile(r"MerchantMaster_" + r"Analytics")),
    ("offline_sv_ref", re.compile(r"\boffline" + r"_sv\b")),
    ("legacy_font_asset_ref", re.compile(r"\bfont_" + r"(?:regular|semibold)\.ttf\b")),
)
OFFLINE_SV_RULE = "offline_sv_ref"
IGNORE_CONFIG_FILES = {".gitignore", ".pkgmeta"}


def _compile_literal_denylist_pattern(term: str) -> re.Pattern[str]:
    prefix = r"(?<![A-Za-z0-9])" if term[0].isalnum() else ""
    suffix = r"(?![A-Za-z0-9])" if term[-1].isalnum() else ""
    return re.compile(prefix + re.escape(term) + suffix, re.I)


def load_private_denylist() -> list[tuple[str, re.Pattern[str]]]:
    raw_entries: list[str] = []
    env_val = os.environ.get("MM_PRIVATE_DENYLIST", "")
    if env_val.strip():
        for raw_line in env_val.splitlines():
            stripped = raw_line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            if stripped.startswith("re:"):
                raw_entries.append(stripped)
            else:
                raw_entries.extend(re.split(r"[,;]+", stripped))

    deny_file = ROOT / ".private_denylist.txt"
    if deny_file.is_file():
        for line in deny_file.read_text(encoding="utf-8", errors="replace").splitlines():
            stripped = line.strip()
            if stripped and not stripped.startswith("#"):
                raw_entries.append(stripped)

    compiled: list[tuple[str, re.Pattern[str]]] = []
    seen: set[str] = set()
    for item in raw_entries:
        token = item.strip()
        if not token or token in seen:
            continue
        seen.add(token)
        if token.startswith("re:"):
            expr = token[3:].strip()
            if not expr:
                continue
            try:
                compiled.append(("private_denylist_regex", re.compile(expr, re.I)))
            except re.error as exc:
                raise RuntimeError(f"Invalid regex in private denylist: {exc}") from exc
        else:
            compiled.append(("private_denylist_term", _compile_literal_denylist_pattern(token)))
    return compiled


def parse_toc_text(toc_text: str) -> tuple[str, list[str], list[str], list[str]]:
    version = "0.0.0"
    interfaces: list[str] = []
    saved_vars: list[str] = []
    lua_rel_paths: list[str] = []

    for raw in toc_text.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("## Version:"):
            version = line.split(":", 1)[1].strip()
            continue
        if line.startswith("## Interface:"):
            val = line.split(":", 1)[1].strip()
            interfaces.extend([part.strip() for part in val.split(",") if part.strip()])
            continue
        if line.startswith("## SavedVariables:"):
            val = line.split(":", 1)[1].strip()
            saved_vars.extend([part.strip() for part in val.split(",") if part.strip()])
            continue
        if line.startswith("#"):
            continue
        lua_rel_paths.append(line.replace("\\", "/"))
    return version, interfaces, saved_vars, lua_rel_paths


def parse_toc() -> tuple[str, list[Path]]:
    if not TOC_PATH.exists():
        raise FileNotFoundError(f"Missing TOC: {TOC_PATH}")
    toc_text = TOC_PATH.read_text(encoding="utf-8")
    version, _, _, lua_rel_paths = parse_toc_text(toc_text)
    lua_files: list[Path] = []
    for rel in lua_rel_paths:
        full = (ROOT / rel).resolve()
        if not full.exists():
            raise FileNotFoundError(f"TOC file missing on disk: {rel}")
        lua_files.append(full)
    return version, lua_files


def _scan_text_violations(
    rel_posix: str,
    raw: bytes,
    private_rules: list[tuple[str, re.Pattern[str]]],
    require_no_bom: bool = True,
) -> tuple[str | None, list[str]]:
    violations: list[str] = []
    if require_no_bom and raw.startswith(b"\xef\xbb\xbf"):
        violations.append(f"{rel_posix}:1: utf8_bom")
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        violations.append(f"{rel_posix}:1: invalid_utf8")
        return None, violations

    skip_offline_sv = rel_posix in IGNORE_CONFIG_FILES
    all_rules = list(BUILTIN_TEXT_RULES) + private_rules
    for idx, line in enumerate(text.splitlines(), 1):
        for rule_name, pat in all_rules:
            if skip_offline_sv and rule_name == OFFLINE_SV_RULE:
                continue
            if pat.search(line):
                violations.append(f"{rel_posix}:{idx}: {rule_name}")
    return text, violations


def _check_toc_rules(rel_posix: str, toc_text: str) -> list[str]:
    violations: list[str] = []
    _, interfaces, saved_vars, _ = parse_toc_text(toc_text)
    if interfaces != ["16001"]:
        violations.append(f"{rel_posix}:1: invalid_interface_list({','.join(interfaces) or 'missing'})")
    if "MerchantProfessorDB" in saved_vars:
        violations.append(f"{rel_posix}:1: forbidden_toc_savedvar(MerchantProfessorDB)")
    return violations


def _check_tga_bytes(rel_posix: str, raw: bytes) -> list[str]:
    if len(raw) < 18:
        return [f"{rel_posix}:1: truncated_tga"]
    if raw[2] == 10:
        return [f"{rel_posix}:1: rle_tga_disallowed(imgType=10)"]
    return []


def _check_ttf_bytes(rel_posix: str, raw: bytes) -> list[str]:
    violations: list[str] = []
    if len(raw) < 12 or raw[:4] != b"\x00\x01\x00\x00":
        violations.append(f"{rel_posix}:1: invalid_or_nonstatic_ttf_sfnt")
    else:
        num_tables = int.from_bytes(raw[4:6], "big")
        if len(raw) < 12 + num_tables * 16:
            violations.append(f"{rel_posix}:1: truncated_ttf_table_directory")
        else:
            tags = {raw[12 + i * 16 : 16 + i * 16] for i in range(num_tables)}
            if b"fvar" in tags:
                violations.append(f"{rel_posix}:1: variable_font_fvar_disallowed")

    low = raw.lower()
    if b"microsoft" in low or b"segoe ui" in low or b"segoeui" in low:
        violations.append(f"{rel_posix}:1: proprietary_font_copyright_bytes")
    return violations


def _gather_repo_files() -> list[Path]:
    git_dir = ROOT / ".git"
    if git_dir.exists():
        paths: set[Path] = set()
        for cmd in (
            ["git", "-C", str(ROOT), "ls-files", "-z"],
            ["git", "-C", str(ROOT), "ls-files", "--others", "--exclude-standard", "-z"],
        ):
            proc = subprocess.run(cmd, capture_output=True, check=False)
            if proc.returncode != 0:
                paths.clear()
                break
            for chunk in proc.stdout.split(b"\x00"):
                if not chunk:
                    continue
                rel = chunk.decode("utf-8", errors="replace")
                full = ROOT / rel
                if full.is_file():
                    paths.add(full.resolve())
        if paths:
            return sorted(paths, key=lambda p: p.relative_to(ROOT).as_posix().lower())

    chosen: list[Path] = []
    for f in ROOT.rglob("*"):
        if not f.is_file():
            continue
        rel_posix = f.relative_to(ROOT).as_posix()
        parts = f.relative_to(ROOT).parts
        if any(part in WALK_SKIP_DIRS for part in parts):
            continue
        if any(rel_posix.startswith(prefix + "/") or rel_posix == prefix for prefix in WALK_SKIP_REL_PREFIXES):
            continue
        if f.name in WALK_SKIP_FILES or f.name.startswith(".env"):
            continue
        if f.suffix.lower() in WALK_SKIP_EXTS:
            continue
        chosen.append(f.resolve())
    return sorted(chosen, key=lambda p: p.relative_to(ROOT).as_posix().lower())


def run_repo_hygiene() -> int:
    private_rules = load_private_denylist()
    files = _gather_repo_files()
    violations: list[str] = []

    for f in files:
        rel_posix = f.relative_to(ROOT).as_posix()
        suffix = f.suffix.lower()
        name = f.name
        if suffix in REPO_TEXT_EXTS or name in REPO_TEXT_EXACT_NAMES:
            raw = f.read_bytes()
            text, text_hits = _scan_text_violations(rel_posix, raw, private_rules, require_no_bom=True)
            violations.extend(text_hits)
            if text is not None and suffix == ".toc":
                violations.extend(_check_toc_rules(rel_posix, text))
        elif suffix == ".tga":
            violations.extend(_check_tga_bytes(rel_posix, f.read_bytes()))
        elif suffix == ".ttf":
            violations.extend(_check_ttf_bytes(rel_posix, f.read_bytes()))

    if violations:
        print(f"REPO_HYGIENE_FAIL files={len(files)} violations={len(violations)}")
        for item in violations:
            print(f"  {item}")
        return 1

    print(f"REPO_HYGIENE_OK files={len(files)} violations=0")
    return 0


def _validate_release_json(release_json_path: Path, zip_name: str) -> list[str]:
    violations: list[str] = []
    if not release_json_path.is_file():
        return [f"{release_json_path.as_posix()}:1: missing_release_json"]
    try:
        payload = json.loads(release_json_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return [f"{release_json_path.as_posix()}:1: invalid_release_json({exc})"]

    releases = payload.get("releases")
    if not isinstance(releases, list) or not releases:
        return [f"{release_json_path.as_posix()}:1: missing_releases_array"]

    matching = [r for r in releases if isinstance(r, dict) and r.get("filename") == zip_name]
    if not matching:
        return [f"{release_json_path.as_posix()}:1: filename_mismatch({zip_name})"]

    found_forever_16001 = False
    for entry in matching:
        name_val = entry.get("name")
        if not isinstance(name_val, str) or not name_val.strip():
            violations.append(f"{release_json_path.as_posix()}:1: invalid_release_name")
        ver_val = entry.get("version")
        if not isinstance(ver_val, str) or not ver_val.strip() or "@project-version@" in ver_val:
            violations.append(f"{release_json_path.as_posix()}:1: invalid_release_version")
        if entry.get("nolib") is not False:
            violations.append(f"{release_json_path.as_posix()}:1: expected_nolib_false")

        meta = entry.get("metadata")
        if not isinstance(meta, list):
            continue
        for m in meta:
            if not isinstance(m, dict):
                continue
            flavor = str(m.get("flavor", "")).lower()
            iface = m.get("interface")
            if flavor == "forever" and type(iface) is int and iface == 16001:
                found_forever_16001 = True
    if not found_forever_16001:
        violations.append(f"{release_json_path.as_posix()}:1: missing_forever_16001_metadata")
    return violations


def emit_release_json(zip_path: Path, out_path: Path, version_override: str = "") -> dict[str, object]:
    if not zip_path.is_file():
        raise FileNotFoundError(f"Zip archive not found: {zip_path}")

    with zipfile.ZipFile(zip_path, "r") as zf:
        try:
            toc_raw = zf.read("MerchantMaster/MerchantMaster.toc")
        except KeyError as exc:
            raise RuntimeError(f"Missing MerchantMaster/MerchantMaster.toc inside {zip_path.name}") from exc

    toc_text = toc_raw.decode("utf-8")
    title = ""
    for raw_line in toc_text.splitlines():
        line = raw_line.strip()
        if line.startswith("## Title:"):
            title = line.split(":", 1)[1].strip()
            break
    if title != "MerchantMaster":
        raise ValueError(f"Unexpected TOC ## Title: {title!r} in {zip_path.name}")

    toc_version, interfaces, _, _ = parse_toc_text(toc_text)
    version = version_override.strip() or toc_version.strip()
    if not version or "@project-version@" in version:
        raise ValueError(f"Unresolved addon version {version!r} for {zip_path.name}")

    if not interfaces or not all(tok.isdigit() for tok in interfaces):
        raise ValueError(f"Non-numeric ## Interface values {interfaces!r} in {zip_path.name}")
    parsed_ifaces = [int(tok) for tok in interfaces]
    if parsed_ifaces != [16001]:
        raise ValueError(f"Expected ## Interface [16001], got {parsed_ifaces!r} in {zip_path.name}")

    payload = {
        "releases": [
            {
                "name": title,
                "version": version,
                "filename": zip_path.name,
                "nolib": False,
                "metadata": [{"flavor": "forever", "interface": 16001}],
            }
        ]
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(payload, separators=(",", ":")) + "\n", encoding="utf-8")
    return {
        "path": str(out_path),
        "filename": zip_path.name,
        "version": version,
        "flavor": "forever",
        "interface": 16001,
    }


def verify_zip_archive(zip_path: Path, release_json_path: Path | None = None) -> tuple[int, dict[str, int]]:
    if not zip_path.is_file():
        raise FileNotFoundError(f"Zip archive not found: {zip_path}")

    private_rules = load_private_denylist()
    violations: list[str] = []
    entry_names: set[str] = set()
    toc_text: str | None = None
    raw_bytes_total = 0
    lua_checked = 0
    glyph_hits: list[str] = []

    with zipfile.ZipFile(zip_path, "r") as zf:
        for info in zf.infolist():
            name = info.filename
            if name.endswith("/"):
                continue
            if "\\" in name or ".." in name.split("/"):
                violations.append(f"{name}:1: unsafe_zip_path")
                continue
            parts = name.split("/")
            if len(parts) < 2 or parts[0] != "MerchantMaster":
                violations.append(f"{name}:1: unexpected_root_prefix")
                continue

            entry_names.add(name)
            rel_inside = "/".join(parts[1:])
            top_inside = parts[1]
            if top_inside in FORBIDDEN_TOP_NAMES or top_inside.startswith("."):
                violations.append(f"{name}:1: forbidden_zip_entry")
                continue

            ext = Path(rel_inside).suffix.lower()
            if rel_inside not in ZIP_ALLOWED_EXACT_NAMES and ext not in ZIP_ALLOWED_EXTS:
                violations.append(f"{name}:1: unallowlisted_extension({ext or 'none'})")
                continue

            raw = zf.read(info)
            raw_bytes_total += len(raw)

            if rel_inside in ZIP_ALLOWED_EXACT_NAMES or ext in ZIP_TEXT_EXTS:
                text, text_hits = _scan_text_violations(name, raw, private_rules, require_no_bom=True)
                violations.extend(text_hits)
                if text is not None:
                    if name == "MerchantMaster/MerchantMaster.toc":
                        toc_text = text
                        violations.extend(_check_toc_rules(name, text))
                    elif ext == ".lua":
                        lua_checked += 1
                        glyph_hits.extend(scan_lua_text(name, text))
            elif ext == ".tga":
                violations.extend(_check_tga_bytes(name, raw))
            elif ext == ".ttf":
                violations.extend(_check_ttf_bytes(name, raw))

    for req in REQUIRED_ZIP_FILES:
        if req not in entry_names:
            violations.append(f"{req}:1: missing_required_file")

    if toc_text is not None:
        _, _, _, toc_lua_rels = parse_toc_text(toc_text)
        for rel in toc_lua_rels:
            expected = f"MerchantMaster/{rel}"
            if expected not in entry_names:
                violations.append(f"{expected}:1: missing_toc_lua_file")

    for hit in glyph_hits:
        violations.append(f"{hit}: disallowed_lua_glyph")

    if release_json_path is not None:
        violations.extend(_validate_release_json(release_json_path, zip_path.name))

    stats = {
        "files": len(entry_names),
        "lua_checked": lua_checked,
        "bad_glyphs": len(glyph_hits),
        "raw_bytes": raw_bytes_total,
        "zip_bytes": zip_path.stat().st_size,
    }
    if violations:
        print(f"ZIP_VERIFY_FAIL zip={zip_path.name} violations={len(violations)}")
        for item in violations:
            print(f"  {item}")
        return 1, stats

    return 0, stats


def collect_release_files(toc_lua: list[Path]) -> list[Path]:
    chosen: set[Path] = set(toc_lua)
    for extra in ALLOWED_ROOT_EXTRAS:
        p = (ROOT / extra).resolve()
        if p.exists():
            chosen.add(p)
    for folder in ALLOWED_STATIC_DIRS:
        base = ROOT / folder
        if not base.exists():
            continue
        for f in base.rglob("*"):
            if f.is_file():
                chosen.add(f.resolve())
    return sorted(chosen, key=lambda p: p.relative_to(ROOT).as_posix().lower())


def verify_release_set(files: list[Path], toc_lua: list[Path]) -> dict[str, int]:
    private_rules = load_private_denylist()
    violations: list[str] = []
    glyph_hits: list[str] = []
    seen = {p.resolve() for p in files}

    for f in files:
        rel = f.relative_to(ROOT)
        rel_posix = rel.as_posix()
        top = rel.parts[0]
        if top in FORBIDDEN_TOP_NAMES or top.startswith("."):
            violations.append(f"{rel_posix}:1: forbidden_dev_file")
            continue
        suffix = f.suffix.lower()
        if rel_posix not in ZIP_ALLOWED_EXACT_NAMES and suffix not in ZIP_ALLOWED_EXTS:
            violations.append(f"{rel_posix}:1: unallowlisted_extension({suffix or 'none'})")
            continue
        if rel_posix in ZIP_ALLOWED_EXACT_NAMES or suffix in ZIP_TEXT_EXTS:
            raw = f.read_bytes()
            text, text_hits = _scan_text_violations(rel_posix, raw, private_rules, require_no_bom=True)
            violations.extend(text_hits)
            if text is not None:
                if rel_posix == "MerchantMaster.toc":
                    violations.extend(_check_toc_rules(rel_posix, text))
                elif suffix == ".lua":
                    glyph_hits.extend(scan_lua_text(rel_posix, text))
        elif suffix == ".tga":
            violations.extend(_check_tga_bytes(rel_posix, f.read_bytes()))
        elif suffix == ".ttf":
            violations.extend(_check_ttf_bytes(rel_posix, f.read_bytes()))

    for req in REQUIRED_ZIP_FILES:
        rel_req = req.split("/", 1)[1]
        if not (ROOT / rel_req).is_file():
            violations.append(f"{rel_req}:1: missing_required_file")

    for lua_path in toc_lua:
        if lua_path.resolve() not in seen:
            violations.append(f"{lua_path.relative_to(ROOT).as_posix()}:1: missing_toc_lua_file")

    for hit in glyph_hits:
        violations.append(f"{hit}: disallowed_lua_glyph")

    if violations:
        raise RuntimeError("Release check failed:\n  " + "\n  ".join(violations[:25]))

    return {
        "files": len(files),
        "toc_lua": len(toc_lua),
        "bad_glyphs": len(glyph_hits),
    }


def cmd_build(args: argparse.Namespace) -> int:
    version, toc_lua = parse_toc()
    files = collect_release_files(toc_lua)
    stats = verify_release_set(files, toc_lua)

    if args.check_only:
        print(
            f"RELEASE_CHECK_OK version={version} files={stats['files']} "
            f"toc_lua={stats['toc_lua']} bad_glyphs={stats['bad_glyphs']}"
        )
        return 0

    safe_ver = "dev" if "@project-version@" in version else version
    out_path = Path(args.out) if args.out else (DIST_DIR / f"MerchantMaster-{safe_ver}.zip")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(out_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for f in files:
            arcname = "MerchantMaster/" + f.relative_to(ROOT).as_posix()
            zf.write(f, arcname)

    rc, zip_stats = verify_zip_archive(out_path)
    if rc != 0:
        return rc

    size_mb = zip_stats["zip_bytes"] / 1048576.0
    print(
        f"RELEASE_ZIP_OK path={out_path} version={safe_ver} files={zip_stats['files']} "
        f"raw_bytes={zip_stats['raw_bytes']} zip_bytes={zip_stats['zip_bytes']} "
        f"zip_mb={size_mb:.2f} bad_glyphs={zip_stats['bad_glyphs']}"
    )
    return 0


def cmd_zip_verify(args: argparse.Namespace) -> int:
    zip_path = Path(args.zip)
    rel_json = Path(args.require_release_json) if args.require_release_json else None
    rc, stats = verify_zip_archive(zip_path, rel_json)
    if rc != 0:
        return rc
    meta_suffix = " flavor=forever interface=16001" if rel_json else ""
    print(
        f"ZIP_VERIFY_OK zip={zip_path.name} files={stats['files']} lua={stats['lua_checked']} "
        f"bad_glyphs={stats['bad_glyphs']} raw_bytes={stats['raw_bytes']} "
        f"zip_bytes={stats['zip_bytes']}{meta_suffix}"
    )
    return 0


def cmd_emit_release_json(args: argparse.Namespace) -> int:
    info = emit_release_json(Path(args.zip), Path(args.out), version_override=args.version)
    print(
        f"RELEASE_JSON_OK path={info['path']} filename={info['filename']} "
        f"version={info['version']} flavor={info['flavor']} interface={info['interface']}"
    )
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Build and verify standalone MerchantMaster releases.")
    sub = parser.add_subparsers(dest="command")

    p_build = sub.add_parser("build", help="Verify and build standalone release zip (default).")
    p_build.add_argument("--out", type=str, default="", help="Optional custom output zip path.")
    p_build.add_argument("--check-only", action="store_true", help="Run gates without writing a zip.")

    sub.add_parser("repo-hygiene", help="Scan tracked/workspace files for secrets, local paths, and denylist terms.")

    p_erj = sub.add_parser("emit-release-json", help="Emit WowUp release.json from a packaged zip.")
    p_erj.add_argument("--zip", required=True, help="Path to packaged zip file.")
    p_erj.add_argument("--out", required=True, help="Output path for release.json.")
    p_erj.add_argument("--version", default="", help="Optional version override when TOC has a placeholder.")

    p_zv = sub.add_parser("zip-verify", help="Validate packaged release zip and optional release.json metadata.")
    p_zv.add_argument("--zip", required=True, help="Path to packaged zip file.")
    p_zv.add_argument("--require-release-json", default="", help="Optional path to BigWigsMods/packager release.json.")
    return parser


def main(argv: list[str] | None = None) -> int:
    raw_args = list(sys.argv[1:] if argv is None else argv)
    if not raw_args or raw_args[0].startswith("-"):
        raw_args = ["build", *raw_args]

    parser = build_parser()
    args = parser.parse_args(raw_args)

    if args.command == "repo-hygiene":
        return run_repo_hygiene()
    if args.command == "emit-release-json":
        return cmd_emit_release_json(args)
    if args.command == "zip-verify":
        return cmd_zip_verify(args)
    return cmd_build(args)


if __name__ == "__main__":
    raise SystemExit(main())
