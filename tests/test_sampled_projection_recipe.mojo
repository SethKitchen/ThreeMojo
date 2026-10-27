# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The sampled projection steps and comparison texts stay reviewed."""

from std.testing import TestSuite, assert_equal

from tools._python_json import PyJson
from tools._sampled_projection_recipe import sampled_projection_recipe


def test_sampled_projection_steps_stay_reviewed() raises:
    """The copy rule and five projection steps keep their comparison texts."""
    var doc = PyJson.parse(sampled_projection_recipe())
    assert_equal(doc.text(doc.at(doc.root, "trig_prefix")), "_atan")
    assert_equal(doc.text(doc.at(doc.root, "trig_module")), "curve_trig.mojo")
    assert_equal(
        doc.text(doc.at(doc.root, "bounds_module")), "curve_bounds.mojo"
    )
    var blend = doc.at(doc.root, "blend")
    assert_equal(doc.text(doc.at(blend, "name")), "_sample_blend_jet")
    var fields = doc.at(blend, "fields")
    assert_equal(doc.text(doc.item(fields, 0)), "first")
    assert_equal(doc.text(doc.item(fields, 1)), "second")
    var steps = doc.at(doc.root, "steps")
    assert_equal(doc.length(steps), 5)
    assert_equal(doc.text(doc.at(doc.item(steps, 0), "kind")), "project")
    assert_equal(
        doc.text(doc.at(doc.item(steps, 0), "target")), "_union_value_points"
    )
    assert_equal(doc.text(doc.at(doc.item(steps, 1), "role")), "reference")
    var rename = doc.item(steps, 2)
    var pairs = doc.at(rename, "pairs")
    assert_equal(doc.text(doc.item(doc.item(pairs, 0), 0)), "_sinc_jet")
    assert_equal(doc.text(doc.item(doc.item(pairs, 1), 1)), "curve_bounds.mojo")
    var constant = doc.item(steps, 3)
    assert_equal(doc.text(doc.at(constant, "constructor_index")), "2")
    assert_equal(doc.text(doc.at(constant, "pair_index")), "3")
    assert_equal(
        doc.text(doc.at(constant, "constructor")), "zero = _Interval.point(0.0)"
    )
    assert_equal(
        doc.text(doc.at(doc.at(constant, "field"), "prefix")),
        "_ValueJet(result[",
    )
    var lane = doc.item(steps, 4)
    assert_equal(doc.text(doc.at(lane, "refusal_index")), "0")
    assert_equal(doc.text(doc.at(lane, "capture_index")), "15")
    assert_equal(
        doc.text(doc.at(lane, "refusal")),
        (
            "if proof and not _sum2_supported_environment():\n        return"
            " _unknown_value_point()\n    "
        ),
    )
    assert_equal(
        doc.text(doc.at(lane, "capture")),
        (
            "if capture:\n            captured.record_at = geometry_at\n       "
            "     captured.low = low\n            captured.high = high\n    "
        ),
    )
    assert_equal(doc.text(doc.at(lane, "target")), "_lane_value_bound_impl")


def main() raises:
    """Run the sampled projection recipe tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
