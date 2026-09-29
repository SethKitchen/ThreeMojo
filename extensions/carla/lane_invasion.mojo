# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's lane invasion sensor, `sensor.other.lane_invasion`.

The source is `LibCarla/source/carla/client/LaneInvasionSensor.cpp` and
`sensor/data/LaneInvasionEvent.h`. The sensor runs on the client, once
each world tick, and reads the snapshot:

1. It places the four bottom corners of the parent vehicle's box: the
   box's extent turned by the vehicle's yaw only, around the vehicle's
   location plus the box's center. CARLA does not turn the center.
2. On the first tick it only keeps them.
3. If any corner moved less than ten `Float32` epsilons, it stops there,
   and keeps the old corners.
4. Otherwise it keeps the new corners and asks the map for the markings
   that each corner crossed, `Map.calculate_crossed_lanes`, corner by
   corner.
5. It reports an event when at least one marking was crossed. The event's
   transform is the parent's.
"""

from extensions.carla.bounding_box import BoundingBox
from extensions.carla.map import Map
from extensions.carla.road_info import LaneMarking
from extensions.carla.transform import CarlaTransform
from math.vector3 import Vector3
from std.math import cos, sin

# `10 * std::numeric_limits<float>::epsilon()`.
comptime _THRESHOLD = Float32(10.0) * Float32(1.1920928955078125e-07)
comptime _TO_RADIANS = Float32(3.14159265358979323846) / Float32(180.0)


def _rotate(yaw: Float32, v: Vector3) -> Vector3:
    """`Rotate`: turn about z by a yaw in degrees."""
    var y = yaw * _TO_RADIANS
    var c = cos(y)
    var s = sin(y)
    return Vector3(c * v.x - s * v.y, s * v.x + c * v.y, v.z)


def box_corners(transform: CarlaTransform, box: BoundingBox) -> List[Vector3]:
    """Return the four bottom corners a lane invasion sensor follows,
    `MakeBounds`.

    Args:
        transform: The vehicle's pose.
        box: The vehicle's box, in its own frame.

    Returns:
        Front right, back right, front left and back left: (+x, +y),
        (-x, +y), (+x, -y) and (-x, -y) of the extent, at z zero, turned
        by the yaw and moved to the location plus the box's center.
    """
    var at = transform.location + box.location
    var yaw = transform.rotation.yaw
    var e = box.extent
    return [
        at + _rotate(yaw, Vector3(e.x, e.y, 0)),
        at + _rotate(yaw, Vector3(-e.x, e.y, 0)),
        at + _rotate(yaw, Vector3(e.x, -e.y, 0)),
        at + _rotate(yaw, Vector3(-e.x, -e.y, 0)),
    ]


struct LaneInvasionEvent(Copyable, Movable):
    """The markings a vehicle crossed in one tick, `LaneInvasionEvent`."""

    var frame: Int
    var timestamp: Float64
    # The parent vehicle's pose.
    var transform: CarlaTransform
    var crossed_lane_markings: List[LaneMarking]

    def __init__(
        out self,
        frame: Int,
        timestamp: Float64,
        transform: CarlaTransform,
        var crossed_lane_markings: List[LaneMarking],
    ):
        """Create an event.

        Args:
            frame: The snapshot's frame.
            timestamp: The snapshot's elapsed seconds.
            transform: The parent's pose.
            crossed_lane_markings: What was crossed, corner by corner.
        """
        self.frame = frame
        self.timestamp = timestamp
        self.transform = transform
        self.crossed_lane_markings = crossed_lane_markings^


struct LaneInvasionSensor(Copyable, Movable):
    """The corners of the last tick, `LaneInvasionCallback`."""

    var box: BoundingBox
    var has_corners: Bool
    var frame: Int
    var corners: List[Vector3]

    def __init__(out self, box: BoundingBox):
        """Create a sensor for a vehicle.

        Args:
            box: The vehicle's box, in its own frame.
        """
        self.box = box
        self.has_corners = False
        self.frame = 0
        self.corners = List[Vector3]()

    def tick(
        mut self,
        map: Map,
        frame: Int,
        timestamp: Float64,
        transform: CarlaTransform,
    ) raises -> Optional[LaneInvasionEvent]:
        """Check one snapshot, `LaneInvasionCallback::Tick`.

        Args:
            map: The world's map.
            frame: The snapshot's frame.
            timestamp: The snapshot's elapsed seconds.
            transform: The parent vehicle's pose in the snapshot.

        Returns:
            The event, or None.

        Raises:
            Error: If a map query fails.
        """
        var next = box_corners(transform, self.box)
        if not self.has_corners:
            self.has_corners = True
            self.frame = frame
            self.corners = next^
            return None
        # There are always four corners.
        for i in range(4):  # pragma: no branch
            if (next[i] - self.corners[i]).length() < _THRESHOLD:
                return None
        if self.frame >= frame:
            return None
        var previous = self.corners.copy()
        self.frame = frame
        self.corners = next.copy()
        var crossed = List[LaneMarking]()
        # There are always four corners.
        for i in range(4):  # pragma: no branch
            crossed.extend(map.calculate_crossed_lanes(previous[i], next[i]))
        if len(crossed) == 0:
            return None
        return LaneInvasionEvent(frame, timestamp, transform, crossed^)
