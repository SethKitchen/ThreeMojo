# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tires use two-body contact motion, checked against impulse mechanics.

The reduced-mass controls use J = -u / (1/m_a + 1/m_b). The off-center
control adds r_z^2 / I_y for each body. All oracles use scalar arithmetic
from the fixture, rather than the production prediction or mass helpers.
"""

from extensions.carla.physics.body import (
    BodyId,
    BodyKind,
    DYNAMIC,
    KINEMATIC,
    STATIC,
    RigidBody,
)
from extensions.carla.physics.shape import Shape, cross
from extensions.carla.physics.vehicle_control import VehicleControl
from extensions.carla.physics.vehicle_physics import (
    VehiclePhysicsControl,
    WheelPhysicsControl,
)
from extensions.carla.physics.wheeled_vehicle import WheeledVehicle
from extensions.carla.physics.world import PhysicsWorld
from extensions.carla.transform import CarlaRotation, CarlaTransform
from math.matrix3 import Matrix3
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.math import sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_false,
    assert_true,
)
from units.si import (
    Angle,
    DEGREE,
    Duration,
    KILOGRAM,
    Length,
    METER,
    Mass,
    SECOND,
)

comptime H = Float32(0.01)


def _setup(count: Int) -> VehiclePhysicsControl:
    var p = VehiclePhysicsControl()
    p.mass = Mass(1000, KILOGRAM)
    p.drag_coefficient = 0
    p.downforce_coefficient = 0
    for i in range(count):
        var w = WheelPhysicsControl()
        w.offset = Vector3(Float32(i % 2) * 2 - 1, Float32(i // 2) * 2 - 1, 0.3)
        w.friction_force_multiplier = 1
        w.wheel_load_ratio = 1
        p.wheels.append(w^)
    return p^


def _support(
    mut world: PhysicsWorld, kind: BodyKind = DYNAMIC
) raises -> BodyId:
    var body = RigidBody(
        kind,
        Shape.box(Length(4, METER), Length(4, METER), Length(0.2, METER)),
        Mass(200, KILOGRAM),
        Vector3(0, 0, 0),
        Quaternion.identity(),
    )
    body.collides = False
    return world.add_body(body^)


def _car(mut world: PhysicsWorld, count: Int = 1) raises -> WheeledVehicle:
    var car = WheeledVehicle(
        world,
        CarlaTransform(
            Length(0, METER),
            Length(0, METER),
            Length(0, METER),
            CarlaRotation(Angle(0, DEGREE), Angle(0, DEGREE), Angle(0, DEGREE)),
        ),
        Vector3(0, 0, 0.75),
        Vector3(2, 1, 0.75),
        _setup(count),
    )
    ref body = world.bodies[car.body.value]
    body.set_center_of_mass(Vector3(0, 0, 0))
    body.collides = False
    return car^


def _contact(mut car: WheeledVehicle, wheel: Int, support: BodyId):
    ref state = car.wheels[wheel]
    state.in_contact = True
    state.ground = support
    state.contact_point = Vector3(0, 0, 0)
    state.contact_normal = Vector3(0, 0, 1)
    state.ground_friction = 1
    state.suspension_force = 1000000
    state.brake_torque = 1000000


def _close(
    actual: Float32, expected: Float32, tolerance: Float32 = 0.001
) raises:
    assert_almost_equal(actual, expected, atol=Float64(tolerance), rtol=0)


def test_comoving_public_update() raises:
    # The issue's public-path regression: a uniform boost must not brake
    # the vehicle. Spring forces are vertical; still-air forces are off.
    for kind in [DYNAMIC, KINEMATIC]:
        for speed in [Float32(0), Float32(10), Float32(-10)]:
            var world = PhysicsWorld()
            var platform = _support(world, kind)
            world.bodies[platform.value].collides = True
            var car = _car(world, 4)
            world.bodies[car.body.value].position.z = 0.25
            world.bodies[car.body.value].linear_velocity = Vector3(speed, 0, 0)
            world.bodies[platform.value].linear_velocity = Vector3(speed, 0, 0)
            var control = VehicleControl()
            control.brake = 1
            car.apply_control(control)
            car.update(world, Duration(H, SECOND))
            _close(world.bodies[car.body.value].force.x, 0)
            for wheel in car.wheels:
                assert_true(wheel.in_contact)
                _close(wheel.omega, 0)
                _close(wheel.lat_slip, 0)
                _close(wheel.long_slip, 0)


def test_reduced_mass_forward_reverse_and_static_baseline() raises:
    for kind in [DYNAMIC, STATIC, KINEMATIC]:
        for direction in [Float32(-1), Float32(1)]:
            var world = PhysicsWorld()
            world.gravity = Vector3(0, 0, 0)
            var platform = _support(world, kind)
            var car = _car(world)
            _contact(car, 0, platform)
            world.bodies[car.body.value].linear_velocity.x = 2 * direction
            var inverse_support = Float32(
                0.005
            ) if kind == DYNAMIC else Float32(0)
            var impulse = -2 * direction / (0.001 + inverse_support)
            car._tires(world, H)
            _close(world.bodies[car.body.value].force.x * H, impulse)
            if kind == DYNAMIC:
                _close(world.bodies[platform.value].force.x * H, -impulse)
            else:
                assert_true(
                    world.bodies[platform.value].force == Vector3(0, 0, 0)
                )
            world.step(Duration(H, SECOND))
            var a = world.bodies[car.body.value].linear_velocity.x
            var b = world.bodies[platform.value].linear_velocity.x
            _close(a, 2 * direction + impulse / 1000)
            _close(b, -impulse * inverse_support)
            _close(a - b, 0)
            assert_true(0.5 * 1000 * a * a + 0.5 * 200 * b * b <= 2000.001)
            if kind == DYNAMIC:
                _close(1000 * a + 200 * b, 2000 * direction)


def test_shared_and_distinct_support_predictions() raises:
    for distinct in [False, True]:
        var world = PhysicsWorld()
        world.gravity = Vector3(0, 0, 0)
        var car = _car(world, 4)
        var platform = _support(world)
        for i in range(4):
            if distinct and i > 0:
                platform = _support(world)
            _contact(car, i, platform)
        world.bodies[car.body.value].linear_velocity.x = 2
        car._tires(world, H)
        world.step(Duration(H, SECOND))
        var count = 4 if distinct else 1
        var common = Float32(2000) / Float32(1000 + count * 200)
        _close(world.bodies[car.body.value].linear_velocity.x, common)
        var momentum = world.bodies[car.body.value].linear_velocity.x * 1000
        for i in range(1, len(world.bodies)):
            _close(world.bodies[i].linear_velocity.x, common)
            momentum += world.bodies[i].linear_velocity.x * 200
        _close(momentum, 2000)


def test_force_torque_gravity_and_damping_prediction() raises:
    # p=(0,0,0), r_a.z=-1, r_b.z=2, I_ay=400, I_by=100.
    # The same backward-Euler damping acts on force and tire kicks.
    var world = PhysicsWorld()
    world.gravity = Vector3(3, 0, 0)
    var platform = _support(world)
    var car = _car(world)
    _contact(car, 0, platform)
    ref a = world.bodies[car.body.value]
    ref b = world.bodies[platform.value]
    a.position.z = 1
    b.position.z = -2
    var inertia = Matrix3()
    inertia.multiply_scalar(400)
    a.set_inertia(inertia)
    inertia.multiply_scalar(0.25)
    b.set_inertia(inertia)
    a.linear_velocity.x = 1.5
    b.linear_velocity.x = -2
    a.angular_velocity.y = 0.75
    b.angular_velocity.y = -0.25
    a.force.x = 3000
    b.force.x = -500
    a.torque.y = 200
    b.torque.y = -50
    a.gravity_scale = 0.5
    b.gravity_scale = 2
    a.linear_damping = 2
    b.linear_damping = 3
    a.angular_damping = 4
    b.angular_damping = 5
    var va = (1.5 + (3 * 0.5 + 3000 / 1000) * H) / (1 + 2 * H)
    var vb = (-2 + (3 * 2 - 500 / 200) * H) / (1 + 3 * H)
    var wa = (0.75 + 200 / 400 * H) / (1 + 4 * H)
    var wb = (-0.25 - 50 / 100 * H) / (1 + 5 * H)
    var relative = va - wa - vb - 2 * wb
    var inverse = (
        0.001 / (1 + 2 * H)
        + 0.005 / (1 + 3 * H)
        + 1 / (400 * (1 + 4 * H))
        + 4 / (100 * (1 + 5 * H))
    )
    var impulse = -relative / inverse
    car._tires(world, H)
    _close((world.bodies[car.body.value].force.x - 3000) * H, impulse)
    _close((world.bodies[platform.value].force.x + 500) * H, -impulse)
    world._integrate_velocities(H)
    var actual = world.bodies[car.body.value].velocity_at(
        Vector3(0, 0, 0)
    ) - world.bodies[platform.value].velocity_at(Vector3(0, 0, 0))
    _close(actual.x, 0)
    _close(car.wheels[0].omega, 0)


def test_rotating_support_relative_spin_and_slip() raises:
    # A prescribed platform's velocity is (2,0,0) at the point. It can
    # supply energy through its drive; that is not a closed-system claim.
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    var platform = _support(world, KINEMATIC)
    var car = _car(world)
    _contact(car, 0, platform)
    world.bodies[platform.value].position = Vector3(0, 1, 0)
    world.bodies[platform.value].angular_velocity.z = 2
    world.bodies[car.body.value].linear_velocity = Vector3(5, 1, 0)
    car.wheels[0].brake_torque = 0
    car._tires(world, H)
    _close(car.wheels[0].omega * car.physics.wheels[0].wheel_radius.value, 3)
    _close(car.wheels[0].lat_slip, 0.32175055)
    _close(car.wheels[0].long_slip, 0)
    assert_false(car.wheels[0].slipping)
    assert_true(world.bodies[platform.value].force == Vector3(0, 0, 0))


def test_uniform_translation_with_spin_slip_and_drive() raises:
    # Compare forces and all tire telemetry after arbitrary world boosts.
    for torque in [Float32(-900), Float32(0), Float32(900)]:
        var reference_force = Vector3(0, 0, 0)
        var reference_omega = Float32(0)
        var reference_long = Float32(0)
        var reference_lat = Float32(0)
        for boost in [Vector3(0, 0, 0), Vector3(13, -7, 4)]:
            var world = PhysicsWorld()
            world.gravity = Vector3(0, 0, 0)
            var platform = _support(world)
            var car = _car(world)
            _contact(car, 0, platform)
            world.bodies[car.body.value].linear_velocity = (
                Vector3(3, 2, 0) + boost
            )
            world.bodies[platform.value].linear_velocity = (
                Vector3(1, -1, 0) + boost
            )
            car.wheels[0].drive_torque = torque
            car.wheels[0].brake_torque = 10
            car.wheels[0].suspension_force = 100
            car._tires(world, H)
            if boost == Vector3(0, 0, 0):
                reference_force = world.bodies[car.body.value].force
                reference_omega = car.wheels[0].omega
                reference_long = car.wheels[0].long_slip
                reference_lat = car.wheels[0].lat_slip
            else:
                _close(world.bodies[car.body.value].force.x, reference_force.x)
                _close(world.bodies[car.body.value].force.y, reference_force.y)
                _close(car.wheels[0].omega, reference_omega)
                _close(car.wheels[0].long_slip, reference_long)
                _close(car.wheels[0].lat_slip, reference_lat)


def test_aerodynamic_world_velocity_remains_distinct() raises:
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    var platform = _support(world)
    var car = _car(world)
    _contact(car, 0, platform)
    world.bodies[car.body.value].linear_velocity.x = 10
    world.bodies[platform.value].linear_velocity.x = 10
    car._tires(world, H)
    _close(world.bodies[car.body.value].force.x, 0)
    car.physics.drag_coefficient = 0.3
    car._aerodynamics(world)
    var expected = -0.5 * 1.225 * car.physics.frontal_area().value * 0.3 * 100
    _close(world.bodies[car.body.value].force.x, expected)
    _close(car.forward_speed(world).value, 10)
    _close(car.wheels[0].omega, 0)


def test_traction_forward_reverse_finite_and_infinite_supports() raises:
    for kind in [DYNAMIC, KINEMATIC]:
        for direction in [Float32(-1), Float32(1)]:
            for controlled in [False, True]:
                var world = PhysicsWorld()
                world.gravity = Vector3(0, 0, 0)
                var platform = _support(world, kind)
                var car = _car(world)
                _contact(car, 0, platform)
                car.physics.wheels[0].traction_control_enabled = controlled
                car.wheels[0].drive_torque = 900 * direction
                car.wheels[0].brake_torque = 0
                car.wheels[0].suspension_force = 100
                car._tires(world, H)
                _close(world.bodies[car.body.value].force.x, 100 * direction)
                world.step(Duration(H, SECOND))
                var inverse_support = Float32(
                    0.005
                ) if kind == DYNAMIC else Float32(0)
                var ground = H * 100 * direction * (0.001 + inverse_support)
                var radius = car.physics.wheels[0].wheel_radius.value
                if controlled:
                    _close(car.wheels[0].omega * radius, ground)
                    _close(car.wheels[0].long_slip, 0)
                else:
                    assert_true(car.wheels[0].spin * direction > 0)
                    assert_true(car.wheels[0].long_slip * direction > 0)
                if kind == DYNAMIC:
                    var a = world.bodies[car.body.value].linear_velocity.x
                    var b = world.bodies[platform.value].linear_velocity.x
                    _close(1000 * a + 200 * b, 0)


def test_off_center_braking_dissipates_closed_system_energy() raises:
    # Equal/opposite impulses at the same point conserve total linear
    # and angular momentum. With no drive or outside force, brakes must
    # not increase the two rigid bodies' kinetic energy.
    for direction in [Float32(-1), Float32(1)]:
        for locked in [False, True]:
            var world = PhysicsWorld()
            world.gravity = Vector3(0, 0, 0)
            var platform = _support(world)
            var car = _car(world, 4)
            world.bodies[car.body.value].position = Vector3(0, 0, 1)
            world.bodies[platform.value].position = Vector3(0, 0, -1)
            world.bodies[car.body.value].linear_velocity = Vector3(
                2 * direction, 3, 0
            )
            world.bodies[platform.value].linear_velocity = Vector3(
                -direction, -2, 0
            )
            world.bodies[car.body.value].angular_velocity = Vector3(
                0.3, -0.2, 0.4
            )
            world.bodies[platform.value].angular_velocity = Vector3(
                -0.1, 0.5, -0.6
            )
            for i in range(4):
                _contact(car, i, platform)
                car.wheels[i].contact_point = Vector3(
                    Float32(i % 2) * 2 - 1, Float32(i // 2) * 2 - 1, 0
                )
                car.wheels[i].suspension_force = 1000
                car.wheels[i].brake_torque = 1000 if locked else 100
            for _ in range(32):
                var before = (
                    world.bodies[car.body.value].kinetic_energy()
                    + world.bodies[platform.value].kinetic_energy()
                )
                var momentum = (
                    world.bodies[car.body.value].momentum()
                    + world.bodies[platform.value].momentum()
                )
                var angular = (
                    world.bodies[car.body.value].angular_momentum()
                    + cross(
                        world.bodies[car.body.value].world_center_of_mass(),
                        world.bodies[car.body.value].momentum(),
                    )
                    + world.bodies[platform.value].angular_momentum()
                    + cross(
                        world.bodies[platform.value].world_center_of_mass(),
                        world.bodies[platform.value].momentum(),
                    )
                )
                car._tires(world, H)
                world._integrate_velocities(H)
                var after = (
                    world.bodies[car.body.value].kinetic_energy()
                    + world.bodies[platform.value].kinetic_energy()
                )
                assert_true(after <= before + 0.003)
                var final_momentum = (
                    world.bodies[car.body.value].momentum()
                    + world.bodies[platform.value].momentum()
                )
                _close(final_momentum.x, momentum.x)
                _close(final_momentum.y, momentum.y)
                _close(final_momentum.z, momentum.z)
                var final_angular = (
                    world.bodies[car.body.value].angular_momentum()
                    + cross(
                        world.bodies[car.body.value].world_center_of_mass(),
                        world.bodies[car.body.value].momentum(),
                    )
                    + world.bodies[platform.value].angular_momentum()
                    + cross(
                        world.bodies[platform.value].world_center_of_mass(),
                        world.bodies[platform.value].momentum(),
                    )
                )
                _close(final_angular.x, angular.x, 0.003)
                _close(final_angular.y, angular.y, 0.003)
                _close(final_angular.z, angular.z, 0.003)


def test_common_rigid_rotation_has_no_contact_slip() raises:
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    var platform = _support(world)
    var car = _car(world, 4)
    world.bodies[car.body.value].position = Vector3(0, 0, 1)
    world.bodies[platform.value].position = Vector3(0, 0, -2)
    var spin = Vector3(0.2, -0.3, 0.4)
    var drift = Vector3(7, -4, 2)
    for i in range(len(world.bodies)):
        world.bodies[i].angular_velocity = spin
        world.bodies[i].linear_velocity = drift + cross(
            spin, world.bodies[i].world_center_of_mass()
        )
    for i in range(4):
        _contact(car, i, platform)
        car.wheels[i].contact_point = Vector3(
            Float32(i % 2) * 2 - 1, Float32(i // 2) * 2 - 1, 0
        )
    car._tires(world, H)
    _close(world.bodies[car.body.value].force.length(), 0, 0.01)
    for wheel in car.wheels:
        _close(wheel.omega, 0)
        _close(wheel.long_slip, 0)
        assert_false(wheel.slipping)
        assert_false(wheel.skidding)


def test_rotated_support_tensor_matches_two_axis_impulse() raises:
    # Rotate principal inertia (100,150,200) by 45 degrees about z.
    # With r_b.z=2, K_xy=-4*(1/100-1/150)/2. A scalar reduced-mass
    # check alone would miss the support's rotated tensor and coupling.
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    var platform = _support(world)
    var car = _car(world)
    _contact(car, 0, platform)
    var inertia = Matrix3()
    inertia.elements[0] = 200
    inertia.elements[4] = 300
    inertia.elements[8] = 400
    world.bodies[car.body.value].set_inertia(inertia)
    inertia.elements[0] = 100
    inertia.elements[4] = 150
    inertia.elements[8] = 200
    world.bodies[platform.value].set_inertia(inertia)
    world.bodies[car.body.value].position.z = 1
    world.bodies[platform.value].position.z = -2
    world.bodies[platform.value].rotation = Quaternion.from_axis_angle(
        Vector3(0, 0, 1), Angle(45, DEGREE)
    )
    world.bodies[car.body.value].linear_velocity = Vector3(2, -3, 0)
    var kxx = Float32(0.006 + 1.0 / 300 + 4 * (1.0 / 100 + 1.0 / 150) / 2)
    var kyy = Float32(0.006 + 1.0 / 200 + 4 * (1.0 / 100 + 1.0 / 150) / 2)
    var kxy = Float32(-4 * (1.0 / 100 - 1.0 / 150) / 2)
    var determinant = kxx * kyy - kxy * kxy
    var jx = -(kyy * 2 + kxy * 3) / determinant
    var jy = (kxy * 2 + kxx * 3) / determinant
    car._tires(world, H)
    _close(world.bodies[car.body.value].force.x * H, jx)
    _close(world.bodies[car.body.value].force.y * H, jy)
    _close(world.bodies[platform.value].force.x * H, -jx)
    _close(world.bodies[platform.value].force.y * H, -jy)
    world._integrate_velocities(H)
    var relative = world.bodies[car.body.value].velocity_at(
        Vector3(0, 0, 0)
    ) - world.bodies[platform.value].velocity_at(Vector3(0, 0, 0))
    _close(relative.x, 0)
    _close(relative.y, 0)


def test_capped_rotated_support_is_passive() raises:
    # Independent scalar oracles for a fully coupled capped impulse.
    # The thin support (1,100,100.5) also satisfies the physical inertia
    # triangle inequalities. No production mass or energy helper is used.
    for thin in [False, True]:
        var ix = Float32(1) if thin else Float32(100)
        var iy = Float32(100) if thin else Float32(150)
        var iz = Float32(100.5) if thin else Float32(200)
        for turn in [Float32(-1), Float32(1)]:
            for velocity in [
                Vector3(2, -3, 0),
                Vector3(-2, 3, 0),
                Vector3(0.03, 0.07, 0),
                Vector3(-0.03, -0.07, 0),
            ]:
                var world = PhysicsWorld()
                world.gravity = Vector3(0, 0, 0)
                var platform = _support(world)
                var car = _car(world)
                _contact(car, 0, platform)
                var inertia = Matrix3()
                inertia.elements[0] = 200
                inertia.elements[4] = 300
                inertia.elements[8] = 400
                world.bodies[car.body.value].set_inertia(inertia)
                inertia.elements[0] = ix
                inertia.elements[4] = iy
                inertia.elements[8] = iz
                world.bodies[platform.value].set_inertia(inertia)
                world.bodies[car.body.value].position.z = 1
                world.bodies[platform.value].position.z = -2
                world.bodies[
                    platform.value
                ].rotation = Quaternion.from_axis_angle(
                    Vector3(0, 0, 1), Angle(45 * turn, DEGREE)
                )
                world.bodies[car.body.value].linear_velocity = velocity
                var kxx = 0.006 + 1.0 / 300 + 2 * (1 / ix + 1 / iy)
                var kyy = 0.006 + 1.0 / 200 + 2 * (1 / ix + 1 / iy)
                var kxy = -2 * (1 / ix - 1 / iy) * turn
                # This radius is below the unconstrained impulse. Both
                # directions are nonzero and the first projection hits it.
                var limit = 0.25 * sqrt(
                    (velocity.x / kxx) ** 2 + (velocity.y / kyy) ** 2
                )
                car.wheels[0].suspension_force = limit / H
                var ux = Float64(velocity.x)
                var uy = Float64(velocity.y)
                var before = 500 * (ux * ux + uy * uy)
                car._tires(world, H)
                var impulse = world.bodies[car.body.value].force * H
                _close(impulse.length(), limit, 0.0001)
                _close(impulse.z, 0)
                var jx = Float64(impulse.x)
                var jy = Float64(impulse.y)
                var change = (
                    jx * ux
                    + jy * uy
                    + 0.5
                    * (
                        Float64(kxx) * jx * jx
                        + 2 * Float64(kxy) * jx * jy
                        + Float64(kyy) * jy * jy
                    )
                )
                assert_true(change <= 0)
                world._integrate_velocities(H)
                var va = world.bodies[car.body.value].linear_velocity
                var vb = world.bodies[platform.value].linear_velocity
                var wa = world.bodies[car.body.value].angular_velocity
                var wb = world.bodies[platform.value].angular_velocity
                var ax = Float64(va.x)
                var ay = Float64(va.y)
                var az = Float64(va.z)
                var bx = Float64(vb.x)
                var by = Float64(vb.y)
                var bz = Float64(vb.z)
                var aox = Float64(wa.x)
                var aoy = Float64(wa.y)
                var aoz = Float64(wa.z)
                var box = Float64(wb.x)
                var boy = Float64(wb.y)
                var boz = Float64(wb.z)
                var diagonal = Float64(ix + iy) / 2
                var mixed = Float64((ix - iy) * turn) / 2
                var after = (
                    500 * (ax * ax + ay * ay + az * az)
                    + 100 * (bx * bx + by * by + bz * bz)
                    + 0.5
                    * (
                        200 * aox * aox
                        + 300 * aoy * aoy
                        + 400 * aoz * aoz
                        + diagonal * (box * box + boy * boy)
                        + 2 * mixed * box * boy
                        + Float64(iz) * boz * boz
                    )
                )
                assert_true(after <= before + 0.00001)
                assert_almost_equal(after, before + change, atol=0.001, rtol=0)
                _close(1000 * va.x + 200 * vb.x, 1000 * velocity.x)
                _close(1000 * va.y + 200 * vb.y, 1000 * velocity.y)
                _close(1000 * va.z + 200 * vb.z, 0)
                # Total angular momentum about the contact origin.
                assert_almost_equal(
                    200 * aox
                    + diagonal * box
                    + mixed * boy
                    - 1000 * ay
                    + 400 * by,
                    -1000 * uy,
                    atol=0.003,
                    rtol=0,
                )
                assert_almost_equal(
                    300 * aoy
                    + mixed * box
                    + diagonal * boy
                    + 1000 * ax
                    - 400 * bx,
                    1000 * ux,
                    atol=0.003,
                    rtol=0,
                )
                assert_almost_equal(
                    400 * aoz + Float64(iz) * boz, 0, atol=0.003, rtol=0
                )


def test_partial_axle_on_moving_support() raises:
    # Only wheels 0 and 2 reach the narrow platform. Place the chassis
    # center above that pair so the vertical springs have no net torque.
    var world = PhysicsWorld()
    var slab = RigidBody(
        KINEMATIC,
        Shape.box(Length(0.4, METER), Length(4, METER), Length(0.2, METER)),
        Mass(0, KILOGRAM),
        Vector3(-1, 0, 0),
        Quaternion.identity(),
    )
    slab.linear_velocity = Vector3(10, 0, 0)
    var platform = world.add_body(slab^)
    var car = _car(world, 4)
    world.bodies[car.body.value].position.z = 0.25
    world.bodies[car.body.value].set_center_of_mass(Vector3(-1, 0, 0))
    world.bodies[car.body.value].linear_velocity = Vector3(10, 0, 0)
    var control = VehicleControl()
    control.brake = 1
    car.apply_control(control)
    car.update(world, Duration(H, SECOND))
    assert_true(car.wheels[0].in_contact)
    assert_false(car.wheels[1].in_contact)
    assert_true(car.wheels[2].in_contact)
    assert_false(car.wheels[3].in_contact)
    _close(world.bodies[car.body.value].force.x, 0)
    for wheel in car.wheels:
        _close(wheel.omega, 0)
        _close(wheel.long_slip, 0)
    assert_true(world.bodies[platform.value].force == Vector3(0, 0, 0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
