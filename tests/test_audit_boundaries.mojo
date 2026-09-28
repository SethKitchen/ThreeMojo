# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Boundary regressions for the repository repair."""

from tests.test_audit_regressions import _loader
from animation.keyframe_track import (
    KeyframeTrack,
    MATERIAL_OPACITY,
    material_target,
)
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION, NORMAL
from core.object3d import Object3D
from core.scene import Scene
from core.scene_optimizer import SceneOptimizer, _same_geometry
from geometries.box import cube
from loaders.draco import DracoGeometry, DRACO_TRIANGULAR_MESH, decode_draco
from loaders.draco_attributes import DracoDataType
from loaders.gltf import _DracoPrimitive
from materials.material import Material, MaterialId
from math.curve import ellipse_sweep, WHOLE_TURN
from math.matrix4 import Matrix4
from objects.mesh import Mesh
from render.framebuffer import Color
from std.testing import TestSuite, assert_equal, assert_true, assert_raises
from std.pathlib import Path
from units.si import Angle, RADIAN, Duration, SECOND, Length, METER


def test_negative_whole_turn_and_outgoing_only_tangents() raises:
    assert_equal(
        ellipse_sweep(Angle(0, RADIAN), Angle(-WHOLE_TURN, RADIAN), False),
        WHOLE_TURN,
    )
    var track = KeyframeTrack(
        material_target(MaterialId(0), MATERIAL_OPACITY),
        [Duration(0, SECOND), Duration(1, SECOND), Duration(2, SECOND)],
        in_tangents=[0, 0, 0],
        values=[0, 0, 0],
        out_tangents=[1, 1, 1],
    )
    var sample = track.sample(Duration(0.5, SECOND))[0]
    track.optimize()
    assert_equal(track.key_count(), 3)
    assert_equal(track.sample(Duration(0.5, SECOND))[0], sample)


def test_empty_geometry_and_morph_arrays_remain_empty() raises:
    var empty = BufferGeometry()
    assert_true(_same_geometry(empty, empty))
    empty.set_attribute(POSITION, BufferAttribute(List[Float32](), 3))
    empty.set_attribute(NORMAL, BufferAttribute(List[Float32](), 3))
    empty.add_morph_target(
        BufferAttribute(List[Float32](), 3), BufferAttribute(List[Float32](), 3)
    )
    empty.apply_matrix4(Matrix4())
    assert_equal(empty.morph_normals[0].count(), 0)
    var scene = Scene()
    var assets = Assets()
    var geometry = assets.geometries.add(BufferGeometry())
    var material = assets.materials.add(Material(Color(255, 255, 255)))
    scene.add_mesh(Mesh(geometry, material, scene.add(Object3D())))
    assert_equal(
        SceneOptimizer().to_batched_mesh(scene, assets).single_meshes, 0
    )


def test_optimizer_leaves_worn_morphs_and_start_only_draw_ranges() raises:
    for morph in [False, True]:
        var scene = Scene()
        var assets = Assets()
        var shape = cube(Length(1, METER))
        if morph:
            shape.add_morph_target(shape.clone_attribute(POSITION))
        else:
            shape.set_draw_range(3)
        var geometry = assets.geometries.add(shape^)
        var material = assets.materials.add(Material(Color(255, 255, 255)))
        for _ in range(2):
            var mesh = Mesh(geometry, material, scene.add(Object3D()))
            if morph:
                mesh.set_morph_influence(0, 0.5)
            scene.add_mesh(mesh^)
        _ = SceneOptimizer().to_batched_mesh(scene, assets)
        assert_equal(len(scene.batched_meshes), 0)
        assert_equal(len(scene.traverse()), 2)


def test_gltf_rejects_impossible_counts_and_missing_view_offsets() raises:
    var bytes = List[UInt8](length=32, fill=0)
    for extra in ['"bufferView":-2,', '"byteOffset":4,']:
        var reader = _loader(
            "{"
            + String(extra)
            + '"componentType":5126,"count":1,"type":"SCALAR"}',
            "",
            bytes,
        )
        with assert_raises(contains="without a buffer view"):
            _ = reader.accessor_floats(0)
    var huge = _loader(
        '{"componentType":5126,"count":4000000000000000000,"type":"VEC3"}',
        "",
        bytes,
    )
    with assert_raises(contains="whole number"):
        _ = huge.accessor_floats(0)
    var empty = _loader(
        '{"componentType":5125,"count":0,"type":"SCALAR"}', "", bytes
    )
    var attribute = empty.vertex_attribute("_ID", 0, None)
    assert_equal(attribute.count(), 0)
    assert_true(attribute.is_integer())


def test_sparse_bounds_cannot_overflow_or_read_outside_the_view() raises:
    var bytes = List[UInt8](length=8, fill=0)
    var huge = _loader(
        '{"componentType":5121,"count":1,"type":"SCALAR","sparse":{"count":2305843009213693952,"indices":{"bufferView":0,"componentType":5125},"values":{"bufferView":0}}}',
        '{"buffer":0,"byteLength":8}',
        bytes,
    )
    var sparse = huge.document.get(huge.entry("accessors", 0), "sparse")
    var output = List[Float32]()
    with assert_raises(contains="whole number"):
        huge.apply_sparse(
            sparse, output, Int(0x7FFFFFFFFFFFFFFF), 1, 5121, False, [0], 1, 1
        )
    for offset in [-1, 12]:
        var reader = _loader(
            '{"componentType":5121,"count":1,"type":"SCALAR","sparse":{"count":1,"indices":{"bufferView":0,"byteOffset":'
            + String(offset)
            + ',"componentType":5121},"values":{"bufferView":0}}}',
            '{"buffer":0,"byteLength":8}',
            bytes,
        )
        with assert_raises(contains="past its buffer view"):
            _ = reader.accessor_floats(0)
    var reader = _loader(
        '{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3"}',
        '{"buffer":0,"byteLength":8}',
        bytes,
    )
    with assert_raises(contains="past its buffer view"):
        _ = reader.sparse_view(reader.entry("accessors", 0), -1)


def test_matrix_views_can_omit_only_the_final_padding() raises:
    # glTF alignment applies to column starts. Final padding is optional.
    for rows in [2, 3]:
        for size in [1, 2]:
            var column = ((rows * size + 3) // 4) * 4
            var stride = rows * column
            var tail = (rows - 1) * column + rows * size
            var width = rows * rows
            var length = stride + tail
            var bytes = List[UInt8](length=length + 4, fill=0)
            bytes[1] = 1
            for element in range(2):
                for lane in range(width):
                    var offset = (
                        4
                        + element * stride
                        + (lane // rows) * column
                        + (lane % rows) * size
                    )
                    bytes[offset] = UInt8(1 + element * width + lane)
            var accessor = (
                '"componentType":'
                + String(5121 if size == 1 else 5123)
                + ',"count":2,"type":"MAT'
                + String(rows)
                + '"'
            )
            for sparse in [False, True]:
                for truncated in [False, True]:
                    var view = (
                        '{"buffer":0,"byteOffset":4,"byteLength":'
                        + String(length - (1 if truncated else 0))
                        + "}"
                    )
                    var text = '{"bufferView":0,' + accessor + "}"
                    if sparse:
                        view += ',{"buffer":0,"byteLength":2}'
                        text = (
                            "{"
                            + accessor
                            + ',"sparse":{"count":2,"indices":{"bufferView":1,"componentType":5121},"values":{"bufferView":0}}}'
                        )
                    var reader = _loader(text, view, bytes)
                    if truncated:
                        with assert_raises(contains="past its buffer view"):
                            _ = reader.accessor_floats(0)
                    else:
                        var result = reader.accessor_floats(0)
                        assert_equal(result[1], width)
                        assert_equal(len(result[0]), width * 2)
                        for lane in range(width * 2):
                            assert_equal(result[0][lane], Float32(lane + 1))


def test_empty_draco_mapping_preserves_uncompressed_integer_storage() raises:
    var reader = _loader(
        '{"bufferView":0,"componentType":5125,"count":1,"type":"SCALAR"}',
        '{"buffer":0,"byteLength":4}',
        List[UInt8](length=4, fill=255),
    )
    var compressed = Optional[_DracoPrimitive](
        _DracoPrimitive(
            DracoGeometry(DRACO_TRIANGULAR_MESH), List[String](), List[Int]()
        )
    )
    var attribute = reader.vertex_attribute("_ID", 0, compressed)
    assert_true(attribute.is_integer())
    assert_equal(attribute.stored_values()[0], 4294967295)


def test_draco_float_requests_preserve_integer_normalization() raises:
    var decoded = decode_draco(Path("assets/draco/grid.drc").read_bytes())
    var integers = decoded.integer_values(3, DracoDataType(2))
    var compressed = _DracoPrimitive(decoded^, ["COLOR_0"], [3])
    var reader = _loader(
        '{"componentType":5123,"count":1,"type":"VEC3","normalized":true}',
        "",
        List[UInt8](),
    )
    for raw in [False, True]:
        var result = reader.draco_floats(compressed, 0, 0, raw)
        assert_equal(result[1], 3)
        assert_equal(len(result[0]), len(integers))
        for index in range(len(integers)):
            var expected = Float32(integers[index])
            if not raw:
                expected /= 65535
            assert_equal(result[0][index], expected)
    var empty = decode_draco(
        Path("assets/draco/empty_raw_points.drc").read_bytes()
    )
    var empty_id = empty.attributes[0].unique_id
    var empty_primitive = _DracoPrimitive(empty^, ["COLOR_0"], [empty_id])
    var result = reader.draco_floats(empty_primitive, 0, 0)
    assert_equal(len(result[0]), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
