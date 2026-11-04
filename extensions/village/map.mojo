# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A map of the village round the player, drawn over the frame.

`draw_map` draws a square in the frame's top left corner, `MAP_REACH`
meters each way round the player, north up:

| Mark | What it is |
|---|---|
| A tan square | A house, as wide as it reaches |
| Blue | The pond |
| A pale line | The trail |
| A white dot with a tick | The player, and which way they face |
| A green dot | A villager |
| A gold dot | A villager with an errand to give |
| A red dot | A foe that stands |

`MapMarks` holds what the map shows: the game fills it each frame.
"""

from extensions.vegetation.ground import Ground
from extensions.village.hud import Rgb, draw_text, fill_box, hud_scale
from math.vector3 import Vector3
from render.framebuffer import Framebuffer
from std.math import cos, sin
from units.si import METER

comptime MAP_REACH = Float32(60)
"""How far the map reaches each way round the player, in meters."""
comptime MAP_SHARE = Float32(0.36)
"""The share of the frame's height that the map's side takes."""


@fieldwise_init
struct MapHouse(Copyable, ImplicitlyCopyable):
    """A house on the map."""

    var x: Float32
    """Its middle along x, in meters."""
    var z: Float32
    """Its middle along z, in meters."""
    var reach: Float32
    """How far it reaches from its middle, in meters."""


struct MapMarks(Copyable, Movable):
    """What the map shows."""

    var houses: List[MapHouse]
    """The houses."""
    var people: List[Vector3]
    """Each villager's feet."""
    var errands: List[Vector3]
    """The feet of each villager with an errand to give."""
    var foes: List[Vector3]
    """The feet of each foe that stands."""

    def __init__(out self):
        """Show nothing yet."""
        self.houses = List[MapHouse]()
        self.people = List[Vector3]()
        self.errands = List[Vector3]()
        self.foes = List[Vector3]()


def _dot(mut frame: Framebuffer, x: Int, y: Int, size: Int, color: Rgb):
    """Draw a square dot of a color, its middle at a pixel."""
    fill_box(frame, x - size, y - size, x + size + 1, y + size + 1, color, 1)


def _place(
    at: Vector3, player: Vector3, meters: Float32, side: Int, x0: Int, y0: Int
) -> Tuple[Int, Int, Bool]:
    """Return the pixel of a place on the map, and whether it is on it."""
    var cx = Int((at.x - player.x + MAP_REACH) / meters)
    var cy = Int((at.z - player.z + MAP_REACH) / meters)
    var inside = cx >= 0 and cy >= 0 and cx < side and cy < side
    return (x0 + cx, y0 + cy, inside)


def draw_map(
    mut frame: Framebuffer,
    ground: Ground,
    marks: MapMarks,
    player: Vector3,
    heading: Float32,
) raises -> Int:
    """Draw the map of the village round the player over a frame.

    Args:
        frame: The frame. Its top left corner is changed.
        ground: The ground: its pond and its trail.
        marks: The houses, the people and the foes.
        player: The player's feet.
        heading: Which way the player faces, as a yaw in radians: zero
            faces -z, north.

    Returns:
        The map's side, in pixels.

    Raises:
        Error: Never: the font holds every character drawn.
    """
    var side = max(16, Int(Float32(frame.height) * MAP_SHARE))
    var x0 = 8
    var y0 = 8
    var meters = 2 * MAP_REACH / Float32(side)
    var pond = ground.pond
    var px = pond.x.to(METER)
    var pz = pond.z.to(METER)
    var pr = pond.radius.to(METER)
    for row in range(side):  # pragma: no branch
        var wz = player.z - MAP_REACH + (Float32(row) + 0.5) * meters
        var course = ground.trail_x(wz)
        for column in range(side):  # pragma: no branch
            var wx = player.x - MAP_REACH + (Float32(column) + 0.5) * meters
            var color = Rgb(40, 62, 32)
            var dx = wx - px
            var dz = wz - pz
            if abs(wx - course) < 1.2:
                color = Rgb(150, 130, 90)
            if dx * dx + dz * dz < pr * pr:
                color = Rgb(50, 90, 150)
            for house in marks.houses:
                if (
                    abs(wx - house.x) < house.reach * 0.7
                    and abs(wz - house.z) < house.reach * 0.7
                ):
                    color = Rgb(190, 160, 110)
            fill_box(
                frame,
                x0 + column,
                y0 + row,
                x0 + column + 1,
                y0 + row + 1,
                color,
                0.8,
            )

    var size = max(1, side // 90)
    for at in marks.people:
        var p = _place(at, player, meters, side, x0, y0)
        if p[2]:
            _dot(frame, p[0], p[1], size, Rgb(110, 210, 90))
    for at in marks.errands:
        var p = _place(at, player, meters, side, x0, y0)
        if p[2]:
            _dot(frame, p[0], p[1], size + 1, Rgb(255, 205, 90))
    for at in marks.foes:
        var p = _place(at, player, meters, side, x0, y0)
        if p[2]:
            _dot(frame, p[0], p[1], size + 1, Rgb(230, 60, 50))
    # The player in the middle, and a tick the way they face.
    var mx = x0 + side // 2
    var my = y0 + side // 2
    _dot(frame, mx, my, size + 1, Rgb(245, 238, 220))
    for step in range(1, 4 * (size + 1)):  # pragma: no branch
        var tx = mx - Int(Float32(step) * sin(heading))
        var ty = my - Int(Float32(step) * cos(heading))
        _dot(frame, tx, ty, 0, Rgb(245, 238, 220))
    draw_text(
        frame,
        x0 + 4,
        y0 + side + 4,
        "MAP",
        hud_scale(frame.height),
        Rgb(245, 238, 220),
        1,
    )
    return side
