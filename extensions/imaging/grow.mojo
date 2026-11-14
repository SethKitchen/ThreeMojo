# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Grow a region from seeds by the statistics of the region itself.

`region_grow` needs the range of values to grow into. `confidence_connected`
finds the range itself, as ITK's `ConfidenceConnectedImageFilter` does:

1. Around each seed, a box of `radius` voxels each way gives a mean and a
   sample variance. A box that leaves the grid repeats the edge voxels.
   The mean of the means and the mean of the variances start the range:
   `mean - multiplier * sigma` to `mean + multiplier * sigma`.
2. The region grows from each seed whose value is in the range, through
   voxels that share a face and whose values are in the range, its ends
   included.
3. Each iteration takes the mean and the sample variance of the region,
   makes a new range, and grows the region again from the seeds. A region
   whose variance is zero stops the iterations.

A region of a lesion or an organ with a smooth inside grows to its edge,
where the values change.
"""

from extensions.imaging.ids import BACKGROUND, LabelId, require_label
from extensions.imaging.image_volume import ImageVolume
from extensions.imaging.labels import LabelMap
from std.math import isfinite, max, min, sqrt


def _clamp(value: Int, size: Int) -> Int:
    """Return an index held inside an axis."""
    return max(0, min(size - 1, value))


def _flood(
    volume: ImageVolume,
    seeds: List[Tuple[Int, Int, Int]],
    low: Float64,
    high: Float64,
) -> List[Bool]:
    """Return the voxels that join a seed by faces, all in the range."""
    var count = volume.count()
    var inside = List[Bool](length=count, fill=False)
    var queue = List[Int]()
    for s in seeds:  # pragma: no branch
        var at = volume.index(s[0], s[1], s[2])
        var v = Float64(volume.values[at])
        if v >= low and v <= high and not inside[at]:
            inside[at] = True
            queue.append(at)
    var steps: List[Int] = [
        1,
        -1,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        -1,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        -1,
    ]
    var head = 0
    while head < len(queue):
        var current = queue[head]
        head += 1
        var i = current % volume.nx
        var j = (current // volume.nx) % volume.ny
        var k = current // (volume.nx * volume.ny)
        for n in range(6):  # pragma: no branch
            var x = i + steps[n]
            var y = j + steps[6 + n]
            var z = k + steps[12 + n]
            if not volume.contains(x, y, z):
                continue
            var next = volume.index(x, y, z)
            if inside[next]:
                continue
            var v = Float64(volume.values[next])
            if v >= low and v <= high:
                inside[next] = True
                queue.append(next)
    return inside^


def confidence_connected(
    volume: ImageVolume,
    seeds: List[Tuple[Int, Int, Int]],
    multiplier: Float64,
    iterations: Int,
    radius: Int,
    label: LabelId,
) raises -> LabelMap:
    """Return the region that grows from seeds by its own statistics.

    Args:
        volume: The volume.
        seeds: The seed voxels, `(i, j, k)`, one or more, in the grid.
        multiplier: How many standard deviations the range reaches each
            way, such as 2.5. Positive and finite.
        iterations: How many times the range is made again from the
            region, from 0 to 100.
        radius: The half size of the box around each seed, in voxels,
            from 0 to 16. ITK's default is 1.
        label: The label of the region. Not the background.

    Returns:
        A map with the region labeled. It is empty when no seed is in the
        first range.

    Raises:
        Error: If there is no seed, a seed is outside the grid, the label
            is not valid or is the background, or a number is out of
            range.
    """
    require_label(label)
    if label == BACKGROUND:
        raise Error("A grown region needs a label other than the background")
    if len(seeds) == 0:
        raise Error("A region grows from one seed or more")
    for s in seeds:  # pragma: no branch
        if not volume.contains(s[0], s[1], s[2]):
            raise Error("A seed is outside the volume")
    if not (multiplier > 0) or not isfinite(multiplier):
        raise Error("A confidence multiplier must be positive and finite")
    if iterations < 0 or iterations > 100:
        raise Error("A region is grown again from 0 to 100 times")
    if radius < 0 or radius > 16:
        raise Error("A seed's box reaches from 0 to 16 voxels")
    # The statistics of the box around each seed, as ITK takes them.
    var mean = 0.0
    var variance = 0.0
    var side = 2 * radius + 1
    var size = Float64(side * side * side)
    for s in seeds:  # pragma: no branch
        var sum = 0.0
        var squares = 0.0
        for dk in range(-radius, radius + 1):  # pragma: no branch
            for dj in range(-radius, radius + 1):  # pragma: no branch
                for di in range(-radius, radius + 1):  # pragma: no branch
                    var v = Float64(
                        volume.get(
                            _clamp(s[0] + di, volume.nx),
                            _clamp(s[1] + dj, volume.ny),
                            _clamp(s[2] + dk, volume.nz),
                        )
                    )
                    sum += v
                    squares += v * v
        mean += sum / size
        if side > 1:
            variance += (squares - sum * sum / size) / (size - 1.0)
    mean /= Float64(len(seeds))
    variance /= Float64(len(seeds))
    var spread = multiplier * sqrt(max(variance, 0.0))
    var inside = _flood(volume, seeds, mean - spread, mean + spread)
    for _ in range(iterations):
        var count = 0
        var sum = 0.0
        var squares = 0.0
        for at in range(volume.count()):  # pragma: no branch
            if inside[at]:
                var v = Float64(volume.values[at])
                count += 1
                sum += v
                squares += v * v
        if count < 2:
            break
        mean = sum / Float64(count)
        variance = (squares - sum * sum / Float64(count)) / Float64(count - 1)
        if not (variance > 0):
            break
        spread = multiplier * sqrt(variance)
        inside = _flood(volume, seeds, mean - spread, mean + spread)
    var out = LabelMap(volume)
    var mark = UInt8(label.value)
    for at in range(volume.count()):  # pragma: no branch
        if inside[at]:
            out.labels[at] = mark
    return out^
