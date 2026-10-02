# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Analytic regularized Gaussian bounds, including directed storage rounding."""

from core.gaussian_splat_utils import create_gaussian_splat_geometry
from core.object3d import NodeId
from core.raycaster import Raycaster
from math.bounds import Box3
from math.matrix4 import Matrix4, scaling
from math.vector3 import Vector3
from objects.gaussian_splat import (
    GaussianSplat,
    _bound_coordinate,
    _round_bound,
)
from std.math import inf, isfinite, sqrt
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
)
from units.si import Length, METER


def make_shape(
    covariance: List[Float32], center: Vector3 = Vector3(0, 0, 0)
) raises -> GaussianSplat:
    """Return one opaque splat for an independent analytic control."""
    return GaussianSplat(
        create_gaussian_splat_geometry(
            [center.x, center.y, center.z],
            covariance.copy(),
            [255, 255, 255, 255],
        ),
        NodeId(0),
    )


def test_unit_public_hit_is_inside_every_bound() raises:
    var shape = make_shape([1, 0, 0, 1, 0, 1])
    for x in [Float32(0), Float32(2.00005)]:
        var query = Raycaster(Vector3(x, 0, 5), Vector3(0, 0, -1))
        var hits = shape.raycast(Matrix4(), query)
        assert_equal(len(hits), 1)
        var expected = sqrt(Float64(4.0004) - Float64(x) * Float64(x))
        assert_almost_equal(
            Float64(hits[0].point.z), expected, atol=1e-6, rtol=0
        )
        assert_true(shape.bounding_box.value().contains_point(hits[0].point))
        assert_true(shape.bounding_sphere.value().contains_point(hits[0].point))
    assert_true(
        Float64(shape.bounding_sphere.value().radius)
        >= 2 * sqrt(Float64(1.0001))
    )
    assert_true(
        Float64(shape.bounding_box.value().max.x) >= 2 * sqrt(Float64(1.0001))
    )


def test_regularized_grazing_hits_at_large_and_small_scale() raises:
    for variance in [Float32(1e-40), Float32(1), Float32(1e38)]:
        var scale = sqrt(Float64(variance))
        var shape = make_shape([variance, 0, 0, variance, 0, variance])
        var x = Float32(2.00005 * scale)
        var query = Raycaster(
            Vector3(x, 0, Float32(5 * scale)), Vector3(0, 0, -1)
        )
        var hits = shape.raycast(Matrix4(), query)
        assert_equal(len(hits), 1)
        var expected = sqrt(
            4 * Float64(variance) * 1.0001 - Float64(x) * Float64(x)
        )
        assert_almost_equal(
            Float64(hits[0].point.z) / scale,
            expected / scale,
            atol=2e-6,
            rtol=0,
        )
        assert_true(shape.bounding_box.value().contains_point(hits[0].point))
        # Compare in Float64: Sphere.contains_point has a Float32 squared API.
        var p = hits[0].point
        var r = Float64(shape.bounding_sphere.value().radius)
        assert_true(Float64(p.x) ** 2 + Float64(p.z) ** 2 <= r * r)
        var distance = hits[0].distance
        query.near = distance
        query.far = distance
        assert_equal(len(shape.raycast(Matrix4(), query)), 1)
        query.near = Length(0, METER)
        query.far = Length(distance.value * 0.99, METER)
        assert_equal(len(shape.raycast(Matrix4(), query)), 0)
        query.near = Length(distance.value * 1.01, METER)
        query.far = Length(distance.value * 2, METER)
        assert_equal(len(shape.raycast(Matrix4(), query)), 0)


def test_rotated_and_flat_regularized_shells_survive_prefilters() raises:
    for sign in [Float32(-1), Float32(1)]:
        var shape = make_shape([2.5, 1.5 * sign, 0, 2.5, 0, 1])
        var x = Float32(2.82847)
        var hits = shape.raycast(
            Matrix4(), Raycaster(Vector3(x, sign * x, 5), Vector3(0, 0, -1))
        )
        assert_equal(len(hits), 1)
        var expected = sqrt((4 - 2 * Float64(x) ** 2 / 4.00025) * 1.00025)
        assert_almost_equal(
            Float64(hits[0].point.z), expected, atol=2e-6, rtol=0
        )
        assert_true(shape.bounding_sphere.value().contains_point(hits[0].point))
        assert_true(shape.bounding_box.value().contains_point(hits[0].point))
    var flat = make_shape([1, 0, 0, 0, 0, 0])
    var hits = flat.raycast(
        Matrix4(), Raycaster(Vector3(0, 0.019, 5), Vector3(0, 0, -1))
    )
    assert_equal(len(hits), 1)
    assert_almost_equal(
        Float64(hits[0].point.z),
        sqrt(0.0004 - Float64(Float32(0.019)) ** 2),
        atol=1e-7,
        rtol=0,
    )
    assert_true(flat.bounding_box.value().contains_point(hits[0].point))
    assert_true(flat.bounding_sphere.value().contains_point(hits[0].point))


def test_transformed_grazing_hit_keeps_the_same_local_shape() raises:
    var shape = make_shape([1, 0, 0, 1, 0, 1])
    var world = scaling(2, 3, 4)
    world.elements[12] = 7
    world.elements[13] = -9
    world.elements[14] = 11
    var local = Vector3(2.00005, 0, 5)
    var hits = shape.raycast(
        world, Raycaster(world.transform_point(local), Vector3(0, 0, -1))
    )
    assert_equal(len(hits), 1)
    var actual_x = (Float64(world.transform_point(local).x) - 7) / 2
    var expected_z = 11 + 4 * sqrt(4.0004 - actual_x * actual_x)
    assert_almost_equal(Float64(hits[0].point.z), expected_z, atol=2e-5, rtol=0)


def test_tiny_extents_at_extreme_centers_are_outward_and_finite() raises:
    var largest = bitcast[DType.float32](UInt32(0x7F7FFFFF))
    for axis in range(3):
        for sign in [Float32(-1), Float32(1)]:
            var center = Vector3(0, 0, 0)
            if axis == 0:
                center.x = sign * largest
            elif axis == 1:
                center.y = sign * largest
            else:
                center.z = sign * largest
            var shape = make_shape([1, 0, 0, 1, 0, 1], center)
            shape.compute_bounding_sphere()
            assert_true(shape.bounding_sphere.value().center == center)
            assert_true(isfinite(shape.bounding_sphere.value().radius))
            assert_true(shape.bounding_box.value().contains_point(center))
            assert_true(
                Float64(shape.bounding_sphere.value().radius)
                >= 2 * sqrt(Float64(1.0001))
            )
    for center in [Float32(-3e38), Float32(3e38)]:
        assert_true(_bound_coordinate[False](center, 2) < center)
        assert_true(_bound_coordinate[True](center, 2) > center)


def test_multiple_splats_and_replaced_empty_metadata_keep_finite_centers() raises:
    var largest = bitcast[DType.float32](UInt32(0x7F7FFFFF))
    var shape = GaussianSplat(
        create_gaussian_splat_geometry(
            [largest, 0, 0, largest, 4, 0],
            [1, 0, 0, 1, 0, 1, 1, 0, 0, 1, 0, 1],
            [255, 255, 255, 255, 255, 255, 255, 255],
        ),
        NodeId(0),
    )
    shape.compute_bounding_sphere()
    assert_true(shape.bounding_sphere.value().center == Vector3(largest, 2, 0))
    assert_true(
        Float64(shape.bounding_sphere.value().radius)
        >= 2 + 2 * sqrt(Float64(1.0001))
    )
    assert_true(isfinite(shape.bounding_sphere.value().radius))
    # Both fields are public. Recomputing must ignore a stale arbitrary box,
    # even when the centers have since been cleared independently.
    shape.splat_geometry.centers = List[Float32]()
    shape.bounding_box = Box3(
        Vector3(largest, 0, 0), Vector3(inf[DType.float32](), 0, 0)
    )
    shape.compute_bounding_sphere()
    assert_true(shape.bounding_box.value().is_empty())
    assert_true(shape.bounding_sphere.value().center == Vector3(0, 0, 0))
    assert_equal(shape.bounding_sphere.value().radius, 0)


def test_global_radius_widens_center_distances_before_accumulation() raises:
    var shape = GaussianSplat(
        create_gaussian_splat_geometry(
            [-2e38, -2e38, 0, 2e38, 2e38, 0],
            [1, 0, 0, 1, 0, 1, 1, 0, 0, 1, 0, 1],
            [255, 255, 255, 255, 255, 255, 255, 255],
        ),
        NodeId(0),
    )
    shape.compute_bounding_sphere()
    assert_true(shape.bounding_sphere.value().center == Vector3(0, 0, 0))
    var coordinate = Float64(Float32(2e38))
    var required = sqrt(2 * coordinate * coordinate) + 2 * sqrt(Float64(1.0001))
    assert_true(Float64(shape.bounding_sphere.value().radius) >= required)
    assert_true(isfinite(shape.bounding_sphere.value().radius))


def test_zero_covariance_finite_limit_is_proved_without_clamping() raises:
    var limit = bitcast[DType.float32](UInt32(0x7F7FFFFF))
    var shape = GaussianSplat(
        create_gaussian_splat_geometry(
            [-limit, 0, 0, limit, 0, 0],
            List[Float32](length=12, fill=0),
            List[UInt8](length=8, fill=255),
        ),
        NodeId(0),
    )
    shape.compute_bounding_sphere()
    assert_true(shape.bounding_sphere.value().center == Vector3(0, 0, 0))
    assert_equal(
        bitcast[DType.uint32](shape.bounding_sphere.value().radius),
        UInt32(0x7F7FFFFF),
    )
    # A second nonzero axis makes the exact radius larger than the limit.
    shape.splat_geometry.centers[1] = -limit
    shape.splat_geometry.centers[4] = limit
    shape.compute_bounding_sphere()
    assert_equal(shape.bounding_sphere.value().radius, inf[DType.float32]())
    # Positive covariance extends beyond the exact limit, even when its
    # tiny extent disappears from a rounded Float64 center-distance sum.
    shape.splat_geometry.centers[1] = 0
    shape.splat_geometry.centers[4] = 0
    shape.splat_geometry.covariances[0] = 1
    shape.compute_bounding_sphere()
    assert_equal(shape.bounding_sphere.value().radius, inf[DType.float32]())
    for axis in range(3):
        var nonfinite = Vector3(0, 0, 0)
        nonfinite.set_component(axis, inf[DType.float32]())
        assert_true(not shape._zero_reach_fits_limit(nonfinite))
        var point = make_shape([0, 0, 0, 0, 0, 0], nonfinite)
        assert_true(not point._zero_reach_fits_limit(Vector3(0, 0, 0)))
    # The exact point-set predicate also obeys the empty-set identity.
    shape.splat_geometry.centers = List[Float32]()
    assert_true(shape._zero_reach_fits_limit(Vector3(0, 0, 0)))


def test_directed_rounding_handles_zero_ties_and_signs() raises:
    var tiny = Float64(bitcast[DType.float32](UInt32(1)))
    assert_equal(
        bitcast[DType.uint32](_round_bound[True](tiny * 0.25, 0)), UInt32(1)
    )
    assert_equal(
        bitcast[DType.uint32](_round_bound[False](-tiny * 0.25, 0)),
        UInt32(0x80000001),
    )
    assert_equal(
        _round_bound[True](1, tiny), bitcast[DType.float32](UInt32(0x3F800001))
    )
    assert_equal(
        _round_bound[False](1, -tiny),
        bitcast[DType.float32](UInt32(0x3F7FFFFF)),
    )
    assert_equal(
        _round_bound[True](-1, tiny), bitcast[DType.float32](UInt32(0xBF7FFFFF))
    )
    assert_equal(
        _round_bound[False](-1, -tiny),
        bitcast[DType.float32](UInt32(0xBF800001)),
    )
    for x in [Float64(-1), Float64(0), Float64(1)]:
        assert_equal(_round_bound[True](x, 0), Float32(x))
        assert_equal(_round_bound[False](x, 0), Float32(x))
        assert_equal(_round_bound[True](x, -tiny), Float32(x))
        assert_equal(_round_bound[False](x, tiny), Float32(x))
    var infinity = inf[DType.float64]()
    assert_equal(_round_bound[True](infinity, 0), inf[DType.float32]())
    assert_equal(_round_bound[False](-infinity, 0), -inf[DType.float32]())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
