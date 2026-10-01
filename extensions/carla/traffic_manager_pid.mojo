# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The traffic manager's PID controller, CARLA's `PID::RunStep`.

One step turns two errors into a vehicle's pedals and wheel. The speed
error drives the throttle or the brake, and the heading error drives the
steer:

    u = kp e + ki (e + e_prev) dt + kd (e - e_prev) / dt

with dt = 0.05 s. A positive speed command is a throttle of at most
0.85; a negative one is a brake of at most 0.7. The steer moves at most
0.15 from the last step's steer, and stays within 0.8 either way. The
clamps are C++'s `std::min` and `std::max`, so a NaN error, which a
target speed of zero gives, comes out as a NaN pedal, as in CARLA.

The errors are CARLA's: the speed error is (target - speed) / target,
and the heading error is the angle to the target point in half turns,
from -1 to 1.

Source: CARLA 1360bb9, `LibCarla/source/carla/trafficmanager/PIDController.h`,
`DataStructures.h` and `Constants.h`.
"""

from extensions.carla.traffic_manager_constants import (
    DT,
    INV_DT,
    MAX_BRAKE,
    MAX_STEERING,
    MAX_STEERING_DIFF,
    MAX_THROTTLE,
)
from units.si import Duration


@fieldwise_init
struct PIDParameters(Equatable, ImplicitlyCopyable, Writable):
    """The three gains of one PID loop, CARLA's parameter vector."""

    var kp: Float32
    var ki: Float32
    var kd: Float32


# CARLA's `LONGITUDIAL_PARAM`, `LONGITUDIAL_HIGHWAY_PARAM`, `LATERAL_PARAM`
# and `LATERAL_HIGHWAY_PARAM`.
comptime LONGITUDINAL_PARAM = PIDParameters(12.0, 0.05, 0.02)
comptime LONGITUDINAL_HIGHWAY_PARAM = PIDParameters(20.0, 0.05, 0.01)
comptime LATERAL_PARAM = PIDParameters(8.0, 0.04, 0.16)
comptime LATERAL_HIGHWAY_PARAM = PIDParameters(4.0, 0.04, 0.08)


@fieldwise_init
struct ActuationSignal(Equatable, ImplicitlyCopyable, Writable):
    """A vehicle's pedals and wheel, CARLA's `ActuationSignal`."""

    var throttle: Float32
    var brake: Float32
    var steer: Float32


@fieldwise_init
struct StateEntry(ImplicitlyCopyable, Writable):
    """A controller's state, CARLA's `StateEntry`."""

    # The simulated time of the step.
    var time_instance: Duration
    # The heading error in half turns, from -1 to 1.
    var angular_deviation: Float32
    # The speed error as a share of the target speed.
    var velocity_deviation: Float32
    var steer: Float32


def cpp_min(a: Float32, b: Float32) -> Float32:
    """Return C++'s `std::min(a, b)`: `b` if `b < a`, else `a`.

    Unlike `min`, a NaN in `a` comes back as it is.

    Args:
        a: The first value.
        b: The second value.

    Returns:
        The smaller, or `a` when they do not compare.
    """
    if b < a:
        return b
    return a


def cpp_max(a: Float32, b: Float32) -> Float32:
    """Return C++'s `std::max(a, b)`: `b` if `a < b`, else `a`.

    Args:
        a: The first value.
        b: The second value.

    Returns:
        The larger, or `a` when they do not compare.
    """
    if a < b:
        return b
    return a


def _pid(gains: PIDParameters, now: Float32, before: Float32) -> Float32:
    return (
        gains.kp * now
        + gains.ki * (now + before) * DT.value
        + gains.kd * (now - before) * INV_DT
    )


def run_step(
    present_state: StateEntry,
    previous_state: StateEntry,
    longitudinal_parameters: PIDParameters,
    lateral_parameters: PIDParameters,
) -> ActuationSignal:
    """Compute the pedals and the wheel for one step, `PID::RunStep`.

    Args:
        present_state: The errors now.
        previous_state: The errors and the steer of the last step.
        longitudinal_parameters: The speed loop's gains.
        lateral_parameters: The heading loop's gains.

    Returns:
        The throttle, the brake and the steer.
    """
    var expr_v = _pid(
        longitudinal_parameters,
        present_state.velocity_deviation,
        previous_state.velocity_deviation,
    )
    var throttle = Float32(0)
    var brake = Float32(0)
    if expr_v > 0.0:
        throttle = cpp_min(expr_v, MAX_THROTTLE)
    else:
        brake = cpp_min(abs(expr_v), MAX_BRAKE)
    var steer = _pid(
        lateral_parameters,
        present_state.angular_deviation,
        previous_state.angular_deviation,
    )
    steer = cpp_max(
        previous_state.steer - MAX_STEERING_DIFF,
        cpp_min(steer, previous_state.steer + MAX_STEERING_DIFF),
    )
    steer = cpp_max(-MAX_STEERING, cpp_min(steer, MAX_STEERING))
    return ActuationSignal(throttle, brake, steer)
