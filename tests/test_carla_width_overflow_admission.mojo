# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Bounded search-kernel witness for finite-endpoint width overflow.

This directly calls the internal search kernel with a preflight-admitted
real LINE Road and genuine checked incumbent. The negative station domain
is a helper-domain control, not a claim of ordinary public Map reachability.
All expression enclosures come from the unchanged Road producers.
"""

from extensions.carla.curve_bounds import _reference_work
from extensions.carla.curve_interval import _Interval
from extensions.carla.lane_refinement import (
    _ClosedInterval,
    _ClosedIntervals,
    _midpoint,
    _run_lane_search,
)
from extensions.carla.map_search import MapBuildBudget, _MapBuildWork
from extensions.carla.map_validation import _preflight_road_records
from math.vector3 import Vector3
from std.math import isfinite
from std.testing import TestSuite, assert_equal, assert_false, assert_raises, assert_true
from tests._lazy_taylor_controls import _whole_certificate
from tests.test_carla_cross_candidate_certificates import _road


def test_real_line_overflow_width_reaches_depth_refusal_with_bounded_work() raises:
    var low = Float64(-1e308)
    var high = Float64(1e308)
    var road = _road()
    # RoadInfo record selectors accept these finite lower coordinates.
    # The real geometry itself remains a four-meter LINE with nonnegative s.
    road.info.geometries[0].s = low
    road.info.elevations[0].s = low
    road.info.lane_offsets[0].s = low
    road.sections[0].lanes[0].info.widths[0].s = low
    var validation = _MapBuildWork(MapBuildBudget())
    _preflight_road_records(road, validation)
    assert_false(validation.exhausted)
    assert_true(isfinite(low) and isfinite(high))
    assert_false(isfinite(high - low))
    assert_equal(_midpoint(low, high), 0.0)
    assert_equal(_reference_work(road, low, high), 1)
    for station in [low, _midpoint(low, high), high]:
        assert_equal(_reference_work(road, station, station), 1)
        var point = road._lane_center(0, 0, station)
        for axis in range(3):
            assert_true(isfinite(point[axis]))
    var location = Vector3(0, 1, 0)
    var certificate = _whole_certificate(road, location, low, high, low)
    assert_equal(certificate.s, low)
    assert_equal(certificate.point[0], 0.0)
    assert_equal(certificate.point[1], 0.0)
    assert_equal(certificate.point[2], 0.0)
    assert_equal(certificate.terms, 1)
    var pending: List[Tuple[Float64, Float64, Int]] = [(low, high, 0)]
    # Zero requested gap prevents tolerance closure from hiding admission.
    # One cell and depth zero rule out recursive search or a large workload.
    with assert_raises(contains="numerical accuracy limit"):
        _run_lane_search(
            road, 0, 0, low, high, location, certificate, pending^,
            _ClosedIntervals(), List[_ClosedInterval](),
            (Float64(0.0), Float64(1.0)), 1, 6, 0,
        )
    assert_equal(certificate.nodes, 1)
    # One initial incumbent, three edge/center samples, one whole enclosure,
    # and one optional expansion debit. No LINE work requires quadrature.
    assert_equal(certificate.terms, 6)
    assert_equal(certificate.s, low)
    assert_false(certificate.exact_witness)
    assert_equal(len(certificate.cells), 1)
    assert_equal(certificate.cells[0].low, low)
    assert_equal(certificate.cells[0].high, high)
    print("WIDTH_OVERFLOW_LEDGER", certificate.nodes, certificate.terms)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
