# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The people and the animals of the village, and how each one moves.

Every resident is a `Character`, as the player is, so the ground, the
houses, the trees and the pond stop them all alike. A `Route` steers each
one: it walks to a point, rests there a while, and walks on to the next.

**People.** A `Body` is a game humanoid on a skeleton, with its idle, walk,
run and jump clips in an `AnimationMixer`. Each frame it stands where its
character stands, turns the way it faces, and fades to the clip of its
`Stance`. The walk and the run play faster or slower with the speed, so
the feet keep pace with the ground. The player is a `Body` too.

**Animals.** An animal is meshed once for each of `phases` poses of its
walk, and once standing: a flipbook. Each frame its mesh shows the pose of
how far it has walked, so a stride covers one stride of ground. Each
`Herd` grazes round its own pasture. A species that does not walk on four
legs keeps its standing mesh.
"""

from animation.animation_mixer import ONCE, AnimationAction, AnimationMixer
from core.assets import Assets
from core.geometry_store import GeometryId
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.anatomy.locomotion import WALK_FROUDE, stride_frequency
from extensions.animals.build import (
    animal_materials,
    create_animal,
    mesh_animal,
)
from extensions.animals.gait import is_quadruped, walk_pose, walk_stride
from extensions.animals.options import CROWD, Quality, animal_options
from extensions.animals.registry import SpeciesId, require_species
from extensions.humanoid.rig.clips import (
    idle_clip,
    jump_clip,
    run_clip,
    walk_clip,
)
from extensions.humanoid.rig.game import GameHumanoid, add_game_humanoid
from extensions.humanoid.rig.joints import RIGHT_TOES
from extensions.humanoid.spec import HumanoidSpec
from extensions.vegetation.checks import require_between, require_count_between
from extensions.vegetation.ground import Ground, Lot
from extensions.vegetation.noise import hash01
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
from controls.third_person_controls import yaw_of
from materials.material import MaterialId
from math.vector3 import Vector3
from objects.mesh import Mesh
from std.math import cos, pi, sin, sqrt
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
comptime ARRIVED = Float32(0.6)
"""How near a point a resident must come, in meters, to have reached it."""
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


def facing_turn(heading: Angle) -> Angle:
    """Return how far to turn a model about +y so it faces a heading.

    A humanoid and an animal are built facing +z. A heading of 0 faces -z.

    Args:
        heading: The way to face, as a yaw.

    Returns:
        The heading plus half a turn.
    """
    return Angle(heading.to(RADIAN) + pi, RADIAN)


struct Body(Movable):
    """A person's skinned body, its clips, and the node that carries it."""

    var person: GameHumanoid
    # The node the humanoid hangs from. It stands at the feet.
    var carrier: NodeId
    var mixer: AnimationMixer
    # The idle, walk, run and jump actions, in that order.
    var actions: List[Int]
    # The stance whose clip plays.
    var playing: Stance
    # How far the humanoid's origin is above its soles, in meters.
    var lift: Float32

    def __init__(
        out self,
        mut scene: Scene,
        mut assets: Assets,
        spec: HumanoidSpec,
        triangles: Int,
        detail: Int,
    ) raises:
        """Build a person into a scene, standing at the origin.

        Args:
            scene: The scene.
            assets: The stores.
            spec: The person.
            triangles: The skin's budget of triangles.
            detail: The cells along the body's skin, from 8 to 64. The
                hands and the hair take half as many, and at least 8.

        Raises:
            Error: If the humanoid cannot be built.
        """
        self.carrier = scene.add(Object3D())
        var half = max(8, detail // 2)
        self.person = add_game_humanoid(
            scene,
            assets,
            self.carrier,
            spec,
            triangles,
            detail=detail,
            hand_detail=half,
            hair_detail=half,
        )
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
        self.mixer.action(self.actions[3]).set_loop(ONCE)
        self.mixer.action(self.actions[3]).clamp_when_finished = True
        self.mixer.action(self.actions[0]).play()
        self.playing = STANDING
        var scale = rig.stature / Float32(1.8288)
        self.lift = -rig.at(RIGHT_TOES).y + SOLE * scale

    def pose(
        mut self, mut scene: Scene, character: Character, delta: Duration
    ) raises:
        """Stand the body where a character stands, and play its stance.

        Args:
            scene: The scene the body is in.
            character: The character the body shows.
            delta: The frame's time.

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
        if stance != self.playing:
            var next = self.actions[clip_of(stance)]
            var last = self.actions[clip_of(self.playing)]
            ref action = self.mixer.action(next)
            action.reset()
            if stance == AIRBORNE:
                action.phase = JUMP_TAKEOFF * action.clip.duration().to(SECOND)
            action.play()
            self.mixer.cross_fade_from(next, last, FADE)
            self.playing = stance
        self.mixer.action(self.actions[clip_of(stance)]).time_scale = play_rate(
            stance, character.speed()
        )
        self.mixer.update(scene, delta)


struct Route(Copyable, Movable):
    """The points a resident walks between, and how long it rests at each."""

    var points: List[Vector3]
    # The point it walks to now.
    var next: Int
    # How long it rests at each point, and how long it has left there.
    var rest: Duration
    var resting: Float32
    # Whether it runs between the points.
    var run: Bool

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
        self.points = points^
        self.next = 0
        self.rest = rest
        self.resting = 0
        self.run = run

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
            input and the character's heading while it rests.
        """
        if self.resting > 0:
            self.resting -= delta.to(SECOND)
            return (no_input(), character.heading)
        var goal = self.points[self.next]
        var way = Vector3(
            goal.x - character.position.x, 0, goal.z - character.position.z
        )
        if way.length() < ARRIVED:
            self.next = (self.next + 1) % len(self.points)
            self.resting = self.rest.to(SECOND)
            return (no_input(), character.heading)
        var input = no_input()
        input.forward = 1
        input.run = self.run
        return (input, yaw_of(way))


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
    """Return a route between points scattered round a middle.

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
    for index in range(count):
        for attempt in range(TRIES):
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
struct Villager(Copyable, Movable):
    """A person of the village, and where they wander."""

    var spec: HumanoidSpec
    # The middle of where they wander, and how far from it, in meters.
    var x: Float32
    var z: Float32
    var reach: Float32
    # Which points they wander between.
    var seed: Int
    # Whether they run between the points.
    var runs: Bool


@fieldwise_init
struct Herd(Copyable, Movable):
    """Animals of one kind that graze round one pasture."""

    var species: SpeciesId
    var count: Int
    # The pasture's middle and radius, in meters.
    var x: Float32
    var z: Float32
    var reach: Float32
    # Which individual, and which points they graze between.
    var seed: Int


struct ResidentsParameters(Copyable, Movable):
    """Who lives in the village, and how finely each one is built."""

    var villagers: List[Villager]
    var herds: List[Herd]
    # Each person's budget of triangles, and the cells along their skin.
    var triangles: Int
    var detail: Int
    # The poses of each animal's walk, and how finely it is meshed.
    var phases: Int
    var quality: Quality
    # How long a resident rests at each point of its route.
    var rest: Duration

    def __init__(out self):
        """Create nobody, with game budgets: 3,000 triangles a person and
        six poses an animal's stride."""
        self.villagers = List[Villager]()
        self.herds = List[Herd]()
        self.triangles = 3000
        self.detail = 24
        self.phases = 6
        self.quality = CROWD
        self.rest = Duration(3.0, SECOND)

    def check(self) raises:
        """Refuse residents that cannot be built.

        Raises:
            Error: If there are not from 0 to 64 villagers or herds; a herd
                has not from 1 to 64 animals, or its species is not one;
                a pasture or a wander reaches further than 1 kilometer;
                the budget is not from 500 to 100,000 triangles; the detail
                is not from 8 to 64; there are not from 1 to 32 phases; or
                the rest is not from 0 to 1 minute.
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
        if character.stance == STANDING or self.stride <= 0:
            return self.stand
        if len(self.frames) == 0:
            return self.stand
        var strides = character.travelled / self.stride
        var phase = strides - Float32(Int(strides))
        var index = Int(phase * Float32(len(self.frames)))
        return self.frames[min(index, len(self.frames) - 1)]


@fieldwise_init
struct Beast(Copyable, Movable):
    """One animal in the scene."""

    var character: Character
    var route: Route
    # The node it stands on, its mesh in `scene.meshes`, and its flipbook.
    var node: NodeId
    var mesh: Int
    var book: Int


struct Residents(Movable):
    """The people and the animals of the village, in a scene."""

    var bodies: List[Body]
    var people: List[Character]
    var walks: List[Route]
    var books: List[Flipbook]
    var beasts: List[Beast]

    def __init__(
        out self,
        mut scene: Scene,
        mut assets: Assets,
        parameters: ResidentsParameters,
        ground: Ground,
        lots: List[Lot],
    ) raises:
        """Build the residents into a scene, each at its first place.

        Args:
            scene: The scene.
            assets: The stores.
            parameters: Who lives in the village.
            ground: The ground they walk on.
            lots: The buildings' footprints.

        Raises:
            Error: If `parameters.check` refuses a value, or a person or an
                animal cannot be built.
        """
        parameters.check()
        self.bodies = List[Body]()
        self.people = List[Character]()
        self.walks = List[Route]()
        for index in range(len(parameters.villagers)):
            ref villager = parameters.villagers[index]
            self.bodies.append(
                Body(
                    scene,
                    assets,
                    villager.spec,
                    parameters.triangles,
                    parameters.detail,
                )
            )
            var route = wander_route(
                villager.seed,
                villager.x,
                villager.z,
                villager.reach,
                6,
                ground,
                lots,
                parameters.rest,
            )
            route.run = villager.runs
            var start = route.points[len(route.points) - 1]
            self.people.append(
                Character(
                    CharacterParameters(),
                    start.x,
                    start.z,
                    Angle(Float32(index), RADIAN),
                    ground,
                )
            )
            self.walks.append(route^)
        self.books = List[Flipbook]()
        self.beasts = List[Beast]()
        var paints = List[MaterialId]()
        for material in animal_materials():
            paints.append(assets.materials.add(material.copy()))
        for index in range(len(parameters.herds)):
            ref herd = parameters.herds[index]
            var animal = create_animal(
                herd.species,
                animal_options(herd.seed, quality=parameters.quality),
            )
            var stand = assets.geometries.add(
                mesh_animal(animal, animal.bind_pose(), workers=0)
            )
            var box = assets.geometries.get(stand).bounding_box()
            var frames = List[GeometryId]()
            var stride = Float32(0)
            var walker = CharacterParameters()
            walker.radius = Length(
                max(Float32(0.1), (box.max.x - box.min.x) * 0.5), METER
            )
            walker.jump_speed = Velocity(0.0, METER_PER_SECOND)
            if is_quadruped(animal.rig):
                stride = walk_stride(animal.rig).to(METER)
                var hip = length_meters(animal.rig.j("hipL").y)
                var pace = stride * stride_frequency(WALK_FROUDE, hip).value
                walker.walk_speed = Velocity(
                    max(Float32(0.2), pace), METER_PER_SECOND
                )
                for phase in range(parameters.phases):
                    var pose = walk_pose(
                        animal.rig,
                        Float64(phase) / Float64(parameters.phases),
                    )
                    frames.append(
                        assets.geometries.add(
                            mesh_animal(animal, pose, workers=0)
                        )
                    )
            else:
                walker.walk_speed = Velocity(0.3, METER_PER_SECOND)
            walker.run_speed = walker.walk_speed
            var book = len(self.books)
            self.books.append(Flipbook(stand, frames^, stride))
            for member in range(herd.count):
                var route = wander_route(
                    herd.seed * 64 + member,
                    herd.x,
                    herd.z,
                    herd.reach,
                    5,
                    ground,
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
                    ground,
                )
                route.next = (member + 1) % len(route.points)
                self.beasts.append(Beast(character^, route^, node, mesh, book))

    def update(
        mut self,
        mut scene: Scene,
        delta: Duration,
        ground: Ground,
        lots: List[Lot],
        obstacles: List[Obstacle],
    ) raises:
        """Move every resident along its route by one frame, and pose it.

        Args:
            scene: The scene the residents are in.
            delta: The frame's time.
            ground: The ground.
            lots: The buildings' footprints.
            obstacles: The round things in the way.

        Raises:
            Error: If the time is negative, or a clip cannot be played.
        """
        for index in range(len(self.people)):
            var steer = self.walks[index].steer(self.people[index], delta)
            self.people[index].step(
                steer[0], steer[1], delta, ground, lots, obstacles
            )
            self.bodies[index].pose(scene, self.people[index], delta)
        for index in range(len(self.beasts)):
            ref beast = self.beasts[index]
            var steer = beast.route.steer(beast.character, delta)
            beast.character.step(
                steer[0], steer[1], delta, ground, lots, obstacles
            )
            var at = beast.character.position
            ref node = scene.node(beast.node)
            node.set_position(at.x, at.y, at.z)
            node.set_rotation_from_axis_angle(
                Vector3(0, 1, 0), facing_turn(beast.character.heading)
            )
            scene.meshes[beast.mesh].geometry = self.books[beast.book].frame(
                beast.character
            )

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
