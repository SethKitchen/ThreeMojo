# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The derivative aliases are checked before the primitive graph digest."""

from std.testing import TestSuite, assert_raises

from tools._sha256 import sha256_hex
from tools.carla_sampled_text import aliases_then_graph


def _source() -> String:
    """Return the two reviewed derivative aliases."""
    return (
        "comptime _Jet = _JetExpression[True]\n"
        + "comptime _ValueJet = _JetExpression[False]\n"
    )


def test_a_missing_alias_fails_before_the_graph() raises:
    """A missing Jet alias fails before a wrong graph digest."""
    with assert_raises(contains="missing or ambiguous actual alias: _Jet"):
        aliases_then_graph(
            "def f():\n    return 1\n",
            "graph",
            "0000000000000000000000000000000000000000000000000000000000000000",
            "Jet primitive graph changed",
        )


def test_a_changed_graph_fails_after_the_aliases() raises:
    """Reviewed aliases still refuse a different primitive graph."""
    with assert_raises(contains="Jet primitive graph changed"):
        aliases_then_graph(
            _source(),
            "class _JetExpression",
            "0000000000000000000000000000000000000000000000000000000000000000",
            "Jet primitive graph changed",
        )


def test_the_reviewed_aliases_match_their_graph() raises:
    """The alias check accepts the digest of the supplied graph."""
    var graph = "class _JetExpression"
    aliases_then_graph(
        _source(),
        graph,
        sha256_hex(graph.as_bytes()),
        "Jet primitive graph changed",
    )


def main() raises:
    """Run the alias and graph tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
