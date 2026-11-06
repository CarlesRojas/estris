#!/usr/bin/env python3
"""Draws src/Estris/Assets/Estris.ico from macos/Resources/Icon/AppIcon.svg, the one source of the
icon: its squircle, gradient and bento, read from the file. Only the squircle is kept, without the
room and shadow macOS expects around an icon. `Ui/AppLogo.cs` draws the same in the app's pages.

    uv run --with pillow windows/scripts/make-icon.py
"""
import re
import xml.etree.ElementTree as ElementTree
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT.parent / "macos/Resources/Icon/AppIcon.svg"
OUT = ROOT / "src/Estris/Assets/Estris.ico"
SIZES = [16, 20, 24, 32, 40, 48, 64, 128, 256]
SUPERSAMPLE = 8
NS = "{http://www.w3.org/2000/svg}"


def color(text):
    return tuple(int(text[i:i + 2], 16) for i in (1, 3, 5))


def rect(element):
    return [float(element.get(name, 0)) for name in ("x", "y", "width", "height", "rx")]


svg = ElementTree.parse(SOURCE).getroot()
stops = svg.findall(f"{NS}defs/{NS}linearGradient/{NS}stop")
TOP, BOTTOM = color(stops[0].get("stop-color")), color(stops[-1].get("stop-color"))
BODY = rect(svg.find(f"{NS}rect"))
group = svg.find(f"{NS}g")
offset_x, offset_y, scale = map(float, re.findall(r"[\d.]+", group.get("transform")))
BOXES = [rect(box) for box in group.findall(f"{NS}rect")]


def icon(size):
    n = size * SUPERSAMPLE
    body_x, body_y, body_size, _, body_radius = BODY
    unit = n / body_size
    image = Image.new("RGBA", (n, n))
    draw = ImageDraw.Draw(image)
    for y in range(n):
        draw.line([(0, y), (n, y)], fill=tuple(round(a + (b - a) * y / n) for a, b in zip(TOP, BOTTOM)) + (255,))
    mask = Image.new("L", (n, n), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, n - 1, n - 1), radius=body_radius * unit, fill=255)
    image.putalpha(mask)
    for x, y, width, height, radius in BOXES:
        left = (offset_x + x * scale - body_x) * unit
        top = (offset_y + y * scale - body_y) * unit
        draw.rounded_rectangle((left, top, left + width * scale * unit - 1, top + height * scale * unit - 1), radius=radius * scale * unit, fill=(255, 255, 255, 255))
    return image.resize((size, size), Image.LANCZOS)


icons = [icon(size) for size in SIZES]
icons[-1].save(OUT, sizes=[(s, s) for s in SIZES], append_images=icons[:-1])
