# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wijnendale Castle, scanned by virtual cameras into splats.

    mojo run -I . examples/wijnendale_scan.mojo [path.splat] [VIEWS] [SIZE]

The castle's renderer draws the plan, the brick, the slate, the water and the
woods with shadows and physically based light, in about half a minute a
picture. `extensions.scan.virtual` makes splats from such pictures with
their depth. So this example takes the pictures a scanner would take of the
castle from a ring of places, from low and from high, under the sun of 15:00
on 19 October 2026, and keeps one splat for each 15 cm cell of what it sees.

The scan is a `.splat` file in the scene's axes, in meters, with y up and
z south. It draws in milliseconds, it can be walked through, cut into parts
and fitted as a building, as any scan can:

    mojo run -I . examples/scan_view.mojo out/castle.png .cache/wijnendale/wijnendale.splat +y

The first argument is the file to write, `.cache/wijnendale/wijnendale.splat`
by default. A path that ends in `.png` writes the scan to that default file,
then draws the scan from above the woods to the picture, as the gallery
does. VIEWS is how many pictures to take, 24 by default, and SIZE their
width and height in pixels, 800 by default. The report goes to the standard
error, one JSON object a line.
"""

from core.clock import Clock
from core.object3d import Object3D
from core.scene import Scene
from extensions.castle.scene import (
    aim_sun,
    build_castle_scene,
    castle_renderer,
    default_settings,
    draw_castle,
)
from extensions.castle.sun import day_of_year, solar_position
from extensions.castle.wijnendale import latitude, longitude, wijnendale_plan
from extensions.scan.virtual import VirtualScan, default_virtual_scan_options
from math.vector3 import Vector3
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from render.splat_lod import build_splat_lod, prepare_splat_lod
from render.splat_raster import rasterize_splats
from render.working_space import resolve_srgb_working, srgb_working_target
from std.math import cos, pi, sin
from std.os import makedirs
from std.os.path import exists
from std.pathlib import Path
from std.sys import argv, num_logical_cores, stderr
from std.time import perf_counter_ns
from tools._example_output import gallery_camera
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = ".cache/wijnendale/wijnendale.splat"
comptime VIEWS = 24
comptime SIZE = 800
comptime HOURS_UTC = 13.0
comptime CLOUD_COVER = 0.55
comptime MIDDLE_X = 40.0
"""The middle of the castle, east, in meters from the plan's origin."""
comptime MIDDLE_Z = -45.0
"""The middle of the castle, in the scene: south is positive."""
comptime MIDDLE_Y = 8.0
"""How high the cameras look, in meters over the island."""
comptime PICTURE_WIDTH = 960
comptime PICTURE_HEIGHT = 540
comptime BACKGROUND = Color(7, 8, 15)


def main() raises:
    var words = List[String]()
    for word in argv():
        words.append(String(word))
    var destination = String(DEFAULT_OUTPUT)
    if len(words) > 1:
        destination = words[1]
    var picture = String("")
    if destination.endswith(".png"):
        picture = destination
        destination = String(DEFAULT_OUTPUT)
    var views = VIEWS
    if len(words) > 2:
        views = Int(words[2])
    var size = SIZE
    if len(words) > 3:
        size = Int(words[3])

    var plan = wijnendale_plan()
    var renderer = castle_renderer(size, size)
    # The woods are scanned too, so no place is kept clear of trees.
    var castle = build_castle_scene(
        plan, default_settings(), MIDDLE_X, -MIDDLE_Z, 1.0
    )
    var sun = solar_position(
        latitude(), longitude(), 2026, day_of_year(2026, 10, 19), HOURS_UTC
    )
    var toward = sun.toward()
    aim_sun(
        castle,
        renderer,
        Vector3(Float32(toward[0]), Float32(toward[2]), Float32(-toward[1])),
    )

    var scan = VirtualScan(default_virtual_scan_options())
    var spent = Float64(0)
    # Rings of cameras: far and high, then nearer and lower, at turning
    # angles so that the rings do not line up.
    for view in range(views):
        var ring = view % 3
        var radius = Float32(150.0)
        var rise = Float32(0.9)
        if ring == 1:
            radius = 105.0
            rise = 0.45
        elif ring == 2:
            radius = 75.0
            rise = 0.22
        var angle = Float32(2 * pi) * Float32(view) / Float32(views) * 3
        var eye = Vector3(
            Float32(MIDDLE_X) + radius * sin(angle),
            Float32(MIDDLE_Y) + radius * rise,
            Float32(MIDDLE_Z) + radius * cos(angle),
        )
        var camera = gallery_camera(
            size,
            size,
            eye,
            Vector3(Float32(MIDDLE_X), Float32(MIDDLE_Y), Float32(MIDDLE_Z)),
            field_of_view=Angle(50.0, DEGREE),
            near=Length(2.0, METER),
            far=Length(900.0, METER),
        )
        var began = perf_counter_ns()
        var image = draw_castle(castle, renderer, camera, CLOUD_COVER, view)
        var taken = scan.add_view(
            image, camera.view_matrix(), camera.projection_matrix()
        )
        var took = Float64(perf_counter_ns() - began) / 1e6
        spent += took
        print(
            '{"view": ',
            view,
            ', "samples": ',
            taken,
            ', "splats": ',
            scan.count(),
            ', "ms": ',
            took,
            "}",
            sep="",
            file=stderr,
        )
    var folder = String(destination)
    var cut = folder.rfind("/")
    if cut > 0:
        var parent = String(folder[byte=:cut])
        if not exists(parent):
            makedirs(parent)
    scan.write(destination)
    print(
        '{"views": ',
        views,
        ', "splats": ',
        scan.count(),
        ', "samples": ',
        scan.samples,
        ', "total_s": ',
        spent / 1e3,
        "}",
        sep="",
        file=stderr,
    )
    print("Wrote", destination, "-", scan.count(), "splats")
    if picture:
        draw_scan(scan, picture)


def draw_scan(scan: VirtualScan, path: String) raises:
    """Draw the scan's splats from above the woods, and write the picture.

    Args:
        scan: The scan, in the scene's axes.
        path: The PNG file to write.

    Raises:
        Error: If the splats cannot be drawn or the file cannot be written.
    """
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    var lod = build_splat_lod(scan.geometry(), node)
    var camera = gallery_camera(
        PICTURE_WIDTH,
        PICTURE_HEIGHT,
        Vector3(
            Float32(MIDDLE_X) - 95,
            Float32(MIDDLE_Y) + 80,
            Float32(MIDDLE_Z) + 95,
        ),
        Vector3(Float32(MIDDLE_X), Float32(MIDDLE_Y) - 6, Float32(MIDDLE_Z)),
        field_of_view=Angle(50.0, DEGREE),
        near=Length(1.0, METER),
        far=Length(900.0, METER),
    )
    var workers = num_logical_cores()
    var target = srgb_working_target(PICTURE_WIDTH, PICTURE_HEIGHT, BACKGROUND)
    var selected = prepare_splat_lod(
        scene,
        lod,
        camera,
        PICTURE_WIDTH,
        PICTURE_HEIGHT,
        target.depth_mode,
        None,
        workers,
    )
    rasterize_splats(target, selected, workers)
    var frames = List[Framebuffer]()
    frames.append(resolve_srgb_working(target))
    Path(path).write_bytes(encode(frames, delay_ms=100))
    print("Wrote", path)
