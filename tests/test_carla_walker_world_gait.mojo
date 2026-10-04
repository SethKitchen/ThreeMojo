# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""World boundaries for the capsule gait, issue #290."""

from extensions.carla.actor import ActorId
from std.testing import TestSuite, assert_equal, assert_raises
from tests.test_carla_world import _world, _spawn, _pose
from units.si import Duration, SECOND, Velocity


def test_world_gait_rejects_nonwalker_and_dead_ids() raises:
    var world = _world()
    with assert_raises(contains="not a walker"):
        _ = world.get_walker_gait(world.get_spectator())
    with assert_raises():
        _ = world.get_walker_gait(ActorId(99999))


def test_world_gait_returns_a_value_and_dead_actor_is_rejected() raises:
    var world = _world()
    var walker = _spawn(
        world, "walker.pedestrian.0015", _pose(20, -4.5, 1.06, 0)
    )
    var gait = world.get_walker_gait(walker)
    gait.advance(Velocity(1.5), Duration(0.25, SECOND))
    assert_equal(world.get_walker_gait(walker).amplitude().value, 0)
    var phase = gait.phase()
    phase.value = 0
    assert_equal(phase.value, 0)
    assert_equal(gait.phase().value > 0, True)
    _ = world.destroy_actor(walker)
    with assert_raises():
        _ = world.get_walker_gait(walker)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
