# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An actor kind must be an `ActorKind`, not a bare integer."""

from extensions.carla.actor import Actor, ActorId, VEHICLE_ACTOR
from extensions.carla.blueprint import ActorAttributeValue
from extensions.carla.bounding_box import BoundingBox
from extensions.carla.sensor import SemanticTag
from extensions.carla.transform import CarlaRotation, CarlaTransform
from math.vector3 import Vector3
from units.si import DEGREE, METER, Angle, Length


def main() raises:
    var r = CarlaRotation(Angle(0, DEGREE), Angle(0, DEGREE), Angle(0, DEGREE))
    var t = CarlaTransform(
        Length(0, METER), Length(0, METER), Length(0, METER), r
    )
    var a = Actor(
        ActorId(1),
        "x",
        1,
        List[ActorAttributeValue](),
        t,
        BoundingBox(Vector3(0, 0, 0)),
        List[SemanticTag](),
    )
    print(a.type_id)
