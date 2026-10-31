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
    BITE,
    GROUND_WAVE,
    DODGE,
    FREE,
    HIGH_STANCE,
    LIGHT_ONE,
    MEND,
    MOVES,
    PLUNGE,
    SPELL_BOLT,
    Fighter,
    FighterParameters,
)
from extensions.village.residents import Body
from extensions.village.styles import (
    ARCHERY,
    AXE,
    HAND_TO_HAND,
    MACE,
    MAGIC,
    STYLES,
    SWORD,
    FightingStyle,
)
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
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
    assert_equal(arms.table[FREE.value], -1)
    assert_true(arms.table[LIGHT_ONE.value] >= 0)
    assert_true(arms.table[GROUND_WAVE.value] >= 0)
    assert_equal(arms.table[BITE.value], -1)
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
    assert_false(scene.node(arms.held[SWORD.value]).visible)
    assert_true(scene.node(arms.stowed[SWORD.value]).visible)
    # Drawn, it stands ready, and the sword is in the hand.
    var ready = arms.readies[SWORD.value]
    assert_equal(arms.clip_for(walker, fighter, True), ready)
    arms.pose(scene, body, walker, fighter, True, step)
    assert_equal(arms.showing, ready)
    assert_true(scene.node(arms.held[SWORD.value]).visible)
    assert_false(scene.node(arms.stowed[SWORD.value]).visible)
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
    assert_equal(
        arms.clip_for(walker, fighter, False), arms.guards[SWORD.value]
    )
    arms.pose(scene, body, walker, fighter, True, step)
    fighter.hold_guard(False)
    # A move plays its clip, slowed by the stance.
    _ = fighter.set_stance(HIGH_STANCE)
    _ = fighter.press_light()
    var cut = arms.table[SWORD.value * MOVES + LIGHT_ONE.value]
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
    assert_equal(arms.showing, arms.table[SWORD.value * MOVES + DODGE.value])


def test_a_body_carries_each_styles_weapon_and_clips() raises:
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
    var styles: List[FightingStyle] = [
        SWORD,
        AXE,
        MACE,
        HAND_TO_HAND,
        MAGIC,
        ARCHERY,
        SWORD,
        AXE,
    ]
    var arms = Arms(
        scene, assets, body, SwordLooks(assets), BRIGHT_STEEL, styles
    )
    for k in range(STYLES):
        assert_true(arms.armed[k])
    # Fists, a staff and a bow have clips of their own; the axe uses the
    # sword's.
    var light = LIGHT_ONE.value
    var sword = arms.table[SWORD.value * MOVES + light]
    assert_true(arms.table[HAND_TO_HAND.value * MOVES + light] != sword)
    assert_equal(arms.table[AXE.value * MOVES + light], sword)
    var bolt = SPELL_BOLT.value
    assert_true(
        arms.table[MAGIC.value * MOVES + bolt]
        != arms.table[SWORD.value * MOVES + bolt]
    )
    assert_true(arms.readies[ARCHERY.value] == arms.guards[ARCHERY.value])
    assert_true(arms.readies[HAND_TO_HAND.value] != arms.readies[SWORD.value])
    # The style in use shows its weapon in the hand, drawn; every other is
    # put away.
    arms.show(scene, MAGIC, True)
    assert_true(scene.node(arms.held[MAGIC.value]).visible)
    assert_false(scene.node(arms.stowed[MAGIC.value]).visible)
    assert_false(scene.node(arms.held[SWORD.value]).visible)
    assert_false(scene.node(arms.stowed[SWORD.value]).visible)
    arms.show(scene, MAGIC, False)
    assert_true(scene.node(arms.stowed[MAGIC.value]).visible)
    # A fighter in a style plays that style's clip.
    var ground = Ground(hill_height=Length(0.0, METER))
    var walker = Character(
        CharacterParameters(), 3, 0, Angle(0.0, RADIAN), ground
    )
    var fighter = Fighter(FighterParameters())
    _ = fighter.set_style(HAND_TO_HAND)
    _ = fighter.request(LIGHT_ONE)
    assert_equal(
        arms.clip_for(walker, fighter, True),
        arms.table[HAND_TO_HAND.value * MOVES + light],
    )
    # Placing a body stands it where its character stands.
    arms.place(scene, body, walker)
    assert_almost_equal(scene.node(body.carrier).position.x, 3, atol=1e-6)
    # A body can carry no weapon at all.
    var bare = Arms(
        scene,
        assets,
        body,
        SwordLooks(assets),
        BRIGHT_STEEL,
        List[FightingStyle](),
    )
    for k in range(STYLES):
        assert_false(bare.armed[k])
    # A giant plays a giant's clips for the moves of a boss's attacks.
    var maces: List[FightingStyle] = [MACE]
    var giant = Arms(
        scene, assets, body, SwordLooks(assets), BRIGHT_STEEL, maces, True
    )
    var slam = giant.table[MACE.value * MOVES + PLUNGE.value]
    assert_equal(body.mixer.action(slam).clip.name, "giant_slam")
    var roar = giant.table[SWORD.value * MOVES + MEND.value]
    assert_equal(body.mixer.action(roar).clip.name, "giant_roar")
    var bad: List[FightingStyle] = [FightingStyle(6)]
    with assert_raises(contains="six"):
        _ = Arms(scene, assets, body, SwordLooks(assets), BRIGHT_STEEL, bad)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
