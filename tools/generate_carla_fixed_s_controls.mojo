# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Generate independent fixed-s lane answers from captured geometry seed bits.

    generate_carla_fixed_s_controls CAPTURE [--json PATH] [--check]

writes `tests/test_carla_fixed_s_fraction.mojo`. CAPTURE is the output of
`tools/capture_carla_fixed_s_controls.mojo`, built with the pinned
compiler. The output needs no compiler or formatter. Use `--check` for an
exact, read-only replay of the saved fixture. Do not combine `--check` and
`--json`.

Only the reference point and the sine and cosine seeds come from the
capture. This tool does each Float64 lane-center operation on its own, and
exact rational arithmetic compares the stored points. It reads no
`nearest_lane` result. Each product is rounded before a sum uses it, as in
the Python generator that this tool replaces.
"""

from std.benchmark import black_box
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._bigint import BigInt
from tools._carla_controls import (
    deliver,
    float_bits,
    from_bits,
    hex_word,
    parse_options,
    write_report,
)
from tools._fraction import Fraction
from tools._json_tools import JsonWriter
from tools._text import split_lines


comptime PROGRAM = "generate_carla_fixed_s_controls"
"""The program name in the usage line."""

comptime DESCRIPTION = (
    "Generate independent fixed-s lane answers from captured geometry seed"
    " bits."
)
"""The help description."""

comptime FIXTURE = "tests/test_carla_fixed_s_fraction.mojo"
"""The fixture path below the repository root."""

comptime CASES = 135
"""The number of cases: 45 captured geometries and three queries each."""

comptime HEADER = (
    "# Copyright (c) 2026 Seth Kitchen, PE\n"
    "# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0\n"
    "# Noncommercial use is free; commercial use requires a paid license.\n"
    "# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.\n"
    "\n"
    '"""Generated stored-input Fraction controls for all five geometry'
    ' kinds."""\n'
    "\n"
    "from extensions.carla.polynomial import CubicPolynomial\n"
    "from extensions.carla.road_info import RoadInfoGeometry,"
    " RoadInfoLaneOffset\n"
    "from math.vector3 import Vector3\n"
    "from std.memory import bitcast\n"
    "from std.testing import TestSuite, assert_equal, assert_true\n"
    "from tests.carla_fixed_s_fixture import _fixed_geometry\n"
    "from tests.test_carla_road_fixed_s import _lane, _road\n"
    "\n"
    "\n"
    "def test_all_geometry_kinds_against_fraction_centers() raises:\n"
    "    # kind, origin/heading/query bits, expected lane, upper exact norm.\n"
    "    var cases: List[Tuple[Int, Array[UInt64, 5], Int, UInt64]] = [\n"
)
"""The fixture text before the cases."""

comptime FOOTER = (
    "    ]\n"
    "    for i in range(len(cases)):\n"
    "        ref row = cases[i]\n"
    "        var origin = bitcast[DType.float64](row[1][0])\n"
    "        var heading = bitcast[DType.float64](row[1][1])\n"
    "        var road = _road(z=1.25)\n"
    "        road.info.geometries[0] = RoadInfoGeometry._from_si(\n"
    "            0.0, _fixed_geometry(row[0], origin, heading)\n"
    "        )\n"
    "        road.info.lane_offsets.append(\n"
    "            RoadInfoLaneOffset._from_si(\n"
    "                0.0, CubicPolynomial._constant_si(0.375)\n"
    "            )\n"
    "        )\n"
    "        _lane(road, 0, -2, 3.0)\n"
    "        _lane(road, 0, 2, 4.0)\n"
    "        var query = Vector3(\n"
    "            Float32(bitcast[DType.float64](row[1][2])),\n"
    "            Float32(bitcast[DType.float64](row[1][3])),\n"
    "            Float32(bitcast[DType.float64](row[1][4])),\n"
    "        )\n"
    "        var result = road.nearest_lane_meters(3.25, query)\n"
    "        assert_equal(result[0].value().lane_id.value, row[2])\n"
    "        assert_true(result[1] >= bitcast[DType.float64](row[3] -"
    " UInt64(5)))\n"
    "        assert_true(result[1] <= bitcast[DType.float64](row[3] +"
    " UInt64(4)))\n"
    "\n"
    "\n"
    "def main() raises:\n"
    "    TestSuite.discover_tests[__functions_in_module()]().run()\n"
)
"""The fixture text after the cases."""


@fieldwise_init
struct Case(Copyable, Movable):
    """One control: a geometry, a query and the exact answer."""

    var kind: Int
    """The geometry kind."""
    var origin_bits: UInt64
    """The bits of the geometry origin."""
    var heading_bits: UInt64
    """The bits of the geometry heading."""
    var query_bits: List[UInt64]
    """The bits of the Float32 query point, widened to Float64."""
    var winner: Int
    """The lane id of the nearest center; the last of equal ones wins."""
    var radius_bits: UInt64
    """The bits of the least double whose square is at least the gap."""
    var lanes: List[Int]
    """The lane id of each center."""
    var center_bits: List[List[UInt64]]
    """The bits of each lane center."""


def _m(a: Float64, b: Float64) -> Float64:
    """Return a product rounded on its own, before a sum uses it."""
    return black_box(a * b)


def _f32(value: Float64) raises -> Float64:
    """Round to Float32 as `struct.pack('>f')` does."""
    var rounded = Float64(Float32(value))
    if rounded - rounded != 0 and value - value == 0:
        raise Error("float too large to pack with f format")
    return rounded


def _square(point: List[Float64], query: List[Float64]) raises -> Fraction:
    """Return the exact squared distance between two stored points."""
    var total = Fraction(0)
    for axis in range(3):
        var difference = Fraction.from_float(point[axis]) - Fraction.from_float(
            query[axis]
        )
        total = total + difference * difference
    return total^


def upper_radius_bits(value: Fraction) raises -> UInt64:
    """Find the least finite double upper radius by exact bisection.

    Args:
        value: A nonnegative rational square.

    Returns:
        The least bits, up to those of the largest finite double, whose
        double squared is at least the value.

    Raises:
        Error: If the exact arithmetic fails, which it must not.
    """
    var low = UInt64(0)
    var high = UInt64(0x7FEFFFFFFFFFFFFF)
    while low < high:
        var middle = (low + high) // 2
        var root = Fraction.from_float(from_bits(middle))
        if root * root >= value:
            high = middle
        else:
            low = middle + 1
    return low


def _word(token: String) raises -> UInt64:
    """Return a decimal capture word that must fit in 64 bits."""
    var value = BigInt.parse(token)
    if value < BigInt(0) or value.bit_length() > 64:
        raise Error("argument out of range: " + token)
    var high = value >> 32
    var low = value - (high << 32)
    return (UInt64(high.to_int()) << 32) | UInt64(low.to_int())


def cases(capture: String) raises -> List[Case]:
    """Return the controls of a capture.

    Args:
        capture: The capture text: per line, a kind and six decimal words.

    Returns:
        Three queries of each captured geometry.

    Raises:
        Error: If a line does not hold seven integers, or the capture does
            not give 135 cases.
    """
    var rows = List[Case]()
    for line in split_lines(capture):
        var tokens = line.split()
        if len(tokens) != 7:
            raise Error("expected 7 values in capture line: " + line)
        var kind = BigInt.parse(String(tokens[0])).to_int()
        var origin_bits = _word(String(tokens[1]))
        var heading_bits = _word(String(tokens[2]))
        var x = from_bits(_word(String(tokens[3])))
        var y = from_bits(_word(String(tokens[4])))
        var sn = from_bits(_word(String(tokens[5])))
        var cs = from_bits(_word(String(tokens[6])))
        var zero_x = x - _m(0.375, sn)
        var zero_y = y + _m(0.375, cs)
        var lanes = List[Int]()
        var centers = List[List[Float64]]()
        for side in [-1, 1]:
            var cx = zero_x
            var cy = zero_y
            var widths: List[Float64] = [2.0, 3.0] if side < 0 else [2.0, 4.0]
            for index in range(len(widths)):
                var half = Float64(-side) * widths[index] * 0.5
                cx = cx + _m(half, sn)
                cy = cy - _m(half, cs)
                lanes.append(side * (index + 1))
                centers.append([cx, cy, 1.25])
                cx = cx + _m(half, sn)
                cy = cy - _m(half, cs)
        var offsets: List[List[Float64]] = [
            [-5.0, -1.0, 0.75],
            [0.0, 0.0, 0.0],
            [4.0, -5.0, -1.25],
        ]
        for offset in offsets:
            var query: List[Float64] = [
                _f32(x + offset[0]),
                _f32(y + offset[1]),
                _f32(offset[2]),
            ]
            var best = lanes[0]
            var gap = _square(centers[0], query)
            for index in range(1, len(lanes)):
                var candidate = _square(centers[index], query)
                if candidate <= gap:
                    best = lanes[index]
                    gap = candidate^
            var query_bits = List[UInt64]()
            for value in query:
                query_bits.append(float_bits(value))
            var center_bits = List[List[UInt64]]()
            for center in centers:
                center_bits.append(
                    [
                        float_bits(center[0]),
                        float_bits(center[1]),
                        float_bits(center[2]),
                    ]
                )
            rows.append(
                Case(
                    kind,
                    origin_bits,
                    heading_bits,
                    query_bits^,
                    best,
                    upper_radius_bits(gap),
                    lanes.copy(),
                    center_bits^,
                )
            )
    if len(rows) != CASES:
        raise Error(
            "expected "
            + String(CASES)
            + " cases, but the capture gives "
            + String(len(rows))
        )
    return rows^


def fixture(rows: List[Case]) -> String:
    """Return the fixture text.

    Args:
        rows: The controls.

    Returns:
        The formatted test module, byte for byte.
    """
    var out = String(HEADER)
    for row in rows:
        var words: List[UInt64] = [row.origin_bits, row.heading_bits]
        words.extend(row.query_bits.copy())
        out += "        (\n            " + String(row.kind) + ",\n"
        out += "            [\n"
        for raw in words:
            out += "                UInt64(0x" + hex_word(raw) + "),\n"
        out += (
            "            ],\n            "
            + String(row.winner)
            + ",\n            UInt64(0x"
            + hex_word(row.radius_bits)
            + "),\n        ),\n"
        )
    out += FOOTER
    return out^


def report(rows: List[Case]) -> String:
    """Return the review report, as `json.dumps(rows, indent=2)` writes it.

    Args:
        rows: The controls.

    Returns:
        The JSON text with a final newline.
    """
    var writer = JsonWriter()
    writer.begin_array()
    for row in rows:
        writer.begin_object()
        writer.key("kind")
        writer.integer(row.kind)
        writer.key("origin_bits")
        writer.unsigned(row.origin_bits)
        writer.key("heading_bits")
        writer.unsigned(row.heading_bits)
        writer.key("query_bits")
        writer.begin_array()
        for raw in row.query_bits:
            writer.unsigned(raw)
        writer.end()
        writer.key("winner")
        writer.integer(row.winner)
        writer.key("radius_bits")
        writer.unsigned(row.radius_bits)
        writer.key("center_bits")
        writer.begin_array()
        for index in range(len(row.lanes)):
            writer.begin_array()
            writer.integer(row.lanes[index])
            writer.begin_array()
            for raw in row.center_bits[index]:
                writer.unsigned(raw)
            writer.end()
            writer.end()
        writer.end()
        writer.end()
    writer.end()
    return writer.text() + "\n"


def run(root: String, arguments: List[String]) raises -> Tuple[Int, String]:
    """Write or check the fixture from a capture, then write the report.

    Args:
        root: The repository root.
        arguments: The command-line arguments, without the program name.

    Returns:
        The exit status and the text to print.

    Raises:
        Error: If the exact arithmetic fails, which it must not.
    """
    var options = parse_options(PROGRAM, DESCRIPTION, arguments, "capture")
    if options.status != 0:
        return (max(options.status, 0), options.message)
    var rows: List[Case]
    try:
        rows = cases(Path(options.positional).read_text())
    except error:
        return (
            1,
            "Cannot read " + options.positional + ": " + String(error) + "\n",
        )
    if options.has_json:
        var written = write_report(options.json, report(rows))
        if written[0] != 0:
            return written
    var delivered = deliver(root, FIXTURE, fixture(rows), options.check)
    if delivered[0] != 0:
        return delivered
    return (
        0,
        ("Verified " if options.check else "Generated ")
        + String(len(rows))
        + " independent fixed-s Fraction cases\n",
    )


def main() raises:
    """Run from the repository root and exit with the status.

    Raises:
        Error: If the exact arithmetic fails, which it must not.
    """
    var given = argv()
    var arguments = List[String]()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    var outcome = run(".", arguments)
    if outcome[0] == 0:
        print(outcome[1], end="")
    else:
        print(outcome[1], end="", file=stderr)
    exit(outcome[0])
