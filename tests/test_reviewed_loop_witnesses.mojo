# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Real reached-loop witnesses for four separately reviewed nonempty sites."""
from extensions.carla.lane_distance import _refinement_square
from extensions.carla.curve_interval import _Jet, _stored_blend_error
from tests.test_hair_strands import test_strands_in_a_scene
from std.math import isfinite
from std.testing import (
    TestSuite,
    assert_true,
    assert_false,
    assert_equal,
    assert_raises,
)
from coverage.report import Hits, parse_manifest, build_report
from coverage.mcdc import DecisionTrace


def test_all_admitted_axis_instantiations_and_four_float_blend() raises:
    var point: Array[Float64, 3] = [1.0, 2.0, 3.0]
    var query: Array[Float64, 3] = [0.0, 0.0, 0.0]
    assert_true(_refinement_square[1](point, query, 1.0).contains(1.0))
    assert_true(_refinement_square[2](point, query, 1.0).contains(5.0))
    assert_true(_refinement_square[3](point, query, 1.0).contains(14.0))
    var error = _stored_blend_error(_Jet.constant(0.5), 1.0, 2.0)
    assert_true(isfinite(error) and error >= 0.0)


def test_real_public_groom_upload_reaches_both_literal_loops() raises:
    test_strands_in_a_scene()


def test_each_named_mask_keeps_true_and_rejects_false() raises:
    # Synthetic protocol inputs validate reporting. They do not emit runtime
    # coverage probes or stand in for the real witnesses in the tests above.
    var entries = parse_manifest(
        "P constant-loops-v2"
        " 0000000000000000000000000000000000000000000000000000000000000000\nR"
        " axes 50 T reviewed-nonempty-range 1\nR blend 592 T literal-list 4\nR"
        " hair 195 T literal-range 2\nR hair 201 T literal-range 3\n"
    )
    for missing in ["axes:50", "blend:592", "hair:195", "hair:201"]:
        var hits = Hits()
        for identity in ["axes:50", "blend:592", "hair:195", "hair:201"]:
            if identity != missing:
                hits.add(String(identity) + ":T")
        var incomplete = build_report(entries, hits, List[DecisionTrace]())
        assert_false(incomplete.is_complete())
        assert_equal(incomplete.covered, 3)
        assert_equal(incomplete.total, 4)
        assert_equal(incomplete.potential, 8)
        hits.add(String(missing) + ":T")
        var complete = build_report(entries, hits, List[DecisionTrace]())
        assert_true(complete.is_complete())
        assert_true(complete.text.find("literal-list cardinality 4") >= 0)
        assert_true(complete.text.find("literal-range cardinality 2") >= 0)
        assert_true(complete.text.find("literal-range cardinality 3") >= 0)
        assert_true(complete.text.find("minimum cardinality 1") >= 0)
        hits.add(String(missing) + ":F")
        with assert_raises(contains="proof contradicted"):
            _ = build_report(entries, hits, List[DecisionTrace]())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
