# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""One group of semantic declarations drops move sigils together."""

from std.testing import TestSuite, assert_raises, assert_true

from tools._python_json import PyJson
from tools._semantic_declarations import semantic_declarations


def _payload() raises -> String:
    """Return two function pins from one module.

    Returns:
        A JSON list.

    Raises:
        Error: The payload cannot be written.
    """
    var source = (
        "def keep():\n    return 1\n"
        "def f(item: Int):\n    return g(item^)\n"
        "def after():\n    return 2\n"
    )
    var doc = PyJson()
    var rows = doc.new_list()
    var first = doc.new_dict()
    doc.set(first, "key", doc.new_str("first"))
    doc.set(first, "name", doc.new_str("f"))
    doc.set(first, "source", doc.new_str(source))
    doc.append(rows, first)
    var second = doc.new_dict()
    doc.set(second, "key", doc.new_str("second"))
    doc.set(second, "name", doc.new_str("after"))
    doc.set(second, "source", doc.new_str(source))
    doc.append(rows, second)
    doc.root = rows
    return doc.dumps()


def test_two_semantic_declarations_drop_move_sigils() raises:
    """Both functions come back, and the move sigil is gone."""
    var result = PyJson.parse(semantic_declarations(_payload()))
    var first = result.text(result.at(result.root, "first"))
    var second = result.text(result.at(result.root, "second"))
    assert_true(first.find("g ( item )") >= 0)
    assert_true(first.find("item^") < 0)
    assert_true(first.find("def keep") < 0)
    assert_true(second.find("return 2") >= 0)
    assert_true(second.find("def f") < 0)


def test_the_first_missing_declaration_is_reported() raises:
    """A later function does not hide the first missing name."""
    var payload = _payload().replace('"name":"f"', '"name":"missing"')
    with assert_raises(
        contains="missing or ambiguous actual guard declaration: missing"
    ):
        _ = semantic_declarations(payload)


def main() raises:
    """Run the semantic declaration batch tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
