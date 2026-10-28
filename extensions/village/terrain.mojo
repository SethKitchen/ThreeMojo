# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What carries a character and what stops it: the ground, the floors of
the houses, their walls, and the buildings that cannot be entered.

A house is not a solid block, because a character walks in at its door.
A house gives a `Terrain` its walls, as `WallSpan` values with gaps at
the doors, and its floor, as a `Floor`. A building that cannot be
entered, such as a scanned one, stays a solid `Lot`.

- `Terrain.height_at` is the height of the highest floor under a point,
  or of the ground where there is no floor.
- `wall_push` moves a circle out of a wall span, as `lot_push` moves it
  out of a lot.
- `Terrain.view_reach` says how far a camera can stand from its focus
  before a wall comes between them. `Terrain.ceiling_over` says how high
  it can stand over a floor.
"""

from extensions.vegetation.ground import Ground, Lot
from math.vector3 import Vector3
from std.math import sqrt

comptime OPEN_SKY = Float32(1.0e30)
"""The ceiling of a floor that has nothing over it, in meters."""
comptime INSIDE = Float32(1.0e-6)
"""A point nearer a lot than this, in meters, is on it."""


@fieldwise_init
struct WallSpan(ImplicitlyCopyable):
    """A straight piece of wall, seen from above: a segment with a
    thickness, from a foot to a top."""

    # The two ends of the wall's middle line, in meters.
    var x0: Float32
    var z0: Float32
    var x1: Float32
    var z1: Float32
    # Half the wall's thickness, in meters.
    var half_thickness: Float32
    # The heights of its foot and its top, in meters.
    var bottom: Float32
    var top: Float32

    def nearest(self, x: Float32, z: Float32) -> Vector3:
        """Return the point of the wall's middle line nearest a point.

        Args:
            x: The point's x, in meters.
            z: The point's z, in meters.

        Returns:
            The nearest point, as `(x, 0, z)`. A span whose two ends are
            one point returns that point.
        """
        var dx = self.x1 - self.x0
        var dz = self.z1 - self.z0
        var length2 = dx * dx + dz * dz
        if length2 <= 0:
            return Vector3(self.x0, 0, self.z0)
        var t = ((x - self.x0) * dx + (z - self.z0) * dz) / length2
        t = min(Float32(1), max(Float32(0), t))
        return Vector3(self.x0 + dx * t, 0, self.z0 + dz * t)

    def blocks(self, foot: Float32, head: Float32) -> Bool:
        """Return whether the wall stands in the way of someone whose feet
        and head are at two heights.

        Args:
            foot: The height of the feet, in meters.
            head: The height of the head, in meters.

        Returns:
            Whether the wall's foot is below the head and its top above
            the feet.
        """
        return self.bottom < head and self.top > foot


def wall_push(
    span: WallSpan, x: Float32, z: Float32, radius: Float32
) -> Vector3:
    """Return where a circle must move to stand clear of a wall span.

    Args:
        span: The wall.
        x: The circle's middle, in meters.
        z: The circle's middle, in meters.
        radius: Its radius, in meters.

    Returns:
        The circle's middle, as `(x, 0, z)`, moved straight away from the
        wall's middle line until it clears the wall. The same point when
        it is already clear. A circle right on the middle line moves out
        to the left of the line, seen from its first end.
    """
    var near = span.nearest(x, z)
    var dx = x - near.x
    var dz = z - near.z
    var reach = radius + span.half_thickness
    var gap = sqrt(dx * dx + dz * dz)
    if gap >= reach:
        return Vector3(x, 0, z)
    if gap < 1.0e-6:
        var ax = span.x1 - span.x0
        var az = span.z1 - span.z0
        var length = sqrt(ax * ax + az * az)
        if length <= 0:
            return Vector3(near.x + reach, 0, near.z)
        return Vector3(
            near.x - az / length * reach, 0, near.z + ax / length * reach
        )
    var scale = reach / gap
    return Vector3(near.x + dx * scale, 0, near.z + dz * scale)


def _clip(
    start: Float32, change: Float32, low: Float32, high: Float32
) -> Tuple[Float32, Float32]:
    """Return the share of a line `start + t change` that lies from `low`
    to `high`, as the first and the last `t`. An empty share has its
    first `t` above its last."""
    if change == 0:
        if start >= low and start <= high:
            return (Float32(-1.0e30), Float32(1.0e30))
        return (Float32(1), Float32(0))
    var a = (low - start) / change
    var b = (high - start) / change
    return (min(a, b), max(a, b))


def view_entry(span: WallSpan, focus: Vector3, eye: Vector3) -> Float32:
    """Return how far along the way from a focus to an eye a wall begins.

    Args:
        span: The wall.
        focus: Where the way starts.
        eye: Where the way ends.

    Returns:
        The share of the way, from 0 to 1, at which it first enters the
        wall's box, or 1 when it never does.
    """
    var dx = span.x1 - span.x0
    var dz = span.z1 - span.z0
    var length = sqrt(dx * dx + dz * dz)
    if length <= 0:
        return 1
    var ux = dx / length
    var uz = dz / length
    # The way in the wall's own frame: along it, across it and up.
    var along0 = (focus.x - span.x0) * ux + (focus.z - span.z0) * uz
    var along1 = (eye.x - span.x0) * ux + (eye.z - span.z0) * uz
    var across0 = -(focus.x - span.x0) * uz + (focus.z - span.z0) * ux
    var across1 = -(eye.x - span.x0) * uz + (eye.z - span.z0) * ux
    var first = Float32(0)
    var last = Float32(1)
    var spans = [
        _clip(along0, along1 - along0, 0, length),
        _clip(
            across0,
            across1 - across0,
            -span.half_thickness,
            span.half_thickness,
        ),
        _clip(focus.y, eye.y - focus.y, span.bottom, span.top),
    ]
    for k in range(3):  # pragma: no branch
        first = max(first, spans[k][0])
        last = min(last, spans[k][1])
    if first > last:
        return 1
    return first


@fieldwise_init
struct Floor(ImplicitlyCopyable):
    """A level floor a character can walk on, such as a house's ground
    floor or a step before its door."""

    # Where the floor is: a rectangle, turned about +y.
    var area: Lot
    # The height of its top, in meters.
    var height: Float32
    # The height of what is over it, in meters: the underside of the
    # floor above, or `OPEN_SKY`.
    var ceiling: Float32


struct Terrain(Copyable, Movable):
    """The ground, the floors on it, the walls on them, and the solid
    buildings."""

    var ground: Ground
    # The buildings that cannot be entered.
    var lots: List[Lot]
    var walls: List[WallSpan]
    var floors: List[Floor]

    @implicit
    def __init__(out self, ground: Ground):
        """Hold bare ground, with no building on it.

        Args:
            ground: The ground.
        """
        self.ground = ground.copy()
        self.lots = List[Lot]()
        self.walls = List[WallSpan]()
        self.floors = List[Floor]()

    def __init__(
        out self,
        ground: Ground,
        var lots: List[Lot],
        var walls: List[WallSpan],
        var floors: List[Floor],
    ):
        """Gather the terrain.

        Args:
            ground: The ground.
            lots: The buildings that cannot be entered.
            walls: The walls of the houses.
            floors: The floors of the houses and their steps.
        """
        self.ground = ground.copy()
        self.lots = lots^
        self.walls = walls^
        self.floors = floors^

    def floor_under(self, x: Float32, z: Float32) -> Int:
        """Return the highest floor under a point.

        Args:
            x: The point's x, in meters.
            z: The point's z, in meters.

        Returns:
            The floor's index in `floors`, or -1 where there is none.
        """
        var best = -1
        for index in range(len(self.floors)):
            ref floor = self.floors[index]
            if floor.area.reach(x, z) >= INSIDE:
                continue
            if best < 0 or floor.height > self.floors[best].height:
                best = index
        return best

    def height_at(self, x: Float32, z: Float32) -> Float32:
        """Return the height a character stands at.

        Args:
            x: The point's x, in meters.
            z: The point's z, in meters.

        Returns:
            The height of the highest floor under the point, or of the
            ground where there is no floor.
        """
        var floor = self.floor_under(x, z)
        if floor < 0:
            return self.ground.height_at(x, z)
        return self.floors[floor].height

    def ceiling_over(self, x: Float32, z: Float32) -> Float32:
        """Return how high something can stand over a point.

        Args:
            x: The point's x, in meters.
            z: The point's z, in meters.

        Returns:
            The ceiling of the highest floor under the point, or
            `OPEN_SKY`.
        """
        var floor = self.floor_under(x, z)
        if floor < 0:
            return OPEN_SKY
        return self.floors[floor].ceiling

    def view_reach(
        self, focus: Vector3, eye: Vector3, margin: Float32
    ) -> Float32:
        """Return how much of the way from a focus to an eye is clear of
        the walls.

        Args:
            focus: The point the camera looks at.
            eye: Where the camera would stand.
            margin: How far before a wall the camera must stop, in meters.

        Returns:
            The share of the way, from 0 to 1, that the camera can stand
            at: 1 when no wall is in the way.
        """
        var first = Float32(1)
        for index in range(len(self.walls)):
            first = min(first, view_entry(self.walls[index], focus, eye))
        if first >= 1:
            return 1
        var length = (eye - focus).length()
        return max(Float32(0), first - margin / length)
