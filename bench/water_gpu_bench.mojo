# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Measure Clearwater's per-pixel shading on a GPU (#300).

    mojo run -I . bench/water_gpu_bench.mojo [frames]

It uses the page's settings, as `water_bench.mojo` does. For each image
size it shades warm-up frames, then times `GpuWater.radiance` for each
frame. The time includes the surface FFT and caustics on the CPU, the
copies to the device, the kernel and the copy back. It reports the
median, the 95th percentile and the slowest frame. It also times the CPU
shading of the largest size once, for comparison. The numbers describe
the machine that runs it.
"""

from extensions.water.frame import WaterScene, _radiance_image, camera_look
from extensions.water.gpu import GpuWater
from extensions.water.pebbles import pebble_bed
from extensions.water.resolution import SpectrumResolution
from render.jpeg import decode
from std.pathlib import Path
from std.sys import argv, has_accelerator
from std.time import perf_counter_ns
from units.si import RADIAN, SECOND, Angle, Duration

comptime PEBBLES = "assets/pebbles.jpg"
comptime WARMUP = 2


def _sorted(var times: List[Int]) -> List[Int]:
    for i in range(1, len(times)):
        var j = i
        while j > 0 and times[j - 1] > times[j]:
            times.swap_elements(j - 1, j)
            j -= 1
    return times^


def _percentile(times: List[Int], fraction: Float64) -> Float64:
    # Nearest rank on a sorted list.
    var rank = Int(fraction * Float64(len(times)) + 0.999999) - 1
    rank = max(0, min(rank, len(times) - 1))
    return Float64(times[rank]) / 1e6


def main() raises:
    if not has_accelerator():
        print("No accelerator: nothing to measure.")
        return
    var frames = 20
    var args = argv()
    if len(args) > 1:
        frames = Int(String(args[1]))
    var bed = pebble_bed(decode(Path(PEBBLES).read_bytes()))
    var water = WaterScene(
        SpectrumResolution(256),
        64,
        256,
        SpectrumResolution(128),
        Duration(5.0, SECOND),
    )
    var start = perf_counter_ns()
    var gpu = GpuWater(bed)
    print(
        "device and photograph upload: "
        + String(Float64(perf_counter_ns() - start) / 1e6)
        + " ms"
    )
    var dt = Duration(1.0 / 60.0, SECOND)
    var pitch = Angle(-0.22, RADIAN)
    var sizes: List[Tuple[Int, Int]] = [
        (320, 180),
        (640, 360),
        (1280, 720),
        (1920, 1080),
    ]
    for size in sizes:
        var width = size[0]
        var height = size[1]
        water.reset()
        for frame in range(WARMUP):
            water.advance(dt, frame == 0)
            _ = gpu.radiance(
                water, camera_look(water.clock, True, pitch), width, height
            )
        var times = List[Int]()
        for _ in range(frames):
            water.advance(dt, False)
            var look = camera_look(water.clock, True, pitch)
            var t0 = perf_counter_ns()
            _ = gpu.radiance(water, look, width, height)
            times.append(Int(perf_counter_ns() - t0))
        var sorted = _sorted(times^)
        print(
            String(width)
            + "x"
            + String(height)
            + ", "
            + String(frames)
            + " frames: GPU radiance p50 "
            + String(_percentile(sorted, 0.5))
            + " ms, p95 "
            + String(_percentile(sorted, 0.95))
            + " ms, max "
            + String(_percentile(sorted, 1.0))
            + " ms"
        )
    var look = camera_look(water.clock, True, pitch)
    var surface = water._surface()
    var caustics = water._caustics(surface)
    var t0 = perf_counter_ns()
    _ = _radiance_image(
        look,
        Float32(1920) / Float32(1080),
        surface,
        water._ripples,
        caustics,
        bed,
        water.clock,
        water.sun,
        1920,
        1080,
        List[Bool](),
    )
    print(
        "1920x1080 CPU radiance on every core: "
        + String(Float64(perf_counter_ns() - t0) / 1e6)
        + " ms"
    )
