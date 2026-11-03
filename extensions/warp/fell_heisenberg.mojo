# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A warp soliton of positive Eulerian energy, after Fell and Heisenberg.

Fell and Heisenberg, "Positive energy warp drive from hidden geometric
structures", Classical and Quantum Gravity 38 (2021) 155020
(arXiv 2104.06488). Their spacetime has lapse 1, a flat spatial metric and
a shift that is the gradient of a potential φ:

    ds² = -c² dt² + Σ (dxⁱ + Nⁱ c dt)²,    N = ∇φ

Then the momentum density is zero, and the Eulerian energy density comes
from the Hessian H of φ alone (their equation 10):

    8π G ρ / c⁴ = h₁ + h₂ + h₃

h₁, h₂ and h₃ are the three 2 × 2 principal minors of H. A potential whose
two-dimensional slices curve the same way everywhere has positive energy.

Their smooth potential (equation 13) has a Gaussian width σ, a radius r, a
strength V, a power Π and two functions m and n. In coordinates x̂ = x / L,
with u = |x̂|^(2Π), A = r - u/m and B = r + u/n, its derivative along u is

    ∂φ/∂u = V √(σπ) (m erf(B/√σ) - n erf(A/√σ)) / (m + n)

when m and n do not depend on u. This needs the last product of their
equation 13 to read m (n r + u). As printed, m (n r - u), the Gaussian
terms of ∂φ/∂u do not cancel, and the shift does not vanish inside and
fall off outside as the paper says it does.

The paper does not give its m and n. It asks that φ go to zero at the
center, which holds when 2 m n = m + n. This port writes m = 1 / (1 - τ)
and n = 1 / (1 + τ). Then m n / (m + n) = 1/2, and the potential is

    φ = (V/2) (G(r - u (1 - τ)) + G(r + u (1 + τ)) - 2 G(r))
    G(a) = σ exp(-a²/σ) + √(σπ) a erf(a/√σ)

with G' = √(σπ) erf(a/√σ) and G'' = 2 exp(-a²/σ). With τ = 0 the soliton is
spherical: the shift is zero inside r and radial outside, and G'' > 0 makes
the energy density positive everywhere. The paper tilts m above n in +z
and below it in -z. This port takes τ = tanh(k ẑ / u), so φ is close to
V √(σπ) erf(r/√σ) k ẑ near the center: a level shift along z of that size,
superluminal when it passes 1. The tilt k tunes it.

φ is not differentiable at the center itself. The components there are
those of a point a billionth of L along +z.
"""

from std.math import erf, exp, isfinite, pi, sqrt

from extensions.warp.analytic import (
    AnalyticMetric,
    flat_components,
    sample_metric,
)
from extensions.warp.grid import SpacetimeCenter, SpacetimeGrid
from extensions.warp.jet import Jet
from extensions.warp.quantities import EnergyDensity64, einstein_coupling
from extensions.warp.tensor import Metric
from units.si import Length64

comptime _NUDGE = 1e-9
"""How far along +z, in units of L, the center is taken from."""


def _require(value: Float64, positive: Bool, name: String) raises:
    """Refuse a parameter that is not finite, or not positive when it must be.
    """
    if not isfinite(value) or (positive and value <= 0.0):
        if positive:
            raise Error(name + " must be positive and finite")
        raise Error(name + " must be finite")


@fieldwise_init
struct FellHeisenbergSoliton(AnalyticMetric):
    """The positive-energy soliton, in the frame where it is static."""

    var power: Float64
    """The power Π of u = |x̂|^(2Π). The paper uses 1/4."""
    var radius: Float64
    """The radius r, in units of u. The paper uses 6."""
    var strength: Float64
    """The strength V. The paper uses 10."""
    var width: Float64
    """The Gaussian width σ. The paper uses 1."""
    var tilt: Float64
    """The tilt k of τ = tanh(k ẑ / u). 0 makes the soliton spherical."""
    var scale: Length64
    """The length L of one unit of x̂."""

    def check(self) raises:
        """Refuse parameters that make no soliton.

        Raises:
            Error: If the power, the radius, the width or the scale is not
                positive and finite, or the strength or the tilt is not
                finite.
        """
        _require(self.power, True, "The power")
        _require(self.radius, True, "The radius")
        _require(self.width, True, "The width")
        _require(self.scale.value, True, "The scale")
        _require(self.strength, False, "The strength")
        _require(self.tilt, False, "The tilt")

    def central_shift(self) -> Float64:
        """Return the level shift near the center, as a fraction of c.

        Returns:
            V √(σπ) erf(r/√σ) k. Above 1 the center moves faster than
            light.
        """
        return (
            self.strength
            * sqrt(self.width * pi)
            * erf(self.radius / sqrt(self.width))
            * self.tilt
        )

    def _scaled(self, place: List[Jet]) -> List[Jet]:
        """Return the jets of x̂, ŷ and ẑ, moved off the center if on it."""
        var unit = 1.0 / self.scale.value
        var x = place[1].scaled(unit)
        var y = place[2].scaled(unit)
        var z = place[3].scaled(unit)
        if x.value * x.value + y.value * y.value + z.value * z.value < (
            _NUDGE * _NUDGE
        ):
            z = z.shifted(_NUDGE)
        return [x^, y^, z^]

    def _g(self, a: Jet) -> Jet:
        """Return the jet of G(a)."""
        var s = self.width
        var v = a.value
        var e = exp(-v * v / s)
        var slope = sqrt(s * pi) * erf(v / sqrt(s))
        return a.apply(
            s * e + sqrt(s * pi) * v * erf(v / sqrt(s)), slope, 2 * e
        )

    def _slope(self, a: Jet) -> Jet:
        """Return the jet of G'(a)."""
        var s = self.width
        var v = a.value
        var e = exp(-v * v / s)
        return a.apply(sqrt(s * pi) * erf(v / sqrt(s)), 2 * e, -4 * v * e / s)

    def _fields(self, coordinates: List[Jet]) -> List[Jet]:
        """Return the jets of u and τ, then of ∂ᵢu and of ∂ᵢτ for x, y, z."""
        var x = coordinates[0]
        var y = coordinates[1]
        var z = coordinates[2]
        var square = x.squared() + y.squared() + z.squared()
        var p = self.power
        var s = square.value
        var u_value = s**p
        var u = square.apply(
            u_value, p * u_value / s, p * (p - 1.0) * u_value / (s * s)
        )
        # ∂ᵢu = 2Π s^(Π - 1) xᵢ.
        var lower = square.apply(
            2.0 * p * u_value / s,
            2.0 * p * (p - 1.0) * u_value / (s * s),
            2.0 * p * (p - 1.0) * (p - 2.0) * u_value / (s * s * s),
        )
        var du_x = lower * x
        var du_y = lower * y
        var du_z = lower * z
        var over_u = u.reciprocal()
        var tau = (z * over_u).scaled(self.tilt).tanh()
        var bend = Jet.constant(1.0) - tau.squared()
        # ∂ᵢτ = (1 - τ²) k (δᵢz / u - ẑ ∂ᵢu / u²).
        var z_over_u2 = z * over_u * over_u
        var dt_x = (bend * z_over_u2 * du_x).scaled(-self.tilt)
        var dt_y = (bend * z_over_u2 * du_y).scaled(-self.tilt)
        var dt_z = (bend * (over_u - z_over_u2 * du_z)).scaled(self.tilt)
        return [u^, tau^, du_x^, du_y^, du_z^, dt_x^, dt_y^, dt_z^]

    def potential(self, place: List[Jet]) -> Jet:
        """Return the jet of φ̂, the potential in units of L.

        Args:
            place: The jets of c t, x, y and z, in meters.

        Returns:
            φ̂ of x̂. The physical potential is L φ̂, so the shift is
            L ∇φ̂.
        """
        var f = self._fields(self._scaled(place))
        var u = f[0]
        var tau = f[1]
        var r = self.radius
        var a = (u * (Jet.constant(1.0) - tau)).scaled(-1.0).shifted(r)
        var b = (u * (Jet.constant(1.0) + tau)).shifted(r)
        var middle = self._g(Jet.constant(r)).value
        return (
            (self._g(a) + self._g(b))
            .shifted(-2.0 * middle)
            .scaled(0.5 * self.strength)
        )

    def shift(self, place: List[Jet]) -> List[Jet]:
        """Return the jets of the shift Nⁱ = ∂ᵢφ, a fraction of c.

        Args:
            place: The jets of c t, x, y and z, in meters.

        Returns:
            Nˣ, Nʸ and Nᶻ.
        """
        var f = self._fields(self._scaled(place))
        var u = f[0]
        var tau = f[1]
        var r = self.radius
        var minus = Jet.constant(1.0) - tau
        var plus = Jet.constant(1.0) + tau
        var a = (u * minus).scaled(-1.0).shifted(r)
        var b = (u * plus).shifted(r)
        var slope_a = self._slope(a)
        var slope_b = self._slope(b)
        var out = List[Jet]()
        for i in range(3):
            # ∂ᵢA = -(1 - τ) ∂ᵢu + u ∂ᵢτ and ∂ᵢB = (1 + τ) ∂ᵢu + u ∂ᵢτ.
            var du = f[2 + i]
            var u_dt = u * f[5 + i]
            var d_a = u_dt - minus * du
            var d_b = u_dt + plus * du
            out.append(
                (slope_a * d_a + slope_b * d_b).scaled(0.5 * self.strength)
            )
        return out^

    def energy_density(self, place: List[Jet]) -> EnergyDensity64:
        """Return the Eulerian energy density, from the Hessian of φ.

        Args:
            place: The jets of c t, x, y and z, in meters.

        Returns:
            ρ = (h₁ + h₂ + h₃) c⁴ / (8π G), in joules per cubic meter.
        """
        var phi = self.potential(place)
        var length = self.scale.value
        var xx = length * phi.second(1, 1)
        var yy = length * phi.second(2, 2)
        var zz = length * phi.second(3, 3)
        var xy = length * phi.second(1, 2)
        var xz = length * phi.second(1, 3)
        var yz = length * phi.second(2, 3)
        var minors = (
            (yy * zz - yz * yz) + (xx * zz - xz * xz) + (xx * yy - xy * xy)
        )
        return EnergyDensity64(minors * einstein_coupling())

    def components(self, place: List[Jet]) -> List[Jet]:
        """Return g_ab at a place.

        Args:
            place: The jets of c t, x, y and z.

        Returns:
            The sixteen components: g_00 = -1 + N·N, g_0i = Nⁱ, g_ij = δᵢⱼ.
        """
        var n = self.shift(place)
        var g = flat_components()
        g[0] = (n[0].squared() + n[1].squared() + n[2].squared()).shifted(-1.0)
        for i in range(3):
            g[1 + i] = n[i]
            g[4 * (1 + i)] = n[i]
        return g^

    def name(self) -> String:
        """Return the name.

        Returns:
            "Fell-Heisenberg".
        """
        return "Fell-Heisenberg"


def fell_heisenberg(
    grid: SpacetimeGrid,
    center: SpacetimeCenter,
    soliton: FellHeisenbergSoliton,
) raises -> Metric:
    """Return the soliton on a grid. It is static, so any time slices serve.

    Args:
        grid: The grid.
        center: The origin, at the center of the soliton.
        soliton: The parameters.

    Returns:
        The metric, named "Fell-Heisenberg".

    Raises:
        Error: If a parameter is out of range, the grid is not Cartesian,
            or the center is not finite.
    """
    soliton.check()
    return sample_metric(soliton, grid, center)
