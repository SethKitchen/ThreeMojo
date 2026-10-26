# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A side of an image or a view times a `Float32` scale.

A scale such as 0.9 is stored as the `Float32` nearest it, a little
below 0.9. The `Float32` product of an ordinary side rounds back up to
the whole number that JavaScript gets from its `Float64` 0.9: 1000 times
0.9 is 900. The `Float64` product of the same `Float32` scale stays
below, at 899.99998. Past 2^24 a `Float32` cannot hold every whole side,
so the product is a `Float64` there.
"""

comptime EXACT_SIDES = 16777216
"""The largest side whose every whole value a `Float32` holds: 2^24."""


def scaled_side(size: Int, scale: Float32) -> Float64:
    """Return a side times a scale, as the renderers have scaled it.

    Args:
        size: The side, in pixels.
        scale: The scale.

    Returns:
        The `Float32` product, as a `Float64`, for a side of at most 2^24
        either way. The `Float64` product for a larger side. Either can
        be infinite, for the caller to refuse.
    """
    if size <= EXACT_SIDES and size >= -EXACT_SIDES:
        return Float64(Float32(size) * scale)
    return Float64(size) * Float64(scale)
