# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The reviewed cleanup declarations stay in source order."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._cleanup_declarations import (
    cleanup_declarations,
    cleanup_declarations_after_digest,
)
from tools._python_json import PyJson
from tools._sha256 import sha256_hex


def test_cleanup_declarations_stay_with_their_sources() raises:
    """Line, arc, bounds, center, and outward keep their owners."""
    var doc = PyJson.parse(cleanup_declarations())
    assert_equal(doc.key(doc.root, 0), "junction")
    assert_equal(doc.key(doc.root, 1), "unreviewed")
    assert_equal(doc.key(doc.root, 2), "declarations")
    assert_equal(
        doc.text(doc.at(doc.root, "junction")),
        "extensions/carla/junction_bounds.mojo",
    )
    assert_equal(
        doc.text(doc.at(doc.root, "unreviewed")),
        "unreviewed complete successor: ",
    )
    var rows = doc.at(doc.root, "declarations")
    assert_equal(doc.length(rows), 5)
    assert_equal(doc.text(doc.at(doc.item(rows, 0), "key")), "line")
    assert_equal(doc.text(doc.at(doc.item(rows, 0), "source")), "0")
    assert_equal(
        doc.text(doc.at(doc.item(rows, 0), "name")),
        "_rounded_line_axis_context",
    )
    assert_equal(doc.length(doc.at(doc.item(rows, 0), "owner")), 0)
    assert_equal(doc.text(doc.at(doc.item(rows, 1), "key")), "arc")
    assert_equal(
        doc.text(doc.at(doc.item(rows, 1), "name")), "_rounded_arc_context"
    )
    var bounds = doc.item(rows, 2)
    assert_equal(doc.text(doc.at(bounds, "source")), "1")
    assert_equal(doc.text(doc.at(bounds, "name")), "bounds")
    assert_equal(doc.text(doc.item(doc.at(bounds, "owner"), 0)), "_RoundedBox")
    var center = doc.item(rows, 3)
    assert_equal(doc.text(doc.at(center, "name")), "center")
    assert_equal(doc.text(doc.item(doc.at(center, "owner"), 0)), "_RoundedArc")
    var outward = doc.item(rows, 4)
    assert_equal(doc.text(doc.at(outward, "source")), "2")
    assert_equal(doc.text(doc.at(outward, "name")), "_outward_float")
    assert_equal(doc.text(doc.at(outward, "key")), "outward")


def test_a_changed_guard_pin_fails_before_the_catalog() raises:
    """A wrong digest fails before the declaration catalog is returned."""
    with assert_raises(
        contains=(
            "reviewed cleanup source contract: unreviewed dependency pin"
            " successor: sum2-guard-pins.json"
        )
    ):
        _ = cleanup_declarations_after_digest(String("nope").as_bytes(), "00")


def test_a_matching_guard_pin_returns_the_catalog() raises:
    """A matching digest returns the declaration catalog."""
    var payload = String("guard").as_bytes()
    var doc = PyJson.parse(
        cleanup_declarations_after_digest(payload, sha256_hex(payload))
    )
    assert_equal(doc.key(doc.root, 0), "junction")
    assert_equal(
        doc.text(doc.at(doc.root, "junction")),
        "extensions/carla/junction_bounds.mojo",
    )


def main() raises:
    """Run the cleanup declaration tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
