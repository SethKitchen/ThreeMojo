# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Meshes that share a material merged into batches, from three.js
`examples/jsm/utils/SceneOptimizer.js`.

`SceneOptimizer.to_batched_mesh` finds the meshes that could be drawn as
one: those whose materials agree in everything but their color, and whose
geometries have the same attributes. Each set of two or more becomes one
`BatchedMesh` beside the first mesh, with the first mesh's material in
white. Each mesh becomes one instance: its geometry, its place relative to
the batch, and its material's color. The meshes are taken out of the
scene, and every node left carrying nothing and holding nothing goes too.

**What counts as the same.** A material's signature is three.js's: its
kind, the flags and numbers three.js lists, each map and how it is laid,
and its emissive, attenuation and sheen colors. Two geometries are one
when their index, their positions and their attributes are the same,
which is what three.js's hash of them stands for.

**Where this differs.** three.js batches every object that is a mesh,
skinned and instanced ones and batches among them. Here only plain meshes
of one material are batched. A node a camera rides carries nothing the
scene knows of, so it is kept only when listed in `keep`.
`to_instancing_mesh` raises, as three.js's throws: it is not written
there either.
"""

from core.assets import Assets
from core.buffer_geometry import BufferGeometry, POSITION
from core.geometry_store import GeometryId
from core.object3d import GROUP_TYPE, NO_PARENT, NodeId, OBJECT3D_TYPE, Object3D
from core.scene import Scene
from materials.material import Material, MaterialId
from math.matrix4 import Matrix4
from objects.instanced_mesh import BatchedMesh
from render.framebuffer import Color
from render.texture_store import NO_TEXTURE, TextureId


@fieldwise_init
struct OptimizerStats(Copyable, Movable):
    """What an optimization did, three.js's debug statistics."""

    # The meshes taken into batches and the meshes left alone.
    var original_meshes: Int
    var batched_meshes: Int
    var single_meshes: Int
    # The batches and the meshes left alone: one draw each.
    var draw_calls: Int
    var unique_geometries: Int


struct _Group(Movable):
    """The meshes of one signature, three.js's batch group."""

    var key: String
    var meshes: List[Int]
    # The distinct geometries, as the first mesh that draws each.
    var geometries: List[Int]

    def __init__(out self, key: String):
        self.key = key
        self.meshes = List[Int]()
        self.geometries = List[Int]()


def _texture_key(assets: Assets, id: TextureId) raises -> String:
    """Return three.js's key of a map: which texture and how it is laid."""
    if id == NO_TEXTURE:
        return "0"
    ref laid = assets.textures.textures[id.value]
    return (
        String(id.value)
        + "_"
        + String(laid.offset.x)
        + "_"
        + String(laid.offset.y)
        + "_"
        + String(laid.repeat.x)
        + "_"
        + String(laid.repeat.y)
        + "_"
        + String(laid.rotation.value)
    )


def _color_key(color: Color) -> String:
    """Return a color as three.js's `getHexString` spells it."""
    return String(color.r) + "," + String(color.g) + "," + String(color.b)


def material_signature(assets: Assets, material: Material) raises -> String:
    """Return what two materials must share to be drawn as one, three.js's
    `_getMaterialPropertiesHash`: everything it lists, and not the color.

    Args:
        assets: Where the textures are.
        material: The material.

    Returns:
        A text that two materials share exactly when they agree.

    Raises:
        Error: If a map names a texture the assets do not have.
    """
    var parts = List[String]()
    parts.append(String(material.kind))
    for flag in [  # pragma: no branch
        material.transparent,
        material.alpha_to_coverage,
        material.vertex_colors,
        material.visible,
        material.wireframe,
        material.flat_shading,
        material.premultiplied_alpha,
        material.dithering,
        material.tone_mapped,
        material.depth_test,
        material.depth_write,
    ]:
        parts.append(String(flag))
    for number in [  # pragma: no branch
        material.opacity,
        material.alpha_test,
        material.metalness,
        material.roughness,
        material.clearcoat,
        material.clearcoat_roughness,
        material.sheen,
        material.sheen_roughness,
        material.transmission,
        material.ior,
        material.iridescence,
        material.iridescence_ior,
        material.reflectivity,
    ]:
        parts.append(String(number))
    parts.append(String(material.side))
    parts.append(String(material.blending))
    parts.append(String(material.thickness.value))
    parts.append(String(material.attenuation_distance.value))
    parts.append(String(material.iridescence_thickness_minimum.value))
    parts.append(String(material.iridescence_thickness_maximum.value))
    for map in [  # pragma: no branch
        material.map,
        material.alpha_map,
        material.ao_map,
        material.bump_map,
        material.displacement_map,
        material.emissive_map,
        material.light_map,
        material.metalness_map,
        material.normal_map,
        material.roughness_map,
    ]:
        parts.append(_texture_key(assets, map))
    parts.append(String(material.env_map.value))
    parts.append(_color_key(material.emissive))
    parts.append(_color_key(material.attenuation_color))
    parts.append(_color_key(material.sheen_color))
    var out = String()
    for at in range(len(parts)):  # pragma: no branch
        if at > 0:
            out += "|"
        out += parts[at]
    return out^


def attributes_signature(geometry: BufferGeometry) -> String:
    """Return the names of a geometry's attributes, sorted, each with its
    item size and whether it is normalized, three.js's
    `_getAttributesSignature`.

    Args:
        geometry: The geometry.

    Returns:
        The signature.
    """
    var names = geometry.names.copy()
    sort(names)
    var out = String()
    for at in range(len(names)):  # pragma: no branch
        for index in range(len(geometry.names)):  # pragma: no branch
            if geometry.names[index] != names[at]:
                continue
            ref attribute = geometry.values[index]
            if at > 0:
                out += "|"
            out += (
                names[at]
                + "_"
                + String(attribute.item_size)
                + "_"
                + String(attribute.is_normalized())
            )
    return out^


def _same_geometry(one: BufferGeometry, two: BufferGeometry) raises -> Bool:
    """Return whether two geometries are one to three.js's hash: the same
    index, positions and attributes."""
    if one.index != two.index:
        return False
    if attributes_signature(one) != attributes_signature(two):
        return False
    return (
        one.attribute_view(String(POSITION)).data
        == two.attribute_view(String(POSITION)).data
    )


def _carries(scene: Scene, node: NodeId) -> Bool:
    """Return whether anything the scene holds rides a node."""
    for at in range(len(scene.meshes)):
        if scene.meshes[at].node == node:
            return True
    for at in range(len(scene.skinned_meshes)):
        if scene.skinned_meshes[at].node == node:
            return True
    for at in range(len(scene.instanced_meshes)):
        if scene.instanced_meshes[at].node == node:
            return True
    for at in range(len(scene.batched_meshes)):
        if scene.batched_meshes[at].node == node:
            return True
    for at in range(len(scene.lights)):
        if scene.lights[at].node == node:
            return True
    for at in range(len(scene.lods)):
        if scene.lods[at].node == node:
            return True
    for at in range(len(scene.lines)):
        if scene.lines[at].node == node:
            return True
    for at in range(len(scene.points)):
        if scene.points[at].node == node:
            return True
    for at in range(len(scene.sprites)):
        if scene.sprites[at].node == node:
            return True
    for at in range(len(scene.wide_lines)):
        if scene.wide_lines[at].node == node:
            return True
    return False


struct SceneOptimizer(Movable):
    """Merges a scene's meshes into batches, three.js's `SceneOptimizer`."""

    # Nodes kept whatever they carry: the nodes cameras ride, which the
    # scene does not know of.
    var keep: List[NodeId]

    def __init__(out self, var keep: List[NodeId] = List[NodeId]()):
        """Create an optimizer.

        Args:
            keep: Nodes never taken out as empty.
        """
        self.keep = keep^

    def to_batched_mesh(
        self, mut scene: Scene, mut assets: Assets
    ) raises -> OptimizerStats:
        """Merge the meshes that can be drawn as one, three.js's
        `toBatchedMesh`.

        Args:
            scene: The scene.
            assets: Where the geometries and the materials are, and where
                each batch's material goes.

        Returns:
            How many meshes were merged, into how many batches.

        Raises:
            Error: If a mesh names a material, a geometry or a texture the
                assets do not have, or the scene cannot be updated.
        """
        scene.update()
        var groups = List[_Group]()
        var unique = List[Int]()
        var order = scene.traverse()
        for step in range(len(order)):
            var node = order[step]
            for at in range(len(scene.meshes)):
                ref mesh = scene.meshes[at]
                if mesh.node != node or len(mesh.materials) > 0:
                    continue
                ref geometry = assets.geometries.get(mesh.geometry)
                var key = (
                    material_signature(
                        assets, assets.materials.get(mesh.material)
                    )
                    + "_"
                    + attributes_signature(geometry)
                )
                var found = -1
                for index in range(len(groups)):
                    if groups[index].key == key:
                        found = index
                if found < 0:
                    groups.append(_Group(key))
                    found = len(groups) - 1
                groups[found].meshes.append(at)
                if not _listed(scene, assets, groups[found].geometries, at):
                    groups[found].geometries.append(at)
                if not _listed(scene, assets, unique, at):
                    unique.append(at)
        var batched = 0
        var singles = 0
        var batches = 0
        for index in range(len(groups)):
            if len(groups[index].meshes) == 1:
                singles += 1
                continue
            self._batch(scene, assets, groups[index])
            batched += len(groups[index].meshes)
            batches += 1
        self.remove_empty_nodes(scene, NO_PARENT)
        scene.update()
        return OptimizerStats(
            batched + singles, batches, singles, batches + singles, len(unique)
        )

    def _batch(
        self, mut scene: Scene, mut assets: Assets, group: _Group
    ) raises:
        """Build one batch of a group's meshes, three.js's
        `_createBatchedMeshes`, and take the meshes out."""
        var first = scene.meshes[group.meshes[0]]
        var vertices = 0
        var indices = 0
        for at in range(len(group.geometries)):  # pragma: no branch
            ref geometry = assets.geometries.get(
                scene.meshes[group.geometries[at]].geometry
            )
            vertices += geometry.attribute_view(String(POSITION)).count()
            indices += len(geometry.index)
        var material = assets.materials.get(first.material)
        material.color = Color(255, 255, 255)
        var paint = assets.materials.add(material^)
        var parent = scene.get(first.node).parent
        var holder = Object3D()
        holder.name = scene.get(first.node).name + "_batch"
        var node = scene.add(holder^)
        if parent != NO_PARENT:
            scene.add(node, parent=parent)
        scene.update()
        var batch = BatchedMesh(
            paint,
            node,
            max_instance_count=len(group.meshes),
            max_vertex_count=vertices,
            max_index_count=indices,
        )
        var inverse = Matrix4()
        if parent != NO_PARENT:
            inverse = scene.world_matrix(parent)
            inverse.invert()
        var ids = List[GeometryId]()
        var sources = List[Int]()
        for at in range(len(group.meshes)):  # pragma: no branch
            var index = group.meshes[at]
            ref mesh = scene.meshes[index]
            var id = GeometryId(-1)
            for known in range(len(sources)):
                if _same_geometry(
                    assets.geometries.get(
                        scene.meshes[sources[known]].geometry
                    ),
                    assets.geometries.get(mesh.geometry),
                ):
                    id = ids[known]
            if id.value < 0:
                id = batch.add_geometry(
                    mesh.geometry, assets.geometries.get(mesh.geometry)
                )
                ids.append(id)
                sources.append(index)
            var instance = batch.add_instance(id)
            var place = Matrix4(copy=inverse)
            place.multiply(scene.world_matrix(mesh.node))
            batch.set_matrix_at(instance, place)
            batch.set_color_at(
                instance, assets.materials.get(mesh.material).color
            )
        for at in range(len(group.meshes)):  # pragma: no branch
            var gone = scene.meshes[group.meshes[at]].node
            scene.remove_from_parent(gone)
        scene.add_batched_mesh(batch^)

    def remove_empty_nodes(self, mut scene: Scene, node: NodeId) raises:
        """Take out every node below `node` that carries nothing and holds
        nothing once its own empty nodes are gone, three.js's
        `removeEmptyNodes`.

        Args:
            scene: The scene.
            node: Where to start, or `NO_PARENT` for the whole scene.

        Raises:
            Error: If a node is not in the scene.
        """
        var children = scene.children(node) if node != NO_PARENT else _roots(
            scene
        )
        for at in range(len(children)):
            var child = children[at]
            self.remove_empty_nodes(scene, child)
            var kind = scene.get(child).object_type
            var plain = kind == OBJECT3D_TYPE or kind == GROUP_TYPE
            var kept = False
            for index in range(len(self.keep)):
                kept = kept or self.keep[index] == child
            if (
                plain
                and not kept
                and not _carries(scene, child)
                and len(scene.children(child)) == 0
            ):
                scene.remove_from_parent(child)

    def to_instancing_mesh(self) raises:
        """Merge meshes into instanced meshes, three.js's
        `toInstancingMesh`, which three.js has not written.

        Raises:
            Error: Always, as three.js throws.
        """
        raise Error("InstancedMesh optimization not implemented yet")


def _roots(scene: Scene) raises -> List[NodeId]:
    """Return the nodes at the top of the scene, not removed."""
    var out = List[NodeId]()
    var order = scene.traverse()
    for at in range(len(order)):
        if scene.get(order[at]).parent == NO_PARENT:
            out.append(order[at])
    return out^


def _listed(
    scene: Scene, assets: Assets, meshes: List[Int], mesh: Int
) raises -> Bool:
    """Return whether a mesh's geometry is one that a listed mesh draws."""
    for at in range(len(meshes)):
        if _same_geometry(
            assets.geometries.get(scene.meshes[meshes[at]].geometry),
            assets.geometries.get(scene.meshes[mesh].geometry),
        ):
            return True
    return False
