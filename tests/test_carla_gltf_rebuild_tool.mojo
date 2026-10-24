# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Rebuilt materials keep their factors, reuse textures, and make town glass."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._tree import tool_mojo
from tools._process import run_program
from tools._python_json import MISSING, PyJson
from tools.carla_gltf_rebuild import rebuild_text


def _python(script: String) raises -> String:
    """Return the standard output of a Python script."""
    var result = run_program(["python3", "-c", script], 30, merge_errors=False)
    if result.status != 0:
        raise Error(result.errors)
    return result.output


def _ready() raises -> String:
    """Write one red texture and return its path."""
    var lines = _python(
        "import os\n"
        + "from PIL import Image\n"
        + "root = '/tmp/carla-gltf-rebuild'\n"
        + "os.makedirs(root + '/out', exist_ok=True)\n"
        + "Image.new('RGB', (2, 2), (255, 0, 0)).save(root + '/Red.png')\n"
        + "print(root)\n"
    )
    var path = String(lines.strip())
    if path.byte_length() == 0:
        raise Error("fixture path is empty")
    return path


def _request(root: String, town: Bool, cache: String, count: Int) -> String:
    """Return one rebuild request."""
    var flag = String("false")
    if town:
        flag = "true"
    var text = String('{"material":{"name":"Wall","extensions":{"KHR":1}},')
    text += '"mat":"Diffuse=Red\\n","props":null,"pngs":{"Red":"'
    text += root
    text += '/Red.png"},"out_dir":"'
    text += root
    text += '/out","max_size":512,"texture_count":'
    text += String(count)
    text += ',"cache":'
    text += cache
    text += ',"town":'
    text += flag
    text += "}"
    return text


def test_a_color_texture_is_stored_once() raises:
    var root = _ready()
    var built = rebuild_text(_request(root, False, "[]", 0))
    var doc = PyJson.parse(built)
    assert_true(doc.find(doc.at(doc.root, "material"), "extensions") == MISSING)
    var pbr = doc.at(doc.at(doc.root, "material"), "pbrMetallicRoughness")
    var slot = doc.at(pbr, "baseColorTexture")
    assert_equal(doc.text(doc.at(slot, "index")), "0")
    assert_equal(doc.length(doc.at(doc.root, "images")), 1)
    var uri = doc.text(doc.item(doc.at(doc.root, "images"), 0))
    assert_true(Path(root + "/out/" + uri).exists())
    var cache = doc.at(doc.root, "cache_add")
    assert_equal(doc.length(cache), 1)
    assert_equal(doc.text(doc.at(doc.item(cache, 0), "index")), "0")
    var again = rebuild_text(
        _request(root, False, doc.subtree(cache).dumps(), 1)
    )
    var second = PyJson.parse(again)
    assert_equal(second.length(second.at(second.root, "images")), 0)
    var again_pbr = second.at(
        second.at(second.root, "material"), "pbrMetallicRoughness"
    )
    assert_equal(
        second.text(
            second.at(second.at(again_pbr, "baseColorTexture"), "index")
        ),
        "0",
    )


def test_town_glass_becomes_a_dark_pane() raises:
    var expected = _python(
        "import json\n"
        + "print(json.dumps([0.05, 0.065, 0.08, 1.0], separators=(',', ':')))\n"
        + "print(json.dumps(0.6))\n"
        + "print(json.dumps(0.06))\n"
    )
    var lines = expected.splitlines()
    var text = String(
        '{"material":{"name":"pane_glass"},"mat":null,"props":null,"pngs":{},'
        '"out_dir":"/tmp","max_size":64,"texture_count":0,"cache":[],"town":true}'
    )
    var doc = PyJson.parse(rebuild_text(text))
    var material = doc.at(doc.root, "material")
    assert_true(doc.find(material, "alphaMode") == MISSING)
    assert_true(doc.find(material, "extras") == MISSING)
    var pbr = doc.at(material, "pbrMetallicRoughness")
    assert_true(doc.find(pbr, "baseColorTexture") == MISSING)
    assert_equal(
        _compact_list(doc, doc.at(pbr, "baseColorFactor")), String(lines[0])
    )
    assert_equal(doc.text(doc.at(pbr, "metallicFactor")), String(lines[1]))
    assert_equal(doc.text(doc.at(pbr, "roughnessFactor")), String(lines[2]))
    var vehicle = PyJson.parse(
        rebuild_text(
            '{"material":{"name":"pane_glass"},"mat":null,"props":null,"pngs":{},'
            '"out_dir":"/tmp","max_size":64,"texture_count":0,"cache":[],"town":false}'
        )
    )
    assert_equal(
        vehicle.text(
            vehicle.at(vehicle.at(vehicle.root, "material"), "alphaMode")
        ),
        "BLEND",
    )


def test_cli_prints_the_material() raises:
    var root = _ready()
    var path = root + "/request.json"
    Path(path).write_text(_request(root, False, "[]", 0))
    var ran = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_gltf_rebuild", path],
        60,
    )
    if ran.status != 0:
        raise Error(ran.output + ran.errors)
    assert_equal(ran.output, rebuild_text(Path(path).read_text()) + "\n")
    var usage = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "carla_gltf_rebuild"],
        30,
        merge_errors=False,
    )
    assert_equal(usage.status, 2)
    assert_equal(usage.errors, "usage: carla_gltf_rebuild FILE\n")
    with assert_raises(contains="rebuild request is not an object"):
        _ = rebuild_text("[]")
    with assert_raises(contains="max_size is negative"):
        _ = rebuild_text(
            '{"material":{"name":"Wall"},"mat":null,"props":null,"pngs":{},'
            '"out_dir":"/tmp","max_size":-1,"texture_count":0,"cache":[]}'
        )


def _compact_list(doc: PyJson, node: Int) raises -> String:
    """Return a number list with no spaces."""
    var out = String("[")
    for index in range(doc.length(node)):
        if index > 0:
            out += ","
        out += doc.text(doc.item(node, index))
    out += "]"
    return out


def main() raises:
    """Build the tool, then run the tests."""
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_gltf_rebuild"],
        180,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
