# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The live lane-center edges stay checked."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._lane_center_edges import lane_center_edges


def _text() raises -> String:
    """Return the lane-refinement module.

    Returns:
        The module text.

    Raises:
        Error: The file is unreadable.
    """
    return Path("extensions/carla/lane_refinement.mojo").read_text()


def test_the_live_lane_center_edges_hold() raises:
    """The memos, grouped caller, support call, and cache lifetime stay."""
    var source = _text()
    lane_center_edges(source)
    lane_center_edges(source + "\n# reviewed\n")


def test_a_changed_lane_center_edge_is_refused() raises:
    """A changed memo, caller, support call, or cache field is refused."""
    var source = _text()
    with assert_raises(
        contains=(
            "optional runtime contract: exact expansion memo lifetime is one "
            "search invocation"
        )
    ):
        lane_center_edges(
            source.replace(
                "var cached_fast: Optional[Tuple[UInt64, UInt64, _Jet]]",
                "var cached_fast: Optional[_Jet]",
            )
        )
    with assert_raises(
        contains=(
            "optional runtime contract: exact station/scale proof expansion "
            "memo and fresh fallback"
        )
    ):
        lane_center_edges(
            source.replace(
                "fast_center = _try_proof_expansion_jet(",
                "fast_center = _proof_expansion_jet(",
            )
        )
    with assert_raises(
        contains=(
            "optional runtime contract: exact station/scale translated "
            "expansion memo and fresh fallback"
        )
    ):
        lane_center_edges(
            source.replace(
                "center = _expansion_distance_jet(",
                "center = _distance_jet(",
            )
        )
    with assert_raises(
        contains=(
            "optional runtime contract: grouped caller must retain recheck "
            "and prepaid original fallback"
        )
    ):
        lane_center_edges(
            source.replace(
                "if max_nodes - nodes >= 2:", "if max_nodes - nodes >= 3:"
            )
        )
    with assert_raises(
        contains=(
            "optional runtime contract: support receives same ideal and "
            "actual witness"
        )
    ):
        lane_center_edges(
            source.replace(
                (
                    "_minimizer_support(\n                domain, center,"
                    " center_s, best, cell.low, cell.high\n            )"
                ),
                (
                    "_minimizer_support(\n                domain, center,"
                    " center_s, best, cell.high, cell.low\n            )"
                ),
            )
        )


def main() raises:
    """Run the lane-center edge tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
