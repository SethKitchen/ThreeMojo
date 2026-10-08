# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Refusals of the optional spiral proofs and envelopes at their limits."""

from extensions.carla.curve_bounds import (
    _finite_spiral_ideal_branch,
    _lane_jet,
    _lane_jet_model_proof,
    _lane_width_box,
    _reference_jet,
    _reference_work,
    _try_lane_envelope_capture,
    _try_proof_expansion_jet,
    _unknown_point,
)
from extensions.carla.curve_interval import _Interval, _Jet, _ValueJet
from extensions.carla.geometry import (
    ARC,
    LINE,
    POLY3,
    SPIRAL,
    RoadGeometry,
    RoadGeometryKind,
    _GL_NODES,
    _GL_WEIGHTS,
    _Sample,
    with_arc,
    with_spiral,
)
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import (
    LANE_DRIVING,
    LaneId,
    NO_JUNCTION,
    RoadId,
    RoadInfoElevation,
    RoadInfoGeometry,
    RoadInfoLaneOffset,
    RoadInfoLaneWidth,
    SectionId,
)
from extensions.carla.spiral_domain_proof import (
    _SpiralDomainProof,
    _SpiralRootCapture,
    _spiral_proof_branch,
    _spiral_proof_matches,
    _try_pack_spiral_proof,
)
from extensions.carla.spiral_grouped_lane import _try_grouped_lane_jet
from extensions.carla.spiral_grouped_roundoff_proof import (
    _grouped_origin_error,
    _grouped_term,
    _spiral_grouped_domain_rate,
    _try_spiral_grouped_roundoff_envelope,
    _try_spiral_grouped_roundoff_envelope_metered,
)
from extensions.carla.spiral_moment_proof import (
    _all_spiral_nodes_quadrant_zero,
    _try_build_spiral_moments,
    _try_spiral_moment_expansion,
)
from extensions.carla.spiral_moment_table import (
    _SpiralMomentProof as _TableProof,
    _try_spiral_moment_expansion as _table_expansion,
)
from extensions.carla.spiral_roundoff_proof import (
    _sum2_envelope_error,
    _try_spiral_roundoff_envelope,
)
from math.vector3 import Vector3
from std.math import inf, isfinite, nan
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

comptime MAX = Float64(1.7976931348623157e308)
# Rate 18.2 over d in [0.15, 0.3] gives piece counts 2 and 3. Two pieces keep
# every Gauss node's phase just below a quarter turn; three pieces pass it.
comptime TURN_RATE = Float64(18.2)


def _spiral(
    end: Float64 = 1.0,
    length: Float64 = 10.0,
    start: Float64 = 0.0,
    heading: Float64 = 0.0,
    x: Float64 = 0.0,
    y: Float64 = 0.0,
) raises -> RoadGeometry:
    var base = RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, 10.0)
    var geometry = with_spiral(base^, start, end)
    geometry.length = length
    geometry.heading = heading
    geometry.x = x
    geometry.y = y
    return geometry^


def _road(
    var geometry: RoadGeometry,
    s0: Float64 = 0.0,
    road_length: Float64 = 10.0,
    inner: Float64 = 3.5,
    width_start: Float64 = 0.0,
    elevation: Float64 = 0.0,
    slope: Float64 = 0.0,
    geometries: Int = 1,
    offset_start: Float64 = 0.0,
) raises -> Road:
    var road = Road(
        RoadId(1),
        "spiral",
        road_length,
        NO_JUNCTION,
        RoadId(0),
        RoadId(0),
        True,
    )
    _ = road.add_section(SectionId(0), 0.0)
    for id in [-1, 0, 1]:
        var lane = road.sections[0].add_lane(LaneId(id))
        road.sections[0].lanes[lane].type = LANE_DRIVING
        if id != 0:
            road.sections[0].lanes[lane].info.widths.append(
                RoadInfoLaneWidth(
                    width_start, CubicPolynomial(inner, 0, 0, 0, width_start)
                )
            )
    for i in range(geometries):
        geometry.s = s0 + Float64(i) * 5.0
        road.info.geometries.append(
            RoadInfoGeometry(s0 + Float64(i) * 5.0, geometry.copy())
        )
    road.info.lane_offsets.append(
        RoadInfoLaneOffset(offset_start, CubicPolynomial(0, 0, 0, 0, 0))
    )
    road.info.elevations.append(
        RoadInfoElevation(0.0, CubicPolynomial(elevation, slope, 0, 0, 0))
    )
    return road^


def _lane(road: Road, id: Int = -1) raises -> Int:
    return road.sections[0].lane_index(LaneId(id))


def _value(low: Float64, high: Float64, error: Float64 = 0.0) -> _ValueJet:
    return _ValueJet(
        _Interval(low, high), _Interval.whole(), _Interval.whole(), error
    )


def _proof(
    low: Float64 = 0.5,
    high: Float64 = 2.0,
    first: Int = 1,
    last: Int = 1,
) -> _SpiralDomainProof:
    return _SpiralDomainProof(
        0, 0, _Interval(low, high), first, last, 0.0, 0.0, 0.0, 0.0
    )


# --- stored table -------------------------------------------------------------


def test_stored_gauss_table_is_symmetric_positive_and_finite() raises:
    # The grouped envelope relies on these facts instead of checking them.
    var nodes = materialize[_GL_NODES]()
    var weights = materialize[_GL_WEIGHTS]()
    assert_equal(weights[0], weights[4])
    assert_equal(weights[1], weights[3])
    for i in range(5):
        assert_true(isfinite(weights[i]) and weights[i] > 0.0)
        assert_true(isfinite(1.0 + nodes[i]))


# --- single-count envelope ----------------------------------------------------


def test_sum2_envelope_refuses_nonfinite_terms_and_overflowing_origins() raises:
    assert_equal(
        _sum2_envelope_error(_value(0.0, inf[DType.float64]()), 1, 0.0),
        inf[DType.float64](),
    )
    assert_equal(
        _sum2_envelope_error(_value(1.0, 1.0, inf[DType.float64]()), 1, 0.0),
        inf[DType.float64](),
    )
    assert_equal(
        _sum2_envelope_error(_value(1.0e292, 1.0e292), 1, MAX),
        inf[DType.float64](),
    )


def test_roundoff_envelope_refuses_each_unsupported_input() raises:
    var d = _Jet.variable(1.0, 2.0)
    var bad = nan[DType.float64]()
    assert_false(Bool(_try_spiral_roundoff_envelope(_spiral(y=bad), d, 1)))
    assert_false(Bool(_try_spiral_roundoff_envelope(_spiral(end=bad), d, 1)))
    var tiny = _Jet.variable(5.0e-11, 6.0e-11)
    assert_false(
        Bool(
            _try_spiral_roundoff_envelope(
                _spiral(end=1.0e308, length=1.0e-10), tiny, 1
            )
        )
    )
    var negative = _Jet.variable(1.0, 2.0)
    negative.error = -0.1
    assert_false(Bool(_try_spiral_roundoff_envelope(_spiral(), negative, 1)))
    var long_turn = _Jet.variable(3.5, 3.9)
    assert_false(
        Bool(
            _try_spiral_roundoff_envelope(
                _spiral(end=MAX, length=4.0), long_turn, 1
            )
        )
    )
    assert_false(Bool(_try_spiral_roundoff_envelope(_spiral(end=1.0e10), d, 1)))
    var far = _Jet.variable(8.0, 9.0)
    assert_false(
        Bool(_try_spiral_roundoff_envelope(_spiral(end=1.0e5), far, 1))
    )
    var small = _Jet.variable(0.1, 0.2)
    assert_false(Bool(_try_spiral_roundoff_envelope(_spiral(x=MAX), small, 1)))
    assert_false(Bool(_try_spiral_roundoff_envelope(_spiral(y=MAX), small, 1)))


# --- grouped envelope ---------------------------------------------------------


def test_grouped_terms_poison_their_sum_when_refused() raises:
    for which in range(7):
        var term = _value(1.0, 2.0)
        var count = 1
        if which == 0:
            count = 0
        elif which == 1:
            count = 321
        elif which == 2:
            term = _value(1.0, inf[DType.float64]())
        elif which == 3:
            term = _value(2.0, 1.0)
        elif which == 4:
            term.error = inf[DType.float64]()
        elif which == 5:
            term.error = -1.0
        else:
            term = _value(1.7e308, 1.7e308, 1.0e308)
        var ideal = _Interval.point(0.0)
        var magnitude = _Interval.point(0.0)
        var inherited = _Interval.point(0.0)
        _grouped_term(term, count, ideal, magnitude, inherited)
        assert_false(ideal.is_finite())


def test_grouped_origin_error_refuses_overflow() raises:
    var one = _Interval.point(1.0)
    var zero = _Interval.point(0.0)
    assert_equal(
        _grouped_origin_error(one, _Interval.point(MAX), zero, 5, 0.0),
        inf[DType.float64](),
    )
    assert_equal(
        _grouped_origin_error(_Interval.whole(), one, zero, 5, 0.0),
        inf[DType.float64](),
    )
    assert_equal(
        _grouped_origin_error(_Interval.point(1.0e292), one, zero, 5, MAX),
        inf[DType.float64](),
    )


def test_grouped_domain_rate_refuses_each_unsupported_input() raises:
    var d = _Jet.variable(1.0, 2.0)
    var bad = nan[DType.float64]()
    assert_false(Bool(_spiral_grouped_domain_rate(_spiral(length=bad), d, 1)))
    assert_false(Bool(_spiral_grouped_domain_rate(_spiral(length=0.0), d, 1)))
    assert_false(Bool(_spiral_grouped_domain_rate(_spiral(x=bad), d, 1)))
    assert_false(Bool(_spiral_grouped_domain_rate(_spiral(y=bad), d, 1)))
    assert_false(Bool(_spiral_grouped_domain_rate(_spiral(end=bad), d, 1)))
    var tiny = _Jet.variable(5.0e-11, 6.0e-11)
    assert_false(
        Bool(
            _spiral_grouped_domain_rate(
                _spiral(end=1.0e308, length=1.0e-10), tiny, 1
            )
        )
    )
    var huge = _Jet.variable(1.0e308, 1.0e308)
    huge.error = 1.0e308
    assert_false(
        Bool(_spiral_grouped_domain_rate(_spiral(length=MAX), huge, 1))
    )


def test_grouped_envelope_refuses_large_phases() raises:
    var long_turn = _Jet.variable(3.5, 3.9)
    assert_false(
        Bool(
            _try_spiral_grouped_roundoff_envelope(
                _spiral(end=MAX, length=4.0), long_turn, 1
            )
        )
    )
    var d = _Jet.variable(1.0, 2.0)
    assert_false(
        Bool(_try_spiral_grouped_roundoff_envelope(_spiral(end=1.0e10), d, 1))
    )
    var far = _Jet.variable(8.0, 9.0)
    assert_false(
        Bool(_try_spiral_grouped_roundoff_envelope(_spiral(end=1.0e5), far, 1))
    )


def test_metered_grouped_envelope_admission() raises:
    var d = _Jet.variable(1.0, 2.0)
    var terms = 0
    assert_false(
        Bool(
            _try_spiral_grouped_roundoff_envelope_metered(
                _spiral(), d, 0, terms, 1000
            )
        )
    )
    terms = 2000
    assert_false(
        Bool(
            _try_spiral_grouped_roundoff_envelope_metered(
                _spiral(), d, 1, terms, 1000
            )
        )
    )
    terms = 0
    assert_false(
        Bool(
            _try_spiral_grouped_roundoff_envelope_metered(
                _spiral(heading=1.0), d, 1, terms, 1000
            )
        )
    )


# --- grouped lane -------------------------------------------------------------


def _grouped(road: Road, low: Float64, high: Float64) raises -> Bool:
    var nodes = 0
    var terms = 0
    return Bool(
        _try_grouped_lane_jet(
            road, 0, _lane(road), low, high, nodes, terms, 1000, 100000
        )
    )


def test_grouped_lane_refuses_unsupported_records_and_counts() raises:
    assert_false(_grouped(_road(_spiral(), s0=2.0, road_length=12.0), 1.0, 2.0))
    assert_false(_grouped(_road(_spiral(), geometries=2), 1.0, 6.0))
    var line = RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, 10.0)
    assert_false(_grouped(_road(line^), 1.0, 2.0))
    assert_false(_grouped(_road(_spiral(heading=0.5)), 1.0, 2.0))
    assert_false(_grouped(_road(_spiral(start=0.1)), 1.0, 2.0))
    var long = _road(_spiral(end=1.0e-12, length=1.0e10), road_length=1.0e10)
    assert_false(_grouped(long, 1.0, 2.0e9))
    var wide = _road(_spiral(end=1.0e-6, length=200.0), road_length=200.0)
    assert_false(_grouped(wide, 1.0, 100.0))
    assert_false(_grouped(_road(_spiral(end=0.01)), 1.0, 3.0))


def test_grouped_lane_refuses_a_failing_second_count_and_infinite_axes() raises:
    var turn = _road(_spiral(end=TURN_RATE * 10.0))
    assert_false(_grouped(turn, 0.15, 0.3))
    var high = _road(_spiral(end=0.01, y=-1.5e308), inner=1.5e308)
    assert_false(_grouped(high, 1.0, 1.0))
    var raised = _road(_spiral(end=0.01), elevation=1.0e308, slope=1.0e308)
    assert_false(_grouped(raised, 1.0, 1.0))


# --- moment proof -------------------------------------------------------------


def test_quadrant_check_refuses_large_phases() raises:
    var long_turn = _Jet.variable(3.5, 3.9)
    assert_false(
        _all_spiral_nodes_quadrant_zero(
            _spiral(end=MAX, length=4.0), long_turn, 1
        )
    )
    var d = _Jet.variable(5.0, 6.0)
    assert_false(_all_spiral_nodes_quadrant_zero(_spiral(end=1.0e9), d, 1))


def test_moment_expansion_refuses_counts_and_domains() raises:
    var terms = 0
    var proof = _try_build_spiral_moments(1, terms, 1000000).value().copy()
    var d = _Jet.variable(1.0, 1.0)
    var origin = Vector3(0, 0, 0)
    var geometry = _spiral(end=0.01)
    assert_false(
        Bool(_try_spiral_moment_expansion(proof, geometry, d, (1, 2), origin))
    )
    var unbounded = _Jet.variable(1.0, inf[DType.float64]())
    assert_false(
        Bool(
            _try_spiral_moment_expansion(
                proof, geometry, unbounded, (1, 1), origin
            )
        )
    )
    var past = _Jet.variable(1.0, 20.0)
    assert_false(
        Bool(
            _try_spiral_moment_expansion(proof, geometry, past, (1, 1), origin)
        )
    )
    assert_false(
        Bool(
            _table_expansion(
                _TableProof(1), geometry, unbounded, (1, 1), origin
            )
        )
    )


# --- domain proof -------------------------------------------------------------


def _captured(low: Float64, high: Float64) -> _SpiralRootCapture:
    var captured = _SpiralRootCapture()
    captured.record_at = 0
    captured.low = low
    captured.high = high
    captured.d = _Jet.variable(low, high)
    captured.first_count = 1
    captured.last_count = 1
    captured.first_x_error = 0.0
    captured.first_y_error = 0.0
    captured.last_x_error = 0.0
    captured.last_y_error = 0.0
    return captured


def _pack(
    road: Road, low: Float64, high: Float64, captured: _SpiralRootCapture
) -> Bool:
    var terms = 0
    var units = 0
    return Bool(
        _try_pack_spiral_proof(road, low, high, 0, captured, 0, terms, units)
    )


def test_pack_refuses_each_invalid_station_and_capture() raises:
    var road = _road(_spiral(end=0.01))
    var bad = nan[DType.float64]()
    assert_true(_pack(road, 1.0, 2.0, _captured(1.0, 2.0)))
    assert_false(_pack(road, bad, 2.0, _captured(bad, 2.0)))
    assert_false(_pack(road, 1.0, bad, _captured(1.0, bad)))
    assert_false(_pack(road, -1.0, 2.0, _captured(-1.0, 2.0)))
    assert_false(_pack(road, 2.0, 1.0, _captured(2.0, 1.0)))
    var later = _road(_spiral(end=0.01), s0=2.0, road_length=12.0)
    assert_false(_pack(later, 1.0, 3.0, _captured(1.0, 3.0)))
    var two = _road(_spiral(end=0.01), geometries=2)
    assert_false(_pack(two, 1.0, 6.0, _captured(1.0, 6.0)))
    var unbounded = _captured(1.0, 2.0)
    unbounded.d = _Jet.variable(1.0, inf[DType.float64]())
    assert_false(_pack(road, 1.0, 2.0, unbounded))
    var slope = _captured(1.0, 2.0)
    slope.d.first = _Interval.whole()
    assert_false(_pack(road, 1.0, 2.0, slope))
    for which in range(5):
        var errors = _captured(1.0, 2.0)
        if which == 0:
            errors.first_x_error = bad
        elif which == 1:
            errors.first_y_error = -1.0
        elif which == 2:
            errors.last_x_error = bad
        elif which == 3:
            errors.last_x_error = -1.0
        else:
            errors.last_y_error = -1.0
        assert_false(_pack(road, 1.0, 2.0, errors))


def test_pack_refuses_a_second_count_past_a_quarter_turn() raises:
    var road = _road(_spiral(end=TURN_RATE * 10.0))
    var captured = _captured(0.15, 0.3)
    captured.first_count = 2
    captured.last_count = 3
    assert_false(_pack(road, 0.15, 0.3, captured))


def _matches(
    proof: _SpiralDomainProof,
    d: _Jet,
    counts: Tuple[Int, Int] = (1, 1),
    low: Float64 = 1.0,
    high: Float64 = 1.5,
    root_low: Float64 = 0.0,
    root_high: Float64 = 5.0,
) raises -> Bool:
    return _spiral_proof_matches(
        proof, _spiral(end=0.01), 0, low, high, root_low, root_high, d, counts
    )


def test_proof_matching_refuses_each_inconsistent_input() raises:
    var d = _Jet.variable(1.0, 1.5)
    var bad = nan[DType.float64]()
    assert_true(_matches(_proof(), d))
    assert_false(_matches(_proof(), d, low=bad))
    assert_false(_matches(_proof(), d, high=bad))
    assert_false(_matches(_proof(), d, root_low=bad))
    assert_false(_matches(_proof(), d, root_high=bad))
    assert_false(_matches(_proof(), d, root_low=5.0, root_high=4.0))
    assert_false(_matches(_proof(), _Jet.variable(1.0, inf[DType.float64]())))
    assert_false(_matches(_proof(), _Jet.variable(0.0, 1.0)))
    assert_false(_matches(_proof(), _Jet.variable(1.0, 20.0)))
    var whole = _proof()
    whole.rounded_d = _Interval.whole()
    assert_false(_matches(whole, d))
    assert_false(_matches(_proof(0.5, 20.0), d))
    assert_false(_matches(_proof(0.5, 1.2), d))
    var slope = _Jet.variable(1.0, 1.5)
    slope.first = _Interval.whole()
    assert_false(_matches(_proof(), slope))
    var curve = _Jet.variable(1.0, 1.5)
    curve.second = _Interval.whole()
    assert_false(_matches(_proof(), curve))
    for counts in [(0, 1), (1, 65), (2, 1), (1, 3)]:
        assert_false(_matches(_proof(), d, counts))
    assert_false(_matches(_proof(first=2, last=1), d))
    assert_false(_matches(_proof(first=1, last=3), d))
    for which in range(5):
        var errors = _proof()
        if which == 0:
            errors.first_x_error = bad
        elif which == 1:
            errors.first_y_error = -1.0
        elif which == 2:
            errors.last_x_error = bad
        elif which == 3:
            errors.last_x_error = -1.0
        else:
            errors.last_y_error = -1.0
        assert_false(_matches(errors, d))


def test_proof_branch_translation_has_no_scalar_error() raises:
    var d = _Jet.variable(1.0, 1.5)
    for translation in [Vector3(0, 1, 0), Vector3(0, 0, 1)]:
        var point = _spiral_proof_branch(
            _proof(), _spiral(end=0.01), d, 1, translation
        )
        assert_equal(point[0].error, inf[DType.float64]())


# --- curve bounds paths -------------------------------------------------------


def test_reference_jet_for_lines_arcs_wide_spirals_and_bare_samples() raises:
    var d = _Jet.variable(1.0, 2.0)
    var origin = Vector3(0, 0, 0)
    var line = RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, 10.0)
    assert_true(_reference_jet(line, d, origin)[0].value.is_finite())
    var arc = with_arc(RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, 10.0), 0.1)
    assert_true(_reference_jet(arc, d, origin)[0].value.is_finite())
    var wide = _Jet.variable(0.1, 9.0)
    assert_false(
        _reference_jet(_spiral(end=1.0), wide, origin)[0].value.is_finite()
    )
    var bare = RoadGeometry(POLY3, 0.0, 0.0, 0.0, 0.0, 10.0)
    assert_false(_reference_jet(bare, d, origin)[0].value.is_finite())


def test_reference_work_and_finite_ideal_branch() raises:
    var two = _road(_spiral(end=0.01), geometries=2)
    assert_equal(_reference_work(two, 1.0, 6.0), -1)
    assert_false(_finite_spiral_ideal_branch(_unknown_point()))


def _envelope(
    road: Road, low: Float64, high: Float64, terms: Int = 0
) raises -> Bool:
    var captured = _SpiralRootCapture()
    var spent = terms
    return Bool(
        _try_lane_envelope_capture(
            road, 0, _lane(road), low, high, captured, spent, 100000
        )
    )


def test_lane_envelope_capture_refuses_each_unsupported_input() raises:
    var road = _road(_spiral(end=0.01))
    assert_false(_envelope(road, 1.0, 2.0, terms=-1))
    assert_false(_envelope(road, 1.0, 2.0, terms=200000))
    assert_false(
        _envelope(_road(_spiral(), s0=2.0, road_length=12.0), 1.0, 2.0)
    )
    assert_false(_envelope(_road(_spiral(), geometries=2), 1.0, 6.0))
    assert_false(_envelope(_road(_spiral(heading=0.5)), 1.0, 2.0))
    var long = _road(_spiral(end=1.0e-12, length=1.0e10), road_length=1.0e10)
    assert_false(_envelope(long, 1.0, 2.0e9))
    var wide = _road(_spiral(end=1.0e-6, length=200.0), road_length=200.0)
    assert_false(_envelope(wide, 1.0, 100.0))
    assert_false(_envelope(_road(_spiral(end=0.01)), 1.0, 3.0))
    assert_false(_envelope(_road(_spiral(end=TURN_RATE * 10.0)), 0.15, 0.3))


def test_lane_jets_need_records_and_refuse_translated_proofs() raises:
    var late = _road(_spiral(end=0.01), s0=2.0, road_length=12.0)
    with assert_raises(contains="geometry, elevation and offset"):
        _ = _lane_jet(late, 0, _lane(late), 1.0, 2.0)
    var offset = _road(_spiral(end=0.01), offset_start=1.5)
    with assert_raises(contains="geometry, elevation and offset"):
        _ = _lane_jet(offset, 0, _lane(offset), 1.0, 2.0)
    var widths = _road(_spiral(end=0.01), width_start=1.5)
    with assert_raises(contains="width record"):
        _ = _lane_width_box(widths, 0, _lane(widths), 1.0, 2.0)
    var road = _road(_spiral(end=0.01))
    var captured = _SpiralRootCapture()
    for translation in [
        Vector3(1, 0, 0),
        Vector3(0, 1, 0),
        Vector3(0, 0, 1),
    ]:
        _ = _lane_jet_model_proof[False](
            road,
            0,
            _lane(road),
            1.0,
            1.5,
            translation,
            _proof(),
            0.0,
            5.0,
            captured,
        )
    # LINE and ARC return earlier; a sampled record reaches the proof check.
    var sampled = RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, 10.0)
    sampled.kind = POLY3
    for s in [0.0, 5.0, 10.0]:
        sampled.samples.append(_Sample(s, 0.0, s, 1.0, 0.0))
    var straight = _road(sampled^)
    _ = _lane_jet_model_proof[False](
        straight,
        0,
        _lane(straight),
        1.0,
        1.5,
        Vector3(0, 0, 0),
        _proof(),
        0.0,
        5.0,
        captured,
    )


def test_proof_expansion_refuses_unsupported_stations() raises:
    var road = _road(_spiral(end=0.01))
    var query = Vector3(1, 1, 0)
    var bad = nan[DType.float64]()
    var lane = _lane(road)
    assert_false(
        Bool(
            _try_proof_expansion_jet(
                road, 0, lane, bad, query, 1.0, 0.0, 5.0, _proof()
            )
        )
    )
    var late = _road(_spiral(end=0.01), s0=2.0, road_length=12.0)
    assert_false(
        Bool(
            _try_proof_expansion_jet(
                late, 0, lane, 1.0, query, 1.0, 0.0, 5.0, _proof()
            )
        )
    )
    var line = RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, 10.0)
    var straight = _road(line^)
    assert_false(
        Bool(
            _try_proof_expansion_jet(
                straight, 0, lane, 1.0, query, 1.0, 0.0, 5.0, _proof()
            )
        )
    )
    # 5.7 - 0.7 is just above 5, so its rounded difference straddles the
    # piece-count boundary at 5 when the spiral has no curvature growth.
    var straddle = _road(_spiral(end=0.0), s0=0.7, road_length=10.7)
    assert_false(
        Bool(
            _try_proof_expansion_jet(
                straddle, 0, lane, 5.7, query, 1.0, 0.0, 10.0, _proof(0.5, 9.0)
            )
        )
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
