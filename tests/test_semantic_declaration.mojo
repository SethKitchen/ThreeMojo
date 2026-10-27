# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A semantic declaration drops postfix move sigils and keeps the function."""

from std.testing import TestSuite, assert_raises, assert_true

from tests._python_tokens import semantic_declaration


def test_a_semantic_declaration_drops_move_sigils() raises:
    """A `^` before a comma or a parenthesis is removed."""
    var source = (
        "def keep():\n    return 1\n"
        "def f(item: Int):\n    return g(item^)\n"
        "def after():\n    return 2\n"
    )
    var text = semantic_declaration(source, "f")
    assert_true(text.find("def f") >= 0)
    assert_true(text.find("g ( item )") >= 0)
    assert_true(text.find("item^") < 0)
    assert_true(text.find("def keep") < 0)
    assert_true(text.find("def after") < 0)


def test_a_bad_move_sigil_is_refused() raises:
    """A `^` that is not a postfix move is refused."""
    with assert_raises(contains="unsupported move-token placement"):
        _ = semantic_declaration("def f():\n    return x^ + 1\n", "f")


def main() raises:
    """Run the semantic declaration tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
