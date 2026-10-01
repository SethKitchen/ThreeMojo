# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA physics: the world step and ray casts.

The expectations come from mechanics, worked by hand: the discrete free
fall of the semi-implicit Euler step, the velocities after an elastic or
a plastic hit from momentum and energy, the rebound height from the
restitution, and the slide down a slope from Coulomb friction.
"""

from extensions.carla.physics.body import (
    BodyId,
    BodyKind,
    DYNAMIC,
    KINEMATIC,
    RigidBody,
    STATIC,
)
from extensions.carla.physics.shape import PhysicsMaterial, Shape, cross
from extensions.carla.physics.world import PhysicsWorld
from math.quaternion import Quaternion
from math.triangle import Triangle
from math.vector3 import Vector3
from std.math import cos, nan, pi, sin, sqrt, tan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
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

comptime H = Float32(1.0 / 60.0)


def _m(value: Float32) -> Length:
    return Length(value, METER)


def _step(mut world: PhysicsWorld, count: Int) raises:
    for _ in range(count):
        world.step(Duration(H, SECOND))


def _near(a: Vector3, b: Vector3, tol: Float64) raises:
    assert_almost_equal(a.x, b.x, atol=tol)
    assert_almost_equal(a.y, b.y, atol=tol)
    assert_almost_equal(a.z, b.z, atol=tol)


def _turn(axis: Vector3, degrees: Float32) -> Quaternion:
    return Quaternion.from_axis_angle(axis, Angle(degrees, DEGREE))


def _ball(
    radius: Float32, mass: Float32, at: Vector3, bounce: Float32
) raises -> RigidBody:
    var body = RigidBody(
        DYNAMIC,
        Shape.sphere(_m(radius)),
        Mass(mass, KILOGRAM),
        at,
        Quaternion.identity(),
    )
    body.linear_damping = 0
    body.material = PhysicsMaterial(0, bounce)
    return body^


def _box(
    kind: BodyKind, half: Float32, mass: Float32, at: Vector3
) raises -> RigidBody:
    var body = RigidBody(
        kind,
        Shape.box(_m(half), _m(half), _m(half)),
        Mass(mass, KILOGRAM),
        at,
        Quaternion.identity(),
    )
    body.linear_damping = 0
    return body^


def _slope(size: Float32, degrees: Float32) -> List[Triangle]:
    """A square that falls toward plus x: z = -x tan(angle)."""
    var t = Float32(tan(degrees * Float32(pi / 180)))
    var a = Vector3(-size, -size, size * t)
    var b = Vector3(size, -size, -size * t)
    var c = Vector3(size, size, -size * t)
    var d = Vector3(-size, size, size * t)
    return [Triangle(a, b, c), Triangle(a, c, d)]


def _ground(
    mut world: PhysicsWorld, z: Float32, material: PhysicsMaterial
) raises -> BodyId:
    var body = RigidBody(
        STATIC,
        Shape.mesh(_slope(50, 0)),
        Mass(0, KILOGRAM),
        Vector3(0, 0, z),
        Quaternion.identity(),
    )
    body.material = material
    return world.add_body(body^)


# --- ray casts --------------------------------------------------------------


def test_raycast_shapes() raises:
    var world = PhysicsWorld()
    var ball = world.add_body(_box(STATIC, 1, 0, Vector3(0, 0, 0)))
    world.bodies[ball.value].shape = Shape.sphere(_m(1))
    var box = world.add_body(_box(STATIC, 1, 0, Vector3(0, 5, 0)))
    var capsule = RigidBody(
        STATIC,
        Shape.capsule(_m(0.5), _m(1)),
        Mass(0, KILOGRAM),
        Vector3(0, 10, 0),
        Quaternion.identity(),
    )
    var cap = world.add_body(capsule^)
    var x = Vector3(1, 0, 0)
    var down = Vector3(0, 0, -1)
    var far = _m(100)
    var none = BodyId(-1)
    # The ball: 5 m to its middle, less its 1 m radius.
    var hit = world.raycast(Vector3(-5, 0, 0), x, far, none).value()
    assert_equal(hit.body, ball)
    assert_almost_equal(hit.distance, 4, atol=1e-5)
    _near(hit.normal, Vector3(-1, 0, 0), 1e-5)
    _near(hit.point, Vector3(-1, 0, 0), 1e-5)
    # The box face at x = -1.
    hit = world.raycast(Vector3(-5, 5, 0), x, far, none).value()
    assert_equal(hit.body, box)
    assert_almost_equal(hit.distance, 4, atol=1e-5)
    _near(hit.normal, Vector3(-1, 0, 0), 1e-6)
    # The capsule's side, then its top: 1 m of segment and 0.5 m of cap.
    hit = world.raycast(Vector3(-5, 10, 0), x, far, none).value()
    assert_equal(hit.body, cap)
    assert_almost_equal(hit.distance, 4.5, atol=1e-5)
    _near(hit.normal, Vector3(-1, 0, 0), 1e-5)
    hit = world.raycast(Vector3(0, 10, 5), down, far, none).value()
    assert_almost_equal(hit.distance, 3.5, atol=1e-5)
    _near(hit.normal, Vector3(0, 0, 1), 1e-5)
    # Straight down beside the axis: the top cap, sqrt(0.25 - 0.04) up.
    hit = world.raycast(Vector3(0.2, 10, 5), down, far, none).value()
    assert_almost_equal(hit.distance, Float32(4 - sqrt(0.21)), atol=1e-5)
    # Level with the top cap: the side is out of reach, the cap is
    # sqrt(0.25 - 0.16) wide there.
    hit = world.raycast(Vector3(-5, 10, 1.4), x, far, none).value()
    assert_almost_equal(hit.distance, 4.7, atol=1e-4)
    # Pointing away from everything.
    assert_false(world.raycast(Vector3(5, 10, 0), x, far, none))
    assert_false(world.raycast(Vector3(5, 0, 0), x, far, none))
    # Below the capsule's segment the side is out of reach; its bottom cap
    # is hit where it is sqrt(0.25 - 0.16) wide.
    hit = world.raycast(Vector3(-5, 10, -1.4), x, far, none).value()
    assert_almost_equal(hit.distance, 4.7, atol=1e-4)
    # Too short, and ignoring the only thing in the way.
    assert_false(world.raycast(Vector3(-5, 0, 0), x, _m(3), none))
    assert_false(world.raycast(Vector3(-5, 0, 0), x, far, ball))
    # From inside the box, along a face, and past a corner.
    assert_false(world.raycast(Vector3(0, 5, 0), x, far, ball))
    assert_false(world.raycast(Vector3(-5, 6.5, 0), x, far, none))
    assert_false(world.raycast(Vector3(-5, 3, 0), Vector3(1, 1, 0), far, none))
    # A body that does not collide is not hit.
    world.bodies[ball.value].collides = False
    assert_false(world.raycast(Vector3(-5, 0, 0), x, far, none))
    with assert_raises():
        _ = world.raycast(Vector3(0, 0, 0), Vector3(0, 0, 0), far, none)


def test_raycast_turned_box() raises:
    var world = PhysicsWorld()
    var body = _box(STATIC, 1, 0, Vector3(0, 0, 0))
    body.rotation = _turn(Vector3(0, 0, 1), 45)
    _ = world.add_body(body^)
    # The ray meets the edge at x = -sqrt(2).
    var hit = world.raycast(
        Vector3(-5, 0, 0), Vector3(1, 0, 0), _m(10), BodyId(-1)
    ).value()
    assert_almost_equal(hit.distance, Float32(5 - sqrt(2.0)), atol=1e-5)


def test_raycast_meshes() raises:
    var world = PhysicsWorld()
    var ground = _ground(world, -5, PhysicsMaterial(0.9, 0.1))
    var lower = _ground(world, -8, PhysicsMaterial.default())
    var down = Vector3(0, 0, -1)
    var none = BodyId(-1)
    # Before a step the meshes are searched one triangle at a time.
    var hit = world.raycast(Vector3(1, 2, 10), down, _m(100), none).value()
    assert_equal(hit.body, ground)
    assert_almost_equal(hit.distance, 15, atol=1e-4)
    _near(hit.normal, Vector3(0, 0, 1), 1e-6)
    assert_almost_equal(hit.material.friction, 0.9, atol=1e-6)
    world.step(Duration(H, SECOND))
    # After it, through the octree: the same answer.
    hit = world.raycast(Vector3(1, 2, 10), down, _m(100), none).value()
    assert_equal(hit.body, ground)
    assert_almost_equal(hit.distance, 15, atol=1e-4)
    # Ignoring the upper mesh finds the lower.
    hit = world.raycast(Vector3(1, 2, 10), down, _m(100), ground).value()
    assert_equal(hit.body, lower)
    world.bodies[lower.value].collides = False
    assert_false(world.raycast(Vector3(1, 2, 10), down, _m(100), ground))
    # Too short, and from behind.
    assert_false(world.raycast(Vector3(1, 2, 10), down, _m(10), none))
    assert_false(
        world.raycast(Vector3(1, 2, -6), Vector3(0, 0, 1), _m(100), none)
    )
    # A ball above the mesh is nearer.
    var ball = world.add_body(_ball(1, 1, Vector3(1, 2, 0), 0))
    hit = world.raycast(Vector3(1, 2, 10), down, _m(100), none).value()
    assert_equal(hit.body, ball)
    assert_almost_equal(hit.distance, 9, atol=1e-4)


# --- the step ---------------------------------------------------------------


def test_step_refusals() raises:
    var world = PhysicsWorld()
    with assert_raises():
        world.step(Duration(0, SECOND))
    with assert_raises():
        world.step(Duration(nan[DType.float32](), SECOND))
    with assert_raises():
        world.check(BodyId(0))
    with assert_raises():
        world.check(BodyId(-1))
    var ground = _ground(world, 0, PhysicsMaterial.default())
    with assert_raises():
        _ = world.bounds(ground)
    var box = world.add_body(_box(DYNAMIC, 0.5, 1, Vector3(1, 2, 3)))
    var bounds = world.bounds(box)
    _near(bounds.min, Vector3(0.5, 1.5, 2.5), 1e-6)
    _near(bounds.max, Vector3(1.5, 2.5, 3.5), 1e-6)
    assert_equal(world.body_count(), 2)


def test_empty_world() raises:
    var world = PhysicsWorld()
    world.step(Duration(H, SECOND))
    assert_equal(world.contact_count, 0)
    assert_false(
        world.raycast(Vector3(0, 0, 0), Vector3(1, 0, 0), _m(10), BodyId(-1))
    )


def test_no_iterations() raises:
    # With no solver passes, a ball falls through the floor.
    var world = PhysicsWorld()
    world.velocity_iterations = 0
    world.position_iterations = 0
    _ = _ground(world, 0, PhysicsMaterial.default())
    var ball = world.add_body(_ball(0.5, 1, Vector3(0, 0, 0.6), 0))
    _step(world, 30)
    assert_true(world.bodies[ball.value].position.z < 0)


def test_box_across_two_meshes() raises:
    # A box resting across the join of two separate meshes touches both.
    var world = PhysicsWorld()
    var left = RigidBody(
        STATIC,
        Shape.mesh(
            [
                Triangle(
                    Vector3(-10, -10, 0), Vector3(0, -10, 0), Vector3(0, 10, 0)
                ),
                Triangle(
                    Vector3(-10, -10, 0), Vector3(0, 10, 0), Vector3(-10, 10, 0)
                ),
            ]
        ),
        Mass(0, KILOGRAM),
        Vector3(0, 0, 0),
        Quaternion.identity(),
    )
    _ = world.add_body(left^)
    var right = RigidBody(
        STATIC,
        Shape.mesh(
            [
                Triangle(
                    Vector3(0, -10, 0), Vector3(10, -10, 0), Vector3(10, 10, 0)
                ),
                Triangle(
                    Vector3(0, -10, 0), Vector3(10, 10, 0), Vector3(0, 10, 0)
                ),
            ]
        ),
        Mass(0, KILOGRAM),
        Vector3(0, 0, 0),
        Quaternion.identity(),
    )
    _ = world.add_body(right^)
    var box = world.add_body(_box(DYNAMIC, 0.5, 1, Vector3(0, 0, 0.5)))
    _step(world, 30)
    assert_almost_equal(world.bodies[box.value].position.z, 0.5, atol=0.01)
    # One pair of events for each mesh.
    assert_equal(len(world.events), 4)


def test_free_fall() raises:
    # Semi-implicit Euler: v_n = -g n h, z_n = z_0 - g h^2 n (n + 1) / 2.
    var world = PhysicsWorld()
    var ball = world.add_body(_ball(0.5, 1, Vector3(0, 0, 10), 0))
    _step(world, 60)
    ref body = world.bodies[ball.value]
    assert_almost_equal(body.linear_velocity.z, -9.8, atol=1e-4)
    assert_almost_equal(
        body.position.z, Float32(10 - 9.8 * H * H * 60 * 61 / 2), atol=1e-4
    )


def test_damping_and_torque() raises:
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    var ball = _ball(0.5, 2, Vector3(0, 0, 0), 0)
    ball.linear_damping = 1
    ball.angular_damping = 1
    ball.linear_velocity = Vector3(10, 0, 0)
    var id = world.add_body(ball^)
    # One step divides the velocity by 1 + h.
    world.step(Duration(H, SECOND))
    assert_almost_equal(
        world.bodies[id.value].linear_velocity.x, 10 / (1 + H), atol=1e-4
    )
    # A 1 N push at the ball's edge for one step: dv = h / m, and
    # dw = (r x F) h / I with I = 0.4 * 2 * 0.25 = 0.2, then damped.
    ref body = world.bodies[id.value]
    body.linear_damping = 0
    body.angular_damping = 0
    body.linear_velocity = Vector3(0, 0, 0)
    body.add_force(Vector3(0, 1, 0), Vector3(0.5, 0, 0) + body.position)
    world.step(Duration(H, SECOND))
    assert_almost_equal(
        world.bodies[id.value].linear_velocity.y, H / 2, atol=1e-6
    )
    assert_almost_equal(
        world.bodies[id.value].angular_velocity.z, 0.5 * H / 0.2, atol=1e-5
    )
    # The force lasts one step only.
    world.step(Duration(H, SECOND))
    assert_almost_equal(
        world.bodies[id.value].linear_velocity.y, H / 2, atol=1e-6
    )


def _pair(
    bounce: Float32, v1: Float32, v2: Float32
) raises -> Tuple[Float32, Float32]:
    """Two balls, 1 kg and 3 kg, meeting head on without gravity."""
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    var a = _ball(0.5, 1, Vector3(-0.6, 0, 0), bounce)
    a.linear_velocity = Vector3(v1, 0, 0)
    var b = _ball(0.5, 3, Vector3(0.6, 0, 0), bounce)
    b.linear_velocity = Vector3(v2, 0, 0)
    var ia = world.add_body(a^)
    var ib = world.add_body(b^)
    _step(world, 30)
    return (
        world.bodies[ia.value].linear_velocity.x,
        world.bodies[ib.value].linear_velocity.x,
    )


def test_elastic_collision() raises:
    # m1 = 1 at +4, m2 = 3 at -2. Momentum -2 and energy 14 give
    # v1 = ((m1 - m2) v1 + 2 m2 v2) / (m1 + m2) = -5 and v2 = 1.
    var v = _pair(1, 4, -2)
    assert_almost_equal(v[0], -5, atol=1e-3)
    assert_almost_equal(v[1], 1, atol=1e-3)
    assert_almost_equal(v[0] + 3 * v[1], -2, atol=1e-4)
    assert_almost_equal(0.5 * v[0] * v[0] + 1.5 * v[1] * v[1], 14, atol=1e-2)


def test_plastic_collision() raises:
    # No restitution: both move at the momentum over the mass, -2 / 4.
    var v = _pair(0, 4, -2)
    assert_almost_equal(v[0], -0.5, atol=1e-3)
    assert_almost_equal(v[1], -0.5, atol=1e-3)


def test_bounce_threshold() raises:
    # Meeting at 0.5 m/s, below the 1 m/s threshold: no bounce, even
    # with a restitution of one. Momentum 1 * 0.375 - 3 * 0.125 = 0.
    var v = _pair(1, 0.375, -0.125)
    assert_almost_equal(v[0], 0, atol=1e-3)
    assert_almost_equal(v[1], 0, atol=1e-3)


def test_collision_events() raises:
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    var a = _ball(0.5, 1, Vector3(-0.505, 0, 0), 1)
    a.linear_velocity = Vector3(4, 0, 0)
    var b = _ball(0.5, 3, Vector3(0.505, 0, 0), 1)
    b.linear_velocity = Vector3(-2, 0, 0)
    var ia = world.add_body(a^)
    var ib = world.add_body(b^)
    world.step(Duration(H, SECOND))
    # The 1 kg ball goes from +4 to -5: an impulse of 9 N s on it.
    assert_equal(len(world.events), 2)
    assert_true(world.contact_count > 0)
    var total = Float32(0)
    for e in world.events:
        if e.body == ia:
            assert_equal(e.other, ib)
            total = e.normal_impulse.x
    assert_almost_equal(total, -9, atol=1e-2)


def _totals(world: PhysicsWorld) -> Tuple[Vector3, Vector3]:
    """The linear momentum, and the angular momentum about the origin."""
    var p = Vector3(0, 0, 0)
    var l = Vector3(0, 0, 0)
    for b in world.bodies:
        p = p + b.momentum()
        l = l + cross(b.world_center_of_mass(), b.momentum())
        l = l + b.angular_momentum()
    return (p, l)


def test_momentum_is_conserved() raises:
    # Five balls and a box thrown together without gravity, with friction
    # and off-center hits. The solver's impulses come in equal and
    # opposite pairs, so the linear momentum and the angular momentum
    # about the origin do not change.
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    for i in range(5):
        var ball = _ball(
            0.4,
            Float32(1 + i),
            Vector3(Float32(i) * 1.1 - 2, Float32(i % 2) * 0.3, 0),
            0.5,
        )
        ball.material = PhysicsMaterial(0.5, 0.5)
        ball.linear_velocity = Vector3(Float32(2 - i), Float32(i) * 0.1, 0)
        _ = world.add_body(ball^)
    var box = _box(DYNAMIC, 0.4, 2, Vector3(0.5, 1.2, 0.1))
    box.linear_velocity = Vector3(0, -3, 0)
    _ = world.add_body(box^)
    var before = _totals(world)
    _step(world, 60)
    var after = _totals(world)
    _near(after[0], before[0], 1e-3)
    _near(after[1], before[1], 1e-2)
    assert_true(len(world.events) >= 0)


def test_bounce_height() raises:
    # A ball and a floor of restitution 0.5 each: e = 0.5, so it comes
    # back up with half its speed and a quarter of its drop.
    var world = PhysicsWorld()
    _ = _ground(world, 0, PhysicsMaterial(0.5, 0.5))
    var ball = world.add_body(_ball(0.25, 1, Vector3(0, 0, 2.25), 0.5))
    world.bodies[ball.value].material = PhysicsMaterial(0.5, 0.5)
    var highest = Float32(0)
    var landed = False
    for _ in range(150):
        world.step(Duration(H, SECOND))
        var z = world.bodies[ball.value].position.z
        if world.bodies[ball.value].linear_velocity.z > 0:
            landed = True
        if landed:
            highest = max(highest, z)
    assert_true(landed)
    assert_almost_equal(highest - 0.25, 0.5, atol=0.03)


def test_rest_on_ground() raises:
    # A box, a capsule and a hull settle where their shapes say.
    var world = PhysicsWorld()
    _ = _ground(world, 0, PhysicsMaterial(0.8, 0))
    var box = world.add_body(_box(DYNAMIC, 0.5, 10, Vector3(0, 0, 1)))
    var capsule = RigidBody(
        DYNAMIC,
        Shape.capsule(_m(0.3), _m(0.5)),
        Mass(70, KILOGRAM),
        Vector3(3, 0, 2),
        Quaternion.identity(),
    )
    var cap = world.add_body(capsule^)
    var points = List[Vector3]()
    for i in range(8):
        points.append(
            Vector3(
                Float32(0.4) if (i & 1) != 0 else Float32(-0.4),
                Float32(0.4) if (i & 2) != 0 else Float32(-0.4),
                Float32(0.2) if (i & 4) != 0 else Float32(-0.2),
            )
        )
    var hull = RigidBody(
        DYNAMIC,
        Shape.convex(points),
        Mass(5, KILOGRAM),
        Vector3(-3, 0, 1),
        Quaternion.identity(),
    )
    var slab = world.add_body(hull^)
    # A second box on top of the first.
    var top = world.add_body(_box(DYNAMIC, 0.25, 2, Vector3(0, 0, 1.6)))
    _step(world, 180)
    assert_almost_equal(world.bodies[box.value].position.z, 0.5, atol=0.01)
    assert_almost_equal(world.bodies[cap.value].position.z, 0.8, atol=0.01)
    assert_almost_equal(world.bodies[slab.value].position.z, 0.2, atol=0.01)
    assert_almost_equal(world.bodies[top.value].position.z, 1.25, atol=0.015)
    for id in [box, cap, slab, top]:
        assert_true(world.bodies[id.value].linear_velocity.length() < 0.05)
    assert_almost_equal(world.bodies[box.value].position.x, 0, atol=0.01)
    assert_almost_equal(world.bodies[top.value].position.x, 0, atol=0.02)


def _on_slope(
    degrees: Float32, friction: Float32
) raises -> Tuple[Float32, Float32]:
    """A box set on a slope at rest; return its speed and travel after one
    second."""
    var world = PhysicsWorld()
    var slope = RigidBody(
        STATIC,
        Shape.mesh(_slope(50, degrees)),
        Mass(0, KILOGRAM),
        Vector3(0, 0, 0),
        Quaternion.identity(),
    )
    slope.material = PhysicsMaterial(friction, 0)
    _ = world.add_body(slope^)
    var turn = _turn(Vector3(0, 1, 0), degrees)
    var normal = turn.rotate(Vector3(0, 0, 1))
    var box = _box(DYNAMIC, 0.5, 4, normal * 0.5)
    box.rotation = turn
    box.material = PhysicsMaterial(friction, 0)
    var id = world.add_body(box^)
    var start = world.bodies[id.value].position
    _step(world, 60)
    ref body = world.bodies[id.value]
    return (
        body.linear_velocity.length(),
        (body.position - start).length(),
    )


def test_friction_holds_on_a_slope() raises:
    # tan 20 degrees is 0.36, less than a friction of 0.7: it stays.
    var r = _on_slope(20, 0.7)
    assert_true(r[0] < 1e-3)
    assert_true(r[1] < 2e-3)


def test_friction_slides_on_a_slope() raises:
    # tan 30 degrees is 0.58, more than 0.2: it slides with
    # a = g (sin 30 - 0.2 cos 30) = 9.8 (0.5 - 0.1732) = 3.2026 m/s^2,
    # and the semi-implicit step gives v = a n h after n steps.
    var r = _on_slope(30, 0.2)
    var a = Float32(9.8 * (0.5 - 0.2 * cos(pi / 6)))
    assert_almost_equal(r[0], a, atol=0.03)
    assert_almost_equal(r[1], a * H * H * 60 * 61 / 2, atol=0.03)


def test_kinematic_pushes() raises:
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    var pusher = _box(KINEMATIC, 0.5, 0, Vector3(-2, 0, 0))
    pusher.linear_velocity = Vector3(2, 0, 0)
    pusher.angular_velocity = Vector3(0, 0, 0.1)
    var ip = world.add_body(pusher^)
    var ib = world.add_body(_ball(0.5, 1, Vector3(0, 0, 0), 0))
    _step(world, 60)
    # The kinematic body keeps its velocity; the ball is shoved ahead.
    _near(world.bodies[ip.value].linear_velocity, Vector3(2, 0, 0), 0)
    assert_true(world.bodies[ib.value].position.x > 0.2)
    assert_true(world.bodies[ib.value].linear_velocity.x >= 1.9)


def test_non_colliding_and_static_pairs() raises:
    var world = PhysicsWorld()
    _ = _ground(world, 0, PhysicsMaterial.default())
    var ghost = _ball(0.5, 1, Vector3(0, 0, 0.4), 0)
    ghost.collides = False
    var ig = world.add_body(ghost^)
    # Two kinematic boxes overlap: neither is dynamic, so no contact.
    var k1 = _box(KINEMATIC, 0.5, 0, Vector3(5, 0, 5))
    var k2 = _box(KINEMATIC, 0.5, 0, Vector3(5.2, 0, 5))
    _ = world.add_body(k1^)
    _ = world.add_body(k2^)
    # A dynamic ball against a ghost ball: no contact.
    # At x = 1.2 the ball is well inside one triangle of the ground, and
    # well away from the other.
    var solid = world.add_body(_ball(0.5, 1, Vector3(1.2, 0, 3), 0))
    var other_ghost = _ball(0.5, 1, Vector3(1.2, 0, 3.3), 0)
    other_ghost.collides = False
    other_ghost.gravity_scale = 0
    _ = world.add_body(other_ghost^)
    _step(world, 90)
    # The ghost falls through the ground.
    assert_true(world.bodies[ig.value].position.z < 0)
    assert_equal(world.contact_count, 1)
    assert_true(world.bodies[solid.value].position.z > 0)


def test_disabled_bodies_leave_the_sweep_and_can_return() raises:
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    # Destroyed actors all park together. These ids must remain valid, but
    # their shared bounds must not cause pair scans or transformed shapes.
    for _ in range(1024):
        var ghost = _ball(0.5, 1, Vector3(0, 0, 0), 0)
        ghost.collides = False
        _ = world.add_body(ghost^)
    var solid = world.add_body(_ball(0.5, 1, Vector3(0.8, 0, 0), 0))
    world.step(Duration(H, SECOND))
    assert_equal(world.contact_count, 0)
    assert_equal(world._order[0], solid.value)
    assert_equal(world.body_count(), 1025)
    # A public collides change takes effect on the next step.
    world.bodies[0].collides = True
    world.step(Duration(H, SECOND))
    assert_true(world.contact_count > 0)
    assert_equal(world._order[0], 0)
    assert_equal(world._order[1], solid.value)
    world.bodies[0].collides = False
    world.bodies[solid.value].collides = False
    world.step(Duration(H, SECOND))
    assert_equal(world.contact_count, 0)


def test_mesh_added_later_and_ignored() raises:
    var world = PhysicsWorld()
    var ball = world.add_body(_ball(0.5, 1, Vector3(0, 0, 1), 0))
    world.step(Duration(H, SECOND))
    var ground = _ground(world, 0, PhysicsMaterial(0.5, 0))
    _step(world, 90)
    assert_almost_equal(world.bodies[ball.value].position.z, 0.5, atol=0.01)
    # A mesh that no longer collides lets the ball fall.
    world.bodies[ground.value].collides = False
    _step(world, 30)
    assert_true(world.bodies[ball.value].position.z < 0.4)


def test_sweep_order_changes() raises:
    # Three balls pass each other along x, so the sorted order changes,
    # and meet in the middle.
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    var a = _ball(0.2, 1, Vector3(3, 1, 0), 0)
    a.linear_velocity = Vector3(-3, 0, 0)
    var b = _ball(0.2, 1, Vector3(-3, 0, 0), 0)
    b.linear_velocity = Vector3(3, 0, 0)
    var c = _ball(0.2, 1, Vector3(0, -1, 0), 0)
    c.linear_velocity = Vector3(0, 0, 0)
    var ia = world.add_body(a^)
    var ib = world.add_body(b^)
    _ = world.add_body(c^)
    _step(world, 120)
    assert_true(world.bodies[ia.value].position.x < -2)
    assert_true(world.bodies[ib.value].position.x > 2)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
