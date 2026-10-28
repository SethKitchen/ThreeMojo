# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Copied helpers are classified after the helper names."""

from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tools._projection_syntax import append_helper_syntax
from tools._python_json import PyJson
from tools.carla_sampled_projection import project_syntax_after_names


def test_an_earlier_syntax_error_stays_ahead_of_the_next_helper() raises:
    """The first helper's syntax error is kept, and the next helper is classified.
    """
    var projected = (
        '{"record":{"helpers":{'
        + '"m":"def f[T: Int]():\\n    return 1\\ndef f[T: Int]():\\n    '
        + 'return 2\\n",'
        + '"a":"def kept():\\n    return 1\\n"}}}'
    )
    var doc = PyJson.parse(append_helper_syntax(projected))
    var syntax = doc.at(doc.root, "syntax")
    assert_equal(doc.length(syntax), 2)
    var failed = doc.item(syntax, 0)
    assert_equal(
        doc.text(doc.at(failed, "error")), "ambiguous generic declaration"
    )
    var clean = doc.item(syntax, 1)
    assert_true(doc.text(doc.at(clean, "source")).find("def kept") >= 0)
    assert_equal(doc.key(clean, doc.length(clean) - 1), "words")
    var helpers = doc.at(doc.at(doc.root, "record"), "helpers")
    assert_true(doc.text(doc.at(helpers, "a")).find("def kept") >= 0)


def test_a_bad_import_fails_before_classification() raises:
    """A bad lane-value module fails before helper syntax is classified."""
    with assert_raises(contains="sampled imports:"):
        _ = project_syntax_after_names('{"target":"nope"}')


def main() raises:
    """Run the copied-helper syntax tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
