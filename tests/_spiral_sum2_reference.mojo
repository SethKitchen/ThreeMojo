# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Independent monotone-endpoint Sum2 error reference over frozen Jet fields.

The full-Jet and half-only references remain unchanged. This reference derives
only the upper error endpoint through ordered scalar operations and adjacent
IEEE words; it never calls the production Sum2 helper or interval formula.
The ideal fields still use the frozen arithmetic and independent half rule.
"""

from extensions.carla.curve_interval import _Interval
from extensions.carla.geometry import RoadGeometry, _GL_NODES, _GL_WEIGHTS
from math.vector3 import Vector3
from std.math import isfinite
from std.memory import bitcast
from tests._spiral_full_jet_reference import _FullJet, _full_sincos_jet
from tests._spiral_half_error_reference import _reference_half


def _sum2_reference_successor(value: Float64) -> Float64:
    # Only nonnegative rounded quantities enter this endpoint operation.
    var word = bitcast[DType.uint64](value)
    if word == UInt64(0x7FF0000000000000):
        return value
    if value == 0.0:
        return bitcast[DType.float64](UInt64(1))
    return bitcast[DType.float64](word + UInt64(1))


def _sum2_reference_add_upper(one: Float64, two: Float64) -> Float64:
    # Both zero signs have the canonical positive-zero upper endpoint.
    if one == 0.0 and two == 0.0:
        return 0.0
    # Zero is an exact identity in the retained outward interval contract.
    if one == 0.0:
        return two
    if two == 0.0:
        return one
    return _sum2_reference_successor(one + two)


def _sum2_reference_error(
    magnitude: Float64, inherited: Float64, count: Int
) -> Float64:
    var magnitude_word = bitcast[DType.uint64](magnitude)
    var inherited_word = bitcast[DType.uint64](inherited)
    var magnitude_abs = magnitude_word & UInt64(0x7FFFFFFFFFFFFFFF)
    var inherited_abs = inherited_word & UInt64(0x7FFFFFFFFFFFFFFF)
    var infinity = bitcast[DType.float64](UInt64(0x7FF0000000000000))
    if count < 1 or count > 1073741824:
        return infinity
    if magnitude_abs >= UInt64(0x7FF0000000000000):
        return infinity
    if inherited_abs >= UInt64(0x7FF0000000000000):
        return infinity
    if magnitude_word != magnitude_abs and magnitude_abs != 0:
        return infinity
    if inherited_word != inherited_abs and inherited_abs != 0:
        return infinity
    # Inclusive exact IEEE word for 2^900; no rounded decimal guard copy.
    if magnitude_abs > UInt64(0x7830000000000000):
        return infinity
    if magnitude_abs == 0 or count == 1:
        return inherited
    var u = bitcast[DType.float64](UInt64(0x3CA0000000000000))
    # Positive monotonicity determines every extremizing endpoint. The
    # count-two identity multiplier avoids an otherwise added successor.
    var nu_high = u
    if count != 2:
        nu_high = _sum2_reference_successor(Float64(count - 1) * u)
    var denominator = 1.0 - nu_high
    var denominator_low = bitcast[DType.float64](
        bitcast[DType.uint64](denominator) - UInt64(1)
    )
    var gamma_high = _sum2_reference_successor(nu_high / denominator_low)
    var square_high = _sum2_reference_successor(gamma_high * gamma_high)
    var factor_high = _sum2_reference_successor(u + square_high)
    var scaled_high = factor_high
    if magnitude != 1.0:
        scaled_high = _sum2_reference_successor(factor_high * magnitude)
    return _sum2_reference_add_upper(inherited, scaled_high)


def _sum2_reference_spiral(
    geometry: RoadGeometry, d: _FullJet, pieces: Int, translation: Vector3
) -> Tuple[_FullJet, _FullJet, _FullJet]:
    var k0 = _FullJet.constant(geometry.curvature_start)
    var rate = _FullJet.constant(
        (geometry.curvature_end - geometry.curvature_start) / geometry.length
    )
    var step = d / _FullJet.constant(Float64(pieces))
    var nodes = materialize[_GL_NODES]()
    var weights = materialize[_GL_WEIGHTS]()
    var x = _FullJet.constant(0.0)
    var y = _FullJet.constant(0.0)
    var x_magnitude = Float64(0.0)
    var y_magnitude = Float64(0.0)
    var x_inherited = Float64(0.0)
    var y_inherited = Float64(0.0)
    var piece = 0
    while piece < pieces:
        var start = step * _FullJet.constant(Float64(piece))
        var i = 0
        while i < 5:
            var t = start + _reference_half(step) * _FullJet.constant(
                1.0 + nodes[i]
            )
            var theta = _FullJet.constant(geometry.heading) + t * (
                k0 + _reference_half(rate) * t
            )
            var trig = _full_sincos_jet(theta)
            var term_x = (
                _reference_half(step) * _FullJet.constant(weights[i]) * trig[1]
            )
            var term_y = (
                _reference_half(step) * _FullJet.constant(weights[i]) * trig[0]
            )
            x = x + term_x
            y = y + term_y
            x_magnitude = _sum2_reference_add_upper(
                x_magnitude, term_x.rounded_value().magnitude()
            )
            y_magnitude = _sum2_reference_add_upper(
                y_magnitude, term_y.rounded_value().magnitude()
            )
            x_inherited = _sum2_reference_add_upper(x_inherited, term_x.error)
            y_inherited = _sum2_reference_add_upper(y_inherited, term_y.error)
            i += 1
        piece += 1
    x.error = _sum2_reference_error(x_magnitude, x_inherited, 5 * pieces)
    y.error = _sum2_reference_error(y_magnitude, y_inherited, 5 * pieces)
    var heading = _FullJet.constant(geometry.heading) + d * (
        k0 + _reference_half(rate) * d
    )
    return (
        (
            _FullJet.constant(geometry.x)
            - _FullJet.constant(Float64(translation.x))
        )
        + x,
        (
            _FullJet.constant(geometry.y)
            + _FullJet.constant(Float64(translation.y))
        )
        + y,
        heading,
    )


def _sum2_reference_scale_upper(value: Float64, count: Int) -> Float64:
    if count == 1:
        return value
    if value == 1.0:
        return Float64(count)
    if value == 0.0:
        return 0.0
    return _sum2_reference_successor(Float64(count) * value)


def _sum2_reference_envelope_error(
    term: _FullJet, count: Int, origin: Float64
) -> Float64:
    var infinity = bitcast[DType.float64](UInt64(0x7FF0000000000000))
    if count < 1 or count > 320 or not isfinite(origin):
        return infinity
    if (
        not term.value.is_finite()
        or not isfinite(term.error)
        or term.error < 0.0
    ):
        return infinity
    var magnitude = _sum2_reference_scale_upper(
        term.rounded_value().magnitude(), count
    )
    var inherited = _sum2_reference_scale_upper(term.error, count)
    var error = _sum2_reference_error(magnitude, inherited, count)
    if not isfinite(error):
        return infinity
    var ideal_magnitude = _sum2_reference_scale_upper(
        term.value.magnitude(), count
    )
    var accumulated = _FullJet(
        _Interval(-ideal_magnitude, ideal_magnitude),
        _Interval.whole(),
        _Interval.whole(),
        error,
    )
    # The origin still uses frozen full-Jet arithmetic; Sum2 error does not
    # erase the final world-coordinate addition or its cancellation allowance.
    var translated = _FullJet.constant(origin) + accumulated
    if not translated.rounded_value().is_finite():
        return infinity
    return translated.error
