# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The metrics that WarpFactory builds in closed form.

Each function samples one metric on a grid. A warp drive moves along x
at a constant speed. A function that ends in `_comoving` gives the metric
in the frame that moves with the drive, on a grid with one time slice.
The others move the drive across the time slices.

| Function | WarpFactory | Reference |
|---|---|---|
| `minkowski` | `metricGet_Minkowski` | Flat space |
| `alcubierre` | `metricGet_Alcubierre` | Alcubierre 1994 |
| `lentz` | `metricGet_Lentz` | Lentz 2021 |
| `van_den_broeck` | `metricGet_VanDenBroeck` | Van Den Broeck 1999 |
| `modified_time` | `metricGet_ModifiedTime` | An Alcubierre drive with a changed lapse |
| `schwarzschild` | `metricGet_Schwarzschild` | A black hole, in Cartesian coordinates |

## Differences from WarpFactory

- `modified_time` and `modified_time_comoving` read the x, y and z steps
  and centers. WarpFactory reads the t, x and y ones, one axis too early.
  WarpFactory also copies g_01 from the wrong point to g_10, and its
  time-dependent version stops on an undefined `gridScale`. Here the
  metric is symmetric and both versions run.
- A Lentz metric needs its size scale. WarpFactory's default, the
  largest count over 7, ignores the grid step.
"""

from std.math import isfinite, sqrt, tanh

from extensions.warp.grid import (
    SpacetimeCenter,
    SpacetimeGrid,
    grid_place,
    grid_time,
    require_single_slice,
)
from extensions.warp.kinds import (
    COORDINATE_FRAME,
    COVARIANT,
    X_AXIS,
    Y_AXIS,
    Z_AXIS,
)
from extensions.warp.quantities import SPEED_OF_LIGHT, light_fraction
from extensions.warp.tensor import Metric, TensorField
from extensions.warp.three_plus_one import ThreePlusOne
from units.si import InverseLength64, Length64, Velocity64

comptime SCHWARZSCHILD_OFFSET = 1e-10
"""WarpFactory adds this to the Schwarzschild radius of every point, in
meters, so that a point at the center does not divide by zero."""


def alcubierre_shape(r: Float64, radius: Float64, sigma: Float64) -> Float64:
    """Return Alcubierre's top-hat shape function f(r).

    f is near 1 inside the bubble and near 0 outside it.

        f(r) = (tanh(σ (R + r)) + tanh(σ (R - r))) / (2 tanh(σ R))

    This is WarpFactory's `shapeFunction_Alcubierre`.

    Args:
        r: The distance from the center of the bubble, in meters.
        radius: The radius R of the bubble, in meters.
        sigma: The steepness σ of the wall, per meter.

    Returns:
        The value of f at r. It is 1 at r = 0.
    """
    return (tanh(sigma * (radius + r)) + tanh(sigma * (radius - r))) / (
        2.0 * tanh(radius * sigma)
    )


def _factors(wx: Float64, wy: Float64) -> SIMD[DType.float64, 2]:
    """Return the two factors as a pair."""
    return SIMD[DType.float64, 2](wx, wy)


def lentz_warp_factors(
    x: Float64, y: Float64, scale: Float64
) -> SIMD[DType.float64, 2]:
    """Return the two shift factors of the Lentz soliton at a point.

    The soliton is a set of diamond-shaped regions in the x-y plane. Each
    region has a constant factor along x and along y. This gives the same
    factors as the `getWarpFactorByRegion` of WarpFactory's Lentz metric.
    WarpFactory tests seven regions one after the other. Here the test is
    split by the band of x first, so that no condition repeats another.

    Args:
        x: The place along the direction of travel, from the center, in
            meters.
        y: The place along y, from the center, in meters.
        scale: The size s of one region, in meters.

    Returns:
        The factor along x, then the factor along y. Both are 0 outside
        the soliton. The factor along y has the sign of y.
    """
    var s = scale
    var ay = abs(y)
    var sign = 1.0
    if y < 0.0:
        sign = -1.0
    if x > 2.0 * s or x <= -s:
        return _factors(0.0, 0.0)
    if x >= s:
        if ay <= x - s:
            return _factors(-2.0, 0.0)
        if x > s:
            if ay <= 3.0 * s - x:
                return _factors(-1.0, sign)
            return _factors(0.0, 0.0)
    if x > 0.0:
        if ay < x + s:
            if ay > s - x:
                return _factors(0.0, sign)
            return _factors(1.0, 0.0)
        if ay <= 3.0 * s - x:
            return _factors(-0.5, 0.5 * sign)
        return _factors(0.0, 0.0)
    if ay > s - x:
        if ay <= 3.0 * s + x:
            return _factors(0.5, 0.5 * sign)
        return _factors(0.0, 0.0)
    return _factors(1.0, 0.0)


def _require_center(center: SpacetimeCenter) raises:
    """Raise unless the center is finite."""
    center.require_finite()


def _require_speed(speed: Velocity64) raises:
    """Raise unless a speed is finite."""
    if not isfinite(speed.value):
        raise Error("A warp speed must be finite")


def _require_size(value: Float64, name: String) raises:
    """Raise unless a size is positive and finite."""
    if not (isfinite(value) and value > 0.0):
        raise Error(String("The ", name, " must be positive and finite"))


def _require_bubble(radius: Length64, thickness: InverseLength64) raises:
    """Raise unless a bubble's radius and steepness are usable."""
    _require_size(radius.value, "bubble radius")
    _require_size(thickness.value, "bubble steepness")


def _place(
    grid: SpacetimeGrid, center: SpacetimeCenter, point: Int
) -> SIMD[DType.float64, 4]:
    """Return the time in seconds and the x, y and z in meters of a point."""
    var at = grid.position(point)
    return SIMD[DType.float64, 4](
        grid_time(grid, center, Int(at[0])),
        grid_place(grid, center, X_AXIS, Int(at[1])),
        grid_place(grid, center, Y_AXIS, Int(at[2])),
        grid_place(grid, center, Z_AXIS, Int(at[3])),
    )


def _distance(x: Float64, y: Float64, z: Float64) -> Float64:
    """Return the length of a vector."""
    return sqrt(x * x + y * y + z * z)


def minkowski(grid: SpacetimeGrid) raises -> Metric:
    """Return flat space, diag(-1, 1, 1, 1) at every point.

    This is WarpFactory's `metricGet_Minkowski`.

    Args:
        grid: The grid.

    Returns:
        The metric, named "Minkowski".

    Raises:
        Error: Never, for a valid grid.
    """
    return ThreePlusOne(grid).metric("Minkowski")


def alcubierre(
    grid: SpacetimeGrid,
    center: SpacetimeCenter,
    speed: Velocity64,
    radius: Length64,
    thickness: InverseLength64,
) raises -> Metric:
    """Return the Alcubierre metric, with the bubble moving along x.

    The bubble's center is at x = v t. The shift is β_x = -(v/c) f(r),
    with r the distance from the center of the bubble. This is
    WarpFactory's `metricGet_Alcubierre`.

    Args:
        grid: The grid. The time derivatives need 5 slices or more.
        center: The origin. The bubble is at the origin at time 0.
        speed: The speed of the bubble. It can exceed c.
        radius: The radius R of the bubble.
        thickness: The steepness σ of the bubble wall.

    Returns:
        The metric, named "Alcubierre".

    Raises:
        Error: If the center or the speed is not finite, or the radius or
            the steepness is not positive and finite.
    """
    _require_center(center)
    _require_speed(speed)
    _require_bubble(radius, thickness)
    var beta = light_fraction(speed)
    var parts = ThreePlusOne(grid)
    for point in range(grid.points()):  # pragma: no branch
        var p = _place(grid, center, point)
        var xs = p[0] * speed.value
        var r = _distance(p[1] - xs, p[2], p[3])
        var f = alcubierre_shape(r, radius.value, thickness.value)
        parts.set_shift(0, point, -beta * f)
    return parts.metric("Alcubierre")


def alcubierre_comoving(
    grid: SpacetimeGrid,
    center: SpacetimeCenter,
    speed: Velocity64,
    radius: Length64,
    thickness: InverseLength64,
) raises -> Metric:
    """Return the Alcubierre metric in the frame that moves with the bubble.

    The frame moves at the bubble's speed, so the shift is
    β_x = (v/c) (1 - f(r)) and the bubble stays at the origin. This is
    WarpFactory's `metricGet_AlcubierreComoving`.

    Args:
        grid: The grid. It must have one time slice.
        center: The origin, at the center of the bubble.
        speed: The speed of the bubble.
        radius: The radius R of the bubble.
        thickness: The steepness σ of the bubble wall.

    Returns:
        The metric, named "Alcubierre Comoving".

    Raises:
        Error: If the grid has more than one slice, the center or the
            speed is not finite, or the radius or the steepness is not
            positive and finite.
    """
    require_single_slice(grid, "Alcubierre Comoving")
    _require_center(center)
    _require_speed(speed)
    _require_bubble(radius, thickness)
    var beta = light_fraction(speed)
    var parts = ThreePlusOne(grid)
    for point in range(grid.points()):  # pragma: no branch
        var p = _place(grid, center, point)
        var r = _distance(p[1], p[2], p[3])
        var f = alcubierre_shape(r, radius.value, thickness.value)
        parts.set_shift(0, point, beta * (1.0 - f))
    return parts.metric("Alcubierre Comoving")


def lentz(
    grid: SpacetimeGrid,
    center: SpacetimeCenter,
    speed: Velocity64,
    scale: Length64,
) raises -> Metric:
    """Return the Lentz soliton, moving along x.

    The shift is β_x = -(v/c) w_x and β_y = (v/c) w_y, with the factors
    of `lentz_warp_factors` at the point's place from the soliton's
    center. The soliton does not depend on z. This is WarpFactory's
    `metricGet_Lentz`.

    Args:
        grid: The grid. The time derivatives need 5 slices or more.
        center: The origin. The soliton is at the origin at time 0.
        speed: The speed of the soliton.
        scale: The size of one region of the soliton.

    Returns:
        The metric, named "Lentz".

    Raises:
        Error: If the center or the speed is not finite, or the scale is
            not positive and finite.
    """
    _require_center(center)
    _require_speed(speed)
    _require_size(scale.value, "Lentz scale")
    var beta = light_fraction(speed)
    var parts = ThreePlusOne(grid)
    for point in range(grid.points()):  # pragma: no branch
        var p = _place(grid, center, point)
        var w = lentz_warp_factors(p[1] - p[0] * speed.value, p[2], scale.value)
        parts.set_shift(0, point, -w[0] * beta)
        parts.set_shift(1, point, w[1] * beta)
    return parts.metric("Lentz")


def lentz_comoving(
    grid: SpacetimeGrid,
    center: SpacetimeCenter,
    speed: Velocity64,
    scale: Length64,
) raises -> Metric:
    """Return the Lentz soliton in the frame that moves with it.

    The shift is β_x = (v/c) (1 - w_x) and β_y = (v/c) w_y. This is
    WarpFactory's `metricGet_LentzComoving`.

    Args:
        grid: The grid. It must have one time slice.
        center: The origin, at the center of the soliton.
        speed: The speed of the soliton.
        scale: The size of one region of the soliton.

    Returns:
        The metric, named "Lentz Comoving".

    Raises:
        Error: If the grid has more than one slice, the center or the
            speed is not finite, or the scale is not positive and finite.
    """
    require_single_slice(grid, "Lentz Comoving")
    _require_center(center)
    _require_speed(speed)
    _require_size(scale.value, "Lentz scale")
    var beta = light_fraction(speed)
    var parts = ThreePlusOne(grid)
    for point in range(grid.points()):  # pragma: no branch
        var p = _place(grid, center, point)
        var w = lentz_warp_factors(p[1], p[2], scale.value)
        parts.set_shift(0, point, beta * (1.0 - w[0]))
        parts.set_shift(1, point, beta * w[1])
    return parts.metric("Lentz Comoving")


def _modified_time_lapse(f: Float64, lapse_factor: Float64) -> Float64:
    """Return the lapse of the modified-time metric, (1 - f) + f / A."""
    return (1.0 - f) + f / lapse_factor


def _require_lapse_factor(lapse_factor: Float64) raises:
    """Raise unless the lapse factor A is finite and not zero."""
    if not isfinite(lapse_factor) or lapse_factor == 0.0:
        raise Error("The lapse factor must be finite and not zero")


def modified_time(
    grid: SpacetimeGrid,
    center: SpacetimeCenter,
    speed: Velocity64,
    radius: Length64,
    thickness: InverseLength64,
    lapse_factor: Float64,
) raises -> Metric:
    """Return an Alcubierre metric whose lapse changes inside the bubble.

    The lapse is α = (1 - f) + f / A, so a clock inside the bubble runs
    at 1/A of the rate of one outside. The shift is the Alcubierre
    shift. This is WarpFactory's `metricGet_ModifiedTime`, corrected:
    see the module notes.

    Args:
        grid: The grid. The time derivatives need 5 slices or more.
        center: The origin. The bubble is at the origin at time 0.
        speed: The speed of the bubble.
        radius: The radius R of the bubble.
        thickness: The steepness σ of the bubble wall.
        lapse_factor: A, the factor that the lapse is divided by inside.

    Returns:
        The metric, named "Modified Time".

    Raises:
        Error: If the center, the speed or A is not finite, A is zero, or
            the radius or the steepness is not positive and finite.
    """
    _require_center(center)
    _require_speed(speed)
    _require_bubble(radius, thickness)
    _require_lapse_factor(lapse_factor)
    var beta = light_fraction(speed)
    var parts = ThreePlusOne(grid)
    for point in range(grid.points()):  # pragma: no branch
        var p = _place(grid, center, point)
        var xs = p[0] * speed.value
        var r = _distance(p[1] - xs, p[2], p[3])
        var f = alcubierre_shape(r, radius.value, thickness.value)
        parts.lapse[point] = _modified_time_lapse(f, lapse_factor)
        parts.set_shift(0, point, -beta * f)
    return parts.metric("Modified Time")


def modified_time_comoving(
    grid: SpacetimeGrid,
    center: SpacetimeCenter,
    speed: Velocity64,
    radius: Length64,
    thickness: InverseLength64,
    lapse_factor: Float64,
) raises -> Metric:
    """Return the modified-time metric in the frame that moves with it.

    The shift is β_x = (v/c) (1 - f(r)) and the lapse is that of
    `modified_time`. WarpFactory's `metricGet_ModifiedTimeComoving` keeps
    g_00 = -α² + (v f / c)², the value of the moving frame, and so does
    this function.

    Args:
        grid: The grid. It must have one time slice.
        center: The origin, at the center of the bubble.
        speed: The speed of the bubble.
        radius: The radius R of the bubble.
        thickness: The steepness σ of the bubble wall.
        lapse_factor: A, the factor that the lapse is divided by inside.

    Returns:
        The metric, named "Modified Time Comoving".

    Raises:
        Error: If the grid has more than one slice, the center, the speed
            or A is not finite, A is zero, or the radius or the steepness
            is not positive and finite.
    """
    require_single_slice(grid, "Modified Time Comoving")
    _require_center(center)
    _require_speed(speed)
    _require_bubble(radius, thickness)
    _require_lapse_factor(lapse_factor)
    var beta = light_fraction(speed)
    var out = minkowski(grid).tensor.copy()
    for point in range(grid.points()):  # pragma: no branch
        var p = _place(grid, center, point)
        var r = _distance(p[1], p[2], p[3])
        var f = alcubierre_shape(r, radius.value, thickness.value)
        var lapse = _modified_time_lapse(f, lapse_factor)
        out.set_symmetric(0, 1, point, beta * (1.0 - f))
        out.set(0, 0, point, -lapse * lapse + (f * beta) * (f * beta))
    return Metric(out^, "Modified Time Comoving")


def schwarzschild(
    grid: SpacetimeGrid, center: SpacetimeCenter, radius: Length64
) raises -> Metric:
    """Return the Schwarzschild metric in Cartesian coordinates.

    The mass sits at the origin and the metric is static. With r the
    distance from the origin plus `SCHWARZSCHILD_OFFSET`:

        g_00 = -(1 - rₛ/r)
        g_ij = δ_ij + (rₛ/(r - rₛ)) xᵢ xⱼ / r²

    This is WarpFactory's `metricGet_Schwarzschild`.

    Args:
        grid: The grid. It must have one time slice.
        center: The origin, at the mass.
        radius: The Schwarzschild radius rₛ = 2 G M / c².

    Returns:
        The metric, named "Schwarzschild".

    Raises:
        Error: If the grid has more than one slice, the center is not
            finite, the radius is not positive and finite, or a point
            sits on the horizon.
    """
    require_single_slice(grid, "Schwarzschild")
    _require_center(center)
    _require_size(radius.value, "Schwarzschild radius")
    var rs = radius.value
    var out = minkowski(grid).tensor.copy()
    for point in range(grid.points()):  # pragma: no branch
        var p = _place(grid, center, point)
        var x = p[1]
        var y = p[2]
        var z = p[3]
        var r = _distance(x, y, z) + SCHWARZSCHILD_OFFSET
        var bend = 1.0 - rs / r
        var r2 = r * r
        var cross = rs / (r2 * r - r2 * rs)
        out.set(0, 0, point, -bend)
        out.set(1, 1, point, (x * x / bend + y * y + z * z) / r2)
        out.set(2, 2, point, (x * x + y * y / bend + z * z) / r2)
        out.set(3, 3, point, (x * x + y * y + z * z / bend) / r2)
        out.set_symmetric(1, 2, point, cross * x * y)
        out.set_symmetric(1, 3, point, cross * x * z)
        out.set_symmetric(2, 3, point, cross * y * z)
    return Metric(out^, "Schwarzschild")


def _require_van_den_broeck(
    inner_radius: Length64,
    inner_thickness: InverseLength64,
    outer_radius: Length64,
    outer_thickness: InverseLength64,
    expansion: Float64,
) raises:
    """Raise unless the two bubbles and the expansion are usable."""
    _require_bubble(inner_radius, inner_thickness)
    _require_bubble(outer_radius, outer_thickness)
    if not isfinite(expansion):
        raise Error("The expansion factor must be finite")


def _set_van_den_broeck(
    mut out: TensorField, point: Int, b: Float64, shift: Float64, f: Float64
):
    """Set the components that a Van Den Broeck metric changes."""
    var b2 = b * b
    for axis in range(1, 4):
        out.set(axis, axis, point, b2)
    out.set_symmetric(0, 1, point, b2 * shift)
    out.set(0, 0, point, -(1.0 - b2 * f * f))


def van_den_broeck(
    grid: SpacetimeGrid,
    center: SpacetimeCenter,
    speed: Velocity64,
    inner_radius: Length64,
    inner_thickness: InverseLength64,
    outer_radius: Length64,
    outer_thickness: InverseLength64,
    expansion: Float64,
) raises -> Metric:
    """Return the Van Den Broeck metric, with the bubble moving along x.

    A small outer bubble holds a large inner volume. Space is scaled by
    B = 1 + A f(r; R₁, σ₁), and the shift is (v/c) f(r; R₂, σ₂):

        g_00 = -(1 - B² v² f₂²),  g_01 = -B² v f₂,  g_ii = B²

    The bubble's center moves at v (1 + A)². This is WarpFactory's
    `metricGet_VanDenBroeck`.

    Args:
        grid: The grid. The time derivatives need 5 slices or more.
        center: The origin. The bubble is at the origin at time 0.
        speed: The speed v in the shift.
        inner_radius: R₁, the radius of the expanded region.
        inner_thickness: σ₁, the steepness of the expanded region.
        outer_radius: R₂, the radius of the shift bubble.
        outer_thickness: σ₂, the steepness of the shift bubble.
        expansion: A, the expansion of space inside.

    Returns:
        The metric, named "Van Den Broeck".

    Raises:
        Error: If the center, the speed or A is not finite, or a radius or
            a steepness is not positive and finite.
    """
    _require_center(center)
    _require_speed(speed)
    _require_van_den_broeck(
        inner_radius, inner_thickness, outer_radius, outer_thickness, expansion
    )
    var beta = light_fraction(speed)
    var grow = (1.0 + expansion) * (1.0 + expansion)
    var out = minkowski(grid).tensor.copy()
    for point in range(grid.points()):  # pragma: no branch
        var p = _place(grid, center, point)
        var xs = p[0] * speed.value * grow
        var r = _distance(p[1] - xs, p[2], p[3])
        var b = (
            1.0
            + alcubierre_shape(r, inner_radius.value, inner_thickness.value)
            * expansion
        )
        var f = alcubierre_shape(r, outer_radius.value, outer_thickness.value)
        _set_van_den_broeck(out, point, b, -f * beta, f * beta)
    return Metric(out^, "Van Den Broeck")


def van_den_broeck_comoving(
    grid: SpacetimeGrid,
    center: SpacetimeCenter,
    speed: Velocity64,
    inner_radius: Length64,
    inner_thickness: InverseLength64,
    outer_radius: Length64,
    outer_thickness: InverseLength64,
    expansion: Float64,
) raises -> Metric:
    """Return the Van Den Broeck metric in the frame that moves with it.

    g_01 = B² (v/c) (1 - f₂), and the other components are those of
    `van_den_broeck` at the bubble's center. This is WarpFactory's
    `metricGet_VanDenBroeckComoving`.

    Args:
        grid: The grid. It must have one time slice.
        center: The origin, at the center of the bubble.
        speed: The speed v in the shift.
        inner_radius: R₁, the radius of the expanded region.
        inner_thickness: σ₁, the steepness of the expanded region.
        outer_radius: R₂, the radius of the shift bubble.
        outer_thickness: σ₂, the steepness of the shift bubble.
        expansion: A, the expansion of space inside.

    Returns:
        The metric, named "Van Den Broeck Comoving".

    Raises:
        Error: If the grid has more than one slice, the center, the speed
            or A is not finite, or a radius or a steepness is not positive
            and finite.
    """
    require_single_slice(grid, "Van Den Broeck Comoving")
    _require_center(center)
    _require_speed(speed)
    _require_van_den_broeck(
        inner_radius, inner_thickness, outer_radius, outer_thickness, expansion
    )
    var beta = light_fraction(speed)
    var out = minkowski(grid).tensor.copy()
    for point in range(grid.points()):  # pragma: no branch
        var p = _place(grid, center, point)
        var r = _distance(p[1], p[2], p[3])
        var b = (
            1.0
            + alcubierre_shape(r, inner_radius.value, inner_thickness.value)
            * expansion
        )
        var f = alcubierre_shape(r, outer_radius.value, outer_thickness.value)
        _set_van_den_broeck(out, point, b, beta - f * beta, f * beta)
    return Metric(out^, "Van Den Broeck Comoving")
