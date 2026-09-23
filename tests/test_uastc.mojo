# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.uastc`: endpoint unquantization, blocks built bit by
bit, and every block the decoder refuses.

`tests/test_ktx2.mojo` decodes files the Basis Universal encoder wrote,
which use all nineteen modes, and compares them with three.js's
transcoder."""

from render.uastc import (
    UastcTables,
    uastc_block,
    uastc_image,
    unquantize_endpoint,
)
from std.testing import TestSuite, assert_equal, assert_raises


def block(fields: List[Tuple[Int, Int]]) -> List[UInt8]:
    """Return a 16-byte block of (value, bits) fields, low bit first."""
    var out = List[UInt8](length=16, fill=0)
    var at = 0
    for field in fields:
        for bit in range(field[1]):
            out[(at + bit) >> 3] |= UInt8(
                ((field[0] >> bit) & 1) << ((at + bit) & 7)
            )
        at += field[1]
    return out^


def test_endpoints_unquantize_as_astc_says() raises:
    # Bits only: the bits repeat down to eight.
    assert_equal(unquantize_endpoint(200, 20), 200)
    assert_equal(unquantize_endpoint(10, 8), 170)
    assert_equal(unquantize_endpoint(5, 5), 182)
    # A trit and two bits: the twelve ASTC levels, in stored order.
    var twelve: List[Int] = [
        0, 255, 69, 186, 23, 232, 92, 163, 46, 209, 116, 139,
    ]  # fmt: skip
    for value in range(12):
        assert_equal(unquantize_endpoint(value, 7), twelve[value])
    # A quint and three bits, and a trit and six bits.
    assert_equal(unquantize_endpoint(7, 12), 158)
    assert_equal(unquantize_endpoint(39, 12), 132)
    assert_equal(unquantize_endpoint(63, 19), 131)
    assert_equal(unquantize_endpoint(191, 19), 129)


def test_a_solid_block_is_one_color() raises:
    # Mode 8's prefix code, then red, green, blue and alpha.
    var data = block([(0x17, 5), (10, 8), (20, 8), (30, 8), (40, 8)])
    var texels = uastc_block(data, 0, UastcTables())
    for texel in range(16):
        assert_equal(texels[texel * 4], 10)
        assert_equal(texels[texel * 4 + 3], 40)


def test_malformed_blocks_are_refused() raises:
    var tables = UastcTables()
    with assert_raises(contains="reserved mode"):
        _ = uastc_block(block([(0x45, 7)]), 0, tables)
    # Modes 2, 3 and 7 name a partition past the end of their table,
    # after their prefix code and fifteen hint bits.
    var codes: List[Int] = [0x1D, 0x3, 0x7]
    var partitions: List[Int] = [30, 11, 19]
    var widths: List[Int] = [5, 4, 5]
    for index in range(3):
        var data = block(
            [(codes[index], 5), (0, 15), (partitions[index], widths[index])]
        )
        with assert_raises(contains="partition"):
            _ = uastc_block(data, 0, tables)
    with assert_raises(contains="one block per 4x4 texels"):
        _ = uastc_image(5, 4, List[UInt8](length=16, fill=0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
