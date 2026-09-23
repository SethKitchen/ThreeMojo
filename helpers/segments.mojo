# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The pairs of points a helper is written as, and their colors.

Every helper here is a list of segments for a `Line` in `SEGMENTS` mode,
each end with a linear color. three.js builds some of its helpers as
line strips and some as wireframe meshes; here each of those is broken
into its segments, so one kind of `Line` and one `helper_material` draw
them all. `Segments` gathers the points and colors, and `geometry` turns
them into the `BufferGeometry` a `Line` names.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, COLOR, POSITION
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from render.framebuffer import FloatColor


struct Segments(Movable):
    """The segments of a helper being built: two points each, with a
    linear color at every point."""

    var positions: List[Float32]
    var colors: List[Float32]

    def __init__(out self):
        """Create an empty list of segments."""
        self.positions = List[Float32]()
        self.colors = List[Float32]()

    def _point(mut self, point: Vector3, color: FloatColor):
        """Append one point and its color."""
        self.positions.append(point.x)
        self.positions.append(point.y)
        self.positions.append(point.z)
        self.colors.append(color.r)
        self.colors.append(color.g)
        self.colors.append(color.b)

    def add(mut self, start: Vector3, end: Vector3, color: FloatColor):
        """Append one segment in one color.

        Args:
            start: Where the segment begins.
            end: Where it ends.
            color: Its color at both ends, in linear light.
        """
        self._point(start, color)
        self._point(end, color)

    def add_blend(
        mut self,
        start: Vector3,
        end: Vector3,
        start_color: FloatColor,
        end_color: FloatColor,
    ):
        """Append one segment that fades from one color to another.

        Args:
            start: Where the segment begins.
            end: Where it ends.
            start_color: Its color at `start`, in linear light.
            end_color: Its color at `end`, in linear light.
        """
        self._point(start, start_color)
        self._point(end, end_color)

    def add_strip(
        mut self, points: List[Vector3], place: Matrix4, color: FloatColor
    ):
        """Append a line strip as its segments, each point carried by
        `place` first.

        three.js draws some helpers as a `Line`, which joins each point to
        the next. This writes the same picture as separate segments.

        Args:
            points: The strip's points, in order. Fewer than two add
                nothing.
            place: The transform each point is carried through.
            color: The color of every segment, in linear light.
        """
        for index in range(1, len(points)):
            self.add(
                place.transform_point(points[index - 1]),
                place.transform_point(points[index]),
                color,
            )

    def count(self) -> Int:
        """Return how many segments have been added.

        Returns:
            The number of segments, half the number of points.
        """
        return len(self.positions) // 6

    def geometry(self) raises -> BufferGeometry:
        """Return the segments as a geometry with `position` and `color`.

        Returns:
            A geometry of two points per segment, for a `Line` in
            `SEGMENTS` mode, with a `color` attribute in linear light.

        Raises:
            Error: Never; `BufferAttribute` checks the lengths, and they
                are whole points by construction.
        """
        var geometry = BufferGeometry()
        geometry.set_attribute(
            String(POSITION),
            BufferAttribute(List[Float32](self.positions), 3),
        )
        geometry.set_attribute(
            String(COLOR), BufferAttribute(List[Float32](self.colors), 3)
        )
        return geometry^
