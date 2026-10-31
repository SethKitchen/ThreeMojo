# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Hats and helmets, each shaped round the head that wears it.

A garment made from the skin follows the face and the ears. A hat does
not: it stands on the head, over the hair. `hat_mesh` replaces a
`HATTED` garment's shell with the hat or helmet its headwear names:

1. The shell's vertices above the base of the neck are closed in their
   convex hull, as a hood's cowl is: see `extensions.attire.cowl`.
2. `HeadFrame` reads the hull: its middle, its top, and its width at
   each height and each way round. A hat's band lies `BAND_DROP` below
   the top of the head, just over the brows, and stands `HAIR_ROOM` out
   of the hull, so it sits over the hair.
3. Each hat is built round the band, in template meters scaled to the
   stature:

| Headwear | Shape |
|---|---|
| `GREAT_HELM` | the hull, cast out of its middle and stood 1.6 cm off it, down to the base of the neck; a flat top, a ridge down the front, and a slit for the eyes on each side of it |
| `HALF_HELM` | the same cast, 1.2 cm off the hull, cut level just over the brows, with a bar down the nose and a ridge over the crown |
| `HORNED_HELM` | a half helm with a horn on each side that curves out, up and forward |
| `WIZARD_HAT` | a brim 8.5 cm wide that droops at its edge, and a cone 30 cm tall whose tip bends back and down |
| `STRAW_HAT` | a brim 9.5 cm wide that turns up at its edge, and a round crown 2.5 cm over the head |
| `FEATHERED_CAP` | a crown that rises 4 cm over the head to a point over the brow, a brim that turns up behind, and a feather |
| `CROWN` | a band 4 cm deep that flares a little, with eight points, a stone at the foot of each and a larger one in front |
| `CIRCLET` | a band 1.2 cm deep that dips to a point over the brow, with a stone there |

Each hat has an outer face and an inner face a fabric's thickness in, so
it shows from below. `press_hair` lays a groom's strands under a hat:
each point over the band that stands further from the head's middle
than the hat's inside is drawn in to it, as a hat presses the hair. Its hat band, its rims and its ridges take the trim
dye: their `cover` attribute is under the trim's level. Its stones,
horns and feather take the accent dye: their `accent` attribute is one.
Every vertex rides the head.

This is not a three.js port. See Extensions.

    var hat = hat_mesh(whole, rig, garment.headwear, thickness)
"""

from std.math import cos, pi, sin, sqrt

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import POSITION, BufferGeometry
from extensions.attire.cowl import cowl_bottom, head_cowl
from extensions.attire.kinds import (
    CIRCLET,
    CROWN,
    FEATHERED_CAP,
    GREAT_HELM,
    HALF_HELM,
    HORNED_HELM,
    NO_HEADWEAR,
    STRAW_HAT,
    WIZARD_HAT,
    Headwear,
    require_headwear,
)
from extensions.attire.last import FootLast
from core.search import first_match
from extensions.attire.mesh_ops import ACCENT, MeshWriter, cut, merge
from extensions.attire.skirt import skirt_scale
from extensions.humanoid.rig.joints import HEAD, HumanoidRig
from extensions.humanoid.skeleton.head.hair.groom import HairGroom
from math.vector3 import Vector3

comptime HAIR_ROOM = Float32(0.012)
"""How far a hat's band stands out of the head's hull, in meters on the
template, so it sits over the hair."""
comptime BAND_DROP = Float32(0.1)
"""How far below the top of the head a hat's band lies, in meters on the
template: just over the brows."""
comptime EYE_DROP = Float32(0.122)
"""How far below the top of the head the eyes lie, in meters on the
template."""
comptime NOSE_DROP = Float32(0.165)
"""How far below the top of the head a helmet's nasal reaches, in meters
on the template."""
comptime SECTORS = 48
"""The steps round a hat."""
comptime RINGS = 24
"""The rings of the sphere a helmet is cast from, pole to pole."""
comptime TRIM = Float32(0.5)
"""The cover value of a hat's trim: under the trim's level, over the
hem's."""


struct HeadFrame(Copyable, Movable):
    """A head's hull, and where a hat sits on it."""

    var hull: FootLast
    """The convex hull of the hat's shell above the base of the neck."""
    var center: Vector3
    """The hull's middle."""
    var top: Float32
    """The height of the top of the hull."""
    var scale: Float32
    """The stature over the template's."""
    var bottom: Float32
    """The height of the base of the neck."""

    def __init__(out self, var hull: FootLast, rig: HumanoidRig):
        """Read a head's hull.

        Args:
            hull: The convex hull of the hat's shell above the neck.
            rig: The rig it was made on.
        """
        self.center = hull.center
        self.top = hull.top
        self.hull = hull^
        self.scale = skirt_scale(rig)
        self.bottom = cowl_bottom(rig)

    def band(self) -> Float32:
        """Return the height of a hat's band.

        Returns:
            `BAND_DROP` below the top of the head.
        """
        return self.top - BAND_DROP * self.scale

    def width(self, y: Float32, theta: Float32) -> Float32:
        """Return how far the hull reaches from its axis at a height.

        Args:
            y: A height inside the hull.
            theta: The way round: zero forward, a quarter turn to the
                wearer's left.

        Returns:
            The distance from the vertical through the middle to the hull.
        """
        return self.hull.cast_from(
            Vector3(self.center.x, y, self.center.z),
            Vector3(sin(theta), 0, cos(theta)),
        )

    def at(self, y: Float32, theta: Float32, reach: Float32) -> Vector3:
        """Return a point at a height, a way round and a reach from the axis.

        Args:
            y: The height.
            theta: The way round.
            reach: The distance from the vertical through the middle.

        Returns:
            The point.
        """
        return Vector3(
            self.center.x + reach * sin(theta),
            y,
            self.center.z + reach * cos(theta),
        )


struct _Hat(Movable):
    """A hat's mesh, written vertex by vertex, every vertex on the head."""

    var writer: MeshWriter
    var accent_at: Int

    def __init__(out self, like: BufferGeometry) raises:
        """Write the attributes of `like`, and an accent.

        Args:
            like: The shell whose attributes the hat takes.

        Raises:
            Error: If an attribute cannot be read.
        """
        var base = like.clone()
        base.set_attribute(
            String(ACCENT),
            BufferAttribute(
                List[Float32](length=like.vertex_count(), fill=0), 1
            ),
        )
        self.writer = MeshWriter(base)
        self.accent_at = first_match(self.writer.names, String(ACCENT))

    def vertex(mut self, p: Vector3, cover: Float32, accent: Bool) -> Int:
        """Write one vertex that rides the head.

        Args:
            p: Where it is.
            cover: Its cover value: one, or `TRIM` for the trim.
            accent: Whether it takes the accent dye.

        Returns:
            Its index.
        """
        var at = self.writer.add(p, cover, [HEAD.value, 0, 0, 0], [1, 0, 0, 0])
        if accent:
            self.writer.out[self.accent_at][at] = 1
        return at

    def sheet(
        mut self,
        rows: List[List[Vector3]],
        covers: List[List[Float32]],
        accent: Bool,
        inward: Bool,
    ):
        """Write rows of points round the axis as one closed band.

        Each row runs once round, from forward toward the wearer's left.
        The rows run up the band, or out of it.

        Args:
            rows: The rows, each of the same count.
            covers: The cover value of each point.
            accent: Whether the band takes the accent dye.
            inward: Whether it faces in, as a lining does, or out.
        """
        var first = List[Int]()
        for r in range(len(rows)):  # pragma: no branch
            first.append(self.vertex(rows[r][0], covers[r][0], accent))
            for k in range(1, len(rows[r])):  # pragma: no branch
                _ = self.vertex(rows[r][k], covers[r][k], accent)
        var count = len(rows[0])
        for r in range(len(rows) - 1):  # pragma: no branch
            for k in range(count):  # pragma: no branch
                var a = first[r] + k
                var b = first[r] + (k + 1) % count
                var c = first[r + 1] + k
                var d = first[r + 1] + (k + 1) % count
                if inward:
                    self.writer.quad(b, a, d, c)
                else:
                    self.writer.quad(a, b, c, d)

    def cap(mut self, row: List[Vector3], tip: Vector3, cover: Float32):
        """Close a row with a fan to one point, facing out and up.

        Args:
            row: The last row of a band, round the axis.
            tip: The point the fan closes to.
            cover: The cover value of the fan.
        """
        var first = self.vertex(row[0], cover, False)
        for k in range(1, len(row)):  # pragma: no branch
            _ = self.vertex(row[k], cover, False)
        var center = self.vertex(tip, cover, False)
        for k in range(len(row)):  # pragma: no branch
            self.writer.triangle(first + k, first + (k + 1) % len(row), center)

    def build(mut self) raises -> BufferGeometry:
        """Return the hat written.

        Returns:
            An indexed mesh with normals.

        Raises:
            Error: If an attribute is malformed.
        """
        return self.writer.build()


def _theta(k: Int) -> Float32:
    """Return the way round of step `k`."""
    return 2 * Float32(pi) * Float32(k) / Float32(SECTORS)


def _ring(frame: HeadFrame, y: Float32, beyond: Float32) -> List[Vector3]:
    """Return a ring round the head at a height, `out` past the hull.

    Args:
        frame: The head.
        y: The height the hull is read at, and the ring's height.
        beyond: How far past the hull the ring stands.
    """
    var ring = List[Vector3](capacity=SECTORS)
    for k in range(SECTORS):  # pragma: no branch
        var theta = _theta(k)
        ring.append(frame.at(y, theta, frame.width(y, theta) + beyond))
    return ring^


def _rows_cover(rows: Int, value: Float32) -> List[List[Float32]]:
    """Return the same cover value for every point of some rows."""
    var covers = List[List[Float32]]()
    for _ in range(rows):  # pragma: no branch
        covers.append(List[Float32](length=SECTORS, fill=value))
    return covers^


def _away(frame: HeadFrame, p: Vector3) -> Vector3:
    """Return the level unit direction from the axis out to a point."""
    var away = Vector3(p.x - frame.center.x, 0, p.z - frame.center.z)
    var length = away.length()
    if length < 1e-6:
        return Vector3(0, 0, 1)
    return away * (1 / length)


def _brim(
    mut hat: _Hat,
    frame: HeadFrame,
    band: List[Vector3],
    widths: List[Float32],
    lifts: List[Float32],
    wave: Float32,
    thickness: Float32,
):
    """Write a brim out from a band: its top and its underside.

    Args:
        hat: The hat.
        frame: The head.
        band: The ring the brim grows from.
        widths: How wide it is at each step round, in meters.
        lifts: How far its edge rises at each step round, in meters;
            below zero it droops.
        wave: How far its edge rises and falls round it, in meters.
        thickness: How far its underside lies under its top.
    """
    var steps = 6
    var top = List[List[Vector3]]()
    var under = List[List[Vector3]]()
    for step in range(steps + 1):  # pragma: no branch
        var t = Float32(step) / Float32(steps)
        var row = List[Vector3]()
        var low = List[Vector3]()
        for k in range(SECTORS):  # pragma: no branch
            var p = band[k]
            var rise = lifts[k] * t * t + wave * t * sin(3 * _theta(k) + 1)
            var q = p + _away(frame, p) * (widths[k] * t) + Vector3(0, rise, 0)
            row.append(q)
            low.append(q - Vector3(0, thickness, 0))
        top.append(row^)
        under.append(low^)
    var covers = _rows_cover(steps + 1, 1)
    # The edge of the brim takes the trim.
    covers[steps] = List[Float32](length=SECTORS, fill=TRIM)
    # Rows that run out from the axis face down as written, so the top
    # is written the other way round.
    hat.sheet(top, covers, False, True)
    hat.sheet(under, covers, False, False)


def _crown(
    mut hat: _Hat,
    frame: HeadFrame,
    band: List[Vector3],
    rise: Float32,
    lean: Vector3,
    taper: Float32,
    crumple: Float32,
    trim_to: Float32,
    thickness: Float32,
):
    """Write a crown that rises from a band to a point, and its lining.

    Args:
        hat: The hat.
        frame: The head.
        band: The ring it rises from.
        rise: How tall it is, in meters.
        lean: Where its tip lies from straight over the band's middle,
            in meters.
        taper: How it narrows: one narrows evenly to the tip; more keeps
            it wide longer, as a dome does.
        crumple: How far it folds in and out round it, as a share of its
            width.
        trim_to: Up to what share of its height it takes the trim, as a
            hat band.
        thickness: How far its lining lies inside it.
    """
    var steps = 14
    var middle = Vector3(frame.center.x, band[0].y, frame.center.z)
    var rows = List[List[Vector3]]()
    var inner = List[List[Vector3]]()
    var covers = List[List[Float32]]()
    for step in range(steps):  # pragma: no branch
        var t = Float32(step) / Float32(steps)
        # The axis bends: most of the lean comes near the tip.
        var axis = middle + Vector3(0, rise * t, 0) + lean * (t * t * t)
        var keep = 1 - t**taper
        var row = List[Vector3]()
        var lining = List[Vector3]()
        for k in range(SECTORS):  # pragma: no branch
            var fold = 1 + crumple * t * sin(5 * _theta(k) + 7 * t)
            var from_axis = Vector3(
                band[k].x - middle.x, 0, band[k].z - middle.z
            ) * (keep * fold)
            # The crown stands clear of the head and the hair under it.
            if axis.y < frame.top:
                var clear = (
                    frame.width(axis.y, _theta(k)) + HAIR_ROOM * frame.scale
                )
                var reach = from_axis.length()
                if reach < clear:
                    from_axis = from_axis * (clear / max(reach, Float32(1e-6)))
            row.append(axis + from_axis)
            var length = max(from_axis.length(), Float32(1e-6))
            var shrink = max(Float32(0), length - thickness) / length
            lining.append(axis + from_axis * shrink)
        rows.append(row^)
        inner.append(lining^)
        covers.append(
            List[Float32](length=SECTORS, fill=TRIM if t < trim_to else 1)
        )
    hat.sheet(rows, covers, False, False)
    hat.cap(rows[steps - 1], middle + Vector3(0, rise, 0) + lean, 1)
    hat.sheet(inner, covers, False, True)


def _gem(mut hat: _Hat, at: Vector3, outward: Vector3, size: Float32):
    """Write a stone: an eight-faced cut set out from a surface.

    Args:
        hat: The hat.
        at: Where it is set.
        outward: The unit direction out of the surface there.
        size: Its half width, in meters.
    """
    var side = Vector3(outward.z, 0, -outward.x)
    side.normalize()
    var up = Vector3(0, 1, 0)
    var corners: List[Vector3] = [
        at + outward * (size * 1.2),
        at + side * size,
        at + up * size,
        at - side * size,
        at - up * size,
        at - outward * (size * 0.3),
    ]
    var index = List[Int]()
    for p in corners:  # pragma: no branch
        index.append(hat.vertex(p, 1, True))
    for k in range(4):  # pragma: no branch
        var a = index[1 + k]
        var b = index[1 + (k + 1) % 4]
        hat.writer.triangle(index[0], a, b)
        hat.writer.triangle(index[5], b, a)


def _tube(
    mut hat: _Hat, spine: List[Vector3], radii: List[Float32], accent: Bool
):
    """Write a tube along a spine, closed to a point at its end.

    Args:
        hat: The hat.
        spine: Its middle line, from its root.
        radii: Its radius at each point.
        accent: Whether it takes the accent dye.
    """
    var sides = 12
    var first = List[Int]()
    for i in range(len(spine)):  # pragma: no branch
        var along = spine[min(i + 1, len(spine) - 1)] - spine[max(i - 1, 0)]
        along.normalize()
        var across = Vector3(0, 1, 0)
        across.cross(along)
        across.normalize()
        var other = along
        other.cross(across)
        first.append(-1)
        for s in range(sides):  # pragma: no branch
            var angle = 2 * Float32(pi) * Float32(s) / Float32(sides)
            var p = spine[i] + (across * cos(angle) + other * sin(angle)) * (
                radii[i]
            )
            var at = hat.vertex(p, 1, accent)
            if s == 0:
                first[i] = at
    for i in range(len(spine) - 1):  # pragma: no branch
        for s in range(sides):  # pragma: no branch
            hat.writer.quad(
                first[i] + s,
                first[i] + (s + 1) % sides,
                first[i + 1] + s,
                first[i + 1] + (s + 1) % sides,
            )
    var last = len(spine) - 1
    var tip = hat.vertex(
        spine[last] + (spine[last] - spine[last - 1]) * 0.5, 1, accent
    )
    for s in range(sides):  # pragma: no branch
        hat.writer.triangle(first[last] + s, first[last] + (s + 1) % sides, tip)


def _corner(ring: Int, sector: Int) -> Int:
    """Return the vertex of a cast sphere at a ring and a sector.

    A pole is one vertex. The sectors wrap round.
    """
    if ring == 0:
        return 0
    if ring == RINGS:
        return 1 + (RINGS - 1) * SECTORS
    return 1 + (ring - 1) * SECTORS + sector % SECTORS


def _helmet(
    mut hat: _Hat,
    frame: HeadFrame,
    headwear: Headwear,
    thickness: Float32,
) raises -> List[Float32]:
    """Write a helmet cast from the hull, and its lining.

    The sphere's pole looks up, so its rings run level round the head and
    a level cut along them is smooth.

    Args:
        hat: The hat, empty.
        frame: The head.
        headwear: `GREAT_HELM`, `HALF_HELM` or `HORNED_HELM`.
        thickness: How far the lining lies inside the helmet.

    Returns:
        One value per vertex written, at or above zero where the helmet
        is kept.

    Raises:
        Error: Never: the values are plain arithmetic.
    """
    var s = frame.scale
    var great = headwear == GREAT_HELM
    var stand = (Float32(0.016) if great else Float32(0.012)) * s
    var c = frame.center
    var band = frame.band()
    var eye = frame.top - EYE_DROP * s
    var cut_at = band - 0.012 * s
    var flat = frame.top + stand * 0.6
    var keep = List[Float32]()
    var lining = List[Vector3]()
    var linings = List[Float32]()
    for ring in range(RINGS + 1):  # pragma: no branch
        var sectors = SECTORS
        if ring == 0 or ring == RINGS:
            sectors = 1
        for sector in range(sectors):  # pragma: no branch
            var down = Float32(pi) * Float32(ring) / Float32(RINGS)
            var theta = _theta(sector)
            var d = Vector3(
                sin(down) * sin(theta), cos(down), sin(down) * cos(theta)
            )
            var p = c + d * (frame.hull.cast(d) + stand)
            var dx = abs(p.x - c.x)
            var front = p.z - c.z - 0.02 * s
            # A ridge runs over the crown, and down the front of a great
            # helm.
            var ridge = max(Float32(0), 1 - dx / (0.01 * s))
            if great:
                p.y = min(p.y, flat)
                if front < 0:
                    ridge = 0
            elif p.y < band:
                ridge = 0
            p = p + d * (0.004 * s * ridge)
            var value: Float32
            var cover = Float32(1)
            if great:
                # The slits: level, in front, beside the bar between them.
                var slit = min(
                    min(0.0065 * s - abs(p.y - eye), front),
                    min(0.075 * s - dx, dx - 0.008 * s),
                )
                value = min(p.y - frame.bottom - 0.004 * s, -slit)
                if (
                    (abs(p.y - eye) < 0.02 * s and front > 0)
                    or p.y < frame.bottom + 0.025 * s
                    or ridge > 0
                ):
                    cover = TRIM
            else:
                var nasal = min(
                    min(0.009 * s - dx, front),
                    p.y - (frame.top - NOSE_DROP * s),
                )
                value = max(p.y - cut_at, nasal)
                if p.y < cut_at + 0.018 * s or ridge > 0:
                    cover = TRIM
            keep.append(value)
            linings.append(cover)
            _ = hat.vertex(p, cover, False)
            lining.append(p - d * thickness)
    var count = len(lining)
    for k in range(count):  # pragma: no branch
        keep.append(keep[k])
        _ = hat.vertex(lining[k], linings[k], False)
    for ring in range(RINGS):  # pragma: no branch
        for sector in range(SECTORS):  # pragma: no branch
            var a = _corner(ring, sector)
            var b = _corner(ring, sector + 1)
            var c2 = _corner(ring + 1, sector)
            var d2 = _corner(ring + 1, sector + 1)
            if ring > 0:
                hat.writer.triangle(a, b, c2)
                hat.writer.triangle(count + a, count + c2, count + b)
            if ring < RINGS - 1:
                hat.writer.triangle(c2, b, d2)
                hat.writer.triangle(count + c2, count + d2, count + b)
    return keep^


def _horns(mut hat: _Hat, frame: HeadFrame):
    """Write a horn on each side of a helmet, out, up and forward.

    Args:
        hat: The hat.
        frame: The head.
    """
    var s = frame.scale
    var y = frame.band() + 0.035 * s
    for side in [Float32(1), Float32(-1)]:  # pragma: no branch
        var theta = side * Float32(pi) / 2
        var root = frame.at(y, theta, frame.width(y, theta) + 0.004 * s)
        var spine = List[Vector3]()
        var radii = List[Float32]()
        var steps = 10
        for i in range(steps + 1):  # pragma: no branch
            var t = Float32(i) / Float32(steps)
            spine.append(
                root
                + Vector3(
                    side * (0.12 * t - 0.02 * t * t * t),
                    0.02 * t + 0.11 * t * t,
                    0.05 * t - 0.03 * t * t,
                )
                * s
            )
            radii.append(s * (0.022 * (1 - t) ** 0.9 + 0.0015))
        _tube(hat, spine, radii, True)


def _feather(mut hat: _Hat, frame: HeadFrame, band: List[Vector3]):
    """Write a feather from a cap's band, back and up, both faces.

    Args:
        hat: The hat.
        frame: The head.
        band: The cap's band.
    """
    var s = frame.scale
    var k = SECTORS * 3 // 8
    var root = band[k] + _away(frame, band[k]) * (0.004 * s)
    var steps = 12
    var left = List[Int]()
    var right = List[Int]()
    var back_left = List[Int]()
    var back_right = List[Int]()
    for i in range(steps + 1):  # pragma: no branch
        var t = Float32(i) / Float32(steps)
        var p = root + Vector3(0.03 * t, 0.06 * t + 0.08 * t * t, -0.2 * t) * s
        var width = 0.022 * s * sin(Float32(pi) * (0.08 + 0.92 * t)) ** 0.7
        var across = Vector3(0, 1, 0.35)
        across.normalize()
        var a = p + across * width
        var b = p - across * width * 0.4
        left.append(hat.vertex(a, 1, True))
        right.append(hat.vertex(b, 1, True))
        back_left.append(hat.vertex(a, 1, True))
        back_right.append(hat.vertex(b, 1, True))
    for i in range(steps):  # pragma: no branch
        hat.writer.quad(left[i], right[i], left[i + 1], right[i + 1])
        hat.writer.quad(
            back_right[i], back_left[i], back_right[i + 1], back_left[i + 1]
        )


def _band_rows(
    frame: HeadFrame,
    lows: List[Float32],
    highs: List[Float32],
    rows: Int,
    flare: Float32,
    beyond: Float32,
) -> List[List[Vector3]]:
    """Return the rows of a band round the head, from its foot to its top.

    Args:
        frame: The head.
        lows: The height of its foot at each step round.
        highs: The height of its top at each step round.
        rows: How many rows, two or more.
        flare: How much wider it is at its top than at its foot, as a
            share of its reach.
        beyond: How far past the hull its foot stands.
    """
    var band = frame.band()
    var rows_out = List[List[Vector3]]()
    for r in range(rows):  # pragma: no branch
        var t = Float32(r) / Float32(rows - 1)
        var row = List[Vector3]()
        for k in range(SECTORS):  # pragma: no branch
            var theta = _theta(k)
            var y = lows[k] + (highs[k] - lows[k]) * t
            var reach = (frame.width(band, theta) + beyond) * (1 + flare * t)
            row.append(frame.at(y, theta, reach))
        rows_out.append(row^)
    return rows_out^


def _inset(
    frame: HeadFrame, rows: List[List[Vector3]], thickness: Float32
) -> List[List[Vector3]]:
    """Return rows moved in toward the axis by a thickness."""
    var inner = List[List[Vector3]]()
    for row in rows:  # pragma: no branch
        var moved = List[Vector3]()
        for p in row:  # pragma: no branch
            moved.append(p - _away(frame, p) * thickness)
        inner.append(moved^)
    return inner^


def _circlet(mut hat: _Hat, frame: HeadFrame, crown: Bool, thickness: Float32):
    """Write a crown or a circlet: a band, its lining, and its stones.

    Args:
        hat: The hat.
        frame: The head.
        crown: Whether it is a crown, with points, or a circlet.
        thickness: How far its lining lies inside it.
    """
    var s = frame.scale
    var band = frame.band()
    var lows = List[Float32]()
    var highs = List[Float32]()
    for k in range(SECTORS):  # pragma: no branch
        var theta = _theta(k)
        if crown:
            # Eight points, one over the brow.
            var phase = Float32(8) * theta / (2 * Float32(pi))
            phase -= Float32(Int(phase))
            var point = 1 - 2 * min(phase, 1 - phase)
            lows.append(band - 0.004 * s)
            highs.append(band + 0.036 * s + 0.035 * s * point**1.5)
        else:
            # A circlet dips to a point over the brow.
            var dip = 0.012 * s * max(Float32(0), cos(theta)) ** 6
            lows.append(band + 0.004 * s - dip)
            highs.append(band + 0.016 * s - dip)
    var rows = 6 if crown else 3
    var flare = Float32(0.12) if crown else Float32(0)
    var outer = _band_rows(frame, lows, highs, rows, flare, HAIR_ROOM * s)
    var covers = _rows_cover(rows, 1)
    covers[0] = List[Float32](length=SECTORS, fill=TRIM)
    hat.sheet(outer, covers, False, False)
    hat.sheet(_inset(frame, outer, thickness), covers, False, True)
    if crown:
        for k in range(8):  # pragma: no branch
            var at = outer[2][k * SECTORS // 8]
            var size = (Float32(0.0065) if k == 0 else Float32(0.0045)) * s
            _gem(
                hat, at + _away(frame, at) * (0.002 * s), _away(frame, at), size
            )
    else:
        var at = outer[1][0]
        _gem(
            hat,
            at + _away(frame, at) * (0.002 * s),
            _away(frame, at),
            0.006 * s,
        )


def head_frame(whole: BufferGeometry, rig: HumanoidRig) raises -> HeadFrame:
    """Return the head a hat is made for, from its shell.

    Args:
        whole: The hat's whole shell, cut at its hems, in the pelvis frame.
        rig: The rig it was made on.

    Returns:
        The head's hull and where a hat sits on it.

    Raises:
        Error: If the shell has too few points above the base of the neck
            to close a hull, the mesh has no positions or skin weights, or
            its points all lie in one plane.
    """
    var hulls = head_cowl(whole, rig)
    if len(hulls) == 0:
        raise Error("A hat needs a head under it")
    return HeadFrame(hulls.pop(0), rig)


def hat_mesh(
    whole: BufferGeometry,
    rig: HumanoidRig,
    headwear: Headwear,
    thickness: Float32,
) raises -> BufferGeometry:
    """Return the hat or helmet a garment is drawn as.

    Args:
        whole: The garment's whole shell, cut at its hems, in the pelvis
            frame. Its attributes are the hat's.
        rig: The rig it was made on.
        headwear: A named headwear kind, not `NO_HEADWEAR`.
        thickness: The fabric's thickness: how far each lining lies in.

    Returns:
        The hat, with an `accent` attribute: one on its stones, horns and
        feather. The shell as it is when it reaches too little of the head.

    Raises:
        Error: If the headwear is not named or is `NO_HEADWEAR`, or the
            mesh has no positions or skin weights.
    """
    require_headwear(headwear)
    if headwear == NO_HEADWEAR:
        raise Error("A hat needs a headwear kind")
    var hulls = head_cowl(whole, rig)
    if len(hulls) == 0:
        return whole.clone()
    var frame = HeadFrame(hulls.pop(0), rig)
    var s = frame.scale
    var hat = _Hat(whole)
    if (
        headwear == GREAT_HELM
        or headwear == HALF_HELM
        or headwear == HORNED_HELM
    ):
        var keep = _helmet(hat, frame, headwear, thickness)
        var shell = cut(hat.build(), keep, 0)
        if headwear != HORNED_HELM:
            return shell^
        var horns = _Hat(whole)
        _horns(horns, frame)
        return merge(shell, horns.build())
    if headwear == CROWN or headwear == CIRCLET:
        _circlet(hat, frame, headwear == CROWN, thickness)
        return hat.build()
    var band = _ring(frame, frame.band(), HAIR_ROOM * s)
    # How far the head rises over the band.
    var above = frame.top - frame.band()
    var widths = List[Float32]()
    var lifts = List[Float32]()
    for k in range(SECTORS):  # pragma: no branch
        var theta = _theta(k)
        if headwear == WIZARD_HAT:
            widths.append(0.085 * s)
            lifts.append(-0.018 * s)
        elif headwear == STRAW_HAT:
            widths.append(0.095 * s)
            lifts.append(0.012 * s)
        else:
            # A cap's brim is turned up behind and gone in front.
            var behind = (1 - cos(theta)) / 2
            widths.append(0.05 * s * behind)
            lifts.append(0.045 * s * behind)
    if headwear == WIZARD_HAT:
        _brim(hat, frame, band, widths, lifts, 0.006 * s, thickness)
        _crown(
            hat,
            frame,
            band,
            0.3 * s,
            Vector3(0, -0.05, -0.11) * s,
            1.25,
            0.035,
            0.1,
            thickness,
        )
    elif headwear == STRAW_HAT:
        _brim(hat, frame, band, widths, lifts, 0.004 * s, thickness)
        _crown(
            hat,
            frame,
            band,
            above + 0.025 * s,
            Vector3(0, 0, 0),
            3.5,
            0.01,
            0.18,
            thickness,
        )
    else:
        _brim(hat, frame, band, widths, lifts, 0, thickness)
        _crown(
            hat,
            frame,
            band,
            above + 0.04 * s,
            Vector3(0, 0, 0.06) * s,
            1.3,
            0.02,
            0.08,
            thickness,
        )
        _feather(hat, frame, band)
    return hat.build()


def press_hair(mut groom: HairGroom, frame: HeadFrame) -> Int:
    """Lay a groom's strands under a hat on a head.

    Each point higher than a centimeter under the hat's band that stands
    further from the hull's middle than the hull and three fifths of
    `HAIR_ROOM` is drawn in to that distance, along its line from the
    middle. The hair below the band falls as it did.

    Args:
        groom: The strands, in the frame the hull was made in.
        frame: The head the hat sits on.

    Returns:
        How many points were drawn in.
    """
    var s = frame.scale
    var floor = frame.band() - 0.01 * s
    var room = HAIR_ROOM * 0.6 * s
    var pressed = 0
    for k in range(len(groom.points)):
        var p = groom.points[k]
        if p.y < floor:
            continue
        var d = p - frame.center
        var distance = d.length()
        # Over the band a point lies above the middle, so it has a way.
        var way = d * (1 / max(distance, Float32(1e-6)))
        var limit = frame.hull.cast(way) + room
        if distance > limit:
            groom.points[k] = frame.center + way * limit
            pressed += 1
    return pressed
