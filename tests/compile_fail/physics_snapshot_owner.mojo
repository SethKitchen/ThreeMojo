# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A historical snapshot owner is not a live world body id."""

from extensions.physics.query_snapshot import SnapshotOwner
from extensions.physics.world import PhysicsWorld


def _wrong(world: PhysicsWorld, owner: SnapshotOwner) raises:
    world.check(owner)


def main():
    pass
