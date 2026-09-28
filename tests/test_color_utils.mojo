# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.color_utils` and `units.temperature`.

The expected colors are what three.js r186's `ColorUtils.setKelvin` gives,
in its linear working space, rounded to six places.
"""

from render.color_utils import kelvin_color, set_kelvin
from render.framebuffer import FloatColor
from std.math import nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_raises,
)
from units.temperature import CELSIUS, KELVIN, Temperature


def assert_kelvin(
    kelvin: Float32, red: Float32, green: Float32, blue: Float32
) raises:
    """Assert that a temperature gives three.js's color."""
    var color = kelvin_color(Temperature(kelvin, KELVIN))
    assert_almost_equal(color.r, red, atol=2e-5)
    assert_almost_equal(color.g, green, atol=2e-5)
    assert_almost_equal(color.b, blue, atol=2e-5)
    assert_almost_equal(color.a, 1)


def test_a_temperature_gives_threes_color() raises:
    assert_kelvin(1900, 1, 0.229854, 0)
    assert_kelvin(3200, 1, 0.477115, 0.198484)
    assert_kelvin(6500, 1, 0.992079, 0.956338)
    assert_kelvin(6600, 1, 1, 1)
    assert_kelvin(10000, 0.588681, 0.701615, 1)


def test_a_temperature_outside_the_fit_is_clamped() raises:
    assert_kelvin(500, 1, 0.057671, 0)
    assert_kelvin(1000, 1, 0.057671, 0)
    assert_kelvin(40000, 0.312513, 0.488252, 1)
    assert_kelvin(50000, 0.312513, 0.488252, 1)


def test_setting_a_color_keeps_its_alpha() raises:
    var color = FloatColor(0.1, 0.2, 0.3, 0.4)
    set_kelvin(color, Temperature(6600, KELVIN))
    assert_almost_equal(color.r, 1)
    assert_almost_equal(color.a, 0.4)


def test_a_temperature_that_is_not_a_number_is_refused() raises:
    with assert_raises(contains="number"):
        _ = kelvin_color(Temperature(nan[DType.float32](), KELVIN))


def test_a_temperature_reads_on_either_scale() raises:
    var bulb = Temperature(3200, KELVIN)
    assert_almost_equal(bulb.kelvin, 3200)
    assert_almost_equal(bulb.to(CELSIUS), 2926.85, atol=1e-2)
    var boiling = Temperature(100, CELSIUS)
    assert_almost_equal(boiling.to(KELVIN), 373.15, atol=1e-3)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
