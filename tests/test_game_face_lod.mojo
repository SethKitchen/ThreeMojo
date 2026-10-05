# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Strict facial LOD preserves original vertex and named-target correspondence."""

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


def _count(scene: Scene, assets: Assets) raises -> Int:
    """Count actual triangles across all body, hand, face, mouth, hair and eyes.
    """
    var total = 0
    for i in range(len(scene.meshes)):
        total += assets.geometries.get(
            scene.meshes[i].geometry
        ).triangle_count()
    for i in range(len(scene.skinned_meshes)):
        total += assets.geometries.get(
            scene.skinned_meshes[i].geometry
        ).triangle_count()
    return total


def test_lod_preserves_full_facial_geometry_and_respects_budget() raises:
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    var spec = HumanoidSpec(Length(6, FOOT), MALE)
    var full = add_game_humanoid(
        scene,
        assets,
        root,
        spec,
        detail=12,
        hand_detail=8,
        hair_detail=8,
        facial_animation=True,
    )
    var total = _count(scene, assets)
    var reserved = 0
    for i in range(len(scene.meshes)):
        # Hair is the first plain mesh; all others retain original topology.
        if i > 0:
            reserved += assets.geometries.get(
                scene.meshes[i].geometry
            ).triangle_count()
    # Both budgets used to fail because the hair exceeded its fixed share.
    # Other parts can safely shrink enough to honor the exact total.
    for allowance in [3000, 5000]:
        var lod_scene = Scene()
        var lod_assets = Assets()
        var lod_root = lod_scene.add(Object3D())
        var budget = reserved + allowance
        var lod = add_game_humanoid(
            lod_scene,
            lod_assets,
            lod_root,
            spec,
            budget,
            detail=12,
            hand_detail=8,
            hair_detail=8,
            facial_animation=True,
        )
        assert_true(_count(lod_scene, lod_assets) <= budget)
        assert_true(_count(lod_scene, lod_assets) < total)
        var full_face = full.face.value().copy()
        var lod_face = lod.face.value().copy()
        for part in range(3):
            assert_equal(
                facial_correspondence(
                    assets.geometries.get(
                        scene.meshes[full_face.meshes[part]].geometry
                    )
                ),
                facial_correspondence(
                    lod_assets.geometries.get(
                        lod_scene.meshes[lod_face.meshes[part]].geometry
                    )
                ),
            )
        # No second static face remains in the body: body's vertices end at neck.
        ref body = lod_assets.geometries.get(
            lod_scene.skinned_meshes[lod.skins[0]].geometry
        )
        ref points = body.attribute_view(String(POSITION))
        for v in range(points.count()):
            assert_true(points.vector3(v).y < lod.rig.at(HEAD).y)
    var rejected_scene = Scene()
    var rejected_assets = Assets()
    var rejected_root = rejected_scene.add(Object3D())
    with assert_raises(contains="Facial LOD budget must keep at least"):
        _ = add_game_humanoid(
            rejected_scene,
            rejected_assets,
            rejected_root,
            spec,
            100,
            detail=8,
            hand_detail=8,
            hair_detail=8,
            facial_animation=True,
        )
    assert_equal(rejected_scene.count(), 1)
    assert_equal(len(rejected_scene.meshes), 0)
    assert_equal(len(rejected_scene.skinned_meshes), 0)
    with assert_raises(contains="nonnegative"):
        _ = game_build_settings(-1)
    with assert_raises(contains="strand hair"):
        _ = game_build_settings(facial_animation=True, guides=1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
