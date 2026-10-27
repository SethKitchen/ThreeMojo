# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Restore reviewed border pins from the live consumer files."""

from std.pathlib import Path

from tools._sha256 import sha256_hex


def _split(text: String) -> List[String]:
    """Split `text` into lines that keep their newlines.

    Args:
        text: The source.

    Returns:
        Each line, including an unfinished last line.
    """
    var lines = List[String]()
    if text.byte_length() == 0:
        return lines^
    var rest = text
    while True:
        var at = rest.find("\n")
        if at < 0:
            lines.append(rest)
            return lines^
        var line = String(rest[byte = : at + 1])
        var tail = String(rest[byte = at + 1 :])
        lines.append(line)
        rest = tail


def _join(lines: List[String]) -> String:
    """Join lines that already carry their separators.

    Args:
        lines: The lines.

    Returns:
        The source.
    """
    var text = String()
    for line in lines:
        text += line
    return text


def _apply(
    text: String,
    starts: List[Int],
    stops: List[Int],
    befores: List[String],
) -> String:
    """Replace each span with its predecessor lines.

    Args:
        text: The source.
        starts: The 0-based start lines, highest line first.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.

    Returns:
        The source with those spans replaced.
    """
    var lines = _split(text)
    for index in range(len(starts)):
        var start = starts[index]
        var stop = stops[index]
        var before = _split(befores[index])
        var next = List[String]()
        for slot in range(start):
            next.append(lines[slot])
        for line in before:
            next.append(line)
        for slot in range(stop, len(lines)):
            next.append(lines[slot])
        lines = next^
    return _join(lines)


def _edits_0(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(880)
    stops.append(884)
    befores.append("")
    starts.append(877)
    stops.append(878)
    befores.append("        distance += Float64(\n")
    starts.append(873)
    stops.append(874)
    befores.append("        var nexts = map.next(last.waypoint, step)\n")
    starts.append(845)
    stops.append(846)
    befores.append(
        "            var nexts = map.next(plan[len(plan) - 1].waypoin"
        "t, across)\n"
    )
    starts.append(826)
    stops.append(834)
    befores.append("")
    starts.append(815)
    stops.append(818)
    befores.append(
        "            Error: If the direction is not a valid road opti"
        "on, or a map\n"
    )
    starts.append(59)
    stops.append(60)
    befores.append("    from_kmh,\n")
    starts.append(46)
    stops.append(47)
    befores.append("")


def _edits_1(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(77)
    stops.append(78)
    befores.append("    from_kmh,\n")


def _edits_2(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(315)
    stops.append(318)
    befores.append(
        "            var nexts = map.next(last,"
        " Float64(self.sampling_radius.value))\n"
    )
    starts.append(154)
    stops.append(155)
    befores.append("        var ahead = map.next(w, 3.0)\n")
    starts.append(52)
    stops.append(53)
    befores.append("    from_kmh,\n")


def _edits_3(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(179)
    stops.append(216)
    befores.append("def from_kmh(value: Float64) -> Velocity:\n")
    starts.append(24)
    stops.append(27)
    befores.append("")


def _edits_4(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(476)
    stops.append(477)
    befores.append("                nexts = map.next(reached, res)\n")
    starts.append(466)
    stops.append(468)
    befores.append("            var nexts = map.next(end, res)\n")
    starts.append(379)
    stops.append(380)
    befores.append("                    var step = map.next(w, res)\n")
    starts.append(375)
    stops.append(376)
    befores.append("")
    starts.append(371)
    stops.append(372)
    befores.append("            var first = map.next(pair[0], res)\n")
    starts.append(333)
    stops.append(341)
    befores.append(
        "        if not (sampling_resolution.value > 0.0):\n         "
        '   raise Error("The sampling resolution must be more than z'
        'ero")\n'
    )
    starts.append(329)
    stops.append(332)
    befores.append(
        "            Error: If the resolution is not more than zero, "
        "or a map query\n                fails.\n"
    )
    starts.append(255)
    stops.append(261)
    befores.append("")
    starts.append(94)
    stops.append(95)
    befores.append("")
    starts.append(85)
    stops.append(86)
    befores.append("from std.math import floor, sqrt\n")
    starts.append(74)
    stops.append(75)
    befores.append("from extensions.carla.map import Map, Waypoint\n")
    starts.append(12)
    stops.append(15)
    befores.append(
        "   `sampling_resolution`, and stops one resolution short of "
        "the exit.\n"
    )


def _edits_5(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(1858)
    stops.append(1859)
    befores.append("")
    starts.append(1710)
    stops.append(1711)
    befores.append("")
    starts.append(1600)
    stops.append(1691)
    befores.append("")
    starts.append(1590)
    stops.append(1590)
    befores.append("@fieldwise_init\n")
    starts.append(45)
    stops.append(48)
    befores.append("")


def _edits_6(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(608)
    stops.append(611)
    befores.append("")
    starts.append(356)
    stops.append(472)
    befores.append("")
    starts.append(311)
    stops.append(312)
    befores.append("")
    starts.append(290)
    stops.append(291)
    befores.append("")
    starts.append(283)
    stops.append(284)
    befores.append("    # The shutter time is one over this, in seconds.\n")
    starts.append(207)
    stops.append(208)
    befores.append("")
    starts.append(202)
    stops.append(204)
    befores.append("")
    starts.append(135)
    stops.append(136)
    befores.append("")


def _edits_7(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(21)
    stops.append(22)
    befores.append("from extensions.carla.road_info import info_index\n")


def _edits_8(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(16)
    stops.append(17)
    befores.append("from extensions.carla.road_info import info_index\n")


def _edits_9(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(2015)
    stops.append(2016)
    befores.append("    return OffsetTransform(\n")
    starts.append(2009)
    stops.append(2012)
    befores.append("")
    starts.append(2000)
    stops.append(2001)
    befores.append(") -> Optional[OffsetTransform]:\n")
    starts.append(1985)
    stops.append(1986)
    befores.append('        ellps.from_b(stod(parameters["b"]))\n')
    starts.append(1554)
    stops.append(1557)
    befores.append(
        "    return GeoLocation(_degrees(lat), _degrees(lon),"
        " Float64(location.z))\n"
    )
    starts.append(1452)
    stops.append(1455)
    befores.append(
        "    return GeoLocation(_degrees(lat), _degrees(lon),"
        " Float64(location.z))\n"
    )
    starts.append(1413)
    stops.append(1416)
    befores.append(
        "    return GeoLocation(_degrees(ll[0]), _degrees(ll[1]),"
        " Float64(location.z))\n"
    )
    starts.append(1338)
    stops.append(1341)
    befores.append(
        "    return GeoLocation(_degrees(ll[0]), _degrees(ll[1]),"
        " Float64(location.z))\n"
    )
    starts.append(1021)
    stops.append(1146)
    befores.append("")
    starts.append(952)
    stops.append(1020)
    befores.append(
        '        """Create CARLA\'s default: parallels at -5 and 5, a'
        ' sphere."""\n        self = LambertConformalConicParams(\n           '
        " 0.0, -5.0, 5.0, 0.0, 0.0, 0.0, Ellipsoid()\n"
    )
    starts.append(939)
    stops.append(939)
    befores.append("@fieldwise_init\n")
    starts.append(707)
    stops.append(862)
    befores.append(
        '        """Create CARLA\'s default: origin 0, 0, scale one, a'
        ' sphere."""\n        self = TransverseMercatorParams(0.0, 0.0, 1.0,'
        " 0.0, 0.0, Ellipsoid())\n"
    )
    starts.append(695)
    stops.append(695)
    befores.append("@fieldwise_init\n")
    starts.append(656)
    stops.append(669)
    befores.append("")
    starts.append(544)
    stops.append(586)
    befores.append(
        "        self.offset_x_meters = x_meters\n        self.offset_y_meters"
        " = y_meters\n        self.offset_z_meters = z_meters\n       "
        " self.offset_cos_h = cos(-heading_radians)\n        self.offset_sin_h"
        " = sin(-heading_radians)\n"
    )
    starts.append(533)
    stops.append(543)
    befores.append(
        "            x_meters: The x offset, in meters.\n            y_meters:"
        " The y offset, in meters.\n            z_meters: The z offset, in"
        " meters.\n            heading_radians: The heading, in radians.\n"
    )
    starts.append(529)
    stops.append(531)
    befores.append('    ):\n        """Create an offset.\n')
    starts.append(500)
    stops.append(525)
    befores.append("        out self,\n")
    starts.append(486)
    stops.append(486)
    befores.append("@fieldwise_init\n")
    starts.append(479)
    stops.append(480)
    befores.append(
        "        return Ellipsoid(6370997.0, inf[DType.float64]())\n"
    )
    starts.append(477)
    stops.append(478)
    befores.append("        return Ellipsoid(6378145.0, 298.25)\n")
    starts.append(475)
    stops.append(476)
    befores.append("        return Ellipsoid(6378135.0, 298.26)\n")
    starts.append(473)
    stops.append(474)
    befores.append("        return Ellipsoid(6377563.396, 299.3249646)\n")
    starts.append(471)
    stops.append(472)
    befores.append("        return Ellipsoid(6378206.4, 294.9786982138)\n")
    starts.append(469)
    stops.append(470)
    befores.append("        return Ellipsoid(6377397.155, 299.1528128)\n")
    starts.append(467)
    stops.append(468)
    befores.append("        return Ellipsoid(6378388.0, 297.0)\n")
    starts.append(465)
    stops.append(466)
    befores.append("        return Ellipsoid(6378137.0, 298.257222101)\n")
    starts.append(463)
    stops.append(464)
    befores.append("        return Ellipsoid(6378137.0, 298.257223563)\n")
    starts.append(420)
    stops.append(430)
    befores.append(
        "        self.f_inv = 1.0 / (1.0 - b_meters / self.a_meters)\n"
    )
    starts.append(416)
    stops.append(419)
    befores.append("")
    starts.append(411)
    stops.append(413)
    befores.append("")
    starts.append(409)
    stops.append(410)
    befores.append("    def from_b(mut self, b_meters: Float64):\n")
    starts.append(287)
    stops.append(376)
    befores.append("")
    starts.append(275)
    stops.append(275)
    befores.append("@fieldwise_init\n")
    starts.append(235)
    stops.append(239)
    befores.append(
        "        return Angle(Float32(self.longitude_degrees), DEGREE)\n"
    )
    starts.append(231)
    stops.append(234)
    befores.append("")
    starts.append(226)
    stops.append(227)
    befores.append("    def longitude_angle(self) -> Angle:\n")
    starts.append(223)
    stops.append(224)
    befores.append("")
    starts.append(219)
    stops.append(222)
    befores.append("")
    starts.append(111)
    stops.append(215)
    befores.append("    def latitude_angle(self) -> Angle:\n")
    starts.append(95)
    stops.append(95)
    befores.append("@fieldwise_init\n")
    starts.append(85)
    stops.append(92)
    befores.append("")
    starts.append(65)
    stops.append(67)
    befores.append("from units.si import DEGREE, Angle\n")
    starts.append(23)
    stops.append(28)
    befores.append(
        "`longitude_angle` give `Angle` values for code that does not need"
        " the\nprecision. A location in the CARLA frame is a `Vector3` in"
        " meters, as\n"
    )


def _edits_10(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(296)
    stops.append(297)
    befores.append("        return GeoLocation(\n")
    starts.append(51)
    stops.append(216)
    befores.append("")
    starts.append(26)
    stops.append(27)
    befores.append("")


def _edits_11(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(28)
    stops.append(29)
    befores.append("from extensions.carla.road_info import info_index\n")


def _edits_12(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(287)
    stops.append(288)
    befores.append("    return DirectedPoint(\n")
    starts.append(202)
    stops.append(205)
    befores.append("")
    starts.append(164)
    stops.append(165)
    befores.append("    return DirectedPoint(\n")
    starts.append(133)
    stops.append(138)
    befores.append("    var pieces = 1 + Int(ceil(d * (1.0 + reach)))\n")
    starts.append(85)
    stops.append(86)
    befores.append("    return DirectedPoint(\n")
    starts.append(59)
    stops.append(60)
    befores.append("        return DirectedPoint(\n")
    starts.append(54)
    stops.append(56)
    befores.append(
        "        Error: If a SPIRAL uses an unsupported arithmetic mode.\n"
    )
    starts.append(11)
    stops.append(13)
    befores.append(
        "scalar witnesses with an ideal trigonometric or moment appro"
        "ximation.\n"
    )


def _edits_13(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(1384)
    stops.append(1385)
    befores.append("            RoadInfoGeometry._from_si(s, geometry^)\n")


def _edits_13_b(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(2930)
    stops.append(2931)
    befores.append(
        "    return map.roads[at[0]].lane_width(at[1], at[2], waypoint.s)\n"
    )
    starts.append(2922)
    stops.append(2923)
    befores.append(
        "    return map.roads[at[0]].lane_transform(at[1], at[2], waypoint.s)\n"
    )
    starts.append(2655)
    stops.append(2656)
    befores.append(
        "                for pair in self.roads[r].lanes_by_distance(s):\n"
    )
    starts.append(2603)
    stops.append(2604)
    befores.append(
        "        var point ="
        " self.roads[found.value()].directed_point_no_lane_offset(\n"
    )
    starts.append(2499)
    stops.append(2500)
    befores.append("                )\n")
    starts.append(2497)
    stops.append(2498)
    befores.append(
        "                var found = r.next_lane(s, next) if positive else"
        " r.prev_lane(\n"
    )
    starts.append(2462)
    stops.append(2463)
    befores.append("                for pair in road.lanes_at(road.length):\n")
    starts.append(2455)
    stops.append(2456)
    befores.append("                for pair in road.lanes_at(0.0):\n")
    starts.append(2227)
    stops.append(2228)
    befores.append("            RoadInfoSignal(\n")
    starts.append(2188)
    stops.append(2222)
    befores.append(
        '        if s < 0.0:\n            raise Error("A signal reference'
        ' cannot sit before s = 0")\n'
    )
    starts.append(2171)
    stops.append(2172)
    befores.append(
        '        """Add a reference to a signal, `AddSignalReference`.\n'
    )
    starts.append(2167)
    stops.append(2169)
    befores.append("        s: Float64,\n        t: Float64,\n")
    starts.append(2108)
    stops.append(2152)
    befores.append("")
    starts.append(2093)
    stops.append(2094)
    befores.append(
        '        """Move a signal to another place on a road,'
        " `AddSignalPositionRoad`.\n"
    )
    starts.append(2086)
    stops.append(2092)
    befores.append(
        "        s: Float64,\n        t: Float64,\n        z_offset: Float64,\n"
        "        h_offset: Float64,\n        pitch: Float64,\n        roll:"
        " Float64,\n"
    )
    starts.append(2073)
    stops.append(2081)
    befores.append("")
    starts.append(2063)
    stops.append(2064)
    befores.append(
        "        signal.using_inertial_position = True\n       "
        " signal.transform = CarlaTransform(\n"
    )
    starts.append(2021)
    stops.append(2062)
    befores.append("")
    starts.append(2007)
    stops.append(2008)
    befores.append(
        '        """Place a signal at a point, `AddSignalPositionInertial`.\n'
    )
    starts.append(2000)
    stops.append(2006)
    befores.append(
        "        x: Float64,\n        y: Float64,\n        z: Float64,\n       "
        " heading: Float64,\n        pitch: Float64,\n        roll: Float64,\n"
    )
    starts.append(1989)
    stops.append(1990)
    befores.append(
        "        return self.add_signal_reference(road, signal_id, s, t,"
        " orientation)\n"
    )
    starts.append(1874)
    stops.append(1961)
    befores.append("        var signal = Signal(\n")
    starts.append(1843)
    stops.append(1844)
    befores.append(
        '        """Add a signal and a reference to it on its road,'
        " `AddSignal`.\n"
    )
    starts.append(1838)
    stops.append(1841)
    befores.append(
        "        h_offset: Float64,\n        pitch: Float64,\n        roll:"
        " Float64,\n"
    )
    starts.append(1835)
    stops.append(1837)
    befores.append("        height: Float64,\n        width: Float64,\n")
    starts.append(1829)
    stops.append(1830)
    befores.append("        z_offset: Float64,\n")
    starts.append(1824)
    stops.append(1826)
    befores.append("        s: Float64,\n        t: Float64,\n")
    starts.append(1804)
    stops.append(1812)
    befores.append("")
    starts.append(1798)
    stops.append(1799)
    befores.append(
        '            p_range: "arcLength", or anything else for a normalized'
        " p.\n"
    )
    starts.append(1787)
    stops.append(1788)
    befores.append(
        '        """Add a parametric cubic, `AddRoadGeometryParamPoly3`.\n'
    )
    starts.append(1699)
    stops.append(1776)
    befores.append("")
    starts.append(1642)
    stops.append(1694)
    befores.append("")
    starts.append(1625)
    stops.append(1626)
    befores.append('        """Add a cubic v(u), `AddRoadGeometryPoly3`.\n')
    starts.append(1622)
    stops.append(1624)
    befores.append("        c: Float64,\n        d: Float64,\n")
    starts.append(1615)
    stops.append(1621)
    befores.append(
        "        s: Float64,\n        x: Float64,\n        y: Float64,\n       "
        " heading: Float64,\n        length: Float64,\n        a: Float64,\n"
    )
    starts.append(1558)
    stops.append(1603)
    befores.append("")
    starts.append(1543)
    stops.append(1544)
    befores.append('        """Add a clothoid, `AddRoadGeometrySpiral`.\n')
    starts.append(1535)
    stops.append(1542)
    befores.append(
        "        s: Float64,\n        x: Float64,\n        y: Float64,\n       "
        " heading: Float64,\n        length: Float64,\n        curvature_start:"
        " Float64,\n        curvature_end: Float64,\n"
    )
    starts.append(1486)
    stops.append(1528)
    befores.append("")
    starts.append(1440)
    stops.append(1472)
    befores.append('        """Add an arc, `AddRoadGeometryArc`.\n')
    starts.append(1439)
    stops.append(1439)
    befores.append("        curvature: Float64,\n")
    starts.append(1431)
    stops.append(1432)
    befores.append("    def add_road_geometry_arc(\n")
    starts.append(1427)
    stops.append(1430)
    befores.append(
        "        self._geometry(road, self._base(s, x, y, heading, length))\n"
    )
    starts.append(1414)
    stops.append(1415)
    befores.append(
        '        """Add a straight geometry, `AddRoadGeometryLine`.\n'
    )
    starts.append(1408)
    stops.append(1413)
    befores.append(
        "        s: Float64,\n        x: Float64,\n        y: Float64,\n       "
        " heading: Float64,\n        length: Float64,\n"
    )
    starts.append(1396)
    stops.append(1397)
    befores.append("        return RoadGeometry(\n")
    starts.append(1383)
    stops.append(1386)
    befores.append(
        "        self.roads[road].info.geometries.append(RoadInfoGeometry(s,"
        " geometry^))\n"
    )
    starts.append(1366)
    stops.append(1367)
    befores.append("            RoadInfoCrosswalk(\n")
    starts.append(1302)
    stops.append(1365)
    befores.append("")
    starts.append(1297)
    stops.append(1301)
    befores.append("")
    starts.append(1281)
    stops.append(1283)
    befores.append(
        '    ):\n        """Add a crosswalk, `AddRoadObjectCrosswalk`.\n'
    )
    starts.append(1278)
    stops.append(1280)
    befores.append("        width: Float64,\n        length: Float64,\n")
    starts.append(1271)
    stops.append(1277)
    befores.append(
        "        s: Float64,\n        t: Float64,\n        z_offset: Float64,\n"
        "        heading: Float64,\n        pitch: Float64,\n        roll:"
        " Float64,\n"
    )
    starts.append(1261)
    stops.append(1263)
    befores.append("")
    starts.append(1249)
    stops.append(1250)
    befores.append(
        '        """Add a numeric, unrestricted, undefined or absent road'
        " speed.\n"
    )
    starts.append(1241)
    stops.append(1242)
    befores.append("    def create_road_speed(\n")
    starts.append(1238)
    stops.append(1239)
    befores.append('        var record = RoadInfoSpeed(s, max, "Town", unit)\n')
    starts.append(1235)
    stops.append(1237)
    befores.append("")
    starts.append(1223)
    stops.append(1224)
    befores.append(
        '        """Add a numeric road speed without dropping its unit.\n'
    )
    starts.append(1196)
    stops.append(1216)
    befores.append("")
    starts.append(1190)
    stops.append(1193)
    befores.append(
        "            RoadInfoLaneOffset(s, CubicPolynomial(a, b, c, d, s))\n"
    )
    starts.append(1157)
    stops.append(1189)
    befores.append("")
    starts.append(1152)
    stops.append(1156)
    befores.append("")
    starts.append(1108)
    stops.append(1144)
    befores.append(
        '    ):\n        """Add a lane offset record, `CreateSectionOffset`.\n'
    )
    starts.append(1100)
    stops.append(1101)
    befores.append("    def create_section_offset(\n")
    starts.append(1096)
    stops.append(1098)
    befores.append(
        "        self.roads[road].info.elevations.append(\n           "
        " RoadInfoElevation(s, CubicPolynomial(a, b, c, d, s))\n"
    )
    starts.append(1091)
    stops.append(1095)
    befores.append("")
    starts.append(1079)
    stops.append(1083)
    befores.append(
        '        c: Float64,\n        d: Float64,\n    ):\n        """Add an'
        " elevation record, `AddRoadElevationProfile`.\n"
    )
    starts.append(1076)
    stops.append(1078)
    befores.append("        s: Float64,\n        a: Float64,\n")
    starts.append(1060)
    stops.append(1061)
    befores.append("                    RoadInfoMarkTypeLine(\n")
    starts.append(1009)
    stops.append(1056)
    befores.append("")
    starts.append(1004)
    stops.append(1008)
    befores.append("")
    starts.append(988)
    stops.append(991)
    befores.append(
        '        width: Float64,\n    ):\n        """Add a line to a road'
        " mark's type, `CreateRoadMarkTypeLine`.\n"
    )
    starts.append(983)
    stops.append(987)
    befores.append(
        "        length: Float64,\n        space: Float64,\n        t_offset:"
        " Float64,\n        s: Float64,\n"
    )
    starts.append(963)
    stops.append(964)
    befores.append("            RoadInfoMarkRecord(\n")
    starts.append(903)
    stops.append(962)
    befores.append("")
    starts.append(898)
    stops.append(902)
    befores.append("")
    starts.append(880)
    stops.append(882)
    befores.append('    ):\n        """Add a road mark, `CreateRoadMark`.\n')
    starts.append(878)
    stops.append(879)
    befores.append("        type_width: Float64,\n")
    starts.append(876)
    stops.append(877)
    befores.append("        height: Float64,\n")
    starts.append(874)
    stops.append(875)
    befores.append("        width: Float64,\n")
    starts.append(869)
    stops.append(870)
    befores.append("        s: Float64,\n")
    starts.append(860)
    stops.append(862)
    befores.append("")
    starts.append(849)
    stops.append(850)
    befores.append(
        '        """Add a numeric lane speed directly from OpenDRIVE text.\n'
    )
    starts.append(842)
    stops.append(843)
    befores.append("    def create_lane_speed(\n")
    starts.append(837)
    stops.append(840)
    befores.append('        var record = RoadInfoSpeed(s, max, "Town", unit)\n')
    starts.append(826)
    stops.append(827)
    befores.append(
        '        """Add a numeric lane speed without dropping its source'
        " unit.\n"
    )
    starts.append(802)
    stops.append(820)
    befores.append("")
    starts.append(798)
    stops.append(799)
    befores.append("            RoadInfoLaneAccess(s, restriction)\n")
    starts.append(780)
    stops.append(797)
    befores.append("")
    starts.append(776)
    stops.append(779)
    befores.append("")
    starts.append(768)
    stops.append(771)
    befores.append(
        "        mut self, lane: Tuple[Int, Int, Int], s: Float64, restriction:"
        ' String\n    ):\n        """Add an access record,'
        " `CreateLaneAccess`.\n"
    )
    starts.append(764)
    stops.append(765)
    befores.append(
        "            RoadInfoLaneVisibility(s, forward, back, left, right)\n"
    )
    starts.append(730)
    stops.append(763)
    befores.append("")
    starts.append(725)
    stops.append(729)
    befores.append("")
    starts.append(710)
    stops.append(717)
    befores.append(
        "        s: Float64,\n        forward: Float64,\n        back:"
        " Float64,\n        left: Float64,\n        right: Float64,\n    ):\n  "
        '      """Add a visibility record, `CreateLaneVisibility`.\n'
    )
    starts.append(688)
    stops.append(706)
    befores.append(
        "        self._lane(lane).info.rules.append(RoadInfoLaneRule(s,"
        " value))\n"
    )
    starts.append(684)
    stops.append(687)
    befores.append("")
    starts.append(676)
    stops.append(679)
    befores.append(
        "        mut self, lane: Tuple[Int, Int, Int], s: Float64, value:"
        ' String\n    ):\n        """Add a rule record, `CreateLaneRule`.\n'
    )
    starts.append(672)
    stops.append(673)
    befores.append(
        "            RoadInfoLaneMaterial(s, surface, friction, roughness)\n"
    )
    starts.append(645)
    stops.append(671)
    befores.append("")
    starts.append(641)
    stops.append(644)
    befores.append("")
    starts.append(632)
    stops.append(634)
    befores.append(
        '    ):\n        """Add a material record, `CreateLaneMaterial`.\n'
    )
    starts.append(628)
    stops.append(629)
    befores.append("        s: Float64,\n")
    starts.append(622)
    stops.append(623)
    befores.append("            RoadInfoLaneHeight(s, inner, outer)\n")
    starts.append(596)
    stops.append(621)
    befores.append("")
    starts.append(591)
    stops.append(595)
    befores.append("")
    starts.append(580)
    stops.append(585)
    befores.append(
        "        s: Float64,\n        inner: Float64,\n        outer:"
        ' Float64,\n    ):\n        """Add a height record,'
        " `CreateLaneHeight`.\n"
    )
    starts.append(540)
    stops.append(575)
    befores.append(
        "            RoadInfoLaneBorder(s, CubicPolynomial(a, b, c, d, s))\n"
    )
    starts.append(509)
    stops.append(539)
    befores.append("")
    starts.append(504)
    stops.append(508)
    befores.append("")
    starts.append(460)
    stops.append(496)
    befores.append(
        '    ):\n        """Add a border record, `CreateLaneBorder`.\n'
    )
    starts.append(452)
    stops.append(453)
    befores.append("    def create_lane_border(\n")
    starts.append(450)
    stops.append(451)
    befores.append(
        "        self._lane(lane).info.widths.append(\n           "
        " RoadInfoLaneWidth(s, CubicPolynomial(a, b, c, d, s))\n        )\n"
    )
    starts.append(445)
    stops.append(449)
    befores.append("")
    starts.append(433)
    stops.append(437)
    befores.append(
        '        c: Float64,\n        d: Float64,\n    ):\n        """Add a'
        " width record, `CreateLaneWidth`.\n"
    )
    starts.append(430)
    stops.append(432)
    befores.append("        s: Float64,\n        a: Float64,\n")
    starts.append(422)
    stops.append(423)
    befores.append(
        "        var found = self.roads[r].lane_by_distance(s, lane_id)\n"
    )
    starts.append(401)
    stops.append(421)
    befores.append("")
    starts.append(388)
    stops.append(389)
    befores.append(
        '        """Return the lane with an id at s, `MapBuilder::GetLane`.\n'
    )
    starts.append(386)
    stops.append(387)
    befores.append(
        "        self, road_id: RoadId, lane_id: LaneId, s: Float64\n"
    )
    starts.append(320)
    stops.append(341)
    befores.append("        return self.roads[road].add_section(id, s)\n")
    starts.append(307)
    stops.append(308)
    befores.append('        """Add a lane section, `AddRoadSection`.\n')
    starts.append(305)
    stops.append(306)
    befores.append("        mut self, road: Int, id: SectionId, s: Float64\n")
    starts.append(236)
    stops.append(271)
    befores.append("        var road = Road(\n")
    starts.append(218)
    stops.append(219)
    befores.append(
        '        """Add a road, `AddRoad`. A second road with the same id'
        " resets the\n"
    )
    starts.append(212)
    stops.append(213)
    befores.append("        length: Float64,\n")
    starts.append(115)
    stops.append(131)
    befores.append("from units.si import DEGREE, Angle, Length, METER\n")
    starts.append(55)
    stops.append(60)
    befores.append(
        "    with_arc,\n    with_param_poly3,\n    with_poly3,\n   "
        " with_spiral,\n"
    )


def _edits_14(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(323)
    stops.append(326)
    befores.append("")
    starts.append(321)
    stops.append(322)
    befores.append(
        "        for i in range(a, b - 1, -1):  # pragma: no branch\n"
    )
    starts.append(317)
    stops.append(320)
    befores.append("")
    starts.append(315)
    stops.append(316)
    befores.append("        for i in range(a, b + 1):  # pragma: no branch\n")
    starts.append(313)
    stops.append(314)
    befores.append("")
    starts.append(302)
    stops.append(312)
    befores.append("")
    starts.append(298)
    stops.append(301)
    befores.append("")
    starts.append(284)
    stops.append(289)
    befores.append("def generate_range(a: Int, b: Int) -> List[Int]:\n")
    starts.append(192)
    stops.append(193)
    befores.append("    var l2 = distance_squared_2d(v, w)\n")
    starts.append(153)
    stops.append(154)
    befores.append(
        "    return Length(sqrt(distance_squared_2d(a, b)), METER)\n"
    )
    starts.append(89)
    stops.append(129)
    befores.append(
        "def distance_squared_2d(a: Vector3, b: Vector3) -> Float32:\n"
    )
    starts.append(38)
    stops.append(41)
    befores.append("")


def _edits_15(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(2592)
    stops.append(2601)
    befores.append("")
    starts.append(2484)
    stops.append(2485)
    befores.append(
        "                s += Float64(distance_between_trees.value)\n"
    )
    starts.append(2472)
    stops.append(2473)
    befores.append(
        "                    var rotation = road.lane_transform(sec, ln,"
        " s).rotation\n"
    )
    starts.append(2461)
    stops.append(2464)
    befores.append(
        "                        s += Float64(distance_between_trees.value)\n"
    )
    starts.append(2449)
    stops.append(2454)
    befores.append(
        "                if road.lane_width(sec, ln, s) != 0.0:\n              "
        "      var edges = road.lane_corners(sec, ln, s, 0.0)\n"
    )
    starts.append(2444)
    stops.append(2448)
    befores.append(
        "            var s_end = section.s + road.section_length(sec)\n"
    )
    starts.append(2414)
    stops.append(2417)
    befores.append("")
    starts.append(2314)
    stops.append(2315)
    befores.append("                    var w = map.waypoint_xodr(\n")
    starts.append(2311)
    stops.append(2313)
    befores.append(
        "                        the_lane.distance +"
        " road.section_length(section) * 0.5\n"
    )
    starts.append(2260)
    stops.append(2262)
    befores.append(
        "        var s = section.s + road.section_length(0) * 0.5\n        var"
        " at = road.lane_transform(0, lane, s).location\n"
    )
    starts.append(2171)
    stops.append(2180)
    befores.append(
        "    var nx = Int((high.x - low.x) / size) + 1\n    var ny ="
        " Int((high.y - low.y) / size) + 1\n"
    )
    starts.append(1959)
    stops.append(1960)
    befores.append("            e = self.compute_edges_for_lanemark(\n")
    starts.append(1954)
    stops.append(1955)
    befores.append(
        "        var width = LaneMarking(info_at(marks, s).value()).width\n"
    )
    starts.append(1948)
    stops.append(1949)
    befores.append("                s += step\n")
    starts.append(1946)
    stops.append(1947)
    befores.append("                s += step * 3.0\n")
    starts.append(1939)
    stops.append(1941)
    befores.append(
        "                s = min(s + step * 3.0, s_end)\n                e ="
        " self.compute_edges_for_lanemark(\n"
    )
    starts.append(1935)
    stops.append(1936)
    befores.append("                var e = self.compute_edges_for_lanemark(\n")
    starts.append(1933)
    stops.append(1934)
    befores.append("                s += step\n")
    starts.append(1927)
    stops.append(1928)
    befores.append("                    e = self.compute_edges_for_lanemark(\n")
    starts.append(1920)
    stops.append(1921)
    befores.append("            var info = LaneMarking(found.value())\n")
    starts.append(1913)
    stops.append(1916)
    befores.append("")
    starts.append(1911)
    stops.append(1912)
    befores.append("")
    starts.append(1908)
    stops.append(1909)
    befores.append(
        "        var s_end = s_start + road.section_length(section)\n"
    )
    starts.append(1892)
    stops.append(1893)
    befores.append("        var right = road.directed_point(s)\n")
    starts.append(1875)
    stops.append(1876)
    befores.append(
        "                var e = road.lane_corners(section, other, s,"
        " extra_width)\n"
    )
    starts.append(1866)
    stops.append(1867)
    befores.append(
        "        var edges = road.lane_corners(section, lane, s, extra_width)\n"
    )
    starts.append(1773)
    stops.append(1842)
    befores.append("")
    starts.append(1525)
    stops.append(1526)
    befores.append(
        "    def _link_kinds(self, lane_type: LaneType) -> List[SurfaceKind]:\n"
    )
    starts.append(1518)
    stops.append(1519)
    befores.append("    def _link_width(self, lane_type: LaneType) -> Int:\n")
    starts.append(1513)
    stops.append(1517)
    befores.append(
        "            return self.generate_tesselated(road, section, lane,"
        " s_start, s_end)\n        return self.generate_sidewalk(road, section,"
        " lane, s_start, s_end)\n"
    )
    starts.append(1383)
    stops.append(1384)
    befores.append("            road.section_length(section)\n")
    starts.append(1376)
    stops.append(1377)
    befores.append("            s += max_len\n")
    starts.append(1373)
    stops.append(1375)
    befores.append("")
    starts.append(1370)
    stops.append(1372)
    befores.append("")
    starts.append(1366)
    stops.append(1368)
    befores.append(
        "        var length = road.section_length(section)\n        var max_len"
        " = Float64(self.road_param.max_road_len.value)\n"
    )
    starts.append(1227)
    stops.append(1283)
    befores.append("")
    starts.append(1143)
    stops.append(1199)
    befores.append("")
    starts.append(1129)
    stops.append(1130)
    befores.append(
        "            var edges = road.lane_corners(section, lane, s,"
        " self._extra())\n"
    )
    starts.append(1042)
    stops.append(1043)
    befores.append(
        "        return self.generate_sidewalk(road, section, lane, span[0],"
        " span[1])\n"
    )
    starts.append(924)
    stops.append(992)
    befores.append("")
    starts.append(898)
    stops.append(900)
    befores.append(
        "            var e = road.lane_corners(section, lane, s,"
        " self._extra())\n            var t = road.lane_edge_offsets(section,"
        " lane, s, self._extra())\n"
    )
    starts.append(877)
    stops.append(880)
    befores.append(
        "        return self.generate_tesselated(road, section, lane, span[0],"
        " span[1])\n"
    )
    starts.append(774)
    stops.append(832)
    befores.append("")
    starts.append(749)
    stops.append(751)
    befores.append(
        "            var edges = road.lane_corners(section, lane, s,"
        " self._extra())\n            var offsets = road.lane_edge_offsets(\n"
    )
    starts.append(744)
    stops.append(746)
    befores.append("")
    starts.append(727)
    stops.append(728)
    befores.append(
        "        return self.generate_lane(road, section, lane, span[0],"
        " span[1])\n"
    )
    starts.append(628)
    stops.append(684)
    befores.append("")
    starts.append(618)
    stops.append(620)
    befores.append(
        "            var edges = road.lane_corners(section, lane, s,"
        " self._extra())\n            var offsets = road.lane_edge_offsets(\n"
    )
    starts.append(589)
    stops.append(593)
    befores.append(
        "        return (start + EPSILON, start + road.section_length(section)"
        " - EPSILON)\n"
    )
    starts.append(580)
    stops.append(581)
    befores.append("            s += step\n")
    starts.append(577)
    stops.append(579)
    befores.append("")
    starts.append(571)
    stops.append(573)
    befores.append("")
    starts.append(562)
    stops.append(563)
    befores.append("                s += step\n")
    starts.append(559)
    stops.append(561)
    befores.append("")
    starts.append(550)
    stops.append(552)
    befores.append("")
    starts.append(536)
    stops.append(540)
    befores.append("    def _width_vertices(self) -> Int:\n")
    starts.append(534)
    stops.append(535)
    befores.append("        return Float64(self.road_param.resolution.value)\n")
    starts.append(81)
    stops.append(82)
    befores.append("    info_at,\n")
    starts.append(54)
    stops.append(57)
    befores.append("")


def _edits_16(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(1358)
    stops.append(1360)
    befores.append(
        "                    var a = road.lane_corners(sec, ln, stati"
        "ons[k])\n                    var b = road.lane_corners(sec, "
        "ln, stations[k + 1])\n"
    )
    starts.append(1346)
    stops.append(1347)
    befores.append(
        "                s0, s0 + road.section_length(sec), step, cuts\n"
    )
    starts.append(1339)
    stops.append(1339)
    befores.append("    var step = Float64(resolution.value)\n")
    starts.append(1332)
    stops.append(1337)
    befores.append(
        '    if not (resolution.value > 0.0):\n        raise Error("'
        'The mesh resolution must be more than zero")\n'
    )
    starts.append(1328)
    stops.append(1331)
    befores.append(
        "        Error: If the resolution is not more than zero, or a"
        " map query\n            fails.\n"
    )
    starts.append(1295)
    stops.append(1298)
    befores.append("")
    starts.append(1293)
    stops.append(1294)
    befores.append(") -> List[Float64]:\n")
    starts.append(521)
    stops.append(522)
    befores.append(
        "            return Vector3(point.x, point.y, self.height_at(point))\n"
    )
    starts.append(433)
    stops.append(482)
    befores.append("    def height_at(self, point: Vector3) -> Float32:\n")
    starts.append(87)
    stops.append(89)
    befores.append("")
    starts.append(46)
    stops.append(48)
    befores.append("")
    starts.append(14)
    stops.append(18)
    befores.append(
        "  ends of each crosswalk. Each strip is a convex quad from t"
        "he lane's two\n  edges, `Road.lane_corners`, which also rais"
        "e a sidewalk by its curb. A\n"
    )


def _edits_17(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(201)
    stops.append(202)
    befores.append(
        "    var line ="
        " map.road(signal.road_id).directed_point(signal.s).to_carla()\n"
    )


def _edits_18(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(354)
    stops.append(355)
    befores.append("")
    starts.append(309)
    stops.append(311)
    befores.append("                or the scene cannot be tested.\n")
    starts.append(160)
    stops.append(232)
    befores.append("")
    starts.append(152)
    stops.append(152)
    befores.append("@fieldwise_init\n")
    starts.append(140)
    stops.append(150)
    befores.append(
        "        return Int(Float32(self.points_per_second) * tick.to"
        "(SECOND))\n"
    )
    starts.append(135)
    stops.append(139)
    befores.append("")
    starts.append(126)
    stops.append(129)
    befores.append("")
    starts.append(124)
    stops.append(125)
    befores.append("    def points_in(self, tick: Duration) -> Int:\n")
    starts.append(49)
    stops.append(50)
    befores.append("from std.math import atan2, cos, sin, sqrt, tan\n")
    starts.append(30)
    stops.append(38)
    befores.append("")


def _edits_19(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(902)
    stops.append(905)
    befores.append("        self.frames.set_frame(delta_seconds)\n")
    starts.append(864)
    stops.append(884)
    befores.append("")
    starts.append(801)
    stops.append(804)
    befores.append(
        "        self.write_frame(world.delta_seconds, world.elapsed_seconds,"
        " platform)\n"
    )
    starts.append(466)
    stops.append(469)
    befores.append(
        "        _ = self.begin(name, map_name, additional_data, date,"
        " saved_dir)\n"
    )
    starts.append(455)
    stops.append(457)
    befores.append(
        "            date: The date for the header in seconds since 1970, or -1"
        " for\n                now.\n"
    )
    starts.append(439)
    stops.append(443)
    befores.append('        """Start a recording of a world, `Start`.\n')
    starts.append(430)
    stops.append(431)
    befores.append("    def start(\n")
    starts.append(397)
    stops.append(399)
    befores.append(
        "            date: The date for the header in seconds since 1970, or -1"
        " for\n                now.\n"
    )
    starts.append(381)
    stops.append(387)
    befores.append(
        '        """Start an empty recording: write the header and turn on.\n'
    )
    starts.append(326)
    stops.append(378)
    befores.append("")
    starts.append(134)
    stops.append(135)
    befores.append("    time_packet,\n")
    starts.append(73)
    stops.append(76)
    befores.append("")


def _edits_20(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(1945)
    stops.append(1946)
    befores.append("")
    starts.append(1916)
    stops.append(1935)
    befores.append(
        "def time_packet(mut w: ByteWriter, id: RecorderPacketId, time:"
        " Float64) raises:\n"
    )
    starts.append(606)
    stops.append(607)
    befores.append("            self.frame.elapsed += delta_seconds\n")
    starts.append(597)
    stops.append(601)
    befores.append("")
    starts.append(592)
    stops.append(596)
    befores.append("")
    starts.append(573)
    stops.append(585)
    befores.append("    def set_frame(mut self, delta_seconds: Float64):\n")
    starts.append(63)
    stops.append(66)
    befores.append("")


def _edits_21(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(479)
    stops.append(480)
    befores.append(
        "        var sigma = fog_density_at(fog, Length(point.y, METER))\n"
    )
    starts.append(380)
    stops.append(419)
    befores.append(
        "def fog_density_at(fog: HeightFog, height: Length) -> Float32:\n"
    )
    starts.append(37)
    stops.append(40)
    befores.append("")


def _edits_22(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(729)
    stops.append(730)
    befores.append("    def _weather(mut self, mut world: World):\n")
    starts.append(122)
    stops.append(123)
    befores.append("    set_walker_speed,\n")


def _edits_23(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(698)
    stops.append(699)
    befores.append("            set_walker_speed(world, id, 0)\n")
    starts.append(611)
    stops.append(613)
    befores.append("")
    starts.append(609)
    stops.append(610)
    befores.append("        Error: Never; the check comes first.\n")
    starts.append(577)
    stops.append(600)
    befores.append(
        "def set_walker_speed(mut world: World, id: ActorId, speed: Float32)"
        " raises:\n"
    )
    starts.append(570)
    stops.append(573)
    befores.append("")
    starts.append(564)
    stops.append(565)
    befores.append(
        "def process_weather(mut world: World, record: RecordedWeather):\n"
    )
    starts.append(546)
    stops.append(547)
    befores.append("    return WeatherParameters(\n")
    starts.append(542)
    stops.append(545)
    befores.append("")
    starts.append(534)
    stops.append(535)
    befores.append(
        "def weather_of(record: RecordedWeather) -> WeatherParameters:\n"
    )
    starts.append(404)
    stops.append(407)
    befores.append(
        "        lerp_angle(r1.x, r2.x, per),\n        lerp_angle(r1.y, r2.y,"
        " per),\n        lerp_angle(r1.z, r2.z, per),\n"
    )
    starts.append(307)
    stops.append(357)
    befores.append(
        "def lerp_angle(a: Float64, b: Float64, fraction: Float64) ->"
        " Float64:\n"
    )
    starts.append(44)
    stops.append(50)
    befores.append("")


def _edits_24(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(3367)
    stops.append(3378)
    befores.append("")
    starts.append(3322)
    stops.append(3323)
    befores.append("")
    starts.append(3249)
    stops.append(3317)
    befores.append("")
    starts.append(3186)
    stops.append(3231)
    befores.append("")
    starts.append(3178)
    stops.append(3185)
    befores.append("")
    starts.append(3170)
    stops.append(3171)
    befores.append("    def __init__(out self, info: RoadInfoMarkRecord):\n")
    starts.append(3093)
    stops.append(3096)
    befores.append(
        "        while j > 0 and records[j - 1].distance() >"
        " records[j].distance():\n"
    )
    starts.append(3079)
    stops.append(3080)
    befores.append("        var s = records[i].distance()\n")
    starts.append(3074)
    stops.append(3075)
    befores.append("            var s = records[i].distance()\n")
    starts.append(3015)
    stops.append(3055)
    befores.append("")
    starts.append(3008)
    stops.append(3009)
    befores.append("    var at = info_index(records, s)\n")
    starts.append(2962)
    stops.append(2998)
    befores.append(
        "def info_at[T: RoadInfo](records: List[T], s: Float64) ->"
        " Optional[T]:\n"
    )
    starts.append(2955)
    stops.append(2956)
    befores.append("        if records[mid].distance() <= s:\n")
    starts.append(2907)
    stops.append(2941)
    befores.append(
        "def info_index[T: RoadInfo](records: List[T], s: Float64) -> Int:\n"
    )
    starts.append(2881)
    stops.append(2903)
    befores.append("")
    starts.append(2754)
    stops.append(2871)
    befores.append(
        '    def distance(self) -> Float64:\n        """Return where the'
        ' reference sits, in meters."""\n'
    )
    starts.append(2740)
    stops.append(2740)
    befores.append("@fieldwise_init\n")
    starts.append(2628)
    stops.append(2716)
    befores.append("")
    starts.append(2433)
    stops.append(2627)
    befores.append(
        '    def distance(self) -> Float64:\n        """Return where the record'
        ' starts, in meters."""\n'
    )
    starts.append(2336)
    stops.append(2415)
    befores.append("@fieldwise_init\n")
    starts.append(2333)
    stops.append(2335)
    befores.append("")
    starts.append(2283)
    stops.append(2325)
    befores.append("@fieldwise_init\n")
    starts.append(2280)
    stops.append(2282)
    befores.append("")
    starts.append(2255)
    stops.append(2278)
    befores.append(
        '    def distance(self) -> Float64:\n        """Return where the record'
        ' starts, in meters."""\n'
    )
    starts.append(2240)
    stops.append(2241)
    befores.append(
        "            is_rht: True if the road keeps traffic to the right.\n    "
        '    """\n'
    )
    starts.append(2228)
    stops.append(2229)
    befores.append("")
    starts.append(2052)
    stops.append(2212)
    befores.append("")
    starts.append(2025)
    stops.append(2036)
    befores.append("        self = RoadInfoMarkRecord(\n")
    starts.append(1983)
    stops.append(2019)
    befores.append(
        "    def __init__(out self, s: Float64, road_mark_id: Int):\n       "
        ' """Create a record with CARLA\'s defaults: white standard paint\n'
    )
    starts.append(1906)
    stops.append(1961)
    befores.append("")
    starts.append(1771)
    stops.append(1905)
    befores.append(
        '    def distance(self) -> Float64:\n        """Return where the record'
        ' starts, in meters."""\n'
    )
    starts.append(1749)
    stops.append(1758)
    befores.append("@fieldwise_init\n")
    starts.append(1746)
    stops.append(1748)
    befores.append("")
    starts.append(1721)
    stops.append(1744)
    befores.append(
        '    def distance(self) -> Float64:\n        """Return where the record'
        ' starts, in meters."""\n'
    )
    starts.append(1690)
    stops.append(1692)
    befores.append("        var out = RoadInfoSpeed(s, 0, type, unit)\n")
    starts.append(1650)
    stops.append(1651)
    befores.append("")
    starts.append(1640)
    stops.append(1646)
    befores.append(
        "        out self, s: Float64, speed: Float64, type: String, unit:"
        ' String = ""\n'
    )
    starts.append(1585)
    stops.append(1639)
    befores.append("")
    starts.append(1555)
    stops.append(1566)
    befores.append("")
    starts.append(1488)
    stops.append(1554)
    befores.append(
        '    def distance(self) -> Float64:\n        """Return where the record'
        ' starts, in meters."""\n'
    )
    starts.append(1473)
    stops.append(1482)
    befores.append("@fieldwise_init\n")
    starts.append(1470)
    stops.append(1472)
    befores.append("")
    starts.append(1402)
    stops.append(1468)
    befores.append(
        '    def distance(self) -> Float64:\n        """Return where the record'
        ' starts, in meters."""\n'
    )
    starts.append(1343)
    stops.append(1396)
    befores.append("@fieldwise_init\n")
    starts.append(1340)
    stops.append(1342)
    befores.append("")
    starts.append(1228)
    stops.append(1338)
    befores.append(
        '    def distance(self) -> Float64:\n        """Return where the record'
        ' starts, in meters."""\n'
    )
    starts.append(1209)
    stops.append(1218)
    befores.append("@fieldwise_init\n")
    starts.append(1206)
    stops.append(1208)
    befores.append("")
    starts.append(1112)
    stops.append(1204)
    befores.append(
        '    def distance(self) -> Float64:\n        """Return where the record'
        ' starts, in meters."""\n'
    )
    starts.append(1071)
    stops.append(1102)
    befores.append("@fieldwise_init\n")
    starts.append(1068)
    stops.append(1070)
    befores.append("")
    starts.append(986)
    stops.append(1066)
    befores.append(
        '    def distance(self) -> Float64:\n        """Return where the record'
        ' starts, in meters."""\n'
    )
    starts.append(969)
    stops.append(978)
    befores.append("@fieldwise_init\n")
    starts.append(966)
    stops.append(968)
    befores.append("")
    starts.append(889)
    stops.append(964)
    befores.append(
        '    def distance(self) -> Float64:\n        """Return where the record'
        ' starts, in meters."""\n'
    )
    starts.append(871)
    stops.append(880)
    befores.append("@fieldwise_init\n")
    starts.append(868)
    stops.append(870)
    befores.append("")
    starts.append(791)
    stops.append(866)
    befores.append(
        '    def distance(self) -> Float64:\n        """Return where the record'
        ' starts, in meters."""\n'
    )
    starts.append(776)
    stops.append(785)
    befores.append("@fieldwise_init\n")
    starts.append(773)
    stops.append(775)
    befores.append("")
    starts.append(696)
    stops.append(771)
    befores.append(
        '    def distance(self) -> Float64:\n        """Return where the record'
        ' starts, in meters."""\n'
    )
    starts.append(681)
    stops.append(690)
    befores.append("@fieldwise_init\n")
    starts.append(678)
    stops.append(680)
    befores.append("")
    starts.append(601)
    stops.append(676)
    befores.append(
        '    def distance(self) -> Float64:\n        """Return where the record'
        ' starts, in meters."""\n'
    )
    starts.append(586)
    stops.append(595)
    befores.append("@fieldwise_init\n")
    starts.append(583)
    stops.append(585)
    befores.append("")
    starts.append(512)
    stops.append(581)
    befores.append(
        '    def distance(self) -> Float64:\n        """Return where the record'
        ' starts, in meters."""\n'
    )
    starts.append(506)
    stops.append(506)
    befores.append("@fieldwise_init\n")
    starts.append(479)
    stops.append(503)
    befores.append(
        '    def distance(self) -> Float64:\n        """Return where the record'
        ' starts, in meters along the road."""\n'
    )
    starts.append(58)
    stops.append(59)
    befores.append("")
    starts.append(45)
    stops.append(52)
    befores.append("")
    starts.append(34)
    stops.append(35)
    befores.append("from extensions.carla.geometry import RoadGeometry\n")


def _edits_25(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(532)
    stops.append(533)
    befores.append("")
    starts.append(528)
    stops.append(531)
    befores.append("")
    starts.append(517)
    stops.append(518)
    befores.append(") -> List[UInt8]:\n")
    starts.append(496)
    stops.append(516)
    befores.append("")
    starts.append(483)
    stops.append(486)
    befores.append("")
    starts.append(480)
    stops.append(482)
    befores.append(
        "        Error: If `flow` does not hold two numbers a pixel.\n"
    )
    starts.append(445)
    stops.append(466)
    befores.append("")
    starts.append(431)
    stops.append(432)
    befores.append("")
    starts.append(395)
    stops.append(417)
    befores.append(
        "def image_data(image: Framebuffer, fov: Float32) raises -> L"
        "ist[UInt8]:\n"
    )
    starts.append(373)
    stops.append(374)
    befores.append("")
    starts.append(334)
    stops.append(357)
    befores.append("")
    starts.append(53)
    stops.append(56)
    befores.append("")


def _edits_26(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(17)
    stops.append(18)
    befores.append("from extensions.carla.road_info import info_index\n")


def _edits_27(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(19)
    stops.append(20)
    befores.append("from extensions.carla.road_info import info_index\n")


def _edits_28(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(1416)
    stops.append(1417)
    befores.append("        scene.add_mesh(mesh^)\n")
    starts.append(708)
    stops.append(712)
    befores.append("")
    starts.append(687)
    stops.append(689)
    befores.append(
        "        Error: Never for finite corners; the geometry's chec"
        "ks are passed\n            on.\n"
    )
    starts.append(654)
    stops.append(656)
    befores.append("")
    starts.append(648)
    stops.append(650)
    befores.append("")
    starts.append(647)
    stops.append(647)
    befores.append(
        '    if not (spacing.to(METER) > 0):\n        raise Error("S'
        'treet lamps need a positive spacing")\n'
    )
    starts.append(644)
    stops.append(646)
    befores.append(
        "        Error: If the spacing is not positive, or a map query fails.\n"
    )
    starts.append(601)
    stops.append(603)
    befores.append("")
    starts.append(597)
    stops.append(598)
    befores.append("        Error: If the count is less than one.\n")
    starts.append(534)
    stops.append(536)
    befores.append("")
    starts.append(527)
    stops.append(529)
    befores.append("        Error: If a map query fails.\n")
    starts.append(192)
    stops.append(196)
    befores.append("")
    starts.append(164)
    stops.append(165)
    befores.append("from std.math import atan2, cos, pow, sin, sqrt\n")
    starts.append(32)
    stops.append(34)
    befores.append("  night.\n")
    starts.append(25)
    stops.append(30)
    befores.append(
        "  another road or another lot is left empty. Each building h"
        "as a row of\n  shops on its ground floor, a cornice above it"
        ", floors of windows, and\n  a parapet round its roof. A ring"
        " of tall buildings far out makes the\n  skyline.\n"
    )
    starts.append(21)
    stops.append(23)
    befores.append("  each crosswalk outline of `Map.all_crosswalk_zones`.\n")


def _edits_28_b(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(2034)
    stops.append(2037)
    befores.append(
        "           "
        " bounds.expand_by_point(road.directed_point(s).to_carla().location)\n"
    )
    starts.append(1861)
    stops.append(1862)
    befores.append("")
    starts.append(645)
    stops.append(646)
    befores.append("                var found = roadside(road, s, side == 0)\n")
    starts.append(550)
    stops.append(551)
    befores.append(
        "                    var tangent = road.directed_point(mid).tangent\n"
    )
    starts.append(534)
    stops.append(535)
    befores.append(
        "                var found = roadside(road, mid, side == 0)\n"
    )
    starts.append(483)
    stops.append(484)
    befores.append("    var corners = road.lane_corners(section, lane, s)\n")
    starts.append(411)
    stops.append(456)
    befores.append("")
    starts.append(43)
    stops.append(46)
    befores.append("")


def _edits_29(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(717)
    stops.append(728)
    befores.append(
        "    var x = Float32(-0.9) * trigger_volume.extent.x\n    var"
        " end = Float32(0.9) * trigger_volume.extent.x\n"
    )
    starts.append(711)
    stops.append(713)
    befores.append("        Error: If a map query fails.\n")
    starts.append(685)
    stops.append(686)
    befores.append("                var w = map.waypoint_xodr(\n")
    starts.append(679)
    stops.append(683)
    befores.append(
        "            var lanes = List[Int]()\n            if v.from_l"
        "ane.value < v.to_lane.value:\n                # from < to, s"
        "o the range holds two lanes at least.\n                for l"
        "ane in range(\n                    v.from_lane.value, v.to_l"
        "ane.value + 1\n                ):  # pragma: no branch\n    "
        "                lanes.append(lane)\n            else:\n     "
        "           # from >= to, so the range holds one lane at leas"
        "t.\n                for lane in range(\n                    "
        "v.from_lane.value, v.to_lane.value - 1, -1\n                "
        "):  # pragma: no branch\n                    lanes.append(la"
        "ne)\n            # Either range above holds one lane at leas"
        "t.\n            for lane in lanes:  # pragma: no branch\n"
    )
    starts.append(672)
    stops.append(674)
    befores.append("        Error: If the id is not valid.\n")
    starts.append(62)
    stops.append(63)
    befores.append("")
    starts.append(57)
    stops.append(58)
    befores.append("")


def _edits_30(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(1121)
    stops.append(1123)
    befores.append("")
    starts.append(1118)
    stops.append(1120)
    befores.append("            Error: If an id names no traffic light.\n")
    starts.append(1101)
    stops.append(1102)
    befores.append("            Error: If its path is empty.\n")
    starts.append(1087)
    stops.append(1088)
    befores.append("            Error: If its path is empty.\n")
    starts.append(1055)
    stops.append(1057)
    befores.append("")
    starts.append(1038)
    stops.append(1041)
    befores.append("")
    starts.append(777)
    stops.append(778)
    befores.append("")
    starts.append(775)
    stops.append(776)
    befores.append("            Error: If the id is not valid.\n")
    starts.append(740)
    stops.append(742)
    befores.append("            Error: If the id names no living actor.\n")
    starts.append(715)
    stops.append(716)
    befores.append("")
    starts.append(712)
    stops.append(714)
    befores.append("            Error: If an idle vehicle is not tracked.\n")
    starts.append(388)
    stops.append(390)
    befores.append("")
    starts.append(386)
    stops.append(387)
    befores.append("            Error: If a world query fails.\n")
    starts.append(314)
    stops.append(316)
    befores.append("")
    starts.append(307)
    stops.append(309)
    befores.append(
        "        Error: If a command's kind is not valid, or the world"
        " refuses a\n"
    )
    starts.append(280)
    stops.append(281)
    befores.append("        Error: If the id names no living actor.\n")
    starts.append(253)
    stops.append(255)
    befores.append(
        "        Error: If the id names no living actor, or the body cannot"
        " enter\n"
    )
    starts.append(219)
    stops.append(220)
    befores.append("")
    starts.append(215)
    stops.append(218)
    befores.append("")
    starts.append(207)
    stops.append(208)
    befores.append("    def contains(self, actor: ActorId) -> Bool:\n")
    starts.append(202)
    stops.append(203)
    befores.append("")
    starts.append(199)
    stops.append(201)
    befores.append("            Error: If the world fails to destroy it.\n")
    starts.append(181)
    stops.append(183)
    befores.append("")
    starts.append(177)
    stops.append(180)
    befores.append("")
    starts.append(172)
    stops.append(173)
    befores.append("    def remove(mut self, actors: List[ActorId]):\n")
    starts.append(163)
    stops.append(164)
    befores.append("")
    starts.append(107)
    stops.append(108)
    befores.append("")
    starts.append(41)
    stops.append(47)
    befores.append("")


def _edits_31(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(754)
    stops.append(758)
    befores.append(
        "        var ego_extension = self.get_bounding_box_extension(reference,"
        " shared)\n        var other_extension ="
        " self.get_bounding_box_extension(other, shared)\n"
    )
    starts.append(732)
    stops.append(734)
    befores.append("")
    starts.append(729)
    stops.append(731)
    befores.append(
        "            Error: If an actor is not tracked, or the vehicle has no"
        " path.\n"
    )
    starts.append(646)
    stops.append(704)
    befores.append("")
    starts.append(631)
    stops.append(635)
    befores.append(
        "                polygon_distance(reference_box, other_geodesic),\n    "
        "            polygon_distance(other_box, reference_geodesic),\n        "
        "        polygon_distance(reference_geodesic, other_geodesic),\n       "
        "         polygon_distance(reference_box, other_box),\n"
    )
    starts.append(612)
    stops.append(614)
    befores.append("")
    starts.append(610)
    stops.append(611)
    befores.append("            Error: If an actor is not tracked.\n")
    starts.append(541)
    stops.append(542)
    befores.append(
        "                self.get_bounding_box_extension(actor, shared),\n"
    )
    starts.append(529)
    stops.append(530)
    befores.append("")
    starts.append(527)
    stops.append(528)
    befores.append("            Error: If the actor is not tracked.\n")
    starts.append(488)
    stops.append(489)
    befores.append("            Error: If the actor is not tracked.\n")
    starts.append(451)
    stops.append(452)
    befores.append("            Error: If the vehicle is not tracked.\n")
    starts.append(401)
    stops.append(437)
    befores.append("")
    starts.append(380)
    stops.append(381)
    befores.append("")
    starts.append(378)
    stops.append(379)
    befores.append(
        "            Error: Never; the keys are collected before removal.\n"
    )
    starts.append(337)
    stops.append(338)
    befores.append(
        "                    var result = self.negotiate_collision(\n"
    )
    starts.append(274)
    stops.append(276)
    befores.append(
        "            Error: If the index is out of range, or a tracked vehicle"
        " has\n"
    )
    starts.append(134)
    stops.append(183)
    befores.append(
        "def polygon_distance(a: List[Vector3], b: List[Vector3]) -> Float64:\n"
    )
    starts.append(87)
    stops.append(88)
    befores.append("from units.si import Length\n")
    starts.append(79)
    stops.append(80)
    befores.append("")
    starts.append(71)
    stops.append(74)
    befores.append(
        "from extensions.carla.traffic_manager_map import distance_squared\n"
    )
    starts.append(52)
    stops.append(53)
    befores.append("from extensions.carla.map import segment_distance_2d\n")
    starts.append(47)
    stops.append(51)
    befores.append("")


def _edits_32(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(1058)
    stops.append(1061)
    befores.append(
        "        var distance ="
        " map.at(end).distance_squared(map.at(imported).location())\n"
    )
    starts.append(1027)
    stops.append(1029)
    befores.append(
        "            and map.at(start).distance_squared(map.at(end).location())"
        " >= 50.0\n"
    )
    starts.append(973)
    stops.append(974)
    befores.append("")
    starts.append(970)
    stops.append(972)
    befores.append(
        "            Error: If the vehicle's path is empty or it is not"
        " tracked.\n"
    )
    starts.append(922)
    stops.append(923)
    befores.append("")
    starts.append(919)
    stops.append(921)
    befores.append(
        "            Error: If the vehicle's path is empty or it is not"
        " tracked.\n"
    )
    starts.append(870)
    stops.append(871)
    befores.append("")
    starts.append(868)
    stops.append(869)
    befores.append("            Error: Never; the lookups are checked.\n")
    starts.append(782)
    stops.append(783)
    befores.append(
        "                shared.local_map.at(chosen).distance_squared(\n"
    )
    starts.append(727)
    stops.append(728)
    befores.append("                    junction_length += current.distance(\n")
    starts.append(679)
    stops.append(680)
    befores.append(
        "                and shared.local_map.at(begin).distance_squared(\n"
    )
    starts.append(659)
    stops.append(660)
    befores.append("                        ).distance_squared(\n")
    starts.append(626)
    stops.append(629)
    befores.append(
        "                   "
        " ).distance_squared(shared.local_map.at(current).location())\n"
    )
    starts.append(546)
    stops.append(547)
    befores.append(
        "                map.at(change_over_point).distance_squared(start)\n"
    )
    starts.append(236)
    stops.append(238)
    befores.append(
        "            Error: If the index is out of range, the vehicle is not\n"
    )
    starts.append(163)
    stops.append(164)
    befores.append(
        "    return map.at(buffer[len(buffer) - 1]).distance_squared(\n"
    )
    starts.append(76)
    stops.append(77)
    befores.append("")
    starts.append(68)
    stops.append(69)
    befores.append("    distance_squared,\n")


def _edits_33(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(1353)
    stops.append(1354)
    befores.append(
        "    for landmark in map.landmarks_in_distance(waypoint, 15.0):\n"
    )
    starts.append(1206)
    stops.append(1207)
    befores.append("            var found = map.waypoint_xodr(\n")
    starts.append(924)
    stops.append(925)
    befores.append("                var nexts = map.next(\n")
    starts.append(825)
    stops.append(826)
    befores.append(
        "                if distance_squared(edge, current.location()) > (\n"
    )
    starts.append(807)
    stops.append(808)
    befores.append(
        "        for w in"
        " map.generate_waypoints(Float64(MAP_RESOLUTION.value)):\n"
    )
    starts.append(402)
    stops.append(403)
    befores.append(
        "        return distance_squared(self.location(), location)\n"
    )
    starts.append(357)
    stops.append(394)
    befores.append(
        "    def distance_squared(self, location: Vector3) -> Float32:\n"
    )
    starts.append(312)
    stops.append(347)
    befores.append("    def distance(self, location: Vector3) -> Float32:\n")
    starts.append(168)
    stops.append(207)
    befores.append("def distance_squared(a: Vector3, b: Vector3) -> Float32:\n")
    starts.append(56)
    stops.append(59)
    befores.append("")


def _edits_34(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(1177)
    stops.append(1178)
    befores.append(
        "        return self._custom_route.get(actor.value,"
        " List[RoadOption]())\n"
    )
    starts.append(1173)
    stops.append(1176)
    befores.append("")
    starts.append(1165)
    stops.append(1166)
    befores.append(
        "    def get_imported_route(self, actor: ActorId) ->"
        " List[RoadOption]:\n"
    )
    starts.append(1163)
    stops.append(1164)
    befores.append(
        "        return self._upload_route.get(actor.value, False)\n"
    )
    starts.append(1159)
    stops.append(1162)
    befores.append("")
    starts.append(1150)
    stops.append(1151)
    befores.append("    def get_upload_route(self, actor: ActorId) -> Bool:\n")
    starts.append(1148)
    stops.append(1149)
    befores.append(
        "        return self._custom_path.get(actor.value, List[Vector3]())\n"
    )
    starts.append(1144)
    stops.append(1147)
    befores.append("")
    starts.append(1136)
    stops.append(1137)
    befores.append(
        "    def get_custom_path(self, actor: ActorId) -> List[Vector3]:\n"
    )
    starts.append(1134)
    stops.append(1135)
    befores.append("        return self._upload_path.get(actor.value, False)\n")
    starts.append(1130)
    stops.append(1133)
    befores.append("")
    starts.append(1121)
    stops.append(1122)
    befores.append("    def get_upload_path(self, actor: ActorId) -> Bool:\n")
    starts.append(1076)
    stops.append(1077)
    befores.append(
        "        return self._auto_update_vehicle_lights.get(actor.value,"
        " False)\n"
    )
    starts.append(1072)
    stops.append(1075)
    befores.append("")
    starts.append(1063)
    stops.append(1064)
    befores.append(
        "    def get_update_vehicle_lights(self, actor: ActorId) -> Bool:\n"
    )
    starts.append(1061)
    stops.append(1062)
    befores.append(
        "        return self._perc_ignore_walkers.get(actor.value,"
        " Float32(0.0))\n"
    )
    starts.append(1057)
    stops.append(1060)
    befores.append("")
    starts.append(1048)
    stops.append(1049)
    befores.append(
        "    def get_percentage_ignore_walkers(self, actor: ActorId) ->"
        " Float32:\n"
    )
    starts.append(1046)
    stops.append(1047)
    befores.append(
        "        return self._perc_ignore_vehicles.get(actor.value,"
        " Float32(0.0))\n"
    )
    starts.append(1042)
    stops.append(1045)
    befores.append("")
    starts.append(1033)
    stops.append(1034)
    befores.append(
        "    def get_percentage_ignore_vehicles(self, actor: ActorId) ->"
        " Float32:\n"
    )
    starts.append(1031)
    stops.append(1032)
    befores.append(
        "        return self._perc_run_traffic_light.get(actor.value,"
        " Float32(0.0))\n"
    )
    starts.append(1027)
    stops.append(1030)
    befores.append("")
    starts.append(1018)
    stops.append(1019)
    befores.append(
        "    def get_percentage_running_light(self, actor: ActorId) ->"
        " Float32:\n"
    )
    starts.append(1016)
    stops.append(1017)
    befores.append(
        "        return self._perc_run_traffic_sign.get(actor.value,"
        " Float32(0.0))\n"
    )
    starts.append(1012)
    stops.append(1015)
    befores.append("")
    starts.append(1003)
    stops.append(1004)
    befores.append(
        "    def get_percentage_running_sign(self, actor: ActorId) ->"
        " Float32:\n"
    )
    starts.append(1000)
    stops.append(1001)
    befores.append("            actor.value, self._distance_margin\n")
    starts.append(995)
    stops.append(998)
    befores.append("")
    starts.append(987)
    stops.append(988)
    befores.append(
        "    def get_distance_to_leading_vehicle(self, actor: ActorId) ->"
        " Length:\n"
    )
    starts.append(985)
    stops.append(986)
    befores.append(
        "        return self._auto_lane_change.get(actor.value, True)\n"
    )
    starts.append(981)
    stops.append(984)
    befores.append("")
    starts.append(972)
    stops.append(973)
    befores.append(
        "    def get_auto_lane_change(self, actor: ActorId) -> Bool:\n"
    )
    starts.append(970)
    stops.append(971)
    befores.append(
        "        return self._perc_random_right.get(actor.value,"
        " Float32(-1.0))\n"
    )
    starts.append(966)
    stops.append(969)
    befores.append("")
    starts.append(957)
    stops.append(958)
    befores.append("    ) -> Float32:\n")
    starts.append(953)
    stops.append(954)
    befores.append(
        "        return self._perc_random_left.get(actor.value,"
        " Float32(-1.0))\n"
    )
    starts.append(949)
    stops.append(952)
    befores.append("")
    starts.append(938)
    stops.append(941)
    befores.append(
        "    def get_random_left_lane_change_percentage(self, actor: ActorId)"
        " -> Float32:\n"
    )
    starts.append(936)
    stops.append(937)
    befores.append(
        "        return self._perc_keep_slow_lane.get(actor.value,"
        " Float32(-1.0))\n"
    )
    starts.append(932)
    stops.append(935)
    befores.append("")
    starts.append(923)
    stops.append(924)
    befores.append(
        "    def get_keep_slow_lane_percentage(self, actor: ActorId) ->"
        " Float32:\n"
    )
    starts.append(920)
    stops.append(921)
    befores.append("            actor.value, ChangeLaneInfo(False, False)\n")
    starts.append(915)
    stops.append(918)
    befores.append("")
    starts.append(904)
    stops.append(907)
    befores.append(
        "    def get_force_lane_change(mut self, actor: ActorId) ->"
        " ChangeLaneInfo:\n"
    )
    starts.append(897)
    stops.append(901)
    befores.append(
        "        var found ="
        " self._ignore_collision.get(reference_actor.value)\n        if"
        " Bool(found) and other_actor.value in found.value():\n"
    )
    starts.append(893)
    stops.append(896)
    befores.append("")
    starts.append(883)
    stops.append(884)
    befores.append("    ) -> Bool:\n")
    starts.append(878)
    stops.append(879)
    befores.append(
        "            actor.value, self._global_large_vehicle_wide_turn\n"
    )
    starts.append(873)
    stops.append(876)
    befores.append("")
    starts.append(864)
    stops.append(865)
    befores.append(
        "    def get_large_vehicle_wide_turn(self, actor: ActorId) -> Bool:\n"
    )
    starts.append(862)
    stops.append(863)
    befores.append(
        "        return self._lane_offset.get(actor.value,"
        " self._global_lane_offset)\n"
    )
    starts.append(858)
    stops.append(861)
    befores.append("")
    starts.append(850)
    stops.append(851)
    befores.append("    def get_lane_offset(self, actor: ActorId) -> Length:\n")
    starts.append(840)
    stops.append(841)
    befores.append("        var a = actor.value\n")
    starts.append(838)
    stops.append(839)
    befores.append("            Error: Never; the lookups are checked.\n")
    starts.append(822)
    stops.append(823)
    befores.append("        return actor.value in self._exact_desired_speed\n")
    starts.append(818)
    stops.append(821)
    befores.append("")
    starts.append(810)
    stops.append(811)
    befores.append("    def has_desired_speed(self, actor: ActorId) -> Bool:\n")


def _edits_35(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(1276)
    stops.append(1278)
    befores.append(
        "            Error: If the index is out of range or the vehicle has no"
        " path.\n"
    )
    starts.append(1259)
    stops.append(1263)
    befores.append("")
    starts.append(1255)
    stops.append(1258)
    befores.append("")
    starts.append(1248)
    stops.append(1249)
    befores.append("    ):\n")
    starts.append(1209)
    stops.append(1210)
    befores.append("")
    starts.append(1207)
    stops.append(1208)
    befores.append("            Error: Never; the lookups are checked.\n")
    starts.append(1110)
    stops.append(1161)
    befores.append("")
    starts.append(1073)
    stops.append(1074)
    befores.append("        for landmark in map.landmarks_in_distance(\n")
    starts.append(1070)
    stops.append(1071)
    befores.append("")
    starts.append(1068)
    stops.append(1069)
    befores.append("            Error: If a map query fails.\n")
    starts.append(972)
    stops.append(1040)
    befores.append("")
    starts.append(937)
    stops.append(938)
    befores.append("")
    starts.append(934)
    stops.append(936)
    befores.append("            Error: If the hazard's actor is not tracked.\n")
    starts.append(845)
    stops.append(917)
    befores.append("")
    starts.append(809)
    stops.append(810)
    befores.append("            Error: If a vehicle is not tracked.\n")
    starts.append(765)
    stops.append(766)
    befores.append("                missing += current.distance(\n")
    starts.append(752)
    stops.append(753)
    befores.append("")
    starts.append(749)
    stops.append(751)
    befores.append(
        "            Error: If a node or the vehicle is not known.\n"
    )
    starts.append(674)
    stops.append(732)
    befores.append("")
    starts.append(640)
    stops.append(641)
    befores.append(
        "            map.at(end).distance_squared(map.at(safe).location())\n"
    )
    starts.append(516)
    stops.append(517)
    befores.append(
        "            var base_offset = self.calculate_base_offset(\n"
    )
    starts.append(492)
    stops.append(493)
    befores.append("        var response = self.collision_handling(\n")
    starts.append(488)
    stops.append(489)
    befores.append("        var turn_target = self.get_turn_target_velocity(\n")
    starts.append(485)
    stops.append(486)
    befores.append(
        "        var landmark_target = self.get_landmark_target_velocity(\n"
    )
    starts.append(429)
    stops.append(430)
    befores.append("")
    starts.append(409)
    stops.append(411)
    befores.append(
        "            Error: If the index is out of range, or the vehicle is"
        " not\n"
    )
    starts.append(339)
    stops.append(340)
    befores.append("")
    starts.append(337)
    stops.append(338)
    befores.append("            Error: Never; the lookups are checked.\n")
    starts.append(314)
    stops.append(315)
    befores.append("")
    starts.append(312)
    stops.append(313)
    befores.append("            Error: If the vehicle has no path.\n")
    starts.append(281)
    stops.append(282)
    befores.append("")
    starts.append(277)
    stops.append(279)
    befores.append(
        "            Error: If the junction has no queue or the vehicle is"
        " not\n"
    )
    starts.append(248)
    stops.append(249)
    befores.append("")
    starts.append(246)
    stops.append(247)
    befores.append("            Error: Never; the lookups are checked.\n")
    starts.append(193)
    stops.append(195)
    befores.append(
        "            Error: If the index is out of range, or the vehicle is"
        " not\n"
    )
    starts.append(122)
    stops.append(123)
    befores.append("")
    starts.append(101)
    stops.append(102)
    befores.append("    distance_squared,\n")
    starts.append(46)
    stops.append(48)
    befores.append("")


def _edits_36(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(258)
    stops.append(259)
    befores.append("")
    starts.append(254)
    stops.append(257)
    befores.append("")
    starts.append(246)
    stops.append(247)
    befores.append(
        "    def buffer(self, actor: ActorId) -> List[SimpleWaypointIndex]:\n"
    )
    starts.append(182)
    stops.append(183)
    befores.append("")
    starts.append(178)
    stops.append(181)
    befores.append("")
    starts.append(169)
    stops.append(170)
    befores.append(") -> TrafficCommand:\n")
    starts.append(161)
    stops.append(162)
    befores.append("")
    starts.append(157)
    stops.append(160)
    befores.append("")
    starts.append(148)
    stops.append(149)
    befores.append(") -> TrafficCommand:\n")
    starts.append(140)
    stops.append(141)
    befores.append("")
    starts.append(136)
    stops.append(139)
    befores.append("")
    starts.append(127)
    stops.append(128)
    befores.append(") -> TrafficCommand:\n")
    starts.append(40)
    stops.append(41)
    befores.append("")


def _edits_37(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(826)
    stops.append(827)
    befores.append("")
    starts.append(824)
    stops.append(825)
    befores.append("        Error: If the path is empty.\n")
    starts.append(800)
    stops.append(801)
    befores.append("")
    starts.append(798)
    stops.append(799)
    befores.append(
        "        Error: If the node is not on the map or the id is not valid.\n"
    )
    starts.append(729)
    stops.append(730)
    befores.append("            Error: If the actor is not tracked.\n")
    starts.append(715)
    stops.append(716)
    befores.append("            Error: If the actor is not tracked.\n")
    starts.append(701)
    stops.append(702)
    befores.append("            Error: If the actor is not tracked.\n")
    starts.append(687)
    stops.append(688)
    befores.append("            Error: If the actor is not tracked.\n")
    starts.append(673)
    stops.append(674)
    befores.append("            Error: If the actor is not tracked.\n")
    starts.append(659)
    stops.append(660)
    befores.append("            Error: If the actor is not tracked.\n")
    starts.append(645)
    stops.append(646)
    befores.append("            Error: If the actor is not tracked.\n")
    starts.append(631)
    stops.append(632)
    befores.append("            Error: If the actor is not tracked.\n")
    starts.append(617)
    stops.append(618)
    befores.append("            Error: If the actor is not tracked.\n")
    starts.append(603)
    stops.append(604)
    befores.append("            Error: If the actor is not tracked.\n")
    starts.append(588)
    stops.append(589)
    befores.append("            Error: If the actor is not tracked.\n")
    starts.append(574)
    stops.append(575)
    befores.append("            Error: If the actor is not tracked.\n")
    starts.append(556)
    stops.append(557)
    befores.append("            Error: If the actor is not tracked.\n")
    starts.append(537)
    stops.append(538)
    befores.append("            Error: If the actor is not tracked.\n")
    starts.append(522)
    stops.append(523)
    befores.append("            Error: If the actor is not tracked.\n")
    starts.append(507)
    stops.append(508)
    befores.append("")
    starts.append(490)
    stops.append(491)
    befores.append("")
    starts.append(488)
    stops.append(489)
    befores.append(
        "            Error: Never; the records of an actor are kept together.\n"
    )
    starts.append(478)
    stops.append(479)
    befores.append("")
    starts.append(474)
    stops.append(477)
    befores.append("")
    starts.append(466)
    stops.append(467)
    befores.append("    def contains_actor(self, actor_id: ActorId) -> Bool:\n")
    starts.append(278)
    stops.append(279)
    befores.append("")
    starts.append(274)
    stops.append(277)
    befores.append("")
    starts.append(263)
    stops.append(266)
    befores.append(
        "    def get_overlapping_vehicles(self, actor_id: ActorId) ->"
        " List[ActorId]:\n"
    )
    starts.append(62)
    stops.append(68)
    befores.append("")
    starts.append(51)
    stops.append(52)
    befores.append("    distance_squared,\n")


def _edits_38(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(645)
    stops.append(675)
    befores.append(
        "    def tick_timers(mut self, dt: Float32) -> List[SignalUpdate]:\n"
    )
    starts.append(421)
    stops.append(422)
    befores.append("                var found = map.waypoint_xodr(\n")
    starts.append(409)
    stops.append(411)
    befores.append("        Error: If the id is not valid.\n")
    starts.append(375)
    stops.append(376)
    befores.append("                var found = map.waypoint_xodr(\n")
    starts.append(362)
    stops.append(364)
    befores.append("        Error: If the id is not valid.\n")
    starts.append(328)
    stops.append(329)
    befores.append(
        "                    for before in map.previous(item[1], step):\n"
    )
    starts.append(321)
    stops.append(327)
    befores.append("")
    starts.append(305)
    stops.append(306)
    befores.append("            for before in map.previous(w, step):\n")
    starts.append(303)
    stops.append(304)
    befores.append("")
    starts.append(296)
    stops.append(299)
    befores.append("                var ahead = map.next(next, step)\n")
    starts.append(289)
    stops.append(295)
    befores.append("")
    starts.append(246)
    stops.append(247)
    befores.append("                var found = map.waypoint_xodr(\n")
    starts.append(234)
    stops.append(236)
    befores.append("        Error: If the id is not valid.\n")
    starts.append(186)
    stops.append(187)
    befores.append(
        "    return (road.sections[section].s, road.section_length(section))\n"
    )
    starts.append(84)
    stops.append(86)
    befores.append("")
    starts.append(70)
    stops.append(71)
    befores.append("    info_at,\n")
    starts.append(50)
    stops.append(54)
    befores.append("")


def _edits_39(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(2017)
    stops.append(2025)
    befores.append("")
    starts.append(1992)
    stops.append(2000)
    befores.append(
        "        var angle = acos(\n            Float64(a.dot(b)) /"
        " (Float64(a.length()) * Float64(b.length()))\n        )\n"
    )
    starts.append(118)
    stops.append(119)
    befores.append("")
    starts.append(57)
    stops.append(62)
    befores.append("")


def _edits_39_b(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(2110)
    stops.append(2111)
    befores.append("            speed_value(speed),\n")
    starts.append(1891)
    stops.append(1925)
    befores.append("")
    starts.append(1864)
    stops.append(1865)
    befores.append("        self.generation_delta0 = generation_delta0\n")
    starts.append(1848)
    stops.append(1850)
    befores.append("")
    starts.append(1841)
    stops.append(1844)
    befores.append(
        "            generation_delta0: Milliseconds from 2004 to the start.\n"
    )
    starts.append(1837)
    stops.append(1839)
    befores.append(
        "            gen_cam_min: The shortest gap between CAMs, in seconds.\n "
        "           gen_cam_max: The longest, in seconds.\n"
    )
    starts.append(1832)
    stops.append(1833)
    befores.append(
        '        """Set the parameters and the owner, `SetParams` and'
        " `SetActor`.\n"
    )
    starts.append(1831)
    stops.append(1831)
    befores.append("        generation_delta0: Int,\n")
    starts.append(1827)
    stops.append(1829)
    befores.append(
        "        gen_cam_min: Float32,\n        gen_cam_max: Float32,\n"
    )
    starts.append(1808)
    stops.append(1810)
    befores.append("")
    starts.append(1435)
    stops.append(1724)
    befores.append("")
    starts.append(1317)
    stops.append(1318)
    befores.append("")
    starts.append(1313)
    stops.append(1316)
    befores.append("")
    starts.append(1289)
    stops.append(1305)
    befores.append("def speed_value(speed: Float32) -> Int:\n")
    starts.append(1049)
    stops.append(1051)
    befores.append(
        "        var found = path_state(world, receiver, senders[k],"
        " reference)\n        var loss = model.loss(\n"
    )
    starts.append(963)
    stops.append(964)
    befores.append("")
    starts.append(961)
    stops.append(962)
    befores.append("        Error: If a sensor is not alive.\n")
    starts.append(923)
    stops.append(943)
    befores.append("")
    starts.append(869)
    stops.append(870)
    befores.append(
        "            path = Float32(self.two_ray(distance, tx, rx))\n"
    )
    starts.append(862)
    stops.append(863)
    befores.append("            path = self.winner(state, distance)\n")
    starts.append(831)
    stops.append(832)
    befores.append("    def loss(\n")
    starts.append(798)
    stops.append(799)
    befores.append(
        "            var loss = self.vehicle_loss(d1, d2, Float64(o.z))\n"
    )
    starts.append(755)
    stops.append(758)
    befores.append(
        "    def vehicle_loss(self, d1: Float64, d2: Float64, h: Float64) ->"
        " Float64:\n"
    )
    starts.append(740)
    stops.append(741)
    befores.append("    def two_ray_simple(\n")
    starts.append(707)
    stops.append(710)
    befores.append(
        "    def two_ray(self, distance: Float64, tx: Float64, rx: Float64) ->"
        " Float64:\n"
    )
    starts.append(406)
    stops.append(676)
    befores.append(
        "    def winner(self, state: PathState, distance: Float64) raises ->"
        " Float32:\n"
    )
    starts.append(247)
    stops.append(277)
    befores.append("")
    starts.append(125)
    stops.append(132)
    befores.append("")
    starts.append(66)
    stops.append(71)
    befores.append("")


def _edits_40(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(417)
    stops.append(418)
    befores.append("        return WeatherParameters(\n")
    starts.append(352)
    stops.append(353)
    befores.append("    return WeatherParameters(\n")
    starts.append(350)
    stops.append(351)
    befores.append(") -> WeatherParameters:\n")
    starts.append(172)
    stops.append(215)
    befores.append(
        "        self.cloudiness = cloudiness\n        self.precipitation ="
        " precipitation\n        self.precipitation_deposits ="
        " precipitation_deposits\n        self.wind_intensity ="
        " wind_intensity\n        self.sun_azimuth_angle ="
        " Angle(sun_azimuth_degrees, DEGREE)\n        self.sun_altitude_angle ="
        " Angle(sun_altitude_degrees, DEGREE)\n        self.fog_density ="
        " fog_density\n        self.fog_distance = Length(fog_distance_meters,"
        " METER)\n        self.fog_falloff = fog_falloff\n        self.wetness"
        " = wetness\n        self.scattering_intensity = scattering_intensity\n"
        "        self.mie_scattering_scale = mie_scattering_scale\n       "
        " self.rayleigh_scattering_scale = rayleigh_scattering_scale\n       "
        " self.dust_storm = dust_storm\n"
    )
    starts.append(165)
    stops.append(171)
    befores.append("")
    starts.append(158)
    stops.append(164)
    befores.append(
        "            fog_distance_meters: Where the fog starts, in meters.\n   "
        "         fog_falloff: How fast the fog thins with height.\n           "
        " wetness: Percent of wetness on the camera's view.\n           "
        " scattering_intensity: How much light the fog scatters.\n           "
        " mie_scattering_scale: The scattering by large particles.\n           "
        " rayleigh_scattering_scale: The scattering by the air.\n"
    )
    starts.append(155)
    stops.append(157)
    befores.append(
        "            sun_azimuth_degrees: The sun's bearing, in degrees.\n     "
        "       sun_altitude_degrees: The sun's height, in degrees.\n"
    )
    starts.append(153)
    stops.append(154)
    befores.append(
        "            precipitation_deposits: Percent of the road under"
        " puddles.\n"
    )
    starts.append(147)
    stops.append(149)
    befores.append(
        '    ):\n        """Create a weather in CARLA\'s argument order.\n'
    )
    starts.append(73)
    stops.append(133)
    befores.append("")
    starts.append(51)
    stops.append(70)
    befores.append(
        '        """Create CARLA\'s field defaults: all zero but the Rayleigh'
        ' scale."""\n        self = WeatherParameters(\n            0, 0, 0, 0,'
        " 0, 0, 0, 0, 0, 0, 0, 0, Float32(0.0331), 0\n        )\n"
    )
    starts.append(22)
    stops.append(23)
    befores.append("")


def restored_dispatch_border() raises -> String:
    """Return the sample-dispatch border source bound by the count-loop proof.

    Returns:
        The count-loop consumer.

    Raises:
        Error: The live file or the border pin changed.
    """
    var path = "extensions/carla/curve_sample_dispatch.mojo"
    var live = Path(path).read_text()
    if (
        sha256_hex(live.as_bytes())
        != "04ff45c12cefcb4dbe3a7b136e77b6baaf02cff52325f6599d99250f820fdebb"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: " + path
        )
    var starts = List[Int]()
    var stops = List[Int]()
    var befores = List[String]()
    _edits_8(starts, stops, befores)
    var restored = _apply(live, starts, stops, befores)
    if (
        sha256_hex(restored.as_bytes())
        != "91ede65bbc39ac57ca54239513b462d3c71e90cacd085b8bafb2bff514767a86"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: " + path
        )
    return restored


def _edits_41(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(317)
    stops.append(319)
    befores.append("            or a mesh cannot be tested.\n")
    starts.append(216)
    stops.append(226)
    befores.append("        return Int(exact + 0.5)\n")
    starts.append(206)
    stops.append(210)
    befores.append("")
    starts.append(195)
    stops.append(199)
    befores.append("")
    starts.append(193)
    stops.append(194)
    befores.append("    def points_per_laser(self, tick: Duration) -> Int:\n")
    starts.append(181)
    stops.append(182)
    befores.append("")
    starts.append(177)
    stops.append(180)
    befores.append("")
    starts.append(171)
    stops.append(172)
    befores.append("    def laser_angles(self) -> List[Angle]:\n")
    starts.append(135)
    stops.append(136)
    befores.append("")
    starts.append(42)
    stops.append(63)
    befores.append("")
    starts.append(28)
    stops.append(29)
    befores.append("from std.math import cos, exp, log, sin, sqrt, trunc\n")


def _edits_42(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(522)
    stops.append(524)
    befores.append(
        "            var u = (Float32(x) + 0.5) / w * 2 - 1\n        "
        "    var v = (Float32(y) + 0.5) / h * 2 - 1\n"
    )
    starts.append(506)
    stops.append(509)
    befores.append("")
    starts.append(304)
    stops.append(307)
    befores.append("")
    starts.append(290)
    stops.append(291)
    befores.append("):\n")
    starts.append(138)
    stops.append(140)
    befores.append(
        "        var u = (Float32(x) + 0.5) / Float32(self.width) * 2"
        " - 1\n        var v = 1 - (Float32(y) + 0.5) / Float32(self."
        "height) * 2\n"
    )
    starts.append(132)
    stops.append(134)
    befores.append("                the near plane and 1 at the far.\n")
    starts.append(34)
    stops.append(35)
    befores.append("from math.utils import SeededRandom\n")


def _edits_43(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(653)
    stops.append(655)
    befores.append("")
    starts.append(640)
    stops.append(651)
    befores.append('    """Refuse a texture of no texels."""\n')
    starts.append(375)
    stops.append(376)
    befores.append("        Error: If `size` is less than one.\n")
    starts.append(338)
    stops.append(339)
    befores.append("        Error: If `size` is less than one.\n")
    starts.append(283)
    stops.append(285)
    befores.append("        Error: If `size` or `slabs` is less than one.\n")
    starts.append(231)
    stops.append(232)
    befores.append("        Error: If `size` is less than one.\n")
    starts.append(160)
    stops.append(162)
    befores.append(
        "        Error: If `size` is less than one, or the heights ar"
        "e not\n            `size * size`.\n"
    )
    starts.append(31)
    stops.append(32)
    befores.append("The sizes and colors are this port's own choices.\n")


def _edits_44(
    mut starts: List[Int], mut stops: List[Int], mut befores: List[String]
):
    """Fill one reviewed line-edit table, highest line first.

    Args:
        starts: The 0-based start lines.
        stops: The exclusive end lines.
        befores: The predecessor lines for each span.
    """
    starts.append(592)
    stops.append(593)
    befores.append("")
    starts.append(550)
    stops.append(558)
    befores.append("    return round_half_from_zero(fov / step)\n")
    starts.append(539)
    stops.append(541)
    befores.append(
        "        Error: If the resolution or field of view is nonfinite.\n"
    )
    starts.append(500)
    stops.append(501)
    befores.append("")
    starts.append(397)
    stops.append(398)
    befores.append("")
    starts.append(312)
    stops.append(333)
    befores.append(
        "def _per_laser(description: LidarDescription, tick: Duration"
        ") -> Int:\n    return round_half_from_zero(\n        Float32"
        "(description.points_per_second)\n        * tick.to(SECOND)\n"
        "        / Float32(description.channels)\n    )\n"
    )
    starts.append(63)
    stops.append(64)
    befores.append("")


def restored_border_pins(
    mut paths: List[String], mut texts: List[String]
) raises:
    """Restore each reviewed border pin from its live file.

    Args:
        paths: The consumer paths, in record order.
        texts: The restored source for each path.

    Raises:
        Error: A live file or a restored pin changed.
    """
    var starts = List[Int]()
    var stops = List[Int]()
    var befores = List[String]()
    var live_0 = Path("extensions/carla/agents.mojo").read_text()
    if (
        sha256_hex(live_0.as_bytes())
        != "0789e9056ca117b2474f7daede991044a7b885f03175f606af55ad2871d472d6"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/agents.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_0(starts, stops, befores)
    var text_0 = _apply(live_0, starts, stops, befores)
    if (
        sha256_hex(text_0.as_bytes())
        != "066d6b805c042341cd023203bce6d2c5f6851121af870585604f860cd858b8b6"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/agents.mojo"
        )
    paths.append("extensions/carla/agents.mojo")
    texts.append(text_0)

    var live_1 = Path("extensions/carla/agents_behavior.mojo").read_text()
    if (
        sha256_hex(live_1.as_bytes())
        != "513601d24c23a9372e34ff8b8cb4b68a33e8275360403af5ac752af8c4080b9e"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/agents_behavior.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_1(starts, stops, befores)
    var text_1 = _apply(live_1, starts, stops, befores)
    if (
        sha256_hex(text_1.as_bytes())
        != "ec8c08f254c62b0ad86ba679bb73cd9cf1c1e4b6a02aa459e91ed39195f1108f"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/agents_behavior.mojo"
        )
    paths.append("extensions/carla/agents_behavior.mojo")
    texts.append(text_1)

    var live_2 = Path("extensions/carla/agents_local_planner.mojo").read_text()
    if (
        sha256_hex(live_2.as_bytes())
        != "ac0a26c230b02387536e73aa73752c73154e0e047b30c555e1f29c2952a8ef57"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/agents_local_planner.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_2(starts, stops, befores)
    var text_2 = _apply(live_2, starts, stops, befores)
    if (
        sha256_hex(text_2.as_bytes())
        != "9df0c612317fedb77367ecd9d19e90ef6c070503a14000e7590c3f27d4a190e3"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/agents_local_planner.mojo"
        )
    paths.append("extensions/carla/agents_local_planner.mojo")
    texts.append(text_2)

    var live_3 = Path("extensions/carla/agents_misc.mojo").read_text()
    if (
        sha256_hex(live_3.as_bytes())
        != "e61d260d2860b69f235e485c3328dcb697356487eae8ed7169562bdd85119512"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/agents_misc.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_3(starts, stops, befores)
    var text_3 = _apply(live_3, starts, stops, befores)
    if (
        sha256_hex(text_3.as_bytes())
        != "cc0f1a129133b7976c4820e1bb20404fc6af9f88a22717385a6f4c88ac0786fe"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/agents_misc.mojo"
        )
    paths.append("extensions/carla/agents_misc.mojo")
    texts.append(text_3)

    var live_4 = Path("extensions/carla/agents_route.mojo").read_text()
    if (
        sha256_hex(live_4.as_bytes())
        != "e53221dee2acec98cee82cb2191aa0d713eee2c0f3b202d6454c569c3438c939"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/agents_route.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_4(starts, stops, befores)
    var text_4 = _apply(live_4, starts, stops, befores)
    if (
        sha256_hex(text_4.as_bytes())
        != "416a86c052dc86cf709bfd33bec5b15ef360c07f6f5cb53aa42a3e9968d33199"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/agents_route.mojo"
        )
    paths.append("extensions/carla/agents_route.mojo")
    texts.append(text_4)

    var live_5 = Path("extensions/carla/blueprint.mojo").read_text()
    if (
        sha256_hex(live_5.as_bytes())
        != "9847da6309d62a432c18cbc1e02170b7be37eca1bf437f2b6b7774f36f9219ca"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/blueprint.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_5(starts, stops, befores)
    var text_5 = _apply(live_5, starts, stops, befores)
    if (
        sha256_hex(text_5.as_bytes())
        != "2a59a1c6c95d66cb00d064ab15a37964c2153835b49c878ac3e824ce91d50782"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/blueprint.mojo"
        )
    paths.append("extensions/carla/blueprint.mojo")
    texts.append(text_5)

    var live_6 = Path("extensions/carla/camera_render.mojo").read_text()
    if (
        sha256_hex(live_6.as_bytes())
        != "ec20cf17e56ddc9367be8bf2d82ed4b0f7d8e4e54b4a2d6db006cfeb00c6439d"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/camera_render.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_6(starts, stops, befores)
    var text_6 = _apply(live_6, starts, stops, befores)
    if (
        sha256_hex(text_6.as_bytes())
        != "35bc60addf95d4e8bff48537f12fe29facbaf9288f845301bbce6c76870f3706"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/camera_render.mojo"
        )
    paths.append("extensions/carla/camera_render.mojo")
    texts.append(text_6)

    var live_7 = Path("extensions/carla/curve_rounded_line.mojo").read_text()
    if (
        sha256_hex(live_7.as_bytes())
        != "22b70ec9febc6f3d21a8a4d9f1a74650d676e34782fab2812004a1a3aadeb698"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/curve_rounded_line.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_7(starts, stops, befores)
    var text_7 = _apply(live_7, starts, stops, befores)
    if (
        sha256_hex(text_7.as_bytes())
        != "6741ad9d7434c08070de3c959cb49ac42939ac633d1dcd48c9f5cdfdaa719aed"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/curve_rounded_line.mojo"
        )
    paths.append("extensions/carla/curve_rounded_line.mojo")
    texts.append(text_7)

    var text_8 = restored_dispatch_border()
    paths.append("extensions/carla/curve_sample_dispatch.mojo")
    texts.append(text_8)

    var live_9 = Path("extensions/carla/geo.mojo").read_text()
    if (
        sha256_hex(live_9.as_bytes())
        != "97abf4a7ba3b36fa923c8ad2520f978921a81fad4bc284080060cd23fcdc1c83"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/geo.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_9(starts, stops, befores)
    var text_9 = _apply(live_9, starts, stops, befores)
    if (
        sha256_hex(text_9.as_bytes())
        != "2b09610f1933d26281a7e018a1474bcb4a59daa63e01ef24528f342cc834a8a5"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/geo.mojo"
        )
    paths.append("extensions/carla/geo.mojo")
    texts.append(text_9)

    var live_10 = Path("extensions/carla/gnss.mojo").read_text()
    if (
        sha256_hex(live_10.as_bytes())
        != "6b388d7e3e6c97b741ecbc35f559d6e294d2fdd5f28b602af4ddd75c1858f55f"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/gnss.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_10(starts, stops, befores)
    var text_10 = _apply(live_10, starts, stops, befores)
    if (
        sha256_hex(text_10.as_bytes())
        != "5f5a97dbb89416efb9be3e0851b304b2aa46b3002dc7ee51dd3f7df04848085b"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/gnss.mojo"
        )
    paths.append("extensions/carla/gnss.mojo")
    texts.append(text_10)

    var live_11 = Path("extensions/carla/lane_box_cover.mojo").read_text()
    if (
        sha256_hex(live_11.as_bytes())
        != "540fbc13b9b0c769f4722b85f540bec773334e33cac910c5df0001893f38e7fe"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/lane_box_cover.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_11(starts, stops, befores)
    var text_11 = _apply(live_11, starts, stops, befores)
    if (
        sha256_hex(text_11.as_bytes())
        != "1ed9978fb4ef7eef3a45c7503dbf5cced03ab1917f6fbf721c785e5a63cce251"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/lane_box_cover.mojo"
        )
    paths.append("extensions/carla/lane_box_cover.mojo")
    texts.append(text_11)

    var live_12 = Path("extensions/carla/lane_geometry.mojo").read_text()
    if (
        sha256_hex(live_12.as_bytes())
        != "f0a4900cc046cf42e925ed912b6557db494eeab3f342a71d72387fe49c667be5"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/lane_geometry.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_12(starts, stops, befores)
    var text_12 = _apply(live_12, starts, stops, befores)
    if (
        sha256_hex(text_12.as_bytes())
        != "8e0917249d8c41233bcb801fac6455d614ed46a7fd8e7505c14259c2a5c81d91"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/lane_geometry.mojo"
        )
    paths.append("extensions/carla/lane_geometry.mojo")
    texts.append(text_12)

    var live_13 = Path("extensions/carla/map_builder.mojo").read_text()
    if (
        sha256_hex(live_13.as_bytes())
        != "6c705c9a40e045c30f70dfbc160e8b8fc706396ccbc0fc0e21e5ca92ab5b6078"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/map_builder.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_13(starts, stops, befores)
    var text_13 = _apply(live_13, starts, stops, befores)
    if (
        sha256_hex(text_13.as_bytes())
        != "f5e28830bb017e42b61d3a40f7e96711ad7aa893d121472f311e36b9a9572d0c"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/map_builder.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_13_b(starts, stops, befores)
    text_13 = _apply(text_13, starts, stops, befores)
    if (
        sha256_hex(text_13.as_bytes())
        != "4092bfc42e1ab091b272da89d1079675ce8fabddd77de573a91df6911aeede61"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/map_builder.mojo"
        )
    paths.append("extensions/carla/map_builder.mojo")
    texts.append(text_13)

    var live_14 = Path("extensions/carla/math.mojo").read_text()
    if (
        sha256_hex(live_14.as_bytes())
        != "fc4fa96bbb1470dc10a4ea894003055610ffb1d08e7d6b2558f204bb243045f0"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/math.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_14(starts, stops, befores)
    var text_14 = _apply(live_14, starts, stops, befores)
    if (
        sha256_hex(text_14.as_bytes())
        != "e02aa0a1d41c17403120ebe1bd4672c2d5a41bb81aac66f1abb7e9a1cb42d147"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/math.mojo"
        )
    paths.append("extensions/carla/math.mojo")
    texts.append(text_14)

    var live_15 = Path("extensions/carla/mesh_factory.mojo").read_text()
    if (
        sha256_hex(live_15.as_bytes())
        != "291679187df49469796893a4885903f003253493d0a928e5b4fb33a2d970f7b6"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/mesh_factory.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_15(starts, stops, befores)
    var text_15 = _apply(live_15, starts, stops, befores)
    if (
        sha256_hex(text_15.as_bytes())
        != "38326e9369f608929b97ee9cffd32f7febc659e31afb024cf6d078178c0439ef"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/mesh_factory.mojo"
        )
    paths.append("extensions/carla/mesh_factory.mojo")
    texts.append(text_15)

    var live_16 = Path("extensions/carla/navigation_mesh.mojo").read_text()
    if (
        sha256_hex(live_16.as_bytes())
        != "19314a6e5db27de8843bbd93f52e9ac185c62af1e8fc71e5de54a79659015e9b"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/navigation_mesh.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_16(starts, stops, befores)
    var text_16 = _apply(live_16, starts, stops, befores)
    if (
        sha256_hex(text_16.as_bytes())
        != "7062918ed17cae12cef32bf7801a0f7d56a99ca2993fea32214247ee2c86a841"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/navigation_mesh.mojo"
        )
    paths.append("extensions/carla/navigation_mesh.mojo")
    texts.append(text_16)

    var live_17 = Path("extensions/carla/props.mojo").read_text()
    if (
        sha256_hex(live_17.as_bytes())
        != "0f7cb38a6afde496f0426786e89c9954490dc34894ba0c732920fc46dddf7542"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/props.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_17(starts, stops, befores)
    var text_17 = _apply(live_17, starts, stops, befores)
    if (
        sha256_hex(text_17.as_bytes())
        != "68438b88c940716d194efb56bf305fcc2efd6f222cee6627fb3eb831793dd149"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/props.mojo"
        )
    paths.append("extensions/carla/props.mojo")
    texts.append(text_17)

    var live_18 = Path("extensions/carla/radar.mojo").read_text()
    if (
        sha256_hex(live_18.as_bytes())
        != "79d31d62991aa60a35e008098fda25c9ba559e94c5823bbfe768061a5005f775"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/radar.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_18(starts, stops, befores)
    var text_18 = _apply(live_18, starts, stops, befores)
    if (
        sha256_hex(text_18.as_bytes())
        != "ed8a31d4243149a2ac707ea8c510994712ba4efc1ee1602215da476b81369cf0"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/radar.mojo"
        )
    paths.append("extensions/carla/radar.mojo")
    texts.append(text_18)

    var live_19 = Path("extensions/carla/recorder.mojo").read_text()
    if (
        sha256_hex(live_19.as_bytes())
        != "e04a7b125714d0840715e5239edb5930e7cd1fe86e37e448022fe76fefc2be31"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/recorder.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_19(starts, stops, befores)
    var text_19 = _apply(live_19, starts, stops, befores)
    if (
        sha256_hex(text_19.as_bytes())
        != "8554db42ffa17cc50562ff257040796adbef0d57b947a7ba530a68d6902bf173"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/recorder.mojo"
        )
    paths.append("extensions/carla/recorder.mojo")
    texts.append(text_19)

    var live_20 = Path("extensions/carla/recorder_packets.mojo").read_text()
    if (
        sha256_hex(live_20.as_bytes())
        != "7b1f564b8254f6184a51d9093a300ba3b8db467ae93e0b872be835bd611e4de1"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/recorder_packets.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_20(starts, stops, befores)
    var text_20 = _apply(live_20, starts, stops, befores)
    if (
        sha256_hex(text_20.as_bytes())
        != "9249aa5bc2793c9feff1f24d7e7ac95c86cee1b9bd0eb1de5638c01a6896ae8e"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/recorder_packets.mojo"
        )
    paths.append("extensions/carla/recorder_packets.mojo")
    texts.append(text_20)

    var live_21 = Path("extensions/carla/render_light.mojo").read_text()
    if (
        sha256_hex(live_21.as_bytes())
        != "039c2602ebe70c7f9564ab39945b0e885e65833950fa2a255b1123edf343970d"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/render_light.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_21(starts, stops, befores)
    var text_21 = _apply(live_21, starts, stops, befores)
    if (
        sha256_hex(text_21.as_bytes())
        != "813f7294c4e0a22bea119b06764726131d9bbc52b881caf78cca9f73a9e535e7"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/render_light.mojo"
        )
    paths.append("extensions/carla/render_light.mojo")
    texts.append(text_21)

    var live_22 = Path("extensions/carla/replayer.mojo").read_text()
    if (
        sha256_hex(live_22.as_bytes())
        != "72fbe8411447f3705b5cb48e592c07d2c50eebf4c97ac24f7288d57ef1598055"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/replayer.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_22(starts, stops, befores)
    var text_22 = _apply(live_22, starts, stops, befores)
    if (
        sha256_hex(text_22.as_bytes())
        != "c97b08f6f6222e97f286e82b6f0d61633d79d3f607eee077aeea21fecbcc7900"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/replayer.mojo"
        )
    paths.append("extensions/carla/replayer.mojo")
    texts.append(text_22)

    var live_23 = Path("extensions/carla/replayer_helper.mojo").read_text()
    if (
        sha256_hex(live_23.as_bytes())
        != "f9f625ec0f0500a80a2bb839cabe01311bb08c7e403d70198dae245f8477b1fa"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/replayer_helper.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_23(starts, stops, befores)
    var text_23 = _apply(live_23, starts, stops, befores)
    if (
        sha256_hex(text_23.as_bytes())
        != "259c31478efee2202f58f73b8813336f573e0022e62a2b1241a255841ba2904f"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/replayer_helper.mojo"
        )
    paths.append("extensions/carla/replayer_helper.mojo")
    texts.append(text_23)

    var live_24 = Path("extensions/carla/road_info.mojo").read_text()
    if (
        sha256_hex(live_24.as_bytes())
        != "3ae47c8a824902138a5921015ad78928d9e1db3cafc66c4df2929023950d9bb8"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/road_info.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_24(starts, stops, befores)
    var text_24 = _apply(live_24, starts, stops, befores)
    if (
        sha256_hex(text_24.as_bytes())
        != "60460851e8884dd89271357a07fa8e127979d68a43c7f4e5962907d1634e12cb"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/road_info.mojo"
        )
    paths.append("extensions/carla/road_info.mojo")
    texts.append(text_24)

    var live_25 = Path("extensions/carla/sensor_data.mojo").read_text()
    if (
        sha256_hex(live_25.as_bytes())
        != "ce3e3089c75c25090f534c988506c2739d494ff4269ee5014b068af4e66481c8"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/sensor_data.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_25(starts, stops, befores)
    var text_25 = _apply(live_25, starts, stops, befores)
    if (
        sha256_hex(text_25.as_bytes())
        != "d881a4a66cd7fa61cde9e441c9c52cbcc33be6f1f32900ea915d440bcecac620"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/sensor_data.mojo"
        )
    paths.append("extensions/carla/sensor_data.mojo")
    texts.append(text_25)

    var live_26 = Path("extensions/carla/spiral_domain_proof.mojo").read_text()
    if (
        sha256_hex(live_26.as_bytes())
        != "a641d554b2c2a3fe5d64bbfed9c4d5b10ac71858e13cd3c35c9619a7766720e9"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/spiral_domain_proof.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_26(starts, stops, befores)
    var text_26 = _apply(live_26, starts, stops, befores)
    if (
        sha256_hex(text_26.as_bytes())
        != "89a8760eee14ff17c682ac69657eb62391e5dfd7e6e1e11fa8a931f8595e9252"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/spiral_domain_proof.mojo"
        )
    paths.append("extensions/carla/spiral_domain_proof.mojo")
    texts.append(text_26)

    var live_27 = Path("extensions/carla/spiral_grouped_lane.mojo").read_text()
    if (
        sha256_hex(live_27.as_bytes())
        != "203dd75e3729ca3b11071e0e4f2c5fe36b6d4d34302084b8a23193373fd052a7"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/spiral_grouped_lane.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_27(starts, stops, befores)
    var text_27 = _apply(live_27, starts, stops, befores)
    if (
        sha256_hex(text_27.as_bytes())
        != "5da09d64a7e3c44139ddc59d0a636ff124470a48834fc81bb05c677c7147694b"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/spiral_grouped_lane.mojo"
        )
    paths.append("extensions/carla/spiral_grouped_lane.mojo")
    texts.append(text_27)

    var live_28 = Path("extensions/carla/town.mojo").read_text()
    if (
        sha256_hex(live_28.as_bytes())
        != "966c0050ee1e67e77c6371a6f415f0afe9bef561804d167dd35e50aa5633c73d"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/town.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_28(starts, stops, befores)
    var text_28 = _apply(live_28, starts, stops, befores)
    if (
        sha256_hex(text_28.as_bytes())
        != "f1917d2fdbe678e0f6623d0bd44f80f54b4e0a9f9c4bb9c486c312ae6cf50ee5"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/town.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_28_b(starts, stops, befores)
    text_28 = _apply(text_28, starts, stops, befores)
    if (
        sha256_hex(text_28.as_bytes())
        != "3cb00b215cf8be1e9b70f6e67afa1aa395d58ce9b9c52030743136d6d5465c1b"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/town.mojo"
        )
    paths.append("extensions/carla/town.mojo")
    texts.append(text_28)

    var live_29 = Path("extensions/carla/traffic_light.mojo").read_text()
    if (
        sha256_hex(live_29.as_bytes())
        != "c5c9a860a7d6668d2fa0a803a20fce84bd598512d42b3ebc98f01c27af9d939e"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/traffic_light.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_29(starts, stops, befores)
    var text_29 = _apply(live_29, starts, stops, befores)
    if (
        sha256_hex(text_29.as_bytes())
        != "f776d47f613cbaa2d75b2c66f378572951b060e229ffe47859e514b82842e025"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/traffic_light.mojo"
        )
    paths.append("extensions/carla/traffic_light.mojo")
    texts.append(text_29)

    var live_30 = Path("extensions/carla/traffic_manager.mojo").read_text()
    if (
        sha256_hex(live_30.as_bytes())
        != "5feb52aab120e95411161921661124eb5ca42989370467acf5bad613cd2fcfe6"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/traffic_manager.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_30(starts, stops, befores)
    var text_30 = _apply(live_30, starts, stops, befores)
    if (
        sha256_hex(text_30.as_bytes())
        != "75abce8cce536efec92c0473971dbb395d06aa9e69edb868cfcee62d53379478"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/traffic_manager.mojo"
        )
    paths.append("extensions/carla/traffic_manager.mojo")
    texts.append(text_30)

    var live_31 = Path(
        "extensions/carla/traffic_manager_collision.mojo"
    ).read_text()
    if (
        sha256_hex(live_31.as_bytes())
        != "b9ee47331258a1c06f47ff60fe56fcb848d7e3c5a7c7cca3ef53de636eddd1ee"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/traffic_manager_collision.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_31(starts, stops, befores)
    var text_31 = _apply(live_31, starts, stops, befores)
    if (
        sha256_hex(text_31.as_bytes())
        != "0af2bfde92c55900bb862886fd9d2ca3b6f6920f1acc412379dbdf1380da2952"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/traffic_manager_collision.mojo"
        )
    paths.append("extensions/carla/traffic_manager_collision.mojo")
    texts.append(text_31)

    var live_32 = Path(
        "extensions/carla/traffic_manager_localization.mojo"
    ).read_text()
    if (
        sha256_hex(live_32.as_bytes())
        != "6ac9f8bf44015c3609331181b81cb36127200272839779234017f02cda3e1d97"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/traffic_manager_localization.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_32(starts, stops, befores)
    var text_32 = _apply(live_32, starts, stops, befores)
    if (
        sha256_hex(text_32.as_bytes())
        != "0ee0e9cff88a49f0a52939adf87a82dd064c8655f77093dc4bfd36af9f644734"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/traffic_manager_localization.mojo"
        )
    paths.append("extensions/carla/traffic_manager_localization.mojo")
    texts.append(text_32)

    var live_33 = Path("extensions/carla/traffic_manager_map.mojo").read_text()
    if (
        sha256_hex(live_33.as_bytes())
        != "620d3f33e995acbd5c37fcf3141022f3451b0e4413893739e4b7411d48a1acf8"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/traffic_manager_map.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_33(starts, stops, befores)
    var text_33 = _apply(live_33, starts, stops, befores)
    if (
        sha256_hex(text_33.as_bytes())
        != "6dd214eef706346be535c24d8506f9373456676bba9192fc213c7854e541e4be"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/traffic_manager_map.mojo"
        )
    paths.append("extensions/carla/traffic_manager_map.mojo")
    texts.append(text_33)

    var live_34 = Path(
        "extensions/carla/traffic_manager_parameters.mojo"
    ).read_text()
    if (
        sha256_hex(live_34.as_bytes())
        != "74c9482b833d35733bdc143fed2ce313c778b8aa4d834b53b4a1f4214e6a1c96"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/traffic_manager_parameters.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_34(starts, stops, befores)
    var text_34 = _apply(live_34, starts, stops, befores)
    if (
        sha256_hex(text_34.as_bytes())
        != "4750289496b0e85de99b487a6e57d69ce0233893f86db276f75d5d6383d93536"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/traffic_manager_parameters.mojo"
        )
    paths.append("extensions/carla/traffic_manager_parameters.mojo")
    texts.append(text_34)

    var live_35 = Path(
        "extensions/carla/traffic_manager_planning.mojo"
    ).read_text()
    if (
        sha256_hex(live_35.as_bytes())
        != "0fad3b00c42544f47dcb2425ea9703c4490a73bf77d7e780ea1b8fda3d37fcbe"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/traffic_manager_planning.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_35(starts, stops, befores)
    var text_35 = _apply(live_35, starts, stops, befores)
    if (
        sha256_hex(text_35.as_bytes())
        != "b4d22df0f4cc6d6ac41eee7b9fd34812402fca5cdd39e84898d070b17fbed3ab"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/traffic_manager_planning.mojo"
        )
    paths.append("extensions/carla/traffic_manager_planning.mojo")
    texts.append(text_35)

    var live_36 = Path(
        "extensions/carla/traffic_manager_shared.mojo"
    ).read_text()
    if (
        sha256_hex(live_36.as_bytes())
        != "25215dfd21b787a5984c03bc6a678f09093080e868cd6bebef51336bc65f92d5"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/traffic_manager_shared.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_36(starts, stops, befores)
    var text_36 = _apply(live_36, starts, stops, befores)
    if (
        sha256_hex(text_36.as_bytes())
        != "f4595070de5a3c90df835668246cae1bab2ce8aaa5279538bcd1f8a3d860493a"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/traffic_manager_shared.mojo"
        )
    paths.append("extensions/carla/traffic_manager_shared.mojo")
    texts.append(text_36)

    var live_37 = Path(
        "extensions/carla/traffic_manager_state.mojo"
    ).read_text()
    if (
        sha256_hex(live_37.as_bytes())
        != "60b8d09b453e8814fe69eee43be61ffca7d78a3837973fbd3b21099379c0b102"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/traffic_manager_state.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_37(starts, stops, befores)
    var text_37 = _apply(live_37, starts, stops, befores)
    if (
        sha256_hex(text_37.as_bytes())
        != "e34c471b8077d5f0a0a9359a258ced7ad30ca9d17bf9d5ba8aa78dd9253b81aa"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/traffic_manager_state.mojo"
        )
    paths.append("extensions/carla/traffic_manager_state.mojo")
    texts.append(text_37)

    var live_38 = Path("extensions/carla/traffic_sign.mojo").read_text()
    if (
        sha256_hex(live_38.as_bytes())
        != "70997f536d06786103665c5c70aa9e710f0645df0bc5e67bfb57886b15cf370a"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/traffic_sign.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_38(starts, stops, befores)
    var text_38 = _apply(live_38, starts, stops, befores)
    if (
        sha256_hex(text_38.as_bytes())
        != "fc5a409d77d0ffdc4b8c8484a17dd93ec37e0b3cf9f1c44dc6c26e97a3514595"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/traffic_sign.mojo"
        )
    paths.append("extensions/carla/traffic_sign.mojo")
    texts.append(text_38)

    var live_39 = Path("extensions/carla/v2x.mojo").read_text()
    if (
        sha256_hex(live_39.as_bytes())
        != "9177db17caf38940a18b671ea04d3877cc14e966e5352e21576e95ed1449e308"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/v2x.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_39(starts, stops, befores)
    var text_39 = _apply(live_39, starts, stops, befores)
    if (
        sha256_hex(text_39.as_bytes())
        != "1a4e8d23c07db07a61f28a0897481c5d2b8b91d14106fc841f681eb3331d03b7"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/v2x.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_39_b(starts, stops, befores)
    text_39 = _apply(text_39, starts, stops, befores)
    if (
        sha256_hex(text_39.as_bytes())
        != "b96b383c8c46120978ccddb0bc7f068a2799d6c95b0cf4619a3caea40dd0cc36"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/v2x.mojo"
        )
    paths.append("extensions/carla/v2x.mojo")
    texts.append(text_39)

    var live_40 = Path("extensions/carla/weather.mojo").read_text()
    if (
        sha256_hex(live_40.as_bytes())
        != "a387c7b041b7cfc8e0662d85f7900ddd7509d1cac39296b57c86acbfcd2876f5"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/weather.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_40(starts, stops, befores)
    var text_40 = _apply(live_40, starts, stops, befores)
    if (
        sha256_hex(text_40.as_bytes())
        != "c498f21bceaf217709f41c1fbf181b507ecd29a6a0d2b019530f1766f83b903c"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/weather.mojo"
        )
    paths.append("extensions/carla/weather.mojo")
    texts.append(text_40)

    var live_41 = Path("extensions/carla/lidar.mojo").read_text()
    if (
        sha256_hex(live_41.as_bytes())
        != "7e6c49a3e8ec17858eafbc74b7051492da1f9da6c6f7302010b5ff38c42741db"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/lidar.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_41(starts, stops, befores)
    var text_41 = _apply(live_41, starts, stops, befores)
    if (
        sha256_hex(text_41.as_bytes())
        != "919e2efbb74445d59c45dd7ae32b4ba21f6558cf9115b2d0d15c6ce24d5c8783"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/lidar.mojo"
        )
    paths.append("extensions/carla/lidar.mojo")
    texts.append(text_41)

    var live_42 = Path("extensions/carla/render_post.mojo").read_text()
    if (
        sha256_hex(live_42.as_bytes())
        != "24c2f807ef5cc5d1b6025aa951feedb8c33d2df665185c63bb91a996de7b73fb"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/render_post.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_42(starts, stops, befores)
    var text_42 = _apply(live_42, starts, stops, befores)
    if (
        sha256_hex(text_42.as_bytes())
        != "8fe64d4c0ba39b549e714e640b2283d70d60a1bdf1816497bc295319b2f009c7"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/render_post.mojo"
        )
    paths.append("extensions/carla/render_post.mojo")
    texts.append(text_42)

    var live_43 = Path("extensions/carla/render_textures.mojo").read_text()
    if (
        sha256_hex(live_43.as_bytes())
        != "12a198cbcef1d0c43df2b8feebfcf4c332f8e1366295adf3aade78ffb46ea16a"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/render_textures.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_43(starts, stops, befores)
    var text_43 = _apply(live_43, starts, stops, befores)
    if (
        sha256_hex(text_43.as_bytes())
        != "d79c12e55dff9ad3ca829f7219365a8bbe1ac5ca6a6be799ce10cc56e0feb42b"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/render_textures.mojo"
        )
    paths.append("extensions/carla/render_textures.mojo")
    texts.append(text_43)

    var live_44 = Path("extensions/carla/semantic_lidar.mojo").read_text()
    if (
        sha256_hex(live_44.as_bytes())
        != "b0f93217b8a55ca63c5904397673f57d264efa8b46e5b3691b2d68eb93269b84"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/semantic_lidar.mojo"
        )
    starts.clear()
    stops.clear()
    befores.clear()
    _edits_44(starts, stops, befores)
    var text_44 = _apply(live_44, starts, stops, befores)
    if (
        sha256_hex(text_44.as_bytes())
        != "057c4be981b28dcd16a5a536706eea66bc6ecb547ac75d8aa8dae7e33aae6f55"
    ):
        raise Error(
            "reviewed border parser successor: border pin changed: "
            + "extensions/carla/semantic_lidar.mojo"
        )
    paths.append("extensions/carla/semantic_lidar.mojo")
    texts.append(text_44)
