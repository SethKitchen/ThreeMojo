# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Volume histograms and Otsu's threshold."""

from extensions.imaging.histogram import (
    Histogram,
    label_histogram,
    otsu_threshold,
    volume_histogram,
)
from extensions.imaging.ids import BACKGROUND, LabelId
from extensions.imaging.image_volume import ImageVolume, MILLIMETER64
from extensions.imaging.labels import LabelMap, threshold
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Length64


def _row(values: List[Float32]) raises -> ImageVolume:
    """A volume of one row of voxels."""
    var mm = Length64(1.0, MILLIMETER64)
    var volume = ImageVolume(len(values), 1, 1, mm, mm, mm)
    for index in range(len(values)):
        volume.values[index] = values[index]
    return volume^


def test_bins_and_edges() raises:
    var histogram = volume_histogram(
        _row([0, 0.5, 1, 2.5, 9.99, 10, -0.1, 10.1, nan[DType.float32]()]),
        4,
        0,
        10,
    )
    assert_equal(histogram.bins(), 4)
    assert_almost_equal(histogram.width(), 2.5)
    assert_almost_equal(histogram.center(1), 3.75)
    # The high edge goes in the last bin. Values outside are not counted.
    assert_equal(histogram.counts[0], 3)
    assert_equal(histogram.counts[1], 1)
    assert_equal(histogram.counts[2], 0)
    assert_equal(histogram.counts[3], 2)
    assert_equal(histogram.total(), 6)


def test_histogram_refusals() raises:
    with assert_raises(contains="from 2 to 2^20 bins"):
        _ = Histogram(1, 0, 1)
    with assert_raises(contains="from 2 to 2^20 bins"):
        _ = Histogram((1 << 20) + 1, 0, 1)
    with assert_raises(contains="low below high"):
        _ = Histogram(2, 1, 1)
    with assert_raises(contains="low below high"):
        _ = Histogram(2, nan[DType.float64](), 1)
    with assert_raises(contains="low below high"):
        _ = Histogram(2, 0, inf[DType.float64]())


def _within(values: List[Float32], edge: Float64) -> Float64:
    """The summed squared distance of each class from its own mean."""
    var sums: List[Float64] = [0, 0]
    var counts: List[Float64] = [0, 0]
    for value in values:
        var side = 1 if Float64(value) >= edge else 0
        sums[side] += Float64(value)
        counts[side] += 1
    var out = 0.0
    for value in values:
        var side = 1 if Float64(value) >= edge else 0
        var mean = sums[side] / max(counts[side], 1.0)
        out += (Float64(value) - mean) ** 2
    return out


def test_otsu_minimizes_the_variance_within_classes() raises:
    # Two overlapping triangles of whole values, one wide and one narrow.
    var values = List[Float32]()
    for v in range(101):
        var dark = max(0, 30 - abs(v - 25))
        var bright = max(0, 12 - abs(v - 66))
        for _ in range(dark + bright):
            values.append(Float32(v))
    # One bin per whole value: each value is at the center of its bin.
    var histogram = volume_histogram(_row(values), 101, -0.5, 100.5)
    var edge = otsu_threshold(histogram)
    # The edge must be the bin edge with the least variance within the
    # classes, found here by brute force over the voxels.
    var best = _within(values, -0.5)
    var best_edge = -0.5
    for k in range(1, 101):
        var candidate = Float64(k) - 0.5
        var within = _within(values, candidate)
        if within < best - 1e-9:
            best = within
            best_edge = candidate
    assert_almost_equal(edge, best_edge)
    # The edge lies between the two peaks. It is 38.5, not in the valley:
    # Otsu's method moves the edge into the wider class.
    assert_almost_equal(edge, 38.5)


def test_otsu_skips_empty_ends() raises:
    # Empty bins at both ends, and two clusters in the middle.
    var histogram = Histogram(10, 0, 10)
    histogram.counts[3] = 5
    histogram.counts[6] = 5
    # A tie in the empty gap goes to the lowest edge.
    assert_almost_equal(otsu_threshold(histogram), 4.0)
    var single = Histogram(10, 0, 10)
    single.counts[4] = 7
    with assert_raises(contains="two bins at least"):
        _ = otsu_threshold(single)


def test_label_histogram() raises:
    var volume = _row([1, 2, 3, 4, 5, 6])
    var map = threshold(volume, 3, 5, LabelId(2))
    var histogram = label_histogram(volume, map, LabelId(2), 6, 0.5, 6.5)
    assert_equal(histogram.total(), 3)
    assert_equal(histogram.counts[2], 1)
    assert_equal(histogram.counts[5], 0)
    var other = _row([1, 2, 3])
    with assert_raises(contains="grid"):
        _ = label_histogram(other, map, LabelId(2), 6, 0.5, 6.5)
    with assert_raises(contains="label"):
        _ = label_histogram(volume, map, LabelId(300), 6, 0.5, 6.5)
    # The background is a label too.
    assert_equal(
        label_histogram(volume, map, BACKGROUND, 6, 0.5, 6.5).total(), 3
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
