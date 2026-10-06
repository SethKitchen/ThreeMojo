# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Equivalent speed units survive graph caches, planning and scenario replay."""

from extensions.carla.actor import ActorId
from extensions.carla.opendrive import load_opendrive
from extensions.carla.recorder import Recorder
from extensions.carla.replayer import Replayer
from extensions.carla.speed_limits import simulation_speed, opendrive_speed
from extensions.carla.traffic_manager_map import (
    InMemoryMap,
    SimpleWaypointIndex,
)
from extensions.carla.traffic_manager_planning import MotionPlanStage
from extensions.carla.traffic_manager_shared import TrafficManagerShared
from extensions.carla.transform import CarlaRotation, CarlaTransform
from extensions.carla.world import World, EpisodeSettings
from math.vector3 import Vector3
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
    assert_raises,
)
from test_carla_traffic_manager import straight_town
from test_carla_speed_units import speed_town, speed_signal
from units.si import Angle, Duration, Length, Velocity


def _equivalent_town(value: String, unit: String) -> String:
    return straight_town().replace(
        'value="60" unit="km/h"',
        'value="' + value + '" unit="' + unit + '"',
    )


def _world_with_units(value: String, unit: String) raises -> World:
    var world = World(load_opendrive(_equivalent_town(value, unit)))
    _ = world.apply_settings(EpisodeSettings(True, False, Duration(0.05)))
    return world^


def _pose_at_sign() -> CarlaTransform:
    return CarlaTransform(
        Length(151),
        Length(1.75),
        Length(0.5),
        CarlaRotation(Angle(0), Angle(0), Angle(0)),
    )


def test_world_and_cached_planning_are_equivalent_across_units() raises:
    var first_map = load_opendrive(_equivalent_town("45", "mph"))
    var first = InMemoryMap()
    first.set_up(first_map)
    var cache = first.save()
    # The existing cache stores stations as Float32 and rebuilds waypoint ids.
    # Compare like-for-like loaded graphs, not an unrounded graph to its cache.
    var first_loaded = InMemoryMap()
    assert_true(first_loaded.load(first_map, cache.copy()))
    var loaded_cache = first_loaded.save()
    var stage = MotionPlanStage()
    var pairs: List[Tuple[String, String]] = [
        ("45", "mph"),
        ("72.42048", "km/h"),
        ("20.1168", "m/s"),
    ]
    for pair in pairs:
        var map = load_opendrive(_equivalent_town(pair[0], pair[1]))
        var built = InMemoryMap()
        built.set_up(map)
        assert_true(built.save() == cache)
        var local = InMemoryMap()
        assert_true(local.load(map, cache.copy()))
        assert_true(local.save() == loaded_cache)
        var shared = TrafficManagerShared(local^, 42)
        var speed = stage.get_landmark_target_velocity(
            SimpleWaypointIndex(88),
            Vector3(140, 1.75, 0),
            ActorId(1),
            25,
            shared,
            map,
        )
        # 20.1168 + (25 - 20.1168) * (10 / (25 * 3.5)).
        assert_almost_equal(speed, Float32(20.67488), atol=1e-4)
        var world = World(map^)
        assert_equal(
            bitcast[DType.uint32](world.signs[0].speed_limit.value),
            bitcast[DType.uint32](Float32(20.1168)),
        )


def test_desired_speed_stays_in_meters_per_second() raises:
    var map = load_opendrive(_equivalent_town("45", "mph"))
    var local = InMemoryMap()
    local.set_up(map)
    var shared = TrafficManagerShared(local^, 42)
    var stage = MotionPlanStage()
    shared.parameters.set_desired_speed(ActorId(1), Velocity(5))
    var desired = stage.get_landmark_target_velocity(
        SimpleWaypointIndex(88),
        Vector3(140, 1.75, 0),
        ActorId(1),
        25,
        shared,
        map,
    )
    # 5 m/s + (25 - 5) m/s * (10 / 87.5). The old km/h comparison gives 18.8.
    assert_almost_equal(desired, Float32(7.285714285714286), atol=1e-4)
    shared.parameters.set_percentage_speed_difference(ActorId(1), 50)
    var scaled = stage.get_landmark_target_velocity(
        SimpleWaypointIndex(88),
        Vector3(140, 1.75, 0),
        ActorId(1),
        25,
        shared,
        map,
    )
    assert_almost_equal(scaled, Float32(11.766011428571428), atol=1e-4)


def test_replay_uses_the_same_physical_sign_limit_for_equivalent_map_units() raises:
    var recorded_world = _world_with_units("72.42048", "km/h")
    var car = recorded_world.spawn_actor(
        recorded_world.blueprints.at("vehicle.lincoln.mkz"), _pose_at_sign()
    )
    var recorder = Recorder()
    _ = recorder.start(recorded_world, "", "equivalent-units", False, 0)
    for _ in range(4):
        _ = recorder.tick(recorded_world)
    recorder.stop()
    var expected = recorded_world.get_speed_limit(car).value
    assert_equal(expected, simulation_speed(opendrive_speed(45, "mph")).value)
    var replayed_world = _world_with_units("45", "mph")
    var replay = Replayer()
    _ = replay.replay_bytes(replayed_world, recorder.bytes(), "unit-roundtrip")
    var mapped = replay.mapped(car)
    assert_true(replayed_world.is_alive(mapped))
    for _ in range(3):
        _ = replay.step(replayed_world)
        assert_equal(replayed_world.get_speed_limit(mapped).value, expected)


def test_simulation_refuses_unusable_signal_units_and_range() raises:
    for unit in ["", " unit='kmh'"]:
        with assert_raises(contains="supported unit"):
            _ = World(
                load_opendrive(speed_town("", "", speed_signal("45", unit)))
            )
    for value in ["1e100", "1e-100"]:
        with assert_raises(contains="Float32 range"):
            _ = World(
                load_opendrive(
                    speed_town("", "", speed_signal(value, " unit='m/s'"))
                )
            )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
