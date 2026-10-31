# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The small lives of the village: fireflies by night and butterflies by
day.

A `Haunt` is a round patch of the meadow, and how many fireflies and
butterflies keep to it. `Critters` draws each one, and flies it on a
loop of its own around a point of its haunt:

| Critter | What it is | When it shows | How it moves |
|---|---|---|---|
| Firefly | A mote 8 centimeters across, drawn unlit in yellow-green, so it glows | When the daylight is less than `NIGHT` | It drifts slowly, 0.4 to 1.3 meters up, and blinks |
| Butterfly | A dark body and four wings 24 centimeters across, in one of four colors: see `wing_color` | When the daylight is more than `DAY` | It flutters 0.5 to 1.2 meters up, faces where it flies, and beats its wings |

Neither flies in rain: each hides when the weather's rain is more than
`WET`. A critter over the pond flies over its water, not its floor.
"""

from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.vegetation.ground import Ground
from extensions.vegetation.noise import hash01
from extensions.village.sheet import Sheet
from extensions.village.surfaces import HouseLooks
from materials.material import standard_material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from std.math import atan2, cos, floor, pi, sin
from units.si import METER, RADIAN, SECOND, Angle, Duration, Length

comptime NIGHT = Float32(0.3)
"""The daylight below which the fireflies show."""
comptime DAY = Float32(0.6)
"""The daylight above which the butterflies show."""
comptime WET = Float32(0.5)
"""The rain above which no critter flies."""
comptime GLOW = Vector3(0.85, 1.0, 0.3)
"""The color of a firefly, drawn unlit."""


def wing_color(index: Int) -> Vector3:
    """Return the color of a butterfly's wings.

    Args:
        index: The butterfly's number. Four colors take turns.

    Returns:
        Orange, cream, blue or yellow.
    """
    var k = index % 4
    if k == 0:
        return Vector3(0.95, 0.45, 0.08)
    if k == 1:
        return Vector3(0.92, 0.9, 0.8)
    if k == 2:
        return Vector3(0.2, 0.42, 0.95)
    return Vector3(0.95, 0.8, 0.15)


comptime FLAP = Float32(16)
"""How fast a butterfly beats its wings, in radians a second."""
comptime BLINK = Float32(0.55)
"""The share of its time that a firefly glows."""


struct Haunt(ImplicitlyCopyable):
    """A round patch of the meadow, and the critters that keep to it."""

    var x: Length
    var z: Length
    var radius: Length
    var fireflies: Int
    var butterflies: Int

    def __init__(
        out self,
        x: Length,
        z: Length,
        radius: Length,
        fireflies: Int,
        butterflies: Int,
    ):
        """Hold a haunt.

        Args:
            x: Its middle, east of the village's origin.
            z: Its middle, south of the village's origin.
            radius: How far from its middle its critters fly.
            fireflies: How many fireflies keep to it.
            butterflies: How many butterflies keep to it.
        """
        self.x = x
        self.z = z
        self.radius = radius
        self.fireflies = fireflies
        self.butterflies = butterflies

    def check(self) raises:
        """Refuse a haunt that cannot be flown.

        Raises:
            Error: If the radius is not from 0 to 100 meters, or a count is
                not from 0 to 64.
        """
        var r = self.radius.to(METER)
        if not (r >= 0 and r <= 100):
            raise Error("A haunt's radius must be from 0 to 100 meters")
        if self.fireflies < 0 or self.fireflies > 64:
            raise Error("A haunt must have from 0 to 64 fireflies")
        if self.butterflies < 0 or self.butterflies > 64:
            raise Error("A haunt must have from 0 to 64 butterflies")


def default_haunts() -> List[Haunt]:
    """Return the haunts of the default village.

    Returns:
        The pond, with the most fireflies, and three patches of the meadow
        clear of the houses.
    """
    return [
        Haunt(
            Length(8.0, METER), Length(19.0, METER), Length(6.5, METER), 14, 2
        ),
        Haunt(
            Length(-8.0, METER), Length(24.0, METER), Length(5.0, METER), 6, 3
        ),
        Haunt(
            Length(-18.0, METER), Length(-8.0, METER), Length(5.0, METER), 6, 2
        ),
        Haunt(
            Length(10.0, METER), Length(-6.0, METER), Length(4.0, METER), 0, 2
        ),
    ]


def _firefly() -> Sheet:
    """Return a firefly: a mote of eight faces, 8 centimeters across."""
    var sheet = Sheet(1)
    var r = Float32(0.04)
    for k in range(4):
        var a = pi / 2 * Float32(k)
        var b = pi / 2 * Float32(k + 1)
        var p = Vector3(cos(a) * r, 0, -sin(a) * r)
        var q = Vector3(cos(b) * r, 0, -sin(b) * r)
        var i0 = sheet.vertex(Vector3(0, r, 0), Vector3(0, 1, 0), GLOW, 0, 0)
        var i1 = sheet.vertex(p, Vector3(0, 1, 0), GLOW, 0, 0)
        var i2 = sheet.vertex(q, Vector3(0, 1, 0), GLOW, 0, 0)
        sheet.triangle(i0, i1, i2)
        var j0 = sheet.vertex(Vector3(0, -r, 0), Vector3(0, -1, 0), GLOW, 0, 0)
        var j1 = sheet.vertex(q, Vector3(0, -1, 0), GLOW, 0, 0)
        var j2 = sheet.vertex(p, Vector3(0, -1, 0), GLOW, 0, 0)
        sheet.triangle(j0, j1, j2)
    return sheet^


def _body() -> Sheet:
    """Return a butterfly's body: a dark bar 11 centimeters long, along +z."""
    var sheet = Sheet(1)
    sheet.box(
        Vector3(0, 0, 0),
        Vector3(0.01, 0, 0),
        Vector3(0, 0.01, 0),
        Vector3(0, 0, 0.055),
        Vector3(0.05, 0.04, 0.03),
    )
    return sheet^


def _wing(color: Vector3, side: Float32) -> Sheet:
    """Return a butterfly's two wings on one side, hinged on the body
    along z: a forewing and a smaller hindwing, seen from both faces.

    Args:
        color: The wings' color.
        side: 1 for the wings on +x, and -1 for those on -x.
    """
    var sheet = Sheet(1)
    var edge = color * 0.45
    var root = Vector3(0, 0, 0.016)
    # The forewing reaches forward and out; the hindwing back and out.
    var shapes: List[Vector3] = [
        Vector3(0.12 * side, 0, 0.07),
        Vector3(0.105 * side, 0, -0.008),
        Vector3(0.08 * side, 0, -0.016),
        Vector3(0.032 * side, 0, -0.08),
    ]
    var up = Vector3(0, 1, 0)
    var down = Vector3(0, -1, 0)
    for w in range(2):
        var a = shapes[2 * w]
        var b = shapes[2 * w + 1]
        var tip = color if w == 0 else color * 0.8
        var i0 = sheet.vertex(root, up, edge, 0, 0)
        var i1 = sheet.vertex(a, up, tip, 0, 0)
        var i2 = sheet.vertex(b, up, tip, 0, 0)
        var j0 = sheet.vertex(root, down, edge, 0, 0)
        var j1 = sheet.vertex(a, down, tip, 0, 0)
        var j2 = sheet.vertex(b, down, tip, 0, 0)
        if side > 0:
            sheet.triangle(i0, i1, i2)
            sheet.triangle(j0, j2, j1)
        else:
            sheet.triangle(i0, i2, i1)
            sheet.triangle(j0, j1, j2)
    return sheet^


struct Critters(Movable):
    """The fireflies and butterflies of the village, and their flight."""

    var fireflies: List[NodeId]
    var butterflies: List[NodeId]
    # Each butterfly's wings: the one on +x, then the one on -x.
    var wings: List[NodeId]
    # The middle of each critter's loop, fireflies first, on the ground or
    # the water under it.
    var homes: List[Vector3]
    # How far each critter flies from its middle, in meters.
    var reaches: List[Float32]
    # Each critter's own place in its loop and its blink, from 0 to 1.
    var phases: List[Float32]
    var clock: Float32
    # How many meshes and triangles the critters add to the scene.
    var meshes: Int
    var triangles: Int

    def __init__(
        out self,
        mut scene: Scene,
        mut assets: Assets,
        looks: HouseLooks,
        haunts: List[Haunt],
        ground: Ground,
        water: Length,
    ) raises:
        """Add a mesh for each firefly, and three for each butterfly.

        Args:
            scene: The scene. Each critter is hidden until `update` shows
                it.
            assets: The stores for the geometries and the wings' material.
            looks: The village's materials: a firefly is unlit.
            haunts: Where the critters keep, and how many.
            ground: The ground they fly over.
            water: The pond's water level: a critter over the pond flies
                over it.

        Raises:
            Error: If a haunt does not check.
        """
        for haunt in haunts:
            haunt.check()
        var before = len(scene.meshes)
        self.triangles = 0
        self.fireflies = List[NodeId]()
        self.butterflies = List[NodeId]()
        self.wings = List[NodeId]()
        self.homes = List[Vector3]()
        self.reaches = List[Float32]()
        self.phases = List[Float32]()
        self.clock = 0
        var mote = _firefly()
        var glow = assets.geometries.add(mote.geometry())
        var body = _body()
        var bodies = assets.geometries.add(body.geometry())
        var silk = assets.materials.add(
            standard_material(Color(255, 255, 255), roughness=0.8)
        )
        var level = water.to(METER)
        var seed = 0
        for pass_ in range(2):
            for haunt in haunts:
                var count = haunt.fireflies if pass_ == 0 else haunt.butterflies
                var r = haunt.radius.to(METER)
                for _ in range(count):
                    seed += 1
                    # A point of the haunt, and a loop around it.
                    var a = 2 * pi * hash01(seed, 1, 91)
                    var d = r * 0.5 * hash01(seed, 2, 91)
                    var x = haunt.x.to(METER) + cos(a) * d
                    var z = haunt.z.to(METER) + sin(a) * d
                    var y = max(ground.height_at(x, z), level)
                    self.homes.append(Vector3(x, y, z))
                    self.reaches.append(r * (0.3 + 0.4 * hash01(seed, 3, 91)))
                    self.phases.append(hash01(seed, 4, 91))
                    var node = Object3D()
                    node.visible = False
                    var at = scene.add(node^)
                    if pass_ == 0:
                        scene.add_mesh(
                            Mesh(glow, looks.daylight, at, cast_shadow=False)
                        )
                        self.triangles += mote.triangles()
                        self.fireflies.append(at)
                        continue
                    scene.add_mesh(Mesh(bodies, silk, at, cast_shadow=False))
                    self.triangles += body.triangles()
                    var color = wing_color(seed)
                    for side in range(2):
                        var hinge = Object3D()
                        hinge.parent = at
                        var held = scene.add(hinge^)
                        var wing = _wing(color, Float32(1 - 2 * side))
                        scene.add_mesh(
                            Mesh(
                                assets.geometries.add(wing.geometry()),
                                silk,
                                held,
                                cast_shadow=False,
                            )
                        )
                        self.triangles += wing.triangles()
                        self.wings.append(held)
                    self.butterflies.append(at)
        self.meshes = len(scene.meshes) - before

    def update(
        mut self,
        mut scene: Scene,
        daylight: Float32,
        rain: Float32,
        delta: Duration,
    ) raises:
        """Fly each critter on along its loop, and show those whose hour
        and weather it is.

        Args:
            scene: The scene the critters are in.
            daylight: The share of the day's light, from 0 to 1.
            rain: How hard it rains, from 0 to 1.
            delta: The frame's time.

        Raises:
            Error: If the time is negative.
        """
        var seconds = delta.to(SECOND)
        if not (seconds >= 0):
            raise Error("A frame's time must not be negative")
        self.clock += seconds
        var dry = rain <= WET
        var night = dry and daylight < NIGHT
        var day = dry and daylight > DAY
        var t = self.clock
        var flies = len(self.fireflies)
        for index in range(flies):
            ref node = scene.node(self.fireflies[index])
            var phase = self.phases[index]
            var blink = t * 0.35 + phase * 7
            node.visible = night and blink - floor(blink) < BLINK
            if not node.visible:
                continue
            var home = self.homes[index]
            var r = self.reaches[index]
            var a = 0.18 * t + 2 * pi * phase
            node.set_position(
                home.x + r * cos(a),
                home.y + 0.85 + 0.45 * sin(0.6 * t + 5 * phase),
                home.z + r * sin(1.4 * a),
            )
        for index in range(len(self.butterflies)):
            var k = flies + index
            ref node = scene.node(self.butterflies[index])
            node.visible = day
            if not day:
                continue
            var home = self.homes[k]
            var r = self.reaches[k]
            var phase = self.phases[k]
            var w = Float32(0.45)
            var a = w * t + 2 * pi * phase
            var b = 1.3 * a
            var beat = FLAP * t + 9 * phase
            node.set_position(
                home.x + r * cos(a),
                home.y
                + 0.85
                + 0.35 * sin(0.8 * t + 4 * phase)
                + 0.04 * sin(beat),
                home.z + r * sin(b),
            )
            # It faces along its flight: the body is built along +z.
            var dx = -r * sin(a)
            var dz = 1.3 * r * cos(b)
            node.set_rotation_from_axis_angle(
                Vector3(0, 1, 0), Angle(atan2(dx, dz), RADIAN)
            )
            var lift = 0.25 + 0.85 * sin(beat)
            scene.node(self.wings[2 * index]).set_rotation_from_axis_angle(
                Vector3(0, 0, 1), Angle(lift, RADIAN)
            )
            scene.node(self.wings[2 * index + 1]).set_rotation_from_axis_angle(
                Vector3(0, 0, 1), Angle(-lift, RADIAN)
            )
