# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Measure ordinary and extreme hull construction and containment.

Compile the same file with each library tree. Ordinary checksums must agree.
The subnormal/mixed cases extend the former supported domain. Each row has
an explicit workload count; times exclude point generation and compilation.
"""

from math.convex_hull import ConvexHull
from std.math import ldexp
from std.sys import argv
from std.time import perf_counter_ns


def _points(kind: Int) -> List[SIMD[DType.float64, 4]]:
    var points = List[SIMD[DType.float64, 4]]()
    if kind < 2:
        var state = UInt64(93849)
        for _ in range(300):
            var p = SIMD[DType.float64, 4](0)
            for axis in range(3):
                state = (state * 1664525 + 1013904223) & UInt64(0xFFFFFFFF)
                p[axis] = Float64(state) / Float64(2147483648) - 1
            points.append(p)
        return points^
    var s = Float64(5e-324)
    if kind == 2:
        return [
            SIMD[DType.float64, 4](0, 0, 0, 0),
            SIMD[DType.float64, 4](2 * s, s, 0, 0),
            SIMD[DType.float64, 4](0, 3 * s, s, 0),
            SIMD[DType.float64, 4](s, 0, 4 * s, 0),
        ]
    var h = ldexp(Float64(1), 1000)
    return [
        SIMD[DType.float64, 4](s, s, s, 0),
        SIMD[DType.float64, 4](h, s, s, 0),
        SIMD[DType.float64, 4](s, h, s, 0),
        SIMD[DType.float64, 4](s, s, h, 0),
    ]


@no_inline
def _construction(
    points: List[SIMD[DType.float64, 4]], count: Int
) raises -> Int:
    var checksum = 0
    for _ in range(count):
        var hull = ConvexHull(points)
        checksum += hull.face_count()
        for face in range(hull.face_count()):
            for corner in range(3):
                checksum += hull.face_vertex(face, corner)
    return checksum


@no_inline
def _queries(hull: ConvexHull, count: Int) -> Int:
    var checksum = 0
    for i in range(count):
        var p = SIMD[DType.float64, 4](
            Float64(i % 31) / 8 - 2,
            Float64(i % 17) / 8 - 1,
            Float64(i % 23) / 8 - 1,
            0,
        )
        checksum += Int(hull.contains_point(p))
    return checksum


def main() raises:
    var args = argv()
    var last = 4
    if len(args) > 1:
        last = Int(args[1])
    print("trial,kind,count,nanoseconds,checksum")
    for trial in range(5):
        for kind in range(last):
            var points = _points(kind)
            var count = 100 if kind != 1 else 10000
            var hull = ConvexHull(points)
            var start = perf_counter_ns()
            var checksum = _queries(
                hull, count
            ) if kind == 1 else _construction(points, count)
            var elapsed = perf_counter_ns() - start
            print(trial, kind, count, elapsed, checksum, sep=",")
