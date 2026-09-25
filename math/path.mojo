# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An outline drawn out of curves, from three.js `src/extras/core/Path.js`,
`CurvePath.js` and `Shape.js`.

A `Path` is what a pen draws: it starts somewhere, and every call after
that leaves from where the last one stopped. `line_to`, `quadratic_to`,
`cubic_to` and `spline_thru` each add one `Curve` to the list, and
`close_path` adds the straight run back to the start. So a path is a list
of curves that meet end to end, which is exactly three.js's `CurvePath`.

`abs_arc` and `abs_ellipse` add an arc about a center given in the plane,
and `arc` and `ellipse` about one given from where the pen is. An arc need
not start where the pen is: as three.js's `absellipse` does, a straight
run is drawn to the arc's start first. On a path with nothing on it there
is nothing to join, so the path starts where the arc does, and the pen
need not be down.

A `Shape` is a closed path with holes in it: three.js's `Shape`, and what
`ShapeGeometry` and `ExtrudeGeometry` are built from. The holes are paths
too, and nothing about them says they are holes except where they are
kept.

## One run, not several

three.js lets `moveTo` be called again in the middle of a path, which
starts a second run with a gap between it and the first. Nothing here can
draw that: a shape is one outline with holes, and a broken outline has no
inside. So `move_to` is refused once the path has a curve on it, and a
second run has to be a second path. That is the same shape three.js's
`Shape.holes` has, said once rather than twice.

## What is refused

Drawing before the pen is put down. Moving the pen after it has drawn.
Closing a path that is already closed, or one with nothing on it.
Sampling a path with no curves. Each of those is a caller that has lost
track of the order, and three.js's silent answer to all of them is a
shape with no area.
"""

from math.curve import (
    ELLIPSE,
    LINE,
    SPLINE,
    Curve,
    cubic_bezier,
    line,
    quadratic_bezier,
    spline,
)
from math.vector2 import Vector2
from units.si import Angle, Length, METER, RADIAN


def resolution_of(curve: Curve, divisions: Int) -> Int:
    """Return how many runs `Path.sample` cuts one curve into.

    three.js's rule in `CurvePath.getPoints`, curve kind by curve kind:
    one for a line, `divisions` for each point of a spline, twice
    `divisions` for an ellipse, and `divisions` for anything else.

    Args:
        curve: The curve.
        divisions: The resolution the path was asked for.

    Returns:
        The runs, at least one.
    """
    if curve.kind == LINE:
        return 1
    if curve.kind == SPLINE:
        return divisions * len(curve.points)
    if curve.kind == ELLIPSE:
        return divisions * 2
    return divisions


struct Path(Copyable, Movable):
    """A run of curves that meet end to end."""

    var curves: List[Curve]
    var first: Vector2
    var last: Vector2
    var down: Bool

    def __init__(out self):
        """Create a path with the pen up and nothing drawn."""
        self.curves = List[Curve]()
        self.first = Vector2(0, 0)
        self.last = Vector2(0, 0)
        self.down = False

    def __init__(out self, start: Vector2):
        """Create a path with the pen down at `start`.

        Args:
            start: Where the path begins, in meters.
        """
        self.curves = List[Curve]()
        self.first = start
        self.last = start
        self.down = True

    def __init__(out self, *, copy: Self):
        """Copy another path."""
        self.curves = copy.curves.copy()
        self.first = copy.first
        self.last = copy.last
        self.down = copy.down

    def curve_count(self) -> Int:
        """Return how many curves the path is made of."""
        return len(self.curves)

    def current(self) -> Vector2:
        """Return where the pen is, in meters. It is the origin while the
        pen is still up."""
        return self.last

    def move_to(mut self, start: Vector2) raises:
        """Put the pen down at `start`.

        Args:
            start: Where the path begins, in meters.

        Raises:
            Error: If the path already has a curve on it. A path is one
                run, and a second run is a second path.
        """
        if len(self.curves) > 0:
            raise Error("A path cannot move once it has drawn")
        self.first = start
        self.last = start
        self.down = True

    def _pen(self) raises:
        """Raise unless the pen is down.

        Raises:
            Error: If nothing has put the pen down yet.
        """
        if not self.down:
            raise Error("A path must be moved to its start before it draws")

    def line_to(mut self, end: Vector2) raises:
        """Draw the straight run from where the pen is to `end`.

        Args:
            end: Where the run ends, in meters.

        Raises:
            Error: If the pen is up, or `end` is where the pen already is.
        """
        self._pen()
        self.curves.append(line(self.last, end))
        self.last = end

    def quadratic_to(mut self, control: Vector2, end: Vector2) raises:
        """Draw a Bezier curve with one control point to `end`.

        Args:
            control: The point the curve is pulled toward, in meters.
            end: Where the curve ends, in meters.

        Raises:
            Error: If the pen is up, or all three points are the same.
        """
        self._pen()
        self.curves.append(quadratic_bezier(self.last, control, end))
        self.last = end

    def cubic_to(
        mut self, first: Vector2, second: Vector2, end: Vector2
    ) raises:
        """Draw a Bezier curve with two control points to `end`.

        Args:
            first: The point the start is pulled toward, in meters.
            second: The point the end is pulled toward, in meters.
            end: Where the curve ends, in meters.

        Raises:
            Error: If the pen is up, or all four points are the same.
        """
        self._pen()
        self.curves.append(cubic_bezier(self.last, first, second, end))
        self.last = end

    def spline_thru(mut self, points: List[Vector2]) raises:
        """Draw a Catmull-Rom spline from where the pen is through every
        point of `points`.

        Args:
            points: The points the curve passes through, in meters, at
                least one of them. Where the pen is becomes the first
                point of the spline, as three.js's `splineThru` has it.

        Raises:
            Error: If the pen is up, if there are no points, or if every
                point is where the pen already is.
        """
        self._pen()
        if len(points) == 0:
            raise Error("A spline needs at least one point to go through")
        var through = List[Vector2]()
        through.append(self.last)
        for index in range(len(points)):  # pragma: no branch
            through.append(points[index])
        self.last = points[len(points) - 1]
        self.curves.append(spline(through^))

    def _add_ellipse(mut self, var curve: Curve) raises:
        """Add an ellipse to the path, joined to it by a straight run when
        it does not start where the pen is, three.js's `absellipse`.

        Raises:
            Error: If the joining run cannot be drawn, which cannot happen:
                it is drawn only between two points that differ.
        """
        var begin = curve.point(0)
        if len(self.curves) > 0:
            var gap = begin - self.last
            if gap.x != 0 or gap.y != 0:
                self.curves.append(line(self.last, begin))
        else:
            self.first = begin
        self.last = curve.point(1)
        self.down = True
        self.curves.append(curve^)

    def abs_ellipse(
        mut self,
        center: Vector2,
        x_radius: Length,
        y_radius: Length,
        start: Angle,
        end: Angle,
        clockwise: Bool = False,
        rotation: Angle = Angle(0, RADIAN),
    ) raises:
        """Draw an arc of an ellipse about `center`, three.js's
        `absellipse`.

        Args:
            center: The middle of the ellipse, in meters.
            x_radius: The radius along the ellipse's own x axis.
            y_radius: The radius along its own y axis.
            start: The angle the arc starts at, from the ellipse's own +x
                axis.
            end: The angle the arc ends at.
            clockwise: True to run clockwise from `start` to `end`.
            rotation: How far the ellipse's axes are turned, anticlockwise.

        Raises:
            Error: If either radius is not positive, or the two angles are
                the same.
        """
        self._add_ellipse(
            Curve(
                center=center,
                x_radius=x_radius,
                y_radius=y_radius,
                start=start,
                end=end,
                clockwise=clockwise,
                rotation=rotation,
            )
        )

    def abs_arc(
        mut self,
        center: Vector2,
        radius: Length,
        start: Angle,
        end: Angle,
        clockwise: Bool = False,
    ) raises:
        """Draw an arc of a circle about `center`, three.js's `absarc`.

        Args:
            center: The middle of the circle, in meters.
            radius: The circle's radius.
            start: The angle the arc starts at, from the +x axis.
            end: The angle the arc ends at.
            clockwise: True to run clockwise from `start` to `end`.

        Raises:
            Error: If the radius is not positive, or the two angles are the
                same.
        """
        self.abs_ellipse(center, radius, radius, start, end, clockwise)

    def ellipse(
        mut self,
        offset: Vector2,
        x_radius: Length,
        y_radius: Length,
        start: Angle,
        end: Angle,
        clockwise: Bool = False,
        rotation: Angle = Angle(0, RADIAN),
    ) raises:
        """Draw an arc of an ellipse whose center is `offset` from where
        the pen is, three.js's `ellipse`.

        Args:
            offset: The center, from where the pen is, in meters.
            x_radius: The radius along the ellipse's own x axis.
            y_radius: The radius along its own y axis.
            start: The angle the arc starts at, from the ellipse's own +x
                axis.
            end: The angle the arc ends at.
            clockwise: True to run clockwise from `start` to `end`.
            rotation: How far the ellipse's axes are turned, anticlockwise.

        Raises:
            Error: If either radius is not positive, or the two angles are
                the same.
        """
        self.abs_ellipse(
            self.last + offset,
            x_radius,
            y_radius,
            start,
            end,
            clockwise,
            rotation,
        )

    def arc(
        mut self,
        offset: Vector2,
        radius: Length,
        start: Angle,
        end: Angle,
        clockwise: Bool = False,
    ) raises:
        """Draw an arc of a circle whose center is `offset` from where the
        pen is, three.js's `arc`.

        Args:
            offset: The center, from where the pen is, in meters.
            radius: The circle's radius.
            start: The angle the arc starts at, from the +x axis.
            end: The angle the arc ends at.
            clockwise: True to run clockwise from `start` to `end`.

        Raises:
            Error: If the radius is not positive, or the two angles are the
                same.
        """
        self.abs_ellipse(
            self.last + offset, radius, radius, start, end, clockwise
        )

    def close_path(mut self) raises:
        """Draw the straight run from where the pen is back to the start.

        Raises:
            Error: If the path has nothing on it, or the pen is already at
                the start, which means the path is closed already.
        """
        if len(self.curves) == 0:
            raise Error("An empty path cannot be closed")
        var start = self.first
        self.line_to(start)

    def is_closed(self) -> Bool:
        """Return True if the path ends where it began."""
        if len(self.curves) == 0:
            return False
        var gap = self.last - self.first
        return gap.x == 0 and gap.y == 0

    def sample(self, divisions: Int) raises -> List[Vector2]:
        """Return the path as points, at three.js's resolution per curve.

        three.js's `CurvePath.getPoints`: a straight line is one run
        whatever `divisions` says, since more points along it would all be
        collinear; a spline is `divisions` runs for each point it passes
        through, since one curve of it may wind through dozens; and a
        Bezier is `divisions` runs, and an ellipse twice that. Cutting
        every curve into `divisions` runs instead, as this once did, gave
        a twenty-point spline twelve runs for the whole of it and missed
        most of its own points, and gave every straight edge eleven points
        it did not need.

        A curve's first point is where the one before it ended, so it is
        left out: the run is continuous, and a repeated point would be a
        segment of no length for whatever reads it.

        Args:
            divisions: How many runs to cut a Bezier curve into, and how
                many per point of a spline; at least one.

        Returns:
            The points, in meters, from the start of the first curve to
            the end of the last.

        Raises:
            Error: If the path has no curves, or `divisions` is less than
                one.
        """
        if len(self.curves) == 0:
            raise Error("A path with no curves has no points")
        if divisions < 1:
            raise Error("A path needs at least one division")
        var out = List[Vector2]()
        for index in range(len(self.curves)):  # pragma: no branch
            var piece = self.curves[index].sample(
                resolution_of(self.curves[index], divisions)
            )
            var start = 1
            if index == 0:
                start = 0
            for step in range(start, len(piece)):  # pragma: no branch
                out.append(piece[step])
        return out^

    def length(self) raises -> Length:
        """Return how long the whole path is.

        Returns:
            The sum of its curves' lengths.

        Raises:
            Error: If the path has no curves.
        """
        if len(self.curves) == 0:
            raise Error("A path with no curves has no length")
        var total = Float32(0)
        for index in range(len(self.curves)):  # pragma: no branch
            total += self.curves[index].length().to(METER)
        return Length(total, METER)


struct Shape(Copyable, Movable):
    """A closed outline with holes in it, three.js's `Shape`."""

    var outline: Path
    var holes: List[Path]
    # three.js's `uuid`, which a geometry names the shape by in JSON.
    # Empty until a JSON document gives one or a writer makes one.
    var uuid: String

    def __init__(out self, var outline: Path) raises:
        """Create a shape from its outline.

        Args:
            outline: The closed path around the outside.

        Raises:
            Error: If the outline is not closed. An open outline has no
                inside to fill.
        """
        if not outline.is_closed():
            raise Error("A shape needs a closed outline")
        self.outline = outline^
        self.holes = List[Path]()
        self.uuid = String()

    def __init__(out self, *, copy: Self):
        """Copy another shape."""
        self.outline = Path(copy=copy.outline)
        self.holes = copy.holes.copy()
        self.uuid = copy.uuid

    def add_hole(mut self, var hole: Path) raises:
        """Cut `hole` out of the shape.

        Args:
            hole: The closed path around the hole.

        Raises:
            Error: If the hole is not closed.
        """
        if not hole.is_closed():
            raise Error("A shape's hole must be closed")
        self.holes.append(hole^)

    def hole_count(self) -> Int:
        """Return how many holes the shape has."""
        return len(self.holes)

    def outline_points(self, divisions: Int) raises -> List[Vector2]:
        """Return the outline as points, at `Path.sample`'s resolution.

        Args:
            divisions: How many runs to cut a curve into; see
                `Path.sample`. At least one.

        Returns:
            The points, in meters, the last of them the first again
            because the outline is closed.

        Raises:
            Error: If `divisions` is less than one.
        """
        return self.outline.sample(divisions)

    def hole_points(self, index: Int, divisions: Int) raises -> List[Vector2]:
        """Return one hole as points, at `Path.sample`'s resolution.

        Args:
            index: Which hole, from zero.
            divisions: How many runs to cut a curve into; see
                `Path.sample`. At least one.

        Returns:
            The points, in meters, the last of them the first again.

        Raises:
            Error: If there is no such hole, or `divisions` is less than
                one.
        """
        if index < 0 or index >= len(self.holes):
            raise Error("A shape has no hole at that index")
        return self.holes[index].sample(divisions)
