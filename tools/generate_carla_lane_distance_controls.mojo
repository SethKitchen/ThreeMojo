# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Generate binary-Float64 point controls with independent Fraction arithmetic.

    generate_carla_lane_distance_controls [--json PATH] [--check]

writes `tests/test_carla_lane_distance_fraction.mojo`. The output needs no
compiler or formatter. Use `--check` for an exact, read-only replay of the
saved fixture. The optional `--json` path keeps the labels and the exact
input bits for review. Do not combine `--check` and `--json`.

The cases are those of the Python generator that this tool replaces: the
random bits come from `random.Random(594302)`.
"""

from std.sys import argv, exit, stderr

from tools._bigint import BigInt
from tools._carla_controls import (
    deliver,
    exact,
    float_bits,
    hex_word,
    parse_options,
    power_of_two,
    write_report,
)
from tools._fraction import Fraction
from tools._json_tools import JsonWriter
from tools._python_random import PythonRandom


comptime PROGRAM = "generate_carla_lane_distance_controls"
"""The program name in the usage line."""

comptime DESCRIPTION = (
    "Generate binary-Float64 point controls with independent Fraction"
    " arithmetic."
)
"""The help description."""

comptime FIXTURE = "tests/test_carla_lane_distance_fraction.mojo"
"""The fixture path below the repository root."""

comptime HEADER = (
    "# Copyright (c) 2026 Seth Kitchen, PE\n"
    "# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0\n"
    "# Noncommercial use is free; commercial use requires a paid license.\n"
    "# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.\n"
    "\n"
    "from extensions.carla.curve_distance import (\n"
    "    _wide_point_order,\n"
    "    _exact_point_order,\n"
    ")\n"
    "from extensions.carla.lane_distance import (\n"
    "    _wide_plan_contains,\n"
    "    _exact_plan_width,\n"
    "    _wide_distance_upper,\n"
    ")\n"
    "from std.memory import bitcast\n"
    "from std.testing import TestSuite, assert_equal, assert_true\n"
    "\n"
    "\n"
    "def test_fraction_bit_corpus() raises:\n"
    "    var cases: List[Tuple[Array[UInt64, 10], Int, Int, UInt64]] = [\n"
)
"""The fixture text before the cases."""

comptime FOOTER = (
    "    ]\n"
    "    for i in range(len(cases)):\n"
    "        ref row = cases[i]\n"
    "        var a = Array[Float64, 3](fill=0)\n"
    "        var b = Array[Float64, 3](fill=0)\n"
    "        var q = Array[Float64, 3](fill=0)\n"
    "        for axis in range(3):\n"
    "            a[axis] = bitcast[DType.float64](row[0][axis])\n"
    "            b[axis] = bitcast[DType.float64](row[0][axis + 3])\n"
    "            q[axis] = bitcast[DType.float64](row[0][axis + 6])\n"
    "        var width = bitcast[DType.float64](row[0][9])\n"
    "        assert_equal(_wide_point_order(a, b, q), row[1])\n"
    "        assert_equal(_exact_point_order(a, b, q), row[1])\n"
    "        assert_equal(_wide_plan_contains(a, q, width), row[2] < 0)\n"
    "        assert_equal(_exact_plan_width(a, q, width), row[2])\n"
    "        assert_true(\n"
    "            _wide_distance_upper(a, q) >= bitcast[DType.float64](row[3])\n"
    "        )\n"
    "\n"
    "\n"
    "def main() raises:\n"
    "    TestSuite.discover_tests[__functions_in_module()]().run()\n"
)
"""The fixture text after the cases."""


@fieldwise_init
struct Row(Copyable, Movable):
    """One point control."""

    var bits: List[UInt64]
    """The bits of a, b and the query point, then the width."""
    var order: Int
    """The sign of |a - q|^2 - |b - q|^2."""
    var width_sign: Int
    """The sign of 4 |a - q|_xy^2 - width^2."""
    var label: String
    """The case name."""
    var upper_radius_bits: UInt64
    """The least nonnegative double at least |a - q|."""


def sign(value: Fraction) -> Int:
    """Return -1, 0 or 1 as the value is negative, zero or positive.

    Args:
        value: The value.

    Returns:
        The sign.
    """
    return value.compare(Fraction(0))


def square_at_least(raw: UInt64, square: Fraction) raises -> Bool:
    """Return whether a nonnegative double's square is at least a dyadic
    rational, with integer arithmetic only.

    Args:
        raw: The bits of a finite, nonnegative double.
        square: A nonnegative rational with a power-of-two denominator.

    Returns:
        True when value * value >= square.

    Raises:
        Error: If the denominator is not a power of two.
    """
    var scale = square.denominator.bit_length() - 1
    if square.denominator.trailing_zeros() != scale:
        raise Error("not a dyadic rational")
    var field = Int(raw >> 52)
    var significand = Int(raw & 0xFFFFFFFFFFFFF)
    if field != 0:
        significand |= 1 << 52
    var power = 2 * (max(field, 1) - 1075) + scale
    var root = BigInt(significand)
    var product = root * root
    if power >= 0:
        return (product << power) >= square.numerator
    return product >= (square.numerator << -power)


def upper_radius_bits(square: Fraction) raises -> UInt64:
    """Find the least nonnegative double whose square is at least a value.

    Args:
        square: A nonnegative dyadic rational.

    Returns:
        The double's bits, found by exact bisection.

    Raises:
        Error: If the value is not dyadic.
    """
    var low = UInt64(0)
    var high = UInt64(0x7FF0000000000000)
    while low < high:
        var middle = (low + high) // 2
        if square_at_least(middle, square):
            high = middle
        else:
            low = middle + 1
    return low


def _squared_distance(
    point: List[Fraction], query: List[Fraction], axes: Int
) raises -> Fraction:
    """Return the squared distance over the first axes."""
    var total = Fraction(0)
    for axis in range(axes):
        var difference = point[axis] - query[axis]
        total = total + difference * difference
    return total^


def _exact_point(raw: List[UInt64]) raises -> List[Fraction]:
    """Decode a point's bits."""
    var point = List[Fraction]()
    for word in raw:
        point.append(exact(word))
    return point^


def _add(
    mut rows: List[Row],
    a: List[UInt64],
    b: List[UInt64],
    query: List[UInt64],
    width: UInt64,
    label: String,
) raises:
    """Add one control."""
    var fa = _exact_point(a)
    var fb = _exact_point(b)
    var fq = _exact_point(query)
    var da = _squared_distance(fa, fq, 3)
    var db = _squared_distance(fb, fq, 3)
    var plan = Fraction(4) * _squared_distance(fa, fq, 2)
    var w = exact(width)
    var bits = a.copy()
    bits.extend(b.copy())
    bits.extend(query.copy())
    bits.append(width)
    rows.append(
        Row(
            bits^,
            sign(da - db),
            sign(plan - w * w),
            label,
            upper_radius_bits(da),
        )
    )


def _random_bits(mut source: PythonRandom) -> UInt64:
    """Draw a double's bits with an exponent from a fixed list."""
    var exponents: List[UInt64] = [
        0,
        1,
        2,
        20,
        500,
        970,
        1022,
        1023,
        1024,
        1074,
        1500,
        2000,
        2045,
        2046,
    ]
    var exponent = exponents[source.choice(len(exponents))]
    var top = UInt64(source.getrandbits(1).to_int_unchecked())
    var low = UInt64(source.getrandbits(52).to_int_unchecked())
    return (top << 63) | (exponent << 52) | low


def _random_point(mut source: PythonRandom) -> List[UInt64]:
    """Draw three coordinates in order."""
    var point = List[UInt64]()
    for _ in range(3):
        point.append(_random_bits(source))
    return point^


def cases() raises -> List[Row]:
    """Return the 100 controls.

    Returns:
        The broad random cases, the equal-norm cases and the carry ties.

    Raises:
        Error: If the exact arithmetic fails, which it must not.
    """
    var source = PythonRandom(594302)
    var rows = List[Row]()
    for index in range(64):
        var a = _random_point(source)
        var b = _random_point(source)
        var query = _random_point(source)
        var width = _random_bits(source) & ((UInt64(1) << 63) - 1)
        _add(rows, a, b, query, width, "broad_" + String(index))
    for shift in [-1000, -700, -500, -200, 0, 200, 500, 700, 1000]:
        var scale = power_of_two(shift)
        for perturbation in [0, 1, -1]:
            var query = UInt64(0) if perturbation == 0 else (
                UInt64(1) if perturbation > 0 else (UInt64(1) << 63) | 1
            )
            _add(
                rows,
                [float_bits(3 * scale), float_bits(4 * scale), 0],
                [0, float_bits(5 * scale), 0],
                [0, query, 0],
                float_bits(10 * scale),
                "equinorm_" + String(shift) + "_" + String(perturbation),
            )
    var fields: List[UInt64] = [0, 1, 1023, 2046]
    for index in range(9):
        var x = (fields[source.choice(4)] << 52) | ((UInt64(1) << 52) - 1)
        var flipped = x ^ (UInt64(1) << 63)
        _add(
            rows,
            [x, x, x],
            [flipped, flipped, flipped],
            [UInt64(1) << 63, 0, 0],
            x,
            "carry_tie_" + String(index),
        )
    return rows^


def fixture(rows: List[Row]) -> String:
    """Return the fixture text.

    Args:
        rows: The controls.

    Returns:
        The test module, byte for byte.
    """
    var out = String(HEADER)
    for row in rows:
        out += "        (\n            [\n"
        for raw in row.bits:
            out += "                UInt64(0x" + hex_word(raw) + "),\n"
        out += (
            "            ],\n            "
            + String(row.order)
            + ",\n            "
            + String(row.width_sign)
            + ",\n            UInt64(0x"
            + hex_word(row.upper_radius_bits)
            + "),\n        ),\n"
        )
    out += FOOTER
    return out^


def report(rows: List[Row]) -> String:
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
        writer.key("bits")
        writer.begin_array()
        for raw in row.bits:
            writer.unsigned(raw)
        writer.end()
        writer.key("order")
        writer.integer(row.order)
        writer.key("width_sign")
        writer.integer(row.width_sign)
        writer.key("label")
        writer.string(row.label)
        writer.key("upper_radius_bits")
        writer.unsigned(row.upper_radius_bits)
        writer.end()
    writer.end()
    return writer.text() + "\n"


def run(root: String, arguments: List[String]) raises -> Tuple[Int, String]:
    """Write or check the fixture, and write the optional report.

    Args:
        root: The repository root.
        arguments: The command-line arguments, without the program name.

    Returns:
        The exit status and the text to print.

    Raises:
        Error: If the exact arithmetic fails, which it must not.
    """
    var options = parse_options(PROGRAM, DESCRIPTION, arguments)
    if options.status != 0:
        return (max(options.status, 0), options.message)
    var rows = cases()
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
        + " independent Fraction cases\n",
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
