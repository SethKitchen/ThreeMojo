# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.json`: every value kind, every escape, the number
grammar, the accessors, and every refusal with where it happened."""

from loaders.json import (
    ARRAY,
    BOOLEAN,
    MAX_DEPTH,
    NO_NODE,
    NULL,
    NUMBER,
    OBJECT,
    STRING,
    JsonDocument,
    JsonKind,
    JsonNode,
    parse_json,
)
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def refused(text: String) raises -> String:
    """Return the message a text is refused with."""
    try:
        _ = parse_json(text)
    except reason:
        return String(reason)
    raise Error("the text was accepted: " + text)


def test_the_six_kinds_are_valid_and_a_seventh_is_not() raises:
    assert_true(OBJECT.is_valid())
    assert_true(ARRAY.is_valid())
    assert_true(STRING.is_valid())
    assert_true(NUMBER.is_valid())
    assert_true(BOOLEAN.is_valid())
    assert_true(NULL.is_valid())
    assert_false(JsonKind(6).is_valid())
    var node = JsonNode(NUMBER)
    assert_equal(node.kind, NUMBER)
    assert_equal(node.number, Float64(0))
    assert_equal(len(node.children), 0)


def test_an_object_is_read_key_by_key_in_order() raises:
    var document = parse_json(
        ' {"a": 1, "b": "two", "c": true, "d": false, "e": null, "f": [1, 2],'
        ' "g": {"h": 3}} '
    )
    var root = document.root()
    assert_equal(root, 0)
    assert_equal(document.kind(root), OBJECT)
    assert_equal(document.length(root), 7)
    assert_equal(document.key(root, 0), "a")
    assert_equal(document.key(root, 6), "g")
    assert_equal(document.number(document.get(root, "a")), Float64(1))
    assert_equal(document.integer(document.get(root, "a")), 1)
    assert_equal(document.string(document.get(root, "b")), "two")
    assert_true(document.boolean(document.get(root, "c")))
    assert_false(document.boolean(document.get(root, "d")))
    assert_true(document.is_null(document.get(root, "e")))
    assert_false(document.is_null(document.get(root, "a")))
    var f = document.get(root, "f")
    assert_equal(document.kind(f), ARRAY)
    assert_equal(document.length(f), 2)
    assert_equal(document.number(document.at(f, 1)), Float64(2))
    var g = document.get(root, "g")
    assert_equal(document.integer(document.get(g, "h")), 3)
    assert_true(document.has(root, "a"))
    assert_false(document.has(root, "z"))
    assert_equal(document.get(root, "z"), NO_NODE)
    # An object's children can be walked by position as well.
    assert_equal(document.at(root, 1), document.get(root, "b"))
    # The last of two equal keys wins.
    var twice = parse_json('{"a": 1, "a": 2}')
    assert_equal(twice.integer(twice.get(twice.root(), "a")), 2)


def test_empty_containers_and_nesting_are_read() raises:
    var document = parse_json('[[], {}, [[[]]], {"a": {}}]')
    var root = document.root()
    assert_equal(document.kind(root), ARRAY)
    assert_equal(document.length(root), 4)
    assert_equal(document.length(document.at(root, 0)), 0)
    assert_equal(document.length(document.at(root, 1)), 0)
    var deep = document.at(document.at(document.at(root, 2), 0), 0)
    assert_equal(document.kind(deep), ARRAY)
    assert_equal(document.length(deep), 0)
    assert_equal(document.kind(document.get(document.at(root, 3), "a")), OBJECT)
    # A bare value is a document too.
    var bare = parse_json("  42 ")
    assert_equal(bare.integer(bare.root()), 42)
    var word = parse_json('"alone"')
    assert_equal(word.string(word.root()), "alone")


def test_every_escape_is_resolved_into_utf8() raises:
    var document = parse_json(
        '"a\\"b\\\\c\\/d\\be\\ff\\ng\\rh\\ti\\u0041\\u00e9\\u4e2d\\ud83d\\ude00"'
    )
    var text = document.string(document.root())
    var expected = List[UInt8]()
    for byte in 'a"b\\c/d'.as_bytes():
        expected.append(byte)
    expected.append(8)
    expected.append(101)
    expected.append(12)
    expected.append(102)
    expected.append(10)
    expected.append(103)
    expected.append(13)
    expected.append(104)
    expected.append(9)
    expected.append(105)
    for byte in "Aé中😀".as_bytes():
        expected.append(byte)
    var got = List[UInt8]()
    for byte in text.as_bytes():
        got.append(byte)
    assert_equal(len(got), len(expected))
    for index in range(len(got)):
        assert_equal(got[index], expected[index])
    # Raw UTF-8 passes through, and upper-case hex digits read.
    var raw = parse_json('"héllo \\u00C9"')
    assert_equal(raw.string(raw.root()), "héllo É")


def test_the_number_grammar_is_read_and_held_to() raises:
    var document = parse_json(
        "[0, -0, 1.5, -2.25, 1e3, 1E-2, 12.5e+1, 123456789]"
    )
    var root = document.root()
    assert_equal(document.number(document.at(root, 0)), Float64(0))
    assert_equal(document.number(document.at(root, 1)), Float64(0))
    assert_almost_equal(document.number(document.at(root, 2)), Float64(1.5))
    assert_almost_equal(document.number(document.at(root, 3)), Float64(-2.25))
    assert_almost_equal(document.number(document.at(root, 4)), Float64(1000))
    assert_almost_equal(document.number(document.at(root, 5)), Float64(0.01))
    assert_almost_equal(document.number(document.at(root, 6)), Float64(125))
    assert_equal(document.integer(document.at(root, 7)), 123456789)
    # A leading zero, a bare dot, a bare exponent and a plus are refused.
    assert_true(refused("01").find("byte") >= 0)
    _ = refused("1.")
    _ = refused(".5")
    _ = refused("1e")
    _ = refused("1e+")
    _ = refused("+1")
    _ = refused("-")
    # A number past a Float64 is refused rather than read as infinity.
    _ = refused("1e400")
    # A fraction is not an integer.
    var half = parse_json("2.5")
    with assert_raises():
        _ = half.integer(half.root())
    var huge = parse_json("1e17")
    with assert_raises():
        _ = huge.integer(huge.root())


def test_a_text_that_bends_the_grammar_is_refused_where_it_bent() raises:
    assert_equal(refused(""), "JSON at byte 0: expected a value, found the end")
    assert_equal(refused("{"), "JSON at byte 1: expected a key in quotes")
    assert_equal(refused("[1,]"), "JSON at byte 3: expected a value")
    assert_equal(refused('{"a" 1}'), "JSON at byte 5: expected ':'")
    assert_equal(
        refused('{"a": 1,}'), "JSON at byte 8: expected a key in quotes"
    )
    assert_equal(refused("[1 2]"), "JSON at byte 3: expected ',' or ']'")
    assert_equal(
        refused('{"a": 1 "b": 2}'), "JSON at byte 8: expected ',' or '}'"
    )
    assert_equal(refused("[1] x"), "JSON at byte 4: text after the root value")
    assert_equal(refused("tru"), "JSON at byte 0: expected true")
    assert_equal(refused("nul"), "JSON at byte 0: expected null")
    assert_equal(refused("fals"), "JSON at byte 0: expected false")
    assert_equal(refused("'a'"), "JSON at byte 0: expected a value")
    assert_equal(refused('"abc'), "JSON at byte 4: unterminated string")
    assert_equal(
        refused('"a\nb"'), "JSON at byte 3: a control byte inside a string"
    )
    assert_equal(refused('"\\x"'), "JSON at byte 3: unknown escape")
    assert_equal(refused('"\\u12"'), "JSON at byte 5: expected a hex digit")
    assert_equal(refused('"\\ud83d"'), "JSON at byte 7: a lone high surrogate")
    assert_equal(refused('"\\ud83dx"'), "JSON at byte 7: a lone high surrogate")
    assert_equal(
        refused('"\\ud83d\\n"'), "JSON at byte 8: a lone high surrogate"
    )
    assert_equal(
        refused('"\\ud83d\\u0041"'), "JSON at byte 13: a lone high surrogate"
    )
    assert_equal(refused('"\\ude00"'), "JSON at byte 7: a lone low surrogate")
    assert_equal(refused("{1: 2}"), "JSON at byte 1: expected a key in quotes")
    assert_equal(
        refused("[1,"), "JSON at byte 3: expected a value, found the end"
    )
    # Nesting past the limit is refused rather than read on a stack that
    # has no more room; nesting at the limit is read.
    var opened = String()
    var closed = String()
    for _ in range(MAX_DEPTH + 1):
        opened += "["
        closed += "]"
    _ = parse_json(opened + closed)
    assert_equal(
        refused("[" + opened + closed + "]").find("nested too deep") >= 0, True
    )


def test_a_node_of_the_wrong_kind_is_refused_by_each_accessor() raises:
    var document = parse_json('{"n": 1, "s": "x", "b": true, "a": [1]}')
    var root = document.root()
    var n = document.get(root, "n")
    var s = document.get(root, "s")
    var b = document.get(root, "b")
    var a = document.get(root, "a")
    with assert_raises():
        _ = document.number(s)
    with assert_raises():
        _ = document.integer(s)
    with assert_raises():
        _ = document.string(n)
    with assert_raises():
        _ = document.boolean(n)
    with assert_raises():
        _ = document.length(n)
    with assert_raises():
        _ = document.get(a, "k")
    with assert_raises():
        _ = document.has(n, "k")
    with assert_raises():
        _ = document.key(a, 0)
    with assert_raises():
        _ = document.key(root, 9)
    with assert_raises():
        _ = document.key(root, -1)
    with assert_raises():
        _ = document.at(n, 0)
    with assert_raises():
        _ = document.at(a, 1)
    with assert_raises():
        _ = document.at(a, -1)
    with assert_raises():
        _ = document.kind(99)
    with assert_raises():
        _ = document.kind(-1)
    with assert_raises():
        _ = document.is_null(99)
    assert_equal(document.length(a), 1)
    assert_true(document.boolean(b))
    var empty = JsonDocument()
    with assert_raises():
        _ = empty.kind(empty.root())


def test_the_edges_of_every_check_are_reached() raises:
    # A large negative number is not an integer either; tabs and carriage
    # returns are whitespace; a hex digit past f or F is refused; a low
    # surrogate past its range, and a private-use point just past the
    # surrogates, which is a plain three-byte character.
    var big = parse_json("-1e17")
    with assert_raises():
        _ = big.integer(big.root())
    var spaced = parse_json("\t[\r1,\t2\r]\t")
    assert_equal(spaced.length(spaced.root()), 2)
    _ = refused('"\\u00g1"')
    _ = refused('"\\u00G1"')
    _ = refused('"\\ud83d\\ue000"')
    var private = parse_json('"\\ue000"')
    var got = List[UInt8]()
    for byte in private.string(private.root()).as_bytes():
        got.append(byte)
    assert_equal(len(got), 3)
    assert_equal(got[0], UInt8(0xEE))
    assert_equal(got[1], UInt8(0x80))
    assert_equal(got[2], UInt8(0x80))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
