# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A body kind must be a `BodyKind`, not a bare integer."""

from extensions.carla.physics.body import RigidBody
from extensions.carla.physics.shape import Shape
from math.quaternion import Quaternion
from math.vector3 import Vector3
from units.si import KILOGRAM, METER, Length, Mass


def main() raises:
    var body = RigidBody(
        1,
        Shape.sphere(Length(1, METER)),
        Mass(1, KILOGRAM),
        Vector3(0, 0, 0),
        Quaternion.identity(),
    )
    print(body.mass())
