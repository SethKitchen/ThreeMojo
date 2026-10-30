# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What a sword leaves in the air: the trail of a swing, and the sparks
of a blow.

**Trails.** A `Trail` hangs one ribbon for each attack from a body's
carrier, so it turns with the body. A ribbon is an arc that a blade's
outer two thirds sweeps, as the move's clip swings it: across at the
chest for the light cuts, down from over the head for the third, high
to low for the heavy cut, low to high for the rising edge, and a whole
ring for the tempest. A ribbon shows while its move strikes, and for
`TRAIL_LINGER` after. The tempest's ribbon is the last 150 degrees of
the blade's turn, and turns with the body as the clip spins it. A ribbon
is drawn unlit and half clear, brighter at the end the blade reaches
last, as Tales of Arise draws its swings.

**Sparks.** `Sparks` keeps `SPARKS` bursts of gold rays. A blow puts the
oldest at the place it lands; it grows and shows for `SPARK_SECONDS`.
"""

from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.village.combat import (
    HEAVY,
    LIGHT_ONE,
    LIGHT_THREE,
    LIGHT_TWO,
    MOVES,
    RISING_EDGE,
    TEMPEST,
    CombatMove,
    Fighter,
    is_attack,
    move_data,
)
from extensions.humanoid.rig.sword_clips import tempest_twist
from extensions.village.sheet import Sheet
from materials.material import BASIC, DOUBLE_SIDE, Material, MaterialId
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from std.math import cos, pi, sin
from units.si import DEGREE, SECOND, Angle, Duration

comptime TRAIL_LINGER = Float32(0.06)
"""How long a trail shows after its move's active part, in seconds."""
comptime TRAIL_STEPS = 18
"""How many quads an arc of a half turn takes."""
comptime SPARKS = 6
"""How many bursts of sparks can show at once."""
comptime SPARK_SECONDS = Float32(0.16)
"""How long a burst of sparks shows, in seconds."""
comptime PLAYER_TRAIL = Vector3(0.75, 0.9, 1.0)
"""The color of the player's trails: white, touched with blue."""
comptime FOE_TRAIL = Vector3(1.0, 0.45, 0.25)
"""The color of a bandit's trails: the orange of a threat."""


def _cross(a: Vector3, b: Vector3) -> Vector3:
    """Return the cross product of two vectors."""
    var out = a
    out.cross(b)
    return out


def _unit(v: Vector3) -> Vector3:
    """Return a vector scaled to length one."""
    var out = v
    out.normalize()
    return out


def arc(
    mut sheet: Sheet,
    center: Vector3,
    first: Vector3,
    second: Vector3,
    begin: Float32,
    end: Float32,
    inner: Float32,
    outer: Float32,
    color: Vector3,
):
    """Add a flat ribbon round a center, between two radii.

    A point of the arc at the angle `a` lies along `first` times `cos a`
    plus `second` times `sin a` from the center. The ribbon is darkest at
    `begin` and brightest at `end`.

    Args:
        sheet: The sheet.
        center: The arc's center.
        first: The way the angle zero points, of length one.
        second: The way a quarter turn points, of length one.
        begin: The angle the ribbon starts at, in radians.
        end: The angle it ends at, in radians.
        inner: Its inner radius, in meters.
        outer: Its outer radius, in meters.
        color: Its color at `end`.
    """
    var steps = max(2, Int(TRAIL_STEPS * abs(end - begin) / pi))
    var normal = _cross(first, second)
    for k in range(steps):  # pragma: no branch
        var t0 = Float32(k) / Float32(steps)
        var t1 = Float32(k + 1) / Float32(steps)
        var a0 = begin + (end - begin) * t0
        var a1 = begin + (end - begin) * t1
        var d0 = first * cos(a0) + second * sin(a0)
        var d1 = first * cos(a1) + second * sin(a1)
        # Fade in from the start, and stay bright to the end.
        var c0 = color * (0.35 + 0.65 * t0 * t0)
        var c1 = color * (0.35 + 0.65 * t1 * t1)
        var i0 = sheet.vertex(center + d0 * inner, normal, c0, 0, 0)
        var i1 = sheet.vertex(center + d1 * inner, normal, c1, 0, 0)
        var i2 = sheet.vertex(center + d1 * outer, normal, c1, 0, 0)
        var i3 = sheet.vertex(center + d0 * outer, normal, c0, 0, 0)
        sheet.triangle(i0, i1, i2)
        sheet.triangle(i0, i2, i3)


def trail_sheet(move: CombatMove, scale: Float32, color: Vector3) -> Sheet:
    """Return the ribbon an attack's blade sweeps, in a body's frame.

    The frame is a body carrier's: plus z forward, the sword on minus x,
    and the hips at the origin.

    Args:
        move: The attack. A move that is not an attack has no ribbon.
        scale: The fighter's height over six feet.
        color: The ribbon's color.

    Returns:
        The ribbon's triangles, from 0.8 to 1.45 meters round the sword's
        shoulder for a person of six feet.
    """
    var sheet = Sheet(1)
    var s = scale
    var inner = Float32(0.8) * s
    var outer = Float32(1.45) * s
    var sword = Vector3(-1, 0, 0)
    var ahead = Vector3(0, 0, 1)
    var up = Vector3(0, 1, 0)
    var degree = Float32(pi / 180)
    if move == LIGHT_ONE or move == LIGHT_TWO:
        # Across the front, at the chest.
        var y = Float32(0.35) if move == LIGHT_ONE else Float32(0.25)
        arc(
            sheet,
            Vector3(0, y * s, 0),
            sword,
            ahead,
            -15 * degree,
            165 * degree,
            inner,
            outer,
            color,
        )
    elif move == LIGHT_THREE:
        # Down the front, from over the head.
        arc(
            sheet,
            Vector3(-0.15 * s, 0.5 * s, 0.1 * s),
            up,
            ahead,
            -20 * degree,
            125 * degree,
            inner,
            outer,
            color,
        )
    elif move == HEAVY:
        # From high on the sword's side to low on the other.
        arc(
            sheet,
            Vector3(0, 0.4 * s, 0.1 * s),
            Vector3(-0.6, 0.8, 0),
            ahead,
            0,
            180 * degree,
            inner,
            outer * 1.05,
            color,
        )
    elif move == RISING_EDGE:
        # From low on the other side to high on the sword's.
        arc(
            sheet,
            Vector3(0, 0.3 * s, 0.1 * s),
            Vector3(0.6, -0.8, 0),
            ahead,
            0,
            180 * degree,
            inner,
            outer,
            color,
        )
    elif move == TEMPEST:
        # The last 150 degrees of the blade's turn at the waist, behind
        # the blade: `Trail.show` turns it with the body.
        arc(
            sheet,
            Vector3(0, 0.3 * s, 0),
            sword,
            ahead,
            -150 * degree,
            0,
            inner,
            outer * 1.1,
            color,
        )
    return sheet^


def slash_material(mut assets: Assets) raises -> MaterialId:
    """Return the material of trails and sparks: unlit, half clear, both
    faces drawn, colored by its vertices.

    Args:
        assets: The stores the material goes into.

    Returns:
        The material.

    Raises:
        Error: If the material cannot be made.
    """
    return assets.materials.add(
        Material(
            Color(255, 255, 255),
            side=DOUBLE_SIDE,
            opacity=0.55,
            transparent=True,
            kind=BASIC,
            vertex_colors=True,
        )
    )


struct Trail(Movable):
    """The ribbons of a body's attacks, and which one shows."""

    # The node of each attack's ribbon, by the move's value, or None.
    var ribbons: List[Optional[NodeId]]
    var shown: Int

    def __init__(
        out self,
        mut scene: Scene,
        mut assets: Assets,
        material: MaterialId,
        carrier: NodeId,
        scale: Float32,
        color: Vector3,
    ) raises:
        """Hang a hidden ribbon for each attack from a body's carrier.

        Args:
            scene: The scene.
            assets: The stores for the geometries.
            material: The trails' material: see `slash_material`.
            carrier: The node the body hangs from.
            scale: The fighter's height over six feet.
            color: The ribbons' color.

        Raises:
            Error: If a mesh cannot be added.
        """
        self.ribbons = List[Optional[NodeId]]()
        self.shown = -1
        for value in range(MOVES):  # pragma: no branch
            var move = CombatMove(value)
            if not is_attack(move):
                self.ribbons.append(None)
                continue
            var node = scene.attach(Object3D(), carrier)
            scene.node(node).visible = False
            var sheet = trail_sheet(move, scale, color)
            scene.add_mesh(
                Mesh(
                    assets.geometries.add(sheet.geometry()),
                    material,
                    node,
                    cast_shadow=False,
                    receive_shadow=False,
                )
            )
            self.ribbons.append(node)

    def show(mut self, mut scene: Scene, fighter: Fighter) raises:
        """Show the ribbon of the attack that strikes now, and hide the
        rest. The tempest's ribbon turns with the body.

        Args:
            scene: The scene the trail is in.
            fighter: The fighter whose body carries the trail.

        Raises:
            Error: Never: the move is one.
        """
        var want = -1
        if is_attack(fighter.move):
            var start = move_data(fighter.move).startup.to(SECOND)
            var begin = start * fighter.pace
            var end = fighter.active_end() + TRAIL_LINGER
            if fighter.clock >= begin and fighter.clock <= end:
                want = fighter.move.value
        if want == TEMPEST.value:
            var share = fighter.clock / fighter.length()
            scene.node(self.ribbons[want].value()).set_rotation_from_axis_angle(
                Vector3(0, 1, 0), Angle(-tempest_twist(share), DEGREE)
            )
        if want == self.shown:
            return
        if self.shown >= 0:
            scene.node(self.ribbons[self.shown].value()).visible = False
        if want >= 0:
            scene.node(self.ribbons[want].value()).visible = True
        self.shown = want


def spark_sheet() -> Sheet:
    """Return a burst of sparks about the origin: eight gold rays and a
    white core.

    Returns:
        The rays, each 25 centimeters long, pointing out at even angles,
        tilted up and down in turn.
    """
    var sheet = Sheet(1)
    for k in range(8):  # pragma: no branch
        var a = Float32(2 * pi) * Float32(k) / 8
        var lift = Float32(0.35) if k % 2 == 0 else Float32(-0.35)
        var ray = _unit(Vector3(cos(a), lift, sin(a)))
        var across = Vector3(-sin(a), 0, cos(a)) * 0.012
        var thin = _unit(_cross(ray, across)) * 0.012
        sheet.box(ray * 0.14, ray * 0.11, across, thin, Vector3(1.0, 0.8, 0.3))
    sheet.box(
        Vector3(0, 0, 0),
        Vector3(0.04, 0, 0),
        Vector3(0, 0.04, 0),
        Vector3(0, 0, 0.04),
        Vector3(1, 1, 0.9),
    )
    return sheet^


struct Sparks(Movable):
    """A few bursts of sparks, used in turn."""

    var nodes: List[NodeId]
    # How long each has shown, in seconds; `SPARK_SECONDS` or more is
    # hidden.
    var ages: List[Float32]
    var next: Int

    def __init__(
        out self, mut scene: Scene, mut assets: Assets, material: MaterialId
    ) raises:
        """Add `SPARKS` hidden bursts to a scene.

        Args:
            scene: The scene.
            assets: The stores for the geometry.
            material: The sparks' material: see `slash_material`.

        Raises:
            Error: If a mesh cannot be added.
        """
        self.nodes = List[NodeId]()
        self.ages = List[Float32]()
        self.next = 0
        var geometry = assets.geometries.add(spark_sheet().geometry())
        for _ in range(SPARKS):  # pragma: no branch
            var node = scene.add(Object3D())
            scene.node(node).visible = False
            scene.add_mesh(
                Mesh(
                    geometry,
                    material,
                    node,
                    cast_shadow=False,
                    receive_shadow=False,
                )
            )
            self.nodes.append(node)
            self.ages.append(SPARK_SECONDS)

    def burst(mut self, mut scene: Scene, at: Vector3) raises:
        """Show the oldest burst at a place.

        Args:
            scene: The scene the sparks are in.
            at: Where the blow lands.

        Raises:
            Error: Never: the nodes are the scene's.
        """
        ref node = scene.node(self.nodes[self.next])
        node.set_position(at.x, at.y, at.z)
        node.set_scale(0.5, 0.5, 0.5)
        node.visible = True
        self.ages[self.next] = 0
        self.next = (self.next + 1) % SPARKS

    def update(mut self, mut scene: Scene, delta: Duration) raises:
        """Grow each burst that shows, and hide each that has shown long
        enough.

        Args:
            scene: The scene the sparks are in.
            delta: The frame's time.

        Raises:
            Error: Never: the nodes are the scene's.
        """
        var seconds = delta.to(SECOND)
        for k in range(SPARKS):  # pragma: no branch
            if self.ages[k] >= SPARK_SECONDS:
                continue
            self.ages[k] += seconds
            ref node = scene.node(self.nodes[k])
            if self.ages[k] >= SPARK_SECONDS:
                node.visible = False
                continue
            var grow = 0.5 + 1.5 * self.ages[k] / SPARK_SECONDS
            node.set_scale(grow, grow, grow)
