# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bone kind must be a `BoneKind`, not a bare integer."""

from extensions.humanoid.skeleton.bone import BoneTissue
from units.si import Density, GRAM_PER_CUBIC_CENTIMETER, GIGAPASCAL, Pressure


def main() raises:
    var tissue = BoneTissue(
        0,
        Density(2.0, GRAM_PER_CUBIC_CENTIMETER),
        0.1,
        Pressure(17.9, GIGAPASCAL),
        Pressure(18.16, GIGAPASCAL),
        0.62,
    )
    print(tissue.porosity)
