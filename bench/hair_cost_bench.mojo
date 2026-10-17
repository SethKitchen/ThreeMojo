# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Measure the CPU cost of each strand-hair stage (#298).

    mojo run -I . bench/hair_cost_bench.mojo [allocation hook]

For four groom sizes it times growth, the first attachment and upload, one
shading pass split into its four stages, and the simulation step and write
with every strand or with the guides only. Each per-frame figure is the
median of several frames. It derives the marginal cost of one follower
strand from the two simulation modes.

With the path of a built `bench/navigation_allocations.c` as its argument,
it also counts the Mojo runtime allocations of one frame of each stage, in
a separate pass after the timings. That hook records the calling thread
only. Work that the stages run on pool threads is not counted.
The numbers describe the machine that runs it.
"""

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.humanoid.athleticism import UNTONED
from extensions.humanoid.genome import Genome
from extensions.humanoid.sex import MALE
from extensions.humanoid.skeleton.complexion import hair_tone
from extensions.humanoid.skeleton.field import DistanceField
from extensions.humanoid.skeleton.head.frame import head_muscle_dimensions
from extensions.humanoid.skeleton.head.hair.collider import HairCollider
from extensions.humanoid.skeleton.head.hair.groom import (
    GroomSpec,
    HairGroom,
    groom_hair,
)
from extensions.humanoid.skeleton.head.hair.shading import (
    HairLight,
    HairLook,
    shade_groom_into,
)
from extensions.humanoid.skeleton.head.hair.simulation import (
    HairSimulation,
    HairWind,
)
from extensions.humanoid.skeleton.head.hair.strands import (
    HairStrands,
    _linear,
    add_strands,
)
from extensions.humanoid.spec import HumanoidSpec
from materials.material import LineWidth
from math.bounds import Box3
from math.vector3 import Vector3, midpoint
from std.ffi import OwnedDLHandle
from std.sys import argv, num_logical_cores
from std.time import perf_counter_ns
from units.si import FOOT, Length

comptime FRAMES = 9


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


def _since(start: Int) -> Int:
    return Int(perf_counter_ns()) - start


def _restore(
    mut hair: HairStrands,
    points: List[Vector3],
    normals: List[Vector3],
    depths: List[Float32],
):
    hair.groom.points = points.copy()
    hair.groom.normals = normals.copy()
    hair.groom.depths = depths.copy()


def _shade_stages(
    mut hair: HairStrands,
    mut assets: Assets,
    lights: List[HairLight],
    eye: Vector3,
    ambient: Vector3,
    mut times: List[List[Int]],
) raises:
    """Run `HairStrands.shade` stage by stage, in its own order."""
    hair._check_geometry(assets)
    var start = perf_counter_ns()
    hair.density.rebuild(hair.groom)
    times[0].append(_since(start))
    start = perf_counter_ns()
    hair._shadow_depths(lights)
    times[1].append(_since(start))
    start = perf_counter_ns()
    shade_groom_into(
        hair.groom,
        hair.look,
        lights,
        eye,
        ambient,
        hair._point_colors,
        hair._optical_depths,
    )
    times[2].append(_since(start))
    start = perf_counter_ns()
    hair._upload(assets)
    times[3].append(_since(start))


def _buffer(hair: HairStrands) raises -> List[Float32]:
    var values = List[Float32](capacity=hair._buffer.length())
    for at in range(hair._buffer.length()):
        values.append(hair._buffer.value(at))
    return values^


def _counted(
    library: OwnedDLHandle, name: String, calls: UInt64, bytes: UInt64
) raises -> String:
    if library.call["navigation_allocations_overflow", UInt64]() != 0:
        raise Error("The allocation hook overflowed")
    return name + " " + String(calls) + " calls/" + String(bytes) + " B"


def _measure(guides: Int, followers: Int, hook: String) raises:
    var person = HumanoidSpec(Length(6.0, FOOT), MALE, UNTONED, Genome())
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    var dims = head_muscle_dimensions(person)
    var start = perf_counter_ns()
    var groom = groom_hair(dims, GroomSpec(dims, guides, followers))
    var grow = Float64(_since(start)) / 1e6
    var tone = hair_tone(person.genome)
    var look = HairLook(
        Vector3(_linear(tone.r), _linear(tone.g), _linear(tone.b))
    )
    start = perf_counter_ns()
    var hair = add_strands(
        scene, assets, root, groom^, look, LineWidth(pixels=1.0)
    )
    var attach = Float64(_since(start)) / 1e6
    var strands = len(hair.groom.starts) - 1
    var points = len(hair.groom.points)
    var guide_strands = 0
    for guide in hair.groom.guides:
        if guide == -1:
            guide_strands += 1
    var follower_strands = strands - guide_strands
    var lights: List[HairLight] = [
        HairLight(Vector3(0.48, 0.64, 0.6), Vector3(3, 3, 3))
    ]
    var eye = Vector3(0, 1.6, 1.0)
    var ambient = Vector3(0.1, 0.1, 0.1)
    var shade_times = List[Int]()
    for _ in range(FRAMES):
        start = perf_counter_ns()
        hair.shade(assets, lights, eye, ambient)
        shade_times.append(_since(start))
    var whole = _buffer(hair)
    var stage_times = List[List[Int]]()
    for _ in range(4):
        stage_times.append(List[Int]())
    for _ in range(FRAMES):
        _shade_stages(hair, assets, lights, eye, ambient, stage_times)
    # The stages must leave the same vertex bytes as one shading pass.
    if _buffer(hair) != whole:
        raise Error("The shading stages differ from HairStrands.shade")
    var box = Box3.from_points(hair.groom.points)
    var low = box.min
    var high = box.max
    var middle = midpoint(low, high)
    var collider = HairCollider(
        _Head(middle, 0.09),
        low - Vector3(0.1, 0.1, 0.1),
        high + Vector3(0.1, 0.1, 0.1),
    )
    var wind = HairWind(Vector3(1, 0, 0), 0.5)
    # Each simulation starts from the same grown pose: a write changes
    # the points, normals and depths, and the next run restores them.
    var points_at_rest = hair.groom.points.copy()
    var normals_at_rest = hair.groom.normals.copy()
    var depths_at_rest = hair.groom.depths.copy()
    var guided = HairSimulation(hair.groom, guides_only=True)
    var guided_step = List[Int]()
    var guided_write = List[Int]()
    for _ in range(FRAMES):
        start = perf_counter_ns()
        guided.step(collider, wind)
        guided_step.append(_since(start))
        start = perf_counter_ns()
        guided.write(hair.groom)
        guided_write.append(_since(start))
    _restore(hair, points_at_rest, normals_at_rest, depths_at_rest)
    var framed = HairSimulation(hair.groom, guides_only=True)
    var frame_times = List[Int]()
    for _ in range(FRAMES):
        start = perf_counter_ns()
        framed.step(collider, wind)
        framed.write(hair.groom)
        hair.shade(assets, lights, eye, ambient)
        frame_times.append(_since(start))
    _restore(hair, points_at_rest, normals_at_rest, depths_at_rest)
    var motion = HairSimulation(hair.groom)
    var full_step = List[Int]()
    var full_write = List[Int]()
    for _ in range(FRAMES):
        start = perf_counter_ns()
        motion.step(collider, wind)
        full_step.append(_since(start))
        start = perf_counter_ns()
        motion.write(hair.groom)
        full_write.append(_since(start))
    var step_ms = _median(full_step^)
    var write_ms = _median(full_write^)
    var guided_step_ms = _median(guided_step^)
    var guided_write_ms = _median(guided_write^)
    # The marginal cost of a follower is the full step's extra time over
    # the guides-only step, shared over the followers.
    var follower_us = Float64(0)
    var guide_us = guided_step_ms * 1000 / Float64(guide_strands)
    if follower_strands > 0:
        follower_us = (
            (step_ms - guided_step_ms) * 1000 / Float64(follower_strands)
        )
    print(
        String(guides)
        + " guides x "
        + String(followers)
        + " followers on "
        + String(num_logical_cores())
        + " logical cores: "
        + String(strands)
        + " strands ("
        + String(guide_strands)
        + " guides), "
        + String(points)
        + " points, "
        + String(hair._buffer.count() * hair._buffer.stride() * 4)
        + " vertex bytes"
    )
    print(
        "  grow "
        + String(grow)
        + " ms, attach and first upload "
        + String(attach)
        + " ms"
    )
    print(
        "  shade "
        + String(_median(shade_times^))
        + " ms = density "
        + String(_median(stage_times[0].copy()))
        + " + optical depth "
        + String(_median(stage_times[1].copy()))
        + " + color "
        + String(_median(stage_times[2].copy()))
        + " + vertex upload "
        + String(_median(stage_times[3].copy()))
        + " ms"
    )
    print(
        "  full step "
        + String(step_ms)
        + " + write "
        + String(write_ms)
        + " ms; guides-only step "
        + String(guided_step_ms)
        + " + write "
        + String(guided_write_ms)
        + " ms; guides-only frame "
        + String(_median(frame_times^))
        + " ms"
    )
    print(
        "  per guide strand "
        + String(guide_us)
        + " us (guides-only step); per follower strand "
        + String(follower_us)
        + " us simulated, laid in the guides-only step"
    )
    if not hook:
        return
    var library = OwnedDLHandle(hook)
    if library.call["navigation_allocations_selftest", UInt64]() != 1:
        raise Error("The allocation hook failed its self-test")
    var line = String("  calling-thread allocations, one frame: ")
    _ = library.call["navigation_allocations_begin", UInt64]()
    hair.density.rebuild(hair.groom)
    _ = library.call["navigation_allocations_end", UInt64]()
    line += _counted(
        library,
        "density",
        library.call["navigation_allocations_calls", UInt64](),
        library.call["navigation_allocations_total", UInt64](),
    )
    _ = library.call["navigation_allocations_begin", UInt64]()
    hair._shadow_depths(lights)
    _ = library.call["navigation_allocations_end", UInt64]()
    line += _counted(
        library,
        ", optical depth",
        library.call["navigation_allocations_calls", UInt64](),
        library.call["navigation_allocations_total", UInt64](),
    )
    _ = library.call["navigation_allocations_begin", UInt64]()
    shade_groom_into(
        hair.groom,
        hair.look,
        lights,
        eye,
        ambient,
        hair._point_colors,
        hair._optical_depths,
    )
    _ = library.call["navigation_allocations_end", UInt64]()
    line += _counted(
        library,
        ", color",
        library.call["navigation_allocations_calls", UInt64](),
        library.call["navigation_allocations_total", UInt64](),
    )
    _ = library.call["navigation_allocations_begin", UInt64]()
    hair._upload(assets)
    _ = library.call["navigation_allocations_end", UInt64]()
    line += _counted(
        library,
        ", vertex upload",
        library.call["navigation_allocations_calls", UInt64](),
        library.call["navigation_allocations_total", UInt64](),
    )
    _ = library.call["navigation_allocations_begin", UInt64]()
    motion.step(collider, wind)
    _ = library.call["navigation_allocations_end", UInt64]()
    line += _counted(
        library,
        ", full step",
        library.call["navigation_allocations_calls", UInt64](),
        library.call["navigation_allocations_total", UInt64](),
    )
    _ = library.call["navigation_allocations_begin", UInt64]()
    motion.write(hair.groom)
    _ = library.call["navigation_allocations_end", UInt64]()
    line += _counted(
        library,
        ", full write",
        library.call["navigation_allocations_calls", UInt64](),
        library.call["navigation_allocations_total", UInt64](),
    )
    _ = library.call["navigation_allocations_begin", UInt64]()
    guided.step(collider, wind)
    _ = library.call["navigation_allocations_end", UInt64]()
    line += _counted(
        library,
        ", guides-only step",
        library.call["navigation_allocations_calls", UInt64](),
        library.call["navigation_allocations_total", UInt64](),
    )
    _ = library.call["navigation_allocations_begin", UInt64]()
    var built = HairSimulation(hair.groom, guides_only=True)
    var retained = library.call["navigation_allocations_end", UInt64]()
    line += _counted(
        library,
        ", guides-only simulation construction",
        library.call["navigation_allocations_calls", UInt64](),
        library.call["navigation_allocations_total", UInt64](),
    )
    line += " (peak " + String(retained) + " B)"
    _ = built.frame
    print(line)


def main() raises:
    var args = argv()
    var hook = String(args[1]) if len(args) > 1 else String("")
    for size in [(250, 2), (1000, 4), (1500, 6), (1500, 0)]:
        _measure(size[0], size[1], hook)
