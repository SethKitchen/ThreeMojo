# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Seeded uniform and normal numbers by xorshift64."""

from extensions.numerics.noise import Xorshift64
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)


def test_first_step() raises:
    # From 1: 1 ^ 1 << 13 = 8193, ^ >> 7 = 8257, ^ << 17 = 8257 * 131073.
    var noise = Xorshift64(1)
    var u = noise.uniform()
    assert_equal(noise.state, UInt64(1082269761))
    assert_equal(u, (528452.0 + 0.5) / 9007199254740992.0)


def test_one_seed_gives_one_sequence() raises:
    var a = Xorshift64(20261115)
    var b = Xorshift64(20261115)
    for _ in range(100):
        assert_equal(a.uniform(), b.uniform())
    assert_equal(a.normal(), b.normal())


def test_moments() raises:
    var noise = Xorshift64(7)
    var n = 20000
    var sum = 0.0
    for _ in range(n):
        var u = noise.uniform()
        assert_true(u > 0 and u < 1)
        sum += u
    assert_almost_equal(sum / Float64(n), 0.5, atol=0.01)
    var mean = 0.0
    var square = 0.0
    for _ in range(n):
        var z = noise.normal()
        mean += z / Float64(n)
        square += z * z / Float64(n)
    assert_almost_equal(mean, 0.0, atol=0.03)
    assert_almost_equal(square, 1.0, atol=0.04)


def test_zero_seed() raises:
    with assert_raises(contains="must not be 0"):
        _ = Xorshift64(0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
