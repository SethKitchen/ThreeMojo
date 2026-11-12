# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the NDS checks of `extensions.design.wood` and the ACI checks
of `extensions.design.concrete`.

The wall references are the closed forms of a simply supported beam
under a triangular load (Roark, "Formulas for Stress and Strain", table
8.1): reactions w L / 6 and w L / 3, and the largest moment
w L^2 / (9 sqrt 3) at L / sqrt 3 from the free end of the load. The bolt
reference is the NDS 2018 yield limit equations worked by hand.
"""

from std.math import sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from extensions.design.concrete import (
    cantilever_wall_effects,
    fixed_base_moment,
    minimum_wall_steel,
    one_way_shear_strength,
    plain_flexural_strength,
    propped_wall_effects,
    square_footing_side,
    stress_block_factor,
    strip_footing_width,
    tension_strain,
    two_way_shear_stress,
    wall_section_effects,
)
from extensions.design.quantities import (
    POUND64,
    POUND_FOOT,
    PSI,
    SQUARE_INCH,
)
from extensions.design.wood import (
    Lumber,
    SAWN_COLUMN_C,
    beam_column_ratio,
    bearing_stress_ratio,
    bolt_lateral_value,
    column_buckling_stress,
    column_stability_factor,
    dowel_bearing_strength,
    dressed_depth,
    joist_line_load,
    nail_lateral_value,
    simple_span_check,
    southern_pine_no2,
)
from extensions.geotech.concrete import ConcreteStrip
from extensions.geotech.quantities import (
    KIP,
    KSI,
    PCF,
    PLF,
    PSF,
    MomentPerLength64,
    UnitWeight64,
)
from units.si import (
    Angle64,
    Area64,
    DEGREE64,
    FOOT64,
    Force64,
    INCH64,
    Length64,
    LineLoad64,
    Pressure64,
)


def _ft(v: Float64) -> Length64:
    return Length64(v, FOOT64)


def _in(v: Float64) -> Length64:
    return Length64(v, INCH64)


def test_southern_pine_values_by_size() raises:
    var expected: List[Float64] = [1100, 1000, 925, 800, 750]
    var depths: List[Int] = [4, 6, 8, 10, 12]
    var dressed: List[Float64] = [3.5, 5.5, 7.25, 9.25, 11.25]
    for i in range(5):
        var l = southern_pine_no2(depths[i])
        l.check()
        assert_almost_equal(l.bending.to(PSI), expected[i], atol=1e-9)
        assert_almost_equal(dressed_depth(depths[i]).to(INCH64), dressed[i])
    assert_almost_equal(southern_pine_no2(12).compression_parallel.to(PSI), 975)
    with assert_raises(contains="nominal depth"):
        _ = southern_pine_no2(14)


def test_lumber_check_refuses_bad_values() raises:
    var l = southern_pine_no2(10)
    l.shear = Pressure64(0)
    with assert_raises(contains="positive and finite"):
        l.check()
    var m = southern_pine_no2(10)
    m.specific_gravity = 1.2
    with assert_raises(contains="less than 1"):
        m.check()


def test_simple_span_matches_hand_calculation() raises:
    var lumber = southern_pine_no2(10)
    var s = _in(16)
    var dead = joist_line_load(s, Pressure64(15, PSF))
    var live = joist_line_load(s, Pressure64(40, PSF))
    assert_almost_equal(live.to(PLF), 40 * 16.0 / 12, atol=1e-9)
    var r = simple_span_check(
        lumber, _in(1.5), _in(9.25), 1, _ft(12), dead, live, 1, True, 360, 240
    )
    var w = 55 * 16.0 / 12 / 12  # lb/in
    var l = 144.0
    var m = w * l * l / 8
    var sx = 1.5 * 9.25**2 / 6
    assert_almost_equal(r.moment.to(POUND_FOOT), m / 12, atol=1e-6)
    assert_almost_equal(r.bending_stress.to(PSI), m / sx, atol=1e-6)
    assert_almost_equal(r.allowable_bending.to(PSI), 800 * 1.15, atol=1e-9)
    assert_almost_equal(r.bending_ratio, m / sx / 920, atol=1e-9)
    var v = w * (l / 2 - 9.25)
    assert_almost_equal(r.shear.to(POUND64), v, atol=1e-6)
    assert_almost_equal(r.shear_ratio, 1.5 * v / (1.5 * 9.25) / 175, atol=1e-9)
    var i = 1.5 * 9.25**3 / 12
    var dl = 5 * (40 * 16.0 / 144) * l**4 / (384 * 1.4e6 * i)
    assert_almost_equal(r.live_deflection.to(INCH64), dl, atol=1e-9)
    assert_almost_equal(r.live_ratio, dl / (l / 360), atol=1e-9)
    assert_true(r.governing_ratio() == r.bending_ratio)
    # A built-up beam of three plies, not repetitive.
    var b = simple_span_check(
        lumber, _in(1.5), _in(9.25), 3, _ft(6), dead, live, 1, False, 360, 240
    )
    assert_almost_equal(b.allowable_bending.to(PSI), 800, atol=1e-9)
    # A short deep member has no shear past d from the supports.
    var short = simple_span_check(
        lumber, _in(1.5), _in(9.25), 1, _in(12), dead, live, 1, True, 360, 240
    )
    assert_almost_equal(short.shear.to(POUND64), 0, atol=1e-12)


def test_simple_span_refuses_bad_inputs() raises:
    var lumber = southern_pine_no2(10)
    var w = LineLoad64(50, PLF)
    with assert_raises(contains="width and plies"):
        _ = simple_span_check(
            lumber, _in(1.5), _in(9.25), 0, _ft(10), w, w, 1, True, 360, 240
        )
    with assert_raises(contains="depth"):
        _ = simple_span_check(
            lumber, _in(1.5), _in(0), 1, _ft(10), w, w, 1, True, 360, 240
        )
    with assert_raises(contains="span"):
        _ = simple_span_check(
            lumber, _in(1.5), _in(9.25), 1, _ft(0), w, w, 1, True, 360, 240
        )
    with assert_raises(contains="CD"):
        _ = simple_span_check(
            lumber, _in(1.5), _in(9.25), 1, _ft(10), w, w, 0, True, 360, 240
        )
    with assert_raises(contains="live deflection"):
        _ = simple_span_check(
            lumber, _in(1.5), _in(9.25), 1, _ft(10), w, w, 1, True, 0, 240
        )
    with assert_raises(contains="total deflection"):
        _ = simple_span_check(
            lumber, _in(1.5), _in(9.25), 1, _ft(10), w, w, 1, True, 360, 0
        )
    with assert_raises(contains="loads"):
        _ = simple_span_check(
            lumber, _in(1.5), _in(9.25), 1, _ft(10), -w, w, 1, True, 360, 240
        )


def test_bearing_ratio() raises:
    var lumber = southern_pine_no2(10)
    var r = bearing_stress_ratio(
        lumber, Force64(1000, POUND64), _in(1.5), _in(3.5)
    )
    assert_almost_equal(r, 1000 / (1.5 * 3.5 * 565), atol=1e-12)
    with assert_raises(contains="bearing width"):
        _ = bearing_stress_ratio(lumber, Force64(1), _in(0), _in(1))
    with assert_raises(contains="bearing length"):
        _ = bearing_stress_ratio(lumber, Force64(1), _in(1), _in(0))
    with assert_raises(contains="reaction"):
        _ = bearing_stress_ratio(lumber, Force64(-1), _in(1), _in(1))


def test_dowel_bearing_and_hankinson() raises:
    var d = _in(0.625)
    var along = dowel_bearing_strength(0.55, d, Angle64(0, DEGREE64))
    assert_almost_equal(along.to(PSI), 11200 * 0.55, atol=1e-6)
    var across = dowel_bearing_strength(0.55, d, Angle64(90, DEGREE64))
    assert_almost_equal(
        across.to(PSI), 6100 * 0.55**1.45 / sqrt(0.625), atol=1e-6
    )
    var mid = dowel_bearing_strength(0.55, d, Angle64(45, DEGREE64))
    var p = along.to(PSI)
    var q = across.to(PSI)
    assert_almost_equal(mid.to(PSI), p * q / (p * 0.5 + q * 0.5), atol=1e-6)
    with assert_raises(contains="specific gravity"):
        _ = dowel_bearing_strength(1.5, d, Angle64(0, DEGREE64))
    with assert_raises(contains="1/4 in"):
        _ = dowel_bearing_strength(0.5, _in(0.1), Angle64(0, DEGREE64))
    with assert_raises(contains="grain angle"):
        _ = dowel_bearing_strength(0.5, d, Angle64(100, DEGREE64))


def test_sill_bolt_into_concrete() raises:
    # 5/8 in. A307 bolt, 1-1/2 in. Southern Pine sill on concrete, load
    # across the grain. By hand, mode IIIs governs at 579 lb.
    var d = _in(0.625)
    var fes = dowel_bearing_strength(0.55, d, Angle64(90, DEGREE64))
    var z = bolt_lateral_value(
        d,
        _in(6),
        _in(1.5),
        Pressure64(7500, PSI),
        fes,
        Pressure64(45000, PSI),
        Angle64(90, DEGREE64),
    )
    assert_almost_equal(z.lateral.to(POUND64), 579.0, atol=0.5)
    assert_almost_equal(z.lateral.to(POUND64), z.mode_iiis.to(POUND64))
    assert_true(z.mode_iv.value > z.mode_iiis.value)
    assert_true(z.mode_is.value > z.mode_iiis.value)
    assert_true(z.mode_im.value > z.mode_is.value)
    assert_true(z.mode_ii.value > 0 and z.mode_iiim.value > 0)
    # Along the grain: 970 lb, IIIs again.
    var along = bolt_lateral_value(
        d,
        _in(6),
        _in(1.5),
        Pressure64(7500, PSI),
        dowel_bearing_strength(0.55, d, Angle64(0, DEGREE64)),
        Pressure64(45000, PSI),
        Angle64(0, DEGREE64),
    )
    assert_almost_equal(along.lateral.to(POUND64), 972.7, atol=1)
    var f = Pressure64(1000, PSI)
    with assert_raises(contains="bolt diameter"):
        _ = bolt_lateral_value(_in(0.2), _in(6), _in(1.5), f, f, f, Angle64(0))
    with assert_raises(contains="main member"):
        _ = bolt_lateral_value(d, _in(0), _in(1.5), f, f, f, Angle64(0))
    with assert_raises(contains="side member"):
        _ = bolt_lateral_value(d, _in(6), _in(0), f, f, f, Angle64(0))
    with assert_raises(contains="main bearing"):
        _ = bolt_lateral_value(
            d, _in(6), _in(1.5), Pressure64(0), f, f, Angle64(0)
        )
    with assert_raises(contains="side bearing"):
        _ = bolt_lateral_value(
            d, _in(6), _in(1.5), f, Pressure64(0), f, Angle64(0)
        )
    with assert_raises(contains="bolt yield"):
        _ = bolt_lateral_value(
            d, _in(6), _in(1.5), f, f, Pressure64(0), Angle64(0)
        )
    with assert_raises(contains="grain angle"):
        _ = bolt_lateral_value(
            d, _in(6), _in(1.5), f, f, f, Angle64(-5, DEGREE64)
        )


def test_nail_through_osb_into_pine() raises:
    # 10d common (0.148 in., Fyb 90 ksi) through 23/32 OSB (G 0.50) into
    # SYP (G 0.55), 3 in. long: Fe = 16,600 G^1.84, Rd = 2.2. By hand,
    # mode IIIs governs at 106.2 lb.
    var z = nail_lateral_value(
        _in(0.148),
        _in(3.0 - 23.0 / 32),
        _in(23.0 / 32),
        0.55,
        0.50,
        Pressure64(90000, PSI),
    )
    assert_almost_equal(z.lateral.to(POUND64), 106.2, atol=0.2)
    assert_almost_equal(z.lateral.to(POUND64), z.mode_iiis.to(POUND64))
    assert_almost_equal(z.mode_is.to(POUND64), 224.2, atol=0.2)
    assert_true(z.mode_iv.value > z.mode_iiis.value)
    var f = Pressure64(90000, PSI)
    with assert_raises(contains="nail diameter"):
        _ = nail_lateral_value(_in(0.25), _in(2), _in(0.5), 0.55, 0.5, f)
    with assert_raises(contains="nail diameter"):
        _ = nail_lateral_value(_in(0), _in(2), _in(0.5), 0.55, 0.5, f)
    with assert_raises(contains="specific gravity"):
        _ = nail_lateral_value(_in(0.148), _in(2), _in(0.5), 1.2, 0.5, f)
    with assert_raises(contains="specific gravity"):
        _ = nail_lateral_value(_in(0.148), _in(2), _in(0.5), 0.55, 0, f)
    with assert_raises(contains="main member"):
        _ = nail_lateral_value(_in(0.148), _in(0), _in(0.5), 0.55, 0.5, f)
    with assert_raises(contains="side member"):
        _ = nail_lateral_value(_in(0.148), _in(2), _in(0), 0.55, 0.5, f)
    with assert_raises(contains="nail yield"):
        _ = nail_lateral_value(
            _in(0.148), _in(2), _in(0.5), 0.55, 0.5, Pressure64(0)
        )


def test_propped_wall_matches_triangular_closed_form() raises:
    var l = 8.0
    var g = UnitWeight64(60, PCF)
    var e = propped_wall_effects(_ft(l), _ft(l), g, Pressure64(0))
    # w = 60 * 8 = 480 psf at the base.
    var w = 480.0
    assert_almost_equal(e.top_reaction.to(PLF), w * l / 6, atol=1e-6)
    assert_almost_equal(e.bottom_reaction.to(PLF), w * l / 3, atol=1e-6)
    assert_almost_equal(e.total_force.to(PLF), w * l / 2, atol=1e-6)
    var m = w * l * l / (9 * sqrt(3.0))
    assert_almost_equal(e.max_moment.value / 4.4482216152605, m, atol=m * 2e-4)
    assert_almost_equal(
        e.max_moment_height.to(FOOT64), l * (1 - 1 / sqrt(3.0)), atol=0.01
    )
    assert_almost_equal(e.max_shear.to(PLF), w * l / 3, atol=1e-6)
    # A uniform surcharge alone: q L / 2 each end, q L^2 / 8 at midspan.
    var q = propped_wall_effects(
        _ft(l), _ft(l), UnitWeight64(0), Pressure64(100, PSF)
    )
    assert_almost_equal(q.top_reaction.to(PLF), 400, atol=1e-6)
    assert_almost_equal(q.max_moment.value / 4.4482216152605, 800, atol=0.1)
    # Soil above the top support loads only the span.
    var high = propped_wall_effects(_ft(l), _ft(10), g, Pressure64(0))
    assert_almost_equal(
        high.total_force.to(PLF), (600 + 120) / 2 * l, atol=1e-6
    )
    # No soil: no load.
    var none = propped_wall_effects(_ft(l), _ft(0), g, Pressure64(0))
    assert_almost_equal(none.max_moment.value, 0)
    with assert_raises(contains="wall span"):
        _ = propped_wall_effects(_ft(0), _ft(1), g, Pressure64(0))
    with assert_raises(contains="soil height"):
        _ = propped_wall_effects(_ft(1), _ft(-1), g, Pressure64(0))
    with assert_raises(contains="fluid pressure"):
        _ = propped_wall_effects(
            _ft(1), _ft(1), UnitWeight64(-1), Pressure64(0)
        )
    with assert_raises(contains="surcharge"):
        _ = propped_wall_effects(_ft(1), _ft(1), g, Pressure64(-1))


def test_cantilever_wall_closed_form() raises:
    var g = UnitWeight64(60, PCF)
    var c = cantilever_wall_effects(_ft(4), _ft(4), g, Pressure64(0))
    assert_almost_equal(c.bottom_reaction.to(PLF), 60 * 16 / 2.0, atol=1e-6)
    assert_almost_equal(
        c.max_moment.value / 4.4482216152605, 60 * 64 / 6.0, atol=1e-6
    )
    assert_almost_equal(c.top_reaction.value, 0)
    # Soil higher than the wall loads the stem with a trapezoid.
    var t = cantilever_wall_effects(_ft(4), _ft(6), g, Pressure64(0))
    assert_almost_equal(
        t.bottom_reaction.to(PLF), (120 + 360) / 2 * 4.0, atol=1e-6
    )


def test_stress_block_and_strain() raises:
    assert_equal(stress_block_factor(Pressure64(3000, PSI)), 0.85)
    assert_almost_equal(stress_block_factor(Pressure64(6000, PSI)), 0.75)
    assert_almost_equal(stress_block_factor(Pressure64(12000, PSI)), 0.65)
    with assert_raises(contains="concrete strength"):
        _ = stress_block_factor(Pressure64(0))
    # 10 in. wall, No. 5 at 12 in., 1-1/2 in. cover: tension controlled.
    var strip = ConcreteStrip(
        _in(10),
        _in(1.5),
        _in(0.625),
        _in(0.31 / 12),
        Pressure64(3000, PSI),
        Pressure64(60, KSI),
    )
    var a = 0.31 * 60 / (0.85 * 3 * 12)
    var c = a / 0.85
    var d = 10 - 1.5 - 0.3125
    assert_almost_equal(tension_strain(strip), 0.003 * (d - c) / c, atol=1e-9)
    strip.steel = _in(0)
    with assert_raises(contains="without steel"):
        _ = tension_strain(strip)


def test_one_and_two_way_shear() raises:
    var fc = Pressure64(3000, PSI)
    var v = one_way_shear_strength(
        _in(12), _in(8), Area64(0.31, SQUARE_INCH), fc
    )
    var lam = sqrt(2 / (1 + 0.8))
    var rho = 0.31 / 96
    assert_almost_equal(
        v.to(POUND64),
        0.75 * 8 * min(lam, 1.0) * rho ** (1.0 / 3.0) * sqrt(3000.0) * 96,
        atol=1e-6,
    )
    # Heavy steel meets the 5 sqrt(f'c) b d cap.
    var cap = one_way_shear_strength(
        _in(12), _in(4), Area64(20, SQUARE_INCH), fc
    )
    assert_almost_equal(
        cap.to(POUND64), 0.75 * 5 * sqrt(3000.0) * 48, atol=1e-6
    )
    with assert_raises(contains="shear width"):
        _ = one_way_shear_strength(_in(0), _in(8), Area64(0), fc)
    with assert_raises(contains="shear depth"):
        _ = one_way_shear_strength(_in(12), _in(0), Area64(0), fc)
    with assert_raises(contains="concrete strength"):
        _ = one_way_shear_strength(_in(12), _in(8), Area64(0), Pressure64(0))
    with assert_raises(contains="steel area"):
        _ = one_way_shear_strength(_in(12), _in(8), Area64(-1), fc)
    var s = two_way_shear_stress(_in(8), _in(64), 1, 40, fc)
    assert_almost_equal(s.to(PSI), 0.75 * 4 * sqrt(3000.0), atol=1e-6)
    var long = two_way_shear_stress(_in(8), _in(64), 4, 40, fc)
    assert_almost_equal(long.to(PSI), 0.75 * 3 * sqrt(3000.0), atol=1e-6)
    var wide = two_way_shear_stress(_in(8), _in(400), 1, 20, fc)
    assert_almost_equal(wide.to(PSI), 0.75 * 2.4 * sqrt(3000.0), atol=1e-6)
    with assert_raises(contains="beta"):
        _ = two_way_shear_stress(_in(8), _in(64), 0.5, 40, fc)
    with assert_raises(contains="critical perimeter"):
        _ = two_way_shear_stress(_in(8), _in(0), 1, 40, fc)
    with assert_raises(contains="alpha_s"):
        _ = two_way_shear_stress(_in(8), _in(64), 1, 0, fc)
    with assert_raises(contains="shear depth"):
        _ = two_way_shear_stress(_in(0), _in(64), 1, 40, fc)
    with assert_raises(contains="concrete strength"):
        _ = two_way_shear_stress(_in(8), _in(64), 1, 40, Pressure64(0))


def test_plain_concrete_and_minimum_steel() raises:
    var m = plain_flexural_strength(_in(12), _in(8), Pressure64(2500, PSI))
    # phi 5 sqrt(f'c) h^2 / 6 per inch of width, in lb-in/in.
    var expected = 0.6 * 5 * 50 * 64 / 6.0
    assert_almost_equal(m.value / 4.4482216152605, expected, atol=1e-6)
    with assert_raises(contains="width"):
        _ = plain_flexural_strength(_in(0), _in(8), Pressure64(2500, PSI))
    with assert_raises(contains="thickness"):
        _ = plain_flexural_strength(_in(12), _in(0), Pressure64(2500, PSI))
    with assert_raises(contains="concrete strength"):
        _ = plain_flexural_strength(_in(12), _in(8), Pressure64(0))
    var small = minimum_wall_steel(_in(10), False)
    assert_almost_equal(small[0].to(INCH64), 0.012, atol=1e-12)
    assert_almost_equal(small[1].to(INCH64), 0.020, atol=1e-12)
    var large = minimum_wall_steel(_in(10), True)
    assert_almost_equal(large[0].to(INCH64), 0.015, atol=1e-12)
    assert_almost_equal(large[1].to(INCH64), 0.025, atol=1e-12)
    with assert_raises(contains="wall thickness"):
        _ = minimum_wall_steel(_in(0), False)


def test_footing_sizes() raises:
    var side = square_footing_side(
        Force64(13.5, KIP), Pressure64(1500, PSF), Pressure64(150, PSF)
    )
    assert_almost_equal(side.to(FOOT64), sqrt(13500 / 1350.0), atol=1e-9)
    var width = strip_footing_width(
        LineLoad64(2000, PLF), Pressure64(1500, PSF), Pressure64(125, PSF)
    )
    assert_almost_equal(width.to(FOOT64), 2000 / 1375.0, atol=1e-9)
    with assert_raises(contains="footing load"):
        _ = square_footing_side(Force64(-1), Pressure64(1), Pressure64(0))
    with assert_raises(contains="allowable"):
        _ = square_footing_side(Force64(1), Pressure64(0), Pressure64(0))
    with assert_raises(contains="under the allowable"):
        _ = square_footing_side(Force64(1), Pressure64(1), Pressure64(2))
    with assert_raises(contains="footing load"):
        _ = strip_footing_width(LineLoad64(-1), Pressure64(1), Pressure64(0))
    with assert_raises(contains="allowable"):
        _ = strip_footing_width(LineLoad64(1), Pressure64(0), Pressure64(0))
    with assert_raises(contains="under the allowable"):
        _ = strip_footing_width(LineLoad64(1), Pressure64(1), Pressure64(-1))
    assert_false(False)


def _lbft(m: MomentPerLength64) -> Float64:
    return m.value / 4.4482216152605


def test_fixed_base_moment_closed_forms() raises:
    var g = UnitWeight64(60, PCF)
    var none = Pressure64(0)
    # A triangle over the span: w L^2 / 15, with w = 480 psf.
    assert_almost_equal(
        _lbft(fixed_base_moment(_ft(8), _ft(8), g, none)), 2048, atol=1e-6
    )
    # A uniform load: q L^2 / 8.
    var q = fixed_base_moment(
        _ft(8), _ft(8), UnitWeight64(0), Pressure64(100, PSF)
    )
    assert_almost_equal(_lbft(q), 800, atol=1e-6)
    # Soil 2 ft above the top support: a 120 psf uniform part plus the
    # triangle, 960 + 2048.
    assert_almost_equal(
        _lbft(fixed_base_moment(_ft(8), _ft(10), g, none)), 3008, atol=1e-6
    )
    assert_almost_equal(_lbft(fixed_base_moment(_ft(8), _ft(0), g, none)), 0)
    with assert_raises(contains="wall span"):
        _ = fixed_base_moment(_ft(0), _ft(1), g, none)


def test_wall_section_effects_between_pin_and_fixed() raises:
    var g = UnitWeight64(60, PCF)
    var none = Pressure64(0)
    var pin = MomentPerLength64(0)
    var fixed = MomentPerLength64(2048 * 4.4482216152605)
    # Pinned base: the reactions of propped_wall_effects.
    var base = wall_section_effects(_ft(8), _ft(8), g, none, pin, _ft(0))
    assert_almost_equal(base.bottom_reaction.to(PLF), 1280, atol=1e-6)
    assert_almost_equal(base.top_reaction.to(PLF), 640, atol=1e-6)
    assert_almost_equal(base.shear.to(PLF), 1280, atol=1e-6)
    assert_almost_equal(_lbft(base.moment), 0)
    var top = wall_section_effects(_ft(8), _ft(8), g, none, pin, _ft(8))
    assert_almost_equal(_lbft(top.moment), 0, atol=1e-6)
    assert_almost_equal(top.shear.to(PLF), -640, atol=1e-6)
    # Fixed base: 0.4 w L at the base and w L / 10 at the top.
    var f0 = wall_section_effects(_ft(8), _ft(8), g, none, fixed, _ft(0))
    assert_almost_equal(f0.bottom_reaction.to(PLF), 1536, atol=1e-6)
    assert_almost_equal(f0.top_reaction.to(PLF), 384, atol=1e-6)
    assert_almost_equal(_lbft(f0.moment), -2048, atol=1e-6)
    # At mid-height: -2048 + 1536 (4) - (1440 (4) - 2560).
    var mid = wall_section_effects(_ft(8), _ft(8), g, none, fixed, _ft(4))
    assert_almost_equal(_lbft(mid.moment), 896, atol=1e-6)
    assert_almost_equal(mid.shear.to(PLF), 96, atol=1e-6)
    # Above the soil the moment falls in a line to the top support.
    var low = wall_section_effects(_ft(8), _ft(4), g, none, pin, _ft(6))
    assert_almost_equal(_lbft(low.moment), 160, atol=1e-6)
    assert_almost_equal(low.shear.to(PLF), -80, atol=1e-6)
    with assert_raises(contains="base moment"):
        _ = wall_section_effects(
            _ft(8), _ft(8), g, none, MomentPerLength64(Float64.MAX * 2), _ft(1)
        )
    with assert_raises(contains="section height"):
        _ = wall_section_effects(_ft(8), _ft(8), g, none, pin, _ft(-1))
    with assert_raises(contains="section height"):
        _ = wall_section_effects(_ft(8), _ft(8), g, none, pin, _ft(9))
    with assert_raises(contains="surcharge"):
        _ = wall_section_effects(_ft(8), _ft(8), g, Pressure64(-1), pin, _ft(1))


def test_column_stability_and_beam_column() raises:
    var emin = Pressure64(510000, PSI)
    var fce = column_buckling_stress(emin, 25)
    assert_almost_equal(fce.to(PSI), 670.752, atol=1e-9)
    var cp = column_stability_factor(Pressure64(1050, PSI), fce, SAWN_COLUMN_C)
    assert_almost_equal(cp, 0.52366908, atol=1e-7)
    # A very stiff column reaches Fc*.
    var stiff = column_stability_factor(
        Pressure64(1050, PSI), Pressure64(1e9, PSI), SAWN_COLUMN_C
    )
    assert_almost_equal(stiff, 1.0, atol=1e-5)
    # 0.04 + 600 / (1000 (1 - 0.25)).
    var ratio = beam_column_ratio(
        Pressure64(100, PSI),
        Pressure64(500, PSI),
        Pressure64(600, PSI),
        Pressure64(1000, PSI),
        Pressure64(400, PSI),
    )
    assert_almost_equal(ratio, 0.84, atol=1e-12)
    with assert_raises(contains="minimum modulus"):
        _ = column_buckling_stress(Pressure64(0), 10)
    with assert_raises(contains="slenderness"):
        _ = column_buckling_stress(emin, 0)
    with assert_raises(contains="slenderness"):
        _ = column_buckling_stress(emin, 51)
    with assert_raises(contains="Fc*"):
        _ = column_stability_factor(Pressure64(0), fce, 0.8)
    with assert_raises(contains="buckling stress"):
        _ = column_stability_factor(Pressure64(1, PSI), Pressure64(0), 0.8)
    with assert_raises(contains="column factor"):
        _ = column_stability_factor(Pressure64(1, PSI), fce, 1.0)
    with assert_raises(contains="column factor"):
        _ = column_stability_factor(Pressure64(1, PSI), fce, 0.0)
    var one = Pressure64(1, PSI)
    with assert_raises(contains="member stress"):
        _ = beam_column_ratio(Pressure64(-1, PSI), one, one, one, one)
    with assert_raises(contains="member stress"):
        _ = beam_column_ratio(one, one, Pressure64(-1, PSI), one, one)
    with assert_raises(contains="allowable axial"):
        _ = beam_column_ratio(one, Pressure64(0), one, one, Pressure64(9, PSI))
    with assert_raises(contains="allowable bending"):
        _ = beam_column_ratio(one, one, one, Pressure64(0), Pressure64(9, PSI))
    with assert_raises(contains="FcE1"):
        _ = beam_column_ratio(one, one, one, one, one)
    var inf = Pressure64(Float64.MAX * 2)
    with assert_raises(contains="member stress"):
        _ = beam_column_ratio(inf, one, one, one, one)
    with assert_raises(contains="member stress"):
        _ = beam_column_ratio(one, one, inf, one, one)
    with assert_raises(contains="FcE1"):
        _ = beam_column_ratio(one, one, one, one, inf)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
