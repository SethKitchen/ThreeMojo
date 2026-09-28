# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.usd_composer`: layers composed as three.js r186's
`USDComposer` composes them, one rule and one quirk at a time.
`tests/test_usd.mojo` compares whole files with three.js."""

from core.assets import Assets
from core.object3d import GROUP_TYPE, Object3D
from core.scene import Scene
from loaders.usd_composer import (
    MAX_REFERENCE_DEPTH,
    USD_IMAGE,
    USD_LAYER,
    UsdAssetKind,
    UsdAssets,
    UsdModel,
    compose_usd,
    moved,
    reference_matches,
    resolve_url,
    variant_path_match,
)
from loaders.usd_specs import (
    SPEC_ATTRIBUTE,
    SPEC_PRIM,
    SPEC_RELATIONSHIP,
    SPEC_VARIANT,
    USD_ARRAY,
    USD_NULL,
    USD_OBJECT,
    USD_SAMPLES,
    UsdLayer,
    UsdSpec,
    UsdValue,
    usd_number,
    usd_numbers,
    usd_string,
    usd_strings,
)
from loaders.usda_parser import parse_usda_layer
from materials.material import Material
from math.quaternion import Quaternion
from render.framebuffer import Color
from render.srgb import LINEAR, SRGB
from render.texture import CLAMP, MIRROR, REPEAT
from render.texture_store import NO_TEXTURE
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


struct _Out(Movable):
    """A composed layer: its scene, its store and what was added."""

    var scene: Scene
    var store: Assets
    var model: UsdModel

    def __init__(out self, var scene: Scene, var store: Assets, var model: UsdModel):
        self.scene = scene^
        self.store = store^
        self.model = model^

    def find(self, name: String) raises -> Int:
        """Return the place of the first object of a name."""
        for k in range(len(self.model.objects)):
            if self.scene.get(self.model.objects[k].node).name == name:
                return k
        raise Error("no object " + name)

    def node(self, name: String) raises -> Object3D:
        """Return the first node of a name."""
        return self.scene.get(self.model.objects[self.find(name)].node)

    def count(self, name: String) raises -> Int:
        """Return how many objects have a name."""
        var n = 0
        for k in range(len(self.model.objects)):
            if self.scene.get(self.model.objects[k].node).name == name:
                n += 1
        return n

    def material(self, name: String, at: Int = 0) raises -> Material:
        """Return a mesh's material."""
        return self.store.materials.get(self.model.objects[self.find(name)].materials[at])


def _compose(
    var layer: UsdLayer, assets: UsdAssets = UsdAssets(), base: String = ""
) raises -> _Out:
    """Compose a layer."""
    var scene = Scene()
    var store = Assets()
    var model = compose_usd(layer^, assets, base, scene, store)
    return _Out(scene^, store^, model^)


def _text(text: String, assets: UsdAssets = UsdAssets(), base: String = "") raises -> _Out:
    """Compose USDA text."""
    return _compose(parse_usda_layer("#usda 1.0\n" + text), assets, base)


def _layer_asset(mut assets: UsdAssets, name: String, text: String) raises:
    """Add a layer of USDA text to an archive."""
    assets.add(name, USD_LAYER, List[UInt8](), parse_usda_layer("#usda 1.0\n" + text))


def _image_asset(mut assets: UsdAssets, name: String) raises:
    """Add the brick PNG to an archive."""
    assets.add(name, USD_IMAGE, Path("assets/brick.png").read_bytes(), UsdLayer())


def _near(got: Float32, want: Float64, what: String = "") raises:
    """Assert a number is near another."""
    assert_almost_equal(Float64(got), want, atol=1e-5, msg=what)


def test_assets() raises:
    var assets = UsdAssets()
    with assert_raises(contains="no kind"):
        assets.add("x", UsdAssetKind(5), List[UInt8](), UsdLayer())
    _image_asset(assets, "b")
    _image_asset(assets, "7")
    assets.add("b", USD_LAYER, List[UInt8](), UsdLayer())
    assert_equal(len(assets.names), 2)
    assert_true(assets.kinds[0] == USD_LAYER)
    assert_equal(assets.find("c"), -1)
    var order = assets.order()
    assert_equal(assets.names[order[0]], "7")
    assert_false(UsdAssetKind(2).is_valid())


def test_resolve_url() raises:
    assert_equal(resolve_url("", "a/"), "")
    assert_equal(resolve_url("x.png", "a/"), "a/x.png")
    assert_equal(resolve_url("/x.png", "http://host/a/"), "http://host/x.png")
    assert_equal(resolve_url("/x.png", "HTTPS://host"), "HTTPS://host/x.png")
    assert_equal(resolve_url("x.png", "http://host/a/"), "http://host/a/x.png")
    assert_equal(resolve_url("/x.png", "a/"), "a//x.png")
    assert_equal(resolve_url("//cdn/x.png", "a/"), "//cdn/x.png")
    assert_equal(resolve_url("HTTP://x", "a/"), "HTTP://x")
    assert_equal(resolve_url("https://x", "a/"), "https://x")
    assert_equal(resolve_url("data:a,b", "a/"), "data:a,b")
    assert_equal(resolve_url("data:ab", "a/"), "a/data:ab")
    assert_equal(resolve_url("blob:x", "a/"), "blob:x")


def test_reference_matches() raises:
    assert_equal(len(reference_matches("")), 0)
    assert_equal(len(reference_matches("x @")), 0)
    assert_equal(len(reference_matches("@@")), 0)
    var found = reference_matches("@a.usda@</B>")
    assert_equal(found[0][0], "@a.usda@</B>")
    assert_equal(found[0][1], "a.usda")
    assert_equal(found[0][2], "/B")
    found = reference_matches("[@a@<>, @b@<c, @@d@]")
    assert_equal(len(found), 3)
    assert_equal(found[0][0], "@a@")
    assert_equal(found[1][2], "")
    assert_equal(found[2][1], "d")
    found = reference_matches("@a@<x")
    assert_equal(found[0][0], "@a@")
    found = reference_matches("@a@<")
    assert_equal(found[0][0], "@a@")


def test_variant_path_match() raises:
    assert_false(Bool(variant_path_match("")))
    assert_false(Bool(variant_path_match("/")))
    var found = variant_path_match("/a/{s=v}/b/c")
    assert_equal(found.value()[0], "/a")
    assert_equal(found.value()[1], "b/c")
    found = variant_path_match("/a/x{/{s=v_2}/b")
    assert_equal(found.value()[0], "/a/x{")
    for path in [
        "/a/{s=v}/",
        "/a/{=v}/b",
        "/a/{s}/b",
        "/a/{s=}/b",
        "/a/{s=v}b",
        "/a/{s-x=v}/b",
        "/a/{s=v}",
        "/a/{s=v}}",
        "/a/{s",
        "/a/{s=v",
        "/{s=v}/b",
        "/a/",
    ]:
        assert_false(Bool(variant_path_match(path)), path)


def test_moved() raises:
    var node = Object3D()
    assert_false(moved(node))
    for axis in range(3):
        var p = Object3D()
        var s = Object3D()
        var values: List[Float32] = [0, 0, 0]
        values[axis] = 2
        p.set_position(values[0], values[1], values[2])
        assert_true(moved(p))
        var scale: List[Float32] = [1, 1, 1]
        scale[axis] = 2
        s.set_scale(scale[0], scale[1], scale[2])
        assert_true(moved(s))
    for q in [
        Quaternion(1, 0, 0, 0),
        Quaternion(0, 1, 0, 0),
        Quaternion(0, 0, 1, 0),
    ]:
        var r = Object3D()
        r.quaternion = q
        assert_true(moved(r))


def test_ordered_transforms() raises:
    var out = _text(
        'def Xform "A"\n{\n    float3 xformOp:scale = (-1, -1, -1)\n'
        + '    uniform token[] xformOpOrder = ["xformOp:scale", "xformOp:unknown", "xformOp:rotateX"]\n}\n'
        + 'def Xform "B"\n{\n    float3 xformOp:scale = (-1, 1, 1)\n'
        + '    uniform token[] xformOpOrder = ["xformOp:scale"]\n}\n'
        + 'def Xform "C"\n{\n    float3 xformOp:scale = (-1, -1, 1)\n'
        + '    uniform token[] xformOpOrder = ["xformOp:scale"]\n}\n'
        + 'def Xform "D"\n{\n    float3 xformOp:translate = (1, 2, 3)\n'
        + '    float xformOp:rotateY = 90\n    float xformOp:rotateZ = 90\n'
        + '    matrix4d xformOp:transform = ((1, 0), (0, 1))\n'
        + '    float3 xformOp:orient = (1, 0, 0)\n'
        + '    uniform token[] xformOpOrder = ["!invert!xformOp:translate", "xformOp:rotateY", '
        + '"xformOp:transform", "xformOp:orient", "xformOp:rotateXYZ", "xformOp:translate:pivot", "xformOp:rotateZ"]\n}\n'
        + 'def Xform "E"\n{\n    float xformOp:scale = 2\n'
        + '    uniform token[] xformOpOrder = ["xformOp:scale"]\n}\n'
    )
    var a = out.node("A")
    _near(a.scale.x, -1)
    _near(a.scale.y, -1)
    _near(a.quaternion.w, 0)
    var b = out.node("B")
    _near(b.scale.x, -1)
    _near(b.scale.y, 1)
    var c = out.node("C")
    _near(c.scale.z, 1)
    var d = out.node("D")
    _near(d.position.x, -1)
    _near(d.position.z, -3)
    _near(out.node("E").scale.y, 2)


def test_unordered_transforms() raises:
    var out = _text(
        'def Xform "A"\n{\n    float3 xformOp:scale = (1, 2, 3)\n'
        + '    float3 xformOp:orient = (1, 0, 0)\n}\n'
        + 'def Xform "B"\n{\n    float3 xformOp:rotateXYZ = (0, 0, 90)\n}\n'
        + 'def Xform "C"\n{\n    uniform token[] xformOpOrder = []\n    float xformOp:scale = 2\n}\n'
        + 'def Xform "D"\n{\n    quatf xformOp:orient = (0.5, 0.5, 0.5, 0.5)\n}\n'
    )
    _near(out.node("A").scale.z, 3)
    _near(out.node("A").quaternion.w, 1)
    _near(out.node("B").quaternion.z, 0.7071068)
    # USDA's `[]` is one empty name, an operation three.js does not know.
    _near(out.node("C").scale.y, 1)
    _near(out.node("D").quaternion.x, 0.5)


def test_transform_refusals() raises:
    with assert_raises(contains="not three numbers"):
        _ = _text('def Xform "A"\n{\n    double xformOp:translate = 1\n}\n')
    with assert_raises(contains="not three numbers"):
        _ = _text(
            'def Xform "A"\n{\n    double2 xformOp:translate = (1, 2)\n'
            + '    uniform token[] xformOpOrder = ["xformOp:translate"]\n}\n'
        )
    with assert_raises(contains="not three numbers"):
        _ = _text('def Xform "A"\n{\n    float xformOp:rotateXYZ = 5\n}\n')
    with assert_raises(contains="not three numbers"):
        _ = _text(
            'def Xform "A"\n{\n    float xformOp:rotateXYZ = 5\n'
            + '    uniform token[] xformOpOrder = ["xformOp:rotateXYZ"]\n}\n'
        )
    var layer = parse_usda_layer('#usda 1.0\ndef Xform "A"\n{\n}\n')
    var order = layer.add(usd_numbers([1]))
    layer.specs[layer.spec("/A")].set("xformOpOrder", order)
    with assert_raises(contains="not a list of names"):
        _ = _compose(layer^)
    var empty = parse_usda_layer('#usda 1.0\ndef Xform "A"\n{\n    float xformOp:scale = 2\n}\n')
    var none = empty.add(usd_strings(List[String]()))
    empty.specs[empty.spec("/A")].set("xformOpOrder", none)
    _near(_compose(empty^).node("A").scale.x, 2)


def test_units_and_axis() raises:
    var out = _text("(\n    metersPerUnit = 1\n    upAxis = \"Y\"\n)\n")
    _near(out.scene.get(out.model.root).scale.x, 1)
    _near(out.scene.get(out.model.root).quaternion.w, 1)
    var layer = parse_usda_layer("#usda 1.0\n")
    var text = layer.add(usd_string("2"))
    layer.specs[0].set("metersPerUnit", text)
    with assert_raises(contains="metersPerUnit"):
        _ = _compose(layer^)
    assert_equal(len(_text("").model.objects), 1)


def test_prim_types() raises:
    var out = _text(
        'def SkelRoot "R"\n{\n    def Skeleton "S"\n    {\n        def Xform "Under"\n        {\n        }\n'
        + '        def SkelAnimation "Anim"\n        {\n        }\n    }\n}\n'
        + 'def Material "M"\n{\n    def Shader "Sh"\n    {\n    }\n}\n'
        + 'def Mesh "Me"\n{\n    def GeomSubset "G"\n    {\n    }\n}\n'
        + 'def Camera "Cam"\n{\n}\n'
        + 'def Cube "Box"\n{\n    token axis = "Y"\n}\n'
        + 'def Sphere "Ball"\n{\n    token axis = "X"\n    double radius = 2\n}\n'
        + 'def Cylinder "Can"\n{\n}\ndef Cone "Tip"\n{\n}\ndef Capsule "Pill"\n{\n}\n'
    )
    assert_true(out.node("R").user_data.has("isSkelRoot"))
    # The skeleton is not a node; what is under it goes under its parent.
    var under = out.model.objects[out.find("Under")].parent
    assert_equal(out.scene.get(out.model.objects[under].node).name, "R")
    assert_equal(out.count("Anim"), 0)
    assert_equal(out.count("M"), 0)
    assert_equal(out.count("Sh"), 0)
    assert_equal(out.count("G"), 0)
    assert_equal(out.count("Cam"), 1)
    for name in ["Box", "Ball", "Can", "Tip", "Pill", "Me"]:
        assert_true(out.model.objects[out.find(name)].is_mesh, name)
    var layer = parse_usda_layer('#usda 1.0\ndef Cube "Box"\n{\n}\n')
    var size = layer.add(usd_string("big"))
    var spec = UsdSpec(SPEC_ATTRIBUTE)
    spec.set("default", size)
    _ = layer.put("/Box.size", spec^)
    with assert_raises(contains="size that is not a number"):
        _ = _compose(layer^)
    var weird = parse_usda_layer('#usda 1.0\ndef Cube "Box"\n{\n}\ndef "X"\n{\n}\n')
    var axis = weird.add(usd_number(5))
    var axis_spec = UsdSpec(SPEC_ATTRIBUTE)
    axis_spec.set("default", axis)
    _ = weird.put("/Box.axis", axis_spec^)
    var kind = weird.add(usd_number(3))
    weird.specs[weird.spec("/X")].set("typeName", kind)
    var composed = _compose(weird^)
    assert_equal(composed.count("X"), 1)


def _mesh(name: String, extra: String = "") -> String:
    """Return a triangle mesh prim's text."""
    return (
        'def Mesh "' + name + '"\n{\n    int[] faceVertexCounts = [3]\n'
        + "    int[] faceVertexIndices = [0, 1, 2]\n"
        + "    point3f[] points = [(0, 0, 0), (1, 0, 0), (0, 1, 0)]\n"
        + extra
        + "}\n"
    )


def _archive() raises -> UsdAssets:
    """Return an archive of layers and an image for references."""
    var assets = UsdAssets()
    _layer_asset(
        assets,
        "geo.usda",
        'def Xform "Shape"\n{\n' + _mesh("M") + "}\n"
        + 'def Xform "Nested"\n{\n    def Xform "Inner"\n    {\n' + _mesh("Deep") + "    }\n}\n"
        + 'def Xform "Moved"\n{\n    double3 xformOp:translate = (1, 0, 0)\n'
        + _mesh("Deep") + "}\n",
    )
    _layer_asset(assets, "flat.usda", _mesh("Flat"))
    _layer_asset(assets, "empty.usda", "")
    _image_asset(assets, "brick.png")
    return assets^


def test_references() raises:
    var out = _text(
        'def Xform "One" (\n    prepend references = @geo.usda@</Shape>\n)\n{\n}\n'
        + 'def "Typeless" (\n    prepend references = @geo.usda@</Shape>\n)\n{\n}\n'
        + 'def Scope "Scoped" (\n    prepend references = @geo.usda@</Shape>\n)\n{\n}\n'
        + 'def Xform "Whole" (\n    prepend references = @geo.usda@\n)\n{\n}\n'
        + 'def Xform "Nest" (\n    prepend references = @geo.usda@</Nested>\n)\n{\n}\n'
        + 'def Xform "Mov" (\n    prepend references = @geo.usda@</Moved>\n)\n{\n}\n'
        + 'def Xform "Two" (\n    prepend references = [@geo.usda@</Shape>, @flat.usda@]\n)\n{\n}\n'
        + 'def Xform "Nope" (\n    prepend references = @geo.usda@</Missing>\n)\n{\n}\n'
        + 'def Xform "Img" (\n    prepend references = @brick.png@\n)\n{\n}\n'
        + 'def Xform "Gone" (\n    prepend references = @gone.usda@\n)\n{\n}\n'
        + 'def Xform "Load" (\n    payload = @flat.usda@\n)\n{\n}\n'
        + 'def Xform "Text" (\n    payload = "abc"\n)\n{\n}\n'
        + 'def Xform "Blank" (\n    payload =\n    prepend references = {\n    }\n)\n{\n}\n'
        + 'def Xform "Void" (\n    prepend references = @empty.usda@</X>\n)\n{\n}\n'
        + 'def Xform "Both" (\n    prepend references = @flat.usda@\n    payload = @geo.usda@\n)\n{\n}\n',
        _archive(),
    )
    assert_true(out.model.objects[out.find("One")].is_mesh)
    assert_true(out.model.objects[out.find("Typeless")].is_mesh)
    # A scope does not take the mesh, which is lost, as in three.js.
    assert_false(out.model.objects[out.find("Scoped")].is_mesh)
    var whole = out.find("Whole")
    assert_equal(out.model.objects[out.find("Nested")].parent, whole)
    assert_false(out.model.objects[out.find("Nest")].is_mesh)
    assert_false(out.model.objects[out.find("Mov")].is_mesh)
    var two = out.find("Two")
    assert_equal(out.model.objects[out.find("Flat")].parent, two)
    assert_false(out.model.objects[out.find("Nope")].is_mesh)
    assert_false(out.model.objects[out.find("Img")].is_mesh)
    assert_false(out.model.objects[out.find("Gone")].is_mesh)
    assert_true(out.model.objects[out.find("Load")].is_mesh)
    assert_false(out.model.objects[out.find("Text")].is_mesh)
    assert_false(out.model.objects[out.find("Blank")].is_mesh)
    assert_false(out.model.objects[out.find("Void")].is_mesh)
    assert_true(out.model.objects[out.find("Both")].is_mesh)


def test_references_nest_at_most_64_deep() raises:
    var assets = UsdAssets()
    _layer_asset(
        assets,
        "self.usda",
        'def Xform "Loop" (\n    prepend references = @self.usda@\n)\n{\n}\n',
    )
    with assert_raises(contains="64 deep"):
        _ = _text(
            'def Xform "A" (\n    prepend references = @self.usda@\n)\n{\n}\n', assets
        )
    assert_equal(MAX_REFERENCE_DEPTH, 64)


def _variant_layer() raises -> UsdLayer:
    """Return a layer whose `/Toy` has three variant sets."""
    var layer = parse_usda_layer(
        '#usda 1.0\ndef Xform "Toy"\n{\n' + _mesh("Body") + "}\n"
        + 'def Scope "Looks"\n{\n    def Material "Red"\n    {\n    }\n}\n'
    )
    var toy = layer.spec("/Toy")
    var sets = layer.add(usd_strings(["color", "size", "shape"]))
    layer.specs[toy].set("variantSetChildren", sets)
    var red = layer.add(usd_string("red"))
    var odd = layer.add(usd_number(4))
    var selection = UsdValue(USD_OBJECT)
    selection.strings = ["color", "size"]
    selection.items = [red, odd]
    var chosen = layer.add(selection^)
    layer.specs[toy].set("variantSelection", chosen)
    var set_spec = UsdSpec(SPEC_ATTRIBUTE)
    set_spec.set("variantChildren", layer.add(usd_strings(["round"])))
    _ = layer.put("/Toy/{shape=}", set_spec^)
    for variant in ["/Toy/{color=red}", "/Toy/{color=blue}", "/Toy/{shape=round}"]:
        _ = layer.put(variant, UsdSpec(SPEC_VARIANT))
    for prim in [
        "/Toy/{color=red}/Badge",
        "/Toy/{color=blue}/Tag",
        "/Toy/{shape=round}/Knob",
    ]:
        var spec = UsdSpec(SPEC_PRIM)
        spec.set("typeName", layer.add(usd_string("Xform")))
        _ = layer.put(prim, spec^)
    var moved_to = UsdSpec(SPEC_ATTRIBUTE)
    moved_to.set("default", layer.add(usd_numbers([0, 0, 5])))
    _ = layer.put("/Toy/{color=red}/Body.xformOp:translate", moved_to^)
    var badge = UsdSpec(SPEC_ATTRIBUTE)
    badge.set("default", layer.add(usd_numbers([0, 2, 0])))
    _ = layer.put("/Toy/{shape=round}/Badge.xformOp:translate", badge^)
    var binding = UsdSpec(SPEC_RELATIONSHIP)
    binding.set("targetPaths", layer.add(usd_strings(["/Looks/Red"])))
    _ = layer.put("/Toy/{color=red}/Body.material:binding", binding^)
    var toy_binding = UsdSpec(SPEC_RELATIONSHIP)
    toy_binding.set("targetPaths", layer.add(usd_strings(["/Looks/Red"])))
    _ = layer.put("/Toy/{color=red}.material:binding", toy_binding^)
    var empty = UsdSpec(SPEC_RELATIONSHIP)
    empty.set("targetPaths", layer.add(UsdValue(USD_NULL)))
    _ = layer.put("/Toy/{shape=round}/Body.material:binding", empty^)
    # A shader under a prim that has no spec, under a variant: its walk to
    # a material passes a path of no spec, a spec that is not a prim, and a
    # prim that is not a material.
    var shader = UsdSpec(SPEC_PRIM)
    shader.set("typeName", layer.add(usd_string("Shader")))
    _ = layer.put("/Toy/{color=red}/Mat/Sh", shader^)
    # A property of no prim, and a material of no parent.
    _ = layer.put("loose", UsdSpec(SPEC_ATTRIBUTE))
    _ = layer.put(".x", UsdSpec(SPEC_ATTRIBUTE))
    var material = UsdSpec(SPEC_PRIM)
    material.set("typeName", layer.add(usd_string("Material")))
    _ = layer.put("M", material^)
    return layer^


def test_variants() raises:
    var out = _compose(_variant_layer())
    assert_equal(out.count("Badge"), 1)
    assert_equal(out.count("Tag"), 0)
    assert_equal(out.count("Knob"), 1)
    _near(out.node("Body").position.z, 5)
    _near(out.node("Badge").position.y, 2)
    # A file that references the layer selects the variant.
    var assets = UsdAssets()
    assets.add("toy.usda", USD_LAYER, List[UInt8](), _variant_layer())
    var picked = _text(
        'def Xform "P" (\n    prepend references = @toy.usda@\n    variants = {\n'
        + '        string color = "blue"\n    }\n)\n{\n}\n',
        assets,
    )
    assert_equal(picked.count("Tag"), 1)
    assert_equal(picked.count("Badge"), 0)


def test_variant_refusals_and_edges() raises:
    var layer = parse_usda_layer('#usda 1.0\ndef Xform "A"\n{\n}\n')
    var sets = layer.add(usd_numbers([1]))
    layer.specs[layer.spec("/A")].set("variantSetChildren", sets)
    with assert_raises(contains="variantSetChildren"):
        _ = _compose(layer^)
    var none = parse_usda_layer('#usda 1.0\ndef Xform "A"\n{\n}\n')
    var empty = none.add(usd_strings(List[String]()))
    none.specs[none.spec("/A")].set("variantSetChildren", empty)
    var selection = none.add(UsdValue(USD_OBJECT))
    none.specs[none.spec("/A")].set("variantSelection", selection)
    assert_equal(_compose(none^).count("A"), 1)


def test_nested_variant_selections() raises:
    var assets = UsdAssets()
    assets.add("toy.usda", USD_LAYER, List[UInt8](), _variant_layer())
    _layer_asset(
        assets,
        "outer.usda",
        'def Xform "O" (\n    prepend references = @toy.usda@\n    variants = {\n'
        + '        string color = "red"\n    }\n)\n{\n}\n',
    )
    # The outer file's selection wins over the inner prim's own.
    var out = _text(
        'def Xform "P" (\n    prepend references = @outer.usda@\n    variants = {\n'
        + '        string color = "blue"\n        string size = "big"\n    }\n)\n{\n}\n',
        assets,
    )
    assert_equal(out.count("Tag"), 1)


def _looks() -> String:
    """Return materials for binding tests."""
    return (
        'def Scope "Looks"\n{\n'
        + '    def Material "A"\n    {\n        def Shader "S"\n        {\n'
        + '            uniform token info:id = "UsdPreviewSurface"\n'
        + "            color3f inputs:diffuseColor = (1, 0, 0)\n        }\n    }\n"
        + '    def Material "B"\n    {\n        def Shader "S"\n        {\n'
        + '            uniform token info:id = "ND_UsdPreviewSurface_surfaceshader"\n'
        + "            color3f inputs:diffuseColor = (0, 0, 1)\n        }\n"
        + '        def Shader "Bare"\n        {\n        }\n'
        + '        def Shader "NoFile"\n        {\n'
        + '            uniform token info:id = "UsdUVTexture"\n        }\n    }\n'
        + '    def Material "Tex"\n    {\n        def Shader "T"\n        {\n'
        + '            uniform token info:id = "UsdUVTexture"\n'
        + "            asset inputs:file = @x.png@\n        }\n    }\n}\n"
    )


def test_bindings() raises:
    var out = _text(
        'def Xform "Root"\n{\n'
        + _mesh("Own", "    rel material:binding = </Root/Looks/A>\n")
        + 'def Xform "Strong"\n{\n    rel material:binding = </Root/Looks/A> (\n'
        + '        bindMaterialAs = "strongerThanDescendants"\n    )\n'
        + _mesh("Weak", "    rel material:binding = </Root/Looks/B>\n")
        + "}\n"
        + 'def Xform "Normal"\n{\n    rel material:binding = </Root/Looks/A> (\n'
        + '        bindMaterialAs = "weakerThanDescendants"\n    )\n'
        + _mesh("Near", "    rel material:binding = </Root/Looks/B>\n")
        + "}\n"
        + _mesh(
            "Scan",
            '    def GeomSubset "S"\n    {\n        rel material:binding = </Root/Looks/B>\n    }\n'
            + '    def GeomSubset "T"\n    {\n        rel material:binding = </Root/Looks/Tex>\n    }\n',
        )
        + _mesh(
            "Scan2",
            '    def GeomSubset "S"\n    {\n        rel material:binding = </Root/Looks/B>\n    }\n',
        )
        + _mesh("Fallback")
        + _looks()
        + "}\n"
        + 'def Xform "Other"\n{\n'
        + _mesh("M2")
        + 'def Scope "Materials"\n{\n    def Material "Z"\n    {\n'
        + '        def Shader "S"\n        {\n            uniform token info:id = "UsdPreviewSurface"\n'
        + "            color3f inputs:diffuseColor = (0, 1, 0)\n        }\n    }\n}\n}\n"
        + 'def Xform "Third"\n{\n'
        + _mesh("M3")
        + 'def Material "Loose"\n{\n}\n}\n'
        + _mesh("Bare")
        + 'def Shader "TopShader"\n{\n}\ndef GeomSubset "TopSubset"\n{\n}\n'
    )
    assert_equal(out.material("Own").color.g, 0)
    # A parent that is stronger than what is under it wins.
    assert_equal(out.material("Weak").color.r, 255)
    assert_equal(out.material("Near").color.b, 255)
    assert_equal(out.material("Near").color.r, 0)
    # The scan finds the bound material with a texture, which has no
    # surface shader, so the material stays white.
    assert_equal(out.material("Scan").color.g, 255)
    assert_equal(out.material("Scan2").color.r, 0)
    assert_equal(out.material("Scan2").color.b, 255)
    assert_equal(out.material("Fallback").color.g, 0)
    assert_equal(out.material("M2").color.r, 0)
    assert_equal(out.material("M3").color.r, 255)
    assert_equal(out.material("Bare").color.r, 255)


def test_own_bindings() raises:
    for kind in range(4):
        var layer = parse_usda_layer("#usda 1.0\n" + _mesh("M") + _looks())
        var value: Int
        if kind == 0:
            value = layer.add(usd_strings(["/Looks/B"]))
        elif kind == 1:
            value = layer.add(usd_string("/Looks/B"))
        elif kind == 2:
            value = layer.add(usd_string(""))
        else:
            value = layer.add(usd_number(3))
        layer.specs[layer.spec("/M")].set("material:binding", value)
        if kind == 3:
            with assert_raises(contains="not a path"):
                _ = _compose(layer^)
            continue
        var out = _compose(layer^)
        # A binding of its own, or none and the first look.
        var r = out.material("M").color.r
        assert_equal(Int(r), 0 if kind < 2 else 255)



def _shader(name: String, body: String) -> String:
    """Return a shader prim's text."""
    return '        def Shader "' + name + '"\n        {\n' + body + "        }\n"


def _texture(name: String, file: String, extra: String = "") -> String:
    """Return a `UsdUVTexture` shader's text."""
    return _shader(
        name,
        '            uniform token info:id = "UsdUVTexture"\n'
        + "            asset inputs:file = @" + file + "@\n" + extra,
    )


def _surface(name: String, body: String) -> String:
    """Return a `UsdPreviewSurface` shader's text."""
    return _shader(name, '            uniform token info:id = "UsdPreviewSurface"\n' + body)


def _material(name: String, shaders: String) -> String:
    """Return a material prim's text, under `/L`."""
    return '    def Material "' + name + '"\n    {\n' + shaders + "    }\n"


def _bound(name: String, material: String) -> String:
    """Return a mesh bound to a material of `/L`."""
    return _mesh(name, "    rel material:binding = </L/" + material + ">\n")


def _map(result: _Out, name: String, at: Int = 0) raises -> Tuple[Int, Int]:
    """Return which of a mesh's maps are there: the color map and the
    normal map, as texture ids or -1."""
    var m = result.material(name, at)
    return (m.map.value, m.normal_map.value)


def test_surface_values() raises:
    var out = _text(
        _bound("Full", "Full") + _bound("Short", "Short")
        + 'def Scope "L"\n{\n'
        + _material(
            "Full",
            _surface(
                "S",
                "            color3f inputs:diffuseColor = (0.5, 0.5, 0.5)\n"
                + "            color3f inputs:emissiveColor = (0.1, 0.2, 0.3)\n"
                + "            float inputs:roughness = 0.25\n"
                + "            float inputs:metallic = 0.75\n"
                + "            float inputs:ior = 1.3\n"
                + "            color3f inputs:specularColor = (0.2, 0.2, 0.2)\n"
                + "            float inputs:clearcoat = 0.5\n"
                + "            float inputs:clearcoatRoughness = 0.1\n"
                + "            float inputs:opacity = 0.5\n",
            ),
        )
        + _material(
            "Short",
            _surface(
                "S",
                "            float2 inputs:diffuseColor = (1, 0)\n"
                + "            float2 inputs:emissiveColor = (1, 0)\n"
                + "            float2 inputs:specularColor = (1, 0)\n"
                + "            float inputs:opacity = 1\n",
            ),
        )
        + "}\n"
    )
    var full = out.material("Full")
    assert_equal(full.color.r, 128)
    assert_equal(full.emissive.b, 77)
    _near(full.roughness, 0.25)
    _near(full.metalness, 0.75)
    _near(full.ior, 1.3)
    assert_equal(full.specular_color.r, 51)
    _near(full.clearcoat, 0.5)
    _near(full.clearcoat_roughness, 0.1)
    _near(full.opacity, 0.5)
    assert_true(full.transparent)
    var short = out.material("Short")
    assert_equal(short.color.g, 255)
    assert_equal(short.emissive.r, 0)
    assert_equal(short.specular_color.g, 255)
    assert_false(short.transparent)


def test_surface_refusals() raises:
    with assert_raises(contains="roughness is not a number"):
        _ = _text(
            _bound("M", "A") + 'def Scope "L"\n{\n'
            + _material("A", _surface("S", '            string inputs:roughness = "x"\n'))
            + "}\n"
        )
    with assert_raises(contains="zero to one"):
        _ = _text(
            _bound("M", "A") + 'def Scope "L"\n{\n'
            + _material("A", _surface("S", "            color3f inputs:diffuseColor = (2, 0, 0)\n"))
            + "}\n"
        )


def _maps() -> String:
    """Return materials of textures, for an archive with `brick.png`."""
    var maps = _material(
        "Maps",
        _surface(
            "PS",
            "            color3f inputs:diffuseColor.connect = </L/Maps/C.outputs:rgb>\n"
            + "            color3f inputs:emissiveColor.connect = </L/Maps/E.outputs:rgb>\n"
            + "            normal3f inputs:normal.connect = </L/Maps/N.outputs:rgb>\n"
            + "            float inputs:roughness.connect = </L/Maps/C.outputs:r>\n"
            + "            float inputs:metallic.connect = </L/Maps/Me.outputs:r>\n"
            + "            float inputs:occlusion.connect = </L/Maps/O.outputs:r>\n"
            + "            color3f inputs:specularColor.connect = </L/Maps/Sp.outputs:rgb>\n"
            + "            float inputs:opacity.connect = </L/Maps/C.outputs:a>\n"
            + "            float inputs:opacityThreshold = 0.5\n",
        )
        + _surface("PS3", "")
        + _texture(
            "C",
            "brick.png",
            "            float4 inputs:scale = (0.5, 0.5, 0.5, 1)\n"
            + "            token[] inputs:bias = [\"x\", \"y\"]\n"
            + '            token inputs:wrapS = "mirror"\n'
            + '            token inputs:wrapT = "clamp"\n'
            + "            float2 inputs:st.connect = </L/Maps/P.outputs:result>\n",
        )
        + _shader(
            "P",
            '            uniform token info:id = "UsdTransform2d"\n'
            + "            float2 inputs:in.connect = </L/Maps/R.outputs:result>\n"
            + "            float2 inputs:scale = (2, 3)\n"
            + "            float2 inputs:translation = (0.25, 0.5)\n"
            + "            float inputs:rotation = 45\n",
        )
        + _shader(
            "R",
            '            uniform token info:id = "UsdPrimvarReader_float2"\n'
            + '            string inputs:varname = "st1"\n',
        )
        + _texture(
            "E",
            "textures/brick.png",
            '            token inputs:wrapS = "repeat"\n'
            + "            int inputs:wrapT = 5\n"
            + "            float2 inputs:st.connect = </L/Maps/R2.outputs:result>\n",
        )
        + _shader(
            "R2",
            '            uniform token info:id = "UsdPrimvarReader_float2"\n'
            + '            string inputs:varname = "st"\n',
        )
        + _texture(
            "N",
            "brick.png",
            "            float4 inputs:scale = (2, 3, 1, 1)\n"
            + "            float2 inputs:st.connect = </L/Maps/P2.outputs:result>\n",
        )
        + _shader(
            "P2",
            '            uniform token info:id = "UsdTransform2d"\n'
            + "            float[] inputs:scale = [3]\n"
            + '            string inputs:rotation = "x"\n',
        )
        + _texture(
            "Me",
            "brick.png",
            "            float4 inputs:scale = (1, 1, 1, 1)\n"
            + "            float2 inputs:st.connect = </Nowhere.outputs:result>\n",
        )
        + _texture("O", "missing.png")
        + _texture(
            "Sp",
            "brick.png",
            "            float4 inputs:scale = (0.25, 0.25, 0.25, 1)\n"
            + "            float2 inputs:st.connect = </L/Maps/PS3.outputs:surface>\n",
        ),
    )
    var maps2 = _material(
        "Maps2",
        _surface(
            "PS",
            "            color3f inputs:diffuseColor.connect = </L/Maps2/C.outputs:rgb>\n"
            + "            color3f inputs:emissiveColor.connect = </L/Maps2/C2.outputs:rgb>\n"
            + "            normal3f inputs:normal.connect = </L/Maps2/N.outputs:rgb>\n"
            + "            float inputs:opacity.connect = </L/Maps2/C.outputs:a>\n",
        )
        + _texture("C", "brick.png", "            float2 inputs:scale = (1, 1)\n")
        + _texture("C2", "brick.png", "            float2 inputs:scale = (1, 1)\n")
        + _texture("N", "brick.png", "            float[] inputs:scale = []\n"),
    )
    var maps3 = _material(
        "Maps3",
        _surface("PS", "            normal3f inputs:normal.connect = </L/Maps3/N.outputs:rgb>\n")
        + _texture("N", "brick.png", "            float[] inputs:scale = [2]\n"),
    )
    return 'def Scope "L"\n{\n' + maps + maps2 + maps3 + "}\n"


def test_texture_maps() raises:
    var assets = UsdAssets()
    _image_asset(assets, "brick.png")
    var out = _text(
        _bound("A", "Maps") + _bound("B", "Maps2") + _bound("C", "Maps3") + _maps(),
        assets,
    )
    var a = out.material("A")
    assert_true(a.map != NO_TEXTURE)
    # The color map and the roughness map share a texture, so they share
    # its color space: the roughness map's, the last one set.
    assert_true(a.map == a.roughness_map)
    ref color = out.store.textures.get(a.map)
    assert_true(color.color_space == LINEAR)
    assert_true(color.wrap_s == MIRROR)
    assert_true(color.wrap_t == CLAMP)
    assert_equal(color.channel.value, 1)
    _near(color.repeat.y, 3)
    _near(color.offset.x, 0.25)
    _near(color.rotation.value, 0.7853982)
    # The texture's scale is the color, sRGB.
    assert_equal(a.color.r, 128)
    ref emissive = out.store.textures.get(a.emissive_map)
    assert_true(emissive.wrap_s == REPEAT)
    assert_true(emissive.wrap_t == REPEAT)
    assert_equal(emissive.channel.value, 0)
    assert_equal(a.emissive.r, 255)
    _near(a.normal_scale.x, 2)
    _near(a.normal_scale.y, 3)
    ref normal = out.store.textures.get(a.normal_map)
    _near(normal.repeat.x, 1)
    _near(normal.rotation.value, 0)
    assert_true(a.ao_map == NO_TEXTURE)
    _near(a.metalness, 1)
    _near(a.roughness, 1)
    assert_equal(a.specular_color.r, 64)
    _near(a.alpha_test, 0.5)
    assert_false(a.transparent)
    var b = out.material("B")
    assert_equal(b.color.r, 255)
    assert_equal(b.emissive.r, 0)
    assert_true(isnan(Float64(b.normal_scale.x)))
    assert_true(isnan(Float64(b.normal_scale.y)))
    assert_true(b.transparent)
    var c = out.material("C")
    _near(c.normal_scale.x, 2)
    assert_true(isnan(Float64(c.normal_scale.y)))
    var found_bias = False
    for texture in out.model.textures:
        if texture.bias:
            found_bias = True
            assert_equal(len(texture.bias.value()), 2)
    assert_true(found_bias)


def test_texture_refusals() raises:
    var assets = UsdAssets()
    _image_asset(assets, "brick.png")
    var start = _bound("M", "A") + 'def Scope "L"\n{\n'
    with assert_raises(contains="st2"):
        _ = _text(
            start
            + _material(
                "A",
                _surface("S", "            color3f inputs:diffuseColor.connect = </L/A/T.outputs:rgb>\n")
                + _texture("T", "brick.png", "            float2 inputs:st.connect = </L/A/R.outputs:result>\n")
                + _shader(
                    "R",
                    '            uniform token info:id = "UsdPrimvarReader_float2"\n'
                    + '            string inputs:varname = "st2"\n',
                ),
            )
            + "}\n",
            assets,
        )
    with assert_raises(contains="scale that is not a list"):
        _ = _text(
            start
            + _material(
                "A",
                _surface("S", "            color3f inputs:diffuseColor.connect = </L/A/T.outputs:rgb>\n")
                + _texture("T", "brick.png", "            float inputs:scale = 2\n"),
            )
            + "}\n",
            assets,
        )


def _one_texture(
    file: String, assets: UsdAssets, base: String = "", extra: String = ""
) raises -> _Out:
    """Compose a mesh whose color map reads one file."""
    return _text(
        _bound("M", "A") + 'def Scope "L"\n{\n'
        + _material(
            "A",
            _surface("S", "            color3f inputs:diffuseColor.connect = </L/A/T.outputs:rgb>\n")
            + _shader(
                "T",
                '            uniform token info:id = "UsdUVTexture"\n'
                + "            asset inputs:file = @" + file + "@\n" + extra,
            ),
        )
        + "}\n",
        assets,
        base,
    )


def test_finding_textures() raises:
    var assets = UsdAssets()
    _image_asset(assets, "textures/brick.png")
    _layer_asset(assets, "geo.usda", "")
    # By its last part, and not a layer.
    var out = _one_texture("x/y/brick.png", assets)
    assert_true(out.model.textures[0].in_archive)
    out = _one_texture("q/geo.usda", assets)
    assert_true(out.material("M").map == NO_TEXTURE)
    # By its path as written, when the folder's path is not there.
    out = _one_texture("textures/brick.png", assets, "sub")
    assert_equal(out.model.textures[0].source, "textures/brick.png")
    # On the disk, beside the file: there, not there, and not an image.
    var none = UsdAssets()
    out = _one_texture("brick.png", none, "assets/")
    assert_true(out.model.textures[0].loaded)
    assert_false(out.model.textures[0].in_archive)
    out = _one_texture("none.png", none, "assets/")
    assert_false(out.model.textures[0].loaded)
    assert_equal(out.model.missing_textures[0], "assets/none.png")
    out = _one_texture("usd/geo.usda", none, "assets/")
    assert_false(out.model.textures[0].loaded)
    # With no folder a file that is nowhere is no texture.
    out = _one_texture("brick.png", none)
    assert_true(out.material("M").map == NO_TEXTURE)
    # A file of no name is no texture.
    out = _one_texture("", assets)
    assert_true(out.material("M").map == NO_TEXTURE)
    # A texture not in the archive is decoded as missing.
    var bad = UsdAssets()
    bad.add("bad.png", USD_IMAGE, [1, 2, 3], UsdLayer())
    out = _one_texture("bad.png", bad)
    assert_false(out.model.textures[0].loaded)
    var empty = UsdAssets()
    empty.add("empty.png", USD_IMAGE, List[UInt8](), UsdLayer())
    out = _one_texture("empty.png", empty)
    assert_false(out.model.textures[0].loaded)


def test_texture_connections() raises:
    var assets = UsdAssets()
    _image_asset(assets, "brick.png")
    # A file with its `@`s, a file that is not a path, a connection list
    # that is empty, and one whose first entry is not a path.
    var layer = parse_usda_layer(
        "#usda 1.0\n" + _bound("M", "A") + _bound("N", "B") + 'def Scope "L"\n{\n'
        + _material(
            "A",
            _surface("S", "            color3f inputs:diffuseColor.connect = </L/A/T.outputs:rgb>\n")
            + _texture("T", "brick.png"),
        )
        + _material(
            "B",
            _surface("S", "            color3f inputs:diffuseColor.connect = </L/B/T.outputs:rgb>\n"),
        )
        + "}\n"
    )
    var file = layer.add(usd_string("@brick.png@"))
    layer.specs[layer.spec("/L/A/T.inputs:file")].set("default", file)
    var empty = layer.add(usd_strings(List[String]()))
    layer.specs[layer.spec("/L/B/S.inputs:diffuseColor")].set("connectionPaths", empty)
    var out = _compose(layer^, assets)
    assert_true(out.material("M").map != NO_TEXTURE)
    assert_true(out.material("N").map == NO_TEXTURE)
    var numbers = parse_usda_layer(
        "#usda 1.0\n" + _bound("M", "A") + 'def Scope "L"\n{\n'
        + _material(
            "A",
            _surface("S", "            color3f inputs:diffuseColor.connect = </L/A/T.outputs:rgb>\n")
            + _texture("T", "brick.png"),
        )
        + "}\n"
    )
    var odd = UsdValue(USD_ARRAY)
    odd.items = [numbers.add(usd_number(1))]
    var links = numbers.add(odd^)
    numbers.specs[numbers.spec("/L/A/S.inputs:diffuseColor")].set("connectionPaths", links)
    out = _compose(numbers^, assets)
    assert_true(out.material("M").map == NO_TEXTURE)
    var wrong = parse_usda_layer(
        "#usda 1.0\n" + _bound("M", "A") + 'def Scope "L"\n{\n'
        + _material(
            "A",
            _surface("S", "            color3f inputs:diffuseColor.connect = </L/A/T.outputs:rgb>\n")
            + _texture("T", "brick.png"),
        )
        + "}\n"
    )
    var number = wrong.add(usd_number(1))
    wrong.specs[wrong.spec("/L/A/T.inputs:file")].set("default", number)
    with assert_raises(contains="texture file that is not a path"):
        _ = _compose(wrong^, assets)


def test_shader_ids() raises:
    # A shader whose `info:id` is a field of its prim, and one of no
    # string; a connection to what is not a texture; a material that is
    # not there.
    var layer = parse_usda_layer(
        "#usda 1.0\n" + _bound("M", "A") + _bound("N", "Gone") + 'def Scope "L"\n{\n'
        + _material(
            "A",
            _shader("S", "            color3f inputs:diffuseColor = (0, 1, 0)\n")
            + _shader(
                "Q",
                '            uniform token info:id = "UsdPreviewSurface"\n'
                + "            color3f inputs:diffuseColor.connect = </L/A/S.outputs:rgb>\n"
                + "            color3f inputs:emissiveColor.connect = </L/A/Z.outputs:rgb>\n",
            )
            + _shader("Z", "            int info:id = 5\n"),
        )
        + "}\n"
    )
    var id = layer.add(usd_string("UsdPreviewSurface"))
    layer.specs[layer.spec("/L/A/S")].set("info:id", id)
    var out = _compose(layer^)
    assert_equal(out.material("M").color.r, 0)
    assert_equal(out.material("N").color.r, 255)


def test_display_colors() raises:
    var out = _text(
        _mesh(
            "Tint",
            "    color3f[] primvars:displayColor = [(0.2, 0.4, 0.6)]\n"
            + "    float[] primvars:displayOpacity = [0.5]\n",
        )
        + _mesh(
            "Short",
            "    float2[] primvars:displayColor = [(1, 0)]\n"
            + "    float[] primvars:displayOpacity = [0.5, 0.5]\n",
        )
        + _mesh("One", "    float[] primvars:displayOpacity = [1]\n")
        + _mesh(
            "Red",
            "    rel material:binding = </L/Red>\n"
            + "    color3f[] primvars:displayColor = [(0.2, 0.4, 0.6)]\n"
            + "    float[] primvars:displayOpacity = [0.5]\n",
        )
        + _mesh(
            "Clear",
            "    rel material:binding = </L/Clear>\n"
            + "    float[] primvars:displayOpacity = [0.5]\n",
        )
        + 'def Scope "L"\n{\n'
        + _material(
            "Red",
            _surface(
                "S",
                "            color3f inputs:diffuseColor = (1, 0, 0)\n"
                + "            float inputs:opacity = 0.75\n",
            ),
        )
        + _material(
            "Clear",
            _surface("S", "            float inputs:opacity.connect = </L/Clear/S.outputs:a>\n"),
        )
        + "}\n"
    )
    var tint = out.material("Tint")
    assert_equal(tint.color.r, 51)
    _near(tint.opacity, 0.5)
    assert_true(tint.transparent)
    assert_equal(out.material("Short").color.r, 255)
    _near(out.material("Short").opacity, 1)
    _near(out.material("One").opacity, 1)
    assert_equal(out.material("Red").color.g, 0)
    _near(out.material("Red").opacity, 0.75)
    _near(out.material("Clear").opacity, 1)
    var layer = parse_usda_layer("#usda 1.0\n" + _mesh("Odd"))
    var odd = UsdSpec(SPEC_ATTRIBUTE)
    odd.set("default", layer.add(usd_string("abc")))
    _ = layer.put("/Odd.primvars:displayColor", odd^)
    assert_equal(_compose(layer^).material("Odd").color.r, 255)


def test_subset_materials() raises:
    var out = _text(
        'def Mesh "Parts"\n{\n    int[] faceVertexCounts = [3, 3]\n'
        + "    int[] faceVertexIndices = [0, 1, 2, 0, 2, 3]\n"
        + "    point3f[] points = [(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)]\n"
        + "    rel material:binding = </L/Blue>\n"
        + "    float[] primvars:displayOpacity = [0.5]\n"
        + '    def GeomSubset "A"\n    {\n        int[] indices = [0]\n'
        + "        rel material:binding = </L/Red>\n    }\n"
        + '    def GeomSubset "B"\n    {\n        int[] indices = [1]\n    }\n}\n'
        + 'def Mesh "Loose"\n{\n    int[] faceVertexCounts = [3]\n'
        + "    int[] faceVertexIndices = [0, 1, 2]\n"
        + "    point3f[] points = [(0, 0, 0), (1, 0, 0), (1, 1, 0)]\n"
        + '    def GeomSubset "A"\n    {\n        int[] indices = [0]\n    }\n}\n'
        + 'def Scope "L"\n{\n'
        + _material("Red", _surface("S", "            color3f inputs:diffuseColor = (1, 0, 0)\n"))
        + _material("Blue", _surface("S", "            color3f inputs:diffuseColor = (0, 0, 1)\n"))
        + "}\n"
    )
    var parts = out.model.objects[out.find("Parts")].copy()
    assert_true(parts.material_list)
    assert_equal(len(parts.materials), 2)
    assert_equal(out.material("Parts", 0).color.r, 255)
    assert_equal(out.material("Parts", 1).color.b, 255)
    _near(out.material("Parts", 0).opacity, 1)
    assert_equal(out.material("Loose", 0).color.g, 255)


def test_coordinates_found() raises:
    var layer = parse_usda_layer(
        "#usda 1.0\n"
        + _mesh(
            "M",
            "    int[] primvars:foo:indices = [0]\n"
            + "    int[] primvars:skel:jointIndices = [0, 0, 0]\n"
            + "    float2[] primvars:bar = [(0, 0), (1, 0), (0, 1)]\n"
            + "    texCoord2f[] primvars:uvs = [(0, 0), (1, 0), (0, 1)]\n",
        )
    )
    var plain = UsdSpec(SPEC_ATTRIBUTE)
    plain.set("default", layer.add(usd_numbers([0, 0, 1, 1, 0, 1])))
    _ = layer.put("/M.primvars:baz", plain^)
    var out = _compose(layer^)
    ref geometry = out.store.geometries.get(out.model.objects[out.find("M")].geometry)
    assert_true(geometry.has_attribute("uv"))
    with assert_raises(contains="points is not an array"):
        _ = _text('def Mesh "M"\n{\n    point3f[] points = 5\n}\n')


def _samples(
    mut layer: UsdLayer, var times: List[Float64], var items: List[Int]
) raises -> Int:
    """Add time samples to a layer."""
    var out = UsdValue(USD_SAMPLES)
    out.numbers = times^
    out.items = items^
    return layer.add(out^)


def test_resolved_values() raises:
    var layer = parse_usda_layer(
        '#usda 1.0\ndef Mesh "V"\n{\n'
        + "    point3f[] points.connect = </V.alias>\n"
        + "    point3f[] alias = [(0, 0, 0), (1, 0, 0), (0, 1, 0)]\n"
        + "    int[] faceVertexCounts.connect = </V.faceVertexCounts>\n"
        + "    int[] faceVertexCounts = [3]\n"
        + "    int[] faceVertexIndices = [0, 1, 2]\n}\n"
        + 'def Xform "S"\n{\n}\n'
    )

    var a = layer.add(usd_numbers([1, 2, 3]))
    var b = layer.add(usd_numbers([4, 5, 6]))
    var translate = UsdSpec(SPEC_ATTRIBUTE)
    translate.set("timeSamples", _samples(layer, [1, 0], [a, b]))
    _ = layer.put("/S.xformOp:translate", translate^)
    var scale = UsdSpec(SPEC_ATTRIBUTE)
    scale.set("timeSamples", _samples(layer, [2], [layer.add(usd_numbers([2, 2, 2]))]))
    _ = layer.put("/S.xformOp:scale", scale^)
    var rotate = UsdSpec(SPEC_ATTRIBUTE)
    rotate.set("timeSamples", _samples(layer, [0], List[Int]()))
    _ = layer.put("/S.xformOp:rotateXYZ", rotate^)
    var none = UsdSpec(SPEC_ATTRIBUTE)
    none.set("timeSamples", _samples(layer, List[Float64](), List[Int]()))
    _ = layer.put("/S.none", none^)
    var number = UsdSpec(SPEC_ATTRIBUTE)
    number.set("timeSamples", layer.add(usd_number(3)))
    _ = layer.put("/S.number", number^)
    var empty = UsdSpec(SPEC_ATTRIBUTE)
    empty.set("connectionPaths", layer.add(usd_strings(List[String]())))
    _ = layer.put("/S.empty", empty^)
    var odd_links = UsdValue(USD_ARRAY)
    odd_links.items = [layer.add(usd_number(1))]
    var odd = UsdSpec(SPEC_ATTRIBUTE)
    odd.set("connectionPaths", layer.add(odd_links^))
    _ = layer.put("/S.odd", odd^)
    var out = _compose(layer^)
    _near(out.node("S").position.x, 4)
    _near(out.node("S").scale.x, 2)
    assert_true(out.model.objects[out.find("V")].is_mesh)


def test_empty_scene() raises:
    var out = _text("")
    assert_equal(len(out.model.objects), 1)
    assert_true(out.scene.get(out.model.root).object_type == GROUP_TYPE)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
