# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `materials.material`, `render.texture_store` and `core.assets`."""

from materials.material import BLEND, OPAQUE, Blending, MaterialKind, Side
from materials.material import (
    BASIC,
    DEPTH,
    DISTANCE,
    LAMBERT,
    MATCAP,
    NORMALS,
    PHONG,
    PHYSICAL,
    SHADOW,
    STANDARD,
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
    distance_material,
    line_dashed_material,
    matcap_material,
    normal_material,
    phong_material,
    physical_material,
    points_material,
    shadow_material,
    sprite_material,
    standard_material,
    toon_material,
)
from materials.material import (
    DEFAULT_IRIDESCENCE_IOR,
    DEFAULT_THICKNESS_MAXIMUM,
    DEFAULT_THICKNESS_MINIMUM,
    MaterialId,
)
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
from materials.material import (
    ADD_OPERATION,
    MIX_OPERATION,
    MULTIPLY_OPERATION,
    Combine,
    combine_light,
)
from render.cube_texture_store import (
    NO_CUBE_TEXTURE,
    SCENE_ENVIRONMENT,
    CubeTextureId,
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
from math.vector2 import Vector2
from std.math import inf, nan
from units.si import Angle, DEGREE, Length, METER, NANOMETER, RADIAN
from math.vector3 import Vector3
from render.packing import (
    BASIC_DEPTH_PACKING,
    RGBA_DEPTH_PACKING,
    RGB_DEPTH_PACKING,
    DepthPacking,
)


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
    assert_true(STANDARD.is_valid())
    assert_true(PHYSICAL.is_valid())
    assert_false(MaterialKind(11).is_valid())
    with assert_raises():
        _ = Material(Color(0, 0, 0), NO_TEXTURE, Side(99))
    with assert_raises():
        _ = Material(Color(0, 0, 0), blending=Blending(7))
    with assert_raises():
        _ = Material(Color(0, 0, 0), kind=MaterialKind(11))
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


# --- the environment ----------------------------------------------------------


def test_a_material_reflects_nothing_by_default() raises:
    var paint = Material(Color(1, 2, 3))
    assert_equal(paint.env_map, NO_CUBE_TEXTURE)
    assert_equal(paint.reflectivity, Float32(1))
    assert_equal(paint.combine, MULTIPLY_OPERATION)
    assert_false(paint.has_env_map())


def test_the_three_reflecting_kinds_take_an_env_map() raises:
    # three.js gives `envMap` to its basic, lambert and phong materials.
    for kind in [BASIC, LAMBERT, PHONG]:
        assert_true(kind.reflects())
        var paint = Material(
            Color(1, 2, 3),
            kind=kind,
            env_map=CubeTextureId(2),
            reflectivity=0.25,
            combine=ADD_OPERATION,
        )
        assert_equal(paint.env_map, CubeTextureId(2))
        assert_equal(paint.reflectivity, Float32(0.25))
        assert_equal(paint.combine, ADD_OPERATION)
        assert_true(paint.has_env_map())
    # And the scene's environment, which is not an id but is a map.
    var shared = Material(Color(1, 2, 3), env_map=SCENE_ENVIRONMENT)
    assert_true(shared.has_env_map())


def test_the_other_kinds_refuse_any_environment_term() raises:
    # No other three.js shader has an envmap chunk, so a value there is a
    # mistake rather than a value to ignore.
    for kind in [TOON, MATCAP, NORMALS, DEPTH]:
        assert_false(kind.reflects())
        var color = Color(1, 2, 3)
        if kind.is_data():
            color = Color(255, 255, 255)
        with assert_raises():
            _ = Material(color, kind=kind, env_map=CubeTextureId(0))
        with assert_raises():
            _ = Material(color, kind=kind, env_map=SCENE_ENVIRONMENT)
        with assert_raises():
            _ = Material(color, kind=kind, reflectivity=0.5)
        with assert_raises():
            _ = Material(color, kind=kind, combine=MIX_OPERATION)
        # The defaults, which nothing reads, are fine.
        _ = Material(color, kind=kind)


def test_a_reflectivity_is_a_fraction() raises:
    _ = Material(Color(1, 2, 3), reflectivity=0.0)
    _ = Material(Color(1, 2, 3), reflectivity=1.0)
    with assert_raises():
        _ = Material(Color(1, 2, 3), reflectivity=-0.1)
    with assert_raises():
        _ = Material(Color(1, 2, 3), reflectivity=1.1)
    with assert_raises():
        _ = Material(Color(1, 2, 3), reflectivity=nan[DType.float32]())
    with assert_raises():
        _ = Material(Color(1, 2, 3), reflectivity=inf[DType.float32]())


def test_a_combine_and_an_env_map_id_are_checked() raises:
    for combine in [MULTIPLY_OPERATION, MIX_OPERATION, ADD_OPERATION]:
        assert_true(combine.is_valid())
        _ = Material(Color(1, 2, 3), combine=combine)
    assert_false(Combine(3).is_valid())
    with assert_raises():
        _ = Material(Color(1, 2, 3), combine=Combine(3))
    with assert_raises():
        _ = Material(Color(1, 2, 3), env_map=CubeTextureId(-3))


def test_a_wireframe_cannot_reflect() raises:
    # A line has no surface to reflect from.
    with assert_raises():
        _ = Material(
            Color(1, 2, 3),
            kind=BASIC,
            wireframe=True,
            env_map=CubeTextureId(0),
        )
    _ = Material(Color(1, 2, 3), kind=BASIC, wireframe=True)


def test_each_combine_joins_the_reflection_its_own_way() raises:
    # three.js's `envmap_fragment`, term for term.
    var own = FloatColor(0.5, 0.2, 1.0, 0.3)
    var seen = FloatColor(0.4, 1.0, 0.5, 1.0)
    var multiplied = combine_light(own, seen, 1.0, MULTIPLY_OPERATION)
    assert_almost_equal(Float64(multiplied.r), 0.2, atol=1e-6)
    assert_almost_equal(Float64(multiplied.g), 0.2, atol=1e-6)
    assert_almost_equal(Float64(multiplied.b), 0.5, atol=1e-6)
    var mixed = combine_light(own, seen, 0.5, MIX_OPERATION)
    assert_almost_equal(Float64(mixed.r), 0.45, atol=1e-6)
    assert_almost_equal(Float64(mixed.g), 0.6, atol=1e-6)
    assert_almost_equal(Float64(mixed.b), 0.75, atol=1e-6)
    var added = combine_light(own, seen, 0.5, ADD_OPERATION)
    assert_almost_equal(Float64(added.r), 0.7, atol=1e-6)
    assert_almost_equal(Float64(added.g), 0.7, atol=1e-6)
    assert_almost_equal(Float64(added.b), 1.25, atol=1e-6)
    # Alpha is coverage and is left alone by all three.
    for joined in [multiplied, mixed, added]:
        assert_equal(joined.a, Float32(0.3))
    # A reflectivity of zero leaves the light alone under the two mixes,
    # and half a multiply is halfway to the product.
    var untouched = combine_light(own, seen, 0.0, MULTIPLY_OPERATION)
    assert_almost_equal(Float64(untouched.g), 0.2, atol=1e-6)
    var half = combine_light(own, seen, 0.5, MULTIPLY_OPERATION)
    assert_almost_equal(Float64(half.r), 0.35, atol=1e-6)
    # An operation neither backend can reach multiplies, as the kernel
    # would; both refuse it before a fragment is shaded.
    var odd = combine_light(own, seen, 1.0, Combine(9))
    assert_almost_equal(Float64(odd.r), 0.2, atol=1e-6)


# --- standard and physical --------------------------------------------------


def test_a_standard_material_carries_three_js_defaults() raises:
    # three.js's MeshStandardMaterial: a roughness of one and a metalness
    # of zero, a chalky dielectric that reflects four percent head on.
    var chalk = standard_material(Color(200, 40, 40))
    assert_equal(chalk.kind, STANDARD)
    assert_equal(chalk.roughness, Float32(1))
    assert_equal(chalk.metalness, Float32(0))
    assert_equal(chalk.env_map_intensity, Float32(1))
    assert_equal(chalk.roughness_map, NO_TEXTURE)
    assert_equal(chalk.metalness_map, NO_TEXTURE)
    assert_true(chalk.is_physical())
    assert_true(chalk.is_lit())
    assert_true(chalk.kind.reflects())
    assert_true(chalk.kind.has_normal())
    assert_false(chalk.has_highlight())
    assert_false(chalk.has_clearcoat())
    var head_on = chalk.base_reflectance()
    assert_almost_equal(head_on.r, Float32(0.04), atol=1e-6)
    assert_almost_equal(head_on.g, Float32(0.04), atol=1e-6)
    assert_almost_equal(head_on.b, Float32(0.04), atol=1e-6)
    assert_equal(head_on.a, Float32(1))
    # And every other property comes through as it does on any material.
    var brushed = standard_material(
        Color(1, 2, 3),
        TextureId(4),
        0.25,
        1.0,
        DOUBLE_SIDE,
        0.5,
        transparent=True,
        env_map=CubeTextureId(2),
        env_map_intensity=1.5,
        roughness_map=TextureId(5),
        metalness_map=TextureId(6),
        emissive=Color(10, 20, 30),
        emissive_intensity=2.0,
        emissive_map=TextureId(7),
    )
    assert_equal(brushed.map, TextureId(4))
    assert_equal(brushed.roughness, Float32(0.25))
    assert_equal(brushed.metalness, Float32(1))
    assert_equal(brushed.side, DOUBLE_SIDE)
    assert_true(brushed.is_transparent())
    assert_equal(brushed.env_map, CubeTextureId(2))
    assert_equal(brushed.env_map_intensity, Float32(1.5))
    assert_equal(brushed.roughness_map, TextureId(5))
    assert_equal(brushed.metalness_map, TextureId(6))
    assert_true(brushed.is_emissive())
    assert_equal(brushed.emissive_map, TextureId(7))
    # A standard material by hand is the same surface.
    var plain = Material(Color(200, 40, 40), kind=STANDARD)
    assert_equal(plain.roughness, chalk.roughness)
    assert_equal(plain.base_reflectance().r, head_on.r)


def test_a_physical_material_reflects_by_its_index() raises:
    # three.js's MeshPhysicalMaterial: an ior of one and a half, which is
    # the same four percent a standard surface reflects, so the default
    # physical surface is the default standard one.
    var glass = physical_material(Color(200, 200, 200))
    assert_equal(glass.kind, PHYSICAL)
    assert_equal(glass.ior, Float32(1.5))
    assert_equal(glass.specular_intensity, Float32(1))
    assert_equal(glass.clearcoat, Float32(0))
    assert_equal(glass.clearcoat_roughness, Float32(0))
    assert_true(glass.is_physical())
    assert_false(glass.has_clearcoat())
    assert_almost_equal(glass.base_reflectance().r, Float32(0.04), atol=1e-6)
    # ((ior - 1) / (ior + 1))^2: the widest index reflects sixteen percent.
    var dense = physical_material(Color(200, 200, 200), ior=2.333)
    assert_almost_equal(dense.base_reflectance().r, Float32(0.16), atol=1e-3)
    # An index of one reflects nothing at all, and two reflects a ninth.
    var air = physical_material(Color(200, 200, 200), ior=1.0)
    assert_equal(air.base_reflectance().r, Float32(0))
    var dense_two = physical_material(Color(200, 200, 200), ior=2.0)
    assert_almost_equal(
        dense_two.base_reflectance().b, Float32(1) / 9, atol=1e-6
    )
    # The specular color is authored in sRGB and decoded before it tints:
    # the reflectance is four percent of the *linear* color.
    var brown = physical_material(
        Color(200, 200, 200), specular_color=Color(128, 64, 32)
    )
    var tinted_f0 = brown.base_reflectance()
    var linear = FloatColor(srgb=Color(128, 64, 32))
    assert_almost_equal(tinted_f0.r, 0.04 * linear.r, atol=1e-6)
    assert_almost_equal(tinted_f0.g, 0.04 * linear.g, atol=1e-6)
    assert_almost_equal(tinted_f0.b, 0.04 * linear.b, atol=1e-6)
    assert_true(tinted_f0.r > 2 * tinted_f0.g, "the tint was read as linear")
    # A specular intensity of zero removes the reflectance whatever the
    # index.
    var none = physical_material(
        Color(200, 200, 200), ior=2.333, specular_intensity=0.0
    )
    assert_equal(none.base_reflectance().r, Float32(0))
    # The specular color tints it and the intensity scales it.
    var tinted = physical_material(
        Color(200, 200, 200),
        specular_color=Color(0, 0, 0),
        specular_intensity=0.5,
    )
    assert_equal(tinted.base_reflectance().r, Float32(0))
    var halved = physical_material(Color(200, 200, 200), specular_intensity=0.5)
    assert_almost_equal(halved.base_reflectance().g, Float32(0.02), atol=1e-6)
    # A clear coat comes through.
    var coated = physical_material(
        Color(200, 40, 40), clearcoat=1.0, clearcoat_roughness=0.3
    )
    assert_true(coated.has_clearcoat())
    assert_equal(coated.clearcoat, Float32(1))
    assert_equal(coated.clearcoat_roughness, Float32(0.3))
    # And the rest of the arguments reach the material.
    var full = physical_material(
        Color(1, 2, 3),
        TextureId(4),
        0.5,
        0.5,
        2.0,
        Color(255, 0, 0),
        0.75,
        0.5,
        0.25,
        BACK_SIDE,
        0.5,
        None,
        True,
        CubeTextureId(1),
        2.0,
        TextureId(5),
        TextureId(6),
        NO_TEXTURE,
        Vector2(1, 1),
        TextureId(7),
        0.5,
        Color(10, 10, 10),
        1.0,
        TextureId(8),
    )
    assert_equal(full.side, BACK_SIDE)
    assert_equal(full.ior, Float32(2))
    assert_equal(full.specular_color.r, UInt8(255))
    assert_equal(full.bump_map, TextureId(7))
    assert_equal(full.bump_scale, Float32(0.5))
    assert_equal(full.emissive_map, TextureId(8))
    # No other kind reflects anything head on.
    assert_equal(Material(Color(1, 1, 1)).base_reflectance().r, Float32(0))
    assert_equal(
        Material(Color(1, 1, 1), kind=BASIC).base_reflectance().b, Float32(0)
    )


def test_only_a_physical_kind_has_a_roughness_or_a_metalness() raises:
    # No other shader reads them, so a value in one is a mistake rather
    # than a choice. Each refuses on its own.
    for kind in [BASIC, LAMBERT, PHONG, TOON, MATCAP]:
        var color = Color(255, 255, 255)
        with assert_raises():
            _ = Material(color, kind=kind, roughness=0.5)
        with assert_raises():
            _ = Material(color, kind=kind, metalness=1.0)
        with assert_raises():
            _ = Material(color, kind=kind, roughness_map=TextureId(0))
        with assert_raises():
            _ = Material(color, kind=kind, metalness_map=TextureId(0))
        with assert_raises():
            _ = Material(color, kind=kind, env_map_intensity=2.0)
        # The defaults are fine on every kind.
        _ = Material(color, kind=kind, roughness=1.0, metalness=0.0)
    # And a physical surface reflects by them, so it reads no reflectivity
    # and no combine.
    for kind in [STANDARD, PHYSICAL]:
        with assert_raises():
            _ = Material(Color(255, 255, 255), kind=kind, reflectivity=0.5)
        with assert_raises():
            _ = Material(Color(255, 255, 255), kind=kind, combine=MIX_OPERATION)
        _ = Material(Color(255, 255, 255), kind=kind, env_map=SCENE_ENVIRONMENT)


def test_only_a_physical_material_has_an_index_or_a_coat() raises:
    for kind in [BASIC, LAMBERT, PHONG, TOON, MATCAP, STANDARD]:
        var color = Color(255, 255, 255)
        with assert_raises():
            _ = Material(color, kind=kind, ior=2.0)
        with assert_raises():
            _ = Material(color, kind=kind, specular_color=Color(255, 0, 0))
        with assert_raises():
            _ = Material(color, kind=kind, specular_intensity=0.5)
        with assert_raises():
            _ = Material(color, kind=kind, clearcoat=1.0)
        with assert_raises():
            _ = Material(color, kind=kind, clearcoat_roughness=0.5)
    _ = Material(
        Color(255, 255, 255),
        kind=PHYSICAL,
        ior=2.0,
        specular_color=Color(255, 0, 0),
        specular_intensity=0.5,
        clearcoat=1.0,
        clearcoat_roughness=0.5,
    )


def test_a_physical_number_outside_its_range_is_refused() raises:
    var color = Color(255, 255, 255)
    for wrong in [
        Float32(-0.1),
        Float32(1.5),
        nan[DType.float32](),
        inf[DType.float32](),
    ]:
        with assert_raises():
            _ = Material(color, kind=STANDARD, roughness=wrong)
        with assert_raises():
            _ = Material(color, kind=STANDARD, metalness=wrong)
        with assert_raises():
            _ = Material(color, kind=PHYSICAL, specular_intensity=wrong)
        with assert_raises():
            _ = Material(color, kind=PHYSICAL, clearcoat=wrong)
        with assert_raises():
            _ = Material(color, kind=PHYSICAL, clearcoat_roughness=wrong)
    for wrong in [Float32(0.9), Float32(3.0), nan[DType.float32]()]:
        with assert_raises():
            _ = Material(color, kind=PHYSICAL, ior=wrong)
    for wrong in [Float32(-1), nan[DType.float32](), inf[DType.float32]()]:
        with assert_raises():
            _ = Material(color, kind=STANDARD, env_map_intensity=wrong)
    with assert_raises():
        _ = Material(color, kind=STANDARD, roughness_map=TextureId(-2))
    with assert_raises():
        _ = Material(color, kind=STANDARD, metalness_map=TextureId(-2))
    # The ends of every range are allowed.
    _ = Material(color, kind=PHYSICAL, roughness=0, metalness=1, ior=1.0)
    _ = Material(
        color,
        kind=PHYSICAL,
        ior=2.333,
        specular_intensity=0,
        clearcoat=1,
        clearcoat_roughness=1,
        env_map_intensity=0,
    )


def test_a_normal_map_or_a_bump_map_needs_a_normal_to_perturb() raises:
    var color = Color(255, 255, 255)
    # Every lit kind reads one in the world's frame, and so does a matcap.
    for kind in [LAMBERT, PHONG, TOON, MATCAP, STANDARD, PHYSICAL]:
        var mapped = Material(
            color,
            kind=kind,
            normal_map=TextureId(0),
            normal_scale=Vector2(2, -1),
        )
        assert_true(mapped.has_normal_map())
        assert_false(mapped.has_bump_map())
        assert_equal(mapped.normal_scale.x, Float32(2))
        assert_equal(mapped.normal_scale.y, Float32(-1))
        var bumped = Material(
            color, kind=kind, bump_map=TextureId(0), bump_scale=0.5
        )
        assert_true(bumped.has_bump_map())
        assert_false(bumped.has_normal_map())
        assert_equal(bumped.bump_scale, Float32(0.5))
        # Not both: three.js reads the normal map and ignores the bump map.
        with assert_raises():
            _ = Material(
                color, kind=kind, normal_map=TextureId(0), bump_map=TextureId(1)
            )
    # A basic surface reads no normal, a depth surface none either, and a
    # normal material reads one in the camera's frame.
    with assert_raises():
        _ = Material(color, kind=BASIC, normal_map=TextureId(0))
    with assert_raises():
        _ = Material(color, kind=BASIC, bump_map=TextureId(0))
    with assert_raises():
        _ = Material(color, kind=DEPTH, normal_map=TextureId(0))
    with assert_raises():
        _ = Material(color, kind=NORMALS, bump_map=TextureId(0))
    assert_false(BASIC.has_normal())
    assert_false(DEPTH.has_normal())
    assert_false(NORMALS.has_normal())
    assert_true(MATCAP.has_normal())
    # A wireframe is drawn by the line pass, which has no surface.
    with assert_raises():
        _ = Material(color, kind=BASIC, wireframe=True, normal_map=TextureId(0))
    # A scale needs a map to scale, and must be a number.
    with assert_raises():
        _ = Material(color, normal_scale=Vector2(2, 2))
    with assert_raises():
        _ = Material(color, bump_scale=2.0)
    with assert_raises():
        _ = Material(
            color,
            normal_map=TextureId(0),
            normal_scale=Vector2(nan[DType.float32](), 1),
        )
    with assert_raises():
        _ = Material(
            color,
            normal_map=TextureId(0),
            normal_scale=Vector2(1, inf[DType.float32]()),
        )
    with assert_raises():
        _ = Material(
            color, bump_map=TextureId(0), bump_scale=nan[DType.float32]()
        )
    # And an id nothing can hold is refused, as every map's is.
    with assert_raises():
        _ = Material(color, normal_map=TextureId(-2))
    with assert_raises():
        _ = Material(color, bump_map=TextureId(-2))
    # A plain material names neither.
    var plain = Material(color)
    assert_false(plain.has_normal_map())
    assert_false(plain.has_bump_map())
    assert_equal(plain.normal_scale.x, Float32(1))
    assert_equal(plain.bump_scale, Float32(1))


# --- shadow -----------------------------------------------------------------


def test_a_shadow_material_is_black_and_blends_by_default() raises:
    # three.js's ShadowMaterial: black, opaque where a shadow falls, and
    # transparent, so it blends, wherever none does.
    var catcher = shadow_material()
    assert_equal(catcher.kind, SHADOW)
    assert_equal(catcher.color.r, UInt8(0))
    assert_equal(catcher.opacity, Float32(1))
    assert_true(catcher.is_transparent())
    assert_true(catcher.kind.is_unlit())
    assert_false(catcher.is_lit())
    assert_false(catcher.kind.is_physical())
    assert_false(catcher.kind.has_normal())
    assert_false(catcher.kind.reflects())
    assert_true(SHADOW.is_valid())
    var faint = shadow_material(Color(40, 0, 80), 0.5, DOUBLE_SIDE)
    assert_equal(faint.color.b, UInt8(80))
    assert_equal(faint.opacity, Float32(0.5))
    assert_equal(faint.side, DOUBLE_SIDE)
    # By hand it blends too, and refuses to be made opaque.
    var plain = Material(Color(0, 0, 0), kind=SHADOW)
    assert_equal(plain.blending, BLEND)
    with assert_raises():
        _ = Material(Color(0, 0, 0), kind=SHADOW, blending=OPAQUE)
    _ = Material(Color(0, 0, 0), kind=SHADOW, blending=BLEND, transparent=True)


def test_a_shadow_material_shows_its_shadow_and_nothing_else() raises:
    with assert_raises():
        _ = Material(Color(0, 0, 0), kind=SHADOW, map=TextureId(0))
    with assert_raises():
        _ = Material(Color(0, 0, 0), kind=SHADOW, alpha_map=TextureId(0))
    with assert_raises():
        _ = Material(Color(0, 0, 0), kind=SHADOW, vertex_colors=True)
    with assert_raises():
        _ = Material(Color(0, 0, 0), kind=SHADOW, wireframe=True)
    # Unlit, so no emissive term either, and no highlight or environment.
    with assert_raises():
        _ = Material(Color(0, 0, 0), kind=SHADOW, emissive=Color(1, 1, 1))
    with assert_raises():
        _ = Material(Color(0, 0, 0), kind=SHADOW, env_map=CubeTextureId(0))
    with assert_raises():
        _ = Material(Color(0, 0, 0), kind=SHADOW, normal_map=TextureId(0))
    with assert_raises():
        _ = shadow_material(opacity=1.5)


def test_an_ao_map_and_a_light_map_need_an_indirect_term() raises:
    var color = Color(255, 255, 255)
    # A basic surface and every lit kind have an indirect diffuse term.
    for kind in [BASIC, LAMBERT, PHONG, TOON, STANDARD, PHYSICAL]:
        assert_true(kind.has_indirect())
        var baked = Material(
            color,
            kind=kind,
            ao_map=TextureId(0),
            ao_map_intensity=0.5,
            light_map=TextureId(1),
            light_map_intensity=2.0,
        )
        assert_true(baked.has_ao_map())
        assert_true(baked.has_light_map())
        assert_true(baked.has_baked_map())
        assert_equal(baked.ao_map_intensity, Float32(0.5))
        assert_equal(baked.light_map_intensity, Float32(2.0))
    # Either map alone counts, and a plain surface names neither.
    assert_true(Material(color, ao_map=TextureId(0)).has_baked_map())
    assert_true(Material(color, light_map=TextureId(0)).has_baked_map())
    var plain = Material(color)
    assert_false(plain.has_ao_map())
    assert_false(plain.has_light_map())
    assert_false(plain.has_baked_map())
    assert_equal(plain.ao_map_intensity, Float32(1))
    assert_equal(plain.light_map_intensity, Float32(1))
    # No other kind has one, whichever map is named.
    for kind in [MATCAP, NORMALS, DEPTH, SHADOW]:
        assert_false(kind.has_indirect())
    with assert_raises(contains="indirect term"):
        _ = Material(color, kind=MATCAP, ao_map=TextureId(0))
    with assert_raises(contains="indirect term"):
        _ = Material(color, kind=SHADOW, light_map=TextureId(0))
    # A wireframe is drawn by the line pass, which samples no map.
    with assert_raises(contains="wireframe"):
        _ = Material(color, kind=BASIC, wireframe=True, ao_map=TextureId(0))
    # An intensity must be a number that is not negative, and needs a map.
    for wrong in [Float32(-1), nan[DType.float32](), inf[DType.float32]()]:
        with assert_raises(contains="ao map intensity"):
            _ = Material(color, ao_map=TextureId(0), ao_map_intensity=wrong)
        with assert_raises(contains="light map intensity"):
            _ = Material(
                color, light_map=TextureId(0), light_map_intensity=wrong
            )
    with assert_raises(contains="needs an ao map"):
        _ = Material(color, ao_map_intensity=0.5)
    with assert_raises(contains="needs a light map"):
        _ = Material(color, light_map_intensity=0.5)
    # An intensity of zero is allowed: it switches the map off.
    _ = Material(color, ao_map=TextureId(0), ao_map_intensity=0)
    # And an id nothing can hold is refused, as every map's is.
    with assert_raises(contains="ao map id"):
        _ = Material(color, ao_map=TextureId(-2))
    with assert_raises(contains="light map id"):
        _ = Material(color, light_map=TextureId(-2))


def test_the_physical_factories_pass_the_baked_maps_on() raises:
    var standard = standard_material(
        Color(200, 200, 200),
        ao_map=TextureId(3),
        ao_map_intensity=0.25,
        light_map=TextureId(4),
        light_map_intensity=3.0,
    )
    assert_equal(standard.ao_map, TextureId(3))
    assert_equal(standard.ao_map_intensity, Float32(0.25))
    assert_equal(standard.light_map, TextureId(4))
    assert_equal(standard.light_map_intensity, Float32(3.0))
    var physical = physical_material(
        Color(200, 200, 200), ao_map=TextureId(5), light_map=TextureId(6)
    )
    assert_equal(physical.ao_map, TextureId(5))
    assert_equal(physical.light_map, TextureId(6))


def test_a_specular_map_belongs_to_a_basic_lambert_or_phong_material() raises:
    var color = Color(255, 255, 255)
    assert_equal(Material(color).specular_map, NO_TEXTURE)
    # The three kinds three.js gives a `specularMap`.
    for kind in [BASIC, LAMBERT, PHONG]:
        var mapped = Material(color, kind=kind, specular_map=TextureId(3))
        assert_equal(mapped.specular_map, TextureId(3))
        assert_true(kind.has_specular_map())
    # Every other kind has no highlight or reflection for it to scale.
    for kind in [TOON, MATCAP, STANDARD, PHYSICAL, NORMALS, DEPTH]:
        assert_false(kind.has_specular_map())
        with assert_raises(contains="has a specular map"):
            _ = Material(color, kind=kind, specular_map=TextureId(0))
    with assert_raises(contains="has a specular map"):
        _ = Material(color, kind=SHADOW, specular_map=TextureId(0))
    # An id nothing can hold, and a wireframe, which has no surface.
    with assert_raises(contains="specular map id cannot be negative"):
        _ = Material(color, specular_map=TextureId(-2))
    with assert_raises(contains="no specular map"):
        _ = Material(
            color, kind=BASIC, wireframe=True, specular_map=TextureId(0)
        )


def test_flat_shading_needs_a_normal_to_replace() raises:
    var color = Color(255, 255, 255)
    assert_false(Material(color).flat_shading)
    # Every kind that reads a normal, in either frame.
    for kind in [LAMBERT, PHONG, TOON, MATCAP, STANDARD, PHYSICAL, NORMALS]:
        assert_true(Material(color, kind=kind, flat_shading=True).flat_shading)
    # A basic, depth or shadow surface reads none, and a wireframe is basic.
    for kind in [BASIC, DEPTH]:
        with assert_raises(contains="flat shaded"):
            _ = Material(color, kind=kind, flat_shading=True)
    with assert_raises(contains="flat shaded"):
        _ = Material(color, kind=SHADOW, flat_shading=True)
    with assert_raises():
        _ = Material(color, kind=BASIC, wireframe=True, flat_shading=True)


# --- depth packing, distance and fog ---------------------------------------


def test_a_depth_material_packs_by_three_js_default() raises:
    var shown = depth_material()
    assert_equal(shown.depth_packing, BASIC_DEPTH_PACKING)
    var packed = depth_material(depth_packing=RGBA_DEPTH_PACKING)
    assert_equal(packed.depth_packing, RGBA_DEPTH_PACKING)
    packed.check_data()
    # A value the type holds and no packing names.
    with assert_raises(contains="depth packing"):
        _ = depth_material(depth_packing=DepthPacking(7))
    # Packed on a kind that shows no depth.
    with assert_raises(contains="Only a depth material"):
        _ = Material(Color(1, 2, 3), depth_packing=RGB_DEPTH_PACKING)
    # A packed depth reads no opacity.
    with assert_raises(contains="no opacity"):
        _ = depth_material(opacity=0.5, depth_packing=RGB_DEPTH_PACKING)
    # The basic packing keeps it, as three.js's does.
    assert_equal(depth_material(opacity=0.5).opacity, Float32(0.5))
    # The field is open, and the check reads it where the renderer does.
    var changed = depth_material()
    changed.depth_packing = DepthPacking(-1)
    with assert_raises(contains="depth packing"):
        changed.check_data()


def test_a_distance_material_is_three_js_mesh_distance_material() raises:
    var measured = distance_material()
    assert_equal(measured.kind, DISTANCE)
    assert_true(measured.is_data())
    assert_true(DISTANCE.is_data())
    assert_true(DISTANCE.is_valid())
    assert_false(DISTANCE.is_lit())
    assert_false(DISTANCE.reflects())
    assert_false(DISTANCE.has_normal())
    assert_false(measured.fog)
    assert_equal(measured.near_distance.to(METER), Float32(1))
    assert_equal(measured.far_distance.to(METER), Float32(1000))
    assert_equal(measured.reference_position.x, Float32(0))
    var placed = distance_material(
        Vector3(1, 2, 3), Length(0.5, METER), Length(20.0, METER)
    )
    assert_equal(placed.reference_position.z, Float32(3))
    assert_equal(placed.far_distance.to(METER), Float32(20))
    # A distance material shows data, not light, so it takes no color.
    with assert_raises(contains="no color"):
        _ = Material(Color(1, 2, 3), kind=DISTANCE)


def test_a_distance_range_is_refused_where_it_cannot_measure() raises:
    with assert_raises(contains="far distance"):
        _ = distance_material(
            near_distance=Length(5.0, METER), far_distance=Length(5.0, METER)
        )
    with assert_raises(contains="near distance"):
        _ = distance_material(near_distance=Length(-1.0, METER))
    with assert_raises(contains="reference"):
        _ = distance_material(Vector3(nan[DType.float32](), 0, 0))
    # A distance material reads no opacity.
    with assert_raises(contains="no opacity"):
        _ = Material(Color(255, 255, 255), kind=DISTANCE, opacity=0.5)
    # And no other kind reads a range, whichever of the three is set.
    with assert_raises(contains="Only a distance material"):
        _ = Material(Color(1, 2, 3), reference_position=Vector3(0, 1, 0))
    with assert_raises(contains="Only a distance material"):
        _ = Material(Color(1, 2, 3), near_distance=Length(2.0, METER))
    with assert_raises(contains="Only a distance material"):
        _ = Material(Color(1, 2, 3), far_distance=Length(2.0, METER))
    with assert_raises(contains="Only a distance material"):
        _ = Material(Color(1, 2, 3), reference_position=Vector3(1, 0, 0))
    with assert_raises(contains="Only a distance material"):
        _ = Material(Color(1, 2, 3), reference_position=Vector3(0, 0, 1))


def test_a_material_is_fogged_unless_it_says_otherwise() raises:
    assert_true(Material(Color(1, 2, 3)).fog)
    assert_true(Material(Color(1, 2, 3), kind=BASIC).fog)
    assert_false(Material(Color(1, 2, 3), fog=False).fog)
    assert_true(Material(Color(1, 2, 3), fog=True).fog)
    # The data kinds are never fogged, as three.js's shaders for them read
    # no fog, and refuse it.
    assert_false(normal_material().fog)
    assert_false(depth_material().fog)
    assert_false(Material(Color(255, 255, 255), kind=NORMALS, fog=False).fog)
    with assert_raises(contains="never fogged"):
        _ = Material(Color(255, 255, 255), kind=DEPTH, fog=True)
    var turned = normal_material()
    turned.fog = True
    with assert_raises(contains="never fogged"):
        turned.check_data()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()


# --- transmission -----------------------------------------------------------


def test_a_physical_material_transmits_at_three_js_s_defaults() raises:
    var glass = physical_material(Color(255, 255, 255))
    assert_equal(glass.transmission, Float32(0))
    assert_false(glass.transmits())
    assert_equal(glass.transmission_map, NO_TEXTURE)
    assert_equal(glass.thickness.to(METER), Float32(0))
    assert_equal(glass.thickness_map, NO_TEXTURE)
    assert_equal(glass.attenuation_color.g, UInt8(255))
    assert_equal(glass.attenuation_distance.to(METER), inf[DType.float32]())
    assert_equal(glass.dispersion, Float32(0))
    var clear = physical_material(
        Color(255, 255, 255),
        roughness=0.1,
        ior=1.45,
        transmission=1.0,
        transmission_map=TextureId(2),
        thickness=Length(0.5, METER),
        thickness_map=TextureId(3),
        attenuation_color=Color(200, 255, 220),
        attenuation_distance=Length(2.0, METER),
        dispersion=3.0,
    )
    assert_true(clear.transmits())
    assert_equal(clear.transmission_map, TextureId(2))
    assert_equal(clear.thickness.to(METER), Float32(0.5))
    assert_equal(clear.thickness_map, TextureId(3))
    assert_equal(clear.attenuation_color.r, UInt8(200))
    assert_equal(clear.attenuation_distance.to(METER), Float32(2))
    assert_equal(clear.dispersion, Float32(3))


def test_a_material_refuses_a_volume_it_cannot_hold() raises:
    var white = Color(255, 255, 255)
    for wrong in [nan[DType.float32](), Float32(-0.1), Float32(1.1)]:
        with assert_raises(contains="transmission must be between"):
            _ = Material(white, kind=PHYSICAL, transmission=wrong)
    for wrong in [nan[DType.float32](), Float32(-1)]:
        with assert_raises(contains="thickness cannot be negative"):
            _ = Material(white, kind=PHYSICAL, thickness=Length(wrong, METER))
    for wrong in [nan[DType.float32](), Float32(0), Float32(-2)]:
        with assert_raises(contains="attenuation distance must be above"):
            _ = Material(
                white,
                kind=PHYSICAL,
                attenuation_distance=Length(wrong, METER),
            )
    for wrong in [nan[DType.float32](), Float32(-1)]:
        with assert_raises(contains="dispersion cannot be negative"):
            _ = Material(white, kind=PHYSICAL, dispersion=wrong)
    with assert_raises(contains="transmission map id cannot be negative"):
        _ = Material(white, kind=PHYSICAL, transmission_map=TextureId(-5))
    with assert_raises(contains="thickness map id cannot be negative"):
        _ = Material(white, kind=PHYSICAL, thickness_map=TextureId(-5))


def test_only_a_physical_material_transmits() raises:
    var white = Color(255, 255, 255)
    var materials = List[Material]()
    for kind in [BASIC, LAMBERT, PHONG, STANDARD, TOON]:
        with assert_raises(contains="Only a physical material transmits"):
            _ = Material(white, kind=kind, transmission=0.5)
        with assert_raises(contains="Only a physical material transmits"):
            _ = Material(white, kind=kind, transmission_map=TextureId(0))
        with assert_raises(contains="Only a physical material transmits"):
            _ = Material(white, kind=kind, thickness=Length(1.0, METER))
        with assert_raises(contains="Only a physical material transmits"):
            _ = Material(white, kind=kind, thickness_map=TextureId(0))
        with assert_raises(contains="Only a physical material transmits"):
            _ = Material(white, kind=kind, attenuation_color=Color(1, 2, 3))
        with assert_raises(contains="Only a physical material transmits"):
            _ = Material(
                white, kind=kind, attenuation_distance=Length(1.0, METER)
            )
        with assert_raises(contains="Only a physical material transmits"):
            _ = Material(white, kind=kind, dispersion=1)
        materials.append(Material(white, kind=kind))
    assert_equal(len(materials), 5)


# --- sheen, iridescence and anisotropy ---------------------------------------


def test_a_physical_material_starts_with_no_sheen_film_or_stretch() raises:
    var plain = physical_material(Color(255, 255, 255))
    assert_equal(plain.sheen, Float32(0))
    assert_equal(plain.sheen_color.r, UInt8(0))
    assert_equal(plain.sheen_roughness, Float32(1))
    assert_equal(plain.iridescence, Float32(0))
    assert_equal(plain.iridescence_ior, DEFAULT_IRIDESCENCE_IOR)
    assert_true(
        plain.iridescence_thickness_minimum == DEFAULT_THICKNESS_MINIMUM
    )
    assert_true(
        plain.iridescence_thickness_maximum == DEFAULT_THICKNESS_MAXIMUM
    )
    assert_almost_equal(
        plain.iridescence_thickness_maximum.to(NANOMETER),
        Float32(400),
        atol=1e-3,
    )
    assert_equal(plain.anisotropy, Float32(0))
    assert_true(plain.anisotropy_rotation == NO_ROTATION)
    assert_equal(plain.sheen_color_map, NO_TEXTURE)
    assert_equal(plain.anisotropy_map, NO_TEXTURE)


def test_a_physical_material_carries_its_three_layers() raises:
    var velvet = physical_material(
        Color(255, 255, 255),
        sheen=1,
        sheen_color=Color(200, 0, 100),
        sheen_color_map=TextureId(1),
        sheen_roughness=0.3,
        sheen_roughness_map=TextureId(2),
        iridescence=0.5,
        iridescence_ior=1.8,
        iridescence_thickness_minimum=Length(50.0, NANOMETER),
        iridescence_thickness_maximum=Length(800.0, NANOMETER),
        iridescence_map=TextureId(3),
        iridescence_thickness_map=TextureId(4),
        anisotropy=0.75,
        anisotropy_rotation=Angle(90.0, DEGREE),
        anisotropy_map=TextureId(5),
    )
    assert_equal(velvet.sheen, Float32(1))
    assert_equal(velvet.sheen_color.b, UInt8(100))
    assert_equal(velvet.sheen_color_map, TextureId(1))
    assert_equal(velvet.sheen_roughness, Float32(0.3))
    assert_equal(velvet.sheen_roughness_map, TextureId(2))
    assert_equal(velvet.iridescence, Float32(0.5))
    assert_equal(velvet.iridescence_ior, Float32(1.8))
    assert_almost_equal(
        velvet.iridescence_thickness_minimum.to(NANOMETER),
        Float32(50),
        atol=1e-3,
    )
    assert_equal(velvet.iridescence_map, TextureId(3))
    assert_equal(velvet.iridescence_thickness_map, TextureId(4))
    assert_equal(velvet.anisotropy, Float32(0.75))
    assert_almost_equal(
        velvet.anisotropy_rotation.to(DEGREE), Float32(90), atol=1e-4
    )
    assert_equal(velvet.anisotropy_map, TextureId(5))


def test_a_layer_number_out_of_range_is_refused() raises:
    var white = Color(255, 255, 255)
    for bad in [Float32(-0.1), Float32(1.1), nan[DType.float32]()]:
        with assert_raises(contains="A sheen must"):
            _ = physical_material(white, sheen=bad)
        with assert_raises(contains="A sheen roughness"):
            _ = physical_material(white, sheen_roughness=bad)
        with assert_raises(contains="An iridescence must"):
            _ = physical_material(white, iridescence=bad)
        with assert_raises(contains="An anisotropy must"):
            _ = physical_material(white, anisotropy=bad)
    for bad in [Float32(0.9), Float32(2.5), nan[DType.float32]()]:
        with assert_raises(contains="index of refraction"):
            _ = physical_material(white, iridescence_ior=bad)
    with assert_raises(contains="thickness cannot be negative"):
        _ = physical_material(
            white, iridescence_thickness_minimum=Length(-1.0, NANOMETER)
        )
    with assert_raises(contains="thickness cannot be negative"):
        _ = physical_material(
            white, iridescence_thickness_maximum=Length(-1.0, NANOMETER)
        )
    with assert_raises(contains="thickness cannot be negative"):
        _ = physical_material(
            white,
            iridescence_thickness_maximum=Length(inf[DType.float32](), METER),
        )
    with assert_raises(contains="rotation must be finite"):
        _ = physical_material(
            white, anisotropy_rotation=Angle(inf[DType.float32](), RADIAN)
        )
    # A film thicker at a texel of zero than at one is three.js's too.
    _ = physical_material(
        white,
        iridescence=1,
        iridescence_thickness_minimum=Length(500.0, NANOMETER),
    )


def test_a_negative_layer_map_id_is_refused() raises:
    var white = Color(255, 255, 255)
    var bad = TextureId(-2)
    with assert_raises(contains="layer map id"):
        _ = physical_material(white, sheen=1, sheen_color_map=bad)
    with assert_raises(contains="layer map id"):
        _ = physical_material(white, sheen=1, sheen_roughness_map=bad)
    with assert_raises(contains="layer map id"):
        _ = physical_material(white, iridescence=1, iridescence_map=bad)
    with assert_raises(contains="layer map id"):
        _ = physical_material(
            white, iridescence=1, iridescence_thickness_map=bad
        )
    with assert_raises(contains="layer map id"):
        _ = physical_material(white, anisotropy=1, anisotropy_map=bad)


def test_a_layer_map_with_nothing_to_multiply_is_refused() raises:
    var white = Color(255, 255, 255)
    var map = TextureId(0)
    with assert_raises(contains="needs a sheen"):
        _ = physical_material(white, sheen_color_map=map)
    with assert_raises(contains="needs a sheen"):
        _ = physical_material(white, sheen_roughness_map=map)
    with assert_raises(contains="needs an iridescence"):
        _ = physical_material(white, iridescence_map=map)
    with assert_raises(contains="needs an iridescence"):
        _ = physical_material(white, iridescence_thickness_map=map)
    with assert_raises(contains="needs an anisotropy"):
        _ = physical_material(white, anisotropy_map=map)


def test_only_a_physical_material_has_a_sheen_a_film_or_a_stretch() raises:
    var white = Color(255, 255, 255)
    for kind in [BASIC, LAMBERT, PHONG, TOON, MATCAP, STANDARD]:
        with assert_raises(contains="Only a physical material has a sheen"):
            _ = Material(white, kind=kind, sheen=0.5)
        with assert_raises(contains="Only a physical material has a sheen"):
            _ = Material(white, kind=kind, sheen_color=Color(0, 0, 9))
        with assert_raises(contains="Only a physical material has a sheen"):
            _ = Material(white, kind=kind, sheen_roughness=0.5)
        with assert_raises(contains="Only a physical material has a sheen"):
            _ = Material(white, kind=kind, iridescence=0.5)
        with assert_raises(contains="Only a physical material has a sheen"):
            _ = Material(white, kind=kind, iridescence_ior=2.0)
        with assert_raises(contains="Only a physical material has a sheen"):
            _ = Material(
                white,
                kind=kind,
                iridescence_thickness_minimum=Length(0.0, NANOMETER),
            )
        with assert_raises(contains="Only a physical material has a sheen"):
            _ = Material(
                white,
                kind=kind,
                iridescence_thickness_maximum=Length(9.0, NANOMETER),
            )
        with assert_raises(contains="Only a physical material has a sheen"):
            _ = Material(white, kind=kind, anisotropy=0.5)
        with assert_raises(contains="Only a physical material has a sheen"):
            _ = Material(
                white, kind=kind, anisotropy_rotation=Angle(1.0, RADIAN)
            )
    # An alpha on a black sheen color is still black.
    _ = Material(white, kind=LAMBERT, sheen_color=Color(0, 0, 0, 128))
