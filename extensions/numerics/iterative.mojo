# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The preconditioned conjugate-gradient method.

Conjugate gradients solve A x = b for a symmetric positive-definite A
with one matrix-vector product per iteration and no fill-in. The
preconditioner is the diagonal of A, the Jacobi preconditioner.

The method stops when the residual norm falls to `tolerance` times the
norm of b, or when it reaches the iteration budget. The second case is
not an error: the result says `BUDGET_EXHAUSTED` and holds the best
iterate, so the caller decides whether it is good enough.

See Hestenes and Stiefel, "Methods of conjugate gradients for solving
linear systems" (1952), and Saad, "Iterative Methods for Sparse Linear
Systems" (2nd edition, 2003), algorithm 9.1.
"""

from std.math import isfinite
from extensions.numerics.sparse import CsrMatrix
from extensions.numerics.vector import axpy, check_finite, dot, norm, zeros


@fieldwise_init
struct SolveStatus(Equatable, ImplicitlyCopyable, Writable):
    """How an iterative solve ended."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the two endings.

        Returns:
            Whether the value is 0 or 1.
        """
        return self.value == 0 or self.value == 1


comptime CONVERGED = SolveStatus(0)
comptime BUDGET_EXHAUSTED = SolveStatus(1)


struct IterativeResult(Movable):
    """What an iterative solve returns."""

    var x: List[Float64]
    var iterations: Int
    # The final residual norm divided by the norm of b.
    var relative_residual: Float64
    var status: SolveStatus

    def __init__(
        out self,
        var x: List[Float64],
        iterations: Int,
        relative_residual: Float64,
        status: SolveStatus,
    ):
        """Hold the result of a solve.

        Args:
            x: The solution, or the last iterate.
            iterations: How many iterations ran.
            relative_residual: The final residual norm over the norm of b.
            status: How the solve ended.
        """
        self.x = x^
        self.iterations = iterations
        self.relative_residual = relative_residual
        self.status = status


def conjugate_gradient(
    a: CsrMatrix, b: List[Float64], tolerance: Float64, max_iterations: Int
) raises -> IterativeResult:
    """Solve A x = b for a symmetric positive-definite A.

    The first iterate is zero.

    Args:
        a: The symmetric positive-definite matrix.
        b: The right-hand side.
        tolerance: The relative residual to stop at. Positive and finite.
        max_iterations: The iteration budget. Zero or more.

    Returns:
        The solution, the iteration count, the relative residual and the
        ending.

    Raises:
        Error: If the sizes differ, an input is not finite, a diagonal
            entry is not positive, or the matrix shows a non-positive
            curvature, which means it is not positive definite.
    """
    if len(b) != a.size:
        raise Error("The right-hand side must have one entry per row")
    if not (tolerance > 0 and isfinite(tolerance)):
        raise Error("A tolerance must be positive and finite")
    if max_iterations < 0:
        raise Error("An iteration budget must be zero or more")
    check_finite(b)
    var diagonal = a.diagonal()
    for i in range(a.size):
        if not (diagonal[i] > 0):
            raise Error("Conjugate gradients need a positive diagonal")
    var x = zeros(a.size)
    var b_norm = norm(b)
    if b_norm == 0:
        return IterativeResult(x^, 0, 0, CONVERGED)
    var r = b.copy()
    var z = zeros(a.size)
    var i = 0
    while i < a.size:
        z[i] = r[i] / diagonal[i]
        i += 1
    var p = z.copy()
    var rz = dot(r, z)
    var iterations = 0
    var residual = Float64(1)
    while iterations < max_iterations:
        var ap = a.multiply(p)
        var curvature = dot(p, ap)
        if not (curvature > 0):
            raise Error("The matrix is not positive definite")
        var alpha = rz / curvature
        axpy(alpha, p, x)
        axpy(-alpha, ap, r)
        iterations += 1
        residual = norm(r) / b_norm
        if residual <= tolerance:
            return IterativeResult(x^, iterations, residual, CONVERGED)
        i = 0
        while i < a.size:
            z[i] = r[i] / diagonal[i]
            i += 1
        var rz_next = dot(r, z)
        var beta = rz_next / rz
        rz = rz_next
        i = 0
        while i < a.size:
            p[i] = z[i] + beta * p[i]
            i += 1
    return IterativeResult(x^, iterations, residual, BUDGET_EXHAUSTED)
