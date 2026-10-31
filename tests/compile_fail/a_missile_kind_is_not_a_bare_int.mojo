# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A missile kind must be a `MissileKind`, not a bare integer."""

from extensions.village.combat import Blow
from extensions.village.missiles import Missile
from math.vector3 import Vector3
from units.si import METER_PER_SECOND, Velocity


def main() raises:
    print(
        Missile(
            0,
            Vector3(0, 0, 0),
            Vector3(0, 0, 1),
            -1,
            -1,
            Blow(
                1,
                1,
                Velocity(0.0, METER_PER_SECOND),
                Velocity(0.0, METER_PER_SECOND),
            ),
        ).age
    )
