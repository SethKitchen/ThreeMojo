# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.mtl`.

Every key three.js's `MTLLoader` reads is given and its material checked,
and every way a library can be wrong is given to the parser and refused.
The images are the project's own fixtures under `assets/`.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from lights.light import ambient_light
from loaders.mtl import (
    MtlLibrary,
    parse_mtl,
    read_mtl,
    read_obj_with_materials,
    set_materials,
)
from loaders.obj import parse_obj
from materials.material import Material, MaterialId, PHONG
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from render.srgb import LINEAR, SRGB
from render.texture import CLAMP, COVERAGE, IGNORED, REPEAT
from render.texture_store import NO_TEXTURE
from renderers.renderer import Renderer
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime TOLERANCE = Float64(1e-6)


def one(text: String, mut assets: Assets) raises -> Material:
    """Return the first material a library's text builds, its textures
    read from `assets/`."""
    var library = parse_mtl(text, "assets/", assets)
    return assets.materials.get(library.materials[0])


def assert_color(got: Color, r: UInt8, g: UInt8, b: UInt8) raises:
    """Assert a color's three channels."""
    assert_equal(got.r, r)
    assert_equal(got.g, g)
    assert_equal(got.b, b)


def refuses(text: String, words: String) raises:
    """Assert a library's text is refused with an error that says `words`."""
    var assets = Assets()
    with assert_raises(contains=words):
        _ = parse_mtl(text, "assets/", assets)


# --- materials -------------------------------------------------------------


def test_a_material_with_no_keys_is_threes_phong_default() raises:
    var assets = Assets()
    var built = one("newmtl plain\n", assets)
    assert_true(built.kind == PHONG)
    assert_color(built.color, 255, 255, 255)
    assert_color(built.specular, 17, 17, 17)
    assert_color(built.emissive, 0, 0, 0)
    assert_almost_equal(built.shininess, Float32(30), atol=TOLERANCE)
    assert_almost_equal(built.opacity, Float32(1), atol=TOLERANCE)
    assert_false(built.transparent)
    assert_true(built.map == NO_TEXTURE)
    assert_true(built.emissive_map == NO_TEXTURE)
    assert_true(built.alpha_map == NO_TEXTURE)
    assert_true(built.normal_map == NO_TEXTURE)
    assert_true(built.bump_map == NO_TEXTURE)
    assert_almost_equal(built.bump_scale, Float32(1), atol=TOLERANCE)
    assert_equal(assets.textures.count(), 0)


def test_colors_shininess_and_keywords_in_any_case() raises:
    var assets = Assets()
    var built = one(
        (
            "newmtl paint\nKD 1 0.5 0\nks 0.2 0.2 0.2\nKe 0 0 1\nNs 96.5\n"
            "Ka 1 1 1\nillum 2\n"
        ),
        assets,
    )
    assert_color(built.color, 255, 128, 0)
    assert_color(built.specular, 51, 51, 51)
    assert_color(built.emissive, 0, 0, 255)
    assert_almost_equal(built.shininess, Float32(96.5), atol=TOLERANCE)
    assert_false(built.transparent)


def test_d_below_one_and_tr_above_zero_make_a_surface_transparent() raises:
    var assets = Assets()
    var faded = one("newmtl a\nd 0.25\n", assets)
    assert_almost_equal(faded.opacity, Float32(0.25), atol=TOLERANCE)
    assert_true(faded.transparent)
    var clear = one("newmtl a\nTr 0.25\n", assets)
    assert_almost_equal(clear.opacity, Float32(0.75), atol=TOLERANCE)
    assert_true(clear.transparent)
    # `d 1` and `Tr 0` say opaque and change nothing, as in three.js.
    var solid = one("newmtl a\nd 1\nTr 0\n", assets)
    assert_almost_equal(solid.opacity, Float32(1), atol=TOLERANCE)
    assert_false(solid.transparent)


def test_a_repeated_key_keeps_its_first_place_and_its_last_value() raises:
    # `d` first seen before `Tr`, so it is applied first and `Tr` wins,
    # even though the last line is a `d`.
    var assets = Assets()
    var built = one("newmtl a\nd 0.5\nTr 0.1\nd 0.3\n", assets)
    assert_almost_equal(built.opacity, Float32(0.9), atol=TOLERANCE)


def test_text_before_the_first_material_comments_and_empty_values() raises:
    var assets = Assets()
    var library = parse_mtl(
        (
            "# a library\nKd 1 0 0\n\nnewmtl a # trailing\nKd\nmap_Kd\n"
            "Kd 0 1 0 # green\nunknown 1 2 3\n"
        ),
        "assets/",
        assets,
    )
    assert_equal(library.count(), 1)
    assert_equal(library.names[0], String("a"))
    var built = assets.materials.get(library.materials[0])
    assert_color(built.color, 0, 255, 0)
    assert_true(built.map == NO_TEXTURE)


def test_a_second_material_of_one_name_replaces_the_first_in_place() raises:
    var assets = Assets()
    var library = parse_mtl(
        "newmtl a\nKd 1 0 0\nnewmtl b\nnewmtl a\nKd 0 1 0\n", "", assets
    )
    assert_equal(library.count(), 2)
    assert_equal(library.names[0], String("a"))
    assert_equal(library.names[1], String("b"))
    assert_color(assets.materials.get(library.get("a")).color, 0, 255, 0)
    assert_equal(assets.materials.count(), 2)


def test_an_empty_library_has_no_materials() raises:
    var assets = Assets()
    var library = parse_mtl("", "", assets)
    assert_equal(library.count(), 0)


# --- textures --------------------------------------------------------------


def test_each_map_is_read_in_the_space_its_use_asks() raises:
    var assets = Assets()
    var built = one(
        (
            "newmtl a\nmap_Kd brick.png\nmap_Ke jpeg/solid.jpg\n"
            "map_d tga/rgba_top.tga\nnorm gltf/checker.png\n"
        ),
        assets,
    )
    assert_true(built.transparent)
    ref color = assets.textures.get(built.map)
    assert_true(color.color_space == SRGB)
    assert_true(color.alpha == COVERAGE)
    assert_true(color.wrap == REPEAT)
    ref glow = assets.textures.get(built.emissive_map)
    assert_true(glow.color_space == SRGB)
    assert_true(glow.alpha == IGNORED)
    ref mask = assets.textures.get(built.alpha_map)
    assert_true(mask.color_space == LINEAR)
    assert_true(mask.alpha == IGNORED)
    ref normal = assets.textures.get(built.normal_map)
    assert_true(normal.color_space == LINEAR)
    var bumpy = one("newmtl b\nmap_bump -bm 0.5 brick.png\n", assets)
    ref bump = assets.textures.get(bumpy.bump_map)
    assert_true(bump.color_space == LINEAR)
    assert_true(bump.alpha == IGNORED)
    assert_almost_equal(bumpy.bump_scale, Float32(0.5), atol=TOLERANCE)
    # brick.png read as color and as data is two textures.
    assert_equal(assets.textures.count(), 5)


def test_a_normal_map_wins_over_a_bump_map() raises:
    # As three.js reads the normal map and ignores the bump map.
    var assets = Assets()
    var built = one("newmtl a\nbump brick.png\nnorm brick.png\n", assets)
    assert_true(built.normal_map != NO_TEXTURE)
    assert_true(built.bump_map == NO_TEXTURE)


def test_the_first_bump_map_is_kept() raises:
    # `bump` and `map_bump` both name the bump map. The second is not even
    # read: its file does not exist, and its bump scale is not applied, as
    # three.js returns before reading it.
    var assets = Assets()
    var built = one(
        "newmtl a\nbump brick.png\nmap_bump -bm 3 nothing.png\n", assets
    )
    assert_true(built.bump_map != NO_TEXTURE)
    assert_almost_equal(built.bump_scale, Float32(1), atol=TOLERANCE)


def test_an_image_read_the_same_way_twice_is_one_texture() raises:
    var assets = Assets()
    var library = parse_mtl(
        (
            "newmtl a\nmap_Kd brick.png\nnewmtl b\nmap_Kd brick.png\n"
            "newmtl c\nmap_Kd -s 2 2 1 brick.png\n"
        ),
        "assets/",
        assets,
    )
    var a = assets.materials.get(library.get("a"))
    var b = assets.materials.get(library.get("b"))
    var c = assets.materials.get(library.get("c"))
    assert_true(a.map == b.map)
    assert_true(a.map != c.map)
    assert_equal(assets.textures.count(), 2)


def test_scale_and_offset_set_repeat_and_offset() raises:
    var assets = Assets()
    var built = one(
        "newmtl a\nmap_Kd -s 2 3 1 -o 0.5 0.25 0 brick.png\n", assets
    )
    ref image = assets.textures.get(built.map)
    assert_almost_equal(image.repeat.x, Float32(2), atol=TOLERANCE)
    assert_almost_equal(image.repeat.y, Float32(3), atol=TOLERANCE)
    assert_almost_equal(image.offset.x, Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(image.offset.y, Float32(0.25), atol=TOLERANCE)
    # One number: `v` is one for a scale, zero for an offset.
    var short = one("newmtl a\nmap_Kd -s 2 -o 0.5 brick.png\n", assets)
    ref trimmed = assets.textures.get(short.map)
    assert_almost_equal(trimmed.repeat.y, Float32(1), atol=TOLERANCE)
    assert_almost_equal(trimmed.offset.y, Float32(0), atol=TOLERANCE)


def test_clamp_and_the_displacement_option() raises:
    var assets = Assets()
    var clamped = one("newmtl a\nmap_Kd -clamp on -mm 0 1 brick.png\n", assets)
    assert_true(assets.textures.get(clamped.map).wrap == CLAMP)
    var repeated = one("newmtl a\nmap_Kd -clamp off brick.png\n", assets)
    assert_true(assets.textures.get(repeated.map).wrap == REPEAT)


def test_a_file_name_can_hold_spaces() raises:
    refuses("newmtl a\nmap_Kd no such.png\n", "assets/no such.png")


def test_a_bad_texture_line_is_refused() raises:
    refuses("newmtl a\nmap_Kd -blendu on brick.png\n", "-blendu")
    refuses("newmtl a\nmap_Kd -s brick.png\n", "-s needs 1 numbers")
    refuses("newmtl a\nmap_Kd -o 1\n", "names no file")
    refuses("newmtl a\nmap_Kd -mm 1 brick.png\n", "-mm needs 2")
    refuses("newmtl a\nmap_Kd -bm inf brick.png\n", "finite")
    refuses("newmtl a\nmap_Kd -clamp maybe brick.png\n", "on or off")
    refuses("newmtl a\nmap_Kd brick.png -clamp\n", "on or off")
    refuses("newmtl a\nmap_Kd missing.png\n", "cannot read the texture")
    refuses("newmtl a\nmap_Kd cube.obj\n", "neither PNG nor JPEG")


# --- values that are refused -----------------------------------------------


def test_a_bad_value_is_refused_with_its_line() raises:
    refuses("newmtl\n", "MTL line 1: newmtl names no material")
    refuses("newmtl a\nKd 1 1\n", "MTL line 2: a color needs three")
    refuses("newmtl a\nKd 1 1 1 1\n", "three numbers")
    refuses("newmtl a\nKs 1.5 0 0\n", "from zero to one")
    refuses("newmtl a\nKe -0.1 0 0\n", "from zero to one")
    refuses("newmtl a\nKd red 0 0\n", "not a number: red")
    refuses("newmtl a\nNs -1\n", "Ns must not be negative")
    refuses("newmtl a\nNs 1e100\n", "finite")
    refuses("newmtl a\nd 1.5\n", "from zero to one")
    refuses("newmtl a\nTr -1\n", "from zero to one")
    refuses("newmtl a\nillum 2.5\n", "illum must be a whole number")
    refuses("newmtl a\nillum 11\n", "illum must be from 0 to 10")
    refuses("newmtl a\nillum -1\n", "illum must be from 0 to 10")


# --- the library -----------------------------------------------------------


def test_a_library_finds_adds_merges_and_creates() raises:
    var assets = Assets()
    var library = MtlLibrary()
    assert_equal(library.find("a"), -1)
    # A name it does not have gets a default material, built once.
    var made = library.create("a", assets)
    assert_equal(library.create("a", assets), made)
    assert_equal(assets.materials.count(), 1)
    assert_true(assets.materials.get(made).kind == PHONG)
    library.add("a", MaterialId(7))
    assert_equal(library.get("a"), MaterialId(7))
    var other = MtlLibrary()
    other.add("b", MaterialId(8))
    other.add("a", MaterialId(9))
    library.merge(other)
    assert_equal(library.count(), 2)
    assert_equal(library.get("a"), MaterialId(9))
    assert_equal(library.get("b"), MaterialId(8))
    with assert_raises(contains="no material is named c"):
        _ = library.get("c")


def test_set_materials_gives_each_object_one() raises:
    var assets = Assets()
    var library = parse_mtl("newmtl red\nKd 1 0 0\n", "", assets)
    var model = parse_obj(
        "v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\nusemtl red\nf 1 2 3\n"
        "usemtl blue\nf 1 2 3\n"
    )
    var ids = set_materials(model, library, assets)
    assert_equal(len(ids), 3)
    # No `usemtl`, and an unknown name, each get a default of their own.
    assert_true(ids[0] != ids[1])
    assert_equal(ids[1], library.get("red"))
    assert_true(ids[2] != ids[0])
    assert_equal(library.count(), 3)


def test_read_mtl_reads_textures_beside_the_library() raises:
    var assets = Assets()
    var library = read_mtl("assets/cube.mtl", assets)
    var brick = assets.materials.get(library.get("Brick"))
    assert_color(brick.color, 204, 128, 77)
    assert_almost_equal(brick.shininess, Float32(50), atol=TOLERANCE)
    assert_true(brick.map != NO_TEXTURE)
    with assert_raises():
        _ = read_mtl("assets/missing.mtl", assets)


def test_read_obj_with_materials_reads_every_library() raises:
    var assets = Assets()
    var read = read_obj_with_materials("assets/mtl/pair.obj", assets)
    assert_equal(read.model.count(), 3)
    assert_equal(len(read.materials), 3)
    # The second library's Shared replaces the first's.
    assert_color(assets.materials.get(read.materials[0]).color, 0, 0, 255)
    # A name neither library has is a default.
    assert_color(assets.materials.get(read.materials[1]).color, 255, 255, 255)
    # The first library's texture is read beside it, one directory up.
    assert_true(assets.materials.get(read.materials[2]).map != NO_TEXTURE)
    var bare = read_obj_with_materials("assets/mtl/bare.obj", assets)
    assert_equal(bare.library.count(), 1)
    var empty = read_obj_with_materials("assets/mtl/empty.obj", assets)
    assert_equal(len(empty.materials), 0)
    assert_equal(empty.library.count(), 0)


def test_a_textured_cube_from_its_library_renders() raises:
    var assets = Assets()
    var read = read_obj_with_materials("assets/cube.obj", assets)
    var shape = assets.geometries.add(read.model.objects[0].take_geometry())
    # The data maps as well, to show the renderer takes them as read.
    var extra = parse_mtl(
        (
            "newmtl all\nKd 0.8 0.5 0.3\nmap_Kd brick.png\nmap_Ke brick.png\n"
            "Ke 0.1 0.1 0.1\nmap_d brick.png\nbump brick.png\nd 0.9\n"
        ),
        "assets/",
        assets,
    )
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    scene.add_light(ambient_light(Color(255, 255, 255), 1.0))
    scene.add_mesh(Mesh(shape, read.materials[0], node))
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE),
        Float32(24) / Float32(18),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(1.5, 1.2, 3), Vector3(0, 0, 0))
    var renderer = Renderer(24, 18)
    var image = renderer.render(scene, assets, camera)
    var drawn = 0
    for y in range(18):
        for x in range(24):
            if image.get_pixel(x, y).r > 0:
                drawn += 1
    assert_true(drawn > 20, "the cube did not draw")
    var second = Scene()
    var holder = second.add(Object3D())
    second.update()
    second.add_light(ambient_light(Color(255, 255, 255), 1.0))
    second.add_mesh(Mesh(shape, extra.get("all"), holder))
    _ = renderer.render(second, assets, camera)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
