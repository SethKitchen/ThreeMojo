# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Gaussian and median filters of volumes."""

from extensions.imaging.filter import (
    gaussian_filter,
    gaussian_kernel,
    median_filter,
)
from extensions.imaging.image_volume import ImageVolume, MILLIMETER64
from std.math import exp, inf
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Length64


def _mm(value: Float64) -> Length64:
    return Length64(value, MILLIMETER64)


def test_kernel() raises:
    var kernel = gaussian_kernel(1.0)
    # Three standard deviations on each side.
    assert_equal(len(kernel), 7)
    var total = 0.0
    for w in kernel:
        total += w
    assert_almost_equal(total, 1.0, atol=1e-15)
    assert_almost_equal(kernel[3] / kernel[4], exp(0.5), rtol=1e-12)
    assert_equal(kernel[0], kernel[6])
    # A narrow kernel still reaches one voxel.
    assert_equal(len(gaussian_kernel(0.1)), 3)
    with assert_raises(contains="positive and finite"):
        _ = gaussian_kernel(0)
    with assert_raises(contains="positive and finite"):
        _ = gaussian_kernel(inf[DType.float64]())
    with assert_raises(contains="at most 128 voxels"):
        _ = gaussian_kernel(43)


def test_gaussian_keeps_constants_and_ramps() raises:
    var volume = ImageVolume(21, 3, 2, _mm(1), _mm(1), _mm(1))
    for index in range(volume.count()):
        volume.values[index] = Float32(index % 21)
    var blurred = gaussian_filter(volume, _mm(1))
    # A symmetric kernel keeps a linear ramp where it does not reach an edge.
    for i in range(3, 18):
        assert_almost_equal(blurred.get(i, 1, 1), Float32(i), atol=1e-4)
    # At the edge, the nearest voxel stands in, so the ramp bends up.
    assert_true(blurred.get(0, 0, 0) > 0.1)
    # The values do not change along j and k, which are constant.
    assert_almost_equal(blurred.get(7, 0, 0), blurred.get(7, 2, 1), atol=1e-5)
    assert_equal(blurred.nx, 21)
    assert_almost_equal(blurred.spacing_x.to(MILLIMETER64), 1.0)


def test_gaussian_impulse_response() raises:
    # Rows 2 mm apart: the kernel is half as wide in voxels along j.
    var volume = ImageVolume(9, 9, 9, _mm(1), _mm(2), _mm(1))
    volume.set(4, 4, 4, 1)
    var blurred = gaussian_filter(volume, _mm(1))
    var wide = gaussian_kernel(1.0)
    var narrow = gaussian_kernel(0.5)
    assert_almost_equal(
        blurred.get(4, 4, 4), Float32(wide[3] * narrow[2] * wide[3]), atol=1e-7
    )
    assert_almost_equal(
        blurred.get(5, 3, 4), Float32(wide[4] * narrow[1] * wide[3]), atol=1e-7
    )
    var total = 0.0
    for value in blurred.values:
        total += Float64(value)
    assert_almost_equal(total, 1.0, atol=1e-5)
    with assert_raises(contains="positive and finite"):
        _ = gaussian_filter(volume, _mm(0))
    with assert_raises(contains="positive and finite"):
        _ = gaussian_filter(volume, _mm(inf[DType.float64]()))


def test_median_removes_spikes_and_keeps_edges() raises:
    var volume = ImageVolume(6, 5, 4, _mm(1), _mm(1), _mm(1))
    for k in range(4):
        for j in range(5):
            for i in range(6):
                volume.set(i, j, k, Float32(10) if i >= 3 else Float32(0))
    # One hot voxel in the dark half, and one cold voxel in the bright half.
    volume.set(1, 2, 1, 500)
    volume.set(4, 2, 2, -500)
    var clean = median_filter(volume, 1)
    assert_equal(clean.get(1, 2, 1), 0)
    assert_equal(clean.get(4, 2, 2), 10)
    # The edge between the halves stays where it was.
    for j in range(5):
        assert_equal(clean.get(2, j, 0), 0)
        assert_equal(clean.get(3, j, 3), 10)
    var wide = median_filter(volume, 3)
    assert_equal(wide.get(5, 4, 3), 10)
    with assert_raises(contains="from 1 to 3 voxels"):
        _ = median_filter(volume, 0)
    with assert_raises(contains="from 1 to 3 voxels"):
        _ = median_filter(volume, 4)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
