# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.texture_copy`: texture to texture, texture to volume,
volume to volume, and framebuffer to texture."""

from render.framebuffer import Color, FloatColor, Framebuffer
from render.rect import Rect
from render.srgb import LINEAR, SRGB, UNKNOWN_SPACE
from render.target import FLOAT_TARGET, HALF_FLOAT_TARGET, RenderTarget
from render.texture import (
    FLOAT_TYPE,
    NEAREST,
    TexelType,
    Texture,
    UNSIGNED_BYTE_TYPE,
    float_texture,
)
from render.texture_copy import (
    TexelBox,
    TexelPoint,
    copy_framebuffer_to_texture,
    copy_texture_to_texture,
    copy_texture_to_volume,
    copy_volume_to_volume,
    framebuffer_texture,
)
from render.volume_texture import VolumeImage
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def counting(width: Int, height: Int, flip_y: Bool = True) raises -> Texture:
    """Return a byte texture whose texel `i` in stored order has red `i`,
    no chain, `LINEAR`."""
    var pixels = List[UInt8]()
    for index in range(width * height):
        pixels.append(UInt8(index))
        pixels.append(0)
        pixels.append(0)
        pixels.append(255)
    var texture = Texture(
        width,
        height,
        pixels^,
        filter=NEAREST,
        color_space=LINEAR,
        mipmapped=False,
    )
    texture.flip_y = flip_y
    return texture^


def red_at(texture: Texture, x: Int, stored_row: Int) -> Int:
    """Return the red byte of a stored texel of the first level."""
    return Int(texture.pixels[(stored_row * texture.width + x) * 4])


def test_a_texel_box_holds_texels() raises:
    assert_true(TexelBox(0, 0, 0, 1, 1, 1).is_valid())
    assert_false(TexelBox(0, 0, 0, 0, 1, 1).is_valid())
    assert_false(TexelBox(0, 0, 0, 1, 0, 1).is_valid())
    assert_false(TexelBox(0, 0, 0, 1, 1, 0).is_valid())
    assert_true(TexelPoint(1, 2, 3) == TexelPoint(1, 2, 3))


def test_a_rectangle_is_copied_in_webgl_rows() raises:
    # Source 4x2 flipped: WebGL row 0 is the last stored row.
    var source = counting(4, 2)
    var destination = counting(4, 4, flip_y=False)
    copy_texture_to_texture(
        source, destination, Rect(1, 0, 2, 1), TexelPoint(0, 3, 0)
    )
    # Source texels 5 and 6 (stored row 1) land on stored row 3.
    assert_equal(red_at(destination, 0, 3), 5)
    assert_equal(red_at(destination, 1, 3), 6)
    assert_equal(red_at(destination, 2, 3), 14)
    # The whole source by default. The destination is not flipped, so the
    # source's rows land upside down in storage.
    var whole = counting(4, 2, flip_y=False)
    copy_texture_to_texture(source, whole)
    assert_equal(red_at(whole, 3, 0), 7)
    assert_equal(red_at(whole, 3, 1), 3)


def test_a_copy_into_the_first_level_rebuilds_the_chain() raises:
    var source = Texture(
        2,
        2,
        List[UInt8](length=16, fill=255),
        filter=NEAREST,
        color_space=LINEAR,
        mipmapped=False,
    )
    var destination = Texture(
        2, 2, List[UInt8](length=16, fill=0), color_space=LINEAR
    )
    assert_equal(destination.levels, 2)
    copy_texture_to_texture(source, destination)
    assert_equal(destination.levels, 2)
    assert_almost_equal(destination.wrapped_texel(0, 0, 1).r, 1)
    # A copy into the second level leaves the first alone.
    var dark = Texture(
        1,
        1,
        List[UInt8](length=4, fill=0),
        filter=NEAREST,
        color_space=LINEAR,
        mipmapped=False,
    )
    copy_texture_to_texture(dark, destination, destination_level=1)
    assert_almost_equal(destination.wrapped_texel(0, 0, 1).r, 0)
    assert_almost_equal(destination.wrapped_texel(0, 0, 0).r, 1)
    # And the chain can be read from a level below the first.
    var small = counting(1, 1)
    copy_texture_to_texture(destination, small, source_level=1)
    assert_equal(red_at(small, 0, 0), 0)
    # A texture with no chain regenerates nothing.
    small.regenerate_mipmaps()
    assert_equal(small.levels, 1)


def test_float_texels_are_copied_as_floats() raises:
    var source = float_texture(1, 1, [Float32(3), 2, 1, 1])
    var destination = float_texture(
        2, 2, List[Float32](length=16, fill=0), mipmapped=True
    )
    copy_texture_to_texture(source, destination, None, TexelPoint(1, 1, 0))
    assert_almost_equal(destination.data[4], 3)
    assert_equal(destination.levels, 2)
    # The chain is rebuilt: a quarter of the coverage, the color kept.
    assert_almost_equal(destination.data[16], 3)
    assert_almost_equal(destination.data[19], 0.25)


def test_a_copy_that_cannot_be_made_is_refused() raises:
    var bytes = counting(2, 2)
    var floats = float_texture(2, 2, List[Float32](length=16, fill=0))
    with assert_raises(contains="one texel type"):
        copy_texture_to_texture(bytes, floats)
    with assert_raises(contains="holds texels"):
        copy_texture_to_texture(Texture(), floats)
    with assert_raises(contains="does not hold"):
        copy_texture_to_texture(bytes, floats, source_level=1)
    with assert_raises(contains="does not hold"):
        copy_texture_to_texture(bytes, floats, source_level=-1)
    var other = counting(2, 2)
    with assert_raises(contains="no layers"):
        copy_texture_to_texture(bytes, other, None, TexelPoint(0, 0, 1))
    with assert_raises(contains="inside both images"):
        copy_texture_to_texture(bytes, other, Rect(1, 0, 2, 1))
    with assert_raises(contains="inside both images"):
        copy_texture_to_texture(bytes, other, None, TexelPoint(1, 0, 0))
    var broken = counting(2, 2)
    broken.color_space = UNKNOWN_SPACE
    with assert_raises(contains="color space"):
        copy_texture_to_texture(broken, other)


def a_volume(width: Int, height: Int, depth: Int) raises -> VolumeImage:
    """Return a byte volume whose texel `i` has red `i`."""
    var pixels = List[UInt8]()
    for index in range(width * height * depth):
        pixels.append(UInt8(index))
    return VolumeImage.of_bytes(width, height, depth, pixels, 1)


def test_a_texture_is_copied_into_a_layer() raises:
    var source = counting(2, 2)
    var volume = a_volume(3, 3, 2)
    copy_texture_to_volume(
        source, volume, Rect(0, 1, 2, 1), TexelPoint(1, 2, 1)
    )
    # WebGL row 1 of a flipped texture is stored row 0: texels 0 and 1.
    var at = ((1 * 3 + 2) * 3 + 1) * 4
    assert_equal(volume.pixels[at], 0)
    assert_equal(volume.pixels[at + 4], 1)
    copy_texture_to_volume(source, volume)
    assert_equal(volume.pixels[4], 3)
    var floats = VolumeImage.of_floats(
        2, 2, 1, List[Float32](length=4, fill=0), 1
    )
    copy_texture_to_volume(
        float_texture(1, 1, [Float32(5), 0, 0, 1]),
        floats,
        None,
        TexelPoint(1, 1, 0),
    )
    assert_almost_equal(floats.data[12], 5)
    with assert_raises(contains="one texel type"):
        copy_texture_to_volume(source, floats)
    with assert_raises(contains="inside both images"):
        copy_texture_to_volume(source, volume, None, TexelPoint(0, 0, 2))
    with assert_raises(contains="inside both images"):
        copy_texture_to_volume(source, volume, None, TexelPoint(0, 0, -1))
    with assert_raises(contains="inside both images"):
        copy_texture_to_volume(source, volume, Rect(0, 0, 3, 1))
    with assert_raises(contains="inside both images"):
        copy_texture_to_volume(source, volume, None, TexelPoint(2, 0, 0))
    var bad = a_volume(2, 2, 1)
    bad.depth = 3
    with assert_raises(contains="does not match"):
        copy_texture_to_volume(source, bad)


def test_a_block_is_copied_between_volumes() raises:
    var source = a_volume(2, 2, 2)
    var destination = a_volume(3, 3, 3)
    copy_volume_to_volume(
        source, destination, TexelBox(1, 0, 1, 1, 2, 1), TexelPoint(0, 1, 2)
    )
    # Source texels (1, 0, 1) = 5 and (1, 1, 1) = 7.
    assert_equal(destination.pixels[((2 * 3 + 1) * 3 + 0) * 4], 5)
    assert_equal(destination.pixels[((2 * 3 + 2) * 3 + 0) * 4], 7)
    copy_volume_to_volume(source, destination)
    assert_equal(destination.pixels[((1 * 3 + 1) * 3 + 1) * 4], 7)
    var floats = VolumeImage.of_floats(1, 1, 2, [Float32(1), 2], 1)
    var into = VolumeImage.of_floats(1, 1, 2, [Float32(0), 0], 1)
    copy_volume_to_volume(
        floats, into, TexelBox(0, 0, 1, 1, 1, 1), TexelPoint(0, 0, 0)
    )
    assert_almost_equal(into.data[0], 2)
    with assert_raises(contains="one texel type"):
        copy_volume_to_volume(source, into)
    with assert_raises(contains="inside both images"):
        copy_volume_to_volume(source, destination, TexelBox(0, 0, 0, 0, 1, 1))
    with assert_raises(contains="inside both images"):
        copy_volume_to_volume(source, destination, TexelBox(0, 0, -1, 1, 1, 1))
    with assert_raises(contains="inside both images"):
        copy_volume_to_volume(source, destination, TexelBox(0, 0, 1, 1, 1, 2))
    with assert_raises(contains="inside both images"):
        copy_volume_to_volume(source, destination, None, TexelPoint(0, 0, -1))
    with assert_raises(contains="inside both images"):
        copy_volume_to_volume(source, destination, None, TexelPoint(0, 0, 2))
    with assert_raises(contains="inside both images"):
        copy_volume_to_volume(source, destination, TexelBox(1, 0, 0, 2, 1, 1))
    with assert_raises(contains="inside both images"):
        copy_volume_to_volume(source, destination, None, TexelPoint(2, 0, 0))
    var bad = a_volume(2, 2, 1)
    bad.width = 5
    with assert_raises(contains="does not match"):
        copy_volume_to_volume(bad, destination)
    with assert_raises(contains="does not match"):
        copy_volume_to_volume(source, bad)


def test_a_framebuffer_texture_starts_empty() raises:
    var bytes = framebuffer_texture(2, 3)
    assert_equal(bytes.width, 2)
    assert_equal(bytes.levels, 1)
    assert_equal(bytes.mag_filter, NEAREST)
    assert_equal(bytes.color_space, SRGB)
    assert_equal(bytes.pixels[3], 0)
    var floats = framebuffer_texture(2, 2, FLOAT_TYPE, LINEAR)
    assert_equal(floats.texel_type, FLOAT_TYPE)
    with assert_raises(contains="must be LINEAR"):
        _ = framebuffer_texture(2, 2, FLOAT_TYPE)
    with assert_raises(contains="must be positive"):
        _ = framebuffer_texture(0, 2)
    with assert_raises(contains="must be positive"):
        _ = framebuffer_texture(2, 0)
    with assert_raises(contains="texel type"):
        _ = framebuffer_texture(2, 2, TexelType(7))


def test_a_displayed_image_is_copied_from_its_bottom_left() raises:
    var image = Framebuffer(3, 3, Color(0, 0, 0))
    image.set_pixel(1, 2, Color(10, 20, 30))
    image.set_pixel(1, 1, Color(40, 50, 60))
    var texture = framebuffer_texture(2, 2)
    copy_framebuffer_to_texture(image, texture, TexelPoint(1, 0, 0))
    # The texture's bottom row, stored last, is the image's bottom row.
    assert_equal(texture.pixels[8], 10)
    assert_equal(texture.pixels[0], 40)
    var chained = Texture(2, 2, List[UInt8](length=16, fill=0))
    copy_framebuffer_to_texture(image, chained, TexelPoint(0, 0, 0), 1)
    assert_equal(chained.pixels[16], 0)
    copy_framebuffer_to_texture(image, chained)
    with assert_raises(contains="into a byte texture"):
        var floats = framebuffer_texture(2, 2, FLOAT_TYPE, LINEAR)
        copy_framebuffer_to_texture(image, floats)
    with assert_raises(contains="inside both images"):
        copy_framebuffer_to_texture(image, texture, TexelPoint(2, 0, 0))
    with assert_raises(contains="no layers"):
        copy_framebuffer_to_texture(image, texture, TexelPoint(0, 0, 1))
    with assert_raises(contains="does not hold"):
        copy_framebuffer_to_texture(image, texture, TexelPoint(0, 0, 0), 1)


def test_a_render_target_is_copied_as_its_type_stores_it() raises:
    var target = RenderTarget(2, 2, Color(0, 0, 0), FLOAT_TARGET)
    target.write(0, 1, FloatColor(4, 0, 0, 1))
    var floats = framebuffer_texture(1, 1, FLOAT_TYPE, LINEAR)
    copy_framebuffer_to_texture(target, floats)
    assert_almost_equal(floats.data[0], 4)
    var bytes_target = RenderTarget(2, 2, Color(0, 0, 0))
    bytes_target.write(1, 0, FloatColor(0.5, 1, 0, 1))
    var bytes = framebuffer_texture(1, 1, color_space=LINEAR)
    copy_framebuffer_to_texture(bytes_target, bytes, TexelPoint(1, 1, 0))
    assert_equal(bytes.pixels[0], 128)
    assert_equal(bytes.pixels[1], 255)
    var chained = Texture(
        2, 2, List[UInt8](length=16, fill=0), color_space=LINEAR
    )
    copy_framebuffer_to_texture(bytes_target, chained)
    assert_equal(chained.levels, 2)
    with assert_raises(contains="a float target a float"):
        copy_framebuffer_to_texture(target, bytes)
    var plain = framebuffer_texture(1, 1)
    with assert_raises(contains="a float target a float"):
        copy_framebuffer_to_texture(
            RenderTarget(2, 2, Color(0, 0, 0), HALF_FLOAT_TARGET), plain
        )
    with assert_raises(contains="a float target a float"):
        copy_framebuffer_to_texture(bytes_target, floats)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
