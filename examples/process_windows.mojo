# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Why each step of the Kroll route runs at its temperature.

    mojo run -I . examples/process_windows.mojo [path.png]

The page is Why a process runs where it does. Each row is one requirement
of a step, and its bar is where the requirement holds, scanned from the
data. The white bar under each step is the window where all of them hold,
and the dot is the temperature the plant runs at. The Kroll reduction's
window opens where MgCl2 melts and closes at the iron-titanium eutectic
of the steel retort.
"""

from extensions.chemistry.kinds import (
    ACTION,
    ENGINEERING,
    KINETIC,
    PHASE,
    RequirementKind,
    THERMODYNAMIC,
)
from extensions.chemistry.plot import Axes
from extensions.chemistry.processes.titanium import kroll_route
from extensions.chemistry.step import operating_window
from extensions.chemistry.window import met_intervals
from extensions.visual.overlay import Overlay, fill_disc, fill_rect
from render.framebuffer import Color, Framebuffer
from tools._chemistry_figure import (
    FONT,
    GRID,
    MUTED,
    SURFACE,
    TEXT,
    legend,
    series,
    write_figure,
)
from tools._example_output import example_destination
from units.temperature import CELSIUS

comptime DEFAULT_OUTPUT = "out/process-windows.png"
comptime WIDTH = 1100
comptime SIZE = 10.0
comptime ROW = 20.0
comptime TOP = 70.0
comptime LEFT = 575.0
comptime RIGHT = 1075.0
comptime LOW_C = 0.0
comptime HIGH_C = 1300.0


def _kind_color(kind: RequirementKind) -> Color:
    """Return the color of a kind of requirement."""
    if kind == THERMODYNAMIC:
        return series(0)
    if kind == PHASE:
        return series(1)
    if kind == KINETIC:
        return series(2)
    if kind == ENGINEERING:
        return series(3)
    return series(4)


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var steps = kroll_route()
    var rows = 0
    for step in steps:
        rows += 2
        for r in step.requirements:
            if r.check != ACTION:
                rows += 1
    var bottom = TOP + ROW * Float64(rows)
    var height = Int(bottom) + 110
    var frame = Framebuffer(WIDTH, height, SURFACE)
    var font = Overlay.from_ttf(FONT)
    var axes = Axes(LEFT, TOP, RIGHT, bottom, LOW_C, HIGH_C, 0, Float64(rows))
    for t in range(100, 1300, 100):
        var x = axes.x(Float64(t))
        fill_rect(frame, x, TOP, x + 1, bottom, GRID)
    var titles: List[String] = [
        "Chlorination",
        "TiCl4 distillation",
        "Kroll reduction",
        "Vacuum distillation",
    ]
    var y = TOP
    for i in range(len(steps)):
        ref step = steps[i]
        var kilopascals = step.pressure.value / 1000
        var header = String(titles[i], ", ")
        if kilopascals < 1:
            header += String(Int(step.pressure.value), " Pa")
        else:
            header += "1 atm"
        font.text(frame, header, 20, y + ROW * 0.75, SIZE * 1.2, TEXT)
        y += ROW
        var lo_c = step.low.to(CELSIUS)
        var hi_c = step.high.to(CELSIUS)
        for r in step.requirements:
            if r.check == ACTION:
                continue
            font.text(frame, r.statement, 34, y + ROW * 0.7, SIZE, MUTED)
            # The scanned range, faint, and the bars where the
            # requirement holds.
            fill_rect(
                frame,
                axes.x(lo_c),
                y + 5,
                axes.x(hi_c),
                y + ROW - 5,
                GRID,
            )
            for interval in met_intervals(
                r, step.low, step.high, step.pressure
            ):
                fill_rect(
                    frame,
                    axes.x(interval.low.to(CELSIUS)),
                    y + 4,
                    axes.x(interval.high.to(CELSIUS)),
                    y + ROW - 4,
                    _kind_color(r.kind),
                )
            y += ROW
        font.text(frame, "Operating window", 34, y + ROW * 0.7, SIZE, TEXT)
        for interval in operating_window(step):
            fill_rect(
                frame,
                axes.x(interval.low.to(CELSIUS)),
                y + 3,
                axes.x(interval.high.to(CELSIUS)),
                y + ROW - 3,
                TEXT,
            )
        var planned = axes.x(step.planned.to(CELSIUS))
        fill_disc(frame, planned, y + ROW / 2, 5, series(4))
        y += ROW
    axes.frame(
        frame,
        font,
        "Temperature (degC)",
        "",
        SIZE,
        MUTED,
        ticks=8,
        y_numbers=False,
    )
    font.text(frame, "Why the Kroll route runs where it does", 20, 34, 16, TEXT)
    var names: List[String] = [
        "Thermodynamic",
        "Phase",
        "Kinetic",
        "Engineering",
    ]
    var colors: List[Color] = [series(0), series(1), series(2), series(3)]
    legend(frame, font, names, colors, 20, bottom + 50, SIZE)
    legend(
        frame,
        font,
        ["All requirements hold", "Planned temperature"],
        [TEXT, series(4)],
        200,
        bottom + 50,
        SIZE,
    )
    write_figure(frame, destination)
