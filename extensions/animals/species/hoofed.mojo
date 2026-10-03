# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Helpers the hoofed species share: the horse, the cow, the deer, the
goat, the sheep and the pig.

Their heads are modeled along their own axis, pitched nose down in the
bind pose. `HeadFrame` is their `hl` and `hdir`. Their skeleton is the
standard quadruped with a hoof bone below each pastern.
"""

from extensions.sdf.ids import (
    BoneId,
    SurfacePart,
)
from extensions.animals.parts import BODY
from extensions.animals.kit import EyeSpec
from extensions.animals.rig import Rig, add_sided
from extensions.sdf.field import SdfModel
from extensions.sdf.vector import (
    V3,
    dot,
    normalize,
)
from std.math import asin, atan2, cos, pi, sin


@fieldwise_init
struct HeadFrame(ImplicitlyCopyable):
    """A head modeled along its own axis.

    Head-local `x` is lateral, `y` dorsal and `z` along the nasal line.
    `o` is the head's origin in reference space, and `hy` and `hz` are
    the local `y` and `z` axes there.
    """

    var o: V3
    var hy: V3
    var hz: V3

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

    def at(self, v: V3) -> V3:
        """Return a head-local point in reference space.

        The origin is added to the whole direction, `o + dir(v)`. The
        horse, the cow and the deer place their heads so.

        Args:
            v: The head-local point.

        Returns:
            The point.
        """
        return self.o + self.dir(v)

    def at_chained(self, v: V3) -> V3:
        """Return a head-local point in reference space, term by term.

        Each term is added to the origin in turn. The goat, the sheep
        and the pig place their heads so. The result can differ from
        `at` in the last bit.

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
    """Return a head frame pitched nose down.

    Args:
        origin: The head's origin in reference space.
        pitch_deg: How far the head's axis points below level, in degrees.

    Returns:
        The frame.
    """
    var a = pitch_deg * pi / 180.0
    return HeadFrame(origin, V3(0.0, cos(a), sin(a)), V3(0.0, -sin(a), cos(a)))


def pitched_head(poll: V3, pitch_deg: Float64, ahead: Float64) -> HeadFrame:
    """Return a head frame pitched nose down, its origin ahead of the poll.

    Args:
        poll: The top of the poll, in reference space.
        pitch_deg: How far the nasal line points below horizontal.
        ahead: How far the origin lies from the poll along the nasal line.

    Returns:
        The frame.
    """
    var f = head_frame(poll, pitch_deg)
    f.o = poll + f.hz * ahead
    return f


def head_ell(
    mut m: SdfModel,
    tag: String,
    bone: BoneId,
    hf: HeadFrame,
    c: V3,
    r: V3,
    k: Float64 = 0.02,
    axis_l: V3 = V3(0.0, 0.0, 1.0),
    up_l: V3 = V3(0.0, 1.0, 0.0),
    carve: Bool = False,
    part: SurfacePart = BODY,
) raises -> Int:
    """Add an ellipsoid in head-local coordinates: the sculpts' `hell`.

    Args:
        m: The sculpt.
        tag: What the primitive is.
        bone: The bone it rides.
        hf: The head frame.
        c: The head-local center.
        r: The radii: lateral, dorsal and along the head.
        k: The blend radius.
        axis_l: The head-local direction of the third radius.
        up_l: A head-local direction near the second radius.
        carve: Whether it cuts instead of adds.
        part: The surface it belongs to.

    Returns:
        Its index.

    Raises:
        Error: If `SdfModel.ell` refuses it.
    """
    return m.ell(
        tag,
        bone,
        hf.at(c),
        r,
        axis=normalize(hf.dir(axis_l)),
        up=normalize(hf.dir(up_l)),
        k=k,
        carve=carve,
        part=part,
    )


def eye_looking(
    hf: HeadFrame,
    c_local: V3,
    look: V3,
    r: Float64,
    back: Float64,
    lid: Float64,
    big_r: Float64,
    d: Float64,
    off: Float64,
    iris_z: Float64,
    iris_r: Float64,
) -> EyeSpec:
    """Return an eye at a head-local point, looking along a direction.

    Its roll is zero: set it with `aperture_tilt_along`.

    Args:
        hf: The head frame.
        c_local: The eye's head-local center.
        look: The view direction in reference space, a unit vector.
        r: The eyeball's radius.
        back: How far the ball sits behind its center.
        lid: The lid's thickness.
        big_r: The aperture arcs' radius.
        d: The arcs' offset.
        off: The aperture's offset along the eye's up axis.
        iris_z: The iris plane's depth.
        iris_r: The iris's radius.

    Returns:
        The eye.
    """
    return EyeSpec(
        hf.dir(c_local),
        r,
        back,
        atan2(look.x, look.z),
        asin(look.y),
        lid,
        big_r,
        d,
        off,
        0.0,
        iris_z,
        iris_r,
    )


def hoofed_bones(mut rig: Rig, tail_segs: Int, snout: Bool = False) raises:
    """Add the quadruped skeleton with a hoof bone below each pastern.

    `fpaw` and `hpaw` are the pasterns, fetlock to coffin joint, and
    `fhoof` and `hhoof` the hooves, coffin joint to toe. The rig's
    joints must include `fcoffin` and `hcoffin` on each side.

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


def dewclaw_balls(
    mut m: SdfModel, bone: BoneId, mc: V3, s: Float64, z: Float64, r: Float64
) raises:
    """Add two round dewclaws behind a fetlock.

    Args:
        m: The sculpt.
        bone: The bone they ride.
        mc: The fetlock joint.
        s: One for the left leg, minus one for the right.
        z: How far forward of the joint they sit. Negative is behind.
        r: Their radius.

    Raises:
        Error: If the sculpt refuses a primitive.
    """
    for k in [1.0, -1.0]:
        _ = m.sphere(
            "dewclaw",
            bone,
            mc + V3(0.009 * k * s, -0.006, z),
            r,
            k=0.004,
        )


def lens_distance(
    p: V3, c: V3, x: V3, y: V3, big_r: Float64, d: Float64
) -> Float64:
    """Return the distance to an eye's almond aperture, across its plane.

    The almond is two circles of radius `big_r` offset by `d` along `y`.
    The square roots are taken as powers of one half, as the horse, the
    cow and the deer painters were tuned with. They can differ from
    `almond_distance` in the last bit.

    Args:
        p: The point.
        c: The almond's center.
        x: Across the almond.
        y: Toward the upper lid.
        big_r: The circles' radius.
        d: Their offset.

    Returns:
        The signed distance, negative inside the almond.
    """
    var q = p - c
    var u = dot(q, x)
    var v = dot(q, y)
    var a = (u * u + (v + d) * (v + d)) ** 0.5 - big_r
    var b = (u * u + (v - d) * (v - d)) ** 0.5 - big_r
    return max(a, b)
