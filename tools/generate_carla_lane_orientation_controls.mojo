# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reproduce corrected town orientation controls without Mojo outputs.

    generate_carla_lane_orientation_controls

prints a JSON report from `assets/carla/town.xodr`. Run it from the
repository root. It reads only the hand-authored OpenDRIVE fixture, and it
imports no CARLA module of this port.

The tool differentiates the line, arc and clothoid equations and the
documented CARLA sample interpolation model. The spiral reference uses its
analytic unit tangent, not the Gauss-Legendre quadrature of the port. The
tool reconstructs the sample positions and derivative vectors from their
cubic definitions.

The report is that of the Python generator that this tool replaces, digit
for digit. To get the same digits, each product is rounded before a sum
uses it, `math.hypot` is CPython's own algorithm, and the trigonometric
functions are those of the C library.
"""

from std.benchmark import black_box

# The standard `atan2` calls the C library's on a CPU. A second declaration
# of the C function would conflict with it in a build that holds both.
from std.math import atan2, pi, sqrt
from std.pathlib import Path
from std.sys import exit, stderr

from loaders.xml import XmlDocument, parse_xml
from tools._json_tools import JsonWriter
from tools._python_float import parse_float
from tools._python_math import (
    acos,
    cos,
    degrees,
    float_sum,
    hypot,
    sin,
)


comptime TOWN = "assets/carla/town.xodr"
"""The OpenDRIVE fixture below the repository root."""

comptime EPSILON = Float64(2.220446049250313e-16)
"""The machine epsilon of a double."""


def _m(a: Float64, b: Float64) -> Float64:
    """Return a product rounded on its own, before a sum uses it."""
    return black_box(a * b)


def _py_min(a: Float64, b: Float64) -> Float64:
    """Return `min(a, b)`: a, unless b is less."""
    return b if b < a else a


def _py_max(a: Float64, b: Float64) -> Float64:
    """Return `max(a, b)`: a, unless b is greater."""
    return b if b > a else a


def _number(
    document: XmlDocument, element: Int, key: String, default: String = "0"
) raises -> Float64:
    """Return `float(element.get(key, default))`."""
    return parse_float(document.attribute(element, key, default))


def _find_all(
    document: XmlDocument, element: Int, first: String, second: String
) raises -> List[Int]:
    """Return `element.findall("first/second")`; `*` matches any child."""
    var found = List[Int]()
    for child in document.children(element):
        if first != "*" and document.name(child) != first:
            continue
        for grandchild in document.children_named(child, second):
            found.append(grandchild)
    return found^


def _first_child(document: XmlDocument, element: Int) raises -> Int:
    """Return `element[0]`."""
    var children = document.children(element)
    if len(children) == 0:
        raise Error("IndexError: child index out of range")
    return children[0]


def coefficients(
    document: XmlDocument, node: Int, suffix: String = ""
) raises -> List[Float64]:
    """Return the a, b, c and d coefficients of a record.

    Args:
        document: The OpenDRIVE document.
        node: The record element.
        suffix: The attribute suffix, such as `U` or `V`.

    Returns:
        The four coefficients; a missing one is zero.

    Raises:
        Error: If an attribute is not a number.
    """
    var result = List[Float64]()
    for key in ["a", "b", "c", "d"]:
        result.append(_number(document, node, key + suffix))
    return result^


def polynomial(coeffs: List[Float64], x: Float64) -> Float64:
    """Return a + x * (b + x * (c + x * d)), each step rounded.

    Args:
        coeffs: The coefficients a, b, c and d.
        x: The parameter.

    Returns:
        The value.
    """
    var inner = coeffs[2] + _m(x, coeffs[3])
    var middle = coeffs[1] + _m(x, inner)
    return coeffs[0] + _m(x, middle)


def slope(coeffs: List[Float64], x: Float64) -> Float64:
    """Return b + x * (2 * c + x * 3 * d), each step rounded.

    Args:
        coeffs: The coefficients a, b, c and d.
        x: The parameter.

    Returns:
        The derivative.
    """
    var inner = 2 * coeffs[2] + _m(_m(x, 3), coeffs[3])
    return coeffs[1] + _m(x, inner)


def active(
    document: XmlDocument, nodes: List[Int], at: Float64, key: String = "s"
) raises -> Int:
    """Return the last record that starts at or before a position.

    Args:
        document: The OpenDRIVE document.
        nodes: The records.
        at: The position.
        key: The start attribute.

    Returns:
        The record, or -1 for none.

    Raises:
        Error: If an attribute is not a number.
    """
    var found = -1
    for node in nodes:
        if _number(document, node, key) <= at:
            found = node
    return found


def record_value(
    document: XmlDocument, nodes: List[Int], at: Float64, key: String = "s"
) raises -> Tuple[Float64, Float64]:
    """Return the value and slope of the active cubic record.

    Args:
        document: The OpenDRIVE document.
        nodes: The records.
        at: The position.
        key: The start attribute.

    Returns:
        The value and slope, or zeros when no record is active.

    Raises:
        Error: If an attribute is not a number.
    """
    var node = active(document, nodes, at, key)
    if node < 0:
        return (0.0, 0.0)
    var local = at - _number(document, node, key)
    var c = coefficients(document, node)
    return (polynomial(c, local), slope(c, local))


struct Oracle(Movable):
    """The town document and the sample tables computed so far."""

    var document: XmlDocument
    """The OpenDRIVE document."""
    var sampled: List[Int]
    """The geometry records that have a sample table."""
    var tables: List[List[List[Float64]]]
    """The sample table of each sampled record."""

    def __init__(out self, var document: XmlDocument):
        """Start with no sample tables.

        Args:
            document: The OpenDRIVE document.
        """
        self.document = document^
        self.sampled = List[Int]()
        self.tables = List[List[List[Float64]]]()

    def samples(mut self, record: Int) raises -> List[List[Float64]]:
        """Sample a polynomial record, without reading a generated fixture.

        Args:
            record: The geometry record.

        Returns:
            Rows of arc length, u, v, du/dp and dv/dp.

        Raises:
            Error: If an attribute is not a number.
        """
        for index in range(len(self.sampled)):
            if self.sampled[index] == record:
                return self.tables[index].copy()
        var table = self._sample(record)
        self.sampled.append(record)
        self.tables.append(table.copy())
        return table^

    def _sample(self, record: Int) raises -> List[List[Float64]]:
        """Compute the sample table of a polynomial record."""
        ref document = self.document
        var child = _first_child(document, record)
        var length = parse_float(document.attribute(record, "length"))
        var result = List[List[Float64]]()
        var total = 0.0
        if document.name(child) == "poly3":
            var v = coefficients(document, child)
            var u = 0.0
            var old_u = 0.0
            var old_v = polynomial(v, 0.0)
            result.append([0.0, old_u, old_v, 1.0, slope(v, 0.0)])
            var step = Float64(0.3)
            while total < length + step:
                u += step
                var value = polynomial(v, u)
                total += hypot(u - old_u, value - old_v)
                result.append([total, u, value, 1.0, slope(v, u)])
                old_u = u
                old_v = value
            return result^
        var u = coefficients(document, child, "U")
        var v = coefficients(document, child, "V")
        var intervals = max(Int(length / 0.5), 5)
        var span = length
        if document.attribute(child, "pRange", "") != "arcLength":
            span = 1.0
        var step = span / Float64(intervals)
        var p = 0.0
        var old_u = polynomial(u, 0)
        var old_v = polynomial(v, 0)
        result.append([0.0, old_u, old_v, slope(u, 0), slope(v, 0)])
        for _ in range(intervals):
            p += step
            var pu = polynomial(u, p)
            var pv = polynomial(v, p)
            total += hypot(pu - old_u, pv - old_v)
            result.append([total, pu, pv, slope(u, p), slope(v, p)])
            old_u = pu
            old_v = pv
            if total > length:
                break
        return result^

    def reference(
        mut self, record: Int, at: Float64
    ) raises -> Tuple[Float64, Float64, Float64, Float64]:
        """Return the reference-line derivative, heading and turn rate.

        Args:
            record: The active geometry record.
            at: The road position.

        Returns:
            The derivatives dx/ds and dy/ds, the heading and its
            derivative.

        Raises:
            Error: If an attribute is not a number.
        """
        var d = _py_min(
            _py_max(at - _number(self.document, record, "s"), 0.0),
            _number(self.document, record, "length"),
        )
        var heading = _number(self.document, record, "hdg")
        var child = _first_child(self.document, record)
        var tag = self.document.name(child)
        if tag == "line":
            return (cos(heading), sin(heading), heading, 0.0)
        if tag == "arc":
            var k = _number(self.document, child, "curvature")
            var theta = heading + _m(k, d)
            return (cos(theta), sin(theta), theta, k)
        if tag == "spiral":
            var k = _number(self.document, child, "curvStart")
            var rate = (_number(self.document, child, "curvEnd") - k) / (
                _number(self.document, record, "length")
            )
            var theta = heading + _m(k, d) + _m(_m(rate, d), d) / 2
            return (cos(theta), sin(theta), theta, k + _m(rate, d))
        var table = self.samples(record)
        # bisect_left on the arc lengths.
        var low = 0
        var high = len(table)
        while low < high:
            var middle = (low + high) // 2
            if table[middle][0] < d:
                low = middle + 1
            else:
                high = middle
        var hi = min(max(low, 1), len(table) - 1)
        ref first = table[hi - 1]
        ref second = table[hi]
        var span = second[0] - first[0]
        var alpha = (d - first[0]) / span
        var du = (second[1] - first[1]) / span
        var dv = (second[2] - first[2]) / span
        var tu = first[3] + _m(alpha, second[3] - first[3])
        var tv = first[4] + _m(alpha, second[4] - first[4])
        var dtu = (second[3] - first[3]) / span
        var dtv = (second[4] - first[4]) / span
        var theta = heading + atan2(tv, tu)
        var turn = (_m(tu, dtv) - _m(tv, dtu)) / (_m(tu, tu) + _m(tv, tv))
        var c = cos(heading)
        var sn = sin(heading)
        return (
            _m(du, c) - _m(dv, sn),
            _m(du, sn) + _m(dv, c),
            theta,
            turn,
        )

    def tangent(
        mut self, road: Int, section: Int, lane_id: Int, at: Float64
    ) raises -> Tuple[Float64, Float64, List[Float64]]:
        """Return a lane's yaw, pitch and unit forward direction.

        Args:
            road: The road element.
            section: The lane section element.
            lane_id: The lane id.
            at: The road position.

        Returns:
            The yaw and pitch in degrees, and the direction in CARLA axes.

        Raises:
            Error: If an attribute is not a number, or no geometry is
                active.
        """
        var offsets = _find_all(self.document, road, "lanes", "laneOffset")
        var off = record_value(self.document, offsets, at)
        var offset = -off[0]
        var lateral_slope = -off[1]
        var section_start = _number(self.document, section, "s")
        if lane_id != 0:
            var side = "left" if lane_id > 0 else "right"
            for id in range(1, abs(lane_id) + 1):
                var signed_id = id if lane_id > 0 else -id
                var lane = self._lane(section, side, String(signed_id))
                if lane < 0:
                    continue
                var widths = self.document.children_named(lane, "width")
                var width = record_value(
                    self.document, widths, at - section_start, "sOffset"
                )
                var factor = -1.0 if lane_id > 0 else 1.0
                if id == abs(lane_id):
                    factor *= 0.5
                offset += _m(factor, width[0])
                lateral_slope += _m(factor, width[1])
        var elevations = _find_all(
            self.document, road, "elevationProfile", "elevation"
        )
        var dz = record_value(self.document, elevations, at)[1]
        var record = active(
            self.document,
            _find_all(self.document, road, "planView", "geometry"),
            at,
        )
        if record < 0:
            raise Error("no geometry is active at s = " + String(at))
        var line = self.reference(record, at)
        var dx = line[0]
        var dy = line[1]
        var theta = line[2]
        var turn = line[3]
        var cos_theta = cos(theta)
        var sin_theta = sin(theta)
        dx += _m(_m(offset, turn), cos_theta) + _m(lateral_slope, sin_theta)
        dy += _m(_m(offset, turn), sin_theta) - _m(lateral_slope, cos_theta)
        var yaw = -theta + atan2(
            _m(dx, sin_theta) - _m(dy, cos_theta),
            _m(dx, cos_theta) + _m(dy, sin_theta),
        )
        var pitch = -atan2(dz, hypot(dx, dy))
        var positive: Bool
        if self.document.attribute(road, "rule", "") != "LHT":
            positive = lane_id <= 0
        else:
            positive = lane_id >= 0
        var sign = 1.0 if positive else -1.0
        if not positive:
            var half_turn = Float64(pi)
            yaw += half_turn
            pitch = 2 * half_turn - pitch
        var norm = sqrt(_m(dx, dx) + _m(dy, dy) + _m(dz, dz))
        var direction: List[Float64] = [
            _m(sign, dx) / norm,
            _m(-sign, dy) / norm,
            _m(sign, dz) / norm,
        ]
        return (degrees(yaw), degrees(pitch), direction^)

    def _lane(self, section: Int, side: String, id: String) raises -> Int:
        """Return `section.find(f"{side}/lane[@id='{id}']")`, or -1."""
        for lane in _find_all(self.document, section, side, "lane"):
            if (
                self.document.has_attribute(lane, "id")
                and self.document.attribute(lane, "id") == id
            ):
                return lane
        return -1

    def segment_count(
        mut self,
        road: Int,
        section: Int,
        length: Float64,
        mut margins: List[Float64],
    ) raises -> Tuple[Int, List[Int], List[Int]]:
        """Count the heading-threshold pieces of each lane in a section.

        Args:
            road: The road element.
            section: The lane section element.
            length: The section length.
            margins: Gets the distance of each heading decision from the
                threshold.

        Returns:
            The total, then the lane ids and the count of each.

        Raises:
            Error: If an attribute is not a number, or no geometry is
                active.
        """
        var ids = List[Int]()
        var counts = List[Int]()
        var count = 0
        var start = _number(self.document, section, "s")
        var end = start + length
        var at_start = active(
            self.document,
            _find_all(self.document, road, "planView", "geometry"),
            start,
        )
        if at_start < 0:
            raise Error("no geometry is active at s = " + String(start))
        var straight = (
            self.document.name(_first_child(self.document, at_start)) == "line"
            and start >= _number(self.document, at_start, "s")
            and end
            <= _number(self.document, at_start, "s")
            + _number(self.document, at_start, "length")
        )
        if straight:
            for elevation in _find_all(
                self.document, road, "elevationProfile", "elevation"
            ):
                if (
                    _number(self.document, elevation, "c") != 0
                    or _number(self.document, elevation, "d") != 0
                ):
                    straight = False
                    break
        var left_hand = self.document.attribute(road, "rule", "") == "LHT"
        var threshold = Float64(pi) / 100
        for lane in _find_all(self.document, section, "*", "lane"):
            var id = Int(self.document.attribute(lane, "id"))
            if id == 0:
                continue
            var n: Int
            if straight:
                n = 1
            else:
                var positive = id > 0 if left_hand else id < 0
                var inset = _py_min(100 * EPSILON, length / 4)
                var at = start + inset if positive else end - inset
                var anchor = at
                var forward = self.tangent(road, section, id, at)[2].copy()
                n = 0
                while True:
                    var remaining = (end - at if positive else at - start) - (
                        1e-6
                    )
                    var delta = _py_min(1.0, remaining)
                    if delta < 1e-6:
                        n += 1
                        break
                    var step = delta - 10 * EPSILON
                    at += step if positive else -step
                    var next_forward = self.tangent(road, section, id, at)[
                        2
                    ].copy()
                    var products = List[Float64]()
                    for axis in range(3):
                        products.append(_m(forward[axis], next_forward[axis]))
                    var cosine = _py_max(
                        -1.0, _py_min(1.0, float_sum(products))
                    )
                    var angle = acos(cosine)
                    margins.append(abs(abs(angle) - threshold))
                    if abs(angle) > threshold or abs(anchor - at) > 100:
                        n += 1
                        anchor = at
                        forward = next_forward^
            var known = False
            for index in range(len(ids)):
                if ids[index] == id:
                    counts[index] = n
                    known = True
            if not known:
                ids.append(id)
                counts.append(n)
            count += n
        return (count, ids^, counts^)


def report(text: String) raises -> String:
    """Return the JSON report for an OpenDRIVE town.

    Args:
        text: The OpenDRIVE text.

    Returns:
        The report as `json.dumps(indent=2)` writes it, with a final
        newline.

    Raises:
        Error: If the XML is malformed, an attribute is not a number, or a
            road lacks a record that the controls need.
    """
    var oracle = Oracle(parse_xml(text))
    var root = oracle.document.root()
    var road_ids = List[Int]()
    var road_nodes = List[Int]()
    for road in oracle.document.children_named(root, "road"):
        var id = Int(oracle.document.attribute(road, "id"))
        var known = False
        for index in range(len(road_ids)):
            if road_ids[index] == id:
                road_nodes[index] = road
                known = True
        if not known:
            road_ids.append(id)
            road_nodes.append(road)
    var writer = JsonWriter()
    writer.begin_object()
    writer.key("orientation_controls")
    writer.begin_array()
    var cases: List[Tuple[Int, Int, Int, Int]] = [
        (1, 1, -1, 50),
        (5, 0, -1, 10),
        (5, 0, 1, 40),
        (5, 0, -2, 50),
    ]
    for control in cases:
        var road = -1
        for index in range(len(road_ids)):
            if road_ids[index] == control[0]:
                road = road_nodes[index]
        if road < 0:
            raise Error("KeyError: " + String(control[0]))
        var section = _find_all(oracle.document, road, "lanes", "laneSection")[
            control[1]
        ]
        var result = oracle.tangent(
            road, section, control[2], Float64(control[3])
        )
        writer.begin_object()
        writer.key("road")
        writer.integer(control[0])
        writer.key("section")
        writer.integer(control[1])
        writer.key("lane")
        writer.integer(control[2])
        writer.key("s")
        writer.integer(control[3])
        writer.key("yaw")
        writer.number(result[0])
        writer.key("pitch")
        writer.number(result[1])
        writer.key("forward")
        writer.begin_array()
        for value in result[2]:
            writer.number(value)
        writer.end()
        writer.end()
    writer.end()
    var total = 0
    var margins = List[Float64]()
    var keys = List[String]()
    var tables = List[Tuple[List[Int], List[Int]]]()
    for index in range(len(road_ids)):
        var road = road_nodes[index]
        var sections = _find_all(oracle.document, road, "lanes", "laneSection")
        for i in range(len(sections)):
            var end: Float64
            if i + 1 < len(sections):
                end = _number(oracle.document, sections[i + 1], "s", "")
            else:
                end = _number(oracle.document, road, "length", "")
            var start = _number(oracle.document, sections[i], "s", "")
            var counted = oracle.segment_count(
                road, sections[i], end - start, margins
            )
            total += counted[0]
            var key = String(road_ids[index]) + "/" + String(i)
            var known = False
            for k in range(len(keys)):
                if keys[k] == key:
                    tables[k] = (counted[1].copy(), counted[2].copy())
                    known = True
            if not known:
                keys.append(key)
                tables.append((counted[1].copy(), counted[2].copy()))
    writer.key("segment_count")
    writer.integer(total)
    writer.key("segments_by_road_section_lane")
    writer.begin_object()
    for k in range(len(keys)):
        writer.key(keys[k])
        writer.begin_object()
        ref table = tables[k]
        for lane in range(len(table[0])):
            writer.key(String(table[0][lane]))
            writer.integer(table[1][lane])
        writer.end()
    writer.end()
    writer.key("heading_threshold_decisions")
    writer.integer(len(margins))
    if len(margins) == 0:
        raise Error("min() arg is an empty sequence")
    var smallest = margins[0]
    for margin in margins:
        if margin < smallest:
            smallest = margin
    writer.key("minimum_threshold_margin_radians")
    writer.number(smallest)
    writer.end()
    return writer.text() + "\n"


def run(root: String) raises -> String:
    """Read the town fixture below a root and return the report.

    Args:
        root: The repository root.

    Returns:
        The JSON report with a final newline.

    Raises:
        Error: If the town cannot be read, or `report` fails.
    """
    return report(Path(root + "/" + TOWN).read_text())


def main():
    """Print the report for the town in the current directory."""
    try:
        print(run("."), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
