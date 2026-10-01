# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Regressions for shadow ownership, layers and bounded triangle jobs."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION, UV, UV1
from core.layers import Layers
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.box import cube
from geometries.plane import plane
from lights.light import directional_light, point_light, spot_light
from materials.material import DOUBLE_SIDE, GOURAUD, LAMBERT, VOLUME, Material
from materials.volume_node_material import volume_node_material
from math.bounds import Plane
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, Framebuffer
from render.target import RenderTarget
from renderers.environment import scene_cube
from renderers.renderer import Frame, PENDING_VERTICES, Renderer
from std.testing import TestSuite, assert_equal, assert_true
from units.si import Angle, DEGREE, Length, METER

comptime SIZE = 16
comptime WHITE = Color(255, 255, 255)


def camera() raises -> PerspectiveCamera:
    """Return a camera four meters in front of the origin."""
    var eye = PerspectiveCamera(
        Angle(60, DEGREE), 1, Length(0.1, METER), Length(20, METER)
    )
    eye.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    return eye^


def shadow_scene(mut assets: Assets, kind: Int) raises -> Scene:
    """Return a layer-three cube lit by one casting light on every layer."""
    var scene = Scene()
    var object = Object3D()
    object.layers.set(3)
    scene.add_mesh(
        Mesh(
            assets.geometries.add(cube(Length(1, METER))),
            assets.materials.add(Material(WHITE)),
            scene.add(object^),
            cast_shadow=True,
        )
    )
    var lamp = Object3D()
    lamp.set_position(0, 0, 4)
    var node = scene.add(lamp^)
    var light = directional_light(WHITE, node, 2)
    if kind == 1:
        light = point_light(WHITE, node, 2)
    elif kind == 2:
        light = spot_light(WHITE, node, 2)
    light.layers = Layers.all()
    light.cast_shadow = True
    light.shadow.map_size = 32
    scene.add_light(light)
    scene.update()
    return scene^


def test_shadow_casters_use_the_view_layers_for_every_light() raises:
    var renderer = Renderer(SIZE, SIZE)
    for kind in range(3):
        var assets = Assets()
        var scene = shadow_scene(assets, kind)
        var layer = Layers()
        layer.set(3)
        var hidden = renderer.shadow_maps(scene, assets, Layers())
        var visible = renderer.shadow_maps(scene, assets, layer)
        assert_equal(len(hidden), 1)
        assert_equal(len(visible), 1)
        var count = 0
        for slot in range(len(visible[0].depths)):
            # Flat maps clear to infinity; point maps clear to one.
            assert_true(hidden[0].depths[slot] >= 1)
            if visible[0].depths[slot] < 1:
                count += 1
        assert_true(count > 0, "no caster for light kind " + String(kind))


def test_cube_capture_skips_shadow_lights_outside_its_layers() raises:
    var scene = Scene()
    # Hidden lights do not read their scene nodes, just as Lighting skips
    # them. An all-layer shadow pass used to try to resolve this node.
    var hidden = directional_light(WHITE, NodeId(123))
    hidden.layers.set(3)
    hidden.cast_shadow = True
    hidden.shadow.map_size = 4
    scene.add_light(hidden)
    scene.update()
    var assets = Assets()
    var captured = scene_cube(Renderer(4, 4), scene, assets, size=4)
    assert_equal(len(captured.faces), 6)


def test_transferred_shadow_maps_keep_their_texel_storage() raises:
    var assets = Assets()
    var scene = shadow_scene(assets, 0)
    var renderer = Renderer(SIZE, SIZE)
    var eye = camera()
    eye.layers.set(3)
    var maps = renderer.shadow_maps(scene, assets, eye.layers)
    var address = Int(maps[0].depths.unsafe_ptr())
    var target = RenderTarget(SIZE, SIZE, Color(0, 0, 0))
    for _ in range(6):
        maps = renderer.render_into_reusing_shadows(
            target, scene, assets, eye, maps^
        )
        assert_equal(Int(maps[0].depths.unsafe_ptr()), address)
    # Borrowed callers keep an independent copy, as before.
    renderer.render_into_with_shadows(target, scene, assets, eye, maps)
    assert_equal(Int(maps[0].depths.unsafe_ptr()), address)


def same_frame(a: Frame, b: Frame) raises:
    """Compare ordered positions, lighting, UVs, normals and draw spans."""
    var first = a.whole_corners()
    var second = b.whole_corners()
    assert_equal(len(first), len(second))
    assert_true(len(first) > 0)
    for slot in range(len(first)):
        ref x = first[slot]
        ref y = second[slot]
        assert_equal(x.x, y.x)
        assert_equal(x.y, y.y)
        assert_equal(x.z, y.z)
        assert_equal(x.inv_w, y.inv_w)
        assert_equal(x.color.r, y.color.r)
        assert_equal(x.color.g, y.color.g)
        assert_equal(x.color.b, y.color.b)
        assert_equal(x.color.a, y.color.a)
        assert_equal(x.u, y.u)
        assert_equal(x.v, y.v)
        assert_equal(x.u1, y.u1)
        assert_equal(x.v1, y.v1)
        assert_equal(x.normal.x, y.normal.x)
        assert_equal(x.normal.y, y.normal.y)
        assert_equal(x.normal.z, y.normal.z)
        assert_equal(x.world.x, y.world.x)
        assert_equal(x.world.y, y.world.y)
        assert_equal(x.world.z, y.world.z)
        assert_equal(x.kind, y.kind)
    assert_equal(len(a.draws), len(b.draws))
    for slot in range(len(a.draws)):
        assert_equal(a.draws[slot].kind, b.draws[slot].kind)
        assert_equal(a.draws[slot].first, b.draws[slot].first)
        assert_equal(a.draws[slot].count, b.draws[slot].count)


def same_image(a: Framebuffer, b: Framebuffer) raises:
    """Compare every output channel exactly."""
    for y in range(SIZE):
        for x in range(SIZE):
            var first = a.get_pixel(x, y)
            var second = b.get_pixel(x, y)
            assert_equal(first.r, second.r)
            assert_equal(first.g, second.g)
            assert_equal(first.b, second.b)
            assert_equal(first.a, second.a)


def test_parallel_jobs_keep_gouraud_clips_and_uv_space_identical() raises:
    var assets = Assets()
    var scene = Scene()
    # 4608 triangles force multiple pieces inside one draw.
    var sheet = plane(Length(3, METER), Length(3, METER), 48, 48)
    var uv1 = sheet.clone_attribute(UV)
    for index in range(uv1.count()):
        uv1.set_component(index, 0, 0.15 + 0.7 * uv1.component(index, 0))
        uv1.set_component(index, 1, 0.1 + 0.6 * uv1.component(index, 1))
    sheet.set_attribute(String(UV1), uv1^)
    var geometry = assets.geometries.add(sheet^)
    var material = Material(Color(180, 120, 70), kind=GOURAUD, side=DOUBLE_SIDE)
    material.set_clipping_planes([Plane(Vector3(0, 1, 0), 0.4)])
    scene.add_mesh(
        Mesh(geometry, assets.materials.add(material), scene.add(Object3D()))
    )
    var lamp = Object3D()
    lamp.set_position(0.4, 0.5, 1)
    scene.add_light(point_light(WHITE, scene.add(lamp^), 4))
    scene.update()
    for uv in [False, True]:
        var one = Renderer(SIZE, SIZE)
        var many = Renderer(SIZE, SIZE, workers=4)
        one.local_clipping_enabled = True
        many.local_clipping_enabled = True
        one.clipping_planes.append(Plane(Vector3(1, 0, 0), 0.3))
        many.clipping_planes = one.clipping_planes.copy()
        if uv:
            one.uv_space_meshes.append(0)
            many.uv_space_meshes.append(0)
        same_frame(
            one.prepare_frame(scene, assets, camera()),
            many.prepare_frame(scene, assets, camera()),
        )
        same_image(
            one.render(scene, assets, camera()),
            many.render(scene, assets, camera()),
        )


def test_parallel_jobs_flush_before_and_after_a_volume() raises:
    var assets = Assets()
    var scene = Scene()
    var sheet = assets.geometries.add(
        plane(Length(3, METER), Length(3, METER), 48, 48)
    )
    var paint = assets.materials.add(
        Material(
            Color(90, 120, 180), kind=LAMBERT, transparent=True, opacity=0.4
        )
    )
    for index in range(3):
        var node = Object3D()
        node.set_position(0, 0, Float32(index - 1))
        node.render_order = index
        if index == 1:
            scene.add_mesh(
                Mesh(
                    assets.geometries.add(cube(Length(1, METER))),
                    assets.materials.add(volume_node_material(steps=4)),
                    scene.add(node^),
                )
            )
        else:
            scene.add_mesh(Mesh(sheet, paint, scene.add(node^)))
    var lamp = scene.add(Object3D())
    scene.add_light(point_light(WHITE, lamp, 3))
    scene.update()
    var one = Renderer(SIZE, SIZE)
    var many = Renderer(SIZE, SIZE, workers=4)
    var prepared = many.prepare_frame(scene, assets, camera())
    var volume_corners = 0
    for corner in prepared.whole_corners():
        if corner.kind == VOLUME:
            volume_corners += 1
    assert_true(volume_corners > 0)
    assert_equal(len(prepared.draws), 3)
    same_frame(one.prepare_frame(scene, assets, camera()), prepared)
    same_image(
        one.render(scene, assets, camera()),
        many.render(scene, assets, camera()),
    )


def test_vertex_budget_flushes_keep_draw_order() raises:
    var assets = Assets()
    var scene = Scene()
    # A small index stream with many retained vertices exercises the
    # memory bound without making the raster output large.
    for count in [PENDING_VERTICES // 2 + 1, PENDING_VERTICES + 1, 3]:
        var positions = List[Float32]()
        for index in range(count):
            positions.append(Float32(index % 3) - 1)
            positions.append(Float32(1 if index % 3 == 1 else -1))
            positions.append(0)
        var geometry = BufferGeometry()
        geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
        geometry.set_index([0, 2, 1])
        scene.add_mesh(
            Mesh(
                assets.geometries.add(geometry^),
                assets.materials.add(Material(WHITE, side=DOUBLE_SIDE)),
                scene.add(Object3D()),
            )
        )
    scene.update()
    same_frame(
        Renderer(SIZE, SIZE).prepare_frame(scene, assets, camera()),
        Renderer(SIZE, SIZE, workers=4).prepare_frame(scene, assets, camera()),
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
