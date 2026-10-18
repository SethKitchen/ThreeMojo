# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Where a fragment is, for the CPU and GPU node evaluators.

Both read GLSL's `gl_FragCoord` and the screen size from the same step.
"""

from materials.nodes import AT_RIGHT, AT_UP, NodeContext


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
    var sample_x = x + (1 if context == AT_RIGHT else 0)
    var sample_y = y - (1 if context == AT_UP else 0)
    return SIMD[DType.float32, 4](
        Float32(sample_x) + 0.5,
        Float32(height - sample_y) - 0.5,
        depth * 0.5 + 0.5,
        1,
    )


def screen_size_coord(width: Int, height: Int) -> SIMD[DType.float32, 4]:
    """Return the target size in pixels.

    Args:
        width: The target width in pixels.
        height: The target height in pixels.

    Returns:
        The width and the height, then two zeros.
    """
    return SIMD[DType.float32, 4](Float32(width), Float32(height), 0, 0)
