# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Histograms of volume values, and Otsu's automatic threshold.

`volume_histogram` counts the values of a volume in bins of equal width
from `low` to `high`. `label_histogram` counts only the voxels of one
label. A value outside the range is not counted.

`otsu_threshold` splits a histogram in two classes at the bin edge that
gives the largest variance between the classes (Otsu, 1979):

    w0 * w1 * (mean0 - mean1)^2

`w0` and `w1` are the voxel counts of the two classes, and each mean is
over the bin centers of its class. The largest variance between the
classes is the smallest variance within them. Use the threshold as the
low end of `threshold` to label the brighter class.
"""

from extensions.imaging.ids import LabelId, require_label
from extensions.imaging.image_volume import ImageVolume
from extensions.imaging.labels import LabelMap, require_same_grid
from std.math import floor, isfinite, min

# The most bins a histogram can have.
comptime MAX_BINS = 1 << 20


struct Histogram(Copyable, Movable):
    """Voxel counts in bins of equal width."""

    var low: Float64
    """The low edge of the first bin."""
    var high: Float64
    """The high edge of the last bin."""
    var counts: List[Int]
    """The voxels in each bin."""

    def __init__(out self, bins: Int, low: Float64, high: Float64) raises:
        """Create a histogram of empty bins.

        Args:
            bins: The number of bins, from 2 to 2^20.
            low: The low edge of the first bin. Finite.
            high: The high edge of the last bin. Finite and above `low`.

        Raises:
            Error: If the bins are out of range, or the edges are not
                finite and in order.
        """
        if bins < 2 or bins > MAX_BINS:
            raise Error("A histogram has from 2 to 2^20 bins")
        if not (isfinite(low) and isfinite(high) and low < high):
            raise Error("A histogram range must be finite, with low below high")
        self.low = low
        self.high = high
        self.counts = List[Int](length=bins, fill=0)

    def bins(self) -> Int:
        """Return the number of bins.

        Returns:
            The length of `counts`.
        """
        return len(self.counts)

    def width(self) -> Float64:
        """Return the width of one bin.

        Returns:
            `(high - low) / bins`.
        """
        return (self.high - self.low) / Float64(self.bins())

    def center(self, bin: Int) -> Float64:
        """Return the center of a bin.

        Args:
            bin: The bin, from zero.

        Returns:
            `low + (bin + 0.5) * width`.
        """
        return self.low + (Float64(bin) + 0.5) * self.width()

    def total(self) -> Int:
        """Return the number of counted voxels.

        Returns:
            The sum of `counts`.
        """
        var sum = 0
        for count in self.counts:  # pragma: no branch
            sum += count
        return sum

    def add(mut self, value: Float64):
        """Count one value, if it is in the range.

        A value equal to `high` goes in the last bin. Other values outside
        the range, and values that are not numbers, are not counted.

        Args:
            value: The value.
        """
        if not (value >= self.low and value <= self.high):
            return
        var bin = Int(floor((value - self.low) / self.width()))
        self.counts[min(bin, self.bins() - 1)] += 1


def volume_histogram(
    volume: ImageVolume, bins: Int, low: Float64, high: Float64
) raises -> Histogram:
    """Return the histogram of every value of a volume.

    Args:
        volume: The volume.
        bins: The number of bins, from 2 to 2^20.
        low: The low edge of the first bin.
        high: The high edge of the last bin.

    Returns:
        The counts. A value outside the range is not counted.

    Raises:
        Error: If the bins or the range are not valid.
    """
    var histogram = Histogram(bins, low, high)
    # A volume holds at least one voxel.
    for value in volume.values:  # pragma: no branch
        histogram.add(Float64(value))
    return histogram^


def label_histogram(
    volume: ImageVolume,
    map: LabelMap,
    label: LabelId,
    bins: Int,
    low: Float64,
    high: Float64,
) raises -> Histogram:
    """Return the histogram of the values of one label's voxels.

    Args:
        volume: The volume.
        map: The label map, on the grid of the volume.
        label: The label.
        bins: The number of bins, from 2 to 2^20.
        low: The low edge of the first bin.
        high: The high edge of the last bin.

    Returns:
        The counts. A value outside the range is not counted.

    Raises:
        Error: If the grids differ, the label is not valid, or the bins or
            the range are not valid.
    """
    require_same_grid(map, volume)
    require_label(label)
    var histogram = Histogram(bins, low, high)
    var mark = UInt8(label.value)
    for index in range(volume.count()):  # pragma: no branch
        if map.labels[index] == mark:
            histogram.add(Float64(volume.values[index]))
    return histogram^


def otsu_threshold(histogram: Histogram) raises -> Float64:
    """Return the bin edge that best splits a histogram in two classes.

    Of two edges with the same variance between the classes, the lower
    edge wins.

    Args:
        histogram: The histogram.

    Returns:
        The edge between the two classes. The values below it are the
        dark class.

    Raises:
        Error: If fewer than two bins hold voxels.
    """
    var total = 0.0
    var weighted = 0.0
    for bin in range(histogram.bins()):  # pragma: no branch
        var count = Float64(histogram.counts[bin])
        total += count
        weighted += count * histogram.center(bin)
    var best = -1.0
    var split = -1
    var below = 0.0
    var below_weighted = 0.0
    for bin in range(histogram.bins() - 1):  # pragma: no branch
        var count = Float64(histogram.counts[bin])
        below += count
        below_weighted += count * histogram.center(bin)
        var above = total - below
        if below == 0 or above == 0:
            continue
        var gap = below_weighted / below - (weighted - below_weighted) / above
        var between = below * above * gap * gap
        if between > best:
            best = between
            split = bin
    if split < 0:
        raise Error("Otsu's method needs voxels in two bins at least")
    return histogram.low + Float64(split + 1) * histogram.width()
