# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Random clip factories validate counts before generating their keys."""

from animation.animation_clip_creator import (
    _key_count,
    create_pulsation_animation,
    create_shake_animation,
)
from core.object3d import NodeId
from math.utils import SeededRandom
from math.vector3 import Vector3
from std.math import inf, nan
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_raises
from units.si import Duration, SECOND


def test_counts_keep_the_existing_float32_boundary_rule() raises:
    var durations: List[Float32] = [
        -1,
        0,
        0.01,
        0.1,
        0.10000001,
        0.2,
        0.21,
        0.35,
        1,
    ]
    var expected: List[Int] = [0, 0, 1, 1, 2, 2, 3, 4, 10]
    for at in range(len(durations)):
        assert_equal(_key_count(Duration(durations[at], SECOND)), expected[at])
    # Count only: do not allocate a million seconds of track data.
    assert_equal(_key_count(Duration(1e6, SECOND)), 10000000)


def test_invalid_counts_do_not_advance_the_random_generator() raises:
    var boundary = Float32(Int.MAX // 3) / 10
    for value in [
        inf[DType.float32](),
        -inf[DType.float32](),
        nan[DType.float32](),
        Float32(1e30),
        Float32(1e38),
        boundary,
    ]:
        var random = SeededRandom(7)
        var before = random.state
        with assert_raises(contains="key count"):
            _ = create_shake_animation(
                NodeId(0), Duration(value, SECOND), Vector3(1, 1, 1), random
            )
        assert_equal(random.state, before)
        with assert_raises(contains="key count"):
            _ = create_pulsation_animation(
                NodeId(0), Duration(value, SECOND), 1, random
            )
        assert_equal(random.state, before)


def test_representable_boundary_is_counted_without_allocating() raises:
    var boundary = Float32(Int.MAX // 3) / 10
    var below = bitcast[DType.float32](bitcast[DType.uint32](boundary) - 1)
    var count = _key_count(Duration(below, SECOND))
    assert_equal(count, Int(below * 10))
    assert_equal(count > Int.MAX // 6, True)
    assert_equal(count <= Int.MAX // 3, True)


def test_nonpositive_duration_keeps_the_empty_track_error() raises:
    for value in [Float32(0), Float32(-0.0), Float32(-1), Float32(-1e38)]:
        var random = SeededRandom(7)
        var before = random.state
        assert_equal(_key_count(Duration(value, SECOND)), 0)
        with assert_raises(contains="at least one key"):
            _ = create_shake_animation(
                NodeId(0), Duration(value, SECOND), Vector3(1, 1, 1), random
            )
        assert_equal(random.state, before)
        with assert_raises(contains="at least one key"):
            _ = create_pulsation_animation(
                NodeId(0), Duration(value, SECOND), 1, random
            )
        assert_equal(random.state, before)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
