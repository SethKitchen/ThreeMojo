# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.design.wind`, `extensions.design.beams` and the
writers `extensions.design.latex` and `extensions.design.tikz`.

The wind references are ASCE/SEI 7-16 Table 26.10-1 (Kz = 0.85 at 15 ft
and 0.98 at 30 ft in Exposure C, 0.57 at 15 ft in B) and Figure 27.3-1.
The beam references are the AISC Manual's beam diagrams 1 and 29: a
simple span, and two equal spans under a uniform load.
"""

from std.math import exp
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from extensions.design.beams import (
    MAX_PATTERNED_SPANS,
    continuous_beam,
    patterned_beam,
)
from extensions.design.kinds import (
    EXPOSURE_B,
    EXPOSURE_C,
    EXPOSURE_D,
    WindExposure,
)
from extensions.design.latex import (
    TexValues,
    feet,
    feet_inches,
    fixed,
    group_thousands,
    inches,
)
from extensions.design.quantities import (
    INCH_TO_THE_FOURTH,
    KIP_FOOT,
    MILE_PER_HOUR,
)
from extensions.design.tikz import TikzBody
from extensions.design.wind import (
    elevation_factor,
    exposure_coefficient,
    leeward_wall_coefficient,
    velocity_pressure,
    wall_net_pressure,
)
from extensions.geotech.quantities import KIP, KSI, PLF, PSF
from std.os import makedirs
from std.pathlib import Path
from units.si import (
    FOOT64,
    INCH64,
    Length64,
    LineLoad64,
    Pressure64,
    SecondMomentOfArea64,
    Velocity64,
)


def test_exposure_kind() raises:
    assert_equal(EXPOSURE_B.name(), "B")
    assert_equal(EXPOSURE_C.name(), "C")
    assert_equal(EXPOSURE_D.name(), "D")
    assert_equal(WindExposure(7).name(), "?")
    assert_true(not WindExposure(-1).is_valid())


def test_exposure_coefficient_matches_table() raises:
    assert_almost_equal(
        exposure_coefficient(Length64(15, FOOT64), EXPOSURE_C), 0.85, atol=0.005
    )
    assert_almost_equal(
        exposure_coefficient(Length64(30, FOOT64), EXPOSURE_C), 0.98, atol=0.005
    )
    assert_almost_equal(
        exposure_coefficient(Length64(15, FOOT64), EXPOSURE_B), 0.57, atol=0.005
    )
    assert_almost_equal(
        exposure_coefficient(Length64(15, FOOT64), EXPOSURE_D), 1.03, atol=0.005
    )
    # Heights under 15 ft use 15 ft.
    assert_equal(
        exposure_coefficient(Length64(5, FOOT64), EXPOSURE_C),
        exposure_coefficient(Length64(15, FOOT64), EXPOSURE_C),
    )
    with assert_raises(contains="gradient height"):
        _ = exposure_coefficient(Length64(5000, FOOT64), EXPOSURE_C)
    with assert_raises(contains="B, C or D"):
        _ = exposure_coefficient(Length64(15, FOOT64), WindExposure(3))


def test_velocity_and_wall_pressure() raises:
    assert_almost_equal(
        elevation_factor(Length64(1000, FOOT64)), exp(-0.0362), atol=1e-12
    )
    with assert_raises(contains="ground elevation"):
        _ = elevation_factor(Length64(Float64.MAX * 2))
    var q = velocity_pressure(Velocity64(115, MILE_PER_HOUR), 0.85, 1, 0.85, 1)
    assert_almost_equal(q.to(PSF), 0.00256 * 0.85 * 0.85 * 115 * 115, atol=1e-9)
    with assert_raises(contains="wind speed"):
        _ = velocity_pressure(Velocity64(0), 1, 1, 1, 1)
    with assert_raises(contains="Kz"):
        _ = velocity_pressure(Velocity64(1, MILE_PER_HOUR), 0, 1, 1, 1)
    with assert_raises(contains="Kzt"):
        _ = velocity_pressure(Velocity64(1, MILE_PER_HOUR), 1, 0, 1, 1)
    with assert_raises(contains="Kd"):
        _ = velocity_pressure(Velocity64(1, MILE_PER_HOUR), 1, 1, 0, 1)
    with assert_raises(contains="Ke"):
        _ = velocity_pressure(Velocity64(1, MILE_PER_HOUR), 1, 1, 1, 0)
    assert_equal(leeward_wall_coefficient(0.5), -0.5)
    assert_almost_equal(leeward_wall_coefficient(1.5), -0.4)
    assert_almost_equal(leeward_wall_coefficient(3), -0.25)
    assert_equal(leeward_wall_coefficient(6), -0.2)
    with assert_raises(contains="L / B"):
        _ = leeward_wall_coefficient(0)
    var net = wall_net_pressure(Pressure64(20, PSF), 1)
    assert_almost_equal(net.to(PSF), 20 * 0.85 * 1.3, atol=1e-9)
    with assert_raises(contains="velocity pressure"):
        _ = wall_net_pressure(Pressure64(0), 1)


def _ei() -> Tuple[Pressure64, SecondMomentOfArea64]:
    return (
        Pressure64(29000, KSI),
        SecondMomentOfArea64(61.9, INCH_TO_THE_FOURTH),
    )


def test_simple_span_beam() raises:
    var ei = _ei()
    var spans: List[Length64] = [Length64(10, FOOT64)]
    var loads: List[LineLoad64] = [LineLoad64(1000, PLF)]
    var r = continuous_beam(spans, loads, ei[0], ei[1])
    assert_almost_equal(r.reactions[0].to(KIP), 5, atol=1e-6)
    assert_almost_equal(r.reactions[1].to(KIP), 5, atol=1e-6)
    assert_almost_equal(r.max_positive.to(KIP_FOOT), 12.5, atol=1e-6)
    assert_almost_equal(r.max_negative.to(KIP_FOOT), 0, atol=1e-6)
    assert_almost_equal(r.max_shear.to(KIP), 5, atol=1e-6)
    var w = 1000.0 / 12
    var delta = 5 * w * 120.0**4 / (384 * 29e6 * 61.9)
    assert_almost_equal(r.max_deflection.to(INCH64), -delta, atol=delta * 1e-6)


def test_two_span_beam_and_patterns() raises:
    var ei = _ei()
    var spans: List[Length64] = [Length64(10, FOOT64), Length64(10, FOOT64)]
    var loads: List[LineLoad64] = [LineLoad64(1000, PLF), LineLoad64(1000, PLF)]
    var r = continuous_beam(spans, loads, ei[0], ei[1])
    assert_almost_equal(r.reactions[1].to(KIP), 12.5, atol=1e-6)
    assert_almost_equal(r.reactions[0].to(KIP), 3.75, atol=1e-6)
    assert_almost_equal(r.max_negative.to(KIP_FOOT), -12.5, atol=1e-6)
    assert_almost_equal(r.max_positive.to(KIP_FOOT), 0.0703125 * 100, atol=1e-3)
    assert_almost_equal(r.max_shear.to(KIP), 6.25, atol=1e-6)
    # Live load on one span gives a larger positive moment than on both.
    var p = patterned_beam(
        spans, LineLoad64(0, PLF), LineLoad64(1000, PLF), ei[0], ei[1]
    )
    # One span loaded: 0.0957 w L^2 positive, 0.0625 w L^2 negative.
    assert_almost_equal(p.max_positive.to(KIP_FOOT), 9.57, atol=0.01)
    assert_almost_equal(p.max_negative.to(KIP_FOOT), -12.5, atol=1e-6)
    assert_almost_equal(p.reactions[1].to(KIP), 12.5, atol=1e-6)
    assert_almost_equal(p.reactions[0].to(KIP), 4.375, atol=1e-6)
    assert_true(p.max_live_deflection.value < 0)
    assert_true(abs(p.max_deflection.value) >= abs(p.max_live_deflection.value))


def test_beam_refuses_bad_inputs() raises:
    var ei = _ei()
    var none = List[Length64]()
    var one: List[Length64] = [Length64(10, FOOT64)]
    var w: List[LineLoad64] = [LineLoad64(1, PLF)]
    with assert_raises(contains="one span"):
        _ = continuous_beam(none, List[LineLoad64](), ei[0], ei[1])
    with assert_raises(contains="span must be positive"):
        var zero: List[Length64] = [Length64(0)]
        _ = continuous_beam(zero, w, ei[0], ei[1])
    with assert_raises(contains="one load per span"):
        _ = continuous_beam(one, List[LineLoad64](), ei[0], ei[1])
    with assert_raises(contains="finite"):
        var bad: List[LineLoad64] = [LineLoad64(Float64.MAX * 2)]
        _ = continuous_beam(one, bad, ei[0], ei[1])
    with assert_raises(contains="E must"):
        _ = continuous_beam(one, w, Pressure64(0), ei[1])
    with assert_raises(contains="I must"):
        _ = continuous_beam(one, w, ei[0], SecondMomentOfArea64(0))
    var many = List[Length64]()
    for _ in range(MAX_PATTERNED_SPANS + 1):
        many.append(Length64(1, FOOT64))
    with assert_raises(contains="at most eight"):
        _ = patterned_beam(many, LineLoad64(1), LineLoad64(1), ei[0], ei[1])


def test_number_text() raises:
    assert_equal(group_thousands("12870"), "12{,}870")
    assert_equal(group_thousands("-1234567.25"), "-1{,}234{,}567.25")
    assert_equal(group_thousands("+999"), "+999")
    assert_equal(group_thousands(""), "")
    assert_equal(fixed(0.375, 2), "0.38")
    with assert_raises(contains="0 to 10"):
        _ = fixed(1, 11)
    with assert_raises(contains="finite"):
        _ = fixed(Float64.MAX * 2, 1)
    assert_equal(feet_inches(feet(18.41667), 2), "18'-5\"")
    assert_equal(feet_inches(inches(108.5), 2), "9'-0 1/2\"")
    assert_equal(feet_inches(inches(3.75), 4), "0'-3 3/4\"")
    assert_equal(feet_inches(inches(3.75), 8), "0'-3 3/4\"")
    assert_equal(feet_inches(inches(11.99), 1), "1'-0\"")
    assert_equal(feet_inches(inches(1.0625), 16), "0'-1 1/16\"")
    with assert_raises(contains="denominator"):
        _ = feet_inches(inches(1), 3)
    with assert_raises(contains="zero or more"):
        _ = feet_inches(inches(-1), 2)


def test_tex_values() raises:
    var v = TexValues("test")
    v.add_number("BeamMoment", 12870.4, 0)
    v.add_text("BeamName", "W8$\\times$18")
    v.add_length("WallHeight", inches(108))
    assert_equal(v.count(), 3)
    var text = v.render()
    assert_true("\\newcommand{\\BeamMoment}{12{,}870}" in text)
    assert_true("\\newcommand{\\WallHeight}{9'-0\"}" in text)
    assert_true(text.startswith("% Auto-generated by test."))
    with assert_raises(contains="used twice"):
        v.add_text("BeamName", "x")
    with assert_raises(contains="ASCII letters"):
        v.add_text("Beam2", "x")
    with assert_raises(contains="ASCII letters"):
        v.add_text("", "x")
    var path = "out/test_design_values.tex"
    makedirs("out", exist_ok=True)
    v.write(path)
    assert_equal(Path(path).read_text(), text)


def test_tikz_body() raises:
    var b = TikzBody("test")
    b.comment("plan")
    b.raw("\\begin{scope}")
    b.box("concfill", "wl", 0, 0, 10, 2.5)
    b.line("home", 0, 0, 1, 1)
    b.circle("colfill", 5, 5, 2)
    b.label("collbl", "west", 1, 2, "C-1")
    b.dimension(0, 120, -10, "10'-0\"")
    b.vertical_dimension(-10, 0, 96, "8'-0\"")
    b.leader("accent", 1, 2, 3, 4)
    var text = b.render()
    assert_true("\\fill[concfill] (0.00,0.00) rectangle (10.00,2.50);" in text)
    assert_true("\\draw[wl] (0.00,0.00) rectangle (10.00,2.50);" in text)
    assert_true("\\draw[home] (0.00,0.00) -- (1.00,1.00);" in text)
    assert_true("\\fill[colfill] (5.00,5.00) circle (2.00);" in text)
    assert_true("\\node[collbl,anchor=west] at (1.00,2.00) {C-1};" in text)
    assert_true("\\dimline{0.00}{-10.00}{120.00}{-10.00}{10'-0\"}" in text)
    assert_true("\\dimlinev{-10.00}{0.00}{-10.00}{96.00}{8'-0\"}" in text)
    assert_true("% plan" in text)
    assert_true(
        "\\draw[accent,line width=0.4pt,-{Stealth[length=3pt]}] (1.00,2.00)"
        + " -- (3.00,4.00);"
        in text
    )
    with assert_raises(contains="two points"):
        b.polyline("wl", [0.0], [0.0])
    with assert_raises(contains="radius"):
        b.circle("x", 0, 0, 0)
    with assert_raises(contains="finite"):
        b.line("x", Float64.MAX * 2, 0, 0, 0)
    makedirs("out", exist_ok=True)
    b.write("out/test_design_body.tex")
    assert_equal(Path("out/test_design_body.tex").read_text(), text)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
