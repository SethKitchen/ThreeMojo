# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Plain reference graph digests are checked before the Jet primitive."""

from std.testing import TestSuite, assert_raises

from tools._python_json import PyJson
from tools._sha256 import sha256_hex
from tools.carla_sampled_text import hashes_then_declaration


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


def test_a_changed_graph_fails_before_the_primitive() raises:
    """A wrong digest fails before the Jet primitive is checked."""
    with assert_raises(contains="reference module changed"):
        hashes_then_declaration(
            _payload(
                "graph",
                "0000000000000000000000000000000000000000000000000000000000000000",
                "reference module changed",
            ),
            "def f():\n    return 1\n",
        )


def test_a_matching_graph_still_checks_the_primitive() raises:
    """A matching digest still refuses a missing Jet primitive."""
    var graph = "graph"
    with assert_raises(contains="unsupported primitive declaration"):
        hashes_then_declaration(
            _payload(
                graph,
                sha256_hex(graph.as_bytes()),
                "reference module changed",
            ),
            "def f():\n    return 1\n",
        )


def test_a_matching_graph_accepts_the_jet_primitive() raises:
    """A matching digest accepts one reviewed Jet primitive."""
    var graph = "graph"
    hashes_then_declaration(
        _payload(
            graph, sha256_hex(graph.as_bytes()), "reference module changed"
        ),
        "struct _JetExpression[derivatives: Bool]():\n    pass\n",
    )


def main() raises:
    """Run the graph digest tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
