# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reproduce the independent CCD entry-time fixtures.

    mojo run -I . tools/physics_ccd_reference.mojo --check docs/validation/continuous-collision-292-reference.json

The oracle minimizes convex point-to-triangle squared distance, then
bisects the first radius crossing. It does not use the sweep quadratic.
The fixed seed also produces misses and initial overlaps. Only entering
hits become the 23 native reference fixtures. Separate native tests check
misses, tangency, overlap, backfaces and numeric-domain refusals.

The arithmetic is double-double: about 32 significant digits. The 70-digit
Decimal oracle that this tool replaces gave the same fixtures. Each entry
time is rounded to the nearest Float64 at the end. The random cases are
those of `random.Random(292)`.
"""

from std.math import fma
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._bigint import BigInt
from tools._fraction import Fraction
from tools._json_tools import JsonWriter, json_tokens
from tools._python_random import PythonRandom


@fieldwise_init
struct DD(ImplicitlyCopyable, Movable):
    """A double-double: the unevaluated sum hi + lo, with |lo| at most half
    an ulp of hi."""

    var hi: Float64
    """The leading double."""
    var lo: Float64
    """The trailing double."""

    def __init__(out self, value: Float64):
        """Hold a double exactly.

        Args:
            value: The value.
        """
        self.hi = value
        self.lo = 0.0

    @staticmethod
    def _quick(a: Float64, b: Float64) -> DD:
        """Normalize a + b when |a| >= |b|."""
        var s = a + b
        return DD(s, b - (s - a))

    @staticmethod
    def _two_sum(a: Float64, b: Float64) -> Tuple[Float64, Float64]:
        """Return a + b and its exact rounding error."""
        var s = a + b
        var v = s - a
        return (s, (a - (s - v)) + (b - v))

    def __neg__(self) -> DD:
        """Negate.

        Returns:
            The negation.
        """
        return DD(-self.hi, -self.lo)

    def __add__(self, other: DD) -> DD:
        """Add.

        Args:
            other: The other value.

        Returns:
            The sum.
        """
        var s = DD._two_sum(self.hi, other.hi)
        var t = DD._two_sum(self.lo, other.lo)
        var first = DD._quick(s[0], s[1] + t[0])
        return DD._quick(first.hi, first.lo + t[1])

    def __sub__(self, other: DD) -> DD:
        """Subtract.

        Args:
            other: The other value.

        Returns:
            The difference.
        """
        return self + -other

    def __mul__(self, other: DD) -> DD:
        """Multiply.

        Args:
            other: The other value.

        Returns:
            The product.
        """
        var p = self.hi * other.hi
        var e = fma(self.hi, other.hi, -p)
        e += self.hi * other.lo + self.lo * other.hi
        return DD._quick(p, e)

    def __truediv__(self, other: DD) -> DD:
        """Divide.

        Args:
            other: The divisor.

        Returns:
            The quotient.
        """
        var q1 = self.hi / other.hi
        var r = self - other * DD(q1)
        var q2 = r.hi / other.hi
        r = r - other * DD(q2)
        var q3 = r.hi / other.hi
        return DD._quick(q1, q2) + DD(q3)

    def __lt__(self, other: DD) -> Bool:
        """Compare.

        Args:
            other: The other value.

        Returns:
            True when this value is less.
        """
        return self.hi < other.hi or (
            self.hi == other.hi and self.lo < other.lo
        )

    def __le__(self, other: DD) -> Bool:
        """Compare.

        Args:
            other: The other value.

        Returns:
            True when this value is less or equal.
        """
        return not other < self

    def __gt__(self, other: DD) -> Bool:
        """Compare.

        Args:
            other: The other value.

        Returns:
            True when this value is greater.
        """
        return other < self

    def __ge__(self, other: DD) -> Bool:
        """Compare.

        Args:
            other: The other value.

        Returns:
            True when this value is greater or equal.
        """
        return not self < other


def smaller(a: DD, b: DD) -> DD:
    """Return `min(a, b)`.

    Args:
        a: The first value.
        b: The second value.

    Returns:
        The smaller value.
    """
    return b if b < a else a


def larger(a: DD, b: DD) -> DD:
    """Return `max(a, b)`.

    Args:
        a: The first value.
        b: The second value.

    Returns:
        The larger value.
    """
    return b if b > a else a


@fieldwise_init
struct V3(ImplicitlyCopyable, Movable):
    """A double-double vector."""

    var x: DD
    """The first coordinate."""
    var y: DD
    """The second coordinate."""
    var z: DD
    """The third coordinate."""

    def __add__(self, other: V3) -> V3:
        """Add.

        Args:
            other: The other vector.

        Returns:
            The sum.
        """
        return V3(self.x + other.x, self.y + other.y, self.z + other.z)

    def __sub__(self, other: V3) -> V3:
        """Subtract.

        Args:
            other: The other vector.

        Returns:
            The difference.
        """
        return V3(self.x - other.x, self.y - other.y, self.z - other.z)

    def scaled(self, value: DD) -> V3:
        """Multiply each coordinate.

        Args:
            value: The factor.

        Returns:
            The scaled vector.
        """
        return V3(self.x * value, self.y * value, self.z * value)


def dot(a: V3, b: V3) -> DD:
    """Return the dot product.

    Args:
        a: The first vector.
        b: The second vector.

    Returns:
        The dot product.
    """
    return a.x * b.x + a.y * b.y + a.z * b.z


def cross(a: V3, b: V3) -> V3:
    """Return the cross product.

    Args:
        a: The first vector.
        b: The second vector.

    Returns:
        The cross product.
    """
    return V3(
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x,
    )


def vector(values: List[Float64]) -> V3:
    """Hold three doubles exactly.

    Args:
        values: The coordinates.

    Returns:
        The vector.
    """
    return V3(DD(values[0]), DD(values[1]), DD(values[2]))


def nearest_sq(point: V3, triangle: List[V3]) -> DD:
    """Return the squared distance from a point to a solid triangle.

    Args:
        point: The point.
        triangle: The three corners.

    Returns:
        The squared distance.
    """
    var a = triangle[0]
    var normal = cross(triangle[1] - a, triangle[2] - a)
    var normal_sq = dot(normal, normal)
    var height = dot(point - a, normal)
    var projected = point - normal.scaled(height / normal_sq)
    var inside = True
    for index in range(3):
        var x = triangle[index]
        var y = triangle[(index + 1) % 3]
        if dot(cross(y - x, projected - x), normal) < DD(0.0):
            inside = False
    if inside:
        return height * height / normal_sq
    var best = DD(0.0)
    for index in range(3):
        var x = triangle[index]
        var edge = triangle[(index + 1) % 3] - x
        var fraction = larger(
            DD(0.0),
            smaller(DD(1.0), dot(point - x, edge) / dot(edge, edge)),
        )
        var offset = point - (x + edge.scaled(fraction))
        var distance = dot(offset, offset)
        if index == 0 or distance < best:
            best = distance
    return best


@fieldwise_init
struct Case(Copyable, Movable):
    """One swept sphere and triangle."""

    var start: List[Float64]
    """The sphere's start center."""
    var travel: List[Float64]
    """The sphere's motion."""
    var radius: Float64
    """The sphere's radius."""
    var triangle: List[List[Float64]]
    """The triangle's three corners."""


comptime MISS = -1.0
"""The oracle's answer for a miss."""
comptime INSIDE = -2.0
"""The oracle's answer for an initial overlap."""


def oracle(item: Case) -> Float64:
    """Return the first time the sphere touches the triangle's front.

    Args:
        item: The case.

    Returns:
        The entry time in [0, 1], `MISS` or `INSIDE`.
    """
    var start = vector(item.start)
    var travel = vector(item.travel)
    var radius = DD(item.radius)
    var triangle: List[V3] = [
        vector(item.triangle[0]),
        vector(item.triangle[1]),
        vector(item.triangle[2]),
    ]
    var normal = cross(triangle[1] - triangle[0], triangle[2] - triangle[0])
    var height = dot(start - triangle[0], normal)
    if height < DD(0.0):
        return MISS
    var radius_sq = radius * radius
    if nearest_sq(start, triangle) <= radius_sq:
        return INSIDE
    var high = DD(1.0)
    var normal_travel = dot(travel, normal)
    if normal_travel < DD(0.0):
        high = smaller(high, -height / normal_travel)
    var low = DD(0.0)
    var two = DD(2.0)
    var three = DD(3.0)
    for _ in range(170):
        var first = (two * low + high) / three
        var second = (low + two * high) / three
        if nearest_sq(start + travel.scaled(first), triangle) < nearest_sq(
            start + travel.scaled(second), triangle
        ):
            high = second
        else:
            low = first
    var middle = (low + high) / two
    if nearest_sq(start + travel.scaled(middle), triangle) >= radius_sq - DD(
        1e-40
    ):
        return MISS
    low = DD(0.0)
    high = middle
    for _ in range(150):
        middle = (low + high) / two
        if nearest_sq(start + travel.scaled(middle), triangle) > radius_sq:
            low = middle
        else:
            high = middle
    return high.hi + high.lo


def _uniform(
    mut random: PythonRandom, a: Float64, b: Float64
) raises -> Float64:
    """Return `random.uniform(a, b)`: a + (b - a) * random(), rounded twice."""
    # An exact product, rounded once, stops a fused multiply-add.
    var product = (
        Fraction.from_float(b - a) * Fraction.from_float(random.random())
    ).to_float()
    return a + product


def _f32(value: Float64) -> Float64:
    """Round to Float32 as `struct.pack("f")` does."""
    return Float64(Float32(value))


def fixtures() raises -> Tuple[List[Case], List[Float64]]:
    """Return the entering hits of 500 seeded cases and their entry times.

    Returns:
        The cases and their entry times.

    Raises:
        Error: If the arithmetic fails.
    """
    var random = PythonRandom(292)
    var cases = List[Case]()
    var times = List[Float64]()
    for _ in range(500):
        var triangle = List[List[Float64]]()
        for _ in range(3):
            var point = List[Float64]()
            for _ in range(3):
                point.append(
                    Float64(random.randrange(BigInt(-10), BigInt(11)).to_int())
                )
            triangle.append(point^)
        var corners: List[V3] = [
            vector(triangle[0]),
            vector(triangle[1]),
            vector(triangle[2]),
        ]
        var normal = cross(corners[1] - corners[0], corners[2] - corners[0])
        if dot(normal, normal).hi == 0.0:
            continue
        var start = List[Float64]()
        for _ in range(3):
            start.append(_f32(_uniform(random, -12.0, 12.0)))
        var travel = List[Float64]()
        for _ in range(3):
            travel.append(_f32(_uniform(random, -25.0, 25.0)))
        var radius = _f32(_uniform(random, 0.1, 3.0))
        var item = Case(start^, travel^, radius, triangle^)
        var expected = oracle(item)
        if expected < 0.0:
            continue
        cases.append(item^)
        times.append(expected)
    return (cases^, times^)


def render(cases: List[Case], times: List[Float64]) -> String:
    """Return the fixtures as JSON, without feature labels.

    Args:
        cases: The cases.
        times: Their entry times.

    Returns:
        The JSON text.
    """
    var out = JsonWriter()
    out.begin_array()
    for index in range(len(cases)):
        ref item = cases[index]
        out.begin_object()
        out.key("start")
        out.begin_array()
        for value in item.start:
            out.number(value)
        out.end()
        out.key("travel")
        out.begin_array()
        for value in item.travel:
            out.number(value)
        out.end()
        out.key("radius")
        out.number(item.radius)
        out.key("triangle")
        out.begin_array()
        for point in item.triangle:
            out.begin_array()
            for value in point:
                out.number(value)
            out.end()
        out.end()
        out.key("expected")
        out.number(times[index])
        out.end()
    out.end()
    return out.text()


def _without_labels(text: String) -> List[String]:
    """Return the tokens of a fixture file without its feature labels.

    Feature labels are descriptive metadata. Every geometric input and
    expected time is reproduced independently of them.
    """
    var found = json_tokens(text)[0].copy()
    var kept = List[String]()
    var index = 0
    while index < len(found):
        if (
            found[index] == '"feature"'
            and index + 2 < len(found)
            and found[index + 1] == ":"
            and len(kept) > 0
            and kept[len(kept) - 1] == ","
        ):
            _ = kept.pop()
            index += 3
            continue
        kept.append(found[index])
        index += 1
    return kept^


def check(path: String) raises -> Tuple[Int, String]:
    """Compare a fixture file with the oracle.

    Args:
        path: The fixture file.

    Returns:
        The exit status and the report.

    Raises:
        Error: If the file cannot be read.
    """
    var built = fixtures()
    var expected = json_tokens(render(built[0], built[1]))[0].copy()
    if _without_labels(Path(path).read_text()) != expected:
        return (1, "CCD reference fixture mismatch\n")
    return (
        0,
        String(len(built[0]))
        + " independent double-double CCD references reproduced\n",
    )


def main() raises:
    var given = argv()
    if len(given) != 3 or String(given[1]) != "--check":
        print("usage: physics_ccd_reference --check FIXTURE", file=stderr)
        exit(2)
    var outcome = check(String(given[2]))
    if outcome[0] != 0:
        print(outcome[1], end="", file=stderr)
    else:
        print(outcome[1], end="")
    exit(outcome[0])
