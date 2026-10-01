# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA physics: walkers, and the `CarlaPhysics` world that holds them.

The walker's numbers come from the controller's own equations, worked by
hand: the velocity moves toward its target by at most the rate times the
step, the world then moves the capsule by the new velocity, and gravity
acts before the move. The traction limit, the jump height under that
step, and where the capsule stands on a slope, a curb and against a wall
follow from the same equations.
"""

from extensions.carla.physics.body import BodyId, DYNAMIC, KINEMATIC, RigidBody
from extensions.carla.physics.shape import PhysicsMaterial, Shape
from extensions.carla.physics.simulation import (
    CarlaPhysics,
    VehicleId,
    WalkerId,
    carla_rotation,
    carla_transform,
)
from extensions.carla.physics.walker import (
    Walker,
    WalkerControl,
    WalkerParameters,
)
from extensions.carla.transform import CarlaRotation, CarlaTransform
from math.matrix4 import Matrix4
from math.quaternion import Quaternion
from math.triangle import Triangle
from math.vector3 import Vector3
from std.math import cos, inf, nan, pi, sin, sqrt, tan
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
    DEGREE,
    Duration,
    KILOGRAM,
    Length,
    METER,
    Mass,
    SECOND,
    Velocity,
)

comptime H = Float32(1.0 / 30.0)
comptime G = Float32(9.8)
# The capsule's middle stands its 0.9 m half height plus the 1 cm skin
# above the floor.
comptime STAND = Float32(0.91)


def _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> List[Triangle]:
    return [Triangle(a, b, c), Triangle(a, c, d)]


def _flat(x0: Float32, x1: Float32, z: Float32) -> List[Triangle]:
    """A rectangle in two triangles. Its diagonal runs corner to corner,
    so the walkers start a little off (0, 0), where the diagonal of the
    square from -50 to 50 passes: a ray exactly on the seam of two
    triangles could meet either, or on another platform neither."""
    return _quad(
        Vector3(x0, -50, z),
        Vector3(x1, -50, z),
        Vector3(x1, 50, z),
        Vector3(x0, 50, z),
    )


def _run(mut sim: CarlaPhysics, seconds: Float32) raises:
    for _ in range(Int(seconds / H + 0.5)):
        sim.tick(Duration(H, SECOND), 1)


def _walk(speed: Float32, direction: Vector3) -> WalkerControl:
    var c = WalkerControl()
    c.speed = Velocity(speed)
    c.direction = direction
    return c


def _ground_and_walker(
    mut sim: CarlaPhysics, at: Vector3, material: PhysicsMaterial
) raises -> WalkerId:
    _ = sim.add_static_mesh(_flat(-50, 50, 0), material)
    var w = sim.add_walker(at, WalkerParameters())
    _run(sim, 0.5)
    return w


def _ground_and_walker(mut sim: CarlaPhysics, at: Vector3) raises -> WalkerId:
    return _ground_and_walker(sim, at, PhysicsMaterial.default())


def _where(sim: CarlaPhysics, w: WalkerId) raises -> Vector3:
    return sim.world.bodies[sim.walker_body(w).value].position


def _speed(sim: CarlaPhysics) -> Float32:
    return sim.walkers[0].speed(sim.world).value


# --- the settings -----------------------------------------------------------


def test_walker_settings() raises:
    var p = WalkerParameters()
    assert_almost_equal(p.radius.value, 0.25, atol=1e-6)
    assert_almost_equal(p.half_height.value, 0.9, atol=1e-6)
    assert_almost_equal(p.mass.value, 75, atol=1e-6)
    # CARLA's walker limit, 4096 cm/s.
    assert_almost_equal(p.max_speed.value, 40.96, atol=1e-4)
    assert_almost_equal(p.max_acceleration.value, 1, atol=1e-6)
    assert_almost_equal(p.braking_deceleration.value, 2, atol=1e-6)
    assert_almost_equal(p.jump_speed.value, 3, atol=1e-6)
    assert_almost_equal(p.max_step_height.value, 0.3, atol=1e-6)
    assert_almost_equal(p.max_slope.to(DEGREE), 35, atol=1e-4)
    assert_almost_equal(p.skin.value, 0.01, atol=1e-6)
    assert_equal(p.jump_max_count, 2)
    p.check()
    var c = WalkerControl()
    assert_equal(c.direction.x, 1)
    assert_equal(c.speed.value, 0)
    assert_false(c.jump)
    var bad = WalkerParameters()
    bad.radius = Length(0, METER)
    with assert_raises():
        bad.check()
    bad = WalkerParameters()
    bad.radius = Length(inf[DType.float32](), METER)
    with assert_raises():
        bad.check()
    bad = WalkerParameters()
    bad.half_height = Length(0.2, METER)
    with assert_raises():
        bad.check()
    bad = WalkerParameters()
    bad.braking_deceleration = Acceleration(-1)
    with assert_raises():
        bad.check()
    bad = WalkerParameters()
    bad.air_control = nan[DType.float32]()
    with assert_raises():
        bad.check()
    bad = WalkerParameters()
    bad.max_slope = Angle(-1, DEGREE)
    with assert_raises():
        bad.check()
    bad = WalkerParameters()
    bad.max_slope = Angle(91, DEGREE)
    with assert_raises():
        bad.check()
    bad = WalkerParameters()
    bad.jump_max_count = 0
    with assert_raises():
        bad.check()


def test_walker_refusals() raises:
    var sim = CarlaPhysics()
    var w = sim.add_walker(Vector3(0.013, 0.021, 1), WalkerParameters())
    with assert_raises():
        sim.apply_walker_control(w, _walk(-1, Vector3(1, 0, 0)))
    with assert_raises():
        sim.apply_walker_control(
            w, _walk(nan[DType.float32](), Vector3(1, 0, 0))
        )
    with assert_raises():
        sim.walkers[0].update(sim.world, Duration(0, SECOND))
    var bad = WalkerParameters()
    bad.jump_max_count = 0
    with assert_raises():
        _ = sim.add_walker(Vector3(0, 0, 1), bad)


def test_target_velocity() raises:
    # The direction's horizontal part times the speed, capped at CARLA's
    # 40.96 m/s.
    var sim = CarlaPhysics()
    var w = sim.add_walker(Vector3(0.013, 0.021, 1), WalkerParameters())
    sim.apply_walker_control(w, _walk(1.4, Vector3(0.6, 0.8, 5)))
    var t = sim.walkers[0].target_velocity()
    assert_almost_equal(t.x, 0.84, atol=1e-6)
    assert_almost_equal(t.y, 1.12, atol=1e-6)
    assert_equal(t.z, 0)
    sim.apply_walker_control(w, _walk(100, Vector3(0, -1, 0)))
    t = sim.walkers[0].target_velocity()
    assert_almost_equal(t.y, -40.96, atol=1e-4)
    assert_almost_equal(t.length(), 40.96, atol=1e-4)


# --- walking ----------------------------------------------------------------


def test_walks_at_the_control_speed() raises:
    # From rest toward 1.4 m/s at 1 m/s^2: after step k the speed is
    # k h, up to 1.4 at step 42. In 90 steps the walker covers
    # h^2 (1 + ... + 42) + 1.4 x 48 h = 903 h^2 + 67.2 h = 3.24333 m.
    var sim = CarlaPhysics()
    var w = _ground_and_walker(sim, Vector3(0.013, 0.021, 1))
    assert_almost_equal(_where(sim, w).z, STAND, atol=1e-4)
    assert_true(sim.walkers[0].grounded)
    var start = _where(sim, w)
    sim.apply_walker_control(w, _walk(1.4, Vector3(1, 0, 0)))
    sim.tick(Duration(H, SECOND), 1)
    assert_almost_equal(_speed(sim), H, atol=1e-6)
    for _ in range(89):
        sim.tick(Duration(H, SECOND), 1)
    var expected = 903 * H * H + 1.4 * 48 * H
    assert_almost_equal(_where(sim, w).x - start.x, expected, atol=1e-3)
    assert_almost_equal(_speed(sim), 1.4, atol=1e-5)
    assert_almost_equal(_where(sim, w).z, STAND, atol=1e-4)
    # It faces where it goes.
    var rotation = carla_transform(sim.world, sim.walker_body(w)).rotation
    assert_almost_equal(rotation.yaw, 0, atol=1e-3)


def test_brakes_to_a_stop() raises:
    # Released at 1.4 m/s, it slows by 2 h each step: 1.4 - 2 h after one
    # step, and at rest after 1.4 / (2 h) = 21 steps.
    var sim = CarlaPhysics()
    var w = _ground_and_walker(sim, Vector3(0.013, 0.021, 1))
    sim.apply_walker_control(w, _walk(1.4, Vector3(0, 1, 0)))
    _run(sim, 3)
    var rotation = carla_transform(sim.world, sim.walker_body(w)).rotation
    assert_almost_equal(rotation.yaw, 90, atol=1e-3)
    sim.apply_walker_control(w, _walk(0, Vector3(0, 1, 0)))
    sim.tick(Duration(H, SECOND), 1)
    assert_almost_equal(_speed(sim), 1.4 - 2 * H, atol=1e-5)
    for _ in range(19):
        sim.tick(Duration(H, SECOND), 1)
    assert_almost_equal(_speed(sim), 1.4 - 40 * H, atol=1e-4)
    sim.tick(Duration(H, SECOND), 1)
    assert_equal(_speed(sim), 0)
    # It keeps the heading it had.
    rotation = carla_transform(sim.world, sim.walker_body(w)).rotation
    assert_almost_equal(rotation.yaw, 90, atol=1e-3)


def test_turns_toward_the_target() raises:
    # Walking along x at 1.4, then asked for 1.4 along y: the velocity
    # moves straight toward (0, 1.4) by h, so each part changes by
    # h / sqrt 2.
    var sim = CarlaPhysics()
    var w = _ground_and_walker(sim, Vector3(0.013, 0.021, 1))
    sim.apply_walker_control(w, _walk(1.4, Vector3(1, 0, 0)))
    _run(sim, 3)
    sim.apply_walker_control(w, _walk(1.4, Vector3(0, 1, 0)))
    sim.tick(Duration(H, SECOND), 1)
    var vel = sim.velocity(sim.walker_body(w))
    var s = H / Float32(sqrt(2.0))
    assert_almost_equal(vel.x, 1.4 - s, atol=1e-5)
    assert_almost_equal(vel.y, s, atol=1e-5)
    # A direction half a unit long asks for half the speed.
    sim.apply_walker_control(w, _walk(1.4, Vector3(0, 0.5, 0)))
    _run(sim, 3)
    assert_almost_equal(_speed(sim), 0.7, atol=1e-4)
    # Faster than the new target, it slows at 1 m/s^2: from 3 to 1 m/s
    # in two seconds.
    sim.apply_walker_control(w, _walk(3, Vector3(0, 1, 0)))
    _run(sim, 3)
    assert_almost_equal(_speed(sim), 3, atol=1e-4)
    sim.apply_walker_control(w, _walk(1, Vector3(0, 1, 0)))
    _run(sim, 1)
    assert_almost_equal(_speed(sim), 2, atol=1e-3)
    _run(sim, 1)
    assert_almost_equal(_speed(sim), 1, atol=1e-4)


def test_reversal() raises:
    # Moving at 1.5 m/s and asked for 1.4 m/s the other way: the velocity
    # moves by h toward -1.4, to 1.5 - h.
    var sim = CarlaPhysics()
    var w = _ground_and_walker(sim, Vector3(0.013, 0.021, 1))
    var body = sim.walker_body(w)
    sim.world.bodies[body.value].linear_velocity = Vector3(1.5, 0, 0)
    sim.apply_walker_control(w, _walk(1.4, Vector3(-1, 0, 0)))
    sim.tick(Duration(H, SECOND), 1)
    assert_almost_equal(sim.velocity(body).x, 1.5 - H, atol=1e-5)
    assert_almost_equal(sim.velocity(body).y, 0, atol=1e-6)


def test_traction_limit() raises:
    # On ice with a friction of 0.05, a foot pushes at most
    # mu g = 0.49 m/s^2: less than the 1 m/s^2 asked for, and less than
    # the 2 m/s^2 of a stop.
    var sim = CarlaPhysics()
    var w = _ground_and_walker(
        sim, Vector3(0.013, 0.021, 1), PhysicsMaterial(0.05, 0)
    )
    assert_true(sim.walkers[0].grounded)
    assert_almost_equal(sim.walkers[0].floor_friction, 0.05, atol=1e-6)
    sim.apply_walker_control(w, _walk(1.4, Vector3(1, 0, 0)))
    _run(sim, 1)
    assert_almost_equal(_speed(sim), 0.05 * G, atol=1e-4)
    sim.apply_walker_control(w, _walk(0, Vector3(1, 0, 0)))
    sim.tick(Duration(H, SECOND), 1)
    assert_almost_equal(_speed(sim), 0.05 * G - 0.05 * G * H, atol=1e-5)
    # With no friction at all, the walker cannot start.
    var slick = CarlaPhysics()
    var s = _ground_and_walker(
        slick, Vector3(0.013, 0.021, 1), PhysicsMaterial(0, 0)
    )
    slick.apply_walker_control(s, _walk(1.4, Vector3(1, 0, 0)))
    _run(slick, 1)
    assert_equal(slick.walkers[0].speed(slick.world).value, 0)


def test_keeps_its_speed_on_a_slope() raises:
    # A 10 degree slope rising toward minus x: z = -x tan 10. Walking up
    # it, the horizontal speed stays 1.4 and the capsule stays 0.91 m over
    # the floor under its middle.
    var sim = CarlaPhysics()
    var t = Float32(tan(pi / 18))
    _ = sim.add_static_mesh(
        _quad(
            Vector3(-50, -50, 50 * t),
            Vector3(50, -50, -50 * t),
            Vector3(50, 50, -50 * t),
            Vector3(-50, 50, 50 * t),
        ),
        PhysicsMaterial.default(),
    )
    var w = sim.add_walker(Vector3(0.013, 0.021, 1), WalkerParameters())
    _run(sim, 0.5)
    sim.apply_walker_control(w, _walk(1.4, Vector3(-1, 0, 0)))
    _run(sim, 3)
    var p = _where(sim, w)
    assert_almost_equal(_speed(sim), 1.4, atol=1e-3)
    assert_almost_equal(p.z, -p.x * t + STAND, atol=1e-3)
    assert_almost_equal(
        sim.walkers[0].floor_normal.z, Float32(cos(pi / 18)), atol=1e-4
    )


def test_steps_up_a_curb_and_stops_at_a_wall() raises:
    # A 15 cm curb from x = 2, and a 1 m wall at x = 8.
    var sim = CarlaPhysics()
    var road = _flat(-50, 2, 0)
    road.extend(_flat(2, 50, 0.15))
    # The curb's face, toward minus x.
    road.extend(
        _quad(
            Vector3(2, -50, 0),
            Vector3(2, -50, 0.15),
            Vector3(2, 50, 0.15),
            Vector3(2, 50, 0),
        )
    )
    _ = sim.add_static_mesh(road^, PhysicsMaterial.default())
    var wall = RigidBody(
        KINEMATIC,
        Shape.box(Length(0.5, METER), Length(50, METER), Length(0.5, METER)),
        Mass(0, KILOGRAM),
        Vector3(8.5, 0, 0.65),
        Quaternion.identity(),
    )
    _ = sim.add_body(wall^)
    var w = sim.add_walker(Vector3(0.013, 0.021, 1), WalkerParameters())
    _run(sim, 0.5)
    sim.apply_walker_control(w, _walk(1.4, Vector3(1, 0, 0)))
    _run(sim, 4)
    var p = _where(sim, w)
    assert_true(p.x > 3)
    assert_almost_equal(p.z, 0.15 + STAND, atol=1e-3)
    _run(sim, 5)
    # Blocked by the wall's face at x = 8: its middle stops a radius
    # short.
    p = _where(sim, w)
    assert_almost_equal(p.x, 8 - 0.25, atol=0.02)
    assert_true(sim.walkers[0].grounded)


def test_jumps() raises:
    # A jump sets 3 m/s up. Each step gravity takes g h first, so the
    # rise is the sum of (3 - k g h) h for k = 1 to 9, while it is
    # positive: (9 x 3 - 45 g h) h = 0.41 m.
    var sim = CarlaPhysics()
    var w = _ground_and_walker(sim, Vector3(0.013, 0.021, 1))
    var ground = _where(sim, w).z
    var c = WalkerControl()
    c.jump = True
    sim.apply_walker_control(w, c)
    sim.tick(Duration(H, SECOND), 1)
    assert_equal(sim.walkers[0].jump_count, 1)
    assert_false(sim.walkers[0].grounded)
    var top = _where(sim, w).z
    for _ in range(19):
        sim.tick(Duration(H, SECOND), 1)
        top = max(top, _where(sim, w).z)
    assert_almost_equal(top - ground, (27 - 45 * G * H) * H, atol=1e-4)
    # Held, the jump does not repeat. It lands on the floor, with no
    # bounce.
    _run(sim, 1)
    assert_true(sim.walkers[0].grounded)
    assert_equal(sim.walkers[0].jump_count, 0)
    assert_almost_equal(_where(sim, w).z, ground, atol=1e-4)
    assert_almost_equal(sim.velocity(sim.walker_body(w)).z, 0, atol=1e-4)


def test_double_jump() raises:
    # CARLA's double jump: pressed again in the air, the walker jumps
    # again from the height it reached. Held for 12 steps and released
    # for one, it is (13 x 3 - 91 g h) h = 0.30911 m up at the second
    # press, and it rises 0.41 m more.
    var sim = CarlaPhysics()
    var w = _ground_and_walker(sim, Vector3(0.013, 0.021, 1))
    var ground = _where(sim, w).z
    var c = WalkerControl()
    c.jump = True
    sim.apply_walker_control(w, c)
    _run(sim, 0.4)
    c.jump = False
    sim.apply_walker_control(w, c)
    sim.tick(Duration(H, SECOND), 1)
    assert_almost_equal(
        _where(sim, w).z - ground, (39 - 91 * G * H) * H, atol=1e-4
    )
    c.jump = True
    sim.apply_walker_control(w, c)
    var top = Float32(0)
    for _ in range(16):
        sim.tick(Duration(H, SECOND), 1)
        top = max(top, _where(sim, w).z)
    assert_equal(sim.walkers[0].jump_count, 2)
    var expected = (39 - 91 * G * H) * H + (27 - 45 * G * H) * H
    assert_almost_equal(top - ground, expected, atol=1e-3)
    # A third press in the air does nothing.
    c.jump = False
    sim.apply_walker_control(w, c)
    sim.tick(Duration(H, SECOND), 1)
    var vz = sim.velocity(sim.walker_body(w)).z
    c.jump = True
    sim.apply_walker_control(w, c)
    sim.tick(Duration(H, SECOND), 1)
    assert_equal(sim.walkers[0].jump_count, 2)
    assert_almost_equal(
        sim.velocity(sim.walker_body(w)).z, vz - G * H, atol=1e-4
    )


def test_walks_off_a_ledge() raises:
    # A 1 m drop at x = 1: more than the 30 cm step, so it falls, steers
    # a little in the air, and lands.
    var sim = CarlaPhysics()
    var ground = _flat(-50, 1, 1)
    ground.extend(_flat(1, 50, 0))
    _ = sim.add_static_mesh(ground^, PhysicsMaterial.default())
    var w = sim.add_walker(Vector3(0.013, 0.021, 2), WalkerParameters())
    _run(sim, 0.5)
    assert_almost_equal(_where(sim, w).z, 1 + STAND, atol=1e-4)
    sim.apply_walker_control(w, _walk(1.4, Vector3(1, 0, 0)))
    var fell = False
    for _ in range(120):
        sim.tick(Duration(H, SECOND), 1)
        if not sim.walkers[0].grounded:
            fell = True
    assert_true(fell)
    assert_true(sim.walkers[0].grounded)
    assert_almost_equal(_where(sim, w).z, STAND, atol=1e-4)


def test_steps_down() raises:
    # A 20 cm step down at x = 1 is within the 30 cm step: the walker
    # follows it and does not leave the ground.
    var sim = CarlaPhysics()
    var ground = _flat(-50, 1, 0.2)
    ground.extend(_flat(1, 50, 0))
    _ = sim.add_static_mesh(ground^, PhysicsMaterial.default())
    var w = sim.add_walker(Vector3(0.013, 0.021, 1.2), WalkerParameters())
    _run(sim, 0.5)
    assert_almost_equal(_where(sim, w).z, 0.2 + STAND, atol=1e-4)
    sim.apply_walker_control(w, _walk(1.4, Vector3(1, 0, 0)))
    var left = False
    for _ in range(90):
        sim.tick(Duration(H, SECOND), 1)
        if not sim.walkers[0].grounded:
            left = True
    assert_false(left)
    assert_true(_where(sim, w).x > 2)
    assert_almost_equal(_where(sim, w).z, STAND, atol=1e-4)


def test_air_control() raises:
    # Dropped from 20 m with the walk asked: in the air the velocity
    # moves toward the target at 0.2 x 1 m/s^2, so 0.2 m/s after 1 s.
    # Released, it keeps that speed.
    var sim = CarlaPhysics()
    var w = sim.add_walker(Vector3(0.013, 0.021, 20), WalkerParameters())
    sim.apply_walker_control(w, _walk(1.4, Vector3(1, 0, 0)))
    _run(sim, 1)
    assert_false(sim.walkers[0].grounded)
    assert_almost_equal(_speed(sim), 0.2, atol=1e-5)
    sim.apply_walker_control(w, _walk(0, Vector3(1, 0, 0)))
    _run(sim, 0.5)
    assert_almost_equal(_speed(sim), 0.2, atol=1e-5)


def test_lands_from_a_fall() raises:
    # Dropped from 6 m, it falls at up to 10 m/s, which is more than one
    # step of 30 cm in a step. The rays reach as far as one step's fall,
    # so it snaps down to the floor and stays there.
    var sim = CarlaPhysics()
    _ = sim.add_static_mesh(_flat(-50, 50, 0), PhysicsMaterial(0.6, 1))
    var w = sim.add_walker(Vector3(0.013, 0.021, 6), WalkerParameters())
    _run(sim, 2)
    assert_true(sim.walkers[0].grounded)
    assert_almost_equal(_where(sim, w).z, STAND, atol=1e-4)
    assert_almost_equal(sim.velocity(sim.walker_body(w)).z, 0, atol=1e-4)


def test_pushed_by_a_body() raises:
    # A kinematic box sweeps the standing walker along.
    var sim = CarlaPhysics()
    var w = _ground_and_walker(sim, Vector3(0.013, 0.021, 1))
    var box = RigidBody(
        KINEMATIC,
        Shape.box(Length(0.5, METER), Length(2, METER), Length(0.5, METER)),
        Mass(0, KILOGRAM),
        Vector3(-1.5, 0, 0.6),
        Quaternion.identity(),
    )
    box.linear_velocity = Vector3(2, 0, 0)
    _ = sim.add_body(box^)
    _run(sim, 1.5)
    assert_true(_where(sim, w).x > 0.5)


def test_ignores_high_and_steep_floors() raises:
    # A 0.7 m block whose edge is under one rim ray: its top is above the
    # 30 cm step, so the walker stays on the ground beside it.
    var sim = CarlaPhysics()
    var w = _ground_and_walker(sim, Vector3(0.013, 0.021, 1))
    var block = RigidBody(
        KINEMATIC,
        Shape.box(Length(0.5, METER), Length(2, METER), Length(0.35, METER)),
        Mass(0, KILOGRAM),
        Vector3(0.76, 0, 0.35),
        Quaternion.identity(),
    )
    _ = sim.add_body(block^)
    _run(sim, 0.5)
    assert_almost_equal(_where(sim, w).z, STAND, atol=1e-3)
    assert_almost_equal(sim.walkers[0].floor_height, 0, atol=1e-4)
    # A 30 degree slope is walkable, and a 40 degree slope is past the
    # 35 degree limit: the walker slides and falls.
    for degrees in [30, 40]:
        var world = CarlaPhysics()
        var t = Float32(tan(Float32(degrees) * Float32(pi / 180)))
        _ = world.add_static_mesh(
            _quad(
                Vector3(-5, -5, 5 * t),
                Vector3(5, -5, -5 * t),
                Vector3(5, 5, -5 * t),
                Vector3(-5, 5, 5 * t),
            ),
            PhysicsMaterial.default(),
        )
        _ = world.add_walker(Vector3(0.013, 0.021, 1.2), WalkerParameters())
        _run(world, 0.5)
        assert_equal(world.walkers[0].grounded, degrees == 30)


# --- the world --------------------------------------------------------------


def test_ids() raises:
    assert_true(VehicleId(0).is_valid())
    assert_false(VehicleId(-1).is_valid())
    assert_true(WalkerId(0).is_valid())
    assert_false(WalkerId(-1).is_valid())
    var sim = CarlaPhysics()
    with assert_raises():
        _ = sim.vehicle_body(VehicleId(0))
    with assert_raises():
        _ = sim.vehicle_body(VehicleId(-1))
    with assert_raises():
        _ = sim.walker_body(WalkerId(0))
    with assert_raises():
        _ = sim.walker_body(WalkerId(-1))
    with assert_raises():
        _ = sim.telemetry(VehicleId(3))
    with assert_raises():
        _ = sim.transform(BodyId(0))
    with assert_raises():
        _ = sim.velocity(BodyId(0))
    with assert_raises():
        _ = sim.angular_velocity(BodyId(-2))
    with assert_raises():
        sim.tick(Duration(H, SECOND), 0)
    with assert_raises():
        sim.tick(Duration(0, SECOND), 1)


def test_world_refusals() raises:
    var sim = CarlaPhysics()
    with assert_raises():
        _ = sim.add_static_mesh(List[Triangle](), PhysicsMaterial.default())
    with assert_raises():
        _ = sim.add_static_mesh(_flat(0, 1, 0), PhysicsMaterial(-1, 0))
    var ball = RigidBody(
        DYNAMIC,
        Shape.sphere(Length(0.5, METER)),
        Mass(1, KILOGRAM),
        Vector3(0, 0, 0),
        Quaternion.identity(),
    )
    ball.material = PhysicsMaterial(0.5, 2)
    with assert_raises():
        _ = sim.add_body(ball^)


def test_rotation_round_trip() raises:
    # A body turned by a CARLA rotation reads back the same angles.
    var r = CarlaRotation(
        Angle(10, DEGREE), Angle(20, DEGREE), Angle(30, DEGREE)
    )
    var t = CarlaTransform(
        Length(1, METER), Length(2, METER), Length(3, METER), r
    )
    var q = Quaternion.from_matrix(t.matrix())
    var back = carla_rotation(q)
    assert_almost_equal(back.pitch, 10, atol=1e-3)
    assert_almost_equal(back.yaw, 20, atol=1e-3)
    assert_almost_equal(back.roll, 30, atol=1e-3)
    var sim = CarlaPhysics()
    var body = RigidBody(
        DYNAMIC,
        Shape.sphere(Length(0.5, METER)),
        Mass(1, KILOGRAM),
        t.location,
        q,
    )
    var id = sim.add_body(body^)
    var read = sim.transform(id)
    assert_almost_equal(read.location.x, 1, atol=1e-6)
    assert_almost_equal(read.location.z, 3, atol=1e-6)
    assert_almost_equal(read.rotation.roll, 30, atol=1e-3)
    # The same vector turns the same way.
    var v = Vector3(0.3, -0.2, 0.9)
    var a = r.rotate_vector(v)
    var b = q.rotate(v)
    assert_almost_equal(a.x, b.x, atol=1e-5)
    assert_almost_equal(a.y, b.y, atol=1e-5)
    assert_almost_equal(a.z, b.z, atol=1e-5)


def test_tick_collects_events_and_casts_rays() raises:
    # Two balls meet during a tick of four substeps.
    var sim = CarlaPhysics()
    sim.world.gravity = Vector3(0, 0, 0)
    for i in range(2):
        var ball = RigidBody(
            DYNAMIC,
            Shape.sphere(Length(0.5, METER)),
            Mass(1, KILOGRAM),
            Vector3(Float32(i) * 1.2 - 0.6, 0, 0),
            Quaternion.identity(),
        )
        ball.linear_velocity = Vector3(Float32(1 - 2 * i) * 3, 0, 0)
        _ = sim.add_body(ball^)
    sim.tick(Duration(0.1, SECOND), 4)
    assert_true(len(sim.events) >= 2)
    var hit = sim.raycast(
        Vector3(-5, 0, 0), Vector3(1, 0, 0), Length(20, METER)
    )
    assert_equal(hit.value().body, BodyId(0))
    assert_almost_equal(sim.angular_velocity(BodyId(0)).length(), 0, atol=1e-6)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
