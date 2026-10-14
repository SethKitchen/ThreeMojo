# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `tools.json_tools`: Python meanings and `json.dumps` text.

The expected text comes from Python's `json.dumps(value, indent=2)`.
"""

from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from loaders.json import parse_json
from tools.json_tools import (
    MISSING,
    JsonWriter,
    equal,
    equals_text,
    equals_texts,
    get,
    index,
    is_none,
    keys,
    python_text,
    quote_ascii,
    truthy,
)


def test_get_and_index_follow_dict() raises:
    var doc = parse_json('{"a": {"b": 1}, "s": "x", "n": null}')
    var root = doc.root()
    assert_true(get(doc, root, "a") != MISSING)
    assert_equal(get(doc, root, "zz"), MISSING)
    assert_equal(get(doc, get(doc, root, "s"), "b"), MISSING)
    assert_equal(get(doc, MISSING, "b"), MISSING)
    assert_equal(doc.integer(index(doc, get(doc, root, "a"), "b")), 1)
    with assert_raises(contains="'zz'"):
        _ = index(doc, root, "zz")
    assert_true(is_none(doc, get(doc, root, "n")))
    assert_true(is_none(doc, MISSING))
    assert_equal(len(keys(doc, root)), 3)
    assert_equal(len(keys(doc, MISSING)), 0)


def test_truth_follows_python() raises:
    var doc = parse_json(
        '[0, 1, "", "x", [], [0], {}, {"a": 0}, true, false, null]'
    )
    var expected = [
        False,
        True,
        False,
        True,
        False,
        True,
        False,
        True,
        True,
        False,
        False,
    ]
    for i in range(len(expected)):
        assert_equal(truthy(doc, doc.at(doc.root(), i)), expected[i])
    assert_false(truthy(doc, MISSING))


def test_equality_follows_python() raises:
    var a = parse_json('{"x": [1, "a", {"k": null}], "y": true}')
    var b = parse_json('{"y": 1, "x": [1.0, "a", {"k": null}]}')
    assert_true(equal(a, a.root(), b, b.root()))
    var c = parse_json('{"x": [1, "a", {}], "y": true}')
    assert_false(equal(a, a.root(), c, c.root()))
    var d = parse_json('{"x": [1, "a"], "y": true}')
    assert_false(equal(a, a.root(), d, d.root()))
    var e = parse_json('{"x": [1, "a", {"k": null}], "z": true}')
    assert_false(equal(a, a.root(), e, e.root()))
    var f = parse_json('["1", null]')
    var g = parse_json("[1, null]")
    assert_false(equal(f, f.root(), g, g.root()))
    assert_true(equal(f, f.at(f.root(), 1), g, MISSING))
    assert_false(equal(f, f.at(f.root(), 0), g, MISSING))


def test_text_helpers() raises:
    var doc = parse_json('["a", "b", 22, 2.5, true, null, [1], 3]')
    var root = doc.root()
    var texts = List[String]()
    texts.append("a")
    texts.append("b")
    var array = parse_json('["a", "b"]')
    assert_true(equals_texts(array, array.root(), texts))
    texts.append("c")
    assert_false(equals_texts(array, array.root(), texts))
    assert_false(equals_texts(doc, MISSING, texts))
    assert_true(equals_text(doc, doc.at(root, 0), "a"))
    assert_false(equals_text(doc, doc.at(root, 2), "22"))
    assert_equal(python_text(doc, doc.at(root, 2)), "22")
    assert_equal(python_text(doc, doc.at(root, 3)), "2.5")
    assert_equal(python_text(doc, doc.at(root, 4)), "True")
    assert_equal(python_text(doc, doc.at(root, 5)), "None")
    assert_equal(python_text(doc, doc.at(root, 6)), "[\n  1\n]")
    assert_equal(python_text(doc, MISSING), "None")


def test_writer_matches_json_dumps() raises:
    var writer = JsonWriter()
    writer.begin_object()
    writer.key("a")
    writer.begin_array()
    writer.end()
    writer.key("b")
    writer.begin_object()
    writer.end()
    writer.key("c")
    writer.begin_array()
    writer.integer(1)
    writer.begin_object()
    writer.key("d")
    writer.null()
    writer.key("e")
    writer.boolean(True)
    writer.end()
    writer.end()
    writer.key("f")
    writer.string('é"')
    writer.end()
    var expected = (
        '{\n  "a": [],\n  "b": {},\n  "c": [\n    1,\n    {\n      "d": null,'
        + '\n      "e": true\n    }\n  ],\n  "f": "\\u00e9\\""\n}'
    )
    assert_equal(writer.text(), expected)
    var doc = parse_json(
        '{"a":[],"b":{},"c":[1,{"d":null,"e":true}],"f":"\\u00e9\\""}'
    )
    var copy = JsonWriter()
    copy.node(doc, doc.root())
    assert_equal(copy.text(), expected)
    var fraction = parse_json("[0.5]")
    var refused = JsonWriter()
    with assert_raises():
        refused.node(fraction, fraction.root())


def test_quote_ascii_matches_python() raises:
    assert_equal(
        quote_ascii('a"\\\n\r\t\b\f\x01\x7f'),
        '"a\\"\\\\\\n\\r\\t\\b\\f\\u0001\\u007f"',
    )
    assert_equal(quote_ascii("é😀"), '"\\u00e9\\ud83d\\ude00"')


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
