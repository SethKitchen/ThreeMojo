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
    flank_spot,
)
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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
