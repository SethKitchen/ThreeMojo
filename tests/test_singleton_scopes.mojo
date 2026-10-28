# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Import scopes are checked before the rounded lane minima."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._python_json import PyJson
from tools.carla_singleton_gate import scopes_then_minima


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


def main() raises:
    """Run the import-scope and lane-minimum tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
