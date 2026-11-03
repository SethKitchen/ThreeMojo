# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The expansion, shear and vorticity of the Eulerian observers.

`metric_scalars` is WarpFactory's `getScalars`. The Eulerian observers
move with the 4-velocity uᵃ = (1, -βⁱ) / α. With the projection
hᵃ_b = δᵃ_b + uᵃ u_b and P_ab = g_ab + u_a u_b:

    θ_ab = hᶜ_a hᵈ_b ∇₍c u_d₎,   θ = g^ab θ_ab
    ω_ab = hᶜ_a hᵈ_b ∇[c u_d],   ω² = ω^ab ω_ab / 2
    σ_ab = θ_ab - θ P_ab / 3,    σ² = σ^ab σ_ab / 2

θ is the expansion, σ² the shear and ω² the vorticity. The covariant
derivative uses fourth-order differences and the Christoffel symbols of
the metric.

## Differences from WarpFactory

WarpFactory takes these derivatives with a step of 1 on every axis,
whatever the grid, and does not divide the time derivative by c. This
port uses the steps of the grid, with x⁰ = c t. On a grid whose space
steps are 1 m and whose time step is 1/c, the two agree.
"""

from extensions.warp.derivatives import Stencil
from extensions.warp.kinds import FOURTH_ORDER
from extensions.warp.tensor import Matrix4, Metric, Vector4, inverse4
from extensions.warp.three_plus_one import decompose
from units.si import InverseArea64, InverseLength64


struct MetricScalars(Copyable, Movable):
    """The expansion, shear and vorticity scalars at each point."""

    var expansion: List[Float64]
    """θ at each point, per meter."""
    var shear: List[Float64]
    """σ² at each point, per square meter."""
    var vorticity: List[Float64]
    """ω² at each point, per square meter."""

    def __init__(
        out self,
        var expansion: List[Float64],
        var shear: List[Float64],
        var vorticity: List[Float64],
    ):
        """Hold the three scalars.

        Args:
            expansion: θ at each point.
            shear: σ² at each point.
            vorticity: ω² at each point.
        """
        self.expansion = expansion^
        self.shear = shear^
        self.vorticity = vorticity^

    def expansion_at(self, point: Int) -> InverseLength64:
        """Return the expansion at one point.

        Args:
            point: The flat index of the point.

        Returns:
            θ. A positive value means the observers move apart.
        """
        return InverseLength64(self.expansion[point])

    def shear_at(self, point: Int) -> InverseArea64:
        """Return the shear scalar at one point.

        Args:
            point: The flat index of the point.

        Returns:
            σ².
        """
        return InverseArea64(self.shear[point])

    def vorticity_at(self, point: Int) -> InverseArea64:
        """Return the vorticity scalar at one point.

        Args:
            point: The flat index of the point.

        Returns:
            ω².
        """
        return InverseArea64(self.vorticity[point])


def _raise_both(t: Matrix4, gu: Matrix4) -> Matrix4:
    """Return t^ab = g^ac t_cd g^db."""
    var out = Matrix4(0)
    for a in range(4):
        for b in range(4):
            var total = 0.0
            for c in range(4):
                for d in range(4):
                    total += gu[4 * a + c] * t[4 * c + d] * gu[4 * d + b]
            out[4 * a + b] = total
    return out


def metric_scalars(metric: Metric) raises -> MetricScalars:
    """Return the expansion, shear and vorticity of the Eulerian observers.

    This is WarpFactory's `getScalars`, with the grid's steps.

    Args:
        metric: The metric.

    Returns:
        The three scalars at each point.

    Raises:
        Error: If the metric is singular at a point or has no real lapse
            at a point.
    """
    var grid = metric.grid()
    var n = grid.points()
    var split = decompose(metric)
    # u_a at every point, component a at a times n, for the derivatives.
    var u_down = List[Float64](length=4 * n, fill=0.0)
    var u_up = List[Vector4](capacity=n)
    for point in range(n):  # pragma: no branch
        var alpha = split.parts.lapse[point]
        var up = (
            Vector4(
                1.0,
                -split.shift_up[point],
                -split.shift_up[n + point],
                -split.shift_up[2 * n + point],
            )
            / alpha
        )
        u_up.append(up)
        var g = metric.at(point)
        for a in range(4):
            var total = 0.0
            for b in range(4):
                total += g[4 * a + b] * up[b]
            u_down[a * n + point] = total
    var stencil = Stencil(grid, FOURTH_ORDER)
    var expansion = List[Float64](capacity=n)
    var shear = List[Float64](capacity=n)
    var vorticity = List[Float64](capacity=n)
    var d1 = List[Float64](length=64, fill=0.0)
    for point in range(n):  # pragma: no branch
        var at = grid.position(point)
        var g = metric.at(point)
        var gu = inverse4(g)
        for i in range(4):
            for j in range(4):
                var base = (4 * i + j) * n
                for k in range(4):
                    d1[(4 * i + j) * 4 + k] = stencil.first(
                        metric.tensor.data, base, point, at, k
                    )
        var u = Vector4(0)
        for a in range(4):
            u[a] = u_down[a * n + point]
        # ∇_i u_j = ∂_i u_j - Γᵏ_ji u_k, with
        # Γᵏ_ji = g^km (∂_i g_mj + ∂_j g_mi - ∂_m g_ji) / 2.
        var del_u = Matrix4(0)
        for i in range(4):
            for j in range(4):
                var value = stencil.first(u_down, j * n, point, at, i)
                for k in range(4):
                    var gamma = 0.0
                    for m in range(4):
                        gamma += (
                            0.5
                            * gu[4 * k + m]
                            * (
                                d1[(4 * m + j) * 4 + i]
                                + d1[(4 * m + i) * 4 + j]
                                - d1[(4 * j + i) * 4 + m]
                            )
                        )
                    value -= gamma * u[k]
                del_u[4 * i + j] = value
        var up = u_up[point]
        var h = Matrix4(0)
        var p = Matrix4(0)
        for i in range(4):
            for j in range(4):
                var delta = 0.0
                if i == j:
                    delta = 1.0
                h[4 * i + j] = delta + up[i] * u[j]
                p[4 * i + j] = g[4 * i + j] + u[i] * u[j]
        var theta = Matrix4(0)
        var omega = Matrix4(0)
        for i in range(4):
            for j in range(4):
                var sym = 0.0
                var anti = 0.0
                for a in range(4):
                    for b in range(4):
                        var weight = 0.5 * h[4 * a + i] * h[4 * b + j]
                        sym += weight * (del_u[4 * a + b] + del_u[4 * b + a])
                        anti += weight * (del_u[4 * a + b] - del_u[4 * b + a])
                theta[4 * i + j] = sym
                omega[4 * i + j] = anti
        var trace = (gu * theta).reduce_add()
        var sigma = theta - (trace / 3.0) * p
        expansion.append(trace)
        shear.append(0.5 * (sigma * _raise_both(sigma, gu)).reduce_add())
        vorticity.append(0.5 * (omega * _raise_both(omega, gu)).reduce_add())
    return MetricScalars(expansion^, shear^, vorticity^)
