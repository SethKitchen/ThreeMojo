# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An arm bone must be an `ArmBone`, not a bare integer."""

from extensions.humanoid.skeleton.arm.bones.dimensions import arm_bone_label


def main() raises:
    print(arm_bone_label(1))
