# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An arm hair group must be an `ArmHair`, not a bare integer."""

from extensions.humanoid.skeleton.arm.hair.dimensions import arm_hair_label


def main() raises:
    print(arm_hair_label(1))
