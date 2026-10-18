# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the upscaler trait and its CPU fallback: what it supports,
what it refuses, and that it is EASU followed by RCAS."""

from extensions.streamline.kinds import (
    Feature,
    RAY_RECONSTRUCTION,
    SUPER_RESOLUTION,
)
from extensions.streamline.sizing import FrameSize
from extensions.streamline.upscaler import SpatialUpscaler, Upscaler
from postprocessing.sampling import LightView
from postprocessing.upscaling import easu_pixel, rcas_pixel
from render.framebuffer import FloatColor
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def gray(value: Float32) -> FloatColor:
    """Return an opaque gray."""
    return FloatColor(value, value, value, 1)


def ramp(width: Int, height: Int) -> List[FloatColor]:
    """Return an image that brightens from left to right."""
    var colors = List[FloatColor]()
    for _ in range(height):
        for x in range(width):
            colors.append(gray(Float32(x) / Float32(width - 1)))
    return colors^


def run_through[
    U: Upscaler
](
    upscaler: U,
    feature: Feature,
    colors: List[FloatColor],
    render: FrameSize,
    output: FrameSize,
) raises -> List[FloatColor]:
    """Run an upscaler through the trait alone."""
    return upscaler.evaluate(feature, colors, render, output)


def test_the_fallback_says_what_it_is() raises:
    var upscaler = SpatialUpscaler()
    assert_equal(upscaler.name(), "EASU and RCAS")
    assert_equal(upscaler.sharpness, 0.2)
    assert_true(upscaler.supports(SUPER_RESOLUTION))
    assert_false(upscaler.supports(RAY_RECONSTRUCTION))
    assert_false(upscaler.supports(Feature(2)))


def test_the_sharpness_must_be_finite_and_not_negative() raises:
    assert_equal(SpatialUpscaler(0).sharpness, 0)
    assert_equal(SpatialUpscaler(2).sharpness, 2)
    for bad in [nan[DType.float32](), inf[DType.float32](), Float32(-0.5)]:
        with assert_raises(contains="sharpness"):
            _ = SpatialUpscaler(bad)


def test_a_flat_image_stays_flat() raises:
    var colors = List[FloatColor]()
    for _ in range(4):
        colors.append(gray(0.5))
    var result = run_through(
        SpatialUpscaler(),
        SUPER_RESOLUTION,
        colors,
        FrameSize(2, 2),
        FrameSize(6, 4),
    )
    assert_equal(len(result), 24)
    for color in result:
        assert_almost_equal(color.r, 0.5, atol=1e-5)
        assert_almost_equal(color.g, 0.5, atol=1e-5)
        assert_almost_equal(color.b, 0.5, atol=1e-5)
        assert_almost_equal(color.a, 1.0, atol=1e-5)


def test_the_fallback_is_easu_then_rcas() raises:
    var render = FrameSize(4, 3)
    var output = FrameSize(8, 6)
    var colors = ramp(4, 3)
    var result = SpatialUpscaler(0.5).evaluate(
        SUPER_RESOLUTION, colors, render, output
    )
    var source = LightView(colors, render.width, render.height)
    var easu = List[FloatColor]()
    for y in range(output.height):
        for x in range(output.width):
            easu.append(
                easu_pixel(
                    source, x, y, output.width, output.height
                ).premultiplied()
            )
    var middle = LightView(easu, output.width, output.height)
    for y in range(output.height):
        for x in range(output.width):
            var expected = rcas_pixel(middle, x, y, 0.5, False)
            var got = result[y * output.width + x]
            assert_equal(got.r, expected.r)
            assert_equal(got.g, expected.g)
            assert_equal(got.b, expected.b)
            assert_equal(got.a, expected.a)
    # The views do not own their pixels: keep the lists to here.
    _ = easu^
    _ = colors^


def test_a_ramp_stays_a_ramp() raises:
    var result = SpatialUpscaler().evaluate(
        SUPER_RESOLUTION, ramp(4, 3), FrameSize(4, 3), FrameSize(8, 6)
    )
    for y in range(6):
        for x in range(7):
            assert_true(result[y * 8 + x].r <= result[y * 8 + x + 1].r + 1e-4)


def test_the_fallback_refuses_ray_reconstruction() raises:
    with assert_raises(contains="does not denoise"):
        _ = SpatialUpscaler().evaluate(
            RAY_RECONSTRUCTION, ramp(2, 2), FrameSize(2, 2), FrameSize(4, 4)
        )


def test_the_fallback_refuses_a_bad_feature_size_or_image() raises:
    var upscaler = SpatialUpscaler()
    with assert_raises(contains="feature"):
        _ = upscaler.evaluate(
            Feature(2), ramp(2, 2), FrameSize(2, 2), FrameSize(4, 4)
        )
    with assert_raises(contains="at least one pixel"):
        _ = upscaler.evaluate(
            SUPER_RESOLUTION, ramp(2, 2), FrameSize(0, 2), FrameSize(4, 4)
        )
    with assert_raises(contains="at least one pixel"):
        _ = upscaler.evaluate(
            SUPER_RESOLUTION, ramp(2, 2), FrameSize(2, 0), FrameSize(4, 4)
        )
    with assert_raises(contains="at least as large"):
        _ = upscaler.evaluate(
            SUPER_RESOLUTION, ramp(2, 2), FrameSize(2, 2), FrameSize(1, 4)
        )
    with assert_raises(contains="at least as large"):
        _ = upscaler.evaluate(
            SUPER_RESOLUTION, ramp(2, 2), FrameSize(2, 2), FrameSize(4, 1)
        )
    with assert_raises(contains="fill the render"):
        _ = upscaler.evaluate(
            SUPER_RESOLUTION, ramp(2, 1), FrameSize(2, 2), FrameSize(4, 4)
        )


def test_the_output_may_be_the_render_size() raises:
    var colors = ramp(3, 3)
    var result = SpatialUpscaler(0).evaluate(
        SUPER_RESOLUTION, colors, FrameSize(3, 3), FrameSize(3, 3)
    )
    assert_equal(len(result), 9)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
