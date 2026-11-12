# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What a passenger sees from the center of an Alcubierre bubble.

    mojo run -I . examples/warp_view.mojo [path.png]

The page is Warp drives. Each panel looks ahead, along the direction of
travel, with a field of view of 120 degrees, at a test sky: a globe of
lines every 15 degrees, red ahead and blue behind. The left panel is flat
space. The other panels are from inside a bubble at 1 c, 3 c and 6 c.
Each ray of light is traced back through the bubble wall to the sky, so
the panels show how the bubble bends the light: the faster it goes, the
more of the sky crowds into the view ahead.
"""

from tools._example_output import blit, example_destination

from extensions.warp.geodesics import draw_view, passenger_view
from extensions.warp.metrics import AlcubierreMetric, MinkowskiMetric
from extensions.warp.quantities import fraction_of_light
from extensions.warp.tensor import Vector4
from render.framebuffer import Color, Framebuffer
from render.png import encode
from std.pathlib import Path
from units.si import Angle64, InverseLength64, Length64

comptime DEFAULT_OUTPUT = "out/warp-view.png"
comptime WIDTH = 160
comptime HEIGHT = 120
comptime GAP = 6
comptime FIELD = 2.0943951023931953
comptime STEP = 0.05
comptime STEPS = 4000
comptime ESCAPE = 6.0


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var center = Vector4(0.0)
    var sheet = Framebuffer(
        4 * WIDTH + 5 * GAP, HEIGHT + 2 * GAP, Color(32, 34, 40)
    )
    var flat = passenger_view(
        MinkowskiMetric(),
        center,
        WIDTH,
        HEIGHT,
        Angle64(FIELD),
        Length64(STEP),
        STEPS,
        Length64(ESCAPE),
    )
    blit(sheet, draw_view(flat, WIDTH, HEIGHT), GAP, GAP)
    var speeds: List[Float64] = [1.0, 3.0, 6.0]
    for k in range(3):
        var bubble = AlcubierreMetric(
            fraction_of_light(speeds[k]),
            Length64(2.0),
            InverseLength64(1.5),
            True,
        )
        var view = passenger_view(
            bubble,
            center,
            WIDTH,
            HEIGHT,
            Angle64(FIELD),
            Length64(STEP),
            STEPS,
            Length64(ESCAPE),
        )
        blit(
            sheet,
            draw_view(view, WIDTH, HEIGHT),
            GAP + (k + 1) * (WIDTH + GAP),
            GAP,
        )
    Path(destination).write_bytes(encode(sheet))
    print("Wrote", destination)
