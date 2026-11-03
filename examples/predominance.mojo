# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Two predominance maps: titanium in O2 and Cl2, and iron in CO and CO2.

    mojo run -I . examples/predominance.mojo [path.png]

The page is Process chemistry. The left map is titanium at 1000 K over
the pressures of O2 and Cl2. Rutile turns into TiCl4 gas only where the O2
pressure is very low. The dashed line is the O2 pressure that carbon and
CO at one bar hold, which is why the chlorinator burns carbon with the
ore.

The right map is the Baur-Glaessner diagram: the stable iron phase over
temperature and the CO fraction of a CO and CO2 gas. The white curve is
the Boudouard balance, C + CO2 = 2 CO, at one bar. Above it, the gas
lays down carbon. FeO in the NASA data is stoichiometric, and real
wustite is Fe(1-x)O. The map therefore puts the Fe3O4 edge near 3 % CO,
where the handbook puts it near 20 % at 1000 degC, and the Fe edge near
80 % CO, where the handbook puts it near 70 %.
"""

from std.math import exp, log10, sqrt
from extensions.chemistry.catalog import (
    carbon_dioxide,
    carbon_monoxide,
    chlorine,
    graphite,
    iron,
    magnetite,
    oxygen,
    rutile,
    titanium,
    titanium_tetrachloride_gas,
    wustite,
)
from extensions.chemistry.elements import IRON, TITANIUM
from extensions.chemistry.maps import (
    LabelMap,
    oxide_map,
    oxygen_pressure,
    predominance,
)
from extensions.chemistry.plot import Axes
from extensions.chemistry.quantities import GAS_CONSTANT, STANDARD_PRESSURE
from extensions.chemistry.reaction import Reaction, product, reactant
from extensions.visual.overlay import CENTER, Overlay, stroke_line
from render.framebuffer import Color, Framebuffer
from tools._chemistry_figure import (
    FONT,
    MUTED,
    SURFACE,
    TEXT,
    legend,
    series,
    write_figure,
)
from tools._example_output import example_destination
from units.temperature import Temperature64

comptime DEFAULT_OUTPUT = "out/predominance.png"
comptime WIDTH = 980
comptime HEIGHT = 536
comptime SIZE = 11.0
# The fills are lighter than the lines, so the labels on them read.
comptime FILL = 0.55


def _label_regions(
    mut frame: Framebuffer, font: Overlay, axes: Axes, map: LabelMap
) raises:
    """Write each name at the middle of the nodes that carry it."""
    for label in range(len(map.names)):
        var sx = Float64(0)
        var sy = Float64(0)
        var count = 0
        for row in range(map.rows):
            for column in range(map.columns):
                if map.label(column, row) == label:
                    sx += map.x(column)
                    sy += map.y(row)
                    count += 1
        if count == 0:
            continue
        var x = axes.x(sx / Float64(count))
        var y = axes.y(sy / Float64(count))
        font.text(frame, map.names[label], x, y, SIZE * 1.2, TEXT, CENTER)


def _dashed(
    mut frame: Framebuffer,
    x0: Float64,
    y0: Float64,
    x1: Float64,
    y1: Float64,
    color: Color,
) raises:
    """Draw a dashed line, 6 pixels on and 4 off."""
    var dx = x1 - x0
    var dy = y1 - y0
    var length = sqrt(dx * dx + dy * dy)
    var at = Float64(0)
    while at < length:
        var end = min(at + 6, length)
        stroke_line(
            frame,
            x0 + dx * at / length,
            y0 + dy * at / length,
            x0 + dx * end / length,
            y0 + dy * end / length,
            2,
            color,
        )
        at += 10


def _titanium(mut frame: Framebuffer, font: Overlay) raises:
    """Draw the Ti-O-Cl map at 1000 K on the left."""
    var t = Temperature64(1000)
    var map = predominance(
        TITANIUM,
        [titanium(), rutile(), titanium_tetrachloride_gas()],
        oxygen(),
        chlorine(),
        t,
        -50,
        0,
        -20,
        0,
        401,
        161,
    )
    var axes = Axes(76, 76, 416, 400, -50, 0, -20, 0)
    var colors: List[Color] = [series(0), series(1), series(2)]
    axes.cells(frame, map, colors, FILL)
    axes.frame(frame, font, "log10 pO2 (bar)", "log10 pCl2 (bar)", SIZE, MUTED)
    _label_regions(frame, font, axes, map)
    # The O2 pressure that graphite and CO at one bar hold.
    var couple = Reaction(
        [
            reactant(graphite(), 2),
            reactant(oxygen()),
            product(carbon_monoxide(), 2),
        ]
    )
    var p = oxygen_pressure(couple, t)
    var x = axes.x(log10(p.value / STANDARD_PRESSURE.value))
    _dashed(frame, x, axes.top, x, axes.bottom, TEXT)
    font.text(frame, "C + CO", x + 6, axes.top + 18, SIZE, TEXT)
    font.text(frame, "Ti, O and Cl at 1000 K", 76, 30, SIZE * 1.4, TEXT)
    legend(frame, font, map.names, colors, 76, 456, SIZE)


def _boudouard(fraction_of: Float64) raises -> Float64:
    """Return the CO fraction in balance with graphite at 1 bar."""
    var reaction = Reaction(
        [
            reactant(graphite()),
            reactant(carbon_dioxide()),
            product(carbon_monoxide(), 2),
        ]
    )
    var t = Temperature64(fraction_of)
    var g = reaction.delta_g(t, STANDARD_PRESSURE).value
    var k = exp(-g / (GAS_CONSTANT.value * t.kelvin))
    # x^2 / (1 - x) = K at one bar.
    return (-k + sqrt(k * k + 4 * k)) / 2


def _iron(mut frame: Framebuffer, font: Overlay) raises:
    """Draw the Baur-Glaessner map on the right."""
    var couple = Reaction(
        [
            reactant(carbon_monoxide(), 2),
            reactant(oxygen()),
            product(carbon_dioxide(), 2),
        ]
    )
    var low = 700.0
    var high = 1500.0
    var map = oxide_map(
        IRON,
        [iron(), wustite(), magnetite()],
        oxygen(),
        couple,
        Temperature64(low),
        Temperature64(high),
        0.005,
        0.995,
        321,
        199,
    )
    var axes = Axes(546, 76, 886, 400, low, high, 0.005, 0.995)
    var colors: List[Color] = [series(3), series(4), series(5)]
    axes.cells(frame, map, colors, FILL)
    axes.frame(frame, font, "Temperature (K)", "CO / (CO + CO2)", SIZE, MUTED)
    _label_regions(frame, font, axes, map)
    var xs = List[Float64]()
    var ys = List[Float64]()
    var t = low
    while t <= high:
        var f = _boudouard(t)
        if f <= 0.995:
            xs.append(t)
            ys.append(max(f, 0.005))
        t += 5
    axes.line(frame, xs, ys, 2, TEXT)
    font.text(frame, "Carbon", axes.x(720), axes.y(0.62), SIZE, TEXT)
    font.text(frame, "deposits", axes.x(720), axes.y(0.62) + 16, SIZE, TEXT)
    font.text(frame, "Fe, O and C, 1 bar", 546, 30, SIZE * 1.4, TEXT)
    var names = map.names.copy()
    names.append("C + CO2 = 2 CO")
    colors.append(TEXT)
    legend(frame, font, names, colors, 546, 456, SIZE)
    # The data's FeO is stoichiometric, and real wustite is not.
    var notes: List[String] = [
        "FeO here is",
        "stoichiometric. Real",
        "wustite, Fe(1-x)O,",
        "puts the Fe3O4 edge",
        "near 20 % CO.",
    ]
    for i in range(len(notes)):
        font.text(frame, notes[i], 730, 456 + 16 * Float64(i), SIZE, MUTED)


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var frame = Framebuffer(WIDTH, HEIGHT, SURFACE)
    var font = Overlay.from_ttf(FONT)
    _titanium(frame, font)
    _iron(frame, font)
    write_figure(frame, destination)
