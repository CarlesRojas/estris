#!/usr/bin/env python3
"""Draws src/Estris/Assets/Estris.ico: the bento box in white on the Mac icon's dark grey gradient,
as a Windows tile: gently rounded corners, the box filling more of it so it reads at 16 px.

    uv run --with pillow windows/scripts/make-icon.py
"""
from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent.parent / "src/Estris/Assets/Estris.ico"
TOP, BOTTOM = (0x2C, 0x2C, 0x2E), (0x14, 0x14, 0x16)
SIZES = [16, 20, 24, 32, 40, 48, 64, 128, 256]


def icon(size):
    n = size * 4
    unit = n / 16
    image = Image.new("RGBA", (n, n))
    draw = ImageDraw.Draw(image)
    for y in range(n):
        draw.line([(0, y), (n, y)], fill=tuple(int(a + (b - a) * y / n) for a, b in zip(TOP, BOTTOM)) + (255,))
    mask = Image.new("L", (n, n), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, n - 1, n - 1), radius=2.6 * unit, fill=255)
    image.putalpha(mask)
    for box in [(3, 3, 7.5, 13), (8.5, 3, 13, 7.5), (8.5, 8.5, 13, 13)]:
        draw.rounded_rectangle([v * unit for v in box], radius=0.9 * unit, fill=(255, 255, 255, 255))
    return image.resize((size, size), Image.LANCZOS)


icons = [icon(size) for size in SIZES]
icons[-1].save(OUT, sizes=[(s, s) for s in SIZES], append_images=icons[:-1])
