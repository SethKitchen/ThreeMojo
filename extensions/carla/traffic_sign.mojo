# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's traffic signs: stop, yield and speed-limit signs from the map.

A sign acts on a vehicle through boxes on the road. A vehicle that enters
a stop sign's effect box is told to stop. The sign lets it go when no
other vehicle is in the sign's check boxes, which cover the junction
lanes that cross its path and the lane before each of them. A yield sign
does the same without the full stop. A speed-limit sign's box gives the
vehicle the sign's limit.

The boxes are the ones CARLA's simulator plugin builds in
`Carla/Traffic/SignComponent.cpp`, `StopSignComponent.cpp`,
`YieldSignComponent.cpp` and `SpeedLimitComponent.cpp`, and the choice of
which signals become signs is `TrafficLightManager.cpp`'s. A box is a
`TriggerBox`: a pose from `Map.compute_transform` and a half size, in
meters.

**The give-way timers.** CARLA calls the stop sign's give-way check after
a delay: 2 s after a vehicle enters the stop box, 1 s after a failed
check, and 0.5 s after a vehicle leaves a check box. A `TrafficSign`
keeps these as a list of timers, a scheduled-callback queue that
`tick_timers` runs down once per world tick. A timer fires on the first
tick that brings it to zero or below. The yield sign checks at once, and
again 0.5 s after a failed check.

**Differences from CARLA.**

- CARLA crashes on a stop or speed-limit reference whose lane has no
  waypoint at the reference's s. This port skips that lane, as CARLA's
  yield sign does.
- CARLA finds a sign's references road by road in hash order. This port
  goes by road id.
"""

from extensions.carla.actor import ActorId, GREEN, RED, TrafficLightState
from extensions.carla.map import (
    Map,
    SIGNAL_MAXIMUM_SPEED,
    SIGNAL_STOP,
    SIGNAL_YIELD,
    Waypoint,
)
from extensions.carla.math import generate_range
from extensions.carla.road_info import (
    LANE_DRIVING,
    LaneId,
    RoadId,
    RoadInfoSignal,
    SignalId,
    info_at,
)
from extensions.carla.transform import CarlaTransform
from math.matrix3 import Matrix3
from math.obb import OBB
from math.vector3 import Vector3
from units.si import Length, METER, Velocity

# The clamp margin CARLA keeps from a lane section's ends, in meters.
comptime _EPSILON = 0.00001
# CARLA's default speed, in the road's unit, where a road has no limit.
comptime _DEFAULT_SPEED = Float32(40)
# How far ahead in time the check boxes reach before a crossing lane.
comptime _ANTICIPATION_TIME = Float32(0.1)


@fieldwise_init
struct SignKind(Equatable, ImplicitlyCopyable, Writable):
    """What a traffic sign does."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names a kind.

        Returns:
            Whether the value is from 0 to 2.
        """
        return self.value >= 0 and self.value <= 2


comptime STOP_SIGN = SignKind(0)
comptime YIELD_SIGN = SignKind(1)
comptime SPEED_LIMIT_SIGN = SignKind(2)


struct TriggerBox(ImplicitlyCopyable):
    """A box on the road that a vehicle enters, CARLA's trigger volume."""

    # The box's middle and its axes: forward along the lane, right, up.
    var transform: CarlaTransform
    # Half its size along its own forward, right and up axes, in meters.
    var extent: Vector3

    def __init__(out self, transform: CarlaTransform, extent: Vector3):
        """Create a box.

        Args:
            transform: The box's pose in the world.
            extent: Its half size, in meters.
        """
        self.transform = transform
        self.extent = extent

    def obb(self) raises -> OBB:
        """Return the box as an oriented box in the world.

        Returns:
            The `OBB`.

        Raises:
            Error: If the half size is not valid.
        """
        var r = self.transform.rotation
        var f = r.forward_vector()
        var y = r.right_vector()
        var u = r.up_vector()
        var axes = Matrix3()
        axes.set(f.x, y.x, u.x, f.y, y.y, u.y, f.z, y.z, u.z)
        return OBB(self.transform.location, self.extent, axes)


@fieldwise_init
struct SignalUpdate(ImplicitlyCopyable, Writable):
    """A signal's order to one vehicle: the state it must obey."""

    var vehicle: ActorId
    var state: TrafficLightState


def signal_references(map: Map, id: SignalId) raises -> List[RoadInfoSignal]:
    """Return every reference to a signal, `GetAllReferencesToThisSignal`.

    CARLA looks only at the roads that have a driving lane, through the
    waypoints at their lane entries.

    Args:
        map: The map.
        id: The signal.

    Returns:
        The signal's references, each on its road.

    Raises:
        Error: If the id is not valid.
    """
    if not id.is_valid():
        raise Error("Signal id is not valid")
    var explored = List[Int]()
    var out = List[RoadInfoSignal]()
    for w in map.generate_waypoints_on_road_entries():
        if w.road_id.value in explored:
            continue
        explored.append(w.road_id.value)
        for reference in map.road(w.road_id).info.signals:
            if reference.signal_id == id:
                out.append(reference.copy())
    return out^


def _lane_bounds(map: Map, w: Waypoint) raises -> Tuple[Float64, Float64]:
    """The start and the length of a waypoint's lane section."""
    ref road = map.road(w.road_id)
    var section = road.section_index(w.section_id)
    return (road.sections[section].s, road.section_length(section))


def _shifted(
    map: Map, w: Waypoint, lane: Int, distance: Float64
) raises -> Waypoint:
    """Move a waypoint against a lane's traffic, clamped to its section."""
    var bounds = _lane_bounds(map, w)
    var low = bounds[0] + _EPSILON
    var high = bounds[0] + bounds[1] - _EPSILON
    var s = w.s - distance if lane < 0 else w.s + distance
    var out = w
    out.s = min(max(s, low), high)
    return out


def _from_before_junction(map: Map, w: Waypoint) raises -> Waypoint:
    """A junction lane's single predecessor outside the junction, or it."""
    if map.is_junction(w.road_id):
        var before = map.predecessors(w)
        if len(before) == 1 and not map.is_junction(before[0].road_id):
            return before[0]
    return w


def _lane_box(map: Map, w: Waypoint, lane: Int) raises -> TriggerBox:
    """The box before a signal on one lane: 1.5 m long, half a lane wide."""
    var width = max(Float32(0.5 * map.lane_width_meters(w) * 0.5), 0.01)
    var at = _shifted(map, w, lane, 3.0)
    return TriggerBox(map.compute_transform(at), Vector3(1.5, width, 1.0))


def traffic_light_boxes(map: Map, id: SignalId) raises -> List[TriggerBox]:
    """Return a traffic light's effect boxes, CARLA's
    `UTrafficLightComponent::InitializeSign`.

    For each lane a reference holds for, the box sits 3 m before the
    reference against the lane's traffic, within its lane section. On a
    junction lane with one predecessor outside the junction, it sits on
    that predecessor. Only driving lanes get one.

    Args:
        map: The map.
        id: The light's signal.

    Returns:
        The boxes.

    Raises:
        Error: If the id is not valid.
    """
    var out = List[TriggerBox]()
    for reference in signal_references(map, id):
        for validity in reference.validities:
            # A range holds one number at least.
            for lane in generate_range(  # pragma: no branch
                validity.from_lane.value, validity.to_lane.value
            ):
                if lane == 0:
                    continue
                var found = map.waypoint_xodr(
                    reference.road_id,
                    LaneId(lane),
                    Length(Float32(reference.s), METER),
                )
                if not Bool(found):
                    continue
                var w = _from_before_junction(map, found.value())
                if map.lane_type(w) != LANE_DRIVING:
                    continue
                out.append(_lane_box(map, w, lane))
    return out^


def _cube(map: Map, w: Waypoint, size: Float32) raises -> TriggerBox:
    return TriggerBox(map.compute_transform(w), Vector3(size, size, size))


def _check_boxes(
    map: Map,
    road: RoadId,
    predecessors: List[Int],
    mut out: List[TriggerBox],
) raises:
    """The check boxes on the junction lanes that cross a sign's road."""
    ref junction = map.junction(map.junction_id(road))
    if not junction.road_has_conflicts(road):
        return
    # The road has conflicts, checked above.
    for conflict in junction.conflicts_of_road(road):  # pragma: no branch
        for w in map.generate_waypoints_in_road(conflict):
            var shared = False
            for before in map.predecessors(w):
                if before.road_id.value in predecessors:
                    shared = True
            # CARLA also skips a lane that is not a driving lane, but the
            # waypoints above come from driving lanes only.
            if shared:
                continue
            var size = max(Float32(0.9 * map.lane_width_meters(w) * 0.5), 0.01)
            var step = Float64(2 * size)
            out.append(_cube(map, w, size))
            var next = w
            while True:
                var ahead = map.next(next, step)
                if len(ahead) != 1 or ahead[0].road_id != w.road_id:
                    break
                next = ahead[0]
                out.append(_cube(map, next, size))
            var queue = List[Tuple[Float32, Waypoint]]()
            for before in map.previous(w, step):
                queue.append((_ANTICIPATION_TIME, before))
            var head = 0
            while head < len(queue):
                var item = queue[head]
                head += 1
                out.append(_cube(map, item[1], size))
                var speed = _DEFAULT_SPEED
                var limit = info_at(
                    map.road(item[1].road_id).info.speeds, item[1].s
                )
                if Bool(limit):
                    speed = Float32(limit.value().speed)
                var remaining = item[0] - size / speed
                if remaining > 0:
                    for before in map.previous(item[1], step):
                        queue.append((remaining, before))


struct SignBoxes(Copyable, Movable):
    """A stop or yield sign's effect boxes and check boxes."""

    var effect: List[TriggerBox]
    var check: List[TriggerBox]

    def __init__(out self):
        """Create an empty set."""
        self.effect = List[TriggerBox]()
        self.check = List[TriggerBox]()


def give_way_boxes(map: Map, id: SignalId) raises -> SignBoxes:
    """Return a stop or yield sign's boxes, CARLA's
    `UStopSignComponent::InitializeSign` and the yield sign's.

    The effect boxes sit as a traffic light's do. The check boxes cover
    each driving lane of each junction road that crosses the sign's road
    and does not come from the same road: cubes a lane wide times 0.9,
    along the lane, and back along the lanes before it for 0.1 s at the
    road's speed.

    Args:
        map: The map.
        id: The sign's signal.

    Returns:
        The boxes.

    Raises:
        Error: If the id is not valid.
    """
    var out = SignBoxes()
    for reference in signal_references(map, id):
        var predecessors = List[Int]()
        for validity in reference.validities:
            # A range holds one number at least.
            for lane in generate_range(  # pragma: no branch
                validity.from_lane.value, validity.to_lane.value
            ):
                if lane == 0:
                    continue
                var found = map.waypoint_xodr(
                    reference.road_id,
                    LaneId(lane),
                    Length(Float32(reference.s), METER),
                )
                if not Bool(found):
                    continue
                var w = found.value()
                if map.lane_type(w) != LANE_DRIVING:
                    continue
                out.effect.append(
                    _lane_box(map, _from_before_junction(map, w), lane)
                )
                for before in map.predecessors(w):
                    if not (before.road_id.value in predecessors):
                        predecessors.append(before.road_id.value)
        if map.is_junction(reference.road_id):
            _check_boxes(map, reference.road_id, predecessors, out.check)
    return out^


def speed_limit_boxes(map: Map, id: SignalId) raises -> List[TriggerBox]:
    """Return a speed-limit sign's boxes, CARLA's
    `USpeedLimitComponent::InitializeSign`.

    Each is a cube 0.7 of a lane wide, its middle that half size before
    the reference against the lane's traffic.

    Args:
        map: The map.
        id: The sign's signal.

    Returns:
        The boxes.

    Raises:
        Error: If the id is not valid.
    """
    var out = List[TriggerBox]()
    for reference in signal_references(map, id):
        for validity in reference.validities:
            # A range holds one number at least.
            for lane in generate_range(  # pragma: no branch
                validity.from_lane.value, validity.to_lane.value
            ):
                if lane == 0:
                    continue
                var found = map.waypoint_xodr(
                    reference.road_id,
                    LaneId(lane),
                    Length(Float32(reference.s), METER),
                )
                if not Bool(found):
                    continue
                var w = found.value()
                if map.lane_type(w) != LANE_DRIVING:
                    continue
                var size = max(
                    Float32(0.7 * map.lane_width_meters(w) * 0.5), 0.01
                )
                var at = _shifted(map, w, lane, Float64(size))
                out.append(_cube(map, at, size))
    return out^


def sign_kind_of(
    type: String, subtype: String, name: String
) -> Optional[SignKind]:
    """Return the kind of sign CARLA places for a signal, if any.

    This is the choice in CARLA's `ATrafficLightManager::SpawnSignals`.

    Args:
        type: The signal's type.
        subtype: Its subtype.
        name: Its name.

    Returns:
        A stop sign for type 206 unless the name is "Stencil_STOP", which
        is paint; a yield sign for 205; a speed-limit sign for 274 with a
        subtype from 30 to 120 in steps of ten; else None.
    """
    if type == SIGNAL_STOP and name != "Stencil_STOP":
        return STOP_SIGN
    if type == SIGNAL_YIELD:
        return YIELD_SIGN
    if type == SIGNAL_MAXIMUM_SPEED:
        # CARLA has a sign model for 30 to 120 km/h in steps of ten.
        for speed in range(30, 130, 10):  # pragma: no branch
            if subtype == String(speed):
                return SPEED_LIMIT_SIGN
    return None


def sign_type_id(kind: SignKind, subtype: String) raises -> String:
    """Return a sign's blueprint id, such as `traffic.stop`.

    Args:
        kind: The sign's kind.
        subtype: The signal's subtype, the speed of a speed limit.

    Returns:
        "traffic.stop", "traffic.yield" or "traffic.speed_limit.<subtype>".

    Raises:
        Error: If the kind is not valid.
    """
    if not kind.is_valid():
        raise Error("Sign kind is not valid")
    if kind == STOP_SIGN:
        return "traffic.stop"
    if kind == YIELD_SIGN:
        return "traffic.yield"
    return "traffic.speed_limit." + subtype


struct TrafficSign(Copyable, Movable):
    """A stop, yield or speed-limit sign placed from the map."""

    var sign_id: SignalId
    var kind: SignKind
    # The sign's pose: the signal's, turned a quarter to the right, level.
    var transform: CarlaTransform
    var speed_limit: Velocity
    var effect_boxes: List[TriggerBox]
    var check_boxes: List[TriggerBox]
    # The vehicles in an effect box, as a set in the order they came.
    var vehicles_in_effect: List[ActorId]
    # The vehicles in check boxes, and in how many.
    var vehicles_to_check: List[ActorId]
    var check_counts: List[Int]
    # The give-way timers, in seconds left.
    var timers: List[Float32]

    def __init__(
        out self,
        sign_id: SignalId,
        kind: SignKind,
        transform: CarlaTransform,
        speed_limit: Velocity,
    ) raises:
        """Create a sign with no boxes.

        Args:
            sign_id: Its signal.
            kind: What it does.
            transform: Where it stands.
            speed_limit: The limit it gives, for a speed-limit sign.

        Raises:
            Error: If the signal id or the kind is not valid.
        """
        if not (sign_id.is_valid() and kind.is_valid()):
            raise Error("Sign id or kind is not valid")
        self.sign_id = sign_id
        self.kind = kind
        self.transform = transform
        self.speed_limit = speed_limit
        self.effect_boxes = List[TriggerBox]()
        self.check_boxes = List[TriggerBox]()
        self.vehicles_in_effect = List[ActorId]()
        self.vehicles_to_check = List[ActorId]()
        self.check_counts = List[Int]()
        self.timers = List[Float32]()

    def _find(self, list: List[ActorId], vehicle: ActorId) -> Int:
        for i in range(len(list)):
            if list[i] == vehicle:
                return i
        return -1

    def _delay(mut self, seconds: Float32):
        self.timers.append(seconds)

    def _drop_checked_in_effect(mut self):
        """`RemoveSameVehicleInBothLists`."""
        # The caller has just added a vehicle.
        for v in self.vehicles_in_effect.copy():  # pragma: no branch
            var i = self._find(self.vehicles_to_check, v)
            if i >= 0:
                _ = self.vehicles_to_check.pop(i)
                _ = self.check_counts.pop(i)

    def give_way(mut self) -> List[SignalUpdate]:
        """Let the stopped vehicles go if the check boxes are empty,
        `GiveWayIfPossible`.

        Returns:
            Green for each vehicle in an effect box when no vehicle is in
            a check box. Otherwise red for each, and a new check after
            1 s at a stop sign or 0.5 s at a yield sign.
        """
        var out = List[SignalUpdate]()
        if len(self.vehicles_to_check) == 0:
            for v in self.vehicles_in_effect:
                out.append(SignalUpdate(v, GREEN))
        elif len(self.vehicles_in_effect) > 0:
            # The list is not empty, checked above.
            for v in self.vehicles_in_effect:  # pragma: no branch
                out.append(SignalUpdate(v, RED))
            self._delay(
                Float32(1.0) if self.kind == STOP_SIGN else Float32(0.5)
            )
        return out^

    def begin_effect(mut self, vehicle: ActorId) -> List[SignalUpdate]:
        """A vehicle enters an effect box.

        At a stop sign it is told red, and the sign checks after 2 s. At
        a yield sign the sign checks at once.

        Args:
            vehicle: The vehicle.

        Returns:
            The orders it gives.
        """
        var out = List[SignalUpdate]()
        if self._find(self.vehicles_in_effect, vehicle) < 0:
            self.vehicles_in_effect.append(vehicle)
        if self.kind == STOP_SIGN:
            out.append(SignalUpdate(vehicle, RED))
            self._delay(2.0)
            self._drop_checked_in_effect()
        else:
            self._drop_checked_in_effect()
            out = self.give_way()
        return out^

    def end_effect(mut self, vehicle: ActorId):
        """A vehicle leaves an effect box.

        Args:
            vehicle: The vehicle.
        """
        var i = self._find(self.vehicles_in_effect, vehicle)
        if i >= 0:
            _ = self.vehicles_in_effect.pop(i)

    def begin_check(mut self, vehicle: ActorId) -> List[SignalUpdate]:
        """A vehicle enters a check box.

        Args:
            vehicle: The vehicle.

        Returns:
            The orders of the give-way check it starts.
        """
        if self._find(self.vehicles_in_effect, vehicle) < 0:
            var i = self._find(self.vehicles_to_check, vehicle)
            if i < 0:
                self.vehicles_to_check.append(vehicle)
                self.check_counts.append(1)
            else:
                self.check_counts[i] += 1
        return self.give_way()

    def end_check(mut self, vehicle: ActorId):
        """A vehicle leaves a check box; the sign checks after 0.5 s.

        Args:
            vehicle: The vehicle.
        """
        var i = self._find(self.vehicles_to_check, vehicle)
        if i >= 0:
            self.check_counts[i] -= 1
            if self.check_counts[i] <= 0:
                _ = self.vehicles_to_check.pop(i)
                _ = self.check_counts.pop(i)
        self._delay(0.5)

    def tick_timers(mut self, dt: Float32) -> List[SignalUpdate]:
        """Run the timers down by one tick and fire those that are due.

        Args:
            dt: The tick, in seconds.

        Returns:
            The orders of the checks that fired. A timer a check starts
            waits for the next tick.
        """
        var due = 0
        var left = List[Float32]()
        for t in self.timers:
            if t - dt <= 0:
                due += 1
            else:
                left.append(t - dt)
        self.timers = left^
        var out = List[SignalUpdate]()
        for _ in range(due):
            out.extend(self.give_way())
        return out^
