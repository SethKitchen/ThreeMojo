# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's basic agent: drive a route and stop for red lights and cars.

A `BasicAgent` drives one vehicle of a `World`. It plans with a
`GlobalRoutePlanner`, follows the plan with a `LocalPlanner`, and brakes
hard for two hazards:

- A vehicle ahead. The agent looks `base_vehicle_threshold` plus
  `detection_speed_ratio` times its speed ahead. Off a junction, a
  vehicle on the agent's lane, or on the lane of the plan three steps
  ahead, counts when its rear is within that distance of the agent's
  front and within 90 degrees of the agent's heading. In a junction, with
  `use_bbs_detection`, or when an offset puts the agent across the lane
  line, the agent checks the vehicle's box against the polygon its route
  sweeps.
- A red light. A light counts when its trigger waypoint is on the
  agent's road, faces the agent's way, and is within the same kind of
  distance, ahead of the agent. The agent keeps a light until it is no
  longer red.

The emergency stop keeps the steering and brakes with `max_brake`.

The source is CARLA's `PythonAPI/carla/agents/navigation/basic_agent.py`
and `agents/tools/hints.py`, checked against `LibCarla/source/carla/
agents/navigation/BasicAgent.cpp`. Where the Python fails on a missing
waypoint or lets two transforms share one location object, this port
follows the C++: the ego location stays at the vehicle's center.

**The route polygon.** CARLA builds the route polygon from the right and
left points of the vehicle, then of each plan waypoint, in that order,
and the target's polygon from its box's eight corners in CARLA's order.
Both rings cross themselves. The geometry libraries CARLA uses test them
as they are. This port does the same: two polygons meet when an edge of
one crosses an edge of the other, or a corner of one is inside the other
by the even-odd rule.

**Differences from CARLA.** The agent takes the world at each call. A
lane change takes `OPTION_CHANGE_LANE_LEFT` or `OPTION_CHANGE_LANE_RIGHT`
where CARLA takes the strings "left" and "right".
"""

from extensions.carla.actor import ActorId, RED
from extensions.carla.agents_local_planner import (
    LocalPlanner,
    LocalPlannerOptions,
    PlanItem,
    plan_item,
)
from extensions.carla.agents_misc import (
    OPTION_CHANGE_LANE_LEFT,
    OPTION_CHANGE_LANE_RIGHT,
    OPTION_LANE_FOLLOW,
    RoadOption,
    compute_distance,
    from_kmh,
    get_trafficlight_trigger_location,
    is_within_distance,
    speed_of,
)
from extensions.carla.agents_route import GlobalRoutePlanner
from extensions.carla.map import Map, Waypoint
from extensions.carla.physics.vehicle_control import VehicleControl
from extensions.carla.road_info import (
    CHANGE_BOTH,
    CHANGE_LEFT,
    CHANGE_RIGHT,
    LANE_ANY,
    LANE_DRIVING,
)
from extensions.carla.transform import CarlaTransform
from extensions.carla.world import World
from math.vector3 import Vector3
from units.si import DEGREE, METER, SECOND, Angle, Duration, Length, Velocity


# --- detection results, hints.py -------------------------------------------------


@fieldwise_init
struct ObstacleDetectionResult(ImplicitlyCopyable):
    """What an obstacle check found, `ObstacleDetectionResult`."""

    var obstacle_was_found: Bool
    var obstacle: Optional[ActorId]
    # The distance between the centers; -1 m when nothing was found.
    var distance: Length


def _no_obstacle() -> ObstacleDetectionResult:
    return ObstacleDetectionResult(False, None, Length(-1, METER))


@fieldwise_init
struct TrafficLightDetectionResult(ImplicitlyCopyable):
    """What a light check found, `TrafficLightDetectionResult`."""

    var traffic_light_was_found: Bool
    var traffic_light: Optional[ActorId]


# --- polygons ----------------------------------------------------------------------


def _segments_cross(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> Bool:
    # Whether segment a-b meets segment c-d in the x-y plane, ends included.
    var d1 = _orient(c, d, a)
    var d2 = _orient(c, d, b)
    var d3 = _orient(a, b, c)
    var d4 = _orient(a, b, d)
    if d1 * d2 < 0.0 and d3 * d4 < 0.0:
        return True
    return (
        (d1 == 0.0 and _on_segment(c, d, a))
        or (d2 == 0.0 and _on_segment(c, d, b))
        or (d3 == 0.0 and _on_segment(a, b, c))
        or (d4 == 0.0 and _on_segment(a, b, d))
    )


def _orient(a: Vector3, b: Vector3, c: Vector3) -> Float64:
    return (Float64(b.x) - Float64(a.x)) * (Float64(c.y) - Float64(a.y)) - (
        Float64(b.y) - Float64(a.y)
    ) * (Float64(c.x) - Float64(a.x))


def _on_segment(a: Vector3, b: Vector3, p: Vector3) -> Bool:
    return (
        min(a.x, b.x) <= p.x
        and p.x <= max(a.x, b.x)
        and min(a.y, b.y) <= p.y
        and p.y <= max(a.y, b.y)
    )


def point_in_polygon(point: Vector3, ring: List[Vector3]) -> Bool:
    """Return whether a point is inside a ring by the even-odd rule.

    The test is in the x-y plane. The ring closes from its last point to
    its first.

    Args:
        point: The point.
        ring: The ring's points.

    Returns:
        Whether a ray from the point crosses the ring an odd number of
        times.
    """
    var inside = False
    var n = len(ring)
    for i in range(n):
        var a = ring[i]
        var b = ring[(i + n - 1) % n]
        if (a.y > point.y) != (b.y > point.y):
            var x = Float64(a.x) + (Float64(point.y) - Float64(a.y)) * (
                Float64(b.x) - Float64(a.x)
            ) / (Float64(b.y) - Float64(a.y))
            if Float64(point.x) < x:
                inside = not inside
    return inside


def polygons_intersect(a: List[Vector3], b: List[Vector3]) -> Bool:
    """Return whether two rings meet in the x-y plane.

    Two rings meet when an edge of one meets an edge of the other, or a
    point of one is inside the other by the even-odd rule. A ring may
    cross itself.

    Args:
        a: The first ring.
        b: The second ring.

    Returns:
        Whether they meet. An empty ring meets nothing.
    """
    if len(a) == 0 or len(b) == 0:
        return False
    # Both rings have a point at least, checked above.
    for i in range(len(a)):  # pragma: no branch
        for j in range(len(b)):  # pragma: no branch
            if _segments_cross(
                a[i], a[(i + 1) % len(a)], b[j], b[(j + 1) % len(b)]
            ):
                return True
    return point_in_polygon(a[0], b) or point_in_polygon(b[0], a)


# --- options -------------------------------------------------------------------------


@fieldwise_init
struct BasicAgentOptions(ImplicitlyCopyable):
    """The agent's settings, CARLA's `opt_dict` of the basic agent."""

    # The local planner's settings. The agent sets their target speed
    # and offset.
    var local: LocalPlannerOptions
    var ignore_traffic_lights: Bool
    var ignore_stop_signs: Bool
    var ignore_vehicles: Bool
    var use_bbs_detection: Bool
    var sampling_resolution: Length
    var base_tlight_threshold: Length
    var base_vehicle_threshold: Length
    # Seconds of travel added to the detection distances.
    var detection_speed_ratio: Duration
    # The brake of an emergency stop.
    var max_brake: Float64
    var offset: Length

    def __init__(out self):
        """Create CARLA's defaults: nothing ignored, a 2 m resolution,
        thresholds of 5 m plus 1 s of travel, and a 0.6 emergency brake.
        """
        self.local = LocalPlannerOptions()
        self.ignore_traffic_lights = False
        self.ignore_stop_signs = False
        self.ignore_vehicles = False
        self.use_bbs_detection = False
        self.sampling_resolution = Length(2, METER)
        self.base_tlight_threshold = Length(5, METER)
        self.base_vehicle_threshold = Length(5, METER)
        self.detection_speed_ratio = Duration(1, SECOND)
        self.max_brake = 0.6
        self.offset = Length(0, METER)


def _with_offset(
    target_speed: Velocity, options: BasicAgentOptions
) -> LocalPlannerOptions:
    var local = options.local
    local.target_speed = target_speed
    local.offset = options.offset
    return local


# --- the agent -----------------------------------------------------------------------


struct BasicAgent(Movable):
    """A vehicle that follows a route and stops for hazards,
    `BasicAgent`."""

    var vehicle: ActorId
    var local_planner: LocalPlanner
    var global_planner: GlobalRoutePlanner
    var target_speed: Velocity
    var ignore_lights: Bool
    var ignore_signs: Bool
    var ignore_others: Bool
    var use_bbs_detection: Bool
    var sampling_resolution: Length
    var base_tlight_threshold: Length
    var base_vehicle_threshold: Length
    var speed_ratio: Duration
    var max_brake: Float64
    var offset: Length
    var last_traffic_light: Optional[ActorId]
    var lights_list: List[ActorId]
    # The trigger waypoint of each light seen, by actor id.
    var lights_map: Dict[Int, PlanItem]

    def __init__(
        out self,
        world: World,
        vehicle: ActorId,
        target_speed: Velocity = from_kmh(20),
        options: BasicAgentOptions = BasicAgentOptions(),
        seed: Int = 0,
    ) raises:
        """Create an agent and its planners, `BasicAgent.__init__`.

        Args:
            world: The world.
            vehicle: The vehicle to drive.
            target_speed: The cruise speed.
            options: The settings.
            seed: The seed of the local planner's random choice.

        Raises:
            Error: If the actor is not a vehicle, it is not near a
                driving lane, or the resolution is not more than zero.
        """
        self = BasicAgent(
            world,
            vehicle,
            GlobalRoutePlanner(world.map, options.sampling_resolution),
            target_speed,
            options,
            seed,
        )

    def __init__(
        out self,
        world: World,
        vehicle: ActorId,
        var planner: GlobalRoutePlanner,
        target_speed: Velocity = from_kmh(20),
        options: BasicAgentOptions = BasicAgentOptions(),
        seed: Int = 0,
    ) raises:
        """Create an agent with a route planner already built, as CARLA's
        `grp_inst`.

        Args:
            world: The world.
            vehicle: The vehicle to drive.
            planner: The route planner.
            target_speed: The cruise speed.
            options: The settings.
            seed: The seed of the local planner's random choice.

        Raises:
            Error: If the actor is not a vehicle, or it is not near a
                driving lane.
        """
        self.vehicle = vehicle
        self.local_planner = LocalPlanner(
            world, vehicle, _with_offset(target_speed, options), seed
        )
        self.global_planner = planner^
        self.target_speed = target_speed
        self.ignore_lights = options.ignore_traffic_lights
        self.ignore_signs = options.ignore_stop_signs
        self.ignore_others = options.ignore_vehicles
        self.use_bbs_detection = options.use_bbs_detection
        self.sampling_resolution = options.sampling_resolution
        self.base_tlight_threshold = options.base_tlight_threshold
        self.base_vehicle_threshold = options.base_vehicle_threshold
        self.speed_ratio = options.detection_speed_ratio
        self.max_brake = options.max_brake
        self.offset = options.offset
        self.last_traffic_light = None
        self.lights_list = world.filter_actors("*traffic_light*")
        self.lights_map = Dict[Int, PlanItem]()

    def add_emergency_stop(self, control: VehicleControl) -> VehicleControl:
        """Turn a control into an emergency stop, `add_emergency_stop`.

        Args:
            control: The control.

        Returns:
            The same steering, no throttle, and `max_brake`.
        """
        var out = control
        out.throttle = 0.0
        out.brake = Float32(self.max_brake)
        out.hand_brake = False
        return out

    def set_target_speed(mut self, speed: Velocity):
        """Change the cruise speed, `set_target_speed`.

        Args:
            speed: The new speed.
        """
        self.target_speed = speed
        self.local_planner.set_speed(speed)

    def follow_speed_limits(mut self, value: Bool = True):
        """Drive at the speed limit, `follow_speed_limits`.

        Args:
            value: Whether to.
        """
        self.local_planner.follow_speed_limits(value)

    def set_destination(
        mut self,
        world: World,
        end_location: Vector3,
        start_location: Optional[Vector3] = None,
        clean_queue: Bool = True,
    ) raises:
        """Plan a route and follow it, `set_destination`.

        Without a start, a cleaned plan starts at the local planner's
        target waypoint, and an appended plan at the plan's last waypoint,
        or at the vehicle when the plan is empty.

        Args:
            world: The world.
            end_location: Where the route ends.
            start_location: Where it starts.
            clean_queue: Whether to replace the plan or append to it.

        Raises:
            Error: If a map query fails.
        """
        var start = world.get_location(self.vehicle)
        if Bool(start_location):
            start = start_location.value()
        elif clean_queue:
            start = self.local_planner.target.transform.location
        elif len(self.local_planner.queue) > 0:
            start = self.local_planner.queue[
                len(self.local_planner.queue) - 1
            ].transform.location
        var start_wp = world.map.closest_waypoint_on_road(start).value()
        var end_wp = world.map.closest_waypoint_on_road(end_location).value()
        var route = self.trace_route(world.map, start_wp, end_wp)
        self.local_planner.set_global_plan(route, True, clean_queue)

    def set_global_plan(
        mut self,
        plan: List[PlanItem],
        stop_waypoint_creation: Bool = True,
        clean_queue: Bool = True,
    ):
        """Follow a given plan, `set_global_plan`.

        Args:
            plan: The items.
            stop_waypoint_creation: Whether to stop adding random
                waypoints after it.
            clean_queue: Whether to replace the plan.
        """
        self.local_planner.set_global_plan(
            plan, stop_waypoint_creation, clean_queue
        )

    def trace_route(
        mut self, map: Map, start: Waypoint, end: Waypoint
    ) raises -> List[PlanItem]:
        """Return the shortest route between two waypoints, `trace_route`.

        Args:
            map: The map.
            start: The first waypoint.
            end: The last waypoint.

        Returns:
            The plan.

        Raises:
            Error: If a map query fails.
        """
        return self.global_planner.trace_route(
            map,
            map.compute_transform(start).location,
            map.compute_transform(end).location,
        )

    def _speed(self, world: World) raises -> Float64:
        return Float64(speed_of(world.get_velocity(self.vehicle)).value)

    def run_step(mut self, world: World) raises -> VehicleControl:
        """Plan and control one step, `run_step`.

        Args:
            world: The world.

        Returns:
            The local planner's control, or an emergency stop when a
            vehicle or a red light is in the way.

        Raises:
            Error: If the vehicle is gone, or a map query fails.
        """
        var speed = self._speed(world)
        var ratio = Float64(self.speed_ratio.value) * speed
        var hazard = self.vehicle_obstacle_detected(
            world,
            world.filter_actors("*vehicle*"),
            Length(
                Float32(Float64(self.base_vehicle_threshold.value) + ratio),
                METER,
            ),
        ).obstacle_was_found
        if self.affected_by_traffic_light(
            world,
            self.lights_list.copy(),
            Length(
                Float32(Float64(self.base_tlight_threshold.value) + ratio),
                METER,
            ),
        ).traffic_light_was_found:
            hazard = True
        var control = self.local_planner.run_step(world)
        if hazard:
            return self.add_emergency_stop(control)
        return control

    def done(self) -> Bool:
        """Return True if the plan is finished, `done`.

        Returns:
            Whether the local planner's queue is empty.
        """
        return self.local_planner.done()

    def ignore_traffic_lights(mut self, active: Bool = True):
        """Turn the red-light check off or on, `ignore_traffic_lights`.

        Args:
            active: Whether to ignore lights.
        """
        self.ignore_lights = active

    def ignore_stop_signs(mut self, active: Bool = True):
        """Keep CARLA's flag for stop signs, `ignore_stop_signs`.

        CARLA's agent keeps the flag and never checks a stop sign.

        Args:
            active: Whether to ignore stop signs.
        """
        self.ignore_signs = active

    def ignore_vehicles(mut self, active: Bool = True):
        """Turn the vehicle check off or on, `ignore_vehicles`.

        Args:
            active: Whether to ignore vehicles.
        """
        self.ignore_others = active

    def set_offset(mut self, offset: Length):
        """Drive to the side of the plan, `set_offset`.

        CARLA changes the local planner's offset only; the detection keeps
        the offset the agent was made with.

        Args:
            offset: Plus is to the right.
        """
        self.local_planner.set_offset(offset)

    def lane_change(
        mut self,
        world: World,
        direction: RoadOption,
        same_lane_time: Duration = Duration(0, SECOND),
        other_lane_time: Duration = Duration(0, SECOND),
        lane_change_time: Duration = Duration(2, SECOND),
    ) raises:
        """Replace the plan with a lane change, `lane_change`.

        The times turn into distances at the vehicle's speed. The change
        does not check the lane marks.

        Args:
            world: The world.
            direction: `OPTION_CHANGE_LANE_LEFT` or
                `OPTION_CHANGE_LANE_RIGHT`.
            same_lane_time: How long to stay in the lane first.
            other_lane_time: How long to drive in the new lane after.
            lane_change_time: How long the change takes.

        Raises:
            Error: If a map query fails.
        """
        var speed = Float32(self._speed(world))
        var here = world.map.closest_waypoint_on_road(
            world.get_location(self.vehicle)
        ).value()
        var path = self.generate_lane_change_path(
            world.map,
            here,
            direction,
            Length(same_lane_time.value * speed, METER),
            Length(other_lane_time.value * speed, METER),
            Length(lane_change_time.value * speed, METER),
            False,
            1,
            self.sampling_resolution,
        )
        self.set_global_plan(path)

    def affected_by_traffic_light(
        mut self,
        world: World,
        lights_list: Optional[List[ActorId]] = None,
        max_distance: Optional[Length] = None,
    ) raises -> TrafficLightDetectionResult:
        """Return the red light that holds the vehicle, if any,
        `_affected_by_traffic_light`.

        Args:
            world: The world.
            lights_list: The lights to check; None or empty checks every
                light of the world.
            max_distance: How far to look; None or zero uses
                `base_tlight_threshold`.

        Returns:
            Whether a red light holds the vehicle, and which.

        Raises:
            Error: If an actor is gone, or a map query fails.
        """
        if self.ignore_lights:
            return TrafficLightDetectionResult(False, None)
        var lights = world.filter_actors("*traffic_light*")
        if Bool(lights_list) and len(lights_list.value()) > 0:
            lights = lights_list.value().copy()
        var reach = self.base_tlight_threshold
        if Bool(max_distance) and max_distance.value().value != 0.0:
            reach = max_distance.value()
        if Bool(self.last_traffic_light):
            var last = self.last_traffic_light.value()
            if world.get_traffic_light_state_of(last) != RED:
                self.last_traffic_light = None
            else:
                return TrafficLightDetectionResult(True, last)
        var ego = world.get_location(self.vehicle)
        var ego_wp = plan_item(
            world.map,
            world.map.closest_waypoint_on_road(ego).value(),
            OPTION_LANE_FOLLOW,
        )
        var ve_dir = ego_wp.transform.rotation.forward_vector()
        for light in lights:
            var cached = self.lights_map.get(light.value)
            if not Bool(cached):
                var at = get_trafficlight_trigger_location(world, light)
                cached = plan_item(
                    world.map,
                    world.map.closest_waypoint_on_road(at).value(),
                    OPTION_LANE_FOLLOW,
                )
                self.lights_map[light.value] = cached.value()
            var trigger = cached.value()
            if Float64(trigger.transform.location.distance_to(ego)) > Float64(
                reach.value
            ):
                continue
            if trigger.waypoint.road_id != ego_wp.waypoint.road_id:
                continue
            var wp_dir = trigger.transform.rotation.forward_vector()
            if ve_dir.dot(wp_dir) < 0.0:
                continue
            if world.get_traffic_light_state_of(light) != RED:
                continue
            if is_within_distance(
                trigger.transform,
                world.get_transform(self.vehicle),
                reach,
                (Angle(0, DEGREE), Angle(90, DEGREE)),
            ):
                self.last_traffic_light = light
                return TrafficLightDetectionResult(True, light)
        return TrafficLightDetectionResult(False, None)

    def _route_polygon(
        self,
        world: World,
        ego: CarlaTransform,
        extent_y: Float32,
        reach: Float64,
    ) raises -> List[Vector3]:
        var ring = List[Vector3]()
        var r_ext = extent_y + self.offset.value
        var l_ext = -extent_y + self.offset.value
        var r = ego.rotation.right_vector()
        ring.append(ego.location + Vector3(r_ext * r.x, r_ext * r.y, 0))
        ring.append(ego.location + Vector3(l_ext * r.x, l_ext * r.y, 0))
        for item in self.local_planner.queue:
            var at = item.transform.location
            if Float64(ego.location.distance_to(at)) > reach:
                break
            r = item.transform.rotation.right_vector()
            ring.append(at + Vector3(r_ext * r.x, r_ext * r.y, 0))
            ring.append(at + Vector3(l_ext * r.x, l_ext * r.y, 0))
        return ring^

    def vehicle_obstacle_detected(
        self,
        world: World,
        vehicle_list: Optional[List[ActorId]] = None,
        max_distance: Optional[Length] = None,
        up_angle_th: Angle = Angle(90, DEGREE),
        low_angle_th: Angle = Angle(0, DEGREE),
        lane_offset: Int = 0,
    ) raises -> ObstacleDetectionResult:
        """Return the first actor in the vehicle's way, if any,
        `_vehicle_obstacle_detected`.

        Args:
            world: The world.
            vehicle_list: The actors to check; None checks every vehicle
                of the world.
            max_distance: How far to look; None or zero uses
                `base_vehicle_threshold`.
            up_angle_th: The upper end of the angle range.
            low_angle_th: The lower end of the angle range.
            lane_offset: Which lane to check: 0 is the vehicle's own lane,
                1 the next lane to the right, -1 to the left.

        Returns:
            Whether an actor is in the way, which, and how far its center
            is from the vehicle's.

        Raises:
            Error: If an actor is gone, or a map query fails.
        """
        if self.ignore_others:
            return _no_obstacle()
        var targets = world.filter_actors("*vehicle*")
        if Bool(vehicle_list):
            targets = vehicle_list.value().copy()
        if len(targets) == 0:
            return _no_obstacle()
        var reach = self.base_vehicle_threshold
        if Bool(max_distance) and max_distance.value().value != 0.0:
            reach = max_distance.value()
        var limit = Float64(reach.value)
        var ego = world.get_transform(self.vehicle)
        var box = world.get_bounding_box(self.vehicle)
        var ego_wp = world.map.closest_waypoint_on_road(ego.location).value()
        var offset = lane_offset
        if ego_wp.lane_id.value < 0 and offset != 0:
            offset = -offset
        var front = ego
        front.location = (
            front.location + ego.rotation.forward_vector() * box.extent.x
        )
        var opposite_invasion = (
            Float64(abs(self.offset.value) + box.extent.y)
            > world.map.lane_width_meters(ego_wp) / 2.0
        )
        var use_bbs = (
            self.use_bbs_detection
            or opposite_invasion
            or world.map.is_junction(ego_wp.road_id)
        )
        var ring = self._route_polygon(world, ego, box.extent.y, limit)
        var incoming = self.local_planner.get_incoming_waypoint_and_direction(3)
        # The list is not empty, checked above.
        for target in targets:  # pragma: no branch
            if target == self.vehicle:
                continue
            var t = world.get_transform(target)
            if Float64(t.location.distance_to(ego.location)) > limit:
                continue
            var target_wp = world.map.closest_waypoint_on_road(
                t.location, LANE_ANY
            ).value()
            if (use_bbs or world.map.is_junction(target_wp.road_id)) and len(
                ring
            ) >= 3:
                var corners = world.get_bounding_box(target).world_vertices(t)
                if polygons_intersect(ring, corners):
                    return ObstacleDetectionResult(
                        True,
                        target,
                        compute_distance(
                            world.get_location(target), ego.location
                        ),
                    )
                continue
            if not _on_lane(target_wp, ego_wp, offset):
                if not Bool(incoming) or not _on_lane(
                    target_wp, incoming.value().waypoint, offset
                ):
                    continue
            var fwd = t.rotation.forward_vector()
            var extent = world.get_bounding_box(target).extent.x
            var rear = t
            rear.location = Vector3(
                t.location.x - extent * fwd.x,
                t.location.y - extent * fwd.y,
                t.location.z,
            )
            if is_within_distance(
                rear, front, reach, (low_angle_th, up_angle_th)
            ):
                return ObstacleDetectionResult(
                    True, target, compute_distance(t.location, ego.location)
                )
        return _no_obstacle()

    def generate_lane_change_path(
        self,
        map: Map,
        waypoint: Waypoint,
        direction: RoadOption,
        distance_same_lane: Length = Length(10, METER),
        distance_other_lane: Length = Length(25, METER),
        lane_change_distance: Length = Length(25, METER),
        check: Bool = True,
        lane_changes: Int = 1,
        step_distance: Length = Length(2, METER),
    ) raises -> List[PlanItem]:
        """Return a plan that changes lanes, `_generate_lane_change_path`.

        Each distance is at least 0.1 m. The plan drives on in the lane,
        steps across once for each change, and drives on in the new
        lane. It is empty when a step finds no waypoint, the new lane is
        not a driving lane, or, with `check`, a mark forbids the change.

        Args:
            map: The map.
            waypoint: Where the plan starts.
            direction: `OPTION_CHANGE_LANE_LEFT` or
                `OPTION_CHANGE_LANE_RIGHT`. Any other option gives an
                empty plan.
            distance_same_lane: How far to stay in the lane first.
            distance_other_lane: How far to drive in the new lane after.
            lane_change_distance: How far the changes take in all.
            check: Whether the lane marks must allow the change.
            lane_changes: How many lanes to cross.
            step_distance: The spacing of the plan.

        Returns:
            The plan.

        Raises:
            Error: If the direction is not a valid road option, or a map
                query fails.
        """
        if not direction.is_valid():
            raise Error("Road option is not valid")
        var same = max(Float64(distance_same_lane.value), 0.1)
        var other = max(Float64(distance_other_lane.value), 0.1)
        var across = max(Float64(lane_change_distance.value), 0.1)
        var step = Float64(step_distance.value)
        var empty = List[PlanItem]()
        var plan = List[PlanItem]()
        plan.append(plan_item(map, waypoint, OPTION_LANE_FOLLOW))
        if not _drive_on(map, plan, same, step):
            return empty^
        var left = direction == OPTION_CHANGE_LANE_LEFT
        if not (left or direction == OPTION_CHANGE_LANE_RIGHT):
            return empty^
        var allowed = CHANGE_LEFT if left else CHANGE_RIGHT
        across = across / Float64(lane_changes)
        for _ in range(lane_changes):
            var nexts = map.next(plan[len(plan) - 1].waypoint, across)
            if len(nexts) == 0:
                return empty^
            var change = map.lane_change(nexts[0])
            if check and not (change == allowed or change == CHANGE_BOTH):
                return empty^
            var side = map.left(nexts[0]) if left else map.right(nexts[0])
            if not Bool(side) or map.lane_type(side.value()) != LANE_DRIVING:
                return empty^
            plan.append(plan_item(map, side.value(), direction))
        if not _drive_on(map, plan, other, step):
            return empty^
        return plan^


def _on_lane(a: Waypoint, b: Waypoint, offset: Int) -> Bool:
    return (
        a.road_id == b.road_id and a.lane_id.value == b.lane_id.value + offset
    )


def _drive_on(
    map: Map, mut plan: List[PlanItem], length: Float64, step: Float64
) raises -> Bool:
    # Step along the lane until `length` is covered; False on a dead end.
    var distance = 0.0
    while distance < length:
        var last = plan[len(plan) - 1]
        var nexts = map.next(last.waypoint, step)
        if len(nexts) == 0:
            return False
        var item = plan_item(map, nexts[0], OPTION_LANE_FOLLOW)
        distance += Float64(
            item.transform.location.distance_to(last.transform.location)
        )
        plan.append(item)
    return True
