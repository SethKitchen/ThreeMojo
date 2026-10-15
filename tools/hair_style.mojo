# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Convert a TressFX hair file into a hairstyle for `assets/hair/`.

    mojo run -I . tools/hair_style.mojo layered SINTEL.tfx assets/hair/layered.bin
    mojo run -I . tools/hair_style.mojo mohawk RATBOY_MOHAWK.tfx assets/hair/mohawk.bin

reads a `.tfx` file, the guide strands of AMD TressFX 4 (the layout is
`TressFXTFXFileHeader` in TressFX's `TressFXFileFormat.h`, MIT license),
and writes one little-endian file that `HairStyleFile` reads:

    "THRS", version 1
    u32 each: strands, points a strand
    f32: the offsets' scale
    each strand's root on the unit cranium: i16 x, y, z over 32767
    each strand's points, from its root, in the frame of the cranium
        at its root and in its mean radii: i16 across, up and along,
        times the scale

A hairstyle is kept on no head of its own. Each root is put on the
source head's cranium, an ellipsoid fitted through the roots, and then
on the unit sphere; each strand is kept as offsets from its root in the
cranium's frame there: across (toward plus x), up (the cranium's
normal) and along (their cross product), in its mean radii. So a
style goes on any cranium: the roots land on it, and each strand keeps
its shape to the scalp under it.

Two styles come from the repositories this project draws on:

- `layered`: Sintel's hair, from Sintel Lite 2.57b by BenDansie, in
  frostbitten-hair-webgpu by Marcin Matuszczyk. The model is (c) the
  Blender Foundation, CC-BY 3.0, durian.blender.org.
- `mohawk`: Ratboy's mohawk, from AMD TressFX 4.1, MIT license,
  copyright 2020 Advanced Micro Devices. On Ratboy it runs from the
  brow down the back, so only its crest from the brow to the nape is
  kept, and that arc is stretched onto a human scalp's.

The converter gives the same bytes as the Python converter it replaces.
Every product that feeds a sum is rounded on its own (`product`), sums run
from left to right, and `math.dist`, `atan2`, `sin` and `cos` follow
CPython 3.12 and the C library. See THIRD-PARTY-NOTICES.md.
"""

from std.math import isfinite, pi, sqrt
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_math import (
    atan2,
    cos,
    degrees,
    dist,
    product,
    round_half_even,
    sin,
)
from tools._struct import (
    pack_f32,
    pack_i16,
    pack_u32,
    pad4,
    unpack_f32,
    unpack_u32,
)

comptime VERSION = 1
"""The THRS format version."""
comptime POINTS = 16
"""The points each strand is resampled to."""
comptime TFX_HEADER_BYTES = 160
"""The size of a TressFX 4 header."""
# The mohawk's crest, as angles from the top of its circle toward the
# back, in degrees: the part of Ratboy's that is kept, and the arc of a
# human scalp's midline from the hairline to the nape it goes on.
comptime MOHAWK_FROM: Float64 = -15.0
"""Where the kept crest starts, in degrees."""
comptime MOHAWK_TO: Float64 = 100.0
"""Where the kept crest ends, in degrees."""
comptime SCALP_FROM: Float64 = -55.0
"""Where a human scalp's midline starts, in degrees."""
comptime SCALP_TO: Float64 = 110.0
"""Where a human scalp's midline ends, in degrees."""
comptime MOHAWK_HEAD: Float64 = 0.6
"""Only Ratboy's roots this high lie on the head's curve."""
# Ratboy's crest widens down his neck; a human's stays a strip. The
# roots' spread across the head, and the strands' reach across, are
# narrowed by these.
comptime MOHAWK_NARROW: Float64 = 0.5
"""How much the roots' spread across the head narrows."""
comptime MOHAWK_REACH: Float64 = 0.6
"""How much the strands' reach across narrows."""
comptime HUMAN_ACROSS: Float64 = 8.1
"""A human cranium's radius across."""
comptime HUMAN_UP: Float64 = 9.3
"""A human cranium's radius up."""
comptime HUMAN_ALONG: Float64 = 10.6
"""A human cranium's radius along."""
comptime USAGE = (
    "Convert a TressFX hair file into a hairstyle for `assets/hair/`."
)
"""The first line of the module's documentation, which a bad call prints."""


@fieldwise_init
struct V3(Equatable, ImplicitlyCopyable, Movable, Writable):
    """Three doubles: a point, a direction or three radii."""

    var x: Float64
    """The first coordinate."""
    var y: Float64
    """The second coordinate."""
    var z: Float64
    """The third coordinate."""

    def __getitem__(self, k: Int) -> Float64:
        """Return a coordinate by its index.

        Args:
            k: 0, 1 or 2.

        Returns:
            The coordinate.
        """
        if k == 0:
            return self.x
        if k == 1:
            return self.y
        return self.z

    def __eq__(self, other: V3) -> Bool:
        """Return True when every coordinate is equal.

        Args:
            other: The other triple.

        Returns:
            True when the triples are equal.
        """
        return self.x == other.x and self.y == other.y and self.z == other.z

    def write_to(self, mut writer: Some[Writer]):
        """Write the triple as `(x, y, z)`.

        Args:
            writer: The destination.
        """
        writer.write("(", self.x, ", ", self.y, ", ", self.z, ")")


@fieldwise_init
struct Encoded(Copyable, Movable):
    """One strand: its root on the unit sphere and its points' offsets."""

    var q: V3
    """The root on the unit sphere."""
    var offsets: List[V3]
    """Each point's offset from the root, in the cranium's frame."""


@fieldwise_init
struct Cranium(ImplicitlyCopyable, Movable):
    """An ellipsoid: its center and radii."""

    var center: V3
    """The center."""
    var radii: V3
    """The radii across, up and along."""


@fieldwise_init
struct Crest(ImplicitlyCopyable, Movable):
    """A circle in the midline's plane: its center and radius."""

    var center: V3
    """The center, with x zero."""
    var radius: Float64
    """The radius."""


def ordered_sum(values: List[Float64]) -> Float64:
    """Add values from left to right with one rounding per addition.

    Python 3.12 changed built-in sum's floating-point algorithm. The
    production THRS recipe uses this explicit order on every version.

    Args:
        values: The addends.

    Returns:
        Their sum, zero when there are none.
    """
    var total = 0.0
    for value in values:
        total += value
    return total


def _divide(a: Float64, b: Float64) raises -> Float64:
    """Return a / b, refusing a zero divisor as Python does."""
    if b == 0:
        raise Error("float division by zero")
    return a / b


def _root(value: Float64) raises -> Float64:
    """Return the square root, refusing a negative number as Python does."""
    if value < 0:
        raise Error("math domain error")
    return sqrt(value)


def read_tfx(path: String) raises -> List[List[V3]]:
    """Return finite positions from a validated TressFX 4 file.

    The offline converter resamples any strand with at least two points;
    the upstream GPU simulation's power-of-two point count does not apply.

    Args:
        path: The `.tfx` file.

    Returns:
        Each strand's points.

    Raises:
        Error: For a malformed header, offset or position, or a file that
            cannot be read.
    """
    var data = Path(path).read_bytes()
    var span = Span(data)
    if len(data) < TFX_HEADER_BYTES:
        raise Error("Not a complete TressFX header: " + path)
    var version = unpack_f32(span, 0)
    var strands = unpack_u32(span, 4)
    var points = unpack_u32(span, 8)
    var offset = unpack_u32(span, 12)
    if not isfinite(version) or not (4.0 <= version and version < 5.0):
        raise Error("The converter requires the TressFX 4 layout: " + path)
    if strands == 0 or points < 2:
        raise Error("A TressFX file with no strands: " + path)
    if offset < TFX_HEADER_BYTES or offset % 8 != 0:
        raise Error("Invalid TressFX position offset: " + path)
    # The counts can reach 2**32 each, so the room is divided instead of
    # their product multiplied: x * p * 16 > room exactly when
    # x > room // 16 // p.
    if offset > len(data) or strands > (len(data) - offset) // 16 // points:
        raise Error("The TressFX file ends early: " + path)
    var result = List[List[V3]](capacity=strands)
    for s in range(strands):
        var strand = List[V3](capacity=points)
        for i in range(points):
            # Each position is FLOAT4; the converter uses xyz, not w.
            var at = offset + 16 * (s * points + i)
            var p = V3(
                unpack_f32(span, at),
                unpack_f32(span, at + 4),
                unpack_f32(span, at + 8),
            )
            if not (isfinite(p.x) and isfinite(p.y) and isfinite(p.z)):
                raise Error(
                    "Non-finite TressFX position at strand "
                    + String(s)
                    + ", point "
                    + String(i)
                    + ": "
                    + path
                )
            strand.append(p)
        result.append(strand^)
    return result^


def _sub(a: V3, b: V3) -> V3:
    """Return a - b."""
    return V3(a.x - b.x, a.y - b.y, a.z - b.z)


def _dot(a: V3, b: V3) -> Float64:
    """Return the dot product, added from left to right."""
    return product(a.x, b.x) + product(a.y, b.y) + product(a.z, b.z)


def _unit(a: V3) raises -> V3:
    """Return a scaled to length one."""
    var length = _root(_dot(a, a))
    return V3(_divide(a.x, length), _divide(a.y, length), _divide(a.z, length))


def _cross(a: V3, b: V3) -> V3:
    """Return the cross product."""
    return V3(
        product(a.y, b.z) - product(a.z, b.y),
        product(a.z, b.x) - product(a.x, b.z),
        product(a.x, b.y) - product(a.y, b.x),
    )


def _coords(p: V3) -> List[Float64]:
    """Return a point's coordinates as a list."""
    return [p.x, p.y, p.z]


def resample(strand: List[V3], count: Int = POINTS) raises -> List[V3]:
    """Return `count` points spaced evenly along a strand.

    Args:
        strand: At least two points.
        count: How many points to return, at least two.

    Returns:
        The points, the first at the root and the last at the tip.

    Raises:
        Error: If the strand has fewer than two points.
    """
    if len(strand) < 2:
        raise Error("A strand needs two points")
    var lengths: List[Float64] = [0.0]
    for i in range(1, len(strand)):
        lengths.append(
            lengths[len(lengths) - 1]
            + dist(_coords(strand[i - 1]), _coords(strand[i]))
        )
    var total = lengths[len(lengths) - 1]
    var result = List[V3](capacity=count)
    var j = 0
    for k in range(count):
        var want = _divide(product(total, Float64(k)), Float64(count - 1))
        while j < len(strand) - 2 and lengths[j + 1] < want:
            j += 1
        var span = lengths[j + 1] - lengths[j]
        var t = 0.0 if span <= 0 else (want - lengths[j]) / span
        # Python's min and max keep the first of equal values.
        if t < 1.0:
            pass
        else:
            t = 1.0
        if t > 0.0:
            pass
        else:
            t = 0.0
        var a = strand[j]
        var b = strand[j + 1]
        result.append(
            V3(
                a.x + product(b.x - a.x, t),
                a.y + product(b.y - a.y, t),
                a.z + product(b.z - a.z, t),
            )
        )
    return result^


def solve(
    matrix: List[List[Float64]], vector: List[Float64]
) raises -> List[Float64]:
    """Solve a small linear system by Gauss-Jordan elimination.

    Args:
        matrix: The square matrix, by rows.
        vector: The right-hand side.

    Returns:
        The solution.

    Raises:
        Error: If a pivot is zero, as Python raises `ZeroDivisionError`.
    """
    var n = len(vector)
    var rows = List[List[Float64]](capacity=n)
    for i in range(n):
        var row = matrix[i].copy()
        row.append(vector[i])
        rows.append(row^)
    for c in range(n):
        var pivot = c
        for r in range(c + 1, n):
            if abs(rows[r][c]) > abs(rows[pivot][c]):
                pivot = r
        rows.swap_elements(c, pivot)
        for r in range(n):
            if r != c:
                var f = _divide(rows[r][c], rows[c][c])
                for k in range(n + 1):
                    rows[r][k] = rows[r][k] - product(f, rows[c][k])
    var result = List[Float64](capacity=n)
    for i in range(n):
        result.append(_divide(rows[i][n], rows[i][i]))
    return result^


def fit_cranium(points: List[V3]) raises -> Cranium:
    """Return the ellipsoid, square to the axes and on the midline, that
    passes nearest `points`.

    Args:
        points: The roots.

    Returns:
        The ellipsoid's center and radii.

    Raises:
        Error: If the points do not fix an ellipsoid.
    """
    var rows = List[List[Float64]](capacity=len(points))
    for p in points:
        rows.append(
            [product(p.x, p.x), product(p.y, p.y), product(p.z, p.z), p.y, p.z]
        )
    var matrix = List[List[Float64]]()
    var vector = List[Float64]()
    for i in range(5):
        var line = List[Float64]()
        for j in range(5):
            var terms = List[Float64](capacity=len(rows))
            for r in rows:
                terms.append(product(r[i], r[j]))
            line.append(ordered_sum(terms))
        matrix.append(line^)
        var terms = List[Float64](capacity=len(rows))
        for r in rows:
            terms.append(r[i])
        vector.append(ordered_sum(terms))
    var solution = solve(matrix, vector)
    var a = solution[0]
    var b = solution[1]
    var c = solution[2]
    var d = solution[3]
    var e = solution[4]
    var cy = _divide(-d, 2 * b)
    var cz = _divide(-e, 2 * c)
    var g = 1 + product(product(b, cy), cy) + product(product(c, cz), cz)
    return Cranium(
        V3(0.0, cy, cz),
        V3(_root(_divide(g, a)), _root(_divide(g, b)), _root(_divide(g, c))),
    )


def fit_crest(points: List[V3]) raises -> Crest:
    """Return the circle in the midline's plane, y and z, that passes
    nearest `points`.

    Args:
        points: The roots.

    Returns:
        The circle's center and radius.

    Raises:
        Error: If the points do not fix a circle.
    """
    var rows = List[List[Float64]](capacity=len(points))
    var rhs = List[Float64](capacity=len(points))
    for p in points:
        rows.append([p.y, p.z, 1.0])
        rhs.append(-(product(p.y, p.y) + product(p.z, p.z)))
    var matrix = List[List[Float64]]()
    var vector = List[Float64]()
    for i in range(3):
        var line = List[Float64]()
        for j in range(3):
            var terms = List[Float64](capacity=len(rows))
            for r in rows:
                terms.append(product(r[i], r[j]))
            line.append(ordered_sum(terms))
        matrix.append(line^)
        var terms = List[Float64](capacity=len(rows))
        for index in range(len(rows)):
            terms.append(product(rows[index][i], rhs[index]))
        vector.append(ordered_sum(terms))
    var solution = solve(matrix, vector)
    var cy = -solution[0] / 2
    var cz = -solution[1] / 2
    return Crest(
        V3(0.0, cy, cz),
        _root(product(cy, cy) + product(cz, cz) - solution[2]),
    )


def cranium_frame(q: V3, radii: V3) raises -> Tuple[V3, V3, V3]:
    """Return the frame of an ellipsoid at the point `q` of its unit
    sphere.

    Args:
        q: A point on the unit sphere.
        radii: The ellipsoid's radii.

    Returns:
        Across, up (the normal) and along.

    Raises:
        Error: If a radius is zero.
    """
    var up = _unit(
        V3(_divide(q.x, radii.x), _divide(q.y, radii.y), _divide(q.z, radii.z))
    )
    var across = _sub(
        V3(1.0, 0.0, 0.0),
        V3(product(up.x, up.x), product(up.y, up.x), product(up.z, up.x)),
    )
    if _dot(across, across) < 1e-6:
        across = _sub(
            V3(0.0, 0.0, 1.0),
            V3(product(up.x, up.z), product(up.y, up.z), product(up.z, up.z)),
        )
    across = _unit(across)
    return (across, up, _cross(up, across))


def encode(
    strands: List[List[V3]], center: V3, radii: V3
) raises -> List[Encoded]:
    """Return each strand as its root on the unit sphere and its points'
    offsets in the cranium's frame, in its mean radii.

    Args:
        strands: The strands, each from its root.
        center: The cranium's center.
        radii: The cranium's radii.

    Returns:
        The encoded strands.

    Raises:
        Error: If a root lies at the center or a radius is zero.
    """
    var mean = ordered_sum([radii.x, radii.y, radii.z]) / 3
    var result = List[Encoded](capacity=len(strands))
    for strand in strands:
        var root = strand[0]
        var q = _unit(
            V3(
                _divide(root.x - center.x, radii.x),
                _divide(root.y - center.y, radii.y),
                _divide(root.z - center.z, radii.z),
            )
        )
        var frame = cranium_frame(q, radii)
        var offsets = List[V3](capacity=len(strand))
        for p in strand:
            var s = _sub(p, root)
            var d = V3(
                _divide(s.x, mean), _divide(s.y, mean), _divide(s.z, mean)
            )
            offsets.append(
                V3(_dot(d, frame[0]), _dot(d, frame[1]), _dot(d, frame[2]))
            )
        result.append(Encoded(q, offsets^))
    return result^


def _roots(strands: List[List[V3]]) -> List[V3]:
    """Return each strand's first point."""
    var roots = List[V3](capacity=len(strands))
    for strand in strands:
        roots.append(strand[0])
    return roots^


def layered(strands: List[List[V3]]) raises -> List[Encoded]:
    """Return Sintel's strands encoded on the cranium fitted to their
    roots.

    Args:
        strands: The resampled strands.

    Returns:
        The encoded strands.

    Raises:
        Error: If the roots do not fix a cranium.
    """
    var cranium = fit_cranium(_roots(strands))
    return encode(strands, cranium.center, cranium.radii)


def _radians(degrees: Float64) -> Float64:
    """Return degrees in radians, as `math.radians` rounds it."""
    var factor = Float64(pi) / Float64(180)
    return product(degrees, factor)


def mohawk(strands: List[List[V3]]) raises -> List[Encoded]:
    """Return the crest of Ratboy's mohawk, from the brow to the nape,
    encoded on a human-shaped cranium round its circle, its arc stretched
    onto a human scalp's.

    Args:
        strands: The resampled strands.

    Returns:
        The encoded strands of the crest.

    Raises:
        Error: If no strand lies on the crest, or the roots fix no circle.
    """
    var head = List[V3]()
    for strand in strands:
        if strand[0].y >= MOHAWK_HEAD:
            head.append(strand[0])
    var crest = fit_crest(head)
    var center = crest.center
    var radii = V3(
        product(crest.radius, HUMAN_ACROSS) / HUMAN_UP,
        product(crest.radius, HUMAN_UP) / HUMAN_UP,
        product(crest.radius, HUMAN_ALONG) / HUMAN_UP,
    )
    var kept = List[List[V3]]()
    for strand in strands:
        var y = strand[0].y
        var z = strand[0].z
        var angle = degrees(atan2(-(z - center.z), y - center.y))
        if angle < MOHAWK_FROM or angle > MOHAWK_TO:
            continue
        var t = (angle - MOHAWK_FROM) / (MOHAWK_TO - MOHAWK_FROM)
        var moved = _radians(SCALP_FROM + product(SCALP_TO - SCALP_FROM, t))
        # The root goes to its place on the stretched arc, and the
        # strand goes with it, turned as the arc turns.
        var turn = moved - _radians(angle)
        var c = cos(turn)
        var s = sin(turn)
        var placed = List[V3](capacity=len(strand))
        for p in strand:
            var dy = p.y - center.y
            var dz = -(p.z - center.z)
            placed.append(
                V3(
                    p.x,
                    center.y + product(dy, c) - product(dz, s),
                    center.z - (product(dy, s) + product(dz, c)),
                )
            )
        kept.append(placed^)
    if len(kept) == 0:
        raise Error("No strand of the mohawk lies on its crest")
    var narrowed = List[Encoded](capacity=len(kept))
    for item in encode(kept, center, radii):
        var q = _unit(V3(product(item.q.x, MOHAWK_NARROW), item.q.y, item.q.z))
        var offsets = List[V3](capacity=len(item.offsets))
        for o in item.offsets:
            offsets.append(V3(product(o.x, MOHAWK_REACH), o.y, o.z))
        narrowed.append(Encoded(q, offsets^))
    return narrowed^


def _i16(value: Float64) -> Int:
    """Return `max(-32767, min(32767, int(round(value))))`."""
    var rounded = round_half_even(value)
    if rounded > 32767:
        return 32767
    if rounded < -32767:
        return -32767
    return Int(rounded)


def thrs_bytes(encoded: List[Encoded]) raises -> List[UInt8]:
    """Return encoded strands in the layout above.

    Args:
        encoded: At least one encoded strand.

    Returns:
        The file's bytes.

    Raises:
        Error: If there is no strand, or the scale is no `float`.
    """
    if len(encoded) == 0:
        raise Error("A hairstyle needs a strand")
    var largest = 0.0
    var any = False
    for item in encoded:
        for o in item.offsets:
            for k in range(3):
                var c = abs(o[k])
                if not any or c > largest:
                    largest = c
                    any = True
    var scale = (largest if any else 1.0) / 32767
    if scale == 0:
        scale = 1.0 / 32767
    var body = List[UInt8]()
    body.extend("THRS".as_bytes())
    var points = len(encoded[0].offsets)
    pack_u32(body, VERSION)
    pack_u32(body, len(encoded))
    pack_u32(body, points)
    pack_f32(body, scale)
    for item in encoded:
        for k in range(3):
            pack_i16(body, _i16(product(item.q[k], 32767)))
    pad4(body)
    for item in encoded:
        for o in item.offsets:
            for k in range(3):
                pack_i16(body, _i16(o[k] / scale))
    return body^


def write(path: String, encoded: List[Encoded]) raises -> Int:
    """Write encoded strands in the layout above.

    Args:
        path: The output file.
        encoded: At least one encoded strand.

    Returns:
        The number of strands.

    Raises:
        Error: If the bytes cannot be made or written.
    """
    var body = thrs_bytes(encoded)
    Path(path).write_bytes(Span(body))
    return len(encoded)


def convert(style: String, source: String, target: String) raises -> Int:
    """Convert one TressFX file into a hairstyle.

    The target is written only once the whole style is made, so a bad
    source never replaces it.

    Args:
        style: `layered` or `mohawk`.
        source: The `.tfx` file.
        target: The output file.

    Returns:
        The number of strands written.

    Raises:
        Error: For an unknown style, a bad source, or a failed write.
    """
    var strands = List[List[V3]]()
    for strand in read_tfx(source):
        strands.append(resample(strand))
    var encoded: List[Encoded]
    if style == "layered":
        encoded = layered(strands)
    elif style == "mohawk":
        encoded = mohawk(strands)
    else:
        raise Error("A style is layered or mohawk")
    return write(target, encoded)


def run(arguments: List[String]) raises -> Tuple[Int, String, String]:
    """Run the converter as the command line does.

    Args:
        arguments: The program name, the style, the source and the target.

    Returns:
        The exit status, the standard output and the standard error.

    Raises:
        Error: If the conversion fails.
    """
    if len(arguments) != 4:
        return (2, String(), String(USAGE) + "\n")
    var count = convert(arguments[1], arguments[2], arguments[3])
    return (0, "strands: " + String(count) + "\n", String())


def main() raises:
    """Run the converter from the command line.

    Raises:
        Error: If the conversion fails.
    """
    var arguments = List[String]()
    for argument in argv():
        arguments.append(String(argument))
    var outcome = run(arguments)
    print(outcome[1], end="")
    print(outcome[2], end="", file=stderr)
    exit(outcome[0])
