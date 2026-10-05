# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.numerics`: vectors, dense and sparse matrices, the
conjugate-gradient and skyline solvers and the eigensolver.

The references are closed forms: the eigenvalues of the second-difference
matrix, 2 - 2 cos(k pi / (n + 1)), and solutions checked by multiplying
back.
"""

from std.math import cos, inf, nan, pi, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from extensions.numerics.dense import (
    DenseMatrix,
    cholesky,
    solve,
    solve_lower,
    solve_lower_transposed,
    solve_tridiagonal,
    symmetric_eigen,
)
from extensions.numerics.eigen import (
    Modes,
    _check_sturm_pivot,
    _checked_schur_value,
    _independent_mass_norm,
    _pivoted_inertia,
    _verify_sturm,
    count_eigenvalues_below,
    lowest_modes,
)
from extensions.numerics.iterative import (
    BUDGET_EXHAUSTED,
    CONVERGED,
    SolveStatus,
    conjugate_gradient,
)
from extensions.numerics.skyline import (
    SkylineFactor,
    identity_order,
    profile,
    reverse_cuthill_mckee,
)
from extensions.numerics.sparse import CsrMatrix, SparseBuilder
from extensions.numerics.vector import (
    axpy,
    check_finite,
    check_same_size,
    dot,
    norm,
    zeros,
)


def _second_difference(n: Int) raises -> CsrMatrix:
    """The matrix with 2 on the diagonal and -1 beside it."""
    var b = SparseBuilder(n)
    for i in range(n):
        b.add(i, i, 2)
        if i + 1 < n:
            b.add(i, i + 1, -1)
            b.add(i + 1, i, -1)
    return b.build()


def _identity_sparse(n: Int) raises -> CsrMatrix:
    var b = SparseBuilder(n)
    for i in range(n):
        b.add(i, i, 1)
    return b.build()


def _scrambled_path(n: Int) raises -> CsrMatrix:
    """A path graph numbered so that neighbors are far apart."""
    var b = SparseBuilder(n)
    var label = List[Int](capacity=n)
    for i in range(n):
        label.append((i * 7) % n)
    for i in range(n):
        b.add(label[i], label[i], 4)
        if i + 1 < n:
            b.add(label[i], label[i + 1], -1)
            b.add(label[i + 1], label[i], -1)
    return b.build()


def _check_modes(k: CsrMatrix, m: CsrMatrix, modes: Modes) raises:
    """Check every residual and every entry of the mass Gram matrix."""
    for c in range(len(modes.values)):
        var kphi = k.multiply(modes.vectors[c])
        var mphi = m.multiply(modes.vectors[c])
        for i in range(k.size):
            assert_almost_equal(kphi[i], modes.values[c] * mphi[i], atol=1e-8)
        for other in range(len(modes.values)):
            assert_almost_equal(
                dot(modes.vectors[other], mphi),
                1.0 if other == c else 0.0,
                atol=1e-10,
            )


# --- vectors -----------------------------------------------------------------


def test_vector_operations() raises:
    var a: List[Float64] = [3, 4]
    var b: List[Float64] = [1, 2]
    assert_equal(dot(a, b), 11)
    assert_equal(norm(a), 5)
    assert_equal(norm(zeros(3)), 0)
    axpy(2, b, a)
    assert_equal(a[0], 5)
    assert_equal(a[1], 8)
    # The scaled norm survives entries whose squares overflow.
    var huge: List[Float64] = [3e200, 4e200]
    assert_almost_equal(norm(huge), 5e200, atol=1e186)


def test_vector_checks_refuse_bad_input() raises:
    with assert_raises(contains="zero or more"):
        _ = zeros(-1)
    var a: List[Float64] = [1, 2]
    var c: List[Float64] = [1]
    with assert_raises(contains="same length"):
        check_same_size(a, c)
    with assert_raises(contains="same length"):
        _ = dot(a, c)
    with assert_raises(contains="same length"):
        axpy(1, a, c)
    var bad: List[Float64] = [1, nan[DType.float64]()]
    with assert_raises(contains="finite"):
        check_finite(bad)
    check_finite(a)


# --- dense -------------------------------------------------------------------


def test_dense_products_and_transpose() raises:
    var a = DenseMatrix(2, 3)
    a.set(0, 0, 1)
    a.set(0, 1, 2)
    a.set(0, 2, 3)
    a.set(1, 0, 4)
    a.set(1, 1, 5)
    a.add(1, 2, 6)
    var t = a.transposed()
    assert_equal(t.rows, 3)
    assert_equal(t.get(2, 1), 6)
    var p = a.multiply(t)
    assert_equal(p.get(0, 0), 14)
    assert_equal(p.get(0, 1), 32)
    assert_equal(p.get(1, 1), 77)
    var x: List[Float64] = [1, 0, -1]
    var y = a.multiply_vector(x)
    assert_equal(y[0], -2)
    assert_equal(y[1], -2)
    # Aᵀ I A, with A as the transformation.
    var tat = a.triple_product(DenseMatrix.identity(2))
    assert_equal(tat.rows, 3)
    assert_equal(tat.get(0, 0), 17)
    with assert_raises(contains="inner dimensions"):
        _ = a.multiply(a)
    with assert_raises(contains="column count"):
        _ = a.multiply_vector(y)
    with assert_raises(contains="zero or more"):
        _ = DenseMatrix(-1, 2)
    with assert_raises(contains="zero or more"):
        _ = DenseMatrix(2, -1)


def test_gaussian_elimination_pivots() raises:
    # A zero leading entry needs a row swap.
    var a = DenseMatrix(3, 3)
    a.set(0, 1, 2)
    a.set(0, 2, 1)
    a.set(1, 0, 1)
    a.set(1, 1, 1)
    a.set(1, 2, 1)
    a.set(2, 0, 2)
    a.set(2, 1, 1)
    a.set(2, 2, 3)
    var b: List[Float64] = [5, 6, 13]
    var x = solve(a, b)
    var back = a.multiply_vector(x)
    for i in range(3):
        assert_almost_equal(back[i], b[i], atol=1e-12)
    # A row that is already eliminated skips its update.
    var diag = DenseMatrix.identity(2)
    var e: List[Float64] = [3, 4]
    var z = solve(diag, e)
    assert_equal(z[1], 4)


def test_gaussian_elimination_refuses() raises:
    var singular = DenseMatrix(2, 2)
    singular.set(0, 0, 1)
    singular.set(0, 1, 2)
    singular.set(1, 0, 2)
    singular.set(1, 1, 4)
    var b: List[Float64] = [1, 2]
    with assert_raises(contains="singular"):
        _ = solve(singular, b)
    with assert_raises(contains="square"):
        _ = solve(DenseMatrix(2, 3), b)
    var c: List[Float64] = [1]
    with assert_raises(contains="one entry per row"):
        _ = solve(DenseMatrix.identity(2), c)


def test_cholesky_and_triangular_solves() raises:
    var a = DenseMatrix(2, 2)
    a.set(0, 0, 4)
    a.set(0, 1, 2)
    a.set(1, 0, 2)
    a.set(1, 1, 3)
    var l = cholesky(a)
    assert_equal(l.get(0, 0), 2)
    assert_equal(l.get(1, 0), 1)
    assert_almost_equal(l.get(1, 1), sqrt(2.0), atol=1e-15)
    var b: List[Float64] = [2, 1]
    var y = solve_lower(l, b)
    var x = solve_lower_transposed(l, y)
    var back = a.multiply_vector(x)
    assert_almost_equal(back[0], 2, atol=1e-14)
    assert_almost_equal(back[1], 1, atol=1e-14)
    var c: List[Float64] = [1]
    with assert_raises(contains="matching sizes"):
        _ = solve_lower(l, c)
    with assert_raises(contains="matching sizes"):
        _ = solve_lower_transposed(l, c)
    with assert_raises(contains="matching sizes"):
        _ = solve_lower(DenseMatrix(2, 1), b)
    with assert_raises(contains="matching sizes"):
        _ = solve_lower_transposed(DenseMatrix(2, 1), b)


def test_cholesky_refuses() raises:
    var a = DenseMatrix(2, 2)
    a.set(0, 0, 1)
    a.set(0, 1, 2)
    a.set(1, 0, 2)
    a.set(1, 1, 1)
    with assert_raises(contains="positive definite"):
        _ = cholesky(a)
    var bad = DenseMatrix.identity(1)
    bad.set(0, 0, inf[DType.float64]())
    with assert_raises(contains="positive definite"):
        _ = cholesky(bad)
    with assert_raises(contains="square"):
        _ = cholesky(DenseMatrix(1, 2))


def test_symmetric_eigen_of_the_second_difference() raises:
    var n = 6
    var a = DenseMatrix(n, n)
    for i in range(n):
        a.set(i, i, 2)
        if i + 1 < n:
            a.set(i, i + 1, -1)
            a.set(i + 1, i, -1)
    var pairs = symmetric_eigen(a)
    for k in range(n):
        var expected = 2 - 2 * cos(Float64(k + 1) * pi / Float64(n + 1))
        assert_almost_equal(pairs.values[k], expected, atol=1e-12)
    # A v = lambda v for the lowest pair.
    var v = zeros(n)
    for i in range(n):
        v[i] = pairs.vectors.get(i, 0)
    var av = a.multiply_vector(v)
    for i in range(n):
        assert_almost_equal(av[i], pairs.values[0] * v[i], atol=1e-12)
    # A diagonal matrix is already converged and only sorts.
    var d = DenseMatrix(2, 2)
    d.set(0, 0, 3)
    d.set(1, 1, 1)
    var sorted = symmetric_eigen(d)
    assert_equal(sorted.values[0], 1)
    assert_equal(sorted.vectors.get(1, 0), 1)


def test_symmetric_eigen_preserves_extreme_finite_scales() raises:
    var scales: List[Float64] = [1e200, 1e-200, 1e-310]
    for scale in scales:
        var a = DenseMatrix(2, 2)
        a.set(0, 0, 2 * scale)
        a.set(1, 1, 2 * scale)
        a.set(0, 1, scale)
        a.set(1, 0, scale)
        var pairs = symmetric_eigen(a)
        assert_almost_equal(pairs.values[0] / scale, 1, atol=1e-12)
        assert_almost_equal(pairs.values[1] / scale, 3, atol=1e-12)
        for c in range(2):
            var norm_squared = Float64(0)
            for i in range(2):
                var left = Float64(0)
                for j in range(2):
                    left += (a.get(i, j) / scale) * pairs.vectors.get(j, c)
                assert_almost_equal(
                    left,
                    (pairs.values[c] / scale) * pairs.vectors.get(i, c),
                    atol=1e-12,
                )
                norm_squared += pairs.vectors.get(i, c) ** 2
            assert_almost_equal(norm_squared, 1, atol=1e-14)
        assert_almost_equal(
            pairs.vectors.get(0, 0) * pairs.vectors.get(0, 1)
            + pairs.vectors.get(1, 0) * pairs.vectors.get(1, 1),
            0,
            atol=1e-14,
        )
    # Both the diagonal difference and twice the off-diagonal used to
    # overflow, although these eigenvalues are representable.
    var extreme = DenseMatrix(2, 2)
    extreme.set(0, 0, -9e307)
    extreme.set(1, 1, 9e307)
    extreme.set(0, 1, 9e307)
    extreme.set(1, 0, 9e307)
    var pairs = symmetric_eigen(extreme)
    assert_almost_equal(pairs.values[0] / 9e307, -sqrt(2.0), atol=1e-14)
    assert_almost_equal(pairs.values[1] / 9e307, sqrt(2.0), atol=1e-14)
    var zero = symmetric_eigen(DenseMatrix(2, 2))
    assert_equal(zero.values[0], 0)
    assert_equal(zero.values[1], 0)
    var overflow = DenseMatrix(2, 2)
    for i in range(4):
        overflow.data[i] = 1e308
    with assert_raises(contains="finite"):
        _ = symmetric_eigen(overflow)


def test_symmetric_eigen_refuses() raises:
    with assert_raises(contains="square"):
        _ = symmetric_eigen(DenseMatrix(1, 2))
    var bad = DenseMatrix.identity(2)
    bad.set(0, 1, nan[DType.float64]())
    with assert_raises(contains="finite"):
        _ = symmetric_eigen(bad)
    # A huge nonsymmetric pair cannot be rotated away.
    var skew = DenseMatrix(2, 2)
    skew.set(0, 1, 1)
    skew.set(1, 0, -1)
    with assert_raises(contains="converge"):
        _ = symmetric_eigen(skew)


def test_thomas_algorithm() raises:
    var lower: List[Float64] = [0, -1, -1]
    var diagonal: List[Float64] = [2, 2, 2]
    var upper: List[Float64] = [-1, -1, 0]
    var rhs: List[Float64] = [1, 0, 1]
    var x = solve_tridiagonal(lower, diagonal, upper, rhs)
    for i in range(3):
        assert_almost_equal(x[i], 1, atol=1e-15)
    var short: List[Float64] = [1]
    with assert_raises(contains="one length"):
        _ = solve_tridiagonal(short, diagonal, upper, rhs)
    var zero: List[Float64] = [0, 2, 2]
    with assert_raises(contains="pivot"):
        _ = solve_tridiagonal(lower, zero, upper, rhs)
    var nan_diag: List[Float64] = [nan[DType.float64](), 2, 2]
    with assert_raises(contains="pivot"):
        _ = solve_tridiagonal(lower, nan_diag, upper, rhs)


# --- sparse ------------------------------------------------------------------


def test_sparse_builder_sums_duplicates_and_sorts() raises:
    var b = SparseBuilder(3)
    b.add(2, 2, 1)
    b.add(0, 2, 5)
    b.add(0, 0, 1)
    b.add(0, 2, 1)
    b.add(1, 1, 0)
    b.add(2, 0, 6)
    var a = b.build()
    assert_equal(a.nonzeros(), 4)
    assert_equal(a.get(0, 2), 6)
    assert_equal(a.get(1, 1), 0)
    assert_equal(a.get(2, 1), 0)
    assert_equal(a.columns[0], 0)
    assert_equal(a.columns[1], 2)
    assert_true(a.is_symmetric(1e-12))
    var x: List[Float64] = [1, 1, 1]
    var y = a.multiply(x)
    assert_equal(y[0], 7)
    assert_equal(y[1], 0)
    assert_equal(y[2], 7)
    var d = a.diagonal()
    assert_equal(d[0], 1)
    assert_equal(d[1], 0)


def test_sparse_refuses_and_detects_asymmetry() raises:
    with assert_raises(contains="zero or more"):
        _ = SparseBuilder(-1)
    var b = SparseBuilder(2)
    with assert_raises(contains="out of range"):
        b.add(-1, 0, 1)
    with assert_raises(contains="out of range"):
        b.add(0, 2, 1)
    with assert_raises(contains="out of range"):
        b.add(2, 0, 1)
    with assert_raises(contains="out of range"):
        b.add(0, -1, 1)
    with assert_raises(contains="finite"):
        b.add(0, 0, inf[DType.float64]())
    b.add(0, 1, 1)
    var a = b.build()
    assert_false(a.is_symmetric(1e-12))
    with assert_raises(contains="out of range"):
        _ = a.get(2, 0)
    with assert_raises(contains="out of range"):
        _ = a.get(-1, 0)
    with assert_raises(contains="out of range"):
        _ = a.get(0, 2)
    with assert_raises(contains="out of range"):
        _ = a.get(0, -1)
    var short: List[Float64] = [1]
    with assert_raises(contains="matrix size"):
        _ = a.multiply(short)


# --- conjugate gradients -----------------------------------------------------


def test_conjugate_gradient_converges() raises:
    var n = 50
    var a = _second_difference(n)
    var b = zeros(n)
    for i in range(n):
        b[i] = Float64(i % 3)
    var result = conjugate_gradient(a, b, 1e-12, 200)
    assert_true(result.status == CONVERGED)
    assert_true(result.relative_residual <= 1e-12)
    var back = a.multiply(result.x)
    for i in range(n):
        assert_almost_equal(back[i], b[i], atol=1e-9)
    var zero = conjugate_gradient(a, zeros(n), 1e-12, 10)
    assert_equal(zero.iterations, 0)
    assert_true(zero.status == CONVERGED)


def test_conjugate_gradient_reports_its_budget() raises:
    var a = _second_difference(40)
    var b = zeros(40)
    b[0] = 1
    var result = conjugate_gradient(a, b, 1e-14, 3)
    assert_true(result.status == BUDGET_EXHAUSTED)
    assert_equal(result.iterations, 3)
    assert_true(BUDGET_EXHAUSTED.is_valid())
    assert_true(CONVERGED.is_valid())
    assert_false(SolveStatus(2).is_valid())
    assert_false(SolveStatus(-1).is_valid())


def test_conjugate_gradient_refuses() raises:
    var a = _second_difference(3)
    var b: List[Float64] = [1, 1, 1]
    var short: List[Float64] = [1]
    with assert_raises(contains="one entry per row"):
        _ = conjugate_gradient(a, short, 1e-8, 10)
    with assert_raises(contains="tolerance"):
        _ = conjugate_gradient(a, b, 0, 10)
    with assert_raises(contains="tolerance"):
        _ = conjugate_gradient(a, b, inf[DType.float64](), 10)
    with assert_raises(contains="budget"):
        _ = conjugate_gradient(a, b, 1e-8, -1)
    var bad: List[Float64] = [1, nan[DType.float64](), 1]
    with assert_raises(contains="finite"):
        _ = conjugate_gradient(a, bad, 1e-8, 10)
    var nb = SparseBuilder(2)
    nb.add(0, 0, 1)
    var no_diagonal = nb.build()
    var b2: List[Float64] = [1, 1]
    with assert_raises(contains="positive diagonal"):
        _ = conjugate_gradient(no_diagonal, b2, 1e-8, 10)
    # A positive diagonal but an indefinite matrix.
    var ib = SparseBuilder(2)
    ib.add(0, 0, 1)
    ib.add(1, 1, 1)
    ib.add(0, 1, 3)
    ib.add(1, 0, 3)
    var b3: List[Float64] = [1, -1]
    with assert_raises(contains="positive definite"):
        _ = conjugate_gradient(ib.build(), b3, 1e-8, 10)


# --- skyline -----------------------------------------------------------------


def test_reverse_cuthill_mckee_narrows_the_profile() raises:
    var n = 60
    var a = _scrambled_path(n)
    var natural = profile(a, identity_order(n))
    var order = reverse_cuthill_mckee(a)
    var reordered = profile(a, order)
    # A path numbered in order has a profile of 2n - 1.
    assert_equal(reordered, 2 * n - 1)
    assert_true(reordered < natural)


def test_reverse_cuthill_mckee_numbers_every_component() raises:
    # Two separate blocks and an isolated unknown.
    var b = SparseBuilder(5)
    b.add(0, 0, 2)
    b.add(0, 3, -1)
    b.add(3, 0, -1)
    b.add(3, 3, 2)
    b.add(1, 1, 2)
    b.add(1, 4, -1)
    b.add(4, 1, -1)
    b.add(4, 4, 2)
    b.add(2, 2, 1)
    var order = reverse_cuthill_mckee(b.build())
    var seen = List[Bool]()
    for _ in range(5):
        seen.append(False)
    for i in range(5):
        seen[order[i]] = True
    for i in range(5):
        assert_true(seen[i])


def test_skyline_matches_the_dense_solution() raises:
    var n = 30
    var a = _scrambled_path(n)
    var b = zeros(n)
    for i in range(n):
        b[i] = Float64(i) - 10
    var factor = SkylineFactor(a, reverse_cuthill_mckee(a))
    assert_true(factor.is_positive_definite())
    assert_equal(factor.negative_pivots(), 0)
    var x = factor.solve(b)
    var back = a.multiply(x)
    for i in range(n):
        assert_almost_equal(back[i], b[i], atol=1e-11)
    var plain = SkylineFactor(a, identity_order(n))
    var y = plain.solve(b)
    for i in range(n):
        assert_almost_equal(y[i], x[i], atol=1e-11)
    var short: List[Float64] = [1]
    with assert_raises(contains="one entry per row"):
        _ = factor.solve(short)


def test_skyline_profile_uses_the_reordered_upper_triangle() raises:
    # Store exactly the upper entries after each permutation. The mirrored
    # system has diagonals 4 and edges 0-1, 1-2, each of weight 1.
    for reordered in range(2):
        var order: List[Int] = [0, 1, 2]
        if reordered == 1:
            order[0] = 2
            order[1] = 0
            order[2] = 1
        for full in range(2):
            var b = SparseBuilder(3)
            for i in range(3):
                b.add(order[i], order[i], 4)
            b.add(order[0], order[1], 1)
            b.add(order[1], order[2], 1)
            if full == 1:
                b.add(order[1], order[0], 1)
                b.add(order[2], order[1], 1)
            var a = b.build()
            assert_equal(profile(a, order), 5)
            var factor = SkylineFactor(a, order.copy())
            assert_equal(len(factor.data), 5)
            var rhs = zeros(3)
            rhs[order[0]] = 5
            rhs[order[1]] = 6
            rhs[order[2]] = 5
            var solution = factor.solve(rhs)
            for i in range(3):
                assert_almost_equal(solution[i], 1, atol=1e-14)
    # Lower-only entries do not widen the profile or enter the factor.
    var lower = SparseBuilder(2)
    lower.add(0, 0, 2)
    lower.add(1, 1, 2)
    lower.add(1, 0, 9)
    var lower_matrix = lower.build()
    assert_equal(profile(lower_matrix, identity_order(2)), 2)
    var diagonal = SkylineFactor(lower_matrix, identity_order(2))
    var rhs: List[Float64] = [2, 2]
    var answer = diagonal.solve(rhs)
    assert_equal(answer[0], 1)
    assert_equal(answer[1], 1)


def test_skyline_counts_negative_pivots() raises:
    # Eigenvalues 1 and -1, so one negative pivot.
    var b = SparseBuilder(2)
    b.add(0, 1, 1)
    b.add(1, 0, 1)
    b.add(0, 0, 1e-3)
    var factor = SkylineFactor(b.build(), identity_order(2))
    assert_equal(factor.negative_pivots(), 1)
    assert_false(factor.is_positive_definite())


def test_skyline_refuses() raises:
    var singular = SparseBuilder(2)
    singular.add(0, 0, 1)
    singular.add(0, 1, 1)
    singular.add(1, 0, 1)
    singular.add(1, 1, 1)
    with assert_raises(contains="singular"):
        _ = SkylineFactor(singular.build(), identity_order(2))
    var a = _second_difference(3)
    var short: List[Int] = [0, 1]
    with assert_raises(contains="every unknown once"):
        _ = SkylineFactor(a, short^)
    var repeated: List[Int] = [0, 0, 1]
    with assert_raises(contains="every unknown once"):
        _ = profile(a, repeated)
    var outside: List[Int] = [0, 1, 3]
    with assert_raises(contains="every unknown once"):
        _ = profile(a, outside)
    var negative: List[Int] = [0, 1, -1]
    with assert_raises(contains="every unknown once"):
        _ = profile(a, negative)


# --- eigen -------------------------------------------------------------------


def test_lowest_modes_of_a_spring_chain() raises:
    var n = 40
    var k = _second_difference(n)
    var m = _identity_sparse(n)
    var modes = lowest_modes(k, m, 4, 1e-10, 60)
    assert_equal(len(modes.values), 4)
    for c in range(4):
        var expected = 2 - 2 * cos(Float64(c + 1) * pi / Float64(n + 1))
        assert_almost_equal(modes.values[c], expected, atol=1e-8)
        # Mass-normalized.
        assert_almost_equal(
            dot(modes.vectors[c], m.multiply(modes.vectors[c])), 1, atol=1e-10
        )
    assert_true(modes.iterations > 1)
    assert_equal(count_eigenvalues_below(k, m, modes.values[3] * 1.0001), 4)


def test_lowest_modes_of_a_small_problem_uses_every_vector() raises:
    # With n = 3 the subspace holds the whole space.
    var k = _second_difference(3)
    var m = _identity_sparse(3)
    var modes = lowest_modes(k, m, 3, 1e-12, 20)
    assert_almost_equal(modes.values[0], 2 - sqrt(2.0), atol=1e-12)
    assert_almost_equal(modes.values[2], 2 + sqrt(2.0), atol=1e-12)


def test_inertia_refusal_helpers_and_empty_rows() raises:
    assert_equal(_pivoted_inertia(SparseBuilder(0).build()), 0)
    with assert_raises(contains="singular"):
        _ = _pivoted_inertia(SparseBuilder(2).build())
    var row = SparseBuilder(2)
    row.add(1, 1, 1)
    with assert_raises(contains="singular"):
        _ = _pivoted_inertia(row.build())
    var invalid = _identity_sparse(1)
    invalid.values[0] = nan[DType.float64]()
    with assert_raises(contains="finite entries"):
        _ = _pivoted_inertia(invalid)
    assert_equal(_checked_schur_value(2), 2)
    with assert_raises(contains="finite arithmetic"):
        _ = _checked_schur_value(inf[DType.float64]())
    with assert_raises(contains="finite arithmetic"):
        _ = _checked_schur_value(nan[DType.float64]())
    _check_sturm_pivot(1)
    _check_sturm_pivot(-1)
    with assert_raises(contains="singular"):
        _check_sturm_pivot(1e-15)
    # The pivot boundary is inclusive, for both signs.
    with assert_raises(contains="singular"):
        _check_sturm_pivot(1e-14)
    with assert_raises(contains="singular"):
        _check_sturm_pivot(-1e-14)
    _check_sturm_pivot(1.0001e-14)
    _check_sturm_pivot(-1.0001e-14)
    assert_true(_independent_mass_norm(1, 1))
    assert_false(_independent_mass_norm(nan[DType.float64](), 1))
    assert_false(_independent_mass_norm(1, nan[DType.float64]()))
    assert_false(_independent_mass_norm(1, 0))
    assert_false(_independent_mass_norm(1, 1e-9))
    # Independence requires a strict increase above the relative bound.
    assert_false(_independent_mass_norm(1, 1e-8))
    assert_true(_independent_mass_norm(1, 1.0001e-8))


def test_sturm_verification_checks_incorrect_candidate_values() raises:
    var identity = _identity_sparse(3)
    _verify_sturm(identity, identity, [1.0, 1.0, 1.0], 2)
    var modes = lowest_modes(identity, identity, 2, 1e-12, 20)
    _check_modes(identity, identity, modes)
    # A purported value below the actual spectrum must fail the upper
    # count, independently of the lower-count refusal.
    with assert_raises(contains="missed eigenvalue"):
        _verify_sturm(identity, identity, [0.0, 1.0, 1.0], 1)
    # An unwanted Ritz value can put the first attempted shift exactly on
    # another true eigenvalue. The requested first value is still valid.
    var diagonal = SparseBuilder(4)
    diagonal.add(0, 0, 1)
    diagonal.add(1, 1, 3)
    diagonal.add(2, 2, 5)
    diagonal.add(3, 3, 7)
    _verify_sturm(diagonal.build(), _identity_sparse(4), [1.0, 5.0, 5.0], 1)


def test_sturm_count_pivots_a_nonsingular_indefinite_shift() raises:
    var b = SparseBuilder(2)
    b.add(0, 0, 2)
    b.add(1, 1, 2)
    b.add(0, 1, 1)
    b.add(1, 0, 1)
    var k = b.build()
    var m = _identity_sparse(2)
    assert_equal(count_eigenvalues_below(k, m, 2), 1)
    assert_equal(count_eigenvalues_below(k, m, 0), 0)
    assert_equal(count_eigenvalues_below(k, m, 4), 2)
    with assert_raises(contains="singular"):
        _ = count_eigenvalues_below(k, m, 1)
    with assert_raises(contains="finite"):
        _ = count_eigenvalues_below(k, m, inf[DType.float64]())
    var modes = lowest_modes(k, m, 1, 1e-12, 20)
    assert_almost_equal(modes.values[0], 1, atol=1e-12)
    _check_modes(k, m, modes)
    # Multiple blocks, symmetric swaps and nontrivial Schur updates.
    var chain = _second_difference(7)
    var mass = _identity_sparse(7)
    for count in range(1, 7):
        var lower = 2 - 2 * cos(Float64(count) * pi / 8)
        var upper = 2 - 2 * cos(Float64(count + 1) * pi / 8)
        assert_equal(
            count_eigenvalues_below(chain, mass, 0.5 * (lower + upper)), count
        )


def test_lowest_modes_can_end_inside_a_repeated_cluster() raises:
    var identity = _identity_sparse(2)
    var first = lowest_modes(identity, identity, 1, 1e-12, 20)
    assert_almost_equal(first.values[0], 1, atol=1e-12)
    _check_modes(identity, identity, first)
    # q = 9: the represented cluster reaches the edge of the trial space,
    # but its actual multiplicity is 12. No shift has a count of 1 or 9.
    var larger = _identity_sparse(12)
    var partial = lowest_modes(larger, larger, 1, 1e-12, 20)
    assert_almost_equal(partial.values[0], 1, atol=1e-12)
    _check_modes(larger, larger, partial)
    # A separate high-stiffness block must not make the narrow cluster
    # shifts look singular merely because the global matrix scale is high.
    var split_builder = SparseBuilder(12)
    for i in range(12):
        split_builder.add(i, i, 100.0 if i < 2 else 1.0)
    var split = split_builder.build()
    var split_modes = lowest_modes(split, larger, 1, 1e-12, 20)
    assert_almost_equal(split_modes.values[0], 1, atol=1e-12)
    _check_modes(split, larger, split_modes)
    # Two identical spring chains give each structural mode twice.
    var b = SparseBuilder(16)
    for block in range(2):
        for i in range(8):
            var row = block * 8 + i
            b.add(row, row, 2)
            if i + 1 < 8:
                b.add(row, row + 1, -1)
                b.add(row + 1, row, -1)
    var k = b.build()
    var m = _identity_sparse(16)
    var modes = lowest_modes(k, m, 3, 1e-12, 80)
    for c in range(3):
        var expected = 2 - 2 * cos(Float64(c // 2 + 1) * pi / 9)
        assert_almost_equal(modes.values[c], expected, atol=1e-10)
    _check_modes(k, m, modes)


def test_lowest_modes_refuses_mass_without_a_positive_basis() raises:
    var k = _identity_sparse(2)
    with assert_raises(contains="positive definite"):
        _ = lowest_modes(k, SparseBuilder(2).build(), 1, 1e-8, 2)
    var partial = SparseBuilder(2)
    partial.add(0, 0, 1)
    with assert_raises(contains="positive definite"):
        _ = lowest_modes(k, partial.build(), 1, 1e-8, 2)
    var negative = SparseBuilder(2)
    negative.add(0, 0, -1)
    negative.add(1, 1, -1)
    with assert_raises(contains="positive definite"):
        _ = lowest_modes(k, negative.build(), 1, 1e-8, 2)


def test_lowest_modes_refuses() raises:
    var k = _second_difference(4)
    var m = _identity_sparse(4)
    with assert_raises(contains="one size"):
        _ = lowest_modes(k, _identity_sparse(3), 1, 1e-8, 10)
    with assert_raises(contains="one size"):
        _ = count_eigenvalues_below(k, _identity_sparse(3), 1)
    with assert_raises(contains="mode count"):
        _ = lowest_modes(k, m, 0, 1e-8, 10)
    with assert_raises(contains="mode count"):
        _ = lowest_modes(k, m, 5, 1e-8, 10)
    with assert_raises(contains="tolerance"):
        _ = lowest_modes(k, m, 1, 0, 10)
    with assert_raises(contains="tolerance"):
        _ = lowest_modes(k, m, 1, nan[DType.float64](), 10)
    with assert_raises(contains="tolerance"):
        _ = lowest_modes(k, m, 1, inf[DType.float64](), 10)
    with assert_raises(contains="budget"):
        _ = lowest_modes(k, m, 1, 1e-8, 0)
    with assert_raises(contains="converge"):
        _ = lowest_modes(
            _second_difference(40), _identity_sparse(40), 2, 1e-15, 2
        )
    var negative = SparseBuilder(2)
    negative.add(0, 0, -1)
    negative.add(1, 1, 1)
    with assert_raises(contains="positive definite"):
        _ = lowest_modes(negative.build(), _identity_sparse(2), 1, 1e-8, 10)


# --- empty and degenerate shapes ----------------------------------------------


def test_empty_vectors_and_matrices() raises:
    var e = zeros(0)
    assert_equal(len(e), 0)
    check_finite(e)
    assert_equal(dot(e, e), 0)
    assert_equal(norm(e), 0)
    var f = zeros(0)
    axpy(1, e, f)
    var empty = DenseMatrix.identity(0)
    assert_equal(empty.transposed().rows, 0)
    assert_equal(len(empty.multiply_vector(e)), 0)
    assert_equal(len(solve(empty, e)), 0)
    assert_equal(cholesky(empty).rows, 0)
    assert_equal(len(solve_lower(empty, e)), 0)
    assert_equal(len(solve_lower_transposed(empty, e)), 0)
    assert_equal(len(symmetric_eigen(empty).values), 0)
    assert_equal(len(solve_tridiagonal(e, e, e, e)), 0)
    # Rows with no columns, and a product with no inner dimension.
    var tall = DenseMatrix(2, 0)
    assert_equal(tall.transposed().cols, 2)
    assert_equal(tall.multiply_vector(e)[1], 0)
    var wide = DenseMatrix(0, 3)
    assert_equal(tall.multiply(wide).get(1, 2), 0)
    assert_equal(wide.multiply(DenseMatrix(3, 2)).rows, 0)
    var one = DenseMatrix.identity(1)
    assert_equal(one.multiply(DenseMatrix(1, 0)).cols, 0)
    # A zero entry skips its row of the product.
    var sparse_rows = DenseMatrix(2, 2)
    sparse_rows.set(1, 1, 3)
    assert_equal(sparse_rows.multiply(DenseMatrix.identity(2)).get(1, 1), 3)


def test_tridiagonal_refuses_each_short_list() raises:
    var three: List[Float64] = [2, 2, 2]
    var short: List[Float64] = [1]
    with assert_raises(contains="one length"):
        _ = solve_tridiagonal(three, three, short, three)
    with assert_raises(contains="one length"):
        _ = solve_tridiagonal(three, three, three, short)


def test_empty_sparse_matrices() raises:
    var a = SparseBuilder(0).build()
    assert_equal(a.size, 0)
    assert_equal(len(a.multiply(zeros(0))), 0)
    assert_equal(len(a.diagonal()), 0)
    assert_true(a.is_symmetric(0))
    assert_equal(len(reverse_cuthill_mckee(a)), 0)
    assert_equal(len(identity_order(0)), 0)
    assert_equal(profile(a, identity_order(0)), 0)
    var factor = SkylineFactor(a, identity_order(0))
    assert_equal(len(factor.solve(zeros(0))), 0)
    var result = conjugate_gradient(a, zeros(0), 1e-8, 5)
    assert_equal(result.iterations, 0)
    assert_equal(count_eigenvalues_below(a, a, 1), 0)


def test_reordering_an_empty_row() raises:
    # Unknown 1 couples to nothing.
    var b = SparseBuilder(3)
    b.add(0, 0, 2)
    b.add(0, 2, -1)
    b.add(2, 0, -1)
    b.add(2, 2, 2)
    var a = b.build()
    var order = reverse_cuthill_mckee(a)
    assert_equal(len(order), 3)
    assert_equal(profile(a, order), 4)
    with assert_raises(contains="singular"):
        _ = SkylineFactor(a, order^)


def test_reordering_a_branching_graph() raises:
    # A tree: 0-1, 1-2, 1-3, 2-4, 2-5. From 1 the new neighbors come in
    # the order 2 (degree 3), 3 (degree 1), so the sort moves 3 first.
    # Then a path seeded from its middle: 7-6-8, with 6 first.
    var b = SparseBuilder(9)
    var edges: List[Int] = [0, 1, 1, 2, 1, 3, 2, 4, 2, 5, 6, 7, 6, 8]
    for i in range(9):
        b.add(i, i, 4)
    var e = 0
    while e < len(edges):
        b.add(edges[e], edges[e + 1], -1)
        b.add(edges[e + 1], edges[e], -1)
        e += 2
    var a = b.build()
    var order = reverse_cuthill_mckee(a)
    var factor = SkylineFactor(a, order^)
    assert_true(factor.is_positive_definite())


def _grid(side: Int) raises -> CsrMatrix:
    """A scrambled five-point grid Laplacian with a shift."""
    var n = side * side
    var b = SparseBuilder(n)
    var label = List[Int](capacity=n)
    for i in range(n):
        label.append((i * 7) % n)
    for r in range(side):
        for c in range(side):
            var here = label[r * side + c]
            b.add(here, here, 4.5)
            if c + 1 < side:
                var right = label[r * side + c + 1]
                b.add(here, right, -1)
                b.add(right, here, -1)
            if r + 1 < side:
                var down = label[(r + 1) * side + c]
                b.add(here, down, -1)
                b.add(down, here, -1)
    return b.build()


def test_reordering_a_grid_narrows_its_profile() raises:
    var a = _grid(6)
    var order = reverse_cuthill_mckee(a)
    assert_true(profile(a, order) < profile(a, identity_order(36)))
    var factor = SkylineFactor(a, order^)
    var b = zeros(36)
    b[5] = 1
    var x = factor.solve(b)
    var back = a.multiply(x)
    for i in range(36):
        assert_almost_equal(back[i], b[i], atol=1e-12)


def test_skyline_refuses_an_overflowing_pivot() raises:
    var b = SparseBuilder(2)
    b.add(0, 0, 1e290)
    b.add(0, 1, 1e300)
    b.add(1, 0, 1e300)
    b.add(1, 1, 1)
    with assert_raises(contains="singular"):
        _ = SkylineFactor(b.build(), identity_order(2))


def test_sturm_count_reads_rows_without_entries() raises:
    # K has no entries in row 0 and M none in row 1.
    var kb = SparseBuilder(2)
    kb.add(1, 1, 2)
    var mb = SparseBuilder(2)
    mb.add(0, 0, 1)
    assert_equal(count_eigenvalues_below(kb.build(), mb.build(), 1), 1)


def test_lowest_modes_with_unequal_masses() raises:
    var n = 20
    var k = _second_difference(n)
    var mb = SparseBuilder(n)
    for i in range(n):
        mb.add(i, i, 1 + Float64(i % 5))
    var m = mb.build()
    var modes = lowest_modes(k, m, 2, 1e-10, 80)
    # K φ = λ M φ for the lowest pair.
    var kphi = k.multiply(modes.vectors[0])
    var mphi = m.multiply(modes.vectors[0])
    for i in range(n):
        assert_almost_equal(kphi[i], modes.values[0] * mphi[i], atol=1e-7)


def test_sturm_check_catches_a_missed_mode() raises:
    # The lowest mode, (1, -1) on unknowns 0 and 1, is orthogonal to every
    # starting vector, so the subspace never contains it.
    var n = 12
    var kb = SparseBuilder(n)
    kb.add(0, 0, 100)
    kb.add(1, 1, 100)
    kb.add(0, 1, 99.5)
    kb.add(1, 0, 99.5)
    for i in range(2, n):
        kb.add(i, i, 10 + Float64(i))
    with assert_raises(contains="Sturm"):
        _ = lowest_modes(kb.build(), _identity_sparse(n), 1, 1e-10, 40)


def test_sturm_cluster_check_catches_a_missed_lower_mode() raises:
    # As in the distinct-mode witness, (1, -1) on the first block is
    # absent from the starting span. The visible lowest modes now repeat.
    var missing: List[Float64] = [0.5, 1 - 1e-10]
    for value in missing:
        var b = SparseBuilder(12)
        b.add(0, 0, 100)
        b.add(1, 1, 100)
        b.add(0, 1, 100 - value)
        b.add(1, 0, 100 - value)
        for i in range(2, 12):
            b.add(i, i, 1)
        with assert_raises(contains="Sturm"):
            _ = lowest_modes(b.build(), _identity_sparse(12), 1, 1e-10, 40)


def test_lowest_modes_with_one_huge_mass() raises:
    # A chain with a mass a million times the others at its last unknown.
    # The lowest mode is that mass on the springs around it: 1/8 + 1. The
    # trial vectors collapse onto it, and Gram-Schmidt replaces them.
    var n = 8
    var mb = SparseBuilder(n)
    for i in range(n):
        mb.add(i, i, 1.0 if i < n - 1 else 1e6)
    var modes = lowest_modes(_second_difference(n), mb.build(), 2, 1e-10, 100)
    assert_almost_equal(modes.values[0] * 1e6, 1.125, atol=1e-4)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
