# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Query-local smooth bounds with source-proven stored ARC constants.

The caller reserves a node and a reference term before context validation.
Every cell and expansion still consumes the original reference-work debit.
This optional model does not change the global full/value graph or evaluator.
"""

from extensions.carla.curve_bounds import _scaled_point_distance_jet
from extensions.carla.curve_interval import (
    _Interval,
    _Jet,
    _stored_difference,
    _stored_half,
)
from extensions.carla.curve_rounded_arc import (
    _RoundedArc,
    _RoundedBox,
    _rounded_arc_context,
)
from extensions.carla.curve_trig import _sinc_jet, _sincos_jet
from extensions.carla.road import Road
from math.vector3 import Vector3
from std.math import inf


def _frozen_arc_context(
    road: Road,
    section: Int,
    lane: Int,
    low: Float64,
    high: Float64,
) raises -> Optional[_RoundedArc]:
    # Its caller MUST reserve the optional validation work before entry.
    # These are structural record checks, never a zero-derivative inference.
    var found = _rounded_arc_context(road, section, lane, low, high)
    if not found:
        return None
    var model = found.value()
    for coefficient in [
        model.start,
        model.curvature,
        model.speed,
        model.x,
        model.y,
        model.z,
    ]:
        if not coefficient.known or coefficient.low != coefficient.high:
            return None
    var distance = _RoundedBox.bounds(low, high) - model.start
    # Keep one smooth interior clamp branch throughout the original domain.
    if (
        not distance.known
        or distance.low <= 0.0
        or distance.high >= model.length
    ):
        return None
    return model


def _frozen_arc_center(
    model: _RoundedArc,
    low: Float64,
    high: Float64,
    translation: Vector3,
) -> Tuple[_Jet, _Jet, _Jet]:
    var distance = _stored_difference(
        _Jet.variable(low, high), _Jet.constant(model.start.low)
    )
    var actual = distance.rounded_value()
    if (
        not actual.is_finite()
        or actual.low <= 0.0
        or actual.high >= model.length
    ):
        var unknown = _Jet(
            _Interval.whole(),
            _Interval.whole(),
            _Interval.whole(),
            inf[DType.float64](),
        )
        return (unknown, unknown, unknown)
    var turn = distance * _Jet.constant(model.curvature.low)
    var half = _stored_half(turn)
    var chord = (_Jet.constant(model.speed.low) * distance) * _sinc_jet(half)
    var trig = _sincos_jet(half)
    return (
        (_Jet.constant(model.x.low) - _Jet.constant(Float64(translation.x)))
        + chord * trig[1],
        (_Jet.constant(model.y.low) + _Jet.constant(Float64(translation.y)))
        + chord * trig[0],
        _Jet.constant(model.z.low) - _Jet.constant(Float64(translation.z)),
    )


def _frozen_arc_expansion(
    model: _RoundedArc,
    station: Float64,
    location: Vector3,
    scale: Float64,
) -> _Jet:
    # This is the same smooth surrogate used by the full-domain center above.
    var relative = _frozen_arc_center(model, station, station, location)
    var result = _scaled_point_distance_jet(relative, Vector3(0, 0, 0), scale)
    # The translated graph supplies only ideal expansion values/derivatives.
    # Global lower bounds MUST keep the full-domain scalar evaluation error.
    result.error = inf[DType.float64]()
    return result
