# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Heat fluxes of elements, and the heat that held nodes supply."""

from extensions.fem.ids import DOF_X, DOF_Y, DOF_Z, DofAxis, NodeId
from extensions.fem.mesh import TetMesh, box_mesh, quadratic_mesh
from extensions.fem.thermal import (
    HeatRates,
    PerfusionCoefficient64,
    PowerDensity64,
    ThermalMaterial,
    ThermalProblem,
    ThermalResult,
    WATT_PER_CUBIC_METER,
    WATT_PER_CUBIC_METER_KELVIN,
    heat_flux,
    held_heat,
    solve_thermal,
)
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
    WATT,
    WATT_PER_METER_KELVIN,
    WATT_PER_SQUARE_METER,
)
from units.temperature import KELVIN, Temperature64

comptime LENGTH = 0.1
comptime SIDE = 0.02
comptime CONDUCTIVITY = 0.5


def _rod(quadratic: Bool) raises -> TetMesh:
    var mesh = box_mesh(
        Length64(LENGTH, METER),
        Length64(SIDE, METER),
        Length64(SIDE, METER),
        4,
        1,
        1,
    )
    if quadratic:
        return quadratic_mesh(mesh)
    return mesh^


def _material(source: Float64) raises -> ThermalMaterial:
    return ThermalMaterial(
        ThermalConductivity64(CONDUCTIVITY, WATT_PER_METER_KELVIN),
        PowerDensity64(source, WATT_PER_CUBIC_METER),
    )


def _hold(mut problem: ThermalProblem, cold: Float64, hot: Float64) raises:
    var near = Length64(1e-9, METER)
    for node in problem.mesh.nodes_on_plane(DOF_X, Length64(0, METER), near):
        problem.fix(node, Temperature64(cold, KELVIN))
    for node in problem.mesh.nodes_on_plane(
        DOF_X, Length64(LENGTH, METER), near
    ):
        problem.fix(node, Temperature64(hot, KELVIN))


def test_a_rod_between_two_temperatures() raises:
    # 310 K at x = 0 and 330 K at x = L: the flux is -k dT/dx everywhere,
    # and k A dT / L enters at the hot end and leaves at the cold end.
    var area = SIDE * SIDE
    var through = CONDUCTIVITY * area * 20.0 / LENGTH
    for quadratic in [False, True]:
        var problem = ThermalProblem(_rod(quadratic), [_material(0)])
        _hold(problem, 310, 330)
        var result = solve_thermal(problem, 1e-13, 5000)
        var flux = heat_flux(problem, result)
        for e in range(problem.mesh.element_count()):
            assert_almost_equal(
                flux.component(e, DOF_X).to(WATT_PER_SQUARE_METER),
                -CONDUCTIVITY * 20.0 / LENGTH,
                rtol=1e-9,
            )
            assert_almost_equal(
                flux.component(e, DOF_Y).to(WATT_PER_SQUARE_METER),
                0.0,
                atol=1e-7,
            )
            assert_almost_equal(
                flux.component(e, DOF_Z).to(WATT_PER_SQUARE_METER),
                0.0,
                atol=1e-7,
            )
            assert_almost_equal(
                flux.magnitude(e).to(WATT_PER_SQUARE_METER), 100.0, rtol=1e-9
            )
        var rates = held_heat(problem, result)
        var hot = 0.0
        var cold = 0.0
        for n in range(problem.mesh.node_count()):
            var x = problem.mesh.nodes[n].x
            var rate = rates.at(NodeId(n)).to(WATT)
            if x < 1e-9:
                cold += rate
            elif x > LENGTH - 1e-9:
                hot += rate
            else:
                assert_equal(rate, 0.0)
        assert_almost_equal(hot, through, rtol=1e-9)
        assert_almost_equal(cold, -through, rtol=1e-9)
        assert_almost_equal(rates.total().to(WATT), 0.0, atol=1e-12)


def test_a_source_leaves_through_the_held_ends() raises:
    # A uniform source q in a rod held at 310 K at both ends: all of q V
    # leaves through the ends, half at each.
    var q = 1.0e4
    var volume = LENGTH * SIDE * SIDE
    for quadratic in [False, True]:
        var problem = ThermalProblem(_rod(quadratic), [_material(q)])
        _hold(problem, 310, 310)
        var result = solve_thermal(problem, 1e-13, 5000)
        var rates = held_heat(problem, result)
        assert_almost_equal(rates.total().to(WATT), -q * volume, rtol=1e-9)
        var cold = 0.0
        for n in range(problem.mesh.node_count()):
            if problem.mesh.nodes[n].x < 1e-9:
                cold += rates.values[n]
        assert_almost_equal(cold, -q * volume / 2, rtol=1e-9)


def test_perfusion_alone_holds_no_node() raises:
    var problem = ThermalProblem(
        _rod(False),
        [
            ThermalMaterial(
                ThermalConductivity64(CONDUCTIVITY, WATT_PER_METER_KELVIN),
                PowerDensity64(400, WATT_PER_CUBIC_METER),
                PerfusionCoefficient64(1890, WATT_PER_CUBIC_METER_KELVIN),
            )
        ],
    )
    var result = solve_thermal(problem, 1e-13, 5000)
    var rates = held_heat(problem, result)
    assert_equal(rates.total().to(WATT), 0.0)
    # A uniform field has no flux.
    var flux = heat_flux(problem, result)
    assert_almost_equal(
        flux.magnitude(0).to(WATT_PER_SQUARE_METER), 0.0, atol=1e-6
    )
    assert_equal(HeatRates(List[Float64]()).total().to(WATT), 0.0)


def test_refusals() raises:
    var problem = ThermalProblem(_rod(False), [_material(0)])
    _hold(problem, 310, 330)
    var wrong = ThermalResult(List[Float64](length=3, fill=310))
    with assert_raises(contains="not for this problem"):
        _ = held_heat(problem, wrong)
    with assert_raises(contains="not for this problem"):
        _ = heat_flux(problem, wrong)
    var result = solve_thermal(problem, 1e-13, 5000)
    var flux = heat_flux(problem, result)
    var count = problem.mesh.element_count()
    with assert_raises(contains="outside the heat fluxes"):
        _ = flux.component(count, DOF_X)
    with assert_raises(contains="outside the heat fluxes"):
        _ = flux.component(-1, DOF_X)
    with assert_raises(contains="outside the heat fluxes"):
        _ = flux.magnitude(count)
    with assert_raises(contains="outside the heat fluxes"):
        _ = flux.magnitude(-1)
    with assert_raises(contains="axis"):
        _ = flux.component(0, DofAxis(3))
    var rates = held_heat(problem, result)
    with assert_raises(contains="node"):
        _ = rates.at(NodeId(problem.mesh.node_count()))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
