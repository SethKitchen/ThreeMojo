# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A vehicle glTF loses the same triangles the Python decimation removed."""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import run_program
from tools._sha256 import sha256_hex
from tools.carla_gltf_decimate import decimate_files


def _fixture(root: String) raises:
    """Write a grid, a masked part, and a part with no material."""
    var script = String(
        "import json, os, struct, sys\n"
        + "def grid(n):\n"
        + "    verts, uvs, normals, indices = [], [], [], []\n"
        + "    for z in range(n + 1):\n"
        + "        for x in range(n + 1):\n"
        + "            y = 1.0 if 0 < x < n and 0 < z < n else 0.0\n"
        + "            verts.append((float(x), y, float(z)))\n"
        + "            normals.append((0.0, 1.0, 0.0))\n"
        + "            uvs.append((x / n, z / n))\n"
        + "    for z in range(n):\n"
        + "        for x in range(n):\n"
        + "            a = z * (n + 1) + x\n"
        + "            b = a + 1\n"
        + "            c = a + (n + 1)\n"
        + "            d = c + 1\n"
        + "            indices.extend((a, c, b, b, c, d))\n"
        + "    return verts, normals, uvs, indices\n"
        + "def pack(gltf, parts):\n"
        + "    blob = bytearray()\n"
        + "    primitives = []\n"
        + "    for part in parts:\n"
        + "        primitive = {'attributes': {}}\n"
        + "        if 'material' in part:\n"
        + "            primitive['material'] = part['material']\n"
        + "        for name, values, fmt, ctype, kind, target in"
        " part['attrs']:\n"
        + "            raw = bytearray()\n"
        + "            for row in values:\n"
        + "                raw.extend(struct.pack(fmt, *row) if isinstance(row,"
        " tuple) else struct.pack(fmt, row))\n"
        + "            gltf['bufferViews'].append({'buffer': 0, 'byteOffset':"
        " len(blob), 'byteLength': len(raw), 'target': target})\n"
        + "            gltf['accessors'].append({'bufferView':"
        " len(gltf['bufferViews']) - 1, 'componentType': ctype, 'count':"
        " len(values), 'type': kind})\n"
        + "            blob.extend(raw)\n"
        + "            if name == 'indices':\n"
        + "                primitive['indices'] = len(gltf['accessors']) - 1\n"
        + "            else:\n"
        + "                primitive['attributes'][name] ="
        " len(gltf['accessors']) - 1\n"
        + "        if 'color' in part:\n"
        + "            raw = bytes(part['color'])\n"
        + "            gltf['bufferViews'].append({'buffer': 0, 'byteOffset':"
        " len(blob), 'byteLength': len(raw), 'target': 34962})\n"
        + "            gltf['accessors'].append({'bufferView':"
        " len(gltf['bufferViews']) - 1, 'componentType': 5121, 'count':"
        " len(raw), 'type': 'SCALAR'})\n"
        + "            blob.extend(raw)\n"
        + "            primitive['attributes']['COLOR_0'] ="
        " len(gltf['accessors']) - 1\n"
        + "        primitives.append(primitive)\n"
        + "    gltf['buffers'] = [{'uri': 'mesh.bin', 'byteLength':"
        " len(blob)}]\n"
        + "    gltf['meshes'] = [{'primitives': primitives}]\n"
        + "    return bytes(blob)\n"
        + "def attrs(vs, ns, us, idx):\n"
        + "    return [('POSITION', vs, '<3f', 5126, 'VEC3', 34962), ('NORMAL',"
        " ns, '<3f', 5126, 'VEC3', 34962), ('TEXCOORD_0', us, '<2f', 5126,"
        " 'VEC2', 34962), ('indices', idx, '<I', 5125, 'SCALAR', 34963)]\n"
        + "verts, normals, uvs, indices = grid(4)\n"
        + "verts2, normals2, uvs2, indices2 = grid(2)\n"
        + "mask = [(0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (1.0, 1.0, 0.0), (0.0,"
        " 1.0, 0.0)]\n"
        + "gltf = {'asset': {'version': '2.0'}, 'materials': [{'name': 'body'},"
        " {'name': 'glass', 'alphaMode': 'MASK', 'alphaCutoff': 0.5}],"
        " 'bufferViews': [], 'accessors': []}\n"
        + "parts = [{'material': 0, 'attrs': attrs(verts, normals, uvs,"
        " indices), 'color': [255] * len(verts)},\n"
        + " {'material': 1, 'attrs': attrs(mask, [(0.0, 1.0, 0.0)] * 4, [(0.0,"
        " 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)], [0, 1, 2, 2, 3, 0, 0, 2,"
        " 3, 1, 2, 3, 0, 1, 3, 1, 0, 2])},\n"
        + " {'attrs': attrs(verts2, normals2, uvs2, indices2)}]\n"
        + "blob = pack(gltf, parts)\n"
        + "root = sys.argv[1]\n"
        + "json.dump(gltf, open(os.path.join(root, 'in.gltf'), 'w'))\n"
        + "open(os.path.join(root, 'in.bin'), 'wb').write(blob)\n"
    )
    var result = run_program(
        ["python3", "-c", script, root],
        30,
        merge_errors=False,
    )
    if result.status != 0:
        raise Error(result.errors)


def test_free_parts_match_the_python_decimation() raises:
    var root = mkdtemp(prefix="test gltf decimate ")
    _fixture(root)
    var source_gltf = root + "/in.gltf"
    var source_bin = root + "/in.bin"
    var out_gltf = root + "/out.gltf"
    var out_bin = root + "/out.bin"
    decimate_files(12, 4, source_gltf, source_bin, out_gltf, out_bin)
    assert_equal(
        sha256_hex(Path(out_bin).read_bytes()),
        "d61a808dda8def2e5e596eb78936abed4babda513880441924c229c93daccd7e",
    )
    assert_equal(
        sha256_hex(Path(out_gltf).read_bytes()),
        "12d03f854d8814287a8e08e72d4dd55bf1123ab41f346919f9616e099b4e394b",
    )
    var skipped_gltf = root + "/skip.gltf"
    var skipped_bin = root + "/skip.bin"
    decimate_files(
        100000, 4, source_gltf, source_bin, skipped_gltf, skipped_bin
    )
    assert_equal(Path(skipped_gltf).read_text(), Path(source_gltf).read_text())
    assert_equal(
        sha256_hex(Path(skipped_bin).read_bytes()),
        sha256_hex(Path(source_bin).read_bytes()),
    )
    Path(root + "/bad.gltf").write_text("[]")
    Path(root + "/bad.bin").write_bytes(Path(source_bin).read_bytes())
    with assert_raises(contains="glTF is not an object"):
        decimate_files(
            12,
            4,
            root + "/bad.gltf",
            root + "/bad.bin",
            root + "/no.gltf",
            root + "/no.bin",
        )
    _ = run_program(["rm", "-rf", root], 10)


def test_the_command_writes_the_mesh_and_refuses_bad_use() raises:
    var root = mkdtemp(prefix="test gltf decimate cli ")
    _fixture(root)
    var ran = run_program(
        [
            "sh",
            "tools/tool.sh",
            tool_mojo(),
            "carla_gltf_decimate",
            "12",
            "4",
            root + "/in.gltf",
            root + "/in.bin",
            root + "/out.gltf",
            root + "/out.bin",
        ],
        30,
        merge_errors=False,
    )
    assert_equal(ran.status, 0)
    assert_equal(ran.errors, "")
    assert_equal(
        sha256_hex(Path(root + "/out.bin").read_bytes()),
        "d61a808dda8def2e5e596eb78936abed4babda513880441924c229c93daccd7e",
    )
    var usage = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_gltf_decimate"],
        30,
        merge_errors=False,
    )
    assert_equal(usage.status, 2)
    assert_equal(
        usage.errors,
        (
            "usage: carla_gltf_decimate BUDGET KEEP INPUT.gltf INPUT.bin"
            " OUTPUT.gltf OUTPUT.bin\n"
        ),
    )
    var failed = run_program(
        [
            "sh",
            "tools/tool.sh",
            tool_mojo(),
            "carla_gltf_decimate",
            "nope",
            "4",
            root + "/in.gltf",
            root + "/in.bin",
            root + "/out.gltf",
            root + "/out.bin",
        ],
        30,
        merge_errors=False,
    )
    assert_true(failed.status != 0)
    assert_true(failed.errors.startswith("carla_gltf_decimate:"))
    var missing = run_program(
        [
            "sh",
            "tools/tool.sh",
            tool_mojo(),
            "carla_gltf_decimate",
            "12",
            "4",
            root + "/missing.gltf",
            root + "/in.bin",
            root + "/out.gltf",
            root + "/out.bin",
        ],
        30,
        merge_errors=False,
    )
    assert_true(missing.status != 0)
    assert_true(missing.errors.startswith("carla_gltf_decimate:"))
    _ = run_program(["rm", "-rf", root], 10)


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_gltf_decimate"],
        180,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
