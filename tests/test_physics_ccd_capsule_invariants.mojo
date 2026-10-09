# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Capsule CCD bounds, endpoint symmetry and one-sided admission (#635)."""

from extensions.physics.body import DYNAMIC, STATIC, RigidBody
from extensions.physics.ccd import (
    SPHERE_MESH_CCD,
    _sweep_capsule_triangle,
    _sweep_triangle,
)
from extensions.physics.shape import PhysicsMaterial, Shape, _wide, _wide_dot
from extensions.physics.world import PhysicsWorld, _CCDImpact, _ccd_bound
from math.quaternion import Quaternion
from math.triangle import Triangle
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from tests.test_physics_ccd_capsule import _capsule, _floor_triangle, _v
from tests.test_physics_ccd_index import (
    _assert_world,
    _failure_pair,
    _step_pair,
)
from units.si import Angle, DEGREE, Duration, Length, Mass


def _world(
    var body: RigidBody, triangle: Triangle, brute: Bool = False
) raises -> PhysicsWorld:
    var triangles = List[Triangle]()
    triangles.append(triangle)
    # Nine dispersed triangles exercise an actual CCD tree, without the
    # separate Octree's coincident-triangle subdivision pathology.
    for k in range(8):
        var x = Float32(10 + 10 * k)
        triangles.append(
            Triangle(
                Vector3(x, 0, -50),
                Vector3(x + 1, 0, -50),
                Vector3(x, 1, -50),
            )
        )
    var world = PhysicsWorld()
    world.gravity = Vector3(0, 0, 0)
    world.margin = 0
    world.collision_detection = SPHERE_MESH_CCD
    world._ccd_brute_force = brute
    _ = world.add_body(
        RigidBody(
            STATIC,
            Shape.mesh(triangles^),
            Mass(0),
            Vector3(0, 0, 0),
            Quaternion.identity(),
        )
    )
    _ = world.add_body(body^)
    return world^


def _assert_tree(world: PhysicsWorld) raises:
    assert_equal(world._ccd_index.count, 9)
    assert_equal(len(world._ccd_index.nodes), 17)


def test_actual_half_axis_has_an_outward_bound() raises:
    for q in [
        Quaternion(1.000004, 0, 0, 0),
        Quaternion(0.600002, 0, 0, 0.800002),
        Quaternion.identity(),
    ]:
        var body = _capsule(
            Vector3(0, 0, 0), Vector3(0, 0, 0), radius=0.0001, half_height=100
        )
        body.rotation = q
        var half = _wide(
            body.shape_world_rotation().rotate(
                Vector3(0, 0, body.shape.half_height)
            )
        )
        var radius = Float64(body.shape.radius)
        var bound_axis = _ccd_bound(body) - radius
        assert_true(bound_axis * bound_axis >= _wide_dot(half, half))
        assert_true(_ccd_bound(body) < 100.01)
    var point = _capsule(Vector3(0, 0, 0), Vector3(0, 0, 0), half_height=0)
    assert_almost_equal(
        _ccd_bound(point), Float64(point.shape.radius), atol=1e-15
    )
    var sphere = RigidBody(
        DYNAMIC,
        Shape.sphere(Length(0.1)),
        Mass(1),
        Vector3(0, 0, 0),
        Quaternion.identity(),
    )
    assert_equal(_ccd_bound(sphere), Float64(sphere.shape.radius))


def _tip_world(brute: Bool, shape_rotation: Bool) raises -> PhysicsWorld:
    var body = _capsule(
        Vector3(0.001, 0, 0), Vector3(-1, 0, 0), radius=0.0001, half_height=100
    )
    # The accepted norm tolerance is unchanged. Either public rotation can
    # stretch the Float32 half axis beyond the nominal bounding sphere.
    if shape_rotation:
        body.shape_rotation = Quaternion(1.000004, 0, 0, 0)
    else:
        body.rotation = Quaternion(1.000004, 0, 0, 0)
    var tip = -body.shape_world_rotation().rotate(Vector3(0, 0, 100)).z
    assert_true(Float64(tip) > 100 + Float64(body.shape.radius))
    var triangle = Triangle(
        Vector3(0, -0.001, tip - 0.0002),
        Vector3(0, 0.001, tip - 0.0002),
        Vector3(0, 0, tip + 0.0002),
    )
    return _world(body^, triangle, brute)


def test_actual_tip_is_retained_by_the_tree() raises:
    for shape_rotation in [False, True]:
        var indexed = _tip_world(False, shape_rotation)
        var brute = _tip_world(True, shape_rotation)
        _step_pair(indexed, brute, 0.002)
        _assert_tree(indexed)
        assert_almost_equal(indexed.bodies[1].position.x, 0.0001, atol=1e-8)
        assert_equal(indexed.bodies[1].linear_velocity.x, 0)
        assert_equal(indexed.contact_count, 1)


def _overlapping_reach(brute: Bool) raises -> PhysicsWorld:
    # Nominal radii sum to 200.2 m. The accepted rotation stretches both
    # half axes, and their actual tips overlap at this 200.201 m spacing.
    var body = _capsule(
        Vector3(0, 0, -100.1005), Vector3(0, 0, 0), half_height=100
    )
    body.rotation = Quaternion(1.000004, 0, 0, 0)
    var world = _world(body^, _floor_triangle(1, -300), brute)
    var other = _capsule(
        Vector3(0, 0, 100.1005), Vector3(0, 0, 0), half_height=100
    )
    other.rotation = Quaternion(1.000004, 0, 0, 0)
    _ = world.add_body(other^)
    world.contact_count = 77
    world.bodies[1].force = Vector3(0.1, 0, 0)
    return world^


def test_actual_reachable_regions_must_be_disjoint() raises:
    var indexed = _overlapping_reach(False)
    var brute = _overlapping_reach(True)
    _failure_pair(indexed, brute, 0.001)
    _assert_tree(indexed)
    with assert_raises(contains="reachable regions must be disjoint"):
        indexed.step(Duration(0.001))
    with assert_raises(contains="reachable regions must be disjoint"):
        brute.step(Duration(0.001))


def _overlap_world(
    brute: Bool, flip: Bool, z: Float32 = 0
) raises -> PhysicsWorld:
    var body = _capsule(Vector3(0, 0, z), Vector3(0, 0, -1))
    if flip:
        body.rotation = Quaternion(1, 0, 0, 0)
    return _world(body^, _floor_triangle(1), brute)


def test_partial_front_overlap_is_endpoint_symmetric() raises:
    for z in [Float32(0), Float32(-0.2), Float32(0.2)]:
        var reference = _overlap_world(False, False, z)
        reference.step(Duration(0.3))
        _assert_tree(reference)
        for flip in [False, True]:
            var indexed = _overlap_world(False, flip, z)
            var brute = _overlap_world(True, flip, z)
            _step_pair(indexed, brute, 0.3)
            _assert_tree(indexed)
            assert_true(
                indexed.bodies[1].position == reference.bodies[1].position
            )
            assert_true(
                indexed.bodies[1].linear_velocity
                == reference.bodies[1].linear_velocity
            )
            assert_equal(indexed.contact_count, 1)
            assert_equal(len(indexed.events), 2)
            assert_true(
                indexed.events[0].normal_impulse
                == reference.events[0].normal_impulse
            )
        if z == 0:
            # One split correction: (radius + half height - slop) * 0.2.
            assert_almost_equal(
                reference.bodies[1].position.z, 0.059, atol=1e-7
            )


def test_cap_and_interior_features_keep_initial_backside_exclusion() raises:
    var triangle = Triangle(
        Vector3(0, 0, 0), Vector3(-1, 0, 0), Vector3(0, -1, 0)
    )
    var travel = _v(-1, 0, 0.25)
    for flip in [False, True]:
        var a = _v(1, -0.5, -0.2)
        var b = _v(1, 0.5, -0.2)
        var start = b if flip else a
        var end = a if flip else b
        assert_equal(_sweep_triangle(start, travel, 0.1, triangle).fraction, 2)
        assert_equal(_sweep_triangle(end, travel, 0.1, triangle).fraction, 2)
        assert_equal(
            _sweep_capsule_triangle(start, end, travel, 0.1, triangle).fraction,
            2,
        )
    # A sphere-size overlap does not turn a wholly back-side segment into
    # a front-side one. Both caps and the cylinder remain one-sided.
    for z in [Float64(-0.05), Float64(-0.2)]:
        assert_equal(
            _sweep_capsule_triangle(
                _v(-0.5, 0, z),
                _v(0.5, 0, z),
                _v(0, 0, 0.4),
                0.1,
                _floor_triangle(1),
            ).fraction,
            2,
        )


def test_partially_front_side_interior_overlap_remains_admitted() raises:
    var triangle = Triangle(
        Vector3(0, -1, 0), Vector3(0, 1, 0), Vector3(-2, 0, 0)
    )
    # The infinite lines are 0.46 m apart, inside radius 0.5. Their
    # closest points lie on both segments. One cap starts behind the face;
    # neither cap overlaps the triangle. The interior must report t = 0.
    var a = _v(0.1, 0, 0.5)
    var b = _v(0.9, 0, -0.1)
    var travel = _v(0, 0, -1)
    for flip in [False, True]:
        var start = b if flip else a
        var end = a if flip else b
        var hit = _sweep_capsule_triangle(start, end, travel, 0.5, triangle)
        assert_equal(hit.fraction, 0)
        assert_almost_equal(hit.normal[0], 0.6, atol=1e-12)
        assert_almost_equal(hit.normal[2], 0.8, atol=1e-12)


def test_wholly_backside_worlds_pass_through() raises:
    var triangle = Triangle(
        Vector3(0, 0, 0), Vector3(-1, 0, 0), Vector3(0, -1, 0)
    )
    var turn = Quaternion.from_axis_angle(Vector3(1, 0, 0), Angle(90, DEGREE))
    for flip in [False, True]:
        var body = _capsule(
            Vector3(1, 0, -0.2), Vector3(-1, 0, 0.25), turn, half_height=0.5
        )
        if flip:
            body.rotation = Quaternion.from_axis_angle(
                Vector3(1, 0, 0), Angle(-90, DEGREE)
            )
        var indexed = _world(body.copy(), triangle)
        var brute = _world(body^, triangle, True)
        _step_pair(indexed, brute, 1)
        _assert_tree(indexed)
        assert_almost_equal(indexed.bodies[1].position.x, 0, atol=1e-7)
        assert_almost_equal(indexed.bodies[1].position.z, 0.05, atol=1e-7)
        assert_true(indexed.bodies[1].linear_velocity == Vector3(-1, 0, 0.25))
        assert_equal(indexed.contact_count, 0)


def test_front_caps_and_interior_features_match_tree_and_full_scan() raises:
    for feature in range(3):
        var body = _capsule(Vector3(0, 0, 0.5), Vector3(0, 0, -30))
        var triangle = _floor_triangle(1)
        var expected = Vector3(0, 0, 0.3)
        if feature == 1:
            # A horizontal segment above a single highest vertex.
            body = _capsule(
                Vector3(0, 0, 0.5),
                Vector3(0, 0, -80),
                Quaternion.from_axis_angle(Vector3(1, 0, 0), Angle(90, DEGREE)),
                half_height=0.5,
            )
            triangle = Triangle(
                Vector3(0, 0, 0), Vector3(1, -1, -1), Vector3(1, 1, -1)
            )
            expected = Vector3(0, 0, 0.1)
        elif feature == 2:
            # The 3-4-5 tilted segment meets an edge at t = 0.005 s.
            # Its plastic projection is (96, 0, -72) m/s for 0.005 s.
            body = _capsule(
                Vector3(0.5, 0, 1.125),
                Vector3(0, 0, -200),
                Quaternion.from_axis_angle(
                    Vector3(0, 1, 0), Angle(126.86989764584402, DEGREE)
                ),
                radius=0.4,
                half_height=0.5,
            )
            triangle = Triangle(
                Vector3(0, -1, 0), Vector3(0, 1, 0), Vector3(-2, 0, 0)
            )
            expected = Vector3(0.98, 0, -0.235)
        # With zero force, damping and split correction, the private sweep
        # has the same initial state as step. Retain its impact times to
        # distinguish a later cap handoff from duplicate zero-time hits.
        var traced = _world(body.copy(), triangle)
        traced._validate_ccd()
        var impacts = List[_CCDImpact]()
        var traced_pose = traced._ccd_sphere(1, 0.01, impacts)
        var indexed = _world(body.copy(), triangle)
        var brute = _world(body^, triangle, True)
        _step_pair(indexed, brute, 0.01)
        _assert_tree(indexed)
        assert_almost_equal(indexed.bodies[1].position.x, expected.x, atol=2e-6)
        assert_almost_equal(indexed.bodies[1].position.z, expected.z, atol=2e-6)
        assert_true(traced_pose[0] == indexed.bodies[1].position)
        assert_true(
            traced.bodies[1].linear_velocity
            == indexed.bodies[1].linear_velocity
        )
        assert_equal(len(impacts), indexed.contact_count)
        if feature != 2:
            assert_equal(indexed.contact_count, 1)
        else:
            # The ideal 3-4-5 motion slides tangentially from the segment
            # onto its trailing cap. In Float64, the rounded post-impact
            # line can enter that cap's edge cylinder by about 1e-16 m^2.
            # Contraction can then change one impact into two. The extra
            # hit must advance time; the original response bounds remain.
            assert_true(
                indexed.contact_count == 1 or indexed.contact_count == 2
            )
            if len(impacts) == 2:
                assert_true(impacts[1].time > impacts[0].time)
                assert_true(impacts[1].time < Float64(Float32(0.01)))
                assert_equal(impacts[1].triangle, impacts[0].triangle)


def _rebound_world(brute: Bool) raises -> PhysicsWorld:
    var body = _capsule(Vector3(0, 0, 0.5), Vector3(0, 0, -300))
    body.material = PhysicsMaterial(0, 1)
    var world = _world(body^, _floor_triangle(1), brute)
    var ceiling = _floor_triangle(1, 1)
    _ = world.add_body(
        RigidBody(
            STATIC,
            Shape.mesh([Triangle(ceiling.a, ceiling.c, ceiling.b)]),
            Mass(0),
            Vector3(0, 0, 0),
            Quaternion.identity(),
        )
    )
    return world^


def test_capsule_late_failure_preserves_full_step_state() raises:
    var indexed = _rebound_world(False)
    var brute = _rebound_world(True)
    _step_pair(indexed, brute, 0.001)
    assert_equal(indexed.contact_count, 1)
    # Preserve a previous report, a pending force, a nondefault count and
    # index lifecycle after an actual second-impact limit failure.
    indexed.bodies[1].force = Vector3(1, 2, 3)
    brute.bodies[1].force = Vector3(1, 2, 3)
    indexed.ccd_max_impacts = 1
    brute.ccd_max_impacts = 1
    _failure_pair(indexed, brute, 0.01)
    with assert_raises(contains="impact limit exhausted"):
        indexed.step(Duration(0.01))
    with assert_raises(contains="impact limit exhausted"):
        brute.step(Duration(0.01))
    _assert_world(indexed, brute)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
