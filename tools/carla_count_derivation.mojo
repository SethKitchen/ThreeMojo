# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Derive the town lane counts and the gentle-circle leaf counts.

It reads `assets/carla/town.xodr`, writes `count-derivation.json`, and
prints the count summary. It does not run a native suite.

    mojo run -I . tools/carla_count_derivation.mojo

`CARLA_LANE_ORACLE_OUTPUT` chooses the output directory. The default is
`out/carla-lane-oracle` under the repository.
"""

from std.math import ceil
from std.os import getenv
from std.os.path import realpath
from std.pathlib import Path
from std.sys import argv

from tools._bigint import BigInt
from tools._fraction import Fraction
from tools._process import run_program
from tools._python_float import parse_float, python_repr
from tools._sha256 import sha256_hex


struct Tag(Movable):
    """One XML tag."""

    var closing: Bool
    """True for an end tag."""
    var name: String
    """The element name."""
    var self_closing: Bool
    """True when the start tag ends with `/>`."""
    var names: List[String]
    """Attribute names, in document order."""
    var values: List[String]
    """Attribute values, paired with `names`."""
    var next: Int
    """The byte index after the tag."""

    def __init__(out self):
        """Start an empty tag."""
        self.closing = False
        self.name = String()
        self.self_closing = False
        self.names = List[String]()
        self.values = List[String]()
        self.next = 0


def _attribute(tag: Tag, name: String) raises -> String:
    """Return one attribute.

    Args:
        tag: The tag.
        name: The attribute name.

    Returns:
        The attribute value.

    Raises:
        Error: If the attribute is absent.
    """
    for index in range(len(tag.names)):
        if tag.names[index] == name:
            return tag.values[index]
    raise Error("missing attribute " + name)


def _skip_until(text: String, at: Int, marker: String) raises -> Int:
    """Return the index after `marker`.

    Args:
        text: The document.
        at: The start of the search.
        marker: The closing marker.

    Returns:
        The index after the marker.

    Raises:
        Error: If the marker is absent.
    """
    var rest = String(text[byte=at:])
    var found = rest.find(marker)
    if found < 0:
        raise Error("unclosed XML marker")
    return at + found + marker.byte_length()


def _name_at(text: String, at: Int) -> Int:
    """Return the end of an XML name.

    Args:
        text: The document.
        at: The first name byte.

    Returns:
        The index after the name.
    """
    var bytes = text.as_bytes()
    var index = at
    while index < len(bytes):
        var byte = bytes[index]
        var ok = (
            (byte >= 0x41 and byte <= 0x5A)
            or (byte >= 0x61 and byte <= 0x7A)
            or (byte >= 0x30 and byte <= 0x39)
            or byte == 0x5F
            or byte == 0x2D
            or byte == 0x3A
            or byte == 0x2E
        )
        if not ok:
            break
        index += 1
    return index


def _read_tag(text: String, at: Int) raises -> Tag:
    """Read the tag that starts at `at`.

    Args:
        text: The document.
        at: The `<` byte.

    Returns:
        The tag.

    Raises:
        Error: If the tag is truncated or an attribute has no value.
    """
    var bytes = text.as_bytes()
    var tag = Tag()
    var index = at + 1
    if index < len(bytes) and bytes[index] == 0x2F:
        tag.closing = True
        index += 1
    var name_end = _name_at(text, index)
    tag.name = String(text[byte=index:name_end])
    index = name_end
    while index < len(bytes) and bytes[index] != 0x3E:
        var byte = bytes[index]
        if byte == 0x2F:
            tag.self_closing = True
            index += 1
            continue
        if (
            (byte >= 0x41 and byte <= 0x5A)
            or (byte >= 0x61 and byte <= 0x7A)
            or byte == 0x5F
        ):
            var attr_end = _name_at(text, index)
            var attr = String(text[byte=index:attr_end])
            index = attr_end
            while index < len(bytes) and (
                bytes[index] == 0x20 or bytes[index] == 0x09
            ):
                index += 1
            if index >= len(bytes) or bytes[index] != 0x3D:
                raise Error("attribute has no value")
            index += 1
            while index < len(bytes) and (
                bytes[index] == 0x20 or bytes[index] == 0x09
            ):
                index += 1
            if index >= len(bytes):
                raise Error("attribute has no value")
            var quote = bytes[index]
            index += 1
            var value_end = index
            while value_end < len(bytes) and bytes[value_end] != quote:
                value_end += 1
            tag.names.append(attr)
            tag.values.append(String(text[byte=index:value_end]))
            index = value_end + 1
            continue
        index += 1
    if index >= len(bytes):
        raise Error("truncated XML tag")
    tag.next = index + 1
    return tag^


def _parent(stack: List[String]) -> String:
    """Return the open element, or empty at the root.

    Args:
        stack: The open element names.

    Returns:
        The current parent name.
    """
    if len(stack) == 0:
        return String()
    return stack[len(stack) - 1]


def _sort_roads(
    ids: List[Int],
) -> List[Int]:
    """Return road indexes in increasing id order.

    Args:
        ids: Each road id.

    Returns:
        The indexes.
    """
    var order = List[Int]()
    for index in range(len(ids)):
        var place = 0
        while place < len(order) and ids[order[place]] < ids[index]:
            place += 1
        # Insert by rebuilding. The town has few roads.
        var next = List[Int]()
        for earlier in range(place):
            next.append(order[earlier])
        next.append(index)
        for later in range(place, len(order)):
            next.append(order[later])
        order = next^
    return order^


def _lane_order(ids: List[Int], start: Int, count: Int) -> List[Int]:
    """Return lane slots in increasing id order.

    Args:
        ids: Every lane id.
        start: The first lane of this section.
        count: The number of lanes.

    Returns:
        Indexes into `ids`.
    """
    var order = List[Int]()
    for offset in range(count):
        var index = start + offset
        var place = 0
        while place < len(order) and ids[order[place]] < ids[index]:
            place += 1
        var next = List[Int]()
        for earlier in range(place):
            next.append(order[earlier])
        next.append(index)
        for later in range(place, len(order)):
            next.append(order[later])
        order = next^
    return order^


def _sagitta(span: Float64) raises -> Tuple[Float64, Float64]:
    """Return the lower and upper sagitta of a gentle circular span.

    Args:
        span: The span in meters.

    Returns:
        The lower and upper bounds, as `float(Fraction)` writes them.

    Raises:
        Error: If the span is outside the proved positive range.
    """
    var k = Fraction.from_float(0.000001)
    var radius = Fraction.from_float(1.0 / 0.000001) + Fraction.of(
        BigInt(7), BigInt(4)
    )
    var x = k * Fraction.from_float(span) / Fraction(4)
    if not (Fraction(0) < x and x < Fraction.of(BigInt(1), BigInt(10000))):
        raise Error("sagitta argument is outside the proved range")
    var cubed = x.__pow__(3)
    var inner = x - cubed / Fraction(6)
    var lower = Fraction(2) * radius * (inner * inner)
    var upper = Fraction(2) * radius * x * x
    return (lower.to_float(), upper.to_float())


struct Spans(Movable):
    """The gentle-circle spans and their leaf counts."""

    var low: List[Float64]
    """Each span's low s."""
    var high: List[Float64]
    """Each span's high s."""
    var leaves: List[Int]
    """The leaf count of each span."""
    var total: Int
    """The sum of the leaf counts."""

    def __init__(out self):
        """Start with no spans."""
        self.low = List[Float64]()
        self.high = List[Float64]()
        self.leaves = List[Int]()
        self.total = 0


def _spans() raises -> Spans:
    """Return the 250 m gentle-circle spans.

    Returns:
        Three spans whose leaves sum to 5.

    Raises:
        Error: If a sagitta bound or the leaf total disagrees.
    """
    var unit = parse_float("2.220446049250313e-16")
    var tiny = parse_float("0.000001")
    var eps = 10.0 * unit
    var position = 10.0 * eps
    var first = position
    var result = Spans()
    while True:
        var remaining = (250.0 - position) - tiny
        var step = 1.0 if 1.0 < remaining else remaining
        if step < tiny:
            result.low.append(first)
            result.high.append(position)
            break
        position = position + (step - eps)
        if (position - first) > 100.0:
            result.low.append(first)
            result.high.append(position)
            first = position
    for index in range(len(result.low)):
        var span = result.high[index] - result.low[index]
        var whole = _sagitta(span)
        var half = _sagitta(span / 2.0)
        var leaves = 1
        if whole[0] > 0.001:
            if not (half[1] < 0.001):
                raise Error("half span is not below the sagitta margin")
            leaves = 2
        elif not (whole[1] < 0.001):
            raise Error("whole span is not below the sagitta margin")
        result.leaves.append(leaves)
        result.total += leaves
    if result.total != 5:
        raise Error("gentle leaf count is not 5")
    return result^


struct Town(Movable):
    """The lane groups read from the town fixture."""

    var road_id: List[Int]
    """Each road id."""
    var road_length: List[Float64]
    """Each road length."""
    var section_road: List[Int]
    """The road index of each lane section."""
    var section_start: List[Float64]
    """The s of each lane section."""
    var section_lane_at: List[Int]
    """The first lane of each section."""
    var section_lane_count: List[Int]
    """The number of lanes in each section."""
    var lane_id: List[Int]
    """Each lane id."""
    var lane_side: List[String]
    """`left`, `center` or `right` for each lane."""
    var checked_widths: List[String]
    """The width records of road 1, section 1, right lane -1."""

    def __init__(out self):
        """Start with no roads."""
        self.road_id = List[Int]()
        self.road_length = List[Float64]()
        self.section_road = List[Int]()
        self.section_start = List[Float64]()
        self.section_lane_at = List[Int]()
        self.section_lane_count = List[Int]()
        self.lane_id = List[Int]()
        self.lane_side = List[String]()
        self.checked_widths = List[String]()


def _read_town(text: String) raises -> Town:
    """Return the lane groups in the OpenDRIVE document.

    Args:
        text: The town fixture.

    Returns:
        The roads, sections and lanes.

    Raises:
        Error: If a tag or a required attribute is missing.
    """
    var town = Town()
    var stack = List[String]()
    var road = -1
    var section = -1
    var side = String()
    var lane = -1
    var at = 0
    var size = text.byte_length()
    while at < size:
        var rest = String(text[byte=at:])
        var mark = rest.find("<")
        if mark < 0:
            break
        at += mark
        if _starts(text, at, "<!--"):
            at = _skip_until(text, at + 4, "-->")
            continue
        if _starts(text, at, "<![CDATA["):
            at = _skip_until(text, at + 9, "]]>")
            continue
        if _starts(text, at, "<?"):
            at = _skip_until(text, at + 2, "?>")
            continue
        var tag = _read_tag(text, at)
        at = tag.next
        if tag.closing:
            if len(stack) == 0 or stack[len(stack) - 1] != tag.name:
                raise Error("unmatched end tag " + tag.name)
            _ = stack.pop()
            if tag.name == "lane":
                lane = -1
            elif tag.name == "laneSection":
                if section >= 0:
                    town.section_lane_count[section] = (
                        len(town.lane_id) - town.section_lane_at[section]
                    )
                section = -1
            elif tag.name == "road":
                road = -1
            continue
        var parent = _parent(stack)
        if tag.name == "road" and parent == "OpenDRIVE":
            road = len(town.road_id)
            town.road_id.append(atol(_attribute(tag, "id")))
            town.road_length.append(parse_float(_attribute(tag, "length")))
        elif tag.name == "laneSection" and parent == "lanes" and road >= 0:
            section = len(town.section_start)
            town.section_road.append(road)
            town.section_start.append(parse_float(_attribute(tag, "s")))
            town.section_lane_at.append(len(town.lane_id))
            town.section_lane_count.append(0)
        elif (
            tag.name == "lane"
            and (parent == "left" or parent == "center" or parent == "right")
            and section >= 0
        ):
            lane = len(town.lane_id)
            side = parent
            town.lane_id.append(atol(_attribute(tag, "id")))
            town.lane_side.append(parent)
        elif tag.name == "width" and lane >= 0 and road >= 0 and section >= 0:
            var on_checked = (
                town.road_id[road] == 1
                and town.section_road[section] == road
                and _section_index(town, section) == 1
                and side == "right"
                and town.lane_id[lane] == -1
            )
            if on_checked:
                town.checked_widths.append(
                    _attribute(tag, "sOffset")
                    + "|"
                    + _attribute(tag, "a")
                    + "|"
                    + _attribute(tag, "b")
                    + "|"
                    + _attribute(tag, "c")
                    + "|"
                    + _attribute(tag, "d")
                )
        if not tag.self_closing and not tag.closing:
            stack.append(tag.name)
    if len(town.lane_id) == 0:
        raise Error("the town fixture has no lanes")
    return town^


def _starts(text: String, at: Int, prefix: String) -> Bool:
    """Return whether `text` at `at` begins with `prefix`.

    Args:
        text: The document.
        at: The byte index.
        prefix: The prefix.

    Returns:
        True when the prefix is present.
    """
    var end = at + prefix.byte_length()
    if end > text.byte_length():
        return False
    return String(text[byte=at:end]) == prefix


def _section_index(town: Town, section: Int) -> Int:
    """Return the section's index within its road.

    Args:
        town: The town.
        section: The section slot.

    Returns:
        The zero-based index among that road's sections.
    """
    var road = town.section_road[section]
    var count = 0
    for index in range(section):
        if town.section_road[index] == road:
            count += 1
    return count


@fieldwise_init
struct Report(Movable):
    """The JSON file and the printed summary."""

    var file: String
    """The report file, including its final newline."""
    var summary: String
    """The printed summary, including its final newline."""


struct _Json(Movable):
    """Python `json.dumps(..., indent=2)` for this report's shape."""

    var text: String
    """The text so far."""
    var first: List[Bool]
    """Whether the next item at each open level is the first."""

    def __init__(out self):
        """Start an empty document."""
        self.text = String()
        self.first = List[Bool]()

    def _indent(self) -> String:
        """Return the current indentation.

        Returns:
            Two spaces per open level.
        """
        var pad = String()
        for _ in range(len(self.first)):
            pad += "  "
        return pad

    def _break(mut self):
        """Write the separator before the next item."""
        var level = len(self.first) - 1
        if self.first[level]:
            self.first[level] = False
        else:
            self.text += ","
        self.text += "\n" + self._indent()

    def begin(mut self, mark: String):
        """Open an object or an array.

        Args:
            mark: `{` or `[`.
        """
        self.text += mark
        self.first.append(True)

    def end(mut self, mark: String):
        """Close an object or an array.

        Args:
            mark: `}` or `]`.
        """
        _ = self.first.pop()
        self.text += "\n" + self._indent() + mark

    def key(mut self, name: String):
        """Write an object key.

        Args:
            name: The key.
        """
        self._break()
        self.text += '"' + name + '": '

    def number(mut self, name: String, value: Int):
        """Write an integer field.

        Args:
            name: The key.
            value: The integer.
        """
        self.key(name)
        self.text += String(value)

    def flag(mut self, name: String, value: Bool):
        """Write a Boolean field.

        Args:
            name: The key.
            value: The Boolean.
        """
        self.key(name)
        self.text += "true" if value else "false"

    def string(mut self, name: String, value: String):
        """Write a string field.

        Args:
            name: The key.
            value: The text. It holds no controls or quotes.
        """
        self.key(name)
        self.text += '"' + value + '"'

    def float(mut self, name: String, value: Float64) raises:
        """Write a float field as Python writes it.

        Args:
            name: The key.
            value: The float.

        Raises:
            Error: If the value is not finite.
        """
        self.key(name)
        self.text += python_repr(value)

    def begin_key(mut self, name: String, mark: String):
        """Open a nested value after a key.

        Args:
            name: The key.
            mark: `{` or `[`.
        """
        self.key(name)
        self.begin(mark)


def _mesh_fields(mut json: _Json, rows: Int):
    """Write the mesh counts.

    Args:
        json: The writer.
        rows: The section-1 row count.
    """
    json.begin_key("mesh", "{")
    json.number("section0_vertices", 16)
    json.number("section1_rows", rows)
    json.number("section1_lane_vertices", 2 * rows)
    json.number("section1_lane_triangles", 2 * (rows - 1))
    json.number("section1_vertices", 4 * 2 * rows)
    json.number("road_vertices", 16 + 4 * 2 * rows)
    json.number("section1_with_walls_vertices", 6 * 2 * rows)
    json.number("joined_vertices", 4 + 2 * rows)
    json.number("joined_triangles", 2 + 2 * (rows - 1) + 2)
    json.number("appended_triangles", 2 + 2 * (rows - 1))
    json.end("}")


def _spans_json(mut json: _Json, spans: Spans) raises:
    """Write the gentle-circle spans.

    Args:
        json: The writer.
        spans: The spans.

    Raises:
        Error: If a float is not finite.
    """
    json.begin_key("gentle_base_spans", "[")
    for index in range(len(spans.low)):
        json._break()
        json.begin("{")
        json.float("low_s", spans.low[index])
        json.float("high_s", spans.high[index])
        json.float("span", spans.high[index] - spans.low[index])
        var whole = _sagitta(spans.high[index] - spans.low[index])
        var half = _sagitta((spans.high[index] - spans.low[index]) / 2.0)
        json.begin_key("whole_sagitta", "{")
        json.float("lower_m", whole[0])
        json.float("upper_m", whole[1])
        json.end("}")
        json.begin_key("half_sagitta", "{")
        json.float("lower_m", half[0])
        json.float("upper_m", half[1])
        json.end("}")
        json.number("leaves", spans.leaves[index])
        json.end("}")
    json.end("]")


def _lanes_json(mut json: _Json, town: Town) raises:
    """Write the town lane groups.

    Args:
        json: The writer.
        town: The town.

    Raises:
        Error: If a float is not finite.
    """
    json.begin_key("town_lane_groups", "[")
    var roads = _sort_roads(town.road_id)
    var groups = 0
    for road_slot in roads:
        var seen = 0
        for section in range(len(town.section_road)):
            if town.section_road[section] != road_slot:
                continue
            var end_s = town.road_length[road_slot]
            var following = section + 1
            while following < len(town.section_road):
                if town.section_road[following] == road_slot:
                    end_s = town.section_start[following]
                    break
                following += 1
            var lanes = _lane_order(
                town.lane_id,
                town.section_lane_at[section],
                town.section_lane_count[section],
            )
            for lane_slot in lanes:
                if town.lane_id[lane_slot] == 0:
                    continue
                json._break()
                json.begin("{")
                json.number("road", town.road_id[road_slot])
                json.number("section", seen)
                json.number("lane", town.lane_id[lane_slot])
                json.float("low_s", town.section_start[section])
                json.float("high_s", end_s)
                json.end("}")
                groups += 1
            seen += 1
    json.end("]")
    if groups != 26:
        raise Error("town lane group count is not 26")


def derive(root: String) raises -> Report:
    """Build the count report for the repository.

    Args:
        root: The repository root.

    Returns:
        The report file and the printed summary.

    Raises:
        Error: If the fixture, a bound, or a count disagrees.
    """
    var fixture = root + "/assets/carla/town.xodr"
    var raw = Path(fixture).read_bytes()
    var digest = sha256_hex(Span(raw))
    var text = String(from_utf8_lossy=raw)
    var spans = _spans()
    var town = _read_town(text)
    if (
        len(town.checked_widths) != 2
        or town.checked_widths[0] != "0|3.5|0|0|0"
        or town.checked_widths[1] != "10|3.5|0.05|0|0"
    ):
        raise Error("road 1 section 1 lane -1 widths changed")
    var rows = Int(ceil((60.0 - 30.0) / 2.0)) + 1
    if rows != 16:
        raise Error("section 1 row count is not 16")
    var full = _Json()
    full.begin("{")
    full.string("fixture_sha256", digest)
    full.flag("native_execution", False)
    _spans_json(full, spans)
    full.number("gentle_leaf_count", spans.total)
    full.string(
        "gentle_margin_note",
        (
            "Circle bounds are geometric justification with large margins, not"
            " a Float64 expression-graph certificate. Native"
            " expected-count/control checks remain required."
        ),
    )
    _lanes_json(full, town)
    full.number("town_lane_group_count", 26)
    full.begin_key("town_index_count", "{")
    full.number("value", 987)
    full.string(
        "basis",
        (
            "Retained native candidate observation; not independently"
            " recomputed here. New tests pair it with parameter coverage and"
            " cached enclosure sanity checks."
        ),
    )
    full.end("}")
    _mesh_fields(full, rows)
    full.end("}")
    var summary = _Json()
    summary.begin("{")
    _spans_json(summary, spans)
    summary.number("gentle_leaf_count", spans.total)
    summary.number("town_lane_group_count", 26)
    _mesh_fields(summary, rows)
    summary.end("}")
    return Report(full.text + "\n", summary.text + "\n")


def repository() raises -> String:
    """Return the repository that holds the town fixture.

    The search starts at the current directory and walks toward the root.

    Returns:
        The repository root.

    Raises:
        Error: If `assets/carla/town.xodr` is not found.
    """
    var directory = realpath(".")
    for _ in range(8):
        if Path(directory + "/assets/carla/town.xodr").exists():
            return directory
        var slash = directory.rfind("/")
        if slash <= 0:
            break
        var parent = String(directory[byte=:slash])
        directory = parent
    raise Error("cannot find assets/carla/town.xodr")


def main() raises:
    """Write the count report and print the summary.

    Raises:
        Error: If the fixture or a count disagrees.
    """
    if len(argv()) != 1:
        raise Error(
            "usage: carla_count_derivation\n"
            + "CARLA_LANE_ORACLE_OUTPUT chooses the output directory."
        )
    var root = repository()
    var output = getenv("CARLA_LANE_ORACLE_OUTPUT", "")
    if output.byte_length() == 0:
        output = root + "/out/carla-lane-oracle"
    var report = derive(root)
    _ = run_program(["mkdir", "-p", output], 10)
    Path(output + "/count-derivation.json").write_text(report.file)
    print(report.summary, end="")
