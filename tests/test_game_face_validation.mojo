# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Small asserted controls for the preserved facial correspondence boundary."""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import POSITION, BufferGeometry
from core.object3d import NodeId, Object3D
from core.scene import Scene
from core.user_data import user_data_of
from extensions.humanoid.rig.game_face import (
    GAME_FACE_KEY,
    GameFace,
    _attribute_hash,
    attach_game_face,
    bind_game_face,
    facial_correspondence,
)
from extensions.humanoid.skeleton.head.expression import (
    AA,
    FaceWeights,
    face_rig_shapes,
)
from loaders.json import parse_json
from materials.material import Color, Material, MaterialId
from std.math import inf
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


def _triangle() raises -> BufferGeometry:
    var geometry = BufferGeometry()
    geometry.set_attribute(
        String(POSITION), BufferAttribute([0, 0, 0, 1, 0, 0, 0, 1, 0], 3)
    )
    geometry.set_index([0, 1, 2])
    geometry.morph_relative = True
    for name in face_rig_shapes():
        geometry.add_morph_target(
            BufferAttribute(List[Float32](length=9, fill=0), 3),
            BufferAttribute(List[Float32](length=9, fill=0), 3),
            name=name,
        )
    return geometry^


def _holder(mut scene: Scene) raises -> NodeId:
    var head = Object3D()
    head.name = "head"
    var parent = scene.add(head^)
    return scene.attach(Object3D(), parent)


def _attach(mut scene: Scene, mut assets: Assets) raises -> GameFace:
    var holder = _holder(scene)
    var paint = assets.materials.add(Material(Color(255, 255, 255)))
    return attach_game_face(
        scene,
        assets,
        holder,
        [_triangle(), _triangle(), _triangle()],
        [paint, paint, paint],
    )


def _assert_rest(scene: Scene, face: GameFace) raises:
    for index in face.meshes:
        for weight in scene.meshes[index].morph_influences.weights:
            assert_equal(weight, 0)


def test_empty_attribute_hash_still_records_shape() raises:
    var value = UInt64(14695981039346656037)
    _attribute_hash(value, BufferAttribute([], 3))
    # Independent FNV-1a word arithmetic for count=0 then item_size=3.
    assert_equal(value, UInt64(590680769285548756))


def test_correspondence_checks_every_shape_dimension() raises:
    var original = _triangle()
    var fingerprint = facial_correspondence(original)
    assert_equal(facial_correspondence(original.clone()), fingerprint)
    for kind in range(13):
        var geometry = original.clone()
        var expected: String
        if kind == 0:
            geometry.set_attribute(String(POSITION), BufferAttribute([0, 0], 2))
            expected = "three components"
        elif kind == 1:
            geometry.set_attribute(String(POSITION), BufferAttribute([], 3))
            expected = "complete indexed topology"
        elif kind == 2:
            geometry.index.clear()
            expected = "complete indexed topology"
        elif kind == 3:
            geometry.index.append(0)
            expected = "complete indexed topology"
        elif kind == 4:
            geometry.morph_relative = False
            expected = "all relative targets"
        elif kind == 5:
            _ = geometry.morph_positions.pop()
            expected = "all relative targets"
        elif kind == 6:
            _ = geometry.morph_names.pop()
            expected = "target names"
        elif kind == 7:
            _ = geometry.morph_normals.pop()
            expected = "all normal targets"
        elif kind == 8:
            geometry.morph_names[0] = "unknown"
            expected = "target mapping"
        elif kind == 9:
            geometry.morph_positions[0] = BufferAttribute([0, 0, 0], 3)
            expected = "target topology"
        elif kind == 10:
            geometry.morph_positions[0] = BufferAttribute([0, 0, 0, 0, 0, 0], 2)
            expected = "target topology"
        elif kind == 11:
            geometry.morph_normals[0] = BufferAttribute([0, 0, 0], 3)
            expected = "normal topology"
        else:
            geometry.morph_normals[0] = BufferAttribute([0, 0, 0, 0, 0, 0], 2)
            expected = "normal topology"
        with assert_raises(contains=expected):
            _ = facial_correspondence(geometry)
    for index in [-1, 3]:
        var geometry = original.clone()
        geometry.index[0] = index
        with assert_raises(contains="index is out of range"):
            _ = facial_correspondence(geometry)
    var nonfinite = original.clone()
    nonfinite.morph_positions[0].set_component(0, 0, inf[DType.float32]())
    with assert_raises(contains="finite components"):
        _ = facial_correspondence(nonfinite)
    assert_equal(facial_correspondence(original), fingerprint)


def test_attach_checks_lists_and_head_before_mutation() raises:
    for kind in range(3):
        var scene = Scene()
        var assets = Assets()
        var holder = _holder(scene)
        var geometry: List[BufferGeometry] = [
            _triangle(),
            _triangle(),
            _triangle(),
        ]
        var paints: List[MaterialId] = [
            MaterialId(0),
            MaterialId(0),
            MaterialId(0),
        ]
        var expected = String("three geometries and paints")
        if kind == 0:
            _ = geometry.pop()
        elif kind == 1:
            _ = paints.pop()
        else:
            scene.node(scene.get(holder).parent).name = "other"
            expected = "directly below HEAD"
        with assert_raises(contains=expected):
            _ = attach_game_face(scene, assets, holder, geometry^, paints)
        assert_equal(scene.count(), 2)
        assert_equal(len(scene.meshes), 0)
        assert_equal(assets.geometries.count(), 0)


def test_binding_checks_sizes_indices_and_hierarchy() raises:
    var scene = Scene()
    var assets = Assets()
    var face = _attach(scene, assets)
    face.validate(scene, assets)
    for kind in range(4):
        var changed = face.copy()
        if kind == 0:
            _ = changed.meshes.pop()
        elif kind == 1:
            _ = changed._correspondence.pop()
        elif kind == 2:
            changed.meshes[0] = -1
        else:
            changed.meshes[0] = len(scene.meshes)
        var expected = (
            "three preserved meshes" if kind < 2 else "mesh is missing"
        )
        with assert_raises(contains=expected):
            changed.validate(scene, assets)
    var node = scene.meshes[face.meshes[0]].node
    scene.node(node).parent = scene.get(face.holder).parent
    with assert_raises(contains="HEAD offset"):
        face.validate(scene, assets)
    scene.node(node).parent = face.holder
    scene.node(node).matrix_auto_update = False
    face.validate(scene, assets)
    scene.node(node).matrix.elements[0] = 2
    with assert_raises(contains="HEAD offset"):
        face.validate(scene, assets)
    scene.node(node).matrix.elements[0] = 1
    scene.meshes[face.meshes[0]].morph_target_dictionary["jawOpen"] = 0
    with assert_raises(contains="dictionary changed"):
        face.validate(scene, assets)
    _assert_rest(scene, face)


def test_weights_refuse_transactionally_and_valid_weights_apply() raises:
    var scene = Scene()
    var assets = Assets()
    var face = _attach(scene, assets)
    for kind in range(4):
        var weights = FaceWeights()
        var expected = String("weights or mapping are invalid")
        if kind == 0:
            _ = weights.weights.pop()
            expected = "weight dimensions do not match"
        elif kind == 1:
            _ = weights.weights.pop()
            _ = weights.shapes.pop()
            expected = "complete weight mapping"
        elif kind == 2:
            weights.shapes[0] = "unknown"
        else:
            weights.weights[0] = inf[DType.float32]()
        with assert_raises(contains=expected):
            face.apply(scene, assets, weights)
        _assert_rest(scene, face)
    var weights = FaceWeights()
    weights.add_viseme(AA)
    face.apply(scene, assets, weights)
    for index in face.meshes:
        assert_equal(
            scene.meshes[index].morph_influence(
                scene.meshes[index].morph_target_dictionary["jawOpen"]
            ),
            weights.get("jawOpen"),
        )
        assert_true(weights.get("jawOpen") > 0)


def test_rebind_validates_each_revision_and_missing_or_duplicate_part() raises:
    var scene = Scene()
    var assets = Assets()
    var face = _attach(scene, assets)
    var saved = scene.get(face.holder).user_data.json(String(GAME_FACE_KEY))
    for key in ["recipe", "mapping", "timing"]:
        var doc = parse_json(saved)
        var record = user_data_of(doc, 0)
        record.set_string(key, "unsupported")
        scene.node(face.holder).user_data.set_json(
            String(GAME_FACE_KEY), record.to_json()
        )
        with assert_raises(contains="revision"):
            _ = bind_game_face(scene, assets, face.holder)
    scene.node(face.holder).user_data.set_json(String(GAME_FACE_KEY), saved)
    var rebound = bind_game_face(scene, assets, face.holder)
    assert_equal(rebound.meshes[0], face.meshes[0])
    var node = scene.meshes[face.meshes[0]].node
    scene.node(node).name = "missing"
    with assert_raises(contains="mesh is missing"):
        _ = bind_game_face(scene, assets, face.holder)
    scene.node(node).name = "game-face-0"
    var unrelated = scene.add(Object3D())
    scene.node(unrelated).name = "game-face-0"
    var extra = scene.meshes[face.meshes[0]]
    extra.node = unrelated
    scene.add_mesh(extra)
    _ = bind_game_face(scene, assets, face.holder)
    scene.node(unrelated).parent = face.holder
    with assert_raises(contains="Duplicate"):
        _ = bind_game_face(scene, assets, face.holder)

    scene.meshes.clear()
    with assert_raises(contains="mesh is missing"):
        _ = bind_game_face(scene, assets, face.holder)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
