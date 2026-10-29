# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An octree filled from a scene, three.js's `Octree.fromGraphNode`.

It lives apart from `math.octree` so that the tree, and the physics built
on it, do not depend on the scene graph.
"""

from core.assets import Assets
from core.object3d import NodeId
from core.scene import Scene
from math.octree import Octree
from math.triangle import Triangle


def from_graph_node(
    mut octree: Octree, mut scene: Scene, assets: Assets, node: NodeId
) raises:
    """Add the triangles of every mesh at and below a node, in world
    space, and build. three.js: `fromGraphNode`.

    The scene is updated first, as three.js updates the world matrices.
    A mesh counts if its node shares a layer with the tree's `layers`,
    visible or not.

    Args:
        octree: The tree to add to.
        scene: The scene.
        assets: The geometry the meshes name.
        node: Where to start.

    Raises:
        Error: If the node is not in the scene, the scene cannot update,
            or a mesh names a geometry that is not there or has no
            positions.
    """
    scene.update()
    # The node itself is always the first.
    for visited in scene.descendants(node):  # pragma: no branch
        var layers = scene.get(visited).layers
        if not octree.layers.test(layers):
            continue
        var world = scene.world_matrix(visited)
        for mesh in scene.meshes:
            if mesh.node != visited:
                continue
            ref geometry = assets.geometries.get(mesh.geometry)
            for triangle in range(geometry.triangle_count()):
                octree.add_triangle(
                    Triangle(
                        world.transform_point(geometry.corner(triangle, 0)),
                        world.transform_point(geometry.corner(triangle, 1)),
                        world.transform_point(geometry.corner(triangle, 2)),
                    )
                )
    octree.build()
