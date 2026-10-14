# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Regenerate binary64 predicate cases with independent exact fractions.

    generate_exact_predicates_oracle [--check | --write]

writes `tests/exact_predicates_oracle.mojo`: binary64 points and tolerances,
with each predicate's answer computed in exact rational arithmetic, not by
production code. `--check`, the default, verifies the file.

The cases are those of the Python generator this tool replaces: the random
cases come from `random.Random(538)`.
"""

from std.ffi import c_int, external_call
from std.math import sqrt
from std.memory import bitcast
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._bigint import BigInt
from tools._fraction import Fraction
from tools._python_random import PythonRandom

comptime TARGET = "tests/exact_predicates_oracle.mojo"
"""The generated test helper."""

comptime Point = Tuple[Float64, Float64, Float64]
comptime Exact = Tuple[Fraction, Fraction, Fraction]


def ldexp(value: Float64, exponent: Int) -> Float64:
    """Return value * 2**exponent, as the C library computes it."""
    return external_call["ldexp", Float64](value, c_int(exponent))


def nextafter(value: Float64, toward: Float64) -> Float64:
    """Return the next double after value toward another."""
    return external_call["nextafter", Float64](value, toward)


def _sub(a: Exact, b: Exact) raises -> Exact:
    """Return a - b."""
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _dot(a: Exact, b: Exact) raises -> Fraction:
    """Return a . b."""
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _cross(a: Exact, b: Exact) raises -> Exact:
    """Return a x b."""
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def _sign(x: Fraction) -> Int:
    """Return -1, 0 or 1."""
    return x.compare(Fraction(0))


def plane(
    a: Exact, b: Exact, c: Exact, p: Exact
) raises -> Tuple[Fraction, Fraction]:
    """Return p's unnormalized distance from plane abc, and |normal|**2."""
    var normal = _cross(_sub(b, a), _sub(c, a))
    return (_dot(normal, _sub(p, a)), _dot(normal, normal))


def segment(a: Exact, b: Exact, p: Exact) raises -> Fraction:
    """Return the squared distance from p to segment ab."""
    var edge = _sub(b, a)
    var gap = _sub(p, a)
    var squared = _dot(edge, edge)
    var projection = _dot(edge, gap)
    if squared.is_zero() or projection <= Fraction(0):
        return _dot(gap, gap)
    if projection >= squared:
        var far = _sub(p, b)
        return _dot(far, far)
    return _dot(gap, gap) - projection * projection / squared


def literal(x: Float64) -> String:
    """Return `_f(0x...)` with the double's sixteen hexadecimal digits."""
    var bits = bitcast[DType.uint64](x)
    var digits = "0123456789ABCDEF"
    var text = String("_f(0x")
    for shift in range(60, -4, -4):
        text += String(
            digits[
                byte = Int((bits >> UInt64(shift)) & 15) : Int(
                    (bits >> UInt64(shift)) & 15
                )
                + 1
            ]
        )
    return text + ")"


def _exact(point: Point) raises -> Exact:
    """Return a point's exact coordinates."""
    return (
        Fraction.from_float(point[0]),
        Fraction.from_float(point[1]),
        Fraction.from_float(point[2]),
    )


@fieldwise_init
struct OracleCase(Copyable, Movable):
    """Eight points and a tolerance."""

    var points: List[Point]
    """The points a, b, c, p, d, e, f, q."""
    var tolerance: Float64
    """The plane tolerance."""


def _uniform(mut rng: PythonRandom, a: Float64, b: Float64) -> Float64:
    """Return `rng.uniform(a, b)`: a + (b - a) * random()."""
    return a + (b - a) * rng.random()


def generate_cases() raises -> List[OracleCase]:
    """Return every case, in the order the file lists them.

    Returns:
        The cases.
    """
    var rng = PythonRandom(538)
    var cases = List[OracleCase]()
    var zero: Point = (0.0, 0.0, 0.0)
    var infinity = Float64.MAX * 2
    for power in [-1074, -1022, -500, -1, 0, 53, 500, 1022]:
        var s = ldexp(1.0, power)
        var a = zero
        var b: Point = (s, 0.0, 0.0)
        var c: Point = (0.0, s, 0.0)
        var p: Point = (0.0, 0.0, s)
        var q: Point = (0.0, 0.0, -s)
        for t in [0.0, s, nextafter(s, 0.0)]:
            cases.append(OracleCase([a, b, c, p, a, c, b, q], t))
    var largest = Float64.MAX_FINITE
    var tiny = ldexp(1.0, -1074)
    cases.append(
        OracleCase(
            [
                (largest, tiny, 0.0),
                (-largest, 0.0, 0.0),
                (0.0, largest, tiny),
                (tiny, 0.0, largest),
                zero,
                (tiny, 0.0, 0.0),
                (0.0, tiny, 0.0),
                (0.0, 0.0, tiny),
            ],
            tiny,
        )
    )
    var big = ldexp(1.0, 53)
    cases.append(
        OracleCase(
            [
                (big, 1.0, 0.0),
                (0.0, 0.0, 0.0),
                (big, 0.0, 1.0),
                (1.0, 0.0, 0.0),
                zero,
                (1.0, 0.0, 0.0),
                (0.0, 1.0, 0.0),
                (0.0, 0.0, 1.0),
            ],
            0.0,
        )
    )
    # Integer cases include exact ties, either projection endpoint, and
    # nonparallel planes. The extreme cases force the bounded fallback.
    for _ in range(32):
        var points = List[Point]()
        for _ in range(8):
            var x = Float64(rng.randrange(BigInt(-4), BigInt(5)).to_int())
            var y = Float64(rng.randrange(BigInt(-4), BigInt(5)).to_int())
            var z = Float64(rng.randrange(BigInt(-4), BigInt(5)).to_int())
            points.append((x, y, z))
        if plane(
            _exact(points[0]),
            _exact(points[1]),
            _exact(points[2]),
            _exact(points[3]),
        )[1].is_zero():
            continue
        if plane(
            _exact(points[4]),
            _exact(points[5]),
            _exact(points[6]),
            _exact(points[7]),
        )[1].is_zero():
            continue
        cases.append(OracleCase(points^, Float64(rng.choice(4))))
    var powers = [-1070, -1000, -500, -54, 0, 54, 500, 1000, 1023]
    var tolerances = [-1074, -500, 0, 500]
    for _ in range(24):
        var points = List[Point]()
        for _ in range(8):
            var coordinates = List[Float64]()
            for _ in range(3):
                # Python evaluates uniform() before choice().
                var mantissa = _uniform(rng, -1.0, 1.0)
                coordinates.append(
                    ldexp(mantissa, powers[rng.choice(len(powers))])
                )
            points.append((coordinates[0], coordinates[1], coordinates[2]))
        cases.append(
            OracleCase(
                points^, ldexp(1.0, tolerances[rng.choice(len(tolerances))])
            )
        )
    # Cancellation around the certified determinant error bound. Here
    # D=delta and its absolute permanent is 4+delta.
    var epsilon = ldexp(1.0, -53)
    for factor in [32, 64, 128, 256]:
        for direction in [-1, 1]:
            var delta = Float64(direction * factor) * epsilon * 4
            cases.append(
                OracleCase(
                    [
                        zero,
                        (1.0, 1.0, 0.0),
                        (1.0, 0.0, 1.0),
                        (2.0 + delta, 1.0, 1.0),
                        zero,
                        (1.0, 0.0, 0.0),
                        (0.0, 1.0, 0.0),
                        (0.0, 0.0, 1.0),
                    ],
                    0.0,
                )
            )
    # A slanted normal makes the true distance irrational. Adjacent stored
    # tolerances straddle the exact squared comparison, not a rounded normal.
    for displacement in [0.0, ldexp(1.0, -53), -ldexp(1.0, -52)]:
        var distance = (1.0 + displacement) / sqrt(3.0)
        for t in [
            nextafter(distance, 0.0),
            distance,
            nextafter(distance, infinity),
        ]:
            cases.append(
                OracleCase(
                    [
                        zero,
                        (1.0, 1.0, 0.0),
                        (1.0, 0.0, 1.0),
                        (1.0 + displacement, 0.0, 0.0),
                        zero,
                        (1.0, 0.0, 0.0),
                        (0.0, 1.0, 0.0),
                        (0.0, 0.0, 1.0),
                    ],
                    t,
                )
            )
    # Both guard endpoints, their immediate neighbors, and exact tolerance
    # equality. The next representable value outside must use a fallback.
    for power in [-100, 100]:
        var endpoint = ldexp(1.0, power)
        for s in [
            nextafter(endpoint, 0.0),
            endpoint,
            nextafter(endpoint, infinity),
        ]:
            var points: List[Point] = [
                zero,
                (s, 0.0, 0.0),
                (0.0, s, 0.0),
                (0.0, 0.0, s),
                zero,
                (0.0, s, 0.0),
                (s, 0.0, 0.0),
                (0.0, 0.0, -s),
            ]
            for t in [0.0, nextafter(s, 0.0), s, nextafter(s, infinity)]:
                cases.append(OracleCase(points.copy(), t))
    return cases^


def _answers(oracle: OracleCase) raises -> List[String]:
    """Return a case's nine exact answers, as the file writes them."""
    var e = List[Exact]()
    for point in oracle.points:
        e.append(_exact(point))
    var first_plane = plane(e[0], e[1], e[2], e[3])
    var second_plane = plane(e[4], e[5], e[6], e[7])
    var first = first_plane[0].copy()
    var n1 = first_plane[1].copy()
    var second = second_plane[0].copy()
    var n2 = second_plane[1].copy()
    var same = plane(e[0], e[1], e[2], e[7])[0].copy()
    var squared_order = _sign(first * first * n2 - second * second * n1)
    var signed_order: Int
    if _sign(first) != _sign(second):
        signed_order = 1 if _sign(first) > _sign(second) else -1
    else:
        signed_order = _sign(first) * squared_order
    var t = Fraction.from_float(oracle.tolerance)
    var above = _sign(first) > 0 and first * first > t * t * n1
    var edge = _sub(e[1], e[0])
    var xp = _cross(edge, _sub(e[3], e[0]))
    var xq = _cross(edge, _sub(e[7], e[0]))
    var values = [
        _sign(first),
        _sign(first - same),
        _sign(abs(first) - abs(same)),
        _sign(segment(e[0], e[1], e[3]) - segment(e[0], e[1], e[7])),
        _sign(_dot(xp, xp) - _dot(xq, xq)),
        _sign((e[0][0] - e[1][0]) - (e[2][0] - e[3][0])),
    ]
    return [
        String(values[0]),
        "True" if above else "False",
        String(signed_order),
        String(squared_order),
        String(values[1]),
        String(values[2]),
        String(values[3]),
        String(values[4]),
        String(values[5]),
    ]


def generate() raises -> Tuple[String, Int]:
    """Return the generated file and its number of cases.

    Returns:
        The Mojo source, and the case count.
    """
    var cases = generate_cases()
    var result: List[String] = [
        "# Copyright (c) 2026 Seth Kitchen, PE",
        "# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0",
        "",
        '"""Generated by tools/generate_exact_predicates_oracle.mojo.',
        "",
        "Expected values use exact rational arithmetic, not production code.",
        '"""',
        "",
        "from std.memory import bitcast",
        "",
        "comptime _P = SIMD[DType.float64, 4]",
        "",
        "",
        "def _f(bits: UInt64) -> Float64:",
        "    return bitcast[DType.float64](bits)",
        "",
        "",
        "@fieldwise_init",
        "struct _OracleCase(ImplicitlyCopyable):",
    ]
    for name in ["a", "b", "c", "p", "d", "e", "f", "q"]:
        result.append("    var " + name + ": _P")
    for line in [
        "    var tolerance: Float64",
        "    var orientation: Int",
        "    var above: Bool",
        "    var signed_planes: Int",
        "    var absolute_planes: Int",
        "    var same_signed: Int",
        "    var same_absolute: Int",
        "    var segment: Int",
        "    var line: Int",
        "    var difference: Int",
        "",
        "",
        "def _oracle_cases() -> List[_OracleCase]:",
        "    var cases = List[_OracleCase]()",
    ]:
        result.append(line)
    for oracle in cases:
        result.append("    cases.append(")
        result.append("        _OracleCase(")
        for point in oracle.points:
            result.append("            _P(")
            result.append("                " + literal(point[0]) + ",")
            result.append("                " + literal(point[1]) + ",")
            result.append("                " + literal(point[2]) + ",")
            result.append("                0,")
            result.append("            ),")
        result.append("            " + literal(oracle.tolerance) + ",")
        for answer in _answers(oracle):
            result.append("            " + answer + ",")
        result.append("        )")
        result.append("    )")
    result.append("    return cases^")
    result.append("")
    return ("\n".join(result), len(cases))


def main() raises:
    var given = argv()
    var mode = String(given[1]) if len(given) > 1 else String("--check")
    if len(given) > 2 or not (mode == "--check" or mode == "--write"):
        print(
            "usage: generate_exact_predicates_oracle [--check | --write]",
            file=stderr,
        )
        exit(2)
    var made = generate()
    if mode == "--write":
        Path(TARGET).write_text(made[0])
        print("Wrote " + String(made[1]) + " exact predicate oracle cases")
    elif Path(TARGET).read_text() == made[0]:
        print("Verified " + String(made[1]) + " exact predicate oracle cases")
    else:
        print("Exact predicate oracle is stale; run with --write", file=stderr)
        exit(1)
