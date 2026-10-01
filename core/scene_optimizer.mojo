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

**What counts as the same.** Material keys include every rendering field
except RGB, which is supplied per instance. Float fields use their exact
bits. Geometry equality compares every attribute, including integer
storage and interleaved values, and the index.

**Supported inputs.** Only static plain meshes with one material are
batched. A batch shares its parent, visibility, layers, render order,
culling, and shadow settings. Meshes with children, co-located objects,
user data, morphs, custom shadow materials, instanced attributes, or a
restricted draw range stay in place. Gyroscopes, clipping groups, light
targets, LOD levels, and skeleton bones stay in place too. Nodes in `keep`
also stay in place.
Use `keep` for camera nodes and for nodes that animation or application
code must continue to address. Optimization captures each eligible mesh's
current local transform; later changes to that original node do not move
the batch instance. Later changes to the shared parent do.
`to_instancing_mesh` raises, as three.js's throws: it is not written
there either.
"""

from std.collections import Dict
from std.memory import bitcast
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
    ref laid = assets.textures.get(id)
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
    return (
        String(color.r)
        + ","
        + String(color.g)
        + ","
        + String(color.b)
        + ","
        + String(color.a)
    )


def material_signature(assets: Assets, material: Material) raises -> String:
    """Return the complete material state needed to share a batch.

    RGB is supplied per instance. All other fields participate. Float
    values use exact bits so formatting cannot merge distinct values.

    Args:
        assets: Where the textures are.
        material: The material.

    Returns:
        A text that two materials share exactly when they agree.

    Raises:
        Error: If a map names a texture the assets do not have.
    """
    var parts = List[String]()
    # RGB is supplied per instance. Every other field participates.
    parts.append(String(material.color.a))
    parts.append(_texture_key(assets, material.map))
    parts.append(String(material.side.value))
    parts.append(String(bitcast[DType.uint32](material.opacity)))
    parts.append(String(material.blending.value))
    parts.append(String(material.kind.value))
    parts.append(_color_key(material.emissive))
    parts.append(String(bitcast[DType.uint32](material.emissive_intensity)))
    parts.append(_texture_key(assets, material.emissive_map))
    parts.append(String(material.vertex_colors))
    parts.append(_texture_key(assets, material.alpha_map))
    parts.append(String(bitcast[DType.uint32](material.alpha_test)))
    parts.append(_texture_key(assets, material.matcap))
    parts.append(_texture_key(assets, material.gradient_map))
    parts.append(_color_key(material.specular))
    parts.append(String(bitcast[DType.uint32](material.shininess)))
    parts.append(String(material.wireframe))
    parts.append(String(bitcast[DType.uint32](material.dash_size.value)))
    parts.append(String(bitcast[DType.uint32](material.gap_size.value)))
    parts.append(String(bitcast[DType.uint32](material.dash_scale)))
    parts.append(String(bitcast[DType.uint32](material.dash_offset.value)))
    parts.append(String(bitcast[DType.uint32](material.line_width.size)))
    parts.append(String(material.line_width.world_units))
    parts.append(String(material.transparent))
    parts.append(String(bitcast[DType.uint32](material.point_size.pixels)))
    parts.append(String(material.size_attenuation))
    parts.append(String(bitcast[DType.uint32](material.rotation.value)))
    parts.append(String(material.env_map.value))
    parts.append(String(bitcast[DType.uint32](material.reflectivity)))
    parts.append(String(material.combine.value))
    parts.append(String(bitcast[DType.uint32](material.roughness)))
    parts.append(String(bitcast[DType.uint32](material.metalness)))
    parts.append(_texture_key(assets, material.roughness_map))
    parts.append(_texture_key(assets, material.metalness_map))
    parts.append(String(bitcast[DType.uint32](material.env_map_intensity)))
    parts.append(
        String(bitcast[DType.uint32](material.env_map_rotation.x.value))
    )
    parts.append(
        String(bitcast[DType.uint32](material.env_map_rotation.y.value))
    )
    parts.append(
        String(bitcast[DType.uint32](material.env_map_rotation.z.value))
    )
    parts.append(String(material.env_map_rotation.order.first))
    parts.append(String(material.env_map_rotation.order.second))
    parts.append(String(material.env_map_rotation.order.third))
    parts.append(String(bitcast[DType.uint32](material.refraction_ratio)))
    parts.append(String(material.normal_map_type.value))
    parts.append(_texture_key(assets, material.normal_map))
    parts.append(String(bitcast[DType.uint32](material.normal_scale.x)))
    parts.append(String(bitcast[DType.uint32](material.normal_scale.y)))
    parts.append(_texture_key(assets, material.bump_map))
    parts.append(String(bitcast[DType.uint32](material.bump_scale)))
    parts.append(_texture_key(assets, material.ao_map))
    parts.append(String(bitcast[DType.uint32](material.ao_map_intensity)))
    parts.append(_texture_key(assets, material.light_map))
    parts.append(String(bitcast[DType.uint32](material.light_map_intensity)))
    parts.append(_texture_key(assets, material.specular_map))
    parts.append(String(material.flat_shading))
    parts.append(_texture_key(assets, material.displacement_map))
    parts.append(
        String(bitcast[DType.uint32](material.displacement_scale.value))
    )
    parts.append(
        String(bitcast[DType.uint32](material.displacement_bias.value))
    )
    parts.append(String(bitcast[DType.uint32](material.ior)))
    parts.append(_color_key(material.specular_color))
    parts.append(String(bitcast[DType.uint32](material.specular_intensity)))
    parts.append(String(bitcast[DType.uint32](material.clearcoat)))
    parts.append(String(bitcast[DType.uint32](material.clearcoat_roughness)))
    parts.append(_texture_key(assets, material.specular_intensity_map))
    parts.append(_texture_key(assets, material.specular_color_map))
    parts.append(_texture_key(assets, material.clearcoat_map))
    parts.append(_texture_key(assets, material.clearcoat_roughness_map))
    parts.append(_texture_key(assets, material.clearcoat_normal_map))
    parts.append(
        String(bitcast[DType.uint32](material.clearcoat_normal_scale.x))
    )
    parts.append(
        String(bitcast[DType.uint32](material.clearcoat_normal_scale.y))
    )
    parts.append(String(bitcast[DType.uint32](material.transmission)))
    parts.append(_texture_key(assets, material.transmission_map))
    parts.append(String(bitcast[DType.uint32](material.thickness.value)))
    parts.append(_texture_key(assets, material.thickness_map))
    parts.append(_color_key(material.attenuation_color))
    parts.append(
        String(bitcast[DType.uint32](material.attenuation_distance.value))
    )
    parts.append(String(bitcast[DType.uint32](material.dispersion)))
    parts.append(String(bitcast[DType.uint32](material.sheen)))
    parts.append(_color_key(material.sheen_color))
    parts.append(_texture_key(assets, material.sheen_color_map))
    parts.append(String(bitcast[DType.uint32](material.sheen_roughness)))
    parts.append(_texture_key(assets, material.sheen_roughness_map))
    parts.append(String(bitcast[DType.uint32](material.iridescence)))
    parts.append(String(bitcast[DType.uint32](material.iridescence_ior)))
    parts.append(
        String(
            bitcast[DType.uint32](material.iridescence_thickness_minimum.value)
        )
    )
    parts.append(
        String(
            bitcast[DType.uint32](material.iridescence_thickness_maximum.value)
        )
    )
    parts.append(_texture_key(assets, material.iridescence_map))
    parts.append(_texture_key(assets, material.iridescence_thickness_map))
    parts.append(String(bitcast[DType.uint32](material.anisotropy)))
    parts.append(
        String(bitcast[DType.uint32](material.anisotropy_rotation.value))
    )
    parts.append(_texture_key(assets, material.anisotropy_map))
    parts.append(String(material.nodes.value))
    parts.append(_texture_key(assets, material.scattering.map))
    parts.append(_color_key(material.scattering.color))
    parts.append(String(bitcast[DType.uint32](material.scattering.distortion)))
    parts.append(String(bitcast[DType.uint32](material.scattering.ambient)))
    parts.append(String(bitcast[DType.uint32](material.scattering.attenuation)))
    parts.append(String(bitcast[DType.uint32](material.scattering.power)))
    parts.append(String(bitcast[DType.uint32](material.scattering.scale)))
    parts.append(String(material.lights.bits))
    # Clipping storage is a fixed, nonempty SIMD, even with no active planes.
    for lane in range(len(material._clip_planes)):  # pragma: no branch
        parts.append(String(bitcast[DType.uint32](material._clip_planes[lane])))
    parts.append(String(material.clip_plane_count))
    parts.append(String(material.clip_intersection))
    parts.append(String(material.clip_shadows))
    parts.append(String(material.depth_test))
    parts.append(String(material.depth_write))
    parts.append(String(material.depth_func.value))
    parts.append(String(material.color_write))
    parts.append(String(material.polygon_offset))
    parts.append(String(bitcast[DType.uint32](material.polygon_offset_factor)))
    parts.append(String(bitcast[DType.uint32](material.polygon_offset_units)))
    parts.append(String(material.stencil_write))
    parts.append(String(material.stencil_write_mask))
    parts.append(String(material.stencil_func.value))
    parts.append(String(material.stencil_ref))
    parts.append(String(material.stencil_func_mask))
    parts.append(String(material.stencil_fail.value))
    parts.append(String(material.stencil_z_fail.value))
    parts.append(String(material.stencil_z_pass.value))
    parts.append(String(material.depth_packing.value))
    parts.append(String(bitcast[DType.uint32](material.reference_position.x)))
    parts.append(String(bitcast[DType.uint32](material.reference_position.y)))
    parts.append(String(bitcast[DType.uint32](material.reference_position.z)))
    parts.append(String(bitcast[DType.uint32](material.near_distance.value)))
    parts.append(String(bitcast[DType.uint32](material.far_distance.value)))
    parts.append(String(material.fog))
    parts.append(String(material.visible))
    parts.append(String(material.allow_override))
    parts.append(
        String(
            material.shadow_side.value().value if material.shadow_side else -1
        )
    )
    parts.append(String(material.dithering))
    parts.append(String(material.tone_mapped))
    parts.append(String(material.alpha_hash))
    parts.append(String(material.alpha_to_coverage))
    parts.append(String(material.premultiplied_alpha))
    parts.append(_color_key(material.blend_color))
    parts.append(String(bitcast[DType.uint32](material.blend_alpha)))
    parts.append(String(material.steps))
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
                + "_"
                + String(attribute.component_type().value)
                + "_"
                + String(attribute.mesh_per_attribute())
            )
    return out^


def _same_geometry(one: BufferGeometry, two: BufferGeometry) raises -> Bool:
    """Return whether two geometries are one to three.js's hash: the same
    index, positions and attributes."""
    if one.index != two.index:
        return False
    if attributes_signature(one) != attributes_signature(two):
        return False
    for slot in range(len(one.names)):
        ref first = one.values[slot]
        ref second = two.attribute_view(one.names[slot])
        if first.is_integer():
            if first.stored_values() != second.stored_values():
                return False
        elif first.packed() != second.packed():
            return False
    return True


def _carries(scene: Scene, node: NodeId, except_mesh: Int = -1) -> Bool:
    """Return whether anything the scene holds rides a node."""
    for at in range(len(scene.meshes)):
        if at != except_mesh and scene.meshes[at].node == node:
            return True
    for at in range(len(scene.skinned_meshes)):
        if scene.skinned_meshes[at].node == node:
            return True
        for bone in scene.skinned_meshes[at].skeleton.bones:
            if bone.node == node:
                return True
    for at in range(len(scene.instanced_meshes)):
        if scene.instanced_meshes[at].node == node:
            return True
    for at in range(len(scene.batched_meshes)):
        if scene.batched_meshes[at].node == node:
            return True
    for at in range(len(scene.lights)):
        if scene.lights[at].node == node or scene.lights[at].target == node:
            return True
    for at in range(len(scene.lods)):
        if scene.lods[at].node == node:
            return True
        for level in scene.lods[at].levels:
            if level.object == node:
                return True
    for at in range(len(scene.lines)):
        if scene.lines[at].node == node:
            return True
    for at in range(len(scene.points)):
        if scene.points[at].node == node:
            return True
    for at in range(len(scene.gaussian_splats)):
        if scene.gaussian_splats[at][].node == node:
            return True
    for at in range(len(scene.sprites)):
        if scene.sprites[at].node == node:
            return True
    for at in range(len(scene.wide_lines)):
        if scene.wide_lines[at].node == node:
            return True
    for group in scene.clipping_groups:
        if group.node == node:
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
        var group_index = Dict[String, Int]()
        var by_node = Dict[Int, List[Int]]()
        for at in range(len(scene.meshes)):
            var node = scene.meshes[at].node.value
            if node not in by_node:
                by_node[node] = List[Int]()
            by_node[node].append(at)
        var unique = List[Int]()
        var order = scene.traverse()
        for step in range(len(order)):
            var node = order[step]
            if node.value not in by_node:
                continue
            # A bucket is inserted only when its first mesh is appended.
            for slot in range(len(by_node[node.value])):  # pragma: no branch
                var at = by_node[node.value][slot]
                ref mesh = scene.meshes[at]
                if len(mesh.materials) > 0:
                    continue
                ref geometry = assets.geometries.get(mesh.geometry)
                if not self._eligible(scene, assets, at):
                    continue
                var object = scene.get(node)
                var key = (
                    material_signature(
                        assets, assets.materials.get(mesh.material)
                    )
                    + "_"
                    + attributes_signature(geometry)
                    + "|"
                    + String(geometry.is_indexed())
                    + "|"
                    + String(object.parent.value)
                    + "|"
                    + String(object.visible)
                    + "|"
                    + String(object.layers.mask)
                    + "|"
                    + String(object.render_order)
                    + "|"
                    + String(mesh.frustum_culled)
                    + "|"
                    + String(mesh.cast_shadow)
                    + "|"
                    + String(mesh.receive_shadow)
                )
                if key not in group_index:
                    group_index[key] = len(groups)
                    groups.append(_Group(key))
                var found = group_index[key]
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

    def _eligible(
        self, scene: Scene, assets: Assets, index: Int
    ) raises -> Bool:
        """Keep dynamic state and nodes that carry other scene content."""
        ref mesh = scene.meshes[index]
        var kind = scene.get(mesh.node).object_type
        if kind != OBJECT3D_TYPE and kind != GROUP_TYPE:
            return False
        for kept in self.keep:
            if kept == mesh.node:
                return False
        if len(scene.children(mesh.node)) > 0 or _carries(
            scene, mesh.node, index
        ):
            return False
        if Bool(mesh.custom_depth_material) or Bool(
            mesh.custom_distance_material
        ):
            return False
        if scene.get(mesh.node).user_data.count() > 0:
            return False
        if len(mesh.morph_influences) > 0:
            return False
        ref geometry = assets.geometries.get(mesh.geometry)
        if not geometry.has_attribute(POSITION):
            return False
        if geometry.instanced or geometry.morph_count() > 0:
            return False
        if geometry.draw_range.start != 0 or Bool(geometry.draw_range.count):
            return False
        # POSITION guarantees that this attribute list is not empty.
        for slot in range(len(geometry.values)):  # pragma: no branch
            if geometry.values[slot].is_instanced():
                return False
        return True

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
        material.color = Color(255, 255, 255, material.color.a)
        var paint = assets.materials.add(material^)
        var parent = scene.get(first.node).parent
        var holder = Object3D()
        var source = scene.get(first.node)
        holder.name = source.name + "_batch"
        holder.visible = source.visible
        holder.layers = source.layers
        holder.render_order = source.render_order
        var node = scene.add(holder^)
        if parent != NO_PARENT:
            scene.add(node, parent=parent)
        scene.update()
        var batch = BatchedMesh(
            paint,
            node,
            frustum_culled=first.frustum_culled,
            per_object_frustum_culled=first.frustum_culled,
            cast_shadow=first.cast_shadow,
            receive_shadow=first.receive_shadow,
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
                and scene.get(child).user_data.count() == 0
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
