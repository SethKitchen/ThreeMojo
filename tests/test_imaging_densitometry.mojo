# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CT density measures on volumes of known values."""

from extensions.imaging.densitometry import (
    attenuation_percentile,
    low_attenuation_fraction,
    tissue_area,
)
from extensions.imaging.ids import (
    BACKGROUND,
    I_AXIS,
    J_AXIS,
    K_AXIS,
    LabelId,
    SliceAxis,
)
from extensions.imaging.image_volume import ImageVolume, MILLIMETER64
from extensions.imaging.labels import LabelMap
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
)
from units.si import Length64, SQUARE_METER


def _lung() raises -> Tuple[ImageVolume, LabelMap]:
    """A grid of 10 by 10 by 2 voxels of 0.5 by 0.8 by 2 mm. The lung is
    the first slice, with the values -1000 to -901 HU in order; the second
    slice is soft tissue of 40 HU."""
    var volume = ImageVolume(
        10,
        10,
        2,
        Length64(0.5, MILLIMETER64),
        Length64(0.8, MILLIMETER64),
        Length64(2.0, MILLIMETER64),
    )
    var map = LabelMap(volume)
    for at in range(100):
        volume.values[at] = Float32(-1000 + at)
        map.labels[at] = 1
    for at in range(100, 200):
        volume.values[at] = 40
        map.labels[at] = 2
    return (volume^, map^)


def test_lung_measures() raises:
    var lung = _lung()
    ref volume = lung[0]
    ref map = lung[1]
    # The values below -950 HU are -1000 to -951: half the lung.
    assert_equal(low_attenuation_fraction(volume, map, LabelId(1), -950), 0.5)
    assert_equal(low_attenuation_fraction(volume, map, LabelId(2), -950), 0.0)
    # Perc15 at rank 0.15 * 99 = 14.85.
    assert_almost_equal(
        attenuation_percentile(volume, map, LabelId(1), 15), -985.15
    )
    assert_equal(attenuation_percentile(volume, map, LabelId(1), 100), -901.0)


def test_tissue_area() raises:
    var lung = _lung()
    ref volume = lung[0]
    ref map = lung[1]
    # The soft tissue slice: 100 pixels of 0.5 by 0.8 mm.
    assert_almost_equal(
        tissue_area(volume, map, LabelId(2), K_AXIS, 1, -29, 150).to(
            SQUARE_METER
        ),
        100 * 0.4e-6,
    )
    # -1000 to -951 HU of the lung slice: 50 pixels.
    assert_almost_equal(
        tissue_area(volume, map, LabelId(1), K_AXIS, 0, -1000, -951).to(
            SQUARE_METER
        ),
        50 * 0.4e-6,
    )
    # The slice of i = 3 holds ten lung voxels and ten of soft tissue,
    # pixels of 0.8 by 2 mm.
    assert_almost_equal(
        tissue_area(volume, map, LabelId(2), I_AXIS, 3, 0, 100).to(
            SQUARE_METER
        ),
        10 * 1.6e-6,
    )
    # The slice of j = 2 holds lung values -980 to -971.
    assert_almost_equal(
        tissue_area(volume, map, LabelId(1), J_AXIS, 2, -975, -900).to(
            SQUARE_METER
        ),
        5 * 1.0e-6,
    )


def test_refusals() raises:
    var lung = _lung()
    ref volume = lung[0]
    ref map = lung[1]
    with assert_raises(contains="threshold must be finite"):
        _ = low_attenuation_fraction(
            volume, map, LabelId(1), nan[DType.float64]()
        )
    with assert_raises(contains="not the background"):
        _ = low_attenuation_fraction(volume, map, BACKGROUND, -950)
    with assert_raises(contains="label"):
        _ = attenuation_percentile(volume, map, LabelId(300), 15)
    with assert_raises(contains="with voxels"):
        _ = attenuation_percentile(volume, map, LabelId(5), 15)
    with assert_raises(contains="from 0 to 100"):
        _ = attenuation_percentile(volume, map, LabelId(1), 101)
    var other = LabelMap(
        ImageVolume(
            2,
            2,
            2,
            Length64(1.0, MILLIMETER64),
            Length64(1.0, MILLIMETER64),
            Length64(1.0, MILLIMETER64),
        )
    )
    with assert_raises(contains="different grids"):
        _ = low_attenuation_fraction(volume, other, LabelId(1), -950)
    with assert_raises(contains="different grids"):
        _ = tissue_area(volume, other, LabelId(1), K_AXIS, 0, 0, 1)
    with assert_raises(contains="not the background"):
        _ = tissue_area(volume, map, BACKGROUND, K_AXIS, 0, 0, 1)
    with assert_raises(contains="label"):
        _ = tissue_area(volume, map, LabelId(-1), K_AXIS, 0, 0, 1)
    with assert_raises(contains="axis"):
        _ = tissue_area(volume, map, LabelId(1), SliceAxis(3), 0, 0, 1)
    var slices: List[Int] = [-1, 2]
    for s in slices:
        with assert_raises(contains="outside the volume"):
            _ = tissue_area(volume, map, LabelId(1), K_AXIS, s, 0, 1)
    var ranges: List[Float64] = [inf[DType.float64](), 0.0, 5.0]
    var tops: List[Float64] = [1.0, inf[DType.float64](), 1.0]
    for n in range(3):
        with assert_raises(contains="do not fall"):
            _ = tissue_area(
                volume, map, LabelId(1), K_AXIS, 0, ranges[n], tops[n]
            )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
