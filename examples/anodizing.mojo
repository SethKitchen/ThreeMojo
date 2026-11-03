# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The colors of anodized titanium, from thin-film interference.

    mojo run -I . examples/anodizing.mojo [path.png]

The page is Process chemistry. Each swatch is titanium under an anodic
TiO2 film grown to a voltage, from 0 to 120 V. Light reflects from the
film's two faces and interferes, so the color cycles as the film thickens:
bronze, purple, blue, gold, magenta, then green.

The optical constants and the growth per volt are assumed values, not
measurements: titanium's index is taken as 2.6 + 3.5i and the film's as
2.3 at every wavelength, and the film grows 2 nm per volt. The growth
depends on the electrolyte, so measure it before you plan a color.
"""

from std.math import pow
from extensions.chemistry.optics import (
    ComplexIndex,
    anodic_thickness,
    film_color,
    linear_srgb,
)
from extensions.visual.overlay import CENTER, Overlay, fill_rect
from render.framebuffer import Color, Framebuffer
from tools._chemistry_figure import FONT, MUTED, SURFACE, TEXT, write_figure
from tools._example_output import example_destination
from units.si import Length64, NANOMETER

comptime DEFAULT_OUTPUT = "out/anodizing.png"
comptime COLUMNS = 5
comptime ROWS = 5
comptime CELL_W = 120.0
comptime CELL_H = 74.0
comptime LEFT = 24.0
comptime TOP = 64.0
comptime STEP_V = 5.0
# Assumed constants: see the module docstring.
comptime TITANIUM_N = 2.6
comptime TITANIUM_K = 3.5
comptime FILM_N = 2.3
comptime GROWTH_NM = 2.0


def _encode(linear: Float64) -> UInt8:
    """Return a linear sRGB channel, clipped, as an 8-bit sRGB value."""
    var c = min(1.0, max(0.0, linear))
    var v = 12.92 * c
    if c > 0.0031308:
        v = 1.055 * pow(c, 1 / 2.4) - 0.055
    return UInt8(Int(v * 255 + 0.5))


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var width = Int(LEFT * 2 + CELL_W * Float64(COLUMNS))
    var height = Int(TOP + CELL_H * Float64(ROWS) + 80)
    var frame = Framebuffer(width, height, SURFACE)
    var font = Overlay.from_ttf(FONT)
    var metal = ComplexIndex(TITANIUM_N, TITANIUM_K)
    var growth = Length64(GROWTH_NM, NANOMETER)
    for i in range(COLUMNS * ROWS):
        var volts = STEP_V * Float64(i)
        var thickness = anodic_thickness(volts, growth)
        var rgb = linear_srgb(film_color(thickness, FILM_N, metal))
        var color = Color(_encode(rgb[0]), _encode(rgb[1]), _encode(rgb[2]))
        var x = LEFT + CELL_W * Float64(i % COLUMNS)
        var y = TOP + CELL_H * Float64(i // COLUMNS)
        fill_rect(frame, x + 4, y, x + CELL_W - 4, y + CELL_H - 26, color)
        var label = String(Int(volts), " V, ")
        label += String(Int(round(thickness.to(NANOMETER))), " nm")
        font.text(
            frame, label, x + CELL_W / 2, y + CELL_H - 10, 10, MUTED, CENTER
        )
    font.text(frame, "Anodized titanium", LEFT, 34, 16, TEXT)
    var foot = TOP + CELL_H * Float64(ROWS) + 22
    font.text(
        frame,
        "Assumed: Ti 2.6 + 3.5i, TiO2 2.3, 2 nm per volt.",
        LEFT,
        foot,
        10,
        MUTED,
    )
    font.text(
        frame,
        "Measure the growth per volt of your bath first.",
        LEFT,
        foot + 18,
        10,
        MUTED,
    )
    write_figure(frame, destination)
