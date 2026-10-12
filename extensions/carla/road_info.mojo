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

from extensions.carla.geometry import _check_geometry_record, RoadGeometry
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
from extensions.carla.quantity_boundary import (
    _RAW_SI,
    _RawSI,
    _finite_si,
    _nonnegative_si,
    _positive_si,
)
from units.si import Velocity64

comptime _UINT32_MAX = 4294967295
comptime _INT32_MIN = -2147483648
comptime _INT32_MAX = 2147483647

from units.si import Length64, Angle64

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

    def distance(self) raises -> Length64:
        """Return the checked typed start station.

        Returns:
            The record's starting station as a Float64 length.

        Raises:
            Error: If the implementing record has an invalid station.
        """
        ...

    def distance_meters(self) raises -> Float64:
        """Read the checked explicit meter compatibility view.

        Returns:
            The record's starting station in meters.

        Raises:
            Error: If the implementing record has an invalid station.
        """
        ...

    def _distance_si(self) -> Float64:
        """Return the internal raw station for ordered record searches."""
        ...


struct RoadInfoGeometry(RoadInfo):
    """A plan-view record of the reference line, `RoadInfoGeometry`."""

    var s: Float64
    var geometry: RoadGeometry

    def __init__(out self, s: Length64, geometry: RoadGeometry) raises:
        """Create a checked typed record without changing scalar storage.

        Args:
            s: Its typed source quantity.
            geometry: Its source record value.

        Returns:
            A record with unchanged source precision and layout.

        Raises:
            Error: If a quantity is not finite or another field is invalid.
        """
        self = RoadInfoGeometry.from_si(s.value, geometry)

    @staticmethod
    def from_si(s: Float64, geometry: RoadGeometry) raises -> RoadInfoGeometry:
        """Explicit source-unit compatibility adapter. Create the explicit compatibility record.

        Args:
            s: The nonnegative record station in meters.
            geometry: The geometry record, including its sampled state when
                required.

        Returns:
            The new RoadInfoGeometry record with the supplied source fields.

        Raises:
            Error: If the station is nonfinite or negative, or the supplied
                geometry record is invalid.
        """
        _ = _nonnegative_si(s)
        _check_geometry_record(geometry)
        return RoadInfoGeometry(_RAW_SI, s, geometry)

    @staticmethod
    def _from_si(s: Float64, geometry: RoadGeometry) -> RoadInfoGeometry:
        """Explicit source-unit compatibility adapter. Create the explicit compatibility record.
        """
        return RoadInfoGeometry(_RAW_SI, s, geometry)

    def __init__(out self, raw: _RawSI, s: Float64, geometry: RoadGeometry):
        """Create the explicit compatibility record."""
        self.s = s
        self.geometry = geometry.copy()

    def distance(self) raises -> Length64:
        """Return the checked typed start station.

        Returns:
            The record's finite Float64 start station.

        Raises:
            Error: If the raw station is not finite.
        """
        return Length64(self.distance_meters())

    def distance_meters(self) raises -> Float64:
        """Read the checked explicit meter compatibility view.

        Returns:
            The unchanged Float64 start station in meters.

        Raises:
            Error: If the raw station is not finite.
        """
        return _nonnegative_si(self.s)

    def _distance_si(self) -> Float64:
        return self.s

    def s_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw s compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_nonnegative_si(self.s))


struct RoadInfoElevation(ImplicitlyCopyable, RoadInfo):
    """The road's height as a cubic in s, `RoadInfoElevation`."""

    var s: Float64
    var polynomial: CubicPolynomial

    def __init__(out self, s: Length64, polynomial: CubicPolynomial) raises:
        """Create a checked typed record without changing scalar storage.

        Args:
            s: Its typed source quantity.
            polynomial: Its source record value.

        Returns:
            A record with unchanged source precision and layout.

        Raises:
            Error: If a quantity is not finite or another field is invalid.
        """
        self = RoadInfoElevation.from_si(s.value, polynomial)

    @staticmethod
    def from_si(
        s: Float64, polynomial: CubicPolynomial
    ) raises -> RoadInfoElevation:
        """Explicit source-unit compatibility adapter. Create the explicit compatibility record.

        Args:
            s: The nonnegative record station in meters.
            polynomial: The local cubic coefficients and origin in their
                source units.

        Returns:
            The new RoadInfoElevation record with the supplied source fields.

        Raises:
            Error: If the station is nonfinite or negative, or a polynomial
                coefficient or origin is nonfinite.
        """
        _ = _nonnegative_si(s)
        _ = CubicPolynomial.from_coefficients(
            polynomial.a, polynomial.b, polynomial.c, polynomial.d, polynomial.s
        )
        return RoadInfoElevation(_RAW_SI, s, polynomial)

    @staticmethod
    def _from_si(s: Float64, polynomial: CubicPolynomial) -> RoadInfoElevation:
        """Explicit source-unit compatibility adapter. Create the explicit compatibility record.
        """
        return RoadInfoElevation(_RAW_SI, s, polynomial)

    def __init__(
        out self, raw: _RawSI, s: Float64, polynomial: CubicPolynomial
    ):
        """Create the explicit compatibility record."""
        self.s = s
        self.polynomial = polynomial

    def distance(self) raises -> Length64:
        """Return the checked typed start station.

        Returns:
            The record's finite Float64 start station.

        Raises:
            Error: If the raw station is not finite.
        """
        return Length64(self.distance_meters())

    def distance_meters(self) raises -> Float64:
        """Read the checked explicit meter compatibility view.

        Returns:
            The unchanged Float64 start station in meters.

        Raises:
            Error: If the raw station is not finite.
        """
        return _nonnegative_si(self.s)

    def _distance_si(self) -> Float64:
        return self.s

    def s_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw s compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_nonnegative_si(self.s))


struct RoadInfoLaneOffset(ImplicitlyCopyable, RoadInfo):
    """How far lane 0 sits left of the reference line, `RoadInfoLaneOffset`."""

    var s: Float64
    var polynomial: CubicPolynomial

    def __init__(out self, s: Length64, polynomial: CubicPolynomial) raises:
        """Create a checked typed record without changing scalar storage.

        Args:
            s: Its typed source quantity.
            polynomial: Its source record value.

        Returns:
            A record with unchanged source precision and layout.

        Raises:
            Error: If a quantity is not finite or another field is invalid.
        """
        self = RoadInfoLaneOffset.from_si(s.value, polynomial)

    @staticmethod
    def from_si(
        s: Float64, polynomial: CubicPolynomial
    ) raises -> RoadInfoLaneOffset:
        """Explicit source-unit compatibility adapter. Create the explicit compatibility record.

        Args:
            s: The nonnegative record station in meters.
            polynomial: The local cubic coefficients and origin in their
                source units.

        Returns:
            The new RoadInfoLaneOffset record with the supplied source fields.

        Raises:
            Error: If the station is nonfinite or negative, or a polynomial
                coefficient or origin is nonfinite.
        """
        _ = _nonnegative_si(s)
        _ = CubicPolynomial.from_coefficients(
            polynomial.a, polynomial.b, polynomial.c, polynomial.d, polynomial.s
        )
        return RoadInfoLaneOffset(_RAW_SI, s, polynomial)

    @staticmethod
    def _from_si(s: Float64, polynomial: CubicPolynomial) -> RoadInfoLaneOffset:
        """Explicit source-unit compatibility adapter. Create the explicit compatibility record.
        """
        return RoadInfoLaneOffset(_RAW_SI, s, polynomial)

    def __init__(
        out self, raw: _RawSI, s: Float64, polynomial: CubicPolynomial
    ):
        """Create the explicit compatibility record."""
        self.s = s
        self.polynomial = polynomial

    def distance(self) raises -> Length64:
        """Return the checked typed start station.

        Returns:
            The record's finite Float64 start station.

        Raises:
            Error: If the raw station is not finite.
        """
        return Length64(self.distance_meters())

    def distance_meters(self) raises -> Float64:
        """Read the checked explicit meter compatibility view.

        Returns:
            The unchanged Float64 start station in meters.

        Raises:
            Error: If the raw station is not finite.
        """
        return _nonnegative_si(self.s)

    def _distance_si(self) -> Float64:
        return self.s

    def s_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw s compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_nonnegative_si(self.s))


struct RoadInfoLaneWidth(ImplicitlyCopyable, RoadInfo):
    """A lane's width as a cubic in s, `RoadInfoLaneWidth`."""

    var s: Float64
    var polynomial: CubicPolynomial

    def __init__(out self, s: Length64, polynomial: CubicPolynomial) raises:
        """Create a checked typed record without changing scalar storage.

        Args:
            s: Its typed source quantity.
            polynomial: Its source record value.

        Returns:
            A record with unchanged source precision and layout.

        Raises:
            Error: If a quantity is not finite or another field is invalid.
        """
        self = RoadInfoLaneWidth.from_si(s.value, polynomial)

    @staticmethod
    def from_si(
        s: Float64, polynomial: CubicPolynomial
    ) raises -> RoadInfoLaneWidth:
        """Explicit source-unit compatibility adapter. Create the explicit compatibility record.

        Args:
            s: The nonnegative record station in meters.
            polynomial: The local cubic coefficients and origin in their
                source units.

        Returns:
            The new RoadInfoLaneWidth record with the supplied source fields.

        Raises:
            Error: If the station is nonfinite or negative, or a polynomial
                coefficient or origin is nonfinite.
        """
        _ = _nonnegative_si(s)
        _ = CubicPolynomial.from_coefficients(
            polynomial.a, polynomial.b, polynomial.c, polynomial.d, polynomial.s
        )
        return RoadInfoLaneWidth(_RAW_SI, s, polynomial)

    @staticmethod
    def _from_si(s: Float64, polynomial: CubicPolynomial) -> RoadInfoLaneWidth:
        """Explicit source-unit compatibility adapter. Create the explicit compatibility record.
        """
        return RoadInfoLaneWidth(_RAW_SI, s, polynomial)

    def __init__(
        out self, raw: _RawSI, s: Float64, polynomial: CubicPolynomial
    ):
        """Create the explicit compatibility record."""
        self.s = s
        self.polynomial = polynomial

    def distance(self) raises -> Length64:
        """Return the checked typed start station.

        Returns:
            The record's finite Float64 start station.

        Raises:
            Error: If the raw station is not finite.
        """
        return Length64(self.distance_meters())

    def distance_meters(self) raises -> Float64:
        """Read the checked explicit meter compatibility view.

        Returns:
            The unchanged Float64 start station in meters.

        Raises:
            Error: If the raw station is not finite.
        """
        return _nonnegative_si(self.s)

    def _distance_si(self) -> Float64:
        return self.s

    def s_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw s compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_nonnegative_si(self.s))


struct RoadInfoLaneBorder(ImplicitlyCopyable, RoadInfo):
    """A lane's outer border as a cubic in s, `RoadInfoLaneBorder`.

    CARLA stores it and does not read it.
    """

    var s: Float64
    var polynomial: CubicPolynomial

    def __init__(out self, s: Length64, polynomial: CubicPolynomial) raises:
        """Create a checked typed record without changing scalar storage.

        Args:
            s: Its typed source quantity.
            polynomial: Its source record value.

        Returns:
            A record with unchanged source precision and layout.

        Raises:
            Error: If a quantity is not finite or another field is invalid.
        """
        self = RoadInfoLaneBorder.from_si(s.value, polynomial)

    @staticmethod
    def from_si(
        s: Float64, polynomial: CubicPolynomial
    ) raises -> RoadInfoLaneBorder:
        """Explicit source-unit compatibility adapter. Create the explicit compatibility record.

        Args:
            s: The nonnegative record station in meters.
            polynomial: The local cubic coefficients and origin in their
                source units.

        Returns:
            The new RoadInfoLaneBorder record with the supplied source fields.

        Raises:
            Error: If the station is nonfinite or negative, or a polynomial
                coefficient or origin is nonfinite.
        """
        _ = _nonnegative_si(s)
        _ = CubicPolynomial.from_coefficients(
            polynomial.a, polynomial.b, polynomial.c, polynomial.d, polynomial.s
        )
        return RoadInfoLaneBorder(_RAW_SI, s, polynomial)

    @staticmethod
    def _from_si(s: Float64, polynomial: CubicPolynomial) -> RoadInfoLaneBorder:
        """Explicit source-unit compatibility adapter. Create the explicit compatibility record.
        """
        return RoadInfoLaneBorder(_RAW_SI, s, polynomial)

    def __init__(
        out self, raw: _RawSI, s: Float64, polynomial: CubicPolynomial
    ):
        """Create the explicit compatibility record."""
        self.s = s
        self.polynomial = polynomial

    def distance(self) raises -> Length64:
        """Return the checked typed start station.

        Returns:
            The record's finite Float64 start station.

        Raises:
            Error: If the raw station is not finite.
        """
        return Length64(self.distance_meters())

    def distance_meters(self) raises -> Float64:
        """Read the checked explicit meter compatibility view.

        Returns:
            The unchanged Float64 start station in meters.

        Raises:
            Error: If the raw station is not finite.
        """
        return _nonnegative_si(self.s)

    def _distance_si(self) -> Float64:
        return self.s

    def s_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw s compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_nonnegative_si(self.s))


struct RoadInfoLaneHeight(ImplicitlyCopyable, RoadInfo):
    """A lane's lift above the road, inner and outer, `RoadInfoLaneHeight`."""

    var s: Float64
    # Meters above the road surface at the lane's inner and outer edges.
    var inner: Float64
    var outer: Float64

    def __init__(
        out self, s: Length64, inner: Length64, outer: Length64
    ) raises:
        """Create a checked typed record without changing scalar storage.

        Args:
            s: Its typed source quantity.
            inner: Its typed source quantity.
            outer: Its typed source quantity.

        Returns:
            A record with unchanged source precision and layout.

        Raises:
            Error: If a quantity is not finite or another field is invalid.
        """
        self = RoadInfoLaneHeight.from_si(s.value, inner.value, outer.value)

    @staticmethod
    def from_si(
        s: Float64, inner: Float64, outer: Float64
    ) raises -> RoadInfoLaneHeight:
        """Explicit source-unit compatibility adapter. Create the explicit compatibility record.

        Args:
            s: The nonnegative record station in meters.
            inner: The signed inner-edge height in meters.
            outer: The signed outer-edge height in meters.

        Returns:
            The new RoadInfoLaneHeight record with the supplied source fields.

        Raises:
            Error: If the station is nonfinite or negative, or either height
                is nonfinite.
        """
        _ = _nonnegative_si(s)
        _ = _finite_si(inner)
        _ = _finite_si(outer)
        return RoadInfoLaneHeight(_RAW_SI, s, inner, outer)

    @staticmethod
    def _from_si(
        s: Float64, inner: Float64, outer: Float64
    ) -> RoadInfoLaneHeight:
        """Explicit source-unit compatibility adapter. Create the explicit compatibility record.
        """
        return RoadInfoLaneHeight(_RAW_SI, s, inner, outer)

    def __init__(
        out self, raw: _RawSI, s: Float64, inner: Float64, outer: Float64
    ):
        """Create the explicit compatibility record."""
        self.s = s
        self.inner = inner
        self.outer = outer

    def distance(self) raises -> Length64:
        """Return the checked typed start station.

        Returns:
            The record's finite Float64 start station.

        Raises:
            Error: If the raw station is not finite.
        """
        return Length64(self.distance_meters())

    def distance_meters(self) raises -> Float64:
        """Read the checked explicit meter compatibility view.

        Returns:
            The unchanged Float64 start station in meters.

        Raises:
            Error: If the raw station is not finite.
        """
        return _nonnegative_si(self.s)

    def _distance_si(self) -> Float64:
        return self.s

    def s_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw s compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_nonnegative_si(self.s))

    def inner_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw inner compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_finite_si(self.inner))

    def outer_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw outer compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_finite_si(self.outer))


struct RoadInfoLaneMaterial(RoadInfo):
    """A lane's surface, `RoadInfoLaneMaterial`."""

    var s: Float64
    var surface: String
    # The friction coefficient, without units.
    var friction: Float64
    # The roughness, as the file writes it.
    var roughness: Float64

    def __init__(
        out self,
        s: Length64,
        surface: String,
        friction: Float64,
        roughness: Float64,
    ) raises:
        """Create a checked typed record without changing scalar storage.

        Args:
            s: Its typed source quantity.
            surface: Its source record value.
            friction: Its source record value.
            roughness: Its source record value.

        Returns:
            A record with unchanged source precision and layout.

        Raises:
            Error: If a quantity is not finite or another field is invalid.
        """
        self = RoadInfoLaneMaterial.from_si(
            s.value, surface, friction, roughness
        )

    @staticmethod
    def from_si(
        s: Float64, surface: String, friction: Float64, roughness: Float64
    ) raises -> RoadInfoLaneMaterial:
        """Explicit source-unit compatibility adapter. Create the explicit compatibility record.

        Args:
            s: The nonnegative record station in meters.
            surface: The source surface name.
            friction: The source dimensionless friction coefficient.
            roughness: The source dimensionless roughness value.

        Returns:
            The new RoadInfoLaneMaterial record with the supplied source
            fields.

        Raises:
            Error: If the station is nonfinite or negative.
        """
        _ = _nonnegative_si(s)
        return RoadInfoLaneMaterial(_RAW_SI, s, surface, friction, roughness)

    @staticmethod
    def _from_si(
        s: Float64, surface: String, friction: Float64, roughness: Float64
    ) -> RoadInfoLaneMaterial:
        """Explicit source-unit compatibility adapter. Create the explicit compatibility record.
        """
        return RoadInfoLaneMaterial(_RAW_SI, s, surface, friction, roughness)

    def __init__(
        out self,
        raw: _RawSI,
        s: Float64,
        surface: String,
        friction: Float64,
        roughness: Float64,
    ):
        """Create the explicit compatibility record."""
        self.s = s
        self.surface = surface
        self.friction = friction
        self.roughness = roughness

    def distance(self) raises -> Length64:
        """Return the checked typed start station.

        Returns:
            The record's finite Float64 start station.

        Raises:
            Error: If the raw station is not finite.
        """
        return Length64(self.distance_meters())

    def distance_meters(self) raises -> Float64:
        """Read the checked explicit meter compatibility view.

        Returns:
            The unchanged Float64 start station in meters.

        Raises:
            Error: If the raw station is not finite.
        """
        return _nonnegative_si(self.s)

    def _distance_si(self) -> Float64:
        return self.s

    def s_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw s compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_nonnegative_si(self.s))


struct RoadInfoLaneVisibility(ImplicitlyCopyable, RoadInfo):
    """How far one sees from a lane, `RoadInfoLaneVisibility`."""

    var s: Float64
    # Meters of sight forward, back, left and right.
    var forward: Float64
    var back: Float64
    var left: Float64
    var right: Float64

    def __init__(
        out self,
        s: Length64,
        forward: Length64,
        back: Length64,
        left: Length64,
        right: Length64,
    ) raises:
        """Create a checked typed record without changing scalar storage.

        Args:
            s: Its typed source quantity.
            forward: Its typed source quantity.
            back: Its typed source quantity.
            left: Its typed source quantity.
            right: Its typed source quantity.

        Returns:
            A record with unchanged source precision and layout.

        Raises:
            Error: If a quantity is not finite or another field is invalid.
        """
        self = RoadInfoLaneVisibility.from_si(
            s.value, forward.value, back.value, left.value, right.value
        )

    @staticmethod
    def from_si(
        s: Float64,
        forward: Float64,
        back: Float64,
        left: Float64,
        right: Float64,
    ) raises -> RoadInfoLaneVisibility:
        """Explicit source-unit compatibility adapter. Create the explicit compatibility record.

        Args:
            s: The nonnegative record station in meters.
            forward: The nonnegative forward sight distance in meters.
            back: The nonnegative rear sight distance in meters.
            left: The nonnegative left sight distance in meters.
            right: The nonnegative right sight distance in meters.

        Returns:
            The new RoadInfoLaneVisibility record with the supplied source
            fields.

        Raises:
            Error: If the station or any sight distance is nonfinite or
                negative.
        """
        _ = _nonnegative_si(s)
        _ = _nonnegative_si(forward)
        _ = _nonnegative_si(back)
        _ = _nonnegative_si(left)
        _ = _nonnegative_si(right)
        return RoadInfoLaneVisibility(_RAW_SI, s, forward, back, left, right)

    @staticmethod
    def _from_si(
        s: Float64,
        forward: Float64,
        back: Float64,
        left: Float64,
        right: Float64,
    ) -> RoadInfoLaneVisibility:
        """Explicit source-unit compatibility adapter. Create the explicit compatibility record.
        """
        return RoadInfoLaneVisibility(_RAW_SI, s, forward, back, left, right)

    def __init__(
        out self,
        raw: _RawSI,
        s: Float64,
        forward: Float64,
        back: Float64,
        left: Float64,
        right: Float64,
    ):
        """Create the explicit compatibility record."""
        self.s = s
        self.forward = forward
        self.back = back
        self.left = left
        self.right = right

    def distance(self) raises -> Length64:
        """Return the checked typed start station.

        Returns:
            The record's finite Float64 start station.

        Raises:
            Error: If the raw station is not finite.
        """
        return Length64(self.distance_meters())

    def distance_meters(self) raises -> Float64:
        """Read the checked explicit meter compatibility view.

        Returns:
            The unchanged Float64 start station in meters.

        Raises:
            Error: If the raw station is not finite.
        """
        return _nonnegative_si(self.s)

    def _distance_si(self) -> Float64:
        return self.s

    def s_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw s compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_nonnegative_si(self.s))

    def forward_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw forward compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_nonnegative_si(self.forward))

    def back_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw back compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_nonnegative_si(self.back))

    def left_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw left compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_nonnegative_si(self.left))

    def right_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw right compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_nonnegative_si(self.right))


struct RoadInfoLaneAccess(RoadInfo):
    """Who may use a lane, `RoadInfoLaneAccess`."""

    var s: Float64
    var restriction: String

    def __init__(out self, s: Length64, restriction: String) raises:
        """Create a checked typed record without changing scalar storage.

        Args:
            s: Its typed source quantity.
            restriction: Its source record value.

        Returns:
            A record with unchanged source precision and layout.

        Raises:
            Error: If a quantity is not finite or another field is invalid.
        """
        self = RoadInfoLaneAccess.from_si(s.value, restriction)

    @staticmethod
    def from_si(s: Float64, restriction: String) raises -> RoadInfoLaneAccess:
        """Explicit source-unit compatibility adapter. Create the explicit compatibility record.

        Args:
            s: The nonnegative record station in meters.
            restriction: The source access restriction text.

        Returns:
            The new RoadInfoLaneAccess record with the supplied source fields.

        Raises:
            Error: If the station is nonfinite or negative.
        """
        _ = _nonnegative_si(s)
        return RoadInfoLaneAccess(_RAW_SI, s, restriction)

    @staticmethod
    def _from_si(s: Float64, restriction: String) -> RoadInfoLaneAccess:
        """Explicit source-unit compatibility adapter. Create the explicit compatibility record.
        """
        return RoadInfoLaneAccess(_RAW_SI, s, restriction)

    def __init__(out self, raw: _RawSI, s: Float64, restriction: String):
        """Create the explicit compatibility record."""
        self.s = s
        self.restriction = restriction

    def distance(self) raises -> Length64:
        """Return the checked typed start station.

        Returns:
            The record's finite Float64 start station.

        Raises:
            Error: If the raw station is not finite.
        """
        return Length64(self.distance_meters())

    def distance_meters(self) raises -> Float64:
        """Read the checked explicit meter compatibility view.

        Returns:
            The unchanged Float64 start station in meters.

        Raises:
            Error: If the raw station is not finite.
        """
        return _nonnegative_si(self.s)

    def _distance_si(self) -> Float64:
        return self.s

    def s_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw s compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_nonnegative_si(self.s))


struct RoadInfoLaneRule(RoadInfo):
    """A free-text lane rule, `RoadInfoLaneRule`."""

    var s: Float64
    var value: String

    def __init__(out self, s: Length64, value: String) raises:
        """Create a checked typed record without changing scalar storage.

        Args:
            s: Its typed source quantity.
            value: Its source record value.

        Returns:
            A record with unchanged source precision and layout.

        Raises:
            Error: If a quantity is not finite or another field is invalid.
        """
        self = RoadInfoLaneRule.from_si(s.value, value)

    @staticmethod
    def from_si(s: Float64, value: String) raises -> RoadInfoLaneRule:
        """Explicit source-unit compatibility adapter. Create the explicit compatibility record.

        Args:
            s: The nonnegative record station in meters.
            value: The source rule text.

        Returns:
            The new RoadInfoLaneRule record with the supplied source fields.

        Raises:
            Error: If the station is nonfinite or negative.
        """
        _ = _nonnegative_si(s)
        return RoadInfoLaneRule(_RAW_SI, s, value)

    @staticmethod
    def _from_si(s: Float64, value: String) -> RoadInfoLaneRule:
        """Explicit source-unit compatibility adapter. Create the explicit compatibility record.
        """
        return RoadInfoLaneRule(_RAW_SI, s, value)

    def __init__(out self, raw: _RawSI, s: Float64, value: String):
        """Create the explicit compatibility record."""
        self.s = s
        self.value = value

    def distance(self) raises -> Length64:
        """Return the checked typed start station.

        Returns:
            The record's finite Float64 start station.

        Raises:
            Error: If the raw station is not finite.
        """
        return Length64(self.distance_meters())

    def distance_meters(self) raises -> Float64:
        """Read the checked explicit meter compatibility view.

        Returns:
            The unchanged Float64 start station in meters.

        Raises:
            Error: If the raw station is not finite.
        """
        return _nonnegative_si(self.s)

    def _distance_si(self) -> Float64:
        return self.s

    def s_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw s compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_nonnegative_si(self.s))


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

    def __init__(out self, s: Length64, speed: Velocity64, type: String) raises:
        """Create a checked typed record without changing scalar storage.

        Args:
            s: Its typed source quantity.
            speed: The finite nonnegative speed quantity.
            type: Its source record value.

        Returns:
            A record with unchanged source precision and layout.

        Raises:
            Error: If a quantity is not finite or another field is invalid.
        """
        self = RoadInfoSpeed.from_si(s.value, speed.value, type, "m/s")

    @staticmethod
    def from_si(
        s: Float64, speed: Float64, type: String, unit: String = ""
    ) raises -> RoadInfoSpeed:
        """Explicit source-unit compatibility adapter. Create a checked numeric source record.

        Args:
            s: Where the record starts, in meters.
            speed: The finite nonnegative source number.
            type: The retained record type.
            unit: The source speed unit; omitted means m/s for road/lane data.

        Returns:
            The new RoadInfoSpeed record with the supplied source fields.

        Raises:
            Error: If the number or source unit is invalid.
        """
        _ = _nonnegative_si(s)
        return RoadInfoSpeed(_RAW_SI, s, speed, type, unit)

    @staticmethod
    def _from_si(
        s: Float64, speed: Float64, type: String, unit: String = ""
    ) raises -> RoadInfoSpeed:
        """Explicit source-unit compatibility adapter. Create a checked numeric source record.

        Args:
            s: Where the record starts, in meters.
            speed: The finite nonnegative source number.
            type: The retained record type.
            unit: The source speed unit; omitted means m/s for road/lane data.

        Raises:
            Error: If the number or source unit is invalid.
        """
        return RoadInfoSpeed(_RAW_SI, s, speed, type, unit)

    def __init__(
        out self,
        raw: _RawSI,
        s: Float64,
        speed: Float64,
        type: String,
        unit: String = "",
    ) raises:
        """Create a checked numeric source record.

        Args:
            raw: The private raw-storage construction capability.
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
        _ = _nonnegative_si(s)
        var out = RoadInfoSpeed._from_si(s, 0, type, unit)
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

    def distance(self) raises -> Length64:
        """Return the checked typed start station.

        Returns:
            The record's finite Float64 start station.

        Raises:
            Error: If the raw station is not finite.
        """
        return Length64(self.distance_meters())

    def distance_meters(self) raises -> Float64:
        """Read the checked explicit meter compatibility view.

        Returns:
            The unchanged Float64 start station in meters.

        Raises:
            Error: If the raw station is not finite.
        """
        return _nonnegative_si(self.s)

    def _distance_si(self) -> Float64:
        return self.s

    def s_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw s compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_nonnegative_si(self.s))


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

    def __init__(
        out self,
        s: Length64,
        road_mark_id: Int,
        length: Length64,
        space: Length64,
        t_offset: Length64,
        rule: String,
        width: Length64,
    ) raises:
        """Create a checked typed record without changing scalar storage.

        Args:
            s: Its typed source quantity.
            road_mark_id: Its source record value.
            length: Its typed source quantity.
            space: Its typed source quantity.
            t_offset: Its typed source quantity.
            rule: Its source record value.
            width: Its typed source quantity.

        Returns:
            A record with unchanged source precision and layout.

        Raises:
            Error: If a quantity is not finite or another field is invalid.
        """
        self = RoadInfoMarkTypeLine.from_si(
            s.value,
            road_mark_id,
            length.value,
            space.value,
            t_offset.value,
            rule,
            width.value,
        )

    @staticmethod
    def from_si(
        s: Float64,
        road_mark_id: Int,
        length: Float64,
        space: Float64,
        t_offset: Float64,
        rule: String,
        width: Float64,
    ) raises -> RoadInfoMarkTypeLine:
        """Explicit source-unit compatibility adapter. Create the explicit compatibility record.

        Args:
            s: The nonnegative record station in meters.
            road_mark_id: The source road-mark identifier.
            length: The nonnegative painted-line length in meters.
            space: The nonnegative gap length in meters.
            t_offset: The signed lateral offset in meters.
            rule: The source line rule text.
            width: The nonnegative line width in meters.

        Returns:
            The new RoadInfoMarkTypeLine record with the supplied source
            fields.

        Raises:
            Error: If a dimensional value is nonfinite, or the station, line
                length, gap, or width is negative.
        """
        _ = _nonnegative_si(s)
        _ = _nonnegative_si(length)
        _ = _nonnegative_si(space)
        _ = _finite_si(t_offset)
        _ = _nonnegative_si(width)
        return RoadInfoMarkTypeLine(
            _RAW_SI, s, road_mark_id, length, space, t_offset, rule, width
        )

    @staticmethod
    def _from_si(
        s: Float64,
        road_mark_id: Int,
        length: Float64,
        space: Float64,
        t_offset: Float64,
        rule: String,
        width: Float64,
    ) -> RoadInfoMarkTypeLine:
        """Explicit source-unit compatibility adapter. Create the explicit compatibility record.
        """
        return RoadInfoMarkTypeLine(
            _RAW_SI, s, road_mark_id, length, space, t_offset, rule, width
        )

    def __init__(
        out self,
        raw: _RawSI,
        s: Float64,
        road_mark_id: Int,
        length: Float64,
        space: Float64,
        t_offset: Float64,
        rule: String,
        width: Float64,
    ):
        """Create the explicit compatibility record."""
        self.s = s
        self.road_mark_id = road_mark_id
        self.length = length
        self.space = space
        self.t_offset = t_offset
        self.rule = rule
        self.width = width

    def distance(self) raises -> Length64:
        """Return the checked typed start station.

        Returns:
            The record's finite Float64 start station.

        Raises:
            Error: If the raw station is not finite.
        """
        return Length64(self.distance_meters())

    def distance_meters(self) raises -> Float64:
        """Read the checked explicit meter compatibility view.

        Returns:
            The unchanged Float64 start station in meters.

        Raises:
            Error: If the raw station is not finite.
        """
        return _nonnegative_si(self.s)

    def _distance_si(self) -> Float64:
        return self.s

    def s_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw s compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_nonnegative_si(self.s))

    def length_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw length compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_nonnegative_si(self.length))

    def space_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw space compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_nonnegative_si(self.space))

    def t_offset_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw t_offset compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_finite_si(self.t_offset))

    def width_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw width compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_nonnegative_si(self.width))


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

    def __init__(out self, s: Length64, road_mark_id: Int) raises:
        """Create a checked typed record without changing scalar storage.

        Args:
            s: Its typed source quantity.
            road_mark_id: Its source record value.

        Returns:
            A record with unchanged source precision and layout.

        Raises:
            Error: If a quantity is not finite or another field is invalid.
        """
        self = RoadInfoMarkRecord.from_si(s.value, road_mark_id)

    @staticmethod
    def from_si(s: Float64, road_mark_id: Int) raises -> RoadInfoMarkRecord:
        """Explicit source-unit compatibility adapter. Create a record with CARLA's defaults: white standard paint
        0.15 meters wide, no lane change, right-hand traffic.

        Args:
            s: Where the mark starts, in meters.
            road_mark_id: The mark's index within its lane.

        Returns:
            The new RoadInfoMarkRecord record with the supplied source fields.

        Raises:
            Error: If the station is nonfinite or negative.
        """
        _ = _nonnegative_si(s)
        return RoadInfoMarkRecord(_RAW_SI, s, road_mark_id)

    @staticmethod
    def _from_si(s: Float64, road_mark_id: Int) -> RoadInfoMarkRecord:
        """Explicit source-unit compatibility adapter. Create a record with CARLA's defaults: white standard paint
        0.15 meters wide, no lane change, right-hand traffic.

        Args:
            s: Where the mark starts, in meters.
            road_mark_id: The mark's index within its lane.
        """
        return RoadInfoMarkRecord(_RAW_SI, s, road_mark_id)

    def __init__(out self, raw: _RawSI, s: Float64, road_mark_id: Int):
        """Create a record with CARLA's defaults: white standard paint
        0.15 meters wide, no lane change, right-hand traffic.

        Args:
            raw: The private raw-storage construction capability.
            s: Where the mark starts, in meters.
            road_mark_id: The mark's index within its lane."""
        self = RoadInfoMarkRecord._from_si(
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
        s: Length64,
        road_mark_id: Int,
        type: String,
        weight: String,
        color: String,
        material: String,
        width: Length64,
        lane_change: MarkLaneChange,
        height: Length64,
        type_name: String,
        type_width: Length64,
        is_rht: Bool,
    ) raises:
        """Create a checked typed record without changing scalar storage.

        Args:
            s: Its typed source quantity.
            road_mark_id: Its source record value.
            type: Its source record value.
            weight: Its source record value.
            color: Its source record value.
            material: Its source record value.
            width: Its typed source quantity.
            lane_change: Its source record value.
            height: Its typed source quantity.
            type_name: Its source record value.
            type_width: Its typed source quantity.
            is_rht: Its source record value.

        Returns:
            A record with unchanged source precision and layout.

        Raises:
            Error: If a quantity is not finite or another field is invalid.
        """
        self = RoadInfoMarkRecord.from_si(
            s.value,
            road_mark_id,
            type,
            weight,
            color,
            material,
            width.value,
            lane_change,
            height.value,
            type_name,
            type_width.value,
            is_rht,
        )

    @staticmethod
    def from_si(
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
    ) raises -> RoadInfoMarkRecord:
        """Explicit source-unit compatibility adapter. Create a record from a file's `roadMark`.

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

        Returns:
            The new RoadInfoMarkRecord record with the supplied source fields.

        Raises:
            Error: If a station or extent is nonfinite or negative, or the
                lane-change value is invalid.
        """
        _ = _nonnegative_si(s)
        _ = _nonnegative_si(width)
        _ = _nonnegative_si(height)
        _ = _nonnegative_si(type_width)
        if not lane_change.is_valid():
            raise Error("Mark lane change is not valid")
        return RoadInfoMarkRecord(
            _RAW_SI,
            s,
            road_mark_id,
            type,
            weight,
            color,
            material,
            width,
            lane_change,
            height,
            type_name,
            type_width,
            is_rht,
        )

    @staticmethod
    def _from_si(
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
    ) -> RoadInfoMarkRecord:
        """Explicit source-unit compatibility adapter. Create a record from a file's `roadMark`.

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
        return RoadInfoMarkRecord(
            _RAW_SI,
            s,
            road_mark_id,
            type,
            weight,
            color,
            material,
            width,
            lane_change,
            height,
            type_name,
            type_width,
            is_rht,
        )

    def __init__(
        out self,
        raw: _RawSI,
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
            raw: The private raw-storage construction capability.
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
            is_rht: True if the road keeps traffic to the right."""
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

    def distance(self) raises -> Length64:
        """Return the checked typed start station.

        Returns:
            The record's finite Float64 start station.

        Raises:
            Error: If the raw station is not finite.
        """
        return Length64(self.distance_meters())

    def distance_meters(self) raises -> Float64:
        """Read the checked explicit meter compatibility view.

        Returns:
            The unchanged Float64 start station in meters.

        Raises:
            Error: If the raw station is not finite.
        """
        return _nonnegative_si(self.s)

    def _distance_si(self) -> Float64:
        return self.s

    def s_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw s compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_nonnegative_si(self.s))

    def width_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw width compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_nonnegative_si(self.width))

    def height_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw height compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_nonnegative_si(self.height))

    def type_width_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw type_width compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_nonnegative_si(self.type_width))


struct CrosswalkPoint(ImplicitlyCopyable):
    """One corner of a crosswalk's outline, in the crosswalk's frame."""

    # Meters along, across and up.
    var u: Float64
    var v: Float64
    var z: Float64

    def u_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw u compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_finite_si(self.u))

    def v_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw v compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_finite_si(self.v))

    def z_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw z compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_finite_si(self.z))

    def __init__(out self, u: Length64, v: Length64, z: Length64) raises:
        """Create a checked typed record without changing scalar storage.

        Args:
            u: Its typed source quantity.
            v: Its typed source quantity.
            z: Its typed source quantity.

        Returns:
            A record with unchanged source precision and layout.

        Raises:
            Error: If a quantity is not finite or another field is invalid.
        """
        self = CrosswalkPoint.from_si(u.value, v.value, z.value)

    @staticmethod
    def from_si(u: Float64, v: Float64, z: Float64) raises -> CrosswalkPoint:
        """Explicit source-unit compatibility adapter. Create the explicit compatibility record.

        Args:
            u: The local longitudinal coordinate in meters.
            v: The local lateral coordinate in meters.
            z: The local height in meters.

        Returns:
            The new CrosswalkPoint record with the supplied source fields.

        Raises:
            Error: If any coordinate is nonfinite.
        """
        _ = _finite_si(u)
        _ = _finite_si(v)
        _ = _finite_si(z)
        return CrosswalkPoint(_RAW_SI, u, v, z)

    @staticmethod
    def _from_si(u: Float64, v: Float64, z: Float64) -> CrosswalkPoint:
        """Explicit source-unit compatibility adapter. Create the explicit compatibility record.
        """
        return CrosswalkPoint(_RAW_SI, u, v, z)

    def __init__(out self, raw: _RawSI, u: Float64, v: Float64, z: Float64):
        """Create the explicit compatibility record."""
        self.u = u
        self.v = v
        self.z = z


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

    def __init__(
        out self,
        s: Length64,
        name: String,
        t: Length64,
        z_offset: Length64,
        heading: Angle64,
        pitch: Angle64,
        roll: Angle64,
        orientation: String,
        width: Length64,
        length: Length64,
        points: List[CrosswalkPoint],
    ) raises:
        """Create a checked typed record without changing scalar storage.

        Args:
            s: Its typed source quantity.
            name: Its source record value.
            t: Its typed source quantity.
            z_offset: Its typed source quantity.
            heading: Its typed source quantity.
            pitch: Its typed source quantity.
            roll: Its typed source quantity.
            orientation: Its source record value.
            width: Its typed source quantity.
            length: Its typed source quantity.
            points: Its source record value.

        Returns:
            A record with unchanged source precision and layout.

        Raises:
            Error: If a quantity is not finite or another field is invalid.
        """
        self = RoadInfoCrosswalk.from_si(
            s.value,
            name,
            t.value,
            z_offset.value,
            heading.value,
            pitch.value,
            roll.value,
            orientation,
            width.value,
            length.value,
            points,
        )

    @staticmethod
    def from_si(
        s: Float64,
        name: String,
        t: Float64,
        z_offset: Float64,
        heading: Float64,
        pitch: Float64,
        roll: Float64,
        orientation: String,
        width: Float64,
        length: Float64,
        points: List[CrosswalkPoint],
    ) raises -> RoadInfoCrosswalk:
        """Explicit source-unit compatibility adapter. Create the explicit compatibility record.

        Args:
            s: The nonnegative road station in meters.
            name: The source crosswalk name.
            t: The signed lateral offset in meters.
            z_offset: The signed height offset in meters.
            heading: The heading in radians.
            pitch: The pitch in radians.
            roll: The roll in radians.
            orientation: The source orientation text.
            width: The nonnegative crosswalk width in meters.
            length: The nonnegative crosswalk length in meters.
            points: The local boundary corners, each in meters.

        Returns:
            The new RoadInfoCrosswalk record with the supplied source fields.

        Raises:
            Error: If a dimensional value or corner coordinate is nonfinite,
                or the station, width, or length is negative.
        """
        _ = _nonnegative_si(s)
        _ = _finite_si(t)
        _ = _finite_si(z_offset)
        _ = _finite_si(heading)
        _ = _finite_si(pitch)
        _ = _finite_si(roll)
        _ = _nonnegative_si(width)
        _ = _nonnegative_si(length)
        for point in points:
            _ = _finite_si(point.u)
            _ = _finite_si(point.v)
            _ = _finite_si(point.z)
        return RoadInfoCrosswalk(
            _RAW_SI,
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
            points,
        )

    @staticmethod
    def _from_si(
        s: Float64,
        name: String,
        t: Float64,
        z_offset: Float64,
        heading: Float64,
        pitch: Float64,
        roll: Float64,
        orientation: String,
        width: Float64,
        length: Float64,
        points: List[CrosswalkPoint],
    ) -> RoadInfoCrosswalk:
        """Explicit source-unit compatibility adapter. Create the explicit compatibility record.
        """
        return RoadInfoCrosswalk(
            _RAW_SI,
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
            points,
        )

    def __init__(
        out self,
        raw: _RawSI,
        s: Float64,
        name: String,
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
        """Create the explicit compatibility record."""
        self.s = s
        self.name = name
        self.t = t
        self.z_offset = z_offset
        self.heading = heading
        self.pitch = pitch
        self.roll = roll
        self.orientation = orientation
        self.width = width
        self.length = length
        self.points = points.copy()

    def distance(self) raises -> Length64:
        """Return the checked typed start station.

        Returns:
            The record's finite Float64 start station.

        Raises:
            Error: If the raw station is not finite.
        """
        return Length64(self.distance_meters())

    def distance_meters(self) raises -> Float64:
        """Read the checked explicit meter compatibility view.

        Returns:
            The unchanged Float64 start station in meters.

        Raises:
            Error: If the raw station is not finite.
        """
        return _nonnegative_si(self.s)

    def _distance_si(self) -> Float64:
        return self.s

    def s_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw s compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_nonnegative_si(self.s))

    def t_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw t compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_finite_si(self.t))

    def z_offset_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw z_offset compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_finite_si(self.z_offset))

    def heading_quantity(self) raises -> Angle64:
        """Read the checked typed view of the raw heading compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Angle64(_finite_si(self.heading))

    def pitch_quantity(self) raises -> Angle64:
        """Read the checked typed view of the raw pitch compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Angle64(_finite_si(self.pitch))

    def roll_quantity(self) raises -> Angle64:
        """Read the checked typed view of the raw roll compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Angle64(_finite_si(self.roll))

    def width_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw width compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_nonnegative_si(self.width))

    def length_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw length compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_nonnegative_si(self.length))


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

    def __init__(
        out self,
        signal_id: SignalId,
        road_id: RoadId,
        s: Length64,
        t: Length64,
        orientation_text: String,
        validities: List[LaneValidity],
    ) raises:
        """Create a checked typed record without changing scalar storage.

        Args:
            signal_id: Its source record value.
            road_id: Its source record value.
            s: Its typed source quantity.
            t: Its typed source quantity.
            orientation_text: Its source record value.
            validities: Its source record value.

        Returns:
            A record with unchanged source precision and layout.

        Raises:
            Error: If a quantity is not finite or another field is invalid.
        """
        self = RoadInfoSignal.from_si(
            signal_id, road_id, s.value, t.value, orientation_text, validities
        )

    @staticmethod
    def from_si(
        signal_id: SignalId,
        road_id: RoadId,
        s: Float64,
        t: Float64,
        orientation_text: String,
        validities: List[LaneValidity],
    ) raises -> RoadInfoSignal:
        """Explicit source-unit compatibility adapter. Create the explicit compatibility record.

        Args:
            signal_id: The signal identifier.
            road_id: The road identifier.
            s: The nonnegative road station in meters.
            t: The signed lateral offset in meters.
            orientation_text: The source orientation text.
            validities: The retained lane-validity records.

        Returns:
            The new RoadInfoSignal record with the supplied source fields.

        Raises:
            Error: If the station is nonfinite or negative, or the lateral
                offset is nonfinite.
        """
        _ = _nonnegative_si(s)
        _ = _finite_si(t)
        return RoadInfoSignal(
            _RAW_SI, signal_id, road_id, s, t, orientation_text, validities
        )

    @staticmethod
    def _from_si(
        signal_id: SignalId,
        road_id: RoadId,
        s: Float64,
        t: Float64,
        orientation_text: String,
        validities: List[LaneValidity],
    ) -> RoadInfoSignal:
        """Explicit source-unit compatibility adapter. Create the explicit compatibility record.
        """
        return RoadInfoSignal(
            _RAW_SI, signal_id, road_id, s, t, orientation_text, validities
        )

    def __init__(
        out self,
        raw: _RawSI,
        signal_id: SignalId,
        road_id: RoadId,
        s: Float64,
        t: Float64,
        orientation_text: String,
        validities: List[LaneValidity],
    ):
        """Create the explicit compatibility record."""
        self.signal_id = signal_id
        self.road_id = road_id
        self.s = s
        self.t = t
        self.orientation_text = orientation_text
        self.validities = validities.copy()

    def distance(self) raises -> Length64:
        """Return the checked typed start station.

        Returns:
            The record's finite Float64 start station.

        Raises:
            Error: If the raw station is not finite.
        """
        return Length64(self.distance_meters())

    def distance_meters(self) raises -> Float64:
        """Read the checked explicit meter compatibility view.

        Returns:
            The unchanged Float64 start station in meters.

        Raises:
            Error: If the raw station is not finite.
        """
        return _nonnegative_si(self.s)

    def _distance_si(self) -> Float64:
        return self.s

    def orientation(self) -> SignalOrientation:
        """Return which way the reference faces, `GetOrientation`.

        Returns:
            Positive for "+", negative for "-", both otherwise.
        """
        return signal_orientation_of(self.orientation_text)

    def s_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw s compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_nonnegative_si(self.s))

    def t_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw t compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_finite_si(self.t))


# --- the set ------------------------------------------------------------------


def info_index[T: RoadInfo](records: List[T], s: Length64) raises -> Int:
    """Search ordered records at typed Float64 stations.

    Args:
        records: The sorted records.
        s: A finite station.

    Returns:
        The same record selection as the source-unit search.

    Raises:
        Error: If a station is not finite.
    """
    return info_index_meters(records, s.value)


def info_index_meters[T: RoadInfo](records: List[T], s: Float64) raises -> Int:
    """Search records through an explicit meter compatibility adapter.

    Args:
        records: The sorted records.
        s: A finite station in meters.

    Returns:
        The source-unit record selection.

    Raises:
        Error: If a station is not finite.
    """
    _ = _finite_si(s)
    return _info_index_si(records, s)


def _info_index_si[T: RoadInfo](records: List[T], s: Float64) -> Int:
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
        if records[mid]._distance_si() <= s:
            lo = mid + 1
        else:
            hi = mid
    return lo - 1


def info_at[T: RoadInfo](records: List[T], s: Length64) raises -> Optional[T]:
    """Search ordered records at typed Float64 stations.

    Args:
        records: The sorted records.
        s: A finite station.

    Returns:
        The same record selection as the source-unit search.

    Raises:
        Error: If a station is not finite.
    """
    return info_at_meters(records, s.value)


def info_at_meters[
    T: RoadInfo
](records: List[T], s: Float64) raises -> Optional[T]:
    """Search records through an explicit meter compatibility adapter.

    Args:
        records: The sorted records.
        s: A finite station in meters.

    Returns:
        The source-unit record selection.

    Raises:
        Error: If a station is not finite.
    """
    _ = _finite_si(s)
    return _info_at_si(records, s)


def _info_at_si[T: RoadInfo](records: List[T], s: Float64) -> Optional[T]:
    """Return the record that holds at s, `InformationSet::GetInfo<T>`.

    Args:
        records: One kind of record, sorted by s.
        s: The distance along the road, in meters.

    Returns:
        The last record that starts at or before s, or None if every one
        starts after it.
    """
    var at = _info_index_si(records, s)
    if at < 0:
        return None
    return records[at].copy()


def infos_in_range[
    T: RoadInfo
](records: List[T], min_s: Length64, max_s: Length64) raises -> List[T]:
    """Search ordered records at typed Float64 stations.

    Args:
        records: The sorted records.
        min_s: A finite station.
        max_s: A finite station.

    Returns:
        The same record selection as the source-unit search.

    Raises:
        Error: If a station is not finite.
    """
    return infos_in_range_meters(records, min_s.value, max_s.value)


def infos_in_range_meters[
    T: RoadInfo
](records: List[T], min_s: Float64, max_s: Float64) raises -> List[T]:
    """Search records through an explicit meter compatibility adapter.

    Args:
        records: The sorted records.
        min_s: A finite station in meters.
        max_s: A finite station in meters.

    Returns:
        The source-unit record selection.

    Raises:
        Error: If a station is not finite.
    """
    _ = _finite_si(min_s)
    _ = _finite_si(max_s)
    return _infos_in_range_si(records, min_s, max_s)


def _infos_in_range_si[
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
            var s = records[i]._distance_si()
            if s >= min_s and s <= max_s:
                out.append(records[i].copy())
        return out^
    for i in range(len(records) - 1, -1, -1):
        var s = records[i]._distance_si()
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
        while (
            j > 0 and records[j - 1]._distance_si() > records[j]._distance_si()
        ):
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

    def __init__(out self, info: RoadInfoMarkRecord) raises:
        """Read a mark record, as `LaneMarking(const RoadInfoMarkRecord &)`.

        "increase" is a change to the right on a right-hand road and to
        the left on a left-hand one; "decrease" the other way.

        Args:
            info: The record.

        Returns:
            The initialized LaneMarking record.

        Raises:
            Error: If the source width is nonfinite or negative, or its lane-
                change value is invalid.
        """
        self = LaneMarking.from_si(info)

    @staticmethod
    def from_si(info: RoadInfoMarkRecord) raises -> LaneMarking:
        """Explicit source-unit compatibility adapter. Read a mark record, as `LaneMarking(const RoadInfoMarkRecord &)`.

        "increase" is a change to the right on a right-hand road and to
        the left on a left-hand one; "decrease" the other way.

        Args:
            info: The record.

        Returns:
            The new LaneMarking record with the supplied source fields.

        Raises:
            Error: If the source width is nonfinite or negative, or its lane-
                change value is invalid.
        """
        _ = _nonnegative_si(info.width)
        if not info.lane_change.is_valid():
            raise Error("Mark lane change is not valid")
        return LaneMarking(_RAW_SI, info)

    @staticmethod
    def _from_si(info: RoadInfoMarkRecord) -> LaneMarking:
        """Explicit source-unit compatibility adapter. Read a mark record, as `LaneMarking(const RoadInfoMarkRecord &)`.

        "increase" is a change to the right on a right-hand road and to
        the left on a left-hand one; "decrease" the other way.

        Args:
            info: The record.
        """
        return LaneMarking(_RAW_SI, info)

    def __init__(out self, raw: _RawSI, info: RoadInfoMarkRecord):
        """Read a mark record, as `LaneMarking(const RoadInfoMarkRecord &)`.

        "increase" is a change to the right on a right-hand road and to
        the left on a left-hand one; "decrease" the other way.

        Args:
            raw: The private raw-storage construction capability.
            info: The record."""
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
        width: Length64,
    ) raises:
        """Create a checked typed record without changing scalar storage.

        Args:
            type: Its source record value.
            color: Its source record value.
            lane_change: Its source record value.
            width: Its typed source quantity.

        Returns:
            A record with unchanged source precision and layout.

        Raises:
            Error: If a quantity is not finite or another field is invalid.
        """
        self = LaneMarking.from_si(type, color, lane_change, width.value)

    @staticmethod
    def from_si(
        type: LaneMarkingType,
        color: LaneMarkingColor,
        lane_change: LaneChange,
        width: Float64,
    ) raises -> LaneMarking:
        """Explicit source-unit compatibility adapter. Create a marking from its parts.

        Args:
            type: How the edge is painted.
            color: The paint's color.
            lane_change: Which way a vehicle may cross.
            width: The paint's width, in meters.

        Returns:
            The new LaneMarking record with the supplied source fields.

        Raises:
            Error: If the type, the color or the lane change is not valid.
        """
        _ = _nonnegative_si(width)
        return LaneMarking(_RAW_SI, type, color, lane_change, width)

    @staticmethod
    def _from_si(
        type: LaneMarkingType,
        color: LaneMarkingColor,
        lane_change: LaneChange,
        width: Float64,
    ) raises -> LaneMarking:
        """Explicit source-unit compatibility adapter. Create a marking from its parts.

        Args:
            type: How the edge is painted.
            color: The paint's color.
            lane_change: Which way a vehicle may cross.
            width: The paint's width, in meters.

        Raises:
            Error: If the type, the color or the lane change is not valid.
        """
        return LaneMarking(_RAW_SI, type, color, lane_change, width)

    def __init__(
        out self,
        raw: _RawSI,
        type: LaneMarkingType,
        color: LaneMarkingColor,
        lane_change: LaneChange,
        width: Float64,
    ) raises:
        """Create a marking from its parts.

        Args:
            raw: The private raw-storage construction capability.
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

    def width_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw width compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_nonnegative_si(self.width))
