# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The JSON tree of the ported tools keeps Python's ints and `json.dumps`
options.

Every expected text here is what CPython 3.12 gives for the same value:
`int(text)`, `float(value)` or `json.dumps` with the same options.
"""

from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from tools._json_tree import JsonTree, canonical_integer, equal


def test_int_text_reads_as_python_int_reads_it() raises:
    assert_equal(canonical_integer(" 0123 "), "123")
    assert_equal(canonical_integer("-0"), "0")
    assert_equal(canonical_integer("+1_000"), "1000")
    assert_equal(canonical_integer("-0_7"), "-7")
    var refused: List[String] = ["", "-", "_1", "1_", "1__0", "1 2"]
    for text in refused:
        with assert_raises(
            contains="invalid literal for int() with base 10: '" + text + "'"
        ):
            _ = canonical_integer(text)
    with assert_raises(contains='with base 10: "\'q"'):
        _ = canonical_integer("'q")
    with assert_raises(contains="with base 10: 'a\\'\"'"):
        _ = canonical_integer("a'\"")
    with assert_raises(contains="with base 10: 'a\\\\b'"):
        _ = canonical_integer("a\\b")


def test_an_int_outside_64_bits_keeps_its_digits() raises:
    var tree = JsonTree()
    var hash = tree.integer_text("18446744073709551615")
    var largest = tree.integer_text(" 9223372036854775807 ")
    assert_true(tree.is_int(hash))
    assert_equal(tree.dumps(hash), "18446744073709551615")
    assert_equal(tree.value(hash), 18446744073709551616.0)
    assert_true(tree.truthy(hash))
    assert_equal(tree.int_value(largest), 9223372036854775807)
    with assert_raises(
        contains="integer too large for this tool: 18446744073709551615"
    ):
        _ = tree.int_value(hash)
    with assert_raises(contains="invalid literal for int()"):
        _ = tree.integer_text("0x10")


def test_parsed_ints_outside_64_bits_compare_and_copy_exactly() raises:
    var text = String(
        "[18446744073709551615, -18446744073709551617,"
        " 9223372036854775807, -9223372036854775808, 0]"
    )
    var tree = JsonTree()
    var parsed = tree.parse(text)
    assert_equal(tree.dumps(parsed, False), text)
    var hash = tree.integer_text("18446744073709551615")
    assert_true(tree.equal(tree.at(parsed, 0), hash))
    assert_false(tree.equal(tree.at(parsed, 1), hash))
    assert_false(tree.equal(tree.at(parsed, 4), hash))
    assert_false(tree.equal(tree.boolean(False), hash))
    assert_true(
        tree.equal(tree.at(parsed, 2), tree.integer(9223372036854775807))
    )
    assert_equal(tree.int_value(tree.at(parsed, 3)), -9223372036854775808)
    assert_equal(tree.value(tree.at(parsed, 1)), -18446744073709551616.0)
    var copy = tree.clone(parsed)
    assert_true(tree.equal(copy, parsed))
    var other = JsonTree()
    var adopted = other.adopt(tree, parsed)
    assert_true(equal(other, adopted, tree, parsed))
    assert_equal(other.dumps(adopted, False), text)


def test_dumps_sorts_keys_and_drops_spaces_as_python_does() raises:
    var tree = JsonTree()
    var root = tree.parse(
        '{"b": [1, {"z": 0, "a": 1}], "é": 2, "Z": 3, "a": []}'
    )
    assert_equal(
        tree.dumps(root, False),
        '{"b": [1, {"z": 0, "a": 1}], "\\u00e9": 2, "Z": 3, "a": []}',
    )
    assert_equal(
        tree.dumps(root, False, sort_keys=True),
        '{"Z": 3, "a": [], "b": [1, {"a": 1, "z": 0}], "\\u00e9": 2}',
    )
    assert_equal(
        tree.dumps(root, False, sort_keys=True, spaces=False),
        '{"Z":3,"a":[],"b":[1,{"a":1,"z":0}],"\\u00e9":2}',
    )
    assert_equal(
        tree.dumps(root, sort_keys=True),
        (
            '{\n  "Z": 3,\n  "a": [],\n  "b": [\n    1,\n    {\n      "a": 1,\n'
            '      "z": 0\n    }\n  ],\n  "\\u00e9": 2\n}'
        ),
    )
    assert_equal(
        tree.dumps(root, spaces=False),
        (
            '{\n  "b":[\n    1,\n    {\n      "z":0,\n      "a":1\n    }\n '
            ' ],\n  "\\u00e9":2,\n  "Z":3,\n  "a":[]\n}'
        ),
    )
    assert_equal(tree.dumps(tree.integers([3, -1]), False), "[3, -1]")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
