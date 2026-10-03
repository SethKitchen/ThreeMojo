# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's `road/Road`, `road/LaneSection` and `road/Lane`.

A road is a reference line, its records and a list of lane sections. A
section starts at a distance s and runs to the next section, or to the
road's end. Each section holds its lanes by id: lane 0 is the reference
line, right lanes have negative ids and left lanes positive ids, counted
outward. On a road that keeps traffic to the right the right lanes run
with the road's s and the left lanes against it; a left-hand road swaps
them. `Road.is_positive_direction` is `Lane::IsPositiveDirection`.

CARLA's lanes point at their section and road. Here a road owns its
sections and a section owns its lanes, so the lane methods that need the
road are `Road` methods that take the section's index and the lane's
index: `lane_transform` is `Lane::ComputeTransform`, `lane_corners` is
`Lane::GetCornerPositions`, `lane_width` is `Lane::GetWidth` and
`lane_is_straight` is `Lane::IsStraight`. A `LaneKey` names a lane from
anywhere in the map: its road id, its section id and its lane id.

CARLA writes a point in single precision. This port computes lane centers
in double and rounds at the public `Location` boundary. Internal nearest
queries retain the double center. The lane pose follows the derivative of
that center, including changing widths and sampled-reference tangents.
This intentionally corrects CARLA's use of a slope as an angle. Pitch
also accounts for the lane center's horizontal speed. A section with a
width-record kink does not use the two-row straight-lane mesh shortcut.
These corrections can change poses, nearest waypoints and mesh counts.

Source: CARLA 1360bb9, `LibCarla/source/carla/road/Road.cpp`,
`LaneSection.cpp`, `LaneSectionMap.h` and `Lane.cpp`.
"""

from extensions.carla.geometry import (
    ARC,
    DirectedPoint,
    LINE,
    PARAM_POLY3,
    SPIRAL,
)
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road_info import (
    InformationSet,
    JuncId,
    LANE_ANY,
    LANE_DRIVING,
    LANE_NONE,
    LANE_SIDEWALK,
    LaneId,
    LaneType,
    NO_JUNCTION,
    RoadId,
    SectionId,
    info_at,
    info_index,
)
from extensions.carla.transform import CarlaRotation, CarlaTransform
from math.vector3 import Vector3
from extensions.carla.curve_trig import (
    _curve_atan2 as atan2,
    _curve_cos as cos,
    _curve_sin as sin,
    _sincos_derivative,
)
from std.math import isfinite, sqrt
from units.si import DEGREE, Angle, Length, METER, RADIAN

# How far CARLA lifts a sidewalk's corners: six inches, in meters.
comptime SIDEWALK_HEIGHT = Float32(0.1524)
comptime _DOUBLE_MAX = 1.7976931348623157e308


@fieldwise_init
struct LaneKey(Equatable, ImplicitlyCopyable, Writable):
    """One lane, named from anywhere in the map."""

    var road_id: RoadId
    var section_id: SectionId
    var lane_id: LaneId

    def __eq__(self, other: Self) -> Bool:
        """Return True if both name the same lane.

        Args:
            other: The other key.

        Returns:
            True if the road, section and lane ids all match.
        """
        return (
            self.road_id == other.road_id
            and self.section_id == other.section_id
            and self.lane_id == other.lane_id
        )


struct Lane(Copyable, Movable):
    """One lane of a lane section, `road/Lane`."""

    var id: LaneId
    var type: LaneType
    # OpenDRIVE's `level`: True keeps the lane flat across superelevation.
    var level: Bool
    # The lane ids this lane links to in the next and previous section or
    # road, 0 for none.
    var successor: LaneId
    var predecessor: LaneId
    var info: InformationSet
    # The lanes a vehicle can drive on to, and the ones it comes from,
    # filled when the map is built.
    var next_lanes: List[LaneKey]
    var prev_lanes: List[LaneKey]
    # The section that holds the lane, and where it starts: CARLA's
    # `GetDistance`, in meters.
    var section_id: SectionId
    var distance: Float64

    def __init__(
        out self, id: LaneId, section_id: SectionId, distance: Float64
    ):
        """Create a lane with no type, no links and no records.

        Args:
            id: The lane's id.
            section_id: The id of the section that holds it.
            distance: Where that section starts, in meters.
        """
        self.id = id
        self.type = LANE_NONE
        self.level = False
        self.successor = LaneId(0)
        self.predecessor = LaneId(0)
        self.info = InformationSet()
        self.next_lanes = List[LaneKey]()
        self.prev_lanes = List[LaneKey]()
        self.section_id = section_id
        self.distance = distance


struct LaneSection(Copyable, Movable):
    """A run of a road with one set of lanes, `road/LaneSection`."""

    var id: SectionId
    # Where the section starts, in meters along the road.
    var s: Float64
    # The lanes, in order of id.
    var lanes: List[Lane]

    def __init__(out self, id: SectionId, s: Float64) raises:
        """Create an empty section.

        Args:
            id: The section's id within its road.
            s: Where it starts, in meters.

        Raises:
            Error: If the id is not valid.
        """
        if not id.is_valid():
            raise Error("Section id is not valid")
        self.id = id
        self.s = s
        self.lanes = List[Lane]()

    def lane_index(self, id: LaneId) -> Int:
        """Return where a lane sits in `lanes`, `LaneSection::GetLane`.

        Args:
            id: The lane's id.

        Returns:
            Its index, or -1 if the section has no such lane.
        """
        for i in range(len(self.lanes)):
            if self.lanes[i].id == id:
                return i
        return -1

    def contains_lane(self, id: LaneId) -> Bool:
        """Return True if the section has a lane, `ContainsLane`.

        Args:
            id: The lane's id.

        Returns:
            Whether the lane is there.
        """
        return self.lane_index(id) >= 0

    def add_lane(mut self, id: LaneId) raises -> Int:
        """Add a lane, or find it, as `std::map::emplace` does.

        Args:
            id: The lane's id.

        Returns:
            The index of the new lane, or of the lane already there.

        Raises:
            Error: If the id is not valid.
        """
        if not id.is_valid():
            raise Error("Lane id is not valid")
        var at = 0
        while at < len(self.lanes) and self.lanes[at].id.value < id.value:
            at += 1
        if at < len(self.lanes) and self.lanes[at].id == id:
            return at
        self.lanes.insert(at, Lane(id, self.id, self.s))
        return at

    def lanes_of_type(self, lane_type: LaneType) raises -> List[LaneId]:
        """Return the lanes of some types, `GetLanesOfType`.

        Args:
            lane_type: A mask of lane types.

        Returns:
            The ids of the lanes whose type shares a bit with the mask.

        Raises:
            Error: If the mask is not valid.
        """
        if not lane_type.is_valid():
            raise Error("Lane type is not valid")
        var out = List[LaneId]()
        for lane in self.lanes:
            if lane.type.matches(lane_type):
                out.append(lane.id)
        return out^


struct Road(Copyable, Movable):
    """One OpenDRIVE road, `road/Road`."""

    var id: RoadId
    var name: String
    # The length of the reference line, in meters, as the file gives it.
    var length: Float64
    var is_junction: Bool
    var junction_id: JuncId
    # True if traffic keeps to the right: OpenDRIVE's `rule="RHT"`.
    var is_rht: Bool
    # The sections, in order of s. Sections at the same s keep the order
    # they were added in, as a `std::multimap`.
    var sections: List[LaneSection]
    # The road or junction ids the file links to, 0 for none.
    var successor: RoadId
    var predecessor: RoadId
    var info: InformationSet
    # The roads a lane of this one leads to, and comes from.
    var nexts: List[RoadId]
    var prevs: List[RoadId]

    def __init__(
        out self,
        id: RoadId,
        name: String,
        length: Float64,
        junction_id: JuncId,
        predecessor: RoadId,
        successor: RoadId,
        is_rht: Bool,
    ) raises:
        """Create a road with no sections and no records, `AddRoad`.

        Args:
            id: The road's id.
            name: Its name.
            length: Its length, in meters.
            junction_id: The junction it belongs to, or `NO_JUNCTION`.
            predecessor: The road or junction before it, 0 for none.
            successor: The road or junction after it, 0 for none.
            is_rht: True if traffic keeps to the right.

        Raises:
            Error: If an id is not valid.
        """
        if not (
            id.is_valid()
            and junction_id.is_valid()
            and predecessor.is_valid()
            and successor.is_valid()
        ):
            raise Error("Road, junction or link id is not valid")
        self.id = id
        self.name = name
        self.length = length
        self.junction_id = junction_id
        self.is_junction = junction_id != NO_JUNCTION
        self.is_rht = is_rht
        self.sections = List[LaneSection]()
        self.successor = successor
        self.predecessor = predecessor
        self.info = InformationSet()
        self.nexts = List[RoadId]()
        self.prevs = List[RoadId]()

    # --- sections -------------------------------------------------------------

    def add_section(mut self, id: SectionId, s: Float64) raises -> Int:
        """Add a lane section, `MapBuilder::AddRoadSection`.

        Args:
            id: The section's id.
            s: Where it starts, in meters.

        Returns:
            The section's index in `sections`.

        Raises:
            Error: If the id is not valid.
        """
        var section = LaneSection(id, s)
        var at = 0
        while at < len(self.sections) and self.sections[at].s <= s:
            at += 1
        self.sections.insert(at, section^)
        return at

    def section_index(self, id: SectionId) raises -> Int:
        """Return where a section sits in `sections`, `GetLaneSectionById`.

        Args:
            id: The section's id.

        Returns:
            Its index.

        Raises:
            Error: If the road has no such section.
        """
        for i in range(len(self.sections)):
            if self.sections[i].id == id:
                return i
        raise Error("The road has no section with that id")

    def section_length(self, index: Int) -> Float64:
        """Return a section's length, `LaneSection::GetLength`.

        Args:
            index: The section's index in `sections`.

        Returns:
            From its start to the next section's start, or to the end of
            the road, in meters.
        """
        var s = self.sections[index].s
        return self.upper_bound(s) - s

    def upper_bound(self, s: Float64) -> Float64:
        """Return where the section at s ends, `Road::UpperBound`.

        Args:
            s: A distance along the road, in meters.

        Returns:
            The start of the first section after s, or the road's length.
        """
        for section in self.sections:
            if section.s > s:
                return section.s
        return self.length

    def sections_at(self, s: Float64) -> List[Int]:
        """Return the sections that hold at s, `GetLaneSectionsAt`.

        These are the sections that start at the greatest start at or
        before s. There is more than one only when two start together.

        Args:
            s: A distance along the road, in meters.

        Returns:
            Their indices, in order. None before the first section.
        """
        var start = -1.0
        var found = False
        for section in self.sections:
            if section.s <= s:
                start = section.s
                found = True
        var out = List[Int]()
        if not Bool(found):
            return out^
        # A section was found, so there are sections.
        for i in range(len(self.sections)):  # pragma: no branch
            if self.sections[i].s == start:
                out.append(i)
        return out^

    def lane_by_distance(
        self, s: Float64, lane_id: LaneId
    ) raises -> Tuple[Int, Int]:
        """Return the lane with an id at s, `GetLaneByDistance`.

        Args:
            s: A distance along the road, in meters.
            lane_id: The lane's id.

        Returns:
            The section's index and the lane's index in it.

        Raises:
            Error: If no section at s has the lane.
        """
        for index in self.sections_at(s):
            var lane = self.sections[index].lane_index(lane_id)
            if lane >= 0:
                return (index, lane)
        raise Error("lane not found")

    def lanes_by_distance(self, s: Float64) -> List[Tuple[Int, Int]]:
        """Return every lane at s, `GetLanesByDistance`.

        Args:
            s: A distance along the road, in meters.

        Returns:
            Each lane's section index and lane index, section by section.
        """
        var out = List[Tuple[Int, Int]]()
        for index in self.sections_at(s):
            for lane in range(len(self.sections[index].lanes)):
                out.append((index, lane))
        return out^

    def lanes_at(self, s: Float64) -> List[Tuple[Int, Int]]:
        """Return the lanes at s by id, `Road::GetLanesAt`.

        Where two sections at s both have an id, the later one wins, as a
        `std::map` assignment does.

        Args:
            s: A distance along the road, in meters.

        Returns:
            Each lane's section index and lane index, in order of id.
        """
        var out = List[Tuple[Int, Int]]()
        for index in self.sections_at(s):
            for lane in range(len(self.sections[index].lanes)):
                var id = self.sections[index].lanes[lane].id.value
                var at = 0
                while at < len(out) and self._id(out[at]) < id:
                    at += 1
                if at < len(out) and self._id(out[at]) == id:
                    out[at] = (index, lane)
                else:
                    out.insert(at, (index, lane))
        return out^

    def _id(self, lane: Tuple[Int, Int]) -> Int:
        return self.sections[lane[0]].lanes[lane[1]].id.value

    def next_lane(
        self, s: Float64, lane_id: LaneId
    ) -> Optional[Tuple[Int, Int]]:
        """Return the lane in a section after s, `Road::GetNextLane`.

        Args:
            s: A section's start, in meters.
            lane_id: The lane's id.

        Returns:
            The first section after s with the lane, and the lane's index,
            or None.
        """
        for i in range(len(self.sections)):
            if self.sections[i].s > s:
                var lane = self.sections[i].lane_index(lane_id)
                if lane >= 0:
                    return (i, lane)
        return None

    def prev_lane(
        self, s: Float64, lane_id: LaneId
    ) -> Optional[Tuple[Int, Int]]:
        """Return the lane in a section before s, `Road::GetPrevLane`.

        Args:
            s: A section's start, in meters.
            lane_id: The lane's id.

        Returns:
            The last section before s with the lane, and the lane's index,
            or None.
        """
        for i in range(len(self.sections) - 1, -1, -1):
            if self.sections[i].s < s:
                var lane = self.sections[i].lane_index(lane_id)
                if lane >= 0:
                    return (i, lane)
        return None

    def start_section(self, lane_id: LaneId) -> Int:
        """Return the first section with a lane, `GetStartSection`.

        Args:
            lane_id: The lane's id.

        Returns:
            Its index, or -1 if no section has the lane.
        """
        for i in range(len(self.sections)):
            if self.sections[i].contains_lane(lane_id):
                return i
        return -1

    def end_section(self, lane_id: LaneId) -> Int:
        """Return the last section with a lane, `GetEndSection`.

        Args:
            lane_id: The lane's id.

        Returns:
            Its index, or -1 if no section has the lane.
        """
        for i in range(len(self.sections) - 1, -1, -1):
            if self.sections[i].contains_lane(lane_id):
                return i
        return -1

    # --- the reference line ---------------------------------------------------

    def elevation_on(self, s: Float64) raises -> CubicPolynomial:
        """Return the elevation cubic at s, `Road::GetElevationOn`.

        Args:
            s: A distance along the road, in meters.

        Returns:
            The cubic of the elevation record that holds at s.

        Raises:
            Error: If no elevation record starts at or before s.
        """
        var found = info_at(self.info.elevations, s)
        if not Bool(found):
            raise Error("failed to find road elevation.")
        return found.value().polynomial

    def directed_point(self, s: Float64) raises -> DirectedPoint:
        """Return lane 0 at s, `Road::GetDirectedPointIn`.

        The lane offset moves the point sideways. The elevation sets z and
        the pitch. CARLA reads the elevation at s as given, and the plan
        view and the lane offset at s clamped to the road.

        Args:
            s: A distance along the road, in meters.

        Returns:
            The point, its heading and its pitch, in OpenDRIVE's frame.

        Raises:
            Error: If no geometry or no elevation record holds at s.
        """
        var clamped = min(max(s, 0.0), self.length)
        var offset = Float32(0)
        var lane_offset = info_at(self.info.lane_offsets, clamped)
        if Bool(lane_offset):
            offset = Float32(lane_offset.value().polynomial.evaluate(clamped))
        var point = self._plan_point(clamped)
        point.apply_lateral_offset(Length(-offset, METER))
        return self._elevate(point, s)

    def directed_point_no_lane_offset(self, s: Float64) raises -> DirectedPoint:
        """Return the reference line at s, `GetDirectedPointInNoLaneOffset`.

        Args:
            s: A distance along the road, in meters.

        Returns:
            The point, its heading and its pitch, with no lane offset.

        Raises:
            Error: If no geometry or no elevation record holds at s.
        """
        var clamped = min(max(s, 0.0), self.length)
        return self._elevate(self._plan_point(clamped), s)

    def _plan_point(self, s: Float64) raises -> DirectedPoint:
        var at = info_index(self.info.geometries, s)
        if at < 0:
            raise Error("The road has no geometry at that s")
        ref record = self.info.geometries[at]
        return record.geometry.pos_at(s - record.s)

    def _elevate(
        self, var point: DirectedPoint, s: Float64
    ) raises -> DirectedPoint:
        var elevation = self.elevation_on(s)
        point.z = Float64(Float32(elevation.evaluate(s)))
        point.pitch = elevation.tangent(s)
        return point

    def nearest_point(self, location: Vector3) -> Tuple[Float64, Float64]:
        """Return CARLA's `Road::GetNearestPoint`.

        CARLA asks every geometry for its `DistanceTo`, keeps the nearest,
        and adds up the lengths of the geometries before it.

        Args:
            location: The point, in meters.

        Returns:
            The distance along the nearest geometry plus the lengths
            before it, and the distance to that geometry, in meters. The
            second is the largest double if the road has no geometry.
        """
        var best_s = 0.0
        var best_d = _DOUBLE_MAX
        var nearest = len(self.info.geometries)
        for i in range(len(self.info.geometries)):
            var d = self.info.geometries[i].geometry.distance_to(location)
            if Float64(d[1]) < best_d:
                best_s = Float64(d[0])
                best_d = Float64(d[1])
                nearest = i
        for i in range(nearest):
            best_s += self.info.geometries[i].geometry.length
        return (best_s, best_d)

    def nearest_lane(
        self, s: Float64, location: Vector3, lane_type: LaneType = LANE_ANY
    ) raises -> Tuple[Optional[LaneKey], Float64]:
        """Return the lane nearest a point at s, `Road::GetNearestLane`.

        CARLA walks out from the reference line to the right, then to the
        left, and stops on each side once a lane center is farther than
        the best so far. It measures in OpenDRIVE's frame.

        Args:
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
        var lanes = self.lanes_at(s)
        var zero = self.directed_point(s)
        var best: Optional[LaneKey] = None
        var best_d = _DOUBLE_MAX
        # Two sides, always.
        for side in range(2):  # pragma: no branch
            var current = zero
            var order = List[Tuple[Int, Int]]()
            for i in range(len(lanes) - 1, -1, -1):
                if self._id(lanes[i]) < 0 and side == 0:
                    order.append(lanes[i])
            for i in range(len(lanes)):
                if self._id(lanes[i]) >= 1 and side == 1:
                    order.append(lanes[i])
            for pair in order:
                ref lane = self.sections[pair[0]].lanes[pair[1]]
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
                    best = LaneKey(self.id, self.sections[pair[0]].id, lane.id)
                    best_d = d
                current.apply_lateral_offset(Length(half, METER))
        return (best, best_d)

    # --- lanes ----------------------------------------------------------------

    def is_positive_direction(self, lane_id: LaneId) -> Bool:
        """Return True if a lane runs with s, `Lane::IsPositiveDirection`.

        Args:
            lane_id: The lane's id.

        Returns:
            True for lane 0 and the right lanes of a right-hand road, and
            for lane 0 and the left lanes of a left-hand one.
        """
        if self.is_rht:
            return lane_id.value <= 0
        return lane_id.value >= 0

    def lane_length(self, section: Int) -> Float64:
        """Return a lane's length, `Lane::GetLength`: its section's.

        Args:
            section: The section's index.

        Returns:
            The length, in meters.
        """
        return self.section_length(section)

    def lane_width(self, section: Int, lane: Int, s: Float64) raises -> Float64:
        """Return a lane's width at s, `Lane::GetWidth`.

        Args:
            section: The section's index.
            lane: The lane's index in the section.
            s: A distance along the road, in meters.

        Returns:
            The width record's value at s, in meters, or 0 if no width
            record holds at s.

        Raises:
            Error: If s is past the end of the road.
        """
        if s > self.length:
            raise Error("s is past the end of the road")
        var width = info_at(self.sections[section].lanes[lane].info.widths, s)
        if Bool(width):
            return width.value().polynomial.evaluate(s)
        return 0.0

    def lane_is_straight(self, section: Int) raises -> Bool:
        """Return True if a lane is one straight run, `Lane::IsStraight`.

        Every center must be affine in road s on one line record. Road
        offsets and accumulated lane widths count, as does elevation.
        Multiple records are conservatively treated as curved.

        Args:
            section: The section's index.

        Returns:
            Whether the section's lanes are straight.

        Raises:
            Error: If no geometry holds at the section's start.
        """
        var start = self.sections[section].s
        var at = info_index(self.info.geometries, start)
        if at < 0:
            raise Error("The road has no geometry at that s")
        ref record = self.info.geometries[at]
        if record.geometry.kind != LINE:
            return False
        # CARLA also tests that the section starts after the record; the
        # record found is the last to start at or before it, so it does.
        if (
            start + self.section_length(section)
            > record.s + record.geometry.length
        ):
            return False
        if len(self.info.elevations) > 1 or len(self.info.lane_offsets) > 1:
            return False
        for elevation in self.info.elevations:
            if elevation.polynomial.c != 0.0 or elevation.polynomial.d != 0.0:
                return False
        for offset in self.info.lane_offsets:
            if offset.polynomial.c != 0.0 or offset.polynomial.d != 0.0:
                return False
        for lane in self.sections[section].lanes:
            if len(lane.info.widths) > 1:
                return False
            for width in lane.info.widths:
                if width.polynomial.c != 0.0 or width.polynomial.d != 0.0:
                    return False
        return True

    def _total_width(
        self, section: Int, s: Float64, lane_id: LaneId
    ) raises -> Tuple[Float64, Float64]:
        # `ComputeTotalLaneWidth`: the offset of the lane's center from
        # lane 0 and its rate of change. Plus is to the right.
        ref lanes = self.sections[section].lanes
        var negative = lane_id.value < 0
        var dist = 0.0
        var tangent = 0.0
        var sign = 1.0 if negative else -1.0
        # Visit the same inner-to-outer order without allocating a list.
        # The section holds the lane, so this loop reaches it and breaks.
        for position in range(len(lanes)):  # pragma: no branch
            var i = len(lanes) - 1 - position if negative else position
            if negative:
                if lanes[i].id.value >= 0:
                    continue
            elif lanes[i].id.value < 1:
                continue
            var width = info_at(lanes[i].info.widths, s)
            if not Bool(width):
                raise Error("A lane has no width record at s")
            var w = width.value().polynomial.evaluate(s)
            var t = width.value().polynomial.tangent(s)
            if lanes[i].id != lane_id:
                dist += sign * w
                tangent += sign * t
            else:
                dist += sign * w * 0.5
                tangent += sign * t * 0.5
                break
        return (dist, tangent)

    def _check_lane(self, section: Int, lane: Int) raises:
        if section < 0 or section >= len(self.sections):
            raise Error("The road has no section at that index")
        if lane < 0 or lane >= len(self.sections[section].lanes):
            raise Error("The section has no lane at that index")

    def _lane_record_boundaries(self, section: Int) -> List[Float64]:
        # Each polynomial and each sampled reference interval is smooth only
        # between its own boundaries. Do not join across a discontinuity.
        var result = List[Float64]()
        for record in self.info.geometries:
            result.append(record.s)
            for sample in record.geometry.samples:
                result.append(record.s + sample.s)
        for record in self.info.elevations:
            result.append(record.s)
        for record in self.info.lane_offsets:
            result.append(record.s)
        for lane in self.sections[section].lanes:
            for record in lane.info.widths:
                result.append(record.s)
        return result^

    def _lane_turn_bound(self, first: Float64, second: Float64) -> Float64:
        # _add_segment splits at geometry boundaries before this call.
        var at = info_index(self.info.geometries, min(first, second))
        ref geometry = self.info.geometries[at].geometry
        return max(
            abs(geometry.curvature_start), abs(geometry.curvature_end)
        ) * abs(second - first)

    def _plan_derivative(
        self, s: Float64
    ) raises -> Tuple[Float64, Float64, Float64]:
        var at = info_index(self.info.geometries, s)
        ref record = self.info.geometries[at]
        return record.geometry._derivative_at(s - record.s)

    def _lane_point(
        self, section: Int, lane: Int, s: Float64
    ) raises -> DirectedPoint:
        # Keep the center in double precision until the public transform.
        var lane_id = self.sections[section].lanes[lane].id
        var offset = 0.0
        if lane_id.value != 0:
            offset = self._total_width(section, s, lane_id)[0]
        var lane_offset = info_at(self.info.lane_offsets, s)
        if not Bool(lane_offset):
            raise Error("The road has no lane offset record at s")
        offset -= lane_offset.value().polynomial.evaluate(s)
        return self._offset_lane_point(s, offset)

    def _offset_lane_point(
        self, s: Float64, offset: Float64
    ) raises -> DirectedPoint:
        var point = self._plan_point(s)
        var at = info_index(self.info.geometries, s)
        ref record = self.info.geometries[at]
        if record.geometry.kind == ARC:
            var d = min(max(s - record.s, 0.0), record.geometry.length)
            point = record.geometry._arc_offset(d, offset)
        else:
            point.x += offset * sin(point.tangent)
            point.y -= offset * cos(point.tangent)
        var elevation = self.elevation_on(s)
        point.z = elevation.evaluate(s)
        point.pitch = elevation.tangent(s)
        return point

    def _lane_center(
        self, section: Int, lane: Int, s: Float64
    ) raises -> Array[Float64, 3]:
        # Internal CARLA-frame center. Public transforms narrow only at their
        # documented storage boundary; query predicates keep these coordinates.
        var point = self._lane_point(section, lane, s)
        return [point.x, -point.y, point.z]

    def _lane_distance_squared(
        self, section: Int, lane: Int, s: Float64, location: Vector3
    ) raises -> Float64:
        var point = self._lane_point(section, lane, s)
        var dx = point.x - Float64(location.x)
        var dy = -point.y - Float64(location.y)
        var dz = point.z - Float64(location.z)
        return dx * dx + dy * dy + dz * dz

    def _lane_distance_derivative(
        self,
        section: Int,
        lane: Int,
        low: Float64,
        high: Float64,
        location: Vector3,
    ) raises -> List[Float64]:
        # A line-reference center is cubic between active record boundaries.
        # Return half the derivative of squared distance in t=(s-low)/span.
        # Empty means the interval cannot use this polynomial certificate.
        var at = info_index(self.info.geometries, low)
        if high <= low or at < 0:
            return List[Float64]()
        ref record = self.info.geometries[at]
        if record.geometry.kind != LINE:
            return List[Float64]()
        if high > record.s + record.geometry.length:
            return List[Float64]()
        if info_index(self.info.geometries, high) != at:
            return List[Float64]()
        if info_index(self.info.elevations, low) != info_index(
            self.info.elevations, high
        ):
            return List[Float64]()
        if info_index(self.info.lane_offsets, low) != info_index(
            self.info.lane_offsets, high
        ):
            return List[Float64]()
        var offset = info_at(self.info.lane_offsets, low).value().polynomial
        var q1 = -offset.tangent(low)
        var q2 = -(offset.c + 3.0 * low * offset.d)
        var q3 = -offset.d
        ref lanes = self.sections[section].lanes
        var id = lanes[lane].id
        var negative = id.value < 0
        var sign = 1.0 if negative else -1.0
        if id.value != 0:
            var done = False
            var position = 0
            while position < len(lanes):
                var i = len(lanes) - 1 - position if negative else position
                position += 1
                if done:
                    continue
                if negative:
                    if lanes[i].id.value >= 0:
                        continue
                elif lanes[i].id.value < 1:
                    continue
                ref widths = lanes[i].info.widths
                var width_at = info_index(widths, low)
                if info_index(widths, high) != width_at:
                    return List[Float64]()
                var width = widths[width_at].polynomial
                var factor = sign * (0.5 if lanes[i].id == id else 1.0)
                q1 += factor * width.tangent(low)
                q2 += factor * (width.c + 3.0 * low * width.d)
                q3 += factor * width.d
                done = lanes[i].id == id
        var point = self._lane_point(section, lane, low)
        var dx = point.x - Float64(location.x)
        var dy = point.y + Float64(location.y)
        var heading = record.geometry.heading
        var c = cos(heading)
        var sn = sin(heading)
        var span = high - low
        var elevation = self.elevation_on(low)
        # Use world-coordinate coefficients of the actual scalar evaluator.
        # A polynomial sine/cosine pair need not satisfy C*C+S*S == 1.
        # Translate before scaling and do not terminate by relative road s.
        var coordinates: List[Float64] = [
            dx,
            span * c + q1 * span * sn,
            q2 * span * span * sn,
            q3 * span * span * span * sn,
            dy,
            span * sn - q1 * span * c,
            -q2 * span * span * c,
            -q3 * span * span * span * c,
            point.z - Float64(location.z),
            elevation.tangent(low) * span,
            (elevation.c + 3.0 * low * elevation.d) * span * span,
            elevation.d * span * span * span,
        ]
        var scale = span
        var coordinate = 0
        while coordinate < len(coordinates):
            var value = coordinates[coordinate]
            coordinate += 1
            if not isfinite(value):
                return List[Float64]()
            scale = max(scale, abs(value))
        var polynomial = List[Float64](length=6, fill=0.0)
        var axis = 0
        while axis < 3:
            var i = 0
            while i < 4:
                var j = 1
                while j < 4:
                    polynomial[i + j - 1] += (
                        coordinates[4 * axis + i]
                        / scale
                        * (coordinates[4 * axis + j] / scale)
                        * Float64(j)
                    )
                    j += 1
                i += 1
            axis += 1
        return polynomial^

    def lane_transform(
        self, section: Int, lane: Int, s: Float64
    ) raises -> CarlaTransform:
        """Return a lane's center at s in CARLA's frame, facing along it.

        The heading and pitch follow the actual center derivative. This
        corrects CARLA's use of the lateral derivative as an angle.
        A lane against s turns its yaw by 180 degrees and reverses pitch.
        A zero horizontal derivative keeps the reference heading. A
        stationary center has zero pitch; a vertical tangent has 90 degrees.

        Args:
            section: The section's index.
            lane: The lane's index in the section.
            s: A distance along the road, in meters.

        Returns:
            The transform a vehicle in that lane would have.

        Raises:
            Error: If the indices name no lane, s is off the road, or a
                record the transform needs is missing.
        """
        self._check_lane(section, lane)
        if s > self.length or s < 0.0:
            raise Error("s is off the road")
        var lane_id = self.sections[section].lanes[lane].id
        var offset = 0.0
        var slope = 0.0
        if lane_id.value != 0:
            var total = self._total_width(section, s, lane_id)
            offset = total[0]
            slope = total[1]
        var lane_offset = info_at(self.info.lane_offsets, s)
        if not Bool(lane_offset):
            raise Error("The road has no lane offset record at s")
        offset -= lane_offset.value().polynomial.evaluate(s)
        slope -= lane_offset.value().polynomial.tangent(s)
        var point = self._offset_lane_point(s, offset)
        var differential = self._plan_derivative(s)
        var c = cos(point.tangent)
        var sn = sin(point.tangent)
        var normal = _sincos_derivative(point.tangent)
        var dx = differential[0] + slope * sn + offset * differential[2] * normal[0]
        var dy = differential[1] - slope * c - offset * differential[2] * normal[1]
        var geometry_at = info_index(self.info.geometries, s)
        ref geometry = self.info.geometries[geometry_at].geometry
        if geometry.kind == ARC:
            var distance = s - self.info.geometries[geometry_at].s
            var derivative = geometry._arc_offset_derivative(
                min(max(distance, 0.0), geometry.length), offset, slope,
                distance >= 0.0 and distance <= geometry.length,
            )
            dx = derivative[0]
            dy = derivative[1]
        var magnitude = max(abs(dx), abs(dy))
        var horizontal = 0.0
        if magnitude > 0.0:
            horizontal = magnitude * sqrt((dx / magnitude) * (dx / magnitude) + (dy / magnitude) * (dy / magnitude))
        var yaw = Float32(-point.tangent) * _TO_DEGREES
        if horizontal > 0.0:
            # Keep the reference heading's winding, while correcting its
            # direction by the actual derivative in the reference frame.
            yaw = (
                Float32(
                    -point.tangent + atan2(
                        (dx / magnitude) * sn - (dy / magnitude) * c,
                        (dx / magnitude) * c + (dy / magnitude) * sn,
                    )
                )
                * _TO_DEGREES
            )
        var pitch = -Float32(atan2(point.pitch, horizontal)) * _TO_DEGREES
        if not self.is_positive_direction(lane_id):
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

    def lane_corners(
        self,
        section: Int,
        lane: Int,
        s: Float64,
        extra_width: Float32 = 0.0,
    ) raises -> Tuple[Vector3, Vector3]:
        """Return a lane's two edges at s, `Lane::GetCornerPositions`.

        A driving lane of a junction road widens by `extra_width` on each
        side. A sidewalk's edges rise by `SIDEWALK_HEIGHT`.

        Args:
            section: The section's index.
            lane: The lane's index in the section.
            s: A distance along the road, in meters. It is clamped.
            extra_width: How far to widen a junction's driving lane, in
                meters.

        Returns:
            The edge at the lane's offset plus half its width, then the
            edge at minus half, in CARLA's frame. For a right lane of a
            right-hand road the first is the outer edge.

        Raises:
            Error: If the indices name no lane, or a record is missing.
        """
        var offsets = self.lane_edge_offsets(section, lane, s, extra_width)
        var at = min(max(s, 0.0), self.length)
        var right = self.directed_point(at)
        var left = right
        right.apply_lateral_offset(Length(offsets[0], METER))
        left.apply_lateral_offset(Length(offsets[1], METER))
        var lift = Float32(0)
        if self.sections[section].lanes[lane].type == LANE_SIDEWALK:
            lift = SIDEWALK_HEIGHT
        return (
            Vector3(
                Float32(right.x), Float32(-right.y), Float32(right.z) + lift
            ),
            Vector3(Float32(left.x), Float32(-left.y), Float32(left.z) + lift),
        )

    def lane_edge_offsets(
        self,
        section: Int,
        lane: Int,
        s: Float64,
        extra_width: Float32 = 0.0,
    ) raises -> Tuple[Float32, Float32]:
        """Return how far a lane's two edges sit from lane 0 at s.

        These are the offsets `lane_corners` moves lane 0 by: the lane's
        center offset plus and minus half its width, widened as there.

        Args:
            section: The section's index.
            lane: The lane's index in the section.
            s: A distance along the road, in meters. It is clamped.
            extra_width: How far to widen a junction's driving lane, in
                meters.

        Returns:
            The offsets of the first and the second edge, in meters. Plus
            is to the right of the road's direction.

        Raises:
            Error: If the indices name no lane, or a record is missing.
        """
        self._check_lane(section, lane)
        var at = min(max(s, 0.0), self.length)
        ref the_lane = self.sections[section].lanes[lane]
        var t_offset = Float32(0)
        if the_lane.id.value != 0:
            t_offset = Float32(self._total_width(section, at, the_lane.id)[0])
        var half = Float32(self.lane_width(section, lane, at)) / 2.0
        if (
            extra_width != 0.0
            and self.is_junction
            and the_lane.type == LANE_DRIVING
        ):
            half += extra_width
        return (t_offset + half, t_offset - half)


# `Math::ToDegrees<float>`: 180 over pi, both floats.
comptime _TO_DEGREES = Float32(180.0) / Float32(3.14159265358979323846)
