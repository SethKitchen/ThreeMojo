# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the AISC 360-16 checks of `extensions.design.steel`.

The references are the AISC Steel Construction Manual, 15th edition:
Table 3-2 (W-shape selection by Zx) for Mp / Omega, Lp, Lr and
Vn / Omega, and Table 4-6 (round HSS and pipe in compression). Other
values are the code equations worked by hand.
"""

from std.math import pi, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from extensions.design.quantities import (
    KIP_FOOT,
    KIP_INCH,
    SQUARE_INCH,
)
from extensions.design.steel import (
    SHEAR_SAFETY,
    STOCKY_WEB_SHEAR_SAFETY,
    compression_strength,
    concrete_bearing,
    flexural_strength,
    require_positive,
    shear_strength,
    standard_pipes,
    w_shape,
    w_shapes,
    web_crippling,
    web_local_yielding,
)
from extensions.geotech.quantities import KIP, KSI
from units.si import FOOT64, INCH64, Area64, Length64, Pressure64


def _fy() -> Pressure64:
    return Pressure64(50, KSI)


def test_catalog_holds_fifteen_valid_shapes() raises:
    var shapes = w_shapes()
    assert_equal(len(shapes), 15)
    for s in shapes:
        s.check()
    assert_equal(w_shape("W10x22").depth.to(INCH64), 10.2)
    with assert_raises(contains="Unknown W shape"):
        _ = w_shape("W40x593")


def test_shape_check_refuses_bad_properties() raises:
    var s = w_shape("W8x18")
    s.area = Area64(0)
    with assert_raises(contains="positive and finite"):
        s.check()
    var t = w_shape("W8x18")
    t.k_design = Length64(5, INCH64)
    with assert_raises(contains="fillets must fit"):
        t.check()


def test_braced_w8x18_matches_table_3_2() raises:
    # Table 3-2: Mp / Omega = 42.4 kip-ft for W8x18 at Fy = 50 ksi.
    var f = flexural_strength(w_shape("W8x18"), _fy(), Length64(0, FOOT64), 1)
    assert_almost_equal(f.allowable().to(KIP_FOOT), 42.4, atol=0.05)
    assert_almost_equal(f.yielding.to(KIP_INCH), 850, atol=1e-9)
    assert_almost_equal(f.nominal.to(KIP_INCH), 850, atol=1e-9)


def test_lateral_torsional_buckling_zones() raises:
    var s = w_shape("W8x18")
    # Table 3-2: Lp = 4.34 ft and Lr = 13.5 ft for W8x18.
    var lp = 1.76 * 1.23 * sqrt(29000.0 / 50) / 12
    assert_almost_equal(lp, 4.34, atol=0.01)
    var at_lp = flexural_strength(s, _fy(), Length64(lp, FOOT64), 1)
    assert_almost_equal(at_lp.lateral_torsional.to(KIP_INCH), 850, atol=1e-6)
    # In the inelastic zone F2-2 is linear from Mp at Lp to 0.7 Fy Sx at
    # Lr. Just inside Lr it gives 0.7 * 50 * 15.2 = 532 kip-in.
    var at_lr = flexural_strength(s, _fy(), Length64(13.48, FOOT64), 1)
    assert_almost_equal(at_lr.lateral_torsional.to(KIP_INCH), 532, atol=1)
    var mid = flexural_strength(s, _fy(), Length64(10, FOOT64), 1)
    assert_true(mid.nominal.to(KIP_INCH) < 850)
    assert_true(mid.nominal.to(KIP_INCH) > 532)
    # Cb raises the inelastic strength, but never past Mp.
    var high_cb = flexural_strength(s, _fy(), Length64(10, FOOT64), 3)
    assert_almost_equal(high_cb.nominal.to(KIP_INCH), 850, atol=1e-9)
    # Past Lr the elastic F2-3 governs.
    var long = flexural_strength(s, _fy(), Length64(30, FOOT64), 1)
    var rts = 1.43
    var jc = 0.172 / (15.2 * 7.81)
    var slender = 360 / rts
    var fcr = (
        pi**2 * 29000 / slender**2 * sqrt(1 + 0.078 * jc * slender**2)
    )
    assert_almost_equal(
        long.lateral_torsional.to(KIP_INCH), fcr * 15.2, atol=1e-6
    )
    var long_cb = flexural_strength(s, _fy(), Length64(30, FOOT64), 20)
    assert_almost_equal(long_cb.nominal.to(KIP_INCH), 850, atol=1e-9)


def test_noncompact_and_slender_flanges() raises:
    # W8x10 has bf / 2tf = 9.61, past 0.38 sqrt(E / Fy) = 9.15.
    var s = w_shape("W8x10")
    var f = flexural_strength(s, _fy(), Length64(0, FOOT64), 1)
    var lam = 3.94 / 0.41
    var lp = 0.38 * sqrt(580.0)
    var lr = sqrt(580.0)
    var mp = 50 * 8.87
    var expected = mp - (mp - 0.7 * 50 * 7.81) * (lam - lp) / (lr - lp)
    assert_almost_equal(f.flange_local.to(KIP_INCH), expected, atol=1e-6)
    assert_almost_equal(f.nominal.to(KIP_INCH), expected, atol=1e-6)
    # A thin flange is slender: F3-2 with kc in its range.
    var thin = w_shape("W8x10")
    thin.flange_thickness = Length64(0.06, INCH64)
    var g = flexural_strength(thin, _fy(), Length64(0, FOOT64), 1)
    var h = 7.89 - 2 * 0.505
    var kc = min(max(4 / sqrt(h / 0.17), 0.35), 0.76)
    var lam_t = 3.94 / 0.12
    assert_almost_equal(
        g.flange_local.to(KIP_INCH),
        0.9 * 29000 * kc * 7.81 / lam_t**2,
        atol=1e-6,
    )


def test_flexure_refuses_bad_inputs() raises:
    var s = w_shape("W8x18")
    with assert_raises(contains="yield strength"):
        _ = flexural_strength(s, Pressure64(0), Length64(0), 1)
    with assert_raises(contains="unbraced length"):
        _ = flexural_strength(s, _fy(), Length64(-1, FOOT64), 1)
    with assert_raises(contains="Cb must"):
        _ = flexural_strength(s, _fy(), Length64(0), 0.5)


def test_shear_matches_table_3_2() raises:
    # Table 3-2: Vn / Omega = 37.4 kips for W8x18.
    var v = shear_strength(w_shape("W8x18"), _fy())
    assert_almost_equal(v.allowable().to(KIP), 37.4, atol=0.05)
    assert_equal(v.safety, STOCKY_WEB_SHEAR_SAFETY)
    # W12x14 has h / tw over 2.24 sqrt(E / Fy), so Omega is 1.67.
    var w = shear_strength(w_shape("W12x14"), _fy())
    assert_equal(w.safety, SHEAR_SAFETY)
    assert_almost_equal(w.nominal.to(KIP), 0.6 * 50 * 11.9 * 0.2, atol=1e-9)
    # A thin web takes Cv1 of G2-4.
    var thin = w_shape("W12x14")
    thin.web_thickness = Length64(0.12, INCH64)
    var t = shear_strength(thin, _fy())
    var slender = (11.9 - 1.05) / 0.12
    var cv1 = 1.10 * sqrt(5.34 * 580.0) / slender
    assert_almost_equal(
        t.nominal.to(KIP), 0.6 * 50 * 11.9 * 0.12 * cv1, atol=1e-9
    )
    with assert_raises(contains="yield strength"):
        _ = shear_strength(w_shape("W8x18"), Pressure64(-1, KSI))


def test_web_bearing_limits() raises:
    var s = w_shape("W8x18")
    var lb = Length64(4, INCH64)
    var end = web_local_yielding(s, _fy(), lb, True)
    assert_almost_equal(end.to(KIP), 50 * 0.23 * (2.5 * 0.63 + 4), atol=1e-9)
    var inside = web_local_yielding(s, _fy(), lb, False)
    assert_almost_equal(inside.to(KIP), 50 * 0.23 * (5 * 0.63 + 4), atol=1e-9)
    var root = sqrt(29000 * 50 * 0.33 / 0.23)
    var ratio = (0.23 / 0.33) ** 1.5
    var crip_end = web_crippling(s, _fy(), Length64(1.5, INCH64), True)
    assert_almost_equal(
        crip_end.to(KIP),
        0.40 * 0.23**2 * (1 + 3 * (1.5 / 8.14) * ratio) * root,
        atol=1e-9,
    )
    var crip_long = web_crippling(s, _fy(), lb, True)
    assert_almost_equal(
        crip_long.to(KIP),
        0.40 * 0.23**2 * (1 + (4 * 4 / 8.14 - 0.2) * ratio) * root,
        atol=1e-9,
    )
    var crip_in = web_crippling(s, _fy(), lb, False)
    assert_almost_equal(
        crip_in.to(KIP),
        0.80 * 0.23**2 * (1 + 3 * (4 / 8.14) * ratio) * root,
        atol=1e-9,
    )
    with assert_raises(contains="bearing length"):
        _ = web_crippling(s, _fy(), Length64(0), True)
    with assert_raises(contains="yield strength"):
        _ = web_local_yielding(s, Pressure64(0), lb, True)


def test_pipe_column_matches_table_4_6() raises:
    var pipes = standard_pipes()
    assert_equal(len(pipes), 3)
    ref p = pipes[1]
    assert_equal(p.name, "Pipe 3-1/2 Std")
    # Table 4-6, Fy = 35 ksi: Pn / Omega = 40.3 kips at Lc = 8 ft.
    var pn = compression_strength(
        p.area, p.radius_of_gyration, Pressure64(35, KSI), Length64(8, FOOT64)
    )
    assert_almost_equal(pn.to(KIP) / 1.67, 40.3, atol=0.1)
    # A long column is elastic: 0.877 Fe Ag.
    var long = compression_strength(
        p.area, p.radius_of_gyration, Pressure64(35, KSI), Length64(30, FOOT64)
    )
    var fe = pi**2 * 29000 / (360 / 1.34) ** 2
    assert_almost_equal(long.to(KIP), 0.877 * fe * 2.5, atol=1e-9)
    with assert_raises(contains="effective length"):
        _ = compression_strength(
            p.area, p.radius_of_gyration, Pressure64(35, KSI), Length64(0)
        )


def test_concrete_bearing_limits() raises:
    var fc = Pressure64(3, KSI)
    var a1 = Area64(16, SQUARE_INCH)
    var same = concrete_bearing(fc, a1, a1)
    assert_almost_equal(same.to(KIP), 0.85 * 3 * 16, atol=1e-9)
    var wide = concrete_bearing(fc, a1, Area64(1000, SQUARE_INCH))
    assert_almost_equal(wide.to(KIP), 1.7 * 3 * 16, atol=1e-9)
    with assert_raises(contains="at least the plate area"):
        _ = concrete_bearing(fc, a1, Area64(4, SQUARE_INCH))
    with assert_raises(contains="positive"):
        require_positive(Float64.MAX * 2, "must be positive")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
