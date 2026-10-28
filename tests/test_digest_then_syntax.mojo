# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The reviewed graph digest is checked before the following syntax."""

from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tools._python_json import PyJson
from tools._sha256 import sha256_hex
from tools.carla_cleanup_gate import digest_then_syntax


def _sources(text: String) raises -> String:
    """Return one source as a JSON list.

    Args:
        text: The source text.

    Returns:
        A JSON list containing `text`.

    Raises:
        Error: The list cannot be written.
    """
    var doc = PyJson()
    var rows = doc.new_list()
    doc.append(rows, doc.new_str(text))
    doc.root = rows
    return doc.dumps()


def test_a_changed_graph_fails_before_the_following_syntax() raises:
    """A wrong digest fails before an ambiguous generic is classified."""
    with assert_raises(contains="reference module changed"):
        _ = digest_then_syntax(
            "graph",
            "0000000000000000000000000000000000000000000000000000000000000000",
            "reference module changed",
            _sources(
                "def f[T: Int]():\n    return 1\ndef f[T: Int]():\n   "
                " return 2\n"
            ),
        )


def test_a_matching_graph_classifies_the_following_source() raises:
    """A matching digest returns the following syntax."""
    var graph = "graph"
    var doc = PyJson.parse(
        digest_then_syntax(
            graph,
            sha256_hex(graph.as_bytes()),
            "reference module changed",
            _sources("def ok():\n    return 1\n"),
        )
    )
    assert_equal(doc.length(doc.root), 1)
    var syntax = doc.item(doc.root, 0)
    assert_true(doc.text(doc.at(syntax, "source")).find("def ok") >= 0)


def main() raises:
    """Run the digest and syntax tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
