# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A vehicle's mechanical setup: `VehiclePhysicsControl` and
`WheelPhysicsControl`.

The field names and the defaults are CARLA's, from
`LibCarla/source/carla/rpc/VehiclePhysicsControl.h` and
`WheelPhysicsControl.h`. CARLA's setup records keep lengths in
centimeters. Here every length, mass, torque and speed carries its unit,
and the defaults keep CARLA's numbers in CARLA's units: a wheel radius of
30 cm, a spring rate of 250 N/cm.

Some units are not written in CARLA. These are the ones this port
chooses:

- `spring_rate` is in N/cm, since CARLA's lengths are in centimeters.
  250 N/cm is 25 000 N/m. With the defaults, four wheels hold a 1000 kg
  car with the spring compressed by the drop limit, 10 cm, give or take
  the 50 N preload: the defaults agree.
- `spring_preload` is a force, in newtons.
- `cornering_stiffness` is the side force per degree of slip angle.
- `brake_effect` is the engine's braking torque, in N m, when the
  throttle is released at the largest engine speed.
- The x axis of `steering_curve` is the forward speed in kilometers per
  hour, the unit of CARLA's speed limits. Its y axis is the fraction of
  the steer angle allowed at that speed.
- `torque_curve` is the engine's torque map: the torque in N m against
  the engine speed in rpm. `max_torque` limits it, as a torque limiter
  does, so the engine gives the smaller of the two.

CARLA's `WheelPhysicsControl` also carries four fields the simulator
writes while it runs: `wheel_index`, `location`, `old_location` and
`velocity`. They are not a setup. `WheeledVehicle` reports them instead.
"""

from extensions.carla.physics.quantities import (
    CorneringStiffness,
    NEWTON_METER,
    NEWTON_PER_CENTIMETER,
    NEWTON_PER_DEGREE,
    REVOLUTION_PER_MINUTE,
    REVOLUTION_PER_MINUTE_PER_SECOND,
    Stiffness,
    Torque,
)
from math.vector2 import Vector2
from math.vector3 import Vector3
from std.math import isfinite
from units.si import (
    Angle,
    AngularAcceleration,
    AngularVelocity,
    Area,
    CENTIMETER,
    DEGREE,
    Duration,
    Force,
    KILOGRAM,
    KILOGRAM_SQUARE_METER,
    Length,
    Mass,
    MomentOfInertia,
    NEWTON,
    RADIAN_PER_SECOND,
    SECOND,
    SQUARE_METER,
    Velocity,
)


@fieldwise_init
struct AxleType(Equatable, ImplicitlyCopyable, Writable):
    """Which axle a wheel is on, CARLA's `axle_type` code."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the three axle types.

        Returns:
            Whether the value is 0 to 2.
        """
        return self.value >= 0 and self.value <= 2


comptime UNDEFINED_AXLE = AxleType(0)
comptime FRONT_AXLE = AxleType(1)
comptime REAR_AXLE = AxleType(2)


@fieldwise_init
struct DifferentialType(Equatable, ImplicitlyCopyable, Writable):
    """Which wheels the engine drives, CARLA's `differential_type` code."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the four differentials.

        Returns:
            Whether the value is 0 to 3.
        """
        return self.value >= 0 and self.value <= 3


# Each wheel with `affected_by_engine` gets an equal share.
comptime UNDEFINED_DIFFERENTIAL = DifferentialType(0)
# The front axle gets one minus `front_rear_split`, the rear the rest.
comptime ALL_WHEEL_DRIVE = DifferentialType(1)
comptime FRONT_WHEEL_DRIVE = DifferentialType(2)
comptime REAR_WHEEL_DRIVE = DifferentialType(3)


@fieldwise_init
struct SweepShape(Equatable, ImplicitlyCopyable, Writable):
    """How a wheel looks for the ground, CARLA's `sweep_shape` code.

    This port casts a ray for each of the three.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the three sweep shapes.

        Returns:
            Whether the value is 0 to 2.
        """
        return self.value >= 0 and self.value <= 2


comptime RAYCAST = SweepShape(0)
comptime SPHERECAST = SweepShape(1)
comptime SHAPECAST = SweepShape(2)


@fieldwise_init
struct SweepType(Equatable, ImplicitlyCopyable, Writable):
    """Which geometry a wheel's sweep reads, CARLA's `sweep_type` code."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the two sweep types.

        Returns:
            Whether the value is 0 or 1.
        """
        return self.value >= 0 and self.value <= 1


comptime SIMPLE_SWEEP = SweepType(0)
comptime COMPLEX_SWEEP = SweepType(1)


@fieldwise_init
struct TorqueCombineMethod(Equatable, ImplicitlyCopyable, Writable):
    """How an outside torque joins the engine's, CARLA's
    `external_torque_combine_method` code."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the three methods.

        Returns:
            Whether the value is 0 to 2.
        """
        return self.value >= 0 and self.value <= 2


comptime NO_COMBINE = TorqueCombineMethod(0)
comptime OVERRIDE_COMBINE = TorqueCombineMethod(1)
comptime ADDITIVE_COMBINE = TorqueCombineMethod(2)


def evaluate_curve(points: List[Vector2], x: Float32) -> Float32:
    """Evaluate a piecewise-linear curve.

    Before the first key and after the last, the curve holds the end
    value.

    Args:
        points: The keys, in order of x.
        x: Where to read the curve.

    Returns:
        The value. Zero for a curve with no keys.
    """
    if len(points) == 0:
        return 0
    if x <= points[0].x:
        return points[0].y
    for i in range(1, len(points)):
        if x <= points[i].x:
            var a = points[i - 1]
            var b = points[i]
            return a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x)
    return points[len(points) - 1].y


def curve_peak(points: List[Vector2]) -> Float32:
    """Return the largest value of a curve.

    Args:
        points: The keys.

    Returns:
        The largest y. Zero for a curve with no keys.
    """
    var best = Float32(0)
    for i in range(len(points)):
        if i == 0 or points[i].y > best:
            best = points[i].y
    return best


def _check_curve(points: List[Vector2], name: String) raises:
    for i in range(1, len(points)):
        if not (points[i].x > points[i - 1].x):
            raise Error(name + " keys must be in increasing order of x")


def _check_positive(value: Float32, name: String) raises:
    if not (isfinite(value) and value > 0):
        raise Error(name + " must be more than zero")


def _check_unit(value: Float32, name: String) raises:
    if not (value >= 0 and value <= 1):
        raise Error(name + " must be from zero to one")


@fieldwise_init
struct WheelPhysicsControl(Copyable, Movable):
    """One wheel's setup, CARLA's `rpc::WheelPhysicsControl`."""

    var axle_type: AxleType
    # Where the wheel's center is at rest, in the vehicle's frame, in
    # meters.
    var offset: Vector3
    var wheel_radius: Length
    var wheel_width: Length
    var wheel_mass: Mass
    var cornering_stiffness: CorneringStiffness
    # Scales the ground's friction.
    var friction_force_multiplier: Float32
    # How much side grip is left while skidding, zero to one.
    var side_slip_modifier: Float32
    # Faster slip than this along the wheel is slipping.
    var slip_threshold: Velocity
    # Faster slip than this across the wheel is skidding.
    var skid_threshold: Velocity
    var max_steer_angle: Angle
    var affected_by_steering: Bool
    var affected_by_brake: Bool
    var affected_by_handbrake: Bool
    var affected_by_engine: Bool
    var abs_enabled: Bool
    var traction_control_enabled: Bool
    # How much faster than the ground a wheel can spin.
    var max_wheelspin_rotation: AngularVelocity
    var external_torque_combine_method: TorqueCombineMethod
    # Kept for CARLA's API. This port's tire model does not read it.
    var lateral_slip_graph: List[Vector2]
    # The way the wheel drops, in the vehicle's frame.
    var suspension_axis: Vector3
    # Where the spring pushes, from the wheel's center, in meters.
    var suspension_force_offset: Vector3
    var suspension_max_raise: Length
    var suspension_max_drop: Length
    # One is critical damping.
    var suspension_damping_ratio: Float32
    # Zero: every wheel grips as if it held an equal share of the weight.
    # One: each wheel grips by the load on it.
    var wheel_load_ratio: Float32
    var spring_rate: Stiffness
    var spring_preload: Force
    # A visual smoothing, zero to ten. This port does not read it.
    var suspension_smoothing: Int
    # The anti-roll bar, as a fraction of the spring rate.
    var rollbar_scaling: Float32
    var sweep_shape: SweepShape
    var sweep_type: SweepType
    var max_brake_torque: Torque
    var max_hand_brake_torque: Torque

    def __init__(out self):
        """Create CARLA's default wheel."""
        self.axle_type = UNDEFINED_AXLE
        self.offset = Vector3(0, 0, 0)
        self.wheel_radius = Length(30, CENTIMETER)
        self.wheel_width = Length(30, CENTIMETER)
        self.wheel_mass = Mass(30, KILOGRAM)
        self.cornering_stiffness = CorneringStiffness(1000, NEWTON_PER_DEGREE)
        self.friction_force_multiplier = 3
        self.side_slip_modifier = 1
        self.slip_threshold = Velocity(0.2)
        self.skid_threshold = Velocity(0.2)
        self.max_steer_angle = Angle(70, DEGREE)
        self.affected_by_steering = True
        self.affected_by_brake = True
        self.affected_by_handbrake = True
        self.affected_by_engine = True
        self.abs_enabled = False
        self.traction_control_enabled = False
        self.max_wheelspin_rotation = AngularVelocity(30, RADIAN_PER_SECOND)
        self.external_torque_combine_method = NO_COMBINE
        self.lateral_slip_graph = List[Vector2]()
        self.suspension_axis = Vector3(0, 0, -1)
        self.suspension_force_offset = Vector3(0, 0, 0)
        self.suspension_max_raise = Length(10, CENTIMETER)
        self.suspension_max_drop = Length(10, CENTIMETER)
        self.suspension_damping_ratio = 0.5
        self.wheel_load_ratio = 0.5
        self.spring_rate = Stiffness(250, NEWTON_PER_CENTIMETER)
        self.spring_preload = Force(50, NEWTON)
        self.suspension_smoothing = 0
        self.rollbar_scaling = 0.15
        self.sweep_shape = RAYCAST
        self.sweep_type = SIMPLE_SWEEP
        self.max_brake_torque = Torque(1500, NEWTON_METER)
        self.max_hand_brake_torque = Torque(3000, NEWTON_METER)

    def check(self) raises:
        """Refuse a wheel no vehicle can have.

        Raises:
            Error: If a kind is not valid, a size or mass is not more than
                zero, a ratio is outside zero to one, the suspension axis
                is zero, or a torque, spring or limit is negative.
        """
        if not self.axle_type.is_valid():
            raise Error("Axle type is not valid")
        if not self.sweep_shape.is_valid():
            raise Error("Sweep shape is not valid")
        if not self.sweep_type.is_valid():
            raise Error("Sweep type is not valid")
        if not self.external_torque_combine_method.is_valid():
            raise Error("Torque combine method is not valid")
        _check_positive(self.wheel_radius.value, "Wheel radius")
        _check_positive(self.wheel_width.value, "Wheel width")
        _check_positive(self.wheel_mass.value, "Wheel mass")
        _check_unit(self.side_slip_modifier, "Side slip modifier")
        _check_unit(self.wheel_load_ratio, "Wheel load ratio")
        _check_unit(self.rollbar_scaling, "Rollbar scaling")
        if self.suspension_axis.length() == 0:
            raise Error("Suspension axis must not be zero")
        var limits = [
            self.cornering_stiffness.value,
            self.friction_force_multiplier,
            self.suspension_max_raise.value,
            self.suspension_max_drop.value,
            self.suspension_damping_ratio,
            self.spring_rate.value,
            self.spring_preload.value,
            self.max_brake_torque.value,
            self.max_hand_brake_torque.value,
            self.max_wheelspin_rotation.value,
        ]
        for value in limits:  # pragma: no branch
            if not (isfinite(value) and value >= 0):
                raise Error("A wheel's forces and limits must not be negative")
        _check_curve(self.lateral_slip_graph, "Lateral slip graph")


@fieldwise_init
struct VehiclePhysicsControl(Copyable, Movable):
    """A vehicle's setup, CARLA's `rpc::VehiclePhysicsControl`."""

    # Engine speed in rpm against torque in N m.
    var torque_curve: List[Vector2]
    var max_torque: Torque
    var max_rpm: AngularVelocity
    var idle_rpm: AngularVelocity
    var brake_effect: Torque
    # The inertia the engine spins up against when the clutch is out.
    var rev_up_moi: MomentOfInertia
    # How fast the engine slows when the clutch is out and the throttle
    # released.
    var rev_down_rate: AngularAcceleration
    var differential_type: DifferentialType
    var front_rear_split: Float32
    var use_automatic_gears: Bool
    var gear_change_time: Duration
    var final_ratio: Float32
    var forward_gear_ratios: List[Float32]
    var reverse_gear_ratios: List[Float32]
    var change_up_rpm: AngularVelocity
    var change_down_rpm: AngularVelocity
    var transmission_efficiency: Float32
    var mass: Mass
    var drag_coefficient: Float32
    # Moves the center of mass from the middle of the chassis, in the
    # vehicle's frame, in meters.
    var center_of_mass: Vector3
    var chassis_width: Length
    var chassis_height: Length
    var downforce_coefficient: Float32
    # The frontal area. Zero uses the chassis width times its height.
    var drag_area: Area
    var inertia_tensor_scale: Vector3
    # Kept for CARLA's API. This port does not put bodies to sleep.
    var sleep_threshold: Float32
    var sleep_slope_limit: Float32
    # Forward speed in mph against the fraction of the steer angle.
    var steering_curve: List[Vector2]
    var wheels: List[WheelPhysicsControl]
    var use_sweep_wheel_collision: Bool

    def __init__(out self):
        """Create CARLA's default setup. It has no wheels."""
        self.torque_curve = [Vector2(0, 500), Vector2(5000, 500)]
        self.max_torque = Torque(300, NEWTON_METER)
        self.max_rpm = AngularVelocity(5000, REVOLUTION_PER_MINUTE)
        self.idle_rpm = AngularVelocity(1, REVOLUTION_PER_MINUTE)
        self.brake_effect = Torque(1, NEWTON_METER)
        self.rev_up_moi = MomentOfInertia(1, KILOGRAM_SQUARE_METER)
        self.rev_down_rate = AngularAcceleration(
            600, REVOLUTION_PER_MINUTE_PER_SECOND
        )
        self.differential_type = UNDEFINED_DIFFERENTIAL
        self.front_rear_split = 0.5
        self.use_automatic_gears = True
        self.gear_change_time = Duration(0.5, SECOND)
        self.final_ratio = 4
        self.forward_gear_ratios = [
            2.85,
            2.02,
            1.35,
            1.0,
            2.85,
            2.02,
            1.35,
            1.0,
        ]
        self.reverse_gear_ratios = [2.86, 2.86]
        self.change_up_rpm = AngularVelocity(4500, REVOLUTION_PER_MINUTE)
        self.change_down_rpm = AngularVelocity(2000, REVOLUTION_PER_MINUTE)
        self.transmission_efficiency = 0.9
        self.mass = Mass(1000, KILOGRAM)
        self.drag_coefficient = 0.3
        self.center_of_mass = Vector3(0, 0, 0)
        self.chassis_width = Length(180, CENTIMETER)
        self.chassis_height = Length(140, CENTIMETER)
        self.downforce_coefficient = 0.3
        self.drag_area = Area(0, SQUARE_METER)
        self.inertia_tensor_scale = Vector3(1, 1, 1)
        self.sleep_threshold = 10
        self.sleep_slope_limit = 0.866
        self.steering_curve = [Vector2(0, 1), Vector2(10, 0.5)]
        self.wheels = List[WheelPhysicsControl]()
        self.use_sweep_wheel_collision = False

    def check(self) raises:
        """Refuse a setup no vehicle can have.

        Raises:
            Error: If there is no wheel, a wheel is refused, the
                differential is not valid, there is no forward gear, a
                ratio or the mass is not more than zero, a fraction is
                outside zero to one, or a curve is out of order.
        """
        if len(self.wheels) == 0:
            raise Error("A vehicle needs at least one wheel")
        # `wheels` is not empty, checked above.
        for wheel in self.wheels:  # pragma: no branch
            wheel.check()
        if not self.differential_type.is_valid():
            raise Error("Differential type is not valid")
        if len(self.forward_gear_ratios) == 0:
            raise Error("A vehicle needs at least one forward gear")
        # `forward_gear_ratios` is not empty, checked above.
        for ratio in self.forward_gear_ratios:  # pragma: no branch
            _check_positive(ratio, "A gear ratio")
        for ratio in self.reverse_gear_ratios:
            _check_positive(ratio, "A gear ratio")
        _check_positive(self.final_ratio, "Final ratio")
        _check_positive(self.mass.value, "Mass")
        _check_positive(self.max_rpm.value, "Max rpm")
        _check_positive(self.rev_up_moi.value, "Rev up MOI")
        _check_unit(self.front_rear_split, "Front rear split")
        _check_unit(self.transmission_efficiency, "Transmission efficiency")
        _check_curve(self.torque_curve, "Torque curve")
        _check_curve(self.steering_curve, "Steering curve")
        if not (curve_peak(self.torque_curve) > 0):
            raise Error("Torque curve must reach above zero")
        var scale = self.inertia_tensor_scale
        if not (scale.x > 0 and scale.y > 0 and scale.z > 0):
            raise Error("Inertia tensor scale must be more than zero")

    def frontal_area(self) -> Area:
        """Return the area the drag and downforce act on.

        Returns:
            `drag_area`, or the chassis width times its height when that
            is zero: the front of the chassis box.
        """
        if self.drag_area.value > 0:
            return self.drag_area
        return self.chassis_width * self.chassis_height
