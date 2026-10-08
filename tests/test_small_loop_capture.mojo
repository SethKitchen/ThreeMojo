# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Focused real witnesses for the two independently reviewed iterator rules."""
from extensions.carla.speed_limits import read_speed_number
from tests.test_small_loop_witnesses import (
    test_empty_and_split_tree_frontiers_use_real_producers,
    test_iterator_protocol_keeps_true_and_rejects_contrary_false,
)
from std.testing import TestSuite, assert_equal


def test_owned_nonempty_zero_mantissa_byte_view() raises:
    assert_equal(read_speed_number("0.000"), Float64(0))
    assert_equal(read_speed_number("-0E-1000"), Float64(0))


def test_real_tree_frontier_producers() raises:
    test_empty_and_split_tree_frontiers_use_real_producers()


def test_required_iterator_outcome_protocol() raises:
    test_iterator_protocol_keeps_true_and_rejects_contrary_false()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
