# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Lamp splitting matches the Python exporter's front and rear index lists."""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_true

from tests._tree import tool_mojo
from tools._process import run_program
from tools._python_json import PyJson
from tools.carla_gltf_lamps import split_lamps


def _u16(mut out: List[UInt8], value: Int):
    """Append a little-endian unsigned 16-bit integer."""
    out.append(UInt8(value & 255))
    out.append(UInt8((value >> 8) & 255))


def _f32(mut out: List[UInt8], value: Int):
    """Append a little-endian float32 for 0 or 2."""
    out.append(0)
    out.append(0)
    out.append(0)
    var high = UInt8(0)
    if value != 0:
        high = 0x40
    out.append(high)


def _fixture() -> List[UInt8]:
    """Return six positions, six uint16 indices, and one extra byte."""
    var out = List[UInt8]()
    for vertex in range(6):
        _f32(out, 2 if vertex < 3 else 0)
        _f32(out, 0)
        _f32(out, 0)
    for index in range(6):
        _u16(out, index)
    out.append(0x7F)
    return out^


def _gltf() -> String:
    """Return the lamp fixture document."""
    return '{"materials":[{"name":"body"},{"name":"lamps","extras":{"carla":"lamps"}}],"meshes":[{"primitives":[{"material":0,"attributes":{"POSITION":0},"indices":1},{"material":1,"attributes":{"POSITION":0,"TEXCOORD_0":2},"indices":1,"mode":4}]}],"accessors":[{"bufferView":0,"componentType":5126,"count":6,"type":"VEC3","min":[0,0,0],"max":[2,0,0]},{"bufferView":1,"componentType":5123,"count":6,"type":"SCALAR"},{"bufferView":2,"componentType":5126,"count":6,"type":"VEC2"}],"bufferViews":[{"byteOffset":0,"byteLength":72},{"byteOffset":72,"byteLength":12},{"byteOffset":0,"byteLength":0}],"buffers":[{"uri":"car.bin","byteLength":85}]}'


def _u32(data: List[UInt8], at: Int) -> Int:
    """Return a little-endian unsigned 32-bit integer."""
    return (
        Int(data[at])
        | (Int(data[at + 1]) << 8)
        | (Int(data[at + 2]) << 16)
        | (Int(data[at + 3]) << 24)
    )


def test_front_and_rear_triangles_become_separate_lamps() raises:
    var doc = PyJson.parse(_gltf())
    var data = _fixture()
    var output = split_lamps(doc, Span(data))
    assert_equal(len(output), 112)
    assert_equal(Int(output[84]), 0x7F)
    assert_equal(Int(output[85]), 0)
    assert_equal(_u32(output, 88), 0)
    assert_equal(_u32(output, 92), 1)
    assert_equal(_u32(output, 96), 2)
    assert_equal(_u32(output, 100), 3)
    assert_equal(_u32(output, 104), 4)
    assert_equal(_u32(output, 108), 5)
    var materials = doc.at(doc.root, "materials")
    assert_equal(doc.length(materials), 3)
    assert_equal(
        doc.text(doc.at(doc.item(materials, 1), "name")), "CarlaHeadLamps"
    )
    assert_equal(
        doc.text(doc.at(doc.item(materials, 2), "name")), "CarlaTailLamps"
    )
    var primitives = doc.at(
        doc.item(doc.at(doc.root, "meshes"), 0), "primitives"
    )
    assert_equal(doc.length(primitives), 3)
    assert_equal(doc.text(doc.at(doc.item(primitives, 0), "material")), "0")
    assert_equal(doc.text(doc.at(doc.item(primitives, 1), "material")), "1")
    assert_equal(doc.text(doc.at(doc.item(primitives, 2), "material")), "2")
    assert_equal(
        doc.text(
            doc.at(doc.item(doc.at(doc.root, "buffers"), 0), "byteLength")
        ),
        "112",
    )


def test_a_model_without_lamps_is_unchanged() raises:
    var doc = PyJson.parse(
        '{"materials":[{"name":"body"}],"meshes":[{"primitives":[{"material":0}]}],"buffers":[{"uri":"a.bin","byteLength":1}]}'
    )
    var data = List[UInt8]()
    data.append(1)
    var output = split_lamps(doc, Span(data))
    assert_equal(len(output), 1)
    assert_equal(Int(output[0]), 1)
    assert_equal(doc.length(doc.at(doc.root, "materials")), 1)
    assert_equal(
        doc.text(
            doc.at(doc.item(doc.at(doc.root, "buffers"), 0), "byteLength")
        ),
        "1",
    )


def test_the_tool_writes_the_split_buffer() raises:
    var directory = mkdtemp(prefix="gltf lamps ")
    Path(directory + "/in.gltf").write_text(_gltf())
    var data = _fixture()
    Path(directory + "/in.bin").write_bytes(Span(data))
    var result = run_program(
        [
            "sh",
            "tools/tool.sh",
            tool_mojo(),
            "carla_gltf_lamps",
            directory + "/in.gltf",
            directory + "/in.bin",
            directory + "/out.gltf",
            directory + "/out.bin",
        ],
        60,
        merge_errors=False,
    )
    assert_equal(result.status, 0)
    var output = Path(directory + "/out.bin").read_bytes()
    assert_equal(len(output), 112)
    assert_equal(_u32(output, 88), 0)
    assert_equal(_u32(output, 100), 3)
    assert_true(result.errors.find("Crashpad") < 0)
    _ = run_program(["rm", "-rf", directory], 10)


def main() raises:
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_gltf_lamps"],
        180,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
