# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the procedural maps of the castle: their sizes, their colors,
that they repeat for a seed and differ between seeds, and that the normals
point out of the surface."""

from core.assets import Assets
from extensions.castle.textures import (
    BRICK_TILE,
    SurfaceMaps,
    brick_maps,
    grass_maps,
    gravel_maps,
    leaf_texture,
    needle_texture,
    slate_maps,
    stone_maps,
)
from math.vector2 import Vector2
from render.texture import Texture
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)

comptime _SIZE = 64


def _mean(texture: Texture, channel: Int) raises -> Float64:
    var total = Float64(0)
    for y in range(texture.height):
        for x in range(texture.width):
            var color = texture.texel(x, y)
            if channel == 0:
                total += Float64(color.r)
            elif channel == 1:
                total += Float64(color.g)
            elif channel == 2:
                total += Float64(color.b)
            else:
                total += Float64(color.a)
    return total / Float64(texture.width * texture.height)


def _spread(texture: Texture, channel: Int) raises -> Float64:
    """Return the highest less the lowest value of a channel."""
    var low = Float64(255)
    var high = Float64(0)
    for y in range(texture.height):
        for x in range(texture.width):
            var color = texture.texel(x, y)
            var value = Float64(color.g)
            if channel == 0:
                value = Float64(color.r)
            elif channel == 2:
                value = Float64(color.b)
            low = min(low, value)
            high = max(high, value)
    return high - low


def _every_normal_points_out(maps: SurfaceMaps) raises:
    # The blue channel of a tangent-space normal is its component out of the
    # surface, and is over one half for a normal in the upper hemisphere.
    for y in range(maps.normal.height):
        for x in range(maps.normal.width):
            assert_true(maps.normal.texel(x, y).b >= 128)


def test_a_brick_wall_is_red_with_pale_joints() raises:
    var maps = brick_maps(_SIZE, 1)
    assert_equal(maps.albedo.width, _SIZE)
    assert_equal(maps.albedo.height, _SIZE)
    assert_equal(maps.normal.width, _SIZE)
    assert_equal(maps.roughness.height, _SIZE)
    # Red over green over blue, as fired clay is.
    assert_true(_mean(maps.albedo, 0) > _mean(maps.albedo, 1) + 20.0)
    assert_true(_mean(maps.albedo, 1) > _mean(maps.albedo, 2))
    # The joints are lime mortar, much paler than the brick, so the red
    # channel spans a wide range.
    assert_true(_spread(maps.albedo, 0) > 60.0)
    _every_normal_points_out(maps)
    # The joints are grooves: some normals lean off the vertical.
    assert_true(_spread(maps.normal, 0) > 10.0)
    assert_almost_equal(_mean(maps.albedo, 3), 255.0, atol=1.0e-9)


def test_a_texture_repeats_for_a_seed_and_changes_with_another() raises:
    var a = brick_maps(_SIZE, 3)
    var b = brick_maps(_SIZE, 3)
    var c = brick_maps(_SIZE, 4)
    var same = True
    var different = False
    for y in range(_SIZE):
        for x in range(_SIZE):
            var p = a.albedo.texel(x, y)
            var q = b.albedo.texel(x, y)
            var r = c.albedo.texel(x, y)
            if p.r != q.r or p.g != q.g or p.b != q.b:
                same = False
            if p.r != r.r or p.g != r.g:
                different = True
    assert_true(same)
    assert_true(different)


def test_dressed_stone_is_pale() raises:
    var maps = stone_maps(_SIZE, 1)
    assert_true(_mean(maps.albedo, 1) > 100.0)
    assert_true(_mean(maps.albedo, 0) > _mean(maps.albedo, 2))
    _every_normal_points_out(maps)


def test_dressed_stone_has_a_rough_joint_between_blocks() raises:
    # At 63 texels a texel center falls on the line between two blocks of an
    # even course, where the joint of mortar is.
    var maps = stone_maps(63, 1)
    var joint = maps.roughness.texel(31, 20).g
    assert_true(joint >= 240)
    assert_true(maps.roughness.texel(10, 20).g < joint)


def test_slate_is_dark_and_blue_gray_with_dark_gaps() raises:
    # A gap is a hundredth of a slate wide, so it needs a larger tile to fall
    # on a texel.
    var maps = slate_maps(256, 1)
    assert_true(_mean(maps.albedo, 0) < 140.0)
    assert_true(_mean(maps.albedo, 2) >= _mean(maps.albedo, 0) - 10.0)
    # The gaps between slates are nearly black.
    var darkest = Float64(255)
    for y in range(256):
        for x in range(256):
            darkest = min(darkest, Float64(maps.albedo.texel(x, y).g))
    assert_true(darkest < 50.0)
    _every_normal_points_out(maps)


def test_the_meadow_is_green_and_the_gravel_is_gray_brown() raises:
    var grass = grass_maps(_SIZE, 1)
    assert_true(_mean(grass.albedo, 1) > _mean(grass.albedo, 2) + 15.0)
    _every_normal_points_out(grass)
    var gravel = gravel_maps(_SIZE, 1)
    assert_true(_mean(gravel.albedo, 0) > _mean(gravel.albedo, 2))
    assert_true(_spread(gravel.albedo, 1) > 20.0)
    _every_normal_points_out(gravel)


def test_the_cards_of_leaves_and_needles_are_cut_out() raises:
    for which in range(2):
        var card = leaf_texture(_SIZE, 1) if which == 0 else needle_texture(
            _SIZE, 1
        )
        var clear = 0
        var solid = 0
        for y in range(_SIZE):
            for x in range(_SIZE):
                var alpha = card.texel(x, y).a
                if alpha == 0:
                    clear += 1
                elif alpha == 255:
                    solid += 1
        # A cut-out has both ground and leaf, and nothing in between before
        # the mip chain is built.
        assert_true(clear > _SIZE * _SIZE // 10)
        assert_true(solid > _SIZE * _SIZE // 40)
        assert_equal(clear + solid, _SIZE * _SIZE)


def test_a_set_of_maps_is_stored_with_its_repeat() raises:
    var assets = Assets()
    var maps = brick_maps(16, 1)
    var ids = maps^.store(assets, Vector2(1.0 / Float32(BRICK_TILE), 2.0))
    assert_equal(assets.textures.count(), 3)
    var albedo = assets.textures.get(ids[0]).repeat
    assert_almost_equal(albedo.y, 2.0, atol=1.0e-6)
    assert_almost_equal(assets.textures.get(ids[2]).repeat.y, 2.0, atol=1.0e-6)
    assert_true(assets.textures.get(ids[1]).repeat.x > 1.0)


def test_a_size_must_be_in_range() raises:
    with assert_raises(contains="texels along a side"):
        _ = brick_maps(7, 1)
    with assert_raises(contains="texels along a side"):
        _ = stone_maps(5000, 1)
    with assert_raises(contains="texels along a side"):
        _ = slate_maps(0, 1)
    with assert_raises(contains="texels along a side"):
        _ = grass_maps(-3, 1)
    with assert_raises(contains="texels along a side"):
        _ = gravel_maps(1, 1)
    with assert_raises(contains="texels along a side"):
        _ = leaf_texture(2, 1)
    with assert_raises(contains="texels along a side"):
        _ = needle_texture(9999, 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
