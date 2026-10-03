# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Helpers the species sculpts share: the eye and the head frame.

The eye functions are procedural-animals' `core/sdf/eyeSocket.js`.
"""

from extensions.sdf.ids import (
    BoneId,
    SurfacePart,
)
from extensions.animals.parts import BODY
from extensions.sdf.field import SdfModel
from extensions.sdf.vector import (
    Frame,
    V3,
    cross,
    frame_zy,
    normalize,
)
from std.math import cos, sin


@fieldwise_init
struct EyeSpec(ImplicitlyCopyable):
    """One species' eye, in head-local meters, for the left eye.

    `c` is the eye's center from the head origin and `r` the eyeball's
    radius. The ball sits `back` behind `c`. `yaw` turns the view axis
    out and `pitch` up, in radians. `lid` is the lid's thickness. The
    almond aperture is two circles of radius `big_r` offset by `d`, moved
    `off` along the eye's up axis and rolled by `tilt`. The iris disc is
    `iris_z` in front of the ball's center, with radius `iris_r`.
    """

    var c: V3
    var r: Float64
    var back: Float64
    var yaw: Float64
    var pitch: Float64
    var lid: Float64
    var big_r: Float64
    var d: Float64
    var off: Float64
    var tilt: Float64
    var iris_z: Float64
    var iris_r: Float64


@fieldwise_init
struct EyeFrame(ImplicitlyCopyable):
    """Where one eye is and how it looks: a center and three axes.

    `z` is the view axis, `y` the aperture's up and `x` across it.
    """

    var c: V3
    var x: V3
    var y: V3
    var z: V3

    def at(self, u: Float64, v: Float64, w: Float64) -> V3:
        """Return a point in the eye's frame.

        Args:
            u: Along `x`.
            v: Along `y`.
            w: Along `z`.

        Returns:
            The point.
        """
        return self.c + self.x * u + self.y * v + self.z * w


def eye_frame_of(e: EyeSpec, head_origin: V3, s: Float64) -> EyeFrame:
    """Return one eye's frame.

    Args:
        e: The eye.
        head_origin: The head's origin in the reference animal.
        s: One for the left eye, minus one for the right.

    Returns:
        The frame.
    """
    var c = V3(
        head_origin.x + e.c.x * s,
        head_origin.y + e.c.y,
        head_origin.z + e.c.z - e.back,
    )
    var z = V3(
        sin(e.yaw) * cos(e.pitch) * s, sin(e.pitch), cos(e.yaw) * cos(e.pitch)
    )
    var f = frame_zy(z, V3(0.0, 1.0, 0.0))
    var ph = s * e.tilt
    var x = f.x * cos(ph) + f.y * sin(ph)
    var y = f.x * -sin(ph) + f.y * cos(ph)
    return EyeFrame(c, x, y, f.z)


def sculpt_eye_socket(
    mut m: SdfModel,
    e: EyeSpec,
    head_origin: V3,
    s: Float64,
    bone: BoneId,
    orbit_r: V3 = V3(0.0, 0.0, 0.0),
    orbit_at: V3 = V3(0.0, 0.0, 0.0),
    orbit_k: Float64 = -1.0,
    z_max: Float64 = -1.0,
) raises -> EyeFrame:
    """Add an eye socket: an optional orbit hollow, the lid and the almond
    aperture cut into it.

    Args:
        m: The sculpt.
        e: The eye.
        head_origin: The head's origin.
        s: One for the left eye, minus one for the right.
        bone: The bone the socket rides, usually the head.
        orbit_r: The orbit hollow's radii. Zero radii add no hollow.
        orbit_at: The hollow's center in the aperture frame.
        orbit_k: The hollow's blend radius. Negative means `0.65 r`.
        z_max: The aperture's far face. Negative means `2 r`.

    Returns:
        The eye's frame.

    Raises:
        Error: If the sculpt refuses a primitive.
    """
    var ef = eye_frame_of(e, head_origin, s)
    if orbit_r.x > 0.0:
        _ = m.ell(
            "orbit",
            bone,
            ef.at(orbit_at.x * s, orbit_at.y, orbit_at.z),
            orbit_r,
            axis=ef.z,
            up=ef.y,
            k=orbit_k if orbit_k >= 0.0 else e.r * 0.65,
            carve=True,
        )
    _ = m.sphere("eyelid", bone, ef.c, e.r + e.lid, k=e.r * 0.4)
    _ = m.lens(
        "eyesocket",
        bone,
        ef.c + ef.y * e.off,
        ef.x,
        ef.y,
        ef.z,
        e.big_r,
        e.d,
        -e.r * 0.16,
        z_max if z_max >= 0.0 else e.r * 2.0,
        k=e.r * 0.18,
        carve=True,
    )
    return ef


def head_local(
    head_origin: V3,
    scale: Float64,
    muzzle_z0: Float64,
    muzzle: Float64,
    width: Float64,
    v: V3,
) -> V3:
    """Return a head-local point in reference space.

    This is the sculpts' `hlOf(m, w)`: the head is scaled by `scale`,
    its width by `width`, and the muzzle in front of `muzzle_z0` is
    stretched by `muzzle`.

    Args:
        head_origin: The head's origin in reference space.
        scale: The head's scale.
        muzzle_z0: Where the muzzle starts, head-local.
        muzzle: The muzzle's length factor.
        width: The head's width factor.
        v: The head-local point.

    Returns:
        The point in reference space.
    """
    var z = muzzle_z0 + (v.z - muzzle_z0) * muzzle if v.z > muzzle_z0 else v.z
    return V3(
        head_origin.x + v.x * width * scale,
        head_origin.y + v.y * scale,
        head_origin.z + scale * z,
    )
