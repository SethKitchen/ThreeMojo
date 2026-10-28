# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed coverage-followup record fails the gate."""

from std.os import makedirs
from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises

from tools._sha256 import sha256_hex
from tools.carla_followup_gate import (
    followup_digest,
    followup_pair,
    followup_pin_predecessor,
    followup_places,
    followup_record,
    followup_tokens,
)


def test_a_changed_record_is_refused() raises:
    """Bytes that are not the reviewed record fail closed."""
    with assert_raises(
        contains="coverage followup successor: unreviewed migration record"
    ):
        followup_record(String("").as_bytes(), String("").as_bytes(), "", False)
    with assert_raises(
        contains="coverage followup successor: unreviewed migration record"
    ):
        followup_record(
            String('{"a":1,"a":2}').as_bytes(),
            String("").as_bytes(),
            "",
            False,
        )


def test_the_reviewed_followup_record_passes() raises:
    """The reviewed record passes the digest and the repeated-key check."""
    followup_record(
        Path(
            "tools/carla_lane_oracle/coverage-followup-migration.json"
        ).read_bytes(),
        String("").as_bytes(),
        "",
        False,
    )


def test_a_changed_pin_reconstruction_is_refused() raises:
    """A different reconstructed pin digest fails closed."""
    with assert_raises(
        contains=(
            "coverage followup successor: historical pin reconstruction failed"
        )
    ):
        followup_digest(
            String("nope").as_bytes(),
            "00",
            "before",
            "runtime-source-pins.json",
        )


def test_a_changed_successor_token_is_refused() raises:
    """A text that does not have the recorded token digest fails closed."""
    var directory = "/tmp/followup-token-test"
    makedirs(directory, exist_ok=True)
    Path(directory + "/labels.json").write_text(
        '[{"path":"module.mojo","token":"00"}]'
    )
    Path(directory + "/0.text").write_text("def changed():\n    pass\n")
    with assert_raises(
        contains=(
            "coverage followup successor: complete successor changed:"
            " module.mojo"
        )
    ):
        followup_tokens(directory)


def test_a_reordered_pin_pair_is_refused() raises:
    """A pin-file order other than runtime then guard fails closed."""
    var directory = "/tmp/followup-pair-test"
    makedirs(directory, exist_ok=True)
    Path(directory + "/labels.json").write_text(
        '["sum2-guard-pins.json","runtime-source-pins.json"]'
    )
    with assert_raises(
        contains="coverage followup successor: wrong fixed ordered pin pair"
    ):
        followup_pair(directory)


def test_a_repeated_pin_placement_is_refused() raises:
    """A repeated pointer fails closed before later values are checked."""
    var directory = "/tmp/followup-places-test"
    makedirs(directory, exist_ok=True)
    Path(directory + "/labels.json").write_text(
        '[{"duplicate":false,"actual":"aa","expected":"aa"},'
        + '{"duplicate":true,"actual":"","expected":"bb"}]'
    )
    with assert_raises(
        contains="coverage followup successor: duplicate pin placement"
    ):
        followup_places(directory)


def test_a_restored_followup_pin_matches_its_predecessor() raises:
    """The historical value replaces the active value in one check."""
    var payload = String('{"group":{"path":"new"}}')
    var restored = "{\n  \"group\": {\n    \"path\": \"old\"\n  }\n}\n"
    var request = (
        '{"after":"'
        + sha256_hex(payload.as_bytes())
        + '","before":"'
        + sha256_hex(restored.as_bytes())
        + '","label":"runtime-source-pins.json","transitions":[{"pointer":'
        + '["group","path"],"after":"new","before":"old"}]}'
    )
    assert_equal(followup_pin_predecessor(payload.as_bytes(), request), restored)


def test_a_wrong_followup_digest_fails_before_a_repeated_key() raises:
    """A repeated key is not reported when the pin digest is wrong."""
    var payload = String('{"a":1,"a":2}')
    var request = (
        '{"after":"00","before":"00","label":"runtime-source-pins.json",'
        + '"transitions":[]}'
    )
    with assert_raises(
        contains=(
            "coverage followup successor: unreviewed runtime pin successor:"
            " runtime-source-pins.json"
        )
    ):
        _ = followup_pin_predecessor(payload.as_bytes(), request)


def test_a_repeated_followup_key_fails_before_placement() raises:
    """A repeated key fails after the digest and before placement."""
    var payload = String('{"a":1,"a":2}')
    var request = (
        '{"after":"'
        + sha256_hex(payload.as_bytes())
        + '","before":"00","label":"runtime-source-pins.json","transitions":[]}'
    )
    with assert_raises(contains="duplicate runtime source pin key: a"):
        _ = followup_pin_predecessor(payload.as_bytes(), request)


def main() raises:
    """Run the coverage-followup gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
