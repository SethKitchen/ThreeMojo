# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A wide-line coverage rule is not a bare integer."""

from core.geometry_store import GeometryId
from core.object3d import NodeId
from materials.material import MaterialId
from objects.line_segments2 import LineSegments2


def main() raises:
    var line = LineSegments2(
        GeometryId(0), MaterialId(0), NodeId(0), coverage=1
    )
    print(line.node.value)
