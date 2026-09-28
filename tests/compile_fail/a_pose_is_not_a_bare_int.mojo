# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a pedestrian's pose: say `WALK`
or `STAND`."""

from generators.person import person_geometry
from units.si import Length, METER


def main() raises:
    var figure = person_geometry(0, Length(1.75, METER))
    print(figure.vertex_count())
