# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the energy totals of `extensions.warp.totals`.

The Alcubierre bubble's total energy has a closed form. Its density is
-κ (v²/4) sin²θ f'(r)², with κ = c⁴/(8 π G) and θ measured from the
direction of travel, so

    E = -(2 π / 3) κ (v/c)² ∫ f'(r)² r² dr.

The test finds the integral by Simpson's rule and compares it with the
sum over a grid of exact stress-energy values.
"""


from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)

from extensions.warp.analytic import exact_stress_energy, sample_metric
from extensions.warp.conditions import ConditionMap
from extensions.warp.grid import SpacetimeCenter, SpacetimeGrid
from extensions.warp.kinds import (
    CONTRAVARIANT,
    COORDINATE_FRAME,
    COVARIANT,
    EULERIAN_FRAME,
    FOURTH_ORDER,
    NULL_ENERGY,
)
from extensions.warp.metrics import (
    AlcubierreMetric,
    alcubierre_shape_derivatives,
    minkowski,
)
from extensions.warp.quantities import einstein_coupling, fraction_of_light
from extensions.warp.solver import StressEnergy
from extensions.warp.tensor import MINKOWSKI, Metric, TensorField
from extensions.warp.totals import energy_totals, violation_total
from units.si import Duration64, InverseLength64, Length64

comptime PI = 3.141592653589793


def _grid() raises -> SpacetimeGrid:
    return SpacetimeGrid(
        2,
        4,
        5,
        6,
        Duration64(1.0),
        Length64(0.5),
        Length64(0.25),
        Length64(2.0),
    )


def _density(grid: SpacetimeGrid) raises -> StressEnergy:
    """ρ = 3 J/m³ everywhere, but -1 at the first point of each slice."""
    var t = TensorField(grid, CONTRAVARIANT, EULERIAN_FRAME)
    for point in range(grid.points()):
        t.set(0, 0, point, 3.0)
    t.set(0, 0, 0, -1.0)
    t.set(0, 0, grid.index(1, 0, 0, 0), -1.0)
    return StressEnergy(t^, "constant", FOURTH_ORDER)


def test_flat_totals() raises:
    var grid = _grid()
    var metric = minkowski(grid)
    var totals = energy_totals(_density(grid), metric)
    var cell = 0.5 * 0.25 * 2.0
    assert_almost_equal(totals.volume.value, 120.0 * cell, atol=1e-12)
    assert_almost_equal(totals.positive.value, 119.0 * 3.0 * cell, atol=1e-12)
    assert_almost_equal(totals.negative.value, -cell, atol=1e-15)
    assert_almost_equal(
        totals.total.value, (119.0 * 3.0 - 1.0) * cell, atol=1e-12
    )
    # A margin of 1 leaves 2 by 3 by 4 points, without the negative one.
    var inner = energy_totals(_density(grid), metric, 1, 1)
    assert_almost_equal(inner.volume.value, 24.0 * cell, atol=1e-12)
    assert_equal(inner.negative.value, 0.0)


def test_spatial_metric_scales_the_volume() raises:
    var grid = _grid()
    var g = TensorField(grid, COVARIANT, COORDINATE_FRAME)
    for point in range(grid.points()):
        g.set_matrix(point, MINKOWSKI * 4.0)
        g.set(0, 0, point, -1.0)
    var metric = Metric(g^, "scaled")
    var totals = energy_totals(_density(grid), metric)
    var cell = 0.5 * 0.25 * 2.0
    # γ = 4 δ: √γ = 8.
    assert_almost_equal(totals.volume.value, 8.0 * 120.0 * cell, atol=1e-10)


def _simpson_integral() -> Float64:
    """Return ∫ f'(r)² r² dr from 0 to 12 m, by Simpson's rule."""
    var n = 24000
    var h = 12.0 / Float64(n)
    var total = 0.0
    for i in range(n + 1):
        var r = Float64(i) * h
        var slope = alcubierre_shape_derivatives(r, 2.0, 1.5)[1]
        var weight = 2.0
        if i == 0 or i == n:
            weight = 1.0
        elif i % 2 == 1:
            weight = 4.0
        total += weight * slope * slope * r * r
    return total * h / 3.0


def test_alcubierre_total_energy() raises:
    # The density is even in x, y and z, so one octant of midpoints, times
    # eight, covers the cube from -4.8 m to 4.8 m.
    var h = 0.3
    var grid = SpacetimeGrid.uniform(
        1, 16, 16, 16, Duration64(1.0), Length64(h)
    )
    var center = SpacetimeCenter(
        Duration64(0.0), Length64(0.5 * h), Length64(0.5 * h), Length64(0.5 * h)
    )
    var bubble = AlcubierreMetric(
        fraction_of_light(0.5), Length64(2.0), InverseLength64(1.5), True
    )
    var metric = sample_metric(bubble, grid, center)
    var energy = exact_stress_energy(bubble, grid, center)
    var totals = energy_totals(energy, metric)
    var exact = (
        -(2.0 * PI / 3.0) * einstein_coupling() * 0.25 * _simpson_integral()
    )
    assert_true(exact < 0.0)
    assert_almost_equal(8.0 * totals.total.value, exact, atol=1e-3 * abs(exact))
    assert_true(totals.positive.value < 1e-6 * abs(exact))
    # The null condition's violation, as a map of the density itself.
    var values = List[Float64]()
    for point in range(grid.points()):
        values.append(energy.tensor.get(0, 0, point))
    var map = ConditionMap(NULL_ENERGY, values^)
    assert_true(violation_total(map, metric).value < 0.0)


def test_violation_total() raises:
    var grid = _grid()
    var metric = minkowski(grid)
    var values = List[Float64](length=grid.points(), fill=2.0)
    values[3] = -4.0
    var map = ConditionMap(NULL_ENERGY, values^)
    var cell = 0.5 * 0.25 * 2.0
    assert_almost_equal(
        violation_total(map, metric).value, -4.0 * cell, atol=1e-15
    )
    assert_equal(violation_total(map, metric, 1).value, 0.0)
    with assert_raises(contains="one value for each grid point"):
        _ = violation_total(ConditionMap(NULL_ENERGY, [1.0]), metric)


def test_total_refusals() raises:
    var grid = _grid()
    var metric = minkowski(grid)
    var energy = _density(grid)
    with assert_raises(contains="outside the grid"):
        _ = energy_totals(energy, metric, -1)
    with assert_raises(contains="outside the grid"):
        _ = energy_totals(energy, metric, 2)
    with assert_raises(contains="must not be negative"):
        _ = energy_totals(energy, metric, 0, -1)
    with assert_raises(contains="no points to sum"):
        _ = energy_totals(energy, metric, 0, 2)
    var g = TensorField(grid, COVARIANT, COORDINATE_FRAME)
    for point in range(grid.points()):
        g.set_matrix(point, MINKOWSKI)
        g.set(2, 2, point, -1.0)
    var flat = Metric(g^, "no volume")
    with assert_raises(contains="no positive volume"):
        _ = energy_totals(energy, flat)
    var nan_metric = TensorField(grid, COVARIANT, COORDINATE_FRAME)
    for point in range(grid.points()):
        nan_metric.set_matrix(point, MINKOWSKI * MINKOWSKI)
        nan_metric.set(0, 0, point, -1.0)
        nan_metric.set(1, 1, point, -1.0)
    var map = ConditionMap(
        NULL_ENERGY, List[Float64](length=grid.points(), fill=0.0)
    )
    with assert_raises(contains="no positive volume"):
        _ = violation_total(map, Metric(nan_metric^, "bad"))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
