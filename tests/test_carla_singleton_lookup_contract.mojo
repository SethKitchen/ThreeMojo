# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Singleton lookup implication and retained malformed-input refusals."""

from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road_info import RoadInfoLaneOffset, info_index
from std.math import inf, nan
from std.testing import TestSuite, assert_equal
from tests.test_carla_proof_guard_controls import _assert_refused, _proof_road


def test_singleton_low_lookup_implies_ordered_high_for_all_start_classes() raises:
    for start in [
        -inf[DType.float64](),
        Float64(-3),
        -0.0,
        0.0,
        1.0,
        2.0,
        3.0,
        inf[DType.float64](),
        nan[DType.float64](),
    ]:
        var records = List[RoadInfoLaneOffset]()
        records.append(RoadInfoLaneOffset(start, CubicPolynomial.constant(0)))
        for low in [Float64(-2), -0.0, 0.0, 1.0, 2.0]:
            for high in [Float64(-2), -0.0, 0.0, 1.0, 2.0, 3.0]:
                if low <= high and info_index(records, low) == 0:
                    assert_equal(info_index(records, high), 0)


def test_contexts_keep_each_malformed_or_late_start_refusal() raises:
    for arc in [False, True]:
        for field in range(4):
            for start in [
                Float64(3),
                inf[DType.float64](),
                nan[DType.float64](),
            ]:
                var road = _proof_road(arc)
                if field == 0:
                    road.info.geometries[0].s = start
                elif field == 1:
                    road.info.lane_offsets[0].s = start
                elif field == 2:
                    road.info.elevations[0].s = start
                else:
                    road.sections[0].lanes[0].info.widths[0].s = start
                _assert_refused(road, arc)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
