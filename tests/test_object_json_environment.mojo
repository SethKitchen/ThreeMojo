# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the cube textures, environment maps, clipping planes,
distance ranges, dash offsets, morph influences and calculated bone
inverses that `exporters.object_json` writes and `loaders.object_loader`
reads.

The key test renders a scene with each of them, writes it as three.js
JSON, reads it back and renders it again: the two images must match. The
rest checks each field against three.js's keys and defaults, and every
refusal.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.background import cube_background
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry
from core.object3d import NodeId, Object3D
from core.scene import Scene
from exporters.gltf import encode_base64
from exporters.object_json import object_to_json
from geometries.box import box
from lights.light import ambient_light, directional_light
from loaders.object_loader import ObjectModel, read_object_json
from materials.material import (
    BASIC,
    DISTANCE,
    LAMBERT,
    MIX_OPERATION,
    PHONG,
    PHYSICAL,
    STANDARD,
    Material,
    MaterialId,
    distance_material,
    line_dashed_material,
)
from math.bounds import Plane
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from objects.line import Line
from objects.mesh import Mesh
from objects.skeleton import bind_skeleton
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT, SkinnedMesh
from render.cube_texture import CubeTexture, cube_uv_width
from render.cube_texture_store import (
    NO_CUBE_TEXTURE,
    SCENE_ENVIRONMENT,
    CubeTextureId,
)
from render.cube_uv import CUBE_UV_MIN_MIP
from render.framebuffer import Color, Framebuffer
from render.pmrem import pmrem_from_cube
from render.png import encode as encode_png
from render.srgb import LINEAR, SRGB
from render.texture import (
    BILINEAR,
    CLAMP,
    COVERAGE,
    NEAREST,
    Texture,
    float_texture,
)
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

comptime TOLERANCE = Float64(1e-5)
comptime WHITE = Color(255, 255, 255)
comptime SIDE = 48
# The side of each cube face: the smallest a PMREM reads at its own size.
comptime FACE = 16


def _face_pixels(face: Int) -> List[UInt8]:
    """Return a face whose texels differ left to right and top to bottom,
    so that a mirror or a flip would show."""
    var pixels = List[UInt8]()
    for y in range(FACE):
        for x in range(FACE):
            pixels.append(UInt8((face * 40 + x * 12) % 256))
            pixels.append(UInt8((face * 90 + y * 14) % 256))
            pixels.append(UInt8((255 - face * 30 - x * 5) % 256))
            pixels.append(255)
    return pixels^


def _cube_texture() raises -> CubeTexture:
    """Return a cube of six faces that each differ."""
    var faces = List[Texture]()
    for face in range(6):
        faces.append(
            Texture(
                FACE, FACE, _face_pixels(face), CLAMP, BILINEAR, SRGB, False
            )
        )
    return CubeTexture(faces^)


def _box() raises -> BufferGeometry:
    """Return a one-meter box."""
    return box(Length(1, METER), Length(1, METER), Length(1, METER))


def _read(text: String) raises -> Tuple[Scene, Assets, ObjectModel]:
    """Read a document into a fresh scene."""
    var scene = Scene()
    var assets = Assets()
    var model = read_object_json(text, scene, assets)
    return (scene^, assets^, model^)


def _wrap(document: String) -> String:
    """Return an Object document around an `object` and libraries."""
    return (
        '{"metadata":{"version":4.6,"type":"Object","generator":'
        '"Object3D.toJSON"},'
        + document
        + "}"
    )


def _refuses(document: String, message: String) raises:
    """Assert that a wrapped document is refused with a message."""
    var scene = Scene()
    var assets = Assets()
    with assert_raises(contains=message):
        _ = read_object_json(_wrap(document), scene, assets)


def _placed(
    mut scene: Scene, x: Float32, y: Float32, turned: Bool = True
) raises -> NodeId:
    """Add a node at a point, turned to show three faces."""
    var node = Object3D()
    node.set_position(x, y, 0)
    if turned:
        node.set_euler(Angle(30, DEGREE), Angle(45, DEGREE), Angle(0, DEGREE))
    return scene.add(node)


def _morphed() raises -> BufferGeometry:
    """Return a box with one morph target that stretches it."""
    var geometry = box(
        Length(1.2, METER), Length(1.2, METER), Length(1.2, METER)
    )
    var moved = List[Float32]()
    var positions = geometry.attribute_view("position").packed()
    for at in range(len(positions)):
        moved.append(positions[at] * (Float32(1.5) if at % 3 == 0 else 1))
    geometry.add_morph_target(BufferAttribute(moved^, 3))
    return geometry^


def _scene(mut assets: Assets) raises -> Scene:
    """Build a scene of each field this suite covers."""
    var scene = Scene()
    var sky = assets.cube_textures.add(_cube_texture())
    var room = assets.cube_textures.add(pmrem_from_cube(_cube_texture()))
    scene.background = cube_background(sky)
    scene.environment = room
    var cube = assets.geometries.add(
        box(Length(1.4, METER), Length(1.4, METER), Length(1.4, METER))
    )
    scene.add_mesh(
        Mesh(
            cube,
            assets.materials.add(
                Material(
                    Color(200, 120, 90),
                    kind=PHONG,
                    shininess=30,
                    env_map=sky,
                    reflectivity=0.5,
                    combine=MIX_OPERATION,
                )
            ),
            _placed(scene, -3.5, 3),
        )
    )
    scene.add_mesh(
        Mesh(
            cube,
            assets.materials.add(
                Material(Color(90, 200, 120), env_map=SCENE_ENVIRONMENT)
            ),
            _placed(scene, 0, 3),
        )
    )
    scene.add_mesh(
        Mesh(
            cube,
            assets.materials.add(
                Material(
                    Color(230, 230, 230),
                    kind=STANDARD,
                    roughness=0.3,
                    metalness=1,
                    env_map=SCENE_ENVIRONMENT,
                )
            ),
            _placed(scene, 3.5, 3),
        )
    )
    scene.add_mesh(
        Mesh(
            cube,
            assets.materials.add(
                Material(
                    Color(160, 200, 240),
                    kind=PHYSICAL,
                    roughness=0.6,
                    metalness=0.5,
                    env_map=room,
                )
            ),
            _placed(scene, -3.5, 0),
        )
    )
    # A box cut by two planes, only where it is behind both.
    var clipped = Material(Color(250, 200, 60), kind=BASIC)
    clipped.set_clipping_planes(
        [
            Plane(Vector3(1, 0, 0), -0.2),
            Plane(Vector3(0, 1, 0), -0.2),
        ],
        intersection=True,
        shadows=True,
    )
    scene.add_mesh(
        Mesh(cube, assets.materials.add(clipped), _placed(scene, 0, 0))
    )
    scene.add_mesh(
        Mesh(
            cube,
            assets.materials.add(
                distance_material(
                    Vector3(0, 0, 8), Length(5, METER), Length(12, METER)
                )
            ),
            # Not turned: a packed distance shows the last bit of a turn
            # decomposed and composed again.
            _placed(scene, 3.5, 0, False),
        )
    )
    var morphed = Mesh(
        assets.geometries.add(_morphed()),
        assets.materials.add(Material(Color(120, 90, 220))),
        _placed(scene, -3.5, -3.5),
    )
    morphed.set_morph_influence(0, 0.7)
    scene.add_mesh(morphed)
    var dashed = line_dashed_material(Color(255, 255, 0))
    var strip = BufferGeometry()
    strip.set_attribute(
        "position", BufferAttribute([0, 0, 0, 1, 0.5, 0, 2, 0, 0], 3)
    )
    var line_node = Object3D()
    line_node.set_position(1.5, -3.5, 0)
    scene.add_line(
        Line(
            assets.geometries.add(strip^),
            assets.materials.add(dashed),
            scene.add(line_node),
        )
    )
    scene.add_light(
        directional_light(Color(255, 250, 240), _placed(scene, 2, 4), 2)
    )
    scene.add_light(ambient_light(Color(60, 60, 60), 1))
    return scene^


def _render(mut scene: Scene, assets: Assets) raises -> List[Color]:
    """Return every pixel of the scene seen from ten meters back, with the
    materials' own clipping planes on."""
    scene.update()
    var camera = PerspectiveCamera(
        Angle(60, DEGREE), 1, Length(0.1, METER), Length(100, METER)
    )
    camera.place(Vector3(0, 0, 10), Vector3(0, 0, 0))
    var renderer = Renderer(SIDE, SIDE)
    renderer.local_clipping_enabled = True
    var image = renderer.render(scene, assets, camera)
    var pixels = List[Color]()
    for y in range(SIDE):
        for x in range(SIDE):
            pixels.append(image.get_pixel(x, y))
    return pixels^


def test_a_scene_read_back_renders_the_same() raises:
    """A scene with cube textures, environment maps, clipping planes, a
    distance range and a morph influence, written and read back, renders
    to the same image, within one step of rounding, and each field comes
    back as it was written."""
    var assets = Assets()
    var scene = _scene(assets)
    var text = object_to_json(scene, assets)
    var before = _render(scene, assets)
    var again = Scene()
    var read = Assets()
    _ = read_object_json(text, again, read)
    var after = _render(again, read)
    var drawn = 0
    for at in range(len(before)):
        var a = before[at]
        var b = after[at]
        assert_true(abs(Int(a.r) - Int(b.r)) <= 1)
        assert_true(abs(Int(a.g) - Int(b.g)) <= 1)
        assert_true(abs(Int(a.b) - Int(b.b)) <= 1)
        if Int(a.r) + Int(a.g) + Int(a.b) > 0:
            drawn += 1
    # The sky fills the frame, so every pixel was drawn.
    assert_equal(drawn, SIDE * SIDE)
    # Each cube is written once, and the same scene writes the same text.
    assert_equal(read.cube_textures.count(), 2)
    assert_equal(text, object_to_json(scene, assets))
    assert_true(text.find('"mapping":301') >= 0)
    ref stores = read
    ref materials = stores.materials
    ref meshes = again.meshes
    # The background is the sky, plain; the environment holds its PMREM.
    var sky = again.background.cube
    assert_false(stores.cube_textures.get(sky).is_prefiltered())
    assert_true(stores.cube_textures.get(again.environment).is_prefiltered())
    # The faces come back as they were, mirrored twice.
    ref face = stores.cube_textures.get(sky).faces[1]
    ref first = assets.cube_textures.get(CubeTextureId(0)).faces[1]
    for at in range(len(first.pixels)):
        assert_equal(face.pixels[at], first.pixels[at])
    assert_equal(face.color_space, SRGB)
    assert_equal(face.filter, BILINEAR)
    var phong = materials.get(meshes[0].material)
    assert_equal(phong.env_map, sky)
    assert_equal(phong.combine, MIX_OPERATION)
    assert_equal(phong.reflectivity, 0.5)
    # A lambert material that reflects the scene's environment names it.
    assert_equal(materials.get(meshes[1].material).env_map, again.environment)
    # A standard material without an envMap reflects the environment.
    assert_equal(materials.get(meshes[2].material).env_map, SCENE_ENVIRONMENT)
    assert_equal(materials.get(meshes[3].material).env_map, again.environment)
    var clipped = materials.get(meshes[4].material)
    var planes = clipped.clipping_planes()
    assert_equal(len(planes), 2)
    assert_equal(planes[1].normal.y, 1)
    assert_almost_equal(Float64(planes[1].constant), -0.2, atol=TOLERANCE)
    assert_true(clipped.clip_intersection)
    assert_true(clipped.clip_shadows)
    var distance = materials.get(meshes[5].material)
    assert_equal(distance.kind, DISTANCE)
    assert_equal(distance.reference_position.z, 8)
    assert_equal(distance.near_distance.to(METER), 5)
    assert_equal(distance.far_distance.to(METER), 12)
    assert_almost_equal(
        Float64(meshes[6].morph_influence(0)), 0.7, atol=TOLERANCE
    )


def _data_url(face: Int) raises -> String:
    """Return a face as a PNG `data:` URL."""
    var png = encode_png(Framebuffer(FACE, FACE, _face_pixels(face)))
    return "data:image/png;base64," + encode_base64(png)


def _cube_document(
    texture: String = "", material: String = "", scene: String = ""
) raises -> String:
    """Return a document with one cube texture of six images, a material
    and a scene root, each with extra fields."""
    var urls = String()
    for face in range(6):
        if face > 0:
            urls += ","
        urls += '"' + _data_url(face) + '"'
    return _wrap(
        '"images":[{"uuid":"i","url":['
        + urls
        + ']}],"textures":[{"uuid":"c","image":"i"'
        + texture
        + '}],"materials":[{"uuid":"m"'
        + material
        + '}],"object":{"uuid":"s","type":"Scene"'
        + scene
        + "}"
    )


def test_a_cube_as_three_js_writes_it() raises:
    """A cube texture is six images in the OpenGL layout, read at three.js's
    defaults; `flipY` turns each face over."""
    var read = _read(
        _cube_document(
            ',"magFilter":1003,"minFilter":1003,"colorSpace":"srgb-linear"',
            ',"type":"MeshBasicMaterial","envMap":"c"',
            ',"background":"c"',
        )
    )
    var id = read[1].materials.get(MaterialId(0)).env_map
    assert_equal(id, read[0].background.cube)
    assert_equal(read[0].environment, NO_CUBE_TEXTURE)
    ref cube = read[1].cube_textures.get(id)
    assert_false(cube.is_prefiltered())
    assert_equal(cube.faces[0].filter, NEAREST)
    assert_equal(cube.faces[0].color_space, LINEAR)
    assert_equal(cube.faces[0].levels, 1)
    # The first texel of a face is the last of the file's first row.
    var file = _face_pixels(2)
    assert_equal(cube.faces[2].pixels[0], file[(FACE - 1) * 4])
    # Turned over, the first row is the file's last.
    var flipped = _read(
        _cube_document(
            ',"flipY":true', ',"type":"MeshBasicMaterial","envMap":"c"'
        )
    )
    ref turned = flipped[1].cube_textures.get(CubeTextureId(0))
    assert_equal(turned.faces[2].pixels[0], file[(FACE * FACE - 1) * 4])
    assert_equal(turned.faces[2].filter, BILINEAR)
    assert_equal(turned.faces[2].color_space, LINEAR)
    # three.js's default filters give a mip chain.
    assert_true(turned.faces[2].levels > 1)


def test_the_environment_and_what_reads_it() raises:
    """The scene's environment is prefiltered, and so is a cube a standard
    or physical material names; a standard or physical material without an
    envMap reflects the environment; other classes do not."""
    # The basic material builds the cube plain, the standard one gives it
    # its PMREM, and the environment finds it prefiltered already.
    var read = _read(
        _cube_document(
            material=(
                ',"type":"MeshBasicMaterial","envMap":"c"},'
                '{"uuid":"n","type":"MeshStandardMaterial","envMap":"c"'
            ),
            scene=',"environment":"c"',
        )
    )
    var env = read[0].environment
    assert_true(read[1].cube_textures.get(env).is_prefiltered())
    assert_equal(read[1].materials.get(MaterialId(0)).env_map, env)
    assert_equal(read[1].materials.get(MaterialId(1)).env_map, env)
    assert_equal(read[1].cube_textures.count(), 1)
    # A physical material without an envMap reflects the environment, a
    # basic one reflects nothing.
    var standard = _read(
        _cube_document(material=',"type":"MeshPhysicalMaterial"')
    )
    assert_equal(
        standard[1].materials.get(MaterialId(0)).env_map, SCENE_ENVIRONMENT
    )
    var basic = _read(_cube_document(material=',"type":"MeshBasicMaterial"'))
    assert_equal(basic[1].materials.get(MaterialId(0)).env_map, NO_CUBE_TEXTURE)
    # A class whose shader reads no envMap ignores one.
    var toon = _read(
        _cube_document(material=',"type":"MeshToonMaterial","envMap":"c"')
    )
    assert_equal(toon[1].materials.get(MaterialId(0)).env_map, NO_CUBE_TEXTURE)
    assert_equal(toon[1].cube_textures.count(), 0)
    var line = _read(
        _cube_document(material=',"type":"LineBasicMaterial","envMap":"c"')
    )
    assert_equal(line[1].materials.get(MaterialId(0)).env_map, NO_CUBE_TEXTURE)


def test_the_reader_refuses_a_cube_it_cannot_read() raises:
    """A cube with the wrong mapping or number of images, an envMap that
    is not a cube, and a map that is a cube are refused."""
    var scene = Scene()
    var assets = Assets()
    with assert_raises(contains="CubeReflectionMapping"):
        _ = read_object_json(
            _cube_document(
                ',"mapping":302', ',"type":"MeshBasicMaterial","envMap":"c"'
            ),
            scene,
            assets,
        )
    with assert_raises(contains="read only from one URL"):
        _ = read_object_json(
            _cube_document(material=',"type":"MeshBasicMaterial","map":"c"'),
            scene,
            assets,
        )
    var flat = (
        '"images":[{"uuid":"i","url":"'
        + _data_url(0)
        + '"},{"uuid":"five","url":["a","b","c","d","e"]},{"uuid":"none"}],'
        '"textures":[{"uuid":"t","image":"i"},{"uuid":"f","image":"five"},'
        '{"uuid":"n","image":"none"}],'
    )
    _refuses(
        flat
        + '"materials":[{"uuid":"m","type":"MeshBasicMaterial","envMap":"t"}],'
        '"object":{"uuid":"o","type":"Group"}',
        "is not a cube",
    )
    _refuses(
        flat + '"object":{"uuid":"o","type":"Scene","environment":"f"}',
        "six images",
    )
    _refuses(
        flat + '"object":{"uuid":"o","type":"Scene","background":"n"}',
        "has no URL",
    )
    _refuses(
        flat + '"object":{"uuid":"o","type":"Scene","background":"x"}',
        "names no texture",
    )
    # A plain texture background still reads as one.
    var read = _read(
        _wrap(flat + '"object":{"uuid":"o","type":"Scene","background":"t"}')
    )
    assert_equal(read[1].textures.count(), 1)


def test_clipping_distance_and_offset_as_written() raises:
    """The clipping planes, the distance range and the dash offset are read
    under their keys, with three.js's defaults."""
    var material = _read(
        _wrap(
            '"materials":[{"uuid":"m","type":"MeshBasicMaterial",'
            '"clippingPlanes":[{"normal":[0,0,2],"constant":1},'
            '{"normal":[1,0,0]}],"dashOffset":2}],'
            '"object":{"uuid":"o","type":"Group"}'
        )
    )[1].materials.get(MaterialId(0))
    var planes = material.clipping_planes()
    assert_equal(len(planes), 2)
    # A plane is normalized, as `Plane` is built.
    assert_equal(planes[0].normal.z, 1)
    assert_equal(planes[0].constant, 0.5)
    assert_equal(planes[1].constant, 0)
    assert_false(material.clip_intersection)
    assert_false(material.clip_shadows)
    assert_equal(material.dash_offset.to(METER), 2)
    var distance = _read(
        _wrap(
            '"materials":[{"uuid":"m","type":"MeshDistanceMaterial"},'
            '{"uuid":"n","type":"MeshDistanceMaterial","nearDistance":2,'
            '"farDistance":9,"referencePosition":[1,2,3]},'
            '{"uuid":"l","type":"MeshLambertMaterial","dashOffset":2,'
            '"referencePosition":[1,2,3]}],'
            '"object":{"uuid":"o","type":"Group"}'
        )
    )
    ref materials = distance[1].materials
    assert_equal(materials.get(MaterialId(0)).near_distance.to(METER), 1)
    assert_equal(materials.get(MaterialId(0)).far_distance.to(METER), 1000)
    assert_equal(materials.get(MaterialId(1)).reference_position.y, 2)
    assert_equal(materials.get(MaterialId(1)).near_distance.to(METER), 2)
    assert_equal(materials.get(MaterialId(1)).far_distance.to(METER), 9)
    # Another class reads neither.
    assert_equal(materials.get(MaterialId(2)).dash_offset.to(METER), 0)
    assert_equal(materials.get(MaterialId(2)).reference_position.y, 0)
    var refused = (
        '"object":{"uuid":"o","type":"Group"},"materials":[{"uuid":"m",'
        '"type":"MeshBasicMaterial",'
    )
    # The writer writes a dash offset where a material has one.
    var assets = Assets()
    var scene = Scene()
    var dashed = Material(WHITE, kind=BASIC)
    dashed.dash_offset = Length(0.5, METER)
    scene.add_mesh(
        Mesh(
            assets.geometries.add(_box()),
            assets.materials.add(dashed),
            scene.add(Object3D()),
        )
    )
    var again = _read(object_to_json(scene, assets))
    assert_equal(
        again[1].materials.get(MaterialId(0)).dash_offset.to(METER), 0.5
    )
    # An empty list of planes clears them.
    var none = _read(_wrap(refused + '"clippingPlanes":[]}]'))[1].materials.get(
        MaterialId(0)
    )
    assert_equal(len(none.clipping_planes()), 0)
    _refuses(refused + '"clippingPlanes":[3]}]', "is an object")
    _refuses(refused + '"clippingPlanes":[{}]}]', "has no normal")
    var nine = String()
    for plane in range(9):
        if plane > 0:
            nine += ","
        nine += '{"normal":[1,0,0]}'
    _refuses(refused + '"clippingPlanes":[' + nine + "]}]", "at most")
    _refuses(
        (
            '"object":{"uuid":"o","type":"Group"},"materials":[{"uuid":"m",'
            '"type":"MeshDistanceMaterial","farDistance":0.5}]'
        ),
        "far distance",
    )


def test_morph_influences_as_written() raises:
    """A mesh reads up to eight influences, and the rest are zero."""
    var library = (
        '"geometries":[{"uuid":"g","type":"BoxGeometry"}],'
        '"materials":[{"uuid":"m","type":"MeshBasicMaterial"}],'
    )
    var read = _read(
        _wrap(
            library
            + '"object":{"uuid":"o","type":"Mesh","geometry":"g",'
            '"material":"m","morphTargetInfluences":[0.25,0.5]}'
        )
    )
    assert_equal(read[0].meshes[0].morph_influence(1), 0.5)
    assert_equal(read[0].meshes[0].morph_influence(2), 0)
    var bare = _read(
        _wrap(
            library
            + '"object":{"uuid":"o","type":"Mesh","geometry":"g",'
            '"material":"m","morphTargetInfluences":[]}'
        )
    )
    assert_false(bare[0].meshes[0].is_morphed())
    _refuses(
        library
        + '"object":{"uuid":"o","type":"Mesh","geometry":"g",'
        '"material":"m","morphTargetInfluences":[0,0,0,0,0,0,0,0,0]}',
        "eight morph influences",
    )
    # The writer leaves them out of a geometry without morph targets.
    var assets = Assets()
    var scene = Scene()
    scene.add_mesh(
        Mesh(
            assets.geometries.add(_box()),
            assets.materials.add(Material(WHITE)),
            scene.add(Object3D()),
        )
    )
    assert_equal(
        object_to_json(scene, assets).find("morphTargetInfluences"), -1
    )


def _skinned_triangle() raises -> BufferGeometry:
    """Return a triangle with one morph target, which the first bone
    carries whole."""
    var geometry = BufferGeometry()
    geometry.set_attribute(
        "position", BufferAttribute([0, 0, 0, 1, 0, 0, 0, 1, 0], 3)
    )
    geometry.set_attribute(
        SKIN_INDEX, BufferAttribute([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], 4)
    )
    geometry.set_attribute(
        SKIN_WEIGHT, BufferAttribute([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0], 4)
    )
    geometry.add_morph_target(BufferAttribute([0, 0, 0, 2, 0, 0, 0, 2, 0], 3))
    return geometry^


def test_a_skeleton_without_inverses_is_bound_where_it_stands() raises:
    """A skeleton without `boneInverses`, or with none, gets the inverse of
    each bone's world matrix, as `Skeleton.calculateInverses` does."""
    var skin = (
        '"geometries":[{"uuid":"g","type":"BoxGeometry"}],'
        '"materials":[{"uuid":"m","type":"MeshBasicMaterial"}],'
        '"skeletons":[{"uuid":"s","bones":["b","c"]SKELETON}],'
        '"object":{"uuid":"o","type":"SkinnedMesh","geometry":"g",'
        '"material":"m","skeleton":"s","morphTargetInfluences":[0.5],'
        '"position":[1,0,0],"children":[{"uuid":"b","type":"Bone",'
        '"position":[0,2,0],"children":[{"uuid":"c","type":"Bone",'
        '"position":[0,0,3]}]}]}'
    )
    for inverses in [String(""), String(',"boneInverses":[]')]:
        var read = _read(_wrap(skin.replace("SKELETON", inverses)))
        ref mesh = read[0].skinned_meshes[0]
        ref first = mesh.skeleton.bones[0].inverse_bind
        ref second = mesh.skeleton.bones[1].inverse_bind
        assert_equal(first.elements[12], -1)
        assert_equal(first.elements[13], -2)
        assert_equal(second.elements[14], -3)
        assert_equal(mesh.morph_influence(0), 0.5)
    # The writer writes a skinned mesh's influences too.
    var assets = Assets()
    var scene = Scene()
    var holder = scene.add(Object3D())
    var bone = scene.attach(Object3D(), holder)
    scene.update()
    var mesh = SkinnedMesh(
        assets.geometries.add(_skinned_triangle()),
        assets.materials.add(Material(WHITE)),
        holder,
        bind_skeleton([bone], [scene.world_matrix(bone)]),
    )
    mesh.set_morph_influence(0, 0.25)
    scene.add_skinned_mesh(mesh^)
    var again = _read(object_to_json(scene, assets))
    assert_equal(again[0].skinned_meshes[0].morph_influence(0), 0.25)


def _prefiltered() raises -> CubeTexture:
    """Return a cube that holds a blank PMREM of the right size: the writer
    asks only that there is one."""
    var cube = _cube_texture()
    var tall = 4 << CUBE_UV_MIN_MIP
    cube.cube_uv = float_texture(
        cube_uv_width(CUBE_UV_MIN_MIP),
        tall,
        List[Float32](length=cube_uv_width(CUBE_UV_MIN_MIP) * tall * 4, fill=0),
    )
    cube.validate()
    return cube^


def _writes(mut scene: Scene, assets: Assets, message: String) raises:
    """Assert that the writer refuses a scene with a message."""
    with assert_raises(contains=message):
        _ = object_to_json(scene, assets)


def test_the_writer_refuses_a_reflection_three_js_would_change() raises:
    """A cube a physical material or the environment reads must hold its
    PMREM, a physical material that reflects nothing must not sit in a
    scene with an environment, and a cube must be one PNG can hold."""
    var assets = Assets()
    var plain = assets.cube_textures.add(_cube_texture())
    var filtered = assets.cube_textures.add(_prefiltered())
    var cube = assets.geometries.add(_box())
    var scene = Scene()
    scene.add_mesh(
        Mesh(
            cube,
            assets.materials.add(Material(WHITE, kind=STANDARD, env_map=plain)),
            scene.add(Object3D()),
        )
    )
    _writes(scene, assets, "through its PMREM")
    var lit = Scene()
    lit.environment = plain
    _writes(lit, assets, "prefilters the scene's environment")
    lit.environment = filtered
    lit.add_mesh(
        Mesh(
            cube,
            assets.materials.add(Material(WHITE, kind=STANDARD)),
            lit.add(Object3D()),
        )
    )
    _writes(lit, assets, "reflects nothing in a scene with an environment")
    # A basic material that reflects nothing sits in such a scene well.
    var basic = Scene()
    basic.environment = filtered
    basic.add_mesh(
        Mesh(cube, assets.materials.add(Material(WHITE)), basic.add(Object3D()))
    )
    _ = object_to_json(basic, assets)
    # A standard material that reflects the environment names none.
    var shared = Scene()
    shared.environment = filtered
    shared.add_mesh(
        Mesh(
            cube,
            assets.materials.add(
                Material(WHITE, kind=STANDARD, env_map=SCENE_ENVIRONMENT)
            ),
            shared.add(Object3D()),
        )
    )
    assert_equal(object_to_json(shared, assets).find('"envMap"'), -1)
    # A cube whose faces differ, or hold floats, has no PNG form.
    var mixed = _cube_texture()
    mixed.faces[3].filter = NEAREST
    var sky = Scene()
    sky.background = cube_background(assets.cube_textures.add(mixed^))
    _writes(sky, assets, "share their filter")
    var faces = List[Texture]()
    for _ in range(6):
        faces.append(
            float_texture(
                2, 2, List[Float32](length=16, fill=0.5), CLAMP, NEAREST
            )
        )
    sky.background = cube_background(
        assets.cube_textures.add(CubeTexture(faces^))
    )
    _writes(sky, assets, "float faces")
    sky.background = cube_background(CubeTextureId(99))
    _writes(sky, assets, "No cube texture has that id")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
