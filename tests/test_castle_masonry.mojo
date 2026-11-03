# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the masonry of a castle, as Eurocode 6 (EN 1996-1-1) gives it.

The reference is worked by hand for the historic brick: units of 20 N/mm^2
and mortar of 2.5 N/mm^2 with K of 0.55 give
f_k = 0.55 * 20^0.7 * 2.5^0.3 = 5.894754 N/mm^2. The design strength over a
partial factor of 2.5 is 2.357902 N/mm^2, E is 1000 f_k and G is 0.4 E. The
shear strength at 0.5 N/mm^2 of compression is 0.2 + 0.4 * 0.5 = 0.4 N/mm^2,
and it is limited to 0.065 * 20 = 1.3 N/mm^2. A density of 1800 kg/m^3
weighs 17.65197 kN/m^3.
"""

from extensions.castle.kinds import ESTIMATED, Provenance
from extensions.castle.masonry import Masonry, historic_brick
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
)
from units.si import KILOGRAM_PER_CUBIC_METER, MEGAPASCAL, Pressure64


def test_the_historic_brick_is_an_estimate() raises:
    var brick = historic_brick()
    brick.check()
    assert_equal(brick.provenance, ESTIMATED)
    assert_almost_equal(brick.unit_strength.to(MEGAPASCAL), 20.0, atol=1e-6)
    assert_almost_equal(brick.mortar_strength.to(MEGAPASCAL), 2.5, atol=1e-6)
    assert_almost_equal(
        brick.density.to(KILOGRAM_PER_CUBIC_METER), 1800.0, atol=1e-6
    )


def test_the_strengths_follow_equation_3_2() raises:
    var brick = historic_brick()
    assert_almost_equal(
        brick.characteristic_strength().to(MEGAPASCAL), 5.894754, atol=1e-5
    )
    assert_almost_equal(
        brick.design_strength().to(MEGAPASCAL), 2.357902, atol=1e-5
    )


def test_the_moduli_follow_the_strength() raises:
    var brick = historic_brick()
    assert_almost_equal(
        brick.elastic_modulus().to(MEGAPASCAL), 5894.754, atol=1e-2
    )
    assert_almost_equal(
        brick.shear_modulus().to(MEGAPASCAL), 2357.902, atol=1e-2
    )


def test_the_shear_strength_grows_with_compression_up_to_its_limit() raises:
    var brick = historic_brick()
    assert_almost_equal(
        brick.shear_strength(Pressure64(0.0)).to(MEGAPASCAL), 0.2, atol=1e-9
    )
    assert_almost_equal(
        brick.shear_strength(Pressure64(0.5, MEGAPASCAL)).to(MEGAPASCAL),
        0.4,
        atol=1e-9,
    )
    assert_almost_equal(
        brick.shear_strength(Pressure64(5.0, MEGAPASCAL)).to(MEGAPASCAL),
        1.3,
        atol=1e-9,
    )
    with assert_raises(contains="compressive stress"):
        _ = brick.shear_strength(Pressure64(-1.0))
    with assert_raises(contains="compressive stress"):
        _ = brick.shear_strength(Pressure64(nan[DType.float64]()))
    with assert_raises(contains="compressive stress"):
        _ = brick.shear_strength(Pressure64(inf[DType.float64]()))


def test_the_unit_weight_is_the_density_times_gravity() raises:
    assert_almost_equal(
        historic_brick().unit_weight().value, 17651.97, atol=0.01
    )


def test_a_masonry_that_cannot_be_analyzed_is_refused() raises:
    var bad = historic_brick()
    bad.unit_strength = Pressure64(0.0)
    with assert_raises(contains="unit strength"):
        bad.check()
    bad = historic_brick()
    bad.unit_strength = Pressure64(nan[DType.float64]())
    with assert_raises(contains="unit strength"):
        bad.check()
    bad = historic_brick()
    bad.mortar_strength = Pressure64(-1.0)
    with assert_raises(contains="mortar strength"):
        bad.check()
    bad = historic_brick()
    bad.mortar_strength = Pressure64(inf[DType.float64]())
    with assert_raises(contains="mortar strength"):
        bad.check()
    bad = historic_brick()
    bad.mortar_strength = Pressure64(30.0, MEGAPASCAL)
    with assert_raises(contains="stronger than the unit"):
        bad.check()
    bad = historic_brick()
    bad.k = 0.0
    with assert_raises(contains="constant K"):
        bad.check()
    bad.k = nan[DType.float64]()
    with assert_raises(contains="constant K"):
        bad.check()
    bad = historic_brick()
    bad.density = historic_brick().density.scaled(0.0)
    with assert_raises(contains="density"):
        bad.check()
    bad.density = historic_brick().density.scaled(nan[DType.float64]())
    with assert_raises(contains="density"):
        bad.check()
    bad = historic_brick()
    bad.partial_factor = 0.0
    with assert_raises(contains="partial factor"):
        bad.check()
    bad.partial_factor = inf[DType.float64]()
    with assert_raises(contains="partial factor"):
        bad.check()
    bad = historic_brick()
    bad.initial_shear = Pressure64(-0.1)
    with assert_raises(contains="initial shear"):
        bad.check()
    bad.initial_shear = Pressure64(nan[DType.float64]())
    with assert_raises(contains="initial shear"):
        bad.check()
    bad = historic_brick()
    bad.provenance = Provenance(9)
    with assert_raises(contains="provenance"):
        bad.check()
    with assert_raises(contains="provenance"):
        _ = bad.characteristic_strength()
    with assert_raises(contains="provenance"):
        _ = bad.design_strength()
    with assert_raises(contains="provenance"):
        _ = bad.unit_weight()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
