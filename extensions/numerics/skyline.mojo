# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A skyline direct solver for symmetric matrices, with reordering.

The skyline, or profile, of a symmetric matrix is the region above the
diagonal from the first nonzero entry of each column down to the
diagonal. Gaussian elimination fills in only inside that region, so the
factor fits in the same storage. A frame or a shell model numbered with
neighbors close together has a narrow profile.

`reverse_cuthill_mckee` numbers the unknowns so that neighbors are close.
It starts from a pseudo-peripheral unknown, found by the method of George
and Liu, and visits the graph breadth first, nearest-degree first. The
reversed order usually gives a smaller profile than the forward one.

`SkylineFactor` holds A = Uᵀ D U, with U unit upper triangular and D
diagonal. The column-by-column elimination is the active-column method of
Bathe and Wilson. A symmetric indefinite matrix factors too, as long as no
pivot is zero; `negative_pivots` counts the negative entries of D. By
Sylvester's law of inertia, that count is the number of eigenvalues of A
below zero when this no-pivot factorization succeeds.

See Cuthill and McKee, "Reducing the bandwidth of sparse symmetric
matrices" (1969); George and Liu, "An implementation of a
pseudoperipheral node finder" (1979); and Bathe, "Finite Element
Procedures" (2nd edition, 2014), section 8.2.
"""

from std.math import isfinite
from extensions.numerics.sparse import CsrMatrix
from extensions.numerics.vector import zeros


def _degree(a: CsrMatrix, node: Int) -> Int:
    """Return how many other unknowns a row couples to."""
    var count = 0
    for k in range(a.row_start[node], a.row_start[node + 1]):
        if a.columns[k] != node:
            count += 1
    return count


def _levels(
    a: CsrMatrix, root: Int, mut level: List[Int], mut order: List[Int]
) -> Int:
    """Visit the component of `root` breadth first and record the levels.

    `level` holds -1 for an unvisited unknown. The visited unknowns are
    appended to `order`. Returns the depth of the deepest level.
    """
    var start = len(order)
    order.append(root)
    level[root] = 0
    var depth = 0
    var head = start
    while head < len(order):
        var node = order[head]
        head += 1
        for k in range(a.row_start[node], a.row_start[node + 1]):
            var other = a.columns[k]
            if level[other] < 0:
                level[other] = level[node] + 1
                depth = max(depth, level[other])
                order.append(other)
    return depth


def _peripheral(a: CsrMatrix, start: Int) -> Int:
    """Return a pseudo-peripheral unknown in the component of `start`.

    A component always holds `start`, so the loops over it run at least
    once.
    """
    var root = start
    var level = List[Int](capacity=a.size)
    var i = 0
    while i < a.size:
        level.append(-1)
        i += 1
    var order = List[Int]()
    var depth = _levels(a, root, level, order)
    while True:
        # The lowest-degree unknown of the deepest level.
        var candidate = -1
        var best = a.size + 1
        i = 0
        while i < len(order):
            var node = order[i]
            if level[node] == depth:
                var d = _degree(a, node)
                if d < best:
                    best = d
                    candidate = node
            i += 1
        _forget(level, order)
        var candidate_depth = _levels(a, candidate, level, order)
        _forget(level, order)
        if candidate_depth <= depth:
            return root
        root = candidate
        depth = _levels(a, root, level, order)


def _forget(mut level: List[Int], mut order: List[Int]):
    """Mark a visited component unvisited again and empty its order."""
    var i = 0
    while i < len(order):
        level[order[i]] = -1
        i += 1
    order.clear()


def reverse_cuthill_mckee(a: CsrMatrix) -> List[Int]:
    """Return an order of the unknowns that keeps neighbors close.

    Each component of the matrix graph is numbered from a
    pseudo-peripheral unknown, breadth first, with the neighbors of an
    unknown taken in order of increasing degree. The whole order is then
    reversed.

    Args:
        a: The matrix. Only its pattern is read.

    Returns:
        The new order: entry i is the original index of unknown i.
    """
    var n = a.size
    var placed = List[Bool](capacity=n)
    for _ in range(n):
        placed.append(False)
    var order = List[Int](capacity=n)
    for seed in range(n):
        if placed[seed]:
            continue
        var root = _peripheral(a, seed)
        placed[root] = True
        var head = len(order)
        order.append(root)
        while head < len(order):
            var node = order[head]
            head += 1
            var first = len(order)
            for k in range(a.row_start[node], a.row_start[node + 1]):
                var other = a.columns[k]
                if not placed[other]:
                    placed[other] = True
                    order.append(other)
            # Insertion sort of the new neighbors by degree.
            var i = first + 1
            while i < len(order):
                var held = order[i]
                var held_degree = _degree(a, held)
                var j = i - 1
                while j >= first and _degree(a, order[j]) > held_degree:
                    order[j + 1] = order[j]
                    j -= 1
                order[j + 1] = held
                i += 1
    var reversed = List[Int](capacity=n)
    var i = n - 1
    while i >= 0:
        reversed.append(order[i])
        i -= 1
    return reversed^


def identity_order(size: Int) -> List[Int]:
    """Return the order that keeps every unknown where it is.

    Args:
        size: The number of unknowns.

    Returns:
        0, 1, ... size - 1.
    """
    var out = List[Int](capacity=size)
    for i in range(size):
        out.append(i)
    return out^


def profile(a: CsrMatrix, order: List[Int]) raises -> Int:
    """Return how many entries a skyline factor stores for an order.

    Args:
        a: The matrix. Only its pattern is read.
        order: Entry i is the original index of unknown i.

    Returns:
        The number of stored entries, diagonal included.

    Raises:
        Error: If the order is not a permutation of the unknowns.
    """
    var inverse = _inverse(order, a.size)
    var top = _column_tops(a, order, inverse)
    var total = 0
    for j in range(a.size):
        total += j - top[j] + 1
    return total


def _inverse(order: List[Int], size: Int) raises -> List[Int]:
    """Return the inverse of a permutation, refusing anything else."""
    if len(order) != size:
        raise Error("An order must name every unknown once")
    var inverse = List[Int](capacity=size)
    for _ in range(size):
        inverse.append(-1)
    for i in range(size):
        var original = order[i]
        if original < 0 or original >= size or inverse[original] >= 0:
            raise Error("An order must name every unknown once")
        inverse[original] = i
    return inverse^


def _column_tops(
    a: CsrMatrix, order: List[Int], inverse: List[Int]
) -> List[Int]:
    """Return the first row of each new column's skyline."""
    var top = List[Int](capacity=a.size)
    for j in range(a.size):
        top.append(j)
    # Use exactly the reordered upper entries consumed by the scatter.
    # The lower pattern need not mirror them.
    for row in range(a.size):
        var original = order[row]
        for k in range(a.row_start[original], a.row_start[original + 1]):
            var col = inverse[a.columns[k]]
            if col >= row:
                top[col] = min(top[col], row)
    return top^


struct SkylineFactor(Movable):
    """A symmetric matrix factored as Uᵀ D U in skyline storage.

    Column j of U is stored from row `top[j]` down to the diagonal, at
    `data[start[j]]` onward. The diagonal slot holds D[j].
    """

    var size: Int
    var order: List[Int]
    var inverse: List[Int]
    var top: List[Int]
    var start: List[Int]
    var data: List[Float64]
    var _negative: Int

    def __init__(out self, a: CsrMatrix, var order: List[Int]) raises:
        """Factor a symmetric matrix in a given order.

        Only the entries in the upper triangle of the reordered matrix are
        read, so a nonsymmetric input is factored as if its other triangle
        mirrored them. Pass `reverse_cuthill_mckee(a)` for a small profile
        or `identity_order(a.size)` to keep the numbering.

        Args:
            a: The symmetric matrix.
            order: Entry i is the original index of unknown i.

        Raises:
            Error: If the order is not a permutation, or a pivot is zero
                or not finite.
        """
        var n = a.size
        self.size = n
        self.inverse = _inverse(order, n)
        self.top = _column_tops(a, order, self.inverse)
        self.order = order^
        self.start = List[Int](capacity=n + 1)
        self.start.append(0)
        for j in range(n):
            self.start.append(self.start[j] + j - self.top[j] + 1)
        self.data = zeros(self.start[n])
        self._negative = 0
        # Scatter the upper triangle into the columns.
        for row in range(n):
            var original = self.order[row]
            for k in range(a.row_start[original], a.row_start[original + 1]):
                var col = self.inverse[a.columns[k]]
                if col >= row:
                    self.data[self.start[col] + row - self.top[col]] = a.values[
                        k
                    ]
        var largest = Float64(0)
        for k in range(len(self.data)):
            largest = max(largest, abs(self.data[k]))
        var tiny = largest * 1e-14
        for j in range(n):
            var top_j = self.top[j]
            var base_j = self.start[j] - top_j
            # g_ij = a_ij - sum over r < i of u_ri g_rj.
            var i = top_j + 1
            while i < j:
                var top_i = self.top[i]
                var base_i = self.start[i] - top_i
                var r = max(top_i, top_j)
                var total = Float64(0)
                while r < i:
                    total += self.data[base_i + r] * self.data[base_j + r]
                    r += 1
                self.data[base_j + i] -= total
                i += 1
            # u_ij = g_ij / d_i and d_j = a_jj - sum of u_ij g_ij.
            var d = self.data[base_j + j]
            i = top_j
            while i < j:
                var g = self.data[base_j + i]
                var u = g / self.data[self.start[i] + i - self.top[i]]
                d -= u * g
                self.data[base_j + i] = u
                i += 1
            if not isfinite(d) or abs(d) <= tiny:
                raise Error("The matrix is singular to working precision")
            if d < 0:
                self._negative += 1
            self.data[base_j + j] = d

    def negative_pivots(self) -> Int:
        """Return how many entries of D are negative.

        Returns:
            The number of eigenvalues of the matrix below zero.
        """
        return self._negative

    def is_positive_definite(self) -> Bool:
        """Return True if every pivot is positive.

        Returns:
            Whether the matrix is positive definite.
        """
        return self._negative == 0

    def solve(self, b: List[Float64]) raises -> List[Float64]:
        """Solve A x = b with the factor.

        Args:
            b: The right-hand side, in the original numbering.

        Returns:
            The solution, in the original numbering.

        Raises:
            Error: If the length differs from the size.
        """
        if len(b) != self.size:
            raise Error("The right-hand side must have one entry per row")
        var n = self.size
        var y = zeros(n)
        for i in range(n):
            y[i] = b[self.order[i]]
        # Uᵀ y = b, forward.
        for j in range(n):
            var base_j = self.start[j] - self.top[j]
            var total = Float64(0)
            for i in range(self.top[j], j):
                total += self.data[base_j + i] * y[i]
            y[j] -= total
        # D z = y.
        for j in range(n):
            y[j] /= self.data[self.start[j] + j - self.top[j]]
        # U x = z, backward.
        var j = n - 1
        while j >= 0:
            var base_j = self.start[j] - self.top[j]
            var xj = y[j]
            for i in range(self.top[j], j):
                y[i] -= self.data[base_j + i] * xj
            j -= 1
        var x = zeros(n)
        for i in range(n):
            x[self.order[i]] = y[i]
        return x^
