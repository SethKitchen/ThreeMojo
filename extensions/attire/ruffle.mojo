# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Ruffles: fluted frills along a garment's cuffs, collar and hem.

A frill is a strip of cloth gathered along one edge. `ruffle_mesh` grows
one from each open edge of a garment that the garment's `Ruffles` name
and that shows:

| Place | Where | Grows | Width | Flutes |
|---|---|---|---|---|
| `CUFF_RUFFLES` | the end of a sleeve | down the arm, over the hand | 4.5 cm | 2.6 cm apart, 8 mm deep |
| `COLLAR_RUFFLE` | the neckline | out and down, over the shoulders and the chest | 5 cm | 3 cm apart, 1 cm deep |
| `HEM_RUFFLE` | the hem below the hips | down from the hem | 7 cm | 4.5 cm apart, 1.4 cm deep |

An open edge is a cuff when the arm weighs most on its vertices and it
runs across the bone. It is a collar above the waist joint, close to the
neck, and a hem below the hip joints and low on the garment, when it
lies about level. The
frill flares as it grows, and its flutes deepen from none at the seam to
their whole depth at its edge. Each loop holds a whole number of flutes,
so a cuff closes on itself.

The frill is two sheets back to back, one facing each way, so it draws
from both sides. Each vertex takes the skin weights of the edge it grows
from. Its `cover` value is `RUFFLE_COVER`, below the trim's level, so the
frill takes the trim's dye. `dress` merges it into the garment before
the garment is dyed.

This is not a three.js port. See Extensions.

    var frill = ruffle_mesh(piece, whole, rig, CUFF_RUFFLES | COLLAR_RUFFLE)
    piece = merge(piece, frill)
"""

from std.collections import Set
from std.math import atan2, ceil, pi, sin

from core.buffer_geometry import POSITION, BufferGeometry
from extensions.attire.kinds import (
    COLLAR_RUFFLE,
    CUFF_RUFFLES,
    HEM_RUFFLE,
    NO_RUFFLES,
    Ruffles,
    require_ruffles,
)
from extensions.attire.mesh_ops import MeshWriter, weld_groups
from extensions.attire.springs import nearest_on_segment
from extensions.attire.surface import BoneFrame
from extensions.humanoid.rig.joints import (
    HIPS,
    LEFT_FOREARM,
    LEFT_HAND,
    LEFT_UPPER_ARM,
    NECK,
    RIGHT_FOREARM,
    RIGHT_HAND,
    RIGHT_UPPER_ARM,
    SPINE,
    HumanoidRig,
)
from math.vector3 import Vector3
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT

comptime RUFFLE_COVER = Float32(0.3)
"""The cover value of a frill: below the trim's level."""
comptime RUFFLE_ROWS = 3
"""How many rows of vertices run along a frill, its seam the first."""
comptime RUFFLE_STEPS = Float32(6)
"""How many columns of vertices each flute spans at the least."""
comptime RUFFLE_LEVEL = Float32(0.6)
"""The most an edge of a collar or a hem climbs for each meter of its
length; a cuff's edge leans this far along its bone at the most."""
comptime RUFFLE_NECK = Float32(0.8)
"""How far from the neck's axis a collar lies at the most, as a share of
half the width of the shoulders."""
comptime RUFFLE_HEM = Float32(0.35)
"""How far up a garment, from its lowest point to its highest, a hem lies
at the most."""
comptime LEAST_FLUTES = 6
"""The fewest flutes round a loop."""


struct RuffleShape(ImplicitlyCopyable):
    """How a frill of one place is cut."""

    var width: Float32
    """How far it grows from its seam, in meters."""
    var flare: Float32
    """How far it stands out at its edge, as a share of its width."""
    var flute: Float32
    """How deep its flutes stand at its edge, in meters."""
    var wave: Float32
    """How far apart its flutes lie, in meters."""

    def __init__(
        out self, width: Float32, flare: Float32, flute: Float32, wave: Float32
    ):
        """Describe a frill.

        Args:
            width: How far it grows, in meters.
            flare: How far it stands out, as a share of its width.
            flute: How deep its flutes are, in meters.
            wave: How far apart its flutes lie, in meters.
        """
        self.width = width
        self.flare = flare
        self.flute = flute
        self.wave = wave


def ruffle_shape(place: Ruffles) raises -> RuffleShape:
    """Return how the frill of one place is cut.

    Args:
        place: `CUFF_RUFFLES`, `COLLAR_RUFFLE` or `HEM_RUFFLE`.

    Returns:
        Its shape, as the table in the module says.

    Raises:
        Error: If `place` is not one place.
    """
    if place == CUFF_RUFFLES:
        return RuffleShape(0.045, 0.5, 0.008, 0.026)
    if place == COLLAR_RUFFLE:
        return RuffleShape(0.05, 0.4, 0.01, 0.03)
    if place == HEM_RUFFLE:
        return RuffleShape(0.07, 0.3, 0.014, 0.045)
    raise Error("A frill grows at one place: the cuffs, the collar or the hem")


def _is_arm(bone: Int) -> Bool:
    """Return whether a bone is of an arm."""
    return (
        bone == RIGHT_UPPER_ARM.value
        or bone == RIGHT_FOREARM.value
        or bone == RIGHT_HAND.value
        or bone == LEFT_UPPER_ARM.value
        or bone == LEFT_FOREARM.value
        or bone == LEFT_HAND.value
    )


def ruffle_place(
    rig: HumanoidRig, a: Vector3, b: Vector3, bone: Int, hem: Float32
) -> Ruffles:
    """Return which place an open edge of a garment is.

    Args:
        rig: The rig the garment was made on.
        a: One end of the edge.
        b: The other end.
        bone: The bone that weighs most on the edge.
        hem: The height a hem lies below: `RUFFLE_HEM` of the way up the
            garment. A skirt's top, tucked inside the garment over it,
            lies above it.

    Returns:
        `CUFF_RUFFLES`, `COLLAR_RUFFLE`, `HEM_RUFFLE`, or `NO_RUFFLES`
        for an edge that is none of them, such as the front of a coat.
    """
    var edge = b - a
    var length = edge.length()
    if length <= 0:
        return NO_RUFFLES
    if _is_arm(bone):
        var frame = BoneFrame(rig, bone)
        if abs(edge.dot(frame.axis)) <= RUFFLE_LEVEL * length:
            return CUFF_RUFFLES
        return NO_RUFFLES
    if abs(edge.y) > RUFFLE_LEVEL * length:
        return NO_RUFFLES
    var middle = (a + b) * 0.5
    if middle.y < rig.joints[HIPS.value].y:
        return HEM_RUFFLE if middle.y < hem else NO_RUFFLES
    var neck = rig.joints[NECK.value]
    var shoulders = (
        rig.joints[RIGHT_UPPER_ARM.value] - rig.joints[LEFT_UPPER_ARM.value]
    ).length()
    var reach = Vector3(middle.x - neck.x, 0, middle.z - neck.z).length()
    if (
        middle.y > rig.joints[SPINE.value].y
        and reach < RUFFLE_NECK * shoulders / 2
    ):
        return COLLAR_RUFFLE
    return NO_RUFFLES


def _point(p: Vector3) -> String:
    """Return one key for a position."""
    return String(repr(p.x), " ", repr(p.y), " ", repr(p.z))


def _open_edges(geometry: BufferGeometry) raises -> List[Int]:
    """Return each open edge of a mesh as two vertices, in the order its
    triangle winds them. Copies of a vertex at one position are one
    vertex."""
    var groups = weld_groups(geometry)
    var count = geometry.vertex_count()
    var holders = Dict[Int, Int]()
    for t in range(geometry.triangle_count()):  # pragma: no branch
        for c in range(3):  # pragma: no branch
            var a = groups[geometry.corner_index(t, c)]
            var b = groups[geometry.corner_index(t, (c + 1) % 3)]
            var key = min(a, b) * count + max(a, b)
            holders[key] = holders.get(key, 0) + 1
    var edges = List[Int]()
    for t in range(geometry.triangle_count()):  # pragma: no branch
        for c in range(3):  # pragma: no branch
            var a = geometry.corner_index(t, c)
            var b = geometry.corner_index(t, (c + 1) % 3)
            var ga = groups[a]
            var gb = groups[b]
            if holders[min(ga, gb) * count + max(ga, gb)] == 1:
                edges.append(a)
                edges.append(b)
    return edges^


def _heaviest(bones: List[Float32], weights: List[Float32], v: Int) -> Int:
    """Return the bone that weighs most on a vertex."""
    var best = 0
    for c in range(1, 4):  # pragma: no branch
        if weights[4 * v + c] > weights[4 * v + best]:
            best = c
    return Int(bones[4 * v + best])


struct _Frame(ImplicitlyCopyable):
    """Where a point of a frill's seam lies round its loop's axis."""

    var radial: Vector3
    """Out from the axis, a unit vector."""
    var along: Vector3
    """The way the frill grows, a unit vector."""
    var turn: Float32
    """The angle round the axis, in radians."""
    var radius: Float32
    """The distance from the axis, in meters."""

    def __init__(
        out self,
        radial: Vector3,
        along: Vector3,
        turn: Float32,
        radius: Float32,
    ):
        self.radial = radial
        self.along = along
        self.turn = turn
        self.radius = radius


def _frame(rig: HumanoidRig, place: Ruffles, bone: Int, p: Vector3) -> _Frame:
    """Return where a seam point lies round the axis of its loop."""
    if place == CUFF_RUFFLES:
        var bones = BoneFrame(rig, bone)
        var center = nearest_on_segment(p, rig.joints[bone], rig.ends[bone])
        var radial = p - center
        var radius = radial.length()
        # A point on the axis has no way out: it stays where it is.
        radial.normalize()
        return _Frame(
            radial,
            bones.axis,
            atan2(radial.dot(bones.side), radial.dot(bones.forward)),
            radius,
        )
    var center = rig.joints[NECK.value]
    if place == HEM_RUFFLE:
        center = rig.joints[HIPS.value]
    var radial = Vector3(p.x - center.x, 0, p.z - center.z)
    var radius = radial.length()
    radial.normalize()
    var along = Vector3(0, -1, 0)
    if place == COLLAR_RUFFLE:
        along = Vector3(0, -0.66, 0) + radial * 0.75
        along.normalize()
    return _Frame(radial, along, atan2(radial.x, radial.z), radius)


def _loop(place: Ruffles, bone: Int) -> Int:
    """Return a key for the loop a seam point lies on: each sleeve's cuff
    apart, the collar, and the hem."""
    if place == CUFF_RUFFLES:
        return bone
    return -place.value


struct _Skin(Movable):
    """A vertex's four bones and their weights."""

    var bones: List[Int]
    """The bones."""
    var weights: List[Float32]
    """Their weights."""

    def __init__(out self, var bones: List[Int], var weights: List[Float32]):
        self.bones = bones^
        self.weights = weights^


def _skin(bones: List[Float32], weights: List[Float32], v: Int) -> _Skin:
    """Return the four bones and weights of a vertex."""
    var four = List[Int](capacity=4)
    var share = List[Float32](capacity=4)
    for c in range(4):  # pragma: no branch
        four.append(Int(bones[4 * v + c]))
        share.append(weights[4 * v + c])
    return _Skin(four^, share^)


struct _Frill(Movable):
    """A frill written column by column: each column's rows on the front
    sheet, and again on the back sheet."""

    var writer: MeshWriter
    """The mesh written."""
    var front: List[Int]
    """The vertices of the front sheet, `RUFFLE_ROWS` a column."""
    var back: List[Int]
    """The vertices of the back sheet, `RUFFLE_ROWS` a column."""

    def __init__(out self, var writer: MeshWriter):
        self.writer = writer^
        self.front = List[Int]()
        self.back = List[Int]()

    def column(
        mut self,
        rig: HumanoidRig,
        p: Vector3,
        skin: _Skin,
        place: Ruffles,
        bone: Int,
        flutes: Float32,
    ) raises -> Int:
        """Write the column that grows from a seam point, and return it."""
        var shape = ruffle_shape(place)
        var frame = _frame(rig, place, bone, p)
        var flute = frame.radial - frame.along * frame.radial.dot(frame.along)
        flute.normalize()
        var wave = sin(flutes * frame.turn)
        var at = len(self.front) // RUFFLE_ROWS
        for sheet in range(2):  # pragma: no branch
            for row in range(RUFFLE_ROWS):  # pragma: no branch
                var t = Float32(row) / Float32(RUFFLE_ROWS - 1)
                var q = (
                    p
                    + frame.along * (shape.width * t)
                    + flute
                    * (
                        shape.width * shape.flare * t * t
                        + shape.flute * wave * t
                    )
                )
                var v = self.writer.add(
                    q, RUFFLE_COVER, skin.bones, skin.weights
                )
                if sheet == 0:
                    self.front.append(v)
                else:
                    self.back.append(v)
        return at

    def join(mut self, first: Int, second: Int):
        """Join two columns with a strip on each sheet, the back's
        triangles wound the other way."""
        var c0 = first * RUFFLE_ROWS
        var c1 = second * RUFFLE_ROWS
        for r in range(RUFFLE_ROWS - 1):  # pragma: no branch
            self.writer.triangle(
                self.front[c0 + r], self.front[c0 + r + 1], self.front[c1 + r]
            )
            self.writer.triangle(
                self.front[c1 + r],
                self.front[c0 + r + 1],
                self.front[c1 + r + 1],
            )
            self.writer.triangle(
                self.back[c0 + r], self.back[c1 + r], self.back[c0 + r + 1]
            )
            self.writer.triangle(
                self.back[c1 + r],
                self.back[c1 + r + 1],
                self.back[c0 + r + 1],
            )


def ruffle_mesh(
    piece: BufferGeometry,
    whole: BufferGeometry,
    rig: HumanoidRig,
    ruffles: Ruffles,
) raises -> BufferGeometry:
    """Return the frills of a garment, to merge into it.

    A frill grows from each open edge of `whole` at a place `ruffles`
    names, when `piece` shows both of its ends. So an edge that a garment
    over it hides grows no frill. A lined skirt's hem is closed in
    `piece`, but it is open in `whole`, so it grows a flounce.

    Args:
        piece: The garment's shown part, with skin weights, in the pelvis
            frame.
        whole: The garment's whole shell, with nothing hidden.
        rig: The rig the garment was made on.
        ruffles: Where the garment wears frills.

    Returns:
        The frills, with the attributes of `piece`. A garment with no
        frills gives a mesh with no triangles.

    Raises:
        Error: If `ruffles` is not named, or a mesh has no positions or
            skin weights.
    """
    require_ruffles(ruffles)
    var writer = MeshWriter(piece)
    if ruffles == NO_RUFFLES:
        return writer.build()
    var shown = Set[String]()
    ref placed = piece.attribute_view(String(POSITION))
    for v in range(placed.count()):  # pragma: no branch
        shown.add(_point(placed.vector3(v)))
    ref whole_placed = whole.attribute_view(String(POSITION))
    var low = Float32.MAX
    var high = -Float32.MAX
    for v in range(whole_placed.count()):  # pragma: no branch
        low = min(low, whole_placed.vector3(v).y)
        high = max(high, whole_placed.vector3(v).y)
    var hem = low + RUFFLE_HEM * (high - low)
    var bones = whole.attribute_view(String(SKIN_INDEX)).packed()
    var weights = whole.attribute_view(String(SKIN_WEIGHT)).packed()
    # The edges that grow a frill, their places and bones, and the mean
    # radius of each loop.
    var chosen = List[Int]()
    var places = List[Ruffles]()
    var owners = List[Int]()
    var loops = Dict[Int, Float32]()
    var counts = Dict[Int, Int]()
    var edges = _open_edges(whole)
    for k in range(0, len(edges), 2):
        var a = edges[k]
        var b = edges[k + 1]
        var pa = whole_placed.vector3(a)
        var pb = whole_placed.vector3(b)
        if _point(pa) not in shown or _point(pb) not in shown:
            continue
        var bone = _heaviest(bones, weights, a)
        var place = ruffle_place(rig, pa, pb, bone, hem)
        if not ruffles.has(place):
            continue
        chosen.append(a)
        chosen.append(b)
        places.append(place)
        owners.append(bone)
        var loop = _loop(place, bone)
        loops[loop] = loops.get(loop, 0) + _frame(rig, place, bone, pa).radius
        counts[loop] = counts.get(loop, 0) + 1
    # The seam's own vertices are shared by the edges that meet there.
    var groups = weld_groups(whole)
    var columns = Dict[Int, Int]()
    var frill = _Frill(writer^)
    for e in range(len(places)):
        var a = chosen[2 * e]
        var b = chosen[2 * e + 1]
        var place = places[e]
        var bone = owners[e]
        var loop = _loop(place, bone)
        var shape = ruffle_shape(place)
        var mean = loops[loop] / Float32(counts[loop])
        var flutes = Float32(
            max(LEAST_FLUTES, Int(2 * Float32(pi) * mean / shape.wave + 0.5))
        )
        var pa = whole_placed.vector3(a)
        var pb = whole_placed.vector3(b)
        var steps = max(
            1,
            Int(
                ceil(
                    (pb - pa).length()
                    * RUFFLE_STEPS
                    * flutes
                    / max(2 * Float32(pi) * mean, Float32(1e-4))
                )
            ),
        )
        var row = List[Int]()
        for s in range(steps + 1):  # pragma: no branch
            if s == 0 or s == steps:
                var v = a if s == 0 else b
                var key = groups[v] * 8 + place.value
                if key not in columns:
                    columns[key] = frill.column(
                        rig,
                        whole_placed.vector3(v),
                        _skin(bones, weights, v),
                        place,
                        bone,
                        flutes,
                    )
                row.append(columns[key])
            else:
                var f = Float32(s) / Float32(steps)
                row.append(
                    frill.column(
                        rig,
                        pa + (pb - pa) * f,
                        _skin(bones, weights, a if f < 0.5 else b),
                        place,
                        bone,
                        flutes,
                    )
                )
        for s in range(steps):  # pragma: no branch
            frill.join(row[s], row[s + 1])
    return frill.writer.build()
