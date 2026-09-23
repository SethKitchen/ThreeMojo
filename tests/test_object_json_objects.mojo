# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the newer material fields and the other objects that
`exporters.object_json` writes and `loaders.object_loader` reads.

The key test renders a scene, writes it as three.js JSON, reads it back
and renders it again: the two images must match. The rest checks each
field and object against three.js's keys and defaults, and every refusal.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import NORMAL, POSITION, UV, UV1, BufferGeometry
from core.geometry_store import GeometryId
from core.object3d import NodeId, Object3D
from core.scene import Scene
from exporters.gltf import encode_base64
from exporters.object_json import object_to_json, object_uuid
from geometries.box import box
from lights.light import ambient_light, directional_light
from loaders.object_loader import (
    ObjectModel,
    bind_mode_name,
    bind_mode_of,
    line_type_names,
    read_object_json,
    stencil_op_code,
    stencil_op_of,
)
from materials.material import (
    BASIC,
    DEPTH,
    DOUBLE_SIDE,
    LAMBERT,
    NO_TEXTURE,
    PHONG,
    PHYSICAL,
    STANDARD,
    LineWidth,
    Material,
    MaterialId,
    PointSize,
    line_dashed_material,
    points_material,
    sprite_material,
)
from math.matrix4 import Matrix4, translation
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.instanced_mesh import BatchedMesh
from objects.line import LOOP, SEGMENTS, STRIP, Line, LineMode
from objects.lod import Lod
from objects.mesh import Mesh
from objects.points import Points
from objects.skeleton import bind_skeleton
from objects.skinned_mesh import (
    ATTACHED,
    DETACHED,
    SKIN_INDEX,
    SKIN_WEIGHT,
    BindMode,
    SkinnedMesh,
)
from objects.sprite import Sprite
from render.framebuffer import Color, Framebuffer
from render.png import encode as encode_png
from render.packing import RGBA_DEPTH_PACKING
from render.raster_state import (
    EQUAL_STENCIL_FUNC,
    GREATER_DEPTH,
    INVERT_STENCIL_OP,
    REPLACE_STENCIL_OP,
    ZERO_STENCIL_OP,
    StencilOp,
)
from render.srgb import LINEAR, SRGB
from render.texture import (
    COVERAGE,
    IGNORED,
    NEAREST,
    REPEAT,
    UV_CHANNEL_1,
    Texture,
)
from render.texture_store import TextureId
from renderers.renderer import Renderer
from std.math import inf
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER, NANOMETER, RADIAN

comptime TOLERANCE = Float64(1e-5)
comptime WHITE = Color(255, 255, 255)
comptime SIDE = 48


def _image(
    seed: Int, data: Bool = False, alpha_read: Bool = False
) raises -> Texture:
    """Return a 2 by 2 texture whose texels differ: a color image, or data
    whose alpha is ignored unless `alpha_read`."""
    var pixels = List[UInt8]()
    for texel in range(4):
        pixels.append(UInt8((seed + texel * 61) % 256))
        pixels.append(UInt8((seed * 3 + texel * 37) % 256))
        pixels.append(UInt8((seed * 7 + texel * 23) % 256))
        pixels.append(UInt8(255 - texel * 40))
    var ignored = data and not alpha_read
    return Texture(
        2,
        2,
        pixels^,
        REPEAT,
        NEAREST,
        LINEAR if data else SRGB,
        False,
        IGNORED if ignored else COVERAGE,
    )


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


def _material(fields: String) raises -> Material:
    """Return the one material of a document with a group root."""
    var read = _read(
        _wrap(
            '"materials":[{"uuid":"m",'
            + fields
            + '}],"object":{"uuid":"o","type":"Group"}'
        )
    )
    return read[1].materials.get(MaterialId(0))


def _skinned_triangle() raises -> BufferGeometry:
    """Return a triangle the first bone carries whole."""
    var geometry = BufferGeometry()
    geometry.set_attribute(
        POSITION, BufferAttribute([0, 0, 0, 1, 0, 0, 0, 1, 0], 3)
    )
    geometry.set_attribute(
        NORMAL, BufferAttribute([0, 0, 1, 0, 0, 1, 0, 0, 1], 3)
    )
    geometry.set_attribute(
        SKIN_INDEX, BufferAttribute([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], 4)
    )
    geometry.set_attribute(
        SKIN_WEIGHT, BufferAttribute([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0], 4)
    )
    return geometry^


def _strip() raises -> BufferGeometry:
    """Return four points in a row, with no index."""
    var geometry = BufferGeometry()
    geometry.set_attribute(
        POSITION, BufferAttribute([0, 0, 0, 1, 0.5, 0, 2, 0, 0, 3, 0.5, 0], 3)
    )
    return geometry^


def _cube(size: Float32) raises -> BufferGeometry:
    """Return an indexed box with a second set of coordinates."""
    var geometry = box(
        Length(size, METER), Length(size, METER), Length(size, METER)
    )
    geometry.set_attribute(UV1, geometry.clone_attribute(UV))
    return geometry^


def _placed(
    mut scene: Scene, x: Float32, y: Float32, turned: Bool = True
) raises -> NodeId:
    """Add a node at a point, turned to show three faces."""
    var node = Object3D()
    node.set_position(x, y, 0)
    if turned:
        node.set_euler(Angle(30, DEGREE), Angle(45, DEGREE), Angle(0, DEGREE))
    return scene.add(node)


def _scene(mut assets: Assets) raises -> Scene:
    """Build a scene of every newer material field and every other object."""
    var scene = Scene()
    var color = assets.textures.add(_image(10))
    var data = assets.textures.add(_image(90, True))
    var alpha = assets.textures.add(_image(170, True, True))
    var second = _image(40, True)
    second.channel = UV_CHANNEL_1
    var baked = assets.textures.add(second^)
    var cube = assets.geometries.add(_cube(1.5))
    var small = assets.geometries.add(_cube(0.8))
    var physical = Material(
        Color(200, 60, 40),
        kind=PHYSICAL,
        roughness=0.4,
        clearcoat=0.5,
        sheen=0.75,
        sheen_color=Color(30, 200, 90),
        sheen_color_map=data,
        sheen_roughness=0.5,
        sheen_roughness_map=alpha,
        iridescence=0.5,
        iridescence_ior=1.8,
        iridescence_thickness_minimum=Length(50, NANOMETER),
        iridescence_thickness_maximum=Length(700, NANOMETER),
        iridescence_map=data,
        iridescence_thickness_map=data,
        dispersion=0.25,
        attenuation_color=Color(250, 200, 150),
        attenuation_distance=Length(2, METER),
        thickness=Length(0.5, METER),
        thickness_map=data,
    )
    scene.add_mesh(
        Mesh(cube, assets.materials.add(physical), _placed(scene, -3.5, 3))
    )
    var standard = Material(
        Color(120, 160, 220),
        kind=STANDARD,
        map=color,
        ao_map=baked,
        ao_map_intensity=0.5,
        light_map=baked,
        light_map_intensity=2,
        flat_shading=True,
    )
    standard.set_displacement(data, Length(0.25, METER), Length(0.1, METER))
    scene.add_mesh(
        Mesh(cube, assets.materials.add(standard), _placed(scene, 0, 3))
    )
    var shiny = Material(
        Color(90, 220, 120),
        kind=PHONG,
        specular=Color(255, 255, 255),
        shininess=40,
        specular_map=data,
    )
    shiny.polygon_offset = True
    shiny.polygon_offset_factor = 1
    shiny.polygon_offset_units = 2
    scene.add_mesh(
        Mesh(cube, assets.materials.add(shiny), _placed(scene, 3.5, 3))
    )
    # An LOD whose near level shows, and its far one.
    var near = assets.materials.add(Material(Color(240, 200, 60)))
    var far = assets.materials.add(Material(Color(60, 60, 240)))
    var lod = Lod(_placed(scene, -3.5, 0))
    lod.add_level(cube, near)
    lod.add_level(small, far, Length(50, METER), 0.25)
    scene.add_lod(lod^)
    # A batch of two geometries, one instance tinted.
    var batch = BatchedMesh(
        assets.materials.add(Material(WHITE)), _placed(scene, 0, 0)
    )
    _ = batch.add_instance(small, translation(-0.9, 0, 0))
    var tinted = batch.add_instance(cube, translation(0.9, 0, 0))
    batch.set_color_at(tinted, Color(255, 128, 0))
    _ = batch.add_instance(small, translation(0, 1, 0))
    scene.add_batched_mesh(batch^)
    # A triangle carried by a bone that has moved since it was bound.
    var holder = _placed(scene, 2.5, -1, False)
    var bone = scene.attach(Object3D(), holder)
    scene.update()
    var skeleton = bind_skeleton([bone], [scene.world_matrix(bone)])
    scene.add_skinned_mesh(
        SkinnedMesh(
            assets.geometries.add(_skinned_triangle()),
            assets.materials.add(
                Material(Color(250, 90, 200), side=DOUBLE_SIDE)
            ),
            holder,
            skeleton^,
        )
    )
    scene.node(bone).set_position(0.5, 0.25, 0)
    # A dashed line, points and a sprite.
    scene.add_line(
        Line(
            assets.geometries.add(_strip()),
            assets.materials.add(line_dashed_material(Color(255, 255, 0))),
            _placed(scene, -5, -3.5, False),
        )
    )
    scene.add_points(
        Points(
            assets.geometries.add(_strip()),
            assets.materials.add(
                points_material(Color(0, 255, 255), PointSize(3))
            ),
            _placed(scene, -1, -3, False),
        )
    )
    var sprite_node = _placed(scene, 3.5, -3, False)
    scene.node(sprite_node).set_scale(1.5, 1.5, 1.5)
    scene.add_sprite(
        Sprite(
            assets.materials.add(
                sprite_material(
                    Color(255, 200, 200), map=color, rotation=Angle(30, DEGREE)
                )
            ),
            sprite_node,
            center=Vector2(0.25, 0.75),
        )
    )
    scene.add_light(
        directional_light(Color(255, 250, 240), _placed(scene, 2, 4, False), 2)
    )
    scene.add_light(ambient_light(Color(60, 60, 60), 1))
    return scene^


def _render(mut scene: Scene, assets: Assets) raises -> List[Color]:
    """Return every pixel of the scene seen from ten meters back."""
    scene.update()
    var camera = PerspectiveCamera(
        Angle(60, DEGREE), 1, Length(0.1, METER), Length(100, METER)
    )
    camera.place(Vector3(0, 0, 10), Vector3(0, 0, 0))
    var image = Renderer(SIDE, SIDE).render(scene, assets, camera)
    var pixels = List[Color]()
    for y in range(SIDE):
        for x in range(SIDE):
            pixels.append(image.get_pixel(x, y))
    return pixels^


def test_a_scene_read_back_renders_the_same() raises:
    """A scene of every newer field and object, written and read back,
    renders to the same image, within one step of rounding."""
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
    # Something was drawn, so the match means something.
    assert_true(drawn > SIDE * SIDE // 8)
    # Every object is there again.
    assert_equal(len(again.meshes), 3)
    assert_equal(len(again.lods), 1)
    assert_equal(len(again.batched_meshes), 1)
    assert_equal(len(again.skinned_meshes), 1)
    assert_equal(len(again.lines), 1)
    assert_equal(len(again.points), 1)
    assert_equal(len(again.sprites), 1)
    # The same scene writes the same text.
    assert_equal(text, object_to_json(scene, assets))


def test_the_newer_material_fields_round_trip() raises:
    """Every newer field of a material comes back as it was written."""
    var assets = Assets()
    var scene = _scene(assets)
    var read = _read(object_to_json(scene, assets))
    ref materials = read[1].materials
    ref meshes = read[0].meshes
    var physical = materials.get(meshes[0].material)
    assert_equal(physical.kind, PHYSICAL)
    assert_equal(physical.sheen, 0.75)
    assert_equal(physical.sheen_color.hex(), Color(30, 200, 90).hex())
    assert_equal(physical.sheen_roughness, 0.5)
    assert_true(physical.sheen_color_map != NO_TEXTURE)
    assert_equal(
        read[1].textures.get(physical.sheen_roughness_map).alpha, COVERAGE
    )
    assert_equal(read[1].textures.get(physical.sheen_color_map).alpha, IGNORED)
    assert_equal(physical.iridescence, 0.5)
    assert_almost_equal(Float64(physical.iridescence_ior), 1.8, atol=TOLERANCE)
    assert_almost_equal(
        Float64(physical.iridescence_thickness_minimum.to(NANOMETER)),
        50,
        atol=1e-3,
    )
    assert_almost_equal(
        Float64(physical.iridescence_thickness_maximum.to(NANOMETER)),
        700,
        atol=1e-3,
    )
    assert_true(physical.iridescence_map != NO_TEXTURE)
    assert_true(physical.iridescence_thickness_map != NO_TEXTURE)
    assert_equal(physical.dispersion, 0.25)
    assert_equal(physical.attenuation_color.hex(), Color(250, 200, 150).hex())
    assert_equal(physical.attenuation_distance.to(METER), 2)
    assert_equal(physical.thickness.to(METER), 0.5)
    assert_true(physical.thickness_map != NO_TEXTURE)
    var standard = materials.get(meshes[1].material)
    assert_equal(standard.ao_map_intensity, 0.5)
    assert_equal(standard.light_map_intensity, 2)
    assert_true(standard.flat_shading)
    assert_equal(standard.displacement_scale.to(METER), 0.25)
    assert_almost_equal(
        Float64(standard.displacement_bias.to(METER)), 0.1, atol=TOLERANCE
    )
    # The texture's second set of coordinates travels as its `channel`.
    assert_equal(read[1].textures.get(standard.ao_map).channel, UV_CHANNEL_1)
    assert_equal(standard.ao_map, standard.light_map)
    var shiny = materials.get(meshes[2].material)
    assert_true(shiny.specular_map != NO_TEXTURE)
    assert_true(shiny.polygon_offset)
    assert_equal(shiny.polygon_offset_factor, 1)
    assert_equal(shiny.polygon_offset_units, 2)
    # An infinite attenuation distance is left out, as three.js leaves it.
    var plain = Assets()
    var holder = Scene()
    plain_mesh(plain, holder, Material(WHITE, kind=PHYSICAL))
    var text = object_to_json(holder, plain)
    assert_equal(text.find("attenuationDistance"), -1)
    assert_true(text.find('"iridescenceThicknessRange":[') >= 0)
    var again = _read(text)
    assert_equal(
        again[1].materials.get(MaterialId(0)).attenuation_distance.to(METER),
        inf[DType.float32](),
    )


def plain_mesh(mut assets: Assets, mut scene: Scene, material: Material) raises:
    """Add a mesh of one cube and a material to a scene."""
    scene.add_mesh(
        Mesh(
            assets.geometries.add(_cube(1)),
            assets.materials.add(material),
            scene.add(Object3D()),
        )
    )


def test_depth_stencil_and_packing_use_three_js_numbers() raises:
    """The depth, stencil and packing state is written with three.js's
    constants and read back."""
    var assets = Assets()
    var scene = Scene()
    var masked = Material(WHITE, kind=BASIC)
    masked.depth_func = GREATER_DEPTH
    masked.depth_test = False
    masked.depth_write = False
    masked.color_write = False
    masked.stencil_write = True
    masked.stencil_write_mask = 15
    masked.stencil_func = EQUAL_STENCIL_FUNC
    masked.stencil_ref = 3
    masked.stencil_func_mask = 7
    masked.stencil_fail = REPLACE_STENCIL_OP
    masked.stencil_z_fail = INVERT_STENCIL_OP
    masked.stencil_z_pass = ZERO_STENCIL_OP
    plain_mesh(assets, scene, masked)
    plain_mesh(
        assets,
        scene,
        Material(WHITE, kind=DEPTH, depth_packing=RGBA_DEPTH_PACKING),
    )
    var text = object_to_json(scene, assets)
    assert_true(text.find('"depthFunc":6') >= 0)
    assert_true(text.find('"stencilFunc":514') >= 0)
    assert_true(text.find('"stencilFail":7681') >= 0)
    assert_true(text.find('"stencilZFail":5386') >= 0)
    assert_true(text.find('"stencilZPass":0') >= 0)
    assert_true(text.find('"depthPacking":3201') >= 0)
    var read = _read(text)
    var again = read[1].materials.get(MaterialId(0))
    assert_equal(again.depth_func, GREATER_DEPTH)
    assert_false(again.depth_test)
    assert_false(again.depth_write)
    assert_false(again.color_write)
    assert_true(again.stencil_write)
    assert_equal(again.stencil_write_mask, 15)
    assert_equal(again.stencil_func, EQUAL_STENCIL_FUNC)
    assert_equal(again.stencil_ref, 3)
    assert_equal(again.stencil_func_mask, 7)
    assert_equal(again.stencil_fail, REPLACE_STENCIL_OP)
    assert_equal(again.stencil_z_fail, INVERT_STENCIL_OP)
    assert_equal(again.stencil_z_pass, ZERO_STENCIL_OP)
    assert_equal(
        read[1].materials.get(MaterialId(1)).depth_packing, RGBA_DEPTH_PACKING
    )


def test_three_js_defaults_are_read() raises:
    """A class without its keys is read with three.js's defaults."""
    var physical = _material('"type":"MeshPhysicalMaterial"')
    assert_equal(physical.sheen, 0)
    assert_equal(physical.sheen_roughness, 1)
    assert_equal(physical.sheen_color.hex(), 0)
    assert_almost_equal(Float64(physical.iridescence_ior), 1.3, atol=TOLERANCE)
    assert_equal(physical.iridescence_thickness_minimum.to(NANOMETER), 100)
    assert_equal(physical.attenuation_color.hex(), 0xFFFFFF)
    assert_equal(physical.depth_func, Material(WHITE).depth_func)
    assert_true(physical.depth_test)
    assert_equal(physical.stencil_write_mask, 255)
    var dashed = _material('"type":"LineDashedMaterial"')
    assert_equal(dashed.kind, BASIC)
    assert_equal(dashed.dash_size.to(METER), 3)
    assert_equal(dashed.gap_size.to(METER), 1)
    assert_equal(dashed.dash_scale, 1)
    var line = _material('"type":"LineBasicMaterial","linewidth":2')
    assert_equal(line.line_width, LineWidth(pixels=2))
    assert_false(line.is_dashed())
    var points = _material('"type":"PointsMaterial"')
    assert_equal(points.point_size.pixels, 1)
    assert_true(points.size_attenuation)
    # A `SpriteMaterial` is built transparent in three.js.
    var sprite = _material(
        '"type":"SpriteMaterial","rotation":0.5,"sizeAttenuation":false'
    )
    assert_true(sprite.transparent)
    assert_equal(sprite.rotation.to(RADIAN), 0.5)
    assert_false(sprite.size_attenuation)
    assert_false(
        _material('"type":"SpriteMaterial","transparent":false').transparent
    )
    # A map's numbers are read only beside it, where three.js writes them.
    var lone = _material(
        '"type":"MeshStandardMaterial","aoMapIntensity":3,'
        '"lightMapIntensity":3,"displacementScale":3'
    )
    assert_equal(lone.ao_map_intensity, 1)
    assert_equal(lone.light_map_intensity, 1)
    assert_equal(lone.displacement_scale.to(METER), 1)


def test_line_points_and_sprite_classes() raises:
    """Each line mode is its three.js class, and a material is written
    once for each class that uses it."""
    var assets = Assets()
    var scene = Scene()
    var strip = assets.geometries.add(_strip())
    var shared = assets.materials.add(
        Material(Color(10, 20, 30), kind=BASIC, line_width=LineWidth(pixels=2))
    )
    var modes = [STRIP, LOOP, SEGMENTS]
    for at in range(3):
        scene.add_line(
            Line(
                strip,
                shared,
                scene.add(Object3D()),
                mode=modes[at],
                frustum_culled=at != 1,
            )
        )
    scene.add_mesh(Mesh(strip, shared, scene.add(Object3D())))
    var opaque = assets.materials.add(
        sprite_material(transparent=False, size_attenuation=False)
    )
    scene.add_sprite(Sprite(opaque, scene.add(Object3D())))
    scene.add_points(
        Points(
            strip,
            assets.materials.add(
                points_material(WHITE, PointSize(4), size_attenuation=False)
            ),
            scene.add(Object3D()),
            frustum_culled=False,
        )
    )
    var text = object_to_json(scene, assets)
    for name in ["Line", "LineLoop", "LineSegments", "Points", "Sprite"]:
        assert_true(text.find('"type":"' + name + '"') >= 0)
    assert_true(text.find('"linewidth":2') >= 0)
    assert_true(text.find('"transparent":false') >= 0)
    # One material a line and a mesh share is two entries.
    assert_true(text.find("LineBasicMaterial") >= 0)
    assert_true(text.find("MeshBasicMaterial") >= 0)
    assert_equal(text.find('"center"'), -1)
    var read = _read(text)
    ref again = read[0]
    assert_equal(read[1].materials.count(), 4)
    assert_equal(len(again.lines), 3)
    for at in range(3):
        assert_equal(again.lines[at].mode, modes[at])
    assert_false(again.lines[1].frustum_culled)
    assert_false(again.points[0].frustum_culled)
    var points = read[1].materials.get(again.points[0].material)
    assert_equal(points.point_size.pixels, 4)
    assert_false(points.size_attenuation)
    var sprite = read[1].materials.get(again.sprites[0].material)
    assert_false(sprite.transparent)
    assert_equal(again.sprites[0].center.x, 0.5)


def test_an_lod_round_trips_its_levels() raises:
    """An LOD's levels are child meshes it names by uuid, with their
    distance and hysteresis."""
    var assets = Assets()
    var scene = Scene()
    var cube = assets.geometries.add(_cube(1))
    var material = assets.materials.add(Material(WHITE))
    var node = scene.add(Object3D())
    var lod = Lod(node, frustum_culled=False)
    lod.add_level(cube, material)
    lod.add_level(cube, material, Length(20, METER), 0.5)
    scene.add_lod(lod^)
    # A second LOD on the same node is a part, its levels its children.
    var other = Lod(node)
    other.add_level(cube, material, Length(5, METER))
    scene.add_lod(other^)
    _ = scene.attach(Object3D(), node)
    # An LOD with no levels is written with none.
    scene.add_lod(Lod(scene.add(Object3D())))
    var text = object_to_json(scene, assets)
    assert_true(text.find('"levels":[]') >= 0)
    assert_true(text.find('"type":"LOD"') >= 0)
    assert_true(text.find('"hysteresis":0.5') >= 0)
    var read = _read(text)
    ref again = read[0]
    assert_equal(len(again.lods), 3)
    assert_equal(again.lods[2].count(), 0)
    var levels = again.lods[0].levels.copy()
    assert_equal(len(levels), 2)
    assert_equal(levels[1].distance.to(METER), 20)
    assert_equal(levels[1].hysteresis, 0.5)
    assert_false(again.lods[0].frustum_culled)
    assert_equal(again.lods[1].levels[0].distance.to(METER), 5)
    # The levels are not nodes: the node, its child and its two parts,
    # and the empty LOD's node.
    assert_equal(again.count(), 5)
    assert_equal(len(again.meshes), 0)


def test_an_lod_as_three_js_writes_it() raises:
    """A level at a negative distance is read at its size, as three.js's
    `addLevel` takes it, and an LOD with no levels is empty."""
    var library = (
        '"geometries":[{"uuid":"g","type":"BoxGeometry"}],'
        '"materials":[{"uuid":"m","type":"MeshBasicMaterial"}],'
    )
    var read = _read(
        _wrap(
            library
            + '"object":{"uuid":"o","type":"LOD","levels":[{"object":"a",'
            '"distance":-4}],"children":[{"uuid":"a","type":"Mesh",'
            '"geometry":"g","material":"m","children":[]},'
            '{"uuid":"b","type":"Group"}]}'
        )
    )
    assert_equal(read[0].lods[0].levels[0].distance.to(METER), 4)
    assert_equal(read[0].lods[0].levels[0].hysteresis, 0)
    assert_equal(read[0].count(), 2)
    var empty = _read(_wrap('"object":{"uuid":"o","type":"LOD"}'))
    assert_equal(empty[0].lods[0].count(), 0)
    var none = _read(_wrap('"object":{"uuid":"o","type":"LOD","levels":[]}'))
    assert_equal(none[0].lods[0].count(), 0)
    _refuses(
        library
        + '"object":{"uuid":"o","type":"LOD","levels":[{"object":"a"}],'
        '"children":[]}',
        "names no child",
    )
    _refuses('"object":{"uuid":"o","type":"Audio"}', "not read: Audio")
    _refuses(
        library
        + '"object":{"uuid":"o","type":"LOD","levels":[{"object":"a"}]}',
        "names no child",
    )
    _refuses(
        library
        + '"object":{"uuid":"o","type":"LOD","levels":[{"object":"a"}],'
        '"children":[{"uuid":"b","type":"Group"}]}',
        "names no child",
    )
    _refuses(
        library
        + '"object":{"uuid":"o","type":"LOD","levels":[{"object":"a"}],'
        '"children":[{"uuid":"a","type":"Group"}]}',
        "a mesh at the",
    )
    _refuses(
        library
        + '"object":{"uuid":"o","type":"LOD","levels":[{"object":"a"}],'
        '"children":[{"uuid":"a","type":"Mesh","geometry":"g",'
        '"material":"m","position":[1,0,0]}]}',
        "a mesh at the",
    )
    _refuses(
        library
        + '"object":{"uuid":"o","type":"LOD","levels":[{"object":"a"}],'
        '"children":[{"uuid":"a","type":"Mesh","geometry":"g",'
        '"material":"m","children":[{"uuid":"c","type":"Group"}]}]}',
        "a mesh at the",
    )
    _refuses(
        library
        + '"object":{"uuid":"o","type":"LOD","levels":[{"object":"a"},'
        '{"object":"a"}],"children":[{"uuid":"a","type":"Mesh",'
        '"geometry":"g","material":"m"}]}',
        "named twice",
    )
    _refuses(
        library
        + '"object":{"uuid":"o","type":"LOD","levels":[{"object":"a"}],'
        '"children":[3,{"uuid":"a","type":"Mesh","geometry":"g",'
        '"material":"m"}]}',
        "must be an object",
    )


def test_a_batch_round_trips_as_three_js_writes_it() raises:
    """A batch is one joined geometry, its info entries and its data
    textures, and reads back to the same instances."""
    var assets = Assets()
    var scene = _scene(assets)
    var text = object_to_json(scene, assets)
    for key in [
        "geometryInfo",
        "instanceInfo",
        "matricesTexture",
        "indirectTexture",
        "colorsTexture",
        '"type":"Float32Array"',
        '"type":"Uint32Array"',
        '"maxInstanceCount":3',
    ]:
        assert_true(text.find(key) >= 0)
    var read = _read(text)
    ref batch = read[0].batched_meshes[0]
    ref original = scene.batched_meshes[0]
    assert_equal(batch.count(), 3)
    assert_true(batch.frustum_culled)
    for at in range(3):
        assert_equal(batch.color_at(at).hex(), original.color_at(at).hex())
        for element in range(16):
            assert_equal(
                batch.matrix_at(at).elements[element],
                original.matrix_at(at).elements[element],
            )
    var small_id = batch.geometry_at(0)
    var cube_id = batch.geometry_at(1)
    assert_equal(small_id, batch.geometry_at(2))
    assert_equal(read[1].geometries.get(small_id).vertex_count(), 24)
    ref cube = read[1].geometries.get(cube_id)
    assert_equal(len(cube.index), 36)
    for at in range(len(cube.index)):
        assert_equal(
            cube.index[at], assets.geometries.get(GeometryId(0)).index[at]
        )


def test_a_batch_without_an_index_or_a_tint_or_instances() raises:
    """A batch of unindexed geometry writes no index and no colors, and an
    empty batch reads back empty."""
    var assets = Assets()
    var scene = Scene()
    var strip = assets.geometries.add(_strip())
    var material = assets.materials.add(Material(WHITE))
    var batch = BatchedMesh(
        material, scene.add(Object3D()), frustum_culled=False
    )
    _ = batch.add_instance(strip)
    _ = batch.add_instance(strip, translation(0, 2, 0))
    scene.add_batched_mesh(batch^)
    scene.add_batched_mesh(BatchedMesh(material, scene.add(Object3D())))
    var text = object_to_json(scene, assets)
    assert_equal(text.find("colorsTexture"), -1)
    assert_true(text.find('"indexStart":-1') >= 0)
    var read = _read(text)
    ref again = read[0].batched_meshes[0]
    assert_equal(again.count(), 2)
    assert_false(again.frustum_culled)
    assert_equal(again.matrix_at(1).elements[13], 2)
    var strip_id = again.geometry_at(1)
    assert_false(read[1].geometries.get(strip_id).is_indexed())
    assert_equal(read[0].batched_meshes[1].count(), 0)


comptime BATCH_LIBRARY = (
    '"geometries":[{"uuid":"g","type":"BufferGeometry","data":{"attributes":'
    '{"position":{"itemSize":3,"type":"Float32Array","array":[0,0,0,1,0,0,'
    '0,1,0,0,0,1],"normalized":false}},"index":{"type":"Uint16Array",'
    '"array":[0,1,2,1,2,3]}}}],'
    '"materials":[{"uuid":"m","type":"MeshBasicMaterial"}],'
    '"textures":[{"uuid":"t","image":"i"},{"uuid":"c","image":"j"},'
    '{"uuid":"s","image":"k"},{"uuid":"u","image":"l"},'
    '{"uuid":"n","image":"q"},{"uuid":"p","image":"x"}],'
    '"images":[{"uuid":"i","url":{"type":"Float32Array","width":4,'
    '"height":4,"data":[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1,'
    "1,0,0,0,0,1,0,0,0,0,1,0,5,0,0,1,1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]}},"
    '{"uuid":"j","url":{"type":"Float32Array","data":[1,0,0,1,0,1,0,1,'
    "0,0,1,1]}},"
    '{"uuid":"k","url":{"type":"Float32Array","data":[1]}},'
    '{"uuid":"l","url":{"type":"Uint32Array","data":[1]}},'
    '{"uuid":"q","url":{"type":"Float32Array"}},'
    '{"uuid":"x","url":"a.png"}],'
)


def _batch(fields: String) -> String:
    """Return a batch document with extra object fields."""
    return (
        BATCH_LIBRARY
        + '"object":{"uuid":"o","type":"BatchedMesh","geometry":"g",'
        '"material":"m"'
        + fields
        + "}"
    )


comptime TWO_INFOS = (
    ',"geometryInfo":[{"vertexStart":0,"vertexCount":3,"indexStart":0,'
    '"indexCount":3},{"vertexStart":1,"vertexCount":3,"indexStart":3,'
    '"indexCount":3,"active":false}]'
)


def test_a_batch_as_three_js_writes_it() raises:
    """Inactive and hidden instances are left out, and the colors are
    read from their linear floats."""
    var read = _read(
        _wrap(
            _batch(
                TWO_INFOS
                + ',"instanceInfo":[{"geometryIndex":0},'
                '{"geometryIndex":0,"visible":false},{"active":false}],'
                '"matricesTexture":{"uuid":"t"},"colorsTexture":{"uuid":"c"}'
            )
        )
    )
    ref batch = read[0].batched_meshes[0]
    assert_equal(batch.count(), 1)
    assert_equal(batch.color_at(0).hex(), 0xFF0000)
    var part = batch.geometry_at(0)
    assert_equal(read[1].geometries.get(part).index[2], 2)
    # A geometry of no triangles is read with no index.
    var hollow = _read(
        _wrap(
            _batch(
                ',"geometryInfo":[{"vertexCount":3,"indexCount":0}],'
                '"instanceInfo":[{"geometryIndex":0}],'
                '"matricesTexture":{"uuid":"t"}'
            )
        )
    )
    var nothing = hollow[0].batched_meshes[0].geometry_at(0)
    assert_false(hollow[1].geometries.get(nothing).is_indexed())
    _refuses(_batch(""), "geometryInfo and")
    _refuses(_batch(TWO_INFOS), "geometryInfo and")
    _refuses(_batch(',"instanceInfo":[]'), "geometryInfo and")
    var one = TWO_INFOS + ',"instanceInfo":[{"geometryIndex":0}]'
    _refuses(_batch(one), "must hold every")
    _refuses(_batch(one + ',"matricesTexture":{"uuid":"s"}'), "must hold every")
    _refuses(
        _batch(
            TWO_INFOS
            + ',"instanceInfo":[{"geometryIndex":0},{"geometryIndex":0},'
            '{"geometryIndex":0},'
            '{"geometryIndex":0}],"matricesTexture":{"uuid":"t"},'
            '"colorsTexture":{"uuid":"c"}'
        ),
        "must hold every",
    )
    _refuses(
        _batch(
            TWO_INFOS
            + ',"instanceInfo":[{"geometryIndex":0},{"geometryIndex":0}],'
            '"matricesTexture":{"uuid":"t"},"colorsTexture":{"uuid":"s"}'
        ),
        "colorsTexture must hold",
    )
    var shown = ',"matricesTexture":{"uuid":"t"}'
    _refuses(
        _batch(TWO_INFOS + ',"instanceInfo":[{}]' + shown), "names no geometry"
    )
    _refuses(
        _batch(TWO_INFOS + ',"instanceInfo":[{"geometryIndex":2}]' + shown),
        "names no geometry",
    )
    _refuses(
        _batch(TWO_INFOS + ',"instanceInfo":[{"geometryIndex":1}]' + shown),
        "no active geometry",
    )
    var instance = ',"instanceInfo":[{"geometryIndex":0}]' + shown
    for info in [
        '{"vertexStart":-1,"vertexCount":3}',
        '{"vertexStart":0,"vertexCount":-1}',
        '{"vertexStart":2,"vertexCount":3}',
    ]:
        _refuses(
            _batch(',"geometryInfo":[' + info + "]" + instance),
            "outside the joined geometry",
        )
    for info in [
        '{"vertexCount":3,"indexStart":-1,"indexCount":3}',
        '{"vertexCount":3,"indexStart":0,"indexCount":-1}',
        '{"vertexCount":3,"indexStart":4,"indexCount":3}',
    ]:
        _refuses(
            _batch(',"geometryInfo":[' + info + "]" + instance),
            "outside the joined index",
        )
    for info in [
        '{"vertexStart":1,"vertexCount":3,"indexStart":0,"indexCount":3}',
        '{"vertexStart":0,"vertexCount":2,"indexStart":0,"indexCount":3}',
    ]:
        _refuses(
            _batch(',"geometryInfo":[' + info + "]" + instance),
            "outside its geometry",
        )
    var infos = TWO_INFOS + ',"instanceInfo":[]'
    _refuses(_batch(infos + ',"matricesTexture":{"uuid":"z"}'), "no texture")
    _refuses(
        String(BATCH_LIBRARY).replace(
            '{"uuid":"t","image":"i"}', '{"uuid":"t"}'
        )
        + '"object":{"uuid":"o","type":"BatchedMesh","geometry":"g",'
        '"material":"m"'
        + infos
        + ',"matricesTexture":{"uuid":"t"}}',
        "names no image",
    )
    _refuses(_batch(infos + ',"matricesTexture":{"uuid":"u"}'), "Float32Array")
    _refuses(_batch(infos + ',"matricesTexture":{"uuid":"n"}'), "has no data")
    _refuses(_batch(infos + ',"matricesTexture":{"uuid":"p"}'), "an object")
    _refuses(
        String(BATCH_LIBRARY).replace(
            '{"uuid":"j","url":', '{"uuid":"j","src":'
        )
        + '"object":{"uuid":"o","type":"BatchedMesh","geometry":"g",'
        '"material":"m"'
        + infos
        + ',"matricesTexture":{"uuid":"c"}}',
        "Float32Array",
    )


def test_the_writer_refuses_a_batch_three_js_cannot_join() raises:
    """A batch's geometries must share their attributes and index, and
    carry no morph targets."""
    var assets = Assets()
    var cube = assets.geometries.add(_cube(1))
    var bare = assets.geometries.add(
        box(Length(1, METER), Length(1, METER), Length(1, METER))
    )
    var strip = assets.geometries.add(_strip())
    var flat = _strip()
    flat.set_attribute(UV, BufferAttribute([0, 0, 1, 0, 0, 1, 1, 1], 2))
    var flat_id = assets.geometries.add(flat^)
    var wide = _strip()
    wide.set_attribute(
        UV, BufferAttribute([0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 1, 0], 3)
    )
    var wide_id = assets.geometries.add(wide^)
    var morphed = _strip()
    morphed.add_morph_target(morphed.clone_attribute(POSITION))
    var morphed_id = assets.geometries.add(morphed^)
    var instanced = BufferGeometry(instanced=True)
    instanced.set_attribute(
        POSITION, BufferAttribute([0, 0, 0, 1, 0, 0, 0, 1, 0], 3)
    )
    var instanced_id = assets.geometries.add(instanced^)
    var holey = _strip()
    holey.set_attribute(
        NORMAL, BufferAttribute([0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1], 3)
    )
    var holey_id = assets.geometries.add(holey^)
    var material = assets.materials.add(Material(WHITE))
    var pairs = [
        (cube, bare),
        (cube, strip),
        (strip, morphed_id),
        (strip, instanced_id),
        (flat_id, wide_id),
        (flat_id, holey_id),
    ]
    for at in range(len(pairs)):
        var scene = Scene()
        var batch = BatchedMesh(material, scene.add(Object3D()))
        _ = batch.add_instance(pairs[at][0])
        _ = batch.add_instance(pairs[at][1])
        scene.add_batched_mesh(batch^)
        with assert_raises(contains="Object JSON: a batch's"):
            _ = object_to_json(scene, assets)


def test_a_skinned_mesh_round_trips_its_skeleton() raises:
    """A skinned mesh names a skeleton of its bones' uuids and inverse
    binds, and a bone that carries nothing is a `Bone`."""
    var assets = Assets()
    var scene = Scene()
    var holder = scene.add(Object3D())
    var bone = scene.attach(Object3D(), holder)
    var other = scene.attach(Object3D(), holder)
    scene.node(other).set_position(1, 0, 0)
    scene.update()
    var skeleton = bind_skeleton(
        [bone, other], [scene.world_matrix(bone), scene.world_matrix(other)]
    )
    var material = assets.materials.add(Material(WHITE))
    scene.add_skinned_mesh(
        SkinnedMesh(
            assets.geometries.add(_skinned_triangle()),
            material,
            holder,
            skeleton^,
            translation(0, 0, 1),
            bind_mode=DETACHED,
            frustum_culled=True,
        )
    )
    # A bone that carries a mesh is written as that mesh.
    scene.add_mesh(Mesh(assets.geometries.add(_cube(1)), material, other))
    var text = object_to_json(scene, assets)
    assert_true(text.find('"type":"Bone"') >= 0)
    assert_true(text.find('"skeletons"') >= 0)
    assert_true(text.find('"bindMode":"detached"') >= 0)
    var read = _read(text)
    var second_bone = read[2].node(object_uuid(2, 2))
    ref mesh = read[0].skinned_meshes[0]
    assert_equal(mesh.bind_mode, DETACHED)
    assert_true(mesh.frustum_culled)
    assert_equal(mesh.bind_matrix.elements[14], 1)
    assert_equal(mesh.bone_count(), 2)
    assert_equal(mesh.skeleton.node(1), second_bone)
    assert_equal(mesh.skeleton.bones[1].inverse_bind.elements[12], -1)


comptime SKIN_LIBRARY = (
    '"geometries":[{"uuid":"g","type":"BoxGeometry"}],'
    '"materials":[{"uuid":"m","type":"MeshBasicMaterial"}],'
)


def _skin(skeletons: String, fields: String = "") -> String:
    """Return a skinned mesh document with a skeletons library."""
    return (
        SKIN_LIBRARY
        + '"skeletons":['
        + skeletons
        + '],"object":{"uuid":"o","type":"SkinnedMesh","geometry":"g",'
        '"material":"m","skeleton":"s"'
        + fields
        + ',"children":[{"uuid":"b","type":"Bone"}]}'
    )


def test_a_skinned_mesh_as_three_js_writes_it() raises:
    """Its bones can come after it, its bind defaults are three.js's, and
    a skeleton this cannot bind is refused."""
    var bone = '{"uuid":"s","bones":["b"],"boneInverses":[[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]]}'
    var read = _read(_wrap(_skin(bone)))
    ref mesh = read[0].skinned_meshes[0]
    assert_equal(mesh.bind_mode, ATTACHED)
    assert_true(mesh.frustum_culled)
    assert_equal(mesh.skeleton.node(0).value, 1)
    _refuses(
        _skin(bone).replace('"skeleton":"s"', '"skeleton":"t"'),
        "names no skeleton",
    )
    _refuses(_skin('{"uuid":"s","bones":["b"]}'), "one of boneInverses")
    _refuses(_skin('{"uuid":"s","boneInverses":[]}'), "one of boneInverses")
    _refuses(
        _skin('{"uuid":"s","bones":["b"],"boneInverses":[]}'),
        "one of boneInverses",
    )
    _refuses(
        _skin('{"uuid":"s","bones":["b"],"boneInverses":[3]}'),
        "must be an array",
    )
    _refuses(
        _skin('{"uuid":"s","bones":["b"],"boneInverses":[[1,0]]}'),
        "16 numbers",
    )
    _refuses(_skin(bone.replace('["b"]', '["z"]')), "no object has the uuid")
    _refuses(_skin(bone, ',"bindMode":"loose"'), "no bind mode")
    _refuses(
        _skin('{"uuid":"s","bones":[],"boneInverses":[]}'), "at least one bone"
    )


def test_the_writer_refuses_what_three_js_has_no_form_for() raises:
    """A lit line material, a width in world units, a mode or bind mode
    that is none of its values, and open fields their checks refuse."""
    var assets = Assets()
    var strip = assets.geometries.add(_strip())
    var lit = assets.materials.add(Material(WHITE, kind=LAMBERT))
    var world = assets.materials.add(
        Material(
            WHITE, kind=BASIC, line_width=LineWidth(world=Length(1, METER))
        )
    )
    var plain = assets.materials.add(Material(WHITE, kind=BASIC))
    var scene = Scene()
    scene.add_line(Line(strip, lit, scene.add(Object3D())))
    with assert_raises(contains="must be basic"):
        _ = object_to_json(scene, assets)
    scene.lines[0].material = world
    with assert_raises(contains="world units"):
        _ = object_to_json(scene, assets)
    scene.lines[0].material = plain
    scene.lines[0].mode = LineMode(7)
    with assert_raises(contains="line mode"):
        _ = object_to_json(scene, assets)
    var rigged = Scene()
    var node = rigged.add(Object3D())
    rigged.update()
    var mesh = SkinnedMesh(
        strip, plain, node, bind_skeleton([node], [rigged.world_matrix(node)])
    )
    mesh.bind_mode = BindMode(5)
    rigged.add_skinned_mesh(mesh^)
    with assert_raises(contains="bind mode"):
        _ = object_to_json(rigged, assets)
    var stenciled = Material(WHITE)
    stenciled.stencil_fail = StencilOp(9)
    var holder = Scene()
    plain_mesh(assets, holder, stenciled)
    with assert_raises():
        _ = object_to_json(holder, assets)
    var moved = Material(WHITE, kind=STANDARD)
    moved.displacement_scale = Length(2, METER)
    var other = Scene()
    plain_mesh(assets, other, moved)
    with assert_raises(contains="displacement"):
        _ = object_to_json(other, assets)


def test_the_reader_refuses_a_state_it_cannot_hold() raises:
    """A depth function, stencil operation or depth packing that is none
    of three.js's is refused."""
    var materials = [
        '"type":"MeshBasicMaterial","depthFunc":9',
        '"type":"MeshBasicMaterial","stencilFunc":520',
        '"type":"MeshBasicMaterial","stencilFail":1',
        '"type":"MeshBasicMaterial","stencilZFail":1',
        '"type":"MeshBasicMaterial","stencilZPass":1',
        '"type":"MeshDepthMaterial","depthPacking":3300',
        '"type":"MeshBasicMaterial","depthPacking":3201',
    ]
    for at in range(len(materials)):
        with assert_raises():
            _ = _material(materials[at])
    # A second set of coordinates is read; a third is not.
    var read = _read(_wrap(_textured(',"channel":1')))
    assert_equal(read[1].textures.get(TextureId(0)).channel, UV_CHANNEL_1)
    var scene = Scene()
    var assets = Assets()
    with assert_raises():
        _ = read_object_json(_wrap(_textured(',"channel":3')), scene, assets)


def _textured(texture: String) raises -> String:
    """Return a document whose one material's ao map is a texture with
    extra fields."""
    var pixels = List[UInt8](length=16, fill=255)
    var png = encode_png(Framebuffer(2, 2, pixels^))
    return (
        '"materials":[{"uuid":"m","type":"MeshStandardMaterial",'
        '"aoMap":"t"}],"textures":[{"uuid":"t","image":"i"'
        + texture
        + '}],"images":[{"uuid":"i","url":"data:image/png;base64,'
        + encode_base64(png)
        + '"}],"object":{"uuid":"o","type":"Group"}'
    )


def test_the_helpers() raises:
    """The constant tables map three.js's numbers and names both ways."""
    assert_equal(stencil_op_code(INVERT_STENCIL_OP), 5386)
    assert_equal(stencil_op_of(7681), REPLACE_STENCIL_OP)
    assert_equal(stencil_op_of(0), ZERO_STENCIL_OP)
    with assert_raises(contains="none of eight"):
        _ = stencil_op_of(2)
    with assert_raises(contains="none of eight"):
        _ = stencil_op_code(StencilOp(8))
    assert_equal(bind_mode_name(ATTACHED), "attached")
    assert_equal(bind_mode_name(DETACHED), "detached")
    assert_equal(bind_mode_of("detached"), DETACHED)
    with assert_raises(contains="neither"):
        _ = bind_mode_name(BindMode(2))
    assert_equal(line_type_names()[LOOP.value], "LineLoop")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
