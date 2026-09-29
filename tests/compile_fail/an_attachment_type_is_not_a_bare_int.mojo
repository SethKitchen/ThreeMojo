# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An attachment type must be an `AttachmentType`, not a bare integer."""

from extensions.carla.actor import NO_ACTOR, RIGID
from extensions.carla.opendrive import load_opendrive
from extensions.carla.transform import CarlaRotation, CarlaTransform
from extensions.carla.world import World
from units.si import DEGREE, METER, Angle, Length


def main() raises:
    var world = World(load_opendrive("<OpenDRIVE></OpenDRIVE>"))
    var r = CarlaRotation(Angle(0, DEGREE), Angle(0, DEGREE), Angle(0, DEGREE))
    var t = CarlaTransform(
        Length(0, METER), Length(0, METER), Length(0, METER), r
    )
    var bp = world.blueprints.at("sensor.camera.rgb")
    print(world.spawn_actor(bp, t, NO_ACTOR, 0))
