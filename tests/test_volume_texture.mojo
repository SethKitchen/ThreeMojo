# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.volume_texture` and `render.volume_texture_store`:
3D textures and array textures sampled as GLSL's `texture` and
`texelFetch` read a `sampler3D` and a `sampler2DArray`."""

from core.assets import Assets
from render.srgb import LINEAR, SRGB, UNKNOWN_SPACE, srgb_to_linear
from render.texture import (
    BILINEAR,
    CLAMP,
    FLOAT_TYPE,
    MIRROR,
    NEAREST,
    REPEAT,
    UNSIGNED_BYTE_TYPE,
    Filter,
    TexelType,
    Wrap,
)
from render.volume_texture import (
    VOLUME_CHANNELS,
    Data3DTexture,
    DataArrayTexture,
    VolumeImage,
    array_layer,
    mix_straight_texels,
)
from render.volume_texture_store import (
    NO_DATA_3D_TEXTURE,
    NO_DATA_ARRAY_TEXTURE,
    Data3DTextureId,
    Data3DTextureStore,
    DataArrayTextureId,
    DataArrayTextureStore,
)
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

comptime TOLERANCE = Float64(1e-5)


def cube_of_floats() raises -> VolumeImage:
    """Return a 2x2x2 float image whose red is its index, 0 through 7:
    `x + 2y + 4z`. Green is minus that, alpha one."""
    var data = List[Float32]()
    for index in range(8):
        data.append(Float32(index))
        data.append(-Float32(index))
    return VolumeImage.of_floats(2, 2, 2, data, 2)


def assert_close(
    got: FloatColor, r: Float32, g: Float32, b: Float32, a: Float32
) raises:
    """Assert every channel of `got` is within the tolerance."""
    assert_almost_equal(got.r, r, atol=TOLERANCE)
    assert_almost_equal(got.g, g, atol=TOLERANCE)
    assert_almost_equal(got.b, b, atol=TOLERANCE)
    assert_almost_equal(got.a, a, atol=TOLERANCE)


# --- the image --------------------------------------------------------------


def test_bytes_fill_red_first_and_alpha_is_opaque() raises:
    var one = VolumeImage.of_bytes(1, 1, 2, [10, 20], 1)
    assert_true(one.texel_type == UNSIGNED_BYTE_TYPE)
    assert_equal(len(one.pixels), 2 * VOLUME_CHANNELS)
    assert_equal(len(one.data), 0)
    assert_equal(one.pixels[0], 10)
    assert_equal(one.pixels[1], 0)
    assert_equal(one.pixels[2], 0)
    assert_equal(one.pixels[3], 255)
    assert_equal(one.pixels[4], 20)
    var full = VolumeImage.of_bytes(1, 1, 1, [1, 2, 3, 4])
    assert_equal(full.pixels[3], 4)


def test_floats_fill_red_first_and_alpha_is_one() raises:
    var image = VolumeImage.of_floats(1, 1, 1, [2.5, 3.0], 2)
    assert_true(image.texel_type == FLOAT_TYPE)
    assert_equal(len(image.pixels), 0)
    assert_equal(image.data[0], 2.5)
    assert_equal(image.data[1], 3.0)
    assert_equal(image.data[2], 0.0)
    assert_equal(image.data[3], 1.0)


def test_an_image_refuses_what_it_cannot_hold() raises:
    with assert_raises(contains="dimensions must be positive"):
        _ = VolumeImage.of_bytes(0, 1, 1, List[UInt8]())
    with assert_raises(contains="dimensions must be positive"):
        _ = VolumeImage.of_bytes(1, 0, 1, List[UInt8]())
    with assert_raises(contains="dimensions must be positive"):
        _ = VolumeImage.of_floats(1, 1, 0, List[Float32]())
    with assert_raises(contains="one through four"):
        _ = VolumeImage.of_bytes(1, 1, 1, [1], 0)
    with assert_raises(contains="one through four"):
        _ = VolumeImage.of_floats(1, 1, 1, [1, 1, 1, 1, 1], 5)
    with assert_raises(contains="does not match"):
        _ = VolumeImage.of_bytes(1, 1, 2, [1, 2, 3, 4])
    with assert_raises(contains="does not match"):
        _ = VolumeImage.of_floats(2, 1, 1, [1, 2, 3, 4])
    with assert_raises(contains="finite"):
        _ = VolumeImage.of_floats(1, 1, 1, [nan[DType.float32]()], 1)
    with assert_raises(contains="finite"):
        _ = VolumeImage.of_floats(1, 1, 1, [0, inf[DType.float32]()], 2)


def test_an_image_edited_into_nonsense_is_refused() raises:
    var image = VolumeImage.of_bytes(1, 1, 1, [1, 2, 3, 4])
    image.validate()
    image.texel_type = TexelType(5)
    with assert_raises(contains="texel type"):
        image.validate()
    image.texel_type = FLOAT_TYPE
    with assert_raises(contains="does not match"):
        image.validate()
    var floats = cube_of_floats()
    floats.validate()
    floats.depth = 3
    with assert_raises(contains="does not match"):
        floats.validate()
    floats.depth = -1
    with assert_raises(contains="positive"):
        floats.validate()


# --- the 3D texture ---------------------------------------------------------


def test_a_3d_texture_takes_three_js_defaults() raises:
    var volume = Data3DTexture(cube_of_floats())
    assert_true(volume.wrap_s == CLAMP)
    assert_true(volume.wrap_t == CLAMP)
    assert_true(volume.wrap_r == CLAMP)
    assert_true(volume.filter == NEAREST)
    assert_true(volume.color_space == LINEAR)
    var copy = Data3DTexture(copy=volume)
    volume.image.data[28] = 0
    assert_equal(volume.image.data[28], 0.0)
    assert_equal(copy.image.depth, 2)
    assert_equal(copy.image.data[28], 7.0)
    assert_true(copy.wrap_r == CLAMP)


def test_a_3d_texture_refuses_modes_no_sampler_has() raises:
    var volume = Data3DTexture(cube_of_floats())
    volume.wrap_s = Wrap(7)
    with assert_raises(contains="wrap modes"):
        volume.validate()
    volume.wrap_s = CLAMP
    volume.wrap_t = Wrap(7)
    with assert_raises(contains="wrap modes"):
        volume.validate()
    volume.wrap_t = CLAMP
    volume.wrap_r = Wrap(7)
    with assert_raises(contains="wrap modes"):
        volume.validate()
    volume.wrap_r = CLAMP
    volume.filter = Filter(4)
    with assert_raises(contains="filter"):
        volume.validate()
    volume.filter = NEAREST
    volume.color_space = UNKNOWN_SPACE
    with assert_raises(contains="color space"):
        volume.validate()
    volume.color_space = LINEAR
    volume.image.width = 0
    with assert_raises(contains="positive"):
        volume.validate()
    with assert_raises(contains="must be LINEAR"):
        _ = Data3DTexture(cube_of_floats(), color_space=SRGB)


def test_texel_fetch_reads_by_index_and_refuses_outside() raises:
    var volume = Data3DTexture(cube_of_floats())
    # x + 2y + 4z: rows run up as stored, with no flip.
    assert_close(volume.texel_fetch(1, 0, 1), 5, -5, 0, 1)
    assert_close(volume.texel_fetch(0, 1, 0), 2, -2, 0, 1)
    with assert_raises(contains="out of bounds"):
        _ = volume.texel_fetch(-1, 0, 0)
    with assert_raises(contains="out of bounds"):
        _ = volume.texel_fetch(2, 0, 0)
    with assert_raises(contains="out of bounds"):
        _ = volume.texel_fetch(0, -1, 0)
    with assert_raises(contains="out of bounds"):
        _ = volume.texel_fetch(0, 2, 0)
    with assert_raises(contains="out of bounds"):
        _ = volume.texel_fetch(0, 0, -1)
    with assert_raises(contains="out of bounds"):
        _ = volume.texel_fetch(0, 0, 2)


def test_bytes_read_as_fractions_and_srgb_decodes_color_only() raises:
    var linear = Data3DTexture(VolumeImage.of_bytes(1, 1, 1, [51, 102, 0, 128]))
    assert_close(linear.texel_fetch(0, 0, 0), 0.2, 0.4, 0, 128.0 / 255)
    var srgb = Data3DTexture(
        VolumeImage.of_bytes(1, 1, 1, [51, 102, 0, 128]), color_space=SRGB
    )
    assert_close(
        srgb.texel_fetch(0, 0, 0),
        srgb_to_linear(0.2),
        srgb_to_linear(0.4),
        0,
        128.0 / 255,
    )


def test_nearest_takes_the_texel_a_coordinate_lands_in() raises:
    var volume = Data3DTexture(cube_of_floats())
    assert_close(volume.sample(0.25, 0.25, 0.25), 0, 0, 0, 1)
    assert_close(volume.sample(0.75, 0.25, 0.75), 5, -5, 0, 1)
    assert_close(volume.sample(0.25, 0.75, 0.25), 2, -2, 0, 1)
    # Clamped, past the far edge reads the last texel.
    assert_close(volume.sample(1.5, 1.5, 1.5), 7, -7, 0, 1)
    # Repeated deep only, 1.25 reads the first slice again.
    volume.wrap_r = REPEAT
    assert_close(volume.sample(0.25, 0.25, 1.25), 0, 0, 0, 1)


def test_bilinear_blends_the_eight_around_the_coordinate() raises:
    var volume = Data3DTexture(cube_of_floats(), filter=BILINEAR)
    # At the center of the cube, the mean of 0 through 7.
    assert_close(volume.sample(0.5, 0.5, 0.5), 3.5, -3.5, 0, 1)
    # At a texel center, that texel.
    assert_close(volume.sample(0.75, 0.25, 0.75), 5, -5, 0, 1)
    # A quarter of the way from slice 0 to slice 1 at the first texel.
    assert_close(volume.sample(0.25, 0.25, 0.375), 1, -1, 0, 1)
    # Clamped past the edge, the edge texel.
    assert_close(volume.sample(-3, 0.25, 0.25), 0, 0, 0, 1)
    # Mirrored deep, -0.75 folds back onto the second slice.
    volume.wrap_r = MIRROR
    assert_close(volume.sample(0.25, 0.25, -0.75), 4, -4, 0, 1)


def test_filtering_is_straight_so_a_clear_texel_keeps_its_color() raises:
    var image = VolumeImage.of_floats(2, 1, 1, [1, 0, 0, 0, 0, 0, 1, 1])
    var volume = Data3DTexture(image^, filter=BILINEAR)
    # A premultiplied blend would give no red at all.
    assert_close(volume.sample(0.5, 0.5, 0.5), 0.5, 0, 0.5, 0.5)
    assert_close(
        mix_straight_texels(
            FloatColor(0, 0, 0, 0), FloatColor(1, 2, 3, 4), 0.25
        ),
        0.25,
        0.5,
        0.75,
        1,
    )


# --- the array texture ------------------------------------------------------


def test_a_layer_rounds_to_the_nearest_and_stays_inside() raises:
    assert_equal(array_layer(-1, 3), 0)
    assert_equal(array_layer(0.49, 3), 0)
    assert_equal(array_layer(0.5, 3), 1)
    assert_equal(array_layer(1.6, 3), 2)
    assert_equal(array_layer(9, 3), 2)


def test_an_array_texture_samples_one_layer_at_a_time() raises:
    var stack = DataArrayTexture(cube_of_floats())
    assert_equal(stack.layers(), 2)
    assert_true(stack.wrap_s == CLAMP)
    assert_true(stack.filter == NEAREST)
    assert_close(stack.sample(0.75, 0.75, 0), 3, -3, 0, 1)
    assert_close(stack.sample(0.75, 0.75, 1), 7, -7, 0, 1)
    # Half way between layers rounds up; never a blend.
    assert_close(stack.sample(0.25, 0.25, 0.5), 4, -4, 0, 1)
    assert_close(stack.texel_fetch(1, 0, 1), 5, -5, 0, 1)
    with assert_raises(contains="out of bounds"):
        _ = stack.texel_fetch(0, 0, 2)
    stack.filter = BILINEAR
    # The middle of layer one: the mean of 4 through 7.
    assert_close(stack.sample(0.5, 0.5, 1), 5.5, -5.5, 0, 1)
    stack.wrap_s = REPEAT
    # Repeated across, the left edge blends the last column with the first.
    assert_close(stack.sample(0, 0.25, 0), 0.5, -0.5, 0, 1)
    var copy = DataArrayTexture(copy=stack)
    # The copy owns its texels: changing the original leaves it alone.
    stack.image.data[0] = 100
    assert_equal(copy.image.data[0], 0.0)
    assert_true(copy.wrap_s == REPEAT)
    assert_true(copy.filter == BILINEAR)
    assert_equal(copy.layers(), 2)
    assert_equal(stack.image.data[0], 100.0)


def test_an_array_texture_refuses_modes_no_sampler_has() raises:
    var stack = DataArrayTexture(cube_of_floats())
    stack.wrap_s = Wrap(3)
    with assert_raises(contains="wrap modes"):
        stack.validate()
    stack.wrap_s = CLAMP
    stack.wrap_t = Wrap(3)
    with assert_raises(contains="wrap modes"):
        stack.validate()
    stack.wrap_t = CLAMP
    stack.validate()
    with assert_raises(contains="filter"):
        _ = DataArrayTexture(cube_of_floats(), filter=Filter(2))


# --- the stores -------------------------------------------------------------


def test_the_stores_hand_out_ids_and_refuse_unknown_ones() raises:
    var volumes = Data3DTextureStore()
    assert_equal(volumes.count(), 0)
    var first = volumes.add(Data3DTexture(cube_of_floats()))
    var second = volumes.add(
        Data3DTexture(VolumeImage.of_bytes(1, 1, 1, [9], 1))
    )
    assert_equal(first, Data3DTextureId(0))
    assert_equal(second, Data3DTextureId(1))
    assert_equal(volumes.count(), 2)
    assert_equal(volumes.get(second).image.pixels[0], 9)
    with assert_raises(contains="No 3D texture"):
        _ = volumes.get(NO_DATA_3D_TEXTURE).image.width
    with assert_raises(contains="No 3D texture"):
        _ = volumes.get(Data3DTextureId(2)).image.width
    var stacks = DataArrayTextureStore()
    assert_equal(stacks.count(), 0)
    var stack = stacks.add(DataArrayTexture(cube_of_floats()))
    assert_equal(stack, DataArrayTextureId(0))
    assert_equal(stacks.count(), 1)
    assert_equal(stacks.get(stack).layers(), 2)
    with assert_raises(contains="No array texture"):
        _ = stacks.get(NO_DATA_ARRAY_TEXTURE).image.width
    with assert_raises(contains="No array texture"):
        _ = stacks.get(DataArrayTextureId(1)).image.width


def test_assets_start_with_empty_volume_stores() raises:
    var assets = Assets()
    assert_equal(assets.data_3d_textures.count(), 0)
    assert_equal(assets.data_array_textures.count(), 0)
    _ = assets.data_array_textures.add(DataArrayTexture(cube_of_floats()))
    assert_equal(assets.data_array_textures.count(), 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
