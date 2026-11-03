# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wijnendale Castle in a landscape of mountains, woods and lakes.

    mojo run -I . examples/wijnendale_landscape.mojo [path.png] [WIDTH] [HEIGHT] [EYE_X EYE_Y EYE_Z TARGET_X TARGET_Y TARGET_Z]

The page is Landscape. The castle, the water and the ground are one scene:

- The castle is `castle_meshes` of the plan of Wijnendale, with its ground
  left out.
- The ground is the castle's own meadow, bank and moat bed round the moat,
  and the mountain range of `generators.terrain` beyond a kilometer. A weight
  joins the two, so nothing jumps.
- The water is the Clearwater of `extensions.water`, one plane at the level of
  the moat. It floods the moat, and every basin of the mountains that lies
  under that level, so the moat and the lakes are one water.
- The woods stand on the ground, by altitude, slope and the nearness of the
  water, and thin out toward the treeline.

The fog is the color of the horizon, so the far mountains fade into the sky.
"""

from tools._scan_demo import open_scan
from tools._example_output import (
    example_destination,
    gallery_camera,
    write_example,
)

from core.clock import Clock
from extensions.castle.forest import Clearing, default_forest
from extensions.castle.landscape import (
    build_landscape,
    default_landscape,
    find_site,
)
from extensions.castle.scene import (
    add_splat_layer,
    aim_sun,
    build_landscape_scene,
    castle_renderer,
    default_settings,
    draw_castle,
)
from extensions.castle.sun import day_of_year, solar_position
from extensions.castle.wijnendale import (
    latitude,
    longitude,
    wijnendale_plan,
)
from math.vector3 import Vector3
from render.framebuffer import Framebuffer
from extensions.scan.composite import splat_layer
from std.math import atan2, pi
from std.sys import argv, stderr
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/wijnendale-landscape.png"
comptime WIDTH = 1920
comptime HEIGHT = 1080
comptime FRAMES = 1
comptime DELAY_MS = 100
# 15:00 on 19 October 2026 at Torhout is 13:00 UTC.
comptime HOURS_UTC = 13.0
comptime CLOUD_COVER = 0.5


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var words = List[String]()
    for word in argv():
        words.append(String(word))
    var width = WIDTH
    var height = HEIGHT
    if len(words) > 3:
        width = Int(words[2])
        height = Int(words[3])

    var plan = wijnendale_plan()
    var renderer = castle_renderer(width, height)
    var settings = default_settings()
    var landscape = default_landscape()
    landscape.seed = 22
    if len(words) > 10:
        landscape.seed = Int(words[10])
    # Local x east and y north become x and -z. The camera stands south-west
    # of the castle, 60 m up, and looks over the church and the castle to the
    # lake and the mountains.
    var eye = Vector3(-160, 60, 60)
    var target = Vector3(-30, 18, -42)
    if len(words) > 9:
        eye = Vector3(
            Float32(atof(words[4])),
            Float32(atof(words[5])),
            Float32(atof(words[6])),
        )
        target = Vector3(
            Float32(atof(words[7])),
            Float32(atof(words[8])),
            Float32(atof(words[9])),
        )
    # Only the trees that the camera sees are planted: the view, and a margin.
    var woods = default_forest()
    woods.eye_x = Float64(eye.x)
    woods.eye_y = Float64(-eye.z)
    woods.heading = atan2(Float64(-target.z + eye.z), Float64(target.x - eye.x))
    woods.half_view = 0.85
    woods.keep_radius = 100.0
    var land = build_landscape(plan, landscape)
    # A village church, scanned as Gaussian splats, stands on open ground to
    # the left of the castle. No tree stands in its churchyard.
    var site = find_site(land, -100.0, 40.0, 24.0, 45.0)
    var clearings = List[Clearing]()
    clearings.append(Clearing(site.x.value, site.y.value, 55.0))
    # The line of sight from the eye to the castle is clear of trees.
    var castle_x = 30.0
    var castle_y = 45.0
    for step in range(6):
        var share = 0.2 + 0.13 * Float64(step)
        clearings.append(
            Clearing(
                woods.eye_x + share * (castle_x - woods.eye_x),
                woods.eye_y + share * (castle_y - woods.eye_y),
                32.0,
            )
        )
    var castle = build_landscape_scene(plan, settings, land, woods, clearings)
    var yaw = 0.0
    if len(words) > 11:
        yaw = Float64(atof(words[11])) * pi / 180.0
    # Without the cached scan the churchyard stays empty, and a note says how
    # to fetch the church.
    try:
        var scan = open_scan("seem-church")
        print(
            '{"church": "',
            scan.title,
            '", "by": "',
            scan.author,
            '", "license": "CC BY 4.0", "splats": ',
            scan.splats.count(),
            "}",
            sep="",
            file=stderr,
        )
        add_splat_layer(
            castle,
            splat_layer(
                scan.splats,
                scan.frame,
                site.x.value,
                site.y.value,
                land.height(site.x.value, site.y.value),
                yaw,
            ),
        )
    except error:
        print('{"church": null, "note": "', error, '"}', sep="", file=stderr)

    var sun = solar_position(
        latitude(), longitude(), 2026, day_of_year(2026, 10, 19), HOURS_UTC
    )
    var toward = sun.toward()
    aim_sun(
        castle,
        renderer,
        Vector3(Float32(toward[0]), Float32(toward[2]), Float32(-toward[1])),
    )

    var camera = gallery_camera(
        width,
        height,
        eye,
        target,
        field_of_view=Angle(50.0, DEGREE),
        near=Length(1.0, METER),
        far=Length(20000.0, METER),
    )

    var frame_clock = Clock()
    frame_clock.start()
    var frames = List[Framebuffer]()
    frames.append(draw_castle(castle, renderer, camera, CLOUD_COVER, 5))
    write_example(frames, destination, DELAY_MS, FRAMES, frame_clock)
