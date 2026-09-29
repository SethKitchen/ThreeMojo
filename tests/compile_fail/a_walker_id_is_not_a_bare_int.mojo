# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A walker id must be a `WalkerId`, not a bare integer."""

from extensions.carla.physics.simulation import CarlaPhysics


def main() raises:
    var sim = CarlaPhysics()
    print(sim.walker_body(0).value)
