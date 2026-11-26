"""Build crisp 32-bit BGRA Apple HIG & SF-Symbol .tga assets for MerchantMaster.

Outputs 46 uncompressed 32-bit BGRA .tga files (image_type=2, bpp=32,
descriptor=0x08 bottom-left origin, TGA 2.0 footer) into Assets/apple/:
  - 20 9-slice / split-pane / pill / circle / meter / shadow / specular surfaces
  - 26 monochrome white SF-Symbol & utility icons rasterized from SVG via
    headless Google Chrome <canvas>

It also regenerates the 4 Liquid Glass refraction layers in Assets/:
  - shade_v.blp, header_wash.blp, fade_lr.blp (256x512 BLP2 DXT5 with mipmaps)
  - glow_line.tga (128x16 uncompressed 32-bit BGRA TGA)

Usage:
  python tools/build_apple_assets.py
  python tools/build_apple_assets.py --verify
"""
from __future__ import annotations

import argparse
import base64
import functools
import http.server
import json
import math
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import threading
from collections.abc import Callable
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT_DIR / "Assets" / "apple"
GLASS_DIR = ROOT_DIR / "Assets"
TGA_FOOTER = b"\x00" * 8 + b"TRUEVISION-XFILE.\x00"


def find_chrome_exe(override: Path | None = None) -> Path | None:
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
    candidates: list[Path] = []
    for env_dir in ("PROGRAMFILES", "PROGRAMFILES(X86)", "LOCALAPPDATA"):
        base = os.environ.get(env_dir, "").strip()
        if base:
            candidates.append(Path(base) / "Google" / "Chrome" / "Application" / "chrome.exe")
    candidates.append(Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"))
    for cand in candidates:
        if cand.is_file():
            return cand
    return None


CHROME_EXE: Path | None = find_chrome_exe()

# Exact SVG inner markup from Fable 5.2 Design 1 (viewBox="0 0 24 24", stroke-width=1.8)
SF_ICONS: dict[str, str] = {
    "icon_grid": (
        '<rect x="3.5" y="3.5" width="7" height="7" rx="2"/>'
        '<rect x="13.5" y="3.5" width="7" height="7" rx="2"/>'
        '<rect x="3.5" y="13.5" width="7" height="7" rx="2"/>'
        '<rect x="13.5" y="13.5" width="7" height="7" rx="2"/>'
    ),
    "icon_basket": (
        '<path d="M3.75 9.5h16.5l-1.5 8.45a2 2 0 0 1-1.97 1.65H7.22a2 2 0 0 1-1.97-1.65L3.75 9.5z"/>'
        '<path d="M8.6 9.5l2.6-5.25M15.4 9.5l-2.6-5.25"/>'
        '<path d="M9.75 13v3.25M14.25 13v3.25"/>'
    ),
    "icon_flask": (
        '<path d="M9.25 3.5h5.5"/>'
        '<path d="M10.25 3.5v5.4l-4.9 8.35a2.2 2.2 0 0 0 1.9 3.3h9.5a2.2 2.2 0 0 0 1.9-3.3l-4.9-8.35V3.5"/>'
        '<path d="M7.9 14.75h8.2"/>'
    ),
    "icon_crown": (
        '<path d="M4.4 17.5L3.25 8.25l4.9 3.6L12 5.5l3.85 6.35 4.9-3.6-1.15 9.25H4.4z"/>'
        '<path d="M5 20.5h14"/>'
    ),
    "icon_book": (
        '<path d="M12 6.5c-1.8-1.45-4.3-2-7.75-1.75v12.9c3.45-.25 5.95.3 7.75 1.75 1.8-1.45 4.3-2 7.75-1.75V4.75C16.3 4.5 13.8 5.05 12 6.5z"/>'
        '<path d="M12 6.5v12.9"/>'
    ),
    "icon_crate": (
        '<path d="M12 3.25l8 4.1v9.3l-8 4.1-8-4.1v-9.3l8-4.1z"/>'
        '<path d="M4 7.35l8 4.1 8-4.1M12 11.45v9.3"/>'
        '<path d="M8 5.3l8 4.1"/>'
    ),
    "icon_doc": (
        '<path d="M7.75 3.5h6l4.5 4.5v10.5a2 2 0 0 1-2 2h-8.5a2 2 0 0 1-2-2v-13a2 2 0 0 1 2-2z"/>'
        '<path d="M13.5 3.5v4.75h4.75"/>'
        '<path d="M9 12.75h6M9 16.25h3.75"/>'
    ),
    "icon_shield": (
        '<path d="M12 3.25l7.25 2.6v5.4c0 4.35-2.85 7.85-7.25 9.75-4.4-1.9-7.25-5.4-7.25-9.75v-5.4L12 3.25z"/>'
        '<path d="M8.9 12l2.2 2.2 4-4.4"/>'
    ),
    "icon_bars": (
        '<rect x="3.75" y="13" width="4" height="7.5" rx="1.25"/>'
        '<rect x="10" y="8.5" width="4" height="12" rx="1.25"/>'
        '<rect x="16.25" y="3.5" width="4" height="17" rx="1.25"/>'
    ),
    "icon_trend": (
        '<path d="M3.75 4v14.25a2 2 0 0 0 2 2h14.5"/>'
        '<path d="M7.5 15l3.6-4.1 3 2.5 5.15-6.15"/>'
        '<path d="M15.5 7.25h3.75V11"/>'
    ),
    "icon_search": (
        '<circle cx="10.75" cy="10.75" r="6.25"/>'
        '<path d="M15.4 15.4l4.85 4.85"/>'
    ),
    "icon_refresh": (
        '<path d="M20.5 4.25V9.5h-5.25"/>'
        '<path d="M19.3 14.6a7.75 7.75 0 1 1-1.82-8.08L20.5 9.5"/>'
    ),
    "icon_sun": (
        '<circle cx="12" cy="12" r="3.9"/>'
        '<path d="M12 2.75v2.1M12 19.15v2.1M2.75 12h2.1M19.15 12h2.1M5.46 5.46l1.48 1.48M17.06 17.06l1.48 1.48M5.46 18.54l1.48-1.48M17.06 6.94l1.48-1.48"/>'
    ),
    "icon_moon": (
        '<path d="M20 13.2A8.53 8.53 0 1 1 10.8 4a6.8 6.8 0 0 0 9.2 9.2z"/>'
    ),
    "icon_check": (
        '<path d="M5.25 12.75l4.25 4.25 9.25-10"/>'
    ),
    "icon_checkcircle": (
        '<circle cx="12" cy="12" r="8.5"/>'
        '<path d="M8.4 12.3l2.5 2.5 4.8-5.3"/>'
    ),
    "icon_lock": (
        '<rect x="5.25" y="10.75" width="13.5" height="9.75" rx="2.5"/>'
        '<path d="M8.5 10.75V8a3.5 3.5 0 0 1 7 0v2.75"/>'
    ),
    "icon_send": (
        '<path d="M20.75 3.25L3.5 9.6l6.9 3.1 3.1 6.9 7.25-16.35z"/>'
        '<path d="M10.4 12.7l4.35-4.35"/>'
    ),
    "icon_leaf": (
        '<path d="M5.25 18.75C4.4 10.6 9.9 5.1 19.5 4.5c.5 9.5-5 15.1-14.25 14.25z"/>'
        '<path d="M5.25 18.75c2.4-4.6 5.4-7.6 9.5-9.75"/>'
    ),
    "icon_vial": (
        '<path d="M9 3.5h6"/>'
        '<path d="M10 3.5v13.75a2 2 0 0 0 4 0V3.5"/>'
        '<path d="M10 11.5h4"/>'
    ),
    "icon_star": (
        '<path d="M12 3.75l2.5 5.2 5.75.8-4.15 4 1 5.7L12 16.75l-5.1 2.7 1-5.7-4.15-4 5.75-.8L12 3.75z"/>'
    ),
    "icon_coins": (
        '<ellipse cx="12" cy="7.25" rx="7.25" ry="3.25"/>'
        '<path d="M4.75 7.25V12c0 1.8 3.25 3.25 7.25 3.25s7.25-1.45 7.25-3.25V7.25"/>'
        '<path d="M4.75 12v4.75c0 1.8 3.25 3.25 7.25 3.25s7.25-1.45 7.25-3.25V12"/>'
    ),
    "icon_bolt": (
        '<path d="M13.25 3.25L5.5 13.5h5.75l-.9 7.25 8.15-10.5h-5.9l.65-7z"/>'
    ),
    "icon_chevron_down": (
        '<path d="M6.5 9.25L12 14.75L17.5 9.25"/>'
    ),
    "icon_close": (
        '<path d="M6.5 6.5L17.5 17.5M17.5 6.5L6.5 17.5"/>'
    ),
    "icon_gear": (
        '<circle cx="12" cy="12" r="2.85"/>'
        '<path d="M18.2 12l2.15 1.15-1.15 2.75-2.35-.45-1.2 1.2.45 2.35-2.75 1.15L12 18.2l-1.35 1.95-2.75-1.15.45-2.35-1.2-1.2-2.35.45-1.15-2.75L5.8 12l-2.15-1.15 1.15-2.75 2.35.45 1.2-1.2-.45-2.35 2.75-1.15L12 5.8l1.35-1.95 2.75 1.15-.45 2.35 1.2 1.2 2.35-.45 1.15 2.75z"/>'
    ),
}


def clamp(v: float, lo: float = 0.0, hi: float = 1.0) -> float:
    return lo if v < lo else (hi if v > hi else v)


def smoothstep(edge0: float, edge1: float, x: float) -> float:
    t = clamp((x - edge0) / (edge1 - edge0))
    return t * t * (3.0 - 2.0 * t)


def sd_rounded_box(px: float, py: float, cx: float, cy: float, hx: float, hy: float, r: float) -> float:
    qx = abs(px - cx) - (hx - r)
    qy = abs(py - cy) - (hy - r)
    return math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - r


def sd_rounded_box_lr(
    px: float,
    py: float,
    cx: float,
    cy: float,
    hx: float,
    hy: float,
    r_left: float,
    r_right: float,
) -> float:
    """Signed distance to box with independent left/right corner radii."""
    r = r_left if px < cx else r_right
    qx = abs(px - cx) - (hx - r)
    qy = abs(py - cy) - (hy - r)
    return math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - r


def write_tga_white_alpha(path: Path, width: int, height: int, top_down_alphas: list[int]) -> None:
    """Write uncompressed 32-bit BGRA TGA (type=2, bpp=32, desc=0x08 bottom-left)."""
    if len(top_down_alphas) != width * height:
        raise ValueError(f"Pixel count mismatch for {path.name}: {len(top_down_alphas)} != {width * height}")
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 0x08)
    buf = bytearray(width * height * 4)
    for y_tga in range(height):
        # descriptor=0x08 stores bottom-most row first
        y_src = height - 1 - y_tga
        src_off = y_src * width
        dst_off = y_tga * width * 4
        for x in range(width):
            a = top_down_alphas[src_off + x]
            idx = dst_off + x * 4
            buf[idx] = 255      # B
            buf[idx + 1] = 255  # G
            buf[idx + 2] = 255  # R
            buf[idx + 3] = a    # A
    path.write_bytes(header + bytes(buf) + TGA_FOOTER)


def write_tga_bgra(path: Path, width: int, height: int, rgba_rows: list[list[tuple[int, int, int, int]]]) -> None:
    """Write uncompressed 32-bit BGRA TGA (type=2, bpp=32, desc=0x08 bottom-left) from top-down RGBA rows."""
    if len(rgba_rows) != height or any(len(row) != width for row in rgba_rows):
        raise ValueError(f"Pixel grid mismatch for {path.name}: expected {width}x{height}")
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 0x08)
    buf = bytearray(width * height * 4)
    for y_tga in range(height):
        row = rgba_rows[height - 1 - y_tga]
        dst_off = y_tga * width * 4
        for x in range(width):
            r, g, b, a = row[x]
            idx = dst_off + x * 4
            buf[idx] = b
            buf[idx + 1] = g
            buf[idx + 2] = r
            buf[idx + 3] = a
    path.write_bytes(header + bytes(buf) + TGA_FOOTER)


# ---------------------------------------------------------------------------
# Liquid Glass sidebar refraction layers (Assets/shade_v, header_wash, fade_lr, glow_line)
#
# The 256x512 maps are drawn as a vertical 3-slice over the 216px sidebar: the top
# and bottom 32 texel rows map 1:1 onto 32px caps and the 448 middle rows stretch,
# so the baked r=22 outer-left corners stay exact at any window height.
# ---------------------------------------------------------------------------
GLASS_W, GLASS_H = 256, 512
GLASS_CAP = 32            # texel rows == screen px for the top / bottom caps
SIDEBAR_W = 216.0         # on-screen sidebar width
SIDEBAR_REF_H = 730.0     # reference window height used to place the light pools
SIDEBAR_R = 22.0          # outer-left corner radius (openRight: flush square right edge)
GLASS_EDGE_INSET = 0.35   # corner arcs sit strictly inside the 9-slice silhouette


def glass_screen_xy(tx: float, ty: float) -> tuple[float, float]:
    """Map a texel position to on-screen sidebar px at the reference height."""
    sx = tx * SIDEBAR_W / GLASS_W
    if ty < GLASS_CAP:
        sy = ty
    elif ty >= GLASS_H - GLASS_CAP:
        sy = SIDEBAR_REF_H - (GLASS_H - ty)
    else:
        sy = GLASS_CAP + (ty - GLASS_CAP) * (SIDEBAR_REF_H - 2 * GLASS_CAP) / (GLASS_H - 2 * GLASS_CAP)
    return sx, sy


def glass_edge_sd(sx: float, sy: float) -> float:
    """Signed distance (screen px, negative inside) to the open-right r=22 sidebar silhouette."""
    # The right edge is pushed far away so only the left / top / bottom rim is measured.
    hx = 2000.0
    return sd_rounded_box_lr(sx, sy, hx, SIDEBAR_REF_H / 2.0, hx, SIDEBAR_REF_H / 2.0, SIDEBAR_R, 0.0)


def glass_coverage(tx: int, ty: int) -> float:
    """Supersampled coverage of the same SDF corner profile the glass_r22 9-slice uses."""
    sx, sy = glass_screen_xy(tx + 0.5, ty + 0.5)
    # Straight edges are flush with the texture bounds; only the two corner arcs cut alpha.
    if sx >= SIDEBAR_R + 1.0 or (SIDEBAR_R + 1.0 <= sy <= SIDEBAR_REF_H - SIDEBAR_R - 1.0):
        return 1.0
    sd_c = glass_edge_sd(sx, sy) + GLASS_EDGE_INSET
    if sd_c < -2.0:
        return 1.0
    if sd_c > 2.0:
        return 0.0
    sub = 4
    acc = 0
    for iy in range(sub):
        for ix in range(sub):
            px, py = glass_screen_xy(tx + (ix + 0.5) / sub, ty + (iy + 0.5) / sub)
            in_arc = px < SIDEBAR_R and (py < SIDEBAR_R or py > SIDEBAR_REF_H - SIDEBAR_R)
            if not in_arc or glass_edge_sd(px, py) + GLASS_EDGE_INSET <= 0.0:
                acc += 1
    return acc / float(sub * sub)


def glass_grain(tx: int, ty: int) -> float:
    """Deterministic smooth silica micro-grain in [-1, 1] (integer hash + 4-tap soften)."""
    def h(ix: int, iy: int) -> float:
        n = (ix * 374761393 + iy * 668265263) & 0xFFFFFFFF
        n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
        n ^= n >> 16
        return (n & 0xFFFF) / 32767.5 - 1.0
    return 0.55 * h(tx, ty) + 0.15 * (h(tx + 1, ty) + h(tx, ty + 1) + h(tx - 1, ty))


def glass_pool(sx: float, sy: float, cx: float, cy: float, rx: float, ry: float) -> float:
    """Soft Gaussian light pool, 1.0 at its centre."""
    dx = (sx - cx) / rx
    dy = (sy - cy) / ry
    return math.exp(-(dx * dx + dy * dy))


def mix(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def render_glass_substrate(light: bool) -> list[list[tuple[int, int, int, int]]]:
    """Regular-Large frosted substrate: diffused light pools, silica grain, lensing rim."""
    rows: list[list[tuple[int, int, int, int]]] = []
    for ty in range(GLASS_H):
        row: list[tuple[int, int, int, int]] = []
        for tx in range(GLASS_W):
            sx, sy = glass_screen_xy(tx + 0.5, ty + 0.5)
            depth = -glass_edge_sd(sx, sy)  # px inside the left / top / bottom rim
            u = sx / SIDEBAR_W
            v = sy / SIDEBAR_REF_H
            diag = clamp(0.62 * v + 0.38 * u)
            cool = glass_pool(sx, sy, 44.0, 96.0, 190.0, 230.0)     # sky / midnight, top-left
            warm = glass_pool(sx, sy, 34.0, 668.0, 200.0, 190.0)    # ember bounce, bottom-left
            sheen_axis = (sx + 0.42 * sy) - 232.0
            sheen = math.exp(-(sheen_axis / 74.0) ** 2)             # soft diagonal specular sheen
            grain = glass_grain(tx, ty)

            if light:
                # #EFF0F6 -> #E6E8F0 pearl mist with #F7F8FC diffusion pools
                r = mix(239.0, 230.0, diag)
                g = mix(240.0, 232.0, diag)
                b = mix(246.0, 240.0, diag)
                r += cool * -5.0 + warm * 7.0 + sheen * 8.0
                g += cool * 0.5 + warm * 4.5 + sheen * 8.0
                b += cool * 6.0 + warm * -1.5 + sheen * 7.0
                r += grain * 2.0
                g += grain * 2.0
                b += grain * 2.0
                # gentle 14px internal shadow falloff just inside the bevel
                shade = 0.035 * (1.0 - smoothstep(3.0, 17.0, depth)) * smoothstep(1.5, 4.5, depth)
                r *= 1.0 - shade
                g *= 1.0 - shade
                b *= 1.0 - shade * 0.8
                # crisp 95% white optical lensing bevel inside the curved rim
                lip = 0.95 * (1.0 - smoothstep(1.4, 3.6, depth))
                r = mix(r, 255.0, lip)
                g = mix(g, 255.0, lip)
                b = mix(b, 255.0, lip)
            else:
                # #1D1E24 -> #22242C frosted slate
                r = mix(29.0, 34.0, diag)
                g = mix(30.0, 36.0, diag)
                b = mix(36.0, 44.0, diag)
                r += cool * 3.0 + warm * 13.0 + sheen * 5.0
                g += cool * 6.0 + warm * 6.0 + sheen * 5.5
                b += cool * 17.0 + warm * 4.0 + sheen * 7.0
                r += grain * 3.0
                g += grain * 3.0
                b += grain * 3.0
                shade = 0.20 * (1.0 - smoothstep(3.0, 17.0, depth)) * smoothstep(1.5, 4.5, depth)
                r *= 1.0 - shade
                g *= 1.0 - shade
                b *= 1.0 - shade
                # 3-4px bright dispersion lip (18% white), strongest on the lit top-left curve
                lit = mix(1.0, 0.55, clamp(v * 1.15))
                lip = 0.18 * lit * (1.0 - smoothstep(1.2, 4.0, depth))
                r = mix(r, 255.0, lip)
                g = mix(g, 255.0, lip)
                b = mix(b, 255.0, lip)

            a = glass_coverage(tx, ty)
            row.append((
                int(round(clamp(r, 0.0, 255.0))),
                int(round(clamp(g, 0.0, 255.0))),
                int(round(clamp(b, 0.0, 255.0))),
                int(round(a * 255.0)),
            ))
        rows.append(row)
    return rows


def render_glass_lens() -> list[list[tuple[int, int, int, int]]]:
    """White refraction caustics: bright top curved lip + left optical lens band."""
    rows: list[list[tuple[int, int, int, int]]] = []
    for ty in range(GLASS_H):
        row: list[tuple[int, int, int, int]] = []
        for tx in range(GLASS_W):
            sx, sy = glass_screen_xy(tx + 0.5, ty + 0.5)
            depth = -glass_edge_sd(sx, sy)
            v = sy / SIDEBAR_REF_H
            top_w = 1.0 - smoothstep(0.0, 0.55, v)           # caustics weighted to the top lip
            bottom_w = smoothstep(0.80, 1.0, v)
            hairline = 1.0 - smoothstep(0.6, 1.9, depth)     # crisp edge light
            feather = math.exp(-max(depth, 0.0) / 5.5)       # inner refraction falloff
            band = math.exp(-max(depth, 0.0) / 26.0)         # wide lens band
            a = hairline * (0.34 + 0.56 * top_w + 0.10 * bottom_w)
            a += feather * (0.07 + 0.20 * top_w)
            a += band * (0.025 + 0.055 * top_w)
            a = clamp(a) * glass_coverage(tx, ty)
            row.append((255, 255, 255, int(round(a * 255.0))))
        rows.append(row)
    return rows


def render_caustic_rows(width: int) -> list[list[tuple[int, int, int, int]]]:
    """Rasterize a diffuse 16px highlight with a Gaussian peak and feathered ends."""
    horizontal = [smoothstep(0.0, 0.32, min(x, width - 1 - x) / (width - 1)) for x in range(width)]
    rows = []
    for y in range(16):
        peak = math.exp(-((y - 2.0) / 5.0) ** 2)
        vertical = smoothstep(-1.0, 2.0, y) * peak * smoothstep(15.0, 10.0, y)
        rows.append([(255, 255, 255, round(140 * vertical * taper)) for taper in horizontal])
    return rows


def render_glass_shimmer() -> list[list[tuple[int, int, int, int]]]:
    return render_caustic_rows(128)


def write_blp2_rgba(path: Path, width: int, height: int, rgba_rows: list[list[tuple[int, int, int, int]]]) -> None:
    """Write WoW-native BLP2 (DXT5 RGBA with full mipmap chain) from top-down RGBA rows."""
    if len(rgba_rows) != height or any(len(row) != width for row in rgba_rows):
        raise ValueError(f"Pixel grid mismatch for {path.name}: expected {width}x{height}")
    import numpy as np

    tools_dir = str(Path(__file__).resolve().parent)
    if tools_dir not in sys.path:
        sys.path.insert(0, tools_dir)
    from build_skin_assets import write_blp2

    arr = np.asarray(rgba_rows, dtype=np.float32) / 255.0
    write_blp2(path, arr, opaque=False)


def verify_glass_blp2(path: Path, width: int, height: int) -> tuple[int, int, int]:
    """Verify native BLP2 (DXT5 + mipmaps) contract for Assets/*.blp glass maps."""
    data = path.read_bytes()
    if len(data) < 1172 or data[:4] != b"BLP2":
        raise ValueError(f"{path.name}: bad BLP2 magic or length ({len(data)})")
    btype, enc, adepth, aenc, has_mips, w, h = struct.unpack_from("<IBBBBII", data, 4)
    offsets = struct.unpack_from("<16I", data, 20)
    lengths = struct.unpack_from("<16I", data, 84)
    if btype != 1 or enc != 2 or adepth != 8 or aenc != 7 or has_mips != 1:
        raise ValueError(
            f"{path.name}: bad BLP2 header (type={btype}, enc={enc}, adepth={adepth}, aenc={aenc}, mips={has_mips})"
        )
    if (w, h) != (width, height):
        raise ValueError(f"{path.name}: {w}x{h} != expected {width}x{height}")
    mip_count = sum(1 for ln in lengths if ln > 0)
    if mip_count < 2 or offsets[0] != 1172:
        raise ValueError(f"{path.name}: invalid mipmap chain (count={mip_count}, off0={offsets[0]})")
    expected_len = 1172 + sum(lengths)
    if len(data) != expected_len:
        raise ValueError(f"{path.name}: size {len(data)} != expected {expected_len}")
    return w, h, mip_count


def verify_glass_tga(path: Path, width: int, height: int) -> tuple[int, int, int]:
    """Verify the legacy Assets/*.tga contract (type=2, bpp=32, desc=0x08, TGA 2.0 footer) + real variation."""
    data = path.read_bytes()
    id_len, cmap_type, img_type, _, _, _, _, _, w, h, bpp, desc = struct.unpack("<BBBHHBHHHHBB", data[:18])
    if id_len != 0 or cmap_type != 0 or img_type != 2 or bpp != 32 or desc != 0x08:
        raise ValueError(f"{path.name}: bad TGA header (type={img_type}, bpp={bpp}, desc=0x{desc:02x})")
    if (w, h) != (width, height):
        raise ValueError(f"{path.name}: {w}x{h} != expected {width}x{height}")
    if len(data) != 18 + w * h * 4 + 26 or data[-26:] != TGA_FOOTER:
        raise ValueError(f"{path.name}: bad length or missing TGA 2.0 footer")
    px = data[18 : 18 + w * h * 4]
    alphas = set(px[3::4])
    colors = {bytes(px[i : i + 3]) for i in range(0, len(px), 4 * 37)}
    if max(alphas) == 0:
        raise ValueError(f"{path.name}: completely empty alpha channel")
    if len(alphas) < 2 and len(colors) < 2:
        raise ValueError(f"{path.name}: uniform pixels (no frosted gradient / refraction)")
    return w, h, len(alphas) + len(colors)


def build_liquid_glass_layers() -> list[tuple[Path, int, int]]:
    blp_layers = [
        ("shade_v.blp", GLASS_W, GLASS_H, render_glass_substrate(False)),
        ("header_wash.blp", GLASS_W, GLASS_H, render_glass_substrate(True)),
        ("fade_lr.blp", GLASS_W, GLASS_H, render_glass_lens()),
    ]
    out: list[tuple[Path, int, int]] = []
    for fname, w, h, rows in blp_layers:
        p = GLASS_DIR / fname
        write_blp2_rgba(p, w, h, rows)
        old_tga = p.with_suffix(".tga")
        if old_tga.exists():
            old_tga.unlink()
        out.append((p, w, h))

    glow_p = GLASS_DIR / "glow_line.tga"
    write_tga_bgra(glow_p, 128, 16, render_glass_shimmer())
    out.append((glow_p, 128, 16))

    # Outer-left corners must be fully transparent, the flush right edge fully opaque.
    sub = blp_layers[0][3]
    if sub[0][0][3] != 0 or sub[GLASS_H - 1][0][3] != 0 or sub[0][GLASS_W - 1][3] != 255 or sub[GLASS_H // 2][0][3] == 0:
        raise AssertionError("shade_v open-right r=22 silhouette invariant failed")
    return out


def render_box_pair_lr(
    width: int,
    height: int,
    r_left: float,
    r_right: float,
    margin: float,
    stroke_w: float,
    rim_weight: Callable[[float], float] | None = None,
) -> tuple[list[int], list[int]]:
    """Compute top-down alpha maps for asymmetric (fill, stroke) using supersampled SDF."""
    cx = width / 2.0
    cy = height / 2.0
    hx = cx - margin
    hy = cy - margin
    fill_alphas: list[int] = [0] * (width * height)
    stroke_alphas: list[int] = [0] * (width * height)
    sub = 4
    inv_sub = 1.0 / sub
    inv_total = 1.0 / (sub * sub)
    feather = 2.0 if rim_weight is not None else 0.0

    for y in range(height):
        row_off = y * width
        weight = rim_weight(y + 0.5) if rim_weight is not None else 1.0
        for x in range(width):
            sd_c = sd_rounded_box_lr(x + 0.5, y + 0.5, cx, cy, hx, hy, r_left, r_right)
            if sd_c < -(stroke_w + feather + 1.5):
                fill_alphas[row_off + x] = 255
                stroke_alphas[row_off + x] = 0
                continue
            if sd_c > 1.5:
                fill_alphas[row_off + x] = 0
                stroke_alphas[row_off + x] = 0
                continue

            f_acc = 0.0
            s_acc = 0.0
            for sy in range(sub):
                py = y + (sy + 0.5) * inv_sub
                for sx in range(sub):
                    px = x + (sx + 0.5) * inv_sub
                    sd = sd_rounded_box_lr(px, py, cx, cy, hx, hy, r_left, r_right)
                    if sd <= 0.0:
                        f_acc += 1.0
                    if -stroke_w <= sd <= 0.0:
                        s_acc += 1.0
                    elif -stroke_w - feather <= sd < -stroke_w:
                        s_acc += 0.22 * math.exp(sd / 0.9)
            fill_alphas[row_off + x] = round(f_acc * inv_total * 255.0)
            stroke_alphas[row_off + x] = round(s_acc * inv_total * weight * 255.0)

    return fill_alphas, stroke_alphas


def render_box_pair(
    width: int,
    height: int,
    radius: float,
    margin: float,
    stroke_w: float,
    rim_weight: Callable[[float], float] | None = None,
) -> tuple[list[int], list[int]]:
    """Compute top-down alpha maps for (fill, stroke) using supersampled SDF."""
    return render_box_pair_lr(width, height, radius, radius, margin, stroke_w, rim_weight)


def glass_rim_weight(y: float) -> float:
    # The top and bottom terms stay zero across the stretchable middle slice.
    return 0.54 + 0.46 * smoothstep(16.0, 0.0, y) + 0.18 * smoothstep(48.0, 64.0, y)


def pill_rim_weight(y: float) -> float:
    return 0.50 + 0.50 * smoothstep(32.0, 0.0, y) + 0.20 * smoothstep(32.0, 64.0, y)


def render_shadow_r22() -> list[int]:
    """128x128 soft Gaussian outer drop shadow for 0.25/0.75 9-slice."""
    size = 128
    cx = cy = 64.0
    hx = hy = 42.0  # inner solid box [22, 106], 22 + r(10) = 32 (exact 0.25/0.75 corner!)
    r = 10.0
    sigma = 8.2
    alphas = [0] * (size * size)
    for y in range(size):
        row_off = y * size
        for x in range(size):
            sd = sd_rounded_box(x + 0.5, y + 0.5, cx, cy, hx, hy, r)
            if sd <= 0.0:
                a = 1.0
            elif sd >= 21.5:
                a = 0.0
            else:
                a = math.exp(-((sd / sigma) ** 2)) * smoothstep(21.5, 13.5, sd)
            alphas[row_off + x] = round(clamp(a) * 255.0)
    return alphas


def render_specular_top() -> list[list[tuple[int, int, int, int]]]:
    return render_caustic_rows(64)


def build_rasterizer_html() -> str:
    payload = json.dumps(SF_ICONS)
    return f"""<!DOCTYPE html>
<html>
<head><meta charset="utf-8" /></head>
<body>
<script>
const ICONS = {payload};
async function run() {{
  const results = {{}};
  const canvas = document.createElement('canvas');
  canvas.width = 64;
  canvas.height = 64;
  const ctx = canvas.getContext('2d', {{ willReadFrequently: true }});

  for (const [name, body] of Object.entries(ICONS)) {{
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="64" height="64" fill="none" stroke="#FFFFFF" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${{body}}</svg>`;
    const url = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg);
    const img = new Image();
    img.src = url;
    await img.decode();
    ctx.clearRect(0, 0, 64, 64);
    ctx.drawImage(img, 0, 0, 64, 64);
    const data = ctx.getImageData(0, 0, 64, 64).data;
    const alpha = new Uint8Array(64 * 64);
    for (let i = 0; i < 64 * 64; i++) {{
      alpha[i] = data[i * 4 + 3];
    }}
    let bin = '';
    for (let i = 0; i < alpha.length; i++) {{
      bin += String.fromCharCode(alpha[i]);
    }}
    results[name] = btoa(bin);
  }}

  await fetch('/submit', {{
    method: 'POST',
    headers: {{ 'Content-Type': 'application/json' }},
    body: JSON.stringify(results)
  }});
}}
run();
</script>
</body>
</html>
"""


def rasterize_icons_via_chrome() -> dict[str, list[int]]:
    if CHROME_EXE is None or not CHROME_EXE.exists():
        raise FileNotFoundError("Chrome executable not found (pass --chrome-exe or set CHROME_BIN)")

    html_content = build_rasterizer_html()
    captured: dict[str, str] = {}
    done_event = threading.Event()

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, format: str, *args) -> None:
            pass

        def do_GET(self) -> None:
            body = html_content.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_POST(self) -> None:
            length = int(self.headers.get("Content-Length", "0"))
            raw = self.rfile.read(length)
            captured.update(json.loads(raw.decode("utf-8")))
            self.send_response(200)
            self.end_headers()
            done_event.set()

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    port = server.server_address[1]
    srv_thread = threading.Thread(target=server.serve_forever, daemon=True)
    srv_thread.start()

    with tempfile.TemporaryDirectory(prefix="mm_chrome_") as tmp_profile:
        proc = subprocess.Popen(
            [
                str(CHROME_EXE),
                "--headless=new",
                "--disable-gpu",
                "--no-sandbox",
                "--no-first-run",
                "--disable-extensions",
                f"--user-data-dir={tmp_profile}",
                f"http://127.0.0.1:{port}/",
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        try:
            if not done_event.wait(timeout=30.0):
                raise TimeoutError("Timed out waiting for headless Chrome SVG rasterization")
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=5.0)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5.0)
            server.shutdown()
            server.server_close()

    out: dict[str, list[int]] = {}
    for name in SF_ICONS:
        if name not in captured:
            raise KeyError(f"Missing icon output from Chrome: {name}")
        raw_bytes = base64.b64decode(captured[name])
        if len(raw_bytes) != 64 * 64:
            raise ValueError(f"Unexpected icon byte length for {name}: {len(raw_bytes)}")
        out[name] = list(raw_bytes)
    return out


def verify_tga_file(path: Path) -> tuple[int, int, int]:
    """Verify TGA header, footer, RGB=255 invariant, and non-empty alpha."""
    data = path.read_bytes()
    if len(data) < 44:
        raise ValueError(f"{path.name}: file too short ({len(data)} bytes)")
    id_len, cmap_type, img_type, _, _, _, _, _, w, h, bpp, desc = struct.unpack("<BBBHHBHHHHBB", data[:18])
    if id_len != 0 or cmap_type != 0 or img_type != 2 or bpp != 32 or desc != 0x08:
        raise ValueError(
            f"{path.name}: bad TGA header (type={img_type}, bpp={bpp}, desc=0x{desc:02x})"
        )
    expected_len = 18 + w * h * 4 + 26
    if len(data) != expected_len:
        raise ValueError(f"{path.name}: size {len(data)} != expected {expected_len}")
    if data[-26:] != TGA_FOOTER:
        raise ValueError(f"{path.name}: missing TGA 2.0 footer")

    px = data[18 : 18 + w * h * 4]
    max_alpha = 0
    for i in range(w * h):
        off = i * 4
        b, g, r, a = px[off], px[off + 1], px[off + 2], px[off + 3]
        if (b, g, r) != (255, 255, 255):
            raise ValueError(f"{path.name}: non-white RGB ({r},{g},{b}) at pixel {i}")
        if a > max_alpha:
            max_alpha = a
    if max_alpha == 0:
        raise ValueError(f"{path.name}: completely empty alpha channel")
    return w, h, max_alpha


def expected_apple_tgas() -> list[Path]:
    names = [
        "glass_r22_fill.tga", "glass_r22_stroke.tga",
        "glass_r16_fill.tga", "glass_r16_stroke.tga",
        "glass_r12_fill.tga", "glass_r12_stroke.tga",
        "glass_r10_fill.tga", "glass_r10_stroke.tga",
        "glass_r8_fill.tga", "glass_r8_stroke.tga",
        "glass_r22_openright_fill.tga", "glass_r22_openleft_fill.tga",
        "pill_fill.tga", "pill_stroke.tga",
        "circle_fill.tga", "circle_stroke.tga",
        "meter_track.tga", "meter_fill.tga",
        "shadow_r22.tga", "specular_top.tga",
    ] + [f"{name}.tga" for name in SF_ICONS]
    return [OUT_DIR / n for n in names]


def main() -> int:
    global CHROME_EXE
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--verify", action="store_true", help="Only verify existing Apple TGA & Liquid Glass BLP2 assets")
    ap.add_argument("--chrome-exe", type=Path, default=CHROME_EXE, help="Chrome executable for SVG icon rasterization")
    args = ap.parse_args()
    CHROME_EXE = find_chrome_exe(args.chrome_exe)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    generated: list[Path] = []

    if args.verify:
        generated = expected_apple_tgas()
        glass_layers = [
            (GLASS_DIR / "shade_v.blp", GLASS_W, GLASS_H),
            (GLASS_DIR / "header_wash.blp", GLASS_W, GLASS_H),
            (GLASS_DIR / "fade_lr.blp", GLASS_W, GLASS_H),
            (GLASS_DIR / "glow_line.tga", 128, 16),
        ]
    else:
        # 1. Rounded-glass 9-slice pairs (64x64, corners inside 16px = 0.25/0.75 UVs)
        glass_specs = [
            ("glass_r22", 16.0, 0.0, 1.1),
            ("glass_r16", 15.5, 0.0, 1.4),
            ("glass_r12", 12.0, 0.0, 1.4),
            ("glass_r10", 10.0, 0.0, 1.4),
            ("glass_r8", 8.0, 0.0, 1.4),
        ]
        for prefix, radius, margin, stroke_w in glass_specs:
            rim_weight = glass_rim_weight if prefix in ("glass_r22", "glass_r16") else None
            fill_a, stroke_a = render_box_pair(64, 64, radius, margin, stroke_w, rim_weight)
            fp = OUT_DIR / f"{prefix}_fill.tga"
            sp = OUT_DIR / f"{prefix}_stroke.tga"
            write_tga_white_alpha(fp, 64, 64, fill_a)
            write_tga_white_alpha(sp, 64, 64, stroke_a)
            generated.extend([fp, sp])

        # 1b. Split-pane openRight & openLeft r=22 fills (crisp 0px square open edge)
        openright_a, _ = render_box_pair_lr(64, 64, 16.0, 0.0, 0.0, 1.1)
        if openright_a[0] != 0 or openright_a[63] != 255 or openright_a[63 * 64 + 63] != 255:
            raise AssertionError("glass_r22_openright_fill square-edge invariant failed")
        orp = OUT_DIR / "glass_r22_openright_fill.tga"
        write_tga_white_alpha(orp, 64, 64, openright_a)
        generated.append(orp)

        openleft_a, _ = render_box_pair_lr(64, 64, 0.0, 16.0, 0.0, 1.1)
        if openleft_a[0] != 255 or openleft_a[63 * 64] != 255 or openleft_a[63] != 0:
            raise AssertionError("glass_r22_openleft_fill square-edge invariant failed")
        olp = OUT_DIR / "glass_r22_openleft_fill.tga"
        write_tga_white_alpha(olp, 64, 64, openleft_a)
        generated.append(olp)

        # 2. Pill & Circle pairs (64x64)
        pill_fill_a, pill_stroke_a = render_box_pair(64, 64, 31.0, 1.0, 1.4, pill_rim_weight)
        for fname, alpha in [("pill_fill.tga", pill_fill_a), ("pill_stroke.tga", pill_stroke_a)]:
            p = OUT_DIR / fname
            write_tga_white_alpha(p, 64, 64, alpha)
            generated.append(p)

        circ_fill_a, circ_stroke_a = render_box_pair(64, 64, 30.5, 1.5, 2.5)
        for fname, alpha in [("circle_fill.tga", circ_fill_a), ("circle_stroke.tga", circ_stroke_a)]:
            p = OUT_DIR / fname
            write_tga_white_alpha(p, 64, 64, alpha)
            generated.append(p)

        # 3. Meter track & fill (32x32 capsule)
        meter_a, _ = render_box_pair(32, 32, 15.0, 1.0, 1.5)
        for fname in ("meter_track.tga", "meter_fill.tga"):
            p = OUT_DIR / fname
            write_tga_white_alpha(p, 32, 32, meter_a)
            generated.append(p)

        # 4. Shadow & Specular surfaces
        shadow_p = OUT_DIR / "shadow_r22.tga"
        write_tga_white_alpha(shadow_p, 128, 128, render_shadow_r22())
        generated.append(shadow_p)

        spec_p = OUT_DIR / "specular_top.tga"
        write_tga_bgra(spec_p, 64, 16, render_specular_top())
        generated.append(spec_p)

        # 5. All 26 SF-Symbol & utility icons (64x64) via headless Chrome
        icons = rasterize_icons_via_chrome()
        for name, alpha in icons.items():
            p = OUT_DIR / f"{name}.tga"
            write_tga_white_alpha(p, 64, 64, alpha)
            generated.append(p)

        glass_layers = build_liquid_glass_layers()

    # 6. Strict header & pixel verification
    for p in generated:
        w, h, max_a = verify_tga_file(p)
        print(f"OK {p.name:24s} {w:3d}x{h:<3d} type=2 bpp=32 desc=0x08 max_a={max_a}")

    print(f"VERIFIED_COUNT={len(generated)}")

    # 7. Liquid Glass sidebar refraction layers (BLP2 DXT5 + glow_line.tga)
    for p, w, h in glass_layers:
        if p.suffix.lower() == ".blp":
            gw, gh, mips = verify_glass_blp2(p, w, h)
            print(f"OK {p.name:24s} {gw:3d}x{gh:<3d} BLP2 DXT5 mips={mips}")
        else:
            gw, gh, variety = verify_glass_tga(p, w, h)
            print(f"OK {p.name:24s} {gw:3d}x{gh:<3d} type=2 bpp=32 desc=0x08 variety={variety}")
    print(f"GLASS_LAYER_COUNT={len(glass_layers)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
