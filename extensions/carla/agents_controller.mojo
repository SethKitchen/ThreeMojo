# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The PID controllers of CARLA's agents, `controller.py`.

A `VehiclePIDController` turns a target speed and a target waypoint into
a `VehicleControl`. It runs two PID loops:

- `PIDLongitudinalController` drives the speed error, in km/h, to zero.
  A result of zero or more is throttle, capped at `max_throttle`. A
  negative result is brake, capped at `max_brake`.
- `PIDLateralController` drives the heading error to zero. The error is
  the angle, in radians, between the vehicle's forward vector and the
  vector to the waypoint in the x-y plane. It is plus when the waypoint
  is to the right. An offset moves the waypoint to the side along its
  right vector.

Each loop keeps its last ten errors. The derivative is the change of the
last two errors over `dt`, and the integral is the sum of the ten times
`dt`. With one error kept, both are zero. The result is clamped to
[-1, 1].

The steering can change by at most 0.1 in one step, and is then clamped
to `max_steering` on each side.

The source is CARLA's `PythonAPI/carla/agents/navigation/controller.py`,
checked against `LibCarla/source/carla/agents/navigation/
PIDController.cpp`. The controllers here take the vehicle's pose and
speed as arguments. CARLA's read them from the vehicle.
"""

from extensions.carla.agents_misc import kmh
from extensions.carla.physics.vehicle_control import VehicleControl
from extensions.carla.transform import CarlaTransform
from math.vector3 import Vector3
from std.ffi import external_call
from std.math import sqrt
from units.si import METER, SECOND, Duration, Length, Velocity

# The length of the error history, `deque(maxlen=10)`.
comptime _HISTORY = 10


@fieldwise_init
struct PIDGains(ImplicitlyCopyable, Writable):
    """The gains of one PID loop and its time step, CARLA's `K_P`, `K_I`,
    `K_D` and `dt`."""

    var k_p: Float64
    var k_i: Float64
    var k_d: Float64
    var dt: Duration


def _clip(value: Float64) -> Float64:
    if value > 1.0:
        return 1.0
    if value < -1.0:
        return -1.0
    return value


struct _ErrorHistory(Copyable, Movable):
    var errors: List[Float64]

    def __init__(out self):
        self.errors = List[Float64]()

    def push(mut self, error: Float64):
        if len(self.errors) == _HISTORY:
            _ = self.errors.pop(0)
        self.errors.append(error)

    def pid(self, gains: PIDGains, error: Float64) -> Float64:
        var de = 0.0
        var ie = 0.0
        var n = len(self.errors)
        var dt = Float64(gains.dt.value)
        if n >= 2:
            de = (self.errors[n - 1] - self.errors[n - 2]) / dt
            var total = 0.0
            # Two errors at least, checked above.
            for e in self.errors:  # pragma: no branch
                total += e
            ie = total * dt
        return _clip(gains.k_p * error + gains.k_d * de + gains.k_i * ie)


struct PIDLongitudinalController(Copyable, Movable):
    """Speed control with a PID loop, `PIDLongitudinalController`."""

    var gains: PIDGains
    var _history: _ErrorHistory

    def __init__(
        out self,
        gains: PIDGains = PIDGains(1.0, 0.0, 0.0, Duration(0.03, SECOND)),
    ):
        """Create a controller.

        Args:
            gains: The gains and the time step. CARLA's defaults are
                K_P 1, K_I 0, K_D 0 and dt 0.03 s.
        """
        self.gains = gains
        self._history = _ErrorHistory()

    def run_step(
        mut self, target_speed: Velocity, current_speed: Velocity
    ) -> Float64:
        """Run one step, `run_step` and `_pid_control`.

        Args:
            target_speed: The speed to reach.
            current_speed: The vehicle's speed.

        Returns:
            The throttle (plus) or brake (minus), from -1 to 1.
        """
        var error = kmh(target_speed) - kmh(current_speed)
        self._history.push(error)
        return self._history.pid(self.gains, error)

    def change_parameters(mut self, gains: PIDGains):
        """Change the gains, `change_parameters`.

        Args:
            gains: The new gains and time step.
        """
        self.gains = gains


struct PIDLateralController(Copyable, Movable):
    """Steering control with a PID loop, `PIDLateralController`."""

    var gains: PIDGains
    var offset: Length
    var _history: _ErrorHistory

    def __init__(
        out self,
        offset: Length = Length(0, METER),
        gains: PIDGains = PIDGains(1.0, 0.0, 0.0, Duration(0.03, SECOND)),
    ):
        """Create a controller.

        Args:
            offset: How far to the right of the waypoints to drive; minus
                is to the left.
            gains: The gains and the time step. CARLA's defaults are
                K_P 1, K_I 0, K_D 0 and dt 0.03 s.
        """
        self.gains = gains
        self.offset = offset
        self._history = _ErrorHistory()

    def set_offset(mut self, offset: Length):
        """Change the offset, `set_offset`.

        Args:
            offset: The new offset.
        """
        self.offset = offset

    def change_parameters(mut self, gains: PIDGains):
        """Change the gains, `change_parameters`.

        Args:
            gains: The new gains and time step.
        """
        self.gains = gains

    def run_step(
        mut self, waypoint: CarlaTransform, vehicle: CarlaTransform
    ) -> Float64:
        """Run one step, `run_step` and `_pid_control`.

        Args:
            waypoint: The target waypoint's pose.
            vehicle: The vehicle's pose.

        Returns:
            The steering, from -1 (left) to 1 (right).
        """
        var ego = vehicle.location
        var v = vehicle.rotation.forward_vector()
        var target = waypoint.location
        if self.offset.value != 0.0:
            var r = waypoint.rotation.right_vector()
            target = Vector3(
                target.x + self.offset.value * r.x,
                target.y + self.offset.value * r.y,
                target.z,
            )
        var wx = Float64(target.x) - Float64(ego.x)
        var wy = Float64(target.y) - Float64(ego.y)
        var vx = Float64(v.x)
        var vy = Float64(v.y)
        var norms = sqrt(wx * wx + wy * wy) * sqrt(vx * vx + vy * vy)
        var error = 1.0
        if norms != 0.0:
            error = external_call["acos", Float64](
                _clip((wx * vx + wy * vy) / norms)
            )
        if vx * wy - vy * wx < 0.0:
            error = -error
        self._history.push(error)
        return self._history.pid(self.gains, error)


struct VehiclePIDController(Copyable, Movable):
    """The two loops together, `VehiclePIDController`."""

    var max_throttle: Float64
    var max_brake: Float64
    var max_steering: Float64
    var past_steering: Float64
    var longitudinal: PIDLongitudinalController
    var lateral: PIDLateralController

    def __init__(
        out self,
        lateral: PIDGains,
        longitudinal: PIDGains,
        offset: Length = Length(0, METER),
        max_throttle: Float64 = 0.75,
        max_brake: Float64 = 0.3,
        max_steering: Float64 = 0.8,
        past_steering: Float64 = 0.0,
    ):
        """Create the controller.

        Args:
            lateral: The steering loop's gains.
            longitudinal: The speed loop's gains.
            offset: How far to the right of the waypoints to drive.
            max_throttle: The highest throttle, 0.75 by default.
            max_brake: The highest brake, 0.3 by default.
            max_steering: The highest steering on each side, 0.8 by
                default.
            past_steering: The vehicle's steering now. CARLA reads it from
                the vehicle's control.
        """
        self.max_throttle = max_throttle
        self.max_brake = max_brake
        self.max_steering = max_steering
        self.past_steering = past_steering
        self.longitudinal = PIDLongitudinalController(longitudinal)
        self.lateral = PIDLateralController(offset, lateral)

    def run_step(
        mut self,
        target_speed: Velocity,
        waypoint: CarlaTransform,
        vehicle: CarlaTransform,
        current_speed: Velocity,
    ) -> VehicleControl:
        """Run both loops once, `run_step`.

        Args:
            target_speed: The speed to reach.
            waypoint: The target waypoint's pose.
            vehicle: The vehicle's pose.
            current_speed: The vehicle's speed.

        Returns:
            The control. The hand brake and the manual gear shift are off.
        """
        var acceleration = self.longitudinal.run_step(
            target_speed, current_speed
        )
        var steering = self.lateral.run_step(waypoint, vehicle)
        var control = VehicleControl()
        if acceleration >= 0.0:
            control.throttle = Float32(min(acceleration, self.max_throttle))
            control.brake = 0.0
        else:
            control.throttle = 0.0
            control.brake = Float32(min(abs(acceleration), self.max_brake))
        if steering > self.past_steering + 0.1:
            steering = self.past_steering + 0.1
        elif steering < self.past_steering - 0.1:
            steering = self.past_steering - 0.1
        if steering >= 0.0:
            steering = min(self.max_steering, steering)
        else:
            steering = max(-self.max_steering, steering)
        control.steer = Float32(steering)
        control.hand_brake = False
        control.manual_gear_shift = False
        self.past_steering = steering
        return control

    def change_longitudinal_pid(mut self, gains: PIDGains):
        """Change the speed loop's gains, `change_longitudinal_PID`.

        Args:
            gains: The new gains.
        """
        self.longitudinal.change_parameters(gains)

    def change_lateral_pid(mut self, gains: PIDGains):
        """Change the steering loop's gains, `change_lateral_PID`.

        Args:
            gains: The new gains.
        """
        self.lateral.change_parameters(gains)

    def set_offset(mut self, offset: Length):
        """Change the lateral offset, `set_offset`.

        Args:
            offset: The new offset.
        """
        self.lateral.set_offset(offset)
