#!/usr/bin/env python3
"""Draws the Home Widgets app icon and writes Resources/AppIcon.icns.

Needs Pillow (pip install pillow). Run from the repo root:  python3 scripts/make-icon.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SCALE = 4  # draw big, then downsample for smooth edges
S = SIZE * SCALE


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def vertical_gradient(size, top, bottom):
    img = Image.new("RGBA", size)
    draw = ImageDraw.Draw(img)
    for y in range(size[1]):
        draw.line([(0, y), (size[0], y)], fill=lerp(top, bottom, y / max(1, size[1] - 1)))
    return img


def rounded_mask(size, radius):
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return mask


def main():
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    # macOS icon grid: ~824px body centered in 1024 with a soft shadow.
    body = int(824 * SCALE)
    offset = (S - body) // 2
    radius = int(185 * SCALE)

    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [offset, offset + 18 * SCALE, offset + body, offset + body + 18 * SCALE], radius=radius, fill=(0, 0, 0, 110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(28 * SCALE))
    canvas.alpha_composite(shadow)

    background = vertical_gradient((body, body), (88, 110, 235, 255), (176, 92, 214, 255))
    glow = Image.new("RGBA", (body, body), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([body * 0.35, -body * 0.35, body * 1.35, body * 0.55], fill=(255, 255, 255, 70))
    glow = glow.filter(ImageFilter.GaussianBlur(90 * SCALE))
    background.alpha_composite(glow)
    canvas.paste(background, (offset, offset), rounded_mask((body, body), radius))

    # Four "widgets": two small squares on top, one wide tile below.
    pad = int(118 * SCALE)
    gap = int(52 * SCALE)
    inner = body - 2 * pad
    small = (inner - gap) // 2
    tile_radius = int(62 * SCALE)
    tiles = [
        (offset + pad, offset + pad, small, small),
        (offset + pad + small + gap, offset + pad, small, small),
        (offset + pad, offset + pad + small + gap, inner, small),
    ]

    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    for x, y, w, h in tiles:
        draw.rounded_rectangle([x, y, x + w, y + h], radius=tile_radius, fill=(255, 255, 255, 215))
    canvas.alpha_composite(layer)

    details = ImageDraw.Draw(canvas)
    # Clock tile: a ring with hands.
    x, y, w, h = tiles[0]
    cx, cy, r = x + w / 2, y + h / 2, w * 0.3
    details.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(88, 110, 235, 255), width=int(16 * SCALE))
    details.line([(cx, cy), (cx, cy - r * 0.62)], fill=(40, 40, 60, 255), width=int(14 * SCALE))
    details.line([(cx, cy), (cx + r * 0.5, cy + r * 0.12)], fill=(40, 40, 60, 255), width=int(14 * SCALE))
    # Gauge tile: a 70% arc.
    x, y, w, h = tiles[1]
    cx, cy, r = x + w / 2, y + h / 2, w * 0.3
    details.arc([cx - r, cy - r, cx + r, cy + r], start=0, end=360, fill=(220, 210, 240, 255), width=int(20 * SCALE))
    details.arc([cx - r, cy - r, cx + r, cy + r], start=-90, end=162, fill=(176, 92, 214, 255), width=int(20 * SCALE))
    # Wide tile: a sparkline.
    x, y, w, h = tiles[2]
    points = [0.55, 0.62, 0.45, 0.5, 0.3, 0.42, 0.25, 0.35, 0.2]
    line = [(x + w * (0.12 + 0.76 * i / (len(points) - 1)), y + h * (0.2 + 0.6 * p)) for i, p in enumerate(points)]
    details.line(line, fill=(88, 110, 235, 255), width=int(18 * SCALE), joint="curve")

    icon = canvas.resize((SIZE, SIZE), Image.LANCZOS)
    out = Path(__file__).resolve().parent.parent / "Resources"
    out.mkdir(exist_ok=True)
    icon.save(out / "AppIcon.png")
    icon.save(out / "AppIcon.icns", sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)])
    print("wrote", out / "AppIcon.icns")


if __name__ == "__main__":
    main()
