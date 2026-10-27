# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed accepted successor record fails the gate."""

from std.os import makedirs
from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tests._python_tokens import token_sha256
from tools.carla_accepted_gate import (
    accepted_digest,
    accepted_pair,
    accepted_record,
    accepted_sources,
)


def test_a_changed_record_is_refused() raises:
    """Bytes that are not the reviewed record fail closed."""
    with assert_raises(
        contains="accepted source successor: unreviewed migration record"
    ):
        accepted_record(String("").as_bytes(), String("").as_bytes(), "", False)


def test_a_changed_pin_is_refused() raises:
    """A different active pin digest fails closed."""
    with assert_raises(
        contains=(
            "accepted source successor: unreviewed runtime pin successor:"
            " runtime-source-pins.json"
        )
    ):
        accepted_digest(
            String("nope").as_bytes(), "00", "after", "runtime-source-pins.json"
        )


def test_a_changed_pin_reconstruction_is_refused() raises:
    """A different reconstructed pin digest fails closed."""
    with assert_raises(
        contains=(
            "accepted source successor: historical pins failed reconstruction"
        )
    ):
        accepted_digest(
            String("nope").as_bytes(),
            "00",
            "before",
            "runtime-source-pins.json",
        )


def test_a_changed_successor_token_is_refused() raises:
    """A text that does not have the recorded token digest fails closed."""
    var directory = "/tmp/accepted-source-test"
    makedirs(directory, exist_ok=True)
    Path(directory + "/labels.json").write_text(
        '[{"path":"module.mojo","token":"00","module_sha":"00"}]'
    )
    Path(directory + "/0.text").write_text("def changed():\n    pass\n")
    Path(directory + "/0.module").write_text("old\n")
    with assert_raises(
        contains=(
            "accepted source successor: unreviewed complete successor:"
            " module.mojo"
        )
    ):
        accepted_sources(directory)


def test_a_changed_historical_module_is_refused() raises:
    """A historical module that does not have the recorded digest fails closed.
    """
    var directory = "/tmp/accepted-module-test"
    var text = "def changed():\n    pass\n"
    makedirs(directory, exist_ok=True)
    Path(directory + "/labels.json").write_text(
        '[{"path":"module.mojo","token":"'
        + token_sha256(text)
        + '","module_sha":"00"}]'
    )
    Path(directory + "/0.text").write_text(text)
    Path(directory + "/0.module").write_text("old\n")
    with assert_raises(
        contains=(
            "accepted source successor: historical module changed: module.mojo"
        )
    ):
        accepted_sources(directory)


def test_a_reordered_pin_pair_is_refused() raises:
    """A pin-file order other than runtime then guard fails closed."""
    var directory = "/tmp/accepted-pair-test"
    makedirs(directory, exist_ok=True)
    Path(directory + "/labels.json").write_text(
        '["sum2-guard-pins.json","runtime-source-pins.json"]'
    )
    with assert_raises(
        contains="accepted source successor: wrong fixed ordered pin pair"
    ):
        accepted_pair(directory)


def main() raises:
    """Run the accepted successor gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
