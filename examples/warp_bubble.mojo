# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An Alcubierre bubble crossing the frame, as an animation.

    mojo run -I . examples/warp_bubble.mojo [path.png]

The page is Warp drives. The bubble moves along x at half the speed of
light, in the frame of the stars. Each frame cuts the plane z = 0. The
left panel is the energy density that the Eulerian observer measures,
and the right panel is its momentum density along x. Red is negative and
blue is positive. The exact solver finds each frame at one instant, with
no time slices around it.
"""

from tools._example_output import blit, example_destination, write_frames

from extensions.warp.analytic import exact_stress_energy, sample_metric
from extensions.warp.frame import to_eulerian
from extensions.warp.grid import SpacetimeCenter, SpacetimeGrid
from extensions.warp.kinds import T_AXIS, Z_AXIS
from extensions.warp.metrics import AlcubierreMetric
from extensions.warp.plot import draw_plane_range, slice_plane
from extensions.warp.quantities import SPEED_OF_LIGHT, fraction_of_light
from render.framebuffer import Color, Framebuffer
from units.si import Duration64, InverseLength64, Length64

comptime DEFAULT_OUTPUT = "out/warp-bubble.png"
comptime COLUMNS = 120
comptime ROWS = 60
comptime STEP = 0.1
comptime SCALE = 3
comptime GAP = 6
comptime FRAMES = 30
comptime DELAY_MS = 80
comptime BETA = 0.5


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var grid = SpacetimeGrid(
        1,
        COLUMNS,
        ROWS,
        1,
        Duration64(1.0),
        Length64(STEP),
        Length64(STEP),
        Length64(STEP),
    )
    var bubble = AlcubierreMetric(
        fraction_of_light(BETA), Length64(2.0), InverseLength64(1.5), False
    )
    var half_x = Float64(COLUMNS + 1) / 2.0 * STEP
    var half_y = Float64(ROWS + 1) / 2.0 * STEP
    var travel = Float64(COLUMNS) * STEP
    var frames = List[Framebuffer]()
    # One color range for every frame: that of the bubble in the middle.
    var middle = SpacetimeCenter(
        Duration64(1.0), Length64(half_x), Length64(half_y), Length64(STEP)
    )
    var still = to_eulerian(
        exact_stress_energy(bubble, grid, middle),
        sample_metric(bubble, grid, middle),
    )
    var e = slice_plane(
        still.tensor.component(0, 0), grid, T_AXIS, 0, Z_AXIS, 0
    ).bounds()
    var p = slice_plane(
        still.tensor.component(0, 1), grid, T_AXIS, 0, Z_AXIS, 0
    ).bounds()
    var bounds = SIMD[DType.float64, 4](e[0], e[1], p[0], p[1])
    for frame in range(FRAMES):
        # The bubble's center goes from one end of the plane to the other.
        var place = -travel / 2.0 + travel * Float64(frame) / Float64(
            FRAMES - 1
        )
        var time = place / (BETA * SPEED_OF_LIGHT.value)
        var center = SpacetimeCenter(
            Duration64(1.0 - time),
            Length64(half_x),
            Length64(half_y),
            Length64(STEP),
        )
        var metric = sample_metric(bubble, grid, center)
        var eulerian = to_eulerian(
            exact_stress_energy(bubble, grid, center), metric
        )
        var energy = slice_plane(
            eulerian.tensor.component(0, 0), grid, T_AXIS, 0, Z_AXIS, 0
        )
        var momentum = slice_plane(
            eulerian.tensor.component(0, 1), grid, T_AXIS, 0, Z_AXIS, 0
        )
        var side = COLUMNS * SCALE
        var sheet = Framebuffer(
            2 * side + 3 * GAP, ROWS * SCALE + 2 * GAP, Color(32, 34, 40)
        )
        blit(
            sheet,
            draw_plane_range(energy, SCALE, bounds[0], bounds[1]),
            GAP,
            GAP,
        )
        blit(
            sheet,
            draw_plane_range(momentum, SCALE, bounds[2], bounds[3]),
            2 * GAP + side,
            GAP,
        )
        frames.append(sheet^)
    write_frames(frames, destination, DELAY_MS, FRAMES)
