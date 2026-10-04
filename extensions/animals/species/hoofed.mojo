# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Helpers the cloven-hoofed species share: the goat, the sheep and the pig.

A pitched head frame, the 32-bit integer mixing their re-seeded streams
use, the weighted pick of their breed tables, the aperture roll of
procedural-animals' `eyeSocket.js`, and the hoofed skeleton: the standard
quadruped with a hoof bone below each pastern.
"""

from extensions.sdf.ids import BoneId
from extensions.animals.kit import (
    EyeSpec,
    eye_frame_of,
)
from extensions.animals.options import AnimalRandom
from extensions.animals.rig import Rig, add_sided
from extensions.sdf.field import SdfModel
from extensions.sdf.vector import (
    V3,
    dot,
    length,
    normalize,
)
from std.math import atan2, cos, pi, sin

comptime MASK32 = 0xFFFFFFFF


@fieldwise_init
struct HeadFrame(ImplicitlyCopyable):
    """A head modeled along its own axis, pitched nose-down.

    Head-local `x` is lateral, `y` dorsal and `z` along the head toward
    the muzzle. `hy` and `hz` are the local `y` and `z` axes in the bind
    pose, and `o` is the origin.
    """

    var o: V3
    var hy: V3
    var hz: V3

    def at(self, v: V3) -> V3:
        """Return a head-local point in reference space.

        Args:
            v: The head-local point.

        Returns:
            The point.
        """
        return V3(
            self.o.x + v.x,
            self.o.y + v.y * self.hy.y + v.z * self.hz.y,
            self.o.z + v.y * self.hy.z + v.z * self.hz.z,
        )

    def dir(self, v: V3) -> V3:
        """Return a head-local direction in reference space.

        Args:
            v: The head-local direction.

        Returns:
            The direction, not normalized.
        """
        return V3(
            v.x,
            v.y * self.hy.y + v.z * self.hz.y,
            v.y * self.hy.z + v.z * self.hz.z,
        )

    def local(self, p: V3) -> V3:
        """Return a reference-space point in head-local coordinates.

        Args:
            p: The point.

        Returns:
            The head-local point.
        """
        var d = p - self.o
        return V3(d.x, dot(d, self.hy), dot(d, self.hz))


def head_frame(origin: V3, pitch_deg: Float64) -> HeadFrame:
    """Return a head frame pitched nose-down.

    Args:
        origin: The head's origin in reference space.
        pitch_deg: How far the head's axis points below level, in degrees.

    Returns:
        The frame.
    """
    var a = pitch_deg * pi / 180.0
    return HeadFrame(origin, V3(0.0, cos(a), sin(a)), V3(0.0, -sin(a), cos(a)))


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


def pick_weighted(mut r: AnimalRandom, weights: List[Float64]) -> Int:
    """Draw from a weighted table as the hoofed species' `pick` does.

    One draw is scaled by the weights' sum; the first entry that takes
    the remainder to zero or below wins.

    Args:
        r: The stream.
        weights: Each entry's weight. They need not sum to one.

    Returns:
        The index picked. The last entry when rounding leaves a rest.
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


def aperture_tilt_along(e: EyeSpec, head_origin: V3, axis: V3) -> Float64:
    """Return the roll that lays the eye's almond along a direction.

    This is procedural-animals' `apertureTiltAlong`: the long axis has no
    direction, so the roll is the one within 90 degrees of upright.

    Args:
        e: The eye. Its own `tilt` is ignored.
        head_origin: The head's origin.
        axis: The direction to follow, such as the head's axis.

    Returns:
        The roll, in radians.
    """
    var flat = EyeSpec(
        e.c,
        e.r,
        e.back,
        e.yaw,
        e.pitch,
        e.lid,
        e.big_r,
        e.d,
        e.off,
        0.0,
        e.iris_z,
        e.iris_r,
    )
    var f = eye_frame_of(flat, head_origin, 1.0)
    var k = dot(axis, f.z)
    var a = axis - f.z * k
    var ph = atan2(dot(a, f.y), dot(a, f.x))
    if ph > pi / 2.0:
        ph -= pi
    elif ph < -pi / 2.0:
        ph += pi
    return ph


def hoofed_bones(mut rig: Rig, tail_segs: Int, snout: Bool = False) raises:
    """Add the hoofed quadruped's skeleton.

    It is the standard quadruped with the pastern ending at the coffin
    joint, `fpaw` from `mcp` to `fcoffin`, and a hoof bone below it,
    `fhoof` from `fcoffin` to `ftoe`. The hind leg is the same with
    `hpaw`, `hcoffin`, `hhoof` and `htoe`.

    Args:
        rig: The rig, with its joints placed and mirrored.
        tail_segs: How many tail bones, `tail0` onward.
        snout: Whether to add a `snout` bone from `snoutBase` to `nose`.

    Raises:
        Error: If a joint is missing.
    """
    _ = rig.add_bone("pelvis", "lumbosacral", "tailBase", "")
    _ = rig.add_bone("spine1", "lumbosacral", "lumbarMid", "pelvis")
    _ = rig.add_bone("spine2", "lumbarMid", "thoraxRear", "spine1")
    _ = rig.add_bone("spine3", "thoraxRear", "chestMid", "spine2")
    _ = rig.add_bone("chest", "chestMid", "neckBase", "spine3")
    _ = rig.add_bone("neck1", "neckBase", "neckMid", "chest")
    _ = rig.add_bone("neck2", "neckMid", "occiput", "neck1")
    _ = rig.add_bone("head", "occiput", "nose", "neck2")
    _ = rig.add_bone("jaw", "jawHinge", "jawTip", "head")
    add_sided(rig, "ear{S}", "earBase{S}", "earTip{S}", "head")
    add_sided(rig, "scapula{S}", "scapTop{S}", "shoulder{S}", "chest")
    add_sided(rig, "humerus{S}", "shoulder{S}", "elbow{S}", "scapula{S}")
    add_sided(rig, "radius{S}", "elbow{S}", "wrist{S}", "humerus{S}")
    add_sided(rig, "metacarpus{S}", "wrist{S}", "mcp{S}", "radius{S}")
    add_sided(rig, "fpaw{S}", "mcp{S}", "fcoffin{S}", "metacarpus{S}")
    add_sided(rig, "femur{S}", "hip{S}", "knee{S}", "pelvis")
    add_sided(rig, "tibia{S}", "knee{S}", "hock{S}", "femur{S}")
    add_sided(rig, "metatarsus{S}", "hock{S}", "mtp{S}", "tibia{S}")
    add_sided(rig, "hpaw{S}", "mtp{S}", "hcoffin{S}", "metatarsus{S}")
    for i in range(tail_segs):
        var parent = String("pelvis") if i == 0 else "tail" + String(i - 1)
        _ = rig.add_bone(
            "tail" + String(i),
            "tail" + String(i),
            "tail" + String(i + 1),
            parent,
        )
    if snout:
        _ = rig.add_bone("snout", "snoutBase", "nose", "head")
    add_sided(rig, "fhoof{S}", "fcoffin{S}", "ftoe{S}", "fpaw{S}")
    add_sided(rig, "hhoof{S}", "hcoffin{S}", "htoe{S}", "hpaw{S}")


def limb_bone(bone: String) -> Bool:
    """Return True for a bone of a hoofed leg.

    Args:
        bone: The bone's name.

    Returns:
        Whether it is a scapula, a leg bone, a pastern or a hoof.
    """
    return (
        bone.startswith("scapula")
        or bone.startswith("humerus")
        or bone.startswith("radius")
        or bone.startswith("metacarpus")
        or bone.startswith("fpaw")
        or bone.startswith("fhoof")
        or bone.startswith("femur")
        or bone.startswith("tibia")
        or bone.startswith("metatarsus")
        or bone.startswith("hpaw")
        or bone.startswith("hhoof")
    )


def front_bone(bone: String) -> Bool:
    """Return True for a bone of a foreleg.

    Args:
        bone: The bone's name.

    Returns:
        Whether it is a scapula, humerus, radius, metacarpus, front
        pastern or front hoof.
    """
    return (
        bone.startswith("scapula")
        or bone.startswith("humerus")
        or bone.startswith("radius")
        or bone.startswith("metacarpus")
        or bone.startswith("fpaw")
        or bone.startswith("fhoof")
    )


def unit_or(v: V3, fallback: V3) -> V3:
    """Return a direction normalized, or a fallback when it is zero.

    Args:
        v: The direction.
        fallback: What to return for a zero vector.

    Returns:
        The unit direction.
    """
    var l2 = dot(v, v)
    return normalize(v) if l2 > 1e-18 else fallback


def cone_or_ball(
    mut m: SdfModel,
    tag: String,
    bone: BoneId,
    a: V3,
    b: V3,
    ra: Float64,
    rb: Float64,
    k: Float64,
    thin: Bool = False,
) raises -> Int:
    """Add a round cone, or its bigger ball when that ball holds the other.

    procedural-animals' round cone accepts ends whose balls nest; its
    shape is then the bigger ball. `SdfModel.cone` refuses them.

    Args:
        m: The sculpt.
        tag: What the primitive is.
        bone: The bone it rides.
        a: One end.
        b: The other end.
        ra: The radius at `a`.
        rb: The radius at `b`.
        k: The blend radius.
        thin: Whether coarse meshes must inflate it to stay visible.

    Returns:
        Its index.

    Raises:
        Error: If the sculpt refuses the primitive.
    """
    var nested = abs(ra - rb) >= length(b - a)
    if nested:
        var c = a if ra >= rb else b
        return m.sphere(tag, bone, c, max(ra, rb), k=k, thin=thin)
    return m.cone(tag, bone, a, b, ra, rb, k=k, thin=thin)
