# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The system zlib gives the bytes and checksums Python's `zlib` gave."""

from std.testing import TestSuite, assert_equal, assert_raises

from render.inflate import zlib_inflate
from tools._zlib import compress, crc32


def _data() -> List[UInt8]:
    var data = List[UInt8]()
    for _ in range(40):
        for value in range(256):
            data.append(UInt8(value))
    return data^


def _hex(data: List[UInt8], count: Int) -> String:
    comptime digits = "0123456789abcdef"
    var out = String()
    for index in range(count):
        out += chr(Int(digits.as_bytes()[Int(data[index] >> 4)]))
        out += chr(Int(digits.as_bytes()[Int(data[index] & 15)]))
    return out^


def test_compress_matches_python_and_round_trips() raises:
    var data = _data()
    var stream = compress(data)
    # zlib.compress(bytes(range(256)) * 40, 6), CPython 3.12, zlib 1.3.
    assert_equal(
        _hex(stream, 40),
        "789c6360646266616563e7e0e4e2e6e1e5e317101412161115139790949296919593575054525651",
    )
    assert_equal(len(stream), 372)
    assert_equal(len(compress(data, 9)), 372)
    assert_equal(zlib_inflate(stream), data)
    with assert_raises():
        _ = compress(data, 10)


def test_crc32_matches_python() raises:
    assert_equal(crc32(_data()), UInt32(3150855069))
    var abc: List[UInt8] = [97, 98, 99]
    assert_equal(crc32(abc, 12345), UInt32(3252201774))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
