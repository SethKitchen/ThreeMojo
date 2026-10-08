# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Native boundary fixtures for the reviewed density operation graph."""

from extensions.humanoid.skeleton.head.hair.density import HairDensity
from extensions.humanoid.skeleton.head.hair.groom import HairGroom
from math.vector3 import Vector3
from std.math import ceil, isfinite, max, nan
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from units.si import Length, METER


def _pair(a: Vector3, b: Vector3) -> HairGroom:
    var groom = HairGroom()
    groom.add([a, b], [Vector3(0, 0, 1), Vector3(0, 0, 1)], [Float32(0), 0], 1)
    return groom^


def test_extreme_valid_density_segments_stay_in_the_grid() raises:
    var tiny = bitcast[DType.float32](UInt32(1))
    var largest = bitcast[DType.float32](UInt32(0x7F7FFFFF))
    for resolution in [4, 64]:
        for mode in range(4):
            var a = Vector3(0, 0, 0)
            var b = Vector3(0.1, 0.1, 0.1)
            if mode == 1:
                a = Vector3(largest, 0, 0)
                b = Vector3(largest, 0.00001, 0.00001)
            elif mode == 2:
                a = Vector3(-largest, 0, 0)
                b = Vector3(-largest, -0.00001, -0.00001)
            elif mode == 3:
                b = Vector3(tiny, tiny, tiny)
            var groom = _pair(a, b)
            var density = HairDensity(resolution, Length(tiny, METER))
            density.rebuild(groom)
            assert_true(density.populated)
            var delta = b - a
            var length = delta.length()
            assert_true(isfinite(length))
            var samples = max(1, Int(ceil(length / (density.cell * 0.5))))
            assert_true(samples >= 1 and samples <= 211)
            for sample in range(samples):
                var p = a + delta * ((Float32(sample) + 0.5) / Float32(samples))
                var slot = density._slot(p)
                assert_true(slot >= 0 and slot < len(density.coefficients))
            for coefficient in density.coefficients:
                assert_true(isfinite(coefficient) and coefficient >= 0)


def test_duplicate_segment_and_rebuild_reset_stale_public_storage() raises:
    var tiny = bitcast[DType.float32](UInt32(1))
    var groom = _pair(Vector3(0, 0, 0), Vector3(0, 0, 0))
    var density = HairDensity(4, Length(tiny, METER))
    for index in range(len(density.coefficients)):
        density.coefficients[index] = nan[DType.float32]()
    density.low = Vector3(nan[DType.float32](), 0, 0)
    density.cell = nan[DType.float32]()
    density.populated = True
    density.rebuild(groom)
    assert_true(density.populated)
    assert_equal(bitcast[DType.uint32](density.cell), UInt32(0x3727C5AC))
    for coefficient in density.coefficients:
        assert_equal(coefficient, 0)


def test_rebuild_revalidates_mutated_settings() raises:
    var groom = _pair(Vector3(0, 0, 0), Vector3(0.01, 0, 0))
    var density = HairDensity(4)
    for resolution in [3, 65]:
        density.resolution = resolution
        with assert_raises(contains="cells"):
            density.rebuild(groom)
    density.resolution = 4
    for diameter in [Float32(0), nan[DType.float32]()]:
        density.diameter = Length(diameter, METER)
        with assert_raises(contains="diameter"):
            density.rebuild(groom)


def test_adjacent_cell_cube_boundary_keeps_finite_and_refuses_overflow() raises:
    var finite_cell = bitcast[DType.float32](UInt32(0x54CB2FF4))
    var overflow_cell = bitcast[DType.float32](UInt32(0x54CB2FF5))
    var groom = _pair(Vector3(0, 0, 0), Vector3(finite_cell, 0, 0))
    var density = HairDensity(4, Length(finite_cell, METER))
    density.rebuild(groom)
    assert_equal(density.cell, finite_cell)
    for coefficient in density.coefficients:
        assert_true(isfinite(coefficient) and coefficient >= 0)
    density.diameter = Length(overflow_cell, METER)
    with assert_raises(contains="grid scale"):
        density.rebuild(groom)


def test_many_repeated_segments_accumulate_finite_density() raises:
    var groom = HairGroom()
    for _ in range(128):
        groom.add(
            [Vector3(0, 0, 0), Vector3(0.00001, 0, 0)],
            [Vector3(0, 0, 1), Vector3(0, 0, 1)],
            [Float32(0), 0],
            1,
        )
    var density = HairDensity(4, Length(0.00001, METER))
    density.rebuild(groom)
    var total = Float32(0)
    for coefficient in density.coefficients:
        assert_true(isfinite(coefficient) and coefficient >= 0)
        total += coefficient
    assert_true(total > 0 and isfinite(total))
    # This primitive check supports the induction barrier, not a huge loop.
    var barrier = Float32(4398046511104)
    var increment = bitcast[DType.float32](UInt32(0x477FFFFF))
    assert_equal(barrier + increment, barrier)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
