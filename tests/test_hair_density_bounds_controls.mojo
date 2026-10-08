# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Bit-level signed-zero and first-point controls for density bounds."""

from extensions.humanoid.skeleton.head.hair.density import HairDensity
from extensions.humanoid.skeleton.head.hair.groom import HairGroom
from math.vector3 import Vector3
from std.math import inf, nan
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Length, METER


def test_signed_zero_first_points_preserve_grid_bits() raises:
    var negative_zero = bitcast[DType.float32](UInt32(0x80000000))
    for mask in range(8):
        var point = Vector3(
            negative_zero if mask & 1 else Float32(0),
            negative_zero if mask & 2 else Float32(0),
            negative_zero if mask & 4 else Float32(0),
        )
        var groom = HairGroom()
        groom.add([point], [Vector3(0, 0, 1)], [Float32(0)], 1)
        var density = HairDensity(
            4, Length(bitcast[DType.float32](UInt32(1)), METER)
        )
        density.rebuild(groom)
        # Exact binary32 floor: its cube remains far above subnormal range.
        assert_equal(bitcast[DType.uint32](density.cell), UInt32(0x3727C5AC))
        assert_equal(bitcast[DType.uint32](density.low.x), UInt32(0xB727C5AC))
        assert_equal(bitcast[DType.uint32](density.low.y), UInt32(0xB727C5AC))
        assert_equal(bitcast[DType.uint32](density.low.z), UInt32(0xB727C5AC))
        assert_true(density.populated)
        for coefficient in density.coefficients:
            assert_equal(bitcast[DType.uint32](coefficient), UInt32(0))
        # Add a second point so both zero-length and nonempty bounds scans run.
        groom.add([Vector3(-0.5, 0.75, 1)], [Vector3(0, 0, 1)], [Float32(0)], 1)
        density.rebuild(groom)
        assert_equal(bitcast[DType.uint32](density.cell), UInt32(0x3F800000))
        assert_equal(bitcast[DType.uint32](density.low.x), UInt32(0xBFC00000))
        assert_equal(bitcast[DType.uint32](density.low.y), UInt32(0xBF800000))
        assert_equal(bitcast[DType.uint32](density.low.z), UInt32(0xBF800000))
        for coefficient in density.coefficients:
            assert_equal(bitcast[DType.uint32](coefficient), UInt32(0))


def test_every_nonfinite_first_coordinate_keeps_scale_and_refuses() raises:
    for bad in [
        Vector3(nan[DType.float32](), 0, 0),
        Vector3(0, inf[DType.float32](), 0),
        Vector3(0, 0, -inf[DType.float32]()),
    ]:
        var groom = HairGroom()
        groom.add([bad], [Vector3(0, 0, 1)], [Float32(0)], 1)
        var density = HairDensity(4)
        with assert_raises(contains="finite positions"):
            density.rebuild(groom)
        assert_false(density.populated)
        assert_equal(density.cell, 1)
        assert_true(density.low == Vector3(0, 0, 0))
        for coefficient in density.coefficients:
            assert_equal(coefficient, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
