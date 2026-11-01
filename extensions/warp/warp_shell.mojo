# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The warp shell of Fuchs et al., in the frame that moves with it.

A shell of ordinary matter, between an inner and an outer radius, holds a
static spherical spacetime. A shift inside the shell then moves the
inside along x. The paper is Fuchs, Helmerich, Bobrick, Sellers, Melcher
and Martire, "Constant velocity physical warp drive solution",
Classical and Quantum Gravity 41 (2024) 095013.

`warp_shell_comoving` is WarpFactory's `metricGet_WarpShellComoving`. It
builds the shell along a line of radial samples first:

1. The density is constant between the radii, and the mass inside r is
   the integral of 4 π r² ρ.
2. The pressure is that of a star of constant density, from the
   Tolman-Oppenheimer-Volkoff equation, `tov_constant_density`.
3. The density and the pressure are smoothed with MATLAB's moving
   average, `moving_average`, and the mass is found again.
4. The radial metric is B = 1 / (1 - 2 G M / (c² r)). The time metric is
   A = -e^(2a), with a from `lapse_exponent`.
5. The shift is a smoothed `compact_sigmoid`: 1 inside, 0 outside.

Each grid point then reads the radial profiles with a cubic
interpolation, `legendre_radial`, and turns them into Cartesian
components with `spherical_to_cartesian`.

## Differences from WarpFactory

- `legendre_radial` returns the sample itself at a whole index.
  WarpFactory divides zero by zero there, so a grid point at a sample
  radius, such as the center, is NaN.
- The pressure outside the outer radius is zero. WarpFactory multiplies
  a complex root by zero there and gets zero.
- The number of radial samples is a parameter. WarpFactory always uses
  100000.
- WarpFactory sets a negative enclosed mass to the largest one. The
  smoothed density here is never negative, so the enclosed mass is never
  negative, and that step is not ported.
"""

from std.math import atan2, ceil, cos, exp, floor, isfinite, log, sin, sqrt

from extensions.warp.grid import (
    SpacetimeCenter,
    SpacetimeGrid,
    grid_place,
    grid_time,
    require_cartesian,
    require_single_slice,
)
from extensions.warp.kinds import (
    COORDINATE_FRAME,
    COVARIANT,
    T_AXIS,
    X_AXIS,
    Y_AXIS,
    Z_AXIS,
)
from extensions.warp.krasnikov import smooth_step
from extensions.warp.quantities import (
    GRAVITATIONAL_CONSTANT,
    SPEED_OF_LIGHT,
    light_fraction,
    schwarzschild_radius,
)
from extensions.warp.tensor import Metric, TensorField
from units.si import Duration64, Length64, Mass64, Velocity64

comptime _PI = 3.141592653589793
comptime _HALF_PI = 1.5707963267948966
comptime DEFAULT_RADIAL_SAMPLES = 100000
"""The default number of radial samples: WarpFactory's `rSampleRes`."""
comptime RADIAL_MARGIN = 1.2
"""WarpFactory samples the radius out to this many times the distance of
the last grid point."""


def _two_sum(a: Float64, b: Float64) -> SIMD[DType.float64, 2]:
    """Return a + b and its rounding error, by Knuth's TwoSum."""
    var s = a + b
    var bb = s - a
    return SIMD[DType.float64, 2](s, (a - (s - bb)) + (b - bb))


def moving_average(values: List[Float64], span: Float64) -> List[Float64]:
    """Return the centered moving average of MATLAB's `smooth`.

    The span is rounded down and then made odd. Near the ends the window
    shrinks so that it stays centered: the first and last values are
    kept.

    The window sums come from running sums held in two floats each, so a
    window of zeros sums to exactly zero, as MATLAB's direct sums do, and
    a window of values that are not negative never sums below zero.

    Args:
        values: The samples.
        span: The width of the window, in samples. 1 or more.

    Returns:
        The smoothed samples.
    """
    var n = len(values)
    var width = min(Int(floor(span)), n)
    if width % 2 == 0:
        width -= 1
    var half = (width - 1) // 2
    var high = List[Float64](capacity=n + 1)
    var low = List[Float64](capacity=n + 1)
    high.append(0.0)
    low.append(0.0)
    for i in range(n):
        var s = _two_sum(high[i], values[i])
        var t = _two_sum(s[0], s[1] + low[i])
        high.append(t[0])
        low.append(t[1])
    var out = List[Float64](capacity=n)
    for i in range(n):
        var h = min(half, min(i, n - 1 - i))
        var d = _two_sum(high[i + h + 1], -high[i - h])
        var total = d[0] + (d[1] + (low[i + h + 1] - low[i - h]))
        out.append(total / Float64(2 * h + 1))
    return out^


def cumulative_trapezoid(x: List[Float64], y: List[Float64]) -> List[Float64]:
    """Return the running integral of y over x by the trapezoid rule.

    This is MATLAB's `cumtrapz`. Both lists must have the same length.

    Args:
        x: The sample places, in order.
        y: The values at the places.

    Returns:
        The integral from the first place to each place. The first is 0.
    """
    var out = List[Float64](capacity=len(x))
    var total = 0.0
    out.append(total)
    for i in range(1, len(x)):
        total += (x[i] - x[i - 1]) * (y[i] + y[i - 1]) / 2.0
        out.append(total)
    return out^


def compact_sigmoid(
    r: Float64,
    inner: Float64,
    outer: Float64,
    sigma: Float64,
    buffer: Float64,
) -> Float64:
    """Return the shift profile of the warp shell: 1 inside, 0 outside.

    Between R₁ + b and R₂ - b the profile falls smoothly:

        f = 1 - 1 / (exp(k (1/(r - R₂ + b) + 1/(r - R₁ - b))) + 1)
        k = (R₂ - R₁ - 2 b) (σ + 2) / 2

    This is WarpFactory's `compactSigmoid`.

    Args:
        r: The radius, in meters.
        inner: R₁, in meters.
        outer: R₂, in meters.
        sigma: σ, which makes the fall steeper.
        buffer: The distance b from each radius where the fall starts,
            in meters.

    Returns:
        The profile, from 0 to 1.
    """
    if r >= outer - buffer:
        return 0.0
    if r <= inner + buffer:
        return 1.0
    var k = (outer - inner - 2.0 * buffer) * (sigma + 2.0) / 2.0
    var power = k * (1.0 / (r - outer + buffer) + 1.0 / (r - inner - buffer))
    return 1.0 - 1.0 / (exp(power) + 1.0)


def tov_constant_density(
    radius: Float64, total_mass: Float64, density: Float64, r: Float64
) -> Float64:
    """Return the pressure inside a star of constant density.

    This is the Schwarzschild interior solution, WarpFactory's
    `TOVconstDensity`. With rₛ = 2 G M / c²:

        P = ρ c² (R √(R - rₛ) - √(R³ - rₛ r²)) / (√(R³ - rₛ r²) - 3 R √(R - rₛ))

    Args:
        radius: R, the outer radius of the star, in meters.
        total_mass: M, its whole mass, in kilograms. rₛ must be less than
            8 R / 9.
        density: ρ at r, in kilograms per cubic meter.
        r: The radius, in meters.

    Returns:
        The pressure, in pascals. It is zero at R and outside.
    """
    if r >= radius:
        return 0.0
    var c = SPEED_OF_LIGHT.value
    var rs = 2.0 * GRAVITATIONAL_CONSTANT.value * total_mass / (c * c)
    var edge = radius * sqrt(radius - rs)
    var inside = sqrt(radius * radius * radius - rs * r * r)
    return c * c * density * (edge - inside) / (inside - 3.0 * edge)


def lapse_exponent(
    mass: List[Float64], pressure: List[Float64], r: List[Float64]
) -> List[Float64]:
    """Return a(r), with g_tt = -e^(2a), from the TOV equations.

        da/dr = (G M / c² + 4 π G r³ P / c⁴) / (r² - 2 G M r / c²)

    The derivative at the first sample is taken as 0. The integral is
    shifted so that a = ln(1 - 2 G M / (c² r)) / 2 at the last sample,
    which matches the Schwarzschild metric outside. This is
    WarpFactory's `alphaNumericSolver`.

    Args:
        mass: The mass inside each radius, in kilograms.
        pressure: The pressure at each radius, in pascals.
        r: The radii, in meters, from 0.

    Returns:
        The exponent a at each radius.
    """
    var g = GRAVITATIONAL_CONSTANT.value
    var c = SPEED_OF_LIGHT.value
    var slope = List[Float64](capacity=len(r))
    slope.append(0.0)
    for i in range(1, len(r)):
        var ri = r[i]
        slope.append(
            (
                g * mass[i] / (c * c)
                + 4.0 * _PI * g * ri * ri * ri * pressure[i] / (c * c * c * c)
            )
            / (ri * ri - 2.0 * g * mass[i] * ri / (c * c))
        )
    var out = cumulative_trapezoid(r, slope)
    var last = len(r) - 1
    var offset = (
        0.5 * log(1.0 - 2.0 * g * mass[last] / (r[last] * c * c)) - out[last]
    )
    for i in range(len(out)):  # pragma: no branch
        out[i] += offset
    return out^


def legendre_radial(values: List[Float64], index: Float64) -> Float64:
    """Return a cubic interpolation of samples at a fractional index.

    This is WarpFactory's `legendreRadialInterp`. The index counts from 1,
    as in WarpFactory. The four nodes are floor(i - 1), floor(i), ceil(i)
    and ceil(i + 1). A node below 1 reads the first sample but keeps its
    own place.

    Args:
        values: The samples. The index plus 2 must not pass their count.
        index: The place, counted from 1.

    Returns:
        The interpolated value. At a whole index it is that sample.
    """
    var x1 = floor(index)
    var x2 = ceil(index)
    if x1 == x2:
        return values[Int(x1) - 1]
    var x0 = floor(index - 1.0)
    var x3 = ceil(index + 1.0)
    var y0 = values[max(Int(x0), 1) - 1]
    var y1 = values[max(Int(x1), 1) - 1]
    var y2 = values[max(Int(x2), 1) - 1]
    var y3 = values[max(Int(x3), 1) - 1]
    var x = index
    return (
        y0
        * (x - x1)
        * (x - x2)
        * (x - x3)
        / ((x0 - x1) * (x0 - x2) * (x0 - x3))
        + y1
        * (x - x0)
        * (x - x2)
        * (x - x3)
        / ((x1 - x0) * (x1 - x2) * (x1 - x3))
        + y2
        * (x - x0)
        * (x - x1)
        * (x - x3)
        / ((x2 - x0) * (x2 - x1) * (x2 - x3))
        + y3
        * (x - x0)
        * (x - x1)
        * (x - x2)
        / ((x3 - x0) * (x3 - x1) * (x3 - x2))
    )


def spherical_to_cartesian(
    theta: Float64, phi: Float64, g_tt: Float64, g_rr: Float64
) -> SIMD[DType.float64, 8]:
    """Return the Cartesian components of a diagonal spherical metric.

    The metric is diag(g_tt, g_rr, r², r² sin²θ). This is WarpFactory's
    `sph2cartDiag`. It takes the cosine of an angle of exactly ±π/2 as 0.

    Args:
        theta: The polar angle, from +z.
        phi: The azimuth, from +x toward +y.
        g_tt: The time component.
        g_rr: The radial component.

    Returns:
        The components g_tt, g_xx, g_xy, g_xz, g_yy, g_yz and g_zz,
        then 0.
    """
    var e = g_rr
    var cos_phi = cos(phi)
    if abs(phi) == _HALF_PI:
        cos_phi = 0.0
    var cos_theta = cos(theta)
    if abs(theta) == _HALF_PI:
        cos_theta = 0.0
    var sin_phi = sin(phi)
    var sin_theta = sin(theta)
    var xx = (
        e * cos_phi * cos_phi * sin_theta * sin_theta
        + cos_phi * cos_phi * cos_theta * cos_theta
        + sin_phi * sin_phi
    )
    var yy = (
        e * sin_phi * sin_phi * sin_theta * sin_theta
        + cos_theta * cos_theta * sin_phi * sin_phi
        + cos_phi * cos_phi
    )
    var zz = e * cos_theta * cos_theta + sin_theta * sin_theta
    var xy = (
        e * cos_phi * sin_phi * sin_theta * sin_theta
        + cos_phi * cos_theta * cos_theta * sin_phi
        - cos_phi * sin_phi
    )
    var xz = (
        e * cos_phi * cos_theta * sin_theta - cos_phi * cos_theta * sin_theta
    )
    var yz = (
        e * cos_theta * sin_phi * sin_theta - cos_theta * sin_phi * sin_theta
    )
    return SIMD[DType.float64, 8](g_tt, xx, xy, xz, yy, yz, zz, 0.0)


struct ShellProfile(Copyable, Movable):
    """The radial profiles of a warp shell."""

    var radius: List[Float64]
    """The sample radii, in meters, from 0."""
    var density: List[Float64]
    """The smoothed density, in kilograms per cubic meter."""
    var pressure: List[Float64]
    """The smoothed pressure, in pascals."""
    var mass: List[Float64]
    """The mass inside each radius, in kilograms."""
    var g_tt: List[Float64]
    """A = -e^(2a), the time component of the metric."""
    var g_rr: List[Float64]
    """B = 1 / (1 - 2 G M / (c² r)), the radial component."""
    var shift: List[Float64]
    """The smoothed shift profile, from 1 inside to 0 outside."""

    def __init__(
        out self,
        var radius: List[Float64],
        var density: List[Float64],
        var pressure: List[Float64],
        var mass: List[Float64],
        var g_tt: List[Float64],
        var g_rr: List[Float64],
        var shift: List[Float64],
    ):
        """Hold the profiles.

        Args:
            radius: The sample radii.
            density: The smoothed density.
            pressure: The smoothed pressure.
            mass: The enclosed mass.
            g_tt: The time component of the metric.
            g_rr: The radial component of the metric.
            shift: The smoothed shift profile.
        """
        self.radius = radius^
        self.density = density^
        self.pressure = pressure^
        self.mass = mass^
        self.g_tt = g_tt^
        self.g_rr = g_rr^
        self.shift = shift^


def _smooth4(values: List[Float64], span: Float64) -> List[Float64]:
    """Return four passes of the moving average, as WarpFactory smooths."""
    var out = moving_average(values, span)
    for _ in range(3):
        out = moving_average(out, span)
    return out^


def _enclosed_mass(r: List[Float64], density: List[Float64]) -> List[Float64]:
    """Return the mass inside each radius, the integral of 4 π r² ρ."""
    var shell = List[Float64](capacity=len(r))
    for i in range(len(r)):  # pragma: no branch
        shell.append(4.0 * _PI * density[i] * r[i] * r[i])
    return cumulative_trapezoid(r, shell)


def shell_profile(
    extent: Length64,
    mass: Mass64,
    inner_radius: Length64,
    outer_radius: Length64,
    buffer: Length64,
    sigma: Float64,
    smoothing: Float64,
    samples: Int = DEFAULT_RADIAL_SAMPLES,
) raises -> ShellProfile:
    """Return the radial profiles of a warp shell.

    Args:
        extent: The largest radius to sample.
        mass: The mass of the shell.
        inner_radius: R₁.
        outer_radius: R₂.
        buffer: The distance from each radius where the shift starts to
            change.
        sigma: The steepness of the shift.
        smoothing: WarpFactory's `smoothFactor`: the width of the moving
            average, in samples. The density is smoothed with 1.79 times
            this width.
        samples: The number of radial samples. 4 or more.

    Returns:
        The profiles.

    Raises:
        Error: If a size is not finite, the radii are not ordered, the
            buffer is negative, σ is not above -2, the smoothing is below
            1, the samples are fewer than 4, or 2 G M / c² is not below
            8/9 of R₂, where the pressure at the center is infinite.
    """
    if not (
        isfinite(extent.value)
        and isfinite(mass.value)
        and isfinite(inner_radius.value)
        and isfinite(outer_radius.value)
        and isfinite(buffer.value)
        and isfinite(sigma)
        and isfinite(smoothing)
    ):
        raise Error("A warp shell parameter must be finite")
    var r1 = inner_radius.value
    var r2 = outer_radius.value
    if not (0.0 <= r1 and r1 < r2 and r2 < extent.value):
        raise Error("A warp shell needs 0 <= R1 < R2 < the sampled extent")
    if mass.value < 0.0 or buffer.value < 0.0:
        raise Error("A warp shell mass and buffer must not be negative")
    if sigma <= -2.0 or smoothing < 1.0 or samples < 4:
        raise Error(
            "A warp shell needs sigma > -2, smoothing >= 1 and 4 samples"
        )
    if schwarzschild_radius(mass).value >= 8.0 / 9.0 * r2:
        raise Error("A warp shell is too heavy to be static")
    var r = List[Float64](capacity=samples)
    for i in range(samples):  # pragma: no branch
        r.append(extent.value * Float64(i) / Float64(samples - 1))
    var rho = mass.value / (4.0 / 3.0 * _PI * (r2 * r2 * r2 - r1 * r1 * r1))
    var density = List[Float64](capacity=samples)
    for i in range(samples):  # pragma: no branch
        density.append(rho if (r[i] > r1 and r[i] < r2) else 0.0)
    var total = _enclosed_mass(r, density)[samples - 1]
    var pressure = List[Float64](capacity=samples)
    for i in range(samples):  # pragma: no branch
        pressure.append(tov_constant_density(r2, total, density[i], r[i]))
    var smooth_density = _smooth4(density, 1.79 * smoothing)
    var smooth_pressure = _smooth4(pressure, smoothing)
    var enclosed = _enclosed_mass(r, smooth_density)
    var shift = List[Float64](capacity=samples)
    for i in range(samples):  # pragma: no branch
        shift.append(compact_sigmoid(r[i], r1, r2, sigma, buffer.value))
    shift = moving_average(moving_average(shift, smoothing), smoothing)
    var c = SPEED_OF_LIGHT.value
    var g = GRAVITATIONAL_CONSTANT.value
    var g_rr = List[Float64](capacity=samples)
    g_rr.append(1.0)
    for i in range(1, samples):  # pragma: no branch
        g_rr.append(1.0 / (1.0 - 2.0 * g * enclosed[i] / (r[i] * c * c)))
    var a = lapse_exponent(enclosed, smooth_pressure, r)
    var g_tt = List[Float64](capacity=samples)
    for i in range(samples):  # pragma: no branch
        g_tt.append(-exp(2.0 * a[i]))
    return ShellProfile(
        r^,
        smooth_density^,
        smooth_pressure^,
        enclosed^,
        g_tt^,
        g_rr^,
        shift^,
    )


def require_profile(profile: ShellProfile) raises:
    """Raise unless a radial profile can be read at any radius it spans.

    Args:
        profile: The profile.

    Raises:
        Error: If its lists differ in length, it has fewer than 4
            samples, its radii do not start at 0 and rise in equal steps,
            or a value is not finite.
    """
    var n = len(profile.radius)
    if n < 4:
        raise Error("A shell profile needs at least 4 samples")
    if (
        len(profile.g_tt) != n
        or len(profile.g_rr) != n
        or len(profile.shift) != n
    ):
        raise Error("A shell profile's lists must have one length")
    var step = profile.radius[1]
    if profile.radius[0] != 0.0 or not (isfinite(step) and step > 0.0):
        raise Error("A shell profile's radii must start at 0 and rise")
    for i in range(n):  # pragma: no branch
        if abs(profile.radius[i] - Float64(i) * step) > 1e-9 * step * Float64(
            n
        ):
            raise Error("A shell profile's radii must have equal steps")
        if not (
            isfinite(profile.g_tt[i])
            and isfinite(profile.g_rr[i])
            and isfinite(profile.shift[i])
        ):
            raise Error("A shell profile value is not finite")


def _world_extent(grid: SpacetimeGrid, center: SpacetimeCenter) -> Float64:
    """Return WarpFactory's sampled extent: 1.2 times the distance of the
    last grid point."""
    var far_x = grid_place(grid, center, X_AXIS, grid.count(X_AXIS) - 1)
    var far_y = grid_place(grid, center, Y_AXIS, grid.count(Y_AXIS) - 1)
    var far_z = grid_place(grid, center, Z_AXIS, grid.count(Z_AXIS) - 1)
    return sqrt(far_x * far_x + far_y * far_y + far_z * far_z) * RADIAL_MARGIN


def _shell_metric(
    grid: SpacetimeGrid,
    center: SpacetimeCenter,
    profile: ShellProfile,
    betas: List[Float64],
    name: String,
) raises -> Metric:
    """Return a shell from its profile, with speed betas[t] over c in slice
    t."""
    require_cartesian(grid, name)
    var samples = len(profile.radius)
    var dr = profile.radius[1]
    var out = TensorField(grid, COVARIANT, COORDINATE_FRAME)
    var stride = grid.stride(T_AXIS)
    for point in range(stride):  # pragma: no branch
        var at = grid.position(point)
        var x = grid_place(grid, center, X_AXIS, Int(at[1]))
        var y = grid_place(grid, center, Y_AXIS, Int(at[2]))
        var z = grid_place(grid, center, Z_AXIS, Int(at[3]))
        var r = sqrt(x * x + y * y + z * z)
        var below = floor(r / dr)
        # The cubic reads up to 3 samples past the one below r.
        if below + 3.0 > Float64(samples):
            raise Error("A grid point is past the radial samples")
        var index = below + 1.0 + (r - profile.radius[Int(below)]) / dr
        var g = spherical_to_cartesian(
            atan2(sqrt(x * x + y * y), z),
            atan2(y, x),
            legendre_radial(profile.g_tt, index),
            legendre_radial(profile.g_rr, index),
        )
        var shift = legendre_radial(profile.shift, index)
        for t in range(grid.count(T_AXIS)):  # pragma: no branch
            var p = point + t * stride
            out.set(0, 0, p, g[0])
            out.set(1, 1, p, g[1])
            out.set_symmetric(1, 2, p, g[2])
            out.set_symmetric(1, 3, p, g[3])
            out.set(2, 2, p, g[4])
            out.set_symmetric(2, 3, p, g[5])
            out.set(3, 3, p, g[6])
            out.set_symmetric(0, 1, p, -shift * betas[t])
    return Metric(out^, name)


def shell_from_profile(
    grid: SpacetimeGrid,
    center: SpacetimeCenter,
    profile: ShellProfile,
    speed: Velocity64,
) raises -> Metric:
    """Return a static spherical shell built from radial profiles.

    The metric is diag(g_tt(r), g_rr(r), r², r² sin²θ) in Cartesian form,
    and g_tx = -(v/c) times the shift profile. Any profiles can be given,
    such as those of `shell_profile` or of another matter distribution.
    Bobrick and Martire describe warp drives as shells of this kind
    ("Introducing physical warp drives", Classical and Quantum Gravity 38
    (2021) 105009). This builder is the general form of WarpFactory's warp
    shell, not a port of their paper.

    Args:
        grid: The grid. The metric is the same in every time slice.
        center: The origin, at the center of the shell.
        profile: The radial profiles, sampled from r = 0 in equal steps.
        speed: The speed of the inside along x.

    Returns:
        The metric, named "Shell".

    Raises:
        Error: If the center or the speed is not finite,
            `require_profile` refuses the profile, or a grid point is
            past the last sample.
    """
    center.require_finite()
    if not isfinite(speed.value):
        raise Error("A warp speed must be finite")
    require_profile(profile)
    var betas = List[Float64](
        length=grid.count(T_AXIS), fill=light_fraction(speed)
    )
    return _shell_metric(grid, center, profile, betas, "Shell")


def accelerating_shell(
    grid: SpacetimeGrid,
    center: SpacetimeCenter,
    profile: ShellProfile,
    start_speed: Velocity64,
    end_speed: Velocity64,
    start: Duration64,
    duration: Duration64,
) raises -> Metric:
    """Return a shell whose inside changes speed over time.

    The shell itself is static. The speed in the shift goes from
    `start_speed` to `end_speed` along the smooth step of
    `extensions.warp.krasnikov.smooth_step`, from `start` for `duration`.
    How to accelerate a physical warp shell is an open question: Fuchs et
    al. leave it for future work. This metric is a test case to analyze,
    not a solution. Its stress-energy tensor shows what this naive change
    of speed needs.

    Args:
        grid: The grid. The time derivatives need 5 slices or more.
        center: The origin, at the center of the shell. Its time is the
            time 0 of the ramp.
        profile: The radial profiles, as for `shell_from_profile`.
        start_speed: The speed before the ramp.
        end_speed: The speed after the ramp.
        start: When the ramp starts, from the center's time.
        duration: How long the ramp lasts. It must be positive.

    Returns:
        The metric, named "Accelerating Shell".

    Raises:
        Error: If the center, a speed or a time is not finite, the
            duration is not positive, `require_profile` refuses the
            profile, the grid is not Cartesian, or a grid point is past the last
            sample.
    """
    center.require_finite()
    if not (
        isfinite(start_speed.value)
        and isfinite(end_speed.value)
        and isfinite(start.value)
    ):
        raise Error("A shell's speeds and start time must be finite")
    if not (isfinite(duration.value) and duration.value > 0.0):
        raise Error("A shell's ramp must last a positive, finite time")
    require_profile(profile)
    var low = light_fraction(start_speed)
    var high = light_fraction(end_speed)
    var betas = List[Float64](capacity=grid.count(T_AXIS))
    for t in range(grid.count(T_AXIS)):  # pragma: no branch
        var since = grid_time(grid, center, t) - start.value
        var step = smooth_step(since, duration.value)
        betas.append(low + (high - low) * step[0])
    return _shell_metric(grid, center, profile, betas, "Accelerating Shell")


def warp_shell_comoving(
    grid: SpacetimeGrid,
    center: SpacetimeCenter,
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
    """Return the warp shell metric in the frame that moves with it.

    This is WarpFactory's `metricGet_WarpShellComoving`. Without the warp
    the metric is static and spherical. With the warp, g_tx is
    -(v/c) times the shift profile.

    Args:
        grid: The grid. It must have one time slice.
        center: The origin, at the center of the shell.
        mass: The mass of the shell.
        inner_radius: R₁, the inner radius of the shell.
        outer_radius: R₂, the outer radius of the shell.
        buffer: The distance from each radius where the shift starts to
            change.
        sigma: The steepness of the shift.
        smoothing: WarpFactory's `smoothFactor`. 1 or more.
        speed: The speed of the inside along x.
        warp: Whether to add the shift.
        samples: The number of radial samples.

    Returns:
        The metric, named "Comoving Warp Shell".

    Raises:
        Error: If the grid has more than one slice, the center or the
            speed is not finite, `shell_profile` refuses the parameters,
            the grid is not Cartesian, or the grid reaches past the radial
            samples.
    """
    require_single_slice(grid, "Comoving Warp Shell")
    center.require_finite()
    if not isfinite(speed.value):
        raise Error("A warp speed must be finite")
    var profile = shell_profile(
        Length64(_world_extent(grid, center)),
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
    var betas: List[Float64] = [beta]
    return _shell_metric(grid, center, profile, betas, "Comoving Warp Shell")
