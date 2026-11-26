"""Canonical verification runner for the standalone MerchantMaster addon.

Supports targeted slices (--only a,b) and bounded parallel execution (-j N),
keeping timing-sensitive performance/frame-budget suites serial at the end.
"""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import argparse
import os
import shutil
import subprocess
import sys
import time


def find_lua() -> str:
    env_bin = os.environ.get("LUA_BIN", "").strip()
    if env_bin:
        return env_bin
    for name in ("lua5.1", "lua51", "lua"):
        found = shutil.which(name)
        if found:
            return found
    for candidate in sorted(Path.home().glob(".vscode/extensions/actboy168.lua-debug-*/runtime/**/lua51/lua.exe")):
        if candidate.is_file():
            return str(candidate)
    return "lua5.1"


PYTHON = sys.executable
LUA = find_lua()
TOOLS = Path(__file__).resolve().parent
MM = TOOLS.parent
TESTS = MM / "tests"
LOGS = TESTS / "logs"

SERIAL_TIMING_SUITES = {
    "wp3_superlist_model",
    "wp6_superlist_ui",
    "wp12_accounting_ui",
    "all_items",
    "perf_bench",
    "perf_slice_b",
    "professor_formulas",
}

SUMMARY_TAGS = (
    "FILES_CHECKED=",
    "REPO_HYGIENE_OK",
    "Ran ",
    "OK",
    "PASS:",
    "PASS ",
    "PASS LIVE",
    "AUCTION_HOUSE_TESTS:",
    "CONSOLE_TESTS:",
    "STANDALONE_GATES:",
    "STANDALONE_FALLBACKS:",
    "WP1 ",
    "WP2 ",
    "WP3 ",
    "WP4 ",
    "WP5 ",
    "WP6 ",
    "WP7 ",
    "WP8 ",
    "MEASURE ",
    "Analytics suite:",
    "Accounting ",
    "store assertions",
    "capture assertions",
    "model assertions",
    "OPEN_MS=",
    "IDLE_5S_MS=",
    "TAB_TOUR_14_MS=",
    "Fable Apple HIG suite:",
    "Warcraft skins suite:",
)


def run_one(name: str, cmd: list[str], cwd: Path, creationflags: int):
    t0 = time.perf_counter()
    try:
        proc = subprocess.run(
            cmd,
            cwd=str(cwd),
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            creationflags=creationflags,
        )
        rc = proc.returncode
        combined = ((proc.stdout or "") + ("\n" + proc.stderr if proc.stderr else "")).strip()
    except FileNotFoundError as exc:
        rc = 127
        combined = f"Executable not found for suite {name}: {cmd[0]} ({exc})"
    dt_ms = (time.perf_counter() - t0) * 1000.0
    LOGS.mkdir(parents=True, exist_ok=True)
    (LOGS / f"all_checks_{name}.log").write_text(combined + "\n", encoding="utf-8")
    return name, rc, dt_ms, combined


def print_result(name: str, rc: int, dt_ms: float, combined: str) -> None:
    print(f"=== {name} EXIT={rc} ({dt_ms:.1f} ms) ===", flush=True)
    lines = combined.splitlines()
    for line in lines:
        if any(tag in line for tag in SUMMARY_TAGS) or (lines and line == lines[-1]):
            print("  " + line, flush=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--skip-migrate-unit", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--only", default="", help="Comma-separated subset of suite names to run")
    parser.add_argument("-j", "--jobs", type=int, default=8, help="Max parallel worker threads for non-timing suites")
    args = parser.parse_args()

    suites = [
        ("glyphs", [PYTHON, str(TOOLS / "check_glyphs.py")], TOOLS),
        ("repo_hygiene", [PYTHON, str(TOOLS / "build_release_zip.py"), "repo-hygiene"], MM),
        ("wp1_lifecycle", [LUA, str(TESTS / "test_wp1.lua")], TESTS),
        ("host_suite", [LUA, str(TESTS / "test_merchantmaster.lua")], TESTS),
        ("wp2_boundaries", [LUA, str(TESTS / "test_wp2.lua")], TESTS),
        ("wp3_superlist_model", [LUA, str(TESTS / "test_superlist_model.lua")], TESTS),
        ("wp4_seller_stats", [LUA, str(TESTS / "test_seller_stats.lua")], TESTS),
        ("wp5_window", [LUA, str(TESTS / "test_window.lua")], TESTS),
        ("wp5_ah_refresh", [LUA, str(TESTS / "test_ah_refresh.lua")], TESTS),
        ("wp5_host_window", [LUA, str(TESTS / "wp6_window_host.lua")], TESTS),
        ("wp6_superlist_ui", [LUA, str(TESTS / "test_superlist_ui.lua")], TESTS),
        ("r3_A_model", [LUA, str(TESTS / "test_r3_A_model.lua")], TESTS),
        ("r3_A_stats_window", [LUA, str(TESTS / "test_r3_A_stats_window.lua")], TESTS),
        ("r3_B_favor", [LUA, str(TESTS / "test_r3_B_favor.lua")], TESTS),
        ("wp6_integration", [LUA, str(TESTS / "test_wp6_integration.lua")], TESTS),
        ("wp7_trainer_stats", [LUA, str(TESTS / "test_trainer_stats.lua")], TESTS),
        ("wp9_accounting_store", [LUA, str(TESTS / "test_accounting_store.lua")], TESTS),
        ("wp10_accounting_capture", [LUA, str(TESTS / "test_accounting_capture.lua")], TESTS),
        ("wp11_accounting_model", [LUA, str(TESTS / "test_accounting_model.lua")], TESTS),
        ("wp12_accounting_ui", [LUA, str(TESTS / "test_accounting_ui.lua")], TESTS),
        ("perf_bench", [LUA, str(TESTS / "bench_mm_perf.lua")], TESTS),
        ("perf_slice_b", [LUA, str(TESTS / "test_perf_slice_b.lua")], TESTS),
        ("r4_fixes", [LUA, str(TESTS / "test_r4_fixes.lua")], TESTS),
        ("crafting_order", [LUA, str(TESTS / "test_crafting_order.lua")], TESTS),
        ("superlist_priority_warm", [LUA, str(TESTS / "test_superlist_priority_warm.lua")], TESTS),
        ("unified_shopping_list", [LUA, str(TESTS / "test_unified_shopping_list.lua")], TESTS),
        ("fable_apple_hig", [LUA, str(TESTS / "test_fable_apple_hig.lua")], TESTS),
        ("warcraft_skins", [LUA, str(TESTS / "test_warcraft_skins.lua")], TESTS),
        ("professor_ux", [LUA, str(TESTS / "test_professor_ux.lua")], TESTS),
        ("professor_formulas", [LUA, str(TESTS / "test_professor_formulas.lua")], TESTS),
        ("cart_buyer", [LUA, str(TESTS / "test_cart_buyer.lua")], TESTS),
        ("bugfixes_20261120", [LUA, str(TESTS / "test_bugfixes_20261120.lua")], TESTS),
        ("de_and_pricing", [LUA, str(TESTS / "test_de_and_pricing.lua")], TESTS),
        ("snapshot_pricing", [LUA, str(TESTS / "test_snapshot_pricing.lua")], TESTS),
        ("heatmap_widgets", [LUA, str(TESTS / "test_heatmap_widgets.lua")], TESTS),
        ("deep_analysis_ui", [LUA, str(TESTS / "test_deep_analysis_ui.lua")], TESTS),
        ("snapshot_ui_status", [LUA, str(TESTS / "test_snapshot_ui_status.lua")], TESTS),
        ("all_items", [LUA, str(TESTS / "test_all_items.lua")], TESTS),
        ("vendor_crafter", [LUA, str(TESTS / "test_vendor_crafter.lua")], TESTS),
        ("disenchant_crafter", [LUA, str(TESTS / "test_disenchant_crafter.lua")], TESTS),
        ("sniper", [LUA, str(TESTS / "test_sniper.lua")], TESTS),
        ("standalone_gates", [LUA, str(TESTS / "test_standalone_gates.lua")], TESTS),
        ("standalone_fallbacks", [LUA, str(TESTS / "test_standalone_fallbacks.lua")], TESTS),
        ("mail_and_logging", [LUA, str(TESTS / "test_mail_and_logging.lua")], TESTS),
        ("console", [LUA, str(TESTS / "test_console.lua")], TESTS),
        ("catalog_blizzard_audit", [PYTHON, "-m", "unittest", str(TOOLS / "test_audit_catalog_blizzard.py"), "-v"], MM),
    ]

    if args.only.strip():
        want = {s.strip() for s in args.only.split(",") if s.strip()}
        known = {n for n, _, _ in suites}
        unknown = sorted(want - known)
        if unknown:
            print(f"UNKNOWN_SUITES={','.join(unknown)}", flush=True)
            return 2
        suites = [s for s in suites if s[0] in want]

    parallel = [s for s in suites if s[0] not in SERIAL_TIMING_SUITES]
    serial = [s for s in suites if s[0] in SERIAL_TIMING_SUITES]

    LOGS.mkdir(parents=True, exist_ok=True)
    t_start = time.perf_counter()
    results = []
    if parallel:
        workers = max(1, min(args.jobs, len(parallel)))
        if workers == 1:
            for name, cmd, cwd in parallel:
                res = run_one(name, cmd, cwd, 0)
                print_result(*res)
                if res[1] != 0:
                    print("FAILURE OUTPUT:\n" + res[3][-3000:], flush=True)
                    return res[1]
                results.append(res)
        else:
            with ThreadPoolExecutor(max_workers=workers) as pool:
                fut_map = {pool.submit(run_one, name, cmd, cwd, 0): name for name, cmd, cwd in parallel}
                by_name = {}
                for fut in as_completed(fut_map):
                    res = fut.result()
                    by_name[res[0]] = res
                    if res[1] != 0:
                        print_result(*res)
                        print("FAILURE OUTPUT:\n" + res[3][-3000:], flush=True)
                        for f in fut_map:
                            f.cancel()
                        return res[1]
                for name, _, _ in parallel:
                    print_result(*by_name[name])
                    results.append(by_name[name])

    hi_flags = getattr(subprocess, "HIGH_PRIORITY_CLASS", 0) if sys.platform == "win32" else 0
    for name, cmd, cwd in serial:
        res = run_one(name, cmd, cwd, hi_flags)
        print_result(*res)
        if res[1] != 0:
            print("FAILURE OUTPUT:\n" + res[3][-3000:], flush=True)
            return res[1]
        results.append(res)

    total_s = time.perf_counter() - t_start
    print(f"ALL_SUITES_PASSED count={len(results)} skipped=0 elapsed_s={total_s:.2f}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
