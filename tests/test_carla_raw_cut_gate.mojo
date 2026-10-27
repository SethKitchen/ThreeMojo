# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed raw-cut record fails the gate."""

from std.testing import TestSuite, assert_raises

from tools.carla_raw_cut_gate import (
    raw_cut_binding,
    raw_cut_graph,
    raw_cut_digest,
    raw_cut_fixture,
    raw_cut_record,
)


def test_a_changed_record_is_refused() raises:
    """Bytes that are not the reviewed record fail closed."""
    with assert_raises(
        contains="raw cut inverse contract: unreviewed migration record"
    ):
        raw_cut_record(String("").as_bytes(), "")


def test_a_changed_predecessor_is_refused() raises:
    """Bytes that are not the recorded predecessor fail closed."""
    with assert_raises(
        contains=(
            "raw cut inverse contract: historical predecessor record changed"
        )
    ):
        raw_cut_digest(String("nope").as_bytes(), "00")


def test_a_changed_fixture_token_is_refused() raises:
    """A fixture that does not have the recorded token digest fails closed."""
    with assert_raises(
        contains=(
            "raw cut inverse contract: independent exact-word native fixture"
            " changed"
        )
    ):
        raw_cut_fixture("def changed():\n    pass\n", "00")


def test_an_unbound_successor_is_refused() raises:
    """A successor token that differs from the recorded predecessor fails closed.
    """
    with assert_raises(
        contains=(
            "raw cut inverse contract: successor is not bound to accepted"
            " predecessor"
        )
    ):
        raw_cut_binding("aa", "bb")


def test_a_changed_operation_graph_is_refused() raises:
    """Different significant token lists fail closed."""
    with assert_raises(
        contains="raw cut inverse contract: raw inverse operation graph changed"
    ):
        raw_cut_graph("[]", '[[1,"def"]]', "graph")


def main() raises:
    """Run the raw-cut gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
