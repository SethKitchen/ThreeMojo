# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.castle.masonry`.

The references are the equation of EN 1996-1-1, equation 3.1, evaluated by
hand, and the unit weight of a density under standard gravity.
"""

from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from extensions.castle.masonry import (
    GRAVITY,
    Masonry,
    characteristic_strength,
    clay_brick_masonry,
    dressed_limestone,
)
from std.math import nan, pow
from units.si import (
    Density64,
    KILOGRAM_PER_CUBIC_METER,
    MEGAPASCAL,
    Pressure64,
)


def _good() raises -> Masonry:
    return clay_brick_masonry()


def test_characteristic_strength_follows_the_equation() raises:
    var fk = characteristic_strength(
        Pressure64(15.0, MEGAPASCAL), Pressure64(2.5, MEGAPASCAL), 0.55
    )
    # 15^0.7 = 6.6575 and 2.5^0.3 = 1.3164, so 0.55 x 6.6575 x 1.3164.
    assert_almost_equal(fk.to(MEGAPASCAL), 4.8196, atol=0.001)
    var by_hand = 0.45 * pow(40.0, 0.7) * pow(5.0, 0.3)
    var stone = characteristic_strength(
        Pressure64(40.0, MEGAPASCAL), Pressure64(5.0, MEGAPASCAL), 0.45
    )
    assert_almost_equal(stone.to(MEGAPASCAL), by_hand, atol=1e-9)


def test_strength_refuses_values_that_are_not_positive() raises:
    var good = Pressure64(10.0, MEGAPASCAL)
    with assert_raises(contains="A unit strength must be positive"):
        _ = characteristic_strength(Pressure64(0.0), good, 0.55)
    with assert_raises(contains="A mortar strength must be positive"):
        _ = characteristic_strength(good, Pressure64(-1.0), 0.55)
    with assert_raises(contains="The constant K must be positive"):
        _ = characteristic_strength(good, good, 0.0)
    with assert_raises(contains="The constant K must be positive"):
        _ = characteristic_strength(good, good, nan[DType.float64]())


def test_clay_brick_masonry() raises:
    var m = clay_brick_masonry()
    m.check()
    assert_equal(m.name, "clay brick in lime mortar")
    assert_almost_equal(m.density.to(KILOGRAM_PER_CUBIC_METER), 1800.0)
    assert_almost_equal(m.compressive.to(MEGAPASCAL), 4.8196, atol=0.001)
    # Eurocode 6, clause 3.7.2: E is 1000 fk.
    assert_almost_equal(m.modulus.value, 1000.0 * m.compressive.value)
    assert_almost_equal(m.friction, 0.6)


def test_dressed_limestone() raises:
    var m = dressed_limestone()
    m.check()
    assert_equal(m.name, "dressed limestone")
    assert_almost_equal(m.density.to(KILOGRAM_PER_CUBIC_METER), 2300.0)
    assert_true(m.compressive > clay_brick_masonry().compressive)
    assert_almost_equal(m.friction, 0.65)


def test_unit_weight_is_density_times_gravity() raises:
    var m = clay_brick_masonry()
    assert_almost_equal(m.unit_weight().value, 1800.0 * 9.80665, atol=1e-9)
    assert_almost_equal(GRAVITY.value, 9.80665)


def test_design_strength_divides_by_the_partial_factor() raises:
    var m = clay_brick_masonry()
    assert_almost_equal(
        m.design_strength(2.2).value, m.compressive.value / 2.2, atol=1e-6
    )
    assert_almost_equal(m.design_strength(1.0).value, m.compressive.value)


def test_design_strength_refuses_a_partial_factor_below_one() raises:
    var m = clay_brick_masonry()
    with assert_raises(contains="A partial factor must be 1 or more"):
        _ = m.design_strength(0.5)
    with assert_raises(contains="A partial factor must be 1 or more"):
        _ = m.design_strength(1.0e10)
    with assert_raises(contains="A partial factor must be 1 or more"):
        _ = m.design_strength(nan[DType.float64]())


def test_check_refuses_each_bad_number() raises:
    var m = _good()
    m.density = Density64(0.0)
    with assert_raises(contains="A masonry density must be positive"):
        m.check()
    m = _good()
    m.compressive = Pressure64(-1.0)
    with assert_raises(contains="A masonry strength must be positive"):
        m.check()
    m = _good()
    m.modulus = Pressure64(0.0)
    with assert_raises(contains="A masonry modulus must be positive"):
        m.check()
    m = _good()
    m.friction = nan[DType.float64]()
    with assert_raises(contains="A masonry friction must be positive"):
        m.check()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
