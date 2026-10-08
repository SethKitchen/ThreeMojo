# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Adversarial rounded-context and sample-dispatch boundary controls."""

from extensions.carla.curve_frozen_arc import (
    _frozen_arc_center,
    _frozen_arc_context,
)
from extensions.carla.curve_rounded_arc import (
    _RoundedBox,
    _rounded_arc_context,
    _rounded_constant,
    _rounded_madd,
)
from extensions.carla.curve_rounded_line import _rounded_line_axis_context
from extensions.carla.curve_sample_dispatch import _try_sample_dispatch_cuts
from extensions.carla.geometry import ARC, LINE, RoadGeometry
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import (
    LaneId,
    RoadInfoElevation,
    RoadInfoGeometry,
    RoadInfoLaneOffset,
    RoadInfoLaneWidth,
)
from math.vector3 import Vector3
from std.math import inf
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_false, assert_true
from tests._sample_dispatch_controls import _dispatch_road
from tests.test_carla_cross_candidate_certificates import _road


def _proof_road(arc: Bool = True) raises -> Road:
    var road = _road(width=2.0)
    road.info.geometries[0].geometry.kind = ARC if arc else LINE
    road.info.geometries[0].geometry.curvature_start = 0.125
    road.info.geometries[0].geometry.x = 16.0
    road.info.geometries[0].geometry.y = 8.0
    road.info.lane_offsets[0].polynomial = CubicPolynomial.constant(0.0)
    return road^


def _assert_refused(
    road: Road, arc: Bool, low: Float64 = 1.0, high: Float64 = 2.0
) raises:
    if arc:
        assert_false(Bool(_rounded_arc_context(road, 0, 0, low, high)))
    else:
        assert_false(Bool(_rounded_line_axis_context(road, 0, 0, low, high)))


def test_rounded_box_unknown_operands_propagate_on_both_sides() raises:
    var one = _RoundedBox.point(1.0)
    var unknown = _RoundedBox.unknown()
    assert_true(one.hull(_RoundedBox.point(2.0)).known)
    assert_false(unknown.hull(one).known)
    assert_false(one.hull(unknown).known)
    assert_false((unknown + one).known)
    assert_false((one + unknown).known)
    assert_false((unknown * one).known)
    assert_false((one * unknown).known)
    assert_false(_rounded_madd(unknown, one, one).known)
    assert_false(_rounded_madd(one, unknown, one).known)
    assert_false(_rounded_madd(one, one, unknown).known)
    # Every operand is supported, but the result crosses the forbidden zero
    # neighborhood. The fused path cannot rescue the unfused path's refusal.
    assert_false(
        _rounded_madd(
            _RoundedBox.bounds(1.0, 2.0), one, _RoundedBox.point(-1.5)
        ).known
    )
    var cubic = CubicPolynomial.constant(1.0)
    cubic.d = 0.125
    assert_false(_rounded_constant(cubic).known)


def test_contexts_reject_missing_geometry_wrong_kind_and_unowned_domain() raises:
    for arc in [False, True]:
        var road = _proof_road(arc)
        road.info.geometries.clear()
        _assert_refused(road, arc)
        road = _proof_road(arc)
        road.info.geometries[0].geometry.kind = LINE if arc else ARC
        _assert_refused(road, arc)
        road = _proof_road(arc)
        road.info.geometries[0].s = 1.5
        _assert_refused(road, arc)
        road = _proof_road(arc)
        _assert_refused(road, arc, 1.0, 5.0)
    var road = _proof_road(False)
    _assert_refused(road, False, -2.0, -1.0)


def test_contexts_require_active_profiles_and_width_records() raises:
    for arc in [False, True]:
        for field in range(3):
            var road = _proof_road(arc)
            if field == 0:
                road.info.lane_offsets[0].s = 1.5
            elif field == 1:
                road.info.elevations[0].s = 1.5
            else:
                road.sections[0].lanes[0].info.widths[0].s = 1.5
            _assert_refused(road, arc)
    for field in range(2):
        var road = _proof_road()
        if field == 0:
            road.info.lane_offsets.clear()
        else:
            road.info.elevations.clear()
        _assert_refused(road, True)
    # A LINE supports multiple records only when the whole owner domain
    # remains within one active constant record of each profile kind.
    var road = _proof_road(False)
    road.info.lane_offsets.append(
        RoadInfoLaneOffset(1.5, CubicPolynomial.constant(0.0))
    )
    _assert_refused(road, False)
    road = _proof_road(False)
    road.info.elevations.append(
        RoadInfoElevation(1.5, CubicPolynomial.constant(0.0))
    )
    _assert_refused(road, False)


def test_center_lane_and_positive_outer_lane_use_complete_constant_offsets() raises:
    for arc in [False, True]:
        var road = _proof_road(arc)
        road.sections[0].lanes[0].id = LaneId(0)
        if arc:
            assert_true(Bool(_rounded_arc_context(road, 0, 0, 1.0, 2.0)))
        else:
            assert_true(Bool(_rounded_line_axis_context(road, 0, 0, 1.0, 2.0)))
        _ = road.sections[0].add_lane(LaneId(1))
        _ = road.sections[0].add_lane(LaneId(2))
        for id in [1, 2]:
            var at = road.sections[0].lane_index(LaneId(id))
            road.sections[0].lanes[at].info.widths.append(
                RoadInfoLaneWidth(0.0, CubicPolynomial.constant(2.0))
            )
        var outer = road.sections[0].lane_index(LaneId(2))
        if arc:
            var model = _rounded_arc_context(road, 0, outer, 1.0, 2.0)
            assert_true(Bool(model))
            assert_equal(model.value().y.low, 11.0)
            assert_equal(model.value().speed.low, 0.625)
        else:
            var axis = _rounded_line_axis_context(road, 0, outer, 1.0, 2.0)
            assert_true(Bool(axis))
            assert_equal(axis.value().axis, 0)
            assert_equal(axis.value().slope, 1.0)


def test_context_refuses_arithmetic_outputs_outside_guarded_operand_range() raises:
    var huge = bitcast[DType.float64](UInt64(1423) << UInt64(52))
    for arc in [False, True]:
        var road = _proof_road(arc)
        road.sections[0].lanes[0].info.widths[0].polynomial.a = huge
        road.info.lane_offsets[0].polynomial.a = -huge
        _assert_refused(road, arc)
        road = _proof_road(arc)
        road.info.geometries[0].geometry.y = 1e200
        _assert_refused(road, arc)
        road = _proof_road(arc)
        road.info.geometries[0].geometry.length = 1e200
        _assert_refused(road, arc)
    var road = _proof_road()
    road.info.geometries[0].geometry.curvature_start = 0.0
    _assert_refused(road, True)
    road = _proof_road()
    road.info.geometries[0].geometry.x = 1e200
    _assert_refused(road, True)
    road = _proof_road()
    road.info.geometries[0].s = -1e200
    _assert_refused(road, True)
    road = _proof_road(False)
    road.info.geometries[0].geometry.length = -1.0
    _assert_refused(road, False)


def test_rounded_and_frozen_centers_refuse_outside_clamp_and_unsupported_products() raises:
    var road = _proof_road()
    var packed = _frozen_arc_context(road, 0, 0, 1.0, 2.0)
    assert_true(Bool(packed))
    var model = packed.value()
    var center = _frozen_arc_center(model, 1.0, 2.0, Vector3(0, 0, 0))
    assert_true(center[0].value.is_finite())
    assert_true(center[1].value.is_finite())
    assert_equal(center[2].value.low, 0.0)
    var beyond = _frozen_arc_center(model, 3.0, 4.0, Vector3(0, 0, 0))
    assert_false(beyond[0].value.is_finite())
    beyond = _frozen_arc_center(
        model, 1.0, inf[DType.float64](), Vector3(0, 0, 0)
    )
    assert_false(beyond[0].value.is_finite())
    model.start = _RoundedBox.point(3.0)
    assert_false(model.center(1.0, 2.0)[0].known)
    road.info.geometries[0].s = 1.5
    assert_false(Bool(_frozen_arc_context(road, 0, 0, 1.5, 2.0)))
    model = packed.value()
    model.curvature = _RoundedBox.point(1e-120)
    assert_false(model.center(1e-100, 2e-100)[0].known)
    model.curvature = _RoundedBox.point(-1.0)
    assert_false(model.center(2.0, 3.0)[0].known)


def _assert_dispatch_uncharged(
    road: Road, low: Float64 = 0.9, high: Float64 = 2.1
) raises:
    var nodes = 7
    var terms = 11
    assert_false(
        Bool(
            _try_sample_dispatch_cuts(road, low, high, nodes, terms, 100, 1000)
        )
    )
    assert_equal(nodes, 7)
    assert_equal(terms, 11)


def test_dispatch_rejects_bad_domains_record_joins_and_invalid_geometry() raises:
    var road = _dispatch_road()
    _assert_dispatch_uncharged(road, inf[DType.float64](), 2.1)
    _assert_dispatch_uncharged(road, 0.9, inf[DType.float64]())
    _assert_dispatch_uncharged(road, 2.1, 0.9)
    road.info.geometries[0].s = 1.0
    _assert_dispatch_uncharged(road)
    road = _dispatch_road()
    road.info.geometries.append(
        RoadInfoGeometry(1.5, RoadGeometry(LINE, 1.5, 0.0, 0.0, 0.0, 1.5))
    )
    _assert_dispatch_uncharged(road)
    for field in range(4):
        road = _dispatch_road()
        if field == 0:
            road.info.geometries[0].geometry.samples.clear()
        elif field == 1:
            road.info.geometries[0].s = -inf[DType.float64]()
        elif field == 2:
            road.info.geometries[0].s = -1.0
        else:
            road.info.geometries[0].geometry.length = inf[DType.float64]()
        _assert_dispatch_uncharged(road)
    road = _dispatch_road()
    road.info.geometries[0].geometry.length = 0.0
    _assert_dispatch_uncharged(road)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
