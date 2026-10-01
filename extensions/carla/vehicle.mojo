# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's vehicles: light state, doors, and what a world keeps of each.

A vehicle is a `WheeledVehicle` of the physics tier. This module adds the
state CARLA keeps beside the physics: the lights that are on, the doors
that are open, and what the road's signals told the vehicle: its speed
limit and the traffic light state it must obey.

The records are CARLA's: `LibCarla/source/carla/rpc/VehicleLightState.h`,
`VehicleDoor.h`, `VehicleWheels.h`, and the vehicle part of
`sensor/data/ActorDynamicState.h`. The default speed limit of 30 km/h is
the vehicle controller's in CARLA's simulator plugin,
`Carla/Vehicle/WheeledVehicleAIController.h`.

**The model of a vehicle.** CARLA's vehicle models are assets with their
own meshes and setups. This port gives each model a bounding box by its
base type, and CARLA's default `VehiclePhysicsControl` on four wheels
placed in that box. The boxes are this port's choice: a car is 4.8 m
long, 2.0 m wide and 1.5 m high; a van 5.8, 2.2 and 2.4; a truck 8.0,
2.6 and 3.2; a bus 11.0, 2.6 and 3.2. A model with dynamic doors has all
six: four doors, the hood and the trunk.
"""

from extensions.carla.actor import ActorId, GREEN, NO_ACTOR, TrafficLightState
from extensions.carla.bounding_box import BoundingBox
from extensions.carla.physics.simulation import VehicleId
from extensions.carla.physics.vehicle_control import (
    NO_FAILURE,
    VehicleControl,
    VehicleFailureState,
)
from extensions.carla.physics.vehicle_physics import (
    FRONT_AXLE,
    REAR_AXLE,
    VehiclePhysicsControl,
    WheelPhysicsControl,
)
from extensions.carla.sensor import BUS, CAR, SemanticTag, TRUCK
from math.vector3 import Vector3
from extensions.carla.physics.quantities import KILOMETER_PER_HOUR
from units.si import Velocity

comptime _UINT32_MAX = 4294967295


@fieldwise_init
struct VehicleLightState(Equatable, ImplicitlyCopyable, Writable):
    """The lights that are on, as flags, `rpc::VehicleLightState`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the flags fit CARLA's 32 bits.

        Returns:
            Whether the value is from 0 to 2^32 - 1.
        """
        return self.value >= 0 and self.value <= _UINT32_MAX

    def __or__(self, other: Self) -> Self:
        """Return both sets of lights.

        Args:
            other: The other lights.

        Returns:
            The union of the flags.
        """
        return VehicleLightState(self.value | other.value)

    def __and__(self, other: Self) -> Self:
        """Return the lights in both sets.

        Args:
            other: The other lights.

        Returns:
            The intersection of the flags.
        """
        return VehicleLightState(self.value & other.value)

    def has(self, light: Self) -> Bool:
        """Return whether every flag of a light is on.

        Args:
            light: One light or several.

        Returns:
            Whether all of its flags are set here.
        """
        return (self.value & light.value) == light.value


comptime LIGHTS_NONE = VehicleLightState(0)
comptime LIGHT_POSITION = VehicleLightState(0x1)
comptime LIGHT_LOW_BEAM = VehicleLightState(0x1 << 1)
comptime LIGHT_HIGH_BEAM = VehicleLightState(0x1 << 2)
comptime LIGHT_BRAKE = VehicleLightState(0x1 << 3)
comptime LIGHT_RIGHT_BLINKER = VehicleLightState(0x1 << 4)
comptime LIGHT_LEFT_BLINKER = VehicleLightState(0x1 << 5)
comptime LIGHT_REVERSE = VehicleLightState(0x1 << 6)
comptime LIGHT_FOG = VehicleLightState(0x1 << 7)
comptime LIGHT_INTERIOR = VehicleLightState(0x1 << 8)
# Such as a siren's lights.
comptime LIGHT_SPECIAL1 = VehicleLightState(0x1 << 9)
comptime LIGHT_SPECIAL2 = VehicleLightState(0x1 << 10)
comptime LIGHTS_ALL = VehicleLightState(0xFFFFFFFF)


@fieldwise_init
struct VehicleDoor(Equatable, ImplicitlyCopyable, Writable):
    """A door, `rpc::VehicleDoor`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names a door or all of them.

        Returns:
            Whether the value is from 0 to 6.
        """
        return self.value >= 0 and self.value <= 6


comptime DOOR_FRONT_LEFT = VehicleDoor(0)
comptime DOOR_FRONT_RIGHT = VehicleDoor(1)
comptime DOOR_REAR_LEFT = VehicleDoor(2)
comptime DOOR_REAR_RIGHT = VehicleDoor(3)
comptime DOOR_HOOD = VehicleDoor(4)
comptime DOOR_TRUNK = VehicleDoor(5)
comptime DOOR_ALL = VehicleDoor(6)


@fieldwise_init
struct VehicleWheelLocation(Equatable, ImplicitlyCopyable, Writable):
    """A wheel, `rpc::VehicleWheelLocation`. A two-wheeler uses 0 and 1."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names a wheel.

        Returns:
            Whether the value is from 0 to 3.
        """
        return self.value >= 0 and self.value <= 3


comptime FRONT_LEFT_WHEEL = VehicleWheelLocation(0)
comptime FRONT_RIGHT_WHEEL = VehicleWheelLocation(1)
comptime BACK_LEFT_WHEEL = VehicleWheelLocation(2)
comptime BACK_RIGHT_WHEEL = VehicleWheelLocation(3)
comptime FRONT_WHEEL = VehicleWheelLocation(0)
comptime BACK_WHEEL = VehicleWheelLocation(1)


@fieldwise_init
struct VehicleData(ImplicitlyCopyable, Writable):
    """A vehicle's part of a snapshot, CARLA's `VehicleData`."""

    var control: VehicleControl
    var speed_limit: Velocity
    var traffic_light_state: TrafficLightState
    var has_traffic_light: Bool
    var traffic_light_id: ActorId
    var failure_state: VehicleFailureState


def default_speed_limit() -> Velocity:
    """Return the speed limit a vehicle starts with.

    Returns:
        30 km/h, CARLA's vehicle controller's default.
    """
    return Velocity(30, KILOMETER_PER_HOUR)


struct VehicleRecord(Copyable, Movable):
    """What a world keeps of one vehicle beside its physics."""

    var physics: VehicleId
    var light_state: VehicleLightState
    # Open or shut, for each of the six doors; empty without dynamic doors.
    var doors_open: List[Bool]
    var speed_limit: Velocity
    var traffic_light_state: TrafficLightState
    # The light whose box the vehicle is in, or `NO_ACTOR`.
    var traffic_light: ActorId
    # A velocity held in the vehicle's frame every tick, in m/s, if set.
    var constant_velocity: Optional[Vector3]
    # Whether a control stays until the next one, CARLA's
    # `sticky_control`. Without it the control goes back to rest each tick.
    var sticky_control: Bool

    def __init__(
        out self, physics: VehicleId, dynamic_doors: Bool, sticky: Bool
    ):
        """Create a vehicle with its lights off and its doors shut.

        Args:
            physics: Its vehicle in the physics world.
            dynamic_doors: Whether its doors open.
            sticky: Whether its control stays until the next.
        """
        self.physics = physics
        self.light_state = LIGHTS_NONE
        self.doors_open = List[Bool]()
        if dynamic_doors:
            for _ in range(6):  # pragma: no branch
                self.doors_open.append(False)
        self.speed_limit = default_speed_limit()
        self.traffic_light_state = GREEN
        self.traffic_light = NO_ACTOR
        self.constant_velocity = None
        self.sticky_control = sticky

    def set_door(mut self, door: VehicleDoor, open: Bool) raises:
        """Open or shut a door, `OpenDoor` and `CloseDoor`.

        A door the model does not have is left alone, as CARLA does.

        Args:
            door: The door, or all of them.
            open: Whether to open it.

        Raises:
            Error: If the door is not valid.
        """
        if not door.is_valid():
            raise Error("Vehicle door is not valid")
        if door == DOOR_ALL:
            for i in range(len(self.doors_open)):
                self.doors_open[i] = open
        elif door.value < len(self.doors_open):
            self.doors_open[door.value] = open

    def is_door_open(self, door: VehicleDoor) raises -> Bool:
        """Return whether a door is open.

        Args:
            door: One door.

        Returns:
            Whether it is open; False for a door the model does not have.

        Raises:
            Error: If the door is not one door.
        """
        if not door.is_valid() or door == DOOR_ALL:
            raise Error("Vehicle door must name one door")
        return door.value < len(self.doors_open) and self.doors_open[door.value]


def vehicle_bounding_box(base_type: String) raises -> BoundingBox:
    """Return this port's box for a vehicle of a base type.

    Args:
        base_type: "car", "van", "truck" or "bus"; any other is a car.

    Returns:
        The box in the vehicle's frame, standing on its origin.

    Raises:
        Error: Never; the box's check is passed on.
    """
    var half = Vector3(2.4, 1.0, 0.75)
    if base_type == "van":
        half = Vector3(2.9, 1.1, 1.2)
    elif base_type == "truck":
        half = Vector3(4.0, 1.3, 1.6)
    elif base_type == "bus":
        half = Vector3(5.5, 1.3, 1.6)
    return BoundingBox(Vector3(0, 0, half.z), half)


def vehicle_semantic_tag(base_type: String) -> SemanticTag:
    """Return the tag a camera sees on a vehicle, CARLA's labels.

    Args:
        base_type: The vehicle's base type.

    Returns:
        Truck for a truck, bus for a bus, car otherwise.
    """
    if base_type == "truck":
        return TRUCK
    if base_type == "bus":
        return BUS
    return CAR


def vehicle_physics_control(box: BoundingBox) -> VehiclePhysicsControl:
    """Return CARLA's default setup on four wheels placed in a box.

    The wheels sit 0.8 m in from the box's ends and 0.15 m in from its
    sides, with their centers one wheel radius, 0.3 m, above the origin.
    The front pair steers, the rear pair has the handbrake, and every
    wheel is driven.

    Args:
        box: The vehicle's box, in its frame.

    Returns:
        The setup.
    """
    var p = VehiclePhysicsControl()
    var x = box.location.x + box.extent.x - Float32(0.8)
    var back = box.location.x - box.extent.x + Float32(0.8)
    var y = box.extent.y - Float32(0.15)
    for i in range(4):  # pragma: no branch
        var w = WheelPhysicsControl()
        var front = i < 2
        w.offset = Vector3(
            x if front else back,
            -y if i % 2 == 0 else y,
            w.wheel_radius.value,
        )
        w.axle_type = FRONT_AXLE if front else REAR_AXLE
        w.affected_by_steering = front
        w.affected_by_handbrake = not front
        p.wheels.append(w^)
    return p^
