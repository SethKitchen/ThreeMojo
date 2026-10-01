# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The traffic manager's last three stages: lights, motion and lamps.

**Traffic lights and signs** (CARLA's `TrafficLightStage`). A vehicle at
a red or yellow light stops, unless its chance to run lights wins a
draw. A vehicle that the world tells to stop without a light, at a stop
or yield sign before a junction, joins the junction's queue unless its
chance to run signs wins. In the queue, it first stops fully (below
0.001 m/s), then waits 2 s, and goes only when it is first in the queue.
It leaves the queue when it leaves the junction.

**Motion planning** (CARLA's `MotionPlanStage`). The target speed is the
limit less the speed difference, or the desired speed. It drops near a
light (to 15 km/h), a stop or yield sign (10 km/h) and a lower speed
limit, linearly over 3.5 s of travel, and on a curve to
sqrt(r 0.6 9.81). A hazard ahead sets the target to the other actor's
speed while the gap is more than 2 s of speed plus 2 m, to at least
12 km/h closer in, and brakes fully inside 0.2 m. The speed falls at most
8 % a step. A vehicle with physics is driven by the PID controller
toward a point 0.5 s ahead on its path (at least 3 m). A vehicle without
physics (hybrid mode) is moved each step by its target speed times
0.05 s, along its path. A dormant vehicle, with respawn on and a hero
alive, is moved to a free spot between the respawn bounds from the hero.

**Vehicle lights** (CARLA's `VehicleLightStage`). For a vehicle whose
lights the traffic manager switches: the brake lights while braking
harder than 0.5, a blinker before a turn in a junction within 15 m, the
position lights and low beams at night or in heavy rain or fog, and the
fog lights in fog.

**Differences from CARLA.** The world always has weather. CARLA's
`std::set_difference` in the safe-space check needs sorted input and is
given hash sets; here the difference is the plain one.

Source: CARLA 1360bb9, `LibCarla/source/carla/trafficmanager/TrafficLightStage.cpp`,
`MotionPlanStage.cpp` and `VehicleLightStage.cpp`.
"""

from extensions.carla.actor import ActorId, GREEN, OFF, TrafficLightState
from extensions.carla.map import Map
from extensions.carla.math import make_unit_vector
from extensions.carla.physics.quantities import KILOMETER_PER_HOUR
from extensions.carla.physics.vehicle_control import VehicleControl
from extensions.carla.road_info import JuncId, NO_JUNCTION
from extensions.carla.traffic_manager_constants import (
    AFTER_JUNCTION_MIN_SPEED,
    ATTEMPTS_TO_TELEPORT,
    CRITICAL_BRAKING_MARGIN,
    EPSILON,
    EPSILON_RELATIVE_SPEED,
    FOG_DENSITY_THRESHOLD,
    FOLLOW_LEAD_FACTOR,
    FRICTION,
    GRAVITY,
    HEAVY_PRECIPITATION_THRESHOLD,
    HIGHWAY_SPEED,
    HYBRID_MODE_DT,
    HYBRID_MODE_DT_SECONDS,
    JUNCTION_LOOK_AHEAD,
    LANDMARK_DETECTION_TIME,
    LARGE_VEHICLES_JUNCTION_CLEARANCE,
    LARGE_VEHICLES_JUNCTION_INBOARD_SCALE,
    LARGE_VEHICLES_JUNCTION_OFFSET,
    LARGE_VEHICLES_JUNCTION_OFFSET_GAIN,
    LARGE_VEHICLES_JUNCTION_POINT,
    LARGE_VEHICLES_JUNCTION_REF_LENGTH,
    LARGE_VEHICLES_JUNCTION_SIDE_MARGIN,
    MAX_DISTANCE_LIGHT_CHECK,
    MAX_JUNCTION_BLOCK_DISTANCE,
    MIN_FOLLOW_LEAD_DISTANCE,
    MIN_SAFE_INTERVAL_LENGTH,
    MIN_TARGET_WAYPOINT_DISTANCE,
    MINIMUM_STOP_TIME,
    PERC_MAX_SLOWDOWN,
    PI,
    RELATIVE_APPROACH_SPEED,
    STOP_TARGET_VELOCITY,
    SUN_ALTITUDE_DEGREES_AFTER_SUNSET,
    SUN_ALTITUDE_DEGREES_BEFORE_DAWN,
    SUN_ALTITUDE_DEGREES_JUST_AFTER_DAWN,
    SUN_ALTITUDE_DEGREES_JUST_BEFORE_SUNSET,
    TARGET_WAYPOINT_TIME_HORIZON,
    TL_TARGET_VELOCITY,
    YIELD_TARGET_VELOCITY,
)
from extensions.carla.traffic_manager_map import (
    ROAD_OPTION_LEFT,
    ROAD_OPTION_RIGHT,
    SimpleWaypointIndex,
    distance_squared,
)
from extensions.carla.traffic_manager_pid import (
    LATERAL_HIGHWAY_PARAM,
    LATERAL_PARAM,
    LONGITUDINAL_HIGHWAY_PARAM,
    LONGITUDINAL_PARAM,
    PIDParameters,
    StateEntry,
    run_step,
)
from extensions.carla.traffic_manager_shared import (
    APPLY_VEHICLE_CONTROL,
    CollisionHazardData,
    LocalizationData,
    TrafficManagerShared,
    apply_transform,
    apply_vehicle_control,
    set_vehicle_light_state,
)
from extensions.carla.traffic_manager_state import (
    FLOAT_MAX,
    KinematicState,
    Neighbor,
    get_target_data,
    get_target_waypoint,
    is_offset_side_occupied,
    large_vehicle_junction_offset_profile,
    large_vehicle_offset_magnitude,
    three_point_circle_radius,
)
from extensions.carla.transform import CarlaTransform
from extensions.carla.vehicle import (
    LIGHT_BRAKE,
    LIGHT_FOG,
    LIGHT_HIGH_BEAM,
    LIGHT_LEFT_BLINKER,
    LIGHT_LOW_BEAM,
    LIGHT_POSITION,
    LIGHT_RIGHT_BLINKER,
    VehicleLightState,
)
from extensions.carla.weather import WeatherParameters
from extensions.carla.world_snapshot import Timestamp
from math.vector3 import Vector3
from std.collections import Dict
from std.math import atan2, sqrt
from units.si import DEGREE, Duration, Length, SECOND, Velocity


def _drop(mut list: List[Int], value: Int):
    # The one caller drops a queued vehicle from its own queue.
    for i in range(len(list)):  # pragma: no branch
        if list[i] == value:
            _ = list.pop(i)
            return


# --- TrafficLightStage ---------------------------------------------------------


struct TrafficLightStage(Movable):
    """The traffic-light stage, CARLA's `TrafficLightStage`."""

    # The vehicles queued at each junction without lights, in order.
    var entering_vehicles_map: Dict[Int, List[Int]]
    # The junction each queued vehicle is at.
    var vehicle_last_junction: Dict[Int, Int]
    # When each queued vehicle stopped, in simulated seconds.
    var vehicle_stop_time: Dict[Int, Float64]

    def __init__(out self):
        """Create an empty stage."""
        self.entering_vehicles_map = Dict[Int, List[Int]]()
        self.vehicle_last_junction = Dict[Int, Int]()
        self.vehicle_stop_time = Dict[Int, Float64]()

    def update(
        mut self,
        index: Int,
        mut shared: TrafficManagerShared,
        timestamp: Timestamp,
    ) raises:
        """Decide whether a light or a sign stops one vehicle, `Update`.

        Args:
            index: The vehicle's place in `shared.vehicle_id_list`.
            shared: The traffic manager's state.
            timestamp: The world's time now.

        Raises:
            Error: If the index is out of range, or the vehicle is not
                tracked or has no path.
        """
        if index < 0 or index >= len(shared.vehicle_id_list):
            raise Error("The vehicle index is out of range")
        var hazard = False
        var ego = shared.vehicle_id_list[index]
        if not shared.simulation_state.is_dormant(ego):
            var current = self.vehicle_last_junction.get(ego.value, -1)
            var affected = self.get_affected_junction_id(ego, shared)
            var light = shared.simulation_state.get_tls(ego)
            var state = light.tl_state
            if (
                light.at_traffic_light
                and state != GREEN
                and state != OFF
                and Float64(shared.parameters.get_percentage_running_light(ego))
                <= shared.random_device.next()
            ):
                if current != -1:
                    self.remove_actor(ego)
                hazard = True
            elif current != -1:
                if affected == -1 or affected != current:
                    self.remove_actor(ego)
                else:
                    hazard = self.handle_non_signalised_junction(
                        ego, affected, timestamp, shared
                    )
            elif (
                affected != -1
                and not light.at_traffic_light
                and state != GREEN
                and Float64(shared.parameters.get_percentage_running_sign(ego))
                <= shared.random_device.next()
            ):
                self.add_actor_to_non_signalised_junction(ego, affected)
                hazard = True
        shared.tl_frame[index] = hazard

    def add_actor_to_non_signalised_junction(
        mut self, ego: ActorId, junction: Int
    ) raises:
        """Queue a vehicle at a junction, `AddActorToNonSignalisedJunction`.

        A vehicle queued at another junction leaves that queue.

        Args:
            ego: The vehicle.
            junction: The junction's id.

        Raises:
            Error: Never; the lookups are checked.
        """
        if junction not in self.entering_vehicles_map:
            self.entering_vehicles_map[junction] = List[Int]()
        if ego.value not in self.entering_vehicles_map[junction]:
            self.entering_vehicles_map[junction].append(ego.value)
            if ego.value in self.vehicle_last_junction:
                self.remove_actor(ego)
            self.vehicle_last_junction[ego.value] = junction

    def handle_non_signalised_junction(
        mut self,
        ego: ActorId,
        junction: Int,
        timestamp: Timestamp,
        shared: TrafficManagerShared,
    ) raises -> Bool:
        """Hold a queued vehicle until it may enter,
        `HandleNonSignalisedJunction`.

        Args:
            ego: The vehicle.
            junction: Its junction's id.
            timestamp: The world's time now.
            shared: The traffic manager's state.

        Returns:
            True while it must stay stopped.

        Raises:
            Error: If the junction has no queue or the vehicle is not
                tracked.
        """
        var a = ego.value
        if junction not in self.entering_vehicles_map:
            raise Error("The junction has no queue")
        if a not in self.vehicle_stop_time:
            if (
                shared.simulation_state.get_velocity(ego).length()
                < EPSILON_RELATIVE_SPEED.value
            ):
                self.vehicle_stop_time[a] = timestamp.elapsed_seconds
            return True
        if self.entering_vehicles_map[junction][0] == a:
            return timestamp.elapsed_seconds - self.vehicle_stop_time[
                a
            ] < Float64(MINIMUM_STOP_TIME.value)
        return True

    def get_affected_junction_id(
        self, ego: ActorId, shared: TrafficManagerShared
    ) raises -> Int:
        """Return the junction a vehicle deals with, `GetAffectedJunctionId`.

        Args:
            ego: The vehicle.
            shared: The traffic manager's state.

        Returns:
            The junction 5 m along its path, or the one it is in while it
            is queued there, or -1.

        Raises:
            Error: If the vehicle has no path.
        """
        if ego.value not in shared.buffer_map:
            raise Error("A tracked vehicle has no path")
        ref buffer = shared.buffer_map[ego.value]
        var look_ahead = get_target_waypoint(
            buffer, shared.local_map, JUNCTION_LOOK_AHEAD
        )[0]
        var ahead = shared.local_map.at(look_ahead).junction_id.value
        var front = shared.local_map.at(buffer[0]).junction_id.value
        var current = self.vehicle_last_junction.get(ego.value, -1)
        if current == -1 or current == ahead or ahead != -1:
            return ahead
        if current == front:
            return front
        return -1

    def remove_actor(mut self, ego: ActorId) raises:
        """Take a vehicle out of its junction's queue, `RemoveActor`.

        Args:
            ego: The vehicle.

        Raises:
            Error: Never; the lookups are checked.
        """
        var a = ego.value
        var junction = self.vehicle_last_junction.get(a)
        if not Bool(junction):
            return
        _drop(self.entering_vehicles_map[junction.value()], a)
        if a in self.vehicle_stop_time:
            _ = self.vehicle_stop_time.pop(a)
        _ = self.vehicle_last_junction.pop(a)

    def reset(mut self):
        """Empty every queue, `Reset`."""
        self.entering_vehicles_map = Dict[Int, List[Int]]()
        self.vehicle_last_junction = Dict[Int, Int]()
        self.vehicle_stop_time = Dict[Int, Float64]()


# --- MotionPlanStage -------------------------------------------------------------


struct MotionPlanStage(Movable):
    """The motion-planning stage, CARLA's `MotionPlanStage`."""

    var urban_longitudinal_parameters: PIDParameters
    var highway_longitudinal_parameters: PIDParameters
    var urban_lateral_parameters: PIDParameters
    var highway_lateral_parameters: PIDParameters
    # Each vehicle's controller state.
    var pid_state_map: Dict[Int, StateEntry]
    # When each vehicle without physics was first moved, in seconds.
    var teleportation_instance: Dict[Int, Float64]

    def __init__(
        out self,
        urban_longitudinal: PIDParameters = LONGITUDINAL_PARAM,
        highway_longitudinal: PIDParameters = LONGITUDINAL_HIGHWAY_PARAM,
        urban_lateral: PIDParameters = LATERAL_PARAM,
        highway_lateral: PIDParameters = LATERAL_HIGHWAY_PARAM,
    ):
        """Create the stage with PID gains; CARLA's by default.

        Args:
            urban_longitudinal: The speed loop at or below 60 km/h.
            highway_longitudinal: The speed loop above 60 km/h.
            urban_lateral: The heading loop at or below 60 km/h.
            highway_lateral: The heading loop above 60 km/h.
        """
        self.urban_longitudinal_parameters = urban_longitudinal
        self.highway_longitudinal_parameters = highway_longitudinal
        self.urban_lateral_parameters = urban_lateral
        self.highway_lateral_parameters = highway_lateral
        self.pid_state_map = Dict[Int, StateEntry]()
        self.teleportation_instance = Dict[Int, Float64]()

    def update(
        mut self,
        index: Int,
        mut shared: TrafficManagerShared,
        map: Map,
        timestamp: Timestamp,
    ) raises:
        """Plan one vehicle's command, `Update`.

        Args:
            index: The vehicle's place in `shared.vehicle_id_list`.
            shared: The traffic manager's state.
            map: The road map, for the landmarks.
            timestamp: The world's time now.

        Raises:
            Error: If the index is out of range, or the vehicle is not
                tracked or has no path.
        """
        if index < 0 or index >= len(shared.vehicle_id_list):
            raise Error("The vehicle index is out of range")
        var actor = shared.vehicle_id_list[index]
        var a = actor.value
        var state = shared.simulation_state.get_kinematic_state(actor)
        var location = state.location
        var velocity = state.velocity
        var rotation = state.rotation
        var speed = velocity.length()
        var heading = rotation.forward_vector()
        var physics_enabled = state.physics_enabled
        if a not in shared.buffer_map:
            raise Error("A tracked vehicle has no path")
        var buffer = shared.buffer_map[a].copy()
        var localization = shared.localization_frame[index]
        var collision = shared.collision_frame[index]
        var tl_hazard = shared.tl_frame[index]
        var now = timestamp.elapsed_seconds
        var teleport = CarlaTransform(
            Length(location.x), Length(location.y), Length(location.z), rotation
        )
        var hero = shared.track_traffic.get_hero_location()
        var hero_alive = hero != Vector3(0, 0, 0)
        if (
            state.is_dormant
            and shared.parameters.get_respawn_dormant_vehicles()
            and hero_alive
        ):
            if a not in self.teleportation_instance:
                self.teleportation_instance[a] = now
            var lower = (
                shared.parameters.get_lower_boundary_respawn_dormant_vehicles().value
            )
            var upper = (
                shared.parameters.get_upper_boundary_respawn_dormant_vehicles().value
            )
            var dilate = (upper - lower) / Float32(100.0)
            var elapsed = now - self.teleportation_instance[a]
            if (
                shared.parameters.get_synchronous_mode()
                or elapsed > HYBRID_MODE_DT_SECONDS
            ):
                var sample = (
                    Float32(shared.random_device.next()) * dilate + lower
                )
                for w in shared.local_map.get_waypoints_in_delta(
                    hero, ATTEMPTS_TO_TELEPORT, Length(sample)
                ):
                    var grid = shared.local_map.at(w).get_geodesic_grid_id()
                    if shared.track_traffic.is_geo_grid_free(grid):
                        teleport = shared.local_map.at(w).transform
                        teleport.location.z += 0.5
                        shared.track_traffic.add_taken_grid(grid, actor)
                        break
            shared.control_frame[index] = apply_transform(actor, teleport)
            shared.simulation_state.update_kinematic_state(
                actor,
                KinematicState(
                    teleport.location,
                    teleport.rotation,
                    velocity,
                    state.speed_limit,
                    physics_enabled,
                    state.is_dormant,
                    teleport.location,
                ),
            )
            return
        var max_target = shared.parameters.get_vehicle_target_velocity(
            actor, state.speed_limit
        ).value
        var landmark_target = self.get_landmark_target_velocity(
            buffer[0], location, actor, max_target, shared, map
        )
        var turn_target = self.get_turn_target_velocity(
            buffer, max_target, shared
        )
        max_target = min(min(max_target, landmark_target), turn_target)
        var response = self.collision_handling(
            collision, tl_hazard, velocity, heading, max_target, shared
        )
        var collision_emergency_stop = response[0]
        var dynamic_target = response[1]
        var safe_after_junction = self.safe_after_junction(
            localization, tl_hazard, collision_emergency_stop, shared
        )
        var emergency_stop = (
            tl_hazard or collision_emergency_stop or not safe_after_junction
        )
        if physics_enabled and not state.is_dormant:
            var target_point_distance = max(
                speed * TARGET_WAYPOINT_TIME_HORIZON.value,
                MIN_TARGET_WAYPOINT_DISTANCE.value,
            )
            var target = get_target_data(
                buffer,
                shared.local_map,
                Length(target_point_distance),
                location,
            )
            var target_location = target[0]
            ref target_waypoint = shared.local_map.at(buffer[target[1]])
            var base_offset = self.calculate_base_offset(
                actor,
                buffer,
                target_waypoint.check_junction(),
                target[1],
                shared,
            )
            var right_vector = target_waypoint.transform.rotation.right_vector()
            if abs(base_offset) > EPSILON:
                var direction = right_vector
                if not (base_offset > 0.0):
                    direction = right_vector * -1.0
                if self.is_wide_turn_side_occupied(
                    actor, direction, Length(abs(base_offset)), shared
                ):
                    base_offset = 0.0
            var offset = (
                shared.parameters.get_lane_offset(actor).value + base_offset
            )
            target_location = target_location + Vector3(
                offset * right_vector.x, offset * right_vector.y, 0
            )
            var target_vector = target_location - location
            var target_yaw = (
                atan2(target_vector.y, target_vector.x) * Float32(180.0) / PI
            )
            var angular_deviation = target_yaw - rotation.yaw
            if angular_deviation > 180.0:
                angular_deviation -= 360.0
            elif angular_deviation < -180.0:
                angular_deviation += 360.0
            angular_deviation /= 180.0
            var velocity_deviation = (dynamic_target - speed) / dynamic_target
            var stamp = Duration(Float32(now), SECOND)
            if a not in self.pid_state_map:
                self.pid_state_map[a] = StateEntry(stamp, 0, 0, 0)
            var previous = self.pid_state_map[a]
            var longitudinal = self.urban_longitudinal_parameters
            var lateral = self.urban_lateral_parameters
            if speed > HIGHWAY_SPEED.value:
                longitudinal = self.highway_longitudinal_parameters
                lateral = self.highway_lateral_parameters
            var current = StateEntry(
                stamp, angular_deviation, velocity_deviation, 0
            )
            var signal = run_step(current, previous, longitudinal, lateral)
            if emergency_stop:
                signal.throttle = 0.0
                signal.brake = 1.0
            var control = VehicleControl()
            control.throttle = signal.throttle
            control.brake = signal.brake
            control.steer = signal.steer
            shared.control_frame[index] = apply_vehicle_control(actor, control)
            current.steer = signal.steer
            self.pid_state_map[a] = current
        else:
            if a not in self.teleportation_instance:
                self.teleportation_instance[a] = now
            var elapsed = now - self.teleportation_instance[a]
            if not emergency_stop and (
                shared.parameters.get_synchronous_mode()
                or elapsed > HYBRID_MODE_DT_SECONDS
            ):
                var displacement = dynamic_target * HYBRID_MODE_DT.value
                var base = shared.local_map.at(buffer[0]).transform
                var target_heading = base.rotation.forward_vector()
                var correct_heading = make_unit_vector(
                    base.location - location, EPSILON
                )
                var moved = location + correct_heading * displacement
                if (location - base.location).length() < displacement:
                    moved = (
                        location
                        + make_unit_vector(target_heading, EPSILON)
                        * displacement
                    )
                teleport = CarlaTransform(
                    Length(moved.x),
                    Length(moved.y),
                    Length(moved.z),
                    base.rotation,
                )
            shared.control_frame[index] = apply_transform(actor, teleport)
            shared.simulation_state.update_kinematic_hybrid_end_location(
                actor, teleport.location
            )

    def safe_after_junction(
        self,
        localization: LocalizationData,
        tl_hazard: Bool,
        collision_emergency_stop: Bool,
        shared: TrafficManagerShared,
    ) raises -> Bool:
        """Return whether a vehicle has room after a junction,
        `SafeAfterJunction`.

        Args:
            localization: The vehicle's localization.
            tl_hazard: Whether a light or sign stops it.
            collision_emergency_stop: Whether a hazard stops it.
            shared: The traffic manager's state.

        Returns:
            False if a slow vehicle stands within 4 m of the middle of the
            space after the junction, and its path passes the safe point
            but not the junction's end.

        Raises:
            Error: If a node or a vehicle is not known.
        """
        var end = localization.junction_end_point
        var safe = localization.safe_point
        if (
            tl_hazard
            or collision_emergency_stop
            or not localization.is_at_junction_entrance
            or not end.is_some()
            or not safe.is_some()
        ):
            return True
        ref map = shared.local_map
        if not (
            map.at(end).distance_squared(map.at(safe).location())
            > MIN_SAFE_INTERVAL_LENGTH.value * MIN_SAFE_INTERVAL_LENGTH.value
        ):
            return True
        var passing_safe = shared.track_traffic.get_passing_vehicles(
            map.at(safe).id
        )
        var passing_end = shared.track_traffic.get_passing_vehicles(
            map.at(end).id
        )
        var middle = (map.at(end).location() + map.at(safe).location()) / 2.0
        for blocking in passing_safe:
            if blocking in passing_end:
                continue
            var at = shared.simulation_state.get_location(blocking)
            var v = shared.simulation_state.get_velocity(blocking)
            if (
                distance_squared(at, middle)
                < MAX_JUNCTION_BLOCK_DISTANCE.value
                * MAX_JUNCTION_BLOCK_DISTANCE.value
                and v.length_sq()
                < AFTER_JUNCTION_MIN_SPEED.value
                * AFTER_JUNCTION_MIN_SPEED.value
            ):
                return False
        return True

    def calculate_base_offset(
        self,
        actor: ActorId,
        buffer: List[SimpleWaypointIndex],
        is_target_junction: Bool,
        target_index: Int,
        shared: TrafficManagerShared,
    ) raises -> Float32:
        """Return a large vehicle's side offset in a junction,
        `CalculateBaseOffset`.

        Args:
            actor: The vehicle.
            buffer: Its path.
            is_target_junction: Whether its target node is in a junction.
            target_index: The target node's index in the path.
            shared: The traffic manager's state.

        Returns:
            The offset in meters, positive to the right; zero for a
            vehicle that is not large, not turning, not at a junction or
            with wide turns off.

        Raises:
            Error: If a node or the vehicle is not known.
        """
        var found = shared.large_vehicles.get(actor.value)
        if not Bool(found) or not is_target_junction:
            return 0.0
        if not shared.parameters.get_large_vehicle_wide_turn(actor):
            return 0.0
        var large = found.value()
        if large.junction_length.value == 0.0:
            return 0.0
        var missing = Float32(0.0)
        for i in range(target_index, len(buffer)):  # pragma: no branch
            ref current = shared.local_map.at(buffer[i])
            if i > target_index:
                missing += current.distance(
                    shared.local_map.at(buffer[i - 1]).location()
                )
            if not current.check_junction():
                break
        var length = (
            Float32(2.0) * shared.simulation_state.get_dimensions(actor).x
        )
        var max_offset = large_vehicle_offset_magnitude(
            Length(length),
            LARGE_VEHICLES_JUNCTION_REF_LENGTH,
            LARGE_VEHICLES_JUNCTION_OFFSET_GAIN,
            LARGE_VEHICLES_JUNCTION_OFFSET,
        )
        var offset = large_vehicle_junction_offset_profile(
            missing / large.junction_length.value,
            max_offset,
            LARGE_VEHICLES_JUNCTION_POINT,
            LARGE_VEHICLES_JUNCTION_INBOARD_SCALE,
        ).value
        if large.turn_right:
            return offset
        return -offset

    def is_wide_turn_side_occupied(
        self,
        actor: ActorId,
        offset_direction: Vector3,
        offset_magnitude: Length,
        shared: TrafficManagerShared,
    ) raises -> Bool:
        """Return whether a vehicle stands where a wide turn swings,
        `IsWideTurnSideOccupied`.

        Args:
            actor: The turning vehicle.
            offset_direction: The way it would swing.
            offset_magnitude: How far.
            shared: The traffic manager's state.

        Returns:
            Whether another vehicle on its grids is there.

        Raises:
            Error: If a vehicle is not tracked.
        """
        var others = shared.track_traffic.get_overlapping_vehicles(actor)
        if len(others) == 0:
            return False
        var neighbors = List[Neighbor]()
        # An empty list returned above.
        for other in others:  # pragma: no branch
            if other == actor:
                continue
            var d = shared.simulation_state.get_dimensions(other)
            neighbors.append(
                Neighbor(
                    shared.simulation_state.get_location(other),
                    Length(max(d.x, d.y)),
                )
            )
        return is_offset_side_occupied(
            shared.simulation_state.get_location(actor),
            shared.simulation_state.get_heading(actor),
            offset_direction,
            offset_magnitude,
            LARGE_VEHICLES_JUNCTION_CLEARANCE,
            Length(
                shared.simulation_state.get_dimensions(actor).x
                + LARGE_VEHICLES_JUNCTION_SIDE_MARGIN.value
            ),
            neighbors,
        )

    def collision_handling(
        self,
        collision_hazard: CollisionHazardData,
        tl_hazard: Bool,
        vehicle_velocity: Vector3,
        vehicle_heading: Vector3,
        max_target_velocity: Float32,
        shared: TrafficManagerShared,
    ) raises -> Tuple[Bool, Float32]:
        """Return the speed a hazard leaves a vehicle, `CollisionHandling`.

        Args:
            collision_hazard: The vehicle's hazard.
            tl_hazard: Whether a light or sign stops it.
            vehicle_velocity: Its velocity, in m/s.
            vehicle_heading: Where it faces.
            max_target_velocity: Its target speed, in m/s.
            shared: The traffic manager's state.

        Returns:
            Whether it must brake fully, and its target speed in m/s.

        Raises:
            Error: If the hazard's actor is not tracked.
        """
        var emergency = False
        var target = max_target_velocity
        var speed = vehicle_velocity.length()
        if collision_hazard.hazard and not tl_hazard:
            var other_velocity = shared.simulation_state.get_velocity(
                collision_hazard.hazard_actor_id
            )
            var relative_speed = (vehicle_velocity - other_velocity).length()
            var margin = collision_hazard.available_distance_margin.value
            var other_along = other_velocity.dot(vehicle_heading)
            if relative_speed > EPSILON_RELATIVE_SPEED.value:
                var follow = (
                    FOLLOW_LEAD_FACTOR.value * speed
                    + MIN_FOLLOW_LEAD_DISTANCE.value
                )
                if margin > follow:
                    target = other_along
                elif margin > CRITICAL_BRAKING_MARGIN.value:
                    target = max(other_along, RELATIVE_APPROACH_SPEED.value)
                else:
                    emergency = True
            if margin < CRITICAL_BRAKING_MARGIN.value:
                emergency = True
        var gradual = PERC_MAX_SLOWDOWN * speed
        if target < speed - gradual:
            target = speed - gradual
        target = min(max_target_velocity, target)
        return (emergency, target)

    def get_landmark_target_velocity(
        self,
        waypoint: SimpleWaypointIndex,
        vehicle_location: Vector3,
        actor: ActorId,
        max_target_velocity: Float32,
        shared: TrafficManagerShared,
        map: Map,
    ) raises -> Float32:
        """Return the speed the landmarks ahead allow,
        `GetLandmarkTargetVelocity`.

        Within 3.5 s of travel, a light allows 15 km/h, a stop or yield
        sign 10 km/h, and a speed-limit sign its limit as the vehicle's
        speed difference scales it, each rising linearly with distance to
        the target speed at 3.5 s.

        CARLA passes the sign's limit, in m/s, where a limit in km/h
        belongs. So a vehicle with a desired speed compares that speed's
        number in km/h with its target in m/s; the port keeps this.

        Args:
            waypoint: The vehicle's first node.
            vehicle_location: The vehicle, in meters.
            actor: The vehicle.
            max_target_velocity: Its target speed, in m/s.
            shared: The traffic manager's state.
            map: The road map.

        Returns:
            The lowest allowed speed in m/s, or `FLT_MAX` with none.

        Raises:
            Error: If a map query fails.
        """
        var max_distance = LANDMARK_DETECTION_TIME.value * max_target_velocity
        var target = FLOAT_MAX
        for landmark in map.landmarks_in_distance(
            shared.local_map.at(waypoint).waypoint,
            Float64(max_distance),
            False,
        ):
            var at = map.compute_transform(landmark.waypoint.value()).location
            ref signal = map.signal(landmark.reference.signal_id)
            var distance = (at - vehicle_location).length()
            if distance > max_distance:
                continue
            var minimum: Float32
            if signal.type == "1000001":
                minimum = TL_TARGET_VELOCITY.value
            elif signal.type == "206":
                minimum = STOP_TARGET_VELOCITY.value
            elif signal.type == "205":
                minimum = YIELD_TARGET_VELOCITY.value
            elif signal.type == "274":
                var value = Float32(signal.value) / Float32(3.6)
                if shared.parameters.has_desired_speed(actor):
                    value = shared.parameters.get_vehicle_target_velocity(
                        actor, Velocity(value)
                    ).to(KILOMETER_PER_HOUR)
                else:
                    value = shared.parameters.get_vehicle_target_velocity(
                        actor, Velocity(value)
                    ).value
                minimum = (
                    value if value
                    < max_target_velocity else max_target_velocity
                )
            else:
                continue
            var v = max(
                ((max_target_velocity - minimum) / max_distance) * distance
                + minimum,
                minimum,
            )
            target = min(target, v)
        return target

    def get_turn_target_velocity(
        self,
        buffer: List[SimpleWaypointIndex],
        max_target_velocity: Float32,
        shared: TrafficManagerShared,
    ) raises -> Float32:
        """Return the speed the path's curve allows,
        `GetTurnTargetVelocity`.

        Args:
            buffer: The path.
            max_target_velocity: The target speed, in m/s.
            shared: The traffic manager's state.

        Returns:
            The square root of r 0.6 9.81 for the circle of radius r
            through the path's first, middle and last nodes, in m/s; the
            target speed for a path of fewer than three nodes.

        Raises:
            Error: If a node is not on the map.
        """
        if len(buffer) < 3:
            return max_target_velocity
        ref map = shared.local_map
        var radius = three_point_circle_radius(
            map.at(buffer[0]).location(),
            map.at(buffer[len(buffer) // 2]).location(),
            map.at(buffer[len(buffer) - 1]).location(),
        )
        return sqrt(radius.value * FRICTION * GRAVITY.value)

    def remove_actor(mut self, actor: ActorId) raises:
        """Forget a vehicle's controller state, `RemoveActor`.

        Args:
            actor: The vehicle.

        Raises:
            Error: Never; the lookups are checked.
        """
        if actor.value in self.pid_state_map:
            _ = self.pid_state_map.pop(actor.value)
        if actor.value in self.teleportation_instance:
            _ = self.teleportation_instance.pop(actor.value)

    def reset(mut self):
        """Forget every vehicle, `Reset`."""
        self.pid_state_map = Dict[Int, StateEntry]()
        self.teleportation_instance = Dict[Int, Float64]()


# --- VehicleLightStage -------------------------------------------------------------


def _switch(lights: Int, flag: VehicleLightState, on: Bool) -> Int:
    if on:
        return lights | flag.value
    return lights & ~flag.value


struct VehicleLightStage(Movable):
    """The vehicle-light stage, CARLA's `VehicleLightStage`."""

    var all_light_states: List[Tuple[ActorId, VehicleLightState]]
    var weather: WeatherParameters
    var is_weather_enabled: Bool

    def __init__(out self):
        """Create an empty stage."""
        self.all_light_states = List[Tuple[ActorId, VehicleLightState]]()
        self.weather = WeatherParameters()
        self.is_weather_enabled = True

    def update_world_info(
        mut self,
        var light_states: List[Tuple[ActorId, VehicleLightState]],
        weather: WeatherParameters,
        is_weather_enabled: Bool = True,
    ):
        """Read the lights and the weather once a step, `UpdateWorldInfo`.

        Args:
            light_states: Every vehicle's lights.
            weather: The weather.
            is_weather_enabled: Whether the world has weather.
        """
        self.all_light_states = light_states^
        self.is_weather_enabled = is_weather_enabled
        if is_weather_enabled:
            self.weather = weather

    def update(mut self, index: Int, mut shared: TrafficManagerShared) raises:
        """Switch one vehicle's lights, `Update`.

        Args:
            index: The vehicle's place in `shared.vehicle_id_list`.
            shared: The traffic manager's state.

        Raises:
            Error: If the index is out of range or the vehicle has no path.
        """
        if index < 0 or index >= len(shared.vehicle_id_list):
            raise Error("The vehicle index is out of range")
        var actor = shared.vehicle_id_list[index]
        if not shared.parameters.get_update_vehicle_lights(actor):
            return
        var lights = 0xFFFFFFFF
        for entry in self.all_light_states:
            if entry[0] == actor:
                lights = entry[1].value
                break
        if (
            actor.value not in shared.buffer_map
            or len(shared.buffer_map[actor.value]) == 0
        ):
            raise Error("A tracked vehicle has no path")
        ref buffer = shared.buffer_map[actor.value]
        ref map = shared.local_map
        var front = map.at(buffer[0]).location()
        var left = False
        var right = False
        # The path is not empty.
        for index_ in buffer:  # pragma: no branch
            ref w = map.at(index_)
            if w.check_junction():
                if w.road_option == ROAD_OPTION_LEFT:
                    left = True
                elif w.road_option == ROAD_OPTION_RIGHT:
                    right = True
                break
            if (
                distance_squared(front, w.location())
                > MAX_DISTANCE_LIGHT_CHECK.value
            ):
                break
        var brake = False
        for command in shared.control_frame:
            if command.kind == APPLY_VEHICLE_CONTROL and command.actor == actor:
                brake = command.control.brake > 0.5
                break
        var position = False
        var low_beam = False
        var fog = False
        if self.is_weather_enabled:
            var sun = self.weather.sun_altitude_angle.to(DEGREE)
            if sun < SUN_ALTITUDE_DEGREES_BEFORE_DAWN.to(
                DEGREE
            ) or sun > SUN_ALTITUDE_DEGREES_AFTER_SUNSET.to(DEGREE):
                position = True
                low_beam = True
            elif sun < SUN_ALTITUDE_DEGREES_JUST_AFTER_DAWN.to(
                DEGREE
            ) or sun > SUN_ALTITUDE_DEGREES_JUST_BEFORE_SUNSET.to(DEGREE):
                position = True
            if self.weather.precipitation > HEAVY_PRECIPITATION_THRESHOLD:
                position = True
                low_beam = True
            if self.weather.fog_density > FOG_DENSITY_THRESHOLD:
                position = True
                low_beam = True
                fog = True
        var fresh = _switch(lights, LIGHT_BRAKE, brake)
        fresh = _switch(fresh, LIGHT_LEFT_BLINKER, left)
        fresh = _switch(fresh, LIGHT_RIGHT_BLINKER, right)
        fresh = _switch(fresh, LIGHT_POSITION, position)
        fresh = _switch(fresh, LIGHT_LOW_BEAM, low_beam)
        fresh = _switch(fresh, LIGHT_HIGH_BEAM, False)
        fresh = _switch(fresh, LIGHT_FOG, fog)
        if fresh != lights:
            shared.control_frame.append(
                set_vehicle_light_state(actor, VehicleLightState(fresh))
            )
