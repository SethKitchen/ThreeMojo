# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The even-odd test for one edge of a polygon in the plane.

A ray to the right from a point crosses the edge when the edge straddles
the point's height and the edge lies to the right at that height.
"""


def ray_crosses(
    ax: Float64,
    ay: Float64,
    bx: Float64,
    by: Float64,
    px: Float64,
    py: Float64,
) -> Bool:
    """Return whether a ray to the right from a point crosses an edge.

    Args:
        ax: The first end's x.
        ay: The first end's y.
        bx: The second end's x.
        by: The second end's y.
        px: The point's x.
        py: The point's y.

    Returns:
        Whether this edge changes the even-odd count.
    """
    if (ay > py) != (by > py):
        var x = ax + (py - ay) * (bx - ax) / (by - ay)
        return px < x
    return False
