#!/usr/bin/env python
"""Build the WoW-ready Warcraft skin textures for MerchantMaster.

Generates Assets/skins/<skin>/*.blp (BLP2 DXT1/DXT5 with full mipmap chains)
for the 5 Warcraft skins (human, night_elf, orc, undead, goblin) from external
theme mockup assets passed via --themes-dir / MM_THEMES_DIR.

Run with a Python environment that has Pillow + numpy + scipy:
    python tools/build_skin_assets.py --themes-dir <THEMES_DIR> --send-btn-dir <CUTOUTS_DIR>
    python tools/build_skin_assets.py --verify            (header/alpha/aspect checks)
    python tools/build_skin_assets.py --skin goblin ...   (one skin)
    python tools/build_skin_assets.py --preview-dir DIR   (also write PNG previews)
    python tools/build_skin_assets.py --audit-png PATH    (write bright-bg transparency audit sheet)
"""
import argparse
import math
import os
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

RESAMPLE_LANCZOS = getattr(Image, "Resampling", Image).LANCZOS
ADDON = Path(__file__).resolve().parent.parent
OUT_ROOT = ADDON / "Assets" / "skins"
THEMES: Optional[Path] = Path(os.environ["MM_THEMES_DIR"]) if os.environ.get("MM_THEMES_DIR") else None
TGA_FOOTER = b"\x00" * 8 + b"TRUEVISION-XFILE.\x00"


def find_chrome_exe(override: Optional[Path] = None) -> Optional[Path]:
    if override is not None:
        return override
    for env_key in ("MM_CHROME_EXE", "CHROME_BIN"):
        val = os.environ.get(env_key, "").strip()
        if val:
            return Path(val)
    for name in ("chrome", "google-chrome", "chromium", "chromium-browser"):
        found = shutil.which(name)
        if found:
            return Path(found)
    candidates: List[Path] = []
    for env_dir in ("PROGRAMFILES", "PROGRAMFILES(X86)", "LOCALAPPDATA"):
        base = os.environ.get(env_dir, "").strip()
        if base:
            candidates.append(Path(base) / "Google" / "Chrome" / "Application" / "chrome.exe")
    candidates.append(Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"))
    for cand in candidates:
        if cand.is_file():
            return cand
    return None


CHROME_EXE: Optional[Path] = find_chrome_exe()

SKIN_DIRS = {
    "human": "13-race-human",
    "night_elf": "11-race-night-elf",
    "orc": "12-race-orc",
    "undead": "14-race-undead",
    "goblin": "23-goblin-trade-baron",
}
SKINS = ["human", "night_elf", "orc", "undead", "goblin"]

Color = Tuple[float, float, float, float]  # r,g,b 0..255, a 0..1
Stop = Tuple[float, Color]

# ---------------------------------------------------------------------------
# Per-skin recipes (values lifted from the 5 mockup index.html stylesheets)
# ---------------------------------------------------------------------------
CREST_SRC = {
    "night_elf": "warcraft_crest.png",
    "orc": "warcraft_crest.png",
    "undead": "warcraft_crest.png",
    "goblin": "warcraft_crest.png",
}
RAIL_SIZES = {  # (rail_h w,h), (rail_v w,h)
    "human": ((512, 128), (64, 512)),
    "night_elf": ((512, 64), (64, 512)),
    "orc": ((512, 128), (128, 512)),
    "undead": ((512, 64), (64, 512)),
    "goblin": ((256, 128), (128, 256)),
}
# Exact pre-POT native source dimensions (w, h) for rail_h and rail_v:
# human stone_beam is cropped to rows 0..71 (780x71 solid battlement band without hanging corner arches);
# human right_masonry is trimmed of its 2 empty outer columns (74x653).
HUMAN_BEAM_CROP_H = 71
HUMAN_MASONRY_X0 = 2
NATIVE_RAIL_DIMS = {  # skin -> ((rh_src_w, rh_src_h), (rv_src_w, rv_src_h))
    "human": ((780, HUMAN_BEAM_CROP_H), (76 - HUMAN_MASONRY_X0, 653)),
    "night_elf": ((846, 129), (129, 846)),
    "orc": ((996, 264), (264, 996)),
    "undead": ((1020, 120), (120, 1020)),
    "goblin": ((280, 142), (142, 280)),
}

# Exact sub-crop offsets (x0, y0) of warcraft_crest.png & warcraft_corner.png inside #000000-backed ai_*.png
AI_CUTOUT_OFFSETS = {
    ("night_elf", "crest"): (43, 123),
    ("night_elf", "corner"): (49, 43),
    ("orc", "crest"): (50, 153),
    ("orc", "corner"): (85, 67),
    ("undead", "crest"): (58, 134),
    ("undead", "corner"): (58, 58),
    ("goblin", "crest"): (31, 88),
    ("goblin", "corner"): (103, 103),
}

# Bounding zones (x0, y0, x1, y1, max_rgb_thresh_255) containing enclosed #000000 background pockets
POCKET_ZONES = {
    ("goblin", "corner"): [
        # Inner gold filigree scrollwork loops & triangles below the coins (outside solid L-bars)
        (175, 172, 460, 440, 26.0),
    ],
    ("goblin", "crest"): [
        # Left balance scale: behind post/curtain/coins, inside chain triangles, under pan, skeleton key bow
        (60, 190, 258, 402, 22.0),
        (75, 432, 138, 484, 24.0),
        # Right balance scale + skeleton key bow
        (1056, 190, 1254, 402, 22.0),
        (1176, 432, 1239, 484, 24.0),
    ],
    ("night_elf", "corner"): [
        # Vine loops along top bar, inner filigree tip, under bar, right of pillar, left hanging vine gap
        (350, 65, 620, 140, 24.0),
        (345, 262, 580, 415, 24.0),
        (232, 350, 310, 620, 24.0),
        (105, 420, 144, 490, 22.0),
    ],
    ("night_elf", "crest"): [
        # Around top wisps, between leaves below wisps, and around owl wingtips
        (260, 45, 400, 168, 22.0),
        (890, 45, 1030, 168, 22.0),
        (430, 35, 860, 245, 18.0),
    ],
    ("orc", "crest"): [
        # Left & right chain links and enclosed gaps between chains, spikes, and tusks
        (110, 130, 315, 315, 22.0),
        (962, 130, 1167, 315, 22.0),
    ],
    ("orc", "corner"): [],
    ("undead", "crest"): [
        # Symmetric gaps around left & right potion bottle necks / collar spikes / bat wing bones
        (395, 175, 485, 245, 22.0),
        (775, 175, 865, 245, 22.0),
    ],
    ("undead", "corner"): [
        # Top & left skeletal ribcage inter-rib slots + crossed bone gaps + 2 wing-to-ear gaps
        (212, 115, 418, 212, 22.0),
        (115, 212, 215, 418, 22.0),
        (120, 18, 182, 108, 22.0),
        (18, 120, 108, 182, 22.0),
    ],
}

PORTRAIT = {
    "human": "game_wc3_paladin.png",
    "night_elf": "game_wc3_moonwell.png",
    "orc": "game_wc3_thrall.png",
    "undead": "game_wc3_lich.png",
    "goblin": "game_goblin_merchant.png",
}
# surface: (source, glaze colour, glaze alpha, grain gain, brightness boost)
SURFACE = {
    "human": ("surface_tex.png", "#10141D", 0.86, 2.4, 1.15),
    "night_elf": ("ai_surface.png", "#0D1623", 0.84, 2.3, 1.1),
    "orc": ("ai_surface.png", "#130E0C", 0.82, 2.2, 1.1),
    "undead": ("ai_surface.png", "#0F131A", 0.85, 2.3, 1.1),
    "goblin": ("ai_surface.png", "#06120C", 0.70, 1.5, 1.35),
}
# sidebar: (source, top colour, bottom colour, top alpha, bottom alpha, gain)
# Uniform c0 == c1 and a0 == a1 so 1:1 ("REPEAT", "REPEAT") tiling has zero vertical cut seam.
SIDEBAR = {
    "human": ("secondary_tex.png", "#0E1B38", "#0E1B38", 0.68, 0.68, 1.00),
    "night_elf": ("ai_surface.png", "#17172A", "#17172A", 0.80, 0.80, 1.55),
    "orc": ("ai_surface.png", "#19100D", "#19100D", 0.83, 0.83, 1.55),
    "undead": ("ai_surface.png", "#0E1118", "#0E1118", 0.86, 0.86, 1.70),
    "goblin": ("ai_velvet.png", "#29050D", "#29050D", 0.57, 0.57, 1.20),
}
# header_tile: (source, tone colour, tone alpha, grain gain, brightness, heal_seams)
HEADER_TILE = {
    "human": ("secondary_tex.png", "#132446", 0.24, 1.15, 1.05, False),
    "night_elf": ("ai_surface.png", "#181328", 0.34, 1.45, 1.08, True),
    "orc": ("ai_surface.png", "#221310", 0.34, 1.45, 1.08, True),
    "undead": ("ai_surface.png", "#10151E", 0.36, 1.45, 1.06, True),
    "goblin": ("ai_velvet.png", "#29050C", 0.22, 1.28, 1.12, True),
}
TEXT_IVORY = (244, 239, 228)  # reference foreground used by the contrast report

# UI plates: header/panel/kpi are smooth translucent overlays (alpha ~0.74..0.90 + 2px metallic border)
# layered in Lua over 1:1 repeating header_tile.tga / surface.tga so grain NEVER stretches horizontally.
PLATES = {
    "human": {
        "tex": "secondary_tex.png", "kpi_tex": "surface_tex.png",
        "header": dict(bg="#132446", angle=180, stops=[(0, (47, 105, 204, .24)), (1, (10, 20, 42, .85))],
                       border="#8c6621", inset=(250, 216, 122, .25), alpha_range=(0.74, 0.88)),
        "panel": dict(bg="#132446", angle=180, stops=[(0, (35, 76, 148, .45)), (1, (15, 29, 58, .92))],
                      border="#8c6621", inset=(250, 216, 122, .18), alpha_range=(0.75, 0.90)),
        "kpi": dict(bg="#232833", angle=135, stops=[(0, (27, 69, 143, .22)), (.72, (16, 20, 29, .88)), (1, (16, 20, 29, .88))],
                    accent="#fad87a", border="#8a6420", alpha_range=(0.74, 0.89)),
        "nav": dict(bg="#132446", angle=90, stops=[(0, (227, 180, 72, .22)), (.18, (27, 69, 143, .72)), (1, (19, 36, 70, .92))],
                    accent="#fad87a", border="#e3b448"),
        "cta": dict(bg="#132446", angle=180, stops=[(0, (58, 116, 214, 1)), (.54, (27, 69, 143, 1)), (1, (15, 39, 80, 1))],
                    border="#e3b448", bevel=(250, 216, 122, .55), tex=None),
        "socket": dict(angle=135, stops=[(0, (255, 242, 178, 1)), (.48, (227, 180, 72, 1)), (1, (107, 71, 16, 1))],
                       outer="#0b0e16", inner=None),
    },
    "night_elf": {
        "tex": "ai_surface.png", "kpi_tex": "ai_surface.png",
        "header": dict(bg="#151122", angle=180, stops=[(0, (53, 41, 82, .72)), (1, (15, 22, 36, .92))],
                       border="#637794", inset=(103, 232, 249, .22), alpha_range=(0.74, 0.89)),
        "panel": dict(bg="#211a33", angle=90, stops=[(0, (49, 38, 79, .82)), (.55, (22, 44, 62, .86)), (1, (36, 29, 60, .88))],
                      border="#637794", inset=(103, 232, 249, .18), alpha_range=(0.76, 0.88)),
        "kpi": dict(bg="#142436", angle=135, stops=[(0, (46, 36, 74, .55)), (.65, (16, 30, 44, .88)), (1, (13, 23, 36, .95))],
                    accent="#67e8f9", border="#637794", alpha_range=(0.74, 0.90)),
        "nav": dict(bg="#111e2e", angle=90, stops=[(0, (40, 138, 85, .40)), (.45, (22, 62, 78, .78)), (1, (18, 33, 52, .94))],
                    accent="#67e8f9", border="#cfdbe8"),
        "cta": dict(bg="#1c5c3e", angle=180, stops=[(0, (48, 148, 96, .92)), (.54, (24, 92, 60, .95)), (1, (15, 62, 42, .98))],
                    border="#b8cce0", bevel=(190, 252, 232, .45), tex="ai_surface.png"),
        "socket": dict(angle=135, stops=[(0, (242, 248, 255, 1)), (.46, (156, 178, 204, 1)), (1, (76, 61, 112, 1))],
                       outer="#0b111c", inner=None),
    },
    "orc": {
        "tex": "ai_surface.png", "kpi_tex": "ai_surface.png",
        "header": dict(bg="#1c120f", angle=180, stops=[(0, (120, 24, 19, .42)), (.68, (28, 17, 14, .90)), (1, (17, 12, 10, .96))],
                       border="#7c5222", inset=(223, 166, 75, .24), alpha_range=(0.74, 0.90)),
        "panel": dict(bg="#281411", angle=90, stops=[(0, (132, 24, 19, .68)), (.55, (56, 20, 16, .88)), (1, (26, 16, 13, .94))],
                      border="#865923", inset=(255, 224, 178, .16), alpha_range=(0.74, 0.90)),
        "kpi": dict(bg="#1e1410", angle=135, stops=[(0, (138, 26, 20, .24)), (.72, (22, 16, 14, .88)), (1, (22, 16, 14, .88))],
                    accent="#dfa64b", border="#865923", alpha_range=(0.74, 0.89)),
        "nav": dict(bg="#271f1c", angle=90, stops=[(0, (176, 37, 30, .86)), (.58, (104, 19, 15, .90)), (1, (38, 17, 14, .95))],
                    accent="#dfa64b", border="#dfa64b"),
        "cta": dict(bg="#8e1914", angle=180, stops=[(0, (198, 44, 35, 1)), (.54, (142, 25, 20, 1)), (1, (92, 14, 11, 1))],
                    border="#e5ae52", bevel=(255, 226, 182, .42), tex=None),
        "socket": dict(angle=135, stops=[(0, (240, 190, 103, 1)), (.48, (143, 93, 34, 1)), (1, (60, 39, 18, 1))],
                       outer="#120c0a", inner=None),
    },
    "undead": {
        "tex": "ai_surface.png", "kpi_tex": "ai_surface.png",
        "header": dict(bg="#0d1117", angle=90, stops=[(0, (16, 21, 29, .92)), (.5, (25, 22, 36, .86)), (1, (16, 21, 29, .92))],
                       border="#3c4656", inset=(104, 245, 75, .18), alpha_range=(0.76, 0.89)),
        "panel": dict(bg="#1c2330", angle=90, stops=[(0, (28, 36, 48, .90)), (.55, (22, 26, 38, .88)), (1, (19, 28, 26, .90))],
                      border="#647184", inset=(230, 220, 198, .14), alpha_range=(0.76, 0.89)),
        "kpi": dict(bg="#141922", angle=135, stops=[(0, (28, 39, 36, .34)), (.72, (15, 19, 27, .90)), (1, (15, 19, 27, .90))],
                    accent="#68f54b", border="#4a5668", alpha_range=(0.74, 0.90)),
        "nav": dict(bg="#141922", angle=90, stops=[(0, (104, 245, 75, .18)), (.26, (28, 44, 34, .78)), (1, (18, 24, 34, .94))],
                    accent="#68f54b", border="#68f54b"),
        "cta": dict(bg="#1c4f18", angle=180, stops=[(0, (66, 152, 50, .92)), (.55, (28, 79, 24, .96)), (1, (18, 49, 16, .98))],
                    border="#78f25c", bevel=(206, 255, 194, .45), tex="ai_surface.png"),
        "socket": dict(angle=135, stops=[(0, (220, 208, 184, 1)), (.48, (104, 115, 133, 1)), (1, (34, 41, 54, 1))],
                       outer="#0c1017", inner=None),
    },
    "goblin": {
        "tex": "ai_velvet.png", "kpi_tex": "ai_surface.png",
        "header": dict(bg="#29050c", angle=90,
                       stops=[(0, (28, 4, 10, .78)), (.35, (92, 12, 28, .56)), (.5, (36, 5, 12, .88)),
                              (.65, (92, 12, 28, .56)), (1, (28, 4, 10, .78))],
                       border="#966d21", inset=(247, 213, 124, .34), alpha_range=(0.72, 0.88)),
        "panel": dict(bg="#5c0c1c", angle=90, stops=[(0, (52, 7, 16, .82)), (.5, (112, 16, 36, .68)), (1, (44, 6, 14, .86))],
                      border="#d4a23e", inset=(255, 224, 158, .25), alpha_range=(0.72, 0.86)),
        "kpi": dict(bg="#091c13", angle=180, stops=[(0, (133, 20, 42, .24)), (.36, (9, 28, 19, .84)), (1, (6, 18, 12, .94))],
                    accent="#f7d57c", border="#966d21", alpha_range=(0.72, 0.90)),
        "nav": dict(bg="#29050c", angle=90, stops=[(0, (46, 242, 143, .20)), (.22, (142, 22, 45, .84)), (1, (66, 9, 20, .94))],
                    accent="#2ef28f", border="#f7d57c"),
        "cta": dict(bg="#85142a", angle=180, stops=[(0, (168, 28, 56, .86)), (1, (88, 11, 27, .96))],
                    border="#f7d57c", bevel=(255, 232, 175, .42), tex="ai_velvet.png"),
        "socket": dict(angle=135, stops=[(0, (251, 226, 155, 1)), (.48, (200, 150, 50, 1)), (1, (84, 57, 10, 1))],
                       outer="#06120c", inner="#2ef28f"),
    },
}


# ---------------------------------------------------------------------------
# Low-level image helpers (float32 RGBA arrays, straight alpha, 0..1)
# ---------------------------------------------------------------------------
def hexc(h: str, a: float = 1.0) -> Color:
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def load_rgba(path: Path) -> np.ndarray:
    im = Image.open(path).convert("RGBA")
    return np.asarray(im, dtype=np.float32) / 255.0


def to_pil(arr: np.ndarray) -> Image.Image:
    return Image.fromarray(np.clip(np.rint(arr * 255.0), 0, 255).astype(np.uint8), "RGBA")


def resize(arr: np.ndarray, w: int, h: int) -> np.ndarray:
    """Alpha-correct (premultiplied) Lanczos resize."""
    im = to_pil(arr).convert("RGBa").resize((w, h), RESAMPLE_LANCZOS).convert("RGBA")
    return np.asarray(im, dtype=np.float32) / 255.0


def trim(arr: np.ndarray, thresh: float = 0.04) -> np.ndarray:
    ys, xs = np.where(arr[..., 3] > thresh)
    if len(xs) == 0:
        return arr
    return arr[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def contain(arr: np.ndarray, w: int, h: int) -> np.ndarray:
    """Aspect-preserving fit, centred on a transparent w x h canvas."""
    ah, aw = arr.shape[:2]
    s = min(w / aw, h / ah)
    nw, nh = max(1, int(round(aw * s))), max(1, int(round(ah * s)))
    small = resize(arr, nw, nh)
    out = np.zeros((h, w, 4), dtype=np.float32)
    x0, y0 = (w - nw) // 2, (h - nh) // 2
    out[y0:y0 + nh, x0:x0 + nw] = small
    return out


def top_fit_width(arr: np.ndarray, w: int, h: int) -> np.ndarray:
    """Aspect-preserving fit filling full width `w`, top-aligned at y=0..contentH (no vertical letterbox)."""
    ah, aw = arr.shape[:2]
    nh = max(1, min(h, int(round(w * float(ah) / float(aw)))))
    small = resize(arr, w, nh)
    # Guarantee bottom row of contentH stays above the verify alpha>8 threshold if visible content reaches nh-1
    out = np.zeros((h, w, 4), dtype=np.float32)
    out[0:nh, 0:w] = small
    return bleed_rgb(out, iters=12)


def over(dst: np.ndarray, src: np.ndarray) -> np.ndarray:
    """Porter-Duff src-over for straight-alpha arrays of identical shape."""
    sa = src[..., 3:4]
    da = dst[..., 3:4]
    oa = sa + da * (1.0 - sa)
    rgb = (src[..., :3] * sa + dst[..., :3] * da * (1.0 - sa)) / np.maximum(oa, 1e-6)
    return np.concatenate([np.clip(rgb, 0, 1), np.clip(oa, 0, 1)], axis=-1)


def paste(dst: np.ndarray, src: np.ndarray, x: int, y: int) -> np.ndarray:
    out = dst.copy()
    h, w = src.shape[:2]
    out[y:y + h, x:x + w] = over(out[y:y + h, x:x + w], src)
    return out


def bleed_rgb(arr: np.ndarray, iters: int = 8) -> np.ndarray:
    """Spread RGB of visible pixels into fully transparent ones (no dark halos when WoW filters)."""
    out = arr.copy()
    known = out[..., 3] > 0.004
    for _ in range(iters):
        if known.all():
            break
        acc = np.zeros(out.shape[:2] + (3,), dtype=np.float32)
        cnt = np.zeros(out.shape[:2], dtype=np.float32)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)):
            k = np.roll(np.roll(known, dy, 0), dx, 1)
            rgb = np.roll(np.roll(out[..., :3], dy, 0), dx, 1)
            acc += rgb * k[..., None]
            cnt += k
        fill = (~known) & (cnt > 0)
        out[..., :3][fill] = acc[fill] / cnt[fill][:, None]
        known = known | fill
    return out


def defringe_rgba(arr: np.ndarray, edge_iters: int = 2) -> np.ndarray:
    """Strip pale/white rembg matte fringes on semi-transparent edges by clamping toward interior RGB."""
    out = arr.copy()
    alpha = out[..., 3].copy()
    alpha[alpha < 0.035] = 0.0
    solid_in = alpha > 0.88
    if solid_in.any() and (~solid_in).any():
        # Propagate clean interior RGB outward across the 2-3px anti-aliased edge
        known = solid_in.copy()
        ref_rgb = np.where(known[..., None], out[..., :3], 0.0)
        for _ in range(edge_iters + 2):
            acc = np.zeros_like(ref_rgb)
            cnt = np.zeros(out.shape[:2], dtype=np.float32)
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)):
                k = np.roll(np.roll(known, dy, 0), dx, 1)
                c = np.roll(np.roll(ref_rgb, dy, 0), dx, 1)
                acc += c * k[..., None]
                cnt += k
            fill = (~known) & (cnt > 0)
            ref_rgb[fill] = acc[fill] / cnt[fill][:, None]
            known = known | fill
        semi = (alpha > 0.0) & (~solid_in)
        # Replace any artificially brightened edge RGB with the propagated interior colour
        brighter = out[..., :3].max(axis=-1) > (ref_rgb.max(axis=-1) + 0.03)
        replace = semi & brighter
        out[..., :3][replace] = ref_rgb[replace]
        # Slightly tighten wispy outer alpha fringe
        alpha[semi] = np.clip(alpha[semi] ** 1.2, 0.0, 1.0)
        alpha[alpha < 0.035] = 0.0
    out[..., 3] = alpha
    out[..., :3] = np.where(alpha[..., None] > 0.0, out[..., :3], 0.0)
    return bleed_rgb(out)


def clean_ai_cutout(skin: str, kind: str) -> np.ndarray:
    """Clean warcraft_<kind>.png using its aligned #000000-backed ai_<kind>.png + enclosed pocket removal."""
    a = assets_dir(skin)
    wc = load_rgba(a / ("warcraft_%s.png" % kind))
    ai_path = a / ("ai_%s.png" % kind)
    if not ai_path.exists() or (skin, kind) not in AI_CUTOUT_OFFSETS:
        return defringe_rgba(wc)

    ai_full = np.asarray(Image.open(ai_path).convert("RGB"), dtype=np.float32) / 255.0
    x0, y0 = AI_CUTOUT_OFFSETS[(skin, kind)]
    h, w = wc.shape[:2]
    ai = ai_full[y0:y0 + h, x0:x0 + w]  # exact 0.000-error crop premultiplied over #000000
    alpha = wc[..., 3].copy()
    max_ai = ai.max(axis=-1)
    min_ai = ai.min(axis=-1)
    sat_ai = max_ai - min_ai

    # 1. Remove low-alpha rembg dust & stranded near-black specks near outer silhouette
    alpha[alpha < 0.05] = 0.0
    dist_in = ndi.distance_transform_edt(alpha > 0.5)
    alpha[(dist_in < 8.0) & (max_ai < 0.048)] = 0.0

    # Strip blotchy rembg smoke clouds around Night Elf wisps/filigree where ai_rgb is dim ambient glow
    if skin == "night_elf":
        near_ext = dist_in < 14.0
        dim_smoke = near_ext & (max_ai < 0.24) & (sat_ai < 0.12)
        alpha[dim_smoke] = 0.0
        # Smooth translucent wisp glow proportional to true #000000 luminance
        wisp_glow = near_ext & (max_ai < 0.30)
        alpha[wisp_glow] = np.minimum(alpha[wisp_glow], np.clip((max_ai[wisp_glow] - 0.05) / 0.25, 0.0, 1.0))

    # 2. Cut out enclosed #000000 background pockets inside verified zones
    hole_mask = np.zeros((h, w), dtype=bool)
    for bx0, by0, bx1, by1, thr255 in POCKET_ZONES.get((skin, kind), []):
        thr = thr255 / 255.0
        sub_dark = (max_ai[by0:by1, bx0:bx1] < thr) & (alpha[by0:by1, bx0:bx1] > 0.05)
        lab, n = ndi.label(sub_dark)
        for i in range(1, n + 1):
            ys, xs = np.where(lab == i)
            if len(xs) >= 16 and float(np.percentile(max_ai[by0:by1, bx0:bx1][ys, xs], 20)) < (10.5 / 255.0):
                hole_mask[by0 + ys, bx0 + xs] = True
    alpha[hole_mask] = 0.0

    # Remove tiny isolated foreground specks (< 22 px) left over after clearing pockets/wisps
    fg_lab, fg_n = ndi.label(alpha > 0.06)
    for i in range(1, fg_n + 1):
        ys, xs = np.where(fg_lab == i)
        if len(xs) < 22:
            alpha[ys, xs] = 0.0

    # 3. Compute crisp 1-2px anti-aliased edge alpha against #000000 around outer & pocket boundaries
    core_min_bright = 0.24 if skin == "night_elf" else 0.0
    solid_core = (alpha > 0.86) & (~ndi.binary_dilation(alpha == 0.0, iterations=2))
    if core_min_bright > 0.0:
        solid_core = solid_core & ((dist_in >= 10.0) | (max_ai >= core_min_bright))

    core_max = np.where(solid_core, np.maximum(max_ai, 0.14), 0.0)
    num = ndi.gaussian_filter(core_max, sigma=2.2)
    den = ndi.gaussian_filter(solid_core.astype(np.float32), sigma=2.2)
    local_ref = np.clip(np.where(den > 1e-4, num / np.maximum(den, 1e-4), 0.25), 0.14, 0.85)

    ramp_alpha = np.clip((max_ai - 0.035) / np.maximum(local_ref - 0.035, 0.10), 0.0, 1.0)
    new_alpha = np.where(solid_core, 1.0, np.minimum(alpha, ramp_alpha))
    hole_rim = hole_mask & ndi.binary_dilation(solid_core, iterations=1)
    new_alpha = np.where(hole_rim, ramp_alpha * 0.85, new_alpha)
    new_alpha[new_alpha < 0.035] = 0.0

    # 4. Exact black-matte unpremultiplication: fg_rgb = ai / max(new_alpha, max_ai) -> ZERO white halo!
    denom = np.maximum(np.maximum(new_alpha, max_ai), 1e-4)[..., None]
    rgb = np.where(new_alpha[..., None] > 0.0, np.clip(ai / denom, 0.0, 1.0), 0.0)
    return bleed_rgb(np.concatenate([rgb, new_alpha[..., None]], axis=-1).astype(np.float32))


def solid(w: int, h: int, c: Color) -> np.ndarray:
    out = np.empty((h, w, 4), dtype=np.float32)
    out[..., 0], out[..., 1], out[..., 2], out[..., 3] = c[0] / 255, c[1] / 255, c[2] / 255, c[3]
    return out


def css_gradient(w: int, h: int, angle: float, stops: Sequence[Stop]) -> np.ndarray:
    """CSS linear-gradient (premultiplied interpolation) rendered into an RGBA array."""
    a = math.radians(angle)
    dx, dy = math.sin(a), -math.cos(a)
    length = abs(w * dx) + abs(h * dy)
    xs = (np.arange(w, dtype=np.float32) + 0.5) - w / 2.0
    ys = (np.arange(h, dtype=np.float32) + 0.5) - h / 2.0
    t = (xs[None, :] * dx + ys[:, None] * dy) / length + 0.5
    t = np.clip(t, 0.0, 1.0)
    pos = [s[0] for s in stops]
    chans = []
    for i in range(4):
        vals = []
        for _, c in stops:
            if i < 3:
                vals.append(c[i] / 255.0 * c[3])  # premultiplied
            else:
                vals.append(c[3])
        chans.append(np.interp(t, pos, vals).astype(np.float32))
    al = chans[3]
    rgb = np.stack(chans[:3], axis=-1) / np.maximum(al[..., None], 1e-6)
    return np.concatenate([np.clip(rgb, 0, 1), al[..., None]], axis=-1)


def tile_texture(tex: np.ndarray, w: int, h: int, tile: int) -> np.ndarray:
    t = resize(tex, tile, tile)
    reps_y, reps_x = -(-h // tile), -(-w // tile)
    big = np.tile(t, (reps_y, reps_x, 1))
    out = big[:h, :w].copy()
    out[..., 3] = 1.0
    return out


def seam_ratio(arr: np.ndarray) -> float:
    """Wrap-seam error relative to the mean neighbour error (1.0 == seamless)."""
    rgb = arr[..., :3]
    wrap = (np.abs(rgb[:, 0] - rgb[:, -1]).mean() + np.abs(rgb[0] - rgb[-1]).mean()) / 2.0
    inner = (np.abs(rgb[:, 1:] - rgb[:, :-1]).mean() + np.abs(rgb[1:] - rgb[:-1]).mean()) / 2.0
    return float(wrap / max(inner, 1e-6))


def seam_ratio_xy(arr: np.ndarray) -> Tuple[float, float]:
    """Horizontal (left-right) and vertical (top-bottom) wrap-seam ratios (1.0 == seamless)."""
    rgb = arr[..., :3]
    wx = float(np.abs(rgb[:, 0] - rgb[:, -1]).mean())
    wy = float(np.abs(rgb[0, :] - rgb[-1, :]).mean())
    ix = float(np.abs(rgb[:, 1:] - rgb[:, :-1]).mean())
    iy = float(np.abs(rgb[1:, :] - rgb[:-1, :]).mean())
    return float(wx / max(ix, 1e-6)), float(wy / max(iy, 1e-6))


def resize_periodic(arr: np.ndarray, size: int) -> np.ndarray:
    """Wrap-padded Lanczos resize for periodic lattices (avoids clamped edge seams)."""
    h, w = arr.shape[:2]
    pad = max(8, w // 16)
    padded = np.pad(arr, ((pad, pad), (pad, pad), (0, 0)), mode="wrap")
    sw = int(round((w + 2 * pad) * (size / float(w))))
    sh = int(round((h + 2 * pad) * (size / float(h))))
    up = resize(padded, sw, sh)
    ox, oy = (sw - size) // 2, (sh - size) // 2
    return up[oy:oy + size, ox:ox + size]


def heal_seams(arr: np.ndarray, band: int = 28) -> np.ndarray:
    """Cross-fade the outer `band` px with the half-shifted image so the tile wraps without a seam."""
    h, w = arr.shape[:2]
    shifted = np.roll(np.roll(arr, h // 2, 0), w // 2, 1)

    def ramp(n: int) -> np.ndarray:
        d = np.minimum(np.arange(n), np.arange(n)[::-1]).astype(np.float32)
        return np.clip(d / band, 0, 1) ** 1.0

    m = (ramp(h)[:, None] * ramp(w)[None, :])[..., None]
    m = m * m * (3 - 2 * m)
    return arr * m + shifted * (1 - m)


def prepare_tile(src: Path, size: int, gain: float, bright: float = 1.0, force_heal: bool = False) -> np.ndarray:
    tex = load_rgba(src)
    tex[..., 3] = 1.0
    tex = resize(tex, size, size)
    ratio = seam_ratio(tex)
    if force_heal or ratio > 1.8:
        tex = heal_seams(tex, band=max(16, size // 9))
    mean = tex[..., :3].reshape(-1, 3).mean(axis=0)
    tex[..., :3] = np.clip((mean + (tex[..., :3] - mean) * gain) * bright, 0, 1)
    return tex


def glaze(tex: np.ndarray, top: Color, bottom: Color, top_a: float, bottom_a: float) -> np.ndarray:
    h, w = tex.shape[:2]
    t = np.linspace(0, 1, h, dtype=np.float32)[:, None, None]
    c0 = np.array(top[:3], dtype=np.float32) / 255.0
    c1 = np.array(bottom[:3], dtype=np.float32) / 255.0
    col = c0 * (1 - t) + c1 * t
    a = top_a * (1 - t) + bottom_a * t
    rgb = tex[..., :3] * (1 - a) + col * a
    return np.concatenate([np.clip(rgb, 0, 1), np.ones((h, w, 1), dtype=np.float32)], axis=-1)


def saturate(rgb: np.ndarray, s: float) -> np.ndarray:
    lum = rgb @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    return np.clip(lum[..., None] + (rgb - lum[..., None]) * s, 0, 1)


def sepia(rgb: np.ndarray, amt: float) -> np.ndarray:
    m = np.array([
        [0.393, 0.769, 0.189],
        [0.349, 0.686, 0.168],
        [0.272, 0.534, 0.131],
    ], dtype=np.float32)
    full = np.clip(rgb @ m.T, 0, 1)
    return rgb * (1 - amt) + full * amt


def rel_lum(rgb: Sequence[float]) -> float:
    def lin(c: float) -> float:
        c = c / 255.0
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    return 0.2126 * lin(rgb[0]) + 0.7152 * lin(rgb[1]) + 0.0722 * lin(rgb[2])


# ---------------------------------------------------------------------------
# TGA writer / reader
# ---------------------------------------------------------------------------
OPAQUE_BLP_ASSETS = {"surface", "sidebar_bg", "header_tile", "portrait", "nav_active", "cta_bg"}


def _rgb888_to_565(rgb: np.ndarray) -> np.ndarray:
    r = (rgb[..., 0].astype(np.uint16) * 31 + 127) // 255
    g = (rgb[..., 1].astype(np.uint16) * 63 + 127) // 255
    b = (rgb[..., 2].astype(np.uint16) * 31 + 127) // 255
    return (r << 11) | (g << 5) | b


def _rgb565_to_888(c565: np.ndarray) -> np.ndarray:
    r = ((c565 >> 11) & 31).astype(np.float32)
    g = ((c565 >> 5) & 63).astype(np.float32)
    b = (c565 & 31).astype(np.float32)
    r = np.floor(r * 255.0 / 31.0 + 0.5)
    g = np.floor(g * 255.0 / 63.0 + 0.5)
    b = np.floor(b * 255.0 / 31.0 + 0.5)
    return np.stack([r, g, b], axis=-1)


def _encode_dxt_blocks(rgba: np.ndarray, with_alpha: bool) -> bytes:
    """Vectorized BC1 (DXT1, 8B/block) or BC3 (DXT5, 16B/block) encoder."""
    h, w, _ = rgba.shape
    ph = max(4, ((h + 3) // 4) * 4)
    pw = max(4, ((w + 3) // 4) * 4)
    if ph != h or pw != w:
        rgba = np.pad(rgba, ((0, ph - h), (0, pw - w), (0, 0)), mode="edge")
    bh, bw = ph // 4, pw // 4
    blocks = rgba.reshape(bh, 4, bw, 4, 4).transpose(0, 2, 1, 3, 4).reshape(-1, 16, 4)
    n_blk = blocks.shape[0]

    rgb = blocks[..., :3].astype(np.float32)
    cmin = rgb.min(axis=1)
    cmax = rgb.max(axis=1)
    inset = (cmax - cmin) * (1.0 / 16.0)
    ep0 = np.clip(np.rint(cmax - inset), 0, 255).astype(np.uint8)
    ep1 = np.clip(np.rint(cmin + inset), 0, 255).astype(np.uint8)
    c0 = _rgb888_to_565(ep0)
    c1 = _rgb888_to_565(ep1)
    swap = c0 < c1
    c0, c1 = np.where(swap, c1, c0), np.where(swap, c0, c1)
    # Guarantee 4-color mode (c0 > c1) unless block is completely flat
    same = c0 == c1
    p0 = _rgb565_to_888(c0)
    p1 = _rgb565_to_888(c1)
    p2 = (2.0 * p0 + p1) / 3.0
    p3 = (p0 + 2.0 * p1) / 3.0
    pal = np.stack([p0, p1, p2, p3], axis=1)  # (N, 4, 3)
    diff = rgb[:, :, None, :] - pal[:, None, :, :]
    dist = (diff * diff).sum(axis=-1)  # (N, 16, 4)
    idx = np.argmin(dist, axis=-1).astype(np.uint32)  # (N, 16)
    idx[same] = 0
    shifts = (np.arange(16, dtype=np.uint32) * 2)[None, :]
    bits = np.bitwise_or.reduce(idx << shifts, axis=1)

    rgb_out = np.empty((n_blk, 8), dtype=np.uint8)
    rgb_out[:, 0] = c0 & 0xFF
    rgb_out[:, 1] = (c0 >> 8) & 0xFF
    rgb_out[:, 2] = c1 & 0xFF
    rgb_out[:, 3] = (c1 >> 8) & 0xFF
    rgb_out[:, 4] = bits & 0xFF
    rgb_out[:, 5] = (bits >> 8) & 0xFF
    rgb_out[:, 6] = (bits >> 16) & 0xFF
    rgb_out[:, 7] = (bits >> 24) & 0xFF

    if not with_alpha:
        return rgb_out.tobytes()

    a = blocks[..., 3].astype(np.uint8)
    a0 = a.max(axis=1)
    a1 = a.min(axis=1)
    a_same = a0 == a1
    a0f = a0.astype(np.float32)
    a1f = a1.astype(np.float32)
    apal = np.stack(
        [
            a0f,
            a1f,
            (6.0 * a0f + 1.0 * a1f) / 7.0,
            (5.0 * a0f + 2.0 * a1f) / 7.0,
            (4.0 * a0f + 3.0 * a1f) / 7.0,
            (3.0 * a0f + 4.0 * a1f) / 7.0,
            (2.0 * a0f + 5.0 * a1f) / 7.0,
            (1.0 * a0f + 6.0 * a1f) / 7.0,
        ],
        axis=1,
    )  # (N, 8)
    adiff = np.abs(a[:, :, None].astype(np.float32) - apal[:, None, :])
    aidx = np.argmin(adiff, axis=-1).astype(np.uint64)  # (N, 16)
    aidx[a_same] = 0
    ashifts = (np.arange(16, dtype=np.uint64) * 3)[None, :]
    abits = np.bitwise_or.reduce(aidx << ashifts, axis=1)

    out = np.empty((n_blk, 16), dtype=np.uint8)
    out[:, 0] = a0
    out[:, 1] = a1
    for b_i in range(6):
        out[:, 2 + b_i] = ((abits >> np.uint64(8 * b_i)) & np.uint64(0xFF)).astype(np.uint8)
    out[:, 8:] = rgb_out
    return out.tobytes()


def write_blp2(path: Path, arr: np.ndarray, opaque: bool = False) -> None:
    """Write WoW-native BLP2 (DXT1 opaque or DXT5 RGBA) with full mipmap chain down to 1x1."""
    h, w = arr.shape[:2]
    if w & (w - 1) or h & (h - 1) or w > 1024 or h > 1024:
        raise ValueError("%s: %dx%d is not power-of-2 <= 1024" % (path.name, w, h))
    px = np.clip(np.rint(arr * 255.0), 0, 255).astype(np.uint8)
    if opaque:
        px[..., 3] = 255
    im = Image.fromarray(px, "RGBA")
    mips: List[bytes] = []
    mw, mh = w, h
    while True:
        cur = np.asarray(im if (mw == w and mh == h) else im.resize((mw, mh), RESAMPLE_LANCZOS))
        mips.append(_encode_dxt_blocks(cur, with_alpha=(not opaque)))
        if mw == 1 and mh == 1:
            break
        mw = max(1, mw // 2)
        mh = max(1, mh // 2)

    offsets = [0] * 16
    lengths = [0] * 16
    cur_off = 148 + 1024  # 148-byte BLP2 header + 1024-byte palette table
    for i, mdata in enumerate(mips[:16]):
        offsets[i] = cur_off
        lengths[i] = len(mdata)
        cur_off += len(mdata)

    alpha_depth = 0 if opaque else 8
    alpha_enc = 0 if opaque else 7
    header = struct.pack(
        "<4sIBBBBII16I16I",
        b"BLP2",
        1,
        2,
        alpha_depth,
        alpha_enc,
        1,
        w,
        h,
        *offsets,
        *lengths,
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(header + (b"\x00" * 1024) + b"".join(mips[:16]))


def read_blp2(path: Path) -> Tuple[int, int, np.ndarray]:
    data = path.read_bytes()
    if len(data) < 1172 or data[:4] != b"BLP2":
        raise ValueError("%s: bad BLP2 magic or length" % path.name)
    btype, enc, adepth, aenc, has_mips, w, h = struct.unpack_from("<IBBBBII", data, 4)
    if btype != 1 or enc != 2 or aenc not in (0, 7):
        raise ValueError("%s: bad BLP2 encoding (type=%d enc=%d aenc=%d)" % (path.name, btype, enc, aenc))
    with Image.open(path) as im:
        rgba = np.asarray(im.convert("RGBA"), dtype=np.uint8)
    return w, h, rgba


def write_tga(path: Path, arr: np.ndarray) -> None:
    """Uncompressed 32-bit BGRA, type=2, descriptor=0x08 (bottom-left origin), TGA 2.0 footer."""
    h, w = arr.shape[:2]
    if w & (w - 1) or h & (h - 1) or w > 1024 or h > 1024:
        raise ValueError("%s: %dx%d is not power-of-2 <= 1024" % (path.name, w, h))
    px = np.clip(np.rint(arr * 255.0), 0, 255).astype(np.uint8)
    bgra = px[::-1, :, [2, 1, 0, 3]]  # bottom row first, RGBA -> BGRA
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 0x08)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(header + np.ascontiguousarray(bgra).tobytes() + TGA_FOOTER)


def read_tga(path: Path) -> Tuple[int, int, np.ndarray]:
    data = path.read_bytes()
    id_len, cmap, itype, _, _, _, _, _, w, h, bpp, desc = struct.unpack("<BBBHHBHHHHBB", data[:18])
    if id_len != 0 or cmap != 0 or itype != 2 or bpp != 32 or desc != 0x08:
        raise ValueError("%s: bad header (type=%d bpp=%d desc=0x%02x)" % (path.name, itype, bpp, desc))
    if len(data) != 18 + w * h * 4 + 26 or data[-26:] != TGA_FOOTER:
        raise ValueError("%s: bad length or missing TGA 2.0 footer" % path.name)
    px = np.frombuffer(data, dtype=np.uint8, count=w * h * 4, offset=18).reshape(h, w, 4)
    rgba = px[::-1, :, [2, 1, 0, 3]]  # back to top-down RGBA
    return w, h, rgba


# ---------------------------------------------------------------------------
# Chrome SVG rasterizer (difference matting on black/white -> crisp alpha)
# ---------------------------------------------------------------------------
def _chrome_shot(html: Path, out_png: Path, size: int, profile: Path) -> None:
    if CHROME_EXE is None or not CHROME_EXE.exists():
        raise FileNotFoundError("Chrome executable not found (pass --chrome-exe or set CHROME_BIN)")
    cmd = [
        str(CHROME_EXE), "--headless=new", "--disable-gpu", "--hide-scrollbars",
        "--force-device-scale-factor=1", "--window-size=%d,%d" % (size, size),
        "--user-data-dir=%s" % profile, "--screenshot=%s" % out_png,
        "--virtual-time-budget=2000", html.as_uri(),
    ]
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=90, check=False)
    if not out_png.exists():
        raise RuntimeError("Chrome produced no screenshot for %s" % html.name)


def rasterize_svg(svg: Path, size: int) -> np.ndarray:
    if CHROME_EXE is None or not CHROME_EXE.exists():
        raise FileNotFoundError("Chrome executable not found (pass --chrome-exe or set CHROME_BIN)")
    shots: Dict[str, np.ndarray] = {}
    with tempfile.TemporaryDirectory(prefix="mm_skin_svg_") as tmp:
        tmpd = Path(tmp)
        for name, bg in (("black", "#000000"), ("white", "#ffffff")):
            html = tmpd / (name + ".html")
            html.write_text(
                '<!doctype html><html><body style="margin:0;background:%s;overflow:hidden">'
                '<img src="%s" width="%d" height="%d" style="display:block"></body></html>'
                % (bg, svg.as_uri(), size, size), encoding="utf-8")
            png = tmpd / (name + ".png")
            _chrome_shot(html, png, size, tmpd / ("profile_" + name))
            im = Image.open(png).convert("RGB")
            if im.size[0] < size or im.size[1] < size:
                raise RuntimeError("Chrome screenshot too small: %s" % (im.size,))
            shots[name] = np.asarray(im.crop((0, 0, size, size)), dtype=np.float32) / 255.0
    b, w = shots["black"], shots["white"]
    alpha = np.clip(1.0 - (w - b).mean(axis=-1), 0, 1)
    rgb = np.where(alpha[..., None] > 0.003, b / np.maximum(alpha[..., None], 1e-3), 0.0)
    alpha[alpha < 0.012] = 0.0  # kill matte noise
    return np.concatenate([np.clip(rgb, 0, 1), alpha[..., None]], axis=-1).astype(np.float32)


# ---------------------------------------------------------------------------
# Asset builders
# ---------------------------------------------------------------------------
def assets_dir(skin: str) -> Path:
    if THEMES is None:
        raise FileNotFoundError("Theme assets directory not configured (pass --themes-dir or set MM_THEMES_DIR)")
    return THEMES / SKIN_DIRS[skin] / "assets"


DRAGON_HOLE_C = (255.5, 90.5)   # centre of the black glass gem inside the gold ring (source px)
DRAGON_HOLE_R = 51.0            # inner edge of the gold ring (source px)
MEDALLION_R = 54.5              # sapphire disc tucks just under the gold ring


def clean_dragon(dragon: np.ndarray) -> np.ndarray:
    """Remove HUD end-bars + divider stubs at the octagonal stone end-caps and cut the gem hole out of the ring."""
    out = dragon.copy()
    h, w = out.shape[:2]
    # Trim outside the sculpted octagonal stone end-caps (x=22..495) so no HUD divider stubs stick out
    out[:, :22, 3] = 0.0
    out[:, 495:, 3] = 0.0
    # Clear dark HUD background wedges touching the outer octagonal stone chamfers
    dark = (out[..., :3].max(axis=-1) < 0.045) & (out[..., 3] > 0.2)
    lab, n = ndi.label(dark)
    for i in range(1, n + 1):
        ys, xs = np.where(lab == i)
        if (xs.min() <= 24) or (xs.max() >= 493):
            out[ys, xs, 3] = 0.0
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    dist = np.sqrt((xx + 0.5 - DRAGON_HOLE_C[0]) ** 2 + (yy + 0.5 - DRAGON_HOLE_C[1]) ** 2)
    out[..., 3] *= np.clip(dist - DRAGON_HOLE_R + 0.5, 0, 1)    # transparent hole, 1px AA edge
    return defringe_rgba(out)


def _trimmed_crest(skin: str) -> np.ndarray:
    """Return the cleaned, trimmed crest RGBA array in native source aspect before POT placement."""
    if skin == "human":
        a = assets_dir("human")
        ss = 3
        dragon = clean_dragon(load_rgba(a / "game_wc3_crop_dragon_crest.png"))
        dh, dw = dragon.shape[:2]
        # Flip the stone dragon bezel vertically (mirror across horizontal axis) so the
        # dragons sit right-side up while keeping the center Paladin shield upright.
        dragon = dragon[::-1].copy()
        W, H = dw * ss, dh * ss
        cx, cy = DRAGON_HOLE_C[0] * ss, (dh - DRAGON_HOLE_C[1]) * ss
        rad = MEDALLION_R * ss
        css = dh / 98.0 * ss            # one mockup css px in supersampled texels
        layer = np.zeros((H, W, 4), dtype=np.float32)

        yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
        xx += 0.5
        yy += 0.5
        dist = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
        # Fill circular medallion with woven royal-blue Alliance banner cloth from game_wc3_banner.png
        # instead of a plain synthetic blue gradient, keeping soft vignette depth + gold bezel rim.
        banner = load_rgba(a / "game_wc3_banner.png")
        bh, bw = banner.shape[:2]
        cloth = banner[int(bh * 0.16):int(bh * 0.56), int(bw * 0.20):int(bw * 0.80), :3]
        disc_sz = int(round(2 * rad)) + 4
        cloth_sq = resize(np.concatenate([cloth, np.ones((*cloth.shape[:2], 1), dtype=np.float32)], axis=-1), disc_sz, disc_sz)[..., :3]
        core = np.zeros((H, W, 3), dtype=np.float32)
        ox = int(round(cx - disc_sz / 2.0))
        oy = int(round(cy - disc_sz / 2.0))
        y0, y1 = max(0, oy), min(H, oy + disc_sz)
        x0, x1 = max(0, ox), min(W, ox + disc_sz)
        core[y0:y1, x0:x1] = cloth_sq[y0 - oy:y1 - oy, x0 - ox:x1 - ox]
        # Subtle royal-blue highlight top-left and dark recessed rim vignette so the upright Paladin crest pops
        gx, gy = cx - rad * 0.25, cy - rad * 0.28
        gd = np.clip(np.sqrt((xx - gx) ** 2 + (yy - gy) ** 2) / (rad * 1.45), 0.0, 1.0)
        shade = (1.18 - 0.52 * (gd ** 1.6))[..., None]
        core = np.clip(core * shade, 0.0, 1.0)
        inner_d = (rad - dist) / css
        rim_shadow = np.clip(inner_d / 4.5, 0.45, 1.0)[..., None]
        core = np.clip(core * rim_shadow, 0.0, 1.0)
        gold = np.array([250, 216, 122], dtype=np.float32) / 255.0
        ring_t = np.clip((dist - (rad - 1.5 * css)) / ss + 0.5, 0, 1)[..., None]
        disc_rgb = core * (1 - ring_t) + gold * ring_t
        cover = np.clip((rad - dist) / ss + 0.5, 0, 1)
        layer = over(layer, np.concatenate([disc_rgb, cover[..., None]], axis=-1).astype(np.float32))

        dres = resize(dragon, W, H)
        layer = over(layer, dres)

        icon = defringe_rgba(load_rgba(a / "game_wc3_raceicon.png"))
        ih, iw = icon.shape[:2]
        s = min(42.0 / iw, 48.0 / ih) * css * 0.92      # mockup 42x48 box, 8% smaller to sit inside the ring
        inw, inh = int(round(iw * s)), int(round(ih * s))
        ires = resize(icon, inw, inh)
        layer = paste(layer, ires, int(round(cx - inw / 2.0)), int(round(cy - inh / 2.0)))

        small = bleed_rgb(resize(layer, dw, dh))
        return trim(small)
    return trim(clean_ai_cutout(skin, "crest"))


def build_crest(skin: str) -> np.ndarray:
    """Scale trimmed crest to full 256 width, top-aligned at y=0..contentH inside 256x128 with bleed_rgb."""
    return top_fit_width(_trimmed_crest(skin), 256, 128)


def build_corner(skin: str) -> np.ndarray:
    a = assets_dir(skin)
    if skin == "human":
        arr = rasterize_svg(a / "corner_piece.svg", 256)
        return bleed_rgb(arr)
    cleaned = clean_ai_cutout(skin, "corner")
    return bleed_rgb(resize(trim(cleaned), 256, 256))


def build_rails(skin: str) -> Tuple[np.ndarray, np.ndarray]:
    a = assets_dir(skin)
    (hw, hh), (vw, vh) = RAIL_SIZES[skin]
    if skin == "human":
        beam_src = defringe_rgba(load_rgba(a / "game_wc3_crop_stone_beam.png")[:HUMAN_BEAM_CROP_H, :, :])
        masonry_src = defringe_rgba(load_rgba(a / "game_wc3_crop_right_masonry.png")[:, HUMAN_MASONRY_X0:, :])
        rh = resize(beam_src, hw, hh)
        rv = resize(masonry_src, vw, vh)
        rv[..., :3] = np.clip(saturate(rv[..., :3], 0.30) * 0.96, 0, 1)   # .wc3-side-pillar filter
    elif skin == "goblin":
        rh = resize(load_rgba(a / "warcraft_rail_h.png"), hw, hh)
        rv = resize(load_rgba(a / "warcraft_rail_v.png"), vw, vh)
    else:
        rh = resize(defringe_rgba(load_rgba(a / "warcraft_rail_h.png")), hw, hh)
        rv = resize(defringe_rgba(load_rgba(a / "warcraft_rail_v.png")), vw, vh)
    return bleed_rgb(rh), bleed_rgb(rv)


def build_banner() -> np.ndarray:
    src = load_rgba(assets_dir("human") / "game_wc3_banner.png")
    src[..., 3] = np.where(src[..., 3] < 0.02, 0.0, src[..., 3])
    return bleed_rgb(contain(trim(src, 0.02), 128, 256))


def build_surface(skin: str) -> np.ndarray:
    src, col, alpha, gain, bright = SURFACE[skin]
    tex = prepare_tile(assets_dir(skin) / src, 512, gain, bright)
    c = hexc(col)
    return glaze(tex, c, c, alpha, alpha)


def build_sidebar(skin: str) -> np.ndarray:
    src, c0, c1, a0, a1, gain = SIDEBAR[skin]
    if c0.lower() != c1.lower() or abs(a0 - a1) > 1e-6:
        raise ValueError("%s/sidebar_bg requires uniform glaze (c0==c1, a0==a1) for REPEAT tiling" % skin)
    if skin == "human":
        tex = load_rgba(assets_dir(skin) / src)
        tex[..., 3] = 1.0
        tex = resize_periodic(tex, 512)   # 256px source upscaled 2x with periodic wrap, keeps diamond lattice
    else:
        tex = prepare_tile(assets_dir(skin) / src, 512, gain, force_heal=True)
    col = hexc(c0)
    return glaze(tex, col, col, a0, a0)


def build_header_tile(skin: str) -> np.ndarray:
    """Seamless 256x256 square header_tile.tga (PLATES[skin]['tex'], seam-healed and softly toned)."""
    src, col, alpha, gain, bright, force_heal = HEADER_TILE[skin]
    tex = prepare_tile(assets_dir(skin) / src, 256, gain, bright, force_heal=force_heal)
    c = hexc(col)
    return glaze(tex, c, c, alpha, alpha)


def build_square_icon(skin: str, name: str) -> np.ndarray:
    arr = load_rgba(assets_dir(skin) / name)
    if float(arr[..., 3].min()) < 0.99:
        arr = defringe_rgba(arr)
    return bleed_rgb(contain(arr, 128, 128))


def _base_plate(skin: str, w: int, h: int, spec: dict, tile: int, tex_key: str = "tex",
                tex_override: Optional[str] = None) -> np.ndarray:
    """Opaque textured plate (used for small fixed-width widgets like nav_active and cta_bg)."""
    name = tex_override or PLATES[skin][tex_key]
    tex = load_rgba(assets_dir(skin) / name)
    tex[..., 3] = 1.0
    base = solid(w, h, hexc(spec["bg"]))
    base = over(base, tile_texture(tex, w, h, tile))
    grad = css_gradient(w, h, spec["angle"], spec["stops"])
    return over(base, grad)


def _translucent_plate(w: int, h: int, spec: dict) -> np.ndarray:
    """Smooth translucent gradient overlay WITHOUT baked repeating pattern texture.

    Preserves exact CSS colour stops while mapping alpha into spec['alpha_range'] (~0.72..0.90) so the
    1:1 REPEAT header_tile / surface underneath shows through crisply at any window width.
    """
    full = over(solid(w, h, hexc(spec["bg"], 1.0)), css_gradient(w, h, spec["angle"], spec["stops"]))
    grad = css_gradient(w, h, spec["angle"], spec["stops"])
    ga = grad[..., 3]
    g_min, g_max = float(ga.min()), float(ga.max())
    a_lo, a_hi = spec.get("alpha_range", (0.74, 0.90))
    if g_max - g_min > 1e-4:
        norm = (ga - g_min) / (g_max - g_min)
    else:
        norm = np.full_like(ga, 0.5)
    alpha = (a_lo + (a_hi - a_lo) * norm).astype(np.float32)
    return np.concatenate([full[..., :3], alpha[..., None]], axis=-1)


def _hline(plate: np.ndarray, y0: int, y1: int, c: Color) -> np.ndarray:
    ov = np.zeros_like(plate)
    ov[y0:y1, :, :3] = np.array(c[:3], dtype=np.float32) / 255.0
    ov[y0:y1, :, 3] = c[3]
    return over(plate, ov)


def _metal_edge(plate: np.ndarray, rows: int, color: str, from_bottom: bool = True) -> np.ndarray:
    """`rows`-texel metallic edge: bright top row fading to the dark base metal."""
    h = plate.shape[0]
    base = np.array(hexc(color)[:3], dtype=np.float32) / 255.0
    out = plate
    for i in range(rows):
        k = i / max(rows - 1, 1)
        shade = base * (1.15 - 0.45 * k) + (1.0 - base) * (0.18 * (1 - k))
        y = h - rows + i if from_bottom else i
        out = _hline(out, y, y + 1, (*np.clip(shade * 255, 0, 255), 1.0))
    return out


def build_header_bg(skin: str) -> np.ndarray:
    sp = PLATES[skin]["header"]
    w, h = 256, 64
    p = _translucent_plate(w, h, sp)
    p = _hline(p, 0, 1, (255, 255, 255, 0.10))                        # 1px inner sheen
    p = _hline(p, h - 4, h - 2, (*sp["inset"][:3], sp["inset"][3]))   # inset -1px glow above the border
    p = _metal_edge(p, 2, sp["border"])                               # 2px metallic bottom edge
    return p


def build_panel_hdr(skin: str) -> np.ndarray:
    sp = PLATES[skin]["panel"]
    w, h = 256, 64
    p = _translucent_plate(w, h, sp)
    p = _hline(p, 0, 2, (*sp["inset"][:3], sp["inset"][3]))           # top bevel highlight
    p = _metal_edge(p, 2, sp["border"])                               # 2px metallic bottom border
    return p


def build_kpi_bg(skin: str) -> np.ndarray:
    sp = PLATES[skin]["kpi"]
    w, h = 256, 128
    p = _translucent_plate(w, h, sp)
    acc = np.array(hexc(sp["accent"])[:3], dtype=np.float32) / 255.0
    xs = (np.arange(w, dtype=np.float32) + 0.5) / w
    fade = np.clip(np.minimum(xs, 1 - xs) / 0.10, 0, 1) ** 0.8        # accent bar fades at both ends
    bar = np.zeros((h, w, 4), dtype=np.float32)
    bar[0:3, :, :3] = acc
    bar[0:3, :, 3] = np.stack([fade, fade, fade * 0.8])               # 3 texel accent bar, last row softer
    p = over(p, bar)
    glow = np.zeros((h, w, 4), dtype=np.float32)
    for i in range(3, 12):                                            # soft glow under the accent bar
        glow[i, :, :3] = acc
        glow[i, :, 3] = fade * 0.22 * (1 - (i - 3) / 9.0) ** 2
    p = over(p, glow)
    p = _hline(p, 3, 4, (255, 255, 255, 0.08))                        # highlight sheen
    p = _metal_edge(p, 2, sp["border"])                               # 2px metallic bottom border
    return p


def build_nav_active(skin: str) -> np.ndarray:
    sp = PLATES[skin]["nav"]
    w, h = 256, 64
    p = _base_plate(skin, w, h, sp, 64)
    bc = hexc(sp["border"])
    p = _hline(p, 0, 2, (*bc[:3], 0.45))                              # 1px top/bottom hairlines
    p = _hline(p, h - 2, h, (*bc[:3], 0.45))
    p = _hline(p, 2, 3, (255, 255, 255, 0.07))
    acc = np.array(hexc(sp["accent"])[:3], dtype=np.float32) / 255.0
    glow = np.zeros((h, w, 4), dtype=np.float32)
    for i in range(3, 12):                                            # glow spilling right of the bar
        glow[:, i, :3] = acc
        glow[:, i, 3] = 0.40 * (1 - (i - 3) / 9.0) ** 2
    p = over(p, glow)
    bar = np.zeros((h, w, 4), dtype=np.float32)
    bar[:, 0:3, :3] = acc                                             # crisp 3px accent bar
    bar[:, 0:3, 3] = 1.0
    p = over(p, bar)
    return p


def build_cta_bg(skin: str) -> np.ndarray:
    sp = PLATES[skin]["cta"]
    w, h = 256, 64
    p = _base_plate(skin, w, h, sp, 64, tex_override=sp.get("tex") or PLATES[skin]["tex"]) \
        if sp.get("tex") else over(solid(w, h, hexc(sp["bg"])), css_gradient(w, h, sp["angle"], sp["stops"]))
    bevel = sp["bevel"]
    p = _hline(p, 2, 5, (*bevel[:3], bevel[3]))                       # top bevel highlight
    p = _hline(p, 5, 6, (255, 255, 255, 0.10))
    p = _hline(p, h - 4, h - 2, (0, 0, 0, 0.45))                      # bottom shade
    border = np.array(hexc(sp["border"])[:3], dtype=np.float32) / 255.0
    ring = np.zeros((h, w, 4), dtype=np.float32)
    ring[:2, :, :3] = border
    ring[-2:, :, :3] = border
    ring[:, :2, :3] = border
    ring[:, -2:, :3] = border
    ring[:2, :, 3] = ring[-2:, :, 3] = ring[:, :2, 3] = ring[:, -2:, 3] = 1.0
    p = over(p, ring)
    # 4px-radius rounded silhouette (anti-aliased alpha), like the mockup button
    r = 6.0
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    qx = np.maximum(np.maximum(r - (xx + 0.5), (xx + 0.5) - (w - r)), 0)
    qy = np.maximum(np.maximum(r - (yy + 0.5), (yy + 0.5) - (h - r)), 0)
    cov = np.clip(r - np.sqrt(qx ** 2 + qy ** 2) + 0.5, 0, 1)
    p = p.copy()
    p[..., 3] *= cov
    return bleed_rgb(p)


def build_socket(skin: str) -> np.ndarray:
    """64x64 frame: 1px dark outer bevel + 3px metallic ring, 100% transparent 56x56 hole."""
    sp = PLATES[skin]["socket"]
    n = 64
    ring = css_gradient(n, n, sp["angle"], sp["stops"])
    out = ring.copy()
    yy, xx = np.mgrid[0:n, 0:n]
    edge = np.minimum(np.minimum(xx, n - 1 - xx), np.minimum(yy, n - 1 - yy))   # px distance to outer edge
    # outer 1px dark bevel
    dark = np.array(hexc(sp["outer"])[:3], dtype=np.float32) / 255.0
    m0 = edge == 0
    out[m0, :3] = dark
    out[m0, 3] = 0.95
    # 3px metallic ring: bright top-left inner highlight, darker innermost px
    m_ring = (edge >= 1) & (edge <= 3)
    tl = (yy == 1) | (xx == 1)
    out[m_ring & tl, :3] = np.clip(out[m_ring & tl, :3] * 0.7 + 0.3, 0, 1)
    innermost = edge == 3
    if sp.get("inner"):
        ic = np.array(hexc(sp["inner"])[:3], dtype=np.float32) / 255.0
        out[innermost, :3] = out[innermost, :3] * 0.25 + ic * 0.75
    else:
        out[innermost, :3] = out[innermost, :3] * 0.65
    out[m_ring, 3] = 1.0
    # transparent 56x56 interior
    out[edge >= 4] = 0.0
    # soften outer corners (r=3)
    r = 3.0
    qx = np.maximum(np.maximum(r - (xx + 0.5), (xx + 0.5) - (n - r)), 0)
    qy = np.maximum(np.maximum(r - (yy + 0.5), (yy + 0.5) - (n - r)), 0)
    cov = np.clip(r - np.sqrt(qx ** 2 + qy ** 2) + 0.5, 0, 1)
    out[..., 3] *= cov.astype(np.float32)
    out = bleed_rgb(out, 4)
    return out


# ---------------------------------------------------------------------------
# Build / verify / audit drivers
# ---------------------------------------------------------------------------
def skin_assets(skin: str, only: Optional[Sequence[str]] = None) -> Dict[str, np.ndarray]:
    want = set(only) if only else None
    out: Dict[str, np.ndarray] = {}
    if want is None or "crest" in want:
        out["crest"] = build_crest(skin)
    if want is None or "corner" in want:
        out["corner"] = build_corner(skin)
    if want is None or "rail_h" in want or "rail_v" in want:
        rh, rv = build_rails(skin)
        if want is None or "rail_h" in want:
            out["rail_h"] = rh
        if want is None or "rail_v" in want:
            out["rail_v"] = rv
    if skin == "human" and (want is None or "banner" in want):
        out["banner"] = build_banner()
    if want is None or "surface" in want:
        out["surface"] = build_surface(skin)
    if want is None or "sidebar_bg" in want:
        out["sidebar_bg"] = build_sidebar(skin)
    if want is None or "header_tile" in want:
        out["header_tile"] = build_header_tile(skin)
    if want is None or "portrait" in want:
        out["portrait"] = build_square_icon(skin, PORTRAIT[skin])
    if want is None or "header_bg" in want:
        out["header_bg"] = build_header_bg(skin)
    if want is None or "panel_hdr" in want:
        out["panel_hdr"] = build_panel_hdr(skin)
    if want is None or "kpi_bg" in want:
        out["kpi_bg"] = build_kpi_bg(skin)
    if want is None or "nav_active" in want:
        out["nav_active"] = build_nav_active(skin)
    if want is None or "cta_bg" in want:
        out["cta_bg"] = build_cta_bg(skin)
    if want is None or "socket" in want:
        out["socket"] = build_socket(skin)
    if want is None or "send_btn" in want:
        out["send_btn"] = build_send_btn(skin)
    return out


SEND_BTN_CUTOUTS: Optional[Path] = (
    Path(os.environ["MM_SEND_BTN_DIR"]) if os.environ.get("MM_SEND_BTN_DIR") else None
)
SEND_BTN_MAP = {
    "human": "b4_sapphire_256.png",
    "night_elf": "b4_sapphire_256.png",
    "orc": "b4_ruby_256.png",
    "undead": "b4_emerald_256.png",
    "goblin": "b4_emerald_256.png",
}


def build_send_btn(skin: str) -> np.ndarray:
    if SEND_BTN_CUTOUTS is None:
        raise FileNotFoundError(
            "Send button cutouts directory not configured (pass --send-btn-dir or set MM_SEND_BTN_DIR)"
        )
    src = SEND_BTN_CUTOUTS / SEND_BTN_MAP[skin]
    arr = load_rgba(src)
    return bleed_rgb(resize(arr, 128, 128))


def build(skins: Sequence[str], preview_dir: Optional[Path], only: Optional[Sequence[str]] = None) -> int:
    count = 0
    for skin in skins:
        assets = skin_assets(skin, only=only)
        for name, arr in assets.items():
            write_blp2(OUT_ROOT / skin / (name + ".blp"), arr, opaque=(name in OPAQUE_BLP_ASSETS))
            old_tga = OUT_ROOT / skin / (name + ".tga")
            if old_tga.exists():
                old_tga.unlink()
            count += 1
            if preview_dir is not None:
                preview_dir.mkdir(parents=True, exist_ok=True)
                bg = Image.new("RGBA", (arr.shape[1], arr.shape[0]), (96, 96, 96, 255))
                bg.alpha_composite(to_pil(arr))
                bg.save(preview_dir / ("%s_%s.png" % (skin, name)))
        print("built %-9s %d textures (BLP2)" % (skin, len(assets)))
    return count


def expected_names(skin: str) -> List[str]:
    names = ["crest", "corner", "rail_h", "rail_v", "surface", "sidebar_bg", "header_tile",
             "portrait", "header_bg", "panel_hdr", "kpi_bg", "nav_active", "cta_bg",
             "socket", "send_btn"]
    if skin == "human":
        names.append("banner")
    return names


def render_magenta_sky_audit(out_png: Path, skins: Sequence[str] = SKINS) -> None:
    """Composite EVERY transparent .blp across all 5 skins over #FF00FF magenta AND #DCE8F5 sky."""
    audit_names = ["crest", "corner", "rail_h", "rail_v", "banner", "socket"]
    magenta = (255, 0, 255, 255)
    sky = (220, 232, 245, 255)
    pad = 12
    row_panels: List[Image.Image] = []

    for skin in skins:
        tiles: List[Image.Image] = []
        for name in audit_names:
            blp_p = OUT_ROOT / skin / (name + ".blp")
            if not blp_p.exists():
                continue
            w, h, rgba = read_blp2(blp_p)
            im = Image.fromarray(rgba, "RGBA")
            # Crop crest to its active top-aligned contentH for 1:1 visual inspection alongside full canvas line
            if name == "crest":
                ys, _ = np.where(rgba[..., 3] > 4)
                ch = int(ys.max()) + 1 if len(ys) else h
                im_disp = im.crop((0, 0, w, ch))
            else:
                im_disp = im
            dw, dh = im_disp.size
            # Scale overly tall/wide rails moderately so all 8 assets fit side-by-side legibly at high res
            max_dim = 260 if name == "crest" else (180 if name == "corner" else 160)
            s = min(1.0, float(max_dim) / float(max(dw, dh)))
            sw, sh = max(1, int(round(dw * s))), max(1, int(round(dh * s)))
            im_s = im_disp.resize((sw, sh), RESAMPLE_LANCZOS) if s < 1.0 else im_disp

            card_w = max(sw * 2 + 18, 150)
            card_h = sh + 34
            card = Image.new("RGB", (card_w, card_h), (26, 28, 34))
            draw = ImageDraw.Draw(card)
            draw.text((6, 5), "%s/%s (%dx%d)" % (skin, name, w, h), fill=(235, 238, 245))
            for idx, bgc in enumerate((magenta, sky)):
                bg = Image.new("RGBA", (sw, sh), bgc)
                bg.alpha_composite(im_s)
                card.paste(bg.convert("RGB"), (6 + idx * (sw + 6), 24))
            tiles.append(card)

        row_w = sum(t.width for t in tiles) + pad * (len(tiles) + 1)
        row_h = max(t.height for t in tiles) + pad * 2 + 22
        row_im = Image.new("RGB", (row_w, row_h), (16, 18, 22))
        rdraw = ImageDraw.Draw(row_im)
        rdraw.text((pad, 6), "SKIN: %s  (Left = #FF00FF Magenta | Right = #DCE8F5 Sky)" % skin.upper(),
                   fill=(247, 213, 124))
        x = pad
        for t in tiles:
            row_im.paste(t, (x, 26))
            x += t.width + pad
        row_panels.append(row_im)

    sheet_w = max(r.width for r in row_panels)
    sheet_h = sum(r.height for r in row_panels)
    sheet = Image.new("RGB", (sheet_w, sheet_h), (16, 18, 22))
    y = 0
    for r in row_panels:
        sheet.paste(r, (0, y))
        y += r.height
    out_png.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out_png)
    print("wrote transparency audit sheet: %s (%dx%d)" % (out_png, sheet_w, sheet_h))


def verify(skins: Sequence[str]) -> int:
    problems: List[str] = []
    total = 0
    print("%-9s %-15s %-9s %s" % ("skin", "file", "size", "notes"))
    for skin in skins:
        for name in expected_names(skin):
            path = OUT_ROOT / skin / (name + ".blp")
            if not path.exists():
                problems.append("%s/%s.blp missing" % (skin, name))
                continue
            try:
                w, h, px = read_blp2(path)
            except ValueError as exc:
                problems.append(str(exc))
                continue
            total += 1
            note = []
            if (w & (w - 1)) or (h & (h - 1)) or w > 1024 or h > 1024:
                problems.append("%s/%s.blp %dx%d not POT<=1024" % (skin, name, w, h))
            alpha = px[..., 3]
            if int(alpha.max()) == 0:
                problems.append("%s/%s.blp alpha is empty" % (skin, name))
            if name == "crest":
                ys, xs = np.where(alpha > 4)
                y0 = int(ys.min())
                cw = int(xs.max() - xs.min() + 1)
                chh = int(ys.max()) + 1
                vmax = chh / float(h)
                if (w, h) != (256, 128):
                    problems.append("%s/crest.blp expected 256x128, got %dx%d" % (skin, w, h))
                if y0 > 1:
                    problems.append("%s/crest.blp not top-aligned (y0=%d)" % (skin, y0))
                if cw < w - 2:
                    problems.append("%s/crest.blp does not fill %dpx width (cw=%d)" % (skin, w, cw))
                if THEMES is not None and THEMES.exists():
                    tc = _trimmed_crest(skin)
                    th_n, tw_n = tc.shape[:2]
                    note.append("top 0..%d vMax=%.6f; native %dx%d w/h=%.4f" % (
                        chh, vmax, tw_n, th_n, tw_n / float(th_n)))
                else:
                    note.append("top 0..%d vMax=%.6f; aspect %.4f" % (chh, vmax, cw / float(chh)))
            if name in ("rail_h", "rail_v"):
                (nhw, nhh), (nvw, nvh) = NATIVE_RAIL_DIMS[skin]
                nw, nh = (nhw, nhh) if name == "rail_h" else (nvw, nvh)
                note.append("pot %.3f; native %dx%d w/h=%.4f (h/w=%.4f)" % (
                    w / float(h), nw, nh, nw / float(nh), nh / float(nw)))
            if name == "corner":
                note.append("corner alpha %d/%d/%d/%d, transparent %.0f%%" % (
                    alpha[0, 0], alpha[0, -1], alpha[-1, 0], alpha[-1, -1], 100.0 * (alpha == 0).mean()))
            if name == "socket":
                hole = alpha[4:60, 4:60]
                note.append("hole 56x56 max alpha %d" % int(hole.max()))
                if int(hole.max()) != 0:
                    problems.append("%s/socket.blp interior hole is not fully transparent" % skin)
            if name in ("surface", "sidebar_bg", "header_tile"):
                if int(alpha.min()) < 250:
                    problems.append("%s/%s.blp should be opaque" % (skin, name))
                cr = (rel_lum(TEXT_IVORY) + 0.05) / (p99_to_rel(px) + 0.05)
                arr_f = px.astype(np.float32) / 255.0
                seam = seam_ratio(arr_f)
                if name == "sidebar_bg":
                    sx, sy = seam_ratio_xy(arr_f)
                    note.append("ivory-text contrast (p99.5) %.1f:1, wrap-seam x%.2f (x=%.2f y=%.2f)" % (
                        cr, seam, sx, sy))
                    if cr < 10.0:
                        problems.append("%s/sidebar_bg.blp contrast %.2f < 10.0" % (skin, cr))
                    if seam >= 1.6 or sx >= 1.6 or sy >= 1.6:
                        problems.append("%s/sidebar_bg.blp wrap-seam (x=%.2f y=%.2f all=%.2f) >= 1.6" % (
                            skin, sx, sy, seam))
                else:
                    note.append("ivory-text contrast (p99.5) %.1f:1, wrap-seam x%.2f" % (cr, seam))
                if name == "surface" and cr < 4.5:
                    problems.append("%s/surface.blp contrast %.2f < 4.5" % (skin, cr))
                if name == "header_tile" and seam > 1.85:
                    problems.append("%s/header_tile.blp wrap-seam %.2f > 1.85" % (skin, seam))
            if name in ("header_bg", "panel_hdr", "kpi_bg"):
                body = alpha[4:-2, :] / 255.0
                bmin, bmax = float(body.min()), float(body.max())
                note.append("translucent body alpha %.2f..%.2f, border alpha %d" % (
                    bmin, bmax, int(alpha[-1, :].min())))
                if bmax > 0.96 or bmin < 0.65:
                    problems.append("%s/%s.blp body alpha %.2f..%.2f outside translucent target" % (
                        skin, name, bmin, bmax))
            print("%-9s %-15s %4dx%-4d %s" % (skin, name + ".blp", w, h, "; ".join(note)))
    print("verified %d BLP2 files, %d problems" % (total, len(problems)))
    for p in problems:
        print("  PROBLEM:", p)
    return len(problems)


def p99_to_rel(px: np.ndarray) -> float:
    """Relative luminance of the 99.5th-percentile-brightest texel (WCAG, sRGB)."""
    rgb = px[..., :3].astype(np.float32) / 255.0
    lin = np.where(rgb <= 0.03928, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    rl = lin @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    return float(np.percentile(rl, 99.5))


def main() -> int:
    global THEMES, SEND_BTN_CUTOUTS, CHROME_EXE
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--verify", action="store_true", help="only validate existing BLP2 files")
    ap.add_argument("--skin", choices=SKINS, help="build/verify a single skin")
    ap.add_argument("--only", nargs="+", help="only build named asset(s), e.g. --only sidebar_bg")
    ap.add_argument("--themes-dir", type=Path, default=THEMES, help="external theme mockup root (or MM_THEMES_DIR)")
    ap.add_argument("--send-btn-dir", type=Path, default=SEND_BTN_CUTOUTS, help="send button cutouts dir (or MM_SEND_BTN_DIR)")
    ap.add_argument("--chrome-exe", type=Path, default=CHROME_EXE, help="Chrome executable for SVG rasterization (or CHROME_BIN)")
    ap.add_argument("--preview-dir", type=Path, help="also write grey-backed PNG previews here")
    ap.add_argument("--audit-png", type=Path, help="write bright magenta + sky transparency audit PNG")
    args = ap.parse_args()
    THEMES = args.themes_dir
    SEND_BTN_CUTOUTS = args.send_btn_dir
    CHROME_EXE = find_chrome_exe(args.chrome_exe)
    skins = [args.skin] if args.skin else SKINS
    if not args.verify:
        if THEMES is None or not THEMES.exists():
            print("theme sources not found (pass --themes-dir or set MM_THEMES_DIR): %s" % THEMES)
            return 2
        n = build(skins, args.preview_dir, only=args.only)
        print("wrote %d BLP2 files into %s" % (n, OUT_ROOT))
    bad = verify(skins)
    if args.audit_png is not None:
        render_magenta_sky_audit(args.audit_png, skins)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
