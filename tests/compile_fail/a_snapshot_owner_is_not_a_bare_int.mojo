# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A capture requires its typed historical owner, not a bare integer."""

from extensions.physics.query_snapshot import PhysicsQuerySnapshot
from extensions.physics.world import PhysicsWorld


def main() raises:
    var world = PhysicsWorld()
    var snapshot = PhysicsQuerySnapshot(world)
    snapshot.check_owner(0)
