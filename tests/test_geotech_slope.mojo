# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for Bishop's slip-circle analysis in `extensions.geotech.slope`.

A cohesionless slope can be no safer, on any surface, than the infinite
slope's tan(phi) / tan(beta), and a large shallow circle comes close to
it. A purely cohesive layer has the closed form of a circle through a
level ground with a surcharge, which bounds the search from above.
"""

from std.math import atan, inf, isinf, nan, pi, sqrt, tan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from extensions.geotech.slope import (
    SectionPoint,
    SlipCircle,
    SlipSearch,
    SlopeRegion,
    SlopeSection,
    Surcharge,
    bishop_factor,
    critical_circle,
)
from extensions.geotech.units import UnitWeight64
from extensions.geotech.wall import Soil
from units.si import Angle64, DEGREE64, Length64, Pressure64

comptime G = 18000.0
comptime GW = 9810.0


def _m(v: Float64) -> Length64:
    return Length64(v)


def _pt(x: Float64, z: Float64) -> SectionPoint:
    return SectionPoint(_m(x), _m(z))


def _sand() -> Soil:
    return Soil(UnitWeight64(G), Angle64(30, DEGREE64), Pressure64(0))


def _slope() raises -> SlopeSection:
    # Ground falling toward -x at 2H:1V from z = 5 to z = 0.
    var surface: List[SectionPoint] = [
        _pt(-30, 0),
        _pt(0, 0),
        _pt(10, 5),
        _pt(40, 5),
    ]
    return SlopeSection(surface^, _sand(), UnitWeight64(GW))


def _search() -> SlipSearch:
    return SlipSearch(_m(-4), _m(14), _m(6), _m(24), 9, 9, _m(4), _m(30), 12)


def test_infinite_slope_bound() raises:
    var best = critical_circle(_slope(), _search())
    var infinite = tan(pi / 6) / 0.5
    assert_true(best.factor >= infinite - 1e-3)
    assert_true(best.factor < infinite * 1.1)
    assert_true(best.start.value < best.end.value)
    assert_true(best.weight > 0)


def test_water_and_surcharge_lower_the_factor() raises:
    var circle = SlipCircle(_m(2), _m(14), _m(14))
    var dry = bishop_factor(_slope(), circle)
    var wet_slope = _slope()
    wet_slope.set_water_table([_pt(-30, 3), _pt(40, 4)])
    var wet = bishop_factor(wet_slope, circle)
    assert_true(wet.factor < dry.factor)
    var loaded = _slope()
    loaded.surcharges.append(Surcharge(_m(10), _m(20), Pressure64(50000)))
    assert_true(bishop_factor(loaded, circle).factor < dry.factor)
    # Ponded water in front adds weight where it resists.
    var ponded = _slope()
    ponded.set_water_table([_pt(-30, 2), _pt(-1, 2), _pt(40, 2)])
    var pond = bishop_factor(ponded, circle)
    assert_true(pond.factor > 0)


def test_cohesive_region() raises:
    var circle = SlipCircle(_m(2), _m(14), _m(14))
    var plain = bishop_factor(_slope(), circle)
    var strong = _slope()
    strong.regions.append(
        SlopeRegion(
            [_pt(-40, -20), _pt(50, -20), _pt(50, 20), _pt(-40, 20)],
            Soil(UnitWeight64(G), Angle64(30, DEGREE64), Pressure64(20000)),
        )
    )
    assert_true(bishop_factor(strong, circle).factor > plain.factor)
    var r = strong.regions[0].copy()
    assert_true(r.contains(0, 0))
    assert_false(r.contains(100, 0))
    assert_almost_equal(strong.soil_at(0, 0).cohesion.value, 20000, atol=1e-9)
    assert_almost_equal(_slope().soil_at(0, 0).cohesion.value, 0, atol=1e-9)
    assert_almost_equal(_slope().top_at(5), 2.5, atol=1e-12)
    assert_true(isinf(_slope().water_at(0)))


def test_partial_region_and_surcharge() raises:
    var circle = SlipCircle(_m(2), _m(14), _m(14))
    var plain = bishop_factor(_slope(), circle)
    # A strong block under the crest holds only part of the slip mass.
    var block = _slope()
    block.regions.append(
        SlopeRegion(
            [_pt(4, -2), _pt(12, -2), _pt(12, 5), _pt(4, 5)],
            Soil(UnitWeight64(G), Angle64(30, DEGREE64), Pressure64(20000)),
        )
    )
    var held = bishop_factor(block, circle)
    assert_true(held.factor > plain.factor)
    assert_almost_equal(block.soil_at(-5, 0).cohesion.value, 0, atol=0)
    # A surcharge that ends inside the circle loads only the slices on it.
    var narrow = _slope()
    narrow.surcharges.append(Surcharge(_m(5), _m(8), Pressure64(50000)))
    var wide = _slope()
    wide.surcharges.append(Surcharge(_m(5), _m(30), Pressure64(50000)))
    var n = bishop_factor(narrow, circle)
    var w = bishop_factor(wide, circle)
    assert_true(n.weight > plain.weight)
    assert_true(w.weight > n.weight)


def test_no_mass_and_filters() raises:
    # A circle above the ground moves nothing.
    var high = bishop_factor(_slope(), SlipCircle(_m(0), _m(100), _m(5)))
    assert_true(isinf(high.factor))
    var none = critical_circle(_slope(), _search(), [_pt(0, -500)])
    assert_true(isinf(none.factor))
    var held = critical_circle(_slope(), _search(), [_pt(5, 1)])
    assert_true(held.factor < 10)
    var one = SlipSearch(_m(2), _m(2), _m(14), _m(14), 1, 1, _m(14), _m(14), 1)
    assert_almost_equal(
        critical_circle(_slope(), one).factor,
        bishop_factor(_slope(), SlipCircle(_m(2), _m(14), _m(14))).factor,
        atol=1e-12,
    )


def test_refusals() raises:
    with assert_raises(contains="three corners"):
        _ = SlopeRegion([_pt(0, 0), _pt(1, 0)], _sand())
    with assert_raises(contains="finite"):
        _ = SlopeRegion(
            [
                _pt(0, 0),
                _pt(1, 0),
                SectionPoint(_m(1), Length64(nan[DType.float64]())),
            ],
            _sand(),
        )
    with assert_raises(contains="finite"):
        _ = SlopeRegion(
            [
                _pt(0, 0),
                SectionPoint(Length64(nan[DType.float64]()), _m(0)),
                _pt(0, 1),
            ],
            _sand(),
        )
    with assert_raises(contains="unit weight"):
        _ = SlopeRegion(
            [_pt(0, 0), _pt(1, 0), _pt(1, 1)],
            Soil(UnitWeight64(-1), Angle64(0.5), Pressure64(0)),
        )
    with assert_raises(contains="at least two"):
        _ = SlopeSection([_pt(0, 0)], _sand(), UnitWeight64(GW))
    with assert_raises(contains="finite"):
        _ = SlopeSection(
            [_pt(0, 0), SectionPoint(_m(inf[DType.float64]()), _m(0))],
            _sand(),
            UnitWeight64(GW),
        )
    with assert_raises(contains="turn back"):
        _ = SlopeSection([_pt(0, 0), _pt(-1, 0)], _sand(), UnitWeight64(GW))
    var s = _slope()
    with assert_raises(contains="at least two"):
        s.set_water_table([_pt(0, 0)])
    with assert_raises(contains="must be finite"):
        s.set_water_table(
            [_pt(0, 0), SectionPoint(_m(1), Length64(nan[DType.float64]()))]
        )
    with assert_raises(contains="positive radius"):
        _ = bishop_factor(s, SlipCircle(_m(0), _m(0), _m(0)))
    var bad = Length64(nan[DType.float64]())
    with assert_raises(contains="positive radius"):
        _ = bishop_factor(s, SlipCircle(bad, _m(0), _m(1)))
    with assert_raises(contains="positive radius"):
        _ = bishop_factor(s, SlipCircle(_m(0), bad, _m(1)))
    with assert_raises(contains="positive radius"):
        _ = bishop_factor(
            s, SlipCircle(_m(0), _m(0), Length64(inf[DType.float64]()))
        )
    with assert_raises(contains="at least one"):
        _ = critical_circle(
            s, SlipSearch(_m(0), _m(1), _m(0), _m(1), 0, 1, _m(1), _m(2), 1)
        )
    with assert_raises(contains="at least one"):
        _ = critical_circle(
            s, SlipSearch(_m(0), _m(1), _m(0), _m(1), 1, 0, _m(1), _m(2), 1)
        )
    with assert_raises(contains="at least one"):
        _ = critical_circle(
            s, SlipSearch(_m(0), _m(1), _m(0), _m(1), 1, 1, _m(1), _m(2), 0)
        )
    with assert_raises(contains="in order"):
        _ = critical_circle(
            s, SlipSearch(_m(0), _m(1), _m(0), _m(1), 1, 1, _m(3), _m(2), 1)
        )
    with assert_raises(contains="in order"):
        _ = critical_circle(
            s, SlipSearch(_m(0), _m(1), _m(0), _m(1), 1, 1, _m(0), _m(2), 1)
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
