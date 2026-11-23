# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Air in a square cavity with a hot wall and a cold wall.

    mojo run -I . examples/buoyant_cavity.mojo [out/buoyant-cavity.png]

The page is Finite-volume flow. The left wall is hot and the right wall
is cold. The floor and the ceiling are insulated. The Prandtl number is
0.71 and the Rayleigh number is 100000, which is one case of the
benchmark of de Vahl Davis. `BuoyantSolver` runs 40 by 40 cells until
the temperatures are steady.

The color is the temperature, from the cold wall (blue) to the hot wall
(red). The white lines are streamlines. The air rises at the hot wall,
crosses under the ceiling and falls at the cold wall, and the core of
the cavity is in layers. The program prints the Nusselt number of the
hot wall. The benchmark value is 4.519.

This is a picture of a coarse model, for teaching.
"""

from std.math import sqrt
from std.pathlib import Path
from extensions.cfd.flow import FlowCase, Grid, default_options
from extensions.cfd.heat import BuoyantCase, BuoyantSolver, fixed_temperature
from extensions.cfd.kinds import EAST, WEST
from extensions.cfd.quantities import (
    DynamicViscosity64,
    PASCAL_SECOND,
    SQUARE_METER_PER_SECOND,
    ThermalDiffusivity64,
)
from render.framebuffer import Color, Framebuffer
from render.png import encode
from tools._example_output import example_destination
from units.si import (
    Acceleration64,
    Density64,
    Duration64,
    KILOGRAM_PER_CUBIC_METER,
    Length64,
    METER,
    METER_PER_SECOND_SQUARED,
    PER_KELVIN,
    SECOND,
    ThermalExpansion64,
)
from units.temperature import (
    KELVIN,
    KELVIN_DIFFERENCE,
    Temperature64,
    TemperatureDifference64,
)

comptime DEFAULT_OUTPUT = "out/buoyant-cavity.png"
comptime SIZE = 720
comptime CELLS = 40
comptime RAYLEIGH = 1.0e5
comptime SEEDS = 12
comptime TRACE_STEPS = 9000


def sample(
    field: List[Float64], x: Float64, y: Float64, west: Float64, east: Float64
) -> Float64:
    """Return a cell-centered field at a point, by bilinear interpolation.

    Past the cell centers the field goes to `west` and `east` at the two
    walls, and keeps the value of the last cell at the floor and the
    ceiling.
    """
    var gx = x * Float64(CELLS) - 0.5
    var gy = min(max(y * Float64(CELLS) - 0.5, 0), Float64(CELLS - 1))
    var i = Int(gx + 1) - 1
    var j = min(Int(gy), CELLS - 2)
    var tx = gx - Float64(i)
    var ty = gy - Float64(j)
    var total = Float64(0)
    for dj in range(2):
        for di in range(2):
            var ci = i + di
            var value = west
            if ci >= CELLS:
                value = east
            if ci >= 0 and ci < CELLS:
                value = field[ci + CELLS * (j + dj)]
            var wx = tx if di == 1 else 1 - tx
            var wy = ty if dj == 1 else 1 - ty
            total += wx * wy * value
    return total


def heat_color(level: Float64) -> Color:
    """Return the color of a level from zero to one, blue to red."""
    var stops: List[Float64] = [
        0.13,
        0.25,
        0.60,
        0.40,
        0.65,
        0.85,
        0.95,
        0.94,
        0.88,
        0.93,
        0.60,
        0.40,
        0.72,
        0.15,
        0.16,
    ]
    var t = min(max(level, 0), 1) * 4
    var k = min(Int(t), 3)
    var f = t - Float64(k)
    var r = stops[3 * k] + f * (stops[3 * k + 3] - stops[3 * k])
    var g = stops[3 * k + 1] + f * (stops[3 * k + 4] - stops[3 * k + 1])
    var b = stops[3 * k + 2] + f * (stops[3 * k + 5] - stops[3 * k + 2])
    return Color(UInt8(Int(255 * r)), UInt8(Int(255 * g)), UInt8(Int(255 * b)))


def trace(
    mut image: Framebuffer,
    u: List[Float64],
    v: List[Float64],
    start_x: Float64,
    start_y: Float64,
) raises:
    """Draw the streamline through a point, by midpoint steps."""
    var x = start_x
    var y = start_y
    var step = 0.25 / Float64(SIZE)
    for _ in range(TRACE_STEPS):
        var ux = sample(u, x, y, 0, 0)
        var uy = sample(v, x, y, 0, 0)
        var size = sqrt(ux * ux + uy * uy)
        if size < 1e-4:
            return
        var mx = x + 0.5 * step * ux / size
        var my = y + 0.5 * step * uy / size
        ux = sample(u, mx, my, 0, 0)
        uy = sample(v, mx, my, 0, 0)
        size = sqrt(ux * ux + uy * uy)
        if size < 1e-4:
            return
        x += step * ux / size
        y += step * uy / size
        if x <= 0 or x >= 1 or y <= 0 or y >= 1:
            return
        var px = Int(x * Float64(SIZE))
        var py = SIZE - 1 - Int(y * Float64(SIZE))
        image.set_pixel(px, py, Color(255, 255, 255))


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    # A side of 1 m, a diffusivity of 1 m²/s and a difference of 1 K, so
    # the gravity is the Rayleigh number times the Prandtl number.
    var flow = FlowCase(
        Grid(CELLS, CELLS, Length64(1, METER), Length64(1, METER)),
        Density64(1, KILOGRAM_PER_CUBIC_METER),
        DynamicViscosity64(0.71, PASCAL_SECOND),
    )
    var buoyant = BuoyantCase(
        flow^,
        ThermalDiffusivity64(1, SQUARE_METER_PER_SECOND),
        ThermalExpansion64(1, PER_KELVIN),
        Acceleration64(RAYLEIGH * 0.71, METER_PER_SECOND_SQUARED),
        Temperature64(300, KELVIN),
    )
    buoyant.set_thermal_boundary(
        WEST, fixed_temperature(Temperature64(300.5, KELVIN))
    )
    buoyant.set_thermal_boundary(
        EAST, fixed_temperature(Temperature64(299.5, KELVIN))
    )
    var solver = BuoyantSolver(buoyant^, default_options())
    var steps = solver.run_to_steady(
        Duration64(0.0005, SECOND),
        TemperatureDifference64(2e-5, KELVIN_DIFFERENCE),
        8000,
    )
    var image = Framebuffer(SIZE, SIZE, Color(0, 0, 0))
    for py in range(SIZE):
        for px in range(SIZE):
            var x = (Float64(px) + 0.5) / Float64(SIZE)
            var y = (Float64(SIZE - 1 - py) + 0.5) / Float64(SIZE)
            var level = sample(solver.temperatures, x, y, 300.5, 299.5)
            image.set_pixel(px, py, heat_color(level - 299.5))
    for s in range(SEEDS):
        var t = (Float64(s) + 0.5) / Float64(SEEDS)
        trace(image, solver.flow.u, solver.flow.v, 0.5, 0.5 + 0.49 * t)
    Path(destination).write_bytes(encode(image))
    print(
        "Steady after",
        steps,
        "steps. The Nusselt number of the hot wall is",
        solver.wall_gradient(WEST),
    )
