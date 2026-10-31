# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Things a knight carries: a heater shield, and a sword in its scabbard.

A prop is a plain mesh that hangs from a socket. It does not bend, so
it is not skinned: it rides its socket's bone as a whole.

- `heater_shield` is the flat-topped shield of the thirteenth and
  fourteenth centuries. Its sides run straight down for nearly half its
  height and then curve in to a point. It is curved across, as a shield
  of boards bent round the arm is. Its face is painted per pale with two
  colors, in the `color` attribute, and it is seen from both sides.
- `heraldic_shield` is the same shield bearing arms: any dye pattern, cut
  crisply on its face, with a rim of metal round its edge.
- `sword_in_scabbard` gives the leather of a scabbard and its grip, and
  the steel of its cross-guard, pommel and chape, as two meshes. The
  sword hangs point down along minus y, its mouth at the origin. Both
  meshes are white in their `color` attribute, so a fabric's look tints
  them.

This is not a three.js port. See Extensions.

    var shield = heater_shield(Length(0.75, METER), dexter, sinister)
    var parts = sword_in_scabbard(Length(0.85, METER))
"""

from std.math import sqrt

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, POSITION, BufferGeometry
from extensions.attire.dye import charge_value, paint, split_dyes, with_channel
from extensions.attire.kinds import (
    PRIMARY_DYE,
    SECONDARY_DYE,
    TRIM_DYE,
    DyePattern,
    require_dye_pattern,
)
from extensions.attire.mesh_ops import cut, merge
from geometries.box import box
from geometries.lathe import lathe
from geometries.parametric import ParametricSurface, parametric
from math.vector2 import Vector2
from math.vector3 import Vector3
from render.framebuffer import Color
from render.srgb import srgb_to_linear
from units.si import Length, METER

comptime SHIELD_SHOULDER = Float32(0.42)
"""How far down a heater shield its sides run straight, as a share of its
height, and how wide it is for its height."""
comptime SHIELD_ASPECT = Float32(0.82)
"""How wide a heater shield is for its height."""
comptime SHIELD_BOW = Float32(0.12)
"""How far the middle of the shield stands forward of its edges, as a share
of its width."""
comptime SHIELD_CELLS = 24
"""Cells across and down a shield."""
comptime SHIELD_FESS = Float32(0.4)
"""How far down a shield its charges cross, as a share of its height."""
comptime SHIELD_CHARGE = Float32(0.2)
"""How wide a charge's band is, as a share of a shield's width."""
comptime SHIELD_RISE = Float32(0.18)
"""How far above the fess point a chevron's point lies, as a share of a
shield's width."""
comptime SHIELD_PALES = Float32(6)
"""How many pales, stripes or checks run across a shield's width."""
comptime SHIELD_RIM = Float32(0.035)
"""How wide a heraldic shield's rim is, as a share of its width."""


def shield_half_width(down: Float32) -> Float32:
    """Return a heater shield's half-width at a depth, as a share of its
    greatest half-width.

    Args:
        down: How far down, zero at the top through one at the point.

    Returns:
        One down to `SHIELD_SHOULDER`, then an ellipse's quarter down to
        zero at the point.
    """
    if down <= SHIELD_SHOULDER:
        return 1
    var t = (down - SHIELD_SHOULDER) / (1 - SHIELD_SHOULDER)
    return sqrt(max(Float32(0), 1 - t * t))


@fieldwise_init
struct HeaterShield(ImplicitlyCopyable, ParametricSurface):
    """A heater shield's face, as a surface of `u` across and `v` down."""

    var half: Float32
    """Its greatest half-width, in meters."""
    var tall: Float32
    """Its height, in meters."""
    var bow: Float32
    """How far its middle stands forward of its edges, in meters."""

    def point(self, u: Float32, v: Float32) -> Vector3:
        """Return the point of the face at `(u, v)`.

        Args:
            u: Across, zero at the left through one at the right.
            v: Down, zero at the top through one at the point.

        Returns:
            The point, in meters.
        """
        var across = (2 * u - 1) * shield_half_width(v)
        return Vector3(
            across * self.half,
            -v * self.tall,
            self.bow * (1 - across * across),
        )


def heater_shield(
    height: Length, dexter: Color, sinister: Color
) raises -> BufferGeometry:
    """Return a heater shield painted per pale.

    The shield faces plus z, its top edge at y = 0, its point at minus
    the height. The wearer's right side, dexter, is at minus x when the
    shield is seen from the front, as heraldry has it.

    Args:
        height: From the top edge to the point.
        dexter: The color of the bearer's right half, sRGB.
        sinister: The color of the bearer's left half, sRGB.

    Returns:
        An indexed mesh with positions, normals, texture coordinates and
        linear vertex colors.

    Raises:
        Error: If the height is not positive.
    """
    var tall = height.to(METER)
    if not (tall > 0):
        raise Error("A shield needs a positive height")
    var half = tall * SHIELD_ASPECT / 2
    var face = HeaterShield(half, tall, 2 * half * SHIELD_BOW)
    var mesh = parametric(face, SHIELD_CELLS, SHIELD_CELLS)
    ref uv = mesh.attribute_view("uv")
    var colors = List[Float32](capacity=3 * uv.count())
    for v in range(uv.count()):  # pragma: no branch
        var pick = dexter
        if uv.component(v, 0) > 0.5:
            pick = sinister
        colors.append(srgb_to_linear(Float32(pick.r) / 255))
        colors.append(srgb_to_linear(Float32(pick.g) / 255))
        colors.append(srgb_to_linear(Float32(pick.b) / 255))
    mesh.set_attribute(String(COLOR), BufferAttribute(colors^, 3))
    return mesh^


def heraldic_shield(
    height: Length,
    pattern: DyePattern,
    field: Color,
    charge: Color,
    rim: Color,
) raises -> BufferGeometry:
    """Return a heater shield that bears arms, with a rim of metal.

    The arms are the dye patterns, laid on the shield's face in its own
    lengths. The charges cross at the fess point, `SHIELD_FESS` of the
    height down from the top. Each band of a cross, a saltire, a chevron
    or a bend is `SHIELD_CHARGE` of the width wide. Quarters, stripes and
    checks cross at the fess point too. The shield is cut along each
    boundary, so each edge is crisp. A band `SHIELD_RIM` of the width
    wide runs round the edge, in the rim's color.

    The shield faces plus z, its top edge at y = 0, its point at minus
    the height. The bearer's right, dexter, is at minus x, seen from the
    front.

    Args:
        height: From the top edge to the point.
        pattern: A named pattern.
        field: The primary dye, sRGB.
        charge: The secondary dye, sRGB.
        rim: The rim's color, sRGB.

    Returns:
        An indexed mesh with positions, normals, texture coordinates, a
        `dye` attribute and linear vertex colors.

    Raises:
        Error: If the height is not positive or the pattern is not named.
    """
    require_dye_pattern(pattern)
    var tall = height.to(METER)
    if not (tall > 0):
        raise Error("A shield needs a positive height")
    var half = tall * SHIELD_ASPECT / 2
    var face = HeaterShield(half, tall, 2 * half * SHIELD_BOW)
    var mesh = parametric(face, SHIELD_CELLS, SHIELD_CELLS)
    # The rim: how far in from the shield's edge each point lies.
    var band = 2 * half * SHIELD_RIM
    ref placed = mesh.attribute_view(String(POSITION))
    var inside = List[Float32](capacity=placed.count())
    for v in range(placed.count()):  # pragma: no branch
        var p = placed.vector3(v)
        var down = min(Float32(1), max(Float32(0), -p.y / tall))
        var edge = half * shield_half_width(down) - abs(p.x)
        inside.append(min(edge, -p.y) - band)
    var body = cut(mesh, inside, 0)
    var outside = List[Float32](capacity=len(inside))
    for value in inside:  # pragma: no branch
        outside.append(-value)
    var edge = with_channel(cut(mesh, outside, 0), TRIM_DYE)
    ref inner = body.attribute_view(String(POSITION))
    var values = List[Float32](capacity=inner.count())
    var fess = -tall * SHIELD_FESS
    var width = 2 * half
    for v in range(inner.count()):  # pragma: no branch
        var p = inner.vector3(v)
        values.append(
            charge_value(
                pattern,
                -p.x,
                p.y - fess,
                p.y - fess,
                width * SHIELD_RISE,
                width * SHIELD_CHARGE / 2,
                width / SHIELD_PALES,
            )
        )
    var arms = merge(split_dyes(body, values, PRIMARY_DYE, SECONDARY_DYE), edge)
    paint(arms, [field, charge, rim, field])
    return arms^


def sword_in_scabbard(blade: Length) raises -> List[BufferGeometry]:
    """Return a sword in its scabbard: the leather, then the steel.

    Args:
        blade: The length of the scabbard, about the blade's.

    Returns:
        Two meshes. The first is the scabbard and the grip, the second
        the cross-guard, the pommel and the chape at the scabbard's tip.

    Raises:
        Error: If the length is not positive.
    """
    var long = blade.to(METER)
    if not (long > 0):
        raise Error("A scabbard needs a positive length")
    var m = METER
    var leather = lathe(
        [
            Vector2(0.0, -long),
            Vector2(0.012, -long + 0.02),
            Vector2(0.028, -0.02),
            Vector2(0.03, 0.0),
            Vector2(0.0, 0.0),
        ],
        16,
    )
    var grip = lathe(
        [
            Vector2(0.0, 0.03),
            Vector2(0.016, 0.03),
            Vector2(0.014, 0.13),
            Vector2(0.0, 0.13),
        ],
        12,
    )
    var guard = box(Length(0.2, m), Length(0.018, m), Length(0.028, m))
    var places = guard.clone_attribute("position")
    for v in range(places.count()):  # pragma: no branch
        places.set_component(v, 1, places.component(v, 1) + 0.02)
    guard.set_attribute("position", places^)
    var pommel = lathe(
        [
            Vector2(0.0, 0.13),
            Vector2(0.024, 0.145),
            Vector2(0.024, 0.165),
            Vector2(0.0, 0.18),
        ],
        12,
    )
    var chape = lathe(
        [
            Vector2(0.0, -long - 0.005),
            Vector2(0.016, -long + 0.03),
            Vector2(0.0, -long + 0.03),
        ],
        12,
    )
    var parts: List[BufferGeometry] = [
        merge(leather, grip),
        merge(merge(guard, pommel), chape),
    ]
    for k in range(2):  # pragma: no branch
        var count = parts[k].vertex_count()
        parts[k].set_attribute(
            String(COLOR),
            BufferAttribute(List[Float32](length=3 * count, fill=1), 3),
        )
    return parts^
