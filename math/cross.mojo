# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The cross product of two vectors, as a new vector.

`Vector3.cross` keeps the product in one statement. A caller that must
leave both inputs unchanged uses `cross_vectors`. `cross_components`
is that product for any width, including the `Float64` vectors.
`widen_vector`, `wide_cross`, and `wide_dot` keep a `Float32` vector in
four `Float64` lanes.
"""

from math.vector3 import Vector3


def cross_vectors(a: Vector3, b: Vector3) -> Vector3:
    """Return the cross product of `a` and `b`.

    `a` and `b` stay as they were.

    Args:
        a: The first vector.
        b: The second vector.

    Returns:
        The product `a` x `b`.
    """
    var out = a
    out.cross(b)
    return out


def cross_components[
    dtype: DType
](
    ax: SIMD[dtype, 1],
    ay: SIMD[dtype, 1],
    az: SIMD[dtype, 1],
    bx: SIMD[dtype, 1],
    by: SIMD[dtype, 1],
    bz: SIMD[dtype, 1],
) -> Tuple[SIMD[dtype, 1], SIMD[dtype, 1], SIMD[dtype, 1]]:
    """Return the components of `a` cross `b`.

    The products are taken in three.js's order. The width is the caller's.

    Args:
        ax: The first vector's x.
        ay: The first vector's y.
        az: The first vector's z.
        bx: The second vector's x.
        by: The second vector's y.
        bz: The second vector's z.

    Returns:
        The product's x, y, and z.
    """
    return (
        ay * bz - az * by,
        az * bx - ax * bz,
        ax * by - ay * bx,
    )


def widen_vector(value: Vector3) -> SIMD[DType.float64, 4]:
    """Return a vector in four `Float64` lanes.

    Products of finite `Float32` coordinates through degree five fit in
    `Float64`. The fourth lane is zero.

    Args:
        value: The vector.

    Returns:
        The widened vector.
    """
    return SIMD[DType.float64, 4](
        Float64(value.x), Float64(value.y), Float64(value.z), 0
    )


def wide_cross(
    a: SIMD[DType.float64, 4], b: SIMD[DType.float64, 4]
) -> SIMD[DType.float64, 4]:
    """Return the cross product of two widened vectors.

    Args:
        a: The first vector.
        b: The second vector.

    Returns:
        `a` crossed with `b`. The fourth lane is zero.
    """
    var x, y, z = cross_components[DType.float64](
        a[0], a[1], a[2], b[0], b[1], b[2]
    )
    return SIMD[DType.float64, 4](x, y, z, 0)


def wide_dot(a: SIMD[DType.float64, 4], b: SIMD[DType.float64, 4]) -> Float64:
    """Return the dot product of the first three lanes.

    The sum is `a.x b.x + a.y b.y + a.z b.z`, the order three.js uses.
    The fourth lane is left out.

    Args:
        a: The first vector.
        b: The second vector.

    Returns:
        The dot product.
    """
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
