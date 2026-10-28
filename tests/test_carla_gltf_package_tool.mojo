# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A vehicle package matches the previous glTF, buffer, and texture bytes."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import run_program
from tools._sha256 import sha256_hex
from tools.carla_gltf_package import package_vehicle


def _python(script: String) raises -> String:
    """Return the standard output of a Python script."""
    var result = run_program(["python3", "-c", script], 30, merge_errors=False)
    if result.status != 0:
        raise Error(result.errors)
    return result.output


def _fixture() raises -> String:
    """Write the oracle mesh and return its root."""
    var lines = _python(
        "import json, os, struct\n"
        + "from PIL import Image\n"
        + "root = '/tmp/carla-gltf-package'\n"
        + "os.makedirs(root + '/export', exist_ok=True)\n"
        + "os.makedirs(root + '/in', exist_ok=True)\n"
        + "Image.new('RGB', (2, 2), (10, 20, 30)).save(root +"
        " '/export/Red.png')\n"
        + "open(root + '/export/Red.tga', 'wb').write(b'not a tga')\n"
        + "open(root + '/export/Wall.mat', 'w').write('Diffuse=Red\\n')\n"
        + "positions = struct.pack('<9f', 0, 0, 0, 1, 0, 0, 0, 1, 0)\n"
        + "indices = struct.pack('<3H', 0, 1, 2)\n"
        + "blob = positions + indices\n"
        + "open(root + '/in/mesh.bin', 'wb').write(blob)\n"
        + "gltf = {\n"
        + " 'asset': {'version': '2.0', 'generator': 'umodel'},\n"
        + " 'buffers': [{'uri': 'mesh.bin', 'byteLength': len(blob)}],\n"
        + " 'bufferViews': [\n"
        + "  {'buffer': 0, 'byteOffset': 0, 'byteLength': 36},\n"
        + "  {'buffer': 0, 'byteOffset': 36, 'byteLength': 6}],\n"
        + " 'accessors': [\n"
        + "  {'bufferView': 0, 'componentType': 5126, 'count': 3, 'type':"
        " 'VEC3'},\n"
        + "  {'bufferView': 1, 'componentType': 5123, 'count': 3, 'type':"
        " 'SCALAR'}],\n"
        + " 'meshes': [{'primitives': [{'attributes': {'POSITION': 0},"
        " 'indices': 1, 'material': 0}]}],\n"
        + " 'materials': [{'name': 'Wall', 'extensions':"
        " {'KHR_materials_unlit': {}}}],\n"
        + " 'nodes': [{'mesh': 0}],\n"
        + " 'scenes': [{'nodes': [0]}],\n"
        + " 'scene': 0}\n"
        + "open(root + '/in/mesh.gltf', 'w').write(json.dumps(gltf))\n"
        + "print(root)\n"
    )
    return String(lines.strip())


def test_a_vehicle_package_matches_the_previous_bytes() raises:
    var root = _fixture()
    var report = package_vehicle(
        root + "/export",
        root + "/in/mesh.gltf",
        root + "/out",
        "car",
        64,
        35000,
    )
    var expected = _python(
        "print('  {:45s} {:28s} {}'.format('Wall', '', 'baseColorTexture'))\n"
    )
    assert_equal(report, expected)
    assert_equal(
        sha256_hex(Path(root + "/out/car.gltf").read_bytes()),
        "9710dc431c1dcb27a521358231824fa28457cfb61d6aa81e8291bb115e3179e9",
    )
    assert_equal(
        sha256_hex(Path(root + "/out/car.bin").read_bytes()),
        "d3478e66e380d8a2b0c9d80f3459f75660efb111e7b801a7d1c1f8f48723d79b",
    )
    var jpg = (
        root
        + "/out/textures/texture_abb6c655cb747a4b84cc005c2a8d39df8516687815d06dd0a53208870c4e4693.jpg"
    )
    assert_equal(
        sha256_hex(Path(jpg).read_bytes()),
        "abb6c655cb747a4b84cc005c2a8d39df8516687815d06dd0a53208870c4e4693",
    )


def test_cli_prints_the_report() raises:
    var root = _fixture()
    var ran = run_program(
        [
            "sh",
            "tools/tool.sh",
            tool_mojo(),
            "carla_gltf_package",
            root + "/export",
            root + "/in/mesh.gltf",
            root + "/cli-out",
            "car",
            "--max-size",
            "64",
            "--budget",
            "35000",
        ],
        60,
    )
    if ran.status != 0:
        raise Error(ran.output + ran.errors)
    var expected = _python(
        "print('  {:45s} {:28s} {}'.format('Wall', '', 'baseColorTexture'))\n"
    )
    assert_equal(ran.output, expected)
    assert_equal(
        sha256_hex(Path(root + "/cli-out/car.gltf").read_bytes()),
        "9710dc431c1dcb27a521358231824fa28457cfb61d6aa81e8291bb115e3179e9",
    )
    var usage = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_gltf_package"],
        30,
        merge_errors=False,
    )
    assert_equal(usage.status, 2)
    assert_true(usage.errors.startswith("usage: carla_gltf_package "))


def test_a_negative_size_is_refused() raises:
    with assert_raises(contains="max_size is negative"):
        _ = package_vehicle(
            "/tmp", "/tmp/missing.gltf", "/tmp/out", "car", -1, 0
        )


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_gltf_package"],
        180,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
