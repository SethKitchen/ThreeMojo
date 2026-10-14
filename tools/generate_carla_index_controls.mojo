# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Regenerate directed CARLA index-key controls from exact rational squares.

    generate_carla_index_controls [--json PATH] [--check]

writes `tests/test_carla_index_admission.mojo`. The output needs no compiler
or formatter. Use `--check` for an exact, read-only replay of the saved
fixture. Do not combine `--check` and `--json`.

The cases are those of the Python generator that this tool replaces: the
random keys come from `random.Random(589302)`. A native square root gives
only the first estimate of each bound. Exact rational squares then move the
estimate to the largest double that satisfies the bound, so the result does
not depend on the estimate.
"""

from std.math import sqrt
from std.sys import argv, exit, stderr

from tools._bigint import BigInt
from tools._carla_controls import (
    deliver,
    float_bits,
    hex_word,
    ldexp,
    next_up,
    parse_options,
    toward_zero,
    write_report,
)
from tools._fraction import Fraction
from tools._json_tools import JsonWriter
from tools._python_random import PythonRandom


comptime PROGRAM = "generate_carla_index_controls"
"""The program name in the usage line."""

comptime DESCRIPTION = (
    "Regenerate directed CARLA index-key controls from exact rational squares."
)
"""The help description."""

comptime FIXTURE = "tests/test_carla_index_admission.mojo"
"""The fixture path below the repository root."""

comptime HEADER = (
    "# Copyright (c) 2026 Seth Kitchen, PE\n"
    "# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0\n"
    "# Noncommercial use is free; commercial use requires a paid license.\n"
    "# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.\n"
    "\n"
    '"""Directed admission controls for the frozen #589 segment key'
    ' contract."""\n'
    "\n"
    "from extensions.carla.lane_refinement import _indexed_curve_lower\n"
    "from std.math import inf\n"
    "from std.memory import bitcast\n"
    "from std.testing import TestSuite, assert_equal, assert_true\n"
    "\n"
    "\n"
    "def test_index_key_allowance_against_exact_rational_squared_bound()"
    " raises:\n"
    "    var cases: List[Array[UInt64, 3]] = [\n"
)
"""The fixture text before the cases."""

comptime FOOTER = (
    "    ]\n"
    "    for i in range(len(cases)):\n"
    "        var key = bitcast[DType.float64](cases[i][0])\n"
    "        var deviation = bitcast[DType.float64](cases[i][1])\n"
    "        # Largest Float64 L with (L+deviation)^2 <= K/(1+2^-40),\n"
    "        # generated using exact rational squares rather than native"
    " sqrt.\n"
    "        var reference = bitcast[DType.float64](cases[i][2])\n"
    "        var lower = _indexed_curve_lower(key, deviation)\n"
    "        assert_true(lower >= 0.0)\n"
    "        assert_true(lower <= reference)\n"
    "        if reference > 0.0:\n"
    "            assert_true(lower > 0.0)\n"
    "\n"
    "\n"
    "def test_unknown_index_bounds_disable_pruning() raises:\n"
    "    assert_equal(_indexed_curve_lower(0.0, 0.0), 0.0)\n"
    "    assert_equal(_indexed_curve_lower(-1.0, 0.0), 0.0)\n"
    "    assert_equal(_indexed_curve_lower(1.0, -1.0), 0.0)\n"
    "    assert_equal(_indexed_curve_lower(inf[DType.float64](), 0.0), 0.0)\n"
    "    assert_equal(_indexed_curve_lower(1.0, inf[DType.float64]()), 0.0)\n"
    "    var nan = bitcast[DType.float64](UInt64(0x7FF8000000000001))\n"
    "    assert_equal(_indexed_curve_lower(nan, 0.0), 0.0)\n"
    "    assert_equal(_indexed_curve_lower(1.0, nan), 0.0)\n"
    "\n"
    "\n"
    "def main() raises:\n"
    "    TestSuite.discover_tests[__functions_in_module()]().run()\n"
)
"""The fixture text after the cases."""


def _fits(x: Float64, deviation: Fraction, bound: Fraction) raises -> Bool:
    """Return whether (x + deviation)^2 <= bound, exactly."""
    var total = Fraction.from_float(x) + deviation
    return total * total <= bound


def floor_bound(key: Float64, deviation: Float64) raises -> Float64:
    """Return the largest double L with (L + deviation)^2 <= key/(1+2^-40).

    Args:
        key: A positive squared index key.
        deviation: A nonnegative deviation.

    Returns:
        The bound, or 0.0 when the deviation alone exceeds it.

    Raises:
        Error: If the exact arithmetic fails, which it must not.
    """
    var q = Fraction.from_float(key) / (
        Fraction(1) + Fraction.of(BigInt(1), BigInt.power_of_two(40))
    )
    var df = Fraction.from_float(deviation)
    if df * df >= q:
        return 0.0
    # One exact Newton step from the native estimate, from above.
    var start = Fraction.from_float(sqrt(q.to_float()) - deviation)
    var total = start + df
    var x = (start - (total * total - q) / (Fraction(2) * total)).to_float()
    while not _fits(x, df, q):
        x = toward_zero(x)
    while _fits(next_up(x), df, q):
        x = next_up(x)
    return x


def cases() raises -> List[List[UInt64]]:
    """Return the 96 controls.

    Returns:
        The bits of each key, deviation and bound.

    Raises:
        Error: If the exact arithmetic fails, which it must not.
    """
    var rng = PythonRandom(589302)
    var factors = [0.0, 0.125, 0.5, 0.99, 1.0, 2.0]
    var result = List[List[UInt64]]()
    for _ in range(96):
        var unit = 1 + rng.random()
        var exponent = rng.randrange(BigInt(-298), BigInt(260)).to_int()
        var key = ldexp(unit, exponent)
        var radius = sqrt(key)
        var deviation = radius * factors[rng.choice(len(factors))]
        var bound = floor_bound(key, deviation)
        result.append(
            [float_bits(key), float_bits(deviation), float_bits(bound)]
        )
    return result^


def fixture(rows: List[List[UInt64]]) -> String:
    """Return the fixture text.

    Args:
        rows: The controls.

    Returns:
        The test module, byte for byte.
    """
    var out = String(HEADER)
    for row in rows:
        out += "        [\n"
        for raw in row:
            out += "            UInt64(0x" + hex_word(raw) + "),\n"
        out += "        ],\n"
    out += FOOTER
    return out^


def report(rows: List[List[UInt64]]) -> String:
    """Return the review report, as `json.dumps(cases, indent=2)` writes it.

    Args:
        rows: The controls.

    Returns:
        The JSON text with a final newline.
    """
    var writer = JsonWriter()
    writer.begin_array()
    for row in rows:
        writer.begin_array()
        for raw in row:
            writer.unsigned(raw)
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
        + " cases independently bounded by exact rational inequalities\n",
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
