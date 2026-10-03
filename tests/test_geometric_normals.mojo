# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Exact dyadic controls for finite three-point normal construction."""

from math.bounds import Plane
from math.triangle import Triangle
from math.vector3 import Vector3
from std.math import inf, isnan, nan
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def test_normals_keep_every_finite_binary_scale() raises:
    var scales: List[Float32] = [
        bitcast[DType.float32](UInt32(1)),
        bitcast[DType.float32](UInt32(0x7F7FFFFF)),
    ]
    for exponent in range(1, 255):
        scales.append(bitcast[DType.float32](UInt32(exponent) << 23))
    for scale in scales:
        var a = Vector3(0, 0, 7)
        var b = Vector3(scale, 0, 7)
        var c = Vector3(0, scale, 7)
        var triangle = Triangle(a, b, c)
        assert_false(triangle.is_degenerate())
        assert_true(triangle.normal() == Vector3(0, 0, 1))
        var plane = Plane.from_coplanar_points(a, b, c)
        assert_true(plane.normal == Vector3(0, 0, 1))
        assert_equal(plane.constant, Float32(-7))
        assert_equal(triangle.plane().constant, Float32(-7))
        assert_true(Triangle(a, c, b).normal() == Vector3(0, 0, -1))


def test_original_coordinates_keep_a_lost_edge_residual() raises:
    # Exact cross z is 2 - 2**-200. Both rounded Float64 edge vectors are
    # (-2**100, -2**100, 0), so widening differences alone gives zero.
    var tiny = bitcast[DType.float32](UInt32(0x0D800000))
    var huge = bitcast[DType.float32](UInt32(0x71800000))
    var a = Vector3(tiny, 0, 3)
    var b = Vector3(huge, huge, 3)
    var c = Vector3(0, tiny, 3)
    var points = [a, b, c]
    for offset in range(3):
        var triangle = Triangle(
            points[offset], points[(offset + 1) % 3], points[(offset + 2) % 3]
        )
        assert_false(triangle.is_degenerate())
        assert_true(triangle.normal() == Vector3(0, 0, 1))
        assert_equal(triangle.plane().constant, Float32(-3))
        var reverse = Triangle(triangle.a, triangle.c, triangle.b)
        assert_true(reverse.normal() == Vector3(0, 0, -1))
        assert_equal(reverse.plane().constant, Float32(3))


def test_extreme_collinearity_still_has_no_normal() raises:
    var huge = bitcast[DType.float32](UInt32(0x7F7FFFFF))
    for scale in [bitcast[DType.float32](UInt32(1)), Float32(1), huge]:
        var triangle = Triangle(
            Vector3(-scale, -scale, -scale),
            Vector3(0, 0, 0),
            Vector3(scale, scale, scale),
        )
        assert_true(triangle.is_degenerate())
        with assert_raises(contains="no normal"):
            _ = triangle.normal()
        with assert_raises(contains="no normal"):
            _ = triangle.plane()
        with assert_raises(contains="one line"):
            _ = Plane.from_coplanar_points(triangle.a, triangle.b, triangle.c)
    var repeated = Triangle(
        Vector3(3, 2, 1), Vector3(3, 2, 1), Vector3(2, 1, 0)
    )
    assert_true(repeated.is_degenerate())


def test_extreme_normal_components_have_the_exact_symmetric_direction() raises:
    for scale in [
        bitcast[DType.float32](UInt32(1)),
        Float32(1),
        bitcast[DType.float32](UInt32(0x71800000)),
    ]:
        var triangle = Triangle(
            Vector3(0, 0, 0),
            Vector3(scale, scale, 0),
            Vector3(0, scale, scale),
        )
        var normal = triangle.normal()
        assert_almost_equal(normal.x, Float32(0.5773502691896258), atol=1e-6)
        assert_equal(normal.y, -normal.x)
        assert_equal(normal.z, normal.x)
    var huge = bitcast[DType.float32](UInt32(0x7F7FFFFF))
    var opposite = Triangle(
        Vector3(-huge, -huge, 0),
        Vector3(huge, huge, 0),
        Vector3(-huge, huge, 0),
    )
    assert_true(opposite.normal() == Vector3(0, 0, 1))


def test_nonfinite_coordinates_retain_direct_ieee_classification() raises:
    for invalid in [inf[DType.float32](), nan[DType.float32]()]:
        for corner in range(3):
            for axis in range(3):
                var points = [
                    Vector3(0, 0, 0),
                    Vector3(1, 0, 0),
                    Vector3(0, 1, 0),
                ]
                points[corner].set_component(axis, invalid)
                var triangle = Triangle(points[0], points[1], points[2])
                var old = triangle.raw_normal()
                old.normalize()
                var normal = triangle.normal()
                assert_false(triangle.is_degenerate())
                for component in range(3):
                    var expected = old.get_component(component)
                    var actual = normal.get_component(component)
                    if isnan(expected):
                        assert_true(isnan(actual))
                    else:
                        assert_equal(actual, expected)
                var old_plane = Plane(
                    triangle.raw_normal(),
                    -triangle.raw_normal().dot(triangle.a),
                )
                var plane = Plane.from_coplanar_points(
                    triangle.a, triangle.b, triangle.c
                )
                assert_equal(isnan(plane.constant), isnan(old_plane.constant))
                var old_triangle_plane = Plane.from_normal_and_point(
                    old, triangle.a
                )
                var triangle_plane = triangle.plane()
                assert_equal(
                    isnan(triangle_plane.constant),
                    isnan(old_triangle_plane.constant),
                )


def test_raw_output_limits_do_not_define_collinearity() raises:
    var tiny = bitcast[DType.float32](UInt32(1))
    var triangle = Triangle(
        Vector3(0, 0, 0), Vector3(tiny, 0, 0), Vector3(0, tiny, 0)
    )
    assert_true(triangle.raw_normal() == Vector3(0, 0, 0))
    assert_equal(triangle.area(), Float32(0))
    assert_false(triangle.is_degenerate())
    assert_true(triangle.normal() == Vector3(0, 0, 1))


def test_coplanar_constant_uses_original_coordinates_after_cancellation() raises:
    # c = a + b exactly. The determinant is zero. The rounded Float32
    # normal dotted with a loses cancellation and gives a nonzero constant.
    var a = Vector3(-65576, 74111, -46463)
    var b = Vector3(85174, 27082, 79223)
    var c = Vector3(19598, 101193, 32760)
    var plane = Plane.from_coplanar_points(a, b, c)
    assert_equal(plane.constant, Float32(0))
    assert_equal(Triangle(a, b, c).plane().constant, Float32(0))


def test_coplanar_constants_keep_the_finite_output_boundary() raises:
    # Independent 180-digit Decimal controls for sqrt(2)*point. Adjacent
    # source Float32 values cross the final finite/infinite rounding boundary.
    var expected = [
        UInt32(0x7F7FFFFA),
        UInt32(0x7F7FFFFB),
        UInt32(0x7F7FFFFD),
        UInt32(0x7F7FFFFE),
        UInt32(0x7F800000),
        UInt32(0x7F800000),
        UInt32(0x7F800000),
    ]
    for index in range(7):
        var bits = UInt32(0x7F3504EF) + UInt32(index)
        var point = bitcast[DType.float32](bits)
        var after = bitcast[DType.float32](bits + 1)
        var before = bitcast[DType.float32](bits - 1)
        var plane = Plane.from_coplanar_points(
            Vector3(point, point, 0),
            Vector3(after, before, 0),
            Vector3(point, point, 1),
        )
        assert_equal(bitcast[DType.uint32](plane.constant), expected[index])
        assert_almost_equal(
            plane.normal.x, Float32(-0.7071067811865475), atol=1e-6
        )
        assert_equal(plane.normal.y, plane.normal.x)
        assert_equal(plane.normal.z, Float32(0))
    var huge = bitcast[DType.float32](UInt32(0x7F7FFFFF))
    for axis in range(3):
        var a = Vector3(0, 0, 0)
        a.set_component(axis, huge)
        var b = a
        b.set_component((axis + 1) % 3, 1)
        var c = a
        c.set_component((axis + 2) % 3, 1)
        var plane = Plane.from_coplanar_points(a, b, c)
        assert_equal(plane.constant, -huge)
        assert_equal(plane.normal.get_component(axis), Float32(1))


def test_cancellation_in_one_cross_component_keeps_its_direction() raises:
    # Exact cross is (10000001, -10000000, -1). Its z component is lost
    # by Float32 product subtraction, even though the norm is ordinary.
    var triangle = Triangle(
        Vector3(0, 0, 0),
        Vector3(10000000, 10000001, 0),
        Vector3(10000001, 10000002, 1),
    )
    var normal = triangle.normal()
    assert_almost_equal(normal.z, Float32(-7.071067458312085e-8), atol=1e-14)
    assert_true(normal.z < 0)


def test_three_factor_minimum_keeps_a_representable_constant() raises:
    # The smallest nonzero Float32 coordinate cube is 2**-447. It is a
    # normal Float64 value, and dividing by cross length recovers 2**-149.
    var tiny = bitcast[DType.float32](UInt32(1))
    var plane = Plane.from_coplanar_points(
        Vector3(0, 0, tiny),
        Vector3(tiny, 0, tiny),
        Vector3(0, tiny, tiny),
    )
    assert_true(plane.normal == Vector3(0, 0, 1))
    assert_equal(plane.constant, -tiny)
    var huge = bitcast[DType.float32](UInt32(0x7F7FFFFF))
    var beyond = Plane.from_coplanar_points(
        Vector3(huge, huge, 0),
        Vector3(huge, 0, huge),
        Vector3(0, huge, huge),
    )
    assert_equal(beyond.constant, inf[DType.float32]())
    assert_almost_equal(
        beyond.normal.x, Float32(-0.5773502691896258), atol=1e-6
    )


def test_ordinary_cross_does_not_hide_subnormal_point_products() raises:
    # The cross is 2**-62 and its square is normal. Its product with this
    # height is subnormal, so the raw dot loses about 29% before division.
    var edge = Float32(4.656612873077393e-10)
    var height = Float32(1e-26)
    var plane = Plane.from_coplanar_points(
        Vector3(0, 0, height),
        Vector3(edge, 0, height),
        Vector3(0, edge, height),
    )
    assert_true(plane.normal == Vector3(0, 0, 1))
    assert_equal(plane.constant, -height)


def test_original_zero_coordinate_keeps_axis_planes_through_the_origin() raises:
    for axis in range(3):
        var a = Vector3(1, 2, 3)
        a.set_component(axis, 0)
        var b = a
        b.set_component((axis + 1) % 3, b.get_component((axis + 1) % 3) + 1)
        var c = a
        c.set_component((axis + 2) % 3, c.get_component((axis + 2) % 3) + 1)
        var plane = Plane.from_coplanar_points(a, b, c)
        assert_equal(plane.normal.get_component(axis), Float32(1))
        assert_equal(plane.constant, Float32(0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
