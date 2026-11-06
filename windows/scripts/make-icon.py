#!/usr/bin/env python3
"""Draws src/Estris/Assets/Estris.ico: the bento box in white on the Mac icon's dark grey gradient,
as a Windows tile: gently rounded corners, the box filling more of it so it reads at 16 px,
its edges on whole pixels at every size. `Ui/AppLogo.cs` draws the same in the app's own pages.

    uv run --with pillow windows/scripts/make-icon.py
"""
import math
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
    def edge(position):
        return math.floor(position * size / 16 + 0.49) * 4

    def mirrored(position):
        return n - edge(16 - position)

    for box in [(edge(3), edge(3), edge(7.5), mirrored(13)), (mirrored(8.5), edge(3), mirrored(13), edge(7.5)),
                (mirrored(8.5), mirrored(8.5), mirrored(13), mirrored(13))]:
        draw.rounded_rectangle(box, radius=0.9 * unit, fill=(255, 255, 255, 255))
    return image.resize((size, size), Image.LANCZOS)


icons = [icon(size) for size in SIZES]
icons[-1].save(OUT, sizes=[(s, s) for s in SIZES], append_images=icons[:-1])
