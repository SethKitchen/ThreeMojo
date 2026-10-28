# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Import scopes are checked before the rounded lane minima."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._python_json import PyJson
from tools.carla_singleton_gate import (
    graphs_then_minima,
    restored_scope_then_minima,
    scopes_then_minima,
)


def test_missing_scope_texts_fail_before_the_minima() raises:
    """A scope without texts fails before a minimum field is read."""
    with assert_raises(contains="KeyError: 'texts'"):
        _ = scopes_then_minima('{"scopes":{},"minima":[{"path":1}]}')


def test_empty_scopes_select_the_lane_minimum() raises:
    """Matching scopes leave the lane minimum flag after the restore flag."""
    var doc = PyJson.parse(
        scopes_then_minima(
            '{"scopes":{"texts":[],"expected":[],"labels":[]},"minima":['
            + '{"path":"extensions/carla/lane_refinement.mojo",'
            + '"name":"_rounded_axis_lane_minimum","owner":[]},'
            + '{"path":"other.mojo","name":"f","owner":["Map"]}]}'
        )
    )
    assert_equal(doc.key(doc.root, 0), "restore")
    assert_equal(doc.key(doc.root, 1), "minima")
    assert_equal(doc.flag(doc.at(doc.root, "restore")), False)
    var flags = doc.at(doc.root, "minima")
    assert_equal(doc.text(doc.item(flags, 0)), "true")
    assert_equal(doc.text(doc.item(flags, 1)), "false")


def test_a_graph_field_fails_before_the_minima() raises:
    """A graph without a source fails before a minimum field is read."""
    with assert_raises(contains="KeyError: 'graphs'"):
        _ = graphs_then_minima('{"minima":[{"path":1}]}')
    with assert_raises(contains="KeyError: 'actual'"):
        _ = graphs_then_minima('{"graphs":[{}],"minima":[{"path":1}]}')


def test_matching_graphs_select_the_lane_minimum() raises:
    """Equal graph text leaves the lane minimum flag."""
    var doc = PyJson.parse(
        graphs_then_minima(
            '{"graphs":[{"label":"ok","actual":"x","source":"x"}],"minima":['
            + '{"path":"extensions/carla/lane_refinement.mojo",'
            + '"name":"_rounded_axis_lane_minimum","owner":[]}]}'
        )
    )
    assert_equal(doc.length(doc.root), 1)
    assert_equal(doc.text(doc.item(doc.root, 0)), "true")


def test_a_restored_scope_fails_before_the_minima() raises:
    """A changed restored scope fails before a minimum field is read."""
    with assert_raises(contains="lane scope changed"):
        _ = restored_scope_then_minima(
            '{"prefixes":["stale"],"lane":0,"text":"def f():\\n    return'
            ' 1\\n",'
            + '"expected":["not-the-scope"],"labels":["lane scope changed"],'
            + '"minima":[{"path":1}]}'
        )


def test_a_matching_restored_scope_selects_the_lane_minimum() raises:
    """The scope before the first definition selects the lane minimum."""
    var doc = PyJson.parse(
        restored_scope_then_minima(
            '{"prefixes":["stale"],"lane":0,"text":"def f():\\n    return'
            ' 1\\n",'
            + '"expected":["def f():\\n    return 1\\n"],"labels":["ok"],'
            + '"minima":['
            + '{"path":"extensions/carla/lane_refinement.mojo",'
            + '"name":"_rounded_axis_lane_minimum","owner":[]}]}'
        )
    )
    assert_equal(doc.text(doc.item(doc.root, 0)), "true")


def main() raises:
    """Run the import-scope and lane-minimum tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
