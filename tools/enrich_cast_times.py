"""Enrich Data_Recipes.lua with authoritative WoW: Forever recipe cast times (ms).

Fetches (and caches) official Wago DB2 CSV exports for the target WoW: Forever
build (`SpellCastTimes` and `SpellMisc`), resolves exact base cast times in
milliseconds for every `R({...})` recipe entry by `s=` (with `mpS=` fallback),
and idempotently inserts or updates `ct=<ms>` inside each matching `R({...})`
line in `Data_Recipes.lua`.

Pure Python 3.11 stdlib only. Zero third-party dependencies.
"""

from __future__ import annotations

import argparse
from collections import Counter
import csv
import io
import os
from pathlib import Path
import statistics
import sys
from typing import Any, Dict, List, Optional, Tuple
import urllib.error
import urllib.request

DEFAULT_BUILD = "1.60.1.71037"
WAGO_CSV_URL = "https://wago.tools/db2/{table}/csv?build={build}"
USER_AGENT = "MerchantMaster-CastTimeEnricher/1.0 (+https://wago.tools)"

TOOLS_DIR = Path(__file__).resolve().parent
MM_ROOT = TOOLS_DIR.parent
DEFAULT_CATALOG_PATH = MM_ROOT / "Data_Recipes.lua"


def default_cache_dir() -> Path:
    local_app_data = os.environ.get("LOCALAPPDATA", "").strip()
    base = Path(local_app_data) if local_app_data else Path.home()
    return base / "MerchantMaster" / "wago_db2_cache"


def fetch_or_load_csv(
    table: str,
    build: str,
    cache_dir: Path,
    refresh: bool = False,
    timeout: float = 60.0,
) -> str:
    cache_dir.mkdir(parents=True, exist_ok=True)
    safe_build = "".join(ch if (ch.isalnum() or ch in "._-") else "_" for ch in build)
    cache_file = cache_dir / f"{table}_{safe_build}.csv"
    if cache_file.exists() and not refresh:
        return cache_file.read_text(encoding="utf-8-sig")

    url = WAGO_CSV_URL.format(table=table, build=build)
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw_bytes = resp.read()
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Failed to fetch {url}: {exc}") from exc

    text = raw_bytes.decode("utf-8-sig")
    tmp_file = cache_file.with_suffix(".csv.tmp")
    tmp_file.write_text(text, encoding="utf-8", newline="")
    tmp_file.replace(cache_file)
    return text


def parse_spell_cast_times(csv_text: str) -> Dict[int, int]:
    """Return mapping of SpellCastTimes.ID -> Base cast time in ms (>= 0)."""
    out: Dict[int, int] = {}
    reader = csv.DictReader(io.StringIO(csv_text))
    for row in reader:
        raw_id = row.get("ID")
        raw_base = row.get("Base")
        if raw_id is None or raw_base is None:
            continue
        try:
            ct_id = int(raw_id)
            base_ms = int(float(raw_base))
        except ValueError:
            continue
        if base_ms >= 0:
            out[ct_id] = base_ms
    return out


def parse_spell_misc(csv_text: str) -> Dict[int, Tuple[int, int]]:
    """Return mapping of SpellID -> (CastingTimeIndex, DifficultyID).

    When multiple rows exist for the same SpellID, prefers DifficultyID == 0.
    """
    out: Dict[int, Tuple[int, int]] = {}
    reader = csv.DictReader(io.StringIO(csv_text))
    for row in reader:
        raw_spell = row.get("SpellID")
        raw_ct_idx = row.get("CastingTimeIndex")
        raw_diff = row.get("DifficultyID", "0")
        if raw_spell is None or raw_ct_idx is None:
            continue
        try:
            spell_id = int(raw_spell)
            ct_idx = int(raw_ct_idx)
            diff_id = int(raw_diff) if raw_diff != "" else 0
        except ValueError:
            continue
        prev = out.get(spell_id)
        if prev is None:
            out[spell_id] = (ct_idx, diff_id)
        elif prev[1] != 0 and diff_id == 0:
            out[spell_id] = (ct_idx, diff_id)
    return out


def parse_top_level_recipe_fields(line: str) -> Optional[Tuple[Dict[str, Tuple[str, int, int]], int]]:
    """Parse top-level key=value fields of an `R({...})` line.

    Returns `(fields, close_brace_pos)` where `fields[key] = (raw_value, val_start, val_end)`,
    and `close_brace_pos` is the index of the matching `}` in `R({...})`.
    Returns None if the line is not an `R({...})` recipe call.
    """
    stripped = line.lstrip(" \t")
    if not stripped.startswith("R({"):
        return None
    open_brace = line.find("R({") + 2
    n = len(line)
    pos = open_brace + 1
    fields: Dict[str, Tuple[str, int, int]] = {}

    def skip_ws(i: int) -> int:
        while i < n and line[i] in " \t":
            i += 1
        return i

    def scan_string(i: int) -> int:
        quote = line[i]
        i += 1
        while i < n:
            ch = line[i]
            if ch == "\\":
                i += 2
                continue
            if ch == quote:
                return i + 1
            i += 1
        return n

    def scan_nested_table(i: int) -> int:
        depth = 1
        i += 1
        while i < n and depth > 0:
            ch = line[i]
            if ch in ('"', "'"):
                i = scan_string(i)
            elif ch == "{":
                depth += 1
                i += 1
            elif ch == "}":
                depth -= 1
                i += 1
            else:
                i += 1
        return i

    while pos < n:
        pos = skip_ws(pos)
        if pos >= n:
            return None
        if line[pos] == "}":
            return fields, pos

        # Key: identifier or [expr]
        if line[pos] == "[":
            k_start = pos
            pos += 1
            while pos < n and line[pos] != "]":
                if line[pos] in ('"', "'"):
                    pos = scan_string(pos)
                else:
                    pos += 1
            pos += 1
            key = line[k_start:pos]
        else:
            k_start = pos
            while pos < n and (line[pos].isalnum() or line[pos] == "_"):
                pos += 1
            key = line[k_start:pos]
        pos = skip_ws(pos)
        if pos >= n or line[pos] != "=":
            return None
        pos += 1
        pos = skip_ws(pos)
        if pos >= n:
            return None

        val_start = pos
        ch = line[pos]
        if ch in ('"', "'"):
            pos = scan_string(pos)
        elif ch == "{":
            pos = scan_nested_table(pos)
        else:
            while pos < n and line[pos] not in ",}":
                pos += 1
            while pos > val_start and line[pos - 1] in " \t":
                pos -= 1
        val_end = pos
        fields[key] = (line[val_start:val_end], val_start, val_end)

        pos = skip_ws(pos)
        if pos < n and line[pos] in (",", ";"):
            pos += 1

    return None


def _parse_int_literal(raw: Optional[str]) -> Optional[int]:
    if raw is None:
        return None
    raw = raw.strip()
    if not raw:
        return None
    try:
        return int(raw)
    except ValueError:
        return None


def _strip_quotes(raw: Optional[str]) -> str:
    if not raw:
        return ""
    s = raw.strip()
    if len(s) >= 2 and s[0] == s[-1] and s[0] in ('"', "'"):
        return s[1:-1]
    return s


def enrich_catalog(
    catalog_path: Path,
    spell_misc: Dict[int, Tuple[int, int]],
    cast_times: Dict[int, int],
    write: bool = False,
) -> Dict[str, Any]:
    raw_bytes = catalog_path.read_bytes()
    if raw_bytes.startswith(b"\xef\xbb\xbf"):
        raw_bytes = raw_bytes[3:]
    text = raw_bytes.decode("utf-8")
    line_ending = "\r\n" if "\r\n" in text else "\n"
    has_trailing_nl = text.endswith("\n")
    lines = text.splitlines()

    total_recipes = 0
    matched = 0
    changed_lines = 0
    matched_values: List[int] = []
    unmatched_reasons: Counter[str] = Counter()
    unmatched_samples: List[Dict[str, Any]] = []
    new_lines: List[str] = []

    for line_no, line in enumerate(lines, 1):
        parsed = parse_top_level_recipe_fields(line)
        if parsed is None:
            new_lines.append(line)
            continue

        total_recipes += 1
        fields, close_brace = parsed
        s_id = _parse_int_literal(fields["s"][0]) if "s" in fields else None
        mp_s_id = _parse_int_literal(fields["mpS"][0]) if "mpS" in fields else None
        src_val = _strip_quotes(fields["src"][0]) if "src" in fields else ""
        name_val = _strip_quotes(fields["n"][0]) if "n" in fields else ""
        pk_val = _strip_quotes(fields["pk"][0]) if "pk" in fields else ""

        resolved_ms: Optional[int] = None
        fail_reason: Optional[str] = None
        candidates = [sid for sid in (s_id, mp_s_id) if sid is not None and sid > 0]

        if not candidates:
            fail_reason = "no_spell_id"
        else:
            for sid in candidates:
                misc_entry = spell_misc.get(sid)
                if misc_entry is None:
                    continue
                ct_idx, _diff = misc_entry
                if ct_idx in cast_times:
                    resolved_ms = cast_times[ct_idx]
                    break
                if ct_idx == 0:
                    # CastingTimeIndex 0 in DB2 means 0ms (instant)
                    resolved_ms = 0
                    break
                fail_reason = f"missing_cast_time_index:{ct_idx}"
            if resolved_ms is None and fail_reason is None:
                if src_val == "gather":
                    fail_reason = "synthetic_gather_entry"
                else:
                    fail_reason = "spell_not_in_spellmisc"

        if resolved_ms is not None and resolved_ms >= 0:
            matched += 1
            matched_values.append(resolved_ms)
            if "ct" in fields:
                _old_raw, v_start, v_end = fields["ct"]
                updated = f"{line[:v_start]}{resolved_ms}{line[v_end:]}"
            else:
                updated = f"{line[:close_brace]},ct={resolved_ms}{line[close_brace:]}"
            if updated != line:
                changed_lines += 1
            new_lines.append(updated)
        else:
            reason = fail_reason or "unknown"
            unmatched_reasons[reason] += 1
            if len(unmatched_samples) < 25:
                unmatched_samples.append(
                    {
                        "line": line_no,
                        "s": s_id,
                        "mpS": mp_s_id,
                        "pk": pk_val,
                        "n": name_val,
                        "src": src_val,
                        "reason": reason,
                    }
                )
            new_lines.append(line)

    if write and changed_lines > 0:
        out_text = line_ending.join(new_lines)
        if has_trailing_nl:
            out_text += line_ending
        out_bytes = out_text.encode("utf-8")
        tmp_path = catalog_path.with_suffix(".lua.tmp")
        tmp_path.write_bytes(out_bytes)
        tmp_path.replace(catalog_path)

    stats: Dict[str, Any] = {
        "total_recipes": total_recipes,
        "matched": matched,
        "unmatched": total_recipes - matched,
        "changed_lines": changed_lines,
        "wrote": bool(write and changed_lines > 0),
        "min_ms": min(matched_values) if matched_values else None,
        "median_ms": int(statistics.median(matched_values)) if matched_values else None,
        "max_ms": max(matched_values) if matched_values else None,
        "value_hist": Counter(matched_values).most_common(12),
        "unmatched_reasons": dict(unmatched_reasons),
        "unmatched_samples": unmatched_samples,
    }
    return stats


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(description="Enrich Data_Recipes.lua with Wago DB2 recipe cast times.")
    ap.add_argument("--build", default=DEFAULT_BUILD, help=f"Wago DB2 build string (default: {DEFAULT_BUILD})")
    ap.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG_PATH, help="Path to Data_Recipes.lua")
    ap.add_argument("--cache-dir", type=Path, default=default_cache_dir(), help="Local CSV cache directory")
    ap.add_argument("--refresh", action="store_true", help="Re-download CSVs from wago.tools ignoring cache")
    ap.add_argument("--write", action="store_true", help="Write enriched ct=<ms> fields into Data_Recipes.lua")
    args = ap.parse_args(argv)

    cast_csv = fetch_or_load_csv("SpellCastTimes", args.build, args.cache_dir, refresh=args.refresh)
    misc_csv = fetch_or_load_csv("SpellMisc", args.build, args.cache_dir, refresh=args.refresh)

    cast_times = parse_spell_cast_times(cast_csv)
    spell_misc = parse_spell_misc(misc_csv)

    stats = enrich_catalog(args.catalog, spell_misc, cast_times, write=args.write)

    mode = "WRITE" if args.write else "DRY-RUN"
    print(
        f"[{mode}] build={args.build} "
        f"SpellCastTimes={len(cast_times)} SpellMisc={len(spell_misc)}"
    )
    print(
        f"COVERAGE: matched={stats['matched']}/{stats['total_recipes']} "
        f"unmatched={stats['unmatched']} changed_lines={stats['changed_lines']}"
    )
    print(
        f"CAST_TIME_MS: min={stats['min_ms']} median={stats['median_ms']} max={stats['max_ms']}"
    )
    print("TOP_VALUES_MS:", ", ".join(f"{ms}ms={cnt}" for ms, cnt in stats["value_hist"]))
    if stats["unmatched"] > 0:
        print("UNMATCHED_REASONS:", stats["unmatched_reasons"])
        for sample in stats["unmatched_samples"]:
            print(
                f"  - L{sample['line']} s={sample['s']} mpS={sample['mpS']} "
                f"pk={sample['pk']} src={sample['src']!r} n={sample['n']!r} ({sample['reason']})"
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
