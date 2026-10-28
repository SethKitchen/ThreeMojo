# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The live ideal spiral keeps its reviewed statement layout."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises

from tools._python_json import PyJson
from tools._sha256 import sha256_hex
from tools._spiral_moment_graph import selected_block
from tools._spiral_moment_ideal import (
    ideal_spiral_layout,
    legacy_rate_half_commutations,
    require_legacy_rate_halves,
)


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


def _legacy() raises -> String:
    """Return the pinned legacy ideal spiral.

    Returns:
        The normalized legacy source.

    Raises:
        Error: The pin file is unreadable.
    """
    var text = Path(
        "tools/carla_lane_oracle/spiral-moment-pins.json"
    ).read_text()
    var doc = PyJson.parse(text)
    var projection = doc.at(doc.root, "ideal_projection")
    return doc.text(doc.at(projection, "legacy_normalized_source"))


def test_the_legacy_source_has_two_rate_halves() raises:
    """The legacy ideal source keeps two half-times-rate products."""
    var legacy = _legacy()
    assert_equal(
        sha256_hex(legacy.as_bytes()),
        "270a3cde3b012388ee8fcb6a4ecc59d837d1583f6c406f942ff98fdccd9f5733",
    )
    require_legacy_rate_halves(legacy)
    assert_equal(legacy_rate_half_commutations(legacy), 2)
    var removed = legacy.replace(
        "Expression.constant(0.5) * rate", "Expression.constant(0.5) * step"
    )
    with assert_raises(contains="exactly two historical rate-half"):
        require_legacy_rate_halves(removed)
    var added = legacy + "\nk0 + Expression.constant(0.5) * rate * d\n"
    with assert_raises(contains="exactly two historical rate-half"):
        require_legacy_rate_halves(added)
    assert_equal(
        legacy_rate_half_commutations(
            "k0 + rate * Expression.constant(0.5) * t\n"
        ),
        0,
    )


def main() raises:
    """Run the ideal spiral layout tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
