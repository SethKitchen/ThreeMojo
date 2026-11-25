# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The flow in a square cavity whose lid slides to the right.

    mojo run -I . examples/cavity_flow.mojo [out/cavity-flow.png]

The page is Finite-volume flow. The cavity is 1 m on a side. Its lid moves
at 1 m/s, and the Reynolds number is 400. `FlowSolver` runs the PISO
algorithm on 48 by 48 cells until the flow is steady.

The color is the speed, from rest (dark blue) to the lid speed (yellow).
The white lines are streamlines. They show the main vortex, which sits
right of the center, and the weak vortices in the two bottom corners.
The program prints the velocity at the center of the cavity.

This is a picture of a coarse model, for teaching.
"""

from std.math import sqrt
from std.pathlib import Path
from extensions.cfd.flow import (
    FlowCase,
    FlowSolver,
    Grid,
    default_options,
    fixed_velocity,
)
from extensions.cfd.kinds import NORTH
from extensions.cfd.quantities import DynamicViscosity64, PASCAL_SECOND
from render.framebuffer import Color, Framebuffer
from render.png import encode
from tools._example_output import example_destination
from units.si import (
    Density64,
    Duration64,
    KILOGRAM_PER_CUBIC_METER,
    Length64,
    METER,
    METER_PER_SECOND,
    SECOND,
    Velocity64,
)

comptime DEFAULT_OUTPUT = "out/cavity-flow.png"
comptime SIZE = 720
comptime CELLS = 48
comptime REYNOLDS = 400.0
# The streamlines start on this many points of each of two lines.
comptime SEEDS = 14
comptime TRACE_STEPS = 6000


def sample(
    field: List[Float64], x: Float64, y: Float64, lid: Float64
) -> Float64:
    """Return a cell-centered field at a point, by bilinear interpolation.

    Outside the cell centers the field goes to its wall value: zero, or
    `lid` at the top.
    """
    var gx = x * Float64(CELLS) - 0.5
    var gy = y * Float64(CELLS) - 0.5
    var i = Int(gx + 1) - 1
    var j = Int(gy + 1) - 1
    var tx = gx - Float64(i)
    var ty = gy - Float64(j)
    var total = Float64(0)
    for dj in range(2):
        for di in range(2):
            var ci = i + di
            var cj = j + dj
            var value = Float64(0)
            if cj >= CELLS:
                value = lid
            if ci >= 0 and ci < CELLS and cj >= 0 and cj < CELLS:
                value = field[ci + CELLS * cj]
            var wx = tx if di == 1 else 1 - tx
            var wy = ty if dj == 1 else 1 - ty
            total += wx * wy * value
    return total


def speed_color(speed: Float64) -> Color:
    """Return the color of a speed from zero to one, dark blue to yellow."""
    var stops: List[Float64] = [
        0.07,
        0.03,
        0.33,
        0.28,
        0.17,
        0.48,
        0.13,
        0.44,
        0.56,
        0.21,
        0.72,
        0.47,
        0.99,
        0.91,
        0.14,
    ]
    # A square root spreads the slow flow of the corners over more colors.
    var t = sqrt(min(max(speed, 0), 1)) * 4
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
        var ux = sample(u, x, y, 1)
        var uy = sample(v, x, y, 0)
        var size = sqrt(ux * ux + uy * uy)
        if size < 1e-5:
            return
        var mx = x + 0.5 * step * ux / size
        var my = y + 0.5 * step * uy / size
        ux = sample(u, mx, my, 1)
        uy = sample(v, mx, my, 0)
        size = sqrt(ux * ux + uy * uy)
        if size < 1e-5:
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
    var grid = Grid(CELLS, CELLS, Length64(1, METER), Length64(1, METER))
    var flow = FlowCase(
        grid,
        Density64(1, KILOGRAM_PER_CUBIC_METER),
        DynamicViscosity64(1 / REYNOLDS, PASCAL_SECOND),
    )
    flow.set_boundary(
        NORTH,
        fixed_velocity(
            Velocity64(1, METER_PER_SECOND), Velocity64(0, METER_PER_SECOND)
        ),
    )
    var solver = FlowSolver(flow^, default_options())
    var steps = solver.run_to_steady(
        Duration64(4 / Float64(CELLS), SECOND),
        Velocity64(1e-5, METER_PER_SECOND),
        5000,
    )
    var image = Framebuffer(SIZE, SIZE, Color(0, 0, 0))
    for py in range(SIZE):
        for px in range(SIZE):
            var x = (Float64(px) + 0.5) / Float64(SIZE)
            var y = (Float64(SIZE - 1 - py) + 0.5) / Float64(SIZE)
            var ux = sample(solver.u, x, y, 1)
            var uy = sample(solver.v, x, y, 0)
            image.set_pixel(px, py, speed_color(sqrt(ux * ux + uy * uy)))
    # Seeds from the center of the main vortex toward the right wall, and
    # near the two bottom corners.
    for s in range(SEEDS):
        var t = (Float64(s) + 0.5) / Float64(SEEDS)
        trace(image, solver.u, solver.v, 0.56 + 0.43 * t, 0.6)
        trace(image, solver.u, solver.v, 0.01 + 0.12 * t, 0.01 + 0.12 * t)
        trace(image, solver.u, solver.v, 0.99 - 0.25 * t, 0.01 + 0.25 * t)
    Path(destination).write_bytes(encode(image))
    var half = CELLS // 2
    print(
        "Steady after",
        steps,
        "steps. At the center, u =",
        solver.velocity_x(half, half).to(METER_PER_SECOND),
        "m/s and v =",
        solver.velocity_y(half, half).to(METER_PER_SECOND),
        "m/s.",
    )
