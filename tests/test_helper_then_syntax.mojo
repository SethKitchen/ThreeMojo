# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The stored helpers are checked before the lane-value syntax."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._python_json import PyJson
from tools.carla_sampled_text import helper_fields_then_syntax


def _helpers() -> String:
    """Return four stored helpers that do not read a derivative."""
    return (
        "def _without_derivatives():\n    return 1\n"
        + "def _stored_difference():\n    return 1\n"
        + "def _stored_blend_error():\n    return 1\n"
        + "def _stored_half():\n    return 1\n"
    )


def test_a_missing_helper_fails_before_the_syntax() raises:
    """A missing helper fails before an unclosed generic is prepared."""
    with assert_raises(
        contains="missing or ambiguous function: _without_derivatives"
    ):
        _ = helper_fields_then_syntax(
            "def main():\n    return 1\n",
            "def f[T:\n    return 1\n",
        )


def test_the_helpers_precede_the_lane_value_syntax() raises:
    """Four clean helpers return the prepared syntax of the target."""
    var doc = PyJson.parse(
        helper_fields_then_syntax(
            _helpers(),
            "def ok():\n    return 1\n",
        )
    )
    _source_keeps_ok(doc)
    assert_equal(doc.key(doc.root, doc.length(doc.root) - 1), "words")


def _source_keeps_ok(doc: PyJson) raises:
    """Require the prepared source to keep the target function.

    Args:
        doc: The syntax JSON.

    Raises:
        Error: The source text is missing.
    """
    if doc.text(doc.at(doc.root, "source")).find("def ok") < 0:
        raise Error("prepared source lost the target function")


def main() raises:
    """Run the helper and syntax tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
