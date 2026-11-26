"""Generate Data_DisenchantMeta.lua (static item metadata catalog for Disenchant.lua).

Inspects every craftable non-enchant outputItemID in Data_Recipes.lua and builds
a compact Lua 5.1 table `ns.DE_ITEM_META[itemID] = { q, ilvl, c, sc, eq }` so
Disenchant.lua never returns "uncached" for craftable recipes before WoW's
GetItemInfo cache warms up.

Sources (in priority order, pure Python 3.11 stdlib only):
  1. Wago WoW: Forever DB2 CSVs (`Item_<build>.csv` & `ItemSparse_<build>.csv`)
     cached in `%LOCALAPPDATA%\\MerchantMaster\\wago_db2_cache\\`.
  2. Blizzard static catalog cache (`%LOCALAPPDATA%\\MerchantMaster\\static_catalog_cache.json`).
  3. Wowhead Forever / Classic XML cache (`wowhead_missing_items.json`, fetched
     politely only for IDs absent from ItemSparse unless `--offline`).
  4. Explicit verified fallback map for hotfixed Forever items absent from both
     ItemSparse and Wowhead XML (currently 250326 Revealing Draught & 280309
     Serrated Strap).

NEVER reads, prints, or stores credentials or SavedVariables.
"""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import csv
import json
import os
from pathlib import Path
import sys
from typing import Any, Dict, List, Optional, Set, Tuple
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET

TOOLS_DIR = Path(__file__).resolve().parent
MM_ROOT = TOOLS_DIR.parent
if str(MM_ROOT) not in sys.path:
    sys.path.insert(0, str(MM_ROOT))

from tools.audit_catalog_blizzard import (  # noqa: E402
    default_cache_path,
    parse_data_recipes,
)
from tools.enrich_cast_times import (  # noqa: E402
    DEFAULT_BUILD,
    default_cache_dir,
    fetch_or_load_csv,
)

USER_AGENT = "MerchantMaster-DECatalogBuilder/1.0"
DEFAULT_OUTPUT_PATH = MM_ROOT / "Data_DisenchantMeta.lua"
CHUNK_SIZE = 500

# WoW Enum.InventoryType -> GetItemInfo equipLoc string
INVENTORY_TYPE_TO_EQUIPLOC: Dict[int, str] = {
    0: "",
    1: "INVTYPE_HEAD",
    2: "INVTYPE_NECK",
    3: "INVTYPE_SHOULDER",
    4: "INVTYPE_BODY",
    5: "INVTYPE_CHEST",
    6: "INVTYPE_WAIST",
    7: "INVTYPE_LEGS",
    8: "INVTYPE_FEET",
    9: "INVTYPE_WRIST",
    10: "INVTYPE_HAND",
    11: "INVTYPE_FINGER",
    12: "INVTYPE_TRINKET",
    13: "INVTYPE_WEAPON",
    14: "INVTYPE_SHIELD",
    15: "INVTYPE_RANGED",
    16: "INVTYPE_CLOAK",
    17: "INVTYPE_2HWEAPON",
    18: "INVTYPE_BAG",
    19: "INVTYPE_TABARD",
    20: "INVTYPE_ROBE",
    21: "INVTYPE_WEAPONMAINHAND",
    22: "INVTYPE_WEAPONOFFHAND",
    23: "INVTYPE_HOLDABLE",
    24: "INVTYPE_AMMO",
    25: "INVTYPE_THROWN",
    26: "INVTYPE_RANGEDRIGHT",
    27: "INVTYPE_QUIVER",
    28: "INVTYPE_RELIC",
}

QUALITY_NAME_TO_ID: Dict[str, int] = {
    "POOR": 0,
    "COMMON": 1,
    "UNCOMMON": 2,
    "RARE": 3,
    "EPIC": 4,
    "LEGENDARY": 5,
    "ARTIFACT": 6,
    "HEIRLOOM": 7,
}

# Verified fallbacks for items present in Item.csv (exact c, sc, eq) but absent
# from both client ItemSparse DB2 and Wowhead XML:
# - 250326: Revealing Draught (Alchemy 205 consumable elixir, c=0 sc=2 eq="")
# - 280309: Serrated Strap (Engineering 175 cloth waist; sibling of 280306-280308
#   Whimsical Waistwrap / Gizmo Girdle / Clanking Cord, all Q=2 ilvl=35)
VERIFIED_SPARSE_OVERRIDES: Dict[int, Tuple[int, int]] = {
    250326: (1, 41),
    280309: (2, 35),
}


def load_wago_item_tables(
    build: str, cache_dir: Path, refresh: bool = False, offline: bool = False
) -> Tuple[Dict[int, Tuple[int, int, int]], Dict[int, Tuple[int, int, int]]]:
    """Load Item (classID, subclassID, invType) and ItemSparse (q, ilvl, flags0)."""
    item_csv = cache_dir / f"Item_{build}.csv"
    sparse_csv = cache_dir / f"ItemSparse_{build}.csv"

    if offline:
        if not item_csv.exists() or not sparse_csv.exists():
            raise FileNotFoundError(
                f"Offline mode requested but DB2 CSVs missing in {cache_dir}"
            )
        item_text = item_csv.read_text(encoding="utf-8-sig")
        sparse_text = sparse_csv.read_text(encoding="utf-8-sig")
    else:
        item_text = fetch_or_load_csv("Item", build, cache_dir, refresh=refresh)
        sparse_text = fetch_or_load_csv("ItemSparse", build, cache_dir, refresh=refresh)

    items_db2: Dict[int, Tuple[int, int, int]] = {}
    for row in csv.DictReader(item_text.splitlines()):
        try:
            iid = int(row["ID"])
            items_db2[iid] = (
                int(row["ClassID"]),
                int(row["SubclassID"]),
                int(row["InventoryType"]),
            )
        except (KeyError, ValueError):
            continue

    sparse_db2: Dict[int, Tuple[int, int, int]] = {}
    for row in csv.DictReader(sparse_text.splitlines()):
        try:
            iid = int(row["ID"])
            q = int(row.get("OverallQualityID") or 0)
            ilvl = int(row.get("ItemLevel") or 0)
            f0 = int(row.get("Flags_0") or 0)
            sparse_db2[iid] = (q, ilvl, f0)
        except (KeyError, ValueError):
            continue

    return items_db2, sparse_db2


def load_static_catalog_items(cache_path: Path) -> Dict[int, Dict[str, Any]]:
    if not cache_path.exists():
        return {}
    raw = json.loads(cache_path.read_text(encoding="utf-8"))
    items = raw.get("items") if isinstance(raw, dict) else {}
    out: Dict[int, Dict[str, Any]] = {}
    if isinstance(items, dict):
        for k, v in items.items():
            if not isinstance(v, dict) or v.get("_not_found"):
                continue
            try:
                out[int(k)] = v
            except ValueError:
                continue
    return out


def fetch_wowhead_item_xml(item_id: int) -> Optional[Dict[str, Any]]:
    for prefix in ("forever", "classic"):
        url = f"https://www.wowhead.com/{prefix}/item={item_id}&xml"
        req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        try:
            with urllib.request.urlopen(req, timeout=10.0) as resp:
                raw = resp.read().decode("utf-8", errors="replace")
            root = ET.fromstring(raw)
            it = root.find("item")
            if it is None:
                continue
            q_el = it.find("quality")
            lvl_el = it.find("level")
            nm_el = it.find("name")
            tip_el = it.find("htmlTooltip")
            q = int(q_el.attrib.get("id", "0")) if q_el is not None else 0
            ilvl = int(lvl_el.text or "0") if (lvl_el is not None and lvl_el.text) else 0
            nm = nm_el.text if (nm_el is not None and nm_el.text) else ""
            tip = tip_el.text if (tip_el is not None and tip_el.text) else ""
            return {
                "source": prefix,
                "name": nm,
                "q": q,
                "ilvl": ilvl,
                "no_de": "cannot be disenchanted" in tip.lower(),
            }
        except (urllib.error.URLError, ET.ParseError, ValueError, TimeoutError):
            continue
    return None


def resolve_wowhead_missing(
    missing_ids: List[int],
    cache_file: Path,
    offline: bool = False,
    refresh: bool = False,
) -> Dict[int, Dict[str, Any]]:
    cached: Dict[str, Dict[str, Any]] = {}
    if cache_file.exists() and not refresh:
        try:
            data = json.loads(cache_file.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                cached = data
        except (OSError, json.JSONDecodeError):
            cached = {}

    to_fetch = [iid for iid in missing_ids if str(iid) not in cached]
    if to_fetch and not offline:
        with ThreadPoolExecutor(max_workers=8) as ex:
            futs = {ex.submit(fetch_wowhead_item_xml, iid): iid for iid in to_fetch}
            for fut in as_completed(futs):
                iid = futs[fut]
                res = fut.result()
                if res is not None:
                    cached[str(iid)] = res
        cache_file.parent.mkdir(parents=True, exist_ok=True)
        tmp = cache_file.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(cached, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        os.replace(tmp, cache_file)

    out: Dict[int, Dict[str, Any]] = {}
    for k, v in cached.items():
        try:
            out[int(k)] = v
        except ValueError:
            continue
    return out


def render_lua_catalog(
    entries: List[Tuple[int, int, int, int, int, str]],
    build: str,
    total_recipes: int,
    non_enchant_recipes: int,
) -> str:
    lines: List[str] = [
        "-- MerchantMaster: Static Craftable Item Metadata Catalog for Disenchanting",
        f"-- Auto-generated by tools/build_de_catalog.py (WoW: Forever DB2 build {build})",
        f"-- Recipes inspected: {total_recipes} total, {non_enchant_recipes} non-enchant item-producing, {len(entries)} unique output items.",
        "-- Schema: ns.DE_ITEM_META[itemID] = { q = quality, ilvl = itemLevel, c = classID, sc = subclassID, eq = equipLoc }",
        "",
        "local _, ns = ...",
        "",
        "local meta = {}",
        "ns.DE_ITEM_META = meta",
        "",
        "local function M(id, q, ilvl, c, sc, eq)",
        "\tmeta[id] = { q = q, ilvl = ilvl, c = c, sc = sc, eq = eq }",
        "end",
        "",
    ]

    for start in range(0, len(entries), CHUNK_SIZE):
        chunk = entries[start : start + CHUNK_SIZE]
        lines.append("do (function()")
        for iid, q, ilvl, c, sc, eq in chunk:
            lines.append(f'\tM({iid}, {q}, {ilvl}, {c}, {sc}, "{eq}")')
        lines.append("end)() end")
        lines.append("")

    return "\n".join(lines)


def build_catalog(
    build: str = DEFAULT_BUILD,
    output_path: Path = DEFAULT_OUTPUT_PATH,
    offline: bool = False,
    refresh: bool = False,
    write: bool = True,
) -> Dict[str, Any]:
    cat = parse_data_recipes(MM_ROOT / "Data_Recipes.lua")
    runtime_recipes = [r for r in cat.recipes if not r.mp_only]
    total_recipes = len(runtime_recipes)
    non_enchant_recipes = [
        r for r in runtime_recipes if (not r.is_enchant) and r.output_item_id and r.output_item_id > 0
    ]
    unique_outputs = sorted({r.output_item_id for r in non_enchant_recipes})

    cache_dir = default_cache_dir()
    items_db2, sparse_db2 = load_wago_item_tables(
        build=build, cache_dir=cache_dir, refresh=refresh, offline=offline
    )
    static_items = load_static_catalog_items(default_cache_path())

    need_wh = [
        iid for iid in unique_outputs if (iid not in sparse_db2) and (iid not in static_items)
    ]
    wh_cache_file = cache_dir / "wowhead_missing_items.json"
    wh_items = resolve_wowhead_missing(
        need_wh, cache_file=wh_cache_file, offline=offline, refresh=refresh
    )

    entries: List[Tuple[int, int, int, int, int, str]] = []
    unresolved: List[int] = []
    no_de_flagged: List[Tuple[int, str]] = []
    source_counts = {"db2": 0, "static_cache": 0, "wowhead_xml": 0, "override": 0}

    for iid in unique_outputs:
        it = items_db2.get(iid)
        if it is None:
            unresolved.append(iid)
            continue
        c, sc, inv = it
        eq = INVENTORY_TYPE_TO_EQUIPLOC.get(inv, "")

        sp = sparse_db2.get(iid)
        if sp is not None:
            q, ilvl, f0 = sp
            source_counts["db2"] += 1
            if (f0 & 0x8000) and c in (2, 4) and q in (2, 3, 4):
                nm = cat.items[iid].name if iid in cat.items else f"Item #{iid}"
                no_de_flagged.append((iid, nm))
        elif iid in static_items:
            ci = static_items[iid]
            q = QUALITY_NAME_TO_ID.get(str(ci.get("quality") or "").upper(), 0)
            ilvl = int(ci.get("level") or 0)
            source_counts["static_cache"] += 1
        elif iid in wh_items:
            wi = wh_items[iid]
            q = int(wi.get("q") or 0)
            ilvl = int(wi.get("ilvl") or 0)
            source_counts["wowhead_xml"] += 1
        elif iid in VERIFIED_SPARSE_OVERRIDES:
            q, ilvl = VERIFIED_SPARSE_OVERRIDES[iid]
            source_counts["override"] += 1
        else:
            unresolved.append(iid)
            continue

        entries.append((iid, q, ilvl, c, sc, eq))

    if unresolved:
        raise RuntimeError(f"Unresolved craftable outputItemIDs ({len(unresolved)}): {unresolved[:20]}")

    lua_text = render_lua_catalog(
        entries=entries,
        build=build,
        total_recipes=total_recipes,
        non_enchant_recipes=len(non_enchant_recipes),
    )

    if write:
        tmp = output_path.with_suffix(".lua.tmp")
        tmp.write_text(lua_text, encoding="utf-8", newline="\n")
        os.replace(tmp, output_path)

    return {
        "build": build,
        "output_path": str(output_path),
        "total_recipes": total_recipes,
        "non_enchant_recipes": len(non_enchant_recipes),
        "unique_outputs": len(unique_outputs),
        "emitted": len(entries),
        "unresolved": len(unresolved),
        "sources": source_counts,
        "no_de_flagged": no_de_flagged,
        "bytes": len(lua_text.encode("utf-8")),
    }


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Build MerchantMaster Data_DisenchantMeta.lua")
    parser.add_argument("--build", default=DEFAULT_BUILD, help=f"Wago DB2 build (default {DEFAULT_BUILD})")
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT_PATH), help="Output Lua file path")
    parser.add_argument("--offline", action="store_true", help="Use local caches only (no network requests)")
    parser.add_argument("--refresh", action="store_true", help="Re-fetch Wago DB2 and Wowhead caches")
    parser.add_argument("--check", action="store_true", help="Verify generation without writing output file")
    args = parser.parse_args(argv)

    summary = build_catalog(
        build=args.build,
        output_path=Path(args.output),
        offline=args.offline,
        refresh=args.refresh,
        write=not args.check,
    )
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
