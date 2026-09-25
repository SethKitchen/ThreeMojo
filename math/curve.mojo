# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A curve in the plane, from three.js `src/extras/core/Curve.js` and the
curve classes beside it.

A curve is a function from a number between zero and one to a point. That
is all three.js's `Curve` is, and every class under it -- `LineCurve`,
`QuadraticBezierCurve`, `CubicBezierCurve`, `SplineCurve` -- differs only
in which function. So here there is one struct and a kind, for the reason
`Material` is one struct and a kind: a `Path` has to hold a list of one
type, and Mojo gives no cheap list of a trait.

The five kinds are the five three.js draws with:

    LINE       two points, and the straight run between them
    QUADRATIC  a start, one control point and an end
    CUBIC      a start, two control points and an end
    SPLINE     any number of points, and a curve through every one
    ELLIPSE    a center, two radii and the angles the arc runs between

The first three are Bezier curves, written as the weighted sums they are.
The fourth is three.js's `SplineCurve`: a Catmull-Rom spline, which passes
*through* its points rather than being pulled toward them, with the ends
handled by repeating the first and last point. The fifth is three.js's
`EllipseCurve`, and `ArcCurve` is the same curve with its two radii equal.

## Two parameters, not one

`point` takes `t`, which runs from zero to one over the curve's own
formula. It is not distance. A Bezier with its control points bunched at
one end crawls there and races at the other, so equal steps in `t` are not
equal steps along the curve.

`point_at` takes `u`, which runs from zero to one over the curve's
*length*. It is what an animation along a path wants, and what a tube
swept along a curve wants, because equal steps in `u` are equal distances.
three.js has the same pair, and builds the second from the first the same
way: sample the curve, add up the straight runs between the samples, and
look `u` up in that table.

That table is an approximation, and it is the only approximation here. How
good it is depends on there being enough samples to follow the curve, and
that is the one thing a fixed count cannot promise.

three.js uses 200 samples for every curve it has. A Bezier has one arc and
200 samples follow it closely. A spline has one arc *per segment*, and a
spline with more segments than the table has samples is not sampled
sparsely -- it is sampled at the wrong places. Take 401 control points
that step left and right by a meter while climbing steadily: 200 samples
land on every second one, all of them on the same side, and the table
reports four meters for a curve more than four hundred meters long. Every
distance `point_at` and `spaced_points` give is then wrong by the same
hundredfold.

So the count is `ARC_DIVISIONS` or `SEGMENT_SAMPLES` per segment,
whichever is larger. That is still an approximation, and the docstrings
say so rather than promising a figure.

## An ellipse, and the way it goes round

An ellipse is not a set of points, so it keeps its own numbers: its radii,
the angle it starts at, the signed angle it sweeps, and how far it is
turned. The sweep is worked out once, when the curve is made, by
three.js's `EllipseCurve.getPoint` rule: bring the difference between the
two angles into zero through a whole turn, call a difference of nothing
there a whole turn, and take a whole turn off it for a clockwise arc.

A whole turn ends where it starts. In double precision three.js lands a
few parts in 10^16 away; in single precision the gap is near a part in
10^7, and a circle drawn as a shape's outline would not close. So at the
end of a whole turn the point is the starting point again, exactly.

## What is refused

A curve whose control points do not match its kind: a line needs two, a
quadratic three, a cubic four, a spline at least two. A curve whose points
are all the same point, which is not a curve and has no direction. An
ellipse with a radius that is not positive, or whose two angles are the
same, which three.js draws as a single point. A `t`
or a `u` outside zero through one, which three.js clamps silently and
which here says the caller has computed something wrong.
"""

from math.vector2 import Vector2
from std.math import cos, floor, pi, sin
from units.si import Angle, Length, METER, RADIAN

# The fewest straight runs that stand in for a curve when its length is
# measured. three.js's `ARC_LENGTH_DIVISIONS`, and enough for a curve with
# one arc in it.
comptime ARC_DIVISIONS = 200

# How many runs each segment of a spline gets, whatever the total comes to.
# A spline has an arc per segment, and a table with fewer samples than the
# curve has segments does not measure it at all.
comptime SEGMENT_SAMPLES = 8

# One whole turn, in radians.
comptime WHOLE_TURN = Float32(2 * pi)

# Below this two angles are the same angle. three.js compares against
# `Number.EPSILON`, a double's last bit; this is the same bit of a `Float32`.
comptime SAME_ANGLE = Float32(1.1920929e-7)


@fieldwise_init
struct CurveKind(Equatable, ImplicitlyCopyable, Writable):
    """Which function a curve is, as a type rather than a bare int.

    The same argument as `materials.material.MaterialKind`: a bare `Int`
    accepted anything, and four small integers that mean four different
    things should not be interchangeable. The type stops a bare integer at
    compile time, and `Curve.__init__` stops `CurveKind(9)` with
    `is_valid`.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the four kinds there are."""
        return (
            self == LINE
            or self == QUADRATIC
            or self == CUBIC
            or self == SPLINE
            or self == ELLIPSE
        )

    def control_count(self) -> Int:
        """Return how many points a curve of this kind takes, or zero for
        `SPLINE`, which takes any number from two up.

        Returns:
            Two for `LINE`, three for `QUADRATIC`, four for `CUBIC`, one
            for `ELLIPSE`, which keeps its center there, and zero for
            `SPLINE`. Zero for a kind that is not valid, which
            `Curve.__init__` has already refused.
        """
        if self == LINE:
            return 2
        if self == QUADRATIC:
            return 3
        if self == CUBIC:
            return 4
        if self == ELLIPSE:
            return 1
        return 0


# A straight run from the first point to the second.
comptime LINE = CurveKind(0)
# A Bezier with one control point: three.js's `QuadraticBezierCurve`.
comptime QUADRATIC = CurveKind(1)
# A Bezier with two control points: three.js's `CubicBezierCurve`.
comptime CUBIC = CurveKind(2)
# A Catmull-Rom spline through every point: three.js's `SplineCurve`.
comptime SPLINE = CurveKind(3)
# An arc of an ellipse about a center: three.js's `EllipseCurve`, and its
# `ArcCurve` when the two radii are equal.
comptime ELLIPSE = CurveKind(4)


def ellipse_sweep(start: Angle, end: Angle, clockwise: Bool) raises -> Float32:
    """Return the signed angle an ellipse runs through from `start` to
    `end`, in radians, by three.js's `EllipseCurve.getPoint` rule.

    The difference is brought into zero through a whole turn. A difference
    of nothing there, from two angles that were not the same, is a whole
    turn. A clockwise arc then has a whole turn taken off it, so it runs
    the other way round.

    Args:
        start: The angle the arc starts at, from the +x axis.
        end: The angle the arc ends at.
        clockwise: True to run clockwise, the way the angle falls.

    Returns:
        The sweep: from zero up to a whole turn anticlockwise, and from
        zero down to minus a whole turn clockwise. Never zero.

    Raises:
        Error: If the two angles are the same, which three.js draws as a
            single point.
    """
    var delta = end.to(RADIAN) - start.to(RADIAN)
    if abs(delta) < SAME_ANGLE:
        raise Error("An ellipse needs two different angles")
    while delta < 0:
        delta += WHOLE_TURN
    while delta > WHOLE_TURN:
        delta -= WHOLE_TURN
    if delta < SAME_ANGLE:
        delta = WHOLE_TURN
    if clockwise:
        if delta == WHOLE_TURN:
            delta = -WHOLE_TURN
        else:
            delta = delta - WHOLE_TURN
    return delta


def _catmull_rom(
    t: Float32, p0: Float32, p1: Float32, p2: Float32, p3: Float32
) -> Float32:
    """Return one component of a Catmull-Rom spline between `p1` and `p2`.

    three.js's `CatmullRom` in `src/extras/core/Interpolations.js`, with a
    tension of one half: the direction at `p1` is half the run from `p0` to
    `p2`, and the direction at `p2` is half the run from `p1` to `p3`.

    Args:
        t: How far between `p1` and `p2`, from zero to one.
        p0: The component of the point before the segment.
        p1: The component of the point the segment starts at.
        p2: The component of the point the segment ends at.
        p3: The component of the point after the segment.

    Returns:
        The component at `t`.
    """
    var v0 = (p2 - p0) * Float32(0.5)
    var v1 = (p3 - p1) * Float32(0.5)
    var t2 = t * t
    var t3 = t * t2
    var cubic = (2 * p1 - 2 * p2 + v0 + v1) * t3
    var square = (-3 * p1 + 3 * p2 - 2 * v0 - v1) * t2
    return cubic + square + v0 * t + p1


def _catmull_rom_slope(
    t: Float32, p0: Float32, p1: Float32, p2: Float32, p3: Float32
) -> Float32:
    """Return one component of the Catmull-Rom segment's slope at `t`.

    The derivative of `_catmull_rom`, term by term. It is with respect to
    the segment's own parameter rather than the whole curve's, which is a
    constant factor and changes no direction.

    Args:
        t: How far between `p1` and `p2`, from zero to one.
        p0: The component of the point before the segment.
        p1: The component of the point the segment starts at.
        p2: The component of the point the segment ends at.
        p3: The component of the point after the segment.

    Returns:
        The slope at `t`.
    """
    var v0 = (p2 - p0) * Float32(0.5)
    var v1 = (p3 - p1) * Float32(0.5)
    var cubic = 3 * (2 * p1 - 2 * p2 + v0 + v1) * t * t
    var square = 2 * (-3 * p1 + 3 * p2 - 2 * v0 - v1) * t
    return cubic + square + v0


def u_to_t(table: List[Float32], u: Float32) -> Float32:
    """Return the `t` at which a curve has run `u` of its length.

    three.js's `getUtoTmapping`: find the two samples the distance falls
    between, and place `u` between their two `t` values in proportion to
    how far it lies between their two distances.

    It takes the table rather than reading it off a curve so that the one
    case a curve cannot easily be made to show -- two samples at the same
    distance, where the curve stands still -- can be given to it directly.
    Such a pair leaves `t` at the earlier sample rather than dividing by a
    span of zero.

    Args:
        table: How far along each sample is, from zero, rising. The caller
            has built it with `Curve.lengths`, so it holds at least two
            entries and starts at zero.
        u: How far along by length, from zero through one.

    Returns:
        The parameter at that distance, from zero through one.
    """
    var last = len(table) - 1
    var target = u * table[last]
    var index = 1
    for step in range(1, last + 1):  # pragma: no branch
        index = step
        if table[step] >= target:
            break
    var span = table[index] - table[index - 1]
    var within = Float32(0)
    if span > 0:
        within = (target - table[index - 1]) / span
    return (Float32(index - 1) + within) / Float32(last)


struct Curve(Copyable, Movable):
    """One curve in the plane: a kind, and the points that kind reads.

    An `ELLIPSE` keeps its center as its one point, and its other numbers
    in the four fields below. Every other kind leaves those at zero.
    """

    var kind: CurveKind
    var points: List[Vector2]
    # An ellipse's radius along its own x and y axes, in meters.
    var radii: Vector2
    # The angle an ellipse starts at, in radians from its own +x axis.
    var start: Float32
    # The signed angle an ellipse runs through, in radians; see
    # `ellipse_sweep`.
    var sweep: Float32
    # How far an ellipse's own axes are turned from the plane's, in
    # radians, anticlockwise.
    var rotation: Float32
    # The angle an ellipse ends at and which way it runs, as it was given:
    # three.js's `aEndAngle` and `aClockwise`, which its JSON carries.
    var end: Float32
    var clockwise: Bool

    def __init__(out self, kind: CurveKind, var points: List[Vector2]) raises:
        """Create a curve of `kind` through or around `points`.

        Args:
            kind: Which function the curve is.
            points: Its control points, in meters, in order.

        Raises:
            Error: If the kind is not one of the five, if it is `ELLIPSE`,
                which takes radii and angles rather than points, if the
                number of points does not match the kind, or if every point
                is the same point, which has no direction anywhere.
        """
        if not kind.is_valid():
            raise Error("A curve needs a kind that exists")
        if kind == ELLIPSE:
            raise Error("An ellipse is made with its radii and angles")
        var wanted = kind.control_count()
        if wanted == 0:
            if len(points) < 2:
                raise Error("A spline needs at least two points")
        elif len(points) != wanted:
            raise Error("A curve's points must match its kind")
        var moved = False
        for index in range(1, len(points)):  # pragma: no branch
            var step = points[index] - points[0]
            if step.x != 0 or step.y != 0:
                moved = True
        if not moved:
            raise Error("A curve needs two points that differ")
        self.kind = kind
        self.points = points^
        self.radii = Vector2(0, 0)
        self.start = 0
        self.sweep = 0
        self.rotation = 0
        self.end = 0
        self.clockwise = False

    def __init__(
        out self,
        *,
        center: Vector2,
        x_radius: Length,
        y_radius: Length,
        start: Angle,
        end: Angle,
        clockwise: Bool,
        rotation: Angle,
    ) raises:
        """Create an arc of an ellipse, three.js's `EllipseCurve`.

        Args:
            center: The middle of the ellipse, in meters.
            x_radius: The radius along the ellipse's own x axis.
            y_radius: The radius along its own y axis.
            start: The angle the arc starts at, from the ellipse's own +x
                axis.
            end: The angle the arc ends at.
            clockwise: True to run clockwise from `start` to `end`.
            rotation: How far the ellipse's axes are turned from the
                plane's, anticlockwise.

        Raises:
            Error: If either radius is not positive, or if the two angles
                are the same.
        """
        if x_radius.value <= 0 or y_radius.value <= 0:
            raise Error("An ellipse needs two positive radii")
        self.kind = ELLIPSE
        self.points = [center]
        self.radii = Vector2(x_radius.to(METER), y_radius.to(METER))
        self.start = start.to(RADIAN)
        self.sweep = ellipse_sweep(start, end, clockwise)
        self.rotation = rotation.to(RADIAN)
        self.end = end.to(RADIAN)
        self.clockwise = clockwise

    def __init__(out self, *, copy: Self):
        """Copy another curve."""
        self.kind = copy.kind
        self.points = copy.points.copy()
        self.radii = copy.radii
        self.start = copy.start
        self.sweep = copy.sweep
        self.rotation = copy.rotation
        self.end = copy.end
        self.clockwise = copy.clockwise

    def _ellipse_angle(self, t: Float32) -> Float32:
        """Return the angle an ellipse has reached at `t`.

        At the end of a whole turn it is the start again, so a full circle
        ends exactly where it began rather than a rounding error away.
        """
        var turn = t * self.sweep
        if t == 1 and abs(self.sweep) == WHOLE_TURN:
            turn = 0
        return self.start + turn

    def _ellipse_point(self, t: Float32) -> Vector2:
        """Return the point at `t` on an ellipse, three.js's
        `EllipseCurve.getPoint`: round the ellipse's own axes, then turned
        about its center when it is turned at all."""
        var center = self.points[0]
        var angle = self._ellipse_angle(t)
        var x = center.x + self.radii.x * cos(angle)
        var y = center.y + self.radii.y * sin(angle)
        if self.rotation != 0:
            var c = cos(self.rotation)
            var s = sin(self.rotation)
            var tx = x - center.x
            var ty = y - center.y
            x = tx * c - ty * s + center.x
            y = tx * s + ty * c + center.y
        return Vector2(x, y)

    def _ellipse_slope(self, t: Float32) -> Vector2:
        """Return the derivative of `_ellipse_point` at `t`: the sweep times
        the direction round the ellipse, turned with it."""
        var angle = self._ellipse_angle(t)
        var dx = -self.radii.x * sin(angle) * self.sweep
        var dy = self.radii.y * cos(angle) * self.sweep
        var c = cos(self.rotation)
        var s = sin(self.rotation)
        return Vector2(dx * c - dy * s, dx * s + dy * c)

    def point(self, t: Float32) raises -> Vector2:
        """Return the point at `t` along this curve's own parameter.

        Args:
            t: Where on the curve, from zero at the start to one at the
                end. It is not a distance; see `point_at`.

        Returns:
            The point, in meters.

        Raises:
            Error: If `t` falls outside zero through one.
        """
        if t < 0 or t > 1:
            raise Error("A curve's t must lie from zero through one")
        if self.kind == LINE:
            # three.js's `LineCurve.getPoint`: the end itself at one, so a
            # closed path ends exactly where it began.
            if t == 1:
                return self.points[1]
            return (self.points[1] - self.points[0]) * t + self.points[0]
        var rest = 1 - t
        if self.kind == QUADRATIC:
            return (
                self.points[0] * (rest * rest)
                + self.points[1] * (2 * rest * t)
                + self.points[2] * (t * t)
            )
        if self.kind == CUBIC:
            return (
                self.points[0] * (rest * rest * rest)
                + self.points[1] * (3 * rest * rest * t)
                + self.points[2] * (3 * rest * t * t)
                + self.points[3] * (t * t * t)
            )
        if self.kind == ELLIPSE:
            return self._ellipse_point(t)
        return self._spline_point(t)

    def _spline_segment(self, t: Float32) -> Int:
        """Return which of the spline's segments `t` falls in.

        The last point belongs to the segment before it rather than
        starting one of its own, which is what keeps `t` of one on the
        curve instead of one point past its end.
        """
        var last = len(self.points) - 1
        var segment = Int(floor(Float32(last) * t))
        if segment > last - 1:
            segment = last - 1
        return segment

    def _spline_point(self, t: Float32) -> Vector2:
        """Return the point at `t` on a Catmull-Rom spline through every
        point, three.js's `SplineCurve.getPoint`.

        The parameter is split into which segment and how far along it. The
        segment's own ends are two of the points, and the two beyond them
        give it its directions, with the first and last point repeated
        where there is nothing beyond.
        """
        var last = len(self.points) - 1
        var segment = self._spline_segment(t)
        var weight = Float32(last) * t - Float32(segment)
        var before = self.points[max(segment - 1, 0)]
        var start = self.points[segment]
        var end = self.points[segment + 1]
        var after = self.points[min(segment + 2, last)]
        return Vector2(
            _catmull_rom(weight, before.x, start.x, end.x, after.x),
            _catmull_rom(weight, before.y, start.y, end.y, after.y),
        )

    def _spline_slope(self, t: Float32) -> Vector2:
        """Return the direction a Catmull-Rom spline runs in at `t`, of
        whatever length the derivative gives it."""
        var last = len(self.points) - 1
        var segment = self._spline_segment(t)
        var weight = Float32(last) * t - Float32(segment)
        var before = self.points[max(segment - 1, 0)]
        var start = self.points[segment]
        var end = self.points[segment + 1]
        var after = self.points[min(segment + 2, last)]
        return Vector2(
            _catmull_rom_slope(weight, before.x, start.x, end.x, after.x),
            _catmull_rom_slope(weight, before.y, start.y, end.y, after.y),
        )

    def _slope(self, t: Float32) -> Vector2:
        """Return how fast and which way the curve moves at `t`, before it
        is made unit length. The caller has checked `t` is on the curve."""
        if self.kind == LINE:
            return self.points[1] - self.points[0]
        var rest = 1 - t
        if self.kind == QUADRATIC:
            return (self.points[1] - self.points[0]) * (2 * rest) + (
                self.points[2] - self.points[1]
            ) * (2 * t)
        if self.kind == CUBIC:
            return (
                (self.points[1] - self.points[0]) * (3 * rest * rest)
                + (self.points[2] - self.points[1]) * (6 * rest * t)
                + (self.points[3] - self.points[2]) * (3 * t * t)
            )
        if self.kind == ELLIPSE:
            return self._ellipse_slope(t)
        return self._spline_slope(t)

    def tangent(self, t: Float32) raises -> Vector2:
        """Return the unit direction the curve runs in at `t`.

        Every kind here but the ellipse is a polynomial, so its derivative
        is another polynomial and the direction is exact. The ellipse's
        derivative is its sine and cosine swapped, which is exact too. three.js measures the same
        thing across two samples a short step apart, which it can afford
        because its numbers are double precision. In single precision that
        subtraction cancels most of the digits it has, and the answer is
        good to about four decimals rather than to the last bit.

        Being exact means a cusp is exact too. A quadratic that starts and
        ends at one point turns back on itself half way along, and its
        derivative there is zero rather than nearly zero. There is no
        direction at such a point, and this says so.

        Args:
            t: Where on the curve, from zero through one.

        Returns:
            The direction, of unit length.

        Raises:
            Error: If `t` falls outside zero through one, or if the curve
                turns back on itself at `t` and has no direction there.
        """
        if t < 0 or t > 1:
            raise Error("A curve's t must lie from zero through one")
        var slope = self._slope(t)
        if slope.length() == 0:
            raise Error("A curve has no direction where it turns back")
        slope.normalize()
        return slope

    def sample(self, divisions: Int) raises -> List[Vector2]:
        """Return `divisions + 1` points at equal steps in `t`.

        Args:
            divisions: How many runs to cut the curve into; at least one.

        Returns:
            The points, first to last, in meters.

        Raises:
            Error: If `divisions` is less than one.
        """
        if divisions < 1:
            raise Error("A curve needs at least one division")
        var out = List[Vector2]()
        for index in range(divisions + 1):  # pragma: no branch
            out.append(self.point(Float32(index) / Float32(divisions)))
        return out^

    def lengths(self, divisions: Int) raises -> List[Float32]:
        """Return how far along the curve each sample is, from zero.

        Args:
            divisions: How many runs to cut the curve into; at least one.

        Returns:
            `divisions + 1` distances in meters, the first zero and the
            last the curve's whole length.

        Raises:
            Error: If `divisions` is less than one.
        """
        var samples = self.sample(divisions)
        var out = List[Float32]()
        out.append(0)
        for index in range(1, len(samples)):  # pragma: no branch
            var step = (samples[index] - samples[index - 1]).length()
            out.append(out[index - 1] + step)
        return out^

    def arc_divisions(self) -> Int:
        """Return how many straight runs stand in for this curve when its
        length is measured.

        `ARC_DIVISIONS` for a curve with one arc in it, and at least
        `SEGMENT_SAMPLES` for each segment of a spline, which has an arc
        apiece. A table with fewer samples than the curve has segments
        lands on the same part of every segment and measures a curve that
        is not there.

        Returns:
            The number of runs, never fewer than `ARC_DIVISIONS`.
        """
        if self.kind == SPLINE:
            var wanted = (len(self.points) - 1) * SEGMENT_SAMPLES
            if wanted > ARC_DIVISIONS:
                return wanted
        return ARC_DIVISIONS

    def length(self) raises -> Length:
        """Return how long the curve is, measured across the straight runs
        `arc_divisions` asks for.

        Returns:
            The length, which is an approximation from below: a curve is at
            least as long as any set of chords across it.

        Raises:
            Error: If a sample falls outside the curve, which cannot
                happen for a curve that was constructed.
        """
        var divisions = self.arc_divisions()
        var table = self.lengths(divisions)
        return Length(table[divisions], METER)

    def point_at(self, u: Float32) raises -> Vector2:
        """Return the point `u` of the way along the curve by distance.

        Args:
            u: How far along by length, from zero through one.

        Returns:
            The point, in meters.

        Raises:
            Error: If `u` falls outside zero through one.
        """
        if u < 0 or u > 1:
            raise Error("A curve's u must lie from zero through one")
        return self.point(u_to_t(self.lengths(self.arc_divisions()), u))

    def tangent_at(self, u: Float32) raises -> Vector2:
        """Return the unit direction `u` of the way along the curve by
        distance, three.js's `getTangentAt`.

        Args:
            u: How far along by length, from zero through one.

        Returns:
            The direction, of unit length.

        Raises:
            Error: If `u` falls outside zero through one, or if the curve
                turns back on itself there.
        """
        if u < 0 or u > 1:
            raise Error("A curve's u must lie from zero through one")
        return self.tangent(u_to_t(self.lengths(self.arc_divisions()), u))

    def spaced_points(self, divisions: Int) raises -> List[Vector2]:
        """Return `divisions + 1` points at equal distances along the curve.

        Args:
            divisions: How many equal runs to cut the curve into; at least
                one.

        Returns:
            The points, first to last, in meters.

        Raises:
            Error: If `divisions` is less than one.
        """
        if divisions < 1:
            raise Error("A curve needs at least one division")
        # One table for the whole call. `point_at` builds its own, and
        # asking it once per point rebuilt the same hundreds of samples for
        # every point returned.
        var table = self.lengths(self.arc_divisions())
        var out = List[Vector2]()
        for index in range(divisions + 1):  # pragma: no branch
            var u = Float32(index) / Float32(divisions)
            out.append(self.point(u_to_t(table, u)))
        return out^


def line(start: Vector2, end: Vector2) raises -> Curve:
    """Return the straight run from `start` to `end`.

    Args:
        start: Where the run begins, in meters.
        end: Where it ends, in meters.

    Returns:
        A `LINE` curve.

    Raises:
        Error: If the two points are the same point.
    """
    return Curve(LINE, [start, end])


def quadratic_bezier(
    start: Vector2, control: Vector2, end: Vector2
) raises -> Curve:
    """Return a Bezier curve with one control point.

    Args:
        start: Where the curve begins, in meters.
        control: The point the curve is pulled toward, in meters.
        end: Where the curve ends, in meters.

    Returns:
        A `QUADRATIC` curve.

    Raises:
        Error: If all three points are the same point.
    """
    return Curve(QUADRATIC, [start, control, end])


def cubic_bezier(
    start: Vector2, first: Vector2, second: Vector2, end: Vector2
) raises -> Curve:
    """Return a Bezier curve with two control points.

    Args:
        start: Where the curve begins, in meters.
        first: The point the start is pulled toward, in meters.
        second: The point the end is pulled toward, in meters.
        end: Where the curve ends, in meters.

    Returns:
        A `CUBIC` curve.

    Raises:
        Error: If all four points are the same point.
    """
    return Curve(CUBIC, [start, first, second, end])


def spline(var points: List[Vector2]) raises -> Curve:
    """Return a Catmull-Rom spline through every point.

    Args:
        points: The points the curve passes through, in meters, at least
            two of them.

    Returns:
        A `SPLINE` curve.

    Raises:
        Error: If there are fewer than two points, or every point is the
            same point.
    """
    return Curve(SPLINE, points^)


def ellipse(
    center: Vector2,
    x_radius: Length,
    y_radius: Length,
    start: Angle,
    end: Angle,
    clockwise: Bool = False,
    rotation: Angle = Angle(0, RADIAN),
) raises -> Curve:
    """Return an arc of an ellipse, three.js's `EllipseCurve`.

    Args:
        center: The middle of the ellipse, in meters.
        x_radius: The radius along the ellipse's own x axis.
        y_radius: The radius along its own y axis.
        start: The angle the arc starts at, from the ellipse's own +x axis.
        end: The angle the arc ends at.
        clockwise: True to run clockwise from `start` to `end`.
        rotation: How far the ellipse's axes are turned, anticlockwise.

    Returns:
        An `ELLIPSE` curve.

    Raises:
        Error: If either radius is not positive, or the two angles are the
            same.
    """
    return Curve(
        center=center,
        x_radius=x_radius,
        y_radius=y_radius,
        start=start,
        end=end,
        clockwise=clockwise,
        rotation=rotation,
    )


def arc(
    center: Vector2,
    radius: Length,
    start: Angle,
    end: Angle,
    clockwise: Bool = False,
) raises -> Curve:
    """Return an arc of a circle, three.js's `ArcCurve`: an ellipse with
    its two radii equal and no turn.

    Args:
        center: The middle of the circle, in meters.
        radius: The circle's radius.
        start: The angle the arc starts at, from the +x axis.
        end: The angle the arc ends at.
        clockwise: True to run clockwise from `start` to `end`.

    Returns:
        An `ELLIPSE` curve.

    Raises:
        Error: If the radius is not positive, or the two angles are the
            same.
    """
    return ellipse(center, radius, radius, start, end, clockwise)
