# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA OpenDRIVE map records, signal catalogs, deformation and landmarks.

`extensions.carla.map` builds and queries the road network over these
records, re-exporting every public type and constant for compatibility.
"""

from extensions.carla.quantity_boundary import (
    _RAW_SI,
    _RawSI,
    _finite_si,
    _nonnegative_si,
)
from extensions.carla.road_info import (
    ConId,
    ControllerId,
    JuncId,
    LaneId,
    RoadId,
    RoadInfoSignal,
    SectionId,
    SignalId,
    SignalOrientation,
    signal_orientation_of,
)
from extensions.carla.speed_limits import opendrive_speed
from extensions.carla.transform import CarlaRotation, CarlaTransform
from math.bounds import Box3
from math.vector3 import Vector3
from std.hash import Hasher
from std.math import ceil, floor, sin, sqrt
from units.si import Angle, Angle64, DEGREE, Length, Length64, METER, Velocity64

# CARLA's `EPSILON`: waypoints sit this far inside a section's edges.
comptime EPSILON = 10.0 * 2.220446049250313e-16
# `std::numeric_limits<double>::epsilon()`.
comptime DOUBLE_EPSILON = 2.220446049250313e-16


# --- waypoint -----------------------------------------------------------------


struct Waypoint(Hashable, ImplicitlyCopyable, KeyElement, Writable):
    """A place on the road network, `road/element/Waypoint`."""

    var road_id: RoadId
    var section_id: SectionId
    var lane_id: LaneId
    # Meters along the road, in double; see the module docstring.
    var s: Float64

    def __init__(
        out self,
        road_id: RoadId,
        section_id: SectionId,
        lane_id: LaneId,
        s: Length64,
    ) raises:
        """Create a checked typed record without changing scalar storage.

        Args:
            road_id: Its source record value.
            section_id: Its source record value.
            lane_id: Its source record value.
            s: Its typed source quantity.

        Returns:
            A record with unchanged source precision and layout.

        Raises:
            Error: If a quantity is not finite or another field is invalid.
        """
        self = Waypoint.from_si(road_id, section_id, lane_id, s.value)

    @staticmethod
    def from_si(
        road_id: RoadId, section_id: SectionId, lane_id: LaneId, s: Float64
    ) raises -> Waypoint:
        """Explicit source-unit compatibility adapter. Create the explicit compatibility record.

        Args:
            road_id: The road identifier.
            section_id: The lane-section identifier.
            lane_id: The signed lane identifier.
            s: The nonnegative station in meters.

        Returns:
            The new Waypoint record with the supplied source fields.

        Raises:
            Error: If the station is nonfinite or negative.
        """
        _ = _nonnegative_si(s)
        return Waypoint(_RAW_SI, road_id, section_id, lane_id, s)

    @staticmethod
    def _from_si(
        road_id: RoadId, section_id: SectionId, lane_id: LaneId, s: Float64
    ) -> Waypoint:
        """Explicit source-unit compatibility adapter. Create the explicit compatibility record.
        """
        return Waypoint(_RAW_SI, road_id, section_id, lane_id, s)

    def __init__(
        out self,
        raw: _RawSI,
        road_id: RoadId,
        section_id: SectionId,
        lane_id: LaneId,
        s: Float64,
    ):
        """Create the explicit compatibility record."""
        self.road_id = road_id
        self.section_id = section_id
        self.lane_id = lane_id
        self.s = s

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

    def s_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw s compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_nonnegative_si(self.s))


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
        s: Length64,
        t: Length64,
        name: String,
        dynamic: String,
        orientation: String,
        z_offset: Length64,
        country: String,
        type: String,
        subtype: String,
        value: Float64,
        unit: String,
        height: Length64,
        width: Length64,
        text: String,
        h_offset: Angle64,
        pitch: Angle64,
        roll: Angle64,
        value_present: Bool = True,
    ) raises:
        """Create a checked typed record without changing scalar storage.

        Args:
            road_id: Its source record value.
            signal_id: Its source record value.
            s: Its typed source quantity.
            t: Its typed source quantity.
            name: Its source record value.
            dynamic: Its source record value.
            orientation: Its source record value.
            z_offset: Its typed source quantity.
            country: Its source record value.
            type: Its source record value.
            subtype: Its source record value.
            value: Its source record value.
            unit: Its source record value.
            height: Its typed source quantity.
            width: Its typed source quantity.
            text: Its source record value.
            h_offset: Its typed source quantity.
            pitch: Its typed source quantity.
            roll: Its typed source quantity.
            value_present: Its source record value.

        Returns:
            A record with unchanged source precision and layout.

        Raises:
            Error: If a quantity is not finite or another field is invalid.
        """
        self = Signal.from_si(
            road_id,
            signal_id,
            s.value,
            t.value,
            name,
            dynamic,
            orientation,
            z_offset.value,
            country,
            type,
            subtype,
            value,
            unit,
            height.value,
            width.value,
            text,
            h_offset.value,
            pitch.value,
            roll.value,
            value_present,
        )

    @staticmethod
    def from_si(
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
    ) raises -> Signal:
        """Explicit source-unit compatibility adapter. Create a signal from a file's `signal`.

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

        Returns:
            The new Signal record with the supplied source fields.

        Raises:
            Error: If an id is not valid.
        """
        _ = _nonnegative_si(s)
        _ = _finite_si(t)
        _ = _finite_si(z_offset)
        _ = _nonnegative_si(height)
        _ = _nonnegative_si(width)
        _ = _finite_si(h_offset)
        _ = _finite_si(pitch)
        _ = _finite_si(roll)
        return Signal(
            _RAW_SI,
            road_id,
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

    @staticmethod
    def _from_si(
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
    ) raises -> Signal:
        """Explicit source-unit compatibility adapter. Create a signal from a file's `signal`.

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
        return Signal(
            _RAW_SI,
            road_id,
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

    def __init__(
        out self,
        raw: _RawSI,
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
            raw: The private raw-storage construction capability.
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

    def height_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw height compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_nonnegative_si(self.height))

    def width_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw width compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_nonnegative_si(self.width))

    def h_offset_quantity(self) raises -> Angle64:
        """Read the checked typed view of the raw h_offset compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Angle64(_finite_si(self.h_offset))

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

    def valid_length_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw valid_length compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_nonnegative_si(self.valid_length))

    def length_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw length compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_nonnegative_si(self.length))

    def width_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw width compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_nonnegative_si(self.width))

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
        accumulated_s: Length64,
    ) raises:
        """Create a checked typed record without changing scalar storage.

        Args:
            signal: Its source record value.
            waypoint: Its source record value.
            accumulated_s: Its typed source quantity.

        Returns:
            A record with unchanged source precision and layout.

        Raises:
            Error: If a quantity is not finite or another field is invalid.
        """
        self = SignalSearchData.from_si(signal, waypoint, accumulated_s.value)

    @staticmethod
    def from_si(
        signal: RoadInfoSignal,
        waypoint: Waypoint,
        accumulated_s: Float64,
    ) raises -> SignalSearchData:
        """Explicit source-unit compatibility adapter. Create a result.

        Args:
            signal: The signal reference found.
            waypoint: Where it applies.
            accumulated_s: How far from the start, in meters.

        Returns:
            The new SignalSearchData record with the supplied source fields.

        Raises:
            Error: If the accumulated distance is nonfinite or negative.
        """
        _ = _nonnegative_si(accumulated_s)
        return SignalSearchData(_RAW_SI, signal, waypoint, accumulated_s)

    @staticmethod
    def _from_si(
        signal: RoadInfoSignal,
        waypoint: Waypoint,
        accumulated_s: Float64,
    ) -> SignalSearchData:
        """Explicit source-unit compatibility adapter. Create a result.

        Args:
            signal: The signal reference found.
            waypoint: Where it applies.
            accumulated_s: How far from the start, in meters.
        """
        return SignalSearchData(_RAW_SI, signal, waypoint, accumulated_s)

    def __init__(
        out self,
        raw: _RawSI,
        signal: RoadInfoSignal,
        waypoint: Waypoint,
        accumulated_s: Float64,
    ):
        """Create a result.

        Args:
            raw: The private raw-storage construction capability.
            signal: The signal reference found.
            waypoint: Where it applies.
            accumulated_s: How far from the start, in meters."""
        self.signal = signal.copy()
        self.waypoint = waypoint
        self.accumulated_s = accumulated_s

    def accumulated_s_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw accumulated_s compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_nonnegative_si(self.accumulated_s))


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
        distance: Length64,
    ) raises:
        """Create a checked typed record without changing scalar storage.

        Args:
            waypoint: Its source record value.
            reference: Its source record value.
            distance: Its typed source quantity.

        Returns:
            A record with unchanged source precision and layout.

        Raises:
            Error: If a quantity is not finite or another field is invalid.
        """
        self = Landmark.from_si(waypoint, reference, distance.value)

    @staticmethod
    def from_si(
        waypoint: Optional[Waypoint],
        reference: RoadInfoSignal,
        distance: Float64,
    ) raises -> Landmark:
        """Explicit source-unit compatibility adapter. Create a landmark.

        Args:
            waypoint: Where it applies, or None.
            reference: The signal reference.
            distance: Meters from the search's start.

        Returns:
            The new Landmark record with the supplied source fields.

        Raises:
            Error: If the distance is nonfinite or negative.
        """
        _ = _nonnegative_si(distance)
        return Landmark(_RAW_SI, waypoint, reference, distance)

    @staticmethod
    def _from_si(
        waypoint: Optional[Waypoint],
        reference: RoadInfoSignal,
        distance: Float64,
    ) -> Landmark:
        """Explicit source-unit compatibility adapter. Create a landmark.

        Args:
            waypoint: Where it applies, or None.
            reference: The signal reference.
            distance: Meters from the search's start.
        """
        return Landmark(_RAW_SI, waypoint, reference, distance)

    def __init__(
        out self,
        raw: _RawSI,
        waypoint: Optional[Waypoint],
        reference: RoadInfoSignal,
        distance: Float64,
    ):
        """Create a landmark.

        Args:
            raw: The private raw-storage construction capability.
            waypoint: Where it applies, or None.
            reference: The signal reference.
            distance: Meters from the search's start."""
        self.waypoint = waypoint
        self.reference = reference.copy()
        self.distance = distance

    def distance_quantity(self) raises -> Length64:
        """Read the checked typed view of the raw distance compatibility field.

        Returns:
            The same finite Float64 value with its unit.

        Raises:
            Error: If the mutable raw value is not finite.
        """
        return Length64(_nonnegative_si(self.distance))
