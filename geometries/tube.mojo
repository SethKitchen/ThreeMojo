# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A tube swept along a path, from three.js `src/geometries/TubeGeometry.js`
and the frames of `src/extras/core/Curve.js`.

A tube is a ring of vertices around each point of a path, joined into the
grid the torus is. What makes it more than a torus is the frame each ring
is built in: a normal and a binormal at right angles to the path's tangent,
carried along the path so that neighboring rings agree and the tube does
not twist where the path merely bends. three.js's `computeFrenetFrames`
does that by parallel transport -- each frame is the last one turned by
the angle between the last tangent and this one -- and, for a closed path,
spreads whatever twist has built up by the end evenly back along the
path, so the last ring meets the first. This is that construction, applied
to a path given as points.

There are two ways in. Given a `math.curve3.Curve3`, the tube is
three.js's `TubeGeometry` exactly: `tubular_segments` rings at equal
distances along the curve, framed by the curve's own `frenet_frames`, and
for a closed tube a last ring that repeats the first. Given a list of
points, the path *is* the points: one ring per point, and the tangent at
each point runs from the point before to the point after. A closed path is
given without repeating its first point, and its last ring repeats its
first. Either way `u` runs along the path by distance, so a long segment
gets a long stretch of the texture, as three.js's arc-length parameter
gives it.

Two paths have no frame and are refused. One returns to the point before
the last, so the tangent between them is zero and points nowhere. One
folds straight back on itself, so two consecutive tangents point opposite
ways: there is no axis to turn the frame about, and carrying it across
unturned would flip the binormal by a half turn, which is a choice no
transport made. three.js checks neither; here both raise.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from geometries.grid import grid_index
from math.curve3 import Curve3, FrenetFrames, transport_frames
from math.vector3 import Vector3
from std.math import cos, pi, sin
from units.si import Length


def _tangents(path: List[Vector3], closed: Bool) raises -> List[Vector3]:
    """Return a unit tangent per ring: from the point before to the point
    after, one-sided at the ends of an open path, and once more at the end
    of a closed one, where the ring after the last is the first again.

    Raises:
        Error: If the point before and the point after are the same, which
            leaves the tangent zero.
    """
    var count = len(path)
    var rings = count
    if not closed:
        rings = count - 1
    var tangents = List[Vector3]()
    for ring in range(rings + 1):  # pragma: no branch
        var at = ring % count
        var before = at - 1
        var after = at + 1
        if closed:
            before = (at + count - 1) % count
            after = (at + 1) % count
        else:
            if before < 0:
                before = 0
            if after >= count:
                after = count - 1
        var tangent = path[after] - path[before]
        if tangent.length() == 0:
            raise Error("A tube's path cannot return to the point before")
        tangent.normalize()
        tangents.append(tangent)
    return tangents^


def _distances(path: List[Vector3], rings: Int) -> List[Float32]:
    """Return how far along the path each ring is, from the first point,
    the closing segment included for a closed path."""
    var count = len(path)
    var along = List[Float32]()
    along.append(0)
    for ring in range(1, rings + 1):  # pragma: no branch
        var step = (path[ring % count] - path[(ring - 1) % count]).length()
        along.append(along[ring - 1] + step)
    return along^


def tube(
    path: List[Vector3],
    radius: Length,
    radial_segments: Int = 8,
    closed: Bool = False,
) raises -> BufferGeometry:
    """Return a tube of `radius` swept along `path`.

    Args:
        path: The points the tube runs through, in meters: at least two, or
            three for a closed path, no two consecutive ones the same. A
            closed path does not repeat its first point.
        radius: The tube's radius.
        radial_segments: How many cells around the tube; at least three.
        closed: True to join the last point back to the first.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes and an
        index buffer, wound counter-clockwise seen from outside. Vertices
        run in rings, one per point of the path and one more for a closed
        path, `radial_segments + 1` to a ring. `u` runs along the path by
        distance and `v` around the tube.

    Raises:
        Error: If the path is too short, two consecutive points coincide,
            the path returns to the point before the last or folds straight
            back on itself, the radius is not positive, or there are fewer
            than three segments around.
    """
    var count = len(path)
    if count < 2 or (closed and count < 3):
        raise Error("A tube needs at least two points, or three to close")
    for index in range(count):  # pragma: no branch
        var next = (index + 1) % count
        if next == 0 and not closed:
            continue
        if (path[next] - path[index]).length() == 0:
            raise Error("A tube's path cannot repeat a point")
    if radius.value <= 0:
        raise Error("A tube needs a positive radius")
    if radial_segments < 3:
        raise Error("A tube needs at least three segments around")

    var rings = count
    if not closed:
        rings = count - 1
    var frames = transport_frames(_tangents(path, closed), closed)
    var along = _distances(path, rings)
    var centers = List[Vector3]()
    var us = List[Float32]()
    for ring in range(rings + 1):  # pragma: no branch
        centers.append(path[ring % count])
        us.append(along[ring] / along[rings])
    return _sweep(centers, frames, us, radius.value, radial_segments)


def tube(
    curve: Curve3,
    radius: Length,
    tubular_segments: Int = 64,
    radial_segments: Int = 8,
    closed: Bool = False,
) raises -> BufferGeometry:
    """Return a tube of `radius` swept along `curve`, three.js's
    `TubeGeometry`.

    Args:
        curve: The curve the tube follows.
        radius: The tube's radius.
        tubular_segments: How many cells along the tube; at least one.
        radial_segments: How many cells around the tube; at least three.
        closed: True to spread the frames' twist so the last ring meets the
            first, and to put the last ring on the first.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes and an
        index buffer, wound counter-clockwise seen from outside. Vertices
        run in `tubular_segments + 1` rings at equal distances along the
        curve, `radial_segments + 1` to a ring. `u` runs along the curve
        and `v` around the tube.

    Raises:
        Error: If there are fewer than one segment along or three around,
            the radius is not positive, or the curve's frames cannot be
            built: it stops at a ring, or two rings point straight
            opposite ways.
    """
    if tubular_segments < 1:
        raise Error("A tube needs at least one segment along it")
    if radius.value <= 0:
        raise Error("A tube needs a positive radius")
    if radial_segments < 3:
        raise Error("A tube needs at least three segments around")
    var frames = curve.frenet_frames(tubular_segments, closed)
    var centers = curve.spaced_points(tubular_segments)
    if closed:
        # three.js builds the closing ring from the first ring's point and
        # frame, so the two meet exactly.
        centers[tubular_segments] = centers[0]
        frames.normals[tubular_segments] = frames.normals[0]
        frames.binormals[tubular_segments] = frames.binormals[0]
    var us = List[Float32]()
    for ring in range(tubular_segments + 1):  # pragma: no branch
        # At least one segment, so this runs.
        us.append(Float32(ring) / Float32(tubular_segments))
    return _sweep(centers, frames, us, radius.value, radial_segments)


def _sweep(
    centers: List[Vector3],
    frames: FrenetFrames,
    us: List[Float32],
    thickness: Float32,
    radial_segments: Int,
) raises -> BufferGeometry:
    """Return the rings of a tube: one about each center, in its frame,
    `thickness` meters out, with `u` from `us` and `v` around.

    Raises:
        Error: If the geometry cannot take its attributes, which cannot
            happen for rings built here.
    """
    var rings = len(centers) - 1
    var data = List[Float32]()
    var normal_data = List[Float32]()
    var uvs = List[Float32]()
    for ring in range(rings + 1):  # pragma: no branch
        var center = centers[ring]
        var u = us[ring]
        for step in range(radial_segments + 1):  # pragma: no branch
            var v = Float32(step) / Float32(radial_segments)
            var around = v * 2 * Float32(pi)
            # three.js's placement: minus the cosine along the normal, the
            # sine along the binormal, as the torus knot has it.
            var along_normal = frames.normals[ring] * (-cos(around))
            var along_binormal = frames.binormals[ring] * sin(around)
            var outward = along_normal + along_binormal
            var vertex = center + outward * thickness
            data.append(vertex.x)
            data.append(vertex.y)
            data.append(vertex.z)
            normal_data.append(outward.x)
            normal_data.append(outward.y)
            normal_data.append(outward.z)
            uvs.append(u)
            uvs.append(v)

    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(data^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(normal_data^, 3))
    geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
    geometry.set_index(grid_index(rings, radial_segments, False))
    return geometry^
