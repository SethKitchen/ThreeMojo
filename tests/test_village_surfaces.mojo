# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The surfaces of the village's houses: textures that tile, and the
materials that wear them."""

from core.assets import Assets
from extensions.village.surfaces import (
    ashlar_texture,
    boards_texture,
    brick_texture,
    cloth_texture,
    fieldstone_texture,
    house_looks,
    plank_texture,
    plaster_texture,
    slate_texture,
    tile_texture,
    tiled_noise,
    wood_texture,
)
from materials.material import BASIC
from render.srgb import SRGB
from render.texture import REPEAT, Texture
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


def test_tiled_noise_repeats_and_stays_in_range() raises:
    for k in range(20):
        var x = Float32(k) * 0.37
        var y = Float32(k) * 0.61 - 3
        var a = tiled_noise(x, y, 4, 9)
        var b = tiled_noise(x + 4, y - 8, 4, 9)
        assert_true(abs(a - b) < 1.0e-5)
        assert_true(a >= 0 and a <= 1)


def _check(texture: Texture, size: Int) raises -> Float32:
    """Check a texture's size and how it repeats, and return the spread
    of its red channel, from its darkest texel to its lightest."""
    assert_equal(texture.width, size)
    assert_equal(texture.height, size)
    assert_true(texture.wrap_s == REPEAT)
    assert_true(texture.color_space == SRGB)
    var low = Float32(1)
    var high = Float32(0)
    for k in range(64):
        var c = texture.sample(
            (Float32(k) + 0.5) / 64, (Float32(k * 7 % 64) + 0.5) / 64
        )
        low = min(low, c.r)
        high = max(high, c.r)
    return high - low


def test_a_texture_needs_a_texel() raises:
    with assert_raises(contains="one texel"):
        _ = brick_texture(0, 17)
    assert_equal(brick_texture(1, 17).width, 1)


def test_each_texture_has_its_pattern() raises:
    var size = 128
    var textures: List[Texture] = [
        brick_texture(size, 17),
        fieldstone_texture(size, 17),
        plaster_texture(size, 17),
        boards_texture(size, 17),
        wood_texture(size, 17),
        ashlar_texture(size, 17),
        tile_texture(size, 17),
        slate_texture(size, 17),
        plank_texture(size, 17),
        cloth_texture(size, 17),
    ]
    for k in range(len(textures)):
        # Each shows a pattern: its texels differ.
        assert_true(_check(textures[k], size) > 0.01)
    # The wood's knots: a seed with one, and one where every cell is
    # clear.
    for seed in range(8):
        _ = wood_texture(32, seed)


def test_the_looks_wear_the_textures() raises:
    var assets = Assets()
    var looks = house_looks(assets, 16, 3)
    assert_equal(len(assets.textures.textures), 10)
    for id in [
        looks.brick,
        looks.tiles,
        looks.planks,
        looks.glass,
        looks.cloth,
    ]:
        assert_true(assets.materials.get(id).vertex_colors)
    assert_true(assets.materials.get(looks.daylight).kind == BASIC)
    assert_true(assets.materials.get(looks.glass).kind != BASIC)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
