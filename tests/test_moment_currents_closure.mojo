# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The sampled closure is read after the live routing documents."""

from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tools._moment_route import moment_route_current
from tools._moment_routes import moment_currents_then_closure
from tools._python_json import PyJson


def _payload(source: String) raises -> String:
    """Return one named route source.

    Args:
        source: The module text.

    Returns:
        A JSON list with one `name` and that `source`.

    Raises:
        Error: The list cannot be written.
    """
    var doc = PyJson()
    var rows = doc.new_list()
    var item = doc.new_dict()
    doc.set(item, "name", doc.new_str("ideal_caller"))
    doc.set(item, "source", doc.new_str(source))
    doc.append(rows, item)
    doc.root = rows
    return doc.dumps()


def test_a_bad_route_fails_before_the_closure() raises:
    """An unsupported route fails before the closure is required."""
    with assert_raises(contains="unsupported top-level source routing"):
        _ = moment_currents_then_closure(_payload('def f():\n    return "'))


def test_the_closure_follows_the_routing_documents() raises:
    """The routing object stays ahead of the sampled closure."""
    var source = "def f():\n    return 1\n"
    var doc = PyJson.parse(moment_currents_then_closure(_payload(source)))
    assert_equal(doc.key(doc.root, 0), "currents")
    assert_equal(doc.key(doc.root, 1), "closure")
    var currents = doc.at(doc.root, "currents")
    assert_equal(
        doc.text(doc.at(currents, "ideal_caller")),
        moment_route_current(source),
    )
    var closure = doc.at(doc.root, "closure")
    assert_equal(
        doc.text(doc.at(closure, "bounds_path")),
        "extensions/carla/curve_bounds.mojo",
    )
    assert_true(doc.get(closure, "reviewed") != -1)


def main() raises:
    """Run the route and closure tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
