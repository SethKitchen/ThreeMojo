# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Independent geometric regressions for thin triangles and Octree contacts."""

from math.bounds import Sphere
from math.capsule import Capsule
from math.octree import (
    Octree,
    _contains_point,
    line_to_line_closest_points,
    triangle_capsule_intersect,
    triangle_sphere_intersect,
)
from math.triangle import Line3, Triangle
from math.vector3 import Vector3
from std.math import inf, isfinite, nan, sqrt
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def near(actual: Float64, expected: Float64, tolerance: Float64 = 2e-7) raises:
    """Use a finite, absolute-only oracle; NaN must not pass."""
    assert_true(isfinite(actual))
    assert_true(isfinite(expected))
    if not (abs(actual - expected) <= tolerance):
        print("NEAR FAILED", actual, expected, tolerance)
    assert_true(abs(actual - expected) <= tolerance)


def near_vector(
    actual: Vector3, expected: Vector3, tolerance: Float64 = 2e-7
) raises:
    near(Float64(actual.x), Float64(expected.x), tolerance)
    near(Float64(actual.y), Float64(expected.y), tolerance)
    near(Float64(actual.z), Float64(expected.z), tolerance)


def reference_weights(triangle: Triangle, point: Vector3) raises -> Vector3:
    """Solve [b-a, c-a, normal] * [v, w, height] = p-a by pivoting.

    Float64 Gaussian elimination is independent of the production signed
    area ratios. It uses the stored Float32 vertices, after quantization.
    """
    var bx = Float64(triangle.b.x) - Float64(triangle.a.x)
    var by = Float64(triangle.b.y) - Float64(triangle.a.y)
    var bz = Float64(triangle.b.z) - Float64(triangle.a.z)
    var cx = Float64(triangle.c.x) - Float64(triangle.a.x)
    var cy = Float64(triangle.c.y) - Float64(triangle.a.y)
    var cz = Float64(triangle.c.z) - Float64(triangle.a.z)
    var matrix = List[Float64](
        [
            bx,
            cx,
            by * cz - bz * cy,
            Float64(point.x) - Float64(triangle.a.x),
            by,
            cy,
            bz * cx - bx * cz,
            Float64(point.y) - Float64(triangle.a.y),
            bz,
            cz,
            bx * cy - by * cx,
            Float64(point.z) - Float64(triangle.a.z),
        ]
    )
    for column in range(3):
        var pivot = column
        for row in range(column + 1, 3):
            if abs(matrix[row * 4 + column]) > abs(matrix[pivot * 4 + column]):
                pivot = row
        for entry in range(4):
            var old = matrix[column * 4 + entry]
            matrix[column * 4 + entry] = matrix[pivot * 4 + entry]
            matrix[pivot * 4 + entry] = old
        var diagonal = matrix[column * 4 + column]
        assert_true(diagonal != 0)
        for entry in range(column, 4):
            matrix[column * 4 + entry] /= diagonal
        for row in range(3):
            if row != column:
                var amount = matrix[row * 4 + column]
                for entry in range(column, 4):
                    matrix[row * 4 + entry] -= (
                        amount * matrix[column * 4 + entry]
                    )
    return Vector3(
        Float32(1 - matrix[3] - matrix[7]),
        Float32(matrix[3]),
        Float32(matrix[7]),
    )


def transform(point: Vector3, variant: Int, scale: Float32) -> Vector3:
    if variant == 0:
        return point * scale
    if variant == 1:
        return Vector3(point.z + 2, point.x - 3, point.y + 5) * scale
    # A non-axis-aligned orthonormal basis, then a translation.
    return (
        Vector3(0.6, 0.8, 0) * point.x
        + Vector3(-0.48, 0.36, 0.8) * point.y
        + Vector3(0.64, -0.48, 0.6) * point.z
        + Vector3(2, -3, 5)
    ) * scale


def test_thin_triangles_keep_weights_projection_and_nearest_identity() raises:
    for height in List[Float32]([Float32(0.001), Float32(0.0001)]):
        for scale in List[Float32]([Float32(0.01), Float32(1), Float32(100)]):
            for variant in range(3):
                var triangle = Triangle(
                    transform(Vector3(0, 0, 0), variant, scale),
                    transform(Vector3(1, 0, 0), variant, scale),
                    transform(Vector3(1, height, 0), variant, scale),
                )
                assert_false(triangle.is_degenerate())
                var point = transform(
                    Vector3(Float32(2) / 3, height / 3, 0), variant, scale
                )
                var expected = reference_weights(triangle, point)
                var actual = triangle.barycoord(point)
                near_vector(actual, expected)
                near(
                    Float64(actual.x) + Float64(actual.y) + Float64(actual.z), 1
                )
                if variant == 0:
                    near_vector(
                        actual,
                        Vector3(Float32(1) / 3, Float32(1) / 3, Float32(1) / 3),
                    )
                assert_true(triangle.contains_point(point))
                assert_true(_contains_point(triangle, point))
                var reconstructed = (
                    triangle.a * actual.x
                    + triangle.b * actual.y
                    + triangle.c * actual.z
                )
                near_vector(reconstructed, point, Float64(scale) * 1e-6)
                near_vector(
                    triangle.closest_point_to_point(point),
                    point,
                    Float64(scale) * 1e-6,
                )
                near_vector(
                    triangle.interpolate(
                        point,
                        Vector3(1, 0, 0),
                        Vector3(0, 1, 0),
                        Vector3(0, 0, 1),
                    ),
                    expected,
                )
                var above = transform(
                    Vector3(Float32(2) / 3, height / 3, 0.25), variant, scale
                )
                near_vector(
                    triangle.barycoord(above),
                    reference_weights(triangle, above),
                )
                var projected = triangle.closest_point_to_point(above)
                near(
                    Float64((above - projected).dot(triangle.b - triangle.a)),
                    0,
                    Float64(scale) * Float64(scale) * 2e-6,
                )
                near(
                    Float64((above - projected).dot(triangle.c - triangle.a)),
                    0,
                    Float64(scale) * Float64(scale) * 2e-6,
                )
                near_vector(triangle.barycoord(triangle.a), Vector3(1, 0, 0))
                near_vector(triangle.barycoord(triangle.b), Vector3(0, 1, 0))
                near_vector(triangle.barycoord(triangle.c), Vector3(0, 0, 1))


def test_thin_edges_and_collinear_triangles_keep_their_contracts() raises:
    for height in List[Float32]([Float32(0.001), Float32(0.0001)]):
        var triangle = Triangle(
            Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, height, 0)
        )
        for point in List[Vector3](
            [
                Vector3(0.5, 0, 0),
                Vector3(1, height * 0.5, 0),
                Vector3(0.5, height * 0.5, 0),
            ]
        ):
            near_vector(
                triangle.barycoord(point), reference_weights(triangle, point)
            )
            assert_true(triangle.contains_point(point))
            assert_true(_contains_point(triangle, point))
            near_vector(triangle.closest_point_to_point(point), point)
        assert_false(_contains_point(triangle, Vector3(0.5, -height, 0)))
        assert_false(_contains_point(triangle, Vector3(1.5, height * 0.5, 0)))
        assert_false(_contains_point(triangle, Vector3(0, height, 0)))
        assert_false(
            _contains_point(triangle, Vector3(nan[DType.float32](), 0, 0))
        )
    for direction in List[Vector3](
        [Vector3(1, 0, 0), Vector3(0, 2, 0), Vector3(1, 2, 3), Vector3(0, 0, 0)]
    ):
        var triangle = Triangle(Vector3(0, 0, 0), direction, direction * 2)
        with assert_raises(contains="degenerate"):
            _ = triangle.barycoord(Vector3(0, 0, 0))
        assert_false(_contains_point(triangle, Vector3(0, 0, 0)))


def ground() -> Triangle:
    return Triangle(Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 0))


def test_sphere_face_edge_vertex_and_touch_contacts() raises:
    var triangle = ground()
    for center in List[Vector3](
        [
            Vector3(-0.1, 0, 0.5),
            Vector3(-0.1, 0.1, 0.5),
            Vector3(-0.1, -0.1, 0.5),
            Vector3(-0.1, -0.1, -0.1),
        ]
    ):
        var expected = Vector3(0, 0, max(Float32(0), center.z))
        var contact = triangle_sphere_intersect(Sphere(center, 0.3), triangle)
        assert_true(Bool(contact))
        near_vector(contact.value().point, expected)
        var delta = center - expected
        var distance = delta.length()
        near(Float64(contact.value().depth), 0.3 - Float64(distance))
        delta.normalize()
        near_vector(contact.value().normal, delta)
    # Front and back face contacts both push to the front of the surface.
    for height in List[Float32]([Float32(-0.25), Float32(0), Float32(0.25)]):
        var contact = triangle_sphere_intersect(
            Sphere(Vector3(0.25, height, 0.25), 0.25), triangle
        )
        assert_true(Bool(contact))
        near_vector(contact.value().normal, Vector3(0, 1, 0))
        near(Float64(contact.value().depth), 0.25 - Float64(height))
    # A dyadic radius makes exact touch distinct from just outside.
    for center in List[Vector3](
        [
            Vector3(-0.25, 0, 0.5),
            Vector3(-0.25, 0, 0),
            Vector3(0.25, 0.25, 0.25),
        ]
    ):
        var touch = triangle_sphere_intersect(Sphere(center, 0.25), triangle)
        assert_true(Bool(touch))
        near(Float64(touch.value().depth), 0)
        assert_false(
            Bool(triangle_sphere_intersect(Sphere(center, 0.24999), triangle))
        )
    assert_false(
        Bool(
            triangle_sphere_intersect(
                Sphere(Vector3(0.25, -0.25001, 0.25), 0.25), triangle
            )
        )
    )
    assert_false(
        Bool(triangle_sphere_intersect(Sphere(Vector3(0, 0, 0), -1), triangle))
    )
    # More than one edge overlaps; the closest edge is not the first edge.
    var corner = triangle_sphere_intersect(
        Sphere(Vector3(1.1, 0, 0.1), 1.25), triangle
    )
    assert_true(Bool(corner))
    near_vector(corner.value().point, Vector3(1, 0, 0))
    near(Float64(corner.value().depth), 1.25 - sqrt(Float64(0.02)))


def test_constrained_segment_minima_and_short_parallel_segments() raises:
    var first = Line3(Vector3(0, 0, 0), Vector3(1, 0, 0))
    var second = Line3(Vector3(2, -1, 0), Vector3(3, 1, 0))
    for swap in range(2):
        for reverse in range(2):
            var a = first if swap == 0 else second
            var b = second if swap == 0 else first
            if reverse == 1:
                a = Line3(a.end, a.start)
                b = Line3(b.end, b.start)
            var result = line_to_line_closest_points(
                a.start, a.end, b.start, b.end
            )
            assert_true(Bool(result))
            var expected_a = Vector3(1, 0, 0) if swap == 0 else Vector3(
                2.2, -0.6, 0
            )
            var expected_b = Vector3(2.2, -0.6, 0) if swap == 0 else Vector3(
                1, 0, 0
            )
            near_vector(result.value()[0], expected_a)
            near_vector(result.value()[1], expected_b)
            var on_a = a.start
            var on_b = b.start
            near(Float64(a.closest_points_to_line(b, on_a, on_b)), 1.8, 4e-7)
            near_vector(on_a, expected_a)
            near_vector(on_b, expected_b)
    # Interior crossing remains visible at angles that cancel a Float32 Gram determinant.
    for height in List[Float32]([Float32(0.001), Float32(0.0001)]):
        var result = line_to_line_closest_points(
            Vector3(0, 0, 0),
            Vector3(1, 0, 0),
            Vector3(0, -height, 0.1),
            Vector3(1, height, 0.1),
        )
        assert_true(Bool(result))
        near_vector(result.value()[0], Vector3(0.5, 0, 0))
        near_vector(result.value()[1], Vector3(0.5, 0, 0.1))
    # Octree treats a short nonzero edge as a segment, not as a point.
    var short = line_to_line_closest_points(
        Vector3(5e-10, 1e-10, 0),
        Vector3(5e-10, 1e-10, 0),
        Vector3(0, 0, 0),
        Vector3(1e-9, 0, 0),
    )
    assert_true(Bool(short))
    near_vector(short.value()[1], Vector3(5e-10, 0, 0), 1e-16)
    assert_false(
        Bool(
            line_to_line_closest_points(
                first.start, first.end, second.start, second.start
            )
        )
    )
    var parallel = line_to_line_closest_points(
        Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 1, 0), Vector3(3, 1, 0)
    )
    assert_true(Bool(parallel))
    near_vector(parallel.value()[0], Vector3(1, 0, 0))
    near_vector(parallel.value()[1], Vector3(2, 1, 0))


def test_capsule_segment_contacts_touch_and_sidedness() raises:
    # The edge has the issue's two constrained segments, translated to y = 0.
    var triangle = Triangle(
        Vector3(2, 0, -1), Vector3(3, 0, 1), Vector3(4, 0, 1)
    )
    var capsule = Capsule(Vector3(0, 0, 0), Vector3(1, 0, 0), 1.4)
    var contact = triangle_capsule_intersect(capsule, triangle)
    assert_true(Bool(contact))
    near_vector(contact.value().point, Vector3(2.2, 0, -0.6))
    near(Float64(contact.value().depth), 1.4 - sqrt(Float64(1.8)))
    var edge_touch = triangle_capsule_intersect(
        Capsule(Vector3(-0.25, 0, 0.25), Vector3(-0.25, 0, 0.75), 0.25),
        ground(),
    )
    assert_true(Bool(edge_touch))
    near(Float64(edge_touch.value().depth), 0)
    var face_touch = triangle_capsule_intersect(
        Capsule(Vector3(0.25, 0.25, 0.25), Vector3(0.25, 0.25, 0.5), 0.25),
        ground(),
    )
    assert_true(Bool(face_touch))
    near(Float64(face_touch.value().depth), 0)
    near_vector(face_touch.value().normal, Vector3(0, 1, 0))
    assert_false(
        Bool(
            triangle_capsule_intersect(
                Capsule(
                    Vector3(0.25, -0.1, 0.25), Vector3(0.25, -0.1, 0.5), 0.25
                ),
                ground(),
            )
        )
    )
    assert_false(
        Bool(
            triangle_capsule_intersect(
                Capsule(
                    Vector3(-0.25001, 0, 0.25), Vector3(-0.25001, 0, 0.75), 0.25
                ),
                ground(),
            )
        )
    )


def test_octree_queries_use_corrected_thin_face_and_edge_contacts() raises:
    var tree = Octree()
    assert_equal(len(tree.boxes()), 0)
    tree.add_triangle(ground())
    tree.build()
    assert_equal(len(tree.boxes()), tree.node_count() - 1)
    var sphere = tree.sphere_intersect(Sphere(Vector3(-0.1, 0, 0.5), 0.3))
    assert_true(Bool(sphere))
    near_vector(sphere.value().normal, Vector3(-1, 0, 0))
    near(Float64(sphere.value().depth), 0.2)
    var capsule = tree.capsule_intersect(
        Capsule(Vector3(-0.1, 0, 0.25), Vector3(-0.1, 0, 0.75), 0.3)
    )
    assert_true(Bool(capsule))
    near_vector(capsule.value().normal, Vector3(-1, 0, 0))
    near(Float64(capsule.value().depth), 0.2)
    for height in List[Float32]([Float32(0.001), Float32(0.0001)]):
        var thin = Octree()
        thin.add_triangle(
            Triangle(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, height, 0))
        )
        thin.build()
        var center = Vector3(Float32(2) / 3, height / 3, 0.1)
        var face = thin.sphere_intersect(Sphere(center, 0.2))
        assert_true(Bool(face))
        near_vector(face.value().normal, Vector3(0, 0, 1))
        near(Float64(face.value().depth), 0.1)
        var cap = thin.capsule_intersect(
            Capsule(center, center + Vector3(0, 0, 1), 0.2)
        )
        assert_true(Bool(cap))
        near_vector(cap.value().normal, Vector3(0, 0, 1))
        near(Float64(cap.value().depth), 0.1)


def test_nested_octree_boxes_remain_available_after_contact_fixes() raises:
    var tree = Octree()
    tree.triangles_per_leaf = 1
    tree.max_level = 2
    tree.add_triangle(ground())
    tree.add_triangle(ground())
    tree.build()
    assert_equal(len(tree.boxes()), tree.node_count() - 1)
    assert_true(len(tree.boxes()) > 8)


def test_contact_oracles_reject_nan_and_infinity() raises:
    with assert_raises():
        near(Float64(nan[DType.float32]()), 0)
    with assert_raises():
        near(Float64(0), Float64(nan[DType.float32]()))
    with assert_raises():
        near(inf[DType.float64](), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
