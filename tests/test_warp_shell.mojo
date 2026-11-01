# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the warp shell of `extensions.warp.warp_shell`.

The references are:

- The pressure at the center of a star of constant density is
  ρ c² (1 - √(1 - rₛ/R)) / (3 √(1 - rₛ/R) - 1). See Schutz, "A First
  Course in General Relativity", 2nd edition, section 10.6.
- Outside a point mass, g_tt = -(1 - rₛ/r), so a = ln(1 - rₛ/r) / 2.
- A diagonal spherical metric diag(E, 1, 1) in Cartesian form is
  δ_ij + (E - 1) r̂_i r̂_j.
- Inside the shell, the Eulerian energy density is ρ c², the energy of
  the shell's matter.
"""

from std.math import cos, inf, log, nan, sin, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)

from extensions.warp.frame import to_eulerian
from extensions.warp.grid import SpacetimeCenter, SpacetimeGrid
from extensions.warp.quantities import (
    GRAVITATIONAL_CONSTANT,
    SPEED_OF_LIGHT,
    fraction_of_light,
)
from extensions.warp.solver import stress_energy
from extensions.warp.warp_shell import (
    compact_sigmoid,
    cumulative_trapezoid,
    legendre_radial,
    lapse_exponent,
    moving_average,
    shell_profile,
    spherical_to_cartesian,
    tov_constant_density,
    warp_shell_comoving,
)
from units.si import Duration64, Length64, Mass64, Velocity64

comptime PI = 3.141592653589793
comptime R1 = 10.0
comptime R2 = 20.0


def _shell_mass() -> Float64:
    """The mass of WarpFactory's example: a third of the mass whose
    Schwarzschild radius is R2."""
    var c = SPEED_OF_LIGHT.value
    return R2 / (2.0 * GRAVITATIONAL_CONSTANT.value) * c * c / 3.0


def _direct_average(values: List[Float64], width: Int, i: Int) -> Float64:
    var n = len(values)
    var h = min((width - 1) // 2, min(i, n - 1 - i))
    var total = 0.0
    for k in range(i - h, i + h + 1):
        total += values[k]
    return total / Float64(2 * h + 1)


def test_moving_average() raises:
    var values: List[Float64] = [1.0, 4.0, 2.0, 8.0, 5.0, 7.0, 3.0, 9.0]
    var same = moving_average(values, 1.9)
    for i in range(8):
        assert_equal(same[i], values[i])
    # 4.7 rounds down to 4, and an even width drops to 3.
    var three = moving_average(values, 4.7)
    var five = moving_average(values, 5.0)
    var all = moving_average(values, 100.0)
    for i in range(8):
        assert_almost_equal(three[i], _direct_average(values, 3, i), atol=1e-14)
        assert_almost_equal(five[i], _direct_average(values, 5, i), atol=1e-14)
        assert_almost_equal(all[i], _direct_average(values, 7, i), atol=1e-14)
    assert_equal(three[0], 1.0)
    assert_equal(five[7], 9.0)
    # A window of zeros sums to exactly zero, beside a large value.
    var spike = List[Float64](length=40, fill=0.0)
    spike[20] = 1e30
    spike[21] = 3.0
    var smooth = moving_average(spike, 5.0)
    assert_equal(smooth[17], 0.0)
    assert_equal(smooth[24], 0.0)
    assert_equal(smooth[2], 0.0)
    for i in range(40):
        assert_true(smooth[i] >= 0.0)
    assert_equal(len(moving_average(List[Float64](), 3.0)), 0)


def test_cumulative_trapezoid() raises:
    var x: List[Float64] = [0.0, 1.0, 3.0]
    var y: List[Float64] = [1.0, 3.0, 5.0]
    var out = cumulative_trapezoid(x, y)
    assert_equal(len(out), 3)
    assert_equal(out[0], 0.0)
    assert_equal(out[1], 2.0)
    assert_equal(out[2], 10.0)
    var one: List[Float64] = [4.0]
    assert_equal(len(cumulative_trapezoid(one, one)), 1)


def test_compact_sigmoid() raises:
    assert_equal(compact_sigmoid(25.0, R1, R2, 0.0, 1.0), 0.0)
    assert_equal(compact_sigmoid(19.0, R1, R2, 0.0, 1.0), 0.0)
    assert_equal(compact_sigmoid(11.0, R1, R2, 0.0, 1.0), 1.0)
    assert_equal(compact_sigmoid(3.0, R1, R2, 0.0, 1.0), 1.0)
    var r = 13.0
    var k = (R2 - R1 - 2.0) * 2.0 / 2.0
    var power = k * (1.0 / (r - R2 + 1.0) + 1.0 / (r - R1 - 1.0))
    var expected = 1.0 - 1.0 / (2.718281828459045**power + 1.0)
    assert_almost_equal(
        compact_sigmoid(r, R1, R2, 0.0, 1.0), expected, atol=1e-12
    )
    # Symmetric about the middle of the fall.
    assert_almost_equal(
        compact_sigmoid(15.0, R1, R2, 0.0, 1.0), 0.5, atol=1e-15
    )
    var steep = compact_sigmoid(14.0, R1, R2, 4.0, 1.0)
    assert_true(steep > compact_sigmoid(14.0, R1, R2, 0.0, 1.0))
    # Next to the edges, the exponential overflows or underflows cleanly.
    assert_equal(compact_sigmoid(11.0 + 1e-300, R1, R2, 0.0, 1.0), 1.0)
    assert_equal(compact_sigmoid(19.0 - 1e-12, R1, R2, 0.0, 1.0), 0.0)


def test_tov_pressure() raises:
    var c = SPEED_OF_LIGHT.value
    var mass = _shell_mass()
    var rho = 1e20
    var rs = 2.0 * GRAVITATIONAL_CONSTANT.value * mass / (c * c)
    var root = sqrt(1.0 - rs / R2)
    var center = rho * c * c * (1.0 - root) / (3.0 * root - 1.0)
    assert_almost_equal(
        tov_constant_density(R2, mass, rho, 0.0), center, atol=1e-9 * center
    )
    assert_true(tov_constant_density(R2, mass, rho, 15.0) < center)
    assert_true(tov_constant_density(R2, mass, rho, 15.0) > 0.0)
    assert_equal(tov_constant_density(R2, mass, rho, R2), 0.0)
    assert_equal(tov_constant_density(R2, mass, rho, 30.0), 0.0)


def test_lapse_exponent() raises:
    var c = SPEED_OF_LIGHT.value
    var rs = 0.1
    var mass = rs * c * c / (2.0 * GRAVITATIONAL_CONSTANT.value)
    var r = List[Float64]()
    var m = List[Float64]()
    var p = List[Float64]()
    for i in range(2001):
        r.append(1.0 + Float64(i) * 0.0045)
        m.append(mass)
        p.append(0.0)
    var a = lapse_exponent(m, p, r)
    assert_almost_equal(a[2000], 0.5 * log(1.0 - rs / r[2000]), atol=1e-15)
    assert_almost_equal(a[1000], 0.5 * log(1.0 - rs / r[1000]), atol=1e-7)
    # No mass and no pressure: flat, a = 0.
    var flat = lapse_exponent(
        List[Float64](length=2001, fill=0.0),
        List[Float64](length=2001, fill=0.0),
        r,
    )
    assert_equal(flat[0], 0.0)
    assert_equal(flat[1500], 0.0)
    var lone: List[Float64] = [2.0]
    var zero: List[Float64] = [0.0]
    assert_equal(lapse_exponent(zero, zero, lone)[0], 0.0)


def _cubic(i: Float64) -> Float64:
    return i * i * i - 2.0 * i * i + 3.0


def _lagrange(
    xs: SIMD[DType.float64, 4], ys: SIMD[DType.float64, 4], x: Float64
) -> Float64:
    var total = 0.0
    for i in range(4):
        var term = ys[i]
        for j in range(4):
            if j != i:
                term *= (x - xs[j]) / (xs[i] - xs[j])
        total += term
    return total


def test_legendre_radial() raises:
    var values = List[Float64]()
    for i in range(1, 11):
        values.append(_cubic(Float64(i)))
    assert_almost_equal(legendre_radial(values, 4.5), _cubic(4.5), atol=1e-12)
    assert_almost_equal(legendre_radial(values, 2.25), _cubic(2.25), atol=1e-12)
    assert_equal(legendre_radial(values, 3.0), _cubic(3.0))
    assert_equal(legendre_radial(values, 1.0), _cubic(1.0))
    # Below 2 the first node is 0. It reads sample 1 but keeps its place.
    var low = _lagrange(
        SIMD[DType.float64, 4](0, 1, 2, 3),
        SIMD[DType.float64, 4](_cubic(1), _cubic(1), _cubic(2), _cubic(3)),
        1.5,
    )
    assert_almost_equal(legendre_radial(values, 1.5), low, atol=1e-12)


def _expected_cartesian(
    theta: Float64, phi: Float64, e: Float64, i: Int, j: Int
) -> Float64:
    var n = SIMD[DType.float64, 4](
        sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta), 0.0
    )
    var delta = 0.0
    if i == j:
        delta = 1.0
    return delta + (e - 1.0) * n[i] * n[j]


def test_spherical_to_cartesian() raises:
    var angles: List[Float64] = [0.3, 1.1, 2.0, 2.9]
    for theta in angles:
        for phi in angles:
            var g = spherical_to_cartesian(theta, phi - 1.5, -0.7, 1.8)
            assert_equal(g[0], -0.7)
            var lanes: List[Int] = [1, 2, 3, 4, 5, 6]
            var rows: List[Int] = [0, 0, 0, 1, 1, 2]
            var cols: List[Int] = [0, 1, 2, 1, 2, 2]
            for k in range(6):
                assert_almost_equal(
                    g[lanes[k]],
                    _expected_cartesian(
                        theta, phi - 1.5, 1.8, rows[k], cols[k]
                    ),
                    atol=1e-14,
                )
    # Exactly ±π/2 has a cosine of exactly 0.
    var side = spherical_to_cartesian(PI / 2.0, PI / 2.0, -1.0, 3.0)
    assert_equal(side[1], 1.0)
    assert_equal(side[4], 3.0)
    assert_equal(side[6], 1.0)
    assert_equal(side[2], 0.0)
    assert_equal(side[3], 0.0)
    var under = spherical_to_cartesian(-PI / 2.0, -PI / 2.0, -1.0, 3.0)
    assert_equal(under[2], 0.0)
    assert_equal(under[5], 0.0)
    var flat = spherical_to_cartesian(0.4, 0.9, -1.0, 1.0)
    assert_almost_equal(flat[1], 1.0, atol=1e-15)
    assert_almost_equal(flat[2], 0.0, atol=1e-15)


def test_shell_profile() raises:
    var c = SPEED_OF_LIGHT.value
    var mass = _shell_mass()
    var profile = shell_profile(
        Length64(30.0),
        Mass64(mass),
        Length64(R1),
        Length64(R2),
        Length64(0.0),
        0.0,
        50.0,
        3001,
    )
    assert_equal(len(profile.radius), 3001)
    assert_equal(profile.radius[3000], 30.0)
    assert_equal(profile.g_rr[0], 1.0)
    assert_equal(profile.density[0], 0.0)
    assert_equal(profile.density[2900], 0.0)
    assert_almost_equal(profile.mass[3000], mass, atol=1e-3 * mass)
    var rs = 2.0 * GRAVITATIONAL_CONSTANT.value * profile.mass[3000] / (c * c)
    assert_almost_equal(profile.g_tt[3000], -(1.0 - rs / 30.0), atol=1e-12)
    assert_almost_equal(profile.shift[0], 1.0, atol=1e-15)
    assert_almost_equal(profile.shift[3000], 0.0, atol=1e-15)
    assert_true(profile.pressure[1500] > 0.0)
    assert_equal(profile.pressure[2500], 0.0)


def test_shell_profile_refusals() raises:
    var m = Mass64(_shell_mass())
    var x = Length64(30.0)
    var a = Length64(R1)
    var b = Length64(R2)
    var z = Length64(0.0)
    var bad = Length64(nan[DType.float64]())
    with assert_raises(contains="must be finite"):
        _ = shell_profile(bad, m, a, b, z, 0.0, 1.0, 10)
    with assert_raises(contains="must be finite"):
        _ = shell_profile(
            x, Mass64(inf[DType.float64]()), a, b, z, 0.0, 1.0, 10
        )
    with assert_raises(contains="must be finite"):
        _ = shell_profile(x, m, bad, b, z, 0.0, 1.0, 10)
    with assert_raises(contains="must be finite"):
        _ = shell_profile(x, m, a, bad, z, 0.0, 1.0, 10)
    with assert_raises(contains="must be finite"):
        _ = shell_profile(x, m, a, b, bad, 0.0, 1.0, 10)
    with assert_raises(contains="must be finite"):
        _ = shell_profile(x, m, a, b, z, nan[DType.float64](), 1.0, 10)
    with assert_raises(contains="must be finite"):
        _ = shell_profile(x, m, a, b, z, 0.0, inf[DType.float64](), 10)
    with assert_raises(contains="0 <= R1 < R2"):
        _ = shell_profile(x, m, Length64(-1.0), b, z, 0.0, 1.0, 10)
    with assert_raises(contains="0 <= R1 < R2"):
        _ = shell_profile(x, m, b, a, z, 0.0, 1.0, 10)
    with assert_raises(contains="0 <= R1 < R2"):
        _ = shell_profile(Length64(15.0), m, a, b, z, 0.0, 1.0, 10)
    with assert_raises(contains="must not be negative"):
        _ = shell_profile(x, Mass64(-1.0), a, b, z, 0.0, 1.0, 10)
    with assert_raises(contains="must not be negative"):
        _ = shell_profile(x, m, a, b, Length64(-0.5), 0.0, 1.0, 10)
    with assert_raises(contains="sigma > -2"):
        _ = shell_profile(x, m, a, b, z, -2.0, 1.0, 10)
    with assert_raises(contains="sigma > -2"):
        _ = shell_profile(x, m, a, b, z, 0.0, 0.5, 10)
    with assert_raises(contains="sigma > -2"):
        _ = shell_profile(x, m, a, b, z, 0.0, 1.0, 3)
    with assert_raises(contains="too heavy"):
        _ = shell_profile(x, Mass64(3.0 * _shell_mass()), a, b, z, 0.0, 1.0, 10)


def _line_grid() raises -> SpacetimeGrid:
    return SpacetimeGrid.uniform(
        1, 24, 5, 5, Duration64(1e-3 / SPEED_OF_LIGHT.value), Length64(1.0)
    )


def _line_center() -> SpacetimeCenter:
    """Point (i, 2, 2) sits at x = i + 3, y = z = 0."""
    return SpacetimeCenter(
        Duration64(0.0), Length64(-2.0), Length64(3.0), Length64(3.0)
    )


def test_shell_energy_density() raises:
    var c = SPEED_OF_LIGHT.value
    var mass = _shell_mass()
    var grid = _line_grid()
    var metric = warp_shell_comoving(
        grid,
        _line_center(),
        Mass64(mass),
        Length64(R1),
        Length64(R2),
        samples=20000,
    )
    assert_equal(metric.name, "Comoving Warp Shell")
    var eulerian = to_eulerian(stress_energy(metric), metric)
    var rho = mass / (4.0 / 3.0 * PI * (R2 * R2 * R2 - R1 * R1 * R1))
    # x = 15, in the middle of the shell.
    var energy = eulerian.tensor.get(0, 0, grid.index(0, 12, 2, 2))
    assert_almost_equal(energy, rho * c * c, atol=2e-3 * rho * c * c)
    # x = 5, inside the shell, is flat: no energy.
    var inside = eulerian.tensor.get(0, 0, grid.index(0, 2, 2, 2))
    assert_true(abs(inside) < 1e-6 * rho * c * c)
    # Without the warp, there is no shift.
    assert_equal(metric.at(grid.index(0, 2, 2, 2))[1], 0.0)


def test_shell_warp() raises:
    var grid = _line_grid()
    var metric = warp_shell_comoving(
        grid,
        _line_center(),
        Mass64(_shell_mass()),
        Length64(R1),
        Length64(R2),
        Length64(1.0),
        0.5,
        4.0,
        fraction_of_light(0.02),
        True,
        4000,
    )
    # Inside the shell the shift is the full warp speed.
    var g = metric.at(grid.index(0, 2, 2, 2))
    assert_almost_equal(g[1], -0.02, atol=1e-12)
    assert_equal(g[4], g[1])
    # Outside, none.
    var outside = metric.at(grid.index(0, 23, 2, 2))
    assert_almost_equal(outside[1], 0.0, atol=1e-15)


def test_shell_refusals() raises:
    var m = Mass64(_shell_mass())
    var grid = _line_grid()
    var center = _line_center()
    with assert_raises(contains="one time slice"):
        _ = warp_shell_comoving(
            SpacetimeGrid.uniform(2, 3, 3, 3, Duration64(1.0), Length64(1.0)),
            center,
            m,
            Length64(R1),
            Length64(R2),
        )
    with assert_raises(contains="center must be finite"):
        _ = warp_shell_comoving(
            grid,
            SpacetimeCenter(
                Duration64(inf[DType.float64]()),
                Length64(0.0),
                Length64(0.0),
                Length64(0.0),
            ),
            m,
            Length64(R1),
            Length64(R2),
        )
    with assert_raises(contains="speed must be finite"):
        _ = warp_shell_comoving(
            grid,
            center,
            m,
            Length64(R1),
            Length64(R2),
            speed=Velocity64(nan[DType.float64]()),
        )
    # The last point is at x = 25, but the first is at x = -40, past the
    # samples, which reach 1.2 times 25.
    var long = SpacetimeGrid.uniform(
        1, 66, 5, 5, Duration64(1.0), Length64(1.0)
    )
    var far = SpacetimeCenter(
        Duration64(0.0), Length64(41.0), Length64(3.0), Length64(3.0)
    )
    with assert_raises(contains="past the radial samples"):
        _ = warp_shell_comoving(
            long, far, m, Length64(R1), Length64(R2), samples=1000
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
