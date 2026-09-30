# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A scanned head fitted to the modeled anatomy.

The face of a sculpt is built from even solids, and reads as a doll's.
The face model's mean head is learned from scans of real faces (see
`face_model`). `ScannedHead` places it on the template: the scan's eyes
land on the template's, and each vertex then goes through the head's
frame as an authored point does. So the genome's face and head genes
move the scan as they move the skull under it.

The ears are skin and cartilage alone, so the frame does not move them.
The ear genes warp the scan's ears here: each ear grows about its root,
stands out from the head, and its lobe hangs lower.

The scan's skin is open at the mouth, at each eye and at the base of the
neck. The mouth and the eyes lead into the scan's mouth and eye sockets,
but the modeled anatomy fills those spaces: the palate, the teeth and
the orbits. So `ScannedHead` closes the mouth and the eyes with a fan of
triangles each, and keeps the closed skin as a `MeshField`, cut off above
the opening at the neck. The sockets are drawn, not solid.

This is not a three.js port. See Extensions.

    var scan = ScannedHead(dims.head, scan_model(), HeadHull(dims.head))
    var d = scan.distance(point)
"""

from core.buffer_geometry import BufferGeometry
from extensions.humanoid.genome import EAR_LOBE, EAR_PROTRUSION, EAR_SIZE
from extensions.humanoid.skeleton.field import (
    Bounds,
    DistanceField,
    cross,
    empty_bounds,
    smax,
)
from extensions.humanoid.skeleton.head.face_model import (
    EYE_SOCKETS,
    FACE_AND_HEAD,
    FACE_MODEL_PATH,
    FaceModel,
    FacePart,
    MOUTH_SOCKET,
)
from extensions.humanoid.skeleton.head.frame import HeadDimensions
from extensions.humanoid.skeleton.mesh_field import MeshField
from extensions.humanoid.skeleton.morph import bump, smoothstep
from extensions.humanoid.skeleton.sculpt import box_gap
from extensions.humanoid.skeleton.surface_nets import (
    finish_surface,
    project_to_surface,
)
from math.vector3 import Vector3
from std.math import cos, max, min, sin

# Where the scan's frame lands on the template, in template cm: the
# scan's eyeballs' centers on the template's.
comptime SCAN_Y = Float32(68.48421)
comptime SCAN_Z = Float32(-1.04114)
# Below this height, in template cm, the scan's neck is left to the
# modeled one: the scan is cut off above its open edge.
comptime SCAN_FLOOR = Float32(55.0)
# Below this height, in template cm, the scan is also cut off beyond
# `SHOULDER_X` from the midline, where its shoulders flare out.
comptime SHOULDER_TOP = Float32(58.0)
comptime SHOULDER_X = Float32(7.2)
# The right ear, in template cm: the root in front of the canal it
# grows about, and the middle of the auricle.
comptime EAR_ROOT = Vector3(7.4, 71.3, -1.0)
comptime EAR_MIDDLE = Vector3(8.3, 71.2, -2.2)
# How far the ear reaches from its middle, and the width over which its
# root leaves the side of the head, in template cm.
comptime EAR_REACH = Float32(6.5)
comptime EAR_ROOT_IN = Float32(6.8)
comptime EAR_ROOT_OUT = Float32(7.6)
# Where the neck's modeled skin hands over to the scan's mesh, in
# template cm: below the chin, where the skin is upright.
comptime NECK_SEAM = Float32(56.5)
# A vertex of the drawn skin nearer the field's surface than this, in
# meters, stays where the scan has it: the field is measured on the
# skin's coarse copy, which lies this near the skin.
comptime SNAP = Float32(1e-3)
# How near the surface a walked vertex must come, in meters.
comptime ON_SURFACE = Float32(1e-5)
# How many passes of Newton steps walk a vertex onto the surface.
comptime WALKS = 4
# How wide the smooth union of the scan and the modeled solids is, in
# template cm; and how far outside the solids the fitted scan lies, a
# little more, so the union is the scan wherever the scan was fitted.
# Then few vertices need walking onto the union's surface.
comptime SCAN_BLEND = Float32(0.2)
comptime FIT_MARGIN = Float32(0.25)
# How far inside the modeled neck the scan sinks at its floor, in
# template cm, so its cut there stays hidden.
comptime SINK = Float32(0.5)
# The height, in template cm, above which the scan lies outside the
# modeled neck; from the floor up to it, the scan rises out of the neck.
comptime SINK_TOP = Float32(58.0)
# How many passes fit the scan, and how many rounds in each spread the
# moves that fit it.
comptime FIT_PASSES = 3
comptime FIT_ROUNDS = 24


def scan_model() raises -> FaceModel:
    """Return as much of the face model as a scanned head needs: the
    mean head and its mesh, with no identity modes or expressions.

    Returns:
        The model.

    Raises:
        Error: If `FACE_MODEL_PATH` cannot be read.
    """
    return FaceModel(FACE_MODEL_PATH, 0, False)


def scan_to_template(point: Vector3) -> Vector3:
    """Return a point of the scan in template centimeters.

    Args:
        point: A point in the face model's frame, in meters.

    Returns:
        The point on the template, before the morph.
    """
    return Vector3(
        point.x * 100, point.y * 100 + SCAN_Y, point.z * 100 + SCAN_Z
    )


def ear_weight(point: Vector3) -> Float32:
    """Return how much of the ear a template point is: one on the
    auricle, zero on the head.

    Args:
        point: A point in template cm.

    Returns:
        The weight, zero through one.
    """
    var side = Vector3(abs(point.x), point.y, point.z)
    return smoothstep(EAR_ROOT_IN, EAR_ROOT_OUT, side.x) * bump(
        side, EAR_MIDDLE, EAR_REACH
    )


def warp_ear(
    point: Vector3, size: Float32, protrusion: Float32, lobe: Float32
) -> Vector3:
    """Return where the ear genes move one template point.

    Args:
        point: A point in template cm.
        size: The `EAR_SIZE` expression: the ear grows about its root.
        protrusion: The `EAR_PROTRUSION` expression: the ear's back
            edge stands out from the head.
        lobe: The `EAR_LOBE` expression: the lobe hangs lower.

    Returns:
        The moved point, in template cm.
    """
    var w = ear_weight(point)
    if w == 0:
        return point
    var side = Float32(1) if point.x >= 0 else Float32(-1)
    var q = Vector3(abs(point.x), point.y, point.z) - EAR_ROOT
    q = q * (1 + Float32(0.16) * size * w)
    var turn = Float32(0.2) * protrusion * w
    q = Vector3(
        q.x * cos(turn) - q.z * sin(turn),
        q.y,
        q.x * sin(turn) + q.z * cos(turn),
    )
    q.y -= Float32(0.35) * lobe * w * (1 - smoothstep(66.5, 68.5, point.y))
    var p = q + EAR_ROOT
    return Vector3(side * p.x, p.y, p.z)


def fit_over[
    F: DistanceField
](
    mut points: List[Vector3],
    triangles: List[Int],
    edges: List[Int],
    hull: F,
    end: Int,
    margin: Float32,
    sink_low: Float32,
    sink_high: Float32,
    sink: Float32,
):
    """Push a mesh's vertices out of a solid, as a sleeve is pulled over
    an arm.

    Each vertex inside `hull`, or nearer its surface than `margin`, needs
    to move out along the mesh's normal by that much. Moving each by
    its own need would fold the mesh where the solid's surface turns
    from the mesh's. So the moves are spread over the mesh: each vertex
    takes the mean of its neighbors' moves, and no less than its own
    need, again and again. The moves grow smooth, and the mesh stretches
    over the solid without folding. A vertex with no need is moved only
    as its neighbors pull it.

    Args:
        points: The vertices, in meters. They are moved.
        triangles: Three vertex indices a triangle, wound counter-
            clockwise seen from outside.
        edges: Two vertex indices an edge of the mesh, each edge once.
        hull: The solid to cover.
        end: Only the vertices before `end` move.
        margin: How far outside the solid each vertex must lie, in
            meters.
        sink_low: The height where each vertex must lie `sink` inside
            the solid instead, in meters. The mesh is cut off there, and
            its cut stays hidden inside the solid. Below it the vertices
            follow their neighbors.
        sink_high: The height above which each vertex lies `margin`
            outside. Between the two, a vertex must lie exactly where
            the two blend.
        sink: How far inside the solid a vertex at `sink_low` lies.
    """
    # The edges between two vertices that move.
    var pairs = List[Int]()
    var counts = List[Int](length=end, fill=0)
    for e in range(0, len(edges), 2):  # pragma: no branch
        var a = edges[e]
        var b = edges[e + 1]
        if a < end and b < end:
            pairs.append(a)
            pairs.append(b)
            counts[a] += 1
            counts[b] += 1
    # Where the solid's surface turns from the mesh's, one push along the
    # normal falls short: each pass measures again and pushes again.
    for _ in range(FIT_PASSES):  # pragma: no branch
        var directions = List[Vector3](length=end, fill=Vector3(0, 0, 0))
        for t in range(0, len(triangles), 3):  # pragma: no branch
            var a = points[triangles[t]]
            var n = cross(
                points[triangles[t + 1]] - a, points[triangles[t + 2]] - a
            )
            for c in range(3):  # pragma: no branch
                var v = triangles[t + c]
                if v < end:
                    directions[v] = directions[v] + n
        # How far each vertex must move along its normal: at least
        # `needs`, and no more than `limits`.
        var needs = List[Float32](length=end, fill=0)
        var limits = List[Float32](length=end, fill=3.0e38)
        var short = False
        for v in range(end):  # pragma: no branch
            var up = smoothstep(sink_low, sink_high, points[v].y)
            var goal = margin * up - sink * (1 - up)
            var need = goal - hull.distance(points[v])
            directions[v].normalize()
            # A vertex off its goal by more than the margin needs another
            # pass: in the band, either way; above it, inside the solid.
            # Below the band the mesh is cut off, so it follows its
            # neighbors freely.
            if points[v].y < sink_low:
                continue
            if up < 1:
                needs[v] = need
                limits[v] = need
                if abs(need) > margin:
                    short = True
            elif need > 0:
                needs[v] = need
                if need > margin:
                    short = True
        if not short:
            break
        var moves = List[Vector3](length=end, fill=Vector3(0, 0, 0))
        for v in range(end):  # pragma: no branch
            moves[v] = directions[v] * needs[v]
        var sums = List[Vector3](length=end, fill=Vector3(0, 0, 0))
        for _ in range(FIT_ROUNDS):  # pragma: no branch
            for v in range(end):  # pragma: no branch
                sums[v] = Vector3(0, 0, 0)
            for e in range(0, len(pairs), 2):  # pragma: no branch
                var a = pairs[e]
                var b = pairs[e + 1]
                sums[a] = sums[a] + moves[b]
                sums[b] = sums[b] + moves[a]
            for v in range(end):  # pragma: no branch
                var move = moves[v]
                if counts[v] > 0:
                    move = sums[v] / Float32(counts[v])
                var along = move.dot(directions[v])
                if along < needs[v]:
                    move = move + directions[v] * (needs[v] - along)
                elif along > limits[v]:
                    move = move - directions[v] * (along - limits[v])
                moves[v] = move
        for v in range(end):  # pragma: no branch
            points[v] = points[v] + moves[v]


def cap_hole(
    mut points: List[Vector3],
    mut triangles: List[Int],
    loop: List[Int],
    floor: Float32,
):
    """Close one hole of a mesh with a fan of triangles, if its middle
    lies above `floor`.

    The fan's hub is a new vertex at the hole's middle. Each edge of the
    hole gets a triangle to the hub, wound so the fan faces the way the
    mesh does.

    Args:
        points: The vertices. The hub is added.
        triangles: Three vertex indices a triangle. The fan is added.
        loop: The hole's vertices, in the order the mesh's triangles run
            its edges.
        floor: The height the hole's middle must lie above, in meters.
    """
    var middle = Vector3(0, 0, 0)
    for corner in loop:  # pragma: no branch
        middle = middle + points[corner]
    middle = middle / Float32(len(loop))
    if middle.y <= floor:
        return
    var hub = len(points)
    points.append(middle)
    for k in range(len(loop)):  # pragma: no branch
        triangles.append(loop[(k + 1) % len(loop)])
        triangles.append(loop[k])
        triangles.append(hub)


def skin_triangles(model: FaceModel) raises -> List[Int]:
    """Return the triangles of the scan's drawn skin, three vertex
    indices each: the face and the head, the inside of the mouth and the
    eye sockets.

    Args:
        model: The face model.

    Returns:
        Indices into the model's vertices.

    Raises:
        Error: Never, for the model's own parts.
    """
    var parts: List[FacePart] = [FACE_AND_HEAD, MOUTH_SOCKET, EYE_SOCKETS]
    return model.triangles_of(parts)


struct ScannedHead(Copyable, Movable):
    """The face model's head placed on one person's template."""

    # The closed skin as a field, over every vertex of the model in the
    # pelvis frame; and the height it is cut off at.
    var mesh: MeshField
    var floor: Float32
    var soft: Float32
    # The scan's shoulders flare out above its floor: below `shoulder_top`
    # it is also cut off beyond `shoulder_x` from the midline.
    var shoulder_x: Float32
    var shoulder_top: Float32
    # The box round both ears.
    var ears: Bounds
    var low: Vector3
    var high: Vector3

    def __init__[
        F: DistanceField
    ](out self, h: HeadDimensions, model: FaceModel, hull: F) raises:
        """Fit the model's mean head to `h`, over `hull`.

        Args:
            h: Head landmarks, with the genome.
            model: The face model.
            hull: The modeled solids the skin must cover. The scan is
                pushed out of them; see `fit_over`.

        Raises:
            Error: If the model's shape or its mesh is refused.
        """
        var genome = h.torso.genome
        var size = genome.get(EAR_SIZE)
        var protrusion = genome.get(EAR_PROTRUSION)
        var lobe = genome.get(EAR_LOBE)
        var shape = model.shape(model.no_identity(), model.no_expression())
        var points = List[Vector3](capacity=len(shape))
        var ear = List[Bool](capacity=len(shape))
        for index in range(len(shape)):  # pragma: no branch
            var t = warp_ear(
                scan_to_template(shape[index]), size, protrusion, lobe
            )
            points.append(h.at(t.x, t.y, t.z))
            ear.append(index < FACE_AND_HEAD.end and ear_weight(t) > 0.5)
        self.floor = h.at(0, SCAN_FLOOR, 0).y
        self.soft = h.cm(1.0)
        self.shoulder_x = h.at(SHOULDER_X, SHOULDER_TOP, 0).x
        self.shoulder_top = h.at(0, SHOULDER_TOP, 0).y
        fit_over(
            points,
            model.skin_triangles,
            model.skin_edges,
            hull,
            FACE_AND_HEAD.end,
            h.cm(FIT_MARGIN),
            self.floor,
            h.at(0, SINK_TOP, 0).y,
            h.cm(SINK),
        )
        self.ears = empty_bounds()
        for index in range(len(ear)):  # pragma: no branch
            if ear[index]:
                self.ears.include_sphere(points[index], 0)
        # The field searches the skin's coarse copy: it lies within a
        # fraction of a millimeter of the skin, and is faster to search.
        var triangles = model.coarse_triangles.copy()
        for index in range(model.holes()):  # pragma: no branch
            cap_hole(points, triangles, model.hole(index), self.floor)
        self.mesh = MeshField(points^, triangles^)
        self.low = Vector3(self.mesh.box_low.x, self.floor, self.mesh.box_low.z)
        self.high = self.mesh.box_high

    def bound(self, point: Vector3) -> Float32:
        """Return a distance the scan's skin is no nearer than, in
        meters: how far `point` lies below the floor or off the mesh's
        box. It costs little, and where it is large the mesh need not be
        searched.

        Args:
            point: A point in the pelvis frame, in meters.

        Returns:
            The bound, zero inside the box and above the floor.
        """
        return max(
            self.floor - point.y,
            box_gap(self.mesh.box_low, self.mesh.box_high, point),
        )

    def distance(self, point: Vector3) -> Float32:
        """Return the signed distance to the scan's skin, in meters,
        negative inside. Below the floor every point is outside, and low
        on the neck every point off to the side.

        Args:
            point: A point in the pelvis frame, in meters.

        Returns:
            The distance.
        """
        var d = smax(self.mesh.distance(point), self.floor - point.y, self.soft)
        var shoulder = max(
            self.shoulder_x - abs(point.x), point.y - self.shoulder_top
        )
        return smax(d, -shoulder, self.soft)


def scan_skin_mesh[
    F: DistanceField
](
    field: F,
    scan: ScannedHead,
    model: FaceModel,
    floor: Float32,
    low: Vector3,
    high: Vector3,
    step: Float32,
) raises -> BufferGeometry:
    """Return the scan's skin as a mesh on the surface of `field`.

    `field` is a skin the scan joins: the head's, or the whole body's.
    Where the field and the scan agree, a vertex stays where the scan
    has it. Where the field's other solids stand out of the scan, over
    the vault and the back of the neck, the vertex is walked out onto
    the field's surface. So the mesh meets any other mesh of the same
    field with no step.

    Args:
        field: The skin's field.
        scan: The scan, fitted to the same person.
        model: The face model the scan was fitted from.
        floor: The height below which triangles are left out, in
            meters. A triangle is kept only if all its corners are above
            it, so the mesh that meets this one must reach a little
            higher.
        low: The field's box's minimum corner, in meters.
        high: Its maximum corner.
        step: The gradient's sample distance, in meters.

    Returns:
        A geometry with `position`, `normal` and `uv`; `v` runs over the
        box's height.

    Raises:
        Error: If no triangle lies above `floor`.
    """
    var triangles = skin_triangles(model)
    var count = scan.mesh.count()
    # Each vertex's place on the field's surface, once it is needed: zero
    # not yet placed, one placed, two lost. A vertex the walk cannot
    # bring onto the surface is off the field's solids, as the scan's
    # shoulders are, and its triangles are left out.
    var state = List[Int](length=count, fill=0)
    var placed = List[Vector3](length=count, fill=Vector3(0, 0, 0))
    var remap = List[Int](length=count, fill=-1)
    var positions = List[Float32]()
    var points = List[Vector3]()
    var indices = List[Int]()
    for t in range(0, len(triangles), 3):  # pragma: no branch
        if not _above(scan.mesh, triangles, t, floor):
            continue
        var lost = False
        for c in range(3):  # pragma: no branch
            var v = triangles[t + c]
            if state[v] == 0:
                state[v] = 1
                var p = scan.mesh.point(v)
                # The sockets lie inside the closed skin; only the skin
                # itself is walked onto the field's surface.
                if v < FACE_AND_HEAD.end and abs(field.distance(p)) > SNAP:
                    p = _walk(field, p, low, high, step)
                    if abs(field.distance(p)) > SNAP:
                        state[v] = 2
                placed[v] = p
            if state[v] == 2:
                lost = True
        if lost:
            continue
        for c in range(3):  # pragma: no branch
            var v = triangles[t + c]
            if remap[v] < 0:
                remap[v] = len(points)
                var p = placed[v]
                points.append(p)
                positions.append(p.x)
                positions.append(p.y)
                positions.append(p.z)
            indices.append(remap[v])
    if len(indices) == 0:
        raise Error("No part of the scanned head lies above the floor")
    var sums = List[Vector3](length=len(points), fill=Vector3(0, 0, 0))
    for t in range(0, len(indices), 3):  # pragma: no branch
        var a = points[indices[t]]
        var n = cross(points[indices[t + 1]] - a, points[indices[t + 2]] - a)
        for c in range(3):  # pragma: no branch
            sums[indices[t + c]] = sums[indices[t + c]] + n
    var normals = List[Float32](capacity=len(positions))
    for v in range(len(sums)):  # pragma: no branch
        var n = sums[v]
        n.normalize()
        normals.append(n.x)
        normals.append(n.y)
        normals.append(n.z)
    return finish_surface(positions^, normals^, indices^, low.y, high.y - low.y)


def _walk[
    F: DistanceField
](
    field: F, start: Vector3, low: Vector3, high: Vector3, step: Float32
) -> Vector3:
    """Walk a point onto the field's surface, however far off it lies.

    Each pass is a few Newton steps; a point the modeled solids stand
    well out of needs several.
    """
    var p = start
    for _ in range(WALKS):  # pragma: no branch
        p = project_to_surface(field, p, low, high, step)
        if abs(field.distance(p)) <= ON_SURFACE:
            break
    return p


def _above(
    mesh: MeshField, triangles: List[Int], t: Int, floor: Float32
) -> Bool:
    """Return True if every corner of triangle `t` lies above `floor`."""
    var bottom = min(
        mesh.point(triangles[t]).y,
        min(mesh.point(triangles[t + 1]).y, mesh.point(triangles[t + 2]).y),
    )
    return bottom >= floor
