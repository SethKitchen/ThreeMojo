# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The reviewed Sum2 caller graphs stay checked."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tests._border_pin_predecessor import restored_border_pins
from tools.sum2_caller_graphs import sum2_caller_graphs


def _text(path: String) raises -> String:
    """Return one module.

    Args:
        path: The repository path.

    Returns:
        The module text.

    Raises:
        Error: The file is unreadable.
    """
    return Path(path).read_text()


def _lane() raises -> String:
    """Return the reviewed lane-geometry source.

    Returns:
        The border source.

    Raises:
        Error: The restoration failed.
    """
    var paths = List[String]()
    var texts = List[String]()
    restored_border_pins(paths, texts)
    var found = String("")
    var index = 0
    while index < len(paths):
        if paths[index] == "extensions/carla/lane_geometry.mojo":
            found = String(texts[index])
        index += 1
    return found^


def _sum2() raises -> String:
    """Return the live Sum2 module.

    Returns:
        The module text.

    Raises:
        Error: The file is unreadable.
    """
    return _text("extensions/carla/curve_sum2.mojo")


def _roundoff() raises -> String:
    """Return the live roundoff module.

    Returns:
        The module text.

    Raises:
        Error: The file is unreadable.
    """
    return _text("extensions/carla/spiral_roundoff_proof.mojo")


def _predecessor() raises -> String:
    """Return the recorded roundoff predecessor.

    Returns:
        The predecessor module.

    Raises:
        Error: The file is unreadable.
    """
    return _text("tests/_reference_roundoff_selection.mojo")


def test_the_sum2_caller_graphs_hold() raises:
    """The recurrence, leaf, scalar spiral, envelope, and predecessor match."""
    var sum2 = _sum2()
    var lane = _lane()
    var roundoff = _roundoff()
    var predecessor = _predecessor()
    sum2_caller_graphs(sum2, lane, roundoff, predecessor)
    sum2_caller_graphs(sum2 + "\n# reviewed\n", lane, roundoff, predecessor)


def test_a_changed_sum2_caller_graph_is_refused() raises:
    """A changed recurrence, leaf, spiral, envelope, or predecessor is refused.
    """
    var sum2 = _sum2()
    var lane = _lane()
    var roundoff = _roundoff()
    var predecessor = _predecessor()
    with assert_raises(contains="Sum2 recurrence changed"):
        sum2_caller_graphs(
            sum2.replace("var high = total + term", "var high = total - term"),
            lane,
            roundoff,
            predecessor,
        )
    with assert_raises(contains="Sum2 checked arithmetic leaf changed"):
        sum2_caller_graphs(
            sum2.replace(
                "magnitude > 8.452712498170644e270", "magnitude > 1.0"
            ),
            lane,
            roundoff,
            predecessor,
        )
    with assert_raises(contains="scalar environment check moved"):
        sum2_caller_graphs(
            sum2,
            lane.replace(
                "    _require_sum2_environment()\n",
                "    _require_sum2_environment_other()\n",
            ),
            roundoff,
            predecessor,
        )
    with assert_raises(
        contains="Sum2 complete caller graph changed: _lane_spiral"
    ):
        sum2_caller_graphs(
            sum2,
            lane.replace(
                "return DirectedPoint(", "return DirectedPoint._from_si("
            ),
            roundoff,
            predecessor,
        )
    with assert_raises(
        contains="Sum2 complete caller graph changed: _sum2_envelope_error"
    ):
        sum2_caller_graphs(
            sum2,
            lane,
            roundoff.replace("count > 320", "count > 321"),
            predecessor,
        )
    with assert_raises(
        contains=(
            "Sum2 complete caller graph changed: _try_spiral_roundoff_envelope"
        )
    ):
        sum2_caller_graphs(
            sum2,
            lane,
            roundoff,
            predecessor.replace("pieces > 64", "pieces > 65"),
        )


def main() raises:
    """Run the Sum2 caller graph tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
