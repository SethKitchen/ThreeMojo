# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A soft-tissue kind must be a `SoftTissueKind`, not a bare integer."""

from extensions.humanoid.skeleton.soft_tissue import SoftTissue
from units.si import Density, GRAM_PER_CUBIC_CENTIMETER, MEGAPASCAL, Pressure


def main() raises:
    var tissue = SoftTissue(
        0,
        Density(1.12, GRAM_PER_CUBIC_CENTIMETER),
        0.75,
        Pressure(0.70, MEGAPASCAL),
        0.45,
    )
    print(tissue.water_fraction)
