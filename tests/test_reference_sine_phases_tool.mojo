# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the independent phase fixture and its Float32 neighbor selection."""

from std.collections import Set
from std.math import sin
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_true

from tools._bigint import BigInt
from tools.reference_sine_phases import EXPONENTS, Fixed, generate, run


def test_the_saved_block_matches_at_two_precisions() raises:
    var outcome = run(".", False)
    assert_equal(outcome[0], 0, outcome[1])
    assert_equal(
        outcome[1],
        (
            "Verified 72 targets, 288 positive neighbors, both signs tested in"
            " Mojo; 140/200-digit agreement\n"
        ),
    )


def test_exact_binary32_decoding_and_ties_to_even() raises:
    var scale = Fixed.of(140)
    assert_true(scale.exact_float32(0x3F800000) == scale.one())
    assert_true(scale.exact_float32(0xC0000000) == -(scale.one() << 1))
    assert_true(scale.exact_float32(1) == BigInt(1) << (scale.bits - 149))
    assert_true(
        scale.exact_float32(0x80000001) == -(BigInt(1) << (scale.bits - 149))
    )
    for lower in [0x3F800000, 0x3F800001]:
        var midpoint = (
            scale.exact_float32(lower) + scale.exact_float32(lower + 1)
        ) >> 1
        var expected = lower + (lower & 1)
        assert_equal(scale.rounded_bits(midpoint), expected)
        assert_equal(scale.rounded_bits(-midpoint), expected | 0x80000000)


def test_neighbors_bracket_targets_and_cover_every_quadrant() raises:
    var groups = generate(140)
    assert_equal(len(groups), 72)
    var scale = Fixed.of(140)
    var half_pi = scale.pi() >> 1
    comptime exponents = EXPONENTS
    for exponent in materialize[exponents]():
        var quadrants = Set[Int]()
        var signs = Set[Int]()
        for group in groups:
            if group.exponent != exponent:
                continue
            var target = group.multiple * half_pi
            if group.midpoint:
                target = target + (half_pi >> 1)
            var first = group.rows[0].bits
            for index in range(4):
                assert_equal(group.rows[index].bits, first + index)
                quadrants.add(group.rows[index].quadrant)
                signs.add(group.rows[index].remainder >> 31)
            assert_true(scale.exact_float32(group.rows[1].bits) < target)
            assert_true(scale.exact_float32(group.rows[2].bits) > target)
        assert_equal(len(quadrants), 4)
        assert_equal(len(signs), 2)


def test_the_taylor_reference_agrees_with_the_host_sine() raises:
    for group in generate(140):
        for row in group.rows:
            var value = Float64(bitcast[DType.float32](UInt32(row.bits)))
            var expected = Float64(bitcast[DType.float32](UInt32(row.sine)))
            assert_true(abs(expected - sin(value)) <= 3e-8)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
