# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed accepted successor record fails the gate."""

from std.os import makedirs
from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises

from tests._python_tokens import token_sha256
from tools._sha256 import sha256_hex
from tools.carla_accepted_gate import (
    accepted_digest,
    accepted_pair,
    accepted_pin_predecessor,
    accepted_places,
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


def test_a_repeated_pin_placement_is_refused() raises:
    """A repeated pointer fails closed before later values are checked."""
    var directory = "/tmp/accepted-places-test"
    makedirs(directory, exist_ok=True)
    Path(directory + "/labels.json").write_text(
        '[{"duplicate":false,"actual":"aa","expected":"aa"},'
        + '{"duplicate":true,"actual":"","expected":"bb"}]'
    )
    with assert_raises(
        contains="accepted source successor: duplicate pin placement"
    ):
        accepted_places(directory)


def _request(payload: String, before: String) -> String:
    """Return one predecessor request for `payload`.

    Args:
        payload: The active pin text.
        before: The required predecessor digest.

    Returns:
        The request JSON.
    """
    return (
        '{"after":"'
        + sha256_hex(payload.as_bytes())
        + '","before":"'
        + before
        + '","label":"runtime-source-pins.json","transitions":[{"pointer":'
        + '["group","path"],"after":"new","before":"old"}]}'
    )


def test_a_restored_accepted_pin_matches_its_predecessor() raises:
    """The historical value replaces the active value in one check."""
    var payload = String('{"group":{"path":"new"}}')
    var restored = "{\n  \"group\": {\n    \"path\": \"old\"\n  }\n}\n"
    assert_equal(
        accepted_pin_predecessor(
            payload.as_bytes(),
            _request(payload, sha256_hex(restored.as_bytes())),
        ),
        restored,
    )


def test_a_wrong_digest_fails_before_a_repeated_key() raises:
    """A repeated key is not reported when the pin digest is wrong."""
    var payload = String('{"a":1,"a":2}')
    with assert_raises(
        contains=(
            "accepted source successor: unreviewed runtime pin successor:"
            " runtime-source-pins.json"
        )
    ):
        _ = accepted_pin_predecessor(
            payload.as_bytes(), _request(payload, "00").replace(
                sha256_hex(payload.as_bytes()), "00"
            )
        )


def test_a_repeated_accepted_key_fails_before_placement() raises:
    """A repeated key fails after the digest and before placement."""
    var payload = String('{"a":1,"a":2}')
    var request = (
        '{"after":"'
        + sha256_hex(payload.as_bytes())
        + '","before":"00","label":"runtime-source-pins.json","transitions":[]}'
    )
    with assert_raises(contains="duplicate runtime source pin key: a"):
        _ = accepted_pin_predecessor(payload.as_bytes(), request)


def main() raises:
    """Run the accepted successor gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
