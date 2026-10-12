# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Real-road endpoint refusals under the original bounded coarse-box path."""
from extensions.carla.curve_bounds import _reference_work
from extensions.carla.geometry import LINE, SPIRAL, RoadGeometry
from extensions.carla.lane_refinement import (
    _ProofNodeWork,
    _chord_certificate_capture_with_nodes,
)
from extensions.carla.map_search import MapBuildBudget, _MapBuildWork
from extensions.carla.map_validation import _preflight_road_records
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import (
    LANE_DRIVING,
    NO_JUNCTION,
    LaneId,
    RoadId,
    RoadInfoElevation,
    RoadInfoGeometry,
    RoadInfoLaneOffset,
    RoadInfoLaneWidth,
    SectionId,
)
from extensions.carla.spiral_domain_proof import _SpiralRootCapture
from math.vector3 import Vector3
from std.math import inf
from std.testing import TestSuite, assert_equal, assert_false


def _road(first_refuses: Bool, last_refuses: Bool) raises -> Road:
    var road = Road._from_si(
        RoadId(1),
        "bounded endpoint preflight",
        4.0,
        NO_JUNCTION,
        RoadId(0),
        RoadId(0),
        True,
    )
    _ = road.add_section_meters(SectionId(0), 0.0)
    _ = road.sections[0].add_lane(LaneId(-1))
    road.sections[0].lanes[0].type = LANE_DRIVING
    road.sections[0].lanes[0].info.widths.append(
        RoadInfoLaneWidth._from_si(0.0, CubicPolynomial._constant_si(2.0))
    )
    road.info.elevations.append(
        RoadInfoElevation._from_si(0.0, CubicPolynomial._constant_si(0.0))
    )
    road.info.lane_offsets.append(
        RoadInfoLaneOffset._from_si(0.0, CubicPolynomial._constant_si(1.0))
    )
    var first = RoadGeometry.from_meters(
        SPIRAL if first_refuses else LINE, 0, 0, 0, 0, 2
    )
    first.curvature_start = 2e9
    first.curvature_end = 2e9
    var last = RoadGeometry.from_meters(
        SPIRAL if last_refuses else LINE, 2, 2, 0, 0, 2
    )
    last.curvature_start = 2e9
    last.curvature_end = 2e9
    road.info.geometries.append(RoadInfoGeometry._from_si(0.0, first^))
    road.info.geometries.append(RoadInfoGeometry._from_si(2.0, last^))
    var validation = _MapBuildWork(MapBuildBudget())
    _preflight_road_records(road, validation)
    assert_false(validation.exhausted)
    return road^


def _control(first_refuses: Bool, last_refuses: Bool) raises:
    var road = _road(first_refuses, last_refuses)
    assert_equal(_reference_work(road, 1.0, 3.0), -1)
    assert_equal(_reference_work(road, 1.0, 1.0), -1 if first_refuses else 1)
    assert_equal(_reference_work(road, 3.0, 3.0), -1 if last_refuses else 1)
    # A single original proof node admits the unresolved root and refuses
    # either child before traversal. The standard 2-million-term cap stays.
    var nodes = _ProofNodeWork(1, fail_on_limit=False)
    var captured = _SpiralRootCapture()
    var result = _chord_certificate_capture_with_nodes(
        road,
        0,
        0,
        1.0,
        3.0,
        Vector3(1, 0, 0),
        Vector3(3, 0, 0),
        captured,
        nodes,
    )
    assert_equal(result[0], inf[DType.float64]())
    for value in [result[1][0], result[1][1], result[1][2]]:
        assert_equal(value.low, -inf[DType.float64]())
        assert_equal(value.high, inf[DType.float64]())
    assert_equal(result[2], 0)
    assert_equal(nodes.used, 1)
    assert_equal(nodes.limit, 1)
    print("CHORD_REFUSAL", first_refuses, last_refuses, result[2], nodes.used)


def test_real_chord_first_endpoint_refusal() raises:
    _control(True, False)


def test_real_chord_last_endpoint_refusal() raises:
    _control(False, True)


def test_real_chord_admitted_endpoints_keep_derivative_fallback() raises:
    _control(False, False)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
