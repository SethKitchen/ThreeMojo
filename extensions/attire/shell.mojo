# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A garment's shell, made from the skin it covers.

A garment is the covered part of the skin, moved out along the skin's
normals. It shares the skin's vertices until it is cut, so:

- It follows any genome and stature. A new body gives a new skin, and
  the garment is made again from it.
- It takes the skin's weights as they are. It bends as the skin bends.
- It knows the layers under it vertex by vertex. Each layer stands off
  the outer face of every layer under it by its own clearance. No layer
  can pass through the one under it at rest.

The steps, for one skin and one garment:

1. `SkinFrame` reads the skin once: its positions, its normals, and the
   vertices that share one position.
2. `standoff` says how far out the garment's inner face must stand at
   each vertex: its clearance, past the outer face of each layer under
   it. A layer under it counts in full where it is cut, and fades out
   just past its hem, so a tunic rises smoothly over the top of a hose.
3. `shell_positions` moves each vertex out by its standoff, then drapes
   the shell: each pass moves a vertex halfway to the mean of its
   neighbors, and back out to its standoff if that took it too close.
   One pass keeps the skin's shape under a thin cloth. Many passes span
   the hollows, as a stiff plate does.
4. `garment_piece` drops what a layer over it hides, cuts the shell at
   its hems, and sets its normals.
5. `hide_under` drops the skin triangles a garment covers fully, so skin
   cannot show through a garment when the body moves.

This is not a three.js port. See Extensions.

    var frame = SkinFrame(skin)
    var values = cover_values(skin, rig, cover)
    var places = shell_positions(frame, offsets, values, fabric.drape)
    var piece = garment_piece(skin, places, values, hidden)
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, NORMAL, POSITION, BufferGeometry
from extensions.attire.cover import HEM_LEVEL
from extensions.attire.mesh_ops import (
    cut,
    keep_triangles,
    vertex_neighbors,
    weld_groups,
)
from extensions.humanoid.skeleton.head.skin.tint import THINNESS
from math.utils import clamp
from math.vector3 import Vector3

comptime HIDE_LEVEL = Float32(0.75)
"""A triangle whose vertices all have at least this cover value from a layer
over it is hidden. It lies well inside that layer's hem, so no gap opens
at the hem."""
comptime DRAPE_FLOOR = Float32(0.05)
"""A vertex is draped only where its garment's cover value is above this.
The bare skin round a garment holds still and anchors its hems."""
comptime COVER = "cover"
"""The name of the attribute that carries each vertex's cover value."""
comptime COVER_SMOOTHING = 3
"""Smoothing passes of the cover values before a garment is cut. A cover
value can step from one to zero across one edge where two joints' weights
meet; smoothed, its iso-line runs smoothly between vertices."""


struct SkinFrame(Movable):
    """A skin's positions, normals and welded neighbors, read once."""

    var points: List[Vector3]
    """The skin's positions."""
    var normals: List[Vector3]
    """The unit normal of each vertex, the same for every copy of it."""
    var groups: List[Int]
    """For each vertex, the first vertex at its position."""
    var neighbors: List[List[Int]]
    """The welded neighbors of each group's first vertex."""

    def __init__(out self, skin: BufferGeometry) raises:
        """Read a skin.

        Args:
            skin: A mesh with positions. Its own normals are used if it
                has them, and computed if it has none.

        Raises:
            Error: If the mesh has no positions or is malformed.
        """
        ref placed = skin.attribute_view(String(POSITION))
        self.points = List[Vector3](capacity=placed.count())
        for v in range(placed.count()):
            self.points.append(placed.vector3(v))
        self.groups = weld_groups(skin)
        self.neighbors = vertex_neighbors(skin, self.groups)
        var raw = List[Vector3](capacity=len(self.points))
        if skin.has_attribute(String(NORMAL)):
            ref given = skin.attribute_view(String(NORMAL))
            for v in range(given.count()):
                raw.append(given.vector3(v))
        else:
            var copy = skin.clone()
            copy.compute_vertex_normals()
            ref made = copy.attribute_view(String(NORMAL))
            for v in range(made.count()):
                raw.append(made.vector3(v))
        # Every copy of a vertex takes the mean normal of the copies, so
        # copies move out together and the shell does not tear.
        var sums = List[Vector3](length=len(self.points), fill=Vector3(0, 0, 0))
        for v in range(len(self.points)):
            sums[self.groups[v]] = sums[self.groups[v]] + raw[v]
        self.normals = List[Vector3](capacity=len(self.points))
        for v in range(len(self.points)):
            self.normals.append(_unit(sums[self.groups[v]]))

    def count(self) -> Int:
        """Return how many vertices the skin has.

        Returns:
            The vertex count.
        """
        return len(self.points)


def _unit(v: Vector3) -> Vector3:
    """Return `v` scaled to unit length, or straight up if it is zero."""
    var length = v.length()
    if length <= 0:
        return Vector3(0, 1, 0)
    return v * (1 / length)


def smooth_values(
    frame: SkinFrame, values: List[Float32], passes: Int
) raises -> List[Float32]:
    """Return per-vertex values smoothed over the skin's welded edges.

    Each pass moves a value halfway to the mean of its neighbors'. Every
    copy of a vertex takes one value.

    Args:
        frame: The skin, read once.
        values: One value per vertex.
        passes: Smoothing passes, zero or more.

    Returns:
        The smoothed values.

    Raises:
        Error: If `values` is not one per vertex.
    """
    var count = frame.count()
    if len(values) != count:
        raise Error("Smoothing needs one value per vertex")
    var now = List[Float32](length=count, fill=0)
    for v in range(count):
        var g = frame.groups[v]
        now[g] = max(now[g], values[v])
    for _ in range(passes):
        var next = now.copy()
        for v in range(count):
            ref around = frame.neighbors[v]
            if frame.groups[v] != v or len(around) == 0:
                continue
            var mean = Float32(0)
            for n in around:  # pragma: no branch
                mean += now[n]
            next[v] = 0.5 * now[v] + 0.5 * mean / Float32(len(around))
        now = next^
    var out = List[Float32](capacity=count)
    for v in range(count):
        out.append(now[frame.groups[v]])
    return out^


def under_share(value: Float32) -> Float32:
    """Return how fully a layer under a garment lifts it at a vertex.

    A layer under the garment lifts it in full where that layer is cut,
    at its hem, and inside it. The lift fades to nothing a quarter of a
    cover value past the hem, outside that layer.

    Args:
        value: The layer's cover value at the vertex.

    Returns:
        Zero through one.
    """
    return clamp(4 * value - 1, 0, 1)


def standoff(
    clearance: Float32,
    under_values: List[List[Float32]],
    under_faces: List[List[Float32]],
    vertex: Int,
) -> Float32:
    """Return how far out a garment's inner face stands at a vertex.

    Args:
        clearance: The garment's own gap, in meters.
        under_values: The cover values of each layer under it.
        under_faces: How far out each such layer's outer face stands, in
            meters, at each vertex.
        vertex: The vertex.

    Returns:
        The standoff, in meters: the clearance, past the highest outer
        face under it that lifts it.
    """
    var lift = Float32(0)
    for k in range(len(under_values)):
        lift = max(
            lift,
            under_share(under_values[k][vertex]) * under_faces[k][vertex],
        )
    return lift + clearance


def shell_positions(
    frame: SkinFrame,
    standoffs: List[Float32],
    values: List[Float32],
    drape: Int,
) raises -> List[Vector3]:
    """Return a garment's shell: each skin vertex moved out and draped.

    Args:
        frame: The skin, read once.
        standoffs: How far out each vertex must stand at least, meters.
        values: The garment's cover values. Only covered vertices drape.
        drape: Smoothing passes, zero or more.

    Returns:
        One position per skin vertex. Copies of a vertex share one.

    Raises:
        Error: If a list is not one entry per vertex, or `drape` is
            negative.
    """
    var count = frame.count()
    if len(standoffs) != count or len(values) != count:
        raise Error("A shell needs one standoff and one value per vertex")
    if drape < 0:
        raise Error("A drape must be zero or more passes")
    # Each group's first vertex carries the group: its greatest standoff
    # and its greatest cover value.
    var least = List[Float32](length=count, fill=0)
    var covered = List[Float32](length=count, fill=0)
    for v in range(count):
        var g = frame.groups[v]
        least[g] = max(least[g], standoffs[v])
        covered[g] = max(covered[g], values[v])
    var places = List[Vector3](capacity=count)
    for v in range(count):
        var g = frame.groups[v]
        places.append(frame.points[g] + frame.normals[g] * least[g])
    for _ in range(drape):
        var moved = places.copy()
        for v in range(count):
            if frame.groups[v] != v or covered[v] <= DRAPE_FLOOR:
                continue
            ref around = frame.neighbors[v]
            if len(around) == 0:
                continue
            var mean = Vector3(0, 0, 0)
            for n in around:  # pragma: no branch
                mean = mean + places[n]
            mean = mean * (1 / Float32(len(around)))
            var q = places[v] + (mean - places[v]) * 0.5
            # Keep the standoff: push back out along the normal.
            var out = (q - frame.points[v]).dot(frame.normals[v])
            if out < least[v]:
                q = q + frame.normals[v] * (least[v] - out)
            moved[v] = q
        places = moved^
    for v in range(count):
        places[v] = places[frame.groups[v]]
    return places^


def outer_faces(
    frame: SkinFrame, places: List[Vector3], thickness: Float32
) raises -> List[Float32]:
    """Return how far out a garment's outer face stands at each vertex.

    Args:
        frame: The skin, read once.
        places: The garment's shell, one position per skin vertex.
        thickness: The fabric's thickness, in meters.

    Returns:
        The distance along each normal from the skin to the shell, plus
        the thickness, in meters.

    Raises:
        Error: If `places` is not one position per vertex.
    """
    if len(places) != frame.count():
        raise Error("A shell needs one position per vertex")
    var faces = List[Float32](capacity=frame.count())
    for v in range(frame.count()):
        faces.append(
            (places[v] - frame.points[v]).dot(frame.normals[v]) + thickness
        )
    return faces^


def hidden_mask(
    geometry: BufferGeometry, over: List[Float32]
) raises -> List[Bool]:
    """Return, per triangle, whether a layer over it keeps it.

    Args:
        geometry: A mesh, indexed or not.
        over: Per vertex, the greatest cover value of any layer over it.

    Returns:
        One flag per triangle: False when every corner is at or above
        `HIDE_LEVEL`.

    Raises:
        Error: If `over` is not one value per vertex.
    """
    if len(over) != geometry.vertex_count():
        raise Error("Hiding needs one value per vertex")
    var keep = List[Bool](capacity=geometry.triangle_count())
    for t in range(geometry.triangle_count()):
        var hidden = True
        for c in range(3):  # pragma: no branch
            if over[geometry.corner_index(t, c)] < HIDE_LEVEL:
                hidden = False
        keep.append(not hidden)
    return keep^


def hide_under(mut geometry: BufferGeometry, over: List[Float32]) raises:
    """Drop the triangles a layer over a mesh covers fully.

    Args:
        geometry: A skin or a garment.
        over: Per vertex, the greatest cover value of any layer over it.

    Raises:
        Error: If `over` is not one value per vertex.
    """
    keep_triangles(geometry, hidden_mask(geometry, over))


def garment_piece(
    skin: BufferGeometry,
    places: List[Vector3],
    values: List[Float32],
    over: List[Float32],
) raises -> BufferGeometry:
    """Return the part of a shell a garment keeps.

    The piece takes the skin's attributes but its colors and thinness,
    which are the skin's own. It drops the triangles a layer over it
    hides, then is cut at its hems, where its cover value is one half.
    Each vertex keeps its cover value in a `cover` attribute.

    Args:
        skin: The skin the shell was made from.
        places: The shell, one position per skin vertex.
        values: The garment's cover values.
        over: Per vertex, the greatest cover value of any layer over it.

    Returns:
        An indexed mesh with recomputed normals. It has no triangles when
        the garment covers none of this skin.

    Raises:
        Error: If a list is not one entry per vertex.
    """
    var count = skin.vertex_count()
    if len(places) != count or len(values) != count:
        raise Error("A garment piece needs one place and one value a vertex")
    var shell = skin.clone()
    var flat = List[Float32](capacity=3 * count)
    for p in places:
        flat.append(p.x)
        flat.append(p.y)
        flat.append(p.z)
    shell.set_attribute(String(POSITION), BufferAttribute(flat^, 3))
    shell.delete_attribute(String(COLOR))
    shell.delete_attribute(String(THINNESS))
    shell.set_attribute(String(COVER), BufferAttribute(values.copy(), 1))
    var keep = hidden_mask(shell, over)
    var shown = False
    for flag in keep:
        if flag:
            shown = True
    if not shown:
        # Every triangle is hidden: cut at a level no value reaches.
        return cut(shell, List[Float32](length=count, fill=0), HEM_LEVEL)
    keep_triangles(shell, keep)
    var piece = cut(shell, values, HEM_LEVEL)
    if piece.triangle_count() > 0:
        piece.compute_vertex_normals()
    return piece^
