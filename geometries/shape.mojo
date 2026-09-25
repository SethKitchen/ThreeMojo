# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A flat surface filled in from a drawn outline, from three.js
`src/geometries/ShapeGeometry.js` and `ShapeUtils.triangulateShape`.

Every other geometry here is a grid. A box, a sphere, a lathe: rows and
columns of vertices, and two triangles per cell. A shape is not. It is an
outline drawn by hand, with holes in it, and nothing says how to cut it
up. three.js cuts it with earcut, and so does this, through
`geometries.earcut.triangulate_shape`.

## The order three.js builds it in

`ShapeGeometry.addShape` turns the outline clockwise and every hole
counter-clockwise, reversing whichever runs the other way. It reverses
with the closing point still in the list, and then `triangulateShape`
drops that point, so a reversed contour starts at the closing point and
leaves out the first one drawn. The vertices are the outline's points and
then each hole's, one after another, and the triangles are earcut's, in
earcut's order. This builds the same arrays in the same order, so a shape
here is three.js's shape number for number.

## What is refused

A hole outside the outline, or inside another hole: neither describes a
surface. A contour of fewer than three corners, or one with no area, such
as a line drawn out and back. three.js fills each of these with something,
or with nothing, and says nothing. This says so instead. The checks read
the contours and change none of them, so a shape that passes is built
exactly as three.js builds it.

An outline that crosses itself is not refused. earcut fills it in, as
three.js does, and the triangles follow the outline where it crosses.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    BufferGeometry,
    MaterialIndex,
    NORMAL,
    POSITION,
    UV,
)
from geometries.earcut import triangulate_shape
from math.path import Shape
from math.vector2 import Vector2


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


# How much of a turn is just the arithmetic, as a share of the size of the
# shape being measured. About eight times `Float32`'s own epsilon: three
# points read off a contour that spans `s` meters carry a rounding error of
# roughly `eps * s` in each coordinate, so the turn they make carries
# roughly `eps * s` times the distance the turn is measured across, and a
# threshold of that shape is the only one that separates a real corner from
# the rounding at every size.
#
# Two fixed thresholds came before this one, and both were wrong in a way
# worth writing down.
#
# The first was 1e-6 square meters flat, described in a comment as a square
# micrometer; it is a square millimeter, and that was the smaller mistake.
# The real one was that a square five millimeters on a side, sampled into
# twelve runs an edge, has a true corner whose turn measures 1.7e-7. The
# threshold called that corner flat and threw the whole shape away, and
# sampling it more finely made more shapes vanish rather than fewer.
#
# The second scaled with the distance between a point's two neighbors,
# which reads as "how flat, for a step this long". That drops a shallow
# corner on a long edge: the point of a triangle ten meters long and a
# millimeter thick stands 8e-5 meters off the line through its neighbors,
# which is a real corner of a real shape and was called flat.
#
# What is left is a noise floor and nothing else. A point is dropped when
# the turn it makes is no larger than the arithmetic could have invented,
# and kept otherwise, however shallow the corner is.
comptime NOISE = Float32(1e-6)


def extent(points: List[Vector2], start: Int, count: Int) -> Float32:
    """Return the diagonal of the box around a contour, which is the scale
    every tolerance here is taken as a share of.

    Args:
        points: Every point.
        start: Where the contour begins.
        count: How many points it has; at least one.

    Returns:
        The distance from the smallest corner of the box to the largest.
    """
    var low = points[start]
    var high = points[start]
    for index in range(1, count):  # pragma: no branch
        var here = points[start + index]
        low = Vector2(min(low.x, here.x), min(low.y, here.y))
        high = Vector2(max(high.x, here.x), max(high.y, here.y))
    return (high - low).length()


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
    var span = extent(points, 0, count)
    for index in range(count):  # pragma: no branch
        var before = points[(index + count - 1) % count]
        var after = points[(index + 1) % count]
        # The turn is twice the area of the triangle the three points
        # make: how far the middle one stands off the line through the
        # other two, times how far apart those two are. The rounding in
        # those three points is worth about `NOISE * span` in each
        # coordinate, so it is worth `NOISE * span * reach` in the turn,
        # and anything at or below that is a point in a line rather than a
        # corner. Coincident neighbors make `reach` zero, which makes both
        # sides zero, and the point goes with them.
        var reach = (after - before).length()
        if abs(turn(before, points[index], after)) <= NOISE * span * reach:
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


def _corners(points: List[Vector2]) raises -> List[Vector2]:
    """Return a closed contour's corners, and refuse a contour with no
    inside.

    Args:
        points: A contour's sampled points, the last the first again.

    Returns:
        The corners `_clean` keeps.

    Raises:
        Error: If fewer than three corners are left, or they enclose no
            area.
    """
    var corners = _clean(points)
    var doubled = _area(corners, 0, len(corners))
    var span = extent(corners, 0, len(corners))
    if abs(doubled) <= NOISE * span * span:
        raise Error("A shape's contour must enclose an area")
    return corners^


struct ShapePoints(Movable):
    """A shape's points, three.js's `Shape.extractPoints`: the outline and
    each hole, each closed, as drawn."""

    var outline: List[Vector2]
    var holes: List[List[Vector2]]

    def __init__(
        out self, var outline: List[Vector2], var holes: List[List[Vector2]]
    ):
        """Hold the outline's points and each hole's.

        Args:
            outline: The outline's points, the last the first again.
            holes: Each hole's points, likewise.
        """
        self.outline = outline^
        self.holes = holes^


def extract_points(shape: Shape, curve_segments: Int) raises -> ShapePoints:
    """Return `shape`'s points, three.js's `Shape.extractPoints`, once
    they are checked.

    Args:
        shape: The outline and its holes.
        curve_segments: How many straight runs each curve is sampled into;
            at least one.

    Returns:
        The outline's points and each hole's, as `Path.sample` gives them.

    Raises:
        Error: If `curve_segments` is less than one, if a contour has fewer
            than three distinct corners or no area, or if a hole lies
            outside the outline or inside another hole.
    """
    var outline = shape.outline_points(curve_segments)
    var corners = _corners(outline)
    var holes = List[List[Vector2]]()
    var hole_corners = List[List[Vector2]]()
    for hole in range(shape.hole_count()):
        var points = shape.hole_points(hole, curve_segments)
        hole_corners.append(_corners(points))
        holes.append(points^)

    # A hole outside the outline, or inside another hole, describes no
    # surface.
    for hole in range(len(hole_corners)):
        var probe = hole_corners[hole][0]
        if not _contains(corners, 0, len(corners), probe):
            raise Error("A shape's hole must lie inside its outline")
        for other in range(len(hole_corners)):  # pragma: no branch
            if other == hole:
                continue
            ref around = hole_corners[other]
            if _contains(around, 0, len(around), probe):
                raise Error("A shape's hole cannot lie inside another hole")
    return ShapePoints(outline^, holes^)


def is_clockwise(points: List[Vector2]) -> Bool:
    """Return True if `points` run clockwise, three.js's
    `ShapeUtils.isClockWise`: its `area` is negative.

    Args:
        points: A contour's points, closed or not.

    Returns:
        True if the signed area is below zero.
    """
    var total = Float64(0)
    var n = len(points)
    for q in range(n):  # pragma: no branch
        var p = (q + n - 1) % n
        total += Float64(points[p].x) * Float64(points[q].y) - Float64(
            points[q].x
        ) * Float64(points[p].y)
    return total * 0.5 < 0


def flat_points(points: List[Vector2]) -> List[Float64]:
    """Return `points` as earcut reads them, x then y for each.

    Args:
        points: The points.

    Returns:
        Two numbers a point.
    """
    var out = List[Float64]()
    for point in points:  # pragma: no branch
        out.append(Float64(point.x))
        out.append(Float64(point.y))
    return out^


def _drop_closing(mut points: List[Vector2]):
    """Drop a last point equal to the first, three.js's `removeDupEndPts`.
    Its test for more than two points always passes here: every contour
    has three corners at least."""
    var n = len(points)
    if points[n - 1] == points[0]:
        _ = points.pop()


struct Contours(Movable):
    """A shape's points, cut into triangles.

    The points are the outline's first, then each hole's, each without its
    closing point, in the order three.js keeps them. `starts` and `counts`
    say where each contour begins and how long it is, the outline first.
    The extrusion reads them to build its walls.
    """

    var points: List[Vector2]
    var index: List[Int]
    var starts: List[Int]
    var counts: List[Int]

    def __init__(
        out self, var outline: List[Vector2], var holes: List[List[Vector2]]
    ) raises:
        """Drop each contour's closing point and cut the whole into
        triangles, three.js's `ShapeUtils.triangulateShape`.

        Args:
            outline: The outline's points, turned as three.js turns them.
            holes: Each hole's points, likewise.

        Raises:
            Error: If earcut refuses the points; see
                `geometries.earcut.earcut`.
        """
        _drop_closing(outline)
        var flat_holes = List[List[Float64]]()
        for at in range(len(holes)):
            _drop_closing(holes[at])
            flat_holes.append(flat_points(holes[at]))
        self.index = triangulate_shape(flat_points(outline), flat_holes)
        self.starts = [0]
        self.counts = [len(outline)]
        self.points = outline^
        for at in range(len(holes)):
            self.starts.append(len(self.points))
            self.counts.append(len(holes[at]))
            self.points.extend(holes[at].copy())

    def contour_count(self) -> Int:
        """Return how many contours there are: the outline and its holes."""
        return len(self.starts)

    def triangle_count(self) -> Int:
        """Return how many triangles fill the shape."""
        return len(self.index) // 3


def triangulate(shape: Shape, curve_segments: Int = 12) raises -> Contours:
    """Return `shape`'s points and the triangles that fill them, as
    three.js's `ShapeGeometry.addShape` builds them.

    The outline is turned clockwise and each hole counter-clockwise, with
    the closing point still in the list, and earcut cuts the whole.

    Args:
        shape: The outline and its holes.
        curve_segments: How many straight runs each curve is sampled into;
            at least one.

    Returns:
        The contours, and three vertex numbers per triangle, each triangle
        wound counter-clockwise, in earcut's order.

    Raises:
        Error: If `curve_segments` is less than one, if a contour has fewer
            than three distinct corners or no area, or if a hole lies
            outside the outline or inside another hole.
    """
    var sampled = extract_points(shape, curve_segments)
    var outline = sampled.outline.copy()
    if not is_clockwise(outline):
        outline.reverse()
    var holes = List[List[Vector2]]()
    for at in range(len(sampled.holes)):
        var hole = sampled.holes[at].copy()
        if is_clockwise(hole):
            hole.reverse()
        holes.append(hole^)
    return Contours(outline^, holes^)


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


def shape_geometry(
    shapes: List[Shape], curve_segments: Int = 12
) raises -> BufferGeometry:
    """Return several shapes as one flat surface in the z equals zero
    plane, three.js's `ShapeGeometry` given an array of shapes.

    Each shape is filled as the one-shape form fills it, the shapes one
    after another, and each is a group whose material index is its place
    in the list, as three.js's `addGroup( groupStart, groupCount, i )`.

    Args:
        shapes: The outlines, each with its holes; at least one.
        curve_segments: How many straight runs each curve is sampled into;
            at least one.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes, an index,
        and one group per shape.

    Raises:
        Error: If there is no shape, or a shape cannot be filled in; see
            `triangulate`.
    """
    if len(shapes) == 0:
        raise Error("A shape geometry needs at least one shape")
    var data = List[Float32]()
    var normals = List[Float32]()
    var uvs = List[Float32]()
    var index = List[Int]()
    var counts = List[Int]()
    for shape in shapes:  # pragma: no branch
        var part = shape_geometry(shape, curve_segments)
        var offset = len(data) // 3
        data.extend(part.attribute_view(String(POSITION)).packed())
        normals.extend(part.attribute_view(String(NORMAL)).packed())
        uvs.extend(part.attribute_view(String(UV)).packed())
        for corner in part.index:  # pragma: no branch
            index.append(corner + offset)
        counts.append(len(part.index))
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(data^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
    geometry.set_index(index^)
    var start = 0
    for at in range(len(counts)):  # pragma: no branch
        geometry.add_group(start, counts[at], MaterialIndex(at))
        start += counts[at]
    return geometry^
