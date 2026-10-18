# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Frame-time samples for a benchmark report.

A sample is a duration in nanoseconds. The report sorts them and reads a
nearest-rank percentile in milliseconds.
"""


def _sorted(var times: List[Int]) -> List[Int]:
    """Return the samples in ascending order.

    Args:
        times: The samples, in nanoseconds. The list is reordered.

    Returns:
        The same list, sorted.
    """
    for i in range(1, len(times)):
        var j = i
        while j > 0 and times[j - 1] > times[j]:
            times.swap_elements(j - 1, j)
            j -= 1
    return times^


def _percentile(times: List[Int], fraction: Float64) -> Float64:
    """Return one nearest-rank percentile, in milliseconds.

    Args:
        times: Samples in nanoseconds, already sorted ascending.
        fraction: The rank, from zero to one.

    Returns:
        The sample at that rank, in milliseconds.
    """
    # Nearest rank on a sorted list.
    var rank = Int(fraction * Float64(len(times)) + 0.999999) - 1
    rank = max(0, min(rank, len(times) - 1))
    return Float64(times[rank]) / 1e6
