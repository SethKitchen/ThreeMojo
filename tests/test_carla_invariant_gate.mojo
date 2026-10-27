# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed coverage-invariant record fails the gate."""

from std.os import makedirs
from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools.carla_invariant_gate import (
    invariant_digest,
    invariant_pair,
    invariant_record,
)


def test_a_changed_record_is_refused() raises:
    """Bytes that are not the reviewed record fail closed."""
    with assert_raises(
        contains="coverage invariant successor: unreviewed migration record"
    ):
        invariant_record(
            String("").as_bytes(), String("").as_bytes(), "", False
        )


def test_a_changed_runtime_pin_is_refused() raises:
    """A different runtime pin digest fails closed."""
    with assert_raises(
        contains=(
            "coverage invariant successor: unreviewed runtime pin successor:"
            " runtime-source-pins.json"
        )
    ):
        invariant_digest(
            String("nope").as_bytes(), "00", "after", "runtime-source-pins.json"
        )


def test_a_changed_reconstruction_is_refused() raises:
    """A different reconstructed pin digest fails closed."""
    with assert_raises(
        contains=(
            "coverage invariant successor: historical pin reconstruction"
            " failed: sum2-guard-pins.json"
        )
    ):
        invariant_digest(
            String("nope").as_bytes(), "00", "before", "sum2-guard-pins.json"
        )


def test_a_reordered_pin_pair_is_refused() raises:
    """A pin-file order other than runtime then guard fails closed."""
    var directory = "/tmp/invariant-pair-test"
    makedirs(directory, exist_ok=True)
    Path(directory + "/labels.json").write_text(
        '["sum2-guard-pins.json","runtime-source-pins.json"]'
    )
    with assert_raises(
        contains="coverage invariant successor: wrong fixed ordered pin pair"
    ):
        invariant_pair(directory)


def main() raises:
    """Run the coverage-invariant gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
