# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The ASTC reference generator draws the blocks of its Python original.

The reference decoder is not available in CI. The fixture comparison is in
docs/validation/raw-astc.md. The expected text is what CPython 3.12 gave.
"""

from std.testing import TestSuite, assert_equal

from tools._bigint import BigInt
from tools._python_random import PythonRandom
from tools.generate_astc import SEED, block_bytes, hex_text


def test_hex_text_matches_bytes_hex() raises:
    var bytes: List[UInt8] = [0, 1, 171, 255]
    assert_equal(hex_text(bytes, 4), "0001abff")
    assert_equal(hex_text(bytes, 2), "0001")


def test_the_first_mode_block_matches_python() raises:
    var random = PythonRandom(SEED)
    var tail = random.getrandbits(128)
    var low = BigInt(1) << 17
    var value = tail - (tail % low) + BigInt(5)
    assert_equal(
        hex_text(block_bytes(value), 16), "05004224a01cfd51edc4f13cfa81c893"
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
