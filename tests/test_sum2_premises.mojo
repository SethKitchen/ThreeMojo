# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reviewed Sum2 premises stay in the live source modules."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tests._python_tokens import token_sha256
from tools._sha256 import sha256_hex


def _cases(mut modules: List[String], mut premises: List[String]):
    """Fill the reviewed Sum2 premises.

    Args:
        modules: The module names, without the `.mojo` suffix.
        premises: The premise text in each module.
    """
    modules.append("curve_sum2")
    premises.append("high - total")
    modules.append("curve_sum2")
    premises.append("total_error + term_error")
    modules.append("curve_sum2")
    premises.append("correction + residual")
    modules.append("curve_sum2")
    premises.append("correction + residual")
    modules.append("curve_sum2")
    premises.append("(high, correction + residual)")
    modules.append("curve_sum2")
    premises.append("@no_inline\n")
    modules.append("curve_sum2")
    premises.append("count < 1")
    modules.append("curve_sum2")
    premises.append("count > 1073741824")
    modules.append("curve_sum2")
    premises.append("not isfinite(magnitude)")
    modules.append("curve_sum2")
    premises.append("magnitude < 0.0")
    modules.append("curve_sum2")
    premises.append("8.452712498170644e270")
    modules.append("curve_sum2")
    premises.append("not isfinite(inherited)")
    modules.append("curve_sum2")
    premises.append("inherited < 0.0")
    modules.append("curve_sum2")
    premises.append("if magnitude == 0.0:\n        return inherited")
    modules.append("curve_sum2")
    premises.append("if count == 1:\n        return inherited")
    modules.append("curve_sum2")
    premises.append("Float64(count - 1)")
    modules.append("curve_sum2")
    premises.append("_Interval.point(1.0) - nu")
    modules.append("curve_sum2")
    premises.append("gamma * gamma")
    modules.append("curve_sum2")
    premises.append("(u + gamma * gamma)")
    modules.append("curve_sum2")
    premises.append("_Interval.point(inherited)\n        +")
    modules.append("curve_sum2")
    premises.append("    ).high")
    modules.append("lane_geometry")
    premises.append("import _sum2_update")
    modules.append("lane_geometry")
    premises.append("    var x = Float64(0.0)")
    modules.append("lane_geometry")
    premises.append("var x_correction = Float64(0.0)")
    modules.append("lane_geometry")
    premises.append("var x_correction = Float64(0.0)")
    modules.append("lane_geometry")
    premises.append("        var start = step * Float64(piece)")
    modules.append("lane_geometry")
    premises.append("x_correction = next_x[1]")
    modules.append("lane_geometry")
    premises.append("y = next_y[0]")
    modules.append("lane_geometry")
    premises.append("geometry.x + (x + x_correction)")
    modules.append("lane_geometry")
    premises.append("geometry.x + (x + x_correction)")
    modules.append("curve_bounds")
    premises.append("x_inherited.high, 5 * pieces")
    modules.append("curve_bounds")
    premises.append("_Interval.point(term_x.error)")
    modules.append("curve_bounds")
    premises.append(
        "_Interval.point(\n                term_x.rounded_value().magnitude()\n"
        "            )"
    )
    modules.append("curve_bounds")
    premises.append("term_x.rounded_value().magnitude()")
    modules.append("curve_bounds")
    premises.append("x_magnitude.high, x_inherited.high")
    modules.append("curve_bounds")
    premises.append("    x.error = _sum2_error")
    modules.append("curve_bounds")
    premises.append("    x.error = _sum2_error")
    modules.append("curve_bounds")
    premises.append("    x.error = _sum2_error")
    modules.append("curve_bounds")
    premises.append("    x.error = _sum2_error")
    modules.append("curve_bounds")
    premises.append("            x = x + term_x")
    modules.append("curve_bounds")
    premises.append("            x = x + term_x")
    modules.append("curve_bounds")
    premises.append("        while i < 5:")
    modules.append("curve_bounds")
    premises.append("- Expression.constant(Float64(translation.x))")
    modules.append("spiral_roundoff_proof")
    premises.append("_sum2_error(absolute_sum.high, inherited.high, count)")
    modules.append("spiral_roundoff_proof")
    premises.append("n * _Interval.point(term.error)")
    modules.append("spiral_roundoff_proof")
    premises.append("_ValueJet.constant(origin) + accumulated")
    modules.append("spiral_roundoff_proof")
    premises.append("count > 320")
    modules.append("spiral_roundoff_proof")
    premises.append("geometry.heading != 0.0")
    modules.append("spiral_roundoff_proof")
    premises.append("domain.low <= 0.0")


def _replace_first(text: String, before: String, after: String) -> String:
    """Replace the first `before`.

    Args:
        text: The source.
        before: The premise.
        after: The replacement.

    Returns:
        The source with that premise replaced.
    """
    var at = text.find(before)
    var head = String(text[byte=:at])
    var tail = String(text[byte = at + before.byte_length() :])
    return head + after + tail


def test_sum2_premises_stay_in_the_live_modules() raises:
    """Every reviewed Sum2 premise still occurs, and an edit changes its digest.
    """
    var modules = List[String]()
    var premises = List[String]()
    _cases(modules, premises)
    assert_equal(len(modules), 49)
    for index in range(len(modules)):
        var path = "extensions/carla/" + modules[index] + ".mojo"
        var text = Path(path).read_text()
        assert_true(text.find(premises[index]) >= 0)
        var changed = _replace_first(text, premises[index], "False")
        assert_true(
            sha256_hex(changed.as_bytes()) != sha256_hex(text.as_bytes())
        )


def test_helper_whitespace_keeps_tokens_and_shadows_change_the_digest() raises:
    """A wider definition keeps its tokens, and a helper shadow changes the digest.
    """
    var bounds = Path("extensions/carla/curve_bounds.mojo").read_text()
    var interval = Path("extensions/carla/curve_interval.mojo").read_text()
    var spaced_bounds = _replace_first(
        bounds, "def _spiral_expression[", "def  _spiral_expression["
    )
    var spaced_interval = _replace_first(
        interval, "def _stored_half[", "def  _stored_half["
    )
    assert_equal(token_sha256(spaced_bounds), token_sha256(bounds))
    assert_equal(token_sha256(spaced_interval), token_sha256(interval))
    assert_true(
        sha256_hex(spaced_bounds.as_bytes()) != sha256_hex(bounds.as_bytes())
    )
    var shadows = List[String]()
    shadows.append("\n_stored_half = other_callable\n")
    shadows.append(
        "\ndef _stored_half[derivatives: Bool](value:"
        " _JetExpression[derivatives]) -> _JetExpression[derivatives]:\n   "
        " return value\n"
    )
    shadows.append("\nstruct _stored_half:\n    pass\n")
    shadows.append("\nimport other as _sum2_error\n")
    shadows.append("\nfrom other import *\n")
    for shadow in shadows:
        var changed = bounds + shadow
        assert_true(
            sha256_hex(changed.as_bytes()) != sha256_hex(bounds.as_bytes())
        )
    var lane = Path("extensions/carla/lane_geometry.mojo").read_text()
    var aliased = lane + "\nimport other as _sum2_update\n"
    assert_true(sha256_hex(aliased.as_bytes()) != sha256_hex(lane.as_bytes()))
    var redirected = _replace_first(
        bounds,
        "from extensions.carla.curve_interval import (",
        "from unexpected.curve_interval import (",
    )
    assert_true(
        sha256_hex(redirected.as_bytes()) != sha256_hex(bounds.as_bytes())
    )


def main() raises:
    """Run the Sum2 premise tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
