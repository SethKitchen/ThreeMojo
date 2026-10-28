# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A house's use must be a `HouseUse`, not a bare integer."""

from extensions.building.material import brick
from extensions.village.house import BOARDED, HouseParameters
from units.si import METER, Length


def main() raises:
    var house = HouseParameters(
        "barn",
        Length(9.0, METER),
        Length(6.0, METER),
        1,
        brick(),
        BOARDED,
        Length(4.0, METER),
        use=1,
    )
    print(house.storeys)
