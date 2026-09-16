# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `core.layers`."""

from core.layers import Layers
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def test_a_new_set_holds_layer_zero_alone() raises:
    var layers = Layers()
    assert_equal(layers.mask, UInt32(1))
    assert_true(layers.is_enabled(0))
    assert_false(layers.is_enabled(1))
    assert_false(layers.is_enabled(31))


def test_set_replaces_the_whole_set_with_one_layer() raises:
    var layers = Layers()
    layers.set(5)
    assert_true(layers.is_enabled(5))
    assert_false(layers.is_enabled(0))
    assert_equal(layers.mask, UInt32(32))


def test_enable_and_disable_change_one_layer_at_a_time() raises:
    var layers = Layers()
    layers.enable(3)
    layers.enable(31)
    assert_true(layers.is_enabled(0))
    assert_true(layers.is_enabled(3))
    assert_true(layers.is_enabled(31))
    layers.disable(0)
    assert_false(layers.is_enabled(0))
    assert_true(layers.is_enabled(3))
    # Disabling a layer that is not in the set changes nothing.
    layers.disable(7)
    assert_equal(layers.mask, (UInt32(1) << 3) | (UInt32(1) << 31))


def test_toggle_flips_one_layer() raises:
    var layers = Layers()
    layers.toggle(2)
    assert_true(layers.is_enabled(2))
    layers.toggle(2)
    assert_false(layers.is_enabled(2))
    layers.toggle(0)
    assert_equal(layers.mask, UInt32(0))


def test_all_and_none() raises:
    var layers = Layers()
    layers.enable_all()
    assert_equal(layers.mask, UInt32(0xFFFFFFFF))
    for layer in [0, 15, 31]:
        assert_true(layers.is_enabled(layer))
    layers.disable_all()
    assert_equal(layers.mask, UInt32(0))
    assert_false(layers.is_enabled(0))


def test_two_sets_overlap_when_they_share_a_layer() raises:
    var camera = Layers()
    var node = Layers()
    assert_true(camera.test(node))
    node.set(1)
    assert_false(camera.test(node))
    camera.enable(1)
    assert_true(camera.test(node))
    camera.disable_all()
    assert_false(camera.test(node))
    # Overlap is symmetric.
    assert_false(node.test(camera))


def test_a_layer_outside_the_thirty_two_is_refused() raises:
    # Each end of the range on its own; three.js would wrap 32 to 0.
    var layers = Layers()
    with assert_raises():
        layers.set(-1)
    with assert_raises():
        layers.set(32)
    with assert_raises():
        layers.enable(32)
    with assert_raises():
        layers.disable(-1)
    with assert_raises():
        layers.toggle(32)
    with assert_raises():
        _ = layers.is_enabled(-1)
    # And the set is as it was.
    assert_equal(layers.mask, UInt32(1))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
