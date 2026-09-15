# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `materials.material`, `render.texture_store` and `core.assets`."""

from materials.material import BASIC, LAMBERT
from materials.material import MaterialId
from core.assets import Assets
from geometries.box import cube
from materials.material import (
    BACK_SIDE,
    MaterialId,
    DOUBLE_SIDE,
    FRONT_SIDE,
    Material,
    MaterialStore,
)
from render.framebuffer import Color
from render.texture import Texture, checkerboard
from render.texture_store import NO_TEXTURE, TextureId, TextureStore
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Length, METRE


def a_board() raises -> Texture:
    """Return a small checkerboard to store."""
    return checkerboard(4, 2, Color(255, 255, 255), Color(0, 0, 0))


# --- Material ---------------------------------------------------------------


def test_a_material_is_a_colour_by_default() raises:
    var paint = Material(Color(10, 20, 30))
    assert_equal(paint.color.r, UInt8(10))
    assert_equal(paint.map, NO_TEXTURE)
    assert_equal(paint.side, FRONT_SIDE)
    assert_false(paint.is_textured())


def test_a_material_is_lit_by_default() raises:
    var paint = Material(Color(10, 20, 30))
    assert_equal(paint.kind, LAMBERT)
    assert_true(paint.is_lit())


def test_a_basic_material_is_not_lit() raises:
    var flat = Material(Color(10, 20, 30), kind=BASIC)
    assert_equal(flat.kind, BASIC)
    assert_false(flat.is_lit())
    # Everything else is untouched by the choice.
    assert_equal(flat.opacity, Float32(1))
    assert_true(not flat.is_transparent())


def test_a_material_can_name_a_texture() raises:
    var paint = Material(Color(1, 2, 3), TextureId(4))
    assert_equal(paint.map, TextureId(4))
    assert_true(paint.is_textured())


def test_every_side_is_accepted() raises:
    # Each operand of the check has to be able to decide the outcome alone.
    assert_equal(
        Material(Color(0, 0, 0), NO_TEXTURE, FRONT_SIDE).side, FRONT_SIDE
    )
    assert_equal(
        Material(Color(0, 0, 0), NO_TEXTURE, BACK_SIDE).side, BACK_SIDE
    )
    assert_equal(
        Material(Color(0, 0, 0), NO_TEXTURE, DOUBLE_SIDE).side, DOUBLE_SIDE
    )


def test_a_negative_texture_id_that_is_not_absence_is_rejected() raises:
    # -1 means "no texture"; -2 is an id nothing can ever hold, which is a
    # mistake rather than a deliberate absence.
    with assert_raises():
        _ = Material(Color(0, 0, 0), TextureId(-2))


# --- MaterialStore ----------------------------------------------------------


def test_a_material_store_hands_out_increasing_ids() raises:
    var store = MaterialStore()
    assert_equal(store.count(), 0)
    assert_equal(store.add(Material(Color(1, 0, 0))), MaterialId(0))
    assert_equal(store.add(Material(Color(0, 1, 0))), MaterialId(1))
    assert_equal(store.count(), 2)


def test_a_material_comes_back_as_it_went_in() raises:
    var store = MaterialStore()
    var id = store.add(Material(Color(9, 8, 7), NO_TEXTURE, DOUBLE_SIDE))
    assert_equal(store.get(id).color.g, UInt8(8))
    assert_equal(store.get(id).side, DOUBLE_SIDE)


def test_an_unknown_material_id_is_rejected() raises:
    var store = MaterialStore()
    with assert_raises():
        _ = store.get(MaterialId(0))
    with assert_raises():
        _ = store.get(MaterialId(-1))


# --- TextureStore -----------------------------------------------------------


def test_a_texture_store_hands_out_increasing_ids() raises:
    var store = TextureStore()
    assert_equal(store.count(), 0)
    assert_equal(store.add(a_board()), TextureId(0))
    assert_equal(store.add(a_board()), TextureId(1))
    assert_equal(store.count(), 2)


def test_a_stored_texture_is_borrowed_not_copied() raises:
    # As with geometry: `ref` binds it, and `var` would be a compile error.
    var store = TextureStore()
    var id = store.add(a_board())
    ref image = store.get(id)
    assert_equal(image.width, 4)
    assert_equal(image.texel(0, 0).r, UInt8(255))


def test_an_unknown_texture_id_is_rejected() raises:
    var store = TextureStore()
    with assert_raises():
        _ = store.get(TextureId(0))
    with assert_raises():
        _ = store.get(TextureId(-1))


# --- Assets -----------------------------------------------------------------


def test_assets_start_empty() raises:
    var assets = Assets()
    assert_equal(assets.geometries.count(), 0)
    assert_equal(assets.materials.count(), 0)
    assert_equal(assets.textures.count(), 0)


def test_assets_hold_the_three_stores_independently() raises:
    # One of each, and adding to one must not disturb the others.
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METRE)))
    var board = assets.textures.add(a_board())
    var paint = assets.materials.add(
        Material(Color(200, 100, 50), board, DOUBLE_SIDE)
    )
    assert_equal(assets.geometries.count(), 1)
    assert_equal(assets.textures.count(), 1)
    assert_equal(assets.materials.count(), 1)
    assert_equal(assets.geometries.get(box).triangle_count(), 12)
    assert_equal(assets.textures.get(board).width, 4)
    assert_equal(assets.materials.get(paint).map, board)


def test_two_materials_can_share_one_texture() raises:
    # Why the texture store exists: an image is large, and two materials
    # differing only in colour should cost one copy of it between them.
    var assets = Assets()
    var board = assets.textures.add(a_board())
    var first = assets.materials.add(Material(Color(255, 0, 0), board))
    var second = assets.materials.add(Material(Color(0, 0, 255), board))
    assert_equal(assets.textures.count(), 1)
    assert_equal(assets.materials.get(first).map, board)
    assert_equal(assets.materials.get(second).map, board)
    assert_true(assets.materials.get(first).color.r > 0)
    assert_true(assets.materials.get(second).color.b > 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
