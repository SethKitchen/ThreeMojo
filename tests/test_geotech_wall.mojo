# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the cantilever wall, its LRFD checks, its concrete strips and
its failure motions in `extensions.geotech`.

The reference wall is worked by hand: 4 m high, a 0.5 m footing 3 m wide,
a 0.4 m stem behind a 0.6 m toe, level dry fill at 18 kN/m^3 and phi 30
degrees, concrete at 24 kN/m^3. Bearing factors are AASHTO LRFD Table
10.6.3.1.2a-1 for phi 30: Nc 30.14, Nq 18.40, N_gamma 22.40.
"""

from std.math import inf, isinf, nan, pi, sqrt, tan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from extensions.geotech.concrete import (
    ConcreteStrip,
    cracking_moment,
    flexural_resistance,
    shear_resistance,
)
from extensions.geotech.failure import (
    RigidMotion,
    bearing,
    failure_motion,
    overturning,
    sliding,
    slip,
    stem_hinge,
    still,
    utilization_color,
)
from extensions.geotech.kinds import (
    ALONG,
    BEARING,
    DC,
    EH,
    ES,
    EV,
    FULL_CONTACT,
    FailureMode,
    GLOBAL_SLIP,
    HEEL_TRIANGLE,
    LS,
    LS_V,
    LoadKind,
    OVERTURNING,
    PW,
    SERVICE_PRESSURE,
    SLIDING,
    STEM_FLEXURE,
    STEM_SHEAR,
    TOE_FLEXURE,
    TOE_TRIANGLE,
    WA,
)
from extensions.geotech.loads import (
    LateralLoad,
    LoadFactors,
    Resultant,
    VerticalLoad,
    extreme_event_i,
    factored,
    service_i,
    strength_i_maximum,
    strength_i_minimum,
)
from extensions.geotech.pipes import BuriedPipe
from extensions.geotech.profile import GradePoint, GradeProfile
from extensions.geotech.stability import (
    StabilitySettings,
    base_pressure,
    bearing_factors,
    check_stability,
)
from extensions.geotech.quantities import KSI, MomentPerLength64, UnitWeight64
from extensions.geotech.wall import (
    CantileverWall,
    RetainedSide,
    Soil,
    WallLoads,
    WallMaterials,
    stem_effects,
    wall_loads,
)
from units.si import Angle64, DEGREE64, Length64, LineLoad64, Pressure64

comptime G = 18000.0
comptime GC = 24000.0
comptime GW = 9810.0


def _m(v: Float64) -> Length64:
    return Length64(v)


def _soil() -> Soil:
    return Soil(UnitWeight64(G), Angle64(30, DEGREE64), Pressure64(0))


def _wall(width: Float64 = 3.0) -> CantileverWall:
    return CantileverWall(
        _m(4),
        _m(0.5),
        _m(0.4),
        _m(width),
        _m(0.6),
        _m(0),
        _m(0.3),
        _m(0),
        _m(0),
    )


def _mats() -> WallMaterials:
    return WallMaterials(UnitWeight64(GC), UnitWeight64(GW))


def test_wall_geometry() raises:
    var w = _wall()
    assert_almost_equal(w.heel().value, 2.0, atol=1e-12)
    assert_almost_equal(w.stem_height().value, 3.5, atol=1e-12)
    assert_almost_equal(w.retained_height().value, 4.0, atol=1e-12)
    w.check()
    var bad = _wall()
    bad.height = Length64(nan[DType.float64]())
    with assert_raises(contains="finite"):
        bad.check()
    bad = _wall()
    bad.stem = _m(0)
    with assert_raises(contains="must be positive"):
        bad.check()
    bad = _wall()
    bad.toe = _m(-0.1)
    with assert_raises(contains="cannot be negative"):
        bad.check()
    bad = _wall(0.9)
    with assert_raises(contains="wider than the footing"):
        bad.check()
    bad = _wall()
    bad.footing = _m(4)
    with assert_raises(contains="below the top"):
        bad.check()
    bad = _wall()
    bad.exposed = _m(3.6)
    with assert_raises(contains="stand above the footing"):
        bad.check()
    bad = _wall()
    bad.height = _m(0)
    with assert_raises(contains="must be positive"):
        bad.check()
    bad = _wall()
    bad.footing = _m(0)
    with assert_raises(contains="must be positive"):
        bad.check()
    bad = _wall(0)
    with assert_raises(contains="must be positive"):
        bad.check()
    bad = _wall()
    bad.key_depth = _m(-0.1)
    with assert_raises(contains="cannot be negative"):
        bad.check()
    bad = _wall()
    bad.key_width = _m(-0.1)
    with assert_raises(contains="cannot be negative"):
        bad.check()
    bad = _wall()
    bad.exposed = _m(-0.1)
    with assert_raises(contains="cannot be negative"):
        bad.check()
    bad = _wall()
    bad.stem_void = _m(-0.1)
    with assert_raises(contains="cannot be negative"):
        bad.check()


def test_soil_and_side_checks() raises:
    var s = _soil()
    s.check()
    s.unit_weight = UnitWeight64(-1)
    with assert_raises(contains="unit weight"):
        s.check()
    s = _soil()
    s.friction = Angle64(2.0)
    with assert_raises(contains="friction"):
        s.check()
    s = _soil()
    s.cohesion = Pressure64(-1)
    with assert_raises(contains="cohesion"):
        s.check()
    s = _soil()
    s.unit_weight = UnitWeight64(nan[DType.float64]())
    with assert_raises(contains="unit weight"):
        s.check()
    s = _soil()
    s.friction = Angle64(nan[DType.float64]())
    with assert_raises(contains="friction"):
        s.check()
    s = _soil()
    s.friction = Angle64(-0.1)
    with assert_raises(contains="friction"):
        s.check()
    s = _soil()
    s.cohesion = Pressure64(inf[DType.float64]())
    with assert_raises(contains="cohesion"):
        s.check()
    var t = RetainedSide(_soil())
    t.top_load = LineLoad64(nan[DType.float64]())
    with assert_raises(contains="zero or more"):
        t.check()
    t = RetainedSide(_soil())
    t.rise_weight = Length64(nan[DType.float64]())
    with assert_raises(contains="credited rise"):
        t.check()
    var r = RetainedSide(_soil())
    r.live_height = _m(-1)
    with assert_raises(contains="zero or more"):
        r.check()
    r = RetainedSide(_soil())
    r.rise_weight = _m(-1)
    with assert_raises(contains="credited rise"):
        r.check()
    r = RetainedSide(_soil())
    r.water = Length64(inf[DType.float64]())
    with assert_raises(contains="water level"):
        r.check()
    r = RetainedSide(_soil())
    r.backslope = Angle64(nan[DType.float64]())
    with assert_raises(contains="backslope"):
        r.check()
    r = RetainedSide(_soil())
    r.pipes.append(
        BuriedPipe(-1, _m(1), _m(0), _m(1), ALONG, _m(1), True, UnitWeight64(1))
    )
    with assert_raises(contains="count"):
        r.check()


def test_loads_by_hand() raises:
    var loads = wall_loads(_wall(), RetainedSide(_soil()), _mats())
    assert_almost_equal(
        loads.vertical_force("stem").value, 3.5 * 0.4 * GC, atol=1e-6
    )
    assert_almost_equal(
        loads.vertical_force("footing").value, 3 * 0.5 * GC, atol=1e-6
    )
    assert_almost_equal(
        loads.vertical_force("soil on heel").value, G * 2 * 3.5, atol=1e-6
    )
    assert_almost_equal(loads.vertical_force("nothing").value, 0.0, atol=1e-12)
    assert_almost_equal(loads.active, 1.0 / 3.0, atol=1e-12)
    assert_almost_equal(
        loads.lateral[0].force.value, 0.5 / 3.0 * G * 16, atol=1e-6
    )
    assert_almost_equal(loads.lateral[0].arm.value, 4.0 / 3.0, atol=1e-12)
    assert_false(Bool(loads.wedge))
    assert_almost_equal(WallLoads().vertical_force("stem").value, 0.0, atol=0)


def test_loads_edge_cases() raises:
    var w = _wall()
    # A pipe wall that weighs nothing adds no load of its own.
    var r = RetainedSide(_soil())
    r.pipes.append(
        BuriedPipe(
            1, _m(0.3), _m(0.25), _m(1.5), ALONG, _m(1), False, UnitWeight64(0)
        )
    )
    var weightless = wall_loads(w, r, _mats())
    assert_almost_equal(
        weightless.vertical_force("pipe wall in heel").value, 0.0, atol=0
    )
    # A water drop with no water level behind is a pool at the base.
    var pool = RetainedSide(_soil())
    pool.water_drop = _m(0.5)
    var pool_loads = wall_loads(w, pool, _mats())
    for l in pool_loads.lateral:
        assert_false(l.kind == WA)


def test_level_grade_adds_no_rise() raises:
    # A grade level with the retained height puts no rise on the heel.
    var flat = RetainedSide(_soil())
    flat.grade = GradeProfile(
        [GradePoint(_m(0), _m(0)), GradePoint(_m(20), _m(0))]
    )
    var flat_loads = wall_loads(_wall(), flat, _mats())
    assert_almost_equal(
        flat_loads.vertical_force("rising grade on heel").value, 0.0, atol=0
    )


def test_stem_under_a_dry_grade() raises:
    # The stem under a dry broken grade with no pipes and no water drop.
    var w = _wall()
    var graded = RetainedSide(_soil())
    graded.grade = _rising()
    var stem = stem_effects(w, graded, _mats(), service_i())
    var level = stem_effects(w, RetainedSide(_soil()), _mats(), service_i())
    assert_true(stem.moment.value > level.moment.value)
    assert_true(stem.shear.value > level.shear.value)


def test_stability_by_hand() raises:
    var w = _wall()
    var r = RetainedSide(_soil())
    var loads = wall_loads(w, r, _mats())
    var settings = StabilitySettings(_m(0.5))
    var st = check_stability(w, r, loads, _soil(), UnitWeight64(GW), settings)
    var dc_v = 3.5 * 0.4 * GC + 1.5 * GC
    var dc_m = 3.5 * 0.4 * GC * 0.8 + 1.5 * GC * 1.5
    var ev = G * 7.0
    var p = 0.5 / 3.0 * G * 16
    var v = 0.9 * dc_v + ev
    var mr = 0.9 * dc_m + ev * 2.0
    var e = 1.5 - (mr - 1.5 * p * 4.0 / 3.0) / v
    assert_almost_equal(st.minimum.vertical.value, v, atol=1e-6)
    assert_almost_equal(st.eccentricity.value, e, atol=1e-9)
    assert_almost_equal(st.eccentricity_ratio, e / 0.75, atol=1e-9)
    assert_almost_equal(
        st.sliding_ratio, 1.5 * p / (0.8 * v * tan(pi / 6)), atol=1e-9
    )
    assert_almost_equal(st.ratio(SLIDING), st.sliding_ratio, atol=1e-15)
    assert_almost_equal(
        st.ratio(OVERTURNING), st.eccentricity_ratio, atol=1e-15
    )
    var vb = 1.25 * dc_v + 1.35 * ev
    var mb = 1.25 * dc_m + 1.35 * ev * 2.0
    var eb = 1.5 - (mb - 1.5 * p * 4.0 / 3.0) / vb
    assert_almost_equal(st.effective_width.value, 3 - 2 * eb, atol=1e-9)
    assert_almost_equal(st.bearing_pressure.value, vb / (3 - 2 * eb), atol=1e-6)
    assert_almost_equal(st.ratio(BEARING), st.bearing_ratio, atol=1e-15)
    assert_true(st.bearing_ratio > 0)
    assert_almost_equal(st.ratio(SERVICE_PRESSURE), 0.0, atol=1e-15)
    assert_true(st.strength_pressure.mode == FULL_CONTACT)
    with assert_raises(contains="Not an external"):
        _ = st.ratio(STEM_FLEXURE)
    # A required resistance and an allowed service pressure.
    settings.required_bearing = Pressure64(200000)
    settings.allowed_service = Pressure64(150000)
    var st2 = check_stability(w, r, loads, _soil(), UnitWeight64(GW), settings)
    assert_almost_equal(
        st2.ratio(BEARING), st2.bearing_pressure.value / 200000, atol=1e-12
    )
    assert_almost_equal(
        st2.service_ratio, st2.service_pressure.value / 150000, atol=1e-12
    )


def test_stability_passive_and_water() raises:
    var w = _wall()
    w.key_depth = _m(1.0)
    var r = RetainedSide(_soil())
    r.water = _m(0.0)
    var loads = wall_loads(w, r, _mats())
    var settings = StabilitySettings(_m(0.5))
    var plain = check_stability(
        w, r, loads, _soil(), UnitWeight64(GW), settings
    )
    assert_almost_equal(
        plain.passive.value, 0.5 * 3 * (G - GW) * 1.0, atol=1e-6
    )
    assert_true(plain.sliding_ratio_with_passive < plain.sliding_ratio)
    settings.credit_passive = True
    var credited = check_stability(
        w, r, loads, _soil(), UnitWeight64(GW), settings
    )
    assert_almost_equal(
        credited.sliding_ratio, plain.sliding_ratio_with_passive, atol=1e-12
    )
    assert_almost_equal(
        loads.vertical_force("key").value, 1.0 * 0.3 * (GC - GW), atol=1e-6
    )
    # Water below the base leaves the passive soil at its moist weight.
    r.water = _m(-1.0)
    settings.credit_passive = False
    var deep = check_stability(
        w, r, wall_loads(w, r, _mats()), _soil(), UnitWeight64(GW), settings
    )
    assert_almost_equal(deep.passive.value, 0.5 * 3 * G * 1.0, atol=1e-6)
    assert_true("phi_tau 0.8" in String(settings))


def test_stability_outside_the_base() raises:
    # A narrow footing under a tall push: the resultant leaves the base.
    var w = CantileverWall(
        _m(6), _m(0.5), _m(0.4), _m(1.2), _m(0.4), _m(0), _m(0.3), _m(0), _m(0)
    )
    var r = RetainedSide(_soil())
    r.top_load = LineLoad64(200000)
    var loads = wall_loads(w, r, _mats())
    var settings = StabilitySettings(_m(0.5))
    settings.allowed_service = Pressure64(1)
    var st = check_stability(w, r, loads, _soil(), UnitWeight64(GW), settings)
    assert_true(isinf(st.bearing_pressure.value))
    assert_true(isinf(st.bearing_ratio))
    assert_true(st.eccentricity_ratio > 2)
    assert_true(isinf(st.service_pressure.value))


def test_base_pressure_modes() raises:
    var full = base_pressure(LineLoad64(600), _m(0.2), _m(6))
    assert_true(full.mode == FULL_CONTACT)
    assert_almost_equal(full.at(_m(0)).value, 100 * 1.2, atol=1e-9)
    assert_almost_equal(full.at(_m(3)).value, 100.0, atol=1e-9)
    assert_almost_equal(full.at(_m(7)).value, 0.0, atol=1e-12)
    assert_almost_equal(full.peak().value, 120.0, atol=1e-9)
    var toe = base_pressure(LineLoad64(600), _m(2), _m(6))
    assert_true(toe.mode == TOE_TRIANGLE)
    assert_almost_equal(toe.end.value, 3.0, atol=1e-12)
    assert_almost_equal(toe.peak().value, 400.0, atol=1e-9)
    var heel = base_pressure(LineLoad64(600), _m(-2), _m(6))
    assert_true(heel.mode == HEEL_TRIANGLE)
    assert_almost_equal(heel.start.value, 3.0, atol=1e-12)
    var out = base_pressure(LineLoad64(600), _m(-3), _m(6))
    assert_true(out.mode == HEEL_TRIANGLE)
    assert_almost_equal(out.at(_m(1)).value, 0.0, atol=1e-12)
    # No contact: even its one point carries nothing.
    assert_almost_equal(out.at(_m(0)).value, 0.0, atol=0)
    # Ahead of a heel triangle's contact there is no pressure.
    assert_almost_equal(heel.at(_m(1)).value, 0.0, atol=0)
    assert_almost_equal(heel.at(_m(6)).value, 400.0, atol=1e-9)
    var gone = base_pressure(LineLoad64(600), _m(4), _m(6))
    assert_true(gone.mode == TOE_TRIANGLE)
    with assert_raises(contains="positive load"):
        _ = base_pressure(LineLoad64(0), _m(0), _m(6))
    with assert_raises(contains="positive load"):
        _ = base_pressure(LineLoad64(600), _m(0), _m(0))
    with assert_raises(contains="positive load"):
        _ = base_pressure(
            LineLoad64(600), Length64(nan[DType.float64]()), _m(6)
        )


def test_bearing_factors() raises:
    var f = bearing_factors(pi / 6)
    assert_almost_equal(f[0], 30.14, atol=0.01)
    assert_almost_equal(f[1], 18.40, atol=0.01)
    assert_almost_equal(f[2], 22.40, atol=0.01)
    var z = bearing_factors(0)
    assert_almost_equal(z[0], 5.14, atol=1e-12)
    assert_almost_equal(z[1], 1.0, atol=1e-12)


def test_load_factors() raises:
    var lo = strength_i_minimum()
    assert_almost_equal(lo.of(DC), 0.90, atol=1e-15)
    assert_almost_equal(lo.of(LS_V), 0.0, atol=1e-15)
    var hi = strength_i_maximum()
    assert_almost_equal(hi.of(EV), 1.35, atol=1e-15)
    assert_almost_equal(service_i().of(LS_V), 1.0, atol=1e-15)
    var quake = extreme_event_i()
    assert_almost_equal(quake.of(LS), 0.5, atol=1e-15)
    assert_almost_equal(quake.of(LoadKind(8)), 1.0, atol=1e-15)
    with assert_raises(contains="not valid"):
        _ = lo.of(LoadKind(11))
    var text = String(lo)
    assert_true("DC=0.9" in text)
    var v: List[VerticalLoad] = [VerticalLoad(DC, "a", LineLoad64(10), _m(2))]
    var h: List[LateralLoad] = [LateralLoad(EH, "b", LineLoad64(4), _m(1))]
    var r = factored(v, h, service_i())
    assert_almost_equal(r.location().value, (20.0 - 4.0) / 10.0, atol=1e-12)
    var bad: List[VerticalLoad] = [
        VerticalLoad(DC, "a", LineLoad64(inf[DType.float64]()), _m(2))
    ]
    with assert_raises(contains="not finite"):
        _ = factored(bad, h, service_i())
    var far: List[VerticalLoad] = [
        VerticalLoad(DC, "a", LineLoad64(10), Length64(inf[DType.float64]()))
    ]
    with assert_raises(contains="not finite"):
        _ = factored(far, h, service_i())
    var push: List[LateralLoad] = [
        LateralLoad(EH, "b", LineLoad64(inf[DType.float64]()), _m(1))
    ]
    with assert_raises(contains="not finite"):
        _ = factored(v, push, service_i())
    var high: List[LateralLoad] = [
        LateralLoad(EH, "b", LineLoad64(4), Length64(inf[DType.float64]()))
    ]
    with assert_raises(contains="not finite"):
        _ = factored(v, high, service_i())
    var nothing = factored(
        List[VerticalLoad](), List[LateralLoad](), service_i()
    )
    assert_almost_equal(nothing.vertical.value, 0.0, atol=0)
    assert_almost_equal(nothing.overturning.value, 0.0, atol=0)
    with assert_raises(contains="positive"):
        _ = Resultant(
            LineLoad64(0),
            LineLoad64(0),
            MomentPerLength64(0),
            MomentPerLength64(0),
        ).location()


def _rising() raises -> GradeProfile:
    return GradeProfile(
        [
            GradePoint(_m(0), _m(0)),
            GradePoint(_m(2), _m(1)),
            GradePoint(_m(20), _m(1)),
        ]
    )


def test_loads_grade_water_pipes() raises:
    var w = _wall()
    var r = RetainedSide(_soil())
    r.grade = _rising()
    r.live_height = _m(0.6)
    r.top_load = LineLoad64(1000)
    r.top_load_height = _m(1)
    r.water = _m(4.5)
    r.water_drop = _m(1.0)
    r.pipes.append(
        BuriedPipe(
            1, _m(0.3), _m(0.25), _m(1.5), ALONG, _m(1), True, UnitWeight64(GC)
        )
    )
    var loads = wall_loads(w, r, _mats())
    assert_true(Bool(loads.wedge))
    assert_true(Bool(loads.heel_profile))
    assert_true(loads.vertical_force("pipe wall in heel").value > 0)
    assert_almost_equal(
        loads.vertical_force("water in pipe barrels").value, 0.0, atol=1e-9
    )
    assert_true(loads.vertical_force("rising grade on heel").value > 0)
    var kinds = List[Int]()
    for l in loads.lateral:
        kinds.append(l.kind.value)
    assert_true(WA.value in kinds)
    # A dry pool, below the base, takes no water thrust.
    r.water = _m(-1.0)
    r.water_drop = _m(0.5)
    var dry = wall_loads(w, r, _mats())
    assert_almost_equal(
        dry.vertical_force("water in pipe barrels").value,
        GW * pi * 0.0625,
        atol=1e-6,
    )
    var stem = stem_effects(w, r, _mats(), strength_i_maximum())
    assert_true(stem.moment.value > 0 and stem.shear.value > 0)


def test_loads_rise_and_rankine_water() raises:
    var w = _wall()
    var r = RetainedSide(_soil())
    r.rise = _m(0.5)
    r.rise_weight = _m(0.25)
    r.water = _m(2.0)
    r.water_drop = _m(0.5)
    var loads = wall_loads(w, r, _mats())
    assert_almost_equal(
        loads.vertical_force("rise on heel").value, G * 0.25 * 2, atol=1e-6
    )
    var ka = 1.0 / 3.0
    var expected = 0.5 * ka * G * 4 + ka * G * 2 * 2 + 0.5 * ka * (G - GW) * 4
    assert_almost_equal(loads.lateral[0].force.value, expected, atol=1e-6)
    assert_true(loads.lateral[1].kind == ES)
    var stem = stem_effects(w, r, _mats(), service_i())
    assert_true(stem.moment.value > 0)
    r.rise_weight = _m(0)
    var none = wall_loads(w, r, _mats())
    assert_almost_equal(
        none.vertical_force("rise on heel").value, 0.0, atol=1e-12
    )
    r.rise_weight = None
    var all = wall_loads(w, r, _mats())
    assert_almost_equal(
        all.vertical_force("rise on heel").value, G * 0.5 * 2, atol=1e-6
    )


def test_terrace_below_water() raises:
    var w = _wall()
    var r = RetainedSide(_soil())
    r.grade = _rising()
    r.water = _m(4.5)
    var loads = wall_loads(w, r, _mats())
    var dry = RetainedSide(_soil())
    dry.grade = _rising()
    var dry_loads = wall_loads(w, dry, _mats())
    assert_true(
        loads.vertical_force("rising grade on heel").value
        < dry_loads.vertical_force("rising grade on heel").value
    )


def test_concrete_strip() raises:
    var inch = 0.0254
    # 18-in strip, 2-in cover, #6 at 12 in: As = 0.44 in^2 per 12 in.
    var strip = ConcreteStrip(
        _m(18 * inch),
        _m(2 * inch),
        _m(0.75 * inch),
        _m(0.44 / 12 * inch),
        Pressure64(4, KSI),
        Pressure64(60, KSI),
    )
    var d = 18 - 2 - 0.375
    var a = 0.44 * 60 / (0.85 * 4 * 12)
    var kip_ft = 4448.2216152605 * 0.3048 / 0.3048
    var mn = 0.9 * 0.44 * 60 * (d - a / 2) / 12  # kip-ft per ft
    assert_almost_equal(
        flexural_resistance(strip).value / kip_ft, mn, atol=1e-6
    )
    var mcr = 0.37 * 2 * 12 * 18 * 18 / 6 / 12
    assert_almost_equal(cracking_moment(strip).value / kip_ft, mcr, atol=1e-6)
    var klf = 4448.2216152605 / 0.3048
    var vc = shear_resistance(
        strip, LineLoad64(5 * klf), MomentPerLength64(20 * kip_ft)
    )
    # Independent calculation in customary units for a 12-in strip:
    # Mu = 20 kip-ft = 240 kip-in, Vu = 5 kip, As = 0.44 in^2.
    # dv = d - a/2 = 15.301470588235293 in; Mu/dv exceeds Vu.
    # epsilon = (240/dv + 5)/(29000 * 0.44) = 0.0016210632397313204.
    # sxe = dv and beta = 4.8/(1 + 750*epsilon) * 51/(39 + sxe).
    # phi Vc = 0.9 * 0.0316 * beta * sqrt(4) * 12 * dv.
    assert_almost_equal(vc.value / klf, 21.249258193210874, atol=1e-8)
    # Below Mu = Vu*dv the minimum moment controls, independently of Mu.
    var shear_controlled = shear_resistance(
        strip, LineLoad64(5 * klf), MomentPerLength64(0)
    )
    assert_almost_equal(
        shear_controlled.value / klf, 29.65412139979375, atol=1e-8
    )
    var bare = strip
    bare.steel = _m(0)
    assert_true(
        shear_resistance(bare, LineLoad64(0), MomentPerLength64(0)).value > 0
    )
    var bad = strip
    bad.cover = _m(1)
    with assert_raises(contains="inside"):
        _ = flexural_resistance(bad)
    bad = strip
    bad.concrete_strength = Pressure64(0)
    with assert_raises(contains="strengths"):
        _ = cracking_moment(bad)
    bad = strip
    bad.steel = Length64(nan[DType.float64]())
    with assert_raises(contains="finite"):
        bad.check()
    with assert_raises(contains="finite"):
        _ = shear_resistance(
            strip, LineLoad64(nan[DType.float64]()), MomentPerLength64(0)
        )
    with assert_raises(contains="finite"):
        _ = shear_resistance(
            strip, LineLoad64(0), MomentPerLength64(inf[DType.float64]())
        )
    bad = strip
    bad.cover = _m(-0.01)
    with assert_raises(contains="zero or more"):
        bad.check()
    bad = strip
    bad.thickness = _m(0)
    with assert_raises(contains="strengths"):
        bad.check()
    bad = strip
    bad.steel_strength = Pressure64(0)
    with assert_raises(contains="strengths"):
        bad.check()


def test_motions() raises:
    var w = _wall()
    var p = still().apply(_m(1), _m(2))
    assert_almost_equal(p[0].value, 1.0, atol=1e-15)
    var s = sliding(_m(0.5)).apply(_m(1), _m(2))
    assert_almost_equal(s[0].value, 0.5, atol=1e-15)
    # Tipping forward moves the top toward the front, -x.
    var o = overturning(w, Angle64(0.1)).apply(_m(0.8), _m(4))
    assert_true(o[0].value < 0.8)
    var b = bearing(w, Angle64(0.1), _m(0.2)).apply(_m(0), _m(0))
    assert_true(b[1].value < -0.2)
    # A forward slip carries the mass under its center toward -x.
    var g = slip(_m(1), _m(10), Angle64(0.1)).apply(_m(1), _m(0))
    assert_true(g[0].value < 1)
    var h = stem_hinge(w, Angle64(0.1)).apply(_m(0.6), _m(4))
    assert_true(h[0].value < 0.6)
    var modes: List[FailureMode] = [
        SLIDING,
        OVERTURNING,
        BEARING,
        GLOBAL_SLIP,
        STEM_FLEXURE,
        STEM_SHEAR,
        TOE_FLEXURE,
    ]
    for m in modes:
        var at_rest = failure_motion(m, w, 0.0, _m(1))
        var q = at_rest.apply(_m(1), _m(1))
        assert_almost_equal(q[0].value, 1.0, atol=1e-12)
        assert_almost_equal(q[1].value, 1.0, atol=1e-12)
        _ = failure_motion(m, w, 2.0, _m(1))
    with assert_raises(contains="not valid"):
        _ = failure_motion(FailureMode(20), w, 0.5, _m(1))
    with assert_raises(contains="finite"):
        _ = failure_motion(SLIDING, w, nan[DType.float64](), _m(1))


def test_utilization_color() raises:
    var low = utilization_color(0)
    assert_almost_equal(low[1], 0.23, atol=1e-12)
    var one = utilization_color(1.0)
    assert_almost_equal(one[0], 1.0, atol=1e-12)
    var mid = utilization_color(0.6)
    assert_true(mid[1] > mid[0])
    var top = utilization_color(9)
    assert_almost_equal(top[0], 0.3, atol=1e-12)
    var worst = utilization_color(inf[DType.float64]())
    assert_almost_equal(worst[0], top[0], atol=1e-15)
    var neg = utilization_color(-1)
    assert_almost_equal(neg[0], low[0], atol=1e-15)
    var bad = utilization_color(nan[DType.float64]())
    assert_almost_equal(bad[0], top[0], atol=1e-15)


def test_stem_water_keeps_head_above_soil_and_wall() raises:
    var wall = _wall()
    wall.height = _m(5)
    wall.footing = _m(1)
    var retained = RetainedSide(_soil())
    retained.water = _m(6)
    retained.water_drop = _m(2)
    var water_only = LoadFactors(0, 0, 0, 0, 0, 0, 1, 0, 0)
    var result = stem_effects(wall, retained, _mats(), water_only)
    # From the stem base the levels are 5 and 3 m, on a 4-m stem.
    # p/gamma = 2 on [0,3], then 5-y on [3,4]. Direct integration:
    # V/gamma = 2*3 + integral(5-y,3,4) = 15/2.
    # M/gamma = 2*3^2/2 + integral(y*(5-y),3,4) = 85/6.
    assert_almost_equal(result.shear.value, 7.5 * GW, atol=1e-8)
    assert_almost_equal(result.moment.value, 85.0 / 6.0 * GW, atol=1e-8)
    # Lowering only the soil leaves this isolated hydrostatic load intact.
    wall.exposed = _m(1)
    result = stem_effects(wall, retained, _mats(), water_only)
    assert_almost_equal(result.shear.value, 7.5 * GW, atol=1e-8)
    assert_almost_equal(result.moment.value, 85.0 / 6.0 * GW, atol=1e-8)
    # A water-drop setting alone supplies no head when no water is present.
    retained.water = None
    result = stem_effects(wall, retained, _mats(), water_only)
    assert_almost_equal(result.shear.value, 0.0, atol=0)
    assert_almost_equal(result.moment.value, 0.0, atol=0)


def test_stability_settings_reject_invalid_limits() raises:
    var wall = _wall()
    var retained = RetainedSide(_soil())
    var loads = wall_loads(wall, retained, _mats())
    for value in [-1.0, 0.0, nan[DType.float64](), inf[DType.float64]()]:
        var settings = StabilitySettings(_m(0.5))
        settings.eccentricity_fraction = value
        with assert_raises(contains="finite and positive"):
            _ = check_stability(
                wall, retained, loads, _soil(), UnitWeight64(GW), settings
            )
        settings = StabilitySettings(_m(0.5))
        settings.required_bearing = Pressure64(value)
        with assert_raises(contains="finite and positive"):
            settings.check()
        settings = StabilitySettings(_m(0.5))
        settings.allowed_service = Pressure64(value)
        with assert_raises(contains="finite and positive"):
            settings.check()
    for value in [-1.0, nan[DType.float64](), inf[DType.float64]()]:
        var settings = StabilitySettings(_m(value))
        with assert_raises(contains="finite and nonnegative"):
            settings.check()
        settings = StabilitySettings(_m(0.5))
        settings.sliding_factor = value
        with assert_raises(contains="finite and nonnegative"):
            settings.check()
        settings = StabilitySettings(_m(0.5))
        settings.passive_factor = value
        with assert_raises(contains="finite and nonnegative"):
            settings.check()
        settings = StabilitySettings(_m(0.5))
        settings.bearing_factor = value
        with assert_raises(contains="finite and nonnegative"):
            settings.check()
        settings = StabilitySettings(_m(0.5))
        settings.water_factor_q = value
        with assert_raises(contains="finite and nonnegative"):
            settings.check()
        settings = StabilitySettings(_m(0.5))
        settings.water_factor_gamma = value
        with assert_raises(contains="finite and nonnegative"):
            settings.check()
    for value in [nan[DType.float64](), inf[DType.float64]()]:
        with assert_raises(contains="finite values"):
            _ = base_pressure(LineLoad64(value), _m(0), _m(3))
        with assert_raises(contains="finite values"):
            _ = base_pressure(LineLoad64(1000), _m(0), _m(value))


def test_planar_wall_python_reference() raises:
    # tools/reference_geotech_wall.py independently integrates pressure
    # diagrams and assembles rectangular weights in four dry-wall cases.
    # h, live height, Strength I V/H/e/sliding, Service I peak pressure.
    var cases: List[
        Tuple[Float64, Float64, Float64, Float64, Float64, Float64, Float64]
    ] = [
        # BEGIN PYTHON WALL REFERENCE
        (
            3.0,
            0.0,
            144000.0,
            40500.0,
            0.07374999999999998,
            0.6089241120359334,
            50800.0,
        ),
        (
            3.0,
            0.6,
            144000.0,
            59400.0,
            0.2706249999999999,
            0.8930886976527024,
            59999.999999999985,
        ),
        (
            4.0,
            0.0,
            188640.0,
            72000.0,
            0.28715012722646316,
            0.8263601181149225,
            81546.66666666667,
        ),
        (
            4.0,
            0.6,
            188640.0,
            97200.0,
            0.5543256997455471,
            1.1155861594551453,
            100746.66666666667,
        ),
        # END PYTHON WALL REFERENCE
    ]
    for row in cases:
        var wall = _wall()
        wall.height = _m(row[0])
        var retained = RetainedSide(_soil())
        retained.live_height = _m(row[1])
        var loads = wall_loads(wall, retained, _mats())
        var result = check_stability(
            wall,
            retained,
            loads,
            _soil(),
            UnitWeight64(GW),
            StabilitySettings(_m(0.5)),
        )
        assert_almost_equal(result.minimum.vertical.value, row[2], atol=1e-6)
        assert_almost_equal(result.minimum.horizontal.value, row[3], atol=1e-6)
        assert_almost_equal(result.eccentricity.value, row[4], atol=1e-9)
        assert_almost_equal(result.sliding_ratio, row[5], atol=1e-9)
        assert_almost_equal(result.service_pressure.value, row[6], atol=1e-6)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
