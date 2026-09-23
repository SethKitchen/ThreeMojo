# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Loose outlines sorted into shapes with holes, from three.js
`src/extras/core/ShapePath.js` and `ShapeUtils.isClockWise`.

A font draws a letter as a list of outlines and does not say which of them
are holes. An "O" is two circles. Only the way each one runs tells them
apart: a font draws its solids clockwise and its holes counterclockwise. A
`ShapePath` collects the outlines, one `Path` per `move_to`, and
`to_shapes` sorts them into `Shape`s by that rule, as three.js does.

## How holes are found

Each outline is sampled at twelve runs a curve, three.js's `getPoints()`
default, and its signed area says which way it runs. A clockwise outline
is a solid and a counterclockwise one is a hole, or the other way round
when `is_ccw` is True.

A hole goes to the solid it was drawn next to. When the first outline is
a hole, the font draws each hole before its solid, and a hole goes to the
solid after it. Otherwise it goes to the solid before it. When there is
more than one solid, each hole's first point is then tested against each
solid, and a hole that lies inside another solid moves there. It moves
only when no hole lies inside two solids, since then nothing says which
of the two it belongs to. That is three.js's rule, `ambiguous` and all.

When the first outline is a hole, a hole drawn after the last solid has
no solid to go to, and three.js drops it. So does this.

When there is no solid at all, every outline becomes a shape of its own.
three.js takes that as a font wound the other way round.

## Where this differs

three.js lets a `Shape` hold an outline that is not closed, and closes it
when it is filled in. A `Shape` here refuses one, so `to_shapes` draws the
closing run first when an outline does not end where it began. The
surface is the same.
"""

from math.path import Path, Shape
from math.vector2 import Vector2

# JavaScript's `Number.EPSILON`: how far an edge must climb before
# `isPointInsidePolygon` treats it as not level.
comptime LEVEL = Float32(2.220446049250313e-16)
# How many runs `to_shapes` cuts each curve into to tell solids from holes,
# three.js's `getPoints()` default.
comptime SORT_DIVISIONS = 12


def signed_area(contour: List[Vector2]) -> Float32:
    """Return the area a contour encloses, signed, three.js's
    `ShapeUtils.area`.

    Args:
        contour: The points, in meters. The last is joined back to the
            first, whether or not it repeats it.

    Returns:
        The area in square meters, positive when the contour runs
        counterclockwise.
    """
    var total = Float32(0)
    var count = len(contour)
    for index in range(count):
        var before = contour[(index + count - 1) % count]
        var here = contour[index]
        total += before.x * here.y - here.x * before.y
    return total * 0.5


def is_clockwise(contour: List[Vector2]) -> Bool:
    """Return True if a contour runs clockwise, three.js's
    `ShapeUtils.isClockWise`.

    Args:
        contour: The points, in meters.

    Returns:
        True when the signed area is negative.
    """
    return signed_area(contour) < 0


def _between(first: Float32, second: Float32, probe: Float32) -> Bool:
    """Return True if `probe` lies between two numbers, ends included, in
    either order."""
    return (first <= probe and probe <= second) or (
        second <= probe and probe <= first
    )


def is_point_inside_polygon(point: Vector2, polygon: List[Vector2]) -> Bool:
    """Return True if a point lies inside a polygon or on its edge, three.js's
    `isPointInsidePolygon` from `ShapePath.toShapes`.

    A ray runs from the point toward negative x, and the polygon is
    inside when the ray crosses an odd number of edges. The lower end of
    an edge does not count, and a level edge does not count, so a ray
    through a corner counts it once. A point on an edge is inside.

    Args:
        point: The point, in meters.
        polygon: The polygon's points, in meters. The last is joined back
            to the first.

    Returns:
        True if the point is inside the polygon or on its boundary.
    """
    var inside = False
    var count = len(polygon)
    for index in range(count):
        var low = polygon[(index + count - 1) % count]
        var high = polygon[index]
        var rise = high - low
        if abs(rise.y) > LEVEL:
            if rise.y < 0:
                low = polygon[index]
                high = polygon[(index + count - 1) % count]
                rise = high - low
            if point.y < low.y:
                continue
            if point.y > high.y:
                continue
            if point.y == low.y:
                if point.x == low.x:
                    return True
                continue
            var side = rise.y * (point.x - low.x) - rise.x * (point.y - low.y)
            if side == 0:
                return True
            if side < 0:
                continue
            inside = not inside
        elif point.y == low.y:
            if _between(low.x, high.x, point.x):
                return True
    return inside


def _closed(path: Path) raises -> Path:
    """Return a copy of `path` that ends where it began.

    Raises:
        Error: If the path has nothing on it.
    """
    var copy = Path(copy=path)
    if not copy.is_closed():
        copy.close_path()
    return copy^


def _shape(path: Path) raises -> Shape:
    """Return a shape whose outline is `path`, closed.

    Raises:
        Error: If the path has nothing on it.
    """
    return Shape(_closed(path))


struct ShapePath(Copyable, Movable):
    """Outlines drawn one after another, three.js's `ShapePath`."""

    var sub_paths: List[Path]

    def __init__(out self):
        """Create a shape path with nothing drawn."""
        self.sub_paths = List[Path]()

    def path_count(self) -> Int:
        """Return how many outlines have been started."""
        return len(self.sub_paths)

    def _last(self) raises -> Int:
        """Return which outline is being drawn.

        Raises:
            Error: If no outline has been started.
        """
        if len(self.sub_paths) == 0:
            raise Error("A shape path must move before it draws")
        return len(self.sub_paths) - 1

    def move_to(mut self, start: Vector2):
        """Start a new outline at `start`.

        Args:
            start: Where the outline begins, in meters.
        """
        self.sub_paths.append(Path(start))

    def line_to(mut self, end: Vector2) raises:
        """Draw a straight run on the current outline.

        Args:
            end: Where the run ends, in meters.

        Raises:
            Error: If no outline has been started, or `end` is where the
                pen already is.
        """
        self.sub_paths[self._last()].line_to(end)

    def quadratic_curve_to(mut self, control: Vector2, end: Vector2) raises:
        """Draw a Bezier curve with one control point on the current
        outline.

        Args:
            control: The point the curve is pulled toward, in meters.
            end: Where the curve ends, in meters.

        Raises:
            Error: If no outline has been started, or all three points are
                the same.
        """
        self.sub_paths[self._last()].quadratic_to(control, end)

    def bezier_curve_to(
        mut self, first: Vector2, second: Vector2, end: Vector2
    ) raises:
        """Draw a Bezier curve with two control points on the current
        outline.

        Args:
            first: The point the start is pulled toward, in meters.
            second: The point the end is pulled toward, in meters.
            end: Where the curve ends, in meters.

        Raises:
            Error: If no outline has been started, or all four points are
                the same.
        """
        self.sub_paths[self._last()].cubic_to(first, second, end)

    def to_shapes(self, is_ccw: Bool = False) raises -> List[Shape]:
        """Return the outlines sorted into shapes with holes, three.js's
        `toShapes`.

        Args:
            is_ccw: False when solids run clockwise and holes
                counterclockwise, as a font draws them. True for the other
                way round.

        Returns:
            One shape per solid, in the order the solids were drawn, each
            outline closed. No shapes when nothing was drawn.

        Raises:
            Error: If an outline has nothing drawn on it after its move.
        """
        var shapes = List[Shape]()
        var count = len(self.sub_paths)
        if count == 0:
            return shapes^
        if count == 1:
            shapes.append(_shape(self.sub_paths[0]))
            return shapes^

        var points = List[List[Vector2]]()
        for index in range(count):  # pragma: no branch
            # More than one outline, so this runs.
            points.append(self.sub_paths[index].sample(SORT_DIVISIONS))
        var holes_first = is_clockwise(points[0]) == is_ccw

        # One slot per solid: which outline it is, and which outlines are
        # its holes. The hole lists run one slot longer when holes come
        # first, and the holes in that last slot are dropped.
        var solids = List[Int]()
        var holes = List[List[Int]]()
        holes.append(List[Int]())
        var slot = 0
        for index in range(count):  # pragma: no branch
            if is_clockwise(points[index]) == is_ccw:
                holes[slot].append(index)
            elif holes_first:
                # This solid takes the holes drawn before it, and the
                # holes after it wait for the next.
                solids.append(index)
                slot += 1
                holes.append(List[Int]())
            else:
                # The holes after this solid are its own. The first solid
                # is the first outline, so nothing waits in slot zero.
                if len(solids) > 0:
                    slot += 1
                    holes.append(List[Int]())
                solids.append(index)

        if len(solids) == 0:
            # Only holes: a font wound the other way round, three.js's
            # `toShapesNoHoles`.
            for index in range(count):  # pragma: no branch
                shapes.append(_shape(self.sub_paths[index]))
            return shapes^

        if len(solids) > 1:
            var better = List[List[Int]]()
            for _ in range(len(solids)):  # pragma: no branch
                better.append(List[Int]())
            var ambiguous = False
            var changed = 0
            for home in range(len(solids)):  # pragma: no branch
                for which in range(len(holes[home])):
                    var hole = holes[home][which]
                    var unassigned = True
                    for other in range(len(solids)):  # pragma: no branch
                        if is_point_inside_polygon(
                            points[hole][0], points[solids[other]]
                        ):
                            if home != other:
                                changed += 1
                            if unassigned:
                                unassigned = False
                                better[other].append(hole)
                            else:
                                ambiguous = True
                    if unassigned:
                        better[home].append(hole)
            if changed > 0 and not ambiguous:
                for home in range(len(solids)):  # pragma: no branch
                    holes[home] = better[home].copy()

        for home in range(len(solids)):  # pragma: no branch
            var shape = _shape(self.sub_paths[solids[home]])
            for which in range(len(holes[home])):
                shape.add_hole(_closed(self.sub_paths[holes[home][which]]))
            shapes.append(shape^)
        return shapes^
