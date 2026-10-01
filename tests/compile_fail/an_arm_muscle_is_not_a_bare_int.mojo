# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An arm muscle must be an `ArmMuscle`, not a bare integer."""

from extensions.humanoid.skeleton.arm.muscles.dimensions import arm_muscle_label


def main() raises:
    print(arm_muscle_label(7))
