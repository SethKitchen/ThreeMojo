# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Finite input contracts for builders without a JSON parameter backstop."""

from core.buffer_geometry import POSITION
from geometries.box_line import box_line
from geometries.circle import FULL_TURN, check_sweep
from geometries.rounded_box import rounded_box
from std.math import inf, isfinite, nan
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from units.si import Angle, Length, METER, RADIAN


def test_box_line_refuses_every_nonfinite_extent() raises:
    for bad in [
        nan[DType.float32](),
        inf[DType.float32](),
        -inf[DType.float32](),
    ]:
        for axis in range(3):
            var extents = [Float32(1), Float32(1), Float32(1)]
            extents[axis] = bad
            with assert_raises(contains="finite"):
                _ = box_line(
                    Length(extents[0], METER),
                    Length(extents[1], METER),
                    Length(extents[2], METER),
                )


def test_rounded_box_refuses_nonfinite_extents_and_radius() raises:
    for bad in [
        nan[DType.float32](),
        inf[DType.float32](),
        -inf[DType.float32](),
    ]:
        for field in range(4):
            var values = [Float32(1), Float32(1), Float32(1), Float32(0.1)]
            values[field] = bad
            with assert_raises(contains="finite"):
                _ = rounded_box(
                    Length(values[0], METER),
                    Length(values[1], METER),
                    Length(values[2], METER),
                    1,
                    Length(values[3], METER),
                )


def test_sweep_validation_itself_refuses_nonfinite_angles() raises:
    for bad in [
        nan[DType.float32](),
        inf[DType.float32](),
        -inf[DType.float32](),
    ]:
        with assert_raises(contains="finite"):
            check_sweep(Angle(bad, RADIAN))
    check_sweep(FULL_TURN)
    with assert_raises(contains="positive"):
        check_sweep(Angle(0, RADIAN))
    with assert_raises(contains="full turn"):
        check_sweep(Angle(Float32(FULL_TURN.value * 2), RADIAN))


def test_finite_box_boundaries_keep_their_geometry() raises:
    var lines = box_line(Length(2, METER), Length(4, METER), Length(6, METER))
    var bounds = lines.bounding_box()
    assert_equal(bounds.min.x, Float32(-1))
    assert_equal(bounds.max.y, Float32(2))
    assert_equal(bounds.max.z, Float32(3))
    for radius in [Float32(0), Float32(10)]:
        var rounded = rounded_box(
            Length(2, METER),
            Length(2, METER),
            Length(2, METER),
            1,
            Length(radius, METER),
        )
        assert_equal(rounded.vertex_count(), 324)
        for component in rounded.attribute_view(String(POSITION)).packed():
            assert_true(isfinite(component))
            assert_true(abs(component) <= 1.000001)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
