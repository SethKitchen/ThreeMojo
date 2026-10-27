# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed support and dispatch record fails the gate."""

from std.os import makedirs
from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools.carla_dispatch_gate import (
    dispatch_edge,
    dispatch_graphs,
    dispatch_pin,
    dispatch_record,
    dispatch_tokens,
)


def test_a_changed_record_is_refused() raises:
    """Bytes that are not the reviewed record fail closed."""
    with assert_raises(
        contains="curve support/dispatch contract: unreviewed migration record"
    ):
        dispatch_record(String("").as_bytes())


def test_a_changed_pin_is_refused() raises:
    """Bytes that are not the recorded pin fail closed."""
    with assert_raises(
        contains=(
            "curve support/dispatch contract: standalone historical pin input"
            " changed: pins.json"
        )
    ):
        dispatch_pin(String("nope").as_bytes(), "00", "pins.json")


def test_a_changed_reference_token_is_refused() raises:
    """A text that does not have the recorded token digest fails closed."""
    var directory = "/tmp/dispatch-token-test"
    makedirs(directory, exist_ok=True)
    Path(directory + "/labels.json").write_text(
        '[{"label":"complete successor changed: module.mojo","token":"00"}]'
    )
    Path(directory + "/0.text").write_text("def changed():\n    pass\n")
    with assert_raises(
        contains=(
            "curve support/dispatch contract: complete successor changed:"
            " module.mojo"
        )
    ):
        dispatch_tokens(directory)


def test_a_mismatched_predecessor_edge_is_refused() raises:
    """A raw predecessor token that differs from the caller fails closed."""
    with assert_raises(
        contains=(
            "curve support/dispatch contract: raw predecessor edge mismatch"
        )
    ):
        dispatch_edge("aa", "bb")


def test_a_changed_operation_graph_is_refused() raises:
    """An operation graph whose token list changed fails closed."""
    var directory = "/tmp/dispatch-graphs-test"
    makedirs(directory, exist_ok=True)
    Path(directory + "/labels.json").write_text(
        '[{"label":"successor operations changed: module.mojo",'
        + '"actual":"[]","expected":"[[1,\\"def\\"]]"}]'
    )
    with assert_raises(
        contains=(
            "curve support/dispatch contract: successor operations changed:"
            " module.mojo"
        )
    ):
        dispatch_graphs(directory)


def main() raises:
    """Run the support and dispatch gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
