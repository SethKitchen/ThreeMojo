# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the jets and the exact derivatives of `extensions.warp`.

The jets are checked against derivatives worked out by hand. The exact
solver is checked against the same references as the finite-difference
solver, but to rounding error: Alcubierre's closed-form energy density,
and the vacuum of the Schwarzschild metric. Along the x axis outside a
mass, Γˣ_00 = (rₛ / 2 r²)(1 - rₛ / r).
"""

from std.math import cosh, exp, inf, log, nan, sqrt, tanh
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)

from extensions.warp.analytic import (
    christoffel_symbols,
    exact_curvature,
    exact_stress_energy,
    flat_components,
    place_jets,
    radial,
    sample_metric,
)
from extensions.warp.frame import to_eulerian
from extensions.warp.grid import SpacetimeCenter, SpacetimeGrid
from extensions.warp.jet import Jet, jet_place
from extensions.warp.kinds import EXACT_DERIVATIVES, FOURTH_ORDER
from extensions.warp.metrics import (
    AlcubierreMetric,
    MinkowskiMetric,
    ModifiedTimeMetric,
    SchwarzschildMetric,
    VanDenBroeckMetric,
    alcubierre_shape,
    alcubierre_shape_derivatives,
)
from extensions.warp.quantities import (
    SPEED_OF_LIGHT,
    einstein_coupling,
    fraction_of_light,
)
from extensions.warp.solver import stress_energy
from units.si import Duration64, InverseLength64, Length64

comptime RADIUS = 2.0
comptime SIGMA = 1.5
comptime BETA = 0.5


def _at(x: Float64, y: Float64, z: Float64) raises -> SpacetimeCenter:
    """The center that puts point (0, 0, 0) of a unit grid at (x, y, z)."""
    return SpacetimeCenter(
        Duration64(0.0), Length64(1.0 - x), Length64(1.0 - y), Length64(1.0 - z)
    )


def _one() raises -> SpacetimeGrid:
    return SpacetimeGrid.uniform(1, 1, 1, 1, Duration64(1.0), Length64(1.0))


def _bubble(comoving: Bool) raises -> AlcubierreMetric:
    return AlcubierreMetric(
        fraction_of_light(BETA),
        Length64(RADIUS),
        InverseLength64(SIGMA),
        comoving,
    )


def _density(x: Float64, y: Float64, z: Float64) -> Float64:
    var r = sqrt(x * x + y * y + z * z)
    var df = alcubierre_shape_derivatives(r, RADIUS, SIGMA)[1]
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


def test_jet_arithmetic() raises:
    var p = jet_place(0.5, 2.0, 3.0, -1.0)
    var x = p[1]
    var y = p[2]
    # f = x² y: ∂x = 2 x y, ∂y = x², ∂x∂x = 2 y, ∂x∂y = 2 x.
    var f = x * x * y
    assert_equal(f.value, 12.0)
    assert_equal(f.gradient[1], 12.0)
    assert_equal(f.gradient[2], 4.0)
    assert_equal(f.second(1, 1), 6.0)
    assert_equal(f.second(1, 2), 4.0)
    assert_equal(f.second(2, 1), 4.0)
    assert_equal(f.second(2, 2), 0.0)
    # g = x / y: ∂x∂y = -1 / y².
    var g = x / y
    assert_almost_equal(g.value, 2.0 / 3.0, atol=1e-15)
    assert_almost_equal(g.gradient[2], -2.0 / 9.0, atol=1e-15)
    assert_almost_equal(g.second(1, 2), -1.0 / 9.0, atol=1e-15)
    assert_almost_equal(g.second(2, 2), 4.0 / 27.0, atol=1e-15)
    var h = (x - y).squared() + (-x).scaled(2.0).shifted(1.0)
    assert_equal(h.value, 1.0 - 4.0 + 1.0)
    assert_equal(h.second(1, 2), -2.0)
    var c = Jet.constant(3.0)
    assert_equal(c.gradient[1], 0.0)
    assert_equal((c * x).gradient[1], 3.0)


def test_jet_functions() raises:
    var x = Jet.variable(0.7, 1)
    var s = x.sqrt()
    assert_almost_equal(s.value, sqrt(0.7), atol=1e-15)
    assert_almost_equal(s.gradient[1], 0.5 / sqrt(0.7), atol=1e-15)
    assert_almost_equal(s.second(1, 1), -0.25 / 0.7**1.5, atol=1e-14)
    var t = x.tanh()
    var sech2 = 1.0 / cosh(0.7) ** 2
    assert_almost_equal(t.gradient[1], sech2, atol=1e-15)
    assert_almost_equal(t.second(1, 1), -2.0 * tanh(0.7) * sech2, atol=1e-15)
    var e = x.exp()
    assert_almost_equal(e.second(1, 1), exp(0.7), atol=1e-15)
    var l = x.log()
    assert_almost_equal(l.value, log(0.7), atol=1e-15)
    assert_almost_equal(l.second(1, 1), -1.0 / 0.49, atol=1e-14)
    var r = x.reciprocal()
    assert_almost_equal(r.second(1, 1), 2.0 / 0.343, atol=1e-13)


def test_radial() raises:
    # f(r) = r² through r² is r² itself, also at r = 0.
    var p = jet_place(0.0, 0.3, -0.4, 1.2)
    var square = p[1].squared() + p[2].squared() + p[3].squared()
    var r = sqrt(square.value)
    var same = radial(square, r * r, 2.0 * r, 2.0)
    for k in range(4):
        assert_almost_equal(same.gradient[k], square.gradient[k], atol=1e-14)
    for k in range(16):
        assert_almost_equal(same.hessian[k], square.hessian[k], atol=1e-14)
    var origin = jet_place(0.0, 0.0, 0.0, 0.0)
    var zero = origin[1].squared() + origin[2].squared() + origin[3].squared()
    var at_zero = radial(zero, 0.0, 0.0, 2.0)
    assert_equal(at_zero.gradient[1], 0.0)
    assert_equal(at_zero.second(1, 1), 2.0)
    assert_equal(at_zero.second(1, 2), 0.0)


def test_shape_derivatives() raises:
    var h = 1e-4
    for r in [0.0, 0.5, 1.9, 2.4, 4.0]:
        var d = alcubierre_shape_derivatives(r, RADIUS, SIGMA)
        assert_almost_equal(
            d[0], alcubierre_shape(r, RADIUS, SIGMA), atol=1e-15
        )
        var up = alcubierre_shape(r + h, RADIUS, SIGMA)
        var down = alcubierre_shape(r - h, RADIUS, SIGMA)
        var mid = alcubierre_shape(r, RADIUS, SIGMA)
        assert_almost_equal(d[1], (up - down) / (2.0 * h), atol=1e-7)
        assert_almost_equal(d[2], (up - 2.0 * mid + down) / (h * h), atol=1e-5)
        # The third and fourth from differences of the first and second.
        var d_up = alcubierre_shape_derivatives(r + h, RADIUS, SIGMA)
        var d_down = alcubierre_shape_derivatives(r - h, RADIUS, SIGMA)
        assert_almost_equal(d[3], (d_up[2] - d_down[2]) / (2.0 * h), atol=1e-6)
        assert_almost_equal(d[4], (d_up[3] - d_down[3]) / (2.0 * h), atol=1e-5)
        assert_equal(d[5], 0.0)


def test_exact_alcubierre_density() raises:
    var grid = _one()
    for i in range(3):
        var x = [0.6, -1.3, 2.1][i]
        var y = [1.1, 0.4, -0.2][i]
        var z = [-0.7, 0.9, 0.3][i]
        var center = _at(x, y, z)
        var bubble = _bubble(True)
        var energy = exact_stress_energy(bubble, grid, center)
        assert_equal(energy.order, EXACT_DERIVATIVES)
        assert_equal(energy.name, "Alcubierre Comoving")
        var metric = sample_metric(bubble, grid, center)
        var eulerian = to_eulerian(energy, metric)
        var exact = _density(x, y, z)
        assert_almost_equal(
            eulerian.tensor.get(0, 0, 0), exact, atol=1e-11 * abs(exact)
        )


def test_exact_at_the_center() raises:
    var grid = _one()
    var center = _at(0.0, 0.0, 0.0)
    var bubble = _bubble(True)
    var energy = exact_stress_energy(bubble, grid, center)
    var metric = sample_metric(bubble, grid, center)
    var rho = to_eulerian(energy, metric).tensor.get(0, 0, 0)
    assert_equal(rho, 0.0)


def test_exact_matches_finite_differences() raises:
    # The middle point of a 5 by 5 by 5 grid of step h.
    var h = 0.05
    var grid = SpacetimeGrid.uniform(1, 5, 5, 5, Duration64(1.0), Length64(h))
    var center = SpacetimeCenter(
        Duration64(0.0),
        Length64(3.0 * h - 0.6),
        Length64(3.0 * h - 1.1),
        Length64(3.0 * h + 0.7),
    )
    var point = grid.index(0, 2, 2, 2)
    var metrics = List[ModifiedTimeMetric]()
    metrics.append(
        ModifiedTimeMetric(
            fraction_of_light(BETA),
            Length64(RADIUS),
            InverseLength64(SIGMA),
            2.0,
            True,
        )
    )
    var shifted = ModifiedTimeMetric(
        fraction_of_light(BETA),
        Length64(RADIUS),
        InverseLength64(SIGMA),
        2.0,
        False,
    )
    assert_equal(shifted.name(), "Modified Time")
    assert_equal(metrics[0].name(), "Modified Time Comoving")
    var sampled = sample_metric(metrics[0], grid, center)
    var by_grid = stress_energy(sampled, FOURTH_ORDER).tensor.matrix(point)
    var exact = exact_stress_energy(metrics[0], grid, center).tensor.matrix(
        point
    )
    var scale = 0.0
    for k in range(16):
        scale = max(scale, abs(exact[k]))
    for k in range(16):
        assert_almost_equal(by_grid[k], exact[k], atol=1e-4 * scale)
    var broeck = VanDenBroeckMetric(
        fraction_of_light(0.1),
        Length64(0.5),
        InverseLength64(2.0),
        Length64(1.5),
        InverseLength64(1.0),
        0.5,
        True,
    )
    var vdb_grid = stress_energy(
        sample_metric(broeck, grid, center), FOURTH_ORDER
    ).tensor.matrix(point)
    var vdb_exact = exact_stress_energy(broeck, grid, center).tensor.matrix(
        point
    )
    scale = 0.0
    for k in range(16):
        scale = max(scale, abs(vdb_exact[k]))
    for k in range(16):
        assert_almost_equal(vdb_grid[k], vdb_exact[k], atol=1e-3 * scale)


def test_moving_bubble_is_exact_too() raises:
    # At c t = 0 the moving bubble sits at the origin.
    var grid = _one()
    var center = SpacetimeCenter(
        Duration64(1.0), Length64(1.0 - 0.6), Length64(1.0 - 1.1), Length64(1.7)
    )
    var moving = _bubble(False)
    assert_equal(moving.name(), "Alcubierre")
    var energy = exact_stress_energy(moving, grid, center)
    var metric = sample_metric(moving, grid, center)
    var rho = to_eulerian(energy, metric).tensor.get(0, 0, 0)
    var exact = _density(0.6, 1.1, -0.7)
    assert_almost_equal(rho, exact, atol=1e-11 * abs(exact))
    var broeck = VanDenBroeckMetric(
        fraction_of_light(0.1),
        Length64(0.5),
        InverseLength64(2.0),
        Length64(1.5),
        InverseLength64(1.0),
        0.5,
        False,
    )
    assert_equal(broeck.name(), "Van Den Broeck")
    var t = exact_stress_energy(broeck, grid, center).tensor.matrix(0)
    for k in range(16):
        assert_true(abs(t[k]) < inf[DType.float64]())


def test_exact_vacuum() raises:
    var grid = _one()
    var hole = SchwarzschildMetric(Length64(0.2))
    assert_equal(hole.name(), "Schwarzschild")
    var bent = exact_curvature(hole, grid, _at(1.2, -0.9, 0.5))
    var r = sqrt(1.2 * 1.2 + 0.81 + 0.25)
    var tidal = 0.2 / (r * r * r)
    # WarpFactory's offset of 1e-10 m in r leaves a residual near 1e-9 of
    # the tidal curvature; the finite differences leave 1e-5.
    for k in range(16):
        assert_true(abs(bent.ricci.matrix(0)[k]) < 1e-8 * tidal)
        assert_true(abs(bent.einstein.matrix(0)[k]) < 1e-8 * tidal)
    assert_true(abs(bent.scalar[0]) < 1e-8 * tidal)
    var flat = exact_stress_energy(MinkowskiMetric(), grid, _at(0.3, 0.2, 0.1))
    for k in range(16):
        assert_equal(flat.tensor.matrix(0)[k], 0.0)
    assert_equal(MinkowskiMetric().name(), "Minkowski")


def test_christoffel_symbols() raises:
    var rs = 0.2
    var hole = SchwarzschildMetric(Length64(rs))
    var x = 1.5
    var gamma = christoffel_symbols(
        hole, SIMD[DType.float64, 4](0.0, x, 0.0, 0.0)
    )
    var r = x + 1e-10
    assert_almost_equal(
        gamma[16 * 1 + 0], rs / (2.0 * r * r) * (1.0 - rs / r), atol=1e-14
    )
    # Symmetric in the lower indices.
    var bubble = christoffel_symbols(
        _bubble(True), SIMD[DType.float64, 4](0.0, 0.6, 1.1, -0.7)
    )
    for a in range(4):
        for b in range(4):
            for c in range(4):
                assert_almost_equal(
                    bubble[16 * a + 4 * b + c],
                    bubble[16 * a + 4 * c + b],
                    atol=1e-15,
                )
    var none = christoffel_symbols(
        MinkowskiMetric(), SIMD[DType.float64, 4](1.0, 2.0, 3.0, 4.0)
    )
    for k in range(64):
        assert_equal(none[k], 0.0)


def test_place_jets() raises:
    var grid = SpacetimeGrid.uniform(
        3, 2, 2, 2, Duration64(2.0 / SPEED_OF_LIGHT.value), Length64(0.5)
    )
    var center = grid.center()
    var jets = place_jets(grid, center, grid.index(2, 1, 0, 1))
    assert_almost_equal(jets[0].value, 3.0 * 2.0 - 4.0, atol=1e-9)
    assert_equal(jets[1].value, 0.25)
    assert_equal(jets[2].value, -0.25)
    assert_equal(jets[0].gradient[0], 1.0)
    assert_equal(jets[3].gradient[3], 1.0)
    var flat = flat_components()
    assert_equal(flat[0].value, -1.0)
    assert_equal(flat[5].value, 1.0)
    assert_equal(flat[1].value, 0.0)


def test_exact_refusals() raises:
    var grid = _one()
    var bad = SpacetimeCenter(
        Duration64(nan[DType.float64]()),
        Length64(0.0),
        Length64(0.0),
        Length64(0.0),
    )
    var bubble = _bubble(True)
    with assert_raises(contains="center must be finite"):
        _ = sample_metric(bubble, grid, bad)
    with assert_raises(contains="center must be finite"):
        _ = exact_stress_energy(bubble, grid, bad)
    with assert_raises(contains="center must be finite"):
        _ = exact_curvature(bubble, grid, bad)
    # A point on the horizon: g_00 = 0 and g_xx is infinite.
    var hole = SchwarzschildMetric(Length64(1.0 + 1e-10))
    var horizon = _at(1.0, 0.0, 0.0)
    with assert_raises(contains="singular"):
        _ = exact_stress_energy(hole, grid, horizon)
    with assert_raises(contains="singular"):
        _ = exact_curvature(hole, grid, horizon)
    with assert_raises(contains="singular"):
        _ = christoffel_symbols(
            hole, SIMD[DType.float64, 4](0.0, 1.0, 0.0, 0.0)
        )
    with assert_raises(contains="order is not valid"):
        _ = stress_energy(
            sample_metric(bubble, grid, _at(1.0, 1.0, 1.0)), EXACT_DERIVATIVES
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
