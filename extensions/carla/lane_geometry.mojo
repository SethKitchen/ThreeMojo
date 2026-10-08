# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Private stored-polynomial geometry for continuous lane certificates.

Separate reference APIs retain the public geometry implementation. Canonical
SPIRAL positions use stored-term Sum2 accumulation. These helpers keep the
authored lane expression, with the current public-pose
refusals before unsafe indexing or integer conversion. They do not replace
scalar witnesses with an ideal trigonometric or moment approximation.
"""

from extensions.carla.geometry import (
    ARC,
    LINE,
    PARAM_POLY3,
    SPIRAL,
    DirectedPoint,
    RoadGeometry,
    _GL_NODES,
    _GL_WEIGHTS,
)
from extensions.carla.curve_trig import (
    _curve_atan as atan,
    _curve_atan2 as atan2,
    _curve_cos as cos,
    _curve_sin as sin,
    _atan_derivative,
    _atan2_derivative,
    _curve_sincos,
    _sincos_derivative,
    _curve_sinc,
    _sinc_derivative,
)
from extensions.carla.curve_sum2 import _sum2_update, _require_sum2_environment
from std.math import ceil, isfinite


def _lane_geometry_pos_at(
    geometry: RoadGeometry, dist: Float64
) raises -> DirectedPoint:
    """Return the point `dist` meters into the record, in double.

    Args:
        geometry: The road geometry record.
        dist: Distance from its start in meters, clamped to the record.

    Returns:
        The point and heading, with z zero.

    Raises:
        Error: If a SPIRAL uses an unsupported arithmetic mode.
    """
    var d = min(max(dist, 0.0), geometry.length)
    if geometry.kind == LINE:
        return DirectedPoint(
            geometry.x + d * cos(geometry.heading),
            geometry.y + d * sin(geometry.heading),
            0.0,
            geometry.heading,
        )
    if geometry.kind == ARC:
        return _lane_arc_offset(geometry, d, 0.0)
    if geometry.kind == SPIRAL:
        return _lane_spiral(geometry, d)
    return _lane_sampled(geometry, d)


def _lane_arc_offset(
    geometry: RoadGeometry, d: Float64, offset: Float64
) -> DirectedPoint:
    var radius = 1.0 / geometry.curvature_start
    var turn = d * geometry.curvature_start
    var half = turn * 0.5
    var phase = geometry.heading + half
    var factor = (radius + offset) * geometry.curvature_start * d
    if not isfinite(radius):
        # A finite offset cannot cancel an unrepresentable radius.
        # This form still resolves every finite tiny-curvature increment.
        factor = (1.0 + offset * geometry.curvature_start) * d
    var chord = factor * _curve_sinc(half)
    return DirectedPoint(
        geometry.x + offset * sin(geometry.heading) + chord * cos(phase),
        geometry.y - offset * cos(geometry.heading) + chord * sin(phase),
        0.0,
        geometry.heading + turn,
    )


def _lane_arc_offset_derivative(
    geometry: RoadGeometry,
    d: Float64,
    offset: Float64,
    slope: Float64,
    active: Bool = True,
) -> Tuple[Float64, Float64]:
    var radius = 1.0 / geometry.curvature_start
    var k = geometry.curvature_start
    var speed = 1.0 if active else 0.0
    var half = (d * k) * 0.5
    var dhalf = (speed * k) * 0.5
    var phase = geometry.heading + half
    var factor = (radius + offset) * k * d
    var dfactor = slope * k * d + (radius + offset) * k * speed
    if not isfinite(radius):
        factor = (1.0 + offset * k) * d
        dfactor = slope * k * d + (1.0 + offset * k) * speed
    var sinc = _curve_sinc(half)
    var chord = factor * sinc
    var dchord = dfactor * sinc + factor * _sinc_derivative(half) * dhalf
    var trig = _curve_sincos(phase)
    var derivative = _sincos_derivative(phase)
    return (
        slope * sin(geometry.heading)
        + dchord * trig[1]
        + chord * derivative[1] * dhalf,
        -slope * cos(geometry.heading)
        + dchord * trig[0]
        + chord * derivative[0] * dhalf,
    )


def _lane_spiral(geometry: RoadGeometry, d: Float64) raises -> DirectedPoint:
    _require_sum2_environment()
    var k0 = geometry.curvature_start
    var rate = (
        geometry.curvature_end - geometry.curvature_start
    ) / geometry.length
    var reach = max(abs(k0), abs(k0 + rate * d))
    var pieces = 1 + Int(ceil(d * (1.0 + reach)))
    var step = d / Float64(pieces)
    var nodes = materialize[_GL_NODES]()
    var weights = materialize[_GL_WEIGHTS]()
    # Accumulate displacement before adding the origin. Repeatedly
    # rounding a large world origin would discard small quadrature terms.
    var x = Float64(0.0)
    var y = Float64(0.0)
    var x_correction = Float64(0.0)
    var y_correction = Float64(0.0)
    for piece in range(pieces):  # pragma: no branch
        var start = step * Float64(piece)
        for i in range(5):  # pragma: no branch
            var t = start + step * 0.5 * (1.0 + nodes[i])
            var theta = geometry.heading + t * (k0 + 0.5 * rate * t)
            # Non-inlined Sum2 calls materialize the complete products.
            # A named intermediate alone would not prevent contraction.
            var next_x = _sum2_update(
                x, x_correction, step * 0.5 * weights[i] * cos(theta)
            )
            var next_y = _sum2_update(
                y, y_correction, step * 0.5 * weights[i] * sin(theta)
            )
            x = next_x[0]
            x_correction = next_x[1]
            y = next_y[0]
            y_correction = next_y[1]
    return DirectedPoint(
        geometry.x + (x + x_correction),
        geometry.y + (y + y_correction),
        0.0,
        geometry.heading + d * (k0 + 0.5 * rate * d),
    )


def _lane_geometry_derivative_at(
    geometry: RoadGeometry, distance: Float64
) raises -> Tuple[Float64, Float64, Float64]:
    if not geometry.kind.is_valid():
        raise Error("Road geometry kind is not valid")
    if not isfinite(distance) or not isfinite(geometry.heading):
        raise Error("Lane geometry needs finite distance and heading")
    if not isfinite(geometry.length) or geometry.length <= 0.0:
        raise Error("Lane geometry needs a finite positive length")
    if distance < 0.0 or distance > geometry.length:
        return (0.0, 0.0, 0.0)
    var d = distance
    if geometry.kind == LINE:
        return (cos(geometry.heading), sin(geometry.heading), 0.0)
    if not isfinite(geometry.curvature_start) or not isfinite(
        geometry.curvature_end
    ):
        raise Error("Lane geometry needs finite curvature")
    if geometry.kind == ARC:
        if geometry.curvature_start == 0.0:
            raise Error("An arc needs nonzero curvature")
        var derivative = _lane_arc_offset_derivative(geometry, d, 0.0, 0.0)
        return (derivative[0], derivative[1], geometry.curvature_start)
    if geometry.kind == SPIRAL:
        var k0 = geometry.curvature_start
        var rate = (geometry.curvature_end - k0) / geometry.length
        var reach = max(abs(k0), abs(k0 + rate * d))
        var work = ceil(d * (1.0 + reach))
        if not isfinite(work) or work >= 9223372036854775807.0:
            raise Error("Spiral derivative work is not representable")
        var pieces = 1 + Int(work)
        var step = d / Float64(pieces)
        var dstep = 1.0 / Float64(pieces)
        var nodes = materialize[_GL_NODES]()
        var weights = materialize[_GL_WEIGHTS]()
        var dx = 0.0
        var dy = 0.0
        var piece = 0
        while piece < pieces:
            var start = step * Float64(piece)
            var dstart = dstep * Float64(piece)
            var i = 0
            while i < 5:
                var t = start + step * 0.5 * (1.0 + nodes[i])
                var dt = dstart + dstep * 0.5 * (1.0 + nodes[i])
                var theta = geometry.heading + t * (k0 + 0.5 * rate * t)
                var dtheta = dt * (k0 + 0.5 * rate * t) + t * (0.5 * rate * dt)
                var trig = _curve_sincos(theta)
                var derivative = _sincos_derivative(theta)
                var factor = step * 0.5 * weights[i]
                var dfactor = dstep * 0.5 * weights[i]
                dx += dfactor * trig[1] + factor * derivative[1] * dtheta
                dy += dfactor * trig[0] + factor * derivative[0] * dtheta
                i += 1
            piece += 1
        return (dx, dy, k0 + d * rate)
    if len(geometry.samples) < 2:
        raise Error("A sampled lane geometry needs two samples")
    var low = 0
    var high = len(geometry.samples) - 1
    while high - low > 1:
        var middle = (low + high) // 2
        if geometry.samples[middle].s < d:
            low = middle
        else:
            high = middle
    var one = geometry.samples[low]
    var two = geometry.samples[high]
    var span = two.s - one.s
    if not isfinite(span) or span <= 0.0:
        raise Error("A sampled lane interval needs finite positive length")
    var fraction = (two.s - d) / span
    var tu = fraction * one.tu + (1.0 - fraction) * two.tu
    var tv = fraction * one.tv + (1.0 - fraction) * two.tv
    var du = (two.u - one.u) / span
    var dv = (two.v - one.v) / span
    var dtu = (two.tu - one.tu) / span
    var dtv = (two.tv - one.tv) / span
    var turn = _atan_derivative(tv) * dtv
    if geometry.kind == PARAM_POLY3:
        var scale = max(abs(tu), abs(tv))
        if not isfinite(scale) or scale == 0.0:
            raise Error("A sampled lane offset frame has no heading")
        turn = _atan2_derivative(tv, tu, dtv, dtu)
    var c = cos(geometry.heading)
    var sn = sin(geometry.heading)
    return (du * c - dv * sn, du * sn + dv * c, turn)


def _lane_sampled(geometry: RoadGeometry, d: Float64) -> DirectedPoint:
    # The first segment whose end reaches d. CARLA finds the same one
    # as the nearest segment in an R-tree.
    var lo = 0
    var hi = len(geometry.samples) - 1
    while hi - lo > 1:
        var mid = (lo + hi) // 2
        if geometry.samples[mid].s < d:
            lo = mid
        else:
            hi = mid
    var one = geometry.samples[lo]
    var two = geometry.samples[hi]
    var rate = (two.s - d) / (two.s - one.s)
    var u = rate * one.u + (1.0 - rate) * two.u
    var v = rate * one.v + (1.0 - rate) * two.v
    var tu = rate * one.tu + (1.0 - rate) * two.tu
    var tv = rate * one.tv + (1.0 - rate) * two.tv
    var tangent = atan(tv)
    if geometry.kind == PARAM_POLY3:
        tangent = atan2(tv, tu)
    var c = cos(geometry.heading)
    var s = sin(geometry.heading)
    return DirectedPoint(
        geometry.x + u * c - v * s,
        geometry.y + v * c + u * s,
        0.0,
        geometry.heading + tangent,
    )
