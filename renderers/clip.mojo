# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Cutting triangles against the near and far planes before they are projected.

Perspective projection divides by depth, so a vertex level with the camera
divides by zero and one behind it divides by a negative and comes out mirrored
through the origin. A triangle with one corner behind the camera does not
project to a slightly wrong triangle; it projects to a wildly wrong one,
usually a huge wedge across the whole image.

The fix is to cut the triangle where it crosses the plane and project only the
part in front. The cut has to happen in camera space, before the divide,
because the planes are only planes there — projection is what bends them.

The far plane is cut for a different reason. Nothing divides by zero out there,
but the camera promised a frustum ending at `far`, and the depth buffer cannot
enforce it: depth starts at infinity and accepts anything smaller, and a point
past the far plane still projects to an NDC depth below infinity. A point at
z = -20 with near 0.1 and far 10 lands at about 1.0101 — outside the unit cube
the projection is defined on, and drawn anyway. Clipping is what makes `far`
mean something.

Clipping a triangle against one plane leaves a polygon of three or four
corners; against both, up to five. Fanning from the first corner turns whatever
is left into triangles. The interpolation at each cut carries every varying
with it -- color and texture coordinates, in floating point -- so a clipped
triangle shades and maps as though it were never cut.
"""

from math.vector3 import Vector3
from render.framebuffer import FloatColor


struct ClipVertex(ImplicitlyCopyable):
    """A camera-space position with the varyings that travel with it."""

    var position: Vector3
    # The surface's own color, not yet lit. Lighting happens per fragment
    # now, so what travels here is what the material says and not what one
    # corner of it happened to catch.
    var color: FloatColor
    # The world-space normal, interpolated across the triangle and normalized
    # again per fragment. A surface seen from behind is lit with this flipped,
    # which is decided after projection from the screen winding -- so unlike
    # the two colors this replaces, only one vector has to travel.
    var normal: Vector3
    # Texture coordinates. A cut has to carry these too: a triangle clipped
    # against the near plane keeps the part of the image that survived, and
    # leaving them behind would slide the texture across the cut.
    var u: Float32
    var v: Float32
    # Where this corner is in the world, for the lights that have a position.
    # A directional light needs only the normal; a point light needs to know
    # how far the surface is from the bulb and in which direction, and the
    # projection threw that away. Carried through a cut like every other
    # varying, so a clipped triangle is lit from where it really is.
    var world: Vector3
    # Light this surface gives off, linear, from the material. Carried like
    # the color, so a cut piece glows as the whole did.
    var emissive: FloatColor

    def __init__(
        out self,
        position: Vector3,
        color: FloatColor,
        normal: Vector3,
        u: Float32,
        v: Float32,
        world: Vector3 = Vector3(0, 0, 0),
        emissive: FloatColor = FloatColor(0.0, 0.0, 0.0),
    ):
        """Create a corner.

        The world position defaults to the origin, which is what a hand-built
        triangle with no point lights in reach wants, and the emissive to
        black, which is no light at all.
        """
        self.position = position
        self.color = color
        self.normal = normal
        self.u = u
        self.v = v
        self.world = world
        self.emissive = emissive


def _mix(a: Float32, b: Float32, t: Float32) -> Float32:
    """Return one color channel a fraction `t` of the way from `a` to `b`."""
    # Done in floats and kept there. Rounding to a byte at each cut, as this
    # used to, spent a level of precision every time a triangle crossed a
    # plane — and a triangle can cross two.
    return a + (b - a) * t


def _inside(z: Float32, plane_z: Float32, keep_nearer: Bool) -> Bool:
    """Return True if `z` is on the kept side of the plane at `plane_z`.

    The camera looks down -z, so depth grows more negative with distance. The
    near plane keeps what is further away than it; the far plane keeps what is
    nearer. That is the only difference between the two, which is why one
    routine clips both.
    """
    if keep_nearer:
        return z <= plane_z
    return z >= plane_z


def within_depth(z: Float32, near: Float32, far: Float32) -> Bool:
    """Return True if a camera-space depth needs no cutting at either plane.

    The same two tests `clip_depth` makes, asked of one corner. A triangle
    whose three corners all pass is left exactly as it is by the clipper --
    every corner kept, no crossing added -- so a caller can skip the clip
    and its allocations for the common case of a triangle wholly in view,
    and get the same three corners back.

    Args:
        z: The corner's camera-space z, negative in front of the camera.
        near: Distance to the near plane; the plane sits at z = -near.
        far: Distance to the far plane, at z = -far.

    Returns:
        True if the corner is at or beyond the near plane and at or before
        the far one.
    """
    return _inside(z, -near, True) and _inside(z, -far, False)


def _cross_at(a: ClipVertex, b: ClipVertex, plane_z: Float32) -> ClipVertex:
    """Return the vertex where the edge from `a` to `b` meets `plane_z`."""
    # Only called for an edge with one end on each side of the plane, so the
    # ends differ in z and the span cannot be zero. The guard is kept because
    # dividing by zero here would silently produce NaN coordinates rather than
    # a visible error.
    var span = a.position.z - b.position.z
    var t = Float32(0)
    if span != 0:  # pragma: no branch
        t = (a.position.z - plane_z) / span
    return ClipVertex(
        Vector3(
            a.position.x + (b.position.x - a.position.x) * t,
            a.position.y + (b.position.y - a.position.y) * t,
            plane_z,
        ),
        FloatColor(
            _mix(a.color.r, b.color.r, t),
            _mix(a.color.g, b.color.g, t),
            _mix(a.color.b, b.color.b, t),
            _mix(a.color.a, b.color.a, t),
        ),
        # Not renormalized here: a cut vertex is about to be interpolated
        # across a triangle anyway, and the fragment normalizes what it gets.
        Vector3(
            _mix(a.normal.x, b.normal.x, t),
            _mix(a.normal.y, b.normal.y, t),
            _mix(a.normal.z, b.normal.z, t),
        ),
        _mix(a.u, b.u, t),
        _mix(a.v, b.v, t),
        Vector3(
            _mix(a.world.x, b.world.x, t),
            _mix(a.world.y, b.world.y, t),
            _mix(a.world.z, b.world.z, t),
        ),
        FloatColor(
            _mix(a.emissive.r, b.emissive.r, t),
            _mix(a.emissive.g, b.emissive.g, t),
            _mix(a.emissive.b, b.emissive.b, t),
            _mix(a.emissive.a, b.emissive.a, t),
        ),
    )


def _clip_plane(
    polygon: List[ClipVertex], plane_z: Float32, keep_nearer: Bool
) -> List[ClipVertex]:
    """Return `polygon` cut down to the kept side of one plane.

    Sutherland-Hodgman: walk the edges, keeping every corner on the kept side
    and adding a crossing wherever an edge leaves or enters. An empty polygon
    in gives an empty polygon out, which is what lets the two planes be
    applied one after the other without a special case between them.

    Args:
        polygon: The corners, in order.
        plane_z: Where the plane sits on the camera's z axis.
        keep_nearer: True to keep what is nearer the camera than the plane
            (the far plane), False to keep what is further (the near plane).

    Returns:
        The surviving corners, in order.
    """
    var kept = List[ClipVertex]()
    for position in range(len(polygon)):
        var current = polygon[position]
        var following = polygon[(position + 1) % len(polygon)]
        var current_in = _inside(current.position.z, plane_z, keep_nearer)
        var following_in = _inside(following.position.z, plane_z, keep_nearer)
        if current_in:
            kept.append(current)
        if current_in != following_in:
            kept.append(_cross_at(current, following, plane_z))
    return kept^


def clip_depth(
    a: ClipVertex, b: ClipVertex, c: ClipVertex, near: Float32, far: Float32
) raises -> List[ClipVertex]:
    """Return the part of a triangle inside the camera's depth range.

    Args:
        a: First corner, in camera space.
        b: Second corner.
        c: Third corner.
        near: Distance to the near plane; the plane sits at z = -near.
        far: Distance to the far plane, at z = -far.

    Returns:
        Corners three at a time: empty if nothing survives, otherwise three
        per triangle of the fan the clipped polygon was cut into.

    Raises:
        Error: If `far` does not lie beyond `near`, which would leave the
            frustum inside out.

            A `near` of zero or less is fine here. This clipper's job is to
            cut against two finite, ordered planes in camera space, and it
            does that as happily behind the camera as anywhere else -- an
            orthographic camera is entitled to a near plane there and
            three.js allows one. Forbidding it was a perspective rule in the
            wrong place: what cannot survive z = 0 is the *divide*, and that
            prohibition lives in `math.projection.perspective` and
            `PerspectiveCamera`, which both still refuse it.
    """
    if far <= near:
        raise Error("The far plane must be beyond the near plane")

    var corners = List[ClipVertex]()
    corners.append(a)
    corners.append(b)
    corners.append(c)

    # Near first, so the far pass usually gets an empty or already-small
    # polygon. Order does not change the result, only the work.
    var in_front = _clip_plane(corners, -near, True)
    var within = _clip_plane(in_front, -far, False)

    # Three to five corners, fanned from the first into triangles. An empty
    # or degenerate polygon gives an empty range and so no triangles.
    var triangles = List[ClipVertex]()
    for corner in range(1, len(within) - 1):
        triangles.append(within[0])
        triangles.append(within[corner])
        triangles.append(within[corner + 1])
    return triangles^


def clip_segment(
    a: ClipVertex, b: ClipVertex, near: Float32, far: Float32
) raises -> List[ClipVertex]:
    """Return the part of a segment inside the camera's depth range.

    The line counterpart of `clip_depth`, and it exists for the same
    reason: a point behind the camera does not project to a slightly wrong
    point, it projects through the origin to the far side of the image. A
    segment is simpler than a triangle, because cutting a segment against
    a plane leaves a segment or nothing at all -- there is no polygon to
    fan.

    Both ends are moved by the same arithmetic the triangle clipper uses,
    `_cross_at`, so a mesh edge and a line lying on it are cut at the same
    place.

    Args:
        a: One end, in camera space.
        b: The other end.
        near: Distance to the near plane; the plane sits at z = -near.
        far: Distance to the far plane, at z = -far.

    Returns:
        Two corners, or none if the segment lies wholly outside the range.

    Raises:
        Error: If `far` does not lie beyond `near`, which would leave the
            frustum inside out; see `clip_depth` on a near plane behind
            the camera.
    """
    if far <= near:
        raise Error("The far plane must be beyond the near plane")

    var first = a
    var second = b
    # Near, then far, as `clip_depth` does them. Each pass either leaves
    # the segment alone, moves one end onto the plane, or throws it away.
    var planes: List[Float32] = [-near, -far]
    var keep_nearer: List[Bool] = [True, False]
    for pass_index in range(2):  # pragma: no branch
        var plane_z = planes[pass_index]
        var nearer = keep_nearer[pass_index]
        var first_in = _inside(first.position.z, plane_z, nearer)
        var second_in = _inside(second.position.z, plane_z, nearer)
        if not first_in and not second_in:
            return List[ClipVertex]()
        if not first_in:
            first = _cross_at(first, second, plane_z)
        elif not second_in:
            second = _cross_at(second, first, plane_z)
    var kept = List[ClipVertex]()
    kept.append(first)
    kept.append(second)
    return kept^
