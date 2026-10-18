# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Where a fragment is, for the CPU and GPU node evaluators.

Both read GLSL's `gl_FragCoord`, `gl_PointCoord` and the screen size from
the same step.
"""

from materials.nodes import AT_RIGHT, AT_UP, NodeContext
from math.vector2 import Vector2
from render.pointrule import gl_point_coord


def sample_pixel(x: Int, y: Int, context: NodeContext) -> Tuple[Int, Int]:
    """Return the pixel a derivative sample reads.

    Args:
        x: The pixel column.
        y: The pixel row, counted down from the top.
        context: Which sample. `AT_RIGHT` steps one column to the right.
            `AT_UP` steps one row up, which is one less in this count.

    Returns:
        The column and the row.
    """
    return (
        x + (1 if context == AT_RIGHT else 0),
        y - (1 if context == AT_UP else 0),
    )


def pixel_frag_coord(
    x: Int,
    y: Int,
    height: Int,
    depth: Float32,
    context: NodeContext,
) -> SIMD[DType.float32, 4]:
    """Return `gl_FragCoord` for one pixel.

    Args:
        x: The pixel column.
        y: The pixel row, counted down from the top.
        height: The target height in pixels.
        depth: The fragment depth, from minus one to one.
        context: Which sample. `AT_RIGHT` and `AT_UP` step one pixel.

    Returns:
        The pixel center from the bottom left, the depth from zero to
        one, and one.
    """
    var sample_x, sample_y = sample_pixel(x, y, context)
    return SIMD[DType.float32, 4](
        Float32(sample_x) + 0.5,
        Float32(height - sample_y) - 0.5,
        depth * 0.5 + 0.5,
        1,
    )


def sampled_point_coord(
    context: NodeContext,
    x: Int,
    y: Int,
    center: Vector2,
    size: Float32,
) -> SIMD[DType.float32, 4]:
    """Return `gl_PointCoord` for one sample.

    Args:
        context: Which sample. A corner is the center of the point.
            `AT_RIGHT` and `AT_UP` step one pixel.
        x: The pixel column.
        y: The pixel row, counted down from the top.
        center: Where the point projects, in pixels.
        size: How many pixels across the point is.

    Returns:
        The coordinate, then two zeros. A corner is `(0.5, 0.5, 0, 0)`.
    """
    if context.is_corner():
        return SIMD[DType.float32, 4](0.5, 0.5, 0, 0)
    var sample_x, sample_y = sample_pixel(x, y, context)
    var place = gl_point_coord(center, size, sample_x, sample_y)
    return SIMD[DType.float32, 4](place.x, place.y, 0, 0)


def screen_size_coord(width: Int, height: Int) -> SIMD[DType.float32, 4]:
    """Return the target size in pixels.

    Args:
        width: The target width in pixels.
        height: The target height in pixels.

    Returns:
        The width and the height, then two zeros.
    """
    return SIMD[DType.float32, 4](Float32(width), Float32(height), 0, 0)
