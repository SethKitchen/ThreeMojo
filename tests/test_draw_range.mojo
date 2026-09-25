# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the readers of a geometry's draw range and of its integer
attributes: the renderer, the raycaster, scene JSON and glTF.

three.js's `renderBufferDirect` draws, and its `raycast` methods pick, only
what `drawRange` lets through. Scene JSON carries a geometry's `name` and
`userData` and its typed arrays, and glTF carries quantized attributes in
their own component types.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import (
    BufferAttribute,
    array_type_name,
    component_of_array,
)
from core.buffer_geometry import (
    COLOR,
    NORMAL,
    POSITION,
    UV,
    UV1,
    BufferGeometry,
    MaterialIndex,
)
from core.object3d import NodeId, Object3D
from core.raycaster import Raycaster
from core.scene import Scene
from exporters.gltf import GLTF_EMBEDDED, export_gltf
from exporters.object_json import object_to_json
from loaders.gltf import load_gltf
from loaders.object_loader import read_object_json
from materials.material import (
    BASIC,
    DOUBLE_SIDE,
    Material,
    MaterialId,
    points_material,
)
from math.utils import (
    ComponentType,
    FLOAT32_COMPONENT,
    INT16_COMPONENT,
    INT32_COMPONENT,
    INT8_COMPONENT,
    UINT16_COMPONENT,
    UINT32_COMPONENT,
    UINT8_COMPONENT,
)
from math.vector3 import Vector3
from objects.line import LOOP, SEGMENTS, STRIP, Line
from objects.mesh import Mesh
from objects.points import Points
from render.framebuffer import Color
from renderers.renderer import Renderer
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER


def _strip(triangles: Int) raises -> BufferGeometry:
    """Return triangles side by side along x, facing +z, without an index:
    triangle `t` covers x from `2t` to `2t + 1`."""
    var numbers = List[Float32]()
    for triangle in range(triangles):
        var left = Float32(2 * triangle)
        for corner in [
            Vector3(left, -0.5, 0),
            Vector3(left + 1, -0.5, 0),
            Vector3(left + 0.5, 0.5, 0),
        ]:
            numbers.append(corner.x)
            numbers.append(corner.y)
            numbers.append(corner.z)
    var geometry = BufferGeometry()
    geometry.set_attribute(POSITION, BufferAttribute(numbers^, 3))
    return geometry^


def _camera() raises -> PerspectiveCamera:
    """Return a camera far enough up +z to see the whole strip."""
    var camera = PerspectiveCamera(
        Angle(60.0, DEGREE), 1.0, Length(0.5, METER), Length(50.0, METER)
    )
    camera.place(Vector3(4, 0, 12), Vector3(4, 0, 0))
    return camera^


def _basic(mut assets: Assets, wireframe: Bool = False) raises -> MaterialId:
    """Add an unlit, two-sided material and return its id."""
    return assets.materials.add(
        Material(
            Color(255, 255, 255),
            kind=BASIC,
            side=DOUBLE_SIDE,
            wireframe=wireframe,
        )
    )


def _scene_of(mut scene: Scene) raises -> NodeId:
    """Add one node at the origin and update the scene."""
    var node = scene.add(Object3D())
    scene.update()
    return node


def _pick_at(x: Float32) raises -> Raycaster:
    """Return a ray down -z through (x, 0), a tenth of a meter wide for
    lines and points."""
    var ray = Raycaster(Vector3(x, 0, 5), Vector3(0, 0, -1))
    ray.line_threshold = Length(0.1, METER)
    ray.points_threshold = Length(0.1, METER)
    return ray^


# --- meshes -----------------------------------------------------------------


def test_the_renderer_draws_only_the_range() raises:
    var assets = Assets()
    var geometry = _strip(4)
    geometry.set_draw_range(3, 6)
    var strip = assets.geometries.add(geometry^)
    var paint = _basic(assets)
    var scene = Scene()
    var node = _scene_of(scene)
    scene.add_mesh(Mesh(strip, paint, node))
    var renderer = Renderer(32, 32)
    assert_equal(len(renderer.prepare(scene, assets, _camera())), 6)


def test_a_group_is_drawn_where_it_meets_the_range() raises:
    var assets = Assets()
    var geometry = _strip(4)
    geometry.add_group(0, 6, MaterialIndex(0))
    geometry.add_group(6, 6, MaterialIndex(1))
    geometry.set_draw_range(3, 6)
    var strip = assets.geometries.add(geometry^)
    var red = _basic(assets)
    var blue = _basic(assets)
    var scene = Scene()
    var node = _scene_of(scene)
    scene.add_mesh(Mesh(strip, [red, blue], node))
    var renderer = Renderer(32, 32)
    # The second triangle from the first group, the third from the second.
    assert_equal(len(renderer.prepare(scene, assets, _camera())), 6)
    # And a pick finds only those two.
    assert_equal(len(_pick_at(0.5).intersect_mesh(scene, assets, 0)), 0)
    var second = _pick_at(2.5).intersect_mesh(scene, assets, 0)
    assert_equal(len(second), 1)
    assert_true(second[0].mesh.material == red)
    var third = _pick_at(4.5).intersect_mesh(scene, assets, 0)
    assert_equal(len(third), 1)
    assert_true(third[0].mesh.material == blue)
    assert_equal(len(_pick_at(6.5).intersect_mesh(scene, assets, 0)), 0)


def test_a_wireframe_draws_the_edges_of_the_range() raises:
    var assets = Assets()
    var geometry = _strip(4)
    geometry.set_draw_range(3, 3)
    var strip = assets.geometries.add(geometry^)
    var wire = _basic(assets, True)
    var scene = Scene()
    var node = _scene_of(scene)
    scene.add_mesh(Mesh(strip, wire, node))
    var renderer = Renderer(32, 32)
    # One triangle's three edges, two ends each.
    assert_equal(len(renderer.prepare_lines(scene, assets, _camera())), 6)


def test_the_raycaster_picks_only_the_range() raises:
    var assets = Assets()
    var geometry = _strip(4)
    geometry.set_index([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11])
    geometry.set_draw_range(6)
    var strip = assets.geometries.add(geometry^)
    var paint = _basic(assets)
    var scene = Scene()
    var node = _scene_of(scene)
    scene.add_mesh(Mesh(strip, paint, node))
    assert_equal(len(_pick_at(0.5).intersect_mesh(scene, assets, 0)), 0)
    var hits = _pick_at(4.5).intersect_mesh(scene, assets, 0)
    assert_equal(len(hits), 1)
    assert_equal(hits[0].triangle, 2)


# --- lines and points -------------------------------------------------------


def _row(count: Int) raises -> BufferGeometry:
    """Return points along x, one a meter apart, from the origin."""
    var numbers = List[Float32]()
    for point in range(count):
        numbers.append(Float32(point))
        numbers.append(0)
        numbers.append(0)
    var geometry = BufferGeometry()
    geometry.set_attribute(POSITION, BufferAttribute(numbers^, 3))
    return geometry^


def _lines_drawn(
    mode_is: Int, start: Int, count: Int, points: Int = 6
) raises -> Int:
    """Return how many segments a line of `points` points draws with a
    draw range: `mode_is` 0 for a strip, 1 for a loop, 2 for sticks."""
    var assets = Assets()
    var geometry = _row(points)
    geometry.set_draw_range(start, count)
    var row = assets.geometries.add(geometry^)
    var ink = assets.materials.add(Material(Color(255, 0, 0), kind=BASIC))
    var scene = Scene()
    var node = _scene_of(scene)
    var mode = STRIP
    if mode_is == 1:
        mode = LOOP
    elif mode_is == 2:
        mode = SEGMENTS
    scene.add_line(Line(row, ink, node, mode=mode))
    var renderer = Renderer(32, 32)
    return len(renderer.prepare_lines(scene, assets, _camera())) // 2


def test_a_line_joins_only_the_points_in_the_range() raises:
    assert_equal(_lines_drawn(0, 0, 6), 5)
    assert_equal(_lines_drawn(0, 1, 3), 2)
    # A loop closes on the first point in the range.
    assert_equal(_lines_drawn(1, 1, 3), 3)
    # Sticks leave out a last point with no partner.
    assert_equal(_lines_drawn(2, 1, 3), 1)
    assert_equal(_lines_drawn(2, 0, 4), 2)
    # The whole line must still suit its mode.
    with assert_raises(contains="pairs of points"):
        _ = _lines_drawn(2, 0, 2, 5)


def test_a_line_is_picked_only_in_the_range() raises:
    var assets = Assets()
    var geometry = _row(6)
    geometry.set_draw_range(2, 3)
    var row = assets.geometries.add(geometry^)
    var ink = assets.materials.add(Material(Color(255, 0, 0), kind=BASIC))
    var sticks_geometry = _row(6)
    sticks_geometry.set_draw_range(1, 5)
    var sticks = assets.geometries.add(sticks_geometry^)
    var scene = Scene()
    var node = _scene_of(scene)
    scene.add_line(Line(row, ink, node, mode=STRIP))
    scene.add_line(Line(row, ink, node, mode=LOOP))
    scene.add_line(Line(sticks, ink, node, mode=SEGMENTS))
    # Between the first two points: outside the range.
    assert_equal(len(_pick_at(0.5).intersect_line(scene, assets, 0)), 0)
    var strip = _pick_at(2.5).intersect_line(scene, assets, 0)
    assert_equal(len(strip), 1)
    assert_equal(strip[0].triangle, 2)
    # The loop's closing segment runs from 4 back to 2, over 3.5 too.
    var loop = _pick_at(3.5).intersect_line(scene, assets, 1)
    assert_equal(len(loop), 2)
    # Sticks from the second point: 1 to 2, then 3 to 4.
    assert_equal(len(_pick_at(2.5).intersect_line(scene, assets, 2)), 0)
    var stick = _pick_at(3.5).intersect_line(scene, assets, 2)
    assert_equal(len(stick), 1)
    assert_equal(stick[0].triangle, 1)


def test_points_draw_and_pick_only_the_range() raises:
    var assets = Assets()
    var geometry = _row(6)
    geometry.set_draw_range(2, 2)
    var row = assets.geometries.add(geometry^)
    var dots = assets.materials.add(points_material(Color(0, 255, 0)))
    var nothing_geometry = _row(6)
    nothing_geometry.set_draw_range(6)
    var nothing = assets.geometries.add(nothing_geometry^)
    var scene = Scene()
    var node = _scene_of(scene)
    scene.add_points(Points(row, dots, node))
    scene.add_points(Points(nothing, dots, node))
    var renderer = Renderer(32, 32)
    assert_equal(len(renderer.prepare_points(scene, assets, _camera())), 2)
    assert_equal(len(_pick_at(1).intersect_points(scene, assets, 0)), 0)
    var hits = _pick_at(3).intersect_points(scene, assets, 0)
    assert_equal(len(hits), 1)
    assert_equal(hits[0].triangle, 3)
    assert_equal(len(_pick_at(3).intersect_points(scene, assets, 1)), 0)


# --- scene JSON -------------------------------------------------------------


def test_array_names_are_three_js_s() raises:
    assert_equal(array_type_name(FLOAT32_COMPONENT), "Float32Array")
    assert_equal(array_type_name(UINT8_COMPONENT), "Uint8Array")
    assert_equal(array_type_name(INT32_COMPONENT), "Int32Array")
    assert_true(component_of_array("Int8Array") == INT8_COMPONENT)
    assert_true(component_of_array("Uint32Array") == UINT32_COMPONENT)
    with assert_raises(contains="not read: Float64Array"):
        _ = component_of_array("Float64Array")
    with assert_raises(contains="valid component type"):
        _ = array_type_name(ComponentType(7))


def test_scene_json_carries_the_name_the_user_data_and_typed_arrays() raises:
    var assets = Assets()
    var geometry = _strip(1)
    geometry.name = "tri"
    geometry.user_data.set_number("a", 1)
    geometry.set_attribute(
        COLOR,
        BufferAttribute(
            [255, 0, 128, 0, 255, 0, 1, 2, 3], 3, UINT8_COMPONENT, True
        ),
    )
    var normals = BufferAttribute([0.0, 0, 1, 0, 0, 1, 0, 0, 1], 3)
    normals.set_normalized(True)
    geometry.set_attribute(NORMAL, normals^)
    # An integer attribute of no items writes and reads an empty array.
    geometry.set_attribute(
        "empty", BufferAttribute(List[Int](), 1, INT8_COMPONENT)
    )
    var shape = assets.geometries.add(geometry^)
    var paint = _basic(assets)
    var scene = Scene()
    var node = _scene_of(scene)
    scene.add_mesh(Mesh(shape, paint, node))
    var text = object_to_json(scene, assets)
    assert_true('"name":"tri","userData":{"a":1}' in text)
    assert_true(
        '"type":"Uint8Array","array":[255,0,128,0,255,0,1,2,3],'
        + '"normalized":true'
        in text
    )
    var again = Scene()
    var more = Assets()
    _ = read_object_json(text, again, more)
    ref back = more.geometries.get(again.meshes[0].geometry)
    assert_equal(back.name, "tri")
    assert_equal(back.user_data.number("a"), 1)
    ref colors = back.attribute_view(COLOR)
    assert_true(colors.component_type() == UINT8_COMPONENT)
    assert_true(colors.is_normalized())
    assert_equal(colors.stored_values(), [255, 0, 128, 0, 255, 0, 1, 2, 3])
    assert_true(back.attribute_view(NORMAL).is_normalized())
    assert_equal(back.attribute_view("empty").count(), 0)
    # A geometry with no name and no user data writes neither.
    var plain = Assets()
    var bare = plain.geometries.add(_strip(1))
    var bare_paint = _basic(plain)
    var bare_scene = Scene()
    var bare_node = _scene_of(bare_scene)
    bare_scene.add_mesh(Mesh(bare, bare_paint, bare_node))
    var bare_text = object_to_json(bare_scene, plain)
    assert_false('"userData"' in bare_text)


def test_scene_json_refuses_an_instanced_integer_attribute() raises:
    var text = (
        '{"metadata":{"version":4.7,"type":"Object"},"geometries":[{"uuid":'
        + '"g","type":"BufferGeometry","data":{"attributes":{"position":'
        + '{"itemSize":3,"type":"Int16Array","array":[0,0,0],'
        + '"isInstancedBufferAttribute":true}}}}],'
        + '"materials":[{"uuid":"m","type":"MeshBasicMaterial"}],'
        + '"object":{"uuid":"o","type":"Mesh","geometry":"g","material":"m"}}'
    )
    var scene = Scene()
    var assets = Assets()
    with assert_raises(contains="instanced attribute is read as floats"):
        _ = read_object_json(text, scene, assets)


# --- glTF -------------------------------------------------------------------


def _quantized() raises -> BufferGeometry:
    """Return one triangle with quantized positions, normals, texture
    coordinates and colors."""
    var geometry = BufferGeometry()
    geometry.set_attribute(
        POSITION,
        BufferAttribute(
            [0, 0, 0, 32767, 0, 0, 0, 32767, -32767], 3, INT16_COMPONENT, True
        ),
    )
    geometry.set_attribute(
        NORMAL,
        BufferAttribute(
            [0, 0, 127, 0, 0, 127, 0, 0, 127], 3, INT8_COMPONENT, True
        ),
    )
    geometry.set_attribute(
        UV, BufferAttribute([0, 0, 2, 0, 0, 3], 2, UINT16_COMPONENT)
    )
    geometry.set_attribute(
        UV1, BufferAttribute([0, 0, 255, 0, 0, 255], 2, UINT8_COMPONENT, True)
    )
    geometry.set_attribute(
        COLOR,
        BufferAttribute(
            [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 128],
            4,
            UINT8_COMPONENT,
            True,
        ),
    )
    return geometry^


def _exported(var geometry: BufferGeometry) raises -> String:
    """Return a scene of one colored mesh of `geometry` as glTF text."""
    var assets = Assets()
    var shape = assets.geometries.add(geometry^)
    var paint = assets.materials.add(
        Material(Color(255, 255, 255), kind=BASIC, vertex_colors=True)
    )
    var scene = Scene()
    var node = _scene_of(scene)
    scene.add_mesh(Mesh(shape, paint, node))
    var files = export_gltf(scene, assets, GLTF_EMBEDDED)
    return String(unsafe_from_utf8=files.document)


def test_gltf_writes_quantized_attributes_in_their_own_types() raises:
    var text = _exported(_quantized())
    assert_true('"extensionsRequired":["KHR_mesh_quantization"]' in text)
    assert_true(
        '"componentType":5122,"normalized":true,"count":3,"type":"VEC3",'
        + '"min":[0,0,-32767],"max":[32767,32767,0]'
        in text
    )
    assert_true('"componentType":5120,"normalized":true' in text)
    assert_true('"componentType":5123,"count":3,"type":"VEC2"' in text)
    assert_true(
        '"componentType":5121,"normalized":true,"count":3,"type":"VEC2"' in text
    )
    assert_true(
        '"componentType":5121,"normalized":true,"count":3,"type":"VEC4"' in text
    )
    # And they read back as the same integers in the same types.
    var scene = Scene()
    var assets = Assets()
    var model = load_gltf(text, List[UInt8](), "", scene, assets)
    ref back = assets.geometries.get(model.geometries[0])
    ref positions = back.attribute_view(POSITION)
    assert_true(positions.component_type() == INT16_COMPONENT)
    assert_true(positions.is_normalized())
    assert_equal(
        positions.stored_values(), [0, 0, 0, 32767, 0, 0, 0, 32767, -32767]
    )
    assert_true(back.attribute_view(NORMAL).component_type() == INT8_COMPONENT)
    ref uvs = back.attribute_view(UV)
    assert_true(uvs.component_type() == UINT16_COMPONENT)
    assert_false(uvs.is_normalized())
    assert_equal(uvs.stored_values(), [0, 0, 2, 0, 0, 3])
    assert_equal(
        back.attribute_view(COLOR).stored_values(),
        [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 128],
    )


def test_gltf_needs_no_extension_for_what_the_core_allows() raises:
    # Normalized unsigned texture coordinates and colors are core glTF,
    # and an unsigned normal is not one the extension names either.
    var geometry = _strip(1)
    geometry.set_attribute(
        UV,
        BufferAttribute([0, 0, 65535, 0, 0, 65535], 2, UINT16_COMPONENT, True),
    )
    geometry.set_attribute(
        NORMAL,
        BufferAttribute(
            [0, 0, 255, 0, 0, 255, 0, 0, 255], 3, UINT8_COMPONENT, True
        ),
    )
    geometry.set_attribute(
        COLOR,
        BufferAttribute([255, 0, 0, 0, 255, 0, 0, 0, 255], 3, INT8_COMPONENT),
    )
    var text = _exported(geometry^)
    assert_false("KHR_mesh_quantization" in text)
    # A 32-bit integer attribute is written as floats.
    var wide = _strip(1)
    wide.set_attribute(
        UV, BufferAttribute([0, 0, 1, 0, 0, 1], 2, UINT32_COMPONENT)
    )
    var wide_text = _exported(wide^)
    assert_false('5125,"count":3,"type":"VEC2"' in wide_text)
    var signed = _strip(1)
    signed.set_attribute(
        UV, BufferAttribute([0, 0, 1, 0, 0, 1], 2, INT32_COMPONENT)
    )
    assert_false("KHR_mesh_quantization" in _exported(signed^))


def test_gltf_bounds_one_quantized_point() raises:
    var assets = Assets()
    var geometry = BufferGeometry()
    geometry.set_attribute(
        POSITION, BufferAttribute([5, -6, 7], 3, INT16_COMPONENT)
    )
    var dot = assets.geometries.add(geometry^)
    var dots = assets.materials.add(points_material(Color(0, 255, 0)))
    var scene = Scene()
    var node = _scene_of(scene)
    scene.add_points(Points(dot, dots, node))
    var files = export_gltf(scene, assets, GLTF_EMBEDDED)
    var text = String(unsafe_from_utf8=files.document)
    assert_true('"min":[5,-6,7],"max":[5,-6,7]' in text)


def test_gltf_reads_an_empty_quantized_attribute() raises:
    var text = String(
        '{"asset":{"version":"2.0"},"accessors":['
        + '{"componentType":5126,"count":0,"type":"VEC3"},'
        + '{"componentType":5121,"count":0,"type":"VEC4","normalized":true}],'
        + '"meshes":[{"primitives":[{"mode":0,"attributes":'
        + '{"POSITION":0,"COLOR_0":1}}]}],'
        + '"nodes":[{"mesh":0}],"scenes":[{"nodes":[0]}],"scene":0}'
    )
    var scene = Scene()
    var assets = Assets()
    var model = load_gltf(text, List[UInt8](), "", scene, assets)
    ref colors = assets.geometries.get(model.geometries[0]).attribute_view(
        COLOR
    )
    assert_equal(colors.count(), 0)
    assert_true(colors.component_type() == UINT8_COMPONENT)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
