# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Depth capture refuses malformed dimensions without replacing a snapshot."""

from math.matrix4 import Matrix4
from render.framebuffer import Color
from render.target import RenderTarget
from render.transmission import TransmissionTarget
from std.testing import TestSuite, assert_equal, assert_raises
from units.si import Length, METER


def test_requested_absent_snapshot_refuses_even_at_zero_size() raises:
    var captured = TransmissionTarget()
    captured.check_volume_depth(False, 0, 0)
    with assert_raises(
        contains="A volume needs scene depth at the raster target size"
    ):
        captured.check_volume_depth(True, 0, 0)
    assert_equal(len(captured.volume_depth), 0)


def test_nonpositive_capture_dimensions_refuse_without_replacing_depth() raises:
    for axis in range(2):
        for size in [0, -1]:
            var target = RenderTarget(1, 1, Color(0, 0, 0))
            var captured = TransmissionTarget(target, Matrix4())
            captured.capture_volume_depth(target, Matrix4(), Length(17, METER))
            captured.check_volume_depth(True, 1, 1)
            assert_equal(captured.volume_depth_at(0, 0).value, Float32(17))
            if axis == 0:
                target.width = size
                captured.image.width = size
            else:
                target.height = size
                captured.image.height = size
            target.depth.clear()
            with assert_raises(contains="positive raster dimensions"):
                captured.capture_volume_depth(
                    target, Matrix4(), Length(23, METER)
                )
            assert_equal(len(captured.volume_depth), 1)
            assert_equal(captured.volume_depth[0], Float32(17))


def test_dimension_mismatch_keeps_precedence_over_nonpositive_size() raises:
    for axis in range(2):
        var target = RenderTarget(1, 1, Color(0, 0, 0))
        var captured = TransmissionTarget(target, Matrix4())
        captured.capture_volume_depth(target, Matrix4(), Length(17, METER))
        if axis == 0:
            target.width = 0
        else:
            target.height = 0
        with assert_raises(contains="must match the captured image"):
            captured.capture_volume_depth(target, Matrix4(), Length(23, METER))
        assert_equal(len(captured.volume_depth), 1)
        assert_equal(captured.volume_depth[0], Float32(17))


def test_valid_one_pixel_capture_replaces_and_checks_the_snapshot() raises:
    var target = RenderTarget(1, 1, Color(0, 0, 0))
    var captured = TransmissionTarget(target, Matrix4())
    captured.capture_volume_depth(target, Matrix4(), Length(17, METER))
    assert_equal(len(captured.volume_depth), 1)
    assert_equal(captured.volume_depth_at(0, 0).value, Float32(17))
    target.depth[0] = -3
    captured.capture_volume_depth(target, Matrix4(), Length(23, METER))
    captured.check_volume_depth(True, 1, 1)
    assert_equal(len(captured.volume_depth), 1)
    assert_equal(captured.volume_depth_at(0, 0).value, Float32(3))


def test_nonempty_depth_length_must_match_the_captured_raster() raises:
    var target = RenderTarget(2, 1, Color(0, 0, 0))
    var captured = TransmissionTarget(target, Matrix4())
    captured.capture_volume_depth(target, Matrix4(), Length(17, METER))
    captured.check_volume_depth(True, 2, 1)
    _ = captured.volume_depth.pop()
    with assert_raises(
        contains="A volume needs scene depth at the raster target size"
    ):
        captured.check_volume_depth(True, 2, 1)
    assert_equal(len(captured.volume_depth), 1)
    assert_equal(captured.volume_depth[0], Float32(17))
    captured.volume_depth.append(17)
    captured.check_volume_depth(True, 2, 1)
    captured.volume_depth.append(23)
    with assert_raises(
        contains="A volume needs scene depth at the raster target size"
    ):
        captured.check_volume_depth(True, 2, 1)
    assert_equal(len(captured.volume_depth), 3)
    assert_equal(captured.volume_depth[0], Float32(17))
    assert_equal(captured.volume_depth[1], Float32(17))
    assert_equal(captured.volume_depth[2], Float32(23))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
