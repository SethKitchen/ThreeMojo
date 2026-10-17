# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Schlick's Fresnel rise, three.js's `F_Schlick`.

The fifth power of one minus the cosine is an `exp2` of a quadratic, so
the host and a kernel compute it from one intrinsic.
"""

from std.math import exp2

# The two numbers in three.js's `F_Schlick`.
comptime _FRESNEL_SLOPE = Float32(-5.55473)
comptime _FRESNEL_OFFSET = Float32(-6.98316)


def schlick_weight(cosine: Float32) -> Float32:
    """Return how far Schlick's curve has risen toward a grazing angle.

    Args:
        cosine: The cosine of the angle, from zero to one.

    Returns:
        The weight, near zero head on and one at a grazing angle.
    """
    return exp2((_FRESNEL_SLOPE * cosine + _FRESNEL_OFFSET) * cosine)
