# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The crow, Corvus brachyrhynchos: procedural-animals' `species/crow/`.

The proving species of the bird body plan. The reference adult is a
450 g American crow, 0.44 m from the bill tip to the tail tip. Morphs
are the American crow, the carrion crow, with a greener gloss and a
heavier bill, and the hooded crow, with a gray body. The seed draws the
American crow (75 %) or the carrion crow. The hooded crow comes only on
request.

procedural-animals binds the wings half open and renders the flight
feathers as cards. This port binds them folded, at rest, and sculpts
each flight feather, covert and rectrix as a fin.
"""

from extensions.animals.coat import (
    FEATHER,
    KERATIN,
    SCALES,
    SKIN,
    CoatSample,
    EyeLook,
    Paint,
    Palette,
    mix3,
    srgb,
)
from extensions.animals.parts import JAW
from extensions.sdf.sculpt import ell_y
from extensions.animals.kit import (
    EyeSpec,
    sculpt_eye_socket,
)
from extensions.animals.noise import fbm3
from extensions.animals.options import AnimalOptions, AnimalRandom
from extensions.animals.rig import Rig
from extensions.sdf.field import SdfModel
from extensions.animals.species.bird_rig import (
    Feather,
    WingPose,
    bird_bones,
    card_point,
    is_card,
    feather_fins,
    feather_frames,
    feather_joints,
    neck_chain,
    place_toe,
    primary,
    rectrix,
    secondary,
    wing_joints,
    wing_normal,
    wing_segment,
)
from extensions.animals.traits import Traits, pick_age, pick_sex
from extensions.sdf.vector import (
    V3,
    clamp,
    lerp,
    mix,
    normalize,
    smoothstep,
)
from extensions.animals.warp import (
    girth_warp,
    legs_warp,
    scale_about_warp,
)
from std.math import pow

comptime NECK_SEGS = 4
# How far the tail is fanned at rest: the motion data's `fanRest`.
comptime FAN_REST = 0.05
# The head's origin, between the eyes: the base layout moved down and
# back by the original's `HEAD_DROP`.
comptime HEAD_O = V3(0.0, 0.295, 0.103)
# The finest cell, at the `HERO` tier: the head's cell in the original.
comptime CELL = 0.00086

# The morphs, in procedural-animals' order.
comptime AMERICAN = 0
comptime CARRION = 1
comptime HOODED = 2


def crow_variant_names() -> List[String]:
    """Return the crow's morphs.

    Returns:
        American, carrion and hooded.
    """
    return [String("american"), "carrion", "hooded"]


def crow_traits(mut r: AnimalRandom, options: AnimalOptions) raises -> Traits:
    """Draw one crow: procedural-animals' `variation`.

    There is no plumage dimorphism: males are about 5 % larger. Juveniles
    are nearly adult-sized at fledging, but duller, fluffier and blue-gray
    eyed with a shorter tail.

    Args:
        r: The individual's stream.
        options: The caller's sex, age and morph.

    Returns:
        The traits.

    Raises:
        Error: If the requested morph is not one of the three.
    """
    var sex = pick_sex(options.sex, r)
    var age = pick_age(options.age)
    var variant: Int
    if options.variant.value >= 3:
        raise Error("The crow has no such color variant")
    if options.variant.value >= 0:
        variant = options.variant.value
    else:
        variant = AMERICAN if r.next() < 0.75 else CARRION
    var t = Traits(sex, age, variant)
    var juv = t.juvenile()
    var male = t.male()
    var size = (
        (1.03 if male else 0.97)
        * (1.0 + 0.045 * r.g())
        * (0.95 if juv > 0.0 else 1.0)
        * (1.0 if variant == AMERICAN else 1.06)
    )
    var bill = (
        (1.06 if variant == CARRION else 1.0)
        * (1.0 + 0.06 * r.g())
        * (1.03 if male else 1.0)
    )
    t.set("size", size)
    t.set("bill", bill)
    t.warps.add(legs_warp(1.0 + 0.04 * r.g(), 0.12))
    t.warps.add(scale_about_warp(V3(0.0, 0.292, 0.135), bill, 0.03, 0.06))
    var head_k = (1.0 + 0.03 * r.g()) * (1.06 if juv > 0.0 else 1.0)
    t.warps.add(scale_about_warp(HEAD_O, head_k, 0.03, 0.06))
    var girth = 1.0 + 0.05 * r.g() + (0.05 if juv > 0.0 else 0.0)
    t.warps.add(girth_warp(girth, 0.16, -0.08, 0.1, 0.04))
    t.set("wear", max(0.0, 0.25 * r.g() + (0.4 if juv > 0.0 else 0.1)))
    t.set("gloss", 1.0 + 0.12 * r.g() - (0.4 if juv > 0.0 else 0.0))
    t.set("tailK", 0.88 if juv > 0.0 else 1.0 + 0.03 * r.g())
    return t^


def crow_eye(t: Traits) -> EyeSpec:
    """Return the crow's left eye: lateral-frontal, with a round aperture.

    Args:
        t: The individual. The crow's eye does not vary.

    Returns:
        The eye, head-local.
    """
    _ = t.juvenile()
    return EyeSpec(
        V3(0.0185, 0.0005, 0.003),
        0.0056,
        0.0016,
        1.08,
        0.05,
        0.00045,
        0.0047,
        0.0006,
        0.0,
        0.0,
        0.0036,
        0.0044,
    )


def crow_look(t: Traits) -> EyeLook:
    """Return the crow's eye colors: a dark brown iris, blue-gray in a
    juvenile.

    Args:
        t: The individual.

    Returns:
        The look.
    """
    var sclera = V3(0.02, 0.02, 0.02)
    if t.juvenile() > 0.0:
        return EyeLook(
            srgb(0x3A4450), srgb(0x7D8CA0), srgb(0x3C4552), sclera, 0.44, 0.0
        )
    return EyeLook(
        srgb(0x120C09), srgb(0x2A1E18), srgb(0x100B09), sclera, 0.44, 0.0
    )


def _lengths() -> V3:
    return V3(0.067, 0.078, 0.058)


def _fold() -> WingPose:
    return WingPose(-82.0, 4.0, 80.0, 175.0, 174.0, 0.0, 0.0, 0.0)


def _glide() -> WingPose:
    return WingPose(5.0, 3.0, 8.0, 24.0, 14.0, 2.0, 1.0, 0.0)


def _feathers() -> List[Feather]:
    # 10 primaries (p5 to p10 emarginated "fingers"), 6 secondaries and 3
    # tertials, and 6 rectrices a side.
    var out = List[Feather]()
    var p: List[List[Float64]] = [
        [0.06, 0.158, 0.030, 80, 9, 0],
        [0.16, 0.166, 0.030, 71, 8, 0],
        [0.27, 0.177, 0.029, 62, 7, 0],
        [0.38, 0.190, 0.028, 53, 6, 0],
        [0.49, 0.205, 0.027, 44, 5, 0.5],
        [0.60, 0.222, 0.026, 36, 4, 0.9],
        [0.71, 0.228, 0.025, 28, 3, 1],
        [0.81, 0.222, 0.024, 20, 2, 1],
        [0.91, 0.200, 0.022, 12, 1, 1],
        [1.00, 0.122, 0.019, 5, 0.5, 0.6],
    ]
    for i in range(len(p)):  # pragma: no branch
        ref q = p[i]
        out.append(primary(i, len(p), q[0], q[1], q[2], q[3], q[4], emarg=q[5]))
    var s: List[List[Float64]] = [
        [0.03, 0.150, 0.033, 90, 176],
        [0.14, 0.150, 0.033, 92, 176],
        [0.25, 0.148, 0.033, 94, 176],
        [0.36, 0.146, 0.033, 96, 176],
        [0.47, 0.144, 0.033, 99, 176],
        [0.58, 0.140, 0.033, 102, 177],
        [0.70, 0.132, 0.032, 108, 177],
        [0.81, 0.122, 0.031, 116, 178],
        [0.92, 0.108, 0.030, 125, 179],
    ]
    for i in range(len(s)):  # pragma: no branch
        ref q = s[i]
        out.append(secondary(i, len(s), len(p), q[0], q[1], q[2], q[3], q[4]))
    var rc: List[List[Float64]] = [
        [0.002, 0.168, 0.034, 4, 0.5, 0],
        [0.004, 0.168, 0.033, 14, 1, -1],
        [0.006, 0.166, 0.032, 25, 1.5, -2],
        [0.008, 0.163, 0.031, 36, 2, -3],
        [0.010, 0.158, 0.030, 47, 2.5, -4],
        [0.012, 0.150, 0.029, 58, 3, -5],
    ]
    for i in range(len(rc)):  # pragma: no branch
        ref q = rc[i]
        out.append(rectrix(i, len(rc), q[0], q[1], q[2], q[3], q[4], bend=q[5]))
    return out^


def _hd(v: V3) -> V3:
    # The original's HEAD_DROP: the skull sits low and close on the body.
    return V3(v.x, v.y - 0.005, v.z - 0.003)


def crow_rig(t: Traits) raises -> Rig:
    """Return the crow's skeleton in bind pose, its wings folded.

    The proportions are from corvid osteometry: femur 47, tibiotarsus 84
    and tarsometatarsus 57 mm, humerus 67, ulna 78 and hand 58 mm.

    Args:
        t: The individual. The crow's rig does not vary.

    Returns:
        The rig.

    Raises:
        Error: If a bone names a missing joint.
    """
    _ = t.juvenile()
    var rig = Rig()
    rig.set("synsacrum", V3(0.0, 0.166, -0.034))
    rig.set("tailBase", V3(0.0, 0.168, -0.074))
    rig.set("tailTip", V3(0.0, 0.166, -0.097))
    rig.set("neckBase", V3(0.0, 0.205, 0.046))
    rig.set("occiput", _hd(V3(0.0, 0.281, 0.064)))
    rig.set("bill", _hd(V3(0.0, 0.305, 0.187)))
    rig.set("jawHinge", _hd(V3(0.0, 0.29, 0.1)))
    rig.set("jawTip", _hd(V3(0.0, 0.296, 0.181)))
    rig.set("shoulderL", V3(0.03, 0.213, 0.03))
    rig.set("hipL", V3(0.026, 0.15, -0.03))
    rig.set("kneeL", V3(0.033, 0.122, 0.008))
    rig.set("ankleL", V3(0.03, 0.058, -0.044))
    rig.set("mtpL", V3(0.024, 0.0062, -0.02))
    place_toe(rig, 3, 2.0, 0.02, 0.021, 0.0034, 0.0022)
    place_toe(rig, 2, -22.0, 0.014, 0.016, 0.0034, 0.0022)
    place_toe(rig, 4, 24.0, 0.015, 0.017, 0.0034, 0.0022)
    place_toe(rig, 1, -6.0, 0.014, 0.015, 0.0034, 0.0022, back=True)
    neck_chain(
        rig,
        NECK_SEGS,
        normalize(V3(0.0, 0.45, 1.0)),
        normalize(V3(0.0, 1.0, -0.35)),
        0.42,
    )
    _ = wing_joints(rig, _lengths(), _fold())
    var feathers = _feathers()
    var frames = feather_frames(
        rig, _lengths(), _fold(), _fold(), _glide(), feathers, FAN_REST
    )
    feather_joints(rig, feathers, frames)
    rig.mirror_joints()
    bird_bones(rig, NECK_SEGS, feathers)
    return rig^


def _hl(v: V3) -> V3:
    return HEAD_O + v


def crow_sculpt(mut m: SdfModel, rig: Rig, t: Traits) raises:
    """Sculpt the crow: procedural-animals' `sculptCrow`, primitive for
    primitive, then its flight feathers as fins.

    Args:
        m: The sculpt to add to.
        rig: The crow's rig in bind pose.
        t: The individual.

    Raises:
        Error: If the rig lacks a joint or a bone, or the sculpt refuses
            a primitive.
    """
    var chest = rig.bone("chest")
    var pelvis = rig.bone("pelvis")
    var tail = rig.bone("tail")

    # TORSO: the feathered body.
    var tilt = normalize(V3(0.0, 0.5, 0.866))
    _ = m.ell(
        "breast",
        chest,
        V3(0.0, 0.182, 0.048),
        V3(0.044, 0.053, 0.07),
        axis=tilt,
        k=0.0,
    )
    _ = m.ell(
        "mantle",
        chest,
        V3(0.0, 0.2, 0.0),
        V3(0.043, 0.038, 0.07),
        axis=tilt,
        k=0.02,
    )
    # A straight underside from the breast to the vent.
    _ = m.ell(
        "belly",
        pelvis,
        V3(0.0, 0.14, -0.012),
        V3(0.041, 0.036, 0.07),
        axis=normalize(V3(0.0, 0.35, 1.0)),
        k=0.022,
    )
    _ = m.ell(
        "rump",
        pelvis,
        V3(0.0, 0.163, -0.07),
        V3(0.03, 0.03, 0.045),
        axis=normalize(V3(0.0, 0.3, 1.0)),
        k=0.02,
    )
    _ = m.ell(
        "undertail",
        tail,
        V3(0.0, 0.147, -0.108),
        V3(0.019, 0.015, 0.055),
        axis=normalize(V3(0.0, 0.18, 1.0)),
        k=0.016,
    )
    _ = m.ell(
        "uppertail",
        tail,
        V3(0.0, 0.172, -0.096),
        V3(0.019, 0.011, 0.032),
        axis=normalize(V3(0.0, 0.1, 1.0)),
        k=0.012,
    )
    for s in [1.0, -1.0]:  # pragma: no branch
        _ = m.ell(
            "flankfold",
            pelvis,
            V3(0.026 * s, 0.145, -0.02),
            V3(0.02, 0.03, 0.06),
            k=0.02,
        )
        # The sides under the folded wing: its lower edge is the outline.
        _ = m.ell(
            "sides",
            pelvis,
            V3(0.03 * s, 0.162, -0.012),
            V3(0.017, 0.026, 0.066),
            axis=normalize(V3(0.0, 0.2, 1.0)),
            k=0.02,
        )
        _ = m.ell(
            "scapular",
            chest,
            V3(0.026 * s, 0.211, 0.004),
            V3(0.02, 0.014, 0.05),
            axis=tilt,
            k=0.018,
        )

    # NECK: tapering from 30 mm at the base to 19 mm at the skull.
    var nj = List[String]()
    nj.append("neckBase")
    for i in range(1, NECK_SEGS):  # pragma: no branch
        nj.append("neck" + String(i))
    nj.append("occiput")
    var nr = List[Float64]()
    for i in range(NECK_SEGS + 1):  # pragma: no branch
        var u = Float64(i) / Float64(NECK_SEGS)
        nr.append(0.03 - 0.011 * pow(u, 0.8))
    for i in range(NECK_SEGS):  # pragma: no branch
        _ = m.cone(
            "neck",
            rig.bone("neck" + String(i)),
            rig.j(nj[i]),
            rig.j(nj[i + 1]),
            nr[i],
            nr[i + 1],
            k=0.02,
        )
    # The throat filled out: bill, chin, throat and breast in one line.
    _ = m.ell(
        "throat",
        rig.bone("neck1"),
        V3(0.0, 0.232, 0.087),
        V3(0.021, 0.028, 0.027),
        axis=normalize(V3(0.0, 0.6, 1.0)),
        k=0.021,
    )
    _ = m.ell(
        "nape",
        rig.bone("neck2"),
        V3(0.0, 0.248, 0.04),
        V3(0.0166, 0.02, 0.0204),
        k=0.022,
    )

    # HEAD, head-local: one smooth dome from the forehead to the nape.
    var h = rig.bone("head")
    _ = m.ell(
        "cranium",
        h,
        _hl(V3(0.0, 0.004, -0.01)),
        V3(0.0185, 0.021, 0.031),
        k=0.014,
    )
    _ = m.ell(
        "crown",
        h,
        _hl(V3(0.0, 0.012, 0.006)),
        V3(0.0145, 0.0105, 0.022),
        axis=normalize(V3(0.0, -0.25, 1.0)),
        k=0.016,
    )
    _ = m.ell(
        "forehead",
        h,
        _hl(V3(0.0, 0.0115, 0.022)),
        V3(0.0115, 0.0115, 0.016),
        axis=normalize(V3(0.0, -0.45, 1.0)),
        k=0.012,
    )
    _ = m.ell(
        "chin",
        h,
        _hl(V3(0.0, -0.02, 0.006)),
        V3(0.012, 0.012, 0.026),
        axis=normalize(V3(0.0, 0.25, 1.0)),
        k=0.012,
    )
    var eye = crow_eye(t)
    for s in [1.0, -1.0]:  # pragma: no branch
        _ = m.ell(
            "cheek",
            h,
            _hl(V3(0.011 * s, -0.009, 0.01)),
            V3(0.009, 0.012, 0.02),
            k=0.008,
        )
        _ = m.ell(
            "brow",
            h,
            _hl(V3(0.013 * s, 0.009, 0.004)),
            V3(0.007, 0.006, 0.014),
            k=0.006,
        )
        _ = sculpt_eye_socket(m, eye, HEAD_O, s, h)
    # The massive bill: about as deep as the forehead at its base, the
    # culmen curving down to a sharp tip.
    _ = m.ell(
        "bill",
        h,
        _hl(V3(0.0, 0.001, 0.042)),
        V3(0.0085, 0.0105, 0.022),
        axis=normalize(V3(0.0, -0.08, 1.0)),
        k=0.007,
    )
    _ = m.cone(
        "bill",
        h,
        _hl(V3(0.0, 0.004, 0.054)),
        _hl(V3(0.0, 0.0028, 0.0808)),
        0.0068,
        0.001,
        k=0.007,
    )
    _ = m.cone(
        "bill",
        h,
        _hl(V3(0.0, -0.004, 0.05)),
        _hl(V3(0.0, 0.0018, 0.0802)),
        0.0052,
        0.001,
        k=0.006,
    )
    # The nasal bristles lie flat along the top of the bill's base.
    _ = m.ell(
        "bristles",
        h,
        _hl(V3(0.0, 0.0098, 0.035)),
        V3(0.0078, 0.004, 0.013),
        axis=normalize(V3(0.0, -0.2, 1.0)),
        k=0.005,
    )
    # The lower mandible: its own surface, so the bill can open.
    var jw = rig.bone("jaw")
    _ = m.ell(
        "mandible",
        jw,
        _hl(V3(0.0, -0.0098, 0.038)),
        V3(0.0075, 0.0052, 0.028),
        axis=normalize(V3(0.0, 0.08, 1.0)),
        k=0.004,
        part=JAW,
    )
    _ = m.cone(
        "mandible",
        jw,
        _hl(V3(0.0, -0.0082, 0.05)),
        _hl(V3(0.0, -0.0006, 0.0772)),
        0.0052,
        0.0009,
        k=0.004,
        part=JAW,
    )
    _ = m.ell(
        "gonys",
        jw,
        _hl(V3(0.0, -0.0135, 0.02)),
        V3(0.0095, 0.0068, 0.02),
        k=0.006,
        part=JAW,
    )

    # LEGS: feathered trousers, then the bare tibia, the tarsus and toes.
    for side in [String("L"), String("R")]:  # pragma: no branch
        var kn = rig.j("knee" + side)
        var an = rig.j("ankle" + side)
        var mt = rig.j("mtp" + side)
        var tib = rig.bone("tibia" + side)
        var tar = rig.bone("tarsus" + side)
        _ = ell_y(
            m,
            "thigh",
            tib,
            lerp(kn, an, 0.22),
            an - kn,
            V3(0.017, 0.03, 0.02),
            k=0.02,
        )
        _ = m.cone(
            "trousers",
            tib,
            lerp(kn, an, 0.3),
            lerp(kn, an, 0.8),
            0.014,
            0.0075,
            k=0.01,
        )
        _ = m.cone("shank", tib, lerp(kn, an, 0.7), an, 0.0055, 0.0045, k=0.004)
        _ = m.cone("tarsus", tar, an, mt, 0.0044, 0.0036, k=0.003)
        _ = m.sphere("pad", tar, mt + V3(0.0, -0.0015, 0.001), 0.0045, k=0.003)
        for toe in range(1, 5):  # pragma: no branch
            var ts = String(toe)
            var b = rig.j("t" + ts + "m" + side)
            var c = rig.j("t" + ts + "t" + side)
            var r0 = 0.0032 if toe == 1 else 0.0028
            var ta = rig.bone("toe" + ts + "a" + side)
            var tb = rig.bone("toe" + ts + "b" + side)
            _ = m.cone("toe", ta, mt, b, r0, 0.0024, k=0.0025)
            _ = m.cone("toe", tb, b, lerp(b, c, 0.72), 0.0024, 0.0017, k=0.002)
            _ = m.cone("claw", tb, lerp(b, c, 0.65), c, 0.0015, 0.0003, k=0.001)

    # WINGS: the arm. The flight feathers follow as fins.
    for side in [String("L"), String("R")]:  # pragma: no branch
        var s = 1.0 if side == "L" else -1.0
        var sh = rig.j("shoulder" + side)
        var el = rig.j("elbow" + side)
        var wr = rig.j("wrist" + side)
        var tp = rig.j("handTip" + side)
        var n = wing_normal(rig, side)
        var ulna = rig.bone("ulna" + side)
        wing_segment(
            m,
            s,
            n,
            sh,
            el,
            rig.bone("humerus" + side),
            0.01,
            0.026,
            0.009,
            "arm",
            0.012,
        )
        wing_segment(m, s, n, el, wr, ulna, 0.0085, 0.026, 0.011, "arm", 0.008)
        wing_segment(
            m,
            s,
            n,
            wr,
            tp,
            rig.bone("hand" + side),
            0.0055,
            0.012,
            0.004,
            "hand",
            0.006,
        )
        # The leading-edge roll, on the forearm only.
        wing_segment(
            m,
            s,
            n,
            lerp(el, wr, 0.08),
            wr,
            ulna,
            0.0065,
            0.009,
            -0.009,
            "patagium",
            0.009,
        )
        _ = m.sphere("wrist", rig.bone("hand" + side), wr, 0.0065, k=0.006)

    # The flight feathers, their coverts and the tail, as fins.
    var feathers = _feathers()
    var frames = feather_frames(
        rig, _lengths(), _fold(), _fold(), _glide(), feathers, FAN_REST
    )
    feather_fins(
        m,
        rig,
        feathers,
        frames,
        0.0016,
        0.0015,
        coverts=V3(0.0, 0.6, 0.44),
        tail_k=t.get("tailK"),
    )


def crow_palette(t: Traits) raises -> Palette:
    """Return one crow's palette: procedural-animals' `crowColors`.

    Wear browns the black, and the gloss falls with it.

    Args:
        t: The individual.

    Returns:
        The palette, in linear light.

    Raises:
        Error: If a swatch is missing.
    """
    var wear = t.get("wear", 0.0)
    var worn = srgb(0x2A2420)
    var out = Palette()
    out.set("body", mix3(srgb(0x131316), worn, wear * 0.35))
    out.set("under", mix3(srgb(0x19191D), worn, wear * 0.35))
    out.set("head", mix3(srgb(0x151518), worn, wear * 0.35))
    out.set("gray", srgb(0x8C8C8A))
    out.set("grayUnder", srgb(0x9A9A98))
    out.set("bill", srgb(0x141414))
    out.set("leg", srgb(0x17171A))
    out.set("claw", srgb(0x0E0E10))
    out.set("ring", srgb(0x1C1B1D))
    out.set("gape", srgb(0xB87C78) if t.juvenile() > 0.0 else srgb(0x2A2A2E))
    # The structural gloss: blue-violet on the back, wings and tail.
    out.set("sheen", srgb(0x3A3C6A))
    var irid = (
        (0.45 if t.variant == CARRION else 0.55)
        * t.get("gloss")
        * (1.0 - 0.5 * wear)
    )
    out.set("irid", V3(irid, irid, irid))
    return out^


def _sheen(pal: Palette, c: V3, amount: Float64, n: V3) -> V3:
    # The gloss reads as a blue-violet (carrion: greener) cast where the
    # feathers face the sky.
    var k = (
        pal.get("irid").x * amount * (0.4 + 0.6 * smoothstep(-0.2, 0.8, n.y))
    )
    return mix3(c, pal.get("sheen"), clamp(k * 0.35, 0.0, 0.5))


def _shingle(p: V3, scale: Float64) -> Float64:
    # Contour feathers as overlapping scales: darker in the hollows
    # between them, lighter on their exposed tips.
    var q = V3(p.x * scale, p.y * scale, p.z * scale * 0.6)
    var c = 0.5 * fbm3(q, 2) + 0.5 * fbm3(q * 2.1, 1)
    return 0.88 + 0.24 * c


def crow_paint(
    pal: Palette, t: Traits, tag: String, bone: String, s: CoatSample
) raises -> Paint:
    """Paint one vertex of a crow.

    Black all over, with a blue-violet gloss on the back, the wings and
    the tail, a matter head and underside, a black bill and black scaled
    legs. The hooded crow's mantle, back and underparts are gray.

    Args:
        pal: The individual's palette.
        t: The individual.
        tag: The tag of the solid the vertex lies on.
        bone: The bone that solid rides.
        s: The vertex.

    Returns:
        The paint.

    Raises:
        Error: If the vertex's solid is not one of the crow's.
    """
    var p = s.p
    var n = s.n
    var h = p - HEAD_O
    var cv = fbm3(p * 40.0, 3) - 0.5
    var vary = V3(1.0 + 0.1 * cv, 1.0 + 0.1 * cv, 1.0 + 0.08 * cv)
    var cond1 = tag == "bill" or tag == "mandible" or tag == "gonys"
    if cond1:
        var gape = tag != "bill" and h.z > 0.02 and abs(h.y + 0.006) < 0.0012
        if gape:
            return Paint(pal.get("gape"), SKIN)
        return Paint(_tint(pal.get("bill"), vary), KERATIN)
    if tag == "claw":
        return Paint(pal.get("claw"), KERATIN)
    var bare_leg = (
        tag == "tarsus" or tag == "toe" or tag == "pad" or tag == "shank"
    )
    if bare_leg:
        return Paint(_tint(pal.get("leg"), vary), SCALES)
    var cond2 = tag == "eyelid" or tag == "eyesocket"
    if cond2:
        return Paint(pal.get("ring"), SKIN)
    var c: V3
    var shine = 1.0
    if is_card(tag):
        var cp = card_point(tag, s.local, bone.endswith("R"))
        var top = cp.top
        var covert = cp.kind.endswith("Covert")
        c = pal.get("body") if top else mix3(
            pal.get("under"), srgb(0x2A2A30), 0.35
        )
        # The primaries' inner vanes, hidden at rest, are duller.
        var cond3 = cp.kind == "primary" and cp.across > 0.004
        if cond3:
            c = mix3(c, pal.get("under"), 0.3)
        # Each feather a shade apart, so the folded wing reads feather
        # by feather, and darker toward its shaft.
        var k = 1.0 + 0.06 * fbm3(V3(Float64(s.bone) * 1.7, cp.t * 2.1, 0.5), 1)
        k *= 0.9 + 0.1 * smoothstep(0.0, 0.006, abs(cp.across))
        c = c * k
        shine = (0.7 if covert else 0.5) if top else 0.0
        c = _sheen(pal, c, shine * 1.6, n)
        return Paint(_tint(c, vary), FEATHER)
    var cond4 = (
        bone.startswith("humerus")
        or bone.startswith("ulna")
        or (bone.startswith("hand"))
    )
    if bone == "head":
        c = pal.get("head")
        shine = 0.35
        if tag == "bristles":
            shine = 0.0
    elif bone.startswith("tibia"):
        c = pal.get("under")
        shine = 0.2
    elif cond4:
        c = pal.get("body")
        var top = n.y > -0.2
        if not top:
            c = pal.get("under")
            shine = 0.25
    else:
        var dorsal = smoothstep(-0.2, 0.5, n.y)
        c = mix3(pal.get("under"), pal.get("body"), dorsal)
        shine = mix(0.2, 0.7, dorsal) * mix(0.45, 1.0, dorsal)
        if t.variant == HOODED:
            # Gray mantle, back, breast and belly; black head, bib, wings
            # and tail, with soft edges.
            var bib = smoothstep(
                0.17, 0.2, p.y + 0.25 * max(0.0, p.z - 0.03)
            ) * smoothstep(0.03, 0.06, p.z)
            var gw = (1.0 - bib) * smoothstep(-0.105, -0.08, p.z)
            var gray = mix3(pal.get("grayUnder"), pal.get("gray"), dorsal)
            c = mix3(c, gray, gw)
            shine = mix(shine, 0.05, gw)
    c = c * _shingle(p, 260.0)
    c = _sheen(pal, c, shine, n)
    return Paint(_tint(c, vary), FEATHER)


def _tint(c: V3, k: V3) -> V3:
    return V3(c.x * k.x, c.y * k.y, c.z * k.z)
