# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Segment sweeps and closest points for moving capsule pairs.

Each case has a hand-computed time of impact and normal. A segment is a
start and an axis; an axis of zero is a sphere's center. The normal runs
from B toward A.
"""

from extensions.physics.body import DYNAMIC, STATIC, RigidBody
from extensions.physics.ccd import (
    SPHERE_MESH_CCD,
    _point_hit,
    _segment_gap,
    _sweep_segments,
    _SweepHit,
)
from extensions.physics.shape import Shape, PhysicsMaterial
from extensions.physics.world import PhysicsWorld
from math.matrix3 import Matrix3
from math.quaternion import Quaternion
from math.triangle import Triangle
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_true,
    assert_equal,
    assert_almost_equal,
)
from units.si import Length, Mass, Duration


def _v(x: Float64, y: Float64, z: Float64) -> SIMD[DType.float64, 4]:
    return SIMD[DType.float64, 4](x, y, z, 0)


def _near(
    hit: _SweepHit, fraction: Float64, normal: SIMD[DType.float64, 4]
) raises:
    assert_almost_equal(hit.fraction, fraction, atol=1e-12)
    for axis in range(3):
        assert_almost_equal(hit.normal[axis], normal[axis], atol=1e-12)


def test_points_and_segment_ends_and_sides() raises:
    var none = _v(0, 0, 0)
    # Two points: 0.3 of the way, closing 1 m on a 0.5 m gap at 0.2.
    _near(
        _sweep_segments(_v(0, 0, 0), none, _v(0.5, 0, 0), none, _v(1, 0, 0), 0.2),
        0.3,
        _v(-1, 0, 0),
    )
    # A point meets a segment's side.
    _near(
        _sweep_segments(
            _v(0, -1, 0), none, _v(-1, 0, 0), _v(2, 0, 0), _v(0, 1, 0), 0.25
        ),
        0.75,
        _v(0, -1, 0),
    )
    # A point meets a segment's far end cap.
    _near(
        _sweep_segments(
            _v(2, 0, 0), none, _v(-1, 0, 0), _v(2, 0, 0), _v(-1, 0, 0), 0.25
        ),
        0.75,
        _v(1, 0, 0),
    )
    # A segment's side meets a point: the point moves the other way, and
    # the normal is flipped to run from B toward A.
    _near(
        _sweep_segments(
            _v(-1, 0, 0), _v(2, 0, 0), _v(0.5, 1, 0), none, _v(0, 1, 0), 0.25
        ),
        0.75,
        _v(0, -1, 0),
    )


def test_interiors_parallel_and_misses() raises:
    var none = _v(0, 0, 0)
    # Crossed segments meet at their interiors.
    _near(
        _sweep_segments(
            _v(0, -1, 1), _v(0, 2, 0), _v(-1, 0, 0), _v(2, 0, 0), _v(0, 0, -1), 0.25
        ),
        0.75,
        _v(0, 0, 1),
    )
    # Parallel segments meet side to side, through an end.
    _near(
        _sweep_segments(
            _v(-1, 0, 1), _v(2, 0, 0), _v(-1, 0, 0), _v(2, 0, 0), _v(0, 0, -1), 0.25
        ),
        0.75,
        _v(0, 0, 1),
    )
    # Crossed segments that already overlap and close meet at once.
    _near(
        _sweep_segments(
            _v(0, -1, 0.1), _v(0, 2, 0), _v(-1, 0, 0), _v(2, 0, 0), _v(0, 0, -1), 0.25
        ),
        0,
        _v(0, 0, 1),
    )
    # Crossed segments that move apart, or that pass beside each other,
    # or that do not reach each other, do not meet.
    for travel in [_v(0, 0, 1), _v(0, 0, -0.5)]:
        assert_equal(
            _sweep_segments(
                _v(0, -1, 1), _v(0, 2, 0), _v(-1, 0, 0), _v(2, 0, 0), travel, 0.25
            ).fraction,
            2,
        )
    assert_equal(
        _sweep_segments(
            _v(5, -1, 1), _v(0, 2, 0), _v(-1, 0, 0), _v(2, 0, 0), _v(0, 0, -1), 0.25
        ).fraction,
        2,
    )
    # The interiors would meet, but A's closest point is past its end.
    assert_equal(
        _sweep_segments(
            _v(0, 1, 1), _v(0, 2, 0), _v(-1, 0, 0), _v(2, 0, 0), _v(0, 0, -1), 0.25
        ).fraction,
        2,
    )
    _ = none


def test_a_point_hit_keeps_only_earlier_approaches() raises:
    var miss = _SweepHit(2, _v(0, 0, 0))
    var earlier = _SweepHit(0.1, _v(1, 0, 0))
    var point = _v(0, 0, 0)
    var travel = _v(1, 0, 0)
    var other = _v(0.5, 0, 0)
    # Later than the step, later than a kept hit, or not closing.
    assert_equal(_point_hit(miss, point, travel, other, 1.5, False).fraction, 2)
    assert_equal(
        _point_hit(earlier, point, travel, other, 0.3, False).fraction, 0.1
    )
    assert_equal(
        _point_hit(miss, point, _v(0, 1, 0), _v(0, -0.5, 0), 0.3, False).fraction,
        2,
    )
    var hit = _point_hit(miss, point, travel, other, 0.3, True)
    assert_almost_equal(hit.normal[0], 1, atol=1e-12)


def test_closest_points_of_segments_and_points() raises:
    var none = _v(0, 0, 0)
    # Two points.
    var g = _segment_gap(_v(0, 0, 1), none, _v(0, 0, 0), none)
    assert_almost_equal(g[0], 1, atol=1e-12)
    assert_almost_equal(g[1][2], 1, atol=1e-12)
    # A point and a segment, both ways round.
    g = _segment_gap(_v(0.5, 2, 0), none, _v(0, 0, 0), _v(1, 0, 0))
    assert_almost_equal(g[0], 2, atol=1e-12)
    g = _segment_gap(_v(0, 0, 0), _v(1, 0, 0), _v(3, 0, 0), none)
    assert_almost_equal(g[0], 2, atol=1e-12)
    assert_almost_equal(g[1][0], -1, atol=1e-12)
    # Crossed segments 1 apart.
    g = _segment_gap(_v(0.5, -1, 1), _v(0, 2, 0), _v(0, 0, 0), _v(1, 0, 0))
    assert_almost_equal(g[0], 1, atol=1e-12)
    # B's closest point clamps to its start, then to its end.
    g = _segment_gap(_v(-2, 1, 0), _v(0, 1, 0), _v(0, 0, 0), _v(1, 0, 0))
    assert_almost_equal(g[0], 2.2360679774997896, atol=1e-12)
    g = _segment_gap(_v(3, 1, 0), _v(0, 1, 0), _v(0, 0, 0), _v(1, 0, 0))
    assert_almost_equal(g[0], 2.2360679774997896, atol=1e-12)
    # Parallel segments.
    g = _segment_gap(_v(0, 1, 0), _v(1, 0, 0), _v(0, 0, 0), _v(1, 0, 0))
    assert_almost_equal(g[0], 1, atol=1e-12)
    # Segments that cross have no normal.
    g = _segment_gap(_v(0.5, -1, 0), _v(0, 2, 0), _v(0, 0, 0), _v(1, 0, 0))
    assert_equal(g[0], 0)
    assert_equal(g[1][1], 0)


def _capsule(x: Float32, z: Float32, velocity: Vector3) raises -> RigidBody:
    var body = RigidBody(
        DYNAMIC,
        Shape.capsule(Length(0.1), Length(0.2)),
        Mass(1),
        Vector3(x, 0, z),
        Quaternion.identity(),
    )
    var locked = Matrix3()
    locked.elements[0] = 0
    locked.elements[4] = 0
    locked.elements[8] = 0
    body.set_inverse_inertia(locked)
    body.linear_velocity = velocity
    body.material = PhysicsMaterial(0, 1)
    return body^


def _sphere(x: Float32, z: Float32, velocity: Vector3) raises -> RigidBody:
    var body = RigidBody(
        DYNAMIC,
        Shape.sphere(Length(0.1)),
        Mass(1),
        Vector3(x, 0, z),
        Quaternion.identity(),
    )
    body.linear_velocity = velocity
    body.material = PhysicsMaterial(0, 1)
    return body^


def _world() -> PhysicsWorld:
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    world.collision_detection = SPHERE_MESH_CCD
    return world^


def test_upright_capsules_swap_velocities_side_on() raises:
    # Two upright capsules 0.5 m apart close side on at 30 m/s each:
    # contact at 5 ms, then an elastic swap.
    var world = _world()
    _ = world.add_body(_capsule(0, 0, Vector3(30, 0, 0)))
    _ = world.add_body(_capsule(0.5, 0, Vector3(-30, 0, 0)))
    world.step(Duration(0.02))
    assert_almost_equal(world.bodies[0].linear_velocity.x, -30, atol=1e-4)
    assert_almost_equal(world.bodies[1].linear_velocity.x, 30, atol=1e-4)
    assert_almost_equal(world.bodies[0].position.x, -0.3, atol=1e-5)
    assert_equal(world.contact_count, 1)


def test_a_sphere_strikes_a_capsule_end_on() raises:
    # A sphere falls onto an upright capsule's top cap. The cap's center
    # is at 0.2 m, so the sphere starts 0.1 m from contact and closes at
    # 20 m/s: contact at 5 ms, then an elastic swap.
    var world = _world()
    _ = world.add_body(_capsule(0, 0, Vector3(0, 0, 0)))
    _ = world.add_body(_sphere(0, 0.5, Vector3(0, 0, -20)))
    world.step(Duration(0.02))
    assert_almost_equal(world.bodies[0].linear_velocity.z, -20, atol=1e-4)
    assert_almost_equal(world.bodies[1].linear_velocity.z, 0, atol=1e-4)
    assert_almost_equal(world.bodies[1].position.z, 0.4, atol=1e-5)


def test_a_capsule_stack_settles_on_the_floor() raises:
    # A capsule rests on the floor; a sphere strikes it plastically. The
    # cascade settles the floor and the pair together.
    var world = _world()
    _ = world.add_body(
        RigidBody(
            STATIC,
            Shape.mesh(
                [
                    Triangle(
                        Vector3(-10, -10, 0),
                        Vector3(10, -10, 0),
                        Vector3(0, 10, 0),
                    )
                ]
            ),
            Mass(0),
            Vector3(0, 0, 0),
            Quaternion.identity(),
        )
    )
    var resting = _capsule(0, 0.3, Vector3(0, 0, 0))
    resting.material = PhysicsMaterial(0, 0)
    _ = world.add_body(resting^)
    var falling = _sphere(0, 0.8, Vector3(0, 0, -30))
    falling.material = PhysicsMaterial(0, 0)
    _ = world.add_body(falling^)
    world.step(Duration(0.02))
    assert_almost_equal(world.bodies[1].linear_velocity.z, 0, atol=1e-5)
    assert_almost_equal(world.bodies[2].linear_velocity.z, 0, atol=1e-5)
    assert_almost_equal(world.bodies[1].position.z, 0.3, atol=1e-5)
    # The sphere stops where it met the capsule's top cap.
    assert_almost_equal(world.bodies[2].position.z, 0.7, atol=1e-5)


def _tiled_floor() raises -> RigidBody:
    # 32 triangles, enough for a tree, in exact binary coordinates.
    var triangles = List[Triangle]()
    for row in range(4):
        for column in range(4):
            var x = Float32(column) * 4 - 8
            var y = Float32(row) * 4 - 8
            triangles.append(
                Triangle(
                    Vector3(x, y, 0), Vector3(x + 4, y, 0), Vector3(x, y + 4, 0)
                )
            )
            triangles.append(
                Triangle(
                    Vector3(x + 4, y, 0),
                    Vector3(x + 4, y + 4, 0),
                    Vector3(x, y + 4, 0),
                )
            )
    return RigidBody(
        STATIC,
        Shape.mesh(triangles^),
        Mass(0),
        Vector3(0, 0, 0),
        Quaternion.identity(),
    )


def test_a_tall_capsule_settles_on_an_indexed_floor() raises:
    # An upright capsule, radius 0.125 and half height 0.5, stands on the
    # floor; a sphere of radius 0.125 falls onto it at 1 m/s from 0.125 m
    # above its top cap. Plastic, frictionless and equal masses: at 0.125 s
    # both move at -0.5 m/s, and the floor contact then settles both at
    # once. The floor is beyond twice the capsule's radius from its center,
    # so settling must search the capsule's whole length. The tree and the
    # full scan agree, and the step ends.
    var results = List[Float32]()
    for brute in [False, True]:
        var world = _world()
        world._ccd_brute_force = brute
        _ = world.add_body(_tiled_floor())
        var capsule = RigidBody(
            DYNAMIC,
            Shape.capsule(Length(0.125), Length(0.5)),
            Mass(1),
            Vector3(0, 0, 0.625),
            Quaternion.identity(),
        )
        var locked = Matrix3()
        locked.elements[0] = 0
        locked.elements[4] = 0
        locked.elements[8] = 0
        capsule.set_inverse_inertia(locked)
        capsule.material = PhysicsMaterial(0, 0)
        _ = world.add_body(capsule^)
        var sphere = RigidBody(
            DYNAMIC,
            Shape.sphere(Length(0.125)),
            Mass(1),
            Vector3(0, 0, 1.5),
            Quaternion.identity(),
        )
        sphere.linear_velocity = Vector3(0, 0, -1)
        sphere.material = PhysicsMaterial(0, 0)
        _ = world.add_body(sphere^)
        world.step(Duration(0.5))
        assert_almost_equal(world.bodies[1].linear_velocity.z, 0, atol=1e-6)
        assert_almost_equal(world.bodies[2].linear_velocity.z, 0, atol=1e-6)
        assert_almost_equal(world.bodies[1].position.z, 0.625, atol=1e-6)
        assert_almost_equal(world.bodies[2].position.z, 1.375, atol=1e-6)
        results.append(world.bodies[1].position.z)
        results.append(world.bodies[2].position.z)
    assert_equal(results[0], results[2])
    assert_equal(results[1], results[3])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
