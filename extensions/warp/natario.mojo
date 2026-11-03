# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A warp drive with zero expansion, of the kind Natário described.

Natário showed that a warp drive need not expand space behind it or
contract space in front of it ("Warp drive with zero expansion",
Classical and Quantum Gravity 19 (2002) 1157). The flow of space is a
divergence-free vector field X, so the Eulerian observers keep their
volume.

This port builds X as a curl, which makes its divergence zero for any
profile:

    X = curl( v f(r) (e_x × r) / 2 )
      = v (f + q (y² + z²),  -q x y,  -q x z),   q = f'(r) / (2 r)

f is Alcubierre's shape: 1 inside the bubble and 0 outside. So X = v e_x
inside and 0 outside. The line element is ds² = -c² dt² + Σ (dxⁱ - Xⁱ dt)²,
so the shift is βⁱ = -Xⁱ / c. In the comoving frame v e_x / c is added.

This construction and its components are derived here. They are not
copied from Natário's paper, whose text this port could not check. The
derivation was checked symbolically, and `tests/test_warp_natario.mojo`
checks that the divergence is zero to rounding.
"""

from std.math import sqrt

from extensions.warp.analytic import (
    AnalyticMetric,
    flat_components,
    radial,
    sample_metric,
)
from extensions.warp.grid import (
    SpacetimeCenter,
    SpacetimeGrid,
    require_single_slice,
)
from extensions.warp.jet import Jet
from extensions.warp.metrics import (
    AlcubierreMetric,
    alcubierre_shape_derivatives,
)
from extensions.warp.tensor import Metric
from units.si import InverseLength64, Length64, Velocity64


def slope_over_radius(square: Jet, derivatives: SIMD[DType.float64, 8]) -> Jet:
    """Return the jet of q = f'(r) / (2 r), given the jet of r².

    With s = r²:

        dq/ds   = (f'' r - f') / (4 r³)
        d²q/ds² = f''' / (8 r³) - 3 (f'' r - f') / (8 r⁵)

    At r = 0 an even profile gives q = f''(0) / 2 and dq/ds = f''''(0) / 12,
    and the gradient of s is zero.

    Args:
        square: The jet of r².
        derivatives: The shape f and its first four derivatives at r.

    Returns:
        The jet of q.
    """
    var s = square.value
    var f1 = derivatives[1]
    var f2 = derivatives[2]
    if s > 0.0:
        var r = sqrt(s)
        var bend = f2 * r - f1
        var dq = bend / (4.0 * r * s)
        var ddq = derivatives[3] / (8.0 * r * s) - 3.0 * bend / (
            8.0 * r * s * s
        )
        return Jet(
            f1 / (2.0 * r),
            dq * square.gradient,
            dq * square.hessian + ddq * _outer_self(square.gradient),
        )
    return Jet(
        f2 / 2.0,
        square.gradient * 0.0,
        (derivatives[4] / 12.0) * square.hessian,
    )


def _outer_self(a: SIMD[DType.float64, 4]) -> SIMD[DType.float64, 16]:
    """Return a ⊗ a."""
    var out = SIMD[DType.float64, 16](0)
    for i in range(4):
        for j in range(4):
            out[4 * i + j] = a[i] * a[j]
    return out


struct NatarioMetric(AnalyticMetric):
    """A zero-expansion warp drive, in the frame of the stars or of the bubble.
    """

    var bubble: AlcubierreMetric
    """The speed, the radius and the steepness, as for Alcubierre."""

    def __init__(
        out self,
        speed: Velocity64,
        radius: Length64,
        thickness: InverseLength64,
        comoving: Bool,
    ) raises:
        """Create the metric.

        Args:
            speed: The speed of the bubble.
            radius: The radius R of the bubble.
            thickness: The steepness σ of the bubble wall.
            comoving: Whether to use the frame that moves with the bubble.

        Raises:
            Error: If the speed is not finite, or the radius or the
                steepness is not positive and finite.
        """
        self.bubble = AlcubierreMetric(speed, radius, thickness, comoving)

    def components(self, place: List[Jet]) -> List[Jet]:
        """Return g_ab at a place.

        Args:
            place: The jets of c t, x, y and z.

        Returns:
            The sixteen components.
        """
        var b = self.bubble.copy()
        var dx = place[1]
        if not b.comoving:
            dx = dx - place[0].scaled(b.beta)
        var y = place[2]
        var z = place[3]
        var square = dx.squared() + y.squared() + z.squared()
        var d = alcubierre_shape_derivatives(
            sqrt(square.value), b.radius, b.sigma
        )
        var f = radial(square, d[0], d[1], d[2])
        var q = slope_over_radius(square, d)
        var shift_x = (f + q * (y.squared() + z.squared())).scaled(-b.beta)
        if b.comoving:
            shift_x = shift_x.shifted(b.beta)
        var shift_y = (q * dx * y).scaled(b.beta)
        var shift_z = (q * dx * z).scaled(b.beta)
        var g = flat_components()
        g[0] = (
            shift_x.squared() + shift_y.squared() + shift_z.squared()
        ).shifted(-1.0)
        g[1] = shift_x
        g[4] = shift_x
        g[2] = shift_y
        g[8] = shift_y
        g[3] = shift_z
        g[12] = shift_z
        return g^

    def name(self) -> String:
        """Return the name.

        Returns:
            "Natário" or "Natário Comoving".
        """
        if self.bubble.comoving:
            return "Natário Comoving"
        return "Natário"


def natario(
    grid: SpacetimeGrid,
    center: SpacetimeCenter,
    speed: Velocity64,
    radius: Length64,
    thickness: InverseLength64,
) raises -> Metric:
    """Return the zero-expansion warp drive, with the bubble moving along x.

    Args:
        grid: The grid. The time derivatives need 5 slices or more.
        center: The origin. The bubble is at the origin at time 0.
        speed: The speed of the bubble.
        radius: The radius R of the bubble.
        thickness: The steepness σ of the bubble wall.

    Returns:
        The metric, named "Natário".

    Raises:
        Error: If the center or the speed is not finite, or the radius or
            the steepness is not positive and finite.
    """
    return sample_metric(
        NatarioMetric(speed, radius, thickness, False), grid, center
    )


def natario_comoving(
    grid: SpacetimeGrid,
    center: SpacetimeCenter,
    speed: Velocity64,
    radius: Length64,
    thickness: InverseLength64,
) raises -> Metric:
    """Return the zero-expansion warp drive in the frame of the bubble.

    Args:
        grid: The grid. It must have one time slice.
        center: The origin, at the center of the bubble.
        speed: The speed of the bubble.
        radius: The radius R of the bubble.
        thickness: The steepness σ of the bubble wall.

    Returns:
        The metric, named "Natário Comoving".

    Raises:
        Error: If the grid has more than one slice, the center or the
            speed is not finite, or the radius or the steepness is not
            positive and finite.
    """
    require_single_slice(grid, "Natário Comoving")
    return sample_metric(
        NatarioMetric(speed, radius, thickness, True), grid, center
    )
