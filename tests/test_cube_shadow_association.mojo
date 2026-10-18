# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Point-shadow distances retain the original Float32 sum association."""

from lights.shadow import cube_stored, point_shadow_depth
from std.math import sqrt, min, max
from std.memory import bitcast
from std.testing import TestSuite, assert_equal


def _original_cube_stored(
    ndc_depth: Float32,
    column: Int,
    row: Int,
    size: Int,
    near: Float32,
    far: Float32,
) -> Float32:
    # Exact main 0ad03120 grouping: (1 + x*x) + y*y.
    if ndc_depth > 1:
        return 1
    var along = 2 * far * near / ((far + near) - ndc_depth * (far - near))
    var x = (Float32(column) + 0.5) / Float32(size) * 2 - 1
    var y = 1 - (Float32(row) + 0.5) / Float32(size) * 2
    var distance = along * sqrt(1 + x * x + y * y)
    return max(
        Float32(0), min(Float32(1), point_shadow_depth(distance, near, far))
    )


def test_known_five_texel_regression() raises:
    var actual = cube_stored(0, 0, 0, 5, 1, 100)
    assert_equal(
        bitcast[DType.uint32](actual),
        bitcast[DType.uint32](_original_cube_stored(0, 0, 0, 5, 1, 100)),
    )


def test_depth_range_and_texel_grid_match_original_bits() raises:
    for size in [1, 2, 3, 5, 8, 13, 32]:
        for row in range(size):
            for column in range(size):
                for depth in [Float32(-1), -0.5, 0, 0.5, 1, 2]:
                    var actual = cube_stored(depth, column, row, size, 1, 100)
                    var reference = _original_cube_stored(
                        depth, column, row, size, 1, 100
                    )
                    assert_equal(
                        bitcast[DType.uint32](actual),
                        bitcast[DType.uint32](reference),
                    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
