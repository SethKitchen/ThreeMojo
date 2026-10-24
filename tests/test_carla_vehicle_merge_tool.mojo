# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A vehicle glTF merge matches the reviewed Python buffer and indexes."""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import run_program
from tools.carla_vehicle_merge import merge_gltf


comptime _BASE = (
    '{"asset": {"version": "2.0"}, "buffers": [{"byteLength": 0, "uri":'
    ' "a.bin"}], "bufferViews": [{"buffer": 1, "byteLength": 3}], "accessors":'
    ' [{"bufferView": 0, "componentType": 5126, "count": 1, "type": "VEC3",'
    ' "min": [0.5, 0, 0], "max": [0.5, 0, 0]}], "meshes": [{"primitives":'
    ' [{"attributes": {"POSITION": 0}, "material": 0}]}], "nodes": [{"name":'
    ' "body", "mesh": 0, "children": [0]}], "scenes": [{"nodes": [0], "name":'
    ' "scene"}], "materials": [{"name": "paint", "pbrMetallicRoughness":'
    ' {"metallicFactor": 0.5}}], "scene": 0}'
)
"""A body whose buffer is three bytes and whose view names buffer 1."""
comptime _EXTRA = (
    '{"asset": {"version": "2.0"}, "buffers": [{"byteLength": 0, "uri":'
    ' "a.bin"}], "bufferViews": [{"byteLength": 2, "target": 34962}],'
    ' "accessors": [{"bufferView": 0, "componentType": 5126, "count": 1,'
    ' "type": "SCALAR"}], "meshes": [{"name": "glass", "primitives":'
    ' [{"attributes": {"POSITION": 0, "NORMAL": 0}, "indices": 0, "material":'
    ' 0}]}], "nodes": [{"name": "lamp", "mesh": 0, "children": [0], "extras":'
    ' {"k": 1}}], "scenes": [{"nodes": [0]}], "materials": [{"name": "glass"}]}'
)
"""A static mesh with no buffer index and no byte offset."""
comptime _MERGED = (
    '{"asset": {"version": "2.0"}, "buffers": [{"byteLength": 6, "uri":'
    ' "a.bin"}], "bufferViews": [{"buffer": 1, "byteLength": 3}, {"byteLength":'
    ' 2, "target": 34962, "buffer": 0, "byteOffset": 4}], "accessors":'
    ' [{"bufferView": 0, "componentType": 5126, "count": 1, "type": "VEC3",'
    ' "min": [0.5, 0, 0], "max": [0.5, 0, 0]}, {"bufferView": 1,'
    ' "componentType": 5126, "count": 1, "type": "SCALAR"}], "meshes":'
    ' [{"primitives": [{"attributes": {"POSITION": 0}, "material": 0}]},'
    ' {"name": "glass", "primitives": [{"attributes": {"POSITION": 1, "NORMAL":'
    ' 1}, "indices": 1, "material": 1}]}], "nodes": [{"name": "body", "mesh":'
    ' 0, "children": [0]}, {"name": "lamp", "mesh": 1, "children": [1],'
    ' "extras": {"k": 1}}], "scenes": [{"nodes": [0, 1], "name": "scene"}],'
    ' "materials": [{"name": "paint", "pbrMetallicRoughness":'
    ' {"metallicFactor": 0.5}}, {"name": "glass"}], "scene": 0}'
)
"""The padded merge of `_BASE` and `_EXTRA`."""
comptime _ALIGNED_BASE = (
    '{"buffers": [{"byteLength": 4}], "bufferViews": [{"buffer": 0,'
    ' "byteOffset": 0, "byteLength": 4}], "accessors": [{"bufferView": 0,'
    ' "componentType": 5126, "count": 1, "type": "SCALAR"}], "meshes":'
    ' [{"primitives": [{"attributes": {"POSITION": 0}}]}], "nodes": [{"mesh":'
    ' 0}, {"name": "wheel"}], "scenes": [{"nodes": []}, {"nodes": [0]}],'
    ' "scene": 1}'
)
"""A body that already ends on a four-byte boundary and selects scene 1."""
comptime _ALIGNED_EXTRA = (
    '{"buffers": [{"byteLength": 4}], "bufferViews": [{"buffer": 0,'
    ' "byteOffset": 4, "byteLength": 4}], "accessors": [{"bufferView": 0,'
    ' "componentType": 5126, "count": 1, "type": "SCALAR"}], "meshes":'
    ' [{"primitives": [{"attributes": {"TEXCOORD_0": 0, "POSITION": 0},'
    ' "material": 1}]}], "nodes": [{"mesh": 0}], "scenes": [{"nodes": [0]},'
    ' {"nodes": []}], "materials": []}'
)
"""A mesh whose attribute order is texture coordinates, then position."""
comptime _ALIGNED = (
    '{"buffers": [{"byteLength": 8}], "bufferViews": [{"buffer": 0,'
    ' "byteOffset": 0, "byteLength": 4}, {"buffer": 0, "byteOffset": 8,'
    ' "byteLength": 4}], "accessors": [{"bufferView": 0, "componentType": 5126,'
    ' "count": 1, "type": "SCALAR"}, {"bufferView": 1, "componentType": 5126,'
    ' "count": 1, "type": "SCALAR"}], "meshes": [{"primitives": [{"attributes":'
    ' {"POSITION": 0}}]}, {"primitives": [{"attributes": {"TEXCOORD_0": 1,'
    ' "POSITION": 1}, "material": 1}]}], "nodes": [{"mesh": 0}, {"name":'
    ' "wheel"}, {"mesh": 1}], "scenes": [{"nodes": []}, {"nodes": [0, 2]}],'
    ' "scene": 1, "materials": []}'
)
"""The merge that adds an empty material list and keeps scene 1."""


def _bytes(first: Int, second: Int, third: Int) -> List[UInt8]:
    """Return three buffer bytes."""
    var out = List[UInt8]()
    out.append(UInt8(first))
    out.append(UInt8(second))
    out.append(UInt8(third))
    return out^


def _four(first: Int, second: Int, third: Int, fourth: Int) -> List[UInt8]:
    """Return four buffer bytes."""
    var out = _bytes(first, second, third)
    out.append(UInt8(fourth))
    return out^


def _expect(mut data: List[UInt8], expected: List[Int]) raises:
    """Require `data` to hold `expected`."""
    assert_equal(len(data), len(expected))
    for index in range(len(expected)):
        assert_equal(Int(data[index]), expected[index])


def test_merge_pads_the_buffer_and_renumbers() raises:
    var base_bin = _bytes(1, 2, 3)
    var extra_bin = List[UInt8]()
    extra_bin.append(4)
    extra_bin.append(5)
    var merged = merge_gltf(_BASE, base_bin^, _EXTRA, extra_bin^)
    assert_equal(merged[0], _MERGED)
    var expected = List[Int]()
    expected.append(1)
    expected.append(2)
    expected.append(3)
    expected.append(0)
    expected.append(4)
    expected.append(5)
    _expect(merged[1], expected)


def test_an_aligned_body_keeps_its_scene_and_attribute_order() raises:
    var base_bin = _four(9, 9, 9, 9)
    var extra_bin = _four(8, 7, 6, 5)
    var merged = merge_gltf(
        _ALIGNED_BASE, base_bin^, _ALIGNED_EXTRA, extra_bin^
    )
    assert_equal(merged[0], _ALIGNED)
    var expected = List[Int]()
    for value in [9, 9, 9, 9, 8, 7, 6, 5]:
        expected.append(value)
    _expect(merged[1], expected)


def test_a_partial_document_is_refused() raises:
    var base_bin = List[UInt8]()
    var extra_bin = List[UInt8]()
    with assert_raises():
        _ = merge_gltf("{}", base_bin^, "{}", extra_bin^)


def test_the_command_writes_the_merged_files() raises:
    var directory = mkdtemp(prefix="vehicle merge ")
    var base_gltf = directory + "/base.gltf"
    var base_bin = directory + "/base.bin"
    var extra_gltf = directory + "/extra.gltf"
    var extra_bin = directory + "/extra.bin"
    var out_gltf = directory + "/out.gltf"
    var out_bin = directory + "/out.bin"
    Path(base_gltf).write_text(_BASE)
    var body = _bytes(1, 2, 3)
    Path(base_bin).write_bytes(Span(body))
    Path(extra_gltf).write_text(_EXTRA)
    var glass = List[UInt8]()
    glass.append(4)
    glass.append(5)
    Path(extra_bin).write_bytes(Span(glass))
    var result = run_program(
        [
            "sh",
            "tools/tool.sh",
            tool_mojo(),
            "carla_vehicle_merge",
            base_gltf,
            base_bin,
            extra_gltf,
            extra_bin,
            out_gltf,
            out_bin,
        ],
        30,
        merge_errors=False,
    )
    assert_equal(result.status, 0)
    assert_equal(Path(out_gltf).read_text(), _MERGED)
    var written = Path(out_bin).read_bytes()
    assert_equal(len(written), 6)
    assert_equal(Int(written[3]), 0)
    assert_equal(Int(written[4]), 4)
    assert_true(result.errors.find("Crashpad") < 0)
    var missing = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_vehicle_merge"],
        30,
        merge_errors=False,
    )
    assert_equal(missing.status, 2)
    Path(base_gltf).write_text("{")
    var bad = run_program(
        [
            "sh",
            "tools/tool.sh",
            tool_mojo(),
            "carla_vehicle_merge",
            base_gltf,
            base_bin,
            extra_gltf,
            extra_bin,
            out_gltf,
            out_bin,
        ],
        30,
        merge_errors=False,
    )
    assert_equal(bad.status, 1)
    _ = run_program(["rm", "-rf", directory], 10)


def main() raises:
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_vehicle_merge"],
        180,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
