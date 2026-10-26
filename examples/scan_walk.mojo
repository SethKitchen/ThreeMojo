# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A person walks through a scanned building: the game loop of a scan.

    mojo run -I . examples/scan_walk.mojo [path.png] [SCAN] [FRAMES] [WIDTH] [HEIGHT]

SCAN is the id of a cached scan in `assets/building_scans/manifest.json`,
`studio-11` by default, or the path of a scan file. Fetch a scan first:

    sh tools/tool.sh .venv/bin/mojo building_scans fetch studio-11 --pin

Each frame does what a game does:

1. The physics world steps by one sixtieth of a second. It holds the scan
   as a static collider and a capsule 1.8 m tall for the walker, which cannot
   turn over (`extensions.scan.walk`). The floor, the walls and the
   furniture of the scan decide where the walker goes.
2. The camera stands at the walker's eye and looks along its way.
3. The splats are drawn with levels of detail on every core.

The example reports the time of each part of a frame, and the frames a
second of the loop as a whole, to the standard error, one JSON object a
line. `scan_walk_gpu.mojo` draws the same walk on a GPU.
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
from render.splat_lod import build_splat_lod, prepare_splat_lod
from render.splat_raster import rasterize_splats
from render.working_space import resolve_srgb_working, srgb_working_target
from std.pathlib import Path
from std.sys import argv, num_logical_cores, stderr
from std.time import perf_counter_ns
from tools._example_output import gallery_camera
from tools._scan_demo import fill_grid, open_scan
from units.si import Angle, DEGREE, Duration, Length, METER, SECOND

comptime DEFAULT_OUTPUT = "out/scan-walk.png"
comptime DEFAULT_SCAN = "studio-11"
comptime WIDTH = 480
comptime HEIGHT = 270
comptime FRAMES = 240
comptime SHOWN = 4
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

    # 1. The scan, cleaned, its grid and its floor.
    var began = perf_counter_ns()
    var scan = open_scan(wanted)
    print(
        '{"scan": "',
        scan.title,
        '", "by": "',
        scan.author,
        '", "splats": ',
        scan.splats.count(),
        ', "outside": ',
        scan.report.outside,
        ', "faint": ',
        scan.report.faint,
        ', "huge": ',
        scan.report.huge,
        ', "load_ms": ',
        Float64(perf_counter_ns() - began) / 1e6,
        "}",
        sep="",
        file=stderr,
    )
    began = perf_counter_ns()
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
        '{"floor_m": ',
        filled.floor.to(METER),
        ', "voxel_m": ',
        filled.grid.voxel.to(METER),
        ', "from": [',
        walker.ends[0].x,
        ", ",
        walker.ends[0].y,
        '], "to": [',
        walker.ends[1].x,
        ", ",
        walker.ends[1].y,
        '], "setup_ms": ',
        Float64(perf_counter_ns() - began) / 1e6,
        "}",
        sep="",
        file=stderr,
    )

    # 2. The scan's splats, in the scene in meters.
    var scene = Scene()
    var standing = Object3D()
    scan_placement(scan.frame).apply(standing)
    var node = scene.add(standing^)
    scene.update()
    began = perf_counter_ns()
    var lod = build_splat_lod(scan.splats, node)
    print(
        '{"lod_build_ms": ',
        Float64(perf_counter_ns() - began) / 1e6,
        ', "lod_splats": ',
        lod.splat.count(),
        "}",
        sep="",
        file=stderr,
    )

    # 3. The loop.
    var workers = num_logical_cores()
    var shown = List[Framebuffer]()
    var physics_ms = Float64(0)
    var draw_ms = Float64(0)
    var slowest = Float64(0)
    var drawn = 0
    var walked = Float64(0)
    for index in range(frame_count):
        var before = walker.position()
        var spent = perf_counter_ns()
        walker.step(Duration(Float32(1.0 / RATE), SECOND))
        physics_ms += Float64(perf_counter_ns() - spent) / 1e6
        var after = walker.position()
        walked += ((after.x - before.x) ** 2 + (after.y - before.y) ** 2) ** 0.5

        # The eye, in the scene: building x, y and z up are x, -z and y.
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
        var target = srgb_working_target(width, height, BACKGROUND)
        spent = perf_counter_ns()
        var selected = prepare_splat_lod(
            scene,
            lod,
            camera,
            width,
            height,
            target.depth_mode,
            None,
            workers,
        )
        drawn += len(selected)
        rasterize_splats(target, selected, workers)
        var took = Float64(perf_counter_ns() - spent) / 1e6
        draw_ms += took
        slowest = max(slowest, took)
        if index % SHOWN == 0:
            shown.append(resolve_srgb_working(target))
    var loop_ms = (physics_ms + draw_ms) / Float64(frame_count)
    print(
        '{"frames": ',
        frame_count,
        ', "walked_m": ',
        walked,
        ', "physics_ms": ',
        physics_ms / Float64(frame_count),
        ', "draw_ms": ',
        draw_ms / Float64(frame_count),
        ', "slowest_draw_ms": ',
        slowest,
        ', "loop_fps": ',
        1000 / loop_ms,
        ', "splats_drawn": ',
        drawn // frame_count,
        "}",
        sep="",
        file=stderr,
    )
    Path(destination).write_bytes(encode(shown, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", len(shown), "frames")
