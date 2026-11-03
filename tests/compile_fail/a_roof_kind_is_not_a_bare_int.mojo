# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for the roof of a tower: name it, as
`CONE` or `FLAT`."""

from extensions.castle.kinds import MEASURED
from extensions.castle.plan import Tower, point
from units.si import Length64


def main() raises:
    var tower = Tower(
        "Tower",
        point(0, 0),
        Length64(2.0),
        Length64(0.0),
        Length64(10.0),
        1,
        Length64(4.0),
        MEASURED,
    )
    tower.check()
