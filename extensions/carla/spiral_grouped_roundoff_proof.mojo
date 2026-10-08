# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Isolated four-group error proof for one canonical stored SPIRAL count.

This helper never evaluates a canonical point, selects a count, or falls back.
The caller supplies the original clamped distance including its scalar error,
and evaluates every admitted fixed count separately. Twelve or fewer distinct
weighted-term pairs replace 5*n pairs. The three-argument helper requires an
already-reserved attempt. The metered adapter preserves a separate fallback
reservation and keeps the attempt debit on every failure.
"""

from extensions.carla.curve_interval import (
    _Interval,
    _Jet,
    _ValueJet,
    _stored_half,
)
from extensions.carla.curve_sum2 import (
    _sum2_error_checked,
    _sum2_supported_environment,
)
from extensions.carla.curve_trig import (
    _sincos_expression,
    _INV_HALF_PI,
    _PHASE_LIMIT,
)
from extensions.carla.geometry import (
    RoadGeometry,
    SPIRAL,
    _GL_NODES,
    _GL_WEIGHTS,
)
from std.math import floor, inf, isfinite


def _spiral_grouped_roundoff_work(pieces: Int) -> Int:
    # One unit is an X/Y weighted-term pair, as in the original 5*n GL work.
    # Empty groups do no work. For every n>=1, 3*min(4,n) <= 5*n.
    if pieces < 1 or pieces > 64:
        return -1
    return 3 * min(4, pieces)


def _grouped_constant(low: Float64, high: Float64) -> _ValueJet:
    # Each possible member is a stored constant; no scalar rounding is added.
    return _ValueJet(
        _Interval(low, high), _Interval.whole(), _Interval.whole(), 0.0
    )


def _grouped_term(
    term: _ValueJet,
    count: Int,
    mut ideal: _Interval,
    mut magnitude: _Interval,
    mut inherited: _Interval,
):
    # A refused term poisons the ideal sum, so _grouped_origin_error refuses
    # the whole envelope. No term is ever silently left out of the sums.
    if (
        count < 1
        or count > 320
        or not term.value.is_finite()
        or term.value.low > term.value.high
        or not isfinite(term.error)
        or term.error < 0.0
    ):
        ideal = _Interval.whole()
        return
    var rounded = term.rounded_value()
    if not rounded.is_finite():
        ideal = _Interval.whole()
        return
    var copies = _Interval.point(Float64(count))
    ideal = ideal + copies * term.value
    magnitude = magnitude + copies * _Interval.point(rounded.magnitude())
    inherited = inherited + copies * _Interval.point(term.error)


def _grouped_origin_error(
    ideal: _Interval,
    magnitude: _Interval,
    inherited: _Interval,
    count: Int,
    origin: Float64,
) -> Float64:
    # PRIVATE CALLER CONTRACT: only the invocation-guarded raw helper below
    # calls this function, after its successful environment check. The exact
    # caller edges are pinned by the isolated source-correspondence controls.
    # Keep the canonical Sum2 theorem and single final world-origin addition.
    var error = _sum2_error_checked(magnitude.high, inherited.high, count)
    if not isfinite(error) or not ideal.is_finite():
        return inf[DType.float64]()
    var ideal_magnitude = ideal.magnitude()
    var accumulated = _ValueJet(
        _Interval(-ideal_magnitude, ideal_magnitude),
        _Interval.whole(),
        _Interval.whole(),
        error,
    )
    var translated = _ValueJet.constant(origin) + accumulated
    if not translated.rounded_value().is_finite():
        return inf[DType.float64]()
    return translated.error


def _spiral_grouped_domain_rate(
    geometry: RoadGeometry, d: _Jet, pieces: Int
) -> Optional[Float64]:
    # Fixed-size structural eligibility; no phase, trig, or weighted term work.
    if _spiral_grouped_roundoff_work(pieces) < 0:
        return None
    if (
        geometry.kind != SPIRAL
        or geometry.heading != 0.0
        or geometry.curvature_start != 0.0
        or not isfinite(geometry.length)
        or geometry.length <= 0.0
        or not isfinite(geometry.x)
        or not isfinite(geometry.y)
        or not isfinite(geometry.curvature_end)
        or not d.value.is_finite()
        or d.value.low > d.value.high
        or not isfinite(d.error)
        or d.error < 0.0
    ):
        return None
    var rate_value = (
        geometry.curvature_end - geometry.curvature_start
    ) / geometry.length
    if not isfinite(rate_value):
        return None
    var domain = d.rounded_value()
    if (
        not domain.is_finite()
        or domain.low <= 0.0
        or domain.high >= geometry.length
    ):
        return None
    return rate_value


def _try_spiral_grouped_roundoff_envelope(
    geometry: RoadGeometry,
    d: _Jet,
    pieces: Int,
) -> Optional[Tuple[Float64, Float64]]:
    # PRECONDITION: the caller reserved this complete attempt separately from
    # any fallback. The metered adapter below supplies that admission policy.
    # The original caller also owns clamping and the complete count union; this
    # helper must not silently replace that union with one selected count.
    if not _sum2_supported_environment():
        return None
    var rate = _spiral_grouped_domain_rate(geometry, d, pieces)
    if not rate:
        return None
    var rate_value = rate.value()
    var nodes = materialize[_GL_NODES]()
    var weights = materialize[_GL_WEIGHTS]()
    # Exactly the stored pairs, with actual multiplicities 2,2,1. The stored
    # table's symmetry, positive finite weights and finite nodes are checked
    # by tests/test_carla_spiral_guards.mojo; a changed table fails there.
    var node_low = inf[DType.float64]()
    var node_high = -inf[DType.float64]()
    for i in range(5):  # pragma: no branch
        var node = 1.0 + nodes[i]
        node_low = min(node_low, node)
        node_high = max(node_high, node)
    var distance = _ValueJet(
        d.value, _Interval.whole(), _Interval.whole(), d.error
    )
    var step = distance / _ValueJet.constant(Float64(pieces))
    var half_step = _stored_half(step)
    var half_rate = _stored_half(_ValueJet.constant(rate_value))
    var node_range = _grouped_constant(node_low, node_high)
    var phases = Array[_ValueJet, 4](fill=_ValueJet.constant(0.0))
    # Establish every group's original rounded phase branch before the first
    # polynomial evaluation. An ineligible later group cannot waste trig work.
    for group in range(4):  # pragma: no branch
        var low = group * pieces // 4
        var high = (group + 1) * pieces // 4
        if low == high:
            continue
        var start = step * _grouped_constant(Float64(low), Float64(high - 1))
        var t = start + half_step * node_range
        var theta = _ValueJet.constant(geometry.heading) + t * (
            _ValueJet.constant(geometry.curvature_start) + half_rate * t
        )
        var phase = theta.rounded_value()
        if not phase.is_finite() or phase.magnitude() > _PHASE_LIMIT:
            return None
        var selection = (
            theta * _ValueJet.constant(_INV_HALF_PI) + _ValueJet.constant(0.5)
        ).rounded_value()
        # A finite phase within the limit gives a finite selector.
        if floor(selection.low) != 0.0 or floor(selection.high) != 0.0:
            return None
        phases[group] = theta
    var factors = Array[_ValueJet, 3](fill=_ValueJet.constant(0.0))
    for weight in range(3):  # pragma: no branch
        factors[weight] = half_step * _ValueJet.constant(weights[weight])
    var x_ideal = _Interval.point(0.0)
    var y_ideal = _Interval.point(0.0)
    var x_magnitude = _Interval.point(0.0)
    var y_magnitude = _Interval.point(0.0)
    var x_inherited = _Interval.point(0.0)
    var y_inherited = _Interval.point(0.0)
    for group in range(4):  # pragma: no branch
        var low = group * pieces // 4
        var high = (group + 1) * pieces // 4
        if low == high:
            continue
        var trig = _sincos_expression(phases[group])
        for weight in range(3):  # pragma: no branch
            var multiplicity = 1 if weight == 2 else 2
            var copies = (high - low) * multiplicity
            var x = factors[weight] * trig[1]
            var y = factors[weight] * trig[0]
            _grouped_term(x, copies, x_ideal, x_magnitude, x_inherited)
            _grouped_term(y, copies, y_ideal, y_magnitude, y_inherited)
    var x_error = _grouped_origin_error(
        x_ideal, x_magnitude, x_inherited, 5 * pieces, geometry.x
    )
    var y_error = _grouped_origin_error(
        y_ideal, y_magnitude, y_inherited, 5 * pieces, geometry.y
    )
    if not isfinite(x_error) or not isfinite(y_error):
        return None
    return (x_error, y_error)


def _try_spiral_grouped_roundoff_envelope_metered(
    geometry: RoadGeometry,
    d: _Jet,
    pieces: Int,
    mut terms: Int,
    max_terms: Int,
) -> Optional[Tuple[Float64, Float64]]:
    # SINGLE FIXED BRANCH ONLY. A count-union caller must reserve the combined
    # attempt and complete fallback union before invoking either raw helper.
    # Additive adapter for a caller which has NOT already debited the original
    # fallback. Retain 5*n units for it; do not force a larger minimum budget.
    # The caller may simply skip this optional path and run its normal fallback
    # when the complete attempt-plus-fallback reservation is unavailable.
    if not _sum2_supported_environment():
        return None
    var work = _spiral_grouped_roundoff_work(pieces)
    if work < 0 or terms < 0 or terms > max_terms:
        return None
    var fallback_work = 5 * pieces
    if work + fallback_work > max_terms - terms:
        return None
    if not _spiral_grouped_domain_rate(geometry, d, pieces):
        return None
    # No phase/trig graph before debit. Every None below retains this debit.
    # If falling back, the caller must separately debit the retained 5*n units
    # immediately before its sole original-expression traversal. Never refund
    # this optional work or charge both traversals as one original traversal.
    terms += work
    return _try_spiral_grouped_roundoff_envelope(geometry, d, pieces)
