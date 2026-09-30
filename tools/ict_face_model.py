# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
"""Convert the ICT Face Model Light into `assets/face/ict_face.bin`.

    python3 tools/ict_face_model.py ICT-FaceKit/FaceXModel assets/face/ict_face.bin

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
identity modes: a head at rest needs a few expressions and no identity. A displacement is its signed byte
times its scale. The file is not compressed, so a head loads in
milliseconds.
"""

import glob
import os
import struct
import sys

IDENTITIES = 60
VERSION = 6
# Where the header's count of the expressions' bytes lies in the file.
_EXPRESSION_BYTES_AT = 48
# The face and the head: the ICT model's first vertices.
SKIN_END = 11248
# How many triangles the skin's coarse copy keeps, for distances.
COARSE_TRIANGLES = 6000
# The OBJ files are in centimeters.
TO_METERS = 0.01
# A vertex an expression moves less than this, in meters, is left out.
STILL = 1e-7


def read_obj(path):
    """Return an OBJ file's vertices, texture coordinates and faces.

    Each face is a list of (vertex, texture coordinate) index pairs,
    counted from zero.
    """
    points, uvs, faces = [], [], []
    with open(path, encoding="ascii") as source:
        for line in source:
            words = line.split()
            if not words:
                continue
            if words[0] == "v":
                points.append(tuple(float(x) for x in words[1:4]))
            elif words[0] == "vt":
                uvs.append(tuple(float(x) for x in words[1:3]))
            elif words[0] == "f":
                corners = []
                for corner in words[1:]:
                    parts = corner.split("/")
                    corners.append((int(parts[0]) - 1, int(parts[1]) - 1))
                faces.append(corners)
    return points, uvs, faces


def quantize(deltas):
    """Return the scale and the signed bytes that stand for `deltas`, a
    flat list of floats."""
    peak = max((abs(x) for x in deltas), default=0.0)
    scale = peak / 127 if peak > 0 else 1.0
    return scale, bytes(
        max(-127, min(127, round(x / scale))) & 0xFF for x in deltas
    )


def displacements(points, neutral):
    """Return each vertex's move from `neutral` to `points`, in meters."""
    if len(points) != len(neutral):
        raise ValueError("A shape needs one vertex per neutral vertex")
    return [
        tuple((p[k] - n[k]) * TO_METERS for k in range(3))
        for p, n in zip(points, neutral)
    ]


def skin_topology(position_of, triangles, skin_end=SKIN_END):
    """Return the skin's triangles, its edges and its holes.

    The skin's triangles name vertices, not drawn vertices, so they join
    across the texture's seams. A hole is a loop of edges that only one
    triangle uses, in the order the triangles run them.
    """
    skin = []
    for triangle in triangles:
        corners = tuple(position_of[d] for d in triangle)
        if all(c < skin_end for c in corners):
            skin.append(corners)
    uses = {}
    for a, b, c in skin:
        for u, v in ((a, b), (b, c), (c, a)):
            key = (min(u, v), max(u, v))
            uses[key] = uses.get(key, 0) + 1
    edges = sorted(uses)
    following = {}
    for a, b, c in skin:
        for u, v in ((a, b), (b, c), (c, a)):
            if uses[(min(u, v), max(u, v))] == 1:
                following[u] = v
    holes = []
    done = set()
    for start in sorted(following):
        if start in done:
            continue
        loop = []
        v = start
        while v not in done:
            done.add(v)
            loop.append(v)
            v = following[v]
        holes.append(loop)
    return skin, edges, holes


def _plane_quadric(a, b, c):
    """Return the quadric of the plane through three points, as the ten
    distinct entries of a symmetric 4-by-4 matrix, or None for a
    triangle with no area."""
    u = [b[k] - a[k] for k in range(3)]
    v = [c[k] - a[k] for k in range(3)]
    n = [
        u[1] * v[2] - u[2] * v[1],
        u[2] * v[0] - u[0] * v[2],
        u[0] * v[1] - u[1] * v[0],
    ]
    length = (n[0] ** 2 + n[1] ** 2 + n[2] ** 2) ** 0.5
    if length == 0:
        return None
    x, y, z = (n[k] / length for k in range(3))
    w = -(x * a[0] + y * a[1] + z * a[2])
    p = (x, y, z, w)
    return [p[i] * p[j] for i in range(4) for j in range(i, 4)]


def _cost(q, p):
    """Return the squared distance a quadric gives the point `p`."""
    x, y, z = p
    return (
        q[0] * x * x
        + 2 * q[1] * x * y
        + 2 * q[2] * x * z
        + 2 * q[3] * x
        + q[4] * y * y
        + 2 * q[5] * y * z
        + 2 * q[6] * y
        + q[7] * z * z
        + 2 * q[8] * z
        + q[9]
    )


def _normal(a, b, c):
    """Return the unnormalized normal of a triangle."""
    u = [b[k] - a[k] for k in range(3)]
    v = [c[k] - a[k] for k in range(3)]
    return (
        u[1] * v[2] - u[2] * v[1],
        u[2] * v[0] - u[0] * v[2],
        u[0] * v[1] - u[1] * v[0],
    )


def decimate(points, triangles, target):
    """Return fewer triangles over the same vertices that keep the shape.

    Garland and Heckbert's quadric error: each edge's cost is how far its
    end would lie from the planes of the triangles round both its ends.
    The cheapest edge collapses first, one end onto the other, so every
    vertex that stays is one of the mesh's own. A collapse that would
    flip a triangle, pinch the mesh, or move a vertex of a hole is left
    out, so the holes keep their loops.

    Args:
        points: The vertices, three floats each.
        triangles: Three vertex indices each, wound alike.
        target: How many triangles to stop at.

    Returns:
        The triangles left, three indices of `points` each.
    """
    import heapq

    faces = [list(t) for t in triangles]
    alive = [True] * len(faces)
    around = {}
    for f, t in enumerate(faces):
        for v in t:
            around.setdefault(v, set()).add(f)
    uses = {}
    for t in faces:
        for k in range(3):
            key = (min(t[k], t[(k + 1) % 3]), max(t[k], t[(k + 1) % 3]))
            uses[key] = uses.get(key, 0) + 1
    fixed = set()
    for (a, b), count in uses.items():
        if count == 1:
            fixed.add(a)
            fixed.add(b)
    quadric = {v: [0.0] * 10 for v in around}
    for t in faces:
        q = _plane_quadric(*(points[v] for v in t))
        if q is None:
            continue
        for v in t:
            quadric[v] = [quadric[v][k] + q[k] for k in range(10)]

    def neighbors(v):
        found = set()
        for f in around[v]:
            found.update(faces[f])
        found.discard(v)
        return found

    def cost(u, v):
        q = [quadric[u][k] + quadric[v][k] for k in range(10)]
        return _cost(q, points[v])

    heap = []
    version = {v: 0 for v in around}

    def push(u):
        if u in fixed:
            return
        for v in neighbors(u):
            heapq.heappush(heap, (cost(u, v), u, v, version[u], version[v]))

    for u in around:
        push(u)
    count = len(faces)
    while count > target and heap:
        _, u, v, vu, vv = heapq.heappop(heap)
        if version[u] != vu or version[v] != vv or u not in around:
            continue
        if v not in neighbors(u):
            continue
        # The link condition: the two ends share only the two corners
        # across their edge, so the collapse does not pinch the mesh.
        if len(neighbors(u) & neighbors(v)) != 2:
            continue
        flips = False
        for f in around[u]:
            t = faces[f]
            if v in t:
                continue
            before = _normal(*(points[w] for w in t))
            moved = [v if w == u else w for w in t]
            after = _normal(*(points[w] for w in moved))
            dot = sum(before[k] * after[k] for k in range(3))
            size = sum(x * x for x in before) ** 0.5 * sum(
                x * x for x in after
            ) ** 0.5
            if size == 0 or dot < 0.3 * size:
                flips = True
                break
        if flips:
            continue
        for f in list(around[u]):
            t = faces[f]
            if v in t:
                alive[f] = False
                count -= 1
                for w in t:
                    if w != u:
                        around[w].discard(f)
            else:
                faces[f] = [v if w == u else w for w in t]
                around[v].add(f)
        del around[u]
        quadric[v] = [quadric[u][k] + quadric[v][k] for k in range(10)]
        version[v] += 1
        for w in neighbors(v):
            version[w] += 1
        push(v)
        for w in neighbors(v):
            push(w)
    return [tuple(faces[f]) for f in range(len(faces)) if alive[f]]


def _closest(p, a, b, c):
    """Return the squared distance from `p` to a triangle and the nearest
    point's weights on `b` and `c` (Ericson, 5.1.5)."""

    def sub(u, v):
        return (u[0] - v[0], u[1] - v[1], u[2] - v[2])

    def dot(u, v):
        return u[0] * v[0] + u[1] * v[1] + u[2] * v[2]

    ab, ac, ap = sub(b, a), sub(c, a), sub(p, a)
    d1, d2 = dot(ab, ap), dot(ac, ap)
    if d1 <= 0 and d2 <= 0:
        v, w = 0.0, 0.0
    else:
        bp = sub(p, b)
        d3, d4 = dot(ab, bp), dot(ac, bp)
        cp = sub(p, c)
        d5, d6 = dot(ab, cp), dot(ac, cp)
        vc = d1 * d4 - d3 * d2
        vb = d5 * d2 - d1 * d6
        va = d3 * d6 - d5 * d4
        if d3 >= 0 and d4 <= d3:
            v, w = 1.0, 0.0
        elif vc <= 0 and d1 >= 0 and d3 <= 0:
            v, w = d1 / (d1 - d3), 0.0
        elif d6 >= 0 and d5 <= d6:
            v, w = 0.0, 1.0
        elif vb <= 0 and d2 >= 0 and d6 <= 0:
            v, w = 0.0, d2 / (d2 - d6)
        elif va <= 0 and (d4 - d3) >= 0 and (d5 - d6) >= 0:
            w = (d4 - d3) / ((d4 - d3) + (d5 - d6))
            v = 1 - w
        else:
            denom = 1 / (va + vb + vc)
            v, w = vb * denom, vc * denom
    q = tuple(a[k] + ab[k] * v + ac[k] * w for k in range(3))
    gap = sub(q, p)
    return dot(gap, gap), v, w


def follow(points, coarse, skin_end, cell=0.015):
    """Return how the skin follows its coarse copy.

    Returns the coarse copy's vertices; its edges, each once, numbered
    among those vertices; and for each skin vertex the three corners of
    the coarse triangle nearest it, numbered the same way, with its
    weights on the second and the third. A vertex of the coarse copy
    follows itself.
    """
    used = sorted({v for t in coarse for v in t})
    local = {v: i for i, v in enumerate(used)}
    edges = sorted(
        {
            (min(local[t[k]], local[t[(k + 1) % 3]]), max(local[t[k]], local[t[(k + 1) % 3]]))
            for t in coarse
            for k in range(3)
        }
    )

    def key(p):
        return tuple(int(p[k] // cell) for k in range(3))

    cells = {}
    for index, t in enumerate(coarse):
        corners = [points[v] for v in t]
        low = key([min(c[k] for c in corners) for k in range(3)])
        high = key([max(c[k] for c in corners) for k in range(3)])
        for i in range(low[0], high[0] + 1):
            for j in range(low[1], high[1] + 1):
                for m in range(low[2], high[2] + 1):
                    cells.setdefault((i, j, m), []).append(index)
    followers = []
    for v in range(skin_end):
        if v in local:
            followers.append((local[v], local[v], local[v], 0.0, 0.0))
            continue
        home = key(points[v])
        best = None
        reach = 1
        while best is None:
            for i in range(home[0] - reach, home[0] + reach + 1):
                for j in range(home[1] - reach, home[1] + reach + 1):
                    for m in range(home[2] - reach, home[2] + reach + 1):
                        for index in cells.get((i, j, m), []):
                            t = coarse[index]
                            d, wb, wc = _closest(
                                points[v], *(points[u] for u in t)
                            )
                            if best is None or d < best[0]:
                                best = (d, t, wb, wc)
            reach += 1
        _, t, wb, wc = best
        followers.append((local[t[0]], local[t[1]], local[t[2]], wb, wc))
    return used, edges, followers


def _pad(body):
    """Pad `body` with zeros to a multiple of four bytes."""
    body += b"\0" * (-len(body) % 4)


def convert(
    folder,
    out,
    identities=IDENTITIES,
    skin_end=SKIN_END,
    coarse_target=COARSE_TRIANGLES,
):
    """Write the model in `folder` to `out` and return its counts: the
    vertices, the drawn vertices, the triangles and the expressions."""
    neutral, uvs, faces = read_obj(
        os.path.join(folder, "generic_neutral_mesh.obj")
    )
    # A vertex on a seam of the texture is drawn once for each side.
    drawn = {}
    order = []
    triangles = []
    for face in faces:
        ids = []
        for corner in face:
            if corner not in drawn:
                drawn[corner] = len(order)
                order.append(corner)
            ids.append(drawn[corner])
        for k in range(1, len(ids) - 1):
            triangles.append((ids[0], ids[k], ids[k + 1]))
    position_of = [p for p, _ in order]
    skin, edges, holes = skin_topology(position_of, triangles, skin_end)
    names = sorted(
        os.path.basename(path)[:-4]
        for path in glob.glob(os.path.join(folder, "*.obj"))
        if not os.path.basename(path).startswith(("identity", "generic"))
    )
    corners = [v for hole in holes for v in hole]
    body = bytearray()
    meters = [tuple(x * TO_METERS for x in p) for p in neutral]
    coarse = decimate(meters, skin, coarse_target)
    used, links, followers = follow(meters, coarse, skin_end)
    body += struct.pack(
        "<14I",
        len(neutral),
        len(order),
        len(triangles),
        identities,
        len(names),
        len(skin),
        len(edges),
        len(holes),
        len(corners),
        len(coarse),
        0,
        len(used),
        len(links),
        len(followers),
    )
    for p in neutral:
        body += struct.pack("<3f", *(x * TO_METERS for x in p))
    for _, t in order:
        body += struct.pack("<2f", *uvs[t])
    shorts = list(position_of)
    shorts += [v for triangle in triangles for v in triangle]
    shorts += [v for triangle in skin for v in triangle]
    shorts += [v for edge in edges for v in edge]
    shorts += [len(hole) for hole in holes]
    shorts += corners
    shorts += [v for triangle in coarse for v in triangle]
    shorts += used
    shorts += [v for link in links for v in link]
    shorts += [v for f in followers for v in f[:3]]
    body += struct.pack("<%dH" % len(shorts), *shorts)
    _pad(body)
    for f in followers:
        body += struct.pack("<2f", f[3], f[4])
    shapes = bytearray()
    for name in names:
        points, _, _ = read_obj(os.path.join(folder, name + ".obj"))
        moves = displacements(points, neutral)
        moved = [
            v
            for v, move in enumerate(moves)
            if sum(x * x for x in move) ** 0.5 > STILL
        ]
        scale, packed = quantize([x for v in moved for x in moves[v]])
        encoded = name.encode("ascii")
        shapes += struct.pack("<B", len(encoded)) + encoded
        _pad(shapes)
        shapes += struct.pack("<If", len(moved), scale)
        shapes += struct.pack("<%dH" % len(moved), *moved)
        _pad(shapes)
        shapes += packed
        _pad(shapes)
    body[_EXPRESSION_BYTES_AT - 8 : _EXPRESSION_BYTES_AT - 4] = struct.pack(
        "<I", len(shapes)
    )
    body += shapes
    for index in range(identities):
        points, _, _ = read_obj(
            os.path.join(folder, "identity%03d.obj" % index)
        )
        moves = displacements(points, neutral)
        scale, packed = quantize([x for move in moves for x in move])
        body += struct.pack("<f", scale) + packed
        _pad(body)
    with open(out, "wb") as sink:
        sink.write(b"ICTF" + struct.pack("<I", VERSION) + bytes(body))
    return len(neutral), len(order), len(triangles), len(names)


def main(argv):
    """Convert the folder `argv[1]` into the file `argv[2]`."""
    if len(argv) != 3:
        print("usage: ict_face_model.py FaceXModel OUT", file=sys.stderr)
        return 2
    print(convert(argv[1], argv[2]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
