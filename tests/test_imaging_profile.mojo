# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Line profiles through a volume, and their full width at half maximum."""

from extensions.imaging.image_volume import ImageVolume, MILLIMETER64
from extensions.imaging.measure import (
    LineProfile,
    full_width_half_maximum,
    line_profile,
)
from extensions.sdf.vector import V3, v3
from std.math import exp, inf, log, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Length64, METER


def _mm(value: Float64) -> Length64:
    return Length64(value, MILLIMETER64)


def _p(x: Float64, y: Float64, z: Float64) -> V3:
    """A point in millimeters, as meters."""
    return v3(x, y, z) * 0.001


def test_a_gaussian_has_its_width() raises:
    # A blob exp(-r^2 / (2 sigma^2)) with sigma = 2 mm, on 0.5 mm voxels.
    var volume = ImageVolume(41, 41, 41, _mm(0.5), _mm(0.5), _mm(0.5))
    var sigma = 2.0
    for k in range(41):
        for j in range(41):
            for i in range(41):
                var r2 = (
                    (Float64(i) * 0.5 - 10) ** 2
                    + (Float64(j) * 0.5 - 10) ** 2
                    + (Float64(k) * 0.5 - 10) ** 2
                )
                volume.set(i, j, k, Float32(exp(-r2 / (2 * sigma * sigma))))
    # The line runs past the grid at both ends, where the value is 0.
    var profile = line_profile(volume, _p(-2, 10, 10), _p(22, 10, 10), 481, 0)
    assert_equal(len(profile.values), 481)
    assert_equal(profile.values[0], 0)
    assert_almost_equal(profile.distances[480].to(MILLIMETER64), 24.0)
    var width = full_width_half_maximum(profile, 0).to(MILLIMETER64)
    assert_almost_equal(width, 2 * sqrt(2 * log(2.0)) * sigma, rtol=0.01)


def test_a_box_and_each_face() raises:
    # 100 from x = 8 to 12 mm and 0 elsewhere: trilinear ramps make the
    # half crossings at 7.5 and 12.5 mm.
    var volume = ImageVolume(21, 3, 3, _mm(1), _mm(1), _mm(1))
    for k in range(3):
        for j in range(3):
            for i in range(8, 13):
                volume.set(i, j, k, 100)
    var profile = line_profile(volume, _p(0, 1, 1), _p(20, 1, 1), 201, -1)
    assert_almost_equal(
        full_width_half_maximum(profile, 0).to(MILLIMETER64), 5.0, atol=1e-6
    )
    # Lines that leave through each face of the grid take the outside
    # value past it.
    var ends: List[Tuple[V3, V3]] = [
        (_p(10, -1, 1), _p(10, 3, 1)),
        (_p(10, 1, -1), _p(10, 1, 3)),
    ]
    for pair in ends:
        var line = line_profile(volume, pair[0], pair[1], 5, -7)
        assert_equal(line.values[0], -7)
        assert_equal(line.values[2], 100)
        assert_equal(line.values[4], -7)


def test_refusals() raises:
    var volume = ImageVolume(3, 3, 3, _mm(1), _mm(1), _mm(1))
    var a = _p(0, 0, 0)
    with assert_raises(contains="finite points"):
        _ = line_profile(volume, v3(inf[DType.float64](), 0, 0), a, 5, 0)
    with assert_raises(contains="two different points"):
        _ = line_profile(volume, a, a, 5, 0)
    with assert_raises(contains="from 2 to 65536 points"):
        _ = line_profile(volume, a, _p(1, 0, 0), 1, 0)
    with assert_raises(contains="from 2 to 65536 points"):
        _ = line_profile(volume, a, _p(1, 0, 0), 65537, 0)
    var flat = line_profile(volume, a, _p(2, 0, 0), 5, 0)
    with assert_raises(contains="above its baseline"):
        _ = full_width_half_maximum(flat, 0)
    with assert_raises(contains="above its baseline"):
        _ = full_width_half_maximum(LineProfile(), 0)
    # A peak at an end of the profile does not fall on that side.
    volume.set(0, 0, 0, 10)
    var left = line_profile(volume, a, _p(2, 0, 0), 5, 0)
    with assert_raises(contains="both sides"):
        _ = full_width_half_maximum(left, 0)
    var right = line_profile(volume, _p(2, 0, 0), a, 5, 0)
    with assert_raises(contains="both sides"):
        _ = full_width_half_maximum(right, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
