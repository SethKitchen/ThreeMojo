# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Compare fixed-s methods in one build with unchanged ordinary geometry.

The baseline method is copied from e53600eb4b0551bbe9900ea0e8b7151e49553a2d.
It uses this build's common geometry helpers, which this change does not edit.
This is a same-build method comparison, not a historical binary benchmark.
"""

from extensions.carla.road import LaneKey, Road
from extensions.carla.road_info import LANE_ANY, LANE_DRIVING, LaneType, info_at
from math.vector3 import Vector3
from std.time import perf_counter_ns
from tests.test_carla_road_fixed_s import _lane, _road
from units.si import Length, METER

comptime _DOUBLE_MAX = 1.7976931348623157e308


def _base_nearest_lane(
    road: Road, s: Float64, location: Vector3, lane_type: LaneType = LANE_ANY
) raises -> Tuple[Optional[LaneKey], Float64]:
    """Return the lane nearest a point at s, `Road::GetNearestLane`.

    CARLA walks out from the reference line to the right, then to the
    left, and stops on each side once a lane center is farther than
    the best so far. It measures in OpenDRIVE's frame.

    Args:
        road: The road to query.
        s: A distance along the road, in meters.
        location: The point, in meters.
        lane_type: The lane types that may be the answer.

    Returns:
        The nearest lane of those types, or None, and its distance.

    Raises:
        Error: If the mask is not valid, or a lane at s has no width
            record there.
    """
    if not lane_type.is_valid():
        raise Error("Lane type is not valid")
    var lanes = road.lanes_at(s)
    var zero = road.directed_point(s)
    var best: Optional[LaneKey] = None
    var best_d = _DOUBLE_MAX
    # Two sides, always.
    for side in range(2):  # pragma: no branch
        var current = zero
        var order = List[Tuple[Int, Int]]()
        for i in range(len(lanes) - 1, -1, -1):
            if road._id(lanes[i]) < 0 and side == 0:
                order.append(lanes[i])
        for i in range(len(lanes)):
            if road._id(lanes[i]) >= 1 and side == 1:
                order.append(lanes[i])
        for pair in order:
            ref lane = road.sections[pair[0]].lanes[pair[1]]
            var width = info_at(lane.info.widths, s)
            if not Bool(width):
                raise Error("A lane has no width record at s")
            var half = Float32(width.value().polynomial.evaluate(s)) * 0.5
            if side == 1:
                half = -half
            current.apply_lateral_offset(Length(half, METER))
            var d = Float64(
                Vector3(
                    Float32(current.x),
                    Float32(current.y),
                    Float32(current.z),
                ).distance_to(location)
            )
            if d > best_d:
                break
            if lane.type.matches(lane_type):
                best = LaneKey(road.id, road.sections[pair[0]].id, lane.id)
                best_d = d
            current.apply_lateral_offset(Length(half, METER))
    return (best, best_d)


@no_inline
def _measure[
    wide: Bool
](road: Road, repetitions: Int) raises -> Tuple[Float64, Float64]:
    var checksum = Float64(0)
    var start = perf_counter_ns()
    for i in range(repetitions):
        var query = Vector3(4.75, Float32(i % 101 - 50) * 0.25, 0.5)
        comptime if wide:
            checksum += road.nearest_lane(5, query, LANE_DRIVING)[1]
        else:
            checksum += _base_nearest_lane(road, 5, query, LANE_DRIVING)[1]
    return (Float64(perf_counter_ns() - start), checksum)


def _bench(lanes_per_side: Int, heading: Float64, repetitions: Int) raises:
    var road = _road(width=3.5)
    road.info.geometries[0].geometry.heading = heading
    for id in range(2, lanes_per_side + 1):
        _lane(road, 0, id, 3.5)
        _lane(road, 0, -id, 3.5)
    var max_difference = Float64(0)
    var changed_distances = 0
    for i in range(101):
        var query = Vector3(4.75, Float32(i - 50) * 0.25, 0.5)
        var old = _base_nearest_lane(road, 5, query, LANE_DRIVING)
        var new = road.nearest_lane(5, query, LANE_DRIVING)
        if old[0].value() != new[0].value():
            raise Error("Ordinary lane identity changed")
        max_difference = max(max_difference, abs(old[1] - new[1]))
        if old[1] != new[1]:
            changed_distances += 1
    # Warm both paths before each group. Alternate which path runs first.
    var warm = _measure[False](road, 100)[1] + _measure[True](road, 100)[1]
    for sample in range(8):
        var old: Tuple[Float64, Float64]
        var new: Tuple[Float64, Float64]
        if sample % 2 == 0:
            old = _measure[False](road, repetitions)
            new = _measure[True](road, repetitions)
        else:
            new = _measure[True](road, repetitions)
            old = _measure[False](road, repetitions)
        print(
            "FIXED_S_BENCH",
            lanes_per_side,
            heading,
            sample,
            repetitions,
            old[0],
            new[0],
            changed_distances,
            max_difference,
            old[1] + new[1] + warm,
        )


def main() raises:
    for heading in [Float64(0), Float64(0.37)]:
        for count in [1, 2, 4, 16, 64]:
            _bench(count, heading, 1000)
