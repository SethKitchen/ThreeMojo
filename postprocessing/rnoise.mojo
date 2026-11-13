# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The analytic noise three.js r186's screen-space nodes share:
`bindAnalyticNoise`, from `examples/jsm/tsl/utils/RNoise.js`.

Each pixel of a 32-pixel tile gets four numbers from an R4
low-discrepancy sequence. The tile moves each frame by an R2 sequence of
the frame's index. A node adds its own seed to the index and to the
sequence, so two nodes do not share a phase.

`postprocessing.temporal_denoise.analytic_noise` is the first of the four
numbers with the denoiser's seed.
"""

from math.sine import fraction
from math.vector4 import Vector4
from std.math import floor


# The tile's side, in pixels: three.js's `tileSize`.
comptime NOISE_TILE = Float32(32)
# The plastic number, the base of the R4 sequence: three.js's `P`.
comptime PLASTIC = 1.32471795724474602596


def analytic_noise4(x: Int, y: Int, index: Int, seed: Int) -> Vector4:
    """Return the four numbers of three.js's `bindAnalyticNoise` at a
    pixel.

    Args:
        x: The column.
        y: The row, down from the top.
        index: The frame, three.js's `sampleIndex`.
        seed: The node's seed.

    Returns:
        Four numbers, each from zero up to one.
    """
    var at = Float32(index + seed)
    var shift_x = floor(fraction(at * Float32(0.7548776662)) * NOISE_TILE)
    var shift_y = floor(fraction(at * Float32(0.5698402910)) * NOISE_TILE)
    var cx = Float32(x) + shift_x
    var cy = Float32(y) + shift_y
    cx = cx - floor(cx / NOISE_TILE) * NOISE_TILE
    cy = cy - floor(cy / NOISE_TILE) * NOISE_TILE
    var t = (
        cx * Float32(1 / PLASTIC)
        + cy * Float32(1 / (PLASTIC * PLASTIC))
        + Float32(seed)
    )
    # three.js's third factor is not `1 / P^3`. Its comment says that this
    # constant gives better noise.
    return Vector4(
        fraction(t * Float32(PLASTIC) * Float32(1 / PLASTIC)),
        fraction(t * Float32(PLASTIC * 2) * Float32(1 / (PLASTIC * PLASTIC))),
        fraction(t * Float32(PLASTIC * 3) * Float32(0.4198754210)),
        fraction(
            t
            * Float32(PLASTIC * 4)
            * Float32(1 / (PLASTIC * PLASTIC * PLASTIC))
        ),
    )
