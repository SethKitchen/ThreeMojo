# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""The Float32-only wide inverse that Apple GPU kernels use.

Apple GPUs have no Float64, so a kernel compiled for one inverts extreme
matrices with `_inverse_scaled_float32`. These tests run it on the host
and compare it with the exact Float64 cofactors the host keeps using.
"""

from math.matrix_inverse import (
    _inverse_exact_cofactors,
    _inverse_scaled_float32,
)
from std.math import inf, isfinite, isnan, nan
from std.testing import TestSuite, assert_equal, assert_true


def assert_scaled_matches_exact[
    size: Int
](entries: Array[Float32, size * size]) raises:
    # The Apple GPU inverse agrees with the exact cofactors on a matrix far
    # from singular, to a few units in the last place.
    var exact = _inverse_exact_cofactors[size](entries)
    var scaled = _inverse_scaled_float32[size](entries)
    assert_equal(scaled[0], exact[0])
    for index in range(size * size):
        var want = exact[1][index]
        var got = scaled[1][index]
        assert_true(
            abs(got - want) <= abs(want) * Float32(1e-5),
            String(index, ": ", got, " against ", want),
        )


def test_apple_gpu_inverse_matches_the_exact_cofactors() raises:
    for value in [Float32(1e-30), Float32(1e-9), Float32(1e9), Float32(3e37)]:
        # A swapped pair needs a row exchange.
        assert_scaled_matches_exact[2]([0, value, value, 0])
        var diagonal = Array[Float32, 9](fill=0)
        diagonal[0] = value
        diagonal[4] = -value
        diagonal[8] = 2 * value
        assert_scaled_matches_exact[3](diagonal)
    # Rows and columns of very different scales.
    assert_scaled_matches_exact[2]([Float32(3e30), 1e-20, 2e-10, 5e15])
    var mixed = Array[Float32, 16](fill=0)
    mixed[0] = 1e-30
    mixed[5] = 4
    mixed[6] = 1
    mixed[9] = 1
    mixed[10] = 3e20
    mixed[15] = -2e9
    assert_scaled_matches_exact[4](mixed)


def test_apple_gpu_inverse_refuses_singular_matrices() raises:
    var zero_row: Array[Float32, 4] = [1e20, 0, 2e20, 0]
    var zero_column: Array[Float32, 4] = [1e20, 3e-20, 0, 0]
    var repeated: Array[Float32, 4] = [1e20, 1e20, 1e20, 1e20]
    for matrix in [zero_row^, zero_column^, repeated^]:
        var scaled = _inverse_scaled_float32[2](matrix)
        assert_true(not scaled[0])
        for value in scaled[1]:
            assert_equal(value, Float32(0))


def test_apple_gpu_inverse_propagates_nonfinite_entries() raises:
    var entries: Array[Float32, 4] = [inf[DType.float32](), 0, 0, 1e20]
    var scaled = _inverse_scaled_float32[2](entries)
    assert_true(scaled[0])
    assert_equal(scaled[1][0], Float32(0))
    assert_true(not isfinite(scaled[1][1]) or scaled[1][1] == 0)
    assert_true(
        isnan(_inverse_scaled_float32[2]([nan[DType.float32](), 1, 1, 1])[1][0])
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
