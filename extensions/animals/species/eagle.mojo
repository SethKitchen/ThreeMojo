# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The eagle, Haliaeetus leucocephalus: procedural-animals'
`species/eagle/`.

A soaring raptor on the bird body plan: an upright perching carriage, a
massive hooked bill under a heavy brow, huge talons and broad plank
wings. The reference adult is a 4.7 kg bald eagle, 0.86 m from the bill
tip to the tail tip. The morphs are the bald eagle and the golden eagle,
which is smaller, with a smaller bill and legs feathered to the toes.
About 30 % of seeds are juveniles: a juvenile bald eagle is brown,
mottled white, with a dark head and bill.

procedural-animals binds the wings half open and renders the flight
feathers as cards. This port binds them folded, at rest, and sculpts
each flight feather as a flattened ellipsoid and the closed tail as a
fin.
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
from extensions.sdf.ids import BoneId
from extensions.animals.parts import JAW
from extensions.sdf.sculpt import ell_y
from extensions.animals.kit import (
    EyeSpec,
    sculpt_eye_socket,
)
from extensions.animals.noise import fbm3
from extensions.animals.options import (
    ANY_AGE,
    ADULT,
    JUVENILE,
    AnimalOptions,
    AnimalRandom,
)
from extensions.animals.rig import Rig
from extensions.sdf.field import SdfModel
from extensions.animals.species.bird_rig import (
    Feather,
    WingPose,
    bird_bones,
    card_point,
    feather_fins,
    feather_frames,
    feather_joints,
    is_card,
    neck_chain,
    place_toe,
    primary,
    rectrix,
    secondary,
    wing_joints,
    wing_normal,
    wing_segment,
)
from extensions.animals.traits import Traits, pick_sex
from extensions.sdf.vector import (
    V3,
    clamp,
    dot,
    length,
    lerp,
    normalize,
    smoothstep,
)
from extensions.animals.warp import (
    girth_warp,
    legs_warp,
    scale_about_warp,
)
from std.math import cos, pi, pow, sin, sqrt

comptime NECK_SEGS = 4
# The standing body axis above the horizontal, in degrees.
comptime TILT = 48.0
# The head's origin, between the eyes.
comptime HEAD_O = V3(0.0, 0.595, 0.205)
# The synsacrum: the origin of the body-axis frame.
comptime SYN = V3(0.0, 0.285, -0.03)
# The finest cell, at the `HERO` tier: the head's cell in the original.
comptime CELL = 0.0018
# How far the tail is fanned at rest: the motion data's `fanRest`.
comptime FAN_REST = 0.04
# The leg bones: femur and tibiotarsus.
comptime FEMUR = 0.098
comptime TIBIA = 0.1595

# The morphs, in procedural-animals' order.
comptime BALD = 0
comptime GOLDEN = 1


def eagle_variant_names() -> List[String]:
    """Return the eagle's morphs.

    Returns:
        Bald and golden.
    """
    return [String("bald"), "golden"]


def eagle_traits(mut r: AnimalRandom, options: AnimalOptions) raises -> Traits:
    """Draw one eagle: procedural-animals' `variation`.

    The size dimorphism is reversed: females are about 10 % larger. When
    no age is asked for, about 30 % of seeds are juveniles.

    Args:
        r: The individual's stream.
        options: The caller's sex, age and morph.

    Returns:
        The traits.

    Raises:
        Error: If the requested morph is not one of the two.
    """
    if options.variant.value >= 2:
        raise Error("The eagle has no such color variant")
    var variant = GOLDEN if options.variant.value == GOLDEN else BALD
    var sex = pick_sex(options.sex, r)
    var age = options.age
    if age == ANY_AGE:
        age = JUVENILE if r.next() < 0.3 else ADULT
    var t = Traits(sex, age, variant)
    var juv = t.juvenile() > 0.0
    var female = not t.male()
    var golden = variant == GOLDEN
    var size = (
        (1.04 if female else 0.94)
        * (1.0 + 0.035 * r.g())
        * (0.96 if golden else 1.0)
    )
    var bill = (
        (1.03 if female else 0.98)
        * (1.0 + 0.05 * r.g())
        * (0.94 if golden else 1.0)
    )
    t.set("size", size)
    t.set("bill", bill)
    t.warps.add(legs_warp(1.0 + 0.035 * r.g(), 0.24))
    t.warps.add(
        scale_about_warp(
            V3(HEAD_O.x, HEAD_O.y - 0.012, HEAD_O.z + 0.045), bill, 0.05, 0.1
        )
    )
    var head_k = (1.0 + 0.03 * r.g()) * (0.95 if golden else 1.0)
    t.warps.add(scale_about_warp(HEAD_O, head_k, 0.06, 0.12))
    var girth = 1.0 + 0.035 * r.g() + (0.01 if juv else 0.0)
    t.warps.add(girth_warp(girth, 0.32, -0.14, 0.1, 0.06))
    t.set("wear", max(0.0, 0.3 * r.g() + (0.35 if juv else 0.1)))
    t.set("warm", 0.5 + 0.5 * r.g())
    t.set("mottle", 0.55 + 0.35 * r.g() if juv else 0.0)
    t.set("billAge", max(0.0, 0.25 * r.g()) if juv else 1.0)
    t.set("goldK", 0.5 + 0.4 * r.g())
    # How far down the neck the white hood reaches.
    t.set("hood", 0.26 + 0.07 * r.g())
    return t^


def eagle_eye(t: Traits) -> EyeSpec:
    """Return the eagle's left eye: large, under the brow shelf and
    fairly forward, the aperture slightly flattened from above.

    Args:
        t: The individual. The eagle's eye does not vary.

    Returns:
        The eye, head-local.
    """
    _ = t.juvenile()
    return EyeSpec(
        V3(0.0242, 0.0, 0.004),
        0.0118,
        0.0038,
        0.9,
        0.06,
        0.0014,
        0.0096,
        0.0012,
        -0.0005,
        0.12,
        0.0074,
        0.0082,
    )


def eagle_look(t: Traits) -> EyeLook:
    """Return the eagle's eye colors: pale yellow in an adult bald eagle,
    brown in a golden eagle and dark brown in a juvenile.

    Args:
        t: The individual.

    Returns:
        The look.
    """
    var sclera = V3(0.02, 0.02, 0.02)
    var golden = t.variant == GOLDEN
    if t.juvenile() > 0.0:
        return EyeLook(
            srgb(0x241408), srgb(0x4A2C14), srgb(0x1C1008), sclera, 0.42, 0.0
        )
    if golden:
        return EyeLook(
            srgb(0x5A3414), srgb(0x8A5A28), srgb(0x3A2410), sclera, 0.42, 0.0
        )
    return EyeLook(
        srgb(0xD9C878), srgb(0xF2E6A0), srgb(0xA89048), sclera, 0.42, 0.0
    )


def _ax(a: Float64, b: Float64, x: Float64 = 0.0) -> V3:
    # The body-axis frame: `a` along the axis, forward and up, `b` dorsal.
    var ct = cos(TILT * pi / 180.0)
    var st = sin(TILT * pi / 180.0)
    return V3(x, SYN.y + a * st + b * ct, SYN.z + a * ct - b * st)


def _axis_at(deg: Float64) -> V3:
    return V3(0.0, sin(deg * pi / 180.0), cos(deg * pi / 180.0))


def _knee(hip: V3, ankle: V3, l1: Float64, l2: Float64, pole: V3) -> V3:
    # The knee of a hip, knee and ankle chain, bent toward `pole`.
    var d = ankle - hip
    var span = length(d)
    var e1 = d * (1.0 / span)
    var e2 = normalize(pole - e1 * dot(pole, e1))
    var c = (l1 * l1 + span * span - l2 * l2) / (2.0 * l1 * span)
    var sn = sqrt(max(0.0, 1.0 - c * c))
    return hip + e1 * (l1 * c) + e2 * (l1 * sn)


def _lengths() -> V3:
    return V3(0.19, 0.22, 0.15)


def _fold() -> WingPose:
    # The wing root frame follows the upright body axis: `tilt` 46.
    return WingPose(-84.0, 2.0, 100.0, 152.0, 160.0, 0.0, 0.0, 46.0)


def _glide() -> WingPose:
    return WingPose(3.0, 6.0, 2.0, 18.0, 16.0, 3.0, 1.0, 46.0)


def _feathers() -> List[Feather]:
    # 10 primaries (p5 to p10 emarginated), 12 secondaries and tertials,
    # and 6 rectrices a side.
    var out = List[Feather]()
    var p: List[List[Float64]] = [
        [0.05, 0.33, 0.066, 78, 8, 0, 0],
        [0.15, 0.345, 0.066, 70, 7, 0, 0],
        [0.26, 0.36, 0.065, 62, 6, 0, 0],
        [0.37, 0.38, 0.064, 54, 5.5, 0.35, 0],
        [0.48, 0.405, 0.062, 46, 5, 0.8, 0],
        [0.59, 0.43, 0.06, 38, 4, 1, 2],
        [0.70, 0.45, 0.058, 30, 3, 1, 3],
        [0.80, 0.45, 0.055, 21, 2, 1, 4],
        [0.90, 0.43, 0.052, 12, 1, 1, 5],
        [1.00, 0.35, 0.046, 3, 0.5, 1, 5],
    ]
    for i in range(len(p)):
        ref q = p[i]
        out.append(
            primary(
                i,
                len(p),
                q[0],
                q[1],
                q[2],
                q[3],
                q[4],
                emarg=q[5],
                bend=q[6],
                droop=0.008,
            )
        )
    var s: List[List[Float64]] = [
        [0.03, 0.32, 0.072, 84, 144],
        [0.11, 0.325, 0.072, 86, 144],
        [0.19, 0.325, 0.072, 88, 144.5],
        [0.27, 0.325, 0.072, 90, 145],
        [0.35, 0.322, 0.072, 92, 145],
        [0.43, 0.318, 0.072, 94, 145.5],
        [0.51, 0.312, 0.071, 96, 146],
        [0.59, 0.304, 0.07, 99, 146],
        [0.67, 0.295, 0.069, 104, 146.5],
        [0.75, 0.29, 0.068, 112, 147],
        [0.84, 0.28, 0.068, 124, 147.5],
        [0.93, 0.265, 0.068, 140, 148],
    ]
    for i in range(len(s)):
        ref q = s[i]
        out.append(secondary(i, len(s), len(p), q[0], q[1], q[2], q[3], q[4]))
    var rc: List[List[Float64]] = [
        [0.004, 0.31, 0.075, 4, 0.5, 0],
        [0.008, 0.305, 0.074, 13, 1, -1],
        [0.012, 0.298, 0.073, 23, 1.5, -2],
        [0.016, 0.29, 0.072, 33, 2, -3],
        [0.020, 0.28, 0.07, 43, 2.5, -4],
        [0.024, 0.268, 0.068, 53, 3, -5],
    ]
    for i in range(len(rc)):
        ref q = rc[i]
        out.append(rectrix(i, len(rc), q[0], q[1], q[2], q[3], q[4], bend=q[5]))
    return out^


def _hl(v: V3) -> V3:
    return HEAD_O + v


def eagle_rig(t: Traits) raises -> Rig:
    """Return the eagle's skeleton in bind pose, standing upright with
    its wings folded.

    The bones are raptor osteometry scaled to a 95 mm tarsometatarsus:
    femur 100, tibiotarsus 160 and tarsometatarsus 95 mm, humerus 190,
    ulna 220 and hand 150 mm.

    Args:
        t: The individual. The eagle's rig does not vary.

    Returns:
        The rig.

    Raises:
        Error: If a bone names a missing joint.
    """
    _ = t.juvenile()
    var rig = Rig()
    rig.set("synsacrum", SYN)
    var tail_base = _ax(-0.06, 0.05)
    rig.set("tailBase", tail_base)
    # The tail points 38 degrees below the horizontal.
    var down = 38.0 * pi / 180.0
    rig.set(
        "tailTip",
        V3(
            0.0,
            tail_base.y - 0.042 * sin(down),
            tail_base.z - 0.042 * cos(down),
        ),
    )
    rig.set("neckBase", _ax(0.19, -0.03))
    rig.set("occiput", _hl(V3(0.0, -0.026, -0.058)))
    rig.set("bill", _hl(V3(0.0, -0.046, 0.109)))
    rig.set("jawHinge", _hl(V3(0.0, -0.027, -0.002)))
    rig.set("jawTip", _hl(V3(0.0, -0.04, 0.094)))
    rig.set("shoulderL", _ax(0.2, 0.045, 0.056))
    var hip = _ax(0.0, 0.015, 0.055)
    var ankle = V3(0.064, 0.108, -0.03)
    rig.set("hipL", hip)
    rig.set("ankleL", ankle)
    rig.set("mtpL", V3(0.05, 0.016, 0.0))
    rig.set("kneeL", _knee(hip, ankle, FEMUR, TIBIA, V3(0.0, 0.0, 1.0)))
    place_toe(rig, 3, 3.0, 0.046, 0.05, 0.011, 0.0085)
    place_toe(rig, 2, -24.0, 0.036, 0.048, 0.011, 0.0085)
    place_toe(rig, 4, 28.0, 0.037, 0.04, 0.011, 0.0085)
    place_toe(rig, 1, -8.0, 0.03, 0.05, 0.011, 0.0085, back=True)
    neck_chain(
        rig,
        NECK_SEGS,
        normalize(V3(0.0, 1.0, 0.15)),
        normalize(V3(0.0, 1.0, 0.7)),
        0.35,
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


def _neck_at(rig: Rig, f: Float64) raises -> Tuple[BoneId, V3]:
    # A point a fraction of the way up the neck, and the bone it is on.
    var x = f * Float64(NECK_SEGS)
    var i = min(NECK_SEGS - 1, Int(x))
    var a = String("neckBase") if i == 0 else "neck" + String(i)
    var b = String("occiput") if i + 1 == NECK_SEGS else "neck" + String(i + 1)
    return (
        rig.bone("neck" + String(i)),
        lerp(rig.j(a), rig.j(b), x - Float64(i)),
    )


def eagle_sculpt(mut m: SdfModel, rig: Rig, t: Traits) raises:
    """Sculpt the eagle: procedural-animals' `sculptEagle`, primitive for
    primitive, then its flight feathers and tail.

    Args:
        m: The sculpt to add to.
        rig: The eagle's rig in bind pose.
        t: The individual.

    Raises:
        Error: If the rig lacks a joint or a bone, or the sculpt refuses
            a primitive.
    """
    var booted = t.variant == GOLDEN
    var chest = rig.bone("chest")
    var pelvis = rig.bone("pelvis")
    var tail = rig.bone("tail")
    var tilt = _axis_at(TILT)

    # TORSO: a streamlined spindle in the body-axis frame, deepest at the
    # breast under the wing roots.
    _ = m.ell(
        "breast",
        chest,
        _ax(0.13, -0.02),
        V3(0.077, 0.074, 0.135),
        axis=tilt,
        k=0.0,
    )
    _ = m.ell(
        "mantle",
        chest,
        _ax(0.08, 0.032),
        V3(0.076, 0.058, 0.15),
        axis=tilt,
        k=0.04,
    )
    _ = m.ell(
        "belly",
        pelvis,
        _ax(-0.01, -0.03),
        V3(0.062, 0.058, 0.13),
        axis=_axis_at(TILT - 8.0),
        k=0.04,
    )
    _ = m.ell(
        "rump",
        pelvis,
        _ax(-0.07, 0.03),
        V3(0.052, 0.046, 0.085),
        axis=_axis_at(TILT - 6.0),
        k=0.035,
    )
    var tt = rig.j("tailTip")
    var td = normalize(tt - rig.j("tailBase"))
    _ = m.ell(
        "undertail",
        tail,
        tt + V3(0.0, -0.018, 0.01),
        V3(0.038, 0.026, 0.1),
        axis=-td,
        k=0.03,
    )
    _ = m.ell(
        "uppertail",
        tail,
        tt + V3(0.0, 0.012, -0.004),
        V3(0.038, 0.018, 0.07),
        axis=-td,
        k=0.024,
    )
    for s in [1.0, -1.0]:
        _ = m.ell(
            "flankfold",
            pelvis,
            _ax(0.01, -0.036, 0.042 * s),
            V3(0.032, 0.054, 0.1),
            axis=tilt,
            k=0.04,
        )
        _ = m.ell(
            "scapular",
            chest,
            _ax(0.13, 0.045, 0.05 * s),
            V3(0.036, 0.028, 0.11),
            axis=tilt,
            k=0.032,
        )

    # NECK: thick and hackled.
    for i in range(NECK_SEGS):
        var a = String("neckBase") if i == 0 else "neck" + String(i)
        var b = String("occiput") if i + 1 == NECK_SEGS else "neck" + String(
            i + 1
        )
        var u0 = Float64(i) / Float64(NECK_SEGS)
        var u1 = Float64(i + 1) / Float64(NECK_SEGS)
        _ = m.cone(
            "neck",
            rig.bone("neck" + String(i)),
            rig.j(a),
            rig.j(b),
            0.054 - 0.012 * pow(u0, 0.8),
            0.054 - 0.012 * pow(u1, 0.8),
            k=0.04,
        )
    var th = _neck_at(rig, 0.4)
    var np = _neck_at(rig, 0.6)
    _ = m.ell(
        "throat",
        th[0],
        th[1] + V3(0.0, -0.004, 0.024),
        V3(0.04, 0.05, 0.034),
        axis=normalize(V3(0.0, 0.6, 1.0)),
        k=0.04,
    )
    _ = m.ell(
        "nape",
        np[0],
        np[1] + V3(0.0, 0.01, -0.026),
        V3(0.04, 0.046, 0.038),
        k=0.04,
    )

    # HEAD, head-local.
    var h = rig.bone("head")
    _ = m.ell(
        "cranium",
        h,
        _hl(V3(0.0, -0.005, -0.028)),
        V3(0.035, 0.032, 0.05),
        k=0.02,
    )
    _ = m.ell(
        "crown",
        h,
        _hl(V3(0.0, 0.013, -0.006)),
        V3(0.026, 0.012, 0.042),
        axis=normalize(V3(0.0, -0.12, 1.0)),
        k=0.016,
    )
    _ = m.ell(
        "hackles",
        h,
        _hl(V3(0.0, -0.008, -0.062)),
        V3(0.034, 0.03, 0.032),
        k=0.02,
    )
    _ = m.ell(
        "forehead",
        h,
        _hl(V3(0.0, 0.014, 0.022)),
        V3(0.019, 0.015, 0.024),
        axis=normalize(V3(0.0, -0.35, 1.0)),
        k=0.012,
    )
    _ = m.ell(
        "chin",
        h,
        _hl(V3(0.0, -0.034, -0.012)),
        V3(0.026, 0.024, 0.044),
        axis=normalize(V3(0.0, 0.15, 1.0)),
        k=0.02,
    )
    var eye = eagle_eye(t)
    for s in [1.0, -1.0]:
        _ = m.ell(
            "cheek",
            h,
            _hl(V3(0.019 * s, -0.016, -0.008)),
            V3(0.017, 0.02, 0.032),
            k=0.014,
        )
        _ = m.ell(
            "lore",
            h,
            _hl(V3(0.013 * s, -0.008, 0.026)),
            V3(0.011, 0.013, 0.02),
            axis=normalize(V3(0.0, -0.1, 1.0)),
            k=0.01,
        )
        # The supraorbital ridge: a hard shelf over the front of the eye.
        _ = ell_y(
            m,
            "brow",
            h,
            _hl(V3(0.0225 * s, 0.0138, 0.01)),
            V3(0.25 * s, 1.0, 0.12),
            V3(0.0095, 0.0055, 0.023),
            k=0.005,
        )
        _ = sculpt_eye_socket(m, eye, HEAD_O, s, h)
    # The upper mandible: deep at the base, the culmen curving into a
    # strong hook; the cere covers its base.
    _ = m.ell(
        "cere",
        h,
        _hl(V3(0.0, 0.003, 0.036)),
        V3(0.0148, 0.0135, 0.016),
        axis=normalize(V3(0.0, -0.1, 1.0)),
        k=0.008,
    )
    _ = m.ell(
        "bill",
        h,
        _hl(V3(0.0, -0.0095, 0.055)),
        V3(0.0128, 0.0205, 0.036),
        axis=normalize(V3(0.0, -0.1, 1.0)),
        k=0.008,
    )
    _ = m.ell(
        "bill",
        h,
        _hl(V3(0.0, -0.012, 0.082)),
        V3(0.0095, 0.018, 0.021),
        axis=normalize(V3(0.0, -0.45, 1.0)),
        k=0.008,
    )
    _ = m.ell(
        "bill",
        h,
        _hl(V3(0.0, -0.02, 0.1)),
        V3(0.0074, 0.016, 0.012),
        axis=normalize(V3(0.0, -0.95, 0.3)),
        k=0.006,
    )
    _ = m.cone(
        "bill",
        h,
        _hl(V3(0.0, -0.029, 0.1055)),
        _hl(V3(0.0, -0.0465, 0.108)),
        0.006,
        0.0012,
        k=0.004,
    )
    for s in [1.0, -1.0]:
        _ = m.ell(
            "nostril",
            h,
            _hl(V3(0.0118 * s, 0.003, 0.044)),
            V3(0.003, 0.0028, 0.005),
            axis=normalize(V3(0.0, 0.2, 1.0)),
            k=0.002,
            carve=True,
        )
    # The lower mandible, tucked inside the hook: its own surface.
    var jw = rig.bone("jaw")
    _ = m.ell(
        "mandible",
        jw,
        _hl(V3(0.0, -0.035, 0.045)),
        V3(0.0125, 0.0072, 0.046),
        axis=normalize(V3(0.0, -0.08, 1.0)),
        k=0.006,
        part=JAW,
    )
    _ = m.cone(
        "mandible",
        jw,
        _hl(V3(0.0, -0.036, 0.072)),
        _hl(V3(0.0, -0.0395, 0.095)),
        0.007,
        0.0018,
        k=0.005,
        part=JAW,
    )
    _ = m.ell(
        "gonys",
        jw,
        _hl(V3(0.0, -0.039, 0.02)),
        V3(0.016, 0.008, 0.03),
        k=0.008,
        part=JAW,
    )

    # LEGS: loose feathered trousers, scaled tarsi, huge talons.
    for side in [String("L"), String("R")]:
        var kn = rig.j("knee" + side)
        var an = rig.j("ankle" + side)
        var mt = rig.j("mtp" + side)
        var tib = rig.bone("tibia" + side)
        var tar = rig.bone("tarsus" + side)
        _ = ell_y(
            m,
            "thigh",
            tib,
            lerp(kn, an, 0.25),
            an - kn,
            V3(0.036, 0.058, 0.032),
            k=0.04,
        )
        _ = m.cone(
            "trousers",
            tib,
            lerp(kn, an, 0.3),
            lerp(kn, an, 0.96),
            0.029,
            0.021,
            k=0.02,
        )
        if booted:
            # The golden eagle is feathered to the toes.
            _ = m.cone(
                "boot",
                tar,
                lerp(an, mt, 0.05),
                lerp(an, mt, 0.66),
                0.017,
                0.0115,
                k=0.006,
            )
        else:
            _ = m.cone(
                "cuff", tar, an, lerp(an, mt, 0.42), 0.02, 0.0135, k=0.01
            )
        _ = m.cone("tarsus", tar, an, mt, 0.0115, 0.0098, k=0.006)
        _ = m.sphere("pad", tar, mt + V3(0.0, -0.001, 0.003), 0.0105, k=0.005)
        for toe in range(1, 5):
            var ts = String(toe)
            var b = rig.j("t" + ts + "m" + side)
            var c = rig.j("t" + ts + "t" + side)
            var big = toe <= 2
            var r0 = 0.0105 if toe == 1 else 0.0092
            var ta = rig.bone("toe" + ts + "a" + side)
            var tb = rig.bone("toe" + ts + "b" + side)
            _ = m.cone("toe", ta, mt, b, r0, 0.0082, k=0.005)
            _ = m.cone("toe", tb, b, lerp(b, c, 0.5), 0.0082, 0.0068, k=0.004)
            # The talon: thick at the base, curved down to a needle point.
            var q0 = lerp(b, c, 0.42) + V3(0.0, 0.004, 0.0)
            var q1 = lerp(b, c, 0.78) + V3(0.0, 0.0035, 0.0)
            var q2 = c + V3(0.0, -0.0035, 0.0)
            var tr = 0.0062 if big else 0.0054
            _ = m.cone("claw", tb, q0, q1, tr, tr * 0.62, k=0.002)
            _ = m.cone("claw", tb, q1, q2, tr * 0.62, 0.0008, k=0.0015)

    # WINGS: the arm. The flight feathers follow.
    for side in [String("L"), String("R")]:
        var s = 1.0 if side == "L" else -1.0
        var sh = rig.j("shoulder" + side)
        var el = rig.j("elbow" + side)
        var wr = rig.j("wrist" + side)
        var tp = rig.j("handTip" + side)
        var n = wing_normal(rig, side)
        var ulna = rig.bone("ulna" + side)
        var hand = rig.bone("hand" + side)
        wing_segment(
            m,
            s,
            n,
            sh,
            el,
            rig.bone("humerus" + side),
            0.019,
            0.05,
            0.018,
            "arm",
            0.024,
        )
        wing_segment(m, s, n, el, wr, ulna, 0.015, 0.052, 0.022, "arm", 0.016)
        wing_segment(m, s, n, wr, tp, hand, 0.012, 0.026, 0.008, "hand", 0.012)
        # The leading-edge roll along the forearm.
        wing_segment(
            m,
            s,
            n,
            lerp(el, wr, 0.08),
            wr,
            ulna,
            0.011,
            0.016,
            -0.02,
            "patagium",
            0.014,
        )
        _ = m.sphere("wrist", hand, wr, 0.0135, k=0.012)

    var feathers = _feathers()
    var frames = feather_frames(
        rig, _lengths(), _fold(), _fold(), _glide(), feathers, FAN_REST
    )
    feather_fins(m, rig, feathers, frames, 0.0036, 0.003)


def _tone(c: V3, t: Traits) -> V3:
    return mix3(
        c,
        srgb(0x5A4430),
        t.get("wear", 0.0) * 0.25 + t.get("warm", 0.0) * 0.1,
    )


def eagle_palette(t: Traits) raises -> Palette:
    """Return one eagle's palette: procedural-animals' `eagleColors`.

    Args:
        t: The individual.

    Returns:
        The palette, in linear light.

    Raises:
        Error: If a swatch is missing.
    """
    var juv = t.juvenile() > 0.0
    var out = Palette()
    if t.variant == GOLDEN:
        out.set("body", _tone(srgb(0x33251B if juv else 0x3A2A1E), t))
        out.set("under", _tone(srgb(0x2E2118 if juv else 0x34261B), t))
        out.set("head", srgb(0x3A2A1E))
        out.set(
            "nape", mix3(srgb(0xC08A3E), srgb(0xD9A650), t.get("goldK", 0.5))
        )
        out.set("face", srgb(0x33251B))
        out.set("covertEdge", srgb(0x8A6A48))
        out.set("white", srgb(0xE6E1D6))
        out.set("tail", srgb(0x4A3E34))
        out.set("tailBar", srgb(0x6E665C))
        out.set("tailBase", srgb(0xEDEAE2))
        out.set("tailBand", srgb(0x1E1A18))
        out.set("bill", srgb(0x4C5258))
        out.set("billTip", srgb(0x141416))
        out.set("cere", srgb(0xE8C040))
        out.set("gape", srgb(0xD8B040))
        out.set("leg", srgb(0xE8C040))
        out.set("boot", _tone(srgb(0x6A4A30), t))
        out.set("claw", srgb(0x161616))
        out.set("ring", srgb(0x4A3A2A))
        return out^
    var bill_age = t.get("billAge", 1.0)
    var bill = mix3(srgb(0x2E2A28), srgb(0xB89A58), bill_age) if juv else srgb(
        0xECC46F
    )
    out.set("body", _tone(srgb(0x3A2A1E if juv else 0x2B1E16), t))
    out.set("under", _tone(srgb(0x3A2B20 if juv else 0x2A1D15), t))
    out.set("head", srgb(0x2E2218) if juv else srgb(0xF2F0EA))
    out.set("nape", srgb(0x3A2A1E) if juv else srgb(0xF2F0EA))
    out.set("face", srgb(0x3A2C20) if juv else srgb(0xEEECE6))
    out.set("covertEdge", srgb(0x4A3828))
    out.set("white", srgb(0xE0D8C8))
    out.set("tail", srgb(0x4A3A2C) if juv else srgb(0xF4F2EC))
    out.set("tailBar", srgb(0x4A3A2C))
    out.set("tailBase", srgb(0xF4F2EC))
    out.set("tailBand", srgb(0x2A1E16))
    out.set("bill", bill)
    out.set("billTip", bill)
    out.set(
        "cere",
        mix3(srgb(0x7A6A50), srgb(0xD8B450), bill_age) if juv else srgb(
            0xEDC45A
        ),
    )
    out.set("gape", srgb(0x8A7A60) if juv else srgb(0xE8C060))
    out.set("leg", srgb(0xE8B840 if juv else 0xF0B830))
    out.set("boot", _tone(srgb(0x3A2B20 if juv else 0x2A1D15), t))
    out.set("claw", srgb(0x161616))
    out.set("ring", srgb(0x5A4A38) if juv else srgb(0xD8C078))
    return out^


def _hash(a: Float64) -> Float64:
    var x = sin(a * 12.9898) * 43758.5453
    return x - Float64(Int(x)) if x >= 0.0 else x - Float64(Int(x)) + 1.0


def _card_color(
    pal: Palette,
    t: Traits,
    kind: String,
    t_along: Float64,
    top: Bool,
    id: Float64,
) -> V3:
    # procedural-animals' `eagleFeatherColour`.
    var golden = t.variant == GOLDEN
    var juv = t.juvenile() > 0.0
    var mot = t.get("mottle", 0.0) if not golden else 0.0
    var c = pal.get("body") * 0.68 if top else mix3(
        pal.get("under"), srgb(0x4A3E36), 0.3
    )
    var cond3 = kind == "primary" or kind == "secondary"
    if kind == "rectrix":
        var cond1 = not golden and not juv
        var cond2 = golden and juv
        if cond1:
            c = pal.get("tail") if top else mix3(
                pal.get("tail"), srgb(0xC8C6C0), 0.3
            )
        elif cond2:
            c = pal.get("tailBase") if t_along < 0.62 else mix3(
                pal.get("tailBase"),
                pal.get("tailBand"),
                smoothstep(0.62, 0.7, t_along),
            )
        elif golden:
            # Grayish bands across the tail.
            var bar = smoothstep(
                0.35, 0.5, sin(t_along * 5.0 * pi + 0.6) * 0.5 + 0.5
            ) * (1.0 - smoothstep(0.8, 0.95, t_along))
            c = mix3(
                pal.get("tail"), pal.get("tailBar"), bar * (0.8 if top else 0.6)
            )
        else:
            # A juvenile bald eagle's tail: brown, mottled white toward
            # its base, darker at the tip.
            c = pal.get("tail")
            var w = (
                (1.0 - smoothstep(0.35, 0.85, t_along))
                * mot
                * (0.4 + 0.6 * _hash(Float64(Int(t_along * 9.0)) + id))
            )
            c = mix3(c, pal.get("white"), clamp(w, 0.0, 0.8))
            c = mix3(c, srgb(0x2A1E16), smoothstep(0.85, 0.97, t_along) * 0.6)
    elif cond3:
        if not top:
            c = mix3(c, srgb(0x5A5048), 0.25)
        c = mix3(c, srgb(0x16110D), smoothstep(0.7, 1.0, t_along) * 0.35)
        var golden_sec = golden and kind == "secondary" and top
        if golden_sec:
            c = mix3(
                c,
                pal.get("tailBar"),
                0.25 * (sin(t_along * 14.0) * 0.5 + 0.5) * (1.0 - t_along),
            )
        var golden_juv = golden and juv and kind == "primary"
        if golden_juv:
            # The golden juvenile's white wing patch at the primaries' base.
            c = mix3(
                c,
                pal.get("tailBase"),
                (1.0 - smoothstep(0.2, 0.45, t_along)) * 0.9,
            )
        var bald_juv = not golden and juv and not top
        if bald_juv:
            c = mix3(
                c,
                pal.get("white"),
                mot * 0.5 * (1.0 - smoothstep(0.3, 0.6, t_along)),
            )
    var k = 1.0 + 0.07 * sin(id * 12.9898 + t_along * 2.1)
    return c * k


def eagle_paint(
    pal: Palette, t: Traits, tag: String, bone: String, s: CoatSample
) raises -> Paint:
    """Paint one vertex of an eagle.

    An adult bald eagle is dark chocolate with a white head, neck and
    tail, a yellow bill and cere and yellow scaled feet with black talons.
    A juvenile bald eagle is brown, mottled white on the underparts, with
    a dark head and bill. A golden eagle is dark brown with a golden crown
    and nape, pale-edged coverts, a gray-barred tail and a dark-tipped
    blue-gray bill; its juvenile has a white tail base and wing patches.

    Args:
        pal: The individual's palette.
        t: The individual.
        tag: The tag of the solid the vertex lies on.
        bone: The bone that solid rides.
        s: The vertex.

    Returns:
        The paint.

    Raises:
        Error: If a feather card's tag cannot be read.
    """
    var p = s.p
    var n = s.n
    var h = p - HEAD_O
    var golden = t.variant == GOLDEN
    var juv = t.juvenile() > 0.0
    var cv = fbm3(p * 18.0, 3) - 0.5
    var cond4 = tag == "mandible" or tag == "gonys"
    if cond4:
        if h.z < 0.012:
            return Paint(pal.get("gape"), SKIN)
        var c = mix3(
            pal.get("bill"), pal.get("billTip"), smoothstep(0.05, 0.085, h.z)
        )
        return Paint(c * (1.0 + 0.08 * cv), KERATIN)
    if tag == "bill":
        if h.z <= 0.045:
            return Paint(pal.get("cere"), SKIN)
        var c = mix3(
            pal.get("bill"), pal.get("billTip"), smoothstep(0.07, 0.098, h.z)
        )
        return Paint(c * (1.0 + 0.08 * cv), KERATIN)
    if tag == "cere":
        return Paint(pal.get("cere"), SKIN)
    if tag == "nostril":
        return Paint(pal.get("cere") * 0.25, SKIN)
    var cond5 = tag == "eyelid" or tag == "eyesocket"
    if cond5:
        return Paint(pal.get("ring"), SKIN)
    if tag == "claw":
        return Paint(pal.get("claw"), KERATIN)
    var bare = tag == "tarsus" or tag == "toe" or tag == "pad"
    if bare:
        # Scutes: a network of small scales over the yellow skin.
        var sc = fbm3(p * 900.0, 1)
        return Paint(pal.get("leg") * (0.85 + 0.25 * sc), SCALES)
    var mottle_ok = 0.0
    var c: V3
    if is_card(tag):
        var cp = card_point(tag, s.local, bone.endswith("R"))
        var id = Float64(s.bone) * 0.37
        c = _card_color(pal, t, cp.kind, cp.t, cp.top, id)
        return Paint(c * (1.0 + 0.3 * cv), FEATHER)
    var cond6 = tag == "boot" or tag == "cuff"
    var cond7 = (
        tag == "arm" or tag == "hand" or tag == "patagium" or tag == "wrist"
    )
    if bone == "head":
        c = pal.get("head")
        if golden:
            c = pal.get("face")
        elif juv:
            c = mix3(
                pal.get("head"), pal.get("face"), smoothstep(0.0, -0.03, h.y)
            )
    elif cond6:
        c = pal.get("boot")
        mottle_ok = 0.5
    elif bone.startswith("tibia"):
        c = mix3(pal.get("under"), pal.get("boot"), 0.5) if golden else pal.get(
            "under"
        )
        mottle_ok = 0.7
    elif cond7:
        # The coverts: top or underwing by the wing plane's normal, which is
        # the segment's lateral axis.
        var top = s.local.x > 0.0 or tag == "wrist"
        c = pal.get("body")
        if not top:
            c = pal.get("under")
            mottle_ok = 1.0
        elif golden:
            c = mix3(
                pal.get("body"),
                pal.get("covertEdge"),
                0.22 * smoothstep(-1.0, 1.0, cv * 4.0),
            )
    elif bone == "tail":
        var dorsal = smoothstep(-0.2, 0.5, n.y)
        c = mix3(pal.get("under"), pal.get("body"), dorsal)
        var cond8 = not golden and not juv
        if cond8:
            var tb = V3(0.0, _ax(-0.06, 0.05).y, _ax(-0.06, 0.05).z)
            var u = (
                dot(p - tb, V3(0.0, -0.616, -0.788))
                + (fbm3(p * 70.0, 2) - 0.5) * 0.012
            )
            c = mix3(c, pal.get("tail"), smoothstep(0.02, 0.036, u))
        else:
            mottle_ok = 0.6
    else:
        var dorsal = smoothstep(-0.2, 0.5, n.y)
        c = mix3(pal.get("under"), pal.get("body"), dorsal)
        mottle_ok = 1.0 - dorsal * 0.7
    # The hood: the bald adult's white head and neck with a ragged edge;
    # the golden eagle's golden crown, nape and hind neck.
    var hooded = bone.startswith("neck") or bone == "chest" or bone == "head"
    if hooded:
        var nb = _ax(0.19, -0.03)
        var occ = _hl(V3(0.0, -0.026, -0.058))
        var nd = occ - nb
        var ht = dot(p - nb, nd) / dot(nd, nd)
        var jag = (fbm3(p * 60.0, 3) - 0.5) * 0.35
        var cond9 = not golden and not juv
        if cond9:
            var hood_c = occ + V3(0.0, -0.008, 0.01)
            var hood_r = 0.1 - (t.get("hood", 0.26) - 0.26) * 0.15
            var r = length(p - hood_c) + jag * 0.05
            var hood = smoothstep(hood_r + 0.008, hood_r - 0.004, r)
            var shade = mix3(
                pal.get("head"),
                srgb(0xD4D2CC),
                0.3 * smoothstep(-0.1, -0.7, n.y) * smoothstep(0.9, 1.2, ht),
            )
            c = mix3(c, shade, hood)
        elif golden:
            var gw = (
                smoothstep(0.45, 0.8, ht + jag * 0.5)
                * smoothstep(-0.25, 0.45, -0.8 * n.z + 0.6 * n.y)
                * smoothstep(0.035, 0.0, h.z)
            )
            c = mix3(c, pal.get("nape"), gw)
        elif bone != "head":
            var h0 = t.get("hood", 0.26)
            c = mix3(
                c, pal.get("head"), smoothstep(h0, h0 + 0.1, ht + jag) * 0.7
            )
        mottle_ok *= 1.0 - smoothstep(0.2, 0.5, ht)
    # The juvenile's mottling: irregular white blotches on the underparts,
    # the armpits and the trousers.
    # A golden eagle is not mottled: its juvenile shows white patches.
    var mot = 0.0 if golden else t.get("mottle", 0.0)
    var mottled = mot > 0.0 and mottle_ok > 0.0
    if mottled:
        var mm = fbm3(p * 48.0 + V3(3.0, 0.0, 0.0), 4)
        var thr = 0.68 - 0.2 * mot * mottle_ok
        var blotch = smoothstep(thr - 0.05, thr + 0.06, mm)
        c = mix3(c, pal.get("white"), blotch * 0.45 * mottle_ok)
    # Contour feathers: a soft shingle of feather tips.
    var sh = fbm3(V3(p.x * 220.0, p.y * 220.0, p.z * 140.0), 2)
    c = c * (0.9 + 0.2 * sh)
    return Paint(c * (1.0 + 0.3 * cv), FEATHER)
