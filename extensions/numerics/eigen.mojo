# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The lowest eigenpairs of K φ = λ M φ, by subspace iteration.

A structure's natural frequencies are the square roots of the lowest
eigenvalues of its stiffness K against its mass M. Both matrices are
symmetric. K is positive definite once the supports are applied; M is
positive definite for a consistent mass.

Subspace iteration carries q > p trial vectors at once. Each iteration
solves K X̄ = M X with the skyline factor of K, projects K and M onto the
span of X̄, and solves that small problem completely with the dense
Jacobi method. The p lowest Ritz values converge first. After they
converge, a Sturm sequence check factors K - σ M just above the largest
one and counts the negative pivots. The count must equal p, which proves
that no eigenvalue below was missed.

See Bathe and Wilson, "Large eigenvalue problems in dynamic analysis"
(1972), and Bathe, "Finite Element Procedures" (2nd edition, 2014),
section 11.6.
"""

from std.math import isfinite, sqrt
from extensions.numerics.dense import (
    DenseMatrix,
    cholesky,
    solve_lower,
    solve_lower_transposed,
    symmetric_eigen,
)
from extensions.numerics.skyline import SkylineFactor, reverse_cuthill_mckee
from extensions.numerics.sparse import CsrMatrix, SparseBuilder
from extensions.numerics.vector import dot, zeros


struct Modes(Movable):
    """The lowest eigenvalues, ascending, and their mass-normalized vectors.

    Each vector φ satisfies φᵀ M φ = 1.
    """

    var values: List[Float64]
    var vectors: List[List[Float64]]
    var iterations: Int

    def __init__(
        out self,
        var values: List[Float64],
        var vectors: List[List[Float64]],
        iterations: Int,
    ):
        """Hold eigenpairs.

        Args:
            values: The eigenvalues, ascending.
            vectors: One mass-normalized vector per eigenvalue.
            iterations: How many subspace iterations ran.
        """
        self.values = values^
        self.vectors = vectors^
        self.iterations = iterations


def _shifted(k: CsrMatrix, m: CsrMatrix, shift: Float64) raises -> CsrMatrix:
    """Return K - shift M."""
    var builder = SparseBuilder(k.size)
    for i in range(k.size):
        for e in range(k.row_start[i], k.row_start[i + 1]):
            builder.add(i, k.columns[e], k.values[e])
        for e in range(m.row_start[i], m.row_start[i + 1]):
            builder.add(i, m.columns[e], -shift * m.values[e])
    return builder.build()


def count_eigenvalues_below(
    k: CsrMatrix, m: CsrMatrix, shift: Float64
) raises -> Int:
    """Return how many eigenvalues of K φ = λ M φ are below a shift.

    This is the Sturm sequence property: the number of negative pivots of
    K - shift M.

    Args:
        k: The symmetric stiffness.
        m: The symmetric positive-definite mass.
        shift: The value to count below.

    Returns:
        The count.

    Raises:
        Error: If the sizes differ or the shift is an eigenvalue to working
            precision.
    """
    if k.size != m.size:
        raise Error("The stiffness and mass must have one size")
    var shifted = _shifted(k, m, shift)
    var factor = SkylineFactor(shifted, reverse_cuthill_mckee(shifted))
    return factor.negative_pivots()


def lowest_modes(
    k: CsrMatrix,
    m: CsrMatrix,
    count: Int,
    tolerance: Float64,
    max_iterations: Int,
) raises -> Modes:
    """Return the lowest eigenpairs of K φ = λ M φ.

    Args:
        k: The symmetric positive-definite stiffness.
        m: The symmetric positive-definite mass.
        count: How many eigenpairs to return. From one to the size.
        tolerance: The relative change of each wanted eigenvalue between
            iterations to stop at. Positive and finite.
        max_iterations: The iteration budget. One or more.

    Returns:
        The eigenvalues, ascending, and their mass-normalized vectors.

    Raises:
        Error: If an argument is out of range, K is not positive definite,
            the projected mass is not positive definite, the iteration does
            not converge within the budget, or the Sturm check finds a
            missed eigenvalue.
    """
    var n = k.size
    if m.size != n:
        raise Error("The stiffness and mass must have one size")
    if count < 1 or count > n:
        raise Error("The mode count must be from one to the matrix size")
    if not (tolerance > 0 and isfinite(tolerance)):
        raise Error("A tolerance must be positive and finite")
    if max_iterations < 1:
        raise Error("An iteration budget must be one or more")
    var factor = SkylineFactor(k, reverse_cuthill_mckee(k))
    if not factor.is_positive_definite():
        raise Error("The stiffness must be positive definite")
    var q = min(n, max(2 * count, count + 8))
    # Starting vectors: the mass diagonal, then unit vectors at the
    # unknowns with the largest ratios of mass to stiffness.
    var m_diag = m.diagonal()
    var k_diag = k.diagonal()
    # Every loop below runs at least once: n, q and count are positive.
    # A positive-definite K has a positive diagonal.
    var ratio = zeros(n)
    var used = List[Bool](capacity=n)
    var i = 0
    while i < n:
        ratio[i] = m_diag[i] / k_diag[i]
        used.append(False)
        i += 1
    var x = List[List[Float64]](capacity=q)
    x.append(m_diag.copy())
    while len(x) < q:
        var best = -1
        i = 0
        while i < n:
            if not used[i] and (best < 0 or ratio[i] > ratio[best]):
                best = i
            i += 1
        used[best] = True
        var unit = zeros(n)
        unit[best] = 1
        x.append(unit^)
    var previous = zeros(count)
    var values = zeros(q)
    var iterations = 0
    var converged = False
    while iterations < max_iterations:
        iterations += 1
        # K X̄ = M X, and M X̄ for the projection.
        var y = List[List[Float64]](capacity=q)
        var xbar = List[List[Float64]](capacity=q)
        var mxbar = List[List[Float64]](capacity=q)
        var c = 0
        while c < q:
            var mx = m.multiply(x[c])
            var solved = factor.solve(mx)
            mxbar.append(m.multiply(solved))
            xbar.append(solved^)
            y.append(mx^)
            c += 1
        # Project: Kr = X̄ᵀ K X̄ = X̄ᵀ M X, Mr = X̄ᵀ M X̄.
        var kr = DenseMatrix(q, q)
        var mr = DenseMatrix(q, q)
        i = 0
        while i < q:
            var j = i
            while j < q:
                var kij = dot(xbar[i], y[j])
                var mij = dot(xbar[i], mxbar[j])
                kr.set(i, j, kij)
                kr.set(j, i, kij)
                mr.set(i, j, mij)
                mr.set(j, i, mij)
                j += 1
            i += 1
        # Kr Q = Mr Q Λ through Mr = L Lᵀ and C = L⁻¹ Kr L⁻ᵀ.
        var l = cholesky(mr)
        var half = DenseMatrix(q, q)
        var j = 0
        while j < q:
            var column = zeros(q)
            i = 0
            while i < q:
                column[i] = kr.get(i, j)
                i += 1
            var solved = solve_lower(l, column)
            i = 0
            while i < q:
                half.set(i, j, solved[i])
                i += 1
            j += 1
        # C = (L⁻¹ halfᵀ)ᵀ; C is symmetric, so row i is L⁻¹ times row i of
        # half.
        var c_matrix = DenseMatrix(q, q)
        i = 0
        while i < q:
            var row = zeros(q)
            j = 0
            while j < q:
                row[j] = half.get(i, j)
                j += 1
            var solved = solve_lower(l, row)
            j = 0
            while j < q:
                c_matrix.set(i, j, solved[j])
                j += 1
            i += 1
        var pairs = symmetric_eigen(c_matrix)
        x.clear()
        c = 0
        while c < q:
            var v = zeros(q)
            i = 0
            while i < q:
                v[i] = pairs.vectors.get(i, c)
                i += 1
            var coefficients = solve_lower_transposed(l, v)
            var vector = zeros(n)
            i = 0
            while i < q:
                var w = coefficients[i]
                var r = 0
                while r < n:
                    vector[r] += w * xbar[i][r]
                    r += 1
                i += 1
            x.append(vector^)
            values[c] = pairs.values[c]
            c += 1
        var done = iterations > 1
        c = 0
        while c < count:
            var change = abs(values[c] - previous[c])
            if not (change <= tolerance * abs(values[c])):
                done = False
            previous[c] = values[c]
            c += 1
        if done:
            converged = True
            break
    if not converged:
        raise Error("Subspace iteration did not converge")
    # The Sturm check, just above the largest wanted eigenvalue.
    var limit: Float64
    if count < q:
        limit = values[count - 1] + 0.5 * (values[count] - values[count - 1])
    else:
        limit = values[count - 1] * (1 + 1e-6)
    var below = count_eigenvalues_below(k, m, limit)
    if below != count:
        raise Error("The Sturm check found a missed eigenvalue")
    var out_values = zeros(count)
    var out_vectors = List[List[Float64]](capacity=count)
    var c = 0
    while c < count:
        out_values[c] = values[c]
        var scale = 1 / sqrt(dot(x[c], m.multiply(x[c])))
        var vector = x[c].copy()
        var r = 0
        while r < n:
            vector[r] *= scale
            r += 1
        out_vectors.append(vector^)
        c += 1
    return Modes(out_values^, out_vectors^, iterations)
