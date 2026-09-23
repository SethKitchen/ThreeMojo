# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the three.js `Box3`, `Box2`, `Sphere`, `Plane`, `Line3`,
`Triangle` and `Frustum` members added to `math.bounds`, `math.matrix2`,
`math.triangle` and `math.frustum`.

The expected numbers come from three.js 0.180, run in node on the same
inputs.
"""

from math.bounds import Box3, Plane, Sphere
from math.frustum import (
    CoordinateSystem,
    FAR,
    Frustum,
    NEAR,
    WEBGL_COORDINATES,
    WEBGPU_COORDINATES,
)
from math.matrix2 import Box2
from math.matrix3 import Matrix3
from math.matrix4 import Matrix4, compose, scaling, translation
from math.projection import perspective
from math.quaternion import Quaternion
from math.triangle import Line3, Triangle
from math.vector2 import Vector2
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, RADIAN

comptime TOLERANCE = Float64(2e-5)


def assert_vector(got: Vector3, x: Float64, y: Float64, z: Float64) raises:
    """Assert a vector matches three components, within tolerance.

    Args:
        got: The vector to check.
        x: Expected x.
        y: Expected y.
        z: Expected z.

    Raises:
        Error: If a component differs.
    """
    assert_almost_equal(Float64(got.x), x, atol=TOLERANCE)
    assert_almost_equal(Float64(got.y), y, atol=TOLERANCE)
    assert_almost_equal(Float64(got.z), z, atol=TOLERANCE)


def a_box() -> Box3:
    """Return the box the node run used."""
    return Box3(Vector3(-1, -1, -1), Vector3(1, 2, 3))


# --- Box3 ------------------------------------------------------------------


def test_box_from_center_and_size() raises:
    var box = Box3.from_center_and_size(Vector3(0, 0.5, 1), Vector3(2, 3, 4))
    assert_true(box == a_box())
    assert_false(box != a_box())
    assert_false(box == Box3(Vector3(-1, -1, -1), Vector3(1, 2, 4)))


def test_box_expand_by_vector_and_scalar() raises:
    var box = a_box()
    box.expand_by_vector(Vector3(1, 2, 3))
    assert_vector(box.min, -2, -3, -4)
    assert_vector(box.max, 2, 4, 6)
    box.expand_by_scalar(-1)
    assert_vector(box.min, -1, -2, -3)
    var empty = Box3.empty()
    empty.expand_by_scalar(5)
    assert_true(empty.is_empty())


def test_box_translate() raises:
    var box = a_box()
    box.translate(Vector3(1, 1, 1))
    assert_vector(box.min, 0, 0, 0)
    assert_vector(box.max, 2, 3, 4)


def test_box_intersect() raises:
    var box = a_box()
    box.intersect(Box3(Vector3(0, 0, 0), Vector3(5, 5, 5)))
    assert_vector(box.min, 0, 0, 0)
    assert_vector(box.max, 1, 2, 3)
    var apart = a_box()
    apart.intersect(Box3(Vector3(4, 4, 4), Vector3(5, 5, 5)))
    assert_true(apart == Box3.empty())


def test_box_contains_box() raises:
    assert_true(a_box().contains_box(Box3(Vector3(0, 0, 0), Vector3(1, 1, 1))))
    assert_true(a_box().contains_box(a_box()))
    assert_true(a_box().contains_box(Box3.empty()))
    assert_false(Box3.empty().contains_box(a_box()))
    var inner = Box3(Vector3(0, 0, 0), Vector3(1, 1, 1))
    for axis in range(3):
        var low = inner
        low.min.set_component(axis, -5)
        assert_false(a_box().contains_box(low))
        var high = inner
        high.max.set_component(axis, 5)
        assert_false(a_box().contains_box(high))


def test_box_get_parameter() raises:
    assert_vector(
        a_box().get_parameter(Vector3(0, 0, 0)), 0.5, 0.3333333333333333, 0.25
    )
    with assert_raises():
        _ = Box3(Vector3(0, 0, 0), Vector3(0, 1, 1)).get_parameter(
            Vector3(0, 0, 0)
        )
    with assert_raises():
        _ = Box3(Vector3(0, 0, 0), Vector3(1, 0, 1)).get_parameter(
            Vector3(0, 0, 0)
        )
    with assert_raises():
        _ = Box3(Vector3(0, 0, 0), Vector3(1, 1, 0)).get_parameter(
            Vector3(0, 0, 0)
        )
    with assert_raises():
        _ = Box3.empty().get_parameter(Vector3(0, 0, 0))


def test_box_intersects_plane() raises:
    var through = Plane(Vector3(0, 1, 0), 0)
    assert_true(a_box().intersects_plane(through))
    assert_false(a_box().intersects_plane(Plane(Vector3(0, 1, 0), -5)))
    assert_false(Box3.empty().intersects_plane(through))


def test_box_intersects_triangle() raises:
    var box = a_box()
    # Through the box.
    assert_true(
        box.intersects_triangle(
            Triangle(Vector3(0, 0, 0), Vector3(5, 5, 5), Vector3(5, 0, 0))
        )
    )
    # Beside a face, separated only by the box's own axes.
    assert_false(
        box.intersects_triangle(
            Triangle(
                Vector3(-3, -3.5, 0.5), Vector3(-1, -1.5, 1), Vector3(-3, -3, 1)
            )
        )
    )
    # Past a corner, separated only by an edge's cross product.
    assert_false(
        box.intersects_triangle(
            Triangle(
                Vector3(3.5, 3.5, 0.5),
                Vector3(-2.5, 2, 2.5),
                Vector3(3.5, 3, 1.5),
            )
        )
    )
    # Across a corner, separated only by the triangle's own plane.
    var diagonal = Triangle(
        Vector3(7, 0, 0), Vector3(0, 7, 0), Vector3(0, 0, 7)
    )
    assert_false(box.intersects_triangle(diagonal))
    assert_false(diagonal.intersects_box(box))
    assert_false(
        Box3.empty().intersects_triangle(
            Triangle(Vector3(0, 0, 0), Vector3(5, 5, 5), Vector3(5, 0, 0))
        )
    )


def test_box_bounding_sphere() raises:
    var sphere = a_box().bounding_sphere()
    assert_vector(sphere.center, 0, 0.5, 1)
    assert_almost_equal(
        Float64(sphere.radius), 2.692582403567252, atol=TOLERANCE
    )


# --- Box2 ------------------------------------------------------------------


def test_box2_members() raises:
    var box = Box2.from_center_and_size(Vector2(0, 0.5), Vector2(2, 3))
    assert_true(box == Box2(Vector2(-1, -1), Vector2(1, 2)))
    assert_false(box != Box2(Vector2(-1, -1), Vector2(1, 2)))
    assert_false(box == Box2(Vector2(-1, -1), Vector2(1, 3)))
    box.expand_by_scalar(1)
    assert_true(box == Box2(Vector2(-2, -2), Vector2(2, 3)))
    box.translate(Vector2(2, 2))
    assert_true(box == Box2(Vector2(0, 0), Vector2(4, 5)))
    var fraction = box.get_parameter(Vector2(1, 1))
    assert_almost_equal(Float64(fraction.x), 0.25, atol=TOLERANCE)
    assert_almost_equal(Float64(fraction.y), 0.2, atol=TOLERANCE)
    with assert_raises():
        _ = Box2(Vector2(0, 0), Vector2(0, 1)).get_parameter(Vector2(0, 0))
    with assert_raises():
        _ = Box2(Vector2(0, 0), Vector2(1, 0)).get_parameter(Vector2(0, 0))
    assert_true(box.contains_box(Box2(Vector2(1, 1), Vector2(2, 2))))
    assert_false(box.contains_box(Box2(Vector2(-1, 1), Vector2(2, 2))))
    assert_false(box.contains_box(Box2(Vector2(1, 1), Vector2(5, 2))))
    assert_false(box.contains_box(Box2(Vector2(1, -1), Vector2(2, 2))))
    assert_false(box.contains_box(Box2(Vector2(1, 1), Vector2(2, 6))))


def test_box2_empty_center_is_the_origin() raises:
    var center = Box2.empty().center()
    assert_equal(center.x, Float32(0))
    assert_equal(center.y, Float32(0))


# --- Sphere ----------------------------------------------------------------


def test_sphere_union() raises:
    var sphere = Sphere(Vector3(0, 0, 0), 1)
    sphere.union(Sphere(Vector3(3, 0, 0), 0.5))
    assert_vector(sphere.center, 1.25, 0, 0)
    assert_almost_equal(Float64(sphere.radius), 2.25, atol=TOLERANCE)
    var same = Sphere(Vector3(0, 0, 0), 1)
    same.union(Sphere(Vector3(0, 0, 0), 2))
    assert_equal(same.radius, Float32(2))
    var empty = Sphere.empty()
    empty.union(same)
    assert_true(empty == same)
    same.union(Sphere.empty())
    assert_equal(same.radius, Float32(2))


def test_sphere_clamp_point() raises:
    var sphere = Sphere(Vector3(0, 0, 0), 1)
    assert_vector(sphere.clamp_point(Vector3(0, 3, 4)), 0, 0.6, 0.8)
    assert_vector(sphere.clamp_point(Vector3(0, 0.5, 0)), 0, 0.5, 0)
    with assert_raises():
        _ = Sphere.empty().clamp_point(Vector3(0, 0, 0))


def test_sphere_translate_equals_and_plane() raises:
    var sphere = Sphere(Vector3(0, 0, 0), 1)
    sphere.translate(Vector3(1, 2, 3))
    assert_true(sphere == Sphere(Vector3(1, 2, 3), 1))
    assert_false(sphere == Sphere(Vector3(1, 2, 3), 2))
    assert_true(sphere != Sphere(Vector3(0, 2, 3), 1))
    assert_true(sphere.intersects_plane(Plane(Vector3(0, 1, 0), -2.5)))
    assert_false(sphere.intersects_plane(Plane(Vector3(0, 1, 0), 0)))
    assert_false(Sphere.empty().intersects_plane(Plane(Vector3(0, 1, 0), 0)))


def test_sphere_from_points_around() raises:
    var points: List[Vector3] = [Vector3(1, 0, 0), Vector3(0, 3, 0)]
    var sphere = Sphere.from_points_around(points, Vector3(0, 1, 0))
    assert_equal(sphere.radius, Float32(2))
    var none = Sphere.from_points_around(List[Vector3](), Vector3(1, 1, 1))
    assert_equal(none.radius, Float32(0))


# --- Plane -----------------------------------------------------------------


def a_plane() raises -> Plane:
    """Return the plane through (1, 0, 0) facing (1, 1, 0)."""
    return Plane.from_normal_and_point(Vector3(1, 1, 0), Vector3(1, 0, 0))


def test_plane_intersect_line() raises:
    var hit = a_plane().intersect_line(
        Line3(Vector3(0, 0, 0), Vector3(2, 2, 0))
    )
    assert_true(Bool(hit))
    assert_vector(hit.value(), 0.5, 0.5, 0)
    # Stops short, either way.
    assert_false(
        Bool(
            a_plane().intersect_line(
                Line3(Vector3(0, 0, 0), Vector3(0.1, 0.1, 0))
            )
        )
    )
    assert_false(
        Bool(
            a_plane().intersect_line(Line3(Vector3(2, 2, 0), Vector3(3, 3, 0)))
        )
    )
    # Parallel: in the plane gives the start, beside it gives nothing.
    var flat = Plane(Vector3(0, 0, 1), 0)
    var inside = flat.intersect_line(Line3(Vector3(1, 2, 0), Vector3(3, 4, 0)))
    assert_vector(inside.value(), 1, 2, 0)
    assert_false(
        Bool(flat.intersect_line(Line3(Vector3(1, 2, 1), Vector3(3, 4, 1))))
    )


def test_plane_intersects_line() raises:
    var flat = Plane(Vector3(0, 0, 1), 0)
    assert_true(
        flat.intersects_line(Line3(Vector3(0, 0, -1), Vector3(0, 0, 1)))
    )
    assert_true(
        flat.intersects_line(Line3(Vector3(0, 0, 1), Vector3(0, 0, -1)))
    )
    assert_false(
        flat.intersects_line(Line3(Vector3(0, 0, 1), Vector3(0, 0, 2)))
    )
    assert_false(
        flat.intersects_line(Line3(Vector3(0, 0, -1), Vector3(0, 0, -2)))
    )
    # An end on the plane does not count, as in three.js.
    assert_false(
        flat.intersects_line(Line3(Vector3(0, 0, 0), Vector3(0, 0, 1)))
    )


def test_plane_apply_matrix4() raises:
    var axis = Vector3(1, 1, 0)
    axis.normalize()
    var m = compose(
        Vector3(1, 2, 3),
        Quaternion.from_axis_angle(axis, Angle(0.7, RADIAN)),
        Vector3(2, 3, 0.5),
    )
    var plane = a_plane()
    plane.apply_matrix4(m)
    assert_vector(
        plane.normal,
        0.7994397731235462,
        0.5873107174395266,
        -0.1263414830087154,
    )
    assert_almost_equal(Float64(plane.constant), -3.25913734765214, atol=1e-4)
    var flattened = a_plane()
    with assert_raises():
        flattened.apply_matrix4(scaling(0, 1, 1))
    with assert_raises():
        flattened.apply_matrix4(Matrix4(), Matrix3.scaling(0, 0))


def test_plane_equals() raises:
    assert_true(a_plane() == a_plane())
    var turned = a_plane()
    turned.negate()
    assert_true(turned != a_plane())
    var moved = a_plane()
    moved.translate(Vector3(1, 1, 0))
    assert_false(moved == a_plane())


# --- Line3 and Triangle ----------------------------------------------------


def test_line_closest_points() raises:
    var x = Line3(Vector3(0, 0, 0), Vector3(2, 0, 0))
    var on_x = Vector3(0, 0, 0)
    var on_other = Vector3(0, 0, 0)
    var squared = x.closest_points_to_line(
        Line3(Vector3(1, -1, 1), Vector3(1, 1, 1)), on_x, on_other
    )
    assert_almost_equal(Float64(squared), 1, atol=TOLERANCE)
    assert_vector(on_x, 1, 0, 0)
    assert_vector(on_other, 1, 0, 1)
    assert_equal(x.distance_sq(), Float32(4))


def test_line_equals() raises:
    var x = Line3(Vector3(0, 0, 0), Vector3(2, 0, 0))
    assert_true(x == Line3(Vector3(0, 0, 0), Vector3(2, 0, 0)))
    assert_false(x == Line3(Vector3(1, 0, 0), Vector3(2, 0, 0)))
    assert_true(x != Line3(Vector3(0, 0, 0), Vector3(3, 0, 0)))


def test_triangle_from_points_and_equals() raises:
    var points: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(0, 1, 0),
    ]
    var t = Triangle.from_points_and_indices(points, 2, 0, 1)
    assert_true(
        t == Triangle(Vector3(0, 1, 0), Vector3(0, 0, 0), Vector3(1, 0, 0))
    )
    assert_false(
        t == Triangle(Vector3(0, 0, 0), Vector3(0, 0, 0), Vector3(1, 0, 0))
    )
    assert_false(
        t == Triangle(Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 0, 0))
    )
    assert_true(
        t != Triangle(Vector3(0, 1, 0), Vector3(0, 0, 0), Vector3(2, 0, 0))
    )
    with assert_raises():
        _ = Triangle.from_points_and_indices(points, 0, 1, 3)
    with assert_raises():
        _ = Triangle.from_points_and_indices(points, -1, 1, 2)
    assert_true(t.intersects_box(Box3(Vector3(-1, -1, -1), Vector3(1, 1, 1))))


# --- Frustum ---------------------------------------------------------------


def test_frustum_webgpu_and_reversed_depth() raises:
    # A WebGPU projection maps the near plane at 1 to depth 0 and the far
    # plane at 10 to depth 1: z' = -10/9 z - 10/9, w = -z.
    var gpu = Matrix4()
    gpu.set(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, -10.0 / 9, -10.0 / 9, 0, 0, -1, 0)
    var frustum = Frustum.from_projection_matrix(gpu, WEBGPU_COORDINATES)
    assert_almost_equal(
        Float64(frustum.planes[NEAR].distance_to_point(Vector3(0, 0, -1))),
        0,
        atol=TOLERANCE,
    )
    assert_almost_equal(
        Float64(frustum.planes[FAR].distance_to_point(Vector3(0, 0, -10))),
        0,
        atol=TOLERANCE,
    )
    assert_true(frustum.contains_point(Vector3(0, 0, -5)))
    # Reversed: near maps to depth 1 and far to 0: z' = z/9 + 10/9.
    var reversed = Matrix4()
    reversed.set(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1.0 / 9, 10.0 / 9, 0, 0, -1, 0)
    var back = Frustum.from_projection_matrix(
        reversed, WEBGL_COORDINATES, reversed_depth=True
    )
    assert_almost_equal(
        Float64(back.planes[NEAR].distance_to_point(Vector3(0, 0, -1))),
        0,
        atol=TOLERANCE,
    )
    assert_almost_equal(
        Float64(back.planes[FAR].distance_to_point(Vector3(0, 0, -10))),
        0,
        atol=TOLERANCE,
    )
    assert_false(back.contains_point(Vector3(0, 0, -11)))
    with assert_raises():
        _ = Frustum.from_projection_matrix(gpu, CoordinateSystem(0))


def test_webgl_frustum_is_the_default() raises:
    var clip = perspective(-1, 1, 1, -1, 1, 10)
    var frustum = Frustum.from_projection_matrix(clip, WEBGL_COORDINATES)
    assert_almost_equal(
        Float64(frustum.planes[NEAR].distance_to_point(Vector3(0, 0, -1))),
        0,
        atol=TOLERANCE,
    )
    assert_true(WEBGL_COORDINATES.is_valid())
    assert_false(CoordinateSystem(1999).is_valid())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
