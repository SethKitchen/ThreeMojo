# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The people and the animals of the village, and how each one moves.

Every resident is a `Character`, as the player is, so the ground, the
walls, the trees and the pond stop them all alike, and they bump into one
another. A `Route` steers each one: it walks to a point, rests there a
while, and walks on to the next. A villager with a home visits it: after
its wander, it walks to the front of its house's door, goes in, rests
inside, and comes back out. The door opens as it comes near.

**People.** A `Body` is a game humanoid on a skeleton, dressed in its
`Outfit`, with its idle, walk, run and jump clips in an `AnimationMixer`.
Each garment is a skinned mesh on the same skeleton, so the clothes move
with the body. Each frame it stands where its
character stands, turns the way it faces, and fades to the clip of its
`Stance`. The walk and the run play faster or slower with the speed, so
the feet keep pace with the ground. The player is a `Body` too.

**Animals.** An animal is meshed once for each of `phases` poses of its
walk, and once standing: a flipbook. Each frame its mesh shows the pose of
how far it has walked, so a stride covers one stride of ground. Each
`Herd` grazes around its own pasture. A species that does not walk on four
legs keeps its standing mesh. A shy herd runs from the player, at
`FLEE_PACE` times its walk, while the player is nearer than its `flee`.
"""

from animation.animation_mixer import ONCE, AnimationAction, AnimationMixer
from core.assets import Assets
from extensions.attire.kinds import CLOSED, SKIRTED
from extensions.attire.outfit import Outfit, dress
from extensions.attire.skirt import skirt_top
from core.geometry_store import GeometryId
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.anatomy.locomotion import WALK_FROUDE, stride_frequency
from extensions.animals.build import (
    Animal,
    animal_materials,
    create_animal,
    mesh_animal,
)
from extensions.animals.rig import Pose
from core.buffer_geometry import BufferGeometry
from render.framebuffer import Color
from render.tasks import TaskGroup
from extensions.animals.gait import is_quadruped, walk_pose, walk_stride
from extensions.animals.options import CROWD, Quality, animal_options
from extensions.animals.registry import SpeciesId, require_species
from extensions.humanoid.rig.clips import (
    idle_clip,
    jump_clip,
    run_clip,
    sit_clip,
    walk_clip,
    work_clip,
)
from extensions.humanoid.rig.game import GameHumanoid, add_game_humanoid
from extensions.humanoid.rig.joints import RIGHT_SHIN, RIGHT_TOES
from extensions.humanoid.skeleton.head.hair.beard import (
    CLEAN_SHAVEN,
    Beard,
)
from extensions.humanoid.skeleton.head.hair.styles import GROWN, HairStyle
from extensions.humanoid.spec import HumanoidSpec
from renderers.renderer import available_workers
from extensions.vegetation.checks import require_between, require_count_between
from extensions.vegetation.ground import Ground, Lot
from extensions.vegetation.noise import hash01
from extensions.village.sway import (
    SWAY_REACH,
    Sway,
    sway_skirts,
    sway_weights,
)
from extensions.village.faces import FACE_TRIANGLES, FaceLife
from extensions.village.clothes import Groom, plain_groom
from extensions.village.interior import Doorway
from core.ordinal import ordinal_valid
from extensions.village.terrain import Terrain
from extensions.village.character import (
    AIRBORNE,
    RUNNING,
    STANDING,
    WALKING,
    Character,
    CharacterParameters,
    MoveInput,
    Obstacle,
    Stance,
    no_input,
)
from controls.third_person_controls import turn_toward, yaw_of
from materials.material import MaterialId
from math.vector3 import Vector3
from objects.mesh import Mesh
from std.math import cos, floor, isnan, nan, pi, sin, sqrt
from units.measure import length_meters
from units.si import (
    METER,
    METER_PER_SECOND,
    RADIAN,
    SECOND,
    Angle,
    Duration,
    Length,
    Velocity,
)

comptime FADE = Duration(0.2, SECOND)
"""How long one clip takes to fade into the next."""
comptime WALK_PACE = Float32(1.4)
"""The speed, in meters a second, at which the walk clip plays at its own
rate."""
comptime RUN_PACE = Float32(4.5)
"""The speed, in meters a second, at which the run clip plays at its own
rate."""
comptime SLOWEST_PLAY = Float32(0.6)
"""The slowest rate a walk or a run plays at."""
comptime FASTEST_PLAY = Float32(1.6)
"""The fastest rate a walk or a run plays at."""
comptime JUMP_TAKEOFF = Float32(0.4)
"""The share of the jump clip at which its feet leave the ground. A jump
plays from there, since the crouch before it is already over."""
comptime JUMP_PLAY = Float32(0.7)
"""The rate the jump clip plays at, so its flight lasts as long as a jump
does."""
comptime SOLE = Float32(0.02)
"""How far the sole is below the toes' joint, in meters for a person of
six feet."""
comptime EYE_HEIGHT = Float32(0.93)
"""How far up a person's height their eyes are."""
comptime FACE_SPEED = Float32(4)
"""How fast a held person turns to face their point, in radians a
second."""
comptime ARRIVED = Float32(0.6)
"""How near a point a resident must come, in meters, to have reached it."""
comptime STALL_SPEED = Float32(0.1)
"""A resident that walks slower than this, in meters a second, is stuck."""
comptime SIDESTEP = Float32(0.6)
"""How long a resident stays stuck, in seconds, before it walks aside."""
comptime DETOUR = Float32(1.2)
"""How long a stuck resident walks aside, in seconds."""
comptime ACTIVITY_REST = Float32(4)
"""How many rests long a person sits or works at a stop."""
comptime TURN_STEP = Float32(0.35)
"""How far an animal's feet step, in meters, for each radian it turns on
the spot."""
comptime TURNING = Float32(0.5)
"""How fast an animal must turn, in radians a second, for its feet to step
as it turns on the spot."""
comptime STOP_REACH = Float32(14)
"""How far from the middle of where a person wanders a stop can be, in
meters, for them to stop at it."""
comptime FOLLOW_REACH = Float32(30)
"""How near a player must be, in meters, for a dog to follow them."""
comptime HEEL = Float32(2.5)
"""How near the player a following dog keeps, in meters."""
comptime PANIC = Float32(9)
"""How near a foe must be, in meters, for a person or an animal to run
from it."""
comptime DETOURS = 4
"""How many times a resident walks round something on its way to a point
before it gives up on the point, rests, and walks on to the next."""
comptime APPROACH = Float32(3.2)
"""How far in front of its door a villager stops before it goes in, in
meters."""
comptime THRESHOLD = Float32(1.0)
"""How far in front of its door a villager steps last before it goes in,
and first after it comes out, in meters."""
comptime INDOORS = Float32(1.8)
"""How far behind its door a villager rests inside, in meters."""
comptime FLEE_PACE = Float32(3)
"""How many times its walking speed an animal runs when it flees."""
comptime TRIES = 8
"""How many places `wander_route` tries for each point before it gives
up on that point."""


def clip_of(stance: Stance) -> Int:
    """Return the clip a stance plays, by its place in a `Body`'s actions.

    Args:
        stance: The stance.

    Returns:
        0 for the idle clip, 1 for the walk, 2 for the run and 3 for the
        jump.
    """
    if stance == WALKING:
        return 1
    if stance == RUNNING:
        return 2
    if stance == AIRBORNE:
        return 3
    return 0


def play_rate(stance: Stance, speed: Velocity) -> Float32:
    """Return the rate a stance's clip plays at, for a speed.

    Args:
        stance: The stance.
        speed: How fast the character moves over the ground.

    Returns:
        For a walk or a run, the speed over the clip's own pace, from
        `SLOWEST_PLAY` to `FASTEST_PLAY`. `JUMP_PLAY` for a jump, and 1 for
        standing.
    """
    var meters = speed.to(METER_PER_SECOND)
    if stance == WALKING:
        return min(FASTEST_PLAY, max(SLOWEST_PLAY, meters / WALK_PACE))
    if stance == RUNNING:
        return min(FASTEST_PLAY, max(SLOWEST_PLAY, meters / RUN_PACE))
    if stance == AIRBORNE:
        return JUMP_PLAY
    return 1


comptime FLASH_GLOW = Color(255, 244, 228)
"""The color a body glows as a blow lands on it."""
comptime FLASH_STRENGTH = Float32(0.12)
"""How strongly a body glows as a blow lands on it."""


def facing_turn(heading: Angle) -> Angle:
    """Return how far to turn a model about +y so it faces a heading.

    A humanoid and an animal are built facing +z. A heading of 0 faces -z.

    Args:
        heading: The way to face, as a yaw.

    Returns:
        The heading plus half a turn.
    """
    return Angle(heading.to(RADIAN) + pi, RADIAN)


def hobbles(outfit: Outfit) raises -> Bool:
    """Return whether an outfit has a closed skirt that falls past the
    knees, as a robe or a gown does.

    A leg that kicks in such a skirt would pass out through its front,
    so its wearer does not kick: see `Arms`.

    Args:
        outfit: The outfit.

    Returns:
        Whether a skirted garment closed all round covers the shins. A
        neckline does not part the skirt, so it does not count.

    Raises:
        Error: Never: each joint is named.
    """
    for garment in outfit.garments:
        if (
            garment.form == SKIRTED
            and garment.opening == CLOSED
            and garment.cover.covers(RIGHT_SHIN)
        ):
            return True
    return False


struct Body(Movable):
    """A person's skinned body, its clothes, its clips, and the node that
    carries it."""

    var person: GameHumanoid
    # Each garment's skinned mesh in `scene.skinned_meshes`, or -1 for a
    # garment that draws nothing.
    var garments: List[Int]
    # The node the humanoid hangs from. It stands at the feet.
    var carrier: NodeId
    var mixer: AnimationMixer
    # The idle, walk, run, jump, sit and work actions, in that order.
    var actions: List[Int]
    # The stance whose clip plays.
    var playing: Stance
    var clip: Int
    """The place in `actions` of the clip that plays."""
    # How far the humanoid's origin is above its soles, in meters.
    var lift: Float32
    # Whether the person speaks: whether its face moves. Its face's
    # blinks, words and expression, and whether the preserved face shows.
    var speaks: Bool
    var life: FaceLife
    var near: Bool
    # Whether a closed skirt falls past the knees: see `hobbles`.
    var hobbled: Bool
    # The skinned meshes of the skirts whose hems swing, how far they
    # swing, and the swing: see `extensions.village.sway`.
    var skirts: List[Int]
    var sway_reach: Float32
    var sway: Sway
    # Each skinned mesh of the skin and the clothes, its own material,
    # and a copy of it that glows white: a blow flashes the body.
    var flashing: List[Int]
    var rest_looks: List[MaterialId]
    var flash_looks: List[MaterialId]
    var flashed: Bool

    def __init__(
        out self,
        mut scene: Scene,
        mut assets: Assets,
        spec: HumanoidSpec,
        outfit: Outfit,
        triangles: Int,
        detail: Int,
        speaks: Bool = False,
        seed: Int = 0,
        hair: HairStyle = GROWN,
        beard: Beard = CLEAN_SHAVEN,
    ) raises:
        """Build a person into a scene, dressed and standing at the origin.

        The skin, the hair and the beard are meshed on every core there is.

        Args:
            scene: The scene.
            assets: The stores.
            spec: The person.
            outfit: What the person wears. An empty outfit leaves them
                bare.
            triangles: The skin's budget of triangles.
            detail: The cells along the body's skin, from 8 to 64. The
                hands and the hair take half as many, and at least 8.
            speaks: Whether the person's face moves: it keeps the
                preserved face, teeth and tongue, and a still face of
                `FACE_TRIANGLES` for a distance, over the budget. See
                `extensions.village.faces`.
            seed: Which times the face blinks at.
            hair: How the hair is cut and laid.
            beard: The facial hair. A speaking face's beard moves with
                its mouth.

        Raises:
            Error: If the humanoid cannot be built, or the outfit does not
                check.
        """
        self.carrier = scene.add(Object3D())
        var half = max(8, detail // 2)
        self.speaks = speaks
        self.life = FaceLife(seed)
        self.near = False
        self.hobbled = hobbles(outfit)
        if speaks:
            self.person = add_game_humanoid(
                scene,
                assets,
                self.carrier,
                spec,
                triangles + FACE_TRIANGLES,
                detail=detail,
                hand_detail=half,
                hair_detail=half,
                facial_animation=True,
                face_stand_in=FACE_TRIANGLES,
                hair_style=hair,
                beard=beard,
                workers=available_workers(),
            )
            # The face is checked once: each frame only sets its weights.
            self.person.face.value().validate(scene, assets)
            self.person.show_face(scene, False)
        else:
            self.person = add_game_humanoid(
                scene,
                assets,
                self.carrier,
                spec,
                triangles,
                detail=detail,
                hand_detail=half,
                hair_detail=half,
                hair_style=hair,
                beard=beard,
                workers=available_workers(),
            )
        # A person casts a shadow, as an animal does.
        # A humanoid wears at least its body's skin.
        for skin in self.person.skins:  # pragma: no branch
            scene.skinned_meshes[skin].cast_shadow = True
        self.garments = List[Int]()
        # Every skinned mesh the body wears: its skin, and each part of
        # each garment.
        var worn = self.person.skins.copy()
        self.skirts = List[Int]()
        self.sway = Sway()
        self.sway_reach = SWAY_REACH * self.person.rig.stature / Float32(1.8288)
        if len(outfit.garments) > 0:
            var dressed = dress(scene, assets, self.person, outfit)
            self.garments = dressed.meshes.copy()
            # A garment in a design, with frills or of fur is drawn in
            # parts, and each part casts a shadow.
            for parts in dressed.parts:  # pragma: no branch
                for mesh in parts:
                    scene.skinned_meshes[mesh].cast_shadow = True
                    worn.append(mesh)
            # A skirt's hem swings as the person moves.
            var top = skirt_top(self.person.rig)
            for g in range(len(outfit.garments)):  # pragma: no branch
                if outfit.garments[g].form != SKIRTED:
                    continue
                self.skirts.extend(
                    sway_skirts(
                        scene, assets, dressed.parts[g], top, self.sway_reach
                    )
                )
        # A copy of each material that glows, to flash the body by.
        self.flashing = List[Int]()
        self.rest_looks = List[MaterialId]()
        self.flash_looks = List[MaterialId]()
        self.flashed = False
        var made = Dict[Int, MaterialId]()
        for mesh in worn:  # pragma: no branch
            var rest = scene.skinned_meshes[mesh].material
            if rest.value not in made:
                var glow = assets.materials.get(rest)
                glow.emissive = FLASH_GLOW
                glow.emissive_intensity = FLASH_STRENGTH
                made[rest.value] = assets.materials.add(glow)
            self.flashing.append(mesh)
            self.rest_looks.append(rest)
            self.flash_looks.append(made[rest.value])
        ref rig = self.person.rig
        ref bones = self.person.bones
        self.mixer = AnimationMixer()
        self.actions = List[Int]()
        self.actions.append(
            self.mixer.add(AnimationAction(idle_clip(bones, rig)))
        )
        self.actions.append(
            self.mixer.add(AnimationAction(walk_clip(bones, rig)))
        )
        self.actions.append(
            self.mixer.add(AnimationAction(run_clip(bones, rig)))
        )
        self.actions.append(
            self.mixer.add(AnimationAction(jump_clip(bones, rig)))
        )
        self.actions.append(
            self.mixer.add(AnimationAction(sit_clip(bones, rig)))
        )
        self.actions.append(
            self.mixer.add(AnimationAction(work_clip(bones, rig)))
        )
        self.mixer.action(self.actions[3]).set_loop(ONCE)
        self.mixer.action(self.actions[3]).clamp_when_finished = True
        self.mixer.action(self.actions[0]).play()
        self.playing = STANDING
        self.clip = 0
        var scale = rig.stature / Float32(1.8288)
        self.lift = -rig.at(RIGHT_TOES).y + SOLE * scale

    def pose(
        mut self,
        mut scene: Scene,
        character: Character,
        delta: Duration,
        activity: Activity = IDLE,
    ) raises:
        """Stand the body where a character stands, and play its stance,
        or what it does while it stands.

        Args:
            scene: The scene the body is in.
            character: The character the body shows.
            delta: The frame's time.
            activity: What the person does while they stand: at ease, on a
                bench, or at work.

        Raises:
            Error: If the time is negative, or a clip cannot be played.
        """
        ref node = scene.node(self.carrier)
        var at = character.position
        node.set_position(at.x, at.y + self.lift, at.z)
        node.set_rotation_from_axis_angle(
            Vector3(0, 1, 0), facing_turn(character.heading)
        )
        var stance = character.stance
        var clip = clip_of(stance)
        if stance == STANDING and activity == SIT:
            clip = 4
        elif stance == STANDING and activity == WORK:
            clip = 5
        if clip != self.clip:
            var next = self.actions[clip]
            var last = self.actions[self.clip]
            ref action = self.mixer.action(next)
            action.reset()
            if stance == AIRBORNE:
                action.phase = JUMP_TAKEOFF * action.clip.duration().to(SECOND)
            action.play()
            self.mixer.cross_fade_from(next, last, FADE)
            self.clip = clip
        self.playing = stance
        if clip < 4:
            self.mixer.action(self.actions[clip]).time_scale = play_rate(
                stance, character.speed()
            )
        self.mixer.update(scene, delta)
        self.swing_hem(scene, character, delta)

    def flash(mut self, mut scene: Scene, on: Bool):
        """Make the body glow white, as a blow lands on it, or stop.

        The skin and each garment wear their glowing copies while `on`
        holds.

        Args:
            scene: The scene the body is in.
            on: Whether the body glows.
        """
        if on == self.flashed:
            return
        self.flashed = on
        for k in range(len(self.flashing)):  # pragma: no branch
            var look = self.flash_looks[k] if on else self.rest_looks[k]
            scene.skinned_meshes[self.flashing[k]].material = look

    def swing_hem(
        mut self, mut scene: Scene, character: Character, delta: Duration
    ) raises:
        """Swing the hems of the person's skirts by the body's motion: see
        `extensions.village.sway`.

        Args:
            scene: The scene the body is in.
            character: The character the body shows.
            delta: The frame's time.

        Raises:
            Error: If a skirt's mesh is not in the scene.
        """
        if len(self.skirts) == 0:
            return
        var turn = facing_turn(character.heading).to(RADIAN)
        var offset = self.sway.step(
            character.position, turn, delta.to(SECOND), self.sway_reach
        )
        var weights = sway_weights(offset, self.sway_reach)
        weights.append(self.sway.flare)
        for mesh in self.skirts:  # pragma: no branch
            for w in range(5):  # pragma: no branch
                scene.skinned_meshes[mesh].set_morph_influence(w, weights[w])

    def head(self, scene: Scene) raises -> Vector3:
        """Return about where the person's eyes are, in the world.

        Args:
            scene: The scene the body is in.

        Returns:
            A point over the soles, `EYE_HEIGHT` of the person's height up.

        Raises:
            Error: If the carrier is not in the scene.
        """
        var at = scene.get(self.carrier).position
        # The carrier stands `lift` over the soles.
        var eyes = at.y - self.lift + EYE_HEIGHT * self.person.rig.stature
        return Vector3(at.x, eyes, at.z)

    def show_face(
        mut self,
        mut scene: Scene,
        eye: Vector3,
        reach: Float32,
        delta: Duration,
    ) raises:
        """Move a speaking person's face on by a frame, and show it.

        Within `reach` of the eye, the preserved face shows and wears the
        face's weights. Past it, the still face shows. A person who does
        not speak is left as it is.

        Args:
            scene: The scene the body is in.
            eye: Where the camera is.
            reach: How near the eye must be to see the face move, in
                meters: see `face_reach`.
            delta: The frame's time.

        Raises:
            Error: If the time is negative.
        """
        if not self.speaks:
            return
        var weights = self.life.advance(delta)
        var d = self.head(scene) - eye
        var near = d.dot(d) < reach * reach
        if near != self.near:
            self.person.show_face(scene, near)
            self.near = near
        if near:
            self.person.move_face(scene, weights)


@fieldwise_init
struct Activity(Equatable, ImplicitlyCopyable, Writable):
    """What a person does while they rest at a point of their route, as a
    type rather than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the three activities there are.

        Returns:
            Whether the value names an activity.
        """
        return ordinal_valid(self.value, 2)


# Standing at ease.
comptime IDLE = Activity(0)
# Sitting on a bench.
comptime SIT = Activity(1)
# Working with a tool: hoeing, chopping or drawing water.
comptime WORK = Activity(2)


@fieldwise_init
struct Stop(Copyable, ImplicitlyCopyable):
    """A place where a person stops a while to do something: a bench to
    sit on, or a place to work."""

    var x: Float32
    """Where the person stands, along x, in meters."""
    var z: Float32
    """Where the person stands, along z, in meters."""
    var facing: Angle
    """Which way the person faces there, as a yaw."""
    var activity: Activity
    """What the person does there."""


struct Route(Copyable, Movable):
    """The points a resident walks between, and how long it rests at each."""

    var points: List[Vector3]
    var activities: List[Activity]
    """What the resident does at each point."""
    var facings: List[Float32]
    """The yaw, in radians, that the resident turns to at each point, or
    NaN to keep its heading."""
    var at: Int
    """The point the resident rests at, or last rested at."""
    # The point it walks to now.
    var next: Int
    # How long it rests at each point, and how long it has left there.
    var rest: Duration
    var resting: Float32
    # Whether it runs between the points.
    var run: Bool
    # How long it has been stuck on its way to the point, in seconds.
    var stalled: Float32
    var detour: Float32
    """How long it still walks aside round something in its way, in
    seconds."""
    var side: Float32
    """Which side it last walked round on: one to its left, minus one to
    its right."""
    var detours: Int
    """How many times it has walked aside on its way to the point."""

    def __init__(
        out self, var points: List[Vector3], rest: Duration, run: Bool = False
    ) raises:
        """Create a route that starts toward its first point.

        Args:
            points: The points, on the ground: their y is not used.
            rest: How long to rest at each point.
            run: Whether to run between them.

        Raises:
            Error: If there is no point, or the rest is negative.
        """
        if len(points) == 0:
            raise Error("A route must have a point")
        if not (rest.to(SECOND) >= 0):
            raise Error("A route's rest must not be negative")
        self.activities = List[Activity](length=len(points), fill=IDLE)
        self.facings = List[Float32](
            length=len(points), fill=nan[DType.float32]()
        )
        self.points = points^
        self.at = 0
        self.next = 0
        self.rest = rest
        self.resting = 0
        self.run = run
        self.stalled = 0
        self.detour = 0
        self.side = 1
        self.detours = 0

    def steer(
        mut self, character: Character, delta: Duration
    ) -> Tuple[MoveInput, Angle]:
        """Return the input that walks a character along the route, and
        the yaw that the input is relative to.

        Args:
            character: The character.
            delta: The frame's time.

        Returns:
            A full lean toward the next point and the yaw toward it, or no
            input and the character's heading while it rests. A character
            that has walked aside `DETOURS` times on its way, behind
            a wall or another resident, rests as if it had arrived.
        """
        var seconds = delta.to(SECOND)
        if self.resting > 0:
            self.resting -= seconds
            var facing = self.facings[self.at]
            if isnan(facing):
                return (no_input(), character.heading)
            return (no_input(), Angle(facing, RADIAN))
        var goal = self.points[self.next]
        var way = Vector3(
            goal.x - character.position.x, 0, goal.z - character.position.z
        )
        if way.length() < ARRIVED or self.detours > DETOURS:
            self.at = self.next
            self.next = (self.next + 1) % len(self.points)
            self.resting = self.rest.to(SECOND)
            # A person sits or works a while longer than they stand.
            if self.activities[self.at] != IDLE:
                self.resting *= ACTIVITY_REST
            self.stalled = 0
            self.detours = 0
            return (no_input(), character.heading)
        # A resident stuck behind something walks round it: aside for
        # `DETOUR` seconds, to one side and then, stuck again, the other.
        if self.stalled >= SIDESTEP and self.detour <= 0:
            self.detour = DETOUR
            self.side = -self.side
            self.stalled = 0
            self.detours += 1
        if self.detour > 0:
            self.detour -= seconds
            way = Vector3(-way.z * self.side, 0, way.x * self.side) + way * 0.25
        if character.speed().to(METER_PER_SECOND) < STALL_SPEED:
            self.stalled += seconds
        else:
            self.stalled = 0
        var input = no_input()
        input.forward = 1
        input.run = self.run
        return (input, yaw_of(way))

    def add(mut self, stop: Stop):
        """Add a stop to the end of the route.

        Args:
            stop: Where to stop, which way to face, and what to do there.
        """
        self.points.append(Vector3(stop.x, 0, stop.z))
        self.activities.append(stop.activity)
        self.facings.append(stop.facing.to(RADIAN))

    def doing(self) -> Activity:
        """Return what the resident does now.

        Returns:
            The activity of the point it rests at, or `IDLE` on its way.
        """
        if self.resting > 0:
            return self.activities[self.at]
        return IDLE


def home_route(
    door: Doorway, climb: List[Vector3] = List[Vector3]()
) raises -> Route:
    """Return a route home: up to the front door, over the threshold, in,
    and up the stairs to bed, where the person stays.

    Args:
        door: The home's front door.
        climb: The way up the home's stairs, from the hall to the top
            story, as `HouseInterior.climb` gives it; empty to stay in the
            hall.

    Returns:
        The route, at its first point. A person on it stays at the last
        point, indoors, for as long as they keep to it.

    Raises:
        Error: Never: the route has its points.
    """
    var middle = door.middle()
    var into = Vector3(door.swing_x, 0, door.swing_z)
    var points = List[Vector3]()
    for reach in [-APPROACH, -THRESHOLD, INDOORS]:  # pragma: no branch
        points.append(middle + into * reach)
    points.extend(climb.copy())
    return Route(points^, Duration(0.2, SECOND))


def visit(mut route: Route, door: Doorway):
    """Add a visit to a house to the end of a route: up to its door, in,
    and back out.

    Args:
        route: The route.
        door: The house's front door.
    """
    var middle = door.middle()
    var into = Vector3(door.swing_x, 0, door.swing_z)
    for reach in [
        -APPROACH,
        -THRESHOLD,
        INDOORS,
        -THRESHOLD,
        -APPROACH,
    ]:  # pragma: no branch
        route.points.append(middle + into * reach)
        route.activities.append(IDLE)
        route.facings.append(nan[DType.float32]())


def wander_route(
    seed: Int,
    x: Float32,
    z: Float32,
    radius: Float32,
    count: Int,
    ground: Ground,
    lots: List[Lot],
    rest: Duration,
) raises -> Route:
    """Return a route between points scattered around a middle.

    A point on a lot, near one, or under the pond's water is tried again
    elsewhere, up to `TRIES` times, and left out after that. The middle
    itself is used when no point is left.

    Args:
        seed: Which points.
        x: The middle, in meters.
        z: The middle, in meters.
        radius: How far from the middle a point can be, in meters.
        count: How many points to try for, from 1 to 64.
        ground: The ground.
        lots: The buildings' footprints.
        rest: How long to rest at each point.

    Returns:
        The route.

    Raises:
        Error: If the count is not from 1 to 64, or the radius is not
            from 0 to 1 kilometer.
    """
    require_count_between(count, 1, 64, "A route must try from 1 to 64 points")
    require_between(radius, 0, 1000, "A route must reach from 0 to 1 kilometer")
    var points = List[Vector3]()
    for index in range(count):  # pragma: no branch
        for attempt in range(TRIES):  # pragma: no branch
            var angle = hash01(index, attempt, seed) * 2 * pi
            var reach = sqrt(hash01(index, attempt, seed + 1)) * radius
            var px = x + cos(angle) * reach
            var pz = z + sin(angle) * reach
            if _clear_of(px, pz, ground, lots):
                points.append(Vector3(px, 0, pz))
                break
    if len(points) == 0:
        points.append(Vector3(x, 0, z))
    return Route(points^, rest)


def _clear_of(x: Float32, z: Float32, ground: Ground, lots: List[Lot]) -> Bool:
    """Return whether a point is dry and a meter clear of every lot."""
    for index in range(len(lots)):
        if lots[index].reach(x, z) < 1:
            return False
    if ground.pond.radius.to(METER) > 0:
        if ground.height_at(x, z) < ground.water_level():
            return False
    return True


@fieldwise_init
struct HouseId(Equatable, ImplicitlyCopyable, Writable):
    """Which of the village's houses, by its place among them, as a type
    rather than a bare int. `NO_HOUSE` is none."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names a house's place, or no house.

        Returns:
            Whether the value is a place, or `NO_HOUSE`.
        """
        return self.value >= -1


comptime NO_HOUSE = HouseId(-1)
"""No house: a villager with no home to visit."""


struct Villager(Copyable, Movable):
    """A person of the village, what they wear, and where they wander."""

    var spec: HumanoidSpec
    # The middle of where they wander, and how far from it, in meters.
    var x: Float32
    var z: Float32
    var reach: Float32
    # Which points they wander between.
    var seed: Int
    # Whether they run between the points.
    var runs: Bool
    # What they wear.
    var outfit: Outfit
    # The house they visit, or `NO_HOUSE`.
    var home: HouseId
    # How their hair is cut and laid, and their beard.
    var groom: Groom

    def __init__(
        out self,
        spec: HumanoidSpec,
        x: Float32,
        z: Float32,
        reach: Float32,
        seed: Int,
        runs: Bool,
        outfit: Outfit,
        home: HouseId,
        groom: Groom = plain_groom(),
    ):
        """Hold a person of the village.

        Args:
            spec: Who they are.
            x: The middle of where they wander along x, in meters.
            z: The middle of where they wander along z, in meters.
            reach: How far from the middle they wander, in meters.
            seed: Which points they wander between.
            runs: Whether they run between the points.
            outfit: What they wear.
            home: The house they visit, or `NO_HOUSE`.
            groom: How their hair is cut, and their beard.
        """
        self.spec = spec.copy()
        self.x = x
        self.z = z
        self.reach = reach
        self.seed = seed
        self.runs = runs
        self.outfit = outfit.copy()
        self.home = home
        self.groom = groom


struct Herd(Copyable, Movable):
    """Animals of one kind that graze around one pasture."""

    var species: SpeciesId
    var count: Int
    # The pasture's middle and radius, in meters.
    var x: Float32
    var z: Float32
    var reach: Float32
    # Which individual, and which points they graze between.
    var seed: Int
    # How near the player may come before they run. Zero is tame.
    var flee: Length
    var follows: Bool
    """Whether they follow the player who comes near, as a dog does."""

    def __init__(
        out self,
        species: SpeciesId,
        count: Int,
        x: Float32,
        z: Float32,
        reach: Float32,
        seed: Int,
        flee: Length = Length(0.0, METER),
        follows: Bool = False,
    ):
        """Create a herd.

        Args:
            species: What kind of animal.
            count: How many.
            x: The pasture's middle along x, in meters.
            z: The pasture's middle along z, in meters.
            reach: How far around the middle they graze, in meters.
            seed: Which individual, and which points they graze between.
            flee: How near the player may come before they run away. Zero
                is tame.
            follows: Whether they follow the player within `FOLLOW_REACH`.
        """
        self.species = species
        self.count = count
        self.x = x
        self.z = z
        self.reach = reach
        self.seed = seed
        self.flee = flee
        self.follows = follows


struct ResidentsParameters(Copyable, Movable):
    """Who lives in the village, and how finely each one is built."""

    var villagers: List[Villager]
    var herds: List[Herd]
    # Each person's budget of triangles, and the cells along their skin.
    var triangles: Int
    var detail: Int
    # Whether the villagers' faces move: see `Body`'s `speaks`.
    var faces: Bool
    # The poses of each animal's walk, how finely it is meshed, and how
    # many times its tier's cell its mesh's cell is: 1 for the tier's own
    # mesh, more for a coarser one.
    var phases: Int
    var quality: Quality
    var animal_coarseness: Float64
    # How long a resident rests at each point of its route.
    var rest: Duration

    def __init__(out self):
        """Create nobody, with game budgets: 3,000 triangles a person and
        six poses an animal's stride. The villagers' faces move."""
        self.villagers = List[Villager]()
        self.herds = List[Herd]()
        self.faces = True
        self.triangles = 3000
        self.detail = 24
        self.phases = 6
        self.quality = CROWD
        self.animal_coarseness = 1
        self.rest = Duration(3.0, SECOND)

    def check(self) raises:
        """Refuse residents that cannot be built.

        Raises:
            Error: If there are not from 0 to 64 villagers or herds; a
                villager's home is not valid; a herd has not from 1 to 64
                animals, or its species is not one, or it flees from
                further than 100 meters or from a negative distance;
                a pasture or a wander reaches further than 1 kilometer;
                the budget is not from 500 to 100,000 triangles; the detail
                is not from 8 to 64; there are not from 1 to 32 phases; the
                animals' coarseness is not from 1 to 8; or the rest is not
                from 0 to 1 minute.
        """
        require_count_between(
            len(self.villagers),
            0,
            64,
            "A village must have from 0 to 64 villagers",
        )
        require_count_between(
            len(self.herds), 0, 64, "A village must have from 0 to 64 herds"
        )
        for index in range(len(self.villagers)):
            require_between(
                self.villagers[index].reach,
                0,
                1000,
                "A villager must wander from 0 to 1 kilometer",
            )
            if not self.villagers[index].home.is_valid():
                raise Error("A villager's home must be a house, or NO_HOUSE")
        for index in range(len(self.herds)):
            ref herd = self.herds[index]
            require_species(herd.species)
            require_count_between(
                herd.count, 1, 64, "A herd must have from 1 to 64 animals"
            )
            require_between(
                herd.reach,
                0,
                1000,
                "A pasture must reach from 0 to 1 kilometer",
            )
            require_between(
                herd.flee.to(METER),
                0,
                100,
                "A herd must flee from 0 to 100 meters",
            )
        require_count_between(
            self.triangles,
            500,
            100000,
            "A person must have from 500 to 100,000 triangles",
        )
        require_count_between(
            self.detail, 8, 64, "A person's detail must be from 8 to 64"
        )
        require_count_between(
            self.phases, 1, 32, "An animal must have from 1 to 32 phases"
        )
        if not (self.animal_coarseness >= 1 and self.animal_coarseness <= 8):
            raise Error("An animal's coarseness must be from 1 to 8")
        require_between(
            self.rest.to(SECOND),
            0,
            60,
            "A resident must rest from 0 to 1 minute",
        )


struct Flipbook(Copyable, Movable):
    """One animal's meshes: standing, and at each phase of its walk."""

    var stand: GeometryId
    var frames: List[GeometryId]
    # How far one stride carries the animal, in meters. Zero for an
    # animal that does not walk on four legs.
    var stride: Float32

    def __init__(
        out self,
        stand: GeometryId,
        var frames: List[GeometryId],
        stride: Float32,
    ):
        """Gather an animal's meshes.

        Args:
            stand: Its standing mesh.
            frames: Its mesh at each phase of its walk, in order.
            stride: How far one stride carries it, in meters.
        """
        self.stand = stand
        self.frames = frames^
        self.stride = stride

    def frame(self, character: Character) -> GeometryId:
        """Return the mesh that shows a character's animal now.

        Args:
            character: The animal's character.

        Returns:
            The standing mesh while it stands or has no stride, and the
            walk's pose at how far it has walked otherwise.
        """
        return self.frame_at(character.traveled, character.stance != STANDING)

    def frame_at(self, paced: Float32, moving: Bool) -> GeometryId:
        """Return the mesh of an animal that has paced a distance.

        Args:
            paced: How far its feet have stepped, in meters: its walk, and
                the steps it took to turn.
            moving: Whether its feet step now: it walks, or turns on the
                spot.

        Returns:
            The standing mesh while its feet are still or it has no
            stride, and the walk's pose at `paced` otherwise.
        """
        if not moving or self.stride <= 0:
            return self.stand
        if len(self.frames) == 0:
            return self.stand
        var strides = paced / self.stride
        var phase = strides - Float32(Int(strides))
        var index = Int(phase * Float32(len(self.frames)))
        return self.frames[min(index, len(self.frames) - 1)]


def animal_paints(mut assets: Assets) raises -> List[MaterialId]:
    """Add the materials an animal's mesh wears.

    Args:
        assets: The stores the materials go into.

    Returns:
        The materials, in the order an animal's mesh names them.

    Raises:
        Error: If a material cannot be added.
    """
    var paints = List[MaterialId]()
    for material in animal_materials():  # pragma: no branch
        paints.append(assets.materials.add(material.copy()))
    return paints^


struct AnimalLook(Movable):
    """An animal's flipbook, and how its character moves."""

    var book: Flipbook
    var walker: CharacterParameters

    def __init__(out self, var book: Flipbook, walker: CharacterParameters):
        """Hold an animal's flipbook and its pace.

        Args:
            book: Its meshes.
            walker: How its character moves.
        """
        self.book = book^
        self.walker = walker


__async def _pose_task(
    animal: Pointer[Animal, ImmutAnyOrigin],
    poses: Pointer[List[Pose], ImmutAnyOrigin],
    meshes: Pointer[List[BufferGeometry], MutAnyOrigin],
    failures: Pointer[List[String], MutAnyOrigin],
    index: Int,
):
    """Mesh an animal in one of its poses, or record why it failed."""
    try:
        meshes[][index] = mesh_animal(animal[], poses[][index], workers=0)
    except e:
        failures[][index] = String(e)


def mesh_poses(
    animal: Animal, poses: List[Pose]
) raises -> List[BufferGeometry]:
    """Return an animal's mesh in each pose, the poses meshed at once.

    Each mesh is the same as `mesh_animal` makes alone: the poses only
    share the threads.

    Args:
        animal: The animal.
        poses: Its poses.

    Returns:
        One mesh per pose, in their order.

    Raises:
        Error: The first pose's error, in their order, if `mesh_animal`
            refuses one.
    """
    var meshes = List[BufferGeometry]()
    var failures = List[String]()
    for _ in range(len(poses)):  # pragma: no branch
        meshes.append(BufferGeometry())
        failures.append(String())
    var group = TaskGroup()
    for index in range(len(poses)):  # pragma: no branch
        group.create_task(
            _pose_task(
                Pointer(to=animal).unsafe_origin_cast[ImmutAnyOrigin](),
                Pointer(to=poses).unsafe_origin_cast[ImmutAnyOrigin](),
                Pointer(to=meshes).unsafe_origin_cast[MutAnyOrigin](),
                Pointer(to=failures).unsafe_origin_cast[MutAnyOrigin](),
                index,
            )
        )
    group.wait()
    for failure in failures:  # pragma: no branch
        if failure != "":
            raise Error(failure)
    return meshes^


def animal_look(
    mut assets: Assets,
    species: SpeciesId,
    seed: Int,
    phases: Int,
    quality: Quality,
    coarseness: Float64,
) raises -> AnimalLook:
    """Mesh an animal as a flipbook, and pace its character.

    Args:
        assets: The stores the meshes go into.
        species: The animal's species.
        seed: The seed of its build.
        phases: How many poses of its walk to mesh.
        quality: How finely it is meshed.
        coarseness: How many times its quality's cell its mesh's cell is.
            The eyes' finer cell grows as much, but never past the body's.

    Returns:
        Its standing mesh and, for an animal on four legs, its walk's
        meshes and its stride. Its character is as wide as the mesh,
        does not jump, and walks at the pace of its stride: 0.3 meters a
        second for an animal not on four legs. It runs at `FLEE_PACE`
        times its walk.

    Raises:
        Error: If the animal cannot be built or meshed.
    """
    var animal = create_animal(
        species,
        animal_options(seed, quality=quality),
    )
    animal.cell *= coarseness
    # The eyes have their own finer cell. Left fine, they made half of a
    # coarse rabbit's vertices.
    animal.eye_cell = min(animal.cell, animal.eye_cell * coarseness)
    # The standing pose first, then the walk's.
    var poses = List[Pose]()
    poses.append(animal.bind_pose())
    var quadruped = is_quadruped(animal.rig)
    if quadruped:
        for phase in range(phases):  # pragma: no branch
            poses.append(
                walk_pose(animal.rig, Float64(phase) / Float64(phases))
            )
    var meshes = mesh_poses(animal, poses)
    var stand = assets.geometries.add(meshes.pop(0))
    var box = assets.geometries.get(stand).bounding_box()
    var frames = List[GeometryId]()
    var stride = Float32(0)
    var walker = CharacterParameters()
    walker.radius = Length(
        max(Float32(0.1), (box.max.x - box.min.x) * 0.5), METER
    )
    walker.jump_speed = Velocity(0.0, METER_PER_SECOND)
    if quadruped:
        stride = walk_stride(animal.rig).to(METER)
        var hip = length_meters(animal.rig.j("hipL").y)
        var pace = stride * stride_frequency(WALK_FROUDE, hip).value
        walker.walk_speed = Velocity(max(Float32(0.2), pace), METER_PER_SECOND)
        for _ in range(len(meshes)):  # pragma: no branch
            frames.append(assets.geometries.add(meshes.pop(0)))
    else:
        walker.walk_speed = Velocity(0.3, METER_PER_SECOND)
    # An animal runs only when it flees, at three times its walk.
    walker.run_speed = Velocity(
        walker.walk_speed.to(METER_PER_SECOND) * FLEE_PACE,
        METER_PER_SECOND,
    )
    return AnimalLook(Flipbook(stand, frames^, stride), walker)


@fieldwise_init
struct Beast(Copyable, Movable):
    """One animal in the scene."""

    var character: Character
    var route: Route
    # The node it stands on, its mesh in `scene.meshes`, and its flipbook.
    var node: NodeId
    var mesh: Int
    var book: Int
    # How near the player may come before it runs, in meters.
    var flee: Float32
    # Whether it follows the player.
    var follows: Bool
    var paced: Float32
    """How far its feet have stepped, in meters, its turns on the spot
    included."""


def _flight(
    at: Vector3, dangers: List[Vector3]
) -> Optional[Tuple[MoveInput, Angle]]:
    """Return the run away from the nearest danger within `PANIC`, or
    None."""
    var nearest = PANIC
    var away = Vector3(0, 0, 0)
    for danger in dangers:
        var off = Vector3(at.x - danger.x, 0, at.z - danger.z)
        var d = off.length()
        if d < nearest:
            nearest = d
            away = off
    if nearest >= PANIC:
        return None
    var run = no_input()
    run.forward = 1
    run.run = True
    return (run, yaw_of(away))


struct Residents(Movable):
    """The people and the animals of the village, in a scene."""

    var bodies: List[Body]
    var people: List[Character]
    var walks: List[Route]
    var books: List[Flipbook]
    var beasts: List[Beast]
    # How long each person still stands still, in seconds, and the point
    # they face while they do: see `hold`.
    var holds: List[Float32]
    var faces: List[Vector3]
    var homeward: List[Route]
    """Each person's way home and in, for when the village shelters."""
    var outward: List[Route]
    """Each person's way back out of their home: their way home, the other
    way round."""
    var leaving: List[Bool]
    """Whether each person is still on their way out of their home, since
    the village stopped sheltering."""
    var sheltering: Bool
    """Whether the people keep to their homes now: at night, or in hard
    rain or snow."""

    def __init__(
        out self,
        mut scene: Scene,
        mut assets: Assets,
        parameters: ResidentsParameters,
        terrain: Terrain,
        lots: List[Lot],
        homes: List[Doorway],
        stops: List[Stop] = List[Stop](),
        climbs: List[List[Vector3]] = List[List[Vector3]](),
    ) raises:
        """Build the residents into a scene, each at its first place.

        Args:
            scene: The scene.
            assets: The stores.
            parameters: Who lives in the village.
            terrain: What they walk on.
            lots: The buildings' footprints, which their routes keep off.
            homes: Each house's front door, in the order of the village's
                houses.
            stops: The benches to sit on and the places to work. A person
                stops at each one within `STOP_REACH` of the middle of
                where they wander.
            climbs: The way up each home's stairs, in the order of
                `homes`, as `HouseInterior.climb` gives it: by night a
                person goes up to bed. Empty, or shorter than `homes`,
                for homes where they stay in the hall.

        Raises:
            Error: If `parameters.check` refuses a value, a villager's
                home is not one of `homes`, or a person or an animal
                cannot be built.
        """
        parameters.check()
        self.bodies = List[Body]()
        self.people = List[Character]()
        self.walks = List[Route]()
        self.holds = List[Float32](length=len(parameters.villagers), fill=0)
        self.faces = List[Vector3](
            length=len(parameters.villagers), fill=Vector3(0, 0, 0)
        )
        self.homeward = List[Route]()
        self.outward = List[Route]()
        self.leaving = List[Bool](length=len(parameters.villagers), fill=False)
        self.sheltering = False
        for index in range(len(parameters.villagers)):
            ref villager = parameters.villagers[index]
            self.bodies.append(
                Body(
                    scene,
                    assets,
                    villager.spec,
                    villager.outfit,
                    parameters.triangles,
                    parameters.detail,
                    speaks=parameters.faces,
                    seed=villager.seed,
                    hair=villager.groom.hair,
                    beard=villager.groom.beard,
                )
            )
            var route = wander_route(
                villager.seed,
                villager.x,
                villager.z,
                villager.reach,
                6,
                terrain.ground,
                lots,
                parameters.rest,
            )
            route.run = villager.runs
            var start = route.points[len(route.points) - 1]
            for stop in stops:
                var dx = stop.x - villager.x
                var dz = stop.z - villager.z
                if dx * dx + dz * dz <= STOP_REACH * STOP_REACH:
                    route.add(stop)
            var home = villager.home.value
            if home >= 0:
                if home >= len(homes):
                    raise Error("A villager's home must be a house")
                visit(route, homes[home])
            # A person with no home of their own shelters in the first.
            if home >= 0 or len(homes) > 0:
                var at = max(0, home)
                var climb = List[Vector3]()
                if at < len(climbs):
                    climb = climbs[at].copy()
                var going = home_route(homes[at], climb)
                var back = List[Vector3]()
                # A way home has its points at the door, at the least.
                for k in range(
                    len(going.points) - 1, -1, -1
                ):  # pragma: no branch
                    back.append(going.points[k])
                self.outward.append(Route(back^, Duration(0.2, SECOND)))
                self.homeward.append(going^)
            else:
                self.homeward.append(route.copy())
                self.outward.append(route.copy())
            self.people.append(
                Character(
                    CharacterParameters(),
                    start.x,
                    start.z,
                    Angle(Float32(index), RADIAN),
                    terrain,
                )
            )
            self.walks.append(route^)
        self.books = List[Flipbook]()
        self.beasts = List[Beast]()
        var paints = animal_paints(assets)
        for index in range(len(parameters.herds)):
            ref herd = parameters.herds[index]
            var look = animal_look(
                assets,
                herd.species,
                herd.seed,
                parameters.phases,
                parameters.quality,
                parameters.animal_coarseness,
            )
            var stand = look.book.stand
            var walker = look.walker
            var book = len(self.books)
            self.books.append(look.book.copy())
            for member in range(herd.count):  # pragma: no branch
                var route = wander_route(
                    herd.seed * 64 + member,
                    herd.x,
                    herd.z,
                    herd.reach,
                    5,
                    terrain.ground,
                    lots,
                    parameters.rest,
                )
                var start = route.points[member % len(route.points)]
                var node = scene.add(Object3D())
                var mesh = len(scene.meshes)
                scene.add_mesh(
                    Mesh(
                        stand,
                        paints,
                        node,
                        cast_shadow=True,
                        receive_shadow=True,
                    )
                )
                var character = Character(
                    walker,
                    start.x,
                    start.z,
                    Angle(Float32(member) * 2.4, RADIAN),
                    terrain,
                )
                route.next = (member + 1) % len(route.points)
                self.beasts.append(
                    Beast(
                        character^,
                        route^,
                        node,
                        mesh,
                        book,
                        herd.flee.to(METER),
                        herd.follows,
                        0,
                    )
                )

    def update(
        mut self,
        mut scene: Scene,
        delta: Duration,
        terrain: Terrain,
        obstacles: List[Obstacle],
        player: Optional[Vector3] = None,
        shelter: Bool = False,
        dangers: List[Vector3] = List[Vector3](),
    ) raises:
        """Move every resident along its route by one frame, and pose it.

        Each resident bumps into the obstacles that you give and into
        every other resident: where it stands now, for one that has moved
        this frame, and where it stood, for one that has not. An animal
        that the player comes nearer than its herd's `flee` runs straight
        away, and walks back to its route once the player is further. A
        person held by `hold` stands and turns to face their point.

        Args:
            scene: The scene the residents are in.
            delta: The frame's time.
            terrain: The ground, the floors, the walls and the solid
                buildings.
            obstacles: The round things in the way.
            player: Where the player stands, which a shy animal runs from,
                and which a dog follows.
            shelter: Whether the people go home and stay in: at night, or
                in hard rain or snow. Once it is false again, they go back
                to their routes.
            dangers: Where each foe stands. A person or an animal within
                `PANIC` of one runs from it.

        Raises:
            Error: If the time is negative, or a clip cannot be played.
        """
        # One list holds the obstacles and then the residents; each one
        # steps passing over its own entry.
        var crowd = obstacles.copy()
        var first = len(crowd)
        crowd.extend(self.obstacles())
        var people = len(self.people)
        var seconds = delta.to(SECOND)
        if shelter and not self.sheltering:
            # Each person sets out for home from where they stand.
            for index in range(people):
                self.homeward[index].next = 0
                self.homeward[index].resting = 0
                self.leaving[index] = False
        if self.sheltering and not shelter:
            # Each person comes back out the way they went in: down the
            # stairs, through the hall and out of the door.
            for index in range(people):
                self.outward[index].next = 0
                self.outward[index].resting = 0
                self.leaving[index] = True
        self.sheltering = shelter
        for index in range(people):
            var steer: Tuple[MoveInput, Angle]
            var fled = _flight(self.people[index].position, dangers)
            var doing = IDLE
            if fled:
                steer = fled.value()
            elif self.holds[index] > 0:
                # A held person stands, and turns to face their point. Their
                # route waits.
                self.holds[index] -= seconds
                ref at = self.people[index].position
                var toward = self.faces[index] - at
                var turned = turn_toward(
                    self.people[index].heading,
                    yaw_of(Vector3(toward.x, 0, toward.z)),
                    Angle(FACE_SPEED * seconds, RADIAN),
                )
                self.people[index].heading = turned
                steer = (no_input(), turned)
            elif shelter:
                steer = self.homeward[index].steer(self.people[index], delta)
                # Home, they stay in.
                ref home = self.homeward[index]
                if home.at == len(home.points) - 1 and home.resting > 0:
                    home.next = home.at
                    home.resting = 1
            elif self.leaving[index]:
                steer = self.outward[index].steer(self.people[index], delta)
                # Out of the door, they walk their route again.
                ref out = self.outward[index]
                if out.at == len(out.points) - 1:
                    self.leaving[index] = False
            else:
                steer = self.walks[index].steer(self.people[index], delta)
                doing = self.walks[index].doing()
                # A seated person or one at work turns to their stop.
                if doing != IDLE:
                    self.people[index].heading = turn_toward(
                        self.people[index].heading,
                        steer[1],
                        Angle(FACE_SPEED * seconds, RADIAN),
                    )
            self.people[index].step(
                steer[0], steer[1], delta, terrain, crowd, first + index
            )
            ref feet = self.people[index].position
            crowd[first + index].x = feet.x
            crowd[first + index].z = feet.z
            self.bodies[index].pose(scene, self.people[index], delta, doing)
        for index in range(len(self.beasts)):
            ref beast = self.beasts[index]
            var steer = beast.route.steer(beast.character, delta)
            if player:
                var at = beast.character.position
                var away = Vector3(
                    at.x - player.value().x, 0, at.z - player.value().z
                )
                var apart = away.length()
                if apart < beast.flee:
                    var run = no_input()
                    run.forward = 1
                    run.run = True
                    steer = (run, yaw_of(away))
                elif beast.follows and apart < FOLLOW_REACH:
                    # A dog keeps at its master's heel, and runs to catch
                    # up from far.
                    if apart > HEEL:
                        var go = no_input()
                        go.forward = 1
                        go.run = apart > HEEL * 3
                        steer = (go, yaw_of(Vector3(0, 0, 0) - away))
                    else:
                        steer = (no_input(), beast.character.heading)
            if beast.flee > 0:
                var fled = _flight(beast.character.position, dangers)
                if fled:
                    steer = fled.value()
            var own = first + people + index
            var was = beast.character.heading.to(RADIAN)
            var walked = beast.character.traveled
            beast.character.step(steer[0], steer[1], delta, terrain, crowd, own)
            # An animal that turns on the spot steps round as it turns.
            var turn = beast.character.heading.to(RADIAN) - was
            turn = turn - Float32(2 * pi) * floor(turn / Float32(2 * pi) + 0.5)
            var stepped = beast.character.traveled - walked
            beast.paced += stepped + abs(turn) * TURN_STEP
            var turning = abs(turn) > TURNING * delta.to(SECOND)
            crowd[own].x = beast.character.position.x
            crowd[own].z = beast.character.position.z
            var at = beast.character.position
            ref node = scene.node(beast.node)
            node.set_position(at.x, at.y, at.z)
            node.set_rotation_from_axis_angle(
                Vector3(0, 1, 0), facing_turn(beast.character.heading)
            )
            scene.meshes[beast.mesh].geometry = self.books[beast.book].frame_at(
                beast.paced,
                beast.character.stance != STANDING or turning,
            )

    def doing(self, index: Int) -> Activity:
        """Return what a person does now.

        Args:
            index: The person's place among `people`.

        Returns:
            Their activity, or `IDLE` on their way, while they shelter, and
            for a person who is not one.
        """
        if index < 0 or index >= len(self.people) or self.sheltering:
            return IDLE
        return self.walks[index].doing()

    def hold(mut self, index: Int, seconds: Float32, toward: Vector3) raises:
        """Stop a person on their route for a while, turned to face a point,
        as a villager stops to talk to the player.

        Args:
            index: The person's place among `people`.
            seconds: How long they stand. Their route waits for them.
            toward: The point they turn to face.

        Raises:
            Error: If the person is not one, or the time is negative.
        """
        if index < 0 or index >= len(self.people):
            raise Error("A held person must be one of the residents")
        if not (seconds >= 0):
            raise Error("A hold's time must not be negative")
        self.holds[index] = seconds
        self.faces[index] = toward

    def obstacles(self) -> List[Obstacle]:
        """Return each resident as an obstacle, for the player to bump.

        Returns:
            A circle for each person and each animal, where it stands now.
        """
        var out = List[Obstacle]()
        for index in range(len(self.people)):
            ref person = self.people[index]
            out.append(
                Obstacle(
                    person.position.x,
                    person.position.z,
                    person.parameters.radius.to(METER),
                )
            )
        for index in range(len(self.beasts)):
            ref beast = self.beasts[index].character
            out.append(
                Obstacle(
                    beast.position.x,
                    beast.position.z,
                    beast.parameters.radius.to(METER),
                )
            )
        return out^
