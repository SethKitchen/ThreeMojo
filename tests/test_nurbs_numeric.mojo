# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""NURBS numerical boundaries with exact integer and analytic references."""

from geometries.parametric import parametric
from math.nurbs import (
    NURBSCurve,
    NURBSSurface,
    NURBSVolume,
    Point4,
    _coefficient_float,
    _coefficient_overflows,
    _exact_binomial,
    basis_functions,
    basis_function_derivatives,
    bspline_derivatives,
    find_span,
    k_over_i,
    rational_curve_derivatives,
    surface_point,
    volume_point,
)
from math.vector4 import Vector4
from std.math import inf, nan
from std.testing import TestSuite, assert_equal, assert_raises
from tests.test_nurbs import near, near3


def test_binomial_edges_symmetry_and_exact_integer_oracles() raises:
    for k in range(171, 173):
        assert_equal(k_over_i(k, 0), 1.0)
        assert_equal(k_over_i(k, 1), Float64(k))
        assert_equal(k_over_i(k, k - 1), Float64(k))
        assert_equal(k_over_i(k, k), 1.0)
        for i in range(k + 1):
            assert_equal(k_over_i(k, i), k_over_i(k, k - i))
    # Rounded only once from Python math.comb's exact arbitrary-size integer.
    near(k_over_i(171, 85), 1.8183348319970882e50, 2e-14)
    near(k_over_i(172, 86), 3.6366696639941765e50, 2e-14)
    near(k_over_i(1000, 500), 2.7028824094543655e299, 2e-14)
    near(k_over_i(1029, 514), 1.429820686498904e308, 2e-14)
    assert_equal(k_over_i(1030, 515), inf[DType.float64]())
    # The overflow exit makes an otherwise impractical count bounded by Float64.
    assert_equal(k_over_i(Int.MAX, Int.MAX // 2), inf[DType.float64]())
    assert_equal(k_over_i(Int.MAX, 1), Float64(Int.MAX))


def test_polynomial_padding_does_not_multiply_infinity_by_zero() raises:
    var constant = bspline_derivatives(0, [0, 1], [Point4(2, 3, 4, 2)], 0.5, 3)
    assert_equal(constant[0], Point4(4, 6, 8, 2))
    for index in range(1, len(constant)):
        assert_equal(constant[index], Point4(0))
    var homogeneous = List[Point4](length=1032, fill=Point4(0))
    homogeneous[0] = Point4(2, 3, 4, 1)
    var derivatives = rational_curve_derivatives(homogeneous)
    near3(derivatives[0], [2, 3, 4], 0)
    for k in range(1, len(derivatives)):
        near3(derivatives[k], [0, 0, 0], 0)


def test_curve_refuses_undefined_denominators_and_projected_overflow() raises:
    var zero = NURBSCurve(0, [0, 1], [Vector4(2, 3, 4, 0)])
    with assert_raises(contains="denominator"):
        _ = zero.point3(0.5)
    with assert_raises(contains="denominator"):
        _ = zero.tangent3(0.5)
    var cancellation = NURBSCurve(
        1, [0, 0, 1, 1], [Vector4(2, 0, 0, 1), Vector4(4, 0, 0, -1)]
    )
    with assert_raises(contains="denominator"):
        _ = cancellation.point3(0.5)
    with assert_raises(contains="denominator"):
        _ = cancellation.tangent3(0.5)
    var values: List[Float64] = [inf[DType.float64](), nan[DType.float64]()]
    for weight in values:
        zero.control_points[0][3] = weight
        with assert_raises(contains="denominator"):
            _ = zero.point3(0.5)
        with assert_raises(contains="denominator"):
            _ = zero.tangent3(0.5)
    near3(cancellation.point3(0.25), [1, 0, 0], 0)
    near3(cancellation.tangent3(0.25), [-1, 0, 0], 0)
    near3(cancellation.tangent3(0.75), [-1, 0, 0], 0)
    cancellation.control_points[0][0] = 1e308
    cancellation.control_points[1][0] = -1e308
    with assert_raises(contains="projected result"):
        _ = cancellation.point3(0.49999999999999994)
    with assert_raises(contains="projected result"):
        _ = cancellation.tangent3(0.49999999999999994)
    var steep = NURBSCurve(
        1, [0, 0, 1e-308, 1e-308], [Vector4(0, 0, 0, 1), Vector4(4, 0, 0, 1)]
    )
    near3(steep.point3(0.5), [2, 0, 0], 1e-15)
    # Its derivative magnitude exceeds Float64, but its unit direction is finite.
    near3(steep.tangent3(0.5), [1, 0, 0], 0)


def test_finite_zero_negative_and_tiny_weights_remain_valid() raises:
    var curve = NURBSCurve(
        1, [0, 0, 1, 1], [Vector4(9, 8, 7, 0), Vector4(2, 3, 4, -2)]
    )
    near3(curve.point3(0.5), [2, 3, 4], 0)
    near3(curve.tangent3(0.5), [0, 0, 0], 0)
    var tiny = NURBSCurve(0, [0, 1], [Vector4(2, 3, 4, 1)])
    tiny.control_points[0][3] = 1e-320
    near3(tiny.point3(0.5), [2, 3, 4], 0)
    near3(tiny.tangent3(0.5), [0, 0, 0], 0)
    var surface = NURBSSurface(
        1,
        0,
        [0, 0, 1, 1],
        [0, 1],
        [[Vector4(9, 8, 7, 0)], [Vector4(2, 3, 4, -2)]],
    )
    near3(surface.point64(0.5, 0.5), [2, 3, 4], 0)
    var volume = NURBSVolume(
        1,
        0,
        0,
        [0, 0, 1, 1],
        [0, 1],
        [0, 1],
        [[[Vector4(9, 8, 7, 0)]], [[Vector4(2, 3, 4, -2)]]],
    )
    near3(volume.point64(0.5, 0.5, 0.5), [2, 3, 4], 0)
    surface.control_points[1][0][3] = 1e-320
    volume.control_points[1][0][0][3] = 1e-320
    near3(surface.point64(1, 0.5), [2, 3, 4], 0)
    near3(volume.point64(1, 0.5, 0.5), [2, 3, 4], 0)


def test_surface_and_volume_check_projection_before_narrowing() raises:
    var surface = NURBSSurface(0, 0, [0, 1], [0, 1], [[Vector4(2, 3, 4, 0)]])
    var volume = NURBSVolume(
        0, 0, 0, [0, 1], [0, 1], [0, 1], [[[Vector4(2, 3, 4, 0)]]]
    )
    var values: List[Float64] = [0, inf[DType.float64](), nan[DType.float64]()]
    for weight in values:
        surface.control_points[0][0][3] = weight
        volume.control_points[0][0][0][3] = weight
        with assert_raises(contains="denominator"):
            _ = surface.point64(0.5, 0.5)
        with assert_raises(contains="denominator"):
            _ = surface.point(0.5, 0.5)
        with assert_raises(contains="denominator"):
            _ = parametric(surface, 1, 1)
        with assert_raises(contains="denominator"):
            _ = volume.point64(0.5, 0.5, 0.5)
        with assert_raises(contains="denominator"):
            _ = volume.point(0.5, 0.5, 0.5)
    surface.control_points[0][0][3] = 1
    volume.control_points[0][0][0][3] = 1
    for axis in range(3):
        surface.control_points[0][0][axis] = 1e300
        volume.control_points[0][0][0][axis] = -1e300
        assert_equal(surface.point64(0.5, 0.5)[axis], 1e300)
        assert_equal(volume.point64(0.5, 0.5, 0.5)[axis], -1e300)
        with assert_raises(contains="Float32"):
            _ = surface.point(0.5, 0.5)
        with assert_raises(contains="Float32"):
            _ = volume.point(0.5, 0.5, 0.5)
        surface.control_points[0][0][axis] = inf[DType.float64]()
        volume.control_points[0][0][0][axis] = nan[DType.float64]()
        with assert_raises(contains="projected result"):
            _ = surface.point64(0.5, 0.5)
        with assert_raises(contains="projected result"):
            _ = volume.point64(0.5, 0.5, 0.5)
        surface.control_points[0][0][axis] = 0
        volume.control_points[0][0][0][axis] = 0


def test_all_parameters_are_checked_in_the_original_precision() raises:
    var curve = NURBSCurve(0, [0, 1], [Vector4(2, 3, 4, 1)])
    var surface = NURBSSurface(0, 0, [0, 1], [0, 1], [[Vector4(2, 3, 4, 1)]])
    var volume = NURBSVolume(
        0, 0, 0, [0, 1], [0, 1], [0, 1], [[[Vector4(2, 3, 4, 1)]]]
    )
    var values: List[Float64] = [
        -5e-324,
        1.0000000000000002,
        1.0000000001,
        inf[DType.float64](),
        -inf[DType.float64](),
        nan[DType.float64](),
    ]
    for t in values:
        with assert_raises(contains="parameter"):
            _ = curve.point3(t)
        with assert_raises(contains="parameter"):
            _ = curve.tangent3(t)
        with assert_raises(contains="parameter"):
            _ = surface.point64(t, 0.5)
        with assert_raises(contains="parameter"):
            _ = surface.point64(0.5, t)
        with assert_raises(contains="parameter"):
            _ = volume.point64(t, 0.5, 0.5)
        with assert_raises(contains="parameter"):
            _ = volume.point64(0.5, t, 0.5)
        with assert_raises(contains="parameter"):
            _ = volume.point64(0.5, 0.5, t)


def test_extreme_line_points_basis_and_derivatives_are_analytic() raises:
    var knots: List[Float64] = [-1e308, -1e308, 1e308, 1e308]
    var curve = NURBSCurve(
        1, knots, [Vector4(0, 0, 0, 1), Vector4(1, 2, -2, 1)]
    )
    var values: List[Float64] = [0, 0.25, 0.5, 0.75, 1]
    for t in values:
        near3(curve.point3(t), [t, 2 * t, -2 * t], 1e-15)
        near3(curve.tangent3(t), [1.0 / 3, 2.0 / 3, -2.0 / 3], 1e-15)
    assert_equal(curve.knots[0], -1e308)
    assert_equal(curve.knots[3], 1e308)
    var basis = basis_function_derivatives(1, 0, 1, 1, knots)
    assert_equal(basis[0][0], 0.5)
    assert_equal(basis[0][1], 0.5)
    # Multiplication by 1e308 tests subnormal derivatives at a normal scale.
    near(basis[1][0] * 1e308, -0.5, 1e-15)
    near(basis[1][1] * 1e308, 0.5, 1e-15)
    var weighted = bspline_derivatives(1, knots, curve.control_points, 0, 1)
    near(weighted[1][0] * 1e308, 0.5, 1e-15)
    var reverse = NURBSCurve(
        1, knots, [Vector4(0, 0, 0, 1), Vector4(1, 0, 0, 1)], 3, 0
    )
    near3(reverse.point3(0.25), [0.75, 0, 0], 1e-15)
    near3(reverse.tangent3(0.25), [1, 0, 0], 0)
    var selected = NURBSCurve(
        1, knots, [Vector4(0, 0, 0, 1), Vector4(1, 0, 0, 1)], 0, 0
    )
    near3(selected.point3(0.75), [0, 0, 0], 0)


def test_repeated_extreme_knots_preserve_the_quadratic() raises:
    var knots: List[Float64] = [
        -1e308,
        -1e308,
        -1e308,
        0,
        0,
        1e308,
        1e308,
        1e308,
    ]
    var curve = NURBSCurve(
        2,
        knots,
        [
            Vector4(0, 0, 0, 1),
            Vector4(1, 0, 0, 1),
            Vector4(2, 0, 0, 1),
            Vector4(3, 0, 0, 1),
            Vector4(4, 0, 0, 1),
        ],
    )
    var values: List[Float64] = [0, 0.25, 0.5, 0.75, 1]
    for t in values:
        near3(curve.point3(t), [4 * t, 0, 0], 1e-15)
        near3(curve.tangent3(t), [1, 0, 0], 1e-15)
    var selected = NURBSCurve(
        2,
        knots,
        [
            Vector4(0, 0, 0, 1),
            Vector4(1, 0, 0, 1),
            Vector4(2, 0, 0, 1),
            Vector4(3, 0, 0, 1),
            Vector4(4, 0, 0, 1),
        ],
        3,
        7,
    )
    near3(selected.point3(0.5), [3, 0, 0], 1e-15)
    var narrow: List[Float64] = [0, 0, 1e-308, 1e-308]
    var basis = basis_functions(1, 5e-309, 1, narrow)
    near(basis[0], 0.5, 1e-15)
    near(basis[1], 0.5, 1e-15)


def test_tensor_surfaces_and_volumes_share_scale_safe_basis() raises:
    var knots: List[Float64] = [-1e308, -1e308, 1e308, 1e308]
    var surface = NURBSSurface(
        1,
        1,
        knots,
        knots,
        [
            [Vector4(0, 0, 0, 1), Vector4(0, 1, 0, 1)],
            [Vector4(1, 0, 0, 1), Vector4(1, 1, 0, 1)],
        ],
    )
    var volume = NURBSVolume(
        1,
        1,
        1,
        knots,
        knots,
        knots,
        [
            [
                [Vector4(0, 0, 0, 1), Vector4(0, 0, 1, 1)],
                [Vector4(0, 1, 0, 1), Vector4(0, 1, 1, 1)],
            ],
            [
                [Vector4(1, 0, 0, 1), Vector4(1, 0, 1, 1)],
                [Vector4(1, 1, 0, 1), Vector4(1, 1, 1, 1)],
            ],
        ],
    )
    var values: List[Float64] = [0, 0.25, 0.5, 0.75, 1]
    for t in values:
        near3(surface.point64(t, t), [t, t, 0], 1e-15)
        near3(volume.point64(t, t, t), [t, t, t], 1e-15)
    near3(surface.point64(0.25, 0.75), [0.25, 0.75, 0], 1e-15)
    near3(volume.point64(0.25, 0.5, 0.75), [0.25, 0.5, 0.75], 1e-15)
    near3(
        surface_point(1, 1, knots, knots, surface.control_points, 0, 0),
        [0.5, 0.5, 0],
        0,
    )
    near3(
        volume_point(
            1, 1, 1, knots, knots, knots, volume.control_points, 0, 0, 0
        ),
        [0.5, 0.5, 0.5],
        0,
    )


def test_low_level_extrapolation_and_collapsed_knot_terms() raises:
    # The utility functions also allow extrapolation outside the knot range.
    # Here only the numerator difference overflows; the quotient is exactly 2.
    var knots: List[Float64] = [0, 0, 1e308, 1e308]
    var basis = basis_functions(1, -1e308, 1, knots)
    assert_equal(basis[0], 2.0)
    assert_equal(basis[1], -1.0)
    var derivatives = basis_function_derivatives(1, -1e308, 1, 1, knots)
    assert_equal(derivatives[0][0], 2.0)
    assert_equal(derivatives[0][1], -1.0)
    # An explicitly selected collapsed span has no contributing basis term.
    var repeated: List[Float64] = [0, 0, 0, 1, 1]
    basis = basis_functions(1, 0, 1, repeated)
    assert_equal(basis[0], 0.0)
    assert_equal(basis[1], 0.0)
    derivatives = basis_function_derivatives(1, 0, 1, 1, repeated)
    for k in range(2):
        for j in range(2):
            assert_equal(derivatives[k][j], 0.0)


def test_extreme_quadratic_keeps_curvature_and_direction() raises:
    var knots: List[Float64] = [-1e308, -1e308, -1e308, 1e308, 1e308, 1e308]
    var curve = NURBSCurve(
        2,
        knots,
        [Vector4(0, 0, 0, 1), Vector4(1, 2, 0, 1), Vector4(2, 0, 0, 1)],
    )
    # The analytic Bernstein polynomial is (2t, 4t(1-t), 0).
    var parameters: List[Float64] = [0, 0.25, 0.5, 0.75, 1]
    for t in parameters:
        near3(curve.point3(t), [2 * t, 4 * t * (1 - t), 0], 1e-15)
    near3(curve.tangent3(0.5), [1, 0, 0], 1e-15)
    var derivatives = basis_function_derivatives(2, 0, 2, 2, knots)
    near(derivatives[1][0] * 1e308, -0.5, 1e-15)
    near(derivatives[1][1] * 1e308, 0, 1e-15)
    near(derivatives[1][2] * 1e308, 0.5, 1e-15)
    # The second derivatives are below the smallest Float64 magnitude.
    for j in range(3):
        assert_equal(derivatives[2][j], 0.0)


def test_unit_tangents_survive_unrepresentable_derivative_magnitudes() raises:
    var knots: List[Float64] = [-1e308, -1e308, 1e308, 1e308]
    var tiny = NURBSCurve(
        1, knots, [Vector4(0, 0, 0, 1), Vector4(1e-30, 0, 0, 1)]
    )
    near3(tiny.tangent3(0), [1, 0, 0], 0)
    near3(tiny.tangent3(0.5), [1, 0, 0], 0)
    near3(tiny.tangent3(1), [1, 0, 0], 0)
    var negative = NURBSCurve(
        1, knots, [Vector4(0, 0, 0, -1), Vector4(1e-30, 0, 0, -2)]
    )
    near3(negative.tangent3(0.5), [1, 0, 0], 0)
    var steep = NURBSCurve(
        1, [0, 0, 1e-308, 1e-308], [Vector4(0, 0, 0, 1), Vector4(4, 0, 0, 1)]
    )
    near3(steep.tangent3(0.5), [1, 0, 0], 0)


def test_tangent_direction_is_independent_of_control_and_knot_scale() raises:
    var sizes: List[Float32] = [1e-30, 1, 1e30]
    for size in sizes:
        var points: List[Vector4] = [
            Vector4(0, 0, 0, 1),
            Vector4(size, 2 * size, -2 * size, 1),
        ]
        var wide = NURBSCurve(1, [-1e308, -1e308, 1e308, 1e308], points)
        var narrow = NURBSCurve(1, [0, 0, 1e-308, 1e-308], points)
        near3(wide.tangent3(0.5), [1.0 / 3, 2.0 / 3, -2.0 / 3], 1e-15)
        near3(narrow.tangent3(0.5), [1.0 / 3, 2.0 / 3, -2.0 / 3], 1e-15)
    var huge = NURBSCurve(
        1,
        [-1e308, -1e308, 1e308, 1e308],
        [Vector4(0, 0, 0, 1), Vector4(1, 0, 0, 1)],
    )
    huge.control_points[0][0] = -1e308
    huge.control_points[1][0] = 1e308
    near3(huge.point3(0.5), [0, 0, 0], 0)
    near3(huge.tangent3(0.5), [1, 0, 0], 0)
    var stopped = NURBSCurve(
        1, [0, 0, 1, 1], [Vector4(0, 0, 0, 1), Vector4(0, 0, 0, 2)]
    )
    near3(stopped.tangent3(0.5), [0, 0, 0], 0)


def test_binomial_exact_neighbors_straddle_float64_overflow() raises:
    # Exact math.comb comparisons with int(sys.float_info.max) determine the
    # boundary. Some genuinely excessive neighbors still round to MAX under
    # ordinary nearest-even conversion, so rounding alone is not the policy.
    var boundary = 1007841023926742612
    assert_equal(k_over_i(boundary - 3, 18), 1.7976931348623155e308)
    for delta in range(-2, 1):
        assert_equal(k_over_i(boundary + delta, 18), 1.7976931348623157e308)
        assert_equal(
            k_over_i(boundary + delta, boundary + delta - 18),
            1.7976931348623157e308,
        )
    for delta in range(1, 6):
        assert_equal(k_over_i(boundary + delta, 18), inf[DType.float64]())
        assert_equal(
            k_over_i(boundary + delta, boundary + delta - 18),
            inf[DType.float64](),
        )
    assert_equal(_exact_binomial(0, 0), 1.0)
    assert_equal(_exact_binomial(5, 2), 10.0)
    assert_equal(_exact_binomial(1000, 500), 2.7028824094543655e299)


def integer_limbs(value: UInt64) -> List[UInt64]:
    """Return a small exact integer in the fallback's base-2**32 format."""
    var digits = List[UInt64](length=34, fill=0)
    digits[0] = value & 0xFFFFFFFF
    digits[1] = value >> 32
    return digits^


def test_exact_integer_rounding_and_maximum_boundary() raises:
    assert_equal(_coefficient_float(integer_limbs(0)), 0.0)
    assert_equal(_coefficient_float(integer_limbs(1)), 1.0)
    assert_equal(
        _coefficient_float(integer_limbs(9007199254740993)), 9007199254740992.0
    )
    assert_equal(
        _coefficient_float(integer_limbs(9007199254740995)), 9007199254740996.0
    )
    assert_equal(
        _coefficient_float(integer_limbs(18014398509481987)),
        18014398509481988.0,
    )
    var maximum = List[UInt64](length=34, fill=0)
    maximum[31] = 0xFFFFFFFF
    maximum[30] = 0xFFFFF800
    assert_equal(_coefficient_float(maximum), 1.7976931348623157e308)
    assert_equal(_coefficient_overflows(maximum), False)
    maximum[0] = 1
    assert_equal(_coefficient_float(maximum), inf[DType.float64]())
    maximum[0] = 0
    maximum[30] += 1
    assert_equal(_coefficient_float(maximum), inf[DType.float64]())
    maximum[30] -= 2
    assert_equal(_coefficient_overflows(maximum), False)
    maximum[32] = 1
    assert_equal(_coefficient_overflows(maximum), True)
    maximum[32] = 0
    maximum[33] = 1
    assert_equal(_coefficient_overflows(maximum), True)


def test_basis_derivative_factors_do_not_overflow_an_integer() raises:
    # For clamped [0,1] knots the first basis is (1-u)**degree.
    # The exact highest derivative is (-1)**degree * math.factorial(degree).
    var expected: List[Float64] = [
        -51090942171709440000.0,
        1124000727777607680000.0,
    ]
    for degree in range(21, 23):
        var knots = List[Float64](length=degree + 1, fill=0.0)
        for _ in range(degree + 1):
            knots.append(1.0)
        var derivatives = basis_function_derivatives(
            degree, 0, degree, degree, knots
        )
        near(derivatives[degree][0], expected[degree - 21], 1e-15)
        assert_equal(derivatives[1][0], -Float64(degree))
        assert_equal(derivatives[1][1], Float64(degree))
    var degree = 171
    var knots = List[Float64](length=degree + 1, fill=0.0)
    for _ in range(degree + 1):
        knots.append(1.0)
    var derivatives = basis_function_derivatives(
        degree, 0, degree, degree, knots
    )
    assert_equal(derivatives[degree][0], -inf[DType.float64]())
    # The last basis is u**171, whose 170th derivative is zero at u=0.
    assert_equal(derivatives[170][171], 0.0)


def test_exact_overflow_thresholds_at_several_orders() raises:
    # Each top value is the largest n with math.comb(n, order) <= the exact
    # integer value of Float64.MAX, found independently by integer binary search.
    var orders: List[Int] = [19, 32, 64, 128, 256, 514]
    var tops: List[Int] = [
        132784659504925514,
        54933874179,
        1617071,
        12437,
        1658,
        1029,
    ]
    var finite: List[Float64] = [
        1.7976931348623155e308,
        1.7976931344428857e308,
        1.7976425439722969e308,
        1.7891224838390814e308,
        1.7949866177796316e308,
        1.429820686498904e308,
    ]
    for index in range(len(orders)):
        assert_equal(k_over_i(tops[index], orders[index]), finite[index])
        assert_equal(
            k_over_i(tops[index] + 1, orders[index]), inf[DType.float64]()
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
