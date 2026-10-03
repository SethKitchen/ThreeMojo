# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Measure four-wheel tire solves on static, shared and separate supports.

Build this same source against each implementation. Each case has 5000
warm-up solves and 500000 timed solves. The checksum consumes the chassis
force and every wheel's speed on every measured iteration. These are fixed
state tire solves, not a whole-vehicle frame-rate benchmark.
"""

from extensions.carla.physics.body import (
    BodyId,
    BodyKind,
    DYNAMIC,
    KINEMATIC,
    STATIC,
    RigidBody,
)
from extensions.carla.physics.shape import Shape
from extensions.carla.physics.vehicle_physics import (
    VehiclePhysicsControl,
    WheelPhysicsControl,
)
from extensions.carla.physics.wheeled_vehicle import WheeledVehicle
from extensions.carla.physics.world import PhysicsWorld
from extensions.carla.transform import CarlaRotation, CarlaTransform
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.time import perf_counter_ns
from units.si import Angle, DEGREE, KILOGRAM, Length, METER, Mass

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


def _case(kind: Int) raises:
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    var car = _car(world, 4)
    var platform = _support(world, STATIC if kind == 0 else DYNAMIC)
    for i in range(4):
        if kind == 2 and i > 0:
            platform = _support(world)
        _contact(car, i, platform)
        car.wheels[i].contact_point = Vector3(
            Float32(i % 2) * 2 - 1, Float32(i // 2) * 2 - 1, 0
        )
        car.wheels[i].suspension_force = 3000
        car.wheels[i].brake_torque = 100
    world.bodies[car.body.value].linear_velocity = Vector3(5, 1, 0)
    for i in range(1, len(world.bodies)):
        if kind != 0:
            world.bodies[i].linear_velocity = Vector3(2, 0, 0)
    for _ in range(5000):
        for i in range(len(world.bodies)):
            world.bodies[i].force = Vector3(0, 0, 0)
            world.bodies[i].torque = Vector3(0, 0, 0)
        car._tires(world, H)
    var checksum = Float64(0)
    var start = perf_counter_ns()
    for _ in range(500000):
        for i in range(len(world.bodies)):
            world.bodies[i].force = Vector3(0, 0, 0)
            world.bodies[i].torque = Vector3(0, 0, 0)
        car._tires(world, H)
        checksum += Float64(world.bodies[car.body.value].force.x)
        for wheel in car.wheels:
            checksum += Float64(wheel.omega)
    var elapsed = perf_counter_ns() - start
    print(
        kind,
        Float64(elapsed) / 500000,
        "ns per four-wheel solve",
        "force",
        world.bodies[car.body.value].force.x,
        "checksum",
        checksum,
    )


def main() raises:
    _case(0)
    _case(1)
    _case(2)
