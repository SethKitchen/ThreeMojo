# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""three.js's `ProgressiveLightMap`: the meshes packed into one map, their
light drawn into it in texture space and mixed frame by frame, the blur
of the padding, and the renderer's texture-space draw itself."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.background import texture_background
from core.buffer_geometry import UV, UV1
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import box
from geometries.plane import plane
from lights.light import directional_light
from materials.material import (
    BASIC,
    NORMALS,
    Material,
    MaterialId,
    line_material,
    points_material,
)
from math.vector3 import Vector3
from objects.line import Line
from objects.mesh import Mesh
from objects.points import Points
from render.framebuffer import Color, Framebuffer
from render.texture import UV_CHANNEL_0, UV_CHANNEL_1, texture_of
from render.texture_store import TextureId
from renderers.progressive_light_map import ProgressiveLightMap
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


comptime SIZE = 32


def a_camera() raises -> PerspectiveCamera:
    """Return a camera in front of the planes."""
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE), 1, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    return camera^


def two_planes(mut assets: Assets, mut scene: Scene) raises:
    """Add a plane that faces the light and one that faces away, each with
    its own node and lambert material, and a light in front of them."""
    var facing = assets.geometries.add(plane(Length(1, METER), Length(1, METER)))
    var turned = plane(Length(1, METER), Length(1, METER))
    turned.rotate_y(Angle(180, DEGREE))
    var away = assets.geometries.add(turned^)
    for geometry in [facing, away]:
        scene.add_mesh(
            Mesh(
                geometry,
                assets.materials.add(Material(Color(255, 255, 255))),
                scene.add(Object3D()),
            )
        )
    var lamp = Object3D()
    lamp.set_position(0, 0, 5)
    var lamp_node = scene.add(lamp^)
    scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 1.0))
    scene.update()


def texel(assets: Assets, map: TextureId, x: Int, row: Int) raises -> Float32:
    """Return a map's red at a texel, its row counted from the top."""
    ref texture = assets.textures.get(map)
    return texture.data[(row * texture.width + x) * 4]


def test_a_resolution_must_be_positive() raises:
    var assets = Assets()
    with assert_raises(contains="resolution must be positive"):
        _ = ProgressiveLightMap(assets, 0)


def test_the_maps_start_black_and_the_second_reads_uv1() raises:
    var assets = Assets()
    var light_map = ProgressiveLightMap(assets, SIZE)
    assert_equal(len(light_map.maps), 2)
    ref first = assets.textures.get(light_map.maps[0])
    ref second = assets.textures.get(light_map.maps[1])
    assert_equal(first.width, SIZE)
    assert_equal(first.data[0], 0)
    assert_true(first.channel == UV_CHANNEL_0)
    assert_true(second.channel == UV_CHANNEL_1)


def test_the_meshes_are_packed_into_the_map() raises:
    var assets = Assets()
    var scene = Scene()
    two_planes(assets, scene)
    var light_map = ProgressiveLightMap(assets, SIZE)
    light_map.add_objects_to_light_map(scene, assets, [0, 1])
    assert_equal(len(light_map.meshes), 2)
    # Two squares of 1 + 6 / 32 pack one above the other: the map is
    # 1.1875 wide and 2.375 tall in those units.
    var padding = Float32(3) / SIZE
    ref first = assets.geometries.get(scene.meshes[0].geometry)
    ref second = assets.geometries.get(scene.meshes[1].geometry)
    var uv1 = first.clone_attribute(UV1)
    var uv = first.clone_attribute(UV)
    for vertex in range(uv.count()):
        assert_almost_equal(
            uv1.component(vertex, 0),
            (uv.component(vertex, 0) + padding) / 1.1875,
            atol=1e-6,
        )
        assert_almost_equal(
            uv1.component(vertex, 1),
            (uv.component(vertex, 1) + padding) / 2.375,
            atol=1e-6,
        )
    var above = second.clone_attribute(UV1)
    var lowest = Float32(1)
    for vertex in range(above.count()):
        lowest = min(lowest, above.component(vertex, 1))
    assert_almost_equal(lowest, (1.1875 + padding) / 2.375, atol=1e-6)
    # Each material reads the second map, dithered, and each mesh casts
    # and receives shadows and draws after the rest, in order.
    for index in range(2):
        var material = assets.materials.get(scene.meshes[index].material)
        assert_true(material.light_map == light_map.maps[1])
        assert_true(material.dithering)
        assert_true(scene.meshes[index].cast_shadow)
        assert_true(scene.meshes[index].receive_shadow)
        assert_equal(scene.render_order(scene.meshes[index].node), 1000 + index)


def test_a_mesh_the_map_cannot_hold_is_refused() raises:
    var assets = Assets()
    var scene = Scene()
    two_planes(assets, scene)
    var light_map = ProgressiveLightMap(assets, SIZE)
    with assert_raises(contains="not in the scene"):
        light_map.add_objects_to_light_map(scene, assets, [2])
    with assert_raises(contains="not in the scene"):
        light_map.add_objects_to_light_map(scene, assets, [-1])
    # A geometry with no uv.
    var bare = box(Length(1, METER), Length(1, METER), Length(1, METER))
    bare.delete_attribute(UV)
    scene.add_mesh(
        Mesh(
            assets.geometries.add(bare^),
            scene.meshes[0].material,
            scene.meshes[0].node,
        )
    )
    with assert_raises(contains="needs a uv"):
        light_map.add_objects_to_light_map(scene, assets, [2])
    # A material with no light map to read.
    scene.add_mesh(
        Mesh(
            scene.meshes[0].geometry,
            assets.materials.add(Material(Color(255, 255, 255), kind=NORMALS)),
            scene.meshes[0].node,
        )
    )
    with assert_raises(contains="basic or lit material"):
        light_map.add_objects_to_light_map(scene, assets, [3])
    var wire = Material(Color(0, 0, 0), kind=BASIC, wireframe=True)
    scene.add_mesh(
        Mesh(
            scene.meshes[0].geometry,
            assets.materials.add(wire),
            scene.meshes[0].node,
        )
    )
    with assert_raises(contains="basic or lit material"):
        light_map.add_objects_to_light_map(scene, assets, [4])


def test_an_update_before_any_mesh_does_nothing() raises:
    var assets = Assets()
    var scene = Scene()
    two_planes(assets, scene)
    var light_map = ProgressiveLightMap(assets, SIZE)
    light_map.update(Renderer(8, 8), scene, assets, a_camera())
    assert_false(light_map.buffer1_active)
    assert_equal(texel(assets, light_map.maps[1], 16, 24), 0)
    with assert_raises(contains="blend window must be positive"):
        light_map.update(Renderer(8, 8), scene, assets, a_camera(), 0)
    with assert_raises(contains="blend window must be positive"):
        light_map.update(
            Renderer(8, 8), scene, assets, a_camera(), Float32.MAX * 2
        )


def test_each_update_mixes_the_light_into_the_other_map() raises:
    var assets = Assets()
    var scene = Scene()
    two_planes(assets, scene)
    var materials: List[MaterialId] = [
        scene.meshes[0].material,
        scene.meshes[1].material,
    ]
    var light_map = ProgressiveLightMap(assets, SIZE)
    light_map.add_objects_to_light_map(scene, assets, [0, 1])
    var renderer = Renderer(8, 8)
    # Half the light at a time. The facing plane's middle is texel
    # (16, 24) from the top; the turned one's is (16, 8), and it is dark.
    light_map.update(renderer, scene, assets, a_camera(), 2)
    assert_true(light_map.buffer1_active)
    var half = texel(assets, light_map.maps[1], 16, 24)
    assert_true(half > 0.05)
    assert_equal(texel(assets, light_map.maps[1], 16, 8), 0)
    assert_equal(texel(assets, light_map.maps[0], 16, 24), 0)
    # The second draws into the first map, reading the second where each
    # fragment is: half of a half more.
    light_map.update(renderer, scene, assets, a_camera(), 2)
    assert_false(light_map.buffer1_active)
    assert_almost_equal(
        texel(assets, light_map.maps[0], 16, 24), half * 1.5, rtol=1e-4
    )
    # The meshes have their own materials back.
    assert_true(scene.meshes[0].material == materials[0])
    assert_true(scene.meshes[1].material == materials[1])


def test_the_padding_takes_the_color_beside_it() raises:
    var assets = Assets()
    var scene = Scene()
    two_planes(assets, scene)
    var light_map = ProgressiveLightMap(assets, SIZE)
    light_map.add_objects_to_light_map(scene, assets, [0])
    var renderer = Renderer(8, 8)
    light_map.update(renderer, scene, assets, a_camera(), 1)
    # The plane covers the rows from 2.5 to 29.5. Row 30 is padding:
    # blurred from the row above it, it is lit.
    light_map.update(renderer, scene, assets, a_camera(), 1)
    assert_true(texel(assets, light_map.maps[0], 16, SIZE - 2) > 0.01)
    # Unblurred, it is black.
    light_map.update(renderer, scene, assets, a_camera(), 1, False)
    assert_equal(texel(assets, light_map.maps[1], 16, SIZE - 2), 0)
    assert_true(texel(assets, light_map.maps[1], 16, 24) > 0.05)


def test_the_map_draws_no_background_line_point_or_other_mesh() raises:
    var assets = Assets()
    var scene = Scene()
    two_planes(assets, scene)
    # A box in front of the planes, a line, points and a background: none
    # is drawn into the map, and the box casts no shade on it here.
    var node = scene.add(Object3D())
    var solid = box(Length(1, METER), Length(1, METER), Length(1, METER))
    var cube = assets.geometries.add(solid.clone())
    var loose = assets.geometries.add(solid.to_non_indexed())
    scene.add_mesh(
        Mesh(cube, assets.materials.add(Material(Color(255, 0, 0))), node)
    )
    scene.add_line(
        Line(loose, assets.materials.add(line_material(Color(255, 0, 0))), node)
    )
    scene.add_points(
        Points(
            loose, assets.materials.add(points_material(Color(255, 0, 0))), node
        )
    )
    scene.background = texture_background(
        assets.textures.add(texture_of(Framebuffer(2, 2, Color(0, 255, 0))))
    )
    var light_map = ProgressiveLightMap(assets, SIZE)
    light_map.add_objects_to_light_map(scene, assets, [0])
    light_map.update(Renderer(8, 8), scene, assets, a_camera(), 1, False)
    ref map = assets.textures.get(light_map.maps[1])
    for slot in range(SIZE * SIZE):
        # No green from the background, and no red alone from the box.
        assert_equal(map.data[slot * 4 + 1], map.data[slot * 4])
    # The renderer the map drew with was a copy: this one still draws the
    # scene through the camera.
    var seen = Renderer(8, 8).render(scene, assets, a_camera())
    assert_true(seen.get_pixel(4, 4).r > 0)


def test_the_debug_plane_shows_the_first_map() raises:
    var assets = Assets()
    var scene = Scene()
    two_planes(assets, scene)
    var light_map = ProgressiveLightMap(assets, SIZE)
    with assert_raises(contains="after adding the meshes"):
        light_map.show_debug_light_map(scene, assets, True)
    light_map.add_objects_to_light_map(scene, assets, [0, 1])
    var meshes = len(scene.meshes)
    light_map.show_debug_light_map(scene, assets, True)
    assert_equal(len(scene.meshes), meshes + 1)
    var label = light_map.label.value()
    assert_true(scene.get(label).visible)
    assert_almost_equal(scene.get(label).position.y, 250)
    var shows = assets.materials.get(scene.meshes[meshes].material)
    assert_true(shows.map == light_map.maps[0])
    assert_true(shows.kind == BASIC)
    # Again: moved and hidden, and no second plane.
    light_map.show_debug_light_map(scene, assets, False, Vector3(1, 2, 3))
    assert_equal(len(scene.meshes), meshes + 1)
    assert_false(scene.get(label).visible)
    assert_almost_equal(scene.get(label).position.z, 3)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
