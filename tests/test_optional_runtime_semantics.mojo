# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The optional runtime source edges stay checked."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools.optional_runtime_semantics import optional_runtime_semantics


def _text(name: String) raises -> String:
    """Return one CARLA module.

    Args:
        name: The module stem.

    Returns:
        The module text.

    Raises:
        Error: The file is unreadable.
    """
    return Path("extensions/carla/" + name + ".mojo").read_text()


def _call(
    refinement: String,
    model: String,
    dispatch: String,
    lane: String,
    roundoff: String,
    support: String,
    map_source: String,
) raises:
    """Run the optional runtime check.

    Args:
        refinement: The lane-refinement module.
        model: The objective-model module.
        dispatch: The sample-dispatch module.
        lane: The grouped-lane module.
        roundoff: The grouped-roundoff module.
        support: The minimizer-support module.
        map_source: The map module.

    Raises:
        Error: An edge changed.
    """
    optional_runtime_semantics(
        refinement, model, dispatch, lane, roundoff, support, map_source
    )


def test_the_optional_runtime_edges_hold() raises:
    """The reviewed guards, rooms, debits, and fees stay in place."""
    var refinement = _text("lane_refinement")
    var model = _text("curve_objective_model")
    var dispatch = _text("curve_sample_dispatch")
    var lane = _text("spiral_grouped_lane")
    var roundoff = _text("spiral_grouped_roundoff_proof")
    var support = _text("curve_minimizer_support")
    var map_source = _text("map")
    _call(refinement, model, dispatch, lane, roundoff, support, map_source)
    _call(
        refinement + "\n# reviewed\n",
        model,
        dispatch,
        lane,
        roundoff,
        support,
        map_source,
    )


def test_a_changed_optional_runtime_edge_is_refused() raises:
    """A moved guard, debit, room, or fee is refused."""
    var refinement = _text("lane_refinement")
    var model = _text("curve_objective_model")
    var dispatch = _text("curve_sample_dispatch")
    var lane = _text("spiral_grouped_lane")
    var roundoff = _text("spiral_grouped_roundoff_proof")
    var support = _text("curve_minimizer_support")
    var map_source = _text("map")
    with assert_raises(
        contains=(
            "optional runtime contract: exact UInt64 pair helper comparison"
        )
    ):
        _call(
            refinement.replace(
                "SIMD[DType.uint64, 2](station, scale)",
                "SIMD[DType.uint64, 2](scale, station)",
            ),
            model,
            dispatch,
            lane,
            roundoff,
            support,
            map_source,
        )
    with assert_raises(
        contains=(
            "optional runtime contract: fresh invocation guard missing or "
            "moved: _try_grouped_lane_jet"
        )
    ):
        _call(
            refinement,
            model,
            dispatch,
            lane.replace(
                (
                    "    if not _sum2_supported_environment():\n        return"
                    " None\n"
                ),
                (
                    "    if not _sum2_supported_environment():\n        return"
                    " _unknown\n"
                ),
            ),
            roundoff,
            support,
            map_source,
        )
    with assert_raises(
        contains=(
            "optional runtime contract: atomic whole-count debit must "
            "precede both raw envelopes"
        )
    ):
        _call(
            refinement,
            model,
            dispatch,
            lane.replace("    terms += extra\n", "    terms += 0\n"),
            roundoff,
            support,
            map_source,
        )
    with assert_raises(
        contains=(
            "optional runtime contract: complete overflow-safe integer "
            "followup admission"
        )
    ):
        _call(
            refinement,
            model.replace("max_nodes - nodes >= 4", "max_nodes - nodes >= 5"),
            dispatch,
            lane,
            roundoff,
            support,
            map_source,
        )
    with assert_raises(
        contains="optional runtime contract: reviewed goal node fee"
    ):
        _call(
            refinement,
            model,
            dispatch,
            lane,
            roundoff,
            support,
            map_source.replace(
                "var fixed = 26 if goal else 20",
                "var fixed = 26 if goal else 21",
            ),
        )


def main() raises:
    """Run the optional runtime edge tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
