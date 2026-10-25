# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The sampled qualifier pins stay checked."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tests._winner_pin_predecessor import (
    restored_count_bounds,
    restored_winner_pins,
)
from tools.sampled_qualifier_gate import sampled_qualifier_gate


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
    """Return the restored lane-value source.

    Returns:
        The winner source.

    Raises:
        Error: The restoration failed.
    """
    var paths = List[String]()
    var texts = List[String]()
    restored_winner_pins(paths, texts)
    var found = String("")
    var index = 0
    while index < len(paths):
        if paths[index] == "extensions/carla/lane_value_bounds.mojo":
            found = String(texts[index])
        index += 1
    return found^


def test_the_qualifier_gate_holds() raises:
    """The four qualifier pins match the reviewed sources."""
    var bounds = restored_count_bounds()
    var trig = _text("extensions/carla/curve_trig.mojo")
    var interval = _text("extensions/carla/curve_interval.mojo")
    var lane = _lane()
    sampled_qualifier_gate(bounds, trig, interval, lane)
    sampled_qualifier_gate(
        bounds + "\n# reviewed\n",
        trig.replace(
            "comptime _PHASE_LIMIT = Float64(1048576.0)\n",
            "# reviewed\ncomptime _PHASE_LIMIT = Float64(1048576.0)\n",
        ),
        interval,
        lane,
    )


def test_a_changed_qualifier_is_refused() raises:
    """A moved qualifier in any of the four sources is refused."""
    var bounds = restored_count_bounds()
    var trig = _text("extensions/carla/curve_trig.mojo")
    var interval = _text("extensions/carla/curve_interval.mojo")
    var lane = _lane()
    with assert_raises(
        contains="lexical qualifier/specialization changed: curve_bounds.mojo"
    ):
        sampled_qualifier_gate(
            _text("extensions/carla/curve_bounds.mojo"), trig, interval, lane
        )
    with assert_raises(
        contains="lexical qualifier/specialization changed: curve_trig.mojo"
    ):
        sampled_qualifier_gate(
            bounds,
            trig.replace(
                "comptime _PHASE_LIMIT = Float64(1048576.0)\n",
                "out kept = 0\ncomptime _PHASE_LIMIT = Float64(1048576.0)\n",
            ),
            interval,
            lane,
        )
    with assert_raises(
        contains="lexical qualifier/specialization changed: curve_interval.mojo"
    ):
        sampled_qualifier_gate(
            bounds,
            trig,
            interval.replace(
                "from std.math import fma, inf, isfinite, isnan, sqrt\n",
                (
                    "var extra = 0\nfrom std.math import fma, inf, isfinite,"
                    " isnan, sqrt\n"
                ),
            ),
            lane,
        )
    with assert_raises(
        contains=(
            "lexical qualifier/specialization changed: lane_value_bounds.mojo"
        )
    ):
        sampled_qualifier_gate(
            bounds,
            trig,
            interval,
            _text("extensions/carla/lane_value_bounds.mojo"),
        )


def main() raises:
    """Run the sampled qualifier tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
