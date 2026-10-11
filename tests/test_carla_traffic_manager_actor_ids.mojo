# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The traffic manager's actor id boundaries refuse a bad id (#333).

These tests are the evidence for the audit in
`docs/validation/carla-quantity-inventory-333.md`. Each test gives a
public traffic manager boundary three bad ids: a negative id, the first
id above CARLA's unsigned 32 bits, and a valid id that names no actor.
A boundary that checks the id must raise and must not change its state.
"""

from extensions.carla.actor import RED, ActorId, no_rotation
from extensions.carla.traffic_manager import (
    ActorSet,
    TrafficManagerLocal,
    apply_batch,
    is_physics_enabled,
    set_simulate_physics,
)
from extensions.carla.traffic_manager_map import ROAD_OPTION_LEFT, WaypointId
from extensions.carla.traffic_manager_parameters import Parameters
from extensions.carla.traffic_manager_shared import (
    apply_transform,
    apply_vehicle_control,
    set_vehicle_light_state,
)
from extensions.carla.traffic_manager_state import (
    KinematicState,
    SimulationState,
    StaticAttributes,
    TRAFFIC_VEHICLE,
    TrackTraffic,
    TrafficLightInfo,
)
from extensions.carla.physics.vehicle_control import VehicleControl
from extensions.carla.vehicle import LIGHT_LOW_BEAM
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from test_carla_traffic_manager import straight_town
from test_carla_traffic_manager_world import _manager, _spawn, _world
from units.si import Length, Velocity


def _out_of_range() -> List[ActorId]:
    """Return the ids that `ActorId.is_valid` refuses."""
    return [ActorId(-1), ActorId(1 << 32)]


def _set_every_actor_setting(
    mut tm: TrafficManagerLocal, actor: ActorId
) raises -> Int:
    """Call each per-actor setter of the facade and count the refusals.

    Args:
        tm: The traffic manager.
        actor: The id to give each setter.

    Returns:
        How many setters raised "not valid".
    """
    var refused = 0
    try:
        tm.set_percentage_speed_difference(actor, 10)
    except e:
        refused += Int("not valid" in String(e))
    try:
        tm.set_desired_speed(actor, Velocity(3))
    except e:
        refused += Int("not valid" in String(e))
    try:
        tm.set_lane_offset(actor, Length(1))
    except e:
        refused += Int("not valid" in String(e))
    try:
        tm.set_large_vehicle_wide_turn(actor, False)
    except e:
        refused += Int("not valid" in String(e))
    try:
        tm.set_update_vehicle_lights(actor, True)
    except e:
        refused += Int("not valid" in String(e))
    try:
        tm.set_collision_detection(actor, ActorId(1), False)
    except e:
        refused += Int("not valid" in String(e))
    try:
        tm.set_collision_detection(ActorId(1), actor, False)
    except e:
        refused += Int("not valid" in String(e))
    try:
        tm.set_force_lane_change(actor, True)
    except e:
        refused += Int("not valid" in String(e))
    try:
        tm.set_auto_lane_change(actor, False)
    except e:
        refused += Int("not valid" in String(e))
    try:
        tm.set_distance_to_leading_vehicle(actor, Length(7))
    except e:
        refused += Int("not valid" in String(e))
    try:
        tm.set_percentage_ignore_walkers(actor, 1)
    except e:
        refused += Int("not valid" in String(e))
    try:
        tm.set_percentage_ignore_vehicles(actor, 1)
    except e:
        refused += Int("not valid" in String(e))
    try:
        tm.set_percentage_running_light(actor, 1)
    except e:
        refused += Int("not valid" in String(e))
    try:
        tm.set_percentage_running_sign(actor, 1)
    except e:
        refused += Int("not valid" in String(e))
    try:
        tm.set_keep_slow_lane_percentage(actor, 1)
    except e:
        refused += Int("not valid" in String(e))
    try:
        tm.set_random_left_lane_change_percentage(actor, 1)
    except e:
        refused += Int("not valid" in String(e))
    try:
        tm.set_random_right_lane_change_percentage(actor, 1)
    except e:
        refused += Int("not valid" in String(e))
    try:
        tm.set_custom_path(actor, [Vector3(1, 2, 3)], True)
    except e:
        refused += Int("not valid" in String(e))
    try:
        tm.remove_upload_path(actor, True)
    except e:
        refused += Int("not valid" in String(e))
    try:
        tm.update_upload_path(actor, [Vector3(1, 2, 3)])
    except e:
        refused += Int("not valid" in String(e))
    try:
        tm.set_imported_route(actor, [ROAD_OPTION_LEFT], True)
    except e:
        refused += Int("not valid" in String(e))
    try:
        tm.remove_imported_route(actor, True)
    except e:
        refused += Int("not valid" in String(e))
    try:
        tm.update_imported_route(actor, [ROAD_OPTION_LEFT])
    except e:
        refused += Int("not valid" in String(e))
    return refused


def test_every_per_actor_setter_refuses_an_out_of_range_id() raises:
    var world = _world(straight_town())
    var tm = _manager(world)
    for bad in _out_of_range():
        assert_equal(_set_every_actor_setting(tm, bad), 23)
    # Nothing was stored for a refused id.
    assert_equal(len(tm.parameters().configured_actor_ids()), 0)
    # The top valid id is a settings key; CARLA keys settings by id alone.
    # The collision setting also names actor 1.
    assert_equal(_set_every_actor_setting(tm, ActorId((1 << 32) - 1)), 0)
    assert_equal(len(tm.parameters().configured_actor_ids()), 2)


def test_registration_refuses_an_out_of_range_id_first() raises:
    var world = _world(straight_town())
    var tm = _manager(world)
    for bad in _out_of_range():
        with assert_raises(contains="not valid"):
            tm.register_vehicles(world, [bad])
        assert_equal(len(tm.get_registered_vehicles_ids()), 0)
        with assert_raises(contains="not valid"):
            tm.unregister_vehicles([bad])


def test_registration_refuses_an_id_that_names_no_actor() raises:
    var world = _world(straight_town())
    var tm = _manager(world)
    with assert_raises(contains="names no actor"):
        tm.register_vehicles(world, [ActorId(999)])


def test_world_adapters_refuse_a_bad_id() raises:
    var world = _world(straight_town())
    var car = _spawn(world, 20, 1.75)
    var tm = _manager(world)
    var ids = _out_of_range()
    ids.append(ActorId(999))
    for bad in ids:
        with assert_raises(contains="names no actor"):
            set_simulate_physics(world, bad, False)
        with assert_raises(contains="names no actor"):
            _ = is_physics_enabled(world, bad)
        with assert_raises():
            _ = tm.check_all_frozen(world, [bad])
        with assert_raises(contains="names no actor"):
            apply_batch(world, [apply_vehicle_control(bad, VehicleControl())])
        with assert_raises(contains="names no actor"):
            apply_batch(world, [apply_transform(bad, world.get_transform(car))])
        with assert_raises():
            apply_batch(world, [set_vehicle_light_state(bad, LIGHT_LOW_BEAM)])
    assert_true(is_physics_enabled(world, car))


def test_the_actor_set_refuses_an_out_of_range_insert() raises:
    var set = ActorSet()
    for bad in _out_of_range():
        with assert_raises(contains="not valid"):
            set.insert([bad])
        assert_equal(set.size(), 0)
        assert_equal(set.state, 0)
        assert_false(set.contains(bad))


def test_parameter_cleanup_refuses_an_out_of_range_id() raises:
    var p = Parameters()
    for bad in _out_of_range():
        with assert_raises(contains="not valid"):
            p.remove_actor(bad)


def test_the_trackers_refuse_an_out_of_range_id() raises:
    var t = TrackTraffic()
    var s = SimulationState()
    for bad in _out_of_range():
        with assert_raises(contains="not valid"):
            t.update_passing_vehicle(WaypointId(1), bad)
        with assert_raises(contains="not valid"):
            t.remove_passing_vehicle(WaypointId(1), bad)
        with assert_raises(contains="not valid"):
            t.delete_actor(bad)
        with assert_raises(contains="not valid"):
            s.add_actor(
                bad,
                KinematicState(
                    Vector3(0, 0, 0),
                    no_rotation(),
                    Vector3(1, 0, 0),
                    Velocity(10),
                    True,
                    False,
                    Vector3(0, 0, 0),
                ),
                StaticAttributes(
                    TRAFFIC_VEHICLE, Length(2.4), Length(1.0), Length(0.75)
                ),
                TrafficLightInfo(RED, False),
            )
        with assert_raises(contains="does not track"):
            _ = s.get_location(bad)
        assert_false(s.contains_actor(bad))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
