# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A smooth rise from zero to one between two edges, GLSL's `smoothstep`.

`smoothstep` is a hard step when the edges are equal, so a spot with no
penumbra stays crisp. `clamped_smoothstep` holds the fraction from zero to
one, so the edges may come in either order.

The spot light's cone, the linear fog, and both rasterizers share
`smoothstep`. The CPU calls it on the host and the GPU calls it inside the
kernel, and the parity tests hold the two to the same numbers. It lives in
`math` rather than beside either caller so that `core.fog` and
`lights.lighting` can both import it without importing each other.
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


def clamped_smoothstep(edge0: Float32, edge1: Float32, x: Float32) -> Float32:
    """Return the Hermite step, with the fraction held from zero to one.

    The edges may come in either order. The fraction is `clamp` of
    `(x - edge0) / (edge1 - edge0)`.

    Args:
        edge0: The edge that gives zero.
        edge1: The edge that gives one.
        x: The value.

    Returns:
        A number from zero to one.
    """
    var fraction = (x - edge0) / (edge1 - edge0)
    var t = max(Float32(0), min(Float32(1), fraction))
    return t * t * (3 - 2 * t)


def clamped_smoothstep(edge0: Float64, edge1: Float64, x: Float64) -> Float64:
    """Return the Hermite step, with the fraction held from zero to one.

    The edges may come in either order. The fraction is `clamp` of
    `(x - edge0) / (edge1 - edge0)`.

    Args:
        edge0: The edge that gives zero.
        edge1: The edge that gives one.
        x: The value.

    Returns:
        A number from zero to one.
    """
    var fraction = (x - edge0) / (edge1 - edge0)
    var t = max(Float64(0), min(Float64(1), fraction))
    return t * t * (3 - 2 * t)
