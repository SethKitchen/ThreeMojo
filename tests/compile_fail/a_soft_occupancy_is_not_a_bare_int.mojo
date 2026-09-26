# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A soft fill must be a `SoftOccupancy`, not a bare integer."""

from extensions.humanoid.skeleton.soft_tissue import (
    cartilage_tissue,
    filled_density,
)


def main() raises:
    var density = filled_density(0, cartilage_tissue())
    print(density.value)
