# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The simplex search of Nelder and Mead, for a cost of a few parameters.

`minimize_simplex(cost, start, steps, tolerance, most)` finds a least
value of a cost without its derivatives, as image registration needs.
The simplex starts at `start` and at one step from it along each
parameter. Each iteration moves the worst point:

1. It reflects the worst point through the middle of the others.
2. When the reflection is the new best, it tries a point twice as far,
   and keeps the better.
3. When the reflection is worse than the second worst, it contracts
   halfway toward the middle, outside or inside of the worst point.
4. When the contraction does not improve, it shrinks every point halfway
   toward the best.

The search stops when every point is within `tolerance` steps of the
best along each parameter, or after `most` iterations.
"""

from std.math import isfinite, max


trait SimplexCost:
    """A cost that the simplex search can minimize."""

    def cost(mut self, point: List[Float64]) -> Float64:
        """Return the cost at a point.

        Args:
            point: The parameters.

        Returns:
            The cost. A larger value is worse.
        """
        ...


struct SimplexResult(Copyable, Movable):
    """The end of a simplex search."""

    var point: List[Float64]
    """The best point."""
    var value: Float64
    """The cost at the best point."""
    var iterations: Int
    """How many times the worst point moved, or the simplex shrank."""
    var evaluations: Int
    """How many times the cost was asked."""
    var converged: Bool
    """Whether the simplex became smaller than the tolerance."""

    def __init__(
        out self,
        var point: List[Float64],
        value: Float64,
        iterations: Int,
        evaluations: Int,
        converged: Bool,
    ):
        """Create a result.

        Args:
            point: The best point.
            value: The cost there.
            iterations: The iterations.
            evaluations: The evaluations of the cost.
            converged: Whether the search converged.
        """
        self.point = point^
        self.value = value
        self.iterations = iterations
        self.evaluations = evaluations
        self.converged = converged


def _toward(a: List[Float64], b: List[Float64], t: Float64) -> List[Float64]:
    """Return `a + t (b - a)`."""
    var out = List[Float64]()
    for i in range(len(a)):  # pragma: no branch
        out.append(a[i] + t * (b[i] - a[i]))
    return out^


def minimize_simplex[
    C: SimplexCost
](
    mut cost: C,
    start: List[Float64],
    steps: List[Float64],
    tolerance: Float64,
    most: Int,
) raises -> SimplexResult:
    """Find a least value of a cost by the simplex of Nelder and Mead.

    Parameters:
        C: The type of the cost.

    Args:
        cost: The cost.
        start: The first point, one parameter or more.
        steps: The first step along each parameter. Positive and finite.
        tolerance: The size at which the search stops, in steps. Positive.
        most: The most iterations, one or more.

    Returns:
        The best point and its cost.

    Raises:
        Error: If there is no parameter, the steps are not one for each
            parameter or not positive and finite, the tolerance is not
            positive, or `most` is less than one.
    """
    var n = len(start)
    if n == 0 or len(steps) != n:
        raise Error("A simplex search needs one step for each parameter")
    for s in steps:  # pragma: no branch
        if not (s > 0) or not isfinite(s):
            raise Error("A simplex step must be positive and finite")
    if not (tolerance > 0):
        raise Error("A simplex tolerance must be positive")
    if most < 1:
        raise Error("A simplex search needs one iteration or more")
    var points = List[List[Float64]]()
    var values = List[Float64]()
    points.append(start.copy())
    for i in range(n):  # pragma: no branch
        var p = start.copy()
        p[i] += steps[i]
        points.append(p^)
    for p in points:  # pragma: no branch
        values.append(cost.cost(p))
    var evaluations = n + 1
    var iterations = 0
    var converged = False
    while True:
        # Order the points from the best to the worst.
        for a in range(1, n + 1):  # pragma: no branch
            var b = a
            while b > 0 and values[b] < values[b - 1]:
                values.swap_elements(b, b - 1)
                points.swap_elements(b, b - 1)
                b -= 1
        var size = 0.0
        for i in range(1, n + 1):  # pragma: no branch
            for j in range(n):  # pragma: no branch
                size = max(size, abs(points[i][j] - points[0][j]) / steps[j])
        if size < tolerance:
            converged = True
            break
        if iterations >= most:
            break
        iterations += 1
        var middle = List[Float64](length=n, fill=0.0)
        for i in range(n):  # pragma: no branch
            for j in range(n):  # pragma: no branch
                middle[j] += points[i][j] / Float64(n)
        var reflected = _toward(middle, points[n], -1.0)
        var fr = cost.cost(reflected)
        evaluations += 1
        if fr < values[0]:
            var expanded = _toward(middle, points[n], -2.0)
            var fe = cost.cost(expanded)
            evaluations += 1
            if fe < fr:
                points[n] = expanded^
                values[n] = fe
            else:
                points[n] = reflected^
                values[n] = fr
            continue
        if fr < values[n - 1]:
            points[n] = reflected^
            values[n] = fr
            continue
        # Contract outside the worst point when the reflection is better
        # than it, and inside otherwise.
        var contracted: List[Float64]
        var limit: Float64
        if fr < values[n]:
            contracted = _toward(middle, reflected, 0.5)
            limit = fr
        else:
            contracted = _toward(middle, points[n], 0.5)
            limit = values[n]
        var fc = cost.cost(contracted)
        evaluations += 1
        if fc < limit:
            points[n] = contracted^
            values[n] = fc
            continue
        for i in range(1, n + 1):  # pragma: no branch
            points[i] = _toward(points[0], points[i], 0.5)
            values[i] = cost.cost(points[i])
        evaluations += n
    return SimplexResult(
        points[0].copy(), values[0], iterations, evaluations, converged
    )
