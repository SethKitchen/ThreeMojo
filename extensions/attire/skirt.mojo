# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A skirt: the part of a garment below the hips, hung as one tube round
both legs.

A garment made from the skin follows each thigh, as hose do. The skirt of
a tunic, a hauberk or a surcoat does not. It hangs from the hips round
both legs at once, and it widens as it falls. `hang_skirt` replaces the
part of a garment's shell below the hips with such a tube:

1. `skirt_top` is the height the skirt hangs from: a little below the
   hip joints, above the crotch, where the shell is one tube round the
   pelvis. The shell is cut there.
2. `skirt_envelope` slices the garment's own shell at rings from the top
   down to its lowest point on the legs, the hem. Each slice is closed as
   a convex hull, so it spans the gap between the thighs. Each ring is at
   least as wide as the ring above it, plus the flare, so the cloth falls
   and does not tuck in between the legs. A skirt under it lifts it.
3. `skirt_mesh` lofts the rings into a tube on `SKIRT_SIDES` sides. The
   top of the tube reaches up inside the shell, so no gap opens at the
   cut. A lined skirt has an inner face one fabric thickness inside, and
   a strip across its hem, so the hem shows its thickness and the inside
   of the skirt draws from below.
4. Each vertex of the tube takes the weights of the shell at its top.
   Down the tube the weights pass over to the thighs: the right thigh
   turns the right side, the left thigh the left side, and the two share
   the middle of the front and the back. So the skirt opens as a leg
   lifts.

The skirt keeps the shell's `cover` attribute, falling to one half at the
hem, so a hem trim lies along it as along any hem.

This is not a three.js port. See Extensions.

    var envelope = skirt_envelope(whole, rig, 0.2, under, gap)
    var piece = hang_skirt(piece, envelope, rig, lined=True, thickness)
"""

from std.math import cos, pi, sin

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import NORMAL, POSITION, BufferGeometry
from extensions.attire.mesh_ops import COVER, MeshWriter, cut, merge, top_four
from extensions.humanoid.rig.joints import (
    HIPS,
    JOINT_COUNT,
    LEFT_THIGH,
    LEFT_HAND,
    RIGHT_THIGH,
    RIGHT_UPPER_ARM,
    HumanoidRig,
)
from math.utils import clamp
from math.vector3 import Vector3
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT

comptime SKIRT_STATURE = Float32(1.8288)
"""The template stature the skirt's lengths are given for, in meters."""
comptime SKIRT_TOP = Float32(0.03)
"""How far below the hip joints a skirt hangs from, in meters on the
template. The legs part 6 cm below them."""
comptime SKIRT_SIDES = 40
"""How many sides a skirt's tube has."""
comptime SKIRT_RING = Float32(0.03)
"""The most a skirt's rings lie apart, in meters on the template."""
comptime SKIRT_TUCK = Float32(0.015)
"""How far a skirt reaches up inside its shell, in meters on the
template."""
comptime SKIRT_INSET = Float32(0.002)
"""How far inside its shell the top of a skirt lies, in meters."""
comptime SKIRT_SPLIT = Float32(0.05)
"""Half the width of the middle of the front and the back that both
thighs turn, in meters on the template."""
comptime SKIRT_LEG_SHARE = Float32(0.9)
"""The share of the hem's weight the thighs take."""
comptime SKIRT_HEM_RAMP = Float32(0.04)
"""Over how many meters above the hem the cover value climbs from one
half to one."""
comptime SKIRT_SHORTEST = Float32(0.01)
"""A garment that reaches less than this below the top, in meters, hangs
no skirt."""


struct SkirtEnvelope(Copyable, Movable):
    """The rings a skirt hangs on: a radius at each side of each ring,
    round a vertical axis through the hips."""

    var center: Vector3
    """A point of the axis the radii are measured from."""
    var heights: List[Float32]
    """The height of each ring, from the top down. The last is the hem."""
    var radii: List[Float32]
    """`SKIRT_SIDES` radii a ring, ring by ring, in meters."""
    var tuck: Float32
    """The height of the ring tucked up inside the shell."""
    var tucked: List[Float32]
    """The radius of each side of the tucked ring, in meters."""
    var thickness: Float32
    """How thick the skirt's fabric is, in meters."""

    def __init__(out self, center: Vector3, thickness: Float32):
        """Hold no rings: a garment that hangs no skirt.

        Args:
            center: A point of the axis.
            thickness: The fabric's thickness, in meters.
        """
        self.center = center
        self.heights = List[Float32]()
        self.radii = List[Float32]()
        self.tuck = center.y
        self.tucked = List[Float32]()
        self.thickness = thickness

    def rings(self) -> Int:
        """Return how many rings the skirt has.

        Returns:
            Zero for a garment that hangs no skirt, else two or more.
        """
        return len(self.heights)

    def hem(self) -> Float32:
        """Return the height of the hem.

        Returns:
            The last ring's height, or the axis point's for no skirt.
        """
        if self.rings() == 0:
            return self.center.y
        return self.heights[self.rings() - 1]

    def radius_at(self, y: Float32, side: Int) -> Float32:
        """Return the skirt's radius at a height, on one side.

        Args:
            y: The height, in meters.
            side: A side, zero through `SKIRT_SIDES - 1`.

        Returns:
            The radius between the two rings round `y`, or zero above the
            top or below the hem.
        """
        for k in range(self.rings() - 1):
            var high = self.heights[k]
            var low = self.heights[k + 1]
            if y <= high and y >= low:
                var t = (high - y) / max(high - low, Float32(1e-6))
                var a = self.radii[k * SKIRT_SIDES + side]
                var b = self.radii[(k + 1) * SKIRT_SIDES + side]
                return a + (b - a) * t
        return 0


def skirt_scale(rig: HumanoidRig) -> Float32:
    """Return the rig's stature over the template's.

    Args:
        rig: The rig.

    Returns:
        The scale the skirt's template lengths take.
    """
    return rig.stature / SKIRT_STATURE


def skirt_top(rig: HumanoidRig) -> Float32:
    """Return the height a skirt hangs from.

    Args:
        rig: The rig the garment was made on.

    Returns:
        `SKIRT_TOP` below the hip joints, scaled to the stature.
    """
    return rig.joints[HIPS.value].y - SKIRT_TOP * skirt_scale(rig)


def _side_direction(side: Int) -> Vector3:
    """Return the unit direction of one side, round from the front."""
    var turn = 2 * Float32(pi) * Float32(side) / Float32(SKIRT_SIDES)
    return Vector3(sin(turn), 0, cos(turn))


def leg_side(piece: BufferGeometry) raises -> List[Bool]:
    """Return, per vertex, whether an arm does not weigh most on it.

    Args:
        piece: A skinned garment.

    Returns:
        False where an upper arm, a forearm or a hand weighs most.

    Raises:
        Error: If the mesh has no skin weights.
    """
    ref bones = piece.attribute_view(String(SKIN_INDEX))
    ref weights = piece.attribute_view(String(SKIN_WEIGHT))
    var legs = List[Bool](capacity=bones.count())
    for v in range(bones.count()):
        var best = 0
        for k in range(1, 4):  # pragma: no branch
            if weights.component(v, k) > weights.component(v, best):
                best = k
        var joint = Int(bones.component(v, best))
        legs.append(joint < RIGHT_UPPER_ARM.value or joint > LEFT_HAND.value)
    return legs^


def skirt_hem(
    piece: BufferGeometry, legs: List[Bool], top: Float32
) raises -> Float32:
    """Return the lowest height a garment reaches on the trunk and legs.

    Args:
        piece: A garment, cut at its hems.
        legs: Its `leg_side` flags.
        top: The height the skirt hangs from.

    Returns:
        The lowest height of a vertex on the trunk or the legs, or `top`
        if none lies below it.

    Raises:
        Error: If the mesh has no positions.
    """
    ref placed = piece.attribute_view(String(POSITION))
    var lowest = top
    for v in range(placed.count()):
        if legs[v]:
            lowest = min(lowest, placed.vector3(v).y)
    return lowest


def slice_segments(
    piece: BufferGeometry, legs: List[Bool], y: Float32
) raises -> List[Vector3]:
    """Return where the trunk and legs of a garment cross a level.

    Args:
        piece: A garment.
        legs: Its `leg_side` flags.
        y: The height of the level.

    Returns:
        Two points a segment, each where one triangle crosses the level.
        A triangle with a corner on an arm is left out.

    Raises:
        Error: If the mesh has no positions.
    """
    ref placed = piece.attribute_view(String(POSITION))
    var points = List[Vector3]()
    for t in range(piece.triangle_count()):
        var corners = List[Vector3](capacity=3)
        var on_legs = True
        for c in range(3):  # pragma: no branch
            var v = piece.corner_index(t, c)
            on_legs = on_legs and legs[v]
            corners.append(placed.vector3(v))
        if not on_legs:
            continue
        var crossing = List[Vector3]()
        for c in range(3):  # pragma: no branch
            var a = corners[c]
            var b = corners[(c + 1) % 3]
            if (a.y < y) != (b.y < y):
                var share = (y - a.y) / (b.y - a.y)
                crossing.append(a + (b - a) * share)
        if len(crossing) == 2:
            points.append(crossing[0])
            points.append(crossing[1])
    return points^


def _turn(o: Vector3, a: Vector3, b: Vector3) -> Float32:
    """Return the cross product of `a - o` and `b - o` in the level, x by
    z."""
    return (a.x - o.x) * (b.z - o.z) - (a.z - o.z) * (b.x - o.x)


def level_hull(points: List[Vector3]) -> List[Vector3]:
    """Return the convex hull of points in a level, by their x and z.

    Args:
        points: Points; their heights are ignored.

    Returns:
        The hull's corners in order round it, Andrew's monotone chain.
        Fewer than three points are returned as they are.
    """
    var count = len(points)
    if count < 3:
        return points.copy()
    var order = List[Int](capacity=count)
    for k in range(count):  # pragma: no branch
        order.append(k)
    # An insertion sort by x, then z: a slice holds a few hundred points.
    for i in range(1, count):  # pragma: no branch
        var k = order[i]
        var j = i - 1
        while j >= 0 and (
            points[order[j]].x > points[k].x
            or (
                points[order[j]].x == points[k].x
                and points[order[j]].z > points[k].z
            )
        ):
            order[j + 1] = order[j]
            j -= 1
        order[j + 1] = k
    var hull = List[Vector3]()
    for pass_ in range(2):  # pragma: no branch
        var start = len(hull)
        for i in range(count):  # pragma: no branch
            var p = points[order[i]]
            if pass_ == 1:
                p = points[order[count - 1 - i]]
            while (
                len(hull) >= start + 2
                and _turn(hull[len(hull) - 2], hull[len(hull) - 1], p) <= 0
            ):
                _ = hull.pop()
            hull.append(p)
        # The last point of each chain is the first of the other.
        _ = hull.pop()
    return hull^


def _ray_hit(
    center: Vector3, direction: Vector3, a: Vector3, b: Vector3
) -> Float32:
    """Return how far along a ray in the level it meets a segment, or
    a negative number if it misses."""
    var ex = b.x - a.x
    var ez = b.z - a.z
    var denominator = direction.x * ez - direction.z * ex
    if denominator == 0:
        return -1
    var wx = a.x - center.x
    var wz = a.z - center.z
    var along = (wx * ez - wz * ex) / denominator
    var share = (wx * direction.z - wz * direction.x) / denominator
    if share < 0 or share > 1:
        return -1
    return along


def hull_radii(hull: List[Vector3], center: Vector3) -> List[Float32]:
    """Return how far a closed outline lies from the axis, on each side.

    Args:
        hull: A closed outline round the axis, as `level_hull` gives.
        center: A point of the axis.

    Returns:
        `SKIRT_SIDES` radii: on each side, the farthest crossing of the
        outline. Zero on a side it does not cross.
    """
    var radii = List[Float32](capacity=SKIRT_SIDES)
    var count = len(hull)
    for side in range(SKIRT_SIDES):  # pragma: no branch
        var direction = _side_direction(side)
        var far = Float32(0)
        for k in range(count):
            far = max(
                far,
                _ray_hit(center, direction, hull[k], hull[(k + 1) % count]),
            )
        radii.append(far)
    return radii^


def segment_radii(segments: List[Vector3], center: Vector3) -> List[Float32]:
    """Return how far a slice's segments lie from the axis, on each side.

    Args:
        segments: Two points a segment, as `slice_segments` gives.
        center: A point of the axis.

    Returns:
        `SKIRT_SIDES` radii: on each side, the farthest crossing of a
        segment. Zero on a side no segment crosses.
    """
    var radii = List[Float32](capacity=SKIRT_SIDES)
    for side in range(SKIRT_SIDES):  # pragma: no branch
        var direction = _side_direction(side)
        var far = Float32(0)
        for k in range(len(segments) // 2):
            far = max(
                far,
                _ray_hit(
                    center, direction, segments[2 * k], segments[2 * k + 1]
                ),
            )
        radii.append(far)
    return radii^


def skirt_envelope(
    whole: BufferGeometry,
    rig: HumanoidRig,
    flare: Float32,
    under: List[SkirtEnvelope],
    clearance: Float32,
    thickness: Float32,
) raises -> SkirtEnvelope:
    """Return the rings a garment's skirt hangs on.

    Args:
        whole: The garment's whole shell, cut at its hems, with nothing
            hidden, in the pelvis frame.
        rig: The rig it was made on.
        flare: How far the skirt widens for each meter it falls.
        under: The skirts of the garments under it, which lift it.
        clearance: The gap it keeps off a skirt under it, in meters.
        thickness: Its fabric's thickness, in meters.

    Returns:
        The envelope. It has no rings when the garment reaches less than
        `SKIRT_SHORTEST` below the top.

    Raises:
        Error: If the mesh has no positions or skin weights.
    """
    var hips = rig.joints[HIPS.value]
    var top = skirt_top(rig)
    var envelope = SkirtEnvelope(Vector3(hips.x, top, hips.z), thickness)
    var legs = leg_side(whole)
    var hem = skirt_hem(whole, legs, top)
    if top - hem < SKIRT_SHORTEST:
        return envelope^
    var scale = skirt_scale(rig)
    var spacing = SKIRT_RING * scale
    var rings = Int((top - hem) / spacing) + 2
    var above = List[Float32]()
    for k in range(rings):  # pragma: no branch
        var y = top + (hem - top) * Float32(k) / Float32(rings - 1)
        envelope.heights.append(y)
        # A level at the hem itself touches only its lowest point.
        var sliced = max(y, hem + Float32(0.002))
        var radii = hull_radii(
            level_hull(slice_segments(whole, legs, sliced)), envelope.center
        )
        for side in range(SKIRT_SIDES):  # pragma: no branch
            var r = radii[side]
            if k > 0:
                # Cloth falls: no narrower than the ring above, and wider
                # by the flare.
                r = max(r, above[side] + flare * (envelope.heights[k - 1] - y))
            for skirt in under:
                var lifted = skirt.radius_at(y, side)
                if lifted > 0:
                    r = max(r, lifted + skirt.thickness + clearance)
            envelope.radii.append(r)
        above.clear()
        for side in range(SKIRT_SIDES):  # pragma: no branch
            above.append(envelope.radii[k * SKIRT_SIDES + side])
    envelope.tuck = top + SKIRT_TUCK * scale
    var inside = segment_radii(
        slice_segments(whole, legs, envelope.tuck), envelope.center
    )
    for side in range(SKIRT_SIDES):  # pragma: no branch
        var r = inside[side] - SKIRT_INSET
        if inside[side] <= 0:
            r = envelope.radii[side] - SKIRT_INSET
        envelope.tucked.append(r)
    return envelope^


def _nearest(placed_points: List[Vector3], legs: List[Bool], p: Vector3) -> Int:
    """Return the trunk or leg vertex nearest a point, or -1."""
    var best = -1
    var closest = Float32(1e30)
    for v in range(len(placed_points)):
        if not legs[v]:
            continue
        var d = (placed_points[v] - p).length_sq()
        if d < closest:
            closest = d
            best = v
    return best


def skirt_mesh(
    envelope: SkirtEnvelope,
    piece: BufferGeometry,
    rig: HumanoidRig,
    lined: Bool,
) raises -> BufferGeometry:
    """Return a skirt lofted through its envelope's rings.

    Args:
        envelope: An envelope with two rings or more.
        piece: The garment's shell, whose attributes the skirt takes and
            whose weights its top takes.
        rig: The rig the garment was made on.
        lined: Whether to add the inner face and the strip across the
            hem.

    Returns:
        The skirt, with the garment's attributes and normals.

    Raises:
        Error: If the envelope has fewer than two rings, or the mesh has
            no positions or skin weights.
    """
    var rings = envelope.rings()
    if rings < 2:
        raise Error("A skirt needs two rings or more")
    var legs = leg_side(piece)
    ref placed = piece.attribute_view(String(POSITION))
    ref bones = piece.attribute_view(String(SKIN_INDEX))
    ref weights = piece.attribute_view(String(SKIN_WEIGHT))
    var points = List[Vector3](capacity=placed.count())
    for v in range(placed.count()):
        points.append(placed.vector3(v))
    var top = envelope.heights[0]
    var hem = envelope.hem()
    var scale = skirt_scale(rig)
    var hips = rig.joints[HIPS.value]
    var right = Float32(1)
    if rig.joints[RIGHT_THIGH.value].x < hips.x:
        right = -1
    var split = SKIRT_SPLIT * scale
    var builder = MeshWriter(piece)
    # The rings of the outer face, from the tucked ring down, and of the
    # inner face, each `SKIRT_SIDES` vertices.
    var outer = List[Int]()
    var inner = List[Int]()
    var hem_outer = List[Int]()
    var hem_inner = List[Int]()
    for k in range(-1, rings):  # pragma: no branch
        var y = envelope.tuck
        if k >= 0:
            y = envelope.heights[k]
        var fall = clamp((top - y) / max(top - hem, Float32(1e-6)), 0, 1)
        var cover = Float32(0.5) + 0.5 * clamp((y - hem) / SKIRT_HEM_RAMP, 0, 1)
        for side in range(SKIRT_SIDES):  # pragma: no branch
            var direction = _side_direction(side)
            var r = envelope.tucked[side]
            if k >= 0:
                r = envelope.radii[k * SKIRT_SIDES + side]
            var p = envelope.center + direction * r
            p.y = y
            # The weights of the shell at the top of this side.
            var all = List[Float32](length=JOINT_COUNT, fill=0)
            var source = _nearest(
                points,
                legs,
                envelope.center + direction * envelope.radii[side],
            )
            if source >= 0:
                for c in range(4):  # pragma: no branch
                    all[Int(bones.component(source, c))] += (
                        1 - fall
                    ) * weights.component(source, c)
            else:
                all[HIPS.value] += 1 - fall
            var share = clamp(0.5 + right * (p.x - hips.x) / (2 * split), 0, 1)
            all[HIPS.value] += fall * (1 - SKIRT_LEG_SHARE)
            all[RIGHT_THIGH.value] += fall * SKIRT_LEG_SHARE * share
            all[LEFT_THIGH.value] += fall * SKIRT_LEG_SHARE * (1 - share)
            var chosen = top_four(all)
            outer.append(builder.add(p, cover, chosen[0], chosen[1]))
            var q = p - direction * envelope.thickness
            if lined:
                inner.append(builder.add(q, cover, chosen[0], chosen[1]))
            if lined and k == rings - 1:
                hem_outer.append(builder.add(p, 0.5, chosen[0], chosen[1]))
                hem_inner.append(builder.add(q, 0.5, chosen[0], chosen[1]))
    for k in range(rings):  # pragma: no branch
        for side in range(SKIRT_SIDES):  # pragma: no branch
            var next = (side + 1) % SKIRT_SIDES
            var a = k * SKIRT_SIDES + side
            var b = (k + 1) * SKIRT_SIDES + side
            var c = k * SKIRT_SIDES + next
            var d = (k + 1) * SKIRT_SIDES + next
            builder.quad(outer[a], outer[b], outer[c], outer[d])
            if lined:
                # The inner face looks in: its corners turn the other way.
                builder.quad(inner[c], inner[d], inner[a], inner[b])
    if lined:
        for side in range(SKIRT_SIDES):  # pragma: no branch
            var next = (side + 1) % SKIRT_SIDES
            builder.quad(
                hem_outer[side],
                hem_inner[side],
                hem_outer[next],
                hem_inner[next],
            )
    return builder.build()


def hang_skirt(
    piece: BufferGeometry,
    envelope: SkirtEnvelope,
    rig: HumanoidRig,
    lined: Bool,
    shown: Bool = True,
) raises -> BufferGeometry:
    """Return a garment with its shell below the top replaced by a skirt.

    Args:
        piece: The garment's shell, cut at its hems.
        envelope: Its skirt's envelope. With no rings the piece is
            returned as it is.
        rig: The rig it was made on.
        lined: Whether the skirt has an inner face and a strip across its
            hem.
        shown: Whether to add the skirt. False cuts the shell at the top
            and adds nothing, for a skirt a longer one over it hides.

    Returns:
        The garment: its shell above the top, on the arms and the rest,
        and the skirt if it is shown.

    Raises:
        Error: If the mesh has no positions or skin weights.
    """
    if envelope.rings() < 2:
        return piece.clone()
    var legs = leg_side(piece)
    ref placed = piece.attribute_view(String(POSITION))
    var top = envelope.heights[0]
    var values = List[Float32](capacity=placed.count())
    for v in range(placed.count()):
        var value = Float32(1)
        if legs[v]:
            value = placed.vector3(v).y - top
        values.append(value)
    var kept = cut(piece, values, 0)
    if not shown:
        return kept^
    return merge(kept, skirt_mesh(envelope, piece, rig, lined))
