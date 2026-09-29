# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's traffic manager: random numbers, PID, settings, state and map.

The expected numbers come from outside this port:

- The Mersenne Twister's draws come from CPython's `random`, whose
  twist and temper are C code of their own, seeded with the standard's
  `init_genrand` state; seed 5489's 10000th draw, 4123659995, is the
  one the C++ standard names. `tm_model.py`, a Python model outside the repository, does this.
- The PID steps are worked by hand from CARLA's gains.
- The graph of the straight town is worked by hand: one road 300 m long
  along x, lanes -2, -1 and 1, 3.5 m wide, sampled each 5 m from s = 0,
  a grid id each 25 m (the first sample more than 20 m from the grid's
  start opens a new grid).
- The junction town's graph is reasoned from the file: road 1 forks into
  road 10, straight on, and road 11, a right turn of radius 10 m, so both
  are real junction roads.
"""

from extensions.carla.actor import ActorId, GREEN, NO_ACTOR, RED, YELLOW
from extensions.carla.map import Map, Waypoint
from extensions.carla.opendrive import load_opendrive
from extensions.carla.road_info import JuncId, LaneId, RoadId, SectionId
from extensions.carla.traffic_manager_constants import (
    AFTER_JUNCTION_MIN_SPEED,
    HIGHWAY_SPEED,
    INV_DT,
    INV_HYBRID_DT,
    MAP_RESOLUTION,
    MAX_WPT_DISTANCE_SQUARED,
    MIN_SAFE_INTERVAL_LENGTH,
    RELATIVE_APPROACH_SPEED,
)
from extensions.carla.traffic_manager_map import (
    CachedSimpleWaypoint,
    InMemoryMap,
    NO_SIMPLE_WAYPOINT,
    ROAD_OPTION_LANE_FOLLOW,
    ROAD_OPTION_LEFT,
    ROAD_OPTION_RIGHT,
    ROAD_OPTION_ROAD_END,
    ROAD_OPTION_STRAIGHT,
    ROAD_OPTION_VOID,
    RoadOption,
    SimpleWaypointIndex,
    WaypointId,
    _SegmentKey,
    _sort_keys,
    c_remainder,
    cook,
    distance_squared,
    to_int16,
)
from extensions.carla.traffic_manager_parameters import Parameters
from extensions.carla.traffic_manager_pid import (
    LATERAL_HIGHWAY_PARAM,
    LATERAL_PARAM,
    LONGITUDINAL_HIGHWAY_PARAM,
    LONGITUDINAL_PARAM,
    PIDParameters,
    StateEntry,
    cpp_max,
    cpp_min,
    run_step,
)
from extensions.carla.traffic_manager_random import (
    MersenneTwister,
    RandomGenerator,
    canonical_from_draws,
)
from extensions.carla.traffic_manager_state import (
    FLOAT_MAX,
    KinematicState,
    Neighbor,
    SimulationState,
    StaticAttributes,
    TRAFFIC_ANY,
    TRAFFIC_PEDESTRIAN,
    TRAFFIC_VEHICLE,
    TrackTraffic,
    TrafficActorType,
    TrafficLightInfo,
    deviation_cross_product,
    deviation_dot_product,
    get_target_data,
    get_target_waypoint,
    interpolate_buffer_at,
    is_offset_side_occupied,
    large_vehicle_junction_offset_profile,
    large_vehicle_offset_magnitude,
    pop_waypoint,
    push_waypoint,
    three_point_circle_radius,
)
from extensions.carla.actor import no_rotation
from extensions.carla.physics.quantities import KILOMETER_PER_HOUR
from math.vector3 import Vector3
from std.math import isnan, nan, sqrt
from std.os import makedirs
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Duration, Length, METER, MILLISECOND, SECOND, Velocity


def straight_town() -> String:
    """One road 300 m long along x: lanes -2 and -1 east, lane 1 west.

    A lane may change between -1 and -2. A 60 km/h sign stands at s 150
    for lane -1.
    """
    return """<?xml version="1.0" encoding="UTF-8"?>
<OpenDRIVE>
  <header revMajor="1" revMinor="4" name="straight" version="1.0"/>
  <road name="main" length="300" id="1" junction="-1">
    <planView><geometry s="0" x="0" y="0" hdg="0" length="300"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <left>
        <lane id="1" type="driving"><width sOffset="0" a="3.5" b="0" c="0" d="0"/><roadMark sOffset="0" type="solid" weight="standard" color="white" width="0.15" laneChange="none"/></lane>
      </left>
      <center><lane id="0" type="none"><roadMark sOffset="0" type="solid" weight="standard" color="yellow" width="0.15" laneChange="none"/></lane></center>
      <right>
        <lane id="-1" type="driving"><width sOffset="0" a="3.5" b="0" c="0" d="0"/><roadMark sOffset="0" type="broken" weight="standard" color="white" width="0.15" laneChange="both"/></lane>
        <lane id="-2" type="driving"><width sOffset="0" a="3.5" b="0" c="0" d="0"/><roadMark sOffset="0" type="solid" weight="standard" color="white" width="0.15" laneChange="none"/></lane>
      </right>
    </laneSection></lanes>
    <signals>
      <signal s="150" t="-8" id="700" name="limit" dynamic="no" orientation="+" zOffset="2" country="DE" type="274" subtype="60" value="60" unit="km/h" height="1" width="1" hOffset="0" pitch="0" roll="0">
        <validity fromLane="-1" toLane="-1"/>
      </signal>
    </signals>
  </road>
</OpenDRIVE>
"""


def junction_town() -> String:
    """Road 1 forks at x = 100 into road 10, straight on to road 2, and
    road 11, a right turn of radius 10 m onto road 3, which runs to plus
    y in CARLA's frame. A light (500) stands at s 95 of road 1 for lane
    -1, and a yield sign (501) on road 10 for lane 1.
    """
    return """<?xml version="1.0" encoding="UTF-8"?>
<OpenDRIVE>
  <header revMajor="1" revMinor="4" name="fork" version="1.0"/>
  <road name="west" length="100" id="1" junction="-1">
    <link><successor elementType="junction" elementId="100"/></link>
    <planView><geometry s="0" x="0" y="0" hdg="0" length="100"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <left><lane id="1" type="driving"><link><predecessor id="1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></left>
      <center><lane id="0" type="none"/></center>
      <right><lane id="-1" type="driving"><link><successor id="-1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></right>
    </laneSection></lanes>
    <signals>
      <signal s="95" t="-5" id="500" name="light" dynamic="yes" orientation="+" zOffset="3" country="OpenDRIVE" type="1000001" subtype="-1" value="-1" height="1" width="0.5" hOffset="0" pitch="0" roll="0">
        <validity fromLane="-1" toLane="-1"/>
      </signal>
    </signals>
  </road>
  <road name="east" length="100" id="2" junction="-1">
    <link><predecessor elementType="junction" elementId="100"/></link>
    <planView><geometry s="0" x="120" y="0" hdg="0" length="100"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <left><lane id="1" type="driving"><link><successor id="1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></left>
      <center><lane id="0" type="none"/></center>
      <right><lane id="-1" type="driving"><link><predecessor id="-1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></right>
    </laneSection></lanes>
  </road>
  <road name="south" length="100" id="3" junction="-1">
    <link><predecessor elementType="junction" elementId="100"/></link>
    <planView><geometry s="0" x="110" y="-10" hdg="-1.5707963267948966" length="100"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <left><lane id="1" type="driving"><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></left>
      <center><lane id="0" type="none"/></center>
      <right><lane id="-1" type="driving"><link><predecessor id="-1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></right>
    </laneSection></lanes>
  </road>
  <road name="through" length="20" id="10" junction="100">
    <link>
      <predecessor elementType="road" elementId="1" contactPoint="end"/>
      <successor elementType="road" elementId="2" contactPoint="start"/>
    </link>
    <planView><geometry s="0" x="100" y="0" hdg="0" length="20"><line/></geometry></planView>
    <lanes><laneSection s="0">
      <left><lane id="1" type="driving"><link><predecessor id="1"/><successor id="1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></left>
      <center><lane id="0" type="none"/></center>
      <right><lane id="-1" type="driving"><link><predecessor id="-1"/><successor id="-1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></right>
    </laneSection></lanes>
    <signals>
      <signal s="18" t="5" id="501" name="yield" dynamic="no" orientation="-" zOffset="2" country="OpenDRIVE" type="205" subtype="" value="0" height="1" width="1" hOffset="0" pitch="0" roll="0">
        <validity fromLane="1" toLane="1"/>
      </signal>
    </signals>
  </road>
  <road name="turn" length="15.707963267948966" id="11" junction="100">
    <link>
      <predecessor elementType="road" elementId="1" contactPoint="end"/>
      <successor elementType="road" elementId="3" contactPoint="start"/>
    </link>
    <planView><geometry s="0" x="100" y="0" hdg="0" length="15.707963267948966"><arc curvature="-0.1"/></geometry></planView>
    <lanes><laneSection s="0">
      <center><lane id="0" type="none"/></center>
      <right><lane id="-1" type="driving"><link><predecessor id="-1"/><successor id="-1"/></link><width sOffset="0" a="3.5" b="0" c="0" d="0"/></lane></right>
    </laneSection></lanes>
  </road>
  <junction id="100" name="fork">
    <connection id="0" incomingRoad="1" connectingRoad="10" contactPoint="start"><laneLink from="-1" to="-1"/></connection>
    <connection id="1" incomingRoad="2" connectingRoad="10" contactPoint="end"><laneLink from="1" to="1"/></connection>
    <connection id="2" incomingRoad="1" connectingRoad="11" contactPoint="start"><laneLink from="-1" to="-1"/></connection>
  </junction>
</OpenDRIVE>
"""


def _near(a: Float32, b: Float32, tol: Float64 = 1e-4) raises:
    assert_almost_equal(a, b, atol=tol)


# --- constants ------------------------------------------------------------------


def test_constants_are_carla_values() raises:
    # CARLA's float divisions, worked by hand.
    _near(HIGHWAY_SPEED.value, 16.666666)
    _near(AFTER_JUNCTION_MIN_SPEED.value, 1.3888888)
    _near(RELATIVE_APPROACH_SPEED.value, 3.3333333)
    assert_equal(MIN_SAFE_INTERVAL_LENGTH.value, 2.0)
    assert_equal(MAX_WPT_DISTANCE_SQUARED, 27.5)
    assert_equal(INV_HYBRID_DT, 20.0)
    assert_equal(INV_DT, 20.0)
    assert_equal(MAP_RESOLUTION.value, 5.0)


# --- random ---------------------------------------------------------------------


def test_mersenne_twister_matches_the_standard() raises:
    var mt = MersenneTwister(5489)
    assert_equal(mt.next_u32(), 3499211612)
    for _ in range(9998):
        _ = mt.next_u32()
    assert_equal(mt.next_u32(), 4123659995)
    # Only the low 32 bits of the seed count.
    var high = MersenneTwister(5489 + (UInt64(1) << 32))
    assert_equal(high.next_u32(), 3499211612)


def test_random_generator_percentages() raises:
    # From tm_model.py: CPython's twister and the GNU canonical.
    var g = RandomGenerator(42)
    assert_almost_equal(g.next(), 79.6542984287846, atol=1e-12)
    assert_almost_equal(g.next(), 18.34347878933685, atol=1e-12)
    assert_almost_equal(g.next(), 77.96909976126612, atol=1e-12)
    assert_almost_equal(g.next(), 59.68501615800565, atol=1e-12)
    var h = RandomGenerator(7 + (UInt64(1) << 32))
    assert_almost_equal(h.next(), 22.733907496470685, atol=1e-12)


def test_canonical_stays_below_one() raises:
    assert_equal(canonical_from_draws(0, 0), 0.0)
    # (2^32 - 1) (1 + 2^32) = 2^64 - 1 rounds to 2^64 in double.
    assert_equal(
        canonical_from_draws(0xFFFFFFFF, 0xFFFFFFFF), 0.99999999999999988898
    )
    assert_equal(canonical_from_draws(0, 0x80000000), 0.5)


# --- PID ------------------------------------------------------------------------


def _state(angular: Float32, velocity: Float32, steer: Float32) -> StateEntry:
    return StateEntry(Duration(0, SECOND), angular, velocity, steer)


def test_pid_gains_are_carla_values() raises:
    assert_true(LONGITUDINAL_PARAM == PIDParameters(12.0, 0.05, 0.02))
    assert_true(LONGITUDINAL_HIGHWAY_PARAM == PIDParameters(20.0, 0.05, 0.01))
    assert_true(LATERAL_PARAM == PIDParameters(8.0, 0.04, 0.16))
    assert_true(LATERAL_HIGHWAY_PARAM == PIDParameters(4.0, 0.04, 0.08))


def test_pid_throttle_and_steer_limits() raises:
    # 12 0.5 + 0.05 0.75 0.05 + 0.02 0.25 20 = 6.101875: capped at 0.85.
    # 8 0.1 + 0.04 0.1 0.05 + 0.16 0.1 20 = 1.1202: capped at 0 + 0.15.
    var out = run_step(
        _state(0.1, 0.5, 0),
        _state(0, 0.25, 0),
        LONGITUDINAL_PARAM,
        LATERAL_PARAM,
    )
    _near(out.throttle, 0.85)
    assert_equal(out.brake, 0.0)
    _near(out.steer, 0.15)


def test_pid_small_errors_pass_through() raises:
    # 12 0.01 + 0.05 0.02 0.05 = 0.12005; 8 0.01 + 0.04 0.02 0.05 = 0.08004.
    var out = run_step(
        _state(0.01, 0.01, 0),
        _state(0.01, 0.01, 0.1),
        LONGITUDINAL_PARAM,
        LATERAL_PARAM,
    )
    _near(out.throttle, 0.12005)
    _near(out.steer, 0.08004)


def test_pid_brake_and_steer_floor() raises:
    # -6.0025 brakes at the 0.7 cap; -4.002 is held at -0.85, then -0.8.
    var out = run_step(
        _state(-0.5, -0.5, 0),
        _state(-0.5, -0.5, -0.7),
        LONGITUDINAL_PARAM,
        LATERAL_PARAM,
    )
    assert_equal(out.throttle, 0.0)
    _near(out.brake, 0.7)
    _near(out.steer, -0.8)
    # A small negative error brakes gently: 12 (-0.01) + ... = -0.12005.
    var gentle = run_step(
        _state(0, -0.01, 0),
        _state(0, -0.01, 0),
        LONGITUDINAL_PARAM,
        LATERAL_PARAM,
    )
    _near(gentle.brake, 0.12005)
    # The steer rises by at most 0.15 from 0.7 and stops at 0.8.
    var high = run_step(
        _state(0.5, 0, 0),
        _state(0.5, 0, 0.7),
        LONGITUDINAL_PARAM,
        LATERAL_PARAM,
    )
    _near(high.steer, 0.8)


def test_pid_nan_error_gives_nan_brake() raises:
    var out = run_step(
        _state(0, nan[DType.float32](), 0),
        _state(0, 0, 0),
        LONGITUDINAL_PARAM,
        LATERAL_PARAM,
    )
    assert_true(isnan(out.brake))
    assert_equal(out.throttle, 0.0)


def test_cpp_min_max_keep_the_first_on_nan() raises:
    assert_equal(cpp_min(1, 2), 1)
    assert_equal(cpp_min(2, 1), 1)
    assert_equal(cpp_max(1, 2), 2)
    assert_equal(cpp_max(2, 1), 2)
    assert_true(isnan(cpp_min(nan[DType.float32](), 1)))
    assert_equal(cpp_min(1, nan[DType.float32]()), 1)


# --- parameters -------------------------------------------------------------------


def test_parameter_defaults() raises:
    var p = Parameters()
    var car = ActorId(5)
    assert_false(p.get_synchronous_mode())
    assert_equal(
        p.get_synchronous_mode_time_out().value, Duration(10, MILLISECOND).value
    )
    assert_false(p.get_hybrid_physics_mode())
    assert_equal(p.get_hybrid_physics_radius().value, 70.0)
    assert_false(p.get_respawn_dormant_vehicles())
    assert_equal(p.get_lower_boundary_respawn_dormant_vehicles().value, 100.0)
    assert_equal(p.get_upper_boundary_respawn_dormant_vehicles().value, 1000.0)
    assert_true(p.get_osm_mode())
    assert_equal(p.get_distance_to_leading_vehicle(car).value, 2.0)
    assert_equal(p.get_lane_offset(car).value, 0.0)
    assert_true(p.get_auto_lane_change(car))
    assert_equal(p.get_keep_slow_lane_percentage(car), -1.0)
    assert_equal(p.get_random_left_lane_change_percentage(car), -1.0)
    assert_equal(p.get_random_right_lane_change_percentage(car), -1.0)
    assert_equal(p.get_percentage_running_light(car), 0.0)
    assert_equal(p.get_percentage_running_sign(car), 0.0)
    assert_equal(p.get_percentage_ignore_vehicles(car), 0.0)
    assert_equal(p.get_percentage_ignore_walkers(car), 0.0)
    assert_false(p.get_update_vehicle_lights(car))
    assert_true(p.get_large_vehicle_wide_turn(car))
    assert_true(p.get_collision_detection(car, ActorId(6)))
    assert_false(p.get_upload_path(car))
    assert_equal(len(p.get_custom_path(car)), 0)
    assert_false(p.get_upload_route(car))
    assert_equal(len(p.get_imported_route(car)), 0)
    var lane = p.get_force_lane_change(car)
    assert_false(lane.change_lane)
    assert_false(p.has_desired_speed(car))
    # 30 km/h with no difference.
    _near(
        p.get_vehicle_target_velocity(
            car, Velocity(30, KILOMETER_PER_HOUR)
        ).value,
        8.333333,
    )


def test_speed_difference_and_desired_speed() raises:
    var p = Parameters()
    var car = ActorId(5)
    var limit = Velocity(10.0)
    p.set_global_percentage_speed_difference(30)
    _near(p.get_vehicle_target_velocity(car, limit).value, 7.0)
    # A difference past 100 % is held at 100 %.
    p.set_global_percentage_speed_difference(150)
    _near(p.get_vehicle_target_velocity(car, limit).value, 0.0)
    p.set_percentage_speed_difference(car, -20)
    _near(p.get_vehicle_target_velocity(car, limit).value, 12.0)
    p.set_percentage_speed_difference(car, 250)
    _near(p.get_vehicle_target_velocity(car, limit).value, 0.0)
    p.set_desired_speed(car, Velocity(4.0))
    assert_true(p.has_desired_speed(car))
    _near(p.get_vehicle_target_velocity(car, limit).value, 4.0)
    p.set_desired_speed(car, Velocity(-4.0))
    _near(p.get_vehicle_target_velocity(car, limit).value, 0.0)
    # A new difference drops the desired speed, and a new speed the
    # difference.
    p.set_percentage_speed_difference(car, 50)
    assert_false(p.has_desired_speed(car))
    _near(p.get_vehicle_target_velocity(car, limit).value, 5.0)
    p.set_desired_speed(car, Velocity(3.0))
    p.set_desired_speed(car, Velocity(2.0))
    _near(p.get_vehicle_target_velocity(car, limit).value, 2.0)


def test_parameter_setters_clamp() raises:
    var p = Parameters()
    var car = ActorId(5)
    p.set_distance_to_leading_vehicle(car, Length(-3))
    assert_equal(p.get_distance_to_leading_vehicle(car).value, 0.0)
    p.set_global_distance_to_leading_vehicle(Length(-1))
    assert_equal(p.get_distance_to_leading_vehicle(ActorId(9)).value, -1.0)
    p.set_percentage_running_light(car, 120)
    assert_equal(p.get_percentage_running_light(car), 100.0)
    p.set_percentage_running_sign(car, -5)
    assert_equal(p.get_percentage_running_sign(car), 0.0)
    p.set_percentage_ignore_vehicles(car, 40)
    assert_equal(p.get_percentage_ignore_vehicles(car), 40.0)
    p.set_percentage_ignore_walkers(car, 101)
    assert_equal(p.get_percentage_ignore_walkers(car), 100.0)
    p.set_hybrid_physics_radius(Length(-2))
    assert_equal(p.get_hybrid_physics_radius().value, 0.0)
    p.set_hybrid_physics_radius(Length(30))
    assert_equal(p.get_hybrid_physics_radius().value, 30.0)
    p.set_keep_slow_lane_percentage(car, 20)
    p.set_random_left_lane_change_percentage(car, 30)
    p.set_random_right_lane_change_percentage(car, 40)
    assert_equal(p.get_keep_slow_lane_percentage(car), 20.0)
    assert_equal(p.get_random_left_lane_change_percentage(car), 30.0)
    assert_equal(p.get_random_right_lane_change_percentage(car), 40.0)
    p.set_lane_offset(car, Length(0.5))
    p.set_global_lane_offset(Length(-0.25))
    assert_equal(p.get_lane_offset(car).value, 0.5)
    assert_equal(p.get_lane_offset(ActorId(9)).value, -0.25)
    p.set_large_vehicle_wide_turn(car, False)
    p.set_global_large_vehicle_wide_turn(False)
    assert_false(p.get_large_vehicle_wide_turn(car))
    assert_false(p.get_large_vehicle_wide_turn(ActorId(9)))
    p.set_update_vehicle_lights(car, True)
    assert_true(p.get_update_vehicle_lights(car))
    p.set_auto_lane_change(car, False)
    assert_false(p.get_auto_lane_change(car))
    p.set_synchronous_mode()
    assert_true(p.get_synchronous_mode())
    p.set_synchronous_mode(False)
    assert_false(p.get_synchronous_mode())
    p.set_synchronous_mode_time_out(Duration(2, SECOND))
    assert_equal(p.get_synchronous_mode_time_out().value, 2.0)
    p.set_hybrid_physics_mode(True)
    assert_true(p.get_hybrid_physics_mode())
    p.set_respawn_dormant_vehicles(True)
    assert_true(p.get_respawn_dormant_vehicles())
    p.set_osm_mode(False)
    assert_false(p.get_osm_mode())


def test_respawn_bounds_respect_the_limits() raises:
    var p = Parameters()
    # CARLA's limits: 20 m and the active distance, 2000 m by default.
    p.set_boundaries_respawn_dormant_vehicles(Length(10), Length(3000))
    assert_equal(p.get_lower_boundary_respawn_dormant_vehicles().value, 20.0)
    assert_equal(p.get_upper_boundary_respawn_dormant_vehicles().value, 2000.0)
    p.set_boundaries_respawn_dormant_vehicles(Length(30), Length(40))
    assert_equal(p.get_lower_boundary_respawn_dormant_vehicles().value, 30.0)
    assert_equal(p.get_upper_boundary_respawn_dormant_vehicles().value, 40.0)
    p.set_max_boundaries(Length(50), Length(60))
    p.set_boundaries_respawn_dormant_vehicles(Length(30), Length(70))
    assert_equal(p.get_lower_boundary_respawn_dormant_vehicles().value, 50.0)
    assert_equal(p.get_upper_boundary_respawn_dormant_vehicles().value, 60.0)


def test_collision_detection_rules() raises:
    var p = Parameters()
    var a = ActorId(1)
    var b = ActorId(2)
    var c = ActorId(3)
    # Detecting with no rules changes nothing.
    p.set_collision_detection(a, b, True)
    assert_true(p.get_collision_detection(a, b))
    p.set_collision_detection(a, b, False)
    assert_false(p.get_collision_detection(a, b))
    assert_true(p.get_collision_detection(b, a))
    p.set_collision_detection(a, b, False)
    p.set_collision_detection(a, c, False)
    assert_false(p.get_collision_detection(a, c))
    p.set_collision_detection(a, b, True)
    assert_true(p.get_collision_detection(a, b))
    assert_false(p.get_collision_detection(a, c))
    # Detecting an actor that is not ignored changes nothing.
    p.set_collision_detection(a, b, True)
    assert_false(p.get_collision_detection(a, c))


def test_force_lane_change_is_read_once() raises:
    var p = Parameters()
    var car = ActorId(4)
    p.set_force_lane_change(car, True)
    var first = p.get_force_lane_change(car)
    assert_true(first.change_lane)
    assert_true(first.direction)
    assert_false(p.get_force_lane_change(car).change_lane)


def test_paths_and_routes() raises:
    var p = Parameters()
    var car = ActorId(4)
    p.set_custom_path(car, [Vector3(1, 2, 3)], True)
    assert_true(p.get_upload_path(car))
    assert_equal(len(p.get_custom_path(car)), 1)
    p.remove_upload_path(car, False)
    assert_false(p.get_upload_path(car))
    p.remove_upload_path(car, False)
    p.update_upload_path(car, [Vector3(1, 2, 3), Vector3(4, 5, 6)])
    assert_equal(len(p.get_custom_path(car)), 2)
    p.remove_upload_path(car, True)
    assert_equal(len(p.get_custom_path(car)), 0)
    p.remove_upload_path(car, True)
    p.set_imported_route(car, [ROAD_OPTION_LEFT, ROAD_OPTION_STRAIGHT], False)
    assert_false(p.get_upload_route(car))
    assert_equal(len(p.get_imported_route(car)), 2)
    p.set_imported_route(car, [ROAD_OPTION_RIGHT], True)
    assert_true(p.get_upload_route(car))
    p.remove_imported_route(car, False)
    assert_false(p.get_upload_route(car))
    p.remove_imported_route(car, False)
    p.update_imported_route(car, [ROAD_OPTION_RIGHT, ROAD_OPTION_LEFT])
    assert_true(p.get_imported_route(car)[1] == ROAD_OPTION_LEFT)
    p.remove_imported_route(car, True)
    assert_equal(len(p.get_imported_route(car)), 0)
    p.remove_imported_route(car, True)
    with assert_raises(contains="road option is not valid"):
        p.set_imported_route(car, [RoadOption(9)], False)


def test_parameters_refuse_bad_ids() raises:
    var p = Parameters()
    var bad = ActorId(-1)
    with assert_raises(contains="not valid"):
        p.set_percentage_speed_difference(bad, 1)
    with assert_raises(contains="not valid"):
        p.set_collision_detection(ActorId(1), bad, True)


# --- TrackTraffic and SimulationState ------------------------------------------------


def _graph(map: Map) raises -> InMemoryMap:
    var local = InMemoryMap()
    local.set_up(map)
    return local^


def test_track_traffic_passing_vehicles() raises:
    var t = TrackTraffic()
    var a = ActorId(3)
    var b = ActorId(2)
    t.update_passing_vehicle(WaypointId(10), a)
    t.update_passing_vehicle(WaypointId(10), b)
    t.update_passing_vehicle(WaypointId(10), a)
    t.update_passing_vehicle(WaypointId(11), a)
    var passing = t.get_passing_vehicles(WaypointId(10))
    assert_equal(len(passing), 2)
    # Sorted by id.
    assert_true(passing[0] == b)
    assert_equal(len(t.get_passing_vehicles(WaypointId(99))), 0)
    t.remove_passing_vehicle(WaypointId(10), a)
    assert_equal(len(t.get_passing_vehicles(WaypointId(10))), 1)
    t.remove_passing_vehicle(WaypointId(10), b)
    assert_equal(len(t.get_passing_vehicles(WaypointId(10))), 0)
    # Removing what is not there changes nothing.
    t.remove_passing_vehicle(WaypointId(10), b)
    t.remove_passing_vehicle(WaypointId(11), a)
    assert_equal(len(t.get_passing_vehicles(WaypointId(11))), 0)
    with assert_raises(contains="not valid"):
        t.update_passing_vehicle(WaypointId(-1), a)
    with assert_raises(contains="not valid"):
        t.remove_passing_vehicle(WaypointId(1), ActorId(-2))


def test_track_traffic_grids() raises:
    var map = load_opendrive(straight_town())
    var local = _graph(map)
    var t = TrackTraffic()
    var a = ActorId(1)
    var b = ActorId(2)
    # Nodes 0 and 5 are on lane -2 at x = 0 and 25: grids 0 and 1.
    t.update_grid_position(
        a, [SimpleWaypointIndex(0), SimpleWaypointIndex(5)], local
    )
    assert_false(t.is_geo_grid_free(JuncId(0)))
    assert_false(t.is_geo_grid_free(JuncId(1)))
    assert_true(t.is_geo_grid_free(JuncId(2)))
    # An empty path changes nothing.
    t.update_grid_position(a, List[SimpleWaypointIndex](), local)
    assert_false(t.is_geo_grid_free(JuncId(0)))
    t.update_unregistered_grid_position(b, [SimpleWaypointIndex(6)], local)
    var overlap = t.get_overlapping_vehicles(a)
    assert_equal(len(overlap), 2)
    assert_true(overlap[0] == a)
    assert_true(overlap[1] == b)
    assert_equal(
        len(t.get_passing_vehicles(local.at(SimpleWaypointIndex(6)).id)), 1
    )
    # A second unregistered update into a grid it already had.
    t.update_unregistered_grid_position(
        b, [SimpleWaypointIndex(6), SimpleWaypointIndex(7)], local
    )
    assert_equal(len(t.get_overlapping_vehicles(b)), 2)
    # The path moves on: grid 0 is freed.
    t.update_grid_position(a, [SimpleWaypointIndex(10)], local)
    assert_true(t.is_geo_grid_free(JuncId(0)))
    assert_equal(len(t.get_overlapping_vehicles(ActorId(9))), 0)
    t.add_taken_grid(JuncId(7), a)
    assert_false(t.is_geo_grid_free(JuncId(7)))
    # A known grid is not claimed again.
    t.add_taken_grid(JuncId(7), b)
    t.delete_actor(a)
    t.delete_actor(b)
    assert_true(t.is_geo_grid_free(JuncId(1)))
    assert_equal(len(t.get_overlapping_vehicles(b)), 0)
    t.set_hero_location(Vector3(1, 2, 3))
    assert_true(t.get_hero_location() == Vector3(1, 2, 3))
    t.update_passing_vehicle(WaypointId(3), a)
    t.clear()
    assert_equal(len(t.get_passing_vehicles(WaypointId(3))), 0)
    assert_true(t.get_hero_location() == Vector3(1, 2, 3))
    with assert_raises(contains="not valid"):
        t.update_grid_position(ActorId(-1), [SimpleWaypointIndex(0)], local)
    with assert_raises(contains="not valid"):
        t.add_taken_grid(JuncId(1 << 40), a)
    with assert_raises(contains="not valid"):
        t.delete_actor(ActorId(-1))


def _kinematic(x: Float32, y: Float32) -> KinematicState:
    return KinematicState(
        Vector3(x, y, 0),
        no_rotation(),
        Vector3(1, 0, 0),
        Velocity(30, KILOMETER_PER_HOUR),
        True,
        False,
        Vector3(0, 0, 0),
    )


def _attributes() -> StaticAttributes:
    return StaticAttributes(
        TRAFFIC_VEHICLE, Length(2.4), Length(1.0), Length(0.75)
    )


def test_simulation_state_records() raises:
    var s = SimulationState()
    var a = ActorId(4)
    s.add_actor(
        a, _kinematic(1, 2), _attributes(), TrafficLightInfo(RED, False)
    )
    assert_true(s.contains_actor(a))
    # A second add keeps the first records.
    s.add_actor(
        a, _kinematic(9, 9), _attributes(), TrafficLightInfo(RED, False)
    )
    assert_equal(s.get_location(a).x, 1.0)
    assert_equal(s.get_heading(a).x, 1.0)
    assert_equal(s.get_velocity(a).x, 1.0)
    _near(s.get_speed_limit(a).value, 8.333333)
    assert_true(s.is_physics_enabled(a))
    assert_false(s.is_dormant(a))
    assert_true(s.get_type(a) == TRAFFIC_VEHICLE)
    assert_equal(s.get_dimensions(a).y, 1.0)
    assert_equal(s.get_rotation(a).yaw, 0.0)
    s.update_kinematic_hybrid_end_location(a, Vector3(5, 6, 7))
    assert_equal(s.get_hybrid_end_location(a).y, 6.0)
    s.update_kinematic_state(a, _kinematic(3, 4))
    assert_equal(s.get_kinematic_state(a).location.y, 4.0)
    s.remove_actor(a)
    assert_false(s.contains_actor(a))
    s.remove_actor(a)
    with assert_raises(contains="does not track"):
        _ = s.get_location(a)
    with assert_raises(contains="not valid"):
        s.add_actor(
            ActorId(-1),
            _kinematic(0, 0),
            _attributes(),
            TrafficLightInfo(RED, False),
        )
    with assert_raises(contains="not valid"):
        s.add_actor(
            a,
            _kinematic(0, 0),
            StaticAttributes(
                TrafficActorType(7), Length(1), Length(1), Length(1)
            ),
            TrafficLightInfo(RED, False),
        )
    s.add_actor(
        a, _kinematic(1, 2), _attributes(), TrafficLightInfo(RED, False)
    )
    s.reset()
    assert_false(s.contains_actor(a))
    assert_true(TRAFFIC_ANY.is_valid() and TRAFFIC_PEDESTRIAN.is_valid())
    assert_false(TrafficActorType(-1).is_valid())


def test_green_is_kept_at_a_light() raises:
    var s = SimulationState()
    var a = ActorId(4)
    s.add_actor(
        a, _kinematic(0, 0), _attributes(), TrafficLightInfo(GREEN, True)
    )
    # Green at a light hides the yellow that follows.
    s.update_traffic_light_state(a, TrafficLightInfo(YELLOW, True))
    assert_true(s.get_tls(a).tl_state == GREEN)
    # Leaving the light passes the next state on.
    s.update_traffic_light_state(a, TrafficLightInfo(RED, False))
    assert_true(s.get_tls(a).tl_state == GREEN)
    s.update_traffic_light_state(a, TrafficLightInfo(RED, False))
    assert_true(s.get_tls(a).tl_state == RED)
    # Red at a light passes on.
    s.update_traffic_light_state(a, TrafficLightInfo(RED, True))
    s.update_traffic_light_state(a, TrafficLightInfo(YELLOW, True))
    assert_true(s.get_tls(a).tl_state == YELLOW)


# --- localization utilities ----------------------------------------------------------


def test_deviation_products() raises:
    var at = Vector3(0, 0, 0)
    var east = Vector3(1, 0, 0)
    # A target at 45 degrees to the right (plus y) and 5 m up: the cross
    # uses the unit vector in 3D, 1 / sqrt(27); the dot drops z first.
    _near(deviation_cross_product(at, east, Vector3(1, 1, 5)), 0.19245009)
    _near(deviation_dot_product(at, east, Vector3(1, 1, 5)), 0.70710677)
    # Behind: the dot clamps to zero.
    assert_equal(deviation_dot_product(at, east, Vector3(-1, 0, 0)), 0.0)
    # A target on the vehicle is too short to make a unit vector.
    assert_equal(deviation_cross_product(at, east, at), 0.0)


def test_push_pop_and_target() raises:
    var map = load_opendrive(straight_town())
    var local = _graph(map)
    var t = TrackTraffic()
    var a = ActorId(1)
    var buffer = List[SimpleWaypointIndex]()
    # Lane -2 nodes 0 to 9: x = 0, 5, ... 45.
    for i in range(10):
        push_waypoint(a, t, buffer, local, SimpleWaypointIndex(i))
    assert_equal(
        len(t.get_passing_vehicles(local.at(SimpleWaypointIndex(3)).id)), 1
    )
    # 12 m: the scan starts at node 2 (x 10), and node 3 (x 15) is past.
    var target = get_target_waypoint(buffer, local, Length(12))
    assert_equal(target[0].value, 3)
    assert_equal(target[1], 3)
    # 10 m exactly: node 2 is not nearer than 10 m, so it is the target.
    assert_equal(get_target_waypoint(buffer, local, Length(10))[1], 2)
    # Past the end: the last node.
    assert_equal(get_target_waypoint(buffer, local, Length(100))[1], 9)
    # A scan that runs off the end.
    assert_equal(get_target_waypoint(buffer, local, Length(49))[1], 9)
    # Zero: the first node.
    assert_equal(get_target_waypoint(buffer, local, Length(0))[1], 0)
    pop_waypoint(a, t, buffer, local)
    pop_waypoint(a, t, buffer, local, False)
    assert_equal(buffer[0].value, 1)
    assert_equal(buffer[len(buffer) - 1].value, 8)
    assert_equal(
        len(t.get_passing_vehicles(local.at(SimpleWaypointIndex(0)).id)), 0
    )
    var empty = List[SimpleWaypointIndex]()
    with assert_raises(contains="empty"):
        pop_waypoint(a, t, empty, local)
    with assert_raises(contains="empty"):
        _ = get_target_waypoint(empty, local, Length(1))


# --- geometry ---------------------------------------------------------------------------


def test_three_point_radius() raises:
    # Three points on a circle of radius 5 about (1, 1).
    _near(
        three_point_circle_radius(
            Vector3(6, 1, 0), Vector3(1, 6, 0), Vector3(-4, 1, 0)
        ).value,
        5.0,
        1e-4,
    )
    # On a line: no finite circle.
    assert_equal(
        three_point_circle_radius(
            Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0)
        ).value,
        FLOAT_MAX,
    )
    # The second denominator: points on a line of slope one pass the
    # first test only by rounding, so use points where the second
    # denominator alone vanishes. With x1 = x2 = x3 both vanish; with
    # y31 x12 = y21 x13 != 0 and x31 y12 = x21 y13 the second does.
    assert_equal(
        three_point_circle_radius(
            Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(0, 2, 0)
        ).value,
        FLOAT_MAX,
    )


def test_interpolate_buffer_at() raises:
    var vehicle = Vector3(0, 0, 0)
    var empty = interpolate_buffer_at(List[Vector3](), Length(3), vehicle)
    assert_true(empty[0] == vehicle)
    var one = interpolate_buffer_at([Vector3(5, 0, 0)], Length(3), vehicle)
    assert_equal(one[0].x, 5.0)
    var path: List[Vector3] = [
        Vector3(2, 0, 0),
        Vector3(6, 0, 0),
        Vector3(10, 0, 0),
    ]
    # 4 m lies between 2 m and 6 m: halfway.
    var mid = interpolate_buffer_at(path, Length(4), vehicle)
    _near(mid[0].x, 4.0)
    assert_equal(mid[1], 0)
    # 8 m: between the second and the third.
    var far = interpolate_buffer_at(path, Length(8), vehicle)
    _near(far[0].x, 8.0)
    assert_equal(far[1], 1)
    # Past the end: the last node.
    var past = interpolate_buffer_at(path, Length(20), vehicle)
    assert_equal(past[0].x, 10.0)
    assert_equal(past[1], 2)
    # Shorter than the first node: the first segment, backward.
    var short = interpolate_buffer_at(path, Length(1), vehicle)
    _near(short[0].x, 1.0)
    # Two nodes at one distance: the nearer node.
    var same = interpolate_buffer_at(
        [Vector3(0, 3, 0), Vector3(3, 0, 0)], Length(1), vehicle
    )
    assert_equal(same[0].y, 3.0)


def test_large_vehicle_profiles() raises:
    var m = Length(1.0)
    # Near the entry: 0.5 (1 - cos(pi a)) scaled by 0.25 inboard.
    _near(
        large_vehicle_junction_offset_profile(0.15, m, 0.3, 0.25).value, 0.125
    )
    # The middle: cos(pi a).
    _near(
        large_vehicle_junction_offset_profile(0.5, m, 0.3, 0.25).value,
        0.0,
        1e-5,
    )
    _near(
        large_vehicle_junction_offset_profile(0.6, m, 0.3, 0.25).value,
        -0.70710677,
    )
    # Near the exit: -0.5 (1 + cos(pi a)).
    _near(large_vehicle_junction_offset_profile(0.85, m, 0.3, 0.25).value, -0.5)
    # Clamped past both ends.
    _near(large_vehicle_junction_offset_profile(-1, m, 0.3, 0.25).value, 0.0)
    _near(large_vehicle_junction_offset_profile(2, m, 0.3, 0.25).value, 0.0)
    _near(
        large_vehicle_offset_magnitude(
            Length(11), Length(6), 0.25, Length(1.5)
        ).value,
        1.25,
    )
    _near(
        large_vehicle_offset_magnitude(
            Length(20), Length(6), 0.25, Length(1.5)
        ).value,
        1.5,
    )
    _near(
        large_vehicle_offset_magnitude(
            Length(4), Length(6), 0.25, Length(1.5)
        ).value,
        0.0,
    )


def test_offset_side_occupied() raises:
    var at = Vector3(0, 0, 0)
    var forward = Vector3(1, 0, 0)
    var right = Vector3(0, 1, 0)
    var clearance = Length(1)
    var window = Length(3)
    # Beside, on the swing side.
    assert_true(
        is_offset_side_occupied(
            at,
            forward,
            right,
            Length(1),
            clearance,
            window,
            [Neighbor(Vector3(0, 2, 0), Length(1))],
        )
    )
    # On the other side.
    assert_false(
        is_offset_side_occupied(
            at,
            forward,
            right,
            Length(1),
            clearance,
            window,
            [Neighbor(Vector3(0, -3, 0), Length(1))],
        )
    )
    # Too far out.
    assert_false(
        is_offset_side_occupied(
            at,
            forward,
            right,
            Length(1),
            clearance,
            window,
            [Neighbor(Vector3(0, 4, 0), Length(1))],
        )
    )
    # Too far ahead.
    assert_false(
        is_offset_side_occupied(
            at,
            forward,
            right,
            Length(1),
            clearance,
            window,
            [Neighbor(Vector3(10, 1, 0), Length(1))],
        )
    )
    assert_false(
        is_offset_side_occupied(
            at,
            forward,
            right,
            Length(1),
            clearance,
            window,
            List[Neighbor](),
        )
    )


# --- the map ----------------------------------------------------------------------------


def test_road_option_and_ids() raises:
    assert_true(ROAD_OPTION_VOID.is_valid() and ROAD_OPTION_ROAD_END.is_valid())
    assert_false(RoadOption(8).is_valid())
    assert_false(RoadOption(-1).is_valid())
    assert_true(NO_SIMPLE_WAYPOINT.is_valid())
    assert_false(NO_SIMPLE_WAYPOINT.is_some())
    assert_false(SimpleWaypointIndex(-2).is_valid())
    assert_true(WaypointId(0).is_valid())
    assert_false(WaypointId(-1).is_valid())
    assert_equal(c_remainder(-7, 360), -7)
    assert_equal(c_remainder(367, 360), 7)
    assert_equal(c_remainder(-720, 360), 0)
    assert_equal(to_int16(nan[DType.float64]()), 0)
    assert_equal(to_int16(-3.9), -3)
    assert_equal(distance_squared(Vector3(1, 2, 3), Vector3(2, 4, 6)), 14.0)


def test_straight_town_graph() raises:
    var map = load_opendrive(straight_town())
    var local = _graph(map)
    # 60 samples on each of three lanes.
    assert_equal(local.size(), 180)
    assert_equal(len(local.get_dense_topology()), 180)
    # Lane -2 first, then -1, then 1 in its own direction.
    ref first = local.at(SimpleWaypointIndex(0))
    assert_equal(first.waypoint.lane_id.value, -2)
    _near(first.location().y, 5.25)
    assert_equal(first.id.value, 1)
    assert_equal(local.at(SimpleWaypointIndex(60)).id.value, 2)
    assert_equal(local.at(SimpleWaypointIndex(179)).id.value, 3)
    _near(local.at(SimpleWaypointIndex(120)).location().x, 295.0)
    # Grid ids: a new one each 25 m, per lane.
    assert_equal(local.at(SimpleWaypointIndex(4)).geodesic_grid_id.value, 0)
    assert_equal(local.at(SimpleWaypointIndex(5)).geodesic_grid_id.value, 1)
    assert_equal(local.at(SimpleWaypointIndex(59)).geodesic_grid_id.value, 11)
    assert_equal(local.at(SimpleWaypointIndex(60)).geodesic_grid_id.value, 12)
    assert_equal(local.at(SimpleWaypointIndex(179)).geodesic_grid_id.value, 35)
    # Links along the lane, and the lane changes -1 to -2 and back.
    assert_equal(local.at(SimpleWaypointIndex(0)).next_waypoints[0].value, 1)
    assert_equal(
        local.at(SimpleWaypointIndex(1)).previous_waypoints[0].value, 0
    )
    assert_equal(local.at(SimpleWaypointIndex(0)).next_left_waypoint.value, 60)
    assert_false(local.at(SimpleWaypointIndex(0)).next_right_waypoint.is_some())
    assert_equal(local.at(SimpleWaypointIndex(60)).next_right_waypoint.value, 0)
    assert_false(
        local.at(SimpleWaypointIndex(150)).next_left_waypoint.is_some()
    )
    # Options: lane follow, and road end at each lane's last node.
    assert_true(
        local.at(SimpleWaypointIndex(3)).road_option == ROAD_OPTION_LANE_FOLLOW
    )
    assert_true(
        local.at(SimpleWaypointIndex(59)).road_option == ROAD_OPTION_ROAD_END
    )
    assert_true(
        local.at(SimpleWaypointIndex(179)).road_option == ROAD_OPTION_ROAD_END
    )
    assert_false(local.at(SimpleWaypointIndex(3)).check_intersection())
    assert_false(local.at(SimpleWaypointIndex(3)).check_junction())
    _near(local.at(SimpleWaypointIndex(1)).distance(Vector3(8, 1.25, 0)), 5.0)
    assert_true(
        local.at(SimpleWaypointIndex(1)).forward_vector() == Vector3(1, 0, 0)
    )
    assert_equal(
        local.at(SimpleWaypointIndex(1)).get_geodesic_grid_id().value, 0
    )


def test_graph_queries() raises:
    var map = load_opendrive(straight_town())
    var local = _graph(map)
    # The nearest node: lane -1 at x = 50.
    assert_equal(local.get_waypoint(Vector3(51, 2, 0)).value, 70)
    # The ring about x = 150 with an inner half width of 10 m: x from 120
    # to 140 and 160 to 180, lane -2 first.
    var ring = local.get_waypoints_in_delta(
        Vector3(150, 1.75, 0), 5, Length(10)
    )
    assert_equal(len(ring), 5)
    assert_equal(ring[0].value, 24)
    assert_equal(ring[4].value, 28)
    var all = local.get_waypoints_in_delta(
        Vector3(150, 1.75, 0), 100, Length(10)
    )
    assert_equal(len(all), 30)
    assert_equal(
        len(local.get_waypoints_in_delta(Vector3(150, 1.75, 0), 0, Length(10))),
        0,
    )
    with assert_raises(contains="must not be negative"):
        _ = local.get_waypoints_in_delta(Vector3(0, 0, 0), -1, Length(1))
    var empty = InMemoryMap()
    with assert_raises(contains="empty"):
        _ = empty.get_waypoint(Vector3(0, 0, 0))
    with assert_raises(contains="names no node"):
        _ = local.at(SimpleWaypointIndex(180))
    with assert_raises(contains="names no node"):
        _ = local.set_next_waypoints(
            SimpleWaypointIndex(0), [NO_SIMPLE_WAYPOINT]
        )
    with assert_raises(contains="names no node"):
        _ = local.set_previous_waypoints(
            SimpleWaypointIndex(0), [SimpleWaypointIndex(999)]
        )
    with assert_raises(contains="already built"):
        local.set_up(map)


def test_junction_town_graph() raises:
    var map = load_opendrive(junction_town())
    var local = InMemoryMap()
    local.set_up(map)
    # Road 1 lane -1's last node forks to roads 10 and 11. The map lists
    # road 10 twice, once from the lane's link and once from the
    # junction's connection, and the graph keeps both.
    var fork = NO_SIMPLE_WAYPOINT
    for i in range(local.size()):
        ref w = local.waypoints[i]
        if (
            w.waypoint.road_id.value == 1
            and w.waypoint.lane_id.value == -1
            and len(w.next_waypoints) >= 2
        ):
            fork = SimpleWaypointIndex(i)
    assert_true(fork.is_some())
    assert_true(local.at(fork).check_intersection())
    assert_true(local.at(fork).road_option == ROAD_OPTION_LANE_FOLLOW)
    var roads = List[Int]()
    for n in local.at(fork).next_waypoints:
        roads.append(local.at(n).waypoint.road_id.value)
        assert_true(local.at(n).check_junction())
    assert_true(10 in roads and 11 in roads)
    # Road 10 goes straight, road 11 turns right; the junction's grid is
    # its id. Road 11 turns 0.5 rad each 5 m, so each gap gets five more
    # nodes: 4 + 15 on it.
    var turn_nodes = 0
    for i in range(local.size()):
        ref w = local.waypoints[i]
        if w.waypoint.road_id.value == 10:
            assert_true(w.road_option == ROAD_OPTION_STRAIGHT)
            assert_equal(w.get_geodesic_grid_id().value, 100)
            assert_true(w.check_junction())
        if w.waypoint.road_id.value == 11:
            assert_true(w.road_option == ROAD_OPTION_RIGHT)
            turn_nodes += 1
        if w.waypoint.road_id.value == 3 and w.waypoint.lane_id.value == 1:
            assert_true(
                w.road_option == ROAD_OPTION_ROAD_END
                or len(w.next_waypoints) == 1
            )
    assert_equal(turn_nodes, 19)
    # Road 2 lane 1 forks into road 10 (twice): lane follow, and road
    # 10's lane 1 is straight.
    for i in range(local.size()):
        ref w = local.waypoints[i]
        if w.waypoint.road_id.value == 2 and w.waypoint.lane_id.value == 1:
            assert_true(w.road_option == ROAD_OPTION_LANE_FOLLOW)


def test_one_path_junction_is_not_real() raises:
    # Only road 10 through the junction: its nodes are not in a junction
    # for the traffic manager, though the road is a junction road.
    var text = junction_town().replace(
        """<connection id="2" incomingRoad="1" connectingRoad="11" contactPoint="start"><laneLink from="-1" to="-1"/></connection>""",
        "",
    )
    text = text.replace(
        """<predecessor elementType="road" elementId="1" contactPoint="end"/>
      <successor elementType="road" elementId="3" contactPoint="start"/>""",
        "",
    )
    var map = load_opendrive(text)
    var local = InMemoryMap()
    local.set_up(map)
    for i in range(local.size()):
        ref w = local.waypoints[i]
        if w.waypoint.road_id.value == 10:
            assert_false(w.check_junction())
            assert_true(w.road_is_junction)
            assert_equal(w.get_geodesic_grid_id().value, 100)


def test_road_options_by_hand() raises:
    # A graph linked by hand on the straight town: a fork into two nodes
    # outside a junction, and single steps into a node marked as a
    # junction, with and without a sign near.
    var map = load_opendrive(straight_town())
    var local = InMemoryMap()
    var w0 = Waypoint(RoadId(1), SectionId(0), LaneId(-2), 10.0)
    var w1 = Waypoint(RoadId(1), SectionId(0), LaneId(-2), 15.0)
    var w2 = Waypoint(RoadId(1), SectionId(0), LaneId(-1), 15.0)
    var w3 = Waypoint(RoadId(1), SectionId(0), LaneId(-1), 140.0)
    var w4 = Waypoint(RoadId(1), SectionId(0), LaneId(-1), 145.0)
    var a = local.add_waypoint(map, w0)
    var b = local.add_waypoint(map, w1)
    var c = local.add_waypoint(map, w2)
    var d = local.add_waypoint(map, w3)
    var e = local.add_waypoint(map, w4)
    var f = local.add_waypoint(map, w0)
    # Same place, same id.
    assert_equal(local.at(f).id.value, local.at(a).id.value)
    _ = local.set_next_waypoints(a, [b, c])
    _ = local.set_next_waypoints(d, [e])
    local.waypoints[e.value].is_junction = True
    _ = local.set_next_waypoints(f, [b])
    local.waypoints[b.value].is_junction = True
    local.waypoints[c.value].is_junction = False
    _ = local.set_next_waypoints(b, [e])
    local.set_up_road_option(map)
    # The fork: b is a junction node that runs on into e, both junction.
    assert_true(local.at(a).road_option == ROAD_OPTION_LANE_FOLLOW)
    assert_true(local.at(b).road_option == ROAD_OPTION_STRAIGHT)
    # c is not in a junction, so the fork's walk from it finds nothing;
    # c itself ends the graph.
    assert_true(local.at(c).road_option == ROAD_OPTION_ROAD_END)
    # d: the 60 km/h sign within 15 m is no junction sign.
    assert_true(local.at(d).road_option == ROAD_OPTION_LANE_FOLLOW)
    # f: no landmark near.
    assert_true(local.at(f).road_option == ROAD_OPTION_LANE_FOLLOW)
    # The left and right links check the side.
    local.set_left_waypoint(a, c)
    assert_equal(local.at(a).next_left_waypoint.value, c.value)
    local.set_right_waypoint(a, c)
    assert_false(local.at(a).next_right_waypoint.is_some())
    local.set_right_waypoint(c, a)
    assert_equal(local.at(c).next_right_waypoint.value, a.value)
    local.set_left_waypoint(c, a)
    assert_false(local.at(c).next_left_waypoint.is_some())


def test_junction_sign_marks_the_approach() raises:
    # Road 2 lane 1 at s 2 steps into road 10 lane 1, marked as a
    # junction: the yield sign at s 18 of road 10 is 4 m on, so the walk
    # through the junction runs and finds it straight.
    var map = load_opendrive(junction_town())
    var local = InMemoryMap()
    var a = local.add_waypoint(
        map, Waypoint(RoadId(2), SectionId(0), LaneId(1), 2.0)
    )
    var b = local.add_waypoint(
        map, Waypoint(RoadId(10), SectionId(0), LaneId(1), 15.0)
    )
    var c = local.add_waypoint(
        map, Waypoint(RoadId(10), SectionId(0), LaneId(1), 5.0)
    )
    local.waypoints[b.value].is_junction = True
    local.waypoints[c.value].is_junction = True
    _ = local.set_next_waypoints(a, [b])
    _ = local.set_next_waypoints(b, [c])
    local.set_up_road_option(map)
    assert_true(local.at(a).road_option == ROAD_OPTION_LANE_FOLLOW)
    assert_true(local.at(b).road_option == ROAD_OPTION_STRAIGHT)


def test_turn_directions_by_yaw() raises:
    # Two junction nodes on road 11's arc, linked by hand, give a right
    # turn; linked the other way, a left one.
    var map = load_opendrive(junction_town())
    var local = InMemoryMap()
    var start = local.add_waypoint(
        map, Waypoint(RoadId(1), SectionId(0), LaneId(-1), 90.0)
    )
    var enter = local.add_waypoint(
        map, Waypoint(RoadId(11), SectionId(0), LaneId(-1), 1.0)
    )
    var leave = local.add_waypoint(
        map, Waypoint(RoadId(11), SectionId(0), LaneId(-1), 15.0)
    )
    local.waypoints[enter.value].is_junction = True
    local.waypoints[leave.value].is_junction = True
    _ = local.set_next_waypoints(start, [enter, leave])
    _ = local.set_next_waypoints(enter, [leave])
    local.set_up_road_option(map)
    assert_true(local.at(enter).road_option == ROAD_OPTION_RIGHT)
    var back = InMemoryMap()
    var s2 = back.add_waypoint(
        map, Waypoint(RoadId(1), SectionId(0), LaneId(-1), 90.0)
    )
    var e2 = back.add_waypoint(
        map, Waypoint(RoadId(11), SectionId(0), LaneId(-1), 15.0)
    )
    var l2 = back.add_waypoint(
        map, Waypoint(RoadId(11), SectionId(0), LaneId(-1), 1.0)
    )
    back.waypoints[e2.value].is_junction = True
    back.waypoints[l2.value].is_junction = True
    _ = back.set_next_waypoints(s2, [e2, l2])
    _ = back.set_next_waypoints(e2, [l2])
    back.set_up_road_option(map)
    assert_true(back.at(e2).road_option == ROAD_OPTION_LEFT)


def test_cache_round_trip() raises:
    var map = load_opendrive(straight_town())
    var local = _graph(map)
    var bytes = local.save()
    # 4 + 3 lanes of 60 records of 50 bytes and 118 links of 8 bytes.
    assert_equal(len(bytes), 11836)
    # The first record: id 1, road 1, section 0, lane -2 in two's
    # complement.
    assert_equal(bytes[0], 180)
    assert_equal(bytes[4], 1)
    assert_equal(bytes[12], 1)
    assert_equal(bytes[20], 0xFE)
    assert_equal(bytes[23], 0xFF)
    var loaded = InMemoryMap()
    assert_true(loaded.load(map, bytes))
    assert_equal(loaded.size(), 180)
    for i in range(180):
        ref x = local.waypoints[i]
        ref y = loaded.waypoints[i]
        assert_true(x.waypoint == y.waypoint)
        assert_equal(len(x.next_waypoints), len(y.next_waypoints))
        assert_equal(x.next_left_waypoint.value, y.next_left_waypoint.value)
        assert_equal(x.next_right_waypoint.value, y.next_right_waypoint.value)
        assert_equal(
            x.get_geodesic_grid_id().value, y.get_geodesic_grid_id().value
        )
        assert_true(x.road_option == y.road_option)
    assert_equal(loaded.get_waypoint(Vector3(51, 2, 0)).value, 70)
    assert_equal(len(cook(map)), 11836)
    makedirs("out/carla_tm", exist_ok=True)
    var path = "out/carla_tm/straight.bin"
    local.save_file(path)
    var from_file = InMemoryMap()
    assert_true(from_file.load_file(map, path))
    assert_equal(from_file.size(), 180)
    with assert_raises(contains="already built"):
        _ = from_file.load(map, bytes)


def test_cache_refuses_bad_bytes() raises:
    var map = load_opendrive(straight_town())
    var bytes = _graph(map).save()
    var short = List[UInt8]()
    for i in range(30):
        short.append(bytes[i])
    with assert_raises(contains="ends too early"):
        var fresh = InMemoryMap()
        _ = fresh.load(map, short)
    # The first record's road option is its last byte, at 4 + 57.
    var option = bytes.copy()
    option[61] = 9
    with assert_raises(contains="road option is not valid"):
        var fresh = InMemoryMap()
        _ = fresh.load(map, option)
    # Road 99 is not on the map.
    var road = bytes.copy()
    road[12] = 99
    with assert_raises(contains="not on the map"):
        var fresh = InMemoryMap()
        _ = fresh.load(map, road)
    # The first record's next id, at 4 + 26, names no record.
    var link = bytes.copy()
    link[30] = 0xEE
    link[31] = 0xEE
    with assert_raises(contains="names no cached waypoint"):
        var fresh = InMemoryMap()
        _ = fresh.load(map, link)
    var record = CachedSimpleWaypoint()
    assert_equal(record.waypoint_id, 0)


def _lane(id: Int, width: Float64, change: String, link: String) -> String:
    return String(
        '<lane id="',
        id,
        '" type="driving">',
        link,
        '<width sOffset="0" a="',
        width,
        '" b="0" c="0" d="0"/><roadMark sOffset="0" type="broken"',
        ' weight="standard" color="white" width="0.15" laneChange="',
        change,
        '"/></lane>',
    )


def _right(lanes: String, s: Int) -> String:
    return String(
        '<laneSection s="',
        s,
        '"><center><lane id="0" type="none"/></center><right>',
        lanes,
        "</right></laneSection>",
    )


def section_town() -> String:
    """Road 1, 100 m along x, in three sections: lanes -1 and -2 to s 40,
    a 3 m section where lane -2 is 0.8 m wide, and both lanes again from
    s 43. Lane -2 ends with road 1; lane -1 runs on through junction 100
    on road 10 (two sections, at s 0 and 10) to road 2, 50 m long. The
    file lists the roads as 2, 10, 1.
    """
    var both = '<link><predecessor id="-1"/><successor id="-1"/></link>'
    var both2 = '<link><predecessor id="-2"/><successor id="-2"/></link>'
    var road1 = String(
        '<road name="a" length="100" id="1" junction="-1"><link><successor',
        ' elementType="junction" elementId="100"/></link><planView><geometry',
        ' s="0" x="0" y="0" hdg="0" length="100"><line/></geometry>',
        "</planView><lanes>",
        _right(
            _lane(-1, 3.5, "both", '<link><successor id="-1"/></link>')
            + _lane(-2, 3.5, "both", '<link><successor id="-2"/></link>'),
            0,
        ),
        _right(
            _lane(-1, 3.5, "both", both) + _lane(-2, 0.8, "none", both2), 40
        ),
        _right(
            _lane(-1, 3.5, "both", both)
            + _lane(-2, 3.5, "both", '<link><predecessor id="-2"/></link>'),
            43,
        ),
        "</lanes></road>",
    )
    var road10 = String(
        '<road name="j" length="20" id="10" junction="100"><link><predecessor',
        ' elementType="road" elementId="1" contactPoint="end"/><successor',
        ' elementType="road" elementId="2" contactPoint="start"/></link>',
        '<planView><geometry s="0" x="100" y="0" hdg="0" length="20"><line/>',
        "</geometry></planView><lanes>",
        _right(_lane(-1, 3.5, "none", both), 0),
        _right(_lane(-1, 3.5, "none", both), 10),
        "</lanes></road>",
    )
    var road2 = String(
        '<road name="b" length="50" id="2" junction="-1"><link><predecessor',
        ' elementType="junction" elementId="100"/></link><planView><geometry',
        ' s="0" x="120" y="0" hdg="0" length="50"><line/></geometry>',
        "</planView><lanes>",
        _right(
            _lane(-1, 3.5, "none", '<link><predecessor id="-1"/></link>'), 0
        ),
        "</lanes></road>",
    )
    return String(
        '<?xml version="1.0" encoding="UTF-8"?><OpenDRIVE><header',
        ' revMajor="1" revMinor="4" name="sections" version="1.0"/>',
        road2,
        road10,
        road1,
        '<junction id="100" name="j"><connection id="0" incomingRoad="1"',
        ' connectingRoad="10" contactPoint="start"><laneLink from="-1"',
        ' to="-1"/></connection></junction></OpenDRIVE>',
    )


def test_sections_narrow_lanes_and_lane_ends() raises:
    var map = load_opendrive(section_town())
    var local = _graph(map)
    # Samples each 5 m: lane -2 has 8 before s 40, none in the narrow
    # section and 11 after; lane -1 has 8, the one at s 40, and 11; road
    # 2 has 10 and road 10 two in each section.
    assert_equal(local.size(), 53)
    ref at35 = local.at(local.get_waypoint(Vector3(35, 5.25, 0)))
    ref at45 = local.at(local.get_waypoint(Vector3(45, 5.25, 0)))
    # Lane -2 links over its narrow section, from s 35 to s 45.
    assert_equal(len(at35.next_waypoints), 1)
    assert_equal(local.at(at35.next_waypoints[0]).waypoint.s, 45.0)
    assert_equal(at45.waypoint.section_id.value, 2)
    # Lane -1's one node in the short section links 35, 40 and 45.
    var mid = local.get_waypoint(Vector3(40, 1.75, 0))
    assert_equal(local.at(mid).waypoint.section_id.value, 1)
    assert_equal(local.at(local.at(mid).next_waypoints[0]).waypoint.s, 45.0)
    assert_equal(local.at(local.at(mid).previous_waypoints[0]).waypoint.s, 35.0)
    # Lane -2's last node, a dead end, takes lane -1's next node: road
    # 10's first.
    ref end = local.at(local.get_waypoint(Vector3(95, 5.25, 0)))
    assert_equal(len(end.next_waypoints), 1)
    ref into = local.at(end.next_waypoints[0])
    assert_equal(into.waypoint.road_id.value, 10)
    _near(into.location().x, 100.0)
    # Road 10's two sections link; one path, so not a real junction.
    ref j = local.at(local.get_waypoint(Vector3(105, 1.75, 0)))
    assert_equal(local.at(j.next_waypoints[0]).waypoint.section_id.value, 1)
    assert_false(j.check_junction())
    # The nodes are in the order of (road, lane, section): road 1 first,
    # though the file lists it last.
    assert_equal(local.at(SimpleWaypointIndex(0)).waypoint.road_id.value, 1)
    assert_equal(local.at(SimpleWaypointIndex(0)).waypoint.lane_id.value, -2)
    assert_equal(local.at(SimpleWaypointIndex(52)).waypoint.road_id.value, 10)


def test_empty_map_graph() raises:
    var map = load_opendrive(
        '<?xml version="1.0"?><OpenDRIVE><header revMajor="1" revMinor="4"'
        ' name="e" version="1.0"/></OpenDRIVE>'
    )
    var local = _graph(map)
    assert_equal(local.size(), 0)
    assert_equal(len(local.get_dense_topology()), 0)
    var bytes = local.save()
    assert_equal(len(bytes), 4)
    var back = InMemoryMap()
    assert_true(back.load(map, bytes))
    assert_equal(back.size(), 0)
    makedirs("out/carla_tm", exist_ok=True)
    var path = "out/carla_tm/empty.bin"
    Path(path).write_bytes(List[UInt8]())
    var from_file = InMemoryMap()
    with assert_raises(contains="ends too early"):
        _ = from_file.load_file(map, path)


def test_order_segment_sorts_and_stops_at_a_dead_end() raises:
    # Lane 1 at s 290 and lane -1 at s 299.99, given out of order. Sorted
    # by s, lane 1 first; lane 1 runs against s, so the list turns round.
    # The two face opposite ways: 36 splits, the first 0.27 m past s
    # 299.99, beyond the road's end at 300. No node is added.
    var map = load_opendrive(straight_town())
    var local = InMemoryMap()
    var a = local.add_waypoint(
        map, Waypoint(RoadId(1), SectionId(0), LaneId(-1), 299.99)
    )
    var b = local.add_waypoint(
        map, Waypoint(RoadId(1), SectionId(0), LaneId(1), 290.0)
    )
    var ordered = local._order_segment(map, [a, b])
    assert_equal(len(ordered), 2)
    assert_equal(ordered[0].value, a.value)
    assert_equal(ordered[1].value, b.value)
    assert_equal(local.size(), 2)


def test_ring_skips_junction_nodes() raises:
    var map = load_opendrive(junction_town())
    var local = _graph(map)
    # The square 25 m about (110, 0) holds the junction's nodes and road
    # 1's and road 2's; the junction's are left out.
    var found = local.get_waypoints_in_delta(
        Vector3(110, 0, 0), 1000, Length(0)
    )
    assert_true(len(found) > 0)
    for w in found:
        assert_false(local.at(w).check_junction())
    var junction_nodes = 0
    for i in range(local.size()):
        ref w = local.at(SimpleWaypointIndex(i))
        if (
            w.check_junction()
            and abs(w.location().x - 110) < 25
            and abs(w.location().y) < 25
        ):
            junction_nodes += 1
    assert_true(junction_nodes > 0)


def test_light_and_stop_sign_mark_the_approach() raises:
    # As the yield sign above: a light or a stop sign in its place also
    # makes the approach a junction's.
    for kind in ["1000001", "206"]:
        var map = load_opendrive(
            junction_town().replace('type="205"', String('type="', kind, '"'))
        )
        var local = InMemoryMap()
        var a = local.add_waypoint(
            map, Waypoint(RoadId(2), SectionId(0), LaneId(1), 2.0)
        )
        var b = local.add_waypoint(
            map, Waypoint(RoadId(10), SectionId(0), LaneId(1), 15.0)
        )
        var c = local.add_waypoint(
            map, Waypoint(RoadId(10), SectionId(0), LaneId(1), 5.0)
        )
        local.waypoints[b.value].is_junction = True
        local.waypoints[c.value].is_junction = True
        _ = local.set_next_waypoints(a, [b])
        _ = local.set_next_waypoints(b, [c])
        local.set_up_road_option(map)
        assert_true(local.at(b).road_option == ROAD_OPTION_STRAIGHT)


def test_empty_lists_in_settings_and_state() raises:
    var p = Parameters()
    var a = ActorId(1)
    # An ignore list emptied, then asked to detect another actor.
    p.set_collision_detection(a, ActorId(2), False)
    p.set_collision_detection(a, ActorId(2), True)
    p.set_collision_detection(a, ActorId(3), True)
    assert_true(p.get_collision_detection(a, ActorId(2)))
    # An empty route.
    p.set_imported_route(a, List[RoadOption](), True)
    assert_equal(len(p.get_imported_route(a)), 0)
    # An actor on no grid overlaps nothing, and deletes cleanly.
    var t = TrackTraffic()
    var map = load_opendrive(straight_town())
    var local = _graph(map)
    t.update_unregistered_grid_position(a, List[SimpleWaypointIndex](), local)
    assert_equal(len(t.get_overlapping_vehicles(a)), 0)
    t.delete_actor(a)
    # An empty path: the target is the vehicle.
    var target = get_target_data(
        List[SimpleWaypointIndex](), local, Length(5), Vector3(1, 2, 3)
    )
    assert_true(target[0] == Vector3(1, 2, 3))
    assert_equal(target[1], 0)


def test_segment_keys_sort_by_road_lane_and_section() raises:
    # The smallest key last: it moves to the front.
    var keys: List[_SegmentKey] = [
        _SegmentKey(3, -1, 0),
        _SegmentKey(1, -1, 1),
        _SegmentKey(1, -1, 0),
        _SegmentKey(1, -2, 4),
    ]
    _sort_keys(keys)
    assert_equal(keys[0].text(), "1:-2:4")
    assert_equal(keys[1].text(), "1:-1:0")
    assert_equal(keys[2].text(), "1:-1:1")
    assert_equal(keys[3].text(), "3:-1:0")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
