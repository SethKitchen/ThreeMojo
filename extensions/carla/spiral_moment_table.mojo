# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Readonly exact stored-polynomial SPIRAL coefficient table access.

The standalone lookup/expansion helpers were qualified separately. The held
Map domain-proof integration reads their immutable coefficient handle and
ideal polynomial helper, then attaches captured original-root scalar errors.
It needs its own native, coverage, and performance gates. No helper here is a
canonical scalar evaluator. The standalone expansion keeps its infinite-error
contract; a None result requires the original generic evaluator.

Coefficient derivation, source pins, and the portable standard-library checker
are documented in tools/carla_lane_oracle/spiral-moments.md. That checker proves
fixed-count ideal coefficients and endpoint rounding only; it does not certify
these runtime guards or any actual rounded geometry/error graph.
"""

from extensions.carla.curve_sum2 import _sum2_supported_environment
from extensions.carla.curve_interval import _Interval, _Jet, _stored_half
from extensions.carla.geometry import RoadGeometry, SPIRAL
from extensions.carla.spiral_moment_proof import (
    _ideal_coefficient,
    _all_spiral_nodes_quadrant_zero,
)
from extensions.carla.spiral_moment_table_data import _SPIRAL_MOMENT_WORDS
from math.vector3 import Vector3
from std.builtin.globals import global_constant
from std.math import inf, isfinite
from std.memory import bitcast


@fieldwise_init
struct _SpiralMomentProof(Copyable, Movable):
    # A count-only handle. No Array copy, ownership, allocation, or mutation
    # of the 22,528-byte global data. Eight raw bytes on an eight-byte Int target.
    var pieces: Int

    def coefficient(self, sine: Bool, index: Int) -> _Interval:
        # Defend this private accessor too: invalid handles or indices must
        # not index static storage. Expansion checks the count before access.
        if self.pieces < 1 or self.pieces > 64 or index < 0 or index > 10:
            return _Interval.whole()
        ref words = global_constant[_SPIRAL_MOMENT_WORDS]()
        var offset = (self.pieces - 1) * 44 + 2 * index
        if sine:
            offset += 22
        return _Interval(
            bitcast[DType.float64](words[offset]),
            bitcast[DType.float64](words[offset + 1]),
        )


def _try_lookup_spiral_moments(
    pieces: Int,
    mut proof_terms: Int,
    max_proof_terms: Int,
    available: Bool = True,
) -> Optional[_SpiralMomentProof]:
    # Reserve 22 fixed coefficient-read units, not 110*pieces construction
    # units. Reads occur lazily in the two polynomial evaluations. This is
    # an OPTIONAL proof allowance; original query GL-term reservations and
    # debits stay unchanged. A caller must not enlarge either original budget.
    if not available or pieces < 1 or pieces > 64:
        return None
    var work = 22
    if proof_terms < 0 or max_proof_terms < proof_terms:
        return None
    if work > max_proof_terms - proof_terms:
        return None
    proof_terms += work
    return _SpiralMomentProof(pieces)


def _ideal_moment_polynomial(
    proof: _SpiralMomentProof, sine: Bool, z: _Jet
) -> _Jet:
    var result = _ideal_coefficient(proof.coefficient(sine, 10))
    var j = 9
    while j >= 0:
        result = result * z + _ideal_coefficient(proof.coefficient(sine, j))
        j -= 1
    return result


def _try_spiral_moment_expansion(
    proof: _SpiralMomentProof,
    geometry: RoadGeometry,
    d: _Jet,
    counts: Tuple[Int, Int],
    translation: Vector3,
) -> Optional[Tuple[_Jet, _Jet, _Jet]]:
    if not _sum2_supported_environment():
        return None
    # `d` and `counts` MUST be the results of the existing clamping/count
    # helpers for this exact query-specific expansion station. Never pass
    # cached count selection or manually rounded endpoint estimates.
    if geometry.kind != SPIRAL:
        return None
    if geometry.heading != 0.0 or geometry.curvature_start != 0.0:
        return None
    if not isfinite(geometry.length) or geometry.length <= 0.0:
        return None
    if not isfinite(geometry.curvature_end):
        return None
    if proof.pieces < 1 or proof.pieces > 64:
        return None
    if counts[0] != proof.pieces or counts[1] != proof.pieces:
        return None
    var domain = d.rounded_value()
    # Reject every clamped or possibly clamped join. The unchanged evaluator
    # remains responsible for endpoints, unknowns, and count/quadrant joins.
    if (
        not domain.is_finite()
        or domain.low <= 0.0
        or domain.high >= geometry.length
    ):
        return None
    if not d.first.is_finite() or not d.second.is_finite():
        return None
    if not _all_spiral_nodes_quadrant_zero(geometry, d, proof.pieces):
        return None
    var rate = _Jet.constant(
        (geometry.curvature_end - geometry.curvature_start) / geometry.length
    )
    # u = beta*d^2. The simplified graph is used ONLY for real-polynomial
    # values and derivatives. Its computed error is never a scalar certificate.
    var u = _Jet.constant(0.5) * rate * d * d
    var z = u * u
    var x = d * _ideal_moment_polynomial(proof, False, z)
    var y = d * u * _ideal_moment_polynomial(proof, True, z)
    x = (_Jet.constant(geometry.x) - _Jet.constant(Float64(translation.x))) + x
    y = (_Jet.constant(geometry.y) + _Jet.constant(Float64(translation.y))) + y
    # Preserve the original heading jet/error graph: lane-offset trigonometry
    # uses this error for branch selection. Do not replace it with `u`.
    var heading = _Jet.constant(geometry.heading) + d * (
        _Jet.constant(geometry.curvature_start) + _stored_half(rate) * d
    )
    # This makes accidental use as a standalone actual rounded-value bound
    # unknown. _lane_jet_model's coordinate addition and the final expansion
    # distance use the value/derivative fields and keep error separate.
    x.error = inf[DType.float64]()
    y.error = inf[DType.float64]()
    return (x, y, heading)
