# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Time ordinary R-tree queries separately from finite-extreme kernels.

Build the same source against the published base and the candidate. The
ordinary checksums must match. The extreme checksums intentionally change:
the base is known to return wrong distances and slab decisions.
"""

from extensions.carla.rtree import (
    SegmentCloudRtree, _segment_distance2, segment_intersects_box,
)
from math.bounds import Box3
from math.vector3 import Vector3
from std.time import perf_counter_ns


@no_inline
def _kernel(extreme: Bool) -> Float64:
    var total = Float64(0)
    var scale = Float32(1e38 if extreme else 10)
    var a = Vector3(-scale, -scale, 0)
    var b = Vector3(-1, -2, 0)
    for i in range(100000):
        total += _segment_distance2(a, b, Vector3(-2, -2, Float32(i % 7) * 0.25))
    return total


@no_inline
def _slab(extreme: Bool) -> Int:
    var hits = 0
    var scale = Float32(1e38 if extreme else 10)
    var a = Vector3(-scale, -scale, 0)
    var b = Vector3(scale, scale, 0)
    for i in range(100000):
        var box = Box3(Vector3(0, Float32(i % 3), -1), Vector3(1, 3, 1))
        hits += Int(segment_intersects_box(a, b, box))
    return hits


def main() raises:
    var tree = SegmentCloudRtree()
    for i in range(1000):
        var x = Float32((i * 37) % 211)
        var y = Float32((i * 73) % 199)
        tree.insert_element(Vector3(x, y, 0), Vector3(x + 5, y + 2, 1), i, i)
    var start = perf_counter_ns()
    var checksum = 0
    for i in range(1000):
        var query = Vector3(Float32(i % 211), Float32((i * 13) % 199), 2)
        var found = tree.get_nearest_neighbours(query, 4)
        for entry in found:
            checksum += entry.start_value
    print("ordinary_nearest_ns", perf_counter_ns() - start, "checksum", checksum)
    for extreme in [False, True]:
        start = perf_counter_ns()
        var distances = _kernel(extreme)
        print("distance_extreme", extreme, "ns", perf_counter_ns() - start, "checksum", distances)
        start = perf_counter_ns()
        var hits = _slab(extreme)
        print("slab_extreme", extreme, "ns", perf_counter_ns() - start, "checksum", hits)
