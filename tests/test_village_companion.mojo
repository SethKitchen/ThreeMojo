# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The companion's mind: she follows, keeps back, casts, heals, and fills
her assist gauge."""

from extensions.humanoid.sex import FEMALE
from extensions.village.companion import (
    ASSIST_FULL,
    ASSIST_RATE,
    CAST_EVERY,
    KEEP,
    MEND_EVERY,
    AllySight,
    Companion,
    ally_fighter,
    assist_blow,
    default_allies,
    FOLLOW,
    DOOR_INSIDE,
    DOOR_OUTSIDE,
    flank_spot,
    follow_point,
    Climb,
    ally_goal,
    no_climb,
    climb_step,
    CLIMB_RISE,
)
from extensions.village.interior import Doorway
from math.vector3 import Vector3
from std.math import cos, pi
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)
from units.si import METER_PER_SECOND, SECOND, Duration


def _sight(
    player: Vector3,
    target: Optional[Vector3] = None,
    health: Float32 = 1,
    free: Bool = True,
    fighting: Bool = True,
) -> AllySight:
    """Return what a companion at the middle knows."""
    return AllySight(Vector3(0, 0, 0), player, target, health, free, fighting)


def _frame() -> Duration:
    """Return a frame of a tenth of a second."""
    return Duration(0.1, SECOND)


def test_out_of_a_fight_she_follows_the_player() raises:
    var mind = Companion()
    # Near the player, she stands.
    var near = mind.think(_sight(Vector3(0, 0, 2), fighting=False), _frame())
    assert_almost_equal(near.way.length(), 0, atol=1e-6)
    assert_false(near.face)
    # Further, she walks to them; further still, she runs.
    var walk = mind.think(_sight(Vector3(0, 0, 5), fighting=False), _frame())
    assert_almost_equal(walk.way.z, 1, atol=1e-6)
    assert_false(walk.run)
    var run = mind.think(_sight(Vector3(9, 0, 0), fighting=False), _frame())
    assert_almost_equal(run.way.x, 1, atol=1e-6)
    assert_true(run.run)
    # A foe outside a fight does not hold her; the gauge does not fill.
    var calm = mind.think(
        _sight(Vector3(0, 0, 5), Vector3(4, 0, 0), fighting=False), _frame()
    )
    assert_almost_equal(calm.way.z, 1, atol=1e-6)
    assert_false(calm.cast)
    assert_almost_equal(mind.assist, 0, atol=1e-6)
    # On the player's own spot, she stands.
    var still = mind.think(_sight(Vector3(0, 0, 0)), _frame())
    assert_almost_equal(still.way.length(), 0, atol=1e-6)
    # In a fight with no foe to cast at, she follows too.
    var lost = mind.think(_sight(Vector3(0, 0, 5)), _frame())
    assert_almost_equal(lost.way.z, 1, atol=1e-6)


def _at(
    at: Vector3, player: Vector3, target: Vector3, free: Bool = True
) -> AllySight:
    """Return what a companion at `at` knows in a fight."""
    return AllySight(at, player, target, 1, free, True)


def test_in_a_fight_she_flanks_the_foe_and_casts() raises:
    var target = Vector3(0, 0, -6)
    var player = Vector3(0, 0, -4)
    # Her spot is `KEEP` from the foe, off the line to the player, on the
    # side she stands on.
    var right = flank_spot(target, player, Vector3(3, 0, 0))
    var left = flank_spot(target, player, Vector3(-3, 0, 0))
    assert_almost_equal((right - target).length(), KEEP, atol=1e-4)
    assert_almost_equal(
        (right - target).z, KEEP * cos(Float32(pi * 70 / 180)), atol=1e-4
    )
    assert_true(right.x > 4)
    assert_true(left.x < -4)
    var mind = Companion()
    # Away from her spot, she runs to it, facing the foe; her first cast
    # waits.
    var at = Vector3(3, 0, 0)
    var run = mind.think(_at(at, player, target), _frame())
    var to_spot = (right - at) / (right - at).length()
    assert_true(run.way.x * to_spot.x + run.way.z * to_spot.z > 0.99)
    assert_true(run.run)
    assert_true(run.face)
    assert_false(run.cast)
    # Near it, she walks.
    var walk = mind.think(
        _at(right + Vector3(2, 0, 0), player, target), _frame()
    )
    assert_true(walk.way.x < -0.9)
    assert_false(walk.run)
    # At her spot, she stands, and casts once her wait is over.
    mind.cast_wait = 0
    var cast = mind.think(_at(right, player, target), _frame())
    assert_almost_equal(cast.way.length(), 0, atol=1e-6)
    assert_true(cast.cast)
    assert_almost_equal(mind.cast_wait, CAST_EVERY, atol=1e-6)
    # She does not cast while her wait lasts, nor while she makes a move.
    assert_false(mind.think(_at(right, player, target), _frame()).cast)
    mind.cast_wait = 0
    var busy = mind.think(_at(right, player, target, False), _frame())
    assert_false(busy.cast)
    # Past her reach, she does not cast.
    var far = mind.think(
        _at(Vector3(0, 0, 0), player, Vector3(0, 0, -25)), _frame()
    )
    assert_false(far.cast)
    # She never strays far from the player.
    var leash = mind.think(
        _sight(Vector3(12, 0, 0), Vector3(0, 0, 6)), _frame()
    )
    assert_almost_equal(leash.way.x, 1, atol=1e-6)
    assert_true(leash.run)


def test_she_heals_a_wounded_player() raises:
    var mind = Companion()
    var player = Vector3(0, 0, 1)
    # A healthy player, or a fallen one, is not healed.
    assert_false(mind.think(_sight(player, health=0.5), _frame()).heal)
    assert_false(mind.think(_sight(player, health=0), _frame()).heal)
    # Nor while she makes a move.
    assert_false(
        mind.think(_sight(player, health=0.3, free=False), _frame()).heal
    )
    var heal = mind.think(_sight(player, health=0.3), _frame())
    assert_true(heal.heal)
    assert_almost_equal(mind.mend_wait, MEND_EVERY, atol=1e-6)
    # Then she waits.
    assert_false(mind.think(_sight(player, health=0.3), _frame()).heal)


def test_the_assist_gauge_fills_and_is_spent() raises:
    var mind = Companion()
    assert_false(mind.ready())
    assert_false(mind.spend())
    _ = mind.think(_sight(Vector3(0, 0, 1)), Duration(2.0, SECOND))
    assert_almost_equal(mind.assist, 2 * ASSIST_RATE, atol=1e-4)
    mind.charge(1000)
    assert_almost_equal(mind.assist, ASSIST_FULL, atol=1e-6)
    assert_true(mind.ready())
    mind.cast_wait = 0
    assert_true(mind.spend())
    assert_almost_equal(mind.assist, 0, atol=1e-6)
    assert_almost_equal(mind.cast_wait, CAST_EVERY, atol=1e-6)


def test_her_strength_and_her_assist_attack() raises:
    ally_fighter().check()
    assert_almost_equal(ally_fighter().health, 400, atol=1e-6)
    var blow = assist_blow(2)
    assert_almost_equal(blow.damage, 140, atol=1e-4)
    assert_almost_equal(blow.stamina_damage, 100, atol=1e-4)
    assert_almost_equal(blow.knockback.to(METER_PER_SECOND), 5, atol=1e-6)
    assert_true(blow.unblockable)
    assert_true(blow.breaks_pierce)
    assert_false(blow.finish)
    var allies = default_allies()
    assert_equal(len(allies), 1)
    assert_true(allies[0].spec.sex == FEMALE)


def test_she_goes_into_a_house_by_its_door() raises:
    # Two doors a meter wide, each opening into its house along +z.
    var doors: List[Doorway] = [
        Doorway(0, 0, 1, 0, 0, 1, 1, 2.1, 0, True),
        Doorway(50, 0, 1, 0, 0, 1, 1, 2.1, 0, True),
    ]
    var player = Vector3(0.5, 0, 5)
    var far = Vector3(0.5, 0, -10)
    # Outdoors, or both indoors, or with no doors, she follows the player.
    var none = List[Doorway]()
    for case_ in [(False, False), (True, True)]:
        var goal = follow_point(far, player, case_[0], case_[1], doors)
        assert_almost_equal((goal - player).length(), 0, atol=1e-6)
    var bare = follow_point(far, player, True, False, none)
    assert_almost_equal((bare - player).length(), 0, atol=1e-6)
    # Far from the door, before it; `FOLLOW` past that, so she stops there.
    var before = follow_point(far, player, True, False, doors)
    assert_almost_equal(before.z, -DOOR_OUTSIDE + FOLLOW, atol=1e-5)
    assert_almost_equal(before.x, 0.5, atol=1e-5)
    # At the door, in past it.
    var at = Vector3(0.5, 0, -1)
    var inside = follow_point(at, player, True, False, doors)
    assert_almost_equal(inside.z, DOOR_INSIDE + FOLLOW, atol=1e-5)
    # The door nearest the player is the one she goes to.
    var other = follow_point(far, Vector3(50.5, 0, 5), True, False, doors)
    assert_true(other.x > 40)


def test_she_climbs_a_houses_stairs_point_by_point() raises:
    # The foot of a flight, its top, and round the landing.
    var way: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(0, 3, -4),
        Vector3(1, 3, -4),
        Vector3(1, 3, 0),
    ]
    # She starts at the first point on her own story, and walks to it.
    assert_equal(climb_step(Vector3(0, 0, 2), way, -1), 0)
    # At it, she goes on to the next.
    assert_equal(climb_step(Vector3(0, 0.2, 0.2), way, 0), 1)
    # Over it, but not on it, she walks on to it.
    assert_equal(climb_step(Vector3(0, 1, 0), way, 0), 0)
    # Round the landing, point by point; at the top, she stays.
    assert_equal(climb_step(Vector3(1, 3, -3.8), way, 2), 3)
    assert_equal(climb_step(Vector3(1, 3, 0), way, 3), 3)
    # On no story of the way, she walks to its top; a step past the way
    # starts again.
    assert_equal(climb_step(Vector3(5, 10, 5), way, -1), 3)
    assert_equal(climb_step(Vector3(0, 0, 2), way, 7), 0)


def test_indoors_she_climbs_up_and_down_and_goes_out_by_the_door() raises:
    # A door into the house along +z; the way up from its foot to the top.
    var doors: List[Doorway] = [Doorway(0, 0, 1, 0, 0, 1, 1, 2.1, 0, True)]
    var way: List[Vector3] = [Vector3(0.5, 0, 3), Vector3(0.5, 3, -1)]
    var climbs: List[List[Vector3]] = [way.copy()]
    var below = Vector3(0.5, 0, 6)
    var above = Vector3(0.5, 3, 2)
    var still = no_climb()
    # Up to the player above her: to the foot of the stairs.
    var up = ally_goal(below, above, True, True, doors, climbs, still)
    assert_equal(up[1].step, 0)
    assert_false(up[1].down)
    assert_almost_equal(up[0].z, 3 - FOLLOW, atol=1e-5)
    # Outdoors she does not climb; on one story, nor with no doors or no
    # way up.
    var none = List[Doorway]()
    var bare = List[List[Vector3]]()
    var flat: List[List[Vector3]] = [List[Vector3]()]
    var level = Vector3(0.5, 0, 2)
    assert_equal(
        ally_goal(below, above, True, False, doors, climbs, still)[1].step, -1
    )
    assert_equal(
        ally_goal(below, level, True, True, doors, climbs, still)[1].step, -1
    )
    assert_equal(
        ally_goal(below, above, True, True, none, climbs, still)[1].step, -1
    )
    assert_equal(
        ally_goal(below, above, True, True, doors, bare, still)[1].step, -1
    )
    assert_equal(
        ally_goal(below, above, True, True, doors, flat, still)[1].step, -1
    )
    # A meter above her: too little to start a climb, but enough to go on.
    var near = Vector3(0.5, 1, 2)
    assert_true(Float32(1) < CLIMB_RISE)
    assert_equal(
        ally_goal(below, near, True, True, doors, climbs, still)[1].step, -1
    )
    var going = Climb(0, False)
    assert_equal(
        ally_goal(below, near, True, True, doors, climbs, going)[1].step, 0
    )
    # Down to a player below her: the way from the top.
    var top = Vector3(0.5, 3, -1)
    var down = ally_goal(top, below, True, True, doors, climbs, still)
    assert_true(down[1].down)
    assert_equal(down[1].step, 1)
    # The player gone out: down the stairs, then out by the door.
    var leave = ally_goal(
        top, Vector3(0.5, 0, -6), False, True, doors, climbs, still
    )
    assert_true(leave[1].down)
    var hall = Vector3(0.5, 0, 4)
    var inner = ally_goal(
        hall, Vector3(0.5, 0, -6), False, True, doors, climbs, still
    )
    assert_equal(inner[1].step, -1)
    assert_almost_equal(inner[0].z, DOOR_INSIDE - FOLLOW, atol=1e-5)
    var sill = Vector3(0.5, 0, 0.5)
    var past = ally_goal(
        sill, Vector3(0.5, 0, -6), False, True, doors, climbs, still
    )
    assert_almost_equal(past[0].z, -DOOR_OUTSIDE - FOLLOW, atol=1e-5)
    # On the way down, she goes on to the foot even below the top's reach.
    var low = Vector3(0.5, 0.4, 2)
    var on = ally_goal(
        low, Vector3(0.5, 0, -6), False, True, doors, climbs, Climb(1, True)
    )
    assert_true(on[1].down)
    var foot = Vector3(0.5, 0, 3)
    var done = ally_goal(
        foot, Vector3(0.5, 0, -6), False, True, doors, climbs, Climb(1, True)
    )
    assert_equal(done[1].step, -1)
    # Outdoors, no climb.
    assert_equal(
        ally_goal(below, above, False, False, doors, climbs, going)[1].step, -1
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
