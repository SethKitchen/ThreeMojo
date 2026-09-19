# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `materials.material`, `render.texture_store` and `core.assets`."""

from materials.material import BLEND, OPAQUE, Blending, MaterialKind, Side
from materials.material import (
    BASIC,
    DEPTH,
    LAMBERT,
    MATCAP,
    NORMALS,
    PHONG,
    TOON,
)
from materials.material import (
    DEFAULT_DASH_SIZE,
    DEFAULT_GAP_SIZE,
    DEFAULT_POINT_SIZE,
    NO_DASH,
    NO_ROTATION,
    PointSize,
    depth_material,
    line_dashed_material,
    matcap_material,
    normal_material,
    phong_material,
    points_material,
    sprite_material,
    toon_material,
)
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
from render.framebuffer import Color, FloatColor
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
from std.math import inf, nan
from units.si import Angle, DEGREE, Length, METER, RADIAN


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


def test_the_data_kinds_show_data_rather_than_light() raises:
    # `is_data` is what both rasterizers ask before they light a fragment,
    # fog it or tone map it, so each kind has to answer for itself.
    assert_true(NORMALS.is_data())
    assert_true(DEPTH.is_data())
    assert_false(BASIC.is_data())
    assert_false(LAMBERT.is_data())
    assert_true(normal_material().is_data())
    assert_true(depth_material().is_data())
    assert_false(Material(Color(1, 2, 3)).is_data())
    # Neither is lit: a normal and a depth are not reflections of anything.
    assert_false(normal_material().is_lit())
    assert_false(depth_material().is_lit())


def test_a_normal_material_is_white_and_front_facing_by_default() raises:
    var shown = normal_material()
    assert_equal(shown.kind, NORMALS)
    assert_equal(shown.color.r, UInt8(255))
    assert_equal(shown.map, NO_TEXTURE)
    assert_equal(shown.side, FRONT_SIDE)
    assert_equal(shown.opacity, Float32(1))
    assert_false(shown.is_transparent())
    # And it takes the properties its shader does read. An opacity below
    # one would make it blend, which a data material cannot do, so an
    # explicit OPAQUE is what keeps such a surface legal.
    var pane = normal_material(DOUBLE_SIDE, 0.5, OPAQUE)
    assert_equal(pane.side, DOUBLE_SIDE)
    assert_equal(pane.opacity, Float32(0.5))
    assert_false(pane.is_transparent())


def test_a_depth_material_takes_a_map_that_cuts_it_out() raises:
    var shown = depth_material()
    assert_equal(shown.kind, DEPTH)
    assert_equal(shown.map, NO_TEXTURE)
    assert_false(shown.is_textured())
    # A map is allowed, unlike on a normal material: three.js's
    # `MeshDepthMaterial` reads its alpha, which cuts the surface out.
    var cut = depth_material(TextureId(2), BACK_SIDE, 0.25, OPAQUE)
    assert_equal(cut.map, TextureId(2))
    assert_true(cut.is_textured())
    assert_equal(cut.side, BACK_SIDE)
    assert_equal(cut.opacity, Float32(0.25))
    assert_false(cut.is_transparent())
    # The same refusals every material makes still apply.
    with assert_raises():
        _ = depth_material(TextureId(-2))
    with assert_raises():
        _ = depth_material(NO_TEXTURE, Side(99))
    with assert_raises():
        _ = depth_material(NO_TEXTURE, FRONT_SIDE, 2.0)
    with assert_raises():
        _ = normal_material(FRONT_SIDE, 1.0, Blending(7))


def test_a_data_material_cannot_blend() raises:
    # One pixel cannot hold part of a normal and part of the scene's
    # light, so the mixture is refused rather than resolved as neither.
    # Stated outright, or taken from `transparent`. An opacity below one
    # on its own changes nothing, as in three.js, and is allowed.
    for kind in [NORMALS, DEPTH]:
        with assert_raises():
            _ = Material(Color(255, 255, 255), kind=kind, blending=BLEND)
        with assert_raises():
            _ = Material(Color(255, 255, 255), kind=kind, transparent=True)
        # Opaque, stated or by default, is what such a surface must be.
        _ = Material(Color(255, 255, 255), kind=kind)
        _ = Material(Color(255, 255, 255), kind=kind, opacity=0.5)
        _ = Material(
            Color(255, 255, 255), kind=kind, opacity=0.5, blending=OPAQUE
        )
    with assert_raises():
        _ = normal_material(FRONT_SIDE, 1.0, BLEND)
    _ = normal_material(FRONT_SIDE, 0.5)
    with assert_raises():
        _ = depth_material(NO_TEXTURE, FRONT_SIDE, 1.0, BLEND)
    _ = depth_material(NO_TEXTURE, FRONT_SIDE, 0.25)
    # A lit material blends as it always did, which is what makes the
    # refusal about the kind and not about the policy.
    _ = Material(Color(255, 255, 255), kind=LAMBERT, blending=BLEND)
    _ = Material(Color(255, 255, 255), kind=BASIC, opacity=0.5)


def test_a_data_material_refuses_a_color_that_is_not_opaque_white() raises:
    # Neither shader reads a color, so a value there is a mistake rather
    # than a choice. Each channel has to be able to say so on its own.
    for kind in [NORMALS, DEPTH]:
        _ = Material(Color(255, 255, 255), kind=kind)
        with assert_raises():
            _ = Material(Color(254, 255, 255), kind=kind)
        with assert_raises():
            _ = Material(Color(255, 254, 255), kind=kind)
        with assert_raises():
            _ = Material(Color(255, 255, 254), kind=kind)
        with assert_raises():
            _ = Material(Color(255, 255, 255, 254), kind=kind)


def test_a_data_material_refuses_light_and_vertex_colors() raises:
    # An emissive color, an emissive map or the vertex colors: each is read
    # by no shader here, and each is refused on its own.
    for kind in [NORMALS, DEPTH]:
        with assert_raises():
            _ = Material(
                Color(255, 255, 255), kind=kind, emissive=Color(255, 0, 0)
            )
        with assert_raises():
            _ = Material(
                Color(255, 255, 255), kind=kind, emissive_map=TextureId(0)
            )
        with assert_raises():
            _ = Material(Color(255, 255, 255), kind=kind, vertex_colors=True)
        # A black emissive at any intensity is no term at all, and passes.
        _ = Material(Color(255, 255, 255), kind=kind, emissive_intensity=3.0)


def test_a_normal_material_refuses_a_map() raises:
    # It shows the normal, not an image. A depth material is the one that
    # reads a map, so the kind decides this on its own.
    with assert_raises():
        _ = Material(Color(255, 255, 255), TextureId(0), kind=NORMALS)
    _ = Material(Color(255, 255, 255), NO_TEXTURE, kind=NORMALS)
    _ = Material(Color(255, 255, 255), TextureId(0), kind=DEPTH)


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
    assert_true(NORMALS.is_valid())
    assert_true(DEPTH.is_valid())
    assert_true(PHONG.is_valid())
    assert_true(TOON.is_valid())
    assert_true(MATCAP.is_valid())
    assert_false(MaterialKind(9).is_valid())
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


# --- alpha map and alpha test -----------------------------------------------


def test_a_material_thins_nothing_by_default() raises:
    var paint = Material(Color(10, 20, 30))
    assert_equal(paint.alpha_map, NO_TEXTURE)
    assert_equal(paint.alpha_test, Float32(0))
    assert_false(paint.has_alpha_map())
    assert_false(paint.is_alpha_tested())


def test_a_material_can_name_an_alpha_map_and_a_test() raises:
    var leaf = Material(
        Color(255, 255, 255), alpha_map=TextureId(3), alpha_test=0.5
    )
    assert_equal(leaf.alpha_map, TextureId(3))
    assert_equal(leaf.alpha_test, Float32(0.5))
    assert_true(leaf.has_alpha_map())
    assert_true(leaf.is_alpha_tested())
    # A test of exactly zero is no test, as in three.js.
    assert_false(Material(Color(1, 2, 3), alpha_test=0.0).is_alpha_tested())


def test_a_bad_alpha_map_id_or_test_is_rejected() raises:
    with assert_raises():
        _ = Material(Color(0, 0, 0), alpha_map=TextureId(-2))
    with assert_raises():
        _ = Material(Color(0, 0, 0), alpha_test=-0.5)
    with assert_raises():
        _ = Material(Color(0, 0, 0), alpha_test=1.5)
    # Not a number is worse than out of range: every comparison with it is
    # false, so the test would silently stop testing.
    with assert_raises():
        _ = Material(Color(0, 0, 0), alpha_test=nan[DType.float32]())
    # The absence value and both ends of the range are fine.
    _ = Material(Color(0, 0, 0), alpha_map=NO_TEXTURE, alpha_test=0.0)
    _ = Material(Color(0, 0, 0), alpha_test=1.0)


def test_a_normal_material_refuses_an_alpha_map_and_takes_a_test() raises:
    # three.js's MeshNormalMaterial has no alphaMap and does have alphaTest,
    # which cuts by the opacity alone.
    with assert_raises():
        _ = Material(Color(255, 255, 255), kind=NORMALS, alpha_map=TextureId(0))
    var cut = normal_material(FRONT_SIDE, 0.4, OPAQUE, 0.5)
    assert_equal(cut.alpha_test, Float32(0.5))
    assert_false(cut.has_alpha_map())
    # A depth material takes both, as three.js's MeshDepthMaterial does.
    var masked = depth_material(
        NO_TEXTURE, FRONT_SIDE, 1.0, None, TextureId(1), 0.25
    )
    assert_equal(masked.alpha_map, TextureId(1))
    assert_equal(masked.alpha_test, Float32(0.25))


# --- phong ------------------------------------------------------------------


def test_a_phong_material_is_lit_and_shows_no_data() raises:
    assert_true(PHONG.is_valid())
    assert_true(PHONG.is_lit())
    assert_false(PHONG.is_data())
    assert_true(LAMBERT.is_lit())
    assert_false(BASIC.is_lit())
    assert_false(NORMALS.is_lit())
    assert_false(DEPTH.is_lit())
    assert_true(TOON.is_lit())
    assert_false(MATCAP.is_lit())
    var shiny = phong_material(Color(200, 40, 40))
    assert_equal(shiny.kind, PHONG)
    assert_true(shiny.is_lit())
    assert_false(shiny.is_data())


def test_a_phong_material_carries_three_js_defaults() raises:
    # three.js's MeshPhongMaterial: a specular of 0x111111 and a shininess
    # of thirty.
    var shiny = phong_material(Color(200, 40, 40))
    assert_equal(shiny.specular.r, UInt8(17))
    assert_equal(shiny.specular.g, UInt8(17))
    assert_equal(shiny.specular.b, UInt8(17))
    assert_equal(shiny.shininess, Float32(30))
    assert_true(shiny.has_highlight())
    assert_equal(shiny.specular_light().r, FloatColor(srgb=shiny.specular).r)
    # And every other property comes through as it does on any material.
    var pane = phong_material(
        Color(1, 2, 3),
        TextureId(4),
        Color(255, 255, 255),
        5.0,
        DOUBLE_SIDE,
        0.5,
    )
    assert_equal(pane.map, TextureId(4))
    assert_equal(pane.shininess, Float32(5))
    assert_equal(pane.side, DOUBLE_SIDE)
    # An opacity below one blends only when the material is transparent,
    # as in three.js.
    assert_false(pane.is_transparent())
    assert_true(
        phong_material(
            Color(1, 2, 3), NO_TEXTURE, Color(0, 0, 0), 5.0, transparent=True
        ).is_transparent()
    )
    assert_true(
        phong_material(
            Color(1, 2, 3),
            NO_TEXTURE,
            Color(0, 0, 0),
            30.0,
            FRONT_SIDE,
            1.0,
            BLEND,
        ).is_transparent()
    )


def test_a_highlight_belongs_to_the_kind_and_not_to_the_color() raises:
    # `has_highlight` asks the kind. A black specular is a base reflectance
    # of zero rather than a term switched off: three.js's Fresnel factor
    # still rises toward one at a grazing angle, so such a surface catches
    # a dim rim where a lambert one catches nothing. Saying "no highlight"
    # there would promise what the shader does not do.
    var dull = Material(Color(200, 40, 40), kind=PHONG)
    assert_equal(dull.specular.r, UInt8(0))
    assert_equal(dull.shininess, Float32(0))
    assert_true(dull.has_highlight())
    assert_equal(dull.specular_light().r, Float32(0))
    for sheen in [Color(1, 0, 0), Color(0, 1, 0), Color(0, 0, 1)]:
        assert_true(
            Material(Color(1, 2, 3), kind=PHONG, specular=sheen).has_highlight()
        )
    # Every other kind reflects none, whatever else it carries.
    assert_false(Material(Color(1, 2, 3)).has_highlight())
    assert_false(Material(Color(1, 2, 3), kind=BASIC).has_highlight())
    assert_false(normal_material().has_highlight())
    assert_false(depth_material().has_highlight())


def test_a_specular_is_decoded_to_linear_light() raises:
    # As the emissive is: an authored byte is not proportional to light.
    var shiny = Material(
        Color(0, 0, 0), kind=PHONG, specular=Color(255, 255, 255)
    )
    var sheen = shiny.specular_light()
    assert_equal(sheen.r, Float32(1))
    assert_equal(sheen.a, Float32(1))
    var dim = Material(
        Color(0, 0, 0), kind=PHONG, specular=Color(128, 128, 128)
    )
    assert_true(dim.specular_light().r < 0.25)
    assert_true(dim.specular_light().r > 0.2)
    # A material with no highlight sends nothing.
    assert_equal(Material(Color(1, 2, 3)).specular_light().r, Float32(0))


def test_only_a_phong_material_has_a_highlight() raises:
    # No other shader here reads either property, so a value in one is a
    # mistake rather than a choice. Each refuses on its own.
    for kind in [BASIC, LAMBERT, NORMALS, DEPTH]:
        var color = Color(255, 255, 255)
        with assert_raises():
            _ = Material(color, kind=kind, specular=Color(17, 17, 17))
        with assert_raises():
            _ = Material(color, kind=kind, shininess=30.0)
        # Black at a shininess of zero is no highlight, and is fine.
        _ = Material(color, kind=kind, specular=Color(0, 0, 0), shininess=0.0)
    # A phong material takes both, which is what they are for.
    _ = Material(
        Color(255, 255, 255),
        kind=PHONG,
        specular=Color(17, 17, 17),
        shininess=30.0,
    )


def test_a_shininess_that_is_not_a_number_is_rejected() raises:
    with assert_raises():
        _ = Material(Color(1, 2, 3), kind=PHONG, shininess=-1.0)
    with assert_raises():
        _ = Material(Color(1, 2, 3), kind=PHONG, shininess=nan[DType.float32]())
    with assert_raises():
        _ = phong_material(Color(1, 2, 3), NO_TEXTURE, Color(17, 17, 17), -5.0)
    # Zero is the widest lobe three.js allows, and any size above it is fine.
    _ = Material(Color(1, 2, 3), kind=PHONG, shininess=0.0)
    _ = Material(Color(1, 2, 3), kind=PHONG, shininess=1000.0)


# --- a toon material steps through a ramp -----------------------------------


def test_a_toon_material_is_lit_and_shows_no_data() raises:
    assert_true(TOON.is_valid())
    assert_true(TOON.is_lit())
    assert_false(TOON.is_data())
    var flat = toon_material(Color(200, 40, 40))
    assert_equal(flat.kind, TOON)
    assert_true(flat.is_lit())
    assert_false(flat.is_data())
    # It has no highlight: a ramp is a diffuse term, and three.js's
    # `MeshToonMaterial` has no specular at all.
    assert_false(flat.has_highlight())
    assert_equal(flat.shininess, Float32(0))


def test_a_toon_material_names_its_ramp_or_takes_the_fallback() raises:
    # With no ramp it is not unramped: three.js's two-tone fallback
    # applies, which is why the default is a material and not an error.
    var plain = toon_material(Color(200, 40, 40))
    assert_equal(plain.gradient_map, NO_TEXTURE)
    assert_false(plain.has_gradient_map())
    var stepped = toon_material(Color(200, 40, 40), NO_TEXTURE, TextureId(3))
    assert_equal(stepped.gradient_map, TextureId(3))
    assert_true(stepped.has_gradient_map())
    # And every other property comes through as it does on any material.
    var pane = toon_material(
        Color(1, 2, 3), TextureId(4), TextureId(5), DOUBLE_SIDE, 0.5
    )
    assert_equal(pane.map, TextureId(4))
    assert_equal(pane.gradient_map, TextureId(5))
    assert_equal(pane.side, DOUBLE_SIDE)
    assert_equal(pane.opacity, Float32(0.5))
    assert_false(pane.is_transparent())
    assert_true(
        toon_material(Color(1, 2, 3), transparent=True).is_transparent()
    )
    assert_true(toon_material(Color(1, 2, 3), blending=BLEND).is_transparent())
    # Every other kind names no ramp, whatever else it carries.
    assert_false(Material(Color(1, 2, 3)).has_gradient_map())
    assert_false(phong_material(Color(1, 2, 3)).has_gradient_map())
    assert_false(normal_material().has_gradient_map())


def test_only_a_toon_material_steps_through_a_ramp() raises:
    # No other shader reads one, so a ramp elsewhere is a mistake rather
    # than a value to ignore -- the same rule a specular follows.
    for kind in [BASIC, LAMBERT, NORMALS, DEPTH, PHONG]:
        with assert_raises():
            _ = Material(
                Color(255, 255, 255), kind=kind, gradient_map=TextureId(1)
            )
    _ = Material(Color(1, 2, 3), kind=TOON, gradient_map=TextureId(1))


def test_a_bad_gradient_map_id_is_rejected() raises:
    with assert_raises():
        _ = toon_material(Color(1, 2, 3), NO_TEXTURE, TextureId(-2))
    with assert_raises():
        _ = Material(Color(1, 2, 3), kind=TOON, gradient_map=TextureId(-7))
    # `NO_TEXTURE` is the one negative that means something.
    _ = toon_material(Color(1, 2, 3), NO_TEXTURE, NO_TEXTURE)
    # The refusals every material makes still apply to this builder.
    with assert_raises():
        _ = toon_material(Color(1, 2, 3), TextureId(-2))
    with assert_raises():
        _ = toon_material(Color(1, 2, 3), NO_TEXTURE, NO_TEXTURE, Side(99))
    with assert_raises():
        _ = toon_material(
            Color(1, 2, 3), NO_TEXTURE, NO_TEXTURE, FRONT_SIDE, 2.0
        )
    with assert_raises():
        _ = toon_material(
            Color(1, 2, 3),
            NO_TEXTURE,
            NO_TEXTURE,
            FRONT_SIDE,
            1.0,
            Blending(7),
        )


# --- a matcap material is looked up in an image -----------------------------


def test_a_matcap_material_is_unlit_and_shows_no_data() raises:
    assert_true(MATCAP.is_valid())
    assert_false(MATCAP.is_lit())
    assert_false(MATCAP.is_data())
    assert_true(MATCAP.is_unlit())
    assert_true(BASIC.is_unlit())
    assert_false(LAMBERT.is_unlit())
    assert_false(PHONG.is_unlit())
    assert_false(TOON.is_unlit())
    assert_false(NORMALS.is_unlit())
    assert_false(DEPTH.is_unlit())
    var ball = matcap_material(TextureId(2))
    assert_equal(ball.kind, MATCAP)
    assert_false(ball.is_lit())
    assert_false(ball.is_data())
    assert_false(ball.has_highlight())


def test_a_matcap_material_names_its_image_or_takes_the_gradient() raises:
    # The image comes first, because the surface is the image. The color
    # is a tint over it, and white leaves it alone.
    var ball = matcap_material(TextureId(2))
    assert_equal(ball.matcap, TextureId(2))
    assert_true(ball.has_matcap())
    assert_equal(ball.color.r, UInt8(255))
    assert_equal(ball.color.g, UInt8(255))
    assert_equal(ball.color.b, UInt8(255))
    # With none it is not unlookupable: three.js's gray gradient applies.
    var plain = matcap_material()
    assert_equal(plain.matcap, NO_TEXTURE)
    assert_false(plain.has_matcap())
    # And every other property comes through as it does on any material.
    var pane = matcap_material(
        TextureId(2), Color(1, 2, 3), TextureId(4), DOUBLE_SIDE, 0.5
    )
    assert_equal(pane.color.r, UInt8(1))
    assert_equal(pane.map, TextureId(4))
    assert_equal(pane.side, DOUBLE_SIDE)
    assert_equal(pane.opacity, Float32(0.5))
    assert_false(pane.is_transparent())
    assert_true(matcap_material(transparent=True).is_transparent())
    # Every other kind names no image, whatever else it carries.
    assert_false(Material(Color(1, 2, 3)).has_matcap())
    assert_false(toon_material(Color(1, 2, 3)).has_matcap())
    assert_false(normal_material().has_matcap())


def test_only_a_matcap_material_is_looked_up_in_an_image() raises:
    for kind in [BASIC, LAMBERT, NORMALS, DEPTH, PHONG, TOON]:
        with assert_raises():
            _ = Material(Color(255, 255, 255), kind=kind, matcap=TextureId(1))
    _ = Material(Color(1, 2, 3), kind=MATCAP, matcap=TextureId(1))


def test_a_matcap_material_has_no_emissive_term() raises:
    # The image already holds every bit of light the surface shows, so an
    # emissive term is a mistake rather than an addition -- the rule a
    # basic material follows, and the reason both answer `is_unlit`.
    with assert_raises():
        _ = Material(
            Color(255, 255, 255), kind=MATCAP, emissive=Color(10, 10, 10)
        )
    with assert_raises():
        _ = Material(
            Color(255, 255, 255), kind=MATCAP, emissive_map=TextureId(1)
        )
    # A black emissive adds nothing and is allowed, as on a basic material.
    _ = Material(Color(255, 255, 255), kind=MATCAP, emissive=Color(0, 0, 0))


def test_a_bad_matcap_id_is_rejected() raises:
    with assert_raises():
        _ = matcap_material(TextureId(-2))
    with assert_raises():
        _ = Material(Color(1, 2, 3), kind=MATCAP, matcap=TextureId(-7))
    _ = matcap_material(NO_TEXTURE)
    # The refusals every material makes still apply to this builder.
    with assert_raises():
        _ = matcap_material(NO_TEXTURE, Color(1, 2, 3), TextureId(-2))
    with assert_raises():
        _ = matcap_material(NO_TEXTURE, Color(1, 2, 3), NO_TEXTURE, Side(99))
    with assert_raises():
        _ = matcap_material(
            NO_TEXTURE, Color(1, 2, 3), NO_TEXTURE, FRONT_SIDE, 2.0
        )
    with assert_raises():
        _ = matcap_material(
            NO_TEXTURE,
            Color(1, 2, 3),
            NO_TEXTURE,
            FRONT_SIDE,
            1.0,
            Blending(7),
        )


def test_a_material_is_solid_unless_asked() raises:
    var plain = Material(Color(255, 255, 255))
    assert_false(plain.is_dashed())
    assert_true(plain.dash_size == NO_DASH)
    assert_true(plain.gap_size == NO_DASH)
    assert_equal(plain.dash_scale, Float32(1))
    # A dash with no gap is a solid line too, as three.js draws it.
    var gapless = Material(
        Color(255, 255, 255), kind=BASIC, dash_size=Length(2.0, METER)
    )
    assert_false(gapless.is_dashed())


def test_a_dashed_line_material_takes_threejs_defaults() raises:
    var dashed = line_dashed_material(Color(255, 0, 0))
    assert_true(dashed.is_dashed())
    assert_true(dashed.kind == BASIC)
    assert_true(dashed.dash_size == DEFAULT_DASH_SIZE)
    assert_true(dashed.gap_size == DEFAULT_GAP_SIZE)
    assert_almost_equal(dashed.dash_size.to(METER), Float32(3), atol=1e-6)
    assert_almost_equal(dashed.gap_size.to(METER), Float32(1), atol=1e-6)
    assert_equal(dashed.dash_scale, Float32(1))
    assert_equal(dashed.color.r, 255)
    var spelled = line_dashed_material(
        Color(255, 0, 0),
        dash_size=Length(0.5, METER),
        gap_size=Length(0.25, METER),
        scale=2,
        opacity=0.5,
        transparent=True,
        vertex_colors=True,
    )
    assert_almost_equal(spelled.dash_size.to(METER), Float32(0.5), atol=1e-6)
    assert_almost_equal(spelled.gap_size.to(METER), Float32(0.25), atol=1e-6)
    assert_equal(spelled.dash_scale, Float32(2))
    assert_true(spelled.is_transparent())
    assert_true(spelled.vertex_colors)


def test_a_dash_and_a_gap_must_be_lengths() raises:
    with assert_raises(contains="dash size cannot be negative"):
        _ = line_dashed_material(
            Color(255, 0, 0), dash_size=Length(-1.0, METER)
        )
    with assert_raises(contains="dash size cannot be negative"):
        _ = line_dashed_material(
            Color(255, 0, 0), dash_size=Length(nan[DType.float32](), METER)
        )
    with assert_raises(contains="gap size cannot be negative"):
        _ = line_dashed_material(Color(255, 0, 0), gap_size=Length(-1.0, METER))
    with assert_raises(contains="gap size cannot be negative"):
        _ = line_dashed_material(
            Color(255, 0, 0), gap_size=Length(nan[DType.float32](), METER)
        )
    with assert_raises(contains="dash scale must be finite"):
        _ = line_dashed_material(Color(255, 0, 0), scale=nan[DType.float32]())
    # A scale below zero is allowed: it runs the pattern backward.
    var backward = line_dashed_material(Color(255, 0, 0), scale=-1)
    assert_equal(backward.dash_scale, Float32(-1))


def test_a_gap_with_no_dash_is_refused() raises:
    with assert_raises(contains="needs a dash"):
        _ = line_dashed_material(Color(255, 0, 0), dash_size=NO_DASH)


def test_only_a_basic_material_can_be_dashed() raises:
    with assert_raises(contains="Only a basic material can be dashed"):
        _ = Material(
            Color(255, 0, 0),
            kind=LAMBERT,
            dash_size=Length(1.0, METER),
            gap_size=Length(1.0, METER),
        )
    with assert_raises(contains="wireframe cannot be dashed"):
        _ = Material(
            Color(255, 0, 0),
            kind=BASIC,
            wireframe=True,
            dash_size=Length(1.0, METER),
            gap_size=Length(1.0, METER),
        )


def test_a_point_size_is_a_positive_number_of_pixels() raises:
    assert_true(PointSize(1.0).is_valid())
    assert_true(PointSize(0.25).is_valid())
    assert_false(PointSize(0.0).is_valid())
    assert_false(PointSize(-3.0).is_valid())
    assert_false(PointSize(nan[DType.float32]()).is_valid())
    assert_false(PointSize(inf[DType.float32]()).is_valid())
    assert_true(DEFAULT_POINT_SIZE == PointSize(1.0))


def test_a_material_draws_one_pixel_points_unless_asked() raises:
    var plain = Material(Color(255, 255, 255))
    assert_true(plain.point_size == DEFAULT_POINT_SIZE)
    assert_true(plain.size_attenuation)
    assert_true(plain.rotation == NO_ROTATION)


def test_a_points_material_takes_threejs_defaults() raises:
    var dots = points_material(Color(255, 0, 0))
    assert_true(dots.kind == BASIC)
    assert_true(dots.point_size == DEFAULT_POINT_SIZE)
    assert_true(dots.size_attenuation)
    assert_false(dots.is_transparent())
    assert_equal(dots.color.r, 255)
    var spelled = points_material(
        Color(255, 0, 0),
        size=PointSize(6.0),
        size_attenuation=False,
        map=TextureId(0),
        alpha_map=TextureId(1),
        alpha_test=0.5,
        opacity=0.5,
        transparent=True,
        vertex_colors=True,
    )
    assert_equal(spelled.point_size.pixels, Float32(6))
    assert_false(spelled.size_attenuation)
    assert_true(spelled.map == TextureId(0))
    assert_true(spelled.alpha_map == TextureId(1))
    assert_equal(spelled.alpha_test, Float32(0.5))
    assert_true(spelled.is_transparent())
    assert_true(spelled.vertex_colors)


def test_a_sprite_material_takes_threejs_defaults() raises:
    var badge = sprite_material()
    assert_true(badge.kind == BASIC)
    assert_equal(badge.color.r, 255)
    assert_equal(badge.color.g, 255)
    assert_equal(badge.color.b, 255)
    assert_true(badge.rotation == NO_ROTATION)
    assert_true(badge.size_attenuation)
    # Transparent by default, as three.js's is: a sprite is a cut-out.
    assert_true(badge.is_transparent())
    var spelled = sprite_material(
        Color(0, 255, 0),
        map=TextureId(2),
        alpha_map=TextureId(3),
        rotation=Angle(90.0, DEGREE),
        size_attenuation=False,
        alpha_test=0.25,
        opacity=0.75,
        transparent=False,
    )
    assert_equal(spelled.color.g, 255)
    assert_true(spelled.map == TextureId(2))
    assert_true(spelled.alpha_map == TextureId(3))
    assert_almost_equal(
        spelled.rotation.to(RADIAN), Float32(1.5707964), atol=1e-6
    )
    assert_false(spelled.size_attenuation)
    assert_equal(spelled.alpha_test, Float32(0.25))
    assert_false(spelled.is_transparent())


def test_a_point_size_that_is_not_a_size_is_refused() raises:
    with assert_raises(contains="positive number of pixels"):
        _ = points_material(Color(255, 0, 0), size=PointSize(0.0))
    with assert_raises(contains="positive number of pixels"):
        _ = points_material(Color(255, 0, 0), size=PointSize(-2.0))
    with assert_raises(contains="positive number of pixels"):
        _ = points_material(
            Color(255, 0, 0), size=PointSize(nan[DType.float32]())
        )


def test_a_sprite_rotation_must_be_finite() raises:
    with assert_raises(contains="rotation must be finite"):
        _ = sprite_material(rotation=Angle(nan[DType.float32](), RADIAN))
    with assert_raises(contains="rotation must be finite"):
        _ = sprite_material(rotation=Angle(inf[DType.float32](), RADIAN))
    # Any finite turn is allowed, more than a full one included.
    var twice = sprite_material(rotation=Angle(720.0, DEGREE))
    assert_almost_equal(twice.rotation.to(DEGREE), Float32(720), atol=1e-3)


def test_only_a_basic_material_draws_points_or_sprites() raises:
    with assert_raises(contains="Only a basic material draws points"):
        _ = Material(Color(255, 0, 0), kind=LAMBERT, point_size=PointSize(4.0))
    with assert_raises(contains="Only a basic material draws points"):
        _ = Material(Color(255, 0, 0), kind=PHONG, size_attenuation=False)
    with assert_raises(contains="Only a basic material draws a sprite"):
        _ = Material(
            Color(255, 0, 0), kind=LAMBERT, rotation=Angle(10.0, DEGREE)
        )
    # A lit material carrying the defaults is not a mistake: every
    # material carries them.
    var lit = Material(Color(255, 0, 0), kind=LAMBERT)
    assert_true(lit.point_size == DEFAULT_POINT_SIZE)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
