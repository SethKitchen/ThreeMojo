# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Optional bounded errors for the canonical stored-term SPIRAL Sum2 graph.

One interval contains every original GL piece, node and weight. Its value-only
expression follows the original step, phase, stored trigonometric polynomial
and weighted-term operations. A uniform Sum2 bound encloses accumulation
after the materialized products. It is not a true-clothoid error estimate.
Unsupported domains fall back to the full Sum2 expression bound.
"""

from extensions.carla.curve_interval import _Interval, _Jet, _ValueJet
from extensions.carla.curve_sum2 import _sum2_error
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


def _envelope_constant(low: Float64, high: Float64) -> _ValueJet:
    # Each member is a stored constant, not an inexactly evaluated variable.
    return _ValueJet(
        _Interval(low, high), _Interval.whole(), _Interval.whole(), 0.0
    )


def _sum2_envelope_error(
    term: _ValueJet, count: Int, origin: Float64
) -> Float64:
    if count < 1 or count > 320 or not isfinite(origin):
        return inf[DType.float64]()
    if (
        not term.value.is_finite()
        or not isfinite(term.error)
        or term.error < 0.0
    ):
        return inf[DType.float64]()
    var n = _Interval.point(Float64(count))
    var absolute_sum = n * _Interval.point(term.rounded_value().magnitude())
    var inherited = n * _Interval.point(term.error)
    var error = _sum2_error(absolute_sum.high, inherited.high, count)
    if not isfinite(error):
        return inf[DType.float64]()
    var ideal_magnitude = (n * _Interval.point(term.value.magnitude())).high
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


def _try_spiral_roundoff_envelope(
    geometry: RoadGeometry, d: _Jet, pieces: Int
) -> Optional[Tuple[Float64, Float64]]:
    # The caller supplies the original clamped distance Jet and fixed count.
    # This does not enlarge the existing moment model's heading/k0 domain.
    if (
        geometry.kind != SPIRAL
        or geometry.heading != 0.0
        or geometry.curvature_start != 0.0
    ):
        return None
    if (
        pieces < 1
        or pieces > 64
        or not isfinite(geometry.length)
        or geometry.length <= 0.0
    ):
        return None
    if (
        not isfinite(geometry.x)
        or not isfinite(geometry.y)
        or not isfinite(geometry.curvature_end)
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
    if not d.value.is_finite() or not isfinite(d.error) or d.error < 0.0:
        return None
    var distance = _ValueJet(
        d.value, _Interval.whole(), _Interval.whole(), d.error
    )
    var nodes = materialize[_GL_NODES]()
    var weights = materialize[_GL_WEIGHTS]()
    var node_low = 1.0 + nodes[0]
    var node_high = node_low
    var weight_low = weights[0]
    var weight_high = weight_low
    for i in range(1, 5):
        var node = 1.0 + nodes[i]
        node_low = min(node_low, node)
        node_high = max(node_high, node)
        weight_low = min(weight_low, weights[i])
        weight_high = max(weight_high, weights[i])
    var step = distance / _ValueJet.constant(Float64(pieces))
    var start = step * _envelope_constant(0.0, Float64(pieces - 1))
    var t = start + step * _ValueJet.constant(0.5) * _envelope_constant(
        node_low, node_high
    )
    var theta = _ValueJet.constant(geometry.heading) + t * (
        _ValueJet.constant(geometry.curvature_start)
        + _ValueJet.constant(0.5) * _ValueJet.constant(rate_value) * t
    )
    # The complete original rounded phase-selection graph must select zero.
    # No ideal beta*d*d estimate replaces the node-specific rounding graph.
    var phase = theta.rounded_value()
    if not phase.is_finite() or phase.magnitude() > _PHASE_LIMIT:
        return None
    var selection = (
        theta * _ValueJet.constant(_INV_HALF_PI) + _ValueJet.constant(0.5)
    ).rounded_value()
    # The ordered theta and nonnegative error are bounded by the phase gate.
    # Multiplication by k<=1 and addition of 0.5 cannot overflow this selector.
    comptime assert _INV_HALF_PI > 0.0 and _INV_HALF_PI <= 1.0
    comptime assert _PHASE_LIMIT > 0.0 and _PHASE_LIMIT <= 1048576.0
    if floor(selection.low) != 0.0 or floor(selection.high) != 0.0:
        return None
    var trig = _sincos_expression(theta)
    var factor = (
        step
        * _ValueJet.constant(0.5)
        * _envelope_constant(weight_low, weight_high)
    )
    var x = factor * trig[1]
    var y = factor * trig[0]
    var x_error = _sum2_envelope_error(x, 5 * pieces, geometry.x)
    var y_error = _sum2_envelope_error(y, 5 * pieces, geometry.y)
    if not isfinite(x_error) or not isfinite(y_error):
        return None
    return (x_error, y_error)
