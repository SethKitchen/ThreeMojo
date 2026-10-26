# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The count-loop curve-bounds module keeps the reviewed reference graph."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tests._winner_pin_predecessor import restored_count_bounds
from tools._process import run_program
from tools._python_json import loads
from tools.sampled_bounds_graph import (
    reviewed_bounds_source,
    sampled_bounds_graph,
)


def _pair() raises -> Tuple[String, String]:
    """Return the live envelope helper pair.

    Returns:
        The historical helper and the reviewed successor.

    Raises:
        Error: The record cannot be read.
    """
    var doc = loads(
        Path(
            "tools/carla_lane_oracle/envelope-budget-contract.json"
        ).read_bytes()
    )
    return (
        doc.text(doc.at(doc.root, "before_complete_function")),
        doc.text(doc.at(doc.root, "after_complete_function")),
    )


def test_the_live_bounds_graph_holds() raises:
    """The reviewed curve-bounds graph matches the pin."""
    sampled_bounds_graph(".")
    sampled_bounds_graph("./")
    sampled_bounds_graph("extensions/..")


def test_a_changed_successor_is_refused() raises:
    """A changed envelope successor is refused."""
    var pair = _pair()
    var source = restored_count_bounds().replace(
        "terms += optional_work", "terms += optional_work + 1"
    )
    with assert_raises(contains="Envelope budget successor function changed"):
        _ = reviewed_bounds_source(source, pair[0], pair[1])


def test_an_extra_try_only_use_is_refused() raises:
    """An extra try-only use is refused."""
    var pair = _pair()
    var source = restored_count_bounds() + "\n# require_reuse\n"
    with assert_raises(contains="try-only flag has an unreviewed use"):
        _ = reviewed_bounds_source(source, pair[0], pair[1])


def test_a_changed_refusal_is_refused() raises:
    """A changed try-only refusal is refused."""
    var pair = _pair()
    var source = restored_count_bounds().replace(
        "elif require_reuse:", "elif require_reuse :"
    )
    with assert_raises(
        contains="try-only refusal missing from reuse/fallback edge"
    ):
        _ = reviewed_bounds_source(source, pair[0], pair[1])


def test_a_changed_parameter_is_refused() raises:
    """A changed try-only parameter is refused."""
    var pair = _pair()
    var source = restored_count_bounds().replace(
        "require_reuse: Bool = False", "require_reuse: Int = False"
    )
    with assert_raises(contains="try-only parameter changed"):
        _ = reviewed_bounds_source(source, pair[0], pair[1])


def test_a_changed_record_is_refused() raises:
    """A changed envelope record is refused."""
    var root = "/tmp/sampled-bounds-graph-record"
    var cleared = run_program(["rm", "-rf", root], 10.0)
    if cleared.status != 0:
        raise Error(cleared.output)
    var made = run_program(
        ["mkdir", "-p", root + "/tools/carla_lane_oracle"], 10.0
    )
    if made.status != 0:
        raise Error(made.output)
    var path = root + "/tools/carla_lane_oracle/envelope-budget-contract.json"
    Path(path).write_text(
        Path("tools/carla_lane_oracle/envelope-budget-contract.json")
        .read_text()
        .replace('"schema": 1', '"schema": 2')
    )
    with assert_raises(
        contains="Unreviewed envelope budget predecessor record"
    ):
        sampled_bounds_graph(root)


def main() raises:
    """Run the bounds-graph tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
