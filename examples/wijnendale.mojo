# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wijnendale Castle from the air, in autumn.

    mojo run -I . examples/wijnendale.mojo [path.png]

The page is Castle. `wijnendale_plan` is the plan of the castle at Torhout,
built from the Flemish survey and the airborne laser scan, and `castle_meshes`
turns it into geometry with the depth of the real building: walls with their
windows cut through, dormers, spires and crenellations. `castle_look` gives
each surface a physically based material, and the woods are grown from a branch
skeleton with cards of leaves.

The sun is where it stands over Torhout at 15:00 local time on 19 October 2026.
The sky lights the scene through a prefiltered environment, and the sun casts
soft shadows. The moat is Clearwater water: the renderer draws the scene, and
`compose` puts the water into the picture where it is nearest. The castle and
the wood are reflected in it by Fresnel's law.

The camera looks north-east from the south-west and from the air, as the
photograph that the plan was checked against does. The gate stands on the
right, the bridge leaves it for the lower right, and the donjon rises behind
the courtyard.
"""

from tools._example_output import (
    example_destination,
    gallery_camera,
    write_example,
)

from core.clock import Clock
from extensions.castle.scene import (
    aim_sun,
    build_castle_scene,
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
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/wijnendale.png"
comptime WIDTH = 800
comptime HEIGHT = 1000
comptime FRAMES = 1
comptime DELAY_MS = 100
# 15:00 on 19 October 2026 at Torhout is 13:00 UTC: summer time is two hours
# ahead, and ends on 25 October.
comptime HOURS_UTC = 13.0
comptime CLOUD_COVER = 0.55


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))

    var plan = wijnendale_plan()
    var renderer = castle_renderer(WIDTH, HEIGHT)
    # Local x east and y north become x and -z. The camera stands south-west
    # of the castle, 49 m up, and looks at the courtyard. No tree stands
    # within 45 m of it.
    var eye = Vector3(-30, 49, 16)
    var castle = build_castle_scene(
        plan, default_settings(), Float64(eye.x), Float64(-eye.z), 45.0
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

    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        eye,
        Vector3(32, 20, -42),
        field_of_view=Angle(58.0, DEGREE),
        near=Length(1.0, METER),
        far=Length(6000.0, METER),
    )

    var frame_clock = Clock()
    frame_clock.start()
    var frames = List[Framebuffer]()
    frames.append(draw_castle(castle, renderer, camera, CLOUD_COVER, 5))
    write_example(frames, destination, DELAY_MS, FRAMES, frame_clock)
