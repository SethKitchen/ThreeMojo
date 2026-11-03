# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Flow lines of the momentum density of a stress-energy tensor.

`momentum_flow_lines` is WarpFactory's `getMomentumFlowLines`. Each line
starts at a place on the grid and moves, one step at a time, along the
momentum density T^0i at that place. The density between grid points is
found by trilinear interpolation. A line stops when it comes within one
point of the edge of the grid.

Places are in grid indexes: x = 2.5 is halfway between the points with
x indexes 2 and 3.

## Differences from WarpFactory

- Indexes count from 0, not from 1.
- WarpFactory adds 1e-8 to each place before it interpolates, so that a
  place on a grid point does not divide by zero. This port interpolates
  without the shift.
- A line holds every place it reaches inside the grid, up to `max_steps`
  places. WarpFactory drops the last place of a line that does not leave
  the grid.
"""

from std.math import ceil, floor, isfinite

from extensions.warp.grid import require_cartesian
from extensions.warp.kinds import CONTRAVARIANT
from extensions.warp.quantities import Compliance64
from extensions.warp.solver import StressEnergy
from extensions.warp.tensor import TensorField


@fieldwise_init
struct GridPoint(Equatable, ImplicitlyCopyable, Writable):
    """A place on a grid with one time slice, in grid indexes."""

    var x: Float64
    """The place along x, in steps from point 0."""
    var y: Float64
    """The place along y, in steps from point 0."""
    var z: Float64
    """The place along z, in steps from point 0."""


def _inside(value: Float64, count: Int) -> Bool:
    """Return True if a place is more than one point from both edges."""
    return floor(value) > 0.0 and ceil(value) < Float64(count - 1)


def trilinear(tensor: TensorField, a: Int, b: Int, place: GridPoint) -> Float64:
    """Return one component of a tensor between grid points.

    The place and the next point along each axis must be on the grid,
    and the grid must have one time slice.

    Args:
        tensor: The tensor.
        a: The first index of the component.
        b: The second index of the component.
        place: The place, in grid indexes.

    Returns:
        The trilinear interpolation of the eight nearest points.
    """
    var grid = tensor.grid
    var x0 = Int(floor(place.x))
    var y0 = Int(floor(place.y))
    var z0 = Int(floor(place.z))
    var fx = place.x - Float64(x0)
    var fy = place.y - Float64(y0)
    var fz = place.z - Float64(z0)
    var total = 0.0
    for corner in range(8):
        var dx = corner // 4
        var dy = (corner // 2) % 2
        var dz = corner % 2
        # The weight of the far corner along an axis is the fraction, and
        # that of the near corner is one minus it.
        var weight = (
            (1.0 - fx + Float64(dx) * (2.0 * fx - 1.0))
            * (1.0 - fy + Float64(dy) * (2.0 * fy - 1.0))
            * (1.0 - fz + Float64(dz) * (2.0 * fz - 1.0))
        )
        total += weight * tensor.get(
            a, b, grid.index(0, x0 + dx, y0 + dy, z0 + dz)
        )
    return total


def momentum_flow_lines(
    energy: StressEnergy,
    starts: List[GridPoint],
    step: Compliance64,
    max_steps: Int,
) raises -> List[List[GridPoint]]:
    """Return the flow line of the momentum density from each start.

    Each step moves a line by T^0i times `step`, in grid indexes. This is
    WarpFactory's `stepSize` times its `scaleFactor`.

    Args:
        energy: The stress-energy tensor. It must be contravariant, and
            its grid must have one time slice.
        starts: The first place of each line, in grid indexes.
        step: How many grid steps a line moves for each joule per cubic
            meter of momentum density.
        max_steps: The most places a line can hold. 1 or more.

    Returns:
        One line for each start. A line that starts outside the grid is
        empty.

    Raises:
        Error: If the tensor is not contravariant, the grid is not
            Cartesian or has more than one time slice, the step is not finite, or `max_steps` is less
            than 1.
    """
    if energy.tensor.index != CONTRAVARIANT:
        raise Error("Momentum flow lines need a contravariant tensor")
    var grid = energy.tensor.grid
    require_cartesian(grid, "Momentum flow lines")
    if grid.counts[0] != 1:
        raise Error("Momentum flow lines need one time slice")
    if not isfinite(step.value):
        raise Error("A flow line step must be finite")
    if max_steps < 1:
        raise Error("A flow line needs at least one step")
    var nx = Int(grid.counts[1])
    var ny = Int(grid.counts[2])
    var nz = Int(grid.counts[3])
    var out = List[List[GridPoint]](capacity=len(starts))
    for start in starts:
        var line = List[GridPoint]()
        var place = start
        while len(line) < max_steps:
            if not (
                _inside(place.x, nx)
                and _inside(place.y, ny)
                and _inside(place.z, nz)
            ):
                break
            line.append(place)
            var px = trilinear(energy.tensor, 0, 1, place)
            var py = trilinear(energy.tensor, 0, 2, place)
            var pz = trilinear(energy.tensor, 0, 3, place)
            place = GridPoint(
                place.x + px * step.value,
                place.y + py * step.value,
                place.z + pz * step.value,
            )
        out.append(line^)
    return out^
