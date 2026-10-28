# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A villager's home must be a `HouseId`, not a bare integer."""

from extensions.attire.outfit import Outfit
from extensions.humanoid.sex import FEMALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.village.residents import Villager
from units.si import INCH, Length


def main() raises:
    var villager = Villager(
        HumanoidSpec(Length(60.0, INCH), FEMALE),
        0,
        0,
        1,
        1,
        False,
        Outfit(),
        2,
    )
    print(villager.seed)
