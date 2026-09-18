# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A flat surface filled in from a drawn outline, from three.js
`src/geometries/ShapeGeometry.js` and the triangulation in `ShapeUtils.js`.

Every other geometry here is a grid. A box, a sphere, a lathe: rows and
columns of vertices, and two triangles per cell. A shape is not. It is an
outline drawn by hand, with holes in it, and nothing says how to cut it
up. That is the whole problem this module solves, and it is the reason
three.js carries a triangulator of its own.

## How it is cut up

By ear clipping, which is the oldest answer and the one three.js used
before it took earcut. A corner of a polygon is an *ear* when the triangle
it makes with its two neighbors lies inside the polygon and holds no other
corner. Clip that triangle off, and what is left is a polygon with one
corner fewer. Repeat until three corners are left. Every simple polygon
has at least two ears at every step, so this always finishes.

## How a hole is joined on

A hole is a separate loop, and ear clipping knows only one loop. So each
hole is cut into the outline first: pick a point of the hole and a point of
the outline that can see each other, and run the outline out along that
line, around the hole and back. The loop is now one loop, with a seam that
goes out and back along the same line and so has no area.

three.js and earcut pick that seam by casting a ray from the hole's
rightmost point, which is quick and needs a second pass to fix the cases
it gets wrong. This picks the *shortest* pair that can see each other,
which is slower and has no cases to fix: a pair that sees each other is a
seam that works, and nothing else has to be true of it.

Two points see each other when the line between them crosses no edge of
the outline and no edge of any hole. That is checked against the holes not
yet joined on as well, which is what keeps two holes from being seamed
through one another.

## What is refused

A hole outside the outline, or inside another hole: neither describes a
surface. A contour of fewer than three corners, or one with no area, such
as a line drawn out and back. An outline that crosses itself, which has no
inside and no ears, and which is refused when the clipping runs out of
ears rather than by a test of its own.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from math.path import Shape
from math.vector2 import Vector2

# A turn smaller than this is no turn, and an area smaller than this is no
# area. The contours are in meters, so this is a square micrometer, far
# below anything a shape is drawn to and far above the noise in a Float32
# sum of products.
comptime NEARBY = Float32(1e-6)


def turn(origin: Vector2, first: Vector2, second: Vector2) -> Float32:
    """Return which way the path from `first` through `origin` to `second`
    turns, and by how much.

    It is the cross product of the two runs out of `origin`, so it is
    positive when `second` lies to the left of `first`, negative when it
    lies to the right, and zero when the three points are in a line. Twice
    the triangle's area, signed.

    Args:
        origin: The point the two runs leave from, in meters.
        first: Where the first run ends, in meters.
        second: Where the second run ends, in meters.

    Returns:
        The signed area of the triangle, doubled.
    """
    return (first - origin).cross(second - origin)


def _clean(points: List[Vector2]) raises -> List[Vector2]:
    """Return the corners of a sampled contour: its points without the
    closing one, and without any point that lies on the straight line
    between its two neighbors.

    The points in a line are the ones that matter, and dropping them is not
    tidying. A straight edge sampled into eight runs leaves seven corners
    that turn by nothing. None of them can ever be an ear, so the clipping
    works its way around the loop and stops with a row of them left and
    nothing it can take. The edge they describe is one edge, and saying so
    once is what lets the clipping finish.

    It is also what handles a point sampled twice at one place. Such a
    point lies on the line between its neighbors -- it *is* one of them --
    so it goes the same way, and the edge of no length it would have left
    goes with it.

    Args:
        points: A contour's sampled points. A `Shape` holds closed paths
            only, so the last is the first again.

    Returns:
        The contour's corners, in order, not closed.

    Raises:
        Error: If fewer than three corners are left, which is a contour
            with no inside.
    """
    var corners = List[Vector2]()
    var count = len(points) - 1
    for index in range(count):  # pragma: no branch
        var before = points[(index + count - 1) % count]
        var after = points[(index + 1) % count]
        if abs(turn(before, points[index], after)) <= NEARBY:
            continue
        corners.append(points[index])
    if len(corners) < 3:
        raise Error("A shape's contour needs three corners")
    return corners^


def _area(points: List[Vector2], start: Int, count: Int) -> Float32:
    """Return twice the signed area of the contour at `start`. It is
    positive when the contour runs counter-clockwise."""
    var total = Float32(0)
    for index in range(count):  # pragma: no branch
        var here = points[start + index]
        var next = points[start + (index + 1) % count]
        total += here.cross(next)
    return total


def _contains(
    points: List[Vector2], start: Int, count: Int, probe: Vector2
) -> Bool:
    """Return True if `probe` lies inside the contour at `start`.

    By ray casting: count the edges directly to the right of the probe,
    and the probe is inside when that count is odd. An edge counts when the
    probe's height falls between its two ends, with one end counted and the
    other not, so a ray through a corner counts it once.
    """
    var inside = False
    for index in range(count):  # pragma: no branch
        var here = points[start + index]
        var next = points[start + (index + 1) % count]
        if (here.y > probe.y) != (next.y > probe.y):
            var along = (probe.y - here.y) / (next.y - here.y)
            if probe.x < here.x + along * (next.x - here.x):
                inside = not inside
    return inside


def _crosses(
    first: Vector2, second: Vector2, third: Vector2, fourth: Vector2
) -> Bool:
    """Return True if the run from `first` to `second` crosses the run from
    `third` to `fourth`.

    Crossing means each run has one end on each side of the other, which is
    what the four turns say. A run that only touches the other, at an end
    or along it, does not cross it: the seam this answers for shares its
    ends with the contour by design.
    """
    var start = turn(third, fourth, first)
    var end = turn(third, fourth, second)
    var left = turn(first, second, third)
    var right = turn(first, second, fourth)
    return (start > 0) != (end > 0) and (left > 0) != (right > 0)


def _blocked(
    points: List[Vector2],
    ring: List[Int],
    from_point: Int,
    to_point: Int,
) -> Bool:
    """Return True if the seam from `from_point` to `to_point` crosses an
    edge of `ring`.

    An edge that ends at either end of the seam is skipped. Such an edge
    touches the seam by construction, and touching is not crossing.
    """
    for index in range(len(ring)):  # pragma: no branch
        var here = ring[index]
        var next = ring[(index + 1) % len(ring)]
        if (
            here == from_point
            or here == to_point
            or next == from_point
            or next == to_point
        ):
            continue
        if _crosses(
            points[from_point], points[to_point], points[here], points[next]
        ):
            return True
    return False


def _bridge(
    points: List[Vector2], ring: List[Int], pending: List[List[Int]]
) -> List[Int]:
    """Return `ring` with the first pending hole seamed into it.

    The seam is the shortest pair of points, one on the hole and one on the
    ring, that can see each other: the line between them crosses no edge of
    the ring and none of any hole still to be joined on, the hole's own
    edges included.

    A hole inside the outline and outside every other hole always has such
    a pair, and `triangulate` has already refused a hole that is neither.
    If no pair is found regardless, the first one is taken: the loop that
    leaves crosses itself, so the clipping refuses it and says so.
    """
    ref hole = pending[0]
    var shortest = Float32(0)
    var at_ring = 0
    var at_hole = 0
    var found = False
    for outer in range(len(ring)):  # pragma: no branch
        for inner in range(len(hole)):  # pragma: no branch
            var span = (points[ring[outer]] - points[hole[inner]]).length()
            if found and span >= shortest:
                continue
            if _blocked(points, ring, hole[inner], ring[outer]):
                continue
            var crossed = False
            for other in range(len(pending)):  # pragma: no branch
                if _blocked(points, pending[other], hole[inner], ring[outer]):
                    crossed = True
            if crossed:
                continue
            shortest = span
            at_ring = outer
            at_hole = inner
            found = True

    # Out along the seam, once around the hole, back along the seam, and on
    # around the ring. Both ends of the seam appear twice, which is what
    # makes one loop out of two.
    var joined = List[Int]()
    for index in range(at_ring + 1):  # pragma: no branch
        joined.append(ring[index])
    for step in range(len(hole)):  # pragma: no branch
        joined.append(hole[(at_hole + step) % len(hole)])
    joined.append(hole[at_hole])
    for index in range(at_ring, len(ring)):  # pragma: no branch
        joined.append(ring[index])
    return joined^


def _find_ear(points: List[Vector2], ring: List[Int]) -> Int:
    """Return where in `ring` a corner sits that can be clipped off, or
    minus one when no corner can be.

    A corner is an ear when it turns left, so its triangle lies inside the
    loop, and no other corner of the loop lies within that triangle.
    """
    for at in range(len(ring)):  # pragma: no branch
        var before = (at + len(ring) - 1) % len(ring)
        var after = (at + 1) % len(ring)
        var corner = points[ring[at]]
        var left = points[ring[before]]
        var right = points[ring[after]]
        if turn(left, corner, right) <= NEARBY:
            continue
        var clear = True
        for other in range(len(ring)):  # pragma: no branch
            if other == before or other == at or other == after:
                continue
            var probe = points[ring[other]]
            if (
                turn(left, corner, probe) > 0
                and turn(corner, right, probe) > 0
                and turn(right, left, probe) > 0
            ):
                clear = False
        if clear:
            return at
    return -1


def _ear_clip(points: List[Vector2], var ring: List[Int]) raises -> List[Int]:
    """Return the triangles that fill `ring`, three vertex numbers each.

    Args:
        points: Every point, the ring's numbers index into it.
        ring: One loop, counter-clockwise, holes already seamed in.

    Returns:
        Three vertex numbers per triangle, each wound counter-clockwise.

    Raises:
        Error: If the loop runs out of ears before it runs out of corners.
            Every simple loop has an ear at every step, so a loop that has
            none crosses itself.
    """
    var index = List[Int]()
    while len(ring) > 3:
        var ear = _find_ear(points, ring)
        if ear < 0:
            raise Error("A shape that crosses itself cannot be filled in")
        var before = (ear + len(ring) - 1) % len(ring)
        var after = (ear + 1) % len(ring)
        index.append(ring[before])
        index.append(ring[ear])
        index.append(ring[after])
        _ = ring.pop(ear)
    index.append(ring[0])
    index.append(ring[1])
    index.append(ring[2])
    return index^


struct Contours(Movable):
    """A shape's points, cut into triangles.

    The points are the outline's first, then each hole's, every contour
    cleaned and turned the way the clipping wants it: the outline
    counter-clockwise, every hole clockwise. `starts` and `counts` say
    where each contour begins and how long it is, the outline first. The
    extrusion reads them to build its walls.
    """

    var points: List[Vector2]
    var index: List[Int]
    var starts: List[Int]
    var counts: List[Int]

    def __init__(
        out self,
        var points: List[Vector2],
        var index: List[Int],
        var starts: List[Int],
        var counts: List[Int],
    ):
        """Hold the points, the triangles and where each contour is.

        Args:
            points: Every contour's points, one after another.
            index: Three vertex numbers per triangle.
            starts: Where each contour begins in `points`.
            counts: How many points each contour has.
        """
        self.points = points^
        self.index = index^
        self.starts = starts^
        self.counts = counts^

    def contour_count(self) -> Int:
        """Return how many contours there are: the outline and its holes."""
        return len(self.starts)

    def triangle_count(self) -> Int:
        """Return how many triangles fill the shape."""
        return len(self.index) // 3


def _add_contour(
    var contour: List[Vector2],
    want_counter_clockwise: Bool,
    mut points: List[Vector2],
) raises -> Int:
    """Clean `contour`, turn it the way the clipping wants it, and append
    it to `points`.

    Args:
        contour: The contour's sampled points.
        want_counter_clockwise: True for the outline, False for a hole.
        points: The list every contour is appended to.

    Returns:
        How many points were appended.

    Raises:
        Error: If the contour has fewer than three distinct points, or no
            area at all.
    """
    var cleaned = _clean(contour)
    var start = len(points)
    for index in range(len(cleaned)):  # pragma: no branch
        points.append(cleaned[index])
    var doubled = _area(points, start, len(cleaned))
    if abs(doubled) <= NEARBY:
        raise Error("A shape's contour must enclose an area")
    if (doubled > 0) != want_counter_clockwise:
        for step in range(len(cleaned) // 2):  # pragma: no branch
            var low = start + step
            var high = start + len(cleaned) - 1 - step
            var held = points[low]
            points[low] = points[high]
            points[high] = held
    return len(cleaned)


def triangulate(shape: Shape, curve_segments: Int = 12) raises -> Contours:
    """Return `shape`'s points and the triangles that fill them.

    Args:
        shape: The outline and its holes.
        curve_segments: How many straight runs each curve is sampled into;
            at least one.

    Returns:
        The contours, and three vertex numbers per triangle, each triangle
        wound counter-clockwise.

    Raises:
        Error: If `curve_segments` is less than one, if a contour has fewer
            than three distinct points or no area, if a hole lies outside
            the outline or inside another hole, or if the outline crosses
            itself.
    """
    var points = List[Vector2]()
    var starts = List[Int]()
    var counts = List[Int]()

    starts.append(0)
    counts.append(
        _add_contour(shape.outline_points(curve_segments), True, points)
    )
    for hole in range(shape.hole_count()):  # pragma: no branch
        starts.append(len(points))
        counts.append(
            _add_contour(shape.hole_points(hole, curve_segments), False, points)
        )

    # A hole outside the outline, or inside another hole, describes no
    # surface. Neither is caught by the seaming, which would run a line to
    # it and leave a loop that crosses itself.
    for hole in range(1, len(starts)):  # pragma: no branch
        if not _contains(points, 0, counts[0], points[starts[hole]]):
            raise Error("A shape's hole must lie inside its outline")
        for other in range(1, len(starts)):  # pragma: no branch
            if other == hole:
                continue
            if _contains(
                points, starts[other], counts[other], points[starts[hole]]
            ):
                raise Error("A shape's hole cannot lie inside another hole")

    var ring = List[Int]()
    for index in range(counts[0]):  # pragma: no branch
        ring.append(index)
    var pending = List[List[Int]]()
    for hole in range(1, len(starts)):  # pragma: no branch
        var loop = List[Int]()
        for index in range(counts[hole]):  # pragma: no branch
            loop.append(starts[hole] + index)
        pending.append(loop^)
    while len(pending) > 0:
        ring = _bridge(points, ring, pending)
        _ = pending.pop(0)

    var index = _ear_clip(points, ring^)
    return Contours(points^, index^, starts^, counts^)


def shape_geometry(
    shape: Shape, curve_segments: Int = 12
) raises -> BufferGeometry:
    """Return `shape` as a flat surface in the z equals zero plane.

    Args:
        shape: The outline and its holes.
        curve_segments: How many straight runs each curve is sampled into;
            at least one.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes and an
        index buffer, wound counter-clockwise seen from the positive z
        axis, every normal along that axis. The texture coordinates are the
        points themselves, which is three.js's default generator.

    Raises:
        Error: If the shape cannot be filled in; see `triangulate`.
    """
    var cut = triangulate(shape, curve_segments)
    var data = List[Float32]()
    var normals = List[Float32]()
    var uvs = List[Float32]()
    for index in range(len(cut.points)):  # pragma: no branch
        var point = cut.points[index]
        data.append(point.x)
        data.append(point.y)
        data.append(0)
        normals.append(0)
        normals.append(0)
        normals.append(1)
        uvs.append(point.x)
        uvs.append(point.y)

    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(data^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
    geometry.set_index(cut.index.copy())
    return geometry^
