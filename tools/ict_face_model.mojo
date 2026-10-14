# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Convert the ICT Face Model Light into `assets/face/ict_face.bin`.

    mojo run -I . tools/ict_face_model.mojo ICT-FaceKit/FaceXModel assets/face/ict_face.bin

reads the model's OBJ files (MIT license, see THIRD-PARTY-NOTICES.md) and
writes one little-endian file that `FaceModel` reads with no parsing of
text:

    "ICTF", version 6
    u32 each: vertices, drawn vertices, triangles, identities,
        expressions, skin triangles, skin edges, holes, hole corners,
        coarse skin triangles, the bytes the expressions take, the
        coarse copy's vertices, its edges, and the skin's followers
    the neutral head: f32 x, y, z a vertex, in meters
    each drawn vertex's texture coordinates: f32 u, v
    each drawn vertex's vertex: u16
    the triangles: u16 three drawn vertices each
    the skin's triangles: u16 three vertices each
    the skin's edges: u16 two vertices each, each edge once
    each hole's length: u16
    each hole's corners, in the order its triangles run its edges: u16
    the skin's coarse triangles, over its own vertices: u16 three each
    the coarse copy's vertices: u16
    its edges, each once, numbered among its vertices: u16 two each
    each skin vertex's coarse triangle, numbered the same way: u16 three
    each skin vertex's weights on that triangle's second and third
        corners: f32 two
    each expression: u8 name length, the name, u32 count, f32 scale,
        u16 the vertices it moves, i8 x, y, z a moved vertex
    each identity mode: f32 scale, then i8 x, y, z a vertex

The skin is the face and the head, the model's first `SKIN_END`
vertices: its holes are the mouth, the eyes and the base of the neck.
Its coarse copy, `decimate`d to `COARSE_TRIANGLES`, is for measuring
distance to the skin: a search through fewer, larger triangles is
faster, and the copy stays within a fraction of a millimeter. The skin
is also fitted on the coarse copy, and each of its vertices `follow`s
the coarse triangle nearest it.
Every section starts on a multiple of four bytes, so the reader takes
each array straight out of the file. The expressions come before the
identity modes: a head at rest needs a few expressions and no identity.
A displacement is its signed byte times its scale. The file is not
compressed, so a head loads in milliseconds.

The converter gives the same bytes as the Python converter it replaces.
It reads each decimal as `float()` does, rounds each product that feeds a
sum on its own (`product`), adds with CPython 3.12's compensated `sum`
where the Python converter called `sum`, and takes `x ** y` from the C
library's `pow`.
"""

from std.collections import Dict, Set
from std.math import isfinite
from std.os import listdir
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_float import parse_float
from tools._python_math import (
    floor_divide,
    float_sum,
    power,
    product,
    round_half_even,
)
from tools._struct import (
    pack_f32,
    pack_u8,
    pack_u16,
    pack_u32,
    pad4,
)

comptime IDENTITIES = 60
"""The identity modes the production file keeps."""
comptime VERSION = 6
"""The ICTF format version."""
comptime _EXPRESSION_BYTES_AT = 48
"""Where the header's count of the expressions' bytes lies in the file."""
comptime SKIN_END = 11248
"""The face and the head: the ICT model's first vertices."""
comptime COARSE_TRIANGLES = 6000
"""How many triangles the skin's coarse copy keeps, for distances."""
comptime TO_METERS: Float64 = 0.01
"""The OBJ files are in centimeters."""
comptime STILL: Float64 = 1e-7
"""A vertex an expression moves less than this, in meters, is left out."""
comptime CELL: Float64 = 0.015
"""The side of a cell of the followers' search grid, in meters."""
comptime USAGE = "usage: ict_face_model.mojo FaceXModel OUT"
"""What a bad call prints."""
# The largest power of ten a double holds exactly.
comptime _EXACT_POWERS = 22
# The cells' grid coordinates are packed into one key, 21 bits each.
comptime _CELL_BIAS = 1 << 20


@fieldwise_init
struct P3(Equatable, ImplicitlyCopyable, Movable, Writable):
    """A point: three doubles."""

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

    def __eq__(self, other: P3) -> Bool:
        """Return True when every coordinate is equal.

        Args:
            other: The other point.

        Returns:
            True when the points are equal.
        """
        return self.x == other.x and self.y == other.y and self.z == other.z

    def write_to(self, mut writer: Some[Writer]):
        """Write the point as `(x, y, z)`.

        Args:
            writer: The destination.
        """
        writer.write("(", self.x, ", ", self.y, ", ", self.z, ")")


@fieldwise_init
struct ObjMesh(Movable):
    """What an OBJ file holds: positions, texture coordinates and faces."""

    var points: List[P3]
    """The positions."""
    var uvs: List[Float64]
    """The texture coordinates, u and v each."""
    var faces: List[List[Int]]
    """Each face's corners, as a position index then a texture index."""


@fieldwise_init
struct Topology(Movable):
    """The skin: its triangles, its edges and its holes."""

    var skin: List[Int]
    """The triangles, three vertices each."""
    var edges: List[Int]
    """The edges, two vertices each, each edge once, sorted."""
    var holes: List[List[Int]]
    """The loops of edges that only one triangle uses."""


@fieldwise_init
struct Following(Movable):
    """How the skin follows its coarse copy."""

    var used: List[Int]
    """The coarse copy's vertices, sorted."""
    var edges: List[Int]
    """Its edges, two local vertices each, each once, sorted."""
    var corners: List[Int]
    """Each skin vertex's coarse triangle, three local vertices each."""
    var weights: List[Float64]
    """Each skin vertex's weights on the second and third corners."""


@fieldwise_init
struct Closest(ImplicitlyCopyable, Movable):
    """The nearest point of a triangle."""

    var distance2: Float64
    """The squared distance to it."""
    var wb: Float64
    """Its weight on the second corner."""
    var wc: Float64
    """Its weight on the third corner."""


# --- reading OBJ files ---------------------------------------------------------


def _is_space(byte: UInt8) -> Bool:
    """Return True for the ASCII bytes `str.split()` splits at."""
    return (
        byte == 32 or (byte >= 9 and byte <= 13) or (byte >= 28 and byte <= 31)
    )


def _parse_int(text: String) raises -> Int:
    """Return an integer as `int(text)` reads one: a sign, then digits with
    single underscores between them."""
    var bytes = text.as_bytes()
    var index = 0
    var negative = False
    if index < len(bytes) and (bytes[index] == 43 or bytes[index] == 45):
        negative = bytes[index] == 45
        index += 1
    var value = 0
    var digits = 0
    var underscore = False
    while index < len(bytes):
        var byte = bytes[index]
        if byte >= 48 and byte <= 57:
            if value > 100000000000000000:
                raise Error("An OBJ index is too large: " + text)
            value = value * 10 + Int(byte) - 48
            digits += 1
            underscore = False
        elif byte == 95 and digits > 0 and not underscore:
            underscore = True
        else:
            raise Error(
                "invalid literal for int() with base 10: '" + text + "'"
            )
        index += 1
    if digits == 0 or underscore:
        raise Error("invalid literal for int() with base 10: '" + text + "'")
    return -value if negative else value


def parse_coordinate(text: String) raises -> Float64:
    """Return a decimal as `float(text)` reads it, nearest with ties to even.

    A plain decimal with at most fifteen digits and a small exponent is one
    exact integer times or over an exact power of ten: one rounding, so it
    is exact (Clinger's fast path). Anything else goes to `parse_float`.

    Args:
        text: The decimal.

    Returns:
        The nearest double.

    Raises:
        Error: If the text is not a number.
    """
    var bytes = text.as_bytes()
    var index = 0
    var negative = False
    if index < len(bytes) and (bytes[index] == 43 or bytes[index] == 45):
        negative = bytes[index] == 45
        index += 1
    var mantissa = 0
    var significant = 0
    var digits = 0
    var exponent = 0
    var point = False
    var simple = True
    while index < len(bytes):
        var byte = bytes[index]
        if byte >= 48 and byte <= 57:
            digits += 1
            if mantissa > 0 or byte != 48:
                significant += 1
                mantissa = (
                    mantissa * 10 + Int(byte) - 48 if significant
                    <= 15 else mantissa
                )
            if significant > 15:
                simple = False
            if point:
                exponent -= 1
        elif byte == 46 and not point:
            point = True
        else:
            break
        index += 1
    if index < len(bytes):
        if digits > 0 and (bytes[index] == 101 or bytes[index] == 69):
            index += 1
            var sign = 1
            if index < len(bytes) and (
                bytes[index] == 43 or bytes[index] == 45
            ):
                sign = -1 if bytes[index] == 45 else 1
                index += 1
            var power_digits = 0
            var value = 0
            while (
                index < len(bytes) and bytes[index] >= 48 and bytes[index] <= 57
            ):
                if value < 100000:
                    value = value * 10 + Int(bytes[index]) - 48
                power_digits += 1
                index += 1
            if power_digits == 0 or index < len(bytes):
                simple = False
            exponent += sign * value
        else:
            simple = False
    if digits == 0:
        simple = False
    if not simple or exponent > _EXACT_POWERS or exponent < -_EXACT_POWERS:
        return parse_float(text)
    var scale = 1.0
    for _ in range(abs(exponent)):
        scale *= 10.0
    var magnitude = Float64(mantissa)
    var value = magnitude * scale if exponent >= 0 else magnitude / scale
    return -value if negative else value


def _obj_index(text: String, count: Int) raises -> Int:
    """Resolve a nonzero OBJ index, using the current count for negatives."""
    var value = _parse_int(text)
    if value == 0:
        raise Error("An OBJ index must not be zero")
    if value < 0:
        value += count
        if value < 0:
            raise Error("An OBJ relative index is out of range")
        return value
    return value - 1


def _words(bytes: Span[UInt8, _], start: Int, end: Int) -> List[String]:
    """Return the words of a line before any `#`."""
    var words = List[String]()
    var index = start
    var stop = end
    for at in range(start, end):
        if bytes[at] == 35:
            stop = at
            break
    while index < stop:
        while index < stop and _is_space(bytes[index]):
            index += 1
        var first = index
        while index < stop and not _is_space(bytes[index]):
            index += 1
        if index > first:
            words.append(String(unsafe_from_utf8=bytes[first:index]))
    return words^


def read_obj(path: String) raises -> ObjMesh:
    """Return finite OBJ positions, texture coordinates and indexed faces.

    Each face needs at least three position/texture-coordinate pairs.
    Indices are returned from zero. Negative indices are relative to the
    declarations before that face; positive references can point forward.

    Args:
        path: The OBJ file, in ASCII.

    Returns:
        The positions, the texture coordinates and the faces.

    Raises:
        Error: For a byte outside ASCII, or an invalid coordinate, corner
            field or reference.
    """
    var data = Path(path).read_bytes()
    var bytes = Span(data)
    for byte in bytes:
        if byte >= 128:
            raise Error("'ascii' codec can't decode byte in position: " + path)
    var points = List[P3]()
    var uvs = List[Float64]()
    var faces = List[List[Int]]()
    var start = 0
    var line_number = 0
    while start < len(bytes):
        # Universal newlines: LF, CR LF or CR ends a line.
        var end = start
        while end < len(bytes) and bytes[end] != 10 and bytes[end] != 13:
            end += 1
        var next = end + 1
        if (
            end < len(bytes)
            and bytes[end] == 13
            and next < len(bytes)
            and bytes[next] == 10
        ):
            next += 1
        line_number += 1
        var words = _words(bytes, start, end)
        start = next
        if len(words) == 0:
            continue
        var place = path + ":" + String(line_number) + ": "
        if words[0] == "v" or words[0] == "vt":
            var width = 3 if words[0] == "v" else 2
            if len(words) < width + 1:
                raise Error(place + "short OBJ coordinate row")
            var values = List[Float64]()
            for k in range(width):
                values.append(parse_coordinate(words[k + 1]))
            for value in values:
                if not isfinite(value):
                    raise Error(place + "non-finite OBJ coordinate")
            if width == 3:
                points.append(P3(values[0], values[1], values[2]))
            else:
                uvs.append(values[0])
                uvs.append(values[1])
        elif words[0] == "f":
            if len(words) < 4:
                raise Error(place + "an OBJ face needs three corners")
            var corners = List[Int]()
            for w in range(1, len(words)):
                var parts = words[w].split("/")
                if (
                    not (len(parts) == 2 or len(parts) == 3)
                    or parts[0].byte_length() == 0
                    or parts[1].byte_length() == 0
                ):
                    raise Error(
                        place + "an OBJ corner needs position/texture indices"
                    )
                corners.append(_obj_index(String(parts[0]), len(points)))
                corners.append(_obj_index(String(parts[1]), len(uvs) // 2))
            faces.append(corners^)
    for face in faces:
        for k in range(0, len(face), 2):
            if not (
                0 <= face[k]
                and face[k] < len(points)
                and 0 <= face[k + 1]
                and face[k + 1] < len(uvs) // 2
            ):
                raise Error(path + ": an OBJ face index is out of range")
    return ObjMesh(points^, uvs^, faces^)


# --- displacements -------------------------------------------------------------


def quantize(deltas: List[Float64]) -> Tuple[Float64, List[UInt8]]:
    """Return the scale and the signed bytes that stand for `deltas`.

    Args:
        deltas: A flat list of floats.

    Returns:
        The scale, and each delta over it, rounded and held to -127..127,
        as a byte.
    """
    var peak = 0.0
    for x in deltas:
        if abs(x) > peak:
            peak = abs(x)
    var scale = peak / 127 if peak > 0 else 1.0
    var packed = List[UInt8](capacity=len(deltas))
    for x in deltas:
        var rounded = round_half_even(x / scale)
        if rounded > 127:
            rounded = 127
        if rounded < -127:
            rounded = -127
        packed.append(UInt8(Int(rounded) & 0xFF))
    return (scale, packed^)


def displacements(points: List[P3], neutral: List[P3]) raises -> List[P3]:
    """Return each vertex's move from `neutral` to `points`, in meters.

    Args:
        points: The shape's vertices.
        neutral: The neutral vertices.

    Returns:
        The moves.

    Raises:
        Error: If the vertex counts differ.
    """
    if len(points) != len(neutral):
        raise Error("A shape needs one vertex per neutral vertex")
    var moves = List[P3](capacity=len(points))
    for i in range(len(points)):
        var p = points[i]
        var n = neutral[i]
        moves.append(
            P3(
                product(p.x - n.x, TO_METERS),
                product(p.y - n.y, TO_METERS),
                product(p.z - n.z, TO_METERS),
            )
        )
    return moves^


def _length(move: P3) -> Float64:
    """Return `sum(x * x for x in move) ** 0.5` as CPython computes it."""
    var squares: List[Float64] = [
        product(move.x, move.x),
        product(move.y, move.y),
        product(move.z, move.z),
    ]
    return power(float_sum(squares), 0.5)


# --- the skin ------------------------------------------------------------------


def _edge_key(u: Int, v: Int) -> Int:
    """Return one key for an edge, whichever way it runs."""
    return (min(u, v) << 32) | max(u, v)


def skin_topology(
    position_of: List[Int], triangles: List[Int], skin_end: Int = SKIN_END
) raises -> Topology:
    """Return the skin's triangles, its edges and its holes.

    The skin's triangles name vertices, not drawn vertices, so they join
    across the texture's seams. A hole is a loop of edges that only one
    triangle uses, in the order the triangles run them.

    Args:
        position_of: Each drawn vertex's vertex.
        triangles: Three drawn vertices each.
        skin_end: The first vertex that is not skin.

    Returns:
        The skin's topology.

    Raises:
        Error: If a hole's loop breaks off, as Python raises `KeyError`.
    """
    var skin = List[Int]()
    for t in range(0, len(triangles), 3):
        var a = position_of[triangles[t]]
        var b = position_of[triangles[t + 1]]
        var c = position_of[triangles[t + 2]]
        if a < skin_end and b < skin_end and c < skin_end:
            skin.append(a)
            skin.append(b)
            skin.append(c)
    var uses = Dict[Int, Int]()
    for t in range(0, len(skin), 3):
        for k in range(3):
            var key = _edge_key(skin[t + k], skin[t + (k + 1) % 3])
            uses[key] = uses.get(key, 0) + 1
    var keys = List[Int]()
    for key in uses.keys():
        keys.append(key)
    sort(keys)
    var edges = List[Int](capacity=2 * len(keys))
    for key in keys:
        edges.append(key >> 32)
        edges.append(key & 0xFFFFFFFF)
    var following = Dict[Int, Int]()
    for t in range(0, len(skin), 3):
        for k in range(3):
            var u = skin[t + k]
            var v = skin[t + (k + 1) % 3]
            if uses[_edge_key(u, v)] == 1:
                following[u] = v
    var starts = List[Int]()
    for key in following.keys():
        starts.append(key)
    sort(starts)
    var holes = List[List[Int]]()
    var done = Set[Int]()
    for start in starts:
        if start in done:
            continue
        var loop = List[Int]()
        var v = start
        while v not in done:
            done.add(v)
            loop.append(v)
            if v not in following:
                raise Error(String(v))
            v = following[v]
        holes.append(loop^)
    return Topology(skin^, edges^, holes^)


# --- decimation ------------------------------------------------------------------


def normal(a: P3, b: P3, c: P3) -> P3:
    """Return the unnormalized normal of a triangle.

    Args:
        a: The first corner.
        b: The second corner.
        c: The third corner.

    Returns:
        (b - a) cross (c - a).
    """
    var u = P3(b.x - a.x, b.y - a.y, b.z - a.z)
    var v = P3(c.x - a.x, c.y - a.y, c.z - a.z)
    return P3(
        product(u.y, v.z) - product(u.z, v.y),
        product(u.z, v.x) - product(u.x, v.z),
        product(u.x, v.y) - product(u.y, v.x),
    )


def _square(x: Float64) -> Float64:
    """Return `x ** 2` as CPython's float power computes it."""
    return power(abs(x), 2.0)


def plane_quadric(a: P3, b: P3, c: P3) -> Optional[List[Float64]]:
    """Return the quadric of the plane through three points.

    Args:
        a: The first point.
        b: The second point.
        c: The third point.

    Returns:
        The ten distinct entries of a symmetric 4-by-4 matrix, or `None`
        for a triangle with no area.
    """
    var n = normal(a, b, c)
    var length = power(_square(n.x) + _square(n.y) + _square(n.z), 0.5)
    if length == 0:
        return None
    var x = n.x / length
    var y = n.y / length
    var z = n.z / length
    var w = -(product(x, a.x) + product(y, a.y) + product(z, a.z))
    var p: List[Float64] = [x, y, z, w]
    var q = List[Float64](capacity=10)
    for i in range(4):
        for j in range(i, 4):
            q.append(product(p[i], p[j]))
    return q^


def _cost(q: Span[Float64, _], p: P3) -> Float64:
    """Return the squared distance a quadric gives the point `p`."""
    var x = p.x
    var y = p.y
    var z = p.z
    return (
        product(q[0] * x, x)
        + product(2 * q[1] * x, y)
        + product(2 * q[2] * x, z)
        + product(2 * q[3], x)
        + product(q[4] * y, y)
        + product(2 * q[5] * y, z)
        + product(2 * q[6], y)
        + product(q[7] * z, z)
        + product(2 * q[8], z)
        + q[9]
    )


def _add_once(mut items: List[Int], value: Int):
    """Add a value to a list that holds each value once."""
    for item in items:
        if item == value:
            return
    items.append(value)


def _discard(mut items: List[Int], value: Int):
    """Remove a value from a list that holds each value once."""
    for i in range(len(items)):
        if items[i] == value:
            _ = items.pop(i)
            return


@fieldwise_init
struct _Entry(ImplicitlyCopyable, Movable):
    """A candidate collapse: its cost, its ends and their versions."""

    var cost: Float64
    var u: Int
    var v: Int
    var vu: Int
    var vv: Int

    def before(self, other: _Entry) -> Bool:
        """Return True when this entry sorts first, as Python's tuples do."""
        if self.cost != other.cost:
            return self.cost < other.cost
        if self.u != other.u:
            return self.u < other.u
        if self.v != other.v:
            return self.v < other.v
        if self.vu != other.vu:
            return self.vu < other.vu
        return self.vv < other.vv


struct _Heap(Movable):
    """A binary min-heap of collapses, as `heapq` keeps one."""

    var items: List[_Entry]

    def __init__(out self):
        self.items = List[_Entry]()

    def push(mut self, entry: _Entry):
        """Add an entry."""
        self.items.append(entry)
        var at = len(self.items) - 1
        while at > 0:
            var parent = (at - 1) // 2
            if self.items[at].before(self.items[parent]):
                self.items.swap_elements(at, parent)
                at = parent
            else:
                break

    def pop(mut self) -> _Entry:
        """Remove and return the least entry."""
        var top = self.items[0]
        var last = self.items.pop()
        if len(self.items) > 0:
            self.items[0] = last
            var at = 0
            while True:
                var left = 2 * at + 1
                var right = left + 1
                var least = at
                if left < len(self.items) and self.items[left].before(
                    self.items[least]
                ):
                    least = left
                if right < len(self.items) and self.items[right].before(
                    self.items[least]
                ):
                    least = right
                if least == at:
                    break
                self.items.swap_elements(at, least)
                at = least
        return top


struct _Decimation(Movable):
    """The state of one decimation."""

    var points: List[P3]
    var faces: List[Int]
    var alive: List[Bool]
    var around: List[List[Int]]
    var present: List[Bool]
    var fixed: List[Bool]
    var quadric: List[Float64]
    var version: List[Int]
    var heap: _Heap

    def __init__(out self, points: List[P3], triangles: List[Int]):
        self.points = points.copy()
        self.faces = triangles.copy()
        var count = len(triangles) // 3
        self.alive = List[Bool](length=count, fill=True)
        var size = len(points)
        for v in triangles:
            size = max(size, v + 1)
        self.around = List[List[Int]](length=size, fill=List[Int]())
        self.present = List[Bool](length=size, fill=False)
        self.fixed = List[Bool](length=size, fill=False)
        self.quadric = List[Float64](length=10 * size, fill=0.0)
        self.version = List[Int](length=size, fill=0)
        self.heap = _Heap()
        for f in range(count):
            for k in range(3):
                var v = triangles[3 * f + k]
                _add_once(self.around[v], f)
                self.present[v] = True

    def neighbors(self, v: Int) -> List[Int]:
        """Return the vertices that share a face with `v`, sorted."""
        var found = List[Int]()
        for f in self.around[v]:
            for k in range(3):
                var w = self.faces[3 * f + k]
                if w != v:
                    _add_once(found, w)
        sort(found)
        return found^

    def cost(self, u: Int, v: Int) -> Float64:
        """Return the cost of moving `u` onto `v`."""
        var q = List[Float64](capacity=10)
        for k in range(10):
            q.append(self.quadric[10 * u + k] + self.quadric[10 * v + k])
        return _cost(Span(q), self.points[v])

    def push(mut self, u: Int):
        """Queue every collapse of `u` onto a neighbor."""
        if self.fixed[u]:
            return
        for v in self.neighbors(u):
            self.heap.push(
                _Entry(self.cost(u, v), u, v, self.version[u], self.version[v])
            )

    def corner(self, f: Int, k: Int) -> P3:
        """Return a face's corner as a point."""
        return self.points[self.faces[3 * f + k]]


def _shared(a: List[Int], b: List[Int]) -> Int:
    """Return how many values two sorted lists share."""
    var i = 0
    var j = 0
    var count = 0
    while i < len(a) and j < len(b):
        if a[i] == b[j]:
            count += 1
            i += 1
            j += 1
        elif a[i] < b[j]:
            i += 1
        else:
            j += 1
    return count


def _contains(items: List[Int], value: Int) -> Bool:
    """Return True when a list holds a value."""
    for item in items:
        if item == value:
            return True
    return False


def decimate(
    points: List[P3], triangles: List[Int], target: Int
) raises -> List[Int]:
    """Return fewer triangles over the same vertices that keep the shape.

    Garland and Heckbert's quadric error: each edge's cost is how far its
    end would lie from the planes of the triangles round both its ends.
    The cheapest edge collapses first, one end onto the other, so every
    vertex that stays is one of the mesh's own. A collapse that would
    flip a triangle, pinch the mesh, or move a vertex of a hole is left
    out, so the holes keep their loops.

    Args:
        points: The vertices.
        triangles: Three vertex indices each, wound alike.
        target: How many triangles to stop at.

    Returns:
        The triangles left, three indices of `points` each.

    Raises:
        Error: If a triangle names a vertex past `points`.
    """
    for v in triangles:
        if v < 0 or v >= len(points):
            raise Error("A triangle names a vertex past the points")
    var state = _Decimation(points, triangles)
    var count = len(triangles) // 3
    var uses = Dict[Int, Int]()
    for f in range(count):
        for k in range(3):
            var key = _edge_key(
                triangles[3 * f + k], triangles[3 * f + (k + 1) % 3]
            )
            uses[key] = uses.get(key, 0) + 1
    for entry in uses.items():
        if entry.value == 1:
            state.fixed[entry.key >> 32] = True
            state.fixed[entry.key & 0xFFFFFFFF] = True
    for f in range(count):
        var q = plane_quadric(
            state.corner(f, 0), state.corner(f, 1), state.corner(f, 2)
        )
        if not q:
            continue
        var entries = q.value().copy()
        for k in range(3):
            var v = triangles[3 * f + k]
            for m in range(10):
                state.quadric[10 * v + m] = (
                    state.quadric[10 * v + m] + entries[m]
                )
    for u in range(len(state.present)):
        if state.present[u]:
            state.push(u)
    while count > target and len(state.heap.items) > 0:
        var entry = state.heap.pop()
        var u = entry.u
        var v = entry.v
        if (
            state.version[u] != entry.vu
            or state.version[v] != entry.vv
            or not state.present[u]
        ):
            continue
        var around_u = state.neighbors(u)
        if not _contains(around_u, v):
            continue
        # The link condition: the two ends share only the two corners
        # across their edge, so the collapse does not pinch the mesh.
        if _shared(around_u, state.neighbors(v)) != 2:
            continue
        var flips = False
        for f in state.around[u]:
            var t0 = state.faces[3 * f]
            var t1 = state.faces[3 * f + 1]
            var t2 = state.faces[3 * f + 2]
            if t0 == v or t1 == v or t2 == v:
                continue
            var before = normal(
                state.points[t0], state.points[t1], state.points[t2]
            )
            var m0 = v if t0 == u else t0
            var m1 = v if t1 == u else t1
            var m2 = v if t2 == u else t2
            var after = normal(
                state.points[m0], state.points[m1], state.points[m2]
            )
            var dot = float_sum(
                [
                    product(before.x, after.x),
                    product(before.y, after.y),
                    product(before.z, after.z),
                ]
            )
            var size = product(
                power(
                    float_sum(
                        [
                            product(before.x, before.x),
                            product(before.y, before.y),
                            product(before.z, before.z),
                        ]
                    ),
                    0.5,
                ),
                power(
                    float_sum(
                        [
                            product(after.x, after.x),
                            product(after.y, after.y),
                            product(after.z, after.z),
                        ]
                    ),
                    0.5,
                ),
            )
            if size == 0 or dot < 0.3 * size:
                flips = True
                break
        if flips:
            continue
        var faces_u = state.around[u].copy()
        for f in faces_u:
            var has_v = False
            for k in range(3):
                if state.faces[3 * f + k] == v:
                    has_v = True
            if has_v:
                state.alive[f] = False
                count -= 1
                for k in range(3):
                    var w = state.faces[3 * f + k]
                    if w != u:
                        _discard(state.around[w], f)
            else:
                for k in range(3):
                    if state.faces[3 * f + k] == u:
                        state.faces[3 * f + k] = v
                _add_once(state.around[v], f)
        state.around[u] = List[Int]()
        state.present[u] = False
        for k in range(10):
            state.quadric[10 * v + k] = (
                state.quadric[10 * u + k] + state.quadric[10 * v + k]
            )
        state.version[v] += 1
        for w in state.neighbors(v):
            state.version[w] += 1
        state.push(v)
        for w in state.neighbors(v):
            state.push(w)
    var kept = List[Int]()
    for f in range(len(state.alive)):
        if state.alive[f]:
            for k in range(3):
                kept.append(state.faces[3 * f + k])
    return kept^


# --- following the coarse copy ---------------------------------------------------


def _sub(u: P3, v: P3) -> P3:
    """Return u - v."""
    return P3(u.x - v.x, u.y - v.y, u.z - v.z)


def _dot(u: P3, v: P3) -> Float64:
    """Return the dot product, added from left to right."""
    return product(u.x, v.x) + product(u.y, v.y) + product(u.z, v.z)


def closest(p: P3, a: P3, b: P3, c: P3) -> Closest:
    """Return the squared distance from `p` to a triangle and the nearest
    point's weights on `b` and `c` (Ericson, 5.1.5).

    Args:
        p: The point.
        a: The first corner.
        b: The second corner.
        c: The third corner.

    Returns:
        The squared distance and the two weights.
    """
    var ab = _sub(b, a)
    var ac = _sub(c, a)
    var ap = _sub(p, a)
    var n = normal(a, b, c)
    if _dot(n, n) == 0:
        # A flat triangle is the segment between its farthest corners.
        var starts: List[P3] = [a, a, b]
        var ends: List[P3] = [b, c, c]
        var w0: List[Float64] = [0.0, 0.0, 0.0, 0.0, 1.0, 0.0]
        var w1: List[Float64] = [1.0, 0.0, 0.0, 1.0, 0.0, 1.0]
        var pick = 0
        var longest = 0.0
        for e in range(3):
            var d = _sub(ends[e], starts[e])
            var size = _dot(d, d)
            if e == 0 or size > longest:
                pick = e
                longest = size
        var start = starts[pick]
        var direction = _sub(ends[pick], start)
        var length2 = _dot(direction, direction)
        var t = 0.0
        if length2 != 0:
            t = _dot(_sub(p, start), direction) / length2
            # Python's min and max keep the first of equal values.
            if not (t < 1.0):
                t = 1.0
            if not (t > 0.0):
                t = 0.0
        var q = P3(
            start.x + product(direction.x, t),
            start.y + product(direction.y, t),
            start.z + product(direction.z, t),
        )
        var gap = _sub(q, p)
        var x0 = w0[2 * pick]
        var y0 = w0[2 * pick + 1]
        var x1 = w1[2 * pick]
        var y1 = w1[2 * pick + 1]
        return Closest(
            _dot(gap, gap),
            x0 + product(x1 - x0, t),
            y0 + product(y1 - y0, t),
        )
    var d1 = _dot(ab, ap)
    var d2 = _dot(ac, ap)
    var v: Float64
    var w: Float64
    if d1 <= 0 and d2 <= 0:
        v = 0.0
        w = 0.0
    else:
        var bp = _sub(p, b)
        var d3 = _dot(ab, bp)
        var d4 = _dot(ac, bp)
        var cp = _sub(p, c)
        var d5 = _dot(ab, cp)
        var d6 = _dot(ac, cp)
        var vc = product(d1, d4) - product(d3, d2)
        var vb = product(d5, d2) - product(d1, d6)
        var va = product(d3, d6) - product(d5, d4)
        if d3 >= 0 and d4 <= d3:
            v = 1.0
            w = 0.0
        elif vc <= 0 and d1 >= 0 and d3 <= 0:
            v = d1 / (d1 - d3)
            w = 0.0
        elif d6 >= 0 and d5 <= d6:
            v = 0.0
            w = 1.0
        elif vb <= 0 and d2 >= 0 and d6 <= 0:
            v = 0.0
            w = d2 / (d2 - d6)
        elif va <= 0 and (d4 - d3) >= 0 and (d5 - d6) >= 0:
            w = (d4 - d3) / ((d4 - d3) + (d5 - d6))
            v = 1 - w
        else:
            var denom = 1 / (va + vb + vc)
            v = product(vb, denom)
            w = product(vc, denom)
    var q = P3(
        a.x + product(ab.x, v) + product(ac.x, w),
        a.y + product(ab.y, v) + product(ac.y, w),
        a.z + product(ab.z, v) + product(ac.z, w),
    )
    var gap = _sub(q, p)
    return Closest(_dot(gap, gap), v, w)


def _cell(value: Float64, cell: Float64) raises -> Int:
    """Return `int(value // cell)`."""
    var index = Int(floor_divide(value, cell))
    if index <= -_CELL_BIAS or index >= _CELL_BIAS:
        raise Error("A point lies too far out for the search grid")
    return index


def _cell_key(i: Int, j: Int, m: Int) -> Int:
    """Return one key for a cell of the grid."""
    return (
        ((i + _CELL_BIAS) << 42) | ((j + _CELL_BIAS) << 21) | (m + _CELL_BIAS)
    )


def follow(
    points: List[P3], coarse: List[Int], skin_end: Int, cell: Float64 = CELL
) raises -> Following:
    """Return how the skin follows its coarse copy.

    A vertex of the coarse copy follows itself. Any other skin vertex
    follows the coarse triangle nearest it, found ring by ring through a
    grid of cells.

    Args:
        points: The vertices.
        coarse: The coarse triangles, three vertex indices each.
        skin_end: The first vertex that is not skin.
        cell: The side of a grid cell.

    Returns:
        The coarse copy's vertices; its edges, each once, numbered among
        those vertices; and for each skin vertex the three corners of the
        coarse triangle nearest it, numbered the same way, with its
        weights on the second and the third.

    Raises:
        Error: If there is skin but no coarse triangle.
    """
    if skin_end > 0 and len(coarse) == 0:
        raise Error("Skin followers need coarse triangles")
    var seen = Set[Int]()
    for v in coarse:
        seen.add(v)
    var used = List[Int]()
    for v in seen:
        used.append(v)
    sort(used)
    var local = Dict[Int, Int]()
    for i in range(len(used)):
        local[used[i]] = i
    var links = Set[Int]()
    for t in range(0, len(coarse), 3):
        for k in range(3):
            links.add(
                _edge_key(local[coarse[t + k]], local[coarse[t + (k + 1) % 3]])
            )
    var keys = List[Int]()
    for key in links:
        keys.append(key)
    sort(keys)
    var edges = List[Int](capacity=2 * len(keys))
    for key in keys:
        edges.append(key >> 32)
        edges.append(key & 0xFFFFFFFF)
    var cells = Dict[Int, List[Int]]()
    for index in range(len(coarse) // 3):
        var low = List[Int]()
        var high = List[Int]()
        for k in range(3):
            var least = points[coarse[3 * index]][k]
            var most = least
            for corner in range(1, 3):
                var value = points[coarse[3 * index + corner]][k]
                if value < least:
                    least = value
                if value > most:
                    most = value
            low.append(_cell(least, cell))
            high.append(_cell(most, cell))
        for i in range(low[0], high[0] + 1):
            for j in range(low[1], high[1] + 1):
                for m in range(low[2], high[2] + 1):
                    var key = _cell_key(i, j, m)
                    if key not in cells:
                        cells[key] = List[Int]()
                    cells[key].append(index)
    var corners = List[Int]()
    var weights = List[Float64]()
    for v in range(skin_end):
        if v in local:
            var own = local[v]
            corners.append(own)
            corners.append(own)
            corners.append(own)
            weights.append(0.0)
            weights.append(0.0)
            continue
        var p = points[v]
        var home0 = _cell(p.x, cell)
        var home1 = _cell(p.y, cell)
        var home2 = _cell(p.z, cell)
        var found = False
        var best = Closest(0.0, 0.0, 0.0)
        var best_triangle = 0
        var reach = 1
        while True:
            for i in range(home0 - reach, home0 + reach + 1):
                for j in range(home1 - reach, home1 + reach + 1):
                    for m in range(home2 - reach, home2 + reach + 1):
                        if (
                            reach > 1
                            and max(
                                abs(i - home0), abs(j - home1), abs(m - home2)
                            )
                            < reach
                        ):
                            continue
                        var key = _cell_key(i, j, m)
                        if key not in cells:
                            continue
                        for index in cells[key]:
                            var near = closest(
                                p,
                                points[coarse[3 * index]],
                                points[coarse[3 * index + 1]],
                                points[coarse[3 * index + 2]],
                            )
                            if not found or near.distance2 < best.distance2:
                                found = True
                                best = near
                                best_triangle = index
            # Every unvisited cell lies at least reach * cell away.
            # A populated ring alone does not prove its closest is best.
            if found and best.distance2 <= _square(
                product(Float64(reach), cell)
            ):
                break
            reach += 1
        for k in range(3):
            corners.append(local[coarse[3 * best_triangle + k]])
        weights.append(best.wb)
        weights.append(best.wc)
    return Following(used^, edges^, corners^, weights^)


# --- the file ------------------------------------------------------------------


def _obj_names(folder: String) raises -> List[String]:
    """Return the expressions' names: the `*.obj` files that are neither
    identities nor the neutral mesh, sorted, as `glob` finds them."""
    var names = List[String]()
    for entry in listdir(folder):
        var name = String(entry)
        if name.startswith(".") or not name.endswith(".obj"):
            continue
        if name.startswith("identity") or name.startswith("generic"):
            continue
        names.append(String(name[byte = : name.byte_length() - 4]))
    sort(names)
    return names^


def ictf_bytes(
    folder: String,
    identities: Int = IDENTITIES,
    skin_end: Int = SKIN_END,
    coarse_target: Int = COARSE_TRIANGLES,
) raises -> Tuple[List[UInt8], List[Int]]:
    """Return the model in `folder` as the bytes of an ICTF file.

    Args:
        folder: The folder of OBJ files.
        identities: How many identity modes to keep.
        skin_end: The first vertex that is not skin.
        coarse_target: How many triangles the coarse copy keeps.

    Returns:
        The file's bytes, and its counts: the vertices, the drawn vertices,
        the triangles and the expressions.

    Raises:
        Error: For a missing or malformed OBJ file, or a count too large
            for its field.
    """
    var neutral_mesh = read_obj(folder + "/generic_neutral_mesh.obj")
    ref neutral = neutral_mesh.points
    ref uvs = neutral_mesh.uvs
    var uv_count = len(uvs) // 2
    # A vertex on a seam of the texture is drawn once for each side.
    var drawn = Dict[Int, Int]()
    var order = List[Int]()
    var triangles = List[Int]()
    for face in neutral_mesh.faces:
        var ids = List[Int]()
        for k in range(0, len(face), 2):
            var key = face[k] * uv_count + face[k + 1]
            if key not in drawn:
                drawn[key] = len(order) // 2
                order.append(face[k])
                order.append(face[k + 1])
            ids.append(drawn[key])
        for k in range(1, len(ids) - 1):
            triangles.append(ids[0])
            triangles.append(ids[k])
            triangles.append(ids[k + 1])
    var position_of = List[Int](capacity=len(order) // 2)
    for k in range(0, len(order), 2):
        position_of.append(order[k])
    var topology = skin_topology(position_of, triangles, skin_end)
    var names = _obj_names(folder)
    var corners = List[Int]()
    for hole in topology.holes:
        corners.extend(hole.copy())
    var meters = List[P3](capacity=len(neutral))
    for p in neutral:
        meters.append(
            P3(
                product(p.x, TO_METERS),
                product(p.y, TO_METERS),
                product(p.z, TO_METERS),
            )
        )
    var coarse = decimate(meters, topology.skin, coarse_target)
    var following = follow(meters, coarse, skin_end)
    var body = List[UInt8]()
    for count in [
        len(neutral),
        len(order) // 2,
        len(triangles) // 3,
        identities,
        len(names),
        len(topology.skin) // 3,
        len(topology.edges) // 2,
        len(topology.holes),
        len(corners),
        len(coarse) // 3,
        0,
        len(following.used),
        len(following.edges) // 2,
        len(following.corners) // 3,
    ]:
        pack_u32(body, count)
    for p in meters:
        pack_f32(body, p.x)
        pack_f32(body, p.y)
        pack_f32(body, p.z)
    for k in range(1, len(order), 2):
        pack_f32(body, uvs[2 * order[k]])
        pack_f32(body, uvs[2 * order[k] + 1])
    var shorts = position_of.copy()
    shorts.extend(triangles.copy())
    shorts.extend(topology.skin.copy())
    shorts.extend(topology.edges.copy())
    for hole in topology.holes:
        shorts.append(len(hole))
    shorts.extend(corners.copy())
    shorts.extend(coarse.copy())
    shorts.extend(following.used.copy())
    shorts.extend(following.edges.copy())
    shorts.extend(following.corners.copy())
    for value in shorts:
        pack_u16(body, value)
    pad4(body)
    for value in following.weights:
        pack_f32(body, value)
    var shapes = List[UInt8]()
    for name in names:
        var points = read_obj(folder + "/" + name + ".obj").points.copy()
        var moves = displacements(points, neutral)
        var moved = List[Int]()
        for v in range(len(moves)):
            if _length(moves[v]) > STILL:
                moved.append(v)
        var deltas = List[Float64](capacity=3 * len(moved))
        for v in moved:
            deltas.append(moves[v].x)
            deltas.append(moves[v].y)
            deltas.append(moves[v].z)
        var quantized = quantize(deltas)
        for byte in name.as_bytes():
            if byte >= 128:
                raise Error("'ascii' codec can't encode the name: " + name)
        pack_u8(shapes, name.byte_length())
        shapes.extend(name.as_bytes())
        pad4(shapes)
        pack_u32(shapes, len(moved))
        pack_f32(shapes, quantized[0])
        for v in moved:
            pack_u16(shapes, v)
        pad4(shapes)
        shapes.extend(quantized[1].copy())
        pad4(shapes)
    var size = List[UInt8]()
    pack_u32(size, len(shapes))
    for k in range(4):
        body[_EXPRESSION_BYTES_AT - 8 + k] = size[k]
    body.extend(shapes^)
    for index in range(identities):
        var label = String(index)
        while label.byte_length() < 3:
            label = "0" + label
        var points = read_obj(
            folder + "/identity" + label + ".obj"
        ).points.copy()
        var moves = displacements(points, neutral)
        var deltas = List[Float64](capacity=3 * len(moves))
        for move in moves:
            deltas.append(move.x)
            deltas.append(move.y)
            deltas.append(move.z)
        var quantized = quantize(deltas)
        pack_f32(body, quantized[0])
        body.extend(quantized[1].copy())
        pad4(body)
    var out = List[UInt8]()
    out.extend("ICTF".as_bytes())
    pack_u32(out, VERSION)
    out.extend(body^)
    var counts: List[Int] = [
        len(neutral),
        len(order) // 2,
        len(triangles) // 3,
        len(names),
    ]
    return (out^, counts^)


def convert(
    folder: String,
    target: String,
    identities: Int = IDENTITIES,
    skin_end: Int = SKIN_END,
    coarse_target: Int = COARSE_TRIANGLES,
) raises -> List[Int]:
    """Write the model in `folder` to `target`.

    The file is written only once the whole model is made, so a bad source
    never replaces it.

    Args:
        folder: The folder of OBJ files.
        target: The output file.
        identities: How many identity modes to keep.
        skin_end: The first vertex that is not skin.
        coarse_target: How many triangles the coarse copy keeps.

    Returns:
        The counts: the vertices, the drawn vertices, the triangles and
        the expressions.

    Raises:
        Error: For a missing or malformed OBJ file, or a failed write.
    """
    var made = ictf_bytes(folder, identities, skin_end, coarse_target)
    Path(target).write_bytes(Span(made[0]))
    return made[1].copy()


def counts_text(counts: List[Int]) -> String:
    """Return counts as Python prints a tuple of ints.

    Args:
        counts: The counts.

    Returns:
        The counts in parentheses, separated by commas.
    """
    var text = String("(")
    for i in range(len(counts)):
        if i > 0:
            text += ", "
        text += String(counts[i])
    if len(counts) == 1:
        text += ","
    return text + ")"


def run(arguments: List[String]) raises -> Tuple[Int, String, String]:
    """Run the converter as the command line does.

    Args:
        arguments: The program name, the folder and the output file.

    Returns:
        The exit status, the standard output and the standard error.

    Raises:
        Error: If the conversion fails.
    """
    if len(arguments) != 3:
        return (2, String(), String(USAGE) + "\n")
    var counts = convert(arguments[1], arguments[2])
    return (0, counts_text(counts) + "\n", String())


def main() raises:
    """Convert the folder `argv[1]` into the file `argv[2]`.

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
