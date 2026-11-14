# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Transient heat conduction by backward Euler."""

from extensions.fem.ids import DOF_X, NodeId
from extensions.fem.mesh import TetMesh, box_mesh, quadratic_mesh
from extensions.fem.thermal import (
    PowerDensity64,
    ThermalCapacity,
    ThermalMaterial,
    ThermalProblem,
    WATT_PER_CUBIC_METER,
    solve_thermal,
    solve_transient,
)
from std.math import exp, inf, pi, sin
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import (
    Density64,
    Duration64,
    JOULE_PER_KILOGRAM_KELVIN,
    KILOGRAM_PER_CUBIC_METER,
    Length64,
    METER,
    SECOND,
    SpecificHeatCapacity64,
    ThermalConductivity64,
    WATT_PER_METER_KELVIN,
)
from units.temperature import KELVIN, Temperature64

comptime LENGTH = 0.1
comptime CONDUCTIVITY = 0.5
comptime DENSITY = 1000.0
comptime HEAT = 4000.0


def _rod(cells: Int) raises -> TetMesh:
    return quadratic_mesh(
        box_mesh(
            Length64(LENGTH, METER),
            Length64(0.02, METER),
            Length64(0.02, METER),
            cells,
            1,
            1,
        )
    )


def _capacity() raises -> List[ThermalCapacity]:
    return [
        ThermalCapacity(
            Density64(DENSITY, KILOGRAM_PER_CUBIC_METER),
            SpecificHeatCapacity64(HEAT, JOULE_PER_KILOGRAM_KELVIN),
        )
    ]


def _material(source: Float64 = 0) raises -> ThermalMaterial:
    return ThermalMaterial(
        ThermalConductivity64(CONDUCTIVITY, WATT_PER_METER_KELVIN),
        PowerDensity64(source, WATT_PER_CUBIC_METER),
    )


def _hold_ends(mut problem: ThermalProblem) raises:
    var near = Length64(1e-9, METER)
    for x in [0.0, LENGTH]:
        for node in problem.mesh.nodes_on_plane(
            DOF_X, Length64(x, METER), near
        ):
            problem.fix(node, Temperature64(310, KELVIN))


def _seconds(value: Float64) -> Duration64:
    return Duration64(value, SECOND)


def test_a_sine_decays_at_its_rate() raises:
    # T = 310 + 10 sin(pi x / L) exp(-t / tau), tau = L^2 / (pi^2 alpha).
    var problem = ThermalProblem(_rod(8), [_material()])
    _hold_ends(problem)
    var start = List[Temperature64]()
    for p in problem.mesh.nodes:
        start.append(Temperature64(310 + 10 * sin(pi * p.x / LENGTH), KELVIN))
    var alpha = CONDUCTIVITY / (DENSITY * HEAT)
    var tau = LENGTH**2 / (pi**2 * alpha)
    var steps = 100
    var result = solve_transient(
        problem,
        _capacity(),
        start,
        _seconds(tau / 4 / Float64(steps)),
        steps,
        steps,
        1e-12,
        2000,
    )
    assert_equal(len(result.times), 2)
    assert_almost_equal(result.times[1], tau / 4, rtol=1e-12)
    var middle = 0
    for n in range(problem.mesh.node_count()):
        if abs(problem.mesh.nodes[n].x - LENGTH / 2) < 1e-9:
            middle = n
    var excess = result.temperatures[1][middle] - 310
    assert_almost_equal(excess, 10 * exp(-0.25), rtol=0.002)
    assert_true(result.iterations > 0)


def test_long_steps_reach_the_steady_state() raises:
    var problem = ThermalProblem(_rod(2), [_material(1.0e4)])
    _hold_ends(problem)
    var steady = solve_thermal(problem, 1e-12, 2000)
    var start = List[Temperature64]()
    for _ in range(problem.mesh.node_count()):
        start.append(Temperature64(310, KELVIN))
    var result = solve_transient(
        problem, _capacity(), start, _seconds(1.0e12), 2, 1, 1e-12, 2000
    )
    assert_equal(len(result.temperatures), 3)
    for n in range(problem.mesh.node_count()):
        assert_almost_equal(
            result.temperatures[2][n], steady.temperatures[n], atol=1e-6
        )


def test_an_insulated_block_keeps_its_heat() raises:
    # No fixed node, source, perfusion or convection: the stored heat stays,
    # and the temperatures even out toward their mean.
    var problem = ThermalProblem(_rod(2), [_material()])
    var start = List[Temperature64]()
    for p in problem.mesh.nodes:
        start.append(Temperature64(300 + 100 * p.x / LENGTH, KELVIN))
    var result = solve_transient(
        problem, _capacity(), start, _seconds(500), 6, 3, 1e-13, 2000
    )
    assert_equal(len(result.times), 3)
    assert_almost_equal(result.times[2], 3000)
    var first = result.temperatures[0].copy()
    var last = result.temperatures[2].copy()
    var spread_first = 0.0
    var spread_last = 0.0
    for n in range(len(first)):
        spread_first = max(spread_first, abs(first[n] - 350))
        spread_last = max(spread_last, abs(last[n] - 350))
    assert_true(spread_last < spread_first)
    # A uniform start stays uniform: no heat flows and none is lost.
    var even = List[Temperature64]()
    for _ in range(problem.mesh.node_count()):
        even.append(Temperature64(333, KELVIN))
    var still = solve_transient(
        problem, _capacity(), even, _seconds(500), 2, 1, 1e-13, 2000
    )
    for value in still.temperatures[2]:
        assert_almost_equal(value, 333, atol=1e-8)


def test_refusals() raises:
    var problem = ThermalProblem(_rod(1), [_material()])
    var start = List[Temperature64]()
    for _ in range(problem.mesh.node_count()):
        start.append(Temperature64(310, KELVIN))
    var dt = _seconds(1)
    with assert_raises(contains="one capacity per material"):
        _ = solve_transient(
            problem, List[ThermalCapacity](), start, dt, 1, 1, 1e-10, 100
        )
    with assert_raises(contains="one start temperature per node"):
        _ = solve_transient(
            problem, _capacity(), List[Temperature64](), dt, 1, 1, 1e-10, 100
        )
    with assert_raises(contains="time step"):
        _ = solve_transient(
            problem, _capacity(), start, _seconds(0), 1, 1, 1e-10, 100
        )
    with assert_raises(contains="time step"):
        _ = solve_transient(
            problem,
            _capacity(),
            start,
            _seconds(inf[DType.float64]()),
            1,
            1,
            1e-10,
            100,
        )
    with assert_raises(contains="from 1 to 1000000 steps"):
        _ = solve_transient(problem, _capacity(), start, dt, 0, 1, 1e-10, 100)
    with assert_raises(contains="from 1 to 1000000 steps"):
        _ = solve_transient(
            problem, _capacity(), start, dt, 1000001, 1, 1e-10, 100
        )
    with assert_raises(contains="record interval"):
        _ = solve_transient(problem, _capacity(), start, dt, 1, 0, 1e-10, 100)
    var cold = start.copy()
    cold[0] = Temperature64(0, KELVIN)
    with assert_raises(contains="absolute zero"):
        _ = solve_transient(problem, _capacity(), cold, dt, 1, 1, 1e-10, 100)
    cold[0] = Temperature64(inf[DType.float64](), KELVIN)
    with assert_raises(contains="absolute zero"):
        _ = solve_transient(problem, _capacity(), cold, dt, 1, 1, 1e-10, 100)
    # A budget of one iteration cannot solve a step of an uneven start.
    var uneven = start.copy()
    uneven[0] = Temperature64(400, KELVIN)
    with assert_raises(contains="did not converge"):
        _ = solve_transient(problem, _capacity(), uneven, dt, 1, 1, 1e-14, 1)
    var heat = SpecificHeatCapacity64(HEAT, JOULE_PER_KILOGRAM_KELVIN)
    var rho = Density64(DENSITY, KILOGRAM_PER_CUBIC_METER)
    with assert_raises(contains="density"):
        _ = ThermalCapacity(Density64(0, KILOGRAM_PER_CUBIC_METER), heat)
    with assert_raises(contains="density"):
        _ = ThermalCapacity(
            Density64(inf[DType.float64](), KILOGRAM_PER_CUBIC_METER), heat
        )
    with assert_raises(contains="specific heat"):
        _ = ThermalCapacity(
            rho, SpecificHeatCapacity64(0, JOULE_PER_KILOGRAM_KELVIN)
        )
    with assert_raises(contains="specific heat"):
        _ = ThermalCapacity(
            rho,
            SpecificHeatCapacity64(
                inf[DType.float64](), JOULE_PER_KILOGRAM_KELVIN
            ),
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
