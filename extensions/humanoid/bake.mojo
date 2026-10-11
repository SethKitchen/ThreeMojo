# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Bind a humanoid bake's mesh bytes and mappings to its recipe.

A recipe says how a bake was made. It cannot detect an edit to the baked
meshes. `bake_content` adds a content record: exact fingerprints of every
mesh under the humanoid's root, the recipe digest, and one mapping record
per named mapping. `require_bake_content` checks a loaded bake against
its recipe, its mesh bytes and its mappings, and refuses any change.

The fingerprints are 64-bit FNV-1a hashes. They detect changed bytes;
they do not authenticate a file against a deliberate forgery.

This is not a three.js port. See Extensions.
"""

from core.assets import Assets
from core.object3d import NodeId
from core.scene import Scene
from core.user_data import UserData, user_data_of
from extensions.humanoid.fidelity import (
    FIDELITY_KEY,
    FINGERPRINT_ALGORITHM,
    GAME_RECIPE,
    geometry_fingerprint,
    json_fingerprint,
    require_bake_provenance,
)
from extensions.humanoid.mapping import (
    DENTAL_MAP,
    EXPRESSION_JAW_MAP,
    EYE_MAP,
    IDENTITY_MAP,
    LOD_MAP,
    SKIN_WEIGHT_MAP,
    MappingKind,
    mapping_label,
    mapping_record,
    named_mappings,
    require_mapping,
)
from extensions.humanoid.rig.joints import named_joints
from extensions.humanoid.skeleton.head.face_model import (
    EYE_SOCKETS,
    FACE_AND_HEAD,
    TEETH,
)
from extensions.humanoid.sources import FACE_ASSET
from loaders.json import parse_json

comptime CONTENT_KEY = "threemojo_humanoid_content"
comptime CONTENT_SCHEMA = 1


def _sorted(var items: List[String]) -> List[String]:
    """Return strings in ascending order."""
    sort(items)
    return items^


def _array(items: List[String]) -> String:
    """Join JSON values into one JSON array."""
    var text = String("[")
    for at in range(len(items)):
        if at > 0:
            text += ","
        text += items[at]
    return text + "]"


def _parsed(text: String) raises -> UserData:
    """Return one JSON object as user data."""
    var document = parse_json(text)
    return user_data_of(document, document.root())


def mesh_inventory(
    scene: Scene, assets: Assets, root: NodeId
) raises -> UserData:
    """Return exact fingerprints of every mesh under a humanoid's root.

    Skinned and rigid meshes are listed apart. Each list is sorted, so a
    loader that reorders meshes still yields the same inventory.

    Args:
        scene: The scene that holds the humanoid.
        assets: The store of its geometry.
        root: The humanoid's root node.

    Returns:
        `skinned` and `rigid` arrays of `geometry_fingerprint` records,
        and `topology`, a fingerprint of every mesh's topology.

    Raises:
        Error: If the root is not in the scene or a mesh is refused.
    """
    var nodes = scene.traverse(root)
    var skinned = List[String]()
    var rigid = List[String]()
    var shapes = List[String]()
    for index in range(len(scene.skinned_meshes)):
        ref mesh = scene.skinned_meshes[index]
        if mesh.node in nodes:
            var record = geometry_fingerprint(
                assets.geometries.get(mesh.geometry)
            )
            skinned.append(record.to_json())
            shapes.append(record.string("topology"))
    for index in range(len(scene.meshes)):
        ref mesh = scene.meshes[index]
        if mesh.node in nodes:
            var record = geometry_fingerprint(
                assets.geometries.get(mesh.geometry)
            )
            rigid.append(record.to_json())
            shapes.append(record.string("topology"))
    var inventory = UserData()
    inventory.set_json("skinned", _array(_sorted(skinned^)))
    inventory.set_json("rigid", _array(_sorted(rigid^)))
    inventory.set_string("topology", json_fingerprint(_array(_sorted(shapes^))))
    return inventory^


def _face_source(provenance: UserData) raises -> String:
    """Return the verified face model SHA-256, or an unverified marker."""
    var recipe = _parsed(provenance.json("recipe"))
    var sources = _parsed(recipe.json("converted_sources"))
    if not sources.has("assets"):
        return "unverified-face-model"
    var assets = _parsed(sources.json("assets"))
    if not assets.has(String(FACE_ASSET)):
        return "unverified-face-model"
    return _parsed(assets.json(String(FACE_ASSET))).string("sha256")


def _face_topology() -> String:
    """Return the scanned face part ranges that the face mappings index."""
    return (
        "ictf6:face_and_head="
        + String(FACE_AND_HEAD.first)
        + "-"
        + String(FACE_AND_HEAD.end)
        + ";eye_sockets="
        + String(EYE_SOCKETS.first)
        + "-"
        + String(EYE_SOCKETS.end)
        + ";teeth="
        + String(TEETH.first)
        + "-"
        + String(TEETH.end)
    )


def _rig_source() -> String:
    """Return the rig revision and joint count that skin weights index."""
    return String(GAME_RECIPE) + ":joints=" + String(len(named_joints()))


def _source(kind: MappingKind, face: String, lod_source: String) -> String:
    """Return the source fingerprint of one named mapping."""
    if kind == SKIN_WEIGHT_MAP:
        return _rig_source()
    if kind == LOD_MAP:
        return lod_source
    return face


def _topology(kind: MappingKind, inventory: UserData) raises -> String:
    """Return the topology fingerprint of one named mapping."""
    if kind == SKIN_WEIGHT_MAP or kind == LOD_MAP:
        return inventory.string("topology")
    return _face_topology()


def bake_content(
    scene: Scene,
    assets: Assets,
    root: NodeId,
    provenance: UserData,
    lod_source: String,
) raises -> UserData:
    """Return the content record of a humanoid's meshes and mappings.

    Args:
        scene: The scene that holds the humanoid.
        assets: The store of its geometry.
        root: The humanoid's root node.
        provenance: Its creation record from `humanoid_provenance`.
        lod_source: The fingerprint of the full-resolution topology that
            the level of detail was decimated from.

    Returns:
        The schema, the recipe digest, the mesh inventory, its content
        digest and one mapping record per named mapping.

    Raises:
        Error: If the root, a mesh or the provenance record is refused,
            or `lod_source` is empty.
    """
    var inventory = mesh_inventory(scene, assets, root)
    var face = _face_source(provenance)
    var mappings = UserData()
    for kind in named_mappings():  # pragma: no branch
        mappings.set_json(
            mapping_label(kind),
            mapping_record(
                kind,
                _source(kind, face, lod_source),
                _topology(kind, inventory),
            ).to_json(),
        )
    var record = UserData()
    record.set_number("schema_version", CONTENT_SCHEMA)
    record.set_string("fingerprint_algorithm", String(FINGERPRINT_ALGORITHM))
    record.set_string("recipe_digest", provenance.string("recipe_digest"))
    record.set_json("meshes", inventory.to_json())
    record.set_string("content_digest", json_fingerprint(inventory.to_json()))
    record.set_json("mappings", mappings.to_json())
    return record^


def require_bake_content(
    scene: Scene, assets: Assets, root: NodeId, expected: UserData
) raises:
    """Refuse a loaded humanoid whose recipe, meshes or mappings changed.

    The check first applies `require_bake_provenance` to the root's
    extras. It then fingerprints every mesh under the root again. Each
    mapping must match the expected sources and the loaded topology. The
    level-of-detail source is the stored fingerprint; the recipe binds
    it, and a rebuild with other settings changes it.

    Args:
        scene: The loaded scene.
        assets: The loaded geometry store.
        root: The node that carries the humanoid's extras.
        expected: The freshly built expected provenance record.

    Raises:
        Error: If the provenance is refused, the content record is
            missing or of another schema, a mesh changed, or a mapping is
            invalid or edited.
    """
    var extras = scene.get(root).user_data.copy()
    require_bake_provenance(extras, expected)
    if not extras.has(String(CONTENT_KEY)):
        raise Error("Humanoid bake has no content record; rebuild it")
    var stored = _parsed(extras.json(String(CONTENT_KEY)))
    if not stored.has("schema_version") or stored.json(
        "schema_version"
    ) != String(CONTENT_SCHEMA):
        raise Error("Humanoid bake content schema is unsupported; rebuild it")
    if stored.string("recipe_digest") != expected.string("recipe_digest"):
        raise Error("Humanoid bake content belongs to another recipe")
    var inventory = mesh_inventory(scene, assets, root)
    if stored.json("meshes") != inventory.to_json():
        raise Error("Humanoid bake mesh content changed; rebuild it")
    var mappings = _parsed(stored.json("mappings"))
    var face = _face_source(expected)
    var lod_source = String()
    for kind in named_mappings():  # pragma: no branch
        var label = mapping_label(kind)
        if not mappings.has(label):
            raise Error("Humanoid bake has no " + label + " mapping")
        var mapping = _parsed(mappings.json(label))
        if kind == LOD_MAP:
            lod_source = mapping.string("source_fingerprint")
        require_mapping(
            mapping,
            kind,
            _source(kind, face, lod_source),
            _topology(kind, inventory),
        )
    var rebuilt = bake_content(scene, assets, root, expected, lod_source)
    if stored.to_json() != rebuilt.to_json():
        raise Error("Humanoid bake content record was edited; rebuild it")
