# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The physics of a CARLA world: bodies, vehicles and walkers together.

`CarlaPhysics` is what a CARLA world ticks. It holds one `PhysicsWorld`,
the vehicles and the walkers, and names each by an id. `tick` advances a
fixed step, cut into substeps: in each, every vehicle and walker updates,
and then the world steps. The collision events of every substep are kept
until the next tick.

`carla_transform` and `carla_rotation` read a body's pose back as
CARLA's `Transform` and `Rotation`.
"""

from extensions.carla.physics.body import BodyId, RigidBody, STATIC
from extensions.carla.physics.shape import PhysicsMaterial, Shape
from extensions.carla.physics.vehicle_control import (
    VehicleAckermannControl,
    VehicleControl,
    VehicleTelemetryData,
)
from extensions.carla.physics.vehicle_physics import VehiclePhysicsControl
from extensions.carla.physics.walker import (
    Walker,
    WalkerControl,
    WalkerParameters,
)
from extensions.carla.physics.wheeled_vehicle import WheeledVehicle
from extensions.carla.physics.world import (
    CollisionEvent,
    PhysicsWorld,
    RaycastHit,
)
from extensions.carla.transform import CarlaRotation, CarlaTransform
from math.quaternion import Quaternion
from math.triangle import Triangle
from math.vector3 import Vector3
from std.math import asin, atan2
from units.si import (
    Angle,
    AngularVelocity,
    Duration,
    KILOGRAM,
    Length,
    METER,
    Mass,
    RADIAN,
    SECOND,
    Velocity,
)


@fieldwise_init
struct VehicleId(Equatable, ImplicitlyCopyable, Writable):
    """The index of a vehicle in its `CarlaPhysics`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this can name a vehicle.

        Returns:
            Whether the index is zero or more.
        """
        return self.value >= 0


@fieldwise_init
struct WalkerId(Equatable, ImplicitlyCopyable, Writable):
    """The index of a walker in its `CarlaPhysics`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this can name a walker.

        Returns:
            Whether the index is zero or more.
        """
        return self.value >= 0


def carla_rotation(q: Quaternion) -> CarlaRotation:
    """Return a rotation as CARLA's pitch, yaw and roll.

    Args:
        q: A unit quaternion in CARLA's frame.

    Returns:
        The angles whose `rotate_vector` turns as `q` does.
    """
    var m = q.to_matrix()
    ref e = m.elements
    # The third row is (-sin pitch, cos pitch sin roll, cos pitch cos roll).
    var pitch = asin(max(min(-e[2], 1), -1))
    var yaw = atan2(e[1], e[0])
    var roll = atan2(e[6], e[10])
    return CarlaRotation(
        Angle(pitch, RADIAN), Angle(yaw, RADIAN), Angle(roll, RADIAN)
    )


def carla_transform(world: PhysicsWorld, id: BodyId) raises -> CarlaTransform:
    """Return a body's pose as CARLA's `Transform`.

    Args:
        world: The world.
        id: The body.

    Returns:
        The body's origin and rotation.

    Raises:
        Error: If the id names no body.
    """
    world.check(id)
    ref body = world.bodies[id.value]
    return CarlaTransform(
        Length(body.position.x, METER),
        Length(body.position.y, METER),
        Length(body.position.z, METER),
        carla_rotation(body.rotation),
    )


struct CarlaPhysics(Movable):
    """A physics world with CARLA's vehicles and walkers in it."""

    var world: PhysicsWorld
    var vehicles: List[WheeledVehicle]
    var walkers: List[Walker]
    # The collision events of the last tick.
    var events: List[CollisionEvent]

    def __init__(out self):
        """Create an empty world."""
        self.world = PhysicsWorld()
        self.vehicles = List[WheeledVehicle]()
        self.walkers = List[Walker]()
        self.events = List[CollisionEvent]()

    def add_static_mesh(
        mut self, var triangles: List[Triangle], material: PhysicsMaterial
    ) raises -> BodyId:
        """Add road, sidewalk or prop triangles that never move.

        Args:
            triangles: The triangles, in the world, in meters. Each is
                solid from its front, where (b - a) x (c - a) points.
            material: The surface.

        Returns:
            The mesh's body id.

        Raises:
            Error: If there are no triangles, or the material is refused.
        """
        material.check()
        var body = RigidBody(
            STATIC,
            Shape.mesh(triangles^),
            Mass(0, KILOGRAM),
            Vector3(0, 0, 0),
            Quaternion.identity(),
        )
        body.material = material
        return self.world.add_body(body^)

    def add_body(mut self, var body: RigidBody) raises -> BodyId:
        """Add a prop or any other body.

        Args:
            body: The body.

        Returns:
            Its id.

        Raises:
            Error: If its material is refused.
        """
        body.material.check()
        return self.world.add_body(body^)

    def add_vehicle(
        mut self,
        transform: CarlaTransform,
        bounding_box_center: Vector3,
        bounding_box_extent: Vector3,
        var physics: VehiclePhysicsControl,
    ) raises -> VehicleId:
        """Spawn a vehicle.

        Args:
            transform: Where its origin is.
            bounding_box_center: The middle of its bounding box, in its
                frame.
            bounding_box_extent: Half the size of the bounding box.
            physics: The setup.

        Returns:
            Its id.

        Raises:
            Error: If `WheeledVehicle` refuses the setup.
        """
        self.vehicles.append(
            WheeledVehicle(
                self.world,
                transform,
                bounding_box_center,
                bounding_box_extent,
                physics^,
            )
        )
        return VehicleId(len(self.vehicles) - 1)

    def add_walker(
        mut self, location: Vector3, parameters: WalkerParameters
    ) raises -> WalkerId:
        """Spawn a walker.

        Args:
            location: The middle of its capsule, in meters.
            parameters: The capsule and its movement settings.

        Returns:
            Its id.

        Raises:
            Error: If `Walker` refuses the settings.
        """
        self.walkers.append(Walker(self.world, location, parameters))
        return WalkerId(len(self.walkers) - 1)

    def _vehicle(self, id: VehicleId) raises -> Int:
        if not id.is_valid() or id.value >= len(self.vehicles):
            raise Error("Vehicle id names no vehicle")
        return id.value

    def _walker(self, id: WalkerId) raises -> Int:
        if not id.is_valid() or id.value >= len(self.walkers):
            raise Error("Walker id names no walker")
        return id.value

    def vehicle_body(self, id: VehicleId) raises -> BodyId:
        """Return the chassis body of a vehicle.

        Args:
            id: The vehicle.

        Returns:
            The body id.

        Raises:
            Error: If the id names no vehicle.
        """
        return self.vehicles[self._vehicle(id)].body

    def walker_body(self, id: WalkerId) raises -> BodyId:
        """Return the capsule body of a walker.

        Args:
            id: The walker.

        Returns:
            The body id.

        Raises:
            Error: If the id names no walker.
        """
        return self.walkers[self._walker(id)].body

    def apply_vehicle_control(
        mut self, id: VehicleId, control: VehicleControl
    ) raises:
        """Apply a `VehicleControl`.

        Args:
            id: The vehicle.
            control: The control.

        Raises:
            Error: If the id names no vehicle, or the control is refused.
        """
        self.vehicles[self._vehicle(id)].apply_control(control)

    def apply_ackermann_control(
        mut self, id: VehicleId, target: VehicleAckermannControl
    ) raises:
        """Apply a `VehicleAckermannControl`.

        Args:
            id: The vehicle.
            target: The target.

        Raises:
            Error: If the id names no vehicle.
        """
        self.vehicles[self._vehicle(id)].apply_ackermann_control(target)

    def apply_physics_control(
        mut self, id: VehicleId, var physics: VehiclePhysicsControl
    ) raises:
        """Replace a vehicle's setup.

        Args:
            id: The vehicle.
            physics: The setup.

        Raises:
            Error: If the id names no vehicle, or the setup is refused.
        """
        var i = self._vehicle(id)
        self.vehicles[i].apply_physics_control(self.world, physics^)

    def telemetry(self, id: VehicleId) raises -> VehicleTelemetryData:
        """Return a vehicle's telemetry.

        Args:
            id: The vehicle.

        Returns:
            The telemetry.

        Raises:
            Error: If the id names no vehicle.
        """
        return self.vehicles[self._vehicle(id)].telemetry(self.world)

    def apply_walker_control(
        mut self, id: WalkerId, control: WalkerControl
    ) raises:
        """Apply a `WalkerControl`.

        Args:
            id: The walker.
            control: The control.

        Raises:
            Error: If the id names no walker, or the control is refused.
        """
        self.walkers[self._walker(id)].apply_control(control)

    def transform(self, id: BodyId) raises -> CarlaTransform:
        """Return a body's pose as CARLA's `Transform`.

        Args:
            id: The body.

        Returns:
            The transform.

        Raises:
            Error: If the id names no body.
        """
        return carla_transform(self.world, id)

    def velocity(self, id: BodyId) raises -> Vector3:
        """Return a body's velocity, in m/s.

        Args:
            id: The body.

        Returns:
            The velocity of its center of mass.

        Raises:
            Error: If the id names no body.
        """
        self.world.check(id)
        return self.world.bodies[id.value].linear_velocity

    def angular_velocity(self, id: BodyId) raises -> Vector3:
        """Return a body's angular velocity, in rad/s.

        Args:
            id: The body.

        Returns:
            The angular velocity, in the world frame.

        Raises:
            Error: If the id names no body.
        """
        self.world.check(id)
        return self.world.bodies[id.value].angular_velocity

    def raycast(
        self,
        origin: Vector3,
        direction: Vector3,
        max_distance: Length,
    ) raises -> Optional[RaycastHit]:
        """Return the nearest shape a ray meets.

        Args:
            origin: Where the ray starts.
            direction: Which way it goes.
            max_distance: How far it reaches.

        Returns:
            The hit, or None.

        Raises:
            Error: If the direction is zero.
        """
        return self.world.raycast(origin, direction, max_distance, BodyId(-1))

    def tick(mut self, dt: Duration, substeps: Int) raises:
        """Advance the world by one fixed step.

        External forces and torques present at tick entry act through every
        substep. The accumulators are cleared after the tick;
        vehicle and walker forces are rebuilt for each substep.

        Args:
            dt: The step, CARLA's `fixed_delta_seconds`.
            substeps: How many physics steps it is cut into. One or more.

        Raises:
            Error: If the step is not more than zero, or `substeps` is
                less than one.
        """
        if substeps < 1:
            raise Error("A tick needs at least one substep")
        if not (dt.value > 0):
            raise Error("A tick must be more than zero")
        var h = Duration(dt.value / Float32(substeps), SECOND)
        self.events = List[CollisionEvent]()
        # External forces belong to the whole tick. The world clears its
        # accumulators after each substep; vehicle forces are rebuilt.
        var forces = List[Vector3]()
        var torques = List[Vector3]()
        for body in self.world.bodies:
            forces.append(body.force)
            torques.append(body.torque)
        # `substeps` is one or more, checked above.
        for _ in range(substeps):  # pragma: no branch
            for i in range(len(forces)):
                self.world.bodies[i].force = forces[i]
                self.world.bodies[i].torque = torques[i]
            for i in range(len(self.vehicles)):
                self.vehicles[i].update(self.world, h)
            for i in range(len(self.walkers)):
                self.walkers[i].update(self.world, h)
            self.world.step(h)
            self.events.extend(self.world.events.copy())
