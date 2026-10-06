# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Independent binary-lattice half-error controls over the frozen full Jet.

The original full-Jet oracle is unchanged. Only the five reviewed exact-half
sites use this separate reference. No production stored-half helper is called.
The ideal/derivative fields still come from the frozen arithmetic. Error
scaling is computed by integer shifts and nearest-even word rounding.
"""

from extensions.carla.curve_interval import _Interval
from extensions.carla.geometry import RoadGeometry, _GL_NODES, _GL_WEIGHTS
from math.vector3 import Vector3
from std.math import isfinite
from std.memory import bitcast
from tests._spiral_full_jet_reference import _FullJet, _full_sincos_jet


def _reference_half_error(error: Float64) -> Float64:
    # Existing interval arithmetic keeps exact identity/zero shortcuts.
    # Otherwise its high endpoint is one successor above RN(error / 2).
    if error == 0.0:
        return 0.0
    if error == 1.0:
        return 0.5
    var word = bitcast[DType.uint64](error)
    var exponent = (word >> UInt64(52)) & UInt64(0x7FF)
    var rounded: UInt64
    if exponent >= 2:
        rounded = word - (UInt64(1) << UInt64(52))
    else:
        var significand = word & UInt64(0x000FFFFFFFFFFFFF)
        if exponent == 1:
            significand |= UInt64(1) << UInt64(52)
        rounded = significand >> UInt64(1)
        # Dividing an odd significand is a halfway case. Round to even.
        if (significand & UInt64(1)) != 0 and (rounded & UInt64(1)) != 0:
            rounded += UInt64(1)
    return bitcast[DType.float64](rounded + UInt64(1))


def _reference_half_supported(value: _FullJet) -> Bool:
    if (
        not value.value.is_finite()
        or value.value.low > value.value.high
        or not isfinite(value.error)
        or value.error < 0.0
    ):
        return False
    var actual = value.rounded_value()
    if actual.low <= 0.0 and actual.high >= 0.0:
        return False
    # Positive IEEE words are ordered. Compare exact endpoint words against
    # 2^-400 and 2^400, including both endpoints, without reproducing the
    # production floating-point magnitude comparisons.
    var one = bitcast[DType.uint64](actual.low) & UInt64(0x7FFFFFFFFFFFFFFF)
    var two = bitcast[DType.uint64](actual.high) & UInt64(0x7FFFFFFFFFFFFFFF)
    var low = min(one, two)
    var high = max(one, two)
    return low >= UInt64(0x26F0000000000000) and high <= UInt64(
        0x58F0000000000000
    )


def _reference_half(value: _FullJet) -> _FullJet:
    var result = value * _FullJet.constant(0.5)
    if _reference_half_supported(value):
        result.error = _reference_half_error(value.error)
    return result


def _half_reference_spiral(
    geometry: RoadGeometry, d: _FullJet, pieces: Int, translation: Vector3
) -> Tuple[_FullJet, _FullJet, _FullJet]:
    # The unchanged scalar polynomial/GL graph, evaluated by the frozen
    # full-Jet arithmetic with the independently checked half-error rule.
    var k0 = _FullJet.constant(geometry.curvature_start)
    var rate = _FullJet.constant(
        (geometry.curvature_end - geometry.curvature_start) / geometry.length
    )
    var step = d / _FullJet.constant(Float64(pieces))
    var nodes = materialize[_GL_NODES]()
    var weights = materialize[_GL_WEIGHTS]()
    var x = _FullJet.constant(0.0)
    var y = _FullJet.constant(0.0)
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
            x = (
                x
                + _reference_half(step)
                * _FullJet.constant(weights[i])
                * trig[1]
            )
            y = (
                y
                + _reference_half(step)
                * _FullJet.constant(weights[i])
                * trig[0]
            )
            i += 1
        piece += 1
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


def _independent_child_hull(one: _FullJet, two: _FullJet) -> _FullJet:
    # Construct endpoints directly from qualified child rounded enclosures.
    # Do not call the production union or the frozen union implementation.
    var first = one.rounded_value()
    var second = two.rounded_value()
    return _FullJet(
        _Interval(min(first.low, second.low), max(first.high, second.high)),
        _Interval.whole(),
        _Interval.whole(),
        0.0,
    )
