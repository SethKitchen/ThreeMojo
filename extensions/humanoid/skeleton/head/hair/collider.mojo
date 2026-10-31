# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A distance field baked into a grid, for hair to collide with.

A body's own field is far too slow to read for every point of every
strand, every step: it is sampled once over a box, and read back
between the samples. Frostbitten Hair WebGPU bakes its head the same
way. See `HairBody` and `HairSimulation`.

This is not a three.js port. See Extensions.

    var collider = HairCollider(skin, skin.low, skin.high)
    var d = collider.distance(point)
"""

from extensions.humanoid.skeleton.field import DistanceField
from math.utils import mix_trilinear
from math.vector3 import Vector3
from render.tasks import TaskGroup
from std.sys import num_logical_cores

# The collider's grid: cells along each side of its box.
comptime COLLIDER_CELLS = 48
# How far past the collider's box a sample reads as empty, in meters.
comptime FAR_AWAY = Float32(1.0)


__async def _bake_task[
    F: DistanceField
](
    field: Pointer[F, ImmutAnyOrigin],
    low: Vector3,
    cell: Vector3,
    cells: Int,
    values: MutPointer[Float32, MutAnyOrigin],
    first: Int,
    past: Int,
):
    """Sample the planes from `first` up to `past` of a baked grid."""
    for k in range(first, past):  # pragma: no branch
        for j in range(cells):  # pragma: no branch
            for i in range(cells):  # pragma: no branch
                values[
                    unsafe_offset=(k * cells + j) * cells + i
                ] = field[].distance(
                    low
                    + Vector3(
                        Float32(i) * cell.x,
                        Float32(j) * cell.y,
                        Float32(k) * cell.z,
                    )
                )


struct HairCollider(Copyable, DistanceField, Movable):
    """A distance field baked into a grid, which a step reads for each
    point: a solid's own field is far too slow to read that often."""

    var low: Vector3
    var cell: Vector3
    var cells: Int
    var values: List[Float32]

    def __init__[
        F: DistanceField
    ](out self, field: F, low: Vector3, high: Vector3):
        """Bake `field` over the box from `low` to `high`, on every
        thread.

        Args:
            field: The solid, a head's skin.
            low: The box's least corner.
            high: The box's greatest corner.
        """
        self.cells = COLLIDER_CELLS
        self.low = low
        var span = Float32(self.cells - 1)
        self.cell = Vector3(
            (high.x - low.x) / span,
            (high.y - low.y) / span,
            (high.z - low.z) / span,
        )
        var n = self.cells
        self.values = List[Float32](length=n * n * n, fill=0)
        # Each thread samples its own planes: one writer to each slot.
        var tasks = min(num_logical_cores(), n)
        var bakers = TaskGroup()
        for task in range(tasks):  # pragma: no branch
            bakers.create_task(
                _bake_task(
                    Pointer(to=field).unsafe_origin_cast[ImmutAnyOrigin](),
                    low,
                    self.cell,
                    n,
                    self.values.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                    task * n // tasks,
                    (task + 1) * n // tasks,
                )
            )
        bakers.wait()

    def distance(self, point: Vector3) -> Float32:
        """Return the baked distance at `point`, trilinear between the
        grid's samples, or far away off the grid.

        Args:
            point: Where to read, in the frame the field was baked in.

        Returns:
            The distance, negative inside the solid.
        """
        var u = (point.x - self.low.x) / self.cell.x
        var v = (point.y - self.low.y) / self.cell.y
        var w = (point.z - self.low.z) / self.cell.z
        var top = Float32(self.cells - 1)
        if u < 0 or v < 0 or w < 0 or u >= top or v >= top or w >= top:
            return FAR_AWAY
        var i = Int(u)
        var j = Int(v)
        var k = Int(w)
        var fu = u - Float32(i)
        var fv = v - Float32(j)
        var fw = w - Float32(k)
        var n = self.cells
        var at = (k * n + j) * n + i
        return mix_trilinear[DType.float32, 1](
            self.values[at],
            self.values[at + 1],
            self.values[at + n],
            self.values[at + n + 1],
            self.values[at + n * n],
            self.values[at + n * n + 1],
            self.values[at + n * n + n],
            self.values[at + n * n + n + 1],
            fu,
            fv,
            fw,
        )
