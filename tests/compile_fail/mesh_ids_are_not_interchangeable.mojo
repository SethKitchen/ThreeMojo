# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Transposing a mesh's material and node must not compile.

The reason the ids are types. `Mesh` takes three small integers in a row, and
as plain `Int`s this swap compiled and rendered nonsense.
"""

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import cube
from materials.material import Material
from objects.mesh import Mesh
from render.framebuffer import Color
from units.si import Length, METER


def main() raises:
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var paint = assets.materials.add(Material(Color(255, 0, 0)))
    var scene = Scene()
    var node = scene.add(Object3D())
    # material and node the wrong way round
    var bad = Mesh(box, node, paint)
    print(bad.node.value)
