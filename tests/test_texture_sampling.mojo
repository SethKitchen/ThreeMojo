# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for a texture's sampler settings in `render.texture`: a wrap per
axis, the magnification and minification filters, `flip_y` and the
mapping, as three.js's `Texture` holds them.

Every expected texel is worked out by hand from a 2x2 or 4x4 image whose
texels are all different, so a wrong axis or a wrong level shows as a
wrong color rather than as a small error.
"""

from math.vector2 import Vector2
from render.framebuffer import Color, FloatColor
from render.srgb import LINEAR
from render.texture import (
    BILINEAR,
    CLAMP,
    COVERAGE,
    CUBE_REFLECTION_MAPPING,
    CUBE_REFRACTION_MAPPING,
    CUBE_UV_REFLECTION_MAPPING,
    EQUIRECTANGULAR_REFLECTION_MAPPING,
    EQUIRECTANGULAR_REFRACTION_MAPPING,
    IGNORED,
    LINEAR_MIPMAP_LINEAR,
    LINEAR_MIPMAP_NEAREST,
    MIRROR,
    MIRRORED_REPEAT,
    NEAREST,
    NEAREST_MIPMAP_LINEAR,
    NEAREST_MIPMAP_NEAREST,
    REPEAT,
    UV_MAPPING,
    Filter,
    Mapping,
    Texture,
    Wrap,
    float_texture,
    level_filter,
    minifying,
    mix_color,
    plan_levels,
    row_coordinate,
)
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def quad(wrap: Wrap = REPEAT, filter: Filter = NEAREST) raises -> Texture:
    """Return a 2x2 linear texture with no chain.

    Laid out from the top:

        red    green
        blue   white
    """
    var colors = [
        Color(255, 0, 0),
        Color(0, 255, 0),
        Color(0, 0, 255),
        Color(255, 255, 255),
    ]
    var pixels = List[UInt8]()
    for index in range(4):
        pixels.append(colors[index].r)
        pixels.append(colors[index].g)
        pixels.append(colors[index].b)
        pixels.append(colors[index].a)
    return Texture(2, 2, pixels^, wrap, filter, LINEAR, mipmapped=False)


def ramp(mipmapped: Bool = True) raises -> Texture:
    """Return a 4x4 linear texture whose texels are all different, with a
    chain of three levels."""
    var pixels = List[UInt8]()
    for index in range(16):
        pixels.append(UInt8(index * 16))
        pixels.append(UInt8(255 - index * 16))
        pixels.append(UInt8((index * 37) % 256))
        pixels.append(255)
    return Texture(4, 4, pixels^, CLAMP, BILINEAR, LINEAR, mipmapped)


def same(a: FloatColor, b: FloatColor) raises:
    """Assert two colors are equal to the last bit."""
    assert_equal(a.r, b.r)
    assert_equal(a.g, b.g)
    assert_equal(a.b, b.b)
    assert_equal(a.a, b.a)


def is_color(seen: FloatColor, r: Float32, g: Float32, b: Float32) raises:
    """Assert a sample is one texel of `quad`."""
    assert_almost_equal(seen.r, r, atol=1e-6)
    assert_almost_equal(seen.g, g, atol=1e-6)
    assert_almost_equal(seen.b, b, atol=1e-6)


# --- the named values -------------------------------------------------------


def test_each_filter_says_what_it_reads() raises:
    var nearest_within: List[Filter] = [
        NEAREST,
        NEAREST_MIPMAP_NEAREST,
        NEAREST_MIPMAP_LINEAR,
    ]
    for index in range(len(nearest_within)):
        assert_equal(nearest_within[index].within_level(), NEAREST)
    var linear_within: List[Filter] = [
        BILINEAR,
        LINEAR_MIPMAP_NEAREST,
        LINEAR_MIPMAP_LINEAR,
    ]
    for index in range(len(linear_within)):
        assert_equal(linear_within[index].within_level(), BILINEAR)
    assert_true(NEAREST.magnifies())
    assert_true(BILINEAR.magnifies())
    assert_false(LINEAR_MIPMAP_LINEAR.magnifies())
    assert_false(NEAREST.is_mipmap())
    assert_true(NEAREST_MIPMAP_NEAREST.is_mipmap())
    assert_true(LINEAR_MIPMAP_LINEAR.is_mipmap())
    assert_false(Filter(9).is_mipmap())
    assert_true(NEAREST_MIPMAP_LINEAR.mixes_levels())
    assert_true(LINEAR_MIPMAP_LINEAR.mixes_levels())
    assert_false(LINEAR_MIPMAP_NEAREST.mixes_levels())
    assert_false(BILINEAR.mixes_levels())
    assert_true(LINEAR_MIPMAP_NEAREST.is_valid())
    assert_false(Filter(6).is_valid())
    assert_false(Filter(-1).is_valid())
    # three.js's name for the mirrored wrap is the same wrap.
    assert_equal(MIRRORED_REPEAT, MIRROR)


def test_one_filter_and_a_chain_make_the_minification_filter() raises:
    assert_equal(minifying(NEAREST, False), NEAREST)
    assert_equal(minifying(BILINEAR, False), BILINEAR)
    assert_equal(minifying(NEAREST, True), NEAREST_MIPMAP_LINEAR)
    assert_equal(minifying(BILINEAR, True), LINEAR_MIPMAP_LINEAR)


def test_each_mapping_says_how_it_is_read() raises:
    var named: List[Mapping] = [
        UV_MAPPING,
        CUBE_REFLECTION_MAPPING,
        CUBE_REFRACTION_MAPPING,
        EQUIRECTANGULAR_REFLECTION_MAPPING,
        EQUIRECTANGULAR_REFRACTION_MAPPING,
        CUBE_UV_REFLECTION_MAPPING,
    ]
    for index in range(len(named)):
        assert_true(named[index].is_valid())
    # three.js's constants, and 305, which three.js skips.
    assert_equal(UV_MAPPING.value, 300)
    assert_equal(CUBE_UV_REFLECTION_MAPPING.value, 306)
    assert_false(Mapping(305).is_valid())
    assert_true(CUBE_REFRACTION_MAPPING.refracts())
    assert_true(EQUIRECTANGULAR_REFRACTION_MAPPING.refracts())
    assert_false(CUBE_REFLECTION_MAPPING.refracts())
    assert_true(EQUIRECTANGULAR_REFLECTION_MAPPING.is_equirectangular())
    assert_true(EQUIRECTANGULAR_REFRACTION_MAPPING.is_equirectangular())
    assert_false(UV_MAPPING.is_equirectangular())
    assert_true(CUBE_REFLECTION_MAPPING.is_cube())
    assert_true(CUBE_REFRACTION_MAPPING.is_cube())
    assert_false(CUBE_UV_REFLECTION_MAPPING.is_cube())


# --- the plan of levels -----------------------------------------------------


def test_a_magnified_sample_reads_the_full_image_through_the_mag_filter() raises:
    var plan = plan_levels(-0.5, 3, NEAREST, LINEAR_MIPMAP_LINEAR)
    assert_equal(plan.filter, NEAREST)
    assert_equal(plan.lower, 0)
    assert_equal(plan.upper, 0)
    plan = plan_levels(0, 3, BILINEAR, NEAREST_MIPMAP_NEAREST)
    assert_equal(plan.filter, BILINEAR)
    assert_equal(plan.lower, 0)


def test_a_minified_sample_without_a_chain_reads_the_full_image() raises:
    # No chain: a mipmap filter reads its one image, inside it as the
    # filter says.
    var plan = plan_levels(1.5, 1, BILINEAR, NEAREST_MIPMAP_LINEAR)
    assert_equal(plan.filter, NEAREST)
    assert_equal(plan.lower, 0)
    assert_equal(plan.upper, 0)
    # A chain, and a filter that does not read it.
    plan = plan_levels(1.5, 3, NEAREST, BILINEAR)
    assert_equal(plan.filter, BILINEAR)
    assert_equal(plan.lower, 0)
    assert_equal(plan.upper, 0)


def test_a_mipmap_nearest_filter_reads_the_nearest_level() raises:
    # OpenGL's `ceil(level + 0.5) - 1`: 1.4 is level one, 1.6 level two.
    var plan = plan_levels(1.4, 4, BILINEAR, NEAREST_MIPMAP_NEAREST)
    assert_equal(plan.filter, NEAREST)
    assert_equal(plan.lower, 1)
    assert_equal(plan.upper, 1)
    plan = plan_levels(1.6, 4, BILINEAR, LINEAR_MIPMAP_NEAREST)
    assert_equal(plan.filter, BILINEAR)
    assert_equal(plan.lower, 2)
    # Past the end of the chain is its last level.
    plan = plan_levels(9, 4, BILINEAR, LINEAR_MIPMAP_NEAREST)
    assert_equal(plan.lower, 3)
    assert_equal(plan.upper, 3)


def test_a_mipmap_linear_filter_mixes_the_two_levels_either_side() raises:
    var plan = plan_levels(1.25, 4, BILINEAR, LINEAR_MIPMAP_LINEAR)
    assert_equal(plan.filter, BILINEAR)
    assert_equal(plan.lower, 1)
    assert_equal(plan.upper, 2)
    assert_almost_equal(plan.blend, 0.25, atol=1e-6)
    plan = plan_levels(5, 4, BILINEAR, NEAREST_MIPMAP_LINEAR)
    assert_equal(plan.filter, NEAREST)
    assert_equal(plan.lower, 3)
    assert_equal(plan.upper, 3)


def test_a_named_level_is_read_through_the_filter_for_it() raises:
    assert_equal(level_filter(0, NEAREST, LINEAR_MIPMAP_LINEAR), NEAREST)
    assert_equal(level_filter(1, NEAREST, LINEAR_MIPMAP_LINEAR), BILINEAR)
    var image = ramp()
    image.mag_filter = NEAREST
    image.min_filter = LINEAR_MIPMAP_NEAREST
    assert_equal(image.filter_at(0), NEAREST)
    assert_equal(image.filter_at(2), BILINEAR)


# --- the two filters, sampled -------------------------------------------------


def test_the_mag_filter_reads_a_magnified_sample() raises:
    var image = ramp()
    image.mag_filter = NEAREST
    # Magnified: the nearest texel of the full-size image.
    same(image.sample_level(0.3, 0.6, -1), image.wrapped_texel(1, 1))
    same(image.sample(0.3, 0.6), image.wrapped_texel(1, 1))


def test_the_min_filter_reads_a_minified_sample() raises:
    var image = ramp()
    var smooth = ramp()
    # `LINEAR_MIPMAP_NEAREST`: level one, filtered, at 1.4.
    image.min_filter = LINEAR_MIPMAP_NEAREST
    same(image.sample_level(0.3, 0.6, 1.4), smooth.sample_at(0.3, 0.6, 1))
    # `NEAREST_MIPMAP_NEAREST`: level one, its nearest texel.
    image.min_filter = NEAREST_MIPMAP_NEAREST
    same(image.sample_level(0.3, 0.6, 1.4), image.sample_at(0.3, 0.6, 1))
    same(image.sample_at(0.3, 0.6, 1), image.wrapped_texel(0, 0, 1))
    # `NEAREST_MIPMAP_LINEAR`: levels one and two mixed, each nearest.
    image.min_filter = NEAREST_MIPMAP_LINEAR
    same(
        image.sample_level(0.3, 0.6, 1.25),
        mix_color(
            image.wrapped_texel(0, 0, 1), image.wrapped_texel(0, 0, 2), 0.25
        ),
    )
    # `BILINEAR` with a chain: the full-size image, filtered, however far
    # the footprint reaches.
    image.mag_filter = NEAREST
    image.min_filter = BILINEAR
    same(image.sample_level(0.3, 0.6, 2), smooth.sample_at(0.3, 0.6, 0))


def test_the_default_filters_read_as_trilinear() raises:
    var image = ramp()
    assert_equal(image.mag_filter, BILINEAR)
    assert_equal(image.min_filter, LINEAR_MIPMAP_LINEAR)
    same(
        image.sample_level(0.3, 0.6, 0.5),
        mix_color(
            image.sample_at(0.3, 0.6, 0), image.sample_at(0.3, 0.6, 1), 0.5
        ),
    )
    var flat = ramp(False)
    assert_equal(flat.min_filter, BILINEAR)


# --- a wrap per axis ------------------------------------------------------------


def test_each_axis_wraps_on_its_own() raises:
    var image = quad()
    image.wrap_s = REPEAT
    image.wrap_t = CLAMP
    # Across, 1.25 tiles back to the left column; up, -0.25 holds the
    # bottom row.
    is_color(image.sample(1.25, -0.25), 0, 0, 1)
    image.wrap_t = REPEAT
    # Up, -0.25 now tiles to the top row.
    is_color(image.sample(1.25, -0.25), 1, 0, 0)
    image.wrap_t = MIRROR
    image.wrap_s = CLAMP
    # Up, 1.25 mirrors back into the top row; across, 1.25 holds the
    # right column.
    is_color(image.sample(1.25, 1.25), 0, 1, 0)
    # The texel by index takes the same two wraps.
    same(image.wrapped_texel(5, -1), image.wrapped_texel(1, 0))


def test_a_bilinear_sample_wraps_each_axis_on_its_own() raises:
    var image = quad(CLAMP, BILINEAR)
    image.wrap_s = REPEAT
    # On the right edge across, halfway between the two rows up: the right
    # column blends with the left, the rows are held apart by the clamp.
    var seen = image.sample(1.0, 0.5)
    # Red, green, blue and white a quarter each.
    assert_almost_equal(seen.r, 0.5, atol=1e-6)
    assert_almost_equal(seen.g, 0.5, atol=1e-6)
    assert_almost_equal(seen.b, 0.5, atol=1e-6)
    image.wrap_s = CLAMP
    # Clamped across as well, the right column alone: green and white.
    seen = image.sample(1.0, 0.5)
    assert_almost_equal(seen.r, 0.5, atol=1e-6)
    assert_almost_equal(seen.g, 1, atol=1e-6)


def test_set_wrap_sets_both_axes() raises:
    var image = quad(CLAMP)
    image.set_wrap(MIRROR)
    assert_equal(image.wrap_s, MIRROR)
    assert_equal(image.wrap_t, MIRROR)
    var built = quad(REPEAT)
    assert_equal(built.wrap_t, REPEAT)


# --- flipY ------------------------------------------------------------------------


def test_flip_y_says_which_row_v_counts_from() raises:
    assert_almost_equal(row_coordinate(0.25, True), 0.75, atol=1e-6)
    assert_almost_equal(row_coordinate(0.25, False), 0.25, atol=1e-6)
    var image = quad()
    assert_true(image.flip_y)
    # Up from the bottom row: the bottom left texel is blue.
    is_color(image.sample(0.25, 0.25), 0, 0, 1)
    image.flip_y = False
    # Down from the first row: the top left texel is red.
    is_color(image.sample(0.25, 0.25), 1, 0, 0)
    var smooth = quad(CLAMP, BILINEAR)
    smooth.flip_y = False
    is_color(smooth.sample(0.25, 0.75), 0, 0, 1)
    assert_true(Texture().flip_y)


# --- the checks and the copies -------------------------------------------------


def test_a_wrong_sampler_setting_is_refused() raises:
    var image = quad()
    image.wrap_t = Wrap(9)
    with assert_raises(contains="wrap mode"):
        image.validate()
    image.wrap_t = CLAMP
    image.wrap_s = Wrap(9)
    with assert_raises(contains="wrap mode"):
        image.validate()
    image.wrap_s = CLAMP
    # A magnified sample reads one level, so no mipmap filter magnifies.
    image.mag_filter = LINEAR_MIPMAP_LINEAR
    with assert_raises(contains="magnification filter"):
        image.validate()
    image.mag_filter = NEAREST
    image.min_filter = Filter(9)
    with assert_raises(contains="minification filter"):
        image.validate()
    image.min_filter = NEAREST_MIPMAP_NEAREST
    image.mapping = Mapping(305)
    with assert_raises(contains="mapping"):
        image.validate()
    image.mapping = EQUIRECTANGULAR_REFLECTION_MAPPING
    image.validate()
    var pixels = List[UInt8](length=4, fill=255)
    with assert_raises(contains="magnification filter"):
        _ = Texture(1, 1, pixels^, CLAMP, NEAREST_MIPMAP_NEAREST)


def test_a_copy_keeps_the_sampler() raises:
    var image = ramp()
    image.wrap_s = MIRROR
    image.wrap_t = REPEAT
    image.mag_filter = NEAREST
    image.min_filter = LINEAR_MIPMAP_NEAREST
    image.flip_y = False
    image.mapping = EQUIRECTANGULAR_REFRACTION_MAPPING
    var copies = List[Texture]()
    copies.append(Texture(copy=image))
    copies.append(image.ignoring_alpha())
    for index in range(len(copies)):
        ref copy = copies[index]
        assert_equal(copy.wrap_s, MIRROR)
        assert_equal(copy.wrap_t, REPEAT)
        assert_equal(copy.mag_filter, NEAREST)
        assert_equal(copy.min_filter, LINEAR_MIPMAP_NEAREST)
        assert_false(copy.flip_y)
        assert_equal(copy.mapping, EQUIRECTANGULAR_REFRACTION_MAPPING)
    assert_equal(copies[1].alpha, IGNORED)
    var floats = float_texture(1, 1, [0.5, 0.5, 0.5, 1.0], REPEAT, NEAREST)
    floats.wrap_t = MIRROR
    floats.flip_y = False
    var ignored = floats.ignoring_alpha()
    assert_equal(ignored.wrap_s, REPEAT)
    assert_equal(ignored.wrap_t, MIRROR)
    assert_false(ignored.flip_y)
    var blank = Texture()
    blank.flip_y = False
    assert_false(blank.ignoring_alpha().flip_y)


def test_the_constructors_take_three_js_defaults() raises:
    var blank = Texture()
    assert_equal(blank.wrap_t, CLAMP)
    assert_equal(blank.min_filter, NEAREST)
    assert_equal(blank.mapping, UV_MAPPING)
    var floats = float_texture(
        2, 2, List[Float32](length=16, fill=0.5), mipmapped=True
    )
    assert_equal(floats.wrap_t, CLAMP)
    assert_equal(floats.min_filter, LINEAR_MIPMAP_LINEAR)
    assert_true(floats.flip_y)
    assert_equal(floats.alpha, COVERAGE)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
