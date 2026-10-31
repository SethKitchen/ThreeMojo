# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A game humanoid's strand hair in motion, stepped and shaded each frame.

`add_game_humanoid` grows strands when it is given guides, and cards when
it is given cards. They hang from the head's bone, in the pelvis frame,
as the hair's shell does. `GameHairMotion` moves them as the person
moves:

1. It reads where the head's bone is in the world, and carries each loose
   point of every strand through the head's move since the last frame.
   So the hair lags as the head starts, swings as it stops, and sways as
   it turns. See `HairSimulation.carry`.
2. It turns gravity, the wind, the lights and the camera into the head's
   frame, so the hair falls toward the ground and is lit from where the
   lights are.
3. It steps the strands against the head and the body, writes them, and
   shades them. A groom of cards writes its moved strands into its
   ribbons.

`move_hair` moves a crowd's hair: it steps and lights the grooms of
many people at once, on threads, and then writes their meshes.

A groom that a helmet or a hood hides is not moved or shaded. It costs
nothing until it shows again. Nor is a groom whose head is farther from
the camera than `reach`, 15 m by default: it rides its head as it last
lay, and its sway is too small to see there. So a crowd pays for the
hair of the people near the camera alone.

This is not a three.js port. See Extensions.

    var person = add_game_humanoid(scene, assets, root, spec, 20000,
        cards=600)
    var motion = GameHairMotion(scene, person, spec)
    # Each frame, after the mixer and `scene.update()`:
    motion.update(scene, assets, person, lights, eye, ambient, wind)
"""

from core.assets import Assets
from core.buffer_geometry import BufferGeometry
from core.object3d import NodeId
from core.scene import Scene
from extensions.humanoid.rig.game import GameHumanoid
from extensions.humanoid.skeleton.head.frame import head_muscle_dimensions
from extensions.humanoid.skeleton.head.hair.groom import HairBody
from extensions.humanoid.skeleton.head.hair.shading import HairLight
from extensions.humanoid.skeleton.head.hair.simulation import (
    HairSimulation,
    HairWind,
)
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.rig.joints import HEAD
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from render.tasks import TaskGroup
from std.math import isfinite
from units.si import METER, Length

comptime HAIR_REACH = Float32(15.0)
"""How far from the camera hair moves by default, in meters."""


def _toward(back: Matrix4, direction: Vector3) -> Vector3:
    """Return a world direction in a frame, as a unit vector.

    Args:
        back: The frame's world matrix, inverted.
        direction: A direction in the world.

    Returns:
        The direction in the frame, of unit length, or the direction as
        it is if it has no length.
    """
    var turned = back.transform_direction(direction)
    if turned.length() == 0:
        return direction
    turned.normalize()
    return turned


struct GameHairMotion(Movable):
    """The motion of each groom of one game humanoid."""

    var simulations: List[HairSimulation]
    """One simulation per groom: those of `GameHumanoid.strands` in their
    order, then those of `GameHumanoid.cards`."""
    var poses: List[Matrix4]
    """Each groom's frame in the world when it was last moved."""
    var body: HairBody
    """What the hair falls against: the head's skin and the body's."""
    var steps: Int
    """How many simulation steps one update takes."""
    var reach: Float32
    """How far from the camera a head's hair moves, in meters."""
    var head: Vector3
    """Where the head's joint is in the grooms' frame."""

    def __init__(
        out self,
        scene: Scene,
        person: GameHumanoid,
        spec: HumanoidSpec,
        guides_only: Bool = True,
        steps: Int = 1,
        reach: Length = Length(HAIR_REACH, METER),
    ) raises:
        """Start each groom of a person at rest, where it was grown.

        Args:
            scene: The scene the person is in, updated.
            person: A game humanoid. One with no strands or cards has
                nothing to move.
            spec: The spec the person was built from.
            guides_only: True steps only the guide strands and lays each
                follower along its guide, for about a third of the cost.
            steps: Simulation steps per update, one or more. Each step is
                a thirtieth of a second.
            reach: How far from the camera a head's hair moves. Farther,
                it rides the head as it last lay.

        Raises:
            Error: If `steps` is below one, `reach` is not positive and
                finite, a groom has no node, the scene was not updated, or
                a groom is refused.
        """
        if steps < 1:
            raise Error("Hair motion needs one step an update or more")
        var meters = Float32(reach.to(METER))
        if not (isfinite(meters) and meters > 0):
            raise Error("Hair motion's reach must be positive and finite")
        self.simulations = List[HairSimulation]()
        self.poses = List[Matrix4]()
        for k in range(len(person.strands)):
            ref hair = person.strands[k]
            if not hair.node:
                raise Error("A game humanoid's groom must hang from a node")
            self.simulations.append(
                HairSimulation(hair.groom, guides_only=guides_only)
            )
            self.poses.append(scene.world_matrix(hair.node.value()))
        for k in range(len(person.cards)):
            ref cards = person.cards[k]
            if not cards.node:
                raise Error("A game humanoid's cards must hang from a node")
            self.simulations.append(
                HairSimulation(cards.groom, guides_only=guides_only)
            )
            self.poses.append(scene.world_matrix(cards.node.value()))
        self.body = HairBody(head_muscle_dimensions(spec))
        self.steps = steps
        self.reach = meters
        self.head = person.rig.joints[HEAD.value]

    def update(
        mut self,
        scene: Scene,
        mut assets: Assets,
        mut person: GameHumanoid,
        lights: List[HairLight],
        camera: Vector3,
        ambient: Vector3,
        wind: HairWind,
    ) raises:
        """Move and shade each groom that shows, for one frame.

        Call it after the scene is updated for the frame. `move_hair`
        does the same for a crowd, the people at once.

        Args:
            scene: The scene, updated.
            assets: The store of the grooms' geometry.
            person: The person this motion was made for.
            lights: The distant lights, in the world.
            camera: Where the camera is, in the world.
            ambient: The light from all round, linear.
            wind: The wind, blowing in a world direction.

        Raises:
            Error: If the person has a different number of grooms, the
                scene was not updated, or a step, write or shade fails.
        """
        var jobs = self.prepare(scene, person, 0, lights, camera, wind)
        for k in range(len(jobs)):
            self.advance(person, jobs[k], ambient)
            self.publish(assets, person, jobs[k], ambient)

    def prepare(
        mut self,
        scene: Scene,
        person: GameHumanoid,
        index: Int,
        lights: List[HairLight],
        camera: Vector3,
        wind: HairWind,
    ) raises -> List[HairJob]:
        """Carry each groom that shows through its head's move, and say
        what is left to do for it this frame.

        A groom that is hidden is passed over. A groom whose head is
        farther from the camera than `reach` rides its head: its frame
        moves on, so no swing is owed when it comes near.

        Args:
            scene: The scene, updated.
            person: The person this motion was made for.
            index: The person's place in a crowd, kept in each job.
            lights: The distant lights, in the world.
            camera: Where the camera is, in the world.
            wind: The wind, blowing in a world direction.

        Returns:
            One job for each groom to step and shade.

        Raises:
            Error: If the person has a different number of grooms, or the
                scene was not updated.
        """
        var strands = len(person.strands)
        if strands + len(person.cards) != len(self.simulations):
            raise Error("The hair motion was made for another person")
        var jobs = List[HairJob]()
        for k in range(len(self.simulations)):
            var node: NodeId
            if k < strands:
                node = person.strands[k].node.value()
            else:
                node = person.cards[k - strands].node.value()
            if not scene.get(node).visible:
                continue
            var pose = scene.world_matrix(node)
            if (pose.transform_point(self.head) - camera).length() > self.reach:
                self.poses[k] = pose^
                continue
            var back = pose.copy()
            back.invert()
            # A bone's pose is affine; its inverse's rounding is not.
            var move = back * self.poses[k]
            for column in range(3):  # pragma: no branch
                move.put(3, column, 0)
            move.put(3, 3, 1)
            self.simulations[k].carry(move)
            self.simulations[k].down = _toward(back, Vector3(0, -1, 0))
            self.poses[k] = pose^
            var local = wind
            local.direction = _toward(back, wind.direction)
            var seen = List[HairLight](capacity=len(lights))
            for light in lights:
                seen.append(
                    HairLight(_toward(back, light.direction), light.radiance)
                )
            jobs.append(
                HairJob(index, k, local, seen^, back.transform_point(camera))
            )
        return jobs^

    def advance(
        mut self, mut person: GameHumanoid, mut job: HairJob, ambient: Vector3
    ) raises:
        """Step a groom and write it; light it if it is cards.

        It touches no store and no scene, so the grooms of many people
        can advance at once.

        Args:
            person: The person this motion was made for.
            job: What `prepare` said to do. A groom of cards keeps its lit
                mesh in it.
            ambient: The light from all round, linear.

        Raises:
            Error: If a step, a write or the lighting fails.
        """
        var k = job.groom
        for _ in range(self.steps):  # pragma: no branch
            self.simulations[k].step(self.body, job.wind)
        var strands = len(person.strands)
        if k < strands:
            self.simulations[k].write(person.strands[k].groom)
            return
        self.simulations[k].write(person.cards[k - strands].groom)
        job.mesh = person.cards[k - strands].light(
            job.lights, job.camera, ambient
        )

    def publish(
        self,
        mut assets: Assets,
        mut person: GameHumanoid,
        mut job: HairJob,
        ambient: Vector3,
    ) raises:
        """Write an advanced groom's mesh to the store, shading strands.

        Args:
            assets: The store of the grooms' geometry.
            person: The person this motion was made for.
            job: A job `advance` has done.
            ambient: The light from all round, linear.

        Raises:
            Error: If the shading fails or the store does not hold the
                groom's mesh.
        """
        var k = job.groom
        var strands = len(person.strands)
        if k < strands:
            person.strands[k].shade(assets, job.lights, job.camera, ambient)
            return
        assets.geometries.replace(
            person.cards[k - strands].geometry, job.mesh.take()
        )


struct HairJob(Movable):
    """What is left to do for one groom of one person this frame."""

    var person: Int
    """The person's place in a crowd."""
    var groom: Int
    """The groom's place in its motion: strands first, then cards."""
    var wind: HairWind
    """The wind, in the groom's frame."""
    var lights: List[HairLight]
    """The lights, in the groom's frame."""
    var camera: Vector3
    """The camera, in the groom's frame."""
    var mesh: Optional[BufferGeometry]
    """A groom of cards' lit mesh, once it has advanced."""

    def __init__(
        out self,
        person: Int,
        groom: Int,
        wind: HairWind,
        var lights: List[HairLight],
        camera: Vector3,
    ):
        """Hold a groom's job, not yet advanced.

        Args:
            person: The person's place in a crowd.
            groom: The groom's place in its motion.
            wind: The wind, in the groom's frame.
            lights: The lights, in the groom's frame.
            camera: The camera, in the groom's frame.
        """
        self.person = person
        self.groom = groom
        self.wind = wind
        self.lights = lights^
        self.camera = camera
        self.mesh = None


__async def _advance_task(
    motions: MutPointer[GameHairMotion, MutAnyOrigin],
    people: MutPointer[GameHumanoid, MutAnyOrigin],
    jobs: MutPointer[HairJob, MutAnyOrigin],
    errors: MutPointer[String, MutAnyOrigin],
    first: Int,
    past: Int,
    ambient: Vector3,
):
    """Advance a run of grooms, keeping the error of each that fails."""
    for j in range(first, past):
        var p = jobs[unsafe_offset=j].person
        try:
            motions[unsafe_offset=p].advance(
                people[unsafe_offset=p], jobs[unsafe_offset=j], ambient
            )
        except e:
            errors[unsafe_offset=j] = String(e)


def move_hair(
    mut motions: List[GameHairMotion],
    scene: Scene,
    mut assets: Assets,
    mut people: List[GameHumanoid],
    lights: List[HairLight],
    camera: Vector3,
    ambient: Vector3,
    wind: HairWind,
    workers: Int = 1,
) raises:
    """Move and shade a crowd's hair for one frame, the people at once.

    Each motion carries its grooms through their heads' moves. Then the
    grooms that show and lie within reach step and are lit on `workers`
    threads, a run of grooms on each. Last, their meshes are written to
    the store. The hair moves as `GameHairMotion.update` moves it, person
    by person.

    Args:
        motions: One motion for each person, in the same order.
        scene: The scene, updated.
        assets: The store of the grooms' geometry.
        people: The people.
        lights: The distant lights, in the world.
        camera: Where the camera is, in the world.
        ambient: The light from all round, linear.
        wind: The wind, blowing in a world direction.
        workers: Threads that advance the grooms, one or more.

    Raises:
        Error: If there is not one motion for each person, there are no
            workers, a motion was made for another person, the scene was
            not updated, or a step, write or shade fails.
    """
    if len(motions) != len(people):
        raise Error("A crowd's hair needs one motion for each person")
    if workers < 1:
        raise Error("Hair motion needs one or more workers")
    var jobs = List[HairJob]()
    for p in range(len(people)):
        jobs.extend(
            motions[p].prepare(scene, people[p], p, lights, camera, wind)
        )
    var errors = List[String](length=len(jobs), fill=String())
    var tasks = min(workers, len(jobs))
    if tasks > 0:
        var group = TaskGroup()
        for task in range(tasks):  # pragma: no branch
            group.create_task(
                _advance_task(
                    motions.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                    people.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                    jobs.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                    errors.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                    task * len(jobs) // tasks,
                    (task + 1) * len(jobs) // tasks,
                    ambient,
                )
            )
        group.wait()
    for j in range(len(jobs)):
        if errors[j]:
            raise Error(errors[j])
        var p = jobs[j].person
        motions[p].publish(assets, people[p], jobs[j], ambient)
