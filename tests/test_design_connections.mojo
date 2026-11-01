# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the connection and interaction checks of `extensions.design`:
the anchors of ACI 318-19 chapter 17, the welds, bolts, base plates and
combined forces of AISC 360-16, and the in-plane shear and plain concrete
checks of ACI 318.

Each expected value is the code equation worked by hand in pounds and
inches.
"""

from std.math import inf, pi, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
)
from extensions.design.anchors import (
    PRYOUT_PHI,
    STEEL_SHEAR_PHI,
    STEEL_TENSION_PHI,
    bond_tension_strength,
    breakout_tension_strength,
    concrete_tension_phi,
    pryout_shear_strength,
    pullout_strength,
    steel_shear_strength,
    steel_tension_strength,
)
from extensions.design.concrete import (
    plain_bearing_strength,
    plain_two_way_shear_strength,
    wall_in_plane_shear_strength,
)
from extensions.design.kinds import AnchorKind, CAST_IN, POST_INSTALLED
from extensions.design.quantities import POUND64, PSI, SQUARE_INCH
from extensions.design.steel import (
    BASE_PLATE_SAFETY,
    BOLT_SAFETY,
    FILLET_WELD_SAFETY,
    base_plate_thickness,
    bolt_shear_strength,
    combined_ratio,
    fillet_weld_strength,
    w_shape,
)
from extensions.geotech.quantities import KIP, KSI, PLF
from units.si import INCH64, Area64, Force64, Length64, Pressure64


def _in(v: Float64) -> Length64:
    return Length64(v, INCH64)


def _psi(v: Float64) -> Pressure64:
    return Pressure64(v, PSI)


def per_foot(stress: Float64) -> Float64:
    # A 10 in. wall: psi times 10 in. is lb/in., times 12 is lb/ft.
    return stress * 10 * 12


def _far() -> Length64:
    # Far enough from every anchor below to be no edge.
    return _in(100)


def test_anchor_kinds_and_factors() raises:
    assert_equal(CAST_IN.name(), "cast-in")
    assert_equal(POST_INSTALLED.name(), "post-installed")
    assert_equal(AnchorKind(2).name(), "?")
    assert_equal(AnchorKind(-1).is_valid(), False)
    assert_equal(concrete_tension_phi(CAST_IN), 0.70)
    assert_equal(concrete_tension_phi(POST_INSTALLED), 0.65)
    with assert_raises(contains="CAST_IN or POST_INSTALLED"):
        _ = concrete_tension_phi(AnchorKind(2))
    assert_equal(STEEL_TENSION_PHI, 0.75)
    assert_equal(STEEL_SHEAR_PHI, 0.65)
    assert_equal(PRYOUT_PHI, 0.70)


def test_steel_strength_caps_the_tensile_strength() raises:
    var a = Area64(0.226, SQUARE_INCH)
    # F1554 Grade 36: f_uta = 58 ksi governs.
    var n = steel_tension_strength(a, _psi(58000), _psi(36000))
    assert_almost_equal(n.to(POUND64), 0.226 * 58000, atol=1e-6)
    var v = steel_shear_strength(a, _psi(58000), _psi(36000))
    assert_almost_equal(v.to(POUND64), 0.6 * 0.226 * 58000, atol=1e-6)
    # 1.9 f_ya governs.
    var b = steel_tension_strength(a, _psi(100000), _psi(36000))
    assert_almost_equal(b.to(POUND64), 0.226 * 1.9 * 36000, atol=1e-6)
    # 125 ksi governs.
    var c = steel_tension_strength(a, _psi(200000), _psi(100000))
    assert_almost_equal(c.to(POUND64), 0.226 * 125000, atol=1e-6)


def test_breakout_far_from_edges() raises:
    var f = breakout_tension_strength(
        CAST_IN, _in(12), _far(), _far(), _far(), _far(), _psi(3000)
    )
    assert_almost_equal(
        f.to(POUND64), 24 * sqrt(3000.0) * 12.0**1.5, atol=1e-6
    )
    var p = breakout_tension_strength(
        POST_INSTALLED, _in(4), _far(), _far(), _far(), _far(), _psi(3000)
    )
    assert_almost_equal(p.to(POUND64), 17 * sqrt(3000.0) * 8.0, atol=1e-6)


def test_breakout_near_one_edge() raises:
    # c = 3 in. on one side of a 4 in. embedment: reach 6 in.
    var f = breakout_tension_strength(
        POST_INSTALLED, _in(4), _in(3), _far(), _far(), _far(), _psi(3000)
    )
    var ratio = (3.0 + 6.0) * 12.0 / (9 * 16.0)
    var psi = 0.7 + 0.3 * 3.0 / 6.0
    assert_almost_equal(
        f.to(POUND64), ratio * psi * 17 * sqrt(3000.0) * 8.0, atol=1e-6
    )


def test_breakout_near_three_edges_reduces_the_embedment() raises:
    # A rod in a 10 in. wall, 12 in. below the top: three edges within
    # 1.5 h_ef = 18 in., so h_ef becomes 12 / 1.5 = 8 in.
    var f = breakout_tension_strength(
        CAST_IN, _in(12), _in(5), _in(5), _in(12), _far(), _psi(3000)
    )
    var ratio = (5.0 + 5.0) * (12.0 + 12.0) / (9 * 64.0)
    var psi = 0.7 + 0.3 * 5.0 / 12.0
    assert_almost_equal(
        f.to(POUND64), ratio * psi * 24 * sqrt(3000.0) * 8.0**1.5, atol=1e-6
    )


def test_pullout_and_pryout() raises:
    var n = pullout_strength(Area64(0.45, SQUARE_INCH), _psi(3000))
    assert_almost_equal(n.to(POUND64), 8 * 0.45 * 3000, atol=1e-6)
    var ncp = Force64(1000, POUND64)
    assert_almost_equal(
        pryout_shear_strength(_in(2), ncp).to(POUND64), 1000, atol=1e-9
    )
    assert_almost_equal(
        pryout_shear_strength(_in(2.5), ncp).to(POUND64), 2000, atol=1e-9
    )


def test_bond_strength() raises:
    var cna = 10 * 0.5 * sqrt(1000.0 / 1100.0)
    var nba = 500 * pi * 0.5 * 4.0
    var far = bond_tension_strength(
        _in(0.5), _in(4), _psi(500), _psi(1000), _far(), _far(), _far(), _far()
    )
    assert_almost_equal(far.to(POUND64), nba, atol=1e-6)
    var near = bond_tension_strength(
        _in(0.5), _in(4), _psi(500), _psi(1000), _in(2), _far(), _far(), _far()
    )
    var ratio = (2 + cna) * (2 * cna) / (4 * cna * cna)
    var psi = 0.7 + 0.3 * 2 / cna
    assert_almost_equal(near.to(POUND64), ratio * psi * nba, atol=1e-6)


def test_anchor_guards() raises:
    var a = Area64(0.226, SQUARE_INCH)
    var c = _in(10)
    var fc = _psi(3000)
    with assert_raises(contains="anchor area"):
        _ = steel_tension_strength(Area64(0), _psi(58000), _psi(36000))
    with assert_raises(contains="anchor area"):
        _ = steel_shear_strength(Area64(-1), _psi(58000), _psi(36000))
    with assert_raises(contains="tensile strength"):
        _ = steel_tension_strength(a, _psi(0), _psi(36000))
    with assert_raises(contains="yield strength"):
        _ = steel_tension_strength(a, _psi(58000), _psi(inf[DType.float64]()))
    with assert_raises(contains="CAST_IN or POST_INSTALLED"):
        _ = breakout_tension_strength(AnchorKind(5), c, c, c, c, c, fc)
    with assert_raises(contains="embedment"):
        _ = breakout_tension_strength(CAST_IN, _in(0), c, c, c, c, fc)
    with assert_raises(contains="concrete strength"):
        _ = breakout_tension_strength(CAST_IN, c, c, c, c, c, _psi(-1))
    with assert_raises(contains="edge distance"):
        _ = breakout_tension_strength(CAST_IN, c, c, c, c, _in(0), fc)
    with assert_raises(contains="bearing area"):
        _ = pullout_strength(Area64(0), fc)
    with assert_raises(contains="concrete strength"):
        _ = pullout_strength(a, _psi(0))
    with assert_raises(contains="anchor diameter"):
        _ = bond_tension_strength(_in(0), c, _psi(500), _psi(1000), c, c, c, c)
    with assert_raises(contains="embedment"):
        _ = bond_tension_strength(
            _in(0.5), _in(0), _psi(500), _psi(1000), c, c, c, c
        )
    with assert_raises(contains="bond stress"):
        _ = bond_tension_strength(_in(0.5), c, _psi(0), _psi(1000), c, c, c, c)
    with assert_raises(contains="bond stress"):
        _ = bond_tension_strength(_in(0.5), c, _psi(500), _psi(0), c, c, c, c)
    with assert_raises(contains="must not exceed"):
        _ = bond_tension_strength(
            _in(0.5), c, _psi(1200), _psi(1000), c, c, c, c
        )
    with assert_raises(contains="edge distance"):
        _ = bond_tension_strength(
            _in(0.5), c, _psi(500), _psi(1000), _in(-1), c, c, c
        )
    with assert_raises(contains="embedment"):
        _ = pryout_shear_strength(_in(0), Force64(1, POUND64))
    with assert_raises(contains="tension strength"):
        _ = pryout_shear_strength(c, Force64(0))


def test_strong_radius_and_combined_ratio() raises:
    var s = w_shape("W8x18")
    assert_almost_equal(
        s.strong_radius().to(INCH64), sqrt(61.9 / 5.26), atol=1e-9
    )
    # H1-1a at and above 0.2, H1-1b below.
    assert_almost_equal(combined_ratio(0.2, 0.45), 0.6, atol=1e-12)
    assert_almost_equal(combined_ratio(0.1, 0.5), 0.55, atol=1e-12)
    with assert_raises(contains="axial ratio"):
        _ = combined_ratio(-0.1, 0.5)
    with assert_raises(contains="axial ratio"):
        _ = combined_ratio(inf[DType.float64](), 0.5)
    with assert_raises(contains="flexural ratio"):
        _ = combined_ratio(0.1, -0.5)
    with assert_raises(contains="flexural ratio"):
        _ = combined_ratio(0.1, inf[DType.float64]())


def test_welds_bolts_and_base_plates() raises:
    assert_equal(FILLET_WELD_SAFETY, 2.0)
    assert_equal(BOLT_SAFETY, 2.0)
    assert_equal(BASE_PLATE_SAFETY, 1.67)
    var w = fillet_weld_strength(_in(0.1875), _in(12), Pressure64(70, KSI))
    assert_almost_equal(w.to(KIP), 0.6 * 70 * 0.707 * 0.1875 * 12, atol=1e-9)
    var b = bolt_shear_strength(
        Area64(0.4418, SQUARE_INCH), Pressure64(54, KSI)
    )
    assert_almost_equal(b.to(KIP), 0.4418 * 54, atol=1e-9)
    var t = base_plate_thickness(
        Force64(10, KIP), _in(6), _in(6), _in(1.4), Pressure64(36, KSI)
    )
    assert_almost_equal(
        t.to(INCH64), 1.4 * sqrt(2 * 10 * 1.67 / (36 * 36.0)), atol=1e-9
    )


def test_connection_guards() raises:
    var k = Pressure64(36, KSI)
    with assert_raises(contains="weld size"):
        _ = fillet_weld_strength(_in(0), _in(1), k)
    with assert_raises(contains="weld length"):
        _ = fillet_weld_strength(_in(0.25), _in(-1), k)
    with assert_raises(contains="electrode strength"):
        _ = fillet_weld_strength(_in(0.25), _in(1), Pressure64(0))
    with assert_raises(contains="bolt area"):
        _ = bolt_shear_strength(Area64(0), k)
    with assert_raises(contains="bolt stress"):
        _ = bolt_shear_strength(Area64(1, SQUARE_INCH), Pressure64(0))
    var p = Force64(10, KIP)
    var l = _in(6)
    with assert_raises(contains="base plate load"):
        _ = base_plate_thickness(Force64(0), l, l, l, k)
    with assert_raises(contains="plate width"):
        _ = base_plate_thickness(p, _in(0), l, l, k)
    with assert_raises(contains="plate length"):
        _ = base_plate_thickness(p, l, _in(0), l, k)
    with assert_raises(contains="plate cantilever"):
        _ = base_plate_thickness(p, l, l, _in(0), k)
    with assert_raises(contains="yield strength"):
        _ = base_plate_thickness(p, l, l, l, Pressure64(0))


def test_in_plane_wall_shear() raises:
    var root = sqrt(3000.0)
    var fc = _psi(3000)
    var fy = _psi(60000)
    var squat = wall_in_plane_shear_strength(_in(10), 1.0, 0.002, fc, fy)
    assert_almost_equal(
        squat.to(PLF), per_foot(3 * root + 0.002 * 60000), atol=1e-6
    )
    var mid = wall_in_plane_shear_strength(_in(10), 1.75, 0.002, fc, fy)
    assert_almost_equal(
        mid.to(PLF), per_foot(2.5 * root + 0.002 * 60000), atol=1e-6
    )
    var tall = wall_in_plane_shear_strength(_in(10), 2.5, 0.0, fc, fy)
    assert_almost_equal(tall.to(PLF), per_foot(2 * root), atol=1e-6)
    var capped = wall_in_plane_shear_strength(_in(10), 1.0, 0.02, fc, fy)
    assert_almost_equal(capped.to(PLF), per_foot(8 * root), atol=1e-6)


def test_plain_concrete() raises:
    var root = sqrt(3000.0)
    var b = plain_bearing_strength(Area64(42, SQUARE_INCH), _psi(3000))
    assert_almost_equal(b.to(POUND64), 0.85 * 3000 * 42, atol=1e-6)
    var square = plain_two_way_shear_strength(
        _in(42.5), _in(4), 1.0, _psi(3000)
    )
    assert_almost_equal(square.to(POUND64), 2.66 * root * 42.5 * 4, atol=1e-6)
    var long = plain_two_way_shear_strength(_in(42.5), _in(4), 4.0, _psi(3000))
    assert_almost_equal(long.to(POUND64), 2.0 * root * 42.5 * 4, atol=1e-6)


def test_wall_and_plain_guards() raises:
    var fc = _psi(3000)
    var fy = _psi(60000)
    with assert_raises(contains="wall thickness"):
        _ = wall_in_plane_shear_strength(_in(0), 1.0, 0.002, fc, fy)
    with assert_raises(contains="aspect ratio"):
        _ = wall_in_plane_shear_strength(_in(10), 0.0, 0.002, fc, fy)
    with assert_raises(contains="concrete strength"):
        _ = wall_in_plane_shear_strength(_in(10), 1.0, 0.002, _psi(0), fy)
    with assert_raises(contains="yield strength"):
        _ = wall_in_plane_shear_strength(_in(10), 1.0, 0.002, fc, _psi(0))
    with assert_raises(contains="steel ratio"):
        _ = wall_in_plane_shear_strength(_in(10), 1.0, -0.001, fc, fy)
    with assert_raises(contains="steel ratio"):
        _ = wall_in_plane_shear_strength(_in(10), 1.0, 1.0, fc, fy)
    with assert_raises(contains="bearing area"):
        _ = plain_bearing_strength(Area64(0), fc)
    with assert_raises(contains="concrete strength"):
        _ = plain_bearing_strength(Area64(1, SQUARE_INCH), _psi(0))
    with assert_raises(contains="perimeter"):
        _ = plain_two_way_shear_strength(_in(0), _in(4), 1.0, fc)
    with assert_raises(contains="thickness"):
        _ = plain_two_way_shear_strength(_in(40), _in(0), 1.0, fc)
    with assert_raises(contains="concrete strength"):
        _ = plain_two_way_shear_strength(_in(40), _in(4), 1.0, _psi(0))
    with assert_raises(contains="beta"):
        _ = plain_two_way_shear_strength(_in(40), _in(4), 0.5, fc)
    with assert_raises(contains="beta"):
        _ = plain_two_way_shear_strength(
            _in(40), _in(4), inf[DType.float64](), fc
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
