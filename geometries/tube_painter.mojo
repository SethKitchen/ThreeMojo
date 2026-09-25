# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A tube drawn as a pen moves, from three.js
`examples/jsm/misc/TubePainter.js`.

A `TubePainter` is a pen. `move_to` lifts it to a point, and `line_to`
draws a tube from where it was to a new point: a ring of ten sides at each
end, turned to face along the stroke, and the walls between them. `size`
scales the tube's radius, one centimeter at a size of one. `geometry`
returns what has been drawn, with `position`, `normal` and `color`.

three.js fills a buffer of a million vertices and moves its draw range on.
Here the lists grow as strokes are drawn. three.js's painter owns a mesh
with a `STANDARD` material that reads the vertex colors, and turns its
frustum culling off; the caller makes that mesh here.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, COLOR, NORMAL, POSITION
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from render.framebuffer import FloatColor
from std.math import cos, pi, sin

# How many sides a stroke's ring has, three.js's `sides`.
comptime TUBE_SIDES = 10
# A stroke's radius at a size of one, in meters.
comptime TUBE_RADIUS = Float32(0.01)


def _push(mut out: List[Float32], v: Vector3):
    """Append a vector's three numbers."""
    out.append(v.x)
    out.append(v.y)
    out.append(v.z)


struct TubePainter(Movable):
    """A pen that draws tubes, three.js's `TubePainter`."""

    var positions: List[Float32]
    var normals: List[Float32]
    var colors: List[Float32]
    # How thick the next strokes are: a factor on `TUBE_RADIUS`.
    var size: Float32
    # The color of the next strokes, in linear light. White, as three.js's
    # painter has it.
    var color: FloatColor
    # Where the pen is, and which way the last stroke's end faced,
    # three.js's `point2` and `matrix2`.
    var _point: Vector3
    var _facing: Matrix4
    # How many vertices `update` has counted, three.js's `count`.
    var _updated: Int

    def __init__(out self):
        """Create a pen at the origin with nothing drawn."""
        self.positions = List[Float32]()
        self.normals = List[Float32]()
        self.colors = List[Float32]()
        self.size = 1
        self.color = FloatColor(1, 1, 1)
        self._point = Vector3(0, 0, 0)
        self._facing = Matrix4()
        self._updated = 0

    def set_size(mut self, value: Float32):
        """Set how thick the next strokes are, three.js's `setSize`.

        Args:
            value: A factor on the radius: one is one centimeter.
        """
        self.size = value

    def _ring(self) -> List[Vector3]:
        """Return the ring of a stroke's end, three.js's `getPoints`."""
        var radius = TUBE_RADIUS * self.size
        var out = List[Vector3]()
        for i in range(TUBE_SIDES):  # pragma: no branch
            var angle = Float32(i) / Float32(TUBE_SIDES) * 2 * pi
            out.append(Vector3(sin(angle) * radius, cos(angle) * radius, 0))
        return out^

    def _facing_to(self, point: Vector3) -> Matrix4:
        """Return a turn that faces from the pen toward a point, three.js's
        `matrix1.lookAt( point2, point1, up )`."""
        var facing = Matrix4()
        facing.look_at(self._point, point, Vector3(0, 1, 0))
        return facing^

    def move_to(mut self, position: Vector3):
        """Lift the pen to a point, three.js's `moveTo`.

        Args:
            position: Where the next stroke starts.
        """
        self._facing = self._facing_to(position)
        self._point = position

    def line_to(mut self, position: Vector3):
        """Draw a tube from the pen to a point, three.js's `lineTo`.
        Nothing is drawn to the point the pen is at.

        Args:
            position: Where the stroke ends, and the pen with it.
        """
        var facing = self._facing_to(position)
        var start = self._point
        var start_facing = Matrix4(copy=self._facing)
        self._stroke(position, start, facing, start_facing)
        self._point = position
        self._facing = facing^

    def _stroke(
        mut self,
        end: Vector3,
        start: Vector3,
        end_facing: Matrix4,
        start_facing: Matrix4,
    ):
        """Append the walls between two rings, three.js's `stroke`."""
        if (end - start).length_sq() == 0:
            return
        var ring = self._ring()
        for i in range(len(ring)):  # pragma: no branch
            var one = ring[i]
            var two = ring[(i + 1) % len(ring)]
            var a = start_facing.transform_point(one)
            var b = start_facing.transform_point(two)
            var c = end_facing.transform_point(two)
            var d = end_facing.transform_point(one)
            for p in [  # pragma: no branch
                a + start,
                b + start,
                d + end,
                b + start,
                c + end,
                d + end,
            ]:
                _push(self.positions, p)
            for n in [a, b, d, b, c, d]:  # pragma: no branch
                var unit = n
                unit.normalize()
                _push(self.normals, unit)
            for _ in range(6):  # pragma: no branch
                self.colors.append(self.color.r)
                self.colors.append(self.color.g)
                self.colors.append(self.color.b)

    def count(self) -> Int:
        """Return how many vertices have been drawn, three.js's
        `drawRange.count`.

        Returns:
            Three for every triangle.
        """
        return len(self.positions) // 3

    def update(mut self) -> Tuple[Int, Int]:
        """Return the vertices drawn since the last update, three.js's
        `update`, which marks that range of its buffers to upload.

        Returns:
            The first vertex and how many there are. Zero of them when
            nothing new was drawn.
        """
        var start = self._updated
        self._updated = self.count()
        return (start, self._updated - start)

    def geometry(self) raises -> BufferGeometry:
        """Return what has been drawn.

        Returns:
            Triangles with `position`, `normal` and `color`.

        Raises:
            Error: Never; the lists hold whole points.
        """
        var geometry = BufferGeometry()
        geometry.set_attribute(
            String(POSITION), BufferAttribute(self.positions.copy(), 3)
        )
        geometry.set_attribute(
            String(NORMAL), BufferAttribute(self.normals.copy(), 3)
        )
        geometry.set_attribute(
            String(COLOR), BufferAttribute(self.colors.copy(), 3)
        )
        return geometry^
