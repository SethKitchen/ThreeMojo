# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the temperature exponent, the `Float64` quantities and the
thermal and structural units of `units.si` and `units.temperature`."""

from std.math import inf, nan, pi
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)
from units.si import (
    Angle64,
    Area64,
    DEGREE64,
    FOOT64,
    INCH64,
    Energy64,
    HeatCapacity64,
    Scalar64,
    SpecificHeatCapacity64,
    ThermalExpansion64,
    CUBIC_METER_PER_SECOND,
    FOOT,
    Force64,
    HeatFlux64,
    JOULE,
    JOULE_PER_KELVIN,
    JOULE_PER_KILOGRAM_KELVIN,
    KILOGRAM,
    KILOGRAM_PER_SECOND,
    KILONEWTON,
    KILONEWTON_METER,
    KILONEWTON_PER_METER,
    KILOPASCAL,
    KILOWATT,
    KILOWATT_HOUR,
    Length,
    Length64,
    LineLoad64,
    METER,
    METER_TO_THE_FOURTH,
    Mass64,
    Moment64,
    NEWTON_METER,
    NEWTON_PER_METER,
    PER_KELVIN,
    Power64,
    SQUARE_METER,
    SQUARE_METER_KELVIN_PER_WATT,
    SecondMomentOfArea64,
    ThermalConductance64,
    ThermalConductivity64,
    ThermalResistance64,
    ThermalTransmittance64,
    WATT,
    WATT_PER_KELVIN,
    WATT_PER_METER_KELVIN,
    WATT_PER_SQUARE_METER,
    WATT_PER_SQUARE_METER_KELVIN,
)
from units.temperature import (
    CELSIUS,
    KELVIN,
    KELVIN_DIFFERENCE,
    Temperature,
    Temperature64,
    TemperatureDifference64,
)


def test_a_float64_unit_keeps_every_digit_of_its_factor() raises:
    # 0.3048 has no exact Float32. FOOT rounds it; FOOT64 keeps it.
    assert_equal(Length64(1.0, FOOT64).value, Float64(0.3048))
    assert_equal(Length64(1.0, INCH64).to(INCH64), 1.0)
    assert_equal(Length(1.0, FOOT).value, Float32(0.3048))
    assert_equal(Length64(1.0, FOOT).value, Float64(Float32(0.3048)))
    # A Float64 unit converts a Float32 quantity too.
    assert_equal(Length(1.0, FOOT64).value, Float32(0.3048))
    assert_equal(Angle64(180, DEGREE64).value, pi)


def test_cast_changes_the_float_type_and_keeps_the_dimension() raises:
    var wide = Length(2.0, METER).cast[DType.float64]()
    assert_equal(wide.value, Float64(2.0))
    var narrow = Length64(0.1, METER).cast[DType.float32]()
    assert_equal(narrow.value, Float32(0.1))


def test_float64_quantities_multiply_and_divide() raises:
    var side = Length64(3.0, METER)
    var area: Area64 = side * side
    assert_equal(area.to(SQUARE_METER), 9.0)
    var back: Length64 = area / side
    assert_equal(back.value, 3.0)
    assert_equal(area.sqrt().value, 3.0)


def test_a_temperature_difference_is_a_quantity() raises:
    var inside = Temperature64(20.0, CELSIUS)
    var outside = Temperature64(-5.0, CELSIUS)
    var drop: TemperatureDifference64 = inside - outside
    assert_almost_equal(drop.to(KELVIN_DIFFERENCE), 25.0, atol=1e-12)
    var warmed = outside + drop
    assert_almost_equal(warmed.to(CELSIUS), 20.0, atol=1e-12)
    assert_true(outside < inside)
    assert_false(inside < outside)


def test_fourier_law_gives_a_heat_flux() raises:
    # q = k dT / L: 0.8 W/(m K) over 0.2 m with 25 K across it.
    var k = ThermalConductivity64(0.8, WATT_PER_METER_KELVIN)
    var thickness = Length64(0.2, METER)
    var drop = TemperatureDifference64(25.0, KELVIN_DIFFERENCE)
    var flux: HeatFlux64 = k * drop / thickness
    assert_almost_equal(flux.to(WATT_PER_SQUARE_METER), 100.0, atol=1e-12)


def test_a_u_value_is_the_inverse_of_an_r_value() raises:
    var r = ThermalResistance64(2.5, SQUARE_METER_KELVIN_PER_WATT)
    var one = Area64(1.0, SQUARE_METER) / Area64(1.0, SQUARE_METER)
    var u: ThermalTransmittance64 = one / r
    assert_almost_equal(u.to(WATT_PER_SQUARE_METER_KELVIN), 0.4, atol=1e-15)
    var area = Area64(10.0, SQUARE_METER)
    var conductance: ThermalConductance64 = u * area
    assert_almost_equal(conductance.to(WATT_PER_KELVIN), 4.0, atol=1e-14)
    var drop = TemperatureDifference64(20.0, KELVIN_DIFFERENCE)
    var loss: Power64 = conductance * drop
    assert_almost_equal(loss.to(WATT), 80.0, atol=1e-12)
    assert_almost_equal(loss.to(KILOWATT), 0.08, atol=1e-15)


def test_heat_capacities() raises:
    # 2 kg of water at 4186 J/(kg K) store 8372 J per kelvin.
    var mass = Mass64(2.0, KILOGRAM)
    var water = SpecificHeatCapacity64(4186.0, JOULE_PER_KILOGRAM_KELVIN)
    var capacity: HeatCapacity64 = water * mass
    assert_equal(capacity.to(JOULE_PER_KELVIN), 8372.0)
    var drop = TemperatureDifference64(10.0, KELVIN_DIFFERENCE)
    var heat: Energy64 = capacity * drop
    assert_equal(heat.to(JOULE), 83720.0)
    # Steel grows 12e-6 of its length per kelvin.
    var alpha = ThermalExpansion64(12.0e-6, PER_KELVIN)
    var strain: Scalar64 = alpha * drop
    assert_almost_equal(strain.value, 1.2e-4, atol=1e-18)


def test_energy_units() raises:
    assert_equal(KILOWATT_HOUR.scale / JOULE.scale, 3.6e6)


def test_structural_units() raises:
    var load = LineLoad64(5.0, KILONEWTON_PER_METER)
    var span = Length64(4.0, METER)
    # A simply supported beam: M = w L^2 / 8.
    var moment: Moment64 = load * span * span
    assert_almost_equal(
        moment.scaled(0.125).to(KILONEWTON_METER), 10.0, atol=1e-12
    )
    assert_equal(moment.scaled(0.125).to(NEWTON_METER), 10000.0)
    var force: Force64 = load * span
    assert_equal(force.to(KILONEWTON), 20.0)
    assert_equal(load.to(NEWTON_PER_METER), 5000.0)
    var inertia = SecondMomentOfArea64(8.0e-5, METER_TO_THE_FOURTH)
    assert_equal(inertia.value, 8.0e-5)
    assert_equal(KILOPASCAL.scale, 1000.0)


def test_flow_units() raises:
    assert_equal(CUBIC_METER_PER_SECOND.scale, 1.0)
    assert_equal(KILOGRAM_PER_SECOND.scale, 1.0)


def test_a_temperature_is_valid_only_above_absolute_zero() raises:
    assert_true(Temperature(0.0, KELVIN).is_valid())
    assert_true(Temperature64(20.0, CELSIUS).is_valid())
    assert_false(Temperature(-1.0, KELVIN).is_valid())
    assert_false(Temperature(inf[DType.float32](), KELVIN).is_valid())
    assert_false(Temperature64(nan[DType.float64](), KELVIN).is_valid())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
