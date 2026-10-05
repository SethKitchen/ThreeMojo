# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Same-build known-waypoint transform benchmark for issue #485.

The complete baseline method is copied from 0f58bc1. Geometry position
helpers and center-coordinate arithmetic are shared and unchanged.
"""

from extensions.carla.geometry import (
    ARC,
    LINE,
    PARAM_POLY3,
    POLY3,
    SPIRAL,
    RoadGeometryKind,
)
from extensions.carla.road import Road
from extensions.carla.road_info import info_at
from extensions.carla.transform import CarlaRotation, CarlaTransform
from std.math import atan
from std.time import perf_counter_ns
from tests.test_carla_lane_orientation import _road
from units.si import DEGREE, Angle, Length, METER

comptime _TO_DEGREES = Float32(180.0) / Float32(3.14159265358979323846)


def _base_lane_transform(
    road: Road, section: Int, lane: Int, s: Float64
) raises -> CarlaTransform:
    """Return a lane's center at s in CARLA's frame, facing along it.

    This follows `Lane::ComputeTransform`, except that the pitch is
    the negative arctangent of the elevation grade. That matches the
    corrected rotation convention and makes rising roads face uphill.
    A lane against s turns its yaw by 180 degrees and reverses pitch.

    Args:
        road: The road that owns the lane.
        section: The section's index.
        lane: The lane's index in the section.
        s: A distance along the road, in meters.

    Returns:
        The transform a vehicle in that lane would have.

    Raises:
        Error: If the indices name no lane, s is off the road, or a
            record the transform needs is missing.
    """
    road._check_lane(section, lane)
    if s > road.length or s < 0.0:
        raise Error("s is off the road")
    var lane_id = road.sections[section].lanes[lane].id
    var t_offset = Float32(0)
    var lane_tangent = Float32(0)
    if lane_id.value != 0:
        var total = road._total_width(section, s, lane_id)
        t_offset = Float32(total[0])
        lane_tangent = Float32(total[1])
    var lane_offset = info_at(road.info.lane_offsets, s)
    if not Bool(lane_offset):
        raise Error("The road has no lane offset record at s")
    lane_tangent -= Float32(lane_offset.value().polynomial.tangent(s))
    var point = road.directed_point(s)
    point.apply_lateral_offset(Length(t_offset, METER))
    point.tangent -= Float64(lane_tangent)
    # Rotation's positive pitch points down. The elevation derivative is
    # a grade, not an angle; use its arctangent before reversing traffic.
    var pitch = -Float32(atan(point.pitch)) * _TO_DEGREES
    var yaw = Float32(-point.tangent) * _TO_DEGREES
    if not road.is_positive_direction(lane_id):
        yaw += 180.0
        pitch = 360.0 - pitch
    return CarlaTransform(
        Length(Float32(point.x), METER),
        Length(Float32(-point.y), METER),
        Length(Float32(point.z), METER),
        CarlaRotation(
            Angle(pitch, DEGREE), Angle(yaw, DEGREE), Angle(0.0, DEGREE)
        ),
    )


@no_inline
def _measure[
    corrected: Bool
](road: Road, count: Int) raises -> Tuple[Float64, Float64]:
    var checksum = 0.0
    var start = perf_counter_ns()
    for i in range(count):
        var at = Float64(i % 101) * 0.19
        var lane = i % 5
        comptime if corrected:
            var pose = road.lane_transform(0, lane, at)
            checksum += (
                Float64(pose.location.x)
                + Float64(pose.location.y)
                + Float64(pose.location.z)
                + Float64(pose.rotation.pitch)
                + Float64(pose.rotation.yaw)
                + Float64(pose.rotation.roll)
            )
        else:
            var pose = _base_lane_transform(road, 0, lane, at)
            checksum += (
                Float64(pose.location.x)
                + Float64(pose.location.y)
                + Float64(pose.location.z)
                + Float64(pose.rotation.pitch)
                + Float64(pose.rotation.yaw)
                + Float64(pose.rotation.roll)
            )
    return (Float64(perf_counter_ns() - start), checksum)


def _bench(kind: RoadGeometryKind) raises:
    var road = _road(kind)
    for lane in range(5):
        for i in range(101):
            var at = Float64(i) * 0.19
            var old = _base_lane_transform(road, 0, lane, at)
            var new = road.lane_transform(0, lane, at)
            if old.location != new.location:
                raise Error("Existing center arithmetic changed")
    var warm = _measure[False](road, 100)[1] + _measure[True](road, 100)[1]
    for sample in range(6):
        var old: Tuple[Float64, Float64]
        var new: Tuple[Float64, Float64]
        if sample % 2 == 0:
            old = _measure[False](road, 5000)
            new = _measure[True](road, 5000)
        else:
            new = _measure[True](road, 5000)
            old = _measure[False](road, 5000)
        print(
            "ORIENTATION_BENCH",
            kind.value,
            sample,
            5000,
            old[0],
            new[0],
            old[1] + new[1] + warm,
        )


def main() raises:
    for kind in [LINE, ARC, SPIRAL, POLY3, PARAM_POLY3]:
        _bench(kind)
