# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A skirt's hem that swings as the person moves.

A skirt is skinned to the hips and the thighs, so it follows them
stiffly: it does not lag as a person starts to run, or swing on as they
stop. `Sway` gives the hem that swing, with no cloth to simulate:

1. **The shapes.** `add_sway_targets` adds four morph targets to each
   piece of a skirted garment: the hem moved forward, back, right and
   left, in the body's frame. A vertex moves by the square of how far it
   lies down the skirt, from none at `skirt_top` to `SWAY_REACH` at the
   hem. So the waist stays, and the hem swings most.
2. **The spring.** `Sway.step` keeps the hem's offset in the body's frame
   on a damped spring. The spring pulls the offset toward a rest that the
   body's motion sets. As the body speeds up, the rest lies behind the
   motion by `SWAY_LAG` for each meter a second squared. As it moves, the
   air holds the hem back by `SWAY_DRAG` for each meter a second. So the
   hem trails a run, kicks forward as the runner stops, and settles.
3. **The weights.** `sway_weights` turns the offset into the four
   targets' weights, each from 0 to 1.
4. **The flare.** A fifth target moves the hem out from the body's axis,
   and a little up. `Sway.flare` follows the body's spin, by `FLARE_SPIN`
   for each radian a second, and its fall, by `FLARE_FALL` for each
   meter a second: a whirlwind spreads the skirt, and so does a jump as
   it comes down.

The offset is held within `SWAY_REACH`. The game's renderer applies the
targets before the bones, so the swing turns with the hips.

This is not a three.js port. See Extensions.

    var sway = Sway()
    var offset = sway.step(at, turn, seconds)
    var weights = sway_weights(offset, SWAY_REACH)
"""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import POSITION, BufferGeometry
from core.scene import Scene
from math.vector3 import Vector3
from std.math import cos, floor, pi, sin, sqrt

comptime SWAY_REACH = Float32(0.09)
"""How far the hem swings at most, in meters on a person of six feet."""
comptime SWAY_STIFFNESS = Float32(55)
"""How hard the spring pulls the hem toward its rest, per second
squared: it swings about once a second."""
comptime SWAY_DAMPING = Float32(4.5)
"""How fast the spring's swing dies, per second."""
comptime SWAY_LAG = Float32(0.012)
"""How far the hem's rest lies behind the body's speeding up, in meters
for each meter a second squared."""
comptime SWAY_DRAG = Float32(0.01)
"""How far the air holds the hem back, in meters for each meter a
second."""
comptime FLARE_TARGET = 4
"""The place of the flare among a skirt's targets."""
comptime FLARE_LIFT = Float32(0.4)
"""How far up the hem rises as it flares, as a share of how far out."""
comptime FLARE_SPIN = Float32(0.12)
"""How much the hem flares for each radian a second the body turns."""
comptime FLARE_FALL = Float32(0.15)
"""How much the hem flares for each meter a second the body falls."""
comptime FLARE_EASE = Float32(8)
"""How fast the flare follows what the body does, per second."""
comptime SWAY_LONGEST = Float32(0.1)
"""The longest step the spring takes at once, in seconds: a longer frame
is taken in steps no longer than this, so the spring stays steady."""


def add_sway_targets(
    mut geometry: BufferGeometry, top: Float32, reach: Float32
) raises -> Bool:
    """Add the five targets that swing and flare a skirt's hem to a
    garment's piece.

    Each of the first four targets moves every vertex below `top` along
    one way of the body's frame: +x, -x, +z and -z. A vertex moves by
    `reach` times the square of how far it lies from `top` to the piece's
    lowest vertex. The fifth, the flare, moves it as far out from the
    body's axis, and `FLARE_LIFT` of that up. The targets are relative:
    they hold how far each vertex moves.

    Args:
        geometry: A piece of a skirted garment, in the body's frame. It is
            changed.
        top: The height the skirt hangs from, in meters.
        reach: How far the lowest vertex moves at full weight, in meters.

    Returns:
        True if the targets were added. A piece with no vertex below
        `top`, or one that wears morph targets already, is left alone.

    Raises:
        Error: If the piece has no positions, or the reach is not from 0
            to a meter.
    """
    if not (reach >= 0 and reach <= 1):
        raise Error("A hem's reach must be from 0 to a meter")
    if geometry.morph_count() > 0:
        return False
    ref points = geometry.attribute_view(String(POSITION))
    var count = points.count()
    var hem = top
    for v in range(count):  # pragma: no branch
        hem = min(hem, points.vector3(v).y)
    if not (hem < top):
        return False
    var reaches = List[Float32](length=count, fill=0)
    for v in range(count):  # pragma: no branch
        var fall = max(Float32(0), (top - points.vector3(v).y) / (top - hem))
        reaches[v] = reach * fall * fall
    # The flare: each vertex out from the body's axis, and a little up.
    var flared = List[Float32](capacity=3 * count)
    for v in range(count):  # pragma: no branch
        var p = points.vector3(v)
        var out = sqrt(p.x * p.x + p.z * p.z)
        var spread = reaches[v] / max(out, Float32(1.0e-6))
        flared.append(p.x * spread)
        flared.append(reaches[v] * FLARE_LIFT)
        flared.append(p.z * spread)
    geometry.morph_relative = True
    var ways: List[Vector3] = [
        Vector3(1, 0, 0),
        Vector3(-1, 0, 0),
        Vector3(0, 0, 1),
        Vector3(0, 0, -1),
    ]
    for w in range(4):  # pragma: no branch
        var moved = List[Float32](capacity=3 * count)
        for v in range(count):  # pragma: no branch
            moved.append(ways[w].x * reaches[v])
            moved.append(0)
            moved.append(ways[w].z * reaches[v])
        geometry.add_morph_target(BufferAttribute(moved^, 3), name=sway_name(w))
    geometry.add_morph_target(
        BufferAttribute(flared^, 3), name=sway_name(FLARE_TARGET)
    )
    return True


def sway_skirts(
    mut scene: Scene,
    mut assets: Assets,
    parts: List[Int],
    top: Float32,
    reach: Float32,
) raises -> List[Int]:
    """Give each part of a skirted garment the targets that swing its hem.

    Args:
        scene: The scene the parts are in.
        assets: The stores of their geometry. A part's geometry is
            replaced by one that wears the targets.
        parts: The garment's skinned meshes in `scene.skinned_meshes`.
        top: The height the skirt hangs from, in meters.
        reach: How far the hem swings at most, in meters.

    Returns:
        The parts that took the targets: see `add_sway_targets`.

    Raises:
        Error: If a part is not in the scene, or the reach is not from 0
            to a meter.
    """
    var swung = List[Int]()
    for mesh in parts:
        var id = scene.skinned_meshes[mesh].geometry
        var piece = assets.geometries.get(id).clone()
        if not add_sway_targets(piece, top, reach):
            continue
        scene.skinned_meshes[mesh].update_morph_targets(piece)
        assets.geometries.replace(id, piece^)
        swung.append(mesh)
    return swung^


def sway_name(way: Int) -> String:
    """Return the name of one of the four targets.

    Args:
        way: The target, from 0 to 4: +x, -x, +z, -z and the flare.

    Returns:
        `sway+x`, `sway-x`, `sway+z`, `sway-z` or `sway-flare`; `sway` for
        any other.
    """
    if way == 0:
        return "sway+x"
    if way == 1:
        return "sway-x"
    if way == 2:
        return "sway+z"
    if way == 3:
        return "sway-z"
    if way == FLARE_TARGET:
        return "sway-flare"
    return "sway"


def sway_weights(offset: Vector3, reach: Float32) -> List[Float32]:
    """Return the four targets' weights for a hem's offset.

    Args:
        offset: The hem's offset in the body's frame, in meters; its y is
            not read.
        reach: How far the hem moves at a weight of one, in meters.

    Returns:
        The weights of +x, -x, +z and -z, each from 0 to 1. A reach of
        zero gives none.
    """
    var weights = List[Float32](length=4, fill=0)
    if reach <= 0:
        return weights^
    weights[0] = min(Float32(1), max(Float32(0), offset.x / reach))
    weights[1] = min(Float32(1), max(Float32(0), -offset.x / reach))
    weights[2] = min(Float32(1), max(Float32(0), offset.z / reach))
    weights[3] = min(Float32(1), max(Float32(0), -offset.z / reach))
    return weights^


struct Sway(Copyable, Movable):
    """A hem's swing: its offset and speed in the body's frame, and the
    body's place and velocity at the last step."""

    var offset: Vector3
    var speed: Vector3
    var last_at: Vector3
    var last_velocity: Vector3
    # How far the hem flares, from 0 to 1, and the body's turn at the last
    # step, in radians.
    var flare: Float32
    var last_turn: Float32
    # Whether a step has been taken: the first step only learns where the
    # body stands.
    var primed: Bool

    def __init__(out self):
        """Create a hem at rest, on a body that has not moved yet."""
        self.offset = Vector3(0, 0, 0)
        self.speed = Vector3(0, 0, 0)
        self.last_at = Vector3(0, 0, 0)
        self.last_velocity = Vector3(0, 0, 0)
        self.flare = 0
        self.last_turn = 0
        self.primed = False

    def step(
        mut self, at: Vector3, turn: Float32, seconds: Float32, reach: Float32
    ) -> Vector3:
        """Move the hem on by one frame of the body's motion.

        Args:
            at: Where the body stands, in world space.
            turn: How far the body is turned about +y, in radians: its
                frame's +z faces that way.
            seconds: The frame's time. A frame of no time leaves the hem
                as it is.
            reach: How far the hem may swing, in meters.

        Returns:
            The hem's offset in the body's frame, in meters, within
            `reach` of rest.
        """
        if not self.primed or seconds <= 0:
            if not self.primed:
                self.last_at = at
                self.last_turn = turn
                self.primed = True
            return self.offset
        var velocity = (at - self.last_at) / seconds
        var speeding = (velocity - self.last_velocity) / seconds
        self.last_at = at
        self.last_velocity = velocity
        # The hem flares as the body spins and as it falls. A turn is
        # taken the short way round.
        var turned = turn - self.last_turn
        turned -= 2 * Float32(pi) * floor(turned / (2 * Float32(pi)) + 0.5)
        self.last_turn = turn
        var goal = min(
            Float32(1),
            abs(turned) / seconds * FLARE_SPIN
            + max(Float32(0), -velocity.y) * FLARE_FALL,
        )
        self.flare += (goal - self.flare) * min(
            Float32(1), seconds * FLARE_EASE
        )
        # Into the body's frame: turned back by its turn about +y.
        var c = cos(turn)
        var s = sin(turn)
        var v = Vector3(
            velocity.x * c - velocity.z * s, 0, velocity.x * s + velocity.z * c
        )
        var a = Vector3(
            speeding.x * c - speeding.z * s, 0, speeding.x * s + speeding.z * c
        )
        var rest = (a * SWAY_LAG + v * SWAY_DRAG) * -1
        var left = seconds
        while left > 0:
            var dt = min(left, SWAY_LONGEST)
            var pull = (rest - self.offset) * SWAY_STIFFNESS
            self.speed = self.speed + (pull - self.speed * SWAY_DAMPING) * dt
            self.offset = self.offset + self.speed * dt
            left -= dt
        var length = sqrt(
            self.offset.x * self.offset.x + self.offset.z * self.offset.z
        )
        var bound = max(reach, Float32(0))
        if length > bound:
            self.offset = self.offset * (bound / length)
            self.speed = self.speed * Float32(0.5)
        return self.offset
