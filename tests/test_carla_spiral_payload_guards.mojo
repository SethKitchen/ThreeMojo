# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Adversarial immutable proof payload and request association controls.

An accepted baseline precedes each independent mutation. These private-API
controls must reject corrupt metadata and retain already reserved work.
"""

from extensions.carla.curve_interval import _Interval, _Jet
from extensions.carla.curve_sum2 import _sum2_supported_environment
from extensions.carla.curve_bounds import _try_lane_envelope_capture
from extensions.carla.spiral_moment_proof import (
    _all_spiral_nodes_quadrant_zero,
    _try_build_spiral_moments,
    _try_spiral_moment_expansion,
)
from extensions.carla.spiral_grouped_lane import _try_grouped_lane_jet
from extensions.carla.road_info import RoadInfoGeometry
from extensions.carla.spiral_domain_proof import (
    _SpiralRootCapture,
    _try_pack_spiral_proof,
    _spiral_proof_matches,
    _spiral_proof_branch,
)
from math.vector3 import Vector3
from std.math import inf, isfinite
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_false, assert_true
from tests._spiral_domain_controls import _geometry, _road, _capture, _proof


def test_capture_rejects_station_guards_after_reservation() raises:
    var road = _road(_geometry())
    var captured = _capture(road, 2.125, 2.25)
    var nan = bitcast[DType.float64](UInt64(0x7FF8000000000001))
    for kind in range(5):
        var low = 2.125
        var high = 2.25
        if kind == 1:
            low = nan
        elif kind == 2:
            high = nan
        elif kind == 3:
            low = -1.0
        elif kind == 4:
            high = 2.0
        var terms = 0
        var units = 0
        var result = _try_pack_spiral_proof(
            road, low, high, 0, captured, 0, terms, units
        )
        assert_equal(Bool(result), kind == 0)
        assert_equal(terms, 144)
        assert_equal(units, 144)


def test_capture_rejects_missing_and_crossed_geometry_records() raises:
    var road = _road(_geometry())
    var captured = _capture(road, 2.125, 2.25)
    road.info.geometries.clear()
    captured.record_at = -1
    var terms = 0
    var units = 0
    assert_false(
        Bool(
            _try_pack_spiral_proof(
                road, 2.125, 2.25, 0, captured, 0, terms, units
            )
        )
    )
    assert_equal(terms, 144)
    road = _road(_geometry())
    captured.record_at = 0
    road.info.geometries.append(RoadInfoGeometry(2.2, _geometry()))
    terms = 0
    units = 0
    assert_false(
        Bool(
            _try_pack_spiral_proof(
                road, 2.125, 2.25, 0, captured, 0, terms, units
            )
        )
    )
    assert_equal(terms, 144)


def test_capture_each_stored_error_field_is_independently_checked() raises:
    var road = _road(_geometry())
    var original = _capture(road, 2.125, 2.25)
    for kind in range(11):
        var captured = original
        if kind == 1:
            captured.first_x_error = inf[DType.float64]()
        elif kind == 2:
            captured.first_x_error = -1.0
        elif kind == 3:
            captured.first_y_error = inf[DType.float64]()
        elif kind == 4:
            captured.first_y_error = -1.0
        elif kind == 5:
            captured.last_x_error = inf[DType.float64]()
        elif kind == 6:
            captured.last_x_error = -1.0
        elif kind == 7:
            captured.last_y_error = inf[DType.float64]()
        elif kind == 8:
            captured.last_y_error = -1.0
        elif kind == 9:
            captured.d.error = inf[DType.float64]()
        elif kind == 10:
            captured.d.value = _Interval.whole()
        var terms = 0
        var units = 0
        assert_equal(
            Bool(
                _try_pack_spiral_proof(
                    road, 2.125, 2.25, 0, captured, 0, terms, units
                )
            ),
            kind == 0,
        )
        assert_equal(terms, 144)
        assert_equal(units, 144)


def test_query_station_association_rejects_each_invalid_operand() raises:
    var geometry = _geometry()
    var road = _road(geometry.copy())
    var proof = _proof(road, 2.125, 2.25)
    var d = _Jet.variable(2.125, 2.25)
    var nan = bitcast[DType.float64](UInt64(0x7FF8000000000001))
    for kind in range(9):
        var low = 2.125
        var high = 2.25
        var root_low = 2.125
        var root_high = 2.25
        if kind == 1:
            low = nan
        elif kind == 2:
            high = nan
        elif kind == 3:
            root_low = nan
        elif kind == 4:
            root_high = nan
        elif kind == 5:
            high = 2.0
        elif kind == 6:
            root_low = 3.0
        elif kind == 7:
            low = 2.0
        elif kind == 8:
            high = 2.5
        assert_equal(
            _spiral_proof_matches(
                proof, geometry, 0, low, high, root_low, root_high, d, (4, 4)
            ),
            kind == 0,
        )


def test_query_domain_and_count_metadata_cannot_authorize_reuse() raises:
    var geometry = _geometry()
    var road = _road(geometry.copy())
    var original = _proof(road, 2.125, 2.25)
    for kind in range(19):
        var proof = original
        var d = _Jet.variable(2.125, 2.25)
        var counts: Tuple[Int, Int] = (4, 4)
        if kind == 1:
            d.value = _Interval.whole()
        elif kind == 2:
            d.value.low = 0.0
        elif kind == 3:
            d.value.high = 20.0
        elif kind == 4:
            proof.rounded_d = _Interval.whole()
        elif kind == 5:
            proof.rounded_d.low = 0.0
        elif kind == 6:
            proof.rounded_d.high = 20.0
        elif kind == 7:
            proof.rounded_d = _Interval(3.0, 2.0)
        elif kind == 8:
            proof.rounded_d.high = 2.2
        elif kind == 9:
            d.second = _Interval.whole()
        elif kind == 10:
            counts = (0, 4)
        elif kind == 11:
            counts = (4, 65)
        elif kind == 12:
            counts = (4, 3)
        elif kind == 13:
            counts = (2, 4)
        elif kind == 14:
            proof.first_count = 0
        elif kind == 15:
            proof.last_count = 65
        elif kind == 16:
            proof.last_count = 3
        elif kind == 17:
            proof.first_count = 2
        elif kind == 18:
            d.first = _Interval.whole()
        assert_equal(
            _spiral_proof_matches(
                proof, geometry, 0, 2.125, 2.25, 2.125, 2.25, d, counts
            ),
            kind == 0,
        )


def test_query_error_metadata_each_field_and_translation() raises:
    var geometry = _geometry()
    var road = _road(geometry.copy())
    var original = _proof(road, 2.125, 2.25)
    var d = _Jet.variable(2.125, 2.25)
    for kind in range(9):
        var proof = original
        if kind == 1:
            proof.first_x_error = inf[DType.float64]()
        elif kind == 2:
            proof.first_x_error = -1.0
        elif kind == 3:
            proof.first_y_error = inf[DType.float64]()
        elif kind == 4:
            proof.first_y_error = -1.0
        elif kind == 5:
            proof.last_x_error = inf[DType.float64]()
        elif kind == 6:
            proof.last_x_error = -1.0
        elif kind == 7:
            proof.last_y_error = inf[DType.float64]()
        elif kind == 8:
            proof.last_y_error = -1.0
        assert_equal(
            _spiral_proof_matches(
                proof, geometry, 0, 2.125, 2.25, 2.125, 2.25, d, (4, 4)
            ),
            kind == 0,
        )
    assert_true(_sum2_supported_environment())
    assert_true(
        _spiral_proof_matches(
            original, geometry, 0, 2.125, 2.25, 2.125, 2.25, d, (4, 4)
        )
    )
    for translation in [Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]:
        var point = _spiral_proof_branch(original, geometry, d, 4, translation)
        assert_equal(
            isfinite(point[0].error),
            translation.y == 0.0 and translation.z == 0.0,
        )
        assert_equal(
            isfinite(point[1].error),
            translation.y == 0.0 and translation.z == 0.0,
        )
        assert_true(point[0].value.is_finite())
        assert_true(point[1].value.is_finite())


def test_second_count_quadrant_refusal_keeps_complete_attempt_debit() raises:
    # The actual count union is (4, 5). Its four-piece node phase remains
    # below pi/4; the five-piece last node is above it. A proof of only the
    # first branch must never authorize the complete stored count union.
    var geometry = _geometry()
    geometry.curvature_end = 0.8242442928533806 * geometry.length
    var road = _road(geometry.copy())
    var captured = _capture(road, 1.3945, 1.3955)
    assert_equal(captured.first_count, 4)
    assert_equal(captured.last_count, 5)
    assert_true(_all_spiral_nodes_quadrant_zero(geometry, captured.d, 4))
    assert_false(_all_spiral_nodes_quadrant_zero(geometry, captured.d, 5))
    var terms = 17
    var units = 9
    assert_false(
        Bool(
            _try_pack_spiral_proof(
                road, 1.3945, 1.3955, 0, captured, 0, terms, units
            )
        )
    )
    assert_equal(terms, 289)
    assert_equal(units, 281)
    terms = 17
    var nodes = 3
    assert_false(
        Bool(
            _try_grouped_lane_jet(
                road, 0, 0, 1.3945, 1.3955, nodes, terms, 100, 10000
            )
        )
    )
    assert_equal(nodes, 4)
    assert_equal(terms, 41)
    terms = 17
    var output = _SpiralRootCapture()
    assert_false(
        Bool(
            _try_lane_envelope_capture(
                road, 0, 0, 1.3945, 1.3955, output, terms, 10000
            )
        )
    )
    assert_equal(terms, 2065)
    assert_equal(output.record_at, -1)
    var moment_terms = 0
    var moments = _try_build_spiral_moments(4, moment_terms, 10000)
    assert_true(Bool(moments))
    assert_false(
        Bool(
            _try_spiral_moment_expansion(
                moments.value(),
                geometry,
                captured.d,
                (captured.first_count, captured.last_count),
                Vector3(0, 0, 0),
            )
        )
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
