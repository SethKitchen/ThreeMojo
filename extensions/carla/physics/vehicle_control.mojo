# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""How a vehicle is driven, and what it reports.

`VehicleControl`, `VehicleAckermannControl`,
`AckermannControllerSettings`, `VehicleTelemetryData` and
`WheelTelemetryData` are CARLA's records from `LibCarla/source/carla/rpc`,
with CARLA's field names and defaults. `VehicleFailureState` is
`rpc/VehicleFailureState.h`.

`AckermannController` is CARLA's Ackermann controller, from CARLA's
simulator plugin, `Carla/Vehicle/AckermannController.cpp`, line by line. It turns a target steer, steer speed, speed, acceleration
and jerk into a throttle, a brake, a steer and a reverse flag. The steer
moves toward its target at the steer speed. A speed PID gives a target
acceleration, clipped to the requested acceleration or, when that is zero,
to 3 m/s^2 up and 8 m/s^2 down. An acceleration PID gives a pedal
position from minus one to one. Both PIDs clamp their integral and their
output to minus one to one, as CARLA's `PID` does. The measured
acceleration is smoothed: four parts the last value to one part the new.
"""

from extensions.carla.physics.quantities import Jerk
from units.si import (
    Acceleration,
    Angle,
    AngularVelocity,
    Duration,
    RADIAN,
    Velocity,
)


@fieldwise_init
struct Gear(Equatable, ImplicitlyCopyable, Writable):
    """A gear: minus one is reverse, zero neutral, one and up forward."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this can name a gear.

        Returns:
            Whether the value is minus one or more.
        """
        return self.value >= -1


comptime REVERSE = Gear(-1)
comptime NEUTRAL = Gear(0)


@fieldwise_init
struct VehicleFailureState(Equatable, ImplicitlyCopyable, Writable):
    """Why a vehicle stopped working, `rpc::VehicleFailureState`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of CARLA's four states.

        Returns:
            Whether the value is 0 to 3.
        """
        return self.value >= 0 and self.value <= 3


comptime NO_FAILURE = VehicleFailureState(0)
comptime ROLLOVER = VehicleFailureState(1)
comptime ENGINE_FAILURE = VehicleFailureState(2)
comptime TIRE_PUNCTURE = VehicleFailureState(3)


@fieldwise_init
struct VehicleControl(Equatable, ImplicitlyCopyable, Writable):
    """The pedals, the wheel and the gear stick, `rpc::VehicleControl`."""

    # Zero to one.
    var throttle: Float32
    # Minus one, full left, to one, full right.
    var steer: Float32
    # Zero to one.
    var brake: Float32
    var hand_brake: Bool
    var reverse: Bool
    var manual_gear_shift: Bool
    # Read only when `manual_gear_shift` is set.
    var gear: Gear

    def __init__(out self):
        """Create CARLA's default control: everything released, gear 0."""
        self.throttle = 0
        self.steer = 0
        self.brake = 0
        self.hand_brake = False
        self.reverse = False
        self.manual_gear_shift = False
        self.gear = NEUTRAL

    def check(self) raises:
        """Refuse a control a vehicle cannot take.

        Raises:
            Error: If the throttle or brake is outside zero to one, the
                steer is outside minus one to one, or the gear is not
                valid.
        """
        if not (self.throttle >= 0 and self.throttle <= 1):
            raise Error("Throttle must be from zero to one")
        if not (self.steer >= -1 and self.steer <= 1):
            raise Error("Steer must be from minus one to one")
        if not (self.brake >= 0 and self.brake <= 1):
            raise Error("Brake must be from zero to one")
        if not self.gear.is_valid():
            raise Error("Gear is not valid")

    def write_to(self, mut writer: Some[Writer]):
        """Write the control as CARLA prints it.

        Args:
            writer: The destination.
        """
        writer.write(
            "VehicleControl(throttle=",
            self.throttle,
            ", steer=",
            self.steer,
            ", brake=",
            self.brake,
            ", hand_brake=",
            self.hand_brake,
            ", reverse=",
            self.reverse,
            ", manual_gear_shift=",
            self.manual_gear_shift,
            ", gear=",
            self.gear.value,
            ")",
        )


@fieldwise_init
struct VehicleAckermannControl(ImplicitlyCopyable):
    """A target for the Ackermann controller,
    `rpc::VehicleAckermannControl`."""

    # The steer angle of the front wheels. Plus is right.
    var steer: Angle
    var steer_speed: AngularVelocity
    # Minus is backward.
    var speed: Velocity
    var acceleration: Acceleration
    var jerk: Jerk

    def __init__(out self):
        """Create CARLA's default target: everything zero."""
        self.steer = Angle(0)
        self.steer_speed = AngularVelocity(0)
        self.speed = Velocity(0)
        self.acceleration = Acceleration(0)
        self.jerk = Jerk(0)


@fieldwise_init
struct AckermannControllerSettings(Equatable, ImplicitlyCopyable):
    """The gains of the two PIDs, `rpc::AckermannControllerSettings`."""

    var speed_kp: Float32
    var speed_ki: Float32
    var speed_kd: Float32
    var accel_kp: Float32
    var accel_ki: Float32
    var accel_kd: Float32

    @staticmethod
    def controller_default() -> AckermannControllerSettings:
        """Return the gains a new controller starts with.

        Returns:
            Speed 0.15, 0 and 0.25, and acceleration 0.01, 0 and 0.01, as
            CARLA's Ackermann controller constructs its two PIDs.
        """
        return AckermannControllerSettings(0.15, 0.0, 0.25, 0.01, 0.0, 0.01)


@fieldwise_init
struct WheelTelemetryData(ImplicitlyCopyable):
    """One wheel's slip and spin, `rpc::WheelTelemetryData`."""

    # The slip angle.
    var lat_slip: Angle
    # The slip ratio.
    var long_slip: Float32
    # The wheel's spin.
    var omega: AngularVelocity


@fieldwise_init
struct VehicleTelemetryData(Copyable, Movable):
    """What a vehicle reports, `rpc::VehicleTelemetryData`."""

    # Along the vehicle's forward axis.
    var speed: Velocity
    var steer: Float32
    var throttle: Float32
    var brake: Float32
    var engine_rpm: AngularVelocity
    var gear: Gear
    var wheels: List[WheelTelemetryData]


struct PID(ImplicitlyCopyable):
    """CARLA's `PID` from `AckermannController.h`.

    The derivative acts on the measurement, not on the error, so a jump
    of the target gives no kick. The integral and the output are clamped
    to minus one to one.
    """

    var kp: Float32
    var ki: Float32
    var kd: Float32
    var set_point: Float32
    var integral: Float32
    var last_input: Float32

    def __init__(out self, kp: Float32, ki: Float32, kd: Float32):
        """Create a PID with its state at zero.

        Args:
            kp: The proportional gain.
            ki: The integral gain.
            kd: The derivative gain.
        """
        self.kp = kp
        self.ki = ki
        self.kd = kd
        self.set_point = 0
        self.integral = 0
        self.last_input = 0

    def run(mut self, input: Float32, dt: Float32) -> Float32:
        """Run one step, `PID::Run`.

        Args:
            input: The measurement.
            dt: The step, in seconds. It must be more than zero.

        Returns:
            The output, from minus one to one.
        """
        var error = self.set_point - input
        var proportional = self.kp * error
        self.integral = _clamp(self.integral + self.ki * error * dt, -1, 1)
        var derivative = (-self.kd * (input - self.last_input)) / dt
        self.last_input = input
        return _clamp(proportional + self.integral + derivative, -1, 1)

    def reset(mut self):
        """Forget the state, `PID::Reset`."""
        self.integral = 0
        self.last_input = 0


def _clamp(value: Float32, low: Float32, high: Float32) -> Float32:
    return max(low, min(high, value))


def _sign(value: Float32) -> Float32:
    """The sign function: minus one, zero or one."""
    if value > 0:
        return 1
    if value < 0:
        return -1
    return 0


struct AckermannController(ImplicitlyCopyable):
    """CARLA's Ackermann controller."""

    var speed_controller: PID
    var acceleration_controller: PID
    var user_target: VehicleAckermannControl
    # In radians, rad/s, m/s, m/s^2 and m/s^3.
    var target_steer: Float32
    var target_steer_speed: Float32
    var target_speed: Float32
    var target_acceleration: Float32
    var target_jerk: Float32
    var max_accel: Float32
    var max_decel: Float32
    var steer: Float32
    var throttle: Float32
    var brake: Float32
    var reverse: Bool
    var speed_control_accel_delta: Float32
    var speed_control_accel_target: Float32
    var accel_control_pedal_delta: Float32
    var accel_control_pedal_target: Float32
    var delta_time: Float32
    # In radians.
    var vehicle_max_steering: Float32
    var vehicle_steer: Float32
    var vehicle_speed: Float32
    var vehicle_acceleration: Float32
    var last_vehicle_speed: Float32
    var last_vehicle_acceleration: Float32

    def __init__(out self):
        """Create a controller with CARLA's gains and limits."""
        var gains = AckermannControllerSettings.controller_default()
        self.speed_controller = PID(
            gains.speed_kp, gains.speed_ki, gains.speed_kd
        )
        self.acceleration_controller = PID(
            gains.accel_kp, gains.accel_ki, gains.accel_kd
        )
        self.user_target = VehicleAckermannControl()
        self.target_steer = 0
        self.target_steer_speed = 0
        self.target_speed = 0
        self.target_acceleration = 0
        self.target_jerk = 0
        self.max_accel = 3
        self.max_decel = 8
        self.steer = 0
        self.throttle = 0
        self.brake = 0
        self.reverse = False
        self.speed_control_accel_delta = 0
        self.speed_control_accel_target = 0
        self.accel_control_pedal_delta = 0
        self.accel_control_pedal_target = 0
        self.delta_time = 0
        self.vehicle_max_steering = 0
        self.vehicle_steer = 0
        self.vehicle_speed = 0
        self.vehicle_acceleration = 0
        self.last_vehicle_speed = 0
        self.last_vehicle_acceleration = 0

    def settings(self) -> AckermannControllerSettings:
        """Return the gains, `GetSettings`.

        Returns:
            The six gains.
        """
        return AckermannControllerSettings(
            self.speed_controller.kp,
            self.speed_controller.ki,
            self.speed_controller.kd,
            self.acceleration_controller.kp,
            self.acceleration_controller.ki,
            self.acceleration_controller.kd,
        )

    def apply_settings(mut self, settings: AckermannControllerSettings):
        """Set the gains, `ApplySettings`.

        Args:
            settings: The six gains.
        """
        self.speed_controller.kp = settings.speed_kp
        self.speed_controller.ki = settings.speed_ki
        self.speed_controller.kd = settings.speed_kd
        self.acceleration_controller.kp = settings.accel_kp
        self.acceleration_controller.ki = settings.accel_ki
        self.acceleration_controller.kd = settings.accel_kd

    def set_target_point(mut self, target: VehicleAckermannControl):
        """Take a new target, `SetTargetPoint`.

        Args:
            target: The target. Its steer is clamped to the vehicle's
                largest steer angle.
        """
        self.user_target = target
        self.target_steer = _clamp(
            target.steer.value,
            -self.vehicle_max_steering,
            self.vehicle_max_steering,
        )
        self.target_steer_speed = abs(target.steer_speed.value)
        self.target_speed = target.speed.value
        self.target_acceleration = abs(target.acceleration.value)
        self.target_jerk = abs(target.jerk.value)

    def reset(mut self):
        """Forget the state, `Reset`."""
        self.speed_controller.reset()
        self.acceleration_controller.reset()
        self.steer = 0
        self.throttle = 0
        self.brake = 0
        self.reverse = False
        self.speed_control_accel_delta = 0
        self.speed_control_accel_target = 0
        self.accel_control_pedal_delta = 0
        self.accel_control_pedal_target = 0
        self.vehicle_speed = 0
        self.vehicle_acceleration = 0
        self.last_vehicle_speed = 0
        self.last_vehicle_acceleration = 0

    def update_vehicle_physics(mut self, max_steer_angle: Angle):
        """Take the vehicle's largest steer angle, `UpdateVehiclePhysics`.

        Args:
            max_steer_angle: The first wheel's `max_steer_angle`.
        """
        self.vehicle_max_steering = max_steer_angle.to(RADIAN)

    def update_vehicle_state(
        mut self, forward_speed: Velocity, applied_steer: Float32, dt: Duration
    ):
        """Measure the vehicle, `UpdateVehicleState`.

        Args:
            forward_speed: The speed along the vehicle's forward axis.
            applied_steer: The steer of the last control applied, minus
                one to one.
            dt: The step. It must be more than zero.
        """
        self.last_vehicle_speed = self.vehicle_speed
        self.last_vehicle_acceleration = self.vehicle_acceleration
        self.delta_time = dt.value
        self.vehicle_steer = applied_steer * self.vehicle_max_steering
        self.vehicle_speed = forward_speed.value
        var current = (
            self.vehicle_speed - self.last_vehicle_speed
        ) / self.delta_time
        self.vehicle_acceleration = (
            4 * self.last_vehicle_acceleration + current
        ) / 5

    def run_loop(mut self, mut control: VehicleControl):
        """Run one step and write the control, `RunLoop`.

        Args:
            control: Receives the throttle, brake, steer and reverse.
        """
        self._run_control_steering()
        if not self._run_control_full_stop():
            self._run_control_reverse()
            self._run_control_speed()
            self._run_control_acceleration()
            self._update_vehicle_control_command()
        if self.vehicle_max_steering > 0:
            control.steer = self.steer / self.vehicle_max_steering
        else:
            control.steer = 0
        control.throttle = _clamp(self.throttle, 0, 1)
        control.brake = _clamp(self.brake, 0, 1)
        control.reverse = self.reverse

    def _run_control_steering(mut self):
        if abs(self.target_steer_speed) < 0.001:
            self.steer = self.target_steer
            return
        var steer_delta = self.target_steer_speed * self.delta_time
        if abs(self.target_steer - self.vehicle_steer) < steer_delta:
            self.steer = self.target_steer
        else:
            var direction = Float32(
                1
            ) if self.target_steer > self.vehicle_steer else Float32(-1)
            self.steer = self.vehicle_steer + direction * steer_delta

    def _run_control_full_stop(mut self) -> Bool:
        var epsilon = Float32(0.1)
        if (
            abs(self.vehicle_speed) < epsilon
            and abs(self.user_target.speed.value) < epsilon
        ):
            self.brake = 1
            self.throttle = 0
            return True
        return False

    def _run_control_reverse(mut self):
        if abs(self.vehicle_speed) < 0.1:
            self.reverse = self.user_target.speed.value < 0
        elif (
            _sign(self.vehicle_speed) * _sign(self.user_target.speed.value)
            == -1
        ):
            self.target_speed = 0

    def _run_control_speed(mut self):
        self.speed_controller.set_point = self.target_speed
        self.speed_control_accel_delta = self.speed_controller.run(
            self.vehicle_speed, self.delta_time
        )
        var low = -abs(self.target_acceleration)
        var high = abs(self.target_acceleration)
        if abs(self.target_acceleration) < 0.0001:
            low = -self.max_decel
            high = self.max_accel
        self.speed_control_accel_target = _clamp(
            self.speed_control_accel_target + self.speed_control_accel_delta,
            low,
            high,
        )

    def _run_control_acceleration(mut self):
        self.acceleration_controller.set_point = self.speed_control_accel_target
        self.accel_control_pedal_delta = self.acceleration_controller.run(
            self.vehicle_acceleration, self.delta_time
        )
        self.accel_control_pedal_target = _clamp(
            self.accel_control_pedal_target + self.accel_control_pedal_delta,
            -1,
            1,
        )

    def _update_vehicle_control_command(mut self):
        var pedal = abs(self.accel_control_pedal_target)
        # Pushing forward while in reverse is braking, and the other way.
        var brakes = (self.accel_control_pedal_target < 0) != self.reverse
        if brakes:
            self.throttle = 0
            self.brake = pedal
        else:
            self.throttle = pedal
            self.brake = 0
