# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA physics: the vehicle setup, the Ackermann controller and the
wheeled vehicle.

The expectations are worked from vehicle dynamics by hand: the spring
compression that holds the weight, the stopping distance of a brake
torque (v^2 / 2a with a = T / (r m)) or of a tire's grip (v^2 / 2 mu g),
the speed at which the engine reaches a shift point or its limit
(omega_engine r / (gear final)), the speed where the drive force meets
the drag (F = rho Cd A v^2 / 2), the roll down a slope, and the yaw rate
of a bicycle model. The PID and controller values are CARLA's formulas
worked by hand.
"""

from extensions.carla.physics.body import BodyId, DYNAMIC, RigidBody
from extensions.carla.physics.quantities import (
    CorneringStiffness,
    NEWTON_METER,
    NEWTON_PER_CENTIMETER,
    NEWTON_PER_DEGREE,
    REVOLUTION_PER_MINUTE,
    Jerk,
    Stiffness,
    Torque,
)
from extensions.carla.physics.shape import PhysicsMaterial, Shape
from extensions.carla.physics.simulation import CarlaPhysics, VehicleId
from extensions.carla.physics.vehicle_control import (
    AckermannController,
    AckermannControllerSettings,
    ENGINE_FAILURE,
    Gear,
    NEUTRAL,
    NO_FAILURE,
    PID,
    REVERSE,
    ROLLOVER,
    TIRE_PUNCTURE,
    VehicleAckermannControl,
    VehicleControl,
    VehicleFailureState,
)
from extensions.carla.physics.vehicle_physics import (
    ALL_WHEEL_DRIVE,
    AxleType,
    COMPLEX_SWEEP,
    DifferentialType,
    FRONT_AXLE,
    FRONT_WHEEL_DRIVE,
    NO_COMBINE,
    RAYCAST,
    REAR_AXLE,
    REAR_WHEEL_DRIVE,
    SPHERECAST,
    SweepShape,
    SweepType,
    TorqueCombineMethod,
    UNDEFINED_AXLE,
    UNDEFINED_DIFFERENTIAL,
    VehiclePhysicsControl,
    WheelPhysicsControl,
    curve_peak,
    evaluate_curve,
)
from extensions.carla.physics.wheeled_vehicle import WheeledVehicle
from extensions.carla.physics.world import PhysicsWorld
from extensions.carla.transform import CarlaRotation, CarlaTransform
from math.quaternion import Quaternion
from math.triangle import Triangle
from math.vector2 import Vector2
from math.vector3 import Vector3
from std.math import atan2, cos, inf, nan, pi, sin, sqrt, tan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import (
    Acceleration,
    Angle,
    AngularVelocity,
    Area,
    CENTIMETER,
    DEGREE,
    Duration,
    Force,
    KILOGRAM,
    Length,
    METER,
    Mass,
    RADIAN,
    SECOND,
    SQUARE_METER,
    Velocity,
)

comptime H = Float32(1.0 / 30.0)
comptime G = Float32(9.8)
comptime RPM = Float32(2 * pi / 60)


def _flat(size: Float32, z: Float32) -> List[Triangle]:
    var a = Vector3(-size, -size, z)
    var b = Vector3(size, -size, z)
    var c = Vector3(size, size, z)
    var d = Vector3(-size, size, z)
    return [Triangle(a, b, c), Triangle(a, c, d)]


def _car() -> VehiclePhysicsControl:
    """CARLA's defaults on four wheels: the front pair steers, the rear
    pair has the handbrake. The wheel centers rest 0.3 m above the
    origin, 1.4 m ahead and behind it, 0.8 m to each side."""
    var p = VehiclePhysicsControl()
    p.forward_gear_ratios = [3.0, 2.0, 1.4, 1.0]
    for i in range(4):
        var w = WheelPhysicsControl()
        w.offset = Vector3(
            Float32(1.4) if i < 2 else Float32(-1.4),
            Float32(-0.8) if i % 2 == 0 else Float32(0.8),
            0.3,
        )
        w.axle_type = FRONT_AXLE if i < 2 else REAR_AXLE
        w.affected_by_steering = i < 2
        w.affected_by_handbrake = i >= 2
        p.wheels.append(w^)
    return p^


def _level() -> CarlaTransform:
    return CarlaTransform(
        Length(0, METER),
        Length(0, METER),
        Length(0.05, METER),
        CarlaRotation(Angle(0, DEGREE), Angle(0, DEGREE), Angle(0, DEGREE)),
    )


def _spawn(
    mut sim: CarlaPhysics, var physics: VehiclePhysicsControl
) raises -> VehicleId:
    _ = sim.add_static_mesh(_flat(3000, 0), PhysicsMaterial.default())
    return sim.add_vehicle(
        _level(), Vector3(0, 0, 0.75), Vector3(2.3, 1.0, 0.75), physics^
    )


def _run(mut sim: CarlaPhysics, seconds: Float32) raises:
    for _ in range(Int(seconds / H + 0.5)):
        sim.tick(Duration(H, SECOND), 1)


def _speed(sim: CarlaPhysics, id: VehicleId) raises -> Float32:
    return sim.telemetry(id).speed.value


def _drive(throttle: Float32, brake: Float32) -> VehicleControl:
    var c = VehicleControl()
    c.throttle = throttle
    c.brake = brake
    return c


def _launch(mut sim: CarlaPhysics, id: VehicleId, speed: Float32) raises:
    """Settle the car on its springs, then set it moving forward."""
    _run(sim, 1)
    var body = sim.vehicle_body(id)
    sim.world.bodies[body.value].linear_velocity = Vector3(speed, 0, 0)
    for i in range(4):
        sim.vehicles[id.value].wheels[i].omega = speed / 0.3


# --- the setup --------------------------------------------------------------


def test_setup_defaults() raises:
    var p = VehiclePhysicsControl()
    assert_equal(p.max_torque.value, 300)
    assert_almost_equal(p.max_rpm.to(REVOLUTION_PER_MINUTE), 5000, atol=0.05)
    assert_almost_equal(p.idle_rpm.to(REVOLUTION_PER_MINUTE), 1, atol=1e-4)
    assert_equal(len(p.forward_gear_ratios), 8)
    assert_equal(len(p.reverse_gear_ratios), 2)
    assert_equal(p.final_ratio, 4)
    assert_equal(p.mass.value, 1000)
    assert_true(p.use_automatic_gears)
    assert_true(p.differential_type == UNDEFINED_DIFFERENTIAL)
    assert_almost_equal(p.chassis_width.value, 1.8, atol=1e-6)
    # No drag area: the chassis width times its height, 1.8 x 1.4.
    assert_almost_equal(p.frontal_area().value, 2.52, atol=1e-5)
    p.drag_area = Area(2, SQUARE_METER)
    assert_equal(p.frontal_area().value, 2)
    var w = WheelPhysicsControl()
    assert_almost_equal(w.wheel_radius.value, 0.3, atol=1e-6)
    assert_almost_equal(w.spring_rate.value, 25000, atol=1e-2)
    assert_equal(w.spring_preload.value, 50)
    assert_almost_equal(w.max_steer_angle.to(DEGREE), 70, atol=1e-4)
    assert_equal(w.max_brake_torque.value, 1500)
    assert_equal(w.max_hand_brake_torque.value, 3000)
    assert_almost_equal(w.suspension_max_drop.value, 0.1, atol=1e-6)
    assert_true(w.sweep_shape == RAYCAST)
    assert_true(w.external_torque_combine_method == NO_COMBINE)
    assert_true(w.axle_type == UNDEFINED_AXLE)
    w.check()


def test_kinds() raises:
    assert_true(FRONT_AXLE.is_valid())
    assert_false(AxleType(3).is_valid())
    assert_false(AxleType(-1).is_valid())
    assert_true(REAR_WHEEL_DRIVE.is_valid())
    assert_false(DifferentialType(4).is_valid())
    assert_false(DifferentialType(-1).is_valid())
    assert_true(SPHERECAST.is_valid())
    assert_false(SweepShape(3).is_valid())
    assert_false(SweepShape(-1).is_valid())
    assert_true(COMPLEX_SWEEP.is_valid())
    assert_false(SweepType(2).is_valid())
    assert_false(SweepType(-1).is_valid())
    assert_true(NO_COMBINE.is_valid())
    assert_false(TorqueCombineMethod(3).is_valid())
    assert_false(TorqueCombineMethod(-1).is_valid())
    assert_true(REVERSE.is_valid())
    assert_true(NEUTRAL.is_valid())
    assert_false(Gear(-2).is_valid())
    assert_true(TIRE_PUNCTURE.is_valid())
    assert_true(ENGINE_FAILURE.is_valid())
    assert_false(VehicleFailureState(4).is_valid())
    assert_false(VehicleFailureState(-1).is_valid())


def _bad_wheel(field: Int) -> WheelPhysicsControl:
    var w = WheelPhysicsControl()
    if field == 0:
        w.axle_type = AxleType(9)
    elif field == 1:
        w.sweep_shape = SweepShape(9)
    elif field == 2:
        w.sweep_type = SweepType(9)
    elif field == 3:
        w.external_torque_combine_method = TorqueCombineMethod(9)
    elif field == 4:
        w.wheel_radius = Length(0, METER)
    elif field == 5:
        w.wheel_width = Length(-1, METER)
    elif field == 6:
        w.wheel_mass = Mass(0, KILOGRAM)
    elif field == 7:
        w.side_slip_modifier = 2
    elif field == 8:
        w.wheel_load_ratio = -0.1
    elif field == 9:
        w.rollbar_scaling = 1.5
    elif field == 10:
        w.suspension_axis = Vector3(0, 0, 0)
    elif field == 11:
        w.max_brake_torque = Torque(-1, NEWTON_METER)
    elif field == 12:
        w.spring_rate = Stiffness(inf[DType.float32](), NEWTON_PER_CENTIMETER)
    else:
        w.lateral_slip_graph = [Vector2(1, 0), Vector2(0, 1)]
    return w^


def test_wheel_refusals() raises:
    for field in range(14):
        with assert_raises():
            _bad_wheel(field).check()
    # A curve in order is fine.
    var w = WheelPhysicsControl()
    w.lateral_slip_graph = [Vector2(0, 0), Vector2(1, 1)]
    w.check()


def _bad_setup(field: Int) -> VehiclePhysicsControl:
    var p = _car()
    if field == 0:
        p.wheels = List[WheelPhysicsControl]()
    elif field == 1:
        p.wheels[0].wheel_radius = Length(0, METER)
    elif field == 2:
        p.differential_type = DifferentialType(9)
    elif field == 3:
        p.forward_gear_ratios = List[Float32]()
    elif field == 4:
        p.forward_gear_ratios = [1.0, -1.0]
    elif field == 5:
        p.reverse_gear_ratios = [0.0]
    elif field == 6:
        p.final_ratio = 0
    elif field == 7:
        p.mass = Mass(nan[DType.float32](), KILOGRAM)
    elif field == 8:
        p.max_rpm = AngularVelocity(0)
    elif field == 9:
        p.rev_up_moi.value = 0
    elif field == 10:
        p.front_rear_split = 1.5
    elif field == 11:
        p.transmission_efficiency = -1
    elif field == 12:
        p.torque_curve = [Vector2(10, 1), Vector2(5, 1)]
    elif field == 13:
        p.steering_curve = [Vector2(10, 1), Vector2(10, 1)]
    elif field == 14:
        p.torque_curve = [Vector2(0, 0), Vector2(10, 0)]
    elif field == 15:
        p.inertia_tensor_scale = Vector3(0, 1, 1)
    elif field == 16:
        p.inertia_tensor_scale = Vector3(1, 0, 1)
    else:
        p.inertia_tensor_scale = Vector3(1, 1, -1)
    return p^


def test_setup_refusals() raises:
    for field in range(18):
        with assert_raises():
            _bad_setup(field).check()
    _car().check()
    # A vehicle with no reverse gear is allowed.
    var forward_only = _car()
    forward_only.reverse_gear_ratios = List[Float32]()
    forward_only.check()


def test_curves() raises:
    var curve: List[Vector2] = [Vector2(0, 1), Vector2(10, 0.5)]
    # Before, between and after the keys: held, linear, held.
    assert_equal(evaluate_curve(curve, -5), 1)
    assert_almost_equal(evaluate_curve(curve, 4), 0.8, atol=1e-6)
    assert_equal(evaluate_curve(curve, 20), 0.5)
    assert_equal(evaluate_curve(List[Vector2](), 3), 0)
    # One key holds everywhere.
    assert_equal(evaluate_curve([Vector2(0, 5)], 3), 5)
    assert_equal(curve_peak(curve), 1)
    assert_equal(curve_peak([Vector2(0, -2), Vector2(1, -1)]), -1)
    assert_equal(curve_peak(List[Vector2]()), 0)


# --- the controls -----------------------------------------------------------


def test_vehicle_control() raises:
    var c = VehicleControl()
    assert_equal(c.throttle, 0)
    assert_equal(c.gear, NEUTRAL)
    c.check()
    assert_equal(
        String(c),
        (
            "VehicleControl(throttle=0.0, steer=0.0, brake=0.0,"
            " hand_brake=False, reverse=False, manual_gear_shift=False,"
            " gear=0)"
        ),
    )
    var copy = c
    assert_true(copy == c)
    var bad = c
    bad.throttle = 1.5
    with assert_raises():
        bad.check()
    bad = c
    bad.steer = -2
    with assert_raises():
        bad.check()
    bad = c
    bad.brake = -0.5
    with assert_raises():
        bad.check()
    bad = c
    bad.gear = Gear(-3)
    with assert_raises():
        bad.check()
    var target = VehicleAckermannControl()
    assert_equal(target.speed.value, 0)
    assert_equal(target.jerk.value, 0)


def test_pid() raises:
    # kp 1, ki 0.5, kd 0.1; target 2, measured 1, dt 0.1 s:
    # P = 1, I = 0.5 * 1 * 0.1 = 0.05, D = -0.1 * (1 - 0) / 0.1 = -1.
    var pid = PID(1, 0.5, 0.1)
    pid.set_point = 2
    assert_almost_equal(pid.run(1, 0.1), 0.05, atol=1e-6)
    # Measured 1 again: P = 1, I = 0.1, D = 0; the output clamps to 1.
    assert_almost_equal(pid.run(1, 0.1), 1, atol=1e-6)
    assert_almost_equal(pid.integral, 0.1, atol=1e-6)
    # Far below: the output clamps to minus one.
    pid.set_point = -50
    assert_equal(pid.run(1, 0.1), -1)
    pid.reset()
    assert_equal(pid.integral, 0)
    assert_equal(pid.last_input, 0)


def test_ackermann_settings() raises:
    var controller = AckermannController()
    var s = controller.settings()
    assert_true(s == AckermannControllerSettings.controller_default())
    assert_almost_equal(s.speed_kp, 0.15, atol=1e-7)
    assert_almost_equal(s.speed_kd, 0.25, atol=1e-7)
    assert_almost_equal(s.accel_kp, 0.01, atol=1e-7)
    var mine = AckermannControllerSettings(1, 2, 3, 4, 5, 6)
    controller.apply_settings(mine)
    assert_true(controller.settings() == mine)


def _controller(max_steer: Float32) -> AckermannController:
    var c = AckermannController()
    c.update_vehicle_physics(Angle(max_steer, RADIAN))
    return c


def _target(
    steer: Float32, steer_speed: Float32, speed: Float32, accel: Float32
) -> VehicleAckermannControl:
    return VehicleAckermannControl(
        Angle(steer, RADIAN),
        AngularVelocity(steer_speed),
        Velocity(speed),
        Acceleration(accel),
        Jerk(0),
    )


def test_ackermann_first_step() raises:
    # From rest toward 10 m/s: the speed PID gives 0.15 * 10 = 1.5,
    # clamped to 1; the acceleration target is 1 (inside -8 to 3); the
    # acceleration PID gives 0.01 * 1 = 0.01 of throttle.
    var c = _controller(1)
    c.set_target_point(_target(2, 0, 10, 0))
    c.update_vehicle_state(Velocity(0), 0, Duration(0.1, SECOND))
    var control = VehicleControl()
    c.run_loop(control)
    assert_almost_equal(c.speed_control_accel_target, 1, atol=1e-6)
    assert_almost_equal(control.throttle, 0.01, atol=1e-6)
    assert_equal(control.brake, 0)
    assert_false(control.reverse)
    # The steer target is clamped to the 1 rad limit, and with no steer
    # speed it is reached at once: 1 / 1.
    assert_equal(control.steer, 1)


def test_ackermann_full_stop() raises:
    var c = _controller(1)
    c.set_target_point(_target(0, 0, 0.05, 0))
    c.update_vehicle_state(Velocity(0.05), 0, Duration(0.1, SECOND))
    var control = VehicleControl()
    c.run_loop(control)
    assert_equal(control.brake, 1)
    assert_equal(control.throttle, 0)
    # Moving, with a stop asked: not a full stop yet.
    c.update_vehicle_state(Velocity(5), 0, Duration(0.1, SECOND))
    c.run_loop(control)
    assert_true(control.brake > 0)


def test_ackermann_steer_speed() raises:
    # 0.5 rad/s for 0.1 s moves the steer 0.05 rad toward the target.
    var c = _controller(0.5)
    c.set_target_point(_target(0.4, -0.5, 5, 0))
    c.update_vehicle_state(Velocity(5), 0.2, Duration(0.1, SECOND))
    var control = VehicleControl()
    c.run_loop(control)
    # The applied steer 0.2 is 0.1 rad; 0.1 + 0.05 = 0.15 rad = 0.3.
    assert_almost_equal(control.steer, 0.3, atol=1e-6)
    # Toward a target on the other side.
    c.set_target_point(_target(-0.4, 0.5, 5, 0))
    c.update_vehicle_state(Velocity(5), 0.2, Duration(0.1, SECOND))
    c.run_loop(control)
    assert_almost_equal(control.steer, 0.1, atol=1e-6)
    # Within one step of the target: the target.
    c.set_target_point(_target(0.12, 0.5, 5, 0))
    c.update_vehicle_state(Velocity(5), 0.2, Duration(0.1, SECOND))
    c.run_loop(control)
    assert_almost_equal(control.steer, 0.24, atol=1e-6)
    # A vehicle that cannot steer gets no steer.
    var none = _controller(0)
    none.set_target_point(_target(0.4, 0, 5, 0))
    none.update_vehicle_state(Velocity(5), 0, Duration(0.1, SECOND))
    none.run_loop(control)
    assert_equal(control.steer, 0)


def test_ackermann_reverse() raises:
    # Standing, a negative speed selects reverse. The pedal then pushes
    # backward, which is the throttle in reverse.
    var c = _controller(1)
    c.set_target_point(_target(0, 0, -3, 0))
    c.update_vehicle_state(Velocity(0), 0, Duration(0.1, SECOND))
    var control = VehicleControl()
    c.run_loop(control)
    assert_true(control.reverse)
    assert_true(control.throttle > 0)
    assert_equal(control.brake, 0)
    # Going backward and asked for more: still the throttle. Asked to
    # go forward while going backward: the target speed becomes zero.
    c.set_target_point(_target(0, 0, 3, 0))
    c.update_vehicle_state(Velocity(-2), 0, Duration(0.1, SECOND))
    c.run_loop(control)
    assert_equal(c.target_speed, 0)
    assert_true(control.reverse)
    assert_true(control.brake > 0)
    # In reverse, a push forward is the brake.
    c.reset()
    assert_false(c.reverse)
    assert_equal(c.speed_control_accel_target, 0)


def test_ackermann_acceleration_limit() raises:
    # A requested acceleration of 0.5 clips the speed PID's target. From
    # 1 m/s toward 10: P = 0.15 x 9 = 1.35, and the derivative of the
    # measurement from the reset 0 to 1 is -0.25 x 1 / 0.1 = -2.5, so the
    # PID gives -1, and the target is clipped at -0.5.
    var c = _controller(1)
    c.set_target_point(_target(0, 0, 10, -0.5))
    c.update_vehicle_state(Velocity(1), 0, Duration(0.1, SECOND))
    var control = VehicleControl()
    c.run_loop(control)
    assert_almost_equal(c.speed_control_accel_target, -0.5, atol=1e-6)
    # The next step, measured 1 again: P = 1.35, no derivative: 1, and the
    # target climbs to -0.5 + 1, clipped at 0.5.
    c.update_vehicle_state(Velocity(1), 0, Duration(0.1, SECOND))
    c.run_loop(control)
    assert_almost_equal(c.speed_control_accel_target, 0.5, atol=1e-6)
    # Braking from 10 m/s to 0 with the default limits: -1, above -8.
    c.set_target_point(_target(0, 0, 0, 0))
    c.update_vehicle_state(Velocity(10), 0, Duration(0.1, SECOND))
    c.run_loop(control)
    assert_true(control.brake > 0)
    assert_equal(control.throttle, 0)


# --- the vehicle ------------------------------------------------------------


def test_rest_height() raises:
    # Each spring holds a quarter of 1000 kg: k x + preload = m g / 4,
    # so x = (2450 - 50) / 25000 = 0.096 m of the 0.2 m travel. The
    # wheel center then sits x - drop = -0.004 m below its rest offset,
    # 0.3 m above the ground, so the origin is 0.004 m up.
    var sim = CarlaPhysics()
    var car = _spawn(sim, _car())
    _run(sim, 3)
    var body = sim.vehicle_body(car)
    var z = sim.world.bodies[body.value].position.z
    var x = (1000 * G / 4 - 50) / 25000
    assert_almost_equal(z, 0.3 - (0.3 + x - 0.1), atol=1e-3)
    ref v = sim.vehicles[car.value]
    for w in v.wheels:
        assert_true(w.in_contact)
        assert_almost_equal(w.sprung_mass, 250, atol=1e-2)
        assert_almost_equal(w.suspension_force, 250 * G, atol=5)
        assert_almost_equal(w.compression, x, atol=1e-3)
    assert_almost_equal(_speed(sim, car), 0, atol=1e-3)
    assert_equal(sim.telemetry(car).gear, NEUTRAL)


def test_sprung_masses_follow_the_center_of_mass() raises:
    # Moved 0.7 m forward on a 2.8 m wheelbase: the front axle holds
    # (1.4 + 0.7) / 2.8 = 3/4 of the weight, 375 kg a wheel.
    var p = _car()
    p.center_of_mass = Vector3(0.7, 0, 0)
    var sim = CarlaPhysics()
    var car = _spawn(sim, p^)
    ref v = sim.vehicles[car.value]
    assert_almost_equal(v.wheels[0].sprung_mass, 375, atol=0.1)
    assert_almost_equal(v.wheels[1].sprung_mass, 375, atol=0.1)
    assert_almost_equal(v.wheels[2].sprung_mass, 125, atol=0.1)


def _brake_setup(
    torque: Float32, grip: Float32, abs: Bool
) -> VehiclePhysicsControl:
    var p = _car()
    p.drag_coefficient = 0
    p.downforce_coefficient = 0
    p.brake_effect = Torque(0, NEWTON_METER)
    for i in range(4):
        p.wheels[i].max_brake_torque = Torque(torque, NEWTON_METER)
        p.wheels[i].friction_force_multiplier = grip
        p.wheels[i].abs_enabled = abs
    return p^


def _stopping_distance(
    var physics: VehiclePhysicsControl, speed: Float32
) raises -> Tuple[Float32, Float32]:
    """Return how far the car goes from `speed` with the brake on, and
    the front wheel's spin halfway."""
    var sim = CarlaPhysics()
    var car = _spawn(sim, physics^)
    _launch(sim, car, speed)
    var body = sim.vehicle_body(car)
    var start = sim.world.bodies[body.value].position.x
    sim.apply_vehicle_control(car, _drive(0, 1))
    var halfway = Float32(-1)
    for _ in range(600):
        sim.tick(Duration(H, SECOND), 1)
        var v = _speed(sim, car)
        if halfway < 0 and v < speed / 2:
            halfway = sim.vehicles[car.value].wheels[0].omega
        if v < 0.01:
            break
    return (sim.world.bodies[body.value].position.x - start, halfway)


def test_stopping_distance_from_brake_torque() raises:
    # Four brakes of 600 N m on 0.3 m wheels: 8000 N on 1000 kg, 8 m/s^2.
    # The tire grip, 3 x 0.6 = 1.8 g, is not reached. From 20 m/s:
    # 400 / 16 = 25 m.
    # The step moves the car at the speed after each step's braking, so
    # it stops v h / 2 short: 25 - 20 / 30 / 2 = 24.67 m.
    var r = _stopping_distance(_brake_setup(600, 3, False), 20)
    assert_almost_equal(r[0], 25 - 20 * H / 2, atol=0.08)
    # The wheels roll: 10 m/s over 0.3 m.
    assert_almost_equal(r[1], 10 / 0.3, atol=1.5)


def test_stopping_distance_from_grip() raises:
    # A grip of 0.5 (the ground's 0.6 times 5/6) and brakes far stronger:
    # the wheels lock and slide at 0.5 g. From 20 m/s: 400 / 9.8 = 40.8 m.
    # Less the v h / 2 of the step, as above.
    var locked = _stopping_distance(_brake_setup(3000, 5.0 / 6.0, False), 20)
    assert_almost_equal(locked[0], 400 / G - 20 * H / 2, atol=0.08)
    assert_equal(locked[1], 0)
    # With ABS the wheels keep turning, and the car stops as short.
    var anti = _stopping_distance(_brake_setup(3000, 5.0 / 6.0, True), 20)
    assert_almost_equal(anti[0], 400 / G - 20 * H / 2, atol=0.08)
    assert_true(anti[1] > 20)


def _shift_setup() -> VehiclePhysicsControl:
    var p = _car()
    p.gear_change_time = Duration(0, SECOND)
    return p^


def test_gear_changes_follow_the_engine_speed() raises:
    # The engine turns at the wheel's spin times the gear times the final
    # ratio 4. It shifts up at 4500 rpm = 471.2 rad/s: in first (3.0) at
    # 471.2 x 0.3 / 12 = 11.78 m/s, in second (2.0) at 17.67 m/s, in
    # third (1.4) at 25.24 m/s.
    var sim = CarlaPhysics()
    var car = _spawn(sim, _shift_setup())
    _run(sim, 1)
    sim.apply_vehicle_control(car, _drive(1, 0))
    var ratios: List[Float32] = [3.0, 2.0, 1.4]
    var shifts = List[Float32]()
    var gear = 0
    for _ in range(Int(20 / H)):
        sim.tick(Duration(H, SECOND), 1)
        var t = sim.telemetry(car)
        if t.gear.value > gear:
            if gear > 0:
                shifts.append(t.speed.value)
            gear = t.gear.value
    assert_equal(gear, 4)
    assert_equal(len(shifts), 3)
    for i in range(3):
        var expected = 4500 * RPM * 0.3 / (ratios[i] * 4)
        # The shift is seen at the end of the step after the crossing:
        # up to two steps of the gear's full acceleration, 300 x gear x 4
        # x 0.9 / 0.3 N on 1000 kg, past the shift point.
        var accel = 300 * ratios[i] * 4 * 0.9 / 0.3 / 1000
        assert_true(shifts[i] >= expected - 0.05)
        assert_true(shifts[i] <= expected + 2 * accel * H)


def test_top_speed_at_the_rev_limit() raises:
    # In fourth (1.0 x 4) the engine's 5000 rpm is 523.6 / 4 rad/s at the
    # wheel: 39.27 m/s. The drag there, 0.5 x 1.225 x 0.3 x 2.52 x 39.27^2
    # = 714 N, is far below the 3600 N the engine pushes, so the limit is
    # the engine speed.
    var sim = CarlaPhysics()
    var car = _spawn(sim, _shift_setup())
    _launch(sim, car, 30)
    var c = _drive(1, 0)
    c.manual_gear_shift = True
    c.gear = Gear(4)
    sim.apply_vehicle_control(car, c)
    _run(sim, 8)
    var t = sim.telemetry(car)
    assert_equal(t.gear.value, 4)
    assert_almost_equal(t.speed.value, 5000 * RPM * 0.3 / 4, atol=0.3)
    assert_almost_equal(t.engine_rpm.to(REVOLUTION_PER_MINUTE), 5000, atol=60)


def test_top_speed_against_drag() raises:
    # A drag coefficient of 3 on 2.52 m^2: the 3600 N of fourth gear meet
    # the drag at v = sqrt(2 x 3600 / (1.225 x 3 x 2.52)) = 27.88 m/s,
    # below the 39.27 m/s rev limit.
    var p = _shift_setup()
    p.drag_coefficient = 3
    var sim = CarlaPhysics()
    var car = _spawn(sim, p^)
    _launch(sim, car, 26)
    var c = _drive(1, 0)
    c.manual_gear_shift = True
    c.gear = Gear(4)
    sim.apply_vehicle_control(car, c)
    _run(sim, 15)
    var expected = sqrt(2 * 3600 / (1.225 * 3 * 2.52))
    assert_almost_equal(_speed(sim, car), Float32(expected), atol=0.05)


def test_torque_curve_under_the_limit() raises:
    # A torque map of 150 N m, under the 300 N m limit: the engine gives
    # the map's torque, 1800 N at the wheels in fourth, which meets a drag
    # coefficient of 3 at v = sqrt(2 x 1800 / (1.225 x 3 x 2.52))
    # = 19.71 m/s.
    var p = _shift_setup()
    p.drag_coefficient = 3
    p.torque_curve = [Vector2(0, 150), Vector2(5000, 150)]
    var sim = CarlaPhysics()
    var car = _spawn(sim, p^)
    _launch(sim, car, 19)
    var c = _drive(1, 0)
    c.manual_gear_shift = True
    c.gear = Gear(4)
    sim.apply_vehicle_control(car, c)
    _run(sim, 15)
    var expected = sqrt(2 * 1800 / (1.225 * 3 * 2.52))
    assert_almost_equal(_speed(sim, car), Float32(expected), atol=0.05)


def test_gear_change_time() raises:
    # With half a second per shift the clutch is out while it lasts.
    var sim = CarlaPhysics()
    var car = _spawn(sim, _car())
    _run(sim, 0.5)
    sim.apply_vehicle_control(car, _drive(1, 0))
    var saw_shift = False
    for _ in range(Int(8 / H)):
        sim.tick(Duration(H, SECOND), 1)
        ref v = sim.vehicles[car.value]
        if v.shift_timer > 0:
            saw_shift = True
            assert_true(v.target_gear != v.gear)
            for w in v.wheels:
                assert_equal(w.drive_torque, 0)
    assert_true(saw_shift)
    assert_true(sim.telemetry(car).gear.value >= 2)
    # Coasting down, the gearbox shifts back down.
    sim.apply_vehicle_control(car, _drive(0, 1))
    _run(sim, 6)
    assert_equal(sim.telemetry(car).gear.value, 1)


def test_reverse_and_manual_gears() raises:
    var sim = CarlaPhysics()
    var car = _spawn(sim, _car())
    _run(sim, 0.5)
    var c = _drive(0.5, 0)
    c.reverse = True
    sim.apply_vehicle_control(car, c)
    _run(sim, 2)
    var t = sim.telemetry(car)
    assert_equal(t.gear, REVERSE)
    assert_true(t.speed.value < -1)
    assert_true(sim.vehicles[car.value].applied.reverse)
    # Back to forward: gear one at once.
    c.reverse = False
    c.throttle = 0
    c.brake = 1
    sim.apply_vehicle_control(car, c)
    _run(sim, 3)
    assert_equal(sim.telemetry(car).gear.value, 1)
    # A manual gear past the last is the last.
    c.manual_gear_shift = True
    c.gear = Gear(9)
    c.brake = 0
    c.throttle = 1
    sim.apply_vehicle_control(car, c)
    _run(sim, 0.1)
    assert_equal(sim.telemetry(car).gear.value, 4)
    assert_false(sim.vehicles[car.value].automatic)


def _tilted_gravity(degrees: Float32) -> Vector3:
    var a = degrees * Float32(pi / 180)
    return Vector3(G * sin(a), 0, -G * cos(a))


def test_handbrake_holds_on_a_slope() raises:
    # A 10 degree slope: gravity along it is 9.8 sin 10 = 1.70 m/s^2. The
    # rear handbrakes hold 2 x 3000 / 0.3 = 20 000 N, far more than the
    # 1702 N needed.
    var sim = CarlaPhysics()
    var car = _spawn(sim, _car())
    _run(sim, 1)
    sim.world.gravity = _tilted_gravity(10)
    var c = VehicleControl()
    c.hand_brake = True
    sim.apply_vehicle_control(car, c)
    _run(sim, 2)
    assert_almost_equal(_speed(sim, car), 0, atol=0.01)
    # Released, it rolls freely: v = g sin 10 t = 3.40 m/s after 2 s.
    c.hand_brake = False
    sim.apply_vehicle_control(car, c)
    _run(sim, 2)
    assert_almost_equal(
        _speed(sim, car), G * Float32(sin(pi / 18)) * 2, atol=0.1
    )


def test_steering_turns_right() raises:
    # At 5 m/s (18 km/h), past the curve's key at 10 km/h, the steering
    # curve allows half the angle, so a steer of 0.5 turns the front wheels 0.5 x 0.5 x 70 = 17.5 degrees.
    # A bicycle model with a 2.8 m wheelbase yaws at v tan(d) / L
    # = 0.563 rad/s, to the right: plus yaw.
    var sim = CarlaPhysics()
    var car = _spawn(sim, _car())
    _launch(sim, car, 5)
    var c = VehicleControl()
    c.steer = 0.5
    sim.apply_vehicle_control(car, c)
    # Hold the speed with the Ackermann controller's help: no, simply
    # read the yaw rate after the steer settles.
    _run(sim, 0.5)
    var body = sim.vehicle_body(car)
    var yaw_rate = sim.angular_velocity(body).z
    var v = _speed(sim, car)
    var kmh = v * 3.6
    var factor = 1 - 0.5 * kmh / 10 if kmh < 10 else Float32(0.5)
    var angle = 0.5 * factor * 70 * Float32(pi / 180)
    var expected = v * tan(angle) / 2.8
    assert_true(yaw_rate > 0)
    assert_almost_equal(yaw_rate, expected, atol=Float64(expected * 0.15))
    assert_almost_equal(
        sim.vehicles[car.value].wheels[0].steer, angle, atol=0.02
    )
    assert_equal(sim.vehicles[car.value].wheels[2].steer, 0)


def test_ackermann_reaches_its_speed() raises:
    var sim = CarlaPhysics()
    var car = _spawn(sim, _car())
    _run(sim, 0.5)
    sim.apply_ackermann_control(car, _target(0, 0, 10, 0))
    _run(sim, 25)
    assert_almost_equal(_speed(sim, car), 10, atol=0.3)
    assert_true(sim.vehicles[car.value].ackermann_active)
    # Then a stop.
    sim.apply_ackermann_control(car, _target(0, 0, 0, 0))
    _run(sim, 15)
    assert_almost_equal(_speed(sim, car), 0, atol=0.1)
    # A plain control hands the pedals back.
    sim.apply_vehicle_control(car, VehicleControl())
    assert_false(sim.vehicles[car.value].ackermann_active)


def test_telemetry_while_rolling() raises:
    var sim = CarlaPhysics()
    var car = _spawn(sim, _car())
    _launch(sim, car, 10)
    sim.apply_vehicle_control(car, _drive(0.3, 0))
    _run(sim, 0.5)
    var t = sim.telemetry(car)
    assert_equal(len(t.wheels), 4)
    assert_almost_equal(t.throttle, 0.3, atol=1e-6)
    assert_equal(t.brake, 0)
    assert_equal(t.steer, 0)
    for w in t.wheels:
        # Rolling: the spin is the speed over the radius.
        assert_almost_equal(w.omega.value, t.speed.value / 0.3, atol=0.5)
        assert_almost_equal(w.lat_slip.value, 0, atol=0.01)
    assert_true(t.engine_rpm.value > 0)


def test_wheelspin_and_traction_control() raises:
    # A grip of 0.2 and full throttle in first: 300 x 12 x 0.9 / 0.3
    # = 10 800 N of drive against 0.2 x 9800 N of grip: the wheels spin.
    var p = _shift_setup()
    for i in range(4):
        p.wheels[i].friction_force_multiplier = 0.2 / 0.6
    var sim = CarlaPhysics()
    var car = _spawn(sim, p^)
    _run(sim, 0.5)
    sim.apply_vehicle_control(car, _drive(1, 0))
    _run(sim, 0.5)
    ref w = sim.vehicles[car.value].wheels[0]
    var ground = _speed(sim, car) / 0.3
    assert_true(w.omega > ground + 1)
    assert_true(w.slipping)
    # The spin past the ground is capped at 30 rad/s.
    assert_true(w.omega - ground <= 30.5)
    var q = _shift_setup()
    for i in range(4):
        q.wheels[i].friction_force_multiplier = 0.2 / 0.6
        q.wheels[i].traction_control_enabled = True
    var sim2 = CarlaPhysics()
    var car2 = _spawn(sim2, q^)
    _run(sim2, 0.5)
    sim2.apply_vehicle_control(car2, _drive(1, 0))
    _run(sim2, 0.5)
    var ground2 = _speed(sim2, car2) / 0.3
    assert_almost_equal(
        sim2.vehicles[car2.value].wheels[0].omega, ground2, atol=0.5
    )
    # Traction control gives the most the grip allows: 0.2 g.
    assert_almost_equal(_speed(sim2, car2), 0.2 * G * 0.5, atol=0.2)


def test_differentials() raises:
    var kinds = [
        ALL_WHEEL_DRIVE,
        FRONT_WHEEL_DRIVE,
        REAR_WHEEL_DRIVE,
        UNDEFINED_DIFFERENTIAL,
    ]
    for k in range(4):
        var p = _car()
        p.differential_type = kinds[k]
        p.front_rear_split = 0.3
        # For the undefined differential, only wheel 3 is driven.
        for i in range(3):
            p.wheels[i].affected_by_engine = False
        var sim = CarlaPhysics()
        var car = _spawn(sim, p^)
        _run(sim, 0.2)
        sim.apply_vehicle_control(car, _drive(1, 0))
        _run(sim, 0.1)
        ref w = sim.vehicles[car.value].wheels
        var total = Float32(0)
        for i in range(4):
            total += w[i].drive_torque
        assert_true(total > 0)
        if k == 0:
            # The front gets 1 - 0.3, the rear 0.3, split per axle.
            assert_almost_equal(w[0].drive_torque / total, 0.35, atol=1e-4)
            assert_almost_equal(w[3].drive_torque / total, 0.15, atol=1e-4)
        elif k == 1:
            assert_almost_equal(w[0].drive_torque / total, 0.5, atol=1e-4)
            assert_equal(w[3].drive_torque, 0)
        elif k == 2:
            assert_equal(w[0].drive_torque, 0)
            assert_almost_equal(w[3].drive_torque / total, 0.5, atol=1e-4)
        else:
            assert_almost_equal(w[3].drive_torque / total, 1, atol=1e-4)


def test_no_driven_wheel() raises:
    var p = _car()
    for i in range(4):
        p.wheels[i].affected_by_engine = False
    var sim = CarlaPhysics()
    var car = _spawn(sim, p^)
    _run(sim, 0.2)
    sim.apply_vehicle_control(car, _drive(1, 0))
    _run(sim, 0.5)
    for w in sim.vehicles[car.value].wheels:
        assert_equal(w.drive_torque, 0)
    assert_almost_equal(_speed(sim, car), 0, atol=0.01)


def test_wheels_in_the_air() raises:
    # No ground: the springs hang at full drop and the wheels spin free.
    var sim = CarlaPhysics()
    var car = sim.add_vehicle(
        _level(), Vector3(0, 0, 0.75), Vector3(2.3, 1.0, 0.75), _shift_setup()
    )
    sim.world.gravity = Vector3(0, 0, 0)
    var c = _drive(1, 0)
    c.manual_gear_shift = True
    c.gear = Gear(1)
    sim.apply_vehicle_control(car, c)
    _run(sim, 0.2)
    ref w = sim.vehicles[car.value].wheels[0]
    assert_false(w.in_contact)
    assert_equal(w.suspension_force, 0)
    assert_true(w.omega > 1)
    # The wheel hangs at its full drop, 0.1 m below its rest offset.
    var body = sim.vehicle_body(car)
    var z = sim.world.bodies[body.value].position.z
    assert_almost_equal(w.location.z, z + 0.2, atol=1e-4)
    # The brake stops it.
    sim.apply_vehicle_control(car, _drive(0, 1))
    _run(sim, 1)
    assert_equal(sim.vehicles[car.value].wheels[0].omega, 0)


def test_engine_out_of_gear() raises:
    # In neutral the engine revs against its 1 kg m^2: 300 N m for one
    # 1/30 s step adds 10 rad/s. Released, it falls at 600 rpm/s.
    var sim = CarlaPhysics()
    var car = _spawn(sim, _car())
    _run(sim, 0.2)
    var c = _drive(1, 0)
    c.manual_gear_shift = True
    c.gear = Gear(0)
    sim.apply_vehicle_control(car, c)
    var before = sim.vehicles[car.value].engine_omega
    sim.tick(Duration(H, SECOND), 1)
    assert_almost_equal(
        sim.vehicles[car.value].engine_omega - before, 300 * H, atol=1e-3
    )
    _run(sim, 5)
    assert_almost_equal(
        sim.vehicles[car.value].engine_omega, 5000 * RPM, atol=0.01
    )
    c.throttle = 0
    sim.apply_vehicle_control(car, c)
    sim.tick(Duration(H, SECOND), 1)
    assert_almost_equal(
        sim.vehicles[car.value].engine_omega,
        5000 * RPM - 600 * RPM * H,
        atol=1e-2,
    )


def test_rollover() raises:
    # Rolled 165 degrees and spinning: four steps each keep 65 percent
    # of the spin, then five seconds later the car reports a rollover.
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    var turned = CarlaTransform(
        Length(0, METER),
        Length(0, METER),
        Length(10, METER),
        CarlaRotation(Angle(0, DEGREE), Angle(0, DEGREE), Angle(165, DEGREE)),
    )
    var car = WheeledVehicle(
        world, turned, Vector3(0, 0, 0.75), Vector3(2.3, 1, 0.75), _car()
    )
    world.bodies[car.body.value].angular_velocity = Vector3(0, 0, 1)
    world.bodies[car.body.value].angular_damping = 0
    for _ in range(4):
        car.update(world, Duration(H, SECOND))
        world.step(Duration(H, SECOND))
    assert_equal(car.rollover_tracker, 4)
    assert_almost_equal(
        world.bodies[car.body.value].angular_velocity.z,
        Float32(0.65**4),
        atol=1e-4,
    )
    car.update(world, Duration(H, SECOND))
    assert_equal(car.rollover_tracker, 5)
    assert_true(car.failure_state == NO_FAILURE)
    for _ in range(Int(5 / H) + 1):
        car.update(world, Duration(H, SECOND))
    assert_true(car.failure_state == ROLLOVER)
    # Back on its wheels, the state clears.
    world.bodies[car.body.value].rotation = Quaternion.identity()
    car.update(world, Duration(H, SECOND))
    assert_equal(car.rollover_tracker, 0)
    assert_true(car.failure_state == NO_FAILURE)


def test_rollover_window_narrows() raises:
    # 135 degrees is inside the first window (130, 230) but not the second
    # (140, 220): the spin is cut once.
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    var turned = CarlaTransform(
        Length(0, METER),
        Length(0, METER),
        Length(10, METER),
        CarlaRotation(Angle(0, DEGREE), Angle(0, DEGREE), Angle(135, DEGREE)),
    )
    var car = WheeledVehicle(
        world, turned, Vector3(0, 0, 0.75), Vector3(2.3, 1, 0.75), _car()
    )
    world.bodies[car.body.value].angular_velocity = Vector3(0, 0, 1)
    for _ in range(3):
        car.update(world, Duration(H, SECOND))
    assert_equal(car.rollover_tracker, 1)
    assert_almost_equal(
        world.bodies[car.body.value].angular_velocity.z, 0.65, atol=1e-5
    )
    # A small roll with no tracker does nothing.
    world.bodies[car.body.value].rotation = Quaternion.identity()
    car.rollover_tracker = 0
    car.update(world, Duration(H, SECOND))
    assert_equal(car.rollover_tracker, 0)


def test_reaction_moves_a_platform() raises:
    # A car on a free slab: pushing forward, it pushes the slab back.
    # The slab slides on the ground at the mean friction, 0.35: at most
    # 0.35 x 1200 kg x 9.8 = 4116 N, less than the car's push.
    var sim = CarlaPhysics()
    _ = sim.add_static_mesh(_flat(100, 0), PhysicsMaterial(0, 0))
    var slab = RigidBody(
        DYNAMIC,
        Shape.box(Length(20, METER), Length(5, METER), Length(0.1, METER)),
        Mass(200, KILOGRAM),
        Vector3(0, 0, 0.1),
        Quaternion.identity(),
    )
    slab.material = PhysicsMaterial(0.7, 0)
    var platform = sim.add_body(slab^)
    var on_top = CarlaTransform(
        Length(0, METER),
        Length(0, METER),
        Length(0.25, METER),
        CarlaRotation(Angle(0, DEGREE), Angle(0, DEGREE), Angle(0, DEGREE)),
    )
    var car = sim.add_vehicle(
        on_top, Vector3(0, 0, 0.75), Vector3(2.3, 1.0, 0.75), _car()
    )
    _run(sim, 1)
    sim.apply_vehicle_control(car, _drive(1, 0))
    _run(sim, 1)
    assert_true(_speed(sim, car) > 1)
    assert_true(sim.velocity(platform).x < -0.2)


def test_physics_control_can_change() raises:
    # Twice the mass: each spring holds 4900 N, x = (4900 - 50) / 25000.
    var sim = CarlaPhysics()
    var car = _spawn(sim, _car())
    var heavy = _car()
    heavy.mass = Mass(2000, KILOGRAM)
    heavy.inertia_tensor_scale = Vector3(1, 2, 1)
    sim.apply_physics_control(car, heavy^)
    _run(sim, 3)
    var x = (2000 * G / 4 - 50) / 25000
    var body = sim.vehicle_body(car)
    assert_almost_equal(
        sim.world.bodies[body.value].position.z,
        0.3 - (0.3 + x - 0.1),
        atol=2e-3,
    )
    assert_almost_equal(
        sim.vehicles[car.value].maximum_steer_angle().to(DEGREE), 70, atol=1e-3
    )
    var three = _car()
    _ = three.wheels.pop()
    with assert_raises():
        sim.apply_physics_control(car, three^)
    with assert_raises():
        sim.vehicles[car.value].update(sim.world, Duration(0, SECOND))


def test_spawn_refusals() raises:
    var sim = CarlaPhysics()
    with assert_raises():
        _ = sim.add_vehicle(
            _level(), Vector3(0, 0, 0), Vector3(2, 1, 0.2), _car()
        )
    var bad = _car()
    bad.mass = Mass(-1, KILOGRAM)
    with assert_raises():
        _ = sim.add_vehicle(
            _level(), Vector3(0, 0, 0.75), Vector3(2, 1, 0.75), bad^
        )
    var c = VehicleControl()
    c.throttle = 2
    var car = sim.add_vehicle(
        _level(), Vector3(0, 0, 0.75), Vector3(2, 1, 0.75), _car()
    )
    with assert_raises():
        sim.apply_vehicle_control(car, c)


def test_skidding_sideways() raises:
    # Thrown sideways at 8 m/s: every tire slides across and skids.
    var sim = CarlaPhysics()
    var car = _spawn(sim, _car())
    _run(sim, 1)
    var body = sim.vehicle_body(car)
    sim.world.bodies[body.value].linear_velocity = Vector3(0, 8, 0)
    sim.tick(Duration(H, SECOND), 1)
    assert_true(sim.vehicles[car.value].wheels[0].skidding)
    _run(sim, 3)
    assert_false(sim.vehicles[car.value].wheels[0].skidding)
    # Coulomb friction at 2.1 g stops 8 m/s in 8 / 20.6 = 0.39 s.
    assert_almost_equal(sim.velocity(body).y, 0, atol=0.05)


def test_one_wheel() raises:
    # A single wheel under the middle holds the whole 1000 kg:
    # x = (9800 - 50) / 25000.
    var p = VehiclePhysicsControl()
    var w = WheelPhysicsControl()
    w.offset = Vector3(0, 0, 0.3)
    p.wheels.append(w^)
    var sim = CarlaPhysics()
    var car = _spawn(sim, p^)
    assert_almost_equal(
        sim.vehicles[car.value].wheels[0].sprung_mass, 1000, atol=0.1
    )
    # Balanced on one wheel it soon tips, but it lands on that wheel first.
    _run(sim, 0.2)
    assert_true(sim.vehicles[car.value].wheels[0].in_contact)
    assert_true(sim.vehicles[car.value].wheels[0].suspension_force > 0)


def test_undefined_axles_and_unbraked_wheels() raises:
    # All-wheel drive with one wheel on no axle: it gets nothing, and the
    # rear share goes to the one rear wheel left. A wheel the brake does
    # not reach holds no brake torque.
    var p = _car()
    p.differential_type = ALL_WHEEL_DRIVE
    p.wheels[3].axle_type = UNDEFINED_AXLE
    p.wheels[3].affected_by_brake = False
    var sim = CarlaPhysics()
    var car = _spawn(sim, p^)
    _run(sim, 0.2)
    sim.apply_vehicle_control(car, _drive(1, 1))
    sim.tick(Duration(H, SECOND), 1)
    ref w = sim.vehicles[car.value].wheels
    assert_equal(w[3].drive_torque, 0)
    assert_equal(w[3].brake_torque, 0)
    # Front: (1 - 0.5) / 2 a wheel. Rear: 0.5 on the one rear wheel.
    assert_almost_equal(w[2].drive_torque, 2 * w[0].drive_torque, atol=1e-2)
    assert_almost_equal(w[0].brake_torque, 1500, atol=1e-3)


def test_control_opposite_range_boundaries() raises:
    var throttle = VehicleControl()
    throttle.throttle = -0.01
    with assert_raises(contains="Throttle"):
        throttle.check()
    var steering = VehicleControl()
    steering.steer = 1.01
    with assert_raises(contains="Steer"):
        steering.check()
    var brake = VehicleControl()
    brake.brake = 1.01
    with assert_raises(contains="Brake"):
        brake.check()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
