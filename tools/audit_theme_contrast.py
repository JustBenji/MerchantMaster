#!/usr/bin/env python3
"""
WCAG contrast audit over the JSON scene trees emitted by tools/lua_frame_dump.lua.

For every visible text run (FontString base colour + each inline |cffRRGGBB segment)
the audit composites the fills / textures drawn underneath it, then reports any run
whose contrast ratio against that backdrop is below the threshold.

Usage:
  lua tools/lua_frame_dump.lua <dump-dir> --audit
  python tools/audit_theme_contrast.py <dump-dir> [--min 3.0] [--scenes a b ...]

Exit code 1 when any run is below --min.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parent))
from render_lua_preview import ADDON_DIR, TextureCache, decode_tga  # noqa: E402

RGB = Tuple[float, float, float]
_TOKEN_RE = re.compile(r"(\|c[0-9a-fA-F]{8}|\|r|\|T[^|]+\|t|\|n)")
# Wallpaper behind the window: only matters for text that sits on nothing at all.
BACKDROP: Dict[str, RGB] = {"dark": (0.06, 0.07, 0.13), "light": (0.20, 0.22, 0.36)}


def luminance(c: RGB) -> float:
    def lin(v: float) -> float:
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    return 0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2])


def contrast(a: RGB, b: RGB) -> float:
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def over(dst: RGB, src: RGB, alpha: float) -> RGB:
    a = max(0.0, min(1.0, alpha))
    return (dst[0] + (src[0] - dst[0]) * a, dst[1] + (src[1] - dst[1]) * a, dst[2] + (src[2] - dst[2]) * a)


class Sampler:
    """Samples straight-alpha RGBA texels of addon .tga files by WoW texture path."""

    def __init__(self) -> None:
        self.cache = TextureCache(ADDON_DIR)
        self.raw: Dict[Path, Tuple[int, int, bytearray]] = {}

    def sample(self, wow_path: str, tex_coord: List[float], fx: float, fy: float, item: Optional[dict] = None) -> Optional[Tuple[float, float, float, float]]:
        p = self.cache.resolve_tga_path(wow_path)
        if not p:
            return None
        if p not in self.raw:
            self.raw[p] = decode_tga(p)
        w, h, px = self.raw[p]
        l, r, t, b = [float(v) for v in (tex_coord or [0, 1, 0, 1])]
        item = item or {}
        if item.get("horizTile") or item.get("vertTile"):
            cw, ch = self.cache.native_size(wow_path, tex_coord)
            if item.get("horizTile"):
                fx = (fx * item["w"] / cw) % 1.0
            if item.get("vertTile"):
                fy = (fy * item["h"] / ch) % 1.0
        u = l + (r - l) * fx
        v = t + (b - t) * fy
        quad = item.get("texQuad")
        if quad and len(quad) == 8:
            ulx, uly, blx, bly, urx, ury, brx, bry = quad
            u = (1 - fy) * (ulx + (urx - ulx) * fx) + fy * (blx + (brx - blx) * fx)
            v = (1 - fy) * (uly + (ury - uly) * fx) + fy * (bly + (bry - bly) * fx)
        if any(uv < 0 or uv > 1 for uv in (l, r, t, b)):
            u, v = u % 1.0, v % 1.0
        x = max(0, min(w - 1, int(u * w)))
        y = max(0, min(h - 1, int(v * h)))
        o = (y * w + x) * 4
        return px[o] / 255.0, px[o + 1] / 255.0, px[o + 2] / 255.0, px[o + 3] / 255.0


def inside(item: dict, x: float, y: float) -> bool:
    clip = item.get("clip")
    if clip and not (clip["x"] <= x <= clip["x"] + clip["w"] and clip["y"] <= y <= clip["y"] + clip["h"]):
        return False
    return item["x"] <= x <= item["x"] + item["w"] and item["y"] <= y <= item["y"] + item["h"]


def layer_at(item: dict, x: float, y: float, sampler: Sampler) -> Optional[Tuple[RGB, float]]:
    """Colour + alpha this draw item contributes at (x, y), or None."""
    kind = item.get("kind")
    if kind not in ("color", "texture", "backdrop") or item.get("blend") == "ADD":
        return None
    if "x" not in item or item.get("w", 0) <= 0 or item.get("h", 0) <= 0 or not inside(item, x, y):
        return None
    alpha = float(item.get("alpha", 1.0))
    if kind == "color":
        c = item.get("color", [1, 1, 1, 1])
        return (c[0], c[1], c[2]), alpha * (c[3] if len(c) > 3 else 1.0)
    if kind == "backdrop":
        c = item.get("bgColor", [0, 0, 0, 0])
        return (c[0], c[1], c[2]), alpha * (c[3] if len(c) > 3 else 1.0)
    vc = item.get("vertexColor") or [1, 1, 1, 1]
    texel = sampler.sample(item.get("texture", ""), item.get("texCoord"), (x - item["x"]) / item["w"], (y - item["y"]) / item["h"], item)
    if texel is None:
        return None
    return (texel[0] * vc[0], texel[1] * vc[1], texel[2] * vc[2]), alpha * texel[3] * (vc[3] if len(vc) > 3 else 1.0)


def text_runs(item: dict) -> List[Tuple[str, RGB, float]]:
    base = item.get("color") or [1, 1, 1, 1]
    base_rgb, base_a = (base[0], base[1], base[2]), (base[3] if len(base) > 3 else 1.0)
    runs: List[Tuple[str, RGB, float]] = []
    stack: List[Tuple[RGB, float]] = []
    for tok in _TOKEN_RE.split(item.get("text", "") or ""):
        if not tok:
            continue
        if tok.startswith("|c") and len(tok) == 10:
            stack.append(((int(tok[4:6], 16) / 255.0, int(tok[6:8], 16) / 255.0, int(tok[8:10], 16) / 255.0), 1.0))
        elif tok == "|r":
            if stack:
                stack.pop()
        elif tok.startswith("|T") or tok == "|n":
            continue
        elif re.search(r"[0-9A-Za-z]", tok):
            rgb, a = stack[-1] if stack else (base_rgb, base_a)
            runs.append((tok.strip(), rgb, a))
    return runs


def probe_point(item: dict) -> Tuple[float, float]:
    jh = str(item.get("justifyH", "CENTER")).upper()
    w = float(item["w"])
    pad = min(6.0, w * 0.5)
    if jh == "LEFT":
        x = item["x"] + pad
    elif jh == "RIGHT":
        x = item["x"] + w - pad
    else:
        x = item["x"] + w * 0.5
    return x, item["y"] + float(item["h"]) * 0.5


def audit_scene(path: Path, sampler: Sampler, min_ratio: float) -> List[dict]:
    scene = json.loads(path.read_text(encoding="utf-8"))
    mode = scene.get("mode", "dark")
    items = scene.get("items", [])
    findings: List[dict] = []
    for idx, item in enumerate(items):
        if item.get("kind") != "text" or float(item.get("alpha", 1.0)) < 0.05:
            continue
        x, y = probe_point(item)
        clip = item.get("clip")
        if clip and not (clip["x"] <= x <= clip["x"] + clip["w"] and clip["y"] <= y <= clip["y"] + clip["h"]):
            continue
        # Skip text buried under a later near-opaque surface (e.g. the main window behind a modal).
        occluded = False
        for later in items[idx + 1:]:
            hit = layer_at(later, x, y, sampler)
            if hit and hit[1] >= 0.85:
                occluded = True
                break
        if occluded:
            continue
        bg = BACKDROP.get(mode, BACKDROP["dark"])
        for under in items[:idx]:
            hit = layer_at(under, x, y, sampler)
            if hit and hit[1] > 0.002:
                bg = over(bg, hit[0], hit[1])
        item_alpha = float(item.get("alpha", 1.0))
        for text, rgb, a in text_runs(item):
            ink = over(bg, rgb, a * item_alpha)
            ratio = contrast(ink, bg)
            if ratio < min_ratio:
                findings.append({
                    "scene": path.stem, "text": text[:48], "ratio": ratio,
                    "ink": "#%02x%02x%02x" % tuple(int(round(v * 255)) for v in rgb),
                    "inkAlpha": round(a * item_alpha, 2),
                    "bg": "#%02x%02x%02x" % tuple(int(round(v * 255)) for v in bg),
                    "x": round(x), "y": round(y),
                })
    return findings


def main() -> int:
    ap = argparse.ArgumentParser(description="WCAG contrast audit over lua_frame_dump.lua scene JSON.")
    ap.add_argument("dump_dir", nargs="?", default=str(Path(__file__).resolve().parent / "scene_dumps"))
    ap.add_argument("--min", type=float, default=3.0, help="Minimum contrast ratio (default 3.0)")
    ap.add_argument("--scenes", nargs="*", default=None, help="Scene names (default: every *.json in dump_dir)")
    args = ap.parse_args()

    dump_dir = Path(args.dump_dir)
    paths = [dump_dir / f"{s}.json" for s in args.scenes] if args.scenes else sorted(dump_dir.glob("*.json"))
    if not paths:
        print(f"[contrast] ERROR: no JSON scenes in {dump_dir}", file=sys.stderr)
        return 2
    sampler = Sampler()
    total = 0
    for p in paths:
        findings = audit_scene(p, sampler, args.min)
        seen = set()
        unique = []
        for f in findings:
            key = (f["text"], f["ink"], f["bg"])
            if key not in seen:
                seen.add(key)
                unique.append(f)
        total += len(unique)
        print(f"[contrast] {p.stem}: {len(unique)} run(s) below {args.min:.1f}:1")
        for f in sorted(unique, key=lambda d: d["ratio"]):
            print(f"    {f['ratio']:.2f}:1  ink {f['ink']} a={f['inkAlpha']}  on {f['bg']}  @({f['x']},{f['y']})  \"{f['text']}\"")
    print(f"CONTRAST_SCENES={len(paths)} BELOW_MIN={total} MIN={args.min:.1f}")
    return 1 if total else 0


if __name__ == "__main__":
    raise SystemExit(main())
