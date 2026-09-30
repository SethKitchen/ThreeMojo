# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A small clay kit for soft forms: ellipsoids and tapered capsules,
joined smoothly, with smooth hollows carved out of them.

A face is not a set of sections along one axis: the cheek is a mound,
the nose a ridge and a ball, the lips two rolls, the ear a rimmed
plate. `Sculpt` holds such pieces in one list. Its distance is the
smooth union of every piece, less the smooth union of every carving.
Each piece keeps a bounding sphere, so a point far from it skips the
piece.

    var clay = Sculpt(blend=0.004, carve=0.002)
    clay.ellipsoid(Vector3(0, 0, 0), Vector3(0.02, 0.01, 0.01))
    clay.capsule(a, b, 0.004, 0.003)
    clay.hollow_ellipsoid(c, Vector3(0.004, 0.002, 0.004))
    var d = clay.distance(point)
"""

from extensions.humanoid.skeleton.field import (
    DistanceField,
    sd_segment,
    smax,
    smin,
)
from math.vector3 import Vector3
from std.math import max, min, sqrt

# The piece kinds.
comptime _ELLIPSOID = 0
comptime _CAPSULE = 1


@fieldwise_init
struct Piece(Copyable, Movable):
    """One ellipsoid or tapered capsule.

    An ellipsoid is centered at `a` with semi-axes `radii` along the
    unit axes `u`, `v` and `w`. A capsule runs from `a` to `b`, with
    radius `ra` at `a` and `rb` at `b`.
    """

    var kind: Int
    var a: Vector3
    var b: Vector3
    var ra: Float32
    var rb: Float32
    var radii: Vector3
    var u: Vector3
    var v: Vector3
    var w: Vector3
    var center: Vector3
    var bound: Float32

    def distance(self, point: Vector3) -> Float32:
        """Return the signed distance to this piece, near enough.

        Args:
            point: The point, in meters.

        Returns:
            Negative inside, positive outside.
        """
        if self.kind == _CAPSULE:
            return sd_segment(point, self.a, self.b, self.ra, self.rb)
        var d = point - self.a
        var px = d.dot(self.u) / self.radii.x
        var py = d.dot(self.v) / self.radii.y
        var pz = d.dot(self.w) / self.radii.z
        var k0 = sqrt(px * px + py * py + pz * pz)
        var qx = px / self.radii.x
        var qy = py / self.radii.y
        var qz = pz / self.radii.z
        var k1 = sqrt(qx * qx + qy * qy + qz * qz)
        if k1 == 0:
            return -min(self.radii.x, min(self.radii.y, self.radii.z))
        return k0 * (k0 - 1) / k1


def _basis(forward: Vector3, up: Vector3) -> Tuple[Vector3, Vector3, Vector3]:
    """Return an orthonormal basis: x, y along `up`, z along `forward`."""
    var w = forward
    w.normalize()
    var v = up - w * up.dot(w)
    v.normalize()
    var u = Vector3(
        v.y * w.z - v.z * w.y, v.z * w.x - v.x * w.z, v.x * w.y - v.y * w.x
    )
    return (u, v, w)


struct Sculpt(Copyable, DistanceField, Movable):
    """Smoothly joined pieces less smoothly carved hollows."""

    var pieces: List[Piece]
    var hollows: List[Piece]
    var blend: Float32
    var carve: Float32
    var low: Vector3
    var high: Vector3

    def __init__(out self, blend: Float32, carve: Float32):
        """Start an empty sculpt.

        Args:
            blend: How wide the fillet is where two pieces meet, in
                meters.
            carve: How soft the edge of each hollow is, in meters.
        """
        self.pieces = List[Piece]()
        self.hollows = List[Piece]()
        self.blend = blend
        self.carve = carve
        self.low = Vector3(3.0e38, 3.0e38, 3.0e38)
        self.high = Vector3(-3.0e38, -3.0e38, -3.0e38)

    def _grow(mut self, center: Vector3, reach: Float32):
        """Grow the bounds to hold a sphere."""
        self.low = Vector3(
            min(self.low.x, center.x - reach),
            min(self.low.y, center.y - reach),
            min(self.low.z, center.z - reach),
        )
        self.high = Vector3(
            max(self.high.x, center.x + reach),
            max(self.high.y, center.y + reach),
            max(self.high.z, center.z + reach),
        )

    @staticmethod
    def _oriented(
        center: Vector3, radii: Vector3, forward: Vector3, up: Vector3
    ) -> Piece:
        """Return an ellipsoid piece turned to `forward` and `up`."""
        var axes = _basis(forward, up)
        var reach = max(radii.x, max(radii.y, radii.z))
        return Piece(
            _ELLIPSOID,
            center,
            center,
            0,
            0,
            radii,
            axes[0],
            axes[1],
            axes[2],
            center,
            reach,
        )

    @staticmethod
    def _capsule(a: Vector3, b: Vector3, ra: Float32, rb: Float32) -> Piece:
        """Return a tapered capsule piece."""
        var center = (a + b) * Float32(0.5)
        var reach = (b - a).length() * Float32(0.5) + max(ra, rb)
        return Piece(
            _CAPSULE,
            a,
            b,
            ra,
            rb,
            Vector3(ra, ra, ra),
            Vector3(1, 0, 0),
            Vector3(0, 1, 0),
            Vector3(0, 0, 1),
            center,
            reach,
        )

    def ellipsoid(
        mut self,
        center: Vector3,
        radii: Vector3,
        forward: Vector3 = Vector3(0, 0, 1),
        up: Vector3 = Vector3(0, 1, 0),
    ):
        """Add an ellipsoid.

        Args:
            center: Its center, in meters.
            radii: Its semi-axes across, up and forward, in meters.
            forward: Where its third axis points. Plus z by default.
            up: Roughly where its second axis points. Plus y by default.
        """
        var piece = Self._oriented(center, radii, forward, up)
        self._grow(center, piece.bound)
        self.pieces.append(piece^)

    def capsule(mut self, a: Vector3, b: Vector3, ra: Float32, rb: Float32):
        """Add a tapered capsule.

        Args:
            a: One end, in meters.
            b: The other end, in meters.
            ra: The radius at `a`, in meters.
            rb: The radius at `b`, in meters.
        """
        var piece = Self._capsule(a, b, ra, rb)
        self._grow(piece.center, piece.bound)
        self.pieces.append(piece^)

    def chain(mut self, points: List[Vector3], radii: List[Float32]):
        """Add tapered capsules through a run of points.

        Args:
            points: The run, two or more points, in meters.
            radii: One radius per point, in meters.
        """
        for index in range(len(points) - 1):  # pragma: no branch
            self.capsule(
                points[index], points[index + 1], radii[index], radii[index + 1]
            )

    def hollow_ellipsoid(
        mut self,
        center: Vector3,
        radii: Vector3,
        forward: Vector3 = Vector3(0, 0, 1),
        up: Vector3 = Vector3(0, 1, 0),
    ):
        """Carve an ellipsoid out of the pieces.

        Args:
            center: Its center, in meters.
            radii: Its semi-axes across, up and forward, in meters.
            forward: Where its third axis points. Plus z by default.
            up: Roughly where its second axis points. Plus y by default.
        """
        self.hollows.append(Self._oriented(center, radii, forward, up))

    def hollow_capsule(
        mut self, a: Vector3, b: Vector3, ra: Float32, rb: Float32
    ):
        """Carve a tapered capsule out of the pieces.

        Args:
            a: One end, in meters.
            b: The other end, in meters.
            ra: The radius at `a`, in meters.
            rb: The radius at `b`, in meters.
        """
        self.hollows.append(Self._capsule(a, b, ra, rb))

    def union(self, point: Vector3) -> Float32:
        """Return the distance to the smooth union of the pieces.

        A piece whose bounding sphere lies farther than the nearest
        piece found so far, and the blend, is skipped: it cannot change
        the result.

        Args:
            point: The point, in meters.

        Returns:
            The distance in meters, negative inside. A huge value when
            there are no pieces.
        """
        var d = Float32(3.0e38)
        for index in range(len(self.pieces)):  # pragma: no branch
            ref piece = self.pieces[index]
            var gap = (point - piece.center).length() - piece.bound
            if gap > d + self.blend:
                continue
            d = smin(d, piece.distance(point), self.blend)
        return d

    def carved(self, d: Float32, point: Vector3) -> Float32:
        """Return a distance with every hollow carved out of it.

        Args:
            d: The distance to some solid, in meters.
            point: The point it was taken at, in meters.

        Returns:
            The distance to that solid less the hollows.
        """
        var out = d
        for index in range(len(self.hollows)):  # pragma: no branch
            ref hollow = self.hollows[index]
            var gap = (point - hollow.center).length() - hollow.bound
            if gap > self.carve - out:
                continue
            out = smax(out, -hollow.distance(point), self.carve)
        return out

    def distance(self, point: Vector3) -> Float32:
        """Return the distance to the sculpted surface, in meters.

        Negative is inside. It is `union` with the hollows `carved`.
        """
        return self.carved(self.union(point), point)
