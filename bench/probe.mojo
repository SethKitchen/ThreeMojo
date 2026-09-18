# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Standalone triangle fill used to compare Mojo 1.1 against Mojo 1.0.

    mojo build -o bench/build/probe bench/probe.mojo

This file imports nothing from ThreeMojo. The 1.0 twin is `bench/mojo10/probe.mojo`.
Both walk the same pixels so the compilers and runtimes can be timed apart from
the library.
"""

comptime WIDTH = 512
comptime HEIGHT = 512
comptime FRAMES = 60


def edge(
    ax: Float32, ay: Float32, bx: Float32, by: Float32, px: Float32, py: Float32
) -> Float32:
    """Return the signed parallelogram area of edge AB seen from P."""
    return (px - ax) * (by - ay) - (py - ay) * (bx - ax)


def main() raises:
    var pixels = List[UInt32](length=WIDTH * HEIGHT, fill=UInt32(0))
    var ax = Float32(40)
    var ay = Float32(HEIGHT) - Float32(40)
    var bx = Float32(WIDTH) * Float32(0.5)
    var by = Float32(40)
    var cx = Float32(WIDTH) - Float32(40)
    var cy = Float32(HEIGHT) - Float32(50)
    var area = edge(ax, ay, bx, by, cx, cy)
    var checksum = UInt32(0)
    for frame in range(FRAMES):
        for y in range(HEIGHT):
            for x in range(WIDTH):
                var px = Float32(x) + Float32(0.5)
                var py = Float32(y) + Float32(0.5)
                var w0 = edge(bx, by, cx, cy, px, py)
                var w1 = edge(cx, cy, ax, ay, px, py)
                var w2 = edge(ax, ay, bx, by, px, py)
                if (w0 >= 0 and w1 >= 0 and w2 >= 0) or (
                    w0 <= 0 and w1 <= 0 and w2 <= 0
                ):
                    var value = UInt32(frame + x + y)
                    pixels[y * WIDTH + x] = value
                    checksum += value
    print(checksum, pixels[0], area)
