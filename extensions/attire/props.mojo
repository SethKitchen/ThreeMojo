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
from core.buffer_geometry import COLOR, BufferGeometry
from extensions.attire.mesh_ops import merge
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
