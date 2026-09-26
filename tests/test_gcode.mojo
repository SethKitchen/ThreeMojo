# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.gcode`: `assets/gcode/fixture.gcode` read as three.js
0.180's `GCodeLoader` reads it, from `assets/gcode/three_gcode.mjs`."""

from core.assets import Assets
from core.buffer_geometry import POSITION
from core.object3d import Object3D
from core.scene import Scene
from loaders.gcode import gcode_layers, parse_gcode, read_gcode
from loaders.json import STRING, parse_json
from math.quaternion import Quaternion
from math.vector3 import Vector3
from objects.line import SEGMENTS
from std.math import isnan, pi
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
)
from units.si import RADIAN, Angle


def _same_group(split: Bool, key: String) raises:
    """Assert the loader adds what three.js's group holds.

    Args:
        split: three.js's `splitLayer`.
        key: The reference's entry for it.
    """
    var scene = Scene()
    var assets = Assets()
    var model = read_gcode("assets/gcode/fixture.gcode", scene, assets, split)
    var doc = parse_json(Path("assets/gcode/gcode.json").read_text())
    var want = doc.get(doc.root(), key)
    assert_equal(scene.node(model.root).name, doc.string(doc.get(want, "name")))
    var turn = Quaternion.from_axis_angle(
        Vector3(1, 0, 0), Angle(Float32(-pi / 2), RADIAN)
    )
    var q = scene.node(model.root).quaternion
    assert_almost_equal(q.x, turn.x)
    assert_almost_equal(q.w, turn.w)
    var children = doc.get(want, "children")
    assert_equal(len(model.objects), doc.length(children))
    assert_equal(len(scene.lines), doc.length(children))
    for at in range(len(model.objects)):
        var child = doc.at(children, at)
        ref object = model.objects[at]
        assert_equal(
            scene.node(object.node).name, doc.string(doc.get(child, "name"))
        )
        assert_true(scene.node(object.node).parent == model.root)
        assert_equal(
            object.extruding,
            doc.string(doc.get(child, "material")) == "extruded",
        )
        ref line = scene.lines[at]
        assert_true(line.mode == SEGMENTS)
        var color = assets.materials.get(line.material).color
        var hex = doc.integer(doc.get(child, "color"))
        assert_equal(Int(color.r), (hex >> 16) & 255)
        assert_equal(Int(color.g), (hex >> 8) & 255)
        assert_equal(Int(color.b), hex & 255)
        var got = (
            assets.geometries.get(object.geometry)
            .attribute_view(String(POSITION))
            .packed()
        )
        var positions = doc.get(child, "positions")
        assert_equal(len(got), doc.length(positions))
        for k in range(len(got)):
            var value = doc.at(positions, k)
            if doc.kind(value) == STRING:
                assert_true(isnan(got[k]))
            else:
                assert_equal(Float64(got[k]), doc.number(value))


def test_a_file_is_read_as_three_js_reads_it() raises:
    _same_group(False, "whole")


def test_a_file_is_split_into_layers_as_three_js_splits_it() raises:
    _same_group(True, "split")


def test_three_js_s_quirks_are_kept() raises:
    # `G90\r` is not `G90`, so the `G91` still holds for the move.
    var layers = gcode_layers("G1 X5\nG91\nG90\r\nG1 X1 E1\n")
    assert_equal(len(layers), 1)
    assert_equal(layers[0].vertex[3], 6)
    # A lone `;` stays in its word, and a word after a comment is gone.
    layers = gcode_layers("G1 X2;\nG1 X3 ;Y9\n")
    assert_equal(layers[0].path_vertex[3], 2)
    assert_equal(layers[0].path_vertex[10], 0)
    # A comment ends at a line terminator: here U+2028, which `split`
    # does not cut at, so the words after it join the move.
    layers = gcode_layers("G1 X4 ;c" + chr(0x2028) + "G1 X7\n")
    assert_equal(len(layers[0].path_vertex), 6)
    assert_equal(layers[0].path_vertex[3], 7)
    # A travel move before any extruding starts a layer at the height the
    # tool is at.
    layers = gcode_layers("G92 Z3\nG1 X1\n")
    assert_equal(layers[0].z, 3)
    # Nothing to read gives two empty objects.
    var scene = Scene()
    var assets = Assets()
    var model = parse_gcode("", scene, assets, parent=scene.add(Object3D()))
    assert_equal(len(model.layers), 0)
    assert_equal(scene.node(model.objects[0].node).name, "layer0")
    # Split, no layers are no objects.
    var none = parse_gcode("", scene, assets, split_layer=True)
    assert_equal(len(none.objects), 0)
    # `G0` moves as `G1` does; `G92` sets x and y; a comment ends at a
    # carriage return, or at the end of the text.
    layers = gcode_layers("G92 X1 Y2\nG0 X3 ;c\r\nG1 Y4 E1 ;end")
    assert_equal(layers[0].path_vertex[0], 1)
    assert_equal(layers[0].path_vertex[1], 2)
    assert_equal(layers[0].path_vertex[3], 3)
    assert_equal(layers[0].vertex[4], 4)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
