# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Small dense matrices in `Float64`.

An element stiffness matrix, a coordinate transformation and the reduced
problem of a subspace iteration are dense and small. `DenseMatrix` holds
them in row-major order.

The solvers are the textbook ones:

- `solve` is Gaussian elimination with partial pivoting.
- `cholesky` factors a symmetric positive-definite matrix as L Lᵀ.
- `symmetric_eigen` is the cyclic Jacobi method. It returns every
  eigenvalue and an orthonormal set of eigenvectors.
- `solve_tridiagonal` is the Thomas algorithm, for one-dimensional heat
  conduction through a wall.

See Golub and Van Loan, "Matrix Computations" (4th edition, 2013),
sections 3.4, 4.2 and 8.5.
"""

from std.math import isfinite, sqrt
from extensions.numerics.vector import zeros

# The cyclic Jacobi method stops after this many sweeps. Each sweep at
# least squares the off-diagonal norm near convergence, so a few dozen
# sweeps are far more than a matrix needs.
comptime _JACOBI_SWEEPS = 64


struct DenseMatrix(Copyable, Movable):
    """A dense matrix of `Float64` entries in row-major order."""

    var rows: Int
    var cols: Int
    var data: List[Float64]

    def __init__(out self, rows: Int, cols: Int) raises:
        """Create a matrix of zeros.

        Args:
            rows: The number of rows. Zero or more.
            cols: The number of columns. Zero or more.

        Raises:
            Error: If a dimension is negative.
        """
        if rows < 0 or cols < 0:
            raise Error("A matrix dimension must be zero or more")
        self.rows = rows
        self.cols = cols
        self.data = zeros(rows * cols)

    @staticmethod
    def identity(size: Int) raises -> DenseMatrix:
        """Return an identity matrix.

        Args:
            size: The number of rows and columns.

        Returns:
            The identity.

        Raises:
            Error: If the size is negative.
        """
        var out = DenseMatrix(size, size)
        for i in range(size):
            out.data[i * size + i] = 1.0
        return out^

    def get(self, row: Int, col: Int) -> Float64:
        """Return one entry. The indices must be in range.

        Args:
            row: The row index.
            col: The column index.

        Returns:
            The entry.
        """
        return self.data[row * self.cols + col]

    def set(mut self, row: Int, col: Int, value: Float64):
        """Set one entry. The indices must be in range.

        Args:
            row: The row index.
            col: The column index.
            value: The new entry.
        """
        self.data[row * self.cols + col] = value

    def add(mut self, row: Int, col: Int, value: Float64):
        """Add to one entry. The indices must be in range.

        Args:
            row: The row index.
            col: The column index.
            value: The amount to add.
        """
        self.data[row * self.cols + col] += value

    def transposed(self) raises -> DenseMatrix:
        """Return the transpose.

        Returns:
            A new matrix with rows and columns swapped.

        Raises:
            Error: Never, for a matrix made by this module.
        """
        var out = DenseMatrix(self.cols, self.rows)
        for i in range(self.rows):
            for j in range(self.cols):
                out.data[j * self.rows + i] = self.data[i * self.cols + j]
        return out^

    def multiply(self, other: DenseMatrix) raises -> DenseMatrix:
        """Return the product of this matrix and another.

        Args:
            other: The right factor.

        Returns:
            The product.

        Raises:
            Error: If the inner dimensions differ.
        """
        if self.cols != other.rows:
            raise Error("A matrix product needs matching inner dimensions")
        var out = DenseMatrix(self.rows, other.cols)
        for i in range(self.rows):
            for k in range(self.cols):
                var a = self.data[i * self.cols + k]
                if a == 0:
                    continue
                for j in range(other.cols):
                    out.data[i * other.cols + j] += (
                        a * other.data[k * other.cols + j]
                    )
        return out^

    def multiply_vector(self, x: List[Float64]) raises -> List[Float64]:
        """Return the product of this matrix and a vector.

        Args:
            x: The vector. Its length must equal the column count.

        Returns:
            The product, one entry per row.

        Raises:
            Error: If the vector length differs from the column count.
        """
        if len(x) != self.cols:
            raise Error("A vector length must equal the column count")
        var out = zeros(self.rows)
        for i in range(self.rows):
            var total = Float64(0)
            for j in range(self.cols):
                total += self.data[i * self.cols + j] * x[j]
            out[i] = total
        return out^

    def triple_product(self, inner: DenseMatrix) raises -> DenseMatrix:
        """Return Tᵀ A T, with this matrix as T and `inner` as A.

        A coordinate transformation of an element matrix has this form.

        Args:
            inner: The square matrix A. Its size must equal T's row count.

        Returns:
            The transformed matrix.

        Raises:
            Error: If the dimensions do not match.
        """
        var t_transposed = self.transposed()
        var left = t_transposed.multiply(inner)
        return left.multiply(self)


def solve(a: DenseMatrix, b: List[Float64]) raises -> List[Float64]:
    """Solve A x = b by Gaussian elimination with partial pivoting.

    Args:
        a: A square matrix.
        b: The right-hand side, one entry per row.

    Returns:
        The solution x.

    Raises:
        Error: If the matrix is not square, the sizes differ, or the
            matrix is singular to working precision.
    """
    if a.rows != a.cols:
        raise Error("Gaussian elimination needs a square matrix")
    if len(b) != a.rows:
        raise Error("The right-hand side must have one entry per row")
    var n = a.rows
    var m = a.copy()
    var x = b.copy()
    var largest = Float64(0)
    for i in range(n * n):
        largest = max(largest, abs(m.data[i]))
    var tiny = largest * Float64(n) * 2.220446049250313e-16
    for k in range(n):
        var pivot_row = k
        var pivot = abs(m.data[k * n + k])
        for i in range(k + 1, n):
            var candidate = abs(m.data[i * n + k])
            if candidate > pivot:
                pivot = candidate
                pivot_row = i
        if not (pivot > tiny):
            raise Error("The matrix is singular")
        if pivot_row != k:
            var j = 0
            while j < n:
                var held = m.data[k * n + j]
                m.data[k * n + j] = m.data[pivot_row * n + j]
                m.data[pivot_row * n + j] = held
                j += 1
            var held_b = x[k]
            x[k] = x[pivot_row]
            x[pivot_row] = held_b
        var diagonal = m.data[k * n + k]
        for i in range(k + 1, n):
            var factor = m.data[i * n + k] / diagonal
            if factor == 0:
                continue
            var j = k
            while j < n:
                m.data[i * n + j] -= factor * m.data[k * n + j]
                j += 1
            x[i] -= factor * x[k]
    var i = n - 1
    while i >= 0:
        var total = x[i]
        for j in range(i + 1, n):
            total -= m.data[i * n + j] * x[j]
        x[i] = total / m.data[i * n + i]
        i -= 1
    return x^


def cholesky(a: DenseMatrix) raises -> DenseMatrix:
    """Factor a symmetric positive-definite matrix as L Lᵀ.

    Only the lower triangle of `a` is read.

    Args:
        a: The square matrix.

    Returns:
        The lower-triangular factor L.

    Raises:
        Error: If the matrix is not square or not positive definite.
    """
    if a.rows != a.cols:
        raise Error("A Cholesky factor needs a square matrix")
    var n = a.rows
    var l = DenseMatrix(n, n)
    for j in range(n):
        var diagonal = a.get(j, j)
        for k in range(j):
            diagonal -= l.get(j, k) * l.get(j, k)
        if not (diagonal > 0 and isfinite(diagonal)):
            raise Error("The matrix is not positive definite")
        var root = sqrt(diagonal)
        l.set(j, j, root)
        for i in range(j + 1, n):
            var total = a.get(i, j)
            for k in range(j):
                total -= l.get(i, k) * l.get(j, k)
            l.set(i, j, total / root)
    return l^


def solve_lower(l: DenseMatrix, b: List[Float64]) raises -> List[Float64]:
    """Solve L y = b for a lower-triangular L with a nonzero diagonal.

    Args:
        l: The lower-triangular matrix, such as a Cholesky factor.
        b: The right-hand side.

    Returns:
        The solution y.

    Raises:
        Error: If the sizes differ.
    """
    if len(b) != l.rows or l.rows != l.cols:
        raise Error("A triangular solve needs matching sizes")
    var y = b.copy()
    for i in range(l.rows):
        var total = y[i]
        for k in range(i):
            total -= l.get(i, k) * y[k]
        y[i] = total / l.get(i, i)
    return y^


def solve_lower_transposed(
    l: DenseMatrix, b: List[Float64]
) raises -> List[Float64]:
    """Solve Lᵀ x = b for a lower-triangular L with a nonzero diagonal.

    Args:
        l: The lower-triangular matrix, such as a Cholesky factor.
        b: The right-hand side.

    Returns:
        The solution x.

    Raises:
        Error: If the sizes differ.
    """
    if len(b) != l.rows or l.rows != l.cols:
        raise Error("A triangular solve needs matching sizes")
    var x = b.copy()
    var i = l.rows - 1
    while i >= 0:
        var total = x[i]
        for k in range(i + 1, l.rows):
            total -= l.get(k, i) * x[k]
        x[i] = total / l.get(i, i)
        i -= 1
    return x^


struct EigenPairs(Movable):
    """Eigenvalues in ascending order, with one eigenvector per column."""

    var values: List[Float64]
    var vectors: DenseMatrix

    def __init__(out self, var values: List[Float64], var vectors: DenseMatrix):
        """Hold eigenvalues and their eigenvectors.

        Args:
            values: The eigenvalues, ascending.
            vectors: The eigenvectors, column i for value i.
        """
        self.values = values^
        self.vectors = vectors^


def symmetric_eigen(a: DenseMatrix) raises -> EigenPairs:
    """Return every eigenvalue and eigenvector of a symmetric matrix.

    The cyclic Jacobi method rotates away each off-diagonal entry in turn
    until the off-diagonal part is negligible. Only symmetric input is
    meaningful; the method reads both triangles and assumes they agree.

    Args:
        a: The symmetric square matrix.

    Returns:
        The eigenvalues in ascending order and orthonormal eigenvectors.

    Raises:
        Error: If the matrix is not square, has a non-finite entry, or
            does not converge.
    """
    if a.rows != a.cols:
        raise Error("An eigenproblem needs a square matrix")
    var n = a.rows
    for i in range(n * n):
        if not isfinite(a.data[i]):
            raise Error("An eigenproblem needs finite entries")
    var m = a.copy()
    var v = DenseMatrix.identity(n)
    var converged = False
    var sweep = 0
    while sweep < _JACOBI_SWEEPS:
        sweep += 1
        var off = Float64(0)
        var total = Float64(0)
        for i in range(n):
            var j = 0
            while j < n:
                var entry = m.data[i * n + j] * m.data[i * n + j]
                total += entry
                if i != j:
                    off += entry
                j += 1
        if off <= total * 1e-28:
            converged = True
            break
        # A sweep runs only when an entry is off the diagonal, so n > 1.
        var p = 0
        while p < n:
            for q in range(p + 1, n):
                var apq = m.data[p * n + q]
                var app = m.data[p * n + p]
                var aqq = m.data[q * n + q]
                # An entry below rounding of its diagonal is already zero.
                if abs(apq) <= 1e-18 * (abs(app) + abs(aqq)):
                    m.data[p * n + q] = 0
                    m.data[q * n + p] = 0
                    continue
                var theta = (aqq - app) / (2 * apq)
                var sign = Float64(1) if theta >= 0 else Float64(-1)
                var t = sign / (abs(theta) + sqrt(theta * theta + 1))
                var c = 1 / sqrt(t * t + 1)
                var s = t * c
                var k = 0
                while k < n:
                    var akp = m.data[k * n + p]
                    var akq = m.data[k * n + q]
                    m.data[k * n + p] = c * akp - s * akq
                    m.data[k * n + q] = s * akp + c * akq
                    k += 1
                k = 0
                while k < n:
                    var apk = m.data[p * n + k]
                    var aqk = m.data[q * n + k]
                    m.data[p * n + k] = c * apk - s * aqk
                    m.data[q * n + k] = s * apk + c * aqk
                    k += 1
                k = 0
                while k < n:
                    var vkp = v.data[k * n + p]
                    var vkq = v.data[k * n + q]
                    v.data[k * n + p] = c * vkp - s * vkq
                    v.data[k * n + q] = s * vkp + c * vkq
                    k += 1
            p += 1

    if not converged:
        raise Error("The Jacobi eigensolver did not converge")
    # Sort ascending, moving eigenvector columns with their values.
    var order = List[Int](capacity=n)
    for i in range(n):
        order.append(i)
    for i in range(1, n):
        var held = order[i]
        var j = i - 1
        while (
            j >= 0 and m.data[order[j] * n + order[j]] > m.data[held * n + held]
        ):
            order[j + 1] = order[j]
            j -= 1
        order[j + 1] = held
    var values = zeros(n)
    var vectors = DenseMatrix(n, n)
    for c in range(n):
        var source = order[c]
        values[c] = m.data[source * n + source]
        var r = 0
        while r < n:
            vectors.data[r * n + c] = v.data[r * n + source]
            r += 1
    return EigenPairs(values^, vectors^)


def solve_tridiagonal(
    lower: List[Float64],
    diagonal: List[Float64],
    upper: List[Float64],
    rhs: List[Float64],
) raises -> List[Float64]:
    """Solve a tridiagonal system by the Thomas algorithm.

    Row i reads lower[i] x[i-1] + diagonal[i] x[i] + upper[i] x[i+1] =
    rhs[i]. `lower[0]` and the last `upper` entry are not read. The
    algorithm is stable for a diagonally dominant matrix, which a heat
    conduction system is.

    Args:
        lower: The entries below the diagonal, one per row.
        diagonal: The diagonal entries.
        upper: The entries above the diagonal, one per row.
        rhs: The right-hand side.

    Returns:
        The solution.

    Raises:
        Error: If the lengths differ or a pivot is zero.
    """
    var n = len(diagonal)
    if len(lower) != n or len(upper) != n or len(rhs) != n:
        raise Error("A tridiagonal system needs four lists of one length")
    var c = zeros(n)
    var d = zeros(n)
    for i in range(n):
        var pivot = diagonal[i]
        if i > 0:
            pivot -= lower[i] * c[i - 1]
        if pivot == 0 or not isfinite(pivot):
            raise Error("A tridiagonal pivot is zero")
        c[i] = upper[i] / pivot if i + 1 < n else 0
        var numerator = rhs[i]
        if i > 0:
            numerator -= lower[i] * d[i - 1]
        d[i] = numerator / pivot
    var x = zeros(n)
    var i = n - 1
    while i >= 0:
        x[i] = d[i]
        if i + 1 < n:
            x[i] -= c[i] * x[i + 1]
        i -= 1
    return x^
