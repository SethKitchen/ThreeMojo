# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `materials.tsl_bits`: 32-bit words, `hash`, the bitcasts, the
bit counts and the packings.

Each expected value is three.js's, worked out on 32-bit integers in
`assets/tsl/tsl_reference.py` or by hand, and read back through the
compiled program, so a test checks the builder and the interpreter
together.
"""

from materials.nodes import (
    FRAGMENT_NODE,
    NODE_FLOAT,
    NODE_VEC2,
    NODE_VEC3,
    NodeGraph,
    NodeInputs,
    NodeRef,
    ProgramSource,
    run_nodes,
)
from materials.tsl_bits import (
    NodeWord,
    count_leading_zeros,
    count_one_bits,
    count_trailing_zeros,
    dot4_i8_packed,
    dot4_u8_packed,
    exp2_whole,
    float_bits_to_int,
    float_bits_to_uint,
    hash,
    int_bits_to_float,
    pack4x_i8,
    pack4x_i8_clamp,
    pack4x_u8,
    pack4x_u8_clamp,
    pack_half_2x16,
    pack_snorm_2x16,
    pack_snorm_4x8,
    pack_unorm_2x16,
    pack_unorm_4x8,
    uint_bits_to_float,
    unpack4x_i8,
    unpack4x_u8,
    unpack_half_2x16,
    unpack_snorm_2x16,
    unpack_snorm_4x8,
    unpack_unorm_2x16,
    unpack_unorm_4x8,
    word,
    word_add,
    word_bit_and,
    word_bit_or,
    word_bit_xor,
    word_constant,
    word_mul,
    word_shift_left,
    word_shift_right,
    word_to_int,
    word_to_uint,
)
from math.vector3 import Vector3
from std.math import isinf, isnan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

comptime Lanes = SIMD[DType.float32, 4]


def value_of(mut g: NodeGraph, node: NodeRef) raises -> Lanes:
    """Return a node's value, padded to a `vec4`, through the fragment
    output."""
    var type = g.type_of(node)
    var shown = node
    if type == NODE_FLOAT:
        shown = g.join([node, g.vec3(0, 0, 0)])
    elif type == NODE_VEC2:
        shown = g.join([node, g.vec2(0, 0)])
    elif type == NODE_VEC3:
        shown = g.join([node, g.float(0)])
    g.set_output(FRAGMENT_NODE, shown)
    var program = g.compile()
    var none = Vector3(0, 0, 0)
    return run_nodes(
        ProgramSource(Pointer(to=program)),
        FRAGMENT_NODE,
        NodeInputs(0, 0, none, none, none, none, False),
    )


def assert_word(mut g: NodeGraph, w: NodeWord, low: Int, high: Int) raises:
    """Assert a word's two halves exactly."""
    var got = value_of(g, w.halves)
    assert_equal(got[0], Float32(low))
    assert_equal(got[1], Float32(high))


def test_a_word_holds_32_bits_in_two_halves() raises:
    var g = NodeGraph()
    assert_word(g, word_constant(g, 0xDEADBEEF), 0xBEEF, 0xDEAD)
    # uint(x) drops the fraction and wraps a negative number.
    assert_word(g, word(g, g.float(70000.7)), 4464, 1)
    assert_word(g, word(g, g.float(-1)), 65535, 65535)
    assert_word(g, word(g, g.float(-65536)), 0, 65535)
    # Read back as a number: rounded once to a float, signed or not.
    assert_equal(
        value_of(g, word_to_uint(g, word_constant(g, 0x80000001)))[0],
        Float32(2147483648.0),
    )
    assert_equal(
        value_of(g, word_to_uint(g, word_constant(g, 0x0012D687)))[0],
        Float32(1234567),
    )
    assert_equal(
        value_of(g, word_to_int(g, word_constant(g, 0xFFFFFFFE)))[0], -2
    )
    assert_equal(
        value_of(g, word_to_int(g, word_constant(g, 0x00012345)))[0], 74565
    )


def test_a_word_refuses_what_is_not_a_word() raises:
    var g = NodeGraph()
    var nowhere = NodeWord(NodeRef(-1))
    assert_false(nowhere.is_valid())
    assert_true(word_constant(g, 1).is_valid())
    with assert_raises(contains="reads a word that names no node"):
        _ = word_to_uint(g, nowhere)
    with assert_raises(contains="A word's add reads a vec2, not a float"):
        _ = word_add(g, NodeWord(g.float(1)), word_constant(g, 1))
    with assert_raises(contains="uint reads a float, not a vec2"):
        _ = word(g, g.vec2(1, 2))
    with assert_raises(contains="shiftRight count reads a float, not a vec2"):
        _ = word_shift_right(g, word_constant(g, 1), g.vec2(1, 2))
    with assert_raises(contains="shiftLeft count reads a float, not a vec2"):
        _ = word_shift_left(g, word_constant(g, 1), g.vec2(1, 2))


def test_word_arithmetic_wraps_at_32_bits() raises:
    var g = NodeGraph()
    var a = word_constant(g, 0xDEADBEEF)
    var b = word_constant(g, 0x12345678)
    assert_word(
        g, word_add(g, word_constant(g, 0xFFFFFFFF), word_constant(g, 2)), 1, 0
    )
    assert_word(
        g, word_add(g, word_constant(g, 0xFFFF), word_constant(g, 1)), 0, 1
    )
    # 0xDEADBEEF * 0x12345678 is 0x5621CA08 modulo 2 ** 32.
    assert_word(g, word_mul(g, a, b), 51720, 22049)
    assert_word(
        g,
        word_mul(g, word_constant(g, 0xFFFFFFFF), word_constant(g, 0xFFFFFFFF)),
        1,
        0,
    )
    assert_word(g, word_bit_and(g, a, b), 5736, 4644)
    assert_word(g, word_bit_or(g, a, b), 65279, 57021)
    assert_word(g, word_bit_xor(g, a, b), 59543, 52377)


def test_a_word_shifts_across_its_halves() raises:
    var g = NodeGraph()
    var edge = word_constant(g, 0x80000001)
    assert_word(g, word_shift_right(g, edge, g.float(0)), 1, 32768)
    assert_word(g, word_shift_right(g, edge, g.float(1)), 0, 16384)
    assert_word(g, word_shift_right(g, edge, g.float(16)), 32768, 0)
    assert_word(g, word_shift_right(g, edge, g.float(20)), 2048, 0)
    assert_word(g, word_shift_right(g, edge, g.float(31)), 1, 0)
    # A GPU reads the count's low five bits: 33 is one.
    assert_word(g, word_shift_right(g, edge, g.float(33)), 0, 16384)
    var mixed = word_constant(g, 0x12345678)
    assert_word(g, word_shift_right(g, mixed, g.float(4)), 17767, 291)
    assert_word(g, word_shift_left(g, mixed, g.float(0)), 22136, 4660)
    assert_word(g, word_shift_left(g, mixed, g.float(1)), 44272, 9320)
    assert_word(g, word_shift_left(g, mixed, g.float(4)), 26496, 9029)
    assert_word(g, word_shift_left(g, mixed, g.float(16)), 0, 22136)
    assert_word(g, word_shift_left(g, mixed, g.float(20)), 0, 26496)
    assert_word(g, word_shift_left(g, mixed, g.float(31)), 0, 0)
    assert_word(g, word_shift_left(g, edge, g.float(1)), 2, 0)


def test_hash_gives_three_js_bits() raises:
    # PCG's hash on 32-bit integers, from `tsl_reference.py`.
    var seeds: List[Float32] = [0, 1, 7, 12345, 16777215]
    var expected: List[Float32] = [
        0.030199997127056122,
        0.6591631174087524,
        0.49376022815704346,
        0.9545696377754211,
        0.16074468195438385,
    ]
    for index in range(len(seeds)):
        var g = NodeGraph()
        assert_almost_equal(
            value_of(g, hash(g, g.float(seeds[index])))[0],
            expected[index],
            atol=1e-7,
        )
    var bad = NodeGraph()
    with assert_raises(contains="hash reads a float, not a vec2"):
        _ = hash(bad, bad.vec2(1, 2))


def test_exp2_whole_is_exact() raises:
    var g = NodeGraph()
    var low = value_of(g, exp2_whole(g, g.vec4(-126, 0, 1, 127)))
    assert_equal(low[0], Float32(1.1754943508222875e-38))
    assert_equal(low[1], 1)
    assert_equal(low[2], 2)
    assert_equal(low[3], Float32(1.7014118346046923e38))
    var mid = value_of(g, exp2_whole(g, g.vec4(-1, 10, 64, -100)))
    assert_equal(mid[0], 0.5)
    assert_equal(mid[1], 1024)
    assert_equal(mid[2], Float32(18446744073709551616.0))
    assert_equal(mid[3], Float32(7.888609052210118e-31))


def test_a_float_bitcast_is_ieee_754() raises:
    var g = NodeGraph()
    assert_word(g, float_bits_to_uint(g, g.float(1)), 0, 16256)
    assert_word(g, float_bits_to_uint(g, g.float(-2.5)), 0, 49184)
    assert_word(g, float_bits_to_uint(g, g.float(0.1)), 52429, 15820)
    assert_word(g, float_bits_to_uint(g, g.float(8)), 0, 16640)
    # Just below a power of two: log2 alone could round up.
    assert_word(g, float_bits_to_uint(g, g.float(0.99999994)), 65535, 16255)
    assert_word(g, float_bits_to_uint(g, g.float(3.0e38)), 45542, 32609)
    assert_word(g, float_bits_to_uint(g, g.float(1.1754944e-38)), 0, 128)
    assert_word(g, float_bits_to_int(g, g.float(123456.789)), 8293, 18417)
    # Zero keeps its sign, a subnormal is flushed, and infinity is 255.
    assert_word(g, float_bits_to_uint(g, g.float(0)), 0, 0)
    assert_word(g, float_bits_to_uint(g, g.float(-0.0)), 0, 32768)
    assert_word(g, float_bits_to_uint(g, g.float(1e-40)), 0, 0)
    var infinity = g.div(g.float(1), g.float(0))
    assert_word(g, float_bits_to_uint(g, infinity), 0, 32640)
    assert_word(g, float_bits_to_uint(g, g.negate(infinity)), 0, 65408)
    with assert_raises(contains="floatBitsToUint reads a float, not a vec2"):
        _ = float_bits_to_uint(g, g.vec2(1, 2))


def bits_of(value: UInt32) raises -> Float32:
    """Return what `uint_bits_to_float` makes of a constant word."""
    var g = NodeGraph()
    return value_of(g, uint_bits_to_float(g, word_constant(g, value)))[0]


def test_bits_are_read_back_as_a_float() raises:
    assert_equal(bits_of(0x3F800000), 1)
    assert_equal(bits_of(0xC0200000), -2.5)
    assert_equal(bits_of(0x3DCCCCCD), Float32(0.1))
    assert_equal(bits_of(0x7F61B1E6), Float32(3.0e38))
    assert_equal(bits_of(0x00800000), Float32(1.1754944e-38))
    assert_equal(bits_of(0x47F12065), Float32(123456.789))
    # An exponent of zero is a zero; 255 is infinity or NaN.
    assert_equal(bits_of(0x00000001), 0)
    assert_equal(bits_of(0x80000000), 0)
    assert_true(isinf(bits_of(0x7F800000)))
    assert_true(bits_of(0xFF800000) < 0)
    assert_true(isnan(bits_of(0x7FC00000)))
    var g = NodeGraph()
    assert_equal(
        value_of(g, int_bits_to_float(g, word_constant(g, 0x40490FDB)))[0],
        Float32(3.1415927),
    )
    with assert_raises(contains="uintBitsToFloat reads a vec2, not a vec3"):
        _ = uint_bits_to_float(g, NodeWord(g.vec3(1, 2, 3)))


def test_the_bit_counts_follow_three_js() raises:
    var g = NodeGraph()
    var ones = value_of(g, count_one_bits(g, g.vec4(0, 1, 255, -1)))
    assert_equal(ones, Lanes(0, 1, 8, 32))
    ones = value_of(g, count_one_bits(g, g.vec4(12345, 65535, 65536, 16777215)))
    assert_equal(ones, Lanes(6, 16, 1, 24))
    assert_equal(value_of(g, count_one_bits(g, g.float(7)))[0], 3)
    var leading = value_of(g, count_leading_zeros(g, g.vec4(0, 1, 65536, -1)))
    assert_equal(leading, Lanes(32, 31, 15, 0))
    leading = value_of(
        g, count_leading_zeros(g, g.vec4(255, 32768, 16777215, 3))
    )
    assert_equal(leading, Lanes(24, 16, 8, 30))
    var trailing = value_of(g, count_trailing_zeros(g, g.vec4(0, 1, 65536, 12)))
    assert_equal(trailing, Lanes(32, 0, 16, 2))
    trailing = value_of(
        g, count_trailing_zeros(g, g.vec4(-1, 256, 32768, 1048576))
    )
    assert_equal(trailing, Lanes(0, 8, 15, 20))


def test_fixed_point_packs_round_and_clamp() raises:
    var g = NodeGraph()
    # round(0.5 * 32767) is 16384, a tie to the even; -1 is -32767.
    var snorm = pack_snorm_2x16(g, g.vec2(0.5, -1))
    assert_word(g, snorm, 16384, 32769)
    var back = value_of(g, unpack_snorm_2x16(g, snorm))
    assert_almost_equal(back[0], Float32(16384.0 / 32767.0), atol=1e-7)
    assert_equal(back[1], -1)
    # The most negative half is held at -1.
    assert_equal(
        value_of(g, unpack_snorm_2x16(g, word_constant(g, 0x8000)))[0], -1
    )
    var unorm = pack_unorm_2x16(g, g.vec2(0.25, 2))
    assert_word(g, unorm, 16384, 65535)
    back = value_of(g, unpack_unorm_2x16(g, unorm))
    assert_almost_equal(back[0], Float32(16384.0 / 65535.0), atol=1e-7)
    assert_equal(back[1], 1)
    var snorm8 = pack_snorm_4x8(g, g.vec4(1, -1, 0.5, -0.25))
    assert_word(g, snorm8, 33151, 57408)
    back = value_of(g, unpack_snorm_4x8(g, snorm8))
    assert_equal(back[0], 1)
    assert_equal(back[1], -1)
    assert_almost_equal(back[2], Float32(64.0 / 127.0), atol=1e-7)
    assert_almost_equal(back[3], Float32(-32.0 / 127.0), atol=1e-7)
    var unorm8 = pack_unorm_4x8(g, g.vec4(0, 1, 0.5, 2))
    assert_word(g, unorm8, 65280, 65408)
    back = value_of(g, unpack_unorm_4x8(g, unorm8))
    assert_equal(back[1], 1)
    assert_almost_equal(back[2], Float32(128.0 / 255.0), atol=1e-7)
    with assert_raises(contains="packSnorm2x16 reads a vec2, not a vec3"):
        _ = pack_snorm_2x16(g, g.vec3(1, 2, 3))
    with assert_raises(contains="packUnorm2x16 reads a vec2, not a float"):
        _ = pack_unorm_2x16(g, g.float(1))
    with assert_raises(contains="packSnorm4x8 reads a vec4, not a vec2"):
        _ = pack_snorm_4x8(g, g.vec2(1, 2))
    with assert_raises(contains="packUnorm4x8 reads a vec4, not a vec2"):
        _ = pack_unorm_4x8(g, g.vec2(1, 2))


def half_pair(x: Float32, y: Float32) raises -> Lanes:
    """Return the halves of `pack_half_2x16` of two constants."""
    var g = NodeGraph()
    return value_of(g, pack_half_2x16(g, g.vec2(x, y)).halves)


def test_a_half_pack_rounds_to_the_nearest_half() raises:
    # Each expected half is numpy's float16, from `tsl_reference.py`.
    var got = half_pair(1, -2)
    assert_equal(got[0], 0x3C00)
    assert_equal(got[1], 0xC000)
    got = half_pair(65504, 65519)
    assert_equal(got[0], 0x7BFF)
    assert_equal(got[1], 0x7BFF)
    got = half_pair(65520, 1e-5)
    assert_equal(got[0], 0x7C00)
    assert_equal(got[1], 0xA8)
    got = half_pair(0.1, 6.1035156e-05)
    assert_equal(got[0], 0x2E66)
    assert_equal(got[1], 0x400)
    got = half_pair(-0.33333334, 5.9604645e-08)
    assert_equal(got[0], 0xB555)
    assert_equal(got[1], 1)
    # A tie goes to the even subnormal: a half step is zero, 1.5 are two.
    got = half_pair(2.9802322e-08, 8.940697e-08)
    assert_equal(got[0], 0)
    assert_equal(got[1], 2)
    got = half_pair(-0.0, 1e30)
    assert_equal(got[0], 0x8000)
    assert_equal(got[1], 0x7C00)
    var g = NodeGraph()
    with assert_raises(contains="packHalf2x16 reads a vec2, not a vec4"):
        _ = pack_half_2x16(g, g.vec4(1, 2, 3, 4))


def unpacked_halves(value: UInt32) raises -> Lanes:
    """Return `unpack_half_2x16` of a constant word."""
    var g = NodeGraph()
    return value_of(g, unpack_half_2x16(g, word_constant(g, value)))


def test_a_half_unpack_reads_ieee_754_halves() raises:
    var got = unpacked_halves(0xC0003C00)
    assert_equal(got[0], 1)
    assert_equal(got[1], -2)
    got = unpacked_halves(0x7BFF8001)
    assert_equal(got[0], Float32(-5.9604645e-08))
    assert_equal(got[1], 65504)
    got = unpacked_halves(0x7E007C00)
    assert_true(isinf(got[0]))
    assert_true(isnan(got[1]))
    got = unpacked_halves(0x00000400)
    assert_equal(got[0], Float32(6.1035156e-05))
    assert_equal(got[1], 0)


def test_packed_4x8_integers_follow_wgsl() raises:
    var g = NodeGraph()
    assert_word(g, pack4x_u8(g, g.vec4(1, 2, 300, 255)), 513, 65324)
    assert_word(g, pack4x_i8(g, g.vec4(-1, 127, -128, 5)), 32767, 1408)
    assert_word(g, pack4x_u8_clamp(g, g.vec4(-5, 300, 7, 255)), 65280, 65287)
    assert_word(g, pack4x_i8_clamp(g, g.vec4(-200, 200, -1, 0)), 32640, 255)
    var packed = word_constant(g, 0x8001FF7F)
    assert_equal(value_of(g, unpack4x_u8(g, packed)), Lanes(127, 255, 1, 128))
    assert_equal(value_of(g, unpack4x_i8(g, packed)), Lanes(127, -1, 1, -128))
    var other = word_constant(g, 0x01020304)
    assert_equal(value_of(g, dot4_u8_packed(g, packed, other))[0], 1403)
    assert_equal(value_of(g, dot4_i8_packed(g, packed, other))[0], 379)
    with assert_raises(contains="pack4xU8 reads a vec4, not a vec3"):
        _ = pack4x_u8(g, g.vec3(1, 2, 3))
    with assert_raises(contains="pack4xI8 reads a vec4, not a vec3"):
        _ = pack4x_i8(g, g.vec3(1, 2, 3))
    with assert_raises(contains="pack4xU8Clamp reads a vec4, not a vec3"):
        _ = pack4x_u8_clamp(g, g.vec3(1, 2, 3))
    with assert_raises(contains="pack4xI8Clamp reads a vec4, not a vec3"):
        _ = pack4x_i8_clamp(g, g.vec3(1, 2, 3))
    with assert_raises(contains="unpack4xU8 reads a vec2, not a float"):
        _ = unpack4x_u8(g, NodeWord(g.float(1)))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
