# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed reviewed cleanup record fails the gate."""

from std.testing import TestSuite, assert_raises

from tools.carla_cleanup_gate import cleanup_digest, cleanup_record, cleanup_sha


def test_a_changed_record_is_refused() raises:
    """Bytes that are not the reviewed record fail closed."""
    with assert_raises(
        contains="reviewed cleanup source contract: unreviewed migration record"
    ):
        cleanup_record(String("").as_bytes(), String("").as_bytes(), False)


def test_a_changed_guard_pin_is_refused() raises:
    """Bytes that are not the recorded guard pin fail closed."""
    with assert_raises(
        contains=(
            "reviewed cleanup source contract: unreviewed dependency pin"
            " successor: sum2-guard-pins.json"
        )
    ):
        cleanup_digest(String("nope").as_bytes(), "00")


def test_the_stored_word_digest_matches_sha256() raises:
    """The stored-word digest is SHA-256 of the given bytes."""
    var digest = cleanup_sha(String("abc").as_bytes())
    if (
        digest
        != "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    ):
        raise Error(digest)


def main() raises:
    """Run the reviewed cleanup gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
