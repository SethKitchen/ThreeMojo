# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The masked manifest keeps proved branches and refuses a bad line."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._sha256 import sha256_hex
from tools.coverage_mask import coverage_mask


def _bytes(text: String) -> List[UInt8]:
    """Return the bytes of `text`.

    Args:
        text: The manifest text.

    Returns:
        The bytes.
    """
    var raw = List[UInt8]()
    for byte in text.as_bytes():
        raw.append(byte)
    return raw^


def test_mask_rows_and_refusals() raises:
    """A matching proof is masked, and a bad manifest is refused."""
    var manifest = "L demo 4\nB demo 4\nL demo 5\n"
    var raw = _bytes(manifest)
    var digest = sha256_hex(Span(raw))
    var envelope = (
        '{"sha256":"abc","receipt":{"manifest_sha256":"'
        + digest
        + '","proofs":[{"module":"demo","line":4,"required":"T",'
        + '"kind":"literal","cardinality":1}]}}'
    )
    assert_equal(
        coverage_mask(raw, envelope),
        "P constant-loops-v2 abc\nL demo 4\nR demo 4 T literal 1\nL demo 5\n",
    )
    with assert_raises(contains="Loop-proof manifest binding mismatch"):
        _ = coverage_mask(
            raw,
            '{"sha256":"abc","receipt":{"manifest_sha256":"no","proofs":[]}}',
        )
    with assert_raises(contains="Malformed original coverage manifest: B demo 0"):
        var bad = _bytes("B demo 0\n")
        var bad_digest = sha256_hex(Span(bad))
        _ = coverage_mask(
            bad,
            '{"sha256":"abc","receipt":{"manifest_sha256":"'
            + bad_digest
            + '","proofs":[]}}',
        )
    with assert_raises(contains="Invalid coverage source identity: ../demo"):
        var escaped = _bytes("B ../demo 4\n")
        var escaped_digest = sha256_hex(Span(escaped))
        _ = coverage_mask(
            escaped,
            '{"sha256":"abc","receipt":{"manifest_sha256":"'
            + escaped_digest
            + '","proofs":[]}}',
        )
    with assert_raises(contains="Duplicate coverage manifest entry: B demo 4"):
        var repeated = _bytes("B demo 4\nB demo 4\n")
        var repeated_digest = sha256_hex(Span(repeated))
        _ = coverage_mask(
            repeated,
            '{"sha256":"abc","receipt":{"manifest_sha256":"'
            + repeated_digest
            + '","proofs":[]}}',
        )
    with assert_raises(contains="Loop proof does not identify one original branch"):
        _ = coverage_mask(
            raw,
            '{"sha256":"abc","receipt":{"manifest_sha256":"'
            + digest
            + '","proofs":[{"module":"demo","line":9,"required":"F",'
            + '"kind":"literal","cardinality":0}]}}',
        )


def main() raises:
    """Run the coverage mask tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
