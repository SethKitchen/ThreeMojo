# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Measure persistent Clearwater frames on the CPU (#300).

    mojo run -I . bench/water_bench.mojo [frames]

It builds one `WaterScene` with the page's settings. For each image size
it draws warm-up frames, then times each frame's `advance` and `draw`
separately. It reports the median, the 95th percentile and the slowest
frame, against a 60 frames-per-second budget of 16.7 milliseconds. The
first frame also builds the glare kernels, so it is a warm-up frame. The
numbers describe the machine that runs it.
"""

from extensions.water.frame import WaterScene
from extensions.water.pebbles import pebble_bed
from extensions.water.resolution import SpectrumResolution
from extensions.water.view import FRAME
from render.jpeg import decode
from std.pathlib import Path
from std.sys import argv
from std.time import perf_counter_ns
from units.si import RADIAN, SECOND, Angle, Duration

comptime PEBBLES = "assets/pebbles.jpg"
comptime WARMUP = 2
comptime BUDGET_MS = 1000.0 / 60.0


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


def _report(label: String, var times: List[Int]) -> String:
    var sorted = _sorted(times^)
    return (
        label
        + " p50 "
        + String(_percentile(sorted, 0.5))
        + " ms, p95 "
        + String(_percentile(sorted, 0.95))
        + " ms, max "
        + String(_percentile(sorted, 1.0))
        + " ms"
    )


def main() raises:
    var frames = 10
    var args = argv()
    if len(args) > 1:
        frames = Int(String(args[1]))
    var bed = pebble_bed(decode(Path(PEBBLES).read_bytes()))
    var start = perf_counter_ns()
    var water = WaterScene(
        SpectrumResolution(256),
        64,
        256,
        SpectrumResolution(128),
        Duration(5.0, SECOND),
    )
    print(
        "build: "
        + String(Float64(perf_counter_ns() - start) / 1e6)
        + " ms; budget "
        + String(BUDGET_MS)
        + " ms a frame"
    )
    var dt = Duration(1.0 / 60.0, SECOND)
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
            _ = water.draw(
                width, height, FRAME, True, bed, Angle(-0.22, RADIAN)
            )
        var advances = List[Int]()
        var draws = List[Int]()
        var totals = List[Int]()
        for _ in range(frames):
            var t0 = perf_counter_ns()
            water.advance(dt, False)
            var t1 = perf_counter_ns()
            _ = water.draw(
                width, height, FRAME, True, bed, Angle(-0.22, RADIAN)
            )
            var t2 = perf_counter_ns()
            advances.append(Int(t1 - t0))
            draws.append(Int(t2 - t1))
            totals.append(Int(t2 - t0))
        print(
            String(width)
            + "x"
            + String(height)
            + ", "
            + String(frames)
            + " frames after "
            + String(WARMUP)
            + " warm-up: "
            + _report("advance", advances^)
            + "; "
            + _report("draw", draws^)
            + "; "
            + _report("frame", totals^)
        )
