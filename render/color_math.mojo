# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Color mixes shared by the passes and the CARLA sky.

`mix_opaque` mixes red, green and blue and stays opaque.
`floor_channels` raises each negative channel to zero.
"""

from render.framebuffer import FloatColor
from std.math import max


def mix_opaque(a: FloatColor, b: FloatColor, t: Float32) -> FloatColor:
    """Return `a` moved toward `b` by `t`, and opaque.

    Args:
        a: The start color. Its alpha is not kept.
        b: The color to move toward.
        t: How far. Zero leaves `a`. One takes `b`'s red, green and blue.

    Returns:
        The mixed color, with alpha one.
    """
    return FloatColor(
        a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t
    )


def floor_channels(color: FloatColor) -> FloatColor:
    """Return `color` with each negative channel raised to zero.

    Args:
        color: The color.

    Returns:
        A color whose channels are at least zero.
    """
    return FloatColor(
        max(color.r, 0), max(color.g, 0), max(color.b, 0), max(color.a, 0)
    )
