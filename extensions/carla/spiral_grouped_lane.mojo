# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Try-only, separately metered grouped error reconstruction for a query cell.

The caller has already debited its complete original fixed-count GL union.
This attempt never invokes that fallback. Any declined attempt retains its
own node/term debit, leaving the caller's one original traversal available.
"""

from extensions.carla.curve_bounds import (
    _geometry_distance,
    _spiral_counts,
    _lane_jet_model_proof,
)
from extensions.carla.curve_interval import _Jet, _stored_difference
from extensions.carla.curve_sum2 import _sum2_supported_environment
from extensions.carla.geometry import SPIRAL
from extensions.carla.road import Road
from extensions.carla.road_info import info_index
from extensions.carla.spiral_domain_proof import (
    _SpiralDomainProof,
    _SpiralRootCapture,
)
from extensions.carla.spiral_grouped_roundoff_proof import (
    _spiral_grouped_roundoff_work,
    _try_spiral_grouped_roundoff_envelope,
)
from math.vector3 import Vector3


def _try_grouped_lane_jet(
    road: Road,
    section: Int,
    lane: Int,
    low: Float64,
    high: Float64,
    mut nodes: Int,
    mut terms: Int,
    max_nodes: Int,
    max_terms: Int,
) raises -> Optional[Tuple[_Jet, _Jet, _Jet]]:
    if not _sum2_supported_environment():
        return None
    # Twenty-four covers BOTH admitted fixed counts, each with at most four
    # groups of three weighted-term pairs. The original GL is already paid.
    if (
        nodes < 0
        or nodes >= max_nodes
        or terms < 0
        or terms > max_terms
        or max_terms - terms < 24
    ):
        return None
    # One full generic-node reservation more than covers one lane/profile
    # reconstruction, count/phase guards and bounded acceptance comparisons.
    # It adds no pending/terminal cell and is never refunded on decline.
    nodes += 1
    var at = info_index(road.info.geometries, low)
    if at < 0 or info_index(road.info.geometries, high) != at:
        return None
    ref record = road.info.geometries[at]
    ref geometry = record.geometry
    if (
        geometry.kind != SPIRAL
        or geometry.heading != 0.0
        or geometry.curvature_start != 0.0
    ):
        return None
    var d = _geometry_distance(
        geometry,
        _stored_difference(_Jet.variable(low, high), _Jet.constant(record.s)),
    )
    var counts = _spiral_counts(geometry, d)
    # _spiral_counts never returns a decreasing pair.
    if counts[0] < 1 or counts[1] > 64 or counts[1] - counts[0] > 1:
        return None
    var extra = _spiral_grouped_roundoff_work(counts[0])
    if counts[1] != counts[0]:
        extra += _spiral_grouped_roundoff_work(counts[1])
    # Atomic union debit precedes either phase/trig graph; later refusal
    # cannot spend the other branch's or the reserved fallback's capacity.
    terms += extra
    var first = _try_spiral_grouped_roundoff_envelope(geometry, d, counts[0])
    if not first:
        return None
    var last = first
    if counts[1] != counts[0]:
        last = _try_spiral_grouped_roundoff_envelope(geometry, d, counts[1])
        if not last:
            return None
    var proof = _SpiralDomainProof(
        0,
        at,
        d.rounded_value(),
        counts[0],
        counts[1],
        first.value()[0],
        first.value()[1],
        last.value()[0],
        last.value()[1],
    )
    var captured = _SpiralRootCapture()
    var point = _lane_jet_model_proof[False](
        road,
        section,
        lane,
        low,
        high,
        Vector3(0, 0, 0),
        proof,
        low,
        high,
        captured,
        require_reuse=True,
    )
    if (
        not point[0].rounded_value().is_finite()
        or not point[1].rounded_value().is_finite()
        or not point[2].rounded_value().is_finite()
    ):
        return None
    return point
