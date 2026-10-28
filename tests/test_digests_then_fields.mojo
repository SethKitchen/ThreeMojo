# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Shared graph digests are checked before the value fields."""

from std.testing import TestSuite, assert_raises

from tools._python_json import PyJson
from tools._sha256 import sha256_hex
from tools.carla_sampled_text import digests_then_value_fields


def _payload(graph: String, digest: String, message: String) raises -> String:
    """Return one graph digest row.

    Args:
        graph: The Python dump.
        digest: The expected SHA-256.
        message: The failure text.

    Returns:
        A JSON list with that row.

    Raises:
        Error: The list cannot be written.
    """
    var doc = PyJson()
    var rows = doc.new_list()
    var item = doc.new_dict()
    doc.set(item, "graph", doc.new_str(graph))
    doc.set(item, "digest", doc.new_str(digest))
    doc.set(item, "message", doc.new_str(message))
    doc.append(rows, item)
    doc.root = rows
    return doc.dumps()


def test_a_changed_graph_fails_before_the_value_fields() raises:
    """A wrong digest fails before a derivative field is checked."""
    with assert_raises(contains="shared bridge changed"):
        digests_then_value_fields(
            _payload(
                "graph",
                "0000000000000000000000000000000000000000000000000000000000000000",
                "shared bridge changed",
            ),
            "def f():\n    return x.first\n",
        )


def test_a_matching_graph_still_checks_the_value_fields() raises:
    """A matching digest still refuses a derivative field."""
    var graph = "graph"
    with assert_raises(
        contains="derivative-field/flag read or sqrt in value-only graph"
    ):
        digests_then_value_fields(
            _payload(
                graph, sha256_hex(graph.as_bytes()), "shared bridge changed"
            ),
            "def f():\n    return x.first\n",
        )


def test_a_matching_graph_accepts_plain_value_fields() raises:
    """A matching digest accepts a value graph without derivative fields."""
    var graph = "graph"
    digests_then_value_fields(
        _payload(graph, sha256_hex(graph.as_bytes()), "shared bridge changed"),
        "def f():\n    return 1\n",
    )


def main() raises:
    """Run the shared graph and value-field tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
