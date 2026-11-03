# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the frames that the native Streamline host reads.

Each test reads the bytes back at the offsets that
`extensions/streamline/native/host.cpp` reads, so the two sides agree on
the layout. The refusals are the checks of `options`, `constants` and
`tags`, plus the bundle's own.
"""

from std.math import nan
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from extensions.streamline.bundle import (
    BufferData,
    FrameBundle,
    MOST_PASSES,
    decode_result,
    encode_result,
)
from extensions.streamline.kinds import (
    BUFFER_ALBEDO,
    BUFFER_DEPTH,
    BUFFER_INPUT_COLOR,
    BUFFER_MOTION_VECTORS,
    BUFFER_OUTPUT_COLOR,
    MODE_BALANCED,
    MODE_DLAA,
    ROUGHNESS_PACKED,
    RR_PRESET_F,
    SR_PRESET_L,
    UpscaleMode,
)
from extensions.streamline.options import (
    RayReconstructionOptions,
    SuperResolutionOptions,
)
from extensions.streamline.sizing import FrameSize
from math.matrix4 import Matrix4
from math.vector2 import Vector2
from render.framebuffer import FloatColor
from tests._streamline_scene import (
    constants_for,
    ray_reconstruction_buffers,
    scene_camera,
    super_resolution_buffers,
)

comptime RENDER = FrameSize(6, 4)
comptime OUTPUT = FrameSize(10, 7)


def _word(bytes: List[UInt8], at: Int) -> Int:
    return Int(
        UInt32(bytes[at])
        | (UInt32(bytes[at + 1]) << 8)
        | (UInt32(bytes[at + 2]) << 16)
        | (UInt32(bytes[at + 3]) << 24)
    )


def _float(bytes: List[UInt8], at: Int) -> Float32:
    return bitcast[DType.float32](UInt32(_word(bytes, at)))


def _super_resolution() raises -> SuperResolutionOptions:
    var options = SuperResolutionOptions(
        MODE_BALANCED, OUTPUT.width, OUTPUT.height
    )
    options.use_dlss_4_5(SR_PRESET_L)
    return options^


def _ray_reconstruction() raises -> RayReconstructionOptions:
    var options = RayReconstructionOptions(
        MODE_DLAA, OUTPUT.width, OUTPUT.height
    )
    options.use_dlss_4_5(RR_PRESET_F)
    options.normal_roughness_mode = ROUGHNESS_PACKED
    var camera = scene_camera()
    options.world_to_camera_view = camera.view
    var inverse = camera.view
    inverse.invert()
    options.camera_view_to_world = inverse
    return options^


def test_a_super_resolution_header() raises:
    var options = _super_resolution()
    options.auto_exposure = True
    options.pre_exposure = 2
    var bundle = FrameBundle(options, RENDER, passes=3)
    var camera = scene_camera()
    var constants = constants_for(camera, RENDER, Vector2(0.25, -0.125), True)
    bundle.add(
        constants,
        super_resolution_buffers(constants, RENDER, Vector2(0.25, -0.125)),
    )
    bundle.add(
        constants, super_resolution_buffers(constants, RENDER, Vector2(0, 0))
    )
    assert_equal(bundle.frames, 2)
    var bytes = bundle.encode()
    assert_equal(Int(bytes[0]), ord("T"))
    assert_equal(Int(bytes[3]), ord("L"))
    assert_equal(_word(bytes, 4), 1)
    assert_equal(_word(bytes, 8), 0)
    assert_equal(_word(bytes, 12), MODE_BALANCED.value)
    assert_equal(_word(bytes, 16), SR_PRESET_L.value)
    assert_equal(_word(bytes, 20), 0)
    # Colors are HDR and auto exposure is on.
    assert_equal(_word(bytes, 24), 3)
    assert_equal(_float(bytes, 28), 2)
    assert_equal(_float(bytes, 32), 1)
    assert_equal(_word(bytes, 36), RENDER.width)
    assert_equal(_word(bytes, 40), RENDER.height)
    assert_equal(_word(bytes, 44), OUTPUT.width)
    assert_equal(_word(bytes, 48), OUTPUT.height)
    assert_equal(_word(bytes, 52), 3)
    assert_equal(_word(bytes, 56), 2)
    # Super Resolution has no view matrices: both are the identity.
    assert_equal(_float(bytes, 60), 1)
    assert_equal(_float(bytes, 64), 0)
    assert_equal(_float(bytes, 124 + 60), 1)


def test_a_frame_is_laid_out_as_the_host_reads_it() raises:
    var options = _super_resolution()
    options.colors_are_hdr = False
    options.alpha_upscaling = True
    var bundle = FrameBundle(options, RENDER)
    var camera = scene_camera()
    var offset = Vector2(0.25, -0.125)
    var constants = constants_for(camera, RENDER, offset, True)
    var buffers = super_resolution_buffers(constants, RENDER, offset)
    bundle.add(constants, buffers)
    var bytes = bundle.encode()
    assert_equal(_word(bytes, 24), 4)
    var at = 188
    for index in range(16):
        assert_equal(
            _float(bytes, at + 4 * index),
            constants.camera_view_to_clip.elements[index],
        )
        assert_equal(
            _float(bytes, at + 192 + 4 * index),
            constants.prev_clip_to_clip.elements[index],
        )
    at += 256
    # `frame_constants` negates the offset.
    assert_equal(_float(bytes, at), -0.25)
    assert_equal(_float(bytes, at + 4), 0.125)
    assert_equal(_float(bytes, at + 8), 1.0 / Float32(RENDER.width))
    assert_equal(_float(bytes, at + 16), constants.camera_position.x)
    assert_equal(_float(bytes, at + 52), constants.camera_forward.x)
    assert_equal(_float(bytes, at + 64), Float32(0.1))
    assert_equal(_float(bytes, at + 68), Float32(100))
    assert_equal(_float(bytes, at + 76), constants.camera_aspect)
    at += 80
    # Camera motion is included, and this frame resets the history.
    assert_equal(_word(bytes, at), 2 + 8)
    assert_equal(_word(bytes, at + 4), 3)
    at += 8
    assert_equal(_word(bytes, at), 3)
    assert_equal(_word(bytes, at + 4), RENDER.width)
    assert_equal(_word(bytes, at + 8), RENDER.height)
    assert_equal(_word(bytes, at + 12), 4)
    assert_equal(_float(bytes, at + 16), buffers[0].values[0])
    at += 16 + 4 * len(buffers[0].values)
    assert_equal(_word(bytes, at), 0)
    assert_equal(_word(bytes, at + 12), 1)
    at += 16 + 4 * len(buffers[1].values)
    assert_equal(_word(bytes, at), 1)
    assert_equal(_word(bytes, at + 12), 2)
    at += 16 + 4 * len(buffers[2].values)
    assert_equal(at, len(bytes))


def test_a_ray_reconstruction_header() raises:
    var options = _ray_reconstruction()
    var bundle = FrameBundle(options, RENDER, passes=MOST_PASSES)
    var camera = scene_camera()
    var constants = constants_for(camera, RENDER, Vector2(0, 0), False)
    bundle.add(
        constants,
        ray_reconstruction_buffers(constants, RENDER, Vector2(0, 0), 3),
    )
    var bytes = bundle.encode()
    assert_equal(_word(bytes, 8), 1001)
    assert_equal(_word(bytes, 12), MODE_DLAA.value)
    assert_equal(_word(bytes, 16), RR_PRESET_F.value)
    assert_equal(_word(bytes, 20), ROUGHNESS_PACKED.value)
    assert_equal(_word(bytes, 24), 1)
    assert_equal(_word(bytes, 52), MOST_PASSES)
    for index in range(16):
        assert_equal(
            _float(bytes, 60 + 4 * index),
            options.world_to_camera_view.elements[index],
        )
        assert_equal(
            _float(bytes, 124 + 4 * index),
            options.camera_view_to_world.elements[index],
        )
    # No reset: only camera motion is included.
    assert_equal(_word(bytes, 188 + 336), 2)
    assert_equal(_word(bytes, 188 + 340), 7)


def test_the_bundle_refuses_what_the_host_cannot_run() raises:
    with assert_raises(contains="passes"):
        _ = FrameBundle(_super_resolution(), RENDER, passes=0)
    with assert_raises(contains="passes"):
        _ = FrameBundle(_ray_reconstruction(), RENDER, passes=MOST_PASSES + 1)
    with assert_raises(contains="at least one pixel"):
        _ = FrameBundle(_super_resolution(), FrameSize(0, 4))
    var bad = _super_resolution()
    bad.mode = UpscaleMode(9)
    with assert_raises():
        _ = FrameBundle(bad, RENDER)
    var bad_denoiser = _ray_reconstruction()
    bad_denoiser.camera_view_to_world = Matrix4()
    with assert_raises():
        _ = FrameBundle(bad_denoiser, RENDER)
    with assert_raises(contains="needs a frame"):
        _ = FrameBundle(_super_resolution(), RENDER).encode()


def test_a_frame_must_be_one_streamline_can_run() raises:
    var bundle = FrameBundle(_super_resolution(), RENDER)
    var camera = scene_camera()
    var constants = constants_for(camera, RENDER, Vector2(0, 0), True)
    var good = super_resolution_buffers(constants, RENDER, Vector2(0, 0))

    var output = good.copy()
    output.append(
        BufferData(
            BUFFER_OUTPUT_COLOR,
            OUTPUT.width,
            OUTPUT.height,
            4,
            List[Float32](length=4 * OUTPUT.width * OUTPUT.height, fill=0),
        )
    )
    with assert_raises(contains="host makes the output"):
        bundle.add(constants, output)

    var channels = good.copy()
    channels[1].channels = 0
    with assert_raises(contains="one to four channels"):
        bundle.add(constants, channels)
    channels[1].channels = 5
    with assert_raises(contains="one to four channels"):
        bundle.add(constants, channels)

    var short = good.copy()
    _ = short[1].values.pop()
    with assert_raises(contains="must fill it"):
        bundle.add(constants, short)
    var empty = good.copy()
    empty[1].width = 0
    with assert_raises(contains="must fill it"):
        bundle.add(constants, empty)

    var infinite = good.copy()
    infinite[0].values[5] = nan[DType.float32]()
    with assert_raises(contains="must be finite"):
        bundle.add(constants, infinite)

    var missing = good.copy()
    _ = missing.pop()
    with assert_raises(contains="motion vectors"):
        bundle.add(constants, missing)

    var unsteady = constants.copy()
    unsteady.jitter_offset = Vector2(nan[DType.float32](), 0)
    with assert_raises():
        bundle.add(unsteady, good)
    assert_equal(bundle.frames, 0)

    var denoiser = FrameBundle(_ray_reconstruction(), RENDER)
    var guides = ray_reconstruction_buffers(constants, RENDER, Vector2(0, 0), 0)
    var no_albedo = List[BufferData]()
    for buffer in guides:
        if buffer.kind != BUFFER_ALBEDO:
            no_albedo.append(buffer.copy())
    with assert_raises(contains="albedo"):
        denoiser.add(constants, no_albedo)
    denoiser.add(constants, guides)
    assert_equal(denoiser.frames, 1)


def test_a_buffer_gives_its_tag() raises:
    var buffer = BufferData(
        BUFFER_DEPTH, 3, 2, 1, List[Float32](length=6, fill=0.5)
    )
    var tag = buffer.tag()
    assert_true(tag.kind == BUFFER_DEPTH)
    assert_equal(tag.width, 3)
    assert_equal(tag.height, 2)
    assert_equal(tag.channels, 1)
    assert_false(tag.srgb)


def test_a_result_round_trips() raises:
    var colors = List[FloatColor]()
    for index in range(6):
        colors.append(FloatColor(Float32(index) / 8, 0.5, 1.5, 1))
    var bytes = encode_result(colors, FrameSize(3, 2))
    assert_equal(len(bytes), 16 + 16 * 6)
    assert_equal(Int(bytes[0]), ord("T"))
    assert_equal(Int(bytes[3]), ord("R"))
    var back = decode_result(bytes, FrameSize(3, 2))
    assert_equal(len(back), 6)
    for index in range(6):
        assert_true(back[index] == colors[index])


def test_a_result_must_be_whole_and_finite() raises:
    var colors = List[FloatColor](length=6, fill=FloatColor(0.25, 0.5, 0.75, 1))
    var good = encode_result(colors, FrameSize(3, 2))
    with assert_raises(contains="not a Streamline result"):
        _ = decode_result(List[UInt8](length=8, fill=0), FrameSize(3, 2))
    var magic = good.copy()
    magic[0] = UInt8(ord("X"))
    with assert_raises(contains="not a Streamline result"):
        _ = decode_result(magic, FrameSize(3, 2))
    var version = good.copy()
    version[4] = 2
    with assert_raises(contains="version"):
        _ = decode_result(version, FrameSize(3, 2))
    with assert_raises(contains="not 2 by 3"):
        _ = decode_result(good, FrameSize(2, 3))
    var long = good.copy()
    long.append(0)
    with assert_raises(contains="length"):
        _ = decode_result(long, FrameSize(3, 2))
    var bad = good.copy()
    var at = 16 + 16 * 4 + 8
    var word = bitcast[DType.uint32](nan[DType.float32]())
    for step in range(4):
        bad[at + step] = UInt8((word >> UInt32(8 * step)) & 0xFF)
    with assert_raises(contains="finite"):
        _ = decode_result(bad, FrameSize(3, 2))
    with assert_raises(contains="at least one pixel"):
        _ = encode_result(colors, FrameSize(3, 0))
    with assert_raises(contains="fill the result"):
        _ = encode_result(colors, FrameSize(2, 2))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
