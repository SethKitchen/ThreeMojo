# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the sampler, mapping and environment keys of three.js's JSON
Object format: `wrap` per axis, `magFilter`, `minFilter`, `flipY` and
`mapping` on a texture; `envMapRotation`, `refractionRatio` and
`normalMapType` on a material; and the background and environment
settings of a scene, as `ObjectLoader` reads them and `toJSON` writes them.
"""

from core.assets import Assets
from core.background import (
    CUBE_BACKGROUND,
    TEXTURE_BACKGROUND,
    cube_background,
)
from core.object3d import Object3D
from core.scene import Scene
from exporters.gltf import encode_base64
from exporters.object_json import object_to_json
from geometries.box import box
from loaders.object_loader import (
    ObjectModel,
    filter_code,
    filter_of,
    read_object_json,
)
from materials.material import (
    BASIC,
    DEFAULT_REFRACTION_RATIO,
    LAMBERT,
    OBJECT_SPACE_NORMAL_MAP,
    PHONG,
    TANGENT_SPACE_NORMAL_MAP,
    Material,
    MaterialId,
)
from math.euler import XYZ, YXZ, ZYX, Euler
from objects.mesh import Mesh
from render.cube_texture import cube_of_panorama
from render.cube_texture_store import CubeTextureId
from render.framebuffer import Color, Framebuffer
from render.png import encode as encode_png
from render.srgb import LINEAR
from render.texture import (
    BILINEAR,
    CLAMP,
    CUBE_REFRACTION_MAPPING,
    EQUIRECTANGULAR_REFLECTION_MAPPING,
    EQUIRECTANGULAR_REFRACTION_MAPPING,
    IGNORED,
    LINEAR_MIPMAP_LINEAR,
    LINEAR_MIPMAP_NEAREST,
    MIRROR,
    NEAREST,
    NEAREST_MIPMAP_LINEAR,
    NEAREST_MIPMAP_NEAREST,
    REPEAT,
    UV_MAPPING,
    Filter,
    Texture,
    float_texture,
)
from render.texture_store import TextureId
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, Length, METER, RADIAN


def _wrap(document: String) -> String:
    """Return an Object document around an `object` and libraries."""
    return (
        '{"metadata":{"version":4.6,"type":"Object","generator":'
        '"Object3D.toJSON"},'
        + document
        + "}"
    )


def _read(document: String) raises -> Tuple[Scene, Assets, ObjectModel]:
    """Read a wrapped document into a fresh scene."""
    var scene = Scene()
    var assets = Assets()
    var model = read_object_json(_wrap(document), scene, assets)
    return (scene^, assets^, model^)


def _refuses(document: String, message: String) raises:
    """Assert that a wrapped document is refused with a message."""
    var scene = Scene()
    var assets = Assets()
    with assert_raises(contains=message):
        _ = read_object_json(_wrap(document), scene, assets)


def _png_url() raises -> String:
    """Return a 2x2 image of four colors as a PNG `data:` URL, its first
    row red and green, its second blue and white."""
    var pixels: List[UInt8] = [
        255,
        0,
        0,
        255,
        0,
        255,
        0,
        255,
        0,
        0,
        255,
        255,
        255,
        255,
        255,
        255,
    ]
    return "data:image/png;base64," + encode_base64(
        encode_png(Framebuffer(2, 2, pixels^))
    )


def _document(
    texture: String, material: String, scene: String = ""
) raises -> String:
    """Return a document of one box mesh, one material and one texture `t`,
    each with extra fields, under a scene root with extra fields."""
    return (
        '"geometries":[{"uuid":"g","type":"BoxGeometry"}],'
        + '"materials":[{"uuid":"m"'
        + material
        + "}],"
        + '"textures":[{"uuid":"t","image":"i"'
        + texture
        + "}],"
        + '"images":[{"uuid":"i","url":"'
        + _png_url()
        + '"}],'
        + '"object":{"uuid":"s","type":"Scene"'
        + scene
        + ',"children":[{"uuid":"o","type":"Mesh","geometry":"g",'
        + '"material":"m"}]}'
    )


# --- the constants ------------------------------------------------------------


def test_each_filter_constant_names_its_filter() raises:
    var filters: List[Filter] = [
        NEAREST,
        NEAREST_MIPMAP_NEAREST,
        NEAREST_MIPMAP_LINEAR,
        BILINEAR,
        LINEAR_MIPMAP_NEAREST,
        LINEAR_MIPMAP_LINEAR,
    ]
    for index in range(len(filters)):
        assert_equal(filter_of(1003 + index), filters[index])
        assert_equal(filter_code(filters[index]), 1003 + index)
    with assert_raises(contains="six"):
        _ = filter_of(1009)


# --- read ---------------------------------------------------------------------


def test_a_texture_reads_its_sampler_axis_by_axis() raises:
    var read = _read(
        _document(
            ',"wrap":[1000,1002],"magFilter":1003,"minFilter":1004,'
            + '"flipY":false,"mapping":303',
            ',"type":"MeshBasicMaterial","map":"t"',
        )
    )
    ref texture = read[1].textures.get(TextureId(0))
    assert_equal(texture.wrap_s, REPEAT)
    assert_equal(texture.wrap_t, MIRROR)
    assert_equal(texture.mag_filter, NEAREST)
    assert_equal(texture.min_filter, NEAREST_MIPMAP_NEAREST)
    assert_true(texture.levels > 1)
    assert_false(texture.flip_y)
    assert_equal(texture.mapping, EQUIRECTANGULAR_REFLECTION_MAPPING)
    # Without a chain, a mipmap filter is kept, and read inside a level.
    var plain = _read(
        _document(
            ',"minFilter":1007,"generateMipmaps":false',
            ',"type":"MeshBasicMaterial","map":"t"',
        )
    )
    ref flat = plain[1].textures.get(TextureId(0))
    assert_equal(flat.min_filter, LINEAR_MIPMAP_NEAREST)
    assert_equal(flat.levels, 1)
    assert_equal(flat.wrap_t, CLAMP)
    assert_true(flat.flip_y)
    assert_equal(flat.mapping, UV_MAPPING)


def test_a_material_reads_its_frames() raises:
    var read = _read(
        _document(
            "",
            ',"type":"MeshPhongMaterial","normalMap":"t","normalMapType":1,'
            + '"envMapRotation":[0,1.5,0,"YXZ"],"refractionRatio":0.5',
        )
    )
    var phong = read[1].materials.get(MaterialId(0))
    assert_equal(phong.normal_map_type, OBJECT_SPACE_NORMAL_MAP)
    assert_almost_equal(phong.env_map_rotation.y.value, 1.5, atol=1e-6)
    assert_equal(phong.env_map_rotation.order, YXZ)
    assert_almost_equal(phong.refraction_ratio, 0.5, atol=1e-6)
    # A rotation of three numbers is `XYZ`, and a standard material has no
    # refraction ratio to read.
    var standard = _read(
        _document(
            "",
            ',"type":"MeshStandardMaterial","envMapRotation":[0,0,0.5],'
            + '"refractionRatio":0.5,"normalMapType":1',
        )
    )
    var metal = standard[1].materials.get(MaterialId(0))
    assert_almost_equal(metal.env_map_rotation.z.value, 0.5, atol=1e-6)
    assert_equal(metal.env_map_rotation.order, XYZ)
    assert_equal(metal.refraction_ratio, DEFAULT_REFRACTION_RATIO)
    # Without a normal map the type is not read.
    assert_equal(metal.normal_map_type, TANGENT_SPACE_NORMAL_MAP)
    # Classes with no environment read neither key.
    var toon = _read(
        _document(
            "",
            ',"type":"MeshToonMaterial","envMapRotation":[0,1,0],'
            + '"refractionRatio":0.5',
        )
    )
    var stepped = toon[1].materials.get(MaterialId(0))
    assert_equal(stepped.env_map_rotation.y.value, 0)
    assert_equal(stepped.refraction_ratio, DEFAULT_REFRACTION_RATIO)
    var sprite = _read(
        _document(
            "",
            ',"type":"SpriteMaterial","envMapRotation":[0,1,0],'
            + '"refractionRatio":0.5',
        )
    )
    var flat = sprite[1].materials.get(MaterialId(0))
    assert_equal(flat.env_map_rotation.y.value, 0)
    assert_equal(flat.refraction_ratio, DEFAULT_REFRACTION_RATIO)


def test_a_scene_reads_its_background_and_environment_settings() raises:
    var read = _read(
        _document(
            "",
            ',"type":"MeshBasicMaterial"',
            ',"backgroundBlurriness":0.25,"backgroundIntensity":2,'
            + '"backgroundRotation":[0,1,0,"ZYX"],'
            + '"environmentIntensity":0.5,"environmentRotation":[1,0,0]',
        )
    )
    ref scene = read[0]
    assert_almost_equal(scene.background_blurriness, 0.25, atol=1e-6)
    assert_almost_equal(scene.background_intensity, 2, atol=1e-6)
    assert_equal(scene.background_rotation.order, ZYX)
    assert_almost_equal(scene.environment_intensity, 0.5, atol=1e-6)
    assert_almost_equal(scene.environment_rotation.x.value, 1, atol=1e-6)
    _refuses(
        _document(
            "", ',"type":"MeshBasicMaterial"', ',"backgroundBlurriness":2'
        ),
        "blurriness",
    )


def test_a_panorama_becomes_an_environment_read_directly() raises:
    # One panorama, the background, the environment and a standard
    # material's `envMap` at once: one cube, prefiltered once.
    var read = _read(
        _document(
            ',"mapping":303',
            ',"type":"MeshStandardMaterial","envMap":"t"',
            ',"background":"t","backgroundBlurriness":0.5,"environment":"t"',
        )
    )
    ref scene = read[0]
    ref assets = read[1]
    assert_equal(assets.cube_textures.count(), 1)
    assert_equal(scene.background.kind, CUBE_BACKGROUND)
    ref cube = assets.cube_textures.get(scene.environment)
    assert_true(cube.has_panorama())
    assert_true(cube.is_prefiltered())
    assert_equal(cube.mapping, EQUIRECTANGULAR_REFLECTION_MAPPING)
    # A basic mirror reads it without a PMREM, and a sharp background is
    # the flat texture itself.
    var basic = _read(
        _document(
            ',"mapping":304',
            ',"type":"MeshBasicMaterial","envMap":"t"',
            ',"background":"t"',
        )
    )
    ref plain = basic[1]
    assert_equal(basic[0].background.kind, TEXTURE_BACKGROUND)
    ref bent = plain.cube_textures.get(CubeTextureId(0))
    assert_false(bent.is_prefiltered())
    assert_equal(bent.mapping, EQUIRECTANGULAR_REFRACTION_MAPPING)
    # A blurred background that is a plain picture stays a picture.
    var picture = _read(
        _document(
            "",
            ',"type":"MeshBasicMaterial"',
            ',"background":"t","backgroundBlurriness":0.5',
        )
    )
    assert_equal(picture[0].background.kind, TEXTURE_BACKGROUND)
    # An env map must be a cube or a panorama.
    _refuses(
        _document("", ',"type":"MeshBasicMaterial","envMap":"t"'),
        "not equirectangular",
    )
    # A flat texture's mapping cannot be a cube's.
    _refuses(
        _document(',"mapping":302', ',"type":"MeshBasicMaterial","map":"t"'),
        "mapping",
    )


# --- written and read back ------------------------------------------------------


def _textured_scene(mut assets: Assets) raises -> Scene:
    """Return a scene of one box whose phong material has a map, an
    object-space normal map and a panorama to reflect."""
    var pixels = List[UInt8](length=16, fill=200)
    var map = Texture(2, 2, pixels^, REPEAT, NEAREST, LINEAR, True)
    map.wrap_t = MIRROR
    map.min_filter = NEAREST_MIPMAP_NEAREST
    map.flip_y = False
    var map_id = assets.textures.add(map^)
    var normals = List[UInt8](length=16, fill=128)
    var normal_id = assets.textures.add(
        Texture(2, 2, normals^, CLAMP, BILINEAR, LINEAR, False, IGNORED)
    )
    var panorama_pixels = List[UInt8](length=24, fill=90)
    var panorama = Texture(3, 2, panorama_pixels^, CLAMP, BILINEAR)
    panorama.mapping = EQUIRECTANGULAR_REFRACTION_MAPPING
    var sky = assets.cube_textures.add(cube_of_panorama(panorama))
    var paint = assets.materials.add(
        Material(
            Color(255, 255, 255),
            kind=PHONG,
            map=map_id,
            normal_map=normal_id,
            normal_map_type=OBJECT_SPACE_NORMAL_MAP,
            env_map=sky,
            env_map_rotation=Euler(
                Angle(0.25, RADIAN),
                Angle(0.5, RADIAN),
                Angle(0.75, RADIAN),
                YXZ,
            ),
            refraction_ratio=0.75,
        )
    )
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(
        Mesh(
            assets.geometries.add(
                box(Length(1.0, METER), Length(1.0, METER), Length(1.0, METER))
            ),
            paint,
            node,
        )
    )
    scene.update()
    return scene^


def test_the_samplers_frames_and_settings_survive_a_round_trip() raises:
    var assets = Assets()
    var scene = _textured_scene(assets)
    scene.background_blurriness = 0.5
    scene.background_intensity = 0.25
    scene.background_rotation = Euler(
        Angle(0.0, RADIAN), Angle(1.0, RADIAN), Angle(0.0, RADIAN), ZYX
    )
    scene.environment_intensity = 3
    scene.environment_rotation = Euler(
        Angle(0.5, RADIAN), Angle(0.0, RADIAN), Angle(0.0, RADIAN), XYZ
    )
    var text = object_to_json(scene, assets)
    assert_true('"backgroundBlurriness"' in text)
    assert_true('"environmentIntensity"' in text)
    assert_true('"ZYX"' in text)
    var again = Scene()
    var back = Assets()
    _ = read_object_json(text, again, back)
    assert_almost_equal(again.background_blurriness, 0.5, atol=1e-6)
    assert_almost_equal(again.background_intensity, 0.25, atol=1e-6)
    assert_equal(again.background_rotation.order, ZYX)
    assert_almost_equal(again.environment_intensity, 3, atol=1e-6)
    assert_almost_equal(again.environment_rotation.x.value, 0.5, atol=1e-6)
    var paint = back.materials.get(MaterialId(0))
    assert_equal(paint.normal_map_type, OBJECT_SPACE_NORMAL_MAP)
    assert_almost_equal(paint.refraction_ratio, 0.75, atol=1e-6)
    assert_equal(paint.env_map_rotation.order, YXZ)
    assert_almost_equal(paint.env_map_rotation.z.value, 0.75, atol=1e-6)
    ref map = back.textures.get(paint.map)
    assert_equal(map.wrap_s, REPEAT)
    assert_equal(map.wrap_t, MIRROR)
    assert_equal(map.mag_filter, NEAREST)
    assert_equal(map.min_filter, NEAREST_MIPMAP_NEAREST)
    assert_false(map.flip_y)
    # The panorama is written as the flat texture it is, and read back as
    # a cube that reads it.
    ref sky = back.cube_textures.get(paint.env_map)
    assert_true(sky.has_panorama())
    assert_equal(sky.mapping, EQUIRECTANGULAR_REFRACTION_MAPPING)
    # The defaults write only the two rotations, as `Scene.toJSON` does.
    var plain = Scene()
    var bare = object_to_json(plain, Assets())
    assert_false('"backgroundBlurriness"' in bare)
    assert_false('"backgroundIntensity"' in bare)
    assert_false('"environmentIntensity"' in bare)
    assert_true('"backgroundRotation"' in bare)
    assert_true('"environmentRotation"' in bare)


def test_a_float_panorama_is_not_written() raises:
    var assets = Assets()
    var panorama = float_texture(2, 1, List[Float32](length=8, fill=2))
    panorama.mapping = EQUIRECTANGULAR_REFLECTION_MAPPING
    var sky = assets.cube_textures.add(cube_of_panorama(panorama))
    _ = assets.materials.add(Material(Color(255, 255, 255), env_map=sky))
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(
        Mesh(
            assets.geometries.add(
                box(Length(1.0, METER), Length(1.0, METER), Length(1.0, METER))
            ),
            MaterialId(0),
            node,
        )
    )
    scene.update()
    with assert_raises(contains="float texture"):
        _ = object_to_json(scene, assets)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
