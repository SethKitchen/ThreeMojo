# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Rollback, mode, grazing and energy controls for general CCD shapes (#635).

The shapes are boxes, hulls, rotation-locked capsules and turning capsules.
Each expected value comes by hand from the geometry or from the impulse law.
"""

from extensions.physics.body import (
    DYNAMIC,
    STATIC,
    RigidBody,
    locked_inverse_inertia,
)
from extensions.physics.ccd import (
    DISCRETE,
    SPHERE_MESH_CCD,
    _sweep_convex_triangle,
)
from extensions.physics.shape import MESH, PhysicsMaterial, Polyhedron, Shape
from extensions.physics.world import PhysicsWorld
from math.matrix3 import Matrix3
from math.quaternion import Quaternion
from math.triangle import Triangle
from math.vector3 import Vector3
from std.math import cos, sin
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from tests.test_physics_ccd_index import (
    _assert_body,
    _assert_world,
    _failure_pair,
    _step_pair,
)
from units.si import Duration, Length, Mass

# The shapes of the mode and rollback controls.
comptime _BOX = 0
comptime _HULL = 1
comptime _LOCKED_CAPSULE = 2
comptime _TURNING_CAPSULE = 3


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


def _grid() -> List[Triangle]:
    # 32 triangles on z = 0, enough for the CCD tree.
    var triangles = List[Triangle]()
    for row in range(4):
        for column in range(4):
            var x = Float32(column) * 5 - 10
            var y = Float32(row) * 5 - 10
            triangles.append(
                Triangle(
                    Vector3(x, y, 0), Vector3(x + 5, y, 0), Vector3(x, y + 5, 0)
                )
            )
            triangles.append(
                Triangle(
                    Vector3(x + 5, y, 0),
                    Vector3(x + 5, y + 5, 0),
                    Vector3(x, y + 5, 0),
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


def _tilt() -> Quaternion:
    # 0.6 rad about x.
    return Quaternion(Float32(sin(0.3)), 0, 0, Float32(cos(0.3)))


def _shape(
    kind: Int,
    position: Vector3,
    velocity: Vector3,
    friction: Float32 = 0,
    bounce: Float32 = 0,
) raises -> RigidBody:
    # A 1 kg body. The box is a 1 m cube. The hull is a tetrahedron whose
    # lowest corner is 0.5 m below its origin. The locked capsule has
    # radius 0.1 m and half height 0.2 m. The turning capsule has radius
    # 0.1 m, half height 0.4 m, a solid rod's inertia and a 0.6 rad tilt.
    var shape = Shape.box(Length(0.5), Length(0.5), Length(0.5))
    var rotation = Quaternion.identity()
    if kind == _HULL:
        shape = Shape.convex(
            [
                Vector3(0, 0, -0.5),
                Vector3(0.5, 0, 0.5),
                Vector3(-0.5, 0.5, 0.5),
                Vector3(-0.5, -0.5, 0.5),
            ]
        )
    elif kind == _LOCKED_CAPSULE:
        shape = Shape.capsule(Length(0.1), Length(0.2))
    elif kind == _TURNING_CAPSULE:
        shape = Shape.capsule(Length(0.1), Length(0.4))
        rotation = _tilt()
    var body = RigidBody(DYNAMIC, shape^, Mass(1), position, rotation)
    if kind == _TURNING_CAPSULE:
        var inverse = Matrix3()
        inverse.elements[0] = 15
        inverse.elements[4] = 15
        inverse.elements[8] = 200
        body.set_inverse_inertia(inverse)
    else:
        body.set_inverse_inertia(locked_inverse_inertia())
    body.linear_velocity = velocity
    body.material = PhysicsMaterial(friction, bounce)
    return body^


def _bystander() raises -> RigidBody:
    # A sphere far from every mesh and body. It is inserted first, so the
    # step moves it before another body fails, and rollback must undo it.
    var body = RigidBody(
        DYNAMIC,
        Shape.sphere(Length(0.1)),
        Mass(2),
        Vector3(50, 0, 5),
        Quaternion.identity(),
    )
    body.linear_velocity = Vector3(1, 0, 0)
    body.angular_velocity = Vector3(0, 0, 3)
    return body^


def _world(brute: Bool) -> PhysicsWorld:
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    world.collision_detection = SPHERE_MESH_CCD
    world._ccd_brute_force = brute
    return world^


def _lowest(body: RigidBody) -> Float64:
    # The lowest point of a capsule: its lower axis end less the radius.
    var half = body.shape_world_rotation().rotate(
        Vector3(0, 0, body.shape.half_height)
    )
    var at = body.shape_world_position()
    return min(Float64(at.z - half.z), Float64(at.z + half.z)) - Float64(
        body.shape.radius
    )


def _pending(mut world: PhysicsWorld, turning: Bool):
    # Pending forces, torques and split pushes that a failed step must
    # keep. A body that cannot turn must have no spin push.
    for i in range(len(world.bodies)):
        if world.bodies[i].shape.kind == MESH:
            continue
        world.bodies[i].force = Vector3(1, -2, 3)
        world.bodies[i].torque = Vector3(0.5, 0, -0.25)
        world.bodies[i].push_velocity = Vector3(0.125, 0, -0.0625)
    world.bodies[0].push_angular = Vector3(0, 0.25, 0)
    if turning:
        world.bodies[len(world.bodies) - 1].push_angular = Vector3(0.5, 0, 0)


def _cage(kind: Int, brute: Bool) raises -> PhysicsWorld:
    # An elastic box or hull between a floor at z = 0 and a ceiling at
    # z = 1.3. Both shapes are 1 m tall, so 0.3 m of room remains.
    var world = _world(brute)
    _ = world.add_body(_bystander())
    _ = world.add_body(_mesh([_floor(), _ceiling(1.3)], bounce=1))
    _ = world.add_body(
        _shape(kind, Vector3(0, 0, 0.65), Vector3(0, 0, -60), bounce=1)
    )
    return world^


def test_a_failed_box_or_hull_step_restores_the_complete_state() raises:
    for kind in [_BOX, _HULL]:
        var indexed = _cage(kind, False)
        var brute = _cage(kind, True)
        var twin = _cage(kind, False)
        # A successful step first leaves reports to keep. The shape falls
        # 0.15 m, crosses the 0.3 m room three times and rises 0.15 m in
        # 1.2 m of travel: four impacts, back at its start at -60 m/s.
        _step_pair(indexed, brute, 0.02)
        twin.step(Duration(0.02))
        assert_equal(indexed.contact_count, 4)
        assert_equal(len(indexed.events), 8)
        assert_almost_equal(indexed.bodies[2].position.z, 0.65, atol=1e-5)
        assert_almost_equal(indexed.bodies[2].linear_velocity.z, -60, atol=1e-4)
        _pending(indexed, False)
        _pending(brute, False)
        _pending(twin, False)
        indexed.contact_count = 77
        brute.contact_count = 77
        twin.contact_count = 77
        # One impact cannot finish the step. Every body, the reports, the
        # count, the body order and the dirty flag stay as they were.
        indexed.ccd_max_impacts = 1
        brute.ccd_max_impacts = 1
        _failure_pair(indexed, brute, 0.02)
        with assert_raises(contains="impact limit exhausted"):
            indexed.step(Duration(0.02))
        assert_equal(indexed.contact_count, 77)
        assert_equal(len(indexed.events), 8)
        assert_true(indexed.bodies[0].force == Vector3(1, -2, 3))
        assert_true(
            indexed.bodies[2].push_velocity == Vector3(0.125, 0, -0.0625)
        )
        # The failed steps leave no trace: the retried step matches a twin
        # that never failed, bit for bit.
        indexed.ccd_max_impacts = 16
        indexed.step(Duration(0.02))
        twin.step(Duration(0.02))
        _assert_world(indexed, twin)
        assert_true(indexed.bodies[0].force == Vector3(0, 0, 0))


def _neighbors(kind: Int, brute: Bool) raises -> PhysicsWorld:
    # A falling shape whose reach overlaps a second shape above it.
    var world = _world(brute)
    _ = world.add_body(_bystander())
    _ = world.add_body(_mesh([_floor()]))
    _ = world.add_body(_shape(kind, Vector3(0, 0, 0.65), Vector3(0, 0, -30)))
    _ = world.add_body(_shape(kind, Vector3(0, 0, 2), Vector3(0, 0, 0)))
    _pending(world, False)
    return world^


def test_a_refused_box_or_hull_step_keeps_pending_forces() raises:
    # The second support check runs after forces change velocities. A
    # shape that can reach another moving body is refused there, and the
    # step must give back the forces and the velocities.
    for kind in [_BOX, _HULL]:
        var indexed = _neighbors(kind, False)
        var brute = _neighbors(kind, True)
        _failure_pair(indexed, brute, 0.01)
        with assert_raises(contains="must not reach another moving body"):
            indexed.step(Duration(0.01))


def _tumbler(brute: Bool) raises -> PhysicsWorld:
    # A turning capsule tumbles onto a 32-triangle floor.
    var world = _world(brute)
    _ = world.add_body(_bystander())
    _ = world.add_body(_mesh(_grid()))
    _ = world.add_body(
        _shape(_TURNING_CAPSULE, Vector3(0, 0, 0.8), Vector3(0, 0, -30))
    )
    world.bodies[2].angular_velocity = Vector3(4, 0, 0)
    return world^


def _rearm(mut world: PhysicsWorld, spin: Float32):
    # Back above the floor, falling and turning, with pending pushes.
    world.bodies[2].position = Vector3(0, 0, 0.8)
    world.bodies[2].rotation = _tilt()
    world.bodies[2].linear_velocity = Vector3(0, 0, -30)
    world.bodies[2].angular_velocity = Vector3(spin, 0, 0)
    _pending(world, True)


def test_a_failed_turning_step_restores_the_complete_state() raises:
    var indexed = _tumbler(False)
    var brute = _tumbler(True)
    var twin = _tumbler(False)
    # A successful landing first leaves reports to keep.
    _step_pair(indexed, brute, 0.02)
    twin.step(Duration(0.02))
    var reports = len(indexed.events)
    assert_true(reports >= 2)
    # Spun at 40 rad/s for 0.1 s, the capsule bounces more than once, so
    # one impact cannot land it.
    _rearm(indexed, 40)
    _rearm(brute, 40)
    indexed.ccd_max_impacts = 1
    brute.ccd_max_impacts = 1
    _failure_pair(indexed, brute, 0.1)
    with assert_raises(contains="impact limit exhausted"):
        indexed.step(Duration(0.1))
    # One sub-step cannot finish it either.
    indexed.ccd_max_impacts = 16
    brute.ccd_max_impacts = 16
    indexed.ccd_max_substeps = 1
    brute.ccd_max_substeps = 1
    _failure_pair(indexed, brute, 0.1)
    with assert_raises(contains="sub-step limit exhausted"):
        indexed.step(Duration(0.1))
    assert_equal(len(indexed.events), reports)
    assert_true(indexed.bodies[2].push_angular == Vector3(0.5, 0, 0))
    assert_true(indexed.bodies[2].rotation == _tilt())
    assert_true(indexed.bodies[2].torque == Vector3(0.5, 0, -0.25))
    # The retried step matches a twin that never failed, bit for bit.
    indexed.ccd_max_substeps = 256
    _rearm(indexed, 4)
    _rearm(twin, 4)
    indexed.step(Duration(0.02))
    twin.step(Duration(0.02))
    _assert_world(indexed, twin)


def _drop(kind: Int, mode_ccd: Bool) raises -> PhysicsWorld:
    # The shape's lowest point starts 0.1 m above the indexed floor and
    # one step travels 0.3 m.
    var world = _world(False)
    if not mode_ccd:
        world.collision_detection = DISCRETE
    _ = world.add_body(_mesh(_grid()))
    _ = world.add_body(_shape(kind, _start(kind), Vector3(0, 0, -30)))
    return world^


def _start(kind: Int) -> Vector3:
    if kind == _HULL:
        return Vector3(0.25, 0.25, 0.6)
    if kind == _LOCKED_CAPSULE:
        return Vector3(0, 0, 0.4)
    if kind == _TURNING_CAPSULE:
        # The tilted lower end is 0.4 cos(0.6) + 0.1 below the center.
        return Vector3(0, 0, Float32(0.2 + 0.4 * cos(0.6)))
    return Vector3(0, 0, 0.6)


def _rest(kind: Int) -> Float64:
    # The center height when the lowest point is on the floor.
    return Float64(_start(kind).z) - 0.1


def _restart(mut world: PhysicsWorld, kind: Int):
    world.bodies[1].position = _start(kind)
    world.bodies[1].rotation = Quaternion.identity()
    if kind == _TURNING_CAPSULE:
        world.bodies[1].rotation = _tilt()
    world.bodies[1].linear_velocity = Vector3(0, 0, -30)
    world.bodies[1].angular_velocity = Vector3(0, 0, 0)
    world.bodies[1].push_velocity = Vector3(0, 0, 0)
    world.bodies[1].push_angular = Vector3(0, 0, 0)


def test_every_shape_switches_between_discrete_and_ccd() raises:
    for kind in [_BOX, _HULL, _LOCKED_CAPSULE, _TURNING_CAPSULE]:
        var world = _drop(kind, False)
        var reference = _drop(kind, False)
        # In the discrete mode the world steps exactly as a discrete world
        # does, builds no CCD index, and the shape sinks into the floor.
        world.step(Duration(0.01))
        reference.step(Duration(0.01))
        _assert_world(world, reference)
        assert_equal(world._ccd_index.count, -1)
        assert_true(
            Float64(world.bodies[1].position.z) < _rest(kind) - 0.05,
            String(kind),
        )
        # Switched to CCD, the same drop stops on the floor.
        world.collision_detection = SPHERE_MESH_CCD
        _restart(world, kind)
        world.step(Duration(0.01))
        assert_equal(world._ccd_index.count, 32)
        assert_true(world.contact_count >= 1)
        if kind == _TURNING_CAPSULE:
            assert_true(_lowest(world.bodies[1]) >= -0.1 / 1024 - 1e-5)
        else:
            assert_almost_equal(
                Float64(world.bodies[1].position.z), _rest(kind), atol=1e-5
            )
            assert_almost_equal(world.bodies[1].linear_velocity.z, 0, atol=1e-5)
        # With collisions off it passes through, and back on it stops.
        world.bodies[1].collides = False
        _restart(world, kind)
        world.step(Duration(0.01))
        assert_equal(world.contact_count, 0)
        assert_almost_equal(
            Float64(world.bodies[1].position.z),
            Float64(_start(kind).z) - 0.3,
            atol=1e-5,
        )
        world.bodies[1].collides = True
        _restart(world, kind)
        world.step(Duration(0.01))
        assert_true(world.contact_count >= 1)
        # Back in the discrete mode, the step is the first discrete step
        # again, bit for bit. No CCD state remains.
        world.collision_detection = DISCRETE
        _restart(world, kind)
        _restart(reference, kind)
        world.step(Duration(0.01))
        reference.step(Duration(0.01))
        _assert_world(world, reference)


def test_a_mesh_added_while_discrete_stops_a_box_under_ccd() raises:
    var world = _drop(_BOX, False)
    _ = world.add_body(_mesh([_floor(1)]))
    world.step(Duration(0.01))
    world.collision_detection = SPHERE_MESH_CCD
    _restart(world, _BOX)
    world.bodies[1].position = Vector3(0, 0, 1.6)
    world.step(Duration(0.01))
    # The index holds the new triangle, and the box rests on it.
    assert_equal(world._ccd_index.count, 33)
    assert_equal(world.events[0].other.value, 2)
    assert_almost_equal(world.bodies[1].position.z, 1.5, atol=1e-5)


def test_a_box_sliding_flat_on_the_floor_takes_no_impulse() raises:
    # An exact parallel slide at contact: the box rests on the floor with
    # its face on the plane and slides at 5 m/s with friction. It never
    # closes on the floor, so no impulse acts and nothing slows it.
    for kind in [_BOX, _LOCKED_CAPSULE]:
        var world = _world(False)
        _ = world.add_body(_mesh([_floor()], friction=0.5))
        var height = Float32(0.5) if kind == _BOX else Float32(0.3)
        var body = _shape(
            kind, Vector3(0, 0, height), Vector3(5, 0, 0), friction=0.5
        )
        _ = world.add_body(body^)
        world.step(Duration(0.01))
        ref slid = world.bodies[1]
        assert_true(slid.linear_velocity == Vector3(5, 0, 0))
        assert_almost_equal(slid.position.x, 0.05, atol=1e-7)
        assert_equal(slid.position.z, height)
        for event in world.events:
            assert_true(event.normal_impulse == Vector3(0, 0, 0))


def test_a_box_sliding_onto_a_triangle_at_its_face_plane_takes_no_impulse() raises:
    # The triangle covers y >= 0 on z = 0. The box starts off it with its
    # bottom face exactly on the face plane and slides 1 m sideways onto
    # it. The face-normal axis has no travel and only touches, so it
    # separates the box from the triangle for the whole step.
    for friction in [Float32(0), Float32(0.5)]:
        var world = _world(False)
        _ = world.add_body(
            _mesh(
                [
                    Triangle(
                        Vector3(-10, 0, 0), Vector3(10, 0, 0), Vector3(0, 10, 0)
                    )
                ],
                friction=friction,
            )
        )
        _ = world.add_body(
            _shape(
                _BOX, Vector3(0, -1, 0.5), Vector3(0, 100, 0), friction=friction
            )
        )
        world.step(Duration(0.01))
        ref slid = world.bodies[1]
        assert_true(slid.linear_velocity == Vector3(0, 100, 0))
        assert_almost_equal(slid.position.y, 0, atol=1e-6)
        assert_equal(slid.position.z, 0.5)
        for event in world.events:
            assert_true(event.normal_impulse == Vector3(0, 0, 0))


def _edge_world(side: Float32) raises -> PhysicsWorld:
    # The triangle covers y >= 0 on z = 0, so its edge lies on y = 0. The
    # box's +y face is at y = side. The box falls 0.3 m past the plane.
    var world = _world(False)
    _ = world.add_body(
        _mesh(
            [Triangle(Vector3(-10, 0, 0), Vector3(10, 0, 0), Vector3(0, 10, 0))]
        )
    )
    _ = world.add_body(
        _shape(_BOX, Vector3(0, side - 0.5, 0.6), Vector3(0, 0, -30))
    )
    return world^


def test_a_box_grazing_a_triangle_edge_passes() raises:
    # The face slides down the edge with zero clearance and never enters
    # the triangle: no impact, and the box ends 0.3 m lower.
    var graze = _edge_world(0)
    graze.step(Duration(0.01))
    assert_equal(graze.contact_count, 0)
    assert_true(graze.bodies[1].linear_velocity == Vector3(0, 0, -30))
    assert_almost_equal(graze.bodies[1].position.z, 0.3, atol=1e-6)
    # 1 mm clear of the edge it also passes.
    var clear = _edge_world(-0.001)
    clear.step(Duration(0.01))
    assert_equal(clear.contact_count, 0)
    # 1 mm over the triangle, its bottom face lands on the face.
    var over = _edge_world(0.001)
    over.step(Duration(0.01))
    assert_equal(over.contact_count, 1)
    assert_almost_equal(over.bodies[1].position.z, 0.5, atol=1e-5)
    assert_almost_equal(over.bodies[1].linear_velocity.z, 0, atol=1e-5)


def _unit_cube(
    center: SIMD[DType.float64, 4],
) -> Tuple[
    List[SIMD[DType.float64, 4]],
    List[SIMD[DType.float64, 4]],
    List[SIMD[DType.float64, 4]],
]:
    # A 1 m cube's corners, face normals and edges in the world.
    var cube = Polyhedron.box(Vector3(0.5, 0.5, 0.5))
    var corners = List[SIMD[DType.float64, 4]]()
    for corner in cube.vertices:
        corners.append(
            SIMD[DType.float64, 4](
                Float64(corner.x), Float64(corner.y), Float64(corner.z), 0
            )
            + center
        )
    var faces = List[SIMD[DType.float64, 4]]()
    for normal in cube.normals:
        faces.append(
            SIMD[DType.float64, 4](
                Float64(normal.x), Float64(normal.y), Float64(normal.z), 0
            )
        )
    var edges = List[SIMD[DType.float64, 4]]()
    for k in range(len(cube.edge_a)):
        edges.append(corners[cube.edge_b[k]] - corners[cube.edge_a[k]])
    return (corners^, faces^, edges^)


def test_a_still_touching_axis_separates_the_whole_sweep() raises:
    # The triangle covers y >= 0 on z = 0. A cube falls 0.3 m from 0.1 m
    # above the plane. Along y it does not move.
    var strip = Triangle(
        Vector3(-10, 0, 0), Vector3(10, 0, 0), Vector3(0, 10, 0)
    )
    var down = SIMD[DType.float64, 4](0, 0, -0.3, 0)
    # Its +y face on the edge line: touching on y for the whole sweep.
    var low = _unit_cube(SIMD[DType.float64, 4](0, -0.5, 0.6, 0))
    assert_equal(
        _sweep_convex_triangle(low[0], low[1], low[2], down, strip).fraction,
        2,
    )
    # Its -y face on the far vertex at y = 10: touching from the other side.
    var high = _unit_cube(SIMD[DType.float64, 4](0, 10.5, 0.6, 0))
    assert_equal(
        _sweep_convex_triangle(high[0], high[1], high[2], down, strip).fraction,
        2,
    )
    # Overlapping the strip on y by 1 mm, the bottom face lands at a third.
    var over = _unit_cube(SIMD[DType.float64, 4](0, -0.499, 0.6, 0))
    var hit = _sweep_convex_triangle(over[0], over[1], over[2], down, strip)
    assert_almost_equal(hit.fraction, 1.0 / 3, atol=1e-12)
    assert_almost_equal(hit.normal[2], 1, atol=1e-12)


def test_box_and_hull_landing_energy_follows_the_impulse_law() raises:
    # A 1 kg shape lands at (5, 0, -30) m/s from 0.1 m. Contact comes at
    # 1/300 s of 0.01 s. The normal impulse is (1 + e) 30 N s, so the
    # rebound is 30 e m/s up and friction removes at most mu (1 + e) 30
    # m/s of slide. Both surfaces have the same material, so the mixed
    # values are mu and e. Tolerance: 1e-4 m/s and 1e-5 m from Float32.
    for kind in [_BOX, _HULL]:
        for bounce in [Float32(0), Float32(1)]:
            for friction in [Float32(0), Float32(0.05)]:
                var world = _world(False)
                _ = world.add_body(_mesh([_floor()], friction, bounce))
                var start = _start(kind)
                _ = world.add_body(
                    _shape(kind, start, Vector3(5, 0, -30), friction, bounce)
                )
                world.step(Duration(0.01))
                ref landed = world.bodies[1]
                var e = Float64(bounce)
                var slide = max(0.0, 5 - Float64(friction) * (1 + e) * 30)
                var v = landed.linear_velocity
                assert_almost_equal(Float64(v.x), slide, atol=1e-4)
                assert_almost_equal(Float64(v.z), 30 * e, atol=1e-4)
                assert_almost_equal(
                    Float64(landed.position.x - start.x),
                    5.0 / 300 + slide * 2 / 300,
                    atol=1e-5,
                )
                assert_almost_equal(
                    Float64(landed.position.z),
                    _rest(kind) + 30 * e * 2 / 300,
                    atol=1e-5,
                )
                # Twice the kinetic energy per kilogram, before and after.
                var after = Float64(v.dot(v))
                assert_almost_equal(
                    after, slide * slide + 900 * e * e, atol=0.01
                )
                assert_true(after <= 925 * (1 + 1e-6))
                assert_equal(world.contact_count, 1)


def _energy(body: RigidBody) -> Float64:
    # Twice the kinetic energy of the 1 kg rod, with the tensor at the
    # step's start pose, the tilt.
    var v = body.linear_velocity
    var local = _tilt().conjugate().rotate(body.angular_velocity)
    return (
        Float64(v.dot(v))
        + (Float64(local.x * local.x) + Float64(local.y * local.y)) / 15
        + Float64(local.z * local.z) / 200
    )


def test_turning_capsule_energy_with_restitution_and_friction() raises:
    # A rigid impulse at the contact point with e = 1 and no friction keeps
    # the energy. With e = 0 or friction, it loses energy. The tolerance
    # 1e-5 relative covers Float32 storage of the velocities.
    for bounce in [Float32(0), Float32(1)]:
        for friction in [Float32(0), Float32(0.5)]:
            var world = _world(False)
            _ = world.add_body(_mesh(_grid(), friction, bounce))
            var body = _shape(
                _TURNING_CAPSULE,
                Vector3(0, 0, 0.8),
                Vector3(0, 0, -30),
                friction,
                bounce,
            )
            body.angular_velocity = Vector3(4, 0, 0)
            _ = world.add_body(body^)
            var before = _energy(world.bodies[1])
            world.step(Duration(0.02))
            ref landed = world.bodies[1]
            assert_true(world.contact_count >= 1)
            assert_true(_lowest(landed) >= -0.1 / 1024 - 1e-5)
            var after = _energy(landed)
            assert_true(after <= before * (1 + 1e-5), String(after))
            if bounce == 1 and friction == 0:
                assert_almost_equal(after, before, atol=before * 1e-5)
            else:
                # A plastic or rough landing loses energy.
                assert_true(after < before * 0.9, String(after))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
