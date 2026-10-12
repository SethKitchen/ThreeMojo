# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Require an explicit source-unit adapter for an arbitrary integer epoch."""

from extensions.carla.v2x import CaService, CamNoise
from tests.test_carla_world import _world
from extensions.carla.actor import ActorId
from units.si import Duration


def main() raises:
    var world = _world()
    _ = CaService(
        world, ActorId(0), Duration(0.1), Duration(1), True, CamNoise(), 1234
    )
