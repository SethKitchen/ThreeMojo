# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Steady heat conduction, convection and Pennes' bioheat term."""

from extensions.fem.ids import DOF_X, DOF_Y, ElementId, NodeId
from extensions.fem.mesh import TetMesh, box_mesh, quadratic_mesh
from extensions.fem.thermal import (
    FilmCoefficient64,
    PerfusionCoefficient64,
    PowerDensity64,
    ThermalMaterial,
    ThermalProblem,
    WATT_PER_CUBIC_METER,
    WATT_PER_CUBIC_METER_KELVIN,
    solve_thermal,
)
from std.math import cosh, inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import (
    Length64,
    METER,
    ThermalConductivity64,
    WATT_PER_METER_KELVIN,
    WATT_PER_SQUARE_METER_KELVIN,
)
from units.temperature import CELSIUS, KELVIN, Temperature64

comptime LENGTH = 0.1
comptime CONDUCTIVITY = 0.5


def _rod(cells: Int, quadratic: Bool) raises -> TetMesh:
    var mesh = box_mesh(
        Length64(LENGTH, METER),
        Length64(0.02, METER),
        Length64(0.02, METER),
        cells,
        1,
        1,
    )
    if quadratic:
        return quadratic_mesh(mesh)
    return mesh^


def _k() -> ThermalConductivity64:
    return ThermalConductivity64(CONDUCTIVITY, WATT_PER_METER_KELVIN)


def _kelvin(value: Float64) -> Temperature64:
    return Temperature64(value, KELVIN)


def _fix_end(mut problem: ThermalProblem, x: Float64, kelvin: Float64) raises:
    var near = Length64(1e-9, METER)
    for node in problem.mesh.nodes_on_plane(DOF_X, Length64(x, METER), near):
        problem.fix(node, _kelvin(kelvin))


def test_a_linear_field_is_exact() raises:
    for quadratic in [False, True]:
        var problem = ThermalProblem(
            _rod(4, quadratic), [ThermalMaterial(_k())]
        )
        _fix_end(problem, 0, 300)
        _fix_end(problem, LENGTH, 400)
        var result = solve_thermal(problem, 1e-12, 500)
        for n in range(problem.mesh.node_count()):
            var x = problem.mesh.nodes[n].x
            assert_almost_equal(
                result.temperatures[n], 300 + 100 * x / LENGTH, atol=1e-6
            )


def test_a_source_is_exact_with_ten_nodes() raises:
    # T = T0 + q x (L - x) / (2 k), a quadratic that ten-node elements hold.
    var q = 1.0e4
    var material = ThermalMaterial(
        _k(), PowerDensity64(q, WATT_PER_CUBIC_METER)
    )
    var problem = ThermalProblem(_rod(4, True), [material])
    _fix_end(problem, 0, 310)
    _fix_end(problem, LENGTH, 310)
    var result = solve_thermal(problem, 1e-12, 2000)
    for n in range(problem.mesh.node_count()):
        var x = problem.mesh.nodes[n].x
        var exact = 310 + q * x * (LENGTH - x) / (2 * CONDUCTIVITY)
        assert_almost_equal(result.temperatures[n], exact, atol=1e-6)
    # Four-node elements come close.
    var linear = ThermalProblem(_rod(8, False), [material])
    _fix_end(linear, 0, 310)
    _fix_end(linear, LENGTH, 310)
    var coarse = solve_thermal(linear, 1e-12, 2000)
    var middle = 0.0
    for n in range(linear.mesh.node_count()):
        if abs(linear.mesh.nodes[n].x - LENGTH / 2) < 1e-9:
            middle = coarse.temperatures[n]
    assert_almost_equal(middle, 335, rtol=0.01)


def test_convection_is_exact() raises:
    # Fixed at x = 0, cooled by a fluid at x = L: a straight line with
    # T(L) = T0 + (Tf - T0) h L / (k + h L).
    var h = 50.0
    for quadratic in [False, True]:
        var problem = ThermalProblem(
            _rod(3, quadratic), [ThermalMaterial(_k())]
        )
        _fix_end(problem, 0, 350)
        var faces = problem.convect_plane(
            DOF_X,
            Length64(LENGTH, METER),
            Length64(1e-9, METER),
            FilmCoefficient64(h, WATT_PER_SQUARE_METER_KELVIN),
            _kelvin(300),
        )
        assert_equal(faces, 2)
        var result = solve_thermal(problem, 1e-12, 500)
        for n in range(problem.mesh.node_count()):
            var x = problem.mesh.nodes[n].x
            var exact = 350 - 50 * h * x / (CONDUCTIVITY + h * LENGTH)
            assert_almost_equal(result.temperatures[n], exact, atol=1e-6)


def test_pennes_profile() raises:
    # A probe holds x = 0 at 320 K, and the far end is insulated. The
    # excess over the arterial temperature falls as cosh(m (L - x)).
    var c = 0.0005 * 1050 * 3600
    var material = ThermalMaterial(
        _k(),
        perfusion=PerfusionCoefficient64(c, WATT_PER_CUBIC_METER_KELVIN),
    )
    var problem = ThermalProblem(_rod(20, True), [material])
    _fix_end(problem, 0, 320)
    var result = solve_thermal(problem, 1e-12, 4000)
    var arterial = Temperature64(37, CELSIUS).to(KELVIN)
    var m = (c / CONDUCTIVITY) ** 0.5
    for n in range(problem.mesh.node_count()):
        var x = problem.mesh.nodes[n].x
        if abs(x - 0.02) < 1e-9:
            var exact = (
                (320 - arterial) * cosh(m * (LENGTH - x)) / cosh(m * LENGTH)
            )
            assert_almost_equal(
                result.temperatures[n] - arterial, exact, rtol=0.01
            )


def test_perfusion_sets_the_level() raises:
    # With no fixed node, perfusion holds the tissue at Ta + q / c.
    var c = 2000.0
    var q = 5000.0
    var material = ThermalMaterial(
        _k(),
        PowerDensity64(q, WATT_PER_CUBIC_METER),
        PerfusionCoefficient64(c, WATT_PER_CUBIC_METER_KELVIN),
    )
    for quadratic in [False, True]:
        var problem = ThermalProblem(
            _rod(2, quadratic), [material], _kelvin(310)
        )
        var result = solve_thermal(problem, 1e-12, 500)
        for n in range(problem.mesh.node_count()):
            assert_almost_equal(result.temperatures[n], 310 + q / c, atol=1e-6)
        assert_almost_equal(
            result.temperature(NodeId(0)).to(KELVIN), 312.5, atol=1e-6
        )
        with assert_raises(contains="node"):
            _ = result.temperature(NodeId(-1))


def test_refusals() raises:
    var k = _k()
    with assert_raises(contains="conductivity"):
        _ = ThermalMaterial(ThermalConductivity64(0, WATT_PER_METER_KELVIN))
    with assert_raises(contains="conductivity"):
        _ = ThermalMaterial(
            ThermalConductivity64(inf[DType.float64](), WATT_PER_METER_KELVIN)
        )
    with assert_raises(contains="heat source"):
        _ = ThermalMaterial(
            k, PowerDensity64(nan[DType.float64](), WATT_PER_CUBIC_METER)
        )
    with assert_raises(contains="perfusion"):
        _ = ThermalMaterial(
            k, perfusion=PerfusionCoefficient64(-1, WATT_PER_CUBIC_METER_KELVIN)
        )
    with assert_raises(contains="perfusion"):
        _ = ThermalMaterial(
            k,
            perfusion=PerfusionCoefficient64(
                inf[DType.float64](), WATT_PER_CUBIC_METER_KELVIN
            ),
        )
    with assert_raises(contains="an element"):
        _ = ThermalProblem(TetMesh(), [ThermalMaterial(k)])
    with assert_raises(contains="material"):
        _ = ThermalProblem(_rod(1, False), List[ThermalMaterial]())
    with assert_raises(contains="absolute zero"):
        _ = ThermalProblem(_rod(1, False), [ThermalMaterial(k)], _kelvin(0))
    with assert_raises(contains="absolute zero"):
        _ = ThermalProblem(
            _rod(1, False), [ThermalMaterial(k)], _kelvin(inf[DType.float64]())
        )
    var problem = ThermalProblem(_rod(1, False), [ThermalMaterial(k)])
    with assert_raises(contains="absolute zero"):
        problem.fix(NodeId(0), _kelvin(-5))
    with assert_raises(contains="absolute zero"):
        problem.fix(NodeId(0), _kelvin(inf[DType.float64]()))
    with assert_raises(contains="node"):
        problem.fix(NodeId(99), _kelvin(300))
    var plane = Length64(0, METER)
    var near = Length64(1e-9, METER)
    with assert_raises(contains="film coefficient"):
        _ = problem.convect_plane(
            DOF_X,
            plane,
            near,
            FilmCoefficient64(-1, WATT_PER_SQUARE_METER_KELVIN),
            _kelvin(300),
        )
    with assert_raises(contains="film coefficient"):
        _ = problem.convect_plane(
            DOF_X,
            plane,
            near,
            FilmCoefficient64(
                inf[DType.float64](), WATT_PER_SQUARE_METER_KELVIN
            ),
            _kelvin(300),
        )
    with assert_raises(contains="absolute zero"):
        _ = problem.convect_plane(
            DOF_X,
            plane,
            near,
            FilmCoefficient64(5, WATT_PER_SQUARE_METER_KELVIN),
            _kelvin(0),
        )
    with assert_raises(contains="absolute zero"):
        _ = problem.convect_plane(
            DOF_X,
            plane,
            near,
            FilmCoefficient64(5, WATT_PER_SQUARE_METER_KELVIN),
            _kelvin(inf[DType.float64]()),
        )
    # A plane through no outer face.
    assert_equal(
        problem.convect_plane(
            DOF_Y,
            Length64(5, METER),
            near,
            FilmCoefficient64(5, WATT_PER_SQUARE_METER_KELVIN),
            _kelvin(300),
        ),
        0,
    )
    # Nothing sets the level of the temperatures.
    var floating = ThermalProblem(_rod(1, False), [ThermalMaterial(k)])
    with assert_raises(contains="fixed temperature, convection or perfusion"):
        _ = solve_thermal(floating, 1e-10, 100)
    # Every node fixed: nothing to solve.
    var held = ThermalProblem(_rod(1, False), [ThermalMaterial(k)])
    for n in range(held.mesh.node_count()):
        held.fix(NodeId(n), _kelvin(300))
    var still = solve_thermal(held, 1e-10, 100)
    assert_equal(still.temperatures[3], 300)
    assert_equal(still.iterations, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
