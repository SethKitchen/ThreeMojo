# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An Ellingham diagram, computed from the NASA data in the catalog.

    mojo run -I . examples/ellingham.mojo [path.png]

The page is Process chemistry. Each line is the standard Gibbs energy of
an oxidation per mole of O2, from 300 to 2000 K. A lower line is a more
stable oxide, and its metal can take the oxygen from an oxide above it.
The kinks are the phase changes in the data, such as magnesium melting at
923 K. Carbon's CO line falls as the temperature rises, which is why
carbon reduces iron oxide in a blast furnace but not titanium oxide.
"""

from extensions.chemistry.catalog import (
    alumina,
    aluminum,
    carbon_dioxide,
    carbon_monoxide,
    graphite,
    hydrogen,
    iron,
    magnesia,
    magnesium,
    oxygen,
    rutile,
    steam,
    titanium,
    wustite,
)
from extensions.chemistry.maps import ellingham, ellingham_crossing
from extensions.chemistry.plot import Axes
from extensions.chemistry.quantities import KILOJOULE_PER_MOLE
from extensions.chemistry.reaction import Reaction, product, reactant
from extensions.visual.overlay import (
    CENTER,
    Overlay,
    fill_disc,
    stroke_line,
)
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
from units.temperature import Temperature64

comptime DEFAULT_OUTPUT = "out/ellingham.png"
comptime WIDTH = 790
comptime HEIGHT = 480
comptime LOW = 300.0
comptime HIGH = 2000.0


def _lines() raises -> List[Reaction]:
    """Return the oxidations, each with one mole of O2."""
    return [
        Reaction(
            [reactant(iron(), 2), reactant(oxygen()), product(wustite(), 2)]
        ),
        Reaction(
            [reactant(hydrogen(), 2), reactant(oxygen()), product(steam(), 2)]
        ),
        Reaction(
            [
                reactant(graphite()),
                reactant(oxygen()),
                product(carbon_dioxide()),
            ]
        ),
        Reaction(
            [
                reactant(graphite(), 2),
                reactant(oxygen()),
                product(carbon_monoxide(), 2),
            ]
        ),
        Reaction([reactant(titanium()), reactant(oxygen()), product(rutile())]),
        Reaction(
            [
                reactant(aluminum(), 4.0 / 3),
                reactant(oxygen()),
                product(alumina(), 2.0 / 3),
            ]
        ),
        Reaction(
            [
                reactant(magnesium(), 2),
                reactant(oxygen()),
                product(magnesia(), 2),
            ]
        ),
    ]


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var frame = Framebuffer(WIDTH, HEIGHT, SURFACE)
    var font = Overlay.from_ttf(FONT)
    var axes = Axes(84, 64, 540, 420, LOW, HIGH, -1200, 0)
    # A recessive grid at each 200 kJ/mol.
    for g in range(-1000, 0, 200):
        var y = axes.y(Float64(g))
        stroke_line(frame, axes.left, y, axes.right, y, 1, GRID)
    axes.frame(
        frame,
        font,
        "Temperature (K)",
        "Gibbs energy (kJ per mol O2)",
        12,
        MUTED,
        ticks=8,
    )
    var names: List[String] = [
        "FeO",
        "H2O",
        "CO2 from C",
        "CO from C",
        "TiO2",
        "Al2O3",
        "MgO",
    ]
    var colors = List[Color]()
    var lines = _lines()
    for i in range(len(lines)):
        var xs = List[Float64]()
        var ys = List[Float64]()
        var t = LOW
        while t <= HIGH:
            # A line stops where its data stops.
            try:
                var g = ellingham(lines[i], Temperature64(t))
                xs.append(t)
                ys.append(g.to(KILOJOULE_PER_MOLE))
            except:
                pass
            t += 10
        axes.line(frame, xs, ys, 2, series(i))
        colors.append(series(i))
    # Above this temperature, carbon takes the oxygen from wustite.
    var cross = ellingham_crossing(
        lines[0], lines[3], Temperature64(LOW), Temperature64(HIGH)
    )
    var g = ellingham(lines[0], cross).to(KILOJOULE_PER_MOLE)
    var cx = axes.x(cross.kelvin)
    var cy = axes.y(g)
    fill_disc(frame, cx, cy, 5, TEXT)
    # The note sits in the clear space under the iron line, with a leader.
    var note_y = axes.y(-560)
    stroke_line(frame, cx, cy + 6, cx, note_y - 14, 1, TEXT)
    font.text(
        frame,
        String("C reduces FeO above ", Int(round(cross.kelvin)), " K"),
        cx,
        note_y,
        11,
        TEXT,
        CENTER,
    )
    font.text(frame, "Ellingham diagram", 84, 28, 16, TEXT)
    font.text(frame, "Oxide formed", 560, 84, 11, MUTED)
    legend(frame, font, names, colors, 560, 108, 11)
    var notes: List[String] = [
        "A lower line is",
        "a more stable oxide.",
        "Its metal or carbon",
        "takes the oxygen",
        "from an oxide above.",
    ]
    for i in range(len(notes)):
        font.text(frame, notes[i], 560, 264 + 18 * Float64(i), 11, MUTED)
    write_figure(frame, destination)
