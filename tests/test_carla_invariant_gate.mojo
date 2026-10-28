# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed coverage-invariant record fails the gate."""

from std.os import makedirs
from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises

from tools._sha256 import sha256_hex
from tools.carla_invariant_gate import (
    invariant_digest,
    invariant_pair,
    invariant_pin_predecessor,
    invariant_places,
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


def test_a_repeated_pin_placement_is_refused() raises:
    """A repeated pointer fails closed before later values are checked."""
    var directory = "/tmp/invariant-places-test"
    makedirs(directory, exist_ok=True)
    Path(directory + "/labels.json").write_text(
        '[{"duplicate":false,"actual":"aa","expected":"aa"},'
        + '{"duplicate":true,"actual":"","expected":"bb"}]'
    )
    with assert_raises(
        contains="coverage invariant successor: duplicate pin placement"
    ):
        invariant_places(directory)


def _pin() -> String:
    """Return one active coverage-invariant pin."""
    return '{\n  "schema": 1,\n  "accepted": "new"\n}\n'


def _restored() -> String:
    """Return the historical pin for `_pin`."""
    return '{\n  "schema": 1,\n  "accepted": "old"\n}\n'


def _request(label: String, before: String, after_token: String) -> String:
    """Return one predecessor request.

    Args:
        label: The pin filename.
        before: The required predecessor digest.
        after_token: The active token stored in the pin.

    Returns:
        The request JSON.
    """
    return (
        '{"after":"'
        + sha256_hex(_pin().as_bytes())
        + '","before":"'
        + before
        + '","label":"'
        + label
        + '","transitions":[{"pointer":["accepted"],"after":"'
        + after_token
        + '","before":"old"}]}'
    )


def test_a_restored_invariant_pin_matches_its_predecessor() raises:
    """The historical token replaces the active token in one check."""
    var restored = _restored()
    assert_equal(
        invariant_pin_predecessor(
            _pin().as_bytes(),
            _request(
                "runtime-source-pins.json",
                sha256_hex(restored.as_bytes()),
                "new",
            ),
        ),
        restored,
    )


def test_a_changed_invariant_pin_digest_is_refused() raises:
    """A wrong active digest fails closed."""
    with assert_raises(
        contains=(
            "coverage invariant successor: unreviewed runtime pin successor:"
            " runtime-source-pins.json"
        )
    ):
        _ = invariant_pin_predecessor(
            _pin().as_bytes(),
            _request("runtime-source-pins.json", "00", "new").replace(
                sha256_hex(_pin().as_bytes()), "00"
            ),
        )


def test_a_repeated_invariant_pointer_is_refused() raises:
    """A repeated pointer fails closed."""
    var request = (
        '{"after":"'
        + sha256_hex(_pin().as_bytes())
        + '","before":"00","label":"runtime-source-pins.json","transitions":['
        + '{"pointer":["accepted"],"after":"new","before":"old"},'
        + '{"pointer":["accepted"],"after":"new","before":"old"}]}'
    )
    with assert_raises(
        contains="coverage invariant successor: duplicate pin placement"
    ):
        _ = invariant_pin_predecessor(_pin().as_bytes(), request)


def test_a_changed_invariant_placement_is_refused() raises:
    """A placement whose current token changed fails closed."""
    with assert_raises(
        contains="coverage invariant successor: active pin placement mismatch"
    ):
        _ = invariant_pin_predecessor(
            _pin().as_bytes(),
            _request("runtime-source-pins.json", "00", "absent"),
        )


def test_a_missing_invariant_pointer_is_refused() raises:
    """A pointer that leaves the pin fails closed."""
    var request = (
        '{"after":"'
        + sha256_hex(_pin().as_bytes())
        + '","before":"00","label":"sum2-guard-pins.json","transitions":['
        + '{"pointer":["missing"],"after":"new","before":"old"}]}'
    )
    with assert_raises(contains="KeyError: 'missing'"):
        _ = invariant_pin_predecessor(_pin().as_bytes(), request)


def test_a_changed_invariant_predecessor_digest_is_refused() raises:
    """A restored pin whose digest changed fails closed."""
    with assert_raises(
        contains=(
            "coverage invariant successor: historical pin reconstruction"
            " failed: sum2-guard-pins.json"
        )
    ):
        _ = invariant_pin_predecessor(
            _pin().as_bytes(),
            _request("sum2-guard-pins.json", "00", "new"),
        )


def main() raises:
    """Run the coverage-invariant gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
