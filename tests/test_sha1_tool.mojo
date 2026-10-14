# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `tools._sha1`.

The vectors are FIPS 180-4's examples and values from Python's `hashlib`
over the pattern `i % 251`, at the lengths where the padding moves to a
second block.
"""

from std.testing import TestSuite, assert_equal

from tools._sha1 import Sha1, git_blob_sha1, sha1_hex


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
        sha1_hex(Span(_bytes("abc"))),
        "a9993e364706816aba3e25717850c26c9cd0d89d",
    )
    assert_equal(
        sha1_hex(
            Span(
                _bytes(
                    "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
                )
            )
        ),
        "84983e441c3bd26ebaae4aa1f95129e5e54670f1",
    )
    var million = List[UInt8](length=1000000, fill=97)
    assert_equal(
        sha1_hex(Span(million)), "34aa973cd4c4daa4f61eeb2bdbad27316534016f"
    )


def test_padding_boundaries_match_hashlib() raises:
    var lengths = [0, 1, 55, 56, 57, 63, 64, 65, 119, 120, 127, 128, 129, 1000]
    var digests = [
        "da39a3ee5e6b4b0d3255bfef95601890afd80709",
        "5ba93c9db0cff93f52b521d7420e43f6eda2784f",
        "8ae2d46729cfe68ff927af5eec9c7d1b66d65ac2",
        "636e2ec698dac903498e648bd2f3af641d3c88cb",
        "7cb1330f35244b57437539253304ea78a6b7c443",
        "6d942da0c4392b123528f2905c713a3ce28364bd",
        "c6138d514ffa2135bfce0ed0b8fac65669917ec7",
        "69bd728ad6e13cd76ff19751fde427b00e395746",
        "41c89d06001bab4ab78736b44efe7ce18ce6ae08",
        "d3dbd653bd8597b7475321b60a36891278e6a04a",
        "89d7312a903f65cd2b3e34a975e55dbea9033353",
        "e6434bc401f98603d7eda504790c98c67385d535",
        "3352e41cc30b40ae80108970492b21014049e625",
        "c9c960a0b925474fab83942cc27d504fc24ac37b",
    ]
    for i in range(len(lengths)):
        assert_equal(sha1_hex(Span(_pattern(lengths[i]))), digests[i])


def test_parts_give_the_same_digest() raises:
    var data = _pattern(300)
    for split in [0, 1, 63, 64, 65, 200, 300]:
        var hash = Sha1()
        hash.update(Span(data)[:split])
        hash.update(Span(data)[split:])
        assert_equal(hash^.hexdigest(), sha1_hex(Span(data)))


def test_git_blob_names() raises:
    # `git hash-object` of an empty file, and of a short one.
    assert_equal(
        git_blob_sha1(Span(List[UInt8]())),
        "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391",
    )
    assert_equal(
        git_blob_sha1(Span(_bytes("pinned source"))),
        "900a09fb895b57fb3c2c5d96a84a385a1979da72",
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
