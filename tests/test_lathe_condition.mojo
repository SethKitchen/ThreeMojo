# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The lathe normals stay finite where a Float32 sum of radii overflows."""

from geometries.lathe import _profile_normals
from math.vector2 import Vector2
from std.math import isfinite
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_false, assert_true


def test_monotone_radii_can_overflow_the_rounded_normal_sum() raises:
    # 3 * 2^103 is 1.5 ULP at the largest finite Float32. Each difference is finite,
    # but their rounded sum reaches the infinity midpoint.
    var largest = bitcast[DType.float32](UInt32(0x7F7FFFFF))
    var middle = bitcast[DType.float32](UInt32(0x73C00000))
    var previous_y = largest - middle
    assert_true(isfinite(previous_y))
    assert_true(isfinite(middle))
    assert_false(isfinite(previous_y + middle))
    var points: List[Vector2] = [
        Vector2(largest, 0),
        Vector2(middle, 1),
        Vector2(0, 2),
    ]
    # The normals are doubles now, as three.js's are, and the sum no
    # longer overflows. The stored Float32 normal is the same.
    var normals = _profile_normals(points)
    assert_equal(len(normals), 3)
    assert_true(isfinite(normals[1][0]))
    assert_true(isfinite(normals[1][1]))
    assert_equal(Float32(normals[1][1]), Float32(1))
    assert_true(normals[1][0] > 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
