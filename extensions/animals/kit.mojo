# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Helpers the species share: the eye, the head, the limbs, the coat's
soft masks and the re-seeded random streams.

The eye functions are procedural-animals' `core/sdf/eyeSocket.js`.
"""

from extensions.sdf.ids import BoneId
from extensions.animals.options import AnimalRandom
from extensions.sdf.distance import almond_distance
from extensions.sdf.field import SdfModel
from extensions.sdf.vector import (
    V3,
    dot,
    frame_zy,
)
from std.math import atan2, cos, exp, pi, sin, sqrt

comptime MASK32 = 0xFFFFFFFF


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


def aperture_tilt_along(e: EyeSpec, head_origin: V3, axis: V3) -> Float64:
    """Return the roll that lays the almond's long axis along a direction.

    This is procedural-animals' `apertureTiltAlong`. The long axis has no
    direction and the upper lid stays up, so the roll lies within a
    quarter turn of upright.

    Args:
        e: The eye. Its own `tilt` is ignored.
        head_origin: The head's origin.
        axis: The direction to follow, such as the head's axis.

    Returns:
        The roll, in radians.
    """
    var flat = e
    flat.tilt = 0.0
    var f = eye_frame_of(flat, head_origin, 1.0)
    var a = axis - f.z * dot(axis, f.z)
    var ph = atan2(dot(a, f.y), dot(a, f.x))
    if ph > pi / 2.0:
        ph -= pi
    elif ph < -pi / 2.0:
        ph += pi
    return ph


def aperture_local(e: EyeSpec, ef: EyeFrame, p: V3) -> V3:
    """Return a point in the frame of an eye's almond aperture.

    The aperture's center is `e.off` up the eye's `y` axis from its
    center.

    Args:
        e: The eye.
        ef: The eye's frame, from `eye_frame_of`.
        p: The point.

    Returns:
        The point across the aperture, up it, and along the view axis.
    """
    var d = p - (ef.c + ef.y * e.off)
    return V3(dot(d, ef.x), dot(d, ef.y), dot(d, ef.z))


def lid_distance(e: EyeSpec, ef: EyeFrame, p: V3) -> Float64:
    """Return the distance from a point to the rim of an eye's aperture.

    The distance is measured in the aperture's plane. The depth along
    the view axis is ignored.

    Args:
        e: The eye.
        ef: The eye's frame, from `eye_frame_of`.
        p: The point.

    Returns:
        The distance to the almond's rim. It is never negative.
    """
    var q = aperture_local(e, ef, p)
    return abs(almond_distance(q.x, q.y, e.big_r, e.d))


def is_front_limb(bone: String) -> Bool:
    """Return whether a bone is part of a foreleg.

    Args:
        bone: The bone's name.

    Returns:
        True for the scapula, humerus, radius, metacarpus, front paw or
        pastern, and front hoof.
    """
    return (
        bone.startswith("scapula")
        or bone.startswith("humerus")
        or bone.startswith("radius")
        or bone.startswith("metacarpus")
        or bone.startswith("fpaw")
        or bone.startswith("fhoof")
    )


def is_hind_limb(bone: String) -> Bool:
    """Return whether a bone is part of a hind leg.

    Args:
        bone: The bone's name.

    Returns:
        True for the femur, tibia, metatarsus, hind paw or pastern, and
        hind hoof.
    """
    return (
        bone.startswith("femur")
        or bone.startswith("tibia")
        or bone.startswith("metatarsus")
        or bone.startswith("hpaw")
        or bone.startswith("hhoof")
    )


def is_limb(bone: String) -> Bool:
    """Return whether a bone is part of a leg.

    Args:
        bone: The bone's name.

    Returns:
        True for a bone of a foreleg or of a hind leg.
    """
    return is_front_limb(bone) or is_hind_limb(bone)


def mirrored_blob(h: V3, c: V3, r: V3) -> Float64:
    """Return a soft Gaussian blob, mirrored across the midline.

    The coat painters use it as a mask: one at the blob's center, and
    falling off over its radii.

    Args:
        h: The point. Its `x` is folded to the left side.
        c: The blob's center on the left side.
        r: The blob's radii.

    Returns:
        The mask, from zero to one.
    """
    var dx = (abs(h.x) - c.x) / r.x
    var dy = (h.y - c.y) / r.y
    var dz = (h.z - c.z) / r.z
    return exp(-(dx * dx + dy * dy + dz * dz))


def mirrored_ell_bottom(h: V3, c: V3, r: V3) -> Float64:
    """Return the lowest point of an upright ellipsoid over a point.

    The ellipsoid is mirrored across the midline. The painters use it
    to find the rim of a lip.

    Args:
        h: The point. Its `x` is folded to the left side.
        c: The ellipsoid's center on the left side.
        r: The ellipsoid's radii.

    Returns:
        The height of the ellipsoid's underside over the point, or one
        when the ellipsoid does not reach over it.
    """
    var dx = (abs(h.x) - c.x) / r.x
    var dz = (h.z - c.z) / r.z
    var q = 1.0 - dx * dx - dz * dz
    return c.y - r.y * sqrt(q) if q > 0.0 else 1.0


def pick_weighted(mut r: AnimalRandom, weights: List[Float64]) -> Int:
    """Draw an index by weight, as procedural-animals' weighted `pick`.

    One draw is scaled by the weights' sum. The first entry that takes
    the remainder to zero or below wins.

    Args:
        r: The stream.
        weights: Each entry's weight. They need not sum to one.

    Returns:
        The index drawn. The last entry when rounding leaves a rest.
    """
    var total = 0.0
    for w in weights:
        total += w
    var x = r.next() * total
    for i in range(len(weights)):
        x -= weights[i]
        if x <= 0.0:
            return i
    return len(weights) - 1


def pick_cumulative(x: Float64, weights: List[Float64]) -> Int:
    """Return the entry whose share of a running sum holds a draw.

    Args:
        x: The draw, usually from zero to one.
        weights: Each entry's share.

    Returns:
        The first index whose running sum exceeds `x`. The last entry
        when `x` is past the sum.
    """
    var acc = 0.0
    for i in range(len(weights)):
        acc += weights[i]
        if x < acc:
            return i
    return len(weights) - 1


def imul32(a: Int, b: Int) -> Int:
    """Return the low 32 bits of a product, as JavaScript's `Math.imul`.

    Args:
        a: One factor. Only its low 32 bits count.
        b: The other factor. Only its low 32 bits count.

    Returns:
        The product's low 32 bits, as an unsigned number.
    """
    var p = UInt64(a & MASK32) * UInt64(b & MASK32)
    return Int(p & UInt64(MASK32))


def draw_u32(mut r: AnimalRandom) -> Int:
    """Draw one 32-bit integer: `Math.floor(R() * 4294967296)`.

    Args:
        r: The stream.

    Returns:
        The integer, from zero to `2^32 - 1`.
    """
    return Int(r.next() * 4294967296.0) & MASK32


def stream_of(seed: Int) -> AnimalRandom:
    """Return procedural-animals' `rng(seed)` for a 32-bit seed.

    Args:
        seed: The seed. Only its low 32 bits count.

    Returns:
        The stream.
    """
    return AnimalRandom(seed & MASK32, 1, 0)


def hashed_stream(seed: Int, add: Int, mul: Int, xor: Int) -> AnimalRandom:
    """Return the stream `rng(Math.imul(seed + add, mul) ^ xor)`.

    The species draw their morphs from such a stream, so consecutive
    seeds do not correlate.

    Args:
        seed: The individual's seed.
        add: What is added to the seed.
        mul: The 32-bit multiplier.
        xor: The 32-bit mask mixed in last.

    Returns:
        The stream.
    """
    return stream_of(imul32(seed + add, mul) ^ xor)
