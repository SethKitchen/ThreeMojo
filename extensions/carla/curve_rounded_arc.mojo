# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Guarded rounded-output boxes for one constant zero-heading ARC graph.

These bounds enclose stored Float64 outputs, not real-expression values.
They do not change _Interval, _Jet, or the scalar lane evaluator. Unknown
support disables this optional proof and leaves ordinary refinement intact.
"""

from extensions.carla.curve_trig import (
    _COS_COEFFICIENTS,
    _INV_HALF_PI,
    _SIN_COEFFICIENTS,
)
from extensions.carla.geometry import ARC
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import info_index
from std.math import fma, isfinite
from std.memory import bitcast


# Every nonzero operand lies in [2^-400, 2^400]. Its binary64 dyadic
# quantum is at least 2^-452. Products and fused sums have quantum at
# least 2^-904, and magnitude below 2^802. Thus no nonzero primitive
# result can underflow, and no primitive can overflow, even at a guard
# boundary. Check outputs again before they become the next operands.
# A box that meets zero without being identically zero is unsupported.
def _rounded_operand(value: Float64) -> Bool:
    var low = bitcast[DType.float64](UInt64(623) << UInt64(52))
    var high = bitcast[DType.float64](UInt64(1423) << UInt64(52))
    return isfinite(value) and (
        value == 0.0 or (abs(value) >= low and abs(value) <= high)
    )


# These boundaries prevent the enclosure's unfused path from contracting.
# fma is explicit in the other path. No fast-math reassociation is assumed.
@no_inline
def _rounded_add(a: Float64, b: Float64) -> Float64:
    return a + b


@no_inline
def _rounded_multiply(a: Float64, b: Float64) -> Float64:
    return a * b


@no_inline
def _rounded_fma(a: Float64, b: Float64, c: Float64) -> Float64:
    return fma(a, b, c)


@no_inline
def _rounded_reciprocal(value: Float64) -> Float64:
    return 1.0 / value


@fieldwise_init
struct _RoundedBox(ImplicitlyCopyable):
    var low: Float64
    var high: Float64
    var known: Bool

    @staticmethod
    def unknown() -> Self:
        return Self(0.0, 0.0, False)

    @staticmethod
    def bounds(low: Float64, high: Float64) -> Self:
        var valid = (
            _rounded_operand(low)
            and _rounded_operand(high)
            and low <= high
            and (low > 0.0 or high < 0.0 or (low == 0.0 and high == 0.0))
        )
        return Self(low, high, valid)

    @staticmethod
    def point(value: Float64) -> Self:
        return Self.bounds(value, value)

    def __neg__(self) -> Self:
        return Self(-self.high, -self.low, self.known)

    def hull(self, other: Self) -> Self:
        if not self.known or not other.known:
            return Self.unknown()
        return Self.bounds(min(self.low, other.low), max(self.high, other.high))

    def __add__(self, other: Self) -> Self:
        if not self.known or not other.known:
            return Self.unknown()
        # RN is monotone. No adjacent-ULP expansion belongs in this type.
        return Self.bounds(
            _rounded_add(self.low, other.low),
            _rounded_add(self.high, other.high),
        )

    def __sub__(self, other: Self) -> Self:
        return self + (-other)

    def __mul__(self, other: Self) -> Self:
        if not self.known or not other.known:
            return Self.unknown()
        var a = _rounded_multiply(self.low, other.low)
        var b = _rounded_multiply(self.low, other.high)
        var c = _rounded_multiply(self.high, other.low)
        var d = _rounded_multiply(self.high, other.high)
        return Self.bounds(min(min(a, b), min(c, d)), max(max(a, b), max(c, d)))


def _rounded_madd(
    a: _RoundedBox, b: _RoundedBox, c: _RoundedBox
) -> _RoundedBox:
    if not a.known or not b.known or not c.known:
        return _RoundedBox.unknown()
    var separate = a * b + c
    if not separate.known:
        return _RoundedBox.unknown()
    # Bilinearity gives extrema at endpoint pairs. Addition is monotone.
    var low = _rounded_fma(a.low, b.low, c.low)
    low = min(low, _rounded_fma(a.low, b.high, c.low))
    low = min(low, _rounded_fma(a.high, b.low, c.low))
    low = min(low, _rounded_fma(a.high, b.high, c.low))
    var high = _rounded_fma(a.low, b.low, c.high)
    high = max(high, _rounded_fma(a.low, b.high, c.high))
    high = max(high, _rounded_fma(a.high, b.low, c.high))
    high = max(high, _rounded_fma(a.high, b.high, c.high))
    return separate.hull(_RoundedBox.bounds(low, high))


def _rounded_polynomial[
    n: Int
](coefficients: Array[Float64, n], x: _RoundedBox) -> _RoundedBox:
    var result = _RoundedBox.point(coefficients[n - 1])
    var i = n - 2
    while i >= 0:
        result = _rounded_madd(result, x, _RoundedBox.point(coefficients[i]))
        i -= 1
    return result


def _rounded_constant(polynomial: CubicPolynomial) -> _RoundedBox:
    if polynomial.b != 0.0 or polynomial.c != 0.0 or polynomial.d != 0.0:
        return _RoundedBox.unknown()
    # For finite s, all variable terms are exact zero in either graph.
    return _RoundedBox.point(polynomial.a)


@fieldwise_init
struct _RoundedArc(ImplicitlyCopyable):
    var start: _RoundedBox
    var length: Float64
    var curvature: _RoundedBox
    var speed: _RoundedBox
    var x: _RoundedBox
    var y: _RoundedBox
    var z: _RoundedBox

    def center(self, low: Float64, high: Float64) -> Array[_RoundedBox, 3]:
        var unknown = _RoundedBox.unknown()
        var d = _RoundedBox.bounds(low, high) - self.start
        # Only the strictly interior, stable clamp branch is supported.
        if not d.known or d.low <= 0.0 or d.high >= self.length:
            return [unknown, unknown, unknown]
        var half = (d * self.curvature) * _RoundedBox.point(0.5)
        if not half.known:
            return [unknown, unknown, unknown]
        var selector = _rounded_madd(
            half, _RoundedBox.point(_INV_HALF_PI), _RoundedBox.point(0.5)
        )
        # floor(selector) == 0 under every permitted contraction graph.
        # Heading and both quadrant-reduction products are exactly zero.
        if not selector.known or selector.low < 0.0 or selector.high >= 1.0:
            return [unknown, unknown, unknown]
        # The selector check above already bounds half by a quarter turn:
        # _QUARTER_PI * _INV_HALF_PI exceeds 0.5 exactly, so any larger
        # positive half reaches 1 and any smaller negative half has a fused
        # selector below 0.
        var square = half * half
        var sinc = _rounded_polynomial(materialize[_SIN_COEFFICIENTS](), square)
        var cosine = _rounded_polynomial(
            materialize[_COS_COEFFICIENTS](), square
        )
        var sine = half * sinc
        var chord = (self.speed * d) * sinc
        return [
            _rounded_madd(chord, cosine, self.x),
            -_rounded_madd(chord, sine, self.y),
            self.z,
        ]


def _rounded_arc_context(
    road: Road, section: Int, lane: Int, low: Float64, high: Float64
) raises -> Optional[_RoundedArc]:
    # The caller reserves its root node and term before this validation.
    # Require one active geometry, offset, and elevation on the whole domain.
    road._check_lane(section, lane)
    if len(road.info.geometries) != 1:
        return None
    ref record = road.info.geometries[0]
    if record.geometry.kind != ARC or record.geometry.heading != 0.0:
        return None
    if not _RoundedBox.bounds(low, high).known or high > road.length:
        return None
    # Each kind has exactly one record here. One that starts at or before
    # low also holds at every high >= low.
    if info_index(road.info.geometries, low) != 0:
        return None
    if len(road.info.lane_offsets) != 1 or len(road.info.elevations) != 1:
        return None
    if (
        info_index(road.info.lane_offsets, low) != 0
        or info_index(road.info.elevations, low) != 0
    ):
        return None
    var lane_offset = _rounded_constant(road.info.lane_offsets[0].polynomial)
    var elevation = _rounded_constant(road.info.elevations[0].polynomial)
    if not lane_offset.known or not elevation.known:
        return None
    ref lanes = road.sections[section].lanes
    var id = lanes[lane].id
    var offset = _RoundedBox.point(0.0)
    if id.value != 0:
        var negative = id.value < 0
        var sign = _RoundedBox.point(1.0 if negative else -1.0)
        # The queried lane itself is in this list.
        for position in range(len(lanes)):  # pragma: no branch
            var i = len(lanes) - 1 - position if negative else position
            if negative:
                if lanes[i].id.value >= 0:
                    continue
            elif lanes[i].id.value < 1:
                continue
            ref widths = lanes[i].info.widths
            if len(widths) != 1:
                return None
            if info_index(widths, low) != 0:
                return None
            var width = _rounded_constant(widths[0].polynomial)
            if not width.known:
                return None
            var contribution = sign * width
            if lanes[i].id == id:
                contribution = contribution * _RoundedBox.point(0.5)
            offset = offset + contribution
            if not offset.known:
                return None
            if lanes[i].id == id:
                break
    offset = offset - lane_offset
    var curvature = _RoundedBox.point(record.geometry.curvature_start)
    if not curvature.known or curvature.low == 0.0 or not offset.known:
        return None
    # Reciprocal of a guarded nonzero input remains normal and finite.
    var radius = _RoundedBox.point(_rounded_reciprocal(curvature.low))
    var speed = (radius + offset) * curvature
    var x = _RoundedBox.point(record.geometry.x)
    var y = _RoundedBox.point(record.geometry.y) - offset
    var start = _RoundedBox.point(record.s)
    if not (speed.known and x.known and y.known and start.known):
        return None
    if not _rounded_operand(record.geometry.length):
        return None
    return _RoundedArc(
        start, record.geometry.length, curvature, speed, x, y, elevation
    )
