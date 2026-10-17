# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the check of a frame's tagged buffers: what each feature
needs, and the size, the channels and the encoding of each buffer."""

from extensions.streamline.kinds import (
    BUFFER_ALBEDO,
    BUFFER_COLOR_BEFORE_TRANSPARENCY,
    BUFFER_DEPTH,
    BUFFER_DEPTH_OF_FIELD_GUIDE,
    BUFFER_EXPOSURE,
    BUFFER_INPUT_COLOR,
    BUFFER_LINEAR_DEPTH,
    BUFFER_MOTION_VECTORS,
    BUFFER_NORMALS,
    BUFFER_NORMAL_ROUGHNESS,
    BUFFER_OUTPUT_COLOR,
    BUFFER_ROUGHNESS,
    BUFFER_SPECULAR_ALBEDO,
    BUFFER_SPECULAR_HIT_DISTANCE,
    BUFFER_SPECULAR_MOTION_VECTORS,
    BUFFER_SUBSURFACE_GUIDE,
    BUFFER_TRANSPARENCY_LAYER,
    BUFFER_TRANSPARENCY_LAYER_OPACITY,
    BufferKind,
    MODE_BALANCED,
    ROUGHNESS_PACKED,
)
from extensions.streamline.options import (
    RayReconstructionOptions,
    SuperResolutionOptions,
)
from extensions.streamline.sizing import FrameSize
from extensions.streamline.tags import (
    TaggedBuffer,
    check_ray_reconstruction_tags,
    check_super_resolution_tags,
)
from std.testing import (
    TestSuite,
    assert_equal,
    assert_raises,
)


comptime RENDER = FrameSize(1280, 720)
comptime OUTPUT = FrameSize(1920, 1080)


def render_buffer(kind: BufferKind, channels: Int) -> TaggedBuffer:
    """Return a buffer at the render size."""
    return TaggedBuffer(kind, RENDER.width, RENDER.height, channels, False)


def output_buffer() -> TaggedBuffer:
    """Return the output color."""
    return TaggedBuffer(
        BUFFER_OUTPUT_COLOR, OUTPUT.width, OUTPUT.height, 4, False
    )


def super_resolution_tags() -> List[TaggedBuffer]:
    """Return the buffers that Super Resolution needs."""
    var tags = List[TaggedBuffer]()
    tags.append(render_buffer(BUFFER_DEPTH, 1))
    tags.append(render_buffer(BUFFER_MOTION_VECTORS, 2))
    tags.append(render_buffer(BUFFER_INPUT_COLOR, 4))
    tags.append(output_buffer())
    return tags^


def ray_reconstruction_tags() -> List[TaggedBuffer]:
    """Return the buffers that Ray Reconstruction needs in the unpacked
    mode."""
    var tags = List[TaggedBuffer]()
    tags.append(render_buffer(BUFFER_DEPTH, 1))
    tags.append(render_buffer(BUFFER_MOTION_VECTORS, 2))
    tags.append(render_buffer(BUFFER_INPUT_COLOR, 4))
    tags.append(render_buffer(BUFFER_ALBEDO, 4))
    tags.append(render_buffer(BUFFER_SPECULAR_ALBEDO, 4))
    tags.append(render_buffer(BUFFER_NORMALS, 4))
    tags.append(render_buffer(BUFFER_ROUGHNESS, 1))
    tags.append(render_buffer(BUFFER_SPECULAR_MOTION_VECTORS, 2))
    tags.append(output_buffer())
    return tags^


def without(tags: List[TaggedBuffer], kind: BufferKind) -> List[TaggedBuffer]:
    """Return the tags less the buffer of a kind."""
    var kept = List[TaggedBuffer]()
    for buffer in tags:
        if buffer.kind != kind:
            kept.append(buffer.copy())
    return kept^


def super_resolution() -> SuperResolutionOptions:
    return SuperResolutionOptions(MODE_BALANCED, OUTPUT.width, OUTPUT.height)


def ray_reconstruction() -> RayReconstructionOptions:
    return RayReconstructionOptions(MODE_BALANCED, OUTPUT.width, OUTPUT.height)


def test_super_resolution_accepts_the_buffers_it_needs() raises:
    check_super_resolution_tags(
        super_resolution(), RENDER, super_resolution_tags()
    )
    var tags = super_resolution_tags()
    tags.append(TaggedBuffer(BUFFER_EXPOSURE, 1, 1, 1, False))
    check_super_resolution_tags(super_resolution(), RENDER, tags)


def test_super_resolution_needs_four_buffers() raises:
    for kind in [
        BUFFER_DEPTH,
        BUFFER_MOTION_VECTORS,
        BUFFER_INPUT_COLOR,
        BUFFER_OUTPUT_COLOR,
    ]:
        with assert_raises(contains=kind.name()):
            check_super_resolution_tags(
                super_resolution(),
                RENDER,
                without(super_resolution_tags(), kind),
            )


def test_a_frame_that_tags_nothing_is_refused() raises:
    var none = List[TaggedBuffer]()
    with assert_raises(contains="depth buffer is not tagged"):
        check_super_resolution_tags(super_resolution(), RENDER, none)
    with assert_raises(contains="input color buffer is not tagged"):
        check_ray_reconstruction_tags(ray_reconstruction(), RENDER, none)


def test_super_resolution_checks_its_options_first() raises:
    var options = super_resolution()
    options.output_width = 0
    with assert_raises(contains="width"):
        check_super_resolution_tags(options, RENDER, super_resolution_tags())


def test_a_buffer_of_an_unnamed_kind_is_refused() raises:
    var tags = super_resolution_tags()
    tags.append(TaggedBuffer(BufferKind(18), 1280, 720, 1, False))
    with assert_raises(contains="eighteen"):
        check_super_resolution_tags(super_resolution(), RENDER, tags)
    tags = super_resolution_tags()
    tags.append(TaggedBuffer(BufferKind(-1), 1280, 720, 1, False))
    with assert_raises(contains="eighteen"):
        check_super_resolution_tags(super_resolution(), RENDER, tags)


def test_a_kind_tagged_twice_is_refused() raises:
    var tags = super_resolution_tags()
    tags.append(render_buffer(BUFFER_DEPTH, 1))
    with assert_raises(contains="depth buffer is tagged twice"):
        check_super_resolution_tags(super_resolution(), RENDER, tags)


def test_each_buffer_has_the_size_of_its_kind() raises:
    var tags = super_resolution_tags()
    tags[0].width = 1281
    with assert_raises(contains="1280 by 720"):
        check_super_resolution_tags(super_resolution(), RENDER, tags)
    tags = super_resolution_tags()
    tags[0].height = 721
    with assert_raises(contains="1280 by 720"):
        check_super_resolution_tags(super_resolution(), RENDER, tags)
    # The output color is the output's size, and not the render's.
    tags = super_resolution_tags()
    tags[3].width = RENDER.width
    tags[3].height = RENDER.height
    with assert_raises(contains="1920 by 1080"):
        check_super_resolution_tags(super_resolution(), RENDER, tags)
    # The exposure is one texel.
    tags = super_resolution_tags()
    tags.append(render_buffer(BUFFER_EXPOSURE, 1))
    with assert_raises(contains="1 by 1"):
        check_super_resolution_tags(super_resolution(), RENDER, tags)


def test_each_buffer_has_the_channels_of_its_kind() raises:
    var tags = super_resolution_tags()
    tags[1].channels = 1
    with assert_raises(contains="motion vectors buffer has the wrong"):
        check_super_resolution_tags(super_resolution(), RENDER, tags)
    tags[1].channels = 3
    with assert_raises(contains="motion vectors buffer has the wrong"):
        check_super_resolution_tags(super_resolution(), RENDER, tags)
    tags = super_resolution_tags()
    tags[2].channels = 2
    with assert_raises(contains="input color buffer has the wrong"):
        check_super_resolution_tags(super_resolution(), RENDER, tags)
    tags[2].channels = 5
    with assert_raises(contains="input color buffer has the wrong"):
        check_super_resolution_tags(super_resolution(), RENDER, tags)
    tags[2].channels = 3
    check_super_resolution_tags(super_resolution(), RENDER, tags)


def test_every_kind_accepts_the_channels_the_guides_name() raises:
    var tags = super_resolution_tags()
    var one: List[BufferKind] = [
        BUFFER_LINEAR_DEPTH,
        BUFFER_SPECULAR_HIT_DISTANCE,
        BUFFER_ROUGHNESS,
        BUFFER_TRANSPARENCY_LAYER_OPACITY,
        BUFFER_SUBSURFACE_GUIDE,
        BUFFER_DEPTH_OF_FIELD_GUIDE,
    ]
    for kind in one:
        tags.append(render_buffer(kind, 1))
    tags.append(render_buffer(BUFFER_SPECULAR_MOTION_VECTORS, 2))
    tags.append(render_buffer(BUFFER_ALBEDO, 3))
    tags.append(render_buffer(BUFFER_SPECULAR_ALBEDO, 4))
    tags.append(render_buffer(BUFFER_NORMALS, 3))
    tags.append(render_buffer(BUFFER_NORMAL_ROUGHNESS, 4))
    tags.append(render_buffer(BUFFER_TRANSPARENCY_LAYER, 4))
    tags.append(render_buffer(BUFFER_COLOR_BEFORE_TRANSPARENCY, 3))
    check_super_resolution_tags(super_resolution(), RENDER, tags)
    var wrong = super_resolution_tags()
    wrong.append(render_buffer(BUFFER_NORMAL_ROUGHNESS, 3))
    with assert_raises(contains="normal and roughness buffer has the wrong"):
        check_super_resolution_tags(super_resolution(), RENDER, wrong)
    wrong = super_resolution_tags()
    wrong.append(render_buffer(BUFFER_ROUGHNESS, 2))
    with assert_raises(contains="roughness buffer has the wrong"):
        check_super_resolution_tags(super_resolution(), RENDER, wrong)


def test_an_albedo_is_not_srgb() raises:
    var tags = ray_reconstruction_tags()
    tags[3].srgb = True
    with assert_raises(contains="albedo buffer must be linear"):
        check_ray_reconstruction_tags(ray_reconstruction(), RENDER, tags)
    tags = ray_reconstruction_tags()
    tags[4].srgb = True
    with assert_raises(contains="specular albedo buffer must be linear"):
        check_ray_reconstruction_tags(ray_reconstruction(), RENDER, tags)
    # A color buffer may be sRGB: only an albedo is refused.
    tags = ray_reconstruction_tags()
    tags[2].srgb = True
    check_ray_reconstruction_tags(ray_reconstruction(), RENDER, tags)


def test_ray_reconstruction_accepts_the_buffers_it_needs() raises:
    check_ray_reconstruction_tags(
        ray_reconstruction(), RENDER, ray_reconstruction_tags()
    )
    # The linear depth does for the depth.
    var tags = without(ray_reconstruction_tags(), BUFFER_DEPTH)
    tags.append(render_buffer(BUFFER_LINEAR_DEPTH, 1))
    check_ray_reconstruction_tags(ray_reconstruction(), RENDER, tags)
    # The hit distance does for the specular motion vectors.
    tags = without(ray_reconstruction_tags(), BUFFER_SPECULAR_MOTION_VECTORS)
    tags.append(render_buffer(BUFFER_SPECULAR_HIT_DISTANCE, 1))
    check_ray_reconstruction_tags(ray_reconstruction(), RENDER, tags)


def test_ray_reconstruction_needs_its_buffers() raises:
    for kind in [
        BUFFER_INPUT_COLOR,
        BUFFER_OUTPUT_COLOR,
        BUFFER_MOTION_VECTORS,
        BUFFER_ALBEDO,
        BUFFER_SPECULAR_ALBEDO,
        BUFFER_NORMALS,
        BUFFER_ROUGHNESS,
    ]:
        with assert_raises(contains=kind.name()):
            check_ray_reconstruction_tags(
                ray_reconstruction(),
                RENDER,
                without(ray_reconstruction_tags(), kind),
            )


def test_ray_reconstruction_needs_a_depth_of_some_kind() raises:
    with assert_raises(contains="depth or the linear depth"):
        check_ray_reconstruction_tags(
            ray_reconstruction(),
            RENDER,
            without(ray_reconstruction_tags(), BUFFER_DEPTH),
        )


def test_ray_reconstruction_needs_a_specular_motion_of_some_kind() raises:
    with assert_raises(contains="specular motion vectors or the specular hit"):
        check_ray_reconstruction_tags(
            ray_reconstruction(),
            RENDER,
            without(ray_reconstruction_tags(), BUFFER_SPECULAR_MOTION_VECTORS),
        )


def test_the_packed_mode_wants_the_normals_with_the_roughness() raises:
    var options = ray_reconstruction()
    options.normal_roughness_mode = ROUGHNESS_PACKED
    var tags = without(ray_reconstruction_tags(), BUFFER_NORMALS)
    tags = without(tags, BUFFER_ROUGHNESS)
    with assert_raises(contains="normal and roughness buffer is not tagged"):
        check_ray_reconstruction_tags(options, RENDER, tags)
    tags.append(render_buffer(BUFFER_NORMAL_ROUGHNESS, 4))
    check_ray_reconstruction_tags(options, RENDER, tags)


def test_the_unpacked_mode_refuses_the_packed_buffer() raises:
    var tags = ray_reconstruction_tags()
    tags.append(render_buffer(BUFFER_NORMAL_ROUGHNESS, 4))
    with assert_raises(contains="needs the packed mode"):
        check_ray_reconstruction_tags(ray_reconstruction(), RENDER, tags)


def test_ray_reconstruction_checks_its_options_first() raises:
    var options = ray_reconstruction()
    options.output_height = 0
    with assert_raises(contains="height"):
        check_ray_reconstruction_tags(
            options, RENDER, ray_reconstruction_tags()
        )


def test_a_buffer_keeps_what_it_was_given() raises:
    var buffer = render_buffer(BUFFER_ALBEDO, 3)
    assert_equal(buffer.kind, BUFFER_ALBEDO)
    assert_equal(buffer.width, 1280)
    assert_equal(buffer.height, 720)
    assert_equal(buffer.channels, 3)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
