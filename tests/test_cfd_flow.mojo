# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the finite-volume flow solver of `extensions.cfd`.

The channel reference is the plane Poiseuille flow of White, "Viscous
Fluid Flow", 3rd edition, and the solution of its finite-volume
equations. The cavity reference is tables I and II of
Ghia, Ghia and Shin, "High-Re solutions for incompressible flow using
the Navier-Stokes equations and a multigrid method", Journal of
Computational Physics 48, 1982, at a Reynolds number of 100. The
cavity is also checked cell by cell against OpenFOAM icoFoam 2406.
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
    Boundary,
    FlowCase,
    FlowOptions,
    FlowSolver,
    Grid,
    default_options,
    fixed_pressure,
    fixed_velocity,
    pressure_pattern,
    wall,
)
from extensions.cfd.kinds import (
    BoundaryKind,
    CENTRAL,
    ConvectionScheme,
    EAST,
    FIXED_PRESSURE,
    FIXED_VELOCITY,
    NORTH,
    SOUTH,
    Side,
    UPWIND,
    WEST,
)
from extensions.cfd.quantities import (
    CENTIPOISE,
    CENTISTOKES,
    DynamicViscosity64,
    PASCAL_SECOND,
    SQUARE_METER_PER_SECOND,
)
from units.si import (
    Density64,
    Duration64,
    KILOGRAM_PER_CUBIC_METER,
    Length64,
    METER,
    METER_PER_SECOND,
    PASCAL,
    Pressure64,
    SECOND,
    Velocity64,
)


def _m(v: Float64) -> Length64:
    return Length64(v, METER)


def _s(v: Float64) -> Duration64:
    return Duration64(v, SECOND)


def _speed(v: Float64) -> Velocity64:
    return Velocity64(v, METER_PER_SECOND)


def _fluid(grid: Grid, density: Float64, viscosity: Float64) raises -> FlowCase:
    return FlowCase(
        grid,
        Density64(density, KILOGRAM_PER_CUBIC_METER),
        DynamicViscosity64(viscosity, PASCAL_SECOND),
    )


def test_kinds() raises:
    assert_true(WEST.is_valid())
    assert_true(NORTH.is_valid())
    assert_false(Side(4).is_valid())
    assert_false(Side(-1).is_valid())
    assert_true(FIXED_VELOCITY.is_valid())
    assert_true(FIXED_PRESSURE.is_valid())
    assert_false(BoundaryKind(2).is_valid())
    assert_true(UPWIND.is_valid())
    assert_true(CENTRAL.is_valid())
    assert_false(ConvectionScheme(-1).is_valid())
    assert_true(EAST != SOUTH)


def test_grid() raises:
    """The sizes, the indices and the neighbors of a grid."""
    var grid = Grid(4, 2, _m(2), _m(3))
    assert_equal(grid.count(), 8)
    assert_almost_equal(grid.dx, 0.5, atol=0)
    assert_almost_equal(grid.dy, 1.5, atol=0)
    assert_equal(grid.cell(3, 1), 7)
    assert_almost_equal(grid.center_x(1).to(METER), 0.75, atol=0)
    assert_almost_equal(grid.center_y(1).to(METER), 2.25, atol=0)
    assert_equal(grid.neighbor(0, 0, 0), -1)
    assert_equal(grid.neighbor(1, 0, 0), 0)
    assert_equal(grid.neighbor(3, 0, 1), -1)
    assert_equal(grid.neighbor(2, 0, 1), 3)
    assert_equal(grid.neighbor(2, 0, 2), -1)
    assert_equal(grid.neighbor(2, 1, 2), 2)
    assert_equal(grid.neighbor(2, 1, 3), -1)
    assert_equal(grid.neighbor(2, 0, 3), 6)
    with assert_raises(contains="out of range"):
        _ = grid.cell(-1, 0)
    with assert_raises(contains="out of range"):
        _ = grid.cell(4, 0)
    with assert_raises(contains="out of range"):
        _ = grid.cell(0, -1)
    with assert_raises(contains="out of range"):
        _ = grid.cell(0, 2)
    with assert_raises(contains="along x"):
        _ = Grid(0, 2, _m(1), _m(1))
    with assert_raises(contains="along y"):
        _ = Grid(2, 0, _m(1), _m(1))
    with assert_raises(contains="larger"):
        _ = Grid(1048577, 1, _m(1), _m(1))
    with assert_raises(contains="larger"):
        _ = Grid(2, 1048576, _m(1), _m(1))
    with assert_raises(contains="width"):
        _ = Grid(2, 2, _m(0), _m(1))
    with assert_raises(contains="height"):
        _ = Grid(2, 2, _m(1), _m(inf[DType.float64]()))
    # The pressure matrix has the cell and each neighbor that exists.
    var pattern = pressure_pattern(grid)
    assert_equal(pattern.size, 8)
    assert_equal(pattern.nonzeros(), 8 + 2 * (3 * 2 + 4))
    assert_equal(pattern.columns[0], 0)
    assert_equal(pattern.columns[1], 1)
    assert_equal(pattern.columns[2], 4)


def test_case_refusals() raises:
    var grid = Grid(2, 2, _m(1), _m(1))
    var bad = nan[DType.float64]()
    with assert_raises(contains="density"):
        _ = _fluid(grid, 0, 1)
    with assert_raises(contains="viscosity"):
        _ = _fluid(grid, 1, -1)
    var flow = _fluid(grid, 1000, 0.001)
    assert_almost_equal(
        flow.kinematic_viscosity().to(CENTISTOKES), 1.0, atol=1e-12
    )
    assert_almost_equal(
        DynamicViscosity64(1, CENTIPOISE).to(PASCAL_SECOND), 0.001, atol=0
    )
    assert_true(flow.scheme == CENTRAL)
    flow.set_scheme(UPWIND)
    assert_true(flow.scheme == UPWIND)
    with assert_raises(contains="scheme"):
        flow.set_scheme(ConvectionScheme(2))
    with assert_raises(contains="side"):
        flow.set_boundary(Side(4), wall())
    assert_true(wall().is_valid())
    assert_false(Boundary(BoundaryKind(3), 0, 0, 0).is_valid())
    assert_false(Boundary(FIXED_VELOCITY, bad, 0, 0).is_valid())
    assert_false(Boundary(FIXED_VELOCITY, 0, bad, 0).is_valid())
    assert_false(Boundary(FIXED_VELOCITY, 0, 0, bad).is_valid())
    with assert_raises(contains="boundary"):
        flow.set_boundary(WEST, fixed_velocity(_speed(bad), _speed(0)))
    with assert_raises(contains="boundary"):
        flow.set_boundary(WEST, fixed_pressure(Pressure64(bad, PASCAL)))
    flow.boundaries[1] = Boundary(FIXED_VELOCITY, bad, 0, 0)
    with assert_raises(contains="boundary"):
        _ = FlowSolver(flow.copy(), default_options())
    with assert_raises(contains="corrector"):
        _ = FlowOptions(0, 1, 1e-6, 1)
    with assert_raises(contains="sweep"):
        _ = FlowOptions(1, 0, 1e-6, 1)
    with assert_raises(contains="tolerance"):
        _ = FlowOptions(1, 1, 0, 1)
    with assert_raises(contains="budget"):
        _ = FlowOptions(1, 1, 1e-6, 0)


def _channel(scheme: ConvectionScheme) raises -> FlowSolver:
    """A 2 m by 1 m channel with a pressure drop of 0.4 Pa.

    The fluid has a density of 2 kg/m³ and a viscosity of 0.1 Pa s.
    """
    var flow = _fluid(Grid(3, 6, _m(2), _m(1)), 2, 0.1)
    flow.set_boundary(WEST, fixed_pressure(Pressure64(0.4, PASCAL)))
    flow.set_boundary(EAST, fixed_pressure(Pressure64(0, PASCAL)))
    flow.set_scheme(scheme)
    var solver = FlowSolver(flow^, default_options())
    _ = solver.run_to_steady(_s(2), _speed(1e-11), 500)
    return solver^


def test_channel_is_poiseuille_flow() raises:
    """A channel between two walls with a pressure drop along it.

    Reference: u = G y (H - y) / (2 μ), with G the pressure drop per
    length. The finite-volume equations of equal cells have the exact
    solution u + G Δy² / (8 μ) at the cell centers, within 1e-8 here. The
    pressure is linear. The flow rate is G H³ / (12 μ) times 1 + 2 / n²
    for n cells across, so it is second order. Both
    convection schemes give the same flow, because the convection of a
    developed flow is zero.
    """
    var schemes = [CENTRAL, UPWIND]
    for k in range(2):
        var solver = _channel(schemes[k])
        var gradient = 0.4 / 2
        var rate = Float64(0)
        for j in range(6):
            var y = (Float64(j) + 0.5) / 6
            var exact = gradient * y * (1 - y) / (2 * 0.1)
            var offset = gradient / 36 / (8 * 0.1)
            for i in range(3):
                var got = solver.velocity_x(i, j).to(METER_PER_SECOND)
                assert_almost_equal(got, exact + offset, atol=1e-8)
                assert_almost_equal(
                    solver.velocity_y(i, j).to(METER_PER_SECOND),
                    0.0,
                    atol=1e-8,
                )
                var x = (Float64(i) + 0.5) * 2 / 3
                assert_almost_equal(
                    solver.pressure(i, j).to(PASCAL),
                    0.4 * (1 - x / 2),
                    atol=1e-8,
                )
            rate += solver.velocity_x(1, j).to(METER_PER_SECOND) / 6
        # The sum over six cells is above the exact rate by 2 / 6².
        var expected = gradient / (12 * 0.1)
        assert_almost_equal(rate / expected, 1 + 2.0 / 36, atol=1e-7)
        assert_true(solver.imbalance().to(SQUARE_METER_PER_SECOND) < 1e-9)


def _cavity(cells: Int) raises -> FlowSolver:
    """A 1 m cavity with a lid at 1 m/s and a Reynolds number of 100."""
    var flow = _fluid(Grid(cells, cells, _m(1), _m(1)), 1, 0.01)
    flow.set_boundary(NORTH, fixed_velocity(_speed(1), _speed(0)))
    var solver = FlowSolver(flow^, default_options())
    _ = solver.run_to_steady(_s(5 / Float64(cells)), _speed(1e-5), 2000)
    return solver^


def _along(values: List[Float64], cells: Int, position: Float64) -> Float64:
    """Interpolate cell-center values along a line at a position."""
    var place = position * Float64(cells) - 0.5
    var low = Int(place)
    low = max(0, min(cells - 2, low))
    var t = place - Float64(low)
    return values[low] + t * (values[low + 1] - values[low])


def _foam_difference(solver: FlowSolver, cells: Int) raises -> Float64:
    """Return the largest difference from the cell velocities of icoFoam.

    Args:
        solver: The cavity at steady state.
        cells: The number of cells on a side.

    Returns:
        The largest difference of u or v over all cells, in m/s.

    Raises:
        Error: The reference file is missing or does not hold each cell.
    """
    var text = Path(String("assets/cfd/cavity_", cells, ".txt")).read_text()
    var worst = Float64(0)
    var count = 0
    for line in text.splitlines():
        if line.startswith("#"):
            continue
        var words = line.split()
        var n = Int(words[0]) + cells * Int(words[1])
        worst = max(worst, abs(solver.u[n] - Float64(words[2])))
        worst = max(worst, abs(solver.v[n] - Float64(words[3])))
        count += 1
    assert_equal(count, cells * cells)
    return worst


def _cavity_error(solver: FlowSolver, cells: Int) raises -> Float64:
    """Return the largest difference from twelve values of Ghia.

    Args:
        solver: The cavity at steady state.
        cells: The number of cells on a side.

    Returns:
        The largest difference of u or v, in m/s.

    Raises:
        Error: The flow does not balance.
    """
    var half = cells // 2
    # u on the vertical line and v on the horizontal line through the
    # center, each as the mean of the two cells beside the line.
    var u = List[Float64]()
    var v = List[Float64]()
    for k in range(cells):
        u.append(
            0.5 * (solver.u[half - 1 + cells * k] + solver.u[half + cells * k])
        )
        v.append(
            0.5
            * (solver.v[k + cells * (half - 1)] + solver.v[k + cells * half])
        )
    var y = [
        0.9766,
        0.8516,
        0.7344,
        0.6172,
        0.5,
        0.4531,
        0.2813,
        0.1719,
        0.0547,
    ]
    var u_ghia = [
        0.84123,
        0.23151,
        0.00332,
        -0.13641,
        -0.20581,
        -0.21090,
        -0.15662,
        -0.10150,
        -0.03717,
    ]
    var x = [0.2344, 0.5, 0.8047]
    var v_ghia = [0.17527, 0.05454, -0.24533]
    var worst = Float64(0)
    for k in range(9):
        worst = max(worst, abs(_along(u, cells, y[k]) - u_ghia[k]))
    for k in range(3):
        worst = max(worst, abs(_along(v, cells, x[k]) - v_ghia[k]))
    assert_true(solver.imbalance().to(SQUARE_METER_PER_SECOND) < 1e-8)
    return worst


def test_cavity_meets_ghia_and_icofoam() raises:
    """A lid-driven cavity at a Reynolds number of 100.

    Reference 1: Ghia, Ghia and Shin, tables I and II: nine values of u
    on the vertical center line and three of v on the horizontal one.
    The largest difference is 0.19 of the lid speed with 8 cells a side
    and 0.029 with 16. The check allows 0.25 and 0.04.

    Reference 2: OpenFOAM icoFoam on the same grid, scheme and time step,
    from `assets/cfd/make_cavity_reference.py`. The largest difference
    over all cells is 0.019 with 8 cells and 0.009 with 16. The two
    programs differ at the lid corners, where icoFoam adds a flux
    correction that depends on the time step. The check allows 0.025 and
    0.012.
    """
    var coarse_solver = _cavity(8)
    var fine_solver = _cavity(16)
    var coarse = _cavity_error(coarse_solver, 8)
    var fine = _cavity_error(fine_solver, 16)
    assert_true(coarse < 0.25, String(coarse))
    assert_true(fine < 0.04, String(fine))
    assert_true(fine < 0.25 * coarse, String(coarse, " ", fine))
    var coarse_foam = _foam_difference(coarse_solver, 8)
    var fine_foam = _foam_difference(fine_solver, 16)
    assert_true(coarse_foam < 0.025, String(coarse_foam))
    assert_true(fine_foam < 0.012, String(fine_foam))


def test_fluid_at_rest_stays_at_rest() raises:
    var flow = _fluid(Grid(3, 2, _m(1), _m(1)), 1, 0.01)
    var solver = FlowSolver(flow^, default_options())
    solver.run(_s(0.1), 0)
    assert_almost_equal(solver.elapsed().to(SECOND), 0.0, atol=0)
    solver.run(_s(0.1), 3)
    assert_almost_equal(solver.elapsed().to(SECOND), 0.3, atol=1e-15)
    assert_almost_equal(solver.change().to(METER_PER_SECOND), 0.0, atol=0)
    for j in range(2):
        for i in range(3):
            assert_almost_equal(
                solver.velocity_x(i, j).to(METER_PER_SECOND), 0.0, atol=0
            )
            assert_almost_equal(solver.pressure(i, j).to(PASCAL), 0.0, atol=0)


def test_one_cell_at_rest() raises:
    """A grid of one cell has no neighbor on any side."""
    var flow = _fluid(Grid(1, 1, _m(1), _m(1)), 1, 0.01)
    var solver = FlowSolver(flow^, default_options())
    solver.step(_s(0.1))
    assert_almost_equal(
        solver.velocity_x(0, 0).to(METER_PER_SECOND), 0.0, atol=0
    )
    assert_almost_equal(solver.pressure(0, 0).to(PASCAL), 0.0, atol=0)


def test_inlet_flow_leaves_through_the_outlet() raises:
    """A duct with an inlet at 0.5 m/s and an outlet of fixed pressure.

    Reference: the continuity equation. The flux through the outlet
    equals the flux through the inlet, and the developed profile is
    faster at the center than the mean. The upwind scheme carries the
    convection.
    """
    var flow = _fluid(Grid(8, 4, _m(4), _m(1)), 1, 0.05)
    flow.set_boundary(WEST, fixed_velocity(_speed(0.5), _speed(0)))
    flow.set_boundary(EAST, fixed_pressure(Pressure64(0, PASCAL)))
    flow.set_scheme(UPWIND)
    var solver = FlowSolver(flow^, default_options())
    var steps = solver.run_to_steady(_s(0.5), _speed(1e-9), 500)
    assert_true(steps > 1)
    var leaving = Float64(0)
    for j in range(4):
        leaving += solver.flux_x[8 + 9 * j]
        assert_almost_equal(solver.flux_x[9 * j], 0.125, atol=0)
    assert_almost_equal(leaving, 0.5, atol=1e-8)
    assert_true(solver.velocity_x(7, 1).to(METER_PER_SECOND) > 0.6)
    assert_true(solver.velocity_x(7, 0).to(METER_PER_SECOND) < 0.45)
    # The pressure falls along the duct.
    assert_true(
        solver.pressure(0, 1).to(PASCAL) > solver.pressure(7, 1).to(PASCAL)
    )
    assert_true(solver.imbalance().to(SQUARE_METER_PER_SECOND) < 1e-8)


def test_solver_refusals() raises:
    var flow = _fluid(Grid(4, 4, _m(1), _m(1)), 1, 0.01)
    flow.set_boundary(NORTH, fixed_velocity(_speed(1), _speed(0)))
    var solver = FlowSolver(flow.copy(), default_options())
    with assert_raises(contains="time step"):
        solver.step(_s(0))
    with assert_raises(contains="time step"):
        solver.step(_s(nan[DType.float64]()))
    with assert_raises(contains="steady tolerance"):
        _ = solver.run_to_steady(_s(0.1), _speed(0), 5)
    with assert_raises(contains="step budget"):
        _ = solver.run_to_steady(_s(0.1), _speed(1e-6), 0)
    with assert_raises(contains="not steady"):
        _ = solver.run_to_steady(_s(0.1), _speed(1e-12), 2)
    with assert_raises(contains="out of range"):
        _ = solver.velocity_x(4, 0)
    with assert_raises(contains="out of range"):
        _ = solver.velocity_y(0, 4)
    with assert_raises(contains="out of range"):
        _ = solver.pressure(-1, 0)
    var starved = FlowSolver(flow.copy(), FlowOptions(2, 1, 1e-12, 1))
    with assert_raises(contains="did not converge"):
        starved.step(_s(0.1))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
