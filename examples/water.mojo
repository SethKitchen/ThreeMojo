# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One Clearwater still: shallow water at five seconds.

    mojo run -I . examples/water.mojo [path.png]

The clock is fixed, so the camera does not bob. The ocean, the frame
and the pebble photograph match the page. The page is Water.
"""

from extensions.water.frame import render_water
from extensions.water.pebbles import pebble_bed
from extensions.water.resolution import SpectrumResolution
from extensions.water.view import FRAME
from render.jpeg import decode
from render.png import encode as encode_png
from std.pathlib import Path
from std.sys import argv
from units.si import RADIAN, SECOND, Angle, Duration

comptime DEFAULT_OUTPUT = "out/water.png"
comptime PEBBLES = "assets/pebbles.jpg"
comptime WIDTH = 1280
comptime HEIGHT = 720


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])
    var bed = pebble_bed(decode(Path(PEBBLES).read_bytes()))
    var image = render_water(
        WIDTH,
        HEIGHT,
        Duration(5.0, SECOND),
        FRAME,
        False,
        SpectrumResolution(256),
        64,
        256,
        SpectrumResolution(128),
        False,
        bed,
        Angle(-0.22, RADIAN),
    )
    Path(destination).write_bytes(encode_png(image))
    print("Wrote", destination)
