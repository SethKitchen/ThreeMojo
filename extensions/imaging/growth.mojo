# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Measures of a tumor over time: growth, longest diameter and response.

Oncology research follows a tumor across scans.

- `doubling_time(first, second, interval)` is the time in which the
  volume doubles at the growth between two scans:
  `interval ln 2 / ln(V2 / V1)`. A tumor that shrinks has a negative
  doubling time, whose size is its halving time.
- `growth_rate(first, second, interval)` is the specific growth rate,
  `ln(V2 / V1) / interval`. It is 0 when the volume does not change, so
  it can be averaged where a doubling time cannot.
- `longest_diameter(map, label)` is the longest distance between two
  voxel centers of a label in one slice of `k`, and the two voxels. RECIST
  1.1 measures a target lesion by its longest diameter in the axial
  plane.
- `recist_response(baseline, nadir, current)` gives the response of the
  target lesions from the sums of their longest diameters:

| Response | Rule |
|---|---|
| `COMPLETE_RESPONSE` | The current sum is 0 |
| `PROGRESSIVE_DISEASE` | The sum grew by 20 percent or more of the nadir, and by 5 mm or more |
| `PARTIAL_RESPONSE` | The sum fell by 30 percent or more of the baseline |
| `STABLE_DISEASE` | Neither |

Progressive disease comes before a partial response. The nadir is the
least sum so far, the baseline included. The thresholds hold to 1e-9 of
the sums, so that sums in millimeters meet them exactly.
"""

from extensions.imaging.ids import (
    BACKGROUND,
    COMPLETE_RESPONSE,
    LabelId,
    PARTIAL_RESPONSE,
    PROGRESSIVE_DISEASE,
    ResponseCategory,
    STABLE_DISEASE,
    require_label,
    require_response,
)
from extensions.imaging.labels import LabelMap
from std.math import isfinite, log, sqrt
from units.quantity import Unit
from units.si import (
    CUBIC_METER,
    METER,
    MILLIMETER64,
    PER_DAY64,
    PER_SECOND64,
    SECOND,
    Duration64,
    Frequency64,
    Length64,
    Volume64,
)

# The RECIST thresholds hold to this part of the sums.
comptime ROUNDING = 1.0e-9


def _growth(
    first: Volume64, second: Volume64, interval: Duration64
) raises -> Float64:
    """Return `ln(V2 / V1)`, after the inputs are checked."""
    var a = first.to(CUBIC_METER)
    var b = second.to(CUBIC_METER)
    var t = interval.to(SECOND)
    if not (a > 0) or not isfinite(a) or not (b > 0) or not isfinite(b):
        raise Error("A tumor volume must be positive and finite")
    if not (t > 0) or not isfinite(t):
        raise Error("The time between two scans must be positive and finite")
    return log(b / a)


def doubling_time(
    first: Volume64, second: Volume64, interval: Duration64
) raises -> Duration64:
    """Return the time in which a volume doubles at its growth.

    Args:
        first: The volume at the first scan.
        second: The volume at the second scan.
        interval: The time from the first scan to the second.

    Returns:
        `interval ln 2 / ln(second / first)`. It is negative when the
        volume falls, and its size is then the halving time.

    Raises:
        Error: If a volume is not positive and finite, the interval is
            not positive and finite, or the two volumes are equal.
    """
    var growth = _growth(first, second, interval)
    if growth == 0:
        raise Error("Two equal volumes have no doubling time")
    return Duration64(interval.to(SECOND) * log(2.0) / growth, SECOND)


def growth_rate(
    first: Volume64, second: Volume64, interval: Duration64
) raises -> Frequency64:
    """Return the specific growth rate of a volume.

    Args:
        first: The volume at the first scan.
        second: The volume at the second scan.
        interval: The time from the first scan to the second.

    Returns:
        `ln(second / first) / interval`, such as 0.01 a day for a volume
        that grows by 1 percent a day. Read it with `PER_DAY64`.

    Raises:
        Error: If a volume is not positive and finite, or the interval
            is not positive and finite.
    """
    var growth = _growth(first, second, interval)
    return Frequency64(growth / interval.to(SECOND), PER_SECOND64)


struct LongestDiameter(Copyable, Movable):
    """The longest diameter of a label in one slice of `k`."""

    var length: Length64
    """The distance between the centers of the two voxels."""
    var first: Tuple[Int, Int, Int]
    """One end, as the voxel `(i, j, k)`."""
    var second: Tuple[Int, Int, Int]
    """The other end, on the same slice."""

    def __init__(
        out self,
        length: Length64,
        first: Tuple[Int, Int, Int],
        second: Tuple[Int, Int, Int],
    ):
        """Create a diameter.

        Args:
            length: The length.
            first: One end.
            second: The other end.
        """
        self.length = length
        self.first = first
        self.second = second


def _inner(map: LabelMap, i: Int, j: Int, k: Int, mark: UInt8) -> Bool:
    """Return whether a voxel's four neighbors in its slice all hold the
    label."""
    if i == 0 or j == 0 or i == map.nx - 1 or j == map.ny - 1:
        return False
    var steps: List[Int] = [-1, 0, 1, 0, 0, -1, 0, 1]
    for n in range(4):  # pragma: no branch
        if (
            map.labels[map.index(i + steps[2 * n], j + steps[2 * n + 1], k)]
            != mark
        ):
            return False
    return True


def longest_diameter(map: LabelMap, label: LabelId) raises -> LongestDiameter:
    """Return the longest distance in one slice between two voxels of a
    label.

    The longest distance runs between two voxels on the edge of the
    label, so only those are searched.

    Args:
        map: The label map, with the spacing of its volume.
        label: The label of one lesion. Not the background.

    Returns:
        The diameter, between voxel centers. RECIST measures from edge to
        edge, which is about one pixel more.

    Raises:
        Error: If the label is not valid, is the background, or has no
            voxel.
    """
    require_label(label)
    if label == BACKGROUND:
        raise Error("A diameter needs a label, not the background")
    var mark = UInt8(label.value)
    var sx = map.spacing_x.to(METER)
    var sy = map.spacing_y.to(METER)
    var best = -1.0
    var first = (0, 0, 0)
    var second = (0, 0, 0)
    for k in range(map.nz):  # pragma: no branch
        var xs = List[Int]()
        var ys = List[Int]()
        for j in range(map.ny):  # pragma: no branch
            for i in range(map.nx):  # pragma: no branch
                if map.labels[map.index(i, j, k)] != mark:
                    continue
                if _inner(map, i, j, k, mark):
                    continue
                xs.append(i)
                ys.append(j)
        for p in range(len(xs)):
            for q in range(p, len(xs)):  # pragma: no branch
                var dx = Float64(xs[q] - xs[p]) * sx
                var dy = Float64(ys[q] - ys[p]) * sy
                var d = dx * dx + dy * dy
                if d > best:
                    best = d
                    first = (xs[p], ys[p], k)
                    second = (xs[q], ys[q], k)
    if best < 0:
        raise Error("A diameter needs a label with one voxel or more")
    return LongestDiameter(Length64(sqrt(best), METER), first, second)


def recist_response(
    baseline: Length64, nadir: Length64, current: Length64
) raises -> ResponseCategory:
    """Return the RECIST 1.1 response of the target lesions.

    Args:
        baseline: The sum of the longest diameters at the baseline.
            Positive and finite.
        nadir: The least sum so far, the baseline included. From 0 to the
            baseline.
        current: The sum now. 0 or more, and finite.

    Returns:
        `COMPLETE_RESPONSE`, `PROGRESSIVE_DISEASE`, `PARTIAL_RESPONSE` or
        `STABLE_DISEASE`, by the rules of the module.

    Raises:
        Error: If a sum is out of its range.
    """
    var b = baseline.to(METER)
    var n = nadir.to(METER)
    var c = current.to(METER)
    if not (b > 0) or not isfinite(b):
        raise Error("A baseline sum must be positive and finite")
    if not (n >= 0) or n > b * (1.0 + ROUNDING):
        raise Error("A nadir sum is from 0 to the baseline sum")
    if not (c >= 0) or not isfinite(c):
        raise Error("A current sum must be 0 or more, and finite")
    if c == 0:
        return COMPLETE_RESPONSE
    var growth = c - n
    var least = Length64(5.0, MILLIMETER64).to(METER) * (1.0 - ROUNDING)
    if growth >= 0.2 * n * (1.0 - ROUNDING) and growth >= least:
        return PROGRESSIVE_DISEASE
    if c <= 0.7 * b * (1.0 + ROUNDING):
        return PARTIAL_RESPONSE
    return STABLE_DISEASE


def response_name(response: ResponseCategory) raises -> String:
    """Return the short name of a response.

    Args:
        response: The response.

    Returns:
        `CR`, `PR`, `SD` or `PD`.

    Raises:
        Error: If the response is not valid.
    """
    require_response(response)
    var names: List[String] = ["CR", "PR", "SD", "PD"]
    return names[response.value]
