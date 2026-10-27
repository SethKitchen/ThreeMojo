# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Framed SHA-256 digests match hashlib, including embedded newlines."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._framed_sha256 import framed_sha256


def test_framed_digests_match_hashlib() raises:
    """Empty, adjacent, and binary payloads keep hashlib's digest."""
    assert_equal(framed_sha256(String("").as_bytes()), "[]")
    assert_equal(
        framed_sha256("0\n".as_bytes()),
        '["e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"]',
    )
    assert_equal(
        framed_sha256("1\nA0\n3\nxyz".as_bytes()),
        '["559aead08264d5795d3909718cdd05abd49572e84fe55590eef31a88a08fdffd",'
        + '"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",'
        + '"3608bca1e44ea6c4d268eb6db02260269892c0b42b86bbf1e77a6fa16c3c9282"]',
    )
    assert_equal(
        framed_sha256("11\nhello\nworld".as_bytes()),
        '["26c60a61d01db5836ca70fefd44a6a016620413c8ef5f259a6c5612d4f79d3b8"]',
    )
    var frame = List[UInt8]()
    frame.append(UInt8(ord("4")))
    frame.append(UInt8(10))
    frame.append(UInt8(0xFF))
    frame.append(UInt8(10))
    frame.append(UInt8(0))
    frame.append(UInt8(1))
    assert_equal(
        framed_sha256(Span(frame)),
        '["550c0b8015c8616e8ed517815229d639a22d329ceb6b605bd58a4bf286f39a9a"]',
    )


def test_a_bad_source_frame_is_refused() raises:
    """Each malformed length is reported before a payload is hashed."""
    with assert_raises(contains="invalid source frame length"):
        _ = framed_sha256("/\n".as_bytes())
    with assert_raises(contains="invalid source frame length"):
        _ = framed_sha256(":\n".as_bytes())
    with assert_raises(contains="invalid source frame length"):
        _ = framed_sha256("\n".as_bytes())
    with assert_raises(contains="invalid source frame length"):
        _ = framed_sha256("12".as_bytes())
    with assert_raises(contains="invalid source frame length"):
        _ = framed_sha256("5\nab".as_bytes())
    with assert_raises(contains="invalid source frame length"):
        _ = framed_sha256("1234567890\n".as_bytes())


def main() raises:
    """Run the framed SHA-256 tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
