# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not say how a dimension of a castle was found: name
it, as `SURVEYED` or `ESTIMATED`."""

from extensions.castle.kinds import CONE
from extensions.castle.plan import Tower, point
from units.si import Length64


def main() raises:
    var tower = Tower(
        "Tower",
        point(0, 0),
        Length64(2.0),
        Length64(0.0),
        Length64(10.0),
        CONE,
        Length64(4.0),
        0,
    )
    tower.check()
