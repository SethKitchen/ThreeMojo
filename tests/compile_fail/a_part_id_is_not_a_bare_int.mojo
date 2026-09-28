# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for the zone a generator part is
tagged with: name it with a `PartId`."""

from generators.utils import part
from geometries.box import box
from units.si import Length, METER


def main() raises:
    var cube = box(Length(1, METER), Length(1, METER), Length(1, METER))
    var tagged = part(cube, 3)
    print(tagged.vertex_count())
