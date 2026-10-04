# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Scale-safe scalar norms without narrowing Float32 or Float64 inputs.

Ordinary inputs keep the direct sum-of-squares arithmetic. When the squared
norm is subnormal or nonfinite, finite components are divided by their largest
magnitude first. Direct division also handles the smallest subnormal values.

## Numerical range correction

Finite norm-dependent directions and lengths use scale-safe arithmetic.
Extreme finite results can differ from direct three.js r180 arithmetic.
See `docs/wiki/Norm-consumers.md` for the changed operations, retained
limits, and explicit zero and nonfinite rules.
"""

from math.scaled_products import (
    _sum_products as _scaled_products,
    _common_scale,
)

from std.math import isfinite, sqrt


def _ordinary_squared[dtype: DType](squared: SIMD[dtype, 1]) -> Bool:
    """Whether a direct square root has a normal, finite operand."""
    comptime assert dtype == DType.float32 or dtype == DType.float64
    comptime tiny = SIMD[dtype, 1](
        1.1754943508222875e-38
    ) if dtype == DType.float32 else SIMD[dtype, 1](2.2250738585072014e-308)
    return isfinite(squared) and squared >= tiny


def _ordinary_product[
    dtype: DType
](a: SIMD[dtype, 1], b: SIMD[dtype, 1]) -> Bool:
    """Whether a finite product keeps a normal magnitude or a true zero."""
    return (
        (_ordinary_squared(abs(a * b)) or a == 0 or b == 0)
        and isfinite(a)
        and isfinite(b)
    )


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


def reciprocal_normalized3[
    dtype: DType
](x: SIMD[dtype, 1], y: SIMD[dtype, 1], z: SIMD[dtype, 1]) -> Tuple[
    SIMD[dtype, 1], SIMD[dtype, 1], SIMD[dtype, 1]
]:
    """Normalize while preserving ordinary reciprocal-multiply rounding.

    Args:
        x: The first component.
        y: The second component.
        z: The third component.

    Returns:
        A unit direction for finite nonzero inputs. Zero stays zero.
        Nonfinite inputs retain reciprocal-multiply IEEE arithmetic.
    """
    var squared = x * x + y * y + z * z
    if _ordinary_squared(squared) or not (
        isfinite(x) and isfinite(y) and isfinite(z)
    ):
        var magnitude = sqrt(squared)
        var inverse = 1 / magnitude
        return x * inverse, y * inverse, z * inverse
    return normalized3(x, y, z)


def normalized_difference2[
    dtype: DType
](
    ax: SIMD[dtype, 1],
    ay: SIMD[dtype, 1],
    bx: SIMD[dtype, 1],
    by: SIMD[dtype, 1],
) -> Tuple[SIMD[dtype, 1], SIMD[dtype, 1]]:
    """Return the direction from one finite point to another.

    Args:
        ax: The start x coordinate.
        ay: The start y coordinate.
        bx: The end x coordinate.
        by: The end y coordinate.

    Returns:
        A unit direction, or zero for equal points. Finite endpoints
        whose difference overflows are halved before subtraction.
        Nonfinite endpoints use direct IEEE subtraction and normalization.
    """
    var x = bx - ax
    var y = by - ay
    if (
        not (isfinite(x) and isfinite(y))
        and isfinite(ax)
        and isfinite(ay)
        and isfinite(bx)
        and isfinite(by)
    ):
        x = bx * SIMD[dtype, 1](0.5) - ax * SIMD[dtype, 1](0.5)
        y = by * SIMD[dtype, 1](0.5) - ay * SIMD[dtype, 1](0.5)
    return normalized2(x, y)


def normalized_difference3[
    dtype: DType
](
    ax: SIMD[dtype, 1],
    ay: SIMD[dtype, 1],
    az: SIMD[dtype, 1],
    bx: SIMD[dtype, 1],
    by: SIMD[dtype, 1],
    bz: SIMD[dtype, 1],
) -> Tuple[SIMD[dtype, 1], SIMD[dtype, 1], SIMD[dtype, 1]]:
    """Return the direction from one finite 3D point to another.

    Args:
        ax: The start x coordinate.
        ay: The start y coordinate.
        az: The start z coordinate.
        bx: The end x coordinate.
        by: The end y coordinate.
        bz: The end z coordinate.

    Returns:
        A unit direction, or zero for equal points. Finite endpoints
        whose difference overflows are halved before subtraction.
        Nonfinite endpoints use direct IEEE subtraction and normalization.
    """
    var x = bx - ax
    var y = by - ay
    var z = bz - az
    if (
        not (isfinite(x) and isfinite(y) and isfinite(z))
        and isfinite(ax)
        and isfinite(ay)
        and isfinite(az)
        and isfinite(bx)
        and isfinite(by)
        and isfinite(bz)
    ):
        x = bx * SIMD[dtype, 1](0.5) - ax * SIMD[dtype, 1](0.5)
        y = by * SIMD[dtype, 1](0.5) - ay * SIMD[dtype, 1](0.5)
        z = bz * SIMD[dtype, 1](0.5) - az * SIMD[dtype, 1](0.5)
    return normalized3(x, y, z)


def normalized_cross3(
    ax: Float64, ay: Float64, az: Float64, bx: Float64, by: Float64, bz: Float64
) -> Tuple[Float64, Float64, Float64]:
    """Return a unit cross-product direction without range loss in products.

    Args:
        ax: The first vector's x component.
        ay: The first vector's y component.
        az: The first vector's z component.
        bx: The second vector's x component.
        by: The second vector's y component.
        bz: The second vector's z component.

    Returns:
        The unit cross direction, or zero for a zero cross. Ordinary
        products keep reciprocal-multiply rounding. Finite extreme
        products use separate mantissas and exponents before subtraction.
        Nonfinite inputs retain direct IEEE cross-product arithmetic.
    """
    var x = ay * bz - az * by
    var y = az * bx - ax * bz
    var z = ax * by - ay * bx
    var products = max(
        abs(ay * bz) + abs(az * by),
        max(abs(az * bx) + abs(ax * bz), abs(ax * by) + abs(ay * bx)),
    )
    var finite = (
        isfinite(ax)
        and isfinite(ay)
        and isfinite(az)
        and isfinite(bx)
        and isfinite(by)
        and isfinite(bz)
    )
    var safe = (
        _ordinary_product(ay, bz)
        and _ordinary_product(az, by)
        and _ordinary_product(az, bx)
        and _ordinary_product(ax, bz)
        and _ordinary_product(ax, by)
        and _ordinary_product(ay, bx)
    )
    if (
        _ordinary_squared(x * x + y * y + z * z)
        and safe
        and products <= 4 * max(abs(x), max(abs(y), abs(z)))
    ) or not finite:
        return reciprocal_normalized3(x, y, z)
    var one = [Float64(1), Float64(1)]
    var sx = _scaled_products[DType.float64, 2]([ay, -az], [bz, by], one)
    var sy = _scaled_products[DType.float64, 2]([az, -ax], [bx, bz], one)
    var sz = _scaled_products[DType.float64, 2]([ax, -ay], [by, bx], one)
    var common = _common_scale[DType.float64, 3]([sx, sy, sz])
    return normalized3(common[0], common[1], common[2])
