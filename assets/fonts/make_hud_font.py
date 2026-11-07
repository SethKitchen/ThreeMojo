"""Writes `extensions/village/hud_font.mojo`: the game display's font, as
a signed distance field a glyph.

Run it from the repository's root, with fontTools installed:

    python3 assets/fonts/make_hud_font.py

Each glyph of `GLYPHS` is a square cell of `CELL` by `CELL` samples. A
sample holds how far its middle is from the glyph's edge, from
`-SPREAD` outside to `+SPREAD` inside, as one of `LEVELS` printable
characters. The cap height spans `CAP` samples, and the baseline is
`BASE` samples down the cell. A glyph's origin is `PAD` samples in from
the cell's left side.

Each glyph also has six metric characters: its advance, in two, and the
box its ink fills in the cell, as left, right, top and bottom.
"""

import math
import sys

from fontTools.pens.recordingPen import DecomposingRecordingPen
from fontTools.ttLib import TTFont

FONT = "assets/fonts/barlow/BarlowSemiCondensed-SemiBold.ttf"
OUT = "extensions/village/hud_font.mojo"
GLYPHS = (
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+/:.,!?'-"
    + "abcdefghijklmnopqrstuvwxyz"
)
CELL = 32
CAP = 18.0
BASE = 25.0
PAD = 5.0
SPREAD = 6.0
FIRST = 35  # '#': the levels skip '"' and stop before '\'.
LEVELS = 57
CURVE_STEPS = 8


def _segments(font, name, scale):
    """Return the glyph's outline as line segments, in cell samples."""
    pen = DecomposingRecordingPen(font.getGlyphSet())
    font.getGlyphSet()[name].draw(pen)
    lines = []
    start = None
    at = None

    def place(p):
        return (PAD + p[0] * scale, BASE - p[1] * scale)

    for verb, points in pen.value:
        if verb == "moveTo":
            start = at = place(points[0])
        elif verb == "lineTo":
            to = place(points[0])
            lines.append((at, to))
            at = to
        elif verb == "qCurveTo":
            # A run of off-curve points with implied on-curve midpoints.
            ps = [place(p) for p in points]
            controls, end = ps[:-1], ps[-1]
            for k, c in enumerate(controls):
                if k + 1 < len(controls):
                    n = controls[k + 1]
                    stop = ((c[0] + n[0]) / 2, (c[1] + n[1]) / 2)
                else:
                    stop = end
                for s in range(1, CURVE_STEPS + 1):
                    t = s / CURVE_STEPS
                    u = 1 - t
                    p = (
                        u * u * at[0] + 2 * u * t * c[0] + t * t * stop[0],
                        u * u * at[1] + 2 * u * t * c[1] + t * t * stop[1],
                    )
                    lines.append((at if s == 1 else last, p))
                    last = p
                at = stop
        elif verb == "curveTo":
            c1, c2, end = [place(p) for p in points]
            for s in range(1, CURVE_STEPS + 1):
                t = s / CURVE_STEPS
                u = 1 - t
                p = tuple(
                    u**3 * at[i]
                    + 3 * u * u * t * c1[i]
                    + 3 * u * t * t * c2[i]
                    + t**3 * end[i]
                    for i in range(2)
                )
                lines.append((at if s == 1 else last, p))
                last = p
            at = end
        elif verb in ("closePath", "endPath"):
            if at is not None and start is not None and at != start:
                lines.append((at, start))
            at = start
    return lines


def _distance(p, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    long = dx * dx + dy * dy
    t = 0.0 if long == 0 else ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / long
    t = min(1.0, max(0.0, t))
    ex, ey = a[0] + dx * t - p[0], a[1] + dy * t - p[1]
    return math.sqrt(ex * ex + ey * ey)


def _winding(p, lines):
    wind = 0
    for a, b in lines:
        if a[1] <= p[1] < b[1] or b[1] <= p[1] < a[1]:
            x = a[0] + (p[1] - a[1]) / (b[1] - a[1]) * (b[0] - a[0])
            if x > p[0]:
                wind += 1 if b[1] > a[1] else -1
    return wind


def _code(v):
    return chr(FIRST + v)


def main():
    font = TTFont(FONT)
    cmap = font.getBestCmap()
    scale = CAP / font["OS/2"].sCapHeight
    hmtx = font["hmtx"]
    cells = []
    metrics = []
    for ch in GLYPHS:
        name = cmap[ord(ch)]
        lines = _segments(font, name, scale)
        cell = []
        left, right, top, bottom = CELL, 0, CELL, 0
        for y in range(CELL):
            for x in range(CELL):
                p = (x + 0.5, y + 0.5)
                d = min(_distance(p, a, b) for a, b in lines)
                if _winding(p, lines) != 0:
                    d = -d
                    left, right = min(left, x), max(right, x + 1)
                    top, bottom = min(top, y), max(bottom, y + 1)
                # Inside is positive.
                v = 0.5 - d / (2 * SPREAD)
                cell.append(_code(round(min(1.0, max(0.0, v)) * (LEVELS - 1))))
        cells.append("".join(cell))
        advance = round(hmtx[name][0] * scale * 8)
        assert advance < LEVELS * LEVELS
        metrics.append(
            _code(advance // LEVELS)
            + _code(advance % LEVELS)
            + "".join(_code(v) for v in (left, right, top, bottom))
        )
    space = hmtx[cmap[ord(" ")]][0] * scale
    data = "".join(cells)
    width = 72
    out = []
    out.append("# Copyright (c) 2026 Seth Kitchen, PE")
    out.append("# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0")
    out.append("# Noncommercial use is free; commercial use requires a paid license.")
    out.append("# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.")
    out.append("")
    out.append('"""The game display\'s font: Barlow Semi Condensed SemiBold, as a')
    out.append("signed distance field a glyph. `assets/fonts/make_hud_font.py`")
    out.append("writes this file. Do not edit it by hand.")
    out.append("")
    out.append("The font is Copyright 2017 The Barlow Project Authors, under the")
    out.append("SIL Open Font License 1.1: see `assets/fonts/barlow/OFL.txt`.")
    out.append('"""')
    out.append("")
    out.append(f"comptime FONT_CELL = {CELL}")
    out.append('"""The side of a glyph\'s square cell, in samples."""')
    out.append(f"comptime FONT_CAP = Float32({CAP})")
    out.append('"""The height of a capital letter, in samples."""')
    out.append(f"comptime FONT_BASE = Float32({BASE})")
    out.append('"""How far down its cell a glyph\'s baseline is, in samples."""')
    out.append(f"comptime FONT_PAD = Float32({PAD})")
    out.append('"""How far in from its cell\'s left side a glyph\'s origin is, in')
    out.append('samples."""')
    out.append(f"comptime FONT_SPREAD = Float32({SPREAD})")
    out.append('"""The distance, in samples, of the field\'s least and greatest')
    out.append('levels from a glyph\'s edge."""')
    out.append(f"comptime FONT_FIRST = {FIRST}")
    out.append('"""The character code of the field\'s least level."""')
    out.append(f"comptime FONT_LEVELS = {LEVELS}")
    out.append('"""How many levels a sample of the field takes."""')
    out.append(f"comptime FONT_SPACE = Float32({space:.4f})")
    out.append('"""The advance of a space, in samples."""')
    out.append("comptime FONT_METRICS: StaticString = (")
    m = "".join(metrics)
    for k in range(0, len(m), width):
        out.append('    "' + m[k : k + width] + '"')
    out.append(")")
    out.append('"""Six characters a glyph: its advance in eighths of a sample, in')
    out.append("two levels, the greater first; then the box its ink fills, as")
    out.append('left, right, top and bottom samples."""')
    out.append("comptime FONT_FIELD: StaticString = (")
    for k in range(0, len(data), width):
        out.append('    "' + data[k : k + width] + '"')
    out.append(")")
    out.append('"""The field, `FONT_CELL` squared samples a glyph, row by row."""')
    open(OUT, "w").write("\n".join(out) + "\n")
    print(f"wrote {OUT}: {len(GLYPHS)} glyphs, {len(data)} samples")


if __name__ == "__main__":
    sys.exit(main())
