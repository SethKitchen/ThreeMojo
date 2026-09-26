# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.ldraw` and `loaders.ldraw_parse`.

`assets/ldraw/ldraw.json` holds what three.js 0.180's `LDrawLoader` makes
of `assets/ldraw/scene.mpd`, its parts in `assets/ldraw/library/`, written
by `three_ldraw.mjs`: loaded, loaded with no smoothing, parsed with no
default colors, and loaded with a file map. Each group, object, attribute,
material group and material must match.
"""

from loaders.json import BOOLEAN, JsonDocument, NULL, NUMBER, STRING, parse_json
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.scene import Scene
from loaders.ldraw import (
    LDrawModel,
    LDrawNode,
    TO_THE_END,
    load_ldraw,
    parse_ldraw,
    read_ldraw,
)
from math.vector3 import Vector3
from renderers.renderer import Renderer
from units.si import DEGREE, METER, Angle, Length
from loaders.ldraw_parse import LDrawLoader, LDrawMaterial, _style, js_parse_int
from std.math import isnan
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

comptime LIBRARY = "assets/ldraw/library/"


def _reference() raises -> JsonDocument:
    return parse_json(Path("assets/ldraw/ldraw.json").read_text())


def _optional(
    got: Optional[String], doc: JsonDocument, node: Int, what: String
) raises:
    if doc.kind(node) == NULL:
        assert_false(Bool(got), what)
    else:
        assert_true(Bool(got), what)
        assert_equal(got.value(), doc.string(node), what)


def _material(
    model: LDrawModel,
    slot: Int,
    code: String,
    doc: JsonDocument,
    want: Int,
    what: String,
) raises:
    if doc.kind(want) == NULL:
        assert_equal(slot, -2, what)
        return
    if not doc.has(want, "type"):
        assert_equal(slot, -1, what)
        assert_equal(code, doc.string(doc.get(want, "code")), what)
        return
    assert_true(slot >= 0, what)
    _same_material(model.loader.all[slot], doc, want, what)


def _same_material(
    m: LDrawMaterial, doc: JsonDocument, want: Int, what: String
) raises:
    var name = what + " " + m.name
    assert_equal(m.type, doc.string(doc.get(want, "type")), name)
    assert_equal(m.name, doc.string(doc.get(want, "name")), name)
    _optional(m.code, doc, doc.get(want, "code"), name + " code")
    var color = doc.get(want, "color")
    for k in range(3):
        assert_almost_equal(
            m.color[k], doc.number(doc.at(color, k)), atol=1e-12, msg=name
        )
    if doc.has(want, "emissive"):
        var e = doc.get(want, "emissive")
        for k in range(3):
            assert_almost_equal(
                m.emissive[k], doc.number(doc.at(e, k)), atol=1e-12, msg=name
            )
    if doc.has(want, "roughness"):
        assert_almost_equal(
            m.roughness,
            doc.number(doc.get(want, "roughness")),
            atol=1e-12,
            msg=name,
        )
        assert_almost_equal(
            m.metalness,
            doc.number(doc.get(want, "metalness")),
            atol=1e-12,
            msg=name,
        )
    assert_almost_equal(
        m.opacity, doc.number(doc.get(want, "opacity")), atol=1e-12, msg=name
    )
    assert_equal(m.transparent, doc.boolean(doc.get(want, "transparent")), name)
    assert_equal(m.depth_write, doc.boolean(doc.get(want, "depthWrite")), name)
    assert_equal(
        m.premultiplied_alpha,
        doc.boolean(doc.get(want, "premultipliedAlpha")),
        name,
    )
    assert_equal(
        m.polygon_offset, doc.boolean(doc.get(want, "polygonOffset")), name
    )
    assert_almost_equal(
        m.polygon_offset_factor,
        doc.number(doc.get(want, "polygonOffsetFactor")),
        atol=0,
        msg=name,
    )


def _floats(
    got: List[Float32], doc: JsonDocument, want: Int, what: String
) raises:
    assert_equal(len(got), doc.length(want), what)
    for k in range(len(got)):
        var w = doc.at(want, k)
        if doc.kind(w) == STRING:
            var text = doc.string(w)
            if text == "NaN":
                assert_true(isnan(got[k]), what)
            else:
                assert_equal(
                    got[k],
                    Float32.MAX * 2 if text == "Infinity" else -Float32.MAX * 2,
                    what,
                )
        else:
            assert_almost_equal(
                Float64(got[k]),
                doc.number(w),
                atol=1e-6,
                msg=what + " " + String(k),
            )


def _node(
    model: LDrawModel,
    index: Int,
    doc: JsonDocument,
    want: Int,
    path: String,
    root: Bool,
) raises:
    ref n = model.nodes[index]
    var what = path + "/" + n.type + ":" + n.name
    assert_equal(n.type, doc.string(doc.get(want, "type")), what)
    assert_equal(n.name, doc.string(doc.get(want, "name")), what)
    var position = doc.get(want, "position")
    var quaternion = doc.get(want, "quaternion")
    var scale = doc.get(want, "scale")
    for k in range(3):
        assert_almost_equal(
            n.position[k], doc.number(doc.at(position, k)), atol=1e-9, msg=what
        )
        assert_almost_equal(
            n.scale[k], doc.number(doc.at(scale, k)), atol=1e-9, msg=what
        )
    for k in range(4):
        assert_almost_equal(
            n.quaternion[k],
            doc.number(doc.at(quaternion, k)),
            atol=1e-9,
            msg=what,
        )
    var data = doc.get(want, "userData")
    if n.is_group_data:
        _optional(
            n.category, doc, doc.get(data, "category"), what + " category"
        )
        _optional(n.author, doc, doc.get(data, "author"), what + " author")
        _optional(n.part_type, doc, doc.get(data, "type"), what + " type")
        if root:
            assert_true(
                n.file_name.value().endswith(
                    doc.string(doc.get(data, "fileName"))
                ),
                what,
            )
            assert_equal(
                model.building_steps,
                doc.integer(doc.get(data, "numBuildingSteps")),
            )
        else:
            _optional(
                n.file_name, doc, doc.get(data, "fileName"), what + " file"
            )
        var keywords = doc.get(data, "keywords")
        if doc.kind(keywords) == NULL:
            assert_false(Bool(n.keywords), what)
        else:
            ref words = n.keywords.value()
            assert_equal(len(words), doc.length(keywords), what)
            for k in range(len(words)):
                assert_equal(words[k], doc.string(doc.at(keywords, k)), what)
        if doc.has(data, "colorCode"):
            assert_equal(
                n.color_code.value(),
                doc.string(doc.get(data, "colorCode")),
                what,
            )
        if doc.has(data, "startingBuildingStep"):
            assert_equal(
                n.starting_building_step.value(),
                doc.boolean(doc.get(data, "startingBuildingStep")),
                what,
            )
        assert_equal(
            n.building_step, doc.integer(doc.get(data, "buildingStep")), what
        )
    if doc.has(want, "attributes"):
        var attributes = doc.get(want, "attributes")
        _floats(
            n.positions,
            doc,
            doc.get(attributes, "position"),
            what + " position",
        )
        if doc.has(attributes, "normal"):
            _floats(
                n.normals, doc, doc.get(attributes, "normal"), what + " normal"
            )
        if doc.has(attributes, "control0"):
            _floats(
                n.control0,
                doc,
                doc.get(attributes, "control0"),
                what + " control0",
            )
            _floats(
                n.control1,
                doc,
                doc.get(attributes, "control1"),
                what + " control1",
            )
            _floats(
                n.direction,
                doc,
                doc.get(attributes, "direction"),
                what + " direction",
            )
        var groups = doc.get(want, "groups")
        assert_equal(len(n.groups), doc.length(groups), what)
        for k in range(len(n.groups)):
            var g = doc.at(groups, k)
            assert_equal(n.groups[k].start, doc.integer(doc.at(g, 0)), what)
            var count = doc.at(g, 1)
            if doc.kind(count) == STRING:
                assert_equal(n.groups[k].count, TO_THE_END, what)
            else:
                assert_equal(n.groups[k].count, doc.integer(count), what)
            assert_equal(
                n.groups[k].material_index, doc.integer(doc.at(g, 2)), what
            )
        var material = doc.get(want, "material")
        if n.single:
            _material(model, n.slots[0], n.codes[0], doc, material, what)
        else:
            assert_equal(len(n.slots), doc.length(material), what)
            for k in range(len(n.slots)):
                _material(
                    model,
                    n.slots[k],
                    n.codes[k],
                    doc,
                    doc.at(material, k),
                    what,
                )
    var children = doc.get(want, "children")
    assert_equal(len(n.children), doc.length(children), what)
    for k in range(len(n.children)):
        _node(model, n.children[k], doc, doc.at(children, k), what, False)


def _same(model: LDrawModel, doc: JsonDocument, name: String) raises:
    var want = doc.get(doc.root(), name)
    _node(model, model.root, doc, doc.get(want, "group"), name, True)
    var library = doc.get(want, "materials")
    assert_equal(len(model.loader.materials), doc.length(library), name)
    for k in range(len(model.loader.materials)):
        _same_material(
            model.loader.all[model.loader.materials[k]],
            doc,
            doc.at(library, k),
            name + " library",
        )


def test_a_model_is_read_as_three_js_reads_it() raises:
    var doc = _reference()
    _same(
        read_ldraw("assets/ldraw/scene.mpd", LDrawLoader(LIBRARY)), doc, "scene"
    )


def test_a_model_without_smoothing() raises:
    var doc = _reference()
    var loader = LDrawLoader(LIBRARY)
    loader.smooth_normals = False
    _same(read_ldraw("assets/ldraw/scene.mpd", loader^), doc, "flat")


def test_a_parsed_model_has_no_default_colors() raises:
    var doc = _reference()
    var text = Path("assets/ldraw/scene.mpd").read_text()
    _same(parse_ldraw(text, LDrawLoader(LIBRARY)), doc, "parsed")


def test_a_file_map_names_another_file() raises:
    var doc = _reference()
    var loader = LDrawLoader(LIBRARY)
    # A name mapped to nothing is not mapped, as JavaScript's `''` is
    # false; the first name that maps is used.
    loader.set_file_map(
        ["brick.dat", "plate.dat", "plate.dat"],
        ["", "parts/brick.dat", "plate.dat"],
    )
    _same(read_ldraw("assets/ldraw/scene.mpd", loader^), doc, "mapped")


def test_a_model_goes_into_a_scene_and_draws() raises:
    var model = read_ldraw("assets/ldraw/scene.mpd", LDrawLoader(LIBRARY))
    var scene = Scene()
    var assets = Assets()
    load_ldraw(model, scene, assets)
    assert_equal(len(scene.meshes), 9)
    var conditional = 0
    for line in scene.lines:
        if line.conditional:
            conditional += 1
    # Three bricks' conditional edges, in two colors each.
    assert_equal(conditional, 6)
    # The second brick is mirrored.
    var mirrored = scene.get(
        model.scene_nodes[model.nodes[model.root].children[1]]
    )
    assert_almost_equal(mirrored.scale.x, -1, atol=1e-6)
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE), 1, Length(0.1, METER), Length(100.0, METER)
    )
    camera.position = Vector3(10, -10, 20)
    camera.target = Vector3(0, 0, 0)
    var image = Renderer(32, 32).render(scene, assets, camera)
    assert_equal(image.width, 32)


def test_every_corner_is_read_as_three_js_reads_it() raises:
    var doc = _reference()
    _same(
        read_ldraw("assets/ldraw/kitchen.mpd", LDrawLoader(LIBRARY)),
        doc,
        "kitchen",
    )


def test_a_file_three_js_cannot_read_is_refused() raises:
    var doc = _reference()
    var root = doc.root()
    var count = 0
    for k in range(doc.length(root)):
        var name = doc.key(root, k)
        if not name.startswith("broken/"):
            continue
        count += 1
        assert_true(doc.has(doc.get(root, name), "error"), name)
        with assert_raises():
            _ = read_ldraw("assets/ldraw/" + name, LDrawLoader(LIBRARY))
    assert_equal(count, 8)


def test_parse_int_and_color_styles_are_javascript_s() raises:
    assert_equal(js_parse_int(" 	+0x1F"), 31)
    assert_equal(js_parse_int("-12abc"), -12)
    assert_equal(js_parse_int("0Xaf"), 175)
    assert_true(isnan(js_parse_int("x")))
    assert_true(isnan(js_parse_int("0xg")))
    assert_equal(js_parse_int("05!"), 5)
    assert_equal(js_parse_int("0x1@"), 1)
    assert_false(Bool(_style("#!")))
    assert_false(Bool(_style("#z")))
    assert_false(Bool(_style("#@")))
    assert_false(Bool(_style("#")))
    assert_false(Bool(_style("red")))
    assert_false(Bool(_style("#12345")))
    assert_false(Bool(_style("#GG0000")))
    assert_almost_equal(_style("#FFF").value()[0], 1)
    assert_almost_equal(_style("#ff8000").value()[0], 1)


def test_a_missing_conditional_material_is_not_drawn() raises:
    # Parsed with no default colors, color 16 is missing, and three.js
    # leaves its conditional edges with no material.
    var text = Path("assets/ldraw/scene.mpd").read_text()
    var model = parse_ldraw(text, LDrawLoader(LIBRARY))
    var scene = Scene()
    var assets = Assets()
    load_ldraw(model, scene, assets)
    var kitchen = read_ldraw("assets/ldraw/kitchen.mpd", LDrawLoader(LIBRARY))
    load_ldraw(kitchen, scene, assets)
    assert_true(len(scene.lines) > 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
