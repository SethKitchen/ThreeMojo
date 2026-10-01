# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's behavior agent and constant-velocity agent.

**BehaviorAgent.** A `BehaviorAgent` drives like a `BasicAgent` with one
of three behavior types. Each step does this, in order:

1. It reads its speed and speed limit, and aims at the speed limit. It
   looks one plan item ahead for each 10 km/h of the limit.
2. A red light: emergency stop.
3. A pedestrian within 10 m and in the way: emergency stop when the gap
   between the two boxes is less than the braking distance.
4. A vehicle within 45 m and in the way: emergency stop when the gap is
   less than the braking distance, else car following. The time to
   collision is the gap over the closing speed, at least 1 m/s. Below the
   safety time, the agent drives `speed_decrease` slower than the car
   ahead. Below twice the safety time, it drives at the car's speed, at
   least 5 km/h. The speed stays below `max_speed` and the limit less
   `speed_lim_dist`.
5. With no vehicle ahead, a left or right turn at a junction ahead
   slows the agent to the limit less 5 km/h.
6. Otherwise the agent drives at `max_speed` or the limit less
   `speed_lim_dist`, whichever is lower.

When a faster car follows close behind on a straight lane, the agent
moves to a free lane beside it where the marks allow, and does not try
again for 200 steps. An aggressive agent never does this.

The ranges mix units as CARLA does: the detection range is the larger
of `min_proximity_threshold` in meters and the speed limit in km/h over
2 or 3, read as meters.

**ConstantVelocityAgent.** A `ConstantVelocityAgent` holds its vehicle
at the target speed with the world's constant-velocity mode. It follows
the plan with the local planner, which only steers in effect. A vehicle
in the way sets the held speed to that vehicle's speed along the agent's
heading, and a red light sets it to zero. A collision stops the mode.
After `restart_time` it starts again. In between, the agent drives as a
basic agent, or gives an empty control.

The sources are CARLA's `PythonAPI/carla/agents/navigation/
behavior_agent.py`, `behavior_types.py` and
`constant_velocity_agent.py`, checked against `LibCarla/source/carla/
agents/navigation/BehaviorAgent.cpp` and `ConstantVelocityAgent.cpp`.

**Differences from CARLA.**

- Where the Python reads a lane mark or a waypoint that is not there,
  this port reads no lane change and no lane.
- The constant-velocity agent reads its collisions with a
  `CollisionSensor` at each step. CARLA spawns a sensor actor with a
  callback.
- The agents take the world at each call.
"""

from extensions.carla.actor import ActorId
from extensions.carla.agents import (
    BasicAgent,
    BasicAgentOptions,
    ObstacleDetectionResult,
)
from extensions.carla.agents_local_planner import PlanItem, plan_item
from extensions.carla.agents_misc import (
    BehaviorParameters,
    BehaviorType,
    NORMAL,
    OPTION_CHANGE_LANE_LEFT,
    OPTION_CHANGE_LANE_RIGHT,
    OPTION_LANE_FOLLOW,
    OPTION_LEFT,
    OPTION_RIGHT,
    OPTION_VOID,
    RoadOption,
    behavior_parameters,
    from_kmh,
    kmh,
    positive,
    speed_of,
)
from extensions.carla.collision import CollisionSensor
from extensions.carla.map import Map, Waypoint
from extensions.carla.physics.vehicle_control import VehicleControl
from extensions.carla.road_info import (
    CHANGE_BOTH,
    CHANGE_LEFT,
    CHANGE_NONE,
    CHANGE_RIGHT,
    LANE_DRIVING,
    LaneChange,
)
from extensions.carla.world import World
from math.vector3 import Vector3
from units.si import DEGREE, METER, SECOND, Angle, Duration, Length, Velocity


def _range(parameters: BehaviorParameters, limit: Float64) -> Length:
    # `max(min_proximity_threshold, speed_limit / k)`, meters and km/h.
    return Length(
        Float32(max(Float64(parameters.min_proximity_threshold.value), limit)),
        METER,
    )


def _half_size(world: World, actor: ActorId) raises -> Float64:
    # `max(extent.y, extent.x)` of an actor's box.
    var e = world.get_bounding_box(actor).extent
    return Float64(max(e.y, e.x))


struct BehaviorAgent(Movable):
    """A basic agent with a behavior type, `BehaviorAgent`."""

    var agent: BasicAgent
    var behavior: BehaviorParameters
    var look_ahead_steps: Int
    var speed: Velocity
    var speed_limit: Velocity
    var direction: RoadOption
    var incoming_direction: RoadOption
    var incoming_waypoint: Optional[PlanItem]
    var min_speed: Velocity

    def __init__(
        out self,
        world: World,
        vehicle: ActorId,
        behavior: BehaviorType = NORMAL,
        options: BasicAgentOptions = BasicAgentOptions(),
        seed: Int = 0,
    ) raises:
        """Create an agent, `BehaviorAgent.__init__`.

        The basic agent starts at 20 km/h. The lane-change paths then use
        a 4.5 m resolution, as CARLA sets it after the route planner is
        built.

        Args:
            world: The world.
            vehicle: The vehicle to drive.
            behavior: `CAUTIOUS`, `NORMAL` or `AGGRESSIVE`.
            options: The basic agent's settings.
            seed: The seed of the local planner's random choice.

        Raises:
            Error: If the behavior type is not valid, or the basic agent
                cannot be made.
        """
        self.behavior = behavior_parameters(behavior)
        self.agent = BasicAgent(world, vehicle, from_kmh(20), options, seed)
        self.agent.sampling_resolution = Length(4.5, METER)
        self.look_ahead_steps = 0
        self.speed = Velocity(0)
        self.speed_limit = Velocity(0)
        self.direction = OPTION_LANE_FOLLOW
        self.incoming_direction = OPTION_LANE_FOLLOW
        self.incoming_waypoint = None
        self.min_speed = from_kmh(5)

    def update_information(mut self, world: World) raises:
        """Read the vehicle's state, `_update_information`.

        Args:
            world: The world.

        Raises:
            Error: If the vehicle is gone.
        """
        var vehicle = self.agent.vehicle
        self.speed = speed_of(world.get_velocity(vehicle))
        self.speed_limit = world.get_speed_limit(vehicle)
        self.agent.local_planner.set_speed(self.speed_limit)
        self.direction = self.agent.local_planner.target.road_option
        self.look_ahead_steps = Int(kmh(self.speed_limit) / 10.0)
        self.incoming_waypoint = (
            self.agent.local_planner.get_incoming_waypoint_and_direction(
                self.look_ahead_steps
            )
        )
        self.incoming_direction = OPTION_VOID
        if Bool(self.incoming_waypoint):
            self.incoming_direction = self.incoming_waypoint.value().road_option

    def traffic_light_manager(mut self, world: World) raises -> Bool:
        """Check for a red light, `traffic_light_manager`.

        Args:
            world: The world.

        Returns:
            Whether a red light holds the vehicle, within the basic
            agent's base threshold.

        Raises:
            Error: If a map query fails.
        """
        return self.agent.affected_by_traffic_light(
            world, world.filter_actors("*traffic_light*")
        ).traffic_light_was_found

    def _tailgating(
        mut self, world: World, waypoint: Waypoint, vehicles: List[ActorId]
    ) raises:
        var left_turn = CHANGE_NONE
        var right_turn = CHANGE_NONE
        var left_mark = world.map.left_lane_marking(waypoint)
        if Bool(left_mark):
            left_turn = left_mark.value().lane_change
        var right_mark = world.map.right_lane_marking(waypoint)
        if Bool(right_mark):
            right_turn = right_mark.value().lane_change
        var left_wpt = world.map.left(waypoint)
        var right_wpt = world.map.right(waypoint)
        var reach = _range(self.behavior, kmh(self.speed_limit) / 2.0)
        var behind = self.agent.vehicle_obstacle_detected(
            world,
            vehicles.copy(),
            reach,
            Angle(180, DEGREE),
            Angle(160, DEGREE),
        )
        if not behind.obstacle_was_found:
            return
        if not (
            kmh(self.speed)
            < kmh(speed_of(world.get_velocity(behind.obstacle.value())))
        ):
            return
        var side = Optional[Waypoint](None)
        var offset = 0
        if (
            right_turn == CHANGE_RIGHT or right_turn == CHANGE_BOTH
        ) and _beside(world.map, waypoint, right_wpt):
            side = right_wpt
            offset = 1
        elif left_turn == CHANGE_LEFT and _beside(
            world.map, waypoint, left_wpt
        ):
            side = left_wpt
            offset = -1
        if not Bool(side):
            return
        var free = self.agent.vehicle_obstacle_detected(
            world,
            vehicles.copy(),
            reach,
            Angle(180, DEGREE),
            Angle(0, DEGREE),
            offset,
        )
        if free.obstacle_was_found:
            return
        var end = self.agent.local_planner.target.transform.location
        self.behavior.tailgate_counter = 200
        self.agent.set_destination(
            world, end, world.map.compute_transform(side.value()).location
        )

    def collision_and_car_avoid_manager(
        mut self, world: World, waypoint: Waypoint
    ) raises -> ObstacleDetectionResult:
        """Look for a vehicle in the way, `collision_and_car_avoid_manager`.

        While following its lane off a junction above 10 km/h, with no
        vehicle ahead, the agent also checks for a tailgater.

        Args:
            world: The world.
            waypoint: The vehicle's waypoint.

        Returns:
            The vehicle found, if any.

        Raises:
            Error: If a map query fails.
        """
        var vehicles = self._near(world, "*vehicle*", waypoint, 45.0)
        var limit = kmh(self.speed_limit)
        var found: ObstacleDetectionResult
        if self.direction == OPTION_CHANGE_LANE_LEFT:
            found = self.agent.vehicle_obstacle_detected(
                world,
                vehicles.copy(),
                _range(self.behavior, limit / 2.0),
                Angle(180, DEGREE),
                Angle(0, DEGREE),
                -1,
            )
        elif self.direction == OPTION_CHANGE_LANE_RIGHT:
            found = self.agent.vehicle_obstacle_detected(
                world,
                vehicles.copy(),
                _range(self.behavior, limit / 2.0),
                Angle(180, DEGREE),
                Angle(0, DEGREE),
                1,
            )
        else:
            found = self.agent.vehicle_obstacle_detected(
                world,
                vehicles.copy(),
                _range(self.behavior, limit / 3.0),
                Angle(30, DEGREE),
            )
            if (
                not found.obstacle_was_found
                and self.direction == OPTION_LANE_FOLLOW
                and not world.map.is_junction(waypoint.road_id)
                and kmh(self.speed) > 10.0
                and self.behavior.tailgate_counter == 0
            ):
                self._tailgating(world, waypoint, vehicles)
        return found

    def _near(
        self, world: World, pattern: String, waypoint: Waypoint, reach: Float64
    ) raises -> List[ActorId]:
        var at = world.map.compute_transform(waypoint).location
        var out = List[ActorId]()
        for a in world.filter_actors(pattern):
            if (
                Float64(world.get_location(a).distance_to(at)) < reach
                and a != self.agent.vehicle
            ):
                out.append(a)
        return out^

    def pedestrian_avoid_manager(
        mut self, world: World, waypoint: Waypoint
    ) raises -> ObstacleDetectionResult:
        """Look for a pedestrian in the way, `pedestrian_avoid_manager`.

        Args:
            world: The world.
            waypoint: The vehicle's waypoint.

        Returns:
            The walker found, if any.

        Raises:
            Error: If a map query fails.
        """
        var walkers = self._near(world, "*walker.pedestrian*", waypoint, 10.0)
        var limit = kmh(self.speed_limit)
        var offset = 0
        if self.direction == OPTION_CHANGE_LANE_LEFT:
            offset = -1
        elif self.direction == OPTION_CHANGE_LANE_RIGHT:
            offset = 1
        if offset != 0:
            return self.agent.vehicle_obstacle_detected(
                world,
                walkers.copy(),
                _range(self.behavior, limit / 2.0),
                Angle(90, DEGREE),
                Angle(0, DEGREE),
                offset,
            )
        return self.agent.vehicle_obstacle_detected(
            world,
            walkers.copy(),
            _range(self.behavior, limit / 3.0),
            Angle(60, DEGREE),
        )

    def car_following_manager(
        mut self, world: World, vehicle: ActorId, distance: Length
    ) raises -> VehicleControl:
        """Follow a car ahead, `car_following_manager`.

        Args:
            world: The world.
            vehicle: The car ahead.
            distance: The gap to it.

        Returns:
            The local planner's control at the chosen speed.

        Raises:
            Error: If the car is gone.
        """
        var vehicle_speed = kmh(speed_of(world.get_velocity(vehicle)))
        var delta_v = max(1.0, (kmh(self.speed) - vehicle_speed) / 3.6)
        var ttc = Float64(distance.value) / delta_v
        var safety = Float64(self.behavior.safety_time.value)
        var cap = min(
            kmh(self.behavior.max_speed),
            kmh(self.speed_limit) - kmh(self.behavior.speed_lim_dist),
        )
        var target = cap
        if safety > ttc and ttc > 0.0:
            target = min(
                kmh(
                    positive(
                        from_kmh(
                            vehicle_speed - kmh(self.behavior.speed_decrease)
                        )
                    )
                ),
                cap,
            )
        elif 2.0 * safety > ttc and ttc >= safety:
            target = min(max(kmh(self.min_speed), vehicle_speed), cap)
        self.agent.local_planner.set_speed(from_kmh(target))
        return self.agent.local_planner.run_step(world)

    def run_step(mut self, world: World) raises -> VehicleControl:
        """Plan and control one step, `run_step`.

        Args:
            world: The world.

        Returns:
            The control.

        Raises:
            Error: If the vehicle is gone, or a map query fails.
        """
        self.update_information(world)
        if self.behavior.tailgate_counter > 0:
            self.behavior.tailgate_counter -= 1
        var vehicle = self.agent.vehicle
        var ego_wp = world.map.closest_waypoint_on_road(
            world.get_location(vehicle)
        ).value()
        if self.traffic_light_manager(world):
            return self.emergency_stop()
        var braking = Float64(self.behavior.braking_distance.value)
        var ego_size = _half_size(world, vehicle)
        var walker = self.pedestrian_avoid_manager(world, ego_wp)
        if walker.obstacle_was_found:
            var gap = (
                Float64(walker.distance.value)
                - _half_size(world, walker.obstacle.value())
                - ego_size
            )
            if gap < braking:
                return self.emergency_stop()
        var car = self.collision_and_car_avoid_manager(world, ego_wp)
        if car.obstacle_was_found:
            var gap = (
                Float64(car.distance.value)
                - _half_size(world, car.obstacle.value())
                - ego_size
            )
            if gap < braking:
                return self.emergency_stop()
            return self.car_following_manager(
                world, car.obstacle.value(), Length(Float32(gap), METER)
            )
        var limit = kmh(self.speed_limit)
        var target = min(
            kmh(self.behavior.max_speed),
            limit - kmh(self.behavior.speed_lim_dist),
        )
        if (
            Bool(self.incoming_waypoint)
            and world.map.is_junction(
                self.incoming_waypoint.value().waypoint.road_id
            )
            and (
                self.incoming_direction == OPTION_LEFT
                or self.incoming_direction == OPTION_RIGHT
            )
        ):
            target = min(kmh(self.behavior.max_speed), limit - 5.0)
        self.agent.local_planner.set_speed(from_kmh(target))
        return self.agent.local_planner.run_step(world)

    def emergency_stop(self) -> VehicleControl:
        """Return an emergency stop, `emergency_stop`.

        Returns:
            A new control with no steering, no throttle and the basic
            agent's `max_brake`.
        """
        var control = VehicleControl()
        control.brake = Float32(self.agent.max_brake)
        return control


def _beside(
    map: Map, waypoint: Waypoint, side: Optional[Waypoint]
) raises -> Bool:
    # A lane beside, facing the same way, that is a driving lane.
    if not Bool(side):
        return False
    var s = side.value()
    return (
        waypoint.lane_id.value * s.lane_id.value > 0
        and map.lane_type(s) == LANE_DRIVING
    )


struct ConstantVelocityAgent(Movable):
    """An agent held at a constant speed, `ConstantVelocityAgent`."""

    var agent: BasicAgent
    var use_basic_behavior: Bool
    var target_speed: Velocity
    var current_speed: Velocity
    # The world time at which a collision stopped the constant speed.
    var constant_velocity_stop_time: Optional[Duration]
    var restart_time: Duration
    var is_constant_velocity_active: Bool
    var collision_sensor: CollisionSensor

    def __init__(
        out self,
        mut world: World,
        vehicle: ActorId,
        target_speed: Velocity = from_kmh(20),
        options: BasicAgentOptions = BasicAgentOptions(),
        restart_time: Duration = Duration(Float32.MAX, SECOND),
        use_basic_behavior: Bool = False,
        seed: Int = 0,
    ) raises:
        """Create an agent and hold its vehicle at the target speed,
        `ConstantVelocityAgent.__init__`.

        Args:
            world: The world.
            vehicle: The vehicle to drive.
            target_speed: The speed to hold.
            options: The basic agent's settings.
            restart_time: How long after a collision to start again;
                CARLA's default is never.
            use_basic_behavior: Whether to drive as a basic agent while
                stopped.
            seed: The seed of the local planner's random choice.

        Raises:
            Error: If the basic agent cannot be made.
        """
        self.agent = BasicAgent(world, vehicle, target_speed, options, seed)
        self.use_basic_behavior = use_basic_behavior
        self.target_speed = target_speed
        self.current_speed = speed_of(world.get_velocity(vehicle))
        self.constant_velocity_stop_time = None
        self.restart_time = restart_time
        self.is_constant_velocity_active = True
        self.collision_sensor = CollisionSensor()
        self._set_constant_velocity(world, target_speed)

    def set_target_speed(mut self, speed: Velocity):
        """Change the speed to hold, `set_target_speed`.

        Args:
            speed: The new speed.
        """
        self.target_speed = speed
        self.agent.local_planner.set_speed(speed)

    def stop_constant_velocity(mut self, mut world: World) raises:
        """Stop holding the speed, `stop_constant_velocity`.

        Args:
            world: The world.

        Raises:
            Error: If the vehicle is gone.
        """
        self.is_constant_velocity_active = False
        world.disable_constant_velocity(self.agent.vehicle)
        self.constant_velocity_stop_time = Duration(
            Float32(world.elapsed_seconds), SECOND
        )

    def restart_constant_velocity(mut self, mut world: World) raises:
        """Hold the speed again, `restart_constant_velocity`.

        Args:
            world: The world.

        Raises:
            Error: If the vehicle is gone.
        """
        self.is_constant_velocity_active = True
        self._set_constant_velocity(world, self.target_speed)

    def _set_constant_velocity(self, mut world: World, speed: Velocity) raises:
        world.enable_constant_velocity(
            self.agent.vehicle, Vector3(speed.value, 0, 0)
        )

    def run_step(mut self, mut world: World) raises -> VehicleControl:
        """Plan and control one step, `run_step`.

        Args:
            world: The world.

        Returns:
            The control.

        Raises:
            Error: If the vehicle is gone, or a map query fails.
        """
        var vehicle = self.agent.vehicle
        if len(self.collision_sensor.collect(world, vehicle)) > 0:
            self.stop_constant_velocity(world)
        if not self.is_constant_velocity_active:
            var stopped = self.constant_velocity_stop_time.value().value
            if Float64(world.elapsed_seconds) - Float64(stopped) > Float64(
                self.restart_time.value
            ):
                self.restart_constant_velocity(world)
            elif self.use_basic_behavior:
                return self.agent.run_step(world)
            else:
                return VehicleControl()
        var velocity = world.get_velocity(vehicle)
        var speed = Float64(speed_of(velocity).value)
        var hazard_speed = 0.0
        var hazard = False
        var found = self.agent.vehicle_obstacle_detected(
            world,
            world.filter_actors("*vehicle*"),
            Length(
                Float32(
                    Float64(self.agent.base_vehicle_threshold.value) + speed
                ),
                METER,
            ),
        )
        if found.obstacle_was_found:
            if speed != 0.0:
                var other = world.get_velocity(found.obstacle.value())
                hazard_speed = Float64(velocity.dot(other)) / speed
            hazard = True
        if self.agent.affected_by_traffic_light(
            world,
            world.filter_actors("*traffic_light*"),
            Length(
                Float32(
                    Float64(self.agent.base_tlight_threshold.value)
                    + 0.3 * speed
                ),
                METER,
            ),
        ).traffic_light_was_found:
            hazard_speed = 0.0
            hazard = True
        var control = self.agent.local_planner.run_step(world)
        if hazard:
            self._set_constant_velocity(world, Velocity(Float32(hazard_speed)))
        else:
            self._set_constant_velocity(world, self.target_speed)
        return control
