# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the Einstein-equation solver and the Eulerian frame of
`extensions.warp`.

The independent references are:

- Flat space has no curvature.
- The Schwarzschild metric is a vacuum: its Ricci tensor is zero.
- The Eulerian energy density of the Alcubierre metric is
  -c⁴/(8 π G) (v²/4) ((y² + z²)/r²) (df/dr)², from Alcubierre,
  "The warp drive: hyper-fast travel within general relativity",
  Classical and Quantum Gravity 11 (1994) L73, equation 19.
- A perfect fluid at rest for the Eulerian observer has the components
  diag(ρ, p, p, p) in that observer's frame.

The derivatives are local, so most tests use a grid of 5 by 5 by 5
points around the point that they check.
"""

from std.math import cosh, sqrt, tanh
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)

from extensions.warp.frame import eulerian_transform, to_eulerian
from extensions.warp.grid import SpacetimeCenter, SpacetimeGrid
from extensions.warp.kinds import (
    CONTRAVARIANT,
    COORDINATE_FRAME,
    COVARIANT,
    DifferenceOrder,
    EULERIAN_FRAME,
    FOURTH_ORDER,
    SECOND_ORDER,
)
from extensions.warp.metrics import (
    alcubierre,
    alcubierre_comoving,
    minkowski,
    schwarzschild,
)
from extensions.warp.quantities import (
    SPEED_OF_LIGHT,
    einstein_coupling,
    fraction_of_light,
)
from extensions.warp.solver import StressEnergy, curvature, stress_energy
from extensions.warp.tensor import (
    MINKOWSKI,
    Matrix4,
    Metric,
    TensorField,
    inverse4,
    multiply4,
    transpose4,
)
from extensions.warp.three_plus_one import ThreePlusOne
from units.si import Duration64, InverseLength64, Length64

comptime RADIUS = 2.0
comptime SIGMA = 1.5
comptime BETA = 0.5


def _around(h: Float64) raises -> SpacetimeGrid:
    return SpacetimeGrid.uniform(1, 5, 5, 5, Duration64(1.0), Length64(h))


def _center_on(
    h: Float64, x: Float64, y: Float64, z: Float64
) -> SpacetimeCenter:
    """Return the center that puts point (2, 2, 2) at (x, y, z)."""
    return SpacetimeCenter(
        Duration64(0.0),
        Length64(3.0 * h - x),
        Length64(3.0 * h - y),
        Length64(3.0 * h - z),
    )


def _analytic_density(x: Float64, y: Float64, z: Float64) -> Float64:
    var r = sqrt(x * x + y * y + z * z)
    var df = (
        SIGMA
        * (
            1.0 / cosh(SIGMA * (RADIUS + r)) ** 2
            - 1.0 / cosh(SIGMA * (RADIUS - r)) ** 2
        )
        / (2.0 * tanh(SIGMA * RADIUS))
    )
    return (
        -einstein_coupling()
        * BETA
        * BETA
        / 4.0
        * (y * y + z * z)
        / (r * r)
        * df
        * df
    )


def _density(
    h: Float64, x: Float64, y: Float64, z: Float64, order: DifferenceOrder
) raises -> Float64:
    var grid = _around(h)
    var metric = alcubierre_comoving(
        grid,
        _center_on(h, x, y, z),
        fraction_of_light(BETA),
        Length64(RADIUS),
        InverseLength64(SIGMA),
    )
    var eulerian = to_eulerian(stress_energy(metric, order), metric)
    return eulerian.tensor.get(0, 0, grid.index(0, 2, 2, 2))


def test_flat_space_is_empty() raises:
    var grid = SpacetimeGrid.uniform(5, 5, 1, 1, Duration64(1.0), Length64(1.0))
    var metric = minkowski(grid)
    var energy = stress_energy(metric)
    assert_equal(energy.name, "Minkowski")
    assert_equal(energy.order, FOURTH_ORDER)
    assert_equal(energy.tensor.index, CONTRAVARIANT)
    assert_equal(energy.tensor.frame, COORDINATE_FRAME)
    for k in range(len(energy.tensor.data)):
        assert_equal(energy.tensor.data[k], 0.0)
    var bent = curvature(metric, SECOND_ORDER)
    assert_equal(bent.scalar_at(12).value, 0.0)
    assert_equal(bent.ricci.get(1, 2, 12), 0.0)


def test_alcubierre_energy_density() raises:
    var x = 0.6
    var y = 1.1
    var z = -0.7
    var exact = _analytic_density(x, y, z)
    assert_true(exact < 0.0)
    var coarse = _density(0.1, x, y, z, FOURTH_ORDER)
    var fine = _density(0.05, x, y, z, FOURTH_ORDER)
    var coarse_error = abs(coarse - exact)
    var fine_error = abs(fine - exact)
    assert_true(fine_error < 1e-4 * abs(exact))
    # Fourth order: half the step gives about a sixteenth of the error.
    assert_true(coarse_error / fine_error > 12.0)
    assert_true(coarse_error / fine_error < 20.0)
    var second = _density(0.05, x, y, z, SECOND_ORDER)
    var second_error = abs(second - exact)
    assert_true(second_error < 5e-3 * abs(exact))
    assert_true(second_error > fine_error)


def test_moving_bubble_matches_comoving_one() raises:
    # Five time slices, with the bubble at the origin in the middle one.
    var h = 0.1
    var x = 0.6
    var y = 1.1
    var z = -0.7
    var dt = h / SPEED_OF_LIGHT.value
    var grid = SpacetimeGrid.uniform(5, 5, 5, 5, Duration64(dt), Length64(h))
    var center = _center_on(h, x, y, z)
    center.time = Duration64(3.0 * dt)
    var metric = alcubierre(
        grid,
        center,
        fraction_of_light(BETA),
        Length64(RADIUS),
        InverseLength64(SIGMA),
    )
    var eulerian = to_eulerian(stress_energy(metric), metric)
    var moving = eulerian.tensor.get(0, 0, grid.index(2, 2, 2, 2))
    var still = _density(h, x, y, z, FOURTH_ORDER)
    assert_almost_equal(moving, still, atol=1e-3 * abs(still))


def _vacuum_residual(h: Float64) raises -> Float64:
    """Return the largest Ricci component of the Schwarzschild metric at
    (1.2, -0.9, 0.5), over the tidal curvature rs / r³ there."""
    var rs = 0.2
    var grid = _around(h)
    var metric = schwarzschild(
        grid, _center_on(h, 1.2, -0.9, 0.5), Length64(rs)
    )
    var bent = curvature(metric)
    var point = grid.index(0, 2, 2, 2)
    var r = sqrt(1.2 * 1.2 + 0.9 * 0.9 + 0.25)
    var largest = abs(bent.scalar[point])
    for k in range(16):
        largest = max(largest, abs(bent.ricci.matrix(point)[k]))
        largest = max(largest, abs(bent.einstein.matrix(point)[k]))
    return largest / (rs / (r * r * r))


def test_schwarzschild_is_a_vacuum() raises:
    var coarse = _vacuum_residual(0.1)
    var fine = _vacuum_residual(0.05)
    # The residual is the truncation error of the stencils: it falls with
    # the fourth power of the step.
    assert_true(fine < 5e-5)
    assert_true(coarse / fine > 12.0)


def test_curvature_matches_stress_energy() raises:
    var h = 0.1
    var grid = _around(h)
    var metric = alcubierre_comoving(
        grid,
        _center_on(h, 0.6, 1.1, -0.7),
        fraction_of_light(BETA),
        Length64(RADIUS),
        InverseLength64(SIGMA),
    )
    var bent = curvature(metric)
    var energy = stress_energy(metric)
    var point = grid.index(0, 2, 2, 2)
    var g = metric.at(point)
    var gu = inverse4(g)
    var r = bent.ricci.matrix(point)
    var e = bent.einstein.matrix(point)
    var s = bent.scalar[point]
    var expected = multiply4(multiply4(gu, e), gu) * einstein_coupling()
    for k in range(16):
        assert_almost_equal(e[k], r[k] - 0.5 * s * g[k], atol=1e-15)
        assert_almost_equal(
            energy.component(k // 4, k % 4, point).value,
            expected[k],
            atol=1e-9 * abs(expected[0]),
        )


def test_solver_refusals() raises:
    var grid = _around(1.0)
    var metric = minkowski(grid)
    with assert_raises(contains="order is not valid"):
        _ = stress_energy(metric, DifferenceOrder(5))
    with assert_raises(contains="order is not valid"):
        _ = curvature(metric, DifferenceOrder(-1))
    var zero = Metric(TensorField(grid, COVARIANT, COORDINATE_FRAME), "zero")
    with assert_raises(contains="singular"):
        _ = stress_energy(zero)
    with assert_raises(contains="singular"):
        _ = curvature(zero)


def _tilted(grid: SpacetimeGrid) raises -> Metric:
    var parts = ThreePlusOne(grid)
    for point in range(grid.points()):
        parts.lapse[point] = 1.5
        parts.set_shift(0, point, 0.25)
        parts.set_shift(2, point, -0.125)
        parts.set_spatial(0, 0, point, 2.0)
        parts.set_spatial(0, 1, point, 0.5)
        parts.set_spatial(1, 2, point, -0.25)
        parts.set_spatial(2, 2, point, 1.5)
    return parts.metric("tilted")


def test_eulerian_transform() raises:
    var grid = SpacetimeGrid.uniform(1, 2, 2, 2, Duration64(1.0), Length64(1.0))
    var metric = _tilted(grid)
    var g = metric.at(3)
    var m = eulerian_transform(g)
    var flat = multiply4(multiply4(transpose4(m), g), m)
    for k in range(16):
        assert_almost_equal(flat[k], MINKOWSKI[k], atol=1e-14)
    # M is lower triangular with a positive diagonal.
    for row in range(4):
        assert_true(m[5 * row] > 0.0)
        for col in range(row + 1, 4):
            assert_equal(m[4 * row + col], 0.0)
    # Column 0 is the Eulerian observer, (1, -βⁱ) / α.
    assert_almost_equal(m[0], 1.0 / 1.5, atol=1e-15)
    var identity = eulerian_transform(MINKOWSKI)
    for k in range(16):
        assert_almost_equal(identity[k], (MINKOWSKI * MINKOWSKI)[k], atol=0.0)
    # Two time directions: no Eulerian frame.
    var bad = Matrix4(-1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
    with assert_raises(contains="no Eulerian frame"):
        _ = eulerian_transform(bad)


def test_to_eulerian() raises:
    var grid = SpacetimeGrid.uniform(1, 2, 2, 2, Duration64(1.0), Length64(1.0))
    var metric = _tilted(grid)
    # A chosen tensor in the Eulerian frame, with momentum and shear.
    var chosen = Matrix4(
        5.0,
        0.5,
        -0.25,
        0.75,
        0.5,
        2.0,
        0.1,
        0.2,
        -0.25,
        0.1,
        1.5,
        -0.3,
        0.75,
        0.2,
        -0.3,
        1.0,
    )
    var coordinate = TensorField(grid, COVARIANT, COORDINATE_FRAME)
    for point in range(grid.points()):
        var m_inv = inverse4(eulerian_transform(metric.at(point)))
        var lowered = multiply4(multiply4(MINKOWSKI, chosen), MINKOWSKI)
        coordinate.set_matrix(
            point, multiply4(multiply4(transpose4(m_inv), lowered), m_inv)
        )
    var energy = StressEnergy(coordinate^, "chosen", FOURTH_ORDER)
    var eulerian = to_eulerian(energy, metric)
    assert_equal(eulerian.tensor.frame, EULERIAN_FRAME)
    assert_equal(eulerian.tensor.index, CONTRAVARIANT)
    assert_equal(eulerian.name, "chosen")
    var back = eulerian.tensor.matrix(5)
    for k in range(16):
        assert_almost_equal(back[k], chosen[k], atol=1e-13)
    # A tensor in the Eulerian frame already is returned unchanged.
    var again = to_eulerian(eulerian, metric)
    for k in range(16):
        assert_equal(again.tensor.matrix(5)[k], back[k])
    with assert_raises(contains="share one grid"):
        _ = to_eulerian(
            energy,
            minkowski(
                SpacetimeGrid.uniform(
                    1, 3, 2, 2, Duration64(1.0), Length64(1.0)
                )
            ),
        )
    var two_times = TensorField(grid, COVARIANT, COORDINATE_FRAME)
    for point in range(grid.points()):
        two_times.set_matrix(
            point, Matrix4(-1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
        )
    with assert_raises(contains="no Eulerian frame"):
        _ = to_eulerian(energy, Metric(two_times^, "bad"))


def test_perfect_fluid() raises:
    var grid = SpacetimeGrid.uniform(1, 2, 2, 2, Duration64(1.0), Length64(1.0))
    var metric = _tilted(grid)
    var rho = 3.0
    var p = 0.5
    var fluid = TensorField(grid, CONTRAVARIANT, COORDINATE_FRAME)
    for point in range(grid.points()):
        var g = metric.at(point)
        var gu = inverse4(g)
        var n = eulerian_transform(g)
        var t = Matrix4(0)
        for a in range(4):
            for b in range(4):
                t[4 * a + b] = (rho + p) * n[4 * a] * n[4 * b] + p * gu[
                    4 * a + b
                ]
        fluid.set_matrix(point, t)
    var eulerian = to_eulerian(
        StressEnergy(fluid^, "fluid", FOURTH_ORDER), metric
    )
    var e = eulerian.tensor.matrix(0)
    var expected = Matrix4(rho, 0, 0, 0, 0, p, 0, 0, 0, 0, p, 0, 0, 0, 0, p)
    for k in range(16):
        assert_almost_equal(e[k], expected[k], atol=1e-13)


def test_energy_has_units() raises:
    var grid = _around(1.0)
    var fluid = TensorField(grid, CONTRAVARIANT, COORDINATE_FRAME)
    fluid.set(0, 0, 4, 7.0)
    var energy = StressEnergy(fluid^, "x", SECOND_ORDER)
    assert_equal(energy.component(0, 0, 4).value, 7.0)
    assert_equal(energy.order, SECOND_ORDER)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
