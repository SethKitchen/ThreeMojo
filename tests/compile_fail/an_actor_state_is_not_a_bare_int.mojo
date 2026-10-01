# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An actor state must be an `ActorState`, not a bare integer."""

from extensions.carla.actor import ACTOR_DORMANT, ActorId
from extensions.carla.transform import CarlaRotation, CarlaTransform
from extensions.carla.world_snapshot import ActorSnapshot
from math.vector3 import Vector3
from units.si import DEGREE, METER, Angle, Length


def main() raises:
    var r = CarlaRotation(Angle(0, DEGREE), Angle(0, DEGREE), Angle(0, DEGREE))
    var t = CarlaTransform(
        Length(0, METER), Length(0, METER), Length(0, METER), r
    )
    var z = Vector3(0, 0, 0)
    var s = ActorSnapshot(ActorId(1), 2, t, z, z, z)
    print(s.sign_id)
