# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Measure body triangles mixed with thin strands on the CPU (#298).

    mojo run -I . bench/hair_strand_raster_bench.mojo [frames [width height]]

It grows the default groom of a six-foot male, 1500 guides with six
followers each, and puts a head sphere and a larger torso sphere under it.
The strands are one output pixel wide with hashed strand coverage. The
scene does not move, so every frame draws the same image.

For each worker count, 1, 2, 4 and so on up to every logical core, it
renders one warm-up frame and then times `frames` frames of each stage:

- `prepare`: `Renderer.prepare_frame` alone, the host step that builds
  the screen-space triangles, the strand ribbons and caps among them.
- `render`: `Renderer.render`: its own preparation, lighting,
  rasterization and resolve.

The difference of the two medians estimates the lighting, rasterization
and resolve. It is not a measured stage.

Each worker count's warm-up image must have the same CRC-32 as one
worker. The bench stops with an error when that checksum differs. It
does not compare pixels or depths directly, or checksum the timed
frames. It also renders the scene with the hair hidden, as a control.

The CPU stages need no GPU. The numbers describe the machine that runs
the bench.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.humanoid.athleticism import UNTONED
from extensions.humanoid.genome import Genome
from extensions.humanoid.sex import MALE
from extensions.humanoid.skeleton.head.hair.shading import HairLight
from extensions.humanoid.skeleton.head.hair.strands import add_groom
from extensions.humanoid.spec import HumanoidSpec
from geometries.sphere import sphere
from lights.light import ambient_light, directional_light
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.checksum import crc32
from render.framebuffer import Color
from renderers.renderer import Renderer
from std.sys import argv, num_logical_cores
from std.time import perf_counter_ns
from units.si import DEGREE, FOOT, METER, Angle, Length


def _sorted(var times: List[Int]) -> List[Int]:
    for i in range(1, len(times)):
        var j = i
        while j > 0 and times[j - 1] > times[j]:
            times.swap_elements(j - 1, j)
            j -= 1
    return times^


def _median(var times: List[Int]) -> Float64:
    var sorted = _sorted(times^)
    return Float64(sorted[(len(sorted) - 1) // 2]) / 1e6


def _slowest(var times: List[Int]) -> Float64:
    var sorted = _sorted(times^)
    return Float64(sorted[len(sorted) - 1]) / 1e6


def main() raises:
    var frames = 5
    var width = 1920
    var height = 1080
    var args = argv()
    if len(args) > 1:
        frames = Int(String(args[1]))
    if len(args) > 3:
        width = Int(String(args[2]))
        height = Int(String(args[3]))
    var person = HumanoidSpec(Length(6.0, FOOT), MALE, UNTONED, Genome())
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    var hair = add_groom(scene, assets, root, person)
    var low = Vector3(1e9, 1e9, 1e9)
    var high = Vector3(-1e9, -1e9, -1e9)
    for p in hair.groom.points:
        low = Vector3(min(low.x, p.x), min(low.y, p.y), min(low.z, p.z))
        high = Vector3(max(high.x, p.x), max(high.y, p.y), max(high.z, p.z))
    var middle = (low + high) * 0.5
    var skin = assets.materials.add(Material(Color(200, 160, 140)))
    # The body triangles: a head under the hair and a torso below it.
    var head = scene.add(Object3D())
    scene.node(head).set_position(middle.x, middle.y, middle.z)
    scene.add_mesh(
        Mesh(
            assets.geometries.add(sphere(Length(0.09, METER), 48, 32)),
            skin,
            head,
        )
    )
    var torso = scene.add(Object3D())
    scene.node(torso).set_position(middle.x, middle.y - 0.3, middle.z)
    scene.add_mesh(
        Mesh(
            assets.geometries.add(sphere(Length(0.2, METER), 128, 64)),
            skin,
            torso,
        )
    )
    var key = scene.add(Object3D())
    scene.node(key).set_position(middle.x + 1, middle.y + 2, middle.z + 2)
    scene.add_light(directional_light(Color(255, 250, 240), key, 1.0))
    scene.add_light(ambient_light(Color(255, 255, 255), 0.25))
    scene.update()
    var camera = PerspectiveCamera(
        Angle(30.0, DEGREE),
        Float32(width) / Float32(height),
        Length(0.05, METER),
        Length(20.0, METER),
    )
    var eye = middle + Vector3(0.25, 0.05, 0.65)
    camera.place(eye, middle)
    var lights: List[HairLight] = [
        HairLight(Vector3(0.41, 0.82, 0.41), Vector3(3, 3, 3))
    ]
    hair.shade(assets, lights, eye, Vector3(0.1, 0.1, 0.1))

    var strands = len(hair.groom.starts) - 1
    var points = len(hair.groom.points)
    var paint = assets.materials.get(hair.material.value())
    var one = Renderer(width, height, 1)
    var frame = one.prepare_frame(scene, assets, camera)
    print(
        width,
        "x",
        height,
        "; strands",
        strands,
        "points",
        points,
        "segments",
        points - strands,
        "; line width",
        paint.line_width.size,
        "px, opacity",
        paint.opacity,
        "with hashed strand coverage; corners",
        len(frame.corners),
        "; logical cores",
        num_logical_cores(),
        "; timed frames",
        frames,
    )

    var counts = List[Int]()
    var workers = 1
    while workers < num_logical_cores():
        counts.append(workers)
        workers *= 2
    counts.append(num_logical_cores())

    var reference = UInt32(0)
    for index in range(len(counts)):
        var renderer = Renderer(width, height, counts[index])
        var image = renderer.render(scene, assets, camera)
        var sum = crc32(image.pixels)
        if index == 0:
            reference = sum
        elif sum != reference:
            raise Error(
                "workers "
                + String(counts[index])
                + " drew a different image: crc32 "
                + String(sum)
                + " against "
                + String(reference)
            )
        var prepares = List[Int]()
        var renders = List[Int]()
        for _ in range(frames):
            var started = perf_counter_ns()
            var prepared = renderer.prepare_frame(scene, assets, camera)
            var between = perf_counter_ns()
            var drawn = renderer.render(scene, assets, camera)
            var done = perf_counter_ns()
            prepares.append(Int(between - started))
            renders.append(Int(done - between))
            if len(prepared.corners) == 0 or drawn.width != width:
                raise Error("The frame drew nothing")
        var prepare_p50 = _median(prepares.copy())
        var render_p50 = _median(renders.copy())
        print(
            "workers",
            counts[index],
            "crc32",
            sum,
            "prepare p50",
            prepare_p50,
            "max",
            _slowest(prepares^),
            "ms; render p50",
            render_p50,
            "max",
            _slowest(renders^),
            "ms; render less prepare",
            render_p50 - prepare_p50,
            "ms",
            flush=True,
        )

    # The control: the same scene with the hair hidden.
    scene.node(hair.node.value()).visible = False
    scene.update()
    var all = Renderer(width, height, num_logical_cores())
    _ = all.render(scene, assets, camera)
    var started = perf_counter_ns()
    _ = all.render(scene, assets, camera)
    print(
        "hair hidden, every core: render",
        Float64(perf_counter_ns() - started) / 1e6,
        "ms",
    )
