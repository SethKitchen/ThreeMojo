# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Independent inverse oracles at extreme scale and cancellation boundaries."""

from math.matrix2 import Matrix2
from math.matrix3 import Matrix3
from math.matrix4 import Matrix4, scaling
from std.math import inf, isfinite, nan
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)


def _near[
    dtype: DType
](
    actual: SIMD[dtype, 1], expected: SIMD[dtype, 1], atol: Float64 = 1e-6
) raises:
    """Refuse nonfinite observations before comparing numerical error."""
    assert_true(isfinite(actual))
    assert_almost_equal(actual, expected, atol=atol)


def test_matrix2_inverse_survives_representable_extreme_scales() raises:
    for s in [Float32(1e-38), Float32(1e-30), Float32(1e30)]:
        var matrix = Matrix2(2 * s, s, s, 2 * s)
        var inverse = matrix.inverse()
        assert_true(isfinite(inverse.m00) and isfinite(inverse.m01))
        _near(Float64(inverse.m00) * Float64(s), Float64(2) / 3, atol=1e-6)
        _near(Float64(inverse.m01) * Float64(s), Float64(-1) / 3, atol=1e-6)
        assert_equal(inverse.m10, inverse.m01)
        assert_equal(inverse.m11, inverse.m00)
        var product = matrix * inverse
        _near(product.m00, Float32(1), atol=1e-6)
        _near(product.m01, Float32(0), atol=1e-6)


def example3(s: Float32) -> Matrix3:
    var matrix = Matrix3()
    matrix.set(2 * s, s, 0, 0, 3 * s, s, s, 0, 4 * s)
    return matrix^


def test_matrix3_inverse_matches_an_independent_adjugate() raises:
    # det([[2,1,0],[0,3,1],[1,0,4]]) = 25; these are its inverse columns.
    var expected: Array[Float64, 9] = [12, 1, -3, -4, 8, 1, 1, -2, 6]
    for s in [Float32(1e-38), Float32(1e-30), Float32(1), Float32(1e30)]:
        var matrix = example3(s)
        var inverse = matrix
        inverse.invert()
        for index in range(9):
            assert_true(isfinite(inverse.elements[index]))
            _near(
                Float64(inverse.elements[index]) * Float64(s),
                expected[index] / 25,
                atol=1e-6,
            )
        var product = matrix * inverse
        for column in range(3):
            for row in range(3):
                _near(
                    product.elements[column * 3 + row],
                    Float32(1) if column == row else Float32(0),
                    atol=1e-6,
                )


def test_matrix4_inverse_preserves_affine_translation_and_scale() raises:
    for s in [Float32(1e-30), Float32(1e30)]:
        var matrix = scaling(s, -s, 2 * s)
        matrix.elements[12] = 3
        matrix.elements[13] = -4
        matrix.elements[14] = 5
        var inverse = matrix
        inverse.invert()
        assert_true(inverse.is_finite())
        _near(Float64(inverse.elements[0]) * Float64(s), 1, atol=1e-6)
        _near(Float64(inverse.elements[5]) * Float64(s), -1, atol=1e-6)
        _near(Float64(inverse.elements[10]) * Float64(s), 0.5, atol=1e-6)
        _near(Float64(inverse.elements[12]) * Float64(s), -3, atol=1e-6)
        _near(Float64(inverse.elements[13]) * Float64(s), -4, atol=1e-6)
        _near(Float64(inverse.elements[14]) * Float64(s), -2.5, atol=1e-6)
        assert_equal(inverse.elements[15], Float32(1))
        matrix.multiply(inverse)
        for column in range(4):
            for row in range(4):
                _near(
                    matrix.elements[column * 4 + row],
                    Float32(1) if column == row else Float32(0),
                    atol=1e-6,
                )


def test_inverse_recovers_a_cancelled_determinant_without_thresholding_it_away() raises:
    # The exact determinant is 1e7, despite products around 1e14.
    var small = Matrix2(1e7, 1e7, 1e7, 10000001)
    var inverse2 = small.inverse()
    _near(inverse2.m00, Float32(1.0000001), atol=1e-6)
    _near(inverse2.m01, Float32(-1), atol=1e-6)
    var middle = Matrix3()
    middle.set(1e7, 1e7, 0, 1e7, 10000001, 0, 0, 0, 1)
    middle.invert()
    _near(middle.elements[0], Float32(1.0000001), atol=1e-6)
    _near(middle.elements[3], Float32(-1), atol=1e-6)
    var large = Matrix4()
    large.set(1e7, 1e7, 0, 0, 1e7, 10000001, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
    large.invert()
    _near(large.elements[0], Float32(1.0000001), atol=1e-6)
    _near(large.elements[4], Float32(-1), atol=1e-6)


def test_wide_inverse_pivots_and_preserves_singular_contracts() raises:
    for s in [Float32(1e-30), Float32(1e30)]:
        var small = Matrix2(0, s, s, 0).inverse()
        _near(Float64(small.m01) * Float64(s), 1, atol=1e-6)
        var middle = Matrix3()
        middle.set(0, s, 0, s, 0, 0, 0, 0, s)
        middle.invert()
        _near(Float64(middle.elements[1]) * Float64(s), 1, atol=1e-6)
        var large = Matrix4()
        large.set(0, s, 0, 0, s, 0, 0, 0, 0, 0, s, 0, 0, 0, 0, 1)
        large.invert()
        _near(Float64(large.elements[1]) * Float64(s), 1, atol=1e-6)
        with assert_raises(contains="singular"):
            _ = Matrix2.scaling(s, 0).inverse()
        middle.set(s, 0, 0, 0, s, 0, 0, 0, 0)
        middle.invert()
        for index in range(9):
            assert_equal(middle.elements[index], Float32(0))
        large = scaling(s, 0, s)
        large.invert()
        for index in range(16):
            assert_equal(large.elements[index], Float32(0))
        with assert_raises(contains="normal matrix"):
            _ = scaling(s, 0, s).normal_matrix()


def test_normal_matrices_match_the_inverse_transpose_at_extreme_scale() raises:
    # Row-major inverse columns become inverse-transpose columns.
    var expected: Array[Float64, 9] = [12, -4, 1, 1, 8, -2, -3, 1, 6]
    for s in [Float32(1e-38), Float32(1e-30), Float32(1e30)]:
        var matrix = example3(s).as_matrix4()
        matrix.elements[12] = 123
        var normal3 = Matrix3.normal_matrix(matrix)
        var normal4 = matrix.normal_matrix()
        for column in range(3):
            for row in range(3):
                var at = column * 3 + row
                assert_true(isfinite(normal3.elements[at]))
                _near(
                    Float64(normal3.elements[at]) * Float64(s),
                    expected[at] / 25,
                    atol=1e-6,
                )
                assert_equal(
                    normal4.elements[column * 4 + row], normal3.elements[at]
                )
        assert_equal(normal4.elements[12], Float32(0))
        assert_equal(normal4.elements[15], Float32(1))


def test_normal_matrix_refuses_nonfinite_or_unrepresentable_linear_inverse() raises:
    for value in [nan[DType.float32](), inf[DType.float32]()]:
        for at in [0, 1, 2, 4, 5, 6, 8, 9, 10]:
            var matrix = Matrix4()
            matrix.elements[at] = value
            with assert_raises(contains="finite"):
                _ = Matrix3.normal_matrix(matrix)
            with assert_raises(contains="finite"):
                _ = matrix.normal_matrix()
    var tiny = bitcast[DType.float32](UInt32(1))
    with assert_raises(contains="fit"):
        _ = scaling(tiny, tiny, tiny).normal_matrix()
    var matrix = Matrix4()
    matrix.elements[12] = nan[DType.float32]()
    assert_true(matrix.normal_matrix() == Matrix4())


def test_diagonal_inverse_sweeps_normal_float32_exponents() raises:
    # Exact powers of two provide an independent reciprocal oracle.
    for exponent in range(-126, 128):
        var value = bitcast[DType.float32](UInt32(exponent + 127) << 23)
        var expected = Float32(Float64(1) / Float64(value))
        var small = Matrix2.scaling(value, value).inverse()
        assert_equal(small.m00, expected)
        assert_equal(small.m11, expected)
        assert_equal(small.m01, Float32(0))
        var middle = Matrix3()
        middle.set(value, 0, 0, 0, value, 0, 0, 0, value)
        middle.invert()
        for at in [0, 4, 8]:
            assert_equal(middle.elements[at], expected)
        var large = scaling(value, value, value)
        large.invert()
        for at in [0, 5, 10]:
            assert_equal(large.elements[at], expected)
        assert_equal(large.elements[15], Float32(1))


def test_dense_matrix4_inverse_matches_hadamard_oracle() raises:
    # H is symmetric and H * H = 4I, independently of matrix inversion.
    var signs: Array[Float32, 16] = [
        1,
        1,
        1,
        1,
        1,
        -1,
        1,
        -1,
        1,
        1,
        -1,
        -1,
        1,
        -1,
        -1,
        1,
    ]
    for scale in [
        Float32(1e-38),
        Float32(1e-30),
        Float32(1),
        Float32(1e30),
        Float32(1e38),
    ]:
        var matrix = Matrix4()
        for at in range(16):
            matrix.elements[at] = signs[at] * scale
        var inverse = matrix
        inverse.invert()
        for at in range(16):
            _near(
                Float64(inverse.elements[at]) * Float64(scale),
                Float64(signs[at]) / 4,
            )
        for row in range(4):
            for column in range(4):
                var value = Float64(0)
                for at in range(4):
                    value += Float64(matrix.elements[at * 4 + row]) * Float64(
                        inverse.elements[column * 4 + at]
                    )
                _near(value, Float64(1) if row == column else Float64(0))


def test_rotated_nonuniform_inverse_and_normal_matrix() raises:
    # A quarter turn about z followed by nonuniform, mirrored scaling.
    for scale in [Float32(1e-30), Float32(1), Float32(1e30)]:
        var matrix = Matrix4()
        matrix.set(
            0,
            -2 * scale,
            0,
            3,
            scale,
            0,
            0,
            -4,
            0,
            0,
            -4 * scale,
            5,
            0,
            0,
            0,
            1,
        )
        var expected: Array[Float64, 16] = [
            0,
            -0.5,
            0,
            0,
            1,
            0,
            0,
            0,
            0,
            0,
            -0.25,
            0,
            4,
            1.5,
            1.25,
            0,
        ]
        var inverse = matrix
        inverse.invert()
        for at in range(15):
            _near(Float64(inverse.elements[at]) * Float64(scale), expected[at])
        assert_equal(inverse.elements[15], Float32(1))
        var normal = matrix.normal_matrix()
        for row in range(3):
            for column in range(3):
                _near(
                    Float64(normal.elements[column * 4 + row]) * Float64(scale),
                    expected[row * 4 + column],
                )
        var product = matrix * inverse
        for row in range(4):
            for column in range(4):
                _near(
                    product.elements[column * 4 + row],
                    Float32(1) if row == column else Float32(0),
                )


def test_unrepresentable_inverse_keeps_nonzero_axes_distinct_from_singular() raises:
    var tiny = bitcast[DType.float32](UInt32(1))
    var small = Matrix2.scaling(tiny, -tiny).inverse()
    assert_equal(small.m00, inf[DType.float32]())
    assert_equal(small.m11, -inf[DType.float32]())
    assert_equal(small.m01, Float32(0))
    var middle = Matrix3()
    middle.set(tiny, 0, 0, 0, -tiny, 0, 0, 0, tiny)
    middle.invert()
    assert_equal(middle.elements[0], inf[DType.float32]())
    assert_equal(middle.elements[4], -inf[DType.float32]())
    var large = scaling(tiny, -tiny, tiny)
    large.invert()
    assert_equal(large.elements[0], inf[DType.float32]())
    assert_equal(large.elements[5], -inf[DType.float32]())
    assert_equal(large.elements[15], Float32(1))


def test_duplicate_large_rows_stay_singular_after_pivot_elimination() raises:
    # Exact equal rows are singular. Rounded cofactors alone produce -420
    # on the pinned toolchain, so the zero-pivot guard must also reject it.
    var matrix = Matrix3()
    matrix.set(
        2944800,
        9896335,
        8200300,
        2547355,
        8155219,
        7814359,
        2944800,
        9896335,
        8200300,
    )
    matrix.invert()
    for at in range(9):
        assert_equal(matrix.elements[at], Float32(0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
