# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Frozen complete predecessor functions, using shared production value types."""
from extensions.carla.spiral_domain_proof import (
    _SpiralRootCapture,
    _SpiralDomainProof,
    _spiral_proof_geometry,
)
from extensions.carla.curve_sum2 import _sum2_supported_environment
from extensions.carla.curve_interval import _Jet
from extensions.carla.geometry import RoadGeometry
from extensions.carla.road import Road
from extensions.carla.road_info import info_index
from extensions.carla.spiral_moment_proof import _all_spiral_nodes_quadrant_zero
from std.math import isfinite


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
