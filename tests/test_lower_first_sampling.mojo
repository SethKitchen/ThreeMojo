# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Keep extracted sampling clamps in their original IEEE operation order."""

from postprocessing.effects import (
    HALFTONE_ADD,
    HALFTONE_DARKER,
    HALFTONE_LIGHTER,
    HALFTONE_LINEAR,
    HALFTONE_MULTIPLY,
    HalftoneBlending,
)

from postprocessing.effects import halftone_blend, HALFTONE_LINEAR
from postprocessing.shaders import _bleach
from math.vector3 import Vector3
from postprocessing.gtao import _unit
from postprocessing.denoise import _normal
from postprocessing.ssr_node import _normal_at
from postprocessing.sampling import LightView
from render.framebuffer import FloatColor
from postprocessing.effects import _smoothstep
from postprocessing.filter_nodes import circle
from postprocessing.sampling import clamped_texel
from postprocessing.traa import sample_motion
from postprocessing.upscaling import _clamp4
from extensions.humanoid.skeleton.head.hair.shading import _saturate
from extensions.humanoid.skeleton.head.hair.groom import _pushed
from std.math import max as std_max, min as std_min
from std.memory import bitcast
from std.testing import TestSuite, assert_equal


def _original_saturate(x: Float32) -> Float32:
    return std_min(std_max(x, Float32(0)), Float32(1))


def _original_clamp4(
    value: Float32, p: Float32, q: Float32, s: Float32, t: Float32
) -> Float32:
    var low = min(min(p, q), min(s, t))
    var high = max(max(p, q), max(s, t))
    return min(max(value, low), high)


def _original_bleach(
    base: Float32, lum: Float32, l: Float32, a2: Float32
) -> Float32:
    var result1 = 2 * base * lum
    var result2 = 1 - 2 * (1 - lum) * (1 - base)
    var new_color = result1 + (result2 - result1) * l
    return a2 * new_color + (1 - a2) * base


def _original_halftone_blend(
    a: Float32, b: Float32, t: Float32, mode: HalftoneBlending
) -> Float32:
    """Return a halftone channel mixed with the frame's: `HalftoneShader`'s
    `blendColour`.

    Args:
        a: The halftone's channel.
        b: The frame's channel.
        t: How much of the halftone shows.
        mode: How the two combine.

    Returns:
        The mix. The linear mode moves from the frame at zero to the
        halftone at one. The others move from the halftone at zero toward
        their combination at one, as three.js's do.
    """
    if mode == HALFTONE_LINEAR:
        return a * t + b * (1 - t)
    var other: Float32
    if mode == HALFTONE_ADD:
        other = min(Float32(1), a + b)
    elif mode == HALFTONE_MULTIPLY:
        other = max(Float32(0), a * b)
    elif mode == HALFTONE_LIGHTER:
        other = max(a, b)
    else:
        # `HALFTONE_DARKER`, the only mode left once it is checked.
        other = min(a, b)
    return a * (1 - t) + other * t


def test_finite_equal_edges_keep_zero() raises:
    assert_equal(circle(1, 0, 1, 0.5), Float32(0))
    assert_equal(_smoothstep(1, 1, 1), Float32(0))
    assert_equal(sample_motion(0, 0, 0, 0, 1, 1, 0), Float32(0))
    assert_equal(_pushed(2, 1, 1, 1), Float32(2))


def test_sample_clamps_match_original_bits() raises:
    var words: List[UInt32] = [
        0,
        0x80000000,
        0x7FC00001,
        0xFFC00002,
        0x7F800000,
        0xFF800000,
        1,
        0x80000001,
        0x3F000000,
        0x40000000,
    ]
    for word in words:
        var x = bitcast[DType.float32](word)
        var expected = _original_saturate(x)
        assert_equal(
            bitcast[DType.uint32](_saturate(x)), bitcast[DType.uint32](expected)
        )
        assert_equal(
            bitcast[DType.uint32](_clamp4(x, 0, 1, 0, 1)),
            bitcast[DType.uint32](_original_clamp4(x, 0, 1, 0, 1)),
        )
        var texel = min(max(x * Float32(3) - 0.5, Float32(0)), Float32(2))
        assert_equal(
            bitcast[DType.uint32](clamped_texel(x, 3)),
            bitcast[DType.uint32](texel),
        )
        var t = min(max((x - Float32(1)) / Float32(0), Float32(0)), Float32(1))
        var step = t * t * (3 - 2 * t)
        assert_equal(
            bitcast[DType.uint32](_smoothstep(1, 1, x)),
            bitcast[DType.uint32](step),
        )


def test_normalization_keeps_original_length_then_reciprocal() raises:
    for v in [
        Vector3(3.0e38, 3.0e38, 0),
        Vector3(1.0e-30, 1.0e-30, 0),
        Vector3(1, 2, 3),
        Vector3(0, 0, 0),
    ]:
        var size = v.length()
        var expected = v if size == 0 else v * (1 / size)
        var colors: List[FloatColor] = [FloatColor(v.x, v.y, v.z, 1)]
        var view = LightView(colors, 1, 1)
        for actual in [
            _unit(v),
            _normal(view, 0.5, 0.5),
            _normal_at(view, 0.5, 0.5),
        ]:
            assert_equal(
                bitcast[DType.uint32](actual.x),
                bitcast[DType.uint32](expected.x),
            )
            assert_equal(
                bitcast[DType.uint32](actual.y),
                bitcast[DType.uint32](expected.y),
            )
            assert_equal(
                bitcast[DType.uint32](actual.z),
                bitcast[DType.uint32](expected.z),
            )
        _ = colors^


def test_color_summands_keep_original_order() raises:
    var words: List[UInt32] = [
        0,
        0x80000000,
        0x7FC00001,
        0xFFC00002,
        0x7F800000,
        0xFF800000,
        1,
        0x80000001,
        0x3F000000,
        0x40000000,
    ]
    for aw in words:
        var a = bitcast[DType.float32](aw)
        for bw in words:
            var b = bitcast[DType.float32](bw)
            for tw in words:
                var t = bitcast[DType.float32](tw)
                var expected = _original_halftone_blend(
                    a, b, t, HALFTONE_LINEAR
                )
                assert_equal(
                    bitcast[DType.uint32](
                        halftone_blend(a, b, t, HALFTONE_LINEAR)
                    ),
                    bitcast[DType.uint32](expected),
                )
                var expected_bleach = _original_bleach(a, b, t, t)
                assert_equal(
                    bitcast[DType.uint32](_bleach(a, b, t, t)),
                    bitcast[DType.uint32](expected_bleach),
                )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
