# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Public density producers and explicit malformed-input refusals."""

from extensions.humanoid.skeleton.head.hair.density import (
    HairDensity,
    _checked_density_samples,
)
from extensions.humanoid.skeleton.head.hair.groom import HairGroom
from math.vector3 import Vector3
from std.math import inf, nan
from std.memory import bitcast
from std.sys import size_of
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from units.si import Length, METER


def _add(mut groom: HairGroom, x: Float32, points: Int = 3):
    """Add a vertical fiber of one, two or three points at x."""
    var p = List[Vector3]()
    var n = List[Vector3]()
    var d = List[Float32]()
    for index in range(points):
        p.append(Vector3(x, Float32(index) * 0.05 - 0.05, 0))
        n.append(Vector3(0, 0, 1))
        d.append(0)
    groom.add(p, n, d, 1)


def _groom() -> HairGroom:
    var groom = HairGroom()
    _add(groom, 0)
    _add(groom, 0.08)
    return groom^


def test_density_reallocates_after_a_resolution_change() raises:
    var density = HairDensity(24, Length(0.00008, METER))
    density.rebuild(_groom())
    density.resolution = 8
    density.rebuild(_groom())
    assert_equal(len(density.coefficients), 8 * 8 * 8)


def test_density_refuses_malformed_topology_and_positions() raises:
    var density = HairDensity(24, Length(0.00008, METER))
    var groom = _groom()
    groom.starts.clear()
    with assert_raises(contains="beginning at zero"):
        density.rebuild(groom)
    groom = _groom()
    groom.starts[1] = 7
    with assert_raises(contains="ordered"):
        density.rebuild(groom)
    for axis in range(3):
        groom = _groom()
        if axis == 0:
            groom.points[1].x = nan[DType.float32]()
        elif axis == 1:
            groom.points[1].y = nan[DType.float32]()
        else:
            groom.points[1].z = nan[DType.float32]()
        with assert_raises(contains="finite positions"):
            density.rebuild(groom)


def test_density_refuses_unrepresentable_grid_scales() raises:
    var density = HairDensity(64, Length(0.00008, METER))
    # The span overflows Float32, so the cell is infinite.
    var groom = HairGroom()
    _add(groom, -3.0e38)
    _add(groom, 3.0e38)
    with assert_raises(contains="grid scale"):
        density.rebuild(groom)
    # A finite cell whose cube overflows.
    groom = HairGroom()
    _add(groom, 0)
    _add(groom, 1.0e15)
    with assert_raises(contains="grid scale"):
        density.rebuild(groom)


def test_density_skips_a_one_point_strand() raises:
    var groom = HairGroom()
    _add(groom, 0, 1)
    _add(groom, 0.08)
    var density = HairDensity(24, Length(0.00008, METER))
    density.rebuild(groom)
    assert_true(density.populated)


def test_optical_depth_outside_the_grid_and_with_an_overflowing_direction() raises:
    var density = HairDensity(24, Length(0.00008, METER))
    density.rebuild(_groom())
    var up = Vector3(0, 0, 1)
    assert_equal(density.optical_depth(Vector3(0, -10, 0), up), 0)
    assert_equal(density.optical_depth(Vector3(0, 0, -10), up), 0)
    var huge = Vector3(3.0e38, 3.0e38, 0)
    assert_equal(density.optical_depth(Vector3(0, 0, 0), huge), 0)
    var bad = nan[DType.float32]()
    for axis in range(3):
        var point = Vector3(0, 0, 0)
        var direction = Vector3(0, 0, 1)
        if axis == 0:
            point.x = bad
            direction.x = bad
        elif axis == 1:
            point.y = bad
            direction.y = bad
        else:
            point.z = bad
            direction.z = bad
        with assert_raises(contains="finite point"):
            _ = density.optical_depth(point, up)
        with assert_raises(contains="finite light direction"):
            _ = density.optical_depth(Vector3(0, 0, 0), direction)


def _assert_same_grid(
    density: HairDensity, control: HairDensity, allocation: Int
) raises:
    """Check the retained volume and allocation without the mutable settings."""
    assert_equal(Int(density.coefficients.unsafe_ptr()), allocation)
    assert_equal(density.populated, control.populated)
    assert_equal(
        bitcast[DType.uint32](density.cell), bitcast[DType.uint32](control.cell)
    )
    assert_equal(
        bitcast[DType.uint32](density.low.x),
        bitcast[DType.uint32](control.low.x),
    )
    assert_equal(
        bitcast[DType.uint32](density.low.y),
        bitcast[DType.uint32](control.low.y),
    )
    assert_equal(
        bitcast[DType.uint32](density.low.z),
        bitcast[DType.uint32](control.low.z),
    )
    assert_equal(len(density.coefficients), len(control.coefficients))
    for index in range(len(control.coefficients)):
        assert_equal(
            bitcast[DType.uint32](density.coefficients[index]),
            bitcast[DType.uint32](control.coefficients[index]),
        )


def test_optical_depth_revalidates_public_settings_without_changing_grid() raises:
    var groom = _groom()
    var density = HairDensity(24)
    density.rebuild(groom)
    var control = HairDensity(24)
    control.rebuild(groom)
    var allocation = Int(density.coefficients.unsafe_ptr())
    var point = Vector3(0, 0, 0)
    var right = Vector3(1, 0, 0)
    var expected = control.optical_depth(point, right)
    assert_true(expected > 0)
    assert_equal(density.optical_depth(point, right), expected)
    # All floor coordinates are zero, even for the large invalid resolution.
    var offset = density.cell * 0.25
    var first_cell = density.low + Vector3(offset, offset, offset)
    for resolution in [Int(0), -1, 3, 65, Int.MAX // 2 + 1]:
        density.resolution = resolution
        with assert_raises(contains="cells"):
            _ = density.optical_depth(first_cell, right)
        assert_equal(density.resolution, resolution)
        _assert_same_grid(density, control, allocation)
        density.resolution = 24
        assert_equal(density.optical_depth(point, right), expected)
    for diameter in [
        Float32(0),
        -0.1,
        nan[DType.float32](),
        inf[DType.float32](),
    ]:
        density.diameter = Length(diameter, METER)
        with assert_raises(contains="diameter"):
            _ = density.optical_depth(point, right)
        assert_equal(
            bitcast[DType.uint32](density.diameter.to(METER)),
            bitcast[DType.uint32](diameter),
        )
        _assert_same_grid(density, control, allocation)
        density.diameter = Length(0.00008, METER)
        assert_equal(density.optical_depth(point, right), expected)
    assert_equal(density.optical_depth(point, Vector3(-1, 0, 0)), 0)
    assert_equal(density.optical_depth(Vector3(100, 0, 0), right), 0)
    assert_equal(density.optical_depth(point, Vector3(0, 0, 0)), 0)
    _assert_same_grid(density, control, allocation)


def test_optical_depth_preserves_error_order_for_empty_and_populated_grids() raises:
    for populated in [False, True]:
        var density = HairDensity(24)
        var control = HairDensity(24)
        if populated:
            density.rebuild(_groom())
            control.rebuild(_groom())
        var allocation = Int(density.coefficients.unsafe_ptr())
        var point = Vector3(0, 0, 0)
        var right = Vector3(1, 0, 0)
        var bad = Vector3(nan[DType.float32](), 0, 0)
        var expected = control.optical_depth(point, right)
        assert_equal(expected > 0, populated)
        assert_equal(density.optical_depth(point, right), expected)
        density.resolution = 0
        density.diameter = Length(0, METER)
        with assert_raises(contains="finite point"):
            _ = density.optical_depth(bad, bad)
        with assert_raises(contains="finite light direction"):
            _ = density.optical_depth(point, bad)
        with assert_raises(contains="cells"):
            _ = density.optical_depth(point, right)
        density.resolution = 24
        with assert_raises(contains="finite point"):
            _ = density.optical_depth(bad, bad)
        with assert_raises(contains="finite light direction"):
            _ = density.optical_depth(point, bad)
        with assert_raises(contains="diameter"):
            _ = density.optical_depth(point, right)
        _assert_same_grid(density, control, allocation)
        density.diameter = Length(0.00008, METER)
        assert_equal(density.optical_depth(point, right), expected)


def test_density_sample_count_checks_before_integer_conversion() raises:
    # Call only the helper at large bounds; never run a huge sampling loop.
    for ratio in [Float32(0), -0.0, -0.25, -1.75, -3.0e38, 0.25, 1.0]:
        assert_equal(_checked_density_samples(ratio), 1)
    assert_equal(_checked_density_samples(1.25), 2)
    assert_equal(_checked_density_samples(2.0), 2)
    assert_equal(_checked_density_samples(2.25), 3)
    # Independently construct binary32's exact 2^(Int width-1) encoding.
    var limit_bits = UInt32((8 * size_of[Int]() + 126) << 23)
    var below = bitcast[DType.float32](limit_bits - 1)
    var limit = bitcast[DType.float32](limit_bits)
    assert_equal(_checked_density_samples(below), Int.MAX - (Int.MAX >> 24))
    for refused in [
        nan[DType.float32](),
        inf[DType.float32](),
        -inf[DType.float32](),
        limit,
        limit * 2,
    ]:
        with assert_raises(contains="sample count is not representable"):
            _ = _checked_density_samples(refused)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
