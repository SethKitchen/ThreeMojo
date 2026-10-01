# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A body id must be a `BodyId`, not a bare integer."""

from extensions.carla.physics.world import PhysicsWorld


def main() raises:
    var world = PhysicsWorld()
    world.check(0)
