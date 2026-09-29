# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's OpenDRIVE reader, `opendrive/OpenDriveParser` and `parser/*`.

`load_opendrive` reads an `.xodr` text with `loaders.xml` and builds a
`Map` with `MapBuilder`, in CARLA's ten passes: the geographic reference,
the roads and their lane sections, the junctions, the plan-view
geometries, the lanes' records, the elevation profiles, the traffic
groups (which CARLA reads and drops), the signals, the objects and the
controllers.

**Numbers are read as pugixml reads them.** CARLA reads every attribute
with pugixml's `as_double`, `as_int`, `as_uint` and `as_bool`, which read
a missing or unreadable attribute as zero or false and stop at the first
character that is not part of the number. `xml_as_double` is
`extensions.carla.geo`'s, and `xml_as_int`, `xml_as_uint` and
`xml_as_bool` below follow pugixml the same way. Some defaults follow
from that and are CARLA's too: a road with no `junction` attribute is in
junction 0, and a `paramPoly3` with no `pRange` is normalized.

**What CARLA reads and drops.** A lateral profile (superelevation,
crossfall and shape) and a `userData` traffic group are read by CARLA and
never reach the map, so this reader skips them. A road's `type` and a
lane's `speed` keep only their number: CARLA drops the unit.

**Objects.** A crosswalk object becomes a crosswalk record. An object
named "Speed_..." or "speed_..." becomes a speed-limit signal of type 274,
and one whose name holds "Stencil_STOP" a stop signal of type 206, as
RoadRunner writes them. A crosswalk with no `outline` reuses the corners
of the crosswalk read before it, as CARLA's does.

Source: CARLA 1360bb9, `LibCarla/source/carla/opendrive/OpenDriveParser.cpp`
and `opendrive/parser/*.cpp`.
"""

from extensions.carla.geo import parse_geo_reference, stod, xml_as_double
from extensions.carla.map import Map
from extensions.carla.map_builder import MapBuilder, SignalReferenceHandle
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road_info import (
    ConId,
    ControllerId,
    CrosswalkPoint,
    JuncId,
    LaneId,
    RoadId,
    SectionId,
    SignalId,
    lane_type_of,
)
from loaders.xml import NO_ELEMENT, XmlDocument, parse_xml
from std.pathlib import Path

comptime _INT32_MIN = -2147483648
comptime _INT32_MAX = 2147483647
comptime _UINT32_MAX = 4294967295


# --- pugixml's readers ----------------------------------------------------


def _hex_digit(c: Int) -> Int:
    # A hexadecimal digit's value, or -1.
    if c >= 48 and c <= 57:
        return c - 48
    var lower = c | 32
    if lower >= 97 and lower <= 102:
        return lower - 87
    return -1


def _integer(text: String, low: Int, high: Int) -> Int:
    # pugixml's `string_to_integer<unsigned int>`: leading space, a sign,
    # then decimal or 0x hexadecimal digits. Out of range clamps.
    var codes = List[Int]()
    for byte in text.as_bytes():
        codes.append(Int(byte))
    codes.append(0)
    var at = 0
    while (
        codes[at] == 32 or codes[at] == 9 or codes[at] == 10 or codes[at] == 13
    ):
        at += 1
    var negative = codes[at] == 45
    if codes[at] == 43 or negative:
        at += 1
    var base = 10
    if codes[at] == 48 and (codes[at + 1] | 32) == 120:
        base = 16
        at += 2
    while codes[at] == 48:
        at += 1
    var start = at
    var result = 0
    while True:
        var digit = _hex_digit(codes[at])
        if digit < 0 or digit >= base:
            break
        if at - start < 12:
            result = result * base + digit
        at += 1
    var digits = at - start
    var limit = 8 if base == 16 else 10
    var overflow = digits > limit or result > _UINT32_MAX
    if negative:
        if overflow or result > -low:
            return low
        return -result
    if overflow or result > high:
        return high
    return result


def xml_as_int(text: String) -> Int:
    """Read an attribute as a signed 32-bit number, pugixml's `as_int`.

    Args:
        text: The attribute's value, empty when it is missing.

    Returns:
        The number the text starts with, clamped to a signed 32-bit
        number, or zero when it starts with none.
    """
    return _integer(text, _INT32_MIN, _INT32_MAX)


def xml_as_uint(text: String) -> Int:
    """Read an attribute as an unsigned 32-bit number, pugixml's `as_uint`.

    Args:
        text: The attribute's value, empty when it is missing.

    Returns:
        The number the text starts with, clamped to an unsigned 32-bit
        number, or zero when it starts with none or with a minus.
    """
    return _integer(text, 0, _UINT32_MAX)


def xml_as_bool(text: String) -> Bool:
    """Read an attribute as a truth value, pugixml's `as_bool`.

    Args:
        text: The attribute's value, empty when it is missing.

    Returns:
        True if it starts with 1, t, T, y or Y.
    """
    var bytes = text.as_bytes()
    if len(bytes) == 0:
        return False
    var c = Int(bytes[0])
    return c == 49 or c == 116 or c == 84 or c == 121 or c == 89


# --- the document ---------------------------------------------------------


struct _Doc(Movable):
    var xml: XmlDocument

    def __init__(out self, var xml: XmlDocument):
        self.xml = xml^

    def top(self) raises -> Int:
        # `xml.child("OpenDRIVE")`.
        if self.xml.name(self.xml.root()) == "OpenDRIVE":
            return self.xml.root()
        return NO_ELEMENT

    def children(self, element: Int, name: String) raises -> List[Int]:
        if element == NO_ELEMENT:
            return List[Int]()
        return self.xml.children_named(element, name)

    def child(self, element: Int, name: String) raises -> Int:
        if element == NO_ELEMENT:
            return NO_ELEMENT
        return self.xml.child(element, name)

    def text(self, element: Int, key: String) raises -> String:
        if element == NO_ELEMENT:
            return ""
        return self.xml.attribute(element, key)

    def has(self, element: Int, key: String) raises -> Bool:
        return self.xml.has_attribute(element, key)

    def double(self, element: Int, key: String) raises -> Float64:
        return xml_as_double(self.text(element, key))

    def int(self, element: Int, key: String) raises -> Int:
        return xml_as_int(self.text(element, key))

    def uint(self, element: Int, key: String) raises -> Int:
        return xml_as_uint(self.text(element, key))


# --- the passes -----------------------------------------------------------


def _roads(doc: _Doc, mut builder: MapBuilder) raises:
    # `RoadParser::Parse`.
    for node in doc.children(doc.top(), "road"):
        var id = RoadId(doc.uint(node, "id"))
        var rule = String("RHT")
        if doc.has(node, "rule"):
            rule = doc.text(node, "rule")
        var is_rht = rule != "LHT"
        if rule != "RHT" and rule != "LHT":
            print(
                "Detected rule '"
                + rule
                + "' for road '"
                + String(id.value)
                + "'. Defaulting to RHT."
            )
        var predecessor = RoadId(0)
        var successor = RoadId(0)
        var link = doc.child(node, "link")
        var before = doc.child(link, "predecessor")
        if before != NO_ELEMENT:
            predecessor = RoadId(doc.uint(before, "elementId"))
        var after = doc.child(link, "successor")
        if after != NO_ELEMENT:
            successor = RoadId(doc.uint(after, "elementId"))
        var road = builder.add_road(
            id,
            doc.text(node, "name"),
            doc.double(node, "length"),
            JuncId(doc.int(node, "junction")),
            predecessor,
            successor,
            is_rht,
        )
        for kind in doc.children(node, "type"):
            var speed = doc.child(kind, "speed")
            var max = 0.0
            var unit = String()
            if speed != NO_ELEMENT:
                max = doc.double(speed, "max")
                unit = doc.text(speed, "unit")
            builder.create_road_speed(
                road, doc.double(kind, "s"), doc.text(kind, "type"), max, unit
            )
        var lanes = doc.child(node, "lanes")
        var offsets = doc.children(lanes, "laneOffset")
        for offset in offsets:
            builder.create_section_offset(
                road,
                doc.double(offset, "s"),
                doc.double(offset, "a"),
                doc.double(offset, "b"),
                doc.double(offset, "c"),
                doc.double(offset, "d"),
            )
        if len(offsets) == 0:
            builder.create_section_offset(road, 0.0, 0.0, 0.0, 0.0, 0.0)
        var number = 0
        for section_node in doc.children(lanes, "laneSection"):
            var section = builder.add_road_section(
                road, SectionId(number), doc.double(section_node, "s")
            )
            number += 1
            # The list is a constant and not empty.
            for side in ["left", "center", "right"]:  # pragma: no branch
                var group = doc.child(section_node, side)
                for lane_node in doc.children(group, "lane"):
                    var lane_link = doc.child(lane_node, "link")
                    var back = LaneId(0)
                    var ahead = LaneId(0)
                    var p = doc.child(lane_link, "predecessor")
                    if p != NO_ELEMENT:
                        back = LaneId(doc.int(p, "id"))
                    var q = doc.child(lane_link, "successor")
                    if q != NO_ELEMENT:
                        ahead = LaneId(doc.int(q, "id"))
                    _ = builder.add_road_section_lane(
                        road,
                        section,
                        LaneId(doc.int(lane_node, "id")),
                        lane_type_of(doc.text(lane_node, "type")),
                        xml_as_bool(doc.text(lane_node, "level")),
                        back,
                        ahead,
                    )


def _junctions(doc: _Doc, mut builder: MapBuilder) raises:
    # `JunctionParser::Parse`.
    for node in doc.children(doc.top(), "junction"):
        var id = JuncId(doc.int(node, "id"))
        builder.add_junction(id, doc.text(node, "name"))
        for connection in doc.children(node, "connection"):
            var con = ConId(doc.uint(connection, "id"))
            builder.add_connection(
                id,
                con,
                RoadId(doc.uint(connection, "incomingRoad")),
                RoadId(doc.uint(connection, "connectingRoad")),
            )
            for link in doc.children(connection, "laneLink"):
                builder.add_lane_link(
                    id,
                    con,
                    LaneId(doc.int(link, "from")),
                    LaneId(doc.int(link, "to")),
                )
        var controllers = List[ControllerId]()
        for controller in doc.children(node, "controller"):
            controllers.append(ControllerId(doc.text(controller, "id")))
        builder.add_junction_controller(id, controllers)


def _geometries(doc: _Doc, mut builder: MapBuilder) raises:
    # `GeometryParser::Parse`.
    for node in doc.children(doc.top(), "road"):
        var id = RoadId(doc.uint(node, "id"))
        for geo in doc.children(doc.child(node, "planView"), "geometry"):
            var kids = doc.xml.children(geo)
            var kind = String()
            var shape = NO_ELEMENT
            if len(kids) > 0:
                shape = kids[0]
                kind = doc.xml.name(shape)
            var road = builder.road_index(id)
            var s = doc.double(geo, "s")
            var x = doc.double(geo, "x")
            var y = doc.double(geo, "y")
            var hdg = doc.double(geo, "hdg")
            var length = doc.double(geo, "length")
            if kind == "line":
                builder.add_road_geometry_line(road, s, x, y, hdg, length)
            elif kind == "arc":
                builder.add_road_geometry_arc(
                    road, s, x, y, hdg, length, doc.double(shape, "curvature")
                )
            elif kind == "spiral":
                builder.add_road_geometry_spiral(
                    road,
                    s,
                    x,
                    y,
                    hdg,
                    length,
                    doc.double(shape, "curvStart"),
                    doc.double(shape, "curvEnd"),
                )
            elif kind == "poly3":
                builder.add_road_geometry_poly3(
                    road,
                    s,
                    x,
                    y,
                    hdg,
                    length,
                    doc.double(shape, "a"),
                    doc.double(shape, "b"),
                    doc.double(shape, "c"),
                    doc.double(shape, "d"),
                )
            elif kind == "paramPoly3":
                builder.add_road_geometry_param_poly3(
                    road,
                    s,
                    x,
                    y,
                    hdg,
                    length,
                    CubicPolynomial(
                        doc.double(shape, "aU"),
                        doc.double(shape, "bU"),
                        doc.double(shape, "cU"),
                        doc.double(shape, "dU"),
                        0.0,
                    ),
                    CubicPolynomial(
                        doc.double(shape, "aV"),
                        doc.double(shape, "bV"),
                        doc.double(shape, "cV"),
                        doc.double(shape, "dV"),
                        0.0,
                    ),
                    doc.text(shape, "pRange"),
                )


def _lane_records(
    doc: _Doc, mut builder: MapBuilder, road_id: RoadId, s: Float64, group: Int
) raises:
    # `LaneParser`'s `ParseLanes`.
    for node in doc.children(group, "lane"):
        var lane_id = LaneId(doc.int(node, "id"))
        var lane = builder.lane(road_id, lane_id, s)
        var widths = doc.children(node, "width")
        for width in widths:
            builder.create_lane_width(
                lane,
                doc.double(width, "sOffset") + s,
                doc.double(width, "a"),
                doc.double(width, "b"),
                doc.double(width, "c"),
                doc.double(width, "d"),
            )
        if len(widths) == 0:
            builder.create_lane_width(lane, s, 0.0, 0.0, 0.0, 0.0)
            if lane_id.value != 0:
                print(
                    "WARNING: In road "
                    + String(road_id.value)
                    + " lane "
                    + String(lane_id.value)
                    + ' no "<width>" parameter found under "<lane>" tag.'
                    + " Using default values."
                )
        for border in doc.children(node, "border"):
            builder.create_lane_border(
                lane,
                doc.double(border, "sOffset") + s,
                doc.double(border, "a"),
                doc.double(border, "b"),
                doc.double(border, "c"),
                doc.double(border, "d"),
            )
        var mark_id = 0
        var is_rht = builder.roads[lane[0]].is_rht
        for mark in doc.children(node, "roadMark"):
            var mark_type = doc.child(mark, "type")
            builder.create_road_mark(
                lane,
                mark_id,
                doc.double(mark, "sOffset") + s,
                doc.text(mark, "type"),
                doc.text(mark, "weight"),
                doc.text(mark, "color"),
                doc.text(mark, "material"),
                doc.double(mark, "width"),
                doc.text(mark, "laneChange"),
                doc.double(mark, "height"),
                doc.text(mark_type, "name"),
                doc.double(mark_type, "width"),
                is_rht,
            )
            for line in doc.children(mark_type, "line"):
                builder.create_road_mark_type_line(
                    lane,
                    mark_id,
                    doc.double(line, "length"),
                    doc.double(line, "space"),
                    doc.double(line, "tOffset"),
                    doc.double(line, "sOffset") + s,
                    doc.text(line, "rule"),
                    doc.double(line, "width"),
                )
            mark_id += 1
        for material in doc.children(node, "material"):
            builder.create_lane_material(
                lane,
                doc.double(material, "sOffset") + s,
                doc.text(material, "surface"),
                doc.double(material, "friction"),
                doc.double(material, "roughness"),
            )
        for sight in doc.children(node, "visibility"):
            builder.create_lane_visibility(
                lane,
                doc.double(sight, "sOffset") + s,
                doc.double(sight, "forward"),
                doc.double(sight, "back"),
                doc.double(sight, "left"),
                doc.double(sight, "right"),
            )
        for speed in doc.children(node, "speed"):
            builder.create_lane_speed(
                lane, doc.double(speed, "sOffset") + s, doc.double(speed, "max")
            )
        for access in doc.children(node, "access"):
            builder.create_lane_access(
                lane,
                doc.double(access, "sOffset") + s,
                doc.text(access, "restriction"),
            )
        for height in doc.children(node, "height"):
            builder.create_lane_height(
                lane,
                doc.double(height, "sOffset") + s,
                doc.double(height, "inner"),
                doc.double(height, "outer"),
            )
        for rule in doc.children(node, "rule"):
            builder.create_lane_rule(
                lane, doc.double(rule, "sOffset") + s, doc.text(rule, "value")
            )


def _lanes(doc: _Doc, mut builder: MapBuilder) raises:
    # `LaneParser::Parse`.
    for road in doc.children(doc.top(), "road"):
        var id = RoadId(doc.uint(road, "id"))
        for lanes in doc.children(road, "lanes"):
            for section in doc.children(lanes, "laneSection"):
                var s = doc.double(section, "s")
                # The list is a constant and not empty.
                for side in ["left", "center", "right"]:  # pragma: no branch
                    var group = doc.child(section, side)
                    if group != NO_ELEMENT:
                        _lane_records(doc, builder, id, s, group)


def _profiles(doc: _Doc, mut builder: MapBuilder) raises:
    # `ProfilesParser::Parse`: the elevation. CARLA drops the lateral
    # profile.
    for node in doc.children(doc.top(), "road"):
        var road = builder.road_index(RoadId(doc.uint(node, "id")))
        var elevations = doc.children(
            doc.child(node, "elevationProfile"), "elevation"
        )
        for elevation in elevations:
            builder.add_road_elevation_profile(
                road,
                doc.double(elevation, "s"),
                doc.double(elevation, "a"),
                doc.double(elevation, "b"),
                doc.double(elevation, "c"),
                doc.double(elevation, "d"),
            )
        if len(elevations) == 0:
            builder.add_road_elevation_profile(road, 0.0, 0.0, 0.0, 0.0, 0.0)


def _validities(
    doc: _Doc,
    mut builder: MapBuilder,
    reference: SignalReferenceHandle,
    node: Int,
) raises:
    for validity in doc.children(node, "validity"):
        builder.add_validity_to_signal_reference(
            reference,
            LaneId(doc.int(validity, "fromLane")),
            LaneId(doc.int(validity, "toLane")),
        )


def _signals(doc: _Doc, mut builder: MapBuilder) raises:
    # `SignalParser::Parse`.
    for road_node in doc.children(doc.top(), "road"):
        var road_id = RoadId(doc.uint(road_node, "id"))
        var signals = doc.child(road_node, "signals")
        for node in doc.children(signals, "signal"):
            var id = SignalId(doc.text(node, "id"))
            var reference = builder.add_signal(
                builder.road_index(road_id),
                id,
                doc.double(node, "s"),
                doc.double(node, "t"),
                doc.text(node, "name"),
                doc.text(node, "dynamic"),
                doc.text(node, "orientation"),
                doc.double(node, "zOffset"),
                doc.text(node, "country"),
                doc.text(node, "type"),
                doc.text(node, "subtype"),
                doc.double(node, "value"),
                doc.text(node, "unit"),
                doc.double(node, "height"),
                doc.double(node, "width"),
                doc.text(node, "text"),
                doc.double(node, "hOffset"),
                doc.double(node, "pitch"),
                doc.double(node, "roll"),
            )
            _validities(doc, builder, reference, node)
            for dependency in doc.children(node, "dependency"):
                builder.add_dependency_to_signal(
                    id, doc.text(dependency, "id"), doc.text(dependency, "type")
                )
            for position in doc.children(node, "positionInertial"):
                builder.add_signal_position_inertial(
                    id,
                    doc.double(position, "x"),
                    doc.double(position, "y"),
                    doc.double(position, "z"),
                    doc.double(position, "hdg"),
                    doc.double(position, "pitch"),
                    doc.double(position, "roll"),
                )
        for node in doc.children(signals, "signalReference"):
            var reference = builder.add_signal_reference(
                builder.road_index(road_id),
                SignalId(doc.text(node, "id")),
                doc.double(node, "s"),
                doc.double(node, "t"),
                doc.text(node, "orientation"),
            )
            _validities(doc, builder, reference, node)


def _objects(doc: _Doc, mut builder: MapBuilder) raises:
    # `ObjectParser::Parse`.
    var points = List[CrosswalkPoint]()
    for road_node in doc.children(doc.top(), "road"):
        var road_id = RoadId(doc.uint(road_node, "id"))
        for node in doc.children(doc.child(road_node, "objects"), "object"):
            var type = doc.text(node, "type")
            var name = doc.text(node, "name")
            var head = String(name[byte = 0 : min(6, name.byte_length())])
            if type == "crosswalk":
                var outline = doc.child(node, "outline")
                if outline != NO_ELEMENT:
                    points.clear()
                    for corner in doc.children(outline, "cornerLocal"):
                        points.append(
                            CrosswalkPoint(
                                doc.double(corner, "u"),
                                doc.double(corner, "v"),
                                doc.double(corner, "z"),
                            )
                        )
                builder.add_road_object_crosswalk(
                    builder.road_index(road_id),
                    name,
                    doc.double(node, "s"),
                    doc.double(node, "t"),
                    doc.double(node, "zOffset"),
                    doc.double(node, "hdg"),
                    doc.double(node, "pitch"),
                    doc.double(node, "roll"),
                    doc.text(node, "orientation"),
                    doc.double(node, "width"),
                    doc.double(node, "length"),
                    points,
                )
            elif head == "Speed_" or head == "speed_":
                var skip = 13 if "STATIC" in name else 6
                if skip > name.byte_length():
                    raise Error("basic_string::substr: the name is too short")
                var speed_text = String(name[byte=skip:])
                _ = builder.add_signal(
                    builder.road_index(road_id),
                    SignalId(doc.text(node, "id")),
                    doc.double(node, "s"),
                    doc.double(node, "t"),
                    name,
                    "no",
                    doc.text(node, "orientation"),
                    doc.double(node, "zOffset"),
                    "OpenDRIVE",
                    "274",
                    speed_text,
                    stod(speed_text),
                    "mph",
                    doc.double(node, "height"),
                    doc.double(node, "width"),
                    speed_text,
                    doc.double(node, "hdg"),
                    doc.double(node, "pitch"),
                    doc.double(node, "roll"),
                )
            elif "Stencil_STOP" in name:
                _ = builder.add_signal(
                    builder.road_index(road_id),
                    SignalId(doc.text(node, "id")),
                    doc.double(node, "s"),
                    doc.double(node, "t"),
                    name,
                    "no",
                    doc.text(node, "orientation"),
                    doc.double(node, "zOffset"),
                    "OpenDRIVE",
                    "206",
                    "",
                    0.0,
                    "mph",
                    doc.double(node, "height"),
                    doc.double(node, "width"),
                    "",
                    doc.double(node, "hdg"),
                    doc.double(node, "pitch"),
                    doc.double(node, "roll"),
                )


def _controllers(doc: _Doc, mut builder: MapBuilder) raises:
    # `ControllerParser::Parse`.
    for node in doc.children(doc.top(), "controller"):
        var signals = List[SignalId]()
        for control in doc.children(node, "control"):
            signals.append(SignalId(doc.text(control, "signalId")))
        builder.create_controller(
            ControllerId(doc.text(node, "id")),
            doc.text(node, "name"),
            doc.uint(node, "sequence"),
            signals,
        )


def load_opendrive(text: String) raises -> Map:
    """Read an OpenDRIVE text into a map, `OpenDriveParser::Load`.

    Args:
        text: The whole `.xodr` file.

    Returns:
        The map. A document whose root is not `OpenDRIVE` gives an empty
        map, as in CARLA.

    Raises:
        Error: If the text is not well-formed XML, a number cannot be
            read where CARLA calls `std::stod`, or the file names a road,
            lane, junction or signal it does not define.
    """
    var doc = _Doc(parse_xml(text))
    var builder = MapBuilder()
    var geo = parse_geo_reference(doc.xml)
    builder.geo_projection = geo[0].copy()
    builder.geo_reference = geo[1]
    _roads(doc, builder)
    _junctions(doc, builder)
    _geometries(doc, builder)
    _lanes(doc, builder)
    _profiles(doc, builder)
    _signals(doc, builder)
    _objects(doc, builder)
    _controllers(doc, builder)
    return builder.build()


def load_opendrive_file(path: String) raises -> Map:
    """Read an `.xodr` file into a map.

    Args:
        path: Where the file is.

    Returns:
        The map.

    Raises:
        Error: If the file cannot be read, or `load_opendrive` raises.
    """
    return load_opendrive(Path(path).read_text())
