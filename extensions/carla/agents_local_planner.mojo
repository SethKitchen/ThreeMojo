# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's local planner: follow a queue of waypoints with PID control.

A `LocalPlanner` keeps a queue of `PlanItem`s, each a waypoint and the
road option that leads to it. Each `run_step` does this:

1. With `follow_speed_limits` set, the target speed becomes the
   vehicle's speed limit.
2. Unless a global plan stopped it, the planner tops the queue up to 100
   items. It steps `sampling_radius` ahead of the last item. Where more
   than one waypoint lies ahead, it picks a road option at random and
   takes the first waypoint with that option.
3. It drops the items the vehicle has reached: those nearer than
   `base_min_distance` plus `distance_ratio` times the speed, in a row
   from the front. The last item needs the vehicle within 1 m.
4. It steers for the first item left, at the target speed. With the
   queue empty, it brakes fully.

`compute_connection` names a turn from two headings: straight within 35
degrees, a left turn past 90 degrees of difference, and a right turn
between.

The source is CARLA's `PythonAPI/carla/agents/navigation/
local_planner.py`, checked against `LibCarla/source/carla/agents/
navigation/LocalPlanner.cpp`.

**Differences from CARLA.**

- The random choice at a fork uses a seeded minimal-standard generator,
  `extensions.carla.sensor_noise.SensorRandom`, and not Python's
  `random` module. The index is the draw times the number of options,
  rounded down.
- A plan item keeps its waypoint's pose, as a CARLA waypoint does.
- The planner takes the world at each step and reads the vehicle there.
- The planner raises an error when the vehicle is not on a driving lane
  at the start. CARLA stores a missing waypoint and fails later.
- CARLA's `dt` option is not kept: CARLA reads it only before the
  options are applied, so it never changes the gains.
"""

from extensions.carla.actor import ActorId
from extensions.carla.agents_controller import PIDGains, VehiclePIDController
from extensions.carla.agents_misc import (
    OPTION_LANE_FOLLOW,
    OPTION_LEFT,
    OPTION_RIGHT,
    OPTION_STRAIGHT,
    RoadOption,
    from_kmh,
    speed_of,
)
from extensions.carla.map import Map, Waypoint
from extensions.carla.physics.vehicle_control import VehicleControl
from extensions.carla.sensor_noise import SensorRandom
from extensions.carla.transform import CarlaTransform
from extensions.carla.world import World
from std.ffi import external_call
from std.math import sqrt
from units.si import DEGREE, METER, SECOND, Angle, Duration, Length, Velocity


@fieldwise_init
struct PlanItem(ImplicitlyCopyable):
    """One step of a plan: a waypoint, its pose and the road option that
    leads to it."""

    var waypoint: Waypoint
    # The waypoint's pose, `Waypoint.transform`.
    var transform: CarlaTransform
    var road_option: RoadOption


def plan_item(
    map: Map, waypoint: Waypoint, road_option: RoadOption
) raises -> PlanItem:
    """Return a plan item with the waypoint's pose.

    Args:
        map: The map.
        waypoint: The waypoint.
        road_option: The road option that leads to it.

    Returns:
        The item.

    Raises:
        Error: If the road option is not valid, or the waypoint is not on
            the map.
    """
    if not road_option.is_valid():
        raise Error("Road option is not valid")
    return PlanItem(waypoint, map.compute_transform(waypoint), road_option)


def _python_mod(a: Float64, b: Float64) -> Float64:
    # Python's float `%`: the C remainder moved to the divisor's sign.
    var r = external_call["fmod", Float64](a, b)
    if r != 0.0 and ((r < 0.0) != (b < 0.0)):
        r += b
    return r


def compute_connection(
    current: CarlaTransform,
    next: CarlaTransform,
    threshold: Angle = Angle(35, DEGREE),
) -> RoadOption:
    """Name the turn from one heading to another, `_compute_connection`.

    Args:
        current: The pose now.
        next: The pose after the turn.
        threshold: The difference below which the turn is straight.

    Returns:
        `OPTION_STRAIGHT`, `OPTION_LEFT` or `OPTION_RIGHT`.
    """
    var n = _python_mod(Float64(next.rotation.yaw), 360.0)
    var c = _python_mod(Float64(current.rotation.yaw), 360.0)
    var diff = _python_mod(n - c, 180.0)
    var th = Float64(threshold.to(DEGREE))
    if diff < th or diff > 180.0 - th:
        return OPTION_STRAIGHT
    if diff > 90.0:
        return OPTION_LEFT
    return OPTION_RIGHT


def retrieve_options(
    map: Map, waypoints: List[Waypoint], current: Waypoint
) raises -> List[RoadOption]:
    """Name the turn to each of several next waypoints, `_retrieve_options`.

    Each is judged 3 m past the waypoint, since a waypoint at the start of
    a junction still faces nearly the old way.

    Args:
        map: The map.
        waypoints: The candidates.
        current: The waypoint now.

    Returns:
        One road option for each candidate.

    Raises:
        Error: If no waypoint lies 3 m past a candidate.
    """
    var out = List[RoadOption]()
    var now = map.compute_transform(current)
    for w in waypoints:
        var ahead = map.next(w, 3.0)
        if len(ahead) == 0:
            raise Error("No waypoint lies 3 m past a candidate")
        out.append(compute_connection(now, map.compute_transform(ahead[0])))
    return out^


@fieldwise_init
struct LocalPlannerOptions(ImplicitlyCopyable):
    """The planner's settings, CARLA's `opt_dict` of the local planner."""

    var target_speed: Velocity
    var sampling_radius: Length
    var lateral: PIDGains
    var longitudinal: PIDGains
    var max_throttle: Float64
    var max_brake: Float64
    var max_steering: Float64
    var offset: Length
    var base_min_distance: Length
    # Seconds of travel added to the reach distance.
    var distance_ratio: Duration
    var follow_speed_limits: Bool

    def __init__(out self):
        """Create CARLA's defaults: 20 km/h, a 2 m sampling radius, the
        lateral gains 1.95, 0.05, 0.2 and the longitudinal gains 1.5,
        0.05, 0.2 at 0.05 s, the limits 0.75, 0.3 and 0.8, no offset, and
        a reach of 3 m plus 0.5 s of travel."""
        self.target_speed = from_kmh(20)
        self.sampling_radius = Length(2, METER)
        self.lateral = PIDGains(1.95, 0.05, 0.2, Duration(0.05, SECOND))
        self.longitudinal = PIDGains(1.5, 0.05, 0.2, Duration(0.05, SECOND))
        self.max_throttle = 0.75
        self.max_brake = 0.3
        self.max_steering = 0.8
        self.offset = Length(0, METER)
        self.base_min_distance = Length(3, METER)
        self.distance_ratio = Duration(0.5, SECOND)
        self.follow_speed_limits = False


def _distance(a: CarlaTransform, b: CarlaTransform) -> Float64:
    var x = Float64(a.location.x) - Float64(b.location.x)
    var y = Float64(a.location.y) - Float64(b.location.y)
    var z = Float64(a.location.z) - Float64(b.location.z)
    return sqrt(x * x + y * y + z * z)


struct LocalPlanner(Movable):
    """Waypoint following with PID control, `LocalPlanner`."""

    var vehicle: ActorId
    var target_speed: Velocity
    var sampling_radius: Length
    var base_min_distance: Length
    var distance_ratio: Duration
    var follow_limits: Bool
    var controller: VehiclePIDController
    var queue: List[PlanItem]
    # `deque(maxlen=10000)`; a longer global plan raises it.
    var max_queue_length: Int
    var min_waypoint_queue_length: Int
    var stop_waypoint_creation: Bool
    # The item steered for last, `target_waypoint` and
    # `target_road_option`.
    var target: PlanItem
    # The reach distance of the last step.
    var min_distance: Length
    var random: SensorRandom

    def __init__(
        out self,
        world: World,
        vehicle: ActorId,
        options: LocalPlannerOptions = LocalPlannerOptions(),
        seed: Int = 0,
    ) raises:
        """Create a planner for a vehicle, `LocalPlanner.__init__`.

        The queue starts with the vehicle's own waypoint.

        Args:
            world: The world.
            vehicle: The vehicle to drive.
            options: The settings.
            seed: The seed of the random choice at forks.

        Raises:
            Error: If the actor is not a vehicle, or it is not on a
                driving lane.
        """
        self.vehicle = vehicle
        self.target_speed = options.target_speed
        self.sampling_radius = options.sampling_radius
        self.base_min_distance = options.base_min_distance
        self.distance_ratio = options.distance_ratio
        self.follow_limits = options.follow_speed_limits
        self.controller = VehiclePIDController(
            options.lateral,
            options.longitudinal,
            options.offset,
            options.max_throttle,
            options.max_brake,
            options.max_steering,
            Float64(world.get_control(vehicle).steer),
        )
        self.queue = List[PlanItem]()
        self.max_queue_length = 10000
        self.min_waypoint_queue_length = 100
        self.stop_waypoint_creation = False
        self.min_distance = Length(0, METER)
        self.random = SensorRandom(seed)
        var here = world.map.waypoint(world.get_location(vehicle))
        if not Bool(here):
            raise Error("The vehicle is not on a driving lane")
        var first = plan_item(world.map, here.value(), OPTION_LANE_FOLLOW)
        self.target = first
        self.queue.append(first)

    def set_speed(mut self, speed: Velocity):
        """Change the target speed, `set_speed`.

        With `follow_speed_limits` on, the next step replaces it.

        Args:
            speed: The new target speed.
        """
        self.target_speed = speed

    def follow_speed_limits(mut self, value: Bool = True):
        """Follow the vehicle's speed limit, `follow_speed_limits`.

        Args:
            value: Whether to follow it.
        """
        self.follow_limits = value

    def set_offset(mut self, offset: Length):
        """Drive to the side of the waypoints, `set_offset`.

        Args:
            offset: Plus is to the right.
        """
        self.controller.set_offset(offset)

    def compute_next_waypoints(mut self, map: Map, k: Int = 1) raises:
        """Add waypoints to the queue, `_compute_next_waypoints`.

        Args:
            map: The map.
            k: How many to add at most.

        Raises:
            Error: If a map query fails.
        """
        if len(self.queue) == 0:
            return
        var count = min(self.max_queue_length - len(self.queue), k)
        for _ in range(count):
            var last = self.queue[len(self.queue) - 1].waypoint
            var nexts = map.next(last, Float64(self.sampling_radius.value))
            if len(nexts) == 0:
                break
            var chosen = nexts[0]
            var option = OPTION_LANE_FOLLOW
            if len(nexts) > 1:
                var options = retrieve_options(map, nexts, last)
                var pick = Int(
                    Float64(self.random.uniform()) * Float64(len(options))
                )
                option = options[pick]
                # `list.index`: the first candidate with that option.
                var index = 0
                while options[index] != option:
                    index += 1
                chosen = nexts[index]
            self.queue.append(plan_item(map, chosen, option))

    def set_global_plan(
        mut self,
        plan: List[PlanItem],
        stop_waypoint_creation: Bool = True,
        clean_queue: Bool = True,
    ):
        """Follow a plan, `set_global_plan`.

        Args:
            plan: The items to follow.
            stop_waypoint_creation: Whether to stop adding waypoints
                after the plan.
            clean_queue: Whether to drop the queue first. If not, the plan
                follows it.
        """
        if clean_queue:
            self.queue.clear()
        var length = len(plan) + len(self.queue)
        if length > self.max_queue_length:
            self.max_queue_length = length
        for item in plan:
            self.queue.append(item)
        self.stop_waypoint_creation = stop_waypoint_creation

    def run_step(mut self, world: World) raises -> VehicleControl:
        """Plan and control one step, `run_step`.

        Args:
            world: The world.

        Returns:
            The control for the vehicle.

        Raises:
            Error: If the vehicle is gone, or a map query fails.
        """
        if self.follow_limits:
            self.target_speed = world.get_speed_limit(self.vehicle)
        if (
            not self.stop_waypoint_creation
            and len(self.queue) < self.min_waypoint_queue_length
        ):
            self.compute_next_waypoints(
                world.map, self.min_waypoint_queue_length
            )
        var pose = world.get_transform(self.vehicle)
        var speed = speed_of(world.get_velocity(self.vehicle))
        var reach = Float64(self.base_min_distance.value) + Float64(
            self.distance_ratio.value
        ) * Float64(speed.value)
        self.min_distance = Length(Float32(reach), METER)
        var removed = 0
        for item in self.queue:
            var limit = reach
            if len(self.queue) - removed == 1:
                limit = 1.0
            if _distance(pose, item.transform) < limit:
                removed += 1
            else:
                break
        for _ in range(removed):
            _ = self.queue.pop(0)
        if len(self.queue) == 0:
            var stop = VehicleControl()
            stop.brake = 1.0
            return stop
        self.target = self.queue[0]
        return self.controller.run_step(
            self.target_speed, self.queue[0].transform, pose, speed
        )

    def get_incoming_waypoint_and_direction(
        self, steps: Int = 3
    ) -> Optional[PlanItem]:
        """Return the item a few steps ahead,
        `get_incoming_waypoint_and_direction`.

        Args:
            steps: How many items ahead.

        Returns:
            That item, the last item if the queue is shorter, or None if
            it is empty. CARLA gives `(None, RoadOption.VOID)` then.
        """
        if len(self.queue) > steps:
            return self.queue[steps]
        if len(self.queue) > 0:
            return self.queue[len(self.queue) - 1]
        return None

    def get_plan(self) -> List[PlanItem]:
        """Return the queue, `get_plan`.

        Returns:
            A copy of the items left.
        """
        return self.queue.copy()

    def done(self) -> Bool:
        """Return True if the queue is empty, `done`.

        Returns:
            Whether the plan is finished.
        """
        return len(self.queue) == 0
