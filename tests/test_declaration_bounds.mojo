# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A declaration span is JSON with its text and line numbers."""

from std.testing import TestSuite, assert_equal, assert_raises

from tests._python_tokens import declaration_bounds_json


def test_a_declaration_span_keeps_its_text_and_lines() raises:
    """The first function occupies lines 0 through 3, including its blank line.
    """
    var source = "def first():\n    return 1\n\n"
    assert_equal(
        declaration_bounds_json(source, "first", List[String]()),
        '{"first":0,"last":3,"text":"def first():\\n    return 1\\n\\n"}',
    )
    var quoted = 'def first():\n    return "hi"\n'
    assert_equal(
        declaration_bounds_json(quoted, "first", List[String]()),
        '{"first":0,"last":2,"text":"def first():\\n    return \\"hi\\"\\n"}',
    )


def test_a_missing_declaration_is_refused() raises:
    """A name that is not declared does not invent a span."""
    with assert_raises(
        contains="missing or ambiguous actual guard declaration: absent"
    ):
        _ = declaration_bounds_json(
            "def first():\n    return 1\n", "absent", List[String]()
        )


def main() raises:
    """Run the declaration span tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
