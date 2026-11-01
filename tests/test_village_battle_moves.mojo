# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The player's moves: stances, specials, attacks in the air, the
surge, the lock and herbs, strong blows and the ground wave; and
the fighters a fight leaves out.

The player stands at the middle and faces -z. The dummy stands 1.5
meters before them, and the bandit 6 meters before them: see
`tests/_village_arena.mojo`."""

from core.assets import Assets
from core.scene import Scene
from extensions.attire.outfit import Outfit
from extensions.humanoid.sex import FEMALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.vegetation.ground import Ground, Lot, Pond
from tests._village_arena import (
    Arena,
    arena_parameters,
    flat_ground,
    holds_text,
    popup_texts,
)
from extensions.village.battle import (
    CHEST,
    WAVE_RANGE,
    HIT_STOP,
    SHAKE,
    Battle,
    Bolt,
    strong_blow,
)
from extensions.village.character import no_input
from extensions.village.combat import (
    BLOCKED,
    FALL,
    CRITICAL,
    GUARD_BREAK,
    HEAVY,
    HIGH_STANCE,
    HIT,
    LOW_STANCE,
    MID_STANCE,
    RISING_EDGE,
    Blow,
    Struck,
)
from extensions.village.residents import Body
from extensions.village.slashes import OVER_TRAIL, PLAYER_TRAIL
from extensions.village.surfaces import house_looks
from extensions.village.terrain import Terrain
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)
from units.si import INCH, METER, METER_PER_SECOND, Length, Velocity


def test_stances_pulses_specials_and_heavy_attacks() raises:
    var arena = Arena(arena_parameters(0, 0))
    var high = no_input()
    high.high = True
    arena.press(high)
    assert_true(arena.battle.fighter.stance == HIGH_STANCE)
    assert_true(holds_text(arena.battle.notes, "HIGH STANCE"))
    arena.battle.notes.clear()
    arena.press(high)
    assert_equal(len(arena.battle.notes), 0)
    var middle = no_input()
    middle.middle = True
    arena.press(middle)
    assert_true(arena.battle.fighter.stance == MID_STANCE)
    var low = no_input()
    low.low = True
    arena.press(low)
    assert_true(arena.battle.fighter.stance == LOW_STANCE)
    # A heavy attack, then a stamina recovery just after its swing.
    var heavy = no_input()
    heavy.heavy = True
    arena.tick(heavy)
    assert_true(arena.battle.fighter.move == HEAVY)
    arena.run(0.45)
    var pulse = no_input()
    pulse.guard = True
    assert_almost_equal(arena.battle.pulsed, -1, atol=1e-6)
    arena.press(pulse)
    assert_true(holds_text(popup_texts(arena.battle), "RECOVERED"))
    # The pulse's ring has started, and ages.
    assert_true(arena.battle.pulsed > 0)
    arena.run(1.5)
    # The rising edge says its name; the whirlwind without its points does
    # not start.
    var rising = no_input()
    rising.rising = True
    arena.press(rising)
    assert_true(holds_text(arena.battle.notes, "RISING EDGE!"))
    arena.run(1)
    arena.battle.notes.clear()
    arena.battle.fighter.special = 0
    var whirlwind = no_input()
    whirlwind.whirlwind = True
    arena.press(whirlwind)
    assert_equal(len(arena.battle.notes), 0)
    assert_true(arena.battle.fighter.free())


def test_an_attack_in_the_air_hangs_and_a_push_carries() raises:
    var arena = Arena(arena_parameters(0, 0))
    _ = arena.battle.fighter.request(RISING_EDGE)
    arena.battle.fighter.clock = 0.17
    arena.player.grounded = False
    arena.player.position = Vector3(0, 2, 0)
    arena.player.velocity = Vector3(0, -3, 0)
    arena.tick(no_input())
    assert_true(arena.player.velocity.y > -1)
    # In the wind-up, it falls.
    var early = Arena(arena_parameters(0, 0))
    _ = early.battle.fighter.request(RISING_EDGE)
    early.player.grounded = False
    early.player.position = Vector3(0, 2, 0)
    early.player.velocity = Vector3(0, -3, 0)
    early.tick(no_input(), 0.01)
    assert_true(early.player.velocity.y < -3)
    # A free player that a blow pushes slides with it.
    var pushed = Arena(arena_parameters(0, 0))
    pushed.battle.shove = Vector3(3, 0, 0)
    pushed.tick(no_input())
    assert_true(pushed.player.position.x > 0.1)
    # So does a free bandit.
    var shoved = Arena(arena_parameters(1, 0, 20))
    shoved.battle.foes[0].shove = Vector3(3, 0, 0)
    shoved.tick(no_input())
    assert_true(shoved.battle.foes[0].character.position.x > 0.1)


def test_a_fighter_on_a_lot_or_in_the_water_is_left_out() raises:
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
    var ground = Ground(
        hill_height=Length(0.0, METER),
        pond=Pond(
            Length(0.0, METER),
            Length(-1.5, METER),
            Length(1.0, METER),
            Length(1.0, METER),
        ),
    )
    var lots: List[Lot] = [Lot(0, -6, 2, 2, 0)]
    var battle = Battle(
        scene,
        assets,
        arena_parameters(1, 1),
        house_looks(assets, 4, 1),
        Terrain(ground),
        lots,
        body,
        Vector3(0, 0, 0),
        500,
        8,
    )
    assert_equal(len(battle.foes), 0)
    assert_equal(len(battle.dummies), 0)
    # And the other way around: the bandit in the water, the dummy on a lot.
    var wet = Ground(
        hill_height=Length(0.0, METER),
        pond=Pond(
            Length(0.0, METER),
            Length(-6.0, METER),
            Length(1.0, METER),
            Length(1.0, METER),
        ),
    )
    var dry: List[Lot] = [Lot(0, -1.5, 1, 1, 0)]
    var other = Battle(
        scene,
        assets,
        arena_parameters(1, 1),
        house_looks(assets, 4, 1),
        Terrain(wet),
        dry,
        body,
        Vector3(0, 0, 0),
        500,
        8,
    )
    assert_equal(len(other.foes), 0)
    assert_equal(len(other.dummies), 0)
    # A wolf on a lot, or in the water, is left out too.
    var den: List[Lot] = [Lot(-3, -6, 0.5, 0.5, 0)]
    var pack = Battle(
        scene,
        assets,
        arena_parameters(0, 0, 6, 1),
        house_looks(assets, 4, 1),
        flat_ground(),
        den,
        body,
        Vector3(0, 0, 0),
        500,
        8,
    )
    assert_equal(len(pack.foes), 0)
    var marsh = Ground(
        hill_height=Length(0.0, METER),
        pond=Pond(
            Length(-3.0, METER),
            Length(-6.0, METER),
            Length(1.0, METER),
            Length(1.0, METER),
        ),
    )
    var drowned = Battle(
        scene,
        assets,
        arena_parameters(0, 0, 6, 1),
        house_looks(assets, 4, 1),
        Terrain(marsh),
        List[Lot](),
        body,
        Vector3(0, 0, 0),
        500,
        8,
    )
    assert_equal(len(drowned.foes), 0)


def test_over_limit_is_announced_and_turns_the_trails_gold() raises:
    var arena = Arena(arena_parameters(0, 1))
    arena.battle.fighter.limit = 99
    var cut = no_input()
    cut.light = True
    arena.tick(cut)
    arena.run(0.3)
    assert_true(arena.battle.fighter.over > 0)
    assert_true(holds_text(arena.battle.notes, "SURGE!"))
    assert_true(arena.battle.trail.color.x == OVER_TRAIL.x)
    arena.battle.notes.clear()
    arena.run(0.5)
    assert_equal(len(arena.battle.notes), 0)
    arena.battle.fighter.over = 0.01
    arena.run(0.2)
    assert_true(arena.battle.trail.color.x == PLAYER_TRAIL.x)
    assert_false(arena.battle.limited)


def test_a_flick_moves_the_lock_and_herbs_heal() raises:
    # Two bandits too far to notice, and the dummy before the player.
    var arena = Arena(arena_parameters(2, 1, 15))
    var lock = no_input()
    lock.lock = True
    arena.press(lock)
    assert_equal(arena.battle.lock, 2)
    # A flick right moves the lock to the bandit on the right.
    var right = no_input()
    right.look_right = 1
    arena.tick(right)
    assert_equal(arena.battle.lock, 1)
    # Held, the stick moves it no further; let go and flicked left, it
    # moves to the first target on the left.
    arena.tick(right)
    assert_equal(arena.battle.lock, 1)
    arena.tick(no_input())
    var left = no_input()
    left.look_right = -1
    arena.tick(left)
    assert_equal(arena.battle.lock, 0)
    # On the left, there is nothing more: the lock stays.
    arena.tick(no_input())
    arena.tick(left)
    assert_equal(arena.battle.lock, 0)
    # A fallen target, or one out of range, is passed over.
    arena.battle.lock = 2
    arena.battle.foes[1].down = 0
    assert_equal(arena.battle.switch_lock(Vector3(0, 0, 0), 1), 2)
    arena.battle.foes[1].down = -1
    assert_equal(arena.battle.switch_lock(Vector3(0, 0, 30), 1), 2)
    # Herbs heal three tenths of the health, while the satchel has them.
    var healer = Arena(arena_parameters(0, 0))
    healer.battle.herbs = 2
    healer.battle.fighter.health = 100
    var heal = no_input()
    heal.heal = True
    healer.press(heal)
    assert_almost_equal(healer.battle.fighter.health, 250, atol=1e-3)
    assert_equal(healer.battle.eaten, 1)
    assert_true(holds_text(popup_texts(healer.battle), "+150"))
    assert_true(holds_text(healer.battle.notes, "HERBS HEAL 150"))
    healer.press(heal)
    healer.press(heal)
    assert_almost_equal(healer.battle.fighter.health, 400, atol=1e-3)
    assert_equal(healer.battle.eaten, 2)
    # At full health, no herb is eaten.
    healer.battle.eaten = 0
    healer.battle.fighter.health = 500
    healer.press(heal)
    assert_equal(healer.battle.eaten, 0)


def test_a_strong_blow_stops_the_fight_and_shakes_the_camera() raises:
    var slight = Blow(
        30,
        8,
        Velocity(1.5, METER_PER_SECOND),
        Velocity(0.0, METER_PER_SECOND),
    )
    var shove = Blow(
        30,
        8,
        Velocity(4.0, METER_PER_SECOND),
        Velocity(0.0, METER_PER_SECOND),
    )
    var lift = Blow(
        30,
        8,
        Velocity(1.0, METER_PER_SECOND),
        Velocity(6.5, METER_PER_SECOND),
    )
    assert_true(strong_blow(Struck(GUARD_BREAK, 0, 8), slight))
    assert_false(strong_blow(Struck(BLOCKED, 0, 8), shove))
    assert_true(strong_blow(Struck(CRITICAL, 45, 0), slight))
    assert_false(strong_blow(Struck(HIT, 30, 8), slight))
    assert_true(strong_blow(Struck(HIT, 30, 8), shove))
    assert_true(strong_blow(Struck(HIT, 30, 8), lift))
    # A heavy cut on the dummy stops the fight, and shakes the camera.
    var arena = Arena(arena_parameters(0, 1))
    var heavy = no_input()
    heavy.heavy = True
    arena.tick(heavy)
    var stopped = False
    for _ in range(20):
        arena.tick(no_input())
        if arena.battle.freeze > 0:
            stopped = True
            assert_true(arena.battle.shake > SHAKE * 0.5)
            break
    assert_true(stopped)
    # While it stands still, the fighter's clock does not run.
    arena.battle.freeze = HIT_STOP
    var clock = arena.battle.fighter.clock
    arena.tick(no_input(), 0.02)
    assert_almost_equal(arena.battle.fighter.clock, clock, atol=1e-6)
    assert_almost_equal(arena.battle.freeze, HIT_STOP - 0.02, atol=1e-6)
    # Then it runs, and the shake dies away.
    arena.run(0.5)
    assert_true(arena.battle.fighter.clock != clock)
    assert_true(arena.battle.shake < SHAKE * 0.01)


def test_a_ground_wave_sends_a_wave_along_the_ground() raises:
    # Two dummies in a line before the player, a fallen bandit beyond
    # them, and a third dummy raised far above the ground.
    var arena = Arena(arena_parameters(1, 3, 4))
    arena.battle.foes[0].fighter.move = FALL
    arena.battle.foes[0].down = 0
    arena.battle.dummies[1].dummy.post.x = 0
    arena.battle.dummies[1].dummy.post.z = -6
    arena.battle.dummies[1].dummy.foot = 5
    arena.battle.dummies[2].dummy.post.x = 0
    arena.battle.dummies[2].dummy.post.z = -3
    var ground_wave = no_input()
    ground_wave.ground_wave = True
    arena.tick(ground_wave)
    assert_true(holds_text(arena.battle.notes, "GROUND WAVE!"))
    arena.run(0.3)
    assert_equal(len(arena.battle.waves), 1)
    arena.run(0.3)
    # It struck each dummy in its way once, and passed the rest.
    assert_equal(arena.battle.fighter.combo, 2)
    assert_true(holds_text(popup_texts(arena.battle), "45"))
    arena.run(1)
    assert_equal(len(arena.battle.waves), 0)
    assert_true(WAVE_RANGE > 4)
    # A bolt strikes the dummy it flies at, with no companion to fill.
    var at = arena.battle.target_at(1) + Vector3(0, CHEST, 0)
    var bolt = Blow(
        28,
        10,
        Velocity(1.5, METER_PER_SECOND),
        Velocity(0.0, METER_PER_SECOND),
    )
    arena.battle.bolts.append(Bolt(at, at, 1, bolt, False, 0))
    arena.tick(no_input())
    assert_equal(len(arena.battle.bolts), 0)
    assert_true(holds_text(popup_texts(arena.battle), "28"))


def test_a_ground_wave_with_no_one_before_it_fades_out() raises:
    var arena = Arena(arena_parameters(0, 0))
    var ground_wave = no_input()
    ground_wave.ground_wave = True
    arena.tick(ground_wave)
    arena.run(0.3)
    assert_equal(len(arena.battle.waves), 1)
    arena.run(1.2)
    assert_equal(len(arena.battle.waves), 0)
    assert_equal(arena.battle.fighter.combo, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
