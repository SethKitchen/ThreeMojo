# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `math.spherical_harmonics3`.

The numbers are three.js's: each basis function and each irradiance weight
at a direction chosen so that every term is non-zero, and the methods of
`SphericalHarmonics3` against sums worked out by hand.
"""

from math.spherical_harmonics3 import (
    SH_COUNT,
    SphericalHarmonics3,
    sh_basis,
    sh_from_array,
    sh_irradiance_weight,
)
from math.vector3 import Vector3
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

comptime TOLERANCE = Float64(1e-5)


def _near(actual: Float32, expected: Float32) raises:
    assert_almost_equal(actual, expected, atol=TOLERANCE)


def test_the_basis_is_three_js_table() raises:
    var n = Vector3(0.48, 0.6, 0.64)
    _near(sh_basis(0, n), 0.282095)
    _near(sh_basis(1, n), 0.488603 * 0.6)
    _near(sh_basis(2, n), 0.488603 * 0.64)
    _near(sh_basis(3, n), 0.488603 * 0.48)
    _near(sh_basis(4, n), 1.092548 * 0.48 * 0.6)
    _near(sh_basis(5, n), 1.092548 * 0.6 * 0.64)
    _near(sh_basis(6, n), 0.315392 * (3 * 0.64 * 0.64 - 1))
    _near(sh_basis(7, n), 1.092548 * 0.48 * 0.64)
    _near(sh_basis(8, n), 0.546274 * (0.48 * 0.48 - 0.6 * 0.6))
    # Past the ninth term there is none.
    assert_equal(sh_basis(SH_COUNT, n), 0)


def test_the_irradiance_weights_are_three_js_table() raises:
    var n = Vector3(0.48, 0.6, 0.64)
    _near(sh_irradiance_weight(0, n), 0.886227)
    _near(sh_irradiance_weight(1, n), 2 * 0.511664 * 0.6)
    _near(sh_irradiance_weight(2, n), 2 * 0.511664 * 0.64)
    _near(sh_irradiance_weight(3, n), 2 * 0.511664 * 0.48)
    _near(sh_irradiance_weight(4, n), 2 * 0.429043 * 0.48 * 0.6)
    _near(sh_irradiance_weight(5, n), 2 * 0.429043 * 0.6 * 0.64)
    _near(sh_irradiance_weight(6, n), 0.743125 * 0.64 * 0.64 - 0.247708)
    _near(sh_irradiance_weight(7, n), 2 * 0.429043 * 0.48 * 0.64)
    _near(sh_irradiance_weight(8, n), 0.429043 * (0.48 * 0.48 - 0.6 * 0.6))
    assert_equal(sh_irradiance_weight(SH_COUNT, n), 0)


def test_new_harmonics_are_dark() raises:
    var sh = SphericalHarmonics3()
    for index in range(SH_COUNT):
        var c = sh.coefficient(index)
        assert_equal(c.x, 0)
        assert_equal(c.y, 0)
        assert_equal(c.z, 0)
    assert_equal(sh.get_irradiance_at(Vector3(0, 1, 0)).x, 0)


def test_a_coefficient_outside_zero_to_eight_is_refused() raises:
    var sh = SphericalHarmonics3()
    with assert_raises():
        _ = sh.coefficient(-1)
    with assert_raises():
        _ = sh.coefficient(SH_COUNT)
    with assert_raises():
        sh.set_coefficient(SH_COUNT, Vector3(1, 1, 1))
    with assert_raises():
        sh.set_coefficient(-1, Vector3(1, 1, 1))


def test_a_uniform_light_is_band_zero_alone() raises:
    # A white sky of radiance one everywhere projects to band zero alone,
    # sqrt(4 pi) = 3.5449; its irradiance is pi and its radiance one.
    var sh = SphericalHarmonics3()
    sh.set_coefficient(0, Vector3(3.5449077, 1.7724539, 0))
    for normal in [Vector3(0, 1, 0), Vector3(0, 0, -1), Vector3(0.6, 0, 0.8)]:
        var irradiance = sh.get_irradiance_at(normal)
        assert_almost_equal(irradiance.x, Float32(3.14159), atol=1e-3)
        assert_almost_equal(irradiance.y, Float32(1.570796), atol=1e-3)
        assert_equal(irradiance.z, 0)
        var radiance = sh.get_at(normal)
        assert_almost_equal(radiance.x, Float32(1), atol=1e-4)


def test_band_one_leans_the_light() raises:
    var sh = SphericalHarmonics3()
    sh.set_coefficient(0, Vector3(1, 1, 1))
    sh.set_coefficient(1, Vector3(0.5, 0.5, 0.5))
    var up = sh.get_irradiance_at(Vector3(0, 1, 0))
    var down = sh.get_irradiance_at(Vector3(0, -1, 0))
    _near(up.x, 0.886227 + 2 * 0.511664 * 0.5)
    _near(down.x, 0.886227 - 2 * 0.511664 * 0.5)
    _near(sh.get_at(Vector3(0, 1, 0)).y, 0.282095 + 0.488603 * 0.5)


def test_add_scale_and_lerp_act_on_every_coefficient() raises:
    var one = SphericalHarmonics3()
    var two = SphericalHarmonics3()
    for index in range(SH_COUNT):
        one.set_coefficient(index, Vector3(Float32(index), 1, 2))
        two.set_coefficient(index, Vector3(1, Float32(index), 0))
    var sum = one
    sum.add(two)
    assert_equal(sum.coefficient(4).x, 5)
    assert_equal(sum.coefficient(4).y, 5)
    var scaled = one
    scaled.add_scaled(two, 2)
    assert_equal(scaled.coefficient(3).y, 7)
    scaled.scale(0.5)
    assert_equal(scaled.coefficient(3).y, 3.5)
    var halfway = one
    halfway.lerp(two, 0.5)
    assert_equal(halfway.coefficient(8).x, 4.5)
    assert_equal(halfway.coefficient(8).z, 1)
    halfway.zero()
    assert_true(halfway == SphericalHarmonics3())
    assert_false(one == two)


def test_arrays_round_trip() raises:
    var sh = SphericalHarmonics3()
    sh.set_coefficient(7, Vector3(0.25, -0.5, 2))
    var numbers = sh.to_array()
    assert_equal(len(numbers), 27)
    assert_equal(numbers[22], -0.5)
    assert_true(sh_from_array(numbers) == sh)
    # An offset reads further in.
    var padded: List[Float32] = [9, 9]
    padded.extend(numbers^)
    assert_true(sh_from_array(padded, 2) == sh)


def test_too_few_numbers_are_refused() raises:
    var short = List[Float32](length=26, fill=0)
    with assert_raises():
        _ = sh_from_array(short)
    var enough = List[Float32](length=27, fill=0)
    with assert_raises():
        _ = sh_from_array(enough, 1)
    with assert_raises():
        _ = sh_from_array(enough, -1)


def test_finite_is_every_coefficient() raises:
    var sh = SphericalHarmonics3()
    assert_true(sh.is_finite())
    sh.set_coefficient(8, Vector3(0, 0, inf[DType.float32]()))
    assert_false(sh.is_finite())
    sh.set_coefficient(8, Vector3(nan[DType.float32](), 0, 0))
    assert_false(sh.is_finite())


def test_harmonics_write_their_numbers() raises:
    var sh = SphericalHarmonics3()
    sh.set_coefficient(0, Vector3(1, 2, 3))
    var text = String(sh)
    assert_true(text.startswith("SphericalHarmonics3(1.0, 2.0, 3.0, 0.0"))
    assert_true(text.endswith("0.0)"))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
