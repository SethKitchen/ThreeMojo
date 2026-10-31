# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Facial hair: a beard or a mustache, as an implicit solid on the face.

A beard is drawn as its volume, as the scalp's hair is: a shell over the
skin, open at the mouth. Its style says where it grows and how deep:

| Style | Grows on | Depth |
|---|---|---|
| `CLEAN_SHAVEN` | nothing | |
| `MUSTACHE` | the upper lip, to the corners of the mouth | 4.5 mm |
| `GOATEE` | the upper lip, round the mouth and down the chin | 6 mm |
| `SHORT_BEARD` | the jaw, the chin, the cheeks and the upper lip | 4 mm |
| `FULL_BEARD` | the same, and a mass that hangs below the chin | 7 mm on the cheeks, 14 mm at the chin |
| `CHIN_STRAP` | a band 3 cm deep along the jaw, from sideburn to sideburn | 4 mm |
| `MUTTON_CHOPS` | the sideburns and the cheeks, the chin and the lip bare | 6 mm |
| `STUBBLE` | the zone of a short beard | 1.5 mm |
| `LONG_BEARD` | a full beard's zone, and a mass that falls from the chin to the chest | 7 mm on the cheeks, 14 mm at the chin |
| `FORKED_BEARD` | a full beard's zone, and two locks that fall from the chin and part | 7 mm on the cheeks, 14 mm at the chin |

The zones are authored in template centimeters round the mouth: the
lips part at 65 cm above the hip joint centers, the chin's point stands
at 62 cm, the nose's base at 67 cm, and the jaw is 6.5 cm wide on each
side. A beard's line runs from each corner of the mouth up across the
cheek to the sideburn, in front of the ear. A long beard falls in a
tapered lock 17 cm below the chin, forward over the chest; a forked
beard falls in two locks 12 cm long that part 5 cm at their tips. Its lower line runs under
the jaw, above the larynx. The head's frame maps the zone onto each
face, so a genome that widens the jaw or the mouth moves the beard with
it. Facial hair takes the scalp's hair color.

This is not a three.js port. See Extensions.

    var shape = BeardShape(dims, FULL_BEARD)
    var beard = beard_mesh(dims, FULL_BEARD, 28, workers)
"""

from std.math import atan2, max, min, pi, sqrt

from core.buffer_geometry import POSITION, BufferGeometry
from core.ordinal import ordinal_label, ordinal_valid, require_valid
from extensions.humanoid.skeleton.field import (
    DistanceField,
    sd_ellipsoid,
    smax,
    smin,
)
from extensions.humanoid.skeleton.head.frame import HeadMuscleDimensions
from extensions.humanoid.skeleton.head.skin.dimensions import HeadSkinField
from extensions.humanoid.skeleton.sculpt import Sculpt
from extensions.humanoid.skeleton.surface_nets import mesh_surface
from math.utils import clamp
from math.vector3 import Vector3
from units.si import DEGREE, Angle

comptime MOUTH_Y = Float32(65.0)
"""Where the lips part, in template centimeters above the hips."""
comptime MOUTH_Z = Float32(10.3)
"""How far in front of the hips the lips part, in template centimeters."""
comptime MOUTH_HALF_WIDTH = Float32(2.7)
"""Half the width of the bare oval round the lips, in template cm."""
comptime MOUTH_HALF_HEIGHT = Float32(0.95)
"""Half the height of the bare oval round the lips, in template cm."""
comptime NOSE_BASE_Y = Float32(67.1)
"""The height of the nose's base, where a mustache stops, in template cm."""
comptime HEAD_AXIS_Z = Float32(-1.0)
"""Where the head's vertical axis stands, front to back, in template cm.
A beard's lines run round it."""
comptime SIDEBURN_Y = Float32(71.5)
"""The height a beard's line meets the sideburn, in template cm."""
comptime EAR_TURN = Float32(95.0)
"""How far round from the front a beard reaches, in degrees: to the ear."""
comptime STRAP_BAND = Float32(3.0)
"""How far up from a beard's lower line a chin strap reaches, in template
cm."""
comptime CHOP_TURN = Float32(32.0)
"""How far round from the front mutton chops begin, in degrees."""
comptime BEARD_BURY = Float32(0.08)
"""How far under the skin a beard's inner face lies, in template cm."""
comptime BEARD_SOFT = Float32(0.35)
"""The blend of a beard's edges into the skin, in template cm."""


@fieldwise_init
struct Beard(Equatable, ImplicitlyCopyable, Writable):
    """Which facial hair a face grows."""

    var value: Int
    """Its index among the named values."""

    def is_valid(self) -> Bool:
        """Return whether this is a named style.

        Returns:
            True for `CLEAN_SHAVEN` through `FORKED_BEARD`.
        """
        return ordinal_valid(self.value, BEARD_COUNT - 1)

    def hangs(self) -> Bool:
        """Return whether the beard has a mass that hangs below the chin.

        Returns:
            True for a full, a long and a forked beard.
        """
        return self == FULL_BEARD or self == LONG_BEARD or self == FORKED_BEARD


comptime CLEAN_SHAVEN = Beard(0)
"""No facial hair."""
comptime MUSTACHE = Beard(1)
"""A mustache over the upper lip."""
comptime GOATEE = Beard(2)
"""A mustache, joined round the mouth to a beard on the chin."""
comptime SHORT_BEARD = Beard(3)
"""A close beard over the jaw, the chin, the cheeks and the upper lip."""
comptime FULL_BEARD = Beard(4)
"""A deep beard over the same, that hangs below the chin."""
comptime CHIN_STRAP = Beard(5)
"""A narrow band along the jaw, from sideburn to sideburn, and no
mustache."""
comptime MUTTON_CHOPS = Beard(6)
"""Sideburns grown down over the cheeks, the chin bare."""
comptime STUBBLE = Beard(7)
"""A day or two of growth over a short beard's zone."""
comptime LONG_BEARD = Beard(8)
"""A full beard that falls in a long tapered lock to the chest."""
comptime FORKED_BEARD = Beard(9)
"""A full beard that falls in two locks that part at their tips."""
comptime BEARD_COUNT = 10
"""How many styles there are."""


def _beard_names() -> List[String]:
    """Return the style names, in order."""
    return [
        "clean-shaven",
        "mustache",
        "goatee",
        "short beard",
        "full beard",
        "chin strap",
        "mutton chops",
        "stubble",
        "long beard",
        "forked beard",
    ]


def beard_label(beard: Beard) -> String:
    """Return the name of a style.

    Args:
        beard: A style, named or not.

    Returns:
        Its name, as `"goatee"`, or `"beard"` when it is not named.
    """
    return ordinal_label(beard.is_valid(), beard.value, _beard_names(), "beard")


def beard_named(name: String) raises -> Beard:
    """Return the style that `name` names.

    Args:
        name: A style's name, as `beard_label` gives it.

    Returns:
        The named style.

    Raises:
        Error: If `name` names no style.
    """
    var names = _beard_names()
    for k in range(len(names)):  # pragma: no branch
        if names[k] == name:
            return Beard(k)
    raise Error("No beard is named " + name)


def require_beard(beard: Beard) raises:
    """Refuse a style that is not named.

    Args:
        beard: The style.

    Raises:
        Error: If the style is not named.
    """
    require_valid(beard.is_valid(), "A beard must be a named style")


def _ramp(value: Float32, low: Float32, high: Float32) -> Float32:
    """Return where `value` lies from `low` to `high`, clamped to zero
    through one."""
    return clamp((value - low) / (high - low), 0, 1)


def _rounded(x: Float32, y: Float32, a: Float32, b: Float32) -> Float32:
    """Return how far a point lies outside a rounded box round the origin,
    in template cm: a superellipse of half width `a` and half height `b`.
    """
    var u = x / a
    var v = y / b
    var r = u * u * u * u + v * v * v * v
    # The fourth root keeps the value in centimeters near the edge.
    return (sqrt(sqrt(r)) - 1) * min(a, b)


def beard_top(turn: Angle) -> Float32:
    """Return the height of a full beard's upper line, round the head.

    Args:
        turn: How far round from the front, either way.

    Returns:
        The height in template cm: under the nose at the front, down to
        the corners of the mouth, then up across the cheek to the
        sideburn.
    """
    var a = abs(turn.to(DEGREE))
    if a <= 14:
        return NOSE_BASE_Y
    if a <= 24:
        return NOSE_BASE_Y + (Float32(64.4) - NOSE_BASE_Y) * _ramp(a, 14, 24)
    return Float32(64.4) + (SIDEBURN_Y - Float32(64.4)) * _ramp(a, 24, 80)


def beard_bottom(turn: Angle) -> Float32:
    """Return the height of a beard's lower line, round the head.

    Args:
        turn: How far round from the front, either way.

    Returns:
        The height in template cm: above the larynx at the front, under
        the jaw at the sides, and up to the ear's lobe behind the jaw.
    """
    var a = abs(turn.to(DEGREE))
    if a <= 50:
        return Float32(57.2) + Float32(0.8) * _ramp(a, 0, 50)
    return Float32(58.0) + Float32(10.0) * _ramp(a, 50, EAR_TURN)


struct BeardShape(Copyable, DistanceField, Movable):
    """The solid a face's facial hair is drawn as."""

    var beard: Beard
    var skin: HeadSkinField
    # The frame round the mouth: the mouth's point, and the inverse of
    # the map from template cm to meters there, row by row.
    var mouth: Vector3
    var inverse: List[Vector3]
    var cm: Float32
    var soft: Float32
    var bury: Float32
    # The deepest the hair stands off the skin: at the cheek and at the
    # chin, in meters.
    var side_depth: Float32
    var chin_depth: Float32
    # A full beard's mass under the chin.
    var mass_center: Vector3
    var mass_radii: Vector3
    # A long or a forked beard's locks below it.
    var locks: Sculpt
    var low: Vector3
    var high: Vector3

    def __init__(
        out self, dimensions: HeadMuscleDimensions, beard: Beard
    ) raises:
        """Shape one face's facial hair.

        Args:
            dimensions: Landmarks from `head_muscle_dimensions`.
            beard: A named style.

        Raises:
            Error: If `dimensions.validate` refuses the copy, or the style
                is not named.
        """
        self = BeardShape(dimensions, beard, HeadSkinField(dimensions))

    def __init__(
        out self,
        dimensions: HeadMuscleDimensions,
        beard: Beard,
        skin: HeadSkinField,
    ) raises:
        """Shape one face's facial hair on a skin already built for the
        same head.

        Args:
            dimensions: Landmarks from `head_muscle_dimensions`.
            beard: A named style.
            skin: The head's skin, from the same dimensions.

        Raises:
            Error: If `dimensions.validate` refuses the copy, or the style
                is not named.
        """
        require_beard(beard)
        dimensions.validate()
        var h = dimensions.head.copy()
        self.beard = beard
        self.skin = skin.copy()
        self.mouth = h.at(0, MOUTH_Y, MOUTH_Z)
        var ex = h.at(1, MOUTH_Y, MOUTH_Z) - self.mouth
        var ey = h.at(0, MOUTH_Y + 1, MOUTH_Z) - self.mouth
        var ez = h.at(0, MOUTH_Y, MOUTH_Z + 1) - self.mouth
        self.inverse = _inverted(ex, ey, ez)
        self.cm = h.cm(1)
        self.soft = h.cm(BEARD_SOFT)
        self.bury = h.cm(BEARD_BURY)
        var side = Float32(0.4)
        var chin = Float32(0.4)
        if beard == MUSTACHE:
            side = 0.45
            chin = 0.45
        elif beard == GOATEE:
            side = 0.6
            chin = 0.6
        elif beard.hangs():
            side = 0.7
            chin = 1.4
        elif beard == STUBBLE:
            side = 0.15
            chin = 0.15
        elif beard == MUTTON_CHOPS:
            side = 0.6
            chin = 0.6
        self.side_depth = h.cm(side)
        self.chin_depth = h.cm(chin)
        self.mass_center = h.at(0, 58.6, 7.6)
        self.mass_radii = Vector3(h.cm(5.0), h.cm(4.6), h.cm(4.2))
        self.locks = Sculpt(self.soft, self.soft)
        var lowest = Float32(56.0)
        if beard == LONG_BEARD:
            var run: List[Vector3] = [
                h.at(0, 58.6, 7.6),
                h.at(0, 54.0, 9.6),
                h.at(0, 48.5, 11.4),
                h.at(0, 42.5, 12.4),
            ]
            self.locks.chain(run, [h.cm(3.6), h.cm(3.0), h.cm(2.1), h.cm(0.7)])
            lowest = 41.0
        elif beard == FORKED_BEARD:
            for side_sign in [Float32(1), Float32(-1)]:  # pragma: no branch
                var run: List[Vector3] = [
                    h.at(side_sign * 0.9, 58.0, 8.2),
                    h.at(side_sign * 1.6, 53.0, 10.0),
                    h.at(side_sign * 2.6, 47.5, 11.2),
                ]
                self.locks.chain(run, [h.cm(2.4), h.cm(1.7), h.cm(0.6)])
            lowest = 46.0
        var reach = h.cm(2.0)
        var front = h.at(0, lowest, 13.5)
        var back = h.at(0, 72.5, -4.0)
        self.low = Vector3(
            self.mouth.x - h.cm(9.0) - reach, front.y - reach, back.z - reach
        )
        self.high = Vector3(
            self.mouth.x + h.cm(9.0) + reach, back.y + reach, front.z + reach
        )

    def template(self, point: Vector3) -> Vector3:
        """Return a point in template cm round the mouth.

        Args:
            point: A point in the pelvis frame, in meters.

        Returns:
            Its template coordinates: across, up from the hips, and in
            front of them.
        """
        var d = point - self.mouth
        return Vector3(
            self.inverse[0].dot(d),
            MOUTH_Y + self.inverse[1].dot(d),
            MOUTH_Z + self.inverse[2].dot(d),
        )

    def zone(self, t: Vector3) -> Float32:
        """Return how far a template point lies outside the zone the
        style grows on, in template cm: negative inside it.

        Args:
            t: A point in template cm, from `template`.

        Returns:
            A signed distance, near enough.
        """
        var x = abs(t.x)
        # The bare oval round the lips.
        var oval = (t.x / MOUTH_HALF_WIDTH) * (t.x / MOUTH_HALF_WIDTH) + (
            (t.y - MOUTH_Y) / MOUTH_HALF_HEIGHT
        ) * ((t.y - MOUTH_Y) / MOUTH_HALF_HEIGHT)
        var lips = (1 - oval) * MOUTH_HALF_HEIGHT
        # The upper lip, from the lips to the nose, arched so that it
        # droops at the corners of the mouth.
        var droop = Float32(0.5) * (x / Float32(3.1)) * (x / Float32(3.1))
        var mustache = _rounded(
            x,
            t.y + droop - (MOUTH_Y + NOSE_BASE_Y) * 0.5,
            Float32(3.1),
            (NOSE_BASE_Y - MOUTH_Y) * 0.5,
        )
        if self.beard == MUSTACHE:
            return max(mustache, lips)
        if self.beard == GOATEE:
            # The chin, from under the lower lip to under the jaw, joined
            # to the mustache round the corners of the mouth.
            var chin = _rounded(x, t.y - Float32(61.9), 2.5, 2.7)
            var ring = _rounded(x, t.y - MOUTH_Y, 3.2, 1.6)
            return max(min(min(mustache, chin), ring), lips)
        var turn = atan2(t.x, t.z - HEAD_AXIS_Z) * Float32(180 / pi)
        var reach = Float32(7) * (abs(turn) - EAR_TURN) * Float32(pi / 180)
        var around = Angle(turn, DEGREE)
        var beard = max(
            max(t.y - beard_top(around), beard_bottom(around) - t.y), reach
        )
        if self.beard == CHIN_STRAP:
            # Only a band along the jaw.
            beard = max(beard, t.y - (beard_bottom(around) + STRAP_BAND))
        elif self.beard == MUTTON_CHOPS:
            # Only the sides: the chin and the lip are bare.
            beard = max(beard, (CHOP_TURN - abs(turn)) * Float32(7 * pi / 180))
        return max(beard, lips)

    def depth(self, t: Vector3, zone: Float32) -> Float32:
        """Return how far the hair stands off the skin at a template
        point, in meters.

        Args:
            t: A point in template cm, from `template`.
            zone: Its `zone` value.

        Returns:
            The depth: deepest at the chin, for a full beard, and thinner
            toward the zone's edge.
        """
        var chin = _ramp(Float32(63.5) - t.y, 0, 3) * _ramp(
            Float32(4.5) - abs(t.x), 0, 3
        )
        # The hair thins toward the zone's edge, as a trimmed beard does.
        var edge = Float32(0.35) + Float32(0.65) * _ramp(-zone, 0, 0.8)
        return edge * (
            self.side_depth + (self.chin_depth - self.side_depth) * chin
        )

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the facial hair, in meters.

        Negative is inside.
        """
        if self.beard == CLEAN_SHAVEN:
            return self.cm
        var t = self.template(point)
        var zone = self.zone(t)
        var skin = self.skin.distance(point)
        var d = max(skin - self.depth(t, zone), -skin - self.bury)
        d = smax(d, zone * self.cm, self.soft)
        if self.beard.hangs():
            # The mass under the chin: outside the skin, inside its
            # ellipsoid, and below the mouth.
            var mass = max(
                sd_ellipsoid(point, self.mass_center, self.mass_radii),
                -skin - self.bury,
            )
            mass = smax(mass, (t.y - (MOUTH_Y - 1.4)) * self.cm, self.soft)
            d = smin(d, mass, self.soft)
            if len(self.locks.pieces) > 0:
                # The locks below it, outside the skin.
                var locks = max(self.locks.union(point), -skin - self.bury)
                d = smin(d, locks, self.soft)
        return d


def _inverted(a: Vector3, b: Vector3, c: Vector3) -> List[Vector3]:
    """Return the rows of the inverse of the matrix whose columns are
    `a`, `b` and `c`."""
    var r0 = b
    r0.cross(c)
    var r1 = c
    r1.cross(a)
    var r2 = a
    r2.cross(b)
    var det = a.dot(r0)
    var scale = 1 / det
    return [r0 * scale, r1 * scale, r2 * scale]


def beard_mesh(
    dimensions: HeadMuscleDimensions,
    beard: Beard,
    detail: Int = 28,
    workers: Int = 1,
) raises -> BufferGeometry:
    """Return the mesh of a face's facial hair, its outer face only.

    Its inner face lies under the skin and never shows, so it is left
    out, as the scalp hair's is in a game.

    Args:
        dimensions: Landmarks from `head_muscle_dimensions`.
        beard: A named style other than `CLEAN_SHAVEN`.
        detail: Cells along the beard's box, eight through sixty-four.
        workers: How many threads mesh it. One by default.

    Returns:
        A geometry with `position`, `normal` and `uv` attributes.

    Raises:
        Error: If the style is not named or is `CLEAN_SHAVEN`, if
            `dimensions.validate` refuses the copy, or if `detail` is out
            of range.
    """
    require_beard(beard)
    if beard == CLEAN_SHAVEN:
        raise Error("A clean-shaven face has no beard to mesh")
    var shape = BeardShape(dimensions, beard)
    var mesh = mesh_surface(
        shape, shape.low, shape.high, detail, "beard", workers
    )
    # Drop the inner face: the triangles whose corners all lie under the
    # skin. The mesher refuses a field with no surface, so the mesh has
    # vertices and triangles.
    ref placed = mesh.attribute_view(String(POSITION))
    var under = List[Bool](capacity=placed.count())
    for v in range(placed.count()):  # pragma: no branch
        under.append(shape.skin.distance(placed.vector3(v)) < -shape.bury * 0.5)
    var index = List[Int]()
    for t in range(mesh.triangle_count()):  # pragma: no branch
        var a = mesh.corner_index(t, 0)
        var b = mesh.corner_index(t, 1)
        var c = mesh.corner_index(t, 2)
        if under[a] and under[b] and under[c]:
            continue
        index.append(a)
        index.append(b)
        index.append(c)
    mesh.set_index(index^)
    return mesh^
