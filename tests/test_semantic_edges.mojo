# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Optional-runtime semantic checks keep their historical groups."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._python_json import PyJson
from tools._semantic_edges import semantic_edge_payload


def _doc(group: String, payload: String) raises -> PyJson:
    """Parse one group's checks.

    Args:
        group: The group name.
        payload: The declaration JSON.

    Returns:
        The parsed check list.

    Raises:
        Error: The group or the payload is invalid.
    """
    return PyJson.parse(semantic_edge_payload(group, payload))


def _one(name: String) -> String:
    """Return one declaration object.

    Args:
        name: The function name.

    Returns:
        A JSON object with that name and a stand-in source.
    """
    return '{"name":"' + name + '","source":"body"}'


def test_each_semantic_group_keeps_its_length() raises:
    """Every historical group has its original number of checks."""
    var helper = '{"helper":' + _one("_same_cache_key") + "}"
    var doc = _doc("helper", helper)
    assert_equal(doc.length(doc.root), 1)
    assert_equal(doc.text(doc.at(doc.item(doc.root, 0), "kind")), "body")
    var guards = (
        '{"model":'
        + _one("_try_objective_model")
        + ',"restrict":'
        + _one("_restrict_objective_model")
        + ',"cut":'
        + _one("_sample_dispatch_cut")
        + ',"cuts":'
        + _one("_try_sample_dispatch_cuts")
        + ',"lane":'
        + _one("_try_grouped_lane_jet")
        + ',"raw":'
        + _one("_try_spiral_grouped_roundoff_envelope")
        + ',"metered":'
        + _one("_try_spiral_grouped_roundoff_envelope_metered")
        + "}"
    )
    doc = _doc("guards", guards)
    assert_equal(doc.length(doc.root), 7)
    assert_equal(doc.text(doc.at(doc.item(doc.root, 0), "kind")), "first")
    assert_equal(
        doc.text(doc.at(doc.item(doc.root, 0), "message")),
        "fresh invocation guard missing or moved: _try_objective_model",
    )
    doc = _doc(
        "origin",
        '{"origin":'
        + _one("_grouped_origin_error")
        + ',"raw":'
        + _one("_try_spiral_grouped_roundoff_envelope")
        + "}",
    )
    assert_equal(doc.length(doc.root), 6)
    doc = _doc(
        "work",
        '{"work":'
        + _one("_spiral_grouped_roundoff_work")
        + ',"lane":'
        + _one("_try_grouped_lane_jet")
        + ',"metered":'
        + _one("_try_spiral_grouped_roundoff_envelope_metered")
        + "}",
    )
    assert_equal(doc.length(doc.root), 8)
    assert_equal(
        doc.text(doc.at(doc.item(doc.root, 5), "call")),
        "_try_spiral_grouped_roundoff_envelope",
    )
    doc = _doc(
        "model",
        '{"model":'
        + _one("_try_objective_model")
        + ',"restrict":'
        + _one("_restrict_objective_model")
        + "}",
    )
    assert_equal(doc.length(doc.root), 13)
    assert_equal(
        doc.text(doc.at(doc.item(doc.root, 3), "fragment")),
        "not _model_interval(domain.value)",
    )
    doc = _doc("support", '{"support":' + _one("_minimizer_support") + "}")
    assert_equal(doc.length(doc.root), 6)
    doc = _doc(
        "dispatch",
        '{"predicate":'
        + _one("_sample_dispatch_predicate")
        + ',"cuts":'
        + _one("_try_sample_dispatch_cuts")
        + "}",
    )
    assert_equal(doc.length(doc.root), 12)
    assert_equal(
        doc.text(doc.at(doc.item(doc.root, 10), "kind")), "before-loop"
    )


def test_an_unknown_semantic_group_is_refused() raises:
    """A group outside the historical set is refused."""
    with assert_raises(contains="optional runtime edge group changed"):
        _ = semantic_edge_payload("other", "{}")


def main() raises:
    """Run the semantic edge tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
