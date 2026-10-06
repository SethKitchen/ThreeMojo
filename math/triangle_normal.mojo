# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Range-safe directions from three stored Float32 points.

Ordinary cross products keep their arithmetic when a product-error bound
controls the full direction. Difficult finite inputs use exact original
coordinate products. Widening only the edge differences is not sufficient:
a tiny coordinate can disappear beside a much larger coordinate.

## Numerical range correction

Finite norm-dependent directions and lengths use scale-safe arithmetic.
Extreme finite results can differ from direct three.js r180 arithmetic.
See `docs/wiki/Norm-consumers.md` for the changed operations, retained
limits, and explicit zero and nonfinite rules.
"""

from math.norm import _ordinary_squared, normalized3

from math.matrix_determinant import _sum_products
from math.vector3 import Vector3
from std.math import isfinite


def _finite_triangle(a: Vector3, b: Vector3, c: Vector3) -> Bool:
    """Check the finite-factor precondition of the coordinate expansion."""
    return (
        isfinite(a.x)
        and isfinite(a.y)
        and isfinite(a.z)
        and isfinite(b.x)
        and isfinite(b.y)
        and isfinite(b.z)
        and isfinite(c.x)
        and isfinite(c.y)
        and isfinite(c.z)
    )


def _coordinate_plane_through_origin(
    a: Vector3, b: Vector3, c: Vector3
) -> Bool:
    """Certify a zero determinant from one shared original zero coordinate.

    The caller has certified a finite nonzero cross. Computed zero dot or
    cross components alone do not establish this original-coordinate fact.
    """
    return (
        (a.x == 0 and b.x == 0 and c.x == 0)
        or (a.y == 0 and b.y == 0 and c.y == 0)
        or (a.z == 0 and b.z == 0 and c.z == 0)
    )


def _ordinary_triangle_cross(cb: Vector3, ab: Vector3, normal: Vector3) -> Bool:
    """Certify a well-conditioned Float32 cross before normalization.

    Let u=2**-24, M=max(abs(normal)), and P be the largest absolute
    two-product sum. Finite endpoint differences have relative error at
    most u; a subnormal difference is exact. A conservative 8u*P bound
    covers each cross-component error, including optional contraction.
    With P <= 4M the entire direction, not just its largest component,
    differs by less than 2**-17 after ordinary normalization. Underflow
    remainders are negligible because the squared norm must be normal.
    Overflowing products or differences cannot pass both checks.
    """
    if not _ordinary_squared(normal.dot(normal)):
        return False
    var products = max(
        abs(cb.y * ab.z) + abs(cb.z * ab.y),
        max(
            abs(cb.z * ab.x) + abs(cb.x * ab.z),
            abs(cb.x * ab.y) + abs(cb.y * ab.x),
        ),
    )
    var magnitude = max(abs(normal.x), max(abs(normal.y), abs(normal.z)))
    return products <= 4 * magnitude


@no_inline
def _triangle_cross_wide(
    a: Vector3, b: Vector3, c: Vector3
) -> SIMD[DType.float64, 4]:
    """Estimate the exact cross with exact sign and zero in each component.

    Inputs must be finite. The six coordinate products for each component
    are exact Float64 values. Their nonzero values are at least 2**-298
    and below 2**256. The shared expansion keeps all cancellation before
    estimating the sum. Its nonzero result cannot underflow or overflow
    Float64. The fourth component is zero.
    """
    var av = [Float64(a.x), Float64(a.y), Float64(a.z)]
    var bv = [Float64(b.x), Float64(b.y), Float64(b.z)]
    var cv = [Float64(c.x), Float64(c.y), Float64(c.z)]
    var normal = SIMD[DType.float64, 4](0)
    for axis in range(3):  # pragma: no branch
        var j = (axis + 1) % 3
        var k = (axis + 2) % 3
        var left = [cv[j], -cv[j], -bv[j], -cv[k], cv[k], bv[k]]
        var right = [av[k], bv[k], av[k], av[j], bv[j], av[j]]
        normal[axis] = _sum_products[6](left, right)
    return normal


def normal_or_zero(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
    """Return a finite triangle's unit normal without losing its cross.

    Args:
        a: The first stored point.
        b: The second stored point.
        c: The third stored point.

    Returns:
        The counterclockwise unit normal, or zero for a degenerate face.
        Nonfinite points retain direct cross and normalization behavior.
    """
    var first = b - a
    var second = c - a
    var normal = first
    normal.cross(second)
    if not _ordinary_triangle_cross(first, second, normal) and _finite_triangle(
        a, b, c
    ):
        var wide = _triangle_cross_wide(a, b, c)
        var unit = normalized3(wide[0], wide[1], wide[2])
        return Vector3(Float32(unit[0]), Float32(unit[1]), Float32(unit[2]))
    normal.normalize()
    return normal


def _add_exact(mut expansion: List[Float64], value: Float64):
    """Add an exact finite coordinate product with error-free TwoSum."""
    var total = value
    var parts = List[Float64](capacity=len(expansion) + 1)
    for part in expansion:
        var next = total + part
        var virtual = next - total
        var error = (total - (next - virtual)) + (part - virtual)
        if error != 0:
            parts.append(error)
        total = next
    if total != 0:
        parts.append(total)
    expansion = parts^


def _polygon_cross_wide(points: List[Vector3]) -> SIMD[DType.float64, 4]:
    """Sum original Float32 polygon coordinate products without cancellation."""
    var result = SIMD[DType.float64, 4](0)
    for axis in range(3):  # pragma: no branch
        var j = (axis + 1) % 3
        var k = (axis + 2) % 3
        var expansion = List[Float64]()
        for index in range(len(points)):
            var a = points[index]
            var b = points[(index + 1) % len(points)]
            var av = [Float64(a.x), Float64(a.y), Float64(a.z)]
            var bv = [Float64(b.x), Float64(b.y), Float64(b.z)]
            _add_exact(expansion, av[j] * bv[k])
            _add_exact(expansion, -av[k] * bv[j])
        for part in expansion:
            result[axis] += part
    return result


def _difference_product_wide(
    a: Float64, b: Float64, c: Float64, x: Float64, y: Float64, z: Float64
) -> Float64:
    """Return (b-a)(z-x)-(c-a)(y-x) from original finite coordinates.

    The coordinate products must fit normal Float64. All stored Float32
    coordinates, including subnormals, satisfy this precondition.
    """
    return _sum_products[6]([b, -b, -a, -c, c, a], [z, x, z, y, x, y])


def polygon_normal(points: List[Vector3]) -> Vector3:
    """Return a polygon's unit Newell normal, with a wide range fallback.

    Args:
        points: The ordered finite Float32 corners.

    Returns:
        The unit Newell normal, or zero for no oriented area. Ordinary
        values keep their Float32 sums. Nonfinite coordinates retain
        direct IEEE results.
    """
    var normal = Vector3(0, 0, 0)
    var finite = True
    for index in range(len(points)):
        var a = points[index]
        var b = points[(index + 1) % len(points)]
        normal.x += (a.y - b.y) * (a.z + b.z)
        normal.y += (a.z - b.z) * (a.x + b.x)
        normal.z += (a.x - b.x) * (a.y + b.y)
        finite = finite and isfinite(a.x) and isfinite(a.y) and isfinite(a.z)
    if not finite:
        normal.normalize()
        return normal
    var wide = _polygon_cross_wide(points)
    var scale = max(abs(wide[0]), max(abs(wide[1]), abs(wide[2])))
    if (
        _ordinary_squared(normal.length_sq())
        and abs(Float64(normal.x) - wide[0]) <= scale * 1e-6
        and abs(Float64(normal.y) - wide[1]) <= scale * 1e-6
        and abs(Float64(normal.z) - wide[2]) <= scale * 1e-6
    ):
        normal.normalize()
        return normal
    var unit = normalized3(wide[0], wide[1], wide[2])
    return Vector3(Float32(unit[0]), Float32(unit[1]), Float32(unit[2]))
