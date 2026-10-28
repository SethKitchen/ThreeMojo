# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The run declaration is read before the lane-search edges."""

from std.testing import TestSuite, assert_raises

from tools._search_declaration import search_edges_after_declaration


def test_a_bad_move_stops_before_the_search_edges() raises:
    """A move failure keeps its prefix and does not reach the frontier."""
    with assert_raises(
        contains="optional runtime contract: unsupported move-token placement"
    ):
        search_edges_after_declaration("def f():\n    return x^ + 1\n", "f")
    with assert_raises(
        contains="missing or ambiguous actual guard declaration: f"
    ):
        search_edges_after_declaration("def g():\n    return 1\n", "f")


def test_a_plain_declaration_reaches_the_frontier_check() raises:
    """A declaration without a move is checked for the frontier loop."""
    with assert_raises(
        contains="optional runtime contract: one original search frontier loop"
    ):
        search_edges_after_declaration("def f():\n    return 1\n", "f")


def main() raises:
    """Run the search-declaration tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
