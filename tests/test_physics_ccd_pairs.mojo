# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Moving sphere pairs under continuous collision, against analytic paths."""

from extensions.physics.body import (
    DYNAMIC,
    KINEMATIC,
    STATIC,
    RigidBody,
    rotation_matrix,
)
from extensions.physics.ccd import DISCRETE, SPHERE_MESH_CCD
from extensions.physics.shape import Shape, PhysicsMaterial
from extensions.physics.world import PhysicsWorld, _ccd_lcp
from math.matrix3 import Matrix3
from math.quaternion import Quaternion
from math.triangle import Triangle
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_true,
    assert_equal,
    assert_almost_equal,
    assert_raises,
)
from units.si import Length, Mass, Duration


def _ball(
    x: Float32,
    velocity: Float32,
    mass: Float32 = 1,
    bounce: Float32 = 0,
    friction: Float32 = 0,
) raises -> RigidBody:
    var body = RigidBody(
        DYNAMIC,
        Shape.sphere(Length(0.1)),
        Mass(mass),
        Vector3(x, 0, 0),
        Quaternion.identity(),
    )
    body.linear_velocity = Vector3(velocity, 0, 0)
    body.material = PhysicsMaterial(friction, bounce)
    return body^


def _floor() raises -> RigidBody:
    return RigidBody(
        STATIC,
        Shape.mesh(
            [
                Triangle(
                    Vector3(-100, -100, 0),
                    Vector3(100, -100, 0),
                    Vector3(0, 100, 0),
                )
            ]
        ),
        Mass(0),
        Vector3(0, 0, 0),
        Quaternion.identity(),
    )


def _world() -> PhysicsWorld:
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    world.collision_detection = SPHERE_MESH_CCD
    return world^


def _energy(world: PhysicsWorld) -> Float64:
    # Twice the kinetic energy, linear and spin, with the world tensor at
    # each body's pose.
    var total = Float64(0)
    for body in world.bodies:
        if body.kind() != DYNAMIC:
            continue
        var v = body.linear_velocity
        total += Float64(v.dot(v)) / Float64(body.inverse_mass())
        var turn = rotation_matrix(body.rotation)
        var back = turn
        back.transpose()
        var tensor = turn * body.inverse_inertia() * back
        tensor.invert()
        var w = body.angular_velocity
        total += Float64(w.dot(tensor.transform(w)))
    return total


def _momentum(world: PhysicsWorld) -> Vector3:
    var total = Vector3(0, 0, 0)
    for body in world.bodies:
        if body.kind() == DYNAMIC:
            total = total + body.linear_velocity * (1 / body.inverse_mass())
    return total


def test_a_head_on_elastic_pair_swaps_velocities() raises:
    # Gap 0.3 m closing at 60 m/s: contact at 5 ms of a 20 ms step.
    var world = _world()
    _ = world.add_body(_ball(0, 30, bounce=1))
    _ = world.add_body(_ball(0.5, -30, bounce=1))
    world.step(Duration(0.02))
    assert_almost_equal(world.bodies[0].linear_velocity.x, -30, atol=1e-5)
    assert_almost_equal(world.bodies[1].linear_velocity.x, 30, atol=1e-5)
    assert_almost_equal(world.bodies[0].position.x, -0.3, atol=1e-5)
    assert_almost_equal(world.bodies[1].position.x, 0.8, atol=1e-5)
    assert_equal(world.contact_count, 1)
    assert_equal(len(world.events), 2)
    assert_equal(world.events[0].body.value, 0)
    assert_equal(world.events[0].other.value, 1)
    assert_almost_equal(world.events[0].normal_impulse.x, -60, atol=1e-4)
    assert_equal(world.events[1].body.value, 1)
    assert_equal(world.events[1].other.value, 0)
    assert_almost_equal(world.events[1].normal_impulse.x, 60, atol=1e-4)
    # The discrete mode lets the same pair pass through each other.
    var discrete = _world()
    discrete.collision_detection = DISCRETE
    _ = discrete.add_body(_ball(0, 30, bounce=1))
    _ = discrete.add_body(_ball(0.5, -30, bounce=1))
    discrete.step(Duration(0.02))
    assert_true(discrete.bodies[0].position.x > discrete.bodies[1].position.x)


def test_a_plastic_pair_of_unequal_masses_keeps_momentum() raises:
    # 1 kg at 30 m/s meets 3 kg at rest: both leave at 7.5 m/s, at 10 ms.
    var world = _world()
    _ = world.add_body(_ball(0, 30))
    _ = world.add_body(_ball(0.5, 0, mass=3))
    var before = _energy(world)
    world.step(Duration(0.02))
    assert_almost_equal(world.bodies[0].linear_velocity.x, 7.5, atol=1e-5)
    assert_almost_equal(world.bodies[1].linear_velocity.x, 7.5, atol=1e-5)
    assert_almost_equal(world.bodies[0].position.x, 0.375, atol=1e-5)
    assert_almost_equal(world.bodies[1].position.x, 0.575, atol=1e-5)
    assert_almost_equal(_momentum(world).x, 30, atol=1e-4)
    assert_true(_energy(world) < before)


def test_energy_passes_along_a_chain_in_one_step() raises:
    # A strikes B, and B strikes C 13.3 ms later. C starts beyond A's own
    # reach and B's own reach. It joins the group because B can take A's
    # whole energy, so B cannot pass through C.
    var world = _world()
    _ = world.add_body(_ball(0, 30, bounce=1))
    _ = world.add_body(_ball(0.3, 0, bounce=1))
    _ = world.add_body(_ball(0.9, 0, bounce=1))
    world.step(Duration(0.02))
    assert_almost_equal(world.bodies[0].linear_velocity.x, 0, atol=1e-5)
    assert_almost_equal(world.bodies[1].linear_velocity.x, 0, atol=1e-5)
    assert_almost_equal(world.bodies[2].linear_velocity.x, 30, atol=1e-5)
    assert_almost_equal(world.bodies[0].position.x, 0.1, atol=1e-5)
    assert_almost_equal(world.bodies[1].position.x, 0.7, atol=1e-5)
    assert_almost_equal(world.bodies[2].position.x, 1.0, atol=1e-5)
    # Events come in time order: A and B first, then B and C.
    assert_equal(len(world.events), 4)
    assert_equal(world.events[0].body.value, 0)
    assert_equal(world.events[2].body.value, 1)
    assert_equal(world.events[2].other.value, 2)


def test_oblique_friction_moves_spin_and_keeps_momentum() raises:
    for anisotropic in [False, True]:
        var world = _world()
        _ = world.add_body(_ball(0, 30, bounce=0.5, friction=0.5))
        var other = _ball(0.5, 0, mass=2, bounce=0.5, friction=0.5)
        other.position.y = 0.1
        if anisotropic:
            var tensor = Matrix3()
            tensor.elements[0] = 100
            tensor.elements[4] = 200
            tensor.elements[8] = 150
            other.set_inverse_inertia(tensor)
            other.rotation = Quaternion(0.2, 0.1, 0.3, 0.9)
            other.rotation.normalize()
        _ = world.add_body(other^)
        var before = _energy(world)
        world.step(Duration(0.02))
        var p = _momentum(world)
        assert_almost_equal(p.x, 30, atol=1e-4)
        assert_almost_equal(p.y, 0, atol=1e-4)
        assert_almost_equal(p.z, 0, atol=1e-4)
        assert_true(_energy(world) < before)
        # Friction at the contact turns both spheres about z.
        assert_true(world.bodies[0].angular_velocity.z != 0)
        assert_true(world.bodies[1].angular_velocity.z != 0)


def test_a_slow_hit_does_not_bounce_and_a_near_miss_is_not_a_hit() raises:
    # Closing at 0.8 m/s, below the 1 m/s bounce threshold, over 30 mm.
    var world = _world()
    _ = world.add_body(_ball(0, 0.4, bounce=1))
    _ = world.add_body(_ball(0.23, -0.4, bounce=1))
    world.step(Duration(0.05))
    assert_almost_equal(world.bodies[0].linear_velocity.x, 0, atol=1e-6)
    assert_almost_equal(world.bodies[1].linear_velocity.x, 0, atol=1e-6)
    assert_equal(world.contact_count, 1)
    # Spin energy groups a slow sphere with a resting one, but the slow
    # sphere does not reach it in this step.
    var spun = _world()
    var spinning = _ball(0, 1)
    spinning.angular_velocity = Vector3(0, 0, 1000)
    _ = spun.add_body(spinning^)
    _ = spun.add_body(_ball(0.5, 0))
    spun.step(Duration(0.02))
    assert_equal(spun.contact_count, 0)
    assert_almost_equal(spun.bodies[0].position.x, 0.02, atol=1e-6)


def test_fast_and_slow_pairs_within_the_margin() raises:
    # A pair 10 mm apart, within the 20 mm margin. Closing fast, the sweep
    # takes it: an elastic swap. Closing slowly, the contact solver keeps
    # it, and the pair does not overlap.
    var fast = _world()
    _ = fast.add_body(_ball(0, 30, bounce=1))
    _ = fast.add_body(_ball(0.21, -30, bounce=1))
    fast.step(Duration(0.02))
    assert_almost_equal(fast.bodies[0].linear_velocity.x, -30, atol=1e-4)
    assert_almost_equal(fast.bodies[1].linear_velocity.x, 30, atol=1e-4)
    var slow = _world()
    _ = slow.add_body(_ball(0, 0.25))
    _ = slow.add_body(_ball(0.21, -0.25))
    slow.step(Duration(0.02))
    var gap = slow.bodies[1].position.x - slow.bodies[0].position.x
    assert_true(gap >= 0.2 - 1e-5)
    assert_true(
        slow.bodies[1].linear_velocity.x - slow.bodies[0].linear_velocity.x
        >= -1e-5
    )


def _stack(limit: Int) raises -> PhysicsWorld:
    # B rests on the floor; A falls onto it at 30 m/s. Plastic.
    var world = _world()
    world.ccd_max_impacts = limit
    _ = world.add_body(_floor())
    var b = _ball(0, 0)
    b.position = Vector3(0, 0, 0.1)
    b.linear_velocity = Vector3(0, 0, 0)
    _ = world.add_body(b^)
    var a = _ball(0, 0)
    a.position = Vector3(0, 0, 0.5)
    a.linear_velocity = Vector3(0, 0, -30)
    _ = world.add_body(a^)
    world.contact_count = 5
    return world^


def test_a_struck_stack_settles_or_rolls_back() raises:
    # A strikes B plastically; B then meets the floor at the same instant.
    # The cascade settles both contacts together, so both stop at once.
    var settled = _stack(16)
    var before = _energy(settled)
    settled.step(Duration(0.02))
    assert_almost_equal(settled.bodies[2].linear_velocity.z, 0, atol=1e-5)
    assert_almost_equal(settled.bodies[1].linear_velocity.z, 0, atol=1e-5)
    assert_almost_equal(settled.bodies[1].position.z, 0.1, atol=1e-5)
    assert_almost_equal(settled.bodies[2].position.z, 0.3, atol=1e-5)
    assert_true(_energy(settled) < before)
    # A step counts its own contacts: B resting on the floor, the first
    # impact, then the settled floor and pair contacts.
    assert_equal(settled.contact_count, 1 + 3)
    # One impact each is not enough: the step rolls back whole.
    var exhausted = _stack(1)
    with assert_raises(contains="impact limit exhausted"):
        exhausted.step(Duration(0.02))
    assert_equal(exhausted.bodies[2].position.z, 0.5)
    assert_equal(exhausted.bodies[2].linear_velocity.z, -30)
    assert_equal(exhausted.bodies[1].linear_velocity.z, 0)
    assert_equal(exhausted.contact_count, 5)
    assert_equal(len(exhausted.events), 0)


def test_an_elastic_stack_bounces_like_a_cradle() raises:
    # Elastic: A stops on B, B bounces off the floor and returns A's
    # speed to it. Each impact rebounds, so the cascade stays sequential.
    var world = _stack(16)
    for i in range(3):
        world.bodies[i].material = PhysicsMaterial(0, 1)
    world.step(Duration(0.02))
    assert_almost_equal(world.bodies[2].linear_velocity.z, 30, atol=1e-4)
    assert_almost_equal(world.bodies[1].linear_velocity.z, 0, atol=1e-4)
    # B resting on the floor, then three sequential impacts.
    assert_equal(world.contact_count, 1 + 3)


def test_a_heavy_elastic_cascade_ends_plastic() raises:
    # A heavy elastic body on a light one rebounds many times at one
    # instant. After twice the member count, the rest settles plastically.
    var world = _stack(16)
    for i in range(3):
        world.bodies[i].material = PhysicsMaterial(0, 1)
    world.bodies[2].set_mass(Mass(100))
    var before = _energy(world)
    world.step(Duration(0.02))
    var gap = world.bodies[2].position.z - world.bodies[1].position.z
    assert_true(gap >= 0.2 - 1e-5)
    assert_true(world.bodies[1].position.z >= 0.1 - 1e-5)
    assert_true(
        world.bodies[2].linear_velocity.z
        >= world.bodies[1].linear_velocity.z - 1e-4
    )
    assert_true(_energy(world) <= before * 1.000001)


def test_the_contact_solver_is_exact_and_fails_closed() raises:
    # No contacts.
    assert_equal(len(_ccd_lcp(List[Float64](), List[Float64]())), 0)
    # One contact closing at 2 with inverse mass 1 takes an impulse of 2.
    var one = _ccd_lcp([Float64(1)], [Float64(-2)])
    assert_almost_equal(one[0], 2, atol=1e-12)
    # A separating contact takes none.
    assert_equal(_ccd_lcp([Float64(1)], [Float64(3)])[0], 0)
    # Two equal rows: a singular set is skipped, and one row carries it.
    var twin = _ccd_lcp(
        [Float64(1), Float64(1), Float64(1), Float64(1)],
        [Float64(-1), Float64(-1)],
    )
    assert_almost_equal(twin[0] + twin[1], 1, atol=1e-12)
    # A chain: x0 pushes two bodies, x1 one. The second row closes faster.
    var chain = _ccd_lcp(
        [Float64(2), Float64(-1), Float64(-1), Float64(1)],
        [Float64(-1), Float64(-3)],
    )
    var w0 = 2 * chain[0] - chain[1] - 1
    var w1 = -chain[0] + chain[1] - 3
    assert_true(chain[0] >= 0 and chain[1] >= 0)
    assert_true(w0 >= -1e-9 and w1 >= -1e-9)
    assert_almost_equal(chain[0] * w0 + chain[1] * w1, 0, atol=1e-9)
    # Only the full set is valid here, and its elimination swaps rows.
    var swapped = _ccd_lcp(
        [Float64(1), Float64(2), Float64(2), Float64(5)],
        [Float64(-3), Float64(-7)],
    )
    assert_almost_equal(swapped[0], 1, atol=1e-9)
    assert_almost_equal(swapped[1], 1, atol=1e-9)
    # The first trial set needs a negative impulse; the second is valid.
    var trial = _ccd_lcp(
        [Float64(1), Float64(2), Float64(2), Float64(5)],
        [Float64(1), Float64(-1)],
    )
    assert_equal(trial[0], 0)
    assert_almost_equal(trial[1], 0.2, atol=1e-9)
    # A contact no impulse can open, and too many contacts, both refuse.
    with assert_raises(contains="could not resolve simultaneous contacts"):
        _ = _ccd_lcp([Float64(0)], [Float64(-1)])
    var many = List[Float64](length=121, fill=0)
    with assert_raises(contains="exceed ten"):
        _ = _ccd_lcp(many, List[Float64](length=11, fill=0))


def test_a_pair_that_touches_at_the_end_of_the_step() raises:
    # Exact binary values: a 0.25 m gap closed at 1 m/s in 0.25 s.
    var world = _world()
    for x, v in [(Float32(0), Float32(1)), (Float32(0.5), Float32(0))]:
        var body = RigidBody(
            DYNAMIC,
            Shape.sphere(Length(0.125)),
            Mass(1),
            Vector3(x, 0, 0),
            Quaternion.identity(),
        )
        body.linear_velocity = Vector3(v, 0, 0)
        _ = world.add_body(body^)
    world.step(Duration(0.25))
    assert_equal(world.contact_count, 1)
    assert_equal(world.bodies[0].position.x, 0.25)
    assert_equal(world.bodies[1].position.x, 0.5)
    assert_almost_equal(world.bodies[0].linear_velocity.x, 0.5, atol=1e-6)


def _tiles() raises -> RigidBody:
    # A 4 x 4 grid of square tiles, enough triangles for a tree.
    var triangles = List[Triangle]()
    for row in range(4):
        for column in range(4):
            var x = Float32(column) - 2
            var y = Float32(row) - 2
            triangles.append(
                Triangle(
                    Vector3(x, y, 0), Vector3(x + 1, y, 0), Vector3(x, y + 1, 0)
                )
            )
            triangles.append(
                Triangle(
                    Vector3(x + 1, y, 0),
                    Vector3(x + 1, y + 1, 0),
                    Vector3(x, y + 1, 0),
                )
            )
    return RigidBody(
        STATIC,
        Shape.mesh(triangles^),
        Mass(0),
        Vector3(0, 0, 0),
        Quaternion.identity(),
    )


def test_indexed_brute_and_repeated_runs_agree() raises:
    var reference = List[Float32]()
    for run in range(4):
        var world = _stack(16)
        # A tiled floor builds a tree. A disabled mesh just above the
        # floor holds triangles that a settled contact must skip.
        _ = world.add_body(_tiles())
        var off = _tiles()
        off.position.z = 0.001
        off.collides = False
        _ = world.add_body(off^)
        world._ccd_brute_force = run % 2 == 1
        var side = _ball(0.4, -20, bounce=0.5, friction=0.3)
        side.position.z = 0.3
        _ = world.add_body(side^)
        world.step(Duration(0.02))
        var values = List[Float32]()
        for body in world.bodies:
            values.append(body.position.x)
            values.append(body.position.z)
            values.append(body.linear_velocity.x)
            values.append(body.linear_velocity.z)
            values.append(body.angular_velocity.y)
        if run == 0:
            reference = values^
            continue
        for k in range(len(values)):
            assert_equal(values[k], reference[k])
        # Events stay in time order.
        assert_true(len(world.events) > 0)


def _paddle(x: Float32, velocity: Float32) raises -> RigidBody:
    var body = _ball(x, velocity, bounce=1)
    body.set_kind(KINEMATIC)
    return body^


def test_a_kinematic_sphere_strikes_with_infinite_mass() raises:
    # A paddle at 10 m/s meets a resting sphere elastically: the sphere
    # leaves at twice the paddle's speed, and the paddle keeps its path.
    var world = _world()
    _ = world.add_body(_paddle(0, 10))
    _ = world.add_body(_ball(0.3, 0, bounce=1))
    world.step(Duration(0.02))
    assert_almost_equal(world.bodies[1].linear_velocity.x, 20, atol=1e-4)
    assert_equal(world.bodies[0].linear_velocity.x, 10)
    assert_almost_equal(world.bodies[0].position.x, 0.2, atol=1e-6)
    assert_equal(world.contact_count, 1)
    assert_equal(world.events[0].body.value, 0)
    assert_equal(world.events[0].other.value, 1)
    # Contact at 10 ms, then 10 ms at 20 m/s.
    assert_almost_equal(world.bodies[1].position.x, 0.5, atol=1e-5)
    # The lower body can be the dynamic one too.
    var swapped = _world()
    _ = swapped.add_body(_ball(0.3, 0, bounce=1))
    _ = swapped.add_body(_paddle(0, 10))
    swapped.step(Duration(0.02))
    assert_almost_equal(swapped.bodies[0].linear_velocity.x, 20, atol=1e-4)


def test_kinematic_spheres_pass_meshes_and_each_other() raises:
    # Two kinematic spheres pass through each other and the floor, with no
    # events, and keep the integrator's path exactly.
    var world = _world()
    _ = world.add_body(_floor())
    var low = _paddle(0, 30)
    low.position.z = 0.05
    low.linear_velocity.z = -10
    _ = world.add_body(low^)
    _ = world.add_body(_paddle(0.5, -30))
    var reference = _world()
    reference.collision_detection = DISCRETE
    _ = reference.add_body(_floor())
    reference.bodies[0].collides = False
    var copy = _paddle(0, 30)
    copy.position.z = 0.05
    copy.linear_velocity.z = -10
    _ = reference.add_body(copy^)
    _ = reference.add_body(_paddle(0.5, -30))
    world.step(Duration(0.02))
    reference.step(Duration(0.02))
    assert_equal(world.contact_count, 0)
    for i in range(1, 3):
        assert_true(world.bodies[i].position == reference.bodies[i].position)


def test_a_sphere_crushed_by_a_kinematic_sphere_rolls_back() raises:
    # A paddle drives a resting sphere into the floor. No impulse can
    # open both contacts, so the step is refused and rolled back.
    var world = _world()
    _ = world.add_body(_floor())
    # The paddle comes before the sphere, so a contact can start at a
    # kinematic member.
    var paddle = _paddle(0, 0)
    paddle.position = Vector3(0, 0, 0.5)
    paddle.linear_velocity = Vector3(0, 0, -30)
    paddle.material = PhysicsMaterial(0, 0)
    _ = world.add_body(paddle^)
    var ball = _ball(0, 0)
    ball.position = Vector3(0, 0, 0.1)
    _ = world.add_body(ball^)
    # A resting kinematic sphere touches the paddle's path; two kinematic
    # spheres never form a contact.
    var post = _paddle(0, 0)
    post.position = Vector3(0, 0, 0.7)
    _ = world.add_body(post^)
    with assert_raises(contains="could not resolve simultaneous contacts"):
        world.step(Duration(0.02))
    assert_equal(world.bodies[1].position.z, 0.5)
    assert_equal(world.bodies[2].position.z, 0.1)


def test_a_sphere_between_closing_paddles_is_bounded() raises:
    # A sphere bounces between two paddles closing at 5 m/s each. Each
    # bounce adds speed, and the impact limit bounds the step.
    var world = _world()
    world.ccd_max_impacts = 4
    _ = world.add_body(_paddle(-0.5, 5))
    _ = world.add_body(_ball(0, 40, bounce=1))
    _ = world.add_body(_paddle(0.5, -5))
    with assert_raises(contains="impact limit exhausted"):
        world.step(Duration(0.05))
    assert_equal(world.bodies[1].linear_velocity.x, 40)
    # With room for the bounces, the sphere stays between the paddles.
    var roomy = _world()
    _ = roomy.add_body(_paddle(-0.5, 5))
    _ = roomy.add_body(_ball(0, 40, bounce=1))
    _ = roomy.add_body(_paddle(0.5, -5))
    roomy.step(Duration(0.02))
    assert_true(
        roomy.bodies[1].position.x > roomy.bodies[0].position.x + 0.2 - 1e-5
    )
    assert_true(
        roomy.bodies[1].position.x < roomy.bodies[2].position.x - 0.2 + 1e-5
    )
    assert_true(abs(roomy.bodies[1].linear_velocity.x) > 40)


def test_a_kinematic_capsule_is_refused() raises:
    var world = _world()
    var capsule = RigidBody(
        KINEMATIC,
        Shape.capsule(Length(0.1), Length(0.1)),
        Mass(1),
        Vector3(0, 0, 0),
        Quaternion.identity(),
    )
    _ = world.add_body(capsule^)
    with assert_raises(contains="kinematic spheres only"):
        world.step(Duration(0.01))
    # A split-correction spin counts as spin.
    var pushed = _world()
    var sphere = _paddle(0, 0)
    sphere.push_angular = Vector3(0, 1, 0)
    _ = pushed.add_body(sphere^)
    with assert_raises(contains="kinematic sphere without spin"):
        pushed.step(Duration(0.01))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
