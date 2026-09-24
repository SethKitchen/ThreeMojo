# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.vrml`.

`assets/vrml/<name>.json` is each object three.js 0.180's `VRMLLoader`
gives for the `.wrl` files in `assets/vrml/`, in node, in the order of
`scene.traverse`: its type, name, transform and children, and the data
of its geometry and material. `tex.png` is the image `scene.wrl` names;
node loads no images, so its texture has none there.
"""

from core.assets import Assets
from core.buffer_geometry import COLOR, NORMAL, POSITION, UV
from core.object3d import NodeId
from core.scene import Scene
from loaders.json import JsonDocument, parse_json
from loaders.vrml import (
    VRML_EMPTY,
    VRML_GROUP,
    VRML_LINES,
    VRML_MESH,
    VRML_POINTS,
    VrmlModel,
    VrmlObjectKind,
    parse_vrml,
    read_vrml,
    vrml_scene,
)
from loaders.vrml_parse import VrmlValueKind, parse_vrml_text

from materials.material import BACK_SIDE, BASIC, DOUBLE_SIDE, FRONT_SIDE, PHONG
from render.texture import CLAMP, REPEAT
from render.texture_store import NO_TEXTURE
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def near(got: Float64, want: Float64, what: String) raises:
    """Assert two numbers agree to a `Float32`."""
    var scale = max(Float64(1), abs(want))
    if not (abs(got - want) <= 2e-6 * scale):
        raise Error(what + ": got " + String(got) + ", want " + String(want))


def numbers_near(
    doc: JsonDocument, node: Int, got: List[Float32], what: String
) raises:
    """Assert a list of numbers agrees with a JSON array."""
    assert_equal(len(got), doc.length(node), what + " length")
    for i in range(len(got)):
        near(Float64(got[i]), doc.number(doc.at(node, i)), what)


def kind_of(type: String) raises -> VrmlObjectKind:
    """Return the kind a three.js type becomes."""
    if type == "Group":
        return VRML_GROUP
    if type == "Mesh":
        return VRML_MESH
    if type == "Points":
        return VRML_POINTS
    if type == "LineSegments":
        return VRML_LINES
    assert_equal(type, "Object3D")
    return VRML_EMPTY


def check(file: String) raises:
    """Compare one file with three.js."""
    var stem = file.replace(".wrl", ".json")
    var doc = parse_json(Path("assets/vrml/" + stem).read_text())
    var want = doc.root()
    var scene = Scene()
    var assets = Assets()
    var model = read_vrml("assets/vrml/" + file, scene, assets)
    var nodes = scene.traverse(model.root)
    var objects = doc.get(want, "objects")
    assert_equal(len(nodes), doc.length(objects), file + " objects")
    # three.js's geometry and material indices, as ours.
    var geometries = List[Int]()
    var materials = List[Int]()
    for i in range(len(nodes)):
        var o = doc.at(objects, i)
        var node = scene.get(nodes[i])
        var what = file + " object " + String(i)
        assert_equal(node.name, doc.string(doc.get(o, "name")), what)
        assert_equal(node.visible, doc.boolean(doc.get(o, "visible")), what)
        assert_equal(
            len(scene.children(nodes[i])),
            doc.integer(doc.get(o, "children")),
            what,
        )
        var order = doc.get(o, "renderOrder")
        if doc.kind(order) == doc.kind(doc.get(o, "name")):
            assert_equal(node.render_order, Int.MIN)
        else:
            assert_equal(node.render_order, doc.integer(order))
        var p = doc.get(o, "position")
        near(Float64(node.position.x), doc.number(doc.at(p, 0)), what)
        near(Float64(node.position.y), doc.number(doc.at(p, 1)), what)
        near(Float64(node.position.z), doc.number(doc.at(p, 2)), what)
        var q = doc.get(o, "quaternion")
        near(Float64(node.quaternion.x), doc.number(doc.at(q, 0)), what)
        near(Float64(node.quaternion.y), doc.number(doc.at(q, 1)), what)
        near(Float64(node.quaternion.z), doc.number(doc.at(q, 2)), what)
        near(Float64(node.quaternion.w), doc.number(doc.at(q, 3)), what)
        var s = doc.get(o, "scale")
        near(Float64(node.scale.x), doc.number(doc.at(s, 0)), what)
        near(Float64(node.scale.y), doc.number(doc.at(s, 1)), what)
        near(Float64(node.scale.z), doc.number(doc.at(s, 2)), what)
        var type = doc.string(doc.get(o, "type"))
        if i == 0:
            assert_equal(type, "Scene")
            assert_equal(model.object_of(nodes[i]), -1)
            continue
        var index = model.object_of(nodes[i])
        assert_true(index >= 0, what)
        ref object = model.objects[index]
        assert_equal(object.kind, kind_of(type), what)
        if not doc.has(o, "geometry"):
            assert_equal(object.geometry, -1, what)
            continue
        check_same(
            geometries, doc.integer(doc.get(o, "geometry")), object.geometry
        )
        check_same(
            materials, doc.integer(doc.get(o, "material")), object.material
        )
        check_geometry(
            doc,
            doc.get(o, "geometryData"),
            model,
            object.geometry,
            assets,
            what,
        )
        check_material(
            doc,
            doc.get(o, "materialData"),
            model,
            object.material,
            object.kind,
            what,
        )
    var info = doc.get(want, "worldInfo")
    if doc.is_null(info):
        assert_false(model.has_world_info)
    else:
        assert_true(model.has_world_info)
        if doc.has(info, "title"):
            assert_equal(
                model.title.value(), doc.string(doc.get(info, "title"))
            )
        else:
            assert_false(Bool(model.title))
        if doc.has(info, "info"):
            var lines = doc.get(info, "info")
            assert_equal(len(model.info), doc.length(lines))
            for k in range(len(model.info)):
                assert_equal(model.info[k], doc.string(doc.at(lines, k)))
        else:
            assert_equal(len(model.info), 0)


def check_same(mut seen: List[Int], theirs: Int, ours: Int) raises:
    """Assert that three.js's indices and ours name the same things."""
    while len(seen) <= theirs:
        seen.append(-1)
    if seen[theirs] < 0:
        for k in range(len(seen)):
            assert_true(seen[k] != ours, "one of ours is two of three.js's")
        seen[theirs] = ours
    assert_equal(seen[theirs], ours, "one of three.js's is two of ours")


def check_geometry(
    doc: JsonDocument,
    want: Int,
    model: VrmlModel,
    geometry: Int,
    assets: Assets,
    what: String,
) raises:
    """Compare a geometry's attributes and index with three.js."""
    ref record = model.geometries[geometry]
    assert_equal(record.name, doc.string(doc.get(want, "name")), what)
    ref g = assets.geometries.get(record.id)
    var names: List[String] = [POSITION, NORMAL, UV, COLOR]
    for name in names:
        if doc.has(want, name):
            numbers_near(
                doc,
                doc.get(want, name),
                g.clone_attribute(name).packed(),
                what + " " + name,
            )
        else:
            assert_false(g.has_attribute(name), what + " " + name)
    assert_equal(record.has_color, doc.has(want, COLOR), what)
    var index = doc.get(want, "index")
    if doc.is_null(index):
        assert_false(g.is_indexed(), what)
    else:
        assert_equal(len(g.index), doc.length(index), what + " index")
        for k in range(len(g.index)):
            assert_equal(g.index[k], doc.integer(doc.at(index, k)), what)


def check_color(
    doc: JsonDocument,
    want: Int,
    r: Float32,
    g: Float32,
    b: Float32,
    what: String,
) raises:
    """Compare a linear color with three.js's."""
    near(Float64(r), doc.number(doc.at(want, 0)), what)
    near(Float64(g), doc.number(doc.at(want, 1)), what)
    near(Float64(b), doc.number(doc.at(want, 2)), what)


def check_material(
    doc: JsonDocument,
    want: Int,
    model: VrmlModel,
    material: Int,
    kind: VrmlObjectKind,
    what: String,
) raises:
    """Compare a material with three.js's."""
    ref m = model.materials[material]
    var type = doc.string(doc.get(want, "type"))
    if kind == VRML_POINTS:
        assert_equal(type, "PointsMaterial", what)
    elif kind == VRML_LINES:
        assert_equal(type, "LineBasicMaterial", what)
    elif m.kind == PHONG:
        assert_equal(type, "MeshPhongMaterial", what)
    else:
        assert_equal(m.kind, BASIC, what)
        assert_equal(type, "MeshBasicMaterial", what)
    assert_equal(m.name, doc.string(doc.get(want, "name")), what)
    check_color(
        doc, doc.get(want, "color"), m.color.r, m.color.g, m.color.b, what
    )
    near(m.opacity, doc.number(doc.get(want, "opacity")), what)
    assert_equal(m.transparent, doc.boolean(doc.get(want, "transparent")), what)
    var sides = [FRONT_SIDE, BACK_SIDE, DOUBLE_SIDE]
    assert_equal(m.side, sides[doc.integer(doc.get(want, "side"))], what)
    assert_equal(
        m.vertex_colors, doc.boolean(doc.get(want, "vertexColors")), what
    )
    assert_equal(m.depth_write, doc.boolean(doc.get(want, "depthWrite")), what)
    assert_equal(m.depth_test, doc.boolean(doc.get(want, "depthTest")), what)
    assert_equal(m.fog, doc.boolean(doc.get(want, "fog")), what)
    if m.kind == PHONG:
        var e = doc.get(want, "emissive")
        check_color(doc, e, m.emissive.r, m.emissive.g, m.emissive.b, what)
        var sp = doc.get(want, "specular")
        check_color(doc, sp, m.specular.r, m.specular.g, m.specular.b, what)
        near(m.shininess, doc.number(doc.get(want, "shininess")), what)
    if not doc.has(want, "map"):
        assert_equal(m.map, -1, what)
        return
    var map = doc.get(want, "map")
    ref t = model.textures[m.map]
    assert_equal(t.name, doc.string(doc.get(map, "name")), what)
    var url = doc.get(map, "url")
    if doc.is_null(url):
        assert_equal(t.url, "", what)
    else:
        assert_equal(t.url, doc.string(url), what)
    var wraps = doc.integer(doc.get(map, "wrapS")), doc.integer(
        doc.get(map, "wrapT")
    )
    assert_equal(t.wrap_s, REPEAT if wraps[0] == 1000 else CLAMP, what)
    assert_equal(t.wrap_t, REPEAT if wraps[1] == 1000 else CLAMP, what)
    var offset = doc.get(map, "offset")
    near(Float64(t.offset.x), doc.number(doc.at(offset, 0)), what)
    near(Float64(t.offset.y), doc.number(doc.at(offset, 1)), what)
    var repeat = doc.get(map, "repeat")
    near(Float64(t.repeat.x), doc.number(doc.at(repeat, 0)), what)
    near(Float64(t.repeat.y), doc.number(doc.at(repeat, 1)), what)
    var center = doc.get(map, "center")
    near(Float64(t.center.x), doc.number(doc.at(center, 0)), what)
    near(Float64(t.center.y), doc.number(doc.at(center, 1)), what)
    var rotation = doc.get(map, "rotation")
    if doc.kind(rotation) == doc.kind(doc.get(map, "name")):
        # three.js sets a `Vector2` as the rotation; this turns by zero.
        assert_equal(t.rotation, 0, what)
    else:
        near(t.rotation, doc.number(rotation), what)
    var image = doc.get(map, "image")
    if doc.is_null(image):
        assert_equal(len(t.data), 0, what)
    else:
        assert_equal(t.width, doc.integer(doc.get(image, "width")), what)
        assert_equal(t.height, doc.integer(doc.get(image, "height")), what)
        var data = doc.get(image, "data")
        assert_equal(len(t.data), doc.length(data), what)
        for k in range(len(t.data)):
            assert_equal(Int(t.data[k]), doc.integer(doc.at(data, k)), what)


def test_scene_matches_three_js() raises:
    check("scene.wrl")


def test_faces_match_three_js() raises:
    check("faces.wrl")


def test_lines_and_points_match_three_js() raises:
    check("lines.wrl")


def test_solids_match_three_js() raises:
    check("solids.wrl")


def test_pixels_match_three_js() raises:
    check("pixels.wrl")


def test_empty_nodes_match_three_js() raises:
    check("edges.wrl")


def refuses(body: String, message: String) raises:
    """Assert that a file of one body is refused with a message."""
    var scene = Scene()
    var assets = Assets()
    try:
        _ = parse_vrml("#VRML V2.0 utf8\n" + body, scene, assets)
    except e:
        if not (message in String(e)):
            raise Error(body + ": " + String(e))
        return
    raise Error("not refused: " + body)


def test_refusals() raises:
    var scene = Scene()
    var assets = Assets()
    with assert_raises(contains="only version 2.0"):
        _ = parse_vrml("#VRML V1.0 ascii\nGroup { }", scene, assets)
    with assert_raises():
        _ = read_vrml("assets/vrml/missing.wrl", scene, assets)
    refuses("Transform { translation 1 2 }", "needs 3 numbers")
    refuses(
        'Shape { geometry IndexedFaceSet { coordIndex [ "a" ] } }',
        "needs numbers",
    )
    refuses("Shape { geometry IndexedFaceSet { ccw 1 } }", "TRUE or FALSE")
    refuses(
        "Shape { appearance Appearance { texture ImageTexture { url 5 } } }",
        "needs strings",
    )
    refuses(
        "Shape { geometry ElevationGrid { xDimension 1.5 } }", "whole number"
    )
    refuses("Shape { geometry ElevationGrid { } }", "not there")
    var points = "coord Coordinate { point [ 0 0 0, 1 0 0, 0 1 0 ] } "
    refuses(
        "Shape { geometry IndexedFaceSet { "
        + points
        + "coordIndex [ 0 1 5 ] } }",
        "names no point",
    )
    refuses(
        "Shape { geometry IndexedFaceSet { "
        + points
        + "coordIndex [ 0 1 5 ] normal Normal { vector [ 0 0 1 ] } } }",
        "not there",
    )
    var colored = (
        "Shape { geometry IndexedFaceSet { "
        + points
        + "coordIndex [ 0 1 2 ] color Color { color [ 1 0 0, 0 1 0 ] }"
        + " colorPerVertex FALSE colorIndex [ "
    )
    refuses(colored + "1.5 ] } }", "not there")
    refuses(colored + "7 ] } }", "not there")
    refuses(
        "Shape { geometry IndexedLineSet { "
        + points
        + "coordIndex [ 0 1 2 ] color Color { color [ 1 0 0 ] } colorIndex [ 0"
        " 0 0 ] } }",
        "not there",
    )
    refuses(
        (
            "Shape { appearance Appearance { texture PixelTexture { image 1 1 1"
            " 1e-7 } } }"
        ),
        "exponent",
    )
    refuses('Shape { appearance "x" }', "needs a node")
    refuses("Group { children [ USE NOWHERE ] }", "which no DEF names")
    refuses("DEF G Group { children [ USE G ] }", "uses itself")
    refuses("Background { skyColor [ 0 0 1, 1 1 1 ] }", "needs skyAngle")
    refuses("Background { skyColor [ 0 0 ] }", "needs 3 numbers")
    refuses("Background { groundColor [ 0 0 1 ] }", "two colors")
    refuses("Background { groundColor [ 0 0 1, 1 1 1 ] }", "groundAngle")
    refuses("Shape { appearance Box { } }", "needs an Appearance")
    refuses("Shape { geometry Group { } }", "geometry node")
    refuses(
        "Shape { appearance Appearance { material Box { } } }",
        "needs a Material",
    )
    refuses(
        "Shape { appearance Appearance { textureTransform Box { } } }",
        "needs a TextureTransform",
    )
    refuses(
        (
            "Shape { appearance Appearance { material NULL"
            " material Material { emissiveColor 1 0 0 } } }"
        ),
        "material NULL",
    )
    refuses("WorldInfo { title [ ] }", "needs a string")
    refuses("Shape { geometry PointSet { coord Box { } } }", "needs a Color")
    refuses("Shape { geometry PointSet { coord Coordinate { } } }", "no values")
    refuses("Shape { geometry IndexedLineSet { } }", "no coordIndex")
    refuses(
        (
            "Shape { geometry IndexedLineSet { coordIndex [ ] color Color {"
            " color [ ] } } }"
        ),
        "no colorIndex",
    )
    refuses(
        "Shape { geometry PointSet { coord Coordinate { point [ 0 0 ] } } }",
        "whole points",
    )
    refuses(
        (
            "Shape { geometry PointSet { coord Coordinate { point [ 0 0 0 ] }"
            " color Color { color [ ] } } }"
        ),
        "a color for each point",
    )
    refuses(
        "Shape { geometry Extrusion { crossSection [ 0 0 1 ] } }", "odd count"
    )
    refuses("Shape { geometry Extrusion { spine [ 0 0 ] } }", "whole points")
    refuses("Shape { appearance [ ] }", "needs a value")
    refuses(
        (
            "Shape { appearance Appearance { texture PixelTexture { image 1 1"
            " } } }"
        ),
        "a width, a height",
    )
    refuses(
        (
            "Shape { appearance Appearance { texture PixelTexture { image 1 1"
            ' "x" } } }'
        ),
        "a width, a height",
    )
    refuses(
        (
            "Shape { appearance Appearance { texture PixelTexture { image 1 1 1"
            " 0xFF TRUE } } }"
        ),
        "not a number",
    )
    refuses(
        (
            "Shape { appearance Appearance { texture PixelTexture { image 1 1 3"
            " 255 } } }"
        ),
        "needs a hex number",
    )
    # A material refuses an opacity above one.
    refuses(
        (
            "Shape { appearance Appearance { material Material { transparency"
            " -0.5 } } geometry Box { } }"
        ),
        "Opacity",
    )


def test_a_field_kind_that_is_not_valid() raises:
    var tree = parse_vrml_text("#VRML V2.0\nGroup { children [ ] }")
    tree.nodes[0].fields[0].kind = VrmlValueKind(9)
    var scene = Scene()
    var assets = Assets()
    with assert_raises(contains="kind is not valid"):
        _ = vrml_scene(tree^, scene, assets, "")


def test_counts_and_names() raises:
    var scene = Scene()
    var assets = Assets()
    var model = read_vrml("assets/vrml/scene.wrl", scene, assets)
    assert_equal(model.count(VRML_MESH), 12)
    assert_equal(model.count(VRML_GROUP), 7)
    with assert_raises(contains="not valid"):
        _ = model.count(VrmlObjectKind(7))
    # The file's image was read, and repeats on neither axis.
    var texture = model.textures[0].id
    assert_true(texture != NO_TEXTURE)
    assert_equal(assets.textures.get(texture).width, 2)
    assert_equal(assets.textures.get(texture).wrap, CLAMP)
    # A file with no objects.
    var empty = parse_vrml("#VRML V2.0\nColor { color [ ] }", scene, assets)
    assert_equal(empty.object_of(empty.root), -1)
    assert_equal(empty.count(VRML_MESH), 0)
    # A background with no fields is an empty group, and a grid of one
    # row colored per quad has no quads.
    var bare = parse_vrml(
        (
            "#VRML V2.0\nBackground { }\nShape { geometry ElevationGrid {"
            " xDimension 3 zDimension 1 height [ 1 2 3 ] color Color { color ["
            " ] } colorPerVertex FALSE } }"
        ),
        scene,
        assets,
    )
    assert_equal(len(scene.children(bare.objects[0].node)), 0)
    ref grid = assets.geometries.get(model.geometries[0].id)
    assert_true(grid.has_attribute(COLOR))
    ref row = assets.geometries.get(bare.geometries[0].id)
    assert_equal(len(row.clone_attribute(COLOR).packed()), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
