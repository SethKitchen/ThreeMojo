# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Every copied helper is classified before the Python comparison."""

from std.testing import TestSuite, assert_equal, assert_true

from tools._python_json import PyJson
from tools.carla_cleanup_gate import classified_syntax_all


def _sources(first: String, second: String) raises -> String:
    """Return two source texts.

    Args:
        first: The first source.
        second: The second source.

    Returns:
        A JSON list of those texts.

    Raises:
        Error: The list cannot be written.
    """
    var doc = PyJson()
    var rows = doc.new_list()
    doc.append(rows, doc.new_str(first))
    doc.append(rows, doc.new_str(second))
    doc.root = rows
    return doc.dumps()


def test_an_earlier_failure_stays_ahead_of_a_later_source() raises:
    """The first syntax failure is kept, and the next source is still classified.
    """
    var doc = PyJson.parse(
        classified_syntax_all(
            _sources(
                (
                    "def f[T: Int]():\n    return 1\ndef f[T: Int]():\n   "
                    " return 2\n"
                ),
                "def ok():\n    return 1\n",
            )
        )
    )
    assert_equal(doc.length(doc.root), 2)
    var failed = doc.item(doc.root, 0)
    assert_equal(
        doc.text(doc.at(failed, "error")), "ambiguous generic declaration"
    )
    var syntax = doc.item(doc.root, 1)
    assert_equal(doc.key(syntax, doc.length(syntax) - 1), "words")
    assert_true(doc.text(doc.at(syntax, "source")).find("def ok") >= 0)


def test_two_clean_helpers_keep_their_order() raises:
    """Both helpers are classified, and the first stays first."""
    var doc = PyJson.parse(
        classified_syntax_all(
            _sources("def ok():\n    return 1\n", "def also():\n    return 2\n")
        )
    )
    assert_equal(doc.length(doc.root), 2)
    var first = doc.item(doc.root, 0)
    var second = doc.item(doc.root, 1)
    assert_true(doc.text(doc.at(first, "source")).find("def ok") >= 0)
    assert_true(doc.text(doc.at(second, "source")).find("def also") >= 0)
    assert_equal(doc.key(first, doc.length(first) - 1), "words")
    assert_equal(doc.key(second, doc.length(second) - 1), "words")


def main() raises:
    """Run the copied-helper syntax tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
