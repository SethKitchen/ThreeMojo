# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The optional-runtime declaration groups stay in reviewed order."""

from std.testing import TestSuite, assert_equal

from tools._optional_runtime_schedule import optional_runtime_schedule
from tools._python_json import MISSING, PyJson


def _bind(doc: PyJson, step: Int, index: Int) raises -> Int:
    """Return one bound declaration in a schedule step."""
    return doc.item(doc.at(step, "bind"), index)


def test_optional_runtime_groups_stay_in_reviewed_order() raises:
    """Seven groups run before the consumer scan, and three run after it."""
    var doc = PyJson.parse(optional_runtime_schedule())
    assert_equal(doc.key(doc.root, 0), "before")
    assert_equal(doc.key(doc.root, 1), "after")
    assert_equal(doc.key(doc.root, 2), "search")
    assert_equal(doc.text(doc.at(doc.root, "search")), "_run_lane_search")
    var before = doc.at(doc.root, "before")
    var after = doc.at(doc.root, "after")
    assert_equal(doc.length(before), 7)
    assert_equal(doc.length(after), 3)
    assert_equal(doc.text(doc.at(doc.item(before, 0), "group")), "helper")
    assert_equal(doc.text(doc.at(doc.item(before, 1), "group")), "guards")
    assert_equal(doc.text(doc.at(doc.item(before, 2), "group")), "origin")
    assert_equal(doc.text(doc.at(doc.item(before, 3), "group")), "work")
    assert_equal(doc.text(doc.at(doc.item(before, 4), "group")), "model")
    assert_equal(doc.text(doc.at(doc.item(before, 5), "group")), "support")
    assert_equal(doc.text(doc.at(doc.item(before, 6), "group")), "dispatch")
    assert_equal(doc.text(doc.at(doc.item(after, 0), "group")), "followup")
    assert_equal(doc.text(doc.at(doc.item(after, 1), "group")), "recheck")
    assert_equal(doc.text(doc.at(doc.item(after, 2), "group")), "fee")
    var helper = doc.item(before, 0)
    assert_equal(doc.find(helper, "check"), MISSING)
    var helper_bind = _bind(doc, helper, 0)
    assert_equal(doc.text(doc.at(helper_bind, "module")), "lane_refinement")
    assert_equal(doc.text(doc.at(helper_bind, "name")), "_same_cache_key")
    assert_equal(
        doc.text(doc.at(helper_bind, "label")),
        "exact UInt64 pair helper comparison",
    )
    var guards = doc.item(before, 1)
    assert_equal(doc.length(doc.at(guards, "bind")), 7)
    assert_equal(doc.find(_bind(doc, guards, 0), "label"), MISSING)
    assert_equal(
        doc.text(doc.at(_bind(doc, guards, 0), "name")), "_try_objective_model"
    )
    assert_equal(
        doc.text(doc.at(_bind(doc, guards, 6), "name")),
        "_try_spiral_grouped_roundoff_envelope_metered",
    )
    assert_equal(doc.text(doc.item(doc.at(guards, "edges"), 3)), "cuts")
    var origin = doc.item(before, 2)
    assert_equal(
        doc.text(doc.at(doc.item(doc.at(origin, "check"), 0), "label")),
        "complete X stored-term count and origin",
    )
    var model = doc.item(before, 4)
    assert_equal(doc.length(doc.at(model, "bind")), 0)
    assert_equal(doc.length(doc.at(model, "check")), 2)
    assert_equal(
        doc.text(doc.at(doc.item(doc.at(model, "check"), 1), "label")),
        "restriction cannot widen owner low",
    )
    var dispatch = doc.item(before, 6)
    assert_equal(
        doc.text(doc.at(_bind(doc, dispatch, 0), "name")),
        "_sample_dispatch_predicate",
    )
    assert_equal(doc.text(doc.item(doc.at(dispatch, "edges"), 1)), "cuts")
    var fee = doc.item(after, 2)
    var fee_bind = _bind(doc, fee, 0)
    assert_equal(doc.text(doc.at(fee_bind, "module")), "map")
    assert_equal(doc.text(doc.at(fee_bind, "name")), "_query_node_step_cost")
    assert_equal(doc.text(doc.at(fee_bind, "label")), "reviewed goal node fee")


def main() raises:
    """Run the optional-runtime schedule tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
