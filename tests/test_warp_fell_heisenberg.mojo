# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the positive-energy soliton of Fell and Heisenberg.

The potential is checked against the paper's equation 13, with m (n r + u)
for its last product. The shift is checked against the gradient of the
potential, and the energy density of the paper's equation 10 against the
Einstein equations: exactly, and with the finite-difference solver. With
no tilt the energy density is positive everywhere it is sampled.
"""

from std.math import erf, exp, pi, sqrt, tanh
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)

from extensions.warp.analytic import exact_stress_energy, place_jets
from extensions.warp.fell_heisenberg import (
    FellHeisenbergSoliton,
    fell_heisenberg,
)
from extensions.warp.frame import to_eulerian
from extensions.warp.grid import SpacetimeCenter, SpacetimeGrid
from extensions.warp.jet import jet_place
from extensions.warp.kinds import FOURTH_ORDER
from extensions.warp.solver import stress_energy
from units.si import Duration64, Length64

comptime SCALE = 100.0
"""Meters in one unit of x̂."""


def _paper(tilt: Float64) -> FellHeisenbergSoliton:
    """The paper's (Π, r, V, σ) = (1/4, 6, 10, 1)."""
    return FellHeisenbergSoliton(0.25, 6.0, 10.0, 1.0, tilt, Length64(SCALE))


def _equation_13(
    s: FellHeisenbergSoliton, x: Float64, y: Float64, z: Float64
) -> Float64:
    """The paper's potential, written out as printed but for m (n r + u)."""
    var square = x * x + y * y + z * z
    var u = square**s.power
    var tau = tanh(s.tilt * z / u)
    var m = 1.0 / (1.0 - tau)
    var n = 1.0 / (1.0 + tau)
    var r = s.radius
    var sigma = s.width
    var root = sqrt(sigma)
    var a = r - u / m
    var b = r + u / n
    var gauss = sigma * (
        exp(-a * a / sigma) * m * n
        + exp(-b * b / sigma) * m * n
        - exp(-r * r / sigma) * (m + n)
    )
    var errors = sqrt(sigma * pi) * (
        -((m + n) * r * erf(r / root))
        + n * (m * r - u) * erf(a / root)
        + m * (n * r + u) * erf(b / root)
    )
    return s.strength / (m + n) * (gauss + errors)


def test_potential_is_equation_13() raises:
    for tilt in [0.0, 0.07, -0.2]:
        var s = _paper(tilt)
        for p in [
            (0.3, -0.2, 0.5),
            (2.0, 1.0, -3.0),
            (20.0, 30.0, 10.0),
            (-40.0, 5.0, 60.0),
        ]:
            var x = p[0]
            var y = p[1]
            var z = p[2]
            var phi = s.potential(
                jet_place(0.0, x * SCALE, y * SCALE, z * SCALE)
            )
            var expected = _equation_13(s, x, y, z)
            assert_almost_equal(
                phi.value, expected, atol=1e-9 * (1 + abs(expected))
            )


def test_shift_is_the_gradient() raises:
    for tilt in [0.0, 0.07]:
        var s = _paper(tilt)
        for p in [(0.4, 0.3, -0.6), (5.0, -8.0, 12.0), (-30.0, 20.0, 45.0)]:
            var place = jet_place(0.0, p[0] * SCALE, p[1] * SCALE, p[2] * SCALE)
            var phi = s.potential(place)
            var n = s.shift(place)
            for i in range(3):
                var by_phi = SCALE * phi.gradient[1 + i]
                assert_almost_equal(
                    n[i].value, by_phi, atol=1e-9 * (1 + abs(by_phi))
                )
                for j in range(3):
                    var by_hessian = SCALE * phi.second(1 + i, 1 + j)
                    assert_almost_equal(
                        n[i].gradient[1 + j],
                        by_hessian,
                        atol=1e-9 * (1 + abs(by_hessian)) / SCALE,
                    )


def test_spherical_shift() raises:
    var s = _paper(0.0)
    # Well inside the radius the shift is zero to rounding.
    var inside = s.shift(jet_place(0.0, 0.6 * SCALE, 0.8 * SCALE, 0.0))
    for i in range(3):
        assert_true(abs(inside[i].value) < 1e-9)
    # Far outside it is radial: V √(σπ) times the gradient of u.
    var x = 3000.0
    var far = s.shift(jet_place(0.0, x * SCALE, 0.0, 0.0))
    var expected = s.strength * sqrt(pi) * 2.0 * 0.25 * x**-0.5
    assert_almost_equal(far[0].value, expected, atol=1e-9)
    assert_true(abs(far[1].value) < 1e-15 and abs(far[2].value) < 1e-15)


def test_spherical_energy_is_positive() raises:
    var s = _paper(0.0)
    var values = List[Float64]()
    for i in range(1, 40):
        for j in range(0, 6):
            var radius = Float64(i) * 1.0
            var angle = Float64(j) * 0.5
            var place = jet_place(
                0.0,
                radius * sqrt(0.5) * SCALE,
                radius * sqrt(0.5) * SCALE * angle / 3.0,
                radius * (1.0 - angle / 3.0) * SCALE,
            )
            values.append(s.energy_density(place).value)
    var largest = 0.0
    for rho in values:
        largest = max(largest, rho)
    assert_true(largest > 0.0)
    # Far out 2 Φ'' + Φ'/R cancels, so allow rounding there.
    for rho in values:
        assert_true(rho >= -1e-9 * largest)


def test_tilted_center_is_superluminal() raises:
    var s = _paper(0.071)
    assert_almost_equal(s.central_shift(), 1.2585, atol=1e-3)
    var n = s.shift(jet_place(0.0, 0.0, 0.0, 1e-4 * SCALE))
    assert_almost_equal(n[2].value, s.central_shift(), atol=1e-3)
    assert_true(abs(n[0].value) < 1e-9 and abs(n[1].value) < 1e-9)
    # The center itself has the components of a point just above it.
    var at = s.components(jet_place(0.0, 0.0, 0.0, 0.0))
    assert_almost_equal(at[3].value, s.central_shift(), atol=1e-3)
    assert_almost_equal(at[0].value, n[2].value ** 2 - 1.0, atol=1e-3)


def _local(h: Float64, x: Float64, y: Float64, z: Float64) -> SpacetimeCenter:
    """The center that puts point (1, 1, 1) of a step-h grid at (x, y, z)."""
    return SpacetimeCenter(
        Duration64(0.0),
        Length64(2.0 * h - x),
        Length64(2.0 * h - y),
        Length64(2.0 * h - z),
    )


def test_energy_matches_einstein_equations() raises:
    for tilt in [0.0, 0.071]:
        var s = _paper(tilt)
        var grid = SpacetimeGrid.uniform(
            1, 3, 3, 3, Duration64(1.0), Length64(0.37 * SCALE)
        )
        var center = _local(
            0.37 * SCALE, 9.0 * SCALE, -4.0 * SCALE, 13.0 * SCALE
        )
        var metric = fell_heisenberg(grid, center, s)
        var exact = to_eulerian(exact_stress_energy(s, grid, center), metric)
        for point in range(grid.points()):
            var rho = s.energy_density(place_jets(grid, center, point)).value
            var by_einstein = exact.tensor.get(0, 0, point)
            assert_almost_equal(by_einstein, rho, atol=1e-7 * abs(rho) + 1e-6)
            # The momentum density is zero.
            for i in range(1, 4):
                assert_true(
                    abs(exact.tensor.get(0, i, point)) <= 1e-7 * abs(rho) + 1e-6
                )


def test_grid_solver_agrees() raises:
    var s = _paper(0.0)
    var h = 0.05 * SCALE
    var grid = SpacetimeGrid.uniform(1, 5, 5, 5, Duration64(1.0), Length64(h))
    var x = 30.0 * SCALE
    var center = SpacetimeCenter(
        Duration64(0.0),
        Length64(3.0 * h - x),
        Length64(3.0 * h),
        Length64(3.0 * h),
    )
    var metric = fell_heisenberg(grid, center, s)
    var by_grid = to_eulerian(stress_energy(metric, FOURTH_ORDER), metric)
    var middle = 2 * 25 + 2 * 5 + 2
    var rho = s.energy_density(jet_place(0.0, x, 0.0, 0.0)).value
    assert_true(rho > 0.0)
    assert_almost_equal(by_grid.tensor.get(0, 0, middle), rho, atol=1e-4 * rho)


def test_refusals() raises:
    var good = _paper(0.0)
    good.check()
    assert_equal(good.name(), "Fell-Heisenberg")
    var bad = good.copy()
    bad.power = 0.0
    with assert_raises(contains="power"):
        bad.check()
    bad = good.copy()
    bad.radius = -1.0
    with assert_raises(contains="radius"):
        bad.check()
    bad = good.copy()
    bad.width = 0.0
    with assert_raises(contains="width"):
        bad.check()
    bad = good.copy()
    bad.scale = Length64(0.0)
    with assert_raises(contains="scale"):
        bad.check()
    bad = good.copy()
    bad.strength = Float64.MAX * 10.0
    with assert_raises(contains="strength"):
        bad.check()
    bad = good.copy()
    bad.tilt = Float64.MAX * 10.0
    with assert_raises(contains="tilt"):
        bad.check()
    var grid = SpacetimeGrid.uniform(1, 1, 1, 1, Duration64(1.0), Length64(1.0))
    var center = SpacetimeCenter(
        Duration64(0.0), Length64(0.0), Length64(0.0), Length64(0.0)
    )
    bad = good.copy()
    bad.width = -2.0
    with assert_raises(contains="width"):
        _ = fell_heisenberg(grid, center, bad)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
