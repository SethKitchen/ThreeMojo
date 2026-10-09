# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Rotation-locked capsule sweeps against static triangles (#635).

Each expected time and normal comes from the geometry by hand: a 3-4-5
tilt, a vertex under the middle of the axis, and so on.
"""

from extensions.physics.body import DYNAMIC, STATIC, RigidBody
from extensions.physics.ccd import SPHERE_MESH_CCD, _sweep_capsule_triangle
from extensions.physics.shape import Shape, PhysicsMaterial
from extensions.physics.world import PhysicsWorld
from math.matrix3 import Matrix3
from math.quaternion import Quaternion
from math.triangle import Triangle
from math.vector3 import Vector3
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Duration, Length, Mass


def _v(x: Float64, y: Float64, z: Float64) -> SIMD[DType.float64, 4]:
    return SIMD[DType.float64, 4](x, y, z, 0)


def _floor_triangle(size: Float32 = 100, z: Float32 = 0) -> Triangle:
    return Triangle(
        Vector3(-size, -size, z), Vector3(size, -size, z), Vector3(0, size, z)
    )


def _sweep(
    start: SIMD[DType.float64, 4],
    end: SIMD[DType.float64, 4],
    travel: SIMD[DType.float64, 4],
    radius: Float64,
    triangle: Triangle,
) raises -> Tuple[Float64, SIMD[DType.float64, 4]]:
    var hit = _sweep_capsule_triangle(start, end, travel, radius, triangle)
    return (hit.fraction, hit.normal)


def test_a_cap_reaches_the_floor_first_from_either_end() raises:
    # The lower cap's center starts 0.3 m up; it touches at 0.1 m after
    # 0.2 m of the 0.3 m travel.
    for flip in [False, True]:
        var low = _v(0, 0, 0.3)
        var high = _v(0, 0, 0.7)
        var hit = _sweep(
            high if flip else low,
            low if flip else high,
            _v(0, 0, -0.3),
            0.1,
            _floor_triangle(),
        )
        assert_almost_equal(hit[0], 2.0 / 3.0, atol=1e-12)
        assert_almost_equal(hit[1][2], 1.0, atol=1e-12)


def test_the_segment_reaches_an_edge() raises:
    # The axis has direction (0.8, 0, -0.6), center (0.5, 0, h) and radius
    # 0.4. Edge AB runs along y at the origin. Their distance in the xz
    # plane is 0.5 * 0.6 + h * 0.8, which is 0.4 at h = 0.125. From
    # h = 1.125 with a 2 m drop, that is half the travel. The nearest axis
    # point is then (0.24, 0, 0.32), so the normal is (0.6, 0, 0.8).
    var triangle = Triangle(
        Vector3(0, -1, 0), Vector3(0, 1, 0), Vector3(-2, 0, 0)
    )
    var half = _v(0.4, 0, -0.3)
    var center = _v(0.5, 0, 1.125)
    var hit = _sweep(center - half, center + half, _v(0, 0, -2), 0.4, triangle)
    assert_almost_equal(hit[0], 0.5, atol=1e-12)
    assert_almost_equal(hit[1][0], 0.6, atol=1e-12)
    assert_almost_equal(hit[1][2], 0.8, atol=1e-12)


def test_a_vertex_reaches_the_cylinder() raises:
    # The triangle's highest point is the vertex at the origin, under the
    # middle of a horizontal axis along y. The face slopes away, so the
    # vertex is the first contact: at height 0.1, after half the travel.
    var triangle = Triangle(
        Vector3(0, 0, 0), Vector3(1, -1, -1), Vector3(1, 1, -1)
    )
    var hit = _sweep(
        _v(0, -0.5, 0.5), _v(0, 0.5, 0.5), _v(0, 0, -0.8), 0.1, triangle
    )
    assert_almost_equal(hit[0], 0.5, atol=1e-12)
    assert_almost_equal(hit[1][2], 1.0, atol=1e-12)


def test_a_flat_capsule_over_a_small_triangle() raises:
    # Both caps lie outside the triangle. The axis crosses edges BC and CA
    # over the face, so an edge crossing reports the face contact.
    var triangle = Triangle(
        Vector3(-0.1, -0.1, 0), Vector3(0.1, -0.1, 0), Vector3(0, 0.1, 0)
    )
    var hit = _sweep(
        _v(-0.5, 0, 0.5), _v(0.5, 0, 0.5), _v(0, 0, -0.8), 0.1, triangle
    )
    assert_almost_equal(hit[0], 0.5, atol=1e-12)
    assert_almost_equal(hit[1][2], 1.0, atol=1e-12)


def test_misses_and_refusals() raises:
    var floor = _floor_triangle()
    # Moving away, a back face, and a triangle out of reach.
    assert_equal(
        _sweep(_v(0, 0, 1), _v(0, 0, 2), _v(0, 0, 1), 0.1, floor)[0], 2
    )
    var back = Triangle(
        Vector3(-100, -100, 0), Vector3(0, 100, 0), Vector3(100, -100, 0)
    )
    assert_equal(
        _sweep(_v(0, 0, 1), _v(0, 0, 2), _v(0, 0, -2), 0.1, back)[0], 2
    )
    var far = _floor_triangle(1, 50)
    assert_equal(
        _sweep(_v(0, 0, 1), _v(0, 0, 2), _v(0, 0, -0.1), 0.1, far)[0], 2
    )
    # A capsule of zero length is its sphere.
    var point = _sweep(_v(0, 0, 0.3), _v(0, 0, 0.3), _v(0, 0, -0.3), 0.1, floor)
    assert_almost_equal(point[0], 2.0 / 3.0, atol=1e-12)
    # A degenerate triangle near the axis gives no contact.
    var flat = Triangle(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0))
    assert_equal(
        _sweep(_v(-1, 0, 0.5), _v(1, 0, 0.5), _v(0, 0, -1), 0.1, flat)[0], 2
    )


def test_edge_feature_boundaries() raises:
    var triangle = Triangle(
        Vector3(0, -1, 0), Vector3(0, 1, 0), Vector3(-2, 0, 0)
    )
    var half = _v(0.4, 0, -0.3)
    # The axis line already lies within the radius of edge AB's line, but
    # the nearest points are past the edge's end, so only caps can touch.
    var beside = _v(0.5, 3, 0.2)
    assert_equal(
        _sweep(beside - half, beside + half, _v(0, 0, 0), 0.4, triangle)[0],
        2,
    )
    # Too slow to reach the edge in this step.
    var high = _v(0.5, 0, 1.125)
    assert_equal(
        _sweep(high - half, high + half, _v(0, 0, -0.5), 0.4, triangle)[0], 2
    )
    # The edge's nearest point is past the axis's start.
    var off = _v(3, 0, 1.125)
    assert_equal(
        _sweep(off - half, off + half, _v(0, 0, -2), 0.4, triangle)[0], 2
    )
    # A vertex beyond the axis's end, and one before its start.
    var tip = Triangle(Vector3(0, 0, 0), Vector3(1, -1, -1), Vector3(1, 1, -1))
    for y in [Float64(2), -2]:
        assert_equal(
            _sweep(
                _v(0, y - 0.5, 0.5),
                _v(0, y + 0.5, 0.5),
                _v(0, 0, -0.8),
                0.1,
                tip,
            )[0],
            2,
        )


def _capsule(
    position: Vector3,
    velocity: Vector3,
    rotation: Quaternion = Quaternion.identity(),
    radius: Float32 = 0.1,
    half_height: Float32 = 0.2,
) raises -> RigidBody:
    var body = RigidBody(
        DYNAMIC,
        Shape.capsule(Length(radius), Length(half_height)),
        Mass(1),
        position,
        rotation,
    )
    var locked = Matrix3()
    locked.elements[0] = 0
    locked.elements[4] = 0
    locked.elements[8] = 0
    body.set_inverse_inertia(locked)
    body.linear_velocity = velocity
    body.material = PhysicsMaterial(0, 0)
    return body^


def _world(var body: RigidBody, brute: Bool = False) raises -> PhysicsWorld:
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    world.collision_detection = SPHERE_MESH_CCD
    world._ccd_brute_force = brute
    _ = world.add_body(
        RigidBody(
            STATIC,
            Shape.mesh([_floor_triangle()]),
            Mass(0),
            Vector3(0, 0, 0),
            Quaternion.identity(),
        )
    )
    _ = world.add_body(body^)
    return world^


def test_a_fast_upright_capsule_lands_without_tunneling() raises:
    # The lower cap starts 0.3 m up and the step travels 0.3 m: it stops
    # when its center is 0.1 m up, the body center 0.3 m up.
    for brute in [False, True]:
        var world = _world(
            _capsule(Vector3(0, 0, 0.5), Vector3(0, 0, -30)), brute
        )
        world.step(Duration(0.01))
        assert_almost_equal(world.bodies[1].position.z, 0.3, atol=1e-6)
        assert_equal(world.bodies[1].linear_velocity.z, 0)
        assert_true(world.bodies[1].angular_velocity == Vector3(0, 0, 0))


def test_a_fast_lying_capsule_lands_on_its_side() raises:
    # Turned a quarter about y, the axis is horizontal and the body stops
    # with its center one radius above the floor.
    var turn = Quaternion.from_axis_angle(Vector3(0, 1, 0), Angle(90, DEGREE))
    var world = _world(_capsule(Vector3(0, 0, 0.4), Vector3(0, 0, -50), turn))
    world.step(Duration(0.01))
    assert_almost_equal(world.bodies[1].position.z, 0.1, atol=1e-6)
    assert_equal(world.bodies[1].linear_velocity.z, 0)


def test_unsupported_capsules_are_refused() raises:
    for choice in range(6):
        var body = _capsule(Vector3(0, 0, 0.5), Vector3(0, 0, -30))
        if choice == 0:
            body.set_inverse_inertia(Matrix3())
        elif choice == 1:
            body.angular_velocity = Vector3(0, 0, 1)
        elif choice == 2:
            body.push_angular = Vector3(1, 0, 0)
        elif choice == 3:
            body.shape.half_height = 20000
        elif choice == 4:
            body.shape.half_height = nan[DType.float32]()
        else:
            body.shape.half_height = -1
        var world = _world(body^)
        with assert_raises():
            world.step(Duration(0.01))
        # A refused step changes nothing.
        assert_almost_equal(world.bodies[1].position.z, 0.5, atol=1e-7)


def test_overlapping_reach_and_precision_are_refused() raises:
    # Two capsules whose reachable bounding spheres overlap.
    var world = _world(_capsule(Vector3(0, 0, 0.5), Vector3(0, 0, -30)))
    _ = world.add_body(_capsule(Vector3(0.3, 0, 0.5), Vector3(0, 0, -30)))
    with assert_raises():
        world.step(Duration(0.01))
    # Travel beyond 2^20 bounding radii in one step.
    var fast = _world(_capsule(Vector3(0, 0, 0.5), Vector3(0, 0, -1.0e6)))
    with assert_raises():
        fast.step(Duration(1))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
