# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.usd`: `assets/usd/cube.usda` and `scene.usdz` read
as three.js 0.180's `USDLoader` reads them, from
`assets/usd/three_usd.mjs`."""

from core.assets import Assets
from core.buffer_geometry import NORMAL, POSITION, UV
from core.object3d import NO_PARENT, NodeId
from core.scene import Scene
from loaders.json import JsonDocument, NULL, STRING, parse_json
from loaders.usd import (
    UsdModel,
    parse_usd,
    parse_usda,
    read_usd,
    read_usda,
    usda_tree,
)
from loaders.zip import ZIP_STORED, ZipEntry, zip_archive
from materials.material import Material
from render.srgb import LINEAR, SRGB, srgb_to_linear
from render.texture import CLAMP, MIRROR, REPEAT, Wrap
from render.texture_store import NO_TEXTURE, TextureId
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


def _flatten(
    doc: JsonDocument,
    node: Int,
    depth: Int,
    mut out: List[Int],
    mut depths: List[Int],
) raises:
    """Collect a reference object and those under it, depth first.

    Args:
        doc: The reference.
        node: The object.
        depth: How deep it is.
        out: The objects so far.
        depths: Their depths.
    """
    out.append(node)
    depths.append(depth)
    var children = doc.get(node, "children")
    for k in range(doc.length(children)):
        _flatten(doc, doc.at(children, k), depth + 1, out, depths)


def _near_list(
    got: List[Float32], doc: JsonDocument, node: Int, what: String
) raises:
    """Assert numbers are three.js's, NaN as `"NaN"`.

    Args:
        got: The numbers.
        doc: The reference.
        node: Its list.
        what: The name, for a failure.
    """
    assert_equal(len(got), doc.length(node), what)
    for k in range(len(got)):
        var want = doc.at(node, k)
        if doc.kind(want) == STRING:
            assert_true(isnan(got[k]), what)
        else:
            assert_almost_equal(
                Float64(got[k]), doc.number(want), atol=1e-6, msg=what
            )


def _color(got: UInt8, want: Float64, what: String) raises:
    """Assert an sRGB byte holds a linear channel, to a byte's step.

    Args:
        got: The byte.
        want: The linear channel.
        what: The name, for a failure.
    """
    assert_almost_equal(
        Float64(srgb_to_linear(Float32(got) / 255)), want, atol=0.005, msg=what
    )


def _map(
    assets: Assets, id: TextureId, doc: JsonDocument, node: Int, what: String
) raises:
    """Assert a map is three.js's: there or not, and placed alike.

    Args:
        assets: The assets.
        id: The map.
        doc: The reference.
        node: Its entry.
        what: The name, for a failure.
    """
    if doc.kind(node) == NULL:
        assert_true(id == NO_TEXTURE, what)
        return
    assert_true(id != NO_TEXTURE, what)
    ref texture = assets.textures.get(id)
    var wraps: List[Wrap] = [REPEAT, CLAMP, MIRROR]
    assert_true(
        texture.wrap_s == wraps[doc.integer(doc.get(node, "wrapS")) - 1000],
        what,
    )
    assert_true(
        texture.wrap_t == wraps[doc.integer(doc.get(node, "wrapT")) - 1000],
        what,
    )
    var srgb = doc.string(doc.get(node, "colorSpace")) == "srgb"
    assert_true(texture.color_space == (SRGB if srgb else LINEAR), what)
    assert_almost_equal(
        Float64(texture.rotation.value),
        doc.number(doc.get(node, "rotation")),
        atol=1e-6,
    )
    var repeat = doc.get(node, "repeat")
    assert_almost_equal(
        Float64(texture.repeat.x), doc.number(doc.at(repeat, 0))
    )
    assert_almost_equal(
        Float64(texture.repeat.y), doc.number(doc.at(repeat, 1))
    )
    var offset = doc.get(node, "offset")
    assert_almost_equal(
        Float64(texture.offset.x), doc.number(doc.at(offset, 0))
    )
    assert_almost_equal(
        Float64(texture.offset.y), doc.number(doc.at(offset, 1))
    )


def _same(
    model: UsdModel, mut scene: Scene, assets: Assets, name: String
) raises:
    """Assert a model is what three.js made of a fixture.

    Args:
        model: The model.
        scene: The scene it went into.
        assets: The assets it went into.
        name: The fixture.
    """
    var doc = parse_json(Path("assets/usd/usd.json").read_text())
    var want = List[Int]()
    var depths = List[Int]()
    _flatten(doc, doc.get(doc.root(), name), 0, want, depths)
    # The first is three.js's group, the root.
    assert_equal(len(model.objects), len(want) - 1, name)
    var parents: List[NodeId] = [model.root]
    for k in range(len(model.objects)):
        ref object = model.objects[k]
        var entry = want[k + 1]
        var depth = depths[k + 1]
        while len(parents) > depth:
            _ = parents.pop()
        ref node = scene.node(object.node)
        assert_equal(node.name, doc.string(doc.get(entry, "name")), name)
        assert_true(node.parent == parents[len(parents) - 1], name)
        parents.append(object.node)
        assert_equal(
            object.is_mesh, doc.string(doc.get(entry, "type")) == "Mesh"
        )
        var position = doc.get(entry, "position")
        var quaternion = doc.get(entry, "quaternion")
        var scale = doc.get(entry, "scale")
        _near_list(
            [node.position.x, node.position.y, node.position.z],
            doc,
            position,
            "p",
        )
        _near_list(
            [
                node.quaternion.x,
                node.quaternion.y,
                node.quaternion.z,
                node.quaternion.w,
            ],
            doc,
            quaternion,
            "q",
        )
        _near_list([node.scale.x, node.scale.y, node.scale.z], doc, scale, "s")
        if not object.is_mesh:
            continue
        ref geometry = assets.geometries.get(object.geometry)
        var attributes = doc.get(entry, "attributes")
        assert_equal(
            doc.length(attributes),
            3 if geometry.has_attribute(String(UV)) else 2,
        )
        for key in [POSITION, NORMAL, UV]:
            if doc.has(attributes, String(key)):
                _near_list(
                    geometry.attribute_view(String(key)).packed(),
                    doc,
                    doc.get(attributes, String(key)),
                    name + " " + String(key),
                )
        var material = assets.materials.get(object.material)
        var m = doc.get(entry, "material")
        var color = doc.get(m, "color")
        var emissive = doc.get(m, "emissive")
        _color(material.color.r, doc.number(doc.at(color, 0)), "red")
        _color(material.color.g, doc.number(doc.at(color, 1)), "green")
        _color(material.color.b, doc.number(doc.at(color, 2)), "blue")
        _color(material.emissive.r, doc.number(doc.at(emissive, 0)), "emissive")
        _color(material.emissive.b, doc.number(doc.at(emissive, 2)), "emissive")
        assert_almost_equal(
            Float64(material.roughness),
            doc.number(doc.get(m, "roughness")),
            atol=1e-6,
        )
        assert_almost_equal(
            Float64(material.metalness),
            doc.number(doc.get(m, "metalness")),
            atol=1e-6,
        )
        assert_almost_equal(
            Float64(material.clearcoat),
            doc.number(doc.get(m, "clearcoat")),
            atol=1e-6,
        )
        assert_almost_equal(
            Float64(material.clearcoat_roughness),
            doc.number(doc.get(m, "clearcoatRoughness")),
            atol=1e-6,
        )
        assert_almost_equal(
            Float64(material.ior), doc.number(doc.get(m, "ior")), atol=1e-6
        )
        _map(assets, material.map, doc, doc.get(m, "map"), "map")
        _map(
            assets,
            material.emissive_map,
            doc,
            doc.get(m, "emissiveMap"),
            "emissive",
        )
        _map(
            assets, material.normal_map, doc, doc.get(m, "normalMap"), "normal"
        )
        _map(
            assets,
            material.roughness_map,
            doc,
            doc.get(m, "roughnessMap"),
            "rough",
        )
        _map(
            assets,
            material.metalness_map,
            doc,
            doc.get(m, "metalnessMap"),
            "metal",
        )
        _map(
            assets,
            material.clearcoat_map,
            doc,
            doc.get(m, "clearcoatMap"),
            "coat",
        )
        _map(
            assets,
            material.clearcoat_roughness_map,
            doc,
            doc.get(m, "clearcoatRoughnessMap"),
            "coat roughness",
        )
        _map(assets, material.ao_map, doc, doc.get(m, "aoMap"), "ao")


def test_usda_text_is_read_as_three_js_reads_it() raises:
    var scene = Scene()
    var assets = Assets()
    var model = read_usda("assets/usd/cube.usda", scene, assets)
    _same(model, scene, assets, "cube.usda")
    assert_equal(len(model.textures), 0)


def test_a_usdz_is_read_as_three_js_reads_it() raises:
    var scene = Scene()
    var assets = Assets()
    var model = read_usd("assets/usd/scene.usdz", scene, assets)
    _same(model, scene, assets, "scene.usdz")
    # The brick is in the archive; the bump map's file is not.
    assert_equal(len(model.missing_textures), 1)
    assert_equal(model.missing_textures[0], "textures/missing.png")
    ref brick = assets.textures.get(model.textures[0])
    assert_true(brick.width > 1)


def _usda(text: String) raises -> Tuple[UsdModel, Scene, Assets]:
    """Read USDA text into a new scene.

    Args:
        text: The text.

    Returns:
        The model, the scene and the assets.
    """
    var scene = Scene()
    var assets = Assets()
    var model = parse_usda(text, scene, assets)
    return (model^, scene^, assets^)


def test_the_text_is_read_into_a_tree_as_three_js_reads_it() raises:
    var tree = usda_tree(
        "a = b = c\nlist = x (\n  meta = 1\n)\nk = v\nk = w\n(\nk\n{\n"
        + "  inner = 2\n}\nk\n{\n}\n}\n}\nq = 1\n"
    )
    # `split( '=' )[ 1 ]`: a second `=` ends the value.
    assert_equal(tree.text(0, "a").value(), "b")
    # A value that ends with `(` loses it and opens metadata, which is
    # not kept.
    assert_equal(tree.text(0, "list").value(), "x ")
    assert_false(tree.has(0, "meta"))
    # A key keeps its first place when it is set again.
    assert_equal(tree.nodes[0].keys[2], "k")
    # A lone `(` with no name before it opens the key `null`. Inside it,
    # `{` opens the group of the name before, which a second `{` reopens.
    var meta = tree.kid(0, "null")
    var group = tree.kid(meta, "k")
    assert_true(group >= 0)
    assert_equal(tree.text(0, "k").value(), "w")
    assert_equal(tree.text(group, "inner").value(), "2")
    # Past the root, `}` changes nothing, and writing goes on.
    assert_equal(tree.text(0, "q").value(), "1")
    # A `{` with nothing named opens the key `null`.
    assert_true(usda_tree("{\n}\n").kid(0, "null") >= 0)
    # An empty string is no group: `{` opens a new one.
    var empty = usda_tree("k =\nk\n{\n  x = 1\n}\n")
    assert_true(empty.kid(0, "k") >= 0)
    with assert_raises(contains="writes into a string"):
        _ = usda_tree("k = v\nk\n{\n  x = 1\n}\n")
    with assert_raises(contains="writes into a string or into nothing"):
        _ = usda_tree(")\nx = 1\n")
    with assert_raises(contains="into nothing"):
        _ = usda_tree(")\na (\n")
    # An order of keys as JavaScript walks them: indices first.
    var order = usda_tree("b = 1\n2 = 2\n1 = 3\n").order(0)
    assert_equal(order[0], 2)
    assert_equal(order[1], 1)


def test_references_are_found_as_three_js_finds_them() raises:
    var brick = Path("assets/brick.png").read_bytes()
    var stage = (
        '#usda 1.0\ndef Xform "A" (\n    prepend references ='
        + ' @x/geo.usda@</Shape>\n)\n{\n}\ndef Xform "B" (\n'
        + "    prepend references = @crate.usdc@</Shape>\n)\n{\n}\n"
        + 'def Xform "C" (\n    prepend references = @gone.usda@</S>\n)\n'
        + "{\n}\n"
    )
    var geo = (
        'def Mesh "Shape"\n{\n    point3f[] points = [(0, 0, 0), (1, 0, 0),'
        + " (0, 1, 0)]\n}\n"
    )
    var crate = List[UInt8](String("PXR-USDC and more").as_bytes())
    var archive = zip_archive(
        [
            ZipEntry("stage.usda", ZIP_STORED, List[UInt8](stage.as_bytes())),
            ZipEntry("geo.usda", ZIP_STORED, List[UInt8](geo.as_bytes())),
            ZipEntry("crate.usdc", ZIP_STORED, crate^),
            ZipEntry("a.png", ZIP_STORED, brick^),
        ]
    )
    var scene = Scene()
    var assets = Assets()
    var model = parse_usd(archive, scene, assets)
    # `x/geo.usda` loses `x/`, as `/^.\//` cuts it. A crate's group and a
    # missing layer hold no mesh.
    assert_true(model.objects[0].is_mesh)
    assert_false(model.objects[1].is_mesh)
    assert_false(model.objects[2].is_mesh)
    # A reference into a PNG looks for a name in a string.
    var into_png = (
        'def Xform "A" (\n    prepend references = @a.png@</S>\n)\n{\n}\n'
    )
    var png_archive = zip_archive(
        [
            ZipEntry("s.usd", ZIP_STORED, List[UInt8](into_png.as_bytes())),
            ZipEntry("a.png", ZIP_STORED, [1, 2, 3]),
        ]
    )
    with assert_raises(contains="`in` reads a key"):
        _ = parse_usd(png_archive, scene, assets)
    with assert_raises(contains="no @path@ and name"):
        _ = _usda('def Xform "A" (\n    prepend references = @a\n)\n{\n}\n')
    with assert_raises(contains="is a group, not a string"):
        _ = _usda('def Xform "A"\n{\n    prepend references = {\n    }\n}\n')


def test_meshes_are_built_as_three_js_builds_them() raises:
    # Counts of five are stepped over; no indices and no counts of three
    # or four is no corner at all.
    var skipped = _usda(
        'def Xform "A"\n{\n    def Mesh "M"\n    {\n'
        + "        int[] faceVertexCounts = [5]\n"
        + "        point3f[] points = [(0, 0, 0), (1, 0, 0), (0, 1, 0)]\n"
        + "    }\n}\n"
    )
    ref geometry = skipped[2].geometries.get(skipped[0].objects[0].geometry)
    assert_equal(len(geometry.attribute_view(String(POSITION)).packed()), 0)
    # A corner past the list reads NaN.
    var past = _usda(
        'def Xform "A"\n{\n    def Mesh "M"\n    {\n'
        + "        int[] faceVertexCounts = [3]\n"
        + "        int[] faceVertexIndices = [0, 1]\n"
        + "        point3f[] points = [(0, 0, 0), (1, 0, 0), (0, 1, 0)]\n"
        + "    }\n}\n"
    )
    var corners = (
        past[2]
        .geometries.get(past[0].objects[0].geometry)
        .attribute_view(String(POSITION))
        .packed()
    )
    assert_true(isnan(corners[6]))
    # Numbers as JavaScript's `Number` reads JSON values.
    var numbers = _usda(
        'def Xform "A"\n{\n    def Mesh "M"\n    {\n'
        + '        point3f[] points = ["2", true, null, [], [5], [1, 2], {"a":'
        " 1}, false, 1]\n"
        + "    }\n}\n"
    )
    var read = (
        numbers[2]
        .geometries.get(numbers[0].objects[0].geometry)
        .attribute_view(String(POSITION))
        .packed()
    )
    assert_equal(read[0], 2)
    assert_equal(read[1], 1)
    assert_equal(read[2], 0)
    assert_equal(read[3], 0)
    assert_equal(read[4], 5)
    assert_true(isnan(read[5]))
    assert_true(isnan(read[6]))
    assert_equal(read[7], 0)
    var mesh = 'def Xform "A"\n{\n    def Mesh "M"\n    {\n'
    with assert_raises(contains="with no faceVertexIndices"):
        _ = _usda(mesh + "        int[] faceVertexCounts = [3]\n    }\n}\n")
    with assert_raises(contains="not an array"):
        _ = _usda(mesh + "        int[] faceVertexIndices = 5\n    }\n}\n")
    with assert_raises(contains="not whole vertices"):
        _ = _usda(mesh + "        point3f[] points = [1, 2]\n    }\n}\n")
    with assert_raises(contains="st indices with no faceVertexCounts"):
        _ = _usda(
            mesh
            + "        texCoord2f[] primvars:st = [(0, 0)]\n"
            + "        int[] primvars:st:indices = [0]\n    }\n}\n"
        )
    with assert_raises(contains="normals that are not three numbers"):
        _ = _usda(mesh + "        normal3f[] normals = [1, 2]\n    }\n}\n")
    with assert_raises(contains="normals with no faceVertexCounts"):
        _ = _usda(mesh + "        normal3f[] normals = [1, 2, 3]\n    }\n}\n")
    with assert_raises(contains="a group, not a string"):
        _ = _usda(mesh + "        point3f[] points = {\n        }\n    }\n}\n")
    # A mesh that is text: empty is none, anything else is read with `in`.
    var blank = _usda('def Xform "A"\n{\n    def Mesh "M" =\n}\n')
    assert_false(blank[0].objects[0].is_mesh)
    with assert_raises(contains="`in` reads a key"):
        _ = _usda('def Xform "A"\n{\n    def Mesh "M" = x\n}\n')
    with assert_raises(contains="`in` reads a key"):
        _ = _usda('def Xform "A" =\n')


def _material(
    surface: String, extra: String = ""
) raises -> Tuple[UsdModel, Scene, Assets]:
    """Read a triangle bound to a material of one surface shader.

    Args:
        surface: The surface shader's inputs.
        extra: More of the material, after the surface.

    Returns:
        The model, the scene and the assets.
    """
    return _usda(
        'def Xform "A"\n{\n    rel material:binding = </Looks/M>\n'
        + '    def Mesh "Face"\n    {\n'
        + "        int[] faceVertexCounts = [3]\n"
        + "        int[] faceVertexIndices = [0, 1, 2]\n"
        + "        point3f[] points = [(0, 0, 0), (1, 0, 0), (0, 1, 0)]\n"
        + "    }\n}\n"
        + 'def Scope "Looks"\n{\n    def Material "M"\n    {\n'
        + "        token outputs:surface.connect ="
        " </Looks/M/S.outputs:surface>\n"
        + '        def Shader "S"\n        {\n'
        + surface
        + "        }\n"
        + extra
        + "    }\n}\n"
    )


def test_materials_are_built_as_three_js_builds_them() raises:
    var shader = (
        '        def Shader "T"\n        {\n'
        + "            asset inputs:file = @t.png@\n"
        + '            token inputs:wrapS = "mirror"\n        }\n'
    )
    var textured = _material(
        "            color3f inputs:emissiveColor.connect ="
        " </Looks/M/T.outputs:rgb>\n"
        + "            float inputs:metallic.connect = </Looks/M/T.outputs:r>\n"
        + "            float inputs:clearcoat.connect ="
        " </Looks/M/T.outputs:r>\n"
        + "            float inputs:clearcoatRoughness.connect ="
        " </Looks/M/T.outputs:r>\n",
        shader
        + '        def Shader "Transform2d_emissive" = x\n'
        + '        def Shader "Transform2d_metallic"\n        {\n'
        + "            float inputs:rotation =\n"
        + "        }\n",
    )
    var built = textured[2].materials.get(textured[0].objects[0].material)
    assert_true(built.emissive_map != NO_TEXTURE)
    assert_equal(built.emissive.r, 255)
    assert_equal(built.metalness, 1)
    assert_equal(built.clearcoat, 1)
    assert_equal(built.clearcoat_roughness, 1)
    assert_true(built.clearcoat_roughness_map != NO_TEXTURE)
    ref first = textured[2].textures.get(built.emissive_map)
    assert_true(first.wrap_s == MIRROR)
    assert_true(first.wrap_t == CLAMP)
    assert_equal(len(textured[0].missing_textures), 4)
    # A binding of one part looks for `def Material "undefined"`.
    var lone = _usda(
        'def Xform "A"\n{\n    rel material:binding = </M>\n}\n'
        + 'def Material "undefined"\n{\n    token outputs:surface.connect ='
        + " </undefined/S.outputs:surface>\n"
        + '    def Shader "S"\n    {\n        float inputs:roughness = 0.5\n   '
        " }\n}\n"
    )
    _ = lone^
    # A surface that is not a group, or not there, or a connection that is
    # a group or names no shader, is the default material.
    for text in [
        "token outputs:surface.connect = x\n",
        "token outputs:surface.connect = </a/Missing.outputs:surface>\n",
        "token outputs:surface.connect = {\n        }\n",
    ]:
        var plain = _usda(
            'def Xform "A"\n{\n    def Material "M"\n    {\n        '
            + text
            + "    }\n}\n"
        )
        _ = plain^
    with assert_raises(contains="`in` reads a key"):
        _ = _usda(
            'def Xform "A"\n{\n    def Material "M"\n    {\n'
            + "        token outputs:surface.connect = </S.outputs:surface>\n"
            + '        def Shader "S" = text\n    }\n}\n'
        )
    with assert_raises(contains="names no shader"):
        _ = _material(
            "            color3f inputs:diffuseColor.connect = </x>\n"
        )
    with assert_raises(contains="`in` reads a key"):
        _ = _material(
            "            normal3f inputs:normal.connect ="
            " </a/Gone.outputs:rgb>\n"
        )
    with assert_raises(contains="has no file"):
        _ = _material(
            "            float inputs:occlusion.connect = </a/T.outputs:r>\n",
            '        def Shader "T"\n        {\n        }\n',
        )
    with assert_raises(contains="wrap three.js does not know"):
        _ = _material(
            "            float inputs:roughness.connect = </a/T.outputs:r>\n",
            '        def Shader "T"\n        {\n'
            + "            asset inputs:file = @t.png@\n"
            + '            token inputs:wrapT = "border"\n        }\n',
        )
    with assert_raises(contains="from zero to one"):
        _ = _material("            color3f inputs:diffuseColor = (2, 0, 0)\n")
    with assert_raises(contains="from zero to one"):
        _ = _material("            color3f inputs:emissiveColor = (0, 0)\n")


def test_nodes_are_placed_and_named_as_three_js_does() raises:
    var placed = _usda(
        'def Xform "a-b" def Xform "Ok"\n{\n'
        + "    matrix4d xformOp:transform = ( (1, 0, 0, 0), (0, 1, 0, 0),"
        + " (0, 0, 1, 0), (4, 5, 6, 1) )\n}\n"
        + 'def Xform "x-y"\n{\n}\n'
    )
    var first = placed[0].objects[0].node
    var second = placed[0].objects[1].node
    assert_equal(placed[1].node(first).name, "Ok")
    assert_equal(placed[1].node(first).position.y, 5)
    assert_equal(placed[1].node(second).name, "")
    with assert_raises(contains="fewer than sixteen"):
        _ = _usda(
            'def Xform "A"\n{\n    matrix4d xformOp:transform = ( (1, 0) )\n}\n'
        )


def test_what_three_js_throws_on_in_an_archive_is_refused() raises:
    var scene = Scene()
    var assets = Assets()
    # A crate is an empty group.
    var crate = parse_usd(
        List[UInt8](String("PXR-USDC").as_bytes()), scene, assets
    )
    assert_equal(len(crate.objects), 0)
    with assert_raises(contains="archive is empty"):
        _ = parse_usd(zip_archive([]), scene, assets)
    with assert_raises(contains="first file is not a USD layer"):
        _ = parse_usd(
            zip_archive([ZipEntry("a.png", ZIP_STORED, [1])]), scene, assets
        )
    with assert_raises(contains="is not UTF-8 text"):
        _ = parse_usd(
            zip_archive([ZipEntry("a.usda", ZIP_STORED, [0xFF])]), scene, assets
        )
    # A byte order mark is dropped.
    var marked = parse_usd(
        zip_archive(
            [
                ZipEntry(
                    "a.usda",
                    ZIP_STORED,
                    [0xEF, 0xBB, 0xBF, 100, 101, 102, 10],
                )
            ]
        ),
        scene,
        assets,
    )
    assert_equal(len(marked.objects), 0)
    # `load` reads bytes, so a `.usda` file is not a ZIP.
    with assert_raises():
        _ = read_usd("assets/usd/cube.usda", scene, assets)
    # A file of a name twice keeps the last, and a file that is neither a
    # PNG nor a layer is stepped over.
    var twice = parse_usd(
        zip_archive(
            [
                ZipEntry("a.usda", ZIP_STORED, [120, 10]),
                ZipEntry("readme.txt", ZIP_STORED, [1]),
                ZipEntry("a.usda", ZIP_STORED, [121, 10]),
            ]
        ),
        scene,
        assets,
    )
    assert_equal(len(twice.objects), 0)


def test_the_tree_s_edges_are_read_as_three_js_reads_them() raises:
    var tree = usda_tree("a = 1\ng = {\n}\n}\n}\n)\n")
    assert_false(Bool(tree.text(0, "missing")))
    assert_false(Bool(tree.text(0, "g")))
    assert_equal(tree.kid(0, "missing"), -1)
    assert_equal(tree.kid(0, "a"), -1)


def _mesh(body: String) raises -> Tuple[UsdModel, Scene, Assets]:
    """Read an Xform holding one mesh of the given lines.

    Args:
        body: The mesh's lines.

    Returns:
        The model, the scene and the assets.
    """
    return _usda(
        'def Xform "A"\n{\n    def Mesh "M"\n    {\n' + body + "    }\n}\n"
    )


def test_mesh_edges_are_read_as_three_js_reads_them() raises:
    var three = "        point3f[] points = [(0, 0, 0), (1, 0, 0), (0, 1, 0)]\n"
    # A face of five is stepped over; a fractional corner reads NaN.
    var mixed = _mesh(
        three
        + "        int[] faceVertexCounts = [3, 5]\n"
        + "        int[] faceVertexIndices = [0.5, 1, 2, 0, 1, 2, 0, 1]\n"
    )
    var corners = (
        mixed[2]
        .geometries.get(mixed[0].objects[0].geometry)
        .attribute_view(String(POSITION))
        .packed()
    )
    assert_equal(len(corners), 9)
    # Empty arrays: no corners and no counts.
    var empty = _mesh(
        three
        + "        int[] faceVertexCounts = []\n"
        + "        int[] faceVertexIndices = []\n"
    )
    var none = (
        empty[2]
        .geometries.get(empty[0].objects[0].geometry)
        .attribute_view(String(POSITION))
        .packed()
    )
    assert_equal(len(none), 0)
    var no_indices = _mesh(three + "        int[] faceVertexCounts = []\n")
    _ = no_indices^
    # Normals of none, which are not as long as the points: none of their
    # own corners.
    var no_normals = _mesh(
        three
        + "        int[] faceVertexCounts = [3]\n"
        + "        int[] faceVertexIndices = [0, 1, 2]\n"
        + "        normal3f[] normals = []\n"
    )
    _ = no_normals^
    # A reference with no archive, and a binding of nothing.
    var unreferenced = _usda(
        'def Xform "A" (\n    prepend references = @a.usda@</M>\n)\n{\n'
        + "    rel material:binding = </\n}\n"
    )
    assert_false(unreferenced[0].objects[0].is_mesh)
    with assert_raises(contains="with no faceVertexIndices"):
        _ = _mesh(three + "        int[] faceVertexCounts = [4]\n")
    # `st` indices with no `st` are stepped over.
    var lone = _mesh(three + "        int[] primvars:st:indices = [0]\n")
    _ = lone^
    # Normals as long as the points and no corners are kept as they are.
    var kept = _mesh(
        three
        + "        normal3f[] normals = [(0, 0, 1), (0, 0, 1), (0, 0, 1)]\n"
    )
    var normals = (
        kept[2]
        .geometries.get(kept[0].objects[0].geometry)
        .attribute_view(String(NORMAL))
        .packed()
    )
    assert_equal(len(normals), 9)
    # Normals of their own, one a corner, read through their own corners.
    var own = _mesh(
        three
        + "        int[] faceVertexCounts = [3]\n"
        + "        int[] faceVertexIndices = [0, 1, 2]\n"
        + "        normal3f[] normals = [(0, 0, 1)]\n"
    )
    var own_normals = (
        own[2]
        .geometries.get(own[0].objects[0].geometry)
        .attribute_view(String(NORMAL))
        .packed()
    )
    assert_equal(own_normals[2], 1)
    assert_true(isnan(own_normals[3]))
    # No points: no normals are computed.
    var pointless = _mesh("        int[] faceVertexIndices = [0]\n")
    ref bare = pointless[2].geometries.get(pointless[0].objects[0].geometry)
    assert_false(bare.has_attribute(String(NORMAL)))
    with assert_raises(contains="is a group, not a string"):
        _ = _mesh(three + "        float2[] primvars:st = {\n        }\n")


def test_material_edges_are_read_as_three_js_reads_them() raises:
    # An empty group before the shader is searched and passed; a binding
    # with no `>` still names its material; a material with no surface
    # is the default.
    var looked = _usda(
        'def Scope "Empty"\n{\n}\n'
        + 'def Xform "A"\n{\n    rel material:binding = </Looks/M\n'
        + '    def Mesh "Face"\n    {\n'
        + "        point3f[] points = [(0, 0, 0), (1, 0, 0), (0, 1, 0)]\n"
        + "    }\n}\n"
        + 'def Xform "B"\n{\n    rel material:binding = </Looks/N>\n'
        + '    def Mesh "Face"\n    {\n'
        + "        point3f[] points = [(0, 0, 0), (1, 0, 0), (0, 1, 0)]\n"
        + "    }\n}\n"
        + 'def Scope "Plain" = x\n'
        + 'def Scope "Looks"\n{\n    def Material "N"\n    {\n    }\n'
        + '    def Material "M"\n    {\n'
        + "        token outputs:surface.connect ="
        " </Looks/M/S.outputs:surface>\n"
        + '        def Shader "S"\n        {\n'
        + "            color3f inputs:diffuseColor.connect ="
        " </Looks/M/T.outputs:rgb>\n"
        + "        }\n"
        + '        def Shader "T"\n        {\n'
        + "            asset inputs:file = @t.png@\n"
        + '            token inputs:wrapS = "clamp"\n'
        + '            token inputs:wrapT = "repeat"\n'
        + "        }\n    }\n}\n"
    )
    var map = looked[2].materials.get(looked[0].objects[0].material).map
    assert_true(map != NO_TEXTURE)
    assert_true(looked[2].textures.get(map).wrap_t == REPEAT)
    with assert_raises(contains="wrap three.js does not know"):
        _ = _material(
            "            float inputs:roughness.connect = </a/T.outputs:r>\n",
            '        def Shader "T"\n        {\n'
            + "            asset inputs:file = @t.png@\n"
            + "            token inputs:wrapS = {\n            }\n"
            + "        }\n",
        )
    # A texture whose file is a layer of the archive has no image.
    var stage = (
        'def Xform "A"\n{\n    rel material:binding = </Looks/M>\n'
        + '    def Mesh "Face"\n    {\n'
        + "        point3f[] points = [(0, 0, 0), (1, 0, 0), (0, 1, 0)]\n"
        + "    }\n}\n"
        + 'def Scope "Looks"\n{\n    def Material "M"\n    {\n'
        + "        token outputs:surface.connect ="
        " </Looks/M/S.outputs:surface>\n"
        + '        def Shader "S"\n        {\n'
        + "            color3f inputs:diffuseColor.connect ="
        " </Looks/M/T.outputs:rgb>\n"
        + "        }\n"
        + '        def Shader "T"\n        {\n'
        + "            asset inputs:file = @other.usda@\n        }\n    }\n}\n"
    )
    var scene = Scene()
    var assets = Assets()
    var layered = parse_usd(
        zip_archive(
            [
                ZipEntry(
                    "stage.usda", ZIP_STORED, List[UInt8](stage.as_bytes())
                ),
                ZipEntry("other.usda", ZIP_STORED, [120, 10]),
            ]
        ),
        scene,
        assets,
    )
    assert_equal(layered.missing_textures[0], "other.usda")


def test_names_are_read_as_three_js_reads_them() raises:
    var named = _usda(
        'def Xform "" def Xform "Ok"\n{\n}\ndef Xform "open\n{\n}\n'
    )
    var first = named[0].objects[0].node
    var second = named[0].objects[1].node
    assert_equal(named[1].node(first).name, "Ok")
    assert_equal(named[1].node(second).name, "")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
