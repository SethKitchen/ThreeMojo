# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Refusals of the optional objective, dispatch and support helpers."""

from extensions.carla.curve_interval import _Interval, _Jet
from extensions.carla.curve_minimizer_support import _minimizer_support
from extensions.carla.curve_objective_model import (
    _restrict_objective_model,
    _try_objective_model,
)
from extensions.carla.curve_sample_dispatch import (
    _sample_dispatch_cut,
    _try_sample_dispatch_cuts,
)
from extensions.carla.geometry import LINE, POLY3, RoadGeometry, _Sample
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
from std.math import inf, isfinite, nan
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_true,
)

comptime MAX = Float64(1.7976931348623157e308)


def _jet(
    value: _Interval,
    first: _Interval = _Interval(-1.0, 1.0),
    second: _Interval = _Interval(0.0, 1.0),
    error: Float64 = 0.0,
) -> _Jet:
    return _Jet(value, first, second, error)


# --- objective model ----------------------------------------------------------


def _model(
    low: Float64 = 1.0,
    high: Float64 = 3.0,
    center_s: Float64 = 1.5,
    scale: Float64 = 1.0,
    domain: _Jet = _jet(_Interval(-1.0e300, 1.0e300)),
    center: _Jet = _jet(_Interval(0.0, 0.0)),
) -> Bool:
    return Bool(
        _try_objective_model(low, high, center_s, scale, domain, center)
    )


def test_objective_model_refuses_each_invalid_input() raises:
    var bad = nan[DType.float64]()
    assert_true(_model())
    assert_false(_model(low=bad))
    assert_false(_model(high=bad))
    assert_false(_model(center_s=bad))
    assert_false(_model(low=3.0, high=3.0, center_s=3.0))
    assert_false(_model(center_s=0.5))
    assert_false(_model(scale=bad))
    assert_false(_model(scale=0.0))
    assert_false(_model(domain=_jet(_Interval.whole())))
    assert_false(_model(domain=_jet(_Interval(0.0, 1.0), error=-1.0)))
    assert_false(_model(center=_jet(_Interval.whole())))
    assert_false(_model(center=_jet(_Interval(0.0, 0.0), _Interval.whole())))


def _restricted(
    domain: _Jet,
    center: _Jet,
    low: Float64 = 2.5,
    high: Float64 = 2.5,
) raises -> Bool:
    var model = _try_objective_model(1.0, 3.0, 1.5, 1.0, domain, center)
    return Bool(_restrict_objective_model(model.value(), low, high, 1.0))


def test_objective_restriction_refuses_overflow_and_empty_intersections() raises:
    var wide = _jet(_Interval(-1.0e300, 1.0e300), _Interval(-1.0e300, 1.0e300))
    var zero = _jet(_Interval(0.0, 0.0))
    var bad = nan[DType.float64]()
    assert_true(_restricted(wide, zero))
    assert_false(_restricted(wide, zero, low=bad))
    assert_false(_restricted(wide, zero, high=bad))
    assert_false(_restricted(wide, zero, low=0.5))
    assert_false(_restricted(wide, zero, high=3.5))
    # A huge curvature overflows the restricted value.
    var curved = _jet(
        _Interval(-1.0e300, 1.0e300),
        _Interval(-1.0e300, 1.0e300),
        _Interval(1.7e308, 1.7e308),
    )
    assert_false(_restricted(curved, zero, low=3.0, high=3.0))
    # The slope overflows while the value stays finite.
    var steep = _jet(
        _Interval(-MAX, MAX),
        _Interval(-1.0e300, 1.0e300),
        _Interval(1.5e308, 1.5e308),
    )
    var sloped = _jet(_Interval(0.0, 0.0), _Interval(1.0e308, 1.0e308))
    assert_false(_restricted(steep, sloped))
    # The restriction misses the whole-cell value, then the whole-cell slope.
    var away = _jet(_Interval(10.0, 11.0), _Interval(-1.0e300, 1.0e300))
    assert_false(_restricted(away, zero))
    var flat = _jet(_Interval(-1.0e300, 1.0e300), _Interval(10.0, 11.0))
    assert_false(_restricted(flat, zero))


# --- sample dispatch ----------------------------------------------------------


def test_dispatch_cut_finds_each_candidate_and_refuses_overflow() raises:
    assert_true(Bool(_sample_dispatch_cut(0.1, 10.0, 0.2)))
    assert_true(Bool(_sample_dispatch_cut(0.1, 10.0, 0.1)))
    assert_true(Bool(_sample_dispatch_cut(0.2, 10.0, 0.5)))
    assert_false(
        Bool(_sample_dispatch_cut(1.0e308, 8.0e307, 7.976931348623157e307))
    )


def _sampled(
    samples: List[Float64],
    start: Float64 = 0.0,
    length: Float64 = 1.0,
    geometries: Int = 1,
) raises -> Road:
    var road = Road(
        RoadId(1), "sampled", 10.0, NO_JUNCTION, RoadId(0), RoadId(0), True
    )
    _ = road.add_section(SectionId(0), 0.0)
    for id in [-1, 0]:
        var lane = road.sections[0].add_lane(LaneId(id))
        road.sections[0].lanes[lane].type = LANE_DRIVING
        if id != 0:
            road.sections[0].lanes[lane].info.widths.append(
                RoadInfoLaneWidth(0.0, CubicPolynomial(3.5, 0, 0, 0, 0))
            )
    var geometry = RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, 10.0)
    geometry.kind = POLY3
    geometry.length = length
    for s in samples:
        geometry.samples.append(_Sample(s, 0, s, 1, 0))
    for i in range(geometries):
        road.info.geometries.append(
            RoadInfoGeometry(start + Float64(i) * 5.0, geometry.copy())
        )
    road.info.lane_offsets.append(
        RoadInfoLaneOffset(0.0, CubicPolynomial(0, 0, 0, 0, 0))
    )
    road.info.elevations.append(
        RoadInfoElevation(0.0, CubicPolynomial(0, 0, 0, 0, 0))
    )
    return road^


def _cuts(road: Road, low: Float64, high: Float64) -> Bool:
    var nodes = 0
    var terms = 0
    return Bool(
        _try_sample_dispatch_cuts(road, low, high, nodes, terms, 1000, 100000)
    )


def test_dispatch_cuts_refuse_each_unsupported_input() raises:
    var samples: List[Float64] = [0.0, 0.25, 0.5, 0.75, 1.0]
    var road = _sampled(samples)
    var bad = nan[DType.float64]()
    assert_true(_cuts(road, 0.1, 0.3))
    assert_false(_cuts(road, bad, 0.3))
    assert_false(_cuts(road, 0.1, bad))
    assert_false(_cuts(road, 0.3, 0.1))
    assert_false(_cuts(_sampled(samples, start=2.0), 1.0, 2.5))
    assert_false(_cuts(_sampled(samples, geometries=2), 0.1, 5.3))
    var two: List[Float64] = [0.0, 1.0]
    assert_false(_cuts(_sampled(two), 0.1, 0.3))
    assert_false(
        _cuts(_sampled(samples, start=-inf[DType.float64]()), 0.1, 0.3)
    )
    assert_false(_cuts(_sampled(samples, start=-1.0), 0.1, 0.3))
    assert_false(_cuts(_sampled(samples, length=bad), 0.1, 0.3))
    assert_false(_cuts(_sampled(samples, length=0.0), 0.1, 0.3))
    # Three thresholds lie between low and high.
    assert_false(_cuts(road, 0.1, 0.9))


def test_dispatch_cuts_refuse_samples_closer_than_one_station_step() raises:
    # One step past the start skips the next sample entirely.
    var start = Float64(1.0e6)
    var samples: List[Float64] = [0.0, 5.0e-11, 1.0e-10, 1.0]
    var road = _sampled(samples, start=start)
    assert_false(_cuts(road, start + 1.0e-12, start + 2.4e-10))


# --- minimizer support --------------------------------------------------------


def _support(
    domain: _Jet,
    center: _Jet = _jet(_Interval(0.0, 0.0)),
    center_s: Float64 = 5.0,
    best: Float64 = 5.0,
    low: Float64 = 0.0,
    high: Float64 = 10.0,
) -> _Interval:
    return _minimizer_support(domain, center, center_s, best, low, high)


def test_minimizer_support_keeps_the_cell_for_invalid_inputs() raises:
    var domain = _jet(_Interval(0.0, 1.0))
    var bad = nan[DType.float64]()
    assert_false(_support(domain, low=bad).is_finite())
    assert_equal(_support(domain, best=bad).low, 0.0)
    assert_equal(_support(domain, center_s=bad).low, 0.0)
    assert_equal(_support(domain, center_s=-1.0).low, 0.0)
    assert_equal(_support(domain, center_s=11.0).low, 0.0)


def test_minimizer_support_overflowing_slopes_and_radii() raises:
    # The Taylor slope overflows; the domain slope remains.
    var curved = _jet(
        _Interval(0.0, 1.0), _Interval(1.0, 2.0), _Interval(1.0e308, 1.0e308)
    )
    _ = _support(curved)
    # No domain slope; the Taylor slope is used alone.
    var bare = _jet(_Interval(0.0, 1.0), _Interval.whole())
    _ = _support(bare)
    # A huge error over a tiny slope gives an infinite radius either way.
    var rising = _jet(
        _Interval(0.0, 1.0),
        _Interval(1.0e-300, 1.0),
        _Interval.whole(),
        1.0e308,
    )
    assert_equal(_support(rising).high, 10.0)
    var falling = _jet(
        _Interval(0.0, 1.0),
        _Interval(-1.0, -1.0e-300),
        _Interval.whole(),
        1.0e308,
    )
    assert_equal(_support(falling).low, 0.0)
    # The slope at best overflows.
    var steep = _jet(
        _Interval(0.0, 1.0), _Interval.whole(), _Interval(1.0e308, 1.0e308)
    )
    var sloped = _jet(_Interval(0.0, 0.0), _Interval(1.0e308, 1.0e308))
    _ = _support(steep, sloped, center_s=4.0, best=5.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
