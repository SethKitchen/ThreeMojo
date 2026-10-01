# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""The same Mulberry32 arithmetic backs core math and Clearwater."""

from extensions.water.random import Mulberry32
from math.random import mulberry32_step
from math.utils import SeededRandom
from std.testing import TestSuite, assert_equal


def test_core_and_water_streams_agree_across_state_wrap() raises:
    for seed in [0, 7, 42, -1, 0x100000007, 2463401483]:
        var core = SeededRandom(seed)
        var water = Mulberry32(seed)
        for _ in range(1024):
            assert_equal(core.next(), water.next_unit())
            assert_equal(Int(core.state), water.state)


def test_water_keeps_its_mutable_integer_state_contract() raises:
    var water = Mulberry32(0)
    for state in [-1, 0x100000007, 2463401483]:
        water.state = state
        var bits = UInt32(state & 0xFFFFFFFF)
        assert_equal(water.next_unit(), mulberry32_step(bits))
        assert_equal(water.state, Int(bits))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
