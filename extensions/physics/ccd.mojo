# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Analytic sphere and rotation-locked capsule sweeps against the front of
static triangles, and the geometry of conservative advancement for turning
and coupled bodies: convex cores, their clearance and clear time, contact
points, and the plastic contact solver.

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
    return _contact_root[False](offset, travel, radius)


def _contact_root[
    initial_only: Bool
](
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

    comptime if initial_only:
        return 2
    else:
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
    return _triangle_geometry[False](start, travel, radius, triangle)


def _triangle_geometry[
    initial_only: Bool
](
    start: SIMD[DType.float64, 4],
    travel: SIMD[DType.float64, 4],
    radius: Float64,
    triangle: Triangle,
) -> _SweepHit:
    # The initial-only lookup is internal to a previously validated hit.
    # It uses incoming travel only as a direction, with no future search.
    var best = _SweepHit(2, SIMD[DType.float64, 4](0))
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
        var fraction = Float64(2)

        comptime if initial_only:
            if height <= radius:
                fraction = 0
        else:
            fraction = max((radius - height) / speed, Float64(0))
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
        var fraction = _contact_root[initial_only](
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
            start,
            travel,
            p,
            normal,
            a,
            _contact_root[initial_only](start - p, travel, radius),
            best,
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
    return _capsule_geometry[False](start, end, travel, radius, triangle)


def _initial_triangle_contact(
    start: SIMD[DType.float64, 4],
    incoming: SIMD[DType.float64, 4],
    radius: Float64,
    triangle: Triangle,
) -> _SweepHit:
    return _triangle_geometry[True](start, incoming, radius, triangle)


def _initial_capsule_contact(
    start: SIMD[DType.float64, 4],
    end: SIMD[DType.float64, 4],
    incoming: SIMD[DType.float64, 4],
    radius: Float64,
    triangle: Triangle,
) raises -> _SweepHit:
    return _capsule_geometry[True](start, end, incoming, radius, triangle)


def _capsule_geometry[
    initial_only: Bool
](
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
    var best: _SweepHit
    var cap: _SweepHit

    comptime if initial_only:
        best = _triangle_geometry[True](start, travel, radius, triangle)
        cap = _triangle_geometry[True](end, travel, radius, triangle)
    else:
        best = _sweep_triangle(start, travel, radius, triangle)
        cap = _sweep_triangle(end, travel, radius, triangle)
    if cap.fraction < best.fraction:
        best = cap
    var axis = end - start
    var length_sq = _wide_dot(axis, axis)
    if length_sq == 0:
        return best

    comptime if not initial_only:
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
    if _wide_dot(start - a, normal) < 0 and _wide_dot(end - a, normal) < 0:
        # The mesh remains one-sided. A capsule wholly behind the face
        # never reaches its front, as each cap sweep already reports.
        return best
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
            else:
                comptime if not initial_only:
                    if gap * rate < 0:
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
        var fraction = _contact_root[initial_only](
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


def _point_hit(
    best: _SweepHit,
    point: SIMD[DType.float64, 4],
    travel: SIMD[DType.float64, 4],
    other: SIMD[DType.float64, 4],
    fraction: Float64,
    flip: Bool,
) -> _SweepHit:
    # Keep an earlier approaching contact of `point`, moving by `travel`,
    # with the fixed point `other`. The normal runs from `other` to the
    # moving point, or the other way when `flip` is set.
    if fraction > 1 or fraction >= best.fraction:
        return best
    var normal = point + travel * fraction - other
    # A contact point lies the summed radius from the other one.
    normal /= sqrt(_wide_dot(normal, normal))
    if not _approaches(travel, normal):
        return best
    return _SweepHit(fraction, -normal if flip else normal)


def _point_segment(
    best: _SweepHit,
    point: SIMD[DType.float64, 4],
    travel: SIMD[DType.float64, 4],
    start: SIMD[DType.float64, 4],
    axis: SIMD[DType.float64, 4],
    radius: Float64,
    flip: Bool,
) -> _SweepHit:
    # A point moving by `travel` against the segment start + u axis, u in
    # [0, 1], grown by `radius`: its two end spheres and, for a segment
    # of some length, its cylinder.
    var found = _point_hit(
        best, point, travel, start, _root(point - start, travel, radius), flip
    )
    var square = _wide_dot(axis, axis)
    if square == 0:
        return found
    var end = start + axis
    found = _point_hit(
        found, point, travel, end, _root(point - end, travel, radius), flip
    )
    var offset = point - start
    var along = _wide_dot(offset, axis) / square
    var delta = _wide_dot(travel, axis) / square
    var fraction = _root(offset - axis * along, travel - axis * delta, radius)
    var coordinate = along + fraction * delta
    if coordinate >= 0 and coordinate <= 1:
        found = _point_hit(
            found, point, travel, start + axis * coordinate, fraction, flip
        )
    return found


def _sweep_segments(
    a: SIMD[DType.float64, 4],
    a_axis: SIMD[DType.float64, 4],
    b: SIMD[DType.float64, 4],
    b_axis: SIMD[DType.float64, 4],
    travel: SIMD[DType.float64, 4],
    radius: Float64,
) -> _SweepHit:
    """Sweep segment A, moving by `travel`, against fixed segment B.

    Each segment is a start and an axis to its other end; an axis of zero
    is a sphere's center. The contact distance is `radius`, the two shapes'
    radii summed. Two capsules that only translate first touch at an end
    of one against the other, or at their interiors. The normal runs from
    B toward A.

    Args:
        a: The start of segment A.
        a_axis: From A's start to its other end.
        b: The start of segment B.
        b_axis: From B's start to its other end.
        travel: A's motion relative to B over the interval.
        radius: The summed radii.

    Returns:
        The earliest approaching contact, or the fraction 2 for none.
    """
    var best = _SweepHit(2, SIMD[DType.float64, 4](0))
    # Each end of A against B, then each end of B against A, where B
    # moves by -travel. Those normals run from A, so they are flipped.
    best = _point_segment(best, a, travel, b, b_axis, radius, False)
    best = _point_segment(best, a + a_axis, travel, b, b_axis, radius, False)
    best = _point_segment(best, b, -travel, a, a_axis, radius, True)
    best = _point_segment(best, b + b_axis, -travel, a, a_axis, radius, True)
    # The interiors meet across the plane that both axes span. Parallel
    # axes meet first at an end, which the cases above cover.
    var cross = _wide_cross(a_axis, b_axis)
    var cross_sq = _wide_dot(cross, cross)
    if cross_sq == 0:
        return best
    var unit = cross / sqrt(cross_sq)
    var gap = _wide_dot(a - b, unit)
    var rate = _wide_dot(travel, unit)
    var fraction = Float64(2)
    if abs(gap) <= radius:
        fraction = 0
    elif gap * rate < 0:
        var target = radius if gap > 0 else -radius
        fraction = (target - gap) / rate
    if fraction > 1:
        return best
    var at = a + travel * fraction
    var params = _segment_parameters(at, a_axis, b, b_axis, cross_sq)
    if min(params[0], params[1]) < 0 or max(params[0], params[1]) > 1:
        return best
    return _point_hit(
        best,
        a + a_axis * params[0],
        travel,
        b + b_axis * params[1],
        fraction,
        False,
    )


def _segment_gap(
    a: SIMD[DType.float64, 4],
    a_axis: SIMD[DType.float64, 4],
    b: SIMD[DType.float64, 4],
    b_axis: SIMD[DType.float64, 4],
) -> Tuple[Float64, SIMD[DType.float64, 4], Float64]:
    """Return the distance between two segments, the unit normal from B
    toward A at their closest points, and A's parameter there.

    Ericson's clamped closest points of two segments, where either can be
    a single point.

    Args:
        a: The start of segment A.
        a_axis: From A's start to its other end.
        b: The start of segment B.
        b_axis: From B's start to its other end.

    Returns:
        The distance, the normal, and the parameter in [0, 1] of A's
        closest point. The normal is zero when they meet.
    """
    var r = a - b
    var aa = _wide_dot(a_axis, a_axis)
    var bb = _wide_dot(b_axis, b_axis)
    var f = _wide_dot(b_axis, r)
    var s = Float64(0)
    var t = Float64(0)
    if aa == 0 and bb > 0:
        t = min(max(f / bb, Float64(0)), Float64(1))
    elif aa > 0:
        var c = _wide_dot(a_axis, r)
        if bb == 0:
            s = min(max(-c / aa, Float64(0)), Float64(1))
        else:
            var ab = _wide_dot(a_axis, b_axis)
            var denominator = aa * bb - ab * ab
            if denominator > 0:
                s = min(
                    max((ab * f - c * bb) / denominator, Float64(0)), Float64(1)
                )
            t = (ab * s + f) / bb
            if t < 0:
                t = 0
                s = min(max(-c / aa, Float64(0)), Float64(1))
            elif t > 1:
                t = 1
                s = min(max((ab - c) / aa, Float64(0)), Float64(1))
    var gap = a + a_axis * s - (b + b_axis * t)
    var distance = sqrt(_wide_dot(gap, gap))
    if distance == 0:
        return (distance, SIMD[DType.float64, 4](0), s)
    return (distance, gap / distance, s)


def _on_segment(
    p: SIMD[DType.float64, 4],
    x: SIMD[DType.float64, 4],
    edge: SIMD[DType.float64, 4],
) -> SIMD[DType.float64, 4]:
    # The point of segment x + u edge, u in [0, 1], closest to p.
    var u = _wide_dot(p - x, edge) / _wide_dot(edge, edge)
    return x + edge * min(max(u, Float64(0)), Float64(1))


def _triangle_closest(
    p: SIMD[DType.float64, 4],
    a: SIMD[DType.float64, 4],
    b: SIMD[DType.float64, 4],
    c: SIMD[DType.float64, 4],
) -> SIMD[DType.float64, 4]:
    """Return the point of triangle abc closest to p.

    The projection onto the plane when it falls inside the triangle, and
    otherwise the nearest point of the three edges.

    Args:
        p: The point.
        a: A corner.
        b: A corner.
        c: A corner. The triangle's normal must not be zero.

    Returns:
        The closest point.
    """
    var normal = _wide_cross(b - a, c - a)
    var flat = p - normal * (
        _wide_dot(p - a, normal) / _wide_dot(normal, normal)
    )
    if (
        _wide_dot(_wide_cross(b - a, flat - a), normal) >= 0
        and _wide_dot(_wide_cross(c - b, flat - b), normal) >= 0
        and _wide_dot(_wide_cross(a - c, flat - c), normal) >= 0
    ):
        return flat
    var best = _on_segment(p, a, b - a)
    for edge in [(b, c - b), (c, a - c)]:  # pragma: no branch
        var other = _on_segment(p, edge[0], edge[1])
        if _wide_dot(p - other, p - other) < _wide_dot(p - best, p - best):
            best = other
    return best


def _segment_triangle_gap(
    start: SIMD[DType.float64, 4],
    axis: SIMD[DType.float64, 4],
    triangle: Triangle,
) -> Tuple[Float64, SIMD[DType.float64, 4], SIMD[DType.float64, 4]]:
    """Return the distance from a segment to a triangle, the unit normal
    from the triangle toward the segment, and the segment's closest point.

    The closest pair is an end of the segment against the triangle, the
    segment against an edge, or a crossing of the face. A crossing has
    distance zero and the face normal. Equal distances keep that order.

    Args:
        start: One end of the segment; an axis of zero is a point.
        axis: From that end to the other.
        triangle: The triangle, with a nonzero normal.

    Returns:
        The distance, the normal and the point on the segment.
    """
    var a = _wide(triangle.a)
    var b = _wide(triangle.b)
    var c = _wide(triangle.c)
    var face = _wide_cross(b - a, c - a)
    face /= sqrt(_wide_dot(face, face))
    var best = Float64(1e300)
    var normal = face
    var point = start
    for end in range(2):  # pragma: no branch
        var p = start + axis * Float64(end)
        var gap = p - _triangle_closest(p, a, b, c)
        var distance = sqrt(_wide_dot(gap, gap))
        if distance < best:
            best = distance
            normal = gap / distance if distance > 0 else face
            point = p
    var corners = [a, b, c]
    for i in range(3):  # pragma: no branch
        var edge = _segment_gap(
            start, axis, corners[i], corners[(i + 1) % 3] - corners[i]
        )
        if edge[0] < best:
            best = edge[0]
            # A segment that touches the edge line has no gap direction.
            normal = edge[1] if edge[0] > 0 else face
            point = start + axis * edge[2]
    var low = _wide_dot(start - a, face)
    var high = _wide_dot(start + axis - a, face)
    if low * high < 0:
        var crossing = start + axis * (low / (low - high))
        if (
            _wide_dot(_wide_cross(b - a, crossing - a), face) >= 0
            and _wide_dot(_wide_cross(c - b, crossing - b), face) >= 0
            and _wide_dot(_wide_cross(a - c, crossing - c), face) >= 0
        ):
            return (Float64(0), face, crossing)
    return (best, normal, point)


def _turning_step(
    ends: Tuple[SIMD[DType.float64, 4], SIMD[DType.float64, 4]],
    speeds: Tuple[SIMD[DType.float64, 4], SIMD[DType.float64, 4]],
    radius: Float64,
    tolerance: Float64,
    curvature: Float64,
    triangle: Triangle,
) -> Float64:
    """Return how long a turning segment stays clear of a triangle.

    The segment's ends move at `speeds` now. Every point of the true rigid
    path stays within curvature * t^2 / 2 of its straight-line path, so a
    separating plane's distance to the true segment is at least its
    distance to the straight-line ends less that. The best separating
    plane is the face or one of the three edge side planes. The result is
    the first time its bound reaches -`tolerance` below `radius`.

    Args:
        ends: The segment's two ends; equal ends are a point.
        speeds: The two ends' velocities.
        radius: The shape's radius about the segment.
        tolerance: The overlap the bound may allow.
        curvature: |omega|^2 times the larger lever from the mass center.
        triangle: The triangle, with a nonzero normal.

    Returns:
        The time, 1e300 for no limit, or -1 when the segment is wholly
        behind the face. A segment that already overlaps may deepen by the
        tolerance at most.
    """
    var a = _wide(triangle.a)
    var b = _wide(triangle.b)
    var c = _wide(triangle.c)
    var face = _wide_cross(b - a, c - a)
    face /= sqrt(_wide_dot(face, face))
    if _wide_dot(ends[0] - a, face) < 0 and _wide_dot(ends[1] - a, face) < 0:
        # The mesh stays one-sided.
        return -1
    # Each plane is a unit normal and a point on it.
    var normals = List[SIMD[DType.float64, 4]]()
    var origins = List[SIMD[DType.float64, 4]]()
    normals.append(face)
    origins.append(a)
    var corners = [a, b, c]
    for i in range(3):  # pragma: no branch
        var side = _wide_cross(corners[(i + 1) % 3] - corners[i], face)
        normals.append(side / sqrt(_wide_dot(side, side)))
        origins.append(corners[i])
    # The plane that separates the segment most now.
    var chosen = 0
    var most = Float64(-1e300)
    for k in range(4):  # pragma: no branch
        var low = min(
            _wide_dot(ends[0] - origins[k], normals[k]),
            _wide_dot(ends[1] - origins[k], normals[k]),
        )
        if low > most:
            most = low
            chosen = k
    # A shape that already overlaps keeps its current depth, plus the
    # tolerance; the caller's impact test opens a closing contact.
    var allowance = tolerance + max(radius - most, Float64(0))
    var limit = Float64(1e300)
    var tips = [ends[0], ends[1]]
    var moving = [speeds[0], speeds[1]]
    for end in range(2):  # pragma: no branch
        var room = (
            _wide_dot(tips[end] - origins[chosen], normals[chosen])
            - radius
            + allowance
        )
        var rate = _wide_dot(moving[end], normals[chosen])
        # The first positive root of room + rate t - curvature t^2 / 2.
        if curvature > 0:
            var root = sqrt(rate * rate + 2 * curvature * room)
            # Rationalize the closing root: when curvature is tiny, root
            # rounds to -rate and their direct sum loses all progress.
            var time = (
                2 * room / (root - rate) if rate
                < 0 else (rate + root) / curvature
            )
            limit = min(limit, time)
        elif rate < 0:
            limit = min(limit, room / -rate)
    return limit


def _project(
    points: List[SIMD[DType.float64, 4]], axis: SIMD[DType.float64, 4]
) -> Tuple[Float64, Float64]:
    # The interval that points cover along an axis.
    var low = _wide_dot(points[0], axis)
    var high = low
    # A triangle or a solid has three points at least.
    for k in range(1, len(points)):  # pragma: no branch
        var value = _wide_dot(points[k], axis)
        low = min(low, value)
        high = max(high, value)
    return (low, high)


def _sweep_convex_triangle(
    vertices: List[SIMD[DType.float64, 4]],
    faces: List[SIMD[DType.float64, 4]],
    edges: List[SIMD[DType.float64, 4]],
    travel: SIMD[DType.float64, 4],
    triangle: Triangle,
) -> _SweepHit:
    """Sweep a translating convex solid against the front of a triangle.

    The separating-axis test over time: the solid and the triangle overlap
    exactly when their projections overlap on every candidate axis. These
    are the solid's face normals, the triangle's normal, and each cross
    product of a solid edge with a triangle edge. Along each axis the
    solid's interval moves linearly, so it overlaps during one interval of
    time. The first contact is the latest entry, when it comes before the
    earliest exit. Its normal is the axis that entered last; a solid that
    already overlaps uses the axis of least overlap instead. An axis that
    the solid does not move along, and on which it only touches the
    triangle, separates them for the whole interval.

    Args:
        vertices: The solid's corners at the start, in the world.
        faces: The solid's unit face normals.
        edges: The solid's edge directions.
        travel: The solid's motion over the interval.
        triangle: The triangle, with a nonzero normal.

    Returns:
        The earliest approaching contact, or the fraction 2 for none.
    """
    var miss = _SweepHit(2, SIMD[DType.float64, 4](0))
    var a = _wide(triangle.a)
    var b = _wide(triangle.b)
    var c = _wide(triangle.c)
    var face = _wide_cross(b - a, c - a)
    face /= sqrt(_wide_dot(face, face))
    if _project(vertices, face)[1] < _wide_dot(a, face):
        # The mesh stays one-sided: a solid wholly behind is not caught.
        return miss
    var corners = List[SIMD[DType.float64, 4]]()
    corners.append(a)
    corners.append(b)
    corners.append(c)
    var axes = faces.copy()
    axes.append(face)
    for edge in edges:  # pragma: no branch
        for k in range(3):  # pragma: no branch
            axes.append(_wide_cross(edge, corners[(k + 1) % 3] - corners[k]))
    var entry = Float64(-1e300)
    var leave = Float64(1e300)
    var normal = SIMD[DType.float64, 4](0)
    # The axis of least overlap now, and the way it separates the solid.
    var depth = Float64(1e300)
    var shallow = SIMD[DType.float64, 4](0)
    for axis in axes:  # pragma: no branch
        var square = _wide_dot(axis, axis)
        if square == 0:
            # Parallel edges give no axis.
            continue
        var unit = axis / sqrt(square)
        var solid = _project(vertices, unit)
        var flat = _project(corners, unit)
        var up = flat[1] - solid[0]
        var down = solid[1] - flat[0]
        if min(up, down) < depth:
            depth = min(up, down)
            shallow = unit if up < down else -unit
        var rate = _wide_dot(travel, unit)
        if rate == 0:
            # An axis the solid does not move along separates it for the
            # whole interval, even when the two only touch: a face or edge
            # that slides along the triangle at zero clearance never
            # enters it.
            if solid[1] <= flat[0] or solid[0] >= flat[1]:
                return miss
            continue
        # The solid's interval reaches the triangle's at `first` and
        # passes it at `last`.
        var first = (flat[0] - solid[1]) / rate
        var last = (flat[1] - solid[0]) / rate
        if rate < 0:
            first = (flat[1] - solid[0]) / rate
            last = (flat[0] - solid[1]) / rate
        if first > entry:
            entry = first
            # From the triangle toward the solid, against its motion.
            normal = -unit if rate > 0 else unit
        leave = min(leave, last)
    if entry == -1e300 or entry > leave or entry > 1 or leave < 0:
        return miss
    if entry <= 0:
        # Already touching or overlapping: every entry is past, and the
        # contact pushes out along the axis of least overlap.
        normal = shallow
    if not _approaches(travel, normal):
        return miss
    return _SweepHit(max(entry, Float64(0)), normal)


@fieldwise_init
struct _Core(Copyable, Movable):
    """A convex shape: the hull of its points, grown by a radius.

    A sphere has one point and a capsule two. A box, a hull or a triangle
    has its corners, its faces as unit normals with corner lists, counter-
    clockwise seen from outside, and its edges as corner pairs. Over a
    sub-step each point moves at its own velocity. The rigid path leaves
    that line by at most bend t^2 / 2, in the plane across the unit spin
    axis `axis`. A triangle has one face and no motion. `face_axes` and
    `edge_axes` name the faces and edges whose directions differ from
    every earlier one's, up to sign: the separating-axis test needs only
    those.
    """

    var points: List[SIMD[DType.float64, 4]]
    var speeds: List[SIMD[DType.float64, 4]]
    var radius: Float64
    var normals: List[SIMD[DType.float64, 4]]
    var face_start: List[Int]
    var face_corners: List[Int]
    var edge_a: List[Int]
    var edge_b: List[Int]
    var bend: Float64
    var axis: SIMD[DType.float64, 4]
    var face_axes: List[Int]
    var edge_axes: List[Int]


def _triangle_core(triangle: Triangle) -> _Core:
    # The triangle's front normal; validated triangles have one.
    var a = _wide(triangle.a)
    var b = _wide(triangle.b)
    var c = _wide(triangle.c)
    var face = _wide_cross(b - a, c - a)
    var none = SIMD[DType.float64, 4](0)
    return _Core(
        [a, b, c],
        [none, none, none],
        0,
        [face / sqrt(_wide_dot(face, face))],
        [0, 3],
        [0, 1, 2],
        [0, 1, 2],
        [1, 2, 0],
        0,
        none,
        [0],
        [0, 1, 2],
    )


def _distinct(directions: List[SIMD[DType.float64, 4]]) -> List[Int]:
    """Return the indices of directions not parallel to an earlier one.

    Two directions are parallel when their cross product is below 1e-9 of
    the product of their lengths. Opposite directions are parallel.

    Args:
        directions: The nonzero directions.

    Returns:
        The indices, in order.
    """
    var out = List[Int]()
    for i in range(len(directions)):  # pragma: no branch
        var fresh = True
        for j in out:
            var cross = _wide_cross(directions[i], directions[j])
            if _wide_dot(cross, cross) <= 1e-18 * _wide_dot(
                directions[i], directions[i]
            ) * _wide_dot(directions[j], directions[j]):
                fresh = False
                break
        if fresh:
            out.append(i)
    return out^


def _over_face(p: SIMD[DType.float64, 4], core: _Core, f: Int) -> Bool:
    # Whether p projects onto face f, a convex polygon, along its normal.
    var normal = core.normals[f]
    var first = core.face_start[f]
    var count = core.face_start[f + 1] - first
    for k in range(count):  # pragma: no branch
        var a = core.points[core.face_corners[first + k]]
        var b = core.points[core.face_corners[first + (k + 1) % count]]
        if _wide_dot(_wide_cross(b - a, p - a), normal) < 0:
            return False
    return True


def _polygon_point(
    p: SIMD[DType.float64, 4], core: _Core, f: Int
) -> SIMD[DType.float64, 4]:
    # The point of face f, a convex polygon, closest to p.
    var normal = core.normals[f]
    var first = core.face_start[f]
    var count = core.face_start[f + 1] - first
    var origin = core.points[core.face_corners[first]]
    var flat = p - normal * _wide_dot(p - origin, normal)
    if _over_face(p, core, f):
        return flat
    var best = flat
    var distance = Float64(1e300)
    for k in range(count):  # pragma: no branch
        var a = core.points[core.face_corners[first + k]]
        var b = core.points[core.face_corners[first + (k + 1) % count]]
        var at = _on_segment(p, a, b - a)
        var square = _wide_dot(p - at, p - at)
        if square < distance:
            distance = square
            best = at
    return best


def _hull_distance(p: SIMD[DType.float64, 4], core: _Core) -> Float64:
    """Return a distance from a point to a core's hull, radius excluded.

    A triangle gives the exact distance, negative for a point behind its
    face that projects onto it. A solid gives the largest signed
    face-plane distance, which is negative inside and at most the true
    distance outside. A sphere or capsule gives the exact distance to its
    point or segment.

    Args:
        p: The point.
        core: The shape.

    Returns:
        The distance, in meters.
    """
    if len(core.normals) == 1:
        if _over_face(p, core, 0):
            return _wide_dot(p - core.points[0], core.normals[0])
        var gap = p - _polygon_point(p, core, 0)
        return sqrt(_wide_dot(gap, gap))
    if len(core.normals) > 1:
        var most = Float64(-1e300)
        for f in range(len(core.normals)):  # pragma: no branch
            var origin = core.points[core.face_corners[core.face_start[f]]]
            most = max(most, _wide_dot(p - origin, core.normals[f]))
        return most
    var start = core.points[0]
    var axis = core.points[len(core.points) - 1] - start
    var at = start
    if _wide_dot(axis, axis) > 0:
        at = _on_segment(p, start, axis)
    return sqrt(_wide_dot(p - at, p - at))


def _separate(
    x: _Core,
    y: _Core,
    axis: SIMD[DType.float64, 4],
    mut best: Float64,
    mut normal: SIMD[DType.float64, 4],
):
    # Keep this axis, either way along it, when it separates the hulls
    # more than the best so far. Parallel edges give no axis.
    var square = _wide_dot(axis, axis)
    if square == 0:
        return
    var unit = axis / sqrt(square)
    var mine = _project(x.points, unit)
    var theirs = _project(y.points, unit)
    if mine[0] - theirs[1] > best:
        best = mine[0] - theirs[1]
        normal = unit
    if theirs[0] - mine[1] > best:
        best = theirs[0] - mine[1]
        normal = -unit


def _core_gap(
    x: _Core, y: _Core, near: Float64
) raises -> Tuple[Float64, SIMD[DType.float64, 4]]:
    """Return the clearance of two cores and the unit normal from y to x.

    Two round shapes use the closest points of their segments. Otherwise
    the separating-axis test runs over each face normal, each cross
    product of an edge of x with an edge of y, and, for a triangle y, its
    side normals and each edge of x crossed with its face. These axes are
    complete for every pair this module forms. A positive axis proves the
    hulls apart, and the exact distance then comes from each corner
    against each face polygon of the other and each edge pair, when the
    axis leaves at most `near` of clearance. A wider axis clearance is
    kept as a lower bound. Otherwise the axis of least overlap gives a
    negative clearance.

    Args:
        x: The first shape, a moving body.
        y: The second shape, a moving body or a triangle.
        near: The axis clearance below which the exact distance is found.

    Returns:
        The clearance, which is the hull distance less both radii, and the
        normal.

    Raises:
        Error: If two round shapes overlap past their segments.
    """
    var radii = x.radius + y.radius
    if len(x.normals) == 0 and len(y.normals) == 0:
        var gap = _segment_gap(
            x.points[0],
            x.points[len(x.points) - 1] - x.points[0],
            y.points[0],
            y.points[len(y.points) - 1] - y.points[0],
        )
        if gap[0] == 0:
            raise Error(
                "CCD round shapes overlap past their axes; step rolled back"
            )
        return (gap[0] - radii, gap[1])
    var best = Float64(-1e300)
    var normal = SIMD[DType.float64, 4](0)
    for f in x.face_axes:
        _separate(x, y, x.normals[f], best, normal)
    for f in y.face_axes:
        _separate(x, y, y.normals[f], best, normal)
    for e in x.edge_axes:
        var edge = x.points[x.edge_b[e]] - x.points[x.edge_a[e]]
        for g in y.edge_axes:
            _separate(
                x,
                y,
                _wide_cross(
                    edge, y.points[y.edge_b[g]] - y.points[y.edge_a[g]]
                ),
                best,
                normal,
            )
        if len(y.normals) == 1:
            _separate(x, y, _wide_cross(edge, y.normals[0]), best, normal)
    if len(y.normals) == 1:
        for g in range(3):  # pragma: no branch
            _separate(
                x,
                y,
                _wide_cross(
                    y.points[y.edge_b[g]] - y.points[y.edge_a[g]], y.normals[0]
                ),
                best,
                normal,
            )
    if best <= 0 or best - radii > near:
        return (best - radii, normal)
    # Apart: each closest pair is a corner on a face or two edges.
    var distance = Float64(1e300)
    for p in x.points:  # pragma: no branch
        for f in range(len(y.normals)):
            var gap = p - _polygon_point(p, y, f)
            var length = sqrt(_wide_dot(gap, gap))
            if length < distance:
                distance = length
                normal = gap / length
    for q in y.points:  # pragma: no branch
        for f in range(len(x.normals)):
            var gap = _polygon_point(q, x, f) - q
            var length = sqrt(_wide_dot(gap, gap))
            if length < distance:
                distance = length
                normal = gap / length
    for e in range(len(x.edge_a)):
        for g in range(len(y.edge_a)):
            var pair = _segment_gap(
                x.points[x.edge_a[e]],
                x.points[x.edge_b[e]] - x.points[x.edge_a[e]],
                y.points[y.edge_a[g]],
                y.points[y.edge_b[g]] - y.points[y.edge_a[g]],
            )
            if pair[0] < distance:
                distance = pair[0]
                normal = pair[1]
    return (distance - radii, normal)


def _bend_along(core: _Core, normal: SIMD[DType.float64, 4]) -> Float64:
    # A rigid point's path bends across the spin axis only, so its deviation
    # along the normal is at most bend times the normal's part across it.
    var across = normal - core.axis * _wide_dot(normal, core.axis)
    return core.bend * sqrt(_wide_dot(across, across)) * 1.000000000000001


def _first_root(room: Float64, rate: Float64, curvature: Float64) -> Float64:
    # The first positive root of room + rate t - curvature t^2 / 2, for a
    # positive room, or 1e300 when it never reaches zero.
    if curvature > 0:
        var root = sqrt(rate * rate + 2 * curvature * room)
        # The rationalized closing root keeps progress for tiny curvature.
        if rate < 0:
            return 2 * room / (root - rate)
        return (rate + root) / curvature
    if rate < 0:
        return room / -rate
    return 1e300


def _core_clear(
    x: _Core,
    y: _Core,
    clearance: Float64,
    normal: SIMD[DType.float64, 4],
    tolerance: Float64,
) -> Float64:
    """Return how long two moving cores stay clear along a fixed normal.

    Along a fixed unit normal, the hulls' separation is the least gap of a
    point of x over a point of y. Each point moves on its straight line
    within its core's bend, so each pair's gap is at least its linear gap
    less the summed bends times t^2 / 2. For shapes apart by more than
    the tolerance, the result is the first time that bound reaches zero.
    For shapes within the tolerance, it is the first time the bound
    reaches the tolerance below zero, or below the present clearance when
    the shapes overlap.

    Args:
        x: The first shape.
        y: The second shape.
        clearance: Their clearance from `_core_gap`.
        normal: Its normal, from y to x.
        tolerance: The deepening that the bound may allow.

    Returns:
        The time, or 1e300 for no limit.
    """
    # Apart, the bound aims at contact itself; touching within the
    # tolerance, it may deepen by the tolerance, so a sliding contact
    # still advances.
    var allowance = Float64(0)
    if clearance <= tolerance:
        allowance = tolerance + max(-clearance, Float64(0))
    var radii = x.radius + y.radius
    var curvature = _bend_along(x, normal) + _bend_along(y, normal)
    var limit = Float64(1e300)
    for p in range(len(x.points)):  # pragma: no branch
        for q in range(len(y.points)):  # pragma: no branch
            var room = (
                _wide_dot(x.points[p] - y.points[q], normal) - radii + allowance
            )
            var rate = _wide_dot(x.speeds[p] - y.speeds[q], normal)
            limit = min(limit, _first_root(room, rate, curvature))
    return limit


def _core_contacts(
    x: _Core,
    y: _Core,
    normal: SIMD[DType.float64, 4],
    band: Float64,
) -> List[SIMD[DType.float64, 4]]:
    """Return the contact points of two cores that touch within a band.

    Two round shapes touch at their closest points. Otherwise a corner of
    either shape within the band of the other is a point, and so is the
    closest point of two edges whose interiors come within the band. Each
    point lies on the surface of x, or of y for y's corners. The caller
    drops repeated points.

    Args:
        x: The first shape.
        y: The second shape.
        normal: Their normal from `_core_gap`, from y to x.
        band: The widest gap a point may have.

    Returns:
        The points, in order: x's corners, y's corners, then edge pairs.
    """
    var found = List[SIMD[DType.float64, 4]]()
    var radii = x.radius + y.radius
    if len(x.normals) == 0 and len(y.normals) == 0:
        var axis = x.points[len(x.points) - 1] - x.points[0]
        var gap = _segment_gap(
            x.points[0],
            axis,
            y.points[0],
            y.points[len(y.points) - 1] - y.points[0],
        )
        found.append(x.points[0] + axis * gap[2] - normal * x.radius)
        return found^
    for p in x.points:  # pragma: no branch
        if _hull_distance(p, y) - radii <= band:
            found.append(p - normal * x.radius)
    for q in y.points:  # pragma: no branch
        if _hull_distance(q, x) - radii <= band:
            found.append(q + normal * y.radius)
    for e in range(len(x.edge_a)):
        var start = x.points[x.edge_a[e]]
        var edge = x.points[x.edge_b[e]] - start
        for g in range(len(y.edge_a)):
            var other = y.points[y.edge_a[g]]
            var side = y.points[y.edge_b[g]] - other
            var pair = _segment_gap(start, edge, other, side)
            if pair[0] - radii > band:
                continue
            # Ends of either edge are corners, found above.
            var at = start + edge * pair[2]
            var along = _wide_dot(at - other, side) / _wide_dot(side, side)
            if min(pair[2], along) > 0 and max(pair[2], along) < 1:
                found.append(at - normal * x.radius)
    return found^


def _ccd_qp(
    matrix: List[Float64], closing: List[Float64]
) raises -> List[Float64]:
    """Solve the plastic contact problem by an active-set method.

    The impulses x >= 0 minimize x^T A x / 2 + b^T x, so the closing
    speeds w = A x + b end nonnegative and x_c w_c = 0. A = J M^-1 J^T is
    positive semidefinite. The method is Lawson and Hanson's nonnegative
    least squares, run on A and b. It adds the contact whose closing
    speed is most negative, lowest index first on a tie, solves the active
    contacts to zero closing speed, and steps back to keep each impulse
    nonnegative. On the solution x^T A x = -b^T x, so the impulses change
    the kinetic energy by -x^T A x / 2: they cannot add any.

    Args:
        matrix: A, row-major, m by m.
        closing: b, the closing speeds before the impulses.

    Returns:
        The impulses.

    Raises:
        Error: If no impulses can open every contact, as when a kinematic
            body drives a body into a mesh, or the method does not end.
    """
    var m = len(closing)
    var scale = Float64(0)
    var largest = Float64(0)
    for c in range(m):
        scale = max(scale, abs(closing[c]))
        for d in range(m):  # pragma: no branch
            largest = max(largest, abs(matrix[c * m + d]))
    var tolerance = scale * 1e-9
    var impulse = List[Float64](length=m, fill=0)
    var active = List[Bool](length=m, fill=False)
    for _ in range(4 * m + 8):  # pragma: no branch
        # The most negative closing speed of an inactive contact.
        var pick = -1
        var most = tolerance
        for c in range(m):
            if active[c]:
                continue
            var speed = closing[c]
            for d in range(m):  # pragma: no branch
                speed += matrix[c * m + d] * impulse[d]
            if -speed > most:
                most = -speed
                pick = c
        if pick < 0:
            return impulse^
        active[pick] = True
        for _ in range(m + 1):  # pragma: no branch
            var trial = _active_solve(matrix, closing, active, largest)
            var alpha = Float64(1)
            for c in range(m):  # pragma: no branch
                if active[c] and trial[c] <= 0:
                    alpha = min(alpha, impulse[c] / (impulse[c] - trial[c]))
            for c in range(m):  # pragma: no branch
                if active[c]:
                    impulse[c] += alpha * (trial[c] - impulse[c])
            if alpha == 1:
                break
            for c in range(m):  # pragma: no branch
                if active[c] and impulse[c] <= 0:
                    active[c] = False
                    impulse[c] = 0
    raise Error("CCD could not resolve simultaneous contacts; step rolled back")


def _active_solve(
    matrix: List[Float64],
    closing: List[Float64],
    active: List[Bool],
    largest: Float64,
) raises -> List[Float64]:
    # Solve A_SS x_S = -b_S by elimination with partial pivoting; the
    # inactive impulses are zero.
    var m = len(closing)
    var index = List[Int]()
    for c in range(m):  # pragma: no branch
        if active[c]:
            index.append(c)
    var size = len(index)
    var width = size + 1
    var rows = List[Float64](length=size * width, fill=0)
    for r in range(size):  # pragma: no branch
        for s in range(size):  # pragma: no branch
            rows[r * width + s] = matrix[index[r] * m + index[s]]
        rows[r * width + size] = -closing[index[r]]
    for column in range(size):  # pragma: no branch
        var pivot = column
        for r in range(column + 1, size):
            if abs(rows[r * width + column]) > abs(
                rows[pivot * width + column]
            ):
                pivot = r
        if abs(rows[pivot * width + column]) <= largest * 1e-12:
            raise Error(
                "CCD could not resolve simultaneous contacts; step rolled back"
            )
        for s in range(width):  # pragma: no branch
            var swap = rows[column * width + s]
            rows[column * width + s] = rows[pivot * width + s]
            rows[pivot * width + s] = swap
        for r in range(column + 1, size):
            var factor = (
                rows[r * width + column] / rows[column * width + column]
            )
            for s in range(column, width):  # pragma: no branch
                rows[r * width + s] -= factor * rows[column * width + s]
    var out = List[Float64](length=m, fill=0)
    for r in reversed(range(size)):  # pragma: no branch
        var value = rows[r * width + size]
        for s in range(r + 1, size):
            value -= rows[r * width + s] * out[index[s]]
        out[index[r]] = value / rows[r * width + r]
    return out^
