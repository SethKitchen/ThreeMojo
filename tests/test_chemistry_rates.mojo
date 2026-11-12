# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the rates and transport of `extensions.chemistry`.

References:

- Callister, "Materials Science and Engineering", the carburizing
  example: a 0.25 wt% C steel at 950 degC with 1.20 wt% at the surface
  reaches 0.80 wt% at 0.5 mm in about 7.1 h, with D = 1.6e-11 m^2/s.
- CRC Handbook: magnesium's vapor pressure is 1 kPa at 971 K.
- The closed forms of Levenspiel's shrinking-core model, one resistance
  at a time.
"""

from std.math import exp, inf, log, nan, pi, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from extensions.chemistry.catalog import magnesium, magnesium_gas
from extensions.chemistry.kinetics import (
    Arrhenius,
    Concentration64,
    Diffusivity64,
    RateAtLeast,
    SQUARE_METER_PER_SECOND,
    ShrinkingCore,
)
from extensions.chemistry.quantities import (
    GRAM_PER_MOLE,
    KILOJOULE_PER_MOLE,
    MolarEnergy64,
    MolarMass64,
)
from extensions.chemistry.transport import (
    Diffusivity,
    MassFlux64,
    biot,
    case_depth,
    evaporation_flux,
    evaporation_time,
    heating_time,
    time_to_depth,
    vapor_pressure,
)
from extensions.chemistry.window import met_intervals
from units.si import (
    Area64,
    Duration64,
    Frequency64,
    HOUR,
    Length64,
    MILLIMETER,
    Mass64,
    Pressure64,
    SpecificHeatCapacity64,
    ThermalConductivity64,
    ThermalTransmittance64,
    Velocity64,
)
from units.temperature import Temperature64

comptime R = 8.31446261815324
comptime NAN = nan[DType.float64]()


def _t(kelvin: Float64) -> Temperature64:
    return Temperature64(kelvin)


def _law() -> Arrhenius:
    return Arrhenius(Frequency64(1e10), MolarEnergy64(150, KILOJOULE_PER_MOLE))


# --- Arrhenius --------------------------------------------------------------


def test_arrhenius() raises:
    var law = _law()
    var k = law.rate(_t(1000)).value
    assert_almost_equal(k, 1e10 * exp(-150000 / (R * 1000)), atol=1e-12)
    assert_almost_equal(
        law.temperature_for(Frequency64(k)).kelvin, 1000.0, atol=1e-9
    )
    assert_almost_equal(law.half_life(_t(1000)).value, log(2.0) / k, atol=1e-9)
    with assert_raises(contains="pre-exponential"):
        Arrhenius(Frequency64(0), MolarEnergy64(1)).check()
    with assert_raises(contains="pre-exponential"):
        Arrhenius(Frequency64(NAN), MolarEnergy64(1)).check()
    with assert_raises(contains="activation energy"):
        Arrhenius(Frequency64(1), MolarEnergy64(-1)).check()
    with assert_raises(contains="activation energy"):
        Arrhenius(Frequency64(1), MolarEnergy64(NAN)).check()
    with assert_raises(contains="above absolute zero"):
        _ = law.rate(_t(0))
    with assert_raises(contains="does not vary"):
        _ = Arrhenius(Frequency64(1), MolarEnergy64(0)).temperature_for(
            Frequency64(0.5)
        )
    with assert_raises(contains="rate must be finite"):
        _ = law.temperature_for(Frequency64(0))
    with assert_raises(contains="below the pre-exponential"):
        _ = law.temperature_for(Frequency64(1e10))


def test_rate_constraint() raises:
    var law = _law()
    var need = RateAtLeast(law, Frequency64(1e-3))
    var t_min = law.temperature_for(Frequency64(1e-3))
    assert_true(need.holds(_t(t_min.kelvin + 1), Pressure64(1e5)))
    assert_false(need.holds(_t(t_min.kelvin - 1), Pressure64(1e5)))
    var met = met_intervals(need, _t(500), _t(1500), Pressure64(1e5))
    assert_equal(len(met), 1)
    assert_almost_equal(met[0].low.kelvin, t_min.kelvin, atol=1e-6)
    var fast = RateAtLeast(
        Arrhenius(Frequency64(2000), MolarEnergy64(0)), Frequency64(1e-3)
    )
    assert_equal(
        fast.describe(_t(1000), Pressure64(1e5)),
        "k 2.000e3 1/s of 1.000e-3 needed",
    )
    var slow = RateAtLeast(
        Arrhenius(Frequency64(0.002), MolarEnergy64(0)), Frequency64(1)
    )
    assert_equal(
        slow.describe(_t(1000), Pressure64(1e5)),
        "k 2.000e-3 1/s of 1.000e0 needed",
    )
    with assert_raises(contains="pre-exponential"):
        _ = RateAtLeast(
            Arrhenius(Frequency64(0), MolarEnergy64(1)), Frequency64(1)
        )
    with assert_raises(contains="rate must be finite"):
        _ = RateAtLeast(law, Frequency64(-1))


# --- shrinking core ---------------------------------------------------------


def test_shrinking_core_one_resistance_at_a_time() raises:
    var reaction = ShrinkingCore(Duration64(0), Duration64(0), Duration64(100))
    # Reaction control: X = 1 - (1 - t / tau)^3.
    var x = reaction.conversion_at(Duration64(50))
    assert_almost_equal(x, 1 - 0.5**3, atol=1e-9)
    var film = ShrinkingCore(Duration64(100), Duration64(0), Duration64(0))
    assert_almost_equal(film.conversion_at(Duration64(30)), 0.3, atol=1e-9)
    var ash = ShrinkingCore(Duration64(0), Duration64(100), Duration64(0))
    var left = 0.5
    var expected = 100 * (1 - 3 * left ** (2.0 / 3.0) + 2 * left)
    assert_almost_equal(ash.time_to(0.5).value, expected, atol=1e-9)
    # In series, the complete-conversion times add.
    var all = ShrinkingCore(Duration64(10), Duration64(20), Duration64(30))
    assert_almost_equal(all.time_to(1).value, 60.0, atol=1e-12)
    assert_almost_equal(all.conversion_at(Duration64(60)), 1.0, atol=0)
    assert_almost_equal(all.conversion_at(Duration64(0)), 0.0, atol=1e-12)


def test_shrinking_core_from_properties() raises:
    var core = ShrinkingCore.from_properties(
        Length64(1e-3),
        Concentration64(20000),
        Concentration64(10),
        1,
        Velocity64(0.1),
        Diffusivity64(1e-6),
        Velocity64(0.01),
    )
    # rho R / (b C) = 20000 * 1e-3 / 10 = 2 s m/m.
    assert_almost_equal(core.film.value, 2.0 / 0.3, atol=1e-12)
    assert_almost_equal(core.ash.value, 2.0 * 1e-3 / 6e-6, atol=1e-9)
    assert_almost_equal(core.reaction.value, 200.0, atol=1e-12)
    with assert_raises(contains="property must be positive"):
        _ = ShrinkingCore.from_properties(
            Length64(0),
            Concentration64(1),
            Concentration64(1),
            1,
            Velocity64(1),
            Diffusivity64(1),
            Velocity64(1),
        )


def test_shrinking_core_refuses_bad_values() raises:
    with assert_raises(contains="finite, not negative"):
        _ = ShrinkingCore(Duration64(-1), Duration64(0), Duration64(1))
    with assert_raises(contains="finite, not negative"):
        _ = ShrinkingCore(Duration64(NAN), Duration64(0), Duration64(1))
    with assert_raises(contains="needs a resistance"):
        _ = ShrinkingCore(Duration64(0), Duration64(0), Duration64(0))
    var core = ShrinkingCore(Duration64(1), Duration64(1), Duration64(1))
    with assert_raises(contains="from 0 to 1"):
        _ = core.time_to(-0.1)
    with assert_raises(contains="from 0 to 1"):
        _ = core.time_to(1.1)
    with assert_raises(contains="finite and not negative"):
        _ = core.conversion_at(Duration64(-1))
    with assert_raises(contains="finite and not negative"):
        _ = core.conversion_at(Duration64(NAN))


# --- evaporation ------------------------------------------------------------


def test_vapor_pressure_and_evaporation() raises:
    var p = vapor_pressure(magnesium(), magnesium_gas(), _t(971))
    assert_almost_equal(p.value / 1000, 1.0, atol=0.1)
    var m = MolarMass64(24.305, GRAM_PER_MOLE)
    var t = _t(1000)
    var p_sat = vapor_pressure(magnesium(), magnesium_gas(), t)
    var flux = evaporation_flux(p_sat, Pressure64(0), m, t)
    var expected = p_sat.value * sqrt(0.024305 / (2 * pi * R * 1000))
    assert_almost_equal(flux.value, expected, atol=1e-12)
    # A thin vapor over the surface slows it; a dense one condenses.
    var half = evaporation_flux(p_sat, Pressure64(0), m, t, 0.5)
    assert_almost_equal(half.value, expected / 2, atol=1e-12)
    var back = evaporation_flux(Pressure64(1), Pressure64(2), m, t)
    assert_true(back.value < 0)
    var time = evaporation_time(Mass64(0.1), Area64(0.01), flux)
    assert_almost_equal(time.value, 0.1 / (0.01 * expected), atol=1e-6)
    with assert_raises(contains="pressure must be finite"):
        _ = evaporation_flux(Pressure64(-1), Pressure64(0), m, t)
    with assert_raises(contains="pressure must be finite"):
        _ = evaporation_flux(Pressure64(1), Pressure64(NAN), m, t)
    with assert_raises(contains="molar mass"):
        _ = evaporation_flux(Pressure64(1), Pressure64(0), MolarMass64(0), t)
    with assert_raises(contains="temperature must be positive"):
        _ = evaporation_flux(Pressure64(1), Pressure64(0), m, _t(0))
    with assert_raises(contains="coefficient"):
        _ = evaporation_flux(Pressure64(1), Pressure64(0), m, t, 0)
    with assert_raises(contains="coefficient"):
        _ = evaporation_flux(Pressure64(1), Pressure64(0), m, t, 1.5)
    with assert_raises(contains="mass must be finite"):
        _ = evaporation_time(Mass64(-1), Area64(1), flux)
    with assert_raises(contains="mass must be finite"):
        _ = evaporation_time(Mass64(NAN), Area64(1), flux)
    with assert_raises(contains="area must be"):
        _ = evaporation_time(Mass64(1), Area64(0), flux)
    with assert_raises(contains="area must be"):
        _ = evaporation_time(Mass64(1), Area64(inf[DType.float64]()), flux)
    with assert_raises(contains="flux must be"):
        _ = evaporation_time(Mass64(1), Area64(1), MassFlux64(0))


# --- diffusion --------------------------------------------------------------


def test_callister_carburizing() raises:
    var d = Diffusivity64(1.6e-11, SQUARE_METER_PER_SECOND)
    var ratio = (0.80 - 0.25) / (1.20 - 0.25)
    var t = time_to_depth(d, Length64(0.5, MILLIMETER), ratio)
    # The book reads z = 0.392 from a table of erf and gets 7.1 h. The
    # exact inverse gives 7.05 h.
    assert_almost_equal(t.to(HOUR), 7.1, atol=0.1)
    var depth = case_depth(d, t, ratio)
    assert_almost_equal(depth.to(MILLIMETER), 0.5, atol=1e-9)


def test_diffusivity() raises:
    # Carbon in austenite: D0 = 2.3e-5 m^2/s and Q = 148 kJ/mol.
    var carbon = Diffusivity(
        Diffusivity64(2.3e-5), MolarEnergy64(148, KILOJOULE_PER_MOLE)
    )
    var d = carbon.at(_t(1223.15)).value
    assert_almost_equal(d, 2.3e-5 * exp(-148000 / (R * 1223.15)), atol=1e-20)
    with assert_raises(contains="D0 must be"):
        _ = Diffusivity(Diffusivity64(0), MolarEnergy64(1)).at(_t(1000))
    with assert_raises(contains="activation energy"):
        _ = Diffusivity(Diffusivity64(1), MolarEnergy64(-1)).at(_t(1000))
    with assert_raises(contains="activation energy"):
        _ = Diffusivity(Diffusivity64(1), MolarEnergy64(NAN)).at(_t(1000))
    with assert_raises(contains="temperature must be positive"):
        _ = carbon.at(_t(0))
    var good = Diffusivity64(1e-11)
    with assert_raises(contains="diffusivity must be"):
        _ = case_depth(Diffusivity64(0), Duration64(1), 0.5)
    with assert_raises(contains="time must be"):
        _ = case_depth(good, Duration64(0), 0.5)
    with assert_raises(contains="ratio must lie"):
        _ = case_depth(good, Duration64(1), 0)
    with assert_raises(contains="ratio must lie"):
        _ = case_depth(good, Duration64(1), 1)
    with assert_raises(contains="diffusivity must be"):
        _ = time_to_depth(Diffusivity64(0), Length64(1), 0.5)
    with assert_raises(contains="depth must be"):
        _ = time_to_depth(good, Length64(0), 0.5)


# --- heating ----------------------------------------------------------------


def test_heating() raises:
    var h = ThermalTransmittance64(50)
    var c = SpecificHeatCapacity64(500)
    # m c / (h A) = 1000 s; ln(1000 / 100) to go from 300 K to 1200 K in a
    # 1300 K furnace.
    var t = heating_time(
        Mass64(1), c, h, Area64(0.01), _t(300), _t(1300), _t(1200)
    )
    assert_almost_equal(t.value, 1000 * log(10.0), atol=1e-9)
    var cooling = heating_time(
        Mass64(1), c, h, Area64(0.01), _t(1300), _t(300), _t(400)
    )
    assert_almost_equal(cooling.value, 1000 * log(10.0), atol=1e-9)
    with assert_raises(contains="between the start and the furnace"):
        _ = heating_time(
            Mass64(1), c, h, Area64(1), _t(300), _t(1300), _t(1400)
        )
    with assert_raises(contains="between the start and the furnace"):
        _ = heating_time(Mass64(1), c, h, Area64(1), _t(300), _t(1300), _t(250))
    with assert_raises(contains="mass must be"):
        _ = heating_time(Mass64(0), c, h, Area64(1), _t(300), _t(1300), _t(400))
    with assert_raises(contains="specific heat"):
        _ = heating_time(
            Mass64(1),
            SpecificHeatCapacity64(0),
            h,
            Area64(1),
            _t(300),
            _t(1300),
            _t(400),
        )
    with assert_raises(contains="coefficient must be"):
        _ = heating_time(
            Mass64(1),
            c,
            ThermalTransmittance64(0),
            Area64(1),
            _t(300),
            _t(1300),
            _t(400),
        )
    with assert_raises(contains="area must be"):
        _ = heating_time(Mass64(1), c, h, Area64(0), _t(300), _t(1300), _t(400))
    var k = ThermalConductivity64(40)
    assert_almost_equal(biot(h, Length64(0.01), k), 50 * 0.01 / 40, atol=1e-15)
    with assert_raises(contains="coefficient must be"):
        _ = biot(ThermalTransmittance64(0), Length64(1), k)
    with assert_raises(contains="length must be"):
        _ = biot(h, Length64(0), k)
    with assert_raises(contains="conductivity must be"):
        _ = biot(h, Length64(1), ThermalConductivity64(0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
