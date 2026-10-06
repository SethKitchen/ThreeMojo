# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Complete synthetic ray-query workloads reconstructed from issue 550."""

from math.bounds import Box3, Sphere
from math.ray import Ray
from math.vector3 import Vector3
from std.sys import argv
from std.time import perf_counter_ns


@no_inline
def run[mode: Int](rays: List[Ray], repeats: Int) raises -> Float64:
    """Execute every requested query and consume each returned coordinate.

    Args:
        rays: The stored input rays.
        repeats: Number of complete passes through the rays.

    Returns:
        The deterministic result checksum.

    Raises:
        Error: If a hit value cannot be read.
    """
    var sphere = Sphere(Vector3(0, 0, 0), 1.5)
    var box = Box3(Vector3(-1, -1, -1), Vector3(1, 1, 1))
    var sum = Float64(0)
    for _ in range(repeats):
        for ray in rays:
            if mode == 0:
                var hit = ray.intersect_sphere(sphere)
                if hit:
                    var p = hit.value()
                    sum += Float64(p.x) + Float64(p.y) * 3 + Float64(p.z) * 7
            elif mode == 1:
                sum += Float64(Int(ray.intersects_sphere(sphere)))
            elif mode == 2:
                var hit = ray.intersect_box(box)
                if hit:
                    var p = hit.value()
                    sum += Float64(p.x) + Float64(p.y) * 3 + Float64(p.z) * 7
            else:
                sum += Float64(Int(ray.intersects_box(box)))
    return sum


def row[mode: Int](name: String, rays: List[Ray], repeats: Int) raises:
    """Print one complete workload measurement.

    Args:
        name: The workload label.
        rays: The stored input rays.
        repeats: Number of complete passes.

    Raises:
        Error: If query execution fails.
    """
    var start = perf_counter_ns()
    var sum = run[mode](rays, repeats)
    var elapsed = perf_counter_ns() - start
    print(name, repeats * len(rays), elapsed, sum, sep=",")


def main() raises:
    """Build the fixed input set and time all four query workloads.

    Raises:
        Error: If an argument or query is invalid.
    """
    var args = argv()
    var repeats = 4000
    if len(args) > 1:
        repeats = Int(args[1])
    var rays = List[Ray]()
    for i in range(256):
        rays.append(
            Ray(
                Vector3(
                    -5, Float32(i % 32) * 0.15 - 2, Float32(i // 32) * 0.2 - 0.5
                ),
                Vector3(1, 0.01, 0.02),
            )
        )
    row[0]("sphere_point", rays, repeats)
    row[1]("sphere_bool", rays, repeats)
    row[2]("box_point", rays, repeats)
    row[3]("box_bool", rays, repeats)
