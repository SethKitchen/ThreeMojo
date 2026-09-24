# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.amf`.

`assets/amf/fixture.json` is what three.js 0.180's `AMFLoader` gives for
`assets/amf/fixture.amf` and `assets/amf/fixture.zip` in node: the
objects in their order, and each mesh's attributes, index and material.
"""

from core.assets import Assets
from core.buffer_geometry import NORMAL, POSITION
from core.object3d import Object3D
from core.scene import Scene
from loaders.amf import (
    AmfColor,
    amf_material,
    amf_unit_scale,
    parse_amf,
    read_amf,
)
from loaders.json import JsonDocument, parse_json
from loaders.zip import ZIP_STORED, ZipEntry, zip_archive
from render.framebuffer import Color
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def near(got: Float64, want: Float64) raises:
    """Assert two numbers agree to a `Float32`."""
    var scale = max(Float64(1), abs(want))
    if not (abs(got - want) <= 1e-6 * scale):
        raise Error("got " + String(got) + ", want " + String(want))


def hex(color: Color) -> String:
    """Return a color as three.js's `getHexString`."""
    comptime digits = "0123456789abcdef"
    var out = String()
    for byte in [color.r, color.g, color.b]:
        out += digits[byte=Int(byte) // 16]
        out += digits[byte=Int(byte) % 16]
    return out^


def check(file: String) raises:
    """Compare one fixture with three.js."""
    var scene = Scene()
    var assets = Assets()
    var model = read_amf("assets/amf/" + file, scene, assets)
    var doc = parse_json(Path("assets/amf/fixture.json").read_text())
    var want = doc.get(doc.root(), file)
    assert_equal(model.name, doc.string(doc.get(want, "name")))
    assert_equal(scene.get(model.root).name, model.name)
    assert_equal(model.author, doc.string(doc.get(want, "author")))
    var objects = doc.get(want, "objects")
    assert_equal(len(model.objects), doc.length(objects))
    var mesh = model.first_mesh
    for o in range(len(model.objects)):
        var wo = doc.at(objects, o)
        assert_equal(
            scene.get(model.objects[o]).name, doc.string(doc.get(wo, "name"))
        )
        var meshes = doc.get(wo, "meshes")
        for m in range(doc.length(meshes)):
            var wm = doc.at(meshes, m)
            ref drawn = scene.meshes[mesh]
            assert_true(drawn.node == model.objects[o])
            ref geometry = assets.geometries.get(drawn.geometry)
            var position = geometry.clone_attribute(String(POSITION)).packed()
            var values = doc.get(wm, "position")
            assert_equal(len(position), doc.length(values))
            for k in range(len(position)):
                near(Float64(position[k]), doc.number(doc.at(values, k)))
            var normal = doc.get(wm, "normal")
            assert_equal(
                geometry.has_attribute(String(NORMAL)), not doc.is_null(normal)
            )
            if not doc.is_null(normal):
                var got = geometry.clone_attribute(String(NORMAL)).packed()
                for k in range(len(got)):
                    near(Float64(got[k]), doc.number(doc.at(normal, k)))
            var index = doc.get(wm, "index")
            assert_equal(len(geometry.index), doc.length(index))
            for k in range(len(geometry.index)):
                assert_equal(geometry.index[k], doc.integer(doc.at(index, k)))
            var material = assets.materials.get(drawn.material)
            var wmat = doc.get(wm, "material")
            assert_equal(
                model.material_names[mesh - model.first_mesh],
                doc.string(doc.get(wmat, "name")),
            )
            assert_equal(
                hex(material.color), doc.string(doc.get(wmat, "color"))
            )
            assert_equal(
                material.transparent, doc.boolean(doc.get(wmat, "transparent"))
            )
            near(
                Float64(material.opacity), doc.number(doc.get(wmat, "opacity"))
            )
            assert_equal(
                material.flat_shading, doc.boolean(doc.get(wmat, "flat"))
            )
            mesh += 1
    assert_equal(mesh - model.first_mesh, model.mesh_count)


def test_the_fixtures_match_three_js() raises:
    check("fixture.amf")
    check("fixture.zip")


def text_bytes(text: String) -> List[UInt8]:
    """Return a text as the bytes of a file."""
    var out = List[UInt8]()
    for byte in text.as_bytes():
        out.append(byte)
    return out^


def load(text: String) raises -> Int:
    """Read an AMF text and return how many meshes it drew."""
    var scene = Scene()
    var assets = Assets()
    return parse_amf(text_bytes(text), scene, assets).mesh_count


comptime TRIANGLE = (
    "<mesh><vertices><vertex><coordinates><x>0</x><y>0</y><z>0</z>"
    + "</coordinates></vertex><vertex><coordinates><x>1</x><y>0</y><z>0</z>"
    + "</coordinates></vertex><vertex><coordinates><x>0</x><y>1</y><z>0</z>"
    + "</coordinates></vertex></vertices><volume><triangle><v1>0</v1>"
    + "<v2>1</v2><v3>2</v3></triangle></volume></mesh>"
)


def test_units_ids_and_archives() raises:
    near(amf_unit_scale("MILLIMETER"), 1)
    near(amf_unit_scale("feet"), 304.8)
    near(amf_unit_scale("meter"), 1000)
    near(amf_unit_scale("parsec"), 1)
    # A later object of the same id takes the earlier one's place.
    var scene = Scene()
    var assets = Assets()
    var parent = scene.add(Object3D())
    var model = parse_amf(
        text_bytes(
            "<AMF><object id='a'>"
            + TRIANGLE
            + "</object><object id='b'/>"
            + "<object id='a'><metadata type='name'>Again</metadata>"
            + "<metadata>x</metadata><other/></object></AMF>"
        ),
        scene,
        assets,
        parent,
    )
    assert_equal(len(model.objects), 2)
    assert_equal(model.object_names[0], "Again")
    assert_equal(model.object_ids[1], "b")
    assert_equal(model.mesh_count, 0)
    assert_true(scene.get(model.root).parent == parent)
    # An archive with no `.amf` reads its last file.
    var entries = List[ZipEntry]()
    entries.append(ZipEntry("a.txt", ZIP_STORED, text_bytes("x")))
    entries.append(
        ZipEntry(
            "b.xml",
            ZIP_STORED,
            text_bytes("<amf><object id='1'>" + TRIANGLE + "</object></amf>"),
        )
    )
    var zipped = zip_archive(entries)
    assert_equal(parse_amf(zipped, scene, assets).mesh_count, 1)
    var material = amf_material(AmfColor())
    assert_false(material.transparent)
    assert_equal(load("<amf/>"), 0)
    # Elements three.js steps over, empty ones, a coordinate nested
    # deeper, a normal of no length, and a material id with no materials.
    var odd = parse_amf(
        text_bytes(
            "<amf><constellation/><object id='1'><color><c>1</c></color>"
            + "<mesh/><mesh><edges/><volume/></mesh><mesh><vertices><x/>"
            + "<vertex/><vertex><color/><coordinates><w><x>4</x></w><y>0</y>"
            + "<z>0</z></coordinates><normal><nx>0</nx><ny>0</ny><nz>0</nz>"
            + "</normal></vertex></vertices><volume materialid='m'/></mesh>"
            + "<mesh><vertices/></mesh></object></amf>"
        ),
        scene,
        assets,
    )
    assert_equal(odd.mesh_count, 2)
    ref placed = assets.geometries.get(odd.geometries[1])
    assert_equal(placed.clone_attribute(String(POSITION)).packed(), [4, 0, 0])
    assert_equal(placed.clone_attribute(String(NORMAL)).packed(), [0, 0, 0])
    var materials = parse_amf(
        text_bytes(
            "<amf><material id='m'/><material id='n'><other/><color/>"
            + "</material><object id='1'>"
            + String(TRIANGLE).replace("<volume>", "<volume materialid='n'>")
            + "</object></amf>"
        ),
        scene,
        assets,
    )
    assert_equal(materials.material_names[0], "AMF Material")


def object_with(old: String, new: String) -> String:
    """Return a file of one object whose mesh has a text replaced."""
    return (
        "<amf><object id='1'>"
        + String(TRIANGLE).replace(old, new)
        + "</object></amf>"
    )


def test_refusals() raises:
    with assert_raises(contains="no `<amf>`"):
        _ = load("<model/>")
    with assert_raises(contains="`<material>` has no `id`"):
        _ = load("<amf><material/></amf>")
    with assert_raises(contains="`<object>` has no `id`"):
        _ = load("<amf><object/></amf>")
    with assert_raises(contains="has no `<z>`"):
        _ = load(
            "<amf><object id='1'><mesh><vertices><vertex><coordinates>"
            + "<x>0</x><y>0</y></coordinates></vertex></vertices></mesh>"
            + "</object></amf>"
        )
    with assert_raises(contains="coordinate is not a number"):
        _ = load(object_with("<x>1</x>", "<x>one</x>"))
    with assert_raises(contains="coordinate is not a number"):
        _ = load(object_with("<x>1</x>", "<x>inf</x>"))
    with assert_raises(contains="color is not a number"):
        _ = load(
            "<amf><material id='m'><color><g>x</g></color></material></amf>"
        )
    with assert_raises(contains="not a whole number"):
        _ = load(object_with("<v1>0</v1>", "<v1>0.5</v1>"))
    with assert_raises(contains="not a whole number"):
        _ = load(object_with("<v1>0</v1>", "<v1>-1</v1>"))
    with assert_raises(contains="not there"):
        _ = load(object_with("<v1>0</v1>", "<v1>3</v1>"))
    with assert_raises(contains="normals for some vertices only"):
        _ = load(
            object_with(
                "</coordinates></vertex></vertices>",
                "</coordinates><normal><nx>0</nx><ny>0</ny><nz>1</nz></normal>"
                + "</vertex></vertices>",
            )
        )
    with assert_raises(contains="no files"):
        var scene = Scene()
        var assets = Assets()
        _ = parse_amf(zip_archive(List[ZipEntry]()), scene, assets)
    with assert_raises():
        var scene = Scene()
        var assets = Assets()
        _ = read_amf("assets/amf/missing.amf", scene, assets)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
