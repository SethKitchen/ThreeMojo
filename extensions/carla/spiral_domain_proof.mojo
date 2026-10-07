# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Private immutable reference-error proofs for an owning Map index snapshot.

The original root GL traversal supplies errors before any branch union.
Construction certifies the original node phase graph after existing cover
work. Queries use the same stored polynomial with those errors and fresh
heading. This module never evaluates a canonical scalar lane witness.
"""

from extensions.carla.curve_sum2 import _sum2_supported_environment
from extensions.carla.curve_interval import _Interval, _Jet, _stored_half
from extensions.carla.geometry import RoadGeometry, SPIRAL
from extensions.carla.road import Road
from extensions.carla.road_info import info_index
from extensions.carla.spiral_moment_proof import _all_spiral_nodes_quadrant_zero
from extensions.carla.spiral_moment_table import (
    _SpiralMomentProof,
    _ideal_moment_polynomial,
)
from math.vector3 import Vector3
from std.math import inf, isfinite


struct _SpiralRootCapture(ImplicitlyCopyable):
    # Construction-only stack value. No root jet is retained in the Map.
    var record_at: Int
    var low: Float64
    var high: Float64
    var d: _Jet
    var first_count: Int
    var last_count: Int
    var first_x_error: Float64
    var first_y_error: Float64
    var last_x_error: Float64
    var last_y_error: Float64

    def __init__(out self):
        self.record_at = -1
        self.low = 0.0
        self.high = 0.0
        self.d = _Jet.constant(0.0)
        self.first_count = 0
        self.last_count = 0
        self.first_x_error = 0.0
        self.first_y_error = 0.0
        self.last_x_error = 0.0
        self.last_y_error = 0.0


@fieldwise_init
struct _SpiralDomainProof(ImplicitlyCopyable):
    # 80 raw field bytes on an eight-byte Int target. Presence certifies q0
    # for BOTH complete count branches. The segment supplies exact stations
    # and owning road/lane identity; no duplicate canonical geometry is stored.
    var segment_index: Int
    var record_at: Int
    var rounded_d: _Interval
    var first_count: Int
    var last_count: Int
    var first_x_error: Float64
    var first_y_error: Float64
    var last_x_error: Float64
    var last_y_error: Float64


def _spiral_proof_geometry(geometry: RoadGeometry) -> Bool:
    return (
        geometry.kind == SPIRAL
        and geometry.heading == 0.0
        and geometry.curvature_start == 0.0
        and isfinite(geometry.length)
        and geometry.length > 0.0
        and isfinite(geometry.x)
        and isfinite(geometry.y)
        and isfinite(geometry.curvature_end)
        and isfinite(
            (geometry.curvature_end - geometry.curvature_start)
            / geometry.length
        )
    )


def _try_pack_spiral_proof(
    road: Road,
    low: Float64,
    high: Float64,
    segment_index: Int,
    captured: _SpiralRootCapture,
    proof_count: Int,
    mut construction_terms: Int,
    mut proof_units: Int,
    max_terms: Int = 2000000,
    max_proof_units: Int = 1048576,
    max_payload_bytes: Int = 1048576,
) -> Optional[_SpiralDomainProof]:
    if not _sum2_supported_environment():
        return None
    # Logical payload cap, not an allocator-capacity or RSS claim. Check before
    # any append can grow the sparse List. Map appends only a complete result.
    if captured.first_count < 1 or captured.last_count > 64:
        return None
    if captured.last_count < captured.first_count:
        return None
    if captured.last_count - captured.first_count > 1:
        return None
    if segment_index < 0 or proof_count < 0 or max_payload_bytes < 80:
        return None
    if proof_count >= max_payload_bytes // 80:
        return None
    # Fixed optional units cover one/two constant-size phase envelopes and
    # validation/packing. No new GL traversal and no coefficient construction.
    # Reserve before the optional arithmetic, after original chord/cover work.
    var branches = 1 if captured.first_count == captured.last_count else 2
    var extra = 16 + 128 * branches
    if construction_terms < 0 or construction_terms > max_terms:
        return None
    if proof_units < 0 or proof_units > max_proof_units:
        return None
    if extra > max_terms - construction_terms:
        return None
    if extra > max_proof_units - proof_units:
        return None
    construction_terms += extra
    proof_units += extra
    if not isfinite(low) or not isfinite(high) or low < 0.0 or high < low:
        return None
    if low != captured.low or high != captured.high:
        return None
    var at = info_index(road.info.geometries, low)
    if at < 0 or at != captured.record_at:
        return None
    if info_index(road.info.geometries, high) != at:
        return None
    ref geometry = road.info.geometries[at].geometry
    if not _spiral_proof_geometry(geometry):
        return None
    var domain = captured.d.rounded_value()
    if (
        not domain.is_finite()
        or domain.low <= 0.0
        or domain.high >= geometry.length
    ):
        return None
    if (
        not captured.d.value.is_finite()
        or not captured.d.first.is_finite()
        or not captured.d.second.is_finite()
    ):
        return None
    if (
        not isfinite(captured.first_x_error)
        or captured.first_x_error < 0.0
        or not isfinite(captured.first_y_error)
        or captured.first_y_error < 0.0
        or not isfinite(captured.last_x_error)
        or captured.last_x_error < 0.0
        or not isfinite(captured.last_y_error)
        or captured.last_y_error < 0.0
    ):
        return None
    if not _all_spiral_nodes_quadrant_zero(
        geometry, captured.d, captured.first_count
    ):
        return None
    if captured.last_count != captured.first_count:
        if not _all_spiral_nodes_quadrant_zero(
            geometry, captured.d, captured.last_count
        ):
            return None
    return _SpiralDomainProof(
        segment_index,
        at,
        domain,
        captured.first_count,
        captured.last_count,
        captured.first_x_error,
        captured.first_y_error,
        captured.last_x_error,
        captured.last_y_error,
    )


def _find_spiral_proof(
    proofs: List[_SpiralDomainProof], segment_index: Int
) -> Optional[_SpiralDomainProof]:
    # Construction appends in public segment order. No per-segment index slot
    # and no mutable query cache. The private pool moves with its owning Map.
    var low = 0
    var high = len(proofs)
    while low < high:
        var middle = low + (high - low) // 2
        if proofs[middle].segment_index < segment_index:
            low = middle + 1
        else:
            high = middle
    if low == len(proofs):
        return None
    if proofs[low].segment_index != segment_index:
        return None
    return proofs[low]


def _spiral_proof_matches(
    proof: _SpiralDomainProof,
    geometry: RoadGeometry,
    record_at: Int,
    low: Float64,
    high: Float64,
    root_low: Float64,
    root_high: Float64,
    d: _Jet,
    counts: Tuple[Int, Int],
) -> Bool:
    if record_at != proof.record_at or not _spiral_proof_geometry(geometry):
        return False
    if (
        not isfinite(low)
        or not isfinite(high)
        or not isfinite(root_low)
        or not isfinite(root_high)
        or high < low
        or root_high < root_low
        or low < root_low
        or high > root_high
    ):
        return False
    var domain = d.rounded_value()
    if (
        not domain.is_finite()
        or domain.low <= 0.0
        or domain.high >= geometry.length
        or not proof.rounded_d.is_finite()
        or proof.rounded_d.low <= 0.0
        or proof.rounded_d.high >= geometry.length
        or proof.rounded_d.high < proof.rounded_d.low
        or domain.low < proof.rounded_d.low
        or domain.high > proof.rounded_d.high
        or not d.value.is_finite()
        or not d.first.is_finite()
        or not d.second.is_finite()
    ):
        return False
    if counts[0] < 1 or counts[1] > 64 or counts[1] < counts[0]:
        return False
    if counts[1] - counts[0] > 1:
        return False
    if proof.first_count < 1 or proof.last_count > 64:
        return False
    if (
        proof.last_count < proof.first_count
        or proof.last_count - proof.first_count > 1
    ):
        return False
    if (
        not isfinite(proof.first_x_error)
        or proof.first_x_error < 0.0
        or not isfinite(proof.first_y_error)
        or proof.first_y_error < 0.0
        or not isfinite(proof.last_x_error)
        or proof.last_x_error < 0.0
        or not isfinite(proof.last_y_error)
        or proof.last_y_error < 0.0
    ):
        return False
    return counts[0] >= proof.first_count and counts[1] <= proof.last_count


def _spiral_proof_branch(
    proof: _SpiralDomainProof,
    geometry: RoadGeometry,
    d: _Jet,
    pieces: Int,
    translation: Vector3 = Vector3(0, 0, 0),
) -> Tuple[_Jet, _Jet, _Jet]:
    # Caller owns a successful arithmetic-mode check in this invocation,
    # before record/profile selection. Do not expose this private branch as
    # a standalone unchecked cached-bound entry.
    # Called only after fresh record/count/clamp/station containment checks.
    # The immutable original-root q0 proof applies to the actual d graph.
    var handle = _SpiralMomentProof(pieces)
    var rate = _Jet.constant(
        (geometry.curvature_end - geometry.curvature_start) / geometry.length
    )
    var u = _Jet.constant(0.5) * rate * d * d
    var z = u * u
    var x = d * _ideal_moment_polynomial(handle, False, z)
    var y = d * u * _ideal_moment_polynomial(handle, True, z)
    x = (_Jet.constant(geometry.x) - _Jet.constant(Float64(translation.x))) + x
    y = (_Jet.constant(geometry.y) + _Jet.constant(Float64(translation.y))) + y
    # Match the COMPLETE zero-translation ideal reference, including origin.
    # Table width is already in ideal intervals, never a scalar roundoff term.
    x.error = proof.first_x_error
    y.error = proof.first_y_error
    if pieces == proof.last_count:
        x.error = proof.last_x_error
        y.error = proof.last_y_error
    if translation.x != 0.0 or translation.y != 0.0 or translation.z != 0.0:
        # Translation is valid only for ideal Taylor expansion. Never claim
        # that root world-evaluator errors describe a translated scalar graph.
        x.error = inf[DType.float64]()
        y.error = inf[DType.float64]()
    # Keep the original fresh graph/error; the lane tail keeps its trig guard.
    var heading = _Jet.constant(geometry.heading) + d * (
        _Jet.constant(geometry.curvature_start) + _stored_half(rate) * d
    )
    return (x, y, heading)
