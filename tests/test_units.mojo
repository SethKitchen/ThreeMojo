# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `units.quantity` and `units.si`.

These cover what a quantity *does*. What it *refuses to do* cannot be tested
here — a mismatched unit is a compile error, so a test exercising one would
stop this file building. Those cases live in `tests/compile_fail/`, which the
`make compile-fail` target checks by asserting each file does not compile.
"""

from units.quantity import Quantity, Unit
from units.si import (
    Angle,
    Area,
    CENTIMETER,
    CUBIC_CENTIMETER,
    CUBIC_METER,
    DEGREE,
    Density,
    Duration,
    FOOT,
    GIGAPASCAL,
    GRAM,
    GRAM_PER_CUBIC_CENTIMETER,
    HOUR,
    INCH,
    KILOGRAM,
    KILOGRAM_PER_CUBIC_METER,
    KILOMETER,
    Length,
    MEGAPASCAL,
    METER,
    METER_PER_SECOND_SQUARED,
    MILE,
    MILLIMETER,
    MINUTE,
    Mass,
    NEWTON,
    PASCAL,
    POUND,
    POUND_FORCE,
    Pressure,
    RADIAN,
    SECOND,
    SQUARE_FOOT,
    SQUARE_METER,
    STANDARD_GRAVITY,
    Scalar,
    TURN,
    Velocity,
    Volume,
    YARD,
)
from std.sys import size_of
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)


def test_canonical_construction_needs_no_unit() raises:
    # The bare constructor means "already in canonical units".
    assert_equal(Length(2.5).value, Float32(2.5))


def test_meter_is_the_canonical_length() raises:
    assert_equal(Length(1.0, METER).value, Float32(1.0))


def test_a_meter_in_imperial_units() raises:
    var height = Length(1.0, METER)
    assert_almost_equal(height.to(FOOT), Float32(3.2808399))
    assert_almost_equal(height.to(INCH), Float32(39.37008))
    assert_almost_equal(height.to(YARD), Float32(1.0936133))


def test_imperial_definitions_are_exact() raises:
    # Defined by international agreement, not measured.
    assert_equal(Length(1.0, YARD).value, Float32(0.9144))
    assert_equal(Length(1.0, FOOT).value, Float32(0.3048))
    assert_equal(Length(1.0, INCH).value, Float32(0.0254))


def test_twelve_inches_make_a_foot() raises:
    assert_almost_equal(Length(12.0, INCH).to(FOOT), Float32(1.0))


def test_metric_prefixes() raises:
    assert_equal(Length(1.0, KILOMETER).value, Float32(1000.0))
    assert_almost_equal(Length(1.0, METER).to(CENTIMETER), Float32(100.0))
    assert_almost_equal(Length(1.0, METER).to(MILLIMETER), Float32(1000.0))


def test_a_mile_in_feet() raises:
    assert_almost_equal(Length(1.0, MILE).to(FOOT), Float32(5280.0))


def test_conversion_round_trips() raises:
    var original = Float32(7.3)
    assert_almost_equal(Length(original, FOOT).to(FOOT), original)


def test_units_can_be_mixed_in_one_sum() raises:
    # Both operands are meters internally, so this is just a float add.
    var total = Length(1.0, METER) + Length(1.0, FOOT)
    assert_almost_equal(total.value, Float32(1.3048))
    assert_almost_equal(total.to(FOOT), Float32(4.2808399))


def test_subtraction() raises:
    var remaining = Length(1.0, METER) - Length(30.0, CENTIMETER)
    assert_almost_equal(remaining.value, Float32(0.7))


def test_negation_and_absolute_value() raises:
    assert_equal((-Length(2.0)).value, Float32(-2.0))
    assert_equal(abs(Length(-2.0)).value, Float32(2.0))
    assert_equal(abs(Length(2.0)).value, Float32(2.0))


def test_scaling_by_a_plain_number_keeps_the_dimension() raises:
    var tripled = Length(2.0, METER).scaled(3.0)
    assert_equal(tripled.value, Float32(6.0))
    assert_equal(tripled.length, 1)


def test_multiplying_lengths_gives_an_area() raises:
    var area = Length(3.0, METER) * Length(4.0, METER)
    assert_equal(area.value, Float32(12.0))
    assert_equal(area.length, 2)
    assert_equal(area.time, 0)


def test_area_converts_to_square_feet() raises:
    var area = Length(1.0, METER) * Length(1.0, METER)
    assert_almost_equal(area.to(SQUARE_FOOT), Float32(10.76391))


def test_multiplying_three_lengths_gives_a_volume() raises:
    var volume = Length(2.0) * Length(3.0) * Length(4.0)
    assert_equal(volume.value, Float32(24.0))
    assert_equal(volume.length, 3)


def test_dividing_length_by_time_gives_velocity() raises:
    var speed = Length(100.0, METER) / Duration(10.0, SECOND)
    assert_equal(speed.value, Float32(10.0))
    assert_equal(speed.length, 1)
    assert_equal(speed.time, -1)


def test_velocity_over_time_gives_acceleration() raises:
    var speed = Length(10.0) / Duration(1.0)
    var rate = speed / Duration(2.0)
    assert_equal(rate.value, Float32(5.0))
    assert_equal(rate.length, 1)
    assert_equal(rate.time, -2)


def test_dividing_equal_dimensions_gives_a_scalar() raises:
    var ratio = Length(6.0) / Length(2.0)
    assert_equal(ratio.value, Float32(3.0))
    assert_equal(ratio.length, 0)
    assert_equal(ratio.time, 0)


def test_square_root_of_an_area_is_a_length() raises:
    var side = (Length(3.0) * Length(3.0)).sqrt()
    assert_almost_equal(side.value, Float32(3.0))
    assert_equal(side.length, 1)


def test_square_root_of_a_scalar_stays_a_scalar() raises:
    assert_almost_equal(Scalar(9.0).sqrt().value, Float32(3.0))


def test_mass_units() raises:
    assert_equal(Mass(1.0, KILOGRAM).value, Float32(1.0))
    assert_almost_equal(Mass(1.0, KILOGRAM).to(GRAM), Float32(1000.0))
    assert_equal(Mass(1.0, POUND).value, Float32(0.45359237))


def test_time_units() raises:
    assert_almost_equal(Duration(1.0, HOUR).to(MINUTE), Float32(60.0))
    assert_almost_equal(Duration(1.0, MINUTE).to(SECOND), Float32(60.0))


def test_degrees_and_radians() raises:
    assert_almost_equal(Angle(180.0, DEGREE).to(RADIAN), Float32(3.1415927))
    assert_almost_equal(Angle(90.0, DEGREE).to(RADIAN), Float32(1.5707964))
    assert_almost_equal(Angle(1.0, TURN).to(DEGREE), Float32(360.0))


def test_radian_is_the_canonical_angle() raises:
    assert_equal(Angle(1.0, RADIAN).value, Float32(1.0))


def test_comparisons_use_the_canonical_value() raises:
    # A foot is shorter than a meter however each was written.
    assert_true(Length(1.0, FOOT) < Length(1.0, METER))
    assert_true(Length(1.0, METER) > Length(1.0, FOOT))
    assert_true(Length(12.0, INCH) <= Length(1.0, FOOT))
    assert_true(Length(12.0, INCH) >= Length(1.0, FOOT))


def test_equality_across_units() raises:
    assert_true(Length(1.0, YARD) == Length(3.0, FOOT))
    assert_false(Length(1.0, YARD) != Length(3.0, FOOT))
    assert_true(Length(1.0, METER) != Length(1.0, FOOT))


def test_units_expose_their_symbol() raises:
    assert_equal(METER.symbol, "m")
    assert_equal(FOOT.symbol, "ft")
    assert_equal(DEGREE.symbol, "deg")


def test_dimension_exponents_are_readable() raises:
    assert_equal(Length(1.0).length, 1)
    assert_equal(Mass(1.0).mass, 1)
    assert_equal(Duration(1.0).time, 1)
    assert_equal(Angle(1.0).angle, 1)
    assert_equal(Scalar(1.0).length, 0)


def test_a_quantity_is_only_as_big_as_its_float() raises:
    # The exponents live in the type, so nothing is stored for them.
    assert_equal(size_of[Length](), size_of[Float32]())
    assert_equal(size_of[Volume](), size_of[Float32]())
    assert_equal(size_of[Velocity](), size_of[Float32]())


def test_a_cubic_centimeter_is_a_millionth_of_a_cubic_meter() raises:
    var milliliter = Volume(1.0, CUBIC_CENTIMETER)
    assert_almost_equal(milliliter.to(CUBIC_METER), Float32(1.0e-6))


def test_one_gram_per_cubic_centimeter_is_a_thousand_kilograms_per_cubic_meter() raises:
    var water = Density(1.0, GRAM_PER_CUBIC_CENTIMETER)
    assert_equal(water.to(KILOGRAM_PER_CUBIC_METER), Float32(1000.0))


def test_standard_gravity_is_the_conventional_value() raises:
    assert_almost_equal(STANDARD_GRAVITY.value, Float32(9.80665))
    assert_almost_equal(
        STANDARD_GRAVITY.to(METER_PER_SECOND_SQUARED), Float32(9.80665)
    )


def test_weight_is_mass_times_gravity() raises:
    var mass = Mass(2.0, KILOGRAM)
    var weight = mass * STANDARD_GRAVITY
    assert_equal(weight.length, 1)
    assert_equal(weight.mass, 1)
    assert_equal(weight.time, -2)
    assert_almost_equal(weight.to(NEWTON), Float32(19.6133))


def test_a_pound_force_is_standard_gravity_on_an_international_pound() raises:
    var weight = Mass(1.0, POUND) * STANDARD_GRAVITY
    assert_almost_equal(
        weight.to(POUND_FORCE), Float32(1.0), atol=Float64(1e-5)
    )


def test_gigapascal_and_megapascal() raises:
    var stiff = Pressure(17.9, GIGAPASCAL)
    assert_almost_equal(stiff.to(PASCAL), Float32(1.79e10))
    assert_almost_equal(Pressure(400.0, MEGAPASCAL).to(PASCAL), Float32(4.0e8))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
