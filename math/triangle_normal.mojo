# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Range-safe directions from three stored Float32 points.

Ordinary cross products keep their arithmetic when a product-error bound
controls the full direction. Difficult finite inputs use exact original
coordinate products. Widening only the edge differences is not sufficient:
a tiny coordinate can disappear beside a much larger coordinate.
"""

from math.matrix_determinant import _sum_products
from math.norm import _ordinary_squared
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
