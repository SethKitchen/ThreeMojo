# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the octree, light probe and texture helpers and the shadow
map viewer, three.js's `OctreeHelper`, `LightProbeHelper`,
`TextureHelper` and `ShadowMapViewer`.

The octree's points were calculated by three.js 0.180, by node on
`examples/jsm/helpers/OctreeHelper.js`, for the level `test_octree` builds.
"""

from animation.keyframe_track import LightIndex
from cameras.orthographic_camera import OrthographicCamera
from core.assets import Assets
from core.buffer_geometry import BufferGeometry, POSITION, UV
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.box import box
from geometries.plane import plane
from helpers.box import box_helper
from helpers.light_probe import LightProbeHelper
from helpers.octree import DEFAULT_OCTREE_COLOR, octree_helper
from helpers.shadow_map_viewer import (
    SHADOW_VIEWER_FRAME,
    ShadowMapViewer,
    shadow_gray,
)
from helpers.texture import TextureHelper, texture_helper
from lights.light import (
    LightKind,
    directional_light,
    light_probe,
    point_light,
    spot_light,
)
from lights.shadow import VSM_SHADOW_MAP
from materials.material import BASIC, DOUBLE_SIDE, Material
from math.bounds import Box3
from math.octree import Octree
from math.spherical_harmonics3 import SphericalHarmonics3
from math.triangle import Triangle
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.cube_texture import CubeTexture
from render.cube_texture_store import CubeTextureId
from render.framebuffer import Color, FloatColor, Framebuffer
from render.rect import Rect
from render.srgb import LINEAR, SRGB
from render.target import RenderTarget
from render.texture import BILINEAR, CLAMP, NEAREST, Texture
from render.texture_store import TextureId
from render.volume_texture import (
    Data3DTexture,
    DataArrayTexture,
    VolumeImage,
)
from render.volume_texture_store import Data3DTextureId, DataArrayTextureId
from renderers.renderer import Renderer
from std.math import inf, pi
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Length, METER

comptime TOLERANCE = Float64(1e-6)
comptime SIDE = 32


def meters(value: Float32) -> Length:
    """Return a length in meters."""
    return Length(value, METER)


def assert_point(
    geometry: BufferGeometry, index: Int, x: Float32, y: Float32, z: Float32
) raises:
    """Assert one position of a geometry."""
    var point = geometry.attribute_view(String(POSITION)).vector3(index)
    assert_almost_equal(Float64(point.x), Float64(x), atol=TOLERANCE)
    assert_almost_equal(Float64(point.y), Float64(y), atol=TOLERANCE)
    assert_almost_equal(Float64(point.z), Float64(z), atol=TOLERANCE)


def assert_byte(actual: UInt8, expected: UInt8, tolerance: Int = 1) raises:
    """Assert a byte to within a tolerance."""
    assert_true(
        abs(Int(actual) - Int(expected)) <= tolerance,
        String(actual) + " is not near " + String(expected),
    )


def assert_pixel(image: Framebuffer, x: Int, y: Int, expected: Color) raises:
    """Assert a pixel's three color bytes, each to within one."""
    var got = image.get_pixel(x, y)
    assert_byte(got.r, expected.r)
    assert_byte(got.g, expected.g)
    assert_byte(got.b, expected.b)


def front_camera(half: Float32) raises -> OrthographicCamera:
    """Return a camera on +z that sees `half` meters each way."""
    var camera = OrthographicCamera(
        meters(-half),
        meters(half),
        meters(half),
        meters(-half),
        meters(0.1),
        meters(10),
    )
    camera.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    return camera^


# --- OctreeHelper -------------------------------------------------------------


def height(i: Int, j: Int) -> Float32:
    """Return the height of the level's grid at a corner."""
    return Float32((i * 7 + j * 3) % 5) * 0.25


def level_tree() -> Octree:
    """Return the octree of `test_octree`'s level."""
    var tree = Octree()
    for i in range(6):
        for j in range(6):
            var x0 = Float32(i - 3)
            var z0 = Float32(j - 3)
            var a = Vector3(x0, height(i, j), z0)
            var b = Vector3(x0, height(i, j + 1), z0 + 1)
            var c = Vector3(x0 + 1, height(i + 1, j + 1), z0 + 1)
            var d = Vector3(x0 + 1, height(i + 1, j), z0)
            tree.add_triangle(Triangle(a, b, c))
            tree.add_triangle(Triangle(a, c, d))
    tree.add_triangle(
        Triangle(Vector3(2, 0, -2), Vector3(2, 3, -2), Vector3(2, 3, 2))
    )
    tree.add_triangle(
        Triangle(Vector3(2, 0, -2), Vector3(2, 3, 2), Vector3(2, 0, 2))
    )
    tree.build()
    return tree^


def test_octree_helper_matches_three() raises:
    var tree = level_tree()
    assert_equal(len(tree.boxes()), tree.node_count() - 1)
    var edges = octree_helper(tree)
    assert_equal(edges.vertex_count(), 2808)
    assert_point(edges, 0, -0.004999999888, 1.495000004768, -0.004999999888)
    assert_point(edges, 1, -3.009999990463, 1.495000004768, -0.004999999888)
    assert_point(edges, 23, -0.004999999888, -0.009999999776, -3.009999990463)
    assert_point(edges, 24, -1.507500052452, 0.742500007152, -1.507500052452)
    assert_point(edges, 25, -3.009999990463, 0.742500007152, -1.507500052452)
    assert_point(edges, 47, -1.507500052452, -0.009999999776, -3.009999990463)
    assert_point(edges, 240, -1.507500052452, 0.742500007152, 1.497499942779)
    assert_point(edges, 246, -1.507500052452, -0.009999999776, 1.497499942779)
    assert_point(edges, 1000, 0.746249973774, 0.742500007152, -0.004999999888)
    assert_point(edges, 2807, 3, 1.495000004768, -0.004999999888)
    assert_equal(DEFAULT_OCTREE_COLOR.hex(), 0xFFFF00)


def test_an_empty_octree_has_no_boxes() raises:
    var tree = Octree()
    assert_equal(len(tree.boxes()), 0)
    assert_equal(octree_helper(tree).vertex_count(), 0)
    tree.build()
    assert_equal(octree_helper(tree).vertex_count(), 0)


def test_the_box_helper_still_draws_twelve_edges() raises:
    var edges = box_helper(Box3(Vector3(-1, -2, -3), Vector3(1, 2, 3)))
    assert_equal(edges.vertex_count(), 24)
    assert_point(edges, 0, 1, 2, 3)
    assert_point(edges, 23, 1, -2, -3)


# --- LightProbeHelper ---------------------------------------------------------


def a_probe(intensity: Float32 = 1.0) raises -> SphericalHarmonics3:
    """Return a probe's coefficients: a base, a z term and a z-squared
    term, each in its own color."""
    var sh = SphericalHarmonics3()
    sh.set_coefficient(0, Vector3(0.6, 0.5, 0.4))
    sh.set_coefficient(2, Vector3(0.3, 0.1, 0.0))
    sh.set_coefficient(6, Vector3(0.0, 0.2, 0.1))
    sh.set_coefficient(3, Vector3(0.1, 0.1, 0.1))
    return sh


def probe_color(sh: SphericalHarmonics3, intensity: Float32) raises -> Color:
    """Return what the helper shows facing +z: three.js's shader at the
    normal (0, 0, 1), encoded."""
    var irradiance = (
        sh.coefficient(0) * 0.886227
        + sh.coefficient(2) * (2.0 * 0.511664)
        + sh.coefficient(6) * (0.743125 - 0.247708)
    )
    var light = irradiance * Float32(0.318309886) * intensity
    return FloatColor(light.x, light.y, light.z).encode()


def draw_probe(helper: LightProbeHelper, assets: Assets) raises -> Framebuffer:
    """Draw a probe helper on a node at the origin, seen from +z."""
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    scene.add_mesh(helper.mesh(node))
    var renderer = Renderer(SIDE, SIDE)
    return renderer.render(scene, assets, front_camera(1.5))


def test_the_probe_helper_shows_the_irradiance() raises:
    var assets = Assets()
    var sh = a_probe()
    var probe = light_probe(sh, 2.0)
    var helper = LightProbeHelper(probe, assets, meters(1.0))
    var image = draw_probe(helper, assets)
    assert_pixel(image, SIDE // 2, SIDE // 2, probe_color(sh, 2.0))
    # The corner is past the sphere.
    assert_pixel(image, 0, 0, Color(16, 18, 26))
    # The intensity is read again on `update`, as before every frame.
    var brighter = light_probe(sh, 3.0)
    helper.update(brighter, assets)
    image = draw_probe(helper, assets)
    assert_pixel(image, SIDE // 2, SIDE // 2, probe_color(sh, 3.0))


def test_the_probe_helper_is_as_big_as_its_size() raises:
    var assets = Assets()
    var probe = light_probe(a_probe())
    var small = LightProbeHelper(probe, assets, meters(0.5))
    var image = draw_probe(small, assets)
    # A pixel at 0.75 m from the center is past a half-meter sphere.
    assert_pixel(image, SIDE // 2 + 8, SIDE // 2, Color(16, 18, 26))
    var bounds = assets.geometries.get(small.geometry).bounding_box()
    assert_almost_equal(Float64(bounds.max.x), 0.5, atol=TOLERANCE)


def test_the_probe_helper_refuses_what_is_not_a_probe() raises:
    var assets = Assets()
    var scene = Scene()
    var node = scene.add(Object3D())
    var lamp = directional_light(Color(255, 255, 255), node)
    with assert_raises(contains="light probe"):
        _ = LightProbeHelper(lamp, assets)
    var odd = light_probe(a_probe())
    odd.kind = LightKind(42)
    with assert_raises(contains="light probe"):
        _ = LightProbeHelper(odd, assets)
    var probe = light_probe(a_probe())
    with assert_raises(contains="positive size"):
        _ = LightProbeHelper(probe, assets, meters(0))
    var helper = LightProbeHelper(probe, assets)
    with assert_raises(contains="light probe"):
        helper.update(lamp, assets)
    with assert_raises(contains="scene node"):
        _ = helper.mesh(NodeId(-1))


# --- TextureHelper -----------------------------------------------------------


def four_texels() raises -> Texture:
    """Return a 2 by 2 image: red, green on top; blue, half-clear white
    below."""
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
        64,
    ]
    return Texture(2, 2, pixels^, CLAMP, NEAREST, SRGB, False)


def draw_parts(
    helper: TextureHelper, assets: Assets, eye: Vector3 = Vector3(0, 0, 5)
) raises -> Framebuffer:
    """Draw a texture helper on a node at the origin, over black."""
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    helper.add_to(scene, node)
    var renderer = Renderer(SIDE, SIDE)
    renderer.set_background(Color(0, 0, 0))
    var camera = front_camera(1)
    camera.place(eye, Vector3(0, 0, 0))
    return renderer.render(scene, assets, camera)


def test_a_2d_texture_shows_upright_and_opaque() raises:
    var assets = Assets()
    var image = four_texels()
    # three.js's shader reads `vUvw.xy` as it is: no offset or repeat.
    image.offset = Vector2(0.5, 0.5)
    image.repeat = Vector2(3, 3)
    var id = assets.textures.add(image^)
    var helper = texture_helper(id, assets, meters(2), meters(2))
    assert_equal(helper.count(), 1)
    ref material = assets.materials.get(helper.materials[0])
    assert_true(material.side == DOUBLE_SIDE)
    # An alpha of one draws opaque, so its depth hides what is behind.
    assert_false(material.transparent)
    var shown = draw_parts(helper, assets)
    # Each quarter of the view is one texel, the top row at the top.
    assert_pixel(shown, 8, 8, Color(255, 0, 0))
    assert_pixel(shown, 24, 8, Color(0, 255, 0))
    assert_pixel(shown, 8, 24, Color(0, 0, 255))
    # The texel's own alpha is not read: white, not gray.
    assert_pixel(shown, 24, 24, Color(255, 255, 255))
    # Both sides are drawn. From behind, left and right trade places.
    var behind = draw_parts(helper, assets, Vector3(0, 0, -5))
    assert_pixel(behind, 24, 8, Color(255, 0, 0))


def test_a_2d_texture_stored_bottom_up_is_turned_upright() raises:
    var assets = Assets()
    var image = four_texels()
    image.flip_y = False
    var id = assets.textures.add(image^)
    var helper = texture_helper(id, assets, meters(2), meters(2))
    ref flat = assets.geometries.get(helper.geometries[0])
    var uvs = flat.attribute_view(String(UV)).copy()
    # The first corner of three.js's plane is its top left, at v = 1.
    assert_almost_equal(Float64(uvs.component(0, 1)), 0.0, atol=TOLERANCE)
    var shown = draw_parts(helper, assets)
    assert_pixel(shown, 8, 8, Color(255, 0, 0))
    assert_pixel(shown, 8, 24, Color(0, 0, 255))


def test_a_2d_texture_helper_refuses_what_it_cannot_show() raises:
    var assets = Assets()
    var blank = assets.textures.add(Texture())
    with assert_raises(contains="image"):
        _ = texture_helper(blank, assets)
    var id = assets.textures.add(four_texels())
    with assert_raises(contains="positive width"):
        _ = texture_helper(id, assets, meters(0))
    with assert_raises(contains="positive height"):
        _ = texture_helper(id, assets, meters(1), meters(-1))
    with assert_raises(contains="No texture"):
        _ = texture_helper(TextureId(9), assets)


def volume_bytes(depth: Int) -> List[UInt8]:
    """Return 2 by 2 by `depth` texels, each slice one gray level."""
    var bytes = List[UInt8]()
    for z in range(depth):
        for _ in range(4):
            var level = UInt8(40 + 80 * z)
            bytes.append(level)
            bytes.append(level)
            bytes.append(level)
            bytes.append(255)
    return bytes^


def baked(assets: Assets, helper: TextureHelper, part: Int) raises -> Texture:
    """Return a copy of one part's map."""
    var map = assets.materials.get(helper.materials[part]).map
    return Texture(copy=assets.textures.get(map))


def test_a_3d_texture_is_a_stack_of_its_slices() raises:
    var assets = Assets()
    var volume = Data3DTexture(
        VolumeImage.of_bytes(2, 2, 3, volume_bytes(3)), filter=BILINEAR
    )
    var id = assets.data_3d_textures.add(volume^)
    var helper = texture_helper(id, assets, meters(1), meters(1), meters(2))
    assert_equal(helper.count(), 3)
    # three.js's `max( 1 / depth, 0.25 )`.
    for part in range(3):
        ref slice = assets.materials.get(helper.materials[part])
        assert_almost_equal(Float64(slice.opacity), 1.0 / 3.0, atol=TOLERANCE)
        assert_true(slice.transparent)
    # Spread from -depth / 2 to depth / 2.
    assert_point(assets.geometries.get(helper.geometries[0]), 0, -0.5, 0.5, -1)
    assert_point(assets.geometries.get(helper.geometries[2]), 0, -0.5, 0.5, 1)
    # The middle slice is read at r = 0.5, the middle layer exactly; the
    # first at r = 0, which the clamp holds on the first layer.
    var levels: List[Float32] = [
        Float32(40) / 255,
        Float32(120) / 255,
        Float32(200) / 255,
    ]
    for part in range(3):
        var map = baked(assets, helper, part)
        assert_false(map.flip_y)
        var texel = map.sample(0.25, 0.25)
        assert_almost_equal(Float64(texel.r), Float64(levels[part]), atol=1e-5)
        assert_almost_equal(Float64(texel.a), 1.0, atol=TOLERANCE)


def test_a_one_slice_volume_is_read_at_the_far_end() raises:
    var assets = Assets()
    var id = assets.data_3d_textures.add(
        Data3DTexture(VolumeImage.of_bytes(2, 2, 1, volume_bytes(1)))
    )
    var helper = texture_helper(id, assets)
    assert_equal(helper.count(), 1)
    assert_almost_equal(
        Float64(assets.materials.get(helper.materials[0]).opacity),
        1.0,
        atol=TOLERANCE,
    )
    assert_point(assets.geometries.get(helper.geometries[0]), 0, -0.5, 0.5, 0)
    var texel = baked(assets, helper, 0).sample(0.5, 0.5)
    assert_almost_equal(Float64(texel.r), 40.0 / 255.0, atol=1e-5)


def test_an_array_texture_is_a_stack_of_its_layers() raises:
    var assets = Assets()
    var stack = DataArrayTexture(VolumeImage.of_bytes(2, 2, 2, volume_bytes(2)))
    var id = assets.data_array_textures.add(stack^)
    var helper = texture_helper(id, assets)
    assert_equal(helper.count(), 2)
    assert_almost_equal(
        Float64(assets.materials.get(helper.materials[1]).opacity),
        0.5,
        atol=TOLERANCE,
    )
    assert_almost_equal(
        Float64(baked(assets, helper, 1).sample(0.5, 0.5).r),
        120.0 / 255.0,
        atol=1e-5,
    )
    # A stack draws: from the front, the nearest layer over the other.
    var shown = draw_parts(helper, assets)
    assert_true(shown.get_pixel(16, 16).r > 0)


def test_a_stack_helper_refuses_bad_sizes_and_ids() raises:
    var assets = Assets()
    var volume = assets.data_3d_textures.add(
        Data3DTexture(VolumeImage.of_bytes(2, 2, 1, volume_bytes(1)))
    )
    var stack = assets.data_array_textures.add(
        DataArrayTexture(VolumeImage.of_bytes(2, 2, 1, volume_bytes(1)))
    )
    with assert_raises(contains="positive depth"):
        _ = texture_helper(volume, assets, meters(1), meters(1), meters(0))
    with assert_raises(contains="positive width"):
        _ = texture_helper(stack, assets, meters(0))
    with assert_raises(contains="positive height"):
        _ = texture_helper(stack, assets, meters(1), meters(0))
    with assert_raises(contains="positive depth"):
        _ = texture_helper(stack, assets, meters(1), meters(1), meters(0))
    with assert_raises(contains="positive width"):
        _ = texture_helper(volume, assets, meters(0))
    with assert_raises(contains="positive height"):
        _ = texture_helper(volume, assets, meters(1), meters(0))
    with assert_raises():
        _ = texture_helper(Data3DTextureId(5), assets)
    with assert_raises():
        _ = texture_helper(DataArrayTextureId(5), assets)


def solid(color: Color) raises -> Texture:
    """Return a 2 by 2 face of one color."""
    var pixels = List[UInt8]()
    for _ in range(4):
        pixels.append(color.r)
        pixels.append(color.g)
        pixels.append(color.b)
        pixels.append(255)
    return Texture(2, 2, pixels^, CLAMP, BILINEAR, SRGB, False)


def test_a_cube_texture_is_a_box_of_its_faces() raises:
    var assets = Assets()
    var colors: List[Color] = [
        Color(255, 0, 0),
        Color(0, 255, 0),
        Color(0, 0, 255),
        Color(255, 255, 0),
        Color(0, 255, 255),
        Color(255, 0, 255),
    ]
    var faces = List[Texture]()
    for color in colors:
        faces.append(solid(color))
    var id = assets.cube_textures.add(CubeTexture(faces^))
    var helper = texture_helper(id, assets)
    assert_equal(helper.count(), 6)
    ref cube = assets.cube_textures.get(id)
    # Each face of the box shows the cube in the direction of its normal.
    for part in range(6):
        ref geometry = assets.geometries.get(helper.geometries[part])
        var normal = geometry.attribute_view(String("normal")).vector3(0)
        var expected = cube.sample(normal)
        var texel = baked(assets, helper, part).sample(0.5, 0.5)
        assert_almost_equal(Float64(texel.r), Float64(expected.r), atol=1e-5)
        assert_almost_equal(Float64(texel.g), Float64(expected.g), atol=1e-5)
        assert_almost_equal(Float64(texel.b), Float64(expected.b), atol=1e-5)
        assert_almost_equal(
            Float64(assets.materials.get(helper.materials[part]).opacity),
            1.0,
            atol=TOLERANCE,
        )
    var shown = draw_parts(helper, assets)
    var front = cube.sample(Vector3(0, 0, 1)).encode()
    assert_pixel(shown, 16, 16, front)


def test_a_cube_helper_refuses_bad_sizes_and_ids() raises:
    var assets = Assets()
    with assert_raises(contains="positive width"):
        _ = texture_helper(CubeTextureId(0), assets, meters(0))
    with assert_raises(contains="positive height"):
        _ = texture_helper(CubeTextureId(0), assets, meters(1), meters(0))
    with assert_raises(contains="positive depth"):
        _ = texture_helper(
            CubeTextureId(0), assets, meters(1), meters(1), meters(0)
        )
    with assert_raises():
        _ = texture_helper(CubeTextureId(0), assets)


def test_an_empty_texture_helper_adds_nothing() raises:
    var helper = TextureHelper()
    var scene = Scene()
    var node = scene.add(Object3D())
    helper.add_to(scene, node)
    assert_equal(len(scene.meshes), 0)
    assert_equal(len(helper.meshes(node)), 0)
    var assets = Assets()
    var one = texture_helper(assets.textures.add(four_texels()), assets)
    with assert_raises(contains="scene node"):
        _ = one.meshes(NodeId(-1))


# --- ShadowMapViewer ---------------------------------------------------------

comptime MAP = 64
comptime VIEW = 96


def shadow_scene(mut assets: Assets, kind: Int = 0) raises -> Scene:
    """Return a floor, a block over it, and a light over both that casts.

    `kind` picks the light: zero for a directional light, one for a spot
    light, two for a point light, three for two directional lights.
    """
    var scene = Scene()
    var floor = scene.add(Object3D())
    var block_node = Object3D()
    block_node.set_position(0, 0.5, 0)
    var block = scene.add(block_node^)
    var lamp_node = Object3D()
    lamp_node.set_position(0, 4, 0.01)
    var lamp = scene.add(lamp_node^)
    scene.update()
    var paint = assets.materials.add(Material(Color(200, 200, 200)))
    scene.add_mesh(
        Mesh(
            assets.geometries.add(box(meters(4), meters(0.1), meters(4))),
            paint,
            floor,
            cast_shadow=True,
            receive_shadow=True,
        )
    )
    scene.add_mesh(
        Mesh(
            assets.geometries.add(box(meters(1), meters(1), meters(1))),
            paint,
            block,
            cast_shadow=True,
        )
    )
    var light = directional_light(Color(255, 255, 255), lamp)
    if kind == 1:
        light = spot_light(Color(255, 255, 255), lamp)
    elif kind == 2:
        light = point_light(Color(255, 255, 255), lamp)
    light.cast_shadow = True
    light.shadow.map_size = MAP
    light.shadow.far = meters(10)
    if kind == 3:
        var other = directional_light(Color(255, 255, 255), lamp)
        other.cast_shadow = True
        other.shadow.map_size = MAP
        scene.add_light(other)
    scene.add_light(light)
    return scene^


def test_shadow_gray_is_one_minus_the_depth() raises:
    assert_equal(shadow_gray(0), 255)
    assert_equal(shadow_gray(1), 0)
    assert_equal(shadow_gray(0.5), 128)
    # Nothing drawn reads as the far plane, and a depth is held inside.
    assert_equal(shadow_gray(inf[DType.float32]()), 0)
    assert_equal(shadow_gray(-1), 255)


def test_the_viewer_starts_where_three_puts_it() raises:
    var viewer = ShadowMapViewer(LightIndex(0))
    assert_equal(viewer.x, 10)
    assert_equal(viewer.y, 10)
    assert_equal(viewer.width, SHADOW_VIEWER_FRAME)
    assert_equal(viewer.height, SHADOW_VIEWER_FRAME)
    assert_true(viewer.enabled)
    with assert_raises(contains="light index"):
        _ = ShadowMapViewer(LightIndex(-1))


def test_the_viewer_rectangle_is_clipped_to_the_image() raises:
    var viewer = ShadowMapViewer(LightIndex(0))
    viewer.x = 10
    viewer.y = 20
    viewer.width = 30
    viewer.height = 40
    var whole = viewer.rect(100, 100)
    assert_true(Bool(whole))
    # Counted up from the bottom: rows 20 to 59 from the top.
    assert_equal(whole.value().x, 10)
    assert_equal(whole.value().y, 40)
    assert_equal(whole.value().width, 30)
    assert_equal(whole.value().height, 40)
    var cut = viewer.rect(25, 30)
    assert_equal(cut.value().x, 10)
    assert_equal(cut.value().y, 0)
    assert_equal(cut.value().width, 15)
    assert_equal(cut.value().height, 10)
    viewer.x = -5
    assert_equal(viewer.rect(100, 100).value().x, 0)
    assert_equal(viewer.rect(100, 100).value().width, 25)
    # Wholly past the right edge, or wholly below the bottom one.
    viewer.x = 10
    assert_false(Bool(viewer.rect(5, 100)))
    assert_false(Bool(viewer.rect(100, 20)))


def shadow_view(
    mut renderer: Renderer, scene: Scene, assets: Assets
) raises -> RenderTarget:
    """Return a target the size of the renderer, cleared to dark blue."""
    var target = RenderTarget(renderer.width, renderer.height, Color(0, 0, 90))
    return target^


def test_the_viewer_shows_the_map_in_gray() raises:
    var assets = Assets()
    var scene = shadow_scene(assets)
    var renderer = Renderer(VIEW, VIEW)
    var viewer = ShadowMapViewer(LightIndex(0))
    viewer.x = 4
    viewer.y = 6
    viewer.width = MAP
    viewer.height = MAP
    var target = shadow_view(renderer, scene, assets)
    viewer.render(renderer, target, scene, assets)
    var image = target.resolve(1, renderer.tone_curve(), 1)
    var maps = renderer.shadow_maps(scene, assets)
    ref depths = maps[0].depths
    # One pixel a texel, the map's top row at the top.
    var near = 255
    var far = 0
    for row in range(MAP):
        for column in range(MAP):
            var expected = shadow_gray(depths[row * MAP + column])
            var got = image.get_pixel(4 + column, 6 + row)
            assert_byte(got.r, expected)
            assert_byte(got.b, expected)
            near = min(near, Int(expected))
            far = max(far, Int(expected))
    # The map shows the block nearer than the floor.
    assert_true(far > near)
    # Outside the rectangle the image is as it was.
    assert_pixel(image, 2, 2, Color(0, 0, 90))
    assert_pixel(image, VIEW - 1, VIEW - 1, Color(0, 0, 90))
    # The renderer's scissor is as it was.
    assert_false(renderer.scissor_test)


def test_the_viewer_shows_a_spot_light() raises:
    var assets = Assets()
    var scene = shadow_scene(assets, 1)
    var renderer = Renderer(VIEW, VIEW)
    var viewer = ShadowMapViewer(LightIndex(0))
    var hud = viewer.hud(renderer, scene, assets)
    assert_equal(len(hud.scene.meshes), 1)
    # The plane is three.js's 256 pixels, scaled to the size.
    var node = hud.scene.get(hud.scene.meshes[0].node)
    assert_almost_equal(Float64(node.scale.x), 1.0, atol=TOLERANCE)
    assert_almost_equal(
        Float64(node.position.x), -48.0 + 128.0 + 10.0, atol=TOLERANCE
    )
    assert_almost_equal(
        Float64(node.position.y), 48.0 - 128.0 - 10.0, atol=TOLERANCE
    )


def test_the_viewer_picks_its_own_light_of_several() raises:
    var assets = Assets()
    var scene = shadow_scene(assets, 3)
    var renderer = Renderer(VIEW, VIEW)
    var viewer = ShadowMapViewer(LightIndex(1))
    var hud = viewer.hud(renderer, scene, assets)
    assert_equal(hud.assets.textures.get(TextureId(0)).width, MAP)


def test_the_viewer_draws_nothing_when_off_or_away() raises:
    var assets = Assets()
    var scene = shadow_scene(assets)
    var renderer = Renderer(VIEW, VIEW)
    var viewer = ShadowMapViewer(LightIndex(0))
    viewer.enabled = False
    var target = shadow_view(renderer, scene, assets)
    viewer.render(renderer, target, scene, assets)
    viewer.enabled = True
    viewer.x = VIEW
    viewer.render(renderer, target, scene, assets)
    var image = target.resolve(1, renderer.tone_curve(), 1)
    assert_pixel(image, 20, 20, Color(0, 0, 90))


def test_the_viewer_refuses_what_it_cannot_show() raises:
    var assets = Assets()
    var scene = shadow_scene(assets)
    var renderer = Renderer(VIEW, VIEW)
    var viewer = ShadowMapViewer(LightIndex(1))
    with assert_raises(contains="light of the scene"):
        _ = viewer.hud(renderer, scene, assets)
    viewer.light = LightIndex(-1)
    with assert_raises(contains="light of the scene"):
        _ = viewer.hud(renderer, scene, assets)
    viewer.light = LightIndex(0)
    viewer.width = 0
    with assert_raises(contains="positive size"):
        _ = viewer.hud(renderer, scene, assets)
    viewer.width = 10
    viewer.height = 0
    with assert_raises(contains="positive size"):
        _ = viewer.hud(renderer, scene, assets)
    viewer.height = 10
    renderer.shadow_map_type = VSM_SHADOW_MAP
    with assert_raises(contains="variance"):
        _ = viewer.hud(renderer, scene, assets)
    renderer = Renderer(VIEW, VIEW)
    scene.lights[0].cast_shadow = False
    with assert_raises(contains="casts"):
        _ = viewer.hud(renderer, scene, assets)
    var bulb = shadow_scene(assets, 2)
    with assert_raises(contains="directional or a spot"):
        _ = viewer.hud(renderer, bulb, assets)
    # A target of another size is refused, and the scissor is put back.
    scene.lights[0].cast_shadow = True
    var small = RenderTarget(8, 8, Color(0, 0, 0))
    with assert_raises(contains="renderer's size"):
        viewer.render(renderer, small, scene, assets)
    assert_false(renderer.scissor_test)
    assert_equal(renderer.scissor.width, VIEW)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
