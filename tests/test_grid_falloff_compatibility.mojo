# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Preserve the original public grid falloff expression."""
from lights.light_probe_grid import grid_falloff
from math.norm import length3
from math.smoothstep import smoothstep
from math.vector3 import Vector3
from std.benchmark import black_box
from std.math import max
from std.memory import bitcast
from std.testing import TestSuite, assert_equal


def _original_grid_falloff(
    position: Vector3, low: Vector3, high: Vector3, falloff: Float32
) -> Float32:
    """Return how much of a grid a surface takes, three.js's `falloff`
    weight: one inside the box, and `1 - smoothstep( 0, falloff, d )` at
    a distance `d` outside it.

    Both backends call it.

    Args:
        position: Where the surface is, in world space.
        low: The box's lowest corner.
        high: The box's highest corner.
        falloff: How far outside the box the grid fades out, in meters.
            Zero applies the grid everywhere.

    Returns:
        The weight, from zero to one.
    """
    if falloff <= 0:
        return 1
    var dx = max(low.x - position.x, Float32(0)) + max(
        position.x - high.x, Float32(0)
    )
    var dy = max(low.y - position.y, Float32(0)) + max(
        position.y - high.y, Float32(0)
    )
    var dz = max(low.z - position.z, Float32(0)) + max(
        position.z - high.z, Float32(0)
    )
    return 1 - smoothstep(0, falloff, length3(dx, dy, dz))


def test_ordered_and_reversed_corners() raises:
    for order in range(2):
        var sign = Float32(1) if order == 0 else Float32(-1)
        var low = Vector3(-1, -2, -3) * sign
        var high = Vector3(1, 2, 3) * sign
        for x in range(-8, 9):
            var point = Vector3(Float32(x) * 0.25, 0.5, -0.75)
            for fade in range(5):
                var falloff = black_box(Float32(fade))
                assert_equal(
                    bitcast[DType.uint32](
                        grid_falloff(point, low, high, falloff)
                    ),
                    bitcast[DType.uint32](
                        _original_grid_falloff(point, low, high, falloff)
                    ),
                )


def test_exceptional_expression_bits() raises:
    var words: List[UInt32] = [
        0x00000000,
        0x80000000,
        0x3F800000,
        0xBF800000,
        0x00000001,
        0x80000001,
        0x7F7FFFFF,
        0xFF7FFFFF,
        0x7F800000,
        0xFF800000,
        0x7FC00001,
        0xFFC00001,
    ]
    for a in range(len(words)):
        for b in range(len(words)):
            for c in range(len(words)):
                var x = black_box(bitcast[DType.float32](words[a]))
                var lo = black_box(bitcast[DType.float32](words[b]))
                var hi = black_box(bitcast[DType.float32](words[c]))
                var point = Vector3(x, 0, -0.5)
                var low = Vector3(lo, -1, -1)
                var high = Vector3(hi, 1, 1)
                assert_equal(
                    bitcast[DType.uint32](grid_falloff(point, low, high, 4)),
                    bitcast[DType.uint32](
                        _original_grid_falloff(point, low, high, 4)
                    ),
                )
    for word in words:
        var falloff = black_box(bitcast[DType.float32](word))
        assert_equal(
            bitcast[DType.uint32](
                grid_falloff(
                    Vector3(2, 0, 0),
                    Vector3(-1, -1, -1),
                    Vector3(1, 1, 1),
                    falloff,
                )
            ),
            bitcast[DType.uint32](
                _original_grid_falloff(
                    Vector3(2, 0, 0),
                    Vector3(-1, -1, -1),
                    Vector3(1, 1, 1),
                    falloff,
                )
            ),
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
