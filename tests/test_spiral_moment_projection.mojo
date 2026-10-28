# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The stored-half helper keeps its reviewed projection."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._spiral_moment_projection import stored_half_projection


def _helper() raises -> String:
    """Return the live stored-half helper.

    Returns:
        The source from `def _stored_half[`.

    Raises:
        Error: The declaration is absent.
    """
    var text = Path("extensions/carla/curve_interval.mojo").read_text()
    var marker = "def _stored_half["
    var at = text.find(marker)
    if at < 0:
        raise Error("missing helper")
    var tail = text[byte=at:]
    return String(tail)


def test_the_live_helper_is_admitted() raises:
    """The live stored-half helper keeps the reviewed shape."""
    stored_half_projection(_helper())


def test_a_changed_helper_is_refused() raises:
    """A changed declaration, product, return, field, or use is refused."""
    var helper = _helper()
    with assert_raises(contains="unsupported ideal function declaration"):
        stored_half_projection("@no_inline\n" + helper)
    with assert_raises(contains="declaration or decorator changed"):
        stored_half_projection(
            helper.replace(
                "value: _JetExpression[derivatives]", "value: Float64"
            )
        )
    with assert_raises(contains="initial expression changed"):
        stored_half_projection(
            helper.replace(
                (
                    "var result = value *"
                    " _JetExpression[derivatives].constant(0.5)"
                ),
                "var result = value",
            )
        )
    with assert_raises(contains="return changed"):
        stored_half_projection(helper.replace("return result", "return value"))
    with assert_raises(contains="result rebound"):
        stored_half_projection(
            helper.replace("var actual =", "result = 1\n    var actual =")
        )
    with assert_raises(contains="non-error result field changed"):
        stored_half_projection(
            helper.replace("result.error = (", "result.value = (")
        )
    with assert_raises(contains="result escapes"):
        stored_half_projection(
            helper.replace("var actual =", "f(result)\n    var actual =")
        )
    with assert_raises(contains="unapproved ideal helper result use"):
        stored_half_projection(
            helper.replace(
                "var actual =", "var alias = result\n    var actual ="
            )
        )
    with assert_raises(contains="unapproved ideal helper result use"):
        stored_half_projection(
            helper.replace("var actual =", "f(value=result)\n    var actual =")
        )
    with assert_raises(contains="unapproved ideal helper result use"):
        stored_half_projection(
            helper.replace(
                "var actual =", "result.some_method()\n    var actual ="
            )
        )
    with assert_raises(contains="unapproved ideal helper result use"):
        stored_half_projection(
            helper.replace(
                "var actual =", "result.value.low = 0.0\n    var actual ="
            )
        )


def main() raises:
    """Run the stored-half projection tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
