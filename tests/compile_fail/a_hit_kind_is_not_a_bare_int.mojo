# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a hit kind."""

from core.geometry_store import GeometryId
from core.object3d import NodeId
from core.raycaster import Hit
from materials.material import MaterialId
from math.vector3 import Vector3
from objects.mesh import Mesh


def main() raises:
    var mesh = Mesh(GeometryId(0), MaterialId(0), NodeId(0))
    var bad = Hit(1.0, Vector3(0, 0, 0), Vector3(0, 0, 1), 0, 0, -1, mesh, 0)
    print(bad.distance)
