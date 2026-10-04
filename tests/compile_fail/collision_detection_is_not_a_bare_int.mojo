# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A collision detection mode must carry its type."""

from extensions.physics.world import PhysicsWorld


def main():
    var world = PhysicsWorld()
    world.collision_detection = 1
