# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The live ideal spiral keeps its reviewed statement layout."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools.spiral_moment_graph import selected_block
from tools.spiral_moment_ideal import ideal_spiral_layout


def _block() raises -> String:
    """Return the live ideal spiral block.

    Returns:
        The normalized block.

    Raises:
        Error: The block is refused.
    """
    var bounds = Path("extensions/carla/curve_bounds.mojo").read_text()
    return selected_block(
        bounds, "def _spiral_expression[", "def _sample_index("
    )


def test_the_live_ideal_spiral_keeps_its_layout() raises:
    """The live ideal spiral keeps the reviewed statements and calls."""
    ideal_spiral_layout(_block())


def test_a_moved_ideal_statement_is_refused() raises:
    """A moved guard, declaration, term, or call is refused."""
    var block = _block()
    with assert_raises(contains="environment refusal changed"):
        ideal_spiral_layout(
            block.replace(
                "if not _sum2_supported_environment():", "if not other():"
            )
        )
    with assert_raises(contains="declarations reordered"):
        ideal_spiral_layout(
            block.replace(
                "var x_magnitude = _Interval.point(0.0)",
                "var y_magnitude = _Interval.point(0.0)",
            )
        )
    with assert_raises(contains="term definition moved"):
        ideal_spiral_layout(block.replace("trig[1]", "trig[2]"))
    with assert_raises(contains="term accumulation moved"):
        ideal_spiral_layout(block.replace("x = x + term_x", "x = x + term_y"))
    with assert_raises(contains="stored-half calls"):
        ideal_spiral_layout(
            block.replace("_stored_half(rate) * d", "_stored_half(d) * d")
        )


def main() raises:
    """Run the ideal spiral layout tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
