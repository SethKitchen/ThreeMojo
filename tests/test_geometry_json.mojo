# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for geometries in three.js JSON: the nineteen types three.js
writes as their parameters, the `shapes` library, and lone geometry and
material documents.

`assets/geometry_json/three_scene.mjs` makes the reference with three.js
0.180: a scene of one mesh for each type, the arrays each type builds,
and a lone box, a lone geometry of arrays and a lone material.
"""

from core.assets import Assets
from core.buffer_geometry import (
    EXTRUDE_GEOMETRY,
    BUFFER_GEOMETRY,
    BOX_GEOMETRY,
    BufferGeometry,
    GeometryType,
    NORMAL,
    POSITION,
    SPHERE_GEOMETRY,
    UV,
    geometry_type_of,
)
from core.geometry_store import GeometryId
from core.object3d import Object3D
from core.scene import Scene
from core.user_data import json_value_text
from exporters.object_json import (
    geometry_to_json,
    material_to_json,
    object_to_json,
)
from geometries.box import box
from geometries.extrude import extrude
from geometries.shape import shape_geometry
from geometries.sphere import sphere
from loaders.json import (
    ARRAY,
    BOOLEAN,
    JsonDocument,
    NUMBER,
    OBJECT,
    STRING,
    parse_json,
)
from loaders.object_loader import (
    read_geometry_json,
    read_material_json,
    read_object_json,
)
from materials.material import Material, MaterialId
from math.curve3 import CurvePath3, line3
from math.path import Path as Outline, Shape
from math.vector2 import Vector2
from math.vector3 import Vector3
from render.framebuffer import Color
from render.srgb import SRGB
from render.texture import COVERAGE, NEAREST, REPEAT, Texture
from render.texture_store import NO_TEXTURE
from objects.mesh import Mesh
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Length, METER


def _reference() raises -> JsonDocument:
    """Return what three.js wrote."""
    return parse_json(Path("assets/geometry_json/scene.json").read_text())


def _part(doc: JsonDocument, key: String) raises -> String:
    """Return one part of the reference as a document of its own."""
    return json_value_text(doc, doc.get(doc.root(), key))


def _same(
    one: JsonDocument,
    a: Int,
    two: JsonDocument,
    b: Int,
    label: String,
    skip: String = "",
) raises:
    """Assert two JSON values are the same, numbers to a hundred
    thousandth, leaving out the key `skip` of the outer object."""
    var kind = one.kind(a)
    assert_true(kind == two.kind(b), label + ": a different kind")
    if kind == OBJECT:
        var keys = 0
        for at in range(one.length(a)):
            var key = one.key(a, at)
            if key == skip:
                continue
            keys += 1
            assert_true(two.has(b, key), label + " lacks " + key)
            _same(one, one.get(a, key), two, two.get(b, key), label + "." + key)
        var theirs = two.length(b) - (
            1 if skip != "" and two.has(b, skip) else 0
        )
        assert_equal(keys, theirs, label + ": keys")
    elif kind == ARRAY:
        assert_equal(one.length(a), two.length(b), label + ": length")
        for at in range(one.length(a)):
            _same(one, one.at(a, at), two, two.at(b, at), label)
    elif kind == NUMBER:
        assert_almost_equal(one.number(a), two.number(b), atol=1e-5, msg=label)
    elif kind == STRING:
        assert_equal(one.string(a), two.string(b), label)
    elif kind == BOOLEAN:
        assert_equal(one.boolean(a), two.boolean(b), label)


def _check_arrays(
    geometry: BufferGeometry,
    doc: JsonDocument,
    want: Int,
    name: String,
    atol: Float64,
) raises:
    """Assert a geometry holds three.js's arrays, index and groups."""
    var attributes: List[String] = [
        String(POSITION),
        String(NORMAL),
        String(UV),
    ]
    var keys: List[String] = ["position", "normal", "uv"]
    for at in range(3):
        var theirs = doc.get(want, keys[at])
        ref ours = geometry.attribute_view(attributes[at])
        var size = ours.item_size
        assert_equal(
            ours.count() * size, doc.length(theirs), name + " " + keys[at]
        )
        for i in range(doc.length(theirs)):
            assert_almost_equal(
                Float64(ours.component(i // size, i % size)),
                doc.number(doc.at(theirs, i)),
                atol=atol,
                msg=name + " " + keys[at] + " " + String(i),
            )
    var index = doc.get(want, "index")
    assert_equal(len(geometry.index), doc.length(index), name + " index")
    for i in range(len(geometry.index)):
        assert_equal(geometry.index[i], doc.integer(doc.at(index, i)))
    var groups = doc.get(want, "groups")
    assert_equal(len(geometry.groups), doc.length(groups), name + " groups")
    for g in range(len(geometry.groups)):
        var triple = doc.at(groups, g)
        assert_equal(geometry.groups[g].start, doc.integer(doc.at(triple, 0)))
        assert_equal(geometry.groups[g].count, doc.integer(doc.at(triple, 1)))
        assert_equal(
            geometry.groups[g].material_index.value,
            doc.integer(doc.at(triple, 2)),
        )


def test_every_type_is_built_from_its_parameters_as_three_js_builds_it() raises:
    var doc = _reference()
    var scene = Scene()
    var assets = Assets()
    _ = read_object_json(_part(doc, "scene"), scene, assets)
    var entries = doc.get(doc.get(doc.root(), "scene"), "geometries")
    var arrays = doc.get(doc.root(), "arrays")
    assert_equal(assets.geometries.count(), doc.length(entries))
    for at in range(doc.length(entries)):
        var entry = doc.at(entries, at)
        var name = doc.string(doc.get(entry, "type"))
        ref geometry = assets.geometries.get(GeometryId(at))
        assert_equal(geometry.kind.name(), name)
        # A tube and a sweep stand their rings at equal distances along a
        # curve, measured in Float32, as `test_extrude_path` allows.
        var options = doc.get(entry, "options")
        var along = name == "TubeGeometry" or (
            options != -1 and doc.has(options, "extrudePath")
        )
        _check_arrays(
            geometry, doc, doc.at(arrays, at), name, 2e-3 if along else 1e-4
        )


def test_every_type_is_written_as_three_js_writes_it() raises:
    var doc = _reference()
    var scene = Scene()
    var assets = Assets()
    _ = read_object_json(_part(doc, "scene"), scene, assets)
    var written = parse_json(object_to_json(scene, assets))
    var theirs = doc.get(doc.root(), "scene")
    var ours = written.get(written.root(), "geometries")
    var want = doc.get(theirs, "geometries")
    assert_equal(written.length(ours), doc.length(want))
    for at in range(doc.length(want)):
        _same(
            written,
            written.at(ours, at),
            doc,
            doc.at(want, at),
            "geometry " + String(at),
            skip="uuid",
        )
    # The shapes keep the uuids three.js gave them.
    var shapes = written.get(written.root(), "shapes")
    var wanted = doc.get(theirs, "shapes")
    assert_equal(written.length(shapes), doc.length(wanted))
    for at in range(doc.length(wanted)):
        _same(written, written.at(shapes, at), doc, doc.at(wanted, at), "shape")


def test_a_lone_geometry_is_written_and_read_as_three_js_does() raises:
    var doc = _reference()
    var crate = box(Length(1, METER), Length(2, METER), Length(3, METER))
    crate.name = "crate"
    var written = parse_json(geometry_to_json(crate))
    _same(
        written,
        written.root(),
        doc,
        doc.get(doc.root(), "box"),
        "box",
        skip="uuid",
    )
    var assets = Assets()
    var id = read_geometry_json(_part(doc, "box"), assets)
    ref read = assets.geometries.get(id)
    assert_true(read.kind == BOX_GEOMETRY)
    assert_equal(read.name, "crate")
    assert_equal(read.vertex_count(), crate.vertex_count())
    # A geometry of arrays, as `BufferGeometryLoader` reads it.
    var arrays = read_geometry_json(_part(doc, "data"), assets)
    ref plain = assets.geometries.get(arrays)
    assert_true(plain.kind == BUFFER_GEOMETRY)
    assert_equal(plain.vertex_count(), 3)
    assert_equal(len(plain.index), 3)
    var back = parse_json(geometry_to_json(plain))
    _same(
        back,
        back.root(),
        doc,
        doc.get(doc.root(), "data"),
        "data",
        skip="uuid",
    )


def test_a_lone_material_is_written_and_read_as_three_js_does() raises:
    var doc = _reference()
    var assets = Assets()
    var id = read_material_json(_part(doc, "material"), assets)
    var written = parse_json(material_to_json(id, assets))
    var root = written.root()
    var metadata = written.get(root, "metadata")
    assert_equal(written.string(written.get(metadata, "type")), "Material")
    assert_equal(
        written.string(written.get(metadata, "generator")), "Material.toJSON"
    )
    var theirs = doc.get(doc.root(), "material")
    for key in ["type", "color", "roughness", "metalness"]:
        _same(
            written,
            written.get(root, key),
            doc,
            doc.get(theirs, key),
            key,
        )


def test_what_a_lone_document_cannot_hold_is_refused() raises:
    var assets = Assets()
    with assert_raises(contains="must be an object"):
        _ = read_geometry_json("[]", assets)
    with assert_raises(contains="must be an object"):
        _ = read_material_json("[]", assets)
    # A lone shape geometry names shapes it does not carry.
    with assert_raises(contains="not there"):
        _ = read_geometry_json(
            '{"uuid":"g","type":"ShapeGeometry","shapes":["s"]}', assets
        )
    with assert_raises(contains="not read"):
        _ = geometry_type_of("TextGeometry")
    assert_equal(GeometryType(40).name(), "")
    assert_false(GeometryType(-1).is_valid())
    assert_true(SPHERE_GEOMETRY.is_valid())
    var ball = sphere(Length(1, METER), 8, 6)
    assert_true(ball.clone().kind == SPHERE_GEOMETRY)
    assert_equal(ball.clone().parameters.count(), 7)


def _read_one(text: String) raises -> BufferGeometry:
    """Return the geometry a lone document holds."""
    var assets = Assets()
    var id = read_geometry_json(text, assets)
    return assets.geometries.get(id).clone()


def test_a_missing_parameter_takes_three_js_default() raises:
    # Every key left out: three.js's constructor defaults.
    var flat = _read_one('{"uuid":"p","type":"PlaneGeometry"}')
    assert_equal(flat.vertex_count(), 4)
    var turned = _read_one('{"uuid":"l","type":"LatheGeometry"}')
    # A flag left out: three.js's `openEnded` of false.
    var can = _read_one('{"uuid":"c","type":"CylinderGeometry"}')
    assert_true(can.parameters.has("openEnded"))
    assert_equal(turned.vertex_count(), 13 * 3)
    # User data is kept, as `parseGeometries` keeps it.
    var tagged = _read_one(
        '{"uuid":"b","type":"BoxGeometry","userData":{"tag":1}}'
    )
    assert_true(tagged.user_data.has("tag"))


def test_a_malformed_parameter_is_refused() raises:
    with assert_raises(contains="beyond a Float64"):
        _ = _read_one('{"uuid":"b","type":"BoxGeometry","width":1e999}')
    with assert_raises(contains="must be an array"):
        _ = _read_one('{"uuid":"p","type":"PolyhedronGeometry","vertices":5}')
    with assert_raises(contains="{x, y}"):
        _ = _read_one('{"uuid":"l","type":"LatheGeometry","points":[5]}')
    with assert_raises(contains="names no shapes"):
        _ = _read_one('{"uuid":"s","type":"ShapeGeometry"}')
    with assert_raises():
        _ = _read_one('{"uuid":"p","type":"PolyhedronGeometry"}')


def _square() raises -> Shape:
    """Return a unit square."""
    var outline = Outline(Vector2(0, 0))
    outline.line_to(Vector2(1, 0))
    outline.line_to(Vector2(1, 1))
    outline.line_to(Vector2(0, 1))
    outline.line_to(Vector2(0, 0))
    return Shape(outline^)


def _scene_of(var geometry: BufferGeometry) raises -> Tuple[Scene, Assets]:
    """Return a scene of one mesh wearing `geometry`."""
    var scene = Scene()
    var assets = Assets()
    var id = assets.geometries.add(geometry^)
    var paint = assets.materials.add(Material(Color(200, 200, 200)))
    scene.add_mesh(Mesh(id, paint, scene.add(Object3D())))
    return (scene^, assets^)


def test_an_extrusion_needs_its_options_and_reads_a_curve_path() raises:
    var made = _scene_of(extrude([_square()], _curve_path()))
    var written = parse_json(object_to_json(made[0], made[1]))
    var geometries = written.get(written.root(), "geometries")
    var entry = written.at(geometries, 0)
    var options = written.get(entry, "options")
    var path = written.get(options, "extrudePath")
    assert_equal(written.string(written.get(path, "type")), "CurvePath")
    # A shape with no uuid is given one by the writer, once.
    var shapes = written.get(written.root(), "shapes")
    assert_equal(written.length(shapes), 1)
    var scene = Scene()
    var assets = Assets()
    _ = read_object_json(
        json_value_text(written, written.root()), scene, assets
    )
    assert_true(assets.geometries.get(GeometryId(0)).kind == EXTRUDE_GEOMETRY)
    var shape_id = written.string(written.at(written.get(entry, "shapes"), 0))
    var bare = (
        '{"metadata":{"version":4.7,"type":"Object"},"shapes":['
        + json_value_text(written, written.at(shapes, 0))
        + '],"geometries":[{"uuid":"g","type":"ExtrudeGeometry","shapes":["'
        + shape_id
        + '"]}],"object":{"uuid":"o","type":"Scene"}}'
    )
    with assert_raises(contains="needs its options"):
        _ = read_object_json(bare, scene, assets)
    var numbered = bare.replace(
        '"shapes":["' + shape_id + '"]}',
        '"shapes":["' + shape_id + '"],"options":5}',
    )
    with assert_raises(contains="needs its options"):
        _ = read_object_json(numbered, scene, assets)
    with assert_raises(contains="at least one shape"):
        _ = extrude(List[Shape](), _curve_path())
    with assert_raises(contains="at least one shape"):
        _ = extrude(List[Shape](), line3(Vector3(0, 0, 0), Vector3(0, 0, 1)))


def _curve_path() raises -> CurvePath3:
    """Return a path of two straight runs."""
    var path = CurvePath3()
    path.add(line3(Vector3(0, 0, 0), Vector3(0, 0, 1)))
    path.add(line3(Vector3(0, 0, 1), Vector3(0, 1, 2)))
    return path^


def test_a_lone_material_carries_its_textures() raises:
    var assets = Assets()
    var pixels: List[UInt8] = [
        255,
        0,
        0,
        255,
        0,
        255,
        0,
        255,
        0,
        0,
        255,
        255,
        255,
        255,
        255,
        255,
    ]
    var map = assets.textures.add(
        Texture(2, 2, pixels^, REPEAT, NEAREST, SRGB, False, COVERAGE)
    )
    var id = assets.materials.add(Material(Color(255, 255, 255), map=map))
    var text = material_to_json(id, assets)
    var doc = parse_json(text)
    assert_true(doc.has(doc.root(), "textures"))
    assert_true(doc.has(doc.root(), "images"))
    var read = Assets()
    var back = read_material_json(text, read)
    assert_true(read.materials.get(back).map != NO_TEXTURE)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
