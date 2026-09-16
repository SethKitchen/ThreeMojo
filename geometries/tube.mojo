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

three.js samples its path from a curve. There are no curve types here yet,
so the path *is* the points: one ring per point, and the tangent at each
point runs from the point before to the point after. A closed path is
given without repeating its first point, and its last ring repeats its
first. `u` runs along the path by distance, so a long segment gets a long
stretch of the texture, as three.js's arc-length parameter gives it.

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
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.math import acos, cos, pi, sin
from units.si import Angle, Length, RADIAN

# Below this the two tangents are parallel and there is no axis to turn
# the frame about; three.js's threshold.
comptime STRAIGHT = Float32(1e-4)


def _clamp_unit(value: Float32) -> Float32:
    """Return `value` held to minus one through one, for `acos`."""
    return max(Float32(-1), min(Float32(1), value))


def _turned(v: Vector3, axis: Vector3, angle: Float32) -> Vector3:
    """Return `v` turned about the unit `axis` by `angle` radians."""
    return Quaternion.from_axis_angle(axis, Angle(angle, RADIAN)).rotate(v)


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


def _first_normal(tangent: Vector3) -> Vector3:
    """Return a direction at right angles to the first tangent, three.js's
    choice: the axis the tangent leans least along, turned against it."""
    var smallest = abs(tangent.x)
    var axis = Vector3(1, 0, 0)
    if abs(tangent.y) <= smallest:
        smallest = abs(tangent.y)
        axis = Vector3(0, 1, 0)
    if abs(tangent.z) <= smallest:
        axis = Vector3(0, 0, 1)
    var across = tangent
    across.cross(axis)
    across.normalize()
    var normal = tangent
    normal.cross(across)
    return normal


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
    var tangents = _tangents(path, closed)

    # The frames, by parallel transport: each normal is the last one turned
    # about the axis between the last tangent and this one, by the angle
    # between them, and the binormal follows.
    var normals = List[Vector3]()
    var binormals = List[Vector3]()
    normals.append(_first_normal(tangents[0]))
    var first_binormal = tangents[0]
    first_binormal.cross(normals[0])
    binormals.append(first_binormal)
    for ring in range(1, rings + 1):  # pragma: no branch
        var normal = normals[ring - 1]
        var axis = tangents[ring - 1]
        axis.cross(tangents[ring])
        if axis.length() > STRAIGHT:
            axis.normalize()
            var angle = acos(
                _clamp_unit(tangents[ring - 1].dot(tangents[ring]))
            )
            normal = _turned(normal, axis, angle)
        elif tangents[ring - 1].dot(tangents[ring]) < 0:
            # Parallel but opposite: no axis, and a half turn to account
            # for that no rule here decides.
            raise Error("A tube's path cannot fold straight back")
        var binormal = tangents[ring]
        binormal.cross(normal)
        normals.append(normal)
        binormals.append(binormal)

    if closed:
        # Whatever twist the transport built up between the first frame and
        # the last, spread evenly back along the path, turning each frame
        # about its own tangent, so the last ring meets the first.
        var twist = acos(_clamp_unit(normals[0].dot(normals[rings])))
        twist /= Float32(rings)
        var handed = normals[0]
        handed.cross(normals[rings])
        if tangents[0].dot(handed) > 0:
            twist = -twist
        for ring in range(1, rings + 1):  # pragma: no branch
            normals[ring] = _turned(
                normals[ring], tangents[ring], twist * Float32(ring)
            )
            var binormal = tangents[ring]
            binormal.cross(normals[ring])
            binormals[ring] = binormal

    var thickness = radius.value
    var along = _distances(path, rings)
    var data = List[Float32]()
    var normal_data = List[Float32]()
    var uvs = List[Float32]()
    for ring in range(rings + 1):  # pragma: no branch
        var center = path[ring % count]
        var u = along[ring] / along[rings]
        for step in range(radial_segments + 1):  # pragma: no branch
            var v = Float32(step) / Float32(radial_segments)
            var around = v * 2 * Float32(pi)
            # three.js's placement: minus the cosine along the normal, the
            # sine along the binormal, as the torus knot has it.
            var along_normal = normals[ring] * (-cos(around))
            var along_binormal = binormals[ring] * sin(around)
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
