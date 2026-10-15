# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Regenerate bounded CARLA endpoint arithmetic controls from exact Fractions.

    generate_carla_directed_controls [--json PATH] [--check]

writes `tests/test_carla_directed_fraction.mojo`. The output needs no
compiler or formatter. Use `--check` for an exact, read-only replay of the
saved fixture. Do not combine `--check` and `--json`.

The cases are those of the Python generator that this tool replaces: the
random pairs come from `random.Random(594400)`.
"""

from std.sys import argv, exit, stderr

from tools._bigint import BigInt
from tools._carla_controls import (
    bracket,
    deliver,
    float_bits,
    hex_word,
    ldexp,
    parse_options,
    power_of_two,
    python_bool,
    toward_zero,
    write_report,
)
from tools._fraction import Fraction
from tools._json_tools import JsonWriter
from tools._python_random import PythonRandom


comptime PROGRAM = "generate_carla_directed_controls"
"""The program name in the usage line."""

comptime DESCRIPTION = (
    "Regenerate bounded CARLA endpoint arithmetic controls from exact"
    " Fractions."
)
"""The help description."""

comptime FIXTURE = "tests/test_carla_directed_fraction.mojo"
"""The fixture path below the repository root."""

comptime HEADER = (
    "# Copyright (c) 2026 Seth Kitchen, PE\n"
    "# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0\n"
    "# Noncommercial use is free; commercial use requires a paid license.\n"
    "# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.\n"
    "\n"
    '"""Exact Fraction controls for bounded directed endpoint'
    ' arithmetic."""\n'
    "\n"
    "from extensions.carla.curve_interval import (\n"
    "    _directed_endpoint_sum,\n"
    "    _directed_endpoint_product,\n"
    "    _directed_endpoint_quotient,\n"
    "    _tight_quotient_bound,\n"
    "    _Interval,\n"
    ")\n"
    "from std.memory import bitcast\n"
    "from std.testing import TestSuite, assert_equal, assert_true\n"
    "\n"
    "\n"
    "def test_directed_endpoint_fraction_corpus() raises:\n"
    "    var cases: List[Tuple[Array[UInt64, 8], Bool]] = [\n"
)
"""The fixture text before the cases."""

comptime FOOTER = (
    "    ]\n"
    "    for i in range(len(cases)):\n"
    "        ref row = cases[i]\n"
    "        var a = bitcast[DType.float64](row[0][0])\n"
    "        var b = bitcast[DType.float64](row[0][1])\n"
    "        var values: Array[_Interval, 3] = [\n"
    "            _directed_endpoint_sum(a, b),\n"
    "            _directed_endpoint_product(a, b),\n"
    "            _directed_endpoint_quotient(a, b),\n"
    "        ]\n"
    "        for j in range(3):\n"
    "            var low = bitcast[DType.float64](row[0][2 + 2 * j])\n"
    "            var high = bitcast[DType.float64](row[0][3 + 2 * j])\n"
    "            assert_true(values[j].low <= low)\n"
    "            assert_true(values[j].high >= high)\n"
    "            if row[1]:\n"
    "                assert_equal(values[j].low, low)\n"
    "                assert_equal(values[j].high, high)\n"
    "\n"
    "\n"
    "def test_directed_zero_denominator_retains_unknown_enclosure() raises:\n"
    "    assert_true(_directed_endpoint_quotient(1.0, 0.0).contains(-1.0))\n"
    "    assert_true(_directed_endpoint_quotient(1.0, 0.0).contains(1.0))\n"
    "    assert_true(\n"
    "        _tight_quotient_bound(\n"
    "            _Interval.point(1.0), _Interval(-1.0, 1.0)\n"
    "        ).contains(0.0)\n"
    "    )\n"
    "\n"
    "\n"
    "def main() raises:\n"
    "    TestSuite.discover_tests[__functions_in_module()]().run()\n"
)
"""The fixture text after the cases."""


@fieldwise_init
struct Case(Copyable, Movable):
    """One endpoint arithmetic control."""

    var bits: List[UInt64]
    """The inputs a and b, then the sum, product and quotient brackets."""
    var tight: Bool
    """True when both inputs are zero or in [2**-400, 2**400]."""


def valid(value: Float64) -> Bool:
    """Return whether a double is zero or of magnitude in [2**-400, 2**400].

    Args:
        value: The double.

    Returns:
        True when the directed endpoints must be tight.
    """
    return value == 0 or (
        power_of_two(-400) <= abs(value) and abs(value) <= power_of_two(400)
    )


def pairs() -> List[Tuple[Float64, Float64]]:
    """Return the fixed edge pairs, then 119 random pairs.

    Returns:
        The (a, b) pairs.
    """
    var result: List[Tuple[Float64, Float64]] = [
        (0.0, 1.0),
        (-0.0, -1.0),
        (1.0, 0.5),
        (toward_zero(1.0), -1.0),
        (power_of_two(400), power_of_two(-400)),
        (-power_of_two(-400), power_of_two(400)),
        (toward_zero(power_of_two(-400)), 2.0),
        (power_of_two(-500), power_of_two(500)),
        (power_of_two(500), -power_of_two(500)),
    ]
    var rng = PythonRandom(594400)
    var exponents = [-400, -399, -1, 0, 1, 398, 399]
    for _ in range(119):
        var sample = List[Float64]()
        for _ in range(2):
            var negative = not rng.randrange(BigInt(0), BigInt(2)).is_zero()
            var unit = 1 + rng.random()
            var value = ldexp(unit, exponents[rng.choice(len(exponents))])
            sample.append(-value if negative else value)
        result.append((sample[0], sample[1]))
    return result^


def cases() raises -> List[Case]:
    """Return the 128 controls.

    Returns:
        The controls, in the order of the pairs.

    Raises:
        Error: If the exact arithmetic fails, which it must not.
    """
    var result = List[Case]()
    for pair in pairs():
        var a = pair[0]
        var b = pair[1]
        var af = Fraction.from_float(a)
        var bf = Fraction.from_float(b)
        var bits: List[UInt64] = [float_bits(a), float_bits(b)]
        for value in [af + bf, af * bf, af / bf]:
            var interval = bracket(value)
            bits.append(float_bits(interval[0]))
            bits.append(float_bits(interval[1]))
        result.append(Case(bits^, valid(a) and valid(b)))
    return result^


def fixture(rows: List[Case]) -> String:
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
            + python_bool(row.tight)
            + ",\n        ),\n"
        )
    out += FOOTER
    return out^


def report(rows: List[Case]) -> String:
    """Return the review report, as `json.dumps(cases, indent=2)` writes it.

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
        writer.key("tight")
        writer.boolean(row.tight)
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
    var delivered = deliver(root, FIXTURE, fixture(rows), options.check)
    if delivered[0] != 0:
        return delivered
    if options.has_json:
        var written = write_report(options.json, report(rows))
        if written[0] != 0:
            return written
    return (
        0,
        ("Verified " if options.check else "Generated ")
        + String(len(rows))
        + " exact Fraction controls\n",
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
