# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `tools.sha256`.

The vectors are FIPS 180-4's examples and values from Python's `hashlib`
over the pattern `i % 251`, at the lengths where the padding moves to a
second block.
"""

from std.testing import TestSuite, assert_equal

from tools.sha256 import Sha256, sha256_hex


def _bytes(text: String) -> List[UInt8]:
    """Return the bytes of a string."""
    var out = List[UInt8]()
    out.extend(text.as_bytes())
    return out^


def _pattern(length: Int) -> List[UInt8]:
    """Return `i % 251` for each index below `length`."""
    var out = List[UInt8](capacity=length)
    for i in range(length):
        out.append(UInt8(i % 251))
    return out^


def test_fips_examples() raises:
    assert_equal(
        sha256_hex(Span(_bytes("abc"))),
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
    )
    assert_equal(
        sha256_hex(
            Span(
                _bytes(
                    "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
                )
            )
        ),
        "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
    )
    var million = List[UInt8](length=1000000, fill=97)
    assert_equal(
        sha256_hex(Span(million)),
        "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0",
    )


def test_padding_boundaries_match_hashlib() raises:
    var lengths = [0, 1, 55, 56, 57, 63, 64, 65, 119, 120, 127, 128, 129, 1000]
    var digests = [
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        "6e340b9cffb37a989ca544e6bb780a2c78901d3fb33738768511a30617afa01d",
        "463eb28e72f82e0a96c0a4cc53690c571281131f672aa229e0d45ae59b598b59",
        "da2ae4d6b36748f2a318f23e7ab1dfdf45acdc9d049bd80e59de82a60895f562",
        "2fe741af801cc238602ac0ec6a7b0c3a8a87c7fc7d7f02a3fe03d1c12eac4d8f",
        "29af2686fd53374a36b0846694cc342177e428d1647515f078784d69cdb9e488",
        "fdeab9acf3710362bd2658cdc9a29e8f9c757fcf9811603a8c447cd1d9151108",
        "4bfd2c8b6f1eec7a2afeb48b934ee4b2694182027e6d0fc075074f2fabb31781",
        "da18797ed7c3a777f0847f429724a2d8cd5138e6ed2895c3fa1a6d39d18f7ec6",
        "f52b23db1fbb6ded89ef42a23ce0c8922c45f25c50b568a93bf1c075420bbb7c",
        "92ca0fa6651ee2f97b884b7246a562fa71250fedefe5ebf270d31c546bfea976",
        "471fb943aa23c511f6f72f8d1652d9c880cfa392ad80503120547703e56a2be5",
        "5099c6a56203f9687f7d33f4bfdf576d31dc91f6b695ecea38b2770c87631135",
        "4e4c294b331f7a2099a379bec34b9f9fc03dc46ab465d998f4d683da53487e6d",
    ]
    for i in range(len(lengths)):
        assert_equal(sha256_hex(Span(_pattern(lengths[i]))), digests[i])


def test_parts_give_the_same_digest() raises:
    var data = _pattern(300)
    var whole = sha256_hex(Span(data))
    for first in [0, 1, 63, 64, 65, 128, 299, 300]:
        for second in [0, 1, 64, 100]:
            if first + second > len(data):
                continue
            var hash = Sha256()
            hash.update(Span(data)[:first])
            hash.update(Span(data)[first : first + second])
            hash.update(Span(data)[first + second :])
            assert_equal(hash^.hexdigest(), whole)


def test_digest_bytes() raises:
    var hash = Sha256()
    hash.update(Span(_bytes("abc")))
    var digest = hash^.digest()
    assert_equal(Int(digest[0]), 0xBA)
    assert_equal(Int(digest[31]), 0xAD)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
