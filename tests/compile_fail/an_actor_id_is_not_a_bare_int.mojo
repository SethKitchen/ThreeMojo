# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An actor id must be an `ActorId`, not a bare integer."""

from extensions.carla.actor import ActorId
from extensions.carla.opendrive import load_opendrive
from extensions.carla.world import World


def main() raises:
    var world = World(load_opendrive("<OpenDRIVE></OpenDRIVE>"))
    print(world.is_alive(1))
