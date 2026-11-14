# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Thermal doses in equivalent minutes at 43 C, and dosed volumes."""

from extensions.fem.dose import dose_volume, thermal_dose
from extensions.fem.mesh import TetMesh, box_mesh
from extensions.fem.thermal import (
    ThermalCapacity,
    ThermalMaterial,
    ThermalProblem,
    TransientResult,
    solve_transient,
)
from extensions.fem.ids import NodeId
from std.math import inf
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
)
from units.si import (
    CUBIC_METER,
    Density64,
    Duration64,
    JOULE_PER_KILOGRAM_KELVIN,
    KILOGRAM_PER_CUBIC_METER,
    Length64,
    METER,
    MINUTE,
    SECOND,
    SpecificHeatCapacity64,
    ThermalConductivity64,
    WATT_PER_METER_KELVIN,
)
from units.temperature import CELSIUS, KELVIN, Temperature64


def _kelvin(celsius: Float64) -> Float64:
    return celsius + 273.15


def _history(
    times: List[Float64], rows: List[List[Float64]]
) -> TransientResult:
    """Return records of these times, in seconds, and Celsius rows."""
    var out = TransientResult()
    for r in range(len(times)):
        out.times.append(times[r])
        var row = List[Float64]()
        for c in rows[r]:
            row.append(_kelvin(c))
        out.temperatures.append(row^)
    return out^


def test_steady_temperatures() raises:
    # Ten minutes at 43, 44, 42 and 37 C.
    var steady = _history([0, 600], [[43, 44, 42, 37], [43, 44, 42, 37]])
    var dose = thermal_dose(steady)
    assert_almost_equal(dose[0].to(MINUTE), 10.0)
    # Each degree above 43 doubles the dose.
    assert_almost_equal(dose[1].to(MINUTE), 20.0)
    # Each degree below divides it by four.
    assert_almost_equal(dose[2].to(MINUTE), 2.5)
    assert_almost_equal(dose[3].to(MINUTE), 10.0 * 0.25**6)


def test_changing_temperatures() raises:
    # From 42 to 44 C: the interval counts at its mean, 43 C.
    var ramp = _history([0, 300, 900], [[42, 50], [44, 50], [44, 50]])
    var dose = thermal_dose(ramp)
    assert_almost_equal(dose[0].to(MINUTE), 5.0 + 10.0 * 2.0)
    assert_almost_equal(dose[1].to(MINUTE), 15.0 * 2.0**7)
    # Records without nodes give no doses.
    var empty = _history([0, 60], [List[Float64](), List[Float64]()])
    assert_equal(len(thermal_dose(empty)), 0)


def test_a_held_block_and_its_volume() raises:
    # A block held at 50 C for two minutes: 2^7 * 2 = 256 minutes.
    var mesh = box_mesh(
        Length64(0.02, METER),
        Length64(0.01, METER),
        Length64(0.01, METER),
        2,
        1,
        1,
    )
    var problem = ThermalProblem(
        mesh^,
        [ThermalMaterial(ThermalConductivity64(0.5, WATT_PER_METER_KELVIN))],
    )
    var start = List[Temperature64]()
    for n in range(problem.mesh.node_count()):
        problem.fix(NodeId(n), Temperature64(50, CELSIUS))
        start.append(Temperature64(50, CELSIUS))
    var capacity: List[ThermalCapacity] = [
        ThermalCapacity(
            Density64(1000, KILOGRAM_PER_CUBIC_METER),
            SpecificHeatCapacity64(4000, JOULE_PER_KILOGRAM_KELVIN),
        )
    ]
    var result = solve_transient(
        problem, capacity, start, Duration64(10, SECOND), 12, 3, 1e-12, 200
    )
    var dose = thermal_dose(result)
    for value in dose:
        assert_almost_equal(value.to(MINUTE), 256.0, rtol=1e-9)
    # Every element reaches 240 minutes: the whole block, 2 mL.
    var all = dose_volume(problem.mesh, dose, Duration64(240, MINUTE))
    assert_almost_equal(all.to(CUBIC_METER), 2e-6, rtol=1e-12)
    # Only the nodes of the first cube reach a dose: its volume.
    var half = List[Duration64]()
    for p in problem.mesh.nodes:
        var minutes = 300.0 if p.x <= 0.01 + 1e-12 else 100.0
        half.append(Duration64(minutes, MINUTE))
    var first = dose_volume(problem.mesh, half, Duration64(240, MINUTE))
    assert_almost_equal(first.to(CUBIC_METER), 1e-6, rtol=1e-12)
    assert_equal(
        dose_volume(TetMesh(), List[Duration64](), Duration64(1, MINUTE)).to(
            CUBIC_METER
        ),
        0.0,
    )


def test_refusals() raises:
    with assert_raises(contains="two or more"):
        _ = thermal_dose(_history([0], [[43]]))
    var odd = _history([0, 60], [[43], [43]])
    odd.times.append(120)
    with assert_raises(contains="two or more"):
        _ = thermal_dose(odd)
    with assert_raises(contains="rise"):
        _ = thermal_dose(_history([0, 0], [[43], [43]]))
    with assert_raises(contains="every node"):
        _ = thermal_dose(_history([0, 60], [[43], [43, 44]]))
    var mesh = box_mesh(
        Length64(1, METER), Length64(1, METER), Length64(1, METER), 1, 1, 1
    )
    with assert_raises(contains="every node"):
        _ = dose_volume(mesh, List[Duration64](), Duration64(1, MINUTE))
    var doses = List[Duration64](
        length=mesh.node_count(), fill=Duration64(1, MINUTE)
    )
    for bad in [-1.0, inf[DType.float64]()]:
        with assert_raises(contains="threshold"):
            _ = dose_volume(mesh, doses, Duration64(bad, MINUTE))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
