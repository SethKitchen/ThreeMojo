# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the render size of a DLSS mode, the check of what Streamline
reports, and the jitter."""

from extensions.streamline.jitter import jitter_offset, jitter_phase_count
from extensions.streamline.kinds import (
    MODE_BALANCED,
    MODE_DLAA,
    MODE_MAX_PERFORMANCE,
    MODE_MAX_QUALITY,
    MODE_OFF,
    MODE_ULTRA_PERFORMANCE,
    MODE_ULTRA_QUALITY,
    UpscaleMode,
)
from extensions.streamline.sizing import (
    FrameSize,
    OptimalSettings,
    check_optimal_settings,
    check_render_size,
    estimated_render_size,
    render_scale,
)
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)


def test_each_mode_renders_the_share_nvidia_publishes() raises:
    assert_equal(render_scale(MODE_OFF), 1.0)
    assert_equal(render_scale(MODE_DLAA), 1.0)
    assert_equal(render_scale(MODE_MAX_PERFORMANCE), 0.5)
    assert_equal(render_scale(MODE_BALANCED), 0.58)
    assert_almost_equal(render_scale(MODE_MAX_QUALITY), 2.0 / 3.0, atol=1e-12)
    assert_almost_equal(
        render_scale(MODE_ULTRA_PERFORMANCE), 1.0 / 3.0, atol=1e-12
    )
    assert_equal(render_scale(MODE_ULTRA_QUALITY), 0.77)
    with assert_raises(contains="mode"):
        _ = render_scale(UpscaleMode(7))
    with assert_raises(contains="mode"):
        _ = render_scale(UpscaleMode(-1))


def test_a_4k_output_renders_at_the_known_sizes() raises:
    var output = FrameSize(3840, 2160)
    assert_equal(
        estimated_render_size(MODE_MAX_QUALITY, output), FrameSize(2560, 1440)
    )
    assert_equal(
        estimated_render_size(MODE_MAX_PERFORMANCE, output),
        FrameSize(1920, 1080),
    )
    assert_equal(
        estimated_render_size(MODE_BALANCED, output), FrameSize(2227, 1253)
    )
    assert_equal(
        estimated_render_size(MODE_ULTRA_PERFORMANCE, output),
        FrameSize(1280, 720),
    )
    assert_equal(
        estimated_render_size(MODE_ULTRA_QUALITY, output), FrameSize(2957, 1663)
    )
    assert_equal(estimated_render_size(MODE_DLAA, output), output)
    assert_equal(estimated_render_size(MODE_OFF, output), output)


def test_a_tiny_output_still_renders_one_pixel() raises:
    assert_equal(
        estimated_render_size(MODE_ULTRA_PERFORMANCE, FrameSize(1, 1)),
        FrameSize(1, 1),
    )
    assert_equal(
        estimated_render_size(MODE_MAX_PERFORMANCE, FrameSize(3, 1)),
        FrameSize(2, 1),
    )


def test_the_estimate_refuses_a_bad_mode_or_output() raises:
    with assert_raises(contains="mode"):
        _ = estimated_render_size(UpscaleMode(7), FrameSize(64, 64))
    with assert_raises(contains="output"):
        _ = estimated_render_size(MODE_BALANCED, FrameSize(0, 64))
    with assert_raises(contains="output"):
        _ = estimated_render_size(MODE_BALANCED, FrameSize(64, 0))


def reply() -> OptimalSettings:
    """Return a reply for a 4K output at the Quality ratio, with a range."""
    return OptimalSettings(2560, 1440, 0.0, 1280, 720, 3840, 2160)


def test_a_sound_reply_is_accepted() raises:
    check_optimal_settings(reply(), FrameSize(3840, 2160))
    var edge = reply()
    edge.optimal_width = 3840
    edge.optimal_height = 2160
    edge.optimal_sharpness = 1
    check_optimal_settings(edge, FrameSize(3840, 2160))
    edge.optimal_width = 1280
    edge.optimal_height = 720
    check_optimal_settings(edge, FrameSize(3840, 2160))


def test_the_reply_check_refuses_a_size_below_one() raises:
    var bad = reply()
    bad.min_width = 0
    with assert_raises(contains="at least one pixel"):
        check_optimal_settings(bad, FrameSize(3840, 2160))
    bad = reply()
    bad.min_height = 0
    with assert_raises(contains="at least one pixel"):
        check_optimal_settings(bad, FrameSize(3840, 2160))


def test_the_reply_check_refuses_an_optimal_size_outside_the_range() raises:
    var bad = reply()
    bad.optimal_width = 1279
    with assert_raises(contains="below the smallest"):
        check_optimal_settings(bad, FrameSize(3840, 2160))
    bad = reply()
    bad.optimal_height = 719
    with assert_raises(contains="below the smallest"):
        check_optimal_settings(bad, FrameSize(3840, 2160))
    bad = reply()
    bad.max_width = 2559
    with assert_raises(contains="above the largest"):
        check_optimal_settings(bad, FrameSize(3840, 2160))
    bad = reply()
    bad.max_height = 1439
    with assert_raises(contains="above the largest"):
        check_optimal_settings(bad, FrameSize(3840, 2160))


def test_the_reply_check_refuses_a_render_larger_than_the_output() raises:
    var settings = reply()
    with assert_raises(contains="larger than the output"):
        check_optimal_settings(settings, FrameSize(2559, 2160))
    with assert_raises(contains="larger than the output"):
        check_optimal_settings(settings, FrameSize(3840, 1439))


def test_the_reply_check_refuses_a_bad_sharpness() raises:
    for bad in [
        nan[DType.float32](),
        inf[DType.float32](),
        Float32(-0.1),
        Float32(1.1),
    ]:
        var settings = reply()
        settings.optimal_sharpness = bad
        with assert_raises(contains="sharpness"):
            check_optimal_settings(settings, FrameSize(3840, 2160))


def test_a_render_size_must_lie_in_the_range() raises:
    var settings = reply()
    check_render_size(settings, FrameSize(2560, 1440))
    check_render_size(settings, FrameSize(1280, 720))
    check_render_size(settings, FrameSize(3840, 2160))
    with assert_raises(contains="smaller"):
        check_render_size(settings, FrameSize(1279, 1440))
    with assert_raises(contains="smaller"):
        check_render_size(settings, FrameSize(2560, 719))
    with assert_raises(contains="larger"):
        check_render_size(settings, FrameSize(3841, 1440))
    with assert_raises(contains="larger"):
        check_render_size(settings, FrameSize(2560, 2161))


def test_the_jitter_takes_eight_samples_a_covered_pixel() raises:
    var output = FrameSize(2560, 1440)
    assert_equal(jitter_phase_count(output, output), 8)
    assert_equal(jitter_phase_count(FrameSize(1280, 720), output), 32)
    assert_equal(jitter_phase_count(FrameSize(1707, 960), output), 18)
    assert_equal(jitter_phase_count(FrameSize(853, 480), output), 73)
    # A render that is not a whole fraction of the output rounds up.
    assert_equal(
        jitter_phase_count(FrameSize(2227, 1253), FrameSize(3840, 2160)), 24
    )


def test_the_jitter_count_refuses_bad_sizes() raises:
    with assert_raises(contains="render"):
        _ = jitter_phase_count(FrameSize(0, 720), FrameSize(2560, 1440))
    with assert_raises(contains="render"):
        _ = jitter_phase_count(FrameSize(1280, 0), FrameSize(2560, 1440))
    with assert_raises(contains="wider"):
        _ = jitter_phase_count(FrameSize(2561, 720), FrameSize(2560, 1440))


def test_the_jitter_is_halton_two_three_less_a_half() raises:
    var first = jitter_offset(0, 32)
    assert_almost_equal(first.x, 0.0, atol=1e-6)
    assert_almost_equal(first.y, 1.0 / 3.0 - 0.5, atol=1e-6)
    var second = jitter_offset(1, 32)
    assert_almost_equal(second.x, 0.25 - 0.5, atol=1e-6)
    assert_almost_equal(second.y, 2.0 / 3.0 - 0.5, atol=1e-6)
    var third = jitter_offset(2, 32)
    assert_almost_equal(third.x, 0.75 - 0.5, atol=1e-6)
    assert_almost_equal(third.y, 1.0 / 9.0 - 0.5, atol=1e-6)


def test_the_jitter_wraps_and_stays_within_half_a_pixel() raises:
    var wrapped = jitter_offset(32, 32)
    var first = jitter_offset(0, 32)
    assert_equal(wrapped.x, first.x)
    assert_equal(wrapped.y, first.y)
    for index in range(64):
        var offset = jitter_offset(index, 64)
        assert_true(offset.x > -0.5 and offset.x < 0.5)
        assert_true(offset.y > -0.5 and offset.y < 0.5)


def test_the_jitter_refuses_a_bad_index_or_count() raises:
    with assert_raises(contains="negative"):
        _ = jitter_offset(-1, 32)
    with assert_raises(contains="phase"):
        _ = jitter_offset(0, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
