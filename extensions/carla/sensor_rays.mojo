# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What a sensor's ray meets: the actor, its tag, its normal and its motion.

CARLA's ray sensors trace a line through its physics scene and read the
actor that the line hits. This module gives them one interface,
`RayScene`, with two sources:

- `WorldRays` casts against a CARLA `World`: the road and sidewalk
  colliders, the vehicles and the walkers of the physics tier. A hit on
  an actor's body names the actor and its first semantic tag. A hit on a
  map surface names no actor, and its tag is the one that
  `World.project_point` reads for that surface.
- `MeshRays` casts against a ThreeMojo `Scene` with `core.raycaster`, as
  `extensions.carla.capture` does. The caller names the actor, the tag
  and the velocity of each mesh.

A hit also carries the velocity of the point that it meets and the
velocity of the actor, for the radar and the optical flow camera.
"""

from core.assets import Assets
from core.raycaster import Raycaster
from core.scene import Scene
from extensions.carla.actor import ActorId, NO_ACTOR
from extensions.carla.physics.body import BodyId
from extensions.carla.physics.shape import MESH
from extensions.carla.sensor import SemanticTag, UNLABELED
from extensions.carla.transform import carla_to_three, three_to_carla
from extensions.carla.world import World
from math.vector3 import Vector3
from std.collections import Dict
from units.si import Length, METER

# How far above a surface the probe ray of `surface_tag_of_body` starts.
comptime _PROBE_LIFT = Float32(0.01)


@fieldwise_init
struct SensorHit(ImplicitlyCopyable):
    """The nearest thing a sensor's ray meets, or a miss."""

    var hit: Bool
    # From the ray's origin, along its unit direction.
    var distance: Length
    # Where, in CARLA's world frame.
    var point: Vector3
    # The outward unit normal of the surface there.
    var normal: Vector3
    # The actor hit, or `NO_ACTOR` for a map surface or a miss.
    var actor: ActorId
    var tag: SemanticTag
    # The velocity of the point hit, in m/s.
    var point_velocity: Vector3
    # The velocity of the actor hit, in m/s. Zero for a map surface.
    var actor_velocity: Vector3

    @staticmethod
    def miss() -> SensorHit:
        """Return the hit of a ray that meets nothing.

        Returns:
            A miss: no actor, no tag, and zero numbers.
        """
        var zero = Vector3(0, 0, 0)
        return SensorHit(
            False, Length(0, METER), zero, zero, NO_ACTOR, UNLABELED, zero, zero
        )


trait RayScene:
    """Something a sensor's rays can meet."""

    def cast_ray(
        mut self, origin: Vector3, direction: Vector3, far: Length
    ) raises -> SensorHit:
        """Return the nearest thing along a ray.

        Args:
            origin: Where the ray starts, in CARLA's world frame.
            direction: Which way it goes. Any length but zero.
            far: How far it reaches.

        Returns:
            The nearest hit, or a miss.

        Raises:
            Error: If the direction has no length, or the scene cannot be
                tested.
        """
        ...


def _unit(direction: Vector3) raises -> Vector3:
    var length = direction.length()
    if not (length > 0):
        raise Error("A sensor ray needs a direction")
    return direction / length


struct WorldRays[world_origin: Origin[mut=False]](RayScene):
    """A `RayScene` over a CARLA `World`: its physics colliders."""

    var world: Pointer[World, Self.world_origin]
    # A body's index to its actor's index.
    var _actor_of_body: Dict[Int, Int]
    # A map surface's body index to its tag, learned on the first hit.
    var _surface_tags: Dict[Int, Int]

    def __init__(out self, world: Pointer[World, Self.world_origin]):
        """Read which body belongs to which living actor.

        Args:
            world: The world. Its actors must not change while this lives.
        """
        self.world = world
        self._actor_of_body = Dict[Int, Int]()
        self._surface_tags = Dict[Int, Int]()
        # The spectator is always in the list.
        for i in range(len(world[].actors)):  # pragma: no branch
            ref a = world[].actors[i]
            if a.is_alive() and a.body.value >= 0:
                self._actor_of_body[a.body.value] = i

    def actor_of_body(self, body: BodyId) -> ActorId:
        """Return the living actor that a body belongs to.

        Args:
            body: The body.

        Returns:
            Its actor, or `NO_ACTOR` for a map surface.
        """
        var found = self._actor_of_body.get(body.value)
        if not Bool(found):
            return NO_ACTOR
        return self.world[].actors[found.value()].id

    def cast_ray(
        mut self, origin: Vector3, direction: Vector3, far: Length
    ) raises -> SensorHit:
        """Return the nearest collider along a ray, `LineTraceSingle`.

        Args:
            origin: Where the ray starts.
            direction: Which way it goes.
            far: How far it reaches.

        Returns:
            The nearest hit, or a miss.

        Raises:
            Error: If the direction has no length.
        """
        var unit = _unit(direction)
        ref world = self.world[]
        var found = world.physics.world.raycast(origin, unit, far, BodyId(-1))
        if not Bool(found):
            return SensorHit.miss()
        var h = found.value()
        var point_velocity = world.physics.world.bodies[
            h.body.value
        ].velocity_at(h.point)
        var actor = self._actor_of_body.get(h.body.value)
        if Bool(actor):
            ref a = world.actors[actor.value()]
            var tag = UNLABELED
            if len(a.semantic_tags) > 0:
                tag = a.semantic_tags[0]
            return SensorHit(
                True,
                Length(h.distance, METER),
                h.point,
                h.normal,
                a.id,
                tag,
                point_velocity,
                world.physics.velocity(h.body),
            )
        var tag = self._surface_tags.get(h.body.value)
        if not Bool(tag):
            # The same ray through the world's own query, which tags it.
            var labelled = world.project_point(origin, unit, far).value()
            tag = labelled.label.value
            self._surface_tags[h.body.value] = tag.value()
        return SensorHit(
            True,
            Length(h.distance, METER),
            h.point,
            h.normal,
            NO_ACTOR,
            SemanticTag(tag.value()),
            point_velocity,
            Vector3(0, 0, 0),
        )


def surface_tag_of_body(world: World, body: BodyId) raises -> SemanticTag:
    """Return the tag of a body: its actor's, or its map surface's.

    A map surface's tag is read with a probe ray: from 1 cm in front of
    the surface's first triangle, back onto it, through
    `World.project_point`.

    Args:
        world: The world.
        body: The body.

    Returns:
        The actor's first tag, `UNLABELED` for an actor without one, or
        the surface's tag.

    Raises:
        Error: If the body is not in the world, or a map surface has no
            triangle the probe can find.
    """
    world.physics.world.check(body)
    # The spectator is always in the list.
    for a in world.actors:  # pragma: no branch
        if a.is_alive() and a.body == body:
            if len(a.semantic_tags) > 0:
                return a.semantic_tags[0]
            return UNLABELED
    ref shape = world.physics.world.bodies[body.value].shape
    if shape.kind != MESH:
        return UNLABELED
    var t = shape.triangles[0]
    var normal = t.normal()
    var probe = world.project_point(
        t.midpoint() + normal * _PROBE_LIFT,
        -normal,
        Length(2 * _PROBE_LIFT, METER),
    )
    if not Bool(probe):
        raise Error("A map surface's probe ray found no surface")
    return probe.value().label


struct MeshRays[
    scene_origin: Origin[mut=False], assets_origin: Origin[mut=False]
](RayScene):
    """A `RayScene` over a ThreeMojo `Scene`, cast with `core.raycaster`."""

    var scene: Pointer[Scene, Self.scene_origin]
    var assets: Pointer[Assets, Self.assets_origin]
    # One entry a mesh in `scene.meshes`.
    var actors: List[ActorId]
    var tags: List[SemanticTag]
    # Each mesh's velocity, in m/s in CARLA's frame.
    var velocities: List[Vector3]

    def __init__(
        out self,
        scene: Pointer[Scene, Self.scene_origin],
        assets: Pointer[Assets, Self.assets_origin],
        var actors: List[ActorId],
        var tags: List[SemanticTag],
        var velocities: List[Vector3],
    ) raises:
        """Name what each mesh of a scene is.

        Args:
            scene: The scene, updated.
            assets: Its geometry and materials.
            actors: The actor of each mesh, or `NO_ACTOR`.
            tags: The tag of each mesh.
            velocities: The velocity of each mesh.

        Raises:
            Error: If a list does not name one entry a mesh.
        """
        var count = len(scene[].meshes)
        if (
            len(actors) != count
            or len(tags) != count
            or len(velocities) != count
        ):
            raise Error("A mesh scene needs one actor, tag and velocity a mesh")
        self.scene = scene
        self.assets = assets
        self.actors = actors^
        self.tags = tags^
        self.velocities = velocities^

    def cast_ray(
        mut self, origin: Vector3, direction: Vector3, far: Length
    ) raises -> SensorHit:
        """Return the nearest mesh along a ray.

        Args:
            origin: Where the ray starts.
            direction: Which way it goes.
            far: How far it reaches.

        Returns:
            The nearest hit, or a miss.

        Raises:
            Error: If the direction has no length, or a mesh cannot be
                tested.
        """
        var unit = _unit(direction)
        var caster = Raycaster(
            carla_to_three(origin), carla_to_three(unit), far=far
        )
        var best = SensorHit.miss()
        for i in range(len(self.scene[].meshes)):
            var hits = caster.intersect_mesh(self.scene[], self.assets[], i)
            if len(hits) == 0:
                continue
            if best.hit and not (hits[0].distance < best.distance.value):
                continue
            best = SensorHit(
                True,
                Length(hits[0].distance, METER),
                three_to_carla(hits[0].point),
                three_to_carla(hits[0].normal),
                self.actors[i],
                self.tags[i],
                self.velocities[i],
                self.velocities[i],
            )
        return best
