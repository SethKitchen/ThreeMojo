# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Bounded midpoint cells that partition an exact rectangular region.

The final cell on each axis is clipped to the requested endplane.
No cell extends into an adjacent segment. Sampling a field at the cell
center still approximates its curved boundary. The cells do not provide
an error bound for that approximation.
"""

from math.vector3 import Vector3
from std.math import ceil, isfinite, min
from units.si import Length

comptime MAX_SAMPLE_CELLS = 2_000_000


struct SampleGrid(ImplicitlyCopyable):
    """A finite grid clipped to a box, with at most two million cells.

    Coordinates and the returned cell widths are in meters.
    """

    var low: Vector3
    var high: Vector3
    var step: Length
    var nx: Int
    var ny: Int
    var nz: Int

    def __init__(out self, low: Vector3, high: Vector3, step: Length) raises:
        """Check the complete work request before constructing cell counts.

        Args:
            low: Minimum box corner, in meters.
            high: Maximum box corner, in meters.
            step: Positive finite maximum cell width.

        Raises:
            Error: If a bound is not finite, a span is not positive,
                the step is not finite and positive, or the work exceeds
                `MAX_SAMPLE_CELLS`.
        """
        if not isfinite(step.value) or step.value <= 0:
            raise Error("A sample step must be finite and positive")
        var counts = SIMD[DType.float64, 4](1)
        for axis in range(3):  # pragma: no branch
            var lo = Float64(low.get_component(axis))
            var hi = Float64(high.get_component(axis))
            if not isfinite(lo) or not isfinite(hi) or hi <= lo:
                raise Error("A sample box must be finite and strictly ordered")
            counts[axis] = ceil((hi - lo) / Float64(step.value))
        # Finite Float32 bounds and a positive Float32 step cannot overflow
        # the Float64 product. Refuse it before any conversion to Int.
        var work = counts[0] * counts[1] * counts[2]
        if work > Float64(MAX_SAMPLE_CELLS):
            raise Error("A sample grid exceeds the two-million-cell work limit")
        self.low = low
        self.high = high
        self.step = step
        self.nx = Int(counts[0])
        self.ny = Int(counts[1])
        self.nz = Int(counts[2])

    def cell(self, ix: Int, iy: Int, iz: Int) raises -> Tuple[Vector3, Vector3]:
        """Return the center and widths of one clipped cell, in meters.

        Args:
            ix: Cell index along x, below `nx`.
            iy: Cell index along y, below `ny`.
            iz: Cell index along z, below `nz`.

        Returns:
            The center and the positive cell widths.

        Raises:
            Error: If a cell index is outside the grid.
        """
        if ix < 0 or ix >= self.nx:
            raise Error("A sample x index must be inside the grid")
        if iy < 0 or iy >= self.ny:
            raise Error("A sample y index must be inside the grid")
        if iz < 0 or iz >= self.nz:
            raise Error("A sample z index must be inside the grid")
        return self._cell(ix, iy, iz)

    def _cell(self, ix: Int, iy: Int, iz: Int) -> Tuple[Vector3, Vector3]:
        """Return a cell for loop indices already bounded by the grid."""
        var s = Float64(self.step.value)
        var x0 = Float64(self.low.x) + Float64(ix) * s
        var y0 = Float64(self.low.y) + Float64(iy) * s
        var z0 = Float64(self.low.z) + Float64(iz) * s
        var x1 = min(x0 + s, Float64(self.high.x))
        var y1 = min(y0 + s, Float64(self.high.y))
        var z1 = min(z0 + s, Float64(self.high.z))
        return (
            Vector3(
                Float32((x0 + x1) * 0.5),
                Float32((y0 + y1) * 0.5),
                Float32((z0 + z1) * 0.5),
            ),
            Vector3(Float32(x1 - x0), Float32(y1 - y0), Float32(z1 - z0)),
        )
