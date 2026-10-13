# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Seal a humanoid bake's geometry into its provenance, and verify it.

A recipe record names how a bake was built. It cannot tell whether the
geometry in the file was edited after the build. This module adds a
geometry digest to the record when it writes the bake, and checks the
digest after a game loads the bake.

The digest covers the geometry as the glTF loader reads it, so the
export side and the load side hash the same values. The loader scales
skin weights to sum to one and drops attributes that glTF cannot carry.
The seal therefore reads its own export back before it hashes it.

    var record = humanoid_provenance(spec, settings, a, b, c)
    write_sealed_bake("out/humanoid.glb", scene, assets, record)
    var model = read_gltf("out/humanoid.glb", loaded, loaded_assets)
    require_sealed_bake(model.scene_extras, record, loaded, loaded_assets)

The digest is a 64-bit FNV-1a hash. It detects an accidental or a
careless edit. It does not authenticate a file that an editor rewrote
together with its digest.
"""

from animation.animation_clip import AnimationClip
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry
from core.scene import Scene
from core.user_data import UserData
from exporters.gltf import (
    GLB,
    GltfContainer,
    GltfExportOptions,
    export_gltf,
    write_gltf,
)
from extensions.humanoid.fidelity import (
    FIDELITY_KEY,
    FNV1A_OFFSET,
    UNSEALED_GEOMETRY,
    fingerprint_hex,
    fnv1a_step,
    require_bake_provenance,
    sealed_provenance,
    stored_provenance,
)
from loaders.gltf import load_gltf, split_glb
from std.memory import bitcast


struct _Digest(Movable):
    """A running 64-bit FNV-1a hash of little-endian words."""

    var hash: UInt64

    def __init__(out self):
        """Start at the FNV-1a offset basis."""
        self.hash = FNV1A_OFFSET

    def count(mut self, value: Int):
        """Add a count or an index as eight little-endian bytes."""
        var word = UInt64(value)
        for at in range(8):  # pragma: no branch
            self.hash = fnv1a_step(
                self.hash, UInt8((word >> type_of(word)(8 * at)) & 0xFF)
            )

    def number(mut self, value: Float32):
        """Add a float32 as its four little-endian bit-pattern bytes."""
        var word = bitcast[DType.uint32](value)
        for at in range(4):  # pragma: no branch
            self.hash = fnv1a_step(
                self.hash, UInt8((word >> type_of(word)(8 * at)) & 0xFF)
            )

    def text(mut self, value: String):
        """Add a string as its byte length and its UTF-8 bytes."""
        self.count(value.byte_length())
        for byte in value.as_bytes():
            self.hash = fnv1a_step(self.hash, byte)

    def attribute(mut self, attribute: BufferAttribute) raises:
        """Add an attribute's item size, count and every component."""
        self.count(attribute.item_size)
        self.count(attribute.count())
        for value in attribute.packed():
            self.number(value)

    def geometry(mut self, geometry: BufferGeometry) raises:
        """Add a geometry's groups, index, attributes and morph targets."""
        self.count(len(geometry.groups))
        for group in geometry.groups:
            self.count(group.start)
            self.count(group.count)
            self.count(group.material_index.value)
        self.count(len(geometry.index))
        for entry in geometry.index:
            self.count(entry)
        self.count(len(geometry.names))
        for at in range(len(geometry.names)):
            self.text(geometry.names[at])
            self.attribute(geometry.values[at])
        self.count(len(geometry.morph_positions))
        for target in geometry.morph_positions:
            self.attribute(target)
        self.count(len(geometry.morph_normals))
        for target in geometry.morph_normals:
            self.attribute(target)
        self.count(len(geometry.morph_colors))
        for target in geometry.morph_colors:
            self.attribute(target)


def bake_geometry_digest(scene: Scene, assets: Assets) raises -> String:
    """Return the geometry digest of every drawn mesh in a scene.

    The digest hashes, in this order, as little-endian words:

    1. The lengths of the scene's mesh, skinned mesh, instanced mesh,
       batched mesh, LOD, line and point lists.
    2. Each skinned mesh in list order: the name of each skeleton bone's
       node, then its geometry.
    3. Each mesh in list order: its geometry.

    A geometry adds its groups, its index, each attribute's name, item
    size, count and float32 bits, and each morph target. Counts and
    indices are eight bytes; floats are four. Materials, textures, node
    transforms, inverse bind matrices and animations are not covered.

    Args:
        scene: The scene that holds only the bake, as the loader read it.
        assets: The store of the scene's geometries.

    Returns:
        Sixteen lowercase hexadecimal digits.

    Raises:
        Error: If a mesh names a geometry or a bone names a node that the
            store or the scene does not hold.
    """
    var digest = _Digest()
    digest.count(len(scene.meshes))
    digest.count(len(scene.skinned_meshes))
    digest.count(len(scene.instanced_meshes))
    digest.count(len(scene.batched_meshes))
    digest.count(len(scene.lods))
    digest.count(len(scene.lines))
    digest.count(len(scene.points))
    for ref skinned in scene.skinned_meshes:
        digest.count(len(skinned.skeleton.bones))
        # `Skeleton` refuses to hold no bones.
        for bone in skinned.skeleton.bones:  # pragma: no branch
            digest.text(scene.get(bone.node).name)
        digest.geometry(assets.geometries.get(skinned.geometry))
    for mesh in scene.meshes:
        digest.geometry(assets.geometries.get(mesh.geometry))
    return fingerprint_hex(digest.hash)


def seal_bake_provenance(
    scene: Scene, assets: Assets, record: UserData
) raises -> UserData:
    """Return a record sealed with the digest of a scene's exported geometry.

    The scene is exported as a GLB and read back. The digest covers what
    the loader reads, which is what a game reads from the bake.

    Args:
        scene: The scene to bake.
        assets: Its geometries, materials and textures.
        record: The unsealed record, as `humanoid_provenance` returns it.

    Returns:
        The record with its `geometry_digest` set.

    Raises:
        Error: If `export_gltf` or `load_gltf` refuses the scene, or if
            `sealed_provenance` refuses the record.
    """
    var files = export_gltf(scene, assets, GLB)
    var parts = split_glb(files.document)
    var loaded = Scene()
    var loaded_assets = Assets()
    _ = load_gltf(parts[0], parts[1], "", loaded, loaded_assets)
    return sealed_provenance(
        record, bake_geometry_digest(loaded, loaded_assets)
    )


def write_sealed_bake(
    path: String,
    scene: Scene,
    assets: Assets,
    record: UserData,
    container: GltfContainer = GLB,
    animations: List[AnimationClip] = List[AnimationClip](),
    options: GltfExportOptions = GltfExportOptions(),
) raises:
    """Write a bake whose scene extras hold its sealed provenance.

    Args:
        path: The `.glb` or `.gltf` file.
        scene: The scene to bake.
        assets: Its geometries, materials and textures.
        record: The unsealed record, as `humanoid_provenance` returns it.
        container: `GLB`, `GLTF_EMBEDDED` or `GLTF_SEPARATE`.
        animations: The clips to write.
        options: The other export options. The sealed record replaces any
            scene extra under `FIDELITY_KEY`.

    Raises:
        Error: If `seal_bake_provenance` or `write_gltf` raises.
    """
    var sealed = seal_bake_provenance(scene, assets, record)
    var written = options.copy()
    written.scene_user_data.set_json(String(FIDELITY_KEY), sealed.to_json())
    write_gltf(
        path,
        scene,
        assets,
        container,
        animations=animations,
        options=written^,
    )


def require_bake_geometry(
    stored: UserData, scene: Scene, assets: Assets
) raises:
    """Refuse a loaded bake whose geometry does not match its digest.

    Call it on the scene the bake was loaded into, before you add meshes.

    Args:
        stored: The loaded scene extras.
        scene: The scene that the loader filled from the bake.
        assets: The store that the loader filled.

    Raises:
        Error: If `stored_provenance` refuses the record, if the record
            is unsealed, or if the loaded geometry has another digest.
    """
    var record = stored_provenance(stored)
    var digest = record.string("geometry_digest")
    if digest == String(UNSEALED_GEOMETRY):
        raise Error(
            "Humanoid bake geometry is unsealed and unverified; rebuild it"
        )
    if bake_geometry_digest(scene, assets) != digest:
        raise Error(
            "Humanoid bake geometry does not match its digest; rebuild it"
        )


def require_sealed_bake(
    stored: UserData, expected: UserData, scene: Scene, assets: Assets
) raises:
    """Refuse a loaded bake with a stale recipe or edited geometry.

    Args:
        stored: The loaded scene extras.
        expected: The freshly built expected record, sealed or unsealed.
        scene: The scene that the loader filled from the bake.
        assets: The store that the loader filled.

    Raises:
        Error: If `require_bake_provenance` or `require_bake_geometry`
            refuses the bake.
    """
    require_bake_provenance(stored, expected)
    require_bake_geometry(stored, scene, assets)
