# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The gray wolf, Canis lupus: procedural-animals' `species/wolf/`.

A digitigrade trotter with a dense double coat. The reference adult
stands 0.75 m at the withers. Its winter coat is partly sculpted as
volume: the neck ruff, the cheek ruff, the cape, the breeches and the
brush. Morphs are gray (60 %), black (20 %), pale (15 %) and tawny (5 %).
"""

from extensions.animals.coat import (
    FUR,
    KERATIN,
    NOSE,
    SKIN,
    CoatSample,
    EyeLook,
    Paint,
    Palette,
    band,
    grizzle,
    mix3,
    palette_of,
    srgb,
)
from extensions.sdf.ids import BoneId
from extensions.animals.parts import JAW
from extensions.sdf.sculpt import (
    ell_y,
    tube,
)
from extensions.animals.kit import (
    EyeSpec,
    eye_frame_of,
    head_local,
    is_limb,
)
from extensions.animals.options import AnimalOptions, AnimalRandom
from extensions.animals.rig import Rig, quadruped_bones, tail_chain
from extensions.sdf.field import SdfModel
from extensions.animals.traits import Traits, pick_age, pick_sex, pick_variant
from extensions.sdf.vector import (
    V3,
    clamp,
    cross,
    length,
    lerp,
    normalize,
    smoothstep,
    on_side,
)
from extensions.animals.warp import (
    length_warp,
    legs_warp,
    scale_about_warp,
)
from std.math import pi, pow, sqrt

comptime TAIL_SEGS = 8
# The head's origin, mid cranium between the eyes and the ears.
comptime HEAD_O = V3(0.0, 0.752, 0.6)
# The head-local scale: landmarks are for a 0.25 m skull.
comptime HS = 1.11
# Where the muzzle starts, head-local. Muzzle length acts ahead of it.
comptime MUZZLE_Z0 = 0.035
# The finest cell, at the `HERO` tier: the head's cell in the original.
comptime CELL = 0.0025

# The morphs, in procedural-animals' order.
comptime GRAY = 0
comptime BLACK = 1
comptime PALE = 2
comptime TAWNY = 3


def wolf_variant_names() -> List[String]:
    """Return the wolf's color morphs.

    Returns:
        Gray, black, pale and tawny.
    """
    return [String("gray"), "black", "pale", "tawny"]


def wolf_traits(mut r: AnimalRandom, options: AnimalOptions) raises -> Traits:
    """Draw one wolf: procedural-animals' `variation`.

    Males are about 20 % heavier, with a broader head and a fuller ruff.
    Pups are half size, with a big domed head, big paws and a short muzzle.

    Args:
        r: The individual's stream.
        options: The caller's sex, age and morph.

    Returns:
        The traits.

    Raises:
        Error: If the requested morph is not one of the four.
    """
    var sex = pick_sex(options.sex, r)
    var age = pick_age(options.age)
    var weights: List[Float64] = [0.6, 0.2, 0.15, 0.05]
    var variant: Int
    if options.variant.value < 0:
        variant = pick_variant(-1, weights, r.next())
    else:
        variant = pick_variant(options.variant.value, weights, 0.0)
        _ = r.next()
    var t = Traits(sex, age, variant)
    var juv = t.juvenile()
    var male = t.male()
    var size = (
        (1.035 if male else 0.965)
        * (0.94 if variant == TAWNY else 1.0)
        * (1.0 + 0.035 * r.g())
        * (0.52 if juv > 0.0 else 1.0)
    )
    var legs = (
        1.0 + 0.03 * r.g() - 0.1 * juv + (-0.03 if variant == PALE else 0.0)
    )
    var head = (1.035 if male else 0.98) * (1.0 + 0.02 * r.g())
    t.set("size", size)
    t.set(
        "muzzle",
        (1.0 + 0.04 * r.g())
        * (0.68 if juv > 0.0 else 1.0)
        * (0.96 if variant == PALE else 1.0),
    )
    t.set(
        "headW",
        (1.06 if male else 0.98)
        * (1.0 + 0.02 * r.g())
        * (1.06 if juv > 0.0 else 1.0),
    )
    t.set(
        "ear",
        (1.0 + 0.05 * r.g())
        * (1.12 if juv > 0.0 else 1.0)
        * (0.92 if variant == PALE else 1.0),
    )
    t.set("tail", (1.0 + 0.04 * r.g()) * (0.75 if juv > 0.0 else 1.0))
    t.set("tailBrush", (1.0 + 0.06 * r.g()) * (0.85 if juv > 0.0 else 1.0))
    t.set(
        "ruff",
        max(0.85, 1.0 + 0.12 * r.g()) * (1.1 if male else 0.95) - 0.2 * juv,
    )
    t.set("saddle", 1.1 * r.g())
    t.set("mask", 1.0 + 0.15 * r.g())
    # These two draw only for the morphs that have them, as the original.
    var line = 0.0
    if variant == GRAY or variant == TAWNY:
        line = max(0.0, 0.3 + 0.7 * r.g())
    t.set("legLine", line)
    var frost = 0.0
    if variant == BLACK:
        frost = max(0.0, 0.25 + 0.5 * r.g()) * (1.0 - juv)
    t.set("frost", frost)
    t.set("coatWarmth", 0.6 * r.g())
    t.set("coatLightness", 0.18 * r.g())
    t.set("coatSeed", Float64(Int(r.next() * 1e6)))
    var length_draw = r.g()
    t.warps.add(legs_warp(legs, 0.45))
    t.warps.add(length_warp(1.0 + 0.03 * length_draw - 0.04 * juv, -0.3, 0.38))
    t.warps.add(
        scale_about_warp(HEAD_O, head * (1.3 if juv > 0.0 else 1.0), 0.08, 0.2)
    )
    if juv > 0.0:
        for paw in [  # pragma: no branch
            V3(0.056, 0.03, 0.32),
            V3(-0.056, 0.03, 0.32),
            V3(0.064, 0.03, -0.3),
            V3(-0.064, 0.03, -0.3),
        ]:
            t.warps.add(scale_about_warp(paw, 1.22, 0.035, 0.075))
    t.set("grayTone", r.g())
    return t^


def wolf_eye(t: Traits) -> EyeSpec:
    """Return the wolf's left eye: a round pupil and an amber iris.

    Args:
        t: The individual. The eye moves with the head's width.

    Returns:
        The eye, head-local.
    """
    var hw = t.get("headW")
    return EyeSpec(
        V3(0.034 * hw * HS, 0.021 * HS, 0.036 * HS),
        0.0118,
        0.0025,
        0.23,
        0.04,
        0.0015,
        0.01415,
        0.0089,
        -0.0008,
        18.0 * pi / 180.0,
        0.0072,
        0.0096,
    )


def _hl(t: Traits, v: V3) -> V3:
    return head_local(HEAD_O, HS, MUZZLE_Z0, t.get("muzzle"), t.get("headW"), v)


def _hl_rig(t: Traits, v: V3) -> V3:
    return head_local(HEAD_O, HS, MUZZLE_Z0, t.get("muzzle"), 1.0, v)


def wolf_rig(t: Traits) raises -> Rig:
    """Return the wolf's skeleton in bind pose.

    Limb segments come from wolf long-bone series. The tail is held out
    behind, clear of the buttocks.

    Args:
        t: The individual.

    Returns:
        The rig.

    Raises:
        Error: If a bone names a missing joint.
    """
    var ek = t.get("ear")
    var rig = Rig()
    rig.set("nose", _hl_rig(t, V3(0.0, -0.012, 0.155)))
    rig.set("occiput", _hl_rig(t, V3(0.0, 0.02, -0.095)))
    rig.set("neckMid", V3(0.0, 0.685, 0.45))
    rig.set("neckBase", V3(0.0, 0.615, 0.4))
    rig.set("chestMid", V3(0.0, 0.635, 0.21))
    rig.set("thoraxRear", V3(0.0, 0.645, 0.03))
    rig.set("lumbarMid", V3(0.0, 0.655, -0.1))
    rig.set("lumbosacral", V3(0.0, 0.65, -0.21))
    rig.set("tailBase", V3(0.0, 0.635, -0.31))
    rig.set("scapTopL", V3(0.042, 0.675, 0.315))
    rig.set("shoulderL", V3(0.076, 0.516, 0.418))
    rig.set("elbowL", V3(0.068, 0.344, 0.29))
    rig.set("wristL", V3(0.058, 0.125, 0.305))
    rig.set("mcpL", V3(0.056, 0.036, 0.32))
    rig.set("ftoeL", V3(0.056, 0.016, 0.37))
    rig.set("hipL", V3(0.07, 0.545, -0.255))
    rig.set("kneeL", V3(0.088, 0.33, -0.173))
    rig.set("hockL", V3(0.068, 0.14, -0.327))
    rig.set("mtpL", V3(0.064, 0.037, -0.315))
    rig.set("htoeL", V3(0.064, 0.016, -0.268))
    rig.set("jawHinge", _hl_rig(t, V3(0.0, -0.035, -0.035)))
    rig.set("jawTip", _hl_rig(t, V3(0.0, -0.058, 0.128)))
    rig.set("earBaseL", _hl_rig(t, V3(0.054, 0.046, -0.048)))
    rig.set(
        "earTipL",
        _hl_rig(
            t, V3(0.054 + 0.03 * ek, 0.046 + 0.084 * ek, -0.048 - 0.006 * ek)
        ),
    )
    var tk = t.get("tail") * 1.08
    var angles: List[Float64] = [-14, -24, -31, -37, -41, -44, -45, -45]
    var lens: List[Float64] = [
        0.06 * tk,
        0.057 * tk,
        0.054 * tk,
        0.051 * tk,
        0.048 * tk,
        0.045 * tk,
        0.042 * tk,
        0.039 * tk,
    ]
    tail_chain(rig, "tailBase", angles, lens)
    rig.mirror_joints()
    quadruped_bones(rig, TAIL_SEGS)
    return rig^


def _tail_radius(t: Float64, tb: Float64) -> Float64:
    # The brush: a narrow root, fullest at 50 to 60 % of its length,
    # tapering to the tip.
    var root = 0.026 + 0.004 * (t / 0.15)
    var mid = 0.03 + 0.026 * smoothstep(0.15, 0.55, t)
    var tip = 0.056 - 0.043 * pow(max(t - 0.55, 0.0) / 0.45, 1.6)
    return tb * (root if t < 0.15 else (mid if t < 0.55 else tip))


def wolf_sculpt(mut m: SdfModel, rig: Rig, t: Traits) raises:
    """Sculpt the wolf: procedural-animals' `sculptWolf`, primitive for
    primitive.

    Args:
        m: The sculpt to add to.
        rig: The wolf's rig in bind pose.
        t: The individual.

    Raises:
        Error: If the rig lacks a joint or a bone, or the sculpt refuses
            a primitive.
    """
    var hw = t.get("headW")
    var ruff = t.get("ruff")
    var juv = t.juvenile()

    # TORSO: a deep, narrow keeled chest, a level back and a tucked belly.
    var b = rig.bone("spine3")
    _ = m.ell(
        "ribcage",
        b,
        V3(0, 0.55, 0.14),
        V3(0.101, 0.142, 0.2),
        axis=normalize(V3(0, 0.12, -1)),
        k=0,
    )
    b = rig.bone("chest")
    _ = m.ell(
        "brisket",
        b,
        V3(0, 0.455, 0.29),
        V3(0.056, 0.07, 0.1),
        axis=normalize(V3(0, -0.35, 1)),
        k=0.06,
    )
    _ = m.ell("pectoral", b, V3(0, 0.5, 0.405), V3(0.066, 0.078, 0.06), k=0.05)
    _ = m.ell(
        "withers",
        b,
        V3(0, 0.69, 0.26),
        V3(0.052, 0.055, 0.13),
        axis=normalize(V3(0, -0.1, 1)),
        k=0.06,
    )
    _ = m.ell(
        "back",
        rig.bone("spine3"),
        V3(0, 0.692, 0.03),
        V3(0.066, 0.05, 0.16),
        k=0.06,
    )
    _ = m.ell(
        "abdomen",
        rig.bone("spine2"),
        V3(0, 0.585, -0.08),
        V3(0.079, 0.087, 0.16),
        axis=normalize(V3(0, 0.33, -1)),
        k=0.07,
    )
    b = rig.bone("spine1")
    _ = m.ell("loin", b, V3(0, 0.68, -0.14), V3(0.06, 0.05, 0.14), k=0.05)
    _ = m.ell("flank", b, V3(0, 0.59, -0.19), V3(0.064, 0.064, 0.09), k=0.05)
    b = rig.bone("pelvis")
    _ = m.ell("pelvis", b, V3(0, 0.625, -0.28), V3(0.07, 0.085, 0.11), k=0.06)
    _ = m.ell("croup", b, V3(0, 0.675, -0.27), V3(0.055, 0.04, 0.1), k=0.04)
    for s in [1.0, -1.0]:  # pragma: no branch
        _ = m.ell(
            "rump",
            b,
            V3(0.042 * s, 0.585, -0.355),
            V3(0.042, 0.07, 0.05),
            k=0.04,
        )
    # The cape: long guard hair over the shoulders and hackles.
    _ = m.ell(
        "cape",
        rig.bone("chest"),
        V3(0, 0.675, 0.31),
        V3(0.09 * (0.8 + 0.2 * ruff), 0.075, 0.13),
        axis=normalize(V3(0, 0.25, 1)),
        k=0.07,
    )

    # NECK: thick, wrapped in the ruff.
    var n1 = rig.bone("neck1")
    var n2 = rig.bone("neck2")
    _ = m.cone(
        "neck", n1, V3(0, 0.58, 0.37), V3(0, 0.685, 0.455), 0.088, 0.07, k=0.06
    )
    _ = m.cone(
        "neck", n2, V3(0, 0.685, 0.455), V3(0, 0.765, 0.51), 0.07, 0.058, k=0.04
    )
    _ = m.ell(
        "nape",
        n1,
        V3(0, 0.745, 0.42),
        V3(0.046, 0.034, 0.1),
        axis=normalize(V3(0, 0.5, 1)),
        k=0.04,
    )
    _ = m.ell(
        "throat",
        n2,
        V3(0, 0.625, 0.5),
        V3(0.048, 0.06, 0.07),
        axis=normalize(V3(0, 0.8, 0.6)),
        k=0.05,
    )
    # The ruff frames the face, fullest at the throat and the sides.
    var rf = (0.75 + 0.25 * ruff) * 1.2
    _ = m.ell(
        "ruff",
        n1,
        V3(0, 0.64, 0.43),
        V3(0.082 * rf, 0.088 * rf, 0.095),
        axis=normalize(V3(0, 0.6, 1)),
        k=0.06,
    )
    _ = m.ell(
        "ruff",
        n2,
        V3(0, 0.67, 0.505),
        V3(0.062 * rf, 0.055 * rf, 0.05),
        axis=normalize(V3(0, 0.8, 1)),
        k=0.05,
    )

    # HEAD, in head-local coordinates.
    var h = rig.bone("head")
    _ = m.ell(
        "cranium",
        h,
        _hl(t, V3(0, 0.024 + 0.002 * juv, -0.035)),
        _hr(t, V3(0.053 + 0.002 * juv, 0.053 + 0.005 * juv, 0.066)),
        k=0.04,
    )
    for s in [1.0, -1.0]:  # pragma: no branch
        _ = m.ell(
            "temporal",
            h,
            _hl(t, V3(0.03 * s, 0.041, -0.045)),
            _hr(t, V3(0.03, 0.026, 0.045)),
            k=0.03,
        )
    _ = m.ell(
        "forehead",
        h,
        _hl(t, V3(0, 0.043 + 0.002 * juv, 0.014)),
        _hr(t, V3(0.037, 0.032, 0.038)),
        axis=normalize(V3(0, -0.35, 1)),
        k=0.025,
    )
    _ = m.ell(
        "crest",
        h,
        _hl(t, V3(0, 0.052, -0.055)),
        _hr(t, V3(0.018, 0.014, 0.05)),
        k=0.03,
    )
    for s in [1.0, -1.0]:  # pragma: no branch
        _ = m.ell(
            "brow",
            h,
            _hl(t, V3(0.029 * s, 0.037, 0.032)),
            _hr(t, V3(0.016, 0.008, 0.014)),
            k=0.012,
        )
        _ = m.ell(
            "zygomatic",
            h,
            _hl(t, V3(0.056 * s, 0.002, -0.004)),
            _hr(t, V3(0.016, 0.022, 0.045)),
            axis=normalize(V3(-0.3 * s, 0, 1)),
            k=0.035,
        )
        _ = m.ell(
            "cheek",
            h,
            _hl(t, V3(0.038 * s, -0.028, -0.006)),
            _hr(t, V3(0.018, 0.026, 0.038)),
            k=0.035,
        )
        _ = m.ell(
            "maxilla",
            h,
            _hl(t, V3(0.022 * s, -0.013, 0.052)),
            _hr(t, V3(0.02, 0.027, 0.062)),
            axis=normalize(V3(-0.2 * s, -0.1, 1)),
            k=0.024,
        )
        _ = m.ell(
            "commissure",
            h,
            _hl(t, V3(0.031 * s, -0.036, 0.028)),
            _hr(t, V3(0.013, 0.012, 0.026)),
            k=0.016,
        )
        _ = m.ell(
            "cheekruff",
            h,
            _hl(t, V3(0.056 * s, -0.036, -0.07)),
            _hr(t, V3(0.03 * rf, 0.045, 0.034)),
            axis=normalize(V3(0.35 * s, 0, 1)),
            k=0.03,
        )
        _ = m.ell(
            "mastoid",
            h,
            _hl(t, V3(0.036 * s, -0.018, -0.062)),
            _hr(t, V3(0.024, 0.03, 0.03)),
            k=0.03,
        )
        _ = m.ell(
            "lip",
            h,
            _hl(t, V3(0.0195 * s, -0.0395, 0.062)),
            _hr(t, V3(0.0095, 0.0108, 0.04)),
            axis=normalize(V3(-0.2 * s, 0.11, 1)),
            k=0.014,
        )
    # The front of the lip: one tube along the margin to the midline.
    for s in [1.0, -1.0]:  # pragma: no branch
        var pts = List[V3]()
        var radii = List[Float64]()
        for q in _lip_margin():  # pragma: no branch
            pts.append(_hl(t, V3(q.x * s, q.y, q.z)))
        for rr in [0.0072, 0.0062, 0.0048, 0.0043]:  # pragma: no branch
            radii.append(rr * HS)
        var mx = _lip_margin()[2]
        tube(
            m,
            "lipfront",
            h,
            pts,
            radii,
            _hl(t, V3(-mx.x * s, mx.y, mx.z)),
            3,
            0.01,
        )
    for s in [1.0, -1.0]:  # pragma: no branch
        _ = m.ell(
            "whisker",
            h,
            _hl(t, V3(0.0115 * s, -0.0195, 0.116)),
            _hr(t, V3(0.009, 0.0088, 0.018)),
            k=0.01,
        )
    _ = m.cone(
        "nasal",
        h,
        _hl(t, V3(0, 0.021, 0.058)),
        _hl(t, V3(0, 0.0084, 0.126)),
        0.024 * hw,
        0.013 * hw,
        k=0.02,
    )
    _ = m.ell(
        "bridge",
        h,
        _hl(t, V3(0, 0.009, 0.088)),
        _hr(t, V3(0.02, 0.012, 0.045)),
        axis=normalize(V3(0, -0.25, 1)),
        k=0.02,
    )
    _ = m.ell(
        "muzzle",
        h,
        _hl(t, V3(0, -0.016, 0.082)),
        _hr(t, V3(0.025, 0.0245, 0.05)),
        axis=normalize(V3(0, 0.1, 1)),
        k=0.02,
    )
    _ = m.ell(
        "rostrum",
        h,
        _hl(t, V3(0, -0.004, 0.13)),
        _hr(t, V3(0.0165, 0.012, 0.019)),
        k=0.012,
    )
    # The nose leather: a front lobe and a dorsal plate.
    _ = m.ell(
        "nose", h, _hl(t, NOSE_C), _hr(t, NOSE_R), axis=_nose_axis(), k=0.008
    )
    _ = m.ell(
        "nosetop",
        h,
        _hl(t, V3(0, 0.0075, 0.142)),
        _hr(t, V3(0.0184, 0.006, 0.017)),
        axis=normalize(V3(0, -0.12, 1)),
        k=0.006,
    )
    var eye = wolf_eye(t)
    for s in [1.0, -1.0]:  # pragma: no branch
        var ef = eye_frame_of(eye, HEAD_O, s)
        # The orbit: a soft hollow so brow, cheek and bridge fall to the lids.
        _ = ell_y(
            m,
            "orbit",
            h,
            ef.at(-0.002 * s, -0.0005, 0.019),
            ef.y,
            V3(0.018, 0.0125, 0.009),
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
            k=0.0022,
            carve=True,
        )
        # The nostril and its alar slit.
        var nc = _nose_at(0.0088 * s, -0.0036, 0.0009)
        _ = m.ell(
            "nostril",
            h,
            _hl(t, nc),
            _hr(t, V3(0.0048, 0.0051, 0.005)),
            axis=_nose_normal(0.0088 * s, -0.0036),
            k=0.0012,
            carve=True,
        )
        _ = m.cone(
            "alar",
            h,
            _hl(t, _nose_at(0.0124 * s, -0.0012, 0.0003)),
            _hl(t, _nose_at(0.0148 * s, 0.0004, 0.0002)),
            0.0014,
            0.001,
            k=0.0008,
            carve=True,
        )
        # The upper canine and the incisors, inside the closed mouth.
        _ = m.cone(
            "canine",
            h,
            _hl(t, V3(0.014 * s, -0.0295, 0.1095)),
            _hl(t, V3(0.013 * s, -0.0362, 0.1067)),
            0.004,
            0.0012,
            k=0.002,
        )
        for q in [  # pragma: no branch
            V3(0.0024, 0.1215, 0.0014),
            V3(0.0066, 0.1202, 0.0014),
            V3(0.0106, 0.1175, 0.0017),
        ]:
            _ = m.cone(
                "tooth",
                h,
                _hl(t, V3(q.x * s, -0.027, q.y + 0.001)),
                _hl(t, V3(q.x * s * 1.03, -0.034, q.y - 0.0004)),
                q.z,
                0.0008,
                k=0.001,
            )

    # JAW: its own surface, so the mouth can open.
    var jw = rig.bone("jaw")
    _ = m.cone(
        "mandible",
        jw,
        _hl(t, V3(0, -0.05, -0.015)),
        _hl(t, V3(0, -0.049, 0.095)),
        0.016,
        0.0105,
        k=0,
        part=JAW,
    )
    _ = m.cone(
        "mandible",
        jw,
        _hl(t, V3(0, -0.049, 0.095)),
        _hl(t, V3(0, -0.0328, 0.1142)),
        0.0105,
        0.0062,
        k=0.006,
        part=JAW,
    )
    for s in [1.0, -1.0]:  # pragma: no branch
        _ = m.cone(
            "mandible",
            jw,
            _hl(t, V3(0.036 * s, -0.044, -0.03)),
            _hl(t, V3(0.0105 * s, -0.0315, 0.1135)),
            0.013,
            0.007,
            k=0.02,
            part=JAW,
        )
    _ = m.ell(
        "chin",
        jw,
        _hl(t, V3(0, -0.038, 0.1005)),
        _hr(t, V3(0.0105, 0.006, 0.008)),
        k=0.01,
        part=JAW,
    )
    _ = m.ell(
        "lowerlip",
        jw,
        _hl(t, V3(0, -0.0262, 0.118)),
        _hr(t, V3(0.0125, 0.004, 0.0075)),
        k=0.01,
        part=JAW,
    )
    for s in [1.0, -1.0]:  # pragma: no branch
        _ = m.cone(
            "canine",
            jw,
            _hl(t, V3(0.0085 * s, -0.0355, 0.1112)),
            _hl(t, V3(0.0096 * s, -0.0212, 0.1142)),
            0.0036,
            0.0012,
            k=0.002,
            part=JAW,
        )
        for q in [  # pragma: no branch
            V3(0.0026, 0.1197, 0),
            V3(0.0062, 0.1182, 0),
            V3(0.0094, 0.1158, 0),
        ]:
            _ = m.cone(
                "tooth",
                jw,
                _hl(t, V3(q.x * s, -0.0295, q.y)),
                _hl(t, V3(q.x * s * 1.05, -0.0225, q.y + 0.0012)),
                0.0017,
                0.0009,
                k=0.001,
                part=JAW,
            )
        for row in _cheek_teeth():  # pragma: no branch
            _ = m.cone(
                "tooth",
                jw,
                _hl(t, V3(row[0] * s, row[2] - 0.002, row[1])),
                _hl(
                    t,
                    V3((row[0] - 0.0006) * s, row[2] + row[3], row[1] - 0.001),
                ),
                row[4],
                0.0009,
                k=0.0015,
                part=JAW,
            )

    # EARS: erect and triangular, set wide, with a cupped front.
    for side in [String("L"), String("R")]:  # pragma: no branch
        var s = 1.0 if side == "L" else -1.0
        var base = rig.j("earBase" + side)
        var tip = rig.j("earTip" + side)
        var up = normalize(tip - base)
        var facing = normalize(V3(0.32 * s, 0.05, 1))
        var lat = normalize(cross(up, facing))
        var eb = rig.bone("ear" + side)
        _ = ell_y(
            m,
            "ear",
            eb,
            lerp(base, tip, 0.22),
            up,
            V3(0.036, 0.036, 0.0095),
            lateral=lat,
            k=0.012,
            thin=True,
        )
        _ = ell_y(
            m,
            "ear",
            eb,
            lerp(base, tip, 0.55),
            up,
            V3(0.023, 0.034, 0.0068),
            lateral=lat,
            k=0.012,
            thin=True,
        )
        _ = ell_y(
            m,
            "ear",
            eb,
            lerp(base, tip, 0.84),
            up,
            V3(0.0085, 0.022, 0.0048),
            lateral=lat,
            k=0.01,
            thin=True,
        )
        _ = ell_y(
            m,
            "earinner",
            eb,
            lerp(base, tip, 0.36) + facing * 0.0085,
            up,
            V3(0.024, 0.034, 0.0062),
            lateral=lat,
            k=0.004,
            carve=True,
            thin=True,
        )
        _ = ell_y(
            m,
            "earinner",
            eb,
            lerp(base, tip, 0.68) + facing * 0.0062,
            up,
            V3(0.011, 0.026, 0.0045),
            lateral=lat,
            k=0.003,
            carve=True,
            thin=True,
        )

    # LEGS: long and lean, with big feet and elbows tucked in.
    for side in [String("L"), String("R")]:  # pragma: no branch
        var s = 1.0 if side == "L" else -1.0
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
            lerp(sc, sh, 0.5) + on_side(V3(0.008, 0, 0), s),
            sh - sc,
            V3(0.026, 0.1, 0.058),
            lateral=lat,
            k=0.06,
        )
        _ = m.cone("upperarm", hum, sh, e, 0.043, 0.032, k=0.06)
        _ = ell_y(
            m,
            "triceps",
            hum,
            lerp(sh, e, 0.55) + V3(0, 0, -0.03),
            e - sh,
            V3(0.03, 0.075, 0.036),
            lateral=lat,
            k=0.05,
        )
        _ = m.sphere("olecranon", rad, e + V3(0, 0.008, -0.024), 0.018, k=0.02)
        _ = m.cone("forearm", rad, e, w, 0.032, 0.019, k=0.025)
        _ = ell_y(
            m,
            "forearmmuscle",
            rad,
            lerp(e, w, 0.25) + on_side(V3(0.003, 0, 0.004), s),
            w - e,
            V3(0.028, 0.068, 0.032),
            lateral=lat,
            k=0.03,
        )
        _ = ell_y(
            m,
            "feather",
            rad,
            lerp(e, w, 0.45) + V3(0, 0, -0.018),
            w - e,
            V3(0.016, 0.06, 0.018),
            lateral=lat,
            k=0.02,
        )
        _ = m.sphere("wrist", meta, w + V3(0, 0, -0.003), 0.019, k=0.012)
        _ = m.sphere(
            "carpalpad", meta, w + V3(0, -0.008, -0.019), 0.009, k=0.01
        )
        _ = m.cone("pastern", meta, w, mc, 0.018, 0.018, k=0.012)
        _ = m.sphere(
            "dewclaw",
            meta,
            lerp(w, mc, 0.3) + on_side(V3(-0.016, 0, 0.002), s),
            0.006,
            k=0.005,
        )
        var dp = normalize(toe - mc)
        _ = ell_y(
            m,
            "paw",
            fpaw,
            mc + dp * 0.022 + V3(0, -0.006, 0),
            dp,
            V3(0.03, 0.04, 0.019),
            lateral=lat,
            k=0.014,
        )
        _ = m.sphere("pad", fpaw, mc + V3(0, -0.025, 0.012), 0.013, k=0.01)
        _toes(
            m,
            fpaw,
            toe,
            s,
            1.0,
            0.95,
            0.0122,
            0.0115,
            0.011,
            0.0032,
            0.0012,
            0.011,
        )

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
            lerp(hp, kn, 0.4) + on_side(V3(0.004, 0, -0.03), s),
            kn - hp,
            V3(0.042, 0.145, 0.095),
            lateral=lat,
            k=0.05,
        )
        _ = m.cone(
            "thighfront",
            fem,
            on_side(V3(0.04, 0.6, -0.15), s),
            kn + on_side(V3(-0.004, 0.055, 0.0), s),
            0.038,
            0.024,
            k=0.06,
        )
        _ = m.cone(
            "hamstring",
            fem,
            on_side(V3(0.045, 0.6, -0.36), s),
            lerp(kn, hk, 0.28) + V3(0, 0, -0.03),
            0.046,
            0.028,
            k=0.04,
        )
        _ = ell_y(
            m,
            "breeches",
            fem,
            lerp(hp, kn, 0.62) + on_side(V3(0.006, -0.01, -0.085), s),
            kn - hp,
            V3(0.03, 0.08, 0.03),
            lateral=lat,
            k=0.035,
        )
        _ = ell_y(
            m,
            "flankfold",
            fem,
            on_side(V3(0.05, 0.48, -0.13), s),
            V3(-0.03, 0.16, 0.1),
            V3(0.02, 0.08, 0.04),
            lateral=lat,
            k=0.06,
        )
        _ = m.sphere(
            "stifle",
            tib,
            kn + on_side(V3(0.002, 0.008, 0.006), s),
            0.017,
            k=0.04,
        )
        _ = m.cone(
            "shin",
            tib,
            lerp(kn, hk, 0.06) + on_side(V3(0, 0, 0.004), s),
            hk,
            0.023,
            0.017,
            k=0.03,
        )
        _ = ell_y(
            m,
            "calf",
            tib,
            lerp(kn, hk, 0.3) + on_side(V3(0.002, 0.01, -0.027), s),
            hk - kn,
            V3(0.025, 0.07, 0.03),
            lateral=lat,
            k=0.035,
        )
        _ = m.cone(
            "achilles",
            tib,
            lerp(kn, hk, 0.5) + V3(0, 0.01, -0.034),
            hk + V3(0, 0.012, -0.029),
            0.012,
            0.011,
            k=0.015,
        )
        _ = m.sphere(
            "calcaneus", mtar, hk + V3(0, 0.012, -0.025), 0.015, k=0.012
        )
        _ = m.sphere("hock", mtar, hk, 0.02, k=0.012)
        _ = m.cone("metatarsus", mtar, hk, mt, 0.018, 0.017, k=0.012)
        var dh = normalize(tt - mt)
        _ = ell_y(
            m,
            "paw",
            hpaw,
            mt + dh * 0.02 + V3(0, -0.006, 0),
            dh,
            V3(0.027, 0.037, 0.018),
            lateral=lat,
            k=0.014,
        )
        _ = m.sphere("pad", hpaw, mt + V3(0, -0.025, 0.01), 0.012, k=0.01)
        _toes(
            m,
            hpaw,
            tt,
            s,
            0.92,
            0.88,
            0.0115,
            0.0105,
            0.01,
            0.003,
            0.0011,
            0.01,
        )

    # TAIL: the brush, thickest past its middle.
    var tb = t.get("tailBrush")
    _ = m.cone(
        "tailroot",
        rig.bone("tail0"),
        V3(0, 0.645, -0.285),
        rig.j("tail1"),
        0.032,
        _tail_radius(0.1, tb),
        k=0.04,
    )
    for i in range(TAIL_SEGS):  # pragma: no branch
        _ = m.cone(
            "tail",
            rig.bone("tail" + String(i)),
            rig.j("tail" + String(i)),
            rig.j("tail" + String(i + 1)),
            _tail_radius(Float64(i) / Float64(TAIL_SEGS), tb),
            _tail_radius(Float64(i + 1) / Float64(TAIL_SEGS), tb),
            k=0.012,
            thin=i >= TAIL_SEGS - 1,
        )


def _toes(
    mut m: SdfModel,
    bone: BoneId,
    toe: V3,
    s: Float64,
    spread: Float64,
    claw_spread: Float64,
    toe_y: Float64,
    toe_r: Float64,
    claw_y: Float64,
    claw_ra: Float64,
    claw_rb: Float64,
    claw_len: Float64,
) raises:
    var toe_x: List[Float64] = [-0.021, -0.0072, 0.0072, 0.021]
    var toe_z: List[Float64] = [-0.011, 0, 0, -0.011]
    for i in range(4):  # pragma: no branch
        _ = m.sphere(
            "toe",
            bone,
            V3(toe.x + toe_x[i] * spread * s, toe_y, toe.z - 0.009 + toe_z[i]),
            toe_r,
            k=0.007,
        )
    for i in range(4):  # pragma: no branch
        var x = toe.x + toe_x[i] * claw_spread * s
        _ = m.cone(
            "claw",
            bone,
            V3(x, claw_y, toe.z + toe_z[i]),
            V3(x, 0.004, toe.z + claw_len + toe_z[i]),
            claw_ra,
            claw_rb,
            k=0.002,
        )


def _hr(t: Traits, r: V3) -> V3:
    return V3(r.x * t.get("headW") * HS, r.y * HS, r.z * HS)


comptime NOSE_C = V3(0.0, -0.0015, 0.1485)
comptime NOSE_R = V3(0.0182, 0.0122, 0.0095)


def _nose_axis() -> V3:
    return normalize(V3(0, -0.25, 1))


def _nose_at(lx: Float64, ly: Float64, push: Float64) -> V3:
    # A head-local point on the front lobe at lateral `lx` and height `ly`
    # along its tilted up axis, pushed `out` along its axis.
    var z = _nose_axis()
    var y = V3(0, z.z, -z.y)
    var q = (
        1.0
        - (lx / NOSE_R.x) * (lx / NOSE_R.x)
        - (ly / NOSE_R.y) * (ly / NOSE_R.y)
    )
    var lz = NOSE_R.z * sqrt(max(0.0, q)) + push
    return V3(
        NOSE_C.x + lx,
        NOSE_C.y + y.y * ly + z.y * lz,
        NOSE_C.z + y.z * ly + z.z * lz,
    )


def _nose_normal(lx: Float64, ly: Float64) -> V3:
    var z = _nose_axis()
    var y = V3(0, z.z, -z.y)
    var q = (
        1.0
        - (lx / NOSE_R.x) * (lx / NOSE_R.x)
        - (ly / NOSE_R.y) * (ly / NOSE_R.y)
    )
    var lz = NOSE_R.z * sqrt(max(1e-4, q))
    var gx = lx / (NOSE_R.x * NOSE_R.x)
    var gy = ly / (NOSE_R.y * NOSE_R.y)
    var gz = lz / (NOSE_R.z * NOSE_R.z)
    return normalize(V3(gx, y.y * gy + z.y * gz, y.z * gy + z.z * gz))


def _lip_margin() -> List[V3]:
    return [
        V3(0.018, -0.031, 0.095),
        V3(0.0158, -0.0218, 0.1235),
        V3(0.0112, -0.0198, 0.1362),
        V3(0, -0.0198, 0.1418),
    ]


def _cheek_teeth() -> List[List[Float64]]:
    # x, z, base y, height, radius: P2 to P4 and the carnassial.
    return [
        [0.0128, 0.086, -0.041, 0.0045, 0.0028],
        [0.0137, 0.073, -0.041, 0.0055, 0.0032],
        [0.0146, 0.059, -0.0405, 0.006, 0.0036],
        [0.0149, 0.043, -0.0395, 0.0065, 0.0044],
    ]


def wolf_look(t: Traits) -> EyeLook:
    """Return the wolf's eye colors: amber, or blue-gray in a pup.

    Args:
        t: The individual.

    Returns:
        The look.
    """
    if t.juvenile() > 0.0:
        return EyeLook(
            V3(0.1, 0.13, 0.17),
            V3(0.2, 0.25, 0.32),
            V3(0.06, 0.07, 0.09),
            V3(0.2, 0.15, 0.11),
            0.4,
            0.0,
        )
    return EyeLook(
        V3(0.36, 0.2, 0.035),
        V3(0.58, 0.33, 0.06),
        V3(0.15, 0.07, 0.014),
        V3(0.2, 0.15, 0.11),
        0.4,
        0.0,
    )


def _swatches() -> List[String]:
    return [
        String("saddle"),
        "flank",
        "lowFlank",
        "cape",
        "capePale",
        "mane",
        "maneDark",
        "legOuter",
        "legInner",
        "belly",
        "throat",
        "cheek",
        "brow",
        "crown",
        "muzzleTop",
        "earBack",
        "earRim",
        "earInner",
        "tailTop",
        "tailTip",
        "tailUnder",
        "rump",
        "paw",
        "gland",
        "legLine",
    ]


def _morph(variant: Int) -> List[Int]:
    if variant == BLACK:
        return [
            0x3E3632,
            0x6E6053,
            0x766757,
            0x3A3330,
            0x564B42,
            0x4A413A,
            0x3A3330,
            0x3A3330,
            0x443C36,
            0x62574E,
            0x544A42,
            0x4A423C,
            0x3A332E,
            0x403833,
            0x3E3632,
            0x3A3330,
            0x1E1A18,
            0x4A423C,
            0x3A3330,
            0x1C1816,
            0x4E453E,
            0x6E6053,
            0x3A3330,
            0x1C1816,
            0x2A2522,
        ]
    if variant == PALE:
        return [
            0xC6B797,
            0xD9D0BB,
            0xE2DAC7,
            0xCDBF9F,
            0xEBE5D6,
            0xDDD4C0,
            0xC9BC9F,
            0xE2D9C6,
            0xECE6D8,
            0xECE6D8,
            0xEFE9DD,
            0xEFE9DD,
            0xCAB897,
            0xD1C5AB,
            0xD2C19F,
            0xCDBB9A,
            0x9D8C70,
            0xE8E1D2,
            0xC0AF8D,
            0x8C7B62,
            0xE6DFCD,
            0xE6DFCD,
            0xE2D9C6,
            0x9A886C,
            0xD2C5A8,
        ]
    if variant == TAWNY:
        return [
            0x4D3D30,
            0xA88A68,
            0xB89A78,
            0x62503F,
            0xD2BF9F,
            0x8A7258,
            0x5C4A3A,
            0xC09A70,
            0xD8C4A8,
            0xD8C4A8,
            0xDECBB0,
            0xD9C7AD,
            0x8C6444,
            0x7E6650,
            0x927052,
            0xA67448,
            0x3A2C22,
            0xC6B69C,
            0x6A5440,
            0x1C1612,
            0xC6AD8A,
            0xCDB592,
            0xC9AB86,
            0x221A14,
            0x5E4834,
        ]
    return [
        0x3A3330,
        0xAE9A86,
        0xC0AD97,
        0x4E4744,
        0xD6CBBB,
        0x8A7F76,
        0x514842,
        0xC4A888,
        0xE2D8C8,
        0xE2D8C8,
        0xD9CFBE,
        0xDBD2C3,
        0x6A635B,
        0x6C6660,
        0x837262,
        0x9A8068,
        0x2E2724,
        0xC2B8AA,
        0x6E6152,
        0x141110,
        0xCDBCA4,
        0xCFC0AA,
        0xCFB99C,
        0x1A1614,
        0x5A4A3C,
    ]


def wolf_palette(t: Traits) raises -> Palette:
    """Return one wolf's palette: its morph, toned and warmed.

    A gray wolf's tone runs from cream-gray toward the pale morph to dark
    and grizzled toward the black one, keeping its pale mask and belly.
    A pup's coat is washed into a sooty, uniform natal gray-brown.

    Args:
        t: The individual.

    Returns:
        The palette, in linear light.

    Raises:
        Error: If the palette tables differ in length.
    """
    var names = _swatches()
    var base = palette_of(names, _morph(t.variant))
    var pale = palette_of(names, _morph(PALE))
    var black = palette_of(names, _morph(BLACK))
    var tone = t.get("grayTone", 0.0) if t.variant == GRAY else 0.0
    var warm = t.get("coatWarmth", 0.0)
    var light = t.get("coatLightness", 0.0)
    var juv = t.juvenile()
    var pup_k = 0.45 if t.variant == BLACK else (
        1.9 if t.variant == PALE else 1.0
    )
    var pup = srgb(0x5B534C) * pup_k
    var out = Palette()
    for name in names:  # pragma: no branch
        var c = base.get(name)
        var keep_pale = (
            name == "cheek"
            or name == "throat"
            or name == "belly"
            or name == "legInner"
            or name == "earInner"
            or name == "capePale"
            or name == "rump"
            or name == "tailUnder"
        )
        if tone > 0.0:
            c = mix3(c, pale.get(name), 0.35 * tone)
        elif tone < 0.0 and not keep_pale:
            c = mix3(c, black.get(name), -0.25 * tone)
        c = V3(
            c.x * (1.0 + 0.1 * warm + light),
            c.y * (1.0 + 0.02 * warm + light),
            c.z * (1.0 - 0.1 * warm + light),
        )
        var masked = (
            name == "cheek"
            or name == "throat"
            or name == "belly"
            or name == "legInner"
            or name == "earInner"
        )
        var marked = name == "tailTip" or name == "earRim" or name == "gland"
        var keep = 0.35 if masked else (0.5 if marked else 0.12)
        c = mix3(c, pup, juv * (1.0 - keep))
        out.set(name, c)
    return out^


def _head_local(t: Traits, p: V3) -> V3:
    var x = (p.x - HEAD_O.x) / t.get("headW") / HS
    var y = (p.y - HEAD_O.y) / HS
    var z = (p.z - HEAD_O.z) / HS
    var mz = t.get("muzzle")
    return V3(x, y, MUZZLE_Z0 + (z - MUZZLE_Z0) / mz if z > MUZZLE_Z0 else z)


def wolf_paint(
    pal: Palette, t: Traits, tag: String, bone: String, s: CoatSample
) -> Paint:
    """Paint one vertex of a wolf.

    The gray wolf's pattern: a dark saddle of black-tipped guard hair from
    the withers into the tail top, a dark cape across the shoulders with a
    pale patch in front of it, a grizzled mane, a cream mask on the muzzle
    sides, cheeks and throat, a cream belly and inner legs, a dark tail
    gland and a black tail tip, black lips and nose.

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
    if tag == "nose" or tag == "nosetop" or tag == "nostril" or tag == "alar":
        var nostril = smoothstep(
            0.004, 0.0, abs(abs(p.x) - 0.0098)
        ) * smoothstep(0.0, -0.4, n.y)
        return Paint(mix3(srgb(0x1C1716), srgb(0x070606), nostril), NOSE)
    if tag == "claw":
        return Paint(srgb(0x2A2420), KERATIN)
    if tag == "tooth" or tag == "canine":
        return Paint(srgb(0xE6DCC6), KERATIN)
    if tag == "pad" or tag == "carpalpad":
        return Paint(srgb(0x1E1A18), SKIN)
    if tag == "eyelid" or tag == "eyesocket":
        return Paint(srgb(0x161210), SKIN)
    var mouth = (
        tag == "lip"
        or tag == "lipfront"
        or tag == "lowerlip"
        or tag == "commissure"
        or tag == "chin"
        or tag == "mandible"
        or tag == "whisker"
    )
    if mouth:
        # The black lip line: the upper lip's margin, rising from the
        # mouth corner to under the nose, and the lower lip under it.
        var h = _head_local(t, p)
        var margin = -0.047 + 0.024 * smoothstep(0.03, 0.14, h.z)
        var line = smoothstep(0.0045, 0.0025, abs(h.y - margin)) * smoothstep(
            0.015, 0.03, h.z
        )
        if line > 0.5:
            return Paint(srgb(0x231D1A), SKIN)
    var juv = t.juvenile()
    var c: V3
    var agouti = 0.45
    var dorsal = smoothstep(-0.05, 0.6, n.y)
    var ventral = smoothstep(-0.05, -0.65, n.y)
    if bone == "head" or bone == "jaw":
        var h = _head_local(t, p)
        var mask = t.get("mask")
        c = mix3(pal.get("cheek"), pal.get("crown"), dorsal)
        var muzzle_top = smoothstep(0.04, 0.07, h.z) * smoothstep(0.1, 0.5, n.y)
        c = mix3(c, pal.get("muzzleTop"), muzzle_top)
        var brow = (
            band(h.z, 0.0, 0.025, 0.045, 0.06)
            * smoothstep(0.02, 0.035, h.y)
            * smoothstep(0.035, 0.012, abs(abs(h.x) - 0.03))
        )
        c = mix3(c, pal.get("brow"), brow * 0.8)
        var cheek = smoothstep(0.0, -0.02, h.y) * smoothstep(
            0.15, 0.5, abs(n.x)
        ) + smoothstep(-0.03, -0.045, h.y)
        c = mix3(c, pal.get("cheek"), clamp(cheek * mask, 0.0, 1.0))
        if bone == "jaw":
            c = mix3(pal.get("throat"), pal.get("cheek"), 0.4)
        agouti = 0.35
    elif bone.startswith("ear"):
        var front = smoothstep(-0.1, 0.4, n.z)
        c = mix3(
            pal.get("earBack"),
            pal.get("earInner"),
            front if tag == "earinner" else front * 0.4,
        )
        var tip = smoothstep(0.82, 0.9, p.y)
        c = mix3(c, pal.get("earRim"), tip * (1.0 - front * 0.6))
        agouti = 0.2
    elif bone.startswith("tail"):
        # How far along the tail, from its root to the tip of the brush.
        var along = length(p - V3(0.0, 0.635, -0.31)) / (0.47 * t.get("tail"))
        c = mix3(
            pal.get("tailUnder"), pal.get("tailTop"), smoothstep(-0.4, 0.4, n.y)
        )
        var gland = band(along, 0.22, 0.28, 0.33, 0.4) * dorsal
        c = mix3(c, pal.get("gland"), gland)
        c = mix3(
            c, pal.get("tailTip"), smoothstep(0.8, 0.93, along + 0.04 * dorsal)
        )
    elif bone == "neck1" or bone == "neck2":
        c = mix3(pal.get("throat"), pal.get("mane"), smoothstep(-0.2, 0.5, n.y))
        c = mix3(c, pal.get("maneDark"), smoothstep(0.4, 0.9, n.y) * 0.7)
        agouti = 0.6
    elif is_limb(bone):
        var side = 1.0 if p.x >= 0.0 else -1.0
        var inner = smoothstep(0.1, -0.6, n.x * side)
        c = mix3(pal.get("legOuter"), pal.get("legInner"), inner)
        c = mix3(c, pal.get("paw"), smoothstep(0.08, 0.03, p.y))
        # The upper limb wears the body's colors: the thigh and the
        # shoulder are flank, the stocking starts at the elbow and knee.
        var high = smoothstep(0.3, 0.46, p.y)
        var body = mix3(
            pal.get("lowFlank"), pal.get("flank"), smoothstep(0.45, 0.6, p.y)
        )
        body = mix3(body, pal.get("belly"), ventral * 0.8)
        c = mix3(c, body, high)
        var front_leg = bone.startswith("radius") or bone.startswith(
            "metacarpus"
        )
        if front_leg:
            var line = smoothstep(0.35, 0.8, n.z) * band(
                p.y, 0.1, 0.16, 0.3, 0.36
            )
            c = mix3(c, pal.get("legLine"), line * t.get("legLine", 0.0))
        agouti = 0.1
    else:
        var saddle_reach = 0.25 - 0.15 * t.get("saddle", 0.0)
        c = mix3(
            pal.get("lowFlank"), pal.get("flank"), smoothstep(0.45, 0.6, p.y)
        )
        var saddle = smoothstep(
            saddle_reach - 0.2, saddle_reach + 0.25, n.y
        ) * smoothstep(0.32, 0.18, p.z)
        c = mix3(c, pal.get("saddle"), saddle)
        var cape = (
            smoothstep(0.16, 0.26, p.z)
            * smoothstep(0.42, 0.32, p.z)
            * smoothstep(0.1, 0.6, n.y)
        )
        c = mix3(c, pal.get("cape"), cape)
        var cape_pale = (
            smoothstep(0.3, 0.4, p.z)
            * smoothstep(0.3, 0.7, abs(n.x))
            * band(p.y, 0.5, 0.56, 0.64, 0.7)
        )
        c = mix3(c, pal.get("capePale"), cape_pale * 0.8)
        var bib = (
            smoothstep(0.25, 0.32, p.z)
            * smoothstep(0.56, 0.44, p.y)
            * smoothstep(0.08, 0.035, abs(p.x))
        )
        var belly = max(
            ventral * (smoothstep(0.6, 0.5, p.y) * 0.55 + 0.45), bib
        )
        c = mix3(c, pal.get("belly"), belly)
        var rump = smoothstep(-0.3, -0.37, p.z) * smoothstep(
            0.2, -0.5, n.y + 0.4 * n.z
        )
        c = mix3(c, pal.get("rump"), rump)
        agouti = 0.85 * saddle + 0.45 * (1.0 - saddle)
    if t.variant == BLACK:
        var frost = (
            t.get("frost", 0.0)
            * smoothstep(0.5, 0.6, p.z)
            * smoothstep(0.65, 0.5, p.y)
        )
        c = mix3(c, srgb(0x8A8580), frost * 0.4)
    c = grizzle(c, p, 120.0, 0.12 + 0.25 * agouti * (1.0 - juv))
    return Paint(c, FUR)
