# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's collision sensor, `sensor.other.collision`.

The source is CARLA's simulator plugin, `Carla/Sensor/
CollisionSensor.cpp`, and `LibCarla/source/carla/sensor/data/
CollisionEvent.h`.

The sensor listens to the hits of its parent. Each collision event of the
physics tier's last tick in which the parent's body took an impulse
becomes one measurement: the parent, the other actor and the impulse that
the other gave the parent, in N s. A pair gives one measurement a frame:
the first event of the tick wins, as CARLA's registry of the frame's
collisions keeps it.

A map surface, such as the road or a sidewalk, is not an actor. Its
measurement names no actor (id zero) and carries the surface's tag, as
CARLA describes an unregistered actor as `static.<tag>`. A parent without
a body, such as a prop, has no hits.
"""

from extensions.carla.actor import ActorId, NO_ACTOR
from extensions.carla.sensor import SemanticTag
from extensions.carla.sensor_rays import surface_tag_of_body
from extensions.carla.world import World
from math.vector3 import Vector3


@fieldwise_init
struct CollisionMeasurement(ImplicitlyCopyable):
    """One hit, CARLA's `CollisionEvent`."""

    # The actor that was hit: the sensor's parent.
    var actor: ActorId
    # The actor it hit, or `NO_ACTOR` for a map surface.
    var other_actor: ActorId
    # The other's first tag, or the surface's.
    var other_tag: SemanticTag
    # The impulse the other gave the parent, in N s.
    var normal_impulse: Vector3


struct CollisionSensor(Copyable, Movable):
    """The frame's registry of reported pairs, `CollisionRegistry`."""

    var frame: Int
    # The other bodies already reported in `frame`.
    var reported: List[Int]

    def __init__(out self):
        """Create an empty registry."""
        self.frame = -1
        self.reported = List[Int]()

    def collect(
        mut self, world: World, parent: ActorId
    ) raises -> List[CollisionMeasurement]:
        """Turn the last tick's collision events into measurements,
        `OnCollisionEvent`.

        Args:
            world: The world, just ticked.
            parent: The actor the sensor is attached to.

        Returns:
            One measurement for each other body that pushed the parent in
            the tick, in the order of the events.

        Raises:
            Error: If the parent is not alive.
        """
        var body = world.actor(parent).body
        if world.frame != self.frame:
            self.frame = world.frame
            self.reported = List[Int]()
        var out = List[CollisionMeasurement]()
        if body.value < 0:
            return out^
        for e in world.physics.events:
            if e.body != body or e.other.value in self.reported:
                continue
            self.reported.append(e.other.value)
            var other = NO_ACTOR
            # The spectator is always in the list.
            for a in world.actors:  # pragma: no branch
                if a.is_alive() and a.body == e.other:
                    other = a.id
            out.append(
                CollisionMeasurement(
                    parent,
                    other,
                    surface_tag_of_body(world, e.other),
                    e.normal_impulse,
                )
            )
        return out^
