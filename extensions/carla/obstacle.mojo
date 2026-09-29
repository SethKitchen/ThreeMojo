# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's obstacle detector, `sensor.other.obstacle`.

The source is CARLA's simulator plugin, `Carla/Sensor/
ObstacleDetectionSensor.cpp`, and `LibCarla/source/carla/sensor/data/
ObstacleDetectionEvent.h`.

Each tick the detector sweeps a sphere of `hit_radius` from its location
along its forward vector for `distance`. The sweep passes through the
detector and its parent. With `only_dynamics`, it meets only the bodies
that move: vehicles, walkers and other dynamic or kinematic bodies.
Without it, it also meets the road and the sidewalks. The first body the
sphere touches gives a measurement: the detector, the other actor (none
for a map surface, with the surface's tag) and how far the sphere's
center traveled.

**The sweep.** The physics tier has no shape cast, so this module sweeps
the sphere by sphere tracing, the conservative-advancement pattern. At
each step it takes the smallest distance from the sphere's center to any
body, minus the radius, and moves the center that far along the path. A
convex shape is never passed through this way. The sweep stops at a
contact when that gap is below 0.1 mm, and gives up after 512 steps. A
sphere that starts in contact touches at zero. The distance to a box or a
hull is `physics.collide.signed_distance`; to a sphere or a capsule it is
the distance to the center or the segment, minus the radius; to a static
mesh it is the distance to the nearest triangle that the swept volume's
bounds can reach, with `Triangle.closest_point_to_point`.
"""

from extensions.carla.actor import (
    ActorId,
    NO_ACTOR,
)
from extensions.carla.blueprint import ActorAttributeValue
from extensions.carla.physics.body import (
    BodyId,
    STATIC,
    rotation_matrix,
)
from extensions.carla.physics.collide import signed_distance
from extensions.carla.physics.shape import (
    CAPSULE,
    MESH,
    SPHERE,
)
from extensions.carla.sensor import SemanticTag
from extensions.carla.sensor_attributes import (
    attribute_bool,
    attribute_float,
)
from extensions.carla.sensor_rays import surface_tag_of_body

from extensions.carla.world import World
from math.triangle import (
    Line3,
    Triangle,
)
from math.vector3 import Vector3
from std.math import inf
from units.si import (
    Length,
    METER,
)

comptime _CONTACT = Float32(1e-4)
comptime _MAX_STEPS = 512


struct ObstacleDescription(ImplicitlyCopyable):
    """An obstacle detector's settings, with CARLA's defaults."""

    var distance: Length
    var hit_radius: Length
    var only_dynamics: Bool
    # Kept for completeness; this port draws nothing.
    var debug_linetrace: Bool

    def __init__(out self):
        """Create the settings of `sensor.other.obstacle`: 5 m ahead, a
        0.5 m radius, every body."""
        self.distance = Length(5, METER)
        self.hit_radius = Length(0.5, METER)
        self.only_dynamics = False
        self.debug_linetrace = False

    @staticmethod
    def from_attributes(
        attributes: List[ActorAttributeValue],
    ) raises -> ObstacleDescription:
        """Read the settings from an actor's attributes, `Set`.

        Args:
            attributes: The actor's attributes.

        Returns:
            The settings. A missing attribute keeps its default.

        Raises:
            Error: Never for these inputs; the number reader's error is
                passed on.
        """
        var d = ObstacleDescription()
        d.distance = Length(attribute_float(attributes, "distance", 5), METER)
        d.hit_radius = Length(
            attribute_float(attributes, "hit_radius", 0.5), METER
        )
        d.only_dynamics = attribute_bool(attributes, "only_dynamics", False)
        d.debug_linetrace = attribute_bool(attributes, "debug_linetrace", False)
        return d


@fieldwise_init
struct SweepHit(ImplicitlyCopyable):
    """The first body a swept sphere touches."""

    var body: BodyId
    # How far the center traveled.
    var distance: Length


@fieldwise_init
struct ObstacleMeasurement(ImplicitlyCopyable):
    """One detection, CARLA's `ObstacleDetectionEvent`."""

    # The detector.
    var actor: ActorId
    # What it met, or `NO_ACTOR` for a map surface.
    var other_actor: ActorId
    var other_tag: SemanticTag
    var distance: Length


def _box_hits(t: Triangle, low: Vector3, high: Vector3) -> Bool:
    var lo = Vector3(
        min(t.a.x, min(t.b.x, t.c.x)),
        min(t.a.y, min(t.b.y, t.c.y)),
        min(t.a.z, min(t.b.z, t.c.z)),
    )
    var hi = Vector3(
        max(t.a.x, max(t.b.x, t.c.x)),
        max(t.a.y, max(t.b.y, t.c.y)),
        max(t.a.z, max(t.b.z, t.c.z)),
    )
    return (
        lo.x <= high.x
        and hi.x >= low.x
        and lo.y <= high.y
        and hi.y >= low.y
        and lo.z <= high.z
        and hi.z >= low.z
    )


def _gap(
    world: World, body: Int, near: List[Triangle], p: Vector3
) raises -> Float32:
    """The distance from a point to one body's surface."""
    ref b = world.physics.world.bodies[body]
    var kind = b.shape.kind
    if kind == MESH:
        var best = inf[DType.float32]()
        # A mesh with no triangle near the sweep is left out of it.
        for t in near:  # pragma: no branch
            best = min(best, (p - t.closest_point_to_point(p)).length())
        return best
    var at = b.shape_world_position()
    if kind == SPHERE or (kind == CAPSULE and not (b.shape.half_height > 0)):
        return (p - at).length() - b.shape.radius
    var turn = b.shape_world_rotation()
    if kind == CAPSULE:
        var half = turn.rotate(Vector3(0, 0, b.shape.half_height))
        var segment = Line3(at - half, at + half)
        return (p - segment.closest_point(p, True)).length() - b.shape.radius
    var solid = b.shape.polyhedron.transformed(at, rotation_matrix(turn))
    return signed_distance(solid, p).distance


def sweep_sphere(
    world: World,
    start: Vector3,
    direction: Vector3,
    distance: Length,
    radius: Length,
    ignore: List[BodyId],
    only_dynamics: Bool,
) raises -> Optional[SweepHit]:
    """Sweep a sphere through the world's bodies, `SweepSingle`.

    Args:
        world: The world.
        start: Where the sphere's center starts.
        direction: Which way it moves. Any length but zero.
        distance: How far it moves.
        radius: The sphere's radius.
        ignore: Bodies it passes through.
        only_dynamics: Whether it meets only bodies that are not static.

    Returns:
        The first body touched and how far the center traveled, or None.

    Raises:
        Error: If the direction has no length, or the distance or the
            radius is negative.
    """
    var length = direction.length()
    if not (length > 0):
        raise Error("A sweep needs a direction")
    if distance.value < 0 or radius.value < 0:
        raise Error("A sweep's distance and radius cannot be negative")
    var unit = direction / length
    var end = start + unit * distance.value
    var r = radius.value
    var low = Vector3(
        min(start.x, end.x) - r,
        min(start.y, end.y) - r,
        min(start.z, end.z) - r,
    )
    var high = Vector3(
        max(start.x, end.x) + r,
        max(start.y, end.y) + r,
        max(start.z, end.z) + r,
    )
    var bodies = List[Int]()
    var near = List[List[Triangle]]()
    for i in range(len(world.physics.world.bodies)):
        ref b = world.physics.world.bodies[i]
        if not b.collides or BodyId(i) in ignore:
            continue
        if only_dynamics and b.kind == STATIC:
            continue
        var kept = List[Triangle]()
        if b.shape.kind == MESH:
            # A mesh shape has a triangle at least.
            for t in b.shape.triangles:  # pragma: no branch
                if _box_hits(t, low, high):
                    kept.append(t)
            if len(kept) == 0:
                continue
        bodies.append(i)
        near.append(kept^)
    if len(bodies) == 0:
        return None
    var travelled = Float32(0)
    # The step count is a positive constant.
    for _ in range(_MAX_STEPS):  # pragma: no branch
        var p = start + unit * travelled
        var gap = inf[DType.float32]()
        var nearest = 0
        # There is a body, checked above.
        for k in range(len(bodies)):  # pragma: no branch
            var g = _gap(world, bodies[k], near[k], p) - r
            if g < gap:
                gap = g
                nearest = k
        if gap < _CONTACT:
            return SweepHit(BodyId(bodies[nearest]), Length(travelled, METER))
        travelled += gap
        if travelled > distance.value:
            return None
    return None


def detect_obstacle(
    world: World,
    sensor: ActorId,
    description: ObstacleDescription,
) raises -> Optional[ObstacleMeasurement]:
    """Run one tick of an obstacle detector, `PostPhysTick`.

    Args:
        world: The world, just ticked.
        sensor: The detector's actor.
        description: Its settings.

    Returns:
        The first obstacle ahead, or None.

    Raises:
        Error: If the sensor is not alive, or the sweep is refused.
    """
    var record = world.actor(sensor)
    var pose = world.get_transform(sensor)
    var ignore = List[BodyId]()
    if record.body.value >= 0:
        ignore.append(record.body)
    if record.parent != NO_ACTOR:
        var parent_body = world.actor(record.parent).body
        if parent_body.value >= 0:
            ignore.append(parent_body)
    var hit = sweep_sphere(
        world,
        pose.location,
        pose.rotation.forward_vector(),
        description.distance,
        description.hit_radius,
        ignore,
        description.only_dynamics,
    )
    if not Bool(hit):
        return None
    var h = hit.value()
    var other = NO_ACTOR
    # The spectator is always in the list.
    for a in world.actors:  # pragma: no branch
        if a.is_alive() and a.body == h.body:
            other = a.id
    return ObstacleMeasurement(
        sensor, other, surface_tag_of_body(world, h.body), h.distance
    )
