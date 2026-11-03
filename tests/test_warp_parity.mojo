# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Parity of `extensions.warp` with the original WarpFactory.

The reference values come from WarpFactory at commit 03b10cb, run in GNU
Octave 8.4.0: see `docs/warpfactory-parity/`. Each case builds the same
metric with the same grid, the same center and the same parameters, and
compares every listed value.

A tensor component is compared within a fraction of the largest
component at the same point, because some listed values are rounding
noise of a zero. The port's documented corrections are checked
separately: the null and weak conditions here use the Minkowski metric,
so the test lowers the Eulerian tensor as WarpFactory does to compare,
and then checks that the corrected values differ.
"""

from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
)
from tests._warpfactory_reference import ReferenceValue, reference_values

from extensions.warp.conditions import (
    energy_condition,
    null_directions,
    timelike_directions,
)
from extensions.warp.flow import GridPoint, momentum_flow_lines
from extensions.warp.frame import to_eulerian
from extensions.warp.grid import SpacetimeCenter, SpacetimeGrid
from extensions.warp.kinds import (
    DOMINANT_ENERGY,
    FOURTH_ORDER,
    NULL_ENERGY,
    SECOND_ORDER,
    STRONG_ENERGY,
)
from extensions.warp.metrics import (
    alcubierre,
    alcubierre_comoving,
    lentz_comoving,
    schwarzschild,
    van_den_broeck_comoving,
)
from extensions.warp.quantities import (
    Compliance64,
    GRAVITATIONAL_CONSTANT,
    SPEED_OF_LIGHT,
    fraction_of_light,
)
from extensions.warp.scalars import metric_scalars
from extensions.warp.solver import StressEnergy, stress_energy
from extensions.warp.tensor import Matrix4, Metric, TensorField, Vector4
from extensions.warp.warp_shell import warp_shell_comoving
from units.si import Duration64, InverseLength64, Length64, Mass64

comptime C = 299792458.0


def _point(grid: SpacetimeGrid, item: ReferenceValue) -> Int:
    """Return the flat index of the 1-based point a value names."""
    var i = item.indexes.copy()
    return grid.index(i[0] - 1, i[1] - 1, i[2] - 1, i[3] - 1)


def _largest(
    refs: List[ReferenceValue], grid: SpacetimeGrid, point: Int
) -> Float64:
    """Return the largest reference value at one point."""
    var out = 0.0
    for item in refs:
        if _point(grid, item) == point:
            out = max(out, abs(item.value))
    return out


def _check_tensor(
    name: String,
    tensor: TensorField,
    tolerance: Float64,
    factor: Float64 = 1.0,
) raises:
    """Compare every listed component of a tensor, each within `tolerance`
    times the largest listed component at its point."""
    var refs = reference_values(name)
    for item in refs:
        var point = _point(tensor.grid, item)
        var scale = _largest(refs, tensor.grid, point) * factor
        var expected = item.value * factor
        var ours = tensor.get(item.indexes[4] - 1, item.indexes[5] - 1, point)
        assert_almost_equal(ours, expected, atol=tolerance * scale + 1e-300)


def _grid_a() raises -> SpacetimeGrid:
    return SpacetimeGrid.uniform(1, 9, 9, 9, Duration64(1.0 / C), Length64(1.0))


def _alcubierre_a() raises -> Metric:
    var grid = _grid_a()
    return alcubierre_comoving(
        grid,
        grid.center(),
        fraction_of_light(0.5),
        Length64(2.0),
        InverseLength64(1.5),
    )


def test_constants_match() raises:
    assert_equal(SPEED_OF_LIGHT.value, C)
    assert_equal(GRAVITATIONAL_CONSTANT.value, 6.67430e-11)


def test_alcubierre_metric_and_energy() raises:
    var metric = _alcubierre_a()
    _check_tensor("A.g", metric.tensor, 1e-15)
    var energy = stress_energy(metric, FOURTH_ORDER)
    _check_tensor("A.E4", energy.tensor, 1e-12)
    _check_tensor("A.EUL", to_eulerian(energy, metric).tensor, 1e-12)
    # WarpFactory's second-order solver uses G = 6.674e-11 and
    # c = 2.99792e8 in c⁴ / (8 π G).
    var up = 2.99792e8
    var factor = (C / up) ** 4 * (6.674e-11 / GRAVITATIONAL_CONSTANT.value)
    _check_tensor(
        "A.E2", stress_energy(metric, SECOND_ORDER).tensor, 1e-12, factor
    )


def _upstream_lowered(eulerian: Matrix4, g: Matrix4) -> Matrix4:
    """Return g T̂ g, as WarpFactory lowers the Eulerian tensor for the
    null and weak conditions."""
    var out = Matrix4(0)
    for a in range(4):
        for b in range(4):
            var total = 0.0
            for c in range(4):
                for d in range(4):
                    total += g[4 * c + a] * eulerian[4 * c + d] * g[4 * d + b]
            out[4 * a + b] = total
    return out


def _quadratic(t: Matrix4, v: Vector4) -> Float64:
    var total = 0.0
    for a in range(4):
        for b in range(4):
            total += t[4 * a + b] * v[a] * v[b]
    return total


def test_directions_match() raises:
    var null = null_directions(10)
    for item in reference_values("A.FIELD"):
        assert_almost_equal(
            null[item.indexes[1] - 1][item.indexes[0] - 1],
            item.value,
            atol=1e-15,
        )
    var timelike = timelike_directions(10, 3)
    for item in reference_values("A.WEAKFIELD"):
        var d = (item.indexes[2] - 1) * 10 + item.indexes[1] - 1
        assert_almost_equal(
            timelike[d][item.indexes[0] - 1], item.value, atol=1e-15
        )


def test_energy_conditions_match() raises:
    var metric = _alcubierre_a()
    var grid = metric.grid()
    var energy = stress_energy(metric, FOURTH_ORDER)
    var eulerian = to_eulerian(energy, metric)
    var strong = energy_condition(energy, metric, STRONG_ENERGY, 10, 3)
    var dominant = energy_condition(energy, metric, DOMINANT_ENERGY, 10, 3)
    for item in reference_values("A.STRONG"):
        assert_almost_equal(
            strong.values[_point(grid, item)],
            item.value,
            atol=1e-12 * abs(item.value),
        )
    for item in reference_values("A.DOMINANT"):
        assert_almost_equal(
            dominant.values[_point(grid, item)],
            item.value,
            atol=1e-12 * abs(item.value),
        )
    # The null and weak maps, lowered with the coordinate metric as
    # WarpFactory lowers them.
    var null = null_directions(10)
    var timelike = timelike_directions(10, 3)
    for name in ["A.NULL", "A.WEAK"]:
        var directions = null.copy()
        if name == "A.WEAK":
            directions = timelike.copy()
        for item in reference_values(name):
            var point = _point(grid, item)
            var lowered = _upstream_lowered(
                eulerian.tensor.matrix(point), metric.at(point)
            )
            var least = _quadratic(lowered, directions[0])
            for d in range(1, len(directions)):
                least = min(least, _quadratic(lowered, directions[d]))
            assert_almost_equal(least, item.value, atol=1e-12 * abs(item.value))
    var at = grid.index(0, 4, 6, 3)
    var lowered = _upstream_lowered(eulerian.tensor.matrix(at), metric.at(at))
    for item in reference_values("A.NULLVEC"):
        assert_almost_equal(
            _quadratic(lowered, null[item.indexes[4] - 1]),
            item.value,
            atol=1e-12 * abs(item.value) + 1e-300,
        )
    for item in reference_values("A.WEAKVEC"):
        var d = (item.indexes[5] - 1) * 10 + item.indexes[4] - 1
        assert_almost_equal(
            _quadratic(lowered, timelike[d]),
            item.value,
            atol=1e-11 * 1e41,
        )
    # The corrected null value, lowered with η, differs where g is not η.
    var corrected = energy_condition(energy, metric, NULL_ENERGY, 10, 3)
    var upstream = reference_values("A.NULL")[0].copy()
    var ours = corrected.values[_point(grid, upstream)]
    assert_true(abs(ours - upstream.value) > 0.01 * abs(upstream.value))


def test_scalars_match() raises:
    var metric = _alcubierre_a()
    var scalars = metric_scalars(metric)
    for item in reference_values("A.SCAL"):
        var point = _point(metric.grid(), item)
        var k = item.indexes[4]
        var ours = scalars.expansion[point]
        if k == 2:
            ours = scalars.shear[point]
        elif k == 3:
            ours = scalars.vorticity[point]
        assert_almost_equal(ours, item.value, atol=1e-13)


def test_flow_line_matches() raises:
    var metric = _alcubierre_a()
    var energy = stress_energy(metric, FOURTH_ORDER)
    var lines = momentum_flow_lines(
        energy, [GridPoint(3.5, 4.2, 4.0)], Compliance64(1e-42), 20
    )
    var refs = reference_values("A.FLOW42")
    assert_equal(len(lines[0]), len(refs) // 3)
    for item in refs:
        var place = lines[0][item.indexes[0] - 1]
        var ours = place.x
        if item.indexes[1] == 2:
            ours = place.y
        elif item.indexes[1] == 3:
            ours = place.z
        # WarpFactory shifts each place by 1e-8 before it interpolates.
        assert_almost_equal(ours + 1.0, item.value, atol=1e-6)


def test_moving_alcubierre_matches() raises:
    var grid = SpacetimeGrid.uniform(
        5, 9, 9, 9, Duration64(1.0 / C), Length64(1.0)
    )
    var metric = alcubierre(
        grid,
        grid.center(),
        fraction_of_light(0.5),
        Length64(2.0),
        InverseLength64(1.5),
    )
    _check_tensor("B.g", metric.tensor, 1e-15)
    var energy = stress_energy(metric, FOURTH_ORDER)
    _check_tensor("B.E4", energy.tensor, 1e-12)
    _check_tensor("B.EUL", to_eulerian(energy, metric).tensor, 1e-12)


def test_schwarzschild_matches() raises:
    var grid = SpacetimeGrid.uniform(1, 9, 9, 9, Duration64(1.0), Length64(1.0))
    var center = SpacetimeCenter(
        Duration64(1.0), Length64(5.3), Length64(5.2), Length64(5.1)
    )
    var metric = schwarzschild(grid, center, Length64(0.5))
    _check_tensor("C.g", metric.tensor, 1e-15)
    _check_tensor("C.E4", stress_energy(metric, FOURTH_ORDER).tensor, 1e-9)


def test_lentz_matches() raises:
    var grid = _grid_a()
    var metric = lentz_comoving(
        grid, grid.center(), fraction_of_light(0.1), Length64(2.0)
    )
    for item in reference_values("D.g"):
        var ours = metric.tensor.get(
            item.indexes[4] - 1, item.indexes[5] - 1, _point(grid, item)
        )
        assert_equal(ours, item.value)
    _check_tensor("D.E4", stress_energy(metric, FOURTH_ORDER).tensor, 1e-12)


def test_van_den_broeck_matches() raises:
    var grid = _grid_a()
    var metric = van_den_broeck_comoving(
        grid,
        grid.center(),
        fraction_of_light(0.1),
        Length64(1.0),
        InverseLength64(2.0),
        Length64(3.0),
        InverseLength64(1.0),
        0.5,
    )
    _check_tensor("E.g", metric.tensor, 1e-15)
    _check_tensor("E.E4", stress_energy(metric, FOURTH_ORDER).tensor, 1e-12)


def _shell(buffer: Float64, sigma: Float64) raises -> Metric:
    var grid = SpacetimeGrid.uniform(
        1, 24, 5, 5, Duration64(1.0 / (1000.0 * C)), Length64(1.0)
    )
    var center = SpacetimeCenter(
        Duration64(0.0), Length64(-2.0), Length64(3.0), Length64(3.0)
    )
    var mass = 20.0 / (2.0 * GRAVITATIONAL_CONSTANT.value) * C * C / 3.0
    return warp_shell_comoving(
        grid,
        center,
        Mass64(mass),
        Length64(10.0),
        Length64(20.0),
        Length64(buffer),
        sigma,
        1.0,
        fraction_of_light(0.02),
        True,
    )


def test_warp_shell_matches() raises:
    var metric = _shell(0.0, 0.0)
    _check_tensor("F.g", metric.tensor, 1e-12)
    var energy = stress_energy(metric, FOURTH_ORDER)
    _check_tensor("F.E4", energy.tensor, 1e-9)
    _check_tensor("F.EUL", to_eulerian(energy, metric).tensor, 1e-9)
    var buffered = _shell(1.0, 0.5)
    for item in reference_values("F2.g"):
        assert_almost_equal(
            buffered.tensor.get(0, 1, _point(buffered.grid(), item)),
            item.value,
            atol=1e-12,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
