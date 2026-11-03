# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the materials data and coating mechanics of
`extensions.chemistry`.

The CRC melting points must agree with the phase transitions in the NASA
data, which come from a different evaluation. An expansion curve's strain
must match the closed-form integral of a linear coefficient. Stoney's
stress and the stack curvature must invert each other.
"""

from std.math import inf, nan, pi
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_raises,
    assert_true,
)
from extensions.chemistry.catalog import aluminum, iron, magnesium, titanium
from extensions.chemistry.coating import (
    ElasticLayer,
    circular_buckle_stress,
    curve_mismatch_stress,
    mismatch_stress,
    stack_curvature,
    stoney_stress,
    straight_buckle_stress,
    thermal_shock_difference,
)
from extensions.chemistry.elements import (
    ALUMINUM,
    CARBON,
    IRON,
    MAGNESIUM,
    OXYGEN,
    SILICON,
    TITANIUM,
)
from extensions.chemistry.materials import (
    ExpansionCurve,
    eutectic_temperature,
    melting_point,
)
from units.si import InverseLength64, Length64, Pressure64, ThermalExpansion64
from units.temperature import CELSIUS, Temperature64

comptime NAN = nan[DType.float64]()


def _t(kelvin: Float64) -> Temperature64:
    return Temperature64(kelvin)


def _curve(
    var temperatures: List[Float64], var coefficients: List[Float64]
) raises -> ExpansionCurve:
    var ts = List[Temperature64]()
    for t in temperatures:
        ts.append(_t(t))
    var cs = List[ThermalExpansion64]()
    for c in coefficients:
        cs.append(ThermalExpansion64(c))
    return ExpansionCurve(ts^, cs^)


def _film() -> ElasticLayer:
    return ElasticLayer(Pressure64(400e9), 0.25, ThermalExpansion64(2e-6))


def test_expansion_curves() raises:
    var flat = _curve([300.0, 1300.0], [5e-6, 5e-6])
    assert_almost_equal(flat.strain(_t(300), _t(1100)), 5e-6 * 800, atol=1e-15)
    assert_almost_equal(flat.strain(_t(1100), _t(300)), -5e-6 * 800, atol=1e-15)
    # A coefficient that rises linearly from 1e-6 at 300 K by 4e-9 per K.
    var rising = _curve([300.0, 800.0, 1300.0], [1e-6, 3e-6, 5e-6])
    var expected = 1e-6 * 800 + 0.5 * 4e-9 * (800.0 * 800.0)
    assert_almost_equal(rising.strain(_t(300), _t(1100)), expected, atol=1e-15)
    assert_almost_equal(rising.at(_t(550)).value, 2e-6, atol=1e-18)
    assert_almost_equal(rising.at(_t(1050)).value, 4e-6, atol=1e-18)
    assert_almost_equal(rising.at(_t(800)).value, 3e-6, atol=1e-18)
    assert_almost_equal(
        rising.mean(_t(300), _t(1100)).value, expected / 800, atol=1e-18
    )
    with assert_raises(contains="two different temperatures"):
        _ = rising.mean(_t(500), _t(500))
    with assert_raises(contains="outside the expansion curve"):
        _ = rising.at(_t(200))
    with assert_raises(contains="outside the expansion curve"):
        _ = rising.at(_t(1400))
    with assert_raises(contains="needs two points"):
        _ = _curve([300.0], [1e-6])
    with assert_raises(contains="one coefficient per"):
        _ = _curve([300.0, 400.0], [1e-6])
    with assert_raises(contains="must be finite"):
        _ = _curve([300.0, 400.0], [1e-6, NAN])
    with assert_raises(contains="must be finite"):
        _ = _curve([-1.0, 400.0], [1e-6, 1e-6])
    with assert_raises(contains="must ascend"):
        _ = _curve([300.0, 300.0], [1e-6, 1e-6])


def test_curve_stress_matches_means() raises:
    var film_curve = _curve([200.0, 1400.0], [2e-6, 2e-6])
    var substrate_curve = _curve([200.0, 1400.0], [5e-6, 5e-6])
    var substrate = ElasticLayer(
        Pressure64(600e9), 0.2, ThermalExpansion64(5e-6)
    )
    var hot = _t(1100)
    var cold = _t(300)
    assert_almost_equal(
        curve_mismatch_stress(
            _film(), film_curve, substrate_curve, hot, cold
        ).value,
        mismatch_stress(_film(), substrate, hot, cold).value,
        atol=1e-3,
    )


def test_melting_points_agree_with_nasa() raises:
    assert_almost_equal(
        melting_point(ALUMINUM).kelvin,
        aluminum().melting_point().kelvin,
        atol=0.5,
    )
    assert_almost_equal(
        melting_point(MAGNESIUM).kelvin,
        magnesium().melting_point().kelvin,
        atol=0.5,
    )
    assert_almost_equal(
        melting_point(TITANIUM).kelvin,
        titanium().melting_point().kelvin,
        atol=5,
    )
    assert_almost_equal(
        melting_point(IRON).kelvin, iron().melting_point().kelvin, atol=3
    )
    with assert_raises(contains="no melting point for O"):
        _ = melting_point(OXYGEN)
    assert_almost_equal(
        eutectic_temperature(IRON, TITANIUM).to(CELSIUS), 1085.0, atol=1e-9
    )
    assert_almost_equal(
        eutectic_temperature(TITANIUM, IRON).to(CELSIUS), 1085.0, atol=1e-9
    )
    assert_almost_equal(
        eutectic_temperature(CARBON, IRON).to(CELSIUS), 1147.0, atol=1e-9
    )
    assert_almost_equal(
        eutectic_temperature(ALUMINUM, SILICON).to(CELSIUS), 577.0, atol=1e-9
    )
    with assert_raises(contains="no eutectic for Ti-C"):
        _ = eutectic_temperature(TITANIUM, CARBON)


def test_stoney_and_stacks() raises:
    var silicon = ElasticLayer(
        Pressure64(130e9), 0.28, ThermalExpansion64(2.6e-6)
    )
    var h_s = Length64(500e-6)
    var h_f = Length64(1e-6)
    var kappa = InverseLength64(0.02)
    var sigma = stoney_stress(silicon, h_s, h_f, kappa)
    var expected = 130e9 * 500e-6 * 500e-6 * 0.02 / (6 * 0.72 * 1e-6)
    assert_almost_equal(sigma.value, expected, atol=1e-3)
    # The stack's curvature inverts Stoney for one layer.
    var back = stack_curvature([sigma], [h_f], silicon, h_s)
    assert_almost_equal(back.value, 0.02, atol=1e-15)
    # Two layers add stress times thickness.
    var two = stack_curvature(
        [Pressure64(1e8), Pressure64(-5e7)],
        [Length64(1e-6), Length64(2e-6)],
        silicon,
        h_s,
    )
    assert_almost_equal(two.value, 0.0, atol=1e-15)
    var none = stack_curvature(
        List[Pressure64](), List[Length64](), silicon, h_s
    )
    assert_almost_equal(none.value, 0.0, atol=0)
    with assert_raises(contains="one thickness per stress"):
        _ = stack_curvature([sigma], List[Length64](), silicon, h_s)
    with assert_raises(contains="stress must be finite"):
        _ = stack_curvature([Pressure64(NAN)], [h_f], silicon, h_s)
    with assert_raises(contains="layer thickness"):
        _ = stack_curvature([sigma], [Length64(0)], silicon, h_s)
    with assert_raises(contains="substrate thickness"):
        _ = stack_curvature([sigma], [h_f], silicon, Length64(0))
    with assert_raises(contains="substrate thickness"):
        _ = stoney_stress(silicon, Length64(inf[DType.float64]()), h_f, kappa)
    with assert_raises(contains="coating thickness"):
        _ = stoney_stress(silicon, h_s, Length64(-1), kappa)
    with assert_raises(contains="curvature must be finite"):
        _ = stoney_stress(silicon, h_s, h_f, InverseLength64(NAN))
    var bad = ElasticLayer(Pressure64(0), 0.2, ThermalExpansion64(1e-6))
    with assert_raises(contains="modulus"):
        _ = stoney_stress(bad, h_s, h_f, kappa)


def test_buckling_and_shock() raises:
    var film = _film()
    var h = Length64(10e-6)
    var b = Length64(100e-6)
    var plate = 400e9 / (1 - 0.0625) * 0.01
    assert_almost_equal(
        straight_buckle_stress(film, h, b).value,
        pi * pi / 12 * plate,
        atol=1e-3,
    )
    assert_almost_equal(
        circular_buckle_stress(film, h, b).value, 1.2235 * plate, atol=1e-3
    )
    with assert_raises(contains="coating thickness"):
        _ = straight_buckle_stress(film, Length64(0), b)
    with assert_raises(contains="delamination size"):
        _ = circular_buckle_stress(film, h, Length64(0))
    var alumina = ElasticLayer(
        Pressure64(380e9), 0.22, ThermalExpansion64(8e-6)
    )
    var shock = thermal_shock_difference(alumina, Pressure64(300e6))
    assert_almost_equal(shock.value, 300e6 * 0.78 / (380e9 * 8e-6), atol=1e-9)
    assert_true(shock.value > 50 and shock.value < 100)
    with assert_raises(contains="positive expansion"):
        _ = thermal_shock_difference(
            ElasticLayer(Pressure64(1e9), 0.2, ThermalExpansion64(0)),
            Pressure64(1e6),
        )
    with assert_raises(contains="strength must be"):
        _ = thermal_shock_difference(alumina, Pressure64(0))
    with assert_raises(contains="strength must be"):
        _ = thermal_shock_difference(alumina, Pressure64(NAN))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
