# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The white-tailed deer, Odocoileus virginianus: procedural-animals'
`species/deer/`.

The reference adult is a doe of 0.92 m at the withers. The legs are very
slender, with a small cloven hoof on its own bone. The ears are large and
mobile, the tail a broad white flag. Bucks carry antlers grown by age
class: a spike or a fork as yearlings, six to ten points later. Fawns are
spotted. The coat is summer red-brown or winter gray-brown.
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
    srgb,
)
from extensions.sdf.ids import BoneId
from extensions.animals.parts import (
    HORN,
    JAW,
)
from extensions.sdf.sculpt import ell_y
from extensions.animals.kit import (
    EyeSpec,
    eye_frame_of,
    sculpt_eye_socket,
    is_front_limb,
    is_hind_limb,
    is_limb,
    pick_weighted,
)
from extensions.animals.noise import cells3, fbm3, vnoise3
from extensions.animals.options import (
    ADULT,
    JUVENILE,
    AnimalOptions,
    AnimalRandom,
)
from extensions.animals.rig import Rig, tail_chain
from extensions.sdf.field import SdfModel
from extensions.animals.species.hoofed import (
    HeadFrame,
    eye_looking,
    head_ell,
    hoofed_bones,
    lens_distance,
    pitched_head,
)
from extensions.animals.traits import Traits, pick_sex
from extensions.sdf.vector import (
    V3,
    clamp,
    cross,
    dot,
    length,
    lerp,
    normalize,
    smoothstep,
    on_side,
)
from extensions.animals.warp import (
    girth_warp,
    legs_warp,
    length_warp,
    scale_about_warp,
)
from std.math import cos, floor, pi, sin
from extensions.sdf.distance import oriented_ellipsoid_estimate

comptime TAIL_SEGS = 6
# The head's origin: on its axis 0.09 m in front of the poll, level with
# the eyes. The head is pitched 50 degrees nose down in the bind pose.
comptime HEAD_O = V3(0.0, 1.1085584337802632, 0.5310393293626243)
# The finest cell, at the `HERO` tier: the head's cell in the original.
comptime CELL = 0.003
# How much further back the loin, flank and hindquarters sit than in a
# first, too boxy layout: `bz` maps that layout's z to the long body.
comptime LOIN = 0.1

# The coats.
comptime SUMMER = 0
comptime WINTER = 1

# The age classes.
comptime FAWN = 0
comptime DOE = 1
comptime YEARLING = 2
comptime PRIME = 3
comptime MATURE = 4

comptime FCOFFIN = V3(0.07, 0.032, 0.385)
comptime BURR = V3(0.024, 0.042, -0.022)


def _hf() -> HeadFrame:
    var f = pitched_head(V3(0.0, 1.2, 0.5), 50.0, 0.09)
    return HeadFrame(HEAD_O, f.hy, f.hz)


def _bz(z: Float64) -> Float64:
    return z - LOIN * smoothstep(-0.1, -0.25, z)


def _b(x: Float64, y: Float64, z: Float64) -> V3:
    return V3(x, y, _bz(z))


def deer_variant_names() -> List[String]:
    """Return the deer's coats.

    Returns:
        Summer and winter.
    """
    return [String("summer"), "winter"]


def deer_traits(mut r: AnimalRandom, options: AnimalOptions) raises -> Traits:
    """Draw one deer: procedural-animals' `variation`.

    Unless an age is requested, about one deer in eight is a fawn. Bucks
    are yearlings, prime or mature, larger and with heavier antlers and a
    swollen neck in rut with age. Summer bucks mostly carry antlers in
    velvet.

    Args:
        r: The individual's stream.
        options: The caller's sex, age and coat.

    Returns:
        The traits.

    Raises:
        Error: If the requested coat is neither summer nor winter.
    """
    if options.variant.value >= 2:
        raise Error("The deer has no such coat")
    var sex = pick_sex(options.sex, r)
    var age = options.age
    var asked = age == ADULT or age == JUVENILE
    if not asked:
        age = JUVENILE if r.next() < 0.12 else ADULT
    var coat = options.variant.value
    if coat < 0:
        coat = SUMMER if r.next() < 0.5 else WINTER
    var t = Traits(sex, age, coat)
    var fawn = t.juvenile() > 0.0
    var male = t.male()
    var age_class = FAWN if fawn else DOE
    var buck = male and not fawn
    if buck:
        var classes: List[Float64] = [30.0, 35.0, 35.0]
        age_class = YEARLING + pick_weighted(r, classes)
    t.set("ageClass", Float64(age_class))
    var buck_size = 1.0
    if age_class == YEARLING:
        buck_size = 0.97
    elif age_class == PRIME:
        buck_size = 1.05
    elif age_class == MATURE:
        buck_size = 1.12
    t.set(
        "size",
        (buck_size if male else 0.98)
        * (1.0 + 0.04 * r.g())
        * (0.52 if fawn else 1.0),
    )
    var antlers = male and not fawn
    t.set("antlers", 1.0 if antlers else 0.0)
    if antlers:
        _antlers(r, t, age_class)
        var velvet = False
        if coat == SUMMER:
            velvet = r.next() < 0.75
        t.set("velvet", 1.0 if velvet else 0.0)
    var type_ = r.g()
    var neck = 0.0
    if antlers:
        var rut = 0.7 if age_class == MATURE else (
            0.45 if age_class == PRIME else 0.15
        )
        neck = rut * (1.0 if coat == WINTER else 0.5)
    t.set("neck", neck)
    t.set("coatShade", r.g())
    t.set("coatLightness", 0.06 * r.g())
    t.set("coatSeed", Float64(Int(r.next() * 1e6)))
    t.set("minThick", 0.004)
    var grown = 0.0
    if age_class == PRIME:
        grown = 0.02
    elif age_class == MATURE:
        grown = 0.04
    var girth = 0.0
    if age_class == YEARLING:
        girth = 0.02
    elif age_class == PRIME:
        girth = 0.05
    elif age_class == MATURE:
        girth = 0.08
    t.warps.add(
        legs_warp(
            (1.0 + 0.03 * r.g() - 0.02 * type_) * (1.22 if fawn else 1.0), 0.5
        )
    )
    t.warps.add(
        length_warp(
            (1.0 + 0.03 * r.g() + grown) * (0.86 if fawn else 1.0), -0.5, 0.35
        )
    )
    t.warps.add(girth_warp(1.0 + 0.045 * type_ + girth, 0.68, -0.55, 0.42))
    if fawn:
        t.warps.add(scale_about_warp(HEAD_O, 1.28, 0.1, 0.26))
    else:
        t.warps.add(scale_about_warp(HEAD_O, 1.0 + 0.025 * r.g(), 0.2, 0.5))
    return t^


def _antlers(mut r: AnimalRandom, mut t: Traits, age_class: Int):
    # The antlers by age class: the main beam's length, its radius at the
    # burr, its spread, rise and curl, and the tines as rows of position
    # along the beam, length and outward lean.
    var tines = List[V3]()
    if age_class == YEARLING:
        if r.next() < 0.6:
            t.set("spike", 1.0)
            t.set("beam", 0.11 + 0.07 * r.next())
            t.set("antlerBase", 0.0105)
            t.set("antlerSeed", Float64(Int(r.next() * 1e6)))
            t.set("tines", 0.0)
            return
        t.set("spike", 0.0)
        t.set("beam", 0.2 + 0.05 * r.next())
        t.set("antlerBase", 0.012)
        t.set("spread", 0.85 + 0.1 * r.g())
        t.set("rise", 1.15)
        t.set("curl", 0.8)
        tines.append(V3(0.45, 0.07 + 0.03 * r.next(), 0.2))
    else:
        var mature = age_class == MATURE
        t.set("spike", 0.0)
        t.set(
            "beam", 0.44 + 0.08 * r.next() if mature else 0.33 + 0.07 * r.next()
        )
        var brow = r.next() < (0.9 if mature else 0.6)
        if brow:
            tines.append(V3(0.09, 0.04 + 0.05 * r.next(), 0.15))
        tines.append(V3(0.37, (0.13 if mature else 0.1) + 0.05 * r.next(), 0.3))
        var third = mature
        if not mature:
            third = r.next() < 0.55
        if third:
            tines.append(
                V3(0.6, (0.11 if mature else 0.08) + 0.04 * r.next(), 0.3)
            )
        if mature:
            if r.next() < 0.65:
                tines.append(V3(0.8, 0.06 + 0.04 * r.next(), 0.25))
        t.set("antlerBase", 0.022 if mature else 0.018)
        t.set("spread", (1.2 if mature else 1.08) + 0.1 * r.g())
        t.set("rise", 1.0 + 0.12 * r.g())
        t.set("curl", 1.0 + 0.12 * r.g())
    t.set("antlerSeed", Float64(Int(r.next() * 1e6)))
    t.set("tines", Float64(len(tines)))
    for i in range(len(tines)):
        t.set("tineT" + String(i), tines[i].x)
        t.set("tineL" + String(i), tines[i].y)
        t.set("tineLean" + String(i), tines[i].z)


def deer_eye(t: Traits) -> EyeSpec:
    """Return the deer's left eye: high on the side of the skull.

    The globe is about 27 mm and the opening 30 by 18 mm. The eye looks
    out and a little forward, its almond along the nasal line.

    Args:
        t: The individual. Every deer has the same eye.

    Returns:
        The eye, head-local.
    """
    return _eye()


def _eye() -> EyeSpec:
    var hf = _hf()
    var a = 18.0 * pi / 180.0
    var look = normalize(V3(cos(a), 0.0, 0.0) + hf.hz * sin(a))
    var e = eye_looking(
        hf,
        V3(0.05, 0.006, 0.0),
        look,
        0.015,
        0.003,
        0.0017,
        0.019,
        0.009,
        -0.0006,
        0.0082,
        0.0116,
    )
    # The roll that lays the almond's long axis along the nasal line, by
    # the original's search, then the inner corner a little lower.
    var best = 0.0
    var bd = -2.0
    var tilt = -1.6
    while tilt <= 1.6:
        e.tilt = tilt
        var f = eye_frame_of(e, HEAD_O, 1.0)
        var d = dot(f.x, hf.hz)
        if d > bd:
            bd = d
            best = tilt
        tilt += 0.005
    e.tilt = best - 0.18
    return e


def _ear_tip() -> V3:
    # The ears are carried up and out in a wide V, a little back.
    var a = 50.0 * pi / 180.0
    var up = V3(0.0, cos(a), -sin(a))
    var d = V3(0.85, 0.52 * up.y - 0.1, 0.52 * up.z - 0.14)
    var n = length(d)
    return _hf().at(V3(0.034, 0.03, -0.055) + d * (0.145 / n))


def deer_rig(t: Traits) raises -> Rig:
    """Return the deer's skeleton in bind pose.

    Landmarks are from a 0.92 m doe: point of shoulder 0.64 m, elbow 0.49,
    carpus 0.28, fetlock 0.085, stifle 0.54 and hock 0.33. The neck
    leaves the chest low, at the thoracic inlet. The tail hangs flat
    against the rump.

    Args:
        t: The individual. Every deer has the same reference rig.

    Returns:
        The rig.

    Raises:
        Error: If a bone names a missing joint.
    """
    var hf = _hf()
    var rig = Rig()
    rig.set("nose", hf.at(V3(0, -0.005, 0.19)))
    rig.set("occiput", hf.at(V3(0, -0.01, -0.085)))
    rig.set("neckMid", V3(0, 0.945, 0.425))
    rig.set("neckBase", V3(0, 0.7, 0.355))
    rig.set("chestMid", V3(0, 0.8, 0.2))
    rig.set("thoraxRear", V3(0, 0.81, -0.02))
    rig.set("lumbarMid", _b(0, 0.83, -0.2))
    rig.set("lumbosacral", _b(0, 0.845, -0.34))
    rig.set("tailBase", _b(0, 0.83, -0.56))
    rig.set("scapTopL", V3(0.055, 0.87, 0.26))
    rig.set("shoulderL", V3(0.095, 0.64, 0.405))
    rig.set("elbowL", V3(0.088, 0.495, 0.3))
    rig.set("wristL", V3(0.074, 0.28, 0.345))
    rig.set("mcpL", V3(0.07, 0.085, 0.35))
    rig.set("fcoffinL", FCOFFIN)
    rig.set("ftoeL", V3(0.07, 0.003, 0.43))
    rig.set("hipL", _b(0.085, 0.745, -0.38))
    rig.set("kneeL", _b(0.1, 0.54, -0.285))
    rig.set("hockL", _b(0.074, 0.33, -0.49))
    rig.set("mtpL", _b(0.068, 0.085, -0.455))
    rig.set("hcoffinL", _b(0.068, 0.031, -0.42))
    rig.set("htoeL", _b(0.068, 0.003, -0.377))
    rig.set("jawHinge", hf.at(V3(0, -0.045, -0.035)))
    rig.set("jawTip", hf.at(V3(0, -0.062, 0.17)))
    rig.set("earBaseL", hf.at(V3(0.034, 0.03, -0.055)))
    rig.set("earTipL", _ear_tip())
    var angles: List[Float64] = [-45, -62, -72, -78, -80, -80]
    var lens: List[Float64] = [0.04, 0.04, 0.04, 0.04, 0.04, 0.04]
    tail_chain(rig, "tailBase", angles, lens)
    rig.mirror_joints()
    hoofed_bones(rig, TAIL_SEGS)
    return rig^


def deer_sculpt(mut m: SdfModel, rig: Rig, t: Traits) raises:
    """Sculpt the deer: procedural-animals' `sculptDeer`, primitive for
    primitive.

    Args:
        m: The sculpt to add to.
        rig: The deer's rig in bind pose.
        t: The individual.

    Raises:
        Error: If the rig lacks a joint or a bone, or the sculpt refuses
            a primitive.
    """
    var neck_k = t.get("neck", 0.0)
    var hf = _hf()

    # TORSO: a slim barrel, a deep narrow chest, the belly tucked up, a
    # long loin and flank, the shoulder and hip only hinted.
    var cb = rig.bone("chest")
    var s3 = rig.bone("spine3")
    var s1 = rig.bone("spine1")
    var pb = rig.bone("pelvis")
    _ = m.ell(
        "ribcage",
        s3,
        V3(0, 0.665, 0.055),
        V3(0.155, 0.195, 0.345),
        axis=normalize(V3(0, 0.05, 1)),
        k=0,
    )
    _ = m.ell("girth", cb, V3(0, 0.64, 0.26), V3(0.13, 0.165, 0.13), k=0.05)
    _ = m.ell(
        "abdomen",
        rig.bone("spine2"),
        V3(0, 0.67, -0.19),
        V3(0.16, 0.165, 0.25),
        axis=normalize(V3(0, 0.14, -1)),
        k=0.06,
    )
    _ = m.ell(
        "flank", s1, V3(0, 0.73, _bz(-0.29)), V3(0.14, 0.125, 0.16), k=0.07
    )
    # The withers: a low ridge between the scapulae.
    _ = m.ell(
        "withers",
        cb,
        V3(0, 0.86, 0.24),
        V3(0.035, 0.055, 0.14),
        axis=normalize(V3(0, -0.2, 1)),
        k=0.08,
    )
    _ = m.ell("back", s3, V3(0, 0.845, -0.02), V3(0.085, 0.045, 0.27), k=0.07)
    _ = m.ell("loin", s1, V3(0, 0.855, -0.25), V3(0.095, 0.045, 0.2), k=0.07)
    # The croup is a little higher than the withers.
    _ = m.ell(
        "pelvis", pb, V3(0, 0.8, _bz(-0.41)), V3(0.138, 0.12, 0.15), k=0.05
    )
    _ = m.ell(
        "croup",
        pb,
        V3(0, 0.855, _bz(-0.4)),
        V3(0.095, 0.05, 0.16),
        axis=normalize(V3(0, -0.1, 1)),
        k=0.06,
    )
    for s in [1.0, -1.0]:
        _ = m.sphere(
            "hippoint", pb, V3(0.105 * s, 0.835, _bz(-0.29)), 0.025, k=0.07
        )
        _ = m.ell(
            "rump",
            pb,
            V3(0.065 * s, 0.77, _bz(-0.5)),
            V3(0.07, 0.11, 0.07),
            k=0.05,
        )
    # A narrow breast between the forelegs.
    _ = m.ell("brisket", cb, V3(0, 0.575, 0.31), V3(0.075, 0.085, 0.08), k=0.05)
    for s in [1.0, -1.0]:
        _ = m.ell(
            "pectoral",
            cb,
            V3(0.048 * s, 0.585, 0.365),
            V3(0.04, 0.06, 0.035),
            k=0.045,
        )

    # NECK: slender and flattened in does, swollen in rutting bucks.
    var nb = rig.j("neckBase")
    var nm = rig.j("neckMid")
    var occ = rig.j("occiput")
    var nd1 = normalize(nm - nb)
    var nd2 = normalize(occ - nm)
    var nk = 1.0 + 0.3 * neck_k
    var up1 = V3(0, 0.6, -1)
    var n1 = rig.bone("neck1")
    var n2 = rig.bone("neck2")
    _ = m.ell(
        "neck",
        n1,
        lerp(nb, nm, 0.15) + V3(0, 0.012, -0.012),
        V3(0.07 * nk, 0.1 * nk, 0.1),
        axis=nd1,
        up=up1,
        k=0.06,
    )
    _ = m.ell(
        "neck",
        n1,
        lerp(nb, nm, 0.65) + V3(0, -0.01, 0.005),
        V3(0.05 * nk, 0.085 * nk, 0.1),
        axis=nd1,
        up=up1,
        k=0.05,
    )
    _ = m.ell(
        "neck",
        n2,
        lerp(nm, occ, 0.5) + V3(0, -0.02, 0.01),
        V3(0.043 * (1.0 + 0.2 * neck_k), 0.066 * (1.0 + 0.2 * neck_k), 0.075),
        axis=nd2,
        up=up1,
        k=0.045,
    )
    _ = m.ell(
        "crest",
        n1,
        lerp(nb, nm, 0.55) + V3(0, 0.03 + 0.01 * neck_k, -0.04),
        V3(0.03 + 0.02 * neck_k, 0.03 + 0.015 * neck_k, 0.12),
        axis=nd1,
        k=0.05,
    )
    # The underline of the neck, from the breast to the throat latch.
    var thr = hf.at(V3(0, -0.068, -0.045))
    var breast = V3(0, 0.67, 0.36)
    _ = m.cone(
        "throat",
        n1,
        breast,
        lerp(breast, thr, 0.55),
        0.04 * nk,
        0.04 * nk,
        k=0.05,
    )
    _ = m.cone(
        "throat", n2, lerp(breast, thr, 0.5), thr, 0.04 * nk, 0.032, k=0.045
    )

    # HEAD, in head-local coordinates.
    var h = rig.bone("head")
    _ = head_ell(
        m, "cranium", h, hf, V3(0, 0.0, -0.035), V3(0.049, 0.04, 0.062), k=0.03
    )
    _ = head_ell(
        m, "poll", h, hf, V3(0, -0.005, -0.07), V3(0.036, 0.038, 0.035), k=0.03
    )
    _ = head_ell(
        m,
        "forehead",
        h,
        hf,
        V3(0, 0.014, 0.02),
        V3(0.046, 0.022, 0.058),
        k=0.025,
    )
    _ = head_ell(
        m, "face", h, hf, V3(0, 0.006, 0.1), V3(0.031, 0.021, 0.09), k=0.025
    )
    _ = head_ell(
        m,
        "lowerface",
        h,
        hf,
        V3(0, -0.024, 0.085),
        V3(0.034, 0.037, 0.085),
        k=0.03,
    )
    _ = head_ell(
        m, "muzzle", h, hf, V3(0, -0.014, 0.16), V3(0.027, 0.027, 0.032), k=0.02
    )
    _ = head_ell(
        m, "nose", h, hf, V3(0, -0.006, 0.182), V3(0.024, 0.021, 0.015), k=0.012
    )
    _ = head_ell(
        m,
        "upperlip",
        h,
        hf,
        V3(0, -0.034, 0.17),
        V3(0.018, 0.012, 0.022),
        k=0.012,
    )
    var eye = _eye()
    for s in [1.0, -1.0]:
        # The masseter, and the mandible's lower border to the chin.
        _ = head_ell(
            m,
            "cheek",
            h,
            hf,
            V3(0.031 * s, -0.04, -0.01),
            V3(0.024, 0.036, 0.05),
            k=0.025,
        )
        _ = m.cone(
            "mandible",
            h,
            hf.at(V3(0.027 * s, -0.068, -0.045)),
            hf.at(V3(0.017 * s, -0.052, 0.12)),
            0.014,
            0.01,
            k=0.02,
        )
        _ = head_ell(
            m,
            "brow",
            h,
            hf,
            V3(0.043 * s, 0.022, -0.002),
            V3(0.014, 0.01, 0.022),
            k=0.015,
        )
        _ = head_ell(
            m,
            "nostrilwing",
            h,
            hf,
            V3(0.019 * s, -0.012, 0.18),
            V3(0.011, 0.015, 0.016),
            k=0.01,
        )
        _ = sculpt_eye_socket(
            m,
            eye,
            HEAD_O,
            s,
            h,
            orbit_r=V3(0.017, 0.012, 0.01),
            orbit_at=V3(0.0, 0.001, 0.016),
            orbit_k=0.007,
        )
        # The preorbital gland: a dark slit before the inner corner.
        _ = head_ell(
            m,
            "preorbital",
            h,
            hf,
            V3(0.045 * s, -0.004, 0.034),
            V3(0.004, 0.0035, 0.011),
            k=0.004,
            axis_l=V3(-0.35 * s, -0.15, 1),
            carve=True,
        )
        # The nostrils: commas opening forward and out.
        _ = head_ell(
            m,
            "nostril",
            h,
            hf,
            V3(0.014 * s, -0.01, 0.194),
            V3(0.0045, 0.009, 0.007),
            k=0.003,
            axis_l=V3(0.3 * s, -0.2, 1),
            up_l=V3(0.5 * s, 1, 0),
            carve=True,
        )

    # JAW: the lower lip and the chin.
    var jw = rig.bone("jaw")
    _ = m.ell(
        "chin",
        jw,
        hf.at(V3(0, -0.051, 0.15)),
        V3(0.02, 0.014, 0.028),
        axis=hf.hz,
        up=hf.hy,
        k=0,
        part=JAW,
    )
    _ = m.ell(
        "lowerlip",
        jw,
        hf.at(V3(0, -0.043, 0.172)),
        V3(0.019, 0.01, 0.018),
        axis=hf.hz,
        up=hf.hy,
        k=0.01,
        part=JAW,
    )
    for s in [1.0, -1.0]:
        _ = m.cone(
            "mandible",
            jw,
            hf.at(V3(0.014 * s, -0.051, 0.115)),
            hf.at(V3(0.01 * s, -0.047, 0.158)),
            0.009,
            0.011,
            k=0.012,
            part=JAW,
        )

    # EARS: large, broad and cupped.
    for side in [String("L"), String("R")]:
        var s = 1.0 if side == "L" else -1.0
        var base = rig.j("earBase" + side)
        var tip = rig.j("earTip" + side)
        var up = normalize(tip - base)
        var facing = normalize(hf.dir(V3(0, 0.3, 1)) * 0.8 + V3(0.5 * s, 0, 0))
        var lat = normalize(cross(up, facing))
        var eb = rig.bone("ear" + side)
        _ = ell_y(
            m,
            "ear",
            eb,
            lerp(base, tip, 0.45),
            up,
            V3(0.045, 0.074, 0.011),
            lateral=lat,
            k=0.012,
            thin=True,
        )
        _ = ell_y(
            m,
            "eartip",
            eb,
            lerp(base, tip, 0.8),
            up,
            V3(0.028, 0.035, 0.008),
            lateral=lat,
            k=0.012,
            thin=True,
        )
        _ = ell_y(
            m,
            "earinner",
            eb,
            lerp(base, tip, 0.5) + facing * 0.009,
            up,
            V3(0.036, 0.068, 0.008),
            lateral=lat,
            k=0.004,
            carve=True,
            thin=True,
        )
        _ = m.sphere("earbase", h, base + up * -0.006, 0.017, k=0.02)

    # LEGS: very slender.
    for side in [String("L"), String("R")]:
        _foreleg(m, rig, side)
        _hind_leg(m, rig, side)

    # TAIL: broad, flat and hairy.
    for i in range(TAIL_SEGS):
        var a = rig.j("tail" + String(i))
        var b = rig.j("tail" + String(i + 1))
        var t0 = Float64(i) / Float64(TAIL_SEGS)
        # The tail is broadest in the middle.
        var w = 0.03 + 0.018 * sin(pi * min(1.0, 0.25 + t0 * 0.95))
        _ = ell_y(
            m,
            "tail",
            rig.bone("tail" + String(i)),
            lerp(a, b, 0.5),
            normalize(b - a),
            V3(w, 0.034, 0.016 - 0.004 * t0),
            k=0.04 if i == 0 else 0.012,
            thin=True,
        )
    _ = m.cone(
        "tailroot",
        rig.bone("tail0"),
        rig.j("tail0"),
        rig.j("tail2"),
        0.03,
        0.022,
        k=0.04,
    )

    if t.get("antlers", 0.0) > 0.0:
        _sculpt_antlers(m, h, t)


def _foreleg(mut m: SdfModel, rig: Rig, side: String) raises:
    var s = 1.0 if side == "L" else -1.0
    var lat = V3(s, 0, 0)
    var sc = rig.j("scapTop" + side)
    var sh = rig.j("shoulder" + side)
    var e = rig.j("elbow" + side)
    var w = rig.j("wrist" + side)
    var mc = rig.j("mcp" + side)
    var scap = rig.bone("scapula" + side)
    var hum = rig.bone("humerus" + side)
    var rad = rig.bone("radius" + side)
    var meta = rig.bone("metacarpus" + side)
    _ = ell_y(
        m,
        "scapmuscle",
        scap,
        lerp(sc, sh, 0.45) + on_side(V3(0.032, 0, -0.01), s),
        sh - sc,
        V3(0.04, 0.14, 0.08),
        lateral=lat,
        k=0.08,
    )
    _ = m.sphere(
        "shoulderpoint",
        hum,
        sh + on_side(V3(0.008, 0.0, 0.0), s),
        0.032,
        k=0.05,
    )
    _ = m.cone("upperarm", hum, sh + V3(0, 0, -0.01), e, 0.043, 0.042, k=0.05)
    _ = ell_y(
        m,
        "triceps",
        hum,
        lerp(sh, e, 0.55) + on_side(V3(0.005, 0.01, -0.05), s),
        e - sh,
        V3(0.05, 0.09, 0.06),
        lateral=lat,
        k=0.05,
    )
    _ = m.sphere("olecranon", rad, e + V3(0, 0.012, -0.038), 0.027, k=0.03)
    _ = m.cone("forearm", rad, e + V3(0, 0, -0.005), w, 0.04, 0.02, k=0.03)
    _ = ell_y(
        m,
        "forearmmuscle",
        rad,
        lerp(e, w, 0.22) + on_side(V3(0.004, 0, 0.006), s),
        w - e,
        V3(0.04, 0.094, 0.044),
        lateral=lat,
        k=0.03,
    )
    _ = m.cone(
        "forearmweb",
        rad,
        e + on_side(V3(-0.02, 0.035, -0.01), s),
        lerp(e, w, 0.3) + on_side(V3(-0.01, 0, 0), s),
        0.03,
        0.022,
        k=0.035,
    )
    # The knee (carpus), the cannon with its tendons, and the fetlock.
    _ = ell_y(
        m,
        "knee",
        meta,
        w + V3(0, 0.0, 0.002),
        V3(0, 1, 0),
        V3(0.021, 0.028, 0.02),
        lateral=lat,
        k=0.012,
    )
    _ = m.sphere("accessory", meta, w + V3(0, 0.014, -0.017), 0.011, k=0.01)
    _ = m.cone(
        "cannon",
        meta,
        w + V3(0, -0.01, 0.0),
        mc + V3(0, 0.01, 0.0),
        0.0135,
        0.012,
        k=0.01,
    )
    _ = m.cone(
        "tendon",
        meta,
        w + V3(0, -0.015, -0.012),
        mc + V3(0, 0.015, -0.013),
        0.009,
        0.01,
        k=0.01,
    )
    _ = ell_y(
        m,
        "fetlock",
        meta,
        mc + V3(0, 0.0, -0.004),
        V3(0, 1, 0.3),
        V3(0.016, 0.02, 0.019),
        lateral=lat,
        k=0.01,
    )
    _digit(
        m,
        rig.bone("fpaw" + side),
        rig.bone("fhoof" + side),
        mc,
        rig.j("fcoffin" + side),
        rig.j("ftoe" + side),
        1.0,
    )


def _hind_leg(mut m: SdfModel, rig: Rig, side: String) raises:
    var s = 1.0 if side == "L" else -1.0
    var lat = V3(s, 0, 0)
    var hp = rig.j("hip" + side)
    var kn = rig.j("knee" + side)
    var hk = rig.j("hock" + side)
    var mt = rig.j("mtp" + side)
    var fem = rig.bone("femur" + side)
    var tib = rig.bone("tibia" + side)
    var mtar = rig.bone("metatarsus" + side)
    _ = ell_y(
        m,
        "thigh",
        fem,
        lerp(hp, kn, 0.42) + on_side(V3(0.02, 0, -0.03), s),
        kn - hp,
        V3(0.055, 0.17, 0.11),
        lateral=lat,
        k=0.06,
    )
    _ = m.cone(
        "thighfront",
        fem,
        on_side(V3(0.1, 0.8, _bz(-0.28)), s),
        kn + on_side(V3(0.0, 0.03, 0.02), s),
        0.06,
        0.038,
        k=0.06,
    )
    _ = m.cone(
        "hamstring",
        fem,
        on_side(V3(0.06, 0.79, _bz(-0.53)), s),
        lerp(kn, hk, 0.3) + V3(0, 0, -0.045),
        0.06,
        0.032,
        k=0.05,
    )
    _ = ell_y(
        m,
        "flankfold",
        fem,
        on_side(V3(0.1, 0.6, _bz(-0.23)), s),
        V3(-0.1, 0.3, 0.12),
        V3(0.03, 0.08, 0.045),
        lateral=lat,
        k=0.06,
    )
    _ = m.sphere(
        "stifle", tib, kn + on_side(V3(0.005, 0.005, 0.016), s), 0.032, k=0.04
    )
    _ = ell_y(
        m,
        "gaskin",
        tib,
        lerp(kn, hk, 0.3) + on_side(V3(0.004, 0, -0.022), s),
        hk - kn,
        V3(0.04, 0.094, 0.05),
        lateral=lat,
        k=0.035,
    )
    _ = m.cone("shin", tib, lerp(kn, hk, 0.1), hk, 0.03, 0.018, k=0.03)
    _ = m.cone(
        "achilles",
        tib,
        lerp(kn, hk, 0.45) + V3(0, 0, -0.04),
        hk + V3(0, 0.035, -0.032),
        0.014,
        0.011,
        k=0.018,
    )
    _ = m.sphere("calcaneus", mtar, hk + V3(0, 0.035, -0.031), 0.015, k=0.014)
    _ = ell_y(
        m,
        "hock",
        mtar,
        hk + V3(0, 0.005, -0.004),
        V3(0, 1, 0.2),
        V3(0.02, 0.034, 0.024),
        lateral=lat,
        k=0.014,
    )
    _ = m.cone(
        "cannon",
        mtar,
        hk + V3(0, -0.02, 0.002),
        mt + V3(0, 0.01, 0.0),
        0.0145,
        0.012,
        k=0.01,
    )
    _ = m.cone(
        "tendon",
        mtar,
        hk + V3(0, -0.02, -0.014),
        mt + V3(0, 0.015, -0.013),
        0.009,
        0.01,
        k=0.01,
    )
    _ = ell_y(
        m,
        "fetlock",
        mtar,
        mt + V3(0, 0.0, -0.004),
        V3(0, 1, 0.3),
        V3(0.016, 0.02, 0.019),
        lateral=lat,
        k=0.01,
    )
    _digit(
        m,
        rig.bone("hpaw" + side),
        rig.bone("hhoof" + side),
        mt,
        rig.j("hcoffin" + side),
        rig.j("htoe" + side),
        0.95,
    )


def _digit(
    mut m: SdfModel,
    paw: BoneId,
    hoof: BoneId,
    mc: V3,
    c: V3,
    toe: V3,
    w: Float64,
) raises:
    # The pastern, two dew claws and a small cloven hoof: two pointed
    # claws with a cleft between them, the sole cut flat.
    _ = m.cone("pastern", paw, mc, c, 0.013 * w, 0.014 * w, k=0.008)
    for s in [1.0, -1.0]:
        _ = m.cone(
            "dewclaw",
            paw,
            mc + V3(0.009 * s, -0.012, -0.012),
            mc + V3(0.011 * s, -0.03, -0.022),
            0.0055,
            0.003,
            k=0.004,
        )
    var dir = normalize(toe - c)
    var heel = c + V3(0, -0.012, -0.012)
    for s in [1.0, -1.0]:
        _ = m.cone(
            "hoof",
            hoof,
            heel + V3(0.0085 * s * w, 0.004, 0),
            toe + V3(0.006 * s * w, 0.002, -0.004),
            0.0135 * w,
            0.005 * w,
            k=0.006,
        )
    _ = m.cone(
        "coronet",
        hoof,
        c + V3(0, 0.008, -0.006),
        c + dir * 0.01,
        0.016 * w,
        0.015 * w,
        k=0.008,
    )
    _ = m.sphere(
        "heelbulb", hoof, c + V3(0, -0.012, -0.018), 0.012 * w, k=0.008
    )
    _ = m.ell(
        "cleft",
        hoof,
        lerp(c, toe, 0.75) + V3(0, -0.006, 0),
        V3(0.0012, 0.02, 0.035),
        axis=dir,
        k=0.002,
        carve=True,
    )
    _ = m.ell(
        "sole",
        hoof,
        V3(c.x, -0.2 + 0.0015, (c.z + toe.z) * 0.5),
        V3(0.2, 0.2, 0.2),
        k=0.002,
        carve=True,
    )


def _catmull(pts: List[V3], n: Int) -> List[V3]:
    # Resample a Catmull-Rom curve through the points at `n + 1` stations.
    var out_pts = List[V3]()
    var seg = len(pts) - 1
    for i in range(n + 1):
        var u = Float64(i) / Float64(n) * Float64(seg)
        var k = min(seg - 1, Int(floor(u)))
        var t = u - Float64(k)
        var p0 = pts[max(0, k - 1)]
        var p1 = pts[k]
        var p2 = pts[k + 1]
        var p3 = pts[min(seg, k + 2)]
        var t2 = t * t
        var t3 = t2 * t
        out_pts.append(
            (
                p1 * 2.0
                + (p2 - p0) * t
                + (p0 * 2.0 - p1 * 5.0 + p2 * 4.0 - p3) * t2
                + (p1 * 3.0 - p0 - p2 * 3.0 + p3) * t3
            )
            * 0.5
        )
    return out_pts^


def _sample_at(pts: List[V3], t: Float64) -> V3:
    var u = clamp(t, 0.0, 1.0) * Float64(len(pts) - 1)
    var k = min(len(pts) - 2, Int(floor(u)))
    return lerp(pts[k], pts[k + 1], u - Float64(k))


def _sculpt_antlers(mut m: SdfModel, h: BoneId, t: Traits) raises:
    # The antlers: rigid bone on the head, their own surface. The main
    # beam leaves the burr up, out and back, then sweeps forward and in;
    # the tines rise near vertically from its top. Each side has its own
    # small asymmetry.
    var hf = _hf()
    var spike = t.get("spike", 0.0) > 0.0
    var r0 = t.get("antlerBase", 0.018)
    var seed = Int(t.get("antlerSeed", 1.0))
    var count = Int(t.get("tines", 0.0))
    for s in [1.0, -1.0]:
        var rr = AnimalRandom(
            (seed if seed != 0 else 1) * 31 + (7 if s > 0.0 else 13), 1, 0
        )
        var burr = hf.at(V3(BURR.x * s, BURR.y, BURR.z))
        var ln = t.get("beam", 0.3) * _jit(rr)
        var pts: List[V3]
        if spike:
            # The yearling's spike: near straight, up and a little out.
            pts = [
                V3(0, 0, 0),
                V3(0.12 * s, 0.5, -0.12),
                V3(0.2 * s, 0.97, -0.08),
            ]
        else:
            # The main beam in fractions of its length: out, up, forward.
            var sp = t.get("spread", 1.0) * _jit(rr)
            var ri = t.get("rise", 1.0)
            var cu = t.get("curl", 1.0)
            pts = [
                V3(0, 0, 0),
                V3(0.13 * sp * s, 0.24 * ri, -0.12),
                V3(0.38 * sp * s, 0.33 * ri, -0.08),
                V3(0.54 * sp * s, 0.37 * ri, 0.08 * cu),
                V3(0.5 * sp * s, 0.4 * ri, 0.28 * cu),
                V3(0.32 * sp * s, 0.43 * ri, 0.44 * cu),
            ]
        for i in range(len(pts)):
            pts[i] = burr + pts[i] * ln
        var beam = _catmull(pts, 8 if spike else 16)
        # The burr: a rough ring at the base, the pedicle into the skull.
        var d0 = normalize(beam[1] - beam[0])
        _ = m.cone(
            "burr",
            h,
            burr + d0 * -0.012,
            burr + d0 * 0.004,
            r0 * 1.12,
            r0 * 1.1,
            k=0.004,
            part=HORN,
        )
        var n = len(beam) - 1
        for i in range(n):
            var t0 = Float64(i) / Float64(n)
            var t1 = Float64(i + 1) / Float64(n)
            _ = m.cone(
                "beam",
                h,
                beam[i],
                beam[i + 1],
                _beam_r(r0, t0, spike),
                max(
                    0.0025,
                    _beam_r(r0, t1, spike) * (0.45 if i == n - 1 else 1.0),
                ),
                k=0.004,
                part=HORN,
            )
        if spike:
            continue
        for j in range(count):
            var tt = t.get("tineT" + String(j), 0.5)
            var b = _sample_at(beam, tt)
            var tangent = normalize(
                _sample_at(beam, min(1.0, tt + 0.03))
                - _sample_at(beam, max(0.0, tt - 0.03))
            )
            # Up, a little outward from the beam's curve, forward at the tip.
            var outward = normalize(cross(tangent, V3(0, 1, 0)))
            var flip = -1.0 if outward.x * s < 0.0 else 1.0
            var l = t.get("tineL" + String(j), 0.05) * _jit(rr)
            var lean = t.get("tineLean" + String(j), 0.2)
            var p2 = b + V3(0, 0.95 * l, 0) + outward * (flip * lean * l * 0.25)
            var ctrl: List[V3] = [
                b,
                b + V3(0, 0.5 * l, 0),
                p2,
                p2 + V3(0, 0.05 * l, 0.12 * l),
            ]
            var tine = _catmull(ctrl, 6)
            var rb = r0 * (0.75 - 0.4 * tt)
            var k = len(tine) - 1
            for i in range(k):
                var u0 = Float64(i) / Float64(k)
                var u1 = Float64(i + 1) / Float64(k)
                _ = m.cone(
                    "tine",
                    h,
                    tine[i],
                    tine[i + 1],
                    max(0.0025, rb * (1.0 - 0.8 * u0)),
                    max(0.0022, rb * (1.0 - 0.8 * u1)),
                    k=0.008 if i == 0 else 0.003,
                    part=HORN,
                )


def _jit(mut rr: AnimalRandom) -> Float64:
    # The left-right asymmetry of the antlers.
    return 1.0 + (rr.next() - 0.5) * 0.12


def _beam_r(r0: Float64, t: Float64, spike: Bool) -> Float64:
    return r0 * (1.0 - 0.55 * t**1.3) * ((1.0 - 0.55 * t) if spike else 1.0)


def deer_look(t: Traits) -> EyeLook:
    """Return the deer's eye colors: a dark brown iris, a horizontal bar.

    Args:
        t: The individual. Every deer has the same eyes.

    Returns:
        The look.
    """
    return EyeLook(
        srgb(0x160D08),
        srgb(0x2A1A10),
        srgb(0x0E0805),
        V3(0.5, 0.45, 0.4),
        0.3,
        -2.5,
    )


def _coat_hexes(t: Traits) -> List[Int]:
    # Body, dorsal, side, head, forehead, face and legs.
    if t.juvenile() > 0.0:
        return [
            0x93603E,
            0x7C5034,
            0xA06E4C,
            0x8C6646,
            0x6E4A30,
            0x8C7462,
            0x9A7656,
        ]
    if t.variant == SUMMER:
        return [
            0x9A6F50,
            0x825A3E,
            0xA87E5E,
            0x8E6C50,
            0x684A34,
            0x8E7A68,
            0x9E7C5C,
        ]
    return [
        0x988670,
        0x7A6A56,
        0xA8977F,
        0x928675,
        0x645240,
        0xA39D94,
        0x9E8A6E,
    ]


def deer_palette(t: Traits) raises -> Palette:
    """Return one deer's palette: its season's coat, shaded, and the
    landmarks the painter reads.

    Args:
        t: The individual.

    Returns:
        The palette, in linear light.

    Raises:
        Error: If the coat table is short.
    """
    var hex = _coat_hexes(t)
    var names: List[String] = [
        String("body"),
        "dorsal",
        "side",
        "head",
        "forehead",
        "face",
        "legs",
    ]
    if len(hex) != len(names):
        raise Error("A deer coat needs seven swatches")
    var k = t.get("coatShade", 0.0)
    var l = t.get("coatLightness", 0.0)
    var pal = Palette()
    for i in range(len(names)):
        var c = srgb(hex[i])
        pal.set(
            names[i],
            V3(
                c.x * (1.0 + 0.07 * k + l),
                c.y * (1.0 + 0.01 * k + l),
                c.z * (1.0 - 0.08 * k + l),
            ),
        )
    pal.set("white", srgb(0xEFEAE0))
    pal.set("spot", srgb(0xEEE4D0))
    pal.set("nose", srgb(0x1A1A1A))
    pal.set("band", srgb(0x1E1A18))
    pal.set("hoof", srgb(0x262220))
    pal.set("earRim", srgb(0x3A2E26))
    pal.set("earIn", srgb(0xEDE7DC))
    pal.set("antlerBurr", srgb(0x5E4A36))
    pal.set("antlerBeam", srgb(0x7E6650))
    pal.set("antlerTip", srgb(0xD8CCB4))
    pal.set("velvet", srgb(0x6B5445))
    # The landmarks: the left eye, the left ear and the burr.
    var e = _eye()
    var ef = eye_frame_of(e, HEAD_O, 1.0)
    pal.set("eyeC", ef.c + ef.y * e.off)
    pal.set("eyeX", ef.x)
    pal.set("eyeY", ef.y)
    pal.set("eyeZ", ef.z)
    var hf = _hf()
    var base = hf.at(V3(0.034, 0.03, -0.055))
    var tip = _ear_tip()
    var up = normalize(tip - base)
    var facing = normalize(hf.dir(V3(0, 0.3, 1)) * 0.8 + V3(0.5, 0, 0))
    var lat = normalize(cross(up, facing))
    pal.set("earBase", base)
    pal.set("earAxis", up)
    pal.set("earLen", V3(length(tip - base), 0, 0))
    pal.set("earFace", normalize(cross(lat, up)))
    pal.set("burr", hf.at(BURR))
    # The white throat patch on the upper throat, below the jaw.
    pal.set(
        "throat", lerp(hf.at(V3(0, -0.068, -0.045)), V3(0, 0.64, 0.39), 0.45)
    )
    return pal^


def _throat(pal: Palette, p: V3, n: V3, rx: Float64, ry: Float64) -> Float64:
    # An oval bib on the front of the throat. (Its depth is 0.12 m here,
    # 0.06 m in the original: this sculpt's throat skin lies about 8 cm in
    # front of the patch's center, so the shallower oval missed it.)
    var tc = pal.get("throat")
    if dot(n, normalize(V3(0, -0.35, 1))) < 0.1:
        return 1.0
    var q = (
        (p.x / rx) ** 2 + ((p.y - tc.y) / ry) ** 2 + ((p.z - tc.z) / 0.12) ** 2
    ) ** 0.5
    return q * 0.03 - 0.03


def _tail_side(bone: String, n: V3) -> Float64:
    # Which face of the flat tail a normal is on: the outer, brown face is
    # positive, the white underside negative.
    var angles: List[Float64] = [-45, -62, -72, -78, -80, -80]
    var i = 0
    for k in range(1, TAIL_SEGS):
        if bone == "tail" + String(k):
            i = k
    var a = angles[i] * pi / 180.0
    var d = V3(0, sin(a), -cos(a))
    return dot(n, normalize(cross(V3(1, 0, 0), d)))


# The painter's regions.
comptime R_BODY = 0
comptime R_NECK = 1
comptime R_HEAD = 2
comptime R_TAIL = 4
comptime R_EAR = 5


def deer_paint(
    pal: Palette, t: Traits, tag: String, bone: String, s: CoatSample
) -> Paint:
    """Paint one vertex of a deer.

    The coat is darker along the back and on the forehead, with a white
    belly, groin and inner legs, a white throat patch, a white eye ring,
    a white band behind the black nose, and a white chin with dark spots
    at the lip corners. The ears have dark rims and white hair inside. The
    tail is brown above with a white fringe and underside. The tarsal
    gland is a dark tuft in bucks. A fawn has rows of white spots along
    its back. Antlers are bone colored with pale tips, or in velvet.

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
    if s.part == HORN:
        return _paint_antler(pal, t, tag, p)
    var jag = (fbm3(p * 70.0, 2) - 0.5) * 0.012
    var leg = 1.0 if is_limb(bone) else 0.0
    var c: V3
    var wsdf = 1.0
    var on_head = bone == "head" or bone == "jaw"
    if on_head:
        return _paint_head(pal, t, tag, s, jag)
    if bone.startswith("ear"):
        c = _paint_ear(pal, bone, p, n)
    elif bone.startswith("tail"):
        # Brown on top, darker along the midline, a white fringe and
        # underside, a dark tip above.
        var ts = _tail_side(bone, n)
        c = mix3(
            pal.get("dorsal"), pal.get("body"), smoothstep(0.3, 0.9, abs(n.x))
        )
        var tip = bone == "tail4" or bone == "tail5"
        if tip:
            c = mix3(c, srgb(0x3A2C20), 0.4 * smoothstep(0.2, 0.9, ts))
        wsdf = min(ts + 0.25, 0.012 - abs(n.x) * 0.02) + jag * 0.5
    else:
        var region = R_NECK if bone == "neck1" or bone == "neck2" else R_BODY
        var hoofed = tag == "hoof" or tag == "heelbulb" or tag == "dewclaw"
        if hoofed:
            var coffin = FCOFFIN if is_front_limb(bone) else _b(
                0.068, 0.031, -0.42
            )
            var wall = tag == "dewclaw" or p.y < coffin.y + 0.006 + 0.35 * (
                p.z - coffin.z
            )
            if wall:
                var hc = pal.get("hoof")
                if tag == "heelbulb":
                    hc = mix3(hc, srgb(0x3A3430), 0.5)
                return Paint(hc, KERATIN)
        c = _paint_coat(pal, t, region, bone, p, n, leg)
        wsdf = _body_white(pal, region, bone, p, n, leg) + jag
    var white = smoothstep(0.002, -0.002, wsdf)
    c = mix3(c, pal.get("white"), white)
    var spotted = (
        t.juvenile() > 0.0 and leg < 0.3 and not bone.startswith("ear")
    )
    if spotted:
        c = mix3(c, pal.get("spot"), 0.92 * _fawn_spot(t, bone, p, n))
    return Paint(_fur(c, p), FUR)


def _fawn_spot(t: Traits, bone: String, p: V3, n: V3) -> Float64:
    # The fawn's spots: rows either side of the spine, thinning out down
    # the flanks, in reference space.
    var torso = not (
        bone == "neck1" or bone == "neck2" or bone.startswith("tail")
    )
    var on_back = (
        torso and n.y >= 0.0 and p.z > _bz(-0.52) and p.z < 0.3 and p.y > 0.66
    )
    if not on_back:
        return 0.0
    # (The spots are cell noise here, the original's are Poisson disks; they
    # are a little larger, so they read on the small fawn without fur.)
    var pitch = 0.04
    var cell = cells3(p * (1.0 / pitch), Int(t.get("coatSeed", 0.0)) % 991)
    var ax = abs(p.x)
    var row = min(abs(ax - 0.035), abs(ax - 0.075))
    var keep = row < 0.014 or cell.id < 0.4
    if not keep:
        return 0.0
    var radius = 0.008 + 0.003 * cell.id
    var wob = 0.15 * (vnoise3(p * 60.0) - 0.5)
    return smoothstep(
        radius * 1.15, radius * 0.85, cell.nearest * pitch * (1.0 + wob)
    )


def _paint_coat(
    pal: Palette,
    t: Traits,
    region: Int,
    bone: String,
    p: V3,
    n: V3,
    leg: Float64,
) -> V3:
    # Countershading: dark along the spine, lighter low on the flanks.
    var up = clamp(n.y, -1.0, 1.0)
    var c = mix3(
        pal.get("body"), pal.get("dorsal"), smoothstep(0.35, 0.95, up) * 0.85
    )
    c = mix3(c, pal.get("side"), smoothstep(0.0, -0.6, up) * 0.6)
    if region == R_NECK:
        c = mix3(c, pal.get("head"), 0.25)
    var chest = region == R_BODY and p.z > 0.3 and p.y < 0.66
    if chest:
        # The chest between the forelegs is darker.
        c = mix3(c, pal.get("dorsal"), 0.35 * smoothstep(0.3, 0.42, p.z))
    if leg > 0.0:
        var lc = mix3(c, pal.get("legs"), smoothstep(0.55, 0.3, p.y))
        if p.y < 0.35:
            lc = mix3(lc, pal.get("dorsal"), 0.25 * smoothstep(0.1, 0.8, n.z))
        c = lc
        var hock_leg = bone.startswith("tibia") or bone.startswith("metatarsus")
        if hock_leg:
            # The tarsal gland: a tuft inside the hock, dark in bucks; the
            # metatarsal gland a pale-rimmed tuft outside the cannon.
            var side = 1.0 if p.x >= 0.0 else -1.0
            var hk = _b(0.074, 0.33, -0.49)
            var dg = (
                ((p.y - hk.y - 0.015) / 0.028) ** 2
                + ((p.z - hk.z + 0.012) / 0.02) ** 2
            ) ** 0.5
            var tarsal = dg < 1.2 and n.x * side < -0.2
            if tarsal:
                var buck = t.male() and t.juvenile() == 0.0
                c = mix3(
                    c,
                    srgb(0x2E2218) if buck else srgb(0x6A5440),
                    smoothstep(1.2, 0.7, dg),
                )
            var dm = (
                ((p.y - (hk.y - 0.12)) / 0.018) ** 2
                + ((p.z - hk.z - 0.004) / 0.012) ** 2
            ) ** 0.5
            var meta = dm < 1.3 and n.x * side > 0.3
            if meta:
                c = mix3(
                    c,
                    srgb(0x4A3A2A) if dm < 0.7 else srgb(0xD8D0C0),
                    smoothstep(1.3, 0.9, dm),
                )
    return c


def _body_white(
    pal: Palette, region: Int, bone: String, p: V3, n: V3, leg: Float64
) -> Float64:
    # The white areas of the body as one signed field, negative inside.
    var d = _throat(pal, p, n, 0.036, 0.045)
    if region == R_BODY:
        # The belly, groin and insides of the legs, below the flank line.
        var belly = (
            p.y
            - (
                0.5
                + 0.05 * smoothstep(0.1, _bz(-0.35), p.z)
                + 0.06 * smoothstep(_bz(-0.2), _bz(-0.45), p.z)
            )
            + 0.06 * (n.y + 0.5)
            + 0.12 * smoothstep(0.1, 0.24, p.z)
        )
        if leg < 0.5:
            d = min(d, belly)
        if p.z < _bz(-0.5):
            # The buttocks: a white band inside the thighs under the tail.
            d = min(
                d,
                abs(p.x)
                - 0.04 * smoothstep(0.72, 0.6, p.y)
                + (1.0 if p.y > 0.72 else 0.0),
            )
    if leg > 0.0:
        # The inside of the hind leg is white down to the hock, of the
        # foreleg only the inside of the cannon.
        var side = 1.0 if p.x >= 0.0 else -1.0
        var hind = is_hind_limb(bone)
        var top = 0.5 if hind else 0.26
        var bottom = 0.36 if hind else 0.12
        var d_in = (n.x * side + 0.35) * 0.05
        d = min(
            d,
            d_in
            + ((p.y - top) * 0.5 if p.y > top else 0.0)
            + ((bottom - p.y) * 0.5 if p.y < bottom else 0.0),
        )
        var low = (
            bone.startswith("metacarpus")
            or bone.startswith("metatarsus")
            or bone.startswith("fpaw")
            or bone.startswith("hpaw")
        )
        var band = low and p.y < 0.075 and p.y > 0.035
        if band:
            # A white band above the hooves, in front of the pasterns.
            d = min(d, 0.012 - (0.075 - p.y) * 0.5 * smoothstep(-0.2, 0.3, n.z))
    return d


def _paint_ear(pal: Palette, bone: String, p: V3, n: V3) -> V3:
    # The coat's color outside with a dark rim, white hair inside.
    var sd = 1.0 if bone == "earL" else -1.0
    var pm = V3(p.x * sd, p.y, p.z)
    var nm = V3(n.x * sd, n.y, n.z)
    var front = dot(nm, pal.get("earFace"))
    var c = mix3(pal.get("head"), pal.get("face"), 0.4)
    var along = (
        dot(pm - pal.get("earBase"), pal.get("earAxis")) / pal.get("earLen").x
    )
    var edge = 1.0 - abs(front)
    c = mix3(
        c,
        pal.get("earRim"),
        clamp(
            smoothstep(0.55, 0.9, edge) * 0.7
            + 0.5 * smoothstep(0.8, 1.0, along),
            0.0,
            1.0,
        ),
    )
    if front > 0.25:
        c = mix3(
            c,
            pal.get("earIn"),
            smoothstep(0.25, 0.6, front) * 0.85 * smoothstep(1.0, 0.75, along),
        )
    return c


def _paint_antler(pal: Palette, t: Traits, tag: String, p: V3) -> Paint:
    # A dark rough burr and beam base, a lighter beam, polished pale
    # tips, fine grooves along the beam; or soft velvet while growing.
    var st = vnoise3(V3(p.x * 300.0, p.y * 90.0, p.z * 300.0))
    if t.get("velvet", 0.0) > 0.0:
        return Paint(pal.get("velvet") * (0.85 + 0.3 * st), FUR)
    var db = length(V3(abs(p.x), p.y, p.z) - pal.get("burr"))
    var c = mix3(
        pal.get("antlerBurr"),
        pal.get("antlerBeam"),
        smoothstep(0.012, 0.05, db),
    )
    c = mix3(c, pal.get("antlerTip"), smoothstep(0.1, 0.35, db) * 0.45)
    if tag == "tine":
        c = mix3(c, pal.get("antlerTip"), 0.2)
    return Paint(c * (0.85 + 0.3 * st), KERATIN)


def _paint_head(
    pal: Palette, t: Traits, tag: String, s: CoatSample, jag: Float64
) -> Paint:
    var p = s.p
    var n = s.n
    var hf = _hf()
    var h = hf.local(p)
    var hm = V3(abs(h.x), h.y, h.z)
    var ax = hm.x
    var jaw = s.part == JAW
    var buck = t.male() and t.juvenile() == 0.0
    var c = mix3(
        pal.get("head"), pal.get("face"), smoothstep(-0.02, 0.1, h.z) * 0.6
    )
    # A darker forehead patch, darker in bucks, and the dark nasal bridge.
    var fh = (
        smoothstep(0.015, 0.035, h.y)
        * smoothstep(0.09, 0.0, h.z)
        * smoothstep(-0.1, -0.04, h.z)
    )
    c = mix3(c, pal.get("forehead"), fh * (0.9 if buck else 0.55))
    c = mix3(
        c,
        pal.get("forehead"),
        smoothstep(0.012, 0.024, h.y)
        * smoothstep(0.02, 0.1, h.z)
        * smoothstep(0.17, 0.12, h.z)
        * 0.35
        * smoothstep(0.02, 0.0, ax),
    )
    if h.z < -0.07:
        c = mix3(c, pal.get("body"), smoothstep(-0.07, -0.11, h.z))
    # The nostrils and the black nose leather.
    var dn = oriented_ellipsoid_estimate(
        hm,
        V3(0.014, -0.01, 0.194),
        V3(0.3, -0.2, 1),
        V3(0.5, 1, 0),
        V3(0.0045, 0.009, 0.007),
    )
    if dn < 0.0025:
        return Paint(pal.get("nose"), NOSE)
    var leather = (h.z > 0.168 and h.y > -0.03 and tag != "upperlip") or (
        tag == "nose" and h.z > 0.16
    )
    if leather:
        var nz = smoothstep(0.168, 0.176, h.z)
        if nz > 0.5:
            return Paint(pal.get("nose"), NOSE)
        c = mix3(c, pal.get("band"), nz * 2.0)
    # The white areas: the chin and lower lip, the band behind the nose,
    # the eye ring and the throat patch.
    var d = -0.006 if jaw else 1.0
    var band = max(
        abs(h.z - 0.158) - 0.011 - 0.004 * smoothstep(0.0, -0.03, h.y),
        -0.03 - h.y,
    )
    d = min(d, band)
    var chin = h.y < -0.036 and h.z > 0.12
    if chin:
        d = min(d, (h.y + 0.036) * 0.5 - 0.002)
    var pm = V3(abs(p.x), p.y, p.z)
    var ec = pal.get("eyeC")
    var near_eye = (
        length(pm - ec) < 0.03 and dot(pm - ec, pal.get("eyeZ")) > -0.008
    )
    var de = lens_distance(
        pm, ec, pal.get("eyeX"), pal.get("eyeY"), 0.019, 0.009
    )
    if near_eye:
        d = min(d, abs(de + 0.0005) - 0.0075)
    d = min(d, _throat(pal, p, n, 0.034, 0.04))
    var flank = ax > 0.05 and h.z < 0.1
    if flank:
        d = max(d, 0.02)
    d += jag * 0.5
    # Dark spots at the corners of the lower lip.
    var lips = jaw or h.y < -0.035
    if lips:
        var dc = (
            ((ax - 0.014) / 0.01) ** 2 + ((h.z - 0.145) / 0.014) ** 2
        ) ** 0.5
        var corner = dc < 1.0 and ax > 0.006
        if corner:
            c = mix3(c, pal.get("band"), smoothstep(1.0, 0.6, dc))
            d = max(d, 0.004)
    # The lid margin is bare dark skin; the preorbital gland a dark slit.
    var lid = near_eye and abs(de) < 0.0014
    if lid:
        return Paint(srgb(0x1C1816), SKIN)
    var dg = oriented_ellipsoid_estimate(
        hm,
        V3(0.045, -0.004, 0.034),
        V3(-0.35, -0.15, 1),
        V3(0, 1, 0),
        V3(0.004, 0.0035, 0.011),
    )
    if dg < 0.003:
        c = srgb(0x2E2622)
        d = max(d, 0.003)
    c = mix3(c, pal.get("white"), smoothstep(0.002, -0.002, d))
    var rim = near_eye and abs(de) < 0.0035
    if rim:
        c = mix3(c, srgb(0x1C1816), 0.5)
    return Paint(_fur(c, p), FUR)


def _fur(c: V3, p: V3) -> V3:
    # Low-frequency color variation and a fine hair grain.
    var cv = fbm3(p * 7.0, 3) - 0.5
    var v = V3(
        c.x * (1.0 + 0.14 * cv), c.y * (1.0 + 0.12 * cv), c.z * (1.0 + 0.1 * cv)
    )
    return grizzle(v, p, 220.0, 0.06)
