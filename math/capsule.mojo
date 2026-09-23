# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A capsule, from three.js `examples/jsm/math/Capsule.js`.

A capsule is a sphere swept along a segment: a cylinder with a half sphere
on each end. A game uses it as the collider of a player, because it slides
over steps and edges where a box catches. `math.octree` pushes a capsule out
of the triangles it overlaps.

This is the capsule as a bound, not as a mesh. `geometries.capsule` builds
the triangles of one.

Like `Sphere`, a capsule holds bare `Float32` meters. The radius must be
zero or more and finite, and the constructor refuses any other value.
three.js accepts any number.
"""

from math.bounds import Box3
from math.vector3 import Vector3
from std.math import isfinite


def _check_axis(
    p1x: Float32,
    p1y: Float32,
    p2x: Float32,
    p2y: Float32,
    minx: Float32,
    maxx: Float32,
    miny: Float32,
    maxy: Float32,
    radius: Float32,
) -> Bool:
    """Return whether a segment, grown by a radius, can touch a box in one
    plane. three.js: `checkAABBAxis`.

    Args:
        p1x: The start's first coordinate.
        p1y: The start's second coordinate.
        p2x: The end's first coordinate.
        p2y: The end's second coordinate.
        minx: The box's smallest first coordinate.
        maxx: The box's largest first coordinate.
        miny: The box's smallest second coordinate.
        maxy: The box's largest second coordinate.
        radius: The radius.

    Returns:
        False if the segment lies wholly past one side of the box by the
        radius or more.
    """
    return (
        (minx - p1x < radius or minx - p2x < radius)
        and (p1x - maxx < radius or p2x - maxx < radius)
        and (miny - p1y < radius or miny - p2y < radius)
        and (p1y - maxy < radius or p2y - maxy < radius)
    )


struct Capsule(ImplicitlyCopyable):
    """A segment and a radius: every point within the radius of the segment.
    three.js: `Capsule`."""

    var start: Vector3
    var end: Vector3
    var radius: Float32

    def __init__(out self):
        """Create three.js's default capsule: from the origin to one meter up
        y, one meter in radius."""
        self.start = Vector3(0, 0, 0)
        self.end = Vector3(0, 1, 0)
        self.radius = 1

    def __init__(
        out self, start: Vector3, end: Vector3, radius: Float32
    ) raises:
        """Create a capsule. three.js: the constructor and `set`.

        Args:
            start: One end of the segment.
            end: The other end.
            radius: The distance of the surface from the segment, in
                meters.

        Raises:
            Error: If the radius is negative or not finite.
        """
        if not isfinite(radius) or radius < 0:
            raise Error("A capsule's radius must be finite and not negative")
        self.start = start
        self.end = end
        self.radius = radius

    def center(self) -> Vector3:
        """Return the midpoint of the segment. three.js: `getCenter`.

        Returns:
            The center.
        """
        return (self.end + self.start) * 0.5

    def translate(mut self, offset: Vector3):
        """Move the capsule. three.js: `translate`.

        Args:
            offset: How far to move it.
        """
        self.start.add(offset)
        self.end.add(offset)

    def intersects_box(self, box: Box3) -> Bool:
        """Return whether the capsule can touch a box. three.js:
        `intersectsBox`.

        The test is three.js's: in each of the three coordinate planes, the
        segment must not lie wholly past a side of the box by the radius or
        more. It is conservative. A capsule near a corner of the box can pass
        the test and not touch the box, and `math.octree` then tests the
        triangles.

        Args:
            box: The box.

        Returns:
            Whether the capsule can touch it.
        """
        return (
            _check_axis(
                self.start.x,
                self.start.y,
                self.end.x,
                self.end.y,
                box.min.x,
                box.max.x,
                box.min.y,
                box.max.y,
                self.radius,
            )
            and _check_axis(
                self.start.x,
                self.start.z,
                self.end.x,
                self.end.z,
                box.min.x,
                box.max.x,
                box.min.z,
                box.max.z,
                self.radius,
            )
            and _check_axis(
                self.start.y,
                self.start.z,
                self.end.y,
                self.end.z,
                box.min.y,
                box.max.y,
                box.min.z,
                box.max.z,
                self.radius,
            )
        )
