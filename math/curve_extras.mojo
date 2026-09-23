# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The named curves in space, from three.js
`examples/jsm/curves/CurveExtras.js`.

three.js has fourteen small `Curve` subclasses, each one formula from `t`
to a point. Here they are one struct, `ExtraCurve`, with a kind that
says which formula, and one function per curve that makes it. Each is a
`SpaceCurve`, so the arc length, the spaced points and the frames of
`math.space_curve` work on it, and so does the curve modifier.

Most of the curves take a scale, a plain number that multiplies the
formula. Three do not: the granny knot, the knot curve and the helix
have fixed sizes in three.js, and here too. The points are in meters.

Every curve takes its tangent by three.js's base rule, the chord a
ten-thousandth either side; see `math.space_curve.chord_tangent`.
"""

from math.space_curve import Point3, SpaceCurve, chord_tangent, point3
from std.math import cos, isfinite, pi, sin


@fieldwise_init
struct ExtraCurveKind(Equatable, ImplicitlyCopyable, Writable):
    """Which of three.js's named curves an `ExtraCurve` is, as a type
    rather than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the fourteen curves there are.

        Returns:
            True from `GRANNY_KNOT` through `DECORATED_TORUS_KNOT_5C`.
        """
        return self.value >= GRANNY_KNOT.value and (
            self.value <= DECORATED_TORUS_KNOT_5C.value
        )


# three.js's `GrannyKnot`.
comptime GRANNY_KNOT = ExtraCurveKind(0)
# three.js's `HeartCurve`.
comptime HEART_CURVE = ExtraCurveKind(1)
# three.js's `VivianiCurve`.
comptime VIVIANI_CURVE = ExtraCurveKind(2)
# three.js's `KnotCurve`.
comptime KNOT_CURVE = ExtraCurveKind(3)
# three.js's `HelixCurve`.
comptime HELIX_CURVE = ExtraCurveKind(4)
# three.js's `TrefoilKnot`.
comptime TREFOIL_KNOT = ExtraCurveKind(5)
# three.js's `TorusKnot`: three times round, four times through.
comptime TORUS_KNOT = ExtraCurveKind(6)
# three.js's `CinquefoilKnot`.
comptime CINQUEFOIL_KNOT = ExtraCurveKind(7)
# three.js's `TrefoilPolynomialKnot`.
comptime TREFOIL_POLYNOMIAL_KNOT = ExtraCurveKind(8)
# three.js's `FigureEightPolynomialKnot`.
comptime FIGURE_EIGHT_POLYNOMIAL_KNOT = ExtraCurveKind(9)
# three.js's `DecoratedTorusKnot4a`.
comptime DECORATED_TORUS_KNOT_4A = ExtraCurveKind(10)
# three.js's `DecoratedTorusKnot4b`.
comptime DECORATED_TORUS_KNOT_4B = ExtraCurveKind(11)
# three.js's `DecoratedTorusKnot5a`.
comptime DECORATED_TORUS_KNOT_5A = ExtraCurveKind(12)
# three.js's `DecoratedTorusKnot5c`.
comptime DECORATED_TORUS_KNOT_5C = ExtraCurveKind(13)


def _torus(p: Float64, q: Float64, t: Float64, scale: Float64) -> Point3:
    """Return the point of a `(p, q)` torus knot at `t`, three.js's
    `TorusKnot` and `CinquefoilKnot` formula.

    Args:
        p: Times round the axis.
        q: Times through the hole.
        t: Where on the curve, zero through one.
        scale: What the formula is multiplied by.

    Returns:
        The point.
    """
    var a = t * (pi * 2)
    var x = (2 + cos(q * a)) * cos(p * a)
    var y = (2 + cos(q * a)) * sin(p * a)
    var z = sin(q * a)
    return point3(x, y, z) * scale


def _scale_to(x: Float64, y: Float64, t: Float64) -> Float64:
    """Return `t` of the way from `x` to `y`, three.js's `scaleTo`."""
    var r = y - x
    return t * r + x


struct ExtraCurve(SpaceCurve):
    """One of three.js's named curves in space."""

    var kind: ExtraCurveKind
    # What the formula is multiplied by. Read only by the curves that take
    # a scale in three.js.
    var scale: Float64

    def __init__(out self, kind: ExtraCurveKind, scale: Float64 = 1) raises:
        """Create a named curve.

        Args:
            kind: Which curve.
            scale: What the formula is multiplied by. The granny knot, the
                knot curve and the helix do not read it.

        Raises:
            Error: If the kind is not valid, or the scale is not finite.
        """
        if not kind.is_valid():
            raise Error("A named curve's kind must be one of the fourteen")
        if not isfinite(scale):
            raise Error("A named curve's scale must be finite")
        self.kind = kind
        self.scale = scale

    def point3(self, t: Float64) raises -> Point3:
        """Return the point of the curve at `t`, three.js's `getPoint`.

        Args:
            t: Where on the curve, from zero through one. three.js reads
                any number, and so does this.

        Returns:
            The point, in meters.

        Raises:
            Error: Never for a curve that was constructed.
        """
        var s = self.scale
        if self.kind == GRANNY_KNOT:
            var a = 2 * pi * t
            var x = (
                -0.22 * cos(a)
                - 1.28 * sin(a)
                - 0.44 * cos(3 * a)
                - 0.78 * sin(3 * a)
            )
            var y = (
                -0.1 * cos(2 * a)
                - 0.27 * sin(2 * a)
                + 0.38 * cos(4 * a)
                + 0.46 * sin(4 * a)
            )
            var z = 0.7 * cos(3 * a) - 0.4 * sin(3 * a)
            return point3(x, y, z) * 20
        if self.kind == HEART_CURVE:
            var a = t * (2 * pi)
            var x = 16 * (sin(a) ** 3)
            var y = 13 * cos(a) - 5 * cos(2 * a) - 2 * cos(3 * a) - cos(4 * a)
            return point3(x, y, 0) * s
        if self.kind == VIVIANI_CURVE:
            var a = t * 4 * pi
            var half = s / 2
            var x = half * (1 + cos(a))
            var y = half * sin(a)
            var z = 2 * half * sin(a / 2)
            return point3(x, y, z)
        if self.kind == KNOT_CURVE:
            var a = t * (2 * pi)
            var r = 10.0
            var k = 50.0
            var x = k * sin(a)
            var y = cos(a) * (r + k * cos(a))
            var z = sin(a) * (r + k * cos(a))
            return point3(x, y, z)
        if self.kind == HELIX_CURVE:
            var radius = 30.0
            var height = 150.0
            var a = 2 * pi * t * height / 30
            return point3(cos(a) * radius, sin(a) * radius, height * t)
        if self.kind == TREFOIL_KNOT:
            var a = t * (pi * 2)
            var x = (2 + cos(3 * a)) * cos(2 * a)
            var y = (2 + cos(3 * a)) * sin(2 * a)
            var z = sin(3 * a)
            return point3(x, y, z) * s
        if self.kind == TORUS_KNOT:
            return _torus(3, 4, t, s)
        if self.kind == CINQUEFOIL_KNOT:
            return _torus(2, 5, t, s)
        if self.kind == TREFOIL_POLYNOMIAL_KNOT:
            var a = t * 4 - 2
            var x = a**3 - 3 * a
            var y = a**4 - 4 * a * a
            var z = 1.0 / 5 * a**5 - 2 * a
            return point3(x, y, z) * s
        if self.kind == FIGURE_EIGHT_POLYNOMIAL_KNOT:
            var a = _scale_to(-4, 4, t)
            var x = 2.0 / 5 * a * (a * a - 7) * (a * a - 10)
            var y = a**4 - 13 * a * a
            var z = 1.0 / 10 * a * (a * a - 4) * (a * a - 9) * (a * a - 12)
            return point3(x, y, z) * s
        if self.kind == DECORATED_TORUS_KNOT_4A:
            var a = t * (pi * 2)
            var ring = 1 + 0.6 * (cos(5 * a) + 0.75 * cos(10 * a))
            var x = cos(2 * a) * ring
            var y = sin(2 * a) * ring
            var z = 0.35 * sin(5 * a)
            return point3(x, y, z) * s
        if self.kind == DECORATED_TORUS_KNOT_4B:
            var fi = t * pi * 2
            var ring = 1 + 0.45 * cos(3 * fi) + 0.4 * cos(9 * fi)
            var x = cos(2 * fi) * ring
            var y = sin(2 * fi) * ring
            var z = 0.2 * sin(9 * fi)
            return point3(x, y, z) * s
        if self.kind == DECORATED_TORUS_KNOT_5A:
            var fi = t * pi * 2
            var ring = 1 + 0.3 * cos(5 * fi) + 0.5 * cos(10 * fi)
            var x = cos(3 * fi) * ring
            var y = sin(3 * fi) * ring
            var z = 0.2 * sin(20 * fi)
            return point3(x, y, z) * s
        # The constructor refused every other kind, so this is the last.
        var fi = t * pi * 2
        var ring = 1 + 0.5 * (cos(5 * fi) + 0.4 * cos(20 * fi))
        var x = cos(4 * fi) * ring
        var y = sin(4 * fi) * ring
        var z = 0.35 * sin(15 * fi)
        return point3(x, y, z) * s

    def tangent3(self, t: Float64) raises -> Point3:
        """Return the unit direction at `t`, by three.js's base
        `getTangent`.

        Args:
            t: Where on the curve, from zero through one.

        Returns:
            The direction.

        Raises:
            Error: Never for a curve that was constructed.
        """
        return chord_tangent(self, t)


def granny_knot() raises -> ExtraCurve:
    """Return three.js's `GrannyKnot`.

    Returns:
        The curve, twenty times the formula.

    Raises:
        Error: Never.
    """
    return ExtraCurve(GRANNY_KNOT)


def heart_curve(scale: Float64 = 5) raises -> ExtraCurve:
    """Return three.js's `HeartCurve`, flat in the xy plane.

    Args:
        scale: What the formula is multiplied by. Five by default.

    Returns:
        The curve.

    Raises:
        Error: If the scale is not finite.
    """
    return ExtraCurve(HEART_CURVE, scale)


def viviani_curve(scale: Float64 = 70) raises -> ExtraCurve:
    """Return three.js's `VivianiCurve`, the line where a sphere and a
    cylinder meet.

    Args:
        scale: The diameter of the sphere. Seventy by default.

    Returns:
        The curve.

    Raises:
        Error: If the scale is not finite.
    """
    return ExtraCurve(VIVIANI_CURVE, scale)


def knot_curve() raises -> ExtraCurve:
    """Return three.js's `KnotCurve`.

    Returns:
        The curve.

    Raises:
        Error: Never.
    """
    return ExtraCurve(KNOT_CURVE)


def helix_curve() raises -> ExtraCurve:
    """Return three.js's `HelixCurve`: five turns of radius thirty, one
    hundred and fifty high.

    Returns:
        The curve.

    Raises:
        Error: Never.
    """
    return ExtraCurve(HELIX_CURVE)


def trefoil_knot(scale: Float64 = 10) raises -> ExtraCurve:
    """Return three.js's `TrefoilKnot`.

    Args:
        scale: What the formula is multiplied by. Ten by default.

    Returns:
        The curve.

    Raises:
        Error: If the scale is not finite.
    """
    return ExtraCurve(TREFOIL_KNOT, scale)


def torus_knot(scale: Float64 = 10) raises -> ExtraCurve:
    """Return three.js's `TorusKnot`.

    Args:
        scale: What the formula is multiplied by. Ten by default.

    Returns:
        The curve.

    Raises:
        Error: If the scale is not finite.
    """
    return ExtraCurve(TORUS_KNOT, scale)


def cinquefoil_knot(scale: Float64 = 10) raises -> ExtraCurve:
    """Return three.js's `CinquefoilKnot`.

    Args:
        scale: What the formula is multiplied by. Ten by default.

    Returns:
        The curve.

    Raises:
        Error: If the scale is not finite.
    """
    return ExtraCurve(CINQUEFOIL_KNOT, scale)


def trefoil_polynomial_knot(scale: Float64 = 10) raises -> ExtraCurve:
    """Return three.js's `TrefoilPolynomialKnot`.

    Args:
        scale: What the formula is multiplied by. Ten by default.

    Returns:
        The curve.

    Raises:
        Error: If the scale is not finite.
    """
    return ExtraCurve(TREFOIL_POLYNOMIAL_KNOT, scale)


def figure_eight_polynomial_knot(scale: Float64 = 1) raises -> ExtraCurve:
    """Return three.js's `FigureEightPolynomialKnot`.

    Args:
        scale: What the formula is multiplied by. One by default.

    Returns:
        The curve.

    Raises:
        Error: If the scale is not finite.
    """
    return ExtraCurve(FIGURE_EIGHT_POLYNOMIAL_KNOT, scale)


def decorated_torus_knot_4a(scale: Float64 = 40) raises -> ExtraCurve:
    """Return three.js's `DecoratedTorusKnot4a`.

    Args:
        scale: What the formula is multiplied by. Forty by default.

    Returns:
        The curve.

    Raises:
        Error: If the scale is not finite.
    """
    return ExtraCurve(DECORATED_TORUS_KNOT_4A, scale)


def decorated_torus_knot_4b(scale: Float64 = 40) raises -> ExtraCurve:
    """Return three.js's `DecoratedTorusKnot4b`.

    Args:
        scale: What the formula is multiplied by. Forty by default.

    Returns:
        The curve.

    Raises:
        Error: If the scale is not finite.
    """
    return ExtraCurve(DECORATED_TORUS_KNOT_4B, scale)


def decorated_torus_knot_5a(scale: Float64 = 40) raises -> ExtraCurve:
    """Return three.js's `DecoratedTorusKnot5a`.

    Args:
        scale: What the formula is multiplied by. Forty by default.

    Returns:
        The curve.

    Raises:
        Error: If the scale is not finite.
    """
    return ExtraCurve(DECORATED_TORUS_KNOT_5A, scale)


def decorated_torus_knot_5c(scale: Float64 = 40) raises -> ExtraCurve:
    """Return three.js's `DecoratedTorusKnot5c`.

    Args:
        scale: What the formula is multiplied by. Forty by default.

    Returns:
        The curve.

    Raises:
        Error: If the scale is not finite.
    """
    return ExtraCurve(DECORATED_TORUS_KNOT_5C, scale)
