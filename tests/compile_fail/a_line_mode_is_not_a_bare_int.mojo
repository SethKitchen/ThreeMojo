# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a line mode."""

from core.geometry_store import GeometryId
from core.object3d import NodeId
from materials.material import MaterialId
from objects.line import Line


def main() raises:
    var line = Line(GeometryId(0), MaterialId(0), NodeId(0), mode=1)
    print(line.node.value)
