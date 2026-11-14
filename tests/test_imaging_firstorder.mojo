# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""First-order features of the values inside a label."""

from extensions.imaging.firstorder import intensity_features
from extensions.imaging.ids import BACKGROUND, LabelId
from extensions.imaging.image_volume import ImageVolume, MILLIMETER64
from extensions.imaging.labels import LabelMap
from std.math import inf, log, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
)
from units.si import Length64


def _region(values: List[Float32]) raises -> Tuple[ImageVolume, LabelMap]:
    """Return a row of voxels with these values, all in label 1, and one
    more voxel of 1000 outside the label."""
    var mm = Length64(1.0, MILLIMETER64)
    var volume = ImageVolume(len(values) + 1, 1, 1, mm, mm, mm)
    var map = LabelMap(volume)
    for i in range(len(values)):
        volume.set(i, 0, 0, values[i])
        map.set(i, 0, 0, LabelId(1))
    volume.set(len(values), 0, 0, 1000)
    return (volume^, map^)


def test_a_known_set() raises:
    # 1, 2, 3, 4 and 10: mean 4, deviation sqrt(10).
    var values: List[Float32] = [1, 2, 3, 4, 10]
    var parts = _region(values)
    var f = intensity_features(parts[0], parts[1], LabelId(1), 2, 0, 10)
    assert_equal(f.voxels, 5)
    assert_almost_equal(f.mean, 4.0)
    assert_almost_equal(f.deviation, sqrt(10.0))
    # Moments about 4: -3, -2, -1, 0 and 6.
    assert_almost_equal(f.skewness, (-27 - 8 - 1 + 216) / 5.0 / 10.0**1.5)
    assert_almost_equal(f.kurtosis, (81 + 16 + 1 + 1296) / 5.0 / 100.0)
    assert_almost_equal(f.minimum, 1.0)
    assert_almost_equal(f.maximum, 10.0)
    assert_almost_equal(f.median, 3.0)
    # Rank 0.4 and rank 3.6 of the sorted values.
    assert_almost_equal(f.p10, 1.4)
    assert_almost_equal(f.p90, 7.6)
    assert_almost_equal(f.interquartile, 4.0 - 2.0)
    assert_almost_equal(f.energy, 1 + 4 + 9 + 16 + 100.0)
    # Two bins of 0 to 5 and 5 to 10: four values, then one; the top value
    # stays in the last bin.
    var p = 0.8
    var q = 0.2
    assert_almost_equal(f.entropy, -(p * log(p) + q * log(q)) / log(2.0))
    # The value of numpy and of Python's math.log2, to the last digit.
    assert_almost_equal(f.entropy, 0.7219280948873623, atol=2e-16, rtol=0)
    assert_almost_equal(f.uniformity, p * p + q * q)


def test_one_value_and_clamped_bins() raises:
    var values: List[Float32] = [7, 7, 7]
    var parts = _region(values)
    var f = intensity_features(parts[0], parts[1], LabelId(1), 4, 0, 1)
    assert_equal(f.deviation, 0.0)
    assert_equal(f.skewness, 0.0)
    assert_equal(f.kurtosis, 0.0)
    # Every value is past the range, so all sit in the last bin.
    assert_equal(f.entropy, 0.0)
    assert_equal(f.uniformity, 1.0)
    var low: List[Float32] = [-5, -6]
    var under = _region(low)
    var g = intensity_features(under[0], under[1], LabelId(1), 4, 0, 1)
    assert_equal(g.uniformity, 1.0)


def test_refusals() raises:
    var values: List[Float32] = [1, 2]
    var parts = _region(values)
    ref volume = parts[0]
    ref map = parts[1]
    with assert_raises(contains="background"):
        _ = intensity_features(volume, map, BACKGROUND, 2, 0, 1)
    with assert_raises(contains="no voxels"):
        _ = intensity_features(volume, map, LabelId(9), 2, 0, 1)
    with assert_raises(contains="bins"):
        _ = intensity_features(volume, map, LabelId(1), 0, 0, 1)
    with assert_raises(contains="bins"):
        _ = intensity_features(volume, map, LabelId(1), 65537, 0, 1)
    with assert_raises(contains="range"):
        _ = intensity_features(volume, map, LabelId(1), 2, 1, 1)
    with assert_raises(contains="range"):
        _ = intensity_features(
            volume, map, LabelId(1), 2, -inf[DType.float64](), 1
        )
    with assert_raises(contains="range"):
        _ = intensity_features(
            volume, map, LabelId(1), 2, 0, inf[DType.float64]()
        )
    var other = LabelMap(
        ImageVolume(
            9,
            1,
            1,
            Length64(1.0, MILLIMETER64),
            Length64(1.0, MILLIMETER64),
            Length64(1.0, MILLIMETER64),
        )
    )
    with assert_raises(contains="different grids"):
        _ = intensity_features(volume, other, LabelId(1), 2, 0, 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
