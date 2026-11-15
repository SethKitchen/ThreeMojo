# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The determinant and the adjugate of 3 by 3 matrices."""

from extensions.numerics.matrix3x3 import Matrix3x3, adjugate3, determinant3
from std.testing import TestSuite, assert_equal


def _matrix(values: List[Float64]) -> Matrix3x3:
    var m = Matrix3x3(0)
    for k in range(9):
        m[k] = values[k]
    return m


def test_determinant() raises:
    assert_equal(determinant3(_matrix([1, 0, 0, 0, 1, 0, 0, 0, 1])), 1.0)
    # A row swap changes the sign; a scaled row scales it.
    assert_equal(determinant3(_matrix([0, 1, 0, 1, 0, 0, 0, 0, 1])), -1.0)
    assert_equal(determinant3(_matrix([2, 0, 1, 1, 3, 2, 1, 1, 2])), 6.0)
    assert_equal(determinant3(_matrix([1, 2, 3, 4, 5, 6, 7, 8, 9])), 0.0)


def test_adjugate_is_the_inverse_times_the_determinant() raises:
    var a = _matrix([2, 0, 1, 1, 3, 2, 1, 1, 2])
    var adj = adjugate3(a)
    var det = determinant3(a)
    # A adj(A) = det(A) I = 6 I, exactly for small integers.
    for r in range(3):
        for c in range(3):
            var sum = 0.0
            for k in range(3):
                sum += a[3 * r + k] * adj[3 * k + c]
            assert_equal(sum, det if r == c else 0.0)
    for lane in range(9, 16):
        assert_equal(adj[lane], 0.0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
