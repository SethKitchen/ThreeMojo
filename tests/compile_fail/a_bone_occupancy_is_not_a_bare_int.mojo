# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A femur fill must be a `BoneOccupancy`, not a bare integer."""

from extensions.humanoid.skeleton.tissue import (
    cortical_tissue,
    trabecular_tissue,
)
from extensions.humanoid.skeleton.leg.femur.mass import apparent_density_of


def main() raises:
    var density = apparent_density_of(0, cortical_tissue(), trabecular_tissue())
    print(density.value)
