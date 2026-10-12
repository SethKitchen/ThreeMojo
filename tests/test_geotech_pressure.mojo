# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the earth, water and surcharge pressures of
`extensions.geotech`.

References: Das, "Principles of Foundation Engineering", 7th ed., tables
7.1 (Rankine with backslope) and 7.4 (Coulomb); AASHTO LRFD 2010 tables
3.11.6.4-1 and 3.11.6.4-2. Closed forms are worked out in each test.
"""

from std.math import inf, nan, pi, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from extensions.geotech.earth_pressure import (
    at_rest,
    coulomb_active,
    mononobe_okabe_active,
    rankine_active,
    rankine_passive,
    trial_wedge,
    trial_wedge_resultant,
)
from extensions.geotech.kinds import (
    ACROSS,
    ALONG,
    BEARING,
    ContactMode,
    DC,
    EQ,
    FULL_CONTACT,
    FailureMode,
    GLOBAL_SLIP,
    HEEL_TRIANGLE,
    LS_V,
    LoadKind,
    OVERTURNING,
    PipeRun,
    SERVICE_PRESSURE,
    SLIDING,
    TOE_TRIANGLE,
)
from extensions.geotech.pipes import BuriedPipe, circle_band_area, pipe_weights
from extensions.geotech.profile import GradePoint, GradeProfile
from extensions.geotech.surcharge import abutment_height, parallel_wall_height
from extensions.geotech.units import (
    KCF,
    KIP,
    KLF,
    KSF,
    PCF,
    PSF,
    UnitWeight64,
    WATER_62_4_PCF,
    WATER_SI,
)
from extensions.geotech.water import effective_unit_weight, net_hydrostatic
from units.si import Angle64, DEGREE64, FOOT64, Length64

comptime GAMMA = 18000.0
comptime GW = 9810.0


def _deg(v: Float64) -> Angle64:
    return Angle64(v, DEGREE64)


def _m(v: Float64) -> Length64:
    return Length64(v)


def _level(height: Float64) raises -> GradeProfile:
    return GradeProfile(
        [GradePoint(_m(0), _m(height)), GradePoint(_m(50), _m(height))]
    )


def test_units() raises:
    assert_almost_equal(UnitWeight64(1, PCF).to(KCF), 0.001, atol=1e-15)
    assert_almost_equal(Length64(1.0, FOOT64).value, 0.3048, atol=1e-15)
    assert_almost_equal(
        UnitWeight64(62.4, PCF).value, WATER_62_4_PCF.value, atol=1e-9
    )
    assert_almost_equal(WATER_SI.value, 9806.65, atol=1e-12)
    assert_almost_equal((1000.0 * PSF.scale) / KSF.scale, 1.0, atol=1e-12)
    assert_almost_equal(KLF.scale * 0.3048, KIP.scale, atol=1e-9)


def test_kinds() raises:
    assert_true(DC.is_valid() and EQ.is_valid())
    assert_false(LoadKind(9).is_valid())
    assert_false(LoadKind(-1).is_valid())
    assert_equal(LS_V.name(), "LS_V")
    assert_equal(LoadKind(12).name(), "?")
    assert_true(ACROSS.is_valid() and ALONG.is_valid())
    assert_false(PipeRun(2).is_valid())
    assert_true(FULL_CONTACT.is_valid() and HEEL_TRIANGLE.is_valid())
    assert_false(ContactMode(3).is_valid())
    assert_false(ContactMode(-1).is_valid())
    assert_true(TOE_TRIANGLE != HEEL_TRIANGLE)
    assert_true(SERVICE_PRESSURE.is_valid())
    assert_false(FailureMode(9).is_valid())
    assert_false(FailureMode(-2).is_valid())
    assert_equal(GLOBAL_SLIP.name(), "global slip")
    assert_equal(FailureMode(40).name(), "?")
    assert_equal(BEARING.name(), "bearing")


def test_rankine_and_at_rest() raises:
    assert_almost_equal(rankine_active(_deg(30)), 1.0 / 3.0, atol=1e-12)
    assert_almost_equal(rankine_passive(_deg(30)), 3.0, atol=1e-12)
    assert_almost_equal(at_rest(_deg(30)), 0.5, atol=1e-12)
    # Das table 7.1: phi 30, alpha 10 degrees, Ka = 0.3495.
    assert_almost_equal(rankine_active(_deg(30), _deg(10)), 0.3495, atol=5e-5)
    # A backslope at phi is the limit: Ka = cos(phi).
    assert_almost_equal(
        rankine_active(_deg(30), _deg(30)), sqrt(3.0) / 2, atol=1e-6
    )
    with assert_raises(contains="steeper than the friction angle"):
        _ = rankine_active(_deg(30), _deg(31))
    with assert_raises(contains="friction angle"):
        _ = rankine_active(_deg(90))
    with assert_raises(contains="friction angle"):
        _ = rankine_passive(_deg(-1))
    with assert_raises(contains="friction angle"):
        _ = at_rest(Angle64(nan[DType.float64]()))
    with assert_raises(contains="backslope must be finite"):
        _ = rankine_active(_deg(30), Angle64(inf[DType.float64]()))


def test_coulomb() raises:
    # A smooth vertical wall under level ground is Rankine.
    assert_almost_equal(
        coulomb_active(_deg(30), _deg(0)), 1.0 / 3.0, atol=1e-12
    )
    # Das table 7.4: phi 30, delta 20, alpha 0, beta 90: Ka = 0.2973.
    assert_almost_equal(coulomb_active(_deg(30), _deg(20)), 0.2973, atol=5e-5)
    with assert_raises(contains="steeper than the friction angle"):
        _ = coulomb_active(_deg(30), _deg(0), _deg(35))
    with assert_raises(contains="must be finite"):
        _ = coulomb_active(_deg(30), Angle64(nan[DType.float64]()))
    with assert_raises(contains="must be finite"):
        _ = coulomb_active(_deg(30), _deg(0), Angle64(nan[DType.float64]()))
    with assert_raises(contains="must be finite"):
        _ = coulomb_active(
            _deg(30), _deg(0), _deg(0), Angle64(inf[DType.float64]())
        )


def test_mononobe_okabe() raises:
    # With no earthquake it is Coulomb's coefficient for a vertical wall.
    assert_almost_equal(
        mononobe_okabe_active(_deg(30), _deg(20), 0.0),
        coulomb_active(_deg(30), _deg(20)),
        atol=1e-12,
    )
    var k = mononobe_okabe_active(_deg(30), _deg(0), 0.2)
    assert_true(k > 1.0 / 3.0)
    # By hand for phi 30, delta 0, kh 0.2: psi = atan(0.2), KAE = 0.4733.
    assert_almost_equal(k, 0.4733, atol=2e-4)
    with assert_raises(contains="too strong"):
        _ = mononobe_okabe_active(_deg(30), _deg(0), 0.9)
    with assert_raises(contains="less than one"):
        _ = mononobe_okabe_active(_deg(30), _deg(0), 0.1, 1.0)
    with assert_raises(contains="must be finite"):
        _ = mononobe_okabe_active(_deg(30), _deg(0), nan[DType.float64]())
    var bad = Angle64(nan[DType.float64]())
    with assert_raises(contains="must be finite"):
        _ = mononobe_okabe_active(_deg(30), bad, 0.1)
    with assert_raises(contains="must be finite"):
        _ = mononobe_okabe_active(_deg(30), _deg(0), 0.1, 0.0, bad)
    with assert_raises(contains="must be finite"):
        _ = mononobe_okabe_active(_deg(30), _deg(0), 0.1, 0.0, _deg(0), bad)
    with assert_raises(contains="must be finite"):
        _ = mononobe_okabe_active(_deg(30), _deg(0), 0.1, nan[DType.float64]())


def test_profile() raises:
    var p = GradeProfile(
        [
            GradePoint(_m(0), _m(2)),
            GradePoint(_m(4), _m(4)),
            GradePoint(_m(10), _m(4)),
        ]
    )
    assert_almost_equal(p.height_at(_m(2)).value, 3.0, atol=1e-12)
    assert_almost_equal(p.height_at(_m(-1)).value, 2.0, atol=1e-12)
    assert_almost_equal(p.height_at(_m(99)).value, 4.0, atol=1e-12)
    assert_almost_equal(p.plane_height().value, 2.0, atol=1e-12)
    var am = p.area_and_moment(_m(4))
    # A trapezoid 2 to 4 over 4: area 12, first moment 2*4*2 + 0.5*2*4*(8/3).
    assert_almost_equal(am[0].value, 12.0, atol=1e-12)
    assert_almost_equal(am[1].value, 16.0 + 32.0 / 3.0, atol=1e-12)
    var none = p.area_and_moment(_m(0))
    assert_almost_equal(none[0].value, 0.0, atol=1e-15)
    # Past the point at 4 m: the trapezoid and a 2 m rectangle at 4.
    var wide = p.area_and_moment(_m(6))
    assert_almost_equal(wide[0].value, 20.0, atol=1e-12)
    assert_almost_equal(wide[1].value, 16.0 + 32.0 / 3.0 + 40.0, atol=1e-12)
    var up = p.raised(_m(1))
    assert_almost_equal(up.height_at(_m(4)).value, 5.0, atol=1e-12)
    var tail = p.beyond(_m(2))
    assert_almost_equal(tail.plane_height().value, 3.0, atol=1e-12)
    # A short tail is extended level by 500 ft.
    assert_almost_equal(
        tail.points[len(tail.points) - 1].distance.value, 8.0 + 152.4, atol=1e-9
    )
    var past = p.beyond(_m(20))
    assert_equal(len(past.points), 2)
    var long = GradeProfile(
        [GradePoint(_m(0), _m(1)), GradePoint(_m(40), _m(1))]
    )
    assert_equal(len(long.beyond(_m(1)).points), 2)
    with assert_raises(contains="at least two"):
        _ = GradeProfile([GradePoint(_m(0), _m(1))])
    with assert_raises(contains="finite"):
        _ = GradeProfile(
            [
                GradePoint(_m(0), _m(1)),
                GradePoint(_m(1), Length64(nan[DType.float64]())),
            ]
        )
    with assert_raises(contains="finite"):
        _ = GradeProfile(
            [
                GradePoint(_m(0), _m(1)),
                GradePoint(Length64(inf[DType.float64]()), _m(1)),
            ]
        )
    with assert_raises(contains="distance zero"):
        _ = GradeProfile([GradePoint(_m(1), _m(1)), GradePoint(_m(2), _m(1))])
    with assert_raises(contains="must increase"):
        _ = GradeProfile([GradePoint(_m(0), _m(1)), GradePoint(_m(0), _m(1))])
    with assert_raises(contains="level segment"):
        _ = GradeProfile([GradePoint(_m(0), _m(1)), GradePoint(_m(2), _m(2))])
    with assert_raises(contains="finite"):
        _ = p.raised(Length64(inf[DType.float64]()))
    with assert_raises(contains="zero or more"):
        _ = p.beyond(_m(-1))
    with assert_raises(contains="zero or more"):
        _ = p.beyond(Length64(nan[DType.float64]()))


def _pipe(run: PipeRun, full: Bool, center: Float64 = 1.0) -> BuriedPipe:
    return BuriedPipe(
        1, _m(0.5), _m(0.4), _m(center), run, _m(2.0), full, UnitWeight64(24000)
    )


def test_circle_band_area() raises:
    assert_almost_equal(circle_band_area(1, 0, -5, 5), pi, atol=1e-12)
    assert_almost_equal(circle_band_area(1, 0, 0, 5), pi / 2, atol=1e-12)
    assert_almost_equal(circle_band_area(1, 0, 2, 3), 0.0, atol=1e-15)
    assert_almost_equal(circle_band_area(0, 0, -1, 1), 0.0, atol=1e-15)
    assert_almost_equal(circle_band_area(1, 0, 1, 0), 0.0, atol=1e-15)


def test_pipe_weights() raises:
    var ring = pi * (0.25 - 0.16)
    var bore = pi * 0.16
    var outer = pi * 0.25
    var along = pipe_weights(
        [_pipe(ALONG, True)],
        _m(0),
        _m(5),
        None,
        UnitWeight64(GAMMA),
        UnitWeight64(GW),
        _m(3),
    )
    assert_almost_equal(along.soil_removed.value, GAMMA * outer, atol=1e-6)
    assert_almost_equal(along.wall_added.value, 24000 * ring, atol=1e-6)
    assert_almost_equal(along.water_added.value, GW * bore, atol=1e-6)
    assert_almost_equal(
        along.net().value, 24000 * ring + GW * bore - GAMMA * outer, atol=1e-6
    )
    # Across the wall the barrel is shared by its 2 m panel; a 3 m band
    # holds 3/2 of it.
    var across = pipe_weights(
        [_pipe(ACROSS, False)],
        _m(0),
        _m(5),
        None,
        UnitWeight64(GAMMA),
        UnitWeight64(GW),
        _m(3),
    )
    assert_almost_equal(
        across.soil_removed.value, 1.5 * GAMMA * outer, atol=1e-6
    )
    assert_almost_equal(across.water_added.value, 0.0, atol=1e-12)
    # Under water: buoyant soil and pipe wall, and a full bore is neutral.
    var wet = pipe_weights(
        [_pipe(ALONG, True)],
        _m(0),
        _m(5),
        _m(9),
        UnitWeight64(GAMMA),
        UnitWeight64(GW),
        _m(1),
    )
    assert_almost_equal(wet.soil_removed.value, (GAMMA - GW) * outer, atol=1e-6)
    assert_almost_equal(wet.wall_added.value, (24000 - GW) * ring, atol=1e-6)
    assert_almost_equal(wet.water_added.value, 0.0, atol=1e-9)
    var empty_band = pipe_weights(
        [_pipe(ALONG, True)],
        _m(3),
        _m(3),
        None,
        UnitWeight64(GAMMA),
        UnitWeight64(GW),
        _m(1),
    )
    assert_almost_equal(empty_band.net().value, 0.0, atol=1e-12)
    var none = BuriedPipe(
        0, _m(0.5), _m(0.4), _m(1), ALONG, _m(1), True, UnitWeight64(1)
    )
    var zero = pipe_weights(
        [none], _m(0), _m(5), None, UnitWeight64(GAMMA), UnitWeight64(GW), _m(1)
    )
    assert_almost_equal(zero.soil_removed.value, 0.0, atol=1e-12)
    var narrow = pipe_weights(
        [_pipe(ACROSS, True)],
        _m(0),
        _m(5),
        None,
        UnitWeight64(GAMMA),
        UnitWeight64(GW),
        _m(0),
    )
    assert_almost_equal(narrow.soil_removed.value, 0.0, atol=1e-12)
    var moved = _pipe(ALONG, True).shifted(_m(0.25))
    assert_almost_equal(moved.center.value, 0.75, atol=1e-12)


def test_pipe_check() raises:
    var bad = _pipe(ALONG, True)
    bad.count = -1
    with assert_raises(contains="count"):
        bad.check()
    bad = _pipe(PipeRun(5), True)
    with assert_raises(contains="run is not valid"):
        bad.check()
    bad = _pipe(ALONG, True)
    bad.inner_radius = _m(-1)
    with assert_raises(contains="radius"):
        bad.check()
    bad = _pipe(ALONG, True)
    bad.inner_radius = _m(0.6)
    with assert_raises(contains="larger than its barrel"):
        bad.check()
    bad = _pipe(ALONG, True)
    bad.center = Length64(nan[DType.float64]())
    with assert_raises(contains="center"):
        bad.check()
    bad = _pipe(ALONG, True)
    bad.wall_unit_weight = UnitWeight64(-1)
    with assert_raises(contains="unit weight"):
        bad.check()
    bad = _pipe(ACROSS, True)
    bad.panel = _m(0)
    with assert_raises(contains="panel"):
        bad.check()
    with assert_raises(contains="panel"):
        _ = pipe_weights(
            [bad], _m(0), _m(1), None, UnitWeight64(1), UnitWeight64(1), _m(1)
        )
    bad = _pipe(ACROSS, True)
    bad.panel = Length64(inf[DType.float64]())
    with assert_raises(contains="panel"):
        bad.check()
    bad = _pipe(ALONG, True)
    bad.outer_radius = Length64(nan[DType.float64]())
    with assert_raises(contains="radius"):
        bad.check()
    bad = _pipe(ALONG, True)
    bad.inner_radius = Length64(inf[DType.float64]())
    with assert_raises(contains="radius"):
        bad.check()
    bad = _pipe(ALONG, True)
    bad.outer_radius = _m(-1)
    with assert_raises(contains="radius"):
        bad.check()
    bad = _pipe(ALONG, True)
    bad.wall_unit_weight = UnitWeight64(nan[DType.float64]())
    with assert_raises(contains="unit weight"):
        bad.check()


def test_pipe_weights_of_nothing() raises:
    # No pipes, and a pipe of no size, change nothing.
    var empty = pipe_weights(
        List[BuriedPipe](),
        _m(0),
        _m(5),
        None,
        UnitWeight64(GAMMA),
        UnitWeight64(GW),
        _m(1),
    )
    assert_almost_equal(empty.net().value, 0.0, atol=1e-15)
    var thin = BuriedPipe(
        1, _m(0), _m(0), _m(1), ALONG, _m(1), True, UnitWeight64(24000)
    )
    var none = pipe_weights(
        [thin], _m(0), _m(5), None, UnitWeight64(GAMMA), UnitWeight64(GW), _m(1)
    )
    assert_almost_equal(none.soil_removed.value, 0.0, atol=1e-15)
    assert_almost_equal(none.net().value, 0.0, atol=1e-15)


def test_trial_wedge_level_is_rankine() raises:
    var h = 4.0
    var r = trial_wedge_resultant(
        _level(h), _deg(30), UnitWeight64(GAMMA), UnitWeight64(GW)
    )
    assert_almost_equal(
        r.wedge.thrust.value, 0.5 * GAMMA * h * h / 3, atol=1e-3 * GAMMA
    )
    assert_almost_equal(r.wedge.angle.value, pi / 4 + pi / 12, atol=1e-4)
    assert_almost_equal(r.arm.value, h / 3, atol=2e-3)
    var w = trial_wedge(
        _level(h), _deg(30), UnitWeight64(GAMMA), UnitWeight64(GW)
    )
    assert_almost_equal(w.thrust.value, r.wedge.thrust.value, atol=1e-9)
    assert_almost_equal(w.reach.value, h / sqrt(3.0), atol=1e-3)


def test_trial_wedge_water_and_slope() raises:
    var h = 4.0
    var dry = trial_wedge(
        _level(h), _deg(30), UnitWeight64(GAMMA), UnitWeight64(GW)
    )
    var wet = trial_wedge(
        _level(h), _deg(30), UnitWeight64(GAMMA), UnitWeight64(GW), _m(2)
    )
    # Below the water the soil is buoyant, so the effective thrust drops.
    var ka = 1.0 / 3.0
    var expected = (
        0.5 * ka * GAMMA * 4 + ka * GAMMA * 2 * 2 + 0.5 * ka * (GAMMA - GW) * 4
    )
    assert_almost_equal(wet.thrust.value, expected, atol=2e-3 * expected)
    assert_true(wet.thrust.value < dry.thrust.value)
    # A rising grade pushes harder than level ground.
    var rising = GradeProfile(
        [
            GradePoint(_m(0), _m(h)),
            GradePoint(_m(2), _m(h + 1)),
            GradePoint(_m(40), _m(h + 1)),
        ]
    )
    var up = trial_wedge(
        rising, _deg(30), UnitWeight64(GAMMA), UnitWeight64(GW), _m(3.5)
    )
    assert_true(up.thrust.value > wet.thrust.value)
    # A pseudo-static earthquake adds to it.
    var quake = trial_wedge(
        _level(h), _deg(30), UnitWeight64(GAMMA), UnitWeight64(GW), None, 0.12
    )
    assert_true(quake.thrust.value > dry.thrust.value)


def test_trial_wedge_pipes() raises:
    var h = 4.0
    var heavy = BuriedPipe(
        2,
        _m(0.6),
        _m(0.0),
        _m(2.0),
        ACROSS,
        _m(1.0),
        False,
        UnitWeight64(80000),
    )
    var light = BuriedPipe(
        2,
        _m(0.6),
        _m(0.55),
        _m(2.0),
        ACROSS,
        _m(1.0),
        False,
        UnitWeight64(24000),
    )
    var along = BuriedPipe(
        2, _m(0.6), _m(0.0), _m(2.0), ALONG, _m(1.0), False, UnitWeight64(80000)
    )
    var base = trial_wedge(
        _level(h), _deg(30), UnitWeight64(GAMMA), UnitWeight64(GW)
    )
    var more = trial_wedge(
        _level(h),
        _deg(30),
        UnitWeight64(GAMMA),
        UnitWeight64(GW),
        None,
        0.0,
        [heavy],
    )
    var less = trial_wedge(
        _level(h),
        _deg(30),
        UnitWeight64(GAMMA),
        UnitWeight64(GW),
        _m(1),
        0.0,
        [light],
    )
    var same = trial_wedge(
        _level(h),
        _deg(30),
        UnitWeight64(GAMMA),
        UnitWeight64(GW),
        None,
        0.0,
        [along],
    )
    assert_true(more.thrust.value > base.thrust.value)
    assert_true(less.weight.value < base.weight.value)
    assert_almost_equal(same.thrust.value, base.thrust.value, atol=1e-9)
    var r = trial_wedge_resultant(
        _level(h),
        _deg(30),
        UnitWeight64(GAMMA),
        UnitWeight64(GW),
        _m(1),
        0.0,
        [heavy],
    )
    assert_true(r.arm.value > 0 and r.arm.value < h)
    # Pipes across the wall with no barrels, or barrels of no size, are
    # left out of the wedge.
    var no_count = BuriedPipe(
        0, _m(0.6), _m(0.0), _m(2.0), ACROSS, _m(1.0), False, UnitWeight64(1)
    )
    var no_size = BuriedPipe(
        2, _m(0.0), _m(0.0), _m(2.0), ACROSS, _m(1.0), False, UnitWeight64(1)
    )
    var skipped = trial_wedge(
        _level(h),
        _deg(30),
        UnitWeight64(GAMMA),
        UnitWeight64(GW),
        None,
        0.0,
        [no_count, no_size],
    )
    assert_almost_equal(skipped.thrust.value, base.thrust.value, atol=1e-9)
    # Water in a full barrel weighs more than an empty one.
    var full = light
    full.full = True
    var empty = trial_wedge(
        _level(h),
        _deg(30),
        UnitWeight64(GAMMA),
        UnitWeight64(GW),
        None,
        0.0,
        [light],
    )
    var filled = trial_wedge(
        _level(h),
        _deg(30),
        UnitWeight64(GAMMA),
        UnitWeight64(GW),
        None,
        0.0,
        [full],
    )
    assert_true(filled.weight.value > empty.weight.value)


def test_trial_wedge_water_across_a_slope() raises:
    # The ground rises from 4 m to 6 m over 10 m, so a water level between
    # those crosses it inside the wedge, or beyond its end.
    var rising = GradeProfile(
        [
            GradePoint(_m(0), _m(4)),
            GradePoint(_m(10), _m(6)),
            GradePoint(_m(40), _m(6)),
        ]
    )
    var dry = trial_wedge(
        rising, _deg(30), UnitWeight64(GAMMA), UnitWeight64(GW)
    )
    var low = trial_wedge(
        rising, _deg(30), UnitWeight64(GAMMA), UnitWeight64(GW), _m(4.2)
    )
    var high = trial_wedge(
        rising, _deg(30), UnitWeight64(GAMMA), UnitWeight64(GW), _m(5.5)
    )
    assert_true(dry.thrust.value > low.thrust.value)
    assert_true(low.thrust.value > high.thrust.value)


def test_trial_wedge_degenerate_profiles() raises:
    var h = 4.0
    var level = trial_wedge(
        _level(h), _deg(30), UnitWeight64(GAMMA), UnitWeight64(GW)
    )
    # Two points within the tolerance of the plane, both behind it: the
    # first piece lies wholly behind the plane and adds nothing.
    var behind = GradeProfile(
        [
            GradePoint(_m(-1e-9), _m(h)),
            GradePoint(_m(-5e-10), _m(h)),
            GradePoint(_m(50), _m(h)),
        ]
    )
    var b = trial_wedge(behind, _deg(30), UnitWeight64(GAMMA), UnitWeight64(GW))
    assert_almost_equal(b.thrust.value, level.thrust.value, atol=1e-6)
    # A piece of ground too short to measure, along the trial plane, is
    # stepped over.
    var steep = GradeProfile(
        [
            GradePoint(_m(0), _m(0)),
            GradePoint(_m(1), _m(2)),
            GradePoint(_m(40), _m(2)),
        ]
    )
    var short = GradeProfile(
        [
            GradePoint(_m(0), _m(0)),
            GradePoint(_m(1e-13), _m(0)),
            GradePoint(_m(1), _m(2)),
            GradePoint(_m(40), _m(2)),
        ]
    )
    var s0 = trial_wedge(steep, _deg(30), UnitWeight64(GAMMA), UnitWeight64(GW))
    var s1 = trial_wedge(short, _deg(30), UnitWeight64(GAMMA), UnitWeight64(GW))
    assert_true(s0.thrust.value > 0)
    assert_almost_equal(
        s1.thrust.value, s0.thrust.value, atol=1e-6 * s0.thrust.value
    )
    # Water that meets the ground just behind the plane, where the wedge
    # does not reach.
    var start = GradeProfile(
        [
            GradePoint(_m(-1e-9), _m(1)),
            GradePoint(_m(2), _m(5)),
            GradePoint(_m(40), _m(5)),
        ]
    )
    var dry = trial_wedge(
        start, _deg(30), UnitWeight64(GAMMA), UnitWeight64(GW)
    )
    var wet = trial_wedge(
        start, _deg(30), UnitWeight64(GAMMA), UnitWeight64(GW), _m(1 + 1e-12)
    )
    assert_true(wet.thrust.value <= dry.thrust.value)
    assert_true(wet.thrust.value > 0)


def test_trial_wedge_refusals() raises:
    with assert_raises(contains="friction angle"):
        _ = trial_wedge(
            _level(1), _deg(95), UnitWeight64(GAMMA), UnitWeight64(GW)
        )
    with assert_raises(contains="soil unit weight"):
        _ = trial_wedge(_level(1), _deg(30), UnitWeight64(-1), UnitWeight64(GW))
    with assert_raises(contains="soil unit weight"):
        _ = trial_wedge(
            _level(1),
            _deg(30),
            UnitWeight64(nan[DType.float64]()),
            UnitWeight64(GW),
        )
    with assert_raises(contains="water unit weight"):
        _ = trial_wedge(
            _level(1), _deg(30), UnitWeight64(GAMMA), UnitWeight64(-1)
        )
    with assert_raises(contains="seismic"):
        _ = trial_wedge(
            _level(1),
            _deg(30),
            UnitWeight64(GAMMA),
            UnitWeight64(GW),
            None,
            nan[DType.float64](),
        )
    with assert_raises(contains="water unit weight"):
        _ = trial_wedge(
            _level(1),
            _deg(30),
            UnitWeight64(GAMMA),
            UnitWeight64(nan[DType.float64]()),
        )
    with assert_raises(contains="seismic"):
        _ = trial_wedge(
            _level(1),
            _deg(30),
            UnitWeight64(GAMMA),
            UnitWeight64(GW),
            None,
            -0.1,
        )
    var bad = BuriedPipe(
        -1, _m(1), _m(0), _m(1), ALONG, _m(1), False, UnitWeight64(1)
    )
    with assert_raises(contains="count"):
        _ = trial_wedge(
            _level(1),
            _deg(30),
            UnitWeight64(GAMMA),
            UnitWeight64(GW),
            None,
            0.0,
            [bad],
        )
    with assert_raises(contains="stand above"):
        _ = trial_wedge_resultant(
            _level(0), _deg(30), UnitWeight64(GAMMA), UnitWeight64(GW)
        )
    # Ground below the base gives no wedge and no thrust.
    var sunk = trial_wedge(
        _level(-1), _deg(30), UnitWeight64(GAMMA), UnitWeight64(GW)
    )
    assert_almost_equal(sunk.thrust.value, 0.0, atol=1e-12)


def test_net_hydrostatic() raises:
    var g = UnitWeight64(GW)
    # Both levels below the top: the difference of two triangles.
    var r = net_hydrostatic(_m(5), _m(2), _m(10), g)
    assert_almost_equal(r.force.value, 0.5 * GW * (25 - 4), atol=1e-6)
    assert_almost_equal(r.moment.value, GW / 6 * (125 - 8), atol=1e-6)
    assert_almost_equal(r.arm.value, r.moment.value / r.force.value, atol=1e-12)
    # Both above the top: a uniform head difference.
    var over = net_hydrostatic(_m(12), _m(11), _m(10), g)
    assert_almost_equal(over.force.value, GW * 1 * 10, atol=1e-6)
    assert_almost_equal(over.arm.value, 5.0, atol=1e-12)
    # Only the back level above the top: integrate the net diagram.
    var mixed = net_hydrostatic(_m(12), _m(4), _m(10), g)
    var p = GW * 8 * 4 + GW * ((12 - 4) * 6 - 0.5 * 36)
    var m = GW * 8 * 4 * 2 + GW * (12 * (100 - 16) / 2 - (1000 - 64) / 3)
    assert_almost_equal(mixed.force.value, p, atol=1e-6)
    assert_almost_equal(mixed.moment.value, m, atol=1e-5)
    # A front level above the back counts as equal; no head, no force.
    assert_almost_equal(
        net_hydrostatic(_m(3), _m(5), _m(10), g).force.value, 0.0, atol=1e-12
    )
    assert_almost_equal(
        net_hydrostatic(_m(0), _m(0), _m(10), g).force.value, 0.0, atol=1e-12
    )
    assert_almost_equal(
        net_hydrostatic(_m(3), _m(1), _m(0), g).arm.value, 0.0, atol=1e-12
    )
    with assert_raises(contains="finite"):
        _ = net_hydrostatic(Length64(nan[DType.float64]()), _m(0), _m(1), g)
    with assert_raises(contains="finite"):
        _ = net_hydrostatic(_m(1), _m(0), _m(1), UnitWeight64(-1))
    var bad = Length64(nan[DType.float64]())
    with assert_raises(contains="finite"):
        _ = net_hydrostatic(_m(1), bad, _m(1), g)
    with assert_raises(contains="finite"):
        _ = net_hydrostatic(_m(1), _m(0), bad, g)
    with assert_raises(contains="finite"):
        _ = net_hydrostatic(
            _m(1), _m(0), _m(1), UnitWeight64(nan[DType.float64]())
        )


def test_effective_unit_weight() raises:
    var g = UnitWeight64(GAMMA)
    var w = UnitWeight64(GW)
    assert_almost_equal(
        effective_unit_weight(g, _m(0), _m(4), None, w).value, GAMMA, atol=1e-9
    )
    assert_almost_equal(
        effective_unit_weight(g, _m(0), _m(4), _m(1), w).value,
        GAMMA - GW / 4,
        atol=1e-9,
    )
    assert_almost_equal(
        effective_unit_weight(g, _m(0), _m(4), _m(9), w).value,
        GAMMA - GW,
        atol=1e-9,
    )
    assert_almost_equal(
        effective_unit_weight(g, _m(0), _m(4), _m(-2), w).value,
        GAMMA,
        atol=1e-9,
    )
    assert_almost_equal(
        effective_unit_weight(g, _m(2), _m(2), _m(9), w).value, GAMMA, atol=1e-9
    )


def test_surcharge_tables() raises:
    var ft = 0.3048
    assert_almost_equal(
        parallel_wall_height(_m(5 * ft), _m(0)).value / ft, 5.0, atol=1e-12
    )
    assert_almost_equal(
        parallel_wall_height(_m(2 * ft), _m(0)).value / ft, 5.0, atol=1e-12
    )
    assert_almost_equal(
        parallel_wall_height(_m(7.5 * ft), _m(0)).value / ft, 4.25, atol=1e-12
    )
    assert_almost_equal(
        parallel_wall_height(_m(15 * ft), _m(0.5 * ft)).value / ft,
        2.75,
        atol=1e-12,
    )
    assert_almost_equal(
        parallel_wall_height(_m(25 * ft), _m(0)).value / ft, 2.0, atol=1e-12
    )
    assert_almost_equal(
        parallel_wall_height(_m(7.5 * ft), _m(1 * ft)).value / ft,
        2.0,
        atol=1e-12,
    )
    assert_almost_equal(abutment_height(_m(5 * ft)).value / ft, 4.0, atol=1e-12)
    assert_almost_equal(
        abutment_height(_m(15 * ft)).value / ft, 2.5, atol=1e-12
    )
    assert_almost_equal(
        abutment_height(_m(30 * ft)).value / ft, 2.0, atol=1e-12
    )
    with assert_raises(contains="wall height"):
        _ = parallel_wall_height(_m(-1), _m(0))
    with assert_raises(contains="traffic distance"):
        _ = parallel_wall_height(_m(1), Length64(nan[DType.float64]()))
    with assert_raises(contains="abutment height"):
        _ = abutment_height(Length64(inf[DType.float64]()))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
