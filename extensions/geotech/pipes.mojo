# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Buried pipes in the soil a wall retains.

A pipe barrel takes the place of soil. Its wall is heavier than the soil
and its bore is lighter, or full of water. `pipe_weights` finds, for a
horizontal band of soil, the soil a barrel removes, the pipe wall it adds
and the water it carries, per unit length of wall.

A pipe that runs `ALONG` the wall lies in the wall's cross-section, so
each length of wall holds the same length of pipe. A pipe that runs
`ACROSS` the wall passes through the section once per panel: a panel
length of wall shares the volume of a strip as wide as the band.

Soil below a water level is taken at its buoyant unit weight, and so is
the pipe wall. A full barrel's water is neutral below the water level and
is added only above it. No bedding is counted.
"""

from std.math import asin, isfinite, sqrt
from extensions.geotech.kinds import ACROSS, ALONG, PipeRun
from extensions.geotech.units import UnitWeight64
from units.si import Length64, LineLoad64


@fieldwise_init
struct BuriedPipe(ImplicitlyCopyable):
    """A group of equal pipe barrels at one height."""

    # How many barrels.
    var count: Int
    var outer_radius: Length64
    # Zero for a solid bar.
    var inner_radius: Length64
    # The height of the center above the section's base.
    var center: Length64
    var run: PipeRun
    # For a pipe `ACROSS` the wall: the length of wall that shares it.
    var panel: Length64
    # True if the barrel runs full of water.
    var full: Bool
    # The unit weight of the pipe wall material.
    var wall_unit_weight: UnitWeight64

    def check(self) raises:
        """Refuse a pipe that cannot be measured.

        Raises:
            Error: If the count is negative, a size is negative or not
                finite, the bore is larger than the barrel, the run is not
                valid, or an `ACROSS` pipe has no positive panel.
        """
        if self.count < 0:
            raise Error("A pipe count must be zero or more")
        if not self.run.is_valid():
            raise Error("A pipe run is not valid")
        var ro = self.outer_radius.value
        var ri = self.inner_radius.value
        if not (isfinite(ro) and isfinite(ri) and ro >= 0 and ri >= 0):
            raise Error("A pipe radius must be zero or more and finite")
        if ri > ro:
            raise Error("A pipe bore cannot be larger than its barrel")
        if not isfinite(self.center.value):
            raise Error("A pipe center must be finite")
        if not (
            isfinite(self.wall_unit_weight.value)
            and self.wall_unit_weight.value >= 0
        ):
            raise Error("A pipe wall unit weight must be zero or more")
        if self.run == ACROSS and not (
            isfinite(self.panel.value) and self.panel.value > 0
        ):
            raise Error("A pipe across a wall needs a positive panel length")

    def shifted(self, drop: Length64) -> BuriedPipe:
        """Return the pipe with its center lowered.

        Args:
            drop: How far to lower the center.

        Returns:
            The same pipe, measured from a base `drop` higher.
        """
        var out = self
        out.center = self.center - drop
        return out


@fieldwise_init
struct PipeWeights(ImplicitlyCopyable):
    """What pipes change in a band of soil, per unit length of wall."""

    # The weight of soil the barrels displace.
    var soil_removed: LineLoad64
    # The weight of the pipe walls.
    var wall_added: LineLoad64
    # The weight of water in full barrels, above the water level.
    var water_added: LineLoad64

    def net(self) -> LineLoad64:
        """Return the net change of weight.

        Returns:
            The pipe walls and water less the soil they displace.
        """
        return self.wall_added + self.water_added - self.soil_removed


def circle_band_area(
    radius: Float64, center: Float64, y0: Float64, y1: Float64
) -> Float64:
    """Return the area of a circle between two horizontal lines.

    Args:
        radius: The radius, in meters.
        center: The height of the center, in meters.
        y0: The lower line, in meters.
        y1: The upper line, in meters.

    Returns:
        The area in square meters; zero if the band misses the circle.
    """
    if radius <= 0 or y1 <= y0:
        return 0
    var a = max(y0, center - radius) - center
    var b = min(y1, center + radius) - center
    if b <= a + 1e-12:
        return 0
    return _band_integral(radius, b) - _band_integral(radius, a)


def _band_integral(radius: Float64, y: Float64) -> Float64:
    """Return twice the area of a circle's chord band from 0 to y.

    Args:
        radius: The radius.
        y: The height above the center, within the circle.

    Returns:
        y sqrt(r^2 - y^2) + r^2 asin(y / r).
    """
    var c = max(-radius, min(radius, y))
    return c * sqrt(max(radius * radius - c * c, 0.0)) + radius * radius * asin(
        c / radius
    )


def pipe_weights(
    pipes: List[BuriedPipe],
    bottom: Length64,
    top: Length64,
    water: Optional[Length64],
    soil: UnitWeight64,
    water_unit_weight: UnitWeight64,
    width: Length64,
) raises -> PipeWeights:
    """Return what pipes change in a horizontal band of soil.

    Args:
        pipes: The pipes, measured from the same base as the band.
        bottom: The bottom of the band.
        top: The top of the band.
        water: The water level, or None for dry soil.
        soil: The unit weight of the soil the pipes displace.
        water_unit_weight: The unit weight of water.
        width: The width of the band, which an `ACROSS` pipe shares
            with its panel.

    Returns:
        The soil removed, the pipe walls and the water, per unit length.

    Raises:
        Error: If a pipe is not valid.
    """
    var y_lo = bottom.value
    var y_hi = top.value
    var gw = water_unit_weight.value
    var gs = soil.value
    var removed = Float64(0)
    var walls = Float64(0)
    var carried = Float64(0)
    if y_hi <= y_lo:
        return PipeWeights(LineLoad64(0), LineLoad64(0), LineLoad64(0))
    for pipe in pipes:
        pipe.check()
        var ro = pipe.outer_radius.value
        if pipe.count == 0 or ro <= 0:
            continue
        var scale = Float64(pipe.count)
        if pipe.run == ACROSS:
            scale *= max(width.value, 0.0) / pipe.panel.value
        if scale <= 0:
            continue
        var ri = pipe.inner_radius.value
        var yc = pipe.center.value
        var a_ext = circle_band_area(ro, yc, y_lo, y_hi)
        var a_int = circle_band_area(ri, yc, y_lo, y_hi)
        var a_wall = max(a_ext - a_int, 0.0)
        var a_ext_sub = Float64(0)
        var a_int_sub = Float64(0)
        if water:
            var yw = min(y_hi, water.value().value)
            a_ext_sub = circle_band_area(ro, yc, y_lo, yw)
            a_int_sub = circle_band_area(ri, yc, y_lo, yw)
        var a_dry = max(a_ext - a_ext_sub, 0.0)
        var a_wall_sub = max(a_ext_sub - a_int_sub, 0.0)
        var a_wall_dry = max(a_wall - a_wall_sub, 0.0)
        var gc = pipe.wall_unit_weight.value
        removed += scale * (gs * a_dry + max(gs - gw, 0.0) * a_ext_sub)
        walls += scale * (gc * a_wall_dry + max(gc - gw, 0.0) * a_wall_sub)
        if pipe.full:
            carried += scale * gw * max(a_int - a_int_sub, 0.0)
    return PipeWeights(
        LineLoad64(removed), LineLoad64(walls), LineLoad64(carried)
    )
