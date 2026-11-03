# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the look of a castle: a material for each kind of surface."""

from core.assets import Assets
from extensions.castle.kinds import (
    BARK,
    BRICK,
    FOLIAGE,
    GLASS,
    GRAVEL,
    LAWN,
    METAL,
    SLATE,
    STONE,
    WATER,
    WOOD,
)
from extensions.castle.look import castle_look
from render.texture_store import NO_TEXTURE
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)


def test_each_kind_of_surface_has_a_material_of_its_own() raises:
    var assets = Assets()
    var look = castle_look(assets, 16)
    assert_equal(len(look.materials), 11)
    # Eleven kinds, the trunk and the needles.
    assert_equal(assets.materials.count(), 13)
    var seen = List[Int]()
    for kind in [
        BRICK,
        STONE,
        SLATE,
        WATER,
        LAWN,
        GRAVEL,
        FOLIAGE,
        GLASS,
        WOOD,
        METAL,
        BARK,
    ]:
        var id = look.material(kind).value
        assert_true(id not in seen)
        seen.append(id)
    assert_true(look.trunk.value not in seen)
    assert_true(look.needles.value not in seen)
    assert_true(look.trunk.value != look.needles.value)


def test_a_wall_wears_its_maps_and_glass_shines() raises:
    var assets = Assets()
    var look = castle_look(assets, 16)
    var brick = assets.materials.get(look.material(BRICK))
    assert_true(brick.map.value != NO_TEXTURE.value)
    assert_true(brick.normal_map.value != NO_TEXTURE.value)
    assert_true(brick.vertex_colors)
    assert_almost_equal(brick.roughness, 1.0)
    var glass = assets.materials.get(look.material(GLASS))
    assert_almost_equal(glass.roughness, 0.05)
    assert_almost_equal(glass.env_map_intensity, 1.4)
    var metal = assets.materials.get(look.material(METAL))
    assert_almost_equal(metal.metalness, 0.25)


def test_leaves_and_needles_are_cut_out_by_their_alpha() raises:
    var assets = Assets()
    var look = castle_look(assets, 16)
    var leaves = assets.materials.get(look.material(FOLIAGE))
    var needles = assets.materials.get(look.needles)
    assert_almost_equal(leaves.alpha_test, 0.5)
    assert_almost_equal(needles.alpha_test, 0.5)
    var trunk = assets.materials.get(look.trunk)
    assert_true(trunk.map.value == NO_TEXTURE.value)
    assert_true(not trunk.vertex_colors)


def test_a_texture_must_be_a_size_the_maps_allow() raises:
    var assets = Assets()
    with assert_raises():
        _ = castle_look(assets, 4)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
