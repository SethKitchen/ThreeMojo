# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for diamond crystal growth: the HPHT and microwave plasma CVD
processes of `extensions.chemistry.processes`, and the cost model of
`extensions.chemistry.production`.

References, independent of the NASA data the modules read:

- Berman and Simon (1955) put the graphite-diamond line at
  P = 7.1 kbar + 0.027 kbar/K T, for T above about 1200 K. The line of
  Kennedy and Kennedy (1976) lies within 0.3 GPa of it from 1100 to
  1625 degC.
- Temperature-gradient growth from Fe-Ni-C runs at 5.5 to 6.0 GPa and
  1360 to 1600 degC (Mu et al., CrystEngComm 2021).
- The metric carat is 200 mg.
- The costs of the example runs are checked by hand arithmetic.
"""

from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from extensions.chemistry.catalog import diamond, graphite
from extensions.chemistry.processes.hpht import (
    FE_NI_EUTECTIC,
    HPHT_PRESSURE,
    diamond_pressure,
    graphite_temperature,
    hpht_growth,
    hpht_run,
)
from extensions.chemistry.processes.mpcvd import (
    mpcvd_run,
    plasma_hydrogen,
    seed_growth,
)
from extensions.chemistry.production import (
    CARAT,
    DIAMOND_DENSITY,
    EnergyPrice64,
    GrowthRun,
    MICROMETER_PER_HOUR,
    MILLIGRAM_PER_HOUR,
    MassPrice64,
    MassRate64,
    Money64,
    PER_CARAT,
    PER_HOUR,
    PER_KILOWATT_HOUR,
    TimePrice64,
    cost_floor,
    cost_report,
    growth_for_price,
    layer_rate,
    run_cost,
)
from extensions.chemistry.quantities import TORR
from extensions.chemistry.reaction import Reaction, product, reactant
from extensions.chemistry.step import Step, operating_window, report, unmet
from extensions.chemistry.window import Interval, met_intervals
from units.si import (
    Area64,
    Density64,
    Duration64,
    Energy64,
    GIGAPASCAL,
    GRAM,
    HOUR,
    KILOWATT,
    KILOWATT_HOUR,
    Mass64,
    Power64,
    Pressure64,
    Velocity64,
)
from units.temperature import CELSIUS, Temperature64

comptime NAN = nan[DType.float64]()
comptime INF = inf[DType.float64]()


def _window(step: Step) raises -> Interval:
    """Return the single interval of a step's window."""
    var w = operating_window(step)
    assert_equal(len(w), 1)
    return w[0]


def _electricity() -> EnergyPrice64:
    return EnergyPrice64(0.10, PER_KILOWATT_HOUR)


def _run(
    growth: Float64 = 60,
    turnaround: Float64 = 4,
    power: Float64 = 15,
    crystals: Int = 12,
    rate: Float64 = 3,
    kept: Float64 = 0.35,
    consumables: Float64 = 150,
    equipment: Float64 = 8,
) raises -> GrowthRun:
    """Return a run; each argument in hours, kW, mg/h or money."""
    return GrowthRun(
        "test run",
        Duration64(growth, HOUR),
        Duration64(turnaround, HOUR),
        Power64(power, KILOWATT),
        crystals,
        MassRate64(rate, MILLIGRAM_PER_HOUR),
        kept,
        Money64(consumables),
        TimePrice64(equipment, PER_HOUR),
    )


# --- the graphite-diamond line ----------------------------------------------


def test_kennedy_line() raises:
    # 19.4 kbar + 1504 / 40 kbar = 57 kbar.
    assert_almost_equal(
        graphite_temperature(HPHT_PRESSURE).to(CELSIUS), 1504.0, atol=1e-9
    )
    assert_almost_equal(
        diamond_pressure(Temperature64(1504, CELSIUS)).to(GIGAPASCAL),
        5.7,
        atol=1e-12,
    )
    # The two functions are inverses over the measured range.
    for c in range(1100, 1626, 25):
        var t = Temperature64(Float64(c), CELSIUS)
        var back = graphite_temperature(diamond_pressure(t))
        assert_almost_equal(back.kelvin, t.kelvin, atol=1e-9)
        # Berman and Simon (1955), an independent measurement.
        var berman = (7.1 + 0.027 * t.kelvin) * 1e8
        assert_true(abs(diamond_pressure(t).value - berman) < 0.3e9)


def test_kennedy_line_refuses_extrapolation() raises:
    with assert_raises(contains="1100-1625"):
        _ = diamond_pressure(Temperature64(1099, CELSIUS))
    with assert_raises(contains="1100-1625"):
        _ = diamond_pressure(Temperature64(1626, CELSIUS))
    with assert_raises(contains="4.69-6.0"):
        _ = graphite_temperature(Pressure64(4.6, GIGAPASCAL))
    with assert_raises(contains="4.69-6.0"):
        _ = graphite_temperature(Pressure64(6.1, GIGAPASCAL))
    with assert_raises(contains="finite"):
        _ = graphite_temperature(Pressure64(NAN))


def test_builtin_data_puts_the_line_too_hot() raises:
    # The data's equal heat capacities and rigid solids put the balance
    # near 2625 K at 5.7 GPa, far above the measured 1777 K.
    var change = Reaction([reactant(graphite()), product(diamond())])
    var computed = change.equilibrium_temperature(
        Temperature64(1300), Temperature64(4000), HPHT_PRESSURE
    )
    assert_almost_equal(computed.kelvin, 2625.0, atol=2.0)
    assert_true(computed.kelvin > graphite_temperature(HPHT_PRESSURE).kelvin)


# --- HPHT growth ------------------------------------------------------------


def test_hpht_window() raises:
    var step = hpht_growth()
    var w = _window(step)
    # From the Fe-Ni-C eutectic to the graphite-diamond line.
    assert_almost_equal(w.low.kelvin, FE_NI_EUTECTIC.kelvin, atol=1e-6)
    assert_almost_equal(w.high.to(CELSIUS), 1504.0, atol=1e-6)
    # Inside the 1360 to 1600 degC of temperature-gradient practice.
    assert_true(w.low.to(CELSIUS) > 1360 and w.high.to(CELSIUS) < 1600)
    assert_equal(unmet(step), 0)
    # A cell that is too cold leaves the solvent solid.
    step.planned = Temperature64(1350, CELSIUS)
    assert_equal(unmet(step), 1)
    # A cell that is too hot grows graphite.
    step.planned = Temperature64(1550, CELSIUS)
    assert_equal(unmet(step), 1)
    var text = report(hpht_growth())
    assert_true("Kennedy and Kennedy (1976)" in text)
    assert_true("pressure vessel" in text)
    assert_true("Fact: graphite -> diamond" in text)


# --- microwave plasma CVD ---------------------------------------------------


def test_seed_growth_window() raises:
    var step = seed_growth()
    var w = _window(step)
    assert_almost_equal(w.low.to(CELSIUS), 700.0, atol=1e-6)
    assert_almost_equal(w.high.to(CELSIUS), 1200.0, atol=1e-6)
    assert_equal(unmet(step), 0)
    # 6 % methane at 200 Torr can deposit diamond well below 700 degC.
    var deposit = met_intervals(
        step.requirements[0], step.low, step.high, step.pressure
    )
    assert_true(deposit[0].low.to(CELSIUS) < 700)
    # Diamond is metastable at 200 Torr: graphite does not turn to it.
    var change = step.facts[0].delta_g(step.planned, step.pressure)
    assert_true(change.value > 0)
    # Outside 100 to 300 Torr, one pressure bound fails.
    step.pressure = Pressure64(50, TORR)
    assert_equal(unmet(step), 1)
    step.pressure = Pressure64(400, TORR)
    assert_equal(unmet(step), 1)
    assert_true("Yan et al. (2002)" in report(seed_growth()))


def test_plasma_needs_more_heat_than_a_filament() raises:
    var w = _window(plasma_hydrogen())
    # 5 % atoms at 200 Torr needs about 2500 K of gas.
    assert_true(w.low.kelvin > 2400 and w.low.kelvin < 2650)
    assert_almost_equal(w.high.kelvin, 5000.0, atol=1e-6)
    assert_equal(unmet(plasma_hydrogen()), 0)


# --- money and prices -------------------------------------------------------


def test_prices() raises:
    var e = _electricity()
    assert_almost_equal(e.to(PER_KILOWATT_HOUR), 0.10, atol=1e-15)
    # Ten kilowatt-hours at 0.10 cost 1.
    assert_almost_equal(
        e.times(Energy64(10, KILOWATT_HOUR)).value, 1.0, atol=1e-12
    )
    assert_almost_equal(
        TimePrice64(8, PER_HOUR).times(Duration64(2, HOUR)).value,
        16.0,
        atol=1e-12,
    )
    assert_almost_equal(
        MassPrice64(100, PER_CARAT).times(Mass64(1, CARAT)).value,
        100.0,
        atol=1e-9,
    )
    assert_almost_equal(TimePrice64(8, PER_HOUR).to(PER_HOUR), 8.0, atol=1e-12)
    assert_almost_equal((Money64(1.5) + Money64(2)).value, 3.5)
    assert_almost_equal(Money64(2).scaled(3).value, 6.0)
    # The metric carat is 200 mg.
    assert_almost_equal(Mass64(1, CARAT).to(GRAM), 0.2, atol=1e-15)


def test_layer_rate() raises:
    # 10 um/h on 7 mm by 7 mm: 1e-5 m * 4.9e-5 m^2 * 3515 kg/m^3 per hour.
    var rate = layer_rate(Velocity64(10, MICROMETER_PER_HOUR), Area64(49e-6))
    assert_almost_equal(rate.to(MILLIGRAM_PER_HOUR), 1.72235, atol=1e-9)
    var silicon = layer_rate(
        Velocity64(1, MICROMETER_PER_HOUR), Area64(1), Density64(2329)
    )
    # Another density: silicon, 2329 kg/m^3, on one square meter.
    assert_almost_equal(silicon.value, 2329 * 1e-6 / 3600, atol=1e-18)
    assert_almost_equal(DIAMOND_DENSITY.value, 3515.0)
    with assert_raises(contains="growth rate"):
        _ = layer_rate(Velocity64(0), Area64(1))
    with assert_raises(contains="growth rate"):
        _ = layer_rate(Velocity64(INF), Area64(1))
    with assert_raises(contains="area"):
        _ = layer_rate(Velocity64(1), Area64(-1))
    with assert_raises(contains="density"):
        _ = layer_rate(Velocity64(1), Area64(1), Density64(NAN))


# --- runs and their cost ----------------------------------------------------


def test_run_refuses_bad_values() raises:
    with assert_raises(contains="growth time"):
        _ = _run(growth=0)
    with assert_raises(contains="growth time"):
        _ = _run(growth=INF)
    with assert_raises(contains="turnaround"):
        _ = _run(turnaround=-1)
    with assert_raises(contains="turnaround"):
        _ = _run(turnaround=NAN)
    with assert_raises(contains="power"):
        _ = _run(power=-1)
    with assert_raises(contains="one crystal"):
        _ = _run(crystals=0)
    with assert_raises(contains="growth rate"):
        _ = _run(rate=-3)
    with assert_raises(contains="kept share"):
        _ = _run(kept=0)
    with assert_raises(contains="kept share"):
        _ = _run(kept=1.01)
    with assert_raises(contains="kept share"):
        _ = _run(kept=NAN)
    with assert_raises(contains="Consumables"):
        _ = _run(consumables=-1)
    with assert_raises(contains="equipment"):
        _ = _run(equipment=INF)
    # A run may keep all of its mass, and need no power or turnaround.
    _ = _run(kept=1, power=0, turnaround=0)


def test_run_cost() raises:
    var run = _run()
    # 12 crystals * 3 mg/h * 60 h = 2160 mg = 10.8 ct; 35 % kept.
    assert_almost_equal(run.grown_mass().to(CARAT), 10.8, atol=1e-9)
    assert_almost_equal(run.kept_mass().to(CARAT), 3.78, atol=1e-9)
    assert_almost_equal(run.energy().to(KILOWATT_HOUR), 900.0, atol=1e-9)
    # 3.78 ct over 64 h of press time.
    assert_almost_equal(
        run.output().value * 3600 / CARAT.scale, 3.78 / 64, atol=1e-12
    )
    var cost = run_cost(run, _electricity())
    assert_almost_equal(cost.energy.value, 90.0, atol=1e-9)
    assert_almost_equal(cost.equipment.value, 512.0, atol=1e-9)
    assert_almost_equal(cost.consumables.value, 150.0, atol=1e-12)
    assert_almost_equal(cost.total().value, 752.0, atol=1e-9)
    assert_almost_equal(cost.per_mass().to(PER_CARAT), 752 / 3.78, atol=1e-9)
    with assert_raises(contains="energy price"):
        _ = run_cost(run, EnergyPrice64(-0.1, PER_KILOWATT_HOUR))
    with assert_raises(contains="energy price"):
        _ = run_cost(run, EnergyPrice64(NAN))


def test_cost_floor_and_target() raises:
    var run = _run()
    var e = _electricity()
    # (15 kW * 0.10 + 8) per hour over 12.6 mg/h kept, per 200 mg.
    var floor = cost_floor(run, e).to(PER_CARAT)
    assert_almost_equal(floor, 9.5 / 12.6 * 200, atol=1e-9)
    # A run that grows longer approaches the floor from above.
    var long = _run(growth=1e6)
    var cost = run_cost(long, e).per_mass().to(PER_CARAT)
    assert_true(cost > floor and cost - floor < 0.01)
    # Fixed costs 8 * 4 + 150 = 182 over a margin of 1.84 per hour.
    var t = growth_for_price(run, e, MassPrice64(180, PER_CARAT))
    assert_almost_equal(t.to(HOUR), 182 / 1.84, atol=1e-9)
    var at_t = _run(growth=t.to(HOUR))
    assert_almost_equal(
        run_cost(at_t, e).per_mass().to(PER_CARAT), 180.0, atol=1e-9
    )
    with assert_raises(contains="floor"):
        _ = growth_for_price(run, e, MassPrice64(floor, PER_CARAT))
    with assert_raises(contains="target"):
        _ = growth_for_price(run, e, MassPrice64(0))
    with assert_raises(contains="target"):
        _ = growth_for_price(run, e, MassPrice64(INF))
    with assert_raises(contains="energy price"):
        _ = cost_floor(run, EnergyPrice64(INF))
    with assert_raises(contains="energy price"):
        _ = growth_for_price(run, EnergyPrice64(-1), MassPrice64(1))
    # With no fixed cost, any growth time meets a target above the floor.
    var free = _run(turnaround=0, consumables=0)
    assert_almost_equal(
        growth_for_price(free, e, MassPrice64(1000, PER_CARAT)).value, 0.0
    )


def test_cost_report() raises:
    var text = cost_report(hpht_run(), _electricity())
    assert_true("10.80 ct grown on 12 crystals, 3.78 ct kept" in text)
    assert_true("Equipment time: 512.00 (68.1 %)" in text)
    assert_true("198.94 per kept carat" in text)
    assert_true("Floor for long runs: 150.79" in text)
    # A run that costs nothing shows each share as zero.
    var free = _run(power=0, turnaround=0, consumables=0, equipment=0)
    var zero = cost_report(free, EnergyPrice64(0))
    assert_true("Total: 0.00 per run" in zero)
    assert_true("Energy: 900.0 kWh, 0.00 (0.0 %)" not in zero)
    assert_true("(0.0 %)" in zero)


def test_example_runs() raises:
    var e = _electricity()
    var cvd = mpcvd_run()
    # 30 seeds * 1.72235 mg/h * 400 h = 20.668 g = 103.34 ct.
    assert_almost_equal(cvd.grown_mass().to(CARAT), 103.341, atol=1e-3)
    assert_almost_equal(run_cost(cvd, e).total().value, 2336.0, atol=1e-9)
    # Equipment time is most of the cost of both examples, so the rate on
    # each reactor sets the cost.
    for run in [hpht_run(), mpcvd_run()]:
        var cost = run_cost(run, e)
        assert_true(cost.equipment.value > 0.5 * cost.total().value)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
