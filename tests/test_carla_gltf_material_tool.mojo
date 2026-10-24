# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Vehicle material factors match the Python rules before images are encoded."""

from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_true

from tests._tree import tool_mojo
from tools._process import run_program
from tools._python_json import MISSING, PyJson
from tools.carla_gltf_material import plan_material


def _plan(text: String) raises -> PyJson:
    """Return a parsed material plan."""
    return PyJson.parse(plan_material(text))


def test_names_choose_glass_rubber_and_plain_factors() raises:
    var glass = _plan('{"name":"SideWindow","mat":null,"props":null,"pngs":[]}')
    assert_equal(doc_text(glass, "alphaMode"), "BLEND")
    assert_equal(factor(glass, 3), "0.35")
    assert_true(glass.find(glass.root, "textures") != MISSING)
    assert_equal(glass.length(glass.at(glass.root, "textures")), 0)
    var rubber = _plan('{"name":"Tire","mat":null,"props":null,"pngs":[]}')
    assert_equal(factor(rubber, 3), "1")
    assert_true(rubber.find(rubber.root, "alphaMode") == MISSING)
    var plain = _plan('{"name":"Door","mat":null,"props":null,"pngs":[]}')
    assert_equal(factor(plain, 0), "0.5")
    assert_equal(plain.text(plain.at(plain.root, "roughnessFactor")), "0.6")


def test_paint_props_and_a_leaf_mask_choose_textures() raises:
    var paint = _plan(
        '{"name":"Hood","mat":"Diffuse=Body\\n","props":"Parent ='
        " Material'/Game/M_CarPaint.M_CarPaint'\\nName=Base Color"
        " }\\nParameterValue = { R=0.2, G=0.3, B=0.4, A=1"
        ' }\\n","pngs":["Body"]}'
    )
    assert_equal(
        paint.text(paint.at(paint.at(paint.root, "extras"), "carla")), "paint"
    )
    assert_equal(paint.length(paint.at(paint.root, "textures")), 0)
    assert_equal(factor(paint, 0), "0.2")
    var leaf = _plan(
        '{"name":"Leaf","mat":"Diffuse=AlphaMask\\nOther[0]=Leaf_Front\\nOpacity=Mask\\n","props":"BlendMode'
        ' = BLEND_Masked\\n","pngs":["Leaf_Front","Mask","AlphaMask"]}'
    )
    assert_equal(doc_text(leaf, "alphaMode"), "MASK")
    assert_equal(leaf.text(leaf.at(leaf.root, "alphaCutoff")), "0.3333")
    assert_true(leaf.flag(leaf.at(leaf.root, "doubleSided")))
    var steps = leaf.at(leaf.root, "textures")
    assert_equal(leaf.text(leaf.at(leaf.item(steps, 0), "kind")), "color")
    assert_equal(leaf.text(leaf.at(leaf.item(steps, 0), "stem")), "AlphaMask")
    var step = leaf.item(steps, 1)
    assert_equal(leaf.text(leaf.at(step, "kind")), "masked")
    assert_equal(leaf.text(leaf.at(step, "color")), "Leaf_Front")
    assert_equal(leaf.text(leaf.at(step, "mask")), "Mask")
    var report = leaf.at(leaf.root, "report")
    assert_equal(
        leaf.text(leaf.item(leaf.item(report, 1), 0)), "baseColorTexture"
    )


def test_the_tool_prints_a_plan() raises:
    var directory = mkdtemp(prefix="gltf material ")
    Path(directory + "/request.json").write_text(
        '{"name":"HeadLight","mat":null,"props":null,"pngs":[]}'
    )
    var result = run_program(
        [
            "sh",
            "tools/tool.sh",
            tool_mojo(),
            "carla_gltf_material",
            directory + "/request.json",
        ],
        60,
        merge_errors=False,
    )
    assert_equal(result.status, 0)
    var doc = PyJson.parse(result.output)
    assert_equal(doc.text(doc.at(doc.at(doc.root, "extras"), "carla")), "lamps")
    assert_true(doc.find(doc.root, "alphaMode") == MISSING)
    assert_true(result.errors.find("Crashpad") < 0)
    _ = run_program(["rm", "-rf", directory], 10)


def factor(doc: PyJson, index: Int) raises -> String:
    """Return one base-color component's text."""
    return doc.text(doc.item(doc.at(doc.root, "baseColorFactor"), index))


def doc_text(doc: PyJson, key: String) raises -> String:
    """Return one string field."""
    return doc.text(doc.at(doc.root, key))


def main() raises:
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "carla_gltf_material"],
        180,
    )
    if built.status != 0:
        raise Error(built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
