#!/usr/bin/env python3
"""Generate Roocast App Icon — LOCKED 2026-11-18 (Scripts/icon/locked.png).

Same-family as Exp-Z: cyan→lime 3D wordmark; flat baseline + italic shear;
dual-mode slate field. Two-row "Roo"/"cast" (Roo @ 0.63, nudge_x 0).

  .venv/bin/python Scripts/generate_app_icon.py --install   # writes Assets + icns

Do not casual-tweak tunables below — bump iter + update Scripts/icon/LOCKED.md.
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ICON_DIR = ROOT / "Scripts" / "icon"
ASSETS_PNG = ROOT / "Sources" / "Roocast" / "Resources" / "AppIcon.png"
ICNS_OUT = ROOT / "Sources" / "Roocast" / "Resources" / "AppIcon.icns"

# --- Tunables (LOCKED 2026-11-18 — Scripts/icon/LOCKED.md) --------------------
# Two-row "Roo"/"cast": Roo @ 63%, ink-aligned (nudge_x 0), tight gap.
# Fallback single-line mark: Scripts/icon/locked-fallback-roo.png.
SIZE = 1024
FONT_PATH = "/System/Library/Fonts/Avenir Next.ttc"
FONT_INDEX = 8  # Heavy
FONT_SIZE = 380  # cast (primary) size; Roo scale is relative to this
ROW_ROO = {"text": "Roo", "scale": 0.63, "nudge_x": 0.0}
ROW_CAST = {"text": "cast", "scale": 1.0, "nudge_x": 0.0}
ROW_GAP_FRAC = 0.04  # ink-bottom(Roo) → ink-top(cast) / cast ink height
DEPTH = 72
DX = -0.72
DY = 0.95
LETTER_TILT_DEG = -14.0
CYAN = (0, 245, 235)
LIME = (100, 255, 75)
SIDE = (0, 95, 130)
TOP = (160, 255, 255)
BG_CENTER = (28, 48, 58)
BG_EDGE = (12, 22, 32)
MASK_RADIUS = 0.2237
MASK_CLEARANCE = 72
WORK_PAD = 1.15
# ------------------------------------------------------------------------------


def load_font(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT_PATH, size=size, index=FONT_INDEX)


def ios_safe_mask(size: int) -> np.ndarray:
    inset = int(round(MASK_CLEARANCE * (size / 1024.0)))
    r = max(0, int(round(size * MASK_RADIUS)) - inset)
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle(
        (inset, inset, size - 1 - inset, size - 1 - inset), radius=r, fill=255
    )
    return np.array(m) > 0


def ios_visible_mask(size: int) -> np.ndarray:
    m = Image.new("L", (size, size), 0)
    r = int(round(size * MASK_RADIUS))
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size - 1, size - 1), radius=r, fill=255)
    return np.array(m) > 0


def _advance(font: ImageFont.FreeTypeFont, text: str) -> float:
    try:
        return float(font.getlength(text))
    except Exception:
        bb = font.getbbox(text)
        return float(bb[2] - bb[0])


def _harden(layer: Image.Image, fill: tuple[int, int, int]) -> Image.Image:
    arr = np.array(layer)
    solid = arr[:, :, 3] > 100
    out = np.zeros_like(arr)
    out[solid, 0] = fill[0]
    out[solid, 1] = fill[1]
    out[solid, 2] = fill[2]
    out[solid, 3] = 255
    return Image.fromarray(out)


def _italic_shear(layer: Image.Image, base_y: float) -> Image.Image:
    """Shear around `base_y` so the baseline row stays fixed (Exp-Z)."""
    import math

    if abs(LETTER_TILT_DEG) < 0.01:
        return layer
    size = layer.size[0]
    shear = math.tan(math.radians(LETTER_TILT_DEG))
    pad_x = int(abs(shear) * size) + 8
    wide = Image.new("RGBA", (size + 2 * pad_x, size), (0, 0, 0, 0))
    wide.paste(layer, (pad_x, 0), layer)
    sheared = wide.transform(
        wide.size,
        Image.Transform.AFFINE,
        (1.0, shear, -shear * base_y, 0.0, 1.0, 0.0),
        resample=Image.Resampling.BICUBIC,
    )
    return sheared.crop((pad_x, 0, pad_x + size, size))


def _ink_left(layer: Image.Image) -> int | None:
    a = np.array(layer)[:, :, 3] > 12
    xs = np.where(a)[1]
    return int(xs.min()) if len(xs) else None


def _ink_bbox(layer: Image.Image) -> tuple[int, int, int, int] | None:
    a = np.array(layer)[:, :, 3] > 12
    ys, xs = np.where(a)
    if len(xs) == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def _draw_row(
    size: int,
    text: str,
    font: ImageFont.FreeTypeFont,
    fill: tuple[int, int, int],
    *,
    hard_alpha: bool,
) -> Image.Image:
    """Draw one sheared row centered on the canvas (position refined later)."""
    ascent, descent = font.getmetrics()
    base_y = (size - (ascent + descent)) / 2 + ascent
    left_x = size * 0.25
    row = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(row).text(
        (left_x, base_y), text, font=font, fill=(*fill, 255), anchor="ls"
    )
    if hard_alpha:
        row = _harden(row, fill)
    return _italic_shear(row, base_y)


def draw_text_layer(
    size: int,
    font: ImageFont.FreeTypeFont,
    fill: tuple[int, int, int],
    ox: int = 0,
    oy: int = 0,
    *,
    hard_alpha: bool = False,
) -> Image.Image:
    """Stack smaller "Roo" over larger "cast" (locked diagram layout).

    Vertical gap is measured ink-to-ink. Horizontally, rows are ink-aligned,
    then Roo is offset by `ROW_ROO["nudge_x"]` (0 = aligned with cast).
    """
    # `font` is the cast (primary) size from compose_glyph; Roo is scaled from it.
    cast_size = getattr(font, "size", FONT_SIZE)
    roo_font = load_font(max(1, int(round(cast_size * float(ROW_ROO["scale"])))))
    cast_font = font

    blank = lambda: Image.new("RGBA", (size, size), (0, 0, 0, 0))
    roo = _draw_row(size, str(ROW_ROO["text"]), roo_font, fill, hard_alpha=hard_alpha)
    cast = _draw_row(size, str(ROW_CAST["text"]), cast_font, fill, hard_alpha=hard_alpha)

    roo_bb = _ink_bbox(roo)
    cast_bb = _ink_bbox(cast)
    if roo_bb is None or cast_bb is None:
        raise RuntimeError("empty wordmark row")

    # Left-align by ink, then nudge Roo further left (diagram: Roo sits slightly left).
    nudge = int(round(float(ROW_ROO["nudge_x"]) * size))
    roo = _offset_paste(blank(), roo, (cast_bb[0] - roo_bb[0]) + nudge, 0)
    roo_bb = _ink_bbox(roo)
    assert roo_bb is not None

    # Pull Roo down so its ink-bottom sits `gap` above cast's ink-top.
    gap = max(2, int(round((cast_bb[3] - cast_bb[1]) * ROW_GAP_FRAC)))
    roo = _offset_paste(blank(), roo, 0, (cast_bb[1] - gap - (roo_bb[3] - roo_bb[1])) - roo_bb[1])

    stacked = Image.alpha_composite(cast, roo)
    bbox = _ink_bbox(stacked)
    if bbox is None:
        return stacked
    x0, y0, x1, y1 = bbox
    dx = (size - (x1 - x0)) // 2 - x0 + ox
    dy = (size - (y1 - y0)) // 2 - y0 + oy
    return _offset_paste(blank(), stacked, dx, dy)


def soft_background(size: int) -> Image.Image:
    """Clean dual-mode field — radial slate→teal only."""
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    cx = cy = (size - 1) / 2.0
    dist = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / (np.sqrt(2.0) * cx)
    dist = np.clip(dist, 0, 1)
    lift = np.clip(1.0 - (yy / (size - 1)) * 0.15, 0.85, 1.0)
    center = np.array(BG_CENTER, dtype=np.float32)
    edge = np.array(BG_EDGE, dtype=np.float32)
    rgb = (center * (1 - dist[..., None]) + edge * dist[..., None]) * lift[..., None]
    return Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8)).convert("RGBA")


def _recolor(layer: Image.Image, fill: tuple[int, int, int], alpha_scale: float = 1.0) -> Image.Image:
    arr = np.array(layer)
    solid = arr[:, :, 3] > 100
    out = np.zeros_like(arr)
    out[solid, 0] = fill[0]
    out[solid, 1] = fill[1]
    out[solid, 2] = fill[2]
    out[solid, 3] = int(255 * alpha_scale)
    return Image.fromarray(out)


def _offset_paste(canvas: Image.Image, layer: Image.Image, ox: int, oy: int) -> Image.Image:
    tmp = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    tmp.paste(layer, (ox, oy), layer)
    return Image.alpha_composite(canvas, tmp)


def compose_glyph(work: int, font_size: int, depth: int) -> Image.Image:
    font = load_font(font_size)
    base = draw_text_layer(work, font, (255, 255, 255), hard_alpha=True)

    canvas = Image.new("RGBA", (work, work), (0, 0, 0, 0))

    shadow = _recolor(base, (0, 160, 140), alpha_scale=0.28)
    shadow = shadow.filter(ImageFilter.GaussianBlur(10))
    canvas = _offset_paste(canvas, shadow, 10, 16)

    for i in range(depth, 0, -1):
        ox = int(round(i * DX))
        oy = int(round(i * DY))
        fill = TOP if i <= max(2, depth // 14) else SIDE
        canvas = _offset_paste(canvas, _recolor(base, fill), ox, oy)

    mask = base.split()[-1]
    yy, xx = np.mgrid[0:work, 0:work].astype(np.float32)
    t = np.clip(xx / max(work - 1, 1) * 0.35 + yy / max(work - 1, 1) * 0.65, 0, 1)
    c = np.array(CYAN, dtype=np.float32)
    l = np.array(LIME, dtype=np.float32)
    rgb = c * (1 - t[..., None]) + l * t[..., None]
    sheen = np.clip(
        (xx / max(work - 1, 1) * 0.6 + (1 - yy / max(work - 1, 1)) * 0.7 - 0.35) * 55, 0, 55
    )
    rgb = np.clip(rgb + sheen[..., None], 0, 255).astype(np.uint8)
    face = Image.fromarray(rgb).convert("RGBA")
    face.putalpha(mask)
    canvas = Image.alpha_composite(canvas, face)

    a = np.array(canvas)[:, :, 3] > 12
    ys, xs = np.where(a)
    if len(xs) == 0:
        raise RuntimeError("empty glyph")
    border = 4
    hit = (
        int(xs.min()) < border
        or int(ys.min()) < border
        or int(xs.max()) >= work - border
        or int(ys.max()) >= work - border
    )
    if hit:
        pad = max(
            border - int(xs.min()),
            border - int(ys.min()),
            int(xs.max()) - (work - 1 - border),
            int(ys.max()) - (work - 1 - border),
            0,
        ) + 32
        bigger = Image.new("RGBA", (work + 2 * pad, work + 2 * pad), (0, 0, 0, 0))
        bigger.paste(canvas, (pad, pad), canvas)
        canvas = bigger
        print(f"note: padded work canvas by {pad}px")
    return canvas


def crop_ink(glyph: Image.Image, pad: int = 8) -> Image.Image:
    a = np.array(glyph)[:, :, 3] > 12
    ys, xs = np.where(a)
    return glyph.crop(
        (
            max(0, int(xs.min()) - pad),
            max(0, int(ys.min()) - pad),
            min(glyph.size[0], int(xs.max()) + 1 + pad),
            min(glyph.size[1], int(ys.max()) + 1 + pad),
        )
    )


def place_scaled(crop: Image.Image, size: int, scale: float) -> Image.Image:
    nw = max(1, int(round(crop.size[0] * scale)))
    nh = max(1, int(round(crop.size[1] * scale)))
    fitted = crop.resize((nw, nh), Image.Resampling.LANCZOS)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(fitted, ((size - nw) // 2, (size - nh) // 2), fitted)
    return out


def fits(glyph: Image.Image, safe: np.ndarray) -> bool:
    ink = np.array(glyph)[:, :, 3] > 12
    return not np.any(ink & ~safe)


def fit_to_ios_mask(glyph: Image.Image, size: int) -> Image.Image:
    safe = ios_safe_mask(size)
    crop = crop_ink(glyph)
    lo, hi = 0.05, min(1.8, (size * 0.98) / max(crop.size))
    best = place_scaled(crop, size, lo)
    for _ in range(24):
        mid = (lo + hi) / 2
        cand = place_scaled(crop, size, mid)
        if fits(cand, safe):
            best = cand
            lo = mid
        else:
            hi = mid
    if not fits(best, safe):
        raise RuntimeError("could not fit glyph inside safe mask")
    return best


def compose(size: int = SIZE) -> Image.Image:
    out_hi = size * 2
    work = int(round(out_hi * (1.0 + WORK_PAD)))
    scale = out_hi / 1024.0
    glyph = compose_glyph(work, int(FONT_SIZE * scale), max(1, int(round(DEPTH * scale))))
    fitted = fit_to_ios_mask(glyph, out_hi)
    icon = Image.alpha_composite(soft_background(out_hi), fitted)
    return icon.resize((size, size), Image.Resampling.LANCZOS).convert("RGB")


def masked_preview(icon: Image.Image, out: Path) -> None:
    s = icon.size[0]
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, s - 1, s - 1), radius=int(s * MASK_RADIUS), fill=255
    )
    wall = Image.new("RGBA", (s, s), (175, 155, 200, 255))
    layer = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    layer.paste(icon.convert("RGBA"), (0, 0), mask)
    Image.alpha_composite(wall, layer).save(out)


def verify(icon: Image.Image) -> dict:
    s = icon.size[0]
    visible = ios_visible_mask(s)
    arr = np.array(icon).astype(np.int16)
    ink = (arr[:, :, 1] > 150) & (arr[:, :, 1] - arr[:, :, 0] > 45) & (arr[:, :, 0] < 200)
    clipped = int((ink & ~visible).sum())
    ys, xs = np.where(ink)
    return {
        "clipped_px": clipped,
        "margins_LRTB": (int(xs.min()), int(s - 1 - xs.max()), int(ys.min()), int(s - 1 - ys.max()))
        if len(xs)
        else None,
        "ink_bbox_w": int(xs.max() - xs.min()) if len(xs) else 0,
    }


def build_icns(png: Path, icns: Path) -> None:
    """Build a multi-resolution .icns from the 1024 master PNG."""
    sizes = [16, 32, 64, 128, 256, 512, 1024]
    with tempfile.TemporaryDirectory(prefix="roocast-iconset-") as tmp:
        iconset = Path(tmp) / "AppIcon.iconset"
        iconset.mkdir()
        for size in sizes:
            for scale, suffix in ((1, ""), (2, "@2x")):
                px = size * scale
                if px > 1024:
                    continue
                out = iconset / f"icon_{size}x{size}{suffix}.png"
                subprocess.run(
                    ["sips", "-z", str(px), str(px), str(png), "--out", str(out)],
                    check=True,
                    capture_output=True,
                )
        icns.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(icns)], check=True)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=None)
    ap.add_argument("--install", action="store_true")
    ap.add_argument("--size", type=int, default=SIZE)
    args = ap.parse_args()

    icon = compose(args.size)
    stats = verify(icon)
    print(f"verify: {stats}")
    if stats["clipped_px"] != 0:
        raise SystemExit(f"FAIL: {stats['clipped_px']} ink px outside iOS mask")

    if args.install:
        ASSETS_PNG.parent.mkdir(parents=True, exist_ok=True)
        icon.save(ASSETS_PNG, "PNG")
        print(f"installed → {ASSETS_PNG}")
        build_icns(ASSETS_PNG, ICNS_OUT)
        print(f"icns → {ICNS_OUT}")
        locked = ICON_DIR / "locked.png"
        ICON_DIR.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ASSETS_PNG, locked)
        masked_preview(icon, ICON_DIR / "locked-masked.png")
        print(f"locked → {locked}")

    out = args.out or (None if args.install else ICON_DIR / "iter-01.png")
    if out is not None:
        out.parent.mkdir(parents=True, exist_ok=True)
        icon.save(out, "PNG")
        print(f"wrote → {out}")
        mp = out.with_name(out.stem + "-masked.png")
        masked_preview(icon, mp)
        print(f"masked → {mp}")


if __name__ == "__main__":
    main()
