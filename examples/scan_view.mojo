# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A scanned building drawn with levels of detail, in meters, with its frame
rate measured.

    mojo run -I . examples/scan_view.mojo PATH.png SCAN [UP] [FRAMES] [DISTANCE] [WIDTH] [HEIGHT] [PIXELS]

SCAN is the id of a cached scan in `assets/building_scans/manifest.json`,
or the path of a scan file of any format that `extensions.scan.files`
reads, such as a `.splat` file. UP is a scan axis,
such as `+y`, that overrides the frame's up, or `auto` to find it from the
splats (`extensions.scan.orient`). FRAMES is how many pictures turn round the
scan, 36 by default. DISTANCE is how far the camera stands from the scan's
middle, in radii of its box: 1.15 by default. PIXELS is the level-of-detail
limit of `render.splat_lod`. Fetch a scan first:

    sh tools/tool.sh .venv/bin/mojo building_scans fetch seem-church --pin

The steps:

1. Read the splats, leave out those that are not the building
   (`extensions.scan.clean`), and place them in a scene in meters with the
   scan's frame (`extensions.scan.place`).
2. Find the box that holds all but the faintest floaters of the scan
   (`trimmed_region`), and turn a camera round it.
3. Build the level-of-detail tree once, and then draw each frame on every
   core.

The report goes to the standard error, one JSON object a line: the read and
the tree build in milliseconds, then the frame time and the frames a second.
`scan_view_gpu.mojo` draws the same views on a GPU.
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
from render.splat_lod import LOD_PIXELS, build_splat_lod, prepare_splat_lod
from render.splat_raster import rasterize_splats
from render.working_space import resolve_srgb_working, srgb_working_target
from std.math import cos, pi, sin
from std.pathlib import Path
from std.sys import argv, num_logical_cores, stderr
from std.time import perf_counter_ns
from tools._example_output import gallery_camera
from tools._scan_demo import open_scan
from units.si import Angle, DEGREE, Length, METER

comptime FRAMES = 36
comptime WIDTH = 640
comptime HEIGHT = 360
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
            "usage: scan_view.mojo PATH.png SCAN [UP] [FRAMES] [DISTANCE]"
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

    var began = perf_counter_ns()
    var scan = open_scan(words[2])
    if len(words) > 3 and words[3] == "auto":
        var up = estimate_up(scan.splats)
        scan.frame.up = up.axis
        print(
            '{"up": "',
            up.axis.name(),
            '", "share": ',
            up.share,
            ', "side": ',
            up.side,
            "}",
            sep="",
            file=stderr,
        )
    elif len(words) > 3:
        scan.frame.up = scan_axis(words[3])
    print(
        '{"scan": "',
        scan.title,
        '", "splats": ',
        scan.splats.count(),
        ', "outside": ',
        scan.report.outside,
        ', "faint": ',
        scan.report.faint,
        ', "huge": ',
        scan.report.huge,
        ', "read_ms": ',
        Float64(perf_counter_ns() - began) / 1e6,
        "}",
        sep="",
        file=stderr,
    )

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
    print(
        '{"box_m": [',
        wide,
        ", ",
        deep,
        ", ",
        tall,
        '], "radius_m": ',
        radius,
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
    print(
        '{"lod_build_ms": ',
        Float64(perf_counter_ns() - began) / 1e6,
        ', "lod_splats": ',
        lod.splat.count(),
        "}",
        sep="",
        file=stderr,
    )

    var workers = num_logical_cores()
    var frames = List[Framebuffer]()
    var spent = Float64(0)
    var slowest = Float64(0)
    var prepare_ms = Float64(0)
    var drawn = 0
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
        var target = srgb_working_target(width, height, BACKGROUND)
        began = perf_counter_ns()
        var selected = prepare_splat_lod(
            scene,
            lod,
            camera,
            width,
            height,
            target.depth_mode,
            None,
            workers,
            pixels,
        )
        drawn += len(selected)
        prepare_ms += Float64(perf_counter_ns() - began) / 1e6
        rasterize_splats(target, selected, workers)
        var took = Float64(perf_counter_ns() - began) / 1e6
        spent += took
        slowest = max(slowest, took)
        frames.append(resolve_srgb_working(target))
    print(
        '{"workers": ',
        workers,
        ', "frame_ms": ',
        spent / Float64(frame_count),
        ', "prepare_ms": ',
        prepare_ms / Float64(frame_count),
        ', "slowest_ms": ',
        slowest,
        ', "fps": ',
        1000 * Float64(frame_count) / spent,
        ', "splats_drawn": ',
        drawn // frame_count,
        "}",
        sep="",
        file=stderr,
    )
    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", frame_count, "frames")
