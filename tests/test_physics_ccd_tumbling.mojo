# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Continuous collision of boxes and hulls that turn: the separating
axis bound, the touching features, and whole steps against a mesh."""

from extensions.physics.body import DYNAMIC, RigidBody, STATIC
from extensions.physics.ccd import (
    SPHERE_MESH_CCD,
    _SolidContact,
    _clear_time,
    _solid_axis,
    _solid_contacts,
    _solid_step,
)
from extensions.physics.shape import PhysicsMaterial, Polyhedron, Shape
from extensions.physics.world import PhysicsWorld
from math.matrix3 import Matrix3
from math.quaternion import Quaternion
from math.triangle import Triangle
from math.vector3 import Vector3
from std.math import cos, sin, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Duration, Length, Mass, RADIAN, SECOND


def _v(x: Float64, y: Float64, z: Float64) -> SIMD[DType.float64, 4]:
    return SIMD[DType.float64, 4](x, y, z, 0)


@fieldwise_init
struct _Cube(Movable):
    # A cube of half size 0.5: corners, face normals, edge directions and
    # the corners of each edge.
    var corners: List[SIMD[DType.float64, 4]]
    var faces: List[SIMD[DType.float64, 4]]
    var edges: List[SIMD[DType.float64, 4]]
    var edge_a: List[Int]
    var edge_b: List[Int]


def _cube(center: SIMD[DType.float64, 4]) -> _Cube:
    var box = Polyhedron.box(Vector3(0.5, 0.5, 0.5))
    var corners = List[SIMD[DType.float64, 4]]()
    for corner in box.vertices:
        corners.append(
            _v(Float64(corner.x), Float64(corner.y), Float64(corner.z)) + center
        )
    var faces = List[SIMD[DType.float64, 4]]()
    for normal in box.normals:
        faces.append(
            _v(Float64(normal.x), Float64(normal.y), Float64(normal.z))
        )
    var edges = List[SIMD[DType.float64, 4]]()
    for k in range(len(box.edge_a)):
        edges.append(corners[box.edge_b[k]] - corners[box.edge_a[k]])
    return _Cube(corners^, faces^, edges^, box.edge_a.copy(), box.edge_b.copy())


def _flat() -> Triangle:
    # A wide floor on z = 0. Its front faces +z.
    return Triangle(
        Vector3(-10, -10, 0), Vector3(10, -10, 0), Vector3(0, 10, 0)
    )


def _touching(
    cube: _Cube, triangle: Triangle, depth: Float64 = 0
) -> List[_SolidContact]:
    var out = List[_SolidContact]()
    _solid_contacts(
        cube.corners,
        cube.faces,
        cube.edge_a,
        cube.edge_b,
        triangle,
        7,
        0.01,
        depth,
        out,
    )
    return out^


def test_the_time_a_bound_reaches_a_plane() raises:
    # A straight path closes 1 m at 2 m/s in half a second.
    assert_equal(_clear_time(1, -2, 0), 0.5)
    # A straight path that does not close has no limit.
    assert_equal(_clear_time(1, 0, 0), 1e300)
    assert_equal(_clear_time(1, 3, 0), 1e300)
    # With a bend of 2, the bound 1 + rate t - t^2 is zero at these times.
    assert_almost_equal(_clear_time(1, 0, 2), 1, atol=1e-15)
    assert_almost_equal(_clear_time(1, -1, 2), (sqrt(5.0) - 1) / 2, atol=1e-15)
    assert_almost_equal(_clear_time(1, 1, 2), (sqrt(5.0) + 1) / 2, atol=1e-15)


def test_the_axis_that_parts_a_cube_from_a_triangle() raises:
    # Over a floor, the floor's own normal parts them, by the clearance.
    var above = _cube(_v(0, 0, 1))
    var parted = _solid_axis(above.corners, above.faces, above.edges, _flat())
    assert_equal(parted[0], 0.5)
    assert_equal(parted[1][2], 1)
    assert_equal(parted[2], 0)
    # Sunk into the floor, the same axis gives the depth.
    var sunk = _cube(_v(0, 0, 0.4))
    parted = _solid_axis(sunk.corners, sunk.faces, sunk.edges, _flat())
    assert_almost_equal(parted[0], -0.1, atol=1e-15)
    assert_equal(parted[1][2], 1)
    # Wholly behind the floor, the mesh does not catch the cube.
    var under = _cube(_v(0, 0, -1))
    parted = _solid_axis(under.corners, under.faces, under.edges, _flat())
    assert_equal(parted[0], -1e300)
    # A triangle on z = 0 beside the cube: the cube spans its plane, and
    # one of the cube's own faces parts them. The axis points from the
    # triangle to the cube, and the offset is the triangle's extent.
    var middle = _cube(_v(0, 0, 0))
    var right = Triangle(Vector3(1, -1, 0), Vector3(3, -1, 0), Vector3(1, 1, 0))
    parted = _solid_axis(middle.corners, middle.faces, middle.edges, right)
    assert_equal(parted[0], 0.5)
    assert_equal(parted[1][0], -1)
    assert_equal(parted[2], -1)
    var left = Triangle(
        Vector3(-1, -1, 0), Vector3(-1, 1, 0), Vector3(-3, -1, 0)
    )
    parted = _solid_axis(middle.corners, middle.faces, middle.edges, left)
    assert_equal(parted[0], 0.5)
    assert_equal(parted[1][0], 1)
    assert_equal(parted[2], -1)
    # A triangle edge across the cube's upright edge at (0.5, 0.5): only
    # the cross product of the two edges parts them, along (1, 1, 0).
    var across = Triangle(
        Vector3(1.2, 0.2, 0), Vector3(0.2, 1.2, 0), Vector3(3, 3, 0)
    )
    parted = _solid_axis(middle.corners, middle.faces, middle.edges, across)
    var diagonal = 1 / sqrt(2.0)
    assert_almost_equal(parted[0], 0.4 * diagonal, atol=1e-7)
    assert_almost_equal(parted[1][0], -diagonal, atol=1e-12)
    assert_almost_equal(parted[1][1], -diagonal, atol=1e-12)
    assert_almost_equal(parted[2], -1.4 * diagonal, atol=1e-7)


def test_how_long_a_turning_cube_stays_clear() raises:
    var above = _cube(_v(0, 0, 1))
    var down = List[SIMD[DType.float64, 4]]()
    var up = List[SIMD[DType.float64, 4]]()
    for _ in range(8):
        down.append(_v(0, 0, -1))
        up.append(_v(0, 0, 1))
    var axis = _v(0, 0, 1)
    # Half a meter of clearance at 1 m/s: the cube is taken to the floor
    # and no farther.
    assert_equal(_solid_step(above.corners, down, 0.01, 0, 0.5, axis, 0), 0.5)
    # Moving away, there is no limit.
    assert_equal(_solid_step(above.corners, up, 0.01, 0, 0.5, axis, 0), 1e300)
    # A turn bends the path toward the plane sooner.
    var bent = _solid_step(above.corners, down, 0.01, 4, 0.5, axis, 0)
    assert_true(bent < 0.4)
    assert_true(bent > 0.3)
    # A cube within the tolerance of the floor touches. Its bound adds
    # the tolerance, so it never holds the step at zero.
    var near = _cube(_v(0, 0, 0.505))
    assert_almost_equal(
        _solid_step(near.corners, down, 0.01, 0, 0.005, axis, 0),
        0.015,
        atol=1e-15,
    )
    # A cube that overlaps by 0.1 m keeps that depth and adds the
    # tolerance only.
    var sunk = _cube(_v(0, 0, 0.4))
    assert_almost_equal(
        _solid_step(sunk.corners, down, 0.01, 0, -0.1, axis, 0),
        0.01,
        atol=1e-15,
    )


def test_cube_corners_on_a_triangle() raises:
    # A cube that rests on the floor touches at its four lower corners.
    var resting = _touching(_cube(_v(0, 0, 0.5)), _flat())
    assert_equal(len(resting), 4)
    for contact in resting:
        assert_equal(contact.point[2], 0)
        assert_equal(contact.normal[2], 1)
        assert_equal(contact.triangle, 7)
    # Within the tolerance above the floor, it still touches.
    assert_equal(len(_touching(_cube(_v(0, 0, 0.505)), _flat())), 4)
    assert_equal(len(_touching(_cube(_v(0, 0, 0.52)), _flat())), 0)
    # A corner sunk deeper than the cube's known overlap is not a contact.
    assert_equal(len(_touching(_cube(_v(0, 0, 0.3)), _flat())), 0)
    assert_equal(len(_touching(_cube(_v(0, 0, 0.3)), _flat(), depth=0.2)), 4)
    # A corner beside a small triangle, in front of it and within the
    # tolerance of its edge, touches along the line to that edge. The
    # triangle's corner at (0, 1, 0) is as near to the cube's lower edge,
    # and touches along the same line.
    var small = Triangle(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0))
    var beside = _touching(_cube(_v(-0.505, 0.8, 0.502)), small)
    assert_equal(len(beside), 2)
    assert_almost_equal(beside[0].point[0], -0.005, atol=1e-12)
    assert_almost_equal(beside[0].point[1], 0.3, atol=1e-12)
    assert_almost_equal(beside[0].point[2], 0.002, atol=1e-12)
    assert_equal(beside[1].point[1], 1)
    var away = sqrt(0.005 * 0.005 + 0.002 * 0.002)
    for contact in beside:
        assert_almost_equal(contact.normal[0], -0.005 / away, atol=1e-9)
        assert_almost_equal(contact.normal[1], 0, atol=1e-9)
        assert_almost_equal(contact.normal[2], 0.002 / away, atol=1e-9)
    # With the cube's corner just behind the triangle's plane, that
    # corner does not touch. The triangle's corner still touches the
    # cube's side face. The cube's upright edge now crosses the
    # triangle's edge. Both push the cube sideways.
    var behind = _touching(_cube(_v(-0.505, 0.8, 0.498)), small)
    assert_equal(len(behind), 2)
    assert_equal(behind[0].point[1], 1)
    assert_equal(behind[0].normal[0], -1)
    assert_almost_equal(behind[0].gap, 0.005, atol=1e-12)
    assert_almost_equal(behind[1].point[1], 0.3, atol=1e-12)
    assert_almost_equal(behind[1].point[2], 0, atol=1e-12)
    assert_equal(behind[1].normal[0], -1)
    assert_almost_equal(behind[1].gap, 0.005, atol=1e-12)
    # Farther than the tolerance from the edge, nothing touches.
    assert_equal(len(_touching(_cube(_v(-0.52, 0.8, 0.502)), small)), 0)


def test_a_triangle_corner_on_a_cube_face() raises:
    # A spike under the cube: one corner of the triangle touches the
    # middle of the lower face. The push on the cube is along +z.
    var cube = _cube(_v(0, 0, 0.5))
    var spike = Triangle(
        Vector3(0, 0, 0), Vector3(1, -1, -1), Vector3(1, 1, -1)
    )
    var found = _touching(cube, spike)
    assert_equal(len(found), 1)
    assert_equal(found[0].point[2], 0)
    assert_equal(found[0].normal[2], 1)
    # The same triangle seen from behind does not push.
    var turned = Triangle(
        Vector3(0, 0, 0), Vector3(1, 1, -1), Vector3(1, -1, -1)
    )
    assert_equal(len(_touching(cube, turned)), 0)
    # A corner deep inside the cube is not a contact, and with the known
    # overlap it is.
    var deep = Triangle(
        Vector3(0, 0, 0.3), Vector3(1, -1, -1), Vector3(1, 1, -1)
    )
    assert_equal(len(_touching(cube, deep)), 0)
    assert_equal(len(_touching(cube, deep, depth=0.3)), 1)
    # A corner far under the cube is not a contact.
    var low = Triangle(
        Vector3(0, 0, -0.2), Vector3(1, -1, -1), Vector3(1, 1, -1)
    )
    assert_equal(len(_touching(cube, low)), 0)


def _crossing(
    a: Vector3, b: Vector3, c: Vector3 = Vector3(3, 3, 0.2)
) -> List[_SolidContact]:
    # A cube at the origin and a triangle whose first edge passes its
    # upright edge at (0.5, 0.5).
    return _touching(_cube(_v(0, 0, 0)), Triangle(a, b, c))


def test_a_cube_edge_across_a_triangle_edge() raises:
    # The triangle's edge is the line x + y = 1.01 at z = 0.2. It passes
    # 0.00707 m from the cube's edge, inside both edges.
    var found = _crossing(
        Vector3(1.005, 0.005, 0.2), Vector3(0.005, 1.005, 0.2)
    )
    assert_equal(len(found), 1)
    assert_almost_equal(found[0].point[0], 0.5, atol=1e-12)
    assert_almost_equal(found[0].point[1], 0.5, atol=1e-12)
    assert_almost_equal(found[0].point[2], 0.2, atol=1e-7)
    var diagonal = 1 / sqrt(2.0)
    assert_almost_equal(found[0].normal[0], -diagonal, atol=1e-12)
    assert_almost_equal(found[0].normal[1], -diagonal, atol=1e-12)
    # Deeper than the known overlap, and farther than the tolerance.
    found = _crossing(Vector3(0.9, -0.1, 0.2), Vector3(-0.1, 0.9, 0.2))
    assert_equal(len(found), 0)
    found = _crossing(Vector3(1.1, 0, 0.2), Vector3(0, 1.1, 0.2))
    assert_equal(len(found), 0)
    # The nearest point is under the cube edge's start, and over its end.
    found = _crossing(
        Vector3(1.005, 0.005, -0.7),
        Vector3(0.005, 1.005, -0.7),
        Vector3(3, 3, -0.7),
    )
    assert_equal(len(found), 0)
    found = _crossing(
        Vector3(1.005, 0.005, 0.7),
        Vector3(0.005, 1.005, 0.7),
        Vector3(3, 3, 0.7),
    )
    assert_equal(len(found), 0)
    # The nearest point is before the triangle edge's start, and past its
    # end.
    found = _crossing(Vector3(0.405, 0.605, 0.2), Vector3(-0.595, 1.605, 0.2))
    assert_equal(len(found), 0)
    found = _crossing(Vector3(1.505, -0.495, 0.2), Vector3(0.605, 0.405, 0.2))
    assert_equal(len(found), 0)
    # A triangle that faces away from the cube does not push it back
    # across the edge. The cube's corner just behind that triangle still
    # counts as sunk into its face.
    found = _crossing(
        Vector3(1.005, 0.005, 0.2),
        Vector3(0.005, 1.005, 0.2),
        Vector3(0.505, 0.505, 1.2),
    )
    assert_equal(len(found), 1)
    assert_true(found[0].normal[0] > 0)
    assert_equal(found[0].point[2], 0.5)


def test_two_triangles_give_one_contact_at_a_shared_point() raises:
    # Two floor triangles share the edge y = 0.5. A cube with corners on
    # that edge touches each triangle there, with one normal.
    var cube = _cube(_v(0, 0, 0.5))
    var near = Triangle(
        Vector3(-5, -5, 0), Vector3(5, -5, 0), Vector3(5, 0.5, 0)
    )
    var far = Triangle(
        Vector3(5, 0.5, 0), Vector3(-5, 0.5, 0), Vector3(-5, -5, 0)
    )
    var beyond = Triangle(
        Vector3(-5, 0.5, 0), Vector3(5, 0.5, 0), Vector3(0, 5, 0)
    )
    var out = List[_SolidContact]()
    for item in [(near, 1), (far, 2), (beyond, 3)]:
        _solid_contacts(
            cube.corners,
            cube.faces,
            cube.edge_a,
            cube.edge_b,
            item[0],
            item[1],
            0.01,
            0,
            out,
        )
    assert_equal(len(out), 4)
    for contact in out:
        assert_true(contact.triangle < 3)
    # A ridge has two normals at one point. Both contacts stay.
    var ridge = List[_SolidContact]()
    var slope = Triangle(
        Vector3(0.5, -5, 0), Vector3(5, -5, -4.5), Vector3(0.5, 5, 0)
    )
    for item in [(_flat(), 1), (slope, 2)]:
        _solid_contacts(
            cube.corners,
            cube.faces,
            cube.edge_a,
            cube.edge_b,
            item[0],
            item[1],
            0.01,
            0,
            ridge,
        )
    assert_equal(len(ridge), 6)


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
    var triangles: List[Triangle], bounce: Float32 = 0
) raises -> RigidBody:
    var body = RigidBody(
        STATIC,
        Shape.mesh(triangles^),
        Mass(0),
        Vector3(0, 0, 0),
        Quaternion.identity(),
    )
    body.material = PhysicsMaterial(0, bounce)
    return body^


def _world(brute: Bool = False, bounce: Float32 = 0) raises -> PhysicsWorld:
    # A floor of 32 triangles on z = 0, and no gravity.
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    world.collision_detection = SPHERE_MESH_CCD
    world._ccd_brute_force = brute
    _ = world.add_body(_mesh(_grid(), bounce))
    return world^


def _box(
    position: Vector3,
    velocity: Vector3,
    rotation: Quaternion = Quaternion.identity(),
    spin: Vector3 = Vector3(0, 0, 0),
    bounce: Float32 = 0,
) raises -> RigidBody:
    # A 10 kg box of 1.0 by 0.6 by 0.4 m that can turn.
    var body = RigidBody(
        DYNAMIC,
        Shape.box(Length(0.5), Length(0.3), Length(0.2)),
        Mass(10),
        position,
        rotation,
    )
    body.linear_velocity = velocity
    body.angular_velocity = spin
    body.material = PhysicsMaterial(0, bounce)
    return body^


def _lowest(world: PhysicsWorld, i: Int) -> Float32:
    # The lowest corner of a box or hull.
    ref body = world.bodies[i]
    var low = Float32(1e9)
    for corner in body.shape.polyhedron.vertices:
        low = min(
            low,
            (
                body.shape_world_position()
                + body.shape_world_rotation().rotate(corner)
            ).z,
        )
    return low


def test_a_fast_flat_drop_stops_on_the_floor() raises:
    # At 60 m/s the box moves 0.6 m a step: more than its 0.4 m height.
    var world = _world()
    _ = world.add_body(_box(Vector3(0.3, 0.4, 2.1), Vector3(0, 0, -60)))
    var events = 0
    for _ in range(6):
        world.step(Duration(0.01, SECOND))
        events += len(world.events)
    ref box = world.bodies[1]
    # The box stops on the floor, not in it.
    assert_almost_equal(box.position.z, 0.2, atol=1e-6)
    assert_true(_lowest(world, 1) >= 0)
    assert_almost_equal(box.linear_velocity.length(), 0, atol=1e-6)
    assert_almost_equal(box.angular_velocity.length(), 0, atol=1e-6)
    assert_true(events >= 4)
    # The discrete mode lets the same box through.
    var discrete = PhysicsWorld()
    discrete.gravity = Vector3(0, 0, 0)
    _ = discrete.add_body(_mesh(_grid()))
    _ = discrete.add_body(_box(Vector3(0.3, 0.4, 2.1), Vector3(0, 0, -60)))
    for _ in range(6):
        discrete.step(Duration(0.01, SECOND))
    assert_true(discrete.bodies[1].position.z < 0)


def test_a_flat_drop_bounces_with_its_restitution() raises:
    var world = _world(bounce=1)
    _ = world.add_body(
        _box(Vector3(0.3, 0.4, 2.1), Vector3(0, 0, -60), bounce=1)
    )
    for _ in range(6):
        world.step(Duration(0.01, SECOND))
    ref box = world.bodies[1]
    # All four corners take their impulses together, scaled by 1 + e.
    assert_almost_equal(box.linear_velocity.z, 60, atol=1e-4)
    assert_almost_equal(box.angular_velocity.length(), 0, atol=1e-4)
    # 3.6 m of travel: 1.9 m down to the floor and 1.7 m back up.
    assert_almost_equal(box.position.z, 1.9, atol=1e-4)
    # A slow flat drop does not bounce: it is under the 1 m/s threshold.
    var slow = _world(bounce=1)
    _ = slow.add_body(
        _box(Vector3(0.3, 0.4, 0.23), Vector3(0, 0, -0.9), bounce=1)
    )
    slow.step(Duration(0.05, SECOND))
    assert_almost_equal(slow.bodies[1].position.z, 0.2, atol=1e-6)
    assert_almost_equal(slow.bodies[1].linear_velocity.z, 0, atol=1e-6)


def test_a_corner_drop_turns_the_box() raises:
    var world = _world(bounce=0.5)
    var tilt = Quaternion.from_axis_angle(
        Vector3(0.6, 0.8, 0), Angle(50, DEGREE)
    )
    _ = world.add_body(
        _box(
            Vector3(0.3, 0.4, 2), Vector3(0, 0, -60), rotation=tilt, bounce=0.5
        )
    )
    var before = world.bodies[1].kinetic_energy()
    var low = Float32(1e9)
    var struck = False
    for _ in range(12):
        world.step(Duration(0.01, SECOND))
        low = min(low, _lowest(world, 1))
        for event in world.events:
            if event.body.value == 1:
                struck = True
                # The floor pushes up.
                assert_true(event.normal_impulse.z > 0)
        # No impact adds energy.
        assert_true(world.bodies[1].kinetic_energy() <= before * 1.00001)
    assert_true(struck)
    # One corner struck, so the box now turns and rises.
    assert_true(world.bodies[1].angular_velocity.length() > 1)
    assert_true(world.bodies[1].linear_velocity.z > 0)
    # The box never went under the floor.
    assert_true(low >= 0)


def test_a_tumbling_box_comes_to_rest_on_the_floor() raises:
    var world = _world()
    world.gravity = Vector3(0, 0, -9.8)
    world.bodies[0].material = PhysicsMaterial(0.5, 0.3)
    var box = _box(
        Vector3(0.3, 0.4, 2), Vector3(1, 0, -40), spin=Vector3(4, 3, 1)
    )
    box.material = PhysicsMaterial(0.5, 0.3)
    _ = world.add_body(box^)
    var low = Float32(1e9)
    for _ in range(300):
        world.step(Duration(0.01, SECOND))
        low = min(low, _lowest(world, 1))
    # The sweep stops a point that would pass the floor by more than a
    # sixteenth of the tolerance: 0.616 m / 1024 / 16.
    assert_true(low > -0.00004)
    # The box lies on its largest face, on the floor and at rest. It did
    # not leave the 20 m floor.
    ref rested = world.bodies[1]
    assert_almost_equal(rested.position.z, 0.2, atol=1e-5)
    assert_true(rested.linear_velocity.length() < 1e-5)
    assert_true(rested.angular_velocity.length() < 1e-5)
    assert_true(abs(rested.position.x) < 9)
    assert_true(abs(rested.position.y) < 9)


def test_a_free_turn_is_the_exact_turn() raises:
    # Far from every triangle, a cube turns about its spin by |w| h and
    # moves in a straight line.
    var world = _world()
    var cube = RigidBody(
        DYNAMIC,
        Shape.box(Length(0.5), Length(0.5), Length(0.5)),
        Mass(6),
        Vector3(0, 0, 50),
        Quaternion.identity(),
    )
    cube.linear_velocity = Vector3(1, 2, 3)
    cube.angular_velocity = Vector3(0, 0, 2)
    _ = world.add_body(cube^)
    world.step(Duration(0.25, SECOND))
    ref moved = world.bodies[1]
    assert_almost_equal(moved.position.x, 0.25, atol=1e-6)
    assert_almost_equal(moved.position.y, 0.5, atol=1e-6)
    assert_almost_equal(moved.position.z, 50.75, atol=1e-5)
    assert_almost_equal(moved.rotation.z, Float32(sin(0.25)), atol=1e-6)
    assert_almost_equal(moved.rotation.w, Float32(cos(0.25)), atol=1e-6)
    assert_equal(moved.angular_velocity.z, 2)
    assert_equal(len(world.events), 0)


def test_the_index_and_the_full_scan_agree() raises:
    var results = List[Vector3]()
    var spins = List[Vector3]()
    for brute in [False, True]:
        var world = _world(brute, bounce=0.3)
        world.gravity = Vector3(0, 0, -9.8)
        _ = world.add_body(
            _box(
                Vector3(0.3, 0.4, 2),
                Vector3(3, 0, -40),
                spin=Vector3(8, 5, 2),
                bounce=0.3,
            )
        )
        for _ in range(40):
            world.step(Duration(0.01, SECOND))
        results.append(world.bodies[1].position)
        spins.append(world.bodies[1].angular_velocity)
    assert_true(results[0] == results[1])
    assert_true(spins[0] == spins[1])


def test_a_hull_lands_on_its_point() raises:
    # A tetrahedron with its point down, 0.5 m under its origin.
    var world = _world()
    var hull = RigidBody(
        DYNAMIC,
        Shape.convex(
            [
                Vector3(0, 0, -0.5),
                Vector3(0.5, 0, 0.5),
                Vector3(-0.5, 0.5, 0.5),
                Vector3(-0.5, -0.5, 0.5),
            ]
        ),
        Mass(1),
        Vector3(0.3, 0.4, 2),
        Quaternion.identity(),
    )
    hull.linear_velocity = Vector3(0, 0, -60)
    _ = world.add_body(hull^)
    var low = Float32(1e9)
    var struck = 0
    for _ in range(6):
        world.step(Duration(0.01, SECOND))
        low = min(low, _lowest(world, 1))
        struck += len(world.events)
    assert_true(struck >= 2)
    assert_true(low > -0.001)
    # The point is off the line through the mass center, so the impulse
    # turns the hull.
    assert_true(world.bodies[1].angular_velocity.length() > 0.1)


def test_one_sided_meshes_and_ghost_owners() raises:
    # A box that starts wholly behind the floor passes it.
    var world = _world()
    _ = world.add_body(_box(Vector3(0.3, 0.4, -1), Vector3(0, 0, 60)))
    for _ in range(5):
        world.step(Duration(0.01, SECOND))
    assert_almost_equal(world.bodies[1].position.z, 2, atol=1e-5)
    assert_equal(len(world.events), 0)
    # A floor that does not collide lets a box through from the front.
    var ghost = _world()
    ghost.bodies[0].collides = False
    _ = ghost.add_body(_box(Vector3(0.3, 0.4, 2), Vector3(0, 0, -60)))
    for _ in range(5):
        ghost.step(Duration(0.01, SECOND))
    assert_almost_equal(ghost.bodies[1].position.z, -1, atol=1e-5)
    # The full scan skips the ghost in the same way.
    var scanned = _world(brute=True)
    scanned.bodies[0].collides = False
    _ = scanned.add_body(_box(Vector3(0.3, 0.4, 2), Vector3(0, 0, -60)))
    for _ in range(5):
        scanned.step(Duration(0.01, SECOND))
    assert_almost_equal(scanned.bodies[1].position.z, -1, atol=1e-5)


def test_turning_boxes_fail_closed() raises:
    # Each refusal leaves the box where it was.
    var limited = _world()
    limited.ccd_max_impacts = 1
    _ = limited.add_body(_box(Vector3(0.3, 0.4, 0.5), Vector3(0, 0, -60)))
    # A flat landing needs more than one impulse.
    with assert_raises(contains="impact limit exhausted"):
        limited.step(Duration(0.01, SECOND))
    assert_equal(limited.bodies[1].position.z, 0.5)
    assert_equal(limited.bodies[1].linear_velocity.z, -60)
    # With the budget back, the same world steps.
    limited.ccd_max_impacts = 16
    limited.step(Duration(0.01, SECOND))
    assert_almost_equal(limited.bodies[1].position.z, 0.2, atol=1e-6)
    # A fast spin close to the floor needs more than one sub-step.
    var coarse = _world()
    coarse.ccd_max_substeps = 1
    _ = coarse.add_body(
        _box(Vector3(0.3, 0.4, 0.3), Vector3(0, 0, -5), spin=Vector3(20, 0, 0))
    )
    with assert_raises(contains="sub-step limit exhausted"):
        coarse.step(Duration(0.01, SECOND))
    assert_equal(coarse.bodies[1].position.z, 0.3)
    assert_equal(coarse.bodies[1].angular_velocity.x, 20)
    # With the default limit the same box lands on its edge.
    coarse.ccd_max_substeps = 256
    coarse.step(Duration(0.01, SECOND))
    assert_true(len(coarse.events) > 0)
    assert_true(_lowest(coarse, 1) > -0.00004)
    # A box that can turn needs a symmetric positive definite tensor.
    var wrong = _world()
    var custom = Matrix3()
    custom.elements[0] = -1
    var box = _box(Vector3(0.3, 0.4, 2), Vector3(0, 0, -1))
    box.set_inverse_inertia(custom)
    _ = wrong.add_body(box^)
    with assert_raises(contains="positive definite box and hull inertia"):
        wrong.step(Duration(0.01, SECOND))
    # A turning box must not reach another moving body.
    var pair = _world()
    _ = pair.add_body(_box(Vector3(0.3, 0.4, 2), Vector3(0, 0, -60)))
    _ = pair.add_body(_box(Vector3(0.3, 0.4, 3), Vector3(0, 0, 0)))
    with assert_raises(contains="must not reach another moving body"):
        pair.step(Duration(0.01, SECOND))
    assert_equal(pair.bodies[1].position.z, 2)


def _same(a: PhysicsWorld, b: PhysicsWorld, i: Int) -> Bool:
    # Whether body i has the same state in two worlds, bit for bit.
    ref x = a.bodies[i]
    ref y = b.bodies[i]
    return (
        x.position == y.position
        and x.rotation == y.rotation
        and x.linear_velocity == y.linear_velocity
        and x.angular_velocity == y.angular_velocity
        and x.force == y.force
        and x.torque == y.torque
        and x.push_velocity == y.push_velocity
        and x.push_angular == y.push_angular
    )


def test_a_failed_step_leaves_no_trace() raises:
    # Two equal worlds with a tilted box about to land. One of them fails
    # a step for lack of impacts, with a force, a torque and a split push
    # pending. Its retry then matches the world that never failed.
    var tilt = Quaternion.from_axis_angle(Vector3(1, 0, 0), Angle(20, DEGREE))
    var failed = _world()
    var twin = _world()
    _ = failed.add_body(
        _box(Vector3(0.3, 0.4, 0.6), Vector3(0, 0, -60), rotation=tilt)
    )
    _ = twin.add_body(
        _box(Vector3(0.3, 0.4, 0.6), Vector3(0, 0, -60), rotation=tilt)
    )
    failed.bodies[1].force = Vector3(1, -2, 3)
    failed.bodies[1].torque = Vector3(0.5, 0, -0.25)
    failed.bodies[1].push_velocity = Vector3(0.125, 0, -0.0625)
    twin.bodies[1].force = Vector3(1, -2, 3)
    twin.bodies[1].torque = Vector3(0.5, 0, -0.25)
    twin.bodies[1].push_velocity = Vector3(0.125, 0, -0.0625)
    assert_true(_same(failed, twin, 1))
    failed.ccd_max_impacts = 1
    failed.contact_count = 77
    with assert_raises(contains="impact limit exhausted"):
        failed.step(Duration(0.01, SECOND))
    # The force, the torque and the push are still pending.
    assert_true(_same(failed, twin, 1))
    assert_equal(failed.contact_count, 77)
    assert_equal(len(failed.events), 0)
    failed.ccd_max_impacts = 16
    failed.step(Duration(0.01, SECOND))
    twin.step(Duration(0.01, SECOND))
    assert_true(_same(failed, twin, 1))
    assert_equal(len(failed.events), len(twin.events))
    assert_true(len(failed.events) > 0)
    assert_true(failed.bodies[1].force == Vector3(0, 0, 0))


def test_a_second_single_impact_spends_the_budget() raises:
    # A corner strike is one impact. With a budget of one, a second
    # strike in the same step is refused.
    var tilt = Quaternion.from_axis_angle(
        Vector3(0.6, 0.8, 0), Angle(50, DEGREE)
    )
    var world = _world(bounce=1)
    world.ccd_max_impacts = 1
    world.bodies[0].material = PhysicsMaterial(0, 1)
    var ceiling = Triangle(
        Vector3(-10, -10, 1.3), Vector3(0, 10, 1.3), Vector3(10, -10, 1.3)
    )
    _ = world.add_body(_mesh([ceiling], bounce=1))
    _ = world.add_body(
        _box(
            Vector3(0.3, 0.4, 0.8), Vector3(0, 0, -60), rotation=tilt, bounce=1
        )
    )
    with assert_raises(contains="impact limit exhausted"):
        world.step(Duration(0.05, SECOND))
    assert_equal(world.bodies[2].position.z, 0.8)
    # With the budget back, the box strikes the floor and the ceiling.
    world.ccd_max_impacts = 16
    world.step(Duration(0.05, SECOND))
    var from_floor = 0
    var from_ceiling = 0
    for event in world.events:
        if event.body.value == 2 and event.other.value == 0:
            from_floor += 1
        if event.body.value == 2 and event.other.value == 1:
            from_ceiling += 1
    assert_true(from_floor >= 1)
    assert_true(from_ceiling >= 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
