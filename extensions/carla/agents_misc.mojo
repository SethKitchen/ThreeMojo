# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The shared pieces of CARLA's navigation agents.

This module holds the road options that the planners give each waypoint,
the three behavior types of the behavior agent, and CARLA's helper
functions from `agents/tools/misc.py`.

The sources are CARLA's `PythonAPI/carla/agents/tools/misc.py`,
`agents/navigation/local_planner.py` (`RoadOption`) and
`agents/navigation/behavior_types.py`, checked against the C++ port in
`LibCarla/source/carla/agents/navigation/Types.h` and `Misc.cpp`.

**Units.** CARLA's agents give speeds in km/h and distances in meters as
bare floats. Here a speed is a `Velocity`, a distance a `Length`, a time
a `Duration` and an angle an `Angle`. The math runs in `Float64`, as
Python's floats do.

**Not ported.** `draw_waypoints` draws debug arrows in the simulator.
This port has no debug drawing.
"""

from extensions.carla.actor import ActorId
from extensions.carla.bounding_box import BoundingBox
from extensions.carla.physics.quantities import KILOMETER_PER_HOUR
from extensions.carla.transform import CarlaTransform
from extensions.carla.world import World
from math.vector3 import Vector3
from std.ffi import external_call
from std.math import cos, sin, sqrt
from units.si import (
    DEGREE,
    METER,
    RADIAN,
    SECOND,
    Angle,
    Duration,
    Length,
    Velocity,
)

# `np.finfo(float).eps`.
comptime _EPS = 2.220446049250313e-16
comptime _TO_DEGREES = 57.29577951308232


# --- road options ---------------------------------------------------------------


@fieldwise_init
struct RoadOption(Equatable, ImplicitlyCopyable, Writable):
    """How a planner moves from one lane piece to the next, CARLA's
    `RoadOption`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of CARLA's seven options.

        Returns:
            Whether the value is -1 or from 1 to 6.
        """
        return self.value == -1 or (self.value >= 1 and self.value <= 6)


comptime OPTION_VOID = RoadOption(-1)
comptime OPTION_LEFT = RoadOption(1)
comptime OPTION_RIGHT = RoadOption(2)
comptime OPTION_STRAIGHT = RoadOption(3)
comptime OPTION_LANE_FOLLOW = RoadOption(4)
comptime OPTION_CHANGE_LANE_LEFT = RoadOption(5)
comptime OPTION_CHANGE_LANE_RIGHT = RoadOption(6)


# --- behavior types ----------------------------------------------------------------


@fieldwise_init
struct BehaviorType(Equatable, ImplicitlyCopyable, Writable):
    """One of the behavior agent's three parameter sets."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names cautious, normal or aggressive.

        Returns:
            Whether the value is from 0 to 2.
        """
        return self.value >= 0 and self.value <= 2


comptime CAUTIOUS = BehaviorType(0)
comptime NORMAL = BehaviorType(1)
comptime AGGRESSIVE = BehaviorType(2)


@fieldwise_init
struct BehaviorParameters(ImplicitlyCopyable, Writable):
    """The numbers of one behavior type, `behavior_types.py`."""

    # The highest speed the agent drives at.
    var max_speed: Velocity
    # How far below the speed limit the agent keeps.
    var speed_lim_dist: Velocity
    # How much slower than a close car ahead the agent drives.
    var speed_decrease: Velocity
    # The time to collision below which the agent slows down.
    var safety_time: Duration
    # The shortest range at which the agent looks for other actors.
    var min_proximity_threshold: Length
    # The gap below which the agent brakes hard.
    var braking_distance: Length
    # Ticks left before the agent may overtake again; -1 never overtakes.
    var tailgate_counter: Int


def behavior_parameters(kind: BehaviorType) raises -> BehaviorParameters:
    """Return CARLA's numbers for a behavior type.

    Args:
        kind: `CAUTIOUS`, `NORMAL` or `AGGRESSIVE`.

    Returns:
        The parameter set of `behavior_types.py`.

    Raises:
        Error: If the kind is not valid.
    """
    if not kind.is_valid():
        raise Error("Behavior type is not valid")
    if kind == CAUTIOUS:
        return _behavior(40, 6, 12, 12, 6, 0)
    if kind == NORMAL:
        return _behavior(50, 3, 10, 10, 5, 0)
    return _behavior(70, 1, 8, 8, 4, -1)


def _behavior(
    max_speed: Float32,
    lim_dist: Float32,
    decrease: Float32,
    proximity: Float32,
    braking: Float32,
    counter: Int,
) -> BehaviorParameters:
    # Every type keeps a safety time of 3 s.
    return BehaviorParameters(
        Velocity(max_speed, KILOMETER_PER_HOUR),
        Velocity(lim_dist, KILOMETER_PER_HOUR),
        Velocity(decrease, KILOMETER_PER_HOUR),
        Duration(3, SECOND),
        Length(proximity, METER),
        Length(braking, METER),
        counter,
    )


# --- misc.py ---------------------------------------------------------------------


def kmh(speed: Velocity) -> Float64:
    """Return a speed in km/h, the unit CARLA's agents compute in.

    Args:
        speed: The speed.

    Returns:
        The speed in km/h.
    """
    return Float64(speed.to(KILOMETER_PER_HOUR))


def from_kmh(value: Float64) -> Velocity:
    """Return a speed given in km/h.

    Args:
        value: The speed in km/h.

    Returns:
        The speed.
    """
    return Velocity(Float32(value), KILOMETER_PER_HOUR)


def speed_of(velocity: Vector3) -> Velocity:
    """Return the speed of a velocity, `get_speed` on a velocity.

    Args:
        velocity: The velocity, in m/s.

    Returns:
        Its length, all three parts counted.
    """
    var x = Float64(velocity.x)
    var y = Float64(velocity.y)
    var z = Float64(velocity.z)
    return Velocity(Float32(sqrt(x * x + y * y + z * z)))


def get_speed(world: World, actor: ActorId) raises -> Velocity:
    """Return an actor's speed, `get_speed`.

    Args:
        world: The world.
        actor: The actor.

    Returns:
        The length of its velocity.

    Raises:
        Error: If the id names no living actor.
    """
    return speed_of(world.get_velocity(actor))


def trafficlight_trigger_location(
    light: CarlaTransform, trigger_volume: BoundingBox
) -> Vector3:
    """Return where a light's trigger box sits on the road,
    `get_trafficlight_trigger_location`.

    CARLA turns the point (0, 0, extent z) by the light's yaw, with a
    rotation whose y row has the wrong sign, and adds only its x and y to
    the box's center. Both are zero, so the result is the box's center in
    the world.

    Args:
        light: The light's pose.
        trigger_volume: The light's trigger box, in the light's frame.

    Returns:
        The point, in the world frame.
    """
    return light.transform_point(trigger_volume.location)


def get_trafficlight_trigger_location(
    world: World, light: ActorId
) raises -> Vector3:
    """Return where a light's trigger box sits, read from the world.

    Args:
        world: The world.
        light: The traffic light.

    Returns:
        `trafficlight_trigger_location` of its pose and trigger box.

    Raises:
        Error: If the actor is not a traffic light or a sign.
    """
    return trafficlight_trigger_location(
        world.get_transform(light), world.get_trigger_volume(light)
    )


def _acos_degrees(cosine: Float64) -> Float64:
    # `np.clip(..., -1, 1)` then `math.acos`; NaN stays NaN.
    var c = cosine
    if c > 1.0:
        c = 1.0
    elif c < -1.0:
        c = -1.0
    return external_call["acos", Float64](c) * _TO_DEGREES


def is_within_distance(
    target: CarlaTransform,
    reference: CarlaTransform,
    max_distance: Length,
    angle_interval: Optional[Tuple[Angle, Angle]] = None,
) -> Bool:
    """Return whether a target is near a reference and at an angle,
    `is_within_distance`.

    The test is in the x-y plane. The angle is between the reference's
    forward vector and the vector to the target: 0 is ahead and 180
    behind.

    Args:
        target: The target's pose.
        reference: The reference's pose.
        max_distance: How far the target may be.
        angle_interval: The open range of angles the target must be in,
            or None to skip the angle.

    Returns:
        True if the target is within 0.001 m, or within the distance and
        the angle range.
    """
    var dx = Float64(target.location.x) - Float64(reference.location.x)
    var dy = Float64(target.location.y) - Float64(reference.location.y)
    var norm = sqrt(dx * dx + dy * dy)
    if norm < 0.001:
        return True
    if norm > Float64(max_distance.value):
        return False
    if not Bool(angle_interval):
        return True
    var fwd = reference.rotation.forward_vector()
    var angle = _acos_degrees(
        (Float64(fwd.x) * dx + Float64(fwd.y) * dy) / norm
    )
    var low = Float64(angle_interval.value()[0].to(DEGREE))
    var high = Float64(angle_interval.value()[1].to(DEGREE))
    return low < angle and angle < high


def compute_magnitude_angle(
    target: Vector3, current: Vector3, orientation: Angle
) -> Tuple[Length, Angle]:
    """Return the distance and angle from one point to another,
    `compute_magnitude_angle`.

    Args:
        target: The target point.
        current: The reference point.
        orientation: The reference's heading; 0 faces plus x.

    Returns:
        The distance in the x-y plane, and the angle between the heading
        and the vector to the target, from 0 to 180 degrees. Equal points
        give NaN, as numpy's division by zero does.
    """
    var dx = Float64(target.x) - Float64(current.x)
    var dy = Float64(target.y) - Float64(current.y)
    var norm = sqrt(dx * dx + dy * dy)
    var radians = Float64(orientation.to(RADIAN))
    var angle = _acos_degrees((cos(radians) * dx + sin(radians) * dy) / norm)
    return (Length(Float32(norm), METER), Angle(Float32(angle), DEGREE))


def distance_vehicle(
    waypoint: CarlaTransform, vehicle: CarlaTransform
) -> Length:
    """Return the distance from a waypoint to a vehicle in the x-y plane,
    `distance_vehicle`.

    Args:
        waypoint: The waypoint's pose.
        vehicle: The vehicle's pose.

    Returns:
        The distance.
    """
    var x = Float64(waypoint.location.x) - Float64(vehicle.location.x)
    var y = Float64(waypoint.location.y) - Float64(vehicle.location.y)
    return Length(Float32(sqrt(x * x + y * y)), METER)


def _norm(a: Vector3, b: Vector3) -> Float64:
    var x = Float64(b.x) - Float64(a.x)
    var y = Float64(b.y) - Float64(a.y)
    var z = Float64(b.z) - Float64(a.z)
    return sqrt(x * x + y * y + z * z) + _EPS


def vector(a: Vector3, b: Vector3) -> Vector3:
    """Return the unit vector from one point to another, `vector`.

    CARLA adds the double epsilon to the length, so equal points give a
    zero vector.

    Args:
        a: The start.
        b: The end.

    Returns:
        The unit vector.
    """
    var norm = _norm(a, b)
    return Vector3(
        Float32((Float64(b.x) - Float64(a.x)) / norm),
        Float32((Float64(b.y) - Float64(a.y)) / norm),
        Float32((Float64(b.z) - Float64(a.z)) / norm),
    )


def compute_distance(a: Vector3, b: Vector3) -> Length:
    """Return the distance between two points, `compute_distance`.

    Args:
        a: One point.
        b: The other.

    Returns:
        The distance plus the double epsilon, as CARLA adds it.
    """
    return Length(Float32(_norm(a, b)), METER)


def positive(speed: Velocity) -> Velocity:
    """Return a speed if it is more than zero, else zero, `positive`.

    Args:
        speed: The speed.

    Returns:
        The speed or zero.
    """
    if speed.value > 0.0:
        return speed
    return Velocity(0)
