# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The weighted spread of points, and eigenpairs from the largest."""

from extensions.numerics.dense import DenseMatrix, EigenPairs, symmetric_eigen
from extensions.numerics.spread import PointSpread, descending
from std.math import inf, nan, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
)


def test_weighted_mean_and_covariance() raises:
    # Weights of 1 and 3 at x = 0 and x = 4: the mean is 3, and the
    # covariance along x is (1 * 9 + 3 * 1) / 4 = 3.
    var spread = PointSpread()
    spread.add(0, 0, 0, 1)
    spread.add(4, 0, 0, 3)
    assert_equal(spread.weight, 4.0)
    assert_equal(spread.mean[0], 3.0)
    var c = spread.covariance()
    assert_almost_equal(c.get(0, 0), 3.0, atol=1e-15)
    assert_equal(c.get(1, 1), 0.0)


def test_far_from_the_origin() raises:
    # Four corners of a unit square, 1e9 from the origin, keep their
    # variance of 1/4 along each side.
    var spread = PointSpread()
    var corners: List[Tuple[Float64, Float64]] = [
        (0.0, 0.0),
        (1.0, 0.0),
        (0.0, 1.0),
        (1.0, 1.0),
    ]
    for p in corners:
        spread.add(1e9 + p[0], 1e9 + p[1], 5.0, 1.0)
    var c = spread.covariance()
    assert_almost_equal(c.get(0, 0), 0.25, atol=1e-12)
    assert_almost_equal(c.get(1, 1), 0.25, atol=1e-12)
    assert_almost_equal(c.get(0, 1), 0.0, atol=1e-12)


def test_principal_axes() raises:
    # Points along the diagonal of x and y spread the most there.
    var spread = PointSpread()
    for t in range(-2, 3):
        spread.add(Float64(t), Float64(t), 0, 1)
        spread.add(0.1 * Float64(t), -0.1 * Float64(t), 0, 1)
    var pairs = spread.principal()
    assert_equal(len(pairs.values), 3)
    assert_almost_equal(pairs.values[0], 2.0, atol=1e-14)
    assert_almost_equal(pairs.values[1], 0.02, atol=1e-14)
    assert_almost_equal(pairs.values[2], 0.0, atol=1e-15)
    assert_almost_equal(abs(pairs.vectors.get(0, 0)), sqrt(0.5), atol=1e-14)
    assert_almost_equal(abs(pairs.vectors.get(1, 0)), sqrt(0.5), atol=1e-14)


def test_descending() raises:
    var a = DenseMatrix(2, 2)
    a.set(0, 0, 1)
    a.set(1, 1, 5)
    var pairs = descending(symmetric_eigen(a))
    assert_equal(pairs.values[0], 5.0)
    assert_equal(pairs.values[1], 1.0)
    assert_equal(abs(pairs.vectors.get(1, 0)), 1.0)
    # No pairs give no pairs.
    var none = descending(EigenPairs(List[Float64](), DenseMatrix(0, 0)))
    assert_equal(len(none.values), 0)
    var values: List[Float64] = [1.0, 2.0]
    with assert_raises(contains="one vector for each value"):
        _ = descending(EigenPairs(values^, DenseMatrix(2, 3)))


def test_errors() raises:
    var spread = PointSpread()
    with assert_raises(contains="one point or more"):
        _ = spread.covariance()
    var weights: List[Float64] = [0.0, -1.0, inf[DType.float64]()]
    for w in weights:
        with assert_raises(contains="weight must be positive"):
            spread.add(0, 0, 0, w)
    var bad: List[Float64] = [inf[DType.float64](), nan[DType.float64]()]
    for v in bad:
        with assert_raises(contains="must be finite"):
            spread.add(v, 0, 0, 1)
        with assert_raises(contains="must be finite"):
            spread.add(0, v, 0, 1)
        with assert_raises(contains="must be finite"):
            spread.add(0, 0, v, 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
