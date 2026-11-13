# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A hinge limit must be an `Angle`, not a bare number."""

from extensions.physics.joint import JointId
from extensions.physics.world import PhysicsWorld


def main() raises:
    var world = PhysicsWorld()
    world.set_hinge_limits(JointId(0), -0.5, 0.5)
