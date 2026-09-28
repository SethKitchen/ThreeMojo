# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.usda_parser`: the text's cleaning, the tree, the
regular expressions and the values, one quirk of three.js r186's
`USDAParser` at a time. `tests/test_usd.mojo` compares whole files with
three.js."""

from loaders.usd_specs import (
    SPEC_ATTRIBUTE,
    SPEC_PRIM,
    SPEC_RELATIONSHIP,
    USD_ARRAY,
    USD_BOOLEAN,
    USD_NULL,
    USD_NUMBER,
    USD_NUMBERS,
    USD_OBJECT,
    USD_SAMPLES,
    USD_STRING,
    USD_STRINGS,
    USD_UNDEFINED,
    UsdLayer,
)
from loaders.usda_parser import (
    UsdaTree,
    attribute_match,
    def_match,
    find_assignment,
    parse_string,
    parse_usda_layer,
    preprocess_usda,
    usda_tree,
)
from std.math import isnan
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def _lines(text: String) -> List[String]:
    """Return the cleaned lines of a text."""
    var out = List[String]()
    for line in preprocess_usda(text).split("\n"):
        out.append(String(line))
    return out^


def test_comments() raises:
    var lines = _lines(
        "#usda 1.0 # kept\na = 1 # dropped\nb = \"#\" # x\n/* one\ntwo */c\n"
        + "d /* e * / f */ g\n   # only\nh = '\\\"' # y\n"
    )
    assert_equal(lines[0], "#usda 1.0 # kept")
    assert_equal(lines[1], "a = 1")
    assert_equal(lines[2], 'b = "#"')
    assert_equal(lines[3], "c")
    assert_equal(lines[4], "d  g")
    assert_equal(lines[5], "")
    assert_equal(lines[6], "h = '\\\"'")
    # A comment that is not closed runs to the end, and so does a slash.
    assert_equal(preprocess_usda("a /* b"), "a")
    assert_equal(preprocess_usda("a /"), "a /")
    assert_equal(preprocess_usda("a/b"), "a/b")
    assert_equal(preprocess_usda("a /* * / *"), "a")


def test_triple_quotes() raises:
    assert_equal(preprocess_usda('a = """x\r\ny"""'), 'a = """x\\ny"""')
    assert_equal(preprocess_usda("a = '''x\ny'''"), "a = '''x\\ny'''")
    # One that is not closed runs to the end.
    assert_equal(preprocess_usda('a = """x\ny'), 'a = """x\\ny')
    assert_equal(preprocess_usda("''x ''"), "''x ''")
    assert_equal(preprocess_usda("'x'"), "'x'")
    assert_equal(preprocess_usda('""'), '""')
    assert_equal(preprocess_usda('a = """x"""""'), 'a = """x"""""')


def test_multiline_arrays() raises:
    var lines = _lines("a = [\n(1, 2),\n\n(3, 4)\n]\nb = [1]\nc = 2")
    assert_equal(lines[0], "a = [ (1, 2),  (3, 4) ]")
    assert_equal(lines[1], "b = [1]")
    assert_equal(lines[2], "c = 2")
    # A parenthesis counts only inside brackets, and an array still open
    # at the end is dropped, as in three.js.
    assert_equal(preprocess_usda("a = [\n(1, 2]\n)\nb = ["), "")
    assert_equal(preprocess_usda("a = [\n])("), "a = [ ])(")
    assert_equal(preprocess_usda("a ="), "a =")


def test_assignment() raises:
    assert_equal(find_assignment('a "=" = b'), 6)
    assert_equal(find_assignment("a '=' \\= = b"), 9)
    assert_equal(find_assignment("\"it's\" = x"), 7)
    assert_equal(find_assignment('"a" "b"'), -1)
    assert_equal(find_assignment(""), -1)


def test_trims_unicode_space() raises:
    assert_equal(preprocess_usda(" a "), "a")
    assert_equal(preprocess_usda("aé  "), "aé")
    assert_equal(preprocess_usda("\x01a"), "\x01a")


def test_def_match() raises:
    var found = def_match('def Xform "Root"')
    assert_equal(found.value()[0], "Xform")
    assert_equal(found.value()[1], "Root")
    found = def_match('def "B"')
    assert_equal(found.value()[0], "")
    assert_equal(found.value()[1], "B")
    found = def_match("def Mesh plain")
    assert_equal(found.value()[1], "plain")
    found = def_match("def  Plain")
    assert_equal(found.value()[0], "")
    assert_equal(found.value()[1], "Plain")
    found = def_match('def Xform "a b"')
    assert_equal(found.value()[1], "a b")
    # Backtracking gives the name a space.
    found = def_match('def Xform  "')
    assert_equal(found.value()[0], "Xform")
    assert_equal(found.value()[1], " ")
    found = def_match('def  "')
    assert_equal(found.value()[1], " ")
    assert_false(Bool(def_match("define x")))
    assert_false(Bool(def_match("def")))
    assert_false(Bool(def_match('def Xform"Root"')))
    assert_false(Bool(def_match('def "a"b"')))
    assert_false(Bool(def_match('def "')))
    assert_false(Bool(def_match('def x"y')))
    assert_false(Bool(def_match('over "A"')))


def test_attribute_match() raises:
    var found = attribute_match("uniform token[] xformOpOrder")
    assert_equal(found.value()[0], "token[]")
    assert_equal(found.value()[1], "xformOpOrder")
    found = attribute_match("custom float withMeta")
    assert_equal(found.value()[0], "custom")
    assert_equal(found.value()[1], "float withMeta")
    found = attribute_match("uniform token")
    assert_equal(found.value()[0], "uniform")
    found = attribute_match("uniform  [x] y")
    assert_equal(found.value()[0], "uniform")
    assert_equal(found.value()[1], "[x] y")
    found = attribute_match("a[] ")
    assert_false(Bool(found))
    found = attribute_match("a  ")
    assert_equal(found.value()[1], " ")
    found = attribute_match("a[]b c")
    assert_false(Bool(found))
    found = attribute_match("_9z: y")
    assert_false(Bool(found))
    found = attribute_match("_9zA y")
    assert_equal(found.value()[0], "_9zA")
    assert_false(Bool(attribute_match('"x" y')))
    assert_false(Bool(attribute_match("x{ y")))
    assert_false(Bool(attribute_match("x@ y")))
    assert_false(Bool(attribute_match("kind")))
    assert_false(Bool(attribute_match("uniformx")))


def test_parse_string() raises:
    assert_equal(parse_string('"a\\nb\\tc\\rd\\\\e\\"f\\qg"'), 'a\nb\tc\rd\\e"fqg')
    assert_equal(parse_string("'x'"), "x")
    assert_equal(parse_string('"'), "")
    assert_equal(parse_string(""), "")
    assert_equal(parse_string('"x'), '"x')
    assert_equal(parse_string("'x\""), "'x\"")
    assert_equal(parse_string("x'"), "x'")
    assert_equal(parse_string("a\\"), "a\\")


def test_tree() raises:
    var tree = usda_tree(
        '#usda 1.0\n(\n    upAxis = "Y"\n)\ndef Xform "A" (\n    kind = "k"\n)\n'
        + '{\n    float x = 1 (\n        doc = "d"\n    )\n    float x = 2 (\n'
        + "        doc = \"e\"\n    )\n    y.timeSamples = {\n        1: 2\n"
        + "        b: 3\n    }\n}\n}\n}\nname\n{\n}\n"
    )
    var a = tree.kid(0, 'def Xform "A"')
    assert_true(a > 0)
    assert_equal(tree.text(a, "kind").value(), '"k"')
    assert_equal(tree.text(a, "float x").value(), "2")
    assert_false(Bool(tree.text(a, "missing")))
    assert_false(Bool(tree.text(0, 'def Xform "A"')))
    assert_equal(tree.kid(a, "kind"), -1)
    assert_equal(tree.kid(a, "missing"), -1)
    assert_equal(len(tree.groups[a].meta_keys), 1)
    var meta = tree.meta(a, "float x")
    assert_equal(tree.text(meta, "doc").value(), '"e"')
    assert_equal(tree.meta(a, "kind"), -1)
    var samples = tree.kid(a, "y.timeSamples")
    assert_equal(tree.text(samples, "1").value(), "2")
    assert_false(Bool(tree.text(samples, "b")))
    assert_true(tree.kid(0, "name") > 0)


def test_tree_names() raises:
    # A line that ends with `{` or `(` and has nothing before it is named
    # by the last line that named nothing, or `null`.
    var tree = usda_tree('{\n}\nx\n(\n)\n{\n}\na "=" b\n{\n}')
    assert_true(tree.kid(0, "null") > 0)
    var x = tree.kid(0, "x")
    assert_true(x > 0)
    assert_true(tree.kid(0, 'a "=" b') > 0)
    # The same name opens the same group again; a text of that name opens
    # a string, and an empty text a new group.
    tree = usda_tree("a = 1\nb =\nc {\n}\nc {\nd = 2\n}\nb {\n}")
    var c = tree.kid(0, "c")
    assert_equal(tree.text(c, "d").value(), "2")
    assert_true(tree.kid(0, "b") > 0)
    tree = usda_tree("a = 1\na {\n}\n}\n}\n)\n")
    assert_equal(tree.text(0, "a").value(), "1")


def test_tree_refusals() raises:
    with assert_raises(contains="writes into a string"):
        _ = usda_tree("a = 1\na {\nb = 2\n}")
    with assert_raises(contains="writes into a string"):
        _ = usda_tree(")\nb = 2")
    with assert_raises(contains="writes into a string"):
        _ = usda_tree(")\n1: 2")
    with assert_raises(contains="writes into a string"):
        _ = usda_tree(")\nx {")
    with assert_raises(contains="writes into a string"):
        _ = usda_tree(")\nx (")
    # A write that is not made does not throw.
    _ = usda_tree(")\nx: 2\n}")


def test_tree_order() raises:
    var tree = usda_tree("b = 1\n10 = 2\n2 = 3\na = 4")
    var order = tree.order(0)
    assert_equal(tree.groups[0].keys[order[0]], "2")
    assert_equal(tree.groups[0].keys[order[1]], "10")
    assert_equal(tree.groups[0].keys[order[2]], "b")
    var empty = UsdaTree()
    assert_equal(len(empty.order(0)), 0)
    assert_equal(empty.meta(0, "x"), -1)


def _default(layer: UsdLayer, path: String) -> Int:
    """Return an attribute's default."""
    return layer.field(path, "default")


def _numbers(layer: UsdLayer, id: Int) raises -> List[Float64]:
    """Return an array of numbers, asserting that it is one."""
    assert_true(layer.kind(id) == USD_NUMBERS, "an array of numbers")
    return layer.values[id].numbers.copy()


def _one(text: String) raises -> UsdLayer:
    """Parse a prim `/P` of attributes."""
    return parse_usda_layer('def "P"\n{\n' + text + "\n}\n")


def test_header() raises:
    var layer = parse_usda_layer(
        '#usda 1.0\n(\n    upAxis = "Z"\n    defaultPrim =\n    metersPerUnit = 0.01\n'
        + "    framesPerSecond = 24\n    timeCodesPerSecond = {\n    }\n)\n"
    )
    assert_equal(layer.text(layer.field("/", "upAxis")), "Z")
    assert_equal(layer.field("/", "defaultPrim"), -1)
    assert_equal(layer.number(layer.field("/", "metersPerUnit")), 0.01)
    assert_equal(layer.number(layer.field("/", "framesPerSecond")), 24)
    assert_true(isnan(layer.number(layer.field("/", "timeCodesPerSecond"))))
    with assert_raises(contains="upAxis is a group"):
        _ = parse_usda_layer("#usda 1.0\n(\n    upAxis = {\n    }\n)\n")
    # A header of text has no fields, and no header neither.
    layer = parse_usda_layer("#usda 1.0 = x\n")
    assert_equal(len(layer.specs[0].names), 0)
    layer = parse_usda_layer("")
    assert_equal(len(layer.paths), 1)


def test_prims() raises:
    var layer = parse_usda_layer(
        'variants = {\n}\ndef Xform "A"\n{\n    def "B"\n    {\n    }\n'
        + '    over "C"\n    {\n    }\n}\ndef Scope "T" = 5\n'
    )
    assert_equal(layer.paths[0], "/")
    # `over "C"` reads as an attribute of type `over`.
    assert_equal(layer.paths[1], '/A."C"')
    assert_equal(layer.paths[2], "/A")
    assert_equal(layer.paths[3], "/A/B")
    assert_equal(layer.paths[4], "/T")
    assert_true(layer.specs[3].spec_type == SPEC_PRIM)
    assert_equal(layer.text(layer.field("/A", "typeName")), "Xform")
    assert_equal(layer.text(layer.field("/A/B", "typeName")), "")
    var children = layer.field("/", "primChildren")
    assert_equal(layer.values[children].strings[1], "T")
    assert_equal(layer.field("/A/B", "primChildren"), -1)


def test_prim_fields() raises:
    var layer = parse_usda_layer(
        'def "A" (\n    prepend references = @a.usda@</B>\n    payload = @p.usda@\n'
        + '    variants = {\n        string color = "red"\n        string  color = "blue"\n'
        + '        string size = "big"\n        other = 1\n    }\n)\n{\n'
        + '    uniform token[] xformOpOrder = ["xformOp:translate", "b"]\n}\n'
        + 'def "B" (\n    prepend references = {\n    }\n    payload = {\n    }\n'
        + "    variants = 3\n)\n{\n}\n"
        + 'def "C" (\n    variants = {\n        other = 1\n    }\n)\n{\n}\n'
    )
    var references = layer.field("/A", "references")
    assert_true(layer.kind(references) == USD_ARRAY)
    assert_equal(layer.text(layer.values[references].items[0]), "@a.usda@</B>")
    assert_equal(layer.text(layer.field("/A", "payload")), "@p.usda@")
    var chosen = layer.field("/A", "variantSelection")
    assert_equal(len(layer.values[chosen].strings), 2)
    assert_equal(layer.text(layer.object_value(chosen, "color")), "blue")
    var ops = layer.field("/A", "xformOpOrder")
    assert_equal(layer.values[ops].strings[0], "xformOp:translate")
    assert_equal(layer.values[ops].strings[1], "b")
    var group = layer.field("/B", "references")
    assert_true(layer.kind(layer.values[group].items[0]) == USD_OBJECT)
    assert_true(layer.kind(layer.field("/B", "payload")) == USD_OBJECT)
    assert_equal(layer.field("/B", "variantSelection"), -1)
    assert_equal(layer.field("/C", "variantSelection"), -1)
    with assert_raises(contains="is a group"):
        _ = _one("uniform token[] xformOpOrder = {\n}")
    with assert_raises(contains="is a group"):
        _ = parse_usda_layer(
            'def "A" (\n    variants = {\n        string c = {\n        }\n    }\n)\n{\n}\n'
        )


def test_relationships() raises:
    var layer = _one(
        "rel material:binding = </M> (\n    bindMaterialAs = \"strongerThanDescendants\"\n)\n"
        + "rel a = </X>\nrel b = <Y> (\n    doc = 1\n)\nrel c = </Z> (\n    bindMaterialAs = {\n    }\n)"
    )
    var binding = layer.spec("/P.material:binding")
    assert_true(layer.specs[binding].spec_type == SPEC_RELATIONSHIP)
    var targets = layer.field("/P.material:binding", "targetPaths")
    assert_equal(layer.values[targets].strings[0], "/M")
    assert_equal(
        layer.text(layer.field("/P.material:binding", "bindMaterialAs")),
        "strongerThanDescendants",
    )
    assert_equal(layer.field("/P.a", "bindMaterialAs"), -1)
    assert_equal(layer.field("/P.b", "bindMaterialAs"), -1)
    assert_equal(layer.text(layer.field("/P.c", "bindMaterialAs")), "[object Object]")
    with assert_raises(contains="is a group"):
        _ = _one("rel a = {\n}")


def test_connections_and_samples() raises:
    var layer = _one(
        "float a.connect = </X.y>\nfloat a = 2\nfloat b = 1\nfloat b.connect = Z\n"
        + "float3 c.timeSamples = {\n    2: (1, 2, 3),\n    0: (4, 5, 6)\n"
        + "    1.5: (7, 8, 9)\n    x = 1\n    0 {\n    }\n}\nfloat d.timeSamples = 5\n"
        + "float a = 3"
    )
    var a = layer.spec("/P.a")
    assert_true(layer.specs[a].spec_type == SPEC_ATTRIBUTE)
    var links = layer.field("/P.a", "connectionPaths")
    assert_equal(layer.values[links].strings[0], "/X.y")
    assert_equal(layer.number(_default(layer, "/P.a")), 3)
    var b = layer.field("/P.b", "connectionPaths")
    assert_equal(layer.values[b].strings[0], "Z")
    assert_equal(layer.number(_default(layer, "/P.b")), 1)
    var samples = layer.field("/P.c", "timeSamples")
    assert_true(layer.kind(samples) == USD_SAMPLES)
    var times = layer.values[samples].numbers.copy()
    assert_equal(len(times), 3)
    assert_equal(times[0], 0)
    assert_equal(times[1], 1.5)
    assert_equal(times[2], 2)
    assert_equal(len(_numbers(layer, layer.values[samples].items[0])), 3)
    # The comma after a sample reads as one more number, NaN.
    var last = _numbers(layer, layer.values[samples].items[2])
    assert_equal(len(last), 4)
    assert_true(isnan(last[3]))
    assert_equal(layer.number(_default(layer, "/P.d.timeSamples")), 5)


def test_values_by_type() raises:
    var layer = _one(
        "float3 v = (1, 2, 3)\nint2 w = (1, x)\nhalf4 u = (4)\nmatrix m = ((1, 2))\n"
        + "quatf q = (1, 2, 3, 4)\nquath r = (5)\nfloat f = 1.5\ndouble d = 2e3x\n"
        + "int i = -3\nasset s = @\"a.png\"@\nstring t = \"x\\ty\"\nbool b = 1\n"
    )
    var v = _numbers(layer, _default(layer, "/P.v"))
    assert_equal(v[2], 3)
    var w = _numbers(layer, _default(layer, "/P.w"))
    assert_true(isnan(w[1]))
    assert_equal(len(_numbers(layer, _default(layer, "/P.u"))), 1)
    assert_equal(len(_numbers(layer, _default(layer, "/P.m"))), 2)
    var q = _numbers(layer, _default(layer, "/P.q"))
    assert_equal(q[0], 2)
    assert_equal(q[3], 1)
    var r = _default(layer, "/P.r")
    assert_true(layer.kind(r) == USD_ARRAY)
    assert_true(layer.kind(layer.values[r].items[0]) == USD_UNDEFINED)
    assert_equal(layer.number(layer.values[r].items[3]), 5)
    assert_equal(layer.number(_default(layer, "/P.f")), 1.5)
    assert_equal(layer.number(_default(layer, "/P.d")), 2000)
    assert_equal(layer.number(_default(layer, "/P.i")), -3)
    assert_equal(layer.text(_default(layer, "/P.s")), "a.png")
    assert_equal(layer.text(_default(layer, "/P.t")), "x\ty")
    assert_equal(layer.text(_default(layer, "/P.b")), "1")
    assert_equal(layer.text(layer.field("/P.b", "typeName")), "bool")


def test_array_values() raises:
    var layer = _one(
        "int[] a = [1],\nint[] b = [(1, 2), (3, 4)]\ntoken[] c = [\"x\", \"y\"]\n"
        + "int[] d = []\nint[] e = [1, \"x\", true, null, {\"k\": 2, \"1\": 3}, [], {}]\n"
        + "int[] f = [[1], 2, []]\nint[] g = 5\nasset[] h = [@a@, @b@]\n"
        + "int[] i = [nan, 1]\nint[] j = [+1, 2]\nint[] k = [\"s\", false]\n"
        + "int[] l = [2, false]"
    )
    _ = _numbers(layer, _default(layer, "/P.a"))
    var b = _numbers(layer, _default(layer, "/P.b"))
    assert_equal(len(b), 4)
    var c = _default(layer, "/P.c")
    assert_equal(layer.values[c].strings[1], "y")
    assert_equal(len(_numbers(layer, _default(layer, "/P.d"))), 0)
    var e = _default(layer, "/P.e")
    assert_true(layer.kind(e) == USD_ARRAY)
    ref items = layer.values[e].items
    assert_true(layer.kind(items[0]) == USD_NUMBER)
    assert_true(layer.kind(items[1]) == USD_STRING)
    assert_true(layer.kind(items[2]) == USD_BOOLEAN)
    assert_true(layer.kind(items[3]) == USD_NULL)
    var object = items[4]
    assert_equal(layer.values[object].strings[0], "1")
    assert_equal(layer.number(layer.object_value(object, "k")), 2)
    assert_equal(len(_numbers(layer, items[5])), 0)
    assert_equal(len(layer.values[items[6]].strings), 0)
    var f = _default(layer, "/P.f")
    assert_true(layer.kind(f) == USD_NUMBERS)
    assert_equal(len(layer.values[f].numbers), 2)
    assert_equal(layer.number(_default(layer, "/P.g")), 5)
    var h = _default(layer, "/P.h")
    assert_equal(layer.values[h].strings[0], "@a@")
    var i = _default(layer, "/P.i")
    assert_true(layer.kind(i) == USD_ARRAY)
    assert_equal(layer.text(layer.values[i].items[0]), "nan")
    assert_equal(layer.number(layer.values[i].items[1]), 1)
    assert_equal(len(_numbers(layer, _default(layer, "/P.j"))), 2)
    assert_true(layer.kind(_default(layer, "/P.k")) == USD_ARRAY)
    assert_true(layer.kind(_default(layer, "/P.l")) == USD_ARRAY)


def test_quaternion_arrays() raises:
    var layer = _one(
        "quatf[] a = [(1, 2, 3, 4)]\nquath[] b = [\"w\", \"x\", \"y\", \"z\"]\n"
        + "quatd[] c = [1, \"x\", 3, 4]\nquatf[] d = []\nquatf[] e = 7"
    )
    var a = _numbers(layer, _default(layer, "/P.a"))
    assert_equal(a[0], 2)
    assert_equal(a[3], 1)
    var b = _default(layer, "/P.b")
    assert_equal(layer.values[b].strings[3], "w")
    var c = _default(layer, "/P.c")
    assert_equal(layer.text(layer.values[c].items[0]), "x")
    assert_equal(len(_numbers(layer, _default(layer, "/P.d"))), 0)
    assert_equal(layer.number(_default(layer, "/P.e")), 7)
    with assert_raises(contains="a string"):
        _ = _one('quatf[] q = "x"')
    with assert_raises(contains="multiple of four"):
        _ = _one("quatf[] q = [1, 2]")


def test_element_sizes() raises:
    var layer = parse_usda_layer(
        'def Mesh "M"\n{\n    point3f[] points = [(0, 0, 0), (1, 0, 0)]\n'
        + "    int[] primvars:skel:jointIndices = [0, 1, 2, 3]\n"
        + "    float[] primvars:skel:jointWeights = [1, 1, 1]\n}\n"
        + 'def Mesh "N"\n{\n    point3f[] points = []\n}\n'
        + 'def Mesh "O"\n{\n    point3f[] points = 5\n'
        + "    int[] primvars:skel:jointIndices = [0]\n}\n"
        + 'def Mesh "Q"\n{\n    point3f[] points = [(0, 0, 0)]\n'
        + "    int[] primvars:skel:jointIndices.connect = </X>\n"
        + "    int[] primvars:skel:jointWeights = []\n}\n"
        + 'def Mesh "R"\n{\n}\ndef Xform "S"\n{\n}\n'
    )
    assert_equal(layer.number(layer.field("/M.primvars:skel:jointIndices", "elementSize")), 2)
    assert_equal(layer.field("/M.primvars:skel:jointWeights", "elementSize"), -1)
    assert_equal(layer.field("/O.primvars:skel:jointIndices", "elementSize"), -1)
    assert_equal(layer.field("/Q.primvars:skel:jointIndices", "elementSize"), -1)
    assert_equal(layer.field("/Q.primvars:skel:jointWeights", "elementSize"), -1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
