# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Fixed-count SPIRAL moment coefficients, built by interval arithmetic.

`_try_build_spiral_moments` encloses the 22 coefficients for a piece count
from the stored GL and trigonometric constants. Queries never call it: they
read the same coefficients from `spiral_moment_table`, and the tests check
that each table word lies inside the built enclosure. The phase guard and the
ideal-coefficient helper here are shared with that table.

Coefficients enclose algebraic expressions in the stored GL/trig constants.
No ideal-sine, fitted-curve, quadrature-exactness, or truncation claim is made.
"""

from extensions.carla.curve_sum2 import _sum2_supported_environment
from extensions.carla.curve_interval import (
    _Interval,
    _Jet,
    _tight_sum_bound,
    _tight_product_bound,
    _tight_quotient_bound,
)
from extensions.carla.curve_trig import (
    _COS_COEFFICIENTS,
    _SIN_COEFFICIENTS,
    _INV_HALF_PI,
    _PHASE_LIMIT,
)
from extensions.carla.geometry import (
    RoadGeometry,
    _GL_NODES,
    _GL_WEIGHTS,
)
from std.math import floor


@fieldwise_init
struct _SpiralMomentProof(Copyable, Movable):
    # Count-only proof data; no origin, curvature, road/lane records, or samples.
    # 360 raw bytes on an eight-byte Int target, before container overhead.
    var pieces: Int
    var cosine: Array[_Interval, 11]
    var sine: Array[_Interval, 11]


def _try_build_spiral_moments(
    pieces: Int, mut proof_terms: Int, max_proof_terms: Int
) -> Optional[_SpiralMomentProof]:
    if not _sum2_supported_environment():
        return None
    # This is a payload-availability ceiling, never a scalar/search count cap.
    # A caller must invoke generic evaluation whenever this returns None.
    if pieces < 1 or pieces > 64:
        return None
    # Conservatively charge one coefficient-node unit per moment per GL node.
    # The complete original chord construction runs first. The caller supplies
    # a separate remaining budget no larger than original_max - original_spent.
    # Existing construction/query counters and error boundaries are untouched.
    var work = 22 * 5 * pieces
    if proof_terms < 0 or max_proof_terms < proof_terms:
        return None
    if work > max_proof_terms - proof_terms:
        return None
    proof_terms += work
    # No runtime arrays, loops, or insertion before debit. These compile-time
    # bounds and the admitted count keep every moment intermediate finite.
    comptime for index in range(5):
        comptime assert _GL_NODES[index] > -1.0 and _GL_NODES[index] < 1.0
        comptime assert _GL_WEIGHTS[index] > 0.0 and _GL_WEIGHTS[index] <= 1.0
    comptime for index in range(11):
        comptime assert (
            _COS_COEFFICIENTS[index] >= -1.0 and _COS_COEFFICIENTS[index] <= 1.0
        )
        comptime assert (
            _SIN_COEFFICIENTS[index] >= -1.0 and _SIN_COEFFICIENTS[index] <= 1.0
        )
    var moments = Array[_Interval, 22](fill=_Interval.point(0.0))
    var nodes = materialize[_GL_NODES]()
    var weights = materialize[_GL_WEIGHTS]()
    var divisor = _Interval.point(Float64(pieces))
    var half = _Interval.point(0.5)
    var weight_sum = _Interval.point(0.0)
    for i in range(5):
        weight_sum = _tight_sum_bound(weight_sum, _Interval.point(weights[i]))
    # Exact cancellation of n copies divided by n. Do not substitute 1.0:
    # the actual stored weights, not ideal GL weights, define this polynomial.
    moments[0] = _tight_product_bound(half, weight_sum)
    for piece in range(pieces):  # pragma: no branch
        for i in range(5):
            # The scalar-rounded 1.0 + node is deliberately computed BEFORE
            # making the interval constant, exactly as curve_bounds:116-118.
            var node_sum = 1.0 + nodes[i]
            var alpha = _tight_quotient_bound(
                _tight_sum_bound(
                    _Interval.point(Float64(piece)),
                    _tight_product_bound(half, _Interval.point(node_sum)),
                ),
                divisor,
            )
            var alpha2 = _tight_product_bound(alpha, alpha)
            var power = alpha2
            for j in range(1, 22):
                moments[j] = _tight_sum_bound(
                    moments[j],
                    _tight_product_bound(_Interval.point(weights[i]), power),
                )
                if j < 21:
                    power = _tight_product_bound(power, alpha2)
    var twice_count = _tight_product_bound(_Interval.point(2.0), divisor)
    for j in range(1, 22):
        moments[j] = _tight_quotient_bound(moments[j], twice_count)
    var cos_coefficients = materialize[_COS_COEFFICIENTS]()
    var sin_coefficients = materialize[_SIN_COEFFICIENTS]()
    var cosine = Array[_Interval, 11](fill=_Interval.point(0.0))
    var sine = Array[_Interval, 11](fill=_Interval.point(0.0))
    for j in range(11):
        cosine[j] = _tight_product_bound(
            _Interval.point(cos_coefficients[j]), moments[2 * j]
        )
        sine[j] = _tight_product_bound(
            _Interval.point(sin_coefficients[j]), moments[2 * j + 1]
        )
    return _SpiralMomentProof(pieces, cosine^, sine^)


def _ideal_coefficient(value: _Interval) -> _Jet:
    # This interval encloses a fixed real coefficient, so both derivatives
    # are zero. Its interval width is construction uncertainty, not a scalar
    # rounding error of the canonical center evaluator.
    var zero = _Interval.point(0.0)
    return _Jet(value, zero, zero, 0.0)


def _all_spiral_nodes_quadrant_zero(
    geometry: RoadGeometry, d: _Jet, pieces: Int
) -> Bool:
    # Enclose the ORIGINAL scalar t/theta graph for every piece/node. A
    # continuous interval of piece/node constants only widens that enclosure.
    # Do not test a simplified beta*d*d phase in place of this operation graph.
    var nodes = materialize[_GL_NODES]()
    var node_low = 1.0 + nodes[0]
    var node_high = node_low
    for i in range(1, 5):
        var node_sum = 1.0 + nodes[i]
        node_low = min(node_low, node_sum)
        node_high = max(node_high, node_sum)
    var step = d / _Jet.constant(Float64(pieces))
    var start = step * _ideal_coefficient(_Interval(0.0, Float64(pieces - 1)))
    var t = start + step * _Jet.constant(0.5) * _ideal_coefficient(
        _Interval(node_low, node_high)
    )
    var rate = _Jet.constant(
        (geometry.curvature_end - geometry.curvature_start) / geometry.length
    )
    var theta = _Jet.constant(geometry.heading) + t * (
        _Jet.constant(geometry.curvature_start) + _Jet.constant(0.5) * rate * t
    )
    var domain = theta.rounded_value()
    if not domain.is_finite() or domain.magnitude() > _PHASE_LIMIT:
        return False
    # This duplicates only the pinned branch selection from curve_trig:341-347.
    # Production integration should share a branch-selection helper if practical.
    var selection = (
        theta * _Jet.constant(_INV_HALF_PI) + _Jet.constant(0.5)
    ).rounded_value()
    if not selection.is_finite():
        return False
    return floor(selection.low) == 0.0 and floor(selection.high) == 0.0
