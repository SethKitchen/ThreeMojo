# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Independent controls for exact cut cells and exclusive tissue assignment."""

from extensions.anatomy.inertia import InertiaTally, SegmentInertia
from extensions.humanoid.skeleton.limb.inertia import (
    SegmentEstimate,
    _occupied_region,
)
from extensions.humanoid.skeleton.limb.regions import (
    LimbRegion,
    region_label,
    CORTICAL_REGION,
    TRABECULAR_REGION,
    MARROW_PROXY_REGION,
    MUSCLE_REGION,
    TENDON_REGION,
    FAT_PROXY_REGION,
)
from extensions.humanoid.skeleton.limb.sampling import SampleGrid
from extensions.humanoid.skeleton.occupancy import (
    BoneOccupancy,
    EMPTY,
    MARROW,
    CORTICAL_FILL,
    TRABECULAR_FILL,
)
from math.vector3 import Vector3
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Length, METER


def test_named_regions_and_marrow_override_overlapping_soft_tissue() raises:
    for index in range(7):
        assert_true(LimbRegion(index).is_valid())
        assert_true(region_label(LimbRegion(index)).byte_length() > 0)
    assert_false(LimbRegion(-1).is_valid())
    assert_false(LimbRegion(7).is_valid())
    with assert_raises():
        _ = region_label(LimbRegion(-1))
    for soft in [MUSCLE_REGION, TENDON_REGION, FAT_PROXY_REGION]:
        # The original MARROW-or-EMPTY branch could select a soft tissue.
        # This tests documented assignment, not biological marrow density.
        assert_equal(_occupied_region(MARROW, soft), MARROW_PROXY_REGION)
        assert_equal(_occupied_region(CORTICAL_FILL, soft), CORTICAL_REGION)
        assert_equal(_occupied_region(TRABECULAR_FILL, soft), TRABECULAR_REGION)
        assert_equal(_occupied_region(EMPTY, soft), soft)
    with assert_raises():
        _ = _occupied_region(BoneOccupancy(8), FAT_PROXY_REGION)
    with assert_raises():
        _ = _occupied_region(EMPTY, LimbRegion(8))


def test_grid_rejects_non_finite_and_unbounded_work_before_counts() raises:
    var lo = Vector3(0, 0, 0)
    var hi = Vector3(0.037, 0.053, 0.029)
    for value in [
        Float32(0),
        Float32(-1),
        nan[DType.float32](),
        inf[DType.float32](),
        -inf[DType.float32](),
    ]:
        with assert_raises(contains="step"):
            _ = SampleGrid(lo, hi, Length(value, METER))
    with assert_raises(contains="work limit"):
        _ = SampleGrid(lo, hi, Length(1.0e-30, METER))
    for value in [
        nan[DType.float32](),
        inf[DType.float32](),
        -inf[DType.float32](),
    ]:
        with assert_raises(contains="box"):
            _ = SampleGrid(Vector3(value, 0, 0), hi, Length(0.01))
        with assert_raises(contains="box"):
            _ = SampleGrid(lo, Vector3(1, value, 1), Length(0.01))
    with assert_raises(contains="box"):
        _ = SampleGrid(lo, lo, Length(0.01))
    with assert_raises(contains="box"):
        _ = SampleGrid(hi, lo, Length(0.01))
    var grid = SampleGrid(lo, hi, Length(0.01))
    for index in [-1, grid.nx]:
        with assert_raises(contains="x index"):
            _ = grid.cell(index, 0, 0)
    for index in [-1, grid.ny]:
        with assert_raises(contains="y index"):
            _ = grid.cell(0, index, 0)
    for index in [-1, grid.nz]:
        with assert_raises(contains="z index"):
            _ = grid.cell(0, 0, index)


def _box(low: Vector3, high: Vector3, step: Float32) raises -> InertiaTally:
    var grid = SampleGrid(low, high, Length(step))
    var tally = InertiaTally()
    for iz in range(grid.nz):
        for iy in range(grid.ny):
            for ix in range(grid.nx):
                var p, w = grid.cell(ix, iy, iz)
                for axis in range(3):
                    assert_true(
                        p.get_component(axis) >= low.get_component(axis)
                    )
                    assert_true(
                        p.get_component(axis) <= high.get_component(axis)
                    )
                    assert_true(w.get_component(axis) > 0)
                var m = (
                    Float64(1200) * Float64(w.x) * Float64(w.y) * Float64(w.z)
                )
                tally.add_cell(m, p, w)
    return tally^


def _tensor(v: SegmentInertia) -> SIMD[DType.float64, 8]:
    return SIMD[DType.float64, 8](
        Float64(v.xx.value),
        Float64(v.yy.value),
        Float64(v.zz.value),
        Float64(v.xy.value),
        Float64(v.xz.value),
        Float64(v.yz.value),
        0,
        0,
    )


def _refuses_unnamed_regions(estimate: SegmentEstimate) raises:
    # Keep these raising calls separate from the loop below, matching the
    # reviewed workaround for a Mojo 1.1.0 compiler failure.
    with assert_raises():
        _ = estimate.region_volume(LimbRegion(7))
    with assert_raises():
        _ = estimate.region_mass(LimbRegion(-1))


def test_cuboid_and_arbitrary_cut_composition_are_exact_at_three_steps() raises:
    var low = Vector3(0.011, -0.027, 0.019)
    var high = Vector3(0.048, 0.026, 0.048)
    var size = high - low
    var center = (low + high) * 0.5
    var expected_mass = 1200 * size.x * size.y * size.z
    var expected = SIMD[DType.float32, 8](
        expected_mass * (size.y * size.y + size.z * size.z) / 12,
        expected_mass * (size.x * size.x + size.z * size.z) / 12,
        expected_mass * (size.x * size.x + size.y * size.y) / 12,
        0,
        0,
        0,
        0,
        0,
    )
    for step in [Float32(0.02), Float32(0.01), Float32(0.005)]:
        var whole = _box(low, high, step)
        var m = whole.mass
        var first = whole.first
        var second = whole.second
        var result = whole.result(size.y)
        assert_almost_equal(result.mass.value, expected_mass, atol=2.0e-8)
        for axis in range(3):
            assert_almost_equal(
                result.center.get_component(axis),
                center.get_component(axis),
                atol=2.0e-8,
            )
        var actual = _tensor(result)
        for index in range(6):
            assert_almost_equal(
                actual[index], Float64(expected[index]), atol=1.0e-10
            )
        # The cut is not aligned with any of the three grids.
        var cut = _box(low, Vector3(high.x, 0.0043, high.z), step)
        cut.add(_box(Vector3(low.x, 0.0043, low.z), high, step))
        assert_almost_equal(cut.mass, m, atol=2.0e-8)
        for axis in range(3):
            assert_almost_equal(cut.first[axis], first[axis], atol=2.0e-9)
        for axis in range(6):
            assert_almost_equal(cut.second[axis], second[axis], atol=2.0e-10)
        var counts = SIMD[DType.float64, 8](0)
        counts[0] = 0.1
        var estimate = SegmentEstimate(
            result, counts, counts, low, high, Length(step)
        )
        assert_almost_equal(
            estimate.region_volume(LimbRegion(0)).value, 0.1, atol=1.0e-8
        )
        assert_almost_equal(
            estimate.region_mass(LimbRegion(0)).value, 0.1, atol=1.0e-8
        )
        _refuses_unnamed_regions(estimate)


def test_independent_point_masses_rigid_transform_and_parallel_axis() raises:
    var a = Vector3(-0.03, 0.02, 0.07)
    var b = Vector3(0.05, -0.04, 0.01)
    var d = b - a
    var expected_center = (a * 2 + b * 3) * 0.2
    var tally = InertiaTally()
    tally.add_cell(2, a, Vector3(0, 0, 0))
    tally.add_cell(3, b, Vector3(0, 0, 0))
    var mass = tally.mass
    var second = tally.second
    var result = tally.result(1)
    # Closed form: central second moment = (m1*m2/M) * d*d^T.
    var expected = SIMD[DType.float32, 8](
        1.2 * (d.y * d.y + d.z * d.z),
        1.2 * (d.x * d.x + d.z * d.z),
        1.2 * (d.x * d.x + d.y * d.y),
        -1.2 * d.x * d.y,
        -1.2 * d.x * d.z,
        -1.2 * d.y * d.z,
        0,
        0,
    )
    var actual = _tensor(result)
    for index in range(6):
        assert_almost_equal(
            actual[index], Float64(expected[index]), atol=1.0e-8
        )
    for axis in range(3):
        assert_almost_equal(
            result.center.get_component(axis),
            expected_center.get_component(axis),
            atol=1.0e-8,
        )
    var c = expected_center
    var offset = SIMD[DType.float32, 8](
        c.y * c.y + c.z * c.z,
        c.x * c.x + c.z * c.z,
        c.x * c.x + c.y * c.y,
        -c.x * c.y,
        -c.x * c.z,
        -c.y * c.z,
        0,
        0,
    )
    var raw = SIMD[DType.float64, 8](
        second[1] + second[2],
        second[0] + second[2],
        second[0] + second[1],
        -second[3],
        -second[4],
        -second[5],
        0,
        0,
    )
    for index in range(6):
        assert_almost_equal(
            actual[index] + mass * Float64(offset[index]),
            raw[index],
            atol=1.0e-8,
        )
    var shift = Vector3(0.13, -0.11, 0.09)
    var ra = Vector3(-a.y, a.x, a.z) + shift
    var rb = Vector3(-b.y, b.x, b.z) + shift
    var turned = InertiaTally()
    turned.add_cell(2, ra, Vector3(0, 0, 0))
    turned.add_cell(3, rb, Vector3(0, 0, 0))
    var rotated = turned.result(1)
    var rotation_expected = SIMD[DType.float64, 8](
        actual[1], actual[0], actual[2], -actual[3], -actual[5], actual[4], 0, 0
    )
    var rotation_actual = _tensor(rotated)
    assert_almost_equal(rotated.mass.value, result.mass.value, atol=1.0e-8)
    var rotated_center = Vector3(-c.y, c.x, c.z) + shift
    for index in range(6):
        assert_almost_equal(
            rotation_actual[index], rotation_expected[index], atol=1.0e-8
        )
    for axis in range(3):
        assert_almost_equal(
            rotated.center.get_component(axis),
            rotated_center.get_component(axis),
            atol=2.0e-8,
        )
    for bad in [
        Float64(0),
        Float64(-1),
        inf[DType.float64](),
        nan[DType.float64](),
    ]:
        var broken = tally.copy()
        broken.mass = bad
        with assert_raises(contains="mass"):
            _ = broken.result(1)


def _check_single_point(m: Float64, p: Vector3) raises:
    var tally = InertiaTally()
    tally.add_cell(m, p, Vector3(0, 0, 0))
    var point = tally.result(0)
    assert_equal(point.mass.value, Float32(m))
    for axis in range(3):
        assert_equal(point.center.get_component(axis), p.get_component(axis))
    var tensor = _tensor(point)
    for axis in range(6):
        assert_equal(tensor[axis], 0.0)


def test_translated_single_points_have_zero_central_inertia() raises:
    for m in [Float64(0.1), Float64(0.3), Float64(2.7)]:
        for x in [Float32(-3.7), Float32(-0.3), Float32(0.1), Float32(1.9)]:
            for y in [Float32(-0.7), Float32(0.2), Float32(2.3)]:
                # Keep raising tally calls in a helper, as in the cuboid
                # control above, for the pinned compiler's loop lowering.
                _check_single_point(m, Vector3(x, y, x - y))


def _check_nearby_pair(a: Vector3, b: Vector3) raises:
    var tally = InertiaTally()
    tally.add_cell(0.3, a, Vector3(0, 0, 0))
    tally.add_cell(0.7, b, Vector3(0, 0, 0))
    var result = tally.result(0)
    var d = b - a
    # Independent two-point formula: m1*m2/M times d*d^T.
    var expected = SIMD[DType.float64, 8](
        0.21 * (Float64(d.y) * Float64(d.y) + Float64(d.z) * Float64(d.z)),
        0.21 * (Float64(d.x) * Float64(d.x) + Float64(d.z) * Float64(d.z)),
        0.21 * (Float64(d.x) * Float64(d.x) + Float64(d.y) * Float64(d.y)),
        -0.21 * Float64(d.x) * Float64(d.y),
        -0.21 * Float64(d.x) * Float64(d.z),
        -0.21 * Float64(d.y) * Float64(d.z),
        0,
        0,
    )
    var actual = _tensor(result)
    for i in range(6):
        assert_almost_equal(actual[i], expected[i], rtol=1e-5, atol=1e-12)


def test_nearby_points_keep_resolved_anisotropic_inertia() raises:
    _check_nearby_pair(Vector3(10, 10, 10), Vector3(10.0001, 10.01, 11))
    _check_nearby_pair(Vector3(10, 10, 10), Vector3(10.001, 10.01, 10.1))
    _check_nearby_pair(Vector3(0.1, -0.3, 0.7), Vector3(0.1001, -0.299, 0.71))


def test_cancellation_guard_cannot_hide_resolved_invalid_moments() raises:
    # A large raw moment on z must not excuse a negative x moment.
    var bad = InertiaTally()
    bad.add_cell(0.3, Vector3(0, 0, 1000), Vector3(0, 0, 0))
    bad.second[0] = -1e-11
    with assert_raises(contains="nonnegative"):
        _ = bad.result(0)
    # At ordinary translated coordinates, a resolved negative variance
    # and a resolved cross moment remain inadmissible.
    bad = InertiaTally()
    bad.add_cell(0.3, Vector3(0.1, -0.3, 0.7), Vector3(0, 0, 0))
    # About twice the raw cancellation envelope, not a broad tolerance.
    bad.second[0] -= 64.0 * 1.1102230246251565e-16 * abs(bad.second[0])
    with assert_raises(contains="nonnegative"):
        _ = bad.result(0)
    bad = InertiaTally()
    bad.add_cell(0.3, Vector3(0.1, -0.3, 0.7), Vector3(0, 0, 0))
    bad.second[3] += 64.0 * 1.1102230246251565e-16 * abs(bad.second[3])
    with assert_raises(contains="admissible"):
        _ = bad.result(0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
