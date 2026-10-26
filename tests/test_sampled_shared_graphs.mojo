# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The trig and curve-bounds helpers keep the reviewed bridge graphs."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._python_json import loads
from tools.sampled_bounds_graph import reviewed_bounds_source
from tests._winner_pin_predecessor import restored_count_bounds
from tools.sampled_shared_graphs import sampled_shared_graphs, shared_bridges


def _bounds() raises -> String:
    """Return the reviewed curve-bounds source.

    Returns:
        The reviewed module.

    Raises:
        Error: The record cannot be read.
    """
    var doc = loads(
        Path(
            "tools/carla_lane_oracle/envelope-budget-contract.json"
        ).read_bytes()
    )
    return reviewed_bounds_source(
        restored_count_bounds(),
        doc.text(doc.at(doc.root, "before_complete_function")),
        doc.text(doc.at(doc.root, "after_complete_function")),
    )


def test_the_live_shared_bridges_hold() raises:
    """The fourteen shared function graphs match their pins."""
    sampled_shared_graphs(".")
    sampled_shared_graphs("./")
    sampled_shared_graphs("extensions/..")


def test_a_changed_trig_bridge_is_refused() raises:
    """A changed trig bridge is refused."""
    var trig = (
        Path("extensions/carla/curve_trig.mojo")
        .read_text()
        .replace(
            "def _sincos_jet(value: _Jet)", "def _sincos_jet(value: _ValueJet)"
        )
    )
    with assert_raises(
        contains=(
            "shared generic or full-Jet bridge changed: "
            + "curve_trig.mojo:_sincos_jet"
        )
    ):
        shared_bridges(trig, _bounds())


def test_a_changed_bounds_bridge_is_refused() raises:
    """A changed curve-bounds bridge is refused."""
    var bounds = _bounds().replace(
        "def _sample_index(geometry: RoadGeometry, d: Float64)",
        "def _sample_index(geometry: RoadGeometry, d: Int)",
    )
    var trig = Path("extensions/carla/curve_trig.mojo").read_text()
    with assert_raises(
        contains=(
            "shared generic or full-Jet bridge changed: "
            + "curve_bounds.mojo:_sample_index"
        )
    ):
        shared_bridges(trig, bounds)


def test_a_missing_bridge_is_refused() raises:
    """A missing shared function is refused."""
    var trig = (
        Path("extensions/carla/curve_trig.mojo")
        .read_text()
        .replace("def _uncertain(", "def _uncertain_value(")
    )
    with assert_raises(contains="missing or ambiguous function: _uncertain"):
        shared_bridges(trig, _bounds())


def main() raises:
    """Run the shared-bridge tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
