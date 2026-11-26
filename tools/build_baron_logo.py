#!/usr/bin/env python
"""Build Logo A (Trade Baron coin) textures for MerchantMaster.

Reads a source Baron logo PNG (passed via --src), decontaminates semi-transparent
outer pixels against dark tarnished gold (#241A0B) so WoW bilinear filtering never
shows a white halo, keeps a clean 2px transparent outer margin, and writes:
  - Textures/MerchantMasterLogo.blp   (256x256, native BLP2 DXT5 with mipmaps)
  - Textures/MerchantMasterLogo64.tga (64x64, uncompressed 32-bit BGRA TGA 2.0)

Usage (requires Pillow + numpy):
    python tools/build_baron_logo.py --src path/to/baron_logo_exact.png
    python tools/build_baron_logo.py --verify
"""
import argparse
import struct
import sys
from pathlib import Path
from typing import List, Optional, Tuple

import numpy as np
from PIL import Image, ImageFilter

RESAMPLE_LANCZOS = getattr(Image, "Resampling", Image).LANCZOS
ADDON = Path(__file__).resolve().parent.parent
OUT_256 = ADDON / "Textures" / "MerchantMasterLogo.blp"
OUT_64 = ADDON / "Textures" / "MerchantMasterLogo64.tga"
TGA_FOOTER = b"\x00" * 8 + b"TRUEVISION-XFILE.\x00"

# Dark tarnished gold (#241A0B) for halo-free bilinear filtering around the coin rim.
TARNISHED_GOLD = np.array([0x24 / 255.0, 0x1A / 255.0, 0x0B / 255.0], dtype=np.float32)


def to_pil(arr: np.ndarray) -> Image.Image:
    return Image.fromarray(np.clip(np.rint(arr * 255.0), 0, 255).astype(np.uint8), "RGBA")


def decontaminate(arr: np.ndarray, gold: np.ndarray = TARNISHED_GOLD) -> np.ndarray:
    """Decontaminate outer semi-transparent pixels and transparent backing against dark tarnished gold."""
    out = arr.copy()
    a = out[..., 3]
    # Kill wispy near-zero matte noise
    dead = a < 0.02
    out[dead, 3] = 0.0
    out[dead, :3] = gold
    # Pull semi-transparent fringe smoothly onto dark tarnished gold to prevent white halos
    semi = (out[..., 3] > 0.0) & (out[..., 3] < 0.96)
    if np.any(semi):
        sa = out[semi, 3:4]
        out[semi, :3] = np.clip(out[semi, :3] * sa + gold[None, :] * (1.0 - sa), 0.0, 1.0)
    return out


def trim_to_square(arr: np.ndarray, thresh: float = 0.02) -> np.ndarray:
    """Tightly crop to visible coin alpha and center in a square canvas."""
    ys, xs = np.where(arr[..., 3] > thresh)
    if len(xs) == 0:
        return arr
    crop = arr[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    ch, cw = crop.shape[:2]
    side = max(ch, cw)
    sq = np.zeros((side, side, 4), dtype=np.float32)
    sq[..., :3] = TARNISHED_GOLD
    y0 = (side - ch) // 2
    x0 = (side - cw) // 2
    sq[y0:y0 + ch, x0:x0 + cw] = crop
    return sq


def build_coin_canvas(
    src_square: np.ndarray,
    size: int,
    margin: int = 2,
    sharpen: bool = False,
) -> np.ndarray:
    """Fit the coin inside (size - 2*margin) with alpha-correct Lanczos resize and clean 2px margin."""
    inner = size - 2 * margin
    if inner < 4:
        raise ValueError("size %d too small for margin %d" % (size, margin))

    # Premultiplied-alpha Lanczos resize prevents dark/white edge ringing
    im_small = to_pil(src_square).convert("RGBa").resize((inner, inner), RESAMPLE_LANCZOS).convert("RGBA")
    small = np.asarray(im_small, dtype=np.float32) / 255.0

    if sharpen:
        # Composite onto tarnished gold before unsharp mask so sharpening never introduces white halos
        alpha = small[..., 3:4]
        comp_rgb = np.clip(small[..., :3] * alpha + TARNISHED_GOLD[None, None, :] * (1.0 - alpha), 0.0, 1.0)
        rgb_u8 = np.clip(np.rint(comp_rgb * 255.0), 0, 255).astype(np.uint8)
        sharp_im = Image.fromarray(rgb_u8, "RGB").filter(
            ImageFilter.UnsharpMask(radius=0.8, percent=85, threshold=2)
        )
        small[..., :3] = np.asarray(sharp_im, dtype=np.float32) / 255.0

    small = decontaminate(small)

    canvas = np.zeros((size, size, 4), dtype=np.float32)
    canvas[..., :3] = TARNISHED_GOLD
    canvas[margin:margin + inner, margin:margin + inner] = small

    # Enforce strict 2px transparent outer margin with tarnished gold RGB
    canvas[:margin, :, 3] = 0.0
    canvas[-margin:, :, 3] = 0.0
    canvas[:, :margin, 3] = 0.0
    canvas[:, -margin:, 3] = 0.0
    canvas[:margin, :, :3] = TARNISHED_GOLD
    canvas[-margin:, :, :3] = TARNISHED_GOLD
    canvas[:, :margin, :3] = TARNISHED_GOLD
    canvas[:, -margin:, :3] = TARNISHED_GOLD
    return canvas


def write_tga(path: Path, arr: np.ndarray) -> None:
    """Uncompressed 32-bit BGRA, image_type=2, bpp=32, descriptor=0x08 (bottom-left), TGA 2.0 footer."""
    h, w = arr.shape[:2]
    if (w & (w - 1)) or (h & (h - 1)) or w > 1024 or h > 1024:
        raise ValueError("%s: %dx%d is not power-of-2 <= 1024" % (path.name, w, h))
    px = np.clip(np.rint(arr * 255.0), 0, 255).astype(np.uint8)
    bgra = px[::-1, :, [2, 1, 0, 3]]  # bottom-left origin, BGRA
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 0x08)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(header + np.ascontiguousarray(bgra).tobytes() + TGA_FOOTER)


def read_tga(path: Path) -> Tuple[int, int, np.ndarray]:
    data = path.read_bytes()
    if len(data) < 18 + 26:
        raise ValueError("%s: file too short (%d bytes)" % (path.name, len(data)))
    id_len, cmap, itype, _, _, _, _, _, w, h, bpp, desc = struct.unpack("<BBBHHBHHHHBB", data[:18])
    if id_len != 0 or cmap != 0 or itype != 2 or bpp != 32 or desc != 0x08:
        raise ValueError(
            "%s: bad header (id=%d cmap=%d type=%d bpp=%d desc=0x%02x)"
            % (path.name, id_len, cmap, itype, bpp, desc)
        )
    expected = 18 + w * h * 4 + 26
    if len(data) != expected or data[-26:] != TGA_FOOTER:
        raise ValueError("%s: bad length (%d != %d) or missing TGA 2.0 footer" % (path.name, len(data), expected))
    px = np.frombuffer(data, dtype=np.uint8, count=w * h * 4, offset=18).reshape(h, w, 4)
    rgba = px[::-1, :, [2, 1, 0, 3]]
    return w, h, rgba


def _rgb888_to_565(rgb: np.ndarray) -> np.ndarray:
    r = (rgb[..., 0].astype(np.uint16) * 31 + 127) // 255
    g = (rgb[..., 1].astype(np.uint16) * 63 + 127) // 255
    b = (rgb[..., 2].astype(np.uint16) * 31 + 127) // 255
    return (r << 11) | (g << 5) | b


def _rgb565_to_888(c565: np.ndarray) -> np.ndarray:
    r = np.floor(((c565 >> 11) & 31).astype(np.float32) * 255.0 / 31.0 + 0.5)
    g = np.floor(((c565 >> 5) & 63).astype(np.float32) * 255.0 / 63.0 + 0.5)
    b = np.floor((c565 & 31).astype(np.float32) * 255.0 / 31.0 + 0.5)
    return np.stack([r, g, b], axis=-1)


def _encode_dxt5_blocks(rgba: np.ndarray) -> bytes:
    """Vectorized BC3 (DXT5, 16B/block) encoder."""
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
    same = c0 == c1
    p0 = _rgb565_to_888(c0)
    p1 = _rgb565_to_888(c1)
    p2 = (2.0 * p0 + p1) / 3.0
    p3 = (p0 + 2.0 * p1) / 3.0
    pal = np.stack([p0, p1, p2, p3], axis=1)
    diff = rgb[:, :, None, :] - pal[:, None, :, :]
    idx = np.argmin((diff * diff).sum(axis=-1), axis=-1).astype(np.uint32)
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
    )
    aidx = np.argmin(np.abs(a[:, :, None].astype(np.float32) - apal[:, None, :]), axis=-1).astype(np.uint64)
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


def write_blp2(path: Path, arr: np.ndarray) -> None:
    """Write WoW-native BLP2 (DXT5 RGBA) with full mipmap chain down to 1x1."""
    h, w = arr.shape[:2]
    if (w & (w - 1)) or (h & (h - 1)) or w > 1024 or h > 1024:
        raise ValueError("%s: %dx%d is not power-of-2 <= 1024" % (path.name, w, h))
    px = np.clip(np.rint(arr * 255.0), 0, 255).astype(np.uint8)
    im = Image.fromarray(px, "RGBA")
    mips: List[bytes] = []
    mw, mh = w, h
    while True:
        cur = np.asarray(im if (mw == w and mh == h) else im.resize((mw, mh), RESAMPLE_LANCZOS))
        mips.append(_encode_dxt5_blocks(cur))
        if mw == 1 and mh == 1:
            break
        mw = max(1, mw // 2)
        mh = max(1, mh // 2)

    offsets = [0] * 16
    lengths = [0] * 16
    cur_off = 148 + 1024
    for i, mdata in enumerate(mips[:16]):
        offsets[i] = cur_off
        lengths[i] = len(mdata)
        cur_off += len(mdata)

    header = struct.pack(
        "<4sIBBBBII16I16I",
        b"BLP2", 1, 2, 8, 7, 1, w, h, *offsets, *lengths,
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(header + (b"\x00" * 1024) + b"".join(mips[:16]))


def read_blp2(path: Path) -> Tuple[int, int, np.ndarray]:
    data = path.read_bytes()
    if len(data) < 1172 or data[:4] != b"BLP2":
        raise ValueError("%s: bad BLP2 magic or length (%d bytes)" % (path.name, len(data)))
    btype, enc, adepth, aenc, has_mips, w, h = struct.unpack_from("<IBBBBII", data, 4)
    offsets = struct.unpack_from("<16I", data, 20)
    lengths = struct.unpack_from("<16I", data, 84)
    if btype != 1 or enc != 2 or adepth != 8 or aenc != 7 or has_mips != 1:
        raise ValueError(
            "%s: bad BLP2 header (type=%d enc=%d adepth=%d aenc=%d mips=%d)"
            % (path.name, btype, enc, adepth, aenc, has_mips)
        )
    mip_count = sum(1 for ln in lengths if ln > 0)
    if mip_count < 2 or offsets[0] != 1172 or len(data) != 1172 + sum(lengths):
        raise ValueError("%s: bad BLP2 mipmap chain (mips=%d len=%d)" % (path.name, mip_count, len(data)))
    with Image.open(path) as im:
        rgba = np.asarray(im.convert("RGBA"), dtype=np.uint8)
    return w, h, rgba


def verify_logo(path: Path, expected_size: int, margin: int = 2) -> Optional[str]:
    if not path.exists():
        return "%s missing" % path
    try:
        if path.suffix.lower() == ".blp":
            w, h, rgba = read_blp2(path)
        else:
            w, h, rgba = read_tga(path)
    except ValueError as exc:
        return str(exc)
    if w != expected_size or h != expected_size:
        return "%s: expected %dx%d, got %dx%d" % (path.name, expected_size, expected_size, w, h)
    alpha = rgba[..., 3]
    if int(alpha.max()) < 250:
        return "%s: coin interior is not opaque (max alpha=%d)" % (path.name, int(alpha.max()))
    border_max = max(
        int(alpha[:margin, :].max()),
        int(alpha[-margin:, :].max()),
        int(alpha[:, :margin].max()),
        int(alpha[:, -margin:].max()),
    )
    if border_max != 0:
        return "%s: outer %dpx margin not transparent (max alpha=%d)" % (path.name, margin, border_max)
    zero_rgb = rgba[alpha == 0, :3]
    if zero_rgb.size > 0 and int(zero_rgb.max()) > 80:
        return "%s: bright RGB in transparent pixels (max=%d)" % (path.name, int(zero_rgb.max()))
    print("OK  %-28s %dx%d  bytes=%d  border_alpha=%d  zero_rgb_max=%d" % (
        path.name, w, h, path.stat().st_size, border_max, int(zero_rgb.max()) if zero_rgb.size else 0
    ))
    return None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--src", type=Path, default=None, help="Source Baron logo PNG (required unless --verify)")
    ap.add_argument("--verify", action="store_true", help="Only validate existing logo texture files")
    ap.add_argument("--preview-dir", type=Path, default=None, help="Optional directory to write preview PNGs")
    args = ap.parse_args()

    if not args.verify:
        if args.src is None:
            print("ERROR: --src is required when building (or pass --verify)", file=sys.stderr)
            return 2
        if not args.src.exists():
            print("ERROR: source PNG not found: %s" % args.src, file=sys.stderr)
            return 2
        raw = np.asarray(Image.open(args.src).convert("RGBA"), dtype=np.float32) / 255.0
        sq = trim_to_square(decontaminate(raw))
        arr_256 = build_coin_canvas(sq, 256, margin=2, sharpen=False)
        arr_64 = build_coin_canvas(sq, 64, margin=2, sharpen=True)
        write_blp2(OUT_256, arr_256)
        old_tga_256 = OUT_256.with_suffix(".tga")
        if old_tga_256.exists():
            old_tga_256.unlink()
        write_tga(OUT_64, arr_64)
        print("Wrote %s and %s" % (OUT_256, OUT_64))
        if args.preview_dir is not None:
            args.preview_dir.mkdir(parents=True, exist_ok=True)
            to_pil(arr_256).save(args.preview_dir / "MerchantMasterLogo_256.png")
            to_pil(arr_64).save(args.preview_dir / "MerchantMasterLogo_64.png")

    errors = []
    for path, sz in ((OUT_256, 256), (OUT_64, 64)):
        err = verify_logo(path, sz, margin=2)
        if err:
            errors.append(err)
            print("FAIL:", err, file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
