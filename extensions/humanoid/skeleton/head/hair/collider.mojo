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
from math.vector3 import Vector3

# The collider's grid: cells along each side of its box.
comptime COLLIDER_CELLS = 48
# How far past the collider's box a sample reads as empty, in meters.
comptime FAR_AWAY = Float32(1.0)


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
        """Bake `field` over the box from `low` to `high`.

        Args:
            field: The solid, a head's skin.
            low: The box's least corner.
            high: The box's greatest corner.
        """
        self.cells = COLLIDER_CELLS
        self.low = low
        var n = Float32(self.cells - 1)
        self.cell = Vector3(
            (high.x - low.x) / n, (high.y - low.y) / n, (high.z - low.z) / n
        )
        self.values = List[Float32](
            capacity=self.cells * self.cells * self.cells
        )
        for k in range(self.cells):  # pragma: no branch
            for j in range(self.cells):  # pragma: no branch
                for i in range(self.cells):  # pragma: no branch
                    self.values.append(
                        field.distance(
                            low
                            + Vector3(
                                Float32(i) * self.cell.x,
                                Float32(j) * self.cell.y,
                                Float32(k) * self.cell.z,
                            )
                        )
                    )

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
        var c00 = self.values[at] + (self.values[at + 1] - self.values[at]) * fu
        var c10 = (
            self.values[at + n]
            + (self.values[at + n + 1] - self.values[at + n]) * fu
        )
        var c01 = (
            self.values[at + n * n]
            + (self.values[at + n * n + 1] - self.values[at + n * n]) * fu
        )
        var c11 = (
            self.values[at + n * n + n]
            + (self.values[at + n * n + n + 1] - self.values[at + n * n + n])
            * fu
        )
        var c0 = c00 + (c10 - c00) * fv
        var c1 = c01 + (c11 - c01) * fv
        return c0 + (c1 - c0) * fw
