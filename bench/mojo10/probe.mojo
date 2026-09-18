# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Standalone triangle fill for the Mojo 1.0.0 compiler. `make lint` excludes it."""

comptime WIDTH = 512
comptime HEIGHT = 512
comptime FRAMES = 60


def edge(
    ax: Float32, ay: Float32, bx: Float32, by: Float32, px: Float32, py: Float32
) -> Float32:
    return (px - ax) * (by - ay) - (py - ay) * (bx - ax)


def main() raises:
    var pixels = List[UInt32]()
    var count = WIDTH * HEIGHT
    var filled = 0
    while filled < count:
        pixels.append(0)
        filled += 1
    var ax = Float32(40)
    var ay = Float32(HEIGHT) - Float32(40)
    var bx = Float32(WIDTH) * Float32(0.5)
    var by = Float32(40)
    var cx = Float32(WIDTH) - Float32(40)
    var cy = Float32(HEIGHT) - Float32(50)
    var area = edge(ax, ay, bx, by, cx, cy)
    var checksum = UInt32(0)
    var frame = 0
    while frame < FRAMES:
        var y = 0
        while y < HEIGHT:
            var x = 0
            while x < WIDTH:
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
                    checksum = checksum + value
                x += 1
            y += 1
        frame += 1
    print(checksum, pixels[0], area)
