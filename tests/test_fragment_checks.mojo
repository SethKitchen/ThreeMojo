# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Fragment checks keep their order and their messages."""

from std.testing import TestSuite, assert_raises

from tests._python_expr import require_fragment_checks


def _check(fragment: String, expected: String, label: String) -> String:
    """Return one contains check.

    Args:
        fragment: The statement text.
        expected: The required count, as JSON.
        label: The failure text.

    Returns:
        One JSON object without braces.
    """
    return (
        '"source":"def show():\\n    var best ='
        ' certificate.s\\n","name":"show",'
        + '"kind":"contains","fragment":"'
        + fragment
        + '","label":"'
        + label
        + '","expected":'
        + expected
    )


def test_fragment_checks_hold_in_order() raises:
    """An empty list and a matching count are accepted."""
    require_fragment_checks("[]")
    require_fragment_checks(
        "[{" + _check("var best = certificate.s", "1", "kept") + "}]"
    )
    require_fragment_checks(
        "[{"
        + _check("var best = certificate.s", "1", "kept")
        + ',"call":"other"}]'
    )


def test_a_changed_fragment_count_is_refused() raises:
    """The first differing count keeps its message."""
    with assert_raises(contains="optional runtime contract: missing best"):
        require_fragment_checks(
            "[{"
            + _check("var best = certificate.s", "1", "kept")
            + "},{"
            + _check("var other = 1", "1", "missing best")
            + "}]"
        )
    with assert_raises(contains="optional runtime contract: custom refusal"):
        require_fragment_checks(
            "[{"
            + _check("var other = 1", "1", "missing best")
            + ',"message":"custom refusal"}]'
        )
    with assert_raises(contains="invalid checker fragment: bad"):
        require_fragment_checks(
            '[{"source":"def show():\\n   '
            ' pass\\n","name":"show","kind":"nope",'
            + '"fragment":"pass","label":"bad","expected":1}]'
        )


def main() raises:
    """Run the fragment-check tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
