# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The producer review is checked before the invariant labels."""

from std.testing import TestSuite, assert_equal, assert_raises

from tests._python_tokens import declaration_routing
from tools._json_tools import quote_ascii
from tools._python_json import PyJson
from tools.carla_frozen_arc_gate import producer_review_then_labels


def test_a_missing_function_list_fails_before_the_labels() raises:
    """The review requires its function list before the labels are read."""
    with assert_raises(contains="KeyError: 'functions'"):
        _ = producer_review_then_labels("{}")


def test_an_empty_review_reads_the_invariant_labels() raises:
    """An empty producer list still returns the invariant labels."""
    var stored = declaration_routing("")
    var doc = PyJson.parse(
        producer_review_then_labels(
            '{"functions":[],"layout":{"source":"","stored":'
            + quote_ascii(stored)
            + "}}"
        )
    )
    assert_equal(doc.key(doc.root, 0), "labels")
    assert_equal(doc.key(doc.root, 1), "migration")
    assert_equal(
        doc.text(doc.at(doc.at(doc.root, "migration"), "path")),
        "tools/carla_lane_oracle/coverage-invariant-migration.json",
    )
    assert_equal(
        doc.text(doc.at(doc.at(doc.root, "labels"), "successor")),
        "complete successor changed: ",
    )


def main() raises:
    """Run the producer-review and invariant-label tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
