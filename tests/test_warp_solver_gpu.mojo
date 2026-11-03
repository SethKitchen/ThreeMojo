# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the warp solver on a GPU: it must give what the CPU solver gives.

A moving Alcubierre bubble on 5 time slices and a comoving one are solved
on both, with both orders of difference. Each
component must match the CPU's to 1e-12 of the largest component at its
point, the measure of the WarpFactory parity. The GPU may fuse a multiply
and an add that the CPU rounds twice, so the match is not bit for bit. A
singular metric is refused. On a machine without a usable GPU, the solver
must refuse to run.
"""

from std.testing import TestSuite, assert_raises, assert_true

from extensions.warp.gpu import (
    gpu_curvature,
    gpu_stress_energy,
    warp_gpu_available,
)
from extensions.warp.grid import SpacetimeGrid
from extensions.warp.kinds import (
    COORDINATE_FRAME,
    COVARIANT,
    DifferenceOrder,
    FOURTH_ORDER,
    SECOND_ORDER,
)
from extensions.warp.metrics import alcubierre, alcubierre_comoving
from extensions.warp.quantities import fraction_of_light
from extensions.warp.solver import curvature, stress_energy
from extensions.warp.tensor import Metric, TensorField
from units.si import Duration64, InverseLength64, Length64


def _agree(cpu: TensorField, gpu: TensorField) raises:
    """Assert that two fields match to 1e-12 of each point's largest value.

    Where a point's values are rounding noise, a billionth of the field's
    largest value is the floor.
    """
    var n = cpu.grid.points()
    var field = 0.0
    for point in range(n):
        field = max(field, abs(cpu.matrix(point)).reduce_max())
    for point in range(n):
        var a = cpu.matrix(point)
        var b = gpu.matrix(point)
        var scale = max(abs(a).reduce_max(), 1e-9 * field)
        var worst = abs(a - b).reduce_max()
        assert_true(worst <= 1e-12 * scale, String(point, ": ", worst))


def _bubble(moving: Bool) raises -> Metric:
    if moving:
        var grid = SpacetimeGrid.uniform(
            5, 13, 11, 11, Duration64(1e-9), Length64(0.5)
        )
        return alcubierre(
            grid,
            grid.center(),
            fraction_of_light(0.5),
            Length64(2.0),
            InverseLength64(1.5),
        )
    var grid = SpacetimeGrid.uniform(
        1, 17, 15, 13, Duration64(1.0), Length64(0.4)
    )
    return alcubierre_comoving(
        grid,
        grid.center(),
        fraction_of_light(0.9),
        Length64(2.0),
        InverseLength64(1.5),
    )


def test_stress_energy_matches_cpu() raises:
    if not warp_gpu_available():
        return
    for moving in [True, False]:
        var metric = _bubble(moving)
        for order in [FOURTH_ORDER, SECOND_ORDER]:
            var cpu = stress_energy(metric, order)
            var gpu = gpu_stress_energy(metric, order)
            _agree(cpu.tensor, gpu.tensor)
            assert_true(gpu.order == order and gpu.name == cpu.name)


def test_curvature_matches_cpu() raises:
    if not warp_gpu_available():
        return
    var metric = _bubble(False)
    var cpu = curvature(metric)
    var gpu = gpu_curvature(metric)
    _agree(cpu.ricci, gpu.ricci)
    _agree(cpu.einstein, gpu.einstein)
    var field = 0.0
    for point in range(len(cpu.scalar)):
        field = max(field, abs(cpu.ricci.matrix(point)).reduce_max())
    for point in range(len(cpu.scalar)):
        var scale = max(abs(cpu.ricci.matrix(point)).reduce_max(), 1e-9 * field)
        assert_true(abs(cpu.scalar[point] - gpu.scalar[point]) <= 1e-12 * scale)


def test_refusals() raises:
    var grid = SpacetimeGrid.uniform(1, 5, 5, 5, Duration64(1.0), Length64(1.0))
    var zero = Metric(TensorField(grid, COVARIANT, COORDINATE_FRAME), "zero")
    if not warp_gpu_available():
        with assert_raises():
            _ = gpu_stress_energy(zero)
        with assert_raises():
            _ = gpu_curvature(zero)
        return
    with assert_raises(contains="singular"):
        _ = gpu_stress_energy(zero)
    with assert_raises(contains="singular"):
        _ = gpu_curvature(zero)
    with assert_raises(contains="order is not valid"):
        _ = gpu_stress_energy(zero, DifferenceOrder(5))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
