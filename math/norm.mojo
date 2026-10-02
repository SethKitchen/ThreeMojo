# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Scale-safe scalar norms without narrowing Float32 or Float64 inputs.

Ordinary inputs keep the direct sum-of-squares arithmetic. When the squared
norm is subnormal or nonfinite, finite components are divided by their largest
magnitude first. Direct division also handles the smallest subnormal values.
"""

from std.math import isfinite, sqrt


def _ordinary_squared[dtype: DType](squared: SIMD[dtype, 1]) -> Bool:
    """Whether a direct square root has a normal, finite operand."""
    comptime assert dtype == DType.float32 or dtype == DType.float64
    comptime tiny = SIMD[dtype, 1](
        1.1754943508222875e-38
    ) if dtype == DType.float32 else SIMD[dtype, 1](2.2250738585072014e-308)
    return isfinite(squared) and squared >= tiny


def length2[
    dtype: DType
](x: SIMD[dtype, 1], y: SIMD[dtype, 1]) -> SIMD[dtype, 1]:
    """Return a 2-component Euclidean length in the input precision.

    Args:
        x: The x component.
        y: The y component.

    Returns:
        The length. A finite input can return infinity only if its length
        cannot fit in the input type. Nonfinite inputs follow IEEE arithmetic.
    """
    var squared = x * x + y * y
    if _ordinary_squared(squared):
        return sqrt(squared)
    var scale = max(abs(x), abs(y))
    if scale > 0 and isfinite(scale):
        var sx = x / scale
        var sy = y / scale
        return scale * sqrt(sx * sx + sy * sy)
    return sqrt(squared)


def normalized2[
    dtype: DType
](x: SIMD[dtype, 1], y: SIMD[dtype, 1]) -> Tuple[
    SIMD[dtype, 1], SIMD[dtype, 1]
]:
    """Return the components of a unit direction in the input precision.

    Args:
        x: The x component.
        y: The y component.

    Returns:
        Unit components for a finite nonzero input, even when its length
        cannot fit in the input type. A zero input stays unchanged. A NaN
        squared norm leaves the input unchanged. An input that contains
        infinity divides by infinity, as vector normalization does.
    """
    var squared = x * x + y * y
    if _ordinary_squared(squared):
        var magnitude = sqrt(squared)
        return x / magnitude, y / magnitude
    if squared != squared:
        return x, y
    var scale = max(abs(x), abs(y))
    if scale > 0 and isfinite(scale):
        var sx = x / scale
        var sy = y / scale
        var magnitude = sqrt(sx * sx + sy * sy)
        return sx / magnitude, sy / magnitude
    var magnitude = sqrt(squared)
    if magnitude > 0:
        return x / magnitude, y / magnitude
    return x, y


def length3[
    dtype: DType
](x: SIMD[dtype, 1], y: SIMD[dtype, 1], z: SIMD[dtype, 1]) -> SIMD[dtype, 1]:
    """Return a 3-component Euclidean length in the input precision.

    Args:
        x: The x component.
        y: The y component.
        z: The z component.

    Returns:
        The length. A finite input can return infinity only if its length
        cannot fit in the input type. Nonfinite inputs follow IEEE arithmetic.
    """
    var squared = x * x + y * y + z * z
    if _ordinary_squared(squared):
        return sqrt(squared)
    var scale = max(abs(x), max(abs(y), abs(z)))
    if scale > 0 and isfinite(scale):
        var sx = x / scale
        var sy = y / scale
        var sz = z / scale
        return scale * sqrt(sx * sx + sy * sy + sz * sz)
    return sqrt(squared)


def normalized3[
    dtype: DType
](x: SIMD[dtype, 1], y: SIMD[dtype, 1], z: SIMD[dtype, 1]) -> Tuple[
    SIMD[dtype, 1], SIMD[dtype, 1], SIMD[dtype, 1]
]:
    """Return the components of a unit direction in the input precision.

    Args:
        x: The x component.
        y: The y component.
        z: The z component.

    Returns:
        Unit components for a finite nonzero input, even when its length
        cannot fit in the input type. A zero input stays unchanged. A NaN
        squared norm leaves the input unchanged. An input that contains
        infinity divides by infinity, as vector normalization does.
    """
    var squared = x * x + y * y + z * z
    if _ordinary_squared(squared):
        var magnitude = sqrt(squared)
        return x / magnitude, y / magnitude, z / magnitude
    if squared != squared:
        return x, y, z
    var scale = max(abs(x), max(abs(y), abs(z)))
    if scale > 0 and isfinite(scale):
        var sx = x / scale
        var sy = y / scale
        var sz = z / scale
        var magnitude = sqrt(sx * sx + sy * sy + sz * sz)
        return sx / magnitude, sy / magnitude, sz / magnitude
    var magnitude = sqrt(squared)
    if magnitude > 0:
        return x / magnitude, y / magnitude, z / magnitude
    return x, y, z


def length4[
    dtype: DType
](
    x: SIMD[dtype, 1], y: SIMD[dtype, 1], z: SIMD[dtype, 1], w: SIMD[dtype, 1]
) -> SIMD[dtype, 1]:
    """Return a 4-component Euclidean length in the input precision.

    Args:
        x: The x component.
        y: The y component.
        z: The z component.
        w: The w component.

    Returns:
        The length. A finite input can return infinity only if its length
        cannot fit in the input type. Nonfinite inputs follow IEEE arithmetic.
    """
    var squared = x * x + y * y + z * z + w * w
    if _ordinary_squared(squared):
        return sqrt(squared)
    var scale = max(abs(x), max(abs(y), max(abs(z), abs(w))))
    if scale > 0 and isfinite(scale):
        var sx = x / scale
        var sy = y / scale
        var sz = z / scale
        var sw = w / scale
        return scale * sqrt(sx * sx + sy * sy + sz * sz + sw * sw)
    return sqrt(squared)


def normalized4[
    dtype: DType
](
    x: SIMD[dtype, 1], y: SIMD[dtype, 1], z: SIMD[dtype, 1], w: SIMD[dtype, 1]
) -> Tuple[SIMD[dtype, 1], SIMD[dtype, 1], SIMD[dtype, 1], SIMD[dtype, 1]]:
    """Return the components of a unit direction in the input precision.

    Args:
        x: The x component.
        y: The y component.
        z: The z component.
        w: The w component.

    Returns:
        Unit components for a finite nonzero input, even when its length
        cannot fit in the input type. A zero input stays unchanged. A NaN
        squared norm leaves the input unchanged. An input that contains
        infinity divides by infinity, as vector normalization does.
    """
    var squared = x * x + y * y + z * z + w * w
    if _ordinary_squared(squared):
        var magnitude = sqrt(squared)
        return x / magnitude, y / magnitude, z / magnitude, w / magnitude
    if squared != squared:
        return x, y, z, w
    var scale = max(abs(x), max(abs(y), max(abs(z), abs(w))))
    if scale > 0 and isfinite(scale):
        var sx = x / scale
        var sy = y / scale
        var sz = z / scale
        var sw = w / scale
        var magnitude = sqrt(sx * sx + sy * sy + sz * sz + sw * sw)
        return sx / magnitude, sy / magnitude, sz / magnitude, sw / magnitude
    var magnitude = sqrt(squared)
    if magnitude > 0:
        return x / magnitude, y / magnitude, z / magnitude, w / magnitude
    return x, y, z, w
