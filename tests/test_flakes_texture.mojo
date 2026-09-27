# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""three.js's `FlakesTexture`: discs of random normals on the flat
normal, from a seed."""

from render.flakes_texture import FLAKE_COUNT, flakes_texture
from render.srgb import LINEAR
from render.texture import REPEAT
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def test_a_seed_gives_the_same_flakes() raises:
    var first = flakes_texture(64, 48, seed=7)
    var again = flakes_texture(64, 48, seed=7)
    var other = flakes_texture(64, 48, seed=8)
    assert_equal(first.width, 64)
    assert_equal(first.height, 48)
    assert_true(first.pixels == again.pixels)
    assert_false(first.pixels == other.pixels)
    # A normal map is data, and three.js's example repeats it.
    assert_true(first.color_space == LINEAR)
    assert_true(first.wrap_s == REPEAT)
    assert_true(first.wrap_t == REPEAT)


def test_every_texel_is_a_normal_tilted_from_z() raises:
    # A flake's z is 1.5 over at most the length of (1, 1, 1.5), so its
    # blue is 185 or more, and the flat normal's is 255: a texel mixed of
    # the two is never under 185. Its alpha is opaque.
    var flakes = flakes_texture()
    assert_equal(flakes.width, 512)
    var red = 0
    var green = 0
    var flat = 0
    for texel in range(flakes.width * flakes.height):
        var at = texel * 4
        assert_true(flakes.pixels[at + 2] >= 185)
        assert_equal(flakes.pixels[at + 3], 255)
        red += Int(flakes.pixels[at])
        green += Int(flakes.pixels[at + 1])
        if (
            flakes.pixels[at] == 127
            and flakes.pixels[at + 1] == 127
            and flakes.pixels[at + 2] == 255
        ):
            flat += 1
    # Tilted every way alike: the mean is near the flat normal's, and
    # some of the canvas is left flat between the discs.
    var count = flakes.width * flakes.height
    assert_true(abs(red // count - 127) <= 3)
    assert_true(abs(green // count - 127) <= 3)
    assert_true(flat > 0)
    assert_equal(FLAKE_COUNT, 4000)


def test_a_flakes_texture_has_a_pixel_on_each_side() raises:
    with assert_raises(contains="at least one pixel on each side"):
        _ = flakes_texture(0, 4)
    with assert_raises(contains="at least one pixel on each side"):
        _ = flakes_texture(4, 0)
    # One pixel is still a texture, under every disc.
    var one = flakes_texture(1, 1, seed=1)
    assert_true(one.pixels[2] >= 185)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
