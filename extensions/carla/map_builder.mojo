# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's `road/MapBuilder`: the calls that assemble a `Map`.

The OpenDRIVE parser reads a file in ten passes and calls a builder
method for each thing it finds: a road, a lane section, a lane, a
geometry, a width record, a signal. `build` then joins the pieces:

1. It links each lane to the lanes it leads to, within its road, onto the
   next road, or through a junction (`CreatePointersBetweenRoadSegments`).
2. It drops signal references whose every validity is lane 0 to lane 0.
3. It sorts every road's and lane's records by s.
4. It places each signal, on its road or at its inertial position, and
   gives a reference with no validity the lanes that face it.
5. It tells each signal which controllers hold it, through the
   junctions that name those controllers.
6. It makes the `Map`, which cuts the lanes into segments.
7. It boxes each junction, finds the junction roads that cross, and
   moves each sign that stands on a driving lane off it.

A road here is named by its index in the builder's list, a section by its
index in the road, and a lane by its index in the section, where CARLA
passes pointers. A signal reference is named by its road's index and its
index in that road's signal list.

Differences from CARLA: a lane link that names no lane is dropped, where
CARLA would store a null pointer and crash on it, and a controller that
names a missing signal skips it, where CARLA would read past the end of a
map. A signal reference that names no signal is refused. Junction bounds
include both traffic directions and complete lane sections, with bounded
chord approximation instead of CARLA's ten-step walk. See `junction_bounds`.

Source: CARLA 1360bb9, `LibCarla/source/carla/road/MapBuilder.cpp`.
"""

from extensions.carla.geo import GeoLocation, GeoProjection
from extensions.carla.map_search import MapBuildBudget, _MapBuildWork
from extensions.carla.map_validation import (
    _preflight_map_records,
    _reserve_information_sort,
    _reserve_road_scan,
    _reserve_lanes_at,
    _reserve_lane_scalars,
)
from extensions.carla.curve_bounds import _reference_work
from extensions.carla.junction_bounds import _lane_section_box_with_work
from extensions.carla.geometry import (
    ARC_LENGTH,
    LINE,
    NORMALIZED,
    RoadGeometry,
    with_arc,
    with_param_poly3,
    with_poly3,
    with_spiral,
)
from extensions.carla.map import (
    Connection,
    Controller,
    Junction,
    LaneLink,
    Map,
    Signal,
    SignalDependency,
    Waypoint,
    is_traffic_light,
    _preflight_map_metadata,
)
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Lane, LaneKey, Road
from extensions.carla.road_info import (
    ConId,
    ControllerId,
    CrosswalkPoint,
    JuncId,
    LANE_ANY,
    LANE_DRIVING,
    LANE_NONE,
    LANE_SHOULDER,
    LaneId,
    LaneType,
    LaneValidity,
    MarkLaneChange,
    ORIENTATION_BOTH,
    ORIENTATION_NEGATIVE,
    ORIENTATION_POSITIVE,
    RoadId,
    RoadInfoCrosswalk,
    RoadInfoElevation,
    RoadInfoGeometry,
    RoadInfoLaneAccess,
    RoadInfoLaneBorder,
    RoadInfoLaneHeight,
    RoadInfoLaneMaterial,
    RoadInfoLaneOffset,
    RoadInfoLaneRule,
    RoadInfoLaneVisibility,
    RoadInfoLaneWidth,
    RoadInfoMarkRecord,
    RoadInfoMarkTypeLine,
    RoadInfoSignal,
    RoadInfoSpeed,
    SectionId,
    SignalId,
    SignalOrientation,
    mark_lane_change_of,
)
from extensions.carla.transform import CarlaRotation, CarlaTransform
from math.bounds import Box3
from math.vector3 import Vector3
from units.si import DEGREE, Angle, Length, METER

comptime _FLOAT_MAX = Float32(3.4028234663852886e38)
comptime _TO_DEGREES = Float32(180.0) / Float32(3.14159265358979323846)


def default_validities(
    orientation: SignalOrientation, lanes: List[LaneId]
) raises -> List[LaneValidity]:
    """Return the lanes a signal with no validity holds for.

    This is `GenerateDefaultValiditiesForSignalReferences`: a signal that
    faces "+" holds for every left lane, one that faces "-" for every
    right lane, and one that faces both ways for both.

    Args:
        orientation: Which way the signal faces.
        lanes: The ids of the lanes at the signal's s.

    Returns:
        One validity from lane 1 to the outermost left lane, then one from
        the outermost right lane to lane -1, as the orientation asks and
        the lanes allow.

    Raises:
        Error: If the orientation is not valid.
    """
    if not orientation.is_valid():
        raise Error("Signal orientation is not valid")
    var out = List[LaneValidity]()
    if orientation != ORIENTATION_NEGATIVE:
        var max_lane = 0
        for lane in lanes:
            max_lane = max(max_lane, lane.value)
        if max_lane >= 1:
            out.append(LaneValidity(LaneId(1), LaneId(max_lane)))
    if orientation != ORIENTATION_POSITIVE:
        var min_lane = 0
        for lane in lanes:
            min_lane = min(min_lane, lane.value)
        if min_lane <= -1:
            out.append(LaneValidity(LaneId(min_lane), LaneId(-1)))
    return out^


@fieldwise_init
struct SignalReferenceHandle(ImplicitlyCopyable):
    """Where a signal reference sits while the map is built."""

    var road: Int
    var index: Int


struct MapBuilder(Movable):
    """The calls that assemble a `Map`, `road::MapBuilder`."""

    var roads: List[Road]
    var junctions: List[Junction]
    var controllers: List[Controller]
    # CARLA's `_temp_signal_container`: a later signal with the same id
    # replaces the earlier one.
    var signals: List[Signal]
    var geo_reference: GeoLocation
    var geo_projection: GeoProjection
    var _build_work: _MapBuildWork

    def __init__(out self):
        """Start with nothing."""
        self._build_work = _MapBuildWork(MapBuildBudget())
        self.roads = List[Road]()
        self.junctions = List[Junction]()
        self.controllers = List[Controller]()
        self.signals = List[Signal]()
        self.geo_reference = GeoLocation()
        self.geo_projection = GeoProjection()

    # --- roads and lanes ------------------------------------------------------

    def add_road(
        mut self,
        id: RoadId,
        name: String,
        length: Float64,
        junction_id: JuncId,
        predecessor: RoadId,
        successor: RoadId,
        is_rht: Bool,
    ) raises -> Int:
        """Add a road, `AddRoad`. A second road with the same id resets the
        first's fields, as CARLA's `emplace` and assignments do.

        Args:
            id: The road's id.
            name: Its name.
            length: Its length, in meters.
            junction_id: Its junction, or `NO_JUNCTION`.
            predecessor: The road or junction before it, 0 for none.
            successor: The road or junction after it, 0 for none.
            is_rht: True if traffic keeps to the right.

        Returns:
            The road's index in `roads`.

        Raises:
            Error: If an id is not valid.
        """
        var road = Road(
            id, name, length, junction_id, predecessor, successor, is_rht
        )
        for i in range(len(self.roads)):
            if self.roads[i].id == id:
                ref old = self.roads[i]
                old.name = name
                old.length = length
                old.junction_id = junction_id
                old.is_junction = road.is_junction
                old.is_rht = is_rht
                old.successor = successor
                old.predecessor = predecessor
                return i
        self.roads.append(road^)
        return len(self.roads) - 1

    def road_index(self, id: RoadId) raises -> Int:
        """Return a road's index, `MapBuilder::GetRoad`.

        Args:
            id: The road's id.

        Returns:
            Its index in `roads`.

        Raises:
            Error: If no road has the id.
        """
        for i in range(len(self.roads)):
            if self.roads[i].id == id:
                return i
        raise Error("The builder has no road with that id")

    def add_road_section(
        mut self, road: Int, id: SectionId, s: Float64
    ) raises -> Int:
        """Add a lane section, `AddRoadSection`.

        Args:
            road: The road's index.
            id: The section's id.
            s: Where it starts, in meters.

        Returns:
            The section's index in the road.

        Raises:
            Error: If the id is not valid.
        """
        return self.roads[road].add_section(id, s)

    def add_road_section_lane(
        mut self,
        road: Int,
        section: Int,
        lane_id: LaneId,
        lane_type: LaneType,
        level: Bool,
        predecessor: LaneId,
        successor: LaneId,
    ) raises -> LaneKey:
        """Add a lane, `AddRoadSectionLane`. A lane with an id the section
        has already takes the new fields.

        Args:
            road: The road's index.
            section: The section's index.
            lane_id: The lane's id.
            lane_type: Its type.
            level: OpenDRIVE's `level`.
            predecessor: The lane it links back to, 0 for none.
            successor: The lane it links on to, 0 for none.

        Returns:
            The lane.

        Raises:
            Error: If an id or the type is not valid.
        """
        if not (
            lane_type.is_valid()
            and predecessor.is_valid()
            and successor.is_valid()
        ):
            raise Error("Lane type or lane link is not valid")
        ref s = self.roads[road].sections[section]
        var at = s.add_lane(lane_id)
        ref lane = s.lanes[at]
        lane.type = lane_type
        lane.level = level
        lane.predecessor = predecessor
        lane.successor = successor
        return LaneKey(self.roads[road].id, s.id, lane_id)

    def lane(
        self, road_id: RoadId, lane_id: LaneId, s: Float64
    ) raises -> Tuple[Int, Int, Int]:
        """Return the lane with an id at s, `MapBuilder::GetLane`.

        Args:
            road_id: The road.
            lane_id: The lane.
            s: A distance along the road, in meters.

        Returns:
            The road's index, the section's index and the lane's index.

        Raises:
            Error: If there is no such road or lane.
        """
        var r = self.road_index(road_id)
        var found = self.roads[r].lane_by_distance(s, lane_id)
        return (r, found[0], found[1])

    # --- lane records ---------------------------------------------------------

    def create_lane_width(
        mut self,
        lane: Tuple[Int, Int, Int],
        s: Float64,
        a: Float64,
        b: Float64,
        c: Float64,
        d: Float64,
    ):
        """Add a width record, `CreateLaneWidth`.

        Args:
            lane: The lane, from `lane`.
            s: Where the record starts, in meters along the road.
            a: The width at s, in meters.
            b: Its rate of change.
            c: The quadratic term, per meter.
            d: The cubic term, per square meter.
        """
        self._lane(lane).info.widths.append(
            RoadInfoLaneWidth(s, CubicPolynomial(a, b, c, d, s))
        )

    def create_lane_border(
        mut self,
        lane: Tuple[Int, Int, Int],
        s: Float64,
        a: Float64,
        b: Float64,
        c: Float64,
        d: Float64,
    ):
        """Add a border record, `CreateLaneBorder`.

        Args:
            lane: The lane.
            s: Where the record starts, in meters along the road.
            a: The border's offset at s, in meters.
            b: Its rate of change.
            c: The quadratic term, per meter.
            d: The cubic term, per square meter.
        """
        self._lane(lane).info.borders.append(
            RoadInfoLaneBorder(s, CubicPolynomial(a, b, c, d, s))
        )

    def create_lane_height(
        mut self,
        lane: Tuple[Int, Int, Int],
        s: Float64,
        inner: Float64,
        outer: Float64,
    ):
        """Add a height record, `CreateLaneHeight`.

        Args:
            lane: The lane.
            s: Where the record starts, in meters along the road.
            inner: The lift at the inner edge, in meters.
            outer: The lift at the outer edge, in meters.
        """
        self._lane(lane).info.heights.append(
            RoadInfoLaneHeight(s, inner, outer)
        )

    def create_lane_material(
        mut self,
        lane: Tuple[Int, Int, Int],
        s: Float64,
        surface: String,
        friction: Float64,
        roughness: Float64,
    ):
        """Add a material record, `CreateLaneMaterial`.

        Args:
            lane: The lane.
            s: Where the record starts, in meters along the road.
            surface: The surface's name.
            friction: Its friction coefficient.
            roughness: Its roughness.
        """
        self._lane(lane).info.materials.append(
            RoadInfoLaneMaterial(s, surface, friction, roughness)
        )

    def create_lane_rule(
        mut self, lane: Tuple[Int, Int, Int], s: Float64, value: String
    ):
        """Add a rule record, `CreateLaneRule`.

        Args:
            lane: The lane.
            s: Where the record starts, in meters along the road.
            value: The rule's text.
        """
        self._lane(lane).info.rules.append(RoadInfoLaneRule(s, value))

    def create_lane_visibility(
        mut self,
        lane: Tuple[Int, Int, Int],
        s: Float64,
        forward: Float64,
        back: Float64,
        left: Float64,
        right: Float64,
    ):
        """Add a visibility record, `CreateLaneVisibility`.

        Args:
            lane: The lane.
            s: Where the record starts, in meters along the road.
            forward: Meters of sight forward.
            back: Meters of sight back.
            left: Meters of sight left.
            right: Meters of sight right.
        """
        self._lane(lane).info.visibilities.append(
            RoadInfoLaneVisibility(s, forward, back, left, right)
        )

    def create_lane_access(
        mut self, lane: Tuple[Int, Int, Int], s: Float64, restriction: String
    ):
        """Add an access record, `CreateLaneAccess`.

        Args:
            lane: The lane.
            s: Where the record starts, in meters along the road.
            restriction: Who may use the lane.
        """
        self._lane(lane).info.accesses.append(
            RoadInfoLaneAccess(s, restriction)
        )

    def create_lane_speed(
        mut self,
        lane: Tuple[Int, Int, Int],
        s: Float64,
        max: Float64,
        unit: String = "",
    ) raises:
        """Add a numeric lane speed without dropping its source unit.

        Args:
            lane: The lane.
            s: Where the record starts, in meters along the road.
            max: The finite nonnegative limit in the source unit.
            unit: The source unit; omitted means m/s.

        Raises:
            Error: If the source number or unit is invalid.
        """
        var record = RoadInfoSpeed(s, max, "Town", unit)
        self._lane(lane).info.speeds.append(record^)

    def create_lane_speed(
        mut self,
        lane: Tuple[Int, Int, Int],
        s: Float64,
        max: String,
        unit: String,
    ) raises:
        """Add a numeric lane speed directly from OpenDRIVE text.

        Args:
            lane: The lane.
            s: Where the record starts, in meters along the road.
            max: The original numeric max text. Road keywords are invalid.
            unit: The original unit; omitted means m/s.

        Raises:
            Error: If the source number or unit is invalid.
        """
        var record = RoadInfoSpeed.from_opendrive(s, max, "Town", unit, False)
        self._lane(lane).info.speeds.append(record^)

    def create_road_mark(
        mut self,
        lane: Tuple[Int, Int, Int],
        road_mark_id: Int,
        s: Float64,
        type: String,
        weight: String,
        color: String,
        material: String,
        width: Float64,
        lane_change: String,
        height: Float64,
        type_name: String,
        type_width: Float64,
        is_rht: Bool,
    ):
        """Add a road mark, `CreateRoadMark`.

        Args:
            lane: The lane.
            road_mark_id: The mark's index within the lane.
            s: Where the mark starts, in meters along the road.
            type: The mark's type, such as "broken".
            weight: Its weight.
            color: Its color.
            material: Its material.
            width: The paint's width, in meters.
            lane_change: "increase", "decrease", "none", or anything else
                for both.
            height: The paint's height, in meters.
            type_name: The name of the mark's `type` child.
            type_width: The width of the mark's `type` child.
            is_rht: The traffic rule of the lane's road.
        """
        self._lane(lane).info.marks.append(
            RoadInfoMarkRecord(
                s,
                road_mark_id,
                type,
                weight,
                color,
                material,
                width,
                mark_lane_change_of(lane_change),
                height,
                type_name,
                type_width,
                is_rht,
            )
        )

    def create_road_mark_type_line(
        mut self,
        lane: Tuple[Int, Int, Int],
        road_mark_id: Int,
        length: Float64,
        space: Float64,
        t_offset: Float64,
        s: Float64,
        rule: String,
        width: Float64,
    ):
        """Add a line to a road mark's type, `CreateRoadMarkTypeLine`.

        The line joins the first mark of the lane with the same id. With
        no such mark it is dropped, as in CARLA.

        Args:
            lane: The lane.
            road_mark_id: The mark's index within the lane.
            length: Meters of paint.
            space: Meters of gap.
            t_offset: The sideways offset, in meters.
            s: Where the line starts, in meters along the road.
            rule: The line's rule.
            width: The line's width, in meters.
        """
        ref marks = self._lane(lane).info.marks
        for i in range(len(marks)):
            if marks[i].road_mark_id == road_mark_id:
                marks[i].lines.append(
                    RoadInfoMarkTypeLine(
                        s, road_mark_id, length, space, t_offset, rule, width
                    )
                )
                return

    def _lane(
        mut self, lane: Tuple[Int, Int, Int]
    ) -> ref[origin_of(self.roads[0].sections[0].lanes[0])] Lane:
        return self.roads[lane[0]].sections[lane[1]].lanes[lane[2]]

    # --- road records ---------------------------------------------------------

    def add_road_elevation_profile(
        mut self,
        road: Int,
        s: Float64,
        a: Float64,
        b: Float64,
        c: Float64,
        d: Float64,
    ):
        """Add an elevation record, `AddRoadElevationProfile`.

        Args:
            road: The road's index.
            s: Where the record starts, in meters.
            a: The height at s, in meters.
            b: The slope.
            c: The quadratic term, per meter.
            d: The cubic term, per square meter.
        """
        self.roads[road].info.elevations.append(
            RoadInfoElevation(s, CubicPolynomial(a, b, c, d, s))
        )

    def create_section_offset(
        mut self,
        road: Int,
        s: Float64,
        a: Float64,
        b: Float64,
        c: Float64,
        d: Float64,
    ):
        """Add a lane offset record, `CreateSectionOffset`.

        Args:
            road: The road's index.
            s: Where the record starts, in meters.
            a: The offset at s, in meters. Plus is to the left.
            b: Its rate of change.
            c: The quadratic term, per meter.
            d: The cubic term, per square meter.
        """
        self.roads[road].info.lane_offsets.append(
            RoadInfoLaneOffset(s, CubicPolynomial(a, b, c, d, s))
        )

    def create_road_speed(
        mut self,
        road: Int,
        s: Float64,
        type: String,
        max: Float64,
        unit: String,
    ) raises:
        """Add a numeric road speed without dropping its unit.

        Args:
            road: The road's index.
            s: Where the record starts, in meters.
            type: The road type; the compatibility record type stays Town.
            max: The finite nonnegative source limit.
            unit: The source unit; omitted means m/s.

        Raises:
            Error: If the number or unit is invalid.
        """
        _ = type
        var record = RoadInfoSpeed(s, max, "Town", unit)
        self.roads[road].info.speeds.append(record^)

    def create_road_speed(
        mut self,
        road: Int,
        s: Float64,
        type: String,
        max: String,
        unit: String,
    ) raises:
        """Add a numeric, unrestricted, undefined or absent road speed.

        Args:
            road: The road's index.
            s: Where the record starts, in meters.
            type: The road type; the compatibility record type stays Town.
            max: The original max text; empty means no speed element.
            unit: The source unit; omitted means m/s.

        Raises:
            Error: If a numeric limit or source unit is invalid.
        """
        _ = type
        var record = RoadInfoSpeed.from_opendrive(s, max, "Town", unit, True)
        self.roads[road].info.speeds.append(record^)

    def add_road_object_crosswalk(
        mut self,
        road: Int,
        name: String,
        s: Float64,
        t: Float64,
        z_offset: Float64,
        heading: Float64,
        pitch: Float64,
        roll: Float64,
        orientation: String,
        width: Float64,
        length: Float64,
        points: List[CrosswalkPoint],
    ):
        """Add a crosswalk, `AddRoadObjectCrosswalk`.

        Args:
            road: The road's index.
            name: The object's name.
            s: Where it sits, in meters along the road.
            t: Meters to the left of the reference line.
            z_offset: Meters up.
            heading: Its heading, in radians.
            pitch: Its pitch, in radians.
            roll: Its roll, in radians.
            orientation: Its orientation text.
            width: Its width, in meters.
            length: Its length, in meters.
            points: Its outline's corners.
        """
        self.roads[road].info.crosswalks.append(
            RoadInfoCrosswalk(
                s,
                name,
                t,
                z_offset,
                heading,
                pitch,
                roll,
                orientation,
                width,
                length,
                points.copy(),
            )
        )

    def _geometry(mut self, road: Int, var geometry: RoadGeometry):
        var s = geometry.s
        self.roads[road].info.geometries.append(RoadInfoGeometry(s, geometry^))

    def _base(
        self,
        s: Float64,
        x: Float64,
        y: Float64,
        heading: Float64,
        length: Float64,
    ) raises -> RoadGeometry:
        # CARLA keeps the start point as a `float` `Location`.
        return RoadGeometry(
            LINE,
            s,
            Float64(Float32(x)),
            Float64(Float32(y)),
            heading,
            length,
        )

    def add_road_geometry_line(
        mut self,
        road: Int,
        s: Float64,
        x: Float64,
        y: Float64,
        heading: Float64,
        length: Float64,
    ) raises:
        """Add a straight geometry, `AddRoadGeometryLine`.

        Args:
            road: The road's index.
            s: Where it starts, in meters.
            x: Start east, in meters.
            y: Start north, in meters.
            heading: Its heading, in radians.
            length: Its length, in meters.

        Raises:
            Error: If s is negative or the length is not positive.
        """
        self._geometry(road, self._base(s, x, y, heading, length))

    def add_road_geometry_arc(
        mut self,
        road: Int,
        s: Float64,
        x: Float64,
        y: Float64,
        heading: Float64,
        length: Float64,
        curvature: Float64,
    ) raises:
        """Add an arc, `AddRoadGeometryArc`.

        Args:
            road: The road's index.
            s: Where it starts, in meters.
            x: Start east, in meters.
            y: Start north, in meters.
            heading: Its start heading, in radians.
            length: Its length, in meters.
            curvature: One over the radius, per meter.

        Raises:
            Error: If s is negative, the length is not positive, or the
                curvature is zero.
        """
        self._geometry(
            road, with_arc(self._base(s, x, y, heading, length), curvature)
        )

    def add_road_geometry_spiral(
        mut self,
        road: Int,
        s: Float64,
        x: Float64,
        y: Float64,
        heading: Float64,
        length: Float64,
        curvature_start: Float64,
        curvature_end: Float64,
    ) raises:
        """Add a clothoid, `AddRoadGeometrySpiral`.

        Args:
            road: The road's index.
            s: Where it starts, in meters.
            x: Start east, in meters.
            y: Start north, in meters.
            heading: Its start heading, in radians.
            length: Its length, in meters.
            curvature_start: The curvature at the start, per meter.
            curvature_end: The curvature at the end, per meter.

        Raises:
            Error: If s is negative or the length is not positive.
        """
        self._geometry(
            road,
            with_spiral(
                self._base(s, x, y, heading, length),
                curvature_start,
                curvature_end,
            ),
        )

    def add_road_geometry_poly3(
        mut self,
        road: Int,
        s: Float64,
        x: Float64,
        y: Float64,
        heading: Float64,
        length: Float64,
        a: Float64,
        b: Float64,
        c: Float64,
        d: Float64,
    ) raises:
        """Add a cubic v(u), `AddRoadGeometryPoly3`.

        Args:
            road: The road's index.
            s: Where it starts, in meters.
            x: Start east, in meters.
            y: Start north, in meters.
            heading: The direction of plus u, in radians.
            length: Its length, in meters.
            a: The constant term of v, in meters.
            b: The linear term.
            c: The quadratic term, per meter.
            d: The cubic term, per square meter.

        Raises:
            Error: If s is negative or the length is not positive.
        """
        self._geometry(
            road, with_poly3(self._base(s, x, y, heading, length), a, b, c, d)
        )

    def add_road_geometry_param_poly3(
        mut self,
        road: Int,
        s: Float64,
        x: Float64,
        y: Float64,
        heading: Float64,
        length: Float64,
        u: CubicPolynomial,
        v: CubicPolynomial,
        p_range: String,
    ) raises:
        """Add a parametric cubic, `AddRoadGeometryParamPoly3`.

        Args:
            road: The road's index.
            s: Where it starts, in meters.
            x: Start east, in meters.
            y: Start north, in meters.
            heading: The direction of plus u, in radians.
            length: Its length, in meters.
            u: The cubic u(p).
            v: The cubic v(p).
            p_range: "arcLength", or anything else for a normalized p.

        Raises:
            Error: If s is negative, the length is not positive, or the
                curve does not move.
        """
        var p = ARC_LENGTH if p_range == "arcLength" else NORMALIZED
        self._geometry(
            road,
            with_param_poly3(self._base(s, x, y, heading, length), u, v, p),
        )

    # --- signals --------------------------------------------------------------

    def add_signal(
        mut self,
        road: Int,
        signal_id: SignalId,
        s: Float64,
        t: Float64,
        name: String,
        dynamic: String,
        orientation: String,
        z_offset: Float64,
        country: String,
        type: String,
        subtype: String,
        value: Float64,
        unit: String,
        height: Float64,
        width: Float64,
        text: String,
        h_offset: Float64,
        pitch: Float64,
        roll: Float64,
        value_present: Bool = True,
    ) raises -> SignalReferenceHandle:
        """Add a signal and a reference to it on its road, `AddSignal`.

        Args:
            road: The road's index.
            signal_id: Its id. A later signal with the same id replaces
                this one.
            s: Meters along the road.
            t: Meters to the left of the reference line.
            name: Its name.
            dynamic: "yes" for a signal that changes.
            orientation: "+", "-" or anything else for both.
            z_offset: Meters up from the road.
            country: Its catalog's country.
            type: Its type.
            subtype: Its subtype.
            value: Its value.
            unit: The value's unit.
            height: Its height, in meters.
            width: Its width, in meters.
            text: Its text.
            h_offset: The turn from the road's heading, in radians.
            pitch: Its pitch, in radians.
            roll: Its roll, in radians.
            value_present: Whether the source supplied a numeric value.

        Returns:
            The reference's handle.

        Raises:
            Error: If the id is not valid or s is negative.
        """
        var signal = Signal(
            self.roads[road].id,
            signal_id,
            s,
            t,
            name,
            dynamic,
            orientation,
            z_offset,
            country,
            type,
            subtype,
            value,
            unit,
            height,
            width,
            text,
            h_offset,
            pitch,
            roll,
            value_present,
        )
        var replaced = False
        for i in range(len(self.signals)):
            if self.signals[i].signal_id == signal_id:
                self.signals[i] = signal.copy()
                replaced = True
        if not replaced:
            self.signals.append(signal^)
        return self.add_signal_reference(road, signal_id, s, t, orientation)

    def _signal_index(self, signal_id: SignalId) raises -> Int:
        for i in range(len(self.signals)):
            if self.signals[i].signal_id == signal_id:
                return i
        raise Error("The builder has no signal with that id")

    def add_signal_position_inertial(
        mut self,
        signal_id: SignalId,
        x: Float64,
        y: Float64,
        z: Float64,
        heading: Float64,
        pitch: Float64,
        roll: Float64,
    ) raises:
        """Place a signal at a point, `AddSignalPositionInertial`.

        Args:
            signal_id: The signal.
            x: East, in meters.
            y: North, in meters.
            z: Up, in meters.
            heading: Its heading, in radians.
            pitch: Its pitch, in radians.
            roll: Its roll, in radians.

        Raises:
            Error: If no signal has the id.
        """
        ref signal = self.signals[self._signal_index(signal_id)]
        signal.using_inertial_position = True
        signal.transform = CarlaTransform(
            Length(Float32(x), METER),
            Length(Float32(-y), METER),
            Length(Float32(z), METER),
            CarlaRotation(
                Angle(Float32(pitch) * _TO_DEGREES, DEGREE),
                Angle(Float32(-heading) * _TO_DEGREES, DEGREE),
                Angle(Float32(roll) * _TO_DEGREES, DEGREE),
            ),
        )

    def add_signal_position_road(
        mut self,
        signal_id: SignalId,
        road_id: RoadId,
        s: Float64,
        t: Float64,
        z_offset: Float64,
        h_offset: Float64,
        pitch: Float64,
        roll: Float64,
    ) raises:
        """Move a signal to another place on a road, `AddSignalPositionRoad`.

        Args:
            signal_id: The signal.
            road_id: The road.
            s: Meters along it.
            t: Meters to the left of its reference line.
            z_offset: Meters up.
            h_offset: The turn from the road's heading, in radians.
            pitch: Its pitch, in radians.
            roll: Its roll, in radians.

        Raises:
            Error: If no signal has the id, or the road id is not valid.
        """
        if not road_id.is_valid():
            raise Error("Road id is not valid")
        ref signal = self.signals[self._signal_index(signal_id)]
        signal.road_id = road_id
        signal.s = s
        signal.t = t
        signal.z_offset = z_offset
        signal.h_offset = h_offset
        signal.pitch = pitch
        signal.roll = roll

    def add_signal_reference(
        mut self,
        road: Int,
        signal_id: SignalId,
        s: Float64,
        t: Float64,
        orientation: String,
    ) raises -> SignalReferenceHandle:
        """Add a reference to a signal, `AddSignalReference`.

        CARLA clamps s to 10 micrometers short of the road's end.

        Args:
            road: The road's index.
            signal_id: The signal.
            s: Meters along the road. It must not be negative.
            t: Meters to the left of the reference line.
            orientation: "+", "-" or anything else for both.

        Returns:
            The reference's handle.

        Raises:
            Error: If s is negative or the id is not valid.
        """
        if s < 0.0:
            raise Error("A signal reference cannot sit before s = 0")
        if not signal_id.is_valid():
            raise Error("Signal id is not valid")
        ref r = self.roads[road]
        var fixed = min(max(s, 0.0), r.length - 0.00001)
        r.info.signals.append(
            RoadInfoSignal(
                signal_id, r.id, fixed, t, orientation, List[LaneValidity]()
            )
        )
        return SignalReferenceHandle(road, len(r.info.signals) - 1)

    def add_validity_to_signal_reference(
        mut self,
        reference: SignalReferenceHandle,
        from_lane: LaneId,
        to_lane: LaneId,
    ) raises:
        """Add a lane range to a reference, `AddValidityToSignalReference`.

        Args:
            reference: The reference's handle.
            from_lane: The first lane.
            to_lane: The last lane.

        Raises:
            Error: If a lane id is not valid.
        """
        if not (from_lane.is_valid() and to_lane.is_valid()):
            raise Error("Lane id is not valid")
        self.roads[reference.road].info.signals[
            reference.index
        ].validities.append(LaneValidity(from_lane, to_lane))

    def add_dependency_to_signal(
        mut self,
        signal_id: SignalId,
        dependency_id: String,
        dependency_type: String,
    ) raises:
        """Add a dependency to a signal, `AddDependencyToSignal`.

        Args:
            signal_id: The signal.
            dependency_id: The signal it depends on.
            dependency_type: The kind of dependency.

        Raises:
            Error: If no signal has the id.
        """
        self.signals[self._signal_index(signal_id)].dependencies.append(
            SignalDependency(dependency_id, dependency_type)
        )

    # --- junctions and controllers ------------------------------------------

    def add_junction(mut self, id: JuncId, name: String) raises:
        """Add a junction, `AddJunction`. A second one with the same id is
        ignored, as `emplace` ignores it.

        Args:
            id: The junction's id.
            name: Its name.

        Raises:
            Error: If the id is not valid.
        """
        var junction = Junction(id, name)
        for existing in self.junctions:
            if existing.id == id:
                return
        self.junctions.append(junction^)

    def _junction(
        mut self, id: JuncId
    ) raises -> ref[origin_of(self.junctions[0])] Junction:
        for i in range(len(self.junctions)):
            if self.junctions[i].id == id:
                return self.junctions[i]
        raise Error("The builder has no junction with that id")

    def add_connection(
        mut self,
        junction_id: JuncId,
        connection_id: ConId,
        incoming_road: RoadId,
        connecting_road: RoadId,
    ) raises:
        """Add a connection to a junction, `AddConnection`. A second one
        with the same id is ignored.

        Args:
            junction_id: The junction.
            connection_id: The connection's id.
            incoming_road: The road that enters.
            connecting_road: The junction road it continues on.

        Raises:
            Error: If an id is not valid or the junction is missing.
        """
        var connection = Connection(
            connection_id, incoming_road, connecting_road
        )
        ref junction = self._junction(junction_id)
        if junction.connection_index(connection_id) >= 0:
            return
        var at = 0
        while (
            at < len(junction.connections)
            and junction.connections[at].id.value < connection_id.value
        ):
            at += 1
        junction.connections.insert(at, connection^)

    def add_lane_link(
        mut self,
        junction_id: JuncId,
        connection_id: ConId,
        from_lane: LaneId,
        to_lane: LaneId,
    ) raises:
        """Add a lane link to a connection, `AddLaneLink`.

        Args:
            junction_id: The junction.
            connection_id: The connection.
            from_lane: The incoming road's lane.
            to_lane: The connecting road's lane.

        Raises:
            Error: If the junction or the connection is missing.
        """
        ref junction = self._junction(junction_id)
        var at = junction.connection_index(connection_id)
        if at < 0:
            raise Error("The junction has no connection with that id")
        junction.connections[at].lane_links.append(LaneLink(from_lane, to_lane))

    def add_junction_controller(
        mut self, junction_id: JuncId, controllers: List[ControllerId]
    ) raises:
        """Set a junction's controllers, `AddJunctionController`.

        Args:
            junction_id: The junction.
            controllers: The controller ids. They are kept sorted, once
                each, as a `std::set`.

        Raises:
            Error: If the junction is missing.
        """
        ref junction = self._junction(junction_id)
        junction.controllers = _sorted_set(controllers)

    def create_controller(
        mut self,
        id: ControllerId,
        name: String,
        sequence: Int,
        signals: List[SignalId],
    ) raises:
        """Add a controller and its signals, `CreateController`.

        A second controller with the same id is ignored, as `emplace`
        ignores it, but its signals still replace the first's, as CARLA's
        assignment does.

        Args:
            id: The controller's id.
            name: Its name.
            sequence: Its sequence number.
            signals: The ids of the signals it holds.

        Raises:
            Error: If the id is not valid.
        """
        var controller = Controller(id, name, sequence)
        var at = -1
        for i in range(len(self.controllers)):
            if self.controllers[i].id == id:
                at = i
        if at < 0:
            self.controllers.append(controller^)
            at = len(self.controllers) - 1
        self.controllers[at].signals = _sorted_signal_set(signals)

    # --- building -------------------------------------------------------------

    def _index(mut self) raises -> Dict[Int, Int]:
        var out = Dict[Int, Int]()
        for i in range(len(self.roads)):
            self._build_work.step()
            out[self.roads[i].id.value] = i
        return out^

    def _edge_lane(
        mut self, index: Dict[Int, Int], road_id: RoadId, lane_id: LaneId
    ) raises -> Optional[LaneKey]:
        # `GetEdgeLanePointer`. The callers pass a road of the map.
        _reserve_road_scan(self.roads[index[road_id.value]], self._build_work)
        ref road = self.roads[index[road_id.value]]
        var section: Int
        if road.is_positive_direction(lane_id):
            section = road.start_section(lane_id)
        else:
            section = road.end_section(lane_id)
        if section < 0:
            return None
        return LaneKey(road.id, road.sections[section].id, lane_id)

    def _junction_lanes(
        mut self,
        index: Dict[Int, Int],
        junction_id: JuncId,
        road_id: RoadId,
        lane_id: LaneId,
    ) raises -> List[Tuple[RoadId, LaneId]]:
        # `GetJunctionLanes`.
        var out = List[Tuple[RoadId, LaneId]]()
        var at = -1
        for i in range(len(self.junctions)):
            self._build_work.step()
            if self.junctions[i].id == junction_id:
                at = i
        if at < 0:
            return out^
        for connection in self.junctions[at].connections:
            self._build_work.step()
            var found = index.get(connection.connecting_road.value)
            if not Bool(found):
                raise Error("A junction connects a road the map lacks")
            ref road = self.roads[found.value()]
            if road_id == road.predecessor:
                _reserve_lanes_at(road, self._build_work)
                for pair in road.lanes_at(0.0):
                    self._build_work.step()
                    ref lane = road.sections[pair[0]].lanes[pair[1]]
                    if lane_id == lane.predecessor:
                        out.append((road.id, lane.id))
            if road_id == road.successor:
                _reserve_lanes_at(road, self._build_work)
                for pair in road.lanes_at(road.length):
                    self._build_work.step()
                    ref lane = road.sections[pair[0]].lanes[pair[1]]
                    if lane_id == lane.successor:
                        out.append((road.id, lane.id))
        return out^

    def _lane_next(
        mut self, index: Dict[Int, Int], road: Int, section: Int, lane: Int
    ) raises -> List[LaneKey]:
        # `GetLaneNext`.
        _reserve_road_scan(self.roads[road], self._build_work)
        ref r = self.roads[road]
        ref the_lane = r.sections[section].lanes[lane]
        var lane_id = the_lane.id
        var positive = r.is_positive_direction(lane_id)
        var next_road = r.successor if positive else r.predecessor
        var next = the_lane.successor if positive else the_lane.predecessor
        var next_is_junction = next_road.value not in index
        var s = r.sections[section].s
        var road_id = r.id
        var linked = next.value != 0 or lane_id.value == 0
        var out = List[LaneKey]()
        # CARLA asks whether a section follows this one in the lane's
        # direction: one with a greater s, or any s above zero backward.
        var inside = s > 0.0
        if positive:
            inside = False
            # The road holds this section, so it has sections.
            for other in r.sections:  # pragma: no branch
                self._build_work.step()
                if other.s > s:
                    inside = True
        if inside:
            if linked:
                var found = r.next_lane(s, next) if positive else r.prev_lane(
                    s, next
                )
                if Bool(found):
                    var f = found.value()
                    out.append(LaneKey(r.id, r.sections[f[0]].id, next))
        elif not next_is_junction:
            if linked:
                var edge = self._edge_lane(index, next_road, next)
                if Bool(edge):
                    out.append(edge.value())
        else:
            for option in self._junction_lanes(
                index, JuncId(next_road.value), road_id, lane_id
            ):
                # The option is a lane of that road, so it has an edge.
                out.append(self._edge_lane(index, option[0], option[1]).value())
        return out^

    def _link_lanes(mut self) raises:
        # `CreatePointersBetweenRoadSegments`.
        var index = self._index()
        for r in range(len(self.roads)):
            self._build_work.step()
            for sec in range(len(self.roads[r].sections)):
                self._build_work.step()
                for ln in range(len(self.roads[r].sections[sec].lanes)):
                    self._build_work.step()
                    var nexts = self._lane_next(index, r, sec, ln)
                    var me = LaneKey(
                        self.roads[r].id,
                        self.roads[r].sections[sec].id,
                        self.roads[r].sections[sec].lanes[ln].id,
                    )
                    for key in nexts:
                        self._build_work.step()
                        var other = self._find(index, key)
                        self.roads[other[0]].sections[other[1]].lanes[
                            other[2]
                        ].prev_lanes.append(me)
                    self.roads[r].sections[sec].lanes[ln].next_lanes = nexts^
        for r in range(len(self.roads)):
            self._build_work.step()
            var nexts = List[RoadId]()
            var prevs = List[RoadId]()
            var me = self.roads[r].id
            for section in self.roads[r].sections:
                self._build_work.step()
                for lane in section.lanes:
                    self._build_work.step()
                    for key in lane.next_lanes:
                        self._build_work.step()
                        self._build_work.step(len(nexts))
                        if key.road_id != me and not _has(nexts, key.road_id):
                            nexts.append(key.road_id)
                    for key in lane.prev_lanes:
                        self._build_work.step()
                        self._build_work.step(len(prevs))
                        if key.road_id != me and not _has(prevs, key.road_id):
                            prevs.append(key.road_id)
            self.roads[r].nexts = nexts^
            self.roads[r].prevs = prevs^

    def _find(
        mut self, index: Dict[Int, Int], key: LaneKey
    ) raises -> Tuple[Int, Int, Int]:
        var r = index[key.road_id.value]
        _reserve_road_scan(self.roads[r], self._build_work)
        var sec = self.roads[r].section_index(key.section_id)
        return (r, sec, self.roads[r].sections[sec].lane_index(key.lane_id))

    def _remove_zero_validities(mut self) raises:
        # `RemoveZeroLaneValiditySignalReferences`.
        for r in range(len(self.roads)):
            self._build_work.step()
            var kept = List[RoadInfoSignal]()
            for reference in self.roads[r].info.signals:
                self._build_work.step()
                var remove = len(reference.validities) > 0
                for validity in reference.validities:
                    self._build_work.step()
                    if (
                        validity.from_lane.value != 0
                        or validity.to_lane.value != 0
                    ):
                        remove = False
                if not remove:
                    kept.append(reference.copy())
            self.roads[r].info.signals = kept^

    def _signal_transform(
        mut self, index: Dict[Int, Int], signal: Signal
    ) raises -> CarlaTransform:
        # `ComputeSignalTransform`, plus a traffic light's quarter meter
        # forward.
        var found = index.get(signal.road_id.value)
        if not Bool(found):
            raise Error("A signal stands on a road the map lacks")
        var terms = _reference_work(
            self.roads[found.value()], signal.s, signal.s
        )
        if terms < 0:
            raise Error(
                "Signal construction cannot resolve reference quadrature work"
            )
        self._build_work.term(terms)
        var point = self.roads[found.value()].directed_point_no_lane_offset(
            signal.s
        )
        point.apply_lateral_offset(Length(Float32(-signal.t), METER))
        var z = Float32(point.z) + Float32(signal.z_offset)
        var transform = CarlaTransform(
            Length(Float32(point.x), METER),
            Length(Float32(-point.y), METER),
            Length(z, METER),
            CarlaRotation(
                Angle(Float32(signal.pitch) * _TO_DEGREES, DEGREE),
                Angle(
                    Float32(-(point.tangent + signal.h_offset)) * _TO_DEGREES,
                    DEGREE,
                ),
                Angle(Float32(signal.roll) * _TO_DEGREES, DEGREE),
            ),
        )
        if is_traffic_light(signal.type):
            transform.location = (
                transform.location + transform.rotation.forward_vector() * 0.25
            )
        return transform

    def _solve_signals(mut self, index: Dict[Int, Int]) raises:
        # `SolveSignalReferencesAndTransforms`.
        for road in self.roads:
            self._build_work.step()
            for reference in road.info.signals:
                self._build_work.step()
                self._build_work.step(len(self.signals))
                _ = self._signal_index(reference.signal_id)
        for i in range(len(self.signals)):
            self._build_work.step()
            if self.signals[i].using_inertial_position:
                continue
            self._build_work.step(len(self.signals[i].controllers))
            self._build_work.step(len(self.signals[i].dependencies))
            var signal = self.signals[i].copy()
            var transform = self._signal_transform(index, signal)
            self.signals[i].transform = transform
        for r in range(len(self.roads)):
            self._build_work.step()
            for k in range(len(self.roads[r].info.signals)):
                self._build_work.step()
                if len(self.roads[r].info.signals[k].validities) > 0:
                    continue
                var s = self.roads[r].info.signals[k].s
                var lanes = List[LaneId]()
                _reserve_road_scan(
                    self.roads[r], self._build_work, section_passes=2
                )
                for pair in self.roads[r].lanes_by_distance(s):
                    self._build_work.step()
                    lanes.append(
                        self.roads[r].sections[pair[0]].lanes[pair[1]].id
                    )
                self._build_work.step_product(2, len(lanes))
                self.roads[r].info.signals[k].validities = default_validities(
                    self.roads[r].info.signals[k].orientation(), lanes
                )

    def _solve_controllers(mut self) raises:
        # `SolveControllerAndJuntionReferences`.
        for junction in self.junctions:
            self._build_work.step()
            for controller_id in junction.controllers:
                self._build_work.step()
                for c in range(len(self.controllers)):
                    self._build_work.step()
                    if self.controllers[c].id != controller_id:
                        continue
                    # The junctions come in order of id and name each
                    # controller once, so the id goes last, as the
                    # `std::set` insert puts it.
                    self.controllers[c].junctions.append(junction.id)
                    for signal_id in self.controllers[c].signals:
                        self._build_work.step()
                        for s in range(len(self.signals)):
                            self._build_work.step()
                            if self.signals[s].signal_id == signal_id:
                                self._build_work.step(
                                    len(self.signals[s].controllers)
                                )
                                self._build_work.step()
                                var ids = self.signals[s].controllers.copy()
                                ids.append(controller_id)
                                self._build_work.sort_work(len(ids))
                                self.signals[s].controllers = _sorted_set(ids)

    def build(
        mut self, budget: MapBuildBudget = MapBuildBudget()
    ) raises -> Map:
        """Join the pieces into a map, `MapBuilder::Build`.

        See the module docstring for the steps. The builder is empty
        afterwards on success. A failure after preflight may consume the
        builder, but never returns a partial Map.

        Args:
            budget: One finite ledger for preflight, links, sorting, spatial
                subdivision, junction proofs/conflicts, and sign relocation.

        Returns:
            The map.

        Raises:
            Error: If a signal reference names no signal, a junction
                connects a road the map lacks, or a record a step needs is
                missing.
        """
        self._build_work = _MapBuildWork(budget)
        _preflight_map_records(self.roads, self._build_work)
        _preflight_map_metadata(
            self.junctions, self.signals, self.controllers, self._build_work
        )
        self._build_work.sort_work(len(self.roads))
        self._build_work.sort_work(len(self.junctions))
        self._build_work.sort_work(len(self.signals))
        self._build_work.sort_work(len(self.controllers))
        var roads = List[Road]()
        while len(self.roads) > 0:
            var best = 0
            for i in range(1, len(self.roads)):
                if self.roads[i].id.value < self.roads[best].id.value:
                    best = i
            roads.append(self.roads.pop(best))
        self.roads = roads^
        _sort_by_junction_id(self.junctions)
        _sort_signals(self.signals)
        _sort_controllers(self.controllers)
        self._link_lanes()
        self._remove_zero_validities()
        for r in range(len(self.roads)):
            _reserve_information_sort(self.roads[r].info, self._build_work)
            self.roads[r].info.sort()
            for sec in range(len(self.roads[r].sections)):
                for ln in range(len(self.roads[r].sections[sec].lanes)):
                    _reserve_information_sort(
                        self.roads[r].sections[sec].lanes[ln].info,
                        self._build_work,
                    )
                    self.roads[r].sections[sec].lanes[ln].info.sort()
        var index = self._index()
        self._solve_signals(index)
        self._solve_controllers()
        var built = self.roads^
        self.roads = List[Road]()
        var junctions = self.junctions^
        self.junctions = List[Junction]()
        var signals = self.signals^
        self.signals = List[Signal]()
        var controllers = self.controllers^
        self.controllers = List[Controller]()
        var map = Map(
            built^,
            junctions^,
            signals^,
            controllers^,
            budget,
            _initial_work=self._build_work,
        )
        map.geo_reference = self.geo_reference
        map.geo_projection = self.geo_projection.copy()
        var post_work = map._construction_work
        for j in range(len(map.junctions)):
            post_work.step()
            map.junctions[j].bounding_box = _junction_box_with_work(
                map, map.junctions[j].id, post_work
            )
        for j in range(len(map.junctions)):
            post_work.step()
            var conflicts = map._compute_junction_conflicts_with_work(
                map.junctions[j].id, post_work
            )
            map.junctions[j].conflict_roads = conflicts[0].copy()
            map.junctions[j].conflicts = conflicts[1].copy()
        _check_signals_on_roads_with_work(map, post_work)
        map._construction_work = post_work
        return map^


def junction_box(map: Map, id: JuncId) raises -> Box3:
    """Return a junction's bounding box, `CreateJunctionBoundingBoxes`.

    Box each nonzero connecting lane selected by `LANE_ANY` over its
    complete section in CARLA's frame, independent of travel direction. Split at record boundaries
    and use at most 1 cm of smooth-curve chord padding. Separate numerical
    allowances cover Float32 rounding, Float64 cubics, and spiral quadrature. Singular tangents and excessive subdivisions use a wider
    conservative envelope. See the CARLA maps wiki's junction bounds.

    Args:
        map: The map.
        id: The junction.

    Returns:
        The box. With no lanes, it is the empty box CARLA makes: every
        minimum the largest float and every maximum the least.

    Raises:
        Error: If the junction or required records are missing, a section or
            sample interval is invalid, or coefficient/subdivision bounds
            are not finite.
    """
    var work = _MapBuildWork(MapBuildBudget())
    return _junction_box_with_work(map, id, work)


def _junction_box_with_work(
    map: Map, id: JuncId, mut work: _MapBuildWork
) raises -> Box3:
    var box = Box3(
        Vector3(_FLOAT_MAX, _FLOAT_MAX, _FLOAT_MAX),
        Vector3(-_FLOAT_MAX, -_FLOAT_MAX, -_FLOAT_MAX),
    )
    for pair in map._junction_waypoints_with_work(id, LANE_ANY, work):
        work.step()
        var start = pair[0]
        var at = map._locate_with_work(start, work)
        box.union(
            _lane_section_box_with_work(map.roads[at[0]], at[1], at[2], work)
        )
    return box


def check_signals_on_roads(mut map: Map) raises:
    """Move each sign that stands on a lane off it, `CheckSignalsOnRoads`.

    A sign closer than 0.7 lane widths to the nearest driving or shoulder
    lane's center steps a fifth of a lane width at a time, up to ten
    times, toward the side that is not a driving lane: right first on a
    right-hand road, left first on a left-hand one. If it finds no place
    in ten steps it stays. Stencils, "STATIC" signals and signals with an
    inertial position stay where they are.

    Args:
        map: The map, whose signals move.

    Raises:
        Error: If a lane's records are missing.
    """
    var work = _MapBuildWork(MapBuildBudget())
    _check_signals_on_roads_with_work(map, work)


def _check_signals_on_roads_with_work(
    mut map: Map, mut work: _MapBuildWork
) raises:
    var flags = LANE_SHOULDER | LANE_DRIVING
    for i in range(len(map.signals)):
        work.step()
        var position = map.signals[i].transform.location
        var rotation = map.signals[i].transform.rotation
        var closest = map._closest_lane_with_build_work(position, flags, work)
        ref name = map.signals[i].name
        if (
            "Stencil_STOP" in name
            or "STATIC" in name
            or map.signals[i].using_inertial_position
        ):
            continue
        if not Bool(closest):
            continue
        var w = closest.value()
        var road_transform = _signal_lane_pose(map, w, work)
        var distance = (road_transform.location - position).length()
        var width = _signal_lane_width(map, w, work)
        var is_rht = map.road(w.road_id).is_rht
        var direction = 1
        var steps = 0
        while Float64(distance) < width * 0.7 and steps < 10 and direction != 0:
            work.step()
            var right = _signal_side(map, w, True, work)
            var right_type = LANE_NONE
            if Bool(right):
                right_type = _signal_lane_type(map, right.value(), work)
            var left = _signal_side(map, w, False, work)
            var left_type = LANE_NONE
            if Bool(left):
                left_type = _signal_lane_type(map, left.value(), work)
            var first = right_type if is_rht else left_type
            var second = left_type if is_rht else right_type
            var toward = 1 if is_rht else -1
            if first != LANE_DRIVING:
                direction = toward
            elif second != LANE_DRIVING:
                direction = -toward
            else:
                direction = 0
            var displacement = (
                road_transform.rotation.right_vector()
                * Float32(abs(width))
                * Float32(0.2)
            )
            position = position + displacement * Float32(direction)
            rotation = road_transform.rotation
            w = map._closest_lane_with_build_work(position, flags, work).value()
            road_transform = _signal_lane_pose(map, w, work)
            distance = (road_transform.location - position).length()
            width = _signal_lane_width(map, w, work)
            steps += 1
        if steps != 10:
            map.signals[i].transform.location = position
            map.signals[i].transform.rotation = rotation


def _signal_lane_pose(
    map: Map, waypoint: Waypoint, mut work: _MapBuildWork
) raises -> CarlaTransform:
    var at = map._locate_with_work(waypoint, work)
    _reserve_lane_scalars(map.roads[at[0]], at[1], work, 2)
    var terms = _reference_work(map.roads[at[0]], waypoint.s, waypoint.s)
    if terms < 0:
        raise Error("Sign relocation cannot resolve pose quadrature work")
    work.step()
    work.term(terms)
    work.term(terms)
    return map.roads[at[0]].lane_transform(at[1], at[2], waypoint.s)


def _signal_lane_width(
    map: Map, waypoint: Waypoint, mut work: _MapBuildWork
) raises -> Float64:
    var at = map._locate_with_work(waypoint, work)
    work.step(len(map.roads[at[0]].sections[at[1]].lanes[at[2]].info.widths))
    return map.roads[at[0]].lane_width(at[1], at[2], waypoint.s)


def _signal_lane_type(
    map: Map, waypoint: Waypoint, mut work: _MapBuildWork
) raises -> LaneType:
    var at = map._locate_with_work(waypoint, work)
    return map.roads[at[0]].sections[at[1]].lanes[at[2]].type


def _signal_side(
    map: Map, waypoint: Waypoint, right: Bool, mut work: _MapBuildWork
) raises -> Optional[Waypoint]:
    if waypoint.lane_id.value == 0:
        raise Error("Lane 0 has no lane beside it")
    var at = map._locate_with_work(waypoint, work)
    var outward = right == map.roads[at[0]].is_rht
    var id = waypoint.lane_id.value
    var out = waypoint
    if outward:
        out.lane_id = LaneId(id + 1 if id > 0 else id - 1)
    elif abs(id) == 1:
        out.lane_id = LaneId(-id)
    else:
        out.lane_id = LaneId(id - 1 if id > 0 else id + 1)
    work.step(len(map.roads[at[0]].sections[at[1]].lanes))
    if map.roads[at[0]].sections[at[1]].contains_lane(out.lane_id):
        return out
    return None


def _has(ids: List[RoadId], id: RoadId) -> Bool:
    for other in ids:
        if other == id:
            return True
    return False


def _sorted_set(ids: List[ControllerId]) -> List[ControllerId]:
    var out = List[ControllerId]()
    for id in ids:
        var at = 0
        while at < len(out) and out[at].value < id.value:
            at += 1
        if at < len(out) and out[at] == id:
            continue
        out.insert(at, id)
    return out^


def _sorted_signal_set(ids: List[SignalId]) -> List[SignalId]:
    var out = List[SignalId]()
    for id in ids:
        var at = 0
        while at < len(out) and out[at].value < id.value:
            at += 1
        if at < len(out) and out[at] == id:
            continue
        out.insert(at, id)
    return out^


def _sort_by_junction_id(mut junctions: List[Junction]):
    for i in range(1, len(junctions)):
        var j = i
        while j > 0 and junctions[j - 1].id.value > junctions[j].id.value:
            junctions.swap_elements(j - 1, j)
            j -= 1


def _sort_signals(mut signals: List[Signal]):
    for i in range(1, len(signals)):
        var j = i
        while (
            j > 0
            and signals[j - 1].signal_id.value > signals[j].signal_id.value
        ):
            signals.swap_elements(j - 1, j)
            j -= 1


def _sort_controllers(mut controllers: List[Controller]):
    for i in range(1, len(controllers)):
        var j = i
        while j > 0 and controllers[j - 1].id.value > controllers[j].id.value:
            controllers.swap_elements(j - 1, j)
            j -= 1
