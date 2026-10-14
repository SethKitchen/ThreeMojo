# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Independent Float64 oracle: projected face solve and all segment candidates.

    mojo run -I . --fp-mode contract=off tools/reference_octree_contacts.mojo

No production Mojo code or three.js arithmetic is imported. The candidate
order is an unchanged broadphase fixture from `tests/test_octree.mojo`. The
tool prints, as JSON, each query's final push and the contact of each
triangle that moved the shape.

The output is the same, to the last digit, as the Python oracle's that it
replaces. Three things make it so:

- `--fp-mode contract=off`: by default Mojo fuses `a + b * c` into one
  rounding, and Python rounds twice.
- `py_sum` adds as CPython 3.12's `sum` does, with Neumaier's compensation.
- Each coordinate remembers whether Python held it as an int, because `sum`
  adds an int item without compensation.
"""

from std.math import isinf, isnan, sqrt
from std.testing import assert_true

from tools._json_tools import JsonWriter


@fieldwise_init
struct Vec(Copyable, Movable):
    """A point or a direction. Each coordinate remembers whether the Python
    oracle held it as an int, because Python's `sum` adds ints and floats
    differently."""

    var x: Float64
    """The first coordinate."""
    var y: Float64
    """The second coordinate."""
    var z: Float64
    """The third coordinate."""
    var ix: Bool
    """True when the first coordinate is an int."""
    var iy: Bool
    """True when the second coordinate is an int."""
    var iz: Bool
    """True when the third coordinate is an int."""

    def __init__(out self, x: Float64, y: Float64, z: Float64):
        """Make a vector of floats.

        Args:
            x: The first coordinate.
            y: The second coordinate.
            z: The third coordinate.
        """
        self.x = x
        self.y = y
        self.z = z
        self.ix = False
        self.iy = False
        self.iz = False

    def at(self, index: Int) -> Float64:
        """Return one coordinate.

        Args:
            index: 0, 1 or 2.

        Returns:
            The coordinate.
        """
        if index == 0:
            return self.x
        if index == 1:
            return self.y
        return self.z

    def is_int(self, index: Int) -> Bool:
        """Return whether one coordinate is an int.

        Args:
            index: 0, 1 or 2.

        Returns:
            True for an int.
        """
        if index == 0:
            return self.ix
        if index == 1:
            return self.iy
        return self.iz


def ints(
    x: Float64, y: Float64, z: Float64, ix: Bool, iy: Bool, iz: Bool
) -> Vec:
    """Return a vector whose marked coordinates are ints. An int has no
    negative zero."""
    return Vec(
        x + 0.0 if ix else x,
        y + 0.0 if iy else y,
        z + 0.0 if iz else z,
        ix,
        iy,
        iz,
    )


def whole(x: Float64, y: Float64, z: Float64) -> Vec:
    """Return a vector of ints."""
    return ints(x, y, z, True, True, True)


def add(a: Vec, b: Vec) -> Vec:
    """Return a + b."""
    return ints(
        a.x + b.x,
        a.y + b.y,
        a.z + b.z,
        a.ix and b.ix,
        a.iy and b.iy,
        a.iz and b.iz,
    )


def sub(a: Vec, b: Vec) -> Vec:
    """Return a - b."""
    return ints(
        a.x - b.x,
        a.y - b.y,
        a.z - b.z,
        a.ix and b.ix,
        a.iy and b.iy,
        a.iz and b.iz,
    )


def mul(a: Vec, t: Float64, t_int: Bool = False) -> Vec:
    """Return a * t, where t is an int when `t_int` is set."""
    return ints(
        a.x * t,
        a.y * t,
        a.z * t,
        a.ix and t_int,
        a.iy and t_int,
        a.iz and t_int,
    )


def py_sum(values: List[Float64], kinds: List[Bool]) -> Tuple[Float64, Bool]:
    """Sum as CPython 3.12's `sum` does from its start of int zero.

    Ints add exactly until the first float. Then each float item is added
    with Neumaier's compensation, an int item is added plainly, and the
    compensation is added once at the end when it is finite and not zero.

    Args:
        values: The items.
        kinds: True for each item that is an int.

    Returns:
        The sum, and whether it is an int.
    """
    var total = 0.0
    var index = 0
    while index < len(values) and kinds[index]:
        total += values[index]
        index += 1
    if index == len(values):
        return (total + 0.0, True)
    total = total + values[index]
    var compensation = 0.0
    index += 1
    while index < len(values):
        var x = values[index]
        if kinds[index]:
            total += x
        else:
            var t = total + x
            if abs(total) >= abs(x):
                compensation += (total - t) + x
            else:
                compensation += (x - t) + total
            total = t
        index += 1
    if (
        compensation != 0
        and not isinf(compensation)
        and not isnan(compensation)
    ):
        total += compensation
    return (total, False)


def dot_kind(a: Vec, b: Vec) -> Tuple[Float64, Bool]:
    """Return a . b as the Python oracle's `sum` gives it, and whether it is
    an int."""
    return py_sum(
        [a.x * b.x, a.y * b.y, a.z * b.z],
        [a.ix and b.ix, a.iy and b.iy, a.iz and b.iz],
    )


def dot(a: Vec, b: Vec) -> Float64:
    """Return a . b as the Python oracle's `sum` gives it."""
    return dot_kind(a, b)[0]


def cross(a: Vec, b: Vec) -> Vec:
    """Return a x b."""
    return ints(
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x,
        a.iy and b.iz and a.iz and b.iy,
        a.iz and b.ix and a.ix and b.iz,
        a.ix and b.iy and a.iy and b.ix,
    )


def length(a: Vec) -> Float64:
    """Return |a|."""
    return sqrt(dot(a, a))


def unit(a: Vec) -> Vec:
    """Return a / |a|, or a itself when it is zero."""
    if length(a) != 0:
        return mul(a, 1 / length(a))
    return a.copy()


def clamp(a: Float64) -> Tuple[Float64, Bool]:
    """Return a limited to [0, 1]. A limit is the int 0 or 1, as Python's
    `max(0, min(1, a))` returns it."""
    if not a < 1:
        return (1.0, True)
    if not a > 0:
        return (0.0, True)
    return (a, False)


def near_segment(p: Vec, a: Vec, b: Vec) -> Vec:
    """Return the point of segment ab nearest to p."""
    var d = sub(b, a)
    if dot(d, d) != 0:
        var limited = clamp(dot(sub(p, a), d) / dot(d, d))
        return add(a, mul(d, limited[0], limited[1]))
    return a.copy()


def segments(a: Vec, b: Vec, c: Vec, d: Vec) -> Tuple[Vec, Vec]:
    """Return the nearest points of segments ab and cd: the minimum of the
    convex squared gap on all four boundaries and its interior."""
    var u = sub(b, a)
    var v = sub(d, c)
    var r = sub(a, c)
    var candidates: List[Tuple[Vec, Vec]] = [
        (a.copy(), near_segment(a, c, d)),
        (b.copy(), near_segment(b, c, d)),
        (near_segment(c, a, b), c.copy()),
        (near_segment(d, a, b), d.copy()),
    ]
    var A = dot(u, u)
    var B = dot(u, v)
    var C = dot(v, v)
    var D = dot(u, r)
    var E = dot(v, r)
    var det = A * C - B * B
    if det > 0:
        var s = (B * E - C * D) / det
        var t = (A * E - B * D) / det
        if s >= 0 and s <= 1 and t >= 0 and t <= 1:
            candidates.append((add(a, mul(u, s)), add(c, mul(v, t))))
    var best = 0
    for index in range(1, len(candidates)):
        var gap = sub(candidates[index][0], candidates[index][1])
        var known = sub(candidates[best][0], candidates[best][1])
        if dot(gap, gap) < dot(known, known):
            best = index
    return (candidates[best][0].copy(), candidates[best][1].copy())


@fieldwise_init
struct Face(Copyable, Movable):
    """A point projected on a triangle's plane."""

    var inside: Bool
    """True when the projection is inside the triangle."""
    var normal: Vec
    """The triangle's unit normal."""
    var height: Float64
    """The point's signed height over the plane."""


def face(t: List[Vec], p: Vec) -> Face:
    """Project a point on a triangle's plane, and solve in the two axes the
    normal is least along."""
    var a = t[0].copy()
    var u = sub(t[1], a)
    var v = sub(t[2], a)
    var n = unit(cross(u, v))
    var z = dot(n, sub(p, a))
    var projected = sub(p, mul(n, z))
    var k = 0
    for index in range(1, 3):
        if abs(n.at(index)) > abs(n.at(k)):
            k = index
    var i = 1 if k == 0 else 0
    var j = 1 if k == 2 else 2
    var q = sub(projected, a)
    var den = u.at(i) * v.at(j) - u.at(j) * v.at(i)
    if den == 0:
        return Face(False, n^, z)
    var s = (q.at(i) * v.at(j) - q.at(j) * v.at(i)) / den
    var w = (u.at(i) * q.at(j) - u.at(j) * q.at(i)) / den
    return Face(s >= 0 and w >= 0 and s + w <= 1, n^, z)


def _edge(t: List[Vec], p: Vec) -> Vec:
    """Return the point of the triangle's edges nearest to p."""
    var nearest = near_segment(p, t[0], t[1])
    for index in range(1, 3):
        var q = near_segment(p, t[index], t[(index + 1) % 3])
        if dot(sub(p, q), sub(p, q)) < dot(sub(p, nearest), sub(p, nearest)):
            nearest = q^
    return nearest^


def sphere(t: List[Vec], p: Vec, r: Float64) -> Optional[Tuple[Vec, Float64]]:
    """Return a sphere's contact normal and depth against a triangle."""
    var hit = face(t, p)
    if abs(hit.height) > r:
        return None
    if hit.inside:
        return (hit.normal.copy(), r - hit.height)
    var delta = sub(p, _edge(t, p))
    var dist = length(delta)
    if dist <= r:
        return (unit(delta), r - dist)
    return None


def capsule(
    t: List[Vec], a: Vec, b: Vec, r: Float64
) -> Optional[Tuple[Vec, Float64]]:
    """Return a capsule's contact normal and depth against a triangle."""
    var start = face(t, a)
    var end = face(t, b)
    var d1 = start.height - r
    var d2 = end.height - r
    if min(d1, d2) > 0 or max(start.height, end.height) < 0:
        return None
    var span = abs(d1) + abs(d2)
    # With no span, the Python oracle's fraction is the int 0.
    var frac = abs(d1) / span if span != 0 else 0.0
    var p = add(a, mul(sub(b, a), frac, span == 0))
    if face(t, p).inside:
        return (start.normal.copy(), abs(min(d1, d2)))
    for i in range(3):
        var pair = segments(a, b, t[i], t[(i + 1) % 3])
        var delta = sub(pair[0], pair[1])
        var dist = length(delta)
        if dist <= r:
            return (unit(delta), r - dist)
    return None


def _height(i: Int, j: Int) -> Float64:
    """Return the height of one grid corner."""
    return Float64((i * 7 + j * 3) % 5) * 0.25


def level() -> List[List[Vec]]:
    """Return the fixture's triangles: a 6 by 6 height grid and a wall."""
    var out = List[List[Vec]]()
    for i in range(6):
        for j in range(6):
            # The grid's x and z are ints in the Python oracle.
            var a = ints(
                Float64(i - 3), _height(i, j), Float64(j - 3), True, False, True
            )
            var b = ints(
                Float64(i - 3),
                _height(i, j + 1),
                Float64(j - 2),
                True,
                False,
                True,
            )
            var c = ints(
                Float64(i - 2),
                _height(i + 1, j + 1),
                Float64(j - 2),
                True,
                False,
                True,
            )
            var d = ints(
                Float64(i - 2),
                _height(i + 1, j),
                Float64(j - 3),
                True,
                False,
                True,
            )
            out.append([a.copy(), b.copy(), c.copy()])
            out.append([a^, c^, d^])
    out.append([whole(2, 0, -2), whole(2, 3, -2), whole(2, 3, 2)])
    out.append([whole(2, 0, -2), whole(2, 3, 2), whole(2, 0, 2)])
    return out^


@fieldwise_init
struct Query(Copyable, Movable):
    """One shape and its broadphase candidates, in order."""

    var name: String
    """The query's name."""
    var capsule: Bool
    """True for a capsule, False for a sphere."""
    var a: Vec
    """The center, or the capsule's start."""
    var b: Vec
    """The capsule's end."""
    var radius: Float64
    """The radius."""
    var indices: List[Int]
    """The candidate triangles, in broadphase order."""


def queries() -> List[Query]:
    """Return the fixture's queries."""
    var none = Vec(0, 0, 0)
    return [
        Query(
            "sphere_ground",
            False,
            Vec(0.3, 0.3, 0.2),
            none.copy(),
            0.5,
            [
                14,
                15,
                16,
                17,
                26,
                27,
                28,
                29,
                31,
                30,
                40,
                41,
                52,
                38,
                39,
                50,
                53,
                43,
                42,
                54,
                55,
                33,
                44,
                45,
            ],
        ),
        Query(
            "sphere_shallow",
            False,
            Vec(0.3, 0.3, 0.2),
            none.copy(),
            0.5,
            [29, 28, 31, 30, 40, 41, 52, 42, 43, 54, 55],
        ),
        Query(
            "sphere_wall",
            False,
            ints(1.7, 1, 0, False, True, True),
            none.copy(),
            0.5,
            [
                52,
                41,
                40,
                27,
                38,
                39,
                50,
                53,
                73,
                64,
                62,
                63,
                65,
                72,
                55,
                54,
                43,
                30,
                31,
                33,
                42,
                44,
                45,
                66,
                67,
                69,
            ],
        ),
        Query(
            "capsule_ground",
            True,
            Vec(0.3, 0.2, 0.2),
            Vec(0.3, 1.2, 0.2),
            0.35,
            [
                14,
                15,
                16,
                17,
                26,
                27,
                28,
                29,
                31,
                30,
                40,
                41,
                38,
                39,
                50,
                52,
                53,
                43,
                42,
                33,
                44,
                45,
                55,
                73,
                72,
            ],
        ),
        Query(
            "capsule_wall",
            True,
            Vec(1.8, 0.8, 0.1),
            Vec(1.8, 1.8, 0.1),
            0.3,
            [73, 64, 53, 52, 62, 63, 65, 72, 66, 55, 54, 67, 69],
        ),
        Query(
            "capsule_slope",
            True,
            Vec(-1.2, 0.3, -1.4),
            ints(-0.4, 0.5, -1, False, False, True),
            0.3,
            [12, 13, 14, 15, 24, 25, 26, 27, 16, 17, 28, 29],
        ),
    ]


def _vector(mut writer: JsonWriter, v: Vec):
    """Write a vector as a JSON list."""
    writer.begin_array()
    writer.number(v.x)
    writer.number(v.y)
    writer.number(v.z)
    writer.end()


def report() -> String:
    """Run every query, and return the JSON report.

    Returns:
        Each query's push normal and depth, and the trace of the triangles
        that moved it.
    """
    var triangles = level()
    var writer = JsonWriter()
    writer.begin_object()
    for query in queries():
        var a = query.a.copy()
        var b = query.b.copy()
        var original = a.copy()
        writer.key(query.name)
        writer.begin_object()
        var steps = List[Tuple[Int, Vec, Float64, Vec]]()
        for index in query.indices:
            var hit = capsule(
                triangles[index], a, b, query.radius
            ) if query.capsule else sphere(triangles[index], a, query.radius)
            if hit:
                var n = hit.value()[0].copy()
                var depth = hit.value()[1]
                var offset = mul(n, depth)
                a = add(a, offset)
                if query.capsule:
                    b = add(b, offset)
                steps.append((index, n^, depth, a.copy()))
        var push = sub(a, original)
        writer.key("normal")
        _vector(writer, unit(push))
        writer.key("depth")
        writer.number(length(push))
        writer.key("trace")
        writer.begin_array()
        for step in steps:
            writer.begin_object()
            writer.key("triangle")
            writer.integer(step[0])
            writer.key("normal")
            _vector(writer, step[1])
            writer.key("depth")
            writer.number(step[2])
            writer.key("moved_start")
            _vector(writer, step[3])
            writer.end()
        writer.end()
        writer.end()
    writer.end()
    return writer.text()


def self_check() raises:
    """Check the segment solver and an edge contact against known answers.

    Raises:
        Error: If either answer is wrong.
    """
    var pair = segments(
        whole(0, 0, 0), whole(1, 0, 0), whole(2, -1, 0), whole(3, 1, 0)
    )
    var a = pair[0].copy()
    var b = pair[1].copy()
    for index in range(3):
        assert_true(abs(a.at(index) - Vec(1, 0, 0).at(index)) < 1e-14)
        assert_true(abs(b.at(index) - Vec(2.2, -0.6, 0).at(index)) < 1e-14)
    assert_true(abs(dot(sub(a, b), sub(a, b)) - 1.8) < 1e-14)
    var edge = sphere(
        [whole(0, 0, 0), whole(0, 0, 1), whole(1, 0, 0)],
        ints(-0.1, 0, 0.5, False, True, False),
        0.3,
    )
    assert_true(Bool(edge))
    var normal = edge.value()[0].copy()
    assert_true(normal.x == -1 and normal.y == 0 and normal.z == 0)
    assert_true(abs(edge.value()[1] - 0.2) < 1e-14)


def main() raises:
    var text = report()
    self_check()
    print(text)
