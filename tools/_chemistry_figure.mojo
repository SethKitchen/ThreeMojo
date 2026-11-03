# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The style of the process chemistry figures, and how they are written.

Every chemistry figure draws on one dark surface with the same text colors
and the same order of series colors. The series colors are the dark steps
of a categorical palette whose adjacent pairs stay apart for color-blind
readers. Each series also carries a label, so no reader needs the color
alone.
"""

from extensions.visual.overlay import Overlay, fill_rect
from render.framebuffer import Color, Framebuffer
from render.png import encode as encode_png
from std.pathlib import Path

comptime FONT = "assets/ttf/kenpixel.ttf"
comptime SURFACE = Color(26, 26, 25)
comptime TEXT = Color(240, 239, 236)
comptime MUTED = Color(195, 194, 183)
comptime GRID = Color(58, 58, 55)


def series(index: Int) -> Color:
    """Return the color of a series, in a fixed order.

    Args:
        index: The series, from 0 to 6. A larger index starts the order
            again; a figure keeps to seven series.

    Returns:
        Blue, orange, aqua, yellow, magenta, green or violet.
    """
    var colors: List[Color] = [
        Color(57, 135, 229),
        Color(217, 89, 38),
        Color(25, 158, 112),
        Color(201, 133, 0),
        Color(213, 81, 129),
        Color(0, 131, 0),
        Color(144, 133, 233),
    ]
    return colors[index % len(colors)]


def legend(
    mut frame: Framebuffer,
    font: Overlay,
    names: List[String],
    colors: List[Color],
    x: Float64,
    y: Float64,
    size: Float64,
) raises:
    """Draw a legend: a swatch and a name on each line.

    Args:
        frame: The frame.
        font: The font.
        names: The series names, top first.
        colors: One color per name.
        x: The legend's left, in pixels.
        y: The first line's baseline.
        size: The text's em size.

    Raises:
        Error: If the font lacks a glyph.
    """
    for i in range(len(names)):
        var base = y + Float64(i) * size * 1.6
        fill_rect(
            frame,
            x,
            base - size * 0.8,
            x + size * 1.4,
            base - size * 0.1,
            colors[i],
        )
        font.text(frame, names[i], x + size * 2, base, size, TEXT)


def write_figure(frame: Framebuffer, path: String) raises:
    """Write a figure as a PNG.

    Args:
        frame: The figure.
        path: Where to write it.

    Raises:
        Error: If the file cannot be written.
    """
    Path(path).write_bytes(encode_png(frame))
    print("Wrote", path)
