# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Totals over a slice of constant time: how many joules a metric needs.

WarpFactory gives each value point by point. `energy_totals` adds up the
energy density that the Eulerian observer measures over one time slice:

    E = Σ T̂⁰⁰ √γ Δx¹ Δx² Δx³

with γ the determinant of the spatial metric, so √γ Δx¹ Δx² Δx³ is the
proper volume of a cell. It gives the total, its positive part and its
negative part. `violation_total` adds up the negative part of an energy
condition map the same way.

The sum is the midpoint rule, one cell for each point. The finite
differences copy the nearest derivative in the two outer layers of
points, so pass `margin` = 2 to leave those layers out. A result from
`exact_stress_energy` has no such layers.
"""

from extensions.warp.conditions import ConditionMap
from extensions.warp.frame import to_eulerian
from extensions.warp.grid import SpacetimeGrid
from extensions.warp.kinds import Axis, T_AXIS
from extensions.warp.solver import StressEnergy
from extensions.warp.tensor import Metric
from units.si import Energy64, Volume64

from std.math import sqrt


struct EnergyTotals(ImplicitlyCopyable, Movable):
    """The energy over one slice, with its two parts."""

    var total: Energy64
    """The sum of the energy density times the proper volume."""
    var positive: Energy64
    """The sum over the points where the energy density is positive."""
    var negative: Energy64
    """The sum over the points where it is negative. It is not positive."""
    var volume: Volume64
    """The proper volume that was summed."""

    def __init__(
        out self,
        total: Energy64,
        positive: Energy64,
        negative: Energy64,
        volume: Volume64,
    ):
        """Hold the totals.

        Args:
            total: The whole sum.
            positive: The positive part.
            negative: The negative part.
            volume: The proper volume.
        """
        self.total = total
        self.positive = positive
        self.negative = negative
        self.volume = volume


def _require_slice(grid: SpacetimeGrid, slice: Int, margin: Int) raises:
    """Raise unless a slice and a margin fit the grid."""
    if slice < 0 or slice >= grid.count(T_AXIS):
        raise Error("A time slice is outside the grid")
    if margin < 0:
        raise Error("A margin must not be negative")
    for axis in range(1, 4):
        if 2 * margin >= grid.count(Axis(axis)):
            raise Error("A margin leaves no points to sum")


def _cell_volume(grid: SpacetimeGrid) -> Float64:
    """Return the product of the three space steps."""
    var product = 1.0
    for axis in range(1, 4):
        product *= grid.coordinate_step(Axis(axis))
    return product


def _proper(metric: Metric, point: Int) raises -> Float64:
    """Return √γ at one point."""
    var g = metric.at(point)
    var det = (
        g[5] * (g[10] * g[15] - g[11] * g[14])
        - g[6] * (g[9] * g[15] - g[11] * g[13])
        + g[7] * (g[9] * g[14] - g[10] * g[13])
    )
    if not det > 0.0:
        raise Error("A spatial metric has no positive volume at a point")
    return sqrt(det)


def _inner_points(grid: SpacetimeGrid, slice: Int, margin: Int) -> List[Int]:
    """Return the flat indexes of a slice, without `margin` layers."""
    var out = List[Int]()
    for x in range(margin, grid.count(Axis(1)) - margin):  # pragma: no branch
        for y in range(
            margin, grid.count(Axis(2)) - margin
        ):  # pragma: no branch
            for z in range(
                margin, grid.count(Axis(3)) - margin
            ):  # pragma: no branch
                out.append(grid.index(slice, x, y, z))
    return out^


def energy_totals(
    energy: StressEnergy, metric: Metric, slice: Int = 0, margin: Int = 0
) raises -> EnergyTotals:
    """Return the energy that the Eulerian observers measure over a slice.

    Args:
        energy: The stress-energy tensor, in any frame and index position.
        metric: The metric. It must have the same grid.
        slice: The time slice, from 0.
        margin: The layers of points to leave out at each edge.

    Returns:
        The total, its positive and negative parts, and the volume.

    Raises:
        Error: If the slice or the margin does not fit the grid, the grids
            differ, the metric has no Eulerian frame at a point, or its
            spatial metric is not positive definite.
    """
    var grid = metric.grid()
    _require_slice(grid, slice, margin)
    var eulerian = to_eulerian(energy, metric)
    var cell = _cell_volume(grid)
    var positive = 0.0
    var negative = 0.0
    var volume = 0.0
    for point in _inner_points(grid, slice, margin):  # pragma: no branch
        var dv = _proper(metric, point) * cell
        var e = eulerian.tensor.get(0, 0, point) * dv
        if e < 0.0:
            negative += e
        else:
            positive += e
        volume += dv
    return EnergyTotals(
        Energy64(positive + negative),
        Energy64(positive),
        Energy64(negative),
        Volume64(volume),
    )


def violation_total(
    map: ConditionMap, metric: Metric, slice: Int = 0, margin: Int = 0
) raises -> Energy64:
    """Return the negative part of an energy condition, summed over a slice.

    Each value of the map is an energy density, so its negative part
    times the proper volume is an energy.

    Args:
        map: The condition map, one value for each point of the grid.
        metric: The metric of the map's grid.
        slice: The time slice, from 0.
        margin: The layers of points to leave out at each edge.

    Returns:
        The sum. It is zero when the condition holds everywhere.

    Raises:
        Error: If the map has the wrong length, the slice or the margin
            does not fit the grid, or the spatial metric is not positive
            definite at a point.
    """
    var grid = metric.grid()
    if len(map.values) != grid.points():
        raise Error("A map must have one value for each grid point")
    _require_slice(grid, slice, margin)
    var cell = _cell_volume(grid)
    var out = 0.0
    for point in _inner_points(grid, slice, margin):  # pragma: no branch
        out += min(map.values[point], 0.0) * _proper(metric, point) * cell
    return Energy64(out)
