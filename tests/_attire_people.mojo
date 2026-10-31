# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A coarse game humanoid for the tests of `extensions.attire` that dress
a person. Apart from `tests._attire_fixtures`, so that a suite of rigs
and strips alone does not compile the humanoid."""

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.humanoid.rig.game import GameHumanoid, add_game_humanoid
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from std.sys import num_logical_cores
from units.si import FOOT, Length


def coarse_spec() -> HumanoidSpec:
    """Return the six-foot male template."""
    return HumanoidSpec(Length(6.0, FOOT), MALE)


def coarse_person(
    mut scene: Scene, mut assets: Assets, guides: Int = 0, cards: Int = 0
) raises -> GameHumanoid:
    """Return a coarse game humanoid in `scene`: detail 12, 3000 triangles.

    Args:
        scene: The scene.
        assets: The store.
        guides: Guide strands of hair, or none.
        cards: Cards of hair, or none.

    Returns:
        The humanoid.
    """
    var root = scene.add(Object3D())
    return add_game_humanoid(
        scene,
        assets,
        root,
        coarse_spec(),
        3000,
        12,
        8,
        8,
        guides=guides,
        followers=1 if guides > 0 else 0,
        workers=num_logical_cores(),
        cards=cards,
    )
