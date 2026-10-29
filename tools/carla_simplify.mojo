# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Collapse a triangle mesh with quadric error.

    carla_simplify FILE

`FILE` is JSON with `points`, `triangles`, `target` and `border`.
`aggressiveness` defaults to 7. The collapses are the ones
`fast-simplification` 0.1.11 records. `border` true keeps every open
edge, as version 0.2.0 does when `preserve_border` is true. `mode`
`replay` applies a collapse list the way 0.1.11 `replay_simplification`
does, including its float32 rounding. The rule is Sven Forstmann's
quadric simplifier, published under the MIT license.
"""

from std.ffi import external_call
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_float import python_repr
from tools._python_json import (
    MISSING,
    PY_BOOL,
    PY_DICT,
    PY_INT,
    PY_LIST,
    PY_STR,
    PyJson,
)
from tools._town_json import json_number


@no_inline
def _fmul(left: Float64, right: Float64) -> Float64:
    """Return one product, rounded before the next operation."""
    return left * right


@no_inline
def _fadd(left: Float64, right: Float64) -> Float64:
    """Return one sum, rounded before the next operation."""
    return left + right


@no_inline
def _fsub(left: Float64, right: Float64) -> Float64:
    """Return one difference, rounded before the next operation."""
    return left - right


@no_inline
def _fdiv(left: Float64, right: Float64) -> Float64:
    """Return one quotient, rounded before the next operation."""
    return left / right


def simplify_text(text: String) raises -> String:
    """Return a simplified mesh as JSON.

    Args:
        text: A JSON object. A collapse request has `points`,
            `triangles`, `target` and `border`. `aggressiveness` is
            optional and defaults to 7. A replay request has `mode`
            `replay`, `points`, `triangles` and `collapses`.

    Returns:
        A collapse request returns `points`, `triangles` and
        `collapses`. A collapse `[i0, i1]` moves vertex `i1` onto
        vertex `i0`. A replay request returns `points`, `triangles`
        and `mapping`. `mapping[i]` is the new index of old vertex `i`.

    Raises:
        Error: If the JSON is not that request, an index is out of
            range, `target` is outside the mesh, or `mode` is not
            `replay`.
    """
    var doc = PyJson.parse(text)
    var root = doc.root
    if doc.kind(root) != PY_DICT:
        raise Error("simplify request is not an object")
    var mode = doc.get(root, "mode")
    if mode != MISSING:
        if doc.kind(mode) != PY_STR or doc.text(mode) != "replay":
            raise Error("mode is not replay")
        return _replay_text(doc, root)
    var points = _points(doc, doc.at(root, "points"))
    var tris = _tris(doc, doc.at(root, "triangles"), len(points))
    var target = _whole(doc, doc.at(root, "target"))
    if target < 0:
        raise Error("target is negative")
    if target > len(tris):
        raise Error("target is larger than the mesh")
    var agg = 7.0
    var agg_node = doc.get(root, "aggressiveness")
    if agg_node != MISSING:
        agg = json_number(doc, agg_node)
    var border = _flag(doc, doc.at(root, "border"))
    var result = _simplify(points^, tris^, target, agg, border)
    return _emit(result^)


def _simplify(
    var points: List[_P],
    var tris: List[_T],
    target: Int,
    agg: Float64,
    border: Bool,
) raises -> _Out:
    """Run the quadric collapse loop."""
    var refs = List[_R]()
    var collapses = List[_C]()
    var deleted_tris = 0
    var count = len(tris)
    for iteration in range(100):
        if count - deleted_tris <= target:
            break
        if iteration % 5 == 0:
            _update(points, tris, refs, iteration)
        for index in range(len(tris)):
            var face = tris[index]
            face.dirty = 0
            tris[index] = face
        var threshold = _fmul(
            0.000000001,
            external_call["pow", Float64](Float64(iteration + 3), agg),
        )
        for index in range(len(tris)):
            var face = tris[index]
            if face.e3 > threshold or face.deleted != 0 or face.dirty != 0:
                continue
            for edge in range(3):
                var err = face.e0
                if edge == 1:
                    err = face.e1
                elif edge == 2:
                    err = face.e2
                if not (err < threshold):
                    continue
                var i0 = _corner(face, edge)
                var i1 = _corner(face, (edge + 1) % 3)
                var v0 = points[i0]
                var v1 = points[i1]
                if border:
                    if v0.border != 0 or v1.border != 0:
                        continue
                elif v0.border != v1.border:
                    continue
                var place = _error(points, i0, i1)
                var gone0 = List[Int]()
                var gone1 = List[Int]()
                _fill(gone0, v0.tcount)
                _fill(gone1, v1.tcount)
                if _flipped(points, tris, refs, place, i0, i1, v0, gone0):
                    continue
                if _flipped(points, tris, refs, place, i1, i0, v1, gone1):
                    continue
                v0.x = place.x
                v0.y = place.y
                v0.z = place.z
                v0.q = _qadd(v0.q, v1.q)
                points[i0] = v0
                var tstart = len(refs)
                deleted_tris = _retie(
                    points, tris, refs, i0, v0, gone0, deleted_tris
                )
                deleted_tris = _retie(
                    points, tris, refs, i0, v1, gone1, deleted_tris
                )
                collapses.append(_C(i0, i1))
                var tcount = len(refs) - tstart
                v0 = points[i0]
                if tcount <= v0.tcount:
                    for slot in range(tcount):
                        refs[v0.tstart + slot] = refs[tstart + slot]
                else:
                    v0.tstart = tstart
                v0.tcount = tcount
                points[i0] = v0
                break
            if count - deleted_tris <= target:
                break
    _compact(points, tris)
    var out = _Out(points^, tris^, collapses^)
    return out^


@fieldwise_init
struct _Out(Movable):
    var points: List[_P]
    var tris: List[_T]
    var collapses: List[_C]


@fieldwise_init
struct _P(ImplicitlyCopyable, Movable):
    var x: Float64
    var y: Float64
    var z: Float64
    var tstart: Int
    var tcount: Int
    var q: _Q
    var border: Int


@fieldwise_init
struct _T(ImplicitlyCopyable, Movable):
    var v0: Int
    var v1: Int
    var v2: Int
    var e0: Float64
    var e1: Float64
    var e2: Float64
    var e3: Float64
    var deleted: Int
    var dirty: Int
    var nx: Float64
    var ny: Float64
    var nz: Float64


@fieldwise_init
struct _R(ImplicitlyCopyable, Movable):
    var tid: Int
    var slot: Int


@fieldwise_init
struct _C(ImplicitlyCopyable, Movable):
    var keep: Int
    var drop: Int


@fieldwise_init
struct _Q(ImplicitlyCopyable, Movable):
    var m0: Float64
    var m1: Float64
    var m2: Float64
    var m3: Float64
    var m4: Float64
    var m5: Float64
    var m6: Float64
    var m7: Float64
    var m8: Float64
    var m9: Float64


@fieldwise_init
struct _V(ImplicitlyCopyable, Movable):
    var x: Float64
    var y: Float64
    var z: Float64


def _zero() -> _Q:
    """Return a zero quadric."""
    return _Q(0, 0, 0, 0, 0, 0, 0, 0, 0, 0)


def _qget(q: _Q, index: Int) -> Float64:
    """Return one quadric entry."""
    if index == 0:
        return q.m0
    if index == 1:
        return q.m1
    if index == 2:
        return q.m2
    if index == 3:
        return q.m3
    if index == 4:
        return q.m4
    if index == 5:
        return q.m5
    if index == 6:
        return q.m6
    if index == 7:
        return q.m7
    if index == 8:
        return q.m8
    return q.m9


def _qadd(a: _Q, b: _Q) -> _Q:
    """Return the sum of two quadrics."""
    return _Q(
        _fadd(a.m0, b.m0),
        _fadd(a.m1, b.m1),
        _fadd(a.m2, b.m2),
        _fadd(a.m3, b.m3),
        _fadd(a.m4, b.m4),
        _fadd(a.m5, b.m5),
        _fadd(a.m6, b.m6),
        _fadd(a.m7, b.m7),
        _fadd(a.m8, b.m8),
        _fadd(a.m9, b.m9),
    )


def _plane(a: Float64, b: Float64, c: Float64, d: Float64) -> _Q:
    """Return the quadric of one plane."""
    return _Q(
        _fmul(a, a),
        _fmul(a, b),
        _fmul(a, c),
        _fmul(a, d),
        _fmul(b, b),
        _fmul(b, c),
        _fmul(b, d),
        _fmul(c, c),
        _fmul(c, d),
        _fmul(d, d),
    )


def _det(
    q: _Q,
    a: Int,
    b: Int,
    c: Int,
    d: Int,
    e: Int,
    f: Int,
    g: Int,
    h: Int,
    i: Int,
) -> Float64:
    """Return one 3 by 3 determinant, in the header's order."""
    var p0 = _fmul(_fmul(_qget(q, a), _qget(q, e)), _qget(q, i))
    var p1 = _fmul(_fmul(_qget(q, c), _qget(q, d)), _qget(q, h))
    var p2 = _fmul(_fmul(_qget(q, b), _qget(q, f)), _qget(q, g))
    var n0 = _fmul(_fmul(_qget(q, c), _qget(q, e)), _qget(q, g))
    var n1 = _fmul(_fmul(_qget(q, a), _qget(q, f)), _qget(q, h))
    var n2 = _fmul(_fmul(_qget(q, b), _qget(q, d)), _qget(q, i))
    var sum = _fadd(_fadd(p0, p1), p2)
    sum = _fsub(sum, n0)
    sum = _fsub(sum, n1)
    return _fsub(sum, n2)


def _verror(q: _Q, x: Float64, y: Float64, z: Float64) -> Float64:
    """Return the quadric error at one point."""
    var two = 2.0
    var t0 = _fmul(_fmul(_qget(q, 0), x), x)
    var t1 = _fmul(_fmul(_fmul(two, _qget(q, 1)), x), y)
    var t2 = _fmul(_fmul(_fmul(two, _qget(q, 2)), x), z)
    var t3 = _fmul(_fmul(two, _qget(q, 3)), x)
    var t4 = _fmul(_fmul(_qget(q, 4), y), y)
    var t5 = _fmul(_fmul(_fmul(two, _qget(q, 5)), y), z)
    var t6 = _fmul(_fmul(two, _qget(q, 6)), y)
    var t7 = _fmul(_fmul(_qget(q, 7), z), z)
    var t8 = _fmul(_fmul(two, _qget(q, 8)), z)
    var sum = t0
    sum = _fadd(sum, t1)
    sum = _fadd(sum, t2)
    sum = _fadd(sum, t3)
    sum = _fadd(sum, t4)
    sum = _fadd(sum, t5)
    sum = _fadd(sum, t6)
    sum = _fadd(sum, t7)
    sum = _fadd(sum, t8)
    return _fadd(sum, _qget(q, 9))


def _corner(face: _T, index: Int) -> Int:
    """Return one corner of a triangle."""
    if index == 0:
        return face.v0
    if index == 1:
        return face.v1
    return face.v2


def _set_corner(mut face: _T, index: Int, value: Int):
    """Write one corner of a triangle."""
    if index == 0:
        face.v0 = value
    elif index == 1:
        face.v1 = value
    else:
        face.v2 = value


def _set_err(mut face: _T, index: Int, value: Float64):
    """Write one edge error."""
    if index == 0:
        face.e0 = value
    elif index == 1:
        face.e1 = value
    else:
        face.e2 = value


def _dot(
    ax: Float64, ay: Float64, az: Float64, bx: Float64, by: Float64, bz: Float64
) -> Float64:
    """Return a dot product, left to right."""
    return _fadd(_fadd(_fmul(ax, bx), _fmul(ay, by)), _fmul(az, bz))


def _normalize(mut x: Float64, mut y: Float64, mut z: Float64):
    """Normalize a vector in place, as the header does."""
    var square = external_call["sqrt", Float64](
        _fadd(_fadd(_fmul(x, x), _fmul(y, y)), _fmul(z, z))
    )
    x = _fdiv(x, square)
    y = _fdiv(y, square)
    z = _fdiv(z, square)


def _fmin(a: Float64, b: Float64) -> Float64:
    """Return `fmin(a, b)`."""
    return external_call["fmin", Float64](a, b)


def _fill(mut slots: List[Int], count: Int):
    """Grow `slots` to `count` entries."""
    while len(slots) < count:
        slots.append(0)


def _update(
    mut points: List[_P], mut tris: List[_T], mut refs: List[_R], iteration: Int
):
    """Compact deleted triangles and rebuild the references."""
    if iteration > 0:
        var dst = 0
        for index in range(len(tris)):
            if tris[index].deleted == 0:
                tris[dst] = tris[index]
                dst += 1
        while len(tris) > dst:
            _ = tris.pop()
    if iteration == 0:
        for index in range(len(points)):
            var point = points[index]
            point.q = _zero()
            point.border = 0
            points[index] = point
        for index in range(len(tris)):
            var face = tris[index]
            var a = points[face.v0]
            var b = points[face.v1]
            var c = points[face.v2]
            var ux = _fsub(b.x, a.x)
            var uy = _fsub(b.y, a.y)
            var uz = _fsub(b.z, a.z)
            var vx = _fsub(c.x, a.x)
            var vy = _fsub(c.y, a.y)
            var vz = _fsub(c.z, a.z)
            var nx = _fsub(_fmul(uy, vz), _fmul(uz, vy))
            var ny = _fsub(_fmul(uz, vx), _fmul(ux, vz))
            var nz = _fsub(_fmul(ux, vy), _fmul(uy, vx))
            _normalize(nx, ny, nz)
            face.nx = nx
            face.ny = ny
            face.nz = nz
            tris[index] = face
            var plane = _plane(nx, ny, nz, -_dot(nx, ny, nz, a.x, a.y, a.z))
            for corner in range(3):
                var at = _corner(face, corner)
                var point = points[at]
                point.q = _qadd(point.q, plane)
                points[at] = point
        for index in range(len(tris)):
            var face = tris[index]
            var sink = _V(0, 0, 0)
            face.e0 = _error_at(points, face.v0, face.v1, sink)
            face.e1 = _error_at(points, face.v1, face.v2, sink)
            face.e2 = _error_at(points, face.v2, face.v0, sink)
            face.e3 = _fmin(face.e0, _fmin(face.e1, face.e2))
            tris[index] = face
    for index in range(len(points)):
        var point = points[index]
        point.tstart = 0
        point.tcount = 0
        points[index] = point
    for index in range(len(tris)):
        var face = tris[index]
        for corner in range(3):
            var at = _corner(face, corner)
            var point = points[at]
            point.tcount += 1
            points[at] = point
    var cursor = 0
    for index in range(len(points)):
        var point = points[index]
        point.tstart = cursor
        cursor += point.tcount
        point.tcount = 0
        points[index] = point
    refs.clear()
    for _ in range(len(tris) * 3):
        refs.append(_R(0, 0))
    for index in range(len(tris)):
        var face = tris[index]
        for corner in range(3):
            var at = _corner(face, corner)
            var point = points[at]
            refs[point.tstart + point.tcount] = _R(index, corner)
            point.tcount += 1
            points[at] = point
    if iteration == 0:
        for index in range(len(points)):
            var point = points[index]
            point.border = 0
            points[index] = point
        for index in range(len(points)):
            var point = points[index]
            var seen = List[Int]()
            var hits = List[Int]()
            for slot in range(point.tcount):
                var face = tris[refs[point.tstart + slot].tid]
                for corner in range(3):
                    var ident = _corner(face, corner)
                    var found = -1
                    for ofs in range(len(seen)):
                        if seen[ofs] == ident:
                            found = ofs
                            break
                    if found < 0:
                        seen.append(ident)
                        hits.append(1)
                    else:
                        hits[found] += 1
            for slot in range(len(hits)):
                if hits[slot] == 1:
                    var marked = points[seen[slot]]
                    marked.border = 1
                    points[seen[slot]] = marked


def _flipped(
    points: List[_P],
    tris: List[_T],
    refs: List[_R],
    place: _V,
    i0: Int,
    i1: Int,
    vertex: _P,
    mut gone: List[Int],
) -> Bool:
    """Return whether collapsing the edge flips a triangle."""
    for slot in range(vertex.tcount):
        var link = refs[vertex.tstart + slot]
        var face = tris[link.tid]
        if face.deleted != 0:
            continue
        var id1 = _corner(face, (link.slot + 1) % 3)
        var id2 = _corner(face, (link.slot + 2) % 3)
        if id1 == i1 or id2 == i1:
            gone[slot] = 1
            continue
        var d1x = _fsub(points[id1].x, place.x)
        var d1y = _fsub(points[id1].y, place.y)
        var d1z = _fsub(points[id1].z, place.z)
        var d2x = _fsub(points[id2].x, place.x)
        var d2y = _fsub(points[id2].y, place.y)
        var d2z = _fsub(points[id2].z, place.z)
        _normalize(d1x, d1y, d1z)
        _normalize(d2x, d2y, d2z)
        var aligned = _dot(d1x, d1y, d1z, d2x, d2y, d2z)
        if aligned > 0.999 or -aligned > 0.999:
            return True
        var nx = _fsub(_fmul(d1y, d2z), _fmul(d1z, d2y))
        var ny = _fsub(_fmul(d1z, d2x), _fmul(d1x, d2z))
        var nz = _fsub(_fmul(d1x, d2y), _fmul(d1y, d2x))
        _normalize(nx, ny, nz)
        gone[slot] = 0
        if _dot(nx, ny, nz, face.nx, face.ny, face.nz) < 0.2:
            return True
    return False


def _retie(
    mut points: List[_P],
    mut tris: List[_T],
    mut refs: List[_R],
    i0: Int,
    vertex: _P,
    gone: List[Int],
    deleted: Int,
) -> Int:
    """Retie one vertex's triangles and return the deleted count."""
    var removed = deleted
    for slot in range(vertex.tcount):
        var link = refs[vertex.tstart + slot]
        var face = tris[link.tid]
        if face.deleted != 0:
            continue
        if gone[slot] != 0:
            face.deleted = 1
            tris[link.tid] = face
            removed += 1
            continue
        _set_corner(face, link.slot, i0)
        face.dirty = 1
        var sink = _V(0, 0, 0)
        face.e0 = _error_at(points, face.v0, face.v1, sink)
        face.e1 = _error_at(points, face.v1, face.v2, sink)
        face.e2 = _error_at(points, face.v2, face.v0, sink)
        face.e3 = _fmin(face.e0, _fmin(face.e1, face.e2))
        tris[link.tid] = face
        refs.append(link)
    return removed


def _error(points: List[_P], i0: Int, i1: Int) -> _V:
    """Return the point an edge collapses to."""
    var sink = _V(0, 0, 0)
    _ = _error_at(points, i0, i1, sink)
    return sink


def _error_at(points: List[_P], i0: Int, i1: Int, mut place: _V) -> Float64:
    """Return the error of an edge and write its collapse point."""
    var q = _qadd(points[i0].q, points[i1].q)
    var border = (points[i0].border & points[i1].border) != 0
    var det = _det(q, 0, 1, 2, 1, 4, 5, 2, 5, 7)
    if det != 0.0 and not border:
        place.x = _fmul(_fdiv(-1.0, det), _det(q, 1, 2, 3, 4, 5, 6, 5, 7, 8))
        place.y = _fmul(_fdiv(1.0, det), _det(q, 0, 2, 3, 1, 5, 6, 2, 7, 8))
        place.z = _fmul(_fdiv(-1.0, det), _det(q, 0, 1, 3, 1, 4, 6, 2, 5, 8))
        return _verror(q, place.x, place.y, place.z)
    var a = points[i0]
    var b = points[i1]
    var mx = _fdiv(_fadd(a.x, b.x), 2.0)
    var my = _fdiv(_fadd(a.y, b.y), 2.0)
    var mz = _fdiv(_fadd(a.z, b.z), 2.0)
    var e1 = _verror(q, a.x, a.y, a.z)
    var e2 = _verror(q, b.x, b.y, b.z)
    var e3 = _verror(q, mx, my, mz)
    var error = _fmin(e1, _fmin(e2, e3))
    place.x = a.x
    place.y = a.y
    place.z = a.z
    if e2 == error:
        place.x = b.x
        place.y = b.y
        place.z = b.z
    if e3 == error:
        place.x = mx
        place.y = my
        place.z = mz
    return error


def _compact(mut points: List[_P], mut tris: List[_T]):
    """Drop deleted triangles and unused points."""
    for index in range(len(points)):
        var point = points[index]
        point.tcount = 0
        points[index] = point
    var dst = 0
    for index in range(len(tris)):
        if tris[index].deleted == 0:
            var face = tris[index]
            tris[dst] = face
            dst += 1
            for corner in range(3):
                var at = _corner(face, corner)
                var point = points[at]
                point.tcount = 1
                points[at] = point
    while len(tris) > dst:
        _ = tris.pop()
    dst = 0
    for index in range(len(points)):
        if points[index].tcount != 0:
            var point = points[index]
            point.tstart = dst
            var packed = points[dst]
            packed.x = point.x
            packed.y = point.y
            packed.z = point.z
            points[dst] = packed
            points[index] = point
            dst += 1
    for index in range(len(tris)):
        var face = tris[index]
        face.v0 = points[face.v0].tstart
        face.v1 = points[face.v1].tstart
        face.v2 = points[face.v2].tstart
        tris[index] = face
    while len(points) > dst:
        _ = points.pop()


def _f32(value: Float64) -> Float64:
    """Return `value` rounded to float32 and back."""
    return Float64(Float32(value))


@fieldwise_init
struct _Edge(ImplicitlyCopyable, Movable):
    var a: Int
    var b: Int


@fieldwise_init
struct _Replay(Movable):
    var points: List[_V]
    var tris: List[_T]
    var mapping: List[Int]


def _replay_text(doc: PyJson, root: Int) raises -> String:
    """Return one replayed mesh as JSON."""
    var points = _points(doc, doc.at(root, "points"))
    var count = len(points)
    var tris = _tris(doc, doc.at(root, "triangles"), count)
    var collapses = _pairs(doc, doc.at(root, "collapses"), count)
    var result = _replay(points^, tris^, collapses)
    return _emit_replay(result^)


def _replay(
    var points: List[_P], var tris: List[_T], collapses: List[_C]
) raises -> _Replay:
    """Replay collapses and return points, triangles and the index map."""
    for index in range(len(points)):
        var point = points[index]
        point.x = _f32(point.x)
        point.y = _f32(point.y)
        point.z = _f32(point.z)
        points[index] = point
    var refs = List[_R]()
    _update(points, tris, refs, 0)
    for index in range(len(collapses)):
        var keep = collapses[index].keep
        var drop = collapses[index].drop
        var place = _error(points, keep, drop)
        var head = points[keep]
        var tail = points[drop]
        head.x = place.x
        head.y = place.y
        head.z = place.z
        head.q = _qadd(tail.q, head.q)
        points[keep] = head
        tail = points[drop]
        tail.tcount = 0
        points[drop] = tail
    var count = len(points)
    var kept = List[_V]()
    for index in range(count):
        if points[index].tcount != 0:
            var point = points[index]
            kept.append(_V(_f32(point.x), _f32(point.y), _f32(point.z)))
    var indice = _indice_mapping(collapses, count)
    var edges = List[_Edge]()
    var faces = List[_T]()
    _clean(_mapped(tris, indice), edges, faces)
    return _settle(kept^, edges^, faces^, indice^)


def _indice_mapping(collapses: List[_C], count: Int) raises -> List[Int]:
    """Return the old-to-new index map from a collapse list."""
    var mapping = List[Int]()
    for index in range(count):
        mapping.append(index)
    var origin = List[Int]()
    var dest = List[Int]()
    for index in range(len(collapses)):
        origin.append(collapses[index].drop)
        dest.append(collapses[index].keep)
    if len(origin) > 0:
        for index in range(len(origin)):
            mapping[origin[index]] = dest[index]
        var guard = 0
        while True:
            guard += 1
            if guard > count + 2:
                raise Error("collapse map does not settle")
            var rhs = List[Int]()
            for index in range(len(origin)):
                rhs.append(mapping[mapping[origin[index]]])
            var changed = False
            for index in range(len(origin)):
                var at = origin[index]
                if mapping[at] != rhs[index]:
                    changed = True
                mapping[at] = rhs[index]
            if not changed:
                break
    var seen = List[Int]()
    for _ in range(count):
        seen.append(0)
    for index in range(len(origin)):
        seen[origin[index]] = 1
    var keep = List[Int]()
    for index in range(count):
        if seen[index] == 0:
            keep.append(index)
    var application = List[Int]()
    for _ in range(count):
        application.append(0)
    var cursor = 0
    for index in range(count):
        if cursor == len(keep):
            break
        if index == keep[cursor]:
            application[index] = cursor
            cursor += 1
    var out = List[Int]()
    for index in range(count):
        out.append(application[mapping[index]])
    return out^


def _mapped(tris: List[_T], indice: List[Int]) -> List[_T]:
    """Return triangles with the collapse map applied."""
    var out = List[_T]()
    for index in range(len(tris)):
        var face = tris[index]
        out.append(
            _T(
                indice[face.v0],
                indice[face.v1],
                indice[face.v2],
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
            )
        )
    return out^


def _clean(mapped: List[_T], mut edges: List[_Edge], mut tris: List[_T]):
    """Drop degenerate triangles and keep one edge from each."""
    for index in range(len(mapped)):
        var face = mapped[index]
        var j = face.v0
        var k = face.v1
        var l = face.v2
        if j != k and j != l and k != l:
            tris.append(_T(j, k, l, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        elif j != k:
            edges.append(_Edge(j, k))
        elif j != l:
            edges.append(_Edge(j, l))
        elif l != k:
            edges.append(_Edge(l, k))


def _at(values: List[Int], index: Int) raises -> Int:
    """Return one mapped index."""
    if index < 0 or index >= len(values):
        raise Error("replay index is out of range")
    return values[index]


def _mark(mut marks: List[Int], index: Int):
    """Mark an index that is inside the point list."""
    if index >= 0 and index < len(marks):
        marks[index] = 1


def _on(marks: List[Int], index: Int) -> Bool:
    """Return whether an index is marked."""
    return index >= 0 and index < len(marks) and marks[index] != 0


def _flags(count: Int, ids: List[Int]) -> List[Int]:
    """Return a mark for each id."""
    var marks = List[Int]()
    for _ in range(count):
        marks.append(0)
    for index in range(len(ids)):
        marks[ids[index]] = 1
    return marks^


def _bind(
    mut link: List[Int], edges: List[_Edge], tris: List[_T], count: Int
) raises -> List[Int]:
    """Merge edge-only points into triangle points and mark deletions."""
    var in_tri = List[Int]()
    var in_edge = List[Int]()
    for _ in range(count):
        in_tri.append(0)
        in_edge.append(0)
    for index in range(len(tris)):
        var face = tris[index]
        _mark(in_tri, face.v0)
        _mark(in_tri, face.v1)
        _mark(in_tri, face.v2)
    for index in range(len(edges)):
        _mark(in_edge, edges[index].a)
        _mark(in_edge, edges[index].b)
    var pending = List[Int]()
    for index in range(count):
        if in_tri[index] == 0 and in_edge[index] == 1:
            pending.append(index)
    var member = _flags(count, pending)
    var active = List[_Edge]()
    for index in range(len(edges)):
        var edge = edges[index]
        if _on(member, edge.a) or _on(member, edge.b):
            active.append(edge)
    var n_edges = len(active)
    var previous = 0
    while n_edges > 0 and n_edges != previous:
        previous = n_edges
        var both = List[_Edge]()
        var merged = List[Int]()
        var target = List[Int]()
        for index in range(len(active)):
            var edge = active[index]
            var a_on = _on(member, edge.a)
            var b_on = _on(member, edge.b)
            if a_on and b_on:
                both.append(edge)
            else:
                if a_on:
                    merged.append(edge.a)
                if b_on:
                    merged.append(edge.b)
                if not a_on:
                    target.append(edge.a)
                if not b_on:
                    target.append(edge.b)
        if len(merged) != len(target):
            raise Error("replay index is out of range")
        var rhs = List[Int]()
        for index in range(len(target)):
            rhs.append(_at(link, target[index]))
        for index in range(len(merged)):
            link[merged[index]] = rhs[index]
        var gone = List[Int]()
        for _ in range(count):
            gone.append(0)
        for index in range(len(merged)):
            var at = merged[index]
            if at >= 0 and at < count:
                gone[at] = 1
        var next_pending = List[Int]()
        for index in range(len(pending)):
            var at = pending[index]
            if gone[at] == 0:
                next_pending.append(at)
        pending = next_pending^
        member = _flags(count, pending)
        var filtered = List[_Edge]()
        for index in range(len(both)):
            var edge = both[index]
            if _on(member, edge.a) or _on(member, edge.b):
                filtered.append(edge)
        active = filtered^
        n_edges = len(active)
    var delete = List[Int]()
    for index in range(count):
        if link[index] != index:
            delete.append(1)
        else:
            delete.append(0)
    for index in range(len(pending)):
        delete[pending[index]] = 1
    return delete^


def _apply_tris(mut tris: List[_T], table: List[Int]) raises:
    """Replace each corner through `table`."""
    for index in range(len(tris)):
        var face = tris[index]
        face.v0 = _at(table, face.v0)
        face.v1 = _at(table, face.v1)
        face.v2 = _at(table, face.v2)
        tris[index] = face


def _apply_map(mut values: List[Int], table: List[Int]) raises:
    """Replace each index through `table`."""
    for index in range(len(values)):
        values[index] = _at(table, values[index])


def _shift(delete: List[Int], count: Int) -> List[Int]:
    """Return the index map after deleting marked points in order."""
    var shift = List[Int]()
    var removed = 0
    for index in range(count):
        if delete[index] != 0:
            removed += 1
        shift.append(index - removed)
    return shift^


def _settle(
    var kept: List[_V],
    var edges: List[_Edge],
    var faces: List[_T],
    var indice: List[Int],
) raises -> _Replay:
    """Merge isolated points, drop them, and renumber the mesh."""
    var count = len(kept)
    var link = List[Int]()
    for index in range(count):
        link.append(index)
    var delete = _bind(link, edges, faces, count)
    _apply_tris(faces, link)
    _apply_map(indice, link)
    var shift = _shift(delete, count)
    var live = List[_V]()
    for index in range(count):
        if delete[index] == 0:
            live.append(kept[index])
    _apply_tris(faces, shift)
    _apply_map(indice, shift)
    var result = _Replay(live^, faces^, indice^)
    return result^


def _pairs(doc: PyJson, node: Int, count: Int) raises -> List[_C]:
    """Read the collapse pairs."""
    if doc.kind(node) != PY_LIST:
        raise Error("collapses are not a list")
    var out = List[_C]()
    for index in range(doc.length(node)):
        var row = doc.item(node, index)
        if doc.kind(row) != PY_LIST or doc.length(row) != 2:
            raise Error("collapse is not 2 indices")
        var keep = _whole(doc, doc.item(row, 0))
        var drop = _whole(doc, doc.item(row, 1))
        if keep < 0 or drop < 0 or keep >= count or drop >= count:
            raise Error("collapse index is out of range")
        out.append(_C(keep, drop))
    return out^


def _emit_replay(var result: _Replay) raises -> String:
    """Return the replayed mesh as JSON."""
    var out = String('{"points":[')
    for index in range(len(result.points)):
        if index > 0:
            out += ","
        var point = result.points[index]
        out += "["
        out += python_repr(point.x)
        out += ","
        out += python_repr(point.y)
        out += ","
        out += python_repr(point.z)
        out += "]"
    out += '],"triangles":['
    for index in range(len(result.tris)):
        if index > 0:
            out += ","
        var face = result.tris[index]
        out += "["
        out += String(face.v0)
        out += ","
        out += String(face.v1)
        out += ","
        out += String(face.v2)
        out += "]"
    out += '],"mapping":['
    for index in range(len(result.mapping)):
        if index > 0:
            out += ","
        out += String(result.mapping[index])
    out += "]}"
    return out^


def _emit(var result: _Out) raises -> String:
    """Return the simplified mesh as JSON."""
    var out = String('{"points":[')
    for index in range(len(result.points)):
        if index > 0:
            out += ","
        var point = result.points[index]
        out += "["
        out += python_repr(point.x)
        out += ","
        out += python_repr(point.y)
        out += ","
        out += python_repr(point.z)
        out += "]"
    out += '],"triangles":['
    for index in range(len(result.tris)):
        if index > 0:
            out += ","
        var face = result.tris[index]
        out += "["
        out += String(face.v0)
        out += ","
        out += String(face.v1)
        out += ","
        out += String(face.v2)
        out += "]"
    out += '],"collapses":['
    for index in range(len(result.collapses)):
        if index > 0:
            out += ","
        out += "["
        out += String(result.collapses[index].keep)
        out += ","
        out += String(result.collapses[index].drop)
        out += "]"
    out += "]}"
    return out^


def _points(doc: PyJson, node: Int) raises -> List[_P]:
    """Read the vertices."""
    if doc.kind(node) != PY_LIST:
        raise Error("points are not a list")
    var out = List[_P]()
    for index in range(doc.length(node)):
        var row = doc.item(node, index)
        if doc.kind(row) != PY_LIST or doc.length(row) != 3:
            raise Error("point is not 3 numbers")
        out.append(
            _P(
                json_number(doc, doc.item(row, 0)),
                json_number(doc, doc.item(row, 1)),
                json_number(doc, doc.item(row, 2)),
                0,
                0,
                _zero(),
                0,
            )
        )
    return out^


def _tris(doc: PyJson, node: Int, count: Int) raises -> List[_T]:
    """Read the triangles."""
    if doc.kind(node) != PY_LIST:
        raise Error("triangles are not a list")
    var out = List[_T]()
    for index in range(doc.length(node)):
        var row = doc.item(node, index)
        if doc.kind(row) != PY_LIST or doc.length(row) != 3:
            raise Error("triangle is not 3 indices")
        var v0 = _whole(doc, doc.item(row, 0))
        var v1 = _whole(doc, doc.item(row, 1))
        var v2 = _whole(doc, doc.item(row, 2))
        if (
            v0 < 0
            or v1 < 0
            or v2 < 0
            or v0 >= count
            or v1 >= count
            or v2 >= count
        ):
            raise Error("triangle index is out of range")
        out.append(_T(v0, v1, v2, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    return out^


def _whole(doc: PyJson, node: Int) raises -> Int:
    """Return a JSON integer."""
    if doc.kind(node) != PY_INT:
        raise Error("index is not an integer")
    var raw = doc.text(node).as_bytes()
    var index = 0
    var negative = False
    if len(raw) > 0 and raw[0] == 45:
        negative = True
        index = 1
    var value = 0
    for offset in range(index, len(raw)):
        var byte = raw[offset]
        if byte < 48 or byte > 57:
            raise Error("index is not an integer")
        value = value * 10 + Int(byte - 48)
    if negative:
        return -value
    return value


def _flag(doc: PyJson, node: Int) raises -> Bool:
    """Return a JSON bool."""
    if doc.kind(node) != PY_BOOL:
        raise Error("border is not a bool")
    return doc.flag(node)


def main() raises:
    """Print the collapsed mesh for the JSON file on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_simplify FILE", file=stderr)
        exit(2)
    try:
        print(simplify_text(Path(arguments[1]).read_text()))
    except error:
        print("carla_simplify:", error, file=stderr)
        exit(1)
