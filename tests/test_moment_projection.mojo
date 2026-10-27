# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The ideal half projection matches its reviewed record."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises

from tests._python_tokens import stored_half_tail
from tools._moment_projection import moment_projection
from tools._python_json import PyJson


def _payload(legacy: String, current: String, helper: String) raises -> String:
    """Return one projection payload.

    Args:
        legacy: The pinned spiral.
        current: The live spiral.
        helper: The stored-half source.

    Returns:
        A JSON object.

    Raises:
        Error: The payload cannot be written.
    """
    var doc = PyJson()
    var root = doc.new_dict()
    doc.set(root, "legacy", doc.new_str(legacy))
    doc.set(root, "current", doc.new_str(current))
    doc.set(root, "helper", doc.new_str(helper))
    doc.root = root
    return doc.dumps()


def test_a_changed_legacy_spiral_is_refused() raises:
    """A different legacy source fails before the helper is checked."""
    with assert_raises(contains="historical ideal source changed"):
        _ = moment_projection(_payload("def f():\n", "x", "y"))


def test_the_live_ideal_projection_matches() raises:
    """The pinned spiral and the live helper produce the reviewed record."""
    var pins = PyJson.parse(
        Path("tools/carla_lane_oracle/spiral-moment-pins.json").read_text()
    )
    var projection = pins.at(pins.root, "ideal_projection")
    var blocks = pins.at(pins.root, "blocks")
    var spiral = pins.at(blocks, "ideal_spiral")
    var helper = stored_half_tail(
        Path("extensions/carla/curve_interval.mojo").read_text()
    )
    var result = PyJson.parse(
        moment_projection(
            _payload(
                pins.text(pins.at(projection, "legacy_normalized_source")),
                pins.text(pins.at(spiral, "normalized_source")),
                helper,
            )
        )
    )
    assert_equal(result.text(result.at(result.root, "helper_projections")), "5")
    assert_equal(
        result.text(result.at(result.root, "rate_half_commutations")), "2"
    )
    assert_equal(
        result.text(result.at(result.root, "projected_ast_sha256")),
        "f0f94e038fd4a783b3ed400ffd32801ca0c3bdc54980e2c408d44f50211b9e06",
    )


def main() raises:
    """Run the ideal projection tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
