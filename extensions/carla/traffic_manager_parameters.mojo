# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The traffic manager's settings, CARLA's `Parameters`.

A setting is global, per vehicle, or both. A per-vehicle value wins over
the global one. The defaults are CARLA's:

| Setting | Default |
|---|---|
| Speed difference from the limit | 0 % (30 % in CARLA's Python helper scripts) |
| Distance to the leading vehicle | 2 m |
| Lane offset | 0 m |
| Auto lane change | on |
| Keep right, random left and right lane changes | off (-1 %) |
| Run lights, run signs, ignore vehicles, ignore walkers | 0 % |
| Update vehicle lights | off |
| Synchronous mode | off, with a time out of 10 ms |
| Hybrid physics mode | off, with a radius of 70 m |
| Respawn dormant vehicles | off, from 100 m to 1000 m of the hero |
| Open Street Map mode | on |
| Large-vehicle wide turn | on |

A percentage is a chance from 0 to 100. The setters clamp as CARLA's do:
the speed difference to at most 100 %, the chances to [0, 100], the
distance to the leading vehicle, the desired speed and the hybrid radius
to zero or more.

**Differences from CARLA.** CARLA leaves the limits of the respawn
bounds unset until the first step sets them to 20 m and the episode's
active distance. Here they start at 20 m and 2000 m, CARLA's default
active distance.

The local lifetime contract adds `remove_actor` for permanent destruction
and `clear_actor_settings` for an episode reset. They preserve global
settings. Temporary autopilot unregister must not call either operation.
`configured_actor_ids` reads only settings that remain, including collision
ignore targets; it does not retain a history of destroyed actors. These
cleanup rules do not claim exact CARLA lifetime behavior.

Source: CARLA 1360bb9, `LibCarla/source/carla/trafficmanager/Parameters.cpp`.
"""

from extensions.carla.actor import ActorId
from extensions.carla.physics.quantities import KILOMETER_PER_HOUR
from extensions.carla.traffic_manager_map import RoadOption
from math.vector3 import Vector3
from std.collections import Dict, Set
from units.si import Duration, Length, MILLISECOND, Velocity


@fieldwise_init
struct ChangeLaneInfo(ImplicitlyCopyable, Writable):
    """A forced lane change, CARLA's `ChangeLaneInfo`."""

    var change_lane: Bool
    # True to change to the right, False to the left, as CARLA's traffic
    # manager reads it.
    var direction: Bool


def _clamp_percentage(value: Float32) -> Float32:
    return min(max(value, Float32(0.0)), Float32(100.0))


def _check(actor: ActorId) raises -> Int:
    if not actor.is_valid():
        raise Error("Actor id is not valid")
    return actor.value


struct Parameters(Movable):
    """The traffic manager's settings, CARLA's `Parameters`."""

    var _percentage_difference: Dict[Int, Float32]
    var _lane_offset: Dict[Int, Length]
    var _exact_desired_speed: Dict[Int, Velocity]
    var _global_percentage_difference: Float32
    var _global_lane_offset: Length
    var _large_vehicle_wide_turn: Dict[Int, Bool]
    var _global_large_vehicle_wide_turn: Bool
    var _ignore_collision: Dict[Int, List[Int]]
    var _distance_to_leading_vehicle: Dict[Int, Length]
    var _force_lane_change: Dict[Int, ChangeLaneInfo]
    var _auto_lane_change: Dict[Int, Bool]
    var _perc_run_traffic_light: Dict[Int, Float32]
    var _perc_run_traffic_sign: Dict[Int, Float32]
    var _perc_ignore_walkers: Dict[Int, Float32]
    var _perc_ignore_vehicles: Dict[Int, Float32]
    var _perc_keep_slow_lane: Dict[Int, Float32]
    var _perc_random_left: Dict[Int, Float32]
    var _perc_random_right: Dict[Int, Float32]
    var _auto_update_vehicle_lights: Dict[Int, Bool]
    var _synchronous_mode: Bool
    var _distance_margin: Length
    var _hybrid_physics_mode: Bool
    var _respawn_dormant_vehicles: Bool
    var _respawn_lower_bound: Length
    var _respawn_upper_bound: Length
    var _min_lower_bound: Length
    var _max_upper_bound: Length
    var _hybrid_physics_radius: Length
    var _osm_mode: Bool
    var _upload_path: Dict[Int, Bool]
    var _custom_path: Dict[Int, List[Vector3]]
    var _upload_route: Dict[Int, Bool]
    var _custom_route: Dict[Int, List[RoadOption]]
    var _synchronous_time_out: Duration

    def __init__(out self):
        """Create CARLA's default settings."""
        self._percentage_difference = Dict[Int, Float32]()
        self._lane_offset = Dict[Int, Length]()
        self._exact_desired_speed = Dict[Int, Velocity]()
        self._global_percentage_difference = 0
        self._global_lane_offset = Length(0)
        self._large_vehicle_wide_turn = Dict[Int, Bool]()
        self._global_large_vehicle_wide_turn = True
        self._ignore_collision = Dict[Int, List[Int]]()
        self._distance_to_leading_vehicle = Dict[Int, Length]()
        self._force_lane_change = Dict[Int, ChangeLaneInfo]()
        self._auto_lane_change = Dict[Int, Bool]()
        self._perc_run_traffic_light = Dict[Int, Float32]()
        self._perc_run_traffic_sign = Dict[Int, Float32]()
        self._perc_ignore_walkers = Dict[Int, Float32]()
        self._perc_ignore_vehicles = Dict[Int, Float32]()
        self._perc_keep_slow_lane = Dict[Int, Float32]()
        self._perc_random_left = Dict[Int, Float32]()
        self._perc_random_right = Dict[Int, Float32]()
        self._auto_update_vehicle_lights = Dict[Int, Bool]()
        self._synchronous_mode = False
        self._distance_margin = Length(2.0)
        self._hybrid_physics_mode = False
        self._respawn_dormant_vehicles = False
        self._respawn_lower_bound = Length(100.0)
        self._respawn_upper_bound = Length(1000.0)
        self._min_lower_bound = Length(20.0)
        self._max_upper_bound = Length(2000.0)
        self._hybrid_physics_radius = Length(70.0)
        self._osm_mode = True
        self._upload_path = Dict[Int, Bool]()
        self._custom_path = Dict[Int, List[Vector3]]()
        self._upload_route = Dict[Int, Bool]()
        self._custom_route = Dict[Int, List[RoadOption]]()
        self._synchronous_time_out = Duration(10, MILLISECOND)

    # --- actor lifetime -------------------------------------------------------

    def configured_actor_ids(self) -> List[ActorId]:
        """Return the actors named by per-actor settings.

        Collision-ignore targets are included. The order is not specified.
        The result contains no historical ids after their settings are removed.

        Returns:
            Each configured owner or collision-ignore target once.
        """
        var ids = Set[Int]()
        for entry in self._percentage_difference.items():
            ids.add(entry.key)
        for entry in self._lane_offset.items():
            ids.add(entry.key)
        for entry in self._exact_desired_speed.items():
            ids.add(entry.key)
        for entry in self._large_vehicle_wide_turn.items():
            ids.add(entry.key)
        for entry in self._ignore_collision.items():
            ids.add(entry.key)
        for entry in self._distance_to_leading_vehicle.items():
            ids.add(entry.key)
        for entry in self._force_lane_change.items():
            ids.add(entry.key)
        for entry in self._auto_lane_change.items():
            ids.add(entry.key)
        for entry in self._perc_run_traffic_light.items():
            ids.add(entry.key)
        for entry in self._perc_run_traffic_sign.items():
            ids.add(entry.key)
        for entry in self._perc_ignore_walkers.items():
            ids.add(entry.key)
        for entry in self._perc_ignore_vehicles.items():
            ids.add(entry.key)
        for entry in self._perc_keep_slow_lane.items():
            ids.add(entry.key)
        for entry in self._perc_random_left.items():
            ids.add(entry.key)
        for entry in self._perc_random_right.items():
            ids.add(entry.key)
        for entry in self._auto_update_vehicle_lights.items():
            ids.add(entry.key)
        for entry in self._upload_path.items():
            ids.add(entry.key)
        for entry in self._custom_path.items():
            ids.add(entry.key)
        for entry in self._upload_route.items():
            ids.add(entry.key)
        for entry in self._custom_route.items():
            ids.add(entry.key)
        for entry in self._ignore_collision.items():
            for other in entry.value:
                ids.add(other)
        var out = List[ActorId]()
        for id in ids:
            out.append(ActorId(id))
        return out^

    def remove_actor(mut self, actor: ActorId) raises:
        """Remove a permanently destroyed actor's settings and references.

        Do not call this when a living actor leaves autopilot temporarily.
        Other actors' settings and all global settings stay unchanged.

        Args:
            actor: The destroyed actor. An unknown valid id is ignored.

        Raises:
            Error: If the id is not valid.
        """
        var a = _check(actor)
        if a in self._percentage_difference:
            _ = self._percentage_difference.pop(a)
        if a in self._lane_offset:
            _ = self._lane_offset.pop(a)
        if a in self._exact_desired_speed:
            _ = self._exact_desired_speed.pop(a)
        if a in self._large_vehicle_wide_turn:
            _ = self._large_vehicle_wide_turn.pop(a)
        if a in self._ignore_collision:
            _ = self._ignore_collision.pop(a)
        if a in self._distance_to_leading_vehicle:
            _ = self._distance_to_leading_vehicle.pop(a)
        if a in self._force_lane_change:
            _ = self._force_lane_change.pop(a)
        if a in self._auto_lane_change:
            _ = self._auto_lane_change.pop(a)
        if a in self._perc_run_traffic_light:
            _ = self._perc_run_traffic_light.pop(a)
        if a in self._perc_run_traffic_sign:
            _ = self._perc_run_traffic_sign.pop(a)
        if a in self._perc_ignore_walkers:
            _ = self._perc_ignore_walkers.pop(a)
        if a in self._perc_ignore_vehicles:
            _ = self._perc_ignore_vehicles.pop(a)
        if a in self._perc_keep_slow_lane:
            _ = self._perc_keep_slow_lane.pop(a)
        if a in self._perc_random_left:
            _ = self._perc_random_left.pop(a)
        if a in self._perc_random_right:
            _ = self._perc_random_right.pop(a)
        if a in self._auto_update_vehicle_lights:
            _ = self._auto_update_vehicle_lights.pop(a)
        if a in self._upload_path:
            _ = self._upload_path.pop(a)
        if a in self._custom_path:
            _ = self._custom_path.pop(a)
        if a in self._upload_route:
            _ = self._upload_route.pop(a)
        if a in self._custom_route:
            _ = self._custom_route.pop(a)
        var references = List[Int]()
        for entry in self._ignore_collision.items():
            references.append(entry.key)
        for reference in references:
            if a not in self._ignore_collision[reference]:
                continue
            # The membership check above proves the source is nonempty.
            var kept = List[Int]()
            for other in self._ignore_collision[reference]:  # pragma: no branch
                if other != a:
                    kept.append(other)
            if len(kept) == 0:
                _ = self._ignore_collision.pop(reference)
            else:
                self._ignore_collision[reference] = kept^

    def clear_actor_settings(mut self):
        """Remove every per-actor setting at an episode reset.

        Global settings stay unchanged. Actor ids can name different actors
        in the next episode, so none of their old settings can carry over.
        """
        self._percentage_difference = Dict[Int, Float32]()
        self._lane_offset = Dict[Int, Length]()
        self._exact_desired_speed = Dict[Int, Velocity]()
        self._large_vehicle_wide_turn = Dict[Int, Bool]()
        self._ignore_collision = Dict[Int, List[Int]]()
        self._distance_to_leading_vehicle = Dict[Int, Length]()
        self._force_lane_change = Dict[Int, ChangeLaneInfo]()
        self._auto_lane_change = Dict[Int, Bool]()
        self._perc_run_traffic_light = Dict[Int, Float32]()
        self._perc_run_traffic_sign = Dict[Int, Float32]()
        self._perc_ignore_walkers = Dict[Int, Float32]()
        self._perc_ignore_vehicles = Dict[Int, Float32]()
        self._perc_keep_slow_lane = Dict[Int, Float32]()
        self._perc_random_left = Dict[Int, Float32]()
        self._perc_random_right = Dict[Int, Float32]()
        self._auto_update_vehicle_lights = Dict[Int, Bool]()
        self._upload_path = Dict[Int, Bool]()
        self._custom_path = Dict[Int, List[Vector3]]()
        self._upload_route = Dict[Int, Bool]()
        self._custom_route = Dict[Int, List[RoadOption]]()

    # --- setters --------------------------------------------------------------

    def set_hybrid_physics_mode(mut self, mode_switch: Bool):
        """Turn hybrid physics on or off, `SetHybridPhysicsMode`.

        Args:
            mode_switch: True for on.
        """
        self._hybrid_physics_mode = mode_switch

    def set_respawn_dormant_vehicles(mut self, mode_switch: Bool):
        """Turn the respawn of dormant vehicles on or off,
        `SetRespawnDormantVehicles`.

        Args:
            mode_switch: True for on.
        """
        self._respawn_dormant_vehicles = mode_switch

    def set_max_boundaries(mut self, lower: Length, upper: Length):
        """Set the limits of the respawn bounds, `SetMaxBoundaries`.

        Args:
            lower: The least lower bound.
            upper: The most upper bound.
        """
        self._min_lower_bound = lower
        self._max_upper_bound = upper

    def set_boundaries_respawn_dormant_vehicles(
        mut self, lower_bound: Length, upper_bound: Length
    ):
        """Set how far from the hero a dormant vehicle comes back,
        `SetBoundariesRespawnDormantVehicles`.

        Args:
            lower_bound: The nearest, at least the least lower bound.
            upper_bound: The farthest, at most the most upper bound.
        """
        self._respawn_lower_bound = (
            self._min_lower_bound if self._min_lower_bound
            > lower_bound else lower_bound
        )
        self._respawn_upper_bound = (
            self._max_upper_bound if self._max_upper_bound
            < upper_bound else upper_bound
        )

    def set_percentage_speed_difference(
        mut self, actor: ActorId, percentage: Float32
    ) raises:
        """Set how much slower than the limit a vehicle drives,
        `SetPercentageSpeedDifference`. A negative value is faster. It
        drops the vehicle's desired speed.

        Args:
            actor: The vehicle.
            percentage: The difference, at most 100.

        Raises:
            Error: If the id is not valid.
        """
        var a = _check(actor)
        self._percentage_difference[a] = min(Float32(100.0), percentage)
        if a in self._exact_desired_speed:
            _ = self._exact_desired_speed.pop(a)

    def set_lane_offset(mut self, actor: ActorId, offset: Length) raises:
        """Set how far right of the lane's center a vehicle drives,
        `SetLaneOffset`. A negative offset is to the left.

        Args:
            actor: The vehicle.
            offset: The offset.

        Raises:
            Error: If the id is not valid.
        """
        self._lane_offset[_check(actor)] = offset

    def set_desired_speed(mut self, actor: ActorId, value: Velocity) raises:
        """Set a vehicle's exact speed, `SetDesiredSpeed`. It drops the
        vehicle's speed difference.

        Args:
            actor: The vehicle.
            value: The speed, at least zero.

        Raises:
            Error: If the id is not valid.
        """
        var a = _check(actor)
        self._exact_desired_speed[a] = Velocity(max(Float32(0.0), value.value))
        if a in self._percentage_difference:
            _ = self._percentage_difference.pop(a)

    def set_global_percentage_speed_difference(mut self, percentage: Float32):
        """Set how much slower than the limit every vehicle drives,
        `SetGlobalPercentageSpeedDifference`.

        Args:
            percentage: The difference, at most 100.
        """
        self._global_percentage_difference = min(Float32(100.0), percentage)

    def set_global_lane_offset(mut self, offset: Length):
        """Set every vehicle's lane offset, `SetGlobalLaneOffset`.

        Args:
            offset: The offset; positive is to the right.
        """
        self._global_lane_offset = offset

    def set_large_vehicle_wide_turn(
        mut self, actor: ActorId, enable: Bool
    ) raises:
        """Turn a large vehicle's wide turns on or off,
        `SetLargeVehicleWideTurn`.

        Args:
            actor: The vehicle.
            enable: True for on.

        Raises:
            Error: If the id is not valid.
        """
        self._large_vehicle_wide_turn[_check(actor)] = enable

    def set_global_large_vehicle_wide_turn(mut self, enable: Bool):
        """Turn every large vehicle's wide turns on or off,
        `SetGlobalLargeVehicleWideTurn`.

        Args:
            enable: True for on.
        """
        self._global_large_vehicle_wide_turn = enable

    def set_collision_detection(
        mut self, reference_actor: ActorId, other_actor: ActorId, detect: Bool
    ) raises:
        """Set whether a vehicle avoids another, `SetCollisionDetection`.

        Args:
            reference_actor: The vehicle.
            other_actor: The other actor.
            detect: True to avoid it, False to ignore it.

        Raises:
            Error: If an id is not valid.
        """
        var r = _check(reference_actor)
        var o = _check(other_actor)
        if detect:
            if r in self._ignore_collision:
                ref ignored = self._ignore_collision[r]
                for i in range(len(ignored)):
                    if ignored[i] == o:
                        _ = ignored.pop(i)
                        break
        elif r in self._ignore_collision:
            if o not in self._ignore_collision[r]:
                self._ignore_collision[r].append(o)
        else:
            self._ignore_collision[r] = [o]

    def set_force_lane_change(mut self, actor: ActorId, direction: Bool) raises:
        """Order one lane change, `SetForceLaneChange`.

        Args:
            actor: The vehicle.
            direction: True for right, False for left, as CARLA's traffic
                manager reads it.

        Raises:
            Error: If the id is not valid.
        """
        self._force_lane_change[_check(actor)] = ChangeLaneInfo(True, direction)

    def set_keep_slow_lane_percentage(
        mut self, actor: ActorId, percentage: Float32
    ) raises:
        """Set the chance a vehicle keeps to the slow lane each step,
        `SetKeepSlowLanePercentage`.

        Args:
            actor: The vehicle.
            percentage: The chance.

        Raises:
            Error: If the id is not valid.
        """
        self._perc_keep_slow_lane[_check(actor)] = percentage

    def set_random_left_lane_change_percentage(
        mut self, actor: ActorId, percentage: Float32
    ) raises:
        """Set the chance of a lane change to the left each step,
        `SetRandomLeftLaneChangePercentage`.

        Args:
            actor: The vehicle.
            percentage: The chance.

        Raises:
            Error: If the id is not valid.
        """
        self._perc_random_left[_check(actor)] = percentage

    def set_random_right_lane_change_percentage(
        mut self, actor: ActorId, percentage: Float32
    ) raises:
        """Set the chance of a lane change to the right each step,
        `SetRandomRightLaneChangePercentage`.

        Args:
            actor: The vehicle.
            percentage: The chance.

        Raises:
            Error: If the id is not valid.
        """
        self._perc_random_right[_check(actor)] = percentage

    def set_update_vehicle_lights(
        mut self, actor: ActorId, do_update: Bool
    ) raises:
        """Let the traffic manager switch a vehicle's lights,
        `SetUpdateVehicleLights`.

        Args:
            actor: The vehicle.
            do_update: True to let it.

        Raises:
            Error: If the id is not valid.
        """
        self._auto_update_vehicle_lights[_check(actor)] = do_update

    def set_auto_lane_change(mut self, actor: ActorId, enable: Bool) raises:
        """Let a vehicle change lanes on its own, `SetAutoLaneChange`.

        Args:
            actor: The vehicle.
            enable: True to let it.

        Raises:
            Error: If the id is not valid.
        """
        self._auto_lane_change[_check(actor)] = enable

    def set_distance_to_leading_vehicle(
        mut self, actor: ActorId, distance: Length
    ) raises:
        """Set the gap a vehicle keeps, `SetDistanceToLeadingVehicle`.

        Args:
            actor: The vehicle.
            distance: The gap, at least zero.

        Raises:
            Error: If the id is not valid.
        """
        self._distance_to_leading_vehicle[_check(actor)] = Length(
            max(Float32(0.0), distance.value)
        )

    def set_synchronous_mode(mut self, mode_switch: Bool = True):
        """Turn synchronous mode on or off, `SetSynchronousMode`.

        Args:
            mode_switch: True for on.
        """
        self._synchronous_mode = mode_switch

    def set_synchronous_mode_time_out(mut self, time: Duration):
        """Set how long a synchronous tick may wait,
        `SetSynchronousModeTimeOutInMiliSecond`.

        Args:
            time: The time out.
        """
        self._synchronous_time_out = time

    def set_global_distance_to_leading_vehicle(mut self, distance: Length):
        """Set the gap every vehicle keeps,
        `SetGlobalDistanceToLeadingVehicle`. CARLA does not clamp it.

        Args:
            distance: The gap.
        """
        self._distance_margin = distance

    def set_percentage_running_light(
        mut self, actor: ActorId, percentage: Float32
    ) raises:
        """Set the chance a vehicle runs a red light,
        `SetPercentageRunningLight`.

        Args:
            actor: The vehicle.
            percentage: The chance, clamped to [0, 100].

        Raises:
            Error: If the id is not valid.
        """
        self._perc_run_traffic_light[_check(actor)] = _clamp_percentage(
            percentage
        )

    def set_percentage_running_sign(
        mut self, actor: ActorId, percentage: Float32
    ) raises:
        """Set the chance a vehicle runs a stop sign,
        `SetPercentageRunningSign`.

        Args:
            actor: The vehicle.
            percentage: The chance, clamped to [0, 100].

        Raises:
            Error: If the id is not valid.
        """
        self._perc_run_traffic_sign[_check(actor)] = _clamp_percentage(
            percentage
        )

    def set_percentage_ignore_vehicles(
        mut self, actor: ActorId, percentage: Float32
    ) raises:
        """Set the chance a vehicle ignores another vehicle,
        `SetPercentageIgnoreVehicles`.

        Args:
            actor: The vehicle.
            percentage: The chance, clamped to [0, 100].

        Raises:
            Error: If the id is not valid.
        """
        self._perc_ignore_vehicles[_check(actor)] = _clamp_percentage(
            percentage
        )

    def set_percentage_ignore_walkers(
        mut self, actor: ActorId, percentage: Float32
    ) raises:
        """Set the chance a vehicle ignores a walker,
        `SetPercentageIgnoreWalkers`.

        Args:
            actor: The vehicle.
            percentage: The chance, clamped to [0, 100].

        Raises:
            Error: If the id is not valid.
        """
        self._perc_ignore_walkers[_check(actor)] = _clamp_percentage(percentage)

    def set_hybrid_physics_radius(mut self, radius: Length):
        """Set how near the hero physics runs, `SetHybridPhysicsRadius`.

        Args:
            radius: The radius, at least zero.
        """
        self._hybrid_physics_radius = Length(max(radius.value, Float32(0.0)))

    def set_osm_mode(mut self, mode_switch: Bool):
        """Turn Open Street Map mode on or off, `SetOSMMode`. In it, a
        vehicle that reaches a dead end is destroyed.

        Args:
            mode_switch: True for on.
        """
        self._osm_mode = mode_switch

    def set_custom_path(
        mut self, actor: ActorId, var path: List[Vector3], empty_buffer: Bool
    ) raises:
        """Give a vehicle points to drive through, `SetCustomPath`.

        Args:
            actor: The vehicle.
            path: The points, in meters.
            empty_buffer: True to drop the vehicle's current path first.

        Raises:
            Error: If the id is not valid.
        """
        var a = _check(actor)
        self._custom_path[a] = path^
        self._upload_path[a] = empty_buffer

    def remove_upload_path(mut self, actor: ActorId, remove_path: Bool) raises:
        """Drop a vehicle's path flag or its points, `RemoveUploadPath`.

        Args:
            actor: The vehicle.
            remove_path: True to drop the points, False the flag.

        Raises:
            Error: If the id is not valid.
        """
        var a = _check(actor)
        if not remove_path:
            if a in self._upload_path:
                _ = self._upload_path.pop(a)
        elif a in self._custom_path:
            _ = self._custom_path.pop(a)

    def update_upload_path(
        mut self, actor: ActorId, var path: List[Vector3]
    ) raises:
        """Replace a vehicle's points, `UpdateUploadPath`.

        Args:
            actor: The vehicle.
            path: The points still to drive through.

        Raises:
            Error: If the id is not valid.
        """
        self._custom_path[_check(actor)] = path^

    def set_imported_route(
        mut self,
        actor: ActorId,
        var route: List[RoadOption],
        empty_buffer: Bool,
    ) raises:
        """Give a vehicle turns to take, `SetImportedRoute`.

        Args:
            actor: The vehicle.
            route: The road options, in order.
            empty_buffer: True to drop the vehicle's current path first.

        Raises:
            Error: If the id or a road option is not valid.
        """
        var a = _check(actor)
        for option in route:
            if not option.is_valid():
                raise Error("A route's road option is not valid")
        self._custom_route[a] = route^
        self._upload_route[a] = empty_buffer

    def remove_imported_route(
        mut self, actor: ActorId, remove_path: Bool
    ) raises:
        """Drop a vehicle's route flag or its route, `RemoveImportedRoute`.

        Args:
            actor: The vehicle.
            remove_path: True to drop the route, False the flag.

        Raises:
            Error: If the id is not valid.
        """
        var a = _check(actor)
        if not remove_path:
            if a in self._upload_route:
                _ = self._upload_route.pop(a)
        elif a in self._custom_route:
            _ = self._custom_route.pop(a)

    def update_imported_route(
        mut self, actor: ActorId, var route: List[RoadOption]
    ) raises:
        """Replace a vehicle's route, `UpdateImportedRoute`.

        Args:
            actor: The vehicle.
            route: The road options still to take.

        Raises:
            Error: If the id is not valid.
        """
        self._custom_route[_check(actor)] = route^

    # --- getters --------------------------------------------------------------

    def get_hybrid_physics_radius(self) -> Length:
        """Return how near the hero physics runs, `GetHybridPhysicsRadius`.

        Returns:
            The radius.
        """
        return self._hybrid_physics_radius

    def get_synchronous_mode(self) -> Bool:
        """Return whether synchronous mode is on, `GetSynchronousMode`.

        Returns:
            The flag.
        """
        return self._synchronous_mode

    def get_synchronous_mode_time_out(self) -> Duration:
        """Return the synchronous time out,
        `GetSynchronousModeTimeOutInMiliSecond`.

        Returns:
            The time out.
        """
        return self._synchronous_time_out

    def has_desired_speed(self, actor: ActorId) -> Bool:
        """Return True if a vehicle has an exact desired speed.

        Args:
            actor: The vehicle.

        Returns:
            Whether `set_desired_speed` set one.
        """
        return actor.value in self._exact_desired_speed

    def get_vehicle_target_velocity(
        self, actor: ActorId, speed_limit: Velocity
    ) raises -> Velocity:
        """Return the speed a vehicle aims for, `GetVehicleTargetVelocity`.

        Args:
            actor: The vehicle.
            speed_limit: The limit it obeys.

        Returns:
            Its desired speed if set, else the limit times one minus its
            speed difference (or the global one) over 100.

        Raises:
            Error: Never; the lookups are checked.
        """
        var a = actor.value
        var difference = self._global_percentage_difference
        if a in self._percentage_difference:
            difference = self._percentage_difference[a]
        elif a in self._exact_desired_speed:
            return self._exact_desired_speed[a]
        return Velocity(
            speed_limit.value * (Float32(1.0) - difference / Float32(100.0))
        )

    def get_lane_offset(self, actor: ActorId) -> Length:
        """Return a vehicle's lane offset, `GetLaneOffset`.

        Args:
            actor: The vehicle.

        Returns:
            Its offset, or the global one.
        """
        return self._lane_offset.get(actor.value, self._global_lane_offset)

    def get_large_vehicle_wide_turn(self, actor: ActorId) -> Bool:
        """Return whether a large vehicle turns wide,
        `GetLargeVehicleWideTurn`.

        Args:
            actor: The vehicle.

        Returns:
            Its flag, or the global one.
        """
        return self._large_vehicle_wide_turn.get(
            actor.value, self._global_large_vehicle_wide_turn
        )

    def get_collision_detection(
        self, reference_actor: ActorId, other_actor: ActorId
    ) -> Bool:
        """Return whether a vehicle avoids another,
        `GetCollisionDetection`.

        Args:
            reference_actor: The vehicle.
            other_actor: The other actor.

        Returns:
            False if the vehicle ignores it.
        """
        var found = self._ignore_collision.get(reference_actor.value)
        if Bool(found) and other_actor.value in found.value():
            return False
        return True

    def get_force_lane_change(mut self, actor: ActorId) -> ChangeLaneInfo:
        """Return and clear a vehicle's forced lane change,
        `GetForceLaneChange`.

        Args:
            actor: The vehicle.

        Returns:
            The order, or none.
        """
        return self._force_lane_change.pop(
            actor.value, ChangeLaneInfo(False, False)
        )

    def get_keep_slow_lane_percentage(self, actor: ActorId) -> Float32:
        """Return the chance a vehicle keeps to the slow lane,
        `GetKeepSlowLanePercentage`.

        Args:
            actor: The vehicle.

        Returns:
            The chance, or -1 when unset.
        """
        return self._perc_keep_slow_lane.get(actor.value, Float32(-1.0))

    def get_random_left_lane_change_percentage(self, actor: ActorId) -> Float32:
        """Return the chance of a random left lane change,
        `GetRandomLeftLaneChangePercentage`.

        Args:
            actor: The vehicle.

        Returns:
            The chance, or -1 when unset.
        """
        return self._perc_random_left.get(actor.value, Float32(-1.0))

    def get_random_right_lane_change_percentage(
        self, actor: ActorId
    ) -> Float32:
        """Return the chance of a random right lane change,
        `GetRandomRightLaneChangePercentage`.

        Args:
            actor: The vehicle.

        Returns:
            The chance, or -1 when unset.
        """
        return self._perc_random_right.get(actor.value, Float32(-1.0))

    def get_auto_lane_change(self, actor: ActorId) -> Bool:
        """Return whether a vehicle changes lanes on its own,
        `GetAutoLaneChange`.

        Args:
            actor: The vehicle.

        Returns:
            Its flag; True when unset.
        """
        return self._auto_lane_change.get(actor.value, True)

    def get_distance_to_leading_vehicle(self, actor: ActorId) -> Length:
        """Return the gap a vehicle keeps, `GetDistanceToLeadingVehicle`.

        Args:
            actor: The vehicle.

        Returns:
            Its gap, or the global one.
        """
        return self._distance_to_leading_vehicle.get(
            actor.value, self._distance_margin
        )

    def get_percentage_running_sign(self, actor: ActorId) -> Float32:
        """Return the chance a vehicle runs a sign,
        `GetPercentageRunningSign`.

        Args:
            actor: The vehicle.

        Returns:
            The chance; 0 when unset.
        """
        return self._perc_run_traffic_sign.get(actor.value, Float32(0.0))

    def get_percentage_running_light(self, actor: ActorId) -> Float32:
        """Return the chance a vehicle runs a light,
        `GetPercentageRunningLight`.

        Args:
            actor: The vehicle.

        Returns:
            The chance; 0 when unset.
        """
        return self._perc_run_traffic_light.get(actor.value, Float32(0.0))

    def get_percentage_ignore_vehicles(self, actor: ActorId) -> Float32:
        """Return the chance a vehicle ignores a vehicle,
        `GetPercentageIgnoreVehicles`.

        Args:
            actor: The vehicle.

        Returns:
            The chance; 0 when unset.
        """
        return self._perc_ignore_vehicles.get(actor.value, Float32(0.0))

    def get_percentage_ignore_walkers(self, actor: ActorId) -> Float32:
        """Return the chance a vehicle ignores a walker,
        `GetPercentageIgnoreWalkers`.

        Args:
            actor: The vehicle.

        Returns:
            The chance; 0 when unset.
        """
        return self._perc_ignore_walkers.get(actor.value, Float32(0.0))

    def get_update_vehicle_lights(self, actor: ActorId) -> Bool:
        """Return whether the traffic manager switches a vehicle's lights,
        `GetUpdateVehicleLights`.

        Args:
            actor: The vehicle.

        Returns:
            Its flag; False when unset.
        """
        return self._auto_update_vehicle_lights.get(actor.value, False)

    def get_hybrid_physics_mode(self) -> Bool:
        """Return whether hybrid physics is on, `GetHybridPhysicsMode`.

        Returns:
            The flag.
        """
        return self._hybrid_physics_mode

    def get_respawn_dormant_vehicles(self) -> Bool:
        """Return whether dormant vehicles come back,
        `GetRespawnDormantVehicles`.

        Returns:
            The flag.
        """
        return self._respawn_dormant_vehicles

    def get_lower_boundary_respawn_dormant_vehicles(self) -> Length:
        """Return the nearest a dormant vehicle comes back,
        `GetLowerBoundaryRespawnDormantVehicles`.

        Returns:
            The bound.
        """
        return self._respawn_lower_bound

    def get_upper_boundary_respawn_dormant_vehicles(self) -> Length:
        """Return the farthest a dormant vehicle comes back,
        `GetUpperBoundaryRespawnDormantVehicles`.

        Returns:
            The bound.
        """
        return self._respawn_upper_bound

    def get_osm_mode(self) -> Bool:
        """Return whether Open Street Map mode is on, `GetOSMMode`.

        Returns:
            The flag.
        """
        return self._osm_mode

    def get_upload_path(self, actor: ActorId) -> Bool:
        """Return whether a vehicle's path drops its buffer,
        `GetUploadPath`.

        Args:
            actor: The vehicle.

        Returns:
            The flag; False when unset.
        """
        return self._upload_path.get(actor.value, False)

    def get_custom_path(self, actor: ActorId) -> List[Vector3]:
        """Return a vehicle's points, `GetCustomPath`.

        Args:
            actor: The vehicle.

        Returns:
            The points; none when unset.
        """
        return self._custom_path.get(actor.value, List[Vector3]())

    def get_upload_route(self, actor: ActorId) -> Bool:
        """Return whether a vehicle's route drops its buffer,
        `GetUploadRoute`.

        Args:
            actor: The vehicle.

        Returns:
            The flag; False when unset.
        """
        return self._upload_route.get(actor.value, False)

    def get_imported_route(self, actor: ActorId) -> List[RoadOption]:
        """Return a vehicle's route, `GetImportedRoute`.

        Args:
            actor: The vehicle.

        Returns:
            The road options; none when unset.
        """
        return self._custom_route.get(actor.value, List[RoadOption]())
