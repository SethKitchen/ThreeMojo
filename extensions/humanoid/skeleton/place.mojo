# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Attach one generated solid under a body part.

The foot, the pelvis, the leg and the torso each hang their layers from
one root. The mesh sits at `origin` in that root. The default is the
root's origin. The caller has already placed the root in the part's
frame.
"""

from core.assets import Assets
from core.buffer_geometry import BufferGeometry
from core.object3d import NodeId, Object3D
from core.scene import Scene
from materials.material import MaterialId
from math.vector3 import Vector3
from objects.mesh import Mesh


def place_mesh(
    mut scene: Scene,
    mut assets: Assets,
    parent: NodeId,
    var geometry: BufferGeometry,
    paint: MaterialId,
    origin: Vector3 = Vector3(0, 0, 0),
) raises -> NodeId:
    """Attach one mesh under `parent` and return its node.

    Args:
        scene: The scene that receives the node and the mesh.
        assets: Geometry store for the new mesh.
        parent: Node the part hangs from.
        geometry: The solid to draw.
        paint: Material id.
        origin: Position of the solid's frame in the parent, in meters.
            The parent's origin is the default.

    Returns:
        The new node's id.

    Raises:
        Error: If the scene refuses the node or the mesh.
    """
    var node = Object3D()
    node.set_position(origin.x, origin.y, origin.z)
    var nid = scene.attach(node^, parent)
    var shape = assets.geometries.add(geometry^)
    scene.add_mesh(Mesh(shape, paint, nid))
    return nid
