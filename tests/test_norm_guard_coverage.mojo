# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""IEEE fallback and exponent-boundary checks for the norm primitives."""

from math.norm import (
    normalized2,
    normalized3,
    normalized_difference2,
    normalized_difference3,
    reciprocal_normalized3,
    normalized_cross3,
)
from math.scaled_products import (
    _Scaled,
    _two_sum,
    _at_exponent,
    _grow_sum,
    _estimate,
)
from math.exact_predicates import _Interval, _outward, _plane_above
from math.vector3 import Vector3, _ordinary_transform, _wide_linear_transform
from math.triangle_normal import normal_or_zero, polygon_normal
from std.math import inf, nan, isnan, isfinite, ldexp, sqrt
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_true,
    assert_false,
    assert_almost_equal,
)


def same_ieee(actual: Float64, expected: Float64) raises:
    if isnan(expected):
        assert_true(isnan(actual))
    else:
        assert_equal(actual, expected)


def test_each_nonfinite_reciprocal_component_retains_ieee_policy() raises:
    for axis in range(3):
        for bad in [inf[DType.float64](), nan[DType.float64]()]:
            var p = [Float64(0), Float64(0), Float64(0)]
            p[axis] = bad
            var actual = reciprocal_normalized3(p[0], p[1], p[2])
            for lane in range(3):
                if isnan(bad) or lane == axis:
                    assert_true(isnan([actual[0], actual[1], actual[2]][lane]))
                else:
                    assert_equal(
                        [actual[0], actual[1], actual[2]][lane], Float64(0)
                    )
    var finite = reciprocal_normalized3(Float64(0), Float64(3), Float64(4))
    assert_almost_equal(finite[1], Float64(0.6), atol=1e-15)
    assert_almost_equal(finite[2], Float64(0.8), atol=1e-15)


def test_difference_endpoints_independently_select_ieee_and_scaled_paths() raises:
    for axis in range(2):
        var a = [Float64(0), Float64(0)]
        var b = [Float64(0), Float64(0)]
        a[axis] = -1e308
        b[axis] = 1e308
        var direction = normalized_difference2(a[0], a[1], b[0], b[1])
        assert_equal([direction[0], direction[1]][axis], Float64(1))
        assert_equal([direction[0], direction[1]][1 - axis], Float64(0))
    for coordinate in range(4):
        for bad in [inf[DType.float64](), nan[DType.float64]()]:
            var p = [Float64(0), Float64(0), Float64(3), Float64(4)]
            p[coordinate] = bad
            var expected = normalized2(p[2] - p[0], p[3] - p[1])
            var actual = normalized_difference2(p[0], p[1], p[2], p[3])
            same_ieee(actual[0], expected[0])
            same_ieee(actual[1], expected[1])
    var ordinary = normalized_difference3(
        Float64(0), Float64(0), Float64(0), Float64(2), Float64(3), Float64(6)
    )
    assert_almost_equal(ordinary[0], Float64(2) / 7, atol=1e-15)
    for axis in range(3):
        var a = [Float64(0), Float64(0), Float64(0)]
        var b = [Float64(0), Float64(0), Float64(0)]
        a[axis] = -1e308
        b[axis] = 1e308
        var direction = normalized_difference3(
            a[0], a[1], a[2], b[0], b[1], b[2]
        )
        for lane in range(3):
            assert_equal(
                [direction[0], direction[1], direction[2]][lane],
                Float64(lane == axis),
            )
    for coordinate in range(6):
        for bad in [inf[DType.float64](), nan[DType.float64]()]:
            var p = [
                Float64(0),
                Float64(0),
                Float64(0),
                Float64(2),
                Float64(3),
                Float64(6),
            ]
            p[coordinate] = bad
            var expected = normalized3(p[3] - p[0], p[4] - p[1], p[5] - p[2])
            var actual = normalized_difference3(
                p[0], p[1], p[2], p[3], p[4], p[5]
            )
            for lane in range(3):
                same_ieee(
                    [actual[0], actual[1], actual[2]][lane],
                    [expected[0], expected[1], expected[2]][lane],
                )


def test_normalized_cross_detects_cancellation_and_small_products() raises:
    var cross = normalized_cross3(1, 1, 0, 1, 1 + ldexp(Float64(1), -40), 0)
    assert_equal(cross[0], Float64(0))
    assert_equal(cross[1], Float64(0))
    assert_equal(cross[2], Float64(1))
    # One product is subnormal, while another component keeps the cross ordinary.
    cross = normalized_cross3(1, 1e-160, 0, 0, 1, 1e-160)
    assert_equal(cross[0], Float64(1e-320))
    assert_equal(cross[1], Float64(-1e-160))
    assert_equal(cross[2], Float64(1))
    var ieee = normalized_cross3(0, inf[DType.float64](), 0, 1, 0, 0)
    assert_true(isnan(ieee[0]))


def test_scaled_zero_overflow_and_nonfinite_accumulation() raises:
    var sum = _two_sum(
        _Scaled[DType.float64](0.75, 5), _Scaled[DType.float64](0, -900)
    )
    assert_equal(sum[0].fraction, Float64(0.75))
    assert_equal(sum[0].exponent, 5)
    assert_equal(sum[1].fraction, Float64(0))
    assert_equal(
        _at_exponent(_Scaled[DType.float64](0.5, 1024), 0),
        ldexp(Float64(1), 1023),
    )
    assert_equal(
        _at_exponent(_Scaled[DType.float64](-0.5, 1025), 0),
        -inf[DType.float64](),
    )
    assert_equal(
        _at_exponent(_Scaled[DType.float32](0.5, 128), 0),
        ldexp(Float32(1), 127),
    )
    assert_equal(
        _at_exponent(_Scaled[DType.float32](0.5, 129), 0), inf[DType.float32]()
    )
    var expansion = List[_Scaled[DType.float64]]()
    _grow_sum(expansion, _Scaled[DType.float64](inf[DType.float64](), 0))
    _grow_sum(expansion, _Scaled[DType.float64](0.75, 5))
    assert_equal(len(expansion), 1)
    assert_equal(_estimate(expansion).fraction, inf[DType.float64]())


def test_interval_overflow_in_later_corners_is_conservative() raises:
    var first = _Interval(1, 1e308) * _Interval(2, 3)
    assert_equal(first.low, -inf[DType.float64]())
    assert_equal(first.high, inf[DType.float64]())
    var last = _Interval(1, 1e308) * _Interval(0.5, 2)
    assert_equal(last.low, -inf[DType.float64]())
    assert_equal(last.high, inf[DType.float64]())
    var outward = _outward(1, inf[DType.float64]())
    assert_equal(outward.low, -inf[DType.float64]())
    assert_equal(outward.high, inf[DType.float64]())


def test_vector_product_guards_and_ieee_transform_components() raises:
    var projected = Vector3(2, 3, 4)
    projected.project_on_vector(Vector3(0, 1, 0))
    assert_true(projected == Vector3(0, 3, 0))
    var tiny = Vector3(1e-30, 0, 0)
    tiny.project_on_vector(Vector3(1, 0, 0))
    assert_true(tiny == Vector3(1e-30, 0, 0))
    for column in range(3):
        var e = Array[Float32, 9](fill=0)
        var source = Vector3(1, 1, 1)
        e[column * 3] = 1e-30
        if column == 0:
            source.x = 1e-20
        elif column == 1:
            source.y = 1e-20
        else:
            source.z = 1e-20
        e[((column + 1) % 3) * 3 + 1] = 1
        assert_false(_ordinary_transform(source, Vector3(0, 1, 0), e))
    for coordinate in range(6):
        var e = Array[Float32, 9](fill=1)
        var source = Vector3(1, 2, 3)
        if coordinate < 3:
            e[coordinate * 3] = inf[DType.float32]()
        elif coordinate == 3:
            source.x = inf[DType.float32]()
        elif coordinate == 4:
            source.y = inf[DType.float32]()
        else:
            source.z = inf[DType.float32]()
        var out = _wide_linear_transform(source, e)
        assert_equal(out[0], inf[DType.float64]())
        assert_equal(out[3], Float64(0))


def test_triangle_nonfinite_and_empty_polygon_policies() raises:
    var bad = Vector3(inf[DType.float32](), 0, 0)
    var normal = normal_or_zero(Vector3(0, 0, 0), bad, Vector3(0, 1, 0))
    assert_true(isnan(normal.y))
    var empty = List[Vector3]()
    assert_true(polygon_normal(empty) == Vector3(0, 0, 0))
    var points: List[Vector3] = [Vector3(0, 0, 0), bad, Vector3(0, 1, 0)]
    normal = polygon_normal(points)
    assert_true(isnan(normal.y))


def test_polygon_newell_cancellation_checks_each_leading_component() raises:
    # Integer differences give the exact cross (9904, -10848, 7020).
    # Translation makes Float32 Newell lose 176 in x and 148 in z.
    # Cycling x/y/z moves an error after the exact y component.
    for swap in [False, True]:
        var points: List[Vector3] = [
            Vector3(-4, 33554348, 33554504),
            Vector3(-46, 33554232, 33554384),
            Vector3(29, 33554272, 33554340),
        ]
        if swap:
            for index in range(3):
                var p = points[index]
                points[index] = Vector3(p.y, p.z, p.x)
        var result = polygon_normal(points)
        var norm = sqrt(
            Float64(9904) * 9904 + Float64(10848) * 10848 + Float64(7020) * 7020
        )
        var expected = Vector3(
            Float32(9904 / norm), Float32(-10848 / norm), Float32(7020 / norm)
        )
        if swap:
            expected = Vector3(expected.y, expected.z, expected.x)
        assert_almost_equal(result.x, expected.x, atol=1e-7)
        assert_almost_equal(result.y, expected.y, atol=1e-7)
        assert_almost_equal(result.z, expected.z, atol=1e-7)


def test_projection_handles_dot_overflow_at_the_finite_square_boundary() raises:
    # Adjacent binary32 values straddle the rounded Cauchy bound. A fused
    # dot can overflow even though each rounded squared length is finite.
    var words: List[UInt32] = [
        0x5F13CD37,
        0x5F13CD3B,
        0x5F13CD3C,
        0x5F13CD37,
        0x5F13CD3C,
        0x5F13CD3B,
        0x5F13CD36,
        0x5F13CD3C,
        0x5F13CD3C,
        0x5F13CD36,
        0x5F13CD3D,
        0x5F13CD3B,
    ]
    for sample in range(2):
        var offset = sample * 6
        var a = Vector3(
            bitcast[DType.float32](words[offset]),
            bitcast[DType.float32](words[offset + 1]),
            bitcast[DType.float32](words[offset + 2]),
        )
        var b = Vector3(
            bitcast[DType.float32](words[offset + 3]),
            bitcast[DType.float32](words[offset + 4]),
            bitcast[DType.float32](words[offset + 5]),
        )
        var numerator = (
            Float64(a.x) * Float64(b.x)
            + Float64(a.y) * Float64(b.y)
            + Float64(a.z) * Float64(b.z)
        )
        var denominator = (
            Float64(b.x) * Float64(b.x)
            + Float64(b.y) * Float64(b.y)
            + Float64(b.z) * Float64(b.z)
        )
        var scale = numerator / denominator
        a.project_on_vector(b)
        assert_true(isfinite(a.x) and isfinite(a.y) and isfinite(a.z))
        assert_almost_equal(
            Float64(a.x), Float64(b.x) * scale, rtol=3e-7, atol=0
        )
        assert_almost_equal(
            Float64(a.y), Float64(b.y) * scale, rtol=3e-7, atol=0
        )
        assert_almost_equal(
            Float64(a.z), Float64(b.z) * scale, rtol=3e-7, atol=0
        )


def test_interval_margin_certifies_tiny_positive_distance() raises:
    comptime P = SIMD[DType.float64, 4]
    var a = P(0)
    var b = P(1, 0, 0, 0)
    var c = P(0, 1, 0, 0)
    var query = P(0, 0, 1e-50, 0)
    assert_true(_plane_above(a, b, c, query, 1e-60))
    assert_false(_plane_above(a, b, c, query, 1e-40))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
