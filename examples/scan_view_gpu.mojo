# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A scanned building drawn on a GPU, in meters, with its frame rate
measured.

    mojo run -I . examples/scan_view_gpu.mojo PATH.png SCAN [UP] [FRAMES] [DISTANCE] [WIDTH] [HEIGHT] [PIXELS]

This is `scan_view.mojo` with the draw on the device: the scan goes to the
GPU once, in `GpuSplatScene`, and each frame sends only the splats that the
host's walk of the level-of-detail tree selected. The arguments are those of
`scan_view.mojo`, and the size is 1920 by 1080 by default. It needs MAX and a
GPU: `.venv/bin/uv pip install "max==26.6.0"`.

The report goes to the standard error, one JSON object a line.
"""

from core.object3d import Object3D
from core.scene import Scene
from extensions.scan.frame import scan_axis
from extensions.scan.occupancy import default_occupancy_options, trimmed_region
from extensions.scan.orient import estimate_up
from extensions.scan.place import scan_placement
from math.vector3 import Vector3
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from render.gpu_splat_lod import GpuSplatScene
from render.splat_lod import LOD_PIXELS, build_splat_lod
from std.math import cos, pi, sin
from std.pathlib import Path
from std.sys import argv, num_logical_cores, stderr
from std.time import perf_counter_ns
from tools._example_output import gallery_camera
from tools._scan_demo import open_scan
from units.si import Angle, DEGREE, Length, METER

comptime FRAMES = 36
comptime WIDTH = 1920
comptime HEIGHT = 1080
comptime SHOWN = 4
"""Every this many frames is kept for the animated picture."""
comptime DELAY_MS = 70
comptime BACKGROUND = Color(7, 8, 15)
comptime ELEVATION = 0.35
"""How high the camera stands over the scan's middle, in radii."""
comptime DISTANCE = 1.15
"""How far the camera stands from the scan's middle, in radii."""


def main() raises:
    var words = List[String]()
    for word in argv():
        words.append(String(word))
    if len(words) < 3:
        raise Error(
            "usage: scan_view_gpu.mojo PATH.png SCAN [UP] [FRAMES] [DISTANCE]"
            " [WIDTH] [HEIGHT] [PIXELS]"
        )
    var destination = words[1]
    var frame_count = FRAMES
    if len(words) > 4:
        frame_count = Int(words[4])
    var distance = Float32(DISTANCE)
    if len(words) > 5:
        distance = Float32(atof(words[5]))
    var width = WIDTH
    var height = HEIGHT
    if len(words) > 7:
        width = Int(words[6])
        height = Int(words[7])
    var pixels = LOD_PIXELS
    if len(words) > 8:
        pixels = Float32(atof(words[8]))

    var scan = open_scan(words[2])
    if len(words) > 3 and words[3] == "auto":
        scan.frame.up = estimate_up(scan.splats).axis
    elif len(words) > 3:
        scan.frame.up = scan_axis(words[3])
    var region = trimmed_region(
        scan.splats, scan.frame, default_occupancy_options()
    )
    var middle = Vector3(
        Float32((region.low.x + region.high.x) / 2),
        Float32((region.low.z + region.high.z) / 2),
        Float32(-(region.low.y + region.high.y) / 2),
    )
    var wide = region.high.x - region.low.x
    var deep = region.high.y - region.low.y
    var tall = region.high.z - region.low.z
    var radius = Float32(0.5 * (wide * wide + deep * deep + tall * tall) ** 0.5)

    var scene = Scene()
    var standing = Object3D()
    scan_placement(scan.frame).apply(standing)
    var node = scene.add(standing^)
    scene.update()
    var began = perf_counter_ns()
    var lod = build_splat_lod(scan.splats, node)
    var lod_ms = Float64(perf_counter_ns() - began) / 1e6
    began = perf_counter_ns()
    var device = GpuSplatScene(lod)
    print(
        '{"scan": "',
        scan.title,
        '", "splats": ',
        scan.splats.count(),
        ', "lod_splats": ',
        lod.splat.count(),
        ', "lod_build_ms": ',
        lod_ms,
        ', "gpu_upload_ms": ',
        Float64(perf_counter_ns() - began) / 1e6,
        "}",
        sep="",
        file=stderr,
    )

    var workers = num_logical_cores()
    var frames = List[Framebuffer]()
    var picture = List[UInt8]()
    var select_ms = Float64(0)
    var device_ms = Float64(0)
    var slowest = Float64(0)
    for index in range(frame_count):
        var angle = Float32(2 * pi) * Float32(index) / Float32(frame_count)
        var eye = Vector3(
            middle.x + radius * distance * sin(angle),
            middle.y + radius * Float32(ELEVATION),
            middle.z + radius * distance * cos(angle),
        )
        var camera = gallery_camera(
            width,
            height,
            eye,
            middle,
            field_of_view=Angle(50.0, DEGREE),
            near=Length(radius * Float32(0.01), METER),
            far=Length(radius * Float32(20.0), METER),
        )
        began = perf_counter_ns()
        device.draw_bytes(
            scene,
            lod,
            camera,
            width,
            height,
            BACKGROUND,
            picture,
            workers,
            pixels,
        )
        slowest = max(slowest, Float64(perf_counter_ns() - began) / 1e6)
        select_ms += device.select_ms
        device_ms += device.device_ms
        if index % SHOWN == 0:
            frames.append(Framebuffer(width, height, picture.copy()))
    var frame_ms = (select_ms + device_ms) / Float64(frame_count)
    print(
        '{"frames": ',
        frame_count,
        ', "select_ms": ',
        select_ms / Float64(frame_count),
        ', "device_ms": ',
        device_ms / Float64(frame_count),
        ', "slowest_ms": ',
        slowest,
        ', "fps": ',
        1000 / frame_ms,
        "}",
        sep="",
        file=stderr,
    )
    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", len(frames), "frames")
