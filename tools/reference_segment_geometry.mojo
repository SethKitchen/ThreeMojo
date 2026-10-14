# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Independent exact projection and clipped-interval oracle from Float32 bits.

    mojo run -I . --fp-mode contract=off tools/reference_segment_geometry.mojo [--stress N]

uses exact fractions, not the production polynomial expansion. It verifies
the words and expected values retained in
`tests/test_carla_rtree_numerics.mojo`, then checks a Float64 model of the
adaptive guards, and prints a JSON summary. It does not replace native
compilation or tests.

The cases are those of the Python oracle this tool replaces, from
`random.Random(589)`. Built with `--fp-mode contract=off`, the summary is
the Python oracle's to the last digit; see `tools/_python_math.mojo`.
"""

from std.memory import bitcast
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._bigint import BigInt
from tools._fraction import Fraction
from tools._json_tools import JsonWriter
from tools._python_float import parse_float
from tools._python_math import float_sum
from tools._python_random import PythonRandom

comptime FIXTURE = "tests/test_carla_rtree_numerics.mojo"
"""The native suite whose retained words this oracle checks."""

comptime Exact = List[Fraction]
comptime Vec = SIMD[DType.float64, 4]
comptime Triple = Tuple[Float64, Float64, Float64]


def bits(x: Float64) raises -> UInt32:
    """Return the Float32 bits of a double, rounded as `struct.pack('<f')`.

    Args:
        x: The double.

    Returns:
        The bits.

    Raises:
        Error: If a finite value rounds past the Float32 range.
    """
    var narrow = Float32(x)
    if narrow != narrow:
        return bitcast[DType.uint32](narrow)
    if (narrow - narrow != 0) and (x - x == 0):
        raise Error("float too large to pack with f format")
    return bitcast[DType.uint32](narrow)


def val(word: UInt32) -> Float64:
    """Return the double equal to Float32 bits."""
    return Float64(bitcast[DType.float32](word))


def _vec(raw: List[UInt32], start: Int) raises -> Exact:
    """Return three words as exact values."""
    return [
        Fraction.from_float(val(raw[start])),
        Fraction.from_float(val(raw[start + 1])),
        Fraction.from_float(val(raw[start + 2])),
    ]


def _floats(raw: List[UInt32], start: Int) -> Vec:
    """Return three words as doubles."""
    return Vec(val(raw[start]), val(raw[start + 1]), val(raw[start + 2]), 0)


def _sub(a: Exact, b: Exact) raises -> Exact:
    """Return a - b."""
    return [a[0] - b[0], a[1] - b[1], a[2] - b[2]]


def _dot(a: Exact, b: Exact) raises -> Fraction:
    """Return a . b."""
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def distance(raw: List[UInt32]) raises -> Fraction:
    """Return the exact squared distance from p to segment ab.

    Args:
        raw: The nine Float32 words of a, b and p.

    Returns:
        The squared distance.
    """
    var a = _vec(raw, 0)
    var b = _vec(raw, 3)
    var p = _vec(raw, 6)
    var d = _sub(b, a)
    var u = _sub(p, a)
    var dd = _dot(d, d)
    if dd.is_zero():
        return _dot(u, u)
    var t = _dot(u, d) / dd
    if t > Fraction(1):
        t = Fraction(1)
    if t < Fraction(0):
        t = Fraction(0)
    var residual: Exact = [u[0] - t * d[0], u[1] - t * d[1], u[2] - t * d[2]]
    return _dot(residual, residual)


def slab(raw: List[UInt32]) raises -> Bool:
    """Return whether segment ab meets the box [lo, hi], exactly.

    Args:
        raw: The twelve Float32 words of a, b, lo and hi.

    Returns:
        True when the clipped parameter interval is not empty.
    """
    var a = _vec(raw, 0)
    var b = _vec(raw, 3)
    var lo = _vec(raw, 6)
    var hi = _vec(raw, 9)
    var near = Fraction(0)
    var far = Fraction(1)
    for i in range(3):
        var x = a[i].copy()
        var y = b[i].copy()
        var l = lo[i].copy()
        var h = hi[i].copy()
        if l > h:
            return False
        if x == y:
            if x < l or x > h:
                return False
        else:
            var t1 = (l - x) / (y - x)
            var t2 = (h - x) / (y - x)
            if t2 < t1:
                var swap = t1^
                t1 = t2^
                t2 = swap^
            if t1 > near:
                near = t1^
            if t2 < far:
                far = t2^
            if near > far:
                return False
    return True


def _exact(v: Vec) raises -> Exact:
    """Return a vector's first three lanes exactly."""
    return [
        Fraction.from_float(v[0]),
        Fraction.from_float(v[1]),
        Fraction.from_float(v[2]),
    ]


def norm(v: Vec) -> Float64:
    """Return v0*v0 + v1*v1 + v2*v2, added left to right."""
    return v[0] * v[0] + v[1] * v[1] + v[2] * v[2]


def exact_f32_difference(a: Float64, b: Float64, difference: Float64) -> Bool:
    """Return whether a Float32 difference is exact and in range."""
    if a == 0 or b == 0:
        return True
    if max(abs(a), abs(b)) > Float64(1 << 28) * min(abs(a), abs(b)):
        return False
    try:
        return val(bits(difference)) == difference
    except:
        return False


def _count(mut paths: Dict[String, Int], path: String):
    """Count one use of a path, keeping the first order of use."""
    paths[path] = paths.get(path).or_else(0) + 1


def _less(a: Vec, b: Vec) -> Bool:
    """Return whether a tuple is below another, as Python orders tuples."""
    for i in range(3):
        if a[i] != b[i]:
            return a[i] < b[i]
    return False


def _py_max3(a: Float64, b: Float64) -> Float64:
    """Return `max(a, b, 0)` as Python picks it: the first largest."""
    var best = a
    if b > best:
        best = b
    if 0.0 > best:
        best = 0.0
    return best


def model(raw: List[UInt32], mut paths: Dict[String, Int]) raises -> Float64:
    """Return the Float64 model's squared distance, and count its path.

    Args:
        raw: The nine Float32 words of a, b and p.
        paths: Each path and how often it was taken.

    Returns:
        The model's squared distance.
    """
    var a = _floats(raw, 0)
    var b = _floats(raw, 3)
    var p = _floats(raw, 6)
    if _less(b, a):
        var swap = a
        a = b
        b = swap
    var ab = b - a
    var ap = p - a
    var bp = p - b
    var da = float_sum([ap[0] * ab[0], ap[1] * ab[1], ap[2] * ab[2]])
    var magnitude = float_sum(
        [abs(ap[0] * ab[0]), abs(ap[1] * ab[1]), abs(ap[2] * ab[2])]
    )
    var ga = 2.0**-49 * magnitude
    var end_dot = da - norm(ab)
    var end_guard = 2.0**-48 * (magnitude + norm(ab))
    var r: Float64
    var path: String
    if norm(ab) == 0:
        r = norm(ap)
        path = "point"
    elif ga == 0 or da < -ga:
        r = norm(ap)
        path = "start"
    elif end_dot > end_guard:
        r = norm(bp)
        path = "end"
    else:
        var cross = List[Float64]()
        var scale = List[Float64]()
        for i in range(3):
            var j = (i + 1) % 3
            var k = (i + 2) % 3
            var left = ap[j] * ab[k]
            var right = ap[k] * ab[j]
            cross.append(left - right)
            scale.append(abs(left) + abs(right))
        var cross_vec = Vec(cross[0], cross[1], cross[2], 0)
        var scale_vec = Vec(scale[0], scale[1], scale[2], 0)
        if (
            da > ga
            and end_dot < -end_guard
            and norm(cross_vec) >= 2.0**-12 * norm(scale_vec)
        ):
            r = norm(cross_vec) / norm(ab)
            path = "interior"
        else:
            var af = _exact(a)
            var bf = _exact(b)
            var pf = _exact(p)
            var df = _sub(bf, af)
            var uf = _sub(pf, af)
            var vf = _sub(pf, bf)
            var local = True
            for i in range(3):
                if not (
                    exact_f32_difference(a[i], b[i], ab[i])
                    and exact_f32_difference(a[i], p[i], ap[i])
                ):
                    local = False
                    break
            if local:
                for i in range(3):
                    if (
                        Fraction.from_float(ab[i]) != df[i]
                        or Fraction.from_float(ap[i]) != uf[i]
                    ):
                        raise Error("a local difference is not exact")
            if _dot(uf, df) <= Fraction(0):
                r = norm(ap)
            elif _dot(vf, df) >= Fraction(0):
                r = norm(bp)
            elif local:
                r = norm(cross_vec) / norm(ab)
            else:
                var c = List[Float64]()
                for i in range(3):
                    var j = (i + 1) % 3
                    var k = (i + 2) % 3
                    c.append((uf[j] * df[k] - uf[k] * df[j]).to_float())
                r = norm(Vec(c[0], c[1], c[2], 0)) / _dot(df, df).to_float()
            path = "local" if local else "exact"
    var gap = Vec(
        _py_max3(min(a[0], b[0]) - p[0], p[0] - max(a[0], b[0])),
        _py_max3(min(a[1], b[1]) - p[1], p[1] - max(a[1], b[1])),
        _py_max3(min(a[2], b[2]) - p[2], p[2] - max(a[2], b[2])),
        0,
    )
    var floor = norm(gap)
    if floor > r:
        r = floor
    _count(paths, path)
    return r


def parameter_before(
    a: Vec, b: Vec, mut slab_paths: Dict[String, Int]
) raises -> Bool:
    """Return whether clip parameter a is before b, exactly when needed."""
    if a[1] == b[1] and a[2] == b[2]:
        return a[0] < b[0]
    var left = (a[0] - a[1]) * (b[2] - b[1])
    var right = (b[0] - b[1]) * (a[2] - a[1])
    var difference = left - right
    if abs(difference) > 2.0**-49 * (abs(left) + abs(right)):
        _count(slab_paths, "fast")
        return difference < 0
    _count(slab_paths, "exact")
    var ea = _exact(a)
    var eb = _exact(b)
    return (ea[0] - ea[1]) * (eb[2] - eb[1]) < (eb[0] - eb[1]) * (ea[2] - ea[1])


def slab_model(
    raw: List[UInt32], mut slab_paths: Dict[String, Int]
) raises -> Bool:
    """Return the Float64 model's answer to `slab`."""
    var a = _floats(raw, 0)
    var b = _floats(raw, 3)
    var lo = _floats(raw, 6)
    var hi = _floats(raw, 9)
    var near = Vec(0.0, 0.0, 1.0, 0)
    var far = Vec(1.0, 0.0, 1.0, 0)
    for i in range(3):
        var x = a[i]
        var y = b[i]
        var l = lo[i]
        var h = hi[i]
        var first = min(x, y)
        var last = max(x, y)
        if last < l or first > h:
            return False
        if first >= l and last <= h:
            continue
        var low = Vec(0.0, 0.0, 1.0, 0)
        var high = Vec(1.0, 0.0, 1.0, 0)
        if x < y:
            if l > x:
                low = Vec(l, x, y, 0)
            if h < y:
                high = Vec(h, x, y, 0)
        else:
            if h < x:
                low = Vec(-h, -x, -y, 0)
            if l > y:
                high = Vec(-l, -x, -y, 0)
        if parameter_before(near, low, slab_paths):
            near = low
        if parameter_before(high, far, slab_paths):
            far = high
        if parameter_before(far, near, slab_paths):
            return False
    return True


@fieldwise_init
struct Case(Copyable, Movable):
    """A named list of Float32 words."""

    var name: String
    """The case's name."""
    var raw: List[UInt32]
    """The words."""


def _raw(points: List[Triple]) raises -> List[UInt32]:
    """Return the Float32 bits of points."""
    var words = List[UInt32]()
    for p in points:
        words.append(bits(p[0]))
        words.append(bits(p[1]))
        words.append(bits(p[2]))
    return words^


def _word(mut rng: PythonRandom) -> UInt32:
    """Draw one Float32 word of any sign and finite exponent."""
    var sign = rng.randrange(BigInt(0), BigInt(2)).to_int_unchecked()
    var exponent = rng.randrange(BigInt(0), BigInt(255)).to_int_unchecked()
    var fraction = rng.randrange(BigInt(0), BigInt(1 << 23)).to_int_unchecked()
    return UInt32((sign << 31) | (exponent << 23) | fraction)


def _reverse(raw: List[UInt32]) -> List[UInt32]:
    """Swap the first two points' words."""
    var result = List[UInt32]()
    for i in range(3, 6):
        result.append(raw[i])
    for i in range(3):
        result.append(raw[i])
    for i in range(6, len(raw)):
        result.append(raw[i])
    return result^


def build(mut rng: PythonRandom) raises -> Tuple[List[Case], List[Case]]:
    """Return the distance and slab cases, in fixture order."""
    var d = List[Case]()
    var s = List[Case]()
    var big = val(0x7F7FFFFF)
    var tiny = val(1)
    var large = val(bits(1e38))
    d.append(
        Case(
            "exterior_gap",
            _raw([(-large, 0.0, 0.0), (-1.0, 0.0, 0.0), (0.0, 0.0, 0.0)]),
        )
    )
    d.append(
        Case(
            "interior_near_end",
            _raw([(-large, 0.0, 0.0), (-1.0, 0.0, 0.0), (-2.0, 1.0, 0.0)]),
        )
    )
    d.append(
        Case(
            "interior_slanted_near_end",
            _raw([(-large, -large, 0.0), (-1.0, -2.0, 0.0), (-2.0, -2.0, 0.0)]),
        )
    )
    d.append(
        Case(
            "interior_slanted_gap",
            _raw([(-large, -large, 0.0), (-1.0, -2.0, 0.0), (-3.0, -2.0, 0.0)]),
        )
    )
    d.append(
        Case(
            "extreme_midpoint",
            _raw([(-big, 0.0, 0.0), (big, 1.0, 0.0), (0.0, 0.0, 0.0)]),
        )
    )
    d.append(
        Case(
            "minimum_segment",
            _raw([(0.0, 0.0, 0.0), (tiny, 0.0, 0.0), (tiny, tiny, 0.0)]),
        )
    )
    d.append(
        Case(
            "minimum_gap",
            _raw([(-big, 0.0, 0.0), (-tiny, 0.0, 0.0), (0.0, 0.0, 0.0)]),
        )
    )
    d.append(
        Case(
            "mixed_3d",
            _raw([(-big, -big, -big), (-tiny, 1.0, 2.0), (tiny, 0.0, 0.0)]),
        )
    )
    var named: List[Tuple[String, Triple, Triple, Triple]] = [
        ("start_boundary", (0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)),
        ("end_boundary", (0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (1.0, 1.0, 0.0)),
        ("point", (1.0, 2.0, 3.0), (1.0, 2.0, 3.0), (4.0, 6.0, 3.0)),
        ("zero_point", (0.0, 0.0, 0.0), (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)),
        ("collinear", (0.0, 0.0, 0.0), (2.0, 2.0, 2.0), (1.0, 1.0, 1.0)),
        ("y_order", (0.0, 1.0, 0.0), (0.0, -1.0, 0.0), (1.0, 0.0, 0.0)),
        ("z_order", (0.0, 0.0, 1.0), (0.0, 0.0, -1.0), (1.0, 0.0, 0.0)),
        ("end_exterior", (0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (2.0, 1.0, 0.0)),
        ("start_exterior", (0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (-2.0, 1.0, 0.0)),
        ("interior_axis", (0.0, 0.0, 0.0), (2.0, 0.0, 0.0), (1.0, 1.0, 0.0)),
    ]
    for entry in named:
        d.append(Case(entry[0], _raw([entry[1], entry[2], entry[3]])))
    # Input words span every finite exponent. Cancellation controls share anchors.
    for i in range(150):
        var words = List[UInt32]()
        for _ in range(9):
            words.append(_word(rng))
        d.append(Case("mixed_" + String(i), words^))
    for exponent in [-140, -100, -30, 0, 30, 70, 120]:
        var scale = 2.0**exponent
        for i in range(6):
            var points = List[Triple]()
            for _ in range(3):
                var x = (
                    Float64(rng.randrange(BigInt(-8), BigInt(9)).to_int())
                    * scale
                )
                var y = (
                    Float64(rng.randrange(BigInt(-8), BigInt(9)).to_int())
                    * scale
                )
                var z = (
                    Float64(rng.randrange(BigInt(-8), BigInt(9)).to_int())
                    * scale
                )
                points.append((x, y, z))
            d.append(
                Case(
                    "scaled_" + String(exponent) + "_" + String(i), _raw(points)
                )
            )
    for exponent in [30, 60, 100, 127]:
        var m = 2.0**exponent
        for gap in [tiny, 2.0**-70, 1.0, 2.0**20]:
            d.append(
                Case(
                    "endpoint_" + String(exponent) + "_" + String(bits(gap)),
                    _raw(
                        [
                            (-m, -m, 0.0),
                            (-gap, -2 * gap, 0.0),
                            (-2 * gap, -2 * gap, gap),
                        ]
                    ),
                )
            )
    for entry in [(0.0, 0.25, "overflow_miss"), (0.5, 0.75, "overflow_hit")]:
        s.append(
            Case(
                entry[2],
                _raw(
                    [
                        (-big, 0.0, 0.0),
                        (big, 1.0, 0.0),
                        (-1.0, entry[0], -1.0),
                        (1.0, entry[1], 1.0),
                    ]
                ),
            )
        )
    var sixty = 2.0**60
    s.append(
        Case(
            "lost_separate_slabs",
            _raw(
                [
                    (-sixty, -sixty, 0.0),
                    (sixty, sixty, 0.0),
                    (0.0, 2.0, -1.0),
                    (1.0, 3.0, 1.0),
                ]
            ),
        )
    )
    s.append(
        Case(
            "lost_touching_slabs",
            _raw(
                [
                    (-sixty, -sixty, 0.0),
                    (sixty, sixty, 0.0),
                    (0.0, 1.0, -1.0),
                    (1.0, 3.0, 1.0),
                ]
            ),
        )
    )
    s.append(
        Case(
            "minimum_touch",
            _raw(
                [
                    (0.0, 0.0, 0.0),
                    (tiny, tiny, 0.0),
                    (tiny, tiny, 0.0),
                    (tiny, tiny, 0.0),
                ]
            ),
        )
    )
    s.append(
        Case(
            "minimum_miss",
            _raw(
                [
                    (0.0, 0.0, 0.0),
                    (tiny, tiny, 0.0),
                    (0.0, tiny, 0.0),
                    (0.0, tiny, 0.0),
                ]
            ),
        )
    )
    s.append(
        Case(
            "tiny_endpoint_gap",
            _raw(
                [
                    (-big, 0.0, 0.0),
                    (-tiny, 0.0, 0.0),
                    (0.0, -1.0, -1.0),
                    (1.0, 1.0, 1.0),
                ]
            ),
        )
    )
    for i in range(150):
        s.append(Case("mixed_slab_" + String(i), _slab_words(rng)))
    return (d^, s^)


def _slab_words(mut rng: PythonRandom) raises -> List[UInt32]:
    """Draw a segment and a box with lo <= hi, as the Python oracle did."""
    var words = List[UInt32]()
    for _ in range(12):
        words.append(_word(rng))
    var result = List[UInt32]()
    for j in range(6):
        result.append(words[j])
    for j in range(3):
        var x = val(words[6 + j])
        var y = val(words[9 + j])
        result.append(bits(y if y < x else x))
    for j in range(3):
        var x = val(words[6 + j])
        var y = val(words[9 + j])
        result.append(bits(y if y > x else x))
    return result^


def _fixture_rows(
    text: String, marker: String
) raises -> List[Tuple[List[UInt32], String]]:
    """Read `marker([words], expectation)` rows from the native suite."""
    var rows = List[Tuple[List[UInt32], String]]()
    var at = 0
    while True:
        var start = text.find(marker + "(", at)
        if start < 0:
            break
        var open = text.find("[", start)
        var close = text.find("]", open)
        var between = String(
            text[byte = start + marker.byte_length() + 1 : open]
        ).strip()
        if open < 0 or close < 0 or between:
            at = start + 1
            continue
        var words = List[UInt32]()
        for word in String(text[byte = open + 1 : close]).split(","):
            var digits = String(word).strip()
            if digits:
                words.append(UInt32(Int(String(digits))))
        var after = String(text[byte = close + 1 :])
        var end = after.find(")")
        var expectation = String(String(after[byte=:end]).strip())
        if expectation.startswith(","):
            expectation = String(String(expectation[byte=1:]).strip())
        if expectation.endswith(","):
            expectation = String(
                String(
                    expectation[byte = : expectation.byte_length() - 1]
                ).strip()
            )
        if expectation.startswith("Float64("):
            end = after.find(")", after.find("Float64(") + 8)
            expectation = String(
                String(after[byte = after.find("Float64(") + 8 : end]).strip()
            )
        rows.append((words^, expectation))
        at = close + 1
    return rows^


def run(stress: Int) raises -> String:
    """Check every item and the native fixture, and return the summary.

    Args:
        stress: Additional seeded mixed-exponent cases for each kernel.

    Returns:
        The JSON summary.

    Raises:
        Error: If any model, fixture word or expectation disagrees.
    """
    var rng = PythonRandom(589)
    var built = build(rng)
    var d = built[0].copy()
    var s = built[1].copy()
    var paths = Dict[String, Int]()
    var max_error = 0.0
    var max_is_int = True
    for item in d:
        var expected = distance(item.raw).to_float()
        var got = model(item.raw, paths)
        var reverse = model(_reverse(item.raw), paths)
        var error = abs(got - expected) / expected if expected != 0 else abs(
            got
        )
        if not error <= 1e-12:
            raise Error("model error too large: " + item.name)
        if got != reverse:
            raise Error("model is not symmetric: " + item.name)
        if error > max_error:
            max_error = error
            max_is_int = False
    var slab_paths: Dict[String, Int] = {"fast": 0, "exact": 0}
    for item in s:
        var expected = slab(item.raw)
        if (
            slab_model(item.raw, slab_paths) != expected
            or slab_model(_reverse(item.raw), slab_paths) != expected
        ):
            raise Error("slab model disagrees: " + item.name)
    var text = Path(FIXTURE).read_text()
    var distance_rows = _fixture_rows(text, "_distance_case")
    var slab_rows = _fixture_rows(text, "_slab_case")
    if len(distance_rows) != len(d) or len(slab_rows) != len(s):
        raise Error("the native fixture has a different number of cases")
    for i in range(len(d)):
        var words = distance_rows[i][0].copy()
        if len(words) != len(d[i].raw):
            raise Error("retained words differ: " + d[i].name)
        for j in range(len(words)):
            if words[j] != d[i].raw[j]:
                raise Error("retained words differ: " + d[i].name)
        if parse_float(distance_rows[i][1]) != distance(words).to_float():
            raise Error("retained expectation differs: " + d[i].name)
    for i in range(len(s)):
        var words = slab_rows[i][0].copy()
        if len(words) != len(s[i].raw):
            raise Error("retained words differ: " + s[i].name)
        for j in range(len(words)):
            if words[j] != s[i].raw[j]:
                raise Error("retained words differ: " + s[i].name)
        if (slab_rows[i][1] == "True") != slab(words):
            raise Error("retained expectation differs: " + s[i].name)
    var stress_max = 0.0
    for i in range(stress):
        var raw = List[UInt32]()
        for _ in range(9):
            raw.append(_word(rng))
        var expected = distance(raw).to_float()
        var got = model(raw, paths)
        var reverse = model(_reverse(raw), paths)
        var error = abs(got - expected) / expected if expected != 0 else abs(
            got
        )
        if not error <= 1e-12 or got != reverse:
            raise Error("stress item " + String(i) + " failed")
        if error > stress_max:
            stress_max = error
        var box = _slab_words(rng)
        var answer = slab(box)
        if (
            slab_model(box, slab_paths) != answer
            or slab_model(_reverse(box), slab_paths) != answer
        ):
            raise Error("stress slab item " + String(i) + " failed")
    var ratio = expansion_ratio()
    var writer = JsonWriter()
    writer.begin_object()
    writer.key("oracle")
    writer.string("stdlib Fraction exact projection and interval clipping")
    writer.key("distance_cases")
    writer.integer(len(d))
    writer.key("slab_cases")
    writer.integer(len(s))
    writer.key("native_fixture_words_and_expectations_verified")
    writer.boolean(True)
    writer.key("float64_model_max_relative_error")
    if max_is_int:
        writer.integer(0)
    else:
        writer.number(max_error)
    writer.key("distance_model_paths")
    writer.begin_object()
    for entry in paths.items():
        writer.key(entry.key)
        writer.integer(entry.value)
    writer.end()
    writer.key("slab_model_paths")
    writer.begin_object()
    for entry in slab_paths.items():
        writer.key(entry.key)
        writer.integer(entry.value)
    writer.end()
    writer.key("stress_cases_per_kernel")
    writer.integer(stress)
    writer.key("stress_max_relative_error")
    writer.number(stress_max)
    writer.key("expansion_regression_component_ratio")
    writer.number(ratio)
    writer.key("scope")
    writer.string("Model and fixture checks; native gates remain separate")
    writer.end()
    return writer.text()


def expansion_ratio() raises -> Float64:
    """Check the Grow-Expansion regression, and return its component ratio.

    This legal polynomial refutes the former component-ratio bound of two.
    Degree-two Float32 products are exact in Float64, so fused residuals
    are zero.

    Returns:
        The sum of the components' magnitudes over the exact value.

    Raises:
        Error: If the expansion is not exact or the ratio is not in (2, 3).
    """
    var words: List[UInt32] = [
        0x21BB7FCC,
        0xEB450330,
        0x80800000,
        0xD1FB6520,
        0x9BBC8638,
        0xD1FB6520,
        0x50886EAF,
        0xEB450330,
    ]
    var v = List[Float64]()
    for word in words:
        v.append(val(word))
    var left = [v[0], -v[0], -v[1], v[1], -v[4], v[4], v[5], -v[5]]
    var right = [v[2], v[3], v[2], v[3], v[6], v[7], v[6], v[7]]
    var expansion = List[Float64]()
    var exact = Fraction(0)
    for index in range(8):
        var high = left[index] * right[index]
        var product = Fraction.from_float(left[index]) * Fraction.from_float(
            right[index]
        )
        if Fraction.from_float(high) != product:
            raise Error("a Float32 product is not exact in Float64")
        exact = exact + product
        for value in [0.0, high]:
            var parts = List[Float64]()
            var total = value
            for part in expansion:
                var next_value = total + part
                var virtual = next_value - total
                var error = (total - (next_value - virtual)) + (part - virtual)
                if error != 0:
                    parts.append(error)
                total = next_value
            if total != 0:
                parts.append(total)
            expansion = parts^
    var parts_sum = Fraction(0)
    var magnitude = Fraction(0)
    for value in expansion:
        parts_sum = parts_sum + Fraction.from_float(value)
        magnitude = magnitude + abs(Fraction.from_float(value))
    if parts_sum != exact:
        raise Error("the expansion is not exact")
    var ratio = magnitude / abs(exact)
    if not (ratio > Fraction(2) and ratio < Fraction(3)):
        raise Error("the component ratio is not in (2, 3)")
    var rounded = Fraction.from_float(float_sum(expansion))
    if not (
        abs(rounded - exact) / abs(exact)
        < Fraction.of(BigInt(70), BigInt(2) ** 53)
    ):
        raise Error("the rounded expansion is too far from exact")
    return ratio.to_float()


def main() raises:
    var given = argv()
    var stress = 0
    if len(given) == 3 and String(given[1]) == "--stress":
        stress = Int(String(given[2]))
    elif len(given) != 1:
        print("usage: reference_segment_geometry [--stress N]", file=stderr)
        exit(2)
    if stress < 0:
        print("--stress must not be negative", file=stderr)
        exit(2)
    print(run(stress))
