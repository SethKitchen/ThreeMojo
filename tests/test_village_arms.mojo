# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A body's sword and its sword clips: which clip plays, and which sword
shows."""

from core.assets import Assets
from core.scene import Scene
from extensions.attire.outfit import Outfit
from extensions.humanoid.sex import FEMALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.vegetation.ground import Ground
from extensions.village.arms import Arms
from extensions.village.blade import BRIGHT_STEEL, SwordLooks
from extensions.village.character import (
    STANDING,
    WALKING,
    Character,
    CharacterParameters,
)
from extensions.village.combat import (
    DODGE,
    FREE,
    HIGH_STANCE,
    LIGHT_ONE,
    Fighter,
    FighterParameters,
)
from extensions.village.residents import Body
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)
from units.si import METER, RADIAN, SECOND, Angle, Duration, INCH, Length


def test_a_body_plays_what_its_fighter_does() raises:
    var assets = Assets()
    var scene = Scene()
    var body = Body(
        scene,
        assets,
        HumanoidSpec(Length(60.0, INCH), FEMALE),
        Outfit(),
        500,
        8,
    )
    var before = len(scene.meshes)
    var arms = Arms(scene, assets, body, SwordLooks(assets), BRIGHT_STEEL)
    assert_equal(arms.moves[FREE.value], -1)
    assert_true(arms.moves[LIGHT_ONE.value] >= 0)
    # A sword in the hand, one at the hip and a scabbard: two meshes a
    # sword and one the scabbard.
    assert_equal(len(scene.meshes) - before, 5)
    var ground = Ground(hill_height=Length(0.0, METER))
    var walker = Character(
        CharacterParameters(), 1, 2, Angle(0.0, RADIAN), ground
    )
    var fighter = Fighter(FighterParameters())
    var step = Duration(0.05, SECOND)
    # Sheathed and standing, the body plays its own clip.
    assert_equal(arms.clip_for(walker, fighter, False), -1)
    arms.pose(scene, body, walker, fighter, False, step)
    assert_equal(arms.showing, -1)
    assert_false(scene.node(arms.held).visible)
    assert_true(scene.node(arms.sheathed).visible)
    # Drawn, it stands ready, and the sword is in the hand.
    assert_equal(arms.clip_for(walker, fighter, True), arms.ready)
    arms.pose(scene, body, walker, fighter, True, step)
    assert_equal(arms.showing, arms.ready)
    assert_true(scene.node(arms.held).visible)
    assert_false(scene.node(arms.sheathed).visible)
    assert_almost_equal(scene.node(body.carrier).position.x, 1, atol=1e-6)
    # Walking with the sword drawn, it plays its walk.
    walker.stance = WALKING
    assert_equal(arms.clip_for(walker, fighter, True), -1)
    arms.pose(scene, body, walker, fighter, True, step)
    assert_equal(arms.showing, -1)
    assert_true(body.playing == WALKING)
    walker.stance = STANDING
    # A guard plays the guard.
    fighter.hold_guard(True)
    assert_equal(arms.clip_for(walker, fighter, False), arms.guard)
    arms.pose(scene, body, walker, fighter, True, step)
    fighter.hold_guard(False)
    # A move plays its clip, slowed by the stance.
    _ = fighter.set_stance(HIGH_STANCE)
    _ = fighter.press_light()
    var cut = arms.moves[LIGHT_ONE.value]
    arms.pose(scene, body, walker, fighter, True, step)
    assert_equal(arms.showing, cut)
    assert_almost_equal(
        body.mixer.action(cut).time_scale, 1 / Float32(1.2), atol=1e-5
    )
    # Further in, it plays on.
    fighter.update(Duration(0.3, SECOND))
    arms.pose(scene, body, walker, fighter, True, step)
    var later = body.mixer.action(cut).phase
    assert_true(later > 0.04)
    # The same move again starts its clip again.
    fighter.clock = 0.01
    arms.pose(scene, body, walker, fighter, True, step)
    assert_true(body.mixer.action(cut).phase < later)
    # A free fighter whose clock reads back is not a move started again.
    var free = Fighter(FighterParameters())
    arms.seen = FREE
    arms.seen_clock = 0.5
    arms.pose(scene, body, walker, free, False, step)
    assert_equal(arms.showing, -1)
    # A dodge after a dodge starts again too.
    var dodger = Fighter(FighterParameters())
    _ = dodger.request(DODGE)
    arms.pose(scene, body, walker, dodger, True, step)
    assert_equal(arms.showing, arms.moves[DODGE.value])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
