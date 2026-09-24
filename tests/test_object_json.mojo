# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `exporters.object_json` and `loaders.object_loader`.

The key tests are the round trip -- a scene written as three.js JSON reads
back to the same nodes, geometry, materials, textures, lights and cameras
-- and a document shaped as three.js's own `scene.toJSON()` output. The
rest walks every choice the two make and every refusal.
"""

from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.background import (
    COLOR_BACKGROUND,
    TEXTURE_BACKGROUND,
    color_background,
    texture_background,
)
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    COLOR,
    NORMAL,
    POSITION,
    UV,
    BufferGeometry,
    MaterialIndex,
)
from core.fog import EXP2_FOG, LINEAR_FOG, exp2_fog, linear_fog
from core.geometry_store import GeometryId
from core.layers import Layers
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from exporters.object_json import (
    index_type,
    object_to_json,
    object_uuid,
    write_object_json,
)
from exporters.gltf import encode_base64
from geometries.box import box
from lights.light import (
    AMBIENT,
    DIRECTIONAL,
    HEMISPHERE,
    POINT,
    RECT_AREA,
    SPOT,
    ambient_light,
    directional_light,
    hemisphere_light,
    LIGHT_PROBE,
    light_probe,
    point_light,
    rect_area_light,
    spot_light,
)
from math.spherical_harmonics3 import SphericalHarmonics3
from loaders.json import parse_json
from loaders.object_loader import (
    ObjectCameras,
    ObjectModel,
    blending_of,
    color_space_of,
    decompose,
    euler_order_of,
    is_mipmap_filter,
    load_object_json,
    read_object_json,
    wrap_code,
    wrap_of,
)
from materials.material import (
    ADDITIVE,
    BASIC,
    BLEND,
    DEPTH,
    DISTANCE,
    DOUBLE_SIDE,
    LAMBERT,
    MATCAP,
    MIX_OPERATION,
    MULTIPLY,
    NORMALS,
    NO_TEXTURE,
    OPAQUE,
    PHONG,
    PHYSICAL,
    SHADOW,
    STANDARD,
    SUBTRACTIVE,
    TOON,
    Blending,
    Material,
    MaterialId,
    MaterialKind,
    custom_blending,
    distance_material,
)
from math.euler import XYZ, YXZ, ZYX
from math.matrix4 import Matrix4, translation
from math.quaternion import Quaternion
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.instanced_mesh import InstancedMesh
from objects.mesh import Mesh
from render.blend import ONE_FACTOR, ZERO_FACTOR
from render.framebuffer import Color, Framebuffer
from render.png import encode as encode_png
from render.srgb import LINEAR, SRGB
from render.texture import (
    BILINEAR,
    CLAMP,
    IGNORED,
    COVERAGE,
    MIRROR,
    NEAREST,
    REPEAT,
    Texture,
    Wrap,
)
from render.texture_store import TextureId
from std.math import pi
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, InverseLength, Length, METER, PER_METER
from units.si import MILLIMETER

comptime TOLERANCE = Float64(1e-5)
comptime WHITE = Color(255, 255, 255)


def _pixels() -> List[UInt8]:
    """Return a 2 by 2 image with four different texels."""
    return [
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
        128,
        255,
        255,
        0,
        255,
    ]


def _texture(
    wrap: Wrap = REPEAT, mipmapped: Bool = False, alpha: Bool = False
) raises -> Texture:
    """Return a small texture."""
    return Texture(
        2,
        2,
        _pixels(),
        wrap,
        NEAREST,
        LINEAR if alpha else SRGB,
        mipmapped,
        IGNORED if alpha else COVERAGE,
    )


def _triangle() raises -> BufferGeometry:
    """Return one triangle with normals, uvs and colors."""
    var geometry = BufferGeometry()
    geometry.set_attribute(
        POSITION, BufferAttribute([0, 0, 0, 1, 0, 0, 0, 1, 0], 3)
    )
    geometry.set_attribute(
        NORMAL, BufferAttribute([0, 0, 1, 0, 0, 1, 0, 0, 1], 3)
    )
    geometry.set_attribute(UV, BufferAttribute([0, 0, 1, 0, 0, 1], 2))
    geometry.set_attribute(
        COLOR, BufferAttribute([1, 0, 0, 0, 1, 0, 0, 0, 1], 3)
    )
    return geometry^


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


def _refuses(document: String) raises:
    """Assert that a wrapped document is refused."""
    var scene = Scene()
    var assets = Assets()
    with assert_raises():
        _ = read_object_json(_wrap(document), scene, assets)


comptime MESH_LIBRARY = (
    '"geometries":[{"uuid":"g","type":"BufferGeometry","data":{"attributes":'
    '{"position":{"itemSize":3,"type":"Float32Array","array":[0,0,0,1,0,0,'
    '0,1,0],"normalized":false}}}}],'
    '"materials":[{"uuid":"m","type":"MeshBasicMaterial","color":16711680}],'
)


def _mesh_object(extra: String) -> String:
    """Return a document of one mesh object with extra fields."""
    return (
        MESH_LIBRARY
        + '"object":{"uuid":"o","type":"Mesh","geometry":"g","material":"m"'
        + extra
        + "}"
    )


def _png_url() raises -> String:
    """Return the 2 by 2 image as a PNG data URL."""
    return "data:image/png;base64," + encode_base64(
        encode_png(Framebuffer(2, 2, _pixels()))
    )


def _textured(texture: String, material: String = "") raises -> String:
    """Return a document of one mesh whose basic material's map is a
    texture with extra fields."""
    var kind = material if material != "" else '"type":"MeshBasicMaterial"'
    return (
        '"geometries":[{"uuid":"g","type":"BoxGeometry"}],'
        + '"materials":[{"uuid":"m",'
        + kind
        + ',"map":"t"}],'
        + '"textures":[{"uuid":"t","image":"i"'
        + texture
        + "}],"
        + '"images":[{"uuid":"i","url":"'
        + _png_url()
        + '"}],'
        + '"object":{"uuid":"o","type":"Mesh","geometry":"g","material":"m"}'
    )


# --- the round trip ---------------------------------------------------------


def _scene(mut assets: Assets) raises -> Tuple[Scene, ObjectCameras]:
    """Build a scene that holds one of nearly everything."""
    var scene = Scene()
    var color_map = assets.textures.add(_texture(CLAMP, True))
    var data_map = assets.textures.add(_texture(MIRROR, False, True))
    var geometry = assets.geometries.add(_triangle())
    var indexed = box(Length(1, METER), Length(2, METER), Length(3, METER))
    indexed.clear_groups()
    indexed.add_group(0, 6, MaterialIndex(1))
    indexed.add_morph_target(
        indexed.clone_attribute(POSITION), indexed.clone_attribute(NORMAL)
    )
    indexed.morph_relative = True
    var boxed = assets.geometries.add(indexed^)

    var root = Object3D()
    root.name = "root"
    root.set_position(1, 2, 3)
    root.set_scale(2, 2, 2)
    root.set_euler(Angle(30, DEGREE), Angle(45, DEGREE), Angle(0, DEGREE))
    var top = scene.add(root)
    var hidden = Object3D()
    hidden.name = "hidden"
    hidden.visible = False
    hidden.render_order = 3
    hidden.layers = Layers(6)
    var hidden_id = scene.attach(hidden, top)
    var fixed = Object3D()
    fixed.matrix_auto_update = False
    fixed.matrix = translation(4, 5, 6)
    var fixed_id = scene.attach(fixed, hidden_id)

    var materials = List[Material]()
    materials.append(
        Material(
            Color(10, 20, 30),
            map=color_map,
            kind=STANDARD,
            roughness=0.5,
            metalness=0.25,
            roughness_map=data_map,
            metalness_map=data_map,
            normal_map=data_map,
            normal_scale=Vector2(2, 3),
            emissive=Color(1, 2, 3),
            emissive_intensity=2,
            emissive_map=data_map,
            env_map_intensity=0.5,
            side=DOUBLE_SIDE,
        )
    )
    materials.append(
        Material(
            WHITE,
            kind=PHONG,
            specular=Color(40, 50, 60),
            shininess=12,
            bump_map=data_map,
            bump_scale=0.5,
            reflectivity=0.5,
            combine=MIX_OPERATION,
            opacity=0.5,
            transparent=True,
        )
    )
    materials.append(
        Material(
            WHITE,
            kind=BASIC,
            vertex_colors=True,
            alpha_map=data_map,
            alpha_test=0.25,
            blending=ADDITIVE,
        )
    )
    materials.append(Material(WHITE, kind=BASIC, wireframe=True))
    materials.append(
        Material(
            WHITE,
            kind=PHYSICAL,
            ior=1.25,
            specular_color=Color(9, 8, 7),
            specular_intensity=0.5,
            clearcoat=0.75,
            clearcoat_roughness=0.125,
        )
    )
    materials.append(Material(WHITE, kind=TOON, gradient_map=data_map))
    materials.append(Material(WHITE, kind=MATCAP, matcap=data_map))
    materials.append(Material(WHITE, kind=NORMALS))
    materials.append(
        Material(WHITE, kind=DEPTH, blending=OPAQUE, transparent=True)
    )
    materials.append(
        Material(Color(0, 0, 0), kind=SHADOW, opacity=0.5, transparent=True)
    )
    materials.append(Material(WHITE, kind=LAMBERT, blending=SUBTRACTIVE))
    for at in range(len(materials)):
        var id = assets.materials.add(materials[at])
        var node = Object3D()
        node.name = "mesh" + String(at)
        var placed = scene.attach(node, top)
        scene.add_mesh(
            Mesh(
                boxed if at == 0 else geometry,
                id,
                placed,
                frustum_culled=at != 1,
                cast_shadow=at == 2,
                receive_shadow=at == 3,
            )
        )
    # One geometry and one material used twice are written once.
    scene.add_mesh(Mesh(geometry, MaterialId(1), fixed_id))
    var crowd = scene.attach(Object3D(), top)
    var instances = InstancedMesh(
        geometry, MaterialId(0), crowd, 2, frustum_culled=False
    )
    instances.set_matrix_at(1, translation(1, 0, 0))
    scene.add_instanced_mesh(instances^)

    var sun_node = scene.attach(Object3D(), top)
    var sun = directional_light(Color(255, 250, 240), sun_node, 2, fixed_id)
    sun.cast_shadow = True
    sun.shadow.bias = -0.001
    sun.shadow.normal_bias = 0.02
    sun.shadow.radius = 2
    sun.shadow.map_size = 1024
    sun.shadow.near = Length(1, METER)
    sun.shadow.far = Length(50, METER)
    sun.shadow.extent = Length(8, METER)
    scene.add_light(sun)
    scene.add_light(ambient_light(Color(20, 20, 20), 0.5))
    var red = point_light(
        Color(255, 0, 0), scene.attach(Object3D(), top), 3, 1, 9
    )
    red.cast_shadow = True
    red.shadow.map_size = 256
    red.shadow.bias = -0.005
    scene.add_light(red)
    scene.add_light(
        hemisphere_light(
            Color(0, 0, 255), Color(0, 255, 0), scene.attach(Object3D(), top)
        )
    )
    var cone = spot_light(
        WHITE,
        scene.attach(Object3D(), top),
        4,
        20,
        Angle(30, DEGREE),
        0.5,
        1,
    )
    cone.cast_shadow = True
    scene.add_light(cone)
    scene.add_light(
        rect_area_light(
            WHITE,
            scene.attach(Object3D(), top),
            1,
            Length(2, METER),
            Length(3, METER),
        )
    )
    var cameras = ObjectCameras()
    var eye = PerspectiveCamera(
        Angle(60, DEGREE), 1.5, Length(0.5, METER), Length(100, METER)
    )
    eye.attach(scene.attach(Object3D(), top))
    cameras.perspective.append(eye)
    var plan = OrthographicCamera(
        Length(-2, METER),
        Length(2, METER),
        Length(1, METER),
        Length(-1, METER),
        Length(0, METER),
        Length(10, METER),
    )
    plan.zoom = 2
    plan.attach(scene.attach(Object3D(), top))
    cameras.orthographic.append(plan^)
    scene.fog = linear_fog(Color(1, 2, 3), Length(2, METER), Length(30, METER))
    scene.background = color_background(Color(4, 5, 6))
    return (scene^, cameras^)


def _same_node(one: Object3D, two: Object3D) raises:
    """Assert two nodes match within rounding."""
    assert_equal(one.name, two.name)
    assert_equal(one.visible, two.visible)
    assert_equal(one.render_order, two.render_order)
    assert_equal(one.layers.mask, two.layers.mask)
    assert_equal(one.matrix_auto_update, two.matrix_auto_update)
    var a = one.local_matrix() if one.matrix_auto_update else one.matrix
    var b = two.local_matrix() if two.matrix_auto_update else two.matrix
    for index in range(16):
        assert_almost_equal(
            Float64(a.elements[index]),
            Float64(b.elements[index]),
            atol=TOLERANCE,
        )


def _same_material(one: Material, two: Material) raises:
    """Assert two materials match, textures aside."""
    assert_equal(one.kind, two.kind)
    assert_equal(one.color.hex(), two.color.hex())
    assert_equal(one.side, two.side)
    assert_equal(one.opacity, two.opacity)
    assert_equal(one.blending, two.blending)
    assert_equal(one.transparent, two.transparent)
    assert_equal(one.emissive.hex(), two.emissive.hex())
    assert_equal(one.emissive_intensity, two.emissive_intensity)
    assert_equal(one.vertex_colors, two.vertex_colors)
    assert_equal(one.alpha_test, two.alpha_test)
    assert_equal(one.specular.hex(), two.specular.hex())
    assert_equal(one.shininess, two.shininess)
    assert_equal(one.wireframe, two.wireframe)
    assert_equal(one.reflectivity, two.reflectivity)
    assert_equal(one.combine, two.combine)
    assert_equal(one.roughness, two.roughness)
    assert_equal(one.metalness, two.metalness)
    assert_equal(one.env_map_intensity, two.env_map_intensity)
    assert_equal(one.normal_scale.x, two.normal_scale.x)
    assert_equal(one.normal_scale.y, two.normal_scale.y)
    assert_equal(one.bump_scale, two.bump_scale)
    assert_equal(one.ior, two.ior)
    assert_equal(one.specular_color.hex(), two.specular_color.hex())
    assert_equal(one.specular_intensity, two.specular_intensity)
    assert_equal(one.clearcoat, two.clearcoat)
    assert_equal(one.clearcoat_roughness, two.clearcoat_roughness)
    assert_equal(one.map == NO_TEXTURE, two.map == NO_TEXTURE)
    assert_equal(one.normal_map == NO_TEXTURE, two.normal_map == NO_TEXTURE)
    assert_equal(one.bump_map == NO_TEXTURE, two.bump_map == NO_TEXTURE)
    assert_equal(one.alpha_map == NO_TEXTURE, two.alpha_map == NO_TEXTURE)
    assert_equal(one.matcap == NO_TEXTURE, two.matcap == NO_TEXTURE)
    assert_equal(one.gradient_map == NO_TEXTURE, two.gradient_map == NO_TEXTURE)


def test_round_trip() raises:
    """A scene written and read back has the same everything."""
    var assets = Assets()
    var built = _scene(assets)
    var text = object_to_json(built[0], assets, built[1])
    # The same scene writes the same text.
    assert_equal(text, object_to_json(built[0], assets, built[1]))
    var scene = Scene()
    var read = Assets()
    var model = read_object_json(text, scene, read)
    ref original = built[0]
    # Every node, and the ambient light's own node after them.
    assert_equal(scene.count(), original.count() + 1)
    for index in range(original.count()):
        var node = model.node(object_uuid(2, index))
        assert_equal(node.value, index)
        _same_node(original.get(NodeId(index)), scene.get(node))
        assert_equal(
            scene.get(node).parent.value,
            original.get(NodeId(index)).parent.value,
        )
    # The geometry and the material used twice are written once.
    assert_equal(read.geometries.count(), 2)
    assert_equal(read.materials.count(), assets.materials.count())
    assert_equal(len(scene.meshes), len(original.meshes))
    for at in range(len(original.meshes)):
        ref one = original.meshes[at]
        # Meshes are read in the order of the tree, so find it by node.
        var found = -1
        for other in range(len(scene.meshes)):
            if scene.meshes[other].node == one.node:
                found = other
        ref two = scene.meshes[found]
        assert_equal(one.frustum_culled, two.frustum_culled)
        assert_equal(one.cast_shadow, two.cast_shadow)
        assert_equal(one.receive_shadow, two.receive_shadow)
        _same_material(
            assets.materials.get(one.material),
            read.materials.get(two.material),
        )
        ref a = assets.geometries.get(one.geometry)
        ref b = read.geometries.get(two.geometry)
        assert_equal(a.attribute_count(), b.attribute_count())
        assert_equal(len(a.index), len(b.index))
        assert_equal(len(a.groups), len(b.groups))
        assert_equal(a.morph_count(), b.morph_count())
        assert_equal(a.morph_relative, b.morph_relative)
        assert_equal(a.has_morph_normals(), b.has_morph_normals())
        for slot in range(len(a.names)):
            assert_true(b.has_attribute(a.names[slot]))
            assert_equal(
                len(a.values[slot].data),
                len(b.attribute_view(a.names[slot]).data),
            )
    ref boxed = read.geometries.get(scene.meshes[1].geometry)
    assert_equal(boxed.groups[0].material_index.value, 1)
    assert_equal(boxed.groups[0].count, 6)
    # Textures come back once per alpha mode they are used with.
    ref first = read.materials.get(scene.meshes[1].material)
    ref color = read.textures.get(first.map)
    assert_equal(color.alpha, COVERAGE)
    assert_equal(color.color_space, SRGB)
    assert_equal(color.wrap_s, CLAMP)
    assert_equal(color.mag_filter, NEAREST)
    assert_true(color.levels > 1)
    for at in range(16):
        assert_equal(color.pixels[at], _pixels()[at])
    ref data = read.textures.get(first.normal_map)
    assert_equal(data.alpha, IGNORED)
    assert_equal(data.color_space, LINEAR)
    assert_equal(data.wrap_s, MIRROR)
    assert_equal(data.levels, 1)
    assert_equal(first.roughness_map, first.normal_map)
    assert_equal(read.textures.count(), 2)
    # The instanced mesh.
    assert_equal(len(scene.instanced_meshes), 1)
    ref crowd = scene.instanced_meshes[0]
    assert_equal(crowd.count(), 2)
    assert_false(crowd.frustum_culled)
    assert_equal(crowd.matrix_at(1).elements[12], 1)
    # The lights, the ambient one last on a node of its own.
    assert_equal(len(scene.lights), 6)
    ref sun = scene.lights[0]
    assert_equal(sun.kind, DIRECTIONAL)
    assert_equal(sun.intensity, 2)
    assert_equal(sun.color.hex(), Color(255, 250, 240).hex())
    assert_equal(sun.target.value, 2)
    assert_true(sun.cast_shadow)
    assert_almost_equal(Float64(sun.shadow.bias), -0.001, atol=TOLERANCE)
    assert_almost_equal(Float64(sun.shadow.normal_bias), 0.02, atol=TOLERANCE)
    assert_equal(sun.shadow.radius, 2)
    assert_equal(sun.shadow.map_size, 1024)
    assert_equal(sun.shadow.near.to(METER), 1)
    assert_equal(sun.shadow.far.to(METER), 50)
    assert_equal(sun.shadow.extent.to(METER), 8)
    ref bulb = scene.lights[1]
    assert_equal(bulb.kind, POINT)
    assert_equal(bulb.decay, 1)
    assert_equal(bulb.distance, 9)
    # A point light's shadow travels as the others' do.
    assert_true(bulb.cast_shadow)
    assert_equal(bulb.shadow.map_size, 256)
    assert_almost_equal(Float64(bulb.shadow.bias), -0.005, atol=TOLERANCE)
    ref sky = scene.lights[2]
    assert_equal(sky.kind, HEMISPHERE)
    assert_equal(sky.ground.hex(), 0x00FF00)
    ref cone = scene.lights[3]
    assert_equal(cone.kind, SPOT)
    assert_almost_equal(Float64(cone.angle.to(DEGREE)), 30, atol=TOLERANCE)
    assert_equal(cone.penumbra, 0.5)
    assert_equal(cone.distance, 20)
    assert_equal(cone.target, NO_PARENT)
    assert_true(cone.cast_shadow)
    ref panel = scene.lights[4]
    assert_equal(panel.kind, RECT_AREA)
    assert_equal(panel.width.to(METER), 2)
    assert_equal(panel.height.to(METER), 3)
    ref fill = scene.lights[5]
    assert_equal(fill.kind, AMBIENT)
    assert_equal(fill.intensity, 0.5)
    assert_equal(fill.node.value, original.count())
    # The cameras ride the same nodes.
    assert_equal(len(model.cameras.perspective), 1)
    ref eye = model.cameras.perspective[0]
    assert_equal(eye.node.value, built[1].perspective[0].node.value)
    assert_almost_equal(Float64(eye.fov.to(DEGREE)), 60, atol=TOLERANCE)
    assert_equal(eye.aspect, 1.5)
    assert_equal(eye.near.to(METER), 0.5)
    assert_equal(eye.far.to(METER), 100)
    ref plan = model.cameras.orthographic[0]
    assert_equal(plan.node.value, built[1].orthographic[0].node.value)
    assert_equal(plan.left.to(METER), -2)
    assert_equal(plan.top.to(METER), 1)
    assert_equal(plan.far.to(METER), 10)
    assert_equal(plan.zoom, 2)
    # The fog and the background.
    assert_equal(scene.fog.kind, LINEAR_FOG)
    assert_equal(scene.fog.far.to(METER), 30)
    assert_equal(scene.background.kind, COLOR_BACKGROUND)
    assert_equal(scene.background.color.hex(), Color(4, 5, 6).hex())


def test_write_and_load_a_file() raises:
    """`write_object_json` and `load_object_json` go through a file."""
    var assets = Assets()
    var scene = Scene()
    var node = scene.add(Object3D())
    var geometry = assets.geometries.add(_triangle())
    var material = assets.materials.add(Material(WHITE, kind=BASIC))
    scene.add_mesh(Mesh(geometry, material, node))
    var path = "/tmp/threemojo_object_json_test.json"
    write_object_json(path, scene, assets)
    var again = Scene()
    var read = Assets()
    var model = load_object_json(path, again, read)
    assert_equal(len(again.meshes), 1)
    assert_equal(model.node(object_uuid(2, 0)).value, 0)


def test_the_fog_switch_and_a_distance_material_round_trip() raises:
    """`fog: false` is written and read as three.js writes it, and a
    `MeshDistanceMaterial` is read as a `DISTANCE` material."""
    var assets = Assets()
    var scene = Scene()
    var node = scene.add(Object3D())
    var geometry = assets.geometries.add(_triangle())
    var kinds = [
        Material(WHITE, kind=BASIC, fog=False),
        Material(WHITE, kind=BASIC),
        distance_material(),
    ]
    for at in range(len(kinds)):
        scene.add_mesh(Mesh(geometry, assets.materials.add(kinds[at]), node))
    var text = object_to_json(scene, assets)
    assert_true(text.find('"fog":false') >= 0)
    assert_true(text.find("MeshDistanceMaterial") >= 0)
    var again = Scene()
    var read = Assets()
    _ = read_object_json(text, again, read)
    assert_false(read.materials.get(MaterialId(0)).fog)
    assert_true(read.materials.get(MaterialId(1)).fog)
    var measured = read.materials.get(MaterialId(2))
    assert_equal(measured.kind, DISTANCE)
    assert_false(measured.fog)
    # A data material has no `fog` in three.js, and none is read for one.
    assert_false(_material('"type":"MeshDepthMaterial","fog":true').fog)


def test_several_things_on_a_node_become_parts() raises:
    """A node that carries two things, or a light or a camera on other
    layers, writes each thing as a child at the identity."""
    var assets = Assets()
    var scene = Scene()
    var geometry = assets.geometries.add(_triangle())
    var material = assets.materials.add(Material(WHITE, kind=BASIC))
    var node = Object3D()
    node.set_position(1, 0, 0)
    var busy = scene.add(node)
    scene.add_mesh(Mesh(geometry, material, busy))
    scene.add_mesh(Mesh(geometry, material, busy))
    scene.add_instanced_mesh(InstancedMesh(geometry, material, busy, 1))
    scene.add_light(point_light(WHITE, busy))
    var lamp = point_light(WHITE, scene.add(Object3D()))
    lamp.layers = Layers(2)
    scene.add_light(lamp)
    var cameras = ObjectCameras()
    var eye = PerspectiveCamera(
        Angle(50, DEGREE), 1, Length(0.1, METER), Length(10, METER)
    )
    eye.attach(busy)
    cameras.perspective.append(eye)
    eye.attach(scene.add(Object3D()))
    eye.layers = Layers(4)
    cameras.perspective.append(eye)
    var plan = OrthographicCamera(
        Length(-1, METER),
        Length(1, METER),
        Length(1, METER),
        Length(-1, METER),
        Length(0, METER),
        Length(10, METER),
    )
    plan.attach(busy)
    cameras.orthographic.append(plan.copy())
    plan.attach(scene.add(Object3D()))
    plan.layers = Layers(8)
    cameras.orthographic.append(plan.copy())
    plan.attach(scene.add(Object3D()))
    plan.layers = Layers()
    cameras.orthographic.append(plan^)
    var text = object_to_json(scene, assets, cameras)
    assert_true(text.find(object_uuid(3, 0)) >= 0)
    var again = Scene()
    var read = Assets()
    var model = read_object_json(text, again, read)
    assert_equal(len(again.meshes), 2)
    assert_equal(len(again.instanced_meshes), 1)
    assert_equal(len(again.lights), 2)
    assert_equal(len(model.cameras.perspective), 2)
    assert_equal(len(model.cameras.orthographic), 3)
    # The parts sit under the busy node, at the identity.
    var first = again.meshes[0].node
    assert_equal(again.get(first).parent.value, 0)
    assert_equal(again.get(first).position.x, 0)
    assert_equal(again.lights[1].layers.mask, 2)
    assert_equal(model.cameras.perspective[1].layers.mask, 4)
    assert_equal(model.cameras.orthographic[1].layers.mask, 8)


def test_a_node_that_becomes_its_thing_keeps_its_children() raises:
    """A node written as its mesh, light or camera still writes its
    children, and odd geometry writes too."""
    var assets = Assets()
    var scene = Scene()
    var empty = assets.geometries.add(BufferGeometry())
    var morphed = _triangle()
    morphed.add_morph_target(morphed.clone_attribute(POSITION))
    var geometry = assets.geometries.add(morphed^)
    var material = assets.materials.add(Material(WHITE, kind=BASIC))
    var cameras = ObjectCameras()
    var eye = PerspectiveCamera(
        Angle(50, DEGREE), 1, Length(0.1, METER), Length(10, METER)
    )
    var plan = OrthographicCamera(
        Length(-1, METER),
        Length(1, METER),
        Length(1, METER),
        Length(-1, METER),
        Length(0, METER),
        Length(10, METER),
    )
    for kind in range(5):
        var node = scene.add(Object3D())
        _ = scene.attach(Object3D(), node)
        if kind == 0:
            scene.add_mesh(Mesh(empty, material, node))
        elif kind == 1:
            scene.add_instanced_mesh(InstancedMesh(geometry, material, node, 0))
        elif kind == 2:
            scene.add_light(point_light(WHITE, node))
        elif kind == 3:
            eye.attach(node)
            cameras.perspective.append(eye)
        else:
            plan.attach(node)
            cameras.orthographic.append(plan.copy())
    var again = Scene()
    var read = Assets()
    _ = read_object_json(object_to_json(scene, assets, cameras), again, read)
    assert_equal(again.count(), 10)
    assert_equal(read.geometries.get(GeometryId(1)).morph_count(), 1)
    assert_equal(read.geometries.get(GeometryId(0)).attribute_count(), 0)
    # A light on a node that is not in the scene is refused.
    scene.add_light(point_light(WHITE, NodeId(70)))
    with assert_raises(contains="not in the scene"):
        _ = object_to_json(scene, assets, cameras)


def test_background_texture_and_exp2_fog() raises:
    """A texture background and an exponential fog round trip."""
    var assets = Assets()
    var scene = Scene()
    scene.background = texture_background(assets.textures.add(_texture()))
    scene.fog = exp2_fog(Color(9, 9, 9), InverseLength(0.5, PER_METER))
    var again = Scene()
    var read = Assets()
    _ = read_object_json(object_to_json(scene, assets), again, read)
    assert_equal(again.background.kind, TEXTURE_BACKGROUND)
    assert_equal(read.textures.get(again.background.texture).alpha, COVERAGE)
    assert_equal(again.fog.kind, EXP2_FOG)
    assert_equal(again.fog.density.to(PER_METER), 0.5)
    assert_equal(again.fog.color.hex(), 0x090909)


def test_an_empty_scene() raises:
    """A scene with nothing writes a scene object and no libraries."""
    var scene = Scene()
    var assets = Assets()
    var text = object_to_json(scene, assets)
    assert_equal(text.find("geometries"), -1)
    var again = Scene()
    var read = Assets()
    var model = read_object_json(text, again, read)
    assert_equal(again.count(), 0)
    assert_equal(len(model.uuids), 0)
    with assert_raises(contains="no object has the uuid"):
        _ = model.node("x")


# --- the writer's refusals --------------------------------------------------


def _one_mesh(material: Material) raises -> Tuple[Scene, Assets]:
    """Return a scene of one mesh with a material."""
    var assets = Assets()
    var scene = Scene()
    var geometry = assets.geometries.add(_triangle())
    var id = assets.materials.add(material)
    scene.add_mesh(Mesh(geometry, id, scene.add(Object3D())))
    return (scene^, assets^)


def test_writer_refuses_what_has_no_three_js_form() raises:
    """The writer refuses blending three.js cannot say, a camera on no
    node, a view shift, a blank texture and a kind that is none of
    eleven."""
    var blended = _one_mesh(Material(WHITE, kind=BASIC, blending=BLEND))
    with assert_raises(contains="blends and is not transparent"):
        _ = object_to_json(blended[0], blended[1])
    var custom = _one_mesh(
        Material(
            WHITE, kind=BASIC, blending=custom_blending(ONE_FACTOR, ZERO_FACTOR)
        )
    )
    with assert_raises(contains="custom blending"):
        _ = object_to_json(custom[0], custom[1])
    var odd = Material(WHITE, kind=BASIC)
    odd.kind = MaterialKind(42)
    var bad = _one_mesh(odd)
    with assert_raises(contains="none of eleven"):
        _ = object_to_json(bad[0], bad[1])
    var blank = Material(WHITE, kind=BASIC)
    var holder = _one_mesh(blank)
    holder[1].materials.materials[0].map = holder[1].textures.add(Texture())
    with assert_raises(contains="blank texture"):
        _ = object_to_json(holder[0], holder[1])
    var scene = Scene()
    var assets = Assets()
    var cameras = ObjectCameras()
    cameras.perspective.append(
        PerspectiveCamera(
            Angle(50, DEGREE), 1, Length(0.1, METER), Length(10, METER)
        )
    )
    with assert_raises(contains="not in the scene"):
        _ = object_to_json(scene, assets, cameras)
    var stray = ObjectCameras()
    var shifted = PerspectiveCamera(
        Angle(50, DEGREE),
        1,
        Length(0.1, METER),
        Length(10, METER),
        Length(0.01, METER),
    )
    shifted.attach(scene.add(Object3D()))
    stray.perspective.append(shifted)
    with assert_raises(contains="view shift"):
        _ = object_to_json(scene, assets, stray)
    var negative = ObjectCameras()
    shifted.node = NodeId(-3)
    negative.perspective.append(shifted)
    with assert_raises(contains="not in the scene"):
        _ = object_to_json(scene, assets, negative)


def test_index_type_follows_the_vertex_count() raises:
    """An index is written as three.js chooses its array."""
    assert_equal(index_type(65535), "Uint16Array")
    assert_equal(index_type(65536), "Uint32Array")


def test_uuid_form() raises:
    """A uuid is in three.js's form and names its kind and position."""
    assert_equal(object_uuid(2, 17), "00000000-0000-4000-8000-200000000011")


# --- a document as three.js writes it --------------------------------------


comptime THREE_JS_SCENE = """{
  "metadata": {"version": 4.6, "type": "Object", "generator": "Object3D.toJSON"},
  "geometries": [
    {"uuid": "6e3d2a4c-7f1b-4a1e-9b1d-2c3f4e5a6b7c", "type": "BoxGeometry",
     "width": 2, "height": 1, "depth": 1,
     "widthSegments": 1, "heightSegments": 1, "depthSegments": 1},
    {"uuid": "0d8f1b2e-3c4a-4b5d-8e6f-7a8b9c0d1e2f", "type": "PlaneGeometry",
     "width": 10, "height": 10, "widthSegments": 2, "heightSegments": 2},
    {"uuid": "9a8b7c6d-5e4f-4321-8765-4321fedcba98", "type": "SphereGeometry",
     "radius": 0.5, "widthSegments": 8, "heightSegments": 6,
     "phiStart": 0, "phiLength": 6.283185307179586,
     "thetaStart": 0, "thetaLength": 3.141592653589793}
  ],
  "materials": [
    {"uuid": "1f2e3d4c-5b6a-4978-8a9b-0c1d2e3f4a5b", "type": "MeshStandardMaterial",
     "color": 16744448, "roughness": 0.4, "metalness": 0.1, "emissive": 0,
     "envMapRotation": [0, 0, 0, "XYZ"], "envMapIntensity": 1,
     "blendColor": 0, "depthFunc": 3, "depthTest": true, "depthWrite": true,
     "colorWrite": true, "stencilWrite": false, "stencilWriteMask": 255,
     "stencilFunc": 519, "stencilRef": 0, "stencilFuncMask": 255,
     "stencilFail": 7680, "stencilZFail": 7680, "stencilZPass": 7680},
    {"uuid": "2a3b4c5d-6e7f-4801-9a2b-3c4d5e6f7a8b", "type": "MeshLambertMaterial",
     "color": 8421504, "emissive": 0, "reflectivity": 1,
     "refractionRatio": 0.98, "combine": 0, "side": 2},
    {"uuid": "3b4c5d6e-7f80-4912-8b3c-4d5e6f7a8b9c", "type": "MeshPhongMaterial",
     "color": 16777215}
  ],
  "object": {
    "uuid": "4c5d6e7f-8091-4a23-9c4d-5e6f7a8b9cad", "type": "Scene",
    "layers": 1, "matrix": [1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1], "up": [0,1,0],
    "background": 1118481,
    "fog": {"type": "Fog", "name": "", "color": 16777215, "near": 10, "far": 50},
    "children": [
      {"uuid": "5d6e7f80-91a2-4b34-8d5e-6f7a8b9cadbe", "type": "Group",
       "name": "rig", "layers": 1,
       "matrix": [1,0,0,0,0,1,0,0,0,0,1,0,0,2,0,1], "up": [0,1,0],
       "children": [
         {"uuid": "6e7f8091-a2b3-4c45-9e6f-7a8b9cadbecf", "type": "Mesh",
          "name": "crate", "castShadow": true, "layers": 1,
          "matrix": [0,0,-1,0,0,1,0,0,1,0,0,0,1,0,0,1], "up": [0,1,0],
          "geometry": "6e3d2a4c-7f1b-4a1e-9b1d-2c3f4e5a6b7c",
          "material": "1f2e3d4c-5b6a-4978-8a9b-0c1d2e3f4a5b"},
         {"uuid": "708192a3-b4c5-4d56-8f70-8b9cadbecfd0", "type": "Mesh",
          "name": "ball", "layers": 1,
          "matrix": [1,0,0,0,0,1,0,0,0,0,1,0,0,1,0,1], "up": [0,1,0],
          "geometry": "9a8b7c6d-5e4f-4321-8765-4321fedcba98",
          "material": "3b4c5d6e-7f80-4912-8b3c-4d5e6f7a8b9c"}
       ]},
      {"uuid": "8192a3b4-c5d6-4e67-9081-9cadbecfd0e1", "type": "Mesh",
       "name": "floor", "receiveShadow": true, "layers": 1,
       "matrix": [1,0,0,0,0,0,-1,0,0,1,0,0,0,0,0,1], "up": [0,1,0],
       "geometry": "0d8f1b2e-3c4a-4b5d-8e6f-7a8b9c0d1e2f",
       "material": "2a3b4c5d-6e7f-4801-9a2b-3c4d5e6f7a8b"},
      {"uuid": "92a3b4c5-d6e7-4f78-8192-adbecfd0e1f2", "type": "DirectionalLight",
       "name": "sun", "castShadow": true, "layers": 1,
       "matrix": [1,0,0,0,0,1,0,0,0,0,1,0,5,10,7.5,1], "up": [0,1,0],
       "color": 16777215, "intensity": 3,
       "shadow": {"mapSize": [2048, 2048],
                  "camera": {"uuid": "a3b4c5d6-e7f8-4089-92a3-becfd0e1f2a3",
                             "type": "OrthographicCamera", "layers": 1,
                             "up": [0,1,0], "zoom": 1, "left": -10, "right": 10,
                             "top": 10, "bottom": -10, "near": 0.5, "far": 500}},
       "target": "5d6e7f80-91a2-4b34-8d5e-6f7a8b9cadbe"},
      {"uuid": "b4c5d6e7-f809-4190-83b4-cfd0e1f2a3b4", "type": "AmbientLight",
       "layers": 1, "matrix": [1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1], "up": [0,1,0],
       "color": 4210752, "intensity": 1},
      {"uuid": "c5d6e7f8-091a-42a1-94c5-d0e1f2a3b4c5", "type": "PerspectiveCamera",
       "name": "camera", "layers": 1,
       "matrix": [1,0,0,0,0,1,0,0,0,0,1,0,0,1.6,5,1], "up": [0,1,0],
       "fov": 45, "zoom": 1, "near": 0.1, "far": 1000, "focus": 10,
       "aspect": 1.7777777777777777, "filmGauge": 35, "filmOffset": 0}
    ]
  }
}"""


def test_a_document_as_three_js_writes_it() raises:
    """A document shaped as three.js's `scene.toJSON()` output reads."""
    var scene = Scene()
    var assets = Assets()
    var model = read_object_json(THREE_JS_SCENE, scene, assets)
    assert_equal(scene.count(), 7)
    var rig = model.node("5d6e7f80-91a2-4b34-8d5e-6f7a8b9cadbe")
    assert_equal(scene.get(rig).name, "rig")
    assert_equal(scene.get(rig).position.y, 2)
    var crate = scene.find("crate").value()
    assert_equal(scene.get(crate).parent, rig)
    assert_equal(scene.get(crate).position.x, 1)
    # A quarter turn about y, read out of the matrix.
    assert_almost_equal(
        Float64(abs(scene.get(crate).quaternion.y)),
        Float64(0.70710678),
        atol=TOLERANCE,
    )
    assert_equal(len(scene.meshes), 3)
    assert_true(scene.meshes[0].cast_shadow)
    assert_true(scene.meshes[2].receive_shadow)
    ref crate_box = assets.geometries.get(scene.meshes[0].geometry)
    assert_equal(crate_box.vertex_count(), 24)
    ref ball = assets.geometries.get(scene.meshes[1].geometry)
    assert_equal(ball.vertex_count(), 9 * 7)
    ref floor = assets.geometries.get(scene.meshes[2].geometry)
    assert_equal(floor.vertex_count(), 9)
    var standard = assets.materials.get(scene.meshes[0].material)
    assert_equal(standard.kind, STANDARD)
    assert_equal(standard.color.hex(), 0xFF8000)
    assert_almost_equal(Float64(standard.roughness), 0.4, atol=TOLERANCE)
    var phong = assets.materials.get(scene.meshes[1].material)
    assert_equal(phong.kind, PHONG)
    assert_equal(phong.specular.hex(), 0x111111)
    assert_equal(phong.shininess, 30)
    var lambert = assets.materials.get(scene.meshes[2].material)
    assert_equal(lambert.kind, LAMBERT)
    assert_equal(lambert.side, DOUBLE_SIDE)
    assert_equal(len(scene.lights), 2)
    ref sun = scene.lights[0]
    assert_equal(sun.kind, DIRECTIONAL)
    assert_equal(sun.target, rig)
    assert_equal(sun.shadow.map_size, 2048)
    assert_equal(sun.shadow.extent.to(METER), 10)
    assert_equal(scene.lights[1].kind, AMBIENT)
    assert_equal(scene.lights[1].color.hex(), 0x404040)
    ref eye = model.cameras.perspective[0]
    assert_almost_equal(Float64(eye.fov.to(DEGREE)), 45, atol=TOLERANCE)
    assert_equal(eye.node, model.node("c5d6e7f8-091a-42a1-94c5-d0e1f2a3b4c5"))
    assert_equal(scene.background.color.hex(), 0x111111)
    assert_equal(scene.fog.near.to(METER), 10)


def test_a_root_that_is_not_a_scene() raises:
    """A document whose root is one object reads that object as a node."""
    var read = _read(
        _mesh_object(
            ',"name":"solo","visible":false,"renderOrder":2,"layers":5,'
            + '"frustumCulled":false,"children":[{"uuid":"c","type":"Bone"}]'
        )
    )
    ref scene = read[0]
    assert_equal(scene.count(), 2)
    assert_equal(scene.get(NodeId(0)).name, "solo")
    assert_false(scene.get(NodeId(0)).visible)
    assert_equal(scene.get(NodeId(0)).render_order, 2)
    assert_equal(scene.get(NodeId(0)).layers.mask, 5)
    assert_false(scene.meshes[0].frustum_culled)
    assert_equal(scene.get(NodeId(1)).parent.value, 0)
    assert_equal(read[1].materials.get(MaterialId(0)).color.hex(), 0xFF0000)


def test_separate_transform_keys() raises:
    """Without a matrix, position, rotation, quaternion and scale are
    read as three.js's `ObjectLoader` reads them."""
    var read = _read(
        '"object":{"uuid":"a","type":"Object3D","position":[1,2,3],'
        + '"rotation":[0,1.5707963,0,"YXZ"],"scale":[2,3,4],'
        + '"children":[{"uuid":"b","type":"Object3D","rotation":[0,0,0]},'
        + '{"uuid":"c","type":"Object3D","quaternion":[0,0,1,0]},'
        + '{"uuid":"d","type":"Object3D","matrix":'
        + '[1,0,0,0,0,1,0,0,0,0,1,0,7,8,9,1],"matrixAutoUpdate":false}]}'
    )
    ref scene = read[0]
    var node = scene.get(NodeId(0))
    assert_equal(node.position.z, 3)
    assert_equal(node.scale.y, 3)
    assert_almost_equal(Float64(node.quaternion.y), 0.70710678, atol=TOLERANCE)
    assert_equal(scene.get(NodeId(1)).quaternion.w, 1)
    assert_equal(scene.get(NodeId(2)).quaternion.z, 1)
    var fixed = scene.get(NodeId(3))
    assert_false(fixed.matrix_auto_update)
    assert_equal(fixed.matrix.elements[13], 8)
    assert_equal(fixed.position.x, 0)


def test_a_flipped_matrix_decomposes_with_a_negative_scale() raises:
    """A matrix with a negative determinant gives a negative x scale."""
    var node = Object3D()
    decompose(node, [-1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])
    assert_equal(node.scale.x, -1)
    with assert_raises(contains="flattens"):
        decompose(node, [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])


def test_a_buffer_geometry_with_an_index_groups_and_morphs() raises:
    """A buffer geometry reads its index, groups and morph targets."""
    var attribute = (
        '{"itemSize":3,"type":"Float32Array","array":[0,0,0,1,0,0,0,1,0]}'
    )
    var read = _read(
        '"geometries":[{"uuid":"g","type":"BufferGeometry","data":{'
        + '"attributes":{"position":'
        + attribute
        + '},"index":{"type":"Uint32Array","array":[0,1,2]},'
        + '"groups":[{"start":0,"count":3,"materialIndex":0}],'
        + '"morphAttributes":{"position":['
        + attribute
        + "]}}},"
        + '{"uuid":"h","type":"BufferGeometry","data":{"morphAttributes":{}}},'
        + '{"uuid":"k","type":"BufferGeometry","data":{"attributes":{},'
        + '"index":{"type":"Uint16Array","array":[]},"groups":[]}}],'
        + '"object":{"uuid":"o","type":"Group"}'
    )
    ref geometry = read[1].geometries.get(GeometryId(0))
    assert_equal(len(geometry.index), 3)
    assert_equal(len(geometry.groups), 1)
    assert_equal(geometry.morph_count(), 1)
    assert_false(geometry.has_morph_normals())
    assert_equal(read[1].geometries.get(GeometryId(1)).morph_count(), 0)


# --- textures ---------------------------------------------------------------


def test_texture_settings_are_read() raises:
    """A texture's wraps, filters, color space, transform and flip are
    read."""
    var read = _read(
        _textured(
            ',"wrap":[1001,1001],"magFilter":1003,"minFilter":1003,'
            + '"colorSpace":"srgb","flipY":false,"repeat":[2,3],'
            + '"offset":[0.5,0.25],"center":[0.5,0.5],"rotation":1,'
            + '"anisotropy":4'
        )
    )
    ref assets = read[1]
    ref texture = assets.textures.get(TextureId(0))
    assert_equal(texture.wrap_s, CLAMP)
    assert_equal(texture.mag_filter, NEAREST)
    assert_equal(texture.levels, 1)
    assert_equal(texture.color_space, SRGB)
    assert_equal(texture.alpha, COVERAGE)
    assert_equal(texture.repeat.y, 3)
    assert_equal(texture.offset.x, 0.5)
    assert_equal(texture.center.y, 0.5)
    assert_equal(texture.rotation.value, 1)
    assert_equal(texture.anisotropy, 4)
    # The rows as the file has them, and `v` reading them from the top.
    assert_false(texture.flip_y)
    assert_equal(texture.pixels[0], 255)
    assert_equal(texture.pixels[2], 0)


def test_a_one_row_image_flips_to_itself() raises:
    """An image one texel tall is the same upside down."""
    var url = "data:image/png;base64," + encode_base64(
        encode_png(Framebuffer(1, 1, [1, 2, 3, 255]))
    )
    var read = _read(_textured(',"flipY":false').replace(_png_url(), url))
    assert_equal(read[1].textures.get(TextureId(0)).pixels[2], 3)


def test_texture_defaults_are_three_js_defaults() raises:
    """A texture with no settings clamps, filters linearly, builds its
    mipmaps and is not decoded."""
    var read = _read(_textured(""))
    ref texture = read[1].textures.get(TextureId(0))
    assert_equal(texture.wrap_s, CLAMP)
    assert_equal(texture.mag_filter, BILINEAR)
    assert_true(texture.levels > 1)
    assert_equal(texture.color_space, LINEAR)
    assert_equal(texture.pixels[0], 255)
    var flat = _read(_textured(',"minFilter":1008,"generateMipmaps":false'))
    assert_equal(flat[1].textures.get(TextureId(0)).levels, 1)
    var linear = _read(_textured(',"colorSpace":"srgb-linear"'))
    assert_equal(linear[1].textures.get(TextureId(0)).color_space, LINEAR)


def test_a_texture_used_twice_is_built_once_per_alpha() raises:
    """A texture a map and an alpha map both name is built twice, and two
    maps of one alpha share one build."""
    var read = _read(
        _textured(
            "",
            '"type":"MeshStandardMaterial","alphaMap":"t","roughnessMap":"t"',
        )
    )
    ref assets = read[1]
    assert_equal(assets.textures.count(), 2)
    var material = assets.materials.get(MaterialId(0))
    assert_equal(material.alpha_map, material.roughness_map)
    assert_true(material.map != material.alpha_map)
    var twice = _read(
        _textured("").replace(
            '"map":"t"}]',
            '"map":"t"},{"uuid":"n","type":"MeshBasicMaterial","map":"t"}]',
        )
    )
    assert_equal(twice[1].textures.count(), 1)
    assert_equal(
        twice[1].materials.get(MaterialId(0)).map,
        twice[1].materials.get(MaterialId(1)).map,
    )


def test_an_image_file_beside_the_document() raises:
    """An image with a relative URL is read beside the document."""
    var directory = "/tmp/"
    Path(directory + "threemojo_object_json.png").write_bytes(
        encode_png(Framebuffer(2, 2, _pixels()))
    )
    var text = _wrap(
        '"geometries":[{"uuid":"g","type":"BoxGeometry"}],'
        + '"materials":[{"uuid":"m","type":"MeshBasicMaterial","map":"t"}],'
        + '"textures":[{"uuid":"t","image":"i"}],'
        + '"images":[{"uuid":"i","url":"threemojo_object_json.png"}],'
        + '"object":{"uuid":"o","type":"Mesh","geometry":"g","material":"m"}'
    )
    var path = directory + "threemojo_object_json_image.json"
    Path(path).write_text(text)
    var scene = Scene()
    var assets = Assets()
    _ = load_object_json(path, scene, assets)
    assert_equal(assets.textures.get(TextureId(0)).width, 2)


def test_texture_refusals() raises:
    """A texture the renderer has no counterpart for is refused."""
    _refuses(_textured(',"mapping":301'))
    _refuses(_textured(',"mapping":306'))
    _refuses(_textured(',"mapping":305'))
    _refuses(_textured(',"channel":2'))
    _refuses(_textured(',"wrap":[1000,999]'))
    _refuses(_textured(',"wrap":[999,999]'))
    _refuses(_textured(',"magFilter":1008'))
    _refuses(_textured(',"minFilter":1002'))
    _refuses(_textured(',"minFilter":1009'))
    _refuses(_textured(',"colorSpace":"display-p3"'))
    _refuses(_textured(',"repeat":[1]'))
    var no_image = _textured("").replace('"image":"i"', '"image":"j"')
    _refuses(no_image)
    var no_texture = _textured("").replace('"map":"t"', '"map":"u"')
    _refuses(no_texture)
    _refuses(
        '"materials":[{"uuid":"m","type":"MeshBasicMaterial","map":"t"}],'
        + '"textures":[{"uuid":"t","image":"i"}],'
        + '"images":[{"uuid":"i"}],"object":{"uuid":"o","type":"Group"}'
    )
    _refuses(
        '"materials":[{"uuid":"m","type":"MeshBasicMaterial","map":"t"}],'
        + '"textures":[{"uuid":"t","image":"i"}],'
        + '"images":[{"uuid":"i","url":["a","b"]}],'
        + '"object":{"uuid":"o","type":"Group"}'
    )
    _refuses(
        '"materials":[{"uuid":"m","type":"MeshBasicMaterial","map":"t"}],'
        + '"textures":[{"uuid":"t","image":"i"}],'
        + '"images":[{"uuid":"i","url":"data:image/png,abc"}],'
        + '"object":{"uuid":"o","type":"Group"}'
    )
    _refuses(
        '"materials":[{"uuid":"m","type":"MeshBasicMaterial","map":"t"}],'
        + '"textures":[{"uuid":"t","image":"i"}],'
        + '"images":[{"uuid":"i","url":"data:nocomma"}],'
        + '"object":{"uuid":"o","type":"Group"}'
    )
    _refuses(
        '"materials":[{"uuid":"m","type":"MeshBasicMaterial","map":"t"}],'
        + '"textures":[{"uuid":"t","image":"i"}],'
        + '"images":[{"uuid":"i","url":"https://example.com/a.png"}],'
        + '"object":{"uuid":"o","type":"Group"}'
    )


# --- materials --------------------------------------------------------------


def _material(fields: String) raises -> Material:
    """Return the one material of a document with a group root."""
    var read = _read(
        '"materials":[{"uuid":"m",'
        + fields
        + '}],"object":{"uuid":"o","type":"Group"}'
    )
    return read[1].materials.get(MaterialId(0))


def test_material_blending_and_defaults() raises:
    """Blending numbers map to `Blending`, and each type has its
    three.js defaults."""
    assert_equal(
        _material('"type":"MeshBasicMaterial","blending":0').blending, OPAQUE
    )
    assert_equal(
        _material('"type":"MeshBasicMaterial","blending":4').blending, MULTIPLY
    )
    assert_equal(
        _material(
            '"type":"MeshBasicMaterial","transparent":true,"opacity":0.5'
        ).blending,
        BLEND,
    )
    var shadow = _material('"type":"ShadowMaterial","transparent":true')
    assert_equal(shadow.color.hex(), 0)
    var normals = _material('"type":"MeshNormalMaterial","color":255')
    assert_equal(normals.color.hex(), 0xFFFFFF)
    var physical = _material(
        '"type":"MeshPhysicalMaterial","reflectivity":0.5,"combine":1'
    )
    assert_equal(physical.reflectivity, 1)
    assert_equal(physical.ior, 1.5)


def test_material_refusals() raises:
    """A material type or blending this port does not read is refused."""
    _refuses(
        '"materials":[{"uuid":"m","type":"RawShaderMaterial"}],'
        + '"object":{"uuid":"o","type":"Group"}'
    )
    _refuses(
        '"materials":[{"uuid":"m","type":"MeshBasicMaterial","blending":5}],'
        + '"object":{"uuid":"o","type":"Group"}'
    )
    _refuses(
        '"materials":[{"uuid":"m","type":"MeshBasicMaterial","blending":6}],'
        + '"object":{"uuid":"o","type":"Group"}'
    )
    _refuses(
        '"materials":[{"uuid":"m","type":"MeshBasicMaterial",'
        + '"normalScale":[1]}],"object":{"uuid":"o","type":"Group"}'
    )
    _refuses(
        '"materials":[{"uuid":"m","type":"MeshBasicMaterial"},'
        + '{"uuid":"m","type":"MeshBasicMaterial"}],'
        + '"object":{"uuid":"o","type":"Group"}'
    )
    _refuses('"materials":[3],"object":{"uuid":"o","type":"Group"}')
    _refuses('"materials":{},"object":{"uuid":"o","type":"Group"}')
    _refuses('"metadata":[],"object":{"uuid":"o","type":"Group"}')
    var none = _read('"materials":[],"object":{"uuid":"o","type":"Group"}')
    assert_equal(none[1].materials.count(), 0)
    _refuses(
        '"materials":[{"type":"MeshBasicMaterial"}],'
        + '"object":{"uuid":"o","type":"Group"}'
    )


comptime TWO_MATERIALS = (
    '"geometries":[{"uuid":"g","type":"BufferGeometry","data":{"attributes":'
    '{"position":{"itemSize":3,"type":"Float32Array","array":[0,0,0,1,0,0,'
    '0,1,0],"normalized":false}},"groups":[{"start":0,"count":3,'
    '"materialIndex":1}]}}],'
    '"materials":[{"uuid":"m","type":"MeshBasicMaterial","color":16711680},'
    '{"uuid":"n","type":"MeshBasicMaterial","color":255}],'
)


def test_a_mesh_reads_and_writes_a_material_list() raises:
    """A mesh's `material` can be a list of uuids, as three.js writes it
    for a material array, and it comes back as a list."""
    var read = _read(
        TWO_MATERIALS
        + '"object":{"uuid":"o","type":"Mesh","geometry":"g",'
        + '"material":["m","n","m"]}'
    )
    ref mesh = read[0].meshes[0]
    assert_true(mesh.is_multi_material())
    assert_equal(len(mesh.materials), 3)
    assert_true(mesh.materials[2] == mesh.materials[0])
    assert_false(mesh.materials[1] == mesh.materials[0])
    var text = object_to_json(read[0], read[1])
    assert_true('"material":["' in text)
    var scene = Scene()
    var assets = Assets()
    _ = read_object_json(text, scene, assets)
    assert_equal(len(scene.meshes[0].materials), 3)
    assert_equal(assets.materials.count(), 2)
    # A list that is empty or names nothing is refused, and only a mesh
    # reads a list.
    _refuses(
        TWO_MATERIALS
        + '"object":{"uuid":"o","type":"Mesh","geometry":"g","material":[]}'
    )
    _refuses(
        TWO_MATERIALS
        + '"object":{"uuid":"o","type":"Mesh","geometry":"g",'
        + '"material":["m","x"]}'
    )
    _refuses(
        TWO_MATERIALS
        + '"object":{"uuid":"o","type":"Points","geometry":"g",'
        + '"material":["m"]}'
    )


def test_the_helpers() raises:
    """The constant tables map three.js's numbers both ways."""
    assert_equal(wrap_of(1002), MIRROR)
    assert_equal(wrap_code(MIRROR), 1002)
    assert_equal(wrap_code(CLAMP), 1001)
    assert_equal(wrap_code(REPEAT), 1000)
    with assert_raises():
        _ = wrap_of(1003)
    assert_true(is_mipmap_filter(1005))
    assert_false(is_mipmap_filter(1006))
    assert_false(is_mipmap_filter(1003))
    assert_false(is_mipmap_filter(1009))
    assert_false(Bool(blending_of(1)))
    assert_equal(blending_of(2).value(), ADDITIVE)
    with assert_raises():
        _ = blending_of(-1)
    assert_equal(color_space_of(""), LINEAR)
    assert_equal(euler_order_of("ZYX"), ZYX)
    with assert_raises(contains="Euler order"):
        _ = euler_order_of("XXY")


# --- objects ----------------------------------------------------------------


def test_object_refusals() raises:
    """An object this port cannot build is refused."""
    _refuses(_mesh_object(',"layers":-1'))
    _refuses(_mesh_object(',"layers":4294967296'))
    _refuses(_mesh_object(',"children":[{"uuid":"o","type":"Group"}]'))
    _refuses(_mesh_object(',"children":[3]'))
    _refuses(_mesh_object(',"children":{}'))
    _refuses(_mesh_object(',"matrix":[1,2]'))
    _refuses(_mesh_object(',"matrix":[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1e300]'))
    _refuses(
        MESH_LIBRARY
        + '"object":{"uuid":"o","type":"Mesh","geometry":"x","material":"m"}'
    )
    _refuses(
        MESH_LIBRARY
        + '"object":{"uuid":"o","type":"Mesh","geometry":"g","material":"x"}'
    )
    _refuses(
        MESH_LIBRARY
        + '"object":{"uuid":"o","type":"Line","geometry":"g",'
        '"material":["m","m"]}'
    )
    _refuses('"object":{"uuid":"o","type":"Line"}')
    _refuses('"object":{"type":"Group"}')
    _refuses('"object":[]')
    _refuses('"object":{"uuid":"o","type":"Scene","children":[4]}')
    _refuses('"objects":{}')
    _refuses(
        MESH_LIBRARY + '"object":{"uuid":"o","type":"Mesh","geometry":"g"}'
    )


def test_an_instanced_mesh() raises:
    """An instanced mesh reads its count and matrices, and refuses a
    matrix array of the wrong size."""
    var matrices = (
        '"instanceMatrix":{"itemSize":16,"type":"Float32Array","array":'
        + "[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1,1,0,0,0,0,1,0,0,0,0,1,0,3,0,0,1]}"
    )
    var read = _read(
        MESH_LIBRARY
        + '"object":{"uuid":"o","type":"InstancedMesh","geometry":"g",'
        + '"material":"m","count":2,'
        + matrices
        + "}"
    )
    assert_equal(read[0].instanced_meshes[0].matrix_at(1).elements[12], 3)
    var none = _read(
        MESH_LIBRARY
        + '"object":{"uuid":"o","type":"InstancedMesh","geometry":"g",'
        + '"material":"m","instanceMatrix":{"itemSize":16,'
        + '"type":"Float32Array","array":[]}}'
    )
    assert_equal(none[0].instanced_meshes[0].count(), 0)
    _refuses(
        MESH_LIBRARY
        + '"object":{"uuid":"o","type":"InstancedMesh","geometry":"g",'
        + '"material":"m","count":1}'
    )
    _refuses(
        MESH_LIBRARY
        + '"object":{"uuid":"o","type":"InstancedMesh","geometry":"g",'
        + '"material":"m","count":3,'
        + matrices
        + "}"
    )
    _refuses(
        MESH_LIBRARY
        + '"object":{"uuid":"o","type":"InstancedMesh","geometry":"g",'
        + '"material":"m","count":2,'
        + matrices.replace('"itemSize":16', '"itemSize":8')
        + "}"
    )


def test_lights_read_with_three_js_defaults() raises:
    """A light with no numbers takes three.js's defaults, a target that
    is not in the file is the origin, and a shadow reads its camera."""
    var read = _read(
        '"object":{"uuid":"s","type":"Scene","children":['
        + '{"uuid":"a","type":"SpotLight","target":"nowhere","shadow":'
        + '{"camera":{"type":"PerspectiveCamera","fov":50}}},'
        + '{"uuid":"b","type":"HemisphereLight"},'
        + '{"uuid":"c","type":"RectAreaLight"},'
        + '{"uuid":"d","type":"PointLight","shadow":{}}]}'
    )
    ref lights = read[0].lights
    assert_equal(lights[0].kind, SPOT)
    assert_almost_equal(Float64(lights[0].angle.to(DEGREE)), 60, atol=TOLERANCE)
    assert_equal(lights[0].decay, 2)
    assert_equal(lights[0].target, NO_PARENT)
    assert_equal(lights[0].shadow.extent.to(METER), 5)
    assert_equal(lights[1].ground.hex(), 0xFFFFFF)
    assert_equal(lights[2].width.to(METER), 10)
    assert_equal(lights[3].kind, POINT)


def test_a_light_probe_round_trips_its_27_numbers() raises:
    """A probe written as three.js's `LightProbe.toJSON` writes `sh` reads it back,
    and a probe without it is darkness."""
    var sh = SphericalHarmonics3()
    for index in range(9):
        sh.set_coefficient(
            index, Vector3(Float32(index) * 0.25, -0.5, Float32(index))
        )
    var scene = Scene()
    scene.add_light(light_probe(sh, 0.75))
    scene.update()
    var assets = Assets()
    var text = object_to_json(scene, assets, ObjectCameras())
    assert_true('"type":"LightProbe"' in text)
    assert_true('"sh":[' in text)
    var again = Scene()
    var read = Assets()
    _ = read_object_json(text, again, read)
    assert_equal(len(again.lights), 1)
    ref probe = again.lights[0]
    assert_equal(probe.kind, LIGHT_PROBE)
    assert_equal(probe.intensity, 0.75)
    assert_true(probe.sh == sh)
    var bare = _read('"object":{"uuid":"p","type":"LightProbe"}')
    assert_equal(bare[0].lights[0].kind, LIGHT_PROBE)
    assert_true(bare[0].lights[0].sh == SphericalHarmonics3())
    # Anything but 27 numbers is refused.
    _refuses('"object":{"uuid":"p","type":"LightProbe","sh":[1,2,3]}')


def test_light_refusals() raises:
    """A shadow that is not square, and a light the renderer refuses, are
    refused."""
    _refuses(
        '"object":{"uuid":"a","type":"DirectionalLight","shadow":'
        + '{"mapSize":[512,256]}}'
    )
    _refuses(
        '"object":{"uuid":"a","type":"DirectionalLight","shadow":'
        + '{"camera":{"left":-5,"right":5,"top":4,"bottom":-4}}}'
    )
    _refuses(
        '"object":{"uuid":"a","type":"DirectionalLight","shadow":'
        + '{"camera":{"left":-4,"right":4,"top":4,"bottom":-5}}}'
    )
    _refuses(
        '"object":{"uuid":"a","type":"DirectionalLight","shadow":'
        + '{"camera":{"left":-4,"right":5,"top":4,"bottom":-4}}}'
    )
    _refuses('"object":{"uuid":"a","type":"HemisphereLight","castShadow":true}')
    _refuses('"object":{"uuid":"a","type":"AmbientLight","intensity":-1}')


def test_cameras_read_with_three_js_defaults() raises:
    """A camera with no numbers takes three.js's defaults, and one with a
    zoom, a film or a view that is not one is refused."""
    var read = _read(
        '"object":{"uuid":"s","type":"Scene","children":['
        + '{"uuid":"a","type":"PerspectiveCamera","view":null},'
        + '{"uuid":"b","type":"OrthographicCamera","view":null}]}'
    )
    ref cameras = read[2].cameras
    ref eye = cameras.perspective[0]
    assert_almost_equal(Float64(eye.fov.to(DEGREE)), 50, atol=TOLERANCE)
    assert_equal(eye.zoom, 1)
    assert_almost_equal(Float64(eye.focus.to(METER)), 10, atol=TOLERANCE)
    assert_almost_equal(
        Float64(eye.film_gauge.to(MILLIMETER)), 35, atol=TOLERANCE
    )
    assert_equal(eye.film_offset.value, 0)
    assert_false(Bool(eye.view))
    assert_equal(cameras.orthographic[0].right.to(METER), 1)
    assert_false(Bool(cameras.orthographic[0].view))
    _refuses('"object":{"uuid":"a","type":"PerspectiveCamera","zoom":0}')
    _refuses('"object":{"uuid":"a","type":"PerspectiveCamera","filmGauge":0}')
    _refuses('"object":{"uuid":"a","type":"PerspectiveCamera","focus":-1}')
    _refuses('"object":{"uuid":"a","type":"PerspectiveCamera","view":3}')
    _refuses(
        '"object":{"uuid":"a","type":"PerspectiveCamera","view":'
        + '{"fullWidth":0}}'
    )
    _refuses(
        '"object":{"uuid":"a","type":"OrthographicCamera","view":{"width":-1}}'
    )


def test_a_camera_reads_three_js_zoom_film_and_view() raises:
    """A camera as three.js 0.180 writes it, zoomed, filmed and tiled,
    reads back to every setting, and a view with keys left out takes
    three.js's first numbers, disabled."""
    var read = _read(
        '"object":{"uuid":"s","type":"Scene","children":['
        + '{"uuid":"a","type":"PerspectiveCamera","fov":60,"zoom":2,'
        + '"near":0.5,"far":100,"focus":7,"aspect":1.5,"view":'
        + '{"enabled":true,"fullWidth":1200,"fullHeight":800,"offsetX":300,'
        + '"offsetY":200,"width":600,"height":400},"filmGauge":24,'
        + '"filmOffset":4},'
        + '{"uuid":"b","type":"OrthographicCamera","zoom":2,"view":{}}]}'
    )
    ref eye = read[2].cameras.perspective[0]
    assert_equal(eye.zoom, 2)
    assert_almost_equal(Float64(eye.focus.to(METER)), 7, atol=TOLERANCE)
    assert_almost_equal(
        Float64(eye.film_gauge.to(MILLIMETER)), 24, atol=TOLERANCE
    )
    assert_almost_equal(
        Float64(eye.film_offset.to(MILLIMETER)), 4, atol=TOLERANCE
    )
    var view = eye.view.value()
    assert_true(view.enabled)
    assert_equal(view.full_width, 1200)
    assert_equal(view.full_height, 800)
    assert_equal(view.offset_x, 300)
    assert_equal(view.offset_y, 200)
    assert_equal(view.width, 600)
    assert_equal(view.height, 400)
    ref plan = read[2].cameras.orthographic[0]
    var tile = plan.view.value()
    assert_false(tile.enabled)
    assert_equal(tile.full_width, 1)
    assert_equal(tile.offset_x, 0)
    assert_equal(tile.height, 1)


def test_a_camera_writes_its_zoom_film_and_view_as_three_js_does() raises:
    """The camera three.js 0.180 wrote in node, zoomed, filmed and with a
    cleared view, is written with the same keys in the same order."""
    var scene = Scene()
    var assets = Assets()
    var cameras = ObjectCameras()
    var eye = PerspectiveCamera(
        Angle(60, DEGREE), 1.5, Length(0.5, METER), Length(100, METER)
    )
    eye.zoom = 2
    eye.film_offset = Length(4, MILLIMETER)
    eye.set_view_offset(1200, 800, 300, 200, 600, 400)
    eye.clear_view_offset()
    eye.attach(scene.add(Object3D()))
    cameras.perspective.append(eye)
    var plan = OrthographicCamera(
        Length(-4, METER),
        Length(6, METER),
        Length(3, METER),
        Length(-1, METER),
        Length(0.5, METER),
        Length(50, METER),
    )
    plan.set_view_offset(1000, 400, 250, 100, 500, 200)
    plan.clear_view_offset()
    plan.attach(scene.add(Object3D()))
    cameras.orthographic.append(plan^)
    var text = object_to_json(scene, assets, cameras)
    # three.js writes 2 where this writes 2.0; the keys, their order and
    # the numbers they read back to are the same.
    assert_true(
        '"zoom":2.0,"near":0.5,"far":100.0,"focus":10.0,"aspect":1.5,'
        + '"view":{"enabled":false,"fullWidth":1200.0,"fullHeight":800.0,'
        + '"offsetX":300.0,"offsetY":200.0,"width":600.0,"height":400.0},'
        + '"filmGauge":35.0,"filmOffset":4.0}'
        in text
    )
    assert_true(
        '"zoom":1.0,"left":-4.0,"right":6.0,"top":3.0,"bottom":-1.0,'
        + '"near":0.5,"far":50.0,"view":{"enabled":false,'
        + '"fullWidth":1000.0,"fullHeight":400.0,"offsetX":250.0,'
        + '"offsetY":100.0,"width":500.0,"height":200.0}}'
        in text
    )
    # A setting that is not one is refused on the way out.
    cameras.perspective[0].zoom = 0
    with assert_raises(contains="zoom"):
        _ = object_to_json(scene, assets, cameras)
    cameras.perspective[0].zoom = 1
    cameras.orthographic[0].view.value().width = 0
    with assert_raises(contains="positive"):
        _ = object_to_json(scene, assets, cameras)


def test_scene_fog_and_background_refusals() raises:
    """A fog this port has no counterpart for is refused."""
    _refuses('"object":{"uuid":"s","type":"Scene","fog":{"type":"Haze"}}')
    _refuses('"object":{"uuid":"s","type":"Scene","background":"t"}')
    _refuses('"object":{"uuid":"s","type":"Scene","background":-1}')


# --- geometry ---------------------------------------------------------------


def test_geometry_refusals() raises:
    """A geometry this port cannot build is refused."""
    var tail = '],"object":{"uuid":"o","type":"Group"}'
    _refuses(
        '"geometries":[{"uuid":"g","type":"BoxGeometry","widthSegments":2}'
        + tail
    )
    _refuses(
        '"geometries":[{"uuid":"g","type":"SphereGeometry","phiStart":1}' + tail
    )
    _refuses(
        '"geometries":[{"uuid":"g","type":"SphereGeometry","phiLength":1}'
        + tail
    )
    _refuses(
        '"geometries":[{"uuid":"g","type":"SphereGeometry","thetaStart":1}'
        + tail
    )
    _refuses(
        '"geometries":[{"uuid":"g","type":"SphereGeometry","thetaLength":1}'
        + tail
    )
    _refuses('"geometries":[{"uuid":"g","type":"TorusGeometry"}' + tail)
    _refuses('"geometries":[{"uuid":"g","type":"BufferGeometry"}' + tail)
    var data = '"geometries":[{"uuid":"g","type":"BufferGeometry","data":'
    _refuses(data + '{"attributes":{"position":3}}}' + tail)
    _refuses(
        data
        + '{"attributes":{"position":{"isInterleavedBufferAttribute":true}}}}'
        + tail
    )
    _refuses(
        data
        + '{"attributes":{"position":{"type":"Uint8Array","array":[1]}}}}'
        + tail
    )
    _refuses(
        data
        + '{"attributes":{"position":{"type":"Float32Array","itemSize":3}}}}'
        + tail
    )
    _refuses(data + '{"index":{"type":"Uint8Array","array":[0]}}}' + tail)
    _refuses(data + '{"index":{"type":"Uint16Array"}}}' + tail)
    _refuses(data + '{"index":{"type":"Uint32Array","array":[0]}}}' + tail)
    var morph = (
        '{"itemSize":3,"type":"Float32Array","array":[0,0,0,1,0,0,0,1,0]}'
    )
    var with_position = (
        data + '{"attributes":{"position":' + morph + '},"morphAttributes":{'
    )
    _refuses(with_position + '"position":[' + morph + '],"normal":[]}}}' + tail)
    _refuses(with_position + '"normal":[' + morph + "]}}}" + tail)
    var both = _read(
        with_position
        + '"position":['
        + morph
        + '],"normal":['
        + morph
        + ']},"morphTargetsRelative":true}}],'
        + '"object":{"uuid":"o","type":"Group"}'
    )
    assert_true(both[1].geometries.get(GeometryId(0)).has_morph_normals())
    assert_true(both[1].geometries.get(GeometryId(0)).morph_relative)


# --- the document -----------------------------------------------------------


def test_document_refusals() raises:
    """A document that is not an Object document of version 4 is
    refused."""
    var scene = Scene()
    var assets = Assets()
    with assert_raises(contains="must be an object"):
        _ = read_object_json("[]", scene, assets)
    with assert_raises(contains="no metadata"):
        _ = read_object_json("{}", scene, assets)
    with assert_raises(contains="metadata.type"):
        _ = read_object_json(
            '{"metadata":{"version":4.6,"type":"Geometry"}}', scene, assets
        )
    with assert_raises(contains="version 4"):
        _ = read_object_json(
            '{"metadata":{"version":3,"type":"Object"}}', scene, assets
        )
    with assert_raises(contains="no object"):
        _ = read_object_json(
            '{"metadata":{"version":4.5,"type":"Object"}}', scene, assets
        )
    with assert_raises(contains="must be finite"):
        _ = read_object_json(
            '{"metadata":{"version":1e300,"type":"Object"}}', scene, assets
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
