# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Foot contents must be a `FootContents`, not a bare integer."""

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.bone import bone_phong
from extensions.humanoid.skeleton.foot.assembly import add_foot
from extensions.humanoid.skeleton.look import (
    ligament_phong,
    muscle_phong,
    tendon_phong,
)
from units.si import FOOT, Length


def main() raises:
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    _ = add_foot(
        scene,
        assets,
        root,
        person,
        assets.materials.add(bone_phong()),
        assets.materials.add(ligament_phong()),
        assets.materials.add(muscle_phong()),
        assets.materials.add(tendon_phong()),
        contents=0,
    )
