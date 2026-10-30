# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What a sword leaves in the air: the trail of a swing, and the sparks
of a blow.

**Trails.** A `Trail` keeps one ribbon for each attack, on a node under a
body's carrier, so it turns with the body. A ribbon is the arc that a
blade's outer third sweeps, as the move's clip swings it: across at the
chest for the light cuts, down from over the head for the third, high to
low for the heavy cut, low to high for the rising edge, down the front
to the ground for the plunge, straight ahead
at the chest for a burst attack's thrust, and the last 150 degrees of the
tempest's turn, which turns with the body as the clip spins it. The
mystic arte's spins leave a wide ring that turns with the body too. A
burst attack's trail is red, whoever makes it, and a mystic arte's is
gold.

A trail is light, so `Trail.draw` adds it to the finished frame, as Tales
of Arise draws its swings. The game's renderer draws every surface
opaque, and could not. Through the move's active part, the ribbon grows
from its start to where the blade is, brightest at the blade and fading
behind it over `TRAIL_TAIL` of its length. After the active part it fades
away over `TRAIL_LINGER`.

**Waves.** `draw_wave` adds a demon fang's wave to the frame: an arch of
light across the way it runs, standing on the ground.

**Rings.** `draw_ring` adds a ring of light on the ground, as a plunge
slams it.

**Stars.** `glow_star` adds a star of light round a point of the frame,
as the red glow of a foe that winds up a burst attack.

**Sparks.** `Sparks` keeps `SPARKS` bursts of gold rays. A blow puts the
oldest at the place it lands; it grows and shows for `SPARK_SECONDS`.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.humanoid.rig.sword_clips import mystic_twist, tempest_twist
from extensions.village.combat import (
    BURST,
    DEMON_FANG,
    HEAVY,
    LIGHT_ONE,
    MYSTIC_ARTE,
    LIGHT_THREE,
    LIGHT_TWO,
    MOVES,
    PLUNGE,
    RISING_EDGE,
    TEMPEST,
    CombatMove,
    Fighter,
    is_attack,
    move_data,
)
from extensions.village.sheet import Sheet
from materials.material import BASIC, Material, MaterialId
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, Framebuffer
from std.math import cos, pi, sin
from units.si import DEGREE, SECOND, Angle, Duration

comptime TRAIL_LINGER = Float32(0.15)
"""How long a trail takes to fade after its move's active part, in
seconds."""
comptime TRAIL_TAIL = Float32(0.6)
"""The share of a ribbon behind the blade over which it fades."""
comptime TRAIL_STEPS = 18
"""How many quads an arc of a half turn takes."""
comptime NEAREST = Float32(0.2)
"""How far before the camera a trail's corner must be to be drawn, in
meters."""
comptime WAVE_INNER = Float32(0.35)
"""The inner radius of a demon fang's arch of light, in meters."""
comptime WAVE_OUTER = Float32(0.85)
"""The outer radius of a demon fang's arch of light, in meters."""
comptime SPARKS = 6
"""How many bursts of sparks can show at once."""
comptime SPARK_SECONDS = Float32(0.16)
"""How long a burst of sparks shows, in seconds."""
comptime PLAYER_TRAIL = Vector3(150, 205, 255)
"""The light the player's trails add, as sRGB bytes at the brightest."""
comptime FOE_TRAIL = Vector3(255, 120, 50)
"""The light a bandit's trails add: the orange of a threat."""
comptime OVER_TRAIL = Vector3(255, 215, 90)
"""The light the player's trails add Over Limit: gold."""
comptime MYSTIC_TRAIL = Vector3(170, 140, 60)
"""The light of a mystic arte's ring: a softer gold, since the ring is
wide."""
comptime BURST_TRAIL = Vector3(255, 40, 30)
"""The light of a burst attack: its trail, and its glow as it winds up."""
comptime RING_INNER = Float32(0.7)
"""A plunge's ring's inner radius, as a share of its outer one."""
comptime STAR_RAYS = 8
"""How many rays a star of light has."""


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


def arc_points(
    center: Vector3,
    first: Vector3,
    second: Vector3,
    begin: Float32,
    end: Float32,
    inner: Float32,
    outer: Float32,
) -> List[Vector3]:
    """Return the corners of a flat ribbon round a center, between two
    radii.

    A point of the arc at the angle `a` lies along `first` times `cos a`
    plus `second` times `sin a` from the center.

    Args:
        center: The arc's center.
        first: The way the angle zero points, of length one.
        second: The way a quarter turn points, of length one.
        begin: The angle the ribbon starts at, in radians.
        end: The angle it ends at, in radians.
        inner: Its inner radius, in meters.
        outer: Its outer radius, in meters.

    Returns:
        For each step from `begin` to `end`, the inner corner and then the
        outer one. A half turn takes `TRAIL_STEPS` steps, and any arc at
        least two.
    """
    var steps = max(2, Int(TRAIL_STEPS * abs(end - begin) / pi))
    var out = List[Vector3](capacity=2 * (steps + 1))
    for k in range(steps + 1):  # pragma: no branch
        var a = begin + (end - begin) * Float32(k) / Float32(steps)
        var d = first * cos(a) + second * sin(a)
        out.append(center + d * inner)
        out.append(center + d * outer)
    return out^


def trail_points(move: CombatMove, scale: Float32) -> List[Vector3]:
    """Return the ribbon an attack's blade sweeps, in a body's frame.

    The frame is a body carrier's: plus z forward, the sword on minus x,
    and the hips at the origin.

    Args:
        move: The attack. A move that is not an attack has no ribbon, and
            nor does a beast's bite.
        scale: The fighter's height over six feet.

    Returns:
        The ribbon's corners, as `arc_points` gives them, from 1.0 to 1.45
        meters round the sword's shoulder for a person of six feet; a
        straight ribbon from 0.4 to 2.6 meters ahead for a burst attack's
        thrust; none for a move that is not a cut.
    """
    var s = scale
    var inner = Float32(1.0) * s
    var outer = Float32(1.45) * s
    var sword = Vector3(-1, 0, 0)
    var ahead = Vector3(0, 0, 1)
    var degree = Float32(pi / 180)
    if move == LIGHT_ONE or move == LIGHT_TWO:
        # Across the front, at the chest: the first from the sword's side,
        # the second back to it.
        var y = Float32(0.35) if move == LIGHT_ONE else Float32(0.25)
        var begin = Float32(-15) if move == LIGHT_ONE else Float32(165)
        return arc_points(
            Vector3(0, y * s, 0),
            sword,
            ahead,
            begin * degree,
            (150 - begin) * degree,
            inner,
            outer,
        )
    if move == LIGHT_THREE:
        # Down the front, from over the head.
        return arc_points(
            Vector3(-0.15 * s, 0.5 * s, 0.1 * s),
            Vector3(0, 1, 0),
            ahead,
            -20 * degree,
            125 * degree,
            inner,
            outer,
        )
    if move == PLUNGE:
        # Down the front, from over the head to the ground.
        return arc_points(
            Vector3(-0.15 * s, 0.3 * s, 0.1 * s),
            Vector3(0, 1, 0),
            ahead,
            -20 * degree,
            150 * degree,
            inner,
            outer,
        )
    if move == HEAVY:
        # From high on the sword's side to low on the other.
        return arc_points(
            Vector3(0, 0.4 * s, 0.1 * s),
            Vector3(-0.6, 0.8, 0),
            ahead,
            0,
            180 * degree,
            inner,
            outer * 1.05,
        )
    if move == RISING_EDGE:
        # From low on the other side to high on the sword's.
        return arc_points(
            Vector3(0, 0.3 * s, 0.1 * s),
            Vector3(0.6, -0.8, 0),
            ahead,
            0,
            180 * degree,
            inner,
            outer,
        )
    if move == DEMON_FANG:
        # From low behind on the sword's side, along the ground, and up.
        return arc_points(
            Vector3(0, 0.2 * s, 0.1 * s),
            Vector3(-0.3, -0.95, 0),
            ahead,
            -30 * degree,
            120 * degree,
            inner,
            outer,
        )
    if move == BURST:
        # A thrust straight ahead at the chest, on the sword's side,
        # tilted so that it shows from behind and from the side.
        var line = List[Vector3]()
        for k in range(TRAIL_STEPS // 2 + 1):  # pragma: no branch
            var z = (0.4 + 2.2 * Float32(k) / Float32(TRAIL_STEPS // 2)) * s
            line.append(Vector3(-0.2 * s, 0.28 * s, z))
            line.append(Vector3(-0.04 * s, 0.44 * s, z))
        return line^
    if move == MYSTIC_ARTE:
        # The last 240 degrees of the blade's turn, out to the arte's
        # reach: `Trail.show` turns it with the body.
        return arc_points(
            Vector3(0, 0.3 * s, 0),
            sword,
            ahead,
            -240 * degree,
            0,
            inner,
            outer * 2.5,
        )
    if move == TEMPEST:
        # The last 150 degrees of the blade's turn at the waist, behind
        # the blade: `Trail.show` turns it with the body.
        return arc_points(
            Vector3(0, 0.3 * s, 0),
            sword,
            ahead,
            -150 * degree,
            0,
            inner,
            outer * 1.1,
        )
    return List[Vector3]()


def slash_material(mut assets: Assets) raises -> MaterialId:
    """Return the material of sparks: unlit, and colored by its vertices.

    Args:
        assets: The stores the material goes into.

    Returns:
        The material.

    Raises:
        Error: If the material cannot be made.
    """
    return assets.materials.add(
        Material(Color(255, 255, 255), kind=BASIC, vertex_colors=True)
    )


def glow_triangle(
    mut frame: Framebuffer,
    a: Vector3,
    b: Vector3,
    c: Vector3,
    color: Vector3,
):
    """Add light over a triangle of the frame, as three.js's additive
    blending does.

    Args:
        frame: The frame.
        a: A corner: its x and y are pixels, its z how much of the light
            it adds, from 0 to 1.
        b: The next corner, either way round.
        c: The last corner.
        color: The light at a share of one, as sRGB bytes.
    """
    var area = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    if abs(area) < 1.0e-6:
        return
    var x0 = max(0, Int(min(a.x, min(b.x, c.x))))
    var x1 = min(frame.width - 1, Int(max(a.x, max(b.x, c.x))) + 1)
    var y0 = max(0, Int(min(a.y, min(b.y, c.y))))
    var y1 = min(frame.height - 1, Int(max(a.y, max(b.y, c.y))) + 1)
    for y in range(y0, y1 + 1):
        var py = Float32(y) + 0.5
        for x in range(x0, x1 + 1):
            var px = Float32(x) + 0.5
            var wa = ((b.x - px) * (c.y - py) - (b.y - py) * (c.x - px)) / area
            var wb = ((c.x - px) * (a.y - py) - (c.y - py) * (a.x - px)) / area
            var wc = 1 - wa - wb
            if wa < 0 or wb < 0 or wc < 0:
                continue
            var share = wa * a.z + wb * b.z + wc * c.z
            var at = (y * frame.width + x) * 4
            var light: List[Float32] = [color.x, color.y, color.z]
            for k in range(3):  # pragma: no branch
                var lit = Float32(frame.pixels[at + k]) + light[k] * share
                frame.pixels[at + k] = UInt8(Int(min(Float32(255), lit)))


def glow_star(
    mut frame: Framebuffer,
    center: Vector3,
    radius: Float32,
    color: Vector3,
):
    """Add a star of light to a frame: `STAR_RAYS` rays round a point,
    brightest at the point.

    Args:
        frame: The frame.
        center: The star's middle: its x and y are pixels, and its z how
            much of the light it adds there, from 0 to 1.
        radius: How far its rays reach, in pixels.
        color: The light at a share of one, as sRGB bytes.
    """
    var half = Float32(pi) / Float32(STAR_RAYS)
    var waist = radius * 0.35
    var dim = center.z * 0.4
    for k in range(STAR_RAYS):  # pragma: no branch
        var a = 2 * half * Float32(k)
        var tip = Vector3(
            center.x + radius * cos(a), center.y + radius * sin(a), 0
        )
        var left = Vector3(
            center.x + waist * cos(a - half),
            center.y + waist * sin(a - half),
            dim,
        )
        var right = Vector3(
            center.x + waist * cos(a + half),
            center.y + waist * sin(a + half),
            dim,
        )
        glow_triangle(frame, center, left, tip, color)
        glow_triangle(frame, center, tip, right, color)


struct Trail(Movable):
    """The ribbons of a body's attacks, and how much of which one shows."""

    # The node of each attack's ribbon, by the move's value, or None; and
    # its corners in the node's frame.
    var nodes: List[Optional[NodeId]]
    var ribbons: List[List[Vector3]]
    # The light the trail adds, as sRGB bytes at the brightest.
    var color: Vector3
    # The attack whose ribbon shows, or -1; how far along its arc the blade
    # is, from 0 to 1; and how bright it is, from 0 to 1.
    var shown: Int
    var sweep: Float32
    var glow: Float32

    def __init__(
        out self,
        mut scene: Scene,
        carrier: NodeId,
        scale: Float32,
        color: Vector3,
    ) raises:
        """Hang a node for each attack's ribbon from a body's carrier.

        Args:
            scene: The scene.
            carrier: The node the body hangs from.
            scale: The fighter's height over six feet.
            color: The light the trail adds, as sRGB bytes.

        Raises:
            Error: If a node cannot be added.
        """
        self.nodes = List[Optional[NodeId]]()
        self.ribbons = List[List[Vector3]]()
        self.color = color
        self.shown = -1
        self.sweep = 0
        self.glow = 0
        for value in range(MOVES):  # pragma: no branch
            var move = CombatMove(value)
            self.ribbons.append(trail_points(move, scale))
            if not is_attack(move):
                self.nodes.append(None)
                continue
            self.nodes.append(scene.attach(Object3D(), carrier))

    def show(mut self, mut scene: Scene, fighter: Fighter) raises:
        """Show the ribbon of the attack that strikes now, as far as the
        blade has swept it; and the tempest's, turned with the body.

        Args:
            scene: The scene the trail is in.
            fighter: The fighter whose body carries the trail.

        Raises:
            Error: Never: the move is one.
        """
        self.shown = -1
        if not is_attack(fighter.move):
            return
        var data = move_data(fighter.move)
        var begin = data.startup.to(SECOND) * fighter.pace
        var end = fighter.active_end()
        if fighter.clock < begin or fighter.clock > end + TRAIL_LINGER:
            return
        self.shown = fighter.move.value
        self.sweep = min(Float32(1), (fighter.clock - begin) / (end - begin))
        self.glow = min(Float32(1), 1 - (fighter.clock - end) / TRAIL_LINGER)
        if fighter.move == TEMPEST:
            # The ribbon trails the blade all through the spin.
            self.sweep = 1
            var share = fighter.clock / fighter.length()
            scene.node(
                self.nodes[TEMPEST.value].value()
            ).set_rotation_from_axis_angle(
                Vector3(0, 1, 0), Angle(-tempest_twist(share), DEGREE)
            )
        if fighter.move == MYSTIC_ARTE:
            self.sweep = 1
            var share = fighter.clock / fighter.length()
            scene.node(
                self.nodes[MYSTIC_ARTE.value].value()
            ).set_rotation_from_axis_angle(
                Vector3(0, 1, 0), Angle(-mystic_twist(share), DEGREE)
            )

    def draw(
        self,
        mut frame: Framebuffer,
        scene: Scene,
        camera: PerspectiveCamera,
        look: Vector3,
    ) raises:
        """Add the ribbon that shows to a finished frame.

        Each quad behind the blade adds less light, down to none
        `TRAIL_TAIL` of the ribbon behind it. A quad with a corner less
        than `NEAREST` before the camera is not drawn.

        Args:
            frame: The frame, the camera's size.
            scene: The scene, updated, that the trail is in.
            camera: The camera the frame was drawn from.
            look: The way the camera looks, of length one.

        Raises:
            Error: If the camera or the frame's size is not valid.
        """
        if self.shown < 0:
            return
        var place = scene.world_matrix(self.nodes[self.shown].value())
        ref corners = self.ribbons[self.shown]
        var steps = len(corners) // 2 - 1
        var placed = List[Vector3](capacity=len(corners))
        for k in range(len(corners)):  # pragma: no branch
            placed.append(place.transform_point(corners[k]))
        # How much light each step adds: most at the blade, none ahead of
        # it.
        var light = List[Float32]()
        for k in range(steps + 1):  # pragma: no branch
            var t = Float32(k) / Float32(steps)
            if t > self.sweep + 1.0e-4:
                break
            var share = max(Float32(0), 1 - (self.sweep - t) / TRAIL_TAIL)
            light.append(share * self.glow)
        var color = self.color
        if self.shown == BURST.value:
            color = BURST_TRAIL
        elif self.shown == MYSTIC_ARTE.value:
            color = MYSTIC_TRAIL
        glow_ribbon(frame, camera, look, placed, light, color)


def glow_ribbon(
    mut frame: Framebuffer,
    camera: PerspectiveCamera,
    look: Vector3,
    corners: List[Vector3],
    light: List[Float32],
    color: Vector3,
) raises:
    """Add a ribbon's light to a frame, quad by quad.

    Args:
        frame: The frame, the camera's size.
        camera: The camera the frame was drawn from.
        look: The way the camera looks, of length one.
        corners: The ribbon's corners in world space: an inner corner and
            an outer one for each step, as `arc_points` gives them.
        light: How much light the outer corners of each step add, from 0
            to 1; the inner corners add half as much. The ribbon is drawn
            as far as the steps that this lists.
        color: The light at a share of one, as sRGB bytes.

    Raises:
        Error: If the camera or the frame's size is not valid. A ribbon
            with a corner less than `NEAREST` before the camera is not
            drawn.
    """
    var pixels = List[Vector3](capacity=len(corners))
    for p in corners:  # pragma: no branch
        var off = p - camera.position
        if off.x * look.x + off.y * look.y + off.z * look.z < NEAREST:
            return
        pixels.append(camera.project(p, frame.width, frame.height))
    for k in range(len(light) - 1):
        var s0 = light[k]
        var s1 = light[k + 1]
        var i0 = pixels[2 * k]
        var o0 = pixels[2 * k + 1]
        var i1 = pixels[2 * k + 2]
        var o1 = pixels[2 * k + 3]
        var a = Vector3(i0.x, i0.y, s0 * 0.5)
        var b = Vector3(o0.x, o0.y, s0)
        var c = Vector3(o1.x, o1.y, s1)
        var d = Vector3(i1.x, i1.y, s1 * 0.5)
        glow_triangle(frame, a, b, c, color)
        glow_triangle(frame, a, c, d, color)


def draw_wave(
    mut frame: Framebuffer,
    camera: PerspectiveCamera,
    look: Vector3,
    at: Vector3,
    way: Vector3,
    glow: Float32,
) raises:
    """Add a demon fang's wave to a frame: an arch of light standing on
    the ground across the way it runs, brightest at its top.

    Args:
        frame: The frame, the camera's size.
        camera: The camera the frame was drawn from.
        look: The way the camera looks, of length one.
        at: The middle of the wave's foot.
        way: The way it runs, of length one.
        glow: How bright it is, from 0 to 1.

    Raises:
        Error: If the camera or the frame's size is not valid.
    """
    var across = Vector3(-way.z, 0, way.x)
    var corners = arc_points(
        at, across, Vector3(0, 1, 0), 0, Float32(pi), WAVE_INNER, WAVE_OUTER
    )
    var steps = len(corners) // 2 - 1
    var light = List[Float32]()
    for k in range(steps + 1):  # pragma: no branch
        light.append(sin(Float32(pi) * Float32(k) / Float32(steps)) * glow)
    glow_ribbon(frame, camera, look, corners, light, PLAYER_TRAIL)


def draw_ring(
    mut frame: Framebuffer,
    camera: PerspectiveCamera,
    look: Vector3,
    center: Vector3,
    radius: Float32,
    glow: Float32,
) raises:
    """Add a ring of light on the ground to a frame, as a plunge slams it.

    Args:
        frame: The frame, the camera's size.
        camera: The camera the frame was drawn from.
        look: The way the camera looks, of length one.
        center: The ring's middle, on the ground.
        radius: Its outer radius, in meters; its inner one is
            `RING_INNER` of it.
        glow: How bright it is, from 0 to 1.

    Raises:
        Error: If the camera or the frame's size is not valid.
    """
    var corners = arc_points(
        center,
        Vector3(1, 0, 0),
        Vector3(0, 0, 1),
        0,
        Float32(2 * pi),
        radius * RING_INNER,
        radius,
    )
    var light = List[Float32](length=len(corners) // 2, fill=glow)
    glow_ribbon(frame, camera, look, corners, light, PLAYER_TRAIL)


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
