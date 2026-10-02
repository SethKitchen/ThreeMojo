# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exact singularity, orientation and Float32 determinant exponent range."""

from math.matrix3 import Matrix3
from math.matrix_determinant import _determinant3_f32
from std.math import isfinite
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_true


def test_nonsymmetric_determinants() raises:
    var matrix = Matrix3()
    matrix.set(3, 1, 4, 1, 5, 9, 2, 6, 5)
    assert_equal(_determinant3_f32(matrix.elements), Float64(-90))
    matrix.set(1, 3, 4, 5, 1, 9, 6, 2, 5)
    assert_equal(_determinant3_f32(matrix.elements), Float64(90))
    var zeros = Array[Float32, 9](fill=0)
    assert_equal(_determinant3_f32(zeros), Float64(0))


def test_exact_rank_two_across_exponents() raises:
    # Every integer entry is exactly representable in Float32. These are
    # Gram matrices of two independent integer vectors, hence rank two.
    for vectors in [
        [-134, 65, 198, 87, -95, 18],
        [485, -1854, 380, 790, -1352, -236],
    ]:
        for exponent in [1, 27, 87, 127, 167, 207, 227]:
            var scale = bitcast[DType.float32](UInt32(exponent) << 23)
            var matrix = Matrix3()
            for i in range(3):
                for j in range(3):
                    matrix.elements[3 * j + i] = (
                        Float32(
                            vectors[i] * vectors[j]
                            + vectors[i + 3] * vectors[j + 3]
                        )
                        * scale
                    )
            assert_equal(_determinant3_f32(matrix.elements), Float64(0))


def test_cancellation_keeps_a_small_exact_determinant() raises:
    # Subtract row one from the other rows: (2,2,2) and (1,1,2).
    # The exact determinant is -2, despite products around 5e20.
    var n = Float32(8000000)
    var matrix = Matrix3()
    matrix.set(n, n + 1, n - 1, n + 2, n + 3, n + 1, n + 1, n + 2, n + 1)
    for exponent in [27, 127, 227]:
        var scale = bitcast[DType.float32](UInt32(exponent) << 23)
        var scaled = matrix
        for i in range(9):
            scaled.elements[i] *= scale
        assert_equal(
            _determinant3_f32(scaled.elements), -2 * Float64(scale) ** 3
        )


def test_nonzero_determinants_across_float32_range() raises:
    var values = [
        bitcast[DType.float32](UInt32(1)),
        Float32(1e-30),
        Float32(1),
        Float32(1e30),
        bitcast[DType.float32](UInt32(0x7F7FFFFF)),
    ]
    for value in values:
        var matrix = Matrix3()
        matrix.elements[0] = value
        matrix.elements[4] = value
        matrix.elements[8] = value
        var determinant = _determinant3_f32(matrix.elements)
        var expected = Float64(value) * Float64(value) * Float64(value)
        assert_true(isfinite(determinant))
        assert_true(determinant > 0)
        assert_true(abs(determinant / expected - 1) < 2e-16)
        matrix.elements[8] = -value
        assert_true(_determinant3_f32(matrix.elements) < 0)


def test_cancellation_keeps_all_significant_expansion_components() raises:
    # A cofactor of a dense invertible Matrix4. The final expansion
    # component is 7995392; the whole exact determinant is 8000003.
    var matrix = Matrix3()
    matrix.set(
        8000003,
        8000001,
        8000004,
        8000002,
        8000001,
        8000003,
        8000001,
        7999999,
        8000003,
    )
    assert_equal(_determinant3_f32(matrix.elements), Float64(8000003))


def test_symmetric_positive_definite_determinant_keeps_magnitude() raises:
    # 8000000*J + I has eigenvalues 24000001, 1, 1.
    var matrix = Matrix3()
    matrix.set(
        8000001,
        8000000,
        8000000,
        8000000,
        8000001,
        8000000,
        8000000,
        8000000,
        8000001,
    )
    assert_equal(_determinant3_f32(matrix.elements), Float64(24000001))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
