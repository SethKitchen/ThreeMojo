# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An arm ligament must be an `ArmLigament`, not a bare integer."""

from extensions.humanoid.skeleton.arm.ligaments.dimensions import (
    arm_ligament_label,
)


def main() raises:
    print(arm_ligament_label(0))
