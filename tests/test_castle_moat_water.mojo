# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the water balance of the moat.

The reference numbers of the weir are worked by hand from the
Kindsvater-Carter formula, and those of the balance from a separate
integration of the same equations.
"""

from extensions.castle.moat_water import (
    DayWeather,
    MoatBalance,
    Weir,
    wijnendale_moat,
)
from extensions.castle.wijnendale import wijnendale_plan
from std.math import nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_raises,
    assert_true,
)
from units.si import (
    Area64,
    Duration64,
    Length64,
    METER,
    VolumeFlowRate64,
)

comptime _DAY = 86400.0


def _weir() -> Weir:
    return Weir(
        Length64(34.0, METER), Length64(1.2, METER), Length64(1.4, METER)
    )


def _dry() -> DayWeather:
    return DayWeather(Length64(0.0), Length64(0.0))


def test_the_weir_passes_the_kindsvater_carter_discharge() raises:
    var weir = _weir()
    # Q = (2/3) (0.602 + 0.075 h / p) sqrt(2 g) L (h + 0.0009144)^1.5.
    assert_almost_equal(
        weir.discharge(Length64(34.1, METER)).value, 0.0689825, atol=1.0e-6
    )
    assert_almost_equal(
        weir.discharge(Length64(34.5, METER)).value, 0.7897930, atol=1.0e-6
    )
    # At or under the crest nothing flows.
    assert_almost_equal(
        weir.discharge(Length64(34.0, METER)).value, 0.0, atol=0.0
    )
    assert_almost_equal(
        weir.discharge(Length64(33.0, METER)).value, 0.0, atol=0.0
    )
    # More head passes more flow.
    assert_true(
        weir.discharge(Length64(34.3, METER)).value
        > weir.discharge(Length64(34.2, METER)).value
    )


def test_a_weir_is_checked() raises:
    var narrow = Weir(
        Length64(34.0, METER), Length64(0.0, METER), Length64(1.4, METER)
    )
    with assert_raises(contains="positive finite width"):
        narrow.check()
    var flat = Weir(
        Length64(34.0, METER), Length64(1.2, METER), Length64(0.0, METER)
    )
    with assert_raises(contains="positive finite width"):
        _ = flat.discharge(Length64(34.1, METER))
    var lost = Weir(
        Length64(Float64(1.0) / Float64(0.0), METER),
        Length64(1.2, METER),
        Length64(1.4, METER),
    )
    with assert_raises(contains="finite crest"):
        lost.check()
    with assert_raises(contains="finite"):
        _ = _weir().discharge(Length64(Float64(0.0) / Float64(0.0)))
    # A head of 2.4 crest heights is the limit of the formula.
    with assert_raises(contains="2.4"):
        _ = _weir().discharge(Length64(34.0 + 3.4, METER))


def test_the_moat_of_the_plan_is_held_at_the_surveyed_level() raises:
    var plan = wijnendale_plan()
    var moat = wijnendale_moat(plan)
    assert_almost_equal(moat.area.value, 7360.28, atol=1.0)
    # The base inflow of 25 L/s passes the weir at a head of 5.05 cm, so
    # the crest is that much under the level.
    assert_almost_equal(moat.weir.crest.value, 34.2594682, atol=1.0e-6)
    var level = Length64(34.31, METER)
    assert_almost_equal(moat.weir.discharge(level).value, 0.025, atol=1.0e-9)
    # In dry weather with no evaporation the level does not change.
    var held = moat.step(level, _dry(), Duration64(_DAY))
    assert_almost_equal(held.value, 34.31, atol=1.0e-8)
    # With 1.2 mm of evaporation it falls by 0.14 mm in a day.
    var dried = moat.step(
        level, DayWeather(Length64(0.0), Length64(0.0012)), Duration64(_DAY)
    )
    assert_almost_equal(dried.value, 34.3098601, atol=1.0e-6)


def test_the_moat_rises_in_rain_and_settles() raises:
    var moat = wijnendale_moat(wijnendale_plan())
    var level = Length64(34.31, METER)
    var storm = DayWeather(Length64(0.030), Length64(0.0006))
    # A day of 30 mm of rain raises the moat by 3.4 cm, which is the new
    # steady level, for the weir is quick.
    var after_one = moat.step(level, storm, Duration64(_DAY))
    assert_almost_equal(after_one.value, 34.3438655, atol=1.0e-5)
    var after_three = moat.step(level, storm, Duration64(3.0 * _DAY))
    assert_almost_equal(after_three.value, 34.3438661, atol=1.0e-6)
    # The rise is what the weir must pass to match the extra inflow.
    var extra = (
        moat.weir.discharge(after_three).value
        - moat.weir.discharge(level).value
    )
    assert_almost_equal(
        extra,
        0.15 * 0.030 * 0.5e6 / _DAY
        + 0.030 * moat.area.value / _DAY
        - 0.0006 * moat.area.value / _DAY,
        atol=1.0e-6,
    )


def test_the_moat_holds_a_volume_that_takes_five_days_to_pass() raises:
    var moat = wijnendale_moat(wijnendale_plan())
    var level = Length64(34.31, METER)
    var bed = Length64(32.81, METER)
    assert_almost_equal(moat.storage(level, bed), 11040.41, atol=1.0)
    var hours = moat.residence_time(level, bed).value / 3600.0
    assert_almost_equal(hours, 122.67, atol=0.05)
    var low = Length64(34.0, METER)
    with assert_raises(contains="no flow"):
        _ = moat.residence_time(low, bed)


def test_seepage_lowers_the_level() raises:
    var moat = wijnendale_moat(wijnendale_plan())
    var level = Length64(34.31, METER)
    var sealed = moat.step(level, _dry(), Duration64(10.0 * _DAY))
    moat.seepage_conductance = 0.01
    var leaking = moat.step(level, _dry(), Duration64(10.0 * _DAY))
    assert_true(leaking.value < sealed.value - 0.010)
    # Water under the groundwater level does not seep.
    moat.groundwater = Length64(40.0, METER)
    var held = moat.step(level, _dry(), Duration64(10.0 * _DAY))
    assert_almost_equal(held.value, sealed.value, atol=1.0e-9)


def test_a_zero_duration_changes_nothing() raises:
    var moat = wijnendale_moat(wijnendale_plan())
    var level = Length64(34.2, METER)
    var same = moat.step(level, _dry(), Duration64(0.0))
    assert_almost_equal(same.value, 34.2, atol=1.0e-12)
    with assert_raises(contains="duration"):
        _ = moat.step(level, _dry(), Duration64(-1.0))


def test_a_balance_is_checked() raises:
    var good = wijnendale_moat(wijnendale_plan())
    var flat = good.copy()
    flat.area = Area64(0.0)
    with assert_raises(contains="positive finite area"):
        flat.check()
    var dry = good.copy()
    dry.base_inflow = VolumeFlowRate64(-1.0)
    with assert_raises(contains="zero or more"):
        dry.check()
    var wet = good.copy()
    wet.runoff_coefficient = 1.5
    with assert_raises(contains="runoff coefficient"):
        wet.check()
    var broken = good.copy()
    broken.weir.width = Length64(0.0, METER)
    with assert_raises(contains="weir needs"):
        broken.check()


def test_numbers_that_are_not_numbers_are_refused() raises:
    var not_a_number = nan[DType.float64]()
    var wide = Weir(
        Length64(34.0, METER),
        Length64(not_a_number, METER),
        Length64(1.4, METER),
    )
    with assert_raises(contains="positive finite width"):
        wide.check()
    var tall = Weir(
        Length64(34.0, METER),
        Length64(1.2, METER),
        Length64(not_a_number, METER),
    )
    with assert_raises(contains="positive finite width"):
        tall.check()
    var good = wijnendale_moat(wijnendale_plan())
    var flat = good.copy()
    flat.area = Area64(not_a_number)
    with assert_raises(contains="positive finite area"):
        flat.check()
    var inflow = good.copy()
    inflow.base_inflow = VolumeFlowRate64(not_a_number)
    with assert_raises(contains="zero or more"):
        inflow.check()
    var catchment = good.copy()
    catchment.catchment = Area64(not_a_number)
    with assert_raises(contains="zero or more"):
        catchment.check()
    catchment.catchment = Area64(-1.0)
    with assert_raises(contains="zero or more"):
        catchment.check()
    var seepage = good.copy()
    seepage.seepage_conductance = not_a_number
    with assert_raises(contains="zero or more"):
        seepage.check()
    seepage.seepage_conductance = -1.0
    with assert_raises(contains="zero or more"):
        seepage.check()
    var ground = good.copy()
    ground.groundwater = Length64(not_a_number)
    with assert_raises(contains="zero or more"):
        ground.check()
    var runoff = good.copy()
    runoff.runoff_coefficient = not_a_number
    with assert_raises(contains="runoff coefficient"):
        runoff.check()
    runoff.runoff_coefficient = -0.1
    with assert_raises(contains="runoff coefficient"):
        runoff.check()
    with assert_raises(contains="duration"):
        _ = good.step(Length64(34.31, METER), _dry(), Duration64(not_a_number))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
