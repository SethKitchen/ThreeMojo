# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's road ids, lane kinds and `road/element/RoadInfo*` records.

An OpenDRIVE road and each of its lanes carry records that start at a
distance s along the road: the plan-view geometry, the elevation, the lane
offset, the lane widths and borders, the road marks and so on. CARLA keeps
them in an `InformationSet`, sorted by s, and asks for "the record of this
kind that holds at s": the last one that starts at or before s.

`InformationSet` here holds one list per kind, each sorted by s with a
stable sort, so a tie keeps the order the records were added in.
`info_at` is `InformationSet::GetInfo<T>(s)` and `infos_in_range` is
`GetInfos<T>(min_s, max_s)`. CARLA sorts all kinds in one list with
`std::sort`, which does not promise to keep ties in order; for records of
one kind at one s this port keeps the file order.

Every record keeps its s in meters as a `Float64`, as CARLA's `double`. The
map's waypoints step s by `10 * DBL_EPSILON`, which a `Float32` `Length`
cannot hold.

The ids are CARLA's `road/RoadTypes.h`: a road id and a section id are
unsigned 32-bit numbers, a junction id and a lane id signed ones, and a
signal id and a controller id are strings. `LaneType` is CARLA's
`Lane::LaneType` bit mask, and `LaneMarking` is `road/element/LaneMarking`.

Source: CARLA 1360bb9, `LibCarla/source/carla/road/element/RoadInfo*.h`,
`road/InformationSet.h`, `road/RoadElementSet.h`, `road/RoadTypes.h`,
`road/LaneValidity.h`, `road/element/LaneMarking.cpp`.
"""

from extensions.carla.geometry import RoadGeometry
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.speed_limits import (
    SpeedLimitKind,
    NUMERIC_SPEED_LIMIT,
    NO_SPEED_LIMIT,
    UNDEFINED_SPEED_LIMIT,
    UNSPECIFIED_SPEED_LIMIT,
    opendrive_speed,
    read_speed_number,
)
from units.si import Velocity64

comptime _UINT32_MAX = 4294967295
comptime _INT32_MIN = -2147483648
comptime _INT32_MAX = 2147483647


# --- ids ----------------------------------------------------------------------


@fieldwise_init
struct RoadId(Equatable, ImplicitlyCopyable, Writable):
    """An OpenDRIVE road id, CARLA's `RoadId`: an unsigned 32-bit number."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the id fits an unsigned 32-bit number."""
        return self.value >= 0 and self.value <= _UINT32_MAX


@fieldwise_init
struct SectionId(Equatable, ImplicitlyCopyable, Writable):
    """A lane section's id within its road, CARLA's `SectionId`.

    The parser numbers a road's sections 0, 1, 2 and so on in file order.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the id fits an unsigned 32-bit number."""
        return self.value >= 0 and self.value <= _UINT32_MAX


@fieldwise_init
struct JuncId(Equatable, ImplicitlyCopyable, Writable):
    """A junction id, CARLA's `JuncId`: a signed 32-bit number.

    A road that is not in a junction has `NO_JUNCTION`, -1.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the id fits a signed 32-bit number."""
        return self.value >= _INT32_MIN and self.value <= _INT32_MAX


# The junction id of a road that is not in a junction.
comptime NO_JUNCTION = JuncId(-1)


@fieldwise_init
struct ConId(Equatable, ImplicitlyCopyable, Writable):
    """A junction connection's id, CARLA's `ConId`: unsigned 32-bit."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the id fits an unsigned 32-bit number."""
        return self.value >= 0 and self.value <= _UINT32_MAX


@fieldwise_init
struct LaneId(Equatable, ImplicitlyCopyable, Writable):
    """An OpenDRIVE lane id. Minus is right of the line, plus is left.

    Lane 0 is the reference line. It has no width, but it is a real lane
    in CARLA: it carries the center road mark, and a waypoint can name it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the id fits a signed 32-bit number."""
        return self.value >= _INT32_MIN and self.value <= _INT32_MAX


@fieldwise_init
struct SignalId(Equatable, ImplicitlyCopyable, Writable):
    """A signal's id, CARLA's `SignId`: a string from the file."""

    var value: String

    def is_valid(self) -> Bool:
        """Return True if the id is not empty."""
        return self.value.byte_length() > 0


@fieldwise_init
struct ControllerId(Equatable, ImplicitlyCopyable, Writable):
    """A signal controller's id, CARLA's `ContId`: a string."""

    var value: String

    def is_valid(self) -> Bool:
        """Return True if the id is not empty."""
        return self.value.byte_length() > 0


# --- kinds ----------------------------------------------------------------


@fieldwise_init
struct LaneType(Equatable, ImplicitlyCopyable, Writable):
    """CARLA's `Lane::LaneType`: one bit per kind, or a mask of several.

    A query takes a mask, such as `LANE_DRIVING | LANE_SHOULDER`, and
    keeps the lanes whose type shares a bit with it. `LANE_ANY` is every
    bit but the lowest, as CARLA's -2.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for a nonzero mask of the 21 kinds, or `LANE_ANY`."""
        if self.value == -2:
            return True
        return self.value > 0 and self.value < (1 << 21)

    def __or__(self, other: Self) -> Self:
        """Return the mask of both.

        Args:
            other: The other mask.

        Returns:
            The bitwise or.
        """
        return LaneType(self.value | other.value)

    def matches(self, mask: Self) -> Bool:
        """Return True if this type shares a bit with a mask.

        Args:
            mask: The mask to test against.

        Returns:
            True if `self & mask` is not zero, as CARLA tests it.
        """
        return (self.value & mask.value) != 0


comptime LANE_NONE = LaneType(1)
comptime LANE_DRIVING = LaneType(1 << 1)
comptime LANE_STOP = LaneType(1 << 2)
comptime LANE_SHOULDER = LaneType(1 << 3)
comptime LANE_BIKING = LaneType(1 << 4)
comptime LANE_SIDEWALK = LaneType(1 << 5)
comptime LANE_BORDER = LaneType(1 << 6)
comptime LANE_RESTRICTED = LaneType(1 << 7)
comptime LANE_PARKING = LaneType(1 << 8)
comptime LANE_BIDIRECTIONAL = LaneType(1 << 9)
comptime LANE_MEDIAN = LaneType(1 << 10)
comptime LANE_SPECIAL1 = LaneType(1 << 11)
comptime LANE_SPECIAL2 = LaneType(1 << 12)
comptime LANE_SPECIAL3 = LaneType(1 << 13)
comptime LANE_ROAD_WORKS = LaneType(1 << 14)
comptime LANE_TRAM = LaneType(1 << 15)
comptime LANE_RAIL = LaneType(1 << 16)
comptime LANE_ENTRY = LaneType(1 << 17)
comptime LANE_EXIT = LaneType(1 << 18)
comptime LANE_OFF_RAMP = LaneType(1 << 19)
comptime LANE_ON_RAMP = LaneType(1 << 20)
# Every kind: CARLA's -2, 0xFFFFFFFE.
comptime LANE_ANY = LaneType(-2)


def lane_type_of(name: String) -> LaneType:
    """Return the lane type a file names, `RoadParser`'s `StringToLaneType`.

    Args:
        name: The `type` attribute of a `lane`, in any case.

    Returns:
        The type, or `LANE_NONE` for a name CARLA does not know.
    """
    var lower = name.lower()
    var names: List[String] = [
        "driving",
        "stop",
        "shoulder",
        "biking",
        "sidewalk",
        "border",
        "restricted",
        "parking",
        "bidirectional",
        "median",
        "special1",
        "special2",
        "special3",
        "roadworks",
        "tram",
        "rail",
        "entry",
        "exit",
        "offramp",
        "onramp",
    ]
    # The list is a constant and not empty.
    for i in range(len(names)):  # pragma: no branch
        if names[i] == lower:
            return LaneType(1 << (i + 1))
    return LANE_NONE


@fieldwise_init
struct SignalOrientation(Equatable, ImplicitlyCopyable, Writable):
    """Which way a signal faces, CARLA's `SignalOrientation`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for positive, negative or both."""
        return self.value >= 0 and self.value <= 2


# The signal faces traffic that runs with the road: "+".
comptime ORIENTATION_POSITIVE = SignalOrientation(0)
# The signal faces traffic that runs against the road: "-".
comptime ORIENTATION_NEGATIVE = SignalOrientation(1)
# Any other text: both ways.
comptime ORIENTATION_BOTH = SignalOrientation(2)


def signal_orientation_of(text: String) -> SignalOrientation:
    """Return the orientation a file writes, as `Signal::GetOrientation`.

    Args:
        text: "+", "-" or anything else.

    Returns:
        Positive, negative, or both for anything else.
    """
    if text == "+":
        return ORIENTATION_POSITIVE
    if text == "-":
        return ORIENTATION_NEGATIVE
    return ORIENTATION_BOTH


@fieldwise_init
struct MarkLaneChange(Equatable, ImplicitlyCopyable, Writable):
    """A road mark's `laneChange`, `RoadInfoMarkRecord::LaneChange`.

    OpenDRIVE writes it against the road's direction: "increase" lets a
    vehicle cross toward higher lane ids. `LaneMarking` turns it into
    right and left with the road's traffic rule.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for none, increase, decrease or both."""
        return self.value >= 0 and self.value <= 3


comptime MARK_CHANGE_NONE = MarkLaneChange(0)
comptime MARK_CHANGE_INCREASE = MarkLaneChange(1)
comptime MARK_CHANGE_DECREASE = MarkLaneChange(2)
comptime MARK_CHANGE_BOTH = MarkLaneChange(3)


def mark_lane_change_of(text: String) -> MarkLaneChange:
    """Return the lane change a file writes, as `MapBuilder::CreateRoadMark`.

    Args:
        text: The `laneChange` attribute, in any case.

    Returns:
        Increase, decrease, none, or both for anything else, including an
        absent attribute.
    """
    var lower = text.lower()
    if lower == "increase":
        return MARK_CHANGE_INCREASE
    if lower == "decrease":
        return MARK_CHANGE_DECREASE
    if lower == "none":
        return MARK_CHANGE_NONE
    return MARK_CHANGE_BOTH


@fieldwise_init
struct LaneMarkingType(Equatable, ImplicitlyCopyable, Writable):
    """How a lane edge is painted, `LaneMarking::Type`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of CARLA's eleven types."""
        return self.value >= 0 and self.value <= 10


comptime OTHER = LaneMarkingType(0)
comptime BROKEN = LaneMarkingType(1)
comptime SOLID = LaneMarkingType(2)
comptime SOLID_SOLID = LaneMarkingType(3)
comptime SOLID_BROKEN = LaneMarkingType(4)
comptime BROKEN_SOLID = LaneMarkingType(5)
comptime BROKEN_BROKEN = LaneMarkingType(6)
comptime BOTTS_DOTS = LaneMarkingType(7)
comptime GRASS = LaneMarkingType(8)
comptime CURB = LaneMarkingType(9)
comptime NO_MARKING = LaneMarkingType(10)


def lane_marking_type_of(text: String) -> LaneMarkingType:
    """Return the marking type a road mark names, `LaneMarking`'s `GetType`.

    Args:
        text: The road mark's `type` attribute, in any case.

    Returns:
        The type, or `OTHER` for a name CARLA does not know.
    """
    var lower = text.lower()
    var names: List[String] = [
        "broken",
        "solid",
        "solid solid",
        "solid broken",
        "broken solid",
        "broken broken",
        "botts dots",
        "grass",
        "curb",
        "none",
    ]
    # The list is a constant and not empty.
    for i in range(len(names)):  # pragma: no branch
        if names[i] == lower:
            return LaneMarkingType(i + 1)
    return OTHER


@fieldwise_init
struct LaneMarkingColor(Equatable, ImplicitlyCopyable, Writable):
    """A road mark's color, `LaneMarking::Color`. White is standard."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for one of CARLA's six colors."""
        return self.value >= 0 and self.value <= 5


comptime MARKING_STANDARD = LaneMarkingColor(0)
comptime MARKING_BLUE = LaneMarkingColor(1)
comptime MARKING_GREEN = LaneMarkingColor(2)
comptime MARKING_RED = LaneMarkingColor(3)
comptime MARKING_WHITE = MARKING_STANDARD
comptime MARKING_YELLOW = LaneMarkingColor(4)
comptime MARKING_OTHER = LaneMarkingColor(5)


def lane_marking_color_of(text: String) -> LaneMarkingColor:
    """Return the color a road mark names, `LaneMarking`'s `GetColor`.

    Args:
        text: The road mark's `color` attribute, in any case.

    Returns:
        The color, or `MARKING_OTHER` for a name CARLA does not know.
    """
    var lower = text.lower()
    if lower == "standard" or lower == "white":
        return MARKING_STANDARD
    if lower == "blue":
        return MARKING_BLUE
    if lower == "green":
        return MARKING_GREEN
    if lower == "red":
        return MARKING_RED
    if lower == "yellow":
        return MARKING_YELLOW
    return MARKING_OTHER


@fieldwise_init
struct LaneChange(Equatable, ImplicitlyCopyable, Writable):
    """Which way a vehicle may cross a mark, `LaneMarking::LaneChange`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for none, right, left or both."""
        return self.value >= 0 and self.value <= 3

    def __and__(self, other: Self) -> Self:
        """Return the bits both allow.

        Args:
            other: The other permission.

        Returns:
            The bitwise and.
        """
        return LaneChange(self.value & other.value)

    def __or__(self, other: Self) -> Self:
        """Return the bits either allows.

        Args:
            other: The other permission.

        Returns:
            The bitwise or.
        """
        return LaneChange(self.value | other.value)


comptime CHANGE_NONE = LaneChange(0)
comptime CHANGE_RIGHT = LaneChange(1)
comptime CHANGE_LEFT = LaneChange(2)
comptime CHANGE_BOTH = LaneChange(3)


# --- records ------------------------------------------------------------------


trait RoadInfo(Copyable, Movable):
    """A record that starts at a distance along its road, `RoadInfo`."""

    def distance(self) -> Float64:
        """Return where the record starts, in meters along the road."""
        ...


@fieldwise_init
struct RoadInfoGeometry(RoadInfo):
    """A plan-view record of the reference line, `RoadInfoGeometry`."""

    var s: Float64
    var geometry: RoadGeometry

    def distance(self) -> Float64:
        """Return where the record starts, in meters."""
        return self.s


@fieldwise_init
struct RoadInfoElevation(ImplicitlyCopyable, RoadInfo):
    """The road's height as a cubic in s, `RoadInfoElevation`."""

    var s: Float64
    var polynomial: CubicPolynomial

    def distance(self) -> Float64:
        """Return where the record starts, in meters."""
        return self.s


@fieldwise_init
struct RoadInfoLaneOffset(ImplicitlyCopyable, RoadInfo):
    """How far lane 0 sits left of the reference line, `RoadInfoLaneOffset`."""

    var s: Float64
    var polynomial: CubicPolynomial

    def distance(self) -> Float64:
        """Return where the record starts, in meters."""
        return self.s


@fieldwise_init
struct RoadInfoLaneWidth(ImplicitlyCopyable, RoadInfo):
    """A lane's width as a cubic in s, `RoadInfoLaneWidth`."""

    var s: Float64
    var polynomial: CubicPolynomial

    def distance(self) -> Float64:
        """Return where the record starts, in meters."""
        return self.s


@fieldwise_init
struct RoadInfoLaneBorder(ImplicitlyCopyable, RoadInfo):
    """A lane's outer border as a cubic in s, `RoadInfoLaneBorder`.

    CARLA stores it and does not read it. The OpenDRIVE reader also makes
    width records from the borders of a lane that has no widths; see
    `extensions.carla.opendrive`.
    """

    var s: Float64
    var polynomial: CubicPolynomial

    def distance(self) -> Float64:
        """Return where the record starts, in meters."""
        return self.s


@fieldwise_init
struct RoadInfoLaneHeight(ImplicitlyCopyable, RoadInfo):
    """A lane's lift above the road, inner and outer, `RoadInfoLaneHeight`."""

    var s: Float64
    # Meters above the road surface at the lane's inner and outer edges.
    var inner: Float64
    var outer: Float64

    def distance(self) -> Float64:
        """Return where the record starts, in meters."""
        return self.s


@fieldwise_init
struct RoadInfoLaneMaterial(RoadInfo):
    """A lane's surface, `RoadInfoLaneMaterial`."""

    var s: Float64
    var surface: String
    # The friction coefficient, without units.
    var friction: Float64
    # The roughness, as the file writes it.
    var roughness: Float64

    def distance(self) -> Float64:
        """Return where the record starts, in meters."""
        return self.s


@fieldwise_init
struct RoadInfoLaneVisibility(ImplicitlyCopyable, RoadInfo):
    """How far one sees from a lane, `RoadInfoLaneVisibility`."""

    var s: Float64
    # Meters of sight forward, back, left and right.
    var forward: Float64
    var back: Float64
    var left: Float64
    var right: Float64

    def distance(self) -> Float64:
        """Return where the record starts, in meters."""
        return self.s


@fieldwise_init
struct RoadInfoLaneAccess(RoadInfo):
    """Who may use a lane, `RoadInfoLaneAccess`."""

    var s: Float64
    var restriction: String

    def distance(self) -> Float64:
        """Return where the record starts, in meters."""
        return self.s


@fieldwise_init
struct RoadInfoLaneRule(RoadInfo):
    """A free-text lane rule, `RoadInfoLaneRule`."""

    var s: Float64
    var value: String

    def distance(self) -> Float64:
        """Return where the record starts, in meters."""
        return self.s


struct RoadInfoSpeed(RoadInfo):
    """A source speed record with its original unit and explicit limit state.

    Numeric zero, no limit, undefined and a missing road speed remain
    distinct. `limit` is the checked Velocity64 boundary. The type stays
    "Town" unless a caller names one, retaining the tree-placement contract.
    """

    var s: Float64
    # The file's number in its original unit; read kind before using it.
    var speed: Float64
    var type: String
    var unit: String
    var kind: SpeedLimitKind
    # Original max text, including keywords. Empty means no road speed.
    var max_text: String

    def __init__(
        out self, s: Float64, speed: Float64, type: String, unit: String = ""
    ) raises:
        """Create a checked numeric source record.

        Args:
            s: Where the record starts, in meters.
            speed: The finite nonnegative source number.
            type: The retained record type.
            unit: The source speed unit; omitted means m/s for road/lane data.

        Raises:
            Error: If the number or source unit is invalid.
        """
        _ = opendrive_speed(speed, unit, True)
        self.s = s
        self.speed = speed
        self.type = type
        self.unit = unit
        self.kind = NUMERIC_SPEED_LIMIT
        self.max_text = String(speed)

    @staticmethod
    def from_opendrive(
        s: Float64,
        max_text: String,
        type: String,
        unit: String,
        allow_road_states: Bool,
    ) raises -> RoadInfoSpeed:
        """Read a road or lane speed while preserving its source payload.

        Args:
            s: Where the record starts, in meters.
            max_text: Original numeric text, or a road keyword.
            type: The retained record type.
            unit: Original unit text; omitted road/lane units mean m/s.
            allow_road_states: Whether no limit, undefined or absent is valid.

        Returns:
            The checked numeric record, or an explicit nonnumeric road state.

        Raises:
            Error: If a lane uses a keyword, or a number or unit is invalid.
        """
        var out = RoadInfoSpeed(s, 0, type, unit)
        out.max_text = max_text
        if allow_road_states and max_text == "no limit":
            out.kind = NO_SPEED_LIMIT
        elif allow_road_states and max_text == "undefined":
            out.kind = UNDEFINED_SPEED_LIMIT
        elif allow_road_states and max_text == "":
            out.kind = UNSPECIFIED_SPEED_LIMIT
        else:
            out.speed = read_speed_number(max_text)
            _ = opendrive_speed(out.speed, unit, True)
        return out^

    def limit(self) raises -> Optional[Velocity64]:
        """Read a numeric limit without conflating zero with road keywords.

        Returns:
            A typed numeric limit, including zero; None for other kinds.
            `kind` distinguishes no limit, undefined and absent.

        Raises:
            Error: If the mutable kind, number or unit is invalid.
        """
        if not self.kind.is_valid():
            raise Error("Road speed limit kind is not valid")
        if self.kind != NUMERIC_SPEED_LIMIT:
            _ = opendrive_speed(0, self.unit, True)
            return None
        return opendrive_speed(self.speed, self.unit, True)

    def distance(self) -> Float64:
        """Return where the record starts, in meters."""
        return self.s


@fieldwise_init
struct RoadInfoMarkTypeLine(ImplicitlyCopyable, RoadInfo):
    """One line of a road mark's `type`, `RoadInfoMarkTypeLine`."""

    var s: Float64
    var road_mark_id: Int
    # Meters of paint, meters of gap, and the sideways offset.
    var length: Float64
    var space: Float64
    var t_offset: Float64
    var rule: String
    # The line's width, in meters.
    var width: Float64

    def distance(self) -> Float64:
        """Return where the record starts, in meters."""
        return self.s


struct RoadInfoMarkRecord(RoadInfo):
    """A road mark on a lane's outer edge, `RoadInfoMarkRecord`."""

    var s: Float64
    # The mark's index within its lane, in file order.
    var road_mark_id: Int
    var type: String
    var weight: String
    var color: String
    var material: String
    # The paint's width and height, in meters.
    var width: Float64
    var lane_change: MarkLaneChange
    var height: Float64
    var type_name: String
    var type_width: Float64
    # The traffic rule of the road the mark is on.
    var is_rht: Bool
    var lines: List[RoadInfoMarkTypeLine]

    def __init__(out self, s: Float64, road_mark_id: Int):
        """Create a record with CARLA's defaults: white standard paint
        0.15 meters wide, no lane change, right-hand traffic.

        Args:
            s: Where the mark starts, in meters.
            road_mark_id: The mark's index within its lane.
        """
        self = RoadInfoMarkRecord(
            s,
            road_mark_id,
            "",
            "",
            "white",
            "standard",
            0.15,
            MARK_CHANGE_NONE,
            0.0,
            "",
            0.0,
            True,
        )

    def __init__(
        out self,
        s: Float64,
        road_mark_id: Int,
        type: String,
        weight: String,
        color: String,
        material: String,
        width: Float64,
        lane_change: MarkLaneChange,
        height: Float64,
        type_name: String,
        type_width: Float64,
        is_rht: Bool,
    ):
        """Create a record from a file's `roadMark`.

        Args:
            s: Where the mark starts, in meters.
            road_mark_id: The mark's index within its lane.
            type: The mark's `type`, such as "solid".
            weight: The mark's `weight`.
            color: The mark's `color`.
            material: The mark's `material`.
            width: The paint's width, in meters.
            lane_change: Which way a vehicle may cross.
            height: The paint's height, in meters.
            type_name: The `name` of the mark's `type` child.
            type_width: The `width` of the mark's `type` child.
            is_rht: True if the road keeps traffic to the right.
        """
        self.s = s
        self.road_mark_id = road_mark_id
        self.type = type
        self.weight = weight
        self.color = color
        self.material = material
        self.width = width
        self.lane_change = lane_change
        self.height = height
        self.type_name = type_name
        self.type_width = type_width
        self.is_rht = is_rht
        self.lines = List[RoadInfoMarkTypeLine]()

    def distance(self) -> Float64:
        """Return where the record starts, in meters."""
        return self.s


@fieldwise_init
struct CrosswalkPoint(ImplicitlyCopyable):
    """One corner of a crosswalk's outline, in the crosswalk's frame."""

    # Meters along, across and up.
    var u: Float64
    var v: Float64
    var z: Float64


@fieldwise_init
struct RoadInfoCrosswalk(RoadInfo):
    """A crosswalk object and its outline, `RoadInfoCrosswalk`."""

    var s: Float64
    var name: String
    # Meters to the left of the reference line, and up.
    var t: Float64
    var z_offset: Float64
    # Radians.
    var heading: Float64
    var pitch: Float64
    var roll: Float64
    var orientation: String
    # Meters.
    var width: Float64
    var length: Float64
    var points: List[CrosswalkPoint]

    def distance(self) -> Float64:
        """Return where the record starts, in meters."""
        return self.s


@fieldwise_init
struct LaneValidity(Equatable, ImplicitlyCopyable, Writable):
    """The lanes a signal holds for, `LaneValidity`: from one id to another."""

    var from_lane: LaneId
    var to_lane: LaneId

    def holds_for(self, lane: LaneId) -> Bool:
        """Return True if a lane is in the range.

        Args:
            lane: The lane.

        Returns:
            True if `from_lane <= lane <= to_lane`.
        """
        return (
            lane.value >= self.from_lane.value
            and lane.value <= self.to_lane.value
        )


@fieldwise_init
struct RoadInfoSignal(RoadInfo):
    """A signal or a reference to one, placed on a road, `RoadInfoSignal`.

    CARLA points at the signal. This keeps its id; `Map.signal` finds it.
    """

    var signal_id: SignalId
    var road_id: RoadId
    var s: Float64
    # Meters to the left of the reference line.
    var t: Float64
    var orientation_text: String
    var validities: List[LaneValidity]

    def distance(self) -> Float64:
        """Return where the reference sits, in meters."""
        return self.s

    def orientation(self) -> SignalOrientation:
        """Return which way the reference faces, `GetOrientation`.

        Returns:
            Positive for "+", negative for "-", both otherwise.
        """
        return signal_orientation_of(self.orientation_text)


# --- the set ------------------------------------------------------------------


def info_index[T: RoadInfo](records: List[T], s: Float64) -> Int:
    """Return where the record that holds at s sits, without copying it.

    Args:
        records: One kind of record, sorted by s.
        s: The distance along the road, in meters.

    Returns:
        The index of the last record that starts at or before s, or -1
        if every one starts after it.
    """
    var lo = 0
    var hi = len(records)
    while lo < hi:
        var mid = (lo + hi) // 2
        if records[mid].distance() <= s:
            lo = mid + 1
        else:
            hi = mid
    return lo - 1


def info_at[T: RoadInfo](records: List[T], s: Float64) -> Optional[T]:
    """Return the record that holds at s, `InformationSet::GetInfo<T>`.

    Args:
        records: One kind of record, sorted by s.
        s: The distance along the road, in meters.

    Returns:
        The last record that starts at or before s, or None if every one
        starts after it.
    """
    var at = info_index(records, s)
    if at < 0:
        return None
    return records[at].copy()


def infos_in_range[
    T: RoadInfo
](records: List[T], min_s: Float64, max_s: Float64) -> List[T]:
    """Return the records in a range, `InformationSet::GetInfos<T>(a, b)`.

    With `min_s < max_s` the records that start in [min_s, max_s] come in
    order of s. Otherwise the records in [max_s, min_s] come in reverse,
    as CARLA walks a lane that runs against the road.

    Args:
        records: One kind of record, sorted by s.
        min_s: Where the walk starts, in meters.
        max_s: Where the walk ends, in meters.

    Returns:
        The records, in the order of the walk.
    """
    var out = List[T]()
    if min_s < max_s:
        for i in range(len(records)):
            var s = records[i].distance()
            if s >= min_s and s <= max_s:
                out.append(records[i].copy())
        return out^
    for i in range(len(records) - 1, -1, -1):
        var s = records[i].distance()
        if s >= max_s and s <= min_s:
            out.append(records[i].copy())
    return out^


def sort_infos[T: RoadInfo](mut records: List[T]):
    """Sort records by s, keeping the order of ties.

    Args:
        records: The records, in the order they were added.
    """
    for i in range(1, len(records)):
        var j = i
        while j > 0 and records[j - 1].distance() > records[j].distance():
            records.swap_elements(j - 1, j)
            j -= 1


struct InformationSet(Copyable, Movable):
    """The records of one road or one lane, `InformationSet`.

    A road uses the geometry, elevation, lane offset, speed, crosswalk and
    signal lists. A lane uses the width, border, height, material,
    visibility, access, rule, mark and speed lists.
    """

    var geometries: List[RoadInfoGeometry]
    var elevations: List[RoadInfoElevation]
    var lane_offsets: List[RoadInfoLaneOffset]
    var speeds: List[RoadInfoSpeed]
    var crosswalks: List[RoadInfoCrosswalk]
    var signals: List[RoadInfoSignal]
    var widths: List[RoadInfoLaneWidth]
    var borders: List[RoadInfoLaneBorder]
    var heights: List[RoadInfoLaneHeight]
    var materials: List[RoadInfoLaneMaterial]
    var visibilities: List[RoadInfoLaneVisibility]
    var accesses: List[RoadInfoLaneAccess]
    var rules: List[RoadInfoLaneRule]
    var marks: List[RoadInfoMarkRecord]

    def __init__(out self):
        """Create an empty set."""
        self.geometries = List[RoadInfoGeometry]()
        self.elevations = List[RoadInfoElevation]()
        self.lane_offsets = List[RoadInfoLaneOffset]()
        self.speeds = List[RoadInfoSpeed]()
        self.crosswalks = List[RoadInfoCrosswalk]()
        self.signals = List[RoadInfoSignal]()
        self.widths = List[RoadInfoLaneWidth]()
        self.borders = List[RoadInfoLaneBorder]()
        self.heights = List[RoadInfoLaneHeight]()
        self.materials = List[RoadInfoLaneMaterial]()
        self.visibilities = List[RoadInfoLaneVisibility]()
        self.accesses = List[RoadInfoLaneAccess]()
        self.rules = List[RoadInfoLaneRule]()
        self.marks = List[RoadInfoMarkRecord]()

    def sort(mut self):
        """Sort every list by s, as CARLA does when it builds the map."""
        sort_infos(self.geometries)
        sort_infos(self.elevations)
        sort_infos(self.lane_offsets)
        sort_infos(self.speeds)
        sort_infos(self.crosswalks)
        sort_infos(self.signals)
        sort_infos(self.widths)
        sort_infos(self.borders)
        sort_infos(self.heights)
        sort_infos(self.materials)
        sort_infos(self.visibilities)
        sort_infos(self.accesses)
        sort_infos(self.rules)
        sort_infos(self.marks)


# --- lane marking -------------------------------------------------------------


struct LaneMarking(ImplicitlyCopyable, Writable):
    """A road mark as a driver reads it, `road/element/LaneMarking`."""

    var type: LaneMarkingType
    var color: LaneMarkingColor
    var lane_change: LaneChange
    # The paint's width, in meters.
    var width: Float64

    def __init__(out self, info: RoadInfoMarkRecord):
        """Read a mark record, as `LaneMarking(const RoadInfoMarkRecord &)`.

        "increase" is a change to the right on a right-hand road and to
        the left on a left-hand one; "decrease" the other way.

        Args:
            info: The record.
        """
        self.type = lane_marking_type_of(info.type)
        self.color = lane_marking_color_of(info.color)
        self.width = info.width
        var change = info.lane_change
        if change == MARK_CHANGE_INCREASE:
            self.lane_change = CHANGE_RIGHT if info.is_rht else CHANGE_LEFT
        elif change == MARK_CHANGE_DECREASE:
            self.lane_change = CHANGE_LEFT if info.is_rht else CHANGE_RIGHT
        elif change == MARK_CHANGE_BOTH:
            self.lane_change = CHANGE_BOTH
        else:
            self.lane_change = CHANGE_NONE

    def __init__(
        out self,
        type: LaneMarkingType,
        color: LaneMarkingColor,
        lane_change: LaneChange,
        width: Float64,
    ) raises:
        """Create a marking from its parts.

        Args:
            type: How the edge is painted.
            color: The paint's color.
            lane_change: Which way a vehicle may cross.
            width: The paint's width, in meters.

        Raises:
            Error: If the type, the color or the lane change is not valid.
        """
        if not (
            type.is_valid() and color.is_valid() and lane_change.is_valid()
        ):
            raise Error("Lane marking type, color or lane change is not valid")
        self.type = type
        self.color = color
        self.lane_change = lane_change
        self.width = width

    def color_name(self) -> String:
        """Return the color as CARLA names it, `GetColorInfoAsString`.

        Returns:
            "yellow" for yellow, "white" for every other color.
        """
        if self.color == MARKING_YELLOW:
            return "yellow"
        return "white"

    def write_to(self, mut writer: Some[Writer]):
        """Write the marking's fields.

        Args:
            writer: The destination.
        """
        writer.write(
            "LaneMarking(type=",
            self.type.value,
            ", color=",
            self.color.value,
            ", lane_change=",
            self.lane_change.value,
            ", width=",
            self.width,
            ")",
        )
