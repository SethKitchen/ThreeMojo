# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Independent planar-wall statics reference; no ThreeMojo library imports.

    mojo run -I . --fp-mode contract=off tools/reference_geotech_wall.mojo
    mojo run -I . --fp-mode contract=off tools/reference_geotech_wall.mojo --check

prints the rows of `test_planar_wall_python_reference` in
`tests/test_geotech_wall.mojo`. `--check` confirms that the rows there are
current, within the native tests' absolute tolerances.

Scope: dry, level backfill, rectangular stem and footing, no key or pipes.
Rankine pressure is integrated as a triangular diagram, surcharge as a
rectangle. Vertical weights are rectangle areas times unit weight. The
reference checks Strength I minimum resultants, eccentricity and sliding,
and Service I tension-free pressure. It does not certify a design.

The rows are the same, to the last digit, as the Python reference that this
tool replaces: see `tools/_python_math.mojo`.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_math import float_sum, radians, sin, tan

comptime CASES = [(3.0, 0.0), (3.0, 0.6), (4.0, 0.0), (4.0, 0.6)]
"""The wall heights and live surcharge heights, in meters."""

comptime BEGIN = "# BEGIN PYTHON WALL REFERENCE\n"
comptime END = "# END PYTHON WALL REFERENCE"


def reference(height: Float64, live_height: Float64) -> List[Float64]:
    """Return the input heights and five independently assembled SI results.

    Args:
        height: The wall height.
        live_height: The live surcharge height.

    Returns:
        The heights, the factored vertical and horizontal resultants, the
        eccentricity, the sliding ratio, and the peak service pressure.
    """
    var width = 3.0
    var toe = 0.6
    var stem = 0.4
    var footing = 0.5
    var soil = 18000.0
    var concrete = 24000.0
    var phi = radians(30)
    var ka = (1 - sin(phi)) / (1 + sin(phi))
    var heel = width - toe - stem
    var forces: List[Float64] = [
        (height - footing) * stem * concrete,
        width * footing * concrete,
        heel * (height - footing) * soil,
    ]
    var arms = [toe + stem / 2, width / 2, toe + stem + heel / 2]
    var factors = [0.9, 0.9, 1.0]
    var earth = ka * soil * (height * height) / 2
    var live = ka * soil * live_height * height
    var factored = List[Float64]()
    var moments = List[Float64]()
    var service_moments = List[Float64]()
    for index in range(3):
        factored.append(forces[index] * factors[index])
        moments.append(forces[index] * arms[index] * factors[index])
        service_moments.append(forces[index] * arms[index])
    var vertical = float_sum(factored)
    var resisting = float_sum(moments)
    var horizontal = 1.5 * earth + 1.75 * live
    var overturning = 1.5 * earth * height / 3 + 1.75 * live * height / 2
    var eccentricity = width / 2 - (resisting - overturning) / vertical
    var sliding = horizontal / (0.8 * vertical * tan(phi))
    var live_weight = heel * live_height * soil
    var service_v = float_sum(forces) + live_weight
    var service_m = float_sum(service_moments)
    service_m += live_weight * (toe + stem + heel / 2)
    service_m -= earth * height / 3 + live * height / 2
    var service_e = abs(width / 2 - service_m / service_v)
    var effective = service_v / (width - 2 * service_e)
    var peak: Float64
    if service_e <= width / 6:
        peak = service_v / width * (1 + 6 * service_e / width)
    else:
        peak = 2 * service_v / (3 * (width / 2 - service_e))
    return [
        height,
        live_height,
        vertical,
        horizontal,
        eccentricity,
        sliding,
        max(effective, peak),
    ]


def rows() -> String:
    """Return the Mojo tuple literals of the four cases.

    Returns:
        One indented line for each case.
    """
    var lines = List[String]()
    for entry in materialize[CASES]():
        var values = List[String]()
        for value in reference(entry[0], entry[1]):
            values.append(String(value))
        lines.append("        (" + ", ".join(values) + "),")
    return "\n".join(lines)


def _parse(text: String) raises -> List[List[Float64]]:
    """Read tuple literals of floats, in any layout, as a list display."""
    var parsed = List[List[Float64]]()
    var at = 0
    while True:
        var open = text.find("(", at)
        if open < 0:
            break
        var close = text.find(")", open)
        if close < 0:
            raise Error("a reference row does not close")
        var values = List[Float64]()
        for field in String(text[byte = open + 1 : close]).split(","):
            var number = String(field).strip()
            if number:
                values.append(Float64(String(number)))
        parsed.append(values^)
        at = close + 1
    return parsed^


def check(root: String) raises -> Bool:
    """Return whether the test's rows match this reference.

    The heights must be equal. The results may differ by the C library's
    last-digit rounding, within the native tests' absolute tolerances.

    Args:
        root: The repository root.

    Returns:
        True when every row matches.

    Raises:
        Error: If the test file has no reference rows.
    """
    var source = Path(root + "/tests/test_geotech_wall.mojo").read_text()
    var start = source.find(BEGIN)
    var end = source.find(END, start)
    if start < 0 or end < 0:
        raise Error("tests/test_geotech_wall.mojo has no reference rows")
    var actual = _parse(
        String(source[byte = start + BEGIN.byte_length() : end])
    )
    var expected = _parse(rows())
    var tolerances = [1e-6, 1e-6, 1e-9, 1e-9, 1e-6]
    if len(actual) != len(expected):
        return False
    for index in range(len(actual)):
        if len(actual[index]) != 7:
            return False
        if (
            actual[index][0] != expected[index][0]
            or actual[index][1] != expected[index][1]
        ):
            return False
        for column in range(2, 7):
            if (
                not abs(actual[index][column] - expected[index][column])
                <= tolerances[column - 2]
            ):
                return False
    return True


def main() raises:
    var given = argv()
    if len(given) > 1 and String(given[1]) == "--check":
        if not check("."):
            print("Planar wall reference rows are stale", file=stderr)
            exit(1)
        print("Four planar wall reference rows match independent statics.")
        return
    if len(given) > 1:
        print("usage: reference_geotech_wall [--check]", file=stderr)
        exit(2)
    print(rows())
