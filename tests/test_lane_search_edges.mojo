# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The live lane-search edges stay checked."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools.lane_search_edges import lane_search_edges


def _text() raises -> String:
    """Return the lane-refinement module.

    Returns:
        The module text.

    Raises:
        Error: The file is unreadable.
    """
    return Path("extensions/carla/lane_refinement.mojo").read_text()


def test_the_live_lane_search_edges_hold() raises:
    """The frontier loop, debit, producer, and dispatch setup stay in place."""
    var source = _text()
    lane_search_edges(source)
    lane_search_edges(source + "\n# reviewed\n")


def test_a_changed_lane_search_edge_is_refused() raises:
    """A moved debit, producer, cut, or dispatch edge is refused."""
    var source = _text()
    with assert_raises(
        contains=(
            "optional runtime contract: fresh cell producer must use "
            "current cell work"
        )
    ):
        lane_search_edges(
            source.replace(
                "var work = _reference_work(road, lo, hi)",
                "var work = _reference_work(road, lo, lo)",
            )
        )
    with assert_raises(
        contains=(
            "optional runtime contract: fresh current-cell producer must "
            "immediately follow original debit"
        )
    ):
        lane_search_edges(
            source.replace(
                "Lane refinement exhausted its quadrature work limit",
                "Lane refinement exhausted its quadrature budget",
            )
        )
    with assert_raises(
        contains=(
            "optional runtime contract: cut lifetime is one search invocation"
        )
    ):
        lane_search_edges(
            source.replace(
                (
                    "var sampled_cuts: Optional[Tuple[Float64, Float64, Int]] ="
                    " None"
                ),
                "var sampled_cuts: Optional[Tuple[Float64, Float64]] = None",
            )
        )
    with assert_raises(
        contains=(
            "optional runtime contract: incumbent is the validated actual "
            "certificate witness"
        )
    ):
        lane_search_edges(
            source.replace("var best = certificate.s", "var best = low")
        )
    with assert_raises(
        contains=(
            "optional runtime contract: depth refusal precedes dispatch setup"
        )
    ):
        lane_search_edges(
            source.replace(
                "Lane refinement exhausted its numerical accuracy limit",
                "Lane refinement exhausted its numerical accuracy budget",
            )
        )
    with assert_raises(
        contains=(
            "optional runtime contract: split predecessor preserves every "
            "stored owner station"
        )
    ):
        lane_search_edges(
            source.replace(
                "bitcast[DType.uint64](split_at) - UInt64(1)",
                "bitcast[DType.uint64](split_at) - UInt64(2)",
            )
        )


def main() raises:
    """Run the lane-search edge tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
