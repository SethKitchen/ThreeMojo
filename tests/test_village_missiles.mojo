# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Missiles: how arrows, spell bolts and orbs fly, turn and strike, and the
fans, rains and lobs that send them."""

from extensions.village.combat import Blow
from extensions.village.missiles import (
    ARROW,
    ARROW_GRAVITY,
    ARROW_LIFE,
    ARROW_REACH,
    MISSILE_KINDS,
    ORB,
    ORB_LIFE,
    ORB_REACH,
    ORB_SPLASH,
    RAIN_HEIGHT,
    RAIN_RADIUS,
    SPARK,
    SPARK_LIFE,
    SPARK_REACH,
    Missile,
    MissileKind,
    fan,
    fly,
    lob,
    rain_spots,
    segment_gap,
    touches,
    turn_toward_point,
)
from math.vector3 import Vector3
from std.math import pi, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import METER_PER_SECOND, Velocity


def _blow() -> Blow:
    """Return a blow of 10 damage."""
    return Blow(
        10, 2, Velocity(0.0, METER_PER_SECOND), Velocity(0.0, METER_PER_SECOND)
    )


def test_each_kind_knows_its_values() raises:
    for value in [-1, MISSILE_KINDS]:
        assert_false(MissileKind(value).is_valid())
    for value in [0, MISSILE_KINDS - 1]:
        assert_true(MissileKind(value).is_valid())
    with assert_raises(contains="arrow"):
        _ = Missile(
            MissileKind(3), Vector3(0, 0, 0), Vector3(0, 0, 1), -1, -1, _blow()
        )
    with assert_raises(contains="pierce"):
        _ = Missile(
            ARROW, Vector3(0, 0, 0), Vector3(0, 0, 1), -1, -1, _blow(), -1
        )


def test_each_kind_has_its_reach_life_and_splash() raises:
    var at = Vector3(0, 0, 0)
    var still = Vector3(0, 0, 0)
    var arrow = Missile(ARROW, at, still, -1, -1, _blow())
    var spark = Missile(SPARK, at, still, -1, -1, _blow())
    var orb = Missile(ORB, at, still, -1, -1, _blow())
    assert_equal(arrow.reach(), ARROW_REACH)
    assert_equal(spark.reach(), SPARK_REACH)
    assert_equal(orb.reach(), ORB_REACH)
    assert_equal(arrow.life(), ARROW_LIFE)
    assert_equal(spark.life(), SPARK_LIFE)
    assert_equal(orb.life(), ORB_LIFE)
    assert_equal(arrow.splash(), 0)
    assert_equal(orb.splash(), ORB_SPLASH)
    assert_false(arrow.spent())
    arrow.age = ARROW_LIFE + 0.01
    assert_true(arrow.spent())
    assert_false(arrow.has_struck(3))
    arrow.struck.append(3)
    assert_true(arrow.has_struck(3))


def test_a_missile_turns_toward_its_aim() raises:
    var v = Vector3(10, 0, 0)
    var at = Vector3(0, 0, 0)
    # Within the turn, it turns onto the aim at its speed.
    var onto = turn_toward_point(v, at, Vector3(0, 0, 5), 2)
    assert_almost_equal(onto.z, 10, atol=1e-3)
    assert_almost_equal(onto.x, 0, atol=1e-3)
    # Past it, it turns part of the way, at its speed.
    var part = turn_toward_point(v, at, Vector3(0, 0, 5), 0.5)
    assert_almost_equal(part.length(), 10, atol=1e-3)
    assert_true(part.x > 0 and part.z > 0)
    # A still missile, or one at its aim, keeps its velocity.
    var still = turn_toward_point(Vector3(0, 0, 0), at, Vector3(1, 0, 0), 1)
    assert_equal(still.length(), 0)
    var there = turn_toward_point(v, at, at, 1)
    assert_equal(there.x, 10)
    # Straight back, a half turn's mix of the two ways is nothing: it
    # keeps going.
    var back = turn_toward_point(v, at, Vector3(-5, 0, 0), Float32(pi) / 2)
    assert_equal(back.x, 10)


def test_a_missile_flies_falls_and_turns() raises:
    var arrow = Missile(
        ARROW, Vector3(0, 2, 0), Vector3(0, 0, 40), -1, -1, _blow()
    )
    fly(arrow, 0.1, None)
    assert_almost_equal(arrow.at.z, 4, atol=1e-4)
    assert_almost_equal(arrow.velocity.y, -ARROW_GRAVITY * 0.1, atol=1e-5)
    assert_equal(arrow.last.z, 0)
    assert_almost_equal(arrow.age, 0.1, atol=1e-6)
    # An arrow does not turn toward an aim.
    var aimed = Missile(
        ARROW, Vector3(0, 2, 0), Vector3(0, 0, 40), 1, -1, _blow()
    )
    fly(aimed, 0.1, Vector3(10, 2, 0))
    assert_equal(aimed.velocity.x, 0)
    var spark = Missile(
        SPARK, Vector3(0, 0, 0), Vector3(0, 0, 20), 1, -1, _blow()
    )
    fly(spark, 0.1, Vector3(10, 0, 0))
    assert_true(spark.velocity.x > 0)
    var orb = Missile(ORB, Vector3(0, 0, 0), Vector3(0, 0, 10), 1, -1, _blow())
    fly(orb, 0.1, Vector3(10, 0, 0))
    assert_true(orb.velocity.x > 0)
    assert_true(orb.velocity.x < spark.velocity.x)
    var drift = Missile(
        SPARK, Vector3(0, 0, 0), Vector3(0, 0, 20), -1, -1, _blow()
    )
    fly(drift, 0.1, None)
    assert_equal(drift.velocity.x, 0)


def test_a_step_that_passes_a_chest_strikes_it() raises:
    assert_almost_equal(
        segment_gap(Vector3(0, 0, 0), Vector3(0, 0, 10), Vector3(1, 0, 5)),
        1,
        atol=1e-5,
    )
    # Before the start and after the end, it is the end's distance.
    assert_almost_equal(
        segment_gap(Vector3(0, 0, 0), Vector3(0, 0, 10), Vector3(0, 0, -3)),
        3,
        atol=1e-5,
    )
    assert_almost_equal(
        segment_gap(Vector3(0, 0, 0), Vector3(0, 0, 10), Vector3(0, 0, 14)),
        4,
        atol=1e-5,
    )
    assert_almost_equal(
        segment_gap(Vector3(1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 3)),
        2,
        atol=1e-5,
    )
    var arrow = Missile(
        ARROW, Vector3(0, 1, 0), Vector3(0, 0, 40), -1, -1, _blow()
    )
    fly(arrow, 0.25, None)
    assert_true(touches(arrow, Vector3(0.2, 1, 5)))
    assert_false(touches(arrow, Vector3(1, 1, 5)))


def test_a_fan_spreads_its_ways() raises:
    var one = fan(Vector3(0, 0, 1), 1, 50)
    assert_equal(len(one), 1)
    assert_equal(one[0].z, 1)
    var five = fan(Vector3(0, 0.2, 1), 5, 60)
    assert_equal(len(five), 5)
    assert_almost_equal(five[2].x, 0, atol=1e-5)
    assert_almost_equal(five[2].z, 1, atol=1e-5)
    assert_almost_equal(five[0].x, -five[4].x, atol=1e-5)
    assert_almost_equal(five[0].y, 0.2, atol=1e-6)
    assert_almost_equal(abs(five[0].x), 0.5, atol=1e-4)
    with assert_raises(contains="ways"):
        _ = fan(Vector3(0, 0, 1), 0, 10)
    with assert_raises(contains="ways"):
        _ = fan(Vector3(0, 0, 1), 65, 10)
    with assert_raises(contains="spread"):
        _ = fan(Vector3(0, 0, 1), 3, -1)
    with assert_raises(contains="spread"):
        _ = fan(Vector3(0, 0, 1), 3, 361)


def test_a_rain_falls_on_a_ring() raises:
    var center = Vector3(5, 1, -2)
    var spots = rain_spots(center, 6)
    assert_equal(len(spots), 6)
    assert_almost_equal(spots[0].y, 1 + RAIN_HEIGHT, atol=1e-5)
    assert_equal(spots[0].x, 5)
    for k in range(1, 6):
        var dx = spots[k].x - center.x
        var dz = spots[k].z - center.z
        assert_almost_equal(sqrt(dx * dx + dz * dz), RAIN_RADIUS, atol=1e-4)
        assert_true(spots[k].y > spots[k - 1].y)
    assert_equal(len(rain_spots(center, 1)), 1)
    with assert_raises(contains="arrows"):
        _ = rain_spots(center, 0)
    with assert_raises(contains="arrows"):
        _ = rain_spots(center, 65)


def test_a_lob_carries_an_arrow_onto_its_mark() raises:
    var start = Vector3(0, 1.5, 0)
    var end = Vector3(0, 1.0, 21)
    var v = lob(start, end, 42)
    assert_almost_equal(sqrt(v.x * v.x + v.z * v.z), 42, atol=1e-3)
    var arrow = Missile(ARROW, start, v, -1, -1, _blow())
    for _ in range(50):
        fly(arrow, 0.01, None)
    assert_almost_equal(arrow.at.z, 21, atol=1e-2)
    assert_almost_equal(arrow.at.y, 1.0, atol=2e-2)
    var up = lob(start, start + Vector3(0, 3, 0), 10)
    assert_equal(up.y, 10)
    with assert_raises(contains="speed"):
        _ = lob(start, end, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
