# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Exact singularity and independent inverse oracles after cancellation."""

from math.matrix2 import Matrix2
from math.matrix3 import Matrix3
from math.matrix4 import Matrix4
from math.matrix_determinant import _determinant_f32
from math.matrix_inverse import _inverse_wide
from std.math import inf, isfinite, isnan, nan
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


def rank_two() -> Matrix3:
    # u*u^T + v*v^T, with u=(485,-1854,380), v=(790,-1352,-236).
    var matrix = Matrix3()
    matrix.set(
        859325,
        -1967270,
        -2140,
        -1967270,
        5265220,
        -385448,
        -2140,
        -385448,
        200096,
    )
    return matrix^


def assert_zero3(matrix: Matrix3) raises:
    var inverse = matrix
    inverse.invert()
    for value in inverse.elements:
        assert_equal(value, Float32(0))
    with assert_raises(contains="normal matrix"):
        _ = Matrix3.normal_matrix(matrix.as_matrix4())
    with assert_raises(contains="normal matrix"):
        _ = matrix.as_matrix4().normal_matrix()


def test_exact_rank_two_row_and_column_permutations() raises:
    var base = rank_two()
    var permutations = [
        [0, 1, 2],
        [0, 2, 1],
        [1, 0, 2],
        [1, 2, 0],
        [2, 0, 1],
        [2, 1, 0],
    ]
    for rows in permutations:
        for columns in permutations:
            var matrix = Matrix3()
            for row in range(3):
                for column in range(3):
                    matrix.elements[3 * column + row] = base.elements[
                        3 * columns[column] + rows[row]
                    ]
            assert_zero3(matrix)


def test_exact_rank_two_scales_and_four_dimensional_embeddings() raises:
    for exponent in [27, 127, 227]:
        var scale = bitcast[DType.float32](UInt32(exponent) << 23)
        for sign in [Float32(-1), Float32(1)]:
            var matrix = rank_two()
            for at in range(9):
                matrix.elements[at] *= sign * scale
            assert_zero3(matrix)
            var embedding = matrix.as_matrix4()
            # Move the independent axis through all four positions.
            for independent in range(4):
                var large = Matrix4()
                for row in range(4):
                    for column in range(4):
                        var source_row = 3 if row == independent else (
                            independent if row == 3 else row
                        )
                        var source_column = 3 if column == independent else (
                            independent if column == 3 else column
                        )
                        large.elements[4 * column + row] = embedding.elements[
                            4 * source_column + source_row
                        ]
                large.invert()
                for value in large.elements:
                    assert_equal(value, Float32(0))


def test_collinear_and_repeated_rows_are_exactly_singular() raises:
    for factors in [[1001, 2011, 3001], [8000001, 7000003, 6000001]]:
        var matrix = Matrix3()
        for column in range(3):
            for row in range(3):
                # Powers of two preserve the stored rank-one relation.
                matrix.elements[column * 3 + row] = Float32(
                    factors[column]
                ) * Float32(1 << row)
        assert_zero3(matrix)
    var repeated = Matrix3()
    repeated.set(
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
    assert_zero3(repeated)
    with assert_raises(contains="singular"):
        _ = Matrix2(8000001, 7000003, 16000002, 14000006).inverse()


def test_rank_one_cancellation_inside_fast_path_cofactors() raises:
    # Every entry is an exact integer in the ordinary fast-path range.
    # On the pinned optimized compiler, the first matrix's rounded det and
    # old cofactor-magnitude bound are both 358735400. The old screen thus
    # accepts a rank-one matrix despite every exact cofactor being zero.
    for left in [[101, 103, 107], [521, 661, 307], [1231, 1171, 1093]]:
        for right in [[1001, 2011, 3001], [853, 719, 661], [1193, 1559, 1031]]:
            var matrix = Matrix3()
            for row in range(3):
                for column in range(3):
                    matrix.elements[3 * column + row] = Float32(
                        left[row] * right[column]
                    )
            assert_zero3(matrix)
            var embedding = matrix.as_matrix4()
            embedding.invert()
            for value in embedding.elements:
                assert_equal(value, Float32(0))


def test_dense_rank_three_four_by_four_is_singular() raises:
    # Three independent integer vectors give a dense rank-three Gram matrix.
    var vectors = [
        [485, -1854, 380, 812],
        [790, -1352, -236, 511],
        [-634, 421, 821, 119],
    ]
    var base = Matrix4()
    for row in range(4):
        for column in range(4):
            var value = 0
            for vector in vectors:
                value += vector[row] * vector[column]
            base.elements[column * 4 + row] = Float32(value)
    for exponent in [27, 127, 227]:
        var scale = bitcast[DType.float32](UInt32(exponent) << 23)
        for shift in range(4):
            var matrix = Matrix4()
            for row in range(4):
                for column in range(4):
                    matrix.elements[column * 4 + row] = (
                        base.elements[((column + shift) % 4) * 4 + (3 - row)]
                        * scale
                    )
            assert_equal(_determinant_f32[4](matrix.elements), Float64(0))
            matrix.invert()
            for value in matrix.elements:
                assert_equal(value, Float32(0))


def test_exact_nonzero_three_by_three_determinant_and_inverse() raises:
    var n = Float32(8000000)
    var base = Matrix3()
    base.set(n, n + 1, n - 1, n + 2, n + 3, n + 1, n + 1, n + 2, n + 1)
    # Integer row subtraction gives determinant -2. These exact half-integer
    # inverse entries are derived from its integer adjugate, not inversion.
    var expected: Array[Float64, 9] = [
        -4000000.5,
        4000000.5,
        -0.5,
        4000001.5,
        -4000000.5,
        -0.5,
        -2,
        1,
        1,
    ]
    var permutations = [
        [0, 1, 2],
        [0, 2, 1],
        [1, 0, 2],
        [1, 2, 0],
        [2, 0, 1],
        [2, 1, 0],
    ]
    for rows in permutations:
        for columns in permutations:
            var matrix = Matrix3()
            for row in range(3):
                for column in range(3):
                    matrix.elements[3 * column + row] = base.elements[
                        3 * columns[column] + rows[row]
                    ]
            assert_equal(abs(_determinant_f32[3](matrix.elements)), Float64(2))
            var normal = Matrix3.normal_matrix(matrix.as_matrix4())
            matrix.invert()
            for row in range(3):
                for column in range(3):
                    var wanted = Float32(
                        expected[3 * rows[column] + columns[row]]
                    )
                    assert_equal(matrix.elements[3 * column + row], wanted)
                    assert_equal(normal.elements[3 * row + column], wanted)


def test_dense_four_by_four_tiny_determinant_keeps_orientation_and_inverse() raises:
    var n = Float32(8000000)
    var base = Matrix4()
    base.set(
        n,
        n + 1,
        n - 1,
        n + 2,
        n + 2,
        n + 3,
        n + 1,
        n + 4,
        n + 1,
        n + 2,
        n + 1,
        n + 3,
        n,
        n + 1,
        n - 1,
        n + 3,
    )
    # Subtract the first row from the fourth: its only entry is a final one.
    # This reduces the determinant to the same exact -2 three-by-three case.
    var expected: Array[Float64, 16] = [
        -4000001.5,
        4000002.5,
        -0.5,
        -1,
        4000001.5,
        -4000000.5,
        -0.5,
        0,
        -2,
        1,
        1,
        0,
        1,
        -2,
        0,
        1,
    ]
    for exponent in [27, 127, 227]:
        var scale = bitcast[DType.float32](UInt32(exponent) << 23)
        for shift in range(4):
            var matrix = Matrix4()
            for row in range(4):
                for column in range(4):
                    matrix.elements[4 * column + row] = (
                        base.elements[4 * ((column + shift) % 4) + row] * scale
                    )
            var sign = Float64(-1) if shift % 2 == 0 else Float64(1)
            assert_equal(
                _determinant_f32[4](matrix.elements),
                sign * 2 * Float64(scale) ** 4,
            )
            matrix.invert()
            for row in range(4):
                for column in range(4):
                    assert_equal(
                        matrix.elements[4 * column + row],
                        Float32(
                            expected[4 * column + (row + shift) % 4]
                            / Float64(scale)
                        ),
                    )


def test_determinant_range_and_matrix2_small_nonzero_determinant() raises:
    for value in [
        bitcast[DType.float32](UInt32(1)),
        Float32(1),
        bitcast[DType.float32](UInt32(0x7F7FFFFF)),
    ]:
        var matrix = Matrix4()
        for at in [0, 5, 10, 15]:
            matrix.elements[at] = value
        var determinant = _determinant_f32[4](matrix.elements)
        assert_true(isfinite(determinant) and determinant > 0)
        matrix.elements[0] = -value
        assert_true(_determinant_f32[4](matrix.elements) < 0)
    var small = Matrix2(8000000, 8000001, 8000001, 8000002).inverse()
    assert_equal(small.m00, Float32(-8000002))
    assert_equal(small.m01, Float32(8000001))
    assert_equal(small.m10, Float32(8000001))
    assert_equal(small.m11, Float32(-8000000))


def test_nearby_invertible_gram_matrix_uses_its_nonzero_determinant() raises:
    var matrix = rank_two()
    for at in [0, 4, 8]:
        matrix.elements[at] += 1
    # Exact integer adjugate of G+I, independent of the implementation.
    var cofactors: Array[Float64, 9] = [
        904984765733,
        394469683910,
        769547859900,
        394469683910,
        171943975022,
        335435445848,
        769547859900,
        335435445848,
        654390048146,
    ]
    var determinant = Float64(1731312464258)
    assert_equal(_determinant_f32[3](matrix.elements), determinant)
    matrix.invert()
    for at in range(9):
        assert_equal(matrix.elements[at], Float32(cofactors[at] / determinant))


def test_well_conditioned_neighbor_has_an_independent_inverse() raises:
    # Adding trace(G)*I makes the rank-two Gram matrix well conditioned:
    # every eigenvalue lies between trace(G) and twice trace(G).
    var matrix = rank_two()
    for at in [0, 4, 8]:
        matrix.elements[at] += 6324641
    var cofactors: Array[Float64, 9] = [
        75472224730853,
        12836744216710,
        783082589500,
        12836744216710,
        46873484187342,
        2773255284568,
        783082589500,
        2773255284568,
        79391016115826,
    ]
    var determinant = Float64(516934878818858491298)
    matrix.invert()
    for at in range(9):
        var expected = Float32(cofactors[at] / determinant)
        assert_true(isfinite(matrix.elements[at]))
        assert_true(
            abs(Float64(matrix.elements[at]) / Float64(expected) - 1) < 2e-6
        )


def test_nonfinite_inverse_keeps_legacy_propagation() raises:
    # Finite exact arithmetic must not consume nonfinite entries. Generic
    # inversion retains its propagation; checked normal matrices refuse it.
    for bad in [
        nan[DType.float32](),
        inf[DType.float32](),
        -inf[DType.float32](),
    ]:
        for at in range(9):
            var matrix = Matrix3()
            matrix.elements[at] = bad
            matrix.invert()
            for index in range(9):
                if isnan(bad) or at == 3 or at == 6 or at == 7:
                    assert_true(isnan(matrix.elements[index]))
                elif at == 0 or at == 4 or at == 8:
                    var expected = Float32(1) if (
                        index == 0 or index == 4 or index == 8
                    ) and index != at else Float32(0)
                    assert_equal(matrix.elements[index], expected)
                else:
                    assert_equal(matrix.elements[index], Float32(0))
        var entries: Array[Float32, 4] = [0, 0, 0, bad]
        var inverse = _inverse_wide[2](entries)
        assert_true(not inverse[0])
        var small = Matrix2(bad, 0, 0, 1).inverse()
        if isnan(bad):
            assert_true(isnan(small.m00))
        else:
            assert_equal(small.m00, Float32(0))
            assert_equal(small.m11, Float32(1))
        var swapped: Array[Float32, 9] = [0, 1, 0, 1, 0, 0, 0, 0, bad]
        _ = _inverse_wide[3](swapped)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
