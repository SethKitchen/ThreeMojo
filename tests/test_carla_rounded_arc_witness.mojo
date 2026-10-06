# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Exact rounded-ARC proof, guard, budget, cover, and tie controls."""

from extensions.carla.curve_distance import (
    _wide_point_order,
)
from extensions.carla.lane_distance import (
    _normalized_square,
)
from extensions.carla.curve_interval import _next_down, _next_up
from extensions.carla.curve_rounded_arc import (
    _RoundedBox,
    _rounded_add,
    _rounded_arc_context,
    _rounded_fma,
    _rounded_madd,
    _rounded_multiply,
    _rounded_operand,
)
from extensions.carla.geometry import ARC
from extensions.carla.lane_refinement import (
    _ClosedInterval,
    _LaneCertificate,
    _lane_certificate_dominates,
    _refine_lane_certificate,
    _resume_lane_certificate,
    _try_rounded_arc_witness,
)
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import LaneId, RoadInfoLaneWidth
from math.vector3 import Vector3
from std.math import inf, isfinite
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests.test_carla_cross_candidate_certificates import _road


def _arc() raises -> Road:
    var road = _road(width=3.5)
    road.length = 31.41592653589793
    road.info.geometries[0].geometry.kind = ARC
    road.info.geometries[0].geometry.length = road.length
    road.info.geometries[0].geometry.x = 60.0
    road.info.geometries[0].geometry.curvature_start = -0.05
    road.info.lane_offsets[0].polynomial = CubicPolynomial.constant(0.0)
    return road^


def _low() -> Float64:
    return bitcast[DType.float64](UInt64(0x3D19000000000000))


def _high() -> Float64:
    return bitcast[DType.float64](UInt64(0x3FD0000000000186))


def _query(red: Bool = False) -> Vector3:
    if red:
        return Vector3(
            bitcast[DType.float32](UInt32(0x426EF980)),
            bitcast[DType.float32](UInt32(0x3FF2F18C)),
            bitcast[DType.float32](UInt32(0x3BA21D00)),
        )
    return Vector3(
        bitcast[DType.float32](UInt32(0x426FAE4E)),
        bitcast[DType.float32](UInt32(0x3FF14FFE)),
        bitcast[DType.float32](UInt32(0x3BB9C100)),
    )


def _wide_query(location: Vector3) -> Array[Float64, 3]:
    return [Float64(location.x), Float64(location.y), Float64(location.z)]


def _loose(
    road: Road, s: Float64, location: Vector3
) raises -> _LaneCertificate:
    var point = road._lane_center(0, 0, s)
    var upper = _normalized_square[3](point, _wide_query(location), 1.0).high
    var cells: List[_ClosedInterval] = [
        _ClosedInterval(_low(), _high(), 17, 0.0, 1.0)
    ]
    return _LaneCertificate(s, point^, 1.0, 0.0, upper, False, cells^, 7, 11)


def _old_cover(certificate: _LaneCertificate, s: Float64) raises:
    assert_false(certificate.exact_witness)
    assert_equal(certificate.s, s)
    assert_equal(certificate.lower, 0.0)
    assert_equal(len(certificate.cells), 1)
    assert_equal(certificate.cells[0].low, _low())
    assert_equal(certificate.cells[0].high, _high())
    assert_equal(certificate.cells[0].depth, 17)


def test_normal_operand_guard_is_closed_and_rejects_zero_crossings() raises:
    var low = bitcast[DType.float64](UInt64(623) << UInt64(52))
    var high = bitcast[DType.float64](UInt64(1423) << UInt64(52))
    for value in [low, high, -low, -high, Float64(0.0)]:
        assert_true(_rounded_operand(value))
    for value in [_next_down(low), _next_up(high), inf[DType.float64]()]:
        assert_false(_rounded_operand(value))
    assert_false(_rounded_operand(bitcast[DType.float64](UInt64(1))))
    assert_false(_RoundedBox.bounds(0.0, 1.0).known)
    assert_false(_RoundedBox.bounds(-1.0, 1.0).known)
    assert_false(_RoundedBox.bounds(1.0, 0.0).known)
    assert_true(_RoundedBox.bounds(-0.0, 0.0).known)
    # Boundary products are finite and normal before the reusable output
    # guard rejects them. The primitive itself cannot underflow/overflow.
    assert_true(_rounded_multiply(low, low) > 0.0)
    assert_true(isfinite(_rounded_multiply(high, high)))
    assert_false((_RoundedBox.point(low) * _RoundedBox.point(low)).known)
    assert_false((_RoundedBox.point(high) * _RoundedBox.point(high)).known)


def test_fused_and_unfused_paths_are_both_enclosed() raises:
    var a = Float64(1.0000000074505806)
    var b = Float64(0.9999999925494194)
    var c = Float64(-0.5)
    var separate = _rounded_add(_rounded_multiply(a, b), c)
    var fused = _rounded_fma(a, b, c)
    assert_true(fused < separate)
    var box = _rounded_madd(
        _RoundedBox.point(a), _RoundedBox.point(b), _RoundedBox.point(c)
    )
    assert_true(box.known)
    assert_equal(box.low, fused)
    assert_equal(box.high, separate)
    assert_equal(box.high, 0.5)
    assert_equal(box.low, _next_down(0.5))


def test_supported_box_encloses_checked_scalar_values() raises:
    var road = _arc()
    var context = _rounded_arc_context(road, 0, 0, _low(), _high())
    assert_true(Bool(context))
    var model = context.value()
    var box = model.center(_low(), _high())
    for axis in range(3):
        assert_true(box[axis].known)
    for i in range(65):
        var s = _low() + (_high() - _low()) * (Float64(i) / 64.0)
        var point = road._lane_center(0, 0, s)
        for axis in range(3):
            assert_true(box[axis].low <= point[axis])
            assert_true(point[axis] <= box[axis].high)
    var plateau_last = bitcast[DType.float64](UInt64(0x3D1EAF57ABD5EAF4))
    var plateau = model.center(_low(), plateau_last)
    var witness = road._lane_center(0, 0, _low())
    for axis in range(3):
        assert_equal(plateau[axis].low, witness[axis])
        assert_equal(plateau[axis].high, witness[axis])
    assert_true(road._lane_center(0, 0, _next_up(plateau_last))[0] > witness[0])


def test_unsupported_branches_records_and_ranges_return_unknown() raises:
    var road = _arc()
    road.info.geometries[0].geometry.heading = 0.1
    assert_false(Bool(_rounded_arc_context(road, 0, 0, _low(), _high())))
    road.info.geometries[0].geometry.heading = 0.0
    road.sections[0].lanes[0].info.widths[0].polynomial.b = 1.0
    assert_false(Bool(_rounded_arc_context(road, 0, 0, _low(), _high())))
    road.sections[0].lanes[0].info.widths[0].polynomial.b = 0.0
    road.sections[0].lanes[0].info.widths[0].s = 0.01
    assert_false(Bool(_rounded_arc_context(road, 0, 0, _low(), _high())))
    road.sections[0].lanes[0].info.widths[0].s = 0.0
    var model = _rounded_arc_context(road, 0, 0, _low(), _high()).value()
    assert_false(model.center(0.0, _high())[0].known)
    assert_false(model.center(31.0, road.length)[0].known)
    assert_true(model.center(20.0, 21.0)[0].known)
    model.curvature = _RoundedBox.point(0.2)
    assert_false(model.center(8.0, 9.0)[0].known)
    road.info.geometries[0].geometry.curvature_start = 1e-200
    assert_false(Bool(_rounded_arc_context(road, 0, 0, _low(), _high())))
    road.info.geometries[0].geometry.curvature_start = -0.05
    road.info.elevations[0].polynomial.a = 1e200
    assert_false(Bool(_rounded_arc_context(road, 0, 0, _low(), _high())))


def test_constant_record_variations_and_every_contributing_width() raises:
    var road = _arc()
    road.info.geometries[0].geometry.x = -60.0
    road.info.geometries[0].geometry.y = 2.0
    road.info.lane_offsets[0].polynomial = CubicPolynomial.constant(0.25)
    road.info.elevations[0].polynomial = CubicPolynomial.constant(3.0)
    road.sections[0].lanes[0].id = LaneId(1)
    var context = _rounded_arc_context(road, 0, 0, _low(), _high())
    assert_true(Bool(context))
    var model = context.value()
    var box = model.center(_low(), _high())
    for s in [_low(), Float64(0.125), _high()]:
        var point = road._lane_center(0, 0, s)
        for axis in range(3):
            assert_true(box[axis].known)
            assert_true(box[axis].low <= point[axis])
            assert_true(point[axis] <= box[axis].high)
    var nested = _arc()
    var outer = nested.sections[0].add_lane(LaneId(-2))
    nested.sections[0].lanes[outer].info.widths.append(
        RoadInfoLaneWidth(0.0, CubicPolynomial.constant(2.0))
    )
    var inner = nested.sections[0].lane_index(LaneId(-1))
    assert_true(Bool(_rounded_arc_context(nested, 0, outer, _low(), _high())))
    nested.sections[0].lanes[inner].info.widths[0].polynomial.b = 0.01
    assert_false(Bool(_rounded_arc_context(nested, 0, outer, _low(), _high())))


def test_both_native_query_words_get_complete_exact_witnesses() raises:
    var road = _arc()
    for red in [False, True]:
        var location = _query(red)
        var certificate = _loose(road, _low(), location)
        _resume_lane_certificate(
            road, 0, 0, _low(), _high(), location, certificate, 0.0, 1.0
        )
        assert_true(certificate.exact_witness)
        assert_equal(certificate.s, _low())
        assert_equal(certificate.nodes, 7 + 45)
        assert_equal(certificate.terms, 11 + 45 + 1 + 22)
        assert_equal(
            bitcast[DType.uint64](certificate.point[0]),
            UInt64(0x404E000000000003),
        )
        assert_equal(certificate.point[1], 1.75)
        assert_equal(certificate.point[2], 0.0)
        assert_equal(len(certificate.cells), 1)
        assert_equal(certificate.cells[0].low, certificate.s)
        assert_equal(certificate.cells[0].high, certificate.s)


def test_general_search_resumption_keeps_its_incumbent_on_a_plateau() raises:
    var road = _arc()
    var location = _query()
    var certificate = _refine_lane_certificate(
        road, 0, 0, _low(), _high(), location, _low(), 0.0
    )
    var s = certificate.s
    var point = certificate.point.copy()
    _resume_lane_certificate(
        road, 0, 0, _low(), _high(), location, certificate, 0.0, 1.0
    )
    assert_true(certificate.exact_witness)
    assert_equal(certificate.s, s)
    for axis in range(3):
        assert_equal(certificate.point[axis], point[axis])
    var line_road = _road(width=3.5)
    line_road.info.geometries[0].geometry.x = 60.0
    line_road.info.lane_offsets[0].polynomial = CubicPolynomial.constant(0.0)
    var line = _refine_lane_certificate(
        line_road, 0, 0, _low(), _high(), location, _low(), 0.0
    )
    assert_true(line.exact_witness)
    assert_equal(
        _wide_point_order(line.point, certificate.point, _wide_query(location)),
        0,
    )
    assert_true(
        _lane_certificate_dominates(
            line, 1, certificate, 2, _wide_query(location)
        )
    )
    assert_false(
        _lane_certificate_dominates(
            certificate, 2, line, 1, _wide_query(location)
        )
    )


def test_interior_plateau_witness_keeps_ordinary_path_without_attempt_debits() raises:
    var road = _arc()
    var location = _query()
    var interior = bitcast[DType.float64](UInt64(0x3D1A000000000000))
    var tied = _loose(road, interior, location)
    assert_false(
        _try_rounded_arc_witness(
            road,
            0,
            0,
            _low(),
            _high(),
            _wide_query(location),
            tied,
            16384,
            2000000,
            96,
        )
    )
    assert_equal(tied.nodes, 7)
    assert_equal(tied.terms, 11)
    _old_cover(tied, interior)
    # The ordinary solver can still finish its unchanged spatial target.
    _resume_lane_certificate(
        road, 0, 0, _low(), _high(), location, tied, 100.0, 1.0
    )
    assert_false(tied.exact_witness)
    assert_equal(tied.s, interior)
    assert_true(tied.nodes > 7)
    assert_true(tied.terms > 11)


def test_inconclusive_proof_keeps_cover_and_all_spent_work() raises:
    var road = _arc()
    var location = _query()
    var certificate = _loose(road, _high(), location)
    var query = _wide_query(location)
    assert_false(
        _try_rounded_arc_witness(
            road, 0, 0, _low(), _high(), query, certificate, 16384, 2000000, 96
        )
    )
    _old_cover(certificate, _high())
    assert_equal(certificate.nodes, 8)
    assert_equal(certificate.terms, 14)
    road.info.geometries[0].geometry.heading = 0.1
    assert_false(
        _try_rounded_arc_witness(
            road, 0, 0, _low(), _high(), query, certificate, 16384, 2000000, 96
        )
    )
    _old_cover(certificate, _high())
    assert_equal(certificate.nodes, 9)
    assert_equal(certificate.terms, 15)


def test_proof_debits_before_work_and_never_hides_exhaustion() raises:
    var road = _arc()
    var location = _query()
    var certificate = _loose(road, _low(), location)
    with assert_raises(contains="interval work limit"):
        _resume_lane_certificate(
            road,
            0,
            0,
            _low(),
            _high(),
            location,
            certificate,
            0.0,
            1.0,
            max_nodes=7,
        )
    assert_equal(certificate.nodes, 7)
    assert_equal(certificate.terms, 11)
    _old_cover(certificate, _low())
    with assert_raises(contains="quadrature work limit"):
        _resume_lane_certificate(
            road,
            0,
            0,
            _low(),
            _high(),
            location,
            certificate,
            0.0,
            1.0,
            max_terms=11,
        )
    assert_equal(certificate.nodes, 8)
    assert_equal(certificate.terms, 11)
    _old_cover(certificate, _low())
    assert_false(
        _try_rounded_arc_witness(
            road,
            0,
            0,
            _low(),
            _high(),
            _wide_query(location),
            certificate,
            16384,
            2000000,
            0,
        )
    )
    _old_cover(certificate, _low())
    with assert_raises(contains="numerical accuracy limit"):
        _resume_lane_certificate(
            road,
            0,
            0,
            _low(),
            _high(),
            location,
            certificate,
            0.0,
            1.0,
            max_depth=0,
        )
    assert_true(certificate.nodes > 8)
    assert_true(certificate.terms > 11)
    _old_cover(certificate, _low())
    var retry_nodes = certificate.nodes
    with assert_raises(contains="interval work limit"):
        _resume_lane_certificate(
            road,
            0,
            0,
            _low(),
            _high(),
            location,
            certificate,
            0.0,
            1.0,
            max_nodes=retry_nodes + 3,
        )
    assert_equal(certificate.nodes, retry_nodes + 3)
    _old_cover(certificate, _low())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
