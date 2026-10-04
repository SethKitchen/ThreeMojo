# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Seeded proportion warps: procedural-animals' `core/build/warp.js`.

A species sculpts one reference animal. Each individual's longer legs,
bigger head or longer body is a small, smooth warp of space.

procedural-animals warps the finished mesh. This port warps the sculpt
instead: each primitive's center moves with the warp, and its axes and
radii follow the warp's Jacobian there. The surface is then meshed from
the warped field, so it stays a true distance field surface and its
normals are exact.
"""

from extensions.sdf.ids import (
    CONE,
    ELLIPSOID,
    LENS,
)
from extensions.animals.rig import Rig
from extensions.sdf.field import (
    Primitive,
    SdfModel,
)
from extensions.sdf.vector import (
    Frame,
    V3,
    cross,
    dot,
    frame_zy,
    length,
    smoothstep,
)
from std.math import cbrt


@fieldwise_init
struct WarpKind(Equatable, ImplicitlyCopyable, Writable):
    """Which warp a `Warp` is.

    `SCALE` scales about the origin. `LEGS` stretches height below a belly
    line. `LENGTH` stretches z between two planes. `SCALE_ABOUT` scales
    about a point and fades out with distance. `GIRTH` widens the torso.
    `SHIFT` moves what lies past a line segment.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the six warps.

        Returns:
            Whether the value is from zero to five.
        """
        return self.value >= 0 and self.value < 6


comptime SCALE = WarpKind(0)
comptime LEGS = WarpKind(1)
comptime LENGTH = WarpKind(2)
comptime SCALE_ABOUT = WarpKind(3)
comptime GIRTH = WarpKind(4)
comptime SHIFT = WarpKind(5)

# The finite-difference step of the Jacobian, as procedural-animals uses.
comptime JACOBIAN_STEP = 0.002


@fieldwise_init
struct Warp(ImplicitlyCopyable):
    """One warp. The fields each kind reads are named in its constructor.

    `k` is the factor. `a` and `b` are two distances. `c`, `d` and `m` are
    a center, a second point and a move.
    """

    var kind: WarpKind
    var k: Float64
    var a: Float64
    var b: Float64
    var c: V3
    var d: V3
    var m: V3


def scale_warp(k: Float64) -> Warp:
    """Return a uniform scale about the origin.

    Args:
        k: The factor.

    Returns:
        The warp.
    """
    var zero = V3(0.0, 0.0, 0.0)
    return Warp(SCALE, k, 0.0, 0.0, zero, zero, zero)


def legs_warp(k: Float64, top: Float64) -> Warp:
    """Return a stretch of everything below a belly line.

    Args:
        k: The factor below the line.
        top: The height of the line, in meters.

    Returns:
        The warp. Everything above the line moves up rigidly.
    """
    var zero = V3(0.0, 0.0, 0.0)
    return Warp(LEGS, k, top, 0.0, zero, zero, zero)


def length_warp(k: Float64, z0: Float64, z1: Float64) -> Warp:
    """Return a stretch of the span between two z planes.

    Args:
        k: The factor.
        z0: The back plane, in meters.
        z1: The front plane, in meters.

    Returns:
        The warp. The ends move rigidly.
    """
    var zero = V3(0.0, 0.0, 0.0)
    return Warp(LENGTH, k, z0, z1, zero, zero, zero)


def scale_about_warp(c: V3, k: Float64, r0: Float64, r1: Float64) -> Warp:
    """Return a scale about a point that fades out with distance.

    Args:
        c: The center.
        k: The factor at the center.
        r0: Where the fade starts, in meters.
        r1: Where the fade ends, in meters.

    Returns:
        The warp.
    """
    var zero = V3(0.0, 0.0, 0.0)
    return Warp(SCALE_ABOUT, k, r0, r1, c, zero, zero)


def girth_warp(
    k: Float64, cy: Float64, z0: Float64, z1: Float64, fade: Float64 = 0.08
) -> Warp:
    """Return a widening of the torso between two z planes.

    Args:
        k: The factor.
        cy: The height of the torso's center, in meters.
        z0: The back plane, in meters.
        z1: The front plane, in meters.
        fade: How wide the ramps at the planes are, in meters.

    Returns:
        The warp.
    """
    var zero = V3(0.0, 0.0, 0.0)
    return Warp(GIRTH, k, z0, z1, V3(0.0, cy, 0.0), V3(fade, 0.0, 0.0), zero)


def shift_warp(a: V3, b: V3, d: V3) -> Warp:
    """Return a move by `d` that ramps in along the segment `a` to `b`.

    Args:
        a: Where the ramp starts.
        b: Where the move is whole.
        d: The move.

    Returns:
        The warp. The segment must not be empty.
    """
    return Warp(SHIFT, 1.0, 0.0, 0.0, a, b, d)


def _ramp(z: Float64, a: Float64, b: Float64) -> Float64:
    # The integral of smoothstep(a, b, x) from minus infinity to z.
    var w = b - a
    var u = (z - a) / w
    var inside = w * (u * u * u - 0.5 * u * u * u * u)
    return 0.0 if z <= a else (w * 0.5 + (z - b) if z >= b else inside)


def apply_warp(w: Warp, p: V3) -> V3:
    """Return a point moved by one warp.

    Args:
        w: The warp.
        p: The point.

    Returns:
        The moved point.
    """
    if w.kind == SCALE:
        return p * w.k
    if w.kind == LEGS:
        var bw = w.a * 0.15
        var lift = max(p.y, 0.0) - _ramp(p.y, w.a - bw, w.a + bw)
        return V3(p.x, p.y + (w.k - 1.0) * lift, p.z)
    if w.kind == LENGTH:
        var bw = (w.b - w.a) * 0.12
        var zc = (w.a + w.b) * 0.5
        var t = _ramp(p.z, w.a - bw, w.a + bw) - _ramp(p.z, w.b - bw, w.b + bw)
        var tc = _ramp(zc, w.a - bw, w.a + bw) - _ramp(zc, w.b - bw, w.b + bw)
        return V3(p.x, p.y, p.z + (w.k - 1.0) * (t - tc))
    if w.kind == SCALE_ABOUT:
        var off = p - w.c
        var f = 1.0 + (w.k - 1.0) * (1.0 - smoothstep(w.a, w.b, length(off)))
        return w.c + off * f
    if w.kind == GIRTH:
        var fade = w.d.x
        var cy = w.c.y
        var band = smoothstep(w.a - fade, w.a + fade, p.z) * (
            1.0 - smoothstep(w.b - fade, w.b + fade, p.z)
        )
        var f = 1.0 + (w.k - 1.0) * band * smoothstep(cy * 0.35, cy * 0.7, p.y)
        return V3(p.x * f, cy + (p.y - cy) * f, p.z)
    # SHIFT: `c` to `d` is the ramp and `m` is the move.
    var ab = w.d - w.c
    var f = smoothstep(0.0, 1.0, dot(p - w.c, ab) / dot(ab, ab))
    return p + w.m * f


def check_warp(w: Warp) raises:
    """Refuse a warp that is not one of the six kinds, or is degenerate.

    Args:
        w: The warp.

    Raises:
        Error: If the kind is not valid, a fade is empty or reversed, or
            a shift's segment is empty.
    """
    if not w.kind.is_valid():
        raise Error("Warp kind must be from 0 to 5")
    if w.kind == SCALE_ABOUT and not w.b > w.a:
        raise Error("A scale-about warp must fade out over a positive width")
    if w.kind == LENGTH and not w.b > w.a:
        raise Error("A length warp's planes must be in order")
    if w.kind == GIRTH and not w.b > w.a:
        raise Error("A girth warp's planes must be in order")
    if w.kind == LEGS and not w.a > 0.0:
        raise Error("A legs warp's belly line must be above the ground")
    if w.kind == SHIFT and not length(w.d - w.c) > 0.0:
        raise Error("A shift warp's segment must not be empty")


struct Warps(Movable):
    """Warps applied in order."""

    var list: List[Warp]

    def __init__(out self):
        """Make an empty list. It moves nothing."""
        self.list = List[Warp]()

    def copy(self) -> Warps:
        """Return a copy of the list.

        Returns:
            The same warps, in the same order.
        """
        var out = Warps()
        out.list = self.list.copy()
        return out^

    def add(mut self, w: Warp) raises:
        """Append a warp.

        Args:
            w: The warp. It is applied after the earlier ones.

        Raises:
            Error: If `check_warp` refuses it.
        """
        check_warp(w)
        self.list.append(w)

    def apply(self, p: V3) -> V3:
        """Return a point moved by every warp in order.

        Args:
            p: The point.

        Returns:
            The moved point.
        """
        var q = p
        for w in self.list:
            q = apply_warp(w, q)
        return q

    def push(self, p: V3, d: V3) -> V3:
        """Return where a short direction at a point goes: the Jacobian
        applied to `d`, by finite differences.

        Args:
            p: The point.
            d: The direction.

        Returns:
            The warped direction, at the same scale.
        """
        var e = JACOBIAN_STEP
        return (self.apply(p + d * e) - self.apply(p)) * (1.0 / e)

    def jacobian(self, p: V3) -> Frame:
        """Return the warp's Jacobian at a point, by finite differences.

        Four warp evaluations give all three columns.

        Args:
            p: The point.

        Returns:
            The images of the unit x, y and z directions.
        """
        var e = JACOBIAN_STEP
        var q = self.apply(p)
        return Frame(
            (self.apply(p + V3(e, 0.0, 0.0)) - q) * (1.0 / e),
            (self.apply(p + V3(0.0, e, 0.0)) - q) * (1.0 / e),
            (self.apply(p + V3(0.0, 0.0, e)) - q) * (1.0 / e),
        )

    def scale_at(self, p: V3) -> Float64:
        """Return the warp's local isotropic scale.

        Args:
            p: The point.

        Returns:
            The cube root of the Jacobian's determinant there.
        """
        return _det_scale(self.jacobian(p))

    def warp_rig(self, rig: Rig) -> Rig:
        """Return the rig with every joint warped.

        Args:
            rig: The reference rig.

        Returns:
            The individual's rig.
        """
        var out = rig.copy()
        for i in range(len(out.joints)):
            out.joints[i] = self.apply(out.joints[i])
        return out^

    def warp_model(self, model: SdfModel) -> SdfModel:
        """Return the sculpt with every primitive warped.

        An ellipsoid's axes follow the Jacobian at its center and its
        radii stretch with them. A cone's ends move, and each radius
        scales with the local isotropic scale. A lens or a fin keeps its
        shape and scales with the isotropic scale at its center. Every blend
        radius scales with the isotropic scale at its center.

        Args:
            model: The reference sculpt.

        Returns:
            The individual's sculpt.
        """
        var out = SdfModel()
        out.tags = model.tags.copy()
        out.tag_at = model.tag_at.copy()
        out.outline = model.outline.copy()
        out.visual_only = model.visual_only
        for p in model.prims:
            out.prims.append(self._warp_primitive(p, out.outline))
        return out^

    def _warp_primitive(
        self, p: Primitive, mut outline: List[Float64]
    ) -> Primitive:
        var q = p
        var j = self.jacobian(p.c)
        var s = _det_scale(j)
        q.c = self.apply(p.c)
        # Blends scale with the body, as the solids do.
        q.k = p.k * s
        if p.kind == CONE:
            q.b = self.apply(p.b)
            q.r = V3(p.r.x * s, p.r.y * self.scale_at(p.b), 0.0)
            return q
        if p.kind == ELLIPSOID:
            var wx = _turn(j, p.ax)
            var wy = _turn(j, p.ay)
            var wz = _turn(j, p.az)
            var f = frame_zy(wz, wy)
            q.ax = f.x
            q.ay = f.y
            q.az = f.z
            q.r = V3(p.r.x * length(wx), p.r.y * length(wy), p.r.z * length(wz))
            q.b = q.c
            return q
        var f = frame_zy(_turn(j, p.az), _turn(j, p.ay))
        q.ax = f.x
        q.ay = f.y
        q.az = f.z
        q.b = q.c
        q.r = p.r * s
        if p.kind == LENS:
            q.lo = p.lo * s
            q.hi = p.hi * s
            return q
        for i in range(
            p.first * 2, (p.first + p.count) * 2
        ):  # pragma: no branch
            outline[i] = outline[i] * s
        return q


def _turn(j: Frame, d: V3) -> V3:
    return j.x * d.x + j.y * d.y + j.z * d.z


def _det_scale(j: Frame) -> Float64:
    return cbrt(abs(dot(j.x, cross(j.y, j.z))))
