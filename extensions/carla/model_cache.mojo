# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Store-scoped immutable CARLA model templates.

Geometry and image bytes belong to the destination stores. Templates keep
only their IDs, a private source scene, and material values. Each placement
gets fresh nodes and materials. No live instance serves as the template.
"""

from core.assets import Assets
from core.object3d import NO_PARENT, NodeId
from core.scene import Scene
from extensions.carla.assets import (
    AssetRegistry,
    MATERIAL_TAG,
    MODEL_ASSET,
    MODEL_ROLE,
    ModelPlacement,
    _model_pivot,
)
from loaders.gltf import read_gltf
from loaders.json import STRING
from materials.material import Material, MaterialId
from math.bounds import Box3
from math.vector3 import Vector3
from render.cube_texture_store import SCENE_ENVIRONMENT
from std.memory import ArcPointer


@fieldwise_init
struct _ModelTemplate(Movable):
    """An unplaced source graph, its material values, and its original box."""

    var scene: Scene
    var bounds: Box3
    var first_material: Int
    var materials: List[Material]
    var paint: List[MaterialId]
    var heads: List[MaterialId]
    var tails: List[MaterialId]


def _part(value: String) -> String:
    """Frame one key component so separators in a path cannot collide."""
    return String(value.byte_length()) + ":" + value


def _model_key(registry: AssetRegistry, index: Int) -> String:
    """Include every declared dependency's path, role, and pinned digest."""
    ref entry = registry.manifest.entries[index]
    var key = _part(registry.cache) + _part(entry.id)
    var f = 0
    while f < len(entry.files):
        ref file = entry.files[f]
        key += _part(String(file.role.value))
        key += _part(file.path) + _part(file.sha256)
        f += 1
    return key


def _read_template(
    registry: AssetRegistry, index: Int, mut assets: Assets
) raises -> _ModelTemplate:
    """Load into a private graph; publish no IDs until the template is valid."""
    var first_geometry = assets.geometries.count()
    var first_texture = assets.textures.count()
    var first_material = assets.materials.count()
    try:
        var source = Scene()
        ref entry = registry.manifest.entries[index]
        var model = read_gltf(
            registry.path(entry.file(MODEL_ROLE).value()),
            source,
            assets,
            registry.workers,
        )
        if model.skinned_mesh_count > 0 or model.instanced_mesh_count > 0:
            raise Error("A town model must hold only plain meshes")
        if model.mesh_count == 0:
            raise Error("The model " + entry.id + " has no mesh")
        source.update()
        var bounds = Box3.empty()
        var m = 0
        while m < len(source.meshes):
            var box = assets.geometries.get(
                source.meshes[m].geometry
            ).bounding_box()
            box.apply_matrix4(source.world_matrix(source.meshes[m].node))
            bounds.union(box)
            source.meshes[m].cast_shadow = True
            source.meshes[m].receive_shadow = True
            m += 1
        for id in model.materials:
            assets.materials.materials[id.value].env_map = SCENE_ENVIRONMENT
        var materials = List[Material]()
        m = first_material
        while m < assets.materials.count():
            materials.append(assets.materials.get(MaterialId(m)))
            m += 1
        var paint = List[MaterialId]()
        var heads = List[MaterialId]()
        var tails = List[MaterialId]()
        for m in range(len(model.materials)):
            ref extras = model.material_extras[m]
            if extras.has(MATERIAL_TAG) and extras.kind(MATERIAL_TAG) == STRING:
                var tag = extras.string(MATERIAL_TAG)
                if tag == "paint":
                    paint.append(model.materials[m])
                elif tag == "heads":
                    heads.append(model.materials[m])
                elif tag == "tails":
                    tails.append(model.materials[m])
        # These IDs are private offsets in the template. No caller has seen
        # them. Keep the material values, not a spare set in the live store.
        while assets.materials.count() > first_material:
            _ = assets.materials.materials.pop()
        return _ModelTemplate(
            source^, bounds, first_material, materials^, paint^, heads^, tails^
        )
    except error:
        # No graph or IDs escaped the private load. Roll back its resources
        # so a failed load and retry cannot accumulate unreachable bytes.
        while assets.materials.count() > first_material:
            _ = assets.materials.materials.pop()
        while assets.textures.count() > first_texture:
            _ = assets.textures.textures.pop()
        while assets.geometries.count() > first_geometry:
            _ = assets.geometries.geometries.pop()
        raise error


def _material_ids(source: List[MaterialId], offset: Int) -> List[MaterialId]:
    """Remap private template offsets into a fresh instance's materials."""
    var result = List[MaterialId]()
    for id in source:
        result.append(MaterialId(id.value + offset))
    return result^


struct ModelCache(Movable):
    """Cache immutable model resources for one geometry and texture owner.

    A move preserves the cache and store identities. These types cannot be
    copied. Replacing either store clears the templates before reuse. A
    retained token prevents a destroyed owner's address from matching a new
    owner. Shared geometry and texture contents must remain unchanged.
    """

    var _geometry_owner: ArcPointer[Int]
    var _texture_owner: ArcPointer[Int]
    var _keys: Dict[String, Int]
    var _models: List[_ModelTemplate]

    def __init__(out self):
        """Create an empty cache, not bound to any resource store."""
        self._geometry_owner = ArcPointer(Int(0))
        self._texture_owner = ArcPointer(Int(0))
        self._keys = Dict[String, Int]()
        self._models = List[_ModelTemplate]()

    def clear(mut self):
        """Forget templates before a cache file changes in place.

        Existing instances and store resources remain valid. The next
        placement reloads the asset. Use a new scene and stores to reclaim
        old instance resources. Changes to declared paths or digests select
        a new key automatically. Byte changes under unchanged declarations
        require this call, even when a declaration includes a digest. This
        cache does not verify file bytes against their declared digest.
        """
        self._keys.clear()
        self._models.clear()

    def place(
        mut self,
        registry: AssetRegistry,
        index: Int,
        mut scene: Scene,
        mut assets: Assets,
        parent: NodeId,
        fit: Vector3,
    ) raises -> ModelPlacement:
        """Place a model with shared geometry and images and fresh materials.

        Args:
            registry: The manifest and cache root.
            index: The model entry index.
            scene: The destination graph, independent of the cached graph.
            assets: The destination stores. Replacing a geometry or texture
                store invalidates this cache before any IDs can be reused.
            parent: The node that will own the new pivot.
            fit: The maximum length, height, and width in meters.

        Returns:
            The new pivot, mesh range, scale, and tagged material IDs.

        Raises:
            Error: If the index, entry, parent, or model is invalid, or the
                model cannot be loaded. No partial template is cached.
        """
        if index < 0 or index >= len(registry.manifest.entries):
            raise Error("No asset entry has that index")
        ref entry = registry.manifest.entries[index]
        if entry.kind != MODEL_ASSET:
            raise Error("The entry " + entry.id + " is not a model")
        if parent != NO_PARENT:
            _ = scene.get(parent)
        if (
            self._geometry_owner.ptr() != assets.geometries._cache_owner.ptr()
            or self._texture_owner.ptr() != assets.textures._cache_owner.ptr()
        ):
            self.clear()
            self._geometry_owner = assets.geometries._cache_owner
            self._texture_owner = assets.textures._cache_owner
        var key = _model_key(registry, index)
        if key not in self._keys:
            var model = _read_template(registry, index, assets)
            self._keys[key] = len(self._models)
            self._models.append(model^)
        ref template = self._models[self._keys[key]]
        var fitted = _model_pivot(template.bounds, entry.yaw, fit)
        var pivot = scene.attach(fitted[0].copy(), parent)
        var first_node = scene.count()
        var n = 0
        while n < template.scene.count():
            var node = template.scene.get(NodeId(n))
            node.parent = pivot if node.parent == NO_PARENT else NodeId(
                first_node + node.parent.value
            )
            _ = scene.add(node^)
            n += 1
        var offset = assets.materials.count() - template.first_material
        var m = 0
        while m < len(template.materials):
            _ = assets.materials.add(template.materials[m])
            m += 1
        var first_mesh = len(scene.meshes)
        m = 0
        while m < len(template.scene.meshes):
            var mesh = template.scene.meshes[m].copy()
            mesh.node = NodeId(first_node + mesh.node.value)
            mesh.material = MaterialId(mesh.material.value + offset)
            mesh.materials = _material_ids(mesh.materials, offset)
            scene.add_mesh(mesh^)
            m += 1
        for source in template.scene.lines:
            var line = source.copy()
            line.node = NodeId(first_node + line.node.value)
            line.material = MaterialId(line.material.value + offset)
            scene.add_line(line)
        for source in template.scene.points:
            var points = source.copy()
            points.node = NodeId(first_node + points.node.value)
            points.material = MaterialId(points.material.value + offset)
            scene.add_points(points)
        for source in template.scene.lights:
            var light = source.copy()
            light.node = NodeId(first_node + light.node.value)
            if light.target != NO_PARENT:
                light.target = NodeId(first_node + light.target.value)
            scene.add_light(light)
        scene.update()
        return ModelPlacement(
            pivot,
            first_mesh,
            len(template.scene.meshes),
            fitted[1],
            _material_ids(template.paint, offset),
            _material_ids(template.heads, offset),
            _material_ids(template.tails, offset),
        )
