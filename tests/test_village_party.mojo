# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A raid party: each role's spot and style, the way out of a zone, and
what each member decides to do."""

from extensions.village.boss import CIRCLE, CONE, LINE, Zone
from extensions.village.combat import (
    AIMED_SHOT,
    FREE,
    HEAVY,
    LIGHT_ONE,
    LIGHT_THREE,
    LIGHT_TWO,
    MEND,
    QUICK_SHOT,
    SPELL_BOLT,
)
from extensions.village.party import (
    ARCHER,
    ARCHER_SPOT,
    DODGE_AT,
    FOLLOW_GAP,
    HEALER,
    HEALER_SPOT,
    ROLES,
    STRIKER,
    STRIKER_SPOT,
    TANK,
    TANK_SPOT,
    TAUNT_EVERY,
    MemberSight,
    PartyMind,
    PartyRole,
    escape,
    role_name,
    role_style,
    still_intent,
)
from extensions.village.styles import ARCHERY, AXE, MACE, MAGIC
from math.vector3 import Vector3
from std.math import sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def _sight(at: Vector3) -> MemberSight:
    """Return a member's sight in a fight with a foe at the origin facing
    plus z, the leader 5 meters behind the foe's front, and nothing else."""
    return MemberSight(
        at,
        Vector3(0, 0, 5),
        Vector3(0, 0, 0),
        Vector3(0, 0, 1),
        None,
        0,
        False,
        None,
        1,
        None,
        None,
        True,
        True,
        True,
    )


def _gap(a: Vector3, b: Vector3) -> Float32:
    """Return how far apart two points are on the ground."""
    var dx = b.x - a.x
    var dz = b.z - a.z
    return sqrt(dx * dx + dz * dz)


def test_each_role_knows_its_name_and_style() raises:
    for value in [-1, ROLES]:
        assert_false(PartyRole(value).is_valid())
    for value in [0, ROLES - 1]:
        assert_true(PartyRole(value).is_valid())
    assert_equal(role_name(TANK), "TANK")
    assert_equal(role_name(ARCHER), "ARCHER")
    with assert_raises(contains="four"):
        _ = role_name(PartyRole(4))
    assert_true(role_style(TANK) == MACE)
    assert_true(role_style(HEALER) == MAGIC)
    assert_true(role_style(STRIKER) == AXE)
    assert_true(role_style(ARCHER) == ARCHERY)
    with assert_raises(contains="four"):
        _ = role_style(PartyRole(-1))
    with assert_raises(contains="four"):
        _ = PartyMind(PartyRole(4))
    var nothing = still_intent()
    assert_true(nothing.attack == FREE)
    assert_false(nothing.guard)


def test_each_role_has_its_spot() raises:
    var sight = _sight(Vector3(0, 0, 0))
    var tank = PartyMind(TANK).spot(sight)
    assert_almost_equal(tank.z, TANK_SPOT, atol=1e-5)
    var striker = PartyMind(STRIKER).spot(sight)
    assert_almost_equal(striker.z, -STRIKER_SPOT, atol=1e-5)
    var archer = PartyMind(ARCHER).spot(sight)
    assert_almost_equal(_gap(archer, Vector3(0, 0, 0)), ARCHER_SPOT, atol=1e-4)
    var healer = PartyMind(HEALER).spot(sight)
    assert_almost_equal(healer.z, 5 + HEALER_SPOT, atol=1e-5)
    # A leader on the foe: the healer stands off the foe's front.
    sight.leader = Vector3(0, 0, 0)
    var close = PartyMind(HEALER).spot(sight)
    assert_almost_equal(close.z, HEALER_SPOT, atol=1e-5)


def test_the_way_out_of_a_zone_is_the_shortest() raises:
    var circle = Zone(CIRCLE, Vector3(0, 0, 0), Vector3(0, 0, 1), 5, 0)
    var out = escape(circle, Vector3(2, 0, 0))
    assert_almost_equal(out.x, 1, atol=1e-5)
    var middle = escape(circle, Vector3(0, 0, 0))
    assert_equal(middle.x, 1)
    var line = Zone(LINE, Vector3(0, 0, 0), Vector3(0, 0, 1), 10, 3)
    var side = escape(line, Vector3(0.5, 0, 4))
    assert_almost_equal(side.x, 1, atol=1e-5)
    var other = escape(line, Vector3(-0.5, 0, 4))
    assert_almost_equal(other.x, -1, atol=1e-5)
    var cone = Zone(CONE, Vector3(0, 0, 0), Vector3(0, 0, 1), 6, 90)
    var across = escape(cone, Vector3(-1, 0, 3))
    assert_almost_equal(across.x, -1, atol=1e-5)


def test_out_of_a_fight_a_member_follows() raises:
    var mind = PartyMind(STRIKER)
    var sight = _sight(Vector3(0, 0, 0))
    sight.fighting = False
    sight.leader = Vector3(0, 0, 10)
    var intent = mind.think(sight, 0.1)
    assert_almost_equal(intent.way.z, 1, atol=1e-5)
    assert_true(intent.run)
    sight.leader = Vector3(0, 0, FOLLOW_GAP + 1)
    assert_false(mind.think(sight, 0.1).run)
    sight.leader = Vector3(0, 0, 1)
    assert_equal(mind.think(sight, 0.1).way.length(), 0)
    # With no foe, the same.
    var none = _sight(Vector3(0, 0, 0))
    none.target = None
    none.leader = Vector3(0, 0, 1)
    assert_equal(mind.think(none, 0.1).way.length(), 0)


def test_a_healer_revives_the_fallen_out_of_a_fight() raises:
    var mind = PartyMind(HEALER)
    var sight = _sight(Vector3(0, 0, 0))
    sight.fighting = False
    sight.leader = Vector3(0, 0, 0)
    sight.fallen = Vector3(4, 0, 0)
    var walk = mind.think(sight, 0.1)
    assert_almost_equal(walk.way.x, 1, atol=1e-5)
    assert_false(walk.revive)
    sight.fallen = Vector3(1, 0, 0)
    assert_true(mind.think(sight, 0.1).revive)
    # Another role does not.
    var striker = PartyMind(STRIKER)
    assert_false(striker.think(sight, 0.1).revive)


def test_a_member_steps_out_of_a_zone_and_dodges_late() raises:
    var mind = PartyMind(STRIKER)
    var sight = _sight(Vector3(0, 0, -2))
    sight.danger = Zone(CIRCLE, Vector3(0, 0, 0), Vector3(0, 0, 1), 5, 0)
    sight.warning = 0.3
    var step = mind.think(sight, 0.1)
    assert_almost_equal(step.way.z, -1, atol=1e-5)
    assert_true(step.run)
    assert_equal(step.dodge.length(), 0)
    sight.warning = DODGE_AT
    var dodge = mind.think(sight, 0.1)
    assert_almost_equal(dodge.dodge.z, -1, atol=1e-5)
    # A member in a move does not dodge.
    sight.free = False
    assert_equal(mind.think(sight, 0.1).dodge.length(), 0)
    # Out of the zone, it goes about its fight.
    var safe = _sight(Vector3(0, 0, -9))
    safe.danger = sight.danger
    safe.warning = 0.9
    assert_equal(mind.think(safe, 0.1).dodge.length(), 0)


def test_a_tank_guards_a_blow_its_guard_stops() raises:
    var mind = PartyMind(TANK)
    var sight = _sight(Vector3(0, 0, 2))
    sight.danger = Zone(CONE, Vector3(0, 0, 0), Vector3(0, 0, 1), 6, 120)
    sight.warning = 0.9
    sight.blockable = True
    var guard = mind.think(sight, 0.1)
    assert_true(guard.guard)
    assert_equal(guard.way.length(), 0)
    # A blow no guard stops sends it out too.
    sight.blockable = False
    var out = mind.think(sight, 0.1)
    assert_false(out.guard)
    assert_true(out.way.length() > 0)
    # Out of a zone it could guard, it fights on.
    var clear = _sight(Vector3(0, 0, -8))
    clear.danger = sight.danger
    clear.blockable = True
    clear.targeted = True
    assert_false(mind.think(clear, 0.1).guard)


def test_the_party_gathers_on_a_marked_member() raises:
    var mind = PartyMind(ARCHER)
    var sight = _sight(Vector3(0, 0, -5))
    sight.stack = Vector3(4, 0, -5)
    var run = mind.think(sight, 0.1)
    assert_almost_equal(run.way.x, 1, atol=1e-5)
    assert_true(run.run)
    sight.stack = Vector3(0.5, 0, -5)
    var there = mind.think(sight, 0.1)
    assert_false(there.run and there.way.x > 0.9)


def test_a_tank_taunts_a_boss_that_fights_another() raises:
    var mind = PartyMind(TANK)
    var sight = _sight(Vector3(0, 0, TANK_SPOT))
    sight.targeted = False
    assert_true(mind.think(sight, 0.1).taunt)
    assert_false(mind.think(sight, 0.1).taunt)
    assert_true(mind.think(sight, TAUNT_EVERY).taunt)
    sight.targeted = True
    assert_false(mind.think(sight, TAUNT_EVERY).taunt)
    # Another role never taunts.
    var other = PartyMind(STRIKER)
    sight.targeted = False
    assert_false(other.think(sight, 0.1).taunt)


def test_a_healer_mends_the_hurt() raises:
    var mind = PartyMind(HEALER)
    var sight = _sight(Vector3(0, 0, 10))
    sight.hurt = Vector3(0, 0, 5)
    assert_true(mind.think(sight, 0.1).attack == MEND)
    # It waits before it mends again.
    assert_false(mind.think(sight, 0.1).attack == MEND)
    # A healer in a move does not mend.
    var busy = PartyMind(HEALER)
    sight.free = False
    assert_false(busy.think(sight, 0.1).attack == MEND)
    # With nobody hurt, it casts bolts.
    var calm = PartyMind(HEALER)
    var plain = _sight(Vector3(0, 0, 10))
    calm.wait = 0
    assert_true(calm.think(plain, 0.1).attack == SPELL_BOLT)


def test_each_role_makes_its_chain() raises:
    var tank = PartyMind(TANK)
    tank.taunt_wait = 100
    var at = _sight(Vector3(0, 0, TANK_SPOT))
    at.targeted = True
    var tanked = List[Int]()
    for _ in range(4):
        tank.wait = 0
        tanked.append(tank.think(at, 0.01).attack.value)
    assert_equal(tanked[0], LIGHT_ONE.value)
    assert_equal(tanked[1], LIGHT_TWO.value)
    assert_equal(tanked[2], HEAVY.value)
    assert_equal(tanked[3], LIGHT_ONE.value)
    var striker = PartyMind(STRIKER)
    var behind = _sight(Vector3(0, 0, -STRIKER_SPOT))
    var struck = List[Int]()
    for _ in range(4):
        striker.wait = 0
        struck.append(striker.think(behind, 0.01).attack.value)
    assert_equal(struck[2], LIGHT_THREE.value)
    assert_equal(struck[3], HEAVY.value)
    var archer = PartyMind(ARCHER)
    var shots = List[Int]()
    var spot = archer.spot(_sight(Vector3(0, 0, 0)))
    for _ in range(3):
        archer.wait = 0
        shots.append(archer.think(_sight(spot), 0.01).attack.value)
    assert_equal(shots[0], QUICK_SHOT.value)
    assert_equal(shots[2], AIMED_SHOT.value)
    # Between two presses it waits.
    assert_true(archer.think(_sight(spot), 0.01).attack == FREE)


def test_a_melee_member_goes_to_its_spot_before_it_strikes() raises:
    var striker = PartyMind(STRIKER)
    striker.wait = 0
    var far = striker.think(_sight(Vector3(0, 0, -9)), 0.01)
    assert_true(far.attack == FREE)
    assert_true(far.run)
    assert_true(far.way.z > 0.9)
    var near = striker.think(_sight(Vector3(0, 0, -4)), 0.01)
    assert_false(near.run)
    # A ranged member shoots on its way.
    var archer = PartyMind(ARCHER)
    archer.wait = 0
    var walking = archer.think(_sight(Vector3(0, 0, 4)), 0.01)
    assert_true(walking.way.length() > 0)
    assert_true(walking.attack == QUICK_SHOT)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
