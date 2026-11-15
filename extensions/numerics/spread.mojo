# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The weighted spread of points in three dimensions: their mean, their
covariance and its principal axes.

The atoms of a molecule weighted by mass, and the voxels of a label, have a
center and a spread. `PointSpread` takes the points one at a time, by the
weighted update of West (1979): it keeps the mean and the scatter about it,
so points far from the origin lose no digits.

`principal()` gives the eigenvalues of the covariance from the largest to
the smallest, with a unit axis for each.
"""

from extensions.numerics.dense import DenseMatrix, EigenPairs, symmetric_eigen
from math.finite import require_positive_finite
from std.math import isfinite


struct PointSpread(Copyable, Movable):
    """The weighted mean and covariance of points in three dimensions."""

    var weight: Float64
    """The sum of the weights."""
    var mean: List[Float64]
    """The weighted mean of x, y and z."""
    var scatter: List[Float64]
    """The weighted sum of the products of the offsets from the mean, row
    by row."""

    def __init__(out self):
        """Create a spread with no point."""
        self.weight = 0
        self.mean = List[Float64](length=3, fill=0)
        self.scatter = List[Float64](length=9, fill=0)

    def add(
        mut self, x: Float64, y: Float64, z: Float64, weight: Float64
    ) raises:
        """Add a point.

        Args:
            x: The first coordinate.
            y: The second coordinate.
            z: The third coordinate.
            weight: The weight of the point, positive and finite.

        Raises:
            Error: If the weight is not positive and finite, or a
                coordinate is not finite.
        """
        require_positive_finite(weight, "A point weight must be positive")
        if not isfinite(x) or not isfinite(y) or not isfinite(z):
            raise Error("A point must be finite")
        self.weight += weight
        var share = weight / self.weight
        # The offsets before and after the mean moves.
        var bx = x - self.mean[0]
        var by = y - self.mean[1]
        var bz = z - self.mean[2]
        self.mean[0] += bx * share
        self.mean[1] += by * share
        self.mean[2] += bz * share
        var ax = x - self.mean[0]
        var ay = y - self.mean[1]
        var az = z - self.mean[2]
        self.scatter[0] += weight * bx * ax
        self.scatter[1] += weight * bx * ay
        self.scatter[2] += weight * bx * az
        self.scatter[3] += weight * by * ax
        self.scatter[4] += weight * by * ay
        self.scatter[5] += weight * by * az
        self.scatter[6] += weight * bz * ax
        self.scatter[7] += weight * bz * ay
        self.scatter[8] += weight * bz * az

    def covariance(self) raises -> DenseMatrix:
        """Return the weighted covariance.

        Returns:
            The scatter over the sum of the weights, 3 by 3.

        Raises:
            Error: If there is no point.
        """
        if not (self.weight > 0):
            raise Error("A spread needs one point or more")
        var out = DenseMatrix(3, 3)
        for at in range(9):  # pragma: no branch
            out.data[at] = self.scatter[at] / self.weight
        return out^

    def principal(self) raises -> EigenPairs:
        """Return the principal axes of the covariance.

        Returns:
            The eigenvalues from the largest to the smallest, and a unit
            axis for each in the columns. An axis has an arbitrary sign.

        Raises:
            Error: If there is no point.
        """
        return descending(symmetric_eigen(self.covariance()))


def descending(pairs: EigenPairs) raises -> EigenPairs:
    """Return eigenpairs from the largest eigenvalue to the smallest.

    Args:
        pairs: Eigenpairs in ascending order, as `symmetric_eigen` gives
            them.

    Returns:
        The same pairs, the largest first, with each vector in its column.

    Raises:
        Error: If the vectors are not one column for each value.
    """
    var n = len(pairs.values)
    if pairs.vectors.cols != n:
        raise Error("Eigenpairs need one vector for each value")
    var values = List[Float64]()
    var vectors = DenseMatrix(pairs.vectors.rows, n)
    for c in range(n):
        values.append(pairs.values[n - 1 - c])
        for r in range(pairs.vectors.rows):  # pragma: no branch
            vectors.set(r, c, pairs.vectors.get(r, n - 1 - c))
    return EigenPairs(values^, vectors^)
