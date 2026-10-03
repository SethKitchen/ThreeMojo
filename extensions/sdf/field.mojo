# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The signed distance field an animal is sculpted in.

This is procedural-animals' `core/sdf/sdf.js`. Primitives are attached
to bones. Solid primitives join with a polynomial smooth minimum, each
with its own blend radius `k`. Carving primitives cut with the matching
smooth maximum. Primitives are evaluated in the order they were added.

The field is negative inside the animal. Distances are meters.
"""

from extensions.sdf.ids import (
    BoneId,
    CONE,
    ELLIPSOID,
    FIN,
    LENS,
    PrimitiveKind,
    SurfacePart,
    TagId,
    require_part,
)
from extensions.sdf.vector import (
    Rigid,
    V3,
    cross,
    dot,
    frame_zy,
    length,
    normalize,
)
from std.collections import Dict
from std.math import sqrt

# The value of an empty field: far outside everything.
comptime FAR = 1e9


@fieldwise_init
struct Primitive(ImplicitlyCopyable):
    """One solid of a sculpt.

    The fields mean different things for each kind:

    - `ELLIPSOID`: center `c`, local axes `ax`, `ay`, `az`, radii `r`.
    - `CONE`: ends `c` and `b`, radii `r.x` at `c` and `r.y` at `b`.
    - `LENS`: center `c`, frame `ax`, `ay`, `az`. `r.x` is the arc radius,
      `r.y` the arc offset, and `lo` to `hi` the depth slab along `az`.
    - `FIN`: origin `c`, plane axes `ax` and `ay`, normal `az`. `r.x` is the
      half thickness and `r.y` the rim radius. The outline is `count`
      points in `SdfModel.outline` from `first`. `lo` and `hi` taper the
      half thickness per meter along `ax` and `ay`.
    """

    var kind: PrimitiveKind
    var c: V3
    var b: V3
    var ax: V3
    var ay: V3
    var az: V3
    var r: V3
    var lo: Float64
    var hi: Float64
    var first: Int
    var count: Int
    var k: Float64
    var carve: Bool
    var bone: BoneId
    var part: SurfacePart
    var tag: TagId
    var thin: Bool

    def moved(self, by: Rigid) -> Self:
        """Return the primitive moved rigidly. Its shape does not change.

        Args:
            by: The rigid transform.

        Returns:
            The moved primitive.
        """
        var out = self
        out.c = by.apply(self.c)
        out.b = by.apply(self.b)
        out.ax = by.turn(self.ax)
        out.ay = by.turn(self.ay)
        out.az = by.turn(self.az)
        return out


def smin(a: Float64, b: Float64, k: Float64) -> Float64:
    """Return the polynomial smooth minimum of two distances.

    Args:
        a: One distance.
        b: The other distance.
        k: The blend radius. Zero or less is the plain minimum.

    Returns:
        The blended distance. It never exceeds `min(a, b)`.
    """
    var low = a if a < b else b
    if k <= 0.0:
        return low
    var h = max(k - abs(a - b), 0.0) / k
    return low - h * h * k * 0.25


def _ellipsoid(p: Primitive, q: V3) -> Float64:
    var d = q - p.c
    var qx = dot(d, p.ax) / p.r.x
    var qy = dot(d, p.ay) / p.r.y
    var qz = dot(d, p.az) / p.r.z
    var k0 = sqrt(qx * qx + qy * qy + qz * qz)
    var sx = qx / p.r.x
    var sy = qy / p.r.y
    var sz = qz / p.r.z
    var k1 = sqrt(sx * sx + sy * sy + sz * sz)
    if k1 < 1e-12:
        return -min(p.r.x, min(p.r.y, p.r.z))
    return k0 * (k0 - 1.0) / k1


def _sign(x: Float64) -> Float64:
    return 1.0 if x > 0.0 else (-1.0 if x < 0.0 else 0.0)


def _cone(p: Primitive, q: V3) -> Float64:
    # Inigo Quilez's exact round cone.
    var pa = q - p.c
    var ba = p.b - p.c
    var l2 = dot(ba, ba)
    var rr = p.r.x - p.r.y
    var a2 = l2 - rr * rr
    var il2 = 1.0 / l2
    var y = dot(pa, ba)
    var z = y - l2
    var v = pa * l2 - ba * y
    var x2 = dot(v, v)
    var y2 = y * y * l2
    var z2 = z * z * l2
    var k = _sign(rr) * rr * rr * x2
    if _sign(z) * a2 * z2 > k:
        return sqrt(x2 + z2) * il2 - p.r.y
    if _sign(y) * a2 * y2 < k:
        return sqrt(x2 + y2) * il2 - p.r.x
    return (sqrt(x2 * a2 * il2) + y * rr) * il2 - p.r.x


def _lens(p: Primitive, q: V3) -> Float64:
    var d = q - p.c
    var lx = dot(d, p.ax)
    var ly = dot(d, p.ay)
    var lz = dot(d, p.az)
    var upper = sqrt(lx * lx + (ly + p.r.y) * (ly + p.r.y)) - p.r.x
    var lower = sqrt(lx * lx + (ly - p.r.y) * (ly - p.r.y)) - p.r.x
    return max(max(upper, lower), max(p.lo - lz, lz - p.hi))


def outline_distance(
    outline: List[Float64], first: Int, count: Int, px: Float64, py: Float64
) -> Float64:
    """Return the signed distance to a closed polygon in its plane.

    Args:
        outline: Flat `u, v` pairs.
        first: The index of the polygon's first pair.
        count: How many points the polygon has.
        px: The point's `u`.
        py: The point's `v`.

    Returns:
        The distance. Negative inside, either winding.
    """
    var at = first * 2
    var dx = px - outline[at]
    var dy = py - outline[at + 1]
    var best = dx * dx + dy * dy
    var s = 1.0
    var j = count - 1
    for i in range(count):
        var ix = outline[at + i * 2]
        var iy = outline[at + i * 2 + 1]
        var ex = outline[at + j * 2] - ix
        var ey = outline[at + j * 2 + 1] - iy
        var wx = px - ix
        var wy = py - iy
        var ee = ex * ex + ey * ey
        var t = min(max((wx * ex + wy * ey) / max(ee, 1e-18), 0.0), 1.0)
        var bx = wx - ex * t
        var by = wy - ey * t
        best = min(best, bx * bx + by * by)
        # The crossing test of the winding rule, as one count: the sign
        # flips when all three tests agree.
        var agree = Int(py >= iy) + Int(py < iy + ey) + Int(ex * wy > ey * wx)
        if agree % 3 == 0:
            s = -s
        j = i
    return s * sqrt(best)


def _fin(p: Primitive, outline: List[Float64], q: V3) -> Float64:
    var d = q - p.c
    var pu = dot(d, p.ax)
    var pv = dot(d, p.ay)
    var pn = dot(d, p.az)
    var half = max(0.2 * p.r.x, p.r.x + p.lo * pu + p.hi * pv)
    var rho = min(half, p.r.y * half / p.r.x)
    var ex = outline_distance(outline, p.first, p.count, pu, pv) + rho
    var ey = abs(pn) - (half - rho)
    var ox = max(ex, 0.0)
    var oy = max(ey, 0.0)
    var slope = sqrt(p.lo * p.lo + p.hi * p.hi)
    var inner = min(max(ex, ey), 0.0) + sqrt(ox * ox + oy * oy) - rho
    return inner / sqrt(1.0 + slope * slope)


def primitive_distance(p: Primitive, outline: List[Float64], q: V3) -> Float64:
    """Return the distance from a point to one primitive.

    Args:
        p: The primitive.
        outline: The model's fin outlines.
        q: The point.

    Returns:
        The signed distance. Exact for balls, cones, lenses and flat fins,
        a close bound for ellipsoids.
    """
    if p.kind == ELLIPSOID:
        return _ellipsoid(p, q)
    if p.kind == CONE:
        return _cone(p, q)
    if p.kind == LENS:
        return _lens(p, q)
    return _fin(p, outline, q)


struct SdfModel(Movable):
    """A sculpt: an ordered list of primitives and their tags.

    `ell`, `sphere`, `cone`, `lens` and `fin` add a primitive and return
    its index. procedural-animals' `SDFModel` has the same five methods.
    """

    var prims: List[Primitive]
    var outline: List[Float64]
    var tags: List[String]
    var tag_at: Dict[String, Int]

    def __init__(out self):
        """Make an empty sculpt."""
        self.prims = List[Primitive]()
        self.outline = List[Float64]()
        self.tags = List[String]()
        self.tag_at = Dict[String, Int]()

    def tag(mut self, name: String) -> TagId:
        """Return the id of a tag, adding the tag when it is new.

        Args:
            name: The tag, such as `nose`.

        Returns:
            Its id.
        """
        var i = self.tag_at.get(name, -1)
        if i >= 0:
            return TagId(i)
        self.tag_at[name] = len(self.tags)
        self.tags.append(name)
        return TagId(len(self.tags) - 1)

    def tag_name(self, id: TagId) raises -> String:
        """Return the name of a tag.

        Args:
            id: The tag.

        Returns:
            Its name.

        Raises:
            Error: If `id` names no tag of this sculpt.
        """
        if not id.is_valid() or id.value >= len(self.tags):
            raise Error("Tag id names no tag of this sculpt")
        return self.tags[id.value]

    def _push(
        mut self,
        kind: PrimitiveKind,
        tag: String,
        bone: BoneId,
        c: V3,
        b: V3,
        f_x: V3,
        f_y: V3,
        f_z: V3,
        r: V3,
        k: Float64,
        carve: Bool,
        part: SurfacePart,
        thin: Bool,
    ) raises -> Int:
        if not bone.is_valid():
            raise Error("A primitive's bone must not be negative")
        require_part(part)
        if not k >= 0.0:
            raise Error("A blend radius must not be negative")
        var id = self.tag(tag)
        self.prims.append(
            Primitive(
                kind,
                c,
                b,
                f_x,
                f_y,
                f_z,
                r,
                0.0,
                0.0,
                0,
                0,
                k,
                carve,
                bone,
                part,
                id,
                thin,
            )
        )
        return len(self.prims) - 1

    def ell(
        mut self,
        tag: String,
        bone: BoneId,
        c: V3,
        r: V3,
        axis: V3 = V3(0.0, 0.0, 1.0),
        up: V3 = V3(0.0, 1.0, 0.0),
        k: Float64 = 0.02,
        carve: Bool = False,
        part: SurfacePart = SurfacePart(0),
        thin: Bool = False,
    ) raises -> Int:
        """Add an ellipsoid.

        Args:
            tag: What the primitive is.
            bone: The bone it rides.
            c: The center.
            r: The radii along the local x, y and z axes.
            axis: The direction of the local z axis.
            up: A direction near the local y axis.
            k: The blend radius.
            carve: Whether it cuts instead of adds.
            part: The surface it belongs to.
            thin: Whether coarse meshes must inflate it to stay visible.

        Returns:
            Its index.

        Raises:
            Error: If a radius is not positive, `bone` is negative, `k` is
                negative or `part` is not a named part.
        """
        if not min(r.x, min(r.y, r.z)) > 0.0:
            raise Error("An ellipsoid's radii must be positive")
        var f = frame_zy(axis, up)
        return self._push(
            ELLIPSOID, tag, bone, c, c, f.x, f.y, f.z, r, k, carve, part, thin
        )

    def sphere(
        mut self,
        tag: String,
        bone: BoneId,
        c: V3,
        rad: Float64,
        k: Float64 = 0.02,
        carve: Bool = False,
        part: SurfacePart = SurfacePart(0),
        thin: Bool = False,
    ) raises -> Int:
        """Add a ball.

        Args:
            tag: What the primitive is.
            bone: The bone it rides.
            c: The center.
            rad: The radius.
            k: The blend radius.
            carve: Whether it cuts instead of adds.
            part: The surface it belongs to.
            thin: Whether coarse meshes must inflate it to stay visible.

        Returns:
            Its index.

        Raises:
            Error: If the radius is not positive, or `ell` refuses the rest.
        """
        return self.ell(
            tag,
            bone,
            c,
            V3(rad, rad, rad),
            k=k,
            carve=carve,
            part=part,
            thin=thin,
        )

    def cone(
        mut self,
        tag: String,
        bone: BoneId,
        a: V3,
        b: V3,
        ra: Float64,
        rb: Float64,
        k: Float64 = 0.02,
        carve: Bool = False,
        part: SurfacePart = SurfacePart(0),
        thin: Bool = False,
    ) raises -> Int:
        """Add a round cone, a tapered capsule.

        Args:
            tag: What the primitive is.
            bone: The bone it rides.
            a: One end.
            b: The other end.
            ra: The radius at `a`.
            rb: The radius at `b`.
            k: The blend radius.
            carve: Whether it cuts instead of adds.
            part: The surface it belongs to.
            thin: Whether coarse meshes must inflate it to stay visible.

        Returns:
            Its index.

        Raises:
            Error: If the ends meet, a radius is negative, one ball holds
                the other, or `_push` refuses the rest.
        """
        var ab = length(b - a)
        if not ab > 0.0:
            raise Error("A cone's ends must differ")
        if not min(ra, rb) >= 0.0:
            raise Error("A cone's radii must not be negative")
        if not abs(ra - rb) < ab:
            raise Error("A cone's balls must not hold each other")
        var unit = V3(0.0, 0.0, 0.0)
        return self._push(
            CONE,
            tag,
            bone,
            a,
            b,
            unit,
            unit,
            unit,
            V3(ra, rb, 0.0),
            k,
            carve,
            part,
            thin,
        )

    def lens(
        mut self,
        tag: String,
        bone: BoneId,
        c: V3,
        x: V3,
        y: V3,
        z: V3,
        big_r: Float64,
        d: Float64,
        z_min: Float64,
        z_max: Float64,
        k: Float64 = 0.02,
        carve: Bool = False,
        part: SurfacePart = SurfacePart(0),
    ) raises -> Int:
        """Add an almond prism: two circular arcs along `z`, cut to a slab.

        Args:
            tag: What the primitive is.
            bone: The bone it rides.
            c: The center.
            x: The frame's x axis, across the almond.
            y: The frame's y axis, toward the upper lid.
            z: The frame's z axis, the depth.
            big_r: The arcs' radius.
            d: How far each arc's center is offset along `y`.
            z_min: The near face of the slab.
            z_max: The far face of the slab.
            k: The blend radius.
            carve: Whether it cuts instead of adds.
            part: The surface it belongs to.

        Returns:
            Its index.

        Raises:
            Error: If the arcs do not overlap, the slab is empty, or
                `_push` refuses the rest.
        """
        if not (d >= 0.0 and d < big_r):
            raise Error("A lens's arcs must overlap")
        if not z_max > z_min:
            raise Error("A lens's slab must not be empty")
        var id = self._push(
            LENS,
            tag,
            bone,
            c,
            c,
            x,
            y,
            z,
            V3(big_r, d, 0.0),
            k,
            carve,
            part,
            False,
        )
        self.prims[id].lo = z_min
        self.prims[id].hi = z_max
        return id

    def fin(
        mut self,
        tag: String,
        bone: BoneId,
        o: V3,
        u: V3,
        v: V3,
        poly: List[Float64],
        t: Float64,
        round: Float64 = -1.0,
        grad_u: Float64 = 0.0,
        grad_v: Float64 = 0.0,
        k: Float64 = 0.02,
        carve: Bool = False,
        part: SurfacePart = SurfacePart(0),
        thin: Bool = False,
    ) raises -> Int:
        """Add a fin: a polygon in a plane, given a thickness.

        Args:
            tag: What the primitive is.
            bone: The bone it rides.
            o: The plane's origin.
            u: The plane's first axis.
            v: A direction in the plane, toward its second axis.
            poly: The outline as flat `u, v` pairs, either winding.
            t: The thickness.
            round: The rim radius. Negative means half the thickness.
            grad_u: How fast the half thickness changes along `u`.
            grad_v: How fast the half thickness changes along `v`.
            k: The blend radius.
            carve: Whether it cuts instead of adds.
            part: The surface it belongs to.
            thin: Whether coarse meshes must inflate it to stay visible.

        Returns:
            Its index.

        Raises:
            Error: If the outline has fewer than three points or an odd
                count of numbers, the thickness is not positive, or
                `_push` refuses the rest.
        """
        if len(poly) < 6 or len(poly) % 2 != 0:
            raise Error("A fin's outline needs three or more points")
        if not t > 0.0:
            raise Error("A fin's thickness must be positive")
        var uu = normalize(u)
        var n = normalize(cross(u, v))
        var vv = cross(n, uu)
        var half = t / 2.0
        var rim = half if round < 0.0 else min(round, half)
        var id = self._push(
            FIN,
            tag,
            bone,
            o,
            o,
            uu,
            vv,
            n,
            V3(half, rim, 0.0),
            k,
            carve,
            part,
            thin,
        )
        self.prims[id].first = len(self.outline) // 2
        self.prims[id].count = len(poly) // 2
        self.prims[id].lo = grad_u
        self.prims[id].hi = grad_v
        for value in poly:  # pragma: no branch
            self.outline.append(value)
        return id

    def distance(self, index: Int, q: V3) -> Float64:
        """Return the distance from a point to one primitive.

        Args:
            index: The primitive.
            q: The point.

        Returns:
            The signed distance.
        """
        return primitive_distance(self.prims[index], self.outline, q)

    def eval_list(self, list: List[Int], q: V3) -> Float64:
        """Return the field of some primitives, in model order.

        Args:
            list: Primitive indexes, ascending.
            q: The point.

        Returns:
            The blended signed distance. `FAR` for an empty list.
        """
        return self.eval_span(list, 0, len(list), q)

    def eval_span(self, ids: List[Int], start: Int, end: Int, q: V3) -> Float64:
        """Return the field of a run of a primitive list, in model order.

        Args:
            ids: Primitive indexes. The run must be ascending.
            start: The first entry of the run.
            end: One past the last entry.
            q: The point.

        Returns:
            The blended signed distance. `FAR` for an empty run.
        """
        var d = FAR
        for n in range(start, end):
            ref p = self.prims[ids[n]]
            var di = primitive_distance(p, self.outline, q)
            d = -smin(-d, di, p.k) if p.carve else smin(d, di, p.k)
        return d

    def part_list(self, part: SurfacePart) -> List[Int]:
        """Return the indexes of the primitives of one surface.

        Args:
            part: The surface.

        Returns:
            Its primitives, in model order.
        """
        var out = List[Int]()
        for i in range(len(self.prims)):
            if self.prims[i].part == part:
                out.append(i)
        return out^

    def max_blend(self) -> Float64:
        """Return the largest blend radius of the sculpt.

        Returns:
            The radius. Zero for an empty sculpt.
        """
        var k = 0.0
        for p in self.prims:
            k = max(k, p.k)
        return k

    def cull(
        self, list: List[Int], c: V3, rho: Float64, kmax: Float64
    ) -> List[Int]:
        """Return the primitives that can change the field inside a ball.

        This is procedural-animals' conservative cull. A solid farther
        from the center than the nearest solid, by more than the ball
        and both blend radii, cannot reach the surface inside the ball.

        Args:
            list: The candidates, in model order.
            c: The ball's center.
            rho: The ball's radius.
            kmax: The largest blend radius of the candidates.

        Returns:
            The survivors, in model order.
        """
        var dv = List[Float64](capacity=len(list))
        var best = FAR
        for i in list:
            ref p = self.prims[i]
            var d = primitive_distance(p, self.outline, c)
            dv.append(d)
            best = best if p.carve else min(best, d)
        var out = List[Int]()
        var margin = 2.2 * rho + 0.5 * kmax
        for n in range(len(list)):
            ref p = self.prims[list[n]]
            var reach = (
                p.k + margin + max(0.0, -best) if p.carve else margin + p.k
            )
            var gap = dv[n] if p.carve else dv[n] - best
            if gap < reach:
                out.append(list[n])
        return out^

    def gradient(self, list: List[Int], q: V3, e: Float64) -> V3:
        """Return the field's gradient by four tetrahedral samples.

        Args:
            list: The primitives to evaluate.
            q: The point.
            e: The sample offset.

        Returns:
            The gradient, not normalized.
        """
        return self.gradient_span(list, 0, len(list), q, e)

    def gradient_span(
        self, ids: List[Int], start: Int, end: Int, q: V3, e: Float64
    ) -> V3:
        """Return the gradient of a run of a primitive list.

        Args:
            ids: Primitive indexes.
            start: The first entry of the run.
            end: One past the last entry.
            q: The point.
            e: The sample offset.

        Returns:
            The gradient, not normalized.
        """
        var a = self.eval_span(ids, start, end, V3(q.x + e, q.y - e, q.z - e))
        var b = self.eval_span(ids, start, end, V3(q.x - e, q.y - e, q.z + e))
        var c = self.eval_span(ids, start, end, V3(q.x - e, q.y + e, q.z - e))
        var d = self.eval_span(ids, start, end, V3(q.x + e, q.y + e, q.z + e))
        var s = 1.0 / (4.0 * e)
        return V3(
            (a - b - c + d) * s, (-a - b + c + d) * s, (-a + b - c + d) * s
        )

    def nearest(self, list: List[Int], q: V3) -> Int:
        """Return the solid primitive nearest a point.

        Args:
            list: The candidates.
            q: The point.

        Returns:
            The index of the nearest solid, or -1 if none is solid.
        """
        return self.nearest_span(list, 0, len(list), q)

    def nearest_span(self, ids: List[Int], start: Int, end: Int, q: V3) -> Int:
        """Return the solid primitive of a run nearest a point.

        Args:
            ids: Primitive indexes.
            start: The first entry of the run.
            end: One past the last entry.
            q: The point.

        Returns:
            The index of the nearest solid, or -1 if none is solid.
        """
        var best = FAR
        var at = -1
        for n in range(start, end):
            ref p = self.prims[ids[n]]
            var d = primitive_distance(p, self.outline, q)
            var closer = (not p.carve) and d < best
            best = d if closer else best
            at = ids[n] if closer else at
        return at

    def nearest_pair_span(
        self, ids: List[Int], start: Int, end: Int, q: V3
    ) -> Tuple[Int, Int]:
        """Return the nearest solid, and the nearest solid on another bone.

        Args:
            ids: Primitive indexes.
            start: The first entry of the run.
            end: One past the last entry.
            q: The point.

        Returns:
            The two indexes. Either is -1 when the run has no such solid.
        """
        var first = self.nearest_span(ids, start, end, q)
        if first < 0:
            return (-1, -1)
        var bone = self.prims[first].bone
        var best = FAR
        var at = -1
        for n in range(start, end):  # pragma: no branch
            ref p = self.prims[ids[n]]
            var d = primitive_distance(p, self.outline, q)
            var closer = (not p.carve) and p.bone != bone and d < best
            best = d if closer else best
            at = ids[n] if closer else at
        return (first, at)

    def moved(self, transforms: List[Rigid]) raises -> SdfModel:
        """Return the sculpt with every primitive moved by its bone.

        Args:
            transforms: One rigid transform per bone, by bone index.

        Returns:
            The posed sculpt.

        Raises:
            Error: If a primitive's bone has no transform.
        """
        var out = SdfModel()
        out.outline = self.outline.copy()
        out.tags = self.tags.copy()
        out.tag_at = self.tag_at.copy()
        for p in self.prims:
            if p.bone.value >= len(transforms):
                raise Error("A primitive's bone has no transform")
            out.prims.append(p.moved(transforms[p.bone.value]))
        return out^
