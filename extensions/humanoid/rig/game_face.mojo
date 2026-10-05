# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Preserved game facial meshes and a validated glTF round-trip binding.

Face, enamel, and gums/tongue retain original vertex order at every body
LOD. Their pelvis-frame positions hang under HEAD with its rest translation
undone. This is visual morph animation, not a mechanical jaw simulation.
"""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import POSITION, BufferGeometry
from core.object3d import NodeId, Object3D
from core.scene import Scene
from core.user_data import UserData, user_data_of
from extensions.humanoid.skeleton.head.aligned_speech import (
    AlignedSpeech,
    SPEECH_MAPPING,
    SPEECH_TIMING,
    read_aligned_speech,
)
from extensions.humanoid.skeleton.head.expression import (
    FaceWeights,
    face_rig_shapes,
)
from loaders.json import parse_json
from materials.material import MaterialId
from objects.mesh import Mesh
from std.math import isfinite
from std.memory import bitcast

comptime GAME_FACE_KEY = "threemojo_game_face"
comptime GAME_FACE_RECIPE = "original-scan-head-relative-v1"
comptime GAME_FACE_ALIGNMENT_KEY = "threemojo_audio_alignment"


def _mix(mut value: UInt64, word: UInt64):
    """Mix an exact word into a noncryptographic correspondence fingerprint."""
    value = (value ^ word) * UInt64(1099511628211)


def _attribute_hash(mut value: UInt64, attribute: BufferAttribute) raises:
    """Hash finite Float32 components, preserving their exact order."""
    _mix(value, UInt64(attribute.count()))
    _mix(value, UInt64(attribute.item_size))
    for i in range(attribute.count()):
        for c in range(attribute.item_size):
            var x = attribute.component(i, c)
            if not isfinite(x):
                raise Error("Facial geometry must have finite components")
            _mix(value, UInt64(bitcast[DType.uint32](x)))


def facial_correspondence(geometry: BufferGeometry) raises -> String:
    """Fingerprint original topology, positions and every named morph offset.

    This detects accidental changes; it is not an authentication signature.
    It deliberately excludes material, UV and normal normalization changes.

    Args:
        geometry: An indexed, relative facial mesh with every required shape.

    Returns:
        The versioned mapping's 64-bit ordered-content fingerprint as text.

    Raises:
        Error: If topology, target names, dimensions or components are invalid.
    """
    _validate_shapes(geometry)
    var value = UInt64(14695981039346656037)
    _attribute_hash(value, geometry.attribute_view(String(POSITION)))
    _mix(value, UInt64(len(geometry.index)))
    var count = geometry.vertex_count()
    for index in geometry.index:
        if index < 0 or index >= count:
            raise Error("Facial topology index is out of range")
        _mix(value, UInt64(index))
    for i in range(geometry.morph_count()):
        for c in geometry.morph_names[i].as_bytes():
            _mix(value, UInt64(c))
        _attribute_hash(value, geometry.morph_positions[i])
    return String(value)


def _validate_shapes(geometry: BufferGeometry) raises:
    """Refuse topology or targets that no longer carry this visual mapping."""
    var shapes = face_rig_shapes()
    var count = geometry.vertex_count()
    if geometry.attribute_view(String(POSITION)).item_size != 3:
        raise Error("Facial positions must have three components")
    if count < 1 or not geometry.is_indexed() or len(geometry.index) % 3 != 0:
        raise Error("Facial correspondence requires complete indexed topology")
    if not geometry.morph_relative or geometry.morph_count() != len(shapes):
        raise Error("Facial correspondence requires all relative targets")
    if len(geometry.morph_names) != len(shapes):
        raise Error("Facial correspondence requires target names")
    if len(geometry.morph_normals) != len(shapes):
        raise Error("Facial correspondence requires all normal targets")
    for i in range(len(shapes)):
        if geometry.morph_names[i] != shapes[i]:
            raise Error("Facial correspondence target mapping has changed")
        ref positions = geometry.morph_positions[i]
        if positions.count() != count or positions.item_size != 3:
            raise Error("Facial correspondence target topology has changed")
        ref normals = geometry.morph_normals[i]
        if normals.count() != count or normals.item_size != 3:
            raise Error("Facial correspondence normal topology has changed")


def _identity_local(node: Object3D) raises -> Bool:
    """Require an unmodified child frame, including matrix-only edits."""
    var matrix = node.local_matrix() if node.matrix_auto_update else node.matrix
    for k in range(16):
        var expected = Float32(1) if k % 5 == 0 else Float32(0)
        if matrix.elements[k] != expected:
            return False
    return True


def _placement(scene: Scene, holder: NodeId, record: UserData) raises:
    """Keep the holder under HEAD with its authored inverse-rest translation."""
    var node = scene.get(holder)
    if scene.get(node.parent).name != "head":
        raise Error("Game facial offset must remain directly below HEAD")
    var matrix = node.local_matrix() if node.matrix_auto_update else node.matrix
    for k in range(16):
        var expected = Float32(1) if k % 5 == 0 else Float32(0)
        if k >= 12 and k <= 14:
            expected = Float32(record.number("offset_" + String(k - 12)))
        if matrix.elements[k] != expected:
            raise Error("Game facial HEAD rest offset has changed")


struct GameFace(Copyable, Movable):
    """Three preserved meshes attached to a game's HEAD bone.

    Use `bind_game_face` after loading a bake. Node and mesh indices are
    resolved from the loaded scene, never reused from the pre-bake scene.
    """

    var holder: NodeId
    var meshes: List[Int]
    var _correspondence: List[String]

    def __init__(
        out self,
        holder: NodeId,
        meshes: List[Int],
        correspondence: List[String],
    ):
        """Hold a binding; consumers validate its mesh and record boundaries.

        Args:
            holder: Pelvis-frame offset node directly below HEAD.
            meshes: Face, teeth, and gums/tongue indices in this scene.
            correspondence: Their original ordered-content fingerprints.
        """
        self.holder = holder
        self.meshes = meshes.copy()
        self._correspondence = correspondence.copy()

    def validate(self, scene: Scene, assets: Assets) raises:
        """Check the exact original correspondence before accepting a bake or edit.

        Args:
            scene: The current scene.
            assets: Its current geometry store.

        Raises:
            Error: If targets, topology, mesh placement or mapping changed.
        """
        if len(self.meshes) != 3 or len(self._correspondence) != 3:
            raise Error("A game face needs three preserved meshes")
        var doc = parse_json(
            scene.get(self.holder).user_data.json(String(GAME_FACE_KEY))
        )
        var record = user_data_of(doc, 0)
        _placement(scene, self.holder, record)
        for i in range(3):
            var k = self.meshes[i]
            if k < 0 or k >= len(scene.meshes):
                raise Error("Game facial mesh is missing")
            var mesh = scene.meshes[k]
            if scene.get(
                mesh.node
            ).parent != self.holder or not _identity_local(
                scene.get(mesh.node)
            ):
                raise Error(
                    "Game facial mesh must remain under its HEAD offset"
                )
            ref geometry = assets.geometries.get(mesh.geometry)
            if facial_correspondence(geometry) != self._correspondence[i]:
                raise Error(
                    "Game facial vertex correspondence changed; rebuild"
                )
            for target in range(len(geometry.morph_names)):
                var name = geometry.morph_names[target]
                if name not in mesh.morph_target_dictionary:
                    raise Error("Game facial mesh is missing a named target")
                if mesh.morph_target_dictionary[name] != target:
                    raise Error("Game facial mesh target dictionary changed")

    def apply(self, mut scene: Scene, assets: Assets, face: FaceWeights) raises:
        """Replace all three meshes' visual weights after correspondence validation.

        Args:
            scene: Scene to update.
            assets: Its geometry store.
            face: Fresh speech weights, optionally composed with expressions.

        Raises:
            Error: If the binding or weights are invalid. No mesh changes first.
        """
        self.validate(scene, assets)
        if len(face.shapes) != len(face.weights):
            raise Error("Facial weight dimensions do not match")
        var shapes = face_rig_shapes()
        if len(face.shapes) != len(shapes):
            raise Error("Game face requires the complete weight mapping")
        for i in range(len(shapes)):
            if face.shapes[i] != shapes[i] or not isfinite(face.weights[i]):
                raise Error("Game face weights or mapping are invalid")
        for k in self.meshes:
            face.apply(scene.meshes[k])

    def store_alignment(self, mut scene: Scene, speech: AlignedSpeech) raises:
        """Store caller alignment in the holder's glTF node extras.

        Args:
            scene: The scene to bake with the ordinary glTF exporter.
            speech: The caller's validated audio-aligned track.

        Raises:
            Error: If the holder is absent or metadata cannot be serialized.
        """
        scene.node(self.holder).user_data.set_json(
            String(GAME_FACE_ALIGNMENT_KEY), speech.metadata().to_json()
        )

    def alignment(self, scene: Scene) raises -> AlignedSpeech:
        """Read the caller's timing metadata after a glTF bake/load.

        Args:
            scene: The loaded or original scene.

        Returns:
            A validated track with the original audio label and time origin.

        Raises:
            Error: If alignment is absent or its revisions or times are invalid.
        """
        var doc = parse_json(
            scene.get(self.holder).user_data.json(
                String(GAME_FACE_ALIGNMENT_KEY)
            )
        )
        return read_aligned_speech(user_data_of(doc, 0))


def attach_game_face(
    mut scene: Scene,
    mut assets: Assets,
    holder: NodeId,
    var geometries: List[BufferGeometry],
    paints: List[MaterialId],
) raises -> GameFace:
    """Attach original face, teeth and gums/tongue at an existing HEAD offset.

    Args:
        scene: The game scene.
        assets: Its geometry and material store.
        holder: Pelvis-frame inverse-rest offset directly below HEAD.
        geometries: Original face, teeth, and gums/tongue in that order.
        paints: One material for each part.

    Returns:
        A binding and serialized correspondence metadata on the holder.

    Raises:
        Error: If meshes, targets, parent or list sizes are invalid.
    """
    if len(geometries) != 3 or len(paints) != 3:
        raise Error("A game face needs three geometries and paints")
    var head = scene.get(holder).parent
    if scene.get(head).name != "head":
        raise Error("Game facial offset must be directly below HEAD")
    var signatures = List[String]()
    for i in range(len(geometries)):
        signatures.append(facial_correspondence(geometries[i]))
    var record = UserData()
    record.set_string("recipe", String(GAME_FACE_RECIPE))
    record.set_string("mapping", String(SPEECH_MAPPING))
    record.set_string("timing", String(SPEECH_TIMING))
    var offset = scene.get(holder).position
    record.set_number("offset_0", Float64(offset.x))
    record.set_number("offset_1", Float64(offset.y))
    record.set_number("offset_2", Float64(offset.z))
    _placement(scene, holder, record)
    var meshes = List[Int]()
    for i in range(3):
        var node = Object3D()
        node.name = "game-face-" + String(i)
        var nid = scene.attach(node^, holder)
        var geometry = geometries.pop(0)
        var gid = assets.geometries.add(geometry^)
        var mesh = Mesh(gid, paints[i], nid)
        mesh.update_morph_targets(assets.geometries.get(gid))
        meshes.append(len(scene.meshes))
        scene.add_mesh(mesh)
        record.set_string("part_" + String(i), signatures[i])
    scene.node(holder).user_data.set_json(
        String(GAME_FACE_KEY), record.to_json()
    )
    return GameFace(holder, meshes, signatures)


def bind_game_face(
    scene: Scene, assets: Assets, holder: NodeId
) raises -> GameFace:
    """Resolve and validate a preserved game face after ordinary glTF loading.

    Find the holder among the loaded model's nodes by `GAME_FACE_KEY`.
    Pass that loaded NodeId; pre-bake scene indices are never portable.

    Args:
        scene: The loaded scene.
        assets: Its geometry store.
        holder: The loaded node carrying `GAME_FACE_KEY`.

    Returns:
        A fully validated binding, preserving the loaded morph weights.

    Raises:
        Error: If recipe, correspondence, hierarchy or mesh parts are missing.
    """
    var node = scene.get(holder)
    var doc = parse_json(node.user_data.json(String(GAME_FACE_KEY)))
    var record = user_data_of(doc, 0)
    if (
        record.string("recipe") != GAME_FACE_RECIPE
        or record.string("mapping") != SPEECH_MAPPING
        or record.string("timing") != SPEECH_TIMING
    ):
        raise Error(
            "Unsupported game facial recipe, mapping or timing revision"
        )
    _placement(scene, holder, record)
    var meshes = List[Int]()
    var signatures = List[String]()
    for part in range(3):
        var found = -1
        for k in range(len(scene.meshes)):
            var child = scene.get(scene.meshes[k].node)
            if child.parent == holder and child.name == "game-face-" + String(
                part
            ):
                if found >= 0:
                    raise Error("Duplicate game facial mesh")
                found = k
        if found < 0:
            raise Error("A preserved game facial mesh is missing")
        meshes.append(found)
        signatures.append(record.string("part_" + String(part)))
    var face = GameFace(holder, meshes, signatures)
    face.validate(scene, assets)
    return face^
