# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Measure Clearwater frames with the GPU shader (#300).

    mojo run -I . bench/water_gpu_bench.mojo [frames]

It uses the page's settings, as `water_bench.mojo` does, and the pebble
photograph. Three workloads run after two warm-up frames each:

- Radiance: `GpuWater.radiance` alone, at four image sizes.
- Water frame: a whole 1920 x 1080 `FRAME`, on the GPU and on the CPU.
- Composed scene: a 1920 x 1080 scene of 64 lit spheres over the water,
  rendered on the CPU, then composed with water shaded on the GPU and on
  the CPU.

Each frame is timed by stage, with the same stage boundaries on both
paths. The report gives the median, the 95th percentile and the slowest
frame. The CPU rows run fewer frames, because each takes over a second.
The numbers describe the machine that runs it.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.water.frame import (
    WaterScene,
    _compose_plan,
    _radiance_image,
    camera_look,
)
from extensions.water.gpu import GpuWater
from extensions.water.pebbles import PebbleBed, pebble_bed
from extensions.water.resolution import SpectrumResolution
from extensions.water.view import FRAME
from geometries.sphere import sphere
from lights.light import ambient_light, directional_light
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from render.jpeg import decode
from renderers.renderer import Renderer
from std.pathlib import Path
from std.sys import argv, has_nvidia_gpu_accelerator
from std.time import perf_counter_ns
from units.si import DEGREE, METER, RADIAN, SECOND, Angle, Duration, Length

comptime PEBBLES = "assets/pebbles.jpg"
comptime WARMUP = 2
comptime WIDTH = 1920
comptime HEIGHT = 1080
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
        + " p95 "
        + String(_percentile(sorted, 0.95))
        + " max "
        + String(_percentile(sorted, 1.0))
    )


def _water() raises -> WaterScene:
    return WaterScene(
        SpectrumResolution(256),
        64,
        256,
        SpectrumResolution(128),
        Duration(5.0, SECOND),
    )


struct _Stages(Movable):
    var names: List[String]
    var times: List[List[Int]]

    def __init__(out self, var names: List[String]):
        self.times = List[List[Int]]()
        for _ in range(len(names)):
            self.times.append(List[Int]())
        self.names = names^

    def add(mut self, stage: Int, start: Int, end: Int):
        self.times[stage].append(Int(end - start))

    def print(mut self, label: String):
        var line = label + " (ms):"
        for i in range(len(self.names)):
            line += " " + _report(self.names[i], self.times[i].copy()) + ";"
        print(line)


def _radiance_sizes(mut gpu: GpuWater, frames: Int) raises:
    var water = _water()
    var dt = Duration(1.0 / 60.0, SECOND)
    var pitch = Angle(-0.22, RADIAN)
    var sizes: List[Tuple[Int, Int]] = [
        (320, 180),
        (640, 360),
        (1280, 720),
        (1920, 1080),
    ]
    for size in sizes:
        water.reset()
        for frame in range(WARMUP):
            water.advance(dt, frame == 0)
            _ = gpu.radiance(
                water, camera_look(water.clock, True, pitch), size[0], size[1]
            )
        var stages = _Stages(["radiance"])
        for _ in range(frames):
            water.advance(dt, False)
            var look = camera_look(water.clock, True, pitch)
            var t0 = perf_counter_ns()
            _ = gpu.radiance(water, look, size[0], size[1])
            stages.add(0, t0, perf_counter_ns())
        stages.print("radiance only " + String(size[0]) + "x" + String(size[1]))


def _water_frames(
    mut gpu: GpuWater, bed: PebbleBed, frames: Int, device: Bool
) raises:
    var water = _water()
    var dt = Duration(1.0 / 60.0, SECOND)
    var pitch = Angle(-0.22, RADIAN)
    var stages = _Stages(
        ["advance", "surface+caustics", "shade", "post", "frame"]
    )
    for frame in range(WARMUP + frames):
        var t0 = perf_counter_ns()
        water.advance(dt, frame == 0)
        var t1 = perf_counter_ns()
        var surface = water._surface()
        var caustics = water._caustics(surface)
        var t2 = perf_counter_ns()
        var look = camera_look(water.clock, True, pitch)
        var hdr: List[Float32]
        if device:
            hdr = gpu._shade(water, surface, caustics, look, WIDTH, HEIGHT)
        else:
            hdr = _radiance_image(
                look,
                Float32(WIDTH) / Float32(HEIGHT),
                surface,
                water._ripples,
                caustics,
                bed,
                water.clock,
                water.sun,
                WIDTH,
                HEIGHT,
                List[Bool](),
            )
        var t3 = perf_counter_ns()
        _ = water._finish(hdr, WIDTH, HEIGHT, FRAME)
        var t4 = perf_counter_ns()
        if frame < WARMUP:
            continue
        stages.add(0, t0, t1)
        stages.add(1, t1, t2)
        stages.add(2, t2, t3)
        stages.add(3, t3, t4)
        stages.add(4, t0, t4)
    stages.print("water FRAME 1920x1080 on the " + ("GPU" if device else "CPU"))


def _spheres() raises -> Tuple[Scene, Assets]:
    # 64 lit spheres standing above the water, in rows away from the camera.
    var assets = Assets()
    var world = Scene()
    var ball = assets.geometries.add(sphere(Length(0.3, METER), 24, 16))
    var paint = assets.materials.add(Material(Color(200, 120, 60)))
    for i in range(64):
        var node = world.add(Object3D())
        world.node(node).set_position(
            Float32(i % 8) * 1.2 - 4.2, 0.5, -2.0 - Float32(i // 8) * 1.5
        )
        world.add_mesh(Mesh(ball, paint, node))
    world.add_light(ambient_light(Color(255, 255, 255), 0.3))
    var sun = world.add(Object3D())
    world.node(sun).set_position(3, 10, 5)
    world.add_light(directional_light(Color(255, 245, 230), sun, 1.0))
    world.update()
    return (world^, assets^)


def _composed(
    mut gpu: GpuWater, bed: PebbleBed, frames: Int, device: Bool
) raises:
    var parts = _spheres()
    var camera = PerspectiveCamera(
        Angle(64.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.05, METER),
        Length(500.0, METER),
    )
    camera.place(Vector3(0, 1.55, 2), Vector3(0, 0.6, -6))
    var renderer = Renderer(WIDTH, HEIGHT)
    var water = _water()
    var dt = Duration(1.0 / 60.0, SECOND)
    var stages = _Stages(
        ["advance", "scene render", "depth", "shade", "write", "frame"]
    )
    for frame in range(WARMUP + frames):
        var t0 = perf_counter_ns()
        water.advance(dt, frame == 0)
        var t1 = perf_counter_ns()
        var image = renderer.render(parts[0], parts[1], camera)
        var t2 = perf_counter_ns()
        var plan = _compose_plan(
            image,
            camera.projection_matrix(),
            camera.view_matrix_in(parts[0]),
            Length(0.0, METER),
        )
        var surface = water._surface()
        var caustics = water._caustics(surface)
        var shown = water._compose_depth(image, plan, surface)
        var t3 = perf_counter_ns()
        var hdr: List[Float32]
        if device:
            hdr = gpu._shade(water, surface, caustics, plan.look, WIDTH, HEIGHT)
        else:
            hdr = _radiance_image(
                plan.look,
                plan.aspect,
                surface,
                water._ripples,
                caustics,
                bed,
                water.clock,
                water.sun,
                WIDTH,
                HEIGHT,
                shown,
            )
        var t4 = perf_counter_ns()
        var drawn = water._compose_write(image, hdr, shown)
        var t5 = perf_counter_ns()
        if frame == 0:
            print("composed water pixels:", drawn, "of", WIDTH * HEIGHT)
        if frame < WARMUP:
            continue
        stages.add(0, t0, t1)
        stages.add(1, t1, t2)
        stages.add(2, t2, t3)
        stages.add(3, t3, t4)
        stages.add(4, t4, t5)
        stages.add(5, t0, t5)
    stages.print(
        "composed scene 1920x1080 on the " + ("GPU" if device else "CPU")
    )


def main() raises:
    if not has_nvidia_gpu_accelerator():
        print("No NVIDIA GPU: nothing to measure.")
        return
    var frames = 10
    var args = argv()
    if len(args) > 1:
        frames = Int(String(args[1]))
    var bed = pebble_bed(decode(Path(PEBBLES).read_bytes()))
    var start = perf_counter_ns()
    var gpu = GpuWater(bed)
    print(
        "device and photograph upload: "
        + String(Float64(perf_counter_ns() - start) / 1e6)
        + " ms; budget "
        + String(BUDGET_MS)
        + " ms a frame"
    )
    _radiance_sizes(gpu, frames)
    _water_frames(gpu, bed, frames, True)
    _water_frames(gpu, bed, 3, False)
    _composed(gpu, bed, frames, True)
    _composed(gpu, bed, 3, False)
