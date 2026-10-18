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

from math.cross import wide_cross, wide_dot, widen_vector
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
    return wide_dot(travel, normal) < -bound * 7.105427357601002e-15


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
    var a = wide_dot(travel, travel)
    var b = wide_dot(offset, travel)
    if a == 0 or b >= 0:
        return 2
    var c = wide_dot(offset, offset) - radius * radius
    if c <= 0:
        return 0

    comptime if initial_only:
        return 2
    else:
        # Resolve the closest point before squaring its distance. Expanding
        # b*b-a*c loses the complete radius term on long, nearly axial paths.
        var closest = offset - travel * (b / a)
        var height = radius * radius - wide_dot(closest, closest)
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
    if wide_dot(at - origin, face) < 0:
        return best
    var normal = at - point
    var length = sqrt(wide_dot(normal, normal))
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
    var a = widen_vector(triangle.a)
    var b = widen_vector(triangle.b)
    var c = widen_vector(triangle.c)
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
    var a = widen_vector(triangle.a)
    var b = widen_vector(triangle.b)
    var c = widen_vector(triangle.c)
    var normal = wide_cross(b - a, c - a)
    var length = sqrt(wide_dot(normal, normal))
    if length == 0:
        return best
    normal /= length
    var height = wide_dot(start - a, normal)
    if height < 0:
        # The mesh remains one-sided. Never catch a body from its back.
        return best
    var speed = wide_dot(travel, normal)
    if _approaches(travel, normal):
        var fraction = Float64(2)

        comptime if initial_only:
            if height <= radius:
                fraction = 0
        else:
            fraction = max((radius - height) / speed, Float64(0))
        if fraction <= 1:
            var at = start + travel * fraction
            var point = at - normal * wide_dot(at - a, normal)
            if (
                wide_dot(wide_cross(b - a, point - a), normal) >= 0
                and wide_dot(wide_cross(c - b, point - b), normal) >= 0
                and wide_dot(wide_cross(a - c, point - c), normal) >= 0
            ):
                best = _SweepHit(fraction, normal)
    var vertices = [a, b, c]
    # The three cylinders and three vertices cover the rounded boundary.
    # Equal fractions retain the face, then edge/vertex insertion order.
    for i in range(3):  # pragma: no branch
        var p = vertices[i]
        var edge = vertices[(i + 1) % 3] - p
        var square = wide_dot(edge, edge)
        # The nonzero triangle normal proves that this edge is nonzero.
        var offset = start - p
        var along = wide_dot(offset, edge) / square
        var delta = wide_dot(travel, edge) / square
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
    var aa = wide_dot(axis, axis)
    var ae = wide_dot(axis, edge)
    var ee = wide_dot(edge, edge)
    var ao = wide_dot(axis, offset)
    var eo = wide_dot(edge, offset)
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
    var length_sq = wide_dot(axis, axis)
    if length_sq == 0:
        return best

    comptime if not initial_only:
        var middle = start + axis * 0.5
        if not _sweep_domain(
            middle, travel, radius, radius + 0.5 * sqrt(length_sq), triangle
        ):
            return best
    var a = widen_vector(triangle.a)
    var b = widen_vector(triangle.b)
    var c = widen_vector(triangle.c)
    var normal = wide_cross(b - a, c - a)
    var length = sqrt(wide_dot(normal, normal))
    if length == 0:
        return best
    normal /= length
    if wide_dot(start - a, normal) < 0 and wide_dot(end - a, normal) < 0:
        # The mesh remains one-sided. A capsule wholly behind the face
        # never reaches its front, as each cap sweep already reports.
        return best
    var vertices = [a, b, c]
    for i in range(3):  # pragma: no branch
        var p = vertices[i]
        var edge = vertices[(i + 1) % 3] - p
        # The segment's interior on this edge. Parallel lines meet first
        # at a cap or a vertex, which the other features cover.
        var cross = wide_cross(axis, edge)
        var cross_sq = wide_dot(cross, cross)
        if cross_sq > 0:
            var unit = cross / sqrt(cross_sq)
            var gap = wide_dot(start - p, unit)
            var rate = wide_dot(travel, unit)
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
        var along = wide_dot(offset, axis) / length_sq
        var delta = -wide_dot(travel, axis) / length_sq
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
    normal /= sqrt(wide_dot(normal, normal))
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
    var square = wide_dot(axis, axis)
    if square == 0:
        return found
    var end = start + axis
    found = _point_hit(
        found, point, travel, end, _root(point - end, travel, radius), flip
    )
    var offset = point - start
    var along = wide_dot(offset, axis) / square
    var delta = wide_dot(travel, axis) / square
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
    var cross = wide_cross(a_axis, b_axis)
    var cross_sq = wide_dot(cross, cross)
    if cross_sq == 0:
        return best
    var unit = cross / sqrt(cross_sq)
    var gap = wide_dot(a - b, unit)
    var rate = wide_dot(travel, unit)
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
    var aa = wide_dot(a_axis, a_axis)
    var bb = wide_dot(b_axis, b_axis)
    var f = wide_dot(b_axis, r)
    var s = Float64(0)
    var t = Float64(0)
    if aa == 0 and bb > 0:
        t = min(max(f / bb, Float64(0)), Float64(1))
    elif aa > 0:
        var c = wide_dot(a_axis, r)
        if bb == 0:
            s = min(max(-c / aa, Float64(0)), Float64(1))
        else:
            var ab = wide_dot(a_axis, b_axis)
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
    var distance = sqrt(wide_dot(gap, gap))
    if distance == 0:
        return (distance, SIMD[DType.float64, 4](0), s)
    return (distance, gap / distance, s)


def _on_segment(
    p: SIMD[DType.float64, 4],
    x: SIMD[DType.float64, 4],
    edge: SIMD[DType.float64, 4],
) -> SIMD[DType.float64, 4]:
    # The point of segment x + u edge, u in [0, 1], closest to p.
    var u = wide_dot(p - x, edge) / wide_dot(edge, edge)
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
    var normal = wide_cross(b - a, c - a)
    var flat = p - normal * (wide_dot(p - a, normal) / wide_dot(normal, normal))
    if (
        wide_dot(wide_cross(b - a, flat - a), normal) >= 0
        and wide_dot(wide_cross(c - b, flat - b), normal) >= 0
        and wide_dot(wide_cross(a - c, flat - c), normal) >= 0
    ):
        return flat
    var best = _on_segment(p, a, b - a)
    for edge in [(b, c - b), (c, a - c)]:  # pragma: no branch
        var other = _on_segment(p, edge[0], edge[1])
        if wide_dot(p - other, p - other) < wide_dot(p - best, p - best):
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
    var a = widen_vector(triangle.a)
    var b = widen_vector(triangle.b)
    var c = widen_vector(triangle.c)
    var face = wide_cross(b - a, c - a)
    face /= sqrt(wide_dot(face, face))
    var best = Float64(1e300)
    var normal = face
    var point = start
    for end in range(2):  # pragma: no branch
        var p = start + axis * Float64(end)
        var gap = p - _triangle_closest(p, a, b, c)
        var distance = sqrt(wide_dot(gap, gap))
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
    var low = wide_dot(start - a, face)
    var high = wide_dot(start + axis - a, face)
    if low * high < 0:
        var crossing = start + axis * (low / (low - high))
        if (
            wide_dot(wide_cross(b - a, crossing - a), face) >= 0
            and wide_dot(wide_cross(c - b, crossing - b), face) >= 0
            and wide_dot(wide_cross(a - c, crossing - c), face) >= 0
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
    var a = widen_vector(triangle.a)
    var b = widen_vector(triangle.b)
    var c = widen_vector(triangle.c)
    var face = wide_cross(b - a, c - a)
    face /= sqrt(wide_dot(face, face))
    if wide_dot(ends[0] - a, face) < 0 and wide_dot(ends[1] - a, face) < 0:
        # The mesh stays one-sided.
        return -1
    # Each plane is a unit normal and a point on it.
    var normals = List[SIMD[DType.float64, 4]]()
    var origins = List[SIMD[DType.float64, 4]]()
    normals.append(face)
    origins.append(a)
    var corners = [a, b, c]
    for i in range(3):  # pragma: no branch
        var side = wide_cross(corners[(i + 1) % 3] - corners[i], face)
        normals.append(side / sqrt(wide_dot(side, side)))
        origins.append(corners[i])
    # The plane that separates the segment most now.
    var chosen = 0
    var most = Float64(-1e300)
    for k in range(4):  # pragma: no branch
        var low = min(
            wide_dot(ends[0] - origins[k], normals[k]),
            wide_dot(ends[1] - origins[k], normals[k]),
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
            wide_dot(tips[end] - origins[chosen], normals[chosen])
            - radius
            + allowance
        )
        var rate = wide_dot(moving[end], normals[chosen])
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
    var low = wide_dot(points[0], axis)
    var high = low
    # A triangle or a solid has three points at least.
    for k in range(1, len(points)):  # pragma: no branch
        var value = wide_dot(points[k], axis)
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
    var a = widen_vector(triangle.a)
    var b = widen_vector(triangle.b)
    var c = widen_vector(triangle.c)
    var face = wide_cross(b - a, c - a)
    face /= sqrt(wide_dot(face, face))
    if _project(vertices, face)[1] < wide_dot(a, face):
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
            axes.append(wide_cross(edge, corners[(k + 1) % 3] - corners[k]))
    var entry = Float64(-1e300)
    var leave = Float64(1e300)
    var normal = SIMD[DType.float64, 4](0)
    # The axis of least overlap now, and the way it separates the solid.
    var depth = Float64(1e300)
    var shallow = SIMD[DType.float64, 4](0)
    for axis in axes:  # pragma: no branch
        var square = wide_dot(axis, axis)
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
        var rate = wide_dot(travel, unit)
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
