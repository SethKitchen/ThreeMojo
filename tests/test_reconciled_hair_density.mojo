# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Public density producers and explicit malformed-input refusals."""

from extensions.humanoid.skeleton.head.hair.density import HairDensity
from extensions.humanoid.skeleton.head.hair.groom import HairGroom
from math.vector3 import Vector3
from std.math import nan
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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
