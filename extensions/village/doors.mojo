# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The village's doors, which open as someone comes near and close
behind them.

Each door is a `Doorway` of a house's interior and the `Hinge` its leaf
turns on. `Doors.update` reads where everyone stands. A door with someone
within `OPEN_REACH` of its middle, on its floor, swings open to `WIDE`.
The others swing shut. A leaf turns at most `SWING_SPEED` a second, so it
swings rather than jumps.

A leaf is not solid: the wall's gap is what a character walks through.
"""

from core.scene import Scene
from extensions.village.house_view import Hinge
from extensions.village.interior import Doorway
from math.vector3 import Vector3
from units.si import RADIAN, SECOND, Angle, Duration

comptime OPEN_REACH = Float32(1.8)
"""How near a door's middle someone must stand for it to open, in
meters."""
comptime WIDE = Float32(1.6)
"""How far an open door turns, in radians: a little over a right angle."""
comptime SWING_SPEED = Float32(2.5)
"""How fast a leaf turns, in radians a second."""
comptime HEADROOM = Float32(2.0)
"""How far above or below a door's floor someone may stand and still open
it, in meters."""


struct Doors(Movable):
    """Every door of the village, and how far each one stands open."""

    var hinges: List[Hinge]
    var ways: List[Doorway]
    # How far each leaf stands open, in radians.
    var angles: List[Float32]

    def __init__(out self):
        """Hold no doors."""
        self.hinges = List[Hinge]()
        self.ways = List[Doorway]()
        self.angles = List[Float32]()

    def add(mut self, hinge: Hinge, way: Doorway):
        """Add a door, shut.

        Args:
            hinge: The node its leaf turns on, and how it turns.
            way: Where the door stands.
        """
        self.hinges.append(hinge)
        self.ways.append(way)
        self.angles.append(0)

    def update(
        mut self, mut scene: Scene, people: List[Vector3], delta: Duration
    ) raises:
        """Swing each door toward open or shut for one frame.

        Args:
            scene: The scene the doors are in.
            people: Where each person and animal stands: their feet.
            delta: The frame's time.

        Raises:
            Error: If the time is negative.
        """
        var seconds = delta.to(SECOND)
        if not (seconds >= 0):
            raise Error("A frame's time must not be negative")
        var most = SWING_SPEED * seconds
        for index in range(len(self.ways)):
            var middle = self.ways[index].middle()
            var wanted = Float32(0)
            for p in people:
                var dx = p.x - middle.x
                var dz = p.z - middle.z
                var near = dx * dx + dz * dz < OPEN_REACH * OPEN_REACH
                if near and abs(p.y - middle.y) < HEADROOM:
                    wanted = WIDE
            var angle = self.angles[index]
            var step = min(most, abs(wanted - angle))
            angle += step if wanted > angle else -step
            self.angles[index] = angle
            ref hinge = self.hinges[index]
            scene.node(hinge.node).set_rotation_from_axis_angle(
                Vector3(0, 1, 0),
                Angle(hinge.shut + hinge.sense * angle, RADIAN),
            )
