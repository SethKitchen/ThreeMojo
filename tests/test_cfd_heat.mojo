# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the buoyant flow of `extensions.cfd`.

The reference is the benchmark of de Vahl Davis, "Natural convection of
air in a square cavity: a bench mark numerical solution", International
Journal for Numerical Methods in Fluids 3, 1983: a square cavity with a
hot wall and a cold wall, insulated above and below, at a Prandtl number
of 0.71. Its table of results gives the mean Nusselt number and the peak
velocities on the two center lines. The two convection cases are also
checked cell by cell against OpenFOAM buoyantBoussinesqPimpleFoam 2406.
"""

from std.math import inf, nan
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from extensions.cfd.flow import (
    FlowCase,
    Grid,
    default_options,
    fixed_pressure,
    fixed_velocity,
)
from extensions.cfd.heat import (
    BuoyantCase,
    BuoyantSolver,
    ThermalBoundary,
    fixed_temperature,
    insulated,
)
from extensions.cfd.kinds import (
    EAST,
    FIXED_TEMPERATURE,
    INSULATED,
    NORTH,
    SOUTH,
    Side,
    ThermalKind,
    UPWIND,
    WEST,
)
from extensions.cfd.quantities import (
    DynamicViscosity64,
    PASCAL_SECOND,
    SQUARE_METER_PER_SECOND,
    ThermalDiffusivity64,
)
from units.si import (
    Acceleration64,
    Density64,
    Duration64,
    KILOGRAM_PER_CUBIC_METER,
    Length64,
    METER,
    METER_PER_SECOND,
    METER_PER_SECOND_SQUARED,
    PASCAL,
    PER_KELVIN,
    Pressure64,
    SECOND,
    ThermalExpansion64,
    Velocity64,
)
from units.temperature import (
    KELVIN,
    KELVIN_DIFFERENCE,
    Temperature64,
    TemperatureDifference64,
)


def _m(v: Float64) -> Length64:
    return Length64(v, METER)


def _s(v: Float64) -> Duration64:
    return Duration64(v, SECOND)


def _kelvin(v: Float64) -> Temperature64:
    return Temperature64(v, KELVIN)


def _within(v: Float64) -> TemperatureDifference64:
    return TemperatureDifference64(v, KELVIN_DIFFERENCE)


def _cavity(cells: Int, rayleigh: Float64) raises -> BuoyantCase:
    """A 1 m cavity of a fluid with a Prandtl number of 0.71.

    The diffusivity, the expansion and the temperature difference are
    one, so the gravity is the Rayleigh number times 0.71, and a velocity
    is in units of the diffusivity over the side.
    """
    var flow = FlowCase(
        Grid(cells, cells, _m(1), _m(1)),
        Density64(1, KILOGRAM_PER_CUBIC_METER),
        DynamicViscosity64(0.71, PASCAL_SECOND),
    )
    var buoyant = BuoyantCase(
        flow^,
        ThermalDiffusivity64(1, SQUARE_METER_PER_SECOND),
        ThermalExpansion64(1, PER_KELVIN),
        Acceleration64(rayleigh * 0.71, METER_PER_SECOND_SQUARED),
        _kelvin(300),
    )
    buoyant.set_thermal_boundary(WEST, fixed_temperature(_kelvin(300.5)))
    buoyant.set_thermal_boundary(EAST, fixed_temperature(_kelvin(299.5)))
    return buoyant^


def _peak_on_center_lines(
    solver: BuoyantSolver, cells: Int
) -> Tuple[Float64, Float64]:
    """Return the peak u on the vertical line and v on the horizontal one."""
    var half = cells // 2
    var u = Float64(0)
    var v = Float64(0)
    for k in range(cells):
        var across = solver.flow.u[half - 1 + cells * k]
        u = max(u, abs(0.5 * (across + solver.flow.u[half + cells * k])))
        var along = solver.flow.v[k + cells * (half - 1)]
        v = max(v, abs(0.5 * (along + solver.flow.v[k + cells * half])))
    return (u, v)


def _foam_difference(
    solver: BuoyantSolver, name: String
) raises -> Tuple[Float64, Float64, Float64]:
    """Compare a 12-cell cavity with buoyantBoussinesqPimpleFoam.

    Args:
        solver: The cavity at steady state.
        name: The case of `assets/cfd/make_convection_reference.py`.

    Returns:
        The largest difference of u or v in m/s, the largest difference
        of the temperature in kelvins, and the mean temperature gradient
        of OpenFOAM at the hot wall, by the formula of `wall_gradient`.

    Raises:
        Error: The reference file is missing or does not hold each cell.
    """
    var text = Path(String("assets/cfd/convection_", name, ".txt")).read_text()
    var velocity = Float64(0)
    var heat = Float64(0)
    var gradient = Float64(0)
    var count = 0
    for line in text.splitlines():
        if line.startswith("#"):
            continue
        var words = line.split()
        var i = Int(words[0])
        var k = Int(words[1])
        var n = i + 12 * k
        velocity = max(velocity, abs(solver.flow.u[n] - Float64(words[2])))
        velocity = max(velocity, abs(solver.flow.v[n] - Float64(words[3])))
        var t = Float64(words[4])
        heat = max(heat, abs(solver.temperature(i, k).to(KELVIN) - t))
        if i == 0:
            gradient += (300.5 - t) / (0.5 / 12) / 12
        count += 1
    assert_equal(count, 144)
    return (velocity, heat, gradient)


def test_conduction_with_no_gravity() raises:
    """The cavity with no gravity: the heat crosses by conduction alone.

    Reference: the temperature is linear from the hot wall to the cold
    wall, the Nusselt number is one, and the fluid stays at rest.
    """
    var solver = BuoyantSolver(_cavity(6, 0), default_options())
    var steps = solver.run_to_steady(_s(0.05), _within(1e-10), 400)
    assert_true(steps > 5)
    for j in range(6):
        for i in range(6):
            var x = (Float64(i) + 0.5) / 6
            assert_almost_equal(
                solver.temperature(i, j).to(KELVIN), 300.5 - x, atol=1e-8
            )
            assert_almost_equal(solver.flow.u[i + 6 * j], 0.0, atol=0)
    assert_almost_equal(solver.wall_gradient(WEST), 1.0, atol=1e-7)
    assert_almost_equal(solver.wall_gradient(EAST), -1.0, atol=1e-7)
    assert_true(solver.change().to(KELVIN_DIFFERENCE) <= 1e-10)


def test_natural_convection_at_a_rayleigh_number_of_1000() raises:
    """The cavity of de Vahl Davis at Ra = 1000, with 12 cells a side.

    Reference: a mean Nusselt number of 1.118, a peak u of 3.649 on the
    vertical center line and a peak v of 3.697 on the horizontal one.
    The coarse grid is within 1.5%, 3% and 3%. The hot wall gives the
    heat that the cold wall takes.

    Second reference: buoyantBoussinesqPimpleFoam 2406 on the same grid,
    scheme and time step. The temperatures differ by at most 0.0013 K,
    the hot-wall gradients by 0.15%, and the velocities by 0.09 m/s, 2.5%
    of the peak. The largest velocity difference is in the cells at the
    corners, where OpenFOAM balances the buoyancy with the pressure at
    the faces. The check allows 0.002 K, 0.5% and 0.12 m/s.
    """
    var solver = BuoyantSolver(_cavity(12, 1000), default_options())
    _ = solver.run_to_steady(_s(0.02), _within(1e-5), 400)
    var hot = solver.wall_gradient(WEST)
    var cold = -solver.wall_gradient(EAST)
    var foam = _foam_difference(solver, "ra1000")
    assert_true(foam[0] < 0.12, String(foam[0]))
    assert_true(foam[1] < 0.002, String(foam[1]))
    assert_true(abs(hot / foam[2] - 1) < 0.005, String(hot, " ", foam[2]))
    assert_true(abs(hot / 1.118 - 1) < 0.015, String(hot))
    assert_almost_equal(cold, hot, atol=1e-3)
    var peaks = _peak_on_center_lines(solver, 12)
    assert_true(abs(peaks[0] / 3.649 - 1) < 0.03, String(peaks[0]))
    assert_true(abs(peaks[1] / 3.697 - 1) < 0.03, String(peaks[1]))
    # The fluid rises at the hot wall and falls at the cold wall.
    assert_true(solver.flow.v[0 + 12 * 6] > 0)
    assert_true(solver.flow.v[11 + 12 * 6] < 0)


def test_natural_convection_at_a_rayleigh_number_of_10000() raises:
    """The same cavity at Ra = 10000, with the upwind scheme.

    Reference: a mean Nusselt number of 2.243. Twelve cells a side with
    the first-order scheme are within 12%, and the heat flow is above
    that of Ra = 1000.

    Second reference: buoyantBoussinesqPimpleFoam 2406 with the upwind
    scheme on the same grid and time step. The temperatures differ by at
    most 0.0024 K, the hot-wall gradients by 0.5%, and the velocities by
    0.62 m/s, 3.4% of the peak, again in the corner cells. The check
    allows 0.004 K, 1% and 0.8 m/s.
    """
    var buoyant = _cavity(12, 10000)
    buoyant.flow.set_scheme(UPWIND)
    var solver = BuoyantSolver(buoyant^, default_options())
    _ = solver.run_to_steady(_s(0.005), _within(1e-4), 600)
    var hot = solver.wall_gradient(WEST)
    var foam = _foam_difference(solver, "ra10000")
    assert_true(foam[0] < 0.8, String(foam[0]))
    assert_true(foam[1] < 0.004, String(foam[1]))
    assert_true(abs(hot / foam[2] - 1) < 0.01, String(hot, " ", foam[2]))
    assert_true(abs(hot / 2.243 - 1) < 0.12, String(hot))
    assert_true(hot > 1.5)


def test_stable_layers_stay_at_rest() raises:
    """A fluid that is warm above and cold below, with gravity.

    Reference: the layers are stable, so the fluid stays at rest and the
    heat goes down by conduction alone. The buoyancy is linear in the
    height, and the pressure balances it at each face and at each wall.
    The velocities stay below 1e-6 m/s, which is the noise of the
    pressure tolerance.
    """
    var flow = FlowCase(
        Grid(4, 8, _m(1), _m(1)),
        Density64(1, KILOGRAM_PER_CUBIC_METER),
        DynamicViscosity64(0.71, PASCAL_SECOND),
    )
    var buoyant = BuoyantCase(
        flow^,
        ThermalDiffusivity64(1, SQUARE_METER_PER_SECOND),
        ThermalExpansion64(1, PER_KELVIN),
        Acceleration64(50, METER_PER_SECOND_SQUARED),
        _kelvin(300),
    )
    buoyant.set_thermal_boundary(NORTH, fixed_temperature(_kelvin(301)))
    buoyant.set_thermal_boundary(SOUTH, fixed_temperature(_kelvin(299)))
    var solver = BuoyantSolver(buoyant^, default_options())
    _ = solver.run_to_steady(_s(0.05), _within(1e-5), 400)
    for j in range(8):
        var y = (Float64(j) + 0.5) / 8
        for i in range(4):
            assert_almost_equal(
                solver.temperature(i, j).to(KELVIN), 299 + 2 * y, atol=1e-4
            )
            assert_almost_equal(solver.flow.u[i + 4 * j], 0.0, atol=1e-6)
            assert_almost_equal(solver.flow.v[i + 4 * j], 0.0, atol=1e-6)
    assert_almost_equal(solver.wall_gradient(NORTH), 2.0, atol=1e-3)
    assert_almost_equal(solver.wall_gradient(SOUTH), -2.0, atol=1e-3)


def test_inlet_temperature_fills_a_duct() raises:
    """A duct with a warm inlet and an insulated outlet, with no buoyancy.

    Reference: with insulated walls, the whole duct takes the temperature
    of the inlet.
    """
    var flow = FlowCase(
        Grid(6, 3, _m(2), _m(1)),
        Density64(1, KILOGRAM_PER_CUBIC_METER),
        DynamicViscosity64(0.1, PASCAL_SECOND),
    )
    flow.set_boundary(
        WEST,
        fixed_velocity(
            Velocity64(1, METER_PER_SECOND), Velocity64(0, METER_PER_SECOND)
        ),
    )
    flow.set_boundary(EAST, fixed_pressure(Pressure64(0, PASCAL)))
    flow.set_scheme(UPWIND)
    var buoyant = BuoyantCase(
        flow^,
        ThermalDiffusivity64(0.05, SQUARE_METER_PER_SECOND),
        ThermalExpansion64(0, PER_KELVIN),
        Acceleration64(9.80665, METER_PER_SECOND_SQUARED),
        _kelvin(290),
    )
    buoyant.set_thermal_boundary(WEST, fixed_temperature(_kelvin(310)))
    var solver = BuoyantSolver(buoyant^, default_options())
    _ = solver.run_to_steady(_s(0.5), _within(1e-9), 400)
    for j in range(3):
        for i in range(6):
            assert_almost_equal(
                solver.temperature(i, j).to(KELVIN), 310.0, atol=1e-6
            )


def test_heat_refusals() raises:
    var bad = nan[DType.float64]()
    var grid = Grid(2, 2, _m(1), _m(1))
    var flow = FlowCase(
        grid,
        Density64(1, KILOGRAM_PER_CUBIC_METER),
        DynamicViscosity64(1, PASCAL_SECOND),
    )
    var alpha = ThermalDiffusivity64(1, SQUARE_METER_PER_SECOND)
    var beta = ThermalExpansion64(1, PER_KELVIN)
    var g = Acceleration64(1, METER_PER_SECOND_SQUARED)
    with assert_raises(contains="diffusivity"):
        _ = BuoyantCase(
            flow.copy(),
            ThermalDiffusivity64(0, SQUARE_METER_PER_SECOND),
            beta,
            g,
            _kelvin(300),
        )
    with assert_raises(contains="expansion"):
        _ = BuoyantCase(
            flow.copy(),
            alpha,
            ThermalExpansion64(bad, PER_KELVIN),
            g,
            _kelvin(300),
        )
    with assert_raises(contains="gravity"):
        _ = BuoyantCase(
            flow.copy(),
            alpha,
            beta,
            Acceleration64(inf[DType.float64](), METER_PER_SECOND_SQUARED),
            _kelvin(300),
        )
    with assert_raises(contains="reference"):
        _ = BuoyantCase(flow.copy(), alpha, beta, g, _kelvin(bad))
    var buoyant = BuoyantCase(flow.copy(), alpha, beta, g, _kelvin(300))
    with assert_raises(contains="side"):
        buoyant.set_thermal_boundary(Side(4), insulated())
    with assert_raises(contains="thermal boundary"):
        buoyant.set_thermal_boundary(WEST, fixed_temperature(_kelvin(bad)))
    with assert_raises(contains="thermal boundary"):
        buoyant.set_thermal_boundary(WEST, ThermalBoundary(ThermalKind(2), 300))
    assert_true(FIXED_TEMPERATURE.is_valid())
    assert_true(INSULATED.is_valid())
    assert_false(ThermalKind(-1).is_valid())
    assert_true(insulated().is_valid())
    var broken = buoyant.copy()
    broken.thermal[2] = ThermalBoundary(FIXED_TEMPERATURE, bad)
    with assert_raises(contains="thermal boundary"):
        _ = BuoyantSolver(broken^, default_options())
    buoyant.set_thermal_boundary(WEST, fixed_temperature(_kelvin(301)))
    var solver = BuoyantSolver(buoyant^, default_options())
    assert_almost_equal(solver.change().to(KELVIN_DIFFERENCE), 0.0, atol=0)
    with assert_raises(contains="time step"):
        solver.step(_s(0))
    with assert_raises(contains="steady tolerance"):
        _ = solver.run_to_steady(_s(0.1), _within(0), 5)
    with assert_raises(contains="step budget"):
        _ = solver.run_to_steady(_s(0.1), _within(1e-6), 0)
    with assert_raises(contains="not steady"):
        _ = solver.run_to_steady(_s(0.001), _within(1e-12), 2)
    with assert_raises(contains="out of range"):
        _ = solver.temperature(2, 0)
    with assert_raises(contains="side"):
        _ = solver.wall_gradient(Side(-1))
    with assert_raises(contains="fixed temperature"):
        _ = solver.wall_gradient(EAST)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
