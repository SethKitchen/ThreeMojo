# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""First-order features of the values inside a label.

Radiomics describes a region first by the spread of its values, without
regard to where they lie. `intensity_features` gives, over the voxels of
one label:

| Feature | Definition |
|---|---|
| `mean` | The mean value |
| `deviation` | The standard deviation, with `n` (not `n - 1`) |
| `skewness` | The third central moment over the deviation cubed |
| `kurtosis` | The fourth central moment over the deviation to the fourth; 3 for a normal law |
| `minimum`, `maximum` | The least and the largest value |
| `p10`, `median`, `p90` | The 10th, 50th and 90th percentiles |
| `interquartile` | The 75th percentile less the 25th |
| `energy` | The sum of the squared values |
| `entropy` | `-sum(p log2 p)` over the histogram of `bins` bins |
| `uniformity` | `sum(p^2)` over the same histogram |

The percentiles interpolate linearly between ranks, as numpy's default
does. The histogram has `bins` bins of one width from `low` to `high`;
a value outside them falls in the first or the last bin. A region of
one value has a skewness and a kurtosis of 0.
"""

from extensions.imaging.compare import percentile
from extensions.imaging.ids import BACKGROUND, LabelId, require_label
from extensions.imaging.image_volume import ImageVolume
from extensions.imaging.labels import LabelMap, require_same_grid
from std.math import floor, isfinite, log, max, min, sqrt


@fieldwise_init
struct IntensityFeatures(Copyable, Movable):
    """The first-order features of one label."""

    var voxels: Int
    """The number of voxels."""
    var mean: Float64
    """The mean value."""
    var deviation: Float64
    """The standard deviation, with `n`."""
    var skewness: Float64
    """The third standardized moment."""
    var kurtosis: Float64
    """The fourth standardized moment, 3 for a normal law."""
    var minimum: Float64
    """The least value."""
    var p10: Float64
    """The 10th percentile."""
    var median: Float64
    """The 50th percentile."""
    var p90: Float64
    """The 90th percentile."""
    var maximum: Float64
    """The largest value."""
    var interquartile: Float64
    """The 75th percentile less the 25th."""
    var energy: Float64
    """The sum of the squared values."""
    var entropy: Float64
    """The entropy of the histogram, in bits."""
    var uniformity: Float64
    """The sum of the squared shares of the histogram."""


def intensity_features(
    volume: ImageVolume,
    map: LabelMap,
    label: LabelId,
    bins: Int,
    low: Float64,
    high: Float64,
) raises -> IntensityFeatures:
    """Return the first-order features of the values inside a label.

    Args:
        volume: The volume.
        map: Its label map.
        label: The region. Not the background.
        bins: The bins of the histogram, from 1 to 65536.
        low: The bottom of the first bin.
        high: The top of the last bin. Above `low`.

    Returns:
        The features.

    Raises:
        Error: If the grids differ, the label is not valid or is the
            background, the label has no voxels, `bins` is out of range,
            or the range is not finite or falls.
    """
    require_same_grid(map, volume)
    require_label(label)
    if label == BACKGROUND:
        raise Error(
            "First-order features need a label other than the background"
        )
    if bins < 1 or bins > 65536:
        raise Error("A histogram has from 1 to 65536 bins")
    if not isfinite(low) or not isfinite(high) or not (high > low):
        raise Error("A histogram range must be finite and rise")
    var mark = UInt8(label.value)
    var values = List[Float64]()
    for at in range(volume.count()):  # pragma: no branch
        if map.labels[at] == mark:
            values.append(Float64(volume.values[at]))
    var n = len(values)
    if n == 0:
        raise Error("The label has no voxels")
    var sum = 0.0
    var energy = 0.0
    for v in values:  # pragma: no branch
        sum += v
        energy += v * v
    var mean = sum / Float64(n)
    var m2 = 0.0
    var m3 = 0.0
    var m4 = 0.0
    var counts = List[Int](length=bins, fill=0)
    var scale = Float64(bins) / (high - low)
    for v in values:  # pragma: no branch
        var d = v - mean
        m2 += d * d
        m3 += d * d * d
        m4 += d * d * d * d
        var bin = Int(floor((v - low) * scale))
        counts[max(0, min(bins - 1, bin))] += 1
    m2 /= Float64(n)
    m3 /= Float64(n)
    m4 /= Float64(n)
    var skewness = 0.0
    var kurtosis = 0.0
    if m2 > 0:
        skewness = m3 / (m2 * sqrt(m2))
        kurtosis = m4 / (m2 * m2)
    # The Float64 `log2` of the standard library is off by about 1e-9;
    # `log` is exact to rounding, so the sum is in nats and then in bits.
    var entropy = 0.0
    var uniformity = 0.0
    for c in counts:  # pragma: no branch
        if c == 0:
            continue
        var p = Float64(c) / Float64(n)
        entropy -= p * log(p)
        uniformity += p * p
    return IntensityFeatures(
        n,
        mean,
        sqrt(m2),
        skewness,
        kurtosis,
        percentile(values, 0),
        percentile(values, 10),
        percentile(values, 50),
        percentile(values, 90),
        percentile(values, 100),
        percentile(values, 75) - percentile(values, 25),
        energy,
        entropy / log(2.0),
        uniformity,
    )
