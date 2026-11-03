# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Metrics on spherical and cylindrical grids.

A spherical shell needs far fewer points in r, θ and φ than in x, y and
z, because its features lie along r. The solver, the Eulerian frame, the
energy conditions, the scalars and the totals work in any coordinates:
they read only the metric and its derivatives. These builders give the
metric in curvilinear coordinates.

In curvilinear coordinates the components of a tensor in the coordinate
frame have mixed units: g_θθ = r² is in square meters. The components in
the Eulerian frame are orthonormal, so they are all in joules per cubic
meter, as on a Cartesian grid.

| Function | Grid | Metric |
|---|---|---|
| `minkowski_curvilinear` | Spherical or cylindrical | Flat space |
| `schwarzschild_spherical` | Spherical | diag(-(1 - rₛ/r), 1/(1 - rₛ/r), r², r² sin²θ) |
| `warp_shell_spherical` | Spherical | The warp shell, with its polar axis along the direction of travel |
| `alcubierre_cylindrical` | Cylindrical | The comoving Alcubierre bubble, moving along z |
"""

from std.math import cos, isfinite, sin, sqrt

from extensions.warp.grid import SpacetimeGrid, require_single_slice
from extensions.warp.kinds import (
    COORDINATE_FRAME,
    COVARIANT,
    CYLINDRICAL,
    SPHERICAL,
    X_AXIS,
    Y_AXIS,
    Z_AXIS,
)
from extensions.warp.metrics import AlcubierreMetric, alcubierre_shape
from extensions.warp.quantities import light_fraction
from extensions.warp.tensor import Metric, TensorField
from extensions.warp.warp_shell import (
    DEFAULT_RADIAL_SAMPLES,
    RADIAL_MARGIN,
    legendre_radial,
    shell_profile,
)
from units.si import InverseLength64, Length64, Mass64, Velocity64


def _require_spherical(grid: SpacetimeGrid, name: String) raises:
    """Raise unless a grid is spherical."""
    if grid.system != SPHERICAL:
        raise Error(String(name, " needs a spherical grid"))


def _flat(grid: SpacetimeGrid) raises -> TensorField:
    """Return flat space in the grid's coordinates."""
    var out = TensorField(grid, COVARIANT, COORDINATE_FRAME)
    for point in range(grid.points()):  # pragma: no branch
        var at = grid.position(point)
        var first = grid.coordinate(X_AXIS, Int(at[1]))
        out.set(0, 0, point, -1.0)
        out.set(1, 1, point, 1.0)
        if grid.system == SPHERICAL:
            var s = sin(grid.coordinate(Y_AXIS, Int(at[2])))
            out.set(2, 2, point, first * first)
            out.set(3, 3, point, first * first * s * s)
        else:
            out.set(2, 2, point, first * first)
            out.set(3, 3, point, 1.0)
    return out^


def minkowski_curvilinear(grid: SpacetimeGrid) raises -> Metric:
    """Return flat space on a spherical or cylindrical grid.

    Args:
        grid: A spherical or cylindrical grid.

    Returns:
        The metric diag(-1, 1, r², r² sin²θ) or diag(-1, 1, ρ², 1),
        named "Minkowski".

    Raises:
        Error: If the grid is Cartesian. Use `minkowski` there.
    """
    if not (grid.system == SPHERICAL or grid.system == CYLINDRICAL):
        raise Error("minkowski_curvilinear needs a curvilinear grid")
    return Metric(_flat(grid), "Minkowski")


def schwarzschild_spherical(
    grid: SpacetimeGrid, radius: Length64
) raises -> Metric:
    """Return the Schwarzschild metric in Schwarzschild coordinates.

    Args:
        grid: A spherical grid. Every radius must be outside the horizon.
        radius: The Schwarzschild radius rₛ.

    Returns:
        The metric, named "Schwarzschild".

    Raises:
        Error: If the grid is not spherical, the radius is not positive
            and finite, or a grid radius is not outside the horizon.
    """
    _require_spherical(grid, "schwarzschild_spherical")
    if not (isfinite(radius.value) and radius.value > 0.0):
        raise Error("The Schwarzschild radius must be positive and finite")
    if not grid.starts[1] > radius.value:
        raise Error("A spherical grid must start outside the horizon")
    var out = _flat(grid)
    for point in range(grid.points()):  # pragma: no branch
        var r = grid.coordinate(X_AXIS, Int(grid.position(point)[1]))
        var bend = 1.0 - radius.value / r
        out.set(0, 0, point, -bend)
        out.set(1, 1, point, 1.0 / bend)
    return Metric(out^, "Schwarzschild")


def warp_shell_spherical(
    grid: SpacetimeGrid,
    mass: Mass64,
    inner_radius: Length64,
    outer_radius: Length64,
    buffer: Length64 = Length64(0.0),
    sigma: Float64 = 0.0,
    smoothing: Float64 = 1.0,
    speed: Velocity64 = Velocity64(0.0),
    warp: Bool = False,
    samples: Int = DEFAULT_RADIAL_SAMPLES,
) raises -> Metric:
    """Return the warp shell on a spherical grid.

    The polar axis θ = 0 points along the direction of travel. The shell
    is diag(A(r), B(r), r², r² sin²θ), with the profiles of
    `shell_profile`. The warp is WarpFactory's g_tx = -(v/c) S(r),
    written in these coordinates: with x = r cos θ,

        g_tr = -(v/c) S cos θ,   g_tθ = (v/c) S r sin θ.

    The samples reach 1.2 times the last radius of the grid.

    Args:
        grid: A spherical grid with one time slice.
        mass: The mass of the shell.
        inner_radius: R₁.
        outer_radius: R₂.
        buffer: The distance from each radius where the shift starts to
            change.
        sigma: The steepness of the shift.
        smoothing: WarpFactory's `smoothFactor`.
        speed: The speed of the inside along the polar axis.
        warp: Whether to add the shift.
        samples: The number of radial samples.

    Returns:
        The metric, named "Spherical Warp Shell".

    Raises:
        Error: If the grid is not spherical or has more than one slice,
            the speed is not finite, or `shell_profile` refuses the
            parameters.
    """
    _require_spherical(grid, "warp_shell_spherical")
    require_single_slice(grid, "Spherical Warp Shell")
    if not isfinite(speed.value):
        raise Error("A warp speed must be finite")
    var last = grid.coordinate(X_AXIS, grid.count(X_AXIS) - 1)
    var profile = shell_profile(
        Length64(last * RADIAL_MARGIN),
        mass,
        inner_radius,
        outer_radius,
        buffer,
        sigma,
        smoothing,
        samples,
    )
    var beta = 0.0
    if warp:
        beta = light_fraction(speed)
    var dr = profile.radius[1]
    var out = _flat(grid)
    for point in range(grid.points()):  # pragma: no branch
        var at = grid.position(point)
        var r = grid.coordinate(X_AXIS, Int(at[1]))
        var theta = grid.coordinate(Y_AXIS, Int(at[2]))
        var index = 1.0 + r / dr
        var shift = legendre_radial(profile.shift, index) * beta
        out.set(0, 0, point, legendre_radial(profile.g_tt, index))
        out.set(1, 1, point, legendre_radial(profile.g_rr, index))
        out.set_symmetric(0, 1, point, -shift * cos(theta))
        out.set_symmetric(0, 2, point, shift * r * sin(theta))
    return Metric(out^, "Spherical Warp Shell")


def alcubierre_cylindrical(
    grid: SpacetimeGrid,
    speed: Velocity64,
    radius: Length64,
    thickness: InverseLength64,
) raises -> Metric:
    """Return the comoving Alcubierre bubble on a cylindrical grid.

    The bubble sits at the origin and moves along z. With
    r = √(ρ² + z²), the shift is β_z = (v/c)(1 - f(r)).

    Args:
        grid: A cylindrical grid with one time slice.
        speed: The speed of the bubble.
        radius: The radius R of the bubble.
        thickness: The steepness σ of the bubble wall.

    Returns:
        The metric, named "Alcubierre Cylindrical".

    Raises:
        Error: If the grid is not cylindrical or has more than one slice,
            the speed is not finite, or the radius or the steepness is not
            positive and finite.
    """
    if grid.system != CYLINDRICAL:
        raise Error("alcubierre_cylindrical needs a cylindrical grid")
    require_single_slice(grid, "Alcubierre Cylindrical")
    var bubble = AlcubierreMetric(speed, radius, thickness, True)
    var out = _flat(grid)
    for point in range(grid.points()):  # pragma: no branch
        var at = grid.position(point)
        var rho = grid.coordinate(X_AXIS, Int(at[1]))
        var z = grid.coordinate(Z_AXIS, Int(at[3]))
        var f = alcubierre_shape(
            sqrt(rho * rho + z * z), bubble.radius, bubble.sigma
        )
        var shift = bubble.beta * (1.0 - f)
        out.set(0, 0, point, shift * shift - 1.0)
        out.set_symmetric(0, 3, point, shift)
    return Metric(out^, "Alcubierre Cylindrical")
