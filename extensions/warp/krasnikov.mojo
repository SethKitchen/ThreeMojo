# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The Krasnikov tube: a passage, laid down on the way out, that shortens
the way back.

Krasnikov's two-dimensional metric is ds² = -(c dt - dx)(c dt + k dx),
from "Hyperfast travel in general relativity", Physical Review D 57
(1998) 4760. With k = 1 it is flat space. Inside the tube, k = δ - 1,
and a ship can return to its start soon after it left. Everett and Roman
made it a tube in four dimensions ("A superluminal subway: the Krasnikov
tube", Physical Review D 56 (1997) 2100):

    ds² = -(c dt - dx)(c dt + k dx) + dy² + dz²
    k = 1 - (2 - δ) θ(ρ_max - ρ) θ(c t - x) (θ(x) - θ(x + ε - D))

with ρ the distance from the x axis, D the length of the tube, ρ_max its
radius, and θ a smooth step from 0 to 1 over a wall of thickness ε.

This port uses the quintic smooth step 6u⁵ - 15u⁴ + 10u³, u = ξ / ε,
which has two continuous derivatives. The papers' own step function is
not reproduced; this port could not check their text.

Inside the tube g_xx = δ - 1 is negative, so the slices of constant time
are not spacelike there and the Eulerian frame does not exist.
`to_eulerian` refuses such a point.
"""

from std.math import isfinite

from extensions.warp.analytic import (
    AnalyticMetric,
    flat_components,
    sample_metric,
)
from extensions.warp.grid import SpacetimeCenter, SpacetimeGrid
from extensions.warp.jet import Jet
from extensions.warp.tensor import Metric
from units.si import Length64


def smooth_step(value: Float64, width: Float64) -> SIMD[DType.float64, 4]:
    """Return a smooth step from 0 to 1 and its first two derivatives.

    Args:
        value: The place ξ, in meters.
        width: The width ε of the rise, in meters.

    Returns:
        θ(ξ), θ'(ξ), θ''(ξ) and 0. θ is 0 for ξ <= 0 and 1 for ξ >= ε.
    """
    if value <= 0.0:
        return SIMD[DType.float64, 4](0.0)
    if value >= width:
        return SIMD[DType.float64, 4](1.0, 0.0, 0.0, 0.0)
    var u = value / width
    var u2 = u * u
    return SIMD[DType.float64, 4](
        u2 * u * (10.0 + u * (6.0 * u - 15.0)),
        30.0 * u2 * (1.0 - u) * (1.0 - u) / width,
        60.0 * u * (1.0 - u) * (1.0 - 2.0 * u) / (width * width),
        0.0,
    )


def _step(value: Jet, width: Float64) -> Jet:
    """Return the jet of the smooth step of a jet."""
    var s = smooth_step(value.value, width)
    return value.apply(s[0], s[1], s[2])


struct KrasnikovMetric(AnalyticMetric):
    """The Krasnikov tube of Everett and Roman, along the x axis."""

    var delta: Float64
    """δ: inside the tube, k = δ - 1."""
    var wall: Float64
    """ε, the thickness of the tube's walls and ends, in meters."""
    var length: Float64
    """D, the length of the tube, in meters."""
    var radius: Float64
    """ρ_max, the radius of the tube, in meters."""

    def __init__(
        out self,
        delta: Float64,
        wall: Length64,
        length: Length64,
        radius: Length64,
    ) raises:
        """Create the tube.

        Args:
            delta: δ, from 0 to 2, both excluded.
            wall: ε, the thickness of the walls.
            length: D, the length of the tube. It must exceed ε.
            radius: ρ_max, the radius of the tube. It must exceed ε.

        Raises:
            Error: If a value is not finite, δ is not between 0 and 2, ε
                is not positive, or D or ρ_max does not exceed ε.
        """
        if not (
            isfinite(delta)
            and isfinite(wall.value)
            and isfinite(length.value)
            and isfinite(radius.value)
        ):
            raise Error("A Krasnikov tube parameter must be finite")
        if not (delta > 0.0 and delta < 2.0):
            raise Error("A Krasnikov tube needs 0 < delta < 2")
        if not (
            wall.value > 0.0
            and length.value > wall.value
            and radius.value > wall.value
        ):
            raise Error("A Krasnikov tube needs 0 < wall < length and radius")
        self.delta = delta
        self.wall = wall.value
        self.length = length.value
        self.radius = radius.value

    def k(self, place: List[Jet]) -> Jet:
        """Return the jet of k at a place.

        Args:
            place: The jets of c t, x, y and z.

        Returns:
            The jet of k: 1 outside the tube and δ - 1 inside.
        """
        var x = place[1]
        var square = place[2].squared() + place[3].squared()
        var inner = self.radius - self.wall
        var across = Jet.constant(1.0)
        if square.value >= inner * inner:
            across = _step(
                square.sqrt().scaled(-1.0).shifted(self.radius), self.wall
            )
        var after = _step(place[0] - x, self.wall)
        var along = _step(x, self.wall) - _step(
            x.shifted(self.wall - self.length), self.wall
        )
        return (across * after * along).scaled(self.delta - 2.0).shifted(1.0)

    def components(self, place: List[Jet]) -> List[Jet]:
        """Return g_ab at a place.

        g_00 = -1, g_01 = (1 - k) / 2 and g_11 = k.

        Args:
            place: The jets of c t, x, y and z.

        Returns:
            The sixteen components.
        """
        var k = self.k(place)
        var g = flat_components()
        var cross = k.scaled(-0.5).shifted(0.5)
        g[1] = cross
        g[4] = cross
        g[5] = k
        return g^

    def name(self) -> String:
        """Return the name.

        Returns:
            "Krasnikov".
        """
        return "Krasnikov"


def krasnikov(
    grid: SpacetimeGrid,
    center: SpacetimeCenter,
    delta: Float64,
    wall: Length64,
    length: Length64,
    radius: Length64,
) raises -> Metric:
    """Return the Krasnikov tube on a grid.

    The tube runs along x from 0 to D. It forms behind a ship that leaves
    x = 0 at the speed of light at time 0.

    Args:
        grid: The grid. The time derivatives need 5 slices or more.
        center: The origin.
        delta: δ, from 0 to 2, both excluded.
        wall: ε, the thickness of the walls.
        length: D, the length of the tube.
        radius: ρ_max, the radius of the tube.

    Returns:
        The metric, named "Krasnikov".

    Raises:
        Error: If the center is not finite, or `KrasnikovMetric` refuses
            the parameters.
    """
    return sample_metric(
        KrasnikovMetric(delta, wall, length, radius), grid, center
    )
