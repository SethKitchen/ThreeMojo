# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Measure the CPU cost of each strand-hair stage (#298).

    mojo run -I . bench/hair_cost_bench.mojo

For three groom sizes it times growing and uploading the groom, one shading
pass, one simulation step with its write-back, and the shading pass that
follows a step. Each per-frame figure is the median of several frames. It
also reports the strand, point and vertex-buffer sizes, which bound the
memory that one groom holds. The numbers describe the machine that runs it.
"""

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.humanoid.athleticism import UNTONED
from extensions.humanoid.genome import Genome
from extensions.humanoid.sex import MALE
from extensions.humanoid.skeleton.field import DistanceField
from extensions.humanoid.skeleton.head.hair.collider import HairCollider
from extensions.humanoid.skeleton.head.hair.shading import HairLight
from extensions.humanoid.skeleton.head.hair.simulation import (
    HairSimulation,
    HairWind,
)
from extensions.humanoid.skeleton.head.hair.strands import add_groom
from extensions.humanoid.spec import HumanoidSpec
from math.vector3 import Vector3
from std.time import perf_counter_ns
from units.si import FOOT, Length

comptime FRAMES = 5


@fieldwise_init
struct _Head(DistanceField, ImplicitlyCopyable):
    """A sphere standing in for the scalp, in the pelvis frame."""

    var center: Vector3
    var radius: Float32

    def distance(self, point: Vector3) -> Float32:
        return (point - self.center).length() - self.radius


def _median(var times: List[Int]) -> Float64:
    for i in range(1, len(times)):
        var j = i
        while j > 0 and times[j - 1] > times[j]:
            times.swap_elements(j - 1, j)
            j -= 1
    return Float64(times[len(times) // 2]) / 1e6


def _measure(guides: Int, followers: Int) raises:
    var person = HumanoidSpec(Length(6.0, FOOT), MALE, UNTONED, Genome())
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    var start = perf_counter_ns()
    var hair = add_groom(scene, assets, root, person, guides, followers)
    var grow = Float64(perf_counter_ns() - start) / 1e6
    var strands = len(hair.groom.starts) - 1
    var points = len(hair.groom.points)
    var lights: List[HairLight] = [
        HairLight(Vector3(0.48, 0.64, 0.6), Vector3(3, 3, 3))
    ]
    var eye = Vector3(0, 1.6, 1.0)
    var ambient = Vector3(0.1, 0.1, 0.1)
    var shade_times = List[Int]()
    for _ in range(FRAMES):
        start = perf_counter_ns()
        hair.shade(assets, lights, eye, ambient)
        shade_times.append(Int(perf_counter_ns() - start))
    var low = Vector3(1e9, 1e9, 1e9)
    var high = Vector3(-1e9, -1e9, -1e9)
    for p in hair.groom.points:
        low = Vector3(min(low.x, p.x), min(low.y, p.y), min(low.z, p.z))
        high = Vector3(max(high.x, p.x), max(high.y, p.y), max(high.z, p.z))
    var middle = (low + high) * 0.5
    var collider = HairCollider(
        _Head(middle, 0.09),
        low - Vector3(0.1, 0.1, 0.1),
        high + Vector3(0.1, 0.1, 0.1),
    )
    var guided = HairSimulation(hair.groom, guides_only=True)
    var guided_times = List[Int]()
    for _ in range(FRAMES):
        start = perf_counter_ns()
        guided.step(collider, HairWind(Vector3(1, 0, 0), 0.5))
        guided.write(hair.groom)
        guided_times.append(Int(perf_counter_ns() - start))
    var frame_times = List[Int]()
    for _ in range(FRAMES):
        start = perf_counter_ns()
        guided.step(collider, HairWind(Vector3(1, 0, 0), 0.5))
        guided.write(hair.groom)
        hair.shade(assets, lights, eye, ambient)
        frame_times.append(Int(perf_counter_ns() - start))
    var motion = HairSimulation(hair.groom)
    var step_times = List[Int]()
    var dynamic_shade_times = List[Int]()
    for _ in range(FRAMES):
        start = perf_counter_ns()
        motion.step(collider, HairWind(Vector3(1, 0, 0), 0.5))
        motion.write(hair.groom)
        step_times.append(Int(perf_counter_ns() - start))
        start = perf_counter_ns()
        hair.shade(assets, lights, eye, ambient)
        dynamic_shade_times.append(Int(perf_counter_ns() - start))
    print(
        String(guides)
        + " guides x "
        + String(followers)
        + " followers: "
        + String(strands)
        + " strands, "
        + String(points)
        + " points, "
        + String(hair._buffer.count() * hair._buffer.stride() * 4)
        + " vertex bytes; grow+upload "
        + String(grow)
        + " ms, shade "
        + String(_median(shade_times^))
        + " ms, step+write "
        + String(_median(step_times^))
        + " ms, shade after step "
        + String(_median(dynamic_shade_times^))
        + " ms, guides-only step+write "
        + String(_median(guided_times^))
        + " ms, guides-only frame "
        + String(_median(frame_times^))
        + " ms"
    )


def main() raises:
    for size in [(250, 2), (1000, 4), (1500, 6), (1500, 0)]:
        _measure(size[0], size[1])
