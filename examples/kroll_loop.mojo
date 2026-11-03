# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The Kroll route as a loop, with the flows the solver settles on.

    mojo run -I . examples/kroll_loop.mojo [path.png]

The page is Process chemistry. The chlorinator turns rutile, coke and
chlorine into TiCl4. Magnesium reduces the TiCl4 to titanium sponge and
MgCl2, and an electrolysis cell splits the MgCl2 back into magnesium and
chlorine, which return to the start. Only the ore, the coke and a little
make-up chlorine come in. The numbers are moles per mole of rutile, from
`Flowsheet.solve`.
"""

from extensions.chemistry.flowsheet import Flowsheet, StreamId
from extensions.chemistry.processes.titanium import kroll_loop
from extensions.visual.overlay import (
    CENTER,
    Overlay,
    arrow,
    fill_disc,
    fill_rect,
    stroke_line,
)
from render.framebuffer import Color, Framebuffer
from tools._chemistry_figure import (
    FONT,
    GRID,
    MUTED,
    SURFACE,
    TEXT,
    series,
    write_figure,
)
from tools._example_output import example_destination

comptime DEFAULT_OUTPUT = "out/kroll-loop.png"
comptime WIDTH = 1000
comptime HEIGHT = 440
comptime SIZE = 10.0
# The two rows of the loop, by the y of their centers.
comptime TOP_ROW = 170.0
comptime LOW_ROW = 350.0
comptime BOX_H = 44.0


def _id(sheet: Flowsheet, name: String) raises -> StreamId:
    """Return the stream of a name."""
    for i in range(len(sheet.stream_names)):
        if sheet.stream_names[i] == name:
            return StreamId(i)
    raise Error(String("No stream is named ", name))


def _flow(sheet: Flowsheet, stream: String, part: String) raises -> String:
    """Return a part's amount in a stream, as text."""
    var moles = sheet.amount(_id(sheet, stream), part).value
    var hundredths = Int(round(moles * 100))
    var tenths = String(hundredths % 100)
    if hundredths % 100 < 10:
        tenths = "0" + tenths
    return String(part, " ", hundredths // 100, ".", tenths)


def _unit(
    mut frame: Framebuffer,
    font: Overlay,
    name: String,
    x0: Float64,
    x1: Float64,
    y: Float64,
    color: Color,
) raises:
    """Draw a unit: a box with its name."""
    fill_rect(frame, x0, y - BOX_H / 2, x1, y + BOX_H / 2, color)
    font.text(frame, name, (x0 + x1) / 2, y + SIZE * 0.4, SIZE, TEXT, CENTER)


def _note(
    mut frame: Framebuffer,
    font: Overlay,
    lines: List[String],
    x: Float64,
    y: Float64,
) raises:
    """Write the lines of a stream's label, centered on x."""
    for i in range(len(lines)):
        font.text(frame, lines[i], x, y + 14 * Float64(i), SIZE, MUTED, CENTER)


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var sheet = kroll_loop()
    var passes = sheet.solve()
    var frame = Framebuffer(WIDTH, HEIGHT, SURFACE)
    var font = Overlay.from_ttf(FONT)
    var line = TEXT
    var w = 2.0
    var box = series(0)
    var cell = series(1)
    # The top row: ore in, chlorinate, condense, reduce, tap the sponge.
    var mix_a = 130.0
    var mix_b = 560.0
    arrow(frame, 30, TOP_ROW, mix_a - 8, TOP_ROW, w, line)
    _note(
        frame,
        font,
        [
            "ore",
            _flow(sheet, "ore", "TiO2"),
            _flow(sheet, "ore", "graphite"),
        ],
        64,
        TOP_ROW - 50,
    )
    arrow(frame, mix_a, 96, mix_a, TOP_ROW - 8, w, line)
    _note(
        frame,
        font,
        ["make-up", _flow(sheet, "make-up Cl2", "Cl2(g)")],
        mix_a + 70,
        96,
    )
    fill_disc(frame, mix_a, TOP_ROW, 8, GRID)
    arrow(frame, mix_a + 8, TOP_ROW, 190, TOP_ROW, w, line)
    _unit(frame, font, "Chlorinator", 190, 310, TOP_ROW, box)
    arrow(frame, 310, TOP_ROW, 370, TOP_ROW, w, line)
    _unit(frame, font, "Condenser", 370, 470, TOP_ROW, box)
    arrow(frame, 420, TOP_ROW - BOX_H / 2, 420, 100, w, line)
    _note(
        frame,
        font,
        [
            "off-gas",
            _flow(sheet, "off-gas", "CO2(g)"),
            _flow(sheet, "off-gas", "Cl2(g)"),
        ],
        420,
        62,
    )
    arrow(frame, 470, TOP_ROW, mix_b - 8, TOP_ROW, w, line)
    _note(frame, font, [_flow(sheet, "TiCl4", "TiCl4(g)")], 515, TOP_ROW - 14)
    fill_disc(frame, mix_b, TOP_ROW, 8, GRID)
    arrow(frame, mix_b + 8, TOP_ROW, 620, TOP_ROW, w, line)
    _unit(frame, font, "Reducer", 620, 730, TOP_ROW, box)
    arrow(frame, 730, TOP_ROW, 780, TOP_ROW, w, line)
    _unit(frame, font, "Tapping", 780, 880, TOP_ROW, box)
    arrow(frame, 880, TOP_ROW, 975, TOP_ROW, w, line)
    _note(
        frame, font, ["sponge", _flow(sheet, "sponge", "Ti")], 930, TOP_ROW - 30
    )
    # Down from the tapping to the cell, then back along the low row.
    arrow(frame, 830, TOP_ROW + BOX_H / 2, 830, LOW_ROW - BOX_H / 2, w, line)
    _note(frame, font, ["salt", _flow(sheet, "salt", "MgCl2")], 885, 255)
    _unit(frame, font, "Electrolysis", 770, 890, LOW_ROW, cell)
    arrow(frame, 770, LOW_ROW, 670, LOW_ROW, w, line)
    _unit(frame, font, "Cell taps", 520, 670, LOW_ROW, cell)
    # Magnesium returns to the reducer's mixer.
    arrow(frame, mix_b, LOW_ROW - BOX_H / 2, mix_b, TOP_ROW + 8, w, line)
    _note(
        frame, font, ["Mg recycle", _flow(sheet, "Mg recycle", "Mg")], 625, 255
    )
    # Chlorine returns to the chlorinator's mixer.
    stroke_line(frame, 520, LOW_ROW, mix_a, LOW_ROW, w, line)
    arrow(frame, mix_a, LOW_ROW, mix_a, TOP_ROW + 8, w, line)
    _note(
        frame,
        font,
        ["Cl2 recycle", _flow(sheet, "Cl2 recycle", "Cl2(g)")],
        320,
        LOW_ROW + 22,
    )
    font.text(frame, "The Kroll loop", 30, 30, 16, TEXT)
    font.text(
        frame,
        String("Moles per mole of rutile, settled in ", passes, " passes."),
        30,
        HEIGHT - 20,
        SIZE,
        MUTED,
    )
    write_figure(frame, destination)
