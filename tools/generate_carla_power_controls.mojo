# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Generate exact Fraction enclosures for the local binary-scaling helpers.

    generate_carla_power_controls [--json PATH] [--check]

writes `tests/test_carla_power_fraction.mojo`. The output needs no compiler
or formatter. Use `--check` for an exact, read-only replay of the saved
fixture. Do not combine `--check` and `--json`.

The cases are those of the Python generator that this tool replaces: the
random bits come from `random.Random(302594)`.
"""

from std.sys import argv, exit, stderr

from tools._carla_controls import (
    bracket,
    deliver,
    float_bits,
    from_bits,
    hex_word,
    is_finite,
    parse_options,
    power_of_two,
    python_bool,
    write_report,
)
from tools._fraction import Fraction
from tools._json_tools import JsonWriter
from tools._python_random import PythonRandom


comptime PROGRAM = "generate_carla_power_controls"
"""The program name in the usage line."""

comptime DESCRIPTION = (
    "Generate exact Fraction enclosures for the local binary-scaling helpers."
)
"""The help description."""

comptime FIXTURE = "tests/test_carla_power_fraction.mojo"
"""The fixture path below the repository root."""

comptime HEADER = (
    "# Copyright (c) 2026 Seth Kitchen, PE\n"
    "# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0\n"
    "# Noncommercial use is free; commercial use requires a paid license.\n"
    "# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.\n"
    "\n"
    '"""Controls for precise ideal bounds and origin-local scalar'
    ' quadrature."""\n'
    "\n"
    "from extensions.carla.curve_interval import (\n"
    "    _Interval,\n"
    "    _power_product_bound,\n"
    "    _power_quotient_bound,\n"
    ")\n"
    "from std.memory import bitcast\n"
    "from std.testing import TestSuite, assert_equal, assert_true\n"
    "\n"
    "\n"
    "def test_exact_fraction_power_scaling_corpus() raises:\n"
    "    var cases: List[Tuple[Array[UInt64, 7], Bool, Bool]] = [\n"
)
"""The fixture text before the cases."""

comptime FOOTER = (
    "    ]\n"
    "    for i in range(len(cases)):\n"
    "        ref row = cases[i]\n"
    "        var one = _Interval(\n"
    "            bitcast[DType.float64](row[0][0]),"
    " bitcast[DType.float64](row[0][1])\n"
    "        )\n"
    "        var two = _Interval.point(bitcast[DType.float64](row[0][2]))\n"
    "        var product = _power_product_bound(one, two)\n"
    "        var quotient = _power_quotient_bound(one, two)\n"
    "        var pl = bitcast[DType.float64](row[0][3])\n"
    "        var ph = bitcast[DType.float64](row[0][4])\n"
    "        var ql = bitcast[DType.float64](row[0][5])\n"
    "        var qh = bitcast[DType.float64](row[0][6])\n"
    "        assert_true(product.low <= pl)\n"
    "        assert_true(product.high >= ph)\n"
    "        assert_true(quotient.low <= ql)\n"
    "        assert_true(quotient.high >= qh)\n"
    "        if row[1]:\n"
    "            assert_equal(product.low, pl)\n"
    "            assert_equal(product.high, ph)\n"
    "        if row[2]:\n"
    "            assert_equal(quotient.low, ql)\n"
    "            assert_equal(quotient.high, qh)\n"
    "\n"
    "\n"
    "def main() raises:\n"
    "    TestSuite.discover_tests[__functions_in_module()]().run()\n"
)
"""The fixture text after the cases."""


@fieldwise_init
struct Case(Copyable, Movable):
    """One scaling control."""

    var bits: List[UInt64]
    """The interval, the scale, the product bracket and the quotient
    bracket."""
    var exact_product: Bool
    """True when the product endpoints are exact normal doubles or zero."""
    var exact_quotient: Bool
    """True when the quotient endpoints are exact normal doubles or zero."""


def exact_normal_or_zero(number: Fraction) raises -> Bool:
    """Return whether a rational is zero or an exact normal double.

    Args:
        number: The rational.

    Returns:
        True when its bracket is one point that is zero or normal.

    Raises:
        Error: If the arithmetic fails, which it must not.
    """
    var interval = bracket(number)
    var low = interval[0]
    return low == interval[1] and (
        low == 0.0 or is_finite(low) and abs(low) > power_of_two(-1022)
    )


def _binary_power(exponent: Int) -> Float64:
    """Return 2.0**exponent for an exponent from -1074 to 1023."""
    if exponent >= -1022:
        return power_of_two(exponent)
    return from_bits(UInt64(1) << UInt64(exponent + 1074))


def _sorted(var first: Fraction, var second: Fraction) -> List[Fraction]:
    """Return two rationals in ascending order, keeping ties in place."""
    if second < first:
        return [second^, first^]
    return [first^, second^]


def cases() raises -> List[Case]:
    """Return the 128 controls.

    Returns:
        The controls, in the order of the random draws.

    Raises:
        Error: If the exact arithmetic fails, which it must not.
    """
    var rng = PythonRandom(302594)
    var exponents: List[UInt64] = [
        0,
        1,
        2,
        100,
        500,
        970,
        1023,
        1024,
        1500,
        2000,
        2046,
    ]
    var powers = [-1074, -1022, -700, -1, 0, 1, 400, 1000, 1023]
    var others = [-3.0, 1.1, 1.5, 3.0]
    var result = List[Case]()
    for index in range(128):
        var values = List[Float64]()
        for _ in range(2):
            var top = UInt64(rng.getrandbits(1).to_int_unchecked())
            var exponent = exponents[rng.choice(len(exponents))]
            var low = UInt64(rng.getrandbits(52).to_int_unchecked())
            values.append(from_bits((top << 63) | (exponent << 52) | low))
        if index % 13 == 0:
            values[0] = 0.0
        var lo = values[0]
        var hi = values[1]
        if hi < lo:
            lo = values[1]
            hi = values[0]
        var negative = not rng.getrandbits(1).is_zero()
        var scale = (-1.0 if negative else 1.0) * _binary_power(
            powers[rng.choice(len(powers))]
        )
        var is_power = index % 7 != 0
        if not is_power:
            scale = others[rng.choice(len(others))]
        var a = Fraction.from_float(lo)
        var b = Fraction.from_float(hi)
        var k = Fraction.from_float(scale)
        var product = _sorted(a * k, b * k)
        var quotient = _sorted(a / k, b / k)
        var bits: List[UInt64] = [
            float_bits(lo),
            float_bits(hi),
            float_bits(scale),
            float_bits(bracket(product[0])[0]),
            float_bits(bracket(product[1])[1]),
            float_bits(bracket(quotient[0])[0]),
            float_bits(bracket(quotient[1])[1]),
        ]
        var exact_product = is_power
        var exact_quotient = is_power
        if is_power:
            exact_product = exact_normal_or_zero(
                product[0]
            ) and exact_normal_or_zero(product[1])
            exact_quotient = exact_normal_or_zero(
                quotient[0]
            ) and exact_normal_or_zero(quotient[1])
        result.append(Case(bits^, exact_product, exact_quotient))
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
            + python_bool(row.exact_product)
            + ",\n            "
            + python_bool(row.exact_quotient)
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
        writer.key("exact_product")
        writer.boolean(row.exact_product)
        writer.key("exact_quotient")
        writer.boolean(row.exact_quotient)
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
