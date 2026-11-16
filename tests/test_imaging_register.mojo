# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Rigid registration that finds a known turn and shift of the phantom.

The fixed and the moving volumes sample the middle of one blurred phantom
on two grids, 72 and 75 mm across. The moving grid has other voxels, is
turned 10 degrees and is placed apart, and its samples are moved by the
inverse of a known transform.
"""

from extensions.imaging.filter import gaussian_filter
from extensions.imaging.ids import (
    LabelId,
    MEAN_SQUARES,
    MUTUAL_INFORMATION,
    RegistrationMetric,
    require_metric,
)
from extensions.imaging.image_volume import ImageVolume
from extensions.imaging.labels import LabelMap, threshold
from extensions.imaging.phantom import shepp_logan
from extensions.imaging.register import (
    RigidTransform,
    _from_vector,
    largest_difference,
    register_rigid,
    resample_labels_transformed,
    resample_transformed,
)
from extensions.imaging.resample import resample_labels_onto, resample_onto
from extensions.sdf.vector import V3, length, v3
from std.math import cos, inf, nan, sin
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import DEGREE64, METER, MILLIMETER64, Angle64, Length64


def _grid(
    n: Int, step: Float64, turn: Float64, shift: Float64
) raises -> ImageVolume:
    """A cube of `n` voxels of `step` mm, turned about z and moved."""
    var s = Length64(step, MILLIMETER64)
    var grid = ImageVolume(n, n, n, s, s, s)
    var c = cos(turn)
    var d = sin(turn)
    grid.axis_x = v3(c, d, 0)
    grid.axis_y = v3(-d, c, 0)
    var half = 0.5 * Float64(n - 1) * step * 0.001
    grid.origin = (
        v3(shift, -shift, 0.5 * shift)
        - grid.axis_x * half
        - grid.axis_y * half
        - grid.axis_z * half
    )
    return grid^


def _truth() raises -> RigidTransform:
    return RigidTransform(
        v3(0.3, -0.5, 0.8),
        Angle64(6.0, DEGREE64),
        v3(0, 0, 0),
        v3(0.005, -0.004, 0.003),
    )


def _pair() raises -> Tuple[ImageVolume, ImageVolume]:
    """The fixed volume, and the moving volume moved by the truth."""
    # The head on 64 voxels of 3.125 mm, one sample each, blurred by 5 mm.
    var source = gaussian_filter(
        shepp_logan(64, Length64(200.0, MILLIMETER64), 1),
        Length64(5.0, MILLIMETER64),
    )
    var fixed = resample_onto(source, _grid(16, 4.5, 0.0, 0.0), 0)
    var moving = resample_transformed(
        source, _grid(15, 5.0, 0.17, 0.002), _truth().inverse(), 0
    )
    return (fixed^, moving^)


def _jaccard(a: LabelMap, b: LabelMap) -> Float64:
    var both = 0
    var either = 0
    for v in range(a.count()):
        var x = a.labels[v] == 1
        var y = b.labels[v] == 1
        if x and y:
            both += 1
        if x or y:
            either += 1
    return Float64(both) / Float64(either)


def _start() -> RigidTransform:
    return RigidTransform(v3(0, 0, 0))


def _mm(length: Length64) -> Float64:
    return length.to(METER) * 1000.0


def test_transforms() raises:
    # A quarter turn about z through (10, 0, 0) mm, then 2 mm up.
    var quarter = RigidTransform(
        v3(0, 0, 3), Angle64(90.0, DEGREE64), v3(0.01, 0, 0), v3(0, 0, 0.002)
    )
    var p = quarter.apply(v3(0.02, 0, 0))
    assert_almost_equal(p.x, 0.01, atol=1e-15)
    assert_almost_equal(p.y, 0.01, atol=1e-15)
    assert_almost_equal(p.z, 0.002, atol=1e-15)
    assert_almost_equal(quarter.axis.z, 1.0)
    var truth = _truth()
    var q = v3(0.03, -0.07, 0.05)
    var back = truth.inverse().apply(truth.apply(q))
    assert_true(length(back - q) < 1e-15)
    # The transform that moves nothing, against a shift of 3 mm.
    var still = RigidTransform(v3(0.1, 0.2, 0.3))
    assert_true(length(still.apply(q) - q) < 1e-16)
    # A search point of no turn: the axis stays z, and the shift is in mm.
    var plain = _from_vector([0.0, 0.0, 0.0, 1.0, 2.0, 3.0], q)
    assert_equal(plain.angle.to(DEGREE64), 0.0)
    assert_equal(plain.axis.z, 1.0)
    assert_almost_equal(plain.shift.y, 0.002)
    var moved = RigidTransform(v3(0, 0, 0))
    moved.shift = v3(0, 0.003, 0)
    var grid = _grid(4, 2.0, 0.3, 0.0)
    assert_almost_equal(_mm(largest_difference(still, moved, grid)), 3.0)
    var axes: List[V3] = [v3(0, 0, 0), v3(inf[DType.float64](), 0, 0)]
    for axis in axes:
        with assert_raises(contains="rotation axis"):
            _ = RigidTransform(axis, Angle64(1.0, DEGREE64), q, q)
    with assert_raises(contains="rotation angle"):
        _ = RigidTransform(
            v3(1, 0, 0), Angle64(nan[DType.float64](), DEGREE64), q, q
        )


def test_resample_through_a_transform() raises:
    var pair = _pair()
    ref fixed = pair[0]
    ref moving = pair[1]
    # Through the transform that moves nothing, as resample_onto.
    var still = RigidTransform(v3(0, 0, 0))
    var plain = resample_onto(moving, fixed, -1)
    var through = resample_transformed(moving, fixed, still, -1)
    for v in range(fixed.count()):
        assert_equal(through.values[v], plain.values[v])
    var map = threshold(moving, 0.1, 2.0, LabelId(1))
    var labels = resample_labels_onto(map, moving, fixed)
    var moved = resample_labels_transformed(map, moving, fixed, still)
    for v in range(fixed.count()):
        assert_equal(moved.labels[v], labels.labels[v])
    # Through the truth, the moving labels land on the fixed labels, far
    # better than through no transform.
    var want = threshold(fixed, 0.1, 2.0, LabelId(1))
    var landed = resample_labels_transformed(map, moving, fixed, _truth())
    var good = _jaccard(landed, want)
    assert_true(good > 0.9)
    assert_true(good > _jaccard(moved, want) + 0.05)
    with assert_raises(contains="different grids"):
        _ = resample_labels_transformed(map, fixed, fixed, still)


def test_mean_squares() raises:
    var pair = _pair()
    var found = register_rigid(
        pair[0], pair[1], MEAN_SQUARES, RigidTransform(v3(0, 0, 0)), 1, 1
    )
    var error = _mm(largest_difference(found.transform, _truth(), pair[0]))
    assert_true(error < 0.25)
    assert_almost_equal(found.transform.angle.to(DEGREE64), 6.0, atol=0.2)
    assert_true(found.overlap > 0.8)
    assert_true(found.cost < 1e-4)
    assert_true(found.evaluations > 100)


def test_mutual_information() raises:
    var pair = _pair()
    # A second kind of scan: the moving values through a curve that rises
    # and falls.
    var other = pair[1].copy()
    for v in range(other.count()):
        var x = Float64(other.values[v]) - 0.3
        other.values[v] = Float32(4.0 * x * x)
    var found = register_rigid(
        pair[0], other, MUTUAL_INFORMATION, RigidTransform(v3(0, 0, 0)), 1, 1
    )
    var error = _mm(largest_difference(found.transform, _truth(), pair[0]))
    assert_true(error < 0.8)
    assert_true(found.cost < -1.0)
    # The mean square of the two kinds is least far from the truth.
    var wrong = register_rigid(
        pair[0], other, MEAN_SQUARES, RigidTransform(v3(0, 0, 0)), 1, 2
    )
    assert_true(
        _mm(largest_difference(wrong.transform, _truth(), pair[0])) > 10.0
    )


def test_a_volume_stays_on_itself() raises:
    var fixed = _pair()[0].copy()
    var found = register_rigid(
        fixed, fixed, MEAN_SQUARES, RigidTransform(v3(0, 0, 0)), 2, 2
    )
    # The identity reads each voxel to 1e-16 of a voxel, so the cost at
    # the start is near 0 and not exactly 0.
    assert_true(found.cost < 1e-25)
    assert_true(
        _mm(largest_difference(found.transform, _start(), fixed)) < 1e-6
    )
    assert_equal(found.overlap, 1.0)


def test_refusals() raises:
    var pair = _pair()
    ref fixed = pair[0]
    ref moving = pair[1]
    var start = RigidTransform(v3(0, 0, 0))
    with assert_raises(contains="metric"):
        require_metric(RegistrationMetric(2))
    with assert_raises(contains="metric"):
        _ = register_rigid(fixed, moving, RegistrationMetric(-1), start, 1, 1)
    var levels: List[Int] = [0, 5]
    for n in levels:
        with assert_raises(contains="1 to 4 levels"):
            _ = register_rigid(fixed, moving, MEAN_SQUARES, start, n, 1)
    var strides: List[Int] = [0, 9]
    for s in strides:
        with assert_raises(contains="1 to 8 voxels"):
            _ = register_rigid(fixed, moving, MEAN_SQUARES, start, 1, s)
    var away = RigidTransform(v3(0, 0, 0))
    away.shift = v3(1.0, 0, 0)
    with assert_raises(contains="do not overlap"):
        _ = register_rigid(fixed, moving, MEAN_SQUARES, away, 1, 4)
    var flat = moving.copy()
    for v in range(flat.count()):
        flat.values[v] = 1
    with assert_raises(contains="values vary"):
        _ = register_rigid(fixed, flat, MUTUAL_INFORMATION, start, 1, 4)
    with assert_raises(contains="values vary"):
        _ = register_rigid(flat, moving, MUTUAL_INFORMATION, start, 1, 4)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
