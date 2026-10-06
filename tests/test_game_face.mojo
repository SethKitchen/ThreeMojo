# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Real game facial controls, HEAD transforms, refusal and glTF round trips."""

from core.assets import Assets
from core.buffer_geometry import POSITION, BufferGeometry
from core.deform import morphed_positions
from core.object3d import NodeId, Object3D, NO_PARENT
from core.scene import Scene
from extensions.humanoid.rig.game import add_game_humanoid, game_build_settings
from extensions.humanoid.rig.game_face import (
    GAME_FACE_KEY,
    bind_game_face,
    facial_correspondence,
)
from extensions.humanoid.rig.joints import HEAD
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.head.aligned_speech import (
    AlignedSpeech,
    TimedViseme,
    AudioSpeechPlayback,
)
from extensions.humanoid.skeleton.head.expression import (
    AA,
    PP,
    SILENT,
    FaceWeights,
)
from extensions.humanoid.skeleton.simplify import (
    simplify,
    fit_triangle_budget_result,
)
from std.testing import TestSuite, assert_equal, assert_true, assert_raises
from units.si import Length, FOOT, Duration, Angle, DEGREE
from exporters.gltf import GLB, write_gltf
from loaders.gltf import read_gltf
from math.vector3 import Vector3
from extensions.humanoid.skeleton.head.skin.scan import scan_model, place
from extensions.humanoid.skeleton.head.frame import head_muscle_dimensions
from tests.test_scratch import TestScratch, temporary_path


def _lip_landmarks(geometry: BufferGeometry) raises -> List[Int]:
    """Resolve pinned ICT outer-midline upper 5533 and lower 5517 vertices.

    These are opposing outer lip-rim vertices, not the deeper mouth socket
    boundary. The pinned asset SHA and the independent binary probe are
    recorded in the validation evidence. They must still match the mesh.
    """
    var dims = head_muscle_dimensions(HumanoidSpec(Length(6, FOOT), MALE))
    var model = scan_model()
    var neutral = place(dims.head, model, 5534)
    ref points = geometry.attribute_view(String(POSITION))
    var result = List[Int]()
    for source in [5533, 5517]:
        var nearest = -1
        var distance = Float32(1)
        for v in range(points.count()):
            var gap = (points.vector3(v) - neutral[source]).length()
            if gap < distance:
                nearest = v
                distance = gap
        assert_true(distance < 1e-5)
        result.append(nearest)
    assert_true(result[0] != result[1])
    return result^


def test_real_game_face_follows_clock_head_and_glb() raises:
    var scene = Scene()
    var assets = Assets()
    var parent = scene.add(Object3D())
    scene.node(parent).set_position(2, 0, 3)
    var person = add_game_humanoid(
        scene,
        assets,
        parent,
        HumanoidSpec(Length(6, FOOT), MALE),
        detail=8,
        hand_detail=8,
        hair_detail=8,
        facial_animation=True,
    )
    var face = person.face.value().copy()
    assert_equal(len(scene.skinned_meshes), 3)
    assert_equal(len(scene.meshes), 6)
    assert_equal(scene.get(face.holder).parent, person.bones[HEAD.value])
    var speech = AlignedSpeech(
        "synthetic-pa-v1",
        Duration(1),
        [
            TimedViseme(PP, Duration(0), Duration(0.125)),
            TimedViseme(AA, Duration(0.125), Duration(0.75)),
            TimedViseme(SILENT, Duration(0.75), Duration(1)),
        ],
        Duration(2),
    )
    face.store_alignment(scene, speech)
    var lips = _lip_landmarks(
        assets.geometries.get(scene.meshes[face.meshes[0]].geometry)
    )
    # Each actual mesh deforms at a sustained vowel, including lower teeth
    # and gums/tongue. Silence returns every vertex exactly to neutral.
    for at in [Float32(2.0625), 2.5, 2.875]:
        face.apply(scene, assets, speech.sample(Duration(at)))
        for part in range(3):
            var mesh = scene.meshes[face.meshes[part]]
            ref geometry = assets.geometries.get(mesh.geometry)
            ref rest = geometry.attribute_view(String(POSITION))
            var worn = morphed_positions(geometry, mesh.morph_influences)
            var move = Float32(0)
            var drop = Float32(0)
            for v in range(rest.count()):
                var delta = worn[v] - rest.vector3(v)
                move = max(move, delta.length())
                drop = max(drop, -delta.y)
            if part == 0:
                var neutral_gap = (
                    rest.vector3(lips[0]).y - rest.vector3(lips[1]).y
                )
                var visible_gap = worn[lips[0]].y - worn[lips[1]].y
                assert_true(neutral_gap > 0)
                if at == 2.0625:
                    assert_true(visible_gap <= 0)
                elif at == 2.5:
                    assert_true(visible_gap > neutral_gap + 0.01)
                else:
                    assert_equal(visible_gap, neutral_gap)
            if at == 2.5:
                assert_true(drop > 0.01)
            elif at == 2.875:
                assert_equal(move, 0)
            elif part == 0:
                # PP engages the real lip-press/roll targets with no jaw opening.
                assert_true(move > 0)
                assert_equal(
                    mesh.morph_influence(
                        mesh.morph_target_dictionary["jawOpen"]
                    ),
                    0,
                )
            else:
                assert_true(move < 0.001)
    face.apply(scene, assets, speech.sample(Duration(2.5)))
    scene.update()
    var skin_node = scene.meshes[face.meshes[0]].node
    ref geometry = assets.geometries.get(scene.meshes[face.meshes[0]].geometry)
    var local = geometry.attribute_view(String(POSITION)).vector3(0)
    var rest_world = scene.world_matrix(skin_node).transform_point(local)
    var expected_rest = scene.world_matrix(person.root).transform_point(local)
    assert_true((rest_world - expected_rest).length() < 1e-6)
    # The offset means head turning happens about HEAD, not pelvis origin.
    scene.node(person.bones[HEAD.value]).rotate_y(Angle(35, DEGREE))
    scene.update()
    var expected = scene.world_matrix(person.bones[HEAD.value]).transform_point(
        local - person.rig.at(HEAD)
    )
    var turned = scene.world_matrix(skin_node).transform_point(local)
    assert_true((turned - expected).length() < 1e-6)
    assert_true((turned - rest_world).length() > 0.001)
    var path = temporary_path("audio-face.glb")
    write_gltf(path, scene, assets, GLB)
    var loaded = Scene()
    var restored = Assets()
    # Shift node and mesh numbering to prove no pre-bake indices are reused.
    _ = loaded.add(Object3D())
    var model = read_gltf(path, loaded, restored)
    var holder = NO_PARENT
    for node in model.nodes:
        if node != NO_PARENT and loaded.get(node).user_data.has(
            String(GAME_FACE_KEY)
        ):
            assert_equal(holder, NO_PARENT)
            holder = node
    assert_true(holder != NO_PARENT)
    var binding = bind_game_face(loaded, restored, holder)
    assert_equal(
        binding.alignment(loaded).metadata().to_json(),
        speech.metadata().to_json(),
    )
    for part in range(3):
        var before = scene.meshes[face.meshes[part]]
        var after = loaded.meshes[binding.meshes[part]]
        ref a = assets.geometries.get(before.geometry)
        ref b = restored.geometries.get(after.geometry)
        assert_equal(facial_correspondence(a), facial_correspondence(b))
        for k in range(a.morph_count()):
            assert_equal(a.morph_names[k], b.morph_names[k])
            assert_equal(before.morph_influence(k), after.morph_influence(k))
    var player = AudioSpeechPlayback(binding.alignment(loaded))
    player.resume(Duration(2))
    for rate in [24, 60]:
        for frame in [0, rate // 2, rate]:
            var time = Duration(2 + Float32(frame) / Float32(rate))
            binding.apply(loaded, restored, player.sample(time))
            assert_equal(
                loaded.meshes[binding.meshes[0]].morph_influence(
                    loaded.meshes[binding.meshes[0]].morph_target_dictionary[
                        "jawOpen"
                    ]
                ),
                speech.sample(time).get("jawOpen"),
            )
    player.pause(Duration(2.5))
    binding.apply(loaded, restored, player.sample(Duration(9)))
    binding.apply(loaded, restored, player.seek(Duration(2.0625)))
    assert_equal(
        loaded.meshes[binding.meshes[0]].morph_influence(
            loaded.meshes[binding.meshes[0]].morph_target_dictionary["jawOpen"]
        ),
        0,
    )
    # Generic decimation must refuse before replacing any facial geometry.
    with assert_raises(contains="morph correspondence"):
        _ = simplify(
            restored.geometries.get(loaded.meshes[binding.meshes[0]].geometry),
            32,
        )
    with assert_raises(contains="morph correspondence"):
        _ = fit_triangle_budget_result(loaded, restored, 0, 1000)
    binding.validate(loaded, restored)
    # Live hierarchy and local-frame edits are rejected before changing weights.
    var saved_parent = loaded.get(holder).parent
    loaded.node(holder).parent = NodeId(0)
    with assert_raises(contains="HEAD"):
        binding.apply(loaded, restored, speech.sample(Duration(2.5)))
    loaded.node(holder).parent = saved_parent
    var saved_offset = loaded.get(holder).position
    loaded.node(holder).set_position(0, 0, 0)
    with assert_raises(contains="rest offset"):
        _ = bind_game_face(loaded, restored, holder)
    loaded.node(holder).position = saved_offset
    var facial_node = loaded.meshes[binding.meshes[0]].node
    loaded.node(facial_node).set_position(1, 0, 0)
    with assert_raises(contains="HEAD offset"):
        binding.apply(loaded, restored, speech.sample(Duration(2.5)))
    loaded.node(facial_node).set_position(0, 0, 0)
    binding.validate(loaded, restored)
    # A missing dictionary name refuses before any mesh influence changes.
    _ = loaded.meshes[binding.meshes[2]].morph_target_dictionary.pop("jawOpen")
    with assert_raises(contains="missing a named target"):
        binding.apply(loaded, restored, speech.sample(Duration(2.5)))
    # Position edits break correspondence even when counts and target names match.
    var changed = restored.geometries.get(
        loaded.meshes[binding.meshes[0]].geometry
    ).clone()
    changed.index[0] = changed.index[1]
    restored.geometries.replace(
        loaded.meshes[binding.meshes[0]].geometry, changed^
    )
    with assert_raises(contains="correspondence changed"):
        _ = bind_game_face(loaded, restored, holder)


def main() raises:
    with TestScratch():
        TestSuite.discover_tests[__functions_in_module()]().run()
