# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed support and dispatch record fails the gate."""

from std.os import makedirs
from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_raises

from tools._sha256 import sha256_hex
from tests._python_tokens import declaration_text, token_sha256
from tools.carla_dispatch_gate import (
    dispatch_declaration_tokens,
    dispatch_edge,
    dispatch_graphs,
    dispatch_pin,
    dispatch_pins,
    dispatch_record,
    dispatch_source_graphs,
    dispatch_tokens,
)


def test_a_changed_record_is_refused() raises:
    """Bytes that are not the reviewed record fail closed."""
    with assert_raises(
        contains="curve support/dispatch contract: unreviewed migration record"
    ):
        dispatch_record(String("").as_bytes())


def test_listed_pins_keep_their_order() raises:
    """A later pin mismatch keeps its own path."""
    var directory = mkdtemp(prefix="dispatch-pins-")
    var first = String("one")
    Path(directory + "/0").write_bytes(first.as_bytes())
    Path(directory + "/1").write_bytes(String("two").as_bytes())
    Path(directory + "/labels.json").write_text(
        '[{"name":"0","sha":"'
        + sha256_hex(first.as_bytes())
        + '","label":"one.json"},{"name":"1","sha":"00","label":"two.json"}]'
    )
    with assert_raises(
        contains=(
            "curve support/dispatch contract: standalone historical pin input"
            " changed: two.json"
        )
    ):
        dispatch_pins(directory)


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


def test_a_changed_dispatch_source_is_refused() raises:
    """A changed operation source fails after both texts are tokenized."""
    var payload = (
        '[{"label":"successor operations changed: module.mojo",'
        + '"actual":"def center():\\n    return 1\\n",'
        + '"source":"def center():\\n    return 2\\n"}]'
    )
    with assert_raises(
        contains=(
            "curve support/dispatch contract: successor operations changed:"
            " module.mojo"
        )
    ):
        dispatch_source_graphs(payload)


def test_matching_dispatch_sources_are_accepted() raises:
    """Identical operation sources pass in one check."""
    var payload = (
        '[{"label":"successor operations changed: module.mojo",'
        + '"actual":"def center():\\n    return 1\\n",'
        + '"source":"def center():\\n    return 1\\n"}]'
    )
    dispatch_source_graphs(payload)


def _declaration_payload(token: String) -> String:
    """Return one reference-declaration token check.

    Args:
        token: The required token digest.

    Returns:
        The JSON payload.
    """
    return (
        '[{"source":"def f():\\n    return 1\\n","name":"f","owner":[],'
        + '"token":"'
        + token
        + '","label":"reference changed: f"}]'
    )


def test_a_reference_declaration_token_is_checked_in_one_call() raises:
    """The recorded digest of the declaration passes."""
    var body = declaration_text("def f():\n    return 1\n", "f", List[String]())
    dispatch_declaration_tokens(_declaration_payload(token_sha256(body)))


def test_a_changed_reference_declaration_token_is_refused() raises:
    """A different declaration digest fails with its label."""
    with assert_raises(
        contains="curve support/dispatch contract: reference changed: f"
    ):
        dispatch_declaration_tokens(_declaration_payload("00"))


def main() raises:
    """Run the support and dispatch gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
