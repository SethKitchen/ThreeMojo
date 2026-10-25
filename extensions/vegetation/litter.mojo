# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Fallen leaves, twigs and pebbles on the bare ground of a field.

`ground_litter` scatters them where a field is bare. They lie thick in a
tree's shade, where the leaves fall, and thin on dirt and on the trail:
the chance of each is `SHADE_LITTER` of the shade and `DIRT_LITTER` of
the bareness. Most are leaves, some are pebbles, and a few are twigs.

- **A leaf** is a diamond that lies on the ground, brown, ochre or the
  dull green of a fresh one.
- **A twig** is a long, thin diamond, dark brown.
- **A pebble** is an eight-faced stone, flattened and half sunk, gray or
  brown. Each face has its own normal, so it reads as stone.

All of them share one geometry, so one mesh draws them, and they take the
sun's shadow as the ground does.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, NORMAL, POSITION, BufferGeometry
from extensions.vegetation.checks import (
    require_between,
    require_count_between,
)
from extensions.vegetation.field import GrassField
from extensions.vegetation.ground import openness
from extensions.vegetation.noise import hash01
from math.vector3 import Vector3
from std.math import cos, pi, sin
from units.si import METER, Length

# The chance that a point is littered, as a share of its shade and of
# its bareness.
comptime SHADE_LITTER = Float32(0.9)
comptime DIRT_LITTER = Float32(0.5)
# The shares of the litter that are leaves and pebbles. The rest are
# twigs.
comptime LEAF_SHARE = Float32(0.78)
comptime PEBBLE_SHARE = Float32(0.17)
# How far above the ground a leaf or a twig lies, so it does not flicker
# into the ground, in meters.
comptime LIFT = Float32(0.006)


struct LitterMesh(Movable):
    """Leaves, twigs and pebbles, filled one at a time."""

    var positions: List[Float32]
    var normals: List[Float32]
    var colors: List[Float32]
    var index: List[Int]

    def __init__(out self):
        """Create an empty buffer."""
        self.positions = List[Float32]()
        self.normals = List[Float32]()
        self.colors = List[Float32]()
        self.index = List[Int]()

    def vertex_count(self) -> Int:
        """Return how many vertices the buffer holds.

        Returns:
            The vertex count.
        """
        return len(self.positions) // 3

    def _vertex(mut self, p: Vector3, n: Vector3, c: Vector3):
        """Append one vertex."""
        self.positions.append(p.x)
        self.positions.append(p.y)
        self.positions.append(p.z)
        self.normals.append(n.x)
        self.normals.append(n.y)
        self.normals.append(n.z)
        self.colors.append(c.x)
        self.colors.append(c.y)
        self.colors.append(c.z)

    def add_flat(
        mut self,
        middle: Vector3,
        turn: Float32,
        length: Float32,
        width: Float32,
        color: Vector3,
    ):
        """Add a diamond that lies on the ground, facing up: a leaf or a
        twig. Its two ends curl up a little.

        Args:
            middle: Its middle, in meters.
            turn: Which way it points, in radians about +y.
            length: Its length, in meters.
            width: Its width, in meters.
            color: Its linear color.
        """
        var along = Vector3(cos(turn), 0, sin(turn)) * (length * 0.5)
        var across = Vector3(-sin(turn), 0, cos(turn)) * (width * 0.5)
        var curl = Vector3(0, length * 0.08, 0)
        var up = Vector3(0, 1, 0)
        var first = self.vertex_count()
        self._vertex(middle - along + curl, up, color)
        self._vertex(middle + across, up, color)
        self._vertex(middle + along + curl, up, color)
        self._vertex(middle - across, up, color)
        self.index.append(first)
        self.index.append(first + 1)
        self.index.append(first + 2)
        self.index.append(first)
        self.index.append(first + 2)
        self.index.append(first + 3)

    def add_pebble(
        mut self,
        middle: Vector3,
        turn: Float32,
        radius: Float32,
        color: Vector3,
    ):
        """Add an eight-faced pebble, half as tall as it is wide, with a
        normal of its own on each face.

        Args:
            middle: Its middle, in meters.
            turn: How it is turned, in radians about +y.
            radius: Its radius across, in meters.
            color: Its linear color.
        """
        var x = Vector3(cos(turn), 0, sin(turn)) * radius
        var z = Vector3(-sin(turn), 0, cos(turn)) * radius
        var y = Vector3(0, radius * 0.5, 0)
        var rim: List[Vector3] = [x, z, -x, -z]
        for k in range(4):  # pragma: no branch
            var a = middle + rim[k]
            var b = middle + rim[(k + 1) % 4]
            self._face(middle + y, b, a, color)
            self._face(middle - y, a, b, color)

    def _face(mut self, a: Vector3, b: Vector3, c: Vector3, color: Vector3):
        """Append one triangle with its own unit normal."""
        var u = b - a
        var v = c - a
        var n = Vector3(
            u.y * v.z - u.z * v.y, u.z * v.x - u.x * v.z, u.x * v.y - u.y * v.x
        )
        n = n / n.length()
        var first = self.vertex_count()
        self._vertex(a, n, color)
        self._vertex(b, n, color)
        self._vertex(c, n, color)
        self.index.append(first)
        self.index.append(first + 1)
        self.index.append(first + 2)

    def geometry(deinit self) raises -> BufferGeometry:
        """Hand the buffer over as one indexed geometry.

        Returns:
            The geometry, with `position`, `normal`, `color` and an index.

        Raises:
            Error: If the buffer is empty.
        """
        if len(self.index) == 0:
            raise Error("A litter mesh with nothing in it makes no geometry")
        var geometry = BufferGeometry()
        geometry.set_attribute(POSITION, BufferAttribute(self.positions^, 3))
        geometry.set_attribute(NORMAL, BufferAttribute(self.normals^, 3))
        geometry.set_attribute(COLOR, BufferAttribute(self.colors^, 3))
        geometry.set_index(self.index^)
        return geometry^


def _leaf_color(pick: Float32) -> Vector3:
    """Return a fallen leaf's linear color: brown, ochre, or the dull
    green of a fresh leaf, from a number from zero to one."""
    var brown = Vector3(0.095, 0.055, 0.024)
    var ochre = Vector3(0.200, 0.120, 0.035)
    var green = Vector3(0.060, 0.075, 0.025)
    if pick < 0.5:
        return brown + (ochre - brown) * (pick * 2)
    return ochre + (green - ochre) * ((pick - 0.5) * 2)


def ground_litter(
    field: GrassField,
    center_x: Float32,
    center_z: Float32,
    reach: Length,
    count: Int,
    seed: Int,
) raises -> Optional[BufferGeometry]:
    """Scatter leaves, twigs and pebbles on a field's bare ground.

    `count` points are tried in a square `reach` each way from the middle.
    Each is littered with the chance its shade and its bareness give.

    Args:
        field: The field: its ground and its clearings are read.
        center_x: The square's middle's x, in meters.
        center_z: The square's middle's z, in meters.
        reach: How far the square reaches each way, from 1 meter to 1
            kilometer.
        count: How many points to try, from 1 to 2 million.
        seed: Which points.

    Returns:
        The litter, with `position`, `normal`, `color` and an index. None
        if no point is littered: the square has neither shade nor dirt.

    Raises:
        Error: If `reach` or `count` is out of range.
    """
    var far = reach.to(METER)
    require_between(
        far, 1, 1000, "Litter must reach from 1 meter to 1 kilometer"
    )
    require_count_between(
        count, 1, 2000000, "Litter must try from 1 to 2 million points"
    )
    ref ground = field.ground
    var turn = Float32(2) * Float32(pi)
    var mesh = LitterMesh()
    for i in range(count):  # pragma: no branch
        var x = center_x + (hash01(i, 0, seed) * 2 - 1) * far
        var z = center_z + (hash01(i, 1, seed) * 2 - 1) * far
        var shade = 1 - openness(field.clearings, x, z)
        var chance = SHADE_LITTER * shade + DIRT_LITTER * ground.bare(x, z)
        if hash01(i, 2, seed) >= chance:
            continue
        var place = Vector3(x, ground.height_at(x, z) + LIFT, z)
        var kind = hash01(i, 3, seed)
        var size = hash01(i, 4, seed)
        var spin = turn * hash01(i, 5, seed)
        var tint = hash01(i, 6, seed)
        if kind < LEAF_SHARE:
            var length = 0.06 + 0.07 * size
            mesh.add_flat(place, spin, length, length * 0.55, _leaf_color(tint))
        elif kind < LEAF_SHARE + PEBBLE_SHARE:
            var radius = 0.02 + 0.07 * size * size
            var stone = Vector3(0.11, 0.10, 0.085) * (0.6 + 0.6 * tint)
            mesh.add_pebble(
                Vector3(x, ground.height_at(x, z) + radius * 0.15, z),
                spin,
                radius,
                stone,
            )
        else:
            var length = 0.2 + 0.35 * size
            mesh.add_flat(
                place,
                spin,
                length,
                0.012,
                Vector3(0.050, 0.035, 0.020) * (0.7 + 0.6 * tint),
            )
    if mesh.vertex_count() == 0:
        return None
    return mesh^.geometry()
