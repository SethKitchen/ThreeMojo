# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The metrics that WarpFactory builds in closed form.

Each function samples one metric on a grid. A warp drive moves along x
at a constant speed. A function that ends in `_comoving` gives the metric
in the frame that moves with the drive, on a grid with one time slice.
The others move the drive across the time slices.

Each closed-form metric is also a struct, such as `AlcubierreMetric`,
that is an `AnalyticMetric`. The function samples the struct. Pass the
struct to `exact_stress_energy` for derivatives without a grid. The Lentz
soliton is a set of regions with jumps between them, so it has a grid
form only.

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

from extensions.warp.analytic import (
    AnalyticMetric,
    flat_components,
    radial,
    sample_metric,
)
from extensions.warp.grid import (
    SpacetimeCenter,
    SpacetimeGrid,
    grid_place,
    grid_time,
    require_cartesian,
    require_single_slice,
)
from extensions.warp.jet import Jet
from extensions.warp.kinds import X_AXIS, Y_AXIS, Z_AXIS
from extensions.warp.quantities import light_fraction
from extensions.warp.tensor import Metric
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


def _tanh_derivatives(u: Float64) -> SIMD[DType.float64, 8]:
    """Return tanh(u) and its first four derivatives."""
    var t = tanh(u)
    var s = 1.0 - t * t
    return SIMD[DType.float64, 8](
        t,
        s,
        -2.0 * t * s,
        (6.0 * t * t - 2.0) * s,
        8.0 * t * (2.0 - 3.0 * t * t) * s,
        0.0,
        0.0,
        0.0,
    )


def alcubierre_shape_derivatives(
    r: Float64, radius: Float64, sigma: Float64
) -> SIMD[DType.float64, 8]:
    """Return Alcubierre's shape function and its first four derivatives.

    With u₁ = σ (R + r), u₂ = σ (R - r) and T = tanh(σ R), the n-th
    derivative is σⁿ (tanh⁽ⁿ⁾(u₁) + (-1)ⁿ tanh⁽ⁿ⁾(u₂)) / (2 T).

    Args:
        r: The distance from the center of the bubble, in meters.
        radius: The radius R of the bubble, in meters.
        sigma: The steepness σ of the wall, per meter.

    Returns:
        The shape and its first four derivatives in r, then three zeros.
    """
    var outer = _tanh_derivatives(sigma * (radius + r))
    var inner = _tanh_derivatives(sigma * (radius - r))
    var scale = 1.0 / (2.0 * tanh(radius * sigma))
    var out = SIMD[DType.float64, 8](0)
    var power = 1.0
    var sign = 1.0
    for n in range(5):
        out[n] = power * (outer[n] + sign * inner[n]) * scale
        power *= sigma
        sign = -sign
    return out


def _shape_jet(square: Jet, radius: Float64, sigma: Float64) -> Jet:
    """Return the jet of Alcubierre's f(r), from the jet of r²."""
    var f = alcubierre_shape_derivatives(sqrt(square.value), radius, sigma)
    return radial(square, f[0], f[1], f[2])


def _distance_squared(x: Jet, y: Jet, z: Jet) -> Jet:
    """Return x² + y² + z²."""
    return x.squared() + y.squared() + z.squared()


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


struct MinkowskiMetric(AnalyticMetric):
    """Flat space, as a closed form."""

    def __init__(out self):
        """Create flat space."""
        pass

    def components(self, place: List[Jet]) -> List[Jet]:
        """Return diag(-1, 1, 1, 1).

        Args:
            place: The coordinate jets. Flat space does not read them.

        Returns:
            The sixteen constant components.
        """
        return flat_components()

    def name(self) -> String:
        """Return the name.

        Returns:
            "Minkowski".
        """
        return "Minkowski"


struct AlcubierreMetric(AnalyticMetric):
    """The Alcubierre metric, in the frame of the stars or of the bubble."""

    var beta: Float64
    """The speed of the bubble over c."""
    var radius: Float64
    """The radius R of the bubble, in meters."""
    var sigma: Float64
    """The steepness σ of the wall, per meter."""
    var comoving: Bool
    """Whether the frame moves with the bubble."""

    def __init__(
        out self,
        speed: Velocity64,
        radius: Length64,
        thickness: InverseLength64,
        comoving: Bool,
    ) raises:
        """Create the metric.

        Args:
            speed: The speed of the bubble. It can exceed c.
            radius: The radius R of the bubble.
            thickness: The steepness σ of the bubble wall.
            comoving: Whether to use the frame that moves with the bubble.

        Raises:
            Error: If the speed is not finite, or the radius or the
                steepness is not positive and finite.
        """
        _require_speed(speed)
        _require_bubble(radius, thickness)
        self.beta = light_fraction(speed)
        self.radius = radius.value
        self.sigma = thickness.value
        self.comoving = comoving

    def components(self, place: List[Jet]) -> List[Jet]:
        """Return g_ab at a place.

        The shift is β_x = -(v/c) f(r) about the moving center x = v t,
        or (v/c) (1 - f(r)) about the origin in the comoving frame.

        Args:
            place: The jets of c t, x, y and z.

        Returns:
            The sixteen components.
        """
        var dx = place[1]
        if not self.comoving:
            dx = dx - place[0].scaled(self.beta)
        var f = _shape_jet(
            _distance_squared(dx, place[2], place[3]), self.radius, self.sigma
        )
        var shift = f.scaled(-self.beta)
        if self.comoving:
            shift = shift.shifted(self.beta)
        var g = flat_components()
        g[0] = shift.squared().shifted(-1.0)
        g[1] = shift
        g[4] = shift
        return g^

    def name(self) -> String:
        """Return WarpFactory's name.

        Returns:
            "Alcubierre" or "Alcubierre Comoving".
        """
        if self.comoving:
            return "Alcubierre Comoving"
        return "Alcubierre"


struct ModifiedTimeMetric(AnalyticMetric):
    """An Alcubierre bubble whose lapse changes inside."""

    var bubble: AlcubierreMetric
    """The bubble that gives the shape and the shift."""
    var lapse_factor: Float64
    """A, the factor that the lapse is divided by inside."""

    def __init__(
        out self,
        speed: Velocity64,
        radius: Length64,
        thickness: InverseLength64,
        lapse_factor: Float64,
        comoving: Bool,
    ) raises:
        """Create the metric.

        Args:
            speed: The speed of the bubble.
            radius: The radius R of the bubble.
            thickness: The steepness σ of the bubble wall.
            lapse_factor: A, the factor that the lapse is divided by.
            comoving: Whether to use the frame that moves with the bubble.

        Raises:
            Error: If the speed or A is not finite, A is zero, or the
                radius or the steepness is not positive and finite.
        """
        self.bubble = AlcubierreMetric(speed, radius, thickness, comoving)
        _require_lapse_factor(lapse_factor)
        self.lapse_factor = lapse_factor

    def components(self, place: List[Jet]) -> List[Jet]:
        """Return g_ab at a place.

        The lapse is α = (1 - f) + f / A. The time component is
        g_00 = -α² + (v f / c)², in both frames, as WarpFactory has it.

        Args:
            place: The jets of c t, x, y and z.

        Returns:
            The sixteen components.
        """
        var b = self.bubble.copy()
        var dx = place[1]
        if not b.comoving:
            dx = dx - place[0].scaled(b.beta)
        var f = _shape_jet(
            _distance_squared(dx, place[2], place[3]), b.radius, b.sigma
        )
        var lapse = f.scaled(1.0 / self.lapse_factor - 1.0).shifted(1.0)
        var shift = f.scaled(-b.beta)
        var g = flat_components()
        g[0] = shift.squared() - lapse.squared()
        if b.comoving:
            shift = shift.shifted(b.beta)
        g[1] = shift
        g[4] = shift
        return g^

    def name(self) -> String:
        """Return the name.

        Returns:
            "Modified Time" or "Modified Time Comoving".
        """
        if self.bubble.comoving:
            return "Modified Time Comoving"
        return "Modified Time"


struct VanDenBroeckMetric(AnalyticMetric):
    """The Van Den Broeck metric: a small bubble with a large inside."""

    var beta: Float64
    """The speed v in the shift, over c."""
    var inner: SIMD[DType.float64, 2]
    """R₁ in meters and σ₁ per meter: the expanded region."""
    var outer: SIMD[DType.float64, 2]
    """R₂ in meters and σ₂ per meter: the shift bubble."""
    var expansion: Float64
    """A, the expansion of space inside."""
    var comoving: Bool
    """Whether the frame moves with the bubble."""

    def __init__(
        out self,
        speed: Velocity64,
        inner_radius: Length64,
        inner_thickness: InverseLength64,
        outer_radius: Length64,
        outer_thickness: InverseLength64,
        expansion: Float64,
        comoving: Bool,
    ) raises:
        """Create the metric.

        Args:
            speed: The speed v in the shift.
            inner_radius: R₁, the radius of the expanded region.
            inner_thickness: σ₁, the steepness of the expanded region.
            outer_radius: R₂, the radius of the shift bubble.
            outer_thickness: σ₂, the steepness of the shift bubble.
            expansion: A, the expansion of space inside.
            comoving: Whether to use the frame that moves with the bubble.

        Raises:
            Error: If the speed or A is not finite, or a radius or a
                steepness is not positive and finite.
        """
        _require_speed(speed)
        _require_bubble(inner_radius, inner_thickness)
        _require_bubble(outer_radius, outer_thickness)
        if not isfinite(expansion):
            raise Error("The expansion factor must be finite")
        self.beta = light_fraction(speed)
        self.inner = SIMD[DType.float64, 2](
            inner_radius.value, inner_thickness.value
        )
        self.outer = SIMD[DType.float64, 2](
            outer_radius.value, outer_thickness.value
        )
        self.expansion = expansion
        self.comoving = comoving

    def components(self, place: List[Jet]) -> List[Jet]:
        """Return g_ab at a place.

        B = 1 + A f(r; R₁, σ₁) and f₂ = (v/c) f(r; R₂, σ₂). Then
        g_00 = -(1 - B² f₂²), g_ii = B² and g_01 = -B² f₂, or
        B² (v/c - f₂) in the comoving frame. The bubble's center moves at
        v (1 + A)².

        Args:
            place: The jets of c t, x, y and z.

        Returns:
            The sixteen components.
        """
        var dx = place[1]
        if not self.comoving:
            var grow = (1.0 + self.expansion) * (1.0 + self.expansion)
            dx = dx - place[0].scaled(self.beta * grow)
        var square = _distance_squared(dx, place[2], place[3])
        var b = (
            _shape_jet(square, self.inner[0], self.inner[1])
            .scaled(self.expansion)
            .shifted(1.0)
        )
        var f = _shape_jet(square, self.outer[0], self.outer[1]).scaled(
            self.beta
        )
        var b2 = b.squared()
        var g = flat_components()
        for axis in range(1, 4):
            g[5 * axis] = b2
        var shift = -f
        if self.comoving:
            shift = shift.shifted(self.beta)
        g[1] = b2 * shift
        g[4] = g[1]
        g[0] = (b2 * f.squared()).shifted(-1.0)
        return g^

    def name(self) -> String:
        """Return WarpFactory's name.

        Returns:
            "Van Den Broeck" or "Van Den Broeck Comoving".
        """
        if self.comoving:
            return "Van Den Broeck Comoving"
        return "Van Den Broeck"


struct SchwarzschildMetric(AnalyticMetric):
    """A black hole at the origin, in Cartesian coordinates."""

    var radius: Float64
    """The Schwarzschild radius rₛ, in meters."""

    def __init__(out self, radius: Length64) raises:
        """Create the metric.

        Args:
            radius: The Schwarzschild radius rₛ = 2 G M / c².

        Raises:
            Error: If the radius is not positive and finite.
        """
        _require_size(radius.value, "Schwarzschild radius")
        self.radius = radius.value

    def components(self, place: List[Jet]) -> List[Jet]:
        """Return g_ab at a place.

        With r the distance from the origin plus `SCHWARZSCHILD_OFFSET`,
        g_00 = -(1 - rₛ/r) and g_ij = δ_ij + (rₛ/(r - rₛ)) xᵢ xⱼ / r². The
        derivatives do not exist at the origin.

        Args:
            place: The jets of c t, x, y and z.

        Returns:
            The sixteen components.
        """
        var r = (
            _distance_squared(place[1], place[2], place[3])
            .sqrt()
            .shifted(SCHWARZSCHILD_OFFSET)
        )
        var rs = Jet.constant(self.radius)
        var bend = (rs / r).scaled(-1.0).shifted(1.0)
        var r2 = r.squared()
        var cross = rs / (r2 * r - r2 * rs)
        var g = flat_components()
        g[0] = -bend
        for i in range(3):
            var others = Jet.constant(0.0)
            for j in range(3):
                if j != i:
                    others = others + place[j + 1].squared()
            g[5 * (i + 1)] = (place[i + 1].squared() / bend + others) / r2
            for j in range(i + 1, 3):
                var value = cross * place[i + 1] * place[j + 1]
                g[4 * (i + 1) + j + 1] = value
                g[4 * (j + 1) + i + 1] = value
        return g^

    def name(self) -> String:
        """Return the name.

        Returns:
            "Schwarzschild".
        """
        return "Schwarzschild"


def minkowski(grid: SpacetimeGrid) raises -> Metric:
    """Return flat space, diag(-1, 1, 1, 1) at every point.

    This is WarpFactory's `metricGet_Minkowski`.

    Args:
        grid: The grid.

    Returns:
        The metric, named "Minkowski".

    Raises:
        Error: If the grid is not Cartesian. Use
            `minkowski_curvilinear` there.
    """
    require_cartesian(grid, "minkowski")
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
    return sample_metric(
        AlcubierreMetric(speed, radius, thickness, False), grid, center
    )


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
    return sample_metric(
        AlcubierreMetric(speed, radius, thickness, True), grid, center
    )


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
        Error: If the grid is not Cartesian, the center or the speed is
            not finite, or the scale is not positive and finite.
    """
    require_cartesian(grid, "lentz")
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
        Error: If the grid has more than one slice or is not Cartesian,
            the center or the speed is not finite, or the scale is not
            positive and finite.
    """
    require_single_slice(grid, "Lentz Comoving")
    require_cartesian(grid, "lentz_comoving")
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
    return sample_metric(
        ModifiedTimeMetric(speed, radius, thickness, lapse_factor, False),
        grid,
        center,
    )


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
    return sample_metric(
        ModifiedTimeMetric(speed, radius, thickness, lapse_factor, True),
        grid,
        center,
    )


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
    return sample_metric(SchwarzschildMetric(radius), grid, center)


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
    return sample_metric(
        VanDenBroeckMetric(
            speed,
            inner_radius,
            inner_thickness,
            outer_radius,
            outer_thickness,
            expansion,
            False,
        ),
        grid,
        center,
    )


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
    return sample_metric(
        VanDenBroeckMetric(
            speed,
            inner_radius,
            inner_thickness,
            outer_radius,
            outer_thickness,
            expansion,
            True,
        ),
        grid,
        center,
    )
