# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The wild boar, Sus scrofa: procedural-animals' `species/boar/`.

A cloven-hoofed forager with a wedge-shaped body: massive high shoulders
slope to narrow hips. The long wedge head ends in the snout disc. The
coat is coarse and grizzled, with a dorsal mane of long bristles. Males
carry long tusks. The reference adult stands 0.75 m at the withers.
The morphs are the age classes: adult (72 %), yearling (14 %) and the
striped piglet (14 %). Adults are dark, black, brown or pale.
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
    grizzle,
    mix3,
    palette_of,
    srgb,
)
from extensions.sdf.ids import (
    BoneId,
    SurfacePart,
)
from extensions.animals.parts import (
    BODY,
    JAW,
    TEETH,
)
from extensions.sdf.sculpt import ell_y
from extensions.animals.kit import (
    EyeSpec,
    sculpt_eye_socket,
    is_limb,
    pick_weighted,
    aperture_tilt_along,
    draw_u32,
    imul32,
    stream_of,
)
from extensions.animals.noise import fbm3, ihash, vnoise3
from extensions.animals.options import (
    ADULT,
    JUVENILE,
    MALE,
    AnimalOptions,
    AnimalRandom,
)
from extensions.animals.rig import Rig, quadruped_bones, tail_chain
from extensions.sdf.field import SdfModel
from extensions.animals.traits import Traits, pick_sex
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
from std.math import asin, atan2, cos, pi, pow, sin, sqrt
from extensions.sdf.distance import ellipsoid_estimate, round_cone_estimate

comptime TAIL_SEGS = 6
# The head's origin: on the head's axis, level with the eyes.
comptime HEAD_O = V3(0.0, 0.555, 0.49)
# The head is pitched 40 degrees nose down: its forward and up axes.
comptime HZ = V3(0.0, -0.6427876096865393, 0.766044443118978)
comptime HY = V3(0.0, 0.766044443118978, 0.6427876096865393)
# The finest cell, at the `HERO` tier: the head's cell in the original.
comptime CELL = 0.0033
comptime EAR_BASE = V3(0.076, 0.066, -0.11)
comptime EAR_LEN = 0.125

# The age classes, in procedural-animals' order.
comptime ADULT_CLASS = 0
comptime YEARLING = 1
comptime PIGLET = 2

# The coats: the four adult morphs, then the two young coats.
comptime DARK = 0
comptime BLACK = 1
comptime BROWN = 2
comptime PALE = 3
comptime YEARLING_COAT = 4
comptime PIGLET_COAT = 5


def boar_variant_names() -> List[String]:
    """Return the boar's age classes.

    Returns:
        Adult, yearling and piglet.
    """
    return [String("adult"), "yearling", "piglet"]


def boar_traits(mut r0: AnimalRandom, options: AnimalOptions) raises -> Traits:
    """Draw one boar: procedural-animals' `variation`.

    The boar draws from its own stream, seeded from the first draw and
    the seed. Males are larger, with a shoulder shield and long tusks.
    Yearlings are red-brown with short tusks. Piglets are striped, with
    a big head, a short snout and no tusks.

    Args:
        r0: The individual's stream.
        options: The caller's sex, age and age class.

    Returns:
        The traits.

    Raises:
        Error: If the requested age class is not one of the three.
    """
    var mixed = draw_u32(r0) ^ imul32(options.seed, 0x9E3779B1) ^ 173
    var r = stream_of(mixed)
    if options.variant.value >= 3:
        raise Error("The boar has no such age class")
    var variant: Int
    if options.variant.value >= 0:
        variant = options.variant.value
    elif options.age == JUVENILE:
        variant = PIGLET if r.next() < 0.5 else YEARLING
    elif options.age == ADULT:
        variant = ADULT_CLASS
    else:
        var classes: List[Float64] = [72.0, 14.0, 14.0]
        variant = pick_weighted(r, classes)
    var piglet = variant == PIGLET
    var yearling = variant == YEARLING
    var sex = pick_sex(options.sex, r)
    var male = sex == MALE
    var coat: Int
    if piglet:
        coat = PIGLET_COAT
    elif yearling:
        coat = YEARLING_COAT
    else:
        var coats: List[Float64] = [55.0, 15.0, 15.0, 15.0]
        coat = pick_weighted(r, coats)
    var reg_k = 1.0
    if variant == ADULT_CLASS:
        var regions: List[Float64] = [80.0, 10.0, 10.0]
        var region = pick_weighted(r, regions)
        reg_k = 1.18 if region == 1 else (0.86 if region == 2 else 1.0)
    var t = Traits(sex, ADULT if variant == ADULT_CLASS else JUVENILE, variant)
    var base = 0.34 if piglet else (
        0.73 if yearling else (1.06 if male else 0.94)
    )
    t.set("size", base * reg_k * (1.0 + 0.045 * r.g()))
    t.set("coat", Float64(coat))
    var lower = 0.0
    var upper = 0.0
    var tusk_r = 0.0
    var curve = 0.0
    var adult_male = male and not yearling
    if not piglet:
        if adult_male:
            lower = 0.085 + 0.04 * r.next()
            upper = 0.04 + 0.015 * r.next()
            tusk_r = 0.0085 + 0.002 * r.next()
            curve = 0.75 + 0.25 * r.next()
        elif male:
            lower = 0.035 + 0.01 * r.next()
            upper = 0.018
            tusk_r = 0.006
            curve = 0.5
        else:
            lower = 0.02 if yearling else 0.03 + 0.012 * r.next()
            upper = 0.012
            tusk_r = 0.0055
            curve = 0.45
    t.set("tuskLower", lower)
    t.set("tuskUpper", upper)
    t.set("tuskR", tusk_r)
    t.set("tuskCurve", curve)
    var shield = 0.0
    var shielded = adult_male and not piglet
    if shielded:
        shield = 0.55 + 0.45 * r.next()
    t.set("shield", shield)
    var snout = 0.72 if piglet else 0.9
    if variant == ADULT_CLASS:
        snout = 1.0 + 0.05 * r.g()
    t.set("snout", snout)
    t.set("earSpread", r.next())
    t.set("winter", r.next())
    var mane = 0.4
    if not piglet:
        mane = (1.0 if male else 0.8) * (0.85 + 0.3 * r.next())
    t.set("mane", mane)
    t.set("coatShade", r.g())
    t.set("coatLightness", 0.1 * r.g())
    t.set("coatSeed", Float64(Int(r.next() * 1e6)))
    t.set("minThick", 0.004)
    var head = (
        1.06
        * (1.0 + 0.035 * r.g())
        * (1.18 if piglet else (1.06 if yearling else 1.0))
        * (1.05 if adult_male else 1.0)
    )
    t.warps.add(scale_about_warp(HEAD_O, head, 0.14, 0.26))
    t.warps.add(
        legs_warp((1.0 + 0.035 * r.g()) * (1.08 if piglet else 1.0), 0.3)
    )
    t.warps.add(
        length_warp(
            (1.0 + 0.035 * r.g()) * (0.86 if piglet else 1.0), -0.45, 0.25
        )
    )
    t.warps.add(
        girth_warp(
            (1.0 + 0.04 * r.g())
            * (1.05 if adult_male else 1.0)
            * (0.94 if piglet else 1.0),
            0.46,
            -0.5,
            0.35,
        )
    )
    return t^


def _hl(v: V3) -> V3:
    # Head-local to reference space: the head is pitched nose down.
    return V3(
        HEAD_O.x + v.x,
        HEAD_O.y + v.y * HY.y + v.z * HZ.y,
        HEAD_O.z + v.y * HY.z + v.z * HZ.z,
    )


def _hdir(v: V3) -> V3:
    return V3(v.x, v.y * HY.y + v.z * HZ.y, v.y * HY.z + v.z * HZ.z)


def _head_local(p: V3) -> V3:
    var d = p - HEAD_O
    return V3(d.x, dot(d, HY), dot(d, HZ))


def boar_eye(t: Traits) -> EyeSpec:
    """Return the boar's left eye: small, set high and far back, deep in
    bristly lids, looking out and a little forward.

    Args:
        t: The individual. Every boar has the same eye.

    Returns:
        The eye, head-local.
    """
    var a = 30.0 * pi / 180.0
    var dir = normalize(V3(cos(a), 0.0, 0.0) + HZ * sin(a) + HY * 0.12)
    var e = EyeSpec(
        _hl(V3(0.082, 0.024, 0.005)) - HEAD_O,
        0.0125,
        0.0025,
        atan2(dir.x, dir.z),
        asin(dir.y),
        0.0016,
        0.0118,
        0.0066,
        0.0,
        0.0,
        0.007,
        0.0094,
    )
    e.tilt = aperture_tilt_along(e, HEAD_O, HZ) - 0.05
    return e


def _ear_tip(t: Traits) -> V3:
    var d = normalize(V3(0.42 + 0.3 * t.get("earSpread", 0.5), 1.0, -0.05))
    return _hl(EAR_BASE) + d * EAR_LEN


def boar_rig(t: Traits) raises -> Rig:
    """Return the boar's skeleton in bind pose.

    Each leg ends in a pastern and a cloven hoof, as the horse's and the
    goat's do. The thin tail hangs against the buttocks.

    Args:
        t: The individual.

    Returns:
        The rig.

    Raises:
        Error: If a bone names a missing joint.
    """
    var rig = Rig()
    rig.set("nose", _hl(V3(0.0, -0.018, 0.305)))
    rig.set("occiput", _hl(V3(0.0, 0.0, -0.15)))
    rig.set("neckMid", V3(0.0, 0.575, 0.3))
    rig.set("neckBase", V3(0.0, 0.57, 0.2))
    rig.set("chestMid", V3(0.0, 0.575, 0.07))
    rig.set("thoraxRear", V3(0.0, 0.575, -0.1))
    rig.set("lumbarMid", V3(0.0, 0.565, -0.25))
    rig.set("lumbosacral", V3(0.0, 0.55, -0.37))
    rig.set("tailBase", V3(0.0, 0.535, -0.535))
    rig.set("scapTopL", V3(0.062, 0.68, 0.185))
    rig.set("shoulderL", V3(0.1, 0.475, 0.27))
    rig.set("elbowL", V3(0.1, 0.305, 0.17))
    rig.set("wristL", V3(0.085, 0.145, 0.18))
    rig.set("mcpL", V3(0.078, 0.058, 0.19))
    rig.set("fcoffinL", V3(0.078, 0.027, 0.212))
    rig.set("ftoeL", V3(0.078, 0.002, 0.25))
    rig.set("hipL", V3(0.085, 0.5, -0.38))
    rig.set("kneeL", V3(0.1, 0.31, -0.27))
    rig.set("hockL", V3(0.075, 0.16, -0.42))
    rig.set("mtpL", V3(0.07, 0.056, -0.405))
    rig.set("hcoffinL", V3(0.07, 0.027, -0.385))
    rig.set("htoeL", V3(0.07, 0.002, -0.347))
    rig.set("jawHinge", _hl(V3(0.0, -0.075, -0.07)))
    rig.set("jawTip", _hl(V3(0.0, -0.088, 0.255)))
    rig.set("earBaseL", _hl(EAR_BASE))
    rig.set("earTipL", _ear_tip(t))
    var angles: List[Float64] = [-35, -60, -72, -78, -82, -84]
    var lens: List[Float64] = [0.04, 0.04, 0.04, 0.038, 0.036, 0.034]
    tail_chain(rig, "tailBase", angles, lens)
    rig.mirror_joints()
    quadruped_bones(rig, TAIL_SEGS)
    # The pastern ends at the coffin joint, and the hoof runs on to the
    # toe.
    for side in [String("L"), String("R")]:
        rig.bones[rig.bone("fpaw" + side).value].tail = "fcoffin" + side
        rig.bones[rig.bone("hpaw" + side).value].tail = "hcoffin" + side
    for side in [String("L"), String("R")]:
        _ = rig.add_bone(
            "fhoof" + side, "fcoffin" + side, "ftoe" + side, "fpaw" + side
        )
        _ = rig.add_bone(
            "hhoof" + side, "hcoffin" + side, "htoe" + side, "hpaw" + side
        )
    return rig^


@fieldwise_init
struct _TuskPoint(Copyable, ImplicitlyCopyable, Movable):
    var p: V3
    var r: Float64
    var t: Float64


def _tusk_path(t: Traits, s: Float64, lower: Bool) -> List[_TuskPoint]:
    # One tusk's center line, in reference space. The lower tusk leaves
    # the lip behind the disc, rises, then curves back and out. The upper
    # one, the whetter, leaves the lip sideways and curves up.
    var out = List[_TuskPoint]()
    var size = t.get("tuskLower", 0.0) if lower else t.get("tuskUpper", 0.0)
    if not (size > 0.004):
        return out^
    var p = V3(0.04 * s, -0.086, 0.215) if lower else V3(
        0.04 * s, -0.052, 0.185
    )
    var d0 = normalize(V3(0.55 * s, 1.0, 0.1)) if lower else normalize(
        V3(s, -0.25, 0.25)
    )
    var d1 = normalize(V3(0.9 * s, 0.5, -0.5)) if lower else normalize(
        V3(0.35 * s, 1.0, -0.15)
    )
    var curve = 0.7 * t.get("tuskCurve", 0.0) if lower else 1.0
    var n = max(4, Int(round(10.0 * min(1.4, size / 0.09))))
    var ds = size / Float64(n)
    var rb = t.get("tuskR", 0.0) * (1.0 if lower else 0.9)
    for i in range(n + 1):
        var f = Float64(i) / Float64(n)
        var u = min(1.0, pow(f, 1.1) * curve)
        var d = normalize(d0 * (1.0 - u) + d1 * u)
        var r = rb * pow(1.0 - 0.88 * f, 0.7) + 0.0008
        out.append(_TuskPoint(_hl(p), r, f))
        p = p + d * ds
    return out^


def boar_sculpt(mut m: SdfModel, rig: Rig, t: Traits) raises:
    """Sculpt the boar: procedural-animals' `sculptBoar`, primitive for
    primitive.

    The mane of long bristles, which the original grows as fur, is
    sculpted here as a low crest along the spine.

    Args:
        m: The sculpt to add to.
        rig: The boar's rig in bind pose.
        t: The individual.

    Raises:
        Error: If the rig lacks a joint or a bone, or the sculpt refuses
            a primitive.
    """
    var young = t.juvenile() > 0.0
    var male = t.male() and not young
    var shield = t.get("shield", 0.0)
    var snout_l = t.get("snout")

    # TORSO: deep high forequarters, a laterally compressed barrel and
    # narrow sloping hindquarters.
    var sw = 1.0 + 0.12 * shield
    var chest = rig.bone("chest")
    var spine3 = rig.bone("spine3")
    var spine2 = rig.bone("spine2")
    var spine1 = rig.bone("spine1")
    var pelvis = rig.bone("pelvis")
    _ = m.ell(
        "forequarter",
        chest,
        V3(0, 0.51, 0.11),
        V3(0.15 * sw, 0.222, 0.25),
        axis=normalize(V3(0, 0.12, 1)),
        k=0,
    )
    _ = m.ell(
        "barrel",
        spine3,
        V3(0, 0.45, -0.03),
        V3(0.155, 0.205, 0.25),
        axis=normalize(V3(0, 0.05, 1)),
        k=0.06,
    )
    _ = m.ell(
        "abdomen", spine2, V3(0, 0.44, -0.22), V3(0.145, 0.17, 0.18), k=0.06
    )
    _ = m.ell("loin", spine1, V3(0, 0.48, -0.3), V3(0.115, 0.125, 0.13), k=0.06)
    _ = m.ell(
        "withers",
        chest,
        V3(0, 0.672, 0.1),
        V3(0.08 * sw, 0.07, 0.2),
        axis=normalize(V3(0, 0.1, 1)),
        k=0.07,
    )
    _ = m.ell(
        "back",
        spine3,
        V3(0, 0.62, -0.08),
        V3(0.095, 0.05, 0.2),
        axis=normalize(V3(0, 0.14, 1)),
        k=0.07,
    )
    _ = m.ell(
        "back",
        spine1,
        V3(0, 0.555, -0.3),
        V3(0.088, 0.045, 0.15),
        axis=normalize(V3(0, 0.12, 1)),
        k=0.07,
    )
    _ = m.ell(
        "pelvis", pelvis, V3(0, 0.455, -0.42), V3(0.102, 0.15, 0.14), k=0.05
    )
    _ = m.ell(
        "croup",
        pelvis,
        V3(0, 0.52, -0.42),
        V3(0.085, 0.06, 0.14),
        axis=normalize(V3(0, -0.35, 1)),
        k=0.05,
    )
    for s in [1.0, -1.0]:
        _ = m.ell(
            "ham",
            pelvis,
            V3(0.05 * s, 0.43, -0.47),
            V3(0.06, 0.11, 0.07),
            k=0.05,
        )
    # The male's shield: thick armor over the shoulders.
    if shield > 0.05:
        for s in [1.0, -1.0]:
            _ = m.ell(
                "shield",
                chest,
                V3(0.085 * s, 0.53, 0.1),
                V3(0.07 * shield + 0.01, 0.15, 0.17),
                k=0.07,
            )
    _ = m.ell(
        "brisket", chest, V3(0, 0.33, 0.19), V3(0.085, 0.075, 0.1), k=0.05
    )
    for s in [1.0, -1.0]:
        _ = m.ell(
            "pectoral",
            chest,
            V3(0.05 * s, 0.32, 0.24),
            V3(0.045, 0.06, 0.045),
            k=0.04,
        )
    # Sows: a double row of teats. Boars: the sheath.
    var sow = not t.male() and not young
    if sow:
        for s in [1.0, -1.0]:
            for i in range(5):
                var fi = Float64(i)
                _ = m.sphere(
                    "teat",
                    spine3 if i < 2 else spine2,
                    V3(0.035 * s, 0.25 + 0.004 * fi, 0.02 - 0.075 * fi),
                    0.007,
                    k=0.01,
                )
    if male:
        _ = m.ell(
            "sheath",
            spine2,
            V3(0, 0.255, -0.17),
            V3(0.018, 0.02, 0.04),
            axis=normalize(V3(0, 0.3, 1)),
            k=0.03,
        )

    # NECK: short, thick, merged into the shoulders.
    var nk = 1.0 + 0.12 * shield
    var n1 = rig.bone("neck1")
    var n2 = rig.bone("neck2")
    var h = rig.bone("head")
    _ = m.ell(
        "neck",
        n1,
        V3(0, 0.49, 0.27),
        V3(0.13 * nk, 0.17, 0.13),
        axis=normalize(V3(0, -0.25, 1)),
        k=0.06,
    )
    _ = m.ell(
        "neck",
        n2,
        V3(0, 0.5, 0.36),
        V3(0.105 * nk, 0.14, 0.1),
        axis=normalize(V3(0, -0.5, 1)),
        k=0.06,
    )
    _ = m.ell(
        "crest",
        n1,
        V3(0, 0.625, 0.28),
        V3(0.07 * nk, 0.06, 0.14),
        axis=normalize(V3(0, 0.2, 1)),
        k=0.06,
    )
    _ = m.cone(
        "throat", n1, V3(0, 0.37, 0.2), V3(0, 0.37, 0.32), 0.08, 0.075, k=0.05
    )
    _ = m.cone(
        "throat",
        n2,
        V3(0, 0.38, 0.33),
        _hl(V3(0, -0.12, -0.02)),
        0.075,
        0.065,
        k=0.05,
    )
    _ = m.ell(
        "throat",
        h,
        _hl(V3(0, -0.115, -0.075)),
        V3(0.068, 0.07, 0.115),
        axis=HZ,
        up=HY,
        k=0.05,
    )
    _ = m.ell(
        "throat",
        n1,
        V3(0, 0.36, 0.36),
        V3(0.085, 0.075, 0.1),
        axis=normalize(V3(0, -0.2, 1)),
        k=0.05,
    )

    # HEAD, in head-local coordinates: a high domed crown, a steep
    # forehead, a long snout tube to the flat disc, and deep jowls.
    _hell(m, h, "cranium", V3(0, 0.02, -0.08), V3(0.092, 0.078, 0.105), 0.03)
    _hell(m, h, "poll", V3(0, 0.04, -0.14), V3(0.084, 0.062, 0.065), 0.04)
    _hell(m, h, "forehead", V3(0, 0.03, -0.005), V3(0.068, 0.045, 0.075), 0.032)
    var eye = boar_eye(t)
    for s in [1.0, -1.0]:
        _hell(
            m,
            h,
            "jowl",
            V3(0.058 * s, -0.07, -0.06),
            V3(0.058, 0.095, 0.1),
            0.045,
        )
        _hell(
            m,
            h,
            "zygoma",
            V3(0.074 * s, -0.012, -0.03),
            V3(0.028, 0.034, 0.075),
            0.03,
        )
        _hell(
            m,
            h,
            "cheek",
            V3(0.044 * s, -0.045, 0.055),
            V3(0.038, 0.05, 0.075),
            0.035,
        )
        _hell(
            m,
            h,
            "brow",
            V3(0.066 * s, 0.043, 0.005),
            V3(0.018, 0.012, 0.026),
            0.015,
        )
        _ = sculpt_eye_socket(
            m,
            eye,
            HEAD_O,
            s,
            h,
            orbit_r=V3(0.013, 0.01, 0.009),
            orbit_at=V3(0.0, 0.001, 0.014),
            orbit_k=0.006,
        )
    _hell(
        m,
        h,
        "face",
        V3(0, -0.01, _hz(0.135, snout_l)),
        V3(0.045, 0.045, 0.12 * (0.6 + 0.4 * snout_l)),
        0.03,
    )
    _hell(
        m,
        h,
        "snout",
        V3(0, -0.016, _hz(0.22, snout_l)),
        V3(0.04, 0.042, 0.075 * snout_l + 0.01),
        0.025,
    )
    for s in [1.0, -1.0]:
        _hell(
            m,
            h,
            "upperlip",
            V3(0.034 * s, -0.056, _hz(0.13, snout_l)),
            V3(0.026, 0.029, 0.085 * snout_l + 0.01),
            0.02,
        )
        _hell(
            m,
            h,
            "tuskboss",
            V3(0.034 * s, -0.045, _hz(0.175, snout_l)),
            V3(0.018 + 0.006 * shield, 0.018, 0.022),
            0.02,
        )
    # The snout disc: a flat round plate facing forward and a little down.
    _hell(
        m,
        h,
        "disc",
        V3(0, -0.021, _hz(0.287, snout_l)),
        V3(0.043, 0.039, 0.016),
        0.01,
    )
    for s in [1.0, -1.0]:
        _ = m.ell(
            "nostril",
            h,
            _hl(V3(0.014 * s, -0.024, _hz(0.307, snout_l))),
            V3(0.0075, 0.011, 0.012),
            axis=normalize(_hdir(V3(0.15 * s, 0, 1))),
            up=HY,
            k=0.003,
            carve=True,
        )
    _hell(
        m,
        h,
        "rostrum",
        V3(0, -0.055, _hz(0.2, snout_l)),
        V3(0.032, 0.022, 0.07 * snout_l + 0.01),
        0.02,
    )

    # JAW: the lower lip and the chin.
    var jw = rig.bone("jaw")
    _hell(
        m,
        jw,
        "chin",
        V3(0, -0.094, _hz(0.12, snout_l)),
        V3(0.038, 0.025, 0.075 * snout_l + 0.02),
        0.0,
        JAW,
    )
    _hell(
        m,
        jw,
        "lowerlip",
        V3(0, -0.08, _hz(0.205, snout_l)),
        V3(0.027, 0.015, 0.042 * snout_l + 0.008),
        0.012,
        JAW,
    )
    for s in [1.0, -1.0]:
        _ = m.cone(
            "mandible",
            jw,
            _hl(V3(0.035 * s, -0.1, _hz(0.04, snout_l))),
            _hl(V3(0.025 * s, -0.085, _hz(0.19, snout_l))),
            0.022,
            0.018,
            k=0.015,
            part=JAW,
        )

    # TUSKS: their own rigid surfaces, the lower on the jaw, the upper on
    # the skull.
    for s in [1.0, -1.0]:
        for lower in [True, False]:
            var path = _tusk_path(t, s, lower)
            var bone = jw if lower else h
            for i in range(len(path) - 1):
                _ = m.cone(
                    "tusk",
                    bone,
                    path[i].p,
                    path[i + 1].p,
                    path[i].r,
                    path[i + 1].r,
                    k=0.002,
                    part=TEETH,
                )

    # EARS: erect, pointed and hairy, the cup open forward and out.
    for side in [String("L"), String("R")]:
        var s = 1.0 if side == "L" else -1.0
        var base = rig.j("earBase" + side)
        var tip = rig.j("earTip" + side)
        var up = normalize(tip - base)
        var ear_len = length(tip - base)
        var facing = normalize(HZ * 0.9 + V3(0.32 * s, -0.2, 0))
        var lat = normalize(cross(up, facing))
        var fc = normalize(cross(lat, up))
        var eb = rig.bone("ear" + side)
        var wd = 0.054
        _ = ell_y(
            m,
            "ear",
            eb,
            lerp(base, tip, 0.38),
            up,
            V3(wd, ear_len * 0.42, 0.009),
            lateral=lat,
            k=0.012,
            thin=True,
        )
        _ = ell_y(
            m,
            "eartip",
            eb,
            lerp(base, tip, 0.74),
            up,
            V3(wd * 0.52, ear_len * 0.26, 0.0065),
            lateral=lat,
            k=0.014,
            thin=True,
        )
        _ = ell_y(
            m,
            "earinner",
            eb,
            lerp(base, tip, 0.45) + fc * 0.0072,
            up,
            V3(wd * 0.72, ear_len * 0.38, 0.0062),
            lateral=lat,
            k=0.004,
            carve=True,
            thin=True,
        )
        _ = m.sphere("earbase", h, base - up * 0.008, 0.022, k=0.025)

    # LEGS: short and slim, on the tips of the claws.
    var lk = 1.0 + 0.1 * shield
    for side in [String("L"), String("R")]:
        var s = 1.0 if side == "L" else -1.0
        var lat = V3(s, 0, 0)
        var sc = rig.j("scapTop" + side)
        var sh = rig.j("shoulder" + side)
        var e = rig.j("elbow" + side)
        var w = rig.j("wrist" + side)
        var mc = rig.j("mcp" + side)
        var cf = rig.j("fcoffin" + side)
        var toe = rig.j("ftoe" + side)
        var hum = rig.bone("humerus" + side)
        var rad = rig.bone("radius" + side)
        var meta = rig.bone("metacarpus" + side)
        _ = ell_y(
            m,
            "scapmuscle",
            rig.bone("scapula" + side),
            lerp(sc, sh, 0.45) + on_side(V3(0.035, 0, -0.01), s),
            sh - sc,
            V3(0.03 * lk, 0.11, 0.075),
            lateral=lat,
            k=0.06,
        )
        _ = m.sphere(
            "shoulderpoint",
            hum,
            sh + on_side(V3(0.012, 0, 0.01), s),
            0.035,
            k=0.045,
        )
        _ = m.cone("upperarm", hum, sh, e, 0.048 * lk, 0.04 * lk, k=0.045)
        _ = ell_y(
            m,
            "triceps",
            hum,
            lerp(sh, e, 0.55) + on_side(V3(0.008, 0.01, -0.05), s),
            e - sh,
            V3(0.04 * lk, 0.08, 0.055),
            lateral=lat,
            k=0.05,
        )
        _ = m.sphere("olecranon", rad, e + V3(0, 0.012, -0.034), 0.026, k=0.025)
        _ = m.cone(
            "forearm", rad, e + V3(0, 0, -0.005), w, 0.043 * lk, 0.023, k=0.025
        )
        _ = ell_y(
            m,
            "forearmmuscle",
            rad,
            lerp(e, w, 0.28) + on_side(V3(0.004, 0, 0.006), s),
            w - e,
            V3(0.04 * lk, 0.07, 0.043 * lk),
            lateral=lat,
            k=0.025,
        )
        _ = m.cone(
            "forearmweb",
            rad,
            e + on_side(V3(-0.025, 0.035, -0.01), s),
            lerp(e, w, 0.3) + on_side(V3(-0.01, 0, 0), s),
            0.03,
            0.022,
            k=0.03,
        )
        _ = ell_y(
            m,
            "knee",
            meta,
            w + V3(0, 0, 0.002),
            V3(0, 1, 0),
            V3(0.022, 0.025, 0.022),
            lateral=lat,
            k=0.012,
        )
        _ = m.cone(
            "cannon",
            meta,
            w + V3(0, -0.01, 0),
            mc + V3(0, 0.01, 0),
            0.02,
            0.019,
            k=0.01,
        )
        _ = m.cone(
            "tendon",
            meta,
            w + V3(0, -0.015, -0.012),
            mc + V3(0, 0.012, -0.013),
            0.01,
            0.012,
            k=0.01,
        )
        _ = ell_y(
            m,
            "fetlock",
            meta,
            mc + V3(0, 0, -0.004),
            V3(0, 1, 0.3),
            V3(0.021, 0.021, 0.022),
            lateral=lat,
            k=0.01,
        )
        var fpaw = rig.bone("fpaw" + side)
        _dewclaws(m, fpaw, mc, s)
        _ = m.cone("pastern", fpaw, mc, cf, 0.017, 0.017, k=0.01)
        _hoof(m, rig.bone("fhoof" + side), cf, toe, 1.0)

        var hp = rig.j("hip" + side)
        var kn = rig.j("knee" + side)
        var hk = rig.j("hock" + side)
        var mt = rig.j("mtp" + side)
        var ch = rig.j("hcoffin" + side)
        var tt = rig.j("htoe" + side)
        var fem = rig.bone("femur" + side)
        var tib = rig.bone("tibia" + side)
        var mtar = rig.bone("metatarsus" + side)
        _ = ell_y(
            m,
            "thigh",
            fem,
            lerp(hp, kn, 0.42) + on_side(V3(0.02, 0, -0.03), s),
            kn - hp,
            V3(0.04 * lk, 0.13, 0.1),
            lateral=lat,
            k=0.06,
        )
        _ = m.cone(
            "thighfront",
            fem,
            on_side(V3(0.08, 0.53, -0.31), s),
            kn + on_side(V3(0.0, 0.03, 0.02), s),
            0.05,
            0.034,
            k=0.05,
        )
        _ = m.cone(
            "hamstring",
            fem,
            on_side(V3(0.05, 0.48, -0.52), s),
            lerp(kn, hk, 0.3) + V3(0, 0, -0.045),
            0.055,
            0.03,
            k=0.045,
        )
        _ = ell_y(
            m,
            "flankfold",
            fem,
            on_side(V3(0.095, 0.34, -0.21), s),
            V3(-0.1, 0.3, 0.12),
            V3(0.026, 0.07, 0.04),
            lateral=lat,
            k=0.05,
        )
        _ = m.sphere(
            "stifle",
            tib,
            kn + on_side(V3(0.004, 0.005, 0.014), s),
            0.03,
            k=0.035,
        )
        _ = ell_y(
            m,
            "gaskin",
            tib,
            lerp(kn, hk, 0.3) + on_side(V3(0.004, 0, -0.024), s),
            hk - kn,
            V3(0.042 * lk, 0.08, 0.052),
            lateral=lat,
            k=0.03,
        )
        _ = m.cone("shin", tib, lerp(kn, hk, 0.1), hk, 0.03, 0.02, k=0.025)
        _ = m.cone(
            "achilles",
            tib,
            lerp(kn, hk, 0.45) + V3(0, 0, -0.038),
            hk + V3(0, 0.03, -0.03),
            0.014,
            0.011,
            k=0.015,
        )
        _ = m.sphere(
            "calcaneus", mtar, hk + V3(0, 0.026, -0.028), 0.015, k=0.012
        )
        _ = ell_y(
            m,
            "hock",
            mtar,
            hk + V3(0, 0.004, -0.002),
            V3(0, 1, 0.25),
            V3(0.021, 0.03, 0.023),
            lateral=lat,
            k=0.015,
        )
        _ = m.cone(
            "cannon",
            mtar,
            hk + V3(0, -0.016, 0.002),
            mt + V3(0, 0.01, 0),
            0.02,
            0.019,
            k=0.01,
        )
        _ = m.cone(
            "tendon",
            mtar,
            hk + V3(0, -0.016, -0.013),
            mt + V3(0, 0.012, -0.013),
            0.01,
            0.012,
            k=0.01,
        )
        _ = ell_y(
            m,
            "fetlock",
            mtar,
            mt + V3(0, 0, -0.004),
            V3(0, 1, 0.3),
            V3(0.021, 0.021, 0.022),
            lateral=lat,
            k=0.01,
        )
        var hpaw = rig.bone("hpaw" + side)
        _dewclaws(m, hpaw, mt, s)
        _ = m.cone("pastern", hpaw, mt, ch, 0.017, 0.017, k=0.01)
        _hoof(m, rig.bone("hhoof" + side), ch, tt, 0.95)

    # TAIL: thin and hanging, with a tassel flattened side to side.
    for i in range(TAIL_SEGS):
        var t0 = Float64(i) / Float64(TAIL_SEGS)
        var t1 = Float64(i + 1) / Float64(TAIL_SEGS)
        var a = rig.j("tail" + String(i))
        var b = rig.j("tail" + String(i + 1))
        var tb = rig.bone("tail" + String(i))
        _ = m.cone(
            "tailhead" if i == 0 else "tail",
            tb,
            a,
            b,
            0.016 - 0.009 * t0,
            0.016 - 0.009 * t1,
            k=0.018 if i == 0 else 0.006,
            thin=i > 2,
        )
        if i >= TAIL_SEGS - 2:
            var d = normalize(b - a)
            _ = m.ell(
                "tassel",
                tb,
                lerp(a, b, 0.6),
                V3(
                    0.009,
                    0.016 + 0.004 * Float64(i - TAIL_SEGS + 2),
                    length(b - a) * 0.62,
                ),
                axis=d,
                up=normalize(cross(d, V3(1, 0, 0))),
                k=0.008,
                thin=True,
            )

    _mane(m, rig, t)


def _mane(mut m: SdfModel, rig: Rig, t: Traits) raises:
    # The mane: long bristles from the crown down the nape to mid-back,
    # standing up and back. The original grows them as fur; here they are
    # a crest of narrow, laterally flattened solids on the dorsal line.
    var k = t.get("mane") * (0.75 + 0.25 * t.get("winter", 0.5))
    var young = t.juvenile() > 0.0
    var tall = (0.016 if young else 0.05) * k
    var h = rig.bone("head")
    # The crest between the ears, on into the nape.
    _hell(
        m,
        h,
        "mane",
        V3(0, 0.1 + 0.4 * tall, -0.15),
        V3(0.022, 0.012 + tall, 0.05),
        0.03,
    )
    var spots: List[V3] = [
        V3(0.0, 0.66, 0.42),
        V3(0.0, 0.69, 0.34),
        V3(0.0, 0.715, 0.26),
        V3(0.0, 0.735, 0.18),
        V3(0.0, 0.745, 0.1),
        V3(0.0, 0.735, 0.02),
        V3(0.0, 0.7, -0.06),
        V3(0.0, 0.66, -0.14),
    ]
    var reach: List[Float64] = [0.5, 0.8, 1.0, 1.0, 1.0, 0.85, 0.6, 0.3]
    var bones: List[String] = [
        String("neck2"),
        "neck2",
        "neck1",
        "chest",
        "chest",
        "spine3",
        "spine3",
        "spine2",
    ]
    var seed = Int(t.get("coatSeed", 0.0))
    for i in range(len(spots)):
        var c = spots[i]
        # Each lock of bristles stands a little higher or lower.
        var jitter = 0.8 + 0.4 * ihash(seed, i, 7)
        var hi = tall * reach[i] * jitter
        _ = m.ell(
            "mane",
            rig.bone(bones[i]),
            V3(c.x, c.y + 0.3 * hi, c.z),
            V3(0.014 + 0.008 * reach[i], 0.014 + hi, 0.06),
            axis=normalize(V3(0, -0.2, 1)),
            k=0.03,
        )


def _hz(z: Float64, snout_l: Float64) -> Float64:
    # The snout's length varies ahead of 0.12 m head-local.
    return 0.12 + (z - 0.12) * snout_l if z > 0.12 else z


def _hell(
    mut m: SdfModel,
    bone: BoneId,
    tag: String,
    c: V3,
    r: V3,
    k: Float64,
    part: SurfacePart = BODY,
) raises:
    # A head-local ellipsoid, aligned with the pitched head.
    _ = m.ell(tag, bone, _hl(c), r, axis=HZ, up=HY, k=k, part=part)


def _dewclaws(mut m: SdfModel, bone: BoneId, mc: V3, s: Float64) raises:
    # Two horny claws behind the fetlock.
    for k in [1.0, -1.0]:
        var a = mc + V3(0.012 * k * s, -0.006, -0.02)
        _ = m.cone(
            "dewclaw",
            bone,
            a,
            a + V3(0.003 * k * s, -0.022, -0.01),
            0.0075,
            0.004,
            k=0.004,
        )


def _hoof(mut m: SdfModel, bone: BoneId, cf: V3, toe: V3, w: Float64) raises:
    # The cloven hoof: two pointed claws with a cleft between them, heel
    # bulbs behind, flat on the ground.
    var zc = (cf.z + toe.z) * 0.5
    for k in [1.0, -1.0]:
        var x = cf.x + 0.0105 * k * w
        var top = V3(x, cf.y + 0.008, cf.z - 0.004)
        var tip = V3(x - 0.003 * k, 0.005, toe.z - 0.003)
        var heel = V3(x, 0.008, cf.z - 0.014)
        _ = m.cone("hoof", bone, top, tip, 0.0112 * w, 0.0045 * w, k=0.006)
        _ = m.cone(
            "hoof",
            bone,
            heel,
            V3(tip.x, 0.006, zc + 0.006),
            0.0105 * w,
            0.008 * w,
            k=0.008,
        )
        _ = m.sphere(
            "heelbulb", bone, V3(x, 0.012, cf.z - 0.017), 0.0095 * w, k=0.008
        )
    _ = m.cone(
        "coronet",
        bone,
        cf + V3(0, 0.012, -0.01),
        cf + V3(0, 0.006, 0.008),
        0.0165 * w,
        0.0165 * w,
        k=0.008,
    )
    _ = m.ell(
        "cleft",
        bone,
        V3(cf.x, 0.006, zc + 0.013),
        V3(0.0022, 0.02, 0.03),
        k=0.002,
        carve=True,
    )
    _ = m.ell(
        "sole",
        bone,
        V3(cf.x, -0.1 + 0.001, zc),
        V3(0.1, 0.1, 0.1),
        k=0.002,
        carve=True,
    )


def boar_look(t: Traits) -> EyeLook:
    """Return the boar's eye colors: a dark brown iris, amber-brown in
    some individuals.

    Args:
        t: The individual.

    Returns:
        The look.
    """
    var s = Float64(Int(t.get("coatSeed", 0.0)) % 100) / 100.0
    if s < 0.7:
        return EyeLook(
            srgb(0x3B2618),
            srgb(0x4E331F),
            srgb(0x1E130C),
            V3(0.5, 0.45, 0.4),
            0.38,
            0.0,
        )
    return EyeLook(
        srgb(0x4A2E18),
        srgb(0x6A4524),
        srgb(0x2A1A0E),
        V3(0.5, 0.45, 0.4),
        0.38,
        0.0,
    )


def _swatches() -> List[String]:
    return [
        String("base"),
        "dorsal",
        "belly",
        "face",
        "snout",
        "legs",
        "mane",
        "band",
    ]


def _coat(coat: Int) -> List[Int]:
    if coat == BLACK:
        return [
            0x4A4542,
            0x33302E,
            0x433E3A,
            0x68625C,
            0x7A746C,
            0x1C1A1A,
            0x1E1C1B,
            0x1E1C1B,
        ]
    if coat == PALE:
        return [
            0x948A7E,
            0x72695F,
            0x867C70,
            0xA39A8E,
            0x9E968C,
            0x2E2A28,
            0x3A3430,
            0x3A3430,
        ]
    if coat == BROWN:
        return [
            0x7E6654,
            0x5A4A3C,
            0x6A5646,
            0x8E7E6C,
            0x8E806E,
            0x2A2420,
            0x352B24,
            0x352B24,
        ]
    if coat == YEARLING_COAT:
        return [
            0x86603E,
            0x6C4A30,
            0x8A6444,
            0x8E6644,
            0x7E5C40,
            0x4A3222,
            0x6A4428,
            0x6A4428,
        ]
    if coat == PIGLET_COAT:
        return [
            0xB07A4A,
            0x7A4E2C,
            0xD8B088,
            0xA8764A,
            0x94683E,
            0x8A5A36,
            0x6E4526,
            0x6E4526,
        ]
    return [
        0x6C625A,
        0x4A423C,
        0x524842,
        0x857C72,
        0x948A80,
        0x2A2826,
        0x2E2A27,
        0x2E2A27,
    ]


def boar_palette(t: Traits) raises -> Palette:
    """Return one boar's palette: its coat, shaded and lightened.

    Args:
        t: The individual.

    Returns:
        The palette, in linear light.

    Raises:
        Error: If the palette tables differ in length.
    """
    var coat = Int(t.get("coat", 0.0))
    var names = _swatches()
    var base = palette_of(names, _coat(coat))
    var k = t.get("coatShade", 0.0)
    var l = t.get("coatLightness", 0.0)
    var out = Palette()
    for name in names:
        var c = base.get(name)
        out.set(
            name,
            V3(
                c.x * (1.0 + 0.1 * k + l),
                c.y * (1.0 + 0.03 * k + l),
                c.z * (1.0 - 0.07 * k + l),
            ),
        )
    out.set("stripe", srgb(0xE4BF8E))
    out.set("disc", srgb(0x5A4038 if coat == PIGLET_COAT else 0x3A3440))
    out.set("hoof", srgb(0x26221F))
    out.set("tusk", srgb(0xEDE6D2))
    out.set("tuskBase", srgb(0xB7A585))
    return out^


def _agouti(coat: Int) -> Float64:
    var table: List[Float64] = [0.6, 0.55, 0.7, 0.8, 0.25, 0.0]
    return table[coat]


def _stripes(t: Traits, p: V3, face: Bool) -> Float64:
    # The piglet's stripes: the signed distance, in meters, to the pale
    # stripes. Longitudinal bands run round the body axis from behind the
    # ears to the rump, wobbling and breaking into dashes. On the face a
    # stripe runs from the eye along the side of the snout.
    var seed = Float64(Int(t.get("coatSeed", 0.0)) % 997) * 0.1
    if face:
        var h = _head_local(p)
        var ay = atan2(abs(h.x), h.y + 0.02)
        var rr = sqrt(h.x * h.x + (h.y + 0.02) * (h.y + 0.02))
        var d = (abs(ay - 1.05) - 0.07) * rr
        var noise = (
            fbm3(V3(h.x * 60.0 + seed, h.y * 60.0, h.z * 30.0), 2) - 0.5
        ) * 0.008
        return max(d, max((h.z - 0.2) * 0.3, (-0.08 - h.z) * 0.3)) + noise
    var yc = mix(0.47, 0.45, smoothstep(0.2, -0.4, p.z))
    var ang = atan2(abs(p.x), p.y - yc)
    var rad = sqrt(p.x * p.x + (p.y - yc) * (p.y - yc))
    var zf = smoothstep(0.42, 0.3, p.z) * smoothstep(-0.6, -0.5, p.z)
    var angles: List[Float64] = [0.26, 0.52, 0.79, 1.06, 1.33, 1.62]
    var widths: List[Float64] = [0.06, 0.055, 0.055, 0.055, 0.06, 0.07]
    var wob = (fbm3(V3(p.x * 9.0 + seed, p.y * 9.0, p.z * 5.0), 3) - 0.5) * 0.12
    var d = 1.0
    for i in range(6):
        var a = angles[i] + wob + 0.05 * sin(p.z * 6.0 + Float64(i))
        d = min(d, (abs(ang - a) - widths[i] * 0.5) * rad)
    var br = vnoise3(V3(p.z * 18.0 + seed, ang * 6.0, 3.1))
    d = max(d, (br - 0.8) * 0.05)
    return d * zf + (1.0 - zf) * max(d, 0.01 + 0.02 * (1.0 - zf))


def _tusk_paint(pal: Palette, t: Traits, p: V3) -> Paint:
    # Ivory, stained brownish at the base.
    var best = 1e9
    var along = 0.0
    for s in [1.0, -1.0]:
        for lower in [True, False]:
            var path = _tusk_path(t, s, lower)
            for i in range(len(path) - 1):
                var a = path[i].p
                var ab = path[i + 1].p - a
                var u = clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0)
                var dd = length(p - (a + ab * u))
                if dd < best:
                    best = dd
                    along = path[i].t + (path[i + 1].t - path[i].t) * u
    var c = mix3(
        pal.get("tuskBase"), pal.get("tusk"), smoothstep(0.1, 0.5, along)
    )
    c = c * (0.92 + 0.12 * vnoise3(p * 400.0))
    return Paint(c, KERATIN)


def boar_paint(
    pal: Palette, t: Traits, tag: String, bone: String, s: CoatSample
) -> Paint:
    """Paint one vertex of a boar.

    The coat is coarse and grizzled: a dark dorsal line, a paler belly, a
    mane darker than the back, grizzled cheeks and a paler snout, legs
    near black below the elbows and stifles. The snout disc is bare and
    dark, the tusks ivory and the hooves dark horn. A piglet wears cream
    stripes on rufous brown with dark bands between them.

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
    var coat = Int(t.get("coat", 0.0))
    var piglet = coat == PIGLET_COAT
    var snout_l = t.get("snout")
    if s.part == TEETH:
        return _tusk_paint(pal, t, p)
    var hoofy = tag == "hoof" or tag == "heelbulb" or tag == "dewclaw"
    if hoofy:
        var front = bone.startswith("f")
        var cf = V3(0.0, 0.027, 0.212) if front else V3(0.0, 0.027, -0.385)
        var horn = tag == "dewclaw" or p.y < cf.y + 0.006 + 0.35 * (p.z - cf.z)
        if horn:
            var c = pal.get("hoof")
            if tag == "heelbulb":
                c = mix3(c, V3(0.06, 0.05, 0.045), 0.5)
            return Paint(c, KERATIN)
    if tag == "teat":
        return Paint(V3(0.12, 0.08, 0.07), SKIN)
    var agouti = _agouti(coat)
    var c: V3
    var pd = 1.0
    var is_head = bone == "head" or bone == "jaw"
    if is_head:
        var h = _head_local(p)
        if tag == "nostril":
            return Paint(pal.get("disc") * 0.4, NOSE)
        # The snout disc: bare, dark and moist on its face.
        var plate = (
            tag == "disc" and h.z > _hz(0.265, snout_l) and dot(n, HZ) > 0.25
        )
        if plate:
            return Paint(pal.get("disc"), NOSE)
        var lid = tag == "eyelid" or tag == "eyesocket"
        if lid:
            return Paint(srgb(0x1A1514), SKIN)
        c = mix3(
            pal.get("dorsal"),
            pal.get("face"),
            smoothstep(-0.02, 0.1, h.z) * 0.8,
        )
        var side = smoothstep(0.02, 0.05, abs(h.x))
        c = mix3(
            c,
            pal.get("snout"),
            smoothstep(0.08, _hz(0.2, snout_l), h.z)
            * (1.0 - smoothstep(_hz(0.24, snout_l), _hz(0.28, snout_l), h.z))
            * (0.5 + 0.5 * side),
        )
        c = mix3(
            c,
            pal.get("dorsal"),
            smoothstep(0.01, 0.06, h.y) * smoothstep(0.1, -0.02, h.z) * 0.6,
        )
        var jowl = (
            smoothstep(0.0, -0.05, h.y)
            * smoothstep(0.09, -0.02, h.z)
            * smoothstep(0.03, 0.06, abs(h.x))
        )
        c = mix3(c, pal.get("face"), jowl * 0.5)
        c = mix3(c, pal.get("mane"), _mane_of(p, n) * t.get("mane") * 0.8)
        if bone == "jaw":
            c = mix3(c, pal.get("dorsal"), 0.35)
        # The disc's rim darkens toward the bare plate.
        c = mix3(
            c,
            pal.get("disc"),
            0.5 * smoothstep(_hz(0.25, snout_l), _hz(0.28, snout_l), h.z),
        )
        # The lip line: dark skin where the upper lip meets the jaw.
        var touch = _jaw_dist(h, snout_l) if bone == "head" else _lip_dist(
            h, snout_l
        )
        var lip = touch < 0.002 and h.z > 0.0
        if lip:
            return Paint(V3(0.03, 0.026, 0.024), SKIN)
        if piglet:
            pd = _stripes(t, p, True)
        agouti *= 0.7
    elif bone.startswith("ear"):
        var front = smoothstep(
            0.1,
            0.5,
            dot(
                n,
                normalize(
                    HZ * 0.9 + V3(0.32 * (1.0 if p.x > 0.0 else -1.0), -0.2, 0)
                ),
            ),
        )
        c = mix3(pal.get("dorsal"), pal.get("face"), 0.2)
        c = mix3(c, V3(0.05, 0.045, 0.04), 0.3 * front)
    elif bone.startswith("tail"):
        c = mix3(pal.get("dorsal"), pal.get("legs"), 0.3)
        if tag == "tassel":
            c = pal.get("mane")
    else:
        var up = clamp(n.y, -1.0, 1.0)
        c = mix3(
            pal.get("base"), pal.get("dorsal"), smoothstep(0.2, 0.95, up) * 0.8
        )
        var ventral = smoothstep(-0.2, -0.8, n.y) * smoothstep(0.4, 0.28, p.y)
        var neck = bone == "neck1" or bone == "neck2"
        if neck:
            ventral = smoothstep(0.0, -0.7, n.y) * 0.5
        var leg = 0.0
        if is_limb(bone):
            leg = 1.0
            var upper = (
                bone.startswith("scapula")
                or bone.startswith("humerus")
                or bone.startswith("femur")
            )
            if upper:
                leg = smoothstep(0.5, 0.36, p.y)
            var sd = 1.0 if p.x >= 0.0 else -1.0
            ventral = mix(
                ventral,
                smoothstep(0.1, -0.7, n.x * sd)
                * 0.5
                * smoothstep(0.2, 0.35, p.y),
                leg,
            )
        c = mix3(c, pal.get("belly"), ventral)
        c = mix3(c, pal.get("mane"), _mane_of(p, n) * t.get("mane") * 0.8)
        if leg > 0.0:
            c = mix3(
                c,
                pal.get("legs"),
                clamp(
                    leg * smoothstep(0.34, 0.2, p.y)
                    + (0.0 if piglet else 0.3 * leg),
                    0.0,
                    1.0,
                ),
            )
        if piglet:
            pd = _stripes(t, p, False)
            var dark = clamp(-pd / 0.012 + 1.6, 0.0, 1.0)
            c = mix3(
                c,
                pal.get("band"),
                0.55 * (1.0 - dark) * smoothstep(0.28, 0.45, p.y) * (1.0 - leg),
            )
            pd = pd + 0.4 * leg * smoothstep(0.32, 0.2, p.y)
        if tag == "mane":
            agouti = min(1.0, agouti + 0.2)
    if piglet:
        c = mix3(c, pal.get("stripe"), smoothstep(0.003, -0.003, pd))
    var cv = fbm3(p * 6.0, 3) - 0.5
    c = V3(
        c.x * (1.0 + 0.16 * cv), c.y * (1.0 + 0.13 * cv), c.z * (1.0 + 0.1 * cv)
    )
    # Coarse bristles: lock-to-lock streaks, then the pale tips.
    var st = vnoise3(V3(p.x * 160.0, p.y * 160.0, p.z * 25.0))
    c = c * (0.86 + 0.28 * st)
    c = grizzle(c, p, 140.0, 0.1 + 0.3 * agouti)
    return Paint(c, FUR)


def _mane_of(p: V3, n: V3) -> Float64:
    # The dorsal strip from the crown between the ears down the nape to
    # mid-back.
    var along = smoothstep(0.52, 0.38, p.z) * smoothstep(-0.22, -0.02, p.z)
    var across = 1.0 - smoothstep(0.025, 0.07, abs(p.x))
    return along * across * smoothstep(0.3, 0.7, n.y + 0.2)


def _jaw_dist(h: V3, snout_l: Float64) -> Float64:
    # The distance from a head-local point to the jaw's surface.
    var d = ellipsoid_estimate(
        h,
        V3(0.0, -0.094, _hz(0.12, snout_l)),
        V3(0.038, 0.025, 0.075 * snout_l + 0.02),
    )
    d = min(
        d,
        ellipsoid_estimate(
            h,
            V3(0.0, -0.08, _hz(0.205, snout_l)),
            V3(0.027, 0.015, 0.042 * snout_l + 0.008),
        ),
    )
    var sx = 1.0 if h.x >= 0.0 else -1.0
    return min(
        d,
        round_cone_estimate(
            h,
            V3(0.035 * sx, -0.1, _hz(0.04, snout_l)),
            V3(0.025 * sx, -0.085, _hz(0.19, snout_l)),
            0.022,
            0.018,
        ),
    )


def _lip_dist(h: V3, snout_l: Float64) -> Float64:
    # The distance from a head-local point to the upper lip and the
    # underside of the snout.
    var sx = 1.0 if h.x >= 0.0 else -1.0
    var d = ellipsoid_estimate(
        h,
        V3(0.034 * sx, -0.056, _hz(0.13, snout_l)),
        V3(0.026, 0.029, 0.085 * snout_l + 0.01),
    )
    d = min(
        d,
        ellipsoid_estimate(
            h,
            V3(0.0, -0.055, _hz(0.2, snout_l)),
            V3(0.032, 0.022, 0.07 * snout_l + 0.01),
        ),
    )
    return min(
        d,
        ellipsoid_estimate(
            h,
            V3(0.044 * sx, -0.045, 0.055),
            V3(0.038, 0.05, 0.075),
        ),
    )
