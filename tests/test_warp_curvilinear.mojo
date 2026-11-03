# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for spherical and cylindrical grids in `extensions.warp`.

The references are those of the Cartesian tests, in other coordinates:
flat space and the Schwarzschild exterior have no Ricci curvature; the
warp shell holds an energy density of ρ c²; the Alcubierre bubble's
energy density is -κ (v²/4) (ρ²/r²) f'(r)², with ρ the distance from the
direction of travel. The volume of a spherical shell is
(4 π / 3)(b³ - a³).
"""

from std.math import cos, inf, nan, sin, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from extensions.warp.analytic import exact_stress_energy, sample_metric
from extensions.warp.curvilinear import (
    alcubierre_cylindrical,
    minkowski_curvilinear,
    schwarzschild_spherical,
    warp_shell_spherical,
)
from extensions.warp.derivatives import derivative, second_derivative
from extensions.warp.flow import GridPoint, momentum_flow_lines
from extensions.warp.frame import to_eulerian
from extensions.warp.grid import SpacetimeGrid, require_cartesian
from extensions.warp.kinds import (
    CARTESIAN,
    CONTRAVARIANT,
    CYLINDRICAL,
    CoordinateSystem,
    EULERIAN_FRAME,
    FOURTH_ORDER,
    SPHERICAL,
    X_AXIS,
    Y_AXIS,
    Z_AXIS,
)
from extensions.warp.metrics import (
    AlcubierreMetric,
    alcubierre_shape_derivatives,
    lentz,
    lentz_comoving,
    minkowski,
)
from extensions.warp.quantities import (
    Compliance64,
    GRAVITATIONAL_CONSTANT,
    SPEED_OF_LIGHT,
    einstein_coupling,
    fraction_of_light,
)
from extensions.warp.solver import StressEnergy, curvature, stress_energy
from extensions.warp.tensor import TensorField
from extensions.warp.totals import energy_totals
from extensions.warp.warp_shell import (
    ShellProfile,
    accelerating_shell,
    shell_from_profile,
    warp_shell_comoving,
)
from units.si import Angle64, Duration64, InverseLength64, Length64, Mass64

comptime PI = 3.141592653589793


def _sphere(
    nr: Int, nt: Int, np: Int, r0: Float64, dr: Float64
) raises -> SpacetimeGrid:
    """A spherical grid of midpoints in θ, around the whole circle in φ."""
    return SpacetimeGrid.spherical(
        1,
        nr,
        nt,
        np,
        Duration64(1.0),
        Length64(r0),
        Length64(dr),
        Angle64(PI / Float64(2 * nt)),
        Angle64(PI / Float64(nt)),
        Angle64(0.0),
        Angle64(2.0 * PI / Float64(np)),
    )


def _cylinder(
    n: Int, np: Int, rho0: Float64, h: Float64
) raises -> SpacetimeGrid:
    return SpacetimeGrid.cylindrical(
        1,
        n,
        np,
        n,
        Duration64(1.0),
        Length64(rho0),
        Length64(h),
        Angle64(0.0),
        Angle64(2.0 * PI / Float64(np)),
        Length64(-Float64(n - 1) * h / 2.0),
        Length64(h),
    )


def test_coordinate_kinds() raises:
    assert_equal(CARTESIAN.name(), "cartesian")
    assert_equal(SPHERICAL.name(), "spherical")
    assert_equal(CYLINDRICAL.name(), "cylindrical")
    assert_equal(CoordinateSystem(3).name(), "?")
    assert_false(CoordinateSystem(-1).is_valid())


def test_curvilinear_grids() raises:
    var sphere = _sphere(5, 4, 8, 1.0, 0.5)
    assert_equal(sphere.system, SPHERICAL)
    assert_equal(sphere.phi_axis(), 3)
    assert_true(sphere.periodic(3))
    assert_false(sphere.periodic(2))
    assert_almost_equal(sphere.coordinate(X_AXIS, 2), 2.0, atol=1e-15)
    assert_almost_equal(
        sphere.coordinate(Y_AXIS, 1), 3.0 * PI / 8.0, atol=1e-15
    )
    var cylinder = _cylinder(5, 6, 0.5, 0.25)
    assert_equal(cylinder.phi_axis(), 2)
    assert_true(cylinder.periodic(2))
    assert_almost_equal(cylinder.coordinate(Z_AXIS, 0), -0.5, atol=1e-15)
    var flat = SpacetimeGrid.uniform(1, 5, 5, 5, Duration64(1.0), Length64(1.0))
    assert_equal(flat.phi_axis(), -1)
    assert_false(flat.periodic(3))
    assert_false(sphere == _sphere(5, 4, 8, 1.5, 0.5))
    assert_false(sphere == cylinder)
    var part = SpacetimeGrid.cylindrical(
        1,
        5,
        6,
        5,
        Duration64(1.0),
        Length64(0.5),
        Length64(0.25),
        Angle64(0.0),
        Angle64(0.1),
        Length64(0.0),
        Length64(0.25),
    )
    assert_false(part.periodic(2))
    require_cartesian(flat, "test")
    with assert_raises(contains="needs a Cartesian grid"):
        require_cartesian(sphere, "test")


def test_grid_refusals() raises:
    var t = Duration64(1.0)
    var one = Length64(1.0)
    var a = Angle64(0.1)
    with assert_raises(contains="start at r > 0"):
        _ = SpacetimeGrid.spherical(
            1, 2, 2, 2, t, Length64(0.0), one, a, a, a, a
        )
    with assert_raises(contains="starts must be finite"):
        _ = SpacetimeGrid.spherical(
            1, 2, 2, 2, t, Length64(nan[DType.float64]()), one, a, a, a, a
        )
    with assert_raises(contains="starts must be finite"):
        _ = SpacetimeGrid.spherical(
            1, 2, 2, 2, t, one, one, a, a, Angle64(inf[DType.float64]()), a
        )
    with assert_raises(contains="inside (0, pi)"):
        _ = SpacetimeGrid.spherical(
            1, 2, 2, 2, t, one, one, Angle64(0.0), a, a, a
        )
    with assert_raises(contains="inside (0, pi)"):
        _ = SpacetimeGrid.spherical(
            1, 2, 10, 2, t, one, one, a, Angle64(0.4), a, a
        )
    with assert_raises(contains="at most one turn"):
        _ = SpacetimeGrid.spherical(
            1, 2, 2, 7, t, one, one, a, a, a, Angle64(1.0)
        )
    with assert_raises(contains="at least one point"):
        _ = SpacetimeGrid.spherical(1, 0, 2, 2, t, one, one, a, a, a, a)
    with assert_raises(contains="start at rho > 0"):
        _ = SpacetimeGrid.cylindrical(
            1, 2, 2, 2, t, Length64(-1.0), one, a, a, one, one
        )
    with assert_raises(contains="starts must be finite"):
        _ = SpacetimeGrid.cylindrical(
            1, 2, 2, 2, t, one, one, a, a, Length64(inf[DType.float64]()), one
        )
    with assert_raises(contains="at most one turn"):
        _ = SpacetimeGrid.cylindrical(
            1, 2, 7, 2, t, one, one, a, Angle64(1.0), one, one
        )


def test_wrapping_derivatives() raises:
    # f = sin φ on a whole circle: the derivative wraps at the seam.
    var grid = _cylinder(5, 32, 1.0, 0.25)
    var field = List[Float64]()
    for point in range(grid.points()):
        var phi = grid.coordinate(Y_AXIS, Int(grid.position(point)[2]))
        field.append(sin(phi))
    var d = derivative(field, grid, Y_AXIS)
    var dd = second_derivative(field, grid, Y_AXIS, Y_AXIS)
    var mixed = second_derivative(field, grid, X_AXIS, Y_AXIS)
    for k in [0, 1, 31]:
        var point = grid.index(0, 2, k, 2)
        var phi = grid.coordinate(Y_AXIS, k)
        # The fourth-order error is about dφ⁴ / 30 = 5e-5.
        assert_almost_equal(d[point], cos(phi), atol=1e-4)
        assert_almost_equal(dd[point], -sin(phi), atol=1e-4)
        assert_equal(mixed[point], 0.0)
    # On a partial circle the edge copies the nearest derivative.
    var part = SpacetimeGrid.cylindrical(
        1,
        5,
        8,
        5,
        Duration64(1.0),
        Length64(1.0),
        Length64(0.25),
        Angle64(0.0),
        Angle64(0.1),
        Length64(0.0),
        Length64(0.25),
    )
    var g = List[Float64]()
    for point in range(part.points()):
        var phi = part.coordinate(Y_AXIS, Int(part.position(point)[2]))
        g.append(sin(phi))
    var pd = derivative(g, part, Y_AXIS)
    assert_equal(pd[part.index(0, 2, 0, 2)], pd[part.index(0, 2, 2, 2)])


def _flat_residual(nt: Int) raises -> Float64:
    """Return the largest Ricci component of flat space at r = 2.75 m on a
    spherical grid with `nt` polar angles."""
    var grid = _sphere(7, nt, 12, 2.0, 0.25)
    var bent = curvature(minkowski_curvilinear(grid))
    var p = grid.index(0, 3, nt // 2, 0)
    var largest = 0.0
    for k in range(16):
        largest = max(largest, abs(bent.ricci.matrix(p)[k]))
    return largest


def test_flat_and_vacuum() raises:
    var grid = _sphere(7, 16, 12, 2.0, 0.25)
    var flat = minkowski_curvilinear(grid)
    assert_equal(flat.name, "Minkowski")
    var p = grid.index(0, 3, 8, 0)
    var r = grid.coordinate(X_AXIS, 3)
    var s = sin(grid.coordinate(Y_AXIS, 8))
    assert_almost_equal(flat.at(p)[10], r * r, atol=1e-14)
    assert_almost_equal(flat.at(p)[15], r * r * s * s, atol=1e-14)
    # Flat space has no curvature: the residual is the truncation of the
    # stencils, which falls by 16 when the angular step halves.
    var coarse = _flat_residual(8)
    var fine = _flat_residual(16)
    assert_true(fine < 5e-4)
    assert_true(coarse / fine > 12.0)
    var hole = schwarzschild_spherical(grid, Length64(1.0))
    assert_equal(hole.name, "Schwarzschild")
    assert_almost_equal(hole.at(p)[0], -(1.0 - 1.0 / r), atol=1e-15)
    var vacuum = curvature(hole)
    for k in range(16):
        assert_true(abs(vacuum.ricci.matrix(p)[k]) < 5e-4)
    var cylinder = minkowski_curvilinear(_cylinder(5, 8, 1.0, 0.5))
    assert_almost_equal(cylinder.at(0)[15], 1.0, atol=0.0)
    assert_almost_equal(cylinder.at(0)[10], 1.0, atol=1e-15)


def test_spherical_shell() raises:
    var c = SPEED_OF_LIGHT.value
    var mass = 20.0 / (2.0 * GRAVITATIONAL_CONSTANT.value) * c * c / 3.0
    # r from 13 to 17 m, around the middle of the shell.
    var grid = SpacetimeGrid.spherical(
        1,
        9,
        17,
        8,
        Duration64(1.0),
        Length64(13.0),
        Length64(0.5),
        Angle64(PI / 34.0),
        Angle64(PI / 17.0),
        Angle64(0.0),
        Angle64(PI / 4.0),
    )
    var metric = warp_shell_spherical(
        grid,
        Mass64(mass),
        Length64(10.0),
        Length64(20.0),
        samples=20000,
    )
    assert_equal(metric.name, "Spherical Warp Shell")
    var eulerian = to_eulerian(stress_energy(metric), metric)
    var rho = mass / (4.0 / 3.0 * PI * (8000.0 - 1000.0))
    var point = grid.index(0, 4, 8, 3)
    assert_almost_equal(
        eulerian.tensor.get(0, 0, point), rho * c * c, atol=1e-3 * rho * c * c
    )
    var moving = warp_shell_spherical(
        grid,
        Mass64(mass),
        Length64(10.0),
        Length64(20.0),
        Length64(1.0),
        0.5,
        1.0,
        fraction_of_light(0.02),
        True,
        4000,
    )
    # Outside the shell's inner radius the shift has fallen to its wall
    # value; along θ it is r sin θ times the radial one over -cos θ.
    var off = grid.index(0, 4, 3, 3)
    var g = moving.at(off)
    var theta = grid.coordinate(Y_AXIS, 3)
    var r = grid.coordinate(X_AXIS, 4)
    assert_almost_equal(g[2], -g[1] * r * sin(theta) / cos(theta), atol=1e-15)


def test_alcubierre_cylinder() raises:
    var h = 0.05
    var grid = SpacetimeGrid.cylindrical(
        1,
        5,
        64,
        5,
        Duration64(1.0),
        Length64(1.1 - 2.0 * h),
        Length64(h),
        Angle64(0.0),
        Angle64(2.0 * PI / 64.0),
        Length64(0.6 - 2.0 * h),
        Length64(h),
    )
    var metric = alcubierre_cylindrical(
        grid, fraction_of_light(0.5), Length64(2.0), InverseLength64(1.5)
    )
    assert_equal(metric.name, "Alcubierre Cylindrical")
    var eulerian = to_eulerian(stress_energy(metric), metric)
    var rho = 1.1
    var z = 0.6
    var r = sqrt(rho * rho + z * z)
    var slope = alcubierre_shape_derivatives(r, 2.0, 1.5)[1]
    var exact = (
        -einstein_coupling()
        * 0.25
        / 4.0
        * (rho * rho)
        / (r * r)
        * slope
        * slope
    )
    for k in [0, 17, 63]:
        var point = grid.index(0, 2, k, 2)
        assert_almost_equal(
            eulerian.tensor.get(0, 0, point), exact, atol=1e-4 * abs(exact)
        )


def test_spherical_volume() raises:
    # Midpoints in r from 1 to 2 m, and in θ over (0, π).
    var grid = SpacetimeGrid.spherical(
        1,
        40,
        60,
        4,
        Duration64(1.0),
        Length64(1.0125),
        Length64(0.025),
        Angle64(PI / 120.0),
        Angle64(PI / 60.0),
        Angle64(0.0),
        Angle64(PI / 2.0),
    )
    var metric = minkowski_curvilinear(grid)
    var t = TensorField(grid, CONTRAVARIANT, EULERIAN_FRAME)
    for point in range(grid.points()):
        t.set(0, 0, point, 2.0)
    var totals = energy_totals(
        StressEnergy(t^, "uniform", FOURTH_ORDER), metric
    )
    var volume = 4.0 / 3.0 * PI * (8.0 - 1.0)
    assert_almost_equal(totals.volume.value, volume, atol=1e-3 * volume)
    assert_almost_equal(totals.total.value, 2.0 * volume, atol=2e-3 * volume)


def test_cartesian_only() raises:
    var sphere = _sphere(5, 4, 8, 1.0, 0.5)
    var c = sphere.center()
    var v = fraction_of_light(0.1)
    var bubble = AlcubierreMetric(v, Length64(1.0), InverseLength64(1.0), True)
    with assert_raises(contains="needs a Cartesian grid"):
        _ = sample_metric(bubble, sphere, c)
    with assert_raises(contains="needs a Cartesian grid"):
        _ = exact_stress_energy(bubble, sphere, c)
    with assert_raises(contains="needs a Cartesian grid"):
        _ = minkowski(sphere)
    with assert_raises(contains="needs a Cartesian grid"):
        _ = lentz(sphere, c, v, Length64(1.0))
    with assert_raises(contains="needs a Cartesian grid"):
        _ = lentz_comoving(sphere, c, v, Length64(1.0))
    var profile = ShellProfile(
        [0.0, 1.0, 2.0, 3.0],
        [0.0, 0.0, 0.0, 0.0],
        [0.0, 0.0, 0.0, 0.0],
        [0.0, 0.0, 0.0, 0.0],
        [-1.0, -1.0, -1.0, -1.0],
        [1.0, 1.0, 1.0, 1.0],
        [0.0, 0.0, 0.0, 0.0],
    )
    with assert_raises(contains="needs a Cartesian grid"):
        _ = shell_from_profile(sphere, c, profile, v)
    with assert_raises(contains="needs a Cartesian grid"):
        _ = accelerating_shell(
            sphere, c, profile, v, v, Duration64(0.0), Duration64(1.0)
        )
    with assert_raises(contains="needs a Cartesian grid"):
        _ = warp_shell_comoving(
            sphere, c, Mass64(1.0), Length64(1.0), Length64(2.0)
        )
    var energy = StressEnergy(
        TensorField(sphere, CONTRAVARIANT, EULERIAN_FRAME), "x", FOURTH_ORDER
    )
    with assert_raises(contains="needs a Cartesian grid"):
        _ = momentum_flow_lines(
            energy, [GridPoint(2.0, 2.0, 2.0)], Compliance64(1.0), 3
        )


def test_curvilinear_refusals() raises:
    var flat = SpacetimeGrid.uniform(1, 5, 5, 5, Duration64(1.0), Length64(1.0))
    var cylinder = _cylinder(5, 8, 1.0, 0.5)
    var sphere = _sphere(5, 4, 8, 2.0, 0.5)
    with assert_raises(contains="needs a curvilinear grid"):
        _ = minkowski_curvilinear(flat)
    with assert_raises(contains="needs a spherical grid"):
        _ = schwarzschild_spherical(cylinder, Length64(1.0))
    with assert_raises(contains="positive and finite"):
        _ = schwarzschild_spherical(sphere, Length64(0.0))
    with assert_raises(contains="positive and finite"):
        _ = schwarzschild_spherical(sphere, Length64(nan[DType.float64]()))
    with assert_raises(contains="outside the horizon"):
        _ = schwarzschild_spherical(sphere, Length64(2.0))
    with assert_raises(contains="needs a spherical grid"):
        _ = warp_shell_spherical(
            flat, Mass64(1.0), Length64(1.0), Length64(2.0)
        )
    var moving = SpacetimeGrid.spherical(
        2,
        3,
        3,
        3,
        Duration64(1.0),
        Length64(1.0),
        Length64(1.0),
        Angle64(0.5),
        Angle64(0.5),
        Angle64(0.0),
        Angle64(0.5),
    )
    with assert_raises(contains="one time slice"):
        _ = warp_shell_spherical(
            moving, Mass64(1.0), Length64(1.0), Length64(2.0)
        )
    with assert_raises(contains="speed must be finite"):
        _ = warp_shell_spherical(
            sphere,
            Mass64(1.0),
            Length64(1.0),
            Length64(2.0),
            speed=fraction_of_light(nan[DType.float64]()),
        )
    with assert_raises(contains="needs a cylindrical grid"):
        _ = alcubierre_cylindrical(
            sphere, fraction_of_light(0.1), Length64(1.0), InverseLength64(1.0)
        )
    var moving_cylinder = SpacetimeGrid.cylindrical(
        2,
        3,
        3,
        3,
        Duration64(1.0),
        Length64(1.0),
        Length64(1.0),
        Angle64(0.0),
        Angle64(0.5),
        Length64(0.0),
        Length64(1.0),
    )
    with assert_raises(contains="one time slice"):
        _ = alcubierre_cylindrical(
            moving_cylinder,
            fraction_of_light(0.1),
            Length64(1.0),
            InverseLength64(1.0),
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
