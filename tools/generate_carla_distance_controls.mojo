# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Generate binary-Float64 point controls with independent Fraction arithmetic.

    generate_carla_distance_controls [--json PATH] [--check]

writes `tests/test_carla_curve_distance_fraction.mojo`. The output needs no
compiler or formatter. Use `--check` for an exact, read-only replay of the
saved fixture. Do not combine `--check` and `--json`. The `--json` report
keeps the labels and the exact input bits for review.

The cases are those of the Python generator that this tool replaces: the
broad and carry cases come from `random.Random(594302)`. Each case holds
three stored points a, b and q. Exact rational squares give the sign of
|a - q|^2 - |b - q|^2, and an exact bisection gives the least double whose
square is at least |a - q|^2.
"""

from std.sys import argv, exit, stderr

from tools._carla_controls import (
    deliver,
    exact,
    float_bits,
    hex_word,
    parse_options,
    power_of_two,
    python_bool,
    write_report,
)
from tools._fraction import Fraction
from tools._json_tools import JsonWriter
from tools._python_random import PythonRandom


comptime PROGRAM = "generate_carla_distance_controls"
"""The program name in the usage line."""

comptime DESCRIPTION = (
    "Generate binary-Float64 point controls with independent Fraction"
    " arithmetic."
)
"""The help description."""

comptime FIXTURE = "tests/test_carla_curve_distance_fraction.mojo"
"""The fixture path below the repository root."""

comptime HEADER = (
    "# Copyright (c) 2026 Seth Kitchen, PE\n"
    "# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0\n"
    "# Noncommercial use is free; commercial use requires a paid license.\n"
    "# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.\n"
    "\n"
    '"""Independent Fraction controls for stored-point distance'
    ' arithmetic."""\n'
    "\n"
    "from extensions.carla.curve_distance import (\n"
    "    _wide_point_order,\n"
    "    _exact_point_order,\n"
    "    _wide_distance,\n"
    ")\n"
    "from std.memory import bitcast\n"
    "from std.testing import TestSuite, assert_equal, assert_true,"
    " assert_raises\n"
    "\n"
    "\n"
    "def test_fraction_bit_corpus() raises:\n"
    "    var cases: List[Tuple[Array[UInt64, 9], Int, Bool, Bool, UInt64]]"
    " = [\n"
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
    "        assert_equal(_wide_point_order(a, b, q), row[1])\n"
    "        assert_equal(_exact_point_order(a, b, q), row[1])\n"
    "        if row[2]:\n"
    '            with assert_raises(contains="Float64 range"):\n'
    "                _ = _wide_distance(a, q)\n"
    "        else:\n"
    "            var distance = _wide_distance(a, q)\n"
    "            assert_equal(distance > 0.0, row[3])\n"
    "            # Independent exact bisection gives a one-ULP norm bracket.\n"
    "            # Permit four more ULPs: this API promises an"
    " approximation.\n"
    "            var lower = UInt64(0)\n"
    "            if row[4] > UInt64(5):\n"
    "                lower = row[4] - UInt64(5)\n"
    "            var upper = min(row[4] + UInt64(4),"
    " UInt64(0x7FEFFFFFFFFFFFFF))\n"
    "            assert_true(distance >= bitcast[DType.float64](lower))\n"
    "            assert_true(distance <= bitcast[DType.float64](upper))\n"
    "\n"
    "\n"
    "def main() raises:\n"
    "    TestSuite.discover_tests[__functions_in_module()]().run()\n"
)
"""The fixture text after the cases."""

comptime LARGEST_FINITE = UInt64(0x7FEFFFFFFFFFFFFF)
"""The bits of the largest finite double."""

comptime INFINITY_BITS = UInt64(0x7FF0000000000000)
"""The bits of positive infinity."""


@fieldwise_init
struct Case(Copyable, Movable):
    """One control: nine input words and the exact answers."""

    var bits: List[UInt64]
    """The bits of a, b and q, three words each."""
    var order: Int
    """The sign of |a - q|^2 - |b - q|^2."""
    var label: String
    """The case name."""
    var exceeds_range: Bool
    """True when |a - q| exceeds the largest finite double."""
    var positive: Bool
    """True when |a - q| is not zero."""
    var upper_radius_bits: UInt64
    """The bits of the least double whose square is at least |a - q|^2."""


def upper_radius_bits(square: Fraction) raises -> UInt64:
    """Find the least nonnegative double upper radius by exact bisection.

    The search runs over the bits from zero to positive infinity, so a
    square past the finite range gives the bits of infinity.

    Args:
        square: A nonnegative rational square.

    Returns:
        The least bits whose double squared is at least the square.

    Raises:
        Error: If the exact arithmetic fails, which it must not.
    """
    var low = UInt64(0)
    var high = INFINITY_BITS
    while low < high:
        var middle = (low + high) // 2
        var value = exact(middle)
        if value * value >= square:
            high = middle
        else:
            low = middle + 1
    return low


def _square_distance(
    point: List[UInt64], query: List[UInt64]
) raises -> Fraction:
    """Return the exact squared distance between two stored points."""
    var total = Fraction(0)
    for axis in range(3):
        var difference = exact(point[axis]) - exact(query[axis])
        total = total + difference * difference
    return total^


def _sign(value: Fraction) -> Int:
    """Return -1, 0 or 1 for the sign of a rational."""
    if value > Fraction(0):
        return 1
    if value < Fraction(0):
        return -1
    return 0


def _add(
    mut rows: List[Case],
    a: List[UInt64],
    b: List[UInt64],
    query: List[UInt64],
    label: String,
) raises:
    """Append one case with its exact answers."""
    var da = _square_distance(a, query)
    var db = _square_distance(b, query)
    var bits = a.copy()
    bits.extend(b.copy())
    bits.extend(query.copy())
    var largest = exact(LARGEST_FINITE)
    rows.append(
        Case(
            bits^,
            _sign(da - db),
            label,
            da > largest * largest,
            da > Fraction(0),
            upper_radius_bits(da),
        )
    )


def _random_bits(mut source: PythonRandom) -> UInt64:
    """Return random double bits with a chosen exponent field."""
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
    var sign = UInt64(source.getrandbits(1).to_int_unchecked())
    var fraction = UInt64(source.getrandbits(52).to_int_unchecked())
    return (sign << 63) | (exponent << 52) | fraction


def _triple(mut source: PythonRandom) -> List[UInt64]:
    """Return three random words."""
    var words = List[UInt64]()
    for _ in range(3):
        words.append(_random_bits(source))
    return words^


def cases() raises -> List[Case]:
    """Return the 100 controls.

    Returns:
        64 broad cases, 27 equal-norm cases and 9 carry cases.

    Raises:
        Error: If the exact arithmetic fails, which it must not.
    """
    var source = PythonRandom(594302)
    var rows = List[Case]()
    for index in range(64):
        var a = _triple(source)
        var b = _triple(source)
        var query = _triple(source)
        # The generator also draws a width that no case uses.
        _ = _random_bits(source)
        _add(rows, a, b, query, "broad_" + String(index))
    var shifts: List[Int] = [-1000, -700, -500, -200, 0, 200, 500, 700, 1000]
    var perturbations: List[Int] = [0, 1, -1]
    for shift in shifts:
        var scale = power_of_two(shift)
        for perturbation in perturbations:
            var query = UInt64(0)
            if perturbation > 0:
                query = 1
            elif perturbation < 0:
                query = (UInt64(1) << 63) | 1
            var a: List[UInt64] = [
                float_bits(3 * scale),
                float_bits(4 * scale),
                0,
            ]
            var b: List[UInt64] = [0, float_bits(5 * scale), 0]
            var q: List[UInt64] = [0, query, 0]
            _add(
                rows,
                a,
                b,
                q,
                "equinorm_" + String(shift) + "_" + String(perturbation),
            )
    var fields: List[UInt64] = [0, 1, 1023, 2046]
    for index in range(9):
        var x = (fields[source.choice(len(fields))] << 52) | (
            (UInt64(1) << 52) - 1
        )
        var flipped = x ^ (UInt64(1) << 63)
        var q: List[UInt64] = [UInt64(1) << 63, 0, 0]
        _add(
            rows,
            [x, x, x],
            [flipped, flipped, flipped],
            q,
            "carry_tie_" + String(index),
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
        out += "        (\n            [\n"
        for raw in row.bits:
            out += "                UInt64(0x" + hex_word(raw) + "),\n"
        out += (
            "            ],\n            "
            + String(row.order)
            + ",\n            "
            + python_bool(row.exceeds_range)
            + ",\n            "
            + python_bool(row.positive)
            + ",\n            UInt64(0x"
            + hex_word(row.upper_radius_bits)
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
        writer.key("bits")
        writer.begin_array()
        for raw in row.bits:
            writer.unsigned(raw)
        writer.end()
        writer.key("order")
        writer.integer(row.order)
        writer.key("label")
        writer.string(row.label)
        writer.key("exceeds_range")
        writer.boolean(row.exceeds_range)
        writer.key("positive")
        writer.boolean(row.positive)
        writer.key("upper_radius_bits")
        writer.unsigned(row.upper_radius_bits)
        writer.end()
    writer.end()
    return writer.text() + "\n"


def run(root: String, arguments: List[String]) raises -> Tuple[Int, String]:
    """Write or check the fixture, then write the optional report.

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
