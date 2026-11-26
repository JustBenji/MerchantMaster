#!/usr/bin/env python3
"""
Headless Lua Frame-Graph -> Chrome @2x Screenshot Renderer for MerchantMaster.

Reads JSON scene trees emitted by tools/lua_frame_dump.lua, converts referenced
.tga textures (including slice UVs and vertexColor tinting) into base64
RGBA PNG data URIs using pure Python stdlib (no PIL/numpy), builds self-contained
1440x900 HTML files over the exact Azeroth ambient backdrop from Fable 5.2, and
captures 2880x1800 @2x PNGs via headless Chrome.
"""

from __future__ import annotations

import argparse
import base64
import html
from functools import lru_cache
import json
import math
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path
from typing import Dict, List, Optional, Tuple


ADDON_DIR = Path(__file__).resolve().parent.parent
DUMPER_LUA = Path(__file__).resolve().parent / "lua_frame_dump.lua"


def find_lua_exe() -> str:
    env_lua = os.environ.get("LUA_BIN", "").strip()
    if env_lua:
        return env_lua
    for name in ("lua5.1", "lua51", "lua"):
        found = shutil.which(name)
        if found:
            return found
    for cand in sorted(
        Path.home().glob(".vscode/extensions/actboy168.lua-debug-*/runtime/**/lua51/lua.exe"),
        reverse=True,
    ):
        if cand.is_file():
            return str(cand)
    return "lua5.1"


def find_chrome_exe() -> str:
    for env_key in ("MM_CHROME_EXE", "CHROME_BIN"):
        val = os.environ.get(env_key, "").strip()
        if val:
            return val
    for name in ("chrome", "google-chrome", "chromium", "chromium-browser"):
        found = shutil.which(name)
        if found:
            return found
    candidates: List[Path] = []
    for env_dir in ("PROGRAMFILES", "PROGRAMFILES(X86)", "LOCALAPPDATA"):
        base = os.environ.get(env_dir, "").strip()
        if base:
            candidates.append(Path(base) / "Google" / "Chrome" / "Application" / "chrome.exe")
    candidates.append(Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"))
    for cand in candidates:
        if cand.is_file():
            return str(cand)
    return "chrome"


def find_arialn_ttf() -> Optional[Path]:
    env_font = os.environ.get("MM_ARIALN_FONT", "").strip()
    if env_font:
        p = Path(env_font)
        return p if p.is_file() else None
    windir = os.environ.get("WINDIR", "").strip()
    if windir:
        p = Path(windir) / "Fonts" / "ARIALN.TTF"
        if p.is_file():
            return p
    return None


DEFAULT_LUA_EXE = find_lua_exe()
DEFAULT_CHROME_EXE = find_chrome_exe()
DEFAULT_OUT_DIR = os.environ.get("MM_PREVIEW_OUT_DIR", "").strip() or str(ADDON_DIR / "tools" / "dist" / "previews")
SCENES = [
    "overview-dark",
    "overview-light",
    "market-dark",
    "market-light",
    "market-allrecipes-dark",
    "market-allrecipes-light",
    "market-allrecipes-columns-dark",
    "minimized-dark",
    "turnins-dark",
    "turnins-light",
    "leveling-dark",
    "leveling-light",
    "ledger-dark",
    "ledger-light",
    "shopping-dark",
    "shopping-light",
    "overview-scanning-dark",
    "quicklook-dark",
    "quicklook-light",
    "quicklook-24h-expanded-dark",
    "quicklook-24h-expanded-light",
    "writ-quicklook-dark",
    "writ-quicklook-light",
    "crate-quicklook-dark",
    "crate-quicklook-light",
    "monopolies-rep-transmute-dark",
    "prices-standard-dark",
    "prices-no-copper-dark",
    "prices-3modes-rightalign-dark",
    "writs-cd-dark",
    "ah-not-open-dark",
]

# Warcraft-skin sweep emitted by `lua_frame_dump.lua --skins` (rendered with `--skins`).
SKIN_SCENES = [
    "overview-standard-dark",
    "overview-standard-light",
    "overview-human",
    "overview-night_elf",
    "overview-orc",
    "overview-undead",
    "overview-goblin",
    "overview-goblin-bright",
    "options-goblin",
    "market-goblin",
    "leveling-goblin",
    "allrecipes-night_elf",
    "ah-minimap-brand",
    "live-cart-goblin",
    "live-cart-compact-goblin",
    "live-cart-empty-goblin",
    "live-cart-dark",
    "live-cart-light",
    "live-ahbuyer-compact-goblin",
    "live-ahbuyer-extended-goblin",
    "live-ahbuyer-overcap-goblin",
    "live-ahbuyer-filtered-goblin",
    "live-ahbuyer-waiting-goblin",
    "live-ahbuyer-extended-dark",
    "live-ahbuyer-extended-light",
    "flow-vendor-goblin",
    "flow-collect-goblin",
    "flow-craft-goblin",
    "flow-craft-extended-goblin",
]

# Optional external WoW icon PNGs (matched by lower-case basename; configured via MM_WOW_ICON_DIR / --wow-icon-dir).
WOW_ICON_DIR: Optional[Path] = (
    Path(os.environ["MM_WOW_ICON_DIR"]) if os.environ.get("MM_WOW_ICON_DIR") else None
)

# Optional external per-item art for Warcraft-skin previews (configured via MM_SKIN_ICON_DIR / --skin-icon-dir).
SKIN_ICON_DIR: Optional[Path] = (
    Path(os.environ["MM_SKIN_ICON_DIR"]) if os.environ.get("MM_SKIN_ICON_DIR") else None
)
SKIN_ICON_ALIASES = {
    "inv_potion_32": "mongoose", "inv_potion_25": "arcane_elixir",
    "inv_potion_76": "major_mana", "inv_potion_24": "fire_prot",
    "inv_potion_41": "flask_supreme", "inv_potion_40": "brute_force",
    "inv_potion_100": "precision", "inv_potion_83": "rage_potion",
    "inv_misc_herb_dreamfoil": "dreamfoil", "inv_misc_herb_mountainsilversage": "silversage",
    "inv_misc_herb_blacklotus": "black_lotus", "inv_drink_05": "crystal_vial",
    "inv_fabric_linen_01": "linen", "inv_misc_leatherscrap_02": "hide",
    "inv_scroll_05": "writ", "inv_crate_03": "crate",
}

ARIALN_TTF: Optional[Path] = find_arialn_ttf()

# lower-case Interface\Icons basename (no extension) -> file stem inside WOW_ICON_DIR.
ICON_ALIASES: Dict[str, str] = {
    "inv_crate_03": "wow_crate",
    "inv_potion_54": "wow_healing_potion",
    "inv_potion_76": "wow_major_mana",
    "inv_potion_25": "wow_arcane_elixir",
    "inv_potion_32": "wow_mana_potion",
    "inv_potion_41": "wow_flask_blight",
    "inv_potion_80": "wow_shroud_potion",
    "inv_drink_05": "wow_crystal_vial",
    "inv_scroll_03": "wow_scroll_classic",
    "inv_scroll_05": "wow_scroll_arcane",
    "inv_misc_herb_dreamfoil": "wow_herbalism",
    "inv_misc_herb_blacklotus": "wow_herbalism",
    "inv_misc_herb_mountainsilversage": "wow_wild_harvest",
    "inv_misc_herb_18": "wow_wild_harvest",
    "inv_misc_herb_07": "wow_wild_harvest",
    "inv_fabric_linen_01": "wow_linen_cloth",
    "inv_misc_leatherscrap_02": "wow_hide",
    "inv_misc_questionmark": "wow_gold_bag",
}

# Numeric fileIDs the dumper still emits as __fileid:N (profession tabs, bag crates, ...) -> file stem.
FILEID_ALIASES: Dict[str, str] = {
    "236994": "wow_crate",
    "134715": "wow_crystal_vial",
    "134939": "wow_scroll_classic",
    "134187": "wow_herbalism",
    "134830": "wow_mana_potion",
}

# (keyword in lower-case basename, file stem) fallbacks, first hit wins.
ICON_KEYWORDS: List[Tuple[str, str]] = [
    ("crate", "wow_crate"), ("chest", "wow_crate"), ("box", "wow_crate"),
    ("scroll", "wow_scroll_classic"), ("book", "wow_scroll_classic"), ("letter", "wow_scroll_classic"),
    ("herb", "wow_herbalism"), ("flower", "wow_herbalism"), ("leaf", "wow_herbalism"),
    ("vial", "wow_crystal_vial"), ("drink", "wow_crystal_vial"),
    ("elixir", "wow_arcane_elixir"), ("flask", "wow_flask_blight"), ("potion", "wow_mana_potion"),
    ("oil", "wow_frost_oil"), ("fabric", "wow_linen_cloth"), ("cloth", "wow_linen_cloth"),
    ("leather", "wow_hide"), ("hide", "wow_hide"), ("coin", "wow_gold_bag"), ("gold", "wow_gold_bag"),
]


def build_font_face_css(addon_dir: Path) -> str:
    """Build @font-face declarations for bundled Inter weights + optional WoW ARIALN fallback."""
    rules: List[str] = []
    reg_ttf = addon_dir / "Assets" / "fonts" / "Inter-Regular.ttf"
    semi_ttf = addon_dir / "Assets" / "fonts" / "Inter-SemiBold.ttf"
    if reg_ttf.exists():
        rules.append(
            f"@font-face {{\n"
            f"  font-family: 'Inter';\n"
            f"  src: url('{reg_ttf.resolve().as_uri()}') format('truetype');\n"
            f"  font-weight: 400;\n"
            f"  font-style: normal;\n"
            f"}}"
        )
    if semi_ttf.exists():
        rules.append(
            f"@font-face {{\n"
            f"  font-family: 'Inter';\n"
            f"  src: url('{semi_ttf.resolve().as_uri()}') format('truetype');\n"
            f"  font-weight: 600;\n"
            f"  font-style: normal;\n"
            f"}}"
        )
    if ARIALN_TTF is not None and ARIALN_TTF.exists():
        rules.append(
            f"@font-face {{\n"
            f"  font-family: 'ArialNarrow';\n"
            f"  src: url('{ARIALN_TTF.resolve().as_uri()}') format('truetype');\n"
            f"  font-weight: 400;\n"
            f"  font-style: normal;\n"
            f"}}"
        )
    return "\n".join(rules)

# Exact Azeroth backdrop CSS + SVG from Fable 5.2 Design 1 index.html
AZEROTH_BACKDROP_CSS = """
:root, [data-apple-theme="light"] {
  --bd-sky: linear-gradient(180deg, #131B34 0%, #263159 30%, #4B446F 56%, #8D5560 78%, #3A2226 100%);
  --bd-moon: rgba(150, 176, 255, 0.44);
  --bd-ember: rgba(255, 170, 104, 0.82);
  --bd-ember-2: rgba(240, 130, 90, 0.42);
  --bd-aurora: rgba(120, 200, 210, 0.18);
  --bd-ridge-back: #35232D;
  --bd-ridge-front: #1D1319;
  --bd-fog: rgba(255, 200, 160, 0.14);
  --bd-star: 0.55;
  --mm-win-shadow: 0 36px 90px rgba(0, 0, 0, 0.50), 0 12px 28px rgba(0, 0, 0, 0.28);
}
[data-apple-theme="dark"] {
  --bd-sky: linear-gradient(180deg, #05070F 0%, #0A0F22 30%, #15132A 58%, #27151C 80%, #140A0B 100%);
  --bd-moon: rgba(92, 122, 214, 0.40);
  --bd-ember: rgba(226, 104, 44, 0.62);
  --bd-ember-2: rgba(196, 74, 40, 0.30);
  --bd-aurora: rgba(56, 150, 164, 0.16);
  --bd-ridge-back: #1B0F12;
  --bd-ridge-front: #0A0607;
  --bd-fog: rgba(255, 160, 110, 0.09);
  --bd-star: 0.9;
  --mm-win-shadow: 0 40px 100px rgba(0, 0, 0, 0.60), 0 14px 30px rgba(0, 0, 0, 0.40);
}
.backdrop {
  position: fixed; inset: 0; z-index: 0;
  background:
    radial-gradient(ellipse 540px 320px at 150px 100%, var(--bd-ember), transparent 72%),
    radial-gradient(ellipse 420px 320px at 170px 30px, var(--bd-moon), transparent 70%),
    radial-gradient(ellipse 560px 240px at 100% 100%, var(--bd-ember-2), transparent 70%),
    radial-gradient(ellipse 560px 200px at 86% 0%, var(--bd-aurora), transparent 70%),
    var(--bd-sky);
}
.backdrop svg { position: absolute; inset: 0; width: 100%; height: 100%; }
.bd-stars { fill: #FFFFFF; opacity: var(--bd-star); }
.bd-lady { fill: #EDEAE0; opacity: 0.88; }
.bd-child { fill: #9DB8F2; opacity: 0.85; }
.bd-fog { fill: var(--bd-fog); }
.bd-ridge-back { fill: var(--bd-ridge-back); }
.bd-ridge-front { fill: var(--bd-ridge-front); }
"""

def build_backdrop_html(vp_w: int, vp_h: int) -> str:
    sx = vp_w / 1440.0
    sy = vp_h / 900.0
    return f"""
<div class="backdrop" aria-hidden="true">
  <svg viewBox="0 0 {vp_w} {vp_h}" preserveAspectRatio="xMidYMax slice" focusable="false">
    <defs>
      <radialGradient id="bd-halo" cx="50%" cy="50%" r="50%">
        <stop offset="0" stop-color="#DCE4FF" stop-opacity="0.30"/>
        <stop offset="1" stop-color="#DCE4FF" stop-opacity="0"/>
      </radialGradient>
    </defs>
    <g transform="scale({sx:.6f} {sy:.6f})">
    <g class="bd-stars">
      <circle cx="38" cy="22" r="0.9" opacity="0.7"/><circle cx="96" cy="48" r="0.7" opacity="0.45"/><circle cx="150" cy="14" r="1.1" opacity="0.8"/><circle cx="212" cy="38" r="0.6" opacity="0.4"/>
      <circle cx="268" cy="56" r="0.8" opacity="0.5"/><circle cx="331" cy="20" r="1" opacity="0.75"/><circle cx="402" cy="44" r="0.6" opacity="0.35"/><circle cx="466" cy="12" r="0.8" opacity="0.6"/>
      <circle cx="523" cy="52" r="0.7" opacity="0.4"/><circle cx="590" cy="28" r="1.2" opacity="0.85"/><circle cx="655" cy="58" r="0.6" opacity="0.35"/><circle cx="712" cy="16" r="0.8" opacity="0.55"/>
      <circle cx="781" cy="40" r="0.7" opacity="0.45"/><circle cx="840" cy="10" r="1" opacity="0.7"/><circle cx="905" cy="50" r="0.6" opacity="0.4"/><circle cx="962" cy="26" r="0.9" opacity="0.6"/>
      <circle cx="1030" cy="60" r="0.7" opacity="0.35"/><circle cx="1088" cy="18" r="1.1" opacity="0.8"/><circle cx="1150" cy="42" r="0.6" opacity="0.4"/><circle cx="1214" cy="30" r="0.8" opacity="0.55"/>
      <circle cx="1270" cy="54" r="0.7" opacity="0.4"/><circle cx="1318" cy="12" r="0.9" opacity="0.65"/><circle cx="1432" cy="62" r="0.6" opacity="0.4"/>
      <circle cx="14" cy="118" r="0.8" opacity="0.55"/><circle cx="40" cy="176" r="0.6" opacity="0.4"/><circle cx="22" cy="262" r="1" opacity="0.7"/><circle cx="48" cy="330" r="0.6" opacity="0.35"/>
      <circle cx="10" cy="410" r="0.8" opacity="0.5"/><circle cx="36" cy="486" r="0.6" opacity="0.3"/>
      <circle cx="1396" cy="132" r="0.7" opacity="0.5"/><circle cx="1424" cy="198" r="1" opacity="0.7"/><circle cx="1404" cy="286" r="0.6" opacity="0.4"/><circle cx="1430" cy="356" r="0.8" opacity="0.5"/>
      <circle cx="1392" cy="440" r="0.6" opacity="0.35"/><circle cx="1418" cy="512" r="0.7" opacity="0.3"/>
    </g>
    <circle cx="1398" cy="38" r="46" fill="url(#bd-halo)"/>
    <circle class="bd-lady" cx="1398" cy="38" r="16"/>
    <circle class="bd-child" cx="1362" cy="22" r="5"/>
    <path class="bd-ridge-back" d="M0 842L26 836L48 806L64 800L80 762L92 756L104 728L126 722L138 744L168 750L182 782L214 790L232 770L262 764L276 796L318 808L360 800L384 822L452 830L520 818L548 796L590 790L612 812L690 824L760 816L800 830L880 834L940 818L972 792L1010 786L1034 806L1100 820L1160 812L1196 790L1230 784L1252 760L1284 754L1300 778L1342 786L1366 808L1410 800L1440 812L1440 900L0 900Z"/>
    <ellipse class="bd-fog" cx="300" cy="838" rx="420" ry="22"/>
    <ellipse class="bd-fog" cx="1120" cy="846" rx="380" ry="18"/>
    <path class="bd-ridge-front" d="M0 874L60 866L92 846L140 842L168 856L240 862L300 850L340 858L420 866L520 860L600 868L700 862L780 870L860 864L940 872L1040 862L1090 846L1130 842L1158 858L1240 866L1320 856L1380 864L1440 858L1440 900L0 900Z"/>
    <path class="bd-ridge-front" d="M1396 866L1400 800L1394 792L1399 790L1397 772L1404 784L1410 764L1416 784L1423 772L1421 790L1426 792L1420 800L1424 866Z"/>
    </g>
  </svg>
</div>
"""


# ---------------------------------------------------------------------------
# Pure-Python TGA Decoder & PNG Encoder (No PIL / numpy)
# ---------------------------------------------------------------------------

def decode_blp2(path: Path) -> Tuple[int, int, bytearray]:
    """Decode WoW BLP2 DXT1 (opaque) or DXT5 (RGBA) mip 0 into top-to-bottom RGBA."""
    data = path.read_bytes()
    if len(data) < 1172 or data[:4] != b"BLP2":
        raise ValueError(f"Bad BLP2 header: {path}")
    btype, enc, adepth, aenc, _, width, height = struct.unpack_from("<IBBBBII", data, 4)
    mip0_off = struct.unpack_from("<I", data, 20)[0]
    mip0_len = struct.unpack_from("<I", data, 84)[0]
    if btype != 1 or enc != 2 or aenc not in (0, 7):
        raise ValueError(f"Unsupported BLP2 format ({btype},{enc},{aenc}) in {path}")
    raw = bytearray(width * height * 4)
    bw = max(1, (width + 3) // 4)
    bh = max(1, (height + 3) // 4)
    pos = mip0_off
    is_dxt5 = (aenc == 7)
    for by in range(bh):
        for bx in range(bw):
            if is_dxt5:
                a0, a1 = data[pos], data[pos + 1]
                abits = int.from_bytes(data[pos + 2 : pos + 8], "little")
                if a0 > a1:
                    apal = (
                        a0, a1,
                        (6 * a0 + 1 * a1) // 7, (5 * a0 + 2 * a1) // 7,
                        (4 * a0 + 3 * a1) // 7, (3 * a0 + 4 * a1) // 7,
                        (2 * a0 + 5 * a1) // 7, (1 * a0 + 6 * a1) // 7,
                    )
                else:
                    apal = (
                        a0, a1,
                        (4 * a0 + 1 * a1) // 5, (3 * a0 + 2 * a1) // 5,
                        (2 * a0 + 3 * a1) // 5, (1 * a0 + 4 * a1) // 5,
                        0, 255,
                    )
                pos += 8
            c0, c1, cbits = struct.unpack_from("<HHI", data, pos)
            pos += 8
            r0, g0, b0 = ((c0 >> 11) & 31) * 255 // 31, ((c0 >> 5) & 63) * 255 // 63, (c0 & 31) * 255 // 31
            r1, g1, b1 = ((c1 >> 11) & 31) * 255 // 31, ((c1 >> 5) & 63) * 255 // 63, (c1 & 31) * 255 // 31
            if c0 > c1 or is_dxt5:
                cpal = (
                    (r0, g0, b0), (r1, g1, b1),
                    ((2 * r0 + r1) // 3, (2 * g0 + g1) // 3, (2 * b0 + b1) // 3),
                    ((r0 + 2 * r1) // 3, (g0 + 2 * g1) // 3, (b0 + 2 * b1) // 3),
                )
            else:
                cpal = (
                    (r0, g0, b0), (r1, g1, b1),
                    ((r0 + r1) // 2, (g0 + g1) // 2, (b0 + b1) // 2),
                    (0, 0, 0),
                )
            for py in range(4):
                yy = by * 4 + py
                if yy >= height:
                    continue
                row_base = yy * width * 4
                for px_i in range(4):
                    xx = bx * 4 + px_i
                    if xx >= width:
                        continue
                    pi = py * 4 + px_i
                    r, g, b = cpal[(cbits >> (2 * pi)) & 3]
                    a = apal[(abits >> (3 * pi)) & 7] if is_dxt5 else 255
                    o = row_base + xx * 4
                    raw[o] = r
                    raw[o + 1] = g
                    raw[o + 2] = b
                    raw[o + 3] = a
    return width, height, raw


def decode_tga(path: Path) -> Tuple[int, int, bytearray]:
    """Decode BLP2 or uncompressed (type=2) / RLE (type=10) 24/32-bit TGA into top-to-bottom RGBA."""
    if path.suffix.lower() == ".blp":
        return decode_blp2(path)
    data = path.read_bytes()
    if len(data) < 18:
        raise ValueError(f"TGA too small: {path}")
    id_len = data[0]
    cmap_type = data[1]
    img_type = data[2]
    cmap_len = struct.unpack_from("<H", data, 5)[0]
    cmap_bpp = data[7]
    width, height = struct.unpack_from("<HH", data, 12)
    bpp = data[16]
    descriptor = data[17]

    if img_type not in (2, 3, 10):
        raise ValueError(f"Unsupported TGA image_type={img_type} in {path}")
    if bpp not in (8, 24, 32):
        raise ValueError(f"Unsupported TGA bpp={bpp} in {path}")

    offset = 18 + id_len
    if cmap_type == 1:
        offset += cmap_len * ((cmap_bpp + 7) // 8)

    bytes_pp = bpp // 8
    total_pixels = width * height
    raw = bytearray(total_pixels * 4)

    if img_type in (2, 3):
        expected = total_pixels * bytes_pp
        if offset + expected > len(data):
            raise ValueError(f"Truncated TGA pixel data in {path}")
        if bpp == 32:
            for i in range(total_pixels):
                p = offset + i * 4
                b, g, r, a = data[p], data[p + 1], data[p + 2], data[p + 3]
                o = i * 4
                raw[o], raw[o + 1], raw[o + 2], raw[o + 3] = r, g, b, a
        elif bpp == 24:
            for i in range(total_pixels):
                p = offset + i * 3
                b, g, r = data[p], data[p + 1], data[p + 2]
                o = i * 4
                raw[o], raw[o + 1], raw[o + 2], raw[o + 3] = r, g, b, 255
        else:
            for i in range(total_pixels):
                v = data[offset + i]
                o = i * 4
                raw[o], raw[o + 1], raw[o + 2], raw[o + 3] = v, v, v, 255
    else:
        # RLE true-color (type 10)
        idx = 0
        pos = offset
        while idx < total_pixels and pos < len(data):
            hdr = data[pos]
            pos += 1
            count = (hdr & 0x7F) + 1
            if hdr & 0x80:
                b, g, r = data[pos], data[pos + 1], data[pos + 2]
                a = data[pos + 3] if bytes_pp == 4 else 255
                pos += bytes_pp
                for _ in range(count):
                    if idx >= total_pixels:
                        break
                    o = idx * 4
                    raw[o], raw[o + 1], raw[o + 2], raw[o + 3] = r, g, b, a
                    idx += 1
            else:
                for _ in range(count):
                    if idx >= total_pixels:
                        break
                    b, g, r = data[pos], data[pos + 1], data[pos + 2]
                    a = data[pos + 3] if bytes_pp == 4 else 255
                    pos += bytes_pp
                    o = idx * 4
                    raw[o], raw[o + 1], raw[o + 2], raw[o + 3] = r, g, b, a
                    idx += 1

    # Handle TGA origin bits: bit 5 (0x20)=0 means bottom-left origin; bit 4 (0x10)=1 means right-to-left
    top_down = (descriptor & 0x20) != 0
    right_left = (descriptor & 0x10) != 0
    stride = width * 4
    if not top_down:
        flipped = bytearray(total_pixels * 4)
        for y in range(height):
            src_y = height - 1 - y
            flipped[y * stride:(y + 1) * stride] = raw[src_y * stride:(src_y + 1) * stride]
        raw = flipped
    if right_left:
        for y in range(height):
            row_start = y * stride
            for x in range(width // 2):
                a_off = row_start + x * 4
                b_off = row_start + (width - 1 - x) * 4
                raw[a_off:a_off + 4], raw[b_off:b_off + 4] = raw[b_off:b_off + 4], raw[a_off:a_off + 4]

    return width, height, raw


def _png_chunk(tag: bytes, payload: bytes) -> bytes:
    return struct.pack(">I", len(payload)) + tag + payload + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)


def encode_png_rgba(width: int, height: int, rgba: bytes) -> bytes:
    """Encode top-to-bottom RGBA bytes into a valid PNG."""
    stride = width * 4
    rows = bytearray((stride + 1) * height)
    for y in range(height):
        dst = y * (stride + 1)
        rows[dst] = 0  # filter type 0 (None)
        src = y * stride
        rows[dst + 1:dst + 1 + stride] = rgba[src:src + stride]
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    idat = zlib.compress(bytes(rows), level=6)
    return b"\x89PNG\r\n\x1a\n" + _png_chunk(b"IHDR", ihdr) + _png_chunk(b"IDAT", idat) + _png_chunk(b"IEND", b"")


def read_png_dimensions(png_path: Path) -> Tuple[int, int]:
    data = png_path.read_bytes()
    if len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"Invalid PNG header: {png_path}")
    w, h = struct.unpack_from(">II", data, 16)
    return w, h


class TextureCache:
    """Loads .blp/.tga files on demand and caches cropped/tinted base64 PNG data URIs."""

    def __init__(
        self,
        addon_dir: Path,
        wow_icon_dir: Optional[Path] = None,
        skin_icon_dir: Optional[Path] = None,
    ) -> None:
        self.addon_dir = addon_dir
        self._wow_icon_dir = wow_icon_dir if wow_icon_dir is not None else WOW_ICON_DIR
        self._skin_icon_dir = skin_icon_dir if skin_icon_dir is not None else SKIN_ICON_DIR
        self._raw_cache: Dict[Path, Tuple[int, int, bytearray]] = {}
        self._uri_cache: Dict[tuple, str] = {}
        self._path_index: Dict[str, Path] = {}
        for sub in ("Assets", "Textures"):
            sub_dir = addon_dir / sub
            if sub_dir.exists():
                for ext in ("*.tga", "*.blp"):
                    for p in sub_dir.rglob(ext):
                        rel = p.relative_to(addon_dir).as_posix().lower()
                        self._path_index[rel] = p
                        self._path_index[rel[:-4]] = p
        # Optional real WoW icon PNGs used by Warcraft-skin scenes (stem -> path).
        self._icon_index: Dict[str, Path] = {}
        if self._wow_icon_dir is not None and self._wow_icon_dir.exists():
            for p in sorted(self._wow_icon_dir.glob("*.png")):
                self._icon_index[p.stem.lower()] = p
        self._icon_uri_cache: Dict[Path, str] = {}

    # -- real WoW icons (Warcraft skins only) ------------------------------------------------------
    def resolve_icon_png(self, wow_path: str) -> Optional[Path]:
        """Map Interface\\Icons\\<name> (or a known __fileid:N) to a PNG in wow_icon_dir.

        Order: exact lower-case basename -> ICON_ALIASES -> keyword -> stable hash over every icon file
        (so a seeded icon is never blank). Returns None for non-icon paths or when no icons are installed."""
        if (not self._icon_index and self._skin_icon_dir is None) or not wow_path:
            return None
        low = wow_path.replace("/", "\\").lower()
        if low.startswith("__fileid:"):
            stem = FILEID_ALIASES.get(low[len("__fileid:"):])
            return self._icon_index.get(stem) if stem else None
        if not low.startswith("interface\\icons\\"):
            return None
        base = low.rsplit("\\", 1)[-1]
        if base.endswith(".blp") or base.endswith(".png") or base.endswith(".tga"):
            base = base.rsplit(".", 1)[0]
        approved = SKIN_ICON_ALIASES.get(base)
        if approved and self._skin_icon_dir is not None:
            path = self._skin_icon_dir / f"game_icon_{approved}.png"
            if path.exists():
                return path
        if not self._icon_index:
            return None
        for stem in (base, ICON_ALIASES.get(base)):
            if stem and stem in self._icon_index:
                return self._icon_index[stem]
        for kw, stem in ICON_KEYWORDS:
            if kw in base and stem in self._icon_index:
                return self._icon_index[stem]
        names = sorted(self._icon_index)
        return self._icon_index[names[sum(base.encode("ascii", "ignore")) % len(names)]]

    def get_icon_data_uri(self, wow_path: str) -> Optional[str]:
        p = self.resolve_icon_png(wow_path)
        if not p:
            return None
        if p not in self._icon_uri_cache:
            self._icon_uri_cache[p] = "data:image/png;base64," + base64.b64encode(p.read_bytes()).decode("ascii")
        return self._icon_uri_cache[p]

    def native_size(self, wow_path: str, tex_coord: Optional[List[float]]) -> Optional[Tuple[int, int]]:
        """Pixel size of the texCoord crop of a .tga (the repeat unit WoW uses for SetHorizTile/SetVertTile)."""
        p = self.resolve_tga_path(wow_path)
        if not p:
            return None
        if p not in self._raw_cache:
            self._raw_cache[p] = decode_tga(p)
        src_w, src_h, _ = self._raw_cache[p]
        l, r, t, b = [float(v) for v in (tex_coord or [0, 1, 0, 1])]
        cw = max(1, int(round((min(1.0, max(l, r)) - max(0.0, min(l, r))) * src_w)))
        ch = max(1, int(round((min(1.0, max(t, b)) - max(0.0, min(t, b))) * src_h)))
        return cw, ch

    def resolve_tga_path(self, wow_path: str) -> Optional[Path]:
        if not wow_path or wow_path.startswith("__fileid:"):
            return None
        norm = wow_path.replace("\\", "/").strip()
        low = norm.lower()
        prefix = "interface/addons/merchantmaster/"
        if low.startswith(prefix):
            low = low[len(prefix):]
            norm = norm[len(prefix):]
        if low in self._path_index:
            return self._path_index[low]
        for ext in (".blp", ".tga"):
            if not low.endswith(ext) and (low + ext) in self._path_index:
                return self._path_index[low + ext]
        cand = self.addon_dir / norm
        if cand.exists() and cand.is_file():
            return cand
        for ext in (".blp", ".tga"):
            if not str(cand).lower().endswith(ext):
                cand2 = Path(str(cand) + ext)
                if cand2.exists() and cand2.is_file():
                    return cand2
        return None

    def get_data_uri(
        self,
        wow_path: str,
        tex_coord: Optional[List[float]],
        vertex_color: List[float],
        alpha: float = 1.0,
        desaturated: bool = False,
    ) -> Optional[str]:
        p = self.resolve_tga_path(wow_path)
        if not p:
            return None
        l, r, t, b = [float(v) for v in (tex_coord or [0, 1, 0, 1])]
        vr, vg, vb, va = [float(v) for v in (vertex_color or [1, 1, 1, 1])]
        eff_a = max(0.0, min(1.0, va * alpha))
        key = (
            p,
            round(l, 4), round(r, 4), round(t, 4), round(b, 4),
            round(vr, 3), round(vg, 3), round(vb, 3), round(eff_a, 3),
            bool(desaturated),
        )
        if key in self._uri_cache:
            return self._uri_cache[key]

        if p not in self._raw_cache:
            self._raw_cache[p] = decode_tga(p)
        src_w, src_h, src_rgba = self._raw_cache[p]

        flip_x = l > r
        flip_y = t > b
        u0, u1 = max(0.0, min(l, r)), min(1.0, max(l, r))
        v0, v1 = max(0.0, min(t, b)), min(1.0, max(t, b))

        x0 = max(0, min(src_w - 1, int(round(u0 * src_w))))
        x1 = max(x0 + 1, min(src_w, int(round(u1 * src_w))))
        y0 = max(0, min(src_h - 1, int(round(v0 * src_h))))
        y1 = max(y0 + 1, min(src_h, int(round(v1 * src_h))))

        cw = x1 - x0
        ch = y1 - y0
        out = bytearray(cw * ch * 4)
        for dy in range(ch):
            sy = (y1 - 1 - dy) if flip_y else (y0 + dy)
            src_row = sy * src_w * 4
            dst_row = dy * cw * 4
            for dx in range(cw):
                sx = (x1 - 1 - dx) if flip_x else (x0 + dx)
                so = src_row + sx * 4
                do = dst_row + dx * 4
                sr, sg, sb, sa = src_rgba[so], src_rgba[so + 1], src_rgba[so + 2], src_rgba[so + 3]
                if desaturated:
                    lum = int(0.299 * sr + 0.587 * sg + 0.114 * sb)
                    sr, sg, sb = lum, lum, lum
                out[do] = max(0, min(255, int(round(sr * vr))))
                out[do + 1] = max(0, min(255, int(round(sg * vg))))
                out[do + 2] = max(0, min(255, int(round(sb * vb))))
                out[do + 3] = max(0, min(255, int(round(sa * eff_a))))

        png_bytes = encode_png_rgba(cw, ch, bytes(out))
        uri = "data:image/png;base64," + base64.b64encode(png_bytes).decode("ascii")
        self._uri_cache[key] = uri
        return uri


# ---------------------------------------------------------------------------
# WoW Rich Text Parser (|cAARRGGBB ... |r and |T...|t)
# ---------------------------------------------------------------------------

_WOW_TOKEN_RE = re.compile(r"(\|c[0-9a-fA-F]{8}|\|r|\|T[^|]+\|t|\|n)")


def wow_text_to_html(text: str, base_css_color: str, tex_cache: TextureCache) -> str:
    parts: List[str] = []
    color_stack: List[str] = []
    tokens = _WOW_TOKEN_RE.split(text or "")
    for tok in tokens:
        if not tok:
            continue
        if tok.startswith("|c") and len(tok) == 10:
            aa = int(tok[2:4], 16) / 255.0
            rr = int(tok[4:6], 16)
            gg = int(tok[6:8], 16)
            bb = int(tok[8:10], 16)
            color_stack.append(f"rgba({rr},{gg},{bb},{aa:.3f})")
        elif tok == "|r":
            if color_stack:
                color_stack.pop()
        elif tok == "|n":
            parts.append("<br/>")
        elif tok.startswith("|T") and tok.endswith("|t"):
            inner = tok[2:-2]
            segs = inner.split(":")
            path_str = segs[0] if len(segs) > 0 else ""
            h_px = int(float(segs[1])) if len(segs) > 1 and segs[1] else 12
            w_px = int(float(segs[2])) if len(segs) > 2 and segs[2] and float(segs[2]) > 0 else h_px
            if len(segs) >= 10:
                dim_x = float(segs[5] or 16)
                dim_y = float(segs[6] or 16)
                u0 = float(segs[7] or 0) / dim_x
                u1 = float(segs[8] or dim_x) / dim_x
                v0 = float(segs[9] or 0) / dim_y
                v1 = float(segs[10] or dim_y) / dim_y if len(segs) > 10 and segs[10] else 1.0
                vc = [1.0, 1.0, 1.0, 1.0]
                if len(segs) >= 14:
                    vc = [
                        float(segs[11] or 255) / 255.0,
                        float(segs[12] or 255) / 255.0,
                        float(segs[13] or 255) / 255.0,
                        1.0,
                    ]
                uri = tex_cache.get_data_uri(path_str, [u0, u1, v0, v1], vc)
            else:
                uri = tex_cache.get_data_uri(path_str, [0, 1, 0, 1], [1, 1, 1, 1])
            if uri:
                parts.append(
                    f'<img src="{uri}" style="width:{w_px}px;height:{h_px}px;vertical-align:middle;display:inline-block;margin:0 1px;" />'
                )
            else:
                plow = path_str.lower()
                if "ui-goldicon" in plow:
                    parts.append('<span style="color:rgba(218,176,64,0.92);font-size:0.82em;font-weight:500;">g</span>')
                elif "ui-silvericon" in plow:
                    parts.append('<span style="color:rgba(168,174,184,0.90);font-size:0.82em;font-weight:500;">s</span>')
                elif "ui-coppericon" in plow:
                    parts.append('<span style="color:rgba(196,130,86,0.90);font-size:0.82em;font-weight:500;">c</span>')
        else:
            escaped = html.escape(tok)
            if color_stack:
                parts.append(f'<span style="color:{color_stack[-1]};">{escaped}</span>')
            else:
                parts.append(escaped)
    return "".join(parts)


# ---------------------------------------------------------------------------
# HTML Scene Composer
# ---------------------------------------------------------------------------

def rgba_css(c: List[float], mul_alpha: float = 1.0) -> str:
    r = max(0, min(255, int(round((c[0] if len(c) > 0 else 1.0) * 255))))
    g = max(0, min(255, int(round((c[1] if len(c) > 1 else 1.0) * 255))))
    b = max(0, min(255, int(round((c[2] if len(c) > 2 else 1.0) * 255))))
    a = max(0.0, min(1.0, float(c[3] if len(c) > 3 else 1.0) * mul_alpha))
    return f"rgba({r},{g},{b},{a:.4f})"


def snap_rect(x: float, y: float, w: float, h: float) -> Tuple[float, float, float, float]:
    """Snap fill edges to the @2x device grid so abutting 9-slice pieces never leave a hairline seam
    when a scene is drawn at a fractional panel scale."""
    x0 = round(x * 2.0) / 2.0
    y0 = round(y * 2.0) / 2.0
    x1 = round((x + w) * 2.0) / 2.0
    y1 = round((y + h) * 2.0) / 2.0
    return x0, y0, x1 - x0, y1 - y0


def wrap_with_clip(inner_html: str, clip: Optional[dict], ox: float, oy: float) -> Tuple[str, float, float]:
    if not clip:
        return inner_html, ox, oy
    return inner_html, ox, oy


def _apple_item_badge_html(
    tex_path: str,
    x: float,
    y: float,
    w: float,
    h: float,
    mode: str,
    alpha: float,
    has_circle_backing: bool = False,
) -> str:
    """Render WoW Interface\\Icons\\... or __fileid:... textures as crisp SF-Symbol glyphs without artificial borders."""
    low = tex_path.lower()
    if "crate" in low or "box" in low or "chest" in low or "236994" in low:
        svg_inner = '<path d="M12 3.25l8 4.1v9.3l-8 4.1-8-4.1v-9.3l8-4.1z"/><path d="M4 7.35l8 4.1 8-4.1M12 11.45v9.3"/><path d="M8 5.3l8 4.1"/>'
    elif "scroll" in low or "note" in low or "book" in low or "134939" in low or "134941" in low or "133741" in low:
        svg_inner = '<path d="M7.75 3.5h6l4.5 4.5v10.5a2 2 0 0 1-2 2h-8.5a2 2 0 0 1-2-2v-13a2 2 0 0 1 2-2z"/><path d="M13.5 3.5v4.75h4.75"/><path d="M9 12.75h6M9 16.25h3.75"/>'
    elif "herb" in low or "leaf" in low or "flower" in low or "134187" in low or "136065" in low:
        svg_inner = '<path d="M5.25 18.75C4.4 10.6 9.9 5.1 19.5 4.5c.5 9.5-5 15.1-14.25 14.25z"/><path d="M5.25 18.75c2.4-4.6 5.4-7.6 9.5-9.75"/>'
    elif "vial" in low or "134715" in low:
        svg_inner = '<path d="M9 3.5h6"/><path d="M10 3.5v13.75a2 2 0 0 0 4 0V3.5"/><path d="M10 11.5h4"/>'
    elif "134830" in low or "flask" in low or "elixir" in low or "potion" in low:
        svg_inner = '<path d="M9.25 3.5h5.5"/><path d="M10.25 3.5v5.4l-4.9 8.35a2.2 2.2 0 0 0 1.9 3.3h9.5a2.2 2.2 0 0 0 1.9-3.3l-4.9-8.35V3.5"/><path d="M7.9 14.75h8.2"/>'
    else:
        svg_inner = '<path d="M9.25 3.5h5.5"/><path d="M10.25 3.5v5.4l-4.9 8.35a2.2 2.2 0 0 0 1.9 3.3h9.5a2.2 2.2 0 0 0 1.9-3.3l-4.9-8.35V3.5"/><path d="M7.9 14.75h8.2"/>'

    is_light = (mode == "light")
    ink = "rgba(60,60,67,0.74)" if is_light else "rgba(235,235,245,0.68)"
    if has_circle_backing:
        ic_sz = max(9.0, min(w, h) * 0.88)
        return (
            f'<div style="position:absolute;left:{x:.2f}px;top:{y:.2f}px;width:{w:.2f}px;height:{h:.2f}px;'
            f'opacity:{alpha:.3f};display:flex;align-items:center;justify-content:center;pointer-events:none;">'
            f'<svg viewBox="0 0 24 24" width="{ic_sz:.1f}" height="{ic_sz:.1f}" fill="none" '
            f'stroke="{ink}" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">{svg_inner}</svg>'
            f'</div>'
        )
    bg = "rgba(118,118,128,0.12)" if is_light else "rgba(118,118,128,0.24)"
    ic_sz = max(9.0, min(w, h) * 0.56)
    radius = min(w, h) * 0.5
    return (
        f'<div style="position:absolute;left:{x:.2f}px;top:{y:.2f}px;width:{w:.2f}px;height:{h:.2f}px;'
        f'border-radius:{radius:.1f}px;background:{bg};opacity:{alpha:.3f};'
        f'display:flex;align-items:center;justify-content:center;pointer-events:none;">'
        f'<svg viewBox="0 0 24 24" width="{ic_sz:.1f}" height="{ic_sz:.1f}" fill="none" '
        f'stroke="{ink}" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">{svg_inner}</svg>'
        f'</div>'
    )


def scene_skin(scene: dict) -> str:
    return str(scene.get("skin") or "standard")


@lru_cache(maxsize=256)
def skin_texture_alpha_bounds(texture: str) -> Optional[Tuple[float, float, float, float]]:
    """Normalized visible bounds, excluding transparent padding in the approved skin art."""
    normalized = texture.replace("\\", "/")
    prefix = "interface/addons/merchantmaster/"
    if not normalized.lower().startswith(prefix + "assets/skins/"):
        return None
    rel = normalized[len(prefix):]
    path = ADDON_DIR / rel
    if not path.is_file():
        for ext in (".blp", ".tga"):
            cand = path.with_suffix(ext)
            if cand.is_file():
                path = cand
                break
    if not path.is_file():
        return None
    width, height, rgba = decode_tga(path)
    left, top, right, bottom = width, height, 0, 0
    for y in range(height):
        for x in range(width):
            if rgba[(y * width + x) * 4 + 3]:
                left, top = min(left, x), min(top, y)
                right, bottom = max(right, x + 1), max(bottom, y + 1)
    if right <= left or bottom <= top:
        return (0, 0, 0, 0)
    return left / width, top / height, right / width, bottom / height


def scene_canvas(scene: dict) -> Tuple[int, int, int, int]:
    """(canvas_w, canvas_h, offset_x, offset_y) in CSS px.

    Preserve the viewport; expand custom scenes only for visible overflowing primitives."""
    vp = scene.get("viewport") or {}
    vp_w = int(vp.get("w", 1920))
    vp_h = int(vp.get("h", 960))
    if scene_skin(scene) == "standard":
        return vp_w, vp_h, 0, 0
    left, top, right, bottom = 0.0, 0.0, float(vp_w), float(vp_h)
    for item in scene.get("items", []):
        if item.get("kind") == "line":
            x0, x1 = sorted((float(item["x1"]), float(item["x2"])))
            y0, y1 = sorted((float(item["y1"]), float(item["y2"])))
        else:
            x0, y0 = float(item.get("x", 0)), float(item.get("y", 0))
            x1, y1 = x0 + float(item.get("w", 0)), y0 + float(item.get("h", 0))
            if (item.get("kind") == "texture" and not item.get("rotation")
                    and not item.get("texQuad") and item.get("texCoord", [0, 1, 0, 1]) == [0, 1, 0, 1]):
                bounds = skin_texture_alpha_bounds(item.get("texture", ""))
                if bounds is not None:
                    if bounds == (0, 0, 0, 0):
                        continue
                    u0, v0, u1, v1 = bounds
                    w, h = x1 - x0, y1 - y0
                    x0, x1 = x0 + u0 * w, x0 + u1 * w
                    y0, y1 = y0 + v0 * h, y0 + v1 * h
        clip = item.get("clip")
        if clip:
            x0, y0 = max(x0, clip["x"]), max(y0, clip["y"])
            x1, y1 = min(x1, clip["x"] + clip["w"]), min(y1, clip["y"] + clip["h"])
        if x1 < x0 or y1 < y0:
            continue
        left, top, right, bottom = min(left, x0), min(top, y0), max(right, x1), max(bottom, y1)
    pad_l, pad_t = math.ceil(-left), math.ceil(-top)
    return math.ceil(right) + pad_l, math.ceil(bottom) + pad_t, pad_l, pad_t


# skin -> (deep base, mid glow, accent) for the dark mood canvas behind Warcraft skins.
SKIN_MOOD: Dict[str, Tuple[str, str, str]] = {
    "human": ("#070b14", "#16264a", "#c9a24a"),
    "night_elf": ("#07060f", "#25164a", "#8a63d2"),
    "orc": ("#0d0504", "#3a1209", "#c8402c"),
    "undead": ("#050908", "#10261c", "#74c69d"),
    "goblin": ("#080a04", "#26340a", "#c9d63a"),
}


def build_skin_canvas_html(skin: str, cw: int, ch: int) -> str:
    base, mid, accent = SKIN_MOOD.get(skin, ("#05070F", "#15132A", "#8888aa"))
    return (
        f'<div class="backdrop" aria-hidden="true" style="background:'
        f'radial-gradient(ellipse {cw * 0.55:.0f}px {ch * 0.55:.0f}px at 50% 46%, {mid} 0%, transparent 78%),'
        f'radial-gradient(ellipse {cw * 0.35:.0f}px {ch * 0.22:.0f}px at 50% 100%, {accent}22 0%, transparent 80%),'
        f'radial-gradient(ellipse {cw * 0.9:.0f}px {ch * 0.9:.0f}px at 50% 50%, transparent 55%, rgba(0,0,0,0.55) 100%),'
        f'{base};"></div>'
    )


def quad_css_matrix(quad: List[float]) -> Optional[Tuple[float, float, float, float, bool]]:
    """Rebuild the CSS matrix(a,b,c,d,0,0) for an 8-argument SetTexCoord quad (rotated/transposed pieces).

    quad = ulx,uly, llx,lly, urx,ury, lrx,lry. The image is drawn upright inside the bbox viewBox, so the
    element transform is the inverse of the screen->texture mapping (orthogonal, hence its transpose).
    The 5th value says the axes are swapped, i.e. the pre-transform box must be h x w."""
    if not quad or len(quad) < 8:
        return None
    ulx, uly, llx, lly, urx, ury, lrx, lry = [float(v) for v in quad[:8]]
    l, r = min(ulx, llx, urx, lrx), max(ulx, llx, urx, lrx)
    t, b = min(uly, lly, ury, lry), max(uly, lly, ury, lry)
    dx, dy = r - l, b - t
    if dx <= 1e-9 or dy <= 1e-9:
        return None

    def n(x: float, y: float) -> Tuple[float, float]:
        return (x - l) / dx - 0.5, (y - t) / dy - 0.5

    ul, ll, ur = n(ulx, uly), n(llx, lly), n(urx, ury)
    ax = (ur[0] - ul[0], ur[1] - ul[1])
    ay = (ll[0] - ul[0], ll[1] - ul[1])
    return ax[0], ay[0], ax[1], ay[1], abs(ax[0]) < 1e-6


def build_scene_html(scene: dict, tex_cache: TextureCache, font_face_css: str = "") -> str:
    mode = scene.get("mode", "dark")
    skin = scene_skin(scene)
    custom_skin = skin != "standard"
    vp = scene.get("viewport", {"w": 1920, "h": 960})
    win = scene.get("window", {"x": 40, "y": 115, "w": 1840, "h": 730})
    items = scene.get("items", [])
    canvas_w, canvas_h, canvas_ox, canvas_oy = scene_canvas(scene)

    # Pre-index circle_fill container centers so __fileid icons inside them don't double-draw circles
    circle_containers: List[Tuple[float, float, float]] = []
    for it in items:
        if it.get("kind") == "texture" and "circle_fill" in str(it.get("texture", "")).lower():
            cw, ch = float(it.get("w", 0)), float(it.get("h", 0))
            if cw >= 16 and ch >= 16:
                circle_containers.append((float(it["x"]) + cw * 0.5, float(it["y"]) + ch * 0.5, min(cw, ch) * 0.5))

    def inside_circle_container(x: float, y: float, w: float, h: float) -> bool:
        cx, cy = x + w * 0.5, y + h * 0.5
        for ccx, ccy, cr in circle_containers:
            if abs(cx - ccx) <= cr and abs(cy - ccy) <= cr:
                return True
        return False

    layers: List[str] = []

    # The preview backdrop supplies a drop shadow. Lua primitives supply the window rim and refraction.
    wx, wy, ww, wh = win["x"], win["y"], win["w"], win["h"]
    shadow_radius = 6 if custom_skin else 22
    layers.append(
        f'<div style="position:absolute;left:{wx:.2f}px;top:{wy:.2f}px;width:{ww:.2f}px;height:{wh:.2f}px;'
        f'border-radius:{shadow_radius}px;box-shadow:var(--mm-win-shadow);pointer-events:none;z-index:1;"></div>'
    )

    scene_body: List[str] = []
    for item in items:
        kind = item.get("kind")
        clip = item.get("clip")
        ox = float(clip["x"]) if clip else 0.0
        oy = float(clip["y"]) if clip else 0.0
        alpha = float(item.get("alpha", 1.0))

        el = ""
        if kind == "color":
            x, y, w, h = snap_rect(float(item["x"]), float(item["y"]), float(item["w"]), float(item["h"]))
            grad = item.get("gradient")
            if isinstance(grad, dict) and grad.get("min") and grad.get("max"):
                c_min = rgba_css(grad["min"], alpha)
                c_max = rgba_css(grad["max"], alpha)
                if grad.get("dir") == "VERTICAL":
                    bg = f"linear-gradient(180deg,{c_max},{c_min})"
                else:
                    bg = f"linear-gradient(90deg,{c_min},{c_max})"
            else:
                bg = rgba_css(item.get("color", [1, 1, 1, 1]), alpha)
            blend_css = "mix-blend-mode:plus-lighter;" if item.get("blend") == "ADD" else ""
            el = (
                f'<div style="position:absolute;left:{x - ox:.2f}px;top:{y - oy:.2f}px;width:{w:.2f}px;height:{h:.2f}px;'
                f'background:{bg};{blend_css}"></div>'
            )

        elif kind == "backdrop":
            x = float(item["x"]) - ox
            y = float(item["y"]) - oy
            w = float(item["w"])
            h = float(item["h"])
            bg = rgba_css(item.get("bgColor", [0, 0, 0, 0]), alpha)
            bd = rgba_css(item.get("borderColor", [1, 1, 1, 0]), alpha)
            es = float(item.get("edgeSize", 1))
            el = (
                f'<div style="position:absolute;left:{x:.2f}px;top:{y:.2f}px;width:{w:.2f}px;height:{h:.2f}px;'
                f'background:{bg};border:{min(2.0, max(0.5, es * 0.1)):.1f}px solid {bd};box-sizing:border-box;"></div>'
            )

        elif kind == "texture":
            x = float(item["x"])
            y = float(item["y"])
            w = float(item["w"])
            h = float(item["h"])
            tex_path = item.get("texture", "")
            tex_coord = item.get("texCoord") or [0, 1, 0, 1]
            u0, u1, v0, v1 = (max(0.0, min(1.0, float(uv))) for uv in tex_coord)
            use_viewbox = (u0, u1, v0, v1) != (0, 1, 0, 1) and u0 != u1 and v0 != v1
            horiz_tile = bool(item.get("horizTile"))
            vert_tile = bool(item.get("vertTile"))
            tiled = horiz_tile or vert_tile
            quad_m = quad_css_matrix(item.get("texQuad")) if item.get("texQuad") else None
            if tiled:
                use_viewbox = False  # tiles bake the texCoord crop (and mirroring) into the repeat unit
            raw_uv = [float(v) for v in tex_coord]
            wrap_h = str(item.get("wrapH") or "").upper() == "REPEAT"
            wrap_v = str(item.get("wrapV") or "").upper() == "REPEAT"
            wrapped = (custom_skin and not tiled and quad_m is None and raw_uv[0] != raw_uv[1] and raw_uv[2] != raw_uv[3]
                       and (wrap_h or wrap_v or any(v < -1e-6 or v > 1 + 1e-6 for v in raw_uv)))
            if wrapped:
                use_viewbox = False  # texCoord with REPEAT wrap repeats the whole texture
            uri = tex_cache.get_data_uri(
                tex_path,
                None if (use_viewbox or wrapped) else tex_coord,
                item.get("vertexColor", [1, 1, 1, 1]),
                alpha=alpha,
                desaturated=bool(item.get("desaturated", False)),
            )
            icon_style = ""
            if uri is None and custom_skin:
                # Warcraft skins paint the real WoW icon PNGs instead of the Apple glyph badges.
                uri = tex_cache.get_icon_data_uri(tex_path)
                if uri:
                    vc = item.get("vertexColor") or [1, 1, 1, 1]
                    eff_a = max(0.0, min(1.0, alpha * float(vc[3] if len(vc) > 3 else 1.0)))
                    icon_style = f"opacity:{eff_a:.3f};"
                    if item.get("desaturated"):
                        icon_style += "filter:grayscale(1);"
            rot = float(item.get("rotation", 0.0))
            transforms = []
            if abs(rot) > 1e-4:
                transforms.append(f"rotate({-rot:.4f}rad)")
            else:
                x, y, w, h = snap_rect(x, y, w, h)
            if w <= 0 or h <= 0:
                continue
            if quad_m is not None:
                qa, qb, qc, qd, swapped = quad_m
                if swapped:
                    # Pre-transform box is h x w; keep the visual centre fixed.
                    x, y, w, h = x + (w - h) * 0.5, y + (h - w) * 0.5, h, w
                transforms.append(f"matrix({qa:.0f},{qb:.0f},{qc:.0f},{qd:.0f},0,0)")
            elif (use_viewbox or wrapped) and (raw_uv[0] > raw_uv[1] or raw_uv[2] > raw_uv[3]):
                transforms.append(f"scale({-1 if raw_uv[0] > raw_uv[1] else 1},{-1 if raw_uv[2] > raw_uv[3] else 1})")
            transform_css = f"transform:{' '.join(transforms)};" if transforms else ""
            blend_css = "mix-blend-mode:plus-lighter;" if item.get("blend") == "ADD" else ""
            style = (
                f"position:absolute;left:{x - ox:.2f}px;top:{y - oy:.2f}px;width:{w:.2f}px;height:{h:.2f}px;"
                f"display:block;{transform_css}{blend_css}{icon_style}"
            )
            if uri and tiled:
                native = tex_cache.native_size(tex_path, tex_coord)
                if native is None:
                    native = (int(w), int(h))
                tile_w = native[0] if horiz_tile else w
                tile_h = native[1] if vert_tile else h
                repeat = "repeat" if (horiz_tile and vert_tile) else ("repeat-x" if horiz_tile else "repeat-y")
                el = (
                    f'<div style="{style}background-image:url({uri});background-size:{tile_w:.2f}px {tile_h:.2f}px;'
                    f'background-repeat:{repeat};background-position:0 0;"></div>'
                )
            elif uri and wrapped:
                unit_w = w / abs(raw_uv[1] - raw_uv[0]) if (wrap_h or abs(raw_uv[1] - raw_uv[0]) > 1e-6) else w
                unit_h = h / abs(raw_uv[3] - raw_uv[2]) if (wrap_v or abs(raw_uv[3] - raw_uv[2]) > 1e-6) else h
                pos_x = -min(raw_uv[0], raw_uv[1]) * unit_w
                pos_y = -min(raw_uv[2], raw_uv[3]) * unit_h
                if wrap_h and not wrap_v and abs(raw_uv[3] - raw_uv[2] - 1.0) < 1e-3:
                    bg_repeat = "repeat-x"
                    unit_h = h
                elif wrap_v and not wrap_h and abs(raw_uv[1] - raw_uv[0] - 1.0) < 1e-3:
                    bg_repeat = "repeat-y"
                    unit_w = w
                else:
                    bg_repeat = "repeat"
                el = (
                    f'<div style="{style}background-image:url({uri});background-size:{unit_w:.2f}px {unit_h:.2f}px;'
                    f'background-repeat:{bg_repeat};background-position:{pos_x:.2f}px {pos_y:.2f}px;"></div>'
                )
            elif uri:
                if use_viewbox:
                    # Keep the whole tinted texture available to the sampler at the UV boundaries.
                    # The viewBox clips each piece to its exact UVs, including the pill's narrow center.
                    viewbox = f"{min(u0, u1):.8f} {min(v0, v1):.8f} {abs(u1 - u0):.8f} {abs(v1 - v0):.8f}"
                    el = (
                        f'<svg viewBox="{viewbox}" preserveAspectRatio="none" style="{style}overflow:hidden;">'
                        f'<image href="{uri}" width="1" height="1" preserveAspectRatio="none" /></svg>'
                    )
                else:
                    el = f'<img src="{uri}" style="{style}object-fit:fill;" />'
            elif tex_path.startswith("__fileid:") or tex_path.lower().startswith("interface\\icons\\") or tex_path.lower().startswith("interface/icons/"):
                has_backing = inside_circle_container(float(item["x"]), float(item["y"]), w, h)
                el = _apple_item_badge_html(tex_path, x - ox, y - oy, w, h, mode, alpha, has_circle_backing=has_backing)

        elif kind == "line":
            x1 = float(item["x1"]) - ox
            y1 = float(item["y1"]) - oy
            x2 = float(item["x2"]) - ox
            y2 = float(item["y2"]) - oy
            thick = float(item.get("thickness", 1.5))
            col = rgba_css(item.get("color", [1, 1, 1, 1]), alpha)
            sw = float(clip["w"]) if clip else float(vp["w"])
            sh = float(clip["h"]) if clip else float(vp["h"])
            el = (
                f'<svg width="{sw:.0f}" height="{sh:.0f}" style="position:absolute;left:0;top:0;pointer-events:none;overflow:visible;">'
                f'<line x1="{x1:.2f}" y1="{y1:.2f}" x2="{x2:.2f}" y2="{y2:.2f}" '
                f'stroke="{col}" stroke-width="{thick:.2f}" stroke-linecap="round" /></svg>'
            )

        elif kind == "text":
            x = float(item["x"]) - ox
            y = float(item["y"]) - oy
            w = float(item["w"])
            h = float(item["h"])
            fs = float(item.get("fontSize", 12))
            fp = str(item.get("fontPath", "")).lower()
            ff = str(item.get("fontFlags", "")).upper()
            if "inter-semibold" in fp or "semibold" in fp or "bold" in fp:
                ff_css = "'Inter',system-ui,sans-serif"
                weight = 600
            elif "inter-regular" in fp or "inter" in fp or "regular" in fp:
                ff_css = "'Inter',system-ui,sans-serif"
                weight = 400
            elif "arialn" in fp:
                ff_css = "'ArialNarrow','Inter',sans-serif"
                weight = 400
            else:
                ff_css = "'Times New Roman',Georgia,serif"
                weight = 400
            col = rgba_css(item.get("color", [1, 1, 1, 1]), alpha)
            jh = item.get("justifyH", "CENTER").upper()
            jv = item.get("justifyV", "MIDDLE").upper()
            jc_css = {"LEFT": "flex-start", "CENTER": "center", "RIGHT": "flex-end"}.get(jh, "center")
            ai_css = {"TOP": "flex-start", "MIDDLE": "center", "BOTTOM": "flex-end"}.get(jv, "center")
            ta_css = {"LEFT": "left", "CENTER": "center", "RIGHT": "right"}.get(jh, "center")
            wrap = bool(item.get("wordWrap", True))
            constrained_w = bool(item.get("constrainedW", True))
            if wrap:
                box_wrap_css = "white-space:normal;"
                span_wrap_css = ""
            elif constrained_w:
                box_wrap_css = "white-space:nowrap;overflow:hidden;"
                span_wrap_css = "min-width:0;max-width:100%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;display:inline-block;"
            else:
                box_wrap_css = "white-space:nowrap;"
                span_wrap_css = "white-space:nowrap;"

            shadows: List[str] = []
            if "OUTLINE" in ff:
                shadows.append("0 0 1px rgba(0,0,0,0.65)")
            so = item.get("shadowOffset")
            sc = item.get("shadowColor")
            if isinstance(so, list) and len(so) >= 2:
                sx, sy = float(so[0] or 0), float(so[1] or 0)
                sc_alpha = float(sc[3]) if isinstance(sc, list) and len(sc) >= 4 else 0.85
                if (abs(sx) > 1e-3 or abs(sy) > 1e-3) and sc_alpha > 1e-3:
                    scol = rgba_css(sc if isinstance(sc, list) else [0, 0, 0, 0.85], alpha)
                    shadows.append(f"{sx:.2f}px {-sy:.2f}px 1px {scol}")
            shadow_css = f"text-shadow:{','.join(shadows)};" if shadows else "text-shadow:none;"

            ls_css = "letter-spacing:-0.02em;" if fs >= 15 else ""
            rich = wow_text_to_html(item.get("text", ""), col, tex_cache)
            el = (
                f'<div style="position:absolute;left:{x:.2f}px;top:{y:.2f}px;width:{w:.2f}px;height:{h:.2f}px;'
                f'display:flex;align-items:{ai_css};justify-content:{jc_css};text-align:{ta_css};'
                f'font-family:{ff_css};font-size:{fs:.2f}px;line-height:1.22;font-weight:{weight};color:{col};'
                f'{box_wrap_css}{shadow_css}{ls_css}"><span style="{span_wrap_css}">{rich}</span></div>'
            )

        if not el:
            continue

        if clip:
            cx, cy, cw, ch = float(clip["x"]), float(clip["y"]), float(clip["w"]), float(clip["h"])
            scene_body.append(
                f'<div style="position:absolute;left:{cx:.2f}px;top:{cy:.2f}px;width:{cw:.2f}px;height:{ch:.2f}px;overflow:hidden;">{el}</div>'
            )
        else:
            scene_body.append(el)

    if custom_skin:
        if scene.get("brightBackdrop"):
            backdrop_html = (
                '<div class="backdrop" aria-hidden="true" style="background:'
                'radial-gradient(ellipse 70% 55% at 50% 35%, #F2F7FC 0%, transparent 72%),'
                'linear-gradient(180deg, #E6F0FA 0%, #CEE0F2 55%, #B5CEE6 100%);"></div>'
            )
        else:
            backdrop_html = build_skin_canvas_html(skin, canvas_w, canvas_h)
        world_open = (
            f'<div class="world" style="position:absolute;left:{canvas_ox}px;top:{canvas_oy}px;'
            f'width:{vp["w"]}px;height:{vp["h"]}px;">'
        )
        world_close = "</div>"
    else:
        backdrop_html = build_backdrop_html(int(vp["w"]), int(vp["h"]))
        world_open = ""
        world_close = ""

    return f"""<!DOCTYPE html>
<html lang="en" data-apple-theme="{html.escape(mode)}">
<head>
<meta charset="utf-8" />
<style>
{font_face_css}
*, *::before, *::after {{ box-sizing: border-box; }}
html, body {{
  margin: 0; padding: 0;
  width: {canvas_w}px; height: {canvas_h}px;
  overflow: hidden;
  background: #05070F;
  font-family: 'Inter', system-ui, sans-serif;
  font-variant-numeric: tabular-nums;
  -webkit-font-smoothing: antialiased;
}}
{AZEROTH_BACKDROP_CSS}
.stage {{
  position: relative;
  width: {vp["w"]}px; height: {vp["h"]}px;
  z-index: 2;
}}
</style>
</head>
<body>
{backdrop_html}
{world_open}{"".join(layers)}
<div class="stage">
{"".join(scene_body)}
</div>{world_close}
</body>
</html>
"""


def main() -> int:
    parser = argparse.ArgumentParser(description="Render Lua-dumped MerchantMaster scenes via headless Chrome @2x.")
    parser.add_argument("--lua-exe", default=DEFAULT_LUA_EXE)
    parser.add_argument("--chrome-exe", default=DEFAULT_CHROME_EXE)
    parser.add_argument("--out-dir", default=DEFAULT_OUT_DIR)
    parser.add_argument("--wow-icon-dir", type=Path, default=WOW_ICON_DIR, help="Optional directory of WoW icon PNGs")
    parser.add_argument("--skin-icon-dir", type=Path, default=SKIN_ICON_DIR, help="Optional directory of custom skin icon PNGs")
    parser.add_argument("--dump-dir", default=None, help="Optional directory containing/receiving JSON scene dumps")
    parser.add_argument("--skip-dump", action="store_true", help="Skip running lua_frame_dump.lua and reuse JSONs in --dump-dir")
    parser.add_argument("--scenes", nargs="*", default=None,
                        help="Scene names to render (default: the standard set, or the 10 skin scenes with --skins)")
    parser.add_argument("--skins", action="store_true",
                        help="Run the dumper with --skins and render the Warcraft-skin scenes (SKIN_SCENES)")
    args = parser.parse_args()
    if args.scenes is None:
        args.scenes = list(SKIN_SCENES if args.skins else SCENES)

    out_dir = Path(args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="mm_preview_") as tmp:
        tmp_path = Path(tmp)
        dump_dir = Path(args.dump_dir) if args.dump_dir else (tmp_path / "scenes")
        dump_dir.mkdir(parents=True, exist_ok=True)

        if not args.skip_dump:
            print(f"[render] Running Lua frame-graph dumper -> {dump_dir}")
            dump_cmd = [args.lua_exe, str(DUMPER_LUA), str(dump_dir)]
            if args.skins:
                dump_cmd.append("--skins")
            res = subprocess.run(
                dump_cmd,
                cwd=str(ADDON_DIR),
                capture_output=True,
                text=True,
            )
            if res.stdout:
                print(res.stdout.strip())
            if res.returncode != 0:
                print(res.stderr, file=sys.stderr)
                return res.returncode

        tex_cache = TextureCache(ADDON_DIR, wow_icon_dir=args.wow_icon_dir, skin_icon_dir=args.skin_icon_dir)
        font_face_css = build_font_face_css(ADDON_DIR)
        html_dir = tmp_path / "html"
        html_dir.mkdir(parents=True, exist_ok=True)

        for scene_name in args.scenes:
            json_path = dump_dir / f"{scene_name}.json"
            if not json_path.exists():
                print(f"[render] ERROR: missing scene JSON {json_path}", file=sys.stderr)
                return 1
            scene_data = json.loads(json_path.read_text(encoding="utf-8"))
            vp = scene_data.get("viewport") or {}
            # Preserve the viewport, adding room only for actual custom-art overflow.
            vp_w, vp_h, _, _ = scene_canvas(scene_data)
            html_str = build_scene_html(scene_data, tex_cache, font_face_css)
            html_file = html_dir / f"{scene_name}.html"
            html_file.write_text(html_str, encoding="utf-8")

            png_out = out_dir / f"{scene_name}.png"
            if png_out.exists():
                png_out.unlink()

            cmd = [
                args.chrome_exe,
                f"--user-data-dir={tmp_path / ('chrome-' + scene_name)}",
                "--headless=new",
                "--disable-gpu",
                "--no-sandbox",
                "--hide-scrollbars",
                f"--window-size={vp_w},{vp_h}",
                "--force-device-scale-factor=2",
                f"--screenshot={png_out}",
                html_file.resolve().as_uri(),
            ]
            c_res = subprocess.run(cmd, capture_output=True, text=True)
            if c_res.returncode != 0 or not png_out.exists():
                print(f"[render] Chrome failed for {scene_name}: {c_res.stderr}", file=sys.stderr)
                return 1
            pw, ph = read_png_dimensions(png_out)
            size_kb = png_out.stat().st_size / 1024.0
            print(f"[render] {scene_name}.png -> {pw}x{ph} ({size_kb:.1f} KB, {len(scene_data.get('items', []))} primitives)")
            if (pw, ph) != (vp_w * 2, vp_h * 2):
                print(f"[render] ERROR: unexpected PNG dimensions {pw}x{ph} for {scene_name} (expected {vp_w * 2}x{vp_h * 2})", file=sys.stderr)
                return 1

    print("[render] All requested @2x previews rendered cleanly.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
