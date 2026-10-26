# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A person walks through a scanned building, drawn on a GPU.

    mojo run -I . examples/scan_walk_gpu.mojo [path.png] [SCAN] [FRAMES] [WIDTH] [HEIGHT]

This is `scan_walk.mojo` with the draw on the device. The scan goes to the
GPU once, in `GpuSplatScene`. Each frame the host steps the physics world,
walks the level-of-detail tree to select the splats, and sends their places.
The device projects, sorts and fills them, and the picture comes back. It
needs MAX and a GPU: `.venv/bin/uv pip install "max==26.6.0"`.

The report goes to the standard error, one JSON object a line.
"""

from core.object3d import Object3D
from core.scene import Scene
from extensions.physics.shape import PhysicsMaterial
from extensions.scan.place import scan_placement
from extensions.scan.walk import Walker, default_walk_options
from generators.utils import Vec3d
from math.vector3 import Vector3
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from render.gpu_splat_lod import GpuSplatScene
from render.splat_lod import build_splat_lod
from std.pathlib import Path
from std.sys import argv, num_logical_cores, stderr
from std.time import perf_counter_ns
from tools._example_output import gallery_camera
from tools._scan_demo import fill_grid, open_scan
from units.si import Angle, DEGREE, Duration, Length, METER, SECOND

comptime DEFAULT_OUTPUT = "out/scan-walk-gpu.png"
comptime DEFAULT_SCAN = "studio-11"
comptime WIDTH = 1280
comptime HEIGHT = 720
comptime FRAMES = 240
comptime SHOWN = 20
"""Every this many frames is kept for the animated picture."""
comptime DELAY_MS = 66
comptime BACKGROUND = Color(7, 8, 15)
comptime RATE = 60.0


def main() raises:
    var words = List[String]()
    for word in argv():
        words.append(String(word))
    var destination = String(DEFAULT_OUTPUT)
    if len(words) > 1:
        destination = words[1]
    var wanted = String(DEFAULT_SCAN)
    if len(words) > 2:
        wanted = words[2]
    var frame_count = FRAMES
    if len(words) > 3:
        frame_count = Int(words[3])
    var width = WIDTH
    var height = HEIGHT
    if len(words) > 5:
        width = Int(words[4])
        height = Int(words[5])

    var began = perf_counter_ns()
    var scan = open_scan(wanted)
    var filled = fill_grid(scan)
    var walker = Walker(
        filled.grid,
        filled.floor,
        Vec3d(filled.region.low.x, filled.region.low.y, 0),
        Vec3d(filled.region.high.x, filled.region.high.y, 0),
        default_walk_options(),
        PhysicsMaterial.default(),
    )
    print(
        '{"scan": "',
        scan.title,
        '", "by": "',
        scan.author,
        '", "splats": ',
        scan.splats.count(),
        ', "setup_ms": ',
        Float64(perf_counter_ns() - began) / 1e6,
        "}",
        sep="",
        file=stderr,
    )

    var scene = Scene()
    var standing = Object3D()
    scan_placement(scan.frame).apply(standing)
    var node = scene.add(standing^)
    scene.update()
    began = perf_counter_ns()
    var lod = build_splat_lod(scan.splats, node)
    var lod_ms = Float64(perf_counter_ns() - began) / 1e6
    began = perf_counter_ns()
    var device = GpuSplatScene(lod)
    print(
        '{"lod_build_ms": ',
        lod_ms,
        ', "lod_splats": ',
        lod.splat.count(),
        ', "gpu_upload_ms": ',
        Float64(perf_counter_ns() - began) / 1e6,
        "}",
        sep="",
        file=stderr,
    )

    var workers = num_logical_cores()
    var shown = List[Framebuffer]()
    var picture = List[UInt8]()
    var physics_ms = Float64(0)
    var select_ms = Float64(0)
    var device_ms = Float64(0)
    var slowest = Float64(0)
    var walked = Float64(0)
    for index in range(frame_count):
        var before = walker.position()
        var spent = perf_counter_ns()
        walker.step(Duration(Float32(1.0 / RATE), SECOND))
        physics_ms += Float64(perf_counter_ns() - spent) / 1e6
        var after = walker.position()
        walked += ((after.x - before.x) ** 2 + (after.y - before.y) ** 2) ** 0.5
        var eye = walker.eye()
        var ahead = walker.forward()
        var camera = gallery_camera(
            width,
            height,
            Vector3(Float32(eye.x), Float32(eye.z), Float32(-eye.y)),
            Vector3(
                Float32(eye.x + ahead.x),
                Float32(eye.z - 0.05),
                Float32(-(eye.y + ahead.y)),
            ),
            field_of_view=Angle(75.0, DEGREE),
            near=Length(0.05, METER),
            far=Length(200.0, METER),
        )
        spent = perf_counter_ns()
        device.draw_bytes(
            scene, lod, camera, width, height, BACKGROUND, picture, workers
        )
        var took = Float64(perf_counter_ns() - spent) / 1e6
        select_ms += device.select_ms
        device_ms += device.device_ms
        slowest = max(slowest, took)
        if index % SHOWN == 0:
            shown.append(Framebuffer(width, height, picture.copy()))
    var loop_ms = (physics_ms + select_ms + device_ms) / Float64(frame_count)
    print(
        '{"frames": ',
        frame_count,
        ', "walked_m": ',
        walked,
        ', "physics_ms": ',
        physics_ms / Float64(frame_count),
        ', "select_ms": ',
        select_ms / Float64(frame_count),
        ', "device_ms": ',
        device_ms / Float64(frame_count),
        ', "slowest_draw_ms": ',
        slowest,
        ', "loop_fps": ',
        1000 / loop_ms,
        "}",
        sep="",
        file=stderr,
    )
    Path(destination).write_bytes(encode(shown, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", len(shown), "frames")
