# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The outlines an SVG file draws, in three.js's own terms: `ShapePath`,
`Path` and the four curves `SVGLoader` makes.

`loaders.svg` reads a file into `SvgShapePath`s, and `loaders.svg_shapes`
turns them into shapes and strokes. This module holds the outlines
themselves, and the 2D transform that places them.

**Why not `math.path`.** The `Path` and `Curve` there are built for
geometry, and refuse what an SVG file draws every day: a line of no
length, a second `moveTo`, an outline that is not closed. three.js keeps
all of these, and its `createShapes` and `pointsToStroke` read them. So
these types keep them too, in the `Float64` three.js computes in.
`SvgShape.to_shape` gives a `math.path.Shape` for `shape_geometry`.

**Units.** An SVG coordinate is a user unit, a number with no length.
three.js uses it as a world unit, and so does this port. An angle is in
radians.

**Arithmetic.** `SvgCurve.point` is three.js's `getPoint` for each curve,
term for term. `SvgSubPath.get_points` is `CurvePath.getPoints`, and
`SvgMatrix` is `Matrix3`, with the same element order.
"""

from math.curve import CUBIC, ELLIPSE, LINE, QUADRATIC, Curve, CurveKind
from math.path import Path, Shape
from math.vector2 import Vector2
from render.framebuffer import FloatColor
from std.math import atan2, cos, nan, pi, sin, sqrt
from units.si import Angle, Length, METER, RADIAN

# A point or a direction in the plane, in user units: x, then y.
comptime SvgVector = SIMD[DType.float64, 2]
# JavaScript's `Number.EPSILON`.
comptime JS_EPSILON = Float64(2.220446049250313e-16)
# One whole turn, in radians.
comptime TWO_PI = Float64(2 * pi)


def same_point(a: SvgVector, b: SvgVector) -> Bool:
    """Return True if two points are equal, three.js's `Vector2.equals`.

    Args:
        a: One point.
        b: The other.

    Returns:
        Whether x and y are both equal.
    """
    return a[0] == b[0] and a[1] == b[1]


struct SvgCurve(Copyable, Movable):
    """One curve of an outline: three.js's `LineCurve`,
    `QuadraticBezierCurve`, `CubicBezierCurve` or `EllipseCurve`.

    A Bezier or a line keeps its points in `points`. An ellipse keeps its
    center in `points[0]` and the rest in the fields below, as three.js's
    `aX`, `aY`, `xRadius`, `yRadius`, `aStartAngle`, `aEndAngle`,
    `aClockwise` and `aRotation`.
    """

    var kind: CurveKind
    var points: List[SvgVector]
    var x_radius: Float64
    var y_radius: Float64
    # Radians.
    var start_angle: Float64
    var end_angle: Float64
    var clockwise: Bool
    var rotation: Float64

    def __init__(out self, kind: CurveKind, var points: List[SvgVector]):
        """Make a line or a Bezier curve.

        Args:
            kind: `LINE`, `QUADRATIC` or `CUBIC`.
            points: Two, three or four points.
        """
        self.kind = kind
        self.points = points^
        self.x_radius = 0
        self.y_radius = 0
        self.start_angle = 0
        self.end_angle = 0
        self.clockwise = False
        self.rotation = 0

    def __init__(
        out self,
        center: SvgVector,
        x_radius: Float64,
        y_radius: Float64,
        start_angle: Float64,
        end_angle: Float64,
        clockwise: Bool,
        rotation: Float64,
    ):
        """Make an arc of an ellipse, three.js's `EllipseCurve`.

        Args:
            center: The center.
            x_radius: The radius along the ellipse's own x axis.
            y_radius: The radius along its own y axis.
            start_angle: Where the arc starts, in radians.
            end_angle: Where it ends, in radians.
            clockwise: True to run clockwise.
            rotation: How far the axes turn, in radians, counterclockwise.
        """
        self.kind = ELLIPSE
        self.points = [center]
        self.x_radius = x_radius
        self.y_radius = y_radius
        self.start_angle = start_angle
        self.end_angle = end_angle
        self.clockwise = clockwise
        self.rotation = rotation

    def check(self) raises:
        """Refuse a curve whose kind or points do not match.

        Raises:
            Error: If the kind is not `LINE`, `QUADRATIC`, `CUBIC` or
                `ELLIPSE`, or the number of points is not the kind's.
        """
        var wanted = 1
        if self.kind == LINE:
            wanted = 2
        elif self.kind == QUADRATIC:
            wanted = 3
        elif self.kind == CUBIC:
            wanted = 4
        elif self.kind != ELLIPSE:
            raise Error("SVG: a curve of a kind an outline does not use")
        if len(self.points) != wanted:
            raise Error("SVG: a curve's points do not match its kind")

    def point(self, t: Float64) raises -> SvgVector:
        """Return the point at `t`, three.js's `getPoint`.

        Args:
            t: From zero at the start to one at the end.

        Returns:
            The point.

        Raises:
            Error: If `check` refuses the curve.
        """
        self.check()
        ref p = self.points
        if self.kind == LINE:
            if t == 1:
                return p[1]
            return (p[1] - p[0]) * t + p[0]
        if self.kind == QUADRATIC:
            var k = 1 - t
            return k * k * p[0] + 2 * (1 - t) * t * p[1] + t * t * p[2]
        if self.kind == CUBIC:
            var k = 1 - t
            return (
                k * k * k * p[0]
                + 3 * k * k * t * p[1]
                + 3 * (1 - t) * t * t * p[2]
                + t * t * t * p[3]
            )
        return self._ellipse_point(t)

    def _ellipse_point(self, t: Float64) -> SvgVector:
        """Return the point at `t` on an ellipse, `EllipseCurve.getPoint`."""
        var delta = self.end_angle - self.start_angle
        var same = abs(delta) < JS_EPSILON
        while delta < 0:
            delta += TWO_PI
        while delta > TWO_PI:
            delta -= TWO_PI
        if delta < JS_EPSILON:
            delta = TWO_PI
            if same:
                delta = 0
        var turn_back = self.clockwise and not same
        if turn_back:
            if delta == TWO_PI:
                delta = -TWO_PI
            else:
                delta = delta - TWO_PI
        var angle = self.start_angle + t * delta
        var center = self.points[0]
        var x = center[0] + self.x_radius * cos(angle)
        var y = center[1] + self.y_radius * sin(angle)
        if self.rotation != 0:
            var c = cos(self.rotation)
            var s = sin(self.rotation)
            var tx = x - center[0]
            var ty = y - center[1]
            x = tx * c - ty * s + center[0]
            y = tx * s + ty * c + center[1]
        return SvgVector(x, y)

    def resolution(self, divisions: Int) -> Int:
        """Return how many runs `CurvePath.getPoints` cuts this curve into.

        Args:
            divisions: The path's divisions.

        Returns:
            One for a line, twice `divisions` for an ellipse, and
            `divisions` for a Bezier curve.
        """
        if self.kind == LINE:
            return 1
        if self.kind == ELLIPSE:
            return divisions * 2
        return divisions

    def get_points(self, divisions: Int) raises -> List[SvgVector]:
        """Return `divisions + 1` points at equal steps of `t`, three.js's
        `Curve.getPoints`.

        Args:
            divisions: How many runs; at least one.

        Returns:
            The points.

        Raises:
            Error: If `divisions` is below one, or `check` refuses the
                curve.
        """
        if divisions < 1:
            raise Error("SVG: a curve needs at least one division")
        var out = List[SvgVector]()
        for d in range(divisions + 1):  # pragma: no branch
            out.append(self.point(Float64(d) / Float64(divisions)))
        return out^

    def to_curve(self) raises -> Curve:
        """Return this curve as a `math.curve.Curve`, in `Float32`, one
        user unit a meter.

        Returns:
            The curve.

        Raises:
            Error: If `Curve` refuses it: a line or a Bezier curve whose
                points are all the same, or an ellipse with a radius that
                is not positive or two angles that are the same.
        """
        self.check()
        if self.kind == ELLIPSE:
            var center = self.points[0]
            return Curve(
                center=Vector2(Float32(center[0]), Float32(center[1])),
                x_radius=Length(Float32(self.x_radius), METER),
                y_radius=Length(Float32(self.y_radius), METER),
                start=Angle(Float32(self.start_angle), RADIAN),
                end=Angle(Float32(self.end_angle), RADIAN),
                clockwise=self.clockwise,
                rotation=Angle(Float32(self.rotation), RADIAN),
            )
        var points = List[Vector2]()
        # `check` has passed, so there are two points or more.
        for p in self.points:  # pragma: no branch
            points.append(Vector2(Float32(p[0]), Float32(p[1])))
        return Curve(self.kind, points^)


struct SvgSubPath(Copyable, Movable):
    """One outline: three.js's `Path`, a run of curves."""

    var curves: List[SvgCurve]
    # Whether `get_points` joins the last point back to the first.
    var auto_close: Bool
    # Where the pen is.
    var current_point: SvgVector

    def __init__(out self):
        """Start an outline with the pen at the origin."""
        self.curves = List[SvgCurve]()
        self.auto_close = False
        self.current_point = SvgVector(0, 0)

    def move_to(mut self, x: Float64, y: Float64):
        """Move the pen, three.js's `Path.moveTo`.

        Args:
            x: Where to, x.
            y: Where to, y.
        """
        self.current_point = SvgVector(x, y)

    def line_to(mut self, x: Float64, y: Float64):
        """Draw a line from the pen, three.js's `Path.lineTo`.

        Args:
            x: Where to, x.
            y: Where to, y.
        """
        var end = SvgVector(x, y)
        self.curves.append(SvgCurve(LINE, [self.current_point, end]))
        self.current_point = end

    def quadratic_curve_to(
        mut self, cx: Float64, cy: Float64, x: Float64, y: Float64
    ):
        """Draw a Bezier curve with one control point.

        Args:
            cx: The control point, x.
            cy: The control point, y.
            x: Where to, x.
            y: Where to, y.
        """
        var end = SvgVector(x, y)
        self.curves.append(
            SvgCurve(QUADRATIC, [self.current_point, SvgVector(cx, cy), end])
        )
        self.current_point = end

    def bezier_curve_to(
        mut self,
        c1x: Float64,
        c1y: Float64,
        c2x: Float64,
        c2y: Float64,
        x: Float64,
        y: Float64,
    ):
        """Draw a Bezier curve with two control points.

        Args:
            c1x: The first control point, x.
            c1y: The first control point, y.
            c2x: The second control point, x.
            c2y: The second control point, y.
            x: Where to, x.
            y: Where to, y.
        """
        var end = SvgVector(x, y)
        self.curves.append(
            SvgCurve(
                CUBIC,
                [
                    self.current_point,
                    SvgVector(c1x, c1y),
                    SvgVector(c2x, c2y),
                    end,
                ],
            )
        )
        self.current_point = end

    def abs_ellipse(
        mut self,
        x: Float64,
        y: Float64,
        x_radius: Float64,
        y_radius: Float64,
        start_angle: Float64,
        end_angle: Float64,
        clockwise: Bool = False,
        rotation: Float64 = 0,
    ) raises:
        """Draw an arc of an ellipse, three.js's `Path.absellipse`.

        When the outline has a curve and the arc does not start at the
        pen, a line to the arc's start comes first.

        Args:
            x: The center, x.
            y: The center, y.
            x_radius: The radius along the ellipse's own x axis.
            y_radius: The radius along its own y axis.
            start_angle: Where the arc starts, in radians.
            end_angle: Where it ends, in radians.
            clockwise: True to run clockwise.
            rotation: How far the axes turn, in radians.

        Raises:
            Error: Never for these arguments; `SvgCurve.point` raises
                only for a curve of a wrong kind.
        """
        var curve = SvgCurve(
            SvgVector(x, y),
            x_radius,
            y_radius,
            start_angle,
            end_angle,
            clockwise,
            rotation,
        )
        if len(self.curves) > 0:
            var first = curve.point(0)
            if not same_point(first, self.current_point):
                self.line_to(first[0], first[1])
        var last = curve.point(1)
        self.curves.append(curve^)
        self.current_point = last

    def abs_arc(
        mut self,
        x: Float64,
        y: Float64,
        radius: Float64,
        start_angle: Float64,
        end_angle: Float64,
        clockwise: Bool = False,
    ) raises:
        """Draw an arc of a circle, three.js's `Path.absarc`.

        Args:
            x: The center, x.
            y: The center, y.
            radius: The radius.
            start_angle: Where the arc starts, in radians.
            end_angle: Where it ends, in radians.
            clockwise: True to run clockwise.

        Raises:
            Error: Never; see `abs_ellipse`.
        """
        self.abs_ellipse(
            x, y, radius, radius, start_angle, end_angle, clockwise
        )

    def get_points(self, divisions: Int = 12) raises -> List[SvgVector]:
        """Return the outline as points, three.js's `CurvePath.getPoints`.

        A point equal to the one before it is left out. With `auto_close`,
        the first point is added again at the end when the last is not
        already it.

        Args:
            divisions: How many runs a Bezier curve takes; an ellipse takes
                twice as many and a line one.

        Returns:
            The points. None for an outline with no curves.

        Raises:
            Error: If `divisions` is below one, or a curve is refused.
        """
        var out = List[SvgVector]()
        for curve in self.curves:
            var points = curve.get_points(curve.resolution(divisions))
            for point in points:  # pragma: no branch
                var repeat = len(out) > 0 and same_point(
                    out[len(out) - 1], point
                )
                if repeat:
                    continue
                out.append(point)
        var close = self.auto_close and len(out) > 1
        if close:
            if not same_point(out[len(out) - 1], out[0]):
                out.append(out[0])
        return out^

    def to_path(self) raises -> Path:
        """Return this outline as a closed `math.path.Path`, one user unit
        a meter.

        A curve that `Curve` refuses, one of no length, is left out. When
        the outline does not end where it starts, a line joins the two, as
        three.js's triangulation joins them.

        Returns:
            The path.

        Raises:
            Error: If no curve is left, or a curve is of a wrong kind.
        """
        var path = Path()
        for curve in self.curves:
            curve.check()
            var made: Curve
            try:
                made = curve.to_curve()
            except:
                continue
            if len(path.curves) == 0:
                path.first = made.point(0)
                path.down = True
            path.last = made.point(1)
            path.curves.append(made^)
        if len(path.curves) == 0:
            raise Error("SVG: an outline with nothing drawn on it")
        if not path.is_closed():
            path.close_path()
        return path^


struct SvgStyle(Copyable, Movable):
    """The presentation an SVG element inherits and sets, three.js's
    `path.userData.style`.

    A text field that three.js leaves `undefined` is empty here. The
    numbers three.js reads are numbers here, clamped as three.js clamps
    them.
    """

    # `fill`: a CSS color, `none`, or empty. It starts at `#000`.
    var fill: String
    # `fill-opacity`, zero to one.
    var fill_opacity: Float64
    # `fill-rule`: `nonzero`, `evenodd`, another word, or empty.
    var fill_rule: String
    # `opacity`, zero to one, when `has_opacity` is True.
    var opacity: Float64
    var has_opacity: Bool
    # `stroke`: a CSS color, `none`, or empty.
    var stroke: String
    # `stroke-opacity`, zero to one.
    var stroke_opacity: Float64
    # `stroke-width`, zero or more user units.
    var stroke_width: Float64
    # `stroke-linejoin` and `stroke-linecap` as written.
    var stroke_line_join: String
    var stroke_line_cap: String
    # `stroke-miterlimit`, zero or more.
    var stroke_miter_limit: Float64
    # `visibility` as written, or empty.
    var visibility: String

    def __init__(out self):
        """Start with three.js's root style: a black fill, opacities of
        one, a stroke one unit wide, miter joins, butt caps and a miter
        limit of four."""
        self.fill = "#000"
        self.fill_opacity = 1
        self.fill_rule = String()
        self.opacity = 1
        self.has_opacity = False
        self.stroke = String()
        self.stroke_opacity = 1
        self.stroke_width = 1
        self.stroke_line_join = "miter"
        self.stroke_line_cap = "butt"
        self.stroke_miter_limit = 4
        self.visibility = String()


struct SvgShapePath(Copyable, Movable):
    """What one SVG element draws, three.js's `ShapePath` with the
    `color` and `userData` `SVGLoader` gives it."""

    var sub_paths: List[SvgSubPath]
    # Which of `sub_paths` a draw goes to, or -1 before a `move_to`.
    var current: Int
    # The fill, in linear light; white when there is none, as three.js's
    # `new Color()` is.
    var color: FloatColor
    # The element's style.
    var style: SvgStyle
    # The element, an index into the document, or -1.
    var node: Int

    def __init__(out self):
        """Start with no outlines."""
        self.sub_paths = List[SvgSubPath]()
        self.current = -1
        self.color = FloatColor(1, 1, 1)
        self.style = SvgStyle()
        self.node = -1

    def _check(self) raises:
        """Refuse a draw before a `move_to`.

        Raises:
            Error: If no outline has been started.
        """
        if self.current < 0:
            raise Error("SVG: a path draws before it moves")

    def move_to(mut self, x: Float64, y: Float64):
        """Start a new outline, three.js's `ShapePath.moveTo`.

        Args:
            x: Where it starts, x.
            y: Where it starts, y.
        """
        var path = SvgSubPath()
        path.move_to(x, y)
        self.sub_paths.append(path^)
        self.current = len(self.sub_paths) - 1

    def line_to(mut self, x: Float64, y: Float64) raises:
        """Draw a line on the current outline.

        Args:
            x: Where to, x.
            y: Where to, y.

        Raises:
            Error: If no outline has been started.
        """
        self._check()
        self.sub_paths[self.current].line_to(x, y)

    def quadratic_curve_to(
        mut self, cx: Float64, cy: Float64, x: Float64, y: Float64
    ) raises:
        """Draw a Bezier curve with one control point on the current
        outline.

        Args:
            cx: The control point, x.
            cy: The control point, y.
            x: Where to, x.
            y: Where to, y.

        Raises:
            Error: If no outline has been started.
        """
        self._check()
        self.sub_paths[self.current].quadratic_curve_to(cx, cy, x, y)

    def bezier_curve_to(
        mut self,
        c1x: Float64,
        c1y: Float64,
        c2x: Float64,
        c2y: Float64,
        x: Float64,
        y: Float64,
    ) raises:
        """Draw a Bezier curve with two control points on the current
        outline.

        Args:
            c1x: The first control point, x.
            c1y: The first control point, y.
            c2x: The second control point, x.
            c2y: The second control point, y.
            x: Where to, x.
            y: Where to, y.

        Raises:
            Error: If no outline has been started.
        """
        self._check()
        self.sub_paths[self.current].bezier_curve_to(c1x, c1y, c2x, c2y, x, y)


struct SvgMatrix(Copyable, Movable):
    """A 3x3 matrix, three.js's `Matrix3`: nine numbers, column by
    column."""

    var e: List[Float64]

    def __init__(out self):
        """Make the identity."""
        self.e = List[Float64](length=9, fill=0)
        self.e[0] = 1
        self.e[4] = 1
        self.e[8] = 1

    def __init__(
        out self,
        n11: Float64,
        n12: Float64,
        n13: Float64,
        n21: Float64,
        n22: Float64,
        n23: Float64,
        n31: Float64,
        n32: Float64,
        n33: Float64,
    ):
        """Make a matrix from its rows, three.js's `Matrix3.set`.

        Args:
            n11: Row one, column one.
            n12: Row one, column two.
            n13: Row one, column three.
            n21: Row two, column one.
            n22: Row two, column two.
            n23: Row two, column three.
            n31: Row three, column one.
            n32: Row three, column two.
            n33: Row three, column three.
        """
        self.e = List[Float64](length=9, fill=0)
        self.e[0] = n11
        self.e[1] = n21
        self.e[2] = n31
        self.e[3] = n12
        self.e[4] = n22
        self.e[5] = n32
        self.e[6] = n13
        self.e[7] = n23
        self.e[8] = n33

    def times(self, other: SvgMatrix) -> SvgMatrix:
        """Return this matrix times another, three.js's
        `multiplyMatrices(this, other)`.

        Args:
            other: The matrix on the right.

        Returns:
            The product.
        """
        var out = SvgMatrix()
        for col in range(3):  # pragma: no branch
            for row in range(3):  # pragma: no branch
                out.e[row + 3 * col] = (
                    self.e[row] * other.e[3 * col]
                    + self.e[row + 3] * other.e[3 * col + 1]
                    + self.e[row + 6] * other.e[3 * col + 2]
                )
        return out^

    def inverse(self) -> SvgMatrix:
        """Return the inverse, three.js's `Matrix3.invert`: all zeros when
        the determinant is zero.

        Returns:
            The inverse.
        """
        var n11 = self.e[0]
        var n21 = self.e[1]
        var n31 = self.e[2]
        var n12 = self.e[3]
        var n22 = self.e[4]
        var n32 = self.e[5]
        var n13 = self.e[6]
        var n23 = self.e[7]
        var n33 = self.e[8]
        var t11 = n33 * n22 - n32 * n23
        var t12 = n32 * n13 - n33 * n12
        var t13 = n23 * n12 - n22 * n13
        var det = n11 * t11 + n21 * t12 + n31 * t13
        var out = SvgMatrix(0, 0, 0, 0, 0, 0, 0, 0, 0)
        if det == 0:
            return out^
        var inv = 1 / det
        out.e[0] = t11 * inv
        out.e[1] = (n31 * n23 - n33 * n21) * inv
        out.e[2] = (n32 * n21 - n31 * n22) * inv
        out.e[3] = t12 * inv
        out.e[4] = (n33 * n11 - n31 * n13) * inv
        out.e[5] = (n31 * n12 - n32 * n11) * inv
        out.e[6] = t13 * inv
        out.e[7] = (n21 * n13 - n23 * n11) * inv
        out.e[8] = (n22 * n11 - n21 * n12) * inv
        return out^

    def transposed(self) -> SvgMatrix:
        """Return the transpose.

        Returns:
            The matrix with rows and columns swapped.
        """
        var out = SvgMatrix()
        for row in range(3):  # pragma: no branch
            for col in range(3):  # pragma: no branch
                out.e[row + 3 * col] = self.e[col + 3 * row]
        return out^

    def apply(
        self, x: Float64, y: Float64, z: Float64
    ) -> SIMD[DType.float64, 4]:
        """Return the matrix times a column, three.js's
        `Vector3.applyMatrix3`.

        Args:
            x: The first value.
            y: The second.
            z: The third.

        Returns:
            The three results, and a zero.
        """
        return SIMD[DType.float64, 4](
            self.e[0] * x + self.e[3] * y + self.e[6] * z,
            self.e[1] * x + self.e[4] * y + self.e[7] * z,
            self.e[2] * x + self.e[5] * y + self.e[8] * z,
            0,
        )

    def apply_point(self, p: SvgVector) -> SvgVector:
        """Return a point moved by this transform.

        Args:
            p: The point.

        Returns:
            The matrix times `(x, y, 1)`, its x and y.
        """
        var v = self.apply(p[0], p[1], 1)
        return SvgVector(v[0], v[1])


def svg_translation(x: Float64, y: Float64) -> SvgMatrix:
    """Return a translation, three.js's `makeTranslation`.

    Args:
        x: The move along x.
        y: The move along y.

    Returns:
        The matrix.
    """
    return SvgMatrix(1, 0, x, 0, 1, y, 0, 0, 1)


def svg_rotation(theta: Float64) -> SvgMatrix:
    """Return a rotation, three.js's `makeRotation`.

    Args:
        theta: The angle, in radians, counterclockwise.

    Returns:
        The matrix.
    """
    var c = cos(theta)
    var s = sin(theta)
    return SvgMatrix(c, -s, 0, s, c, 0, 0, 0, 1)


def svg_scale(x: Float64, y: Float64) -> SvgMatrix:
    """Return a scale, three.js's `makeScale`.

    Args:
        x: The scale along x.
        y: The scale along y.

    Returns:
        The matrix.
    """
    return SvgMatrix(x, 0, 0, 0, y, 0, 0, 0, 1)


def is_transform_flipped(m: SvgMatrix) -> Bool:
    """Return True if a transform mirrors, three.js's `isTransformFlipped`.

    Args:
        m: The transform.

    Returns:
        Whether its 2x2 part has a negative determinant.
    """
    return m.e[0] * m.e[4] - m.e[1] * m.e[3] < 0


def transform_scale_x(m: SvgMatrix) -> Float64:
    """Return the length of a transform's first column.

    Args:
        m: The transform.

    Returns:
        How much it scales x.
    """
    return sqrt(m.e[0] * m.e[0] + m.e[1] * m.e[1])


def transform_scale_y(m: SvgMatrix) -> Float64:
    """Return the length of a transform's second column.

    Args:
        m: The transform.

    Returns:
        How much it scales y.
    """
    return sqrt(m.e[3] * m.e[3] + m.e[4] * m.e[4])


def is_transform_skewed(m: SvgMatrix) -> Bool:
    """Return True if a transform's axes are not at right angles,
    three.js's `isTransformSkewed`.

    Args:
        m: The transform.

    Returns:
        Whether the columns' dot product, over the scales, passes
        `Number.EPSILON`.
    """
    var dot = m.e[0] * m.e[3] + m.e[1] * m.e[4]
    if dot == 0:
        return False
    var sx = transform_scale_x(m)
    var sy = transform_scale_y(m)
    return abs(dot / (sx * sy)) > JS_EPSILON


struct EigenDecomposition(Copyable, Movable):
    """The eigensystem of a symmetric 2x2 matrix, three.js's
    `eigenDecomposition` result."""

    var rt1: Float64
    var rt2: Float64
    var cs: Float64
    var sn: Float64

    def __init__(
        out self, rt1: Float64, rt2: Float64, cs: Float64, sn: Float64
    ):
        """Hold the result.

        Args:
            rt1: The larger eigenvalue.
            rt2: The smaller.
            cs: The cosine of the first eigenvector's angle.
            sn: Its sine.
        """
        self.rt1 = rt1
        self.rt2 = rt2
        self.cs = cs
        self.sn = sn


def eigen_decomposition(
    a: Float64, b: Float64, c: Float64
) -> EigenDecomposition:
    """Return the eigensystem of `[[a, b], [b, c]]`, three.js's
    `eigenDecomposition`.

    When `a + c` is negative, three.js leaves the first eigenvalue
    `undefined`; it is NaN here.

    Args:
        a: The first diagonal value.
        b: The off-diagonal value.
        c: The second diagonal value.

    Returns:
        The two eigenvalues and the first eigenvector.
    """
    var rt1: Float64
    var rt2: Float64
    var sm = a + c
    var df = a - c
    var rt = sqrt(df * df + 4 * b * b)
    var t: Float64
    if sm > 0:
        rt1 = 0.5 * (sm + rt)
        t = 1 / rt1
        rt2 = a * t * c - b * t * b
    elif sm < 0:
        rt1 = nan[DType.float64]()
        rt2 = 0.5 * (sm - rt)
    else:
        rt1 = 0.5 * rt
        rt2 = -0.5 * rt
    var cs: Float64
    if df > 0:
        cs = df + rt
    else:
        cs = df - rt
    var sn: Float64
    if abs(cs) > 2 * abs(b):
        t = -2 * b / cs
        sn = 1 / sqrt(1 + t * t)
        cs = t * sn
    elif abs(b) == 0:
        cs = 1
        sn = 0
    else:
        t = -0.5 * cs / b
        cs = 1 / sqrt(1 + t * t)
        sn = t * cs
    if df > 0:
        t = cs
        cs = -sn
        sn = t
    return EigenDecomposition(rt1, rt2, cs, sn)


def _transform_ellipse_generic(mut curve: SvgCurve, m: SvgMatrix):
    """Reshape an ellipse under a skewing transform, three.js's
    `transfEllipseGeneric`."""
    var a = curve.x_radius
    var b = curve.y_radius
    var cos_t = cos(curve.rotation)
    var sin_t = sin(curve.rotation)
    var f1 = m.apply(a * cos_t, a * sin_t, 0)
    var f2 = m.apply(-b * sin_t, b * cos_t, 0)
    var mf = SvgMatrix(f1[0], f2[0], 0, f1[1], f2[1], 0, 0, 0, 1)
    var inv = mf.inverse()
    var q = inv.transposed().times(inv)
    var ed = eigen_decomposition(q.e[0], q.e[1], q.e[4])
    var rt1 = sqrt(ed.rt1)
    var rt2 = sqrt(ed.rt2)
    curve.x_radius = 1 / rt1
    curve.y_radius = 1 / rt2
    curve.rotation = _atan2(ed.sn, ed.cs)
    var full = (
        js_remainder(curve.end_angle - curve.start_angle, 2 * pi) < JS_EPSILON
    )
    if full:
        return
    var d = SvgMatrix(rt1, 0, 0, 0, rt2, 0, 0, 0, 1)
    var r = SvgMatrix(ed.cs, ed.sn, 0, -ed.sn, ed.cs, 0, 0, 0, 1)
    var drf = d.times(r).times(mf)
    var s = drf.apply(cos(curve.start_angle), sin(curve.start_angle), 0)
    curve.start_angle = _atan2(s[1], s[0])
    var e = drf.apply(cos(curve.end_angle), sin(curve.end_angle), 0)
    curve.end_angle = _atan2(e[1], e[0])
    if is_transform_flipped(m):
        curve.clockwise = not curve.clockwise


def _transform_ellipse_no_skew(mut curve: SvgCurve, m: SvgMatrix):
    """Reshape an ellipse under a transform that keeps right angles,
    three.js's `transfEllipseNoSkew`."""
    var sx = transform_scale_x(m)
    var sy = transform_scale_y(m)
    curve.x_radius *= sx
    curve.y_radius *= sy
    var theta: Float64
    if sx > JS_EPSILON:
        theta = _atan2(m.e[1], m.e[0])
    else:
        theta = _atan2(-m.e[3], m.e[4])
    curve.rotation += theta
    if is_transform_flipped(m):
        curve.start_angle *= -1
        curve.end_angle *= -1
        curve.clockwise = not curve.clockwise


def _atan2(y: Float64, x: Float64) -> Float64:
    """Return `Math.atan2(y, x)`."""
    return atan2(y, x)


def js_remainder(a: Float64, b: Float64) -> Float64:
    """Return JavaScript's `a % b` for a positive `b`: the remainder with
    the sign of `a`. Mojo's `%` takes the sign of `b`.

    Args:
        a: The dividend.
        b: The divisor, above zero.

    Returns:
        The remainder.
    """
    var r = a % b
    var wrap = a < 0 and r != 0
    if wrap:
        r -= b
    return r


def transform_path(mut path: SvgShapePath, m: SvgMatrix) raises:
    """Move every curve of a shape path by a transform, three.js's
    `transformPath`.

    Points move by the matrix. An ellipse's center moves, and its radii,
    rotation and angles are worked out again: by the no-skew shortcut
    when the transform keeps right angles, and by an eigen decomposition
    when it does not.

    Args:
        path: The shape path.
        m: The transform.

    Raises:
        Error: If a curve is of a wrong kind.
    """
    var skewed = is_transform_skewed(m)
    for i in range(len(path.sub_paths)):
        for j in range(len(path.sub_paths[i].curves)):
            ref curve = path.sub_paths[i].curves[j]
            curve.check()
            if curve.kind != ELLIPSE:
                for k in range(len(curve.points)):  # pragma: no branch
                    curve.points[k] = m.apply_point(curve.points[k])
                continue
            curve.points[0] = m.apply_point(curve.points[0])
            if skewed:
                _transform_ellipse_generic(curve, m)
            else:
                _transform_ellipse_no_skew(curve, m)
