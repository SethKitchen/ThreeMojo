# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's traffic lights: controllers, groups and their cycle.

A traffic light belongs to a controller, and a controller to a group, one
group per junction. A controller runs its stages in turn: 10 s green,
3 s yellow and 2 s red by default. A group runs its controllers in turn:
while one runs its cycle, the lights of the others stay red, and when its
red stage ends, the next controller starts at green. So at a junction
with two controllers, one road has green while the other has red.

The lights come from the map. Each traffic-light signal a controller
holds becomes a light, and so does a traffic-light signal outside any
junction that no controller holds. That one gets a group and a controller
of its own, with a red stage of 10 s.

The sources are CARLA's simulator plugin, `Carla/Traffic/TrafficLightController.cpp`,
`TrafficLightGroup.cpp`, `TrafficLightManager.cpp`, `TrafficLightComponent.cpp`
and `TrafficLightBase.cpp`, and CARLA's `LibCarla/source/carla/client/TrafficLight.cpp`
for `affected_lane_waypoints` and `stop_waypoints`.

**Time.** A controller adds each tick to its elapsed time. The stage
changes on the first tick that takes the elapsed time past the stage's
time, and the elapsed time starts again from zero; the rest of that tick
is dropped, as in CARLA. A frozen group does not count.

**Orders to vehicles.** A light keeps the vehicles in its boxes. Each
time its state is set, the world gives those vehicles the new state. The
manager lists the lights it set in `notified`, an observer queue the
world empties after each call.

**Differences from CARLA.**

- CARLA does not tell the controller of a light with no OpenDRIVE
  controller which group it is in, so its state reads as zero. Here that
  light cycles and reports its state like any other.
- A signal learns its controllers only through the junctions that name
  them, as in CARLA. So a light held by a controller that no junction
  names gets a group of its own, like a light with no controller.
- CARLA keeps groups and controllers in hash maps. Here they are in the
  order they were made.
"""

from extensions.carla.actor import (
    ActorId,
    GREEN,
    RED,
    TrafficLightState,
    YELLOW,
    no_rotation,
    relative,
)
from extensions.carla.bounding_box import BoundingBox
from extensions.carla.map import Map, Waypoint, is_traffic_light
from extensions.carla.road_info import LaneId, SignalId
from extensions.carla.traffic_sign import TriggerBox, traffic_light_boxes
from extensions.carla.transform import CarlaRotation, CarlaTransform
from math.vector3 import Vector3
from units.si import DEGREE, SECOND, Angle, Duration, Length, METER


@fieldwise_init
struct TrafficLightStage(ImplicitlyCopyable, Writable):
    """One stage of a controller's cycle, CARLA's traffic light stage."""

    var time: Duration
    var state: TrafficLightState


def default_stages() -> List[TrafficLightStage]:
    """Return CARLA's default cycle.

    Returns:
        Green for 10 s, yellow for 3 s, red for 2 s.
    """
    return [
        TrafficLightStage(Duration(10, SECOND), GREEN),
        TrafficLightStage(Duration(3, SECOND), YELLOW),
        TrafficLightStage(Duration(2, SECOND), RED),
    ]


struct TrafficLightController(Copyable, Movable):
    """The lights that change together, CARLA's traffic light controller."""

    # The OpenDRIVE controller's id, or a negative number for a light that
    # had none.
    var id: String
    var stages: List[TrafficLightStage]
    var current_stage: Int
    var elapsed: Duration
    # The lights, as indices into the manager's `lights`.
    var lights: List[Int]
    # The group, as an index into the manager's `groups`.
    var group: Int
    var sequence: Int

    def __init__(out self, id: String):
        """Create a controller with CARLA's default cycle and no lights.

        Args:
            id: Its id.
        """
        self.id = id
        self.stages = default_stages()
        self.current_stage = 0
        self.elapsed = Duration(0, SECOND)
        self.lights = List[Int]()
        self.group = -1
        self.sequence = 0

    def stage_time(self, state: TrafficLightState) -> Duration:
        """Return how long the first stage of a state lasts, `GetStateTime`.

        Args:
            state: The state.

        Returns:
            The time, or zero with no such stage.
        """
        # A controller has one stage at least: `set_stages` checks.
        for s in self.stages:  # pragma: no branch
            if s.state == state:
                return s.time
        return Duration(0, SECOND)

    def set_stage_time(mut self, state: TrafficLightState, time: Duration):
        """Set how long every stage of a state lasts, `SetStateTime`.

        Args:
            state: The state.
            time: The new time.
        """
        # A controller has one stage at least: `set_stages` checks.
        for i in range(len(self.stages)):  # pragma: no branch
            if self.stages[i].state == state:
                self.stages[i].time = time

    def is_cycle_finished(self) -> Bool:
        """Return whether the last stage runs, `IsCycleFinished`.

        Returns:
            Whether the current stage is the last.
        """
        return self.current_stage == len(self.stages) - 1


struct TrafficLightGroup(Copyable, Movable):
    """The controllers of one junction, CARLA's traffic light group."""

    # The junction's id, or a negative number for a group of its own.
    var junction_id: Int
    # As indices into the manager's `controllers`.
    var controllers: List[Int]
    var current_controller: Int
    var frozen: Bool

    def __init__(out self, junction_id: Int):
        """Create an empty group.

        Args:
            junction_id: Its junction.
        """
        self.junction_id = junction_id
        self.controllers = List[Int]()
        self.current_controller = 0
        self.frozen = False


struct TrafficLight(Copyable, Movable):
    """One traffic light placed from the map."""

    var sign_id: SignalId
    # The light's pose: the signal's, turned a quarter to the right, level.
    var transform: CarlaTransform
    var state: TrafficLightState
    # As an index into the manager's `controllers`, or -1.
    var controller: Int
    var boxes: List[TriggerBox]
    var pole_index: Int
    # The vehicles in its boxes, one entry for each box they are in.
    var vehicles: List[ActorId]

    def __init__(out self, sign_id: SignalId, transform: CarlaTransform):
        """Create a red light with no controller and no boxes.

        Args:
            sign_id: Its signal.
            transform: Its pose.
        """
        self.sign_id = sign_id
        self.transform = transform
        self.state = RED
        self.controller = -1
        self.boxes = List[TriggerBox]()
        self.pole_index = 0
        self.vehicles = List[ActorId]()

    def trigger_volume(self) raises -> BoundingBox:
        """Return the light's first box in its own frame, `GetTriggerVolume`.

        Returns:
            The box's middle and turn relative to the light, and its half
            size; a zero box when the light has no box.

        Raises:
            Error: If the half size is not valid.
        """
        if len(self.boxes) == 0:
            return BoundingBox(Vector3(0, 0, 0))
        var local = relative(self.transform, self.boxes[0].transform)
        return BoundingBox(local.location, self.boxes[0].extent, local.rotation)


def light_transform(signal: CarlaTransform) -> CarlaTransform:
    """Return where CARLA stands a light or a sign for a signal.

    Args:
        signal: The signal's pose.

    Returns:
        The same place, level, with the yaw turned 90 degrees and wrapped
        into [-180, 180).
    """
    var out = signal
    out.rotation = CarlaRotation(
        Angle(0, DEGREE),
        Angle(signal.rotation.yaw + 90, DEGREE),
        Angle(0, DEGREE),
    ).normalized()
    return out


def _has_signal(map: Map, id: SignalId) -> Bool:
    for s in map.signals:
        if s.signal_id == id:
            return True
    return False


struct TrafficLightManager(Copyable, Movable):
    """Every traffic light of a world, CARLA's traffic light manager."""

    var lights: List[TrafficLight]
    var controllers: List[TrafficLightController]
    var groups: List[TrafficLightGroup]
    var frozen: Bool
    # The lights whose state was set since the world last looked.
    var notified: List[Int]
    var _missing_group: Int
    var _missing_controller: Int

    def __init__(out self):
        """Create a manager with no lights."""
        self.lights = List[TrafficLight]()
        self.controllers = List[TrafficLightController]()
        self.groups = List[TrafficLightGroup]()
        self.frozen = False
        self.notified = List[Int]()
        self._missing_group = -2
        self._missing_controller = -1

    @staticmethod
    def from_map(map: Map) raises -> TrafficLightManager:
        """Place a map's traffic lights, `SpawnTrafficLights`.

        Args:
            map: The map.

        Returns:
            The manager, with each light in its group, its boxes built,
            and each group reset: its first controller green, the others
            red.

        Raises:
            Error: If a map query fails.
        """
        var out = TrafficLightManager()
        var to_spawn = List[SignalId]()
        for c in map.controllers:
            for id in c.signals:
                if not _has_signal(map, id):
                    continue
                if not is_traffic_light(map.signal(id).type):
                    continue
                if not (id in to_spawn):
                    to_spawn.append(id)
        for s in map.signals:
            if (
                len(s.controllers) == 0
                and not map.is_junction(s.road_id)
                and is_traffic_light(s.type)
                and not (s.signal_id in to_spawn)
            ):
                to_spawn.append(s.signal_id)
        for id in to_spawn:
            var light = TrafficLight(
                id, light_transform(map.signal(id).transform)
            )
            light.boxes = traffic_light_boxes(map, id)
            out.lights.append(light^)
            out._register(map, len(out.lights) - 1)
        out.notified = List[Int]()
        return out^

    def _group_of_junction(mut self, junction: Int) -> Int:
        for g in range(len(self.groups)):
            if self.groups[g].junction_id == junction:
                return g
        self.groups.append(TrafficLightGroup(junction))
        return len(self.groups) - 1

    def _register(mut self, map: Map, light: Int) raises:
        """`RegisterLightComponentFromOpenDRIVE`."""
        ref signal = map.signal(self.lights[light].sign_id)
        var group: Int
        var controller = -1
        if len(signal.controllers) > 0:
            var id = signal.controllers[0]
            # A signal learns its controllers through the junctions that
            # name them, so its controller is in a junction; CARLA's check
            # for a controller with none can never fire.
            group = self._group_of_junction(
                map.controller(id).junctions[0].value
            )
            for i in range(len(self.controllers)):
                if self.controllers[i].id == id.value:
                    controller = i
            if controller < 0:
                self.controllers.append(TrafficLightController(id.value))
                controller = len(self.controllers) - 1
                self.controllers[controller].group = group
                self.groups[group].controllers.append(controller)
        else:
            self.groups.append(TrafficLightGroup(self._missing_group))
            group = len(self.groups) - 1
            self._missing_group -= 1
            self.controllers.append(
                TrafficLightController(String(self._missing_controller))
            )
            controller = len(self.controllers) - 1
            self._missing_controller -= 1
            self.controllers[controller].set_stage_time(
                RED, Duration(10, SECOND)
            )
            self.controllers[controller].group = group
            self.groups[group].controllers.append(controller)
        self.controllers[controller].lights.append(light)
        self.lights[light].controller = controller
        self.reset_state(controller)
        self.reset_group(group)

    # --- the controller's cycle -------------------------------------------

    def set_light_state(mut self, light: Int, state: TrafficLightState) raises:
        """Set one light's state, CARLA's `SetLightState`.

        The controller's cycle goes on, and sets the light again at its
        next stage.

        Args:
            light: The light's index.
            state: The new state.

        Raises:
            Error: If the index or the state is not valid.
        """
        self._check(light)
        if not state.is_valid():
            raise Error("Traffic light state is not valid")
        self.lights[light].state = state
        self.notified.append(light)

    def _set_controller_lights(mut self, controller: Int):
        var state = (
            self.controllers[controller]
            .stages[self.controllers[controller].current_stage]
            .state
        )
        for light in self.controllers[controller].lights:
            self.lights[light].state = state
            self.notified.append(light)

    def next_state(mut self, controller: Int):
        """Go to a controller's next stage, `NextState`.

        Args:
            controller: The controller's index.
        """
        var count = len(self.controllers[controller].stages)
        var next = (self.controllers[controller].current_stage + 1) % count
        self.controllers[controller].current_stage = next
        self._set_controller_lights(controller)

    def advance(mut self, controller: Int, dt: Duration) -> Bool:
        """Add time to a controller, `AdvanceTimeAndCycleFinished`.

        Args:
            controller: The controller's index.
            dt: The tick.

        Returns:
            True when the last stage's time has passed: the group must
            start its next controller.
        """
        var elapsed = self.controllers[controller].elapsed + dt
        var stage = self.controllers[controller].current_stage
        self.controllers[controller].elapsed = elapsed
        if elapsed > self.controllers[controller].stages[stage].time:
            self.controllers[controller].elapsed = Duration(0, SECOND)
            if self.controllers[controller].is_cycle_finished():
                return True
            self.next_state(controller)
        return False

    def start_cycle(mut self, controller: Int):
        """Start a controller at its first stage, `StartCycle`.

        Args:
            controller: The controller's index.
        """
        self.controllers[controller].elapsed = Duration(0, SECOND)
        self.controllers[controller].current_stage = 0
        self._set_controller_lights(controller)

    def reset_state(mut self, controller: Int):
        """Put a controller at its last stage, `ResetState`.

        Args:
            controller: The controller's index.
        """
        var last = len(self.controllers[controller].stages) - 1
        self.controllers[controller].current_stage = last
        self.controllers[controller].elapsed = Duration(0, SECOND)
        self._set_controller_lights(controller)

    def set_stages(
        mut self, controller: Int, var stages: List[TrafficLightStage]
    ) raises:
        """Replace a controller's cycle and reset it, `SetStates`.

        Args:
            controller: The controller's index.
            stages: The new stages.

        Raises:
            Error: If there are no stages, or a state is not valid.
        """
        if len(stages) == 0:
            raise Error("A controller needs at least one stage")
        # The list is not empty, checked above.
        for s in stages:  # pragma: no branch
            if not s.state.is_valid():
                raise Error("Traffic light state is not valid")
        self.controllers[controller].stages = stages^
        self.reset_state(controller)

    # --- the group -----------------------------------------------------------

    def reset_group(mut self, group: Int):
        """Reset a group, `ResetGroup`: every controller to its last
        stage, then the first controller to its first.

        Args:
            group: The group's index.
        """
        # A group gets its first controller when it is made.
        for c in self.groups[group].controllers.copy():  # pragma: no branch
            self.reset_state(c)
        self.groups[group].current_controller = 0
        # A group gets its first controller when it is made.
        self.start_cycle(self.groups[group].controllers[0])

    def tick(mut self, dt: Duration):
        """Advance every group that is not frozen, `Tick`.

        Args:
            dt: The world's tick.
        """
        for g in range(len(self.groups)):
            if self.groups[g].frozen:
                continue
            var at = self.groups[g].current_controller
            # A group gets its first controller when it is made.
            if self.advance(self.groups[g].controllers[at], dt):
                at = (at + 1) % len(self.groups[g].controllers)
                self.groups[g].current_controller = at
                self.start_cycle(self.groups[g].controllers[at])

    def set_frozen(mut self, frozen: Bool):
        """Freeze or free every group, `SetFrozen`.

        Args:
            frozen: Whether time stops for the lights.
        """
        self.frozen = frozen
        for i in range(len(self.groups)):
            self.groups[i].frozen = frozen

    def reset_all(mut self):
        """Reset every group, the world's `ResetAllTrafficLights`."""
        for g in range(len(self.groups)):
            self.reset_group(g)

    # --- one light's view ----------------------------------------------------

    def _check(self, light: Int) raises:
        if light < 0 or light >= len(self.lights):
            raise Error("Traffic light index is out of range")

    def time_of(self, light: Int, state: TrafficLightState) raises -> Duration:
        """Return how long a light's controller keeps a state.

        Args:
            light: The light's index.
            state: Green, yellow or red.

        Returns:
            The stage's time, or zero with no controller.

        Raises:
            Error: If the index is out of range.
        """
        self._check(light)
        var c = self.lights[light].controller
        if c < 0:
            return Duration(0, SECOND)
        return self.controllers[c].stage_time(state)

    def set_time_of(
        mut self, light: Int, state: TrafficLightState, time: Duration
    ) raises:
        """Set how long a light's controller keeps a state,
        `SetGreenTime`, `SetYellowTime` and `SetRedTime`.

        Args:
            light: The light's index.
            state: Green, yellow or red.
            time: The new time.

        Raises:
            Error: If the index is out of range, or the light has no
                controller.
        """
        self._check(light)
        var c = self.lights[light].controller
        if c < 0:
            raise Error("The traffic light has no controller")
        self.controllers[c].set_stage_time(state, time)

    def elapsed_time(self, light: Int) raises -> Duration:
        """Return the time in a light's current stage, `GetElapsedTime`.

        Args:
            light: The light's index.

        Returns:
            The elapsed time, or zero with no controller.

        Raises:
            Error: If the index is out of range.
        """
        self._check(light)
        var c = self.lights[light].controller
        if c < 0:
            return Duration(0, SECOND)
        return self.controllers[c].elapsed

    def group_of(self, light: Int) raises -> Int:
        """Return a light's group.

        Args:
            light: The light's index.

        Returns:
            The group's index, or -1.

        Raises:
            Error: If the index is out of range.
        """
        self._check(light)
        var c = self.lights[light].controller
        if c < 0:
            return -1
        return self.controllers[c].group

    def is_frozen(self, light: Int) raises -> Bool:
        """Return whether a light's group is frozen, `IsFrozen`.

        Args:
            light: The light's index.

        Returns:
            Whether its group is frozen; False with no group.

        Raises:
            Error: If the index is out of range.
        """
        var g = self.group_of(light)
        return g >= 0 and self.groups[g].frozen

    def group_lights(self, light: Int) raises -> List[Int]:
        """Return the lights of a light's group, `GetGroupTrafficLights`.

        Args:
            light: The light's index.

        Returns:
            The lights of each controller of the group, in order; empty
            with no group.

        Raises:
            Error: If the index is out of range.
        """
        var out = List[Int]()
        var g = self.group_of(light)
        if g < 0:
            return out^
        # A group gets its first controller when it is made.
        for c in self.groups[g].controllers:  # pragma: no branch
            out.extend(self.controllers[c].lights.copy())
        return out^

    def reset_group_of(mut self, light: Int) raises:
        """Reset a light's group, `ResetGroup`.

        Args:
            light: The light's index.

        Raises:
            Error: If the index is out of range.
        """
        var g = self.group_of(light)
        if g >= 0:
            self.reset_group(g)

    def find(self, sign_id: SignalId) -> Int:
        """Return the light of a signal.

        Args:
            sign_id: The signal's id.

        Returns:
            The light's index, or -1.
        """
        for i in range(len(self.lights)):
            if self.lights[i].sign_id == sign_id:
                return i
        return -1


def affected_lane_waypoints(
    map: Map, sign_id: SignalId
) raises -> List[Waypoint]:
    """Return the waypoints of the lanes a light holds,
    `TrafficLight::GetAffectedLaneWaypoints`.

    Args:
        map: The map.
        sign_id: The light's signal.

    Returns:
        For each reference and each lane of its validities, lane 0 left
        out, the waypoint at the reference's s. CARLA lists a missing
        waypoint as null; this list leaves it out.

    Raises:
        Error: If the id is not valid.
    """
    var out = List[Waypoint]()
    for landmark in map.landmarks_from_id(sign_id):
        ref r = landmark.reference
        for v in r.validities:
            var lanes = List[Int]()
            if v.from_lane.value < v.to_lane.value:
                # from < to, so the range holds two lanes at least.
                for lane in range(
                    v.from_lane.value, v.to_lane.value + 1
                ):  # pragma: no branch
                    lanes.append(lane)
            else:
                # from >= to, so the range holds one lane at least.
                for lane in range(
                    v.from_lane.value, v.to_lane.value - 1, -1
                ):  # pragma: no branch
                    lanes.append(lane)
            # Either range above holds one lane at least.
            for lane in lanes:  # pragma: no branch
                if lane == 0:
                    continue
                var w = map.waypoint_xodr(
                    r.road_id, LaneId(lane), Length(Float32(r.s), METER)
                )
                if Bool(w):
                    out.append(w.value())
    return out^


def stop_waypoints(
    map: Map, transform: CarlaTransform, trigger_volume: BoundingBox
) raises -> List[Waypoint]:
    """Return where vehicles stop for a light, `GetStopWaypoints`.

    CARLA steps along the light's forward axis through its trigger
    volume, from -0.9 to 0.9 of the volume's x half size, 1 m at a time,
    and keeps the first waypoint of each road and lane it finds.

    Args:
        map: The map.
        transform: The light's pose.
        trigger_volume: Its trigger volume, in its frame.

    Returns:
        The waypoints.

    Raises:
        Error: If a map query fails.
    """
    var out = List[Waypoint]()
    var middle = transform.transform_point(trigger_volume.location)
    var along = transform.rotation.forward_vector()
    var x = Float32(-0.9) * trigger_volume.extent.x
    var end = Float32(0.9) * trigger_volume.extent.x
    while x < end:
        var found = map.closest_waypoint_on_road(middle + along * x)
        x += 1
        if not Bool(found):
            continue
        var w = found.value()
        var seen = False
        for have in out:
            if have.road_id == w.road_id and have.lane_id == w.lane_id:
                seen = True
        if not seen:
            out.append(w)
    return out^
