# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The swimmer skeleton and fin membranes: procedural-animals'
`core/rig/swimmer.js`.

The fish and the sharks share one bone set. The axial chain runs from
the snout through `spine0` (behind the skull) to `spine{N}`, the caudal
base, and on along the caudal fin as `caudal1` to `caudal{M}`. Its bones
are `head` (spine0 to snout), `spine0` to `spine{N-1}` and `caudal0` to
`caudal{M-1}`. The head carries the lower `jaw`, an optional `upperJaw`
and optional gill covers. The paired fins are `pectoral{S}` and
`pelvic{S}`.

A fin is a membrane: an outline in the fin's plane, made of rays that
run from a base line sunk into the body to the ray tips, and given a
thickness. The outline is the same as the original's, so the painters can
find the rays again with `fin_ray_coords`.
"""

from extensions.sdf.ids import (
    BoneId,
    SurfacePart,
)
from extensions.animals.parts import BODY
from extensions.animals.rig import Rig, add_sided
from extensions.sdf.field import SdfModel
from extensions.sdf.vector import (
    V3,
    clamp,
    cross,
    normalize,
)
from std.math import cos, floor, pi, sin, sqrt


def spine_name(i: Int) -> String:
    """Return the name of one spine joint and bone.

    Args:
        i: The index, from zero at the skull.

    Returns:
        `spine` and the index.
    """
    return "spine" + String(i)


def swimmer_bones(
    mut rig: Rig,
    spine_segs: Int,
    caudal_segs: Int,
    pectoral_parent: String,
    pelvic_parent: String,
    jaw: Bool = True,
    upper_jaw: Bool = False,
    opercula: Bool = True,
) raises:
    """Add procedural-animals' standard swimmer bones.

    The rig must hold `snout`, `spine0` to `spine{N}`, `caudal0` (the
    same point as `spine{N}`) to `caudal{M}`, and the joints of the bones
    asked for, with the left joints mirrored.

    Args:
        rig: The rig, with its joints placed and mirrored.
        spine_segs: How many trunk bones, `N`.
        caudal_segs: How many caudal bones, `M`.
        pectoral_parent: The spine bone the pectoral fins hang from.
        pelvic_parent: The spine bone the pelvic fins hang from.
        jaw: Whether to add the lower jaw.
        upper_jaw: Whether to add the protrusible upper jaw.
        opercula: Whether to add the gill covers.

    Raises:
        Error: If a joint is missing.
    """
    _ = rig.add_bone(spine_name(0), spine_name(0), spine_name(1), "")
    _ = rig.add_bone("head", spine_name(0), "snout", spine_name(0))
    for i in range(1, spine_segs):
        _ = rig.add_bone(
            spine_name(i), spine_name(i), spine_name(i + 1), spine_name(i - 1)
        )
    for i in range(caudal_segs):
        var parent = spine_name(
            spine_segs - 1
        ) if i == 0 else "caudal" + String(i - 1)
        _ = rig.add_bone(
            "caudal" + String(i),
            "caudal" + String(i),
            "caudal" + String(i + 1),
            parent,
        )
    if jaw:
        _ = rig.add_bone("jaw", "jawHinge", "jawTip", "head")
    if upper_jaw:
        _ = rig.add_bone("upperJaw", "premaxBase", "premaxTip", "head")
    if opercula:
        add_sided(rig, "operculum{S}", "opHinge{S}", "opEdge{S}", "head")
    add_sided(rig, "pectoral{S}", "pecBase{S}", "pecTip{S}", pectoral_parent)
    add_sided(rig, "pelvic{S}", "pelBase{S}", "pelTip{S}", pelvic_parent)


def _cr(
    p0: Float64, p1: Float64, p2: Float64, p3: Float64, t: Float64
) -> Float64:
    # Catmull-Rom, clamped to the neighbors' range.
    var t2 = t * t
    var t3 = t2 * t
    var v = 0.5 * (
        2.0 * p1
        + (-p0 + p2) * t
        + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
        + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
    )
    var lo = min(p1, p2)
    var hi = max(p1, p2)
    var pad = (hi - lo) * 0.25
    return max(lo - pad, min(hi + pad, v))


struct Profile(Copyable, Movable):
    """A swimmer's outline table: rows of `u, top, bottom, half width`.

    `u` is a fraction of the body's length from the snout. The other
    columns are fractions of that length too. Between rows the table is
    read along a clamped Catmull-Rom curve, as the original reads it.
    """

    var rows: List[Float64]

    def __init__(out self, rows: List[Float64]):
        """Make a table from its rows, four numbers each.

        Args:
            rows: The rows, flat.
        """
        self.rows = rows.copy()

    def count(self) -> Int:
        """Return how many rows the table has.

        Returns:
            The row count.
        """
        return len(self.rows) // 4

    def col(self, i: Int, k: Int) -> Float64:
        """Return one cell, with the row index held to the table.

        Args:
            i: The row. It is clamped to the first and last rows.
            k: The column, from zero to three.

        Returns:
            The cell.
        """
        var n = self.count()
        var r = max(0, min(n - 1, i))
        return self.rows[r * 4 + k]

    def at(self, u: Float64, k: Int) -> Float64:
        """Return one column of the outline at `u`.

        Args:
            u: The fraction of the length from the snout.
            k: The column: 1 top, 2 bottom, 3 half width.

        Returns:
            The value, as a fraction of the length.
        """
        var n = self.count()
        var u0 = self.col(0, 0)
        if u <= u0:
            return self.col(0, k) * sqrt(max(0.0, u) / u0)
        if u >= self.col(n - 1, 0):
            return self.col(n - 1, k)
        var i = 0
        while i < n - 2 and u > self.col(i + 1, 0):
            i += 1
        var t = (u - self.col(i, 0)) / (self.col(i + 1, 0) - self.col(i, 0))
        return _cr(
            self.col(i - 1, k),
            self.col(i, k),
            self.col(i + 1, k),
            self.col(i + 2, k),
            t,
        )

    def max_of(self, k: Int) -> Float64:
        """Return the largest value of one column.

        Args:
            k: The column.

        Returns:
            The largest value.
        """
        var best = 0.0
        for i in range(self.count()):
            best = max(best, self.col(i, k))
        return best


def fan_rays(
    base0_u: Float64,
    base0_v: Float64,
    base1_u: Float64,
    base1_v: Float64,
    angle0: Float64,
    angle1: Float64,
    lengths: List[Float64],
) -> List[Float64]:
    """Return a fan of rays between two base points: `fanRays`.

    Args:
        base0_u: The first base point's `u`.
        base0_v: The first base point's `v`.
        base1_u: The last base point's `u`.
        base1_v: The last base point's `v`.
        angle0: The first ray's angle in the fin's plane, in degrees.
        angle1: The last ray's angle, in degrees.
        lengths: Each ray's length. Their count is the ray count.

    Returns:
        The rays, flat: base `u, v`, then tip `u, v`, for each ray.
    """
    var n = len(lengths)
    var rays = List[Float64](capacity=n * 4)
    for i in range(n):
        var t = 0.0 if n == 1 else Float64(i) / Float64(n - 1)
        var bu = base0_u + (base1_u - base0_u) * t
        var bv = base0_v + (base1_v - base0_v) * t
        var a = (angle0 + (angle1 - angle0) * t) * pi / 180.0
        rays.append(bu)
        rays.append(bv)
        rays.append(bu + cos(a) * lengths[i])
        rays.append(bv + sin(a) * lengths[i])
    return rays^


def fin_outline(
    rays: List[Float64], sink: Float64, notch: Float64
) -> List[Float64]:
    """Return a fin's outline from its rays: `sculptFin`'s polygon.

    The outline runs from the first base point, sunk into the body, over
    the ray tips, with a notch between tips for a spiny fin, to the last
    base point, sunk.

    Args:
        rays: The rays, as `fan_rays` returns them.
        sink: How far the base is pushed into the body.
        notch: How deep the membrane is notched between tips, zero to one.

    Returns:
        The outline, flat `u, v` pairs.
    """
    var n = len(rays) // 4
    var b0u = rays[0]
    var b0v = rays[1]
    var bnu = rays[(n - 1) * 4]
    var bnv = rays[(n - 1) * 4 + 1]
    var bdu = bnu - b0u
    var bdv = bnv - b0v
    var bl = sqrt(bdu * bdu + bdv * bdv)
    bl = bl if bl > 0.0 else 1.0
    var nx = -bdv / bl
    var ny = bdu / bl
    var mid = n // 2
    var flip = (rays[mid * 4 + 2] - b0u) * nx + (
        rays[mid * 4 + 3] - b0v
    ) * ny < 0.0
    nx = -nx if flip else nx
    ny = -ny if flip else ny
    var poly = List[Float64]()
    poly.append(b0u - nx * sink)
    poly.append(b0v - ny * sink)
    # The base points above read the first and the last ray, so a fin
    # that gets here has one.
    for i in range(n):  # pragma: no branch
        poly.append(rays[i * 4 + 2])
        poly.append(rays[i * 4 + 3])
        if notch > 0.0 and i < n - 1:
            var tmu = (rays[i * 4 + 2] + rays[i * 4 + 6]) / 2.0
            var tmv = (rays[i * 4 + 3] + rays[i * 4 + 7]) / 2.0
            var bmu = (rays[i * 4] + rays[i * 4 + 4]) / 2.0
            var bmv = (rays[i * 4 + 1] + rays[i * 4 + 5]) / 2.0
            poly.append(tmu + (bmu - tmu) * notch)
            poly.append(tmv + (bmv - tmv) * notch)
    poly.append(bnu - nx * sink)
    poly.append(bnv - ny * sink)
    return poly^


def sculpt_fin(
    mut m: SdfModel,
    tag: String,
    bone: BoneId,
    origin: V3,
    u: V3,
    v: V3,
    rays: List[Float64],
    t: Float64,
    sink: Float64 = 0.0,
    notch: Float64 = 0.0,
    k: Float64 = -1.0,
    round: Float64 = -1.0,
    part: SurfacePart = BODY,
    thin: Bool = True,
) raises -> Int:
    """Add a fin membrane: `sculptFin`.

    Args:
        m: The sculpt.
        tag: What the fin is.
        bone: The bone it rides.
        origin: The plane's origin.
        u: The plane's first axis.
        v: A direction in the plane, toward its second axis.
        rays: The rays, as `fan_rays` returns them.
        t: The membrane's thickness.
        sink: How far the base is pushed into the body.
        notch: How deep the membrane is notched between ray tips.
        k: The blend radius. Negative means the thickness.
        round: The rim radius. Negative means half the thickness.
        part: The surface it belongs to.
        thin: Whether coarse meshes must inflate it.

    Returns:
        The fin's index.

    Raises:
        Error: If the sculpt refuses the fin.
    """
    var poly = fin_outline(rays, sink, notch)
    return m.fin(
        tag,
        bone,
        origin,
        u,
        v,
        poly,
        t,
        round=round,
        k=k if k >= 0.0 else t,
        part=part,
        thin=thin,
    )


def fin_plane_v(u: V3, v: V3) -> V3:
    """Return a fin plane's second axis: `v` made square to `u`.

    Args:
        u: The plane's first axis.
        v: A direction in the plane.

    Returns:
        The unit second axis, as `SdfModel.fin` builds it.
    """
    var uu = normalize(u)
    var n = normalize(cross(u, v))
    return cross(n, uu)


@fieldwise_init
struct RayCoords(ImplicitlyCopyable):
    """Where a point lies in a fin's fan of rays.

    `phase` is a continuous ray index, from zero to the last ray. `along`
    is zero at the base and one at the tips.
    """

    var phase: Float64
    var along: Float64


def _side(rays: List[Float64], i: Int, qu: Float64, qv: Float64) -> Float64:
    var bu = rays[i * 4]
    var bv = rays[i * 4 + 1]
    var dx = rays[i * 4 + 2] - bu
    var dy = rays[i * 4 + 3] - bv
    var l = sqrt(dx * dx + dy * dy)
    l = l if l > 0.0 else 1.0
    return ((qu - bu) * -dy + (qv - bv) * dx) / l


def fin_ray_coords(rays: List[Float64], qu: Float64, qv: Float64) -> RayCoords:
    """Return a point's ray coordinates in a fin: `finRayCoords`.

    A point outside the fan is held to the nearest ray.

    Args:
        rays: The fin's rays, as `fan_rays` returns them.
        qu: The point's `u` in the fin's plane.
        qv: The point's `v`.

    Returns:
        The phase and the fraction along the ray.
    """
    var n = len(rays) // 4
    var s0 = _side(rays, 0, qu, qv)
    var sn = _side(rays, n - 1, qu, qv)
    var t0u = rays[2] - rays[0]
    var t0v = rays[3] - rays[1]
    var bnu = rays[(n - 1) * 4] - rays[0]
    var bnv = rays[(n - 1) * 4 + 1] - rays[1]
    var sgn = 1.0 if bnu * -t0v + bnv * t0u >= 0.0 else -1.0
    var phase = 0.0
    # A point that is not a number takes the first ray.
    if not s0 * sgn > 0.0:
        phase = 0.0
    elif sn * sgn >= 0.0:
        phase = Float64(n - 1)
    else:
        var prev = s0 * sgn
        # The first and the last ray lie on opposite sides of the point,
        # so there are two rays at least.
        for i in range(1, n):  # pragma: no branch
            var si = _side(rays, i, qu, qv) * sgn
            if si <= 0.0:
                phase = Float64(i - 1) + prev / (prev - si)
                break
            prev = si
    var i0 = min(n - 2, Int(floor(phase)))
    var f = phase - Float64(i0)
    var bu = rays[i0 * 4] + (rays[i0 * 4 + 4] - rays[i0 * 4]) * f
    var bv = rays[i0 * 4 + 1] + (rays[i0 * 4 + 5] - rays[i0 * 4 + 1]) * f
    var tu = rays[i0 * 4 + 2] + (rays[i0 * 4 + 6] - rays[i0 * 4 + 2]) * f
    var tv = rays[i0 * 4 + 3] + (rays[i0 * 4 + 7] - rays[i0 * 4 + 3]) * f
    var dx = tu - bu
    var dy = tv - bv
    var l2 = dx * dx + dy * dy
    l2 = l2 if l2 > 0.0 else 1e-12
    var along = clamp(((qu - bu) * dx + (qv - bv) * dy) / l2, 0.0, 1.2)
    return RayCoords(phase, along)


def offset_poly(poly: List[Float64], d: Float64) -> List[Float64]:
    """Return a polygon grown outward by `d`: the sculpts' `offsetPoly`.

    Each point moves along its two edges' mean normal, so the result is
    approximate at sharp corners, as the original's is.

    Args:
        poly: The polygon, flat `u, v` pairs.
        d: How far to grow it. Negative shrinks it.

    Returns:
        The grown polygon.
    """
    var n = len(poly) // 2
    var area = 0.0
    for i in range(n):
        var j = (i + 1) % n
        area += poly[i * 2] * poly[j * 2 + 1] - poly[j * 2] * poly[i * 2 + 1]
    var sgn = 1.0 if area > 0.0 else -1.0
    var out = List[Float64](capacity=n * 2)
    for i in range(n):
        var a = (i + n - 1) % n
        var b = (i + 1) % n
        var e1 = normalize(
            V3(poly[i * 2] - poly[a * 2], poly[i * 2 + 1] - poly[a * 2 + 1], 0)
        )
        var e2 = normalize(
            V3(poly[b * 2] - poly[i * 2], poly[b * 2 + 1] - poly[i * 2 + 1], 0)
        )
        var nn = normalize(
            V3(e1.y * sgn + e2.y * sgn, -e1.x * sgn - e2.x * sgn, 0)
        )
        out.append(poly[i * 2] + nn.x * d)
        out.append(poly[i * 2 + 1] + nn.y * d)
    return out^
