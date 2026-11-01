"""Tile the route-harness screenshots into one labelled contact sheet.

Usage: uv run --with pillow python3 scripts/contact-sheet.py build/screens build/screens/contact-sheet.png

Every PNG in the directory named <route>-<appearance>-<size>.png becomes a thumbnail. Each
route is one row, labelled with its name; columns are appearance x size in the order the
screenshots script takes them. The output file itself is skipped. Missing shots leave a gap.
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

THUMB_WIDTH = 180
LABEL_WIDTH = 300
GAP = 12
HEADER = 44
BACKGROUND = (231, 234, 236)  # Tray, light
INK = (22, 32, 38)
GRADUATION = (86, 98, 106)
SCHEME_ORDER = ["light", "dark"]
SIZE_ORDER = ["xSmall", "small", "medium", "large", "xLarge", "xxLarge", "xxxLarge",
              "accessibility1", "accessibility2", "accessibility3", "accessibility4", "accessibility5"]


def font(size: int) -> ImageFont.ImageFont:
    for path in ("/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Helvetica.ttc",
                 "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def parse(path: Path) -> tuple[str, str, str] | None:
    parts = path.stem.rsplit("-", 2)
    if len(parts) != 3:
        return None
    route, scheme, size = parts
    return route, scheme, size


def rank(value: str, order: list[str]) -> int:
    return order.index(value) if value in order else len(order)


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2
    source = Path(sys.argv[1])
    output = Path(sys.argv[2])
    shots: dict[str, dict[tuple[str, str], Path]] = {}
    route_order: list[str] = []
    columns: set[tuple[str, str]] = set()
    for png in sorted(source.glob("*.png"), key=lambda p: p.stat().st_mtime):
        if png.resolve() == output.resolve():
            continue
        parsed = parse(png)
        if parsed is None:
            continue
        route, scheme, size = parsed
        if route not in shots:
            shots[route] = {}
            route_order.append(route)
        shots[route][(scheme, size)] = png
        columns.add((scheme, size))
    if not shots:
        print(f"contact-sheet: no screenshots in {source}", file=sys.stderr)
        return 1

    cols = sorted(columns, key=lambda c: (rank(c[0], SCHEME_ORDER), rank(c[1], SIZE_ORDER), c))
    sample = Image.open(next(iter(next(iter(shots.values())).values())))
    thumb_height = round(THUMB_WIDTH * sample.height / sample.width)
    row_height = thumb_height + GAP
    width = LABEL_WIDTH + len(cols) * (THUMB_WIDTH + GAP) + GAP
    height = HEADER + len(route_order) * row_height + GAP

    sheet = Image.new("RGB", (width, height), BACKGROUND)
    draw = ImageDraw.Draw(sheet)
    title_font, label_font, small_font = font(26), font(22), font(16)
    draw.text((GAP, 10), f"Route harness screenshots: {len(route_order)} routes", fill=INK, font=title_font)
    for i, (scheme, size) in enumerate(cols):
        x = LABEL_WIDTH + i * (THUMB_WIDTH + GAP)
        draw.text((x, HEADER - 20), f"{scheme}, {size}", fill=GRADUATION, font=small_font)

    for r, route in enumerate(route_order):
        y = HEADER + r * row_height
        draw.text((GAP, y + thumb_height // 2 - 12), route, fill=INK, font=label_font)
        for i, col in enumerate(cols):
            png = shots[route].get(col)
            if png is None:
                continue
            with Image.open(png) as im:
                thumb = im.convert("RGB").resize((THUMB_WIDTH, thumb_height), Image.LANCZOS)
            sheet.paste(thumb, (LABEL_WIDTH + i * (THUMB_WIDTH + GAP), y))

    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output, optimize=True)
    total = sum(len(v) for v in shots.values())
    print(f"contact-sheet: {total} screenshot(s), {len(route_order)} route(s), {len(cols)} column(s) -> {output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
