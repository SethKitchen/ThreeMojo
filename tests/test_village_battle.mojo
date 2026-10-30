# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A fight on flat ground: the player against a bandit and a straw dummy.

The player stands at the middle and faces -z. The dummy stands 1.5
meters before them, and the bandit 6 meters before them: see
`tests/_village_arena.mojo`."""

from controls.third_person_controls import ThirdPersonControls
from core.assets import Assets
from core.scene import Scene
from extensions.attire.outfit import Outfit
from extensions.humanoid.sex import FEMALE, MALE
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
    HIT_STOP,
    SHAKE,
    BLOCK_PUSH,
    CALM_SECONDS,
    JUGGLE,
    LOOT,
    SLOW_SECONDS,
    Battle,
    BattleParameters,
    pressed,
    push_of,
    strong_blow,
    throw_up,
)
from extensions.village.character import (
    Character,
    CharacterParameters,
    MoveInput,
    Obstacle,
    no_input,
)
from extensions.village.combat import (
    BLOCKED,
    CRITICAL,
    FREE,
    STAGGER,
    DEFEATED,
    DODGE,
    EVADED,
    FLINCH,
    GUARD_BREAK,
    HEAVY,
    HIGH_STANCE,
    HIT,
    LIGHT_ONE,
    LOW_STANCE,
    MID_STANCE,
    RISING_EDGE,
    Blow,
    Struck,
)
from extensions.village.foes import (
    ALERTED,
    ATTACKING,
    CLOSING,
    GUARDING,
    RETREATING,
    RETURNING,
    Bandit,
    Post,
    POSTED,
)
from extensions.vegetation.noise import hash01
from extensions.village.residents import Body
from extensions.village.skills import (
    BLOW_EXPERIENCE,
    DEFEAT_EXPERIENCE,
    PRACTICE_EXPERIENCE,
)
from extensions.village.slashes import OVER_TRAIL, PLAYER_TRAIL
from extensions.village.surfaces import house_looks
from extensions.village.terrain import Terrain
from math.vector3 import Vector3
from std.math import cos, sin
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import (
    DEGREE,
    INCH,
    METER,
    METER_PER_SECOND,
    RADIAN,
    SECOND,
    Angle,
    Duration,
    Length,
    Velocity,
)


def test_a_press_is_a_button_held_now_and_not_before() raises:
    var all = MoveInput(
        0.5,
        0.25,
        0,
        0,
        True,
        True,
        True,
        light=True,
        heavy=True,
        rising=True,
        tempest=True,
        dodge=True,
        guard=True,
        lock=True,
        high=True,
        middle=True,
        low=True,
        heal=True,
    )
    var none = no_input()
    var fresh = pressed(all, none)
    assert_almost_equal(fresh.forward, 0.5, atol=1e-6)
    for button in [
        fresh.run,
        fresh.jump,
        fresh.use,
        fresh.light,
        fresh.heavy,
        fresh.rising,
        fresh.tempest,
        fresh.dodge,
        fresh.guard,
        fresh.lock,
        fresh.high,
        fresh.middle,
        fresh.low,
        fresh.heal,
    ]:
        assert_true(button)
    for held in [pressed(all, all), pressed(none, all)]:
        for button in [
            held.run,
            held.jump,
            held.use,
            held.light,
            held.heavy,
            held.rising,
            held.tempest,
            held.dodge,
            held.guard,
            held.lock,
            held.high,
            held.middle,
            held.low,
            held.heal,
        ]:
            assert_false(button)


def test_a_fight_refuses_what_cannot_be_held() raises:
    BattleParameters().check()
    var p = BattleParameters()
    for k in range(17):
        p.posts.append(Post(Float32(k), 0, Angle(0.0, DEGREE)))
    with assert_raises(contains="16"):
        p.check()
    p = BattleParameters()
    for _ in range(17):
        p.bandits.append(p.bandits[0].copy())
    with assert_raises(contains="16"):
        p.check()
    p = BattleParameters()
    p.bandits[1].fighter.health = 0
    with assert_raises(contains="health"):
        p.check()
    p = BattleParameters()
    p.revive = Duration(-1.0, SECOND)
    with assert_raises(contains="revive"):
        p.check()
    p = BattleParameters()
    p.respawn = Duration(2.0e4, SECOND)
    with assert_raises(contains="revive"):
        p.check()


def test_a_frame_must_have_a_time() raises:
    var arena = Arena(arena_parameters(0, 0))
    with assert_raises(contains="frame"):
        arena.tick(no_input(), -1)
    with assert_raises(contains="frame"):
        arena.tick(no_input(), 2.0e9)
    # With nobody to fight, there is nothing to lock on to.
    assert_equal(
        arena.battle.pick_lock(Vector3(0, 0, 0), Angle(0.0, DEGREE)), -1
    )


def test_a_blow_pushes_and_throws() raises:
    var way = Vector3(1, 0, 0)
    var blow = Blow(
        30,
        10,
        Velocity(4.0, METER_PER_SECOND),
        Velocity(0.0, METER_PER_SECOND),
    )
    assert_almost_equal(push_of(Struck(HIT, 30, 10), blow, way).x, 4, atol=1e-6)
    assert_almost_equal(
        push_of(Struck(BLOCKED, 0, 10), blow, way).x, 4 * BLOCK_PUSH, atol=1e-6
    )
    assert_almost_equal(
        push_of(Struck(GUARD_BREAK, 0, 10), blow, way).x,
        4 * BLOCK_PUSH,
        atol=1e-6,
    )
    assert_almost_equal(
        push_of(Struck(EVADED, 0, 0), blow, way).x, 0, atol=1e-6
    )
    var ground = flat_ground()
    var walker = Character(
        CharacterParameters(), 0, 0, Angle(0.0, RADIAN), ground
    )
    # A blow that does not land throws nothing; one that lands on a fighter
    # on the ground throws nothing either, unless it launches.
    throw_up(walker, Struck(BLOCKED, 0, 0), blow)
    throw_up(walker, Struck(HIT, 30, 10), blow)
    assert_true(walker.grounded)
    var launch = Blow(
        30,
        10,
        Velocity(1.0, METER_PER_SECOND),
        Velocity(6.5, METER_PER_SECOND),
    )
    throw_up(walker, Struck(HIT, 30, 10), launch)
    assert_false(walker.grounded)
    assert_almost_equal(walker.velocity.y, 6.5, atol=1e-6)
    # In the air, a blow keeps it up.
    walker.velocity.y = -2
    throw_up(walker, Struck(HIT, 30, 10), blow)
    assert_almost_equal(walker.velocity.y, JUGGLE, atol=1e-6)


def test_the_player_cuts_a_dummy() raises:
    # The bandit stands too far to notice, or to reach.
    var arena = Arena(arena_parameters(1, 1, 15))
    assert_equal(arena.battle.trained, 0)
    assert_equal(len(arena.battle.dummies), 1)
    assert_equal(arena.battle.targets(), 2)
    assert_true(arena.battle.standing(1))
    assert_almost_equal(arena.battle.target_at(1).z, -1.5, atol=1e-6)
    assert_equal(len(arena.battle.movers()), 2)
    assert_almost_equal(arena.battle.obstacles()[1].radius, 0.35, atol=1e-6)
    assert_false(arena.battle.drawn)
    var cut = no_input()
    cut.light = True
    arena.tick(cut)
    assert_true(arena.battle.fighter.move == LIGHT_ONE)
    assert_true(arena.battle.drawn)
    arena.run(0.3)
    assert_equal(arena.battle.fighter.combo, 1)
    assert_true(holds_text(popup_texts(arena.battle), "30"))
    assert_equal(arena.battle.trained, PRACTICE_EXPERIENCE)
    assert_almost_equal(arena.battle.foes[0].fighter.health, 300, atol=1e-6)
    assert_false(arena.battle.limited)
    # The dummy rocks, and keeps its health.
    var rocked = arena.battle.dummies[0].dummy.spin.length()
    assert_true(rocked > 0)
    assert_almost_equal(
        arena.battle.dummies[0].fighter.health,
        arena.battle.dummies[0].fighter.parameters.health,
        atol=1e-3,
    )
    # The numbers rise and go.
    arena.run(1.2)
    assert_equal(len(arena.battle.popups), 0)
    # With nothing to fight, the sword is sheathed.
    arena.run(CALM_SECONDS + 0.5)
    assert_false(arena.battle.drawn)


def test_the_lock_turns_the_camera_and_faces_the_player() raises:
    # The bandit stands too far to notice the player.
    var arena = Arena(arena_parameters(1, 1, 15))
    arena.view.yaw = Angle(90.0, DEGREE)
    # The dummy lies nearer the middle of the view than the bandit.
    assert_equal(
        arena.battle.pick_lock(Vector3(0, 0, 0), Angle(0.0, DEGREE)), 1
    )
    var lock = no_input()
    lock.lock = True
    arena.press(lock)
    assert_true(arena.battle.lock >= 0)
    arena.run(1)
    assert_true(abs(arena.view.yaw.to(DEGREE)) < 30)
    # Walking right, the locked player still faces the target.
    var right = no_input()
    right.right = 1
    arena.run(0.5, right)
    var toward = (
        arena.battle.target_at(arena.battle.lock) - arena.player.position
    )
    var h = arena.player.heading.to(RADIAN)
    var ahead = Vector3(-sin(h), 0, -cos(h))
    assert_true((toward.x * ahead.x + toward.z * ahead.z) > 0)
    # An attack turns to the locked target.
    assert_true(
        arena.battle.aim(
            arena.player.position, arena.player.heading, Vector3(0, 0, 0)
        )
    )
    arena.press(lock)
    assert_equal(arena.battle.lock, -1)
    # Near the bandit, it is the best, and the dummy after it is worse.
    assert_equal(
        arena.battle.pick_lock(Vector3(0, 0, -14), Angle(0.0, DEGREE)), 0
    )
    # A target behind the player is not aimed at.
    assert_false(
        arena.battle.aim(
            Vector3(0, 0, 0), Angle(180.0, DEGREE), Vector3(0, 0, 0)
        )
    )
    # Nothing in range: nothing to lock on to.
    assert_equal(
        arena.battle.pick_lock(Vector3(100, 0, 100), Angle(0.0, DEGREE)), -1
    )
    # Aim: the nearest before the player, else the stick, else nothing.
    var aim = arena.battle.aim(
        Vector3(0, 0, 0), Angle(0.0, DEGREE), Vector3(0, 0, 0)
    )
    assert_true(aim)
    var stick = arena.battle.aim(
        Vector3(50, 0, 50), Angle(0.0, DEGREE), Vector3(1, 0, 0)
    )
    assert_almost_equal(stick.value().to(DEGREE), -90, atol=1e-3)
    assert_false(
        arena.battle.aim(
            Vector3(50, 0, 50), Angle(0.0, DEGREE), Vector3(0, 0, 0)
        )
    )
    # A lock lets go when its target goes too far.
    arena.press(lock)
    assert_true(arena.battle.lock >= 0)
    arena.player.position = Vector3(40, 0, 40)
    arena.tick(no_input())
    assert_equal(arena.battle.lock, -1)


def test_a_bandit_comes_and_strikes_and_a_guard_blocks() raises:
    var arena = Arena(arena_parameters(1, 0))
    assert_equal(len(arena.battle.foes), 1)
    arena.run(9)
    # It noticed the player, took the token and struck.
    assert_true(arena.battle.foes[0].brain.state != POSTED)
    assert_true(arena.battle.fighter.health < 500)
    assert_true(arena.battle.drawn)
    # Locked on and guarding, the player takes its blows on ki.
    var guard = no_input()
    guard.guard = True
    guard.lock = True
    var health = arena.battle.fighter.health
    var blocked = False
    for _ in range(200):
        arena.tick(guard)
        if holds_text(popup_texts(arena.battle), "BLOCKED"):
            blocked = True
    assert_true(blocked)
    assert_almost_equal(arena.battle.fighter.health, health, atol=1e-3)


def _swinging(mut arena: Arena, clock: Float32) raises:
    """Stand the bandit 1.5 meters before the player, facing them, in its
    first light attack `clock` seconds in."""
    ref foe = arena.battle.foes[0]
    foe.character.position = Vector3(0, 0, -1.5)
    foe.character.heading = Angle(180.0, DEGREE)
    _ = foe.fighter.request(LIGHT_ONE)
    foe.fighter.clock = clock


def test_a_fresh_guard_parries_and_a_late_dodge_is_perfect() raises:
    var arena = Arena(arena_parameters(1, 0))
    _swinging(arena, 0.1)
    var guard = no_input()
    guard.guard = True
    arena.tick(guard)
    assert_true(holds_text(popup_texts(arena.battle), "PARRY"))
    assert_true(arena.battle.foes[0].fighter.move == FLINCH)
    var dodger = Arena(arena_parameters(1, 0))
    dodger.battle.drawn = True
    _swinging(dodger, 0.1)
    var dodge = no_input()
    dodge.dodge = True
    dodger.tick(dodge)
    assert_true(dodger.battle.fighter.move == DODGE)
    assert_true(holds_text(popup_texts(dodger.battle), "PERFECT DODGE"))
    assert_almost_equal(dodger.battle.slow, SLOW_SECONDS - 0.05, atol=1e-4)
    # The bandit moves slowly while the dodge's time lasts.
    var clock = dodger.battle.foes[0].fighter.clock
    dodger.tick(no_input())
    assert_true(dodger.battle.foes[0].fighter.clock - clock < 0.02)


def test_a_dodge_goes_the_way_of_the_stick_or_back() raises:
    var arena = Arena(arena_parameters(0, 0))
    # A sheathed sword does not dodge.
    var dodge = no_input()
    dodge.dodge = True
    arena.press(dodge)
    assert_true(arena.battle.fighter.free())
    arena.battle.drawn = True
    dodge.right = 1
    arena.tick(dodge)
    assert_true(arena.battle.fighter.move == DODGE)
    arena.run(0.4)
    assert_true(arena.player.position.x > 2)
    var back = Arena(arena_parameters(0, 0))
    back.battle.drawn = True
    var plain = no_input()
    plain.dodge = True
    back.tick(plain)
    back.run(0.4)
    assert_true(back.player.position.z > 2)


def test_the_player_defeats_a_bandit_who_comes_back() raises:
    var arena = Arena(arena_parameters(1, 0))
    _swinging(arena, 0)
    ref foe = arena.battle.foes[0]
    foe.fighter.move = FLINCH
    foe.fighter.health = 1
    foe.brain.seed = _seed(True)
    arena.battle.lock = 0
    arena.battle.token = 0
    var cut = no_input()
    cut.light = True
    arena.tick(cut)
    arena.run(0.3)
    assert_true(arena.battle.foes[0].fighter.defeated())
    assert_equal(arena.battle.foes[0].down >= 0, True)
    assert_equal(arena.battle.lock, -1)
    assert_equal(arena.battle.token, -1)
    assert_false(arena.battle.standing(0))
    assert_almost_equal(arena.battle.obstacles()[0].radius, 0, atol=1e-6)
    assert_equal(arena.battle.loot, LOOT)
    assert_true(holds_text(arena.battle.notes, "+8 COINS +1 HERB"))
    assert_equal(arena.battle.found, 1)
    assert_equal(arena.battle.trained, BLOW_EXPERIENCE + DEFEAT_EXPERIENCE)
    arena.run(1.2)
    assert_false(arena.scene.node(arena.battle.foes[0].body.carrier).visible)
    arena.run(1.2)
    assert_true(arena.battle.foes[0].fighter.free())
    assert_true(arena.battle.foes[0].down < 0)
    assert_true(arena.scene.node(arena.battle.foes[0].body.carrier).visible)


def _seed(drops: Bool) -> Int:
    """Return a seed whose first roll of the dice drops a herb, or does
    not."""
    for seed in range(1000):  # pragma: no branch
        if (hash01(seed, 1, 6) < 0.5) == drops:
            return seed
    return -1


def _facing(mut arena: Arena, index: Int = 0):
    """Stand a bandit free 1.5 meters before the player, facing them."""
    ref foe = arena.battle.foes[index]
    foe.character.position = Vector3(0, 0, -1.5)
    foe.character.heading = Angle(180.0, DEGREE)


def _cut(mut arena: Arena) raises:
    """Make a light attack, and let it strike."""
    var cut = no_input()
    cut.light = True
    arena.tick(cut)
    arena.run(0.3)


def test_a_guard_blocks_a_cut_and_a_stagger_takes_a_critical() raises:
    var arena = Arena(arena_parameters(1, 0))
    _facing(arena)
    arena.battle.foes[0].brain.state = GUARDING
    arena.battle.foes[0].brain.timer = 5
    arena.battle.foes[0].fighter.hold_guard(True)
    _cut(arena)
    assert_true(holds_text(popup_texts(arena.battle), "BLOCKED"))
    assert_almost_equal(arena.battle.foes[0].fighter.health, 300, atol=1e-6)
    var broken = Arena(arena_parameters(1, 0))
    _facing(broken)
    broken.battle.foes[0].brain.state = ALERTED
    broken.battle.foes[0].brain.timer = 5
    broken.battle.foes[0].fighter.move = STAGGER
    _cut(broken)
    assert_true(holds_text(popup_texts(broken.battle), "CRITICAL"))


def test_a_cut_breaks_off_an_attack_and_fells_a_bandit() raises:
    var arena = Arena(arena_parameters(2, 0))
    _facing(arena)
    ref attacker = arena.battle.foes[0]
    attacker.brain.state = ATTACKING
    attacker.brain.plan = [HEAVY, HEAVY]
    arena.battle.token = 0
    _cut(arena)
    assert_true(arena.battle.foes[0].brain.state == RETREATING)
    assert_equal(arena.battle.token, -1)
    # A bandit with no token and no lock on it falls.
    var fell = Arena(arena_parameters(1, 0))
    _facing(fell)
    fell.battle.foes[0].fighter.health = 1
    fell.battle.foes[0].brain.seed = _seed(False)
    _cut(fell)
    assert_true(holds_text(fell.battle.notes, "+8 COINS"))
    assert_equal(fell.battle.found, 0)
    assert_true(fell.battle.foes[0].fighter.defeated())
    assert_equal(fell.battle.token, -1)
    assert_equal(fell.battle.lock, -1)
    # A fallen bandit cannot be locked on to.
    assert_equal(
        fell.battle.pick_lock(Vector3(0, 0, 0), Angle(0.0, DEGREE)), -1
    )


def test_a_fallen_player_comes_to_at_the_start() raises:
    # The second bandit stays at its post, 7 meters off.
    var arena = Arena(arena_parameters(2, 0))
    arena.battle.lock = 0
    # A bandit on its way to the player goes home when the player falls.
    arena.battle.foes[0].brain.state = CLOSING
    arena.battle.foes[0].character.position = Vector3(0, 0, -3)
    _ = arena.battle.fighter.receive(
        Blow(
            1000,
            0,
            Velocity(2.0, METER_PER_SECOND),
            Velocity(0.0, METER_PER_SECOND),
        ),
        False,
    )
    arena.battle.shove = Vector3(2, 0, 0)
    # A fallen player makes no move.
    var cut = no_input()
    cut.light = True
    arena.tick(cut)
    assert_true(arena.battle.fighter.defeated())
    assert_equal(arena.battle.lock, -1)
    assert_true(holds_text(arena.battle.notes, "YOU FALL"))
    assert_true(arena.battle.foes[0].brain.state == RETURNING)
    assert_true(arena.battle.foes[1].brain.state == POSTED)
    assert_true(arena.player.position.x > 0)
    arena.run(0.6)
    assert_true(arena.battle.fighter.free())
    assert_almost_equal(arena.player.position.x, 0, atol=1e-4)
    assert_true(holds_text(arena.battle.notes, "YOU COME TO BY THE TRAIL"))


def test_stances_pulses_artes_and_heavy_attacks() raises:
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
    # A heavy attack, then a ki pulse just after its swing.
    var heavy = no_input()
    heavy.heavy = True
    arena.tick(heavy)
    assert_true(arena.battle.fighter.move == HEAVY)
    arena.run(0.45)
    var pulse = no_input()
    pulse.guard = True
    arena.press(pulse)
    assert_true(holds_text(popup_texts(arena.battle), "KI PULSE"))
    arena.run(1.5)
    # The rising edge says its name; the tempest without its points does
    # not start.
    var rising = no_input()
    rising.rising = True
    arena.press(rising)
    assert_true(holds_text(arena.battle.notes, "RISING EDGE!"))
    arena.run(1)
    arena.battle.notes.clear()
    arena.battle.fighter.arte = 0
    var tempest = no_input()
    tempest.tempest = True
    arena.press(tempest)
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
    # And the other way round: the bandit in the water, the dummy on a lot.
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


def test_over_limit_is_announced_and_turns_the_trails_gold() raises:
    var arena = Arena(arena_parameters(0, 1))
    arena.battle.fighter.limit = 99
    var cut = no_input()
    cut.light = True
    arena.tick(cut)
    arena.run(0.3)
    assert_true(arena.battle.fighter.over > 0)
    assert_true(holds_text(arena.battle.notes, "OVER LIMIT!"))
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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
