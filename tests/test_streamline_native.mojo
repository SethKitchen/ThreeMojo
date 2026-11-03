# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests that DLSS, through the native host, does better than the fallback.

The tests run only where `THREEMOJO_STREAMLINE_HOST` names the program that
`extensions/streamline/native/build.bat` builds, on an RTX GPU. In WSL 2 the
Windows program runs directly. The bundle goes in through its standard input
and the frame comes back through its standard output, because a pipe is
faster than a file across the WSL 2 file bridge. On any other machine the
tests return at once.

Both tests feed the host frames of an analytic scene and compare its output
with the true image and with `SpatialUpscaler`:

- Super Resolution gets 24 jittered renders, played three times. It must
  come closer to the true image than the fallback on one render.
- Ray Reconstruction gets 24 jittered renders whose light is scaled by noise
  from 0 to 2, and the albedo, the normals and the roughness. It must come
  closer to the true image than the fallback on one noisy render, by a
  factor of two.
"""

from std.os import getenv, remove, rmdir
from std.os.path import exists
from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_true

from extensions.streamline.bundle import FrameBundle, decode_result
from extensions.streamline.jitter import jitter_offset, jitter_phase_count
from extensions.streamline.kinds import (
    MODE_BALANCED,
    ROUGHNESS_PACKED,
    RR_PRESET_F,
    SR_PRESET_M,
    SUPER_RESOLUTION,
)
from extensions.streamline.options import (
    RayReconstructionOptions,
    SuperResolutionOptions,
)
from extensions.streamline.sizing import FrameSize, estimated_render_size
from extensions.streamline.upscaler import SpatialUpscaler
from math.vector2 import Vector2
from render.framebuffer import FloatColor
from tests._streamline_scene import (
    constants_for,
    mean_squared_error,
    ray_reconstruction_buffers,
    render_colors,
    scene_camera,
    super_resolution_buffers,
    truth,
)
from tools._process import run_program

comptime OUTPUT = FrameSize(320, 180)


def _host() -> String:
    """Return the host program, or nothing when it is not here."""
    var host = getenv("THREEMOJO_STREAMLINE_HOST")
    if host.byte_length() == 0 or not exists(host):
        print("THREEMOJO_STREAMLINE_HOST names no program: skipped")
        return ""
    return host


def _run(host: String, bundle: FrameBundle) raises -> List[FloatColor]:
    """Run the host on a bundle, and return the frame that it wrote."""
    var directory = mkdtemp(prefix="threemojo-streamline-")
    var frames = directory + "/frames.slf"
    var result = directory + "/result.slr"
    Path(frames).write_bytes(bundle.encode())
    var ran = run_program(
        ["sh", "-c", 'exec "$0" - - <"$1" >"$2"', host, frames, result], 30
    )
    print(ran.output)
    var bytes = Path(result).read_bytes()
    remove(frames)
    remove(result)
    rmdir(directory)
    assert_equal(ran.status, 0, ran.output)
    return decode_result(bytes, bundle.output)


def test_super_resolution_beats_the_fallback() raises:
    var host = _host()
    if host.byte_length() == 0:
        return
    var render = estimated_render_size(MODE_BALANCED, OUTPUT)
    var options = SuperResolutionOptions(
        MODE_BALANCED, OUTPUT.width, OUTPUT.height
    )
    options.use_dlss_4_5(SR_PRESET_M)
    options.colors_are_hdr = False
    var camera = scene_camera()
    var bundle = FrameBundle(options, render, passes=3)
    var count = jitter_phase_count(render, OUTPUT)
    for index in range(count):
        var offset = jitter_offset(index, count)
        var constants = constants_for(camera, render, offset, index == 0)
        bundle.add(
            constants, super_resolution_buffers(constants, render, offset)
        )
    var dlss = _run(host, bundle)
    var still = constants_for(camera, render, Vector2(0, 0), True)
    var expected = truth(still, OUTPUT)
    var fallback = SpatialUpscaler().evaluate(
        SUPER_RESOLUTION,
        render_colors(still, render, Vector2(0, 0)),
        render,
        OUTPUT,
    )
    var dlss_error = mean_squared_error(dlss, expected, OUTPUT)
    var fallback_error = mean_squared_error(fallback, expected, OUTPUT)
    print("Super Resolution", dlss_error, "fallback", fallback_error)
    assert_true(dlss_error < fallback_error)


def test_ray_reconstruction_beats_the_fallback() raises:
    var host = _host()
    if host.byte_length() == 0:
        return
    var render = estimated_render_size(MODE_BALANCED, OUTPUT)
    var camera = scene_camera()
    var options = RayReconstructionOptions(
        MODE_BALANCED, OUTPUT.width, OUTPUT.height
    )
    options.use_dlss_4_5(RR_PRESET_F)
    options.colors_are_hdr = False
    options.normal_roughness_mode = ROUGHNESS_PACKED
    options.world_to_camera_view = camera.view
    var to_world = camera.view
    to_world.invert()
    options.camera_view_to_world = to_world
    var bundle = FrameBundle(options, render, passes=2)
    var count = jitter_phase_count(render, OUTPUT)
    for index in range(count):
        var offset = jitter_offset(index, count)
        var constants = constants_for(camera, render, offset, index == 0)
        bundle.add(
            constants,
            ray_reconstruction_buffers(constants, render, offset, index),
        )
    var dlss = _run(host, bundle)
    var still = constants_for(camera, render, Vector2(0, 0), True)
    var expected = truth(still, OUTPUT)
    var fallback = SpatialUpscaler().evaluate(
        SUPER_RESOLUTION,
        render_colors(still, render, Vector2(0, 0), 0),
        render,
        OUTPUT,
    )
    var dlss_error = mean_squared_error(dlss, expected, OUTPUT)
    var fallback_error = mean_squared_error(fallback, expected, OUTPUT)
    print("Ray Reconstruction", dlss_error, "fallback", fallback_error)
    assert_true(2 * dlss_error < fallback_error)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
