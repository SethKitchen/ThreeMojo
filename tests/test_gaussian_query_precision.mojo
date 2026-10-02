# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Analytic ray and Gaussian queries across finite Float32 scales."""

from core.gaussian_splat_utils import create_gaussian_splat_geometry
from core.object3d import NodeId
from core.raycaster import Raycaster
from math.bounds import Box3, Sphere
from math.matrix4 import Matrix4, scaling
from math.ray import Ray
from math.vector3 import Vector3
from objects.gaussian_splat import GaussianSplat
from std.math import sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)
from units.si import Length, METER


def round_splat(variance: Float32) raises -> GaussianSplat:
    """Return one opaque round splat at the origin."""
    return GaussianSplat(
        create_gaussian_splat_geometry(
            [0, 0, 0],
            [variance, 0, 0, variance, 0, variance],
            [255, 255, 255, 255],
        ),
        NodeId(0),
    )


def test_sphere_misses_do_not_overflow_or_underflow() raises:
    for scale in [Float32(1e19), Float32(1e-30)]:
        var ray = Ray(Vector3(-5 * scale, 3 * scale, 0), Vector3(1, 0, 0))
        var sphere = Sphere(Vector3(0, 0, 0), 2 * scale)
        assert_false(ray.intersects_sphere(sphere))
        assert_false(Bool(ray.intersect_sphere(sphere)))


def test_sphere_hit_coordinates_remain_finite_at_both_scales() raises:
    for scale in [Float32(1e19), Float32(1e-30)]:
        var ray = Ray(Vector3(-5 * scale, scale, 0), Vector3(1, 0, 0))
        var sphere = Sphere(Vector3(0, 0, 0), 2 * scale)
        assert_true(ray.intersects_sphere(sphere))
        var hit = ray.intersect_sphere(sphere)
        assert_true(Bool(hit))
        # x^2 + y^2 = radius^2, with x < 0 at the entry.
        var expected = -sqrt(
            Float64(sphere.radius) ** 2 - Float64(ray.origin.y) ** 2
        )
        assert_almost_equal(
            Float64(hit.value().x) / Float64(scale),
            expected / Float64(scale),
            atol=1e-6,
        )


def test_stored_diagonal_direction_is_not_exactly_unit() raises:
    var ray = Ray(Vector3(0, 0, 0), Vector3(1, 1, 0))
    var sphere = Sphere(Vector3(1e19, 1e19, 0), 1e8)
    # The center is exactly on this line, regardless of the stored norm.
    assert_true(ray.intersects_sphere(sphere))
    assert_true(Bool(ray.intersect_sphere(sphere)))


def test_gaussian_large_and_small_hits_match_the_round_surface() raises:
    for variance in [Float32(1e38), Float32(1e-40)]:
        var shape = round_splat(variance)
        var scale = Float32(sqrt(Float64(variance)))
        var query = Raycaster(
            Vector3(-5 * scale, 1.9 * scale, 0), Vector3(1, 0, 0)
        )
        var hits = shape.raycast(Matrix4(), query)
        assert_equal(len(hits), 1)
        # Independent sphere equation includes the documented covariance floor.
        var radius_sq = 4 * Float64(variance) * 1.0001
        var y = Float64(query.ray.origin.y)
        var expected_x = -sqrt(radius_sq - y * y)
        assert_almost_equal(
            Float64(hits[0].point.x) / Float64(scale),
            expected_x / Float64(scale),
            atol=2e-6,
        )
        var distance = Float64(hits[0].distance.value)
        assert_almost_equal(
            distance / Float64(scale),
            (expected_x - Float64(query.ray.origin.x)) / Float64(scale),
            atol=2e-6,
        )
        query.near = Length(Float32(distance), METER)
        query.far = Length(Float32(distance), METER)
        assert_equal(len(shape.raycast(Matrix4(), query)), 1)
        query.near = Length(0, METER)
        query.far = Length(Float32(distance * 0.9), METER)
        assert_equal(len(shape.raycast(Matrix4(), query)), 0)
        query.far = Length(Float32(distance * 2), METER)
        query.near = Length(Float32(distance * 1.1), METER)
        assert_equal(len(shape.raycast(Matrix4(), query)), 0)


def test_slab_offsets_and_reciprocals_are_widened_before_arithmetic() raises:
    var across = Ray(Vector3(3e38, 0, 0), Vector3(-1, 0, 0))
    var distant = Box3(Vector3(-3e38, -1, -1), Vector3(-2e38, 1, 1))
    var hit = across.intersect_box(distant)
    assert_true(Bool(hit))
    assert_equal(hit.value().x, distant.max.x)
    var shallow = Ray(Vector3(0, 0, 0), Vector3(1, 1e-40, 0))
    var thin = Box3(Vector3(1, 1e-40, -1), Vector3(2, 2e-40, 1))
    hit = shallow.intersect_box(thin)
    assert_true(Bool(hit))
    assert_almost_equal(hit.value().x, 1, atol=1e-6)
    assert_equal(hit.value().y, thin.min.y)


def test_unsquared_point_distance_remains_representable() raises:
    for scale in [Float32(1e19), Float32(1e-30)]:
        var ray = Ray(Vector3(0, 0, 0), Vector3(1, 0, 0))
        assert_almost_equal(
            Float64(ray.distance_to_point(Vector3(scale, 3 * scale, 0)))
            / Float64(scale),
            3,
            atol=1e-6,
        )
        # A point behind the origin uses the endpoint, not the infinite line.
        assert_almost_equal(
            Float64(ray.distance_to_point(Vector3(-3 * scale, 4 * scale, 0)))
            / Float64(scale),
            5,
            atol=1e-6,
        )


def test_rotated_ellipsoids_keep_hits_and_reject_exact_misses_at_scale() raises:
    for variance in [Float32(1e38), Float32(1e-40)]:
        var scale = Float32(sqrt(Float64(variance)))
        var c = Float32(2.5) * variance
        var xy = Float32(1.5) * variance
        var shape = GaussianSplat(
            create_gaussian_splat_geometry(
                [0, 0, 0], [c, xy, 0, c, 0, variance], [255, 255, 255, 255]
            ),
            NodeId(0),
        )
        var along = Raycaster(
            Vector3(2.6 * scale, 2.6 * scale, 5 * scale), Vector3(0, 0, -1)
        )
        var hits = shape.raycast(Matrix4(), along)
        assert_equal(len(hits), 1)
        # Diagonalize analytically: the long variance is c+xy, z is independent.
        var floor_variance = Float64(c) * 1e-4
        var x = Float64(along.ray.origin.x)
        var expected_z = sqrt(
            (4 - 2 * x * x / (Float64(c) + Float64(xy) + floor_variance))
            * (Float64(variance) + floor_variance)
        )
        assert_almost_equal(
            Float64(hits[0].point.z) / Float64(scale),
            expected_z / Float64(scale),
            atol=2e-6,
        )
        var across = Raycaster(
            Vector3(2 * scale, -2 * scale, 5 * scale), Vector3(0, 0, -1)
        )
        assert_equal(len(shape.raycast(Matrix4(), across)), 0)


def test_world_scale_translation_and_shear_preserve_the_hit() raises:
    for scale in [Float32(1e19), Float32(1e-20)]:
        var shape = round_splat(1)
        var world = scaling(scale, scale, scale)
        world.elements[4] = scale
        world.elements[12] = 3 * scale
        # local (1.2,1.2,5) maps to (5.4,1.2,5)*scale.
        # The image's xy distance exceeds longest-column sphere scaling;
        # Matrix4.max_stretch already bounds this shear in the base revision.
        var query = Raycaster(
            Vector3(5.4 * scale, 1.2 * scale, 5 * scale), Vector3(0, 0, -1)
        )
        var hits = shape.raycast(world, query)
        assert_equal(len(hits), 1)
        var expected_z = sqrt(Float64(4.0004 - 2 * 1.2 * 1.2))
        assert_almost_equal(
            Float64(hits[0].point.z) / Float64(scale), expected_z, atol=2e-6
        )


def test_sphere_parameter_can_exceed_float32_without_losing_the_point() raises:
    var ray = Ray(Vector3(-3e38, 0, 0), Vector3(1, 0, 0))
    var sphere = Sphere(Vector3(3e38, 0, 0), 1e37)
    assert_true(ray.intersects_sphere(sphere))
    var hit = ray.intersect_sphere(sphere)
    assert_true(Bool(hit))
    var expected = Float32(Float64(sphere.center.x) - Float64(sphere.radius))
    assert_equal(hit.value().x, expected)
    assert_equal(ray.closest_point_to_point(sphere.center).x, sphere.center.x)


def test_sphere_tangency_and_behind_origin_at_both_scales() raises:
    for scale in [Float32(1e19), Float32(1e-30)]:
        var sphere = Sphere(Vector3(0, 0, 0), scale)
        var tangent = Ray(Vector3(-5 * scale, scale, 0), Vector3(1, 0, 0))
        assert_true(tangent.intersects_sphere(sphere))
        assert_equal(tangent.intersect_sphere(sphere).value().x, 0)
        var behind = Ray(Vector3(5 * scale, 0, 0), Vector3(1, 0, 0))
        assert_false(behind.intersects_sphere(sphere))
        assert_false(Bool(behind.intersect_sphere(sphere)))
        var inside = Ray(Vector3(0, 0, 0), Vector3(1, 0, 0))
        assert_equal(inside.intersect_sphere(sphere).value().x, scale)
        assert_false(inside.intersects_sphere(Sphere.empty()))
        assert_false(Bool(inside.intersect_box(Box3.empty())))


def test_distant_ellipsoid_rejection_is_not_lost_in_the_discriminant() raises:
    var shape = GaussianSplat(
        create_gaussian_splat_geometry(
            [0, 0, 0], [2.5, 1.5, 0, 2.5, 0, 1], [255, 255, 255, 255]
        ),
        NodeId(0),
    )
    var across = Raycaster(Vector3(2, -2, 1e19), Vector3(0, 0, -1))
    # In principal axes this is 8 / 1.00025 > cutoff^2 = 4.
    # Both broad bounds accept it, so the exact ellipsoid must reject it.
    assert_equal(len(shape.raycast(Matrix4(), across)), 0)
    var through = Raycaster(Vector3(0, 0, 1e19), Vector3(0, 0, -1))
    var hits = shape.raycast(Matrix4(), through)
    assert_equal(len(hits), 1)
    assert_almost_equal(Float64(hits[0].distance.value) / 1e19, 1, atol=1e-6)
    assert_almost_equal(hits[0].point.z, sqrt(Float32(4.001)), atol=1e-6)
    through.far = Length(9e18, METER)
    assert_equal(len(shape.raycast(Matrix4(), through)), 0)
    through.far = Length(2e19, METER)
    through.near = Length(1.1e19, METER)
    assert_equal(len(shape.raycast(Matrix4(), through)), 0)


def test_distant_sphere_retains_its_representable_surface_offset() raises:
    var sphere = Sphere(Vector3(0, 0, 0), 2)
    var ray = Ray(Vector3(0, 0, 1e19), Vector3(0, 0, -1))
    assert_equal(ray.intersect_sphere(sphere).value().z, 2)


def test_a_negative_third_pivot_rejects_the_covariance() raises:
    var shape = GaussianSplat(
        create_gaussian_splat_geometry(
            [0, 0, 0], [1, 0, 0, 1, 0, -1], [255, 255, 255, 255]
        ),
        NodeId(0),
    )
    var query = Raycaster(Vector3(0, 0, 5), Vector3(0, 0, -1))
    assert_equal(len(shape.raycast(Matrix4(), query)), 0)


def test_distant_diagonal_gaussian_keeps_the_surface_point() raises:
    var shape = round_splat(1)
    var query = Raycaster(Vector3(1e19, 1e19, 0), Vector3(-1, -1, 0))
    var hits = shape.raycast(Matrix4(), query)
    assert_equal(len(hits), 1)
    var expected = sqrt(Float32(4.0004 / 2))
    assert_almost_equal(hits[0].point.x, expected, atol=1e-6)
    assert_almost_equal(hits[0].point.y, expected, atol=1e-6)


def test_distant_diagonal_projection_keeps_small_point_offsets() raises:
    var ray = Ray(Vector3(1e19, 1e19, 0), Vector3(-1, -1, 0))
    var point = Vector3(2, 3, 0)
    var nearest = ray.closest_point_to_point(point)
    # The line is x=y; its nearest point is the arithmetic mean.
    assert_almost_equal(nearest.x, 2.5, atol=1e-6)
    assert_almost_equal(nearest.y, 2.5, atol=1e-6)
    assert_almost_equal(ray.distance_sq_to_point(point), 0.5, atol=1e-6)
    var sphere = Sphere(point, 0.5)
    assert_false(ray.intersects_sphere(sphere))
    assert_false(Bool(ray.intersect_sphere(sphere)))


def test_distant_box_intervals_keep_their_separation_and_surface() raises:
    var ray = Ray(Vector3(1e19, 1e19, 0), Vector3(-1, -1, 0))
    var missed = Box3(Vector3(0, 10, -1), Vector3(1, 11, 1))
    assert_false(ray.intersects_box(missed))
    var met = Box3(Vector3(0, 0, -1), Vector3(1, 1, 1))
    var hit = ray.intersect_box(met)
    assert_true(Bool(hit))
    assert_almost_equal(hit.value().x, 1, atol=1e-6)
    assert_almost_equal(hit.value().y, 1, atol=1e-6)
    assert_equal(hit.value().z, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
