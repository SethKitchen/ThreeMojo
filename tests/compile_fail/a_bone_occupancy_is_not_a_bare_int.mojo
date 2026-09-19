# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A femur fill must be a `BoneOccupancy`, not a bare integer."""

from extensions.humanoid.skeleton.bone import cortical_tissue, trabecular_tissue
from extensions.humanoid.skeleton.leg.femur.mass import mineral_density


def main() raises:
    var density = mineral_density(0, cortical_tissue(), trabecular_tissue())
    print(density.value)
