# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The domestic dog, Canis familiaris: procedural-animals' `species/dog/`.

A digitigrade trotter in three variants on one canid rig: a medium
shepherd type, a Labrador-type retriever and a small Jack Russell-type
terrier. The reference adult is a shepherd 0.60 m at the withers. The
variants differ in size, topline, hind angulation, head, ears, tail and
coat. Each variant draws its own coat colors from a hashed stream.
"""

from extensions.animals.coat import (
    FUR,
    KERATIN,
    NOSE,
    SKIN,
    WET,
    CoatSample,
    EyeLook,
    Paint,
    Palette,
    grizzle,
    mix3,
    palette_of,
    srgb,
)
from extensions.sdf.ids import BoneId
from extensions.animals.parts import (
    JAW,
    TONGUE,
)
from extensions.sdf.sculpt import ell_y
from extensions.animals.kit import (
    EyeSpec,
    eye_frame_of,
    head_local,
    is_limb,
    mirrored_blob,
    hashed_stream,
    pick_cumulative,
    mirrored_ell_bottom,
)
from extensions.animals.noise import fbm3, vnoise3
from extensions.animals.options import AnimalOptions, AnimalRandom
from extensions.animals.rig import Rig, quadruped_bones, tail_chain
from extensions.sdf.field import SdfModel
from extensions.animals.traits import Traits, pick_age, pick_sex, pick_variant
from extensions.sdf.vector import (
    V3,
    clamp,
    cross,
    dot,
    length,
    lerp,
    mix,
    normalize,
    smoothstep,
    on_side,
)
from extensions.animals.warp import (
    girth_warp,
    length_warp,
    legs_warp,
    scale_about_warp,
)
from std.math import cos, pi, pow, sin, sqrt

comptime TAIL_SEGS = 8
# The head's origin, mid cranium between the eyes and the ears.
comptime HEAD_O = V3(0.0, 0.622, 0.562)
# The head-local scale: landmarks are for a 0.25 m skull.
comptime HS = 1.0
# Where the muzzle starts, head-local. Muzzle length acts ahead of it.
comptime MUZZLE_Z0 = 0.04
# The finest cell, at the `HERO` tier: the jaw's cell in the original.
comptime CELL = 0.0021

# The variants, in procedural-animals' order.
comptime SHEPHERD = 0
comptime RETRIEVER = 1
comptime TERRIER = 2

# The ear types.
comptime PRICK = 0
comptime DROP = 1
comptime BUTTON = 2

# The coat colors, as `color` indices within each variant's table.
# Shepherd: black and tan, sable, black.
comptime BLACK_TAN = 0
comptime SABLE = 1
comptime SHEP_BLACK = 2
# Retriever: yellow, black, chocolate.
comptime YELLOW = 0
comptime LAB_BLACK = 1
comptime CHOCOLATE = 2
# Terrier: tricolor, tan, white.
comptime TRICOLOR = 0
comptime TAN = 1
comptime WHITE = 2


def dog_variant_names() -> List[String]:
    """Return the dog's variants.

    Returns:
        Shepherd, retriever and terrier.
    """
    return [String("shepherd"), "retriever", "terrier"]


def _colors(variant: Int) -> List[Float64]:
    if variant == RETRIEVER:
        return [0.45, 0.4, 0.15]
    if variant == TERRIER:
        return [0.45, 0.4, 0.15]
    return [0.68, 0.27, 0.05]


def dog_traits(mut r: AnimalRandom, options: AnimalOptions) raises -> Traits:
    """Draw one dog: procedural-animals' `variation`.

    The variant is the requested one, a shepherd by default. The coat
    color within the variant comes from its own hashed stream. Males are
    larger, with a broader head and a heavier neck and ruff. Puppies are
    about half size, with a big domed head, a short muzzle, big paws,
    short legs and soft button ears.

    Args:
        r: The individual's stream.
        options: The caller's sex, age and variant.

    Returns:
        The traits.

    Raises:
        Error: If the requested variant is not one of the three.
    """
    # Without a requested variant the dog is a shepherd: no draw picks it.
    var weights: List[Float64] = [1.0, 0.0, 0.0]
    var variant = pick_variant(max(options.variant.value, 0), weights, 0.0)
    _ = r.next()
    var sex = pick_sex(options.sex, r)
    var age = pick_age(options.age)
    var t = Traits(sex, age, variant)
    var juv = t.juvenile()
    var male = t.male()
    var m = hashed_stream(options.seed, 0x2B7E1516, 0x9E3779B1, 0x68E31DA4)
    for _ in range(3):  # pragma: no branch
        _ = m.next()
    var color = pick_cumulative(m.next(), _colors(variant))
    t.set("color", Float64(color))
    var shep = variant == SHEPHERD
    var ret = variant == RETRIEVER
    var ter = variant == TERRIER
    var base = (1.035 if male else 0.96) if shep else (
        (0.95 if male else 0.915) if ret else 0.46 * (1.02 if male else 0.98)
    )
    var size = (
        base
        * (1.0 + (0.06 if ter else 0.03) * r.g())
        * ((0.6 if ter else 0.5) if juv > 0.0 else 1.0)
    )
    var legs = (
        1.0
        + 0.03 * r.g()
        - 0.16 * juv
        + (-0.04 if ret else (0.1 if ter else 0.0))
    )
    var head = (
        (1.03 if male else 0.985)
        * (1.0 + 0.02 * r.g())
        * (1.15 if ret else (1.12 if ter else 1.0))
        * (1.3 if juv > 0.0 else 1.0)
    )
    var ear_type = DROP if ret else (
        BUTTON if ter else (BUTTON if juv > 0.0 else PRICK)
    )
    var tail_k = (1.0 + 0.05 * r.g()) * (0.7 if juv > 0.0 else 1.0)
    if ter:
        var docked = m.next() < 0.35
        tail_k *= 0.62 if docked else 0.9 + 0.1 * r.g()
    t.warps.add(legs_warp(legs, 0.36))
    t.warps.add(
        length_warp(
            1.0
            + 0.03 * r.g()
            - 0.05 * juv
            + (-0.09 if ret else (-0.03 if ter else 0.0)),
            -0.26,
            0.3,
        )
    )
    t.warps.add(scale_about_warp(HEAD_O, head, 0.075, 0.19))
    if not shep:
        # A shorter, thicker-looking neck: the head sits closer over the
        # forechest.
        t.warps.add(length_warp(0.78, 0.3, 0.44))
    if ret:
        t.warps.add(
            girth_warp(
                (1.1 if male else 1.07) * (1.0 + 0.03 * r.g()),
                0.42,
                -0.3,
                0.42,
                0.1,
            )
        )
    if ter:
        t.warps.add(
            girth_warp(0.95 * (1.0 + 0.03 * r.g()), 0.42, -0.3, 0.42, 0.1)
        )
    if shep:
        t.warps.add(
            girth_warp(
                (1.02 if male else 0.98) * (1.0 + 0.02 * r.g()),
                0.42,
                -0.3,
                0.42,
                0.1,
            )
        )
    if juv > 0.0:
        # Chubby pups with big paws.
        t.warps.add(girth_warp(1.12, 0.42, -0.3, 0.42, 0.1))
        for paw in [  # pragma: no branch
            V3(0.046, 0.025, 0.26),
            V3(-0.046, 0.025, 0.26),
            V3(0.052, 0.025, -0.28),
            V3(-0.052, 0.025, -0.28),
        ]:
            t.warps.add(scale_about_warp(paw, 1.22, 0.03, 0.06))
    t.set("size", size)
    t.set("headScale", head)
    t.set("earType", Float64(ear_type))
    t.set(
        "muzzle",
        (1.0 + 0.04 * r.g())
        * (0.96 if ret else (0.88 if ter else 1.02))
        * (0.72 if juv > 0.0 else 1.0),
    )
    t.set(
        "headW",
        (1.04 if male else 0.99)
        * (1.0 + 0.02 * r.g())
        * (1.12 if ret else (1.12 if ter else 1.05))
        * (1.05 if juv > 0.0 else 1.0),
    )
    var stop = 0.35 + 0.1 * r.g() if shep else (0.75 if ret else 1.0)
    t.set("stop", stop)
    t.set("flews", 0.8 + 0.2 * r.g() if ret else 0.0)
    t.set("muzzleDepth", 1.15 if ret else (1.08 if ter else 1.0))
    t.set("zyg", 0.7 if ret else 1.0)
    t.set("dome", 0.6 if ret else (0.2 if ter else 0.0))
    var ruff = (0.7 if male else 0.5) + 0.1 * r.g() if shep else (
        0.12 if ret else 0.0
    )
    t.set("ruff", ruff)
    t.set(
        "neckK",
        (1.22 if ret else (1.04 if ter else 1.0)) * (1.03 if male else 0.98),
    )
    t.set("chestK", 1.06 if ret else 1.0)
    t.set(
        "boneK",
        (1.35 if ret else (1.1 if ter else 1.0)) * (1.1 if juv > 0.0 else 1.0),
    )
    t.set("pawK", 1.1 if ret else (0.92 if ter else 1.0))
    t.set("tuck", 0.2 if ret else 1.0)
    t.set("eyeK", (1.3 if ter else 1.0) * (1.25 if juv > 0.0 else 1.0))
    t.set("eyeRound", 0.6 if ret else (0.5 if ter else 0.1 * juv))
    var shep_adult = shep and juv == 0.0
    t.set(
        "ear",
        (1.0 + 0.05 * r.g())
        * (1.08 if juv > 0.0 else 1.0)
        * (0.95 if shep_adult else (1.35 if ter else 1.0)),
    )
    t.set("tail", tail_k)
    t.set(
        "tailBrush",
        (1.0 + 0.06 * r.g())
        * (0.85 if juv > 0.0 else 1.0)
        * (1.2 if ret else 1.0),
    )
    t.set(
        "furK",
        (1.0 if shep else (0.32 if ret else 0.3)) * (1.0 + 0.06 * r.g()),
    )
    t.set("saddle", 1.1 * r.g())
    t.set("mask", 1.0 + 0.15 * r.g())
    t.set("coatWarmth", 0.9 * r.g())
    t.set("coatLightness", 0.1 * r.g())
    # The yellow retriever's nose fades to liver in some.
    var fade = 0.0
    var yellow_lab = ret and color == YELLOW
    if yellow_lab:
        fade = m.next()
    t.set("noseFade", fade)
    t.set("patches", 0.7 + 0.6 * m.next())
    t.set("blaze", 0.2 + 0.8 * m.next())
    t.set("blazeEnd", -0.05 + 0.08 * m.next())
    t.set("maskSide", 2.0 * m.next() - 1.0)
    t.set("coatSeed", Float64(Int(r.next() * 1e6)))
    t.set("minThick", 0.003)
    return t^


def dog_eye(t: Traits) -> EyeSpec:
    """Return the dog's left eye: an almond fissure, rounder in retrievers
    and terriers, relatively larger in small dogs and puppies.

    Args:
        t: The individual.

    Returns:
        The eye, head-local.
    """
    var k = t.get("eyeK")
    var rd = t.get("eyeRound", 0.0)
    return EyeSpec(
        V3(
            0.033 * t.get("headW") * HS,
            (0.022 + 0.002 * (k - 1.0)) * HS,
            0.038 * HS,
        ),
        0.0108 * k,
        0.0023 * k,
        0.2 - 0.05 * rd,
        0.04,
        0.0014 * k,
        0.0131 * k,
        0.0081 * k * (1.0 - 0.3 * rd),
        -0.0006,
        12.0 * pi / 180.0 * (1.0 - 0.6 * rd),
        0.0066 * k,
        0.0089 * k,
    )


def _hl(t: Traits, v: V3) -> V3:
    return head_local(HEAD_O, HS, MUZZLE_Z0, t.get("muzzle"), t.get("headW"), v)


def _hr(t: Traits, r: V3) -> V3:
    return V3(r.x * t.get("headW") * HS, r.y * HS, r.z * HS)


def _ear_base(ear_type: Int) -> V3:
    if ear_type == DROP:
        return V3(0.05, 0.036, -0.026)
    if ear_type == BUTTON:
        return V3(0.043, 0.047, -0.036)
    return V3(0.04, 0.045, -0.037)


def _ear_dir(ear_type: Int) -> V3:
    if ear_type == DROP:
        return V3(0.026, -0.08, 0.034)
    if ear_type == BUTTON:
        return V3(0.028, -0.004, 0.04)
    return V3(0.034, 0.116, -0.012)


def dog_rig(t: Traits) raises -> Rig:
    """Return the dog's skeleton in bind pose.

    The variant sets the topline, the hind angulation, the tail set and
    its carriage: the shepherd's sloping back and low saber tail, the
    retriever's level back and otter tail, the terrier's square frame and
    erect tail. Every variant is modeled at the shepherd's scale.

    Args:
        t: The individual.

    Returns:
        The rig.

    Raises:
        Error: If a bone names a missing joint.
    """
    var v = t.variant
    var hw = t.get("headW")
    var ek = t.get("ear")
    var ear_type = Int(t.get("earType", 0.0))
    var rig = Rig()
    rig.set("nose", _hl(t, V3(0.0, -0.014, 0.158)))
    rig.set("occiput", _hl(t, V3(0.0, 0.02, -0.095)))
    rig.set("neckMid", V3(0.0, 0.556, 0.405))
    rig.set("neckBase", V3(0.0, 0.5, 0.33))
    rig.set("chestMid", V3(0.0, 0.51, 0.17))
    rig.set("thoraxRear", V3(0.0, 0.514, 0.02))
    var angles: List[Float64]
    var tail_len: Float64
    if v == RETRIEVER:
        rig.set("lumbarMid", V3(0.0, 0.512, -0.095))
        rig.set("lumbosacral", V3(0.0, 0.505, -0.195))
        rig.set("tailBase", V3(0.0, 0.498, -0.27))
        rig.set("hipL", V3(0.058, 0.425, -0.23))
        rig.set("kneeL", V3(0.072, 0.252, -0.158))
        rig.set("hockL", V3(0.056, 0.105, -0.295))
        rig.set("mtpL", V3(0.053, 0.03, -0.283))
        rig.set("htoeL", V3(0.053, 0.012, -0.245))
        angles = [-10, -16, -20, -23, -25, -26, -26, -25]
        tail_len = 0.36
    elif v == TERRIER:
        rig.set("lumbarMid", V3(0.0, 0.515, -0.09))
        rig.set("lumbosacral", V3(0.0, 0.51, -0.185))
        rig.set("tailBase", V3(0.0, 0.505, -0.255))
        rig.set("hipL", V3(0.056, 0.43, -0.215))
        rig.set("kneeL", V3(0.068, 0.26, -0.145))
        rig.set("hockL", V3(0.054, 0.108, -0.268))
        rig.set("mtpL", V3(0.051, 0.03, -0.258))
        rig.set("htoeL", V3(0.051, 0.012, -0.22))
        angles = [38, 52, 62, 68, 70, 70, 68, 64]
        tail_len = 0.3
    else:
        rig.set("lumbarMid", V3(0.0, 0.505, -0.1))
        rig.set("lumbosacral", V3(0.0, 0.488, -0.205))
        rig.set("tailBase", V3(0.0, 0.468, -0.285))
        rig.set("hipL", V3(0.056, 0.41, -0.24))
        rig.set("kneeL", V3(0.07, 0.245, -0.165))
        rig.set("hockL", V3(0.055, 0.105, -0.318))
        rig.set("mtpL", V3(0.052, 0.03, -0.305))
        rig.set("htoeL", V3(0.052, 0.012, -0.267))
        angles = [-20, -32, -40, -45, -47, -47, -45, -41]
        tail_len = 0.39
    if v == TERRIER:
        # A little more bend in the standing foreleg of a small dog.
        rig.set("scapTopL", V3(0.034, 0.53, 0.255))
        rig.set("shoulderL", V3(0.06, 0.398, 0.333))
        rig.set("elbowL", V3(0.054, 0.264, 0.232))
    else:
        rig.set("scapTopL", V3(0.034, 0.54, 0.255))
        rig.set("shoulderL", V3(0.06, 0.41, 0.335))
        rig.set("elbowL", V3(0.054, 0.27, 0.238))
    rig.set("wristL", V3(0.047, 0.1, 0.247))
    rig.set("mcpL", V3(0.046, 0.029, 0.259))
    rig.set("ftoeL", V3(0.046, 0.012, 0.299))
    rig.set("jawHinge", _hl(t, V3(0.0, -0.034, -0.03)))
    rig.set("jawTip", _hl(t, V3(0.0, -0.06, 0.13)))
    # The tongue rides the jaw, in the floor of the mouth.
    rig.set("tongueBase", _hl(t, V3(0.0, -0.046, 0.02)))
    rig.set("tongueTip", _hl(t, V3(0.0, -0.05, 0.118)))
    var ear = _hl(t, _ear_base(ear_type))
    var d = _ear_dir(ear_type)
    rig.set("earBaseL", ear)
    rig.set(
        "earTipL",
        V3(
            ear.x + d.x * ek * HS * hw,
            ear.y + d.y * ek * HS,
            ear.z + d.z * ek * HS,
        ),
    )
    var tk = t.get("tail") * tail_len
    var w: List[Float64] = [1.14, 1.09, 1.04, 0.99, 0.95, 0.91, 0.86, 0.82]
    var ws = 0.0
    for x in w:  # pragma: no branch
        ws += x
    var lens = List[Float64]()
    for x in w:  # pragma: no branch
        lens.append(x / ws * tk)
    tail_chain(rig, "tailBase", angles, lens)
    rig.mirror_joints()
    quadruped_bones(rig, TAIL_SEGS)
    _ = rig.add_bone("tongue", "tongueBase", "tongueTip", "jaw")
    return rig^


def _tail_radius(t: Float64, tail_type: Int, tb: Float64) -> Float64:
    if tail_type == RETRIEVER:
        # Thick at the root, tapering evenly to a rounded tip.
        return tb * (0.034 - 0.022 * pow(t, 1.1))
    if tail_type == TERRIER:
        return tb * (0.019 - 0.008 * t)
    # The bushy saber: thickest at a third of its length.
    var root = 0.024 + 0.004 * (t / 0.12)
    var mid = 0.028 + 0.004 * ((t - 0.12) / 0.33)
    var tip = 0.032 - 0.016 * pow(max(t - 0.45, 0.0) / 0.55, 1.6)
    return tb * (root if t < 0.12 else (mid if t < 0.45 else tip))


def dog_sculpt(mut m: SdfModel, rig: Rig, t: Traits) raises:
    """Sculpt the dog: procedural-animals' `sculptDog`, primitive for
    primitive.

    The torso follows the axial joints, so each variant's topline carries
    the body. The head is shaped by the stop, the skull's width, the
    muzzle's length and depth, the retriever's flews and the cheek fur.
    The ears are prick, drop or button, the tail a saber, an otter tail
    or a short erect tail.

    Args:
        m: The sculpt to add to.
        rig: The dog's rig in bind pose.
        t: The individual.

    Raises:
        Error: If the rig lacks a joint or a bone, or the sculpt refuses
            a primitive.
    """
    var eye = dog_eye(t)
    var mz = t.get("muzzle")
    var hw = t.get("headW")
    var juv = t.juvenile()
    var stop = t.get("stop", 0.5)
    var flews = t.get("flews", 0.0)
    var mzd = t.get("muzzleDepth")
    var ruff = t.get("ruff", 0.5)
    var neck_k = t.get("neckK")
    var chest_k = t.get("chestK")
    var tuck = t.get("tuck", 0.0)
    var dome_k = t.get("dome", 0.0)
    # Short muzzles shorten the muzzle pads with the muzzle.
    var mzs = min(1.0, mz)
    var cm = rig.j("chestMid")
    var tr = rig.j("thoraxRear")
    var lm = rig.j("lumbarMid")
    var ls = rig.j("lumbosacral")
    var nb = rig.j("neckBase")
    var nm = rig.j("neckMid")
    var scap = rig.j("scapTopL")
    var tail_base = rig.j("tailBase")

    # TORSO: a deep chest to the elbow, a firm back, the belly tucked up.
    var rib_y = (cm.y + tr.y) / 2.0
    _ = m.ell(
        "ribcage",
        rig.bone("spine3"),
        V3(0, rib_y - 0.077, lerp(cm, tr, 0.4).z),
        V3(0.077 * chest_k, 0.128 * chest_k, 0.165),
        axis=normalize(V3(0, 0.1, -1)),
        k=0,
    )
    var b = rig.bone("chest")
    _ = m.ell(
        "brisket",
        b,
        V3(0, cm.y - 0.148, cm.z + 0.07),
        V3(0.048 * chest_k, 0.062, 0.085),
        axis=normalize(V3(0, -0.35, 1)),
        k=0.05,
    )
    _ = m.ell(
        "pectoral",
        b,
        V3(0, nb.y - 0.095, nb.z + 0.008),
        V3(0.056 * chest_k, 0.066, 0.052),
        k=0.045,
    )
    _ = m.ell(
        "withers",
        b,
        V3(0, scap.y + 0.012, scap.z - 0.045),
        V3(0.044, 0.046, 0.105),
        axis=normalize(V3(0, -0.1, 1)),
        k=0.05,
    )
    _ = m.ell(
        "back",
        rig.bone("spine3"),
        V3(0, tr.y + 0.036, tr.z + 0.01),
        V3(0.055, 0.042, 0.13),
        k=0.05,
    )
    _ = m.ell(
        "abdomen",
        rig.bone("spine2"),
        V3(0, lm.y - 0.048 + 0.012 * tuck, lm.z + 0.035),
        V3(0.06 * chest_k, 0.06 - 0.008 * tuck, 0.13),
        axis=normalize(V3(0, 0.34 * max(0.0, tuck), -1)),
        k=0.055,
    )
    var lo = lerp(lm, ls, 0.4)
    var neg_tuck = max(0.0, -tuck)
    b = rig.bone("spine1")
    _ = m.ell(
        "loin", b, V3(0, lo.y + 0.022, lo.z), V3(0.05, 0.041, 0.115), k=0.045
    )
    _ = m.ell(
        "flank",
        b,
        V3(0, ls.y - 0.05 - 0.01 * neg_tuck, ls.z + 0.02),
        V3(0.053 * chest_k, 0.053 + 0.012 * neg_tuck, 0.075),
        k=0.045,
    )
    b = rig.bone("pelvis")
    _ = m.ell(
        "pelvis",
        b,
        V3(0, ls.y - 0.02, ls.z - 0.058),
        V3(0.058, 0.07, 0.09),
        k=0.05,
    )
    _ = m.ell(
        "croup",
        b,
        V3(0, ls.y + 0.02, ls.z - 0.048),
        V3(0.046, 0.034, 0.085),
        axis=normalize(V3(0, (tail_base.y - ls.y) * 3.0, -0.25)),
        k=0.035,
    )
    for s in [1.0, -1.0]:  # pragma: no branch
        _ = m.ell(
            "rump",
            b,
            V3(0.035 * s, ls.y - 0.052, ls.z - 0.118),
            V3(0.036, 0.058, 0.042),
            k=0.035,
        )
    if ruff > 0.3:
        # The shepherd's thicker coat over the shoulders and neck.
        _ = m.ell(
            "cape",
            rig.bone("chest"),
            V3(0, scap.y + 0.005, scap.z + 0.04),
            V3(0.06 * (0.7 + 0.3 * ruff), 0.055, 0.1),
            axis=normalize(V3(0, 0.25, 1)),
            k=0.06,
        )

    # NECK
    var occ = rig.j("occiput")
    var n_top = lerp(nm, occ, 0.55)
    var n1 = rig.bone("neck1")
    _ = m.cone(
        "neck",
        n1,
        V3(0, nb.y - 0.02, nb.z - 0.03),
        nm,
        0.072 * neck_k,
        0.058 * neck_k,
        k=0.05,
    )
    _ = m.cone(
        "neck",
        rig.bone("neck2"),
        nm,
        V3(0, n_top.y, n_top.z),
        0.056 * neck_k,
        0.049 * neck_k,
        k=0.04,
    )
    # The crest: one convex arc from the occiput to the withers.
    var cr = lerp(nm, occ, 0.3)
    _ = m.ell(
        "nape",
        n1,
        V3(0, cr.y + 0.046, cr.z - 0.025),
        V3(0.042 * neck_k, 0.034, 0.1),
        axis=normalize(V3(0, 0.55, 1)),
        k=0.045,
    )
    # The throat: a straight line from under the jaw to the forechest.
    _ = m.cone(
        "throat",
        n1,
        _hl(t, V3(0, -0.05, -0.03)),
        V3(0, nb.y - 0.085, nb.z + 0.035),
        0.034 * neck_k,
        0.05 * neck_k,
        k=0.05,
    )
    var rf = 0.7 + 0.3 * ruff
    if ruff > 0.3:
        _ = m.ell(
            "ruff",
            n1,
            V3(0, nm.y - 0.03, nm.z - 0.035),
            V3(0.058 * rf * neck_k, 0.052 * rf, 0.07),
            axis=normalize(V3(0, 0.6, 1)),
            k=0.05,
        )

    # HEAD, in head-local coordinates.
    var h = rig.bone("head")
    var dome = 0.004 * juv + 0.003 * dome_k
    _ = m.ell(
        "cranium",
        h,
        _hl(t, V3(0, 0.016 + dome, -0.034)),
        _hr(
            t,
            V3(0.05 + 0.004 * juv, 0.048 + 0.008 * juv + 0.003 * dome_k, 0.064),
        ),
        k=0.035,
    )
    _ = m.ell(
        "forehead",
        h,
        _hl(t, V3(0, 0.027 + 0.011 * stop + dome, 0.008 + 0.008 * stop)),
        _hr(t, V3(0.034, 0.03, 0.042)),
        axis=normalize(V3(0, -0.35 + 0.35 * stop, 1)),
        k=0.026,
    )
    _ = m.ell(
        "crest",
        h,
        _hl(t, V3(0, 0.05, -0.055)),
        _hr(t, V3(0.016, 0.013, 0.048)),
        k=0.03,
    )
    for s in [1.0, -1.0]:  # pragma: no branch
        _ = m.ell(
            "brow",
            h,
            _hl(t, V3(0.028 * s, 0.037 + 0.006 * stop, 0.034)),
            _hr(t, V3(0.016, 0.008 + 0.002 * stop, 0.014)),
            k=0.012,
        )
        _ = m.ell(
            "zygomatic",
            h,
            _hl(t, V3(0.05 * s, 0.002, -0.006)),
            _hr(t, V3(0.015 * t.get("zyg"), 0.02, 0.042)),
            axis=normalize(V3(-0.3 * s, 0, 1)),
            k=0.024,
        )
        _ = m.ell(
            "cheek",
            h,
            _hl(t, V3(0.034 * s, -0.022, -0.006)),
            _hr(t, V3(0.021, 0.027, 0.04)),
            k=0.03,
        )
        # The maxilla carries the cheek forward into the muzzle's side.
        _ = m.ell(
            "maxilla",
            h,
            _hl(t, V3(0.029 * s, -0.02, 0.046)),
            _hr(t, V3(0.021, 0.025, 0.038)),
            k=0.03,
        )
        if ruff > 0.2:
            _ = m.ell(
                "cheekruff",
                h,
                _hl(t, V3(0.046 * s, -0.026, -0.046)),
                _hr(t, V3(0.014 * ruff, 0.036, 0.04)),
                axis=normalize(V3(0.3 * s, 0, 1)),
                k=0.03,
            )
        _ = m.ell(
            "mastoid",
            h,
            _hl(t, V3(0.034 * s, -0.02, -0.062)),
            _hr(t, V3(0.023, 0.03, 0.03)),
            k=0.03,
        )
        # The upper lip. The retriever's flews hang lower and fuller.
        _ = m.ell(
            "lip",
            h,
            _hl(t, V3(0.025 * s, -0.045 - 0.006 * flews, 0.078)),
            _hr(t, V3(0.015 + 0.002 * flews, 0.013 + 0.005 * flews, 0.058)),
            axis=normalize(V3(-0.2 * s, -0.06, 1)),
            k=0.016,
        )
        _ = m.ell(
            "whisker",
            h,
            _hl(t, V3(0.021 * s, -0.027 - 0.003 * flews, 0.121)),
            _hr(t, V3(0.015 + 0.002 * flews, 0.015 * mzd, 0.026 * mzs)),
            k=0.016,
        )
    # The muzzle: a straight bridge, broader and deeper in the retriever.
    _ = m.cone(
        "nasal",
        h,
        _hl(t, V3(0, 0.033 - 0.004 * stop - 0.023 * hw, 0.055)),
        _hl(t, V3(0, 0.007 - 0.016 * hw, 0.1505 - 0.0145 / mz)),
        0.023 * hw,
        0.016 * hw,
        k=0.016,
    )
    _ = m.ell(
        "muzzle",
        h,
        _hl(t, V3(0, -0.02, 0.084)),
        _hr(t, V3(0.033, 0.027 * mzd, 0.064 * mzs)),
        axis=normalize(V3(0, -0.1, 1)),
        k=0.02,
    )
    _ = m.ell(
        "nose",
        h,
        _hl(t, V3(0, -0.006, 0.1505)),
        _hr(t, V3(0.02, 0.0135, 0.0095)),
        axis=normalize(V3(0, 0.4, 1)),
        k=0.008,
    )
    _ = m.ell(
        "philtrum",
        h,
        _hl(t, V3(0, -0.031, 0.146)),
        _hr(t, V3(0.01, 0.012, 0.008)),
        k=0.01,
    )
    var er = eye.r / 0.0108
    for s in [1.0, -1.0]:  # pragma: no branch
        var ef = eye_frame_of(eye, HEAD_O, s)
        _ = ell_y(
            m,
            "orbit",
            h,
            ef.at(-0.002 * s, -0.0005, 0.018),
            ef.y,
            V3(0.017 * er, 0.012 * er, 0.0085),
            lateral=ef.x,
            k=0.008,
            carve=True,
        )
        _ = m.sphere("eyelid", h, ef.c, eye.r + eye.lid, k=0.005)
        _ = m.lens(
            "eyesocket",
            h,
            ef.c + ef.y * eye.off,
            ef.x,
            ef.y,
            ef.z,
            eye.big_r,
            eye.d,
            -0.002,
            0.024,
            k=0.0021,
            carve=True,
        )
        _ = m.sphere(
            "nostril",
            h,
            _hl(t, V3(0.0078 * s, -0.009, 0.16)),
            0.0035,
            k=0.002,
            carve=True,
        )
        # The upper canine, hidden behind the lip.
        _ = m.cone(
            "canine",
            h,
            _hl(t, V3(0.014 * s, -0.043, 0.118)),
            _hl(t, V3(0.013 * s, -0.057 - 0.004 * flews, 0.115)),
            0.0038,
            0.0011,
            k=0.002,
        )

    # JAW: its own surface, so the mouth can open.
    var jw = rig.bone("jaw")
    _ = m.cone(
        "mandible",
        jw,
        _hl(t, V3(0, -0.05, -0.015)),
        _hl(t, V3(0, -0.058, 0.11)),
        0.016,
        0.0085,
        k=0,
        part=JAW,
    )
    for s in [1.0, -1.0]:  # pragma: no branch
        _ = m.cone(
            "mandible",
            jw,
            _hl(t, V3(0.03 * s * hw, -0.044, -0.03)),
            _hl(t, V3(0.0065 * s, -0.056, 0.108)),
            0.012,
            0.007,
            k=0.02,
            part=JAW,
        )
        _ = m.cone(
            "lowercanine",
            jw,
            _hl(t, V3(0.0105 * s, -0.05, 0.112)),
            _hl(t, V3(0.0115 * s, -0.038, 0.109)),
            0.0032,
            0.001,
            k=0.001,
            part=JAW,
        )
    _ = m.ell(
        "chin",
        jw,
        _hl(t, V3(0, -0.06, 0.104)),
        _hr(t, V3(0.0105, 0.0085, 0.012)),
        k=0.015,
        part=JAW,
    )

    # TONGUE: long and flat in the floor of the mouth.
    var tb = rig.j("tongueBase")
    var tt = rig.j("tongueTip")
    var tdir = normalize(tt - tb)
    var tl = length(tt - tb)
    var tg = rig.bone("tongue")
    _ = ell_y(
        m,
        "tongue",
        tg,
        lerp(tb, tt, 0.45),
        tdir,
        V3(0.018 * hw, tl * 0.56, 0.0055),
        k=0,
        part=TONGUE,
    )
    _ = ell_y(
        m,
        "tongue",
        tg,
        lerp(tb, tt, 0.86),
        tdir,
        V3(0.019 * hw, tl * 0.2, 0.0045),
        k=0.01,
        part=TONGUE,
    )

    # EARS by type.
    var ear_type = Int(t.get("earType", 0.0))
    for side in [String("L"), String("R")]:  # pragma: no branch
        var s = 1.0 if side == "L" else -1.0
        var base = rig.j("earBase" + side)
        var tip = rig.j("earTip" + side)
        var dir = normalize(tip - base)
        var ln = length(tip - base)
        var eb = rig.bone("ear" + side)
        if ear_type == PRICK:
            _prick_ear(m, eb, base, tip, dir, ln, s)
        elif ear_type == DROP:
            # A pendant flap lying against the cheek.
            var fwd = normalize(cross(V3(s, 0, 0), dir) * -1.0)
            var k = ln / 0.09
            _ = ell_y(
                m,
                "ear",
                eb,
                lerp(base, tip, 0.12),
                dir,
                V3(0.022 * k, 0.02 * k, 0.008),
                lateral=fwd,
                k=0.012,
                thin=True,
            )
            _ = ell_y(
                m,
                "ear",
                eb,
                lerp(base, tip, 0.45),
                dir,
                V3(0.033 * k, 0.04 * k, 0.0055),
                lateral=fwd,
                k=0.012,
                thin=True,
            )
            _ = ell_y(
                m,
                "ear",
                eb,
                lerp(base, tip, 0.8),
                dir,
                V3(0.026 * k, 0.026 * k, 0.005),
                lateral=fwd,
                k=0.012,
                thin=True,
            )
        else:
            # A short upright root, then the flap folded forward and down.
            var k = ln / 0.05
            _ = ell_y(
                m,
                "ear",
                eb,
                base + V3(0.004 * s, 0.006, 0),
                V3(0, 1, 0),
                V3(0.019 * k, 0.013 * k, 0.008),
                lateral=V3(0, 0, 1),
                k=0.01,
                thin=True,
            )
            var nn = normalize(V3(0.8 * s, 0.6, 0.1))
            var bend = normalize(dir + V3(0, -0.6, 0))
            _ = ell_y(
                m,
                "ear",
                eb,
                lerp(base, tip, 0.5),
                dir,
                V3(0.022 * k, 0.026 * k, 0.005),
                lateral=normalize(cross(nn, dir)),
                k=0.01,
                thin=True,
            )
            _ = ell_y(
                m,
                "ear",
                eb,
                lerp(base, tip, 0.88) + bend * (0.008 * k),
                bend,
                V3(0.017 * k, 0.014 * k, 0.0045),
                lateral=normalize(cross(nn, bend)),
                k=0.01,
                thin=True,
            )

    # LEGS: bone and paw substance by variant.
    var leg_k = t.get("boneK")
    var pk = t.get("pawK")
    for side in [String("L"), String("R")]:  # pragma: no branch
        var s = 1.0 if side == "L" else -1.0
        _fore_leg(m, rig, side, s, leg_k, pk, ruff)
        _hind_leg(m, rig, side, s, leg_k, pk, ruff)

    # TAIL by type.
    var tail_type = t.variant
    var tbr = t.get("tailBrush")
    var root_r = 0.024 if tail_type == TERRIER else 0.03
    _ = m.cone(
        "tailroot",
        rig.bone("tail0"),
        lerp(tail_base, ls, 0.3),
        rig.j("tail1"),
        root_r,
        _tail_radius(0.1, tail_type, tbr),
        k=0.035,
    )
    var tk = 0.012 if tail_type == SHEPHERD else 0.022
    for i in range(TAIL_SEGS):  # pragma: no branch
        _ = m.cone(
            "tail",
            rig.bone("tail" + String(i)),
            rig.j("tail" + String(i)),
            rig.j("tail" + String(i + 1)),
            _tail_radius(Float64(i) / Float64(TAIL_SEGS), tail_type, tbr),
            _tail_radius(Float64(i + 1) / Float64(TAIL_SEGS), tail_type, tbr),
            k=tk,
            thin=i >= TAIL_SEGS - 1,
        )


def _prick_ear(
    mut m: SdfModel,
    eb: BoneId,
    base: V3,
    tip: V3,
    dir: V3,
    ln: Float64,
    s: Float64,
) raises:
    # Erect, broad at the base, pointed, the opening forward and a little
    # out, with a deep cup on its front.
    var facing = normalize(V3(0.5 * s, 0.05, 1))
    var lat = normalize(cross(dir, facing))
    var k = ln / 0.125
    _ = ell_y(
        m,
        "ear",
        eb,
        lerp(base, tip, 0.22),
        dir,
        V3(0.031 * k, 0.042 * k, 0.0085),
        lateral=lat,
        k=0.012,
        thin=True,
    )
    _ = ell_y(
        m,
        "ear",
        eb,
        lerp(base, tip, 0.55),
        dir,
        V3(0.02 * k, 0.042 * k, 0.006),
        lateral=lat,
        k=0.012,
        thin=True,
    )
    _ = ell_y(
        m,
        "ear",
        eb,
        lerp(base, tip, 0.85),
        dir,
        V3(0.0085 * k, 0.026 * k, 0.0042),
        lateral=lat,
        k=0.01,
        thin=True,
    )
    _ = ell_y(
        m,
        "earinner",
        eb,
        lerp(base, tip, 0.34) + facing * 0.0075,
        dir,
        V3(0.022 * k, 0.044 * k, 0.0075),
        lateral=lat,
        k=0.004,
        carve=True,
        thin=True,
    )
    _ = ell_y(
        m,
        "earinner",
        eb,
        lerp(base, tip, 0.67) + facing * 0.0055,
        dir,
        V3(0.011 * k, 0.03 * k, 0.0048),
        lateral=lat,
        k=0.003,
        carve=True,
        thin=True,
    )


def _fore_leg(
    mut m: SdfModel,
    rig: Rig,
    side: String,
    s: Float64,
    leg_k: Float64,
    pk: Float64,
    ruff: Float64,
) raises:
    var lat = V3(s, 0, 0)
    var sc = rig.j("scapTop" + side)
    var sh = rig.j("shoulder" + side)
    var e = rig.j("elbow" + side)
    var w = rig.j("wrist" + side)
    var mc = rig.j("mcp" + side)
    var toe = rig.j("ftoe" + side)
    var scap = rig.bone("scapula" + side)
    var hum = rig.bone("humerus" + side)
    var rad = rig.bone("radius" + side)
    var meta = rig.bone("metacarpus" + side)
    var fpaw = rig.bone("fpaw" + side)
    _ = ell_y(
        m,
        "scapmuscle",
        scap,
        lerp(sc, sh, 0.5) + on_side(V3(0.007, 0, 0), s),
        sh - sc,
        V3(0.022, 0.085, 0.05),
        lateral=lat,
        k=0.05,
    )
    _ = m.cone("upperarm", hum, sh, e, 0.034, 0.025, k=0.05)
    _ = ell_y(
        m,
        "triceps",
        hum,
        lerp(sh, e, 0.55) + V3(0, 0, -0.025),
        e - sh,
        V3(0.026, 0.063, 0.031),
        lateral=lat,
        k=0.042,
    )
    _ = m.sphere("olecranon", rad, e + V3(0, 0.006, -0.02), 0.015, k=0.018)
    _ = m.cone("forearm", rad, e, w, 0.025 * leg_k, 0.0155 * leg_k, k=0.022)
    _ = ell_y(
        m,
        "forearmmuscle",
        rad,
        lerp(e, w, 0.25) + on_side(V3(0.0025, 0, 0.003), s),
        w - e,
        V3(0.023 * leg_k, 0.056, 0.027 * leg_k),
        lateral=lat,
        k=0.026,
    )
    _ = ell_y(
        m,
        "feather",
        rad,
        lerp(e, w, 0.45) + V3(0, 0, -0.014),
        w - e,
        V3(0.012, 0.05, 0.014 * (0.6 + 0.6 * ruff)),
        lateral=lat,
        k=0.018,
    )
    _ = m.sphere("wrist", meta, w + V3(0, 0, -0.0025), 0.016 * leg_k, k=0.01)
    _ = m.sphere("carpalpad", meta, w + V3(0, -0.007, -0.016), 0.0075, k=0.009)
    _ = m.cone("pastern", meta, w, mc, 0.0155 * leg_k, 0.0155 * leg_k, k=0.01)
    _ = m.sphere(
        "dewclaw",
        meta,
        lerp(w, mc, 0.3) + on_side(V3(-0.0135, 0, 0.002), s),
        0.005,
        k=0.004,
    )
    var dp = normalize(toe - mc)
    _ = ell_y(
        m,
        "paw",
        fpaw,
        mc + dp * 0.018 + V3(0, -0.005, 0),
        dp,
        V3(0.025 * pk, 0.033 * pk, 0.016),
        lateral=lat,
        k=0.012,
    )
    _ = m.sphere("pad", fpaw, mc + V3(0, -0.016, 0.01), 0.011 * pk, k=0.009)
    var toe_x: List[Float64] = [-0.0175, -0.006, 0.006, 0.0175]
    var toe_z: List[Float64] = [-0.009, 0, 0, -0.009]
    for i in range(4):  # pragma: no branch
        _ = m.sphere(
            "toe",
            fpaw,
            V3(
                toe.x + toe_x[i] * pk * s,
                0.0102 * pk,
                toe.z - 0.0075 * pk + toe_z[i] * pk,
            ),
            0.0096 * pk,
            k=0.006,
        )
    for i in range(4):  # pragma: no branch
        var x = toe.x + toe_x[i] * pk * s * 0.95
        _ = m.cone(
            "claw",
            fpaw,
            V3(x, 0.0092 * pk, toe.z + toe_z[i] * pk),
            V3(x, 0.0035, toe.z + 0.009 * pk + toe_z[i] * pk),
            0.0027,
            0.001,
            k=0.002,
        )


def _hind_leg(
    mut m: SdfModel,
    rig: Rig,
    side: String,
    s: Float64,
    leg_k: Float64,
    pk: Float64,
    ruff: Float64,
) raises:
    var lat = V3(s, 0, 0)
    var hp = rig.j("hip" + side)
    var kn = rig.j("knee" + side)
    var hk = rig.j("hock" + side)
    var mt = rig.j("mtp" + side)
    var tt = rig.j("htoe" + side)
    var fem = rig.bone("femur" + side)
    var tib = rig.bone("tibia" + side)
    var mtar = rig.bone("metatarsus" + side)
    var hpaw = rig.bone("hpaw" + side)
    _ = ell_y(
        m,
        "thigh",
        fem,
        lerp(hp, kn, 0.4) + on_side(V3(0.003, 0, -0.024), s),
        kn - hp,
        V3(0.035, 0.118, 0.078),
        lateral=lat,
        k=0.045,
    )
    _ = m.cone(
        "thighfront",
        fem,
        hp + on_side(V3(-0.024, 0.044, 0.084), s),
        kn + on_side(V3(-0.003, 0.045, 0.0), s),
        0.031,
        0.02,
        k=0.05,
    )
    _ = m.cone(
        "hamstring",
        fem,
        hp + on_side(V3(-0.02, 0.044, -0.084), s),
        lerp(kn, hk, 0.28) + V3(0, 0, -0.025),
        0.037,
        0.023,
        k=0.035,
    )
    _ = ell_y(
        m,
        "breeches",
        fem,
        lerp(hp, kn, 0.62) + on_side(V3(0.005, -0.008, -0.068), s),
        kn - hp,
        V3(0.024, 0.064, 0.018 + 0.012 * ruff),
        lateral=lat,
        k=0.03,
    )
    _ = ell_y(
        m,
        "flankfold",
        fem,
        hp + on_side(V3(-0.016, -0.052, 0.1), s),
        V3(-0.03, 0.16, 0.1),
        V3(0.017, 0.066, 0.033),
        lateral=lat,
        k=0.05,
    )
    _ = m.sphere(
        "stifle", tib, kn + on_side(V3(0.002, 0.007, 0.005), s), 0.014, k=0.035
    )
    _ = m.cone(
        "shin",
        tib,
        lerp(kn, hk, 0.06) + on_side(V3(0, 0, 0.003), s),
        hk,
        0.019 * leg_k,
        0.014 * leg_k,
        k=0.025,
    )
    _ = ell_y(
        m,
        "calf",
        tib,
        lerp(kn, hk, 0.3) + on_side(V3(0.002, 0.008, -0.022), s),
        hk - kn,
        V3(0.021, 0.058, 0.025),
        lateral=lat,
        k=0.03,
    )
    _ = m.cone(
        "achilles",
        tib,
        lerp(kn, hk, 0.5) + V3(0, 0.008, -0.028),
        hk + V3(0, 0.01, -0.024),
        0.01,
        0.009,
        k=0.013,
    )
    _ = m.sphere("calcaneus", mtar, hk + V3(0, 0.01, -0.02), 0.0125, k=0.01)
    _ = m.sphere("hock", mtar, hk, 0.0165 * leg_k, k=0.01)
    _ = m.cone("metatarsus", mtar, hk, mt, 0.015 * leg_k, 0.014 * leg_k, k=0.01)
    var dh = normalize(tt - mt)
    _ = ell_y(
        m,
        "paw",
        hpaw,
        mt + dh * 0.016 + V3(0, -0.005, 0),
        dh,
        V3(0.022 * pk, 0.03 * pk, 0.015),
        lateral=lat,
        k=0.012,
    )
    _ = m.sphere("pad", hpaw, mt + V3(0, -0.018, 0.008), 0.01 * pk, k=0.009)
    var toe_x: List[Float64] = [-0.0175, -0.006, 0.006, 0.0175]
    var toe_z: List[Float64] = [-0.009, 0, 0, -0.009]
    for i in range(4):  # pragma: no branch
        _ = m.sphere(
            "toe",
            hpaw,
            V3(
                tt.x + toe_x[i] * pk * 0.92 * s,
                0.0096 * pk,
                tt.z - 0.0075 * pk + toe_z[i] * pk,
            ),
            0.0088 * pk,
            k=0.006,
        )
    for i in range(4):  # pragma: no branch
        var x = tt.x + toe_x[i] * pk * 0.88 * s
        _ = m.cone(
            "claw",
            hpaw,
            V3(x, 0.0085 * pk, tt.z + toe_z[i] * pk),
            V3(x, 0.0035, tt.z + 0.0085 * pk + toe_z[i] * pk),
            0.0025,
            0.0009,
            k=0.002,
        )


def dog_look(t: Traits) -> EyeLook:
    """Return the dog's eye colors: dark brown, brown in retrievers, amber
    in chocolates, blue-gray in puppies.

    Args:
        t: The individual.

    Returns:
        The look.
    """
    var sclera = V3(0.55, 0.45, 0.38)
    if t.juvenile() > 0.0:
        return EyeLook(
            V3(0.1, 0.12, 0.15),
            V3(0.2, 0.24, 0.3),
            V3(0.06, 0.07, 0.09),
            sclera,
            0.4,
            0.0,
        )
    var color = Int(t.get("color", 0.0))
    var chocolate = t.variant == RETRIEVER and color == CHOCOLATE
    if chocolate:
        return EyeLook(
            V3(0.22, 0.11, 0.03),
            V3(0.42, 0.24, 0.07),
            V3(0.1, 0.05, 0.015),
            sclera,
            0.4,
            0.0,
        )
    if t.variant == RETRIEVER:
        return EyeLook(
            V3(0.12, 0.055, 0.018),
            V3(0.24, 0.12, 0.04),
            V3(0.05, 0.022, 0.008),
            sclera,
            0.4,
            0.0,
        )
    return EyeLook(
        V3(0.08, 0.035, 0.012),
        V3(0.16, 0.075, 0.025),
        V3(0.035, 0.016, 0.006),
        sclera,
        0.4,
        0.0,
    )


def _swatches() -> List[String]:
    return [
        String("saddle"),
        "tan",
        "tanLight",
        "cream",
        "mask",
        "headTop",
        "earBack",
        "earInner",
        "tailTop",
        "tailUnder",
        "paw",
        "patchTan",
        "patchBlack",
    ]


# The palette keys, in procedural-animals' `PAL` order.
comptime KEY_BLACK_TAN = 0
comptime KEY_SABLE = 1
comptime KEY_BLACK = 2
comptime KEY_YELLOW = 3
comptime KEY_CHOC = 4
comptime KEY_LAB_BLACK = 5
comptime KEY_TERRIER = 6


def _key(t: Traits) -> Int:
    var color = Int(t.get("color", 0.0))
    if t.variant == TERRIER:
        return KEY_TERRIER
    if t.variant == RETRIEVER:
        return KEY_YELLOW if color == YELLOW else (
            KEY_LAB_BLACK if color == LAB_BLACK else KEY_CHOC
        )
    return KEY_BLACK_TAN if color == BLACK_TAN else (
        KEY_SABLE if color == SABLE else KEY_BLACK
    )


def _hexes(key: Int) -> List[Int]:
    if key == KEY_SABLE:
        return [
            0x4A3D33,
            0x9C7F5E,
            0xB89C78,
            0xCFBD9F,
            0x241D19,
            0x5A4A3C,
            0x2A221E,
            0x9C8468,
            0x3A302A,
            0xB49E80,
            0xB39776,
            0xA35F2C,
            0x1D1B1D,
        ]
    if key == KEY_BLACK:
        return [
            0x1B1817,
            0x221E1C,
            0x2A2522,
            0x332D29,
            0x171413,
            0x1D1A18,
            0x171413,
            0x2A2522,
            0x1A1716,
            0x26221F,
            0x221E1C,
            0xA35F2C,
            0x1D1B1D,
        ]
    if key == KEY_YELLOW:
        return [
            0xCFAE78,
            0xD9BB88,
            0xE2C89C,
            0xEBDCBC,
            0xD6B886,
            0xD2B27E,
            0xBF9A64,
            0xDCC094,
            0xCFAE78,
            0xE2CAA0,
            0xE0C79C,
            0xA35F2C,
            0x1D1B1D,
        ]
    if key == KEY_CHOC:
        return [
            0x5C3626,
            0x683F2B,
            0x734A34,
            0x7C5340,
            0x5F3828,
            0x5D3727,
            0x4F2E20,
            0x6C4634,
            0x5C3626,
            0x6E4533,
            0x6C4533,
            0xA35F2C,
            0x1D1B1D,
        ]
    if key == KEY_LAB_BLACK:
        return [
            0x19191B,
            0x1C1C1F,
            0x202023,
            0x232327,
            0x1A1A1D,
            0x19191B,
            0x161618,
            0x202023,
            0x19191B,
            0x1E1E21,
            0x1E1E21,
            0xA35F2C,
            0x1D1B1D,
        ]
    if key == KEY_TERRIER:
        return [
            0xF0EDE5,
            0xEFECE4,
            0xF2EFE8,
            0xF4F1EA,
            0xEFEBE2,
            0xEEEAE1,
            0xEFEBE2,
            0xE8DCD2,
            0xF0EDE5,
            0xF2EFE8,
            0xEEEBE3,
            0xA35F2C,
            0x1D1B1D,
        ]
    return [
        0x221B1A,
        0xB57A45,
        0xCB9D6C,
        0xD9C2A0,
        0x1C1615,
        0x3C2A22,
        0x1D1715,
        0xA07E5C,
        0x201A19,
        0xC39A6C,
        0xC99A66,
        0xA35F2C,
        0x1D1B1D,
    ]


def _agouti(key: Int) -> V3:
    # The agouti band's strength: back, side and head; legs are bare of it.
    if key == KEY_BLACK_TAN:
        return V3(0.15, 0.1, 0.1)
    if key == KEY_SABLE:
        return V3(0.85, 0.6, 0.45)
    return V3(0.0, 0.0, 0.0)


# The terrier's patch layout: the reference joints it is placed by.
comptime TER_THORAX = V3(0.0, 0.514, 0.02)
comptime TER_LUMBAR = V3(0.0, 0.515, -0.09)
comptime TER_TAIL = V3(0.0, 0.505, -0.255)
comptime TER_CHEST = V3(0.0, 0.51, 0.17)


def dog_palette(t: Traits) raises -> Palette:
    """Return one dog's palette: its variant's coat color, warmed and
    lightened, with its nose leather and agouti strength.

    A shepherd pup's tan is sooty until the tan comes in. The `agouti`
    entry holds the agouti band's strength on the back, the side and the
    head.

    Args:
        t: The individual.

    Returns:
        The palette, in linear light.

    Raises:
        Error: If the palette tables differ in length.
    """
    var key = _key(t)
    var names = _swatches()
    var base = palette_of(names, _hexes(key))
    var k = t.get("coatWarmth", 0.0)
    var l = t.get("coatLightness", 0.0)
    var juv = t.juvenile()
    var out = Palette()
    for name in names:  # pragma: no branch
        var c = base.get(name)
        var patch = name.startswith("patch")
        var kk = 2.2 * k if key == KEY_YELLOW else (
            0.15 * k if key == KEY_TERRIER and not patch else k
        )
        c = V3(
            c.x * (1.0 + 0.1 * kk + l),
            c.y * (1.0 + 0.01 * kk + l),
            c.z * (1.0 - 0.14 * kk + l),
        )
        var sooty = (
            juv > 0.0
            and key == KEY_BLACK_TAN
            and (name.startswith("tan") or name == "cream" or name == "paw")
        )
        if sooty:
            c = mix3(c, srgb(0x6A5040), 0.45 * juv)
        out.set(name, c)
    out.set("agouti", _agouti(key))
    var nose = srgb(0x161414)
    if key == KEY_CHOC:
        nose = srgb(0x6E4234)
    elif key == KEY_YELLOW and t.get("noseFade", 0.0) > 0.5:
        nose = srgb(0x5A4238)
    out.set("nose", nose)
    return out^


@fieldwise_init
struct _Patch(Copyable, Movable):
    var c: V3
    var r: V3
    var black: Bool


def _terrier_patches(t: Traits) -> List[_Patch]:
    # The terrier's seeded body patches, from the coat's own stream: a
    # saddle spot over the back, a tail-root patch and a chest patch.
    var out = List[_Patch]()
    var r = AnimalRandom(9173 + Int(t.get("coatSeed", 0.0)), 1, 0)
    var tri = Int(t.get("color", 0.0)) == TRICOLOR
    var nb = t.get("patches")
    var saddle = tri or r.next() < 0.35
    if saddle:
        var z0 = mix(TER_THORAX.z, TER_LUMBAR.z, r.next())
        var side = 1.0 if r.next() < 0.5 else -1.0
        var cx = 0.03 * side * r.next()
        var rx = 0.09 + 0.05 * r.next() * nb
        var ry = 0.1 + 0.05 * r.next()
        var rz = 0.07 + 0.06 * r.next() * nb
        out.append(_Patch(V3(cx, TER_THORAX.y + 0.02, z0), V3(rx, ry, rz), tri))
    var root = r.next() < (0.85 if tri else 0.4)
    if root:
        var rx = 0.07 + 0.02 * r.next()
        var rz = 0.06 + 0.03 * r.next()
        out.append(
            _Patch(
                V3(0.0, TER_TAIL.y + 0.01, TER_TAIL.z + 0.015),
                V3(rx, 0.06, rz),
                tri,
            )
        )
    if r.next() < 0.3 * nb:
        var cx = 0.06 * (1.0 if r.next() < 0.5 else -1.0)
        var cz = mix(TER_CHEST.z, TER_THORAX.z, r.next())
        var ry = 0.06 + 0.03 * r.next()
        var rz = 0.06 + 0.03 * r.next()
        var dark = tri and r.next() < 0.6
        out.append(
            _Patch(V3(cx, TER_CHEST.y - 0.02, cz), V3(0.05, ry, rz), dark)
        )
    return out^


def _head_local(t: Traits, p: V3) -> V3:
    var x = (p.x - HEAD_O.x) / t.get("headW") / HS
    var y = (p.y - HEAD_O.y) / HS
    var z = (p.z - HEAD_O.z) / HS
    var mz = t.get("muzzle")
    return V3(x, y, MUZZLE_Z0 + (z - MUZZLE_Z0) / mz if z > MUZZLE_Z0 else z)


def _patch_field(t: Traits, p: V3, n_off: Float64) -> V3:
    # The distance to the nearest body patch, and how black it is there:
    # a black patch keeps a thin tan rim.
    var d = 1.0
    var db = 1.0
    var nz = fbm3(V3(p.x * 18.0 + n_off, p.y * 18.0, p.z * 18.0), 2) - 0.5
    for q in _terrier_patches(t):
        var c = q.c
        var r = q.r
        var u = V3((p.x - c.x) / r.x, (p.y - c.y) / r.y, (p.z - c.z) / r.z)
        var di = (length(u) - 1.0 + 0.5 * nz) * min(r.x, min(r.y, r.z)) * 0.8
        d = min(d, di)
        if q.black:
            db = min(db, di)
    var black = smoothstep(-0.002, -0.009, db) if db < 0.02 else 0.0
    return V3(d, black, 0.0)


def _mouth_line(t: Traits, h: V3) -> Float64:
    # The upper lip's lower rim over a head-local point: the lowest of the
    # lips, the whisker pads, the muzzle and the philtrum.
    var f = t.get("flews", 0.0)
    var mz = t.get("muzzle")
    var mzd = t.get("muzzleDepth")
    var mzs = min(1.0, mz)
    var lip = mirrored_ell_bottom(
        h,
        V3(0.025, -0.045 - 0.006 * f, 0.078),
        V3(0.015 + 0.002 * f, 0.013 + 0.005 * f, 0.058 / mz),
    )
    var pad = mirrored_ell_bottom(
        h,
        V3(0.021, -0.027 - 0.003 * f, 0.121),
        V3(0.015 + 0.002 * f, 0.015 * mzd, 0.026 * mzs / mz),
    )
    var muzzle = mirrored_ell_bottom(
        h, V3(0.0, -0.02, 0.084), V3(0.033, 0.027 * mzd, 0.064 * mzs / mz)
    )
    var philtrum = mirrored_ell_bottom(
        h, V3(0.0, -0.031, 0.146), V3(0.01, 0.012, 0.008 / mz)
    )
    return min(min(lip, pad), min(muzzle, philtrum))


def _tail_at(t: Traits, bone: String, p: V3) -> V3:
    # How far along the tail a point lies, from zero at the root to one at
    # the tip, and the tail's dorsal direction there (y and z).
    var angles: List[Float64]
    var tail_len: Float64
    var base: V3
    if t.variant == RETRIEVER:
        angles = [-10, -16, -20, -23, -25, -26, -26, -25]
        tail_len = 0.36
        base = V3(0.0, 0.498, -0.27)
    elif t.variant == TERRIER:
        angles = [38, 52, 62, 68, 70, 70, 68, 64]
        tail_len = 0.3
        base = V3(0.0, 0.505, -0.255)
    else:
        angles = [-20, -32, -40, -45, -47, -47, -45, -41]
        tail_len = 0.39
        base = V3(0.0, 0.468, -0.285)
    var w: List[Float64] = [1.14, 1.09, 1.04, 0.99, 0.95, 0.91, 0.86, 0.82]
    var ws = 0.0
    for x in w:  # pragma: no branch
        ws += x
    var seg = 0
    for i in range(TAIL_SEGS):  # pragma: no branch
        if bone == "tail" + String(i):
            seg = i
    var a = base
    var done = 0.0
    for i in range(seg):
        var ang = angles[i] * pi / 180.0
        var l = w[i] / ws
        a = a + V3(0.0, sin(ang), -cos(ang)) * (l * tail_len * t.get("tail"))
        done += l
    var ang = angles[seg] * pi / 180.0
    var d = V3(0.0, sin(ang), -cos(ang))
    var l = w[seg] / ws
    var u = clamp((dot(p - a, d)) / (l * tail_len * t.get("tail")), 0.0, 1.0)
    return V3(done + u * l, cos(ang), sin(ang))


def dog_paint(
    pal: Palette, t: Traits, tag: String, bone: String, s: CoatSample
) -> Paint:
    """Paint one vertex of a dog.

    The shepherd wears a black saddle from the withers into the tail top,
    a black mask, dark ear backs, tan legs, cheeks and chest and a cream
    belly; a sable is agouti all over, darker along the back. Retrievers
    are solid, paler underneath. The terrier is white with a tan head
    mask split by a white blaze and, in tricolors, black body patches
    with a tan rim.

    Args:
        pal: The individual's palette.
        t: The individual.
        tag: The tag of the solid the vertex lies on.
        bone: The bone that solid rides.
        s: The vertex.

    Returns:
        The paint.
    """
    var p = s.p
    var n = s.n
    var key = _key(t)
    var liver = key == KEY_CHOC
    if tag == "tongue":
        return Paint(srgb(0xC86070), WET)
    if tag == "nose" or tag == "nostril":
        # The leather is the nose solid's own surface, not the fur it
        # blends into.
        var hn = _head_local(t, p)
        var on = hn.z > 0.135 and hn.y > -0.024
        if on:
            var nostril = 1.0 if tag == "nostril" else 0.0
            var leather = liver or key == KEY_YELLOW
            return Paint(
                mix3(pal.get("nose"), pal.get("nose") * 0.4, nostril),
                SKIN if leather else NOSE,
            )
    if tag == "canine" or tag == "lowercanine":
        return Paint(srgb(0xE8E0CC), KERATIN)
    if tag == "claw":
        var pale = key == KEY_TERRIER or key == KEY_YELLOW
        return Paint(srgb(0xB8A894) if pale else srgb(0x2A2420), KERATIN)
    var pad = (tag == "pad" or tag == "carpalpad") and n.y < -0.3
    if pad:
        return Paint(srgb(0x5A3A30) if liver else srgb(0x2A2524), SKIN)
    if tag == "eyesocket":
        return Paint(srgb(0x4A2A22) if liver else srgb(0x161210), SKIN)
    var juv = t.juvenile()
    var head = bone == "head" or bone == "jaw"
    if head:
        # The lip line: dark skin along the mouth slit, where the upper
        # lip's lower rim meets the jaw.
        var h = _head_local(t, p)
        var line = _mouth_line(t, h)
        var near = line < 0.5 and h.z > 0.02
        var upper = (
            near and bone == "head" and h.y < line + 0.0018 and n.y < -0.35
        )
        var lower = near and bone == "jaw" and h.y > line - 0.001 and n.y > 0.1
        var lips = upper or lower
        if lips:
            return Paint(srgb(0x5A3A30) if liver else srgb(0x231D1A), SKIN)
    var ag = pal.get("agouti")
    var n_off = Float64(Int(t.get("coatSeed", 0.0)) % 997)
    var nz = fbm3(V3(p.x * 7.0 + n_off, p.y * 7.0, p.z * 7.0), 3) - 0.5
    var nz2 = vnoise3(V3(p.x * 38.0 + n_off, p.y * 38.0, p.z * 38.0)) - 0.5
    var c: V3
    var agouti: Float64
    var region = 0
    var leg = 0.0
    if bone == "head":
        region = 2
    elif bone == "jaw":
        region = 6
    elif bone.startswith("ear"):
        region = 5
    elif bone.startswith("tail"):
        region = 4
    elif bone == "neck1" or bone == "neck2":
        region = 1
    elif is_limb(bone):
        # The limb's own colors take over below the body line.
        leg = smoothstep(0.42, 0.24, p.y)
    if region <= 1:
        var up = n.y
        # The pale underside: belly, the chest front, the inner legs.
        var vent: Float64
        if region == 0:
            vent = smoothstep(-0.05, -0.65, n.y)
            if p.z > 0.2:
                vent = max(
                    vent,
                    smoothstep(0.46, 0.36, p.y)
                    * smoothstep(0.07, 0.03, abs(p.x))
                    * smoothstep(-0.3, 0.4, n.z),
                )
            vent *= smoothstep(0.5, 0.4, p.y) * 0.55 + 0.45
        else:
            vent = (
                smoothstep(0.1, -0.5, n.y) * smoothstep(-0.4, 0.3, n.z)
                + smoothstep(0.52, 0.44, p.y) * 0.6
            )
        if leg > 0.0:
            var side = 1.0 if p.x >= 0.0 else -1.0
            var inner = smoothstep(0.1, -0.6, n.x * side)
            var wl = (
                inner * 0.8 * smoothstep(0.06, 0.25, p.y)
                + smoothstep(-0.3, -0.85, n.y) * 0.5
            )
            vent = mix(vent, wl, leg)
        vent = clamp(vent, 0.0, 1.0)
        c = mix3(
            pal.get("tan"),
            pal.get("tanLight"),
            smoothstep(0.2, -0.4, up + 0.2 * nz) * 0.5,
        )
        agouti = mix(ag.y * 0.7, ag.y, smoothstep(-0.3, 0.3, up))
        if region == 0:
            # The saddle: from the withers over the back into the tail top,
            # down the flanks, with a ragged edge.
            var dors = smoothstep(
                -0.08,
                0.12,
                up
                + 0.3 * nz
                + 0.22 * t.get("saddle", 0.0)
                + 0.2 * smoothstep(0.42, 0.55, p.y),
            )
            var along = smoothstep(0.3, 0.2, p.z) * smoothstep(
                -0.36, -0.26, p.z
            )
            if key == KEY_BLACK_TAN:
                c = mix3(c, pal.get("saddle"), dors * along)
            else:
                c = mix3(
                    c,
                    pal.get("saddle"),
                    dors * along * (0.7 if key == KEY_SABLE else 0.25),
                )
                agouti = mix(agouti, ag.x, dors * along)
            c = mix3(c, pal.get("cream"), vent)
            agouti *= 1.0 - vent
        else:
            # The neck: a dark nape, a tan or cream throat.
            var top = smoothstep(0.2, 0.85, up + 0.25 * nz)
            if key == KEY_BLACK_TAN:
                c = mix3(
                    c,
                    mix3(pal.get("saddle"), pal.get("headTop"), 0.5),
                    top * 0.9,
                )
            else:
                c = mix3(
                    c,
                    pal.get("saddle"),
                    top * (0.55 if key == KEY_SABLE else 0.2),
                )
            agouti = mix(ag.y * 0.7, ag.x, top)
            var shep = key == KEY_BLACK_TAN or key == KEY_SABLE
            c = mix3(
                c,
                pal.get("cream"),
                smoothstep(0.35, 0.8, vent) * (0.8 if shep else 0.6),
            )
            agouti *= 1.0 - smoothstep(0.3, 0.7, vent)
        if leg > 0.0:
            var lc = mix3(
                pal.get("tan"),
                pal.get("cream"),
                smoothstep(0.2, 0.8, vent) * 0.6,
            )
            lc = mix3(lc, c, smoothstep(0.26, 0.42, p.y) * 0.6)
            var paw = bone.startswith("fpaw") or bone.startswith("hpaw")
            if paw:
                lc = pal.get("paw")
            c = mix3(c, lc, leg)
            agouti = mix(agouti, 0.0, leg)
    elif region == 4:
        var tf = _tail_at(t, bone, p)
        var along = tf.x
        var dorsal = V3(0.0, tf.y, tf.z)
        var top = smoothstep(
            -0.35, 0.55, n.y * dorsal.y + n.z * dorsal.z + 0.3 * nz
        )
        c = mix3(pal.get("tailUnder"), pal.get("tailTop"), top)
        agouti = ag.x * 0.9 * top
        if key == KEY_BLACK_TAN:
            c = mix3(
                c, pal.get("saddle"), smoothstep(0.75, 0.92, along + 0.05 * nz)
            )
        if key == KEY_SABLE:
            c = mix3(c, srgb(0x1C1716), smoothstep(0.82, 0.95, along))
    elif region == 5:
        # Ears: dark backs, the inside paler.
        var sgn = 1.0 if p.x >= 0.0 else -1.0
        var facing = n.x * -sgn
        if Int(t.get("earType", 0.0)) == PRICK:
            facing = (n.x * 0.5 * sgn + n.y * 0.05 + n.z) / sqrt(
                0.25 + 0.0025 + 1.0
            )
        c = pal.get("earBack")
        if facing > 0.3 or tag == "earinner":
            c = mix3(
                pal.get("earBack"),
                pal.get("earInner"),
                max(
                    smoothstep(0.3, 0.75, facing),
                    0.5 if tag == "earinner" else 0.0,
                ),
            )
        agouti = ag.z * 0.5
    else:
        # The head and jaw.
        var h = _head_local(t, p)
        c = mix3(
            pal.get("headTop"),
            pal.get("tan"),
            smoothstep(0.03, -0.02, h.y + 0.1 * nz),
        )
        agouti = ag.z
        var muzzle = smoothstep(0.035, 0.075, h.z)
        var eye_ring = mirrored_blob(
            h, V3(0.033, 0.022, 0.038), V3(0.02, 0.014, 0.02)
        )
        var cheek = mirrored_blob(
            h, V3(0.04, -0.02, 0.0), V3(0.022, 0.022, 0.035)
        )
        var brow = mirrored_blob(
            h, V3(0.025, 0.04, 0.036), V3(0.01, 0.007, 0.01)
        )
        var shep = key == KEY_BLACK_TAN or key == KEY_SABLE
        if shep:
            var mk = clamp(
                max(
                    muzzle * (0.9 - 0.4 * smoothstep(-0.03, -0.06, h.y)),
                    eye_ring * 0.9,
                )
                * t.get("mask"),
                0.0,
                1.0,
            )
            c = mix3(c, pal.get("tan"), cheek * 0.9)
            c = mix3(c, pal.get("mask"), mk)
            c = mix3(c, pal.get("tanLight"), brow * 0.6 * (1.0 - juv))
            agouti *= 1.0 - 0.6 * mk
            c = mix3(
                c,
                pal.get("cream"),
                smoothstep(-0.05, -0.07, h.y)
                * smoothstep(-0.2, -0.6, n.y)
                * 0.5,
            )
        elif key == KEY_YELLOW:
            c = mix3(c, pal.get("tanLight"), cheek * 0.4)
            c = mix3(c, pal.get("cream"), smoothstep(-0.04, -0.065, h.y) * 0.4)
        # The darker lid margin round the eye.
        if tag == "eyelid":
            c = c * 0.55
    if t.variant == TERRIER:
        c = _terrier(pal, t, c, p, region, n_off)
    if juv > 0.0:
        agouti *= 1.0 - 0.6 * juv
    var cvh = fbm3(V3(p.x * 4.0 + 5.0 + n_off, p.y * 4.0, p.z * 4.0), 2) - 0.5
    var a = 0.25 if key == KEY_TERRIER else 1.0
    c = V3(
        c.x * (1.0 + a * (0.12 * nz + 0.08 * cvh + 0.06 * nz2)),
        c.y * (1.0 + a * (0.1 * nz + 0.06 * nz2)),
        c.z * (1.0 + a * (0.08 * nz - 0.06 * cvh + 0.06 * nz2)),
    )
    c = grizzle(c, p, 110.0, 0.08 + 0.3 * agouti)
    return Paint(c, FUR)


def _terrier(
    pal: Palette, t: Traits, c: V3, p: V3, region: Int, n_off: Float64
) -> V3:
    # The terrier's crisp patches over its white ground.
    var pd = 1.0
    var black = 0.0
    if region == 0 or region == 1 or region == 4:
        var f = _patch_field(t, p, n_off)
        pd = f.x
        black = f.y
    if region == 1 or region == 2 or region == 5:
        # A tan head mask over the ears, round the eyes, the cheeks and
        # the skull, split by a white blaze. A white terrier keeps tan
        # only on the ears and round one or both eyes.
        var h = _head_local(t, p)
        var side = 1.0 if h.x >= 0.0 else -1.0
        var ext = 1.0 + 0.35 * t.get("maskSide", 0.0) * side
        var wob = 0.005 * (
            fbm3(V3(p.x * 30.0 + n_off, p.y * 30.0, p.z * 30.0), 2) - 0.5
        )
        var white = Int(t.get("color", 0.0)) == WHITE
        var z_front = (0.03 if white else 0.068) * ext
        var y_low = 0.0 if white else -0.022 - 0.006 * ext
        var d_mask = max(h.z - z_front, max(y_low - h.y, -0.09 - h.z)) + wob
        var bw = (0.004 + 0.01 * t.get("blaze")) * (
            0.5 + 0.8 * smoothstep(0.0, 0.07, h.z)
        )
        var d_blaze = max(abs(h.x) - bw, t.get("blazeEnd", -0.02) - h.z)
        var dh = -0.02 if region == 5 else max(d_mask, -d_blaze)
        black = 0.0 if dh < pd else black
        pd = min(pd, dh)
        var one_eye = (
            white and region == 2 and t.get("maskSide", 0.0) * side < -0.3
        )
        if one_eye:
            pd = max(pd, 0.01)
    var w = smoothstep(0.0015, -0.0015, pd)
    return mix3(c, mix3(pal.get("patchTan"), pal.get("patchBlack"), black), w)
