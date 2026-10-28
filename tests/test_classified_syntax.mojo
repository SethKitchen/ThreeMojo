# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A syntax failure is classified before the Python parser fallback."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._python_json import PyJson
from tools.carla_cleanup_gate import classified_syntax_json


def test_an_ambiguous_generic_keeps_its_message() raises:
    """A repeated generic is refused after the syntax check."""
    with assert_raises(contains="ambiguous generic declaration"):
        _ = classified_syntax_json(
            "def f[T]():\n    pass\ndef f[U]():\n    pass\n"
        )


def test_another_token_failure_falls_back() raises:
    """A non-generic token failure asks the Python parser to continue."""
    var doc = PyJson.parse(
        classified_syntax_json("def f():\n    pass\n  pass\n")
    )
    assert_equal(doc.flag(doc.at(doc.root, "fallback")), True)


def test_a_plain_function_keeps_its_python_source() raises:
    """A plain function returns source and generic metadata."""
    var doc = PyJson.parse(classified_syntax_json("def f():\n    return 1\n"))
    assert_equal(doc.text(doc.at(doc.root, "source")).find("def f") >= 0, True)


def main() raises:
    """Run the classified syntax tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
