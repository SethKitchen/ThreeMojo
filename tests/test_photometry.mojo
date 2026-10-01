# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `units.photometry`: illuminance and luminance.

A bare float passed as either, and one passed as the other, are compile
errors; `tests/compile_fail/` holds those cases.
"""

from units.photometry import (
    FOOT_CANDLE,
    KILOLUX,
    LUX,
    NIT,
    Illuminance,
    Luminance,
    diffuse_luminance,
)
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)


def test_an_illuminance_converts_between_units() raises:
    var noon = Illuminance(100, KILOLUX)
    assert_equal(noon.to(LUX), Float32(100000))
    assert_equal(noon.lux, Float32(100000))
    # One foot-candle is one lumen per square foot.
    assert_almost_equal(Illuminance(1, FOOT_CANDLE).to(LUX), Float32(10.7639))


def test_illuminances_add_scale_and_divide() raises:
    var sun = Illuminance(80, KILOLUX)
    var sky = Illuminance(20, KILOLUX)
    assert_equal((sun + sky).to(KILOLUX), Float32(100))
    assert_equal((sun - sky).to(KILOLUX), Float32(60))
    assert_equal((sky * 0.5).to(KILOLUX), Float32(10))
    assert_equal((Float32(2) * sky).to(KILOLUX), Float32(40))
    assert_equal(sun / sky, Float32(4))


def test_illuminances_compare() raises:
    var dim = Illuminance(300, LUX)
    assert_true(dim == Illuminance(0.3, KILOLUX))
    assert_true(dim < Illuminance(301, LUX))
    assert_false(Illuminance(301, LUX) < dim)


def test_a_luminance_converts_scales_and_compares() raises:
    var screen = Luminance(250, NIT)
    assert_equal(screen.to(NIT), Float32(250))
    assert_equal((screen * 2).nits, Float32(500))
    assert_equal(Luminance(1000, NIT) / screen, Float32(4))
    assert_true(screen == Luminance(250, NIT))
    assert_true(screen < Luminance(251, NIT))
    assert_false(Luminance(251, NIT) < screen)


def test_a_white_diffuse_surface_shines_its_light_over_pi() raises:
    var shine = diffuse_luminance(Illuminance(100, KILOLUX))
    assert_almost_equal(shine.to(NIT), Float32(31830.99), atol=0.05)


def test_each_writes_its_unit() raises:
    assert_equal(String(Illuminance(5, LUX)), "5.0 lx")
    assert_equal(String(Luminance(5, NIT)), "5.0 cd/m^2")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
