# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A facial LOD budget above the minimum can still refuse safe collapse."""

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.humanoid.rig.game import add_game_humanoid
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from std.testing import TestSuite, assert_equal, assert_raises
from units.si import FOOT, Length


def test_safe_collapse_refuses_before_scene_or_asset_changes() raises:
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    # This template reserves 42,423 face, mouth and eye triangles. The
    # remaining 1,000 exceed the minimum, but safe collapse retains more.
    # In particular, the hair shell alone retains 1,664 triangles.
    with assert_raises(
        contains="Facial LOD safe-collapse limit exceeds budget"
    ):
        _ = add_game_humanoid(
            scene,
            assets,
            root,
            HumanoidSpec(Length(6, FOOT), MALE),
            43423,
            detail=12,
            hand_detail=8,
            hair_detail=8,
            facial_animation=True,
        )
    assert_equal(scene.count(), 1)
    assert_equal(len(scene.meshes), 0)
    assert_equal(len(scene.skinned_meshes), 0)
    assert_equal(assets.geometries.count(), 0)
    assert_equal(assets.materials.count(), 0)
    assert_equal(assets.textures.count(), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
