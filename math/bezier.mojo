# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Bezier weights for a quadratic curve and a cubic curve.

The plane curve and the space curve share them. Each weight is the
scalar three.js multiplies by a control point.
"""


def quadratic_bezier_weights(
    t: Float32,
) -> Tuple[Float32, Float32, Float32]:
    """Return the three quadratic Bezier weights at `t`.

    Args:
        t: How far from the start to the end, from zero to one.

    Returns:
        The weights of the start, the control point, and the end.
    """
    var rest = 1 - t
    return (rest * rest, 2 * rest * t, t * t)


def cubic_bezier_weights(
    t: Float32,
) -> Tuple[Float32, Float32, Float32, Float32]:
    """Return the four cubic Bezier weights at `t`.

    Args:
        t: How far from the start to the end, from zero to one.

    Returns:
        The weights of the start, the first control, the second
        control, and the end.
    """
    var rest = 1 - t
    return (
        rest * rest * rest,
        3 * rest * rest * t,
        3 * rest * t * t,
        t * t * t,
    )


def quadratic_bezier_slope(t: Float32) -> Tuple[Float32, Float32]:
    """Return the two quadratic Bezier slope weights at `t`.

    Args:
        t: How far from the start to the end, from zero to one.

    Returns:
        The weights of the first span and the second span.
    """
    var rest = 1 - t
    return (2 * rest, 2 * t)


def cubic_bezier_slope(t: Float32) -> Tuple[Float32, Float32, Float32]:
    """Return the three cubic Bezier slope weights at `t`.

    Args:
        t: How far from the start to the end, from zero to one.

    Returns:
        The weights of the three spans between the control points.
    """
    var rest = 1 - t
    return (3 * rest * rest, 6 * rest * t, 3 * t * t)
