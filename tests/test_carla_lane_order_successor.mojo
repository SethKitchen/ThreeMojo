# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""The lane search keeps the work, witness and cells of its predecessor.

The digests pin every field of the certificates the predecessor solver
produced for these cases. `_reference_expansion_center` is an independent
statement of the expansion center rule.
"""

from extensions.carla.curve_interval import _next_down, _next_up
from extensions.carla.geometry import PARAM_POLY3, RoadGeometry, _Sample
from extensions.carla.lane_distance import (
    _refinement_square as _normalized_square,
    _point_gap_scale,
)
from extensions.carla.lane_refinement import (
    _checked_center,
    _ClosedInterval,
    _ClosedIntervals,
    _continue_lane_certificate,
    _expansion_center,
    _goal_excludes,
    _LaneCertificate,
    _LaneExclusionGoal,
    _midpoint,
    _refine_lane_certificate,
    _run_lane_search,
)
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road_info import RoadInfoGeometry
from math.vector3 import Vector3
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_raises
from tests._lane_digest import certificate_digest
from tests._lazy_taylor_controls import _whole_certificate, _diagonal_road
from tests.test_carla_cross_candidate_certificates import _road


def _reference_expansion_center(
    low: Float64, high: Float64, best: Float64
) -> Float64:
    var center = min(max(best, low), high)
    if center <= low:
        var interior = _next_up(low)
        if interior > low and interior < high:
            return interior
        return _midpoint(low, high)
    if center >= high:
        var interior = _next_down(high)
        if interior > low and interior < high:
            return interior
        return _midpoint(low, high)
    return center


def test_expansion_center_ordered_finite_boundary_words() raises:
    var words: List[UInt64] = [
        0,
        1,
        2,
        0x000FFFFFFFFFFFFF,
        0x0010000000000000,
        0x3FEFFFFFFFFFFFFF,
        0x3FF0000000000000,
        0x3FF0000000000001,
        0x7FEFFFFFFFFFFFFE,
        0x7FEFFFFFFFFFFFFF,
    ]
    for i in range(len(words)):
        for j in range(i, len(words)):
            var low = bitcast[DType.float64](words[i])
            var high = bitcast[DType.float64](words[j])
            for best in [low, high, _midpoint(low, high)]:
                assert_equal(
                    bitcast[DType.uint64](_expansion_center(low, high, best)),
                    bitcast[DType.uint64](
                        _reference_expansion_center(low, high, best)
                    ),
                )
                assert_equal(
                    bitcast[DType.uint64](
                        _expansion_center(-high, -low, -best)
                    ),
                    bitcast[DType.uint64](
                        _reference_expansion_center(-high, -low, -best)
                    ),
                )


def _case(first_cell: Int, depth: Int) raises -> _LaneCertificate:
    var road = _road()
    var geometry = RoadGeometry.from_meters(
        PARAM_POLY3, 0.0, 0.0, 0.0, 0.0, 3.0
    )
    for i in range(4):
        var x = Float64(-1.0 if i % 2 == 0 else 1.0)
        geometry.samples.append(_Sample(x, 0.0, Float64(i), 1.0, 0.0))
    road.length = 3.0
    road.info.geometries[0] = RoadInfoGeometry._from_si(0.0, geometry)
    var location = Vector3(0, 1, 0)
    var pending = List[Tuple[Float64, Float64, Int]]()
    var seed = Float64(0.5)
    var root_low = Float64(0.0) if first_cell == 3 else Float64(0.1)
    if first_cell == 3:
        pending.append((0.0, 2.9, 0))
    elif first_cell == 0:
        pending.append((0.1, 2.9, 0))
    elif first_cell == 1:
        pending.append((0.1, 1.1, 0))
        pending.append((1.1, 2.9, 0))
        seed = 1.5
    else:
        pending.append((0.1, 2.1, 0))
        pending.append((2.1, 2.9, 0))
        seed = 2.5
    var certificate = _whole_certificate(road, location, root_low, 2.9, seed)
    with assert_raises(contains="numerical accuracy limit"):
        _run_lane_search(
            road,
            0,
            0,
            root_low,
            2.9,
            location,
            certificate,
            pending^,
            _ClosedIntervals(),
            List[_ClosedInterval](),
            (Float64(0.0), Float64(1.0)),
            100,
            10000,
            depth,
        )
    return certificate^


def test_dispatch_preserves_exact_work_witness_cells_and_depth_refusal() raises:
    var published: List[String] = [
        "4b01cae715c6eee94dcfc2470360524dd95d6388bb4276657da59ffc52b55daa",
        "fc5a3e036ffe325f7cc05b6b669e4b9f79b71b17b8952b6a75a11175588149be",
        "c7df460d9a10af1d7fafe28b8b8d5415ba4bcd39f02d7fab0ddc7379710943a3",
        "d3e999424965fda4625e7394cba3e7e48e705c3282834c161bdbcf2688d371ef",
        "545c7380481f755ad79303f1d4896fbc2d7ced816709d25700e6e9fd2fc0fc72",
        "6d11d4a2cee193d19e8b2db04f59aec3efe430be7ce133b6b3755ac1f04d252e",
        "1e4aa23ca97b57da4697c9461fee952be1a74901ec930a669c68f85c6d996fed",
        "3db9928705d6da5916d985e4b771369c5d3acb06c8ad1eb9f4f9cda9e05b9f0b",
        "cfa837f7241e95c3b87af4e9e64882be2717e5e5cf120e728d38fcfe948f08a0",
        "4a2932bd795ac13888b89ac75cd03b2e26ec98f047afa84aaa3496bba4e0caf3",
        "d2560c7a84dfaa8b72f7828d3816bcdb4173e848b02e9534ae4572e8f2147366",
        "3233ad7c22d63f3f75e5ab6d6cd715dd00311de14ef5903b022f58ec77b27674",
    ]
    var index = 0
    for depth in [0, 1, 3]:
        for first_cell in range(4):
            assert_equal(
                certificate_digest(_case(first_cell, depth)), published[index]
            )
            index += 1


def test_unavailable_dispatch_retains_original_work_and_refusal() raises:
    var road = _diagonal_road()
    var location = Vector3(0.4, 1, 0.6)
    var certificate = _whole_certificate(road, location, 0.4, 0.7, 0.4)
    var pending: List[Tuple[Float64, Float64, Int]] = [(0.4, 0.7, 0)]
    with assert_raises(contains="numerical accuracy limit"):
        _run_lane_search(
            road,
            0,
            0,
            0.4,
            0.7,
            location,
            certificate,
            pending^,
            _ClosedIntervals(),
            List[_ClosedInterval](),
            (Float64(0.0), Float64(1.0)),
            100,
            10000,
            1,
        )
    assert_equal(
        certificate_digest(certificate),
        "d66cbfb2b1252c8365dd84dc83dba12fa1cb0dd6ad0e6b8acac21fb5655d8aea",
    )


def test_tiny_positive_cell_preserves_exact_witness_and_work() raises:
    var road = _road()
    var location = Vector3(1, 0, 0)
    var low = Float64(1.0)
    var high = _next_up(low)
    var certificate = _whole_certificate(road, location, low, high, high)
    var pending: List[Tuple[Float64, Float64, Int]] = [(low, high, 0)]
    _run_lane_search(
        road,
        0,
        0,
        low,
        high,
        location,
        certificate,
        pending^,
        _ClosedIntervals(),
        List[_ClosedInterval](),
        None,
        100,
        100,
        96,
    )
    assert_equal(certificate.nodes, 1)
    assert_equal(certificate.exact_witness, True)
    assert_equal(
        certificate_digest(certificate),
        "c14a88d80137d2f5429393e2719af746d8d7e2d665e01ff7f623462d35c0dd52",
    )


def test_legitimate_continuation_reopens_after_incumbent_and_scale_changes() raises:
    var road = _road()
    var root = bitcast[DType.float64](UInt64(0x3FD7AE147A450500))
    var slope = bitcast[DType.float64](UInt64(1623) << UInt64(52))
    road.info.elevations[0].polynomial = CubicPolynomial._from_coefficients(
        -slope * root, slope, 0.0, 0.0, 0.0
    )
    var location = Vector3(0, 1, 0)
    var query: Array[Float64, 3] = [0.0, 1.0, 0.0]
    var external_road = _road()
    var terms = 0
    var external = _checked_center(external_road, 0, 0, 0.0, terms, 100)
    var goal_scale = _point_gap_scale(external, query)
    var goal = _LaneExclusionGoal(
        _normalized_square[3](external, query, goal_scale).high,
        goal_scale,
        False,
    )
    var certificate = _refine_lane_certificate(
        road, 0, 0, 0.1, 0.9, location, 0.5, 0.0, seed_only=True
    )
    var original_scale = certificate.scale
    var published: List[String] = [
        "b21e5438e2b8d41a5edbdbc2b2ec3cac250a339f782ba16ffdeb63f2a288fa4c",
        "bfe65c5a42e9627cd83cfade7ec6ab1baa3e69c964f6de6e326722a2433db7f1",
    ]
    for round in range(2):
        _continue_lane_certificate(
            road,
            0,
            0,
            0.1,
            0.9,
            location,
            certificate,
            Float64(0.0),
            1.0,
            30,
            2000,
            0,
            None,
            goal,
            external.copy(),
        )
        assert_equal(certificate_digest(certificate), published[round])
        assert_equal(certificate.s, root)
        assert_equal(certificate.point[2], 0.0)
        assert_equal(certificate.scale < original_scale, True)
        assert_equal(
            _goal_excludes(certificate.lower, certificate.scale, goal), True
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
