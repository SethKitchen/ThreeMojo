# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reading a frame the way a shader reads a texture: bilinear, clamped at
the edges, with `v` running up from the bottom.

Every pass in `postprocessing` reads its frame through these, so a tap
past the edge means one thing everywhere: the edge pixel, as a texture
with `ClampToEdgeWrapping` gives it.
"""

from render.framebuffer import FloatColor


def clamped_tap(
    colors: List[FloatColor], width: Int, height: Int, x: Float32, y: Float32
) -> FloatColor:
    """Return the light at a point in pixel coordinates, blended from the
    four pixels around it and held at the edges.

    Pixel centers are on the integers and rows count down from the top.

    Args:
        colors: The frame's pixels, row by row.
        width: The frame's width in pixels.
        height: The frame's height in pixels.
        x: The column, fractional.
        y: The row, fractional.

    Returns:
        The bilinear blend of the four pixels around the point.
    """
    var px = x
    var py = y
    if px < 0:
        px = 0
    if py < 0:
        py = 0
    if px > Float32(width - 1):
        px = Float32(width - 1)
    if py > Float32(height - 1):
        py = Float32(height - 1)
    var x0 = Int(px)
    var y0 = Int(py)
    var fx = px - Float32(x0)
    var fy = py - Float32(y0)
    var x1 = x0 + 1
    var y1 = y0 + 1
    if x1 >= width:
        x1 = width - 1
    if y1 >= height:
        y1 = height - 1
    var top = mix(colors[y0 * width + x0], colors[y0 * width + x1], fx)
    var bottom = mix(colors[y1 * width + x0], colors[y1 * width + x1], fx)
    return mix(top, bottom, fy)


def sample(
    colors: List[FloatColor], width: Int, height: Int, u: Float32, v: Float32
) -> FloatColor:
    """Return the light at a texture coordinate, as a shader's `texture`
    reads it.

    Args:
        colors: The frame's pixels, row by row.
        width: The frame's width in pixels.
        height: The frame's height in pixels.
        u: Across, zero at the left edge and one at the right.
        v: Up, zero at the bottom edge and one at the top, as `vUv` runs.

    Returns:
        The bilinear blend at that point, held at the edges.
    """
    return clamped_tap(
        colors,
        width,
        height,
        u * Float32(width) - 0.5,
        (1 - v) * Float32(height) - 0.5,
    )


def mix(a: FloatColor, b: FloatColor, t: Float32) -> FloatColor:
    """Return `a` moved toward `b` by `t`, every channel: GLSL's `mix`.

    Args:
        a: Where `t` of zero lands.
        b: Where `t` of one lands.
        t: How far from `a` toward `b`.

    Returns:
        The blend.
    """
    return FloatColor(
        a.r + (b.r - a.r) * t,
        a.g + (b.g - a.g) * t,
        a.b + (b.b - a.b) * t,
        a.a + (b.a - a.a) * t,
    )


def u_of(x: Int, width: Int) -> Float32:
    """Return a column's texture coordinate, at its center.

    Args:
        x: The column.
        width: The frame's width in pixels.

    Returns:
        The `u` of the column's center.
    """
    return (Float32(x) + 0.5) / Float32(width)


def v_of(y: Int, height: Int) -> Float32:
    """Return a row's texture coordinate, at its center, up from the bottom.

    Args:
        y: The row, down from the top.
        height: The frame's height in pixels.

    Returns:
        The `v` of the row's center.
    """
    return 1 - (Float32(y) + 0.5) / Float32(height)
