# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Attach a generated part under a parent.

`place_root` hangs an empty node at `origin`. `place_mesh` hangs one
solid under a node. The default place is the parent's origin.
"""

from core.assets import Assets
from core.buffer_geometry import BufferGeometry
from core.object3d import NodeId, Object3D
from core.scene import Scene
from materials.material import MaterialId
from math.vector3 import Vector3
from objects.mesh import Mesh


def place_root(
    mut scene: Scene,
    parent: NodeId,
    origin: Vector3 = Vector3(0, 0, 0),
) raises -> NodeId:
    """Attach an empty node under `parent` at `origin`.

    Args:
        scene: The scene that receives the node.
        parent: Node the part hangs from.
        origin: Position of the new node in the parent, in meters.
            The parent's origin is the default.

    Returns:
        The new node's id.

    Raises:
        Error: If the scene refuses the node.
    """
    var node = Object3D()
    node.set_position(origin.x, origin.y, origin.z)
    return scene.attach(node^, parent)


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
    var nid = place_root(scene, parent, origin)
    var shape = assets.geometries.add(geometry^)
    scene.add_mesh(Mesh(shape, paint, nid))
    return nid
