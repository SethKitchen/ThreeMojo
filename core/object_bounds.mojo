# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The bounds of scene content, from three.js `Box3.setFromObject`,
`Box3.expandByObject`, `Frustum.intersectsObject` and
`Frustum.intersectsSprite`.

three.js asks an object for its geometry and its world matrix, and walks
its children. Here an object is a node, and what is drawn at a node is in
the scene's lists: meshes, lines, points, wide lines, instanced and batched
meshes, skinned meshes and sprites. Each one that names
a node of the subtree adds its bound, carried to world space by the node's
world matrix. The scene must be updated first.

The bound of each thing is three.js's. A mesh, a line, a set of points or a
wide line adds its geometry's box. An instanced or a batched mesh adds the
box of its instances' boxes, three.js's object-level `boundingBox`. A level
of detail adds every level, shown or hidden, because each level is a child
node, as in three.js. A skinned
mesh adds the box of its posed vertices, as three.js's `SkinnedMesh`
computes it. A sprite adds the unit square three.js's sprite geometry is.

With `precise`, each vertex is carried to world space on its own, which
gives a tighter box for a turned object. A mesh or a skinned mesh wears its
morph targets there, as three.js's `getVertexPosition` does. An instanced
or a batched mesh uses its box, as in three.js.

The geometry's own box leaves its morph targets out, as
`BufferGeometry.bounding_box` does. three.js's includes them.
"""

from core.assets import Assets
from core.buffer_geometry import POSITION
from core.deform import morphed_positions, skin_carriers, skin_pose
from core.geometry_store import GeometryId
from core.morph import MorphInfluences
from core.object3d import NodeId
from core.scene import Scene
from math.bounds import Box3, Sphere
from math.frustum import Frustum
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.instanced_mesh import InstancedMesh
from objects.line import Line
from objects.mesh import Mesh
from objects.points import Points
from objects.sprite import SPRITE_RADIUS, Sprite


def box_from_object(
    scene: Scene, assets: Assets, node: NodeId, precise: Bool = False
) raises -> Box3:
    """Return the world-space box around everything drawn at a node and
    under it, three.js's `Box3.setFromObject`.

    Args:
        scene: The scene, updated.
        assets: Where the geometry lives.
        node: The root of the subtree.
        precise: True to carry each vertex to world space on its own.

    Returns:
        The box. Empty if nothing is drawn in the subtree.

    Raises:
        Error: If the node is not in the scene, the scene is stale, or a
            geometry is missing or has no positions.
    """
    var box = Box3.empty()
    expand_by_object(box, scene, assets, node, precise)
    return box


def expand_by_object(
    mut box: Box3,
    scene: Scene,
    assets: Assets,
    node: NodeId,
    precise: Bool = False,
) raises:
    """Grow a box to hold everything drawn at a node and under it, in
    world space, three.js's `Box3.expandByObject`.

    Args:
        box: The box to grow.
        scene: The scene, updated.
        assets: Where the geometry lives.
        node: The root of the subtree.
        precise: True to carry each vertex to world space on its own.

    Raises:
        Error: If the node is not in the scene, the scene is stale, or a
            geometry is missing or has no positions.
    """
    var inside = List[Bool](length=scene.count(), fill=False)
    var subtree = scene.descendants(node)
    for index in range(len(subtree)):  # pragma: no branch
        inside[subtree[index].value] = True
    var none = MorphInfluences()
    for index in range(len(scene.meshes)):
        ref mesh = scene.meshes[index]
        if inside[mesh.node.value]:
            _add_geometry(
                box,
                scene,
                assets,
                mesh.geometry,
                mesh.node,
                precise,
                True,
                mesh.morph_influences,
            )
    for index in range(len(scene.lines)):
        ref line = scene.lines[index]
        if inside[line.node.value]:
            _add_geometry(
                box,
                scene,
                assets,
                line.geometry,
                line.node,
                precise,
                False,
                none,
            )
    for index in range(len(scene.points)):
        ref cloud = scene.points[index]
        if inside[cloud.node.value]:
            _add_geometry(
                box,
                scene,
                assets,
                cloud.geometry,
                cloud.node,
                precise,
                False,
                none,
            )
    for index in range(len(scene.wide_lines)):
        ref wide = scene.wide_lines[index]
        if inside[wide.node.value]:
            _add_geometry(
                box, scene, assets, wide.geometry, wide.node, False, False, none
            )

    for index in range(len(scene.instanced_meshes)):
        ref instanced = scene.instanced_meshes[index]
        if inside[instanced.node.value]:
            ref shape = assets.geometries.get(instanced.geometry)
            var local = Box3.empty()
            for instance in range(instanced.count()):
                var one = shape.bounding_box()
                one.apply_matrix4(instanced.matrices[instance])
                local.union(one)
            local.apply_matrix4(scene.world_matrix(instanced.node))
            box.union(local)
    for index in range(len(scene.batched_meshes)):
        ref batched = scene.batched_meshes[index]
        if inside[batched.node.value]:
            var local = Box3.empty()
            for instance in range(batched.count()):
                ref placed = batched.instances[instance]
                # three.js's `computeBoundingBox` skips a deleted instance
                # and keeps a hidden one.
                if not placed.active:
                    continue
                var one = assets.geometries.get(placed.geometry).bounding_box()
                one.apply_matrix4(placed.matrix)
                local.union(one)
            local.apply_matrix4(scene.world_matrix(batched.node))
            box.union(local)
    for index in range(len(scene.skinned_meshes)):
        ref skinned = scene.skinned_meshes[index]
        if inside[skinned.node.value]:
            var world = scene.world_matrix(skinned.node)
            var posed = _posed(scene, assets, index)
            var local = Box3.empty()
            for vertex in range(len(posed)):
                if precise:
                    box.expand_by_point(world.transform_point(posed[vertex]))
                else:
                    local.expand_by_point(posed[vertex])
            local.apply_matrix4(world)
            box.union(local)
    for index in range(len(scene.sprites)):
        ref sprite = scene.sprites[index]
        if inside[sprite.node.value]:
            var square = Box3(Vector3(-0.5, -0.5, 0), Vector3(0.5, 0.5, 0))
            square.apply_matrix4(scene.world_matrix(sprite.node))
            box.union(square)


def _add_geometry(
    mut box: Box3,
    scene: Scene,
    assets: Assets,
    geometry: GeometryId,
    node: NodeId,
    precise: Bool,
    morphs: Bool,
    influences: MorphInfluences,
) raises:
    """Grow a box by one geometry drawn at one node.

    Args:
        box: The box to grow.
        scene: The scene, updated.
        assets: Where the geometry lives.
        geometry: Which geometry.
        node: Where it is drawn.
        precise: True to carry each vertex on its own.
        morphs: True if the thing drawn wears morph targets.
        influences: How much of each target it wears.

    Raises:
        Error: If the geometry is missing or has no positions, or the
            scene is stale.
    """
    ref shape = assets.geometries.get(geometry)
    var world = scene.world_matrix(node)
    if not precise:
        var local = shape.bounding_box()
        local.apply_matrix4(world)
        box.union(local)
        return
    var vertices: List[Vector3]
    if morphs:
        vertices = morphed_positions(shape, influences)
    else:
        vertices = List[Vector3]()
        ref positions = shape.attribute_view(String(POSITION))
        for vertex in range(positions.count()):
            vertices.append(positions.vector3(vertex))
    for vertex in range(len(vertices)):
        box.expand_by_point(world.transform_point(vertices[vertex]))


def _posed(scene: Scene, assets: Assets, index: Int) raises -> List[Vector3]:
    """Return a skinned mesh's vertices where its morph targets and its
    bones put them, in its own space: three.js's `getVertexPosition`.

    Args:
        scene: The scene, updated.
        assets: Where the geometry lives.
        index: Which skinned mesh, in `scene.skinned_meshes`.

    Returns:
        One point per vertex.

    Raises:
        Error: For anything `skin_pose` or `skin_carriers` raises for.
    """
    ref skinned = scene.skinned_meshes[index]
    ref shape = assets.geometries.get(skinned.geometry)
    var morphed = morphed_positions(shape, skinned.morph_influences)
    var carriers = skin_carriers(shape, skin_pose(scene, index), len(morphed))
    var out = List[Vector3]()
    for vertex in range(len(morphed)):
        out.append(carriers[vertex].transform_point(morphed[vertex]))
    return out^


def intersects_object(
    frustum: Frustum, scene: Scene, assets: Assets, mesh: Mesh
) raises -> Bool:
    """Return True if any of a mesh's bounding sphere, carried to world
    space, is in view, three.js's `Frustum.intersectsObject`.

    Args:
        frustum: The frustum, in world space.
        scene: The scene, updated.
        assets: Where the geometry lives.
        mesh: The mesh.

    Returns:
        Whether some of its bound is in view.

    Raises:
        Error: If the geometry is missing or has no positions, or the
            scene is stale.
    """
    return _sphere_in_view(frustum, scene, assets, mesh.geometry, mesh.node)


def intersects_object(
    frustum: Frustum, scene: Scene, assets: Assets, line: Line
) raises -> Bool:
    """Return True if any of a line's bounding sphere is in view,
    three.js's `Frustum.intersectsObject`.

    Args:
        frustum: The frustum, in world space.
        scene: The scene, updated.
        assets: Where the geometry lives.
        line: The line.

    Returns:
        Whether some of its bound is in view.

    Raises:
        Error: If the geometry is missing or has no positions, or the
            scene is stale.
    """
    return _sphere_in_view(frustum, scene, assets, line.geometry, line.node)


def intersects_object(
    frustum: Frustum, scene: Scene, assets: Assets, points: Points
) raises -> Bool:
    """Return True if any of a set of points' bounding sphere is in view,
    three.js's `Frustum.intersectsObject`.

    Args:
        frustum: The frustum, in world space.
        scene: The scene, updated.
        assets: Where the geometry lives.
        points: The points.

    Returns:
        Whether some of its bound is in view.

    Raises:
        Error: If the geometry is missing or has no positions, or the
            scene is stale.
    """
    return _sphere_in_view(frustum, scene, assets, points.geometry, points.node)


def intersects_object(
    frustum: Frustum, scene: Scene, assets: Assets, mesh: InstancedMesh
) raises -> Bool:
    """Return True if any of an instanced mesh's bounding sphere is in
    view, three.js's `Frustum.intersectsObject` with the object-level
    sphere: the union of the geometry's sphere under each instance.

    Args:
        frustum: The frustum, in world space.
        scene: The scene, updated.
        assets: Where the geometry lives.
        mesh: The instanced mesh.

    Returns:
        Whether some of its bound is in view. False with no instances.

    Raises:
        Error: If the geometry is missing or has no positions, or the
            scene is stale.
    """
    var shape = assets.geometries.get(mesh.geometry).bounding_sphere()
    var bound = Sphere.empty()
    for instance in range(mesh.count()):
        var one = shape
        one.apply_matrix4(mesh.matrices[instance])
        bound.union(one)
    bound.apply_matrix4(scene.world_matrix(mesh.node))
    return frustum.intersects_sphere(bound)


def intersects_sprite(
    frustum: Frustum, scene: Scene, sprite: Sprite
) raises -> Bool:
    """Return True if any of a sprite's bound is in view, three.js's
    `Frustum.intersectsSprite`.

    The bound is the sphere around the unit square, centered on the node
    and grown by how far the sprite's center is from the middle.

    Args:
        frustum: The frustum, in world space.
        scene: The scene, updated.
        sprite: The sprite.

    Returns:
        Whether some of its bound is in view.

    Raises:
        Error: If the scene is stale or does not have the node.
    """
    var offset = sprite.center.distance_to(Vector2(0.5, 0.5))
    var bound = Sphere(Vector3(0, 0, 0), SPRITE_RADIUS + offset)
    bound.apply_matrix4(scene.world_matrix(sprite.node))
    return frustum.intersects_sphere(bound)


def _sphere_in_view(
    frustum: Frustum,
    scene: Scene,
    assets: Assets,
    geometry: GeometryId,
    node: NodeId,
) raises -> Bool:
    """Return True if any of a geometry's bounding sphere, carried by a
    node's world matrix, is in view.

    Args:
        frustum: The frustum, in world space.
        scene: The scene, updated.
        assets: Where the geometry lives.
        geometry: Which geometry.
        node: Where it is drawn.

    Returns:
        Whether some of the sphere is in view.

    Raises:
        Error: If the geometry is missing or has no positions, or the
            scene is stale.
    """
    var bound = assets.geometries.get(geometry).bounding_sphere()
    bound.apply_matrix4(scene.world_matrix(node))
    return frustum.intersects_sphere(bound)
