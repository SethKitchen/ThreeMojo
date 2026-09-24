# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.cube_uv` and `render.pmrem`, three.js's cube UV
layout and `PMREMGenerator`.

The layout's arithmetic is checked against three.js's numbers one function
at a time. The generator is checked by what a PMREM must do: read the
source unchanged at roughness zero, keep a uniform sky uniform at every
roughness, and blur a bright patch wider the rougher the surface.
"""

from math.vector3 import Vector3
from render.cube_texture import (
    NEGATIVE_X,
    NEGATIVE_Y,
    NEGATIVE_Z,
    POSITIVE_X,
    POSITIVE_Y,
    POSITIVE_Z,
    CubeTexture,
    cube_uv_width,
    face_forward,
    validate_cube_uv,
)
from render.cube_uv import (
    CubeUvTaps,
    cube_uv_coordinate,
    cube_uv_direction,
    cube_uv_face,
    cube_uv_face_uv,
    cube_uv_lod_max,
    cube_uv_taps,
    roughness_to_mip,
    sample_cube_uv,
)
from render.pmrem import (
    blur_axis,
    extra_lod_sigma,
    pmrem_from_cube,
    pmrem_from_equirectangular,
    pmrem_lod_max,
    pole_axis,
)
from render.texture import (
    BILINEAR,
    CLAMP,
    IGNORED,
    NEAREST,
    REPEAT,
    Texture,
    float_texture,
)
from render.framebuffer import Color
from render.srgb import SRGB
from std.math import inf, log2
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def a_colored_cube(size: Int, bright: Int = -1) raises -> CubeTexture:
    """Return a float cube whose face `f` holds red `f + 1`, green one and
    blue zero; or, with `bright`, one face at ten and the rest at zero."""
    var faces = List[Texture]()
    for face in range(6):
        var data = List[Float32]()
        for _ in range(size * size):
            var red = Float32(face + 1)
            var green = Float32(1)
            if bright >= 0:
                red = 10 if face == bright else 0
                green = red
            data.append(red)
            data.append(green)
            data.append(0)
            data.append(1)
        faces.append(
            float_texture(size, size, data^, CLAMP, BILINEAR, False, IGNORED)
        )
    return CubeTexture(faces^)


def a_layout() raises -> Texture:
    """Return a valid layout image for `lod_max` four, 336 by 64, whose
    texels rise along the rows: a stand-in for a PMREM where only the
    layout's shape and its reads matter, so a test need not blur one."""
    var data = List[Float32]()
    for texel in range(336 * 64):
        var level = Float32(texel % 97) / 97
        data.append(level)
        data.append(2 * level)
        data.append(1 - level)
        data.append(1)
    return float_texture(336, 64, data^, CLAMP, BILINEAR, False, IGNORED)


def a_cube_with_a_layout() raises -> CubeTexture:
    """Return `a_colored_cube(16)` holding `a_layout` as its PMREM."""
    var cube = a_colored_cube(16)
    cube.cube_uv = a_layout()
    cube.validate()
    return cube^


# --- the layout ---------------------------------------------------------------


def test_faces_are_three_js_order() raises:
    assert_equal(cube_uv_face(Vector3(2, 1, 1)), 0)
    assert_equal(cube_uv_face(Vector3(0.5, 2, 1)), 1)
    assert_equal(cube_uv_face(Vector3(0.5, 1, 2)), 2)
    assert_equal(cube_uv_face(Vector3(-2, 1, 1)), 3)
    assert_equal(cube_uv_face(Vector3(0.5, -2, 1)), 4)
    assert_equal(cube_uv_face(Vector3(0.5, 1, -2)), 5)
    # x beats z but not y.
    assert_equal(cube_uv_face(Vector3(1, -2, 0.5)), 4)
    # Ties go as three.js's strict comparisons send them: to y.
    assert_equal(cube_uv_face(Vector3(1, 1, 1)), 1)
    assert_equal(cube_uv_face(Vector3(0, 0, 0)), 4)


def test_directions_and_places_are_inverses() raises:
    for face in range(6):
        for place in [(0.25, 0.75), (0.9, 0.1), (0.5, 0.5)]:
            var u = Float32(place[0])
            var v = Float32(place[1])
            var direction = cube_uv_direction(u, v, face)
            assert_equal(cube_uv_face(direction), face)
            var back = cube_uv_face_uv(direction, face)
            assert_almost_equal(back.x, u, atol=1e-6)
            assert_almost_equal(back.y, v, atol=1e-6)


def test_the_zero_vector_lands_in_the_middle() raises:
    for face in range(6):
        var middle = cube_uv_face_uv(Vector3(0, 0, 0), face)
        assert_equal(middle.x, 0.5)
        assert_equal(middle.y, 0.5)


def test_roughness_maps_to_three_js_mips() raises:
    assert_almost_equal(roughness_to_mip(1), Float32(-2), atol=1e-5)
    assert_almost_equal(roughness_to_mip(0.8), Float32(-1), atol=1e-5)
    assert_almost_equal(roughness_to_mip(0.9), Float32(-1.5), atol=1e-5)
    assert_almost_equal(roughness_to_mip(0.4), Float32(2), atol=1e-5)
    assert_almost_equal(roughness_to_mip(0.6), Float32(0.5), atol=1e-5)
    assert_almost_equal(roughness_to_mip(0.305), Float32(3), atol=1e-4)
    assert_almost_equal(roughness_to_mip(0.35), Float32(2.5263), atol=1e-3)
    assert_almost_equal(roughness_to_mip(0.21), Float32(4), atol=1e-4)
    assert_almost_equal(roughness_to_mip(0.25), Float32(3.5789), atol=1e-3)
    assert_almost_equal(
        roughness_to_mip(0.1), -2 * log2(Float32(0.116)), atol=1e-5
    )
    assert_equal(roughness_to_mip(0), inf[DType.float32]())


def test_the_sharpest_mip_is_read_from_the_height() raises:
    assert_equal(cube_uv_lod_max(64), 4)
    assert_equal(cube_uv_lod_max(1024), 8)
    assert_equal(cube_uv_lod_max(100), 4)
    assert_equal(cube_uv_width(4), 336)
    assert_equal(cube_uv_width(8), 768)


def test_a_coordinate_is_three_js_texel() raises:
    # lod_max 8: 768 by 1024. Straight down +x at mip 8 is the middle of
    # the first tile, (1 + 0.5 * 254, 1 + 0.5 * 254) = (128, 128).
    var place = cube_uv_coordinate(Vector3(1, 0, 0), 8, 8, 768, 1024)
    assert_almost_equal(place.x, Float32(128.0 / 768), atol=1e-6)
    assert_almost_equal(place.y, Float32(128.0 / 1024), atol=1e-6)
    # -z at mip 7: second row of tiles, third column, 128 texels a tile,
    # above the 512 rows of mip 8.
    var lower = cube_uv_coordinate(Vector3(0, 0, -1), 7, 8, 768, 1024)
    assert_almost_equal(lower.x, Float32((2 * 128 + 64) / 768.0), atol=1e-6)
    assert_almost_equal(lower.y, Float32((512 + 128 + 64) / 1024.0), atol=1e-6)
    # Mip minus two is the sixth extra copy: 16 texels, six copies of 48
    # to the right, on the top band.
    var roughest = cube_uv_coordinate(Vector3(0, 1, 0), -2, 8, 768, 1024)
    assert_almost_equal(
        roughest.x, Float32((6 * 48 + 16 + 8) / 768.0), atol=1e-6
    )
    assert_almost_equal(roughest.y, Float32((960 + 8) / 1024.0), atol=1e-6)


def test_taps_split_the_mip() raises:
    # Roughness 0.6 reads mip 0.5: copies zero and one, half way.
    var taps = cube_uv_taps(Vector3(0, 0, 1), 0.6, 336, 64)
    assert_almost_equal(taps.blend, Float32(0.5), atol=1e-5)
    var zero = cube_uv_coordinate(Vector3(0, 0, 1), 0, 4, 336, 64)
    var one = cube_uv_coordinate(Vector3(0, 0, 1), 1, 4, 336, 64)
    assert_equal(taps.near.x, zero.x)
    assert_equal(taps.far.x, one.x)
    # Roughness zero is clamped to the sharpest copy and does not mix.
    assert_equal(cube_uv_taps(Vector3(0, 0, 1), 0, 336, 64).blend, 0)
    # Roughness one is the roughest copy.
    var rough = cube_uv_taps(Vector3(0, 0, 1), 1, 336, 64)
    assert_equal(rough.blend, 0)
    var roughest = cube_uv_coordinate(Vector3(0, 0, 1), -2, 4, 336, 64)
    assert_equal(rough.near.x, roughest.x)


# --- the generator ------------------------------------------------------------


def test_the_generator_sizes_as_three_js_does() raises:
    assert_equal(pmrem_lod_max(256), 8)
    assert_equal(pmrem_lod_max(300), 8)
    assert_equal(pmrem_lod_max(16), 4)
    # Smaller than sixteen reads at sixteen.
    assert_equal(pmrem_lod_max(2), 4)
    assert_equal(len(extra_lod_sigma()), 6)
    assert_equal(extra_lod_sigma()[5], 0.582)


def test_the_poles_are_a_dodecahedron() raises:
    for index in range(10):
        var axis = pole_axis(index)
        assert_true(axis.length() > 1)
    assert_equal(pole_axis(0).x, -pole_axis(1).x)
    assert_equal(pole_axis(13).z, pole_axis(3).z)
    assert_equal(pole_axis(9).y, 1)
    assert_equal(pole_axis(6).z, -1)
    assert_equal(pole_axis(7).x, 1)
    assert_equal(pole_axis(8).x, -1)
    assert_true(pole_axis(4).z < 0)
    assert_true(pole_axis(5).z > 0)
    assert_true(pole_axis(2).x < 0)


def test_a_blur_turns_about_the_pole_or_across_it() raises:
    var pole = Vector3(0, 2, 0)
    var around = blur_axis(True, pole, Vector3(1, 0, 0))
    assert_almost_equal(around.y, Float32(1), atol=1e-6)
    var across = blur_axis(False, pole, Vector3(1, 0, 0))
    assert_almost_equal(across.z, Float32(-1), atol=1e-6)
    # Along the pole there is no across, and three.js falls back on
    # (z, 0, -x).
    var fallback = blur_axis(False, Vector3(1, 0, 0), Vector3(2, 0, 0))
    assert_almost_equal(fallback.z, Float32(-1), atol=1e-6)


def test_roughness_zero_reads_the_source() raises:
    var cube = a_colored_cube(16)
    var prefiltered = pmrem_from_cube(cube)
    assert_true(prefiltered.is_prefiltered())
    assert_false(cube.is_prefiltered())
    assert_equal(prefiltered.cube_uv.width, 336)
    assert_equal(prefiltered.cube_uv.height, 64)
    validate_cube_uv(prefiltered.cube_uv)
    for face in [
        POSITIVE_X,
        NEGATIVE_X,
        POSITIVE_Y,
        NEGATIVE_Y,
        POSITIVE_Z,
        NEGATIVE_Z,
    ]:
        var direction = face_forward(face)
        var seen = prefiltered.sample_rough(direction, 0)
        assert_almost_equal(seen.r, Float32(face + 1), atol=1e-4)
        assert_almost_equal(seen.g, Float32(1), atol=1e-4)
        assert_equal(seen.a, 1)
        # The faces are the source's, for every other reader.
        assert_equal(prefiltered.sample(direction).r, Float32(face + 1))


def test_a_uniform_sky_stays_uniform_at_every_roughness() raises:
    var faces = List[Texture]()
    for _ in range(6):
        var data = List[Float32]()
        for _ in range(4 * 4):
            data.append(0.5)
            data.append(2)
            data.append(4)
            data.append(1)
        faces.append(float_texture(4, 4, data^))
    var prefiltered = pmrem_from_cube(CubeTexture(faces^))
    for roughness in [Float32(0), 0.1, 0.3, 0.37, 0.5, 0.9, 1]:
        for direction in [Vector3(0.3, 0.9, -0.2), Vector3(-1, 0.1, 0.4)]:
            var seen = prefiltered.sample_rough(direction, roughness)
            assert_almost_equal(seen.r, Float32(0.5), atol=1e-4)
            assert_almost_equal(seen.g, Float32(2), atol=1e-4)
            assert_almost_equal(seen.b, Float32(4), atol=1e-4)


def test_a_bright_face_spreads_with_roughness() raises:
    # Only +y is lit. Looking at the horizon, a mirror sees black and a
    # rough surface sees the sky bleed in, more the rougher it is.
    var prefiltered = pmrem_from_cube(a_colored_cube(32, POSITIVE_Y))
    var horizon = Vector3(1, 0.3, 0)
    var last = Float32(-1)
    for roughness in [Float32(0.05), 0.3, 0.5, 0.7, 1]:
        var seen = prefiltered.sample_rough(horizon, roughness).r
        assert_true(seen > last, "the blur did not widen")
        last = seen
    assert_almost_equal(
        prefiltered.sample_rough(horizon, 0).r, Float32(0), atol=1e-4
    )
    # Straight up keeps most of the light, and loses some to the dark as
    # the lobe widens.
    var up = Vector3(0, 1, 0)
    assert_almost_equal(
        prefiltered.sample_rough(up, 0).r, Float32(10), atol=1e-3
    )
    assert_true(prefiltered.sample_rough(up, 1).r < 10)
    assert_true(prefiltered.sample_rough(up, 1).r > 2)


def test_a_cube_without_a_pmrem_reads_down_its_chain() raises:
    var faces = List[Texture]()
    for face in range(6):
        var pixels = List[UInt8]()
        for texel in range(16):
            var bright = UInt8(255) if (texel + face) % 2 == 0 else 0
            pixels.append(bright)
            pixels.append(bright)
            pixels.append(bright)
            pixels.append(255)
        faces.append(Texture(4, 4, pixels^, CLAMP, BILINEAR, SRGB, True))
    var cube = CubeTexture(faces^)
    var direction = Vector3(0.2, 0.1, 1)
    var chained = cube.sample_rough(direction, 1)
    var level = cube.sample_level(direction, Float32(cube.levels() - 1))
    assert_equal(chained.r, level.r)


def test_a_sample_reads_the_layout_directly() raises:
    # Any valid layout proves the dispatch; no blur is needed for it.
    var prefiltered = a_cube_with_a_layout()
    var direct = sample_cube_uv(prefiltered.cube_uv, Vector3(0, 0, 1), 0.45)
    var through = prefiltered.sample_rough(Vector3(0, 0, 1), 0.45)
    assert_true(direct.r > 0)
    assert_equal(direct.r, through.r)
    assert_equal(direct.g, through.g)
    assert_equal(direct.b, through.b)


def test_a_copy_keeps_the_pmrem() raises:
    var prefiltered = a_cube_with_a_layout()
    var copied = CubeTexture(copy=prefiltered)
    assert_true(copied.is_prefiltered())
    assert_equal(copied.cube_uv.width, prefiltered.cube_uv.width)


def test_a_panorama_prefilters_too() raises:
    # A panorama gray at two everywhere: a quarter of 64 is 16.
    var data = List[Float32]()
    for _ in range(64 * 32):
        data.append(2)
        data.append(2)
        data.append(2)
        data.append(1)
    var prefiltered = pmrem_from_equirectangular(float_texture(64, 32, data^))
    assert_equal(prefiltered.size, 16)
    assert_equal(prefiltered.cube_uv.height, 64)
    for roughness in [Float32(0), 0.5, 1]:
        assert_almost_equal(
            prefiltered.sample_rough(Vector3(0.2, -0.7, 0.1), roughness).g,
            Float32(2),
            atol=1e-4,
        )
    with assert_raises():
        _ = pmrem_from_equirectangular(Texture())


def test_a_source_refused_by_the_cube_is_refused() raises:
    var cube = a_colored_cube(4)
    cube.faces[1].set_wrap(REPEAT)
    with assert_raises():
        _ = pmrem_from_cube(cube)


def test_a_layout_image_is_checked() raises:
    var prefiltered = a_cube_with_a_layout()
    validate_cube_uv(prefiltered.cube_uv)
    # Bytes.
    var bytes = List[UInt8](length=336 * 64 * 4, fill=0)
    with assert_raises():
        validate_cube_uv(Texture(336, 64, bytes^, CLAMP, BILINEAR, SRGB, False))
    # Wrapped, filtered or chained otherwise.
    var wrapped = Texture(copy=prefiltered.cube_uv)
    wrapped.set_wrap(REPEAT)
    with assert_raises():
        validate_cube_uv(wrapped)
    var nearest = Texture(copy=prefiltered.cube_uv)
    nearest.mag_filter = NEAREST
    with assert_raises():
        validate_cube_uv(nearest)
    var chained = Texture(copy=prefiltered.cube_uv)
    chained.levels = 2
    with assert_raises():
        validate_cube_uv(chained)
    # The wrong height or width.
    for size in [(336, 32), (336, 72), (400, 64)]:
        var data = List[Float32](length=size[0] * size[1] * 4, fill=0)
        with assert_raises():
            validate_cube_uv(float_texture(size[0], size[1], data^))
    # A cube with a bad one is refused.
    var edited = CubeTexture(copy=prefiltered)
    edited.cube_uv.mag_filter = NEAREST
    with assert_raises():
        edited.validate()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
