# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests that `extensions.warp` gives the same result on any number of
tasks.

Each point is computed alone, so the values must be equal bit for bit,
not only close.
"""

from std.sys import num_logical_cores
from std.testing import TestSuite, assert_equal, assert_raises

from extensions.warp.analytic import exact_curvature, exact_stress_energy
from extensions.warp.conditions import (
    energy_condition,
    energy_condition_samples,
)
from extensions.warp.grid import SpacetimeGrid
from extensions.warp.kinds import (
    COORDINATE_FRAME,
    COVARIANT,
    DOMINANT_ENERGY,
    FOURTH_ORDER,
    WEAK_ENERGY,
)
from extensions.warp.metrics import AlcubierreMetric, alcubierre_comoving
from extensions.warp.quantities import fraction_of_light
from extensions.warp.solver import curvature, stress_energy, task_count
from extensions.warp.tensor import Metric, TensorField
from units.si import Duration64, InverseLength64, Length64


def _grid() raises -> SpacetimeGrid:
    return SpacetimeGrid.uniform(1, 7, 6, 5, Duration64(1.0), Length64(0.4))


def _bubble() raises -> AlcubierreMetric:
    return AlcubierreMetric(
        fraction_of_light(0.5), Length64(1.0), InverseLength64(2.0), True
    )


def _same(a: List[Float64], b: List[Float64]) raises:
    assert_equal(len(a), len(b))
    for k in range(len(a)):
        assert_equal(a[k], b[k])


def test_task_count() raises:
    assert_equal(task_count(3, 100), 3)
    assert_equal(task_count(8, 5), 5)
    assert_equal(task_count(0, 1000), min(num_logical_cores(), 1000))
    assert_equal(task_count(1, 1), 1)
    with assert_raises(contains="must not be negative"):
        _ = task_count(-1, 10)


def test_solver_is_the_same_on_any_count() raises:
    var grid = _grid()
    var metric = alcubierre_comoving(
        grid,
        grid.center(),
        fraction_of_light(0.5),
        Length64(1.0),
        InverseLength64(2.0),
    )
    var one = stress_energy(metric, FOURTH_ORDER, 1)
    var three = stress_energy(metric, FOURTH_ORDER, 3)
    _same(one.tensor.data, three.tensor.data)
    var bent_one = curvature(metric, FOURTH_ORDER, 1)
    var bent_many = curvature(metric, FOURTH_ORDER, 7)
    _same(bent_one.ricci.data, bent_many.ricci.data)
    _same(bent_one.einstein.data, bent_many.einstein.data)
    _same(bent_one.scalar, bent_many.scalar)
    with assert_raises(contains="must not be negative"):
        _ = stress_energy(metric, FOURTH_ORDER, -2)
    var zero = Metric(TensorField(grid, COVARIANT, COORDINATE_FRAME), "zero")
    with assert_raises(contains="singular"):
        _ = curvature(zero, FOURTH_ORDER, 3)


def test_exact_solver_is_the_same_on_any_count() raises:
    var grid = _grid()
    var center = grid.center()
    var one = exact_stress_energy(_bubble(), grid, center, 1)
    var four = exact_stress_energy(_bubble(), grid, center, 4)
    _same(one.tensor.data, four.tensor.data)
    var bent_one = exact_curvature(_bubble(), grid, center, 1)
    var bent_two = exact_curvature(_bubble(), grid, center, 2)
    _same(bent_one.ricci.data, bent_two.ricci.data)
    _same(bent_one.scalar, bent_two.scalar)
    with assert_raises(contains="must not be negative"):
        _ = exact_curvature(_bubble(), grid, center, -1)


def test_conditions_are_the_same_on_any_count() raises:
    var grid = _grid()
    var metric = alcubierre_comoving(
        grid,
        grid.center(),
        fraction_of_light(0.5),
        Length64(1.0),
        InverseLength64(2.0),
    )
    var energy = stress_energy(metric)
    var one = energy_condition(energy, metric, WEAK_ENERGY, 6, 2, 1)
    var three = energy_condition(energy, metric, WEAK_ENERGY, 6, 2, 3)
    _same(one.values, three.values)
    var all_one = energy_condition_samples(
        energy, metric, DOMINANT_ENERGY, 5, 1, 1
    )
    var all_two = energy_condition_samples(
        energy, metric, DOMINANT_ENERGY, 5, 1, 2
    )
    _same(all_one.values, all_two.values)
    with assert_raises(contains="must not be negative"):
        _ = energy_condition(energy, metric, WEAK_ENERGY, 6, 2, -1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
