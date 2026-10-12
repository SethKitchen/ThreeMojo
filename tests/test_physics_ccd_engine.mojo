# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Turning boxes and hulls, kinematic shapes and coupled bodies (#635).

These worlds take the conservative-advancement engine. Each expected value
comes by hand from the geometry or the impulse law, or is a bound: no
shape passes a surface by more than its tolerance, and no response adds
kinetic energy.
"""

from extensions.physics.body import DYNAMIC, KINEMATIC, STATIC, RigidBody
from extensions.physics.ccd import (
    DISCRETE,
    SPHERE_MESH_CCD,
    _ccd_qp,
    _core_gap,
    _first_root,
    _hull_distance,
    _triangle_core,
)
from extensions.physics.shape import MESH, PhysicsMaterial, Shape, _wide, cross
from extensions.physics.world import (
    PhysicsWorld,
    _CCDGroup,
    _ccd_collect,
    _ccd_placed,
)
from math.matrix3 import Matrix3
from math.quaternion import Quaternion
from math.triangle import Triangle
from math.vector3 import Vector3
from std.math import acos, asin, atan, cos, sin, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from tests.test_physics_ccd_index import (
    _assert_world,
    _failure_pair,
    _step_pair,
)
from units.si import Duration, Length, Mass

# A 1 m cube's tolerance: 1/1024 of its bounding radius, sqrt(3) / 2.
comptime _CUBE_TOLERANCE = 0.8660254037844386 / 1024


def _floor(z: Float32 = 0) -> Triangle:
    # Its front faces +z.
    return Triangle(
        Vector3(-10, -10, z), Vector3(10, -10, z), Vector3(0, 10, z)
    )


def _ceiling(z: Float32) -> Triangle:
    # Its front faces -z.
    return Triangle(
        Vector3(-10, -10, z), Vector3(0, 10, z), Vector3(10, -10, z)
    )


def _grid(cell: Float32 = 5, count: Int = 4) -> List[Triangle]:
    # Squares of `cell` meters on z = 0, two triangles each, centered on
    # the origin. The default has 32 triangles, enough for the CCD tree.
    var triangles = List[Triangle]()
    var half = cell * Float32(count) / 2
    for row in range(count):
        for column in range(count):
            var x = Float32(column) * cell - half
            var y = Float32(row) * cell - half
            triangles.append(
                Triangle(
                    Vector3(x, y, 0),
                    Vector3(x + cell, y, 0),
                    Vector3(x, y + cell, 0),
                )
            )
            triangles.append(
                Triangle(
                    Vector3(x + cell, y, 0),
                    Vector3(x + cell, y + cell, 0),
                    Vector3(x, y + cell, 0),
                )
            )
    return triangles^


def _mesh(
    var triangles: List[Triangle], friction: Float32 = 0, bounce: Float32 = 0
) raises -> RigidBody:
    var body = RigidBody(
        STATIC,
        Shape.mesh(triangles^),
        Mass(0),
        Vector3(0, 0, 0),
        Quaternion.identity(),
    )
    body.material = PhysicsMaterial(friction, bounce)
    return body^


def _cube(
    position: Vector3,
    velocity: Vector3,
    rotation: Quaternion = Quaternion.identity(),
    friction: Float32 = 0,
    bounce: Float32 = 0,
) raises -> RigidBody:
    # A 1 kg, 1 m cube that turns: its inverse inertia is 6 per kg m^2 on
    # every axis.
    var body = RigidBody(
        DYNAMIC,
        Shape.box(Length(0.5), Length(0.5), Length(0.5)),
        Mass(1),
        position,
        rotation,
    )
    body.linear_velocity = velocity
    body.material = PhysicsMaterial(friction, bounce)
    return body^


def _ball(
    position: Vector3,
    velocity: Vector3,
    radius: Float32 = 0.25,
    bounce: Float32 = 0,
) raises -> RigidBody:
    var body = RigidBody(
        DYNAMIC,
        Shape.sphere(Length(radius)),
        Mass(1),
        position,
        Quaternion.identity(),
    )
    body.linear_velocity = velocity
    body.material = PhysicsMaterial(0, bounce)
    return body^


def _world(brute: Bool = False) -> PhysicsWorld:
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    world.collision_detection = SPHERE_MESH_CCD
    world._ccd_brute_force = brute
    return world^


def _about_x(angle: Float64) -> Quaternion:
    return Quaternion(Float32(sin(angle / 2)), 0, 0, Float32(cos(angle / 2)))


def _lowest(world: PhysicsWorld, i: Int) -> Float64:
    # The lowest corner of a box or hull in the world.
    var low = Float64(1e30)
    for corner in world._shape(i).polyhedron.vertices:
        low = min(low, Float64(corner.z))
    return low


def _cube_energy(body: RigidBody) -> Float64:
    # Twice the kinetic energy of a 1 kg cube: v^2 + w^2 / 6.
    var v = body.linear_velocity
    var w = body.angular_velocity
    return Float64(v.dot(v)) + Float64(w.dot(w)) / 6


def test_a_flat_face_landing_takes_one_simultaneous_impulse() raises:
    # A turning cube lands flat at 30 m/s. Its four lower corners touch at
    # once, so the plastic response stops it and adds no spin. Elastic, it
    # leaves at 30 m/s. Sequential corner impulses would spin it instead.
    for bounce in [Float32(0), Float32(1)]:
        var world = _world()
        _ = world.add_body(_mesh([_floor()], bounce=bounce))
        _ = world.add_body(
            _cube(Vector3(0, 0, 0.6), Vector3(0, 0, -30), bounce=bounce)
        )
        world.step(Duration(0.01))
        ref cube = world.bodies[1]
        assert_almost_equal(cube.linear_velocity.z, 30 * bounce, atol=1e-4)
        assert_true(cube.angular_velocity.length() < 1e-4)
        assert_equal(world.contact_count, 1)
        assert_true(_lowest(world, 1) >= -_CUBE_TOLERANCE - 1e-6)
        if bounce == 0:
            assert_true(Float64(cube.position.z) <= 0.5 + 1e-5)


def test_edge_and_corner_landings_below_the_mass_center() raises:
    # An edge or a corner straight below the mass center takes the whole
    # impulse through it: no spin, and the normal speed follows e.
    var edge = _about_x(0.7853981633974483)
    # Turn the corner (-1, -1, -1) / sqrt(3) onto -z.
    var angle = acos(1 / sqrt(3.0))
    var s = Float32(sin(angle / 2) / sqrt(2.0))
    var corner = Quaternion(s, -s, 0, Float32(cos(angle / 2)))
    for pose in [edge, corner]:
        for bounce in [Float32(0), Float32(1)]:
            var world = _world()
            _ = world.add_body(_mesh([_floor()], bounce=bounce))
            _ = world.add_body(
                _cube(Vector3(0, 0, 0.95), Vector3(0, 0, -30), pose, 0, bounce)
            )
            world.step(Duration(0.01))
            ref cube = world.bodies[1]
            assert_almost_equal(cube.linear_velocity.z, 30 * bounce, atol=1e-3)
            assert_true(cube.angular_velocity.length() < 1e-3)
            assert_true(_lowest(world, 1) >= -_CUBE_TOLERANCE - 1e-6)
            assert_equal(world.contact_count, 1)


def test_an_off_center_edge_landing_follows_the_rigid_impulse() raises:
    # Tilted 0.3 rad about x, the cube's lowest edge lies parallel to x at
    # y = -0.5 cos 0.3 + 0.5 sin 0.3 from the mass center. Its two corners
    # take the impulse together, J = (1 + e) 30 / (1 + 6 y^2), so the
    # cube leaves at -30 + J m/s and turns at 6 y J rad/s about x.
    var y = -0.5 * cos(0.3) + 0.5 * sin(0.3)
    for bounce in [Float32(0), Float32(1)]:
        var world = _world()
        _ = world.add_body(_mesh([_floor()], bounce=bounce))
        _ = world.add_body(
            _cube(
                Vector3(0, 0, 0.7), Vector3(0, 0, -30), _about_x(0.3), 0, bounce
            )
        )
        world.step(Duration(0.004))
        ref cube = world.bodies[1]
        var impulse = (1 + Float64(bounce)) * 30 / (1 + 6 * y * y)
        assert_almost_equal(
            Float64(cube.linear_velocity.z), -30 + impulse, atol=0.05
        )
        assert_almost_equal(
            Float64(cube.angular_velocity.x), 6 * y * impulse, atol=0.05
        )
        assert_true(abs(cube.angular_velocity.y) < 1e-3)
        assert_true(_lowest(world, 1) >= -_CUBE_TOLERANCE - 1e-6)
        assert_equal(world.contact_count, 1)


def _tumbler(
    brute: Bool, friction: Float32, bounce: Float32
) raises -> PhysicsWorld:
    var world = _world(brute)
    _ = world.add_body(_mesh(_grid(), friction, bounce))
    var cube = _cube(
        Vector3(0, 0, 1.2), Vector3(2, 0, -30), _about_x(0.6), friction, bounce
    )
    cube.angular_velocity = Vector3(5, 1, 0)
    _ = world.add_body(cube^)
    return world^


def test_a_tumbling_cube_keeps_out_of_the_floor_and_loses_no_energy() raises:
    # Elastic and smooth, a landing keeps the energy. Plastic or rough, it
    # loses some. No step adds any, and the indexed and brute-force paths
    # agree bit for bit. The tolerance 1e-5 relative covers Float32 state.
    for bounce in [Float32(0), Float32(1)]:
        for friction in [Float32(0), Float32(0.5)]:
            var indexed = _tumbler(False, friction, bounce)
            var brute = _tumbler(True, friction, bounce)
            var before = _cube_energy(indexed.bodies[1])
            for _ in range(5):
                _step_pair(indexed, brute, 0.01)
                assert_true(_lowest(indexed, 1) >= -_CUBE_TOLERANCE - 1e-6)
            var after = _cube_energy(indexed.bodies[1])
            assert_true(after <= before * (1 + 1e-5), String(after))
            if bounce == 1 and friction == 0:
                assert_almost_equal(after, before, atol=before * 1e-4)
            else:
                assert_true(after < before * 0.9, String(after))


def _clearance(world: PhysicsWorld, i: Int, j: Int) raises -> Float64:
    # The clearance of two bodies' shapes at their present poses.
    var none = SIMD[DType.float64, 4](0)
    var a = _ccd_placed(
        world._ccd_template(i),
        _wide(world.bodies[i].world_center_of_mass()),
        world.bodies[i].rotation,
        none,
        none,
    )
    var b = _ccd_placed(
        world._ccd_template(j),
        _wide(world.bodies[j].world_center_of_mass()),
        world.bodies[j].rotation,
        none,
        none,
    )
    return _core_gap(a, b, 1e300)[0]


def _momentum(world: PhysicsWorld) -> Tuple[Vector3, Vector3, Float64]:
    # The linear momentum, the angular momentum about the origin and twice
    # the kinetic energy of 1 kg cubes and balls in a world. A ball here
    # has radius 0.25 m, so its inverse inertia is 40 per kg m^2.
    var linear = Vector3(0, 0, 0)
    var angular = Vector3(0, 0, 0)
    var energy = Float64(0)
    for body in world.bodies:
        if body.shape.kind == MESH:
            continue
        var inertia = Float32(1) / body.inverse_inertia().elements[0]
        var center = body.world_center_of_mass()
        linear = linear + body.linear_velocity
        angular = (
            angular
            + cross(center, body.linear_velocity)
            + body.angular_velocity * inertia
        )
        energy += Float64(body.linear_velocity.dot(body.linear_velocity))
        energy += Float64(
            body.angular_velocity.dot(body.angular_velocity) * inertia
        )
    return (linear, angular, energy)


def _assert_close(a: Vector3, b: Vector3, atol: Float32) raises:
    assert_true((a - b).length() <= atol, String((a - b).length()))


def test_two_turning_cubes_meet_and_keep_momentum() raises:
    # Two spinning cubes meet off center in free space. A pair response
    # keeps linear and angular momentum. Elastic and smooth it keeps the
    # energy; otherwise it loses some.
    for bounce in [Float32(0), Float32(1)]:
        for friction in [Float32(0), Float32(0.5)]:
            var world = _world()
            # Smooth and plastic, the cubes grind past each other in contact
            # for half the step: each re-closing takes a response.
            world.ccd_max_impacts = 1024
            world.ccd_max_substeps = 65536
            var a = _cube(
                Vector3(-1, 0.3, 5),
                Vector3(10, 0, 0),
                _about_x(0.4),
                friction,
                bounce,
            )
            a.angular_velocity = Vector3(1, 2, 3)
            var b = _cube(
                Vector3(1, 0, 5),
                Vector3(-10, 0, 1),
                Quaternion.identity(),
                friction,
                bounce,
            )
            b.angular_velocity = Vector3(0, -2, 1)
            _ = world.add_body(a^)
            _ = world.add_body(b^)
            var before = _momentum(world)
            world.step(Duration(0.1))
            var after = _momentum(world)
            assert_true(world.contact_count >= 1)
            _assert_close(after[0], before[0], 1e-4)
            _assert_close(after[1], before[1], 1e-3)
            assert_true(after[2] <= before[2] * (1 + 1e-5))
            if bounce == 1 and friction == 0:
                assert_almost_equal(after[2], before[2], atol=before[2] * 1e-4)
            else:
                assert_true(after[2] < before[2] * 0.99)


def test_an_elastic_head_on_cube_pair_swaps_velocities() raises:
    # Equal cubes face to face at 10 m/s each way: elastic, they swap.
    var world = _world()
    _ = world.add_body(_cube(Vector3(-1, 0, 5), Vector3(10, 0, 0), bounce=1))
    _ = world.add_body(_cube(Vector3(1, 0, 5), Vector3(-10, 0, 0), bounce=1))
    world.step(Duration(0.1))
    assert_almost_equal(world.bodies[0].linear_velocity.x, -10, atol=1e-4)
    assert_almost_equal(world.bodies[1].linear_velocity.x, 10, atol=1e-4)
    assert_true(world.bodies[0].angular_velocity.length() < 1e-4)
    assert_true(
        world.bodies[1].position.x - world.bodies[0].position.x
        >= 1 - 2 * _CUBE_TOLERANCE - 1e-5
    )


def test_a_cube_falls_onto_a_resting_ball_without_driving_it_down() raises:
    # A ball rests on the floor and a turning cube falls onto it. The
    # cube's impulse and the floor's act together, so the ball stays on
    # the floor and the cube above it.
    for bounce in [Float32(0), Float32(1)]:
        var world = _world()
        world.gravity = Vector3(0, 0, -9.8)
        world.ccd_max_impacts = 1024
        world.ccd_max_substeps = 65536
        _ = world.add_body(_mesh(_grid(), bounce=bounce))
        _ = world.add_body(
            _ball(Vector3(0, 0, 0.25), Vector3(0, 0, 0), bounce=bounce)
        )
        var cube = _cube(
            Vector3(0.1, 0, 1.1),
            Vector3(0, 0, -20),
            _about_x(0.3),
            bounce=bounce,
        )
        cube.angular_velocity = Vector3(0, 3, 0)
        _ = world.add_body(cube^)
        for _ in range(3):
            world.step(Duration(0.01))
            ref ball = world.bodies[1]
            assert_true(Float64(ball.position.z) >= 0.25 - 0.25 / 1024 - 1e-5)
            assert_true(_lowest(world, 2) >= -_CUBE_TOLERANCE - 1e-5)
            assert_true(_clearance(world, 2, 1) >= -0.25 / 1024 - 1e-5)
        assert_true(world.contact_count >= 1)


def _paddle(
    position: Vector3,
    velocity: Vector3,
    rotation: Quaternion = Quaternion.identity(),
) raises -> RigidBody:
    # A kinematic plate, 0.1 m thick and 2 m square, with restitution 1.
    var body = RigidBody(
        KINEMATIC,
        Shape.box(Length(0.05), Length(1), Length(1)),
        Mass(1),
        position,
        rotation,
    )
    body.linear_velocity = velocity
    body.material = PhysicsMaterial(0, 1)
    return body^


def test_a_kinematic_box_strikes_a_ball_as_an_infinite_mass() raises:
    # The plate moves at 10 m/s and keeps its velocity. In its frame the
    # ball rebounds with e, so it leaves at (1 + e) 10 m/s.
    for bounce in [Float32(0), Float32(1)]:
        var world = _world()
        _ = world.add_body(_paddle(Vector3(-0.5, 0, 5), Vector3(10, 0, 0)))
        world.bodies[0].material = PhysicsMaterial(0, bounce)
        _ = world.add_body(
            _ball(Vector3(0, 0, 5), Vector3(0, 0, 0), bounce=bounce)
        )
        world.step(Duration(0.05))
        assert_almost_equal(
            world.bodies[1].linear_velocity.x, 10 * (1 + bounce), atol=1e-4
        )
        assert_true(world.bodies[0].linear_velocity == Vector3(10, 0, 0))
        assert_almost_equal(world.bodies[0].position.x, 0, atol=1e-6)
        assert_equal(world.contact_count, 1)
        assert_true(
            world.bodies[1].position.x - world.bodies[0].position.x
            >= 0.3 - 0.25 / 1024 - 1e-5
        )


def test_a_spinning_kinematic_capsule_bats_a_ball() raises:
    # A kinematic capsule 2 m long lies along x and spins at 10 rad/s about
    # z. The integrator turns it by 2 atan(w h / 2) in a step, so the sweep
    # spins it at w' = 2 atan(w h / 2) / h. A ball of radius 0.25 m rests
    # at (0.8, 0.5). The bat's surface reaches it when its axis is 0.35 m
    # from the ball's center, at the angle phi - asin(0.35 / d) with phi
    # the ball's bearing and d its distance. The contact point is then
    # d cos(asin(0.35 / d)) along the axis, and an elastic hit sends the
    # ball off at twice its surface speed.
    var world = _world()
    var bat = RigidBody(
        KINEMATIC,
        Shape.capsule(Length(0.1), Length(1)),
        Mass(1),
        Vector3(0, 0, 0),
        Quaternion(
            0,
            Float32(sin(0.7853981633974483)),
            0,
            Float32(cos(0.7853981633974483)),
        ),
    )
    bat.angular_velocity = Vector3(0, 0, 10)
    bat.material = PhysicsMaterial(0, 1)
    _ = world.add_body(bat^)
    _ = world.add_body(_ball(Vector3(0.8, 0.5, 0), Vector3(0, 0, 0), bounce=1))
    var h = 0.05
    world.step(Duration(Float32(h)))
    var spin = 2 * atan(10 * h / 2) / h
    var d = sqrt(0.8 * 0.8 + 0.5 * 0.5)
    var along = d * cos(asin(0.35 / d))
    var speed = world.bodies[1].linear_velocity.length()
    assert_almost_equal(
        Float64(speed), 2 * spin * along, atol=0.02 * spin * along
    )
    assert_equal(world.contact_count, 1)
    # The bat keeps the integrator's pose and spin.
    assert_true(world.bodies[0].angular_velocity == Vector3(0, 0, 10))


def test_a_kinematic_squeeze_into_a_wall_rolls_back() raises:
    # A plate drives a ball into a wall. No impulse can open both
    # contacts, so the step raises and rolls back.
    var world = _world()
    _ = world.add_body(
        _mesh(
            [
                Triangle(
                    Vector3(0, -10, -10), Vector3(0, 10, -10), Vector3(0, 0, 10)
                )
            ]
        )
    )
    _ = world.add_body(_ball(Vector3(0.3, 0, 0), Vector3(0, 0, 0)))
    _ = world.add_body(_paddle(Vector3(0.65, 0, 0), Vector3(-5, 0, 0)))
    world.bodies[2].material = PhysicsMaterial(0, 0)
    world.bodies[1].force = Vector3(1, 2, 3)
    with assert_raises(contains="could not resolve simultaneous contacts"):
        world.step(Duration(0.1))
    assert_true(world.bodies[1].position == Vector3(0.3, 0, 0))
    assert_true(world.bodies[1].force == Vector3(1, 2, 3))
    assert_true(world.bodies[2].position == Vector3(0.65, 0, 0))


def test_a_kinematic_wedge_that_ejects_past_the_reach_rolls_back() raises:
    # Two plates close on a ball at 1 m/s each, their faces 0.1 rad off
    # vertical. The only velocity that opens both contacts is cot(0.1)
    # m/s up, almost 10 m/s. With one impact allowed, the separation
    # bounded the ball's speed by twice the plates' speed, so the response
    # would leave the ball's certified reach. The step rolls back.
    var a = 0.1
    var world = _world()
    world.ccd_max_impacts = 1
    _ = world.add_body(_ball(Vector3(0, 0, 0), Vector3(0, 0, 0)))
    var offset = Float32(0.25 + 0.05 + 0.001)
    _ = world.add_body(
        _paddle(
            Vector3(-offset, 0, 0),
            Vector3(1, 0, 0),
            Quaternion(0, Float32(sin(-a / 2)), 0, Float32(cos(-a / 2))),
        )
    )
    _ = world.add_body(
        _paddle(
            Vector3(offset, 0, 0),
            Vector3(-1, 0, 0),
            Quaternion(0, Float32(sin(a / 2)), 0, Float32(cos(a / 2))),
        )
    )
    with assert_raises(contains="certified reach"):
        world.step(Duration(0.1))
    assert_true(world.bodies[0].position == Vector3(0, 0, 0))
    assert_true(world.bodies[0].linear_velocity == Vector3(0, 0, 0))
    # With a generous impact limit the same plastic squeeze is within
    # reach.
    world.ccd_max_impacts = 16
    world.bodies[1].material = PhysicsMaterial(0, 0)
    world.bodies[2].material = PhysicsMaterial(0, 0)
    world.step(Duration(0.1))
    assert_almost_equal(
        Float64(world.bodies[0].linear_velocity.z),
        cos(a) / sin(a),
        atol=0.01,
    )


def test_kinematic_shapes_pass_meshes_and_each_other() raises:
    # A kinematic box falls through the floor and another kinematic box,
    # beside a resting dynamic cube that joins their group: no contacts.
    var world = _world()
    _ = world.add_body(_mesh([_floor()]))
    _ = world.add_body(_paddle(Vector3(0, 0, 0.2), Vector3(0, 0, -10)))
    _ = world.add_body(_paddle(Vector3(0, 0, -0.3), Vector3(0, 0, 0)))
    _ = world.add_body(_cube(Vector3(2.6, 0, 0.5), Vector3(0, 0, 0)))
    world.step(Duration(0.05))
    for event in world.events:
        assert_true(event.normal_impulse == Vector3(0, 0, 0))
    assert_almost_equal(world.bodies[1].position.z, -0.3, atol=1e-6)
    assert_true(world.bodies[3].position == Vector3(2.6, 0, 0.5))


def _chassis(position: Vector3, velocity: Vector3) raises -> RigidBody:
    # A 1500 kg box chassis, 4.5 m by 2 m by 1.5 m, with its own tensor:
    # anisotropic, so its energy depends on its orientation.
    var body = RigidBody(
        DYNAMIC,
        Shape.box(Length(2.25), Length(1), Length(0.75)),
        Mass(1500),
        position,
        _about_x(0.2),
    )
    body.linear_velocity = velocity
    body.angular_velocity = Vector3(1.5, -0.5, 2)
    body.material = PhysicsMaterial(0.8, 0.2)
    return body^


def _chassis_energy(body: RigidBody, start: Quaternion) -> Float64:
    # Twice the kinetic energy with the tensor at the step's start pose.
    var v = body.linear_velocity
    var local = start.conjugate().rotate(body.angular_velocity)
    var inverse = body.inverse_inertia()
    return 1500 * Float64(v.dot(v)) + (
        Float64(local.x * local.x) / Float64(inverse.elements[0])
        + Float64(local.y * local.y) / Float64(inverse.elements[4])
        + Float64(local.z * local.z) / Float64(inverse.elements[8])
    )


def test_a_rolling_chassis_hits_a_wall_and_loses_energy() raises:
    # A turning chassis drives at 25 m/s into a wall at x = 3 and onto the
    # floor. Its corners stay out of both by the tolerance, a bounding
    # radius over 1024, and no step adds energy in the start metric.
    var world = _world()
    var wall = Triangle(
        Vector3(3, -20, -5), Vector3(3, 0, 20), Vector3(3, 20, -5)
    )
    _ = world.add_body(_mesh(_grid(), 0.8, 0.2))
    _ = world.add_body(_mesh([wall], 0.8, 0.2))
    _ = world.add_body(_chassis(Vector3(0, 0, 1.2), Vector3(25, 0, -2)))
    var tolerance = 2.5617376914898995 / 1024
    for _ in range(4):
        var start = world.bodies[2].rotation
        var before = _chassis_energy(world.bodies[2], start)
        world.step(Duration(0.02))
        var after = _chassis_energy(world.bodies[2], start)
        assert_true(after <= before * (1 + 1e-5), String(after))
        assert_true(_lowest(world, 2) >= -tolerance - 1e-5)
        var front = Float64(-1e30)
        for corner in world._shape(2).polyhedron.vertices:
            front = max(front, Float64(corner.x))
        assert_true(front <= 3 + tolerance + 1e-5)
    assert_true(world.contact_count >= 1)
    assert_true(world.bodies[2].linear_velocity.x < 25)


def test_a_yawing_cube_slides_flat_without_an_impulse() raises:
    # A cube rests flat on the floor, slides at 5 m/s and spins about the
    # vertical. Its corners move parallel to the floor and its path bends
    # only across the spin axis, so nothing closes on the floor.
    var world = _world()
    _ = world.add_body(_mesh([_floor()], friction=0.5))
    var cube = _cube(Vector3(0, 0, 0.5), Vector3(5, 0, 0), friction=0.5)
    cube.angular_velocity = Vector3(0, 0, 10)
    _ = world.add_body(cube^)
    world.step(Duration(0.01))
    ref slid = world.bodies[1]
    assert_true(slid.linear_velocity == Vector3(5, 0, 0))
    assert_true(slid.angular_velocity == Vector3(0, 0, 10))
    assert_almost_equal(slid.position.z, 0.5, atol=1e-6)
    for event in world.events:
        assert_true(event.normal_impulse == Vector3(0, 0, 0))


def _cage(brute: Bool) raises -> PhysicsWorld:
    # A spinning elastic cube between a floor and a ceiling 0.3 m above
    # its top, with a bystander sphere inserted first.
    var world = _world(brute)
    _ = world.add_body(_ball(Vector3(50, 0, 5), Vector3(1, 0, 0)))
    world.bodies[0].angular_velocity = Vector3(0, 0, 3)
    _ = world.add_body(_mesh([_floor(), _ceiling(1.3)], bounce=1))
    var cube = _cube(
        Vector3(0, 0, 0.65), Vector3(0, 0, -60), Quaternion.identity(), 0, 1
    )
    cube.angular_velocity = Vector3(0, 0, 4)
    _ = world.add_body(cube^)
    return world^


def _pending(mut world: PhysicsWorld):
    for i in range(len(world.bodies)):
        if world.bodies[i].shape.kind == MESH:
            continue
        world.bodies[i].force = Vector3(1, -2, 3)
        world.bodies[i].torque = Vector3(0.5, 0, -0.25)
        world.bodies[i].push_velocity = Vector3(0.125, 0, -0.0625)
        world.bodies[i].push_angular = Vector3(0, 0, 0.25)


def test_a_failed_turning_box_step_restores_the_complete_state() raises:
    var indexed = _cage(False)
    var brute = _cage(True)
    var twin = _cage(False)
    # A successful step first leaves reports to keep: four elastic hits,
    # back at the start.
    _step_pair(indexed, brute, 0.02)
    twin.step(Duration(0.02))
    assert_equal(indexed.contact_count, 4)
    assert_almost_equal(indexed.bodies[2].position.z, 0.65, atol=1e-4)
    _pending(indexed)
    _pending(brute)
    _pending(twin)
    indexed.contact_count = 77
    brute.contact_count = 77
    twin.contact_count = 77
    # One impact cannot finish the step, and neither can one sub-step.
    indexed.ccd_max_impacts = 1
    brute.ccd_max_impacts = 1
    _failure_pair(indexed, brute, 0.02)
    with assert_raises(contains="impact limit exhausted"):
        indexed.step(Duration(0.02))
    indexed.ccd_max_impacts = 16
    brute.ccd_max_impacts = 16
    indexed.ccd_max_substeps = 1
    brute.ccd_max_substeps = 1
    _failure_pair(indexed, brute, 0.02)
    with assert_raises(contains="sub-step limit exhausted"):
        indexed.step(Duration(0.02))
    assert_equal(indexed.contact_count, 77)
    assert_true(indexed.bodies[2].push_angular == Vector3(0, 0, 0.25))
    # The retried step matches a twin that never failed, bit for bit.
    indexed.ccd_max_substeps = 256
    indexed.step(Duration(0.02))
    twin.step(Duration(0.02))
    _assert_world(indexed, twin)


def _drop(mode_ccd: Bool) raises -> PhysicsWorld:
    var world = _world()
    if not mode_ccd:
        world.collision_detection = DISCRETE
    _ = world.add_body(_mesh(_grid()))
    var cube = _cube(Vector3(0, 0, 0.6), Vector3(0, 0, -30), _about_x(0.1))
    cube.angular_velocity = Vector3(0, 0, 1)
    _ = world.add_body(cube^)
    return world^


def _restart(mut world: PhysicsWorld):
    world.bodies[1].position = Vector3(0, 0, 0.75)
    world.bodies[1].rotation = _about_x(0.1)
    world.bodies[1].linear_velocity = Vector3(0, 0, -30)
    world.bodies[1].angular_velocity = Vector3(0, 0, 1)


def test_a_turning_cube_switches_modes_and_ghosts() raises:
    var world = _drop(False)
    var reference = _drop(False)
    # Discrete: the step is a discrete step, no CCD index, and the cube
    # sinks into the floor.
    world.step(Duration(0.01))
    reference.step(Duration(0.01))
    _assert_world(world, reference)
    assert_equal(world._ccd_index.count, -1)
    assert_true(_lowest(world, 1) < -0.05)
    # CCD stops it on the floor.
    world.collision_detection = SPHERE_MESH_CCD
    _restart(world)
    world.step(Duration(0.01))
    assert_equal(world._ccd_index.count, 32)
    assert_true(world.contact_count >= 1)
    assert_true(_lowest(world, 1) >= -_CUBE_TOLERANCE - 1e-6)
    # A ghost passes through, and back on it stops again.
    world.bodies[1].collides = False
    _restart(world)
    world.step(Duration(0.01))
    assert_equal(world.contact_count, 0)
    assert_true(_lowest(world, 1) < -0.05)
    world.bodies[1].collides = True
    _restart(world)
    world.step(Duration(0.01))
    assert_true(_lowest(world, 1) >= -_CUBE_TOLERANCE - 1e-6)
    # A disabled mesh is a ghost too.
    world.bodies[0].collides = False
    _restart(world)
    world.step(Duration(0.01))
    assert_true(_lowest(world, 1) < -0.05)
    world.bodies[0].collides = True
    # Back in the discrete mode, the step matches a discrete world again.
    world.collision_detection = DISCRETE
    _restart(world)
    _restart(reference)
    world.step(Duration(0.01))
    reference.step(Duration(0.01))
    _assert_world(world, reference)


def test_equal_time_contacts_report_in_mesh_order() raises:
    # A cube lands flat across two meshes at once. One response acts on
    # both, and the reports follow mesh insertion order, every time.
    var first = List[Int]()
    for _ in range(2):
        var world = _world()
        _ = world.add_body(
            _mesh(
                [
                    Triangle(
                        Vector3(0, -10, 0), Vector3(10, 0, 0), Vector3(0, 10, 0)
                    )
                ]
            )
        )
        _ = world.add_body(
            _mesh(
                [
                    Triangle(
                        Vector3(0, -10, 0),
                        Vector3(0, 10, 0),
                        Vector3(-10, 0, 0),
                    )
                ]
            )
        )
        _ = world.add_body(_cube(Vector3(0, 0, 0.6), Vector3(0, 0, -30)))
        world.step(Duration(0.01))
        assert_equal(world.contact_count, 2)
        assert_equal(world.events[0].body.value, 2)
        assert_equal(world.events[0].other.value, 0)
        assert_equal(world.events[2].other.value, 1)
        assert_almost_equal(
            world.events[0].normal_impulse.z + world.events[2].normal_impulse.z,
            30,
            atol=1e-4,
        )
        assert_true(world.bodies[2].angular_velocity.length() < 1e-4)
        first.append(Int(world.events[0].normal_impulse.z * 1000))
    assert_equal(first[0], first[1])


def test_unsupported_worlds_are_still_refused() raises:
    # A moving mesh: its triangles never move, in either mode.
    var moving = _world()
    _ = moving.add_body(_mesh([_floor()]))
    _ = moving.add_body(_cube(Vector3(0, 0, 2), Vector3(0, 0, 0)))
    moving.bodies[0].linear_velocity = Vector3(0, 0, 1)
    with assert_raises(contains="motionless static meshes"):
        moving.step(Duration(0.01))
    # A static primitive.
    var primitive = _world()
    _ = primitive.add_body(
        RigidBody(
            STATIC,
            Shape.box(Length(1), Length(1), Length(1)),
            Mass(0),
            Vector3(0, 0, 0),
            Quaternion.identity(),
        )
    )
    with assert_raises(contains="static primitives"):
        primitive.step(Duration(0.01))
    # A box that can turn needs a positive definite tensor.
    var skew = _world()
    var cube = _cube(Vector3(0, 0, 2), Vector3(0, 0, 0))
    var tensor = Matrix3()
    tensor.elements[0] = 6
    tensor.elements[4] = 0
    tensor.elements[8] = 6
    cube.set_inverse_inertia(tensor)
    _ = skew.add_body(cube^)
    with assert_raises(contains="symmetric positive definite"):
        skew.step(Duration(0.01))
    # Two capsules whose axes already cross cannot be separated by a sweep.
    var crossed = _world()
    var upright = RigidBody(
        DYNAMIC,
        Shape.capsule(Length(0.1), Length(0.5)),
        Mass(1),
        Vector3(0, 0, 5),
        Quaternion.identity(),
    )
    upright.angular_velocity = Vector3(1, 0, 0)
    _ = crossed.add_body(upright^)
    _ = crossed.add_body(
        RigidBody(
            DYNAMIC,
            Shape.capsule(Length(0.1), Length(0.5)),
            Mass(1),
            Vector3(0, 0, 5),
            _about_x(1.5707963267948966),
        )
    )
    with assert_raises(contains="overlap past their axes"):
        crossed.step(Duration(0.01))
    assert_true(crossed.bodies[0].position == Vector3(0, 0, 5))


def test_too_many_simultaneous_contacts_roll_back() raises:
    # A cube landing flat on a 2.5 cm grid touches hundreds of triangle
    # corners at once, more than one response may solve.
    var world = _world()
    _ = world.add_body(_mesh(_grid(0.025, 48)))
    _ = world.add_body(_cube(Vector3(0.01, 0.01, 0.6), Vector3(0, 0, -30)))
    with assert_raises(contains="exceed 256"):
        world.step(Duration(0.01))
    assert_true(world.bodies[1].position == Vector3(0.01, 0.01, 0.6))


def test_the_contact_solver_solves_steps_back_and_refuses() raises:
    # One contact closes at 2 m/s with response 2 per unit impulse, the
    # other opens: the first takes impulse 1, the second none.
    var single = _ccd_qp([2.0, 0, 0, 1], [-2.0, 1])
    assert_almost_equal(single[0], 1, atol=1e-12)
    assert_equal(single[1], 0)
    # Coupled contacts where the active set first takes the third
    # contact, then steps back to the second alone: the impulses (0, 1, 0)
    # leave closing speeds (1, 0, 1).
    var coupled = _ccd_qp([5.0, -1, 0, -1, 2, 4, 0, 4, 9], [2.0, -2, -3])
    assert_almost_equal(coupled[0], 0, atol=1e-12)
    assert_almost_equal(coupled[1], 1, atol=1e-12)
    assert_almost_equal(coupled[2], 0, atol=1e-12)
    # The same with a partial pivot: (0, 1, 0) leaves (4, 0, 0).
    var pivot = _ccd_qp([4.0, 2, 4, 2, 2, 3, 4, 3, 5], [2.0, -2, -3])
    assert_almost_equal(pivot[1], 1, atol=1e-12)
    assert_almost_equal(pivot[2], 0, atol=1e-12)
    # Nothing closes: no impulse.
    assert_equal(_ccd_qp([1.0], [0.5])[0], 0)
    # No impulse can open a contact with no response.
    with assert_raises(contains="could not resolve"):
        _ = _ccd_qp([0.0], [-1.0])
    # A matrix that is not positive semidefinite never settles.
    with assert_raises(contains="could not resolve"):
        _ = _ccd_qp([-1.0], [-1.0])


def test_first_roots_and_hull_distances() raises:
    # room + rate t - curvature t^2 / 2 with room 1.
    assert_almost_equal(_first_root(1, -1, 0), 1, atol=1e-15)
    assert_equal(_first_root(1, 1, 0), 1e300)
    # With curvature 2 the roots of 1 -/+ t - t^2 are (sqrt(5) -/+ 1) / 2.
    assert_almost_equal(_first_root(1, -1, 2), (sqrt(5.0) - 1) / 2, atol=1e-15)
    assert_almost_equal(_first_root(1, 1, 2), (sqrt(5.0) + 1) / 2, atol=1e-15)
    # A triangle on z = 0: above, behind and beside it.
    var face = _triangle_core(_floor())
    var up = SIMD[DType.float64, 4](0, 0, 2, 0)
    assert_almost_equal(_hull_distance(up, face), 2, atol=1e-15)
    assert_almost_equal(_hull_distance(-up, face), -2, atol=1e-15)
    var side = SIMD[DType.float64, 4](0, -13, 4, 0)
    assert_almost_equal(_hull_distance(side, face), 5, atol=1e-12)


def test_a_turning_capsule_strikes_a_cube_and_keeps_momentum() raises:
    # A spinning capsule flies into a resting turning cube in free space.
    # The pair response keeps the momentum; elastic and smooth it keeps the
    # energy. The two end clear of each other within the tolerance.
    for bounce in [Float32(0), Float32(1)]:
        var world = _world()
        # Plastic, the rod grinds along the cube while both turn.
        world.ccd_max_impacts = 1024
        world.ccd_max_substeps = 65536
        var rod = RigidBody(
            DYNAMIC,
            Shape.capsule(Length(0.25), Length(0.4)),
            Mass(1),
            Vector3(-1.2, 0.2, 5),
            _about_x(0.5),
        )
        var inverse = Matrix3()
        inverse.elements[0] = 40
        inverse.elements[4] = 40
        inverse.elements[8] = 40
        rod.set_inverse_inertia(inverse)
        rod.linear_velocity = Vector3(15, 0, 0)
        rod.angular_velocity = Vector3(0, 0, 4)
        rod.material = PhysicsMaterial(0, bounce)
        _ = world.add_body(rod^)
        _ = world.add_body(
            _cube(Vector3(0, 0, 5), Vector3(0, 0, 0), bounce=bounce)
        )
        var before = _momentum(world)
        world.step(Duration(0.1))
        var after = _momentum(world)
        assert_true(world.contact_count >= 1)
        _assert_close(after[0], before[0], 1e-4)
        _assert_close(after[1], before[1], 1e-3)
        assert_true(after[2] <= before[2] * (1 + 1e-5))
        if bounce == 1:
            assert_almost_equal(after[2], before[2], atol=before[2] * 1e-4)
        assert_true(_clearance(world, 0, 1) >= -0.25 / 1024 - 1e-5)


def test_every_kinematic_sphere_variant_bats_a_ball() raises:
    # A kinematic sphere that sits off its body or its mass, or that spins,
    # takes conservative advancement with the ball it strikes. A plain one
    # takes the exact group sweep. Each moves at 10 m/s and keeps it; the
    # ball, struck through its center, leaves at 20 m/s.
    for variant in range(5):
        var world = _world()
        var bat = RigidBody(
            KINEMATIC,
            Shape.sphere(Length(0.25)),
            Mass(1),
            Vector3(-0.6, 0, 5),
            Quaternion.identity(),
        )
        bat.linear_velocity = Vector3(10, 0, 0)
        bat.material = PhysicsMaterial(0, 1)
        if variant == 1:
            bat.shape_position = Vector3(0.1, 0, 0)
            bat.position = Vector3(-0.7, 0, 5)
        elif variant == 2:
            bat.center_of_mass = Vector3(0, 0, 0.1)
        elif variant == 3:
            bat.angular_velocity = Vector3(1, 0, 0)
        elif variant == 4:
            bat.push_angular = Vector3(1, 0, 0)
        _ = world.add_body(bat^)
        _ = world.add_body(_ball(Vector3(0, 0, 5), Vector3(0, 0, 0), bounce=1))
        world.step(Duration(0.05))
        assert_almost_equal(
            world.bodies[1].linear_velocity.x,
            20,
            atol=1e-3,
            msg=String(variant),
        )
        assert_true(world.bodies[0].linear_velocity == Vector3(10, 0, 0))
        assert_equal(world.contact_count, 1)


def test_a_cube_lands_in_a_corner_against_two_meshes() raises:
    # A cube slides into a wall at x = 0.5 as it lands on the floor. Its
    # lower corners on the wall touch both: one point, two normals, both
    # kept. The response stops it on both.
    var world = _world()
    _ = world.add_body(_mesh([_floor()]))
    # The wall at x = 0.5 faces -x, toward the cube.
    _ = world.add_body(
        _mesh(
            [
                Triangle(
                    Vector3(0.5, -10, -5),
                    Vector3(0.5, 0, 10),
                    Vector3(0.5, 10, -5),
                )
            ]
        )
    )
    _ = world.add_body(_cube(Vector3(-0.1, 0, 0.6), Vector3(60, 0, -60)))
    world.step(Duration(0.01))
    ref cube = world.bodies[2]
    assert_almost_equal(cube.linear_velocity.x, 0, atol=1e-3)
    assert_almost_equal(cube.linear_velocity.z, 0, atol=1e-3)
    assert_true(cube.angular_velocity.length() < 1e-3)
    assert_true(_lowest(world, 2) >= -_CUBE_TOLERANCE - 1e-6)
    assert_equal(world.contact_count, 2)


def test_a_turning_cube_rises_through_the_back_of_a_floor() raises:
    # The mesh is one-sided: a spinning cube wholly below a floor that
    # faces up passes up through it, and so does its group partner.
    var world = _world()
    _ = world.add_body(_mesh(_grid()))
    var cube = _cube(Vector3(0, 0, -1), Vector3(0, 0, 60), _about_x(0.2))
    cube.angular_velocity = Vector3(0, 0, 3)
    _ = world.add_body(cube^)
    _ = world.add_body(_ball(Vector3(2, 0, -1), Vector3(0, 0, 60)))
    world.step(Duration(0.02))
    assert_equal(world.contact_count, 0)
    assert_almost_equal(world.bodies[1].position.z, 0.2, atol=1e-5)
    assert_almost_equal(world.bodies[2].position.z, 0.2, atol=1e-5)


def test_two_cubes_land_side_by_side_in_one_response() raises:
    # Two turning cubes 0.2 m apart land flat together. One response
    # stops both on the floor, with no spin.
    var world = _world()
    _ = world.add_body(_mesh(_grid()))
    _ = world.add_body(_cube(Vector3(-0.6, 0, 0.6), Vector3(0, 0, -30)))
    _ = world.add_body(_cube(Vector3(0.6, 0, 0.6), Vector3(0, 0, -30)))
    world.step(Duration(0.01))
    for i in [1, 2]:
        ref cube = world.bodies[i]
        assert_almost_equal(cube.linear_velocity.z, 0, atol=1e-4)
        assert_true(cube.angular_velocity.length() < 1e-4)
        assert_true(_lowest(world, i) >= -_CUBE_TOLERANCE - 1e-6)
    assert_true(world.contact_count >= 2)


def test_contact_collection_and_the_empty_solver() raises:
    # No contact points add nothing, and no contacts take no impulse.
    var group = _CCDGroup([0])
    _ccd_collect(
        group,
        0,
        -1,
        0,
        List[SIMD[DType.float64, 4]](),
        SIMD[DType.float64, 4](0, 0, 1, 0),
        1e-9,
    )
    assert_equal(len(group.points), 0)
    assert_equal(len(_ccd_qp(List[Float64](), List[Float64]())), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
