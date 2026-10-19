# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.castle.water_balance`.

The references are the weir equation evaluated by hand, a climate that
evaporates one millimeter a day so the drawdown is a count of days, a
constant stream over a weir, and the conservation of volume over a year.
"""

from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from extensions.castle.plan import wijnendale
from extensions.castle.water_balance import (
    Climate,
    Weir,
    YearResult,
    flanders_climate,
    required_inflow,
    simulate_year,
)
from std.math import nan, pow, sqrt
from units.si import (
    Length64,
    METER,
    METER_PER_SECOND,
    MILLIMETER,
    Velocity64,
    VolumeFlowRate64,
)


def _mm(v: Float64) -> Length64:
    return Length64(v, MILLIMETER)


def _flow(v: Float64) -> VolumeFlowRate64:
    return VolumeFlowRate64(v)


def _weir() -> Weir:
    return Weir(Length64(1.5, METER), 0.62)


def _daily_millimeter() -> Climate:
    """No rain, no stream and exactly one millimeter of evaporation a day."""
    var rain = List[Length64]()
    var evaporation = List[Length64]()
    var inflow = List[VolumeFlowRate64]()
    var days: List[Int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    for month in range(12):
        rain.append(_mm(0.0))
        evaporation.append(_mm(Float64(days[month])))
        inflow.append(_flow(0.0))
    return Climate(rain^, evaporation^, inflow^)


def _steady_stream(flow: Float64) -> Climate:
    var rain = List[Length64]()
    var evaporation = List[Length64]()
    var inflow = List[VolumeFlowRate64]()
    for _ in range(12):
        rain.append(_mm(0.0))
        evaporation.append(_mm(0.0))
        inflow.append(_flow(flow))
    return Climate(rain^, evaporation^, inflow^)


def test_an_empty_year_has_no_drawdown() raises:
    var empty = YearResult()
    assert_almost_equal(empty.lowest().value, 0.0)
    assert_equal(empty.days_below(Length64(0.0, METER)), 0)
    assert_equal(len(empty.head), 0)


def test_weir_discharge_follows_the_equation() raises:
    var weir = _weir()
    var expected = (
        0.62 * (2.0 / 3.0) * sqrt(2.0 * 9.80665) * 1.5 * pow(0.1, 1.5)
    )
    assert_almost_equal(weir.discharge(Length64(0.1, METER)).value, expected)
    assert_almost_equal(expected, 0.0868, atol=5e-5)


def test_weir_head_inverts_the_discharge() raises:
    var weir = _weir()
    var head = weir.head(weir.discharge(Length64(0.23, METER)))
    assert_almost_equal(head.value, 0.23, atol=1e-12)
    assert_almost_equal(weir.head(_flow(0.0)).value, 0.0)


def test_weir_refuses_bad_input() raises:
    var weir = _weir()
    with assert_raises(contains="A weir flow must be zero or more"):
        _ = weir.head(_flow(-1.0))
    with assert_raises(contains="A weir head must be zero or more"):
        _ = weir.discharge(Length64(-0.1, METER))
    var bad = Weir(Length64(0.0, METER), 0.62)
    with assert_raises(contains="A weir crest must be positive"):
        bad.check()
    bad = Weir(Length64(1.0, METER), nan[DType.float64]())
    with assert_raises(contains="A weir coefficient must be positive"):
        bad.check()
    with assert_raises(contains="A weir crest must be positive"):
        _ = Weir(Length64(0.0, METER), 0.6).head(_flow(0.1))


def test_the_typical_climate_has_the_stated_totals() raises:
    var c = flanders_climate()
    c.check()
    var rain = 0.0
    var evaporation = 0.0
    for month in range(12):
        rain += c.precipitation[month].to(MILLIMETER)
        evaporation += c.evaporation[month].to(MILLIMETER)
    # The Uccle normals of 1991-2020 sum to 837.2 mm. The evaporation sums
    # to 608 mm.
    assert_almost_equal(rain, 837.2, atol=1e-9)
    assert_almost_equal(evaporation, 608.0, atol=1e-9)
    assert_true(c.inflow[0].value > c.inflow[7].value)


def test_climate_refuses_what_is_not_twelve_months() raises:
    var c = flanders_climate()
    _ = c.precipitation.pop()
    with assert_raises(contains="12 monthly rain depths"):
        c.check()
    c = flanders_climate()
    _ = c.evaporation.pop()
    with assert_raises(contains="12 monthly evaporation depths"):
        c.check()
    c = flanders_climate()
    _ = c.inflow.pop()
    with assert_raises(contains="12 monthly stream flows"):
        c.check()
    c = flanders_climate()
    c.precipitation[3] = _mm(-1.0)
    with assert_raises(contains="A rain depth must be zero or more"):
        c.check()
    c = flanders_climate()
    c.evaporation[3] = _mm(nan[DType.float64]())
    with assert_raises(contains="An evaporation depth must be zero or more"):
        c.check()
    c = flanders_climate()
    c.inflow[3] = _flow(-1.0)
    with assert_raises(contains="A stream flow must be zero or more"):
        c.check()


def test_evaporation_alone_lowers_the_level_a_millimeter_a_day() raises:
    var plan = wijnendale()
    var result = simulate_year(
        plan.moat,
        _daily_millimeter(),
        _weir(),
        Velocity64(0.0, METER_PER_SECOND),
        1.0,
        1.0,
    )
    assert_equal(len(result.drawdown), 365)
    assert_almost_equal(result.drawdown[0].value, 0.001, atol=1e-12)
    assert_almost_equal(result.drawdown[99].value, 0.100, atol=1e-12)
    assert_almost_equal(result.lowest().value, 0.365, atol=1e-12)
    # A drawdown of 100.5 mm is passed on day 101, so 265 days pass it.
    assert_equal(result.days_below(Length64(0.1005, METER)), 365 - 100)
    assert_almost_equal(result.spilled.value, 0.0)
    assert_almost_equal(
        result.evaporated.value, plan.moat.water_area().value * 0.365, atol=1e-6
    )


def test_a_steady_stream_goes_over_the_weir_at_its_own_head() raises:
    var plan = wijnendale()
    var weir = _weir()
    var result = simulate_year(
        plan.moat,
        _steady_stream(0.05),
        weir,
        Velocity64(0.0, METER_PER_SECOND),
        1.0,
        1.0,
    )
    assert_almost_equal(result.lowest().value, 0.0)
    assert_almost_equal(result.head[10].value, weir.head(_flow(0.05)).value)
    assert_almost_equal(result.spilled.value, 0.05 * 86400.0 * 365.0, atol=1e-3)


def test_volume_is_conserved_over_a_year() raises:
    var plan = wijnendale()
    var c = flanders_climate()
    var leak = Velocity64(2.0e-8, METER_PER_SECOND)
    var result = simulate_year(plan.moat, c, _weir(), leak, 0.5, 0.0)
    var area = plan.moat.water_area().value
    var rain = 0.0
    for month in range(12):
        rain += c.precipitation[month].value * 0.5
    var gained = rain * area
    var lost = (
        result.evaporated.value + result.leaked.value + result.spilled.value
    )
    var stored = result.drawdown[364].value * area
    assert_almost_equal(gained - lost, -stored, atol=1e-6)


def test_a_normal_year_holds_the_level_and_a_dry_year_does_not() raises:
    var plan = wijnendale()
    var c = flanders_climate()
    var leak = Velocity64(2.0e-8, METER_PER_SECOND)
    var normal = simulate_year(plan.moat, c, _weir(), leak, 1.0, 1.0)
    assert_almost_equal(normal.lowest().value, 0.0)
    assert_true(normal.spilled.value > 0.0)
    var dry = simulate_year(plan.moat, c, _weir(), leak, 0.6, 0.0)
    assert_true(dry.lowest().value > 0.5)
    assert_true(dry.days_below(Length64(0.1, METER)) > 200)
    assert_true(dry.lowest().value < plan.moat.depth.value)


def test_required_inflow_balances_the_losses() raises:
    var plan = wijnendale()
    var c = _daily_millimeter()
    c.precipitation[5] = _mm(10.0)
    var leak = Velocity64(1.0e-8, METER_PER_SECOND)
    var area = plan.moat.water_area().value
    # June has 30 days. It loses 30 mm and gains 10 mm, so 20 mm net, and the
    # lining leaks 1e-8 m/s.
    var expected = (0.020 / (30.0 * 86400.0) + 1.0e-8) * area
    assert_almost_equal(
        required_inflow(plan.moat, c, leak, 5, 1.0).value, expected, atol=1e-12
    )
    # With no rain scale the rain does not count.
    var no_rain = (0.030 / (30.0 * 86400.0) + 1.0e-8) * area
    assert_almost_equal(
        required_inflow(plan.moat, c, leak, 5, 0.0).value, no_rain, atol=1e-12
    )


def test_required_inflow_is_zero_when_rain_is_enough() raises:
    var plan = wijnendale()
    var c = flanders_climate()
    var none = Velocity64(0.0, METER_PER_SECOND)
    assert_almost_equal(required_inflow(plan.moat, c, none, 0, 1.0).value, 0.0)
    assert_true(required_inflow(plan.moat, c, none, 5, 1.0).value > 0.0)


def test_simulation_refuses_bad_input() raises:
    var plan = wijnendale()
    var c = flanders_climate()
    var leak = Velocity64(0.0, METER_PER_SECOND)
    with assert_raises(contains="A leakage must be zero or more"):
        _ = simulate_year(plan.moat, c, _weir(), Velocity64(-1.0), 1.0, 1.0)
    with assert_raises(contains="A rain scale must be zero or more"):
        _ = simulate_year(plan.moat, c, _weir(), leak, -1.0, 1.0)
    with assert_raises(contains="An inflow scale must be zero or more"):
        _ = simulate_year(plan.moat, c, _weir(), leak, 1.0, -1.0)
    with assert_raises(contains="A weir crest must be positive"):
        _ = simulate_year(
            plan.moat, c, Weir(Length64(0.0, METER), 0.6), leak, 1.0, 1.0
        )
    var bad = flanders_climate()
    _ = bad.inflow.pop()
    with assert_raises(contains="12 monthly stream flows"):
        _ = simulate_year(plan.moat, bad, _weir(), leak, 1.0, 1.0)
    plan.moat.depth = Length64(0.0, METER)
    with assert_raises(contains="A moat depth must be positive"):
        _ = simulate_year(plan.moat, c, _weir(), leak, 1.0, 1.0)


def test_required_inflow_refuses_bad_input() raises:
    var plan = wijnendale()
    var c = flanders_climate()
    var leak = Velocity64(0.0, METER_PER_SECOND)
    with assert_raises(contains="A month must be 0 to 11"):
        _ = required_inflow(plan.moat, c, leak, -1, 1.0)
    with assert_raises(contains="A month must be 0 to 11"):
        _ = required_inflow(plan.moat, c, leak, 12, 1.0)
    with assert_raises(contains="A leakage must be zero or more"):
        _ = required_inflow(plan.moat, c, Velocity64(-1.0), 0, 1.0)
    with assert_raises(contains="A rain scale must be zero or more"):
        _ = required_inflow(plan.moat, c, leak, 0, -1.0)
    var bad = flanders_climate()
    _ = bad.evaporation.pop()
    with assert_raises(contains="12 monthly evaporation depths"):
        _ = required_inflow(plan.moat, bad, leak, 0, 1.0)
    plan.moat.depth = Length64(0.0, METER)
    with assert_raises(contains="A moat depth must be positive"):
        _ = required_inflow(plan.moat, c, leak, 0, 1.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
