# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CPU against GPU rasterization, across image sizes.

    mojo run -I . bench/raster_bench.mojo

Both paths are timed doing the same whole job — produce a finished framebuffer
of the given size — because that is what a caller actually needs. For the CPU
that is clearing the buffer and walking every pixel; for the GPU it is
allocating device memory, launching the kernel and copying the result back.
Timing the kernel alone would flatter the GPU by hiding the transfer that
makes its output usable.

The first GPU launch pays for kernel compilation, so a warm-up run is
discarded before measuring.
"""

from math.vector2 import Vector2
from render.framebuffer import Color, Framebuffer
from render.gpu import available, render
from render.rasterizer import Triangle, rasterize
from std.time import perf_counter_ns

comptime REPEATS = 5
comptime BACKGROUND = Color(20, 24, 32)
comptime FOREGROUND = Color(255, 128, 32)


def triangle_for(width: Int, height: Int) -> Triangle:
    """Return a triangle scaled to cover a consistent share of the image."""
    var w = Float32(width)
    var h = Float32(height)
    return Triangle(
        Vector2(w * 0.15, h * 0.75),
        Vector2(w * 0.50, h * 0.15),
        Vector2(w * 0.85, h * 0.80),
    )


def time_cpu(width: Int, height: Int) raises -> Int:
    """Return the best of several CPU renders, in microseconds."""
    var triangle = triangle_for(width, height)
    var best = -1
    for _ in range(REPEATS):
        var started = perf_counter_ns()
        var target = Framebuffer(width, height, BACKGROUND)
        rasterize(triangle, target, FOREGROUND)
        var elapsed = Int(perf_counter_ns() - started) // 1000
        # Keep the buffer alive past the timer so it cannot be optimized away.
        if target.width == 0:
            raise Error("unreachable")
        if best < 0 or elapsed < best:
            best = elapsed
    return best


def time_gpu(width: Int, height: Int) raises -> Int:
    """Return the best of several GPU renders, in microseconds."""
    var triangle = triangle_for(width, height)
    # Discard a warm-up: the first launch compiles the kernel.
    var warmup = render(triangle, width, height, BACKGROUND, FOREGROUND)
    if warmup.width == 0:
        raise Error("unreachable")

    var best = -1
    for _ in range(REPEATS):
        var started = perf_counter_ns()
        var target = render(triangle, width, height, BACKGROUND, FOREGROUND)
        var elapsed = Int(perf_counter_ns() - started) // 1000
        if target.width == 0:
            raise Error("unreachable")
        if best < 0 or elapsed < best:
            best = elapsed
    return best


def report(width: Int, height: Int) raises:
    """Time both paths at one size and print the comparison."""
    var cpu = time_cpu(width, height)
    var label = String(width) + "x" + String(height)
    var pixels = width * height

    if not available():
        print(label, "CPU", cpu, "us   GPU: no accelerator")
        return

    var gpu = time_gpu(width, height)
    var verdict = String("CPU wins")
    if gpu < cpu:
        verdict = "GPU wins by " + String(cpu // gpu) + "x"
    elif cpu < gpu:
        verdict = "CPU wins by " + String(gpu // cpu) + "x"
    print(
        label,
        "(" + String(pixels // 1000) + "k px)",
        " CPU",
        cpu,
        "us   GPU",
        gpu,
        "us   ",
        verdict,
    )


def main() raises:
    print("Rasterizing one triangle into a full framebuffer.")
    print("Best of", REPEATS, "runs, microseconds, lower is better.")
    print("GPU timing includes device allocation and the copy back.")
    print()
    report(320, 240)
    report(640, 480)
    report(1280, 720)
    report(1920, 1080)
    report(3840, 2160)
