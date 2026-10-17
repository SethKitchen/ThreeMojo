# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Render clamps retain their original NaN and signed-zero behavior."""

from math.vector3 import Vector3
from render.color_math import mix_opaque
from render.framebuffer import FloatColor
from render.fragment_flags import MIN_HASH_THRESHOLD, alpha_hash_threshold
from render.packing import normalized_distance
from render.raster_state import (
    LOGARITHMIC_DEPTH,
    REVERSED_DEPTH,
    STANDARD_DEPTH,
    DepthMode,
    window_depth,
)
from std.benchmark import black_box
from std.math import inf, max, min
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_true


def _original_window_depth(mode: DepthMode, depth: Float32) -> Float32:
    """Return a stored depth as a depth texture holds it: zero to one.

    Args:
        mode: The depth mode it was stored with.
        depth: The stored depth.

    Returns:
        The stored depth moved to zero to one and clamped there. A cleared
        pixel gives 1, or 0 under `REVERSED_DEPTH`.
    """
    var window = depth * 0.5 + 0.5
    if mode == REVERSED_DEPTH:
        window = depth
    return min(max(window, Float32(0)), Float32(1))


def test_depth_window_keeps_original_clamp_order() raises:
    var words: List[UInt32] = [
        0x00000000,
        0x80000000,
        0x7F800000,
        0xFF800000,
        0x7FC00001,
        0xFFC00001,
        0x7FA00001,
        0xFFA00001,
        0x00000001,
        0x80000001,
        0x3F000000,
        0x3F7FFFFF,
        0x3F800000,
        0x3F800001,
        0xBF800000,
    ]
    var modes = [STANDARD_DEPTH, LOGARITHMIC_DEPTH, REVERSED_DEPTH]
    for mode in modes:
        for word in words:
            var depth = black_box(bitcast[DType.float32](word))
            var expected = _original_window_depth(mode, depth)
            assert_equal(
                bitcast[DType.uint32](window_depth(mode, depth)),
                bitcast[DType.uint32](expected),
            )


def test_distance_clamp_keeps_nan_zero_and_infinity() raises:
    var zero = Vector3(0, 0, 0)
    var words: List[UInt32] = [0x7FC00001, 0xFFC00001, 0x7FA00001, 0xFFA00001]
    for word in words:
        var value = black_box(bitcast[DType.float32](word))
        assert_equal(
            bitcast[DType.uint32](
                normalized_distance(Vector3(value, 0, 0), zero, 0, 2)
            ),
            UInt32(0),
        )
    assert_equal(
        bitcast[DType.uint32](
            normalized_distance(Vector3(-0.0, 0, 0), zero, 0, 2)
        ),
        UInt32(0),
    )
    assert_equal(
        normalized_distance(Vector3(inf[DType.float32](), 0, 0), zero, 0, 2),
        Float32(1),
    )
    assert_equal(
        normalized_distance(Vector3(-inf[DType.float32](), 0, 0), zero, 0, 2),
        Float32(1),
    )
    assert_equal(normalized_distance(Vector3(1, 0, 0), zero, 0, 2), 0.5)
    assert_equal(normalized_distance(Vector3(3, 0, 0), zero, 0, 2), 1)


def test_alpha_hash_zero_derivatives_keep_the_low_threshold() raises:
    # Finite, stationary coordinates reach NaN through an infinite scale.
    # The original min(max(value, low), high) returns the low threshold.
    var zero = Vector3(0, 0, 0)
    assert_equal(alpha_hash_threshold(zero, zero, zero), MIN_HASH_THRESHOLD)
    assert_equal(
        alpha_hash_threshold(Vector3(1, 2, 3), zero, zero), MIN_HASH_THRESHOLD
    )
    var words: List[UInt32] = [
        0x7FC00001,
        0xFFC00001,
        0x7FA00001,
        0xFFA00001,
        0x7F800000,
        0xFF800000,
    ]
    for word in words:
        var value = black_box(bitcast[DType.float32](word))
        assert_equal(
            alpha_hash_threshold(
                Vector3(value, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)
            ),
            MIN_HASH_THRESHOLD,
        )
    assert_equal(
        alpha_hash_threshold(zero, Vector3(1, 0, 0), Vector3(0, 1, 0)),
        MIN_HASH_THRESHOLD,
    )
    var ordinary = alpha_hash_threshold(
        Vector3(1.25, -2, 3), Vector3(0.1, 0, 0), Vector3(0, 0.1, 0)
    )
    assert_true(ordinary >= MIN_HASH_THRESHOLD and ordinary <= 1)


def test_opaque_mix_discards_nonfinite_alpha_without_changing_rgb() raises:
    var words: List[UInt32] = [
        0x00000000,
        0x80000000,
        0x3F800000,
        0x7F800000,
        0xFF800000,
        0x7FC00001,
        0xFFC00001,
        0x7FA00001,
        0xFFA00001,
    ]
    var weights: List[Float32] = [0, 0.375, 1]
    for first in words:
        for second in words:
            var a = FloatColor(
                0.25, 0.5, 0.75, black_box(bitcast[DType.float32](first))
            )
            var b = FloatColor(
                0.75, 0.25, 0.125, black_box(bitcast[DType.float32](second))
            )
            for t in weights:
                var actual = mix_opaque(a, b, t)
                var expected = FloatColor(
                    a.r + (b.r - a.r) * t,
                    a.g + (b.g - a.g) * t,
                    a.b + (b.b - a.b) * t,
                )
                assert_equal(
                    bitcast[DType.uint32](actual.r),
                    bitcast[DType.uint32](expected.r),
                )
                assert_equal(
                    bitcast[DType.uint32](actual.g),
                    bitcast[DType.uint32](expected.g),
                )
                assert_equal(
                    bitcast[DType.uint32](actual.b),
                    bitcast[DType.uint32](expected.b),
                )
                assert_equal(actual.a, Float32(1))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
