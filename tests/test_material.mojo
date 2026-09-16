# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `materials.material`, `render.texture_store` and `core.assets`."""

from materials.material import BLEND, OPAQUE, Blending, MaterialKind, Side
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
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Length, METER


def a_board() raises -> Texture:
    """Return a small checkerboard to store."""
    return checkerboard(4, 2, Color(255, 255, 255), Color(0, 0, 0))


# --- Material ---------------------------------------------------------------


def test_a_material_is_a_color_by_default() raises:
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


def test_a_wrong_value_in_the_right_type_is_refused() raises:
    # The types stop a bare integer at compile time; they do not stop a
    # struct built from one, because Mojo's fields are open. So the
    # constructor asks, and each named value has to pass on its own.
    assert_true(FRONT_SIDE.is_valid())
    assert_true(BACK_SIDE.is_valid())
    assert_true(DOUBLE_SIDE.is_valid())
    assert_false(Side(99).is_valid())
    assert_true(OPAQUE.is_valid())
    assert_true(BLEND.is_valid())
    assert_false(Blending(7).is_valid())
    assert_true(BASIC.is_valid())
    assert_true(LAMBERT.is_valid())
    assert_false(MaterialKind(7).is_valid())
    with assert_raises():
        _ = Material(Color(0, 0, 0), NO_TEXTURE, Side(99))
    with assert_raises():
        _ = Material(Color(0, 0, 0), blending=Blending(7))
    with assert_raises():
        _ = Material(Color(0, 0, 0), kind=MaterialKind(7))
    # Editing one after the fact is possible too; the rasterizers check.
    var changed = OPAQUE
    changed.value = 7
    assert_false(changed.is_valid())


def test_a_material_ignores_vertex_colors_unless_asked() raises:
    assert_false(Material(Color(1, 2, 3)).vertex_colors)
    assert_true(Material(Color(1, 2, 3), vertex_colors=True).vertex_colors)
    # On an unlit material too, as three.js's MeshBasicMaterial has it.
    assert_true(
        Material(Color(1, 2, 3), kind=BASIC, vertex_colors=True).vertex_colors
    )


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


# --- emissive ---------------------------------------------------------------


def test_a_material_gives_off_no_light_by_default() raises:
    var paint = Material(Color(10, 20, 30))
    assert_equal(paint.emissive.r, UInt8(0))
    assert_equal(paint.emissive.g, UInt8(0))
    assert_equal(paint.emissive.b, UInt8(0))
    assert_equal(paint.emissive_intensity, Float32(1))
    assert_equal(paint.emissive_map, NO_TEXTURE)
    assert_false(paint.is_emissive())
    var glow = paint.emissive_light()
    assert_equal(glow.r, Float32(0))
    assert_equal(glow.g, Float32(0))
    assert_equal(glow.b, Float32(0))


def test_an_emissive_material_glows_by_its_color_times_its_intensity() raises:
    var lamp = Material(
        Color(10, 20, 30),
        emissive=Color(255, 255, 255),
        emissive_intensity=0.5,
    )
    assert_true(lamp.is_emissive())
    var glow = lamp.emissive_light()
    assert_almost_equal(glow.r, Float32(0.5), atol=Float64(1e-6))
    assert_almost_equal(glow.g, Float32(0.5), atol=Float64(1e-6))
    assert_almost_equal(glow.b, Float32(0.5), atol=Float64(1e-6))
    assert_equal(glow.a, Float32(1))
    # Decoded from sRGB, as the base color is: a mid gray is not half light.
    var dim = Material(Color(0, 0, 0), emissive=Color(128, 128, 128))
    assert_true(dim.emissive_light().r < 0.25)
    assert_true(dim.emissive_light().r > 0.2)


def test_any_channel_at_any_positive_intensity_is_a_glow() raises:
    # Each operand of the check has to decide the outcome on its own.
    assert_true(Material(Color(0, 0, 0), emissive=Color(1, 0, 0)).is_emissive())
    assert_true(Material(Color(0, 0, 0), emissive=Color(0, 1, 0)).is_emissive())
    assert_true(Material(Color(0, 0, 0), emissive=Color(0, 0, 1)).is_emissive())
    assert_false(
        Material(Color(0, 0, 0), emissive=Color(0, 0, 0)).is_emissive()
    )
    assert_false(
        Material(
            Color(0, 0, 0), emissive=Color(1, 0, 0), emissive_intensity=0
        ).is_emissive()
    )


def test_an_emissive_map_alone_adds_nothing() raises:
    # The map multiplies the emissive color, and black times anything is
    # black, as in three.js.
    var mapped = Material(Color(0, 0, 0), emissive_map=TextureId(3))
    assert_equal(mapped.emissive_map, TextureId(3))
    assert_false(mapped.is_emissive())
    var lit = Material(
        Color(0, 0, 0), emissive=Color(255, 255, 255), emissive_map=TextureId(3)
    )
    assert_true(lit.is_emissive())


def test_a_basic_material_refuses_an_emissive_term() raises:
    # three.js's MeshBasicMaterial has none: an unlit surface already shows
    # its own color. The color alone or the map alone is refused.
    with assert_raises():
        _ = Material(Color(0, 0, 0), kind=BASIC, emissive=Color(255, 0, 0))
    with assert_raises():
        _ = Material(Color(0, 0, 0), kind=BASIC, emissive_map=TextureId(0))
    # Black at any intensity is no term at all, and is fine.
    _ = Material(Color(0, 0, 0), kind=BASIC, emissive_intensity=4.0)
    # A lit material with the same term is what the term is for.
    _ = Material(
        Color(0, 0, 0), emissive=Color(255, 0, 0), emissive_map=TextureId(0)
    )


def test_a_bad_emissive_map_id_or_intensity_is_rejected() raises:
    with assert_raises():
        _ = Material(Color(0, 0, 0), emissive_map=TextureId(-2))
    with assert_raises():
        _ = Material(Color(0, 0, 0), emissive_intensity=-0.5)
    # The absence value is fine, and so is an intensity of zero.
    _ = Material(Color(0, 0, 0), emissive_map=NO_TEXTURE, emissive_intensity=0)


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
    var box = assets.geometries.add(cube(Length(1.0, METER)))
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
    # differing only in color should cost one copy of it between them.
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
