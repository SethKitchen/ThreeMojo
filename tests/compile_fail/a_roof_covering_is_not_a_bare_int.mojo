# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A house's roof covering must be a `RoofCovering`, not a bare integer."""

from extensions.building.material import brick
from extensions.village.house import HouseParameters
from units.si import METER, Length


def main() raises:
    var house = HouseParameters(
        "house", Length(5.0, METER), Length(4.0, METER), 1, brick(), covering=3
    )
    print(house.name)
