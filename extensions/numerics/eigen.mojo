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
solves K X̄ = M X with the skyline factor of K, makes X̄ M-orthonormal by
modified Gram-Schmidt, projects K and M onto its span, and solves that
small problem completely with the dense Jacobi method. A vector that
collapses into the span of the others, as the vectors do when one mass
dwarfs the rest, is replaced by a unit vector. The p lowest Ritz values converge first. After they
converge, a Sturm sequence check counts the negative eigenvalues of
K - σ M. Symmetric pivoting handles a zero leading pivot. A request can
end inside a repeated cluster; counts on both sides of that cluster
check that no lower eigenvalue was missed.

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
from extensions.numerics.vector import dot, norm, zeros


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


def _swap_symmetric(mut a: DenseMatrix, first: Int, second: Int):
    """Apply the same permutation to rows and columns."""
    # The only caller swaps an active pivot in a nonempty matrix.
    for i in range(a.rows):  # pragma: no branch
        var held = a.get(first, i)
        a.set(first, i, a.get(second, i))
        a.set(second, i, held)
    for i in range(a.rows):  # pragma: no branch
        var held = a.get(i, first)
        a.set(i, first, a.get(i, second))
        a.set(i, second, held)


def _checked_schur_value(value: Float64) raises -> Float64:
    """Refuse a nonfinite Schur update before it enters the working matrix."""
    if not isfinite(value):
        raise Error("An inertia count needs finite arithmetic")
    return value


def _check_sturm_pivot(value: Float64) raises:
    """Refuse a finite pivot at or below the existing working threshold."""
    if abs(value) <= 1e-14:
        raise Error("The shifted matrix is singular to working precision")


def _independent_mass_norm(size: Float64, length: Float64) -> Bool:
    """Check the two computed mass norms before accepting a trial vector."""
    if (
        isfinite(size)
        and isfinite(length)
        and length > 0
        and length > 1e-8 * size
    ):
        return True
    return False


def _pivoted_inertia(a: CsrMatrix) raises -> Int:
    """Count negative eigenvalues by complete-pivot symmetric elimination.

    A 1 by 1 pivot is used when the largest diagonal is at least alpha
    times the largest off-diagonal. Otherwise a 2 by 2 pivot contains
    that off-diagonal. Both its scaled diagonals have magnitude below
    alpha < 1, so its determinant is negative: it adds one negative
    eigenvalue. Congruence preserves the remaining Schur inertia.
    """
    var n = a.size
    var work = DenseMatrix(n, n)
    var scale = Float64(0)
    for i in range(n):
        for e in range(a.row_start[i], a.row_start[i + 1]):
            var j = a.columns[e]
            if j >= i:
                var value = a.values[e]
                if not isfinite(value):
                    raise Error("An inertia count needs finite entries")
                work.set(i, j, value)
                work.set(j, i, value)
                scale = max(scale, abs(value))
    if n == 0:
        return 0
    if scale == 0:
        raise Error("The shifted matrix is singular to working precision")
    # n == 0 returned above; all following full-matrix ranges are nonempty.
    for i in range(n * n):  # pragma: no branch
        work.data[i] /= scale
    # Symmetric equilibration is a congruence, so it preserves inertia.
    # It prevents a large, separate block from making a small but fully
    # resolved diagonal shift look singular. The pivot tolerance stays
    # unchanged, applied to the equilibrated entries.
    var row_scale = zeros(n)
    for i in range(n):  # pragma: no branch
        var largest = Float64(0)
        for j in range(n):  # pragma: no branch
            largest = max(largest, abs(work.get(i, j)))
        if largest == 0:
            raise Error("The shifted matrix is singular to working precision")
        row_scale[i] = sqrt(largest)
    for i in range(n):  # pragma: no branch
        # Each row range includes its diagonal.
        for j in range(i, n):  # pragma: no branch
            var value = (work.get(i, j) / row_scale[i]) / row_scale[j]
            work.set(i, j, value)
            work.set(j, i, value)
    var alpha = (1 + sqrt(17.0)) / 8
    var tiny = Float64(1e-14)
    var negative = 0
    var k = 0
    while k < n:
        var diagonal = Float64(0)
        var off = Float64(0)
        var pivot = k
        var first = k
        var second = k
        # The enclosing while establishes k < n.
        for i in range(k, n):  # pragma: no branch
            if abs(work.get(i, i)) > diagonal:
                diagonal = abs(work.get(i, i))
                pivot = i
            for j in range(i + 1, n):
                if abs(work.get(i, j)) > off:
                    off = abs(work.get(i, j))
                    first = i
                    second = j
        if max(diagonal, off) <= tiny:
            raise Error("The shifted matrix is singular to working precision")
        if diagonal >= alpha * off:
            _swap_symmetric(work, k, pivot)
            var d = work.get(k, k)
            _check_sturm_pivot(d)
            if d < 0:
                negative += 1
            for i in range(k + 1, n):
                var multiplier = work.get(i, k) / d
                # i < n, so the update includes at least the diagonal.
                for j in range(i, n):  # pragma: no branch
                    var value = _checked_schur_value(
                        work.get(i, j) - multiplier * work.get(j, k)
                    )
                    work.set(i, j, value)
                    work.set(j, i, value)
            k += 1
        else:
            # first < second, so swapping first with k leaves second put.
            _swap_symmetric(work, k, first)
            _swap_symmetric(work, k + 1, second)
            var b = work.get(k, k + 1)
            var aa = work.get(k, k) / b
            var cc = work.get(k + 1, k + 1) / b
            var middle = 0.5 * (aa + cc)
            var half_gap = 0.5 * (aa - cc)
            var radius = sqrt(1 + half_gap * half_gap)
            _check_sturm_pivot((radius - abs(middle)) * abs(b))
            var determinant = aa * cc - 1
            negative += 1
            for i in range(k + 2, n):
                var left = work.get(i, k) / b
                var right = work.get(i, k + 1) / b
                var u = (cc * left - right) / determinant
                var v = (aa * right - left) / determinant
                # i < n, so the update includes at least the diagonal.
                for j in range(i, n):  # pragma: no branch
                    var value = _checked_schur_value(
                        work.get(i, j)
                        - u * work.get(j, k)
                        - v * work.get(j, k + 1)
                    )
                    work.set(i, j, value)
                    work.set(j, i, value)
            k += 2
    return negative


def count_eigenvalues_below(
    k: CsrMatrix, m: CsrMatrix, shift: Float64
) raises -> Int:
    """Return how many eigenvalues of K φ = λ M φ are below a shift.

    This is the inertia of K - shift M. A safe skyline factor is used
    first. A dense symmetric factor with 1 by 1 and 2 by 2 pivots handles
    zero or small leading pivots without changing the skyline contract.

    Args:
        k: The symmetric stiffness.
        m: The symmetric positive-definite mass.
        shift: The value to count below.

    Returns:
        The count.

    Raises:
        Error: If the sizes differ, the shift or arithmetic is not finite,
            or the shift is an eigenvalue to working precision.
    """
    if k.size != m.size:
        raise Error("The stiffness and mass must have one size")
    if not isfinite(shift):
        raise Error("An eigenvalue shift must be finite")
    var shifted = _shifted(k, m, shift)
    try:
        var factor = SkylineFactor(shifted, reverse_cuthill_mckee(shifted))
        # U_ij is the current off-diagonal divided by its 1 by 1 pivot.
        # This bound accepts only pivots with the same stability criterion
        # as the complete-pivot path. Large multipliers need pivoting too.
        var bound = 8 / (1 + sqrt(17.0))
        var safe = True
        for j in range(factor.size):
            for e in range(factor.start[j], factor.start[j + 1] - 1):
                if abs(factor.data[e]) > bound:
                    safe = False
        if safe:
            return factor.negative_pivots()
    except:
        pass
    return _pivoted_inertia(shifted)


def _verify_sturm(
    k: CsrMatrix, m: CsrMatrix, values: List[Float64], count: Int
) raises:
    """Check candidate Ritz values, including a partially requested cluster.

    The iteration supplies at least count values. Keeping this verification
    separate also lets tests supply deliberately incorrect candidate values
    and prove that each refusal remains active.
    """
    var q = len(values)
    # Preserve the ordinary Sturm check in a resolved Ritz gap.
    var last = values[count - 1]
    # The Euclidean norm of the Ritz values is the reduced symmetric
    # matrix's Frobenius norm. This is the scale of Jacobi's 1e-14 test.
    var roundoff = norm(values) * 1e-14
    var verified = False
    if count == q or abs(values[count] - last) > roundoff:
        var limit: Float64
        if count < q:
            limit = last + 0.5 * (values[count] - last)
        else:
            limit = last * (1 + 1e-6)
        try:
            verified = count_eigenvalues_below(k, m, limit) == count
        except:
            pass
    if not verified:
        # An unwanted Ritz vector can still be converging to the same
        # eigenvalue as the last wanted vector. Thus its apparent gap is
        # not proof that the repeated cluster ends. Let inertia identify
        # the cluster at Jacobi working precision, independently of the
        # user's iteration tolerance and the unwanted Ritz values.
        var first = count - 1
        while first > 0 and abs(values[first - 1] - last) <= roundoff:
            first -= 1
        var lower = count_eigenvalues_below(k, m, last - 4 * roundoff)
        var upper = count_eigenvalues_below(k, m, last + 4 * roundoff)
        if lower != first or upper < count:
            raise Error("The Sturm check found a missed eigenvalue")


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
    var cursor = 0
    var iterations = 0
    var converged = False
    while iterations < max_iterations:
        iterations += 1
        # X̄ = K⁻¹ M X, made M-orthonormal by modified Gram-Schmidt. A
        # vector that collapses into the span of the others is replaced by
        # a unit vector, so the projected mass stays positive definite.
        var xbar = List[List[Float64]](capacity=q)
        var mxbar = List[List[Float64]](capacity=q)
        var c = 0
        while c < q:
            var v = factor.solve(m.multiply(x[c]))
            var size = sqrt(dot(v, m.multiply(v)))
            var length: Float64
            var mv: List[Float64]
            var replacements = 0
            while True:
                var j = 0
                while j < len(xbar):
                    var projection = dot(v, mxbar[j])
                    var r = 0
                    while r < n:
                        v[r] -= projection * xbar[j][r]
                        r += 1
                    j += 1
                mv = m.multiply(v)
                length = sqrt(dot(v, mv))
                if _independent_mass_norm(size, length):
                    break
                # Try every coordinate at most once for this column.
                # No positive independent direction means M is unusable.
                if replacements == n:
                    raise Error(
                        "The mass must have independent positive definite"
                        " directions"
                    )
                replacements += 1
                v = zeros(n)
                v[cursor % n] = 1
                cursor += 1
                size = sqrt(dot(v, m.multiply(v)))
            var r = 0
            while r < n:
                v[r] /= length
                mv[r] /= length
                r += 1
            xbar.append(v^)
            mxbar.append(mv^)
            c += 1
        # Project: Kr = X̄ᵀ K X̄ and Mr = X̄ᵀ M X̄, close to the identity.
        var kr = DenseMatrix(q, q)
        var mr = DenseMatrix(q, q)
        i = 0
        while i < q:
            var kx = k.multiply(xbar[i])
            var j = i
            while j < q:
                var kij = dot(xbar[j], kx)
                var mij = dot(xbar[j], mxbar[i])
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
    _verify_sturm(k, m, values, count)
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
