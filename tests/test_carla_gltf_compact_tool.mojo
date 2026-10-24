# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Vehicle glTF compaction matches the Python exporter's buffer steps."""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_true

from tests._tree import tool_mojo
from tools._process import run_program
from tools._python_json import MISSING, PyJson
from tools.carla_gltf_compact import compact_gltf


def _range(count: Int) -> List[UInt8]:
    """Return bytes 0 through `count - 1`."""
    var out = List[UInt8]()
    for index in range(count):
        out.append(UInt8(index))
    return out^


def _sample() -> List[UInt8]:
    """Return the three-byte compact fixture."""
    var out = List[UInt8]()
    out.append(0xAA)
    out.append(0xBB)
    out.append(0xCC)
    return out^


def _run(text: String, data: List[UInt8], mode: String) raises -> PyJson:
    """Apply `mode` and return the edited document."""
    var doc = PyJson.parse(text)
    var output = compact_gltf(doc, mode, Span(data))
    if mode == "compact" or mode == "strip":
        var length = doc.text(
            doc.at(doc.item(doc.at(doc.root, "buffers"), 0), "byteLength")
        )
        assert_equal(length, String(len(output)))
    return doc^


def test_duplicate_material_names_keep_the_first() raises:
    var doc = _run(
        '{"materials":[{"name":"glass","a":1},{"name":"paint"},{"name":"glass","a":2}],"meshes":[{"primitives":[{"material":0},{"material":2},{"attributes":{}}]}]}',
        List[UInt8](),
        "dedupe",
    )
    var materials = doc.at(doc.root, "materials")
    assert_equal(doc.length(materials), 2)
    assert_equal(doc.text(doc.at(doc.item(materials, 0), "name")), "glass")
    assert_equal(doc.text(doc.at(doc.item(materials, 1), "name")), "paint")
    var primitives = doc.at(
        doc.item(doc.at(doc.root, "meshes"), 0), "primitives"
    )
    assert_equal(doc.text(doc.at(doc.item(primitives, 0), "material")), "0")
    assert_equal(doc.text(doc.at(doc.item(primitives, 1), "material")), "0")
    assert_true(doc.find(doc.item(primitives, 2), "material") == MISSING)


def test_compaction_aligns_views_and_drops_unread_bytes() raises:
    var data = _sample()
    var doc = PyJson.parse(
        '{"meshes":[{"primitives":[{"attributes":{"POSITION":1},"indices":0}]}],"accessors":[{"bufferView":0,"componentType":5125},{"bufferView":1,"componentType":5126}],"bufferViews":[{"byteOffset":0,"byteLength":1},{"byteOffset":1,"byteLength":2}],"buffers":[{"uri":"mesh.bin","byteLength":3}]}'
    )
    var output = compact_gltf(doc, "compact", Span(data))
    assert_equal(len(output), 8)
    assert_equal(Int(output[0]), 0xAA)
    assert_equal(Int(output[1]), 0)
    assert_equal(Int(output[4]), 0xBB)
    assert_equal(Int(output[5]), 0xCC)
    var views = doc.at(doc.root, "bufferViews")
    assert_equal(doc.text(doc.at(doc.item(views, 1), "byteOffset")), "4")
    var shared = PyJson.parse(
        '{"extras":{"keep":true},"meshes":[{"primitives":[{"attributes":{"NORMAL":2,"POSITION":0}}]}],"accessors":[{"bufferView":0,"componentType":5126,"count":1},{"bufferView":1,"componentType":5126,"count":9},{"bufferView":0,"componentType":5126,"count":1}],"bufferViews":[{"byteLength":3},{"byteOffset":3,"byteLength":5}],"buffers":[{"uri":"a.bin","byteLength":8}]}'
    )
    var raw = _range(8)
    var packed = compact_gltf(shared, "compact", Span(raw))
    assert_equal(len(packed), 4)
    assert_equal(Int(packed[0]), 0)
    assert_equal(Int(packed[1]), 1)
    assert_equal(Int(packed[2]), 2)
    assert_equal(Int(packed[3]), 0)
    assert_equal(shared.length(shared.at(shared.root, "accessors")), 2)
    assert_true(shared.find(shared.root, "extras") != MISSING)


def test_skin_attributes_leave_the_bind_pose_mesh() raises:
    var doc = _run(
        '{"nodes":[{"name":"wheel","skin":0},{"name":"body"}],"skins":[{"joints":[0]}],"meshes":[{"primitives":[{"attributes":{"POSITION":0,"JOINTS_0":1,"WEIGHTS_0":2,"COLOR_0":3},"indices":4}]}],"accessors":[{"bufferView":0,"componentType":5126},{"bufferView":1,"componentType":5126},{"bufferView":2,"componentType":5126},{"bufferView":3,"componentType":5126},{"bufferView":4,"componentType":5126}],"bufferViews":[{"byteLength":4,"byteOffset":0},{"byteLength":4,"byteOffset":4},{"byteLength":4,"byteOffset":8},{"byteLength":4,"byteOffset":12},{"byteLength":4,"byteOffset":16}],"buffers":[{"uri":"car.bin","byteLength":20}]}',
        _range(20),
        "strip",
    )
    assert_true(doc.find(doc.root, "skins") == MISSING)
    assert_true(
        doc.find(doc.item(doc.at(doc.root, "nodes"), 0), "skin") == MISSING
    )
    var attributes = doc.at(
        doc.item(
            doc.at(doc.item(doc.at(doc.root, "meshes"), 0), "primitives"), 0
        ),
        "attributes",
    )
    assert_equal(doc.length(attributes), 1)
    assert_equal(doc.key(attributes, 0), "POSITION")
    assert_equal(doc.length(doc.at(doc.root, "accessors")), 2)


def test_the_tool_writes_the_compacted_buffer() raises:
    var directory = mkdtemp(prefix="gltf compact ")
    var source = '{"meshes":[{"primitives":[{"attributes":{"POSITION":1},"indices":0}]}],"accessors":[{"bufferView":0,"componentType":5125},{"bufferView":1,"componentType":5126}],"bufferViews":[{"byteOffset":0,"byteLength":1},{"byteOffset":1,"byteLength":2}],"buffers":[{"uri":"mesh.bin","byteLength":3}]}'
    Path(directory + "/in.gltf").write_text(source)
    var data = _sample()
    Path(directory + "/in.bin").write_bytes(Span(data))
    var result = run_program(
        [
            "sh",
            "tools/tool.sh",
            tool_mojo(),
            "carla_gltf_compact",
            "compact",
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
    assert_equal(len(output), 8)
    assert_equal(Int(output[0]), 0xAA)
    assert_equal(Int(output[4]), 0xBB)
    assert_true(result.errors.find("Crashpad") < 0)
    _ = run_program(["rm", "-rf", directory], 10)


def main() raises:
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_gltf_compact"],
        180,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
