# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Thick-slab projections on a plane."""

from extensions.imaging.ids import (
    SLAB_MAXIMUM,
    SLAB_MEAN,
    SLAB_MINIMUM,
    SlabMode,
    require_slab_mode,
)
from extensions.imaging.image_volume import ImageVolume
from extensions.imaging.reformat import slab_projection
from extensions.sdf.vector import V3, v3
from std.math import inf
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import MILLIMETER64, Length64


def _mm(value: Float64) -> Length64:
    return Length64(value, MILLIMETER64)


def _ramp() raises -> ImageVolume:
    """Values that rise by one per millimeter along z."""
    var volume = ImageVolume(9, 9, 13, _mm(1), _mm(1), _mm(1))
    for k in range(13):
        for j in range(9):
            for i in range(9):
                volume.set(i, j, k, Float32(k))
    return volume^


def _slab(
    volume: ImageVolume, thickness: Float64, samples: Int, mode: SlabMode
) raises -> ImageVolume:
    # An axial plane through z = 6 mm: right along x and down along y, so
    # the normal is +z.
    return slab_projection(
        volume,
        v3(0.004, 0.004, 0.006),
        v3(1, 0, 0),
        v3(0, 1, 0),
        5,
        5,
        _mm(1),
        _mm(thickness),
        samples,
        mode,
        -1000,
    )


def test_projections_of_a_ramp() raises:
    var volume = _ramp()
    # Planes at -1.5, -0.5, 0.5 and 1.5 mm from the center.
    var top = _slab(volume, 4, 4, SLAB_MAXIMUM)
    var bottom = _slab(volume, 4, 4, SLAB_MINIMUM)
    var mean = _slab(volume, 4, 4, SLAB_MEAN)
    for index in range(25):
        assert_almost_equal(top.values[index], 7.5, atol=1e-5)
        assert_almost_equal(bottom.values[index], 4.5, atol=1e-5)
        assert_almost_equal(mean.values[index], 6.0, atol=1e-5)
    # The slice lies on the center plane.
    assert_almost_equal(mean.origin.z, 0.006, atol=1e-12)
    assert_almost_equal(mean.origin.x, 0.002, atol=1e-12)
    # One plane is an oblique slice.
    var thin = _slab(volume, 4, 1, SLAB_MEAN)
    assert_almost_equal(thin.values[12], 6.0, atol=1e-5)


def test_outside_counts() raises:
    # A slab that reaches past the top of the volume takes the outside
    # value there, so the least sample is the outside value.
    var volume = _ramp()
    var deep = slab_projection(
        volume,
        v3(0.004, 0.004, 0.012),
        v3(1, 0, 0),
        v3(0, 1, 0),
        3,
        3,
        _mm(1),
        _mm(4),
        4,
        SLAB_MINIMUM,
        -1000,
    )
    assert_equal(deep.values[4], -1000)


def test_refusals() raises:
    var volume = _ramp()
    with assert_raises(contains="slab mode"):
        _ = _slab(volume, 4, 4, SlabMode(3))
    with assert_raises(contains="thickness must be positive"):
        _ = _slab(volume, 0, 4, SLAB_MEAN)
    with assert_raises(contains="thickness must be positive"):
        _ = _slab(volume, inf[DType.float64](), 4, SLAB_MEAN)
    with assert_raises(contains="from 1 to 256 planes"):
        _ = _slab(volume, 4, 0, SLAB_MEAN)
    with assert_raises(contains="from 1 to 256 planes"):
        _ = _slab(volume, 4, 257, SLAB_MEAN)
    require_slab_mode(SLAB_MINIMUM)
    with assert_raises(contains="from 0 to 2"):
        require_slab_mode(SlabMode(-1))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
