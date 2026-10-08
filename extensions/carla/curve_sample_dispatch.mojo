# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exact stored-sample dispatch cuts without changing index ownership.

A cut is admitted only after its actual stored subtraction/clamp predicate
is true and its immediate predecessor's predicate is false. The short probe
is optional; all unsupported or unbracketed cases retain the original solver.
"""

from extensions.carla.curve_sum2 import _sum2_supported_environment
from extensions.carla.curve_bounds import _sample_index
from extensions.carla.geometry import POLY3, PARAM_POLY3
from extensions.carla.road import Road
from extensions.carla.road_info import info_index
from std.math import isfinite
from std.memory import bitcast


def _sample_dispatch_predicate(
    origin: Float64, length: Float64, local: Float64, station: Float64
) -> Bool:
    return min(max(station - origin, 0.0), length) > local


def _sample_dispatch_cut(
    origin: Float64, length: Float64, local: Float64
) -> Optional[Float64]:
    # The caller pre-reserves the complete three-candidate attempt.
    if not _sum2_supported_environment():
        return None
    if (
        not isfinite(origin)
        or origin < 0.0
        or not isfinite(length)
        or length <= 0.0
        or not isfinite(local)
        or local < 0.0
        or local >= length
    ):
        return None
    var start = origin + local
    if not isfinite(start) or start <= 0.0:
        return None
    var word = bitcast[DType.uint64](start)
    for i in range(3):
        var bits = word + UInt64(i)
        if bits >= UInt64(0x7FF0000000000000):
            return None
        var cut = bitcast[DType.float64](bits)
        var before = bitcast[DType.float64](bits - UInt64(1))
        if _sample_dispatch_predicate(
            origin, length, local, cut
        ) and not _sample_dispatch_predicate(origin, length, local, before):
            return cut
    return None


def _try_sample_dispatch_cuts(
    road: Road,
    low: Float64,
    high: Float64,
    mut nodes: Int,
    mut terms: Int,
    max_nodes: Int,
    max_terms: Int,
) -> Optional[Tuple[Float64, Float64, Int]]:
    if not _sum2_supported_environment():
        return None
    if not isfinite(low) or not isfinite(high) or low <= 0.0 or high < low:
        return None
    var at = info_index(road.info.geometries, low)
    if at < 0 or info_index(road.info.geometries, high) != at:
        return None
    ref record = road.info.geometries[at]
    ref geometry = record.geometry
    if geometry.kind != POLY3 and geometry.kind != PARAM_POLY3:
        return None
    if (
        len(geometry.samples) < 3
        or not isfinite(record.s)
        or record.s < 0.0
        or not isfinite(geometry.length)
        or geometry.length <= 0.0
    ):
        return None
    var dl = min(max(low - record.s, 0.0), geometry.length)
    var dh = min(max(high - record.s, 0.0), geometry.length)
    var first = _sample_index(geometry, dl)
    var last = _sample_index(geometry, dh)
    var count = last - first
    if count < 1 or count > 2:
        return None
    var extra = 8 * count
    var node_reserve = 3 * count + 2
    var term_reserve = 16 * count
    if (
        max_nodes < node_reserve
        or max_terms < 0
        or nodes < 0
        or nodes > max_nodes - node_reserve
        or terms < 0
        or terms > max_terms
        or term_reserve > max_terms - terms
    ):
        return None
    # For c cuts, retain setup + 2c visited descendants + c+1 closed-cell
    # rechecks. Each sampled descendant needs three scalar witnesses and
    # one domain reservation, in addition to the 8c optional probe units.
    # This reserves immediate followup, not completion of an arbitrary
    # remaining search. Setup follows all original node closure choices.
    # One generic node covers at most sixteen predicate/index checks and
    # constant-size packing. Eight reference-equivalent units per cut cover
    # all six possible predicate calls plus two actual sample-index checks.
    # Debit atomically before either complete optional attempt; never refund.
    nodes += 1
    terms += extra
    var one = 0.0
    var two = 0.0
    for i in range(count):
        var threshold_at = first + i + 1
        # The index bracket and count admission put this in [1, n - 2].
        var cut = _sample_dispatch_cut(
            record.s, geometry.length, geometry.samples[threshold_at].s
        )
        if not cut:
            return None
        var station = cut.value()
        # The accepted index bracket makes the cut strictly later than low.
        if station > high:
            return None
        var before = bitcast[DType.float64](
            bitcast[DType.uint64](station) - UInt64(1)
        )
        var before_index = _sample_index(
            geometry, min(max(before - record.s, 0.0), geometry.length)
        )
        var after_index = _sample_index(
            geometry, min(max(station - record.s, 0.0), geometry.length)
        )
        if before_index != threshold_at - 1 or after_index != threshold_at:
            return None
        if i == 0:
            one = station
        else:
            two = station
    return (one, two, count)
