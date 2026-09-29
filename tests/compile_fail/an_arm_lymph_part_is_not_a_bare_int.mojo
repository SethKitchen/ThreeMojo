# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An arm lymphatic must be an `ArmLymph`, not a bare integer."""

from extensions.humanoid.skeleton.arm.lymph.dimensions import arm_lymph_label


def main() raises:
    print(arm_lymph_label(0))
