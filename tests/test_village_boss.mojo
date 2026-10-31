# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A raid boss: its zones, its attacks and phases, its threat table, its
poise, its shared rockfall, and what it decides each frame."""

from extensions.village.boss import (
    AGGRO_RANGE,
    BOSS_ATTACKS,
    BOSS_HEALTH,
    BOSS_PHASES,
    BOSS_POISE,
    BOSS_STAGGER,
    CHARGE,
    CHARGE_LENGTH,
    CHARGE_SPEED,
    CIRCLE,
    CLEAVE,
    CONE,
    ENRAGE_POWER,
    ENRAGE_SECONDS,
    FURY,
    HEAL_THREAT,
    LAST_STAND,
    LEASH_RANGE,
    LINE,
    LINK_DAMAGE,
    MELEE_RANGE,
    OPENING,
    PARTY_HEALTH,
    POISE_DELAY,
    ROCKFALL,
    ROCK_DAMAGE,
    ROCK_RADIUS,
    SLAM,
    STAGGER_BONUS,
    STOMP,
    SUMMON,
    TANK_THREAT,
    TAUNT_SECONDS,
    THREAT_SWITCH,
    ZONE_SHAPES,
    Boss,
    BossAttack,
    BossPhase,
    BossSight,
    Zone,
    ZoneShape,
    attack_data,
    attack_name,
    boss_health,
    inside,
    link_damage,
    phase_of,
    phase_pace,
    rock_blow,
    rotation,
    share_rockfall,
)
from extensions.village.combat import (
    CRITICAL,
    DEFEATED,
    HIT,
    IGNORED,
    STAMINA_BREAK,
    Blow,
)
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import METER_PER_SECOND, Velocity


def _blow(damage: Float32, stamina: Float32) -> Blow:
    """Return a blow that pushes and throws nothing."""
    return Blow(
        damage,
        stamina,
        Velocity(0.0, METER_PER_SECOND),
        Velocity(0.0, METER_PER_SECOND),
    )


def _sight(at: Vector3, members: List[Vector3]) -> BossSight:
    """Return a boss's sight at home, facing plus z, with every member
    standing."""
    var up = List[Bool](length=len(members), fill=True)
    return BossSight(at, Vector3(0, 0, 1), at, members.copy(), up^)


def _think(
    mut boss: Boss, sight: BossSight, seconds: Float32
) raises -> List[Bool]:
    """Let a boss think in steps of a 60th of a second; return whether it
    struck in any step, summoned in any, and dropped a rock in any."""
    var struck = False
    var summoned = False
    var rocked = False
    var steps = Int(seconds * 60 + 0.5)
    for _ in range(steps):
        var intent = boss.think(sight, Float32(1) / 60)
        struck = struck or intent.strikes
        summoned = summoned or intent.summon
        rocked = rocked or len(intent.rock) > 0
    return [struck, summoned, rocked]


def test_each_kind_knows_its_values() raises:
    for value in [-1, BOSS_ATTACKS]:
        assert_false(BossAttack(value).is_valid())
    for value in [0, BOSS_ATTACKS - 1]:
        assert_true(BossAttack(value).is_valid())
    for value in [-1, ZONE_SHAPES]:
        assert_false(ZoneShape(value).is_valid())
    for value in [0, ZONE_SHAPES - 1]:
        assert_true(ZoneShape(value).is_valid())
    for value in [-1, BOSS_PHASES]:
        assert_false(BossPhase(value).is_valid())
    for value in [0, BOSS_PHASES - 1]:
        assert_true(BossPhase(value).is_valid())


def test_a_point_lies_in_a_zone() raises:
    var circle = Zone(CIRCLE, Vector3(0, 0, 0), Vector3(0, 0, 1), 3, 0)
    assert_true(inside(circle, Vector3(2.9, 5, 0)))
    assert_false(inside(circle, Vector3(3.2, 0, 0)))
    assert_true(inside(circle, Vector3(3.2, 0, 0), 0.3))
    var line = Zone(LINE, Vector3(0, 0, 0), Vector3(0, 0, 1), 10, 2)
    assert_true(inside(line, Vector3(0.9, 0, 5)))
    assert_false(inside(line, Vector3(1.1, 0, 5)))
    assert_false(inside(line, Vector3(0, 0, -0.5)))
    assert_false(inside(line, Vector3(0, 0, 10.5)))
    assert_true(inside(line, Vector3(0, 0, 10.5), 0.6))
    var cone = Zone(CONE, Vector3(0, 0, 0), Vector3(0, 0, 1), 6, 90)
    assert_true(inside(cone, Vector3(0, 0, 0)))
    assert_true(inside(cone, Vector3(2, 0, 3)))
    assert_false(inside(cone, Vector3(3, 0, 2)))
    assert_false(inside(cone, Vector3(0, 0, 6.5)))
    assert_false(inside(cone, Vector3(0, 0, -2)))
    # A margin widens the cone by the angle it fills.
    assert_true(inside(cone, Vector3(3, 0, 2.6), 0.5))


def test_each_attack_has_its_data_and_name() raises:
    assert_equal(attack_data(CLEAVE).unblockable, False)
    assert_true(attack_data(SLAM).unblockable)
    assert_true(attack_data(STOMP).windup > attack_data(SLAM).windup)
    assert_equal(attack_data(CHARGE).damage, 220)
    assert_equal(attack_data(ROCKFALL).damage, ROCK_DAMAGE)
    assert_equal(attack_data(SUMMON).damage, 0)
    with assert_raises(contains="six"):
        _ = attack_data(BossAttack(6))
    assert_equal(attack_name(CLEAVE), "CLEAVE")
    assert_equal(attack_name(SUMMON), "SUMMON")
    with assert_raises(contains="six"):
        _ = attack_name(BossAttack(-1))


def test_the_phases_follow_the_health() raises:
    assert_true(phase_of(1) == OPENING)
    assert_true(phase_of(0.7) == FURY)
    assert_true(phase_of(0.36) == FURY)
    assert_true(phase_of(0.35) == LAST_STAND)
    assert_equal(phase_pace(OPENING), 1)
    assert_true(phase_pace(LAST_STAND) < phase_pace(FURY))
    assert_equal(len(rotation(OPENING)), 5)
    assert_equal(len(rotation(FURY)), 6)
    assert_equal(len(rotation(LAST_STAND)), 7)


def test_a_bosss_health_grows_with_its_party() raises:
    assert_equal(boss_health(1), BOSS_HEALTH)
    assert_almost_equal(
        boss_health(5), BOSS_HEALTH * (1 + 4 * PARTY_HEALTH), atol=1e-2
    )
    with assert_raises(contains="1 to 40"):
        _ = boss_health(0)
    with assert_raises(contains="1 to 40"):
        _ = boss_health(41)
    with assert_raises(contains="1 to 40"):
        _ = Boss(0, 1)


def test_a_rockfall_is_shared_by_those_near() raises:
    var members: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(2, 0, 0),
        Vector3(10, 0, 0),
    ]
    var up: List[Bool] = [True, True, False, True]
    var share = share_rockfall(Vector3(0, 0, 0), members, up)
    assert_almost_equal(share[0], ROCK_DAMAGE / 2, atol=1e-3)
    assert_almost_equal(share[1], ROCK_DAMAGE / 2, atol=1e-3)
    assert_equal(share[2], 0)
    assert_equal(share[3], 0)
    var alone = share_rockfall(Vector3(10, 0, 0), members, up)
    assert_almost_equal(alone[3], ROCK_DAMAGE, atol=1e-3)
    var nobody = share_rockfall(Vector3(0, 0, 0), List[Vector3](), List[Bool]())
    assert_equal(len(nobody), 0)
    var blow = rock_blow(200)
    assert_equal(blow.damage, 200)
    assert_true(blow.unblockable)


def test_threat_draws_the_boss_and_a_taunt_holds_it() raises:
    var boss = Boss(3, 5)
    assert_false(boss.engaged)
    boss.add_threat(1, 100)
    assert_true(boss.engaged)
    var up: List[Bool] = [True, True, True]
    boss.pick_target(up)
    assert_equal(boss.target, 1)
    # Another must pass the target's threat by the switch to draw it.
    boss.add_threat(2, 105)
    boss.pick_target(up)
    assert_equal(boss.target, 1)
    boss.add_threat(2, 10)
    boss.pick_target(up)
    assert_equal(boss.target, 2)
    # A taunt gives the taunter the most, and holds the boss on it.
    boss.taunt(0)
    assert_equal(boss.target, 0)
    assert_almost_equal(boss.threat[0], 115 * THREAT_SWITCH + 50, atol=1e-3)
    assert_almost_equal(boss.taunted, TAUNT_SECONDS, atol=1e-6)
    boss.add_threat(1, 1000)
    boss.pick_target(up)
    assert_equal(boss.target, 0)
    # A fallen target loses the boss, even taunted.
    var down: List[Bool] = [False, True, True]
    boss.pick_target(down)
    assert_equal(boss.target, 1)
    # With nobody standing, it keeps its target.
    var none: List[Bool] = [False, False, False]
    boss.taunted = 0
    boss.pick_target(none)
    assert_equal(boss.target, 1)
    with assert_raises(contains="no such"):
        boss.add_threat(3, 1)
    with assert_raises(contains="no such"):
        boss.add_threat(-1, 1)
    with assert_raises(contains="negative"):
        boss.add_threat(0, -1)
    with assert_raises(contains="no such"):
        boss.taunt(3)
    with assert_raises(contains="no such"):
        boss.taunt(-1)


def test_a_heal_draws_threat_once_the_fight_is_on() raises:
    var boss = Boss(2, 5)
    boss.healed(1, 100)
    assert_equal(boss.threat[1], 0)
    boss.engaged = True
    boss.healed(1, 100)
    assert_almost_equal(boss.threat[1], 100 * HEAL_THREAT, atol=1e-4)


def test_a_bosss_poise_breaks_and_it_staggers() raises:
    var boss = Boss(2, 5)
    var hit = boss.receive(_blow(100, 50), 0, False)
    assert_true(hit.outcome == HIT)
    assert_almost_equal(boss.poise, BOSS_POISE - 50, atol=1e-3)
    assert_almost_equal(boss.threat[0], 100, atol=1e-3)
    var tank = boss.receive(_blow(100, 50), 1, True)
    assert_true(tank.outcome == HIT)
    assert_almost_equal(boss.threat[1], 100 * TANK_THREAT, atol=1e-3)
    var broke = boss.receive(_blow(10, BOSS_POISE), 0, False)
    assert_true(broke.outcome == STAMINA_BREAK)
    assert_almost_equal(boss.staggered, BOSS_STAGGER, atol=1e-6)
    assert_false(boss.busy())
    var critical = boss.receive(_blow(100, 50), 0, False)
    assert_true(critical.outcome == CRITICAL)
    assert_almost_equal(critical.damage, 100 * STAGGER_BONUS, atol=1e-3)
    boss.health = 10
    var fell = boss.receive(_blow(100, 50), 0, False)
    assert_true(fell.outcome == DEFEATED)
    assert_true(boss.defeated())
    assert_true(boss.receive(_blow(100, 50), 0, False).outcome == IGNORED)
    with assert_raises(contains="no such"):
        _ = boss.receive(_blow(1, 1), 5, False)
    with assert_raises(contains="no such"):
        _ = boss.receive(_blow(1, 1), -1, False)


def test_a_party_links_its_strike_once_in_a_stagger() raises:
    assert_almost_equal(link_damage(1), LINK_DAMAGE, atol=1e-3)
    assert_almost_equal(link_damage(5), 2400, atol=1e-2)
    assert_true(link_damage(3) > 3 * link_damage(1))
    with assert_raises(contains="from 1 to 40"):
        _ = link_damage(0)
    with assert_raises(contains="from 1 to 40"):
        _ = link_damage(41)
    var boss = Boss(3, 5)
    var pair: List[Int] = [0, 2]
    # Before a stagger, it does nothing.
    assert_false(boss.link_ready())
    assert_true(boss.link(pair).outcome == IGNORED)
    _ = boss.receive(_blow(10, BOSS_POISE), 0, False)
    assert_true(boss.link_ready())
    var health = boss.health
    var linked = boss.link(pair)
    assert_true(linked.outcome == CRITICAL)
    assert_almost_equal(linked.damage, link_damage(2), atol=1e-3)
    assert_almost_equal(boss.health, health - link_damage(2), atol=1e-2)
    assert_almost_equal(boss.threat[2], link_damage(2) / 2, atol=1e-3)
    # It strikes once in each stagger.
    assert_false(boss.link_ready())
    assert_true(boss.link(pair).outcome == IGNORED)
    boss.staggered = 0
    boss.poise = 1
    _ = boss.receive(_blow(10, 5), 0, False)
    assert_true(boss.link_ready())
    # It can fell the boss.
    boss.health = 10
    assert_true(boss.link(pair).outcome == DEFEATED)
    assert_equal(boss.health, 0)
    var fallen = Boss(1, 5)
    fallen.staggered = 1
    fallen.health = 0
    assert_false(fallen.link_ready())
    # Its members must be in the party, each once.
    with assert_raises(contains="a member"):
        _ = boss.link(List[Int]())
    var stranger: List[Int] = [0, 3]
    with assert_raises(contains="no such"):
        _ = boss.link(stranger)
    var negative: List[Int] = [-1]
    with assert_raises(contains="no such"):
        _ = boss.link(negative)
    var twice: List[Int] = [1, 1]
    with assert_raises(contains="once"):
        _ = boss.link(twice)


def test_a_boss_waits_until_a_member_comes_near() raises:
    var home = Vector3(0, 0, 0)
    var boss = Boss(1, 5)
    var far: List[Vector3] = [Vector3(0, 0, AGGRO_RANGE + 5)]
    var intent = boss.think(_sight(home, far), 0.1)
    assert_false(boss.engaged)
    assert_equal(intent.way.length(), 0)
    # Near, it engages and walks to its target.
    var near: List[Vector3] = [Vector3(0, 0, AGGRO_RANGE - 1)]
    var walk = boss.think(_sight(home, near), 0.1)
    assert_true(boss.engaged)
    assert_almost_equal(walk.way.z, 1, atol=1e-5)
    assert_true(walk.face)
    with assert_raises(contains="negative"):
        _ = boss.think(_sight(home, near), -1)
    var two: List[Vector3] = [near[0], near[0]]
    with assert_raises(contains="one place"):
        _ = boss.think(_sight(home, two), 0.1)
    var unsure = BossSight(
        home, Vector3(0, 0, 1), home, near.copy(), [True, True]
    )
    with assert_raises(contains="one place"):
        _ = boss.think(unsure, 0.1)


def test_a_boss_lays_its_zone_and_strikes_as_the_windup_ends() raises:
    var home = Vector3(0, 0, 0)
    var boss = Boss(1, 5)
    var close: List[Vector3] = [Vector3(0, 0, 2)]
    var sight = _sight(home, close)
    var first = boss.think(sight, 0.01)
    assert_true(boss.busy())
    assert_true(boss.attack == CLEAVE)
    assert_true(first.zone.shape == CONE)
    assert_true(boss.warning() >= 0)
    var wind = boss.windup()
    assert_almost_equal(wind, attack_data(CLEAVE).windup, atol=1e-5)
    var steps = _think(boss, sight, wind + 0.05)
    assert_true(steps[0])
    assert_equal(boss.warning(), 0)
    # The cleave's blow; then it recovers, and slams.
    var blow = boss.attack_blow()
    assert_equal(blow.damage, attack_data(CLEAVE).damage)
    assert_false(blow.unblockable)
    _ = _think(boss, sight, attack_data(CLEAVE).recovery + 0.1)
    assert_true(boss.attack == SLAM)
    assert_true(boss.zone.shape == CIRCLE)
    var idle = Boss(1, 5)
    assert_equal(idle.windup(), 0)
    assert_equal(idle.warning(), 0)
    with assert_raises(contains="no attack"):
        _ = idle.attack_blow()


def test_a_boss_works_through_its_rotation() raises:
    var home = Vector3(0, 0, 0)
    var boss = Boss(2, 5)
    var members: List[Vector3] = [Vector3(0, 0, 2), Vector3(1, 0, 2)]
    var sight = _sight(home, members)
    var seen = List[Bool](length=BOSS_ATTACKS, fill=False)
    var rocked = False
    for _ in range(60 * 20):
        var intent = boss.think(sight, Float32(1) / 60)
        if boss.busy():
            seen[boss.attack.value] = True
        rocked = rocked or len(intent.rock) > 0
        if boss.attack == ROCKFALL:
            assert_true(boss.marked >= 0)
    assert_true(seen[CLEAVE.value])
    assert_true(seen[SLAM.value])
    assert_true(seen[ROCKFALL.value])
    assert_true(seen[STOMP.value])
    assert_true(rocked)


def test_a_boss_charges_at_range_and_runs_its_line() raises:
    var home = Vector3(0, 0, 0)
    var boss = Boss(1, 5)
    boss.engaged = True
    boss.turn = 3
    boss.phase = FURY
    boss.health = boss.most * 0.6
    boss.summoned[0] = True
    var far: List[Vector3] = [Vector3(0, 0, 9)]
    var sight = _sight(home, far)
    _ = boss.think(sight, 0.01)
    assert_true(boss.attack == CHARGE)
    assert_true(boss.zone.shape == LINE)
    var charged = False
    var struck = False
    for _ in range(60 * 3):
        var intent = boss.think(sight, Float32(1) / 60)
        charged = charged or intent.charging
        struck = struck or intent.strikes
    assert_true(charged)
    assert_true(struck)
    assert_true(CHARGE_LENGTH / CHARGE_SPEED > 1)


def test_a_boss_summons_as_a_later_phase_begins() raises:
    var home = Vector3(0, 0, 0)
    var boss = Boss(1, 5)
    boss.engaged = True
    boss.health = boss.most * 0.5
    var close: List[Vector3] = [Vector3(0, 0, 2)]
    var sight = _sight(home, close)
    _ = boss.think(sight, 0.01)
    assert_true(boss.attack == SUMMON)
    var steps = _think(boss, sight, 1.5)
    assert_true(steps[1])
    assert_false(steps[0])
    assert_true(boss.summoned[0])
    # In its last stand it summons once more.
    boss.health = boss.most * 0.2
    _ = _think(boss, sight, 4)
    assert_true(boss.summoned[1])


def test_a_staggered_boss_makes_no_attack() raises:
    var home = Vector3(0, 0, 0)
    var boss = Boss(1, 5)
    var close: List[Vector3] = [Vector3(0, 0, 2)]
    var sight = _sight(home, close)
    _ = boss.think(sight, 0.01)
    _ = boss.receive(_blow(1, BOSS_POISE + 1), 0, False)
    var steps = _think(boss, sight, BOSS_STAGGER - 0.5)
    assert_false(steps[0])
    assert_true(boss.staggered > 0)
    _ = _think(boss, sight, 1)
    assert_equal(boss.staggered, 0)
    assert_equal(boss.poise, BOSS_POISE)


def test_poise_comes_back_after_the_last_blow() raises:
    var home = Vector3(0, 0, 0)
    var boss = Boss(1, 5)
    var close: List[Vector3] = [Vector3(0, 0, 2)]
    var sight = _sight(home, close)
    _ = boss.think(sight, 0.01)
    _ = boss.receive(_blow(1, 300), 0, False)
    _ = _think(boss, sight, POISE_DELAY * 0.5)
    assert_almost_equal(boss.poise, BOSS_POISE - 300, atol=1e-3)
    _ = _think(boss, sight, POISE_DELAY + 1)
    assert_true(boss.poise > BOSS_POISE - 300)


def test_a_boss_goes_home_and_heals_when_its_party_falls() raises:
    var home = Vector3(0, 0, 0)
    var boss = Boss(1, 5)
    var close: List[Vector3] = [Vector3(0, 0, 2)]
    _ = boss.think(_sight(home, close), 0.01)
    boss.health = 100
    var gone = BossSight(
        Vector3(0, 0, 5), Vector3(0, 0, 1), home, close.copy(), [False]
    )
    var intent = boss.think(gone, 0.1)
    assert_equal(boss.health, boss.most)
    assert_false(boss.engaged)
    assert_almost_equal(intent.way.z, -1, atol=1e-5)
    # At home, it stands still.
    var there = BossSight(home, Vector3(0, 0, 1), home, close.copy(), [False])
    assert_equal(boss.think(there, 0.1).way.length(), 0)
    # Led too far from home, it goes back too.
    var led = Boss(1, 5)
    var away = Vector3(0, 0, LEASH_RANGE + 5)
    var chase: List[Vector3] = [away + Vector3(0, 0, 1)]
    var leash = BossSight(away, Vector3(0, 0, 1), home, chase.copy(), [True])
    _ = led.think(leash, 0.1)
    assert_false(led.engaged)


def test_a_fallen_boss_does_nothing() raises:
    var boss = Boss(1, 5)
    boss.health = 0
    var close: List[Vector3] = [Vector3(0, 0, 2)]
    var intent = boss.think(_sight(Vector3(0, 0, 0), close), 0.1)
    assert_false(intent.strikes)
    assert_equal(intent.way.length(), 0)


def test_a_boss_enrages_after_its_time() raises:
    var boss = Boss(1, 5)
    assert_false(boss.enraged())
    assert_equal(boss.power(), 1)
    boss.fight_time = ENRAGE_SECONDS
    assert_true(boss.enraged())
    assert_equal(boss.power(), ENRAGE_POWER)
    assert_almost_equal(boss.pace(), 0.5, atol=1e-6)
    var rolls = Boss(1, 9)
    var a = rolls.roll()
    var b = rolls.roll()
    assert_true(a != b)
    assert_true(a >= 0 and a <= 1)


def test_a_rockfall_marks_another_member_and_falls_on_them() raises:
    var home = Vector3(0, 0, 0)
    var boss = Boss(3, 5)
    boss.engaged = True
    boss.turn = 3
    var members: List[Vector3] = [
        Vector3(0, 0, 2),
        Vector3(2, 0, 2),
        Vector3(-2, 0, 2),
    ]
    var sight = _sight(home, members)
    _ = boss.think(sight, 0.01)
    assert_true(boss.attack == ROCKFALL)
    assert_true(boss.marked >= 0)
    assert_true(boss.marked != boss.target)
    assert_almost_equal(boss.zone.size, ROCK_RADIUS, atol=1e-6)
    var steps = _think(boss, sight, 4.5)
    assert_true(steps[2])
    assert_equal(boss.marked, -1)
    # With one member down, the mark passes it by.
    var lone = Boss(2, 7)
    lone.engaged = True
    lone.turn = 3
    var pair: List[Vector3] = [Vector3(0, 0, 2), Vector3(1, 0, 2)]
    var half = BossSight(
        home, Vector3(0, 0, 1), home, pair.copy(), [True, False]
    )
    _ = lone.think(half, 0.01)
    assert_equal(lone.marked, 0)
    # A party of one is marked itself.
    var solo = Boss(1, 5)
    var one: List[Vector3] = [Vector3(0, 0, 2)]
    solo._begin(ROCKFALL, _sight(home, one))
    assert_equal(solo.marked, 0)
    # When the next member is down too, the mark falls on the target.
    var trio: List[Vector3] = [
        Vector3(0, 0, 2),
        Vector3(1, 0, 2),
        Vector3(-1, 0, 2),
    ]
    for seed in range(8):
        var few = Boss(3, seed)
        var alone = BossSight(
            home, Vector3(0, 0, 1), home, trio.copy(), [True, False, False]
        )
        few._begin(ROCKFALL, alone)
        assert_equal(few.marked, 0)
    # A frame as long as its wind-up does not strike with its zone.
    var long = Boss(1, 5)
    long.engaged = True
    long._begin(ROCKFALL, _sight(home, one))
    assert_false(long.think(_sight(home, one), 5).strikes)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
