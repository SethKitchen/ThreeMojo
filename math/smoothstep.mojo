# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A smooth rise from zero to one between two edges, GLSL's `smoothstep`.

Shared by the spot light's cone and the linear fog, and by both rasterizers:
the CPU calls it on the host and the GPU calls it inside the kernel, and the
parity tests hold the two to the same numbers. It lives in `math` rather than
beside either caller so that `core.fog` and `lights.lighting` can both import
it without importing each other.
"""


def smoothstep(edge0: Float32, edge1: Float32, x: Float32) -> Float32:
    """Return zero below `edge0`, one above `edge1`, and a smooth rise between.

    GLSL's `smoothstep`: the cubic Hermite curve `t * t * (3 - 2 * t)` over
    the fraction of the way `x` lies from `edge0` to `edge1`. GLSL leaves the
    result undefined when the two edges coincide. Here two equal edges are a
    hard step, zero at and below them and one above, so a spot light with no
    penumbra has a crisp rim rather than a division by zero.

    Args:
        edge0: Where the rise starts. At or below it the answer is zero.
        edge1: Where the rise ends. At or above it the answer is one.
        x: The value to place between the edges.

    Returns:
        A number from zero to one.
    """
    if x <= edge0:
        return 0
    if x >= edge1:
        return 1
    var t = (x - edge0) / (edge1 - edge0)
    return t * t * (3 - 2 * t)
