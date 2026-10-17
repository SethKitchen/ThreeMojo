# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Public scalar helper names keep their original arithmetic."""

from extensions.water.optics import clamp01
from render.texture import mix
from std.math import inf, isnan, nan
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_true


def test_water_clamp_keeps_nan_and_zero_rules() raises:
    assert_true(isnan(clamp01(nan[DType.float32]())))
    assert_equal(bitcast[DType.uint32](clamp01(Float32(-0.0))), 0)
    assert_equal(clamp01(-inf[DType.float32]()), 0)
    assert_equal(clamp01(inf[DType.float32]()), 1)
    assert_equal(clamp01(0.375), 0.375)


def test_texture_mix_keeps_public_difference_first_order() raises:
    var values: List[Float32] = [-2, -0.0, 0.375, 1, 16]
    for near in values:
        for far in values:
            for t in values:
                var expected = near + (far - near) * t
                assert_equal(
                    bitcast[DType.uint32](mix(near, far, t)),
                    bitcast[DType.uint32](expected),
                )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
