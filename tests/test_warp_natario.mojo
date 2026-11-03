# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the Natário drive and the Krasnikov tube of `extensions.warp`.

The Natário shift is a curl, so its divergence is zero: the test checks
that from the exact jets, to rounding, and that the finite-difference
expansion is zero next to an Alcubierre bubble's. The Krasnikov metric is
flat outside the tube and has k = δ - 1 inside it.
"""

from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)

from extensions.warp.analytic import (
    exact_stress_energy,
    sample_metric,
)
from extensions.warp.frame import to_eulerian
from extensions.warp.grid import SpacetimeCenter, SpacetimeGrid
from extensions.warp.jet import Jet, jet_place
from extensions.warp.kinds import FOURTH_ORDER
from extensions.warp.krasnikov import KrasnikovMetric, krasnikov, smooth_step
from extensions.warp.metrics import (
    AlcubierreMetric,
    alcubierre_shape,
    alcubierre_shape_derivatives,
)
from extensions.warp.natario import (
    NatarioMetric,
    natario,
    natario_comoving,
    slope_over_radius,
)
from extensions.warp.quantities import SPEED_OF_LIGHT, fraction_of_light
from extensions.warp.scalars import metric_scalars
from extensions.warp.solver import stress_energy
from units.si import Duration64, InverseLength64, Length64

comptime RADIUS = 2.0
comptime SIGMA = 1.5
comptime BETA = 0.5


def _drive(comoving: Bool) raises -> NatarioMetric:
    return NatarioMetric(
        fraction_of_light(BETA),
        Length64(RADIUS),
        InverseLength64(SIGMA),
        comoving,
    )


def _local(h: Float64, x: Float64, y: Float64, z: Float64) -> SpacetimeCenter:
    """The center that puts point (2, 2, 2) of a step-h grid at (x, y, z)."""
    return SpacetimeCenter(
        Duration64(0.0),
        Length64(3.0 * h - x),
        Length64(3.0 * h - y),
        Length64(3.0 * h - z),
    )


def _divergence(g: List[Jet]) -> Float64:
    """Return ∂ᵢ βⁱ: here γ = δ, so βⁱ = β_i = g_0i."""
    return g[1].gradient[1] + g[2].gradient[2] + g[3].gradient[3]


def test_slope_over_radius() raises:
    var h = 1e-5
    for r in [0.3, 1.2, 2.2, 3.5]:
        var place = jet_place(0.0, r, 0.0, 0.0)
        var square = place[1].squared()
        var d = alcubierre_shape_derivatives(r, RADIUS, SIGMA)
        var q = slope_over_radius(square, d)
        assert_almost_equal(q.value, d[1] / (2.0 * r), atol=1e-14)
        var up = alcubierre_shape_derivatives(r + h, RADIUS, SIGMA)[1] / (
            2.0 * (r + h)
        )
        var down = alcubierre_shape_derivatives(r - h, RADIUS, SIGMA)[1] / (
            2.0 * (r - h)
        )
        assert_almost_equal(q.gradient[1], (up - down) / (2.0 * h), atol=1e-8)
    var origin = jet_place(0.0, 0.0, 0.0, 0.0)
    var zero = origin[1].squared() + origin[2].squared() + origin[3].squared()
    var d0 = alcubierre_shape_derivatives(0.0, RADIUS, SIGMA)
    var q0 = slope_over_radius(zero, d0)
    assert_almost_equal(q0.value, d0[2] / 2.0, atol=1e-15)
    assert_equal(q0.gradient[1], 0.0)
    assert_almost_equal(q0.second(2, 2), d0[4] / 6.0, atol=1e-14)


def test_natario_has_no_divergence() raises:
    var points: List[SIMD[DType.float64, 4]] = [
        SIMD[DType.float64, 4](0.0, 0.6, 1.1, -0.7),
        SIMD[DType.float64, 4](0.0, -1.9, 0.2, 0.4),
        SIMD[DType.float64, 4](1.3, 2.4, -0.5, 0.9),
        SIMD[DType.float64, 4](0.0, 0.0, 0.0, 0.0),
    ]
    for comoving in [True, False]:
        var drive = _drive(comoving)
        for p in points:
            var g = drive.components(jet_place(p[0], p[1], p[2], p[3]))
            var scale = abs(g[1].gradient[1]) + abs(g[2].gradient[2]) + 1e-3
            assert_true(abs(_divergence(g)) < 1e-14 * scale)
            # The metric is symmetric.
            for k in range(16):
                assert_equal(g[k].value, g[4 * (k % 4) + k // 4].value)


def test_natario_shift() raises:
    var moving = _drive(False)
    var still = _drive(True)
    assert_equal(moving.name(), "Natário")
    assert_equal(still.name(), "Natário Comoving")
    # Deep inside, X = v e_x; far outside, X = 0.
    var inside = moving.components(jet_place(0.0, 0.1, 0.0, 0.0))
    var f = alcubierre_shape(0.1, RADIUS, SIGMA)
    assert_true(abs(inside[1].value + BETA * f) < 1e-3)
    assert_true(abs(inside[2].value) < 1e-12)
    var outside = still.components(jet_place(0.0, 9.0, 3.0, 0.0))
    assert_almost_equal(outside[1].value, BETA, atol=1e-12)
    assert_almost_equal(outside[0].value, -1.0 + BETA * BETA, atol=1e-12)
    var center = still.components(jet_place(0.0, 0.0, 0.0, 0.0))
    var f0 = alcubierre_shape(0.0, RADIUS, SIGMA)
    assert_almost_equal(center[1].value, BETA * (1.0 - f0), atol=1e-15)


def test_natario_expansion_is_zero() raises:
    var h = 0.05
    var grid = SpacetimeGrid.uniform(1, 5, 5, 5, Duration64(1.0), Length64(h))
    var center = _local(h, 0.9, -0.6, 0.4)
    var point = grid.index(0, 2, 2, 2)
    var zero = metric_scalars(sample_metric(_drive(True), grid, center))
    var bubble = AlcubierreMetric(
        fraction_of_light(BETA),
        Length64(RADIUS),
        InverseLength64(SIGMA),
        True,
    )
    var alcubierre = metric_scalars(sample_metric(bubble, grid, center))
    var reference = abs(alcubierre.expansion[point])
    assert_true(reference > 0.01)
    assert_true(abs(zero.expansion[point]) < 1e-5 * reference)
    assert_true(zero.shear[point] > 0.0)


def test_natario_energy() raises:
    var h = 0.05
    var grid = SpacetimeGrid.uniform(1, 5, 5, 5, Duration64(1.0), Length64(h))
    var center = _local(h, 0.9, -0.6, 0.4)
    var point = grid.index(0, 2, 2, 2)
    var drive = _drive(True)
    var metric = natario_comoving(
        grid,
        center,
        fraction_of_light(BETA),
        Length64(RADIUS),
        InverseLength64(SIGMA),
    )
    assert_equal(metric.name, "Natário Comoving")
    var by_grid = to_eulerian(stress_energy(metric, FOURTH_ORDER), metric)
    var exact = to_eulerian(exact_stress_energy(drive, grid, center), metric)
    var rho = exact.tensor.get(0, 0, point)
    # The Eulerian energy density is negative: K_ij K^ij > 0 and K = 0.
    assert_true(rho < 0.0)
    assert_almost_equal(
        by_grid.tensor.get(0, 0, point), rho, atol=1e-4 * abs(rho)
    )
    # At the center of the bubble the exact derivatives exist.
    var middle = SpacetimeGrid.uniform(
        1, 1, 1, 1, Duration64(1.0), Length64(1.0)
    )
    var origin = SpacetimeCenter(
        Duration64(0.0), Length64(1.0), Length64(1.0), Length64(1.0)
    )
    var at_center = exact_stress_energy(drive, middle, origin)
    for k in range(16):
        assert_true(abs(at_center.tensor.matrix(0)[k]) < inf[DType.float64]())


def test_natario_builders() raises:
    var moving = SpacetimeGrid.uniform(
        3, 3, 3, 3, Duration64(1.0 / SPEED_OF_LIGHT.value), Length64(1.0)
    )
    var metric = natario(
        moving,
        moving.center(),
        fraction_of_light(BETA),
        Length64(RADIUS),
        InverseLength64(SIGMA),
    )
    assert_equal(metric.name, "Natário")
    with assert_raises(contains="one time slice"):
        _ = natario_comoving(
            moving,
            moving.center(),
            fraction_of_light(BETA),
            Length64(RADIUS),
            InverseLength64(SIGMA),
        )
    with assert_raises(contains="bubble radius"):
        _ = NatarioMetric(
            fraction_of_light(BETA), Length64(0.0), InverseLength64(1.0), True
        )


def test_smooth_step() raises:
    assert_equal(smooth_step(-0.5, 2.0)[0], 0.0)
    assert_equal(smooth_step(0.0, 2.0)[1], 0.0)
    assert_equal(smooth_step(2.0, 2.0)[0], 1.0)
    assert_equal(smooth_step(5.0, 2.0)[2], 0.0)
    var half = smooth_step(1.0, 2.0)
    assert_almost_equal(half[0], 0.5, atol=1e-15)
    var h = 1e-5
    for x in [0.3, 1.0, 1.7]:
        var s = smooth_step(x, 2.0)
        var up = smooth_step(x + h, 2.0)
        var down = smooth_step(x - h, 2.0)
        assert_almost_equal(s[1], (up[0] - down[0]) / (2.0 * h), atol=1e-8)
        assert_almost_equal(s[2], (up[1] - down[1]) / (2.0 * h), atol=1e-7)


def _tube() raises -> KrasnikovMetric:
    return KrasnikovMetric(0.5, Length64(0.5), Length64(10.0), Length64(2.0))


def test_krasnikov_regions() raises:
    var tube = _tube()
    assert_equal(tube.name(), "Krasnikov")
    # Inside: c t - x > ε, ε < x < D - ε, ρ < ρ_max - ε.
    var inside = tube.components(jet_place(20.0, 5.0, 0.3, -0.4))
    assert_equal(inside[5].value, 0.5 - 1.0)
    assert_equal(inside[1].value, (2.0 - 0.5) / 2.0)
    assert_equal(inside[0].value, -1.0)
    # Before the ship passes, beyond the tube's end, and outside it: flat.
    var places: List[SIMD[DType.float64, 4]] = [
        SIMD[DType.float64, 4](2.0, 5.0, 0.0, 0.0),
        SIMD[DType.float64, 4](20.0, 12.0, 0.0, 0.0),
        SIMD[DType.float64, 4](20.0, -3.0, 0.0, 0.0),
        SIMD[DType.float64, 4](20.0, 5.0, 2.5, 0.0),
    ]
    for p in places:
        var g = tube.components(jet_place(p[0], p[1], p[2], p[3]))
        assert_equal(g[5].value, 1.0)
        assert_equal(g[1].value, 0.0)
    # In the wall the tube changes with ρ.
    var wall = tube.k(jet_place(20.0, 5.0, 1.75, 0.0))
    assert_true(wall.value > -0.5 and wall.value < 1.0)
    assert_true(wall.gradient[2] > 0.0)


def test_krasnikov_stress_energy() raises:
    var tube = _tube()
    var h = 0.02
    var grid = SpacetimeGrid.uniform(
        5, 5, 5, 5, Duration64(h / SPEED_OF_LIGHT.value), Length64(h)
    )
    # A point in the side wall, after the ship has passed.
    var center = SpacetimeCenter(
        Duration64(
            3.0 * h / SPEED_OF_LIGHT.value - 20.0 / SPEED_OF_LIGHT.value
        ),
        Length64(3.0 * h - 5.0),
        Length64(3.0 * h - 1.7),
        Length64(3.0 * h - 0.1),
    )
    var point = grid.index(2, 2, 2, 2)
    var metric = krasnikov(
        grid, center, 0.5, Length64(0.5), Length64(10.0), Length64(2.0)
    )
    assert_equal(metric.name, "Krasnikov")
    var by_grid = stress_energy(metric, FOURTH_ORDER).tensor.matrix(point)
    var exact = exact_stress_energy(tube, grid, center).tensor.matrix(point)
    var scale = 0.0
    for k in range(16):
        scale = max(scale, abs(exact[k]))
    assert_true(scale > 0.0)
    for k in range(16):
        assert_almost_equal(by_grid[k], exact[k], atol=1e-3 * scale)


def test_krasnikov_has_no_eulerian_frame_inside() raises:
    var grid = SpacetimeGrid.uniform(1, 1, 1, 1, Duration64(1.0), Length64(1.0))
    var center = SpacetimeCenter(
        Duration64(1.0 - 20.0 / SPEED_OF_LIGHT.value),
        Length64(1.0 - 5.0),
        Length64(1.0),
        Length64(1.0),
    )
    var tube = _tube()
    var metric = sample_metric(tube, grid, center)
    assert_equal(metric.at(0)[5], -0.5)
    with assert_raises(contains="no Eulerian frame"):
        _ = to_eulerian(exact_stress_energy(tube, grid, center), metric)


def test_krasnikov_refusals() raises:
    var w = Length64(0.5)
    var d = Length64(10.0)
    var r = Length64(2.0)
    var bad = Length64(nan[DType.float64]())
    with assert_raises(contains="must be finite"):
        _ = KrasnikovMetric(inf[DType.float64](), w, d, r)
    with assert_raises(contains="must be finite"):
        _ = KrasnikovMetric(0.5, bad, d, r)
    with assert_raises(contains="must be finite"):
        _ = KrasnikovMetric(0.5, w, bad, r)
    with assert_raises(contains="must be finite"):
        _ = KrasnikovMetric(0.5, w, d, bad)
    with assert_raises(contains="0 < delta < 2"):
        _ = KrasnikovMetric(0.0, w, d, r)
    with assert_raises(contains="0 < delta < 2"):
        _ = KrasnikovMetric(2.0, w, d, r)
    with assert_raises(contains="0 < wall"):
        _ = KrasnikovMetric(0.5, Length64(0.0), d, r)
    with assert_raises(contains="0 < wall"):
        _ = KrasnikovMetric(0.5, w, Length64(0.5), r)
    with assert_raises(contains="0 < wall"):
        _ = KrasnikovMetric(0.5, w, d, Length64(0.25))
    with assert_raises(contains="center must be finite"):
        _ = krasnikov(
            SpacetimeGrid.uniform(1, 1, 1, 1, Duration64(1.0), Length64(1.0)),
            SpacetimeCenter(Duration64(0.0), bad, Length64(0.0), Length64(0.0)),
            0.5,
            w,
            d,
            r,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
