# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Square sparse matrices in `Float64`.

A finite-element assembly adds many small contributions to a large,
mostly empty matrix. `SparseBuilder` collects them as triplets: a row, a
column and a value. `build` sorts the triplets, adds the ones at the same
position and returns a `CsrMatrix` in compressed sparse row form.

The matrices are square, because the stiffness, mass and conductance
matrices of an analysis are square.
"""

from std.math import isfinite
from extensions.numerics.vector import zeros


struct SparseBuilder(Movable):
    """A square matrix under assembly, as a list of triplets."""

    var size: Int
    var _rows: List[Int]
    var _cols: List[Int]
    var _values: List[Float64]

    def __init__(out self, size: Int) raises:
        """Create an empty builder.

        Args:
            size: The number of rows and columns. Zero or more.

        Raises:
            Error: If the size is negative.
        """
        if size < 0:
            raise Error("A matrix size must be zero or more")
        self.size = size
        self._rows = List[Int]()
        self._cols = List[Int]()
        self._values = List[Float64]()

    def add(mut self, row: Int, col: Int, value: Float64) raises:
        """Add a value at a position. Repeated positions are summed.

        A zero value is skipped, so it does not widen the pattern.

        Args:
            row: The row index.
            col: The column index.
            value: The value to add.

        Raises:
            Error: If an index is out of range or the value is not finite.
        """
        if row < 0 or row >= self.size or col < 0 or col >= self.size:
            raise Error("A matrix index is out of range")
        if not isfinite(value):
            raise Error("A matrix entry must be a finite number")
        if value == 0:
            return
        self._rows.append(row)
        self._cols.append(col)
        self._values.append(value)

    def build(self) raises -> CsrMatrix:
        """Return the assembled matrix in compressed sparse row form.

        Returns:
            The matrix, with columns sorted within each row and duplicate
            positions summed.

        Raises:
            Error: Never, for triplets added through `add`.
        """
        var n = self.size
        var count = List[Int](capacity=n + 1)
        count.append(0)
        for _ in range(n):
            count.append(0)
        for k in range(len(self._rows)):
            count[self._rows[k] + 1] += 1
        for i in range(n):
            count[i + 1] += count[i]
        # Bucket the triplets by row.
        var next = count.copy()
        var cols = List[Int](capacity=len(self._rows))
        var values = zeros(len(self._rows))
        for _ in range(len(self._rows)):
            cols.append(0)
        for k in range(len(self._rows)):
            var slot = next[self._rows[k]]
            cols[slot] = self._cols[k]
            values[slot] = self._values[k]
            next[self._rows[k]] = slot + 1
        # Sort each row by column, then merge equal columns.
        var row_start = List[Int](capacity=n + 1)
        row_start.append(0)
        var out_cols = List[Int]()
        var out_values = List[Float64]()
        for i in range(n):
            var lo = count[i]
            var hi = count[i + 1]
            var j = lo + 1
            while j < hi:
                var held_col = cols[j]
                var held_value = values[j]
                var k = j - 1
                while k >= lo and cols[k] > held_col:
                    cols[k + 1] = cols[k]
                    values[k + 1] = values[k]
                    k -= 1
                cols[k + 1] = held_col
                values[k + 1] = held_value
                j += 1
            var k = lo
            while k < hi:
                var col = cols[k]
                var total = Float64(0)
                while k < hi and cols[k] == col:
                    total += values[k]
                    k += 1
                out_cols.append(col)
                out_values.append(total)
            row_start.append(len(out_cols))
        return CsrMatrix(n, row_start^, out_cols^, out_values^)


struct CsrMatrix(Copyable, Movable):
    """A square sparse matrix in compressed sparse row form.

    Row i holds the entries from `row_start[i]` up to `row_start[i + 1]`.
    Within a row the columns are sorted and distinct.
    """

    var size: Int
    var row_start: List[Int]
    var columns: List[Int]
    var values: List[Float64]

    def __init__(
        out self,
        size: Int,
        var row_start: List[Int],
        var columns: List[Int],
        var values: List[Float64],
    ):
        """Hold compressed rows. `SparseBuilder.build` makes these.

        Args:
            size: The number of rows and columns.
            row_start: Where each row starts, plus the end of the last.
            columns: The column of each entry.
            values: The value of each entry.
        """
        self.size = size
        self.row_start = row_start^
        self.columns = columns^
        self.values = values^

    def nonzeros(self) -> Int:
        """Return how many entries are stored.

        Returns:
            The number of stored entries.
        """
        return len(self.values)

    def get(self, row: Int, col: Int) raises -> Float64:
        """Return one entry, zero where nothing is stored.

        Args:
            row: The row index.
            col: The column index.

        Returns:
            The entry.

        Raises:
            Error: If an index is out of range.
        """
        if row < 0 or row >= self.size or col < 0 or col >= self.size:
            raise Error("A matrix index is out of range")
        var lo = self.row_start[row]
        var hi = self.row_start[row + 1]
        while lo < hi:
            var mid = (lo + hi) // 2
            if self.columns[mid] < col:
                lo = mid + 1
            else:
                hi = mid
        if lo < self.row_start[row + 1] and self.columns[lo] == col:
            return self.values[lo]
        return 0

    def multiply(self, x: List[Float64]) raises -> List[Float64]:
        """Return the product of this matrix and a vector.

        Args:
            x: The vector, one entry per column.

        Returns:
            The product, one entry per row.

        Raises:
            Error: If the vector length differs from the size.
        """
        if len(x) != self.size:
            raise Error("A vector length must equal the matrix size")
        var out = zeros(self.size)
        for i in range(self.size):
            var total = Float64(0)
            for k in range(self.row_start[i], self.row_start[i + 1]):
                total += self.values[k] * x[self.columns[k]]
            out[i] = total
        return out^

    def diagonal(self) raises -> List[Float64]:
        """Return the diagonal entries.

        Returns:
            One entry per row, zero where nothing is stored.

        Raises:
            Error: Never, for a matrix made by `SparseBuilder`.
        """
        var out = zeros(self.size)
        for i in range(self.size):
            out[i] = self.get(i, i)
        return out^

    def is_symmetric(self, tolerance: Float64) raises -> Bool:
        """Return True if the matrix equals its transpose within a tolerance.

        Args:
            tolerance: The largest difference allowed, relative to the
                largest entry.

        Returns:
            Whether every entry matches its mirror.

        Raises:
            Error: Never, for a matrix made by `SparseBuilder`.
        """
        var largest = Float64(0)
        for k in range(len(self.values)):
            largest = max(largest, abs(self.values[k]))
        for i in range(self.size):
            for k in range(self.row_start[i], self.row_start[i + 1]):
                var mirror = self.get(self.columns[k], i)
                if abs(self.values[k] - mirror) > tolerance * largest:
                    return False
        return True
