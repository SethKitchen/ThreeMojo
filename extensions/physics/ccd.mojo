# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Analytic sphere and rotation-locked capsule sweeps against the front of
static triangles.

This module uses Float64 intermediates, not exact predicates. The world
opts in through a typed mode and checks its narrower supported domain.
Triangles have no adjacency data. Shared mesh edges can produce tilted
contacts during shallow overlap, as in the discrete solver. See the
continuous-collision wiki for the tessellated-floor limitation.
"""

from extensions.physics.shape import _wide, _wide_cross, _wide_dot
from math.triangle import Triangle
from std.math import sqrt


@fieldwise_init
struct CollisionDetection(Equatable, ImplicitlyCopyable, Writable):
    """Select discrete contacts or the supported sphere/capsule mesh sweep."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return whether this is a supported detection mode.

        Returns:
            True for either declared mode.
        """
        return self.value == 0 or self.value == 1


comptime DISCRETE = CollisionDetection(0)
comptime SPHERE_MESH_CCD = CollisionDetection(1)


@fieldwise_init
struct _SweepHit(ImplicitlyCopyable):
    var fraction: Float64
    var normal: SIMD[DType.float64, 4]


def _approaches(
    travel: SIMD[DType.float64, 4], normal: SIMD[DType.float64, 4]
) -> Bool:
    # A scale-relative dot-product roundoff bound, not a world-space skin.
    # Projection at a plastic impact can leave an unresolvable inward bit.
    var bound = Float64(0)
    for axis in range(3):  # pragma: no branch
        bound += abs(travel[axis] * normal[axis])
    return _wide_dot(travel, normal) < -bound * 7.105427357601002e-15


def _root(
    offset: SIMD[DType.float64, 4],
    travel: SIMD[DType.float64, 4],
    radius: Float64,
) -> Float64:
    # Enter a sphere or the perpendicular section of an edge cylinder.
    var a = _wide_dot(travel, travel)
    var b = _wide_dot(offset, travel)
    if a == 0 or b >= 0:
        return 2
    var c = _wide_dot(offset, offset) - radius * radius
    if c <= 0:
        return 0
    # Resolve the closest point before squaring its distance. Expanding
    # b*b-a*c loses the complete radius term on long, nearly axial paths.
    var closest = offset - travel * (b / a)
    var height = radius * radius - _wide_dot(closest, closest)
    if height <= 0:
        # A tangent has no inward velocity and needs no impulse.
        return 2
    # Conjugate form also avoids cancellation near the start of the path.
    return c / (-b + sqrt(a) * sqrt(height))


def _choose(
    start: SIMD[DType.float64, 4],
    travel: SIMD[DType.float64, 4],
    point: SIMD[DType.float64, 4],
    face: SIMD[DType.float64, 4],
    origin: SIMD[DType.float64, 4],
    fraction: Float64,
    best: _SweepHit,
) -> _SweepHit:
    if fraction < 0 or fraction > 1 or fraction >= best.fraction:
        return best
    var at = start + travel * fraction
    if _wide_dot(at - origin, face) < 0:
        return best
    var normal = at - point
    var length = sqrt(_wide_dot(normal, normal))
    if length == 0:
        return best
    normal /= length
    if not _approaches(travel, normal):
        return best
    return _SweepHit(fraction, normal)


def _sweep_domain(
    start: SIMD[DType.float64, 4],
    travel: SIMD[DType.float64, 4],
    radius: Float64,
    reach: Float64,
    triangle: Triangle,
) raises -> Bool:
    var a = _wide(triangle.a)
    var b = _wide(triangle.b)
    var c = _wide(triangle.c)
    for axis in range(3):  # pragma: no branch
        var end = start[axis] + travel[axis]
        if max(start[axis], end) + reach < min(
            a[axis], min(b[axis], c[axis])
        ) or min(start[axis], end) - reach > max(
            a[axis], max(b[axis], c[axis])
        ):
            return False
    for axis in range(3):  # pragma: no branch
        var extent = max(
            abs(a[axis] - start[axis]),
            max(abs(b[axis] - start[axis]), abs(c[axis] - start[axis])),
        )
        if extent > radius * 1048576:
            raise Error(
                "CCD nearby triangle exceeds the radius-relative precision"
                " bound"
            )
    return True


def _sweep_triangle(
    start: SIMD[DType.float64, 4],
    travel: SIMD[DType.float64, 4],
    radius: Float64,
    triangle: Triangle,
) raises -> _SweepHit:
    var best = _SweepHit(2, SIMD[DType.float64, 4](0))
    if not _sweep_domain(start, travel, radius, radius, triangle):
        return best
    var a = _wide(triangle.a)
    var b = _wide(triangle.b)
    var c = _wide(triangle.c)
    var normal = _wide_cross(b - a, c - a)
    var length = sqrt(_wide_dot(normal, normal))
    if length == 0:
        return best
    normal /= length
    var height = _wide_dot(start - a, normal)
    if height < 0:
        # The mesh remains one-sided. Never catch a body from its back.
        return best
    var speed = _wide_dot(travel, normal)
    if _approaches(travel, normal):
        var fraction = max((radius - height) / speed, Float64(0))
        if fraction <= 1:
            var at = start + travel * fraction
            var point = at - normal * _wide_dot(at - a, normal)
            if (
                _wide_dot(_wide_cross(b - a, point - a), normal) >= 0
                and _wide_dot(_wide_cross(c - b, point - b), normal) >= 0
                and _wide_dot(_wide_cross(a - c, point - c), normal) >= 0
            ):
                best = _SweepHit(fraction, normal)
    var vertices = [a, b, c]
    # The three cylinders and three vertices cover the rounded boundary.
    # Equal fractions retain the face, then edge/vertex insertion order.
    for i in range(3):  # pragma: no branch
        var p = vertices[i]
        var edge = vertices[(i + 1) % 3] - p
        var square = _wide_dot(edge, edge)
        # The nonzero triangle normal proves that this edge is nonzero.
        var offset = start - p
        var along = _wide_dot(offset, edge) / square
        var delta = _wide_dot(travel, edge) / square
        var fraction = _root(
            offset - edge * along, travel - edge * delta, radius
        )
        var coordinate = along + fraction * delta
        if coordinate >= 0 and coordinate <= 1:
            best = _choose(
                start,
                travel,
                p + edge * coordinate,
                normal,
                a,
                fraction,
                best,
            )
        best = _choose(
            start, travel, p, normal, a, _root(start - p, travel, radius), best
        )
    return best


def _segment_parameters(
    start: SIMD[DType.float64, 4],
    axis: SIMD[DType.float64, 4],
    point: SIMD[DType.float64, 4],
    edge: SIMD[DType.float64, 4],
    denominator: Float64,
) -> Tuple[Float64, Float64]:
    # Closest points of two nonparallel lines, start + u axis and
    # point + w edge. The denominator is |axis x edge|^2, which is not zero.
    var offset = start - point
    var aa = _wide_dot(axis, axis)
    var ae = _wide_dot(axis, edge)
    var ee = _wide_dot(edge, edge)
    var ao = _wide_dot(axis, offset)
    var eo = _wide_dot(edge, offset)
    return (
        (ae * eo - ee * ao) / denominator,
        (aa * eo - ae * ao) / denominator,
    )


def _sweep_capsule_triangle(
    start: SIMD[DType.float64, 4],
    end: SIMD[DType.float64, 4],
    travel: SIMD[DType.float64, 4],
    radius: Float64,
    triangle: Triangle,
) raises -> _SweepHit:
    # A capsule that only translates is the sphere of radius swept along
    # its segment. Its first contact with the front of a triangle is a cap
    # sphere on the triangle, the segment on an edge, or a vertex on the
    # segment's cylinder. The segment's interior reaches the face itself
    # only when it is parallel to it, and then all of it reaches the plane
    # at once: a cap over the face or an edge crossing reports that time.
    var best = _sweep_triangle(start, travel, radius, triangle)
    var cap = _sweep_triangle(end, travel, radius, triangle)
    if cap.fraction < best.fraction:
        best = cap
    var axis = end - start
    var length_sq = _wide_dot(axis, axis)
    if length_sq == 0:
        return best
    var middle = start + axis * 0.5
    if not _sweep_domain(
        middle, travel, radius, radius + 0.5 * sqrt(length_sq), triangle
    ):
        return best
    var a = _wide(triangle.a)
    var b = _wide(triangle.b)
    var c = _wide(triangle.c)
    var normal = _wide_cross(b - a, c - a)
    var length = sqrt(_wide_dot(normal, normal))
    if length == 0:
        return best
    normal /= length
    var vertices = [a, b, c]
    for i in range(3):  # pragma: no branch
        var p = vertices[i]
        var edge = vertices[(i + 1) % 3] - p
        # The segment's interior on this edge. Parallel lines meet first
        # at a cap or a vertex, which the other features cover.
        var cross = _wide_cross(axis, edge)
        var cross_sq = _wide_dot(cross, cross)
        if cross_sq > 0:
            var unit = cross / sqrt(cross_sq)
            var gap = _wide_dot(start - p, unit)
            var rate = _wide_dot(travel, unit)
            var fraction = Float64(2)
            if abs(gap) <= radius:
                fraction = 0
            elif gap * rate < 0:
                var target = radius if gap > 0 else -radius
                fraction = (target - gap) / rate
            if fraction <= 1:
                var at = start + travel * fraction
                var params = _segment_parameters(at, axis, p, edge, cross_sq)
                if (
                    min(params[0], params[1]) >= 0
                    and max(params[0], params[1]) <= 1
                ):
                    best = _choose(
                        start + axis * params[0],
                        travel,
                        p + edge * params[1],
                        normal,
                        a,
                        fraction,
                        best,
                    )
        # This vertex on the segment's cylinder. In the capsule's frame the
        # vertex moves by -travel.
        var offset = p - start
        var along = _wide_dot(offset, axis) / length_sq
        var delta = -_wide_dot(travel, axis) / length_sq
        var fraction = _root(
            offset - axis * along, -travel - axis * delta, radius
        )
        var coordinate = along + fraction * delta
        if coordinate >= 0 and coordinate <= 1:
            best = _choose(
                start + axis * coordinate,
                travel,
                p,
                normal,
                a,
                fraction,
                best,
            )
    return best
