# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Scene helpers, from three.js `examples/jsm/utils/SceneUtils.js`, and
the forms of `computeMorphedAttributes` that take a mesh.

`create_meshes_from_instanced_mesh` turns each instance of an instanced
mesh into a mesh of its own under one group.
`create_meshes_from_multi_material_mesh` turns each group of a mesh that
wears a material list into a mesh of its own. `create_multi_material_object`
draws one geometry once for each of several materials. `sort_instanced_mesh`
reorders an instanced mesh's instances. `reduce_vertices` folds a function
over every vertex under a node, in world space.

## What is not here

three.js's `traverseGenerator` and its kin
are JavaScript generators over a tree; `Scene.descendants` and
`Scene.children` walk this scene's array instead.

## A scene is an array

A three.js group holds its children. Here a group is a node, and a
mesh names the node that places it; see `core.scene`. So each function
that makes objects adds nodes and meshes to a scene and returns the id of
the group's node. The group is added with no parent, as three.js returns
one that is not in a scene yet.
"""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION
from core.deform import morphed_positions, skin_carriers, skin_pose
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from geometries.attribute_utils import (
    MorphedAttributes,
    compute_morphed_attributes,
    merge_groups,
)
from materials.material import MaterialId
from core.geometry_store import GeometryId
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from objects.mesh import Mesh


def create_meshes_from_instanced_mesh(
    mut scene: Scene, index: Int
) raises -> NodeId:
    """Add a group of meshes, one for each instance of an instanced mesh,
    three.js's `createMeshesFromInstancedMesh`.

    The group copies the instanced mesh's node. Each mesh gets a node of
    its own under the group, placed by its instance's matrix taken apart,
    and draws the instanced mesh's geometry and material. The instance
    colors are not carried over, as in three.js. The node's children are
    not copied under the group; three.js's `copy` copies them.

    Args:
        scene: The scene, which the group and the meshes are added to.
        index: Which instanced mesh, as its place in
            `scene.instanced_meshes`.

    Returns:
        The group's node.

    Raises:
        Error: If there is no instanced mesh of that index, its node is
            not in the scene, or an instance's matrix has no extent along
            an axis.
    """
    if index < 0 or index >= len(scene.instanced_meshes):
        raise Error("No instanced mesh has that index")
    var instanced = scene.instanced_meshes[index].copy()
    var group = scene.get(instanced.node)
    group.parent = NO_PARENT
    var group_id = scene.add(group^)
    for instance in range(instanced.count()):
        var node = Object3D()
        instanced.matrices[instance].decompose(
            node.position, node.quaternion, node.scale
        )
        var id = scene.attach(node^, group_id)
        scene.add_mesh(Mesh(instanced.geometry, instanced.material, id))
    return group_id


def create_meshes_from_multi_material_mesh(
    mut scene: Scene, mut assets: Assets, index: Int
) raises -> NodeId:
    """Add a group of meshes, one for each material of a mesh that wears
    a material list, three.js's `createMeshesFromMultiMaterialMesh`.

    The geometry's groups are first sorted and joined by material, by
    `merge_groups` on a copy. Each joined group then becomes a geometry
    of its own, every attribute read through the index for the group's
    slots, so the new geometry has no index. It is drawn with the
    material the group's index names, at a node of its own under the
    group. The group copies the mesh's node. As in three.js, the new
    geometries carry no morph target and no group, and the node's
    children are not copied under the group.

    A group whose material index is past the end of the list gets a
    mesh with no material in three.js. It is refused here, because a
    mesh here must name a material.

    A mesh with one material is not split. Its own node is returned, as
    three.js warns and returns the mesh itself.

    Args:
        scene: The scene, which the group and the meshes are added to.
        assets: Where the mesh's geometry is, and where the new
            geometries are added.
        index: Which mesh, as its place in `scene.meshes`.

    Returns:
        The group's node, or the mesh's own node for a mesh with one
        material.

    Raises:
        Error: If there is no mesh of that index, its node or geometry is
            not there, a group reaches past the end of the index or names
            a material the list does not have, or an index entry points
            past the last vertex.
    """
    if index < 0 or index >= len(scene.meshes):
        raise Error("No mesh has that index")
    var mesh = scene.meshes[index]
    if not mesh.is_multi_material():
        return mesh.node
    var geometry = assets.geometries.get(mesh.geometry).clone()
    # Asked first, so a geometry without positions is refused here and
    # every part below has an attribute to read.
    _ = geometry.vertex_count()
    merge_groups(geometry)
    var parts = List[BufferGeometry]()
    var wears = List[MaterialId]()
    for group in geometry.groups:
        var worn = mesh.group_material(group.material_index)
        if not Bool(worn):
            raise Error("A group names a material the mesh does not have")
        var slots = List[Int]()
        for slot in range(group.start, group.start + group.count):
            slots.append(geometry.vertex_at(slot))
        var part = BufferGeometry()
        for attribute in range(len(geometry.names)):  # pragma: no branch
            part.set_attribute(
                geometry.names[attribute],
                geometry.values[attribute].gather(slots),
            )
        parts.append(part^)
        wears.append(worn.value())
    var copied = scene.get(mesh.node)
    copied.parent = NO_PARENT
    var group_id = scene.add(copied^)
    for part in range(len(parts)):
        var node = scene.attach(Object3D(), group_id)
        var id = assets.geometries.add(parts[part].clone())
        scene.add_mesh(Mesh(id, wears[part], node))
    return group_id


def create_multi_material_object(
    mut scene: Scene, geometry: GeometryId, materials: List[MaterialId]
) raises -> NodeId:
    """Add a group that draws one geometry once for each material,
    three.js's `createMultiMaterialObject`.

    Args:
        scene: The scene, which the group and the meshes are added to.
        geometry: The geometry every mesh draws.
        materials: One material for each mesh, in order.

    Returns:
        The group's node.

    Raises:
        Error: If an id is negative.
    """
    var group = scene.add(Object3D())
    for index in range(len(materials)):
        var node = scene.attach(Object3D(), group)
        scene.add_mesh(Mesh(geometry, materials[index], node))
    return group


def _sorted_order(keys: List[Float64]) -> List[Int]:
    """Return the instances in order of their keys, rising, equal keys in
    the order they came: JavaScript's stable `sort`."""
    var order = List[Int]()
    for item in range(len(keys)):
        var at = len(order)
        while at > 0 and keys[order[at - 1]] > keys[item]:
            at -= 1
        order.insert(at, item)
    return order^


def sort_instanced_mesh(
    mut scene: Scene, mut assets: Assets, index: Int, keys: List[Float64]
) raises:
    """Reorder an instanced mesh's instances, three.js's
    `sortInstancedMesh`.

    three.js takes a comparison function. This takes one key for each
    instance and sorts them rising, equal keys keeping their order, which
    is what three.js's stable sort gives a comparison of keys. The
    matrices, the colors and every attribute of the geometry that advances
    per instance move with their instance. As in three.js, only the first
    four numbers of such an attribute's item move.

    Args:
        scene: The scene that holds the instanced mesh.
        assets: The stores that hold its geometry.
        index: Which instanced mesh, as its place in
            `scene.instanced_meshes`.
        keys: One key for each instance.

    Raises:
        Error: If there is no instanced mesh of that index, there is not
            one key for each instance, or its geometry is not in the store.
    """
    if index < 0 or index >= len(scene.instanced_meshes):
        raise Error("No instanced mesh has that index")
    ref mesh = scene.instanced_meshes[index]
    if len(keys) != mesh.count():
        raise Error("Sorting instances needs one key for each instance")
    var id = mesh.geometry.value
    if id >= assets.geometries.count():
        raise Error("An instanced mesh must name a stored geometry")
    var order = _sorted_order(keys)
    var matrices = mesh.matrices.copy()
    var colors = mesh.colors.copy()
    for i in range(len(order)):
        mesh.matrices[i] = matrices[order[i]]
        if len(colors) > 0:
            mesh.colors[i] = colors[order[i]]
    ref geometry = assets.geometries.geometries[id]
    for slot in range(len(geometry.values)):
        ref attribute = geometry.values[slot]
        if not attribute.is_instanced():
            continue
        var reference = attribute.clone()
        for i in range(len(order)):
            # An item size is positive, so this runs.
            for axis in range(min(attribute.item_size, 4)):  # pragma: no branch
                attribute.set_component(
                    i, axis, reference.component(order[i], axis)
                )


def _placed(
    scene: Scene, positions: List[Vector3], node: NodeId
) raises -> List[Vector3]:
    """Return points carried by a node's world matrix."""
    var world = scene.world_matrix(node)
    var out = List[Vector3](capacity=len(positions))
    for index in range(len(positions)):
        out.append(world.transform_point(positions[index]))
    return out^


def _base(geometry: BufferGeometry) raises -> List[Vector3]:
    """Return a geometry's positions as they are stored."""
    ref positions = geometry.attribute_view(String(POSITION))
    var out = List[Vector3](capacity=positions.count())
    for vertex in range(positions.count()):
        out.append(positions.vector3(vertex))
    return out^


def node_vertices(
    scene: Scene, assets: Assets, node: NodeId
) raises -> List[Vector3]:
    """Return the vertices of everything a node draws, as three.js's
    `reduceVertices` visits one object.

    A mesh's vertices wear its morph targets, three.js's
    `getVertexPosition`, and are carried to world space. A skinned mesh's
    are carried by its bones and not by the node, as in three.js, which
    skips the world matrix for one. An instanced mesh's are placed by the
    node and not by the instances, and a line's and points' by the node.
    A node that draws more than one thing gives them in that order.

    Args:
        scene: The scene, updated.
        assets: The stores that hold the geometries.
        node: The node.

    Returns:
        The vertices, in world space except for a skinned mesh.

    Raises:
        Error: If the scene is stale, or a geometry is not in the store or
            has no positions.
    """
    var out = List[Vector3]()
    for index in range(len(scene.meshes)):
        ref mesh = scene.meshes[index]
        if mesh.node == node:
            ref geometry = assets.geometries.get(mesh.geometry)
            out.extend(
                _placed(
                    scene,
                    morphed_positions(geometry, mesh.morph_influences),
                    node,
                )
            )
    for index in range(len(scene.skinned_meshes)):
        ref skinned = scene.skinned_meshes[index]
        if skinned.node == node:
            ref geometry = assets.geometries.get(skinned.geometry)
            var moved = morphed_positions(geometry, skinned.morph_influences)
            var carriers = skin_carriers(
                geometry, skin_pose(scene, index), len(moved)
            )
            for vertex in range(len(moved)):
                out.append(carriers[vertex].transform_point(moved[vertex]))
    for index in range(len(scene.instanced_meshes)):
        ref instanced = scene.instanced_meshes[index]
        if instanced.node == node:
            ref geometry = assets.geometries.get(instanced.geometry)
            out.extend(_placed(scene, _base(geometry), node))
    for index in range(len(scene.lines)):
        ref line = scene.lines[index]
        if line.node == node:
            ref geometry = assets.geometries.get(line.geometry)
            out.extend(_placed(scene, _base(geometry), node))
    for index in range(len(scene.points)):
        ref points = scene.points[index]
        if points.node == node:
            ref geometry = assets.geometries.get(points.geometry)
            out.extend(_placed(scene, _base(geometry), node))
    return out^


def visible_nodes(scene: Scene, root: NodeId) raises -> List[NodeId]:
    """Return a node and every node under it that is visible, depth
    first, three.js's `traverseVisible`: an invisible node hides the
    nodes under it.

    Args:
        scene: The scene.
        root: Where to start.

    Returns:
        The nodes, each before its children, the children in the order
        they were added.

    Raises:
        Error: If the root is not in the scene.
    """
    var out = List[NodeId]()
    var stack = List[NodeId]()
    stack.append(root)
    while len(stack) > 0:
        var node = stack.pop()
        if not scene.get(node).visible:
            continue
        out.append(node)
        var children = scene.children(node)
        for index in range(len(children) - 1, -1, -1):
            stack.append(children[index])
    return out^


def reduce_vertices[
    T: Copyable, //, func: def(var T, Vector3) thin -> T
](scene: Scene, assets: Assets, root: NodeId, initial: T) raises -> T:
    """Fold a function over every vertex drawn under a node, three.js's
    `reduceVertices`.

    The nodes are visited as `visible_nodes` gives them, and the vertices
    of each as `node_vertices` gives them. three.js updates the world
    matrices first; here the scene must be current, and `Scene.update`
    makes it so.

    Parameters:
        T: The type of the value folded.
        func: The function: the value so far and a vertex, to the next
            value.

    Args:
        scene: The scene, updated.
        assets: The stores that hold the geometries.
        root: Where to start.
        initial: The value to start from.

    Returns:
        The value after the last vertex.

    Raises:
        Error: If the scene is stale, the root is not in it, or a geometry
            is not in the store or has no positions.
    """
    # Every vertex first, then the fold: the value is not held while
    # anything can raise.
    var vertices = List[Vector3]()
    var nodes = visible_nodes(scene, root)
    for index in range(len(nodes)):
        vertices.extend(node_vertices(scene, assets, nodes[index]))
    var value = initial.copy()
    for vertex in range(len(vertices)):
        value = func(value^, vertices[vertex])
    return value^


def compute_mesh_morphed_attributes(
    assets: Assets, mesh: Mesh
) raises -> MorphedAttributes:
    """Return a mesh's positions and normals with its morph targets worn,
    three.js's `computeMorphedAttributes` for a `Mesh`.

    Args:
        assets: The stores that hold the mesh's geometry.
        mesh: The mesh.

    Returns:
        See `geometries.attribute_utils.compute_morphed_attributes`.

    Raises:
        Error: If the geometry is not in the store, or it cannot be worn.
    """
    return compute_morphed_attributes(
        assets.geometries.get(mesh.geometry), mesh.morph_influences
    )


def compute_skinned_morphed_attributes(
    scene: Scene, assets: Assets, index: Int
) raises -> MorphedAttributes:
    """Return a skinned mesh's positions and normals with its morph
    targets worn and its bones' carrying applied, three.js's
    `computeMorphedAttributes` for a `SkinnedMesh`.

    Args:
        scene: The scene, updated.
        assets: The stores that hold the mesh's geometry.
        index: Which skinned mesh, as its place in
            `scene.skinned_meshes`.

    Returns:
        See `geometries.attribute_utils.compute_morphed_attributes`.

    Raises:
        Error: If there is no such skinned mesh, the scene is stale, the
            geometry is not in the store or cannot be worn or carried.
    """
    var pose = skin_pose(scene, index)
    ref skinned = scene.skinned_meshes[index]
    ref geometry = assets.geometries.get(skinned.geometry)
    var carriers = skin_carriers(geometry, pose, geometry.vertex_count())
    return compute_morphed_attributes(
        geometry, skinned.morph_influences, carriers
    )
