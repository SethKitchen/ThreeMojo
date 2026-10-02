# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Compare navigation queue operations without graph or geometry work."""

from extensions.carla.search_queue import _MinCostQueue
from std.time import perf_counter_ns


def _linear(count: Int) -> Int:
    var entries = List[Tuple[Float64, Int]]()
    for i in range(count):
        entries.append((Float64((i * 37) % 97), i))
    var checksum = 0
    while len(entries) > 0:
        var best = 0
        for i in range(1, len(entries)):
            if entries[i][0] < entries[best][0] or (
                entries[i][0] == entries[best][0]
                and entries[i][1] < entries[best][1]
            ):
                best = i
        checksum += entries.pop(best)[1]
    return checksum


def _heap(count: Int) raises -> Int:
    var queue = _MinCostQueue()
    for i in range(count):
        queue.push(Float64((i * 37) % 97), i)
    var checksum = 0
    while len(queue) > 0:
        checksum += queue.pop()[1]
    return checksum


def main() raises:
    for count in [100, 1000, 10000]:
        var start = perf_counter_ns()
        var linear = _linear(count)
        var linear_ns = perf_counter_ns() - start
        start = perf_counter_ns()
        var heap = _heap(count)
        var heap_ns = perf_counter_ns() - start
        if linear != heap:
            raise Error("Queue checksums differ")
        print(count, "entries; linear ns", linear_ns, "heap ns", heap_ns)
