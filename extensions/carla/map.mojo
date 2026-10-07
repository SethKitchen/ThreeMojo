# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's `road/Map`: the road network and every question a car asks it.

A `Map` holds the roads, the junctions, the signals and the signal
controllers of one OpenDRIVE file. A `Waypoint` is a place on it: a road,
a lane section, a lane and a distance s along the road. The map answers
where a waypoint is (`compute_transform`), what lies ahead of it (`next`,
`successors`), beside it (`right`, `left`) and on it (`mark_record`,
`signals_in_distance`), and which waypoint is nearest a point
(`closest_waypoint_on_road`, `waypoint`).

**Two segment indices.** The map keeps CARLA's heading and length
partition in its own R-tree. `closest_waypoint_on_road`, `waypoint` and
the sign check at load use it with CARLA's algorithm: the nearest segment,
then a step along the lane to the point's foot. These queries are fast and
always answer. They also keep CARLA's approximations: the step treats
distance along the segment chord as road s.

**The certified index.** `certified_closest_waypoint_on_road` and
`certified_waypoint` use a second index. It starts with CARLA's partition
and splits again at record boundaries and until quarter-point
chord errors are at most one millimeter. A required split without an
interior Float64 road-s value raises a resolution error. A positive
nonterminal index step must also advance in lane order. The line and its
stored-point minima can still be representable. This sampled target is not
an unsampled error bound. A separate full-center enclosure and the R-tree's
bounded distance key control candidate admission. An unknown bound keeps
the candidate. Each remaining candidate exports a bounded minimum-distance
certificate. Overlapping candidates resume with their remaining work budget.
Selection requires proved dominance; unresolved work raises an accuracy
error. Approximate witnesses require strict classification agreement across
all possible minimizing cells. An exact witness uses its proved minimizer.
Classification uses the Float64 center before public location narrowing.

Certified queries minimize three-dimensional distance to the stored canonical
Float64 lane center over the indexed station domains. Station s is the road
reference parameter, not lane chord length. Public `compute_transform` narrows
that same center. Road reference and fixed-s helpers describe separate geometry.
Segment indices resolve exact distance ties. A rounded station plateau keeps
its incumbent; the API does not promise the first station on that plateau.

The public `segment_count` and `segment` methods expose this accuracy-driven
index. Its partition and count can change when the geometry requires more
subdivision. Lane order and index tie rules remain deterministic. The
certified queries correct curved lane offsets and the treatment of lane
distance as road s. They cost more and can raise where CARLA's query
answers, so they are not the default.

The R-tree, full-center bounds, and optional sampled-curve box covers belong
to the same construction snapshot. Queries do not update these proofs.
As with the existing index, callers must rebuild the Map after editing its
source road records. A cover stores only four complete interval boxes; it
does not copy geometry or change the public segment partition.

**Order.** CARLA keeps roads, junctions and signals in hash maps and
walks them in hash order. This port walks them in order of id, so a list
such as `generate_waypoints` holds the same waypoints in a fixed order.

**Waypoints keep s in double.** CARLA steps a waypoint 10 `DBL_EPSILON`
off a section's edge, which a `Float32` cannot hold, so `Waypoint.s` is a
`Float64` in meters. Two waypoints are equal when their road, section and
lane match and s agrees to 5 millimeters, as CARLA's hash.

The methods that CARLA's client `Map`, `Waypoint` and `Landmark` add on
top, such as `next_until_lane_end`, `lane_change` and `landmark_group`,
are here as well.

Source: CARLA 1360bb9, `LibCarla/source/carla/road/Map.cpp`,
`road/Junction.h`, `road/Signal.h`, `road/SignalType.cpp`,
`road/Controller.h`, `road/Object.h`, `road/Deformation.h`,
`road/element/Waypoint.cpp`, `road/element/LaneCrossingCalculator.cpp`,
and `client/Map.cpp`, `client/Waypoint.cpp`, `client/Landmark.h`.
"""

from extensions.carla.curve_sum2 import _require_sum2_environment
from extensions.carla.geo import GeoLocation, GeoProjection
from extensions.carla.curve_bounds import _reference_work
from extensions.carla.map_search import (
    MapBuildBudget,
    MapQueryBudget,
    _MapBuildWork,
    _MapQueryWork,
)
from extensions.carla.map_validation import (
    _preflight_map_records,
    _reserve_lane_boundaries,
    _reserve_lane_scalars,
    _reserve_straightness,
)
from extensions.carla.geometry import SPIRAL
from extensions.carla.curve_interval import _Interval
from extensions.carla.spiral_domain_proof import (
    _SpiralRootCapture,
    _SpiralDomainProof,
    _find_spiral_proof,
    _try_pack_spiral_proof,
)
from extensions.carla.lane_box_cover import (
    _LaneBoxCover,
    _lane_cover_can_improve,
    _sampled_lane_box_cover_fast as _sampled_lane_box_cover,
)
from extensions.carla.curve_distance import (
    _finite_point,
    _wide_point_order,
)
from extensions.carla.lane_distance import (
    _wide_distance_upper,
)
from extensions.carla.lane_refinement import (
    _LaneCertificate,
    _LaneExclusionGoal,
    _indexed_curve_lower,
    _chord_certificate_capture_fast_with_nodes as _chord_certificate_capture_with_nodes,
    _ProofNodeWork,
    _lane_certificate_contains,
    _lane_box_can_improve,
    _lane_certificate_dominates,
    _lane_certificate_dominates_cells,
    _legacy_square,
    _midpoint,
    _next_resume_gap,
    _refine_lane_certificate,
    _continue_lane_certificate,
)
from extensions.carla.speed_limits import opendrive_speed, NUMERIC_SPEED_LIMIT
from extensions.carla.math import (
    distance_segment_to_point,
    make_unit_vector,
    vector_angle,
)
from extensions.carla.road import Lane, LaneKey, LaneSection, Road
from extensions.carla.road_info import (
    CHANGE_BOTH,
    CHANGE_LEFT,
    CHANGE_RIGHT,
    ConId,
    ControllerId,
    JuncId,
    LANE_BIDIRECTIONAL,
    LANE_BIKING,
    LANE_DRIVING,
    LANE_PARKING,
    LaneChange,
    LaneId,
    LaneMarking,
    LaneType,
    LaneValidity,
    RoadId,
    RoadInfoMarkRecord,
    RoadInfoSignal,
    SectionId,
    SignalId,
    SignalOrientation,
    info_at,
    info_index,
    infos_in_range,
    signal_orientation_of,
)
from extensions.carla.rtree import (
    SegmentCloudRtree,
    SegmentElement,
    SegmentFilter,
    _segment_distance2,
)
from extensions.carla.transform import CarlaRotation, CarlaTransform
from math.bounds import Box3
from math.vector3 import Vector3
from std.hashlib import Hasher
from std.math import ceil, floor, inf, isfinite, sin, sqrt
from std.memory import bitcast
from units.si import DEGREE, Angle, Length, METER, Velocity64

# CARLA's `EPSILON`: waypoints sit this far inside a section's edges.
comptime EPSILON = 10.0 * 2.220446049250313e-16
# `std::numeric_limits<double>::epsilon()`.
comptime DOUBLE_EPSILON = 2.220446049250313e-16


# --- waypoint -----------------------------------------------------------------


@fieldwise_init
struct Waypoint(Hashable, ImplicitlyCopyable, KeyElement, Writable):
    """A place on the road network, `road/element/Waypoint`."""

    var road_id: RoadId
    var section_id: SectionId
    var lane_id: LaneId
    # Meters along the road, in double; see the module docstring.
    var s: Float64

    def _bucket(self) -> Float64:
        return floor(self.s * 200.0)

    def __eq__(self, other: Self) -> Bool:
        """Return True if two waypoints are the same place, as CARLA's `==`.

        Args:
            other: The other waypoint.

        Returns:
            True if the road, section and lane match and `floor(200 s)`
            matches.
        """
        return (
            self.road_id == other.road_id
            and self.section_id == other.section_id
            and self.lane_id == other.lane_id
            and self._bucket() == other._bucket()
        )

    def __hash__[H: Hasher](self, mut hasher: H):
        """Hash what `__eq__` compares.

        Args:
            hasher: The hasher to feed.
        """
        self.road_id.value.__hash__(hasher)
        self.section_id.value.__hash__(hasher)
        self.lane_id.value.__hash__(hasher)
        Int(self._bucket()).__hash__(hasher)

    def write_to(self, mut writer: Some[Writer]):
        """Write the waypoint's fields.

        Args:
            writer: The destination.
        """
        writer.write(
            "Waypoint(road_id=",
            self.road_id.value,
            ", section_id=",
            self.section_id.value,
            ", lane_id=",
            self.lane_id.value,
            ", s=",
            self.s,
            ")",
        )


# --- junctions ----------------------------------------------------------------


@fieldwise_init
struct LaneLink(Equatable, ImplicitlyCopyable, Writable):
    """A junction's lane link: a lane of the incoming road to one of the
    connecting road, `Junction::LaneLink`."""

    var from_lane: LaneId
    var to_lane: LaneId


struct Connection(Copyable, Movable):
    """One road through a junction, `Junction::Connection`."""

    var id: ConId
    var incoming_road: RoadId
    var connecting_road: RoadId
    var lane_links: List[LaneLink]

    def __init__(
        out self, id: ConId, incoming_road: RoadId, connecting_road: RoadId
    ) raises:
        """Create a connection with no lane links.

        Args:
            id: The connection's id.
            incoming_road: The road that enters the junction.
            connecting_road: The junction road it continues on.

        Raises:
            Error: If an id is not valid.
        """
        if not (
            id.is_valid()
            and incoming_road.is_valid()
            and connecting_road.is_valid()
        ):
            raise Error("Connection id or road id is not valid")
        self.id = id
        self.incoming_road = incoming_road
        self.connecting_road = connecting_road
        self.lane_links = List[LaneLink]()


struct Junction(Copyable, Movable):
    """A junction, `road/Junction`."""

    var id: JuncId
    var name: String
    # In order of id.
    var connections: List[Connection]
    # The controller ids, sorted as a `std::set`.
    var controllers: List[ControllerId]
    # For each road with a conflict, the roads it crosses within 2 meters.
    var conflict_roads: List[RoadId]
    var conflicts: List[List[RoadId]]
    # Where the junction's lanes lie, in CARLA's frame.
    var bounding_box: Box3

    def __init__(out self, id: JuncId, name: String) raises:
        """Create a junction with no connections.

        Args:
            id: The junction's id.
            name: Its name.

        Raises:
            Error: If the id is not valid.
        """
        if not id.is_valid():
            raise Error("Junction id is not valid")
        self.id = id
        self.name = name
        self.connections = List[Connection]()
        self.controllers = List[ControllerId]()
        self.conflict_roads = List[RoadId]()
        self.conflicts = List[List[RoadId]]()
        self.bounding_box = Box3.empty()

    def connection_index(self, id: ConId) -> Int:
        """Return where a connection sits in `connections`.

        Args:
            id: The connection's id.

        Returns:
            Its index, or -1 if the junction has no such connection.
        """
        for i in range(len(self.connections)):
            if self.connections[i].id == id:
                return i
        return -1

    def road_has_conflicts(self, road: RoadId) -> Bool:
        """Return True if a road crosses another here, `RoadHasConflicts`.

        Args:
            road: The road.

        Returns:
            Whether it has conflicts.
        """
        for id in self.conflict_roads:
            if id == road:
                return True
        return False

    def conflicts_of_road(self, road: RoadId) raises -> List[RoadId]:
        """Return the roads a road crosses here, `GetConflictsOfRoad`.

        Args:
            road: The road.

        Returns:
            The roads it conflicts with, in the order they were found.

        Raises:
            Error: If the road has no conflicts.
        """
        for i in range(len(self.conflict_roads)):
            if self.conflict_roads[i] == road:
                return self.conflicts[i].copy()
        raise Error("The road has no conflicts in this junction")

    def location(self) -> Vector3:
        """Return the bounding box's center, CARLA's `location`.

        Returns:
            Half the sum of its corners, in meters.
        """
        var b = self.bounding_box
        return Vector3(
            0.5 * (b.max.x + b.min.x),
            0.5 * (b.max.y + b.min.y),
            0.5 * (b.max.z + b.min.z),
        )

    def extent(self) -> Vector3:
        """Return the bounding box's half size, CARLA's `extent`.

        Returns:
            Half the difference of its corners, in meters.
        """
        var b = self.bounding_box
        return Vector3(
            0.5 * (b.max.x - b.min.x),
            0.5 * (b.max.y - b.min.y),
            0.5 * (b.max.z - b.min.z),
        )


# --- signals ------------------------------------------------------------------


@fieldwise_init
struct SignalDependency(Copyable, Movable):
    """Another signal a signal depends on, `SignalDependency`."""

    var dependency_id: String
    var type: String


struct Signal(Copyable, Movable):
    """A traffic sign or light, `road/Signal`."""

    var road_id: RoadId
    var signal_id: SignalId
    # Meters along the road and to its left.
    var s: Float64
    var t: Float64
    var name: String
    var dynamic: String
    var orientation_text: String
    # Meters up from the road.
    var z_offset: Float64
    var country: String
    var type: String
    var subtype: String
    var value: Float64
    var value_present: Bool
    var unit: String
    # Meters.
    var height: Float64
    var width: Float64
    var text: String
    # Radians.
    var h_offset: Float64
    var pitch: Float64
    var roll: Float64
    var dependencies: List[SignalDependency]
    # Where the signal stands, in CARLA's frame.
    var transform: CarlaTransform
    # The controllers that hold it, sorted as a `std::set`.
    var controllers: List[ControllerId]
    # True if the file gave a `positionInertial`.
    var using_inertial_position: Bool

    def __init__(
        out self,
        road_id: RoadId,
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
    ) raises:
        """Create a signal from a file's `signal`.

        Args:
            road_id: The road it stands on.
            signal_id: Its id.
            s: Meters along the road.
            t: Meters to the left of the reference line.
            name: Its name.
            dynamic: "yes" for a signal that changes, such as a light.
            orientation: "+", "-" or anything else for both.
            z_offset: Meters up from the road.
            country: The code of the country whose catalog it is from.
            type: Its type in that catalog, such as "206".
            subtype: Its subtype.
            value: Its value, such as a speed.
            unit: The unit of the value.
            height: Its height, in meters.
            width: Its width, in meters.
            text: Its text.
            h_offset: The turn from the road's heading, in radians.
            pitch: Its pitch, in radians.
            roll: Its roll, in radians.
            value_present: Whether the file supplied a numeric value.

        Raises:
            Error: If an id is not valid.
        """
        if not (road_id.is_valid() and signal_id.is_valid()):
            raise Error("Road id or signal id is not valid")
        self.road_id = road_id
        self.signal_id = signal_id
        self.s = s
        self.t = t
        self.name = name
        self.dynamic = dynamic
        self.orientation_text = orientation
        self.z_offset = z_offset
        self.country = country
        self.type = type
        self.subtype = subtype
        self.value = value
        self.value_present = value_present
        self.unit = unit
        self.height = height
        self.width = width
        self.text = text
        self.h_offset = h_offset
        self.pitch = pitch
        self.roll = roll
        self.dependencies = List[SignalDependency]()
        self.transform = CarlaTransform(
            Length(0.0, METER),
            Length(0.0, METER),
            Length(0.0, METER),
            CarlaRotation(
                Angle(0.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE)
            ),
        )
        self.controllers = List[ControllerId]()
        self.using_inertial_position = False

    def speed_limit(self) raises -> Velocity64:
        """Interpret a speed signal with its explicit source unit.

        Returns:
            The finite nonnegative speed, retaining Float64 precision.

        Raises:
            Error: If this is not a speed signal, the value is absent,
                or its numeric value or explicit unit is invalid.
        """
        if self.type != SIGNAL_MAXIMUM_SPEED:
            raise Error("Only a speed signal has a speed limit")
        if not self.value_present:
            raise Error("A speed signal needs a numeric value")
        return opendrive_speed(self.value, self.unit)

    def is_dynamic(self) -> Bool:
        """Return True if the file says `dynamic="yes"`, `GetDynamic`."""
        return self.dynamic == "yes"

    def orientation(self) -> SignalOrientation:
        """Return which way the signal faces, `GetOrientation`.

        Returns:
            Positive for "+", negative for "-", both otherwise.
        """
        return signal_orientation_of(self.orientation_text)


struct Controller(Copyable, Movable):
    """A group of signals that change together, `road/Controller`."""

    var id: ControllerId
    var name: String
    var sequence: Int
    # Sorted as `std::set`s.
    var junctions: List[JuncId]
    var signals: List[SignalId]

    def __init__(
        out self, id: ControllerId, name: String, sequence: Int
    ) raises:
        """Create a controller with no signals.

        Args:
            id: The controller's id.
            name: Its name.
            sequence: Its `sequence`, the order it runs in.

        Raises:
            Error: If the id is not valid.
        """
        if not id.is_valid():
            raise Error("Controller id is not valid")
        self.id = id
        self.name = name
        self.sequence = sequence
        self.junctions = List[JuncId]()
        self.signals = List[SignalId]()


struct RoadObject(Copyable, Movable):
    """An OpenDRIVE object, `road/Object`.

    CARLA declares the fields and never fills them: it reads crosswalks as
    `RoadInfoCrosswalk` records and speed and stop stencils as signals.
    """

    var id: Int
    var type: String
    var name: String
    # Meters and radians, as OpenDRIVE writes them.
    var s: Float64
    var t: Float64
    var z_offset: Float64
    var valid_length: Float64
    var orientation: String
    var length: Float64
    var width: Float64
    var heading: Float64
    var pitch: Float64
    var roll: Float64

    def __init__(out self):
        """Create an object with every field zero or empty."""
        self.id = 0
        self.type = ""
        self.name = ""
        self.s = 0.0
        self.t = 0.0
        self.z_offset = 0.0
        self.valid_length = 0.0
        self.orientation = ""
        self.length = 0.0
        self.width = 0.0
        self.heading = 0.0
        self.pitch = 0.0
        self.roll = 0.0


# CARLA's `SignalType` catalog: the German StVO numbers OpenDRIVE uses.
comptime SIGNAL_DANGER = "101"
comptime SIGNAL_LANES_MERGING = "121"
comptime SIGNAL_CAUTION_PEDESTRIAN = "133"
comptime SIGNAL_CAUTION_BICYCLE = "138"
comptime SIGNAL_LEVEL_CROSSING = "150"
comptime SIGNAL_YIELD = "205"
comptime SIGNAL_STOP = "206"
comptime SIGNAL_MANDATORY_TURN_DIRECTION = "209"
comptime SIGNAL_MANDATORY_LEFT_RIGHT_DIRECTION = "211"
comptime SIGNAL_TWO_CHOICE_TURN_DIRECTION = "214"
comptime SIGNAL_ROUNDABOUT = "215"
comptime SIGNAL_PASS_RIGHT_LEFT = "222"
comptime SIGNAL_ACCESS_FORBIDDEN = "250"
comptime SIGNAL_ACCESS_FORBIDDEN_MOTORVEHICLES = "251"
comptime SIGNAL_ACCESS_FORBIDDEN_TRUCKS = "253"
comptime SIGNAL_ACCESS_FORBIDDEN_BICYCLE = "254"
comptime SIGNAL_ACCESS_FORBIDDEN_WEIGHT = "263"
comptime SIGNAL_ACCESS_FORBIDDEN_WIDTH = "264"
comptime SIGNAL_ACCESS_FORBIDDEN_HEIGHT = "265"
comptime SIGNAL_ACCESS_FORBIDDEN_WRONG_DIRECTION = "267"
comptime SIGNAL_FORBIDDEN_U_TURN = "272"
comptime SIGNAL_MAXIMUM_SPEED = "274"
comptime SIGNAL_FORBIDDEN_OVERTAKING_MOTORVEHICLES = "276"
comptime SIGNAL_FORBIDDEN_OVERTAKING_TRUCKS = "277"
comptime SIGNAL_ABSOLUTE_NO_STOP = "283"
comptime SIGNAL_RESTRICTED_STOP = "286"
comptime SIGNAL_HAS_WAY_NEXT_INTERSECTION = "301"
comptime SIGNAL_PRIORITY_WAY = "306"
comptime SIGNAL_PRIORITY_WAY_END = "307"
comptime SIGNAL_CITY_BEGIN = "310"
comptime SIGNAL_CITY_END = "311"
comptime SIGNAL_HIGHWAY = "330"
comptime SIGNAL_DEAD_END = "357"
comptime SIGNAL_RECOMMENDED_SPEED = "380"
comptime SIGNAL_RECOMMENDED_SPEED_END = "381"


def is_traffic_light(type: String) -> Bool:
    """Return True for a traffic light's type, `SignalType::IsTrafficLight`.

    Args:
        type: A signal's `type`.

    Returns:
        True for CARLA's nineteen traffic-light types.
    """
    var lights: List[String] = [
        "1000001",
        "1000002",
        "1000009",
        "1000010",
        "1000011",
        "1000007",
        "1000014",
        "1000015",
        "1000016",
        "1000017",
        "1000018",
        "1000019",
        "1000013",
        "1000020",
        "1000008",
        "1000012",
        "F",
        "W",
        "A",
    ]
    # The list is a constant and not empty.
    for light in lights:  # pragma: no branch
        if light == type:
            return True
    return False


# --- deformation --------------------------------------------------------------


def z_pos_in_deformation(x: Length, y: Length) -> Length:
    """Return CARLA's rolling road surface, `GetZPosInDeformation`.

    Two long sine waves across the map, 0.6 and 1.1 meters high.

    Args:
        x: Forward, in CARLA's frame.
        y: Right, in CARLA's frame.

    Returns:
        The height of the surface.
    """
    var px = x.value
    var py = y.value
    var z = Float32(0.6) * sin(
        Float32(0.035) * px + Float32(-0.08) * py + Float32(1000.0)
    ) + Float32(1.1) * sin(
        Float32(0.02) * px + Float32(0.05) * py + Float32(-1500.0)
    )
    return Length(z, METER)


def bump_deformation(x: Length, y: Length) -> Length:
    """Return CARLA's speed bumps, `GetBumpDeformation`.

    A bump sits on a grid of 17 by 12 meters and reaches 2 meters out.

    Args:
        x: Forward, in CARLA's frame.
        y: Right, in CARLA's frame.

    Returns:
        The height of the bump there, zero away from one.
    """
    var px = x.value
    var py = y.value
    var bump_x = ceil(px / Float32(17.0)) * Float32(17.0)
    var bump_y = floor(py / Float32(12.0)) * Float32(12.0)
    var dx = Float64(bump_x - px)
    var dy = Float64(bump_y - py)
    var d = Float32(sqrt(dx * dx + dy * dy))
    var offset = Float32(0)
    if d <= Float32(2.0):
        offset = sin(d)
    return Length(Float32(0.10) * offset, METER)


def map_deformation(x: Length, y: Length) -> Length:
    """Return both deformations, `Map::GetZPosInDeformation`.

    Args:
        x: Forward, in CARLA's frame.
        y: Right, in CARLA's frame.

    Returns:
        The rolling surface plus the bumps.
    """
    return z_pos_in_deformation(x, y) + bump_deformation(x, y)


# --- query results ------------------------------------------------------------


struct SignalSearchData(Copyable, Movable):
    """A signal found ahead of a waypoint, `Map::SignalSearchData`."""

    var signal: RoadInfoSignal
    # The waypoint where the signal applies.
    var waypoint: Waypoint
    # Meters from the search's start.
    var accumulated_s: Float64

    def __init__(
        out self,
        signal: RoadInfoSignal,
        waypoint: Waypoint,
        accumulated_s: Float64,
    ):
        """Create a result.

        Args:
            signal: The signal reference found.
            waypoint: Where it applies.
            accumulated_s: How far from the start, in meters.
        """
        self.signal = signal.copy()
        self.waypoint = waypoint
        self.accumulated_s = accumulated_s


struct Landmark(Copyable, Movable):
    """A signal reference seen from a waypoint, `client/Landmark`.

    `Map.signal(landmark.reference.signal_id)` gives the signal's fields.
    """

    # Where the landmark applies, or None when listed from the map.
    var waypoint: Optional[Waypoint]
    var reference: RoadInfoSignal
    # Meters from the search's start.
    var distance: Float64

    def __init__(
        out self,
        waypoint: Optional[Waypoint],
        reference: RoadInfoSignal,
        distance: Float64,
    ):
        """Create a landmark.

        Args:
            waypoint: Where it applies, or None.
            reference: The signal reference.
            distance: Meters from the search's start.
        """
        self.waypoint = waypoint
        self.reference = reference.copy()
        self.distance = distance


def _has_uniform_plan_classification(
    bounds: Tuple[_Interval, _Interval, _Interval],
    width: Float64,
    location: Vector3,
) -> Bool:
    # This controls only heuristic eligibility. The supplied full-curve box
    # must be the existing certified cache, never sampled chord padding.
    if (
        not bounds[0].is_finite()
        or not bounds[1].is_finite()
        or not bounds[2].is_finite()
        or not isfinite(width)
    ):
        return False
    if width <= 0.0:
        # Nonpositive widths retain the original initialization as well.
        return False
    var x = bounds[0] - _Interval.point(Float64(location.x))
    var y = bounds[1] - _Interval.point(Float64(location.y))
    if not x.is_finite() or not y.is_finite():
        return False
    var scale = max(width, max(x.magnitude(), y.magnitude()))
    var divisor = _Interval.point(scale)
    var diameter = _Interval.point(width) / divisor
    var difference = (
        _Interval.point(4.0) * ((x / divisor).square() + (y / divisor).square())
        - diameter.square()
    )
    # A strict inside bound or a closed outside bound covers every station.
    # Any uncertain crossing retains the original midpoint initialization.
    return difference.high < 0.0 or difference.low >= 0.0


def _use_projected_spiral_seed(
    road: Road,
    section: Int,
    lane: Int,
    low: Float64,
    high: Float64,
    bounds: Tuple[_Interval, _Interval, _Interval],
    location: Vector3,
) -> Bool:
    # ARC retains its original witness order and endpoint-proof eligibility.
    # Variable/transitioning width records retain their original choices too.
    var geometry_at = info_index(road.info.geometries, low)
    if geometry_at < 0 or info_index(road.info.geometries, high) != geometry_at:
        return False
    if road.info.geometries[geometry_at].geometry.kind != SPIRAL:
        return False
    ref widths = road.sections[section].lanes[lane].info.widths
    var width_at = info_index(widths, low)
    if width_at < 0 or info_index(widths, high) != width_at:
        return False
    ref width = widths[width_at].polynomial
    if width.b != 0.0 or width.c != 0.0 or width.d != 0.0:
        return False
    return _has_uniform_plan_classification(bounds, width.a, location)


def _projected_seed(
    start: Vector3,
    end: Vector3,
    first: Float64,
    second: Float64,
    location: Vector3,
) -> Float64:
    # Initial guess only. Stored Float32 coordinates are widened before
    # subtraction. A finite nonzero chord has a finite normal Float64 norm.
    # Degenerate/unsupported arithmetic retains the safe midpoint fallback.
    var low = min(first, second)
    var high = max(first, second)
    var seed = _midpoint(low, high)
    var dx = Float64(end.x) - Float64(start.x)
    var dy = Float64(end.y) - Float64(start.y)
    var dz = Float64(end.z) - Float64(start.z)
    var qx = Float64(location.x) - Float64(start.x)
    var qy = Float64(location.y) - Float64(start.y)
    var qz = Float64(location.z) - Float64(start.z)
    var denominator = dx * dx + dy * dy + dz * dz
    var numerator = qx * dx + qy * dy + qz * dz
    if denominator > 0.0 and isfinite(denominator) and isfinite(numerator):
        var ratio = min(max(numerator / denominator, 0.0), 1.0)
        var guess = first + (second - first) * ratio
        if isfinite(guess):
            seed = min(max(guess, low), high)
    return seed


@fieldwise_init
struct _Segment(ImplicitlyCopyable):
    var start: Vector3
    var end: Vector3
    var first: Waypoint
    var second: Waypoint
    var bounds: Tuple[_Interval, _Interval, _Interval]
    # -1 means the optional construction proof is absent.
    var cover_index: Int


@fieldwise_init
struct _CarlaSegment(ImplicitlyCopyable):
    # One piece of CARLA's `Map::CreateRtree` partition, before refinement.
    var start: Vector3
    var end: Vector3
    var first: Waypoint
    var second: Waypoint


@fieldwise_init
struct _LaneTypeFilter(ImplicitlyCopyable, SegmentFilter):
    # The tree keeps each segment's lane type as its end value.
    var mask: Int

    def accepts(self, element: SegmentElement) -> Bool:
        return (element.end_value & self.mask) != 0


def _polynomial_value(coefficients: List[Float64], t: Float64) -> Float64:
    var value = coefficients[len(coefficients) - 1]
    var i = len(coefficients) - 2
    while i >= 0:
        value = value * t + coefficients[i]
        i -= 1
    return value


def _polynomial_candidates(coefficients: List[Float64]) -> List[Float64]:
    # Rolle's theorem: the roots of each derivative partition the polynomial
    # into monotone intervals. Keep those partition points too. Thus repeated
    # roots need no residual tolerance and cannot disappear at a tangency.
    # Degree is at most five: recursion has five levels and at most thirty-one
    # interior candidates. Every sign-changing root gets 64 bounded bisections.
    if len(coefficients) == 1:
        return [0.0, 1.0]
    var derivative = List[Float64]()
    var index = 1
    while index < len(coefficients):
        derivative.append(Float64(index) * coefficients[index])
        index += 1
    var partition = _polynomial_candidates(derivative)
    var candidates: List[Float64] = [0.0]
    var i = 1
    while i < len(partition):
        var low = partition[i - 1]
        var high = partition[i]
        var before = _polynomial_value(coefficients, low)
        var after = _polynomial_value(coefficients, high)
        if (before < 0.0 and after > 0.0) or (before > 0.0 and after < 0.0):
            var iterations = 0
            while iterations < 64:
                iterations += 1
                var middle = low + (high - low) * 0.5
                var value = _polynomial_value(coefficients, middle)
                if (value < 0.0) == (before < 0.0):
                    low = middle
                else:
                    high = middle
            candidates.append(low + (high - low) * 0.5)
        candidates.append(partition[i])
        i += 1
    return candidates^


def _distance_is_convex(derivative: List[Float64]) -> Bool:
    # Bernstein coefficients of the quartic second derivative on [0,1].
    # Strict positive margin keeps roundoff away from the sign certificate.
    var a = derivative[1]
    var b = 2.0 * derivative[2]
    var c = 3.0 * derivative[3]
    var d = 4.0 * derivative[4]
    var e = 5.0 * derivative[5]
    var margin = (
        64.0 * DOUBLE_EPSILON * (abs(a) + abs(b) + abs(c) + abs(d) + abs(e))
    )
    return (
        min(
            min(a, a + b * 0.25),
            min(
                a + b * 0.5 + c / 6.0,
                min(a + b * 0.75 + c * 0.5 + d * 0.25, a + b + c + d + e),
            ),
        )
        > margin
    )


def _concat(var dst: List[Waypoint], var src: List[Waypoint]) -> List[Waypoint]:
    # CARLA's `ConcatVectors`: the longer list goes first.
    if len(src) > len(dst):
        return _concat(src^, dst^)
    dst.extend(src^)
    return dst^


def _concat_signals(
    var dst: List[SignalSearchData], var src: List[SignalSearchData]
) -> List[SignalSearchData]:
    if len(src) > len(dst):
        return _concat_signals(src^, dst^)
    dst.extend(src^)
    return dst^


def _cross(ax: Float64, ay: Float64, bx: Float64, by: Float64) -> Float64:
    return ax * by - ay * bx


def _point_segment_2d(
    px: Float64, py: Float64, ax: Float64, ay: Float64, bx: Float64, by: Float64
) -> Float64:
    var dx = bx - ax
    var dy = by - ay
    var l2 = dx * dx + dy * dy
    var t = 0.0
    if l2 > 0.0:
        t = min(max(((px - ax) * dx + (py - ay) * dy) / l2, 0.0), 1.0)
    var ex = px - (ax + t * dx)
    var ey = py - (ay + t * dy)
    return sqrt(ex * ex + ey * ey)


def segment_distance_2d(
    a1: Vector3, a2: Vector3, b1: Vector3, b2: Vector3
) -> Float64:
    """Return the plan distance between two segments, as Boost's.

    Args:
        a1: The first segment's start.
        a2: The first segment's end.
        b1: The second segment's start.
        b2: The second segment's end.

    Returns:
        Zero if they cross or touch, else the least distance from an end
        of one to the other, in meters. z is ignored.
    """
    var ax = Float64(a1.x)
    var ay = Float64(a1.y)
    var bx = Float64(a2.x)
    var by = Float64(a2.y)
    var cx = Float64(b1.x)
    var cy = Float64(b1.y)
    var dx = Float64(b2.x)
    var dy = Float64(b2.y)
    var d1 = _cross(bx - ax, by - ay, cx - ax, cy - ay)
    var d2 = _cross(bx - ax, by - ay, dx - ax, dy - ay)
    var d3 = _cross(dx - cx, dy - cy, ax - cx, ay - cy)
    var d4 = _cross(dx - cx, dy - cy, bx - cx, by - cy)
    if d1 * d2 < 0.0 and d3 * d4 < 0.0:
        return 0.0
    return min(
        min(
            _point_segment_2d(cx, cy, ax, ay, bx, by),
            _point_segment_2d(dx, dy, ax, ay, bx, by),
        ),
        min(
            _point_segment_2d(ax, ay, cx, cy, dx, dy),
            _point_segment_2d(bx, by, cx, cy, dx, dy),
        ),
    )


# --- the map ------------------------------------------------------------------


def _map_locate_with_work(
    roads: List[Road],
    index: Dict[Int, Int],
    waypoint: Waypoint,
    mut work: _MapBuildWork,
) raises -> Tuple[Int, Int, Int]:
    work.step()
    if not waypoint.road_id.is_valid():
        raise Error("Road id is not valid")
    var found = index.get(waypoint.road_id.value)
    if not found:
        raise Error("The map has no road with that id")
    var r = found.value()
    work.step(len(roads[r].sections))
    var section = roads[r].section_index(waypoint.section_id)
    work.step(len(roads[r].sections[section].lanes))
    var lane = roads[r].sections[section].lane_index(waypoint.lane_id)
    if lane < 0:
        raise Error("The section has no lane with that id")
    return (r, section, lane)


def _query_node_step_cost(
    lanes: Int, goal: Bool = False, witness: Bool = False
) raises -> Int:
    # A generic node has at most 3 edge centers, 42 seed centers, one
    # initial center and 4 Jets: at most 100*lanes profile visits.
    # Its 20 fixed units cover 16 node/cell operations, 2 selected-width
    # lookups, one tightened Taylor recheck, and one bounded tiny-cell
    # eligibility/depth check. The latter check
    # uses local words only and at most 5 depth iterations. A closed-cell
    # recheck uses its own node and at most one selected-width lookup.
    # A discrete leaf has at most 3 centers and 3 terminals. Including the
    # first node's initial center, 8*lanes+80 bounds its profile and fixed
    # work, which is <=100*lanes+20 for every valid lane count >=1.
    # A later solver with more centers/Jets needs a new audited inventory.
    # Goal search adds at most six bounded exclusion comparisons: natural,
    # post-seed natural, cached Taylor, tightened natural, tightened Taylor,
    # and fallback Taylor.
    # A closed-cell recheck has only one such comparison, mutually exclusive
    # with that path. Reserve these units before any goal node can execute.
    var fixed = 26 if goal else 20
    fixed += 16  # Stored-dispatch eligibility, cached cuts and split routing.
    if witness:
        # Retain the prior containing-model allowance so removing its reuse
        # does not increase effective budgets or change established node fees.
        # The fresh per-cell producer is already covered by the generic node.
        fixed += 14
    if witness:
        # Four exact challenger comparisons and one child-order check.
        # Eighteen more units cover at most three exported frontier entries
        # per visited node, at six bounded packing operations per entry.
        # Entry frontier packing is reserved separately before continuation.
        # One additional bounded support-localization operation.
        fixed += 26
    if lanes < 0 or lanes > (9223372036854775807 - fixed) // 100:
        raise Error("Map query profile work is not representable")
    return 100 * lanes + fixed


def _preflight_map_metadata(
    junctions: List[Junction],
    signals: List[Signal],
    controllers: List[Controller],
    mut work: _MapBuildWork,
) raises:
    work.record(len(junctions))
    work.record(len(signals))
    work.record(len(controllers))
    for junction in junctions:
        work.step()
        work.record(len(junction.connections))
        work.record(len(junction.controllers))
        work.record(len(junction.conflict_roads))
        work.record(len(junction.conflicts))
        for conflict in junction.conflicts:
            work.step()
            work.record(len(conflict))
        for connection in junction.connections:
            work.step()
            work.record(len(connection.lane_links))
    for signal in signals:
        work.step()
        work.record(len(signal.dependencies))
        work.record(len(signal.controllers))
    for controller in controllers:
        work.step()
        work.record(len(controller.signals))
        work.record(len(controller.junctions))


struct Map(Movable):
    """An OpenDRIVE road network, CARLA's `road::Map` and `MapData`.

    Build one with `MapBuilder` or with `load_opendrive`.
    """

    # In order of id.
    var roads: List[Road]
    var junctions: List[Junction]
    var signals: List[Signal]
    var controllers: List[Controller]
    var geo_reference: GeoLocation
    var geo_projection: GeoProjection
    var _road_index: Dict[Int, Int]
    var _segments: List[_Segment]
    # Immutable after construction, under the existing index snapshot's
    # source-record validity contract. No query-time geometry cache.
    var _sampled_covers: List[_LaneBoxCover]
    # Sparse, owner-local immutable proofs in public segment order. These
    # follow the same source-record snapshot contract as the existing index.
    var _spiral_proofs: List[_SpiralDomainProof]
    var _spiral_proof_units: Int
    var _tree: SegmentCloudRtree
    # CARLA's own heading and length partition. The default nearest
    # queries use it; the certified queries use the refined index above.
    var _carla_segments: List[_CarlaSegment]
    var _carla_tree: SegmentCloudRtree
    var _curve_deviation: Float64
    var _endpoint_scale: Float64
    var _construction_work: _MapBuildWork

    def __init__(
        out self,
        var roads: List[Road],
        var junctions: List[Junction],
        var signals: List[Signal],
        var controllers: List[Controller],
        budget: MapBuildBudget = MapBuildBudget(),
        _initial_work: Optional[_MapBuildWork] = None,
    ) raises:
        """Hold the data and cut the lanes into segments, `Map(MapData)`.

        Args:
            roads: The roads, in order of id.
            junctions: The junctions, in order of id.
            signals: The signals, in order of id.
            controllers: The controllers, in order of id.
            budget: Finite global spatial-construction limits.
            _initial_work: Internal continuation of a builder's admitted work.

        Raises:
            Error: If a lane's records are missing where the segments need
                them, an index endpoint is not finite in Float32 storage,
                or Float64 road-s resolution prevents a required split or
                a positive nonterminal index step, or the floating-point
                mode is not round-to-nearest with gradual underflow.
        """
        budget.validate()
        self._construction_work = _MapBuildWork(budget)
        if _initial_work:
            self._construction_work = _initial_work.value()
        self._construction_work.validate()
        if not _initial_work:
            _preflight_map_records(roads, self._construction_work)
            _preflight_map_metadata(
                junctions, signals, controllers, self._construction_work
            )
        self.roads = roads^
        self.junctions = junctions^
        self.signals = signals^
        self.controllers = controllers^
        self.geo_reference = GeoLocation()
        self.geo_projection = GeoProjection()
        self._road_index = Dict[Int, Int]()
        for i in range(len(self.roads)):
            self._construction_work.step()
            self._road_index[self.roads[i].id.value] = i
        self._segments = List[_Segment]()
        self._sampled_covers = List[_LaneBoxCover]()
        self._spiral_proofs = List[_SpiralDomainProof]()
        self._spiral_proof_units = 0
        self._tree = SegmentCloudRtree()
        self._carla_segments = List[_CarlaSegment]()
        self._carla_tree = SegmentCloudRtree()
        self._curve_deviation = 0.0
        self._endpoint_scale = 0.0
        self._create_segments()

    # --- lookups --------------------------------------------------------------

    def contains_road(self, id: RoadId) -> Bool:
        """Return True if the map has a road, `MapData::ContainsRoad`.

        Args:
            id: The road's id.

        Returns:
            Whether it is there.
        """
        return id.value in self._road_index

    def road_index(self, id: RoadId) raises -> Int:
        """Return where a road sits in `roads`, as `MapData::GetRoad`.

        Args:
            id: The road's id.

        Returns:
            Its index.

        Raises:
            Error: If the id is not valid or the map has no such road.
        """
        if not id.is_valid():
            raise Error("Road id is not valid")
        var found = self._road_index.get(id.value)
        if not Bool(found):
            raise Error("The map has no road with that id")
        return found.value()

    def road(ref self, id: RoadId) raises -> ref[origin_of(self.roads[0])] Road:
        """Return a road by id, `MapData::GetRoad`.

        Args:
            id: The road's id.

        Returns:
            The road.

        Raises:
            Error: If the map has no such road.
        """
        return self.roads[self.road_index(id)]

    def _locate(self, waypoint: Waypoint) raises -> Tuple[Int, Int, Int]:
        var r = self.road_index(waypoint.road_id)
        var section = self.roads[r].section_index(waypoint.section_id)
        var lane = self.roads[r].sections[section].lane_index(waypoint.lane_id)
        if lane < 0:
            raise Error("The section has no lane with that id")
        return (r, section, lane)

    def _locate_with_work(
        self, waypoint: Waypoint, mut work: _MapBuildWork
    ) raises -> Tuple[Int, Int, Int]:
        return _map_locate_with_work(
            self.roads, self._road_index, waypoint, work
        )

    def _build_locate(
        mut self, waypoint: Waypoint
    ) raises -> Tuple[Int, Int, Int]:
        return _map_locate_with_work(
            self.roads, self._road_index, waypoint, self._construction_work
        )

    def _query_locate(
        self, waypoint: Waypoint, mut work: _MapQueryWork
    ) raises -> Tuple[Int, Int, Int]:
        work._step()
        var r = self.road_index(waypoint.road_id)
        work._step(len(self.roads[r].sections))
        var section = self.roads[r].section_index(waypoint.section_id)
        work._step(len(self.roads[r].sections[section].lanes))
        var lane = self.roads[r].sections[section].lane_index(waypoint.lane_id)
        if lane < 0:
            raise Error("The section has no lane with that id")
        return (r, section, lane)

    def _key(self, key: LaneKey) raises -> Tuple[Int, Int, Int]:
        return self._locate(
            Waypoint(key.road_id, key.section_id, key.lane_id, 0.0)
        )

    def lane(
        ref self, waypoint: Waypoint
    ) raises -> ref[origin_of(self.roads[0].sections[0].lanes[0])] Lane:
        """Return a waypoint's lane, `Map::GetLane`.

        Args:
            waypoint: The waypoint.

        Returns:
            The lane.

        Raises:
            Error: If the map has no such road, section or lane.
        """
        var at = self._locate(waypoint)
        return self.roads[at[0]].sections[at[1]].lanes[at[2]]

    def junction_index(self, id: JuncId) -> Int:
        """Return where a junction sits in `junctions`.

        Args:
            id: The junction's id.

        Returns:
            Its index, or -1 if the map has no such junction.
        """
        for i in range(len(self.junctions)):
            if self.junctions[i].id == id:
                return i
        return -1

    def junction(
        ref self, id: JuncId
    ) raises -> ref[origin_of(self.junctions[0])] Junction:
        """Return a junction by id, `Map::GetJunction`.

        Args:
            id: The junction's id.

        Returns:
            The junction.

        Raises:
            Error: If the id is not valid or the map has no such junction.
        """
        if not id.is_valid():
            raise Error("Junction id is not valid")
        var at = self.junction_index(id)
        if at < 0:
            raise Error("The map has no junction with that id")
        return self.junctions[at]

    def signal(
        ref self, id: SignalId
    ) raises -> ref[origin_of(self.signals[0])] Signal:
        """Return a signal by id.

        Args:
            id: The signal's id.

        Returns:
            The signal.

        Raises:
            Error: If the id is not valid or the map has no such signal.
        """
        if not id.is_valid():
            raise Error("Signal id is not valid")
        for i in range(len(self.signals)):
            if self.signals[i].signal_id == id:
                return self.signals[i]
        raise Error("The map has no signal with that id")

    def controller(
        ref self, id: ControllerId
    ) raises -> ref[origin_of(self.controllers[0])] Controller:
        """Return a controller by id.

        Args:
            id: The controller's id.

        Returns:
            The controller.

        Raises:
            Error: If the id is not valid or the map has no such
                controller.
        """
        if not id.is_valid():
            raise Error("Controller id is not valid")
        for i in range(len(self.controllers)):
            if self.controllers[i].id == id:
                return self.controllers[i]
        raise Error("The map has no controller with that id")

    # --- lane geometry ----------------------------------------------------------

    def _start_of_lane(self, road: Int, section: Int, lane: Int) -> Float64:
        # `GetDistanceAtStartOfLane`.
        ref r = self.roads[road]
        var s = r.sections[section].s
        var inset = min(10.0 * EPSILON, r.section_length(section) / 4.0)
        if r.is_positive_direction(r.sections[section].lanes[lane].id):
            return s + inset
        return s + r.section_length(section) - inset

    def _end_of_lane(self, road: Int, section: Int, lane: Int) -> Float64:
        # `GetDistanceAtEndOfLane`.
        ref r = self.roads[road]
        var s = r.sections[section].s
        var inset = min(10.0 * EPSILON, r.section_length(section) / 4.0)
        if not r.is_positive_direction(r.sections[section].lanes[lane].id):
            return s + inset
        return s + r.section_length(section) - inset

    def compute_transform(self, waypoint: Waypoint) raises -> CarlaTransform:
        """Return where a waypoint is, `Map::ComputeTransform`.

        Narrow the same canonical Float64 lane center used by nearest queries.
        Station s is the road-reference parameter, not lane chord length.

        Args:
            waypoint: The waypoint.

        Returns:
            Its lane's center at s, facing the way the lane runs.

        Raises:
            Error: If the lane is not in the map, s is off the road, or a
                SPIRAL uses an unsupported floating-point mode.
        """
        var at = self._locate(waypoint)
        return self.roads[at[0]].lane_transform(at[1], at[2], waypoint.s)

    def lane_type(self, waypoint: Waypoint) raises -> LaneType:
        """Return a waypoint's lane type, `Map::GetLaneType`.

        Args:
            waypoint: The waypoint.

        Returns:
            The lane's type.

        Raises:
            Error: If the lane is not in the map.
        """
        return self.lane(waypoint).type

    def speed_limit_at(self, waypoint: Waypoint) raises -> Optional[Velocity64]:
        """Return the lane limit at a waypoint, falling back to its road.

        Args:
            waypoint: The checked road, section, lane and station.

        Returns:
            A finite typed speed, including a numeric zero. None means the
            road state has no numeric limit; the source record keeps whether
            it is unrestricted, undefined or absent. Signals take precedence
            when the simulation applies them.

        Raises:
            Error: If the waypoint or a mutable speed record is invalid.
        """
        var location = self._locate(waypoint)
        ref road = self.roads[location[0]]
        if (
            not isfinite(waypoint.s)
            or waypoint.s < 0
            or waypoint.s > road.length
        ):
            raise Error(
                "Speed-limit station must be finite and within the road"
            )
        ref lane = road.sections[location[1]].lanes[location[2]]
        var lane_speed = info_at(lane.info.speeds, waypoint.s)
        if Bool(lane_speed):
            if lane_speed.value().kind != NUMERIC_SPEED_LIMIT:
                raise Error("A lane speed must be numeric")
            return lane_speed.value().limit()
        var road_speed = info_at(road.info.speeds, waypoint.s)
        if Bool(road_speed):
            return road_speed.value().limit()
        return None

    def lane_width(self, waypoint: Waypoint) raises -> Length:
        """Return a waypoint's lane width, `Map::GetLaneWidth`.

        Args:
            waypoint: The waypoint.

        Returns:
            The width at the waypoint's s.

        Raises:
            Error: If the lane is not in the map, s is past the road's end,
                or no width record holds at s.
        """
        var at = self._locate(waypoint)
        ref road = self.roads[at[0]]
        if waypoint.s > road.length:
            raise Error("s is past the end of the road")
        var width = info_at(
            road.sections[at[1]].lanes[at[2]].info.widths, waypoint.s
        )
        if not Bool(width):
            raise Error("The lane has no width record at s")
        return Length(
            Float32(width.value().polynomial.evaluate(waypoint.s)), METER
        )

    def lane_width_meters(self, waypoint: Waypoint) raises -> Float64:
        """Return a waypoint's lane width in double, as CARLA computes it.

        Args:
            waypoint: The waypoint.

        Returns:
            The width at the waypoint's s, in meters.

        Raises:
            Error: If `lane_width` would.
        """
        var at = self._locate(waypoint)
        ref road = self.roads[at[0]]
        if waypoint.s > road.length:
            raise Error("s is past the end of the road")
        var width = info_at(
            road.sections[at[1]].lanes[at[2]].info.widths, waypoint.s
        )
        if not Bool(width):
            raise Error("The lane has no width record at s")
        return width.value().polynomial.evaluate(waypoint.s)

    def junction_id(self, road: RoadId) raises -> JuncId:
        """Return the junction a road belongs to, `Map::GetJunctionId`.

        Args:
            road: The road's id.

        Returns:
            The junction's id, or `NO_JUNCTION`.

        Raises:
            Error: If the map has no such road.
        """
        return self.road(road).junction_id

    def is_junction(self, road: RoadId) raises -> Bool:
        """Return True if a road is in a junction, `Map::IsJunction`.

        Args:
            road: The road's id.

        Returns:
            Whether it is.

        Raises:
            Error: If the map has no such road.
        """
        return self.road(road).is_junction

    def is_positive_direction(self, waypoint: Waypoint) raises -> Bool:
        """Return True if a waypoint's lane runs with s.

        Args:
            waypoint: The waypoint.

        Returns:
            `Lane::IsPositiveDirection` for its lane.

        Raises:
            Error: If the lane is not in the map.
        """
        var at = self._locate(waypoint)
        return self.roads[at[0]].is_positive_direction(waypoint.lane_id)

    def mark_record(
        self, waypoint: Waypoint
    ) raises -> Tuple[
        Optional[RoadInfoMarkRecord], Optional[RoadInfoMarkRecord]
    ]:
        """Return the marks on a lane's two edges, `Map::GetMarkRecord`.

        Args:
            waypoint: The waypoint.

        Returns:
            The mark on the lane's own outer edge, then the mark on its
            inner edge: the outer mark of the next lane in. Both are None
            for lane 0.

        Raises:
            Error: If the lane or the lane inside it is not in the map, or
                s is past the road's end.
        """
        if waypoint.lane_id.value == 0:
            return (None, None)
        var at = self._locate(waypoint)
        ref road = self.roads[at[0]]
        if waypoint.s > road.length:
            raise Error("s is past the end of the road")
        var inner_id = waypoint.lane_id.value - 1
        if waypoint.lane_id.value < 0:
            inner_id = waypoint.lane_id.value + 1
        ref section = road.sections[at[1]]
        var inner = section.lane_index(LaneId(inner_id))
        if inner < 0:
            raise Error("The section has no lane inside that one")
        return (
            info_at(section.lanes[at[2]].info.marks, waypoint.s),
            info_at(section.lanes[inner].info.marks, waypoint.s),
        )

    # --- nearest waypoint -----------------------------------------------------

    def closest_waypoint_on_road(
        self, location: Vector3, lane_type: LaneType = LANE_DRIVING
    ) raises -> Optional[Waypoint]:
        """Return the waypoint nearest a point, `GetClosestWaypointOnRoad`.

        CARLA finds the nearest segment of a lane of the given types, then
        steps from the segment's start by the distance along it to the
        point's foot. The segments are CARLA's heading and length partition.
        For the certified nearest center, use
        `certified_closest_waypoint_on_road`.

        Args:
            location: The point, in CARLA's frame.
            lane_type: The lane types to search.

        Returns:
            The waypoint, or None if the map has no lane of those types.

        Raises:
            Error: If the mask is not valid.
        """
        if not lane_type.is_valid():
            raise Error("Lane type is not valid")
        var found = self._carla_tree.get_nearest_neighbours_with_filter(
            location, _LaneTypeFilter(lane_type.value)
        )
        if len(found) == 0:
            return None
        ref segment = self._carla_segments[found[0].start_value]
        var along = distance_segment_to_point(
            location, segment.start, segment.end
        )
        var start = segment.first
        var end = segment.second
        var delta = Float64(along[0].value)
        var forward = self.is_positive_direction(start)
        var final_s = start.s + delta if forward else start.s - delta
        var past = final_s >= end.s if forward else final_s <= end.s
        if past:
            return end
        if delta <= 0.0:
            return start
        # The foot lies inside the segment's lane, so one step stays in it.
        return self.next(start, delta)[0]

    def waypoint(
        self, location: Vector3, lane_type: LaneType = LANE_DRIVING
    ) raises -> Optional[Waypoint]:
        """Return the waypoint under a point, `Map::GetWaypoint`.

        This is CARLA's query: the nearest waypoint from
        `closest_waypoint_on_road`, kept if the point is within half the
        lane's width of it in plan. For the certified query, use
        `certified_waypoint`.

        Args:
            location: The point, in CARLA's frame.
            lane_type: The lane types to search.

        Returns:
            The nearest waypoint if the point lies within half its lane's
            width of it in plan, or None.

        Raises:
            Error: If the mask is not valid, or the lane has no width
                record at the waypoint.
        """
        var found = self.closest_waypoint_on_road(location, lane_type)
        if not Bool(found):
            return None
        var w = found.value()
        var at = self.compute_transform(w).location
        var dx = at.x - location.x
        var dy = at.y - location.y
        var dist = Float64(sqrt(dx * dx + dy * dy))
        if dist < self.lane_width_meters(w) * 0.5:
            return w
        return None

    def certified_closest_waypoint_on_road(
        self,
        location: Vector3,
        lane_type: LaneType = LANE_DRIVING,
        budget: MapQueryBudget = MapQueryBudget(),
    ) raises -> Optional[Waypoint]:
        """Return the certified nearest waypoint to a point.

        This query is not CARLA's. It is slower than
        `closest_waypoint_on_road`, and it can raise where that query
        answers.

        Minimize three-dimensional distance to the stored Float64 canonical
        lane center over the indexed domains. The returned s is road-reference
        station, not lane chord length. Public compute_transform narrows that
        same center. A rounded plateau need not return its first station.
        R-tree and full-center bounds admit eligible candidates.
        Segment indices resolve proved exact-distance ties.
        Certified full-center boxes can exclude strictly farther candidates.
        Minimum-distance certificates select among the remaining candidates.
        Overlaps resume retained cells within the original cumulative limits.
        An overlap that cannot be resolved within those limits raises.

        Args:
            location: The point, in CARLA's frame.
            lane_type: The lane types to search.
            budget: Finite cumulative candidate, refinement, and index limits.

        Returns:
            The waypoint, or None if the map has no lane of those types.

        Raises:
            Error: If the mask is not valid, a center is not finite, or
                refinement exhausts its numerical or work limit, or candidate
                minimum bounds overlap without a dominance proof, or the
                floating-point mode is not round-to-nearest with gradual
                underflow.
        """
        var found = self._closest_lane(location, lane_type, budget)
        if not Bool(found):
            return None
        return found.value()[0]

    def _closest_lane(
        self,
        location: Vector3,
        lane_type: LaneType,
        budget: MapQueryBudget = MapQueryBudget(),
    ) raises -> Optional[Tuple[Waypoint, Float64, Array[Float64, 3]]]:
        var found = self._closest_lane_certificate(location, lane_type, budget)
        if not Bool(found):
            return None
        ref selected = found.value()
        var query: Array[Float64, 3] = [
            Float64(location.x),
            Float64(location.y),
            Float64(location.z),
        ]
        return (
            selected[0],
            _legacy_square(selected[1].point, query),
            selected[1].point.copy(),
        )

    def _closest_lane_certificate(
        self,
        location: Vector3,
        lane_type: LaneType,
        budget: MapQueryBudget = MapQueryBudget(),
    ) raises -> Optional[Tuple[Waypoint, _LaneCertificate]]:
        var work = _MapQueryWork(budget)
        return self._closest_lane_certificate_with_work(
            location, lane_type, work
        )

    def _closest_lane_certificate_with_work(
        self, location: Vector3, lane_type: LaneType, mut work: _MapQueryWork
    ) raises -> Optional[Tuple[Waypoint, _LaneCertificate]]:
        work.validate()
        if not lane_type.is_valid():
            raise Error("Lane type is not valid")
        var query: Array[Float64, 3] = [
            Float64(location.x),
            Float64(location.y),
            Float64(location.z),
        ]
        _finite_point(query)
        _require_sum2_environment()
        var indices = List[Int]()
        var certificates = List[_LaneCertificate]()
        var waypoints = List[Waypoint]()
        var accurate = List[Bool]()
        var best = -1
        var frontier = self._tree._nearest_begin(location, work)
        var best_radius = Float64(0.0)
        while True:
            var candidate = self._tree._nearest_next(
                location, _LaneTypeFilter(lane_type.value), frontier, work
            )
            if not candidate:
                break
            var index = candidate.value().start_value
            ref segment = self._segments[index]
            if best >= 0:
                var lower = _indexed_curve_lower(
                    _segment_distance2(segment.start, segment.end, location),
                    self._curve_deviation,
                )
                if lower > best_radius:
                    break
                if not _lane_box_can_improve(
                    segment.bounds, location, certificates[best].point
                ):
                    continue
                if segment.cover_index >= 0:
                    if not _lane_cover_can_improve(
                        self._sampled_covers[segment.cover_index],
                        location,
                        certificates[best].point,
                    ):
                        continue
            # Candidate storage is admitted before refinement or any append.
            work.candidate()
            var result = self._nearest_on_segment_certificate(
                index, location, work, seed_only=True
            )
            var improves = best < 0
            if best >= 0:
                var order = _wide_point_order(
                    result[1].point, certificates[best].point, query
                )
                improves = order < 0 or (order == 0 and index < indices[best])
            if improves:
                best = len(indices)
                best_radius = _wide_distance_upper(result[1].point, query)
            work._step(len(result[1].cells) + 1)
            indices.append(index)
            waypoints.append(result[0])
            certificates.append(result[1].copy())
            accurate.append(result[1].exact_witness)
        if best < 0:
            return None
        # Admission's strict full-domain exclusions remain valid
        # as these retained candidates improve their stored incumbents.
        var requested_gaps = List[Float64]()
        var requested_scales = List[Float64]()
        for certificate in certificates:
            work._step(2)
            requested_gaps.append(inf[DType.float64]())
            requested_scales.append(certificate.scale)
        while True:
            # A resumed candidate can change the best stored sample. Recheck
            # all index-sensitive dominance relations after every refinement.
            for i in range(len(indices)):
                work._step()
                var order = _wide_point_order(
                    certificates[i].point, certificates[best].point, query
                )
                if order < 0 or (order == 0 and indices[i] < indices[best]):
                    best = i
            if not accurate[best]:
                # A seed or goal-closed candidate is not an accurate result.
                # Finish the current winner under the original local accuracy
                # and the same cumulative counters before selecting a pose.
                self._resume_on_segment_certificate(
                    indices[best],
                    location,
                    certificates[best],
                    None,
                    certificates[best].scale,
                    work,
                )
                accurate[best] = True
                waypoints[best].s = certificates[best].s
            var target = -1
            for i in range(len(indices)):
                work._step()
                if i == best:
                    continue
                if _lane_certificate_dominates(
                    certificates[best],
                    indices[best],
                    certificates[i],
                    indices[i],
                    query,
                ):
                    continue
                # The terminal-aware proof scans the retained cover only
                # after the constant-time bound did not establish dominance.
                work._step(len(certificates[i].cells))
                if _lane_certificate_dominates_cells(
                    certificates[best],
                    indices[best],
                    certificates[i],
                    indices[i],
                    query,
                ):
                    continue
                if (
                    certificates[best].exact_witness
                    and certificates[i].exact_witness
                ):
                    raise Error(
                        "Exact lane witnesses have inconsistent dominance"
                    )
                target = i
                # Dominance needs a tighter lower bound on the competitor.
                # The current winner contributes an actual scalar witness;
                # proving its own exact minimum is unnecessary here. If the
                # competitor finds a closer witness, the next pass switches
                # the winner and refines this candidate in its new role.
                break
            if target < 0:
                # A valid wide center does not by itself guarantee that the
                # selected public pose is finite and has a valid frame.
                self._validate_query_pose(waypoints[best], work)
                work._step(len(certificates[best].cells))
                return (waypoints[best], certificates[best].copy())
            var request = _next_resume_gap(
                certificates[target],
                requested_gaps[target],
                requested_scales[target],
            )
            requested_gaps[target] = request
            requested_scales[target] = certificates[target].scale
            self._resume_on_segment_certificate(
                indices[target],
                location,
                certificates[target],
                request,
                requested_scales[target],
                work,
                _LaneExclusionGoal(
                    certificates[best].upper,
                    certificates[best].scale,
                    indices[best] < indices[target],
                ),
                certificates[best].point.copy(),
            )
            accurate[target] = certificates[target].exact_witness
            waypoints[target].s = certificates[target].s

    def _resume_on_segment_certificate(
        self,
        index: Int,
        location: Vector3,
        mut certificate: _LaneCertificate,
        requested_gap: Optional[Float64],
        request_scale: Float64,
        mut work: _MapQueryWork,
        goal: Optional[_LaneExclusionGoal] = None,
        external_witness: Optional[Array[Float64, 3]] = None,
    ) raises:
        var previous_nodes = certificate.nodes
        var previous_terms = certificate.terms
        ref segment = self._segments[index]
        var at = self._query_locate(segment.first, work)
        var lane_count = len(self.roads[at[0]].sections[at[1]].lanes)
        work._step(lane_count)
        work._step_product(4, len(certificate.cells))
        if external_witness:
            # Reserve invocation validation and packing of the old frontier.
            # New entries are covered by the witness-specific node debit.
            work._step(6)
            work._step_product(6, len(certificate.cells))
        var node_cost = _query_node_step_cost(
            lane_count, Bool(goal), Bool(external_witness)
        )
        _continue_lane_certificate(
            self.roads[at[0]],
            at[1],
            at[2],
            min(segment.first.s, segment.second.s),
            max(segment.first.s, segment.second.s),
            location,
            certificate,
            requested_gap,
            request_scale,
            max_nodes=work.node_cap(previous_nodes, node_cost),
            max_terms=work.term_cap(previous_terms),
            spiral_proof=_find_spiral_proof(self._spiral_proofs, index),
            goal=goal,
            external_witness=external_witness,
        )
        work.charge(
            certificate.nodes - previous_nodes,
            certificate.terms - previous_terms,
            node_cost,
        )

    def _nearest_on_segment(
        self, index: Int, location: Vector3
    ) raises -> Tuple[Waypoint, Float64, Array[Float64, 3]]:
        var work = _MapQueryWork(MapQueryBudget())
        work.candidate()
        var result = self._nearest_on_segment_certificate(index, location, work)
        var query: Array[Float64, 3] = [
            Float64(location.x),
            Float64(location.y),
            Float64(location.z),
        ]
        return (
            result[0],
            _legacy_square(result[1].point, query),
            result[1].point.copy(),
        )

    def _nearest_on_segment_certificate(
        self,
        index: Int,
        location: Vector3,
        mut work: _MapQueryWork,
        seed_only: Bool = False,
    ) raises -> Tuple[Waypoint, _LaneCertificate]:
        ref segment = self._segments[index]
        var waypoint = segment.first
        var at = self._query_locate(waypoint, work)
        var lane_count = len(self.roads[at[0]].sections[at[1]].lanes)
        work._step(lane_count)
        var node_cost = _query_node_step_cost(lane_count)
        var low = min(segment.first.s, segment.second.s)
        var high = max(segment.first.s, segment.second.s)
        var seed = _midpoint(low, high)
        if _use_projected_spiral_seed(
            self.roads[at[0]],
            at[1],
            at[2],
            low,
            high,
            segment.bounds,
            location,
        ):
            seed = _projected_seed(
                segment.start,
                segment.end,
                segment.first.s,
                segment.second.s,
                location,
            )
        # This is not an admission, monotonicity, or accuracy certificate.
        # The canonical evaluator and unchanged bounded search still verify
        # the complete actual curve and charge every evaluated scalar point.
        var result = _refine_lane_certificate(
            self.roads[at[0]],
            at[1],
            at[2],
            low,
            high,
            location,
            seed,
            0.0,
            max_nodes=work.node_cap(step_cost=node_cost),
            max_terms=work.term_cap(),
            spiral_proof=_find_spiral_proof(self._spiral_proofs, index),
            seed_only=seed_only,
        )
        work.charge(result.nodes, result.terms, node_cost)
        waypoint.s = result.s
        return (waypoint, result^)

    def certified_waypoint(
        self,
        location: Vector3,
        lane_type: LaneType = LANE_DRIVING,
        budget: MapQueryBudget = MapQueryBudget(),
    ) raises -> Optional[Waypoint]:
        """Return the certified waypoint under a point.

        This query is not CARLA's. It is slower than `waypoint`, and it can
        raise where that query answers.

        Select by canonical three-dimensional lane-center distance. Then
        require strict planar distance below half the width at the proved
        minimizer. Approximate witnesses require all possible minimizing
        cells to agree. An exact half-width boundary is outside.

        Args:
            location: The point, in CARLA's frame.
            lane_type: The lane types to search.
            budget: Finite cumulative candidate, refinement, and index limits.

        Returns:
            The nearest waypoint if the point lies within half its lane's
            width of it in plan, or None.

        Raises:
            Error: If the mask is not valid, a center or width is not finite,
                the width record is absent, refinement exhausts a limit, or
                lane selection or strict cell classification is unresolved,
                or the floating-point mode is not round-to-nearest with
                gradual underflow.
        """
        var work = _MapQueryWork(budget)
        var found = self._closest_lane_certificate_with_work(
            location, lane_type, work
        )
        if not Bool(found):
            return None
        ref selected = found.value()
        var w = selected[0]
        var at = self._query_locate(w, work)
        work._step(len(selected[1].cells))
        var certificate = selected[1].copy()
        var node_cost = _query_node_step_cost(
            len(self.roads[at[0]].sections[at[1]].lanes)
        )
        var previous_nodes = certificate.nodes
        var previous_terms = certificate.terms
        var contained = _lane_certificate_contains(
            self.roads[at[0]],
            at[1],
            at[2],
            location,
            certificate,
            max_nodes=work.node_cap(previous_nodes, node_cost),
            max_terms=work.term_cap(previous_terms),
        )
        work.charge(
            certificate.nodes - previous_nodes,
            certificate.terms - previous_terms,
            node_cost,
        )
        if contained:
            return w
        return None

    def _closest_lane_with_build_work(
        self, location: Vector3, lane_type: LaneType, mut work: _MapBuildWork
    ) raises -> Optional[Waypoint]:
        work.validate()
        # CARLA's sign check uses `GetClosestWaypointOnRoad`. Charge the
        # R-tree's worst case, one visit per segment, and the lane step.
        work.step(len(self._carla_segments) + 1)
        return self.closest_waypoint_on_road(location, lane_type)

    def _validate_query_pose(
        self, waypoint: Waypoint, mut work: _MapQueryWork
    ) raises:
        var at = self._query_locate(waypoint, work)
        work._step_product(4, len(self.roads[at[0]].sections[at[1]].lanes))
        var terms = _reference_work(self.roads[at[0]], waypoint.s, waypoint.s)
        if terms < 0:
            raise Error("Selected lane pose has unresolved quadrature work")
        # Two separately checked debits avoid overflow in twice-the-cost.
        work.charge(1, terms)
        work.charge(0, terms)
        _ = self.roads[at[0]].lane_transform(at[1], at[2], waypoint.s)

    def waypoint_xodr(
        self, road_id: RoadId, lane_id: LaneId, s: Length
    ) raises -> Optional[Waypoint]:
        """Return the waypoint at a road, a lane and an s, `GetWaypoint`.

        CARLA takes s as a `float`, as `Length` holds it.

        Args:
            road_id: The road.
            lane_id: The lane.
            s: The distance along the road.

        Returns:
            The waypoint in the first section at s that has the lane, or
            None if the road, the lane or s is not on the map.

        Raises:
            Error: If an id is not valid.
        """
        if not (road_id.is_valid() and lane_id.is_valid()):
            raise Error("Road id or lane id is not valid")
        if not self.contains_road(road_id):
            return None
        ref road = self.road(road_id)
        var at = Float64(s.value)
        if s.value < 0.0 or at >= road.length:
            return None
        for index in road.sections_at(at):
            if road.sections[index].contains_lane(lane_id):
                return Waypoint(road_id, road.sections[index].id, lane_id, at)
        return None

    # --- walking the network --------------------------------------------------

    def successors(self, waypoint: Waypoint) raises -> List[Waypoint]:
        """Return the start of each lane a waypoint's lane leads to.

        This is `Map::GetSuccessors`. Lane 0 is left out.

        Args:
            waypoint: The waypoint.

        Returns:
            One waypoint at the start of each next lane.

        Raises:
            Error: If the lane is not in the map.
        """
        var out = List[Waypoint]()
        for key in self.lane(waypoint).next_lanes:
            if key.lane_id.value == 0:
                continue
            var at = self._key(key)
            out.append(
                Waypoint(
                    key.road_id,
                    key.section_id,
                    key.lane_id,
                    self._start_of_lane(at[0], at[1], at[2]),
                )
            )
        return out^

    def predecessors(self, waypoint: Waypoint) raises -> List[Waypoint]:
        """Return the end of each lane that leads to a waypoint's lane.

        This is `Map::GetPredecessors`. Lane 0 is left out.

        Args:
            waypoint: The waypoint.

        Returns:
            One waypoint at the end of each previous lane.

        Raises:
            Error: If the lane is not in the map.
        """
        var out = List[Waypoint]()
        for key in self.lane(waypoint).prev_lanes:
            if key.lane_id.value == 0:
                continue
            var at = self._key(key)
            out.append(
                Waypoint(
                    key.road_id,
                    key.section_id,
                    key.lane_id,
                    self._end_of_lane(at[0], at[1], at[2]),
                )
            )
        return out^

    def next(
        self, waypoint: Waypoint, distance: Float64
    ) raises -> List[Waypoint]:
        """Return the waypoints a distance ahead, `Map::GetNext`.

        Ahead is the way the lane runs. Past the lane's end the walk
        continues on each successor; where two lanes lead back into each
        other, CARLA skips the loop. The list puts the longer part first,
        as CARLA's `ConcatVectors`.

        Args:
            waypoint: The start.
            distance: How far ahead, in meters. It must be positive.

        Returns:
            Every waypoint that distance ahead.

        Raises:
            Error: If the distance is not positive, or the lane is not in
                the map.
        """
        return self._step(waypoint, distance, True)

    def previous(
        self, waypoint: Waypoint, distance: Float64
    ) raises -> List[Waypoint]:
        """Return the waypoints a distance behind, `Map::GetPrevious`.

        Args:
            waypoint: The start.
            distance: How far behind, in meters. It must be positive.

        Returns:
            Every waypoint that distance behind.

        Raises:
            Error: If the distance is not positive, or the lane is not in
                the map.
        """
        return self._step(waypoint, distance, False)

    def _step(
        self, waypoint: Waypoint, distance: Float64, ahead: Bool
    ) raises -> List[Waypoint]:
        if not (distance > 0.0):
            raise Error("A step needs a positive distance")
        if distance <= EPSILON:
            return [waypoint]
        var at = self._locate(waypoint)
        ref road = self.roads[at[0]]
        var positive = road.is_positive_direction(waypoint.lane_id)
        var forward = positive if ahead else not positive
        var start = road.sections[at[1]].s
        var length = road.section_length(at[1])
        var relative = waypoint.s - start
        var remaining = length - relative if forward else relative
        if distance <= remaining:
            var result = waypoint
            if forward:
                result.s += distance - EPSILON
            else:
                result.s += -distance + EPSILON
            if not (result.s > 0.0):
                raise Error("A step left the road")
            return [result]
        var out = List[Waypoint]()
        var nexts = self.successors(waypoint) if ahead else self.predecessors(
            waypoint
        )
        for candidate in nexts:
            var broken = False
            var after = self.successors(
                candidate
            ) if ahead else self.predecessors(candidate)
            for future in after:
                if (
                    future.road_id == waypoint.road_id
                    and future.lane_id == waypoint.lane_id
                    and future.section_id == waypoint.section_id
                ):
                    broken = True
                    break
            if not broken:
                out = _concat(
                    out^, self._step(candidate, distance - remaining, ahead)
                )
        return out^

    def right(self, waypoint: Waypoint) raises -> Optional[Waypoint]:
        """Return the waypoint in the lane to the right, `Map::GetRight`.

        Right is as the lane's traffic sees it.

        Args:
            waypoint: The waypoint. It must not be on lane 0.

        Returns:
            The same s on the lane to the right, or None if there is none.

        Raises:
            Error: If the waypoint is on lane 0 or not in the map.
        """
        return self._side(waypoint, True)

    def left(self, waypoint: Waypoint) raises -> Optional[Waypoint]:
        """Return the waypoint in the lane to the left, `Map::GetLeft`.

        Args:
            waypoint: The waypoint. It must not be on lane 0.

        Returns:
            The same s on the lane to the left, or None if there is none.

        Raises:
            Error: If the waypoint is on lane 0 or not in the map.
        """
        return self._side(waypoint, False)

    def _side(
        self, waypoint: Waypoint, right: Bool
    ) raises -> Optional[Waypoint]:
        if waypoint.lane_id.value == 0:
            raise Error("Lane 0 has no lane beside it")
        var at = self._locate(waypoint)
        var outward = right == self.roads[at[0]].is_rht
        var id = waypoint.lane_id.value
        var out = waypoint
        if outward:
            out.lane_id = LaneId(id + 1 if id > 0 else id - 1)
        elif abs(id) == 1:
            out.lane_id = LaneId(-id)
        else:
            out.lane_id = LaneId(id - 1 if id > 0 else id + 1)
        if self.roads[at[0]].sections[at[1]].contains_lane(out.lane_id):
            return out
        return None

    # --- waypoint generation ------------------------------------------------------

    def generate_waypoints(self, distance: Float64) raises -> List[Waypoint]:
        """Return waypoints every `distance` on every driving lane.

        This is `Map::GenerateWaypoints`: from `EPSILON` along each road,
        every `distance` meters, on each driving lane at that s.

        Args:
            distance: The spacing, in meters. It must be positive.

        Returns:
            The waypoints, road by road.

        Raises:
            Error: If the distance is not positive.
        """
        if not (distance > 0.0):
            raise Error("Waypoint spacing must be positive")
        var out = List[Waypoint]()
        for road in self.roads:
            var s = EPSILON
            while s < road.length - EPSILON:
                for index in road.sections_at(s):
                    for lane in road.sections[index].lanes:
                        if lane.id.value == 0:
                            continue
                        if lane.type.matches(LANE_DRIVING):
                            out.append(
                                Waypoint(
                                    road.id, road.sections[index].id, lane.id, s
                                )
                            )
                s += distance
        return out^

    def _entries(
        self, road: Road, lane_type: LaneType, mut out: List[Waypoint]
    ):
        for index in road.sections_at(0.0):
            for lane in road.sections[index].lanes:
                if road.is_positive_direction(lane.id) and lane.type.matches(
                    lane_type
                ):
                    out.append(
                        Waypoint(road.id, road.sections[index].id, lane.id, 0.0)
                    )
        for index in road.sections_at(road.length):
            for lane in road.sections[index].lanes:
                if not road.is_positive_direction(
                    lane.id
                ) and lane.type.matches(lane_type):
                    out.append(
                        Waypoint(
                            road.id,
                            road.sections[index].id,
                            lane.id,
                            road.length,
                        )
                    )

    def generate_waypoints_on_road_entries(
        self, lane_type: LaneType = LANE_DRIVING
    ) raises -> List[Waypoint]:
        """Return a waypoint where each lane enters its road.

        This is `GenerateWaypointsOnRoadEntries`: s = 0 for the lanes that
        run with the road, s = the road's length for the others.

        Args:
            lane_type: The lane types to keep.

        Returns:
            The waypoints, road by road.

        Raises:
            Error: If the mask is not valid.
        """
        if not lane_type.is_valid():
            raise Error("Lane type is not valid")
        var out = List[Waypoint]()
        for road in self.roads:
            self._entries(road, lane_type, out)
        return out^

    def generate_waypoints_in_road(
        self, road_id: RoadId, lane_type: LaneType = LANE_DRIVING
    ) raises -> List[Waypoint]:
        """Return a waypoint where each lane of one road enters it.

        This is `GenerateWaypointsInRoad`.

        Args:
            road_id: The road.
            lane_type: The lane types to keep.

        Returns:
            The waypoints, or none if the map has no such road.

        Raises:
            Error: If the road id or the mask is not valid.
        """
        if not (road_id.is_valid() and lane_type.is_valid()):
            raise Error("Road id or lane type is not valid")
        var out = List[Waypoint]()
        if self.contains_road(road_id):
            self._entries(self.road(road_id), lane_type, out)
        return out^

    def generate_topology(self) raises -> List[Tuple[Waypoint, Waypoint]]:
        """Return each driving lane's start and each lane it leads to.

        This is `Map::GenerateTopology`. A lane with no successor pairs
        its start with its own section's end. The endpoint keeps its
        double precision and section identity; CARLA's float lookup can
        drop the pair or select a different section.

        Returns:
            The pairs, road by road and section by section.

        Raises:
            Error: If a lane's records are missing.
        """
        var out = List[Tuple[Waypoint, Waypoint]]()
        for r in range(len(self.roads)):
            ref road = self.roads[r]
            for sec in range(len(road.sections)):
                ref section = road.sections[sec]
                for ln in range(len(section.lanes)):
                    ref lane = section.lanes[ln]
                    if lane.id.value == 0 or not lane.type.matches(
                        LANE_DRIVING
                    ):
                        continue
                    var w = Waypoint(
                        road.id,
                        section.id,
                        lane.id,
                        self._start_of_lane(r, sec, ln),
                    )
                    var nexts = self.successors(w)
                    if len(nexts) == 0:
                        var last = Waypoint(
                            road.id,
                            section.id,
                            lane.id,
                            self._end_of_lane(r, sec, ln),
                        )
                        out.append((w, last))
                    for n in nexts:
                        out.append((w, n))
        return out^

    def junction_waypoints(
        self, id: JuncId, lane_type: LaneType
    ) raises -> List[Tuple[Waypoint, Waypoint]]:
        """Return the start and end of each lane through a junction.

        This is `Map::GetJunctionWaypoints`.

        Args:
            id: The junction.
            lane_type: The lane types to keep.

        Returns:
            One pair per lane of each connecting road.

        Raises:
            Error: If the junction, a connecting road or the mask is not
                valid.
        """
        if not lane_type.is_valid():
            raise Error("Lane type is not valid")
        var out = List[Tuple[Waypoint, Waypoint]]()
        ref junction = self.junction(id)
        for connection in junction.connections:
            var r = self.road_index(connection.connecting_road)
            ref road = self.roads[r]
            for sec in range(len(road.sections)):
                ref section = road.sections[sec]
                for ln in range(len(section.lanes)):
                    ref lane = section.lanes[ln]
                    if lane.id.value == 0 or not lane.type.matches(lane_type):
                        continue
                    var start = Waypoint(
                        road.id,
                        section.id,
                        lane.id,
                        self._start_of_lane(r, sec, ln),
                    )
                    var end = start
                    end.s = self._end_of_lane(r, sec, ln)
                    out.append((start, end))
        return out^

    def _junction_waypoints_with_work(
        self, id: JuncId, lane_type: LaneType, mut work: _MapBuildWork
    ) raises -> List[Tuple[Waypoint, Waypoint]]:
        work.step(len(self.junctions))
        if not lane_type.is_valid():
            raise Error("Lane type is not valid")
        var out = List[Tuple[Waypoint, Waypoint]]()
        ref junction = self.junction(id)
        for connection in junction.connections:
            work.step()
            work.step(len(self.roads))
            var r = self.road_index(connection.connecting_road)
            ref road = self.roads[r]
            for sec in range(len(road.sections)):
                work.step()
                ref section = road.sections[sec]
                for ln in range(len(section.lanes)):
                    work.step()
                    ref lane = section.lanes[ln]
                    if lane.id.value == 0 or not lane.type.matches(lane_type):
                        continue
                    # Each edge helper can scan strict section successors twice.
                    work.step_product(4, len(road.sections))
                    var start = Waypoint(
                        road.id,
                        section.id,
                        lane.id,
                        self._start_of_lane(r, sec, ln),
                    )
                    var end = start
                    end.s = self._end_of_lane(r, sec, ln)
                    out.append((start, end))
        return out^

    def compute_junction_conflicts(
        self, id: JuncId
    ) raises -> Tuple[List[RoadId], List[List[RoadId]]]:
        """Return which junction roads cross, `ComputeJunctionConflicts`.

        Two roads of the junction conflict when segments of theirs inside
        the junction's box come within 2 meters in plan.

        Args:
            id: The junction.

        Returns:
            The roads with a conflict, and for each the roads it crosses,
            in the order found.

        Raises:
            Error: If the junction is not in the map.
        """
        var work = _MapBuildWork(MapBuildBudget())
        return self._compute_junction_conflicts_with_work(id, work)

    def _compute_junction_conflicts_with_work(
        self, id: JuncId, mut work: _MapBuildWork
    ) raises -> Tuple[List[RoadId], List[List[RoadId]]]:
        work.step(len(self.junctions))
        ref junction = self.junction(id)
        comptime delta = Float32(0.0001)
        var center = junction.location()
        var extent = junction.extent()
        var box = Box3(
            Vector3(
                center.x - extent.x,
                center.y - extent.y,
                center.z - extent.z - delta,
            ),
            Vector3(
                center.x + extent.x,
                center.y + extent.y,
                center.z + extent.z + delta,
            ),
        )
        var found = List[Int]()
        for element in self._tree._intersections_with_work(box, work):
            work.step()
            found.append(element.start_value)
        var roads = List[RoadId]()
        var conflicts = List[List[RoadId]]()
        for i in range(len(found)):
            work.step()
            ref one = self._segments[found[i]]
            if self.road(one.first.road_id).junction_id != id:
                continue
            for j in range(i + 1, len(found)):
                work.step()
                ref two = self._segments[found[j]]
                if self.road(two.first.road_id).junction_id != id:
                    continue
                if one.first.road_id == two.first.road_id:
                    continue
                if (
                    segment_distance_2d(one.start, one.end, two.start, two.end)
                    > 2.0
                ):
                    continue
                _add_conflict_with_work(
                    roads, conflicts, one.first.road_id, two.first.road_id, work
                )
                _add_conflict_with_work(
                    roads, conflicts, two.first.road_id, one.first.road_id, work
                )
        return (roads^, conflicts^)

    # --- signals and marks ----------------------------------------------------

    def signals_in_distance(
        self,
        waypoint: Waypoint,
        distance: Float64,
        stop_at_junction: Bool = False,
    ) raises -> List[SignalSearchData]:
        """Return the signals within a distance ahead, `GetSignalsInDistance`.

        A signal counts when one of its validities holds the waypoint's
        lane. The search follows every successor past the lane's end, and
        skips junction roads when `stop_at_junction` is set.

        Args:
            waypoint: The start.
            distance: How far ahead, in meters.
            stop_at_junction: Whether to stop at junctions.

        Returns:
            The signals found, each with the waypoint where it applies and
            its distance from the start.

        Raises:
            Error: If the lane is not in the map.
        """
        var at = self._locate(waypoint)
        ref road = self.roads[at[0]]
        var forward = road.is_positive_direction(waypoint.lane_id)
        var relative = waypoint.s - road.sections[at[1]].s
        var remaining = (
            road.section_length(at[1]) - relative if forward else relative
        )
        var reach = min(distance, remaining)
        var signed = reach if forward else -reach
        var out = List[SignalSearchData]()
        for signal in infos_in_range(
            road.info.signals, waypoint.s, waypoint.s + signed
        ):
            var to_signal = (
                signal.s - waypoint.s if forward else waypoint.s - signal.s
            )
            var valid = False
            for validity in signal.validities:
                if validity.holds_for(waypoint.lane_id):
                    valid = True
                    break
            if not valid:
                continue
            if to_signal == 0.0:
                out.append(SignalSearchData(signal, waypoint, to_signal))
            else:
                out.append(
                    SignalSearchData(
                        signal, self.next(waypoint, to_signal)[0], to_signal
                    )
                )
        if distance <= remaining:
            return out^
        for candidate in self.successors(waypoint):
            if self.road(candidate.road_id).is_junction and stop_at_junction:
                continue
            var c = self._locate(candidate)
            ref next_road = self.roads[c[0]]
            var s = next_road.sections[c[1]].s
            var start = candidate
            if next_road.is_positive_direction(candidate.lane_id):
                start.s = s
            else:
                start.s = s + next_road.section_length(c[1])
            var found = self.signals_in_distance(
                start, distance - remaining, stop_at_junction
            )
            for i in range(len(found)):
                found[i].accumulated_s += remaining
            out = _concat_signals(out^, found^)
        return out^

    def all_signal_references(self) -> List[RoadInfoSignal]:
        """Return every signal reference, `GetAllSignalReferences`.

        Returns:
            The references, road by road, each road's in order of s.
        """
        var out = List[RoadInfoSignal]()
        for road in self.roads:
            for signal in road.info.signals:
                out.append(signal.copy())
        return out^

    def calculate_crossed_lanes(
        self, origin: Vector3, destination: Vector3
    ) raises -> List[LaneMarking]:
        """Return the marks a move crosses, `LaneCrossingCalculator`.

        CARLA only answers within one lane section of one road that is not
        a junction, for driving, bidirectional, biking and parking lanes.

        Args:
            origin: Where the move starts, in CARLA's frame.
            destination: Where it ends.

        Returns:
            The mark crossed, or nothing.

        Raises:
            Error: If a lane's records are missing.
        """
        var flags = (
            LANE_DRIVING | LANE_BIDIRECTIONAL | LANE_BIKING | LANE_PARKING
        )
        var w0 = self.closest_waypoint_on_road(origin, flags)
        var out = List[LaneMarking]()
        # With no lane of those types there is no nearest one for either
        # point, so CARLA's second test adds nothing to its first.
        if not Bool(w0):
            return out^
        var a = w0.value()
        var b = self.closest_waypoint_on_road(destination, flags).value()
        if a.road_id != b.road_id or a.section_id != b.section_id:
            return out^
        # Both are on one road, so CARLA's second junction test adds
        # nothing either.
        if self.is_junction(a.road_id):
            return out^
        var a_off = not self.waypoint(origin, flags)
        var b_off = not self.waypoint(destination, flags)
        if a_off and b_off:
            return out^
        if a.lane_id == b.lane_id and not a_off and not b_off:
            return out^
        var ahead = self.compute_transform(a).rotation.forward_vector()
        var toward = make_unit_vector(destination - origin)
        var to_right = (-ahead.x * toward.y + ahead.y * toward.x) < 0.0
        var marks_a = self.mark_record(a)
        var marks_b = self.mark_record(b)
        var mark: Optional[RoadInfoMarkRecord]
        if to_right:
            mark = marks_b[1].copy() if a_off else marks_a[0].copy()
        else:
            mark = marks_b[0].copy() if a_off else marks_a[1].copy()
        if Bool(mark):
            out.append(LaneMarking(mark.value()))
        return out^

    def all_crosswalk_zones(self) raises -> List[Vector3]:
        """Return the corners of every crosswalk, `GetAllCrosswalkZones`.

        Each outline is placed on lane 0 at the crosswalk's s, moved by
        its t, turned by its heading, and widened by a meter at each end
        so that it meets the sidewalks. An outline closes where a corner
        repeats the first.

        Returns:
            The corners, outline after outline, in CARLA's frame.

        Raises:
            Error: If a road's records are missing.
        """
        var out = List[Vector3]()
        for road in self.roads:
            for crosswalk in road.info.crosswalks:
                var base = CarlaTransform(
                    Length(0.0, METER),
                    Length(0.0, METER),
                    Length(0.0, METER),
                    CarlaRotation(
                        Angle(0.0, DEGREE),
                        Angle(0.0, DEGREE),
                        Angle(0.0, DEGREE),
                    ),
                )
                for index in road.sections_at(crosswalk.s):
                    var lane = road.sections[index].lane_index(LaneId(0))
                    if lane >= 0:
                        base = road.lane_transform(index, lane, crosswalk.s)
                var heading = Float32(crosswalk.heading) * _TO_DEGREES
                var pivot = base
                pivot.rotation.yaw -= heading
                pivot.rotation.yaw -= 90.0
                var moved = pivot.transform_point(
                    Vector3(Float32(crosswalk.t), 0, 0)
                )
                pivot = base
                pivot.location = moved
                pivot.rotation.yaw -= heading
                for corner in crosswalk.points:
                    var v = Vector3(
                        Float32(corner.u), Float32(corner.v), Float32(corner.z)
                    )
                    if corner.u < 0.0:
                        v.x -= 1.0
                    else:
                        v.x += 1.0
                    out.append(pivot.transform_point(v))
        return out^

    # --- client-side helpers ----------------------------------------------------

    def next_until_lane_end(
        self, waypoint: Waypoint, distance: Float64
    ) raises -> List[Waypoint]:
        """Return waypoints every `distance` to the lane's end.

        This is the client's `Waypoint::GetNextUntilLaneEnd`: steps while
        exactly one lane lies ahead on the same road, then appends the
        reachable lane endpoint. It never samples a different road.

        Args:
            waypoint: The start.
            distance: The spacing, in meters.

        Returns:
            The waypoints, ending at the reachable lane endpoint. Empty
            if the start is already at or beyond that inward endpoint.

        Raises:
            Error: If the lane is not in the map, s is not finite or is
                outside its section, the spacing is not finite and above
                EPSILON, or a step cannot advance.
        """
        return self._until_end(waypoint, distance, True)

    def previous_until_lane_start(
        self, waypoint: Waypoint, distance: Float64
    ) raises -> List[Waypoint]:
        """Return waypoints every `distance` back to the lane's start.

        This corrects the client's `Waypoint::GetPreviousUntilLaneStart`:
        the last step measures what is left in the requested backward
        direction and stays on the starting road.

        Args:
            waypoint: The start.
            distance: The spacing, in meters.

        Returns:
            The waypoints, ending at the reachable lane start. Empty
            if the start is already at or beyond that inward endpoint.

        Raises:
            Error: If the lane is not in the map, s is not finite or is
                outside its section, the spacing is not finite and above
                EPSILON, or a step cannot advance.
        """
        return self._until_end(waypoint, distance, False)

    def _until_end(
        self, waypoint: Waypoint, distance: Float64, ahead: Bool
    ) raises -> List[Waypoint]:
        if not isfinite(distance) or distance <= EPSILON:
            raise Error("Lane traversal needs a finite spacing above EPSILON")
        var initial = self._locate(waypoint)
        ref road = self.roads[initial[0]]
        var section_start = road.sections[initial[1]].s
        var section_end = section_start + road.section_length(initial[1])
        var s = waypoint.s
        if not isfinite(s) or s < section_start or s > section_end:
            raise Error("Waypoint is outside its lane section")
        var forward = road.is_positive_direction(waypoint.lane_id) == ahead
        # Locate the reachable end before sampling. Never walk through a
        # different road just to discover that a large interval overshoots.
        var end = waypoint
        var links = self.successors(end) if ahead else self.predecessors(end)
        while len(links) == 1 and links[0].road_id == waypoint.road_id:
            var candidate = links[0]
            # At larger s, the inward epsilon can round to the exact
            # shared boundary. Section order still proves progress.
            var current_section = self._locate(end)[1]
            var next_section = self._locate(candidate)[1]
            var advance = (
                next_section
                - current_section if forward else current_section
                - next_section
            )
            if advance <= 0:
                break
            end = candidate
            links = self.successors(end) if ahead else self.predecessors(end)
        var at = self._locate(end)
        end.s = self._end_of_lane(
            at[0], at[1], at[2]
        ) if ahead else self._start_of_lane(at[0], at[1], at[2])
        var out = List[Waypoint]()
        var current = waypoint
        var remaining = end.s - current.s if forward else current.s - end.s
        while remaining > 0.0:
            if distance >= remaining or remaining <= 10.0 * EPSILON:
                out.append(end)
                break
            var step = self._step(current, distance, ahead)
            if len(step) != 1:
                raise Error("Lane traversal left its unique path")
            var reached = step[0]
            var advance = (
                reached.s - current.s if forward else current.s - reached.s
            )
            if advance <= 0.0:
                raise Error(
                    "Lane traversal spacing cannot advance the waypoint"
                )
            out.append(reached)
            current = reached
            remaining = end.s - current.s if forward else current.s - end.s
        return out^

    def right_lane_marking(
        self, waypoint: Waypoint
    ) raises -> Optional[LaneMarking]:
        """Return the mark on a lane's right, `GetRightLaneMarking`.

        Args:
            waypoint: The waypoint.

        Returns:
            The mark on the right as the road's traffic sees it, or None.

        Raises:
            Error: If `mark_record` would.
        """
        var marks = self.mark_record(waypoint)
        var mark = (
            marks[0]
            .copy() if self.road(waypoint.road_id)
            .is_rht else marks[1]
            .copy()
        )
        if Bool(mark):
            return LaneMarking(mark.value())
        return None

    def left_lane_marking(
        self, waypoint: Waypoint
    ) raises -> Optional[LaneMarking]:
        """Return the mark on a lane's left, `GetLeftLaneMarking`.

        Args:
            waypoint: The waypoint.

        Returns:
            The mark on the left as the road's traffic sees it, or None.

        Raises:
            Error: If `mark_record` would.
        """
        var marks = self.mark_record(waypoint)
        var mark = (
            marks[1]
            .copy() if self.road(waypoint.road_id)
            .is_rht else marks[0]
            .copy()
        )
        if Bool(mark):
            return LaneMarking(mark.value())
        return None

    def lane_change(self, waypoint: Waypoint) raises -> LaneChange:
        """Return where a vehicle may change lanes, `Waypoint::GetLaneChange`.

        CARLA reads each mark's `laneChange` as a right or left bit
        directly, allows both where there is no mark, swaps them on a
        lane that runs against s, and keeps the right bit of the right
        mark and the left bit of the left mark.

        Args:
            waypoint: The waypoint.

        Returns:
            The permission.

        Raises:
            Error: If `mark_record` would.
        """
        var marks = self.mark_record(waypoint)
        var rht = self.road(waypoint.road_id).is_rht
        var right = marks[0].copy() if rht else marks[1].copy()
        var left = marks[1].copy() if rht else marks[0].copy()
        var c_right = CHANGE_BOTH
        if Bool(right):
            c_right = LaneChange(right.value().lane_change.value)
        var c_left = CHANGE_BOTH
        if Bool(left):
            c_left = LaneChange(left.value().lane_change.value)
        var positive = self.is_positive_direction(waypoint)
        if not positive:
            c_right = _swap(c_right)
        var beside = (
            waypoint.lane_id.value
            + 1 if positive else waypoint.lane_id.value
            - 1
        )
        if beside < 0:
            c_left = _swap(c_left)
        return (c_right & CHANGE_RIGHT) | (c_left & CHANGE_LEFT)

    def landmarks_in_distance(
        self,
        waypoint: Waypoint,
        distance: Float64,
        stop_at_junction: Bool = False,
    ) raises -> List[Landmark]:
        """Return the landmarks ahead, `GetAllLandmarksInDistance`.

        Each signal reference comes once, at its first find.

        Args:
            waypoint: The start.
            distance: How far ahead, in meters.
            stop_at_junction: Whether to stop at junctions.

        Returns:
            The landmarks.

        Raises:
            Error: If the lane is not in the map.
        """
        var out = List[Landmark]()
        for data in self.signals_in_distance(
            waypoint, distance, stop_at_junction
        ):
            var seen = False
            for landmark in out:
                if _same_reference(landmark.reference, data.signal):
                    seen = True
            if seen:
                continue
            out.append(Landmark(data.waypoint, data.signal, data.accumulated_s))
        return out^

    def landmarks_of_type_in_distance(
        self,
        waypoint: Waypoint,
        distance: Float64,
        type: String,
        stop_at_junction: Bool = False,
    ) raises -> List[Landmark]:
        """Return the landmarks of one type ahead.

        This is `GetLandmarksOfTypeInDistance`. CARLA checks for repeats
        but never records one, so a reference found twice comes twice.

        Args:
            waypoint: The start.
            distance: How far ahead, in meters.
            type: The signal type to keep.
            stop_at_junction: Whether to stop at junctions.

        Returns:
            The landmarks.

        Raises:
            Error: If the lane is not in the map or a signal is missing.
        """
        var out = List[Landmark]()
        for data in self.signals_in_distance(
            waypoint, distance, stop_at_junction
        ):
            if self.signal(data.signal.signal_id).type == type:
                out.append(
                    Landmark(data.waypoint, data.signal, data.accumulated_s)
                )
        return out^

    def all_landmarks(self) -> List[Landmark]:
        """Return every signal reference as a landmark, `GetAllLandmarks`.

        Returns:
            The landmarks, with no waypoint and distance 0.
        """
        var out = List[Landmark]()
        for reference in self.all_signal_references():
            out.append(Landmark(None, reference, 0.0))
        return out^

    def landmarks_from_id(self, id: SignalId) raises -> List[Landmark]:
        """Return the references to one signal, `GetLandmarksFromId`.

        Args:
            id: The signal's id.

        Returns:
            The landmarks.

        Raises:
            Error: If the id is not valid.
        """
        if not id.is_valid():
            raise Error("Signal id is not valid")
        var out = List[Landmark]()
        for reference in self.all_signal_references():
            if reference.signal_id == id:
                out.append(Landmark(None, reference, 0.0))
        return out^

    def all_landmarks_of_type(self, type: String) raises -> List[Landmark]:
        """Return the references to signals of one type.

        This is `GetAllLandmarksOfType`.

        Args:
            type: The signal type.

        Returns:
            The landmarks.

        Raises:
            Error: If a reference names a signal the map lacks.
        """
        var out = List[Landmark]()
        for reference in self.all_signal_references():
            if self.signal(reference.signal_id).type == type:
                out.append(Landmark(None, reference, 0.0))
        return out^

    def landmark_group(self, landmark: Landmark) raises -> List[Landmark]:
        """Return the landmarks of the signals that share a controller.

        This is `GetLandmarkGroup`.

        Args:
            landmark: One landmark.

        Returns:
            For each controller of its signal, and each signal of that
            controller, every reference to that signal.

        Raises:
            Error: If a signal or controller is missing.
        """
        var out = List[Landmark]()
        ref signal = self.signal(landmark.reference.signal_id)
        for controller_id in signal.controllers:
            var held = self.controller(controller_id).signals.copy()
            # The controller holds this signal, so it holds one at least.
            for id in held:  # pragma: no branch
                _ = self.signal(id)
                out.extend(self.landmarks_from_id(id))
        return out^

    # --- the segment index ----------------------------------------------------

    def segment_count(self) -> Int:
        """Return how many segments the nearest-waypoint index holds.

        Returns:
            The number of segments.
        """
        return len(self._segments)

    def segment(
        self, index: Int
    ) raises -> Tuple[Vector3, Vector3, Waypoint, Waypoint]:
        """Return one segment of the nearest-waypoint index.

        Args:
            index: Its index.

        Returns:
            Its start and end in CARLA's frame, and the waypoints there.

        Raises:
            Error: If the index is out of range.
        """
        if index < 0 or index >= len(self._segments):
            raise Error("No segment at that index")
        ref s = self._segments[index]
        return (s.start, s.end, s.first, s.second)

    def _build_next(
        mut self, waypoint: Waypoint, distance: Float64
    ) raises -> Waypoint:
        # Index construction deliberately stays inside one section. Preserve
        # _step's scalar arithmetic, but never enter unmetered graph recursion.
        if not distance > 0.0:
            raise Error("A step needs a positive distance")
        if distance <= EPSILON:
            return waypoint
        var at = self._build_locate(waypoint)
        self._construction_work.step(len(self.roads[at[0]].sections))
        var length = self.roads[at[0]].section_length(at[1])
        var start = self.roads[at[0]].sections[at[1]].s
        var forward = self.roads[at[0]].is_positive_direction(waypoint.lane_id)
        var relative = waypoint.s - start
        var remaining = length - relative if forward else relative
        if distance > remaining:
            raise Error("Map construction step cannot remain in its section")
        var result = waypoint
        if forward:
            result.s += distance - EPSILON
        else:
            result.s += -distance + EPSILON
        if not result.s > 0.0:
            raise Error("A step left the road")
        return result

    def _build_transform(mut self, waypoint: Waypoint) raises -> CarlaTransform:
        var at = self._build_locate(waypoint)
        _reserve_lane_scalars(
            self.roads[at[0]], at[1], self._construction_work, 2
        )
        var terms = _reference_work(self.roads[at[0]], waypoint.s, waypoint.s)
        if terms < 0:
            raise Error("Map construction cannot resolve pose quadrature work")
        self._construction_work.step()
        self._construction_work.term(terms)
        self._construction_work.term(terms)
        return self.roads[at[0]].lane_transform(at[1], at[2], waypoint.s)

    def _reserve_build_point(
        mut self, road: Int, section: Int, s: Float64
    ) raises:
        _reserve_lane_scalars(
            self.roads[road], section, self._construction_work
        )
        var terms = _reference_work(self.roads[road], s, s)
        if terms < 0:
            raise Error("Map construction cannot resolve point quadrature work")
        self._construction_work.step()
        self._construction_work.term(terms)

    def _add_segment(
        mut self,
        a: CarlaTransform,
        b: CarlaTransform,
        first: Waypoint,
        second: Waypoint,
    ) raises:
        var at = self._build_locate(first)
        # CARLA's piece goes into its own index unchanged. Each piece adds
        # at least one refined segment below, so the refined index's
        # segment and step charges also bound this index.
        var lane_type = self.roads[at[0]].sections[at[1]].lanes[at[2]].type
        self._carla_tree.insert_element(
            a.location, b.location, len(self._carla_segments), lane_type.value
        )
        self._carla_segments.append(
            _CarlaSegment(a.location, b.location, first, second)
        )
        _reserve_lane_boundaries(
            self.roads[at[0]], at[1], self._construction_work
        )
        var boundaries = self.roads[at[0]]._lane_record_boundaries(at[1])
        var forward = first.s < second.s
        var current = first
        var current_t = a
        # Iterate boundaries instead of recursively nesting one stack frame
        # per source record. The scan and each resulting cell share the ledger.
        while True:
            self._construction_work.step()
            var boundary = second.s
            var found = False
            for s in boundaries:
                self._construction_work.step()
                if forward:
                    if s > current.s and s <= boundary:
                        boundary = s
                        found = True
                elif s <= current.s and s > boundary:
                    boundary = s
                    found = True
            if not found:
                self._subdivide_segment(current_t, b, current, second, 0)
                return
            var before = current
            var after = current
            after.s = boundary
            before.s = bitcast[DType.float64](
                bitcast[DType.uint64](boundary) - 1
            )
            var before_t = self._build_transform(before)
            var after_t = self._build_transform(after)
            if forward:
                self._subdivide_segment(current_t, before_t, current, before, 0)
                current = after
                current_t = after_t
            else:
                self._subdivide_segment(current_t, after_t, current, after, 0)
                current = before
                current_t = before_t

    def _subdivide_segment(
        mut self,
        a: CarlaTransform,
        b: CarlaTransform,
        first: Waypoint,
        second: Waypoint,
        depth: Int,
    ) raises:
        # Quarter points also expose cubic inflections that a midpoint misses.
        self._construction_work.step()
        var at = self._build_locate(first)
        self._reserve_build_point(at[0], at[1], first.s)
        var one = self.roads[at[0]]._lane_point(at[1], at[2], first.s)
        self._reserve_build_point(at[0], at[1], second.s)
        var two = self.roads[at[0]]._lane_point(at[1], at[2], second.s)
        var error = 0.0
        var quarter = 1
        while quarter < 4:
            var fraction = Float64(quarter) * 0.25
            quarter += 1
            var sample = first
            sample.s += fraction * (second.s - first.s)
            self._reserve_build_point(at[0], at[1], sample.s)
            var point = self.roads[at[0]]._lane_point(at[1], at[2], sample.s)
            var dx = point.x - (one.x + fraction * (two.x - one.x))
            var dy = point.y - (one.y + fraction * (two.y - one.y))
            var dz = point.z - (one.z + fraction * (two.z - one.z))
            error = max(error, dx * dx + dy * dy + dz * dz)
        var mid = first
        mid.s = first.s + (second.s - first.s) * 0.5
        var turn = self.roads[at[0]]._lane_turn_bound(first.s, second.s)
        if error > 0.000001 or turn > 0.5:
            # Adjacent road-s values cannot produce an interior waypoint.
            # Do not repeat the same failed interval up to the depth cap.
            if mid.s == first.s or mid.s == second.s:
                raise Error(
                    "Lane center cannot meet the spatial subdivision target "
                    "at Float64 road-s resolution"
                )
            if depth >= 24:
                raise Error("Lane center exceeds the spatial subdivision limit")
            var middle = self._build_transform(mid)
            self._subdivide_segment(a, middle, first, mid, depth + 1)
            self._subdivide_segment(middle, b, mid, second, depth + 1)
            return
        var lane_type = self.roads[at[0]].sections[at[1]].lanes[at[2]].type
        # The index's numerical contract requires finite stored Float32
        # endpoints. Refuse an unrepresentable index input rather than let
        # infinity or NaN defeat node bounds. Wide center arithmetic remains.
        var stored_start: Array[Float64, 3] = [
            Float64(a.location.x),
            Float64(a.location.y),
            Float64(a.location.z),
        ]
        var stored_end: Array[Float64, 3] = [
            Float64(b.location.x),
            Float64(b.location.y),
            Float64(b.location.z),
        ]
        _finite_point(stored_start)
        _finite_point(stored_end)
        # Admit all storage for this segment before inserting any index entry.
        self._construction_work.segment()
        var low = first.s
        var high = second.s
        var start = a.location
        var end = b.location
        if low > high:
            low = second.s
            high = first.s
            start = b.location
            end = a.location
        self._construction_work.step()
        # Root Jet, two endpoint centers and four optional cover Jets each
        # scan lane profiles. Reserve their full fixed allowance up front.
        var lane_count = len(self.roads[at[0]].sections[at[1]].lanes)
        self._construction_work.step_product(10, lane_count)
        # The successful10*lane_count check also makes1+6*lane_count safe.
        var node_cost = 1 + 6 * lane_count
        self._construction_work.proof_headroom()
        var remaining_steps = (
            self._construction_work.policy.max_steps
            - self._construction_work.steps
        )
        var proof_nodes = _ProofNodeWork(
            min(16384, remaining_steps // node_cost),
            fail_on_limit=remaining_steps // node_cost < 16384,
        )
        var captured = _SpiralRootCapture()
        var certificate = _chord_certificate_capture_with_nodes(
            self.roads[at[0]],
            at[1],
            at[2],
            low,
            high,
            start,
            end,
            captured,
            proof_nodes,
        )
        self._construction_work.step_product(proof_nodes.used, node_cost)
        var construction_terms = certificate[2]
        var cover = _sampled_lane_box_cover(
            self.roads[at[0]], at[1], at[2], low, high, construction_terms
        )
        var cover_index = -1
        if cover:
            cover_index = len(self._sampled_covers)
            self._sampled_covers.append(cover.value())
        # Preserve the existing chord and sampled-cover construction work
        # before spending ANY optional phase-proof/packing allowance.
        var proof = _try_pack_spiral_proof(
            self.roads[at[0]],
            low,
            high,
            len(self._segments),
            captured,
            len(self._spiral_proofs),
            construction_terms,
            self._spiral_proof_units,
        )
        if proof:
            self._spiral_proofs.append(proof.value())
        self._construction_work.term(construction_terms)
        self._tree.insert_element(
            a.location, b.location, len(self._segments), lane_type.value
        )
        self._segments.append(
            _Segment(
                a.location,
                b.location,
                first,
                second,
                certificate[1],
                cover_index,
            )
        )
        self._curve_deviation = max(self._curve_deviation, certificate[0])
        self._endpoint_scale = max(
            self._endpoint_scale,
            Float64(
                max(
                    max(abs(start.x), max(abs(start.y), abs(start.z))),
                    max(abs(end.x), max(abs(end.y), abs(end.z))),
                )
            ),
        )

    def _create_segments(mut self) raises:
        _require_sum2_environment()
        # `Map::CreateRtree`.
        comptime tiny = 0.000001
        comptime min_delta = 1.0
        comptime angle_threshold = 3.14159265358979323846 / 100.0
        comptime max_segment = 100.0
        var starts = List[Waypoint]()
        for r in range(len(self.roads)):
            self._construction_work.step()
            for sec in range(len(self.roads[r].sections)):
                self._construction_work.step()
                ref section = self.roads[r].sections[sec]
                for ln in range(len(section.lanes)):
                    self._construction_work.step()
                    if section.lanes[ln].id.value == 0:
                        continue
                    self._construction_work.step_product(
                        2, len(self.roads[r].sections)
                    )
                    starts.append(
                        Waypoint(
                            self.roads[r].id,
                            section.id,
                            section.lanes[ln].id,
                            self._start_of_lane(r, sec, ln),
                        )
                    )
        for start in starts:
            self._construction_work.step()
            var at = self._build_locate(start)
            var current = start
            var current_t = self._build_transform(current)
            var lane_start = self.roads[at[0]].sections[at[1]].s
            self._construction_work.step(len(self.roads[at[0]].sections))
            var lane_end = lane_start + self.roads[at[0]].section_length(at[1])
            var positive = self.roads[at[0]].is_positive_direction(
                start.lane_id
            )
            _reserve_straightness(
                self.roads[at[0]], at[1], self._construction_work
            )
            var straight = self.roads[at[0]].lane_is_straight(at[1])
            if straight:
                var remaining = (
                    lane_end - current.s if positive else current.s - lane_start
                ) - tiny
                if remaining < tiny:
                    continue
                # The step stops short of the section's end, so it gives
                # one waypoint on the same lane.
                var end = self._build_next(current, remaining)
                self._add_segment(
                    current_t, self._build_transform(end), current, end
                )
                continue
            var next_w = current
            while True:
                self._construction_work.step()
                var remaining = (
                    lane_end - next_w.s if positive else next_w.s - lane_start
                ) - tiny
                var delta = min(min_delta, remaining)
                if delta < tiny:
                    self._add_segment(
                        current_t,
                        self._build_transform(next_w),
                        current,
                        next_w,
                    )
                    break
                # CARLA also stops where the step leaves the section. A
                # step of at most `remaining` stops short of the section's
                # end, so it gives one waypoint in the same section.
                var previous_s = next_w.s
                next_w = self._build_next(next_w, delta)
                # This positive nonterminal step must advance in lane order.
                # The terminal branch above can still insert a zero span.
                if (
                    next_w.s
                    <= previous_s if positive else next_w.s
                    >= previous_s
                ):
                    raise Error(
                        "Lane index sampling cannot advance "
                        "at Float64 road-s resolution"
                    )
                var next_t = self._build_transform(next_w)
                var angle = Float64(
                    vector_angle(
                        current_t.rotation.forward_vector(),
                        next_t.rotation.forward_vector(),
                    ).value
                )
                if (
                    abs(angle) > angle_threshold
                    or abs(current.s - next_w.s) > max_segment
                ):
                    self._add_segment(current_t, next_t, current, next_w)
                    current = next_w
                    current_t = next_t


# `Math::ToDegrees<float>`: 180 over pi, both floats.
comptime _TO_DEGREES = Float32(180.0) / Float32(3.14159265358979323846)


def _swap(change: LaneChange) -> LaneChange:
    if change == CHANGE_RIGHT:
        return CHANGE_LEFT
    if change == CHANGE_LEFT:
        return CHANGE_RIGHT
    return change


def _same_reference(a: RoadInfoSignal, b: RoadInfoSignal) -> Bool:
    return a.signal_id == b.signal_id and a.road_id == b.road_id and a.s == b.s


def _add_conflict(
    mut roads: List[RoadId],
    mut conflicts: List[List[RoadId]],
    road: RoadId,
    other: RoadId,
):
    for i in range(len(roads)):
        if roads[i] == road:
            # A road is added with one conflict, so the list is not empty.
            for id in conflicts[i]:  # pragma: no branch
                if id == other:
                    return
            conflicts[i].append(other)
            return
    roads.append(road)
    conflicts.append([other])


def _add_conflict_with_work(
    mut roads: List[RoadId],
    mut conflicts: List[List[RoadId]],
    road: RoadId,
    other: RoadId,
    mut work: _MapBuildWork,
) raises:
    for i in range(len(roads)):
        work.step()
        if roads[i] == road:
            # A road is added with one conflict, so the list is not empty.
            for id in conflicts[i]:  # pragma: no branch
                work.step()
                if id == other:
                    return
            work.step()
            conflicts[i].append(other)
            return
    work.step(2)
    roads.append(road)
    conflicts.append([other])
