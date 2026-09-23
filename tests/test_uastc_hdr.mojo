# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.uastc_hdr`: the unquantization tables, the conversions
to half floats, void-extent blocks built bit by bit, and every block the
decoder refuses.

`tests/test_ktx2.mojo` decodes a file of ASTC blocks that use every
endpoint mode, partition count, grid and range a 4x4 block can use, and a
file the Basis Universal encoder wrote, and compares them with three.js's
transcoder."""

from render.uastc import bise_ranges
from render.uastc_hdr import (
    AstcTables,
    EndpointMode,
    decode_endpoints,
    partition_of,
    qlog16_to_half,
    sequence_bits,
    uastc_hdr_block,
    uastc_hdr_image,
    unorm16_to_half,
    unquantize_weight,
)
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


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


def void_extent(hdr: Int, colors: List[Int]) -> List[UInt8]:
    """Return a void-extent block of one color over the whole image."""
    var fields: List[Tuple[Int, Int]] = [(0x1FC, 9), (hdr, 1), (3, 2)]
    for _ in range(4):
        fields.append((0x1FFF, 13))
    for color in colors:
        fields.append((color, 16))
    return block(fields)


def test_weights_unquantize_as_astc_says() raises:
    var ranges = bise_ranges()
    var tables = AstcTables()
    # Bits only, a lone trit, and a lone quint.
    assert_equal(tables.weights[0], [0, 64])
    assert_equal(tables.weights[1], [0, 32, 64])
    assert_equal(tables.weights[3], [0, 16, 32, 48, 64])
    assert_equal(tables.weights[2], [0, 21, 43, 64])
    # A bit and a trit, in stored order: the digit above the bit.
    assert_equal(tables.weights[4], [0, 64, 12, 52, 25, 39])
    # Two bits and a quint, and three bits and a trit.
    assert_equal(unquantize_weight(0b01, 9, ranges), 64)
    assert_equal(unquantize_weight(0b0110, 9, ranges), 19)
    assert_equal(unquantize_weight(0b01010, 10, ranges), 11)
    # Endpoints come from `render.uastc`, from range 4 up.
    assert_equal(len(tables.endpoints[3]), 0)
    assert_equal(len(tables.endpoints[4]), 6)
    assert_equal(len(tables.endpoints[20]), 256)
    assert_equal(len(tables.weights[12]), 0)
    # Five trits take eight bits, and three quints take seven.
    assert_equal(sequence_bits(5, 1, ranges), 8)
    assert_equal(sequence_bits(3, 3, ranges), 7)
    assert_equal(sequence_bits(4, 4, ranges), 4 + 7)


def test_halves_come_from_the_log_encoding() raises:
    # 0x7800 is one; the mantissa maps in three linear pieces.
    assert_equal(qlog16_to_half(0x7800), 0x3C00)
    assert_equal(qlog16_to_half(0x7800 + 511), 0x3C00 + (3 * 511 >> 3))
    assert_equal(qlog16_to_half(0x7800 + 512), 0x3C00 + (4 * 512 - 512 >> 3))
    assert_equal(qlog16_to_half(0x7800 + 1536), 0x3C00 + (5 * 1536 - 2048 >> 3))
    assert_equal(qlog16_to_half(0), 0)


def test_ldr_values_truncate_to_halves() raises:
    # Out of 65536: subnormal halves below 2^-14, then normal ones.
    assert_equal(unorm16_to_half(0), 0)
    assert_equal(unorm16_to_half(1), 0x0100)
    assert_equal(unorm16_to_half(3), 0x0300)
    assert_equal(unorm16_to_half(4), 0x0400)
    assert_equal(unorm16_to_half(1000), (8 << 10) | 976)
    assert_equal(unorm16_to_half(0x8000), 0x3800)
    # 65534 / 65536 truncates to the half below one.
    assert_equal(unorm16_to_half(0xFFFE), 0x3BFF)


def test_partitions_follow_the_hash() raises:
    # Every texel lands in a partition the block has, and the seeds
    # between them use every one.
    for partitions in range(2, 5):
        var seen = List[Bool](length=4, fill=False)
        for seed in range(64):
            for texel in range(16):
                var part = partition_of(seed, texel & 3, texel >> 2, partitions)
                assert_true(part >= 0 and part < partitions)
                seen[part] = True
        for part in range(partitions):
            assert_true(seen[part])


def test_endpoint_modes_decode_as_astc_says() raises:
    # Luminance, direct: alpha is one.
    assert_equal(
        decode_endpoints(EndpointMode(0), [10, 200]),
        [10, 10, 10, 255, 200, 200, 200, 255],
    )
    # HDR luminance, large range, in order and swapped.
    assert_equal(decode_endpoints(EndpointMode(2), [1, 2])[0], 16)
    assert_equal(decode_endpoints(EndpointMode(2), [2, 1])[0], 24)
    # RGB direct, and its blue contraction when the sum falls.
    assert_equal(
        decode_endpoints(EndpointMode(8), [0, 100, 0, 100, 0, 100]),
        [0, 0, 0, 255, 100, 100, 100, 255],
    )
    assert_equal(
        decode_endpoints(EndpointMode(8), [100, 0, 100, 0, 100, 0]),
        [0, 0, 0, 255, 100, 100, 100, 255],
    )
    # A mode outside the sixteen, and values of the wrong count.
    assert_false(EndpointMode(16).is_valid())
    assert_false(EndpointMode(-1).is_valid())
    assert_true(EndpointMode(12).is_ldr())
    assert_false(EndpointMode(14).is_ldr())
    assert_equal(String(EndpointMode(7)), "EndpointMode(7)")
    with assert_raises(contains="EndpointMode(16) is not a mode"):
        _ = decode_endpoints(EndpointMode(16), [0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
    with assert_raises(contains="wrong count"):
        _ = decode_endpoints(EndpointMode(4), [0, 0])


def test_a_void_extent_is_one_color() raises:
    var tables = AstcTables()
    # LDR: all ones is exactly one, the rest truncate.
    var ldr = uastc_hdr_block(
        void_extent(0, [0xFFFF, 0x8000, 0, 1000]), 0, tables
    )
    for texel in range(16):
        assert_equal(ldr[texel * 4], 0x3C00)
        assert_equal(ldr[texel * 4 + 1], 0x3800)
        assert_equal(ldr[texel * 4 + 2], 0)
        assert_equal(ldr[texel * 4 + 3], (8 << 10) | 976)
    # HDR: the halves as they are.
    var hdr = uastc_hdr_block(
        void_extent(1, [0x4000, 0x3C00, 0x7BFF, 0x0001]), 0, tables
    )
    assert_equal(hdr[60], 0x4000)
    assert_equal(hdr[63], 0x0001)
    # An extent that is not all ones must order its ends.
    var ordered = block(
        [(0x1FC, 9), (0, 1), (3, 2), (1, 13), (2, 13), (3, 13), (4, 13)]
    )
    assert_equal(uastc_hdr_block(ordered, 0, tables)[0], 0)


def test_malformed_blocks_are_refused() raises:
    var tables = AstcTables()
    # Four zero bits, and a reserved pattern of the high layouts.
    with assert_raises(contains="reserved block mode"):
        _ = uastc_hdr_block(block([]), 0, tables)
    with assert_raises(contains="reserved block mode"):
        _ = uastc_hdr_block(block([(4, 6), (7, 3)]), 0, tables)
    # Void extents: reserved bits, an empty extent, and an infinity.
    with assert_raises(contains="reserved bits"):
        _ = uastc_hdr_block(block([(0x1FC, 9), (0, 1), (1, 2)]), 0, tables)
    var empty = block(
        [(0x1FC, 9), (0, 1), (3, 2), (5, 13), (5, 13), (0, 13), (1, 13)]
    )
    with assert_raises(contains="empty extent"):
        _ = uastc_hdr_block(empty, 0, tables)
    with assert_raises(contains="infinity or a NaN"):
        _ = uastc_hdr_block(void_extent(1, [0, 0, 0x7C00, 0]), 0, tables)
    # A 12x2 grid, which a 4x4 block cannot hold.
    with assert_raises(contains="larger than 4x4"):
        _ = uastc_hdr_block(block([(4, 4), (0, 5)]), 0, tables)
    # A 2x2 grid of one-bit weights: four bits.
    with assert_raises(contains="weight bits"):
        _ = uastc_hdr_block(block([(0x10D, 9)]), 0, tables)
    # Dual planes with four partitions.
    var dual = 1 | (1 << 9) | (1 << 10) | (3 << 11)
    with assert_raises(contains="four partitions"):
        _ = uastc_hdr_block(block([(dual, 13)]), 0, tables)
    # Three partitions of mixed modes on 96 bits of dual-plane weights.
    var crowded = 2 | 32 | 512 | 1024 | (2 << 11)
    with assert_raises(contains="no room"):
        _ = uastc_hdr_block(block([(crowded, 13), (0, 10), (1, 6)]), 0, tables)
    # Four partitions of mode 15: 32 endpoint values.
    var many = 1 | 2 | 16 | (3 << 11)
    with assert_raises(contains="more than 18"):
        _ = uastc_hdr_block(block([(many, 13), (0, 10), (60, 6)]), 0, tables)
    # Four partitions of mode 4 in the 19 bits 80 bits of weights leave.
    var tight = 1 | 2 | 16 | 64 | 512 | (3 << 11)
    with assert_raises(contains="reserved range"):
        _ = uastc_hdr_block(block([(tight, 13), (0, 10), (16, 6)]), 0, tables)
    with assert_raises(contains="one block per 4x4 texels"):
        _ = uastc_hdr_image(5, 4, List[UInt8](length=16, fill=0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
