# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Regression cases for the audit's shared layouts and integrated splats."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D, NodeId
from core.scene import Scene
from core.scene_optimizer import _carries
from exporters.gltf import export_gltf
from exporters.object_json import object_to_json
from geometries.plane import plane
from loaders.gltf_layout import AccessorLayout, check_buffer_range
from loaders.gltf_gaussian_splat import (
    _read_accessor,
    load_gltf_gaussian_splat_scene,
    read_gltf_gaussian_splat_scene,
)
from std.pathlib import Path
from loaders.json import parse_json
from materials.material import Material, BASIC, NORMALS
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from render.raster_state import STANDARD_DEPTH
from render.rasterizer import DRAW_SPLATS, DRAW_TRIANGLES, Draw, check_draws
from render.rasterizer import check_output_kinds
from render.rect import Rect
from render.splat_raster import prepare_gaussian_splat, draw_gaussian_splat
from render.target import RenderTarget
from renderers.renderer import Renderer
from std.testing import (
    TestSuite,
    assert_equal,
    assert_true,
    assert_almost_equal,
    assert_raises,
)
from test_gaussian_splat import one_red_splat
from test_gaussian_splat_loaders import zeros, put_u32
from units.si import Angle, DEGREE, Length, METER


def camera() raises -> PerspectiveCamera:
    var out = PerspectiveCamera(
        Angle(90, DEGREE), 1, Length(1, METER), Length(100, METER)
    )
    out.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    return out^


def test_shared_layout_keeps_matrix_padding_and_checks_zero_stride() raises:
    var layout = AccessorLayout("MAT2", 1)
    assert_equal(layout.width, 4)
    assert_equal(layout.element_size, 8)
    assert_equal(layout.occupied_size, 6)
    var offsets = layout.offsets()
    assert_equal(offsets[2], 4)
    var span = layout.span(2, 0, 0, 14, 0, False)
    assert_equal(span[1], 8)
    with assert_raises():
        _ = layout.span(2, 0, 0, 14, 0, True)
    with assert_raises():
        _ = layout.span(2, 0, 0, 13, 0, False)
    with assert_raises():
        layout.check(9223372036854775807, 0)
    with assert_raises():
        check_buffer_range(8, 4, 9223372036854775807)


def test_sparse_splats_keep_uint32_precision_and_implicit_zeros() raises:
    var document = parse_json(
        '{"accessors":[{"componentType":5125,"count":3,"type":"SCALAR","sparse":{"count":1,"indices":{"bufferView":0,"componentType":5121},"values":{"bufferView":1}}}],"bufferViews":[{"buffer":0,"byteLength":1},{"buffer":0,"byteOffset":4,"byteLength":4}]}'
    )
    var bytes = zeros(8)
    bytes[0] = 1
    put_u32(bytes, 4, 16777217)
    var buffers: List[List[UInt8]] = [bytes^]
    var got = _read_accessor(document, buffers, 0)
    assert_equal(got.values[0], 0)
    assert_equal(got.values[1], 16777217)
    assert_equal(got.values[2], 0)
    buffers[0][0] = 3
    with assert_raises(contains="inside"):
        _ = _read_accessor(document, buffers, 0)


def test_viewport_projects_at_its_own_size_and_offset() raises:
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    var splat = one_red_splat(scene, node)
    var eye = camera()
    var original = prepare_gaussian_splat(
        scene, splat, eye, 16, 16, STANDARD_DEPTH
    )
    var placed = prepare_gaussian_splat(
        scene, splat, eye, 40, 40, STANDARD_DEPTH, Rect(4, 5, 16, 16)
    )
    assert_equal(len(placed), 1)
    assert_almost_equal(placed[0].x, original[0].x + 4)
    assert_almost_equal(placed[0].y, original[0].y + 19)
    assert_equal(placed[0].scale1, original[0].scale1)
    with assert_raises(contains="viewport"):
        _ = prepare_gaussian_splat(
            scene, splat, eye, 40, 40, STANDARD_DEPTH, Rect(0, 0, 0, 1)
        )


def test_scene_splats_render_in_the_transparent_list_and_clone_independently() raises:
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    scene.add_gaussian_splat(one_red_splat(scene, node))
    assert_true(_carries(scene, node))
    var assets = Assets()
    var geometry = assets.geometries.add(
        plane(Length(4, METER), Length(4, METER))
    )
    var material = assets.materials.add(
        Material(Color(0, 255, 0), opacity=0.5, kind=BASIC, transparent=True)
    )
    var front = Object3D()
    front.set_position(0, 0, 1)
    var near = scene.add(front^)
    scene.add_mesh(Mesh(geometry, material, near))
    scene.update()
    var renderer = Renderer(16, 16)
    var eye = camera()
    var frame = renderer.prepare_frame(scene, assets, eye)
    assert_equal(len(frame.splats), 1)
    assert_true(frame.draws[0].kind == DRAW_SPLATS)
    assert_true(frame.draws[1].kind == DRAW_TRIANGLES)
    assert_equal(DRAW_SPLATS.stride(), 1)
    var single = renderer.render(scene, assets, eye)
    renderer.workers = 3
    var parallel = renderer.render(scene, assets, eye)
    for y in range(16):
        for x in range(16):
            var a = single.get_pixel(x, y)
            var b = parallel.get_pixel(x, y)
            assert_equal(a.r, b.r)
            assert_equal(a.g, b.g)
            assert_equal(a.b, b.b)
    var center = single.get_pixel(8, 8)
    assert_true(center.r > 0 and center.g > 0)
    frame.surfaces[frame.corners[0].surface].kind = NORMALS
    with assert_raises(contains="tone-mapped frame"):
        check_output_kinds(frame.surfaces, True, splats=True)
    check_output_kinds(frame.surfaces, False, splats=True)
    var copied = scene.clone(node)
    assert_equal(len(scene.gaussian_splats), 2)
    scene.gaussian_splats[1][].splat_geometry.colors[0] = 0
    assert_equal(scene.gaussian_splats[0][].splat_geometry.colors[0], 255)
    assert_true(scene.gaussian_splats[1][].node == copied)


def test_splat_draw_ranges_cannot_wrap() raises:
    var draws: List[Draw] = [Draw(DRAW_SPLATS, 0, 1)]
    check_draws(draws, 0, 0, 0, 1)
    with assert_raises():
        check_draws(draws, 0, 0, 0, 0)
    draws[0] = Draw(DRAW_SPLATS, 1, 9223372036854775807)
    with assert_raises():
        check_draws(draws, 0, 0, 0, 1)


def test_gltf_splat_nodes_keep_hierarchy_names_and_instance_geometry() raises:
    var text = Path("assets/gaussian_splat/splats.gltf").read_text()
    var scene = Scene()
    var nodes = load_gltf_gaussian_splat_scene(text, List[UInt8](), "", scene)
    assert_equal(len(nodes), 4)
    assert_equal(len(scene.gaussian_splats), 4)
    var from_file = Scene()
    var read_nodes = read_gltf_gaussian_splat_scene(
        "assets/gaussian_splat/splats.glb", from_file
    )
    assert_equal(len(read_nodes), 4)
    assert_equal(len(from_file.gaussian_splats), 4)
    # Replace only the node array; the source geometry remains the fixture.
    var begin = text.find('"nodes": [')
    var altered = (
        String(text[byte=:begin])
        + '"nodes":[{"name":"splats","translation":[2,0,0],"mesh":0,"children":[1]},'
        '{"name":"splats","translation":[0,3,0],"mesh":0}],'
        '"scenes":[{"nodes":[0]}],"scene":0}'
    )
    var placed = Scene()
    var ids = load_gltf_gaussian_splat_scene(altered, List[UInt8](), "", placed)
    assert_equal(len(placed.gaussian_splats), 2)
    var world = placed.world_matrix(ids[1]).transform_point(Vector3(0, 0, 0))
    assert_almost_equal(world.x, 2)
    assert_almost_equal(world.y, 3)
    assert_equal(placed.get(ids[0]).name, "splats")
    assert_equal(placed.get(ids[1]).name, "splats_1")
    placed.gaussian_splats[1][].splat_geometry.colors[0] = 0
    assert_true(placed.gaussian_splats[0][].splat_geometry.colors[0] != 0)
    with assert_raises(contains="reached twice"):
        var bad = Scene()
        _ = load_gltf_gaussian_splat_scene(
            '{"nodes":[{"children":[0]}],"scenes":[{"nodes":[0]}]}',
            List[UInt8](),
            "",
            bad,
        )


def test_exporters_refuse_to_silently_drop_registered_splats() raises:
    var scene = Scene()
    var assets = Assets()
    _ = object_to_json(scene, assets)
    _ = export_gltf(scene, assets)
    var node = scene.add(Object3D())
    scene.update()
    scene.add_gaussian_splat(one_red_splat(scene, node))
    with assert_raises(contains="cannot serialize Gaussian splats"):
        _ = object_to_json(scene, assets)
    with assert_raises(contains="cannot serialize Gaussian splats"):
        _ = export_gltf(scene, assets)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
