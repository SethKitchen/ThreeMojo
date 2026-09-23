# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for float textures in `render.texture` and for the
equirectangular conversion in `render.cube_texture`.

A float texture holds linear light as it is, above one included, and
every test here checks a number that a byte texture would have clipped or
rounded.
"""

from math.vector3 import Vector3
from render.cube_texture import (
    FACE_COUNT,
    NEGATIVE_Y,
    POSITIVE_X,
    POSITIVE_Y,
    POSITIVE_Z,
    cube_from_equirectangular,
    equirect_uv,
    face_direction,
    face_of,
    face_uv,
)
from render.float_image import FloatImage
from render.framebuffer import Color
from render.srgb import LINEAR, SRGB
from render.texture import (
    BILINEAR,
    CLAMP,
    COVERAGE,
    FLOAT_TYPE,
    IGNORED,
    NEAREST,
    REPEAT,
    UNSIGNED_BYTE_TYPE,
    Filter,
    TexelType,
    Texture,
    Wrap,
    checkerboard,
    float_from_bytes,
    float_texel,
    float_texture,
    float_texture_from,
)
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def two_by_two() raises -> Texture:
    """Return a 2x2 float texture: 4 and 0 on top, 1 and 2 below, alpha
    one, nearest and unchained."""
    return float_texture(
        2,
        2,
        [4, 4, 4, 1, 0, 0, 0, 1, 1, 1, 1, 1, 2, 2, 2, 1],
        filter=NEAREST,
    )


# --- the type ---------------------------------------------------------------


def test_a_texel_type_is_bytes_or_floats() raises:
    assert_true(UNSIGNED_BYTE_TYPE.is_valid())
    assert_true(FLOAT_TYPE.is_valid())
    assert_false(TexelType(2).is_valid())
    assert_true(Texture().texel_type == UNSIGNED_BYTE_TYPE)
    assert_true(two_by_two().texel_type == FLOAT_TYPE)


def test_a_float_crosses_as_four_little_endian_bytes() raises:
    assert_equal(float_from_bytes(0, 0, 128, 63), 1)
    assert_equal(float_from_bytes(0, 0, 128, 67), 256)
    assert_equal(float_from_bytes(0, 0, 0, 192), -2)


def test_a_float_texel_ignores_its_alpha_when_asked() raises:
    var kept = float_texel(1, 2, 3, 0.25, COVERAGE)
    assert_equal(kept.a, 0.25)
    var ignored = float_texel(1, 2, 3, 0.25, IGNORED)
    assert_equal(ignored.a, 1)
    assert_equal(ignored.b, 3)


# --- building one -----------------------------------------------------------


def test_a_float_texture_is_linear_and_clamped_by_default() raises:
    var image = two_by_two()
    assert_true(image.color_space == LINEAR)
    assert_true(image.wrap == CLAMP)
    assert_equal(image.levels, 1)
    assert_equal(len(image.pixels), 0)
    assert_equal(len(image.data), 16)


def test_a_float_texture_refuses_what_it_cannot_hold() raises:
    with assert_raises(contains="positive"):
        _ = float_texture(0, 1, [])
    with assert_raises(contains="positive"):
        _ = float_texture(1, 0, [])
    with assert_raises(contains="length"):
        _ = float_texture(1, 1, [1, 1, 1])
    with assert_raises(contains="finite"):
        _ = float_texture(1, 1, [1, inf[DType.float32](), 1, 1])
    with assert_raises(contains="finite"):
        _ = float_texture(1, 1, [1, 1, nan[DType.float32](), 1])
    with assert_raises(contains="wrap mode"):
        _ = float_texture(1, 1, [1, 1, 1, 1], wrap=Wrap(7))


def test_a_float_texture_must_stay_linear() raises:
    var image = two_by_two()
    image.color_space = SRGB
    with assert_raises(contains="LINEAR"):
        image.validate()
    var odd = two_by_two()
    odd.texel_type = TexelType(5)
    with assert_raises(contains="texel type"):
        odd.validate()


def test_a_float_image_becomes_a_texture() raises:
    var image = FloatImage(1, 1, [3, 2, 1, 1])
    var texture = float_texture_from(image, REPEAT, NEAREST, False, IGNORED)
    assert_true(texture.wrap == REPEAT)
    assert_true(texture.alpha == IGNORED)
    assert_equal(texture.sample(0.5, 0.5).r, 3)
    with assert_raises(contains="out of bounds"):
        _ = image.get_pixel(1, 0)
    with assert_raises(contains="out of bounds"):
        _ = image.get_pixel(0, -1)
    with assert_raises(contains="out of bounds"):
        _ = image.get_pixel(-1, 0)
    with assert_raises(contains="out of bounds"):
        _ = image.get_pixel(0, 1)


# --- reading one ------------------------------------------------------------


def test_a_float_texel_is_read_as_it_is() raises:
    var image = two_by_two()
    assert_equal(image.wrapped_texel(0, 0).r, 4)
    assert_equal(image.wrapped_texel(1, 1).g, 2)
    # Light above one survives nearest sampling, top row at v one.
    assert_equal(image.sample(0.25, 0.75).r, 4)
    with assert_raises(contains="not bytes"):
        _ = image.texel(0, 0)


def test_a_float_texture_filters_light_above_one() raises:
    var image = float_texture(2, 1, [8, 0, 0, 1, 0, 0, 0, 1], filter=BILINEAR)
    # Halfway between 8 and 0 is 4: a byte texture would have said half.
    assert_equal(image.sample(0.5, 0.5).r, 4)


def test_a_float_chain_averages_light_above_one() raises:
    var image = float_texture(
        2,
        2,
        [4, 4, 4, 1, 0, 0, 0, 1, 1, 1, 1, 1, 3, 3, 3, 1],
        filter=NEAREST,
        mipmapped=True,
    )
    assert_equal(image.levels, 2)
    assert_equal(image.offsets[1], 16)
    assert_equal(len(image.data), 20)
    # (4 + 0 + 1 + 3) / 4.
    assert_equal(image.wrapped_texel(0, 0, 1).r, 2)
    assert_equal(image.sample_level(0.5, 0.5, 1).g, 2)


def test_a_float_chain_weights_by_alpha_unless_ignored() raises:
    var data: List[Float32] = [6, 6, 6, 1, 2, 2, 2, 0]
    var weighted = float_texture(2, 1, data.copy(), mipmapped=True)
    # The transparent texel weighs nothing: the color stays 6.
    assert_equal(weighted.wrapped_texel(0, 0, 1).r, 6)
    assert_equal(weighted.wrapped_texel(0, 0, 1).a, 0.5)
    var flat = float_texture(2, 1, data.copy(), mipmapped=True, alpha=IGNORED)
    assert_equal(flat.wrapped_texel(0, 0, 1).r, 4)
    assert_equal(flat.wrapped_texel(0, 0, 1).a, 1)


def test_a_float_texture_copies_and_ignores_its_alpha() raises:
    var chained = float_texture(2, 1, [6, 6, 6, 1, 2, 2, 2, 0], mipmapped=True)
    var copy = Texture(copy=chained)
    assert_true(copy.texel_type == FLOAT_TYPE)
    assert_equal(copy.data, chained.data)
    var ignoring = chained.ignoring_alpha()
    assert_true(ignoring.texel_type == FLOAT_TYPE)
    assert_equal(ignoring.levels, 2)
    # Rebuilt from the full-size image with alpha ignored: a plain mean.
    assert_equal(ignoring.wrapped_texel(0, 0, 1).r, 4)
    var single = two_by_two().ignoring_alpha()
    assert_equal(single.levels, 1)
    assert_true(single.alpha == IGNORED)


# --- equirectangular images -------------------------------------------------


def test_a_direction_lands_where_three_js_puts_it() raises:
    # Positive x is the middle of the image, positive z a quarter on.
    var middle = equirect_uv(Vector3(1, 0, 0))
    assert_almost_equal(middle.x, 0.5, atol=1e-6)
    assert_almost_equal(middle.y, 0.5, atol=1e-6)
    var quarter = equirect_uv(Vector3(0, 0, 2))
    assert_almost_equal(quarter.x, 0.75, atol=1e-6)
    # Straight up is the top row, v of one; straight down the bottom.
    assert_almost_equal(equirect_uv(Vector3(0, 3, 0)).y, 1, atol=1e-6)
    assert_almost_equal(equirect_uv(Vector3(0, -1, 0)).y, 0, atol=1e-6)
    # Negative x is the seam, at either edge.
    var seam = equirect_uv(Vector3(-1, 0, 0)).x
    assert_true(seam < 1e-6 or seam > 1 - 1e-6)
    var none = equirect_uv(Vector3(0, 0, 0))
    assert_equal(none.x, 0.5)
    assert_equal(none.y, 0.5)


def test_a_face_texel_direction_is_where_face_uv_reads_it() raises:
    for face in range(FACE_COUNT):
        for y in range(3):
            for x in range(3):
                var direction = face_direction(face, x, y, 3)
                assert_equal(face_of(direction), face)
                var place = face_uv(face, direction)
                assert_almost_equal(place.x, (Float32(x) + 0.5) / 3, atol=1e-6)
                assert_almost_equal(
                    place.y, 1 - (Float32(y) + 0.5) / 3, atol=1e-6
                )


def banded(height: Int) raises -> Texture:
    """Return a float panorama twice as wide as tall whose rows hold their
    own row number as red and whose columns hold theirs as green."""
    var data = List[Float32]()
    for y in range(height):
        for x in range(height * 2):
            data.append(Float32(y) + 100)
            data.append(Float32(x))
            data.append(0)
            data.append(1)
    return float_texture(height * 2, height, data^, filter=NEAREST)


def test_a_panorama_becomes_a_cube_read_in_the_same_directions() raises:
    var panorama = banded(8)
    var cube = cube_from_equirectangular(panorama)
    assert_equal(cube.size, 8)
    assert_equal(cube.levels(), 1)
    assert_true(cube.faces[0].texel_type == FLOAT_TYPE)
    assert_true(cube.faces[0].wrap == CLAMP)
    # Every face texel holds what the panorama holds in its direction.
    for face in range(FACE_COUNT):
        for y in range(8):
            for x in range(8):
                var place = equirect_uv(face_direction(face, x, y, 8))
                var expected = panorama.sample(place.x, place.y)
                var seen = cube.faces[face].wrapped_texel(x, y)
                assert_equal(seen.r, expected.r)
                assert_equal(seen.g, expected.g)
    # The top face is the top row, the bottom face the bottom row.
    assert_equal(cube.sample(Vector3(0, 1, 0)).r, 100)
    assert_equal(cube.sample(Vector3(0, -1, 0)).r, 107)


def test_a_panorama_cube_takes_a_size_and_a_chain() raises:
    var panorama = banded(4)
    var small = cube_from_equirectangular(panorama, 2)
    assert_equal(small.size, 2)
    var chained = cube_from_equirectangular(panorama, mipmapped=True)
    assert_equal(chained.levels(), 3)
    var from_chain = float_texture(
        2, 1, [1, 1, 1, 1, 3, 3, 3, 1], mipmapped=True
    )
    assert_equal(cube_from_equirectangular(from_chain).levels(), 1)
    assert_equal(cube_from_equirectangular(from_chain, 2).levels(), 2)
    assert_equal(cube_from_equirectangular(from_chain, 2, False).levels(), 1)
    with assert_raises(contains="at least one texel"):
        _ = cube_from_equirectangular(panorama, 0)
    with assert_raises(contains="must hold texels"):
        _ = cube_from_equirectangular(Texture())
    var odd = banded(2)
    odd.filter = Filter(4)
    with assert_raises(contains="filter"):
        _ = cube_from_equirectangular(odd)


def test_a_byte_panorama_gives_byte_faces_in_its_own_space() raises:
    var srgb = checkerboard(
        4, 1, Color(200, 100, 50), Color(0, 0, 0), CLAMP, NEAREST, SRGB, False
    )
    var cube = cube_from_equirectangular(srgb)
    assert_true(cube.faces[0].texel_type == UNSIGNED_BYTE_TYPE)
    assert_true(cube.faces[0].color_space == SRGB)
    # One square: every face holds the same bytes back.
    assert_equal(cube.faces[POSITIVE_X].texel(0, 0).r, 200)
    assert_equal(cube.faces[NEGATIVE_Y].texel(1, 1).b, 50)
    var linear = checkerboard(
        4, 1, Color(200, 100, 50), Color(0, 0, 0), CLAMP, NEAREST, LINEAR, False
    )
    var plain = cube_from_equirectangular(linear, 2)
    assert_true(plain.faces[0].color_space == LINEAR)
    assert_equal(plain.faces[POSITIVE_Z].texel(0, 1).g, 100)
    assert_equal(plain.faces[POSITIVE_Y].texel(1, 0).a, 255)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
