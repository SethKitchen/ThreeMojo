# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The true frogs: procedural-animals' `species/frog/`.

The American bullfrog, Lithobates catesbeianus (the default), its pale
morph, and the common frog, Rana temporaria. The reference is an adult
female bullfrog, 140 mm from snout to vent, in the classic sitting pose:
forelegs upright on flat hands, hind legs folded in a Z beside the body,
the long webbed feet flat and pointing forward. It has no neck and no
tail. The head is broad and flat with large bulging eyes and a round
tympanum behind each one, larger than the eye in males.
"""

from extensions.animals.coat import (
    SKIN,
    WET,
    CoatSample,
    EyeLook,
    Paint,
    Palette,
    mix3,
    palette_of,
    srgb,
)
from extensions.sdf.ids import BoneId
from extensions.animals.parts import (
    BODY,
    JAW,
    TONGUE,
)
from extensions.sdf.sculpt import ell_y
from extensions.animals.kit import (
    EyeSpec,
    eye_frame_of,
    sculpt_eye_socket,
)
from extensions.animals.noise import cells3, fbm3
from extensions.animals.options import AnimalOptions, AnimalRandom
from extensions.animals.rig import Rig, quadruped_bones
from extensions.sdf.field import SdfModel
from extensions.animals.traits import Traits, pick_age, pick_sex
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
)
from extensions.animals.warp import legs_warp, length_warp, scale_about_warp
from std.math import atan2, cos, floor, pi, sin, sqrt

# The head's origin: on the midline, level with the eye centers.
comptime HEAD_O = V3(0.0, 0.06, 0.049)
# The finest cell, at the `HERO` tier: the head's cell in the original.
comptime CELL = 0.00068
# The left eye's center, head-local.
comptime EYE_C = V3(0.0152, 0.0012, -0.0002)
# The sprawl of the resting stance: knees and elbows turned out.
comptime SPRAWL = 0.25

# The variants, in procedural-animals' order.
comptime BULLFROG = 0
comptime BULLFROG_PALE = 1
comptime COMMON_FROG = 2

# The color schemes.
comptime GREEN = 0
comptime OLIVE = 1
comptime PALE = 2
comptime TEMPORARIA = 3


def frog_variant_names() -> List[String]:
    """Return the frog's variants.

    Returns:
        The bullfrog, the pale bullfrog and the common frog.
    """
    return [String("bullfrog"), "bullfrog-pale", "common-frog"]


def frog_traits(mut r: AnimalRandom, options: AnimalOptions) raises -> Traits:
    """Draw one frog: procedural-animals' `variation`.

    A bullfrog is green or olive (males mostly green); its males have a
    tympanum larger than the eye, a yellow throat, thicker forearms and
    a nuptial pad, and are a little smaller than females. The common frog
    is smaller and brown. A young frog is much smaller, with a big head
    and greener skin.

    Args:
        r: The individual's stream.
        options: The caller's sex, age and variant.

    Returns:
        The traits.

    Raises:
        Error: If the requested variant is not one of the three.
    """
    var sex = pick_sex(options.sex, r)
    var age = pick_age(options.age)
    var variant = BULLFROG
    if options.variant.value >= 0:
        if options.variant.value >= 3:
            raise Error("The species has no such color variant")
        variant = options.variant.value
    var t = Traits(sex, age, variant)
    var juv = t.juvenile() > 0.0
    var male = t.male()
    var temporaria = variant == COMMON_FROG
    var color: Int
    if temporaria:
        color = TEMPORARIA
    elif variant == BULLFROG_PALE:
        color = PALE
    else:
        color = GREEN if r.next() < (0.75 if male else 0.45) else OLIVE
    t.set("color", Float64(color))
    var size: Float64
    if temporaria:
        size = 0.55 * (1.0 + 0.08 * r.g()) * (0.97 if male else 1.03)
    else:
        size = (0.92 if male else 1.0) * (1.0 + 0.07 * r.g())
    if juv:
        size *= 0.42
    t.set("size", size)
    t.set(
        "tympanum",
        (0.0102 if male else 0.0073)
        * (1.0 + 0.07 * r.g())
        * (0.8 if juv else 1.0),
    )
    t.set("headWidth", (1.0 + 0.035 * r.g()) * (1.04 if juv else 1.0))
    t.set(
        "plump",
        (1.0 + 0.05 * r.g())
        * (0.98 if male else 1.03)
        * (0.95 if juv else 1.0),
    )
    t.set("armK", 1.0 + 0.05 * r.g())
    t.set(
        "mottle",
        0.55 + 0.35 * r.next() if temporaria else 0.35 + 0.5 * r.next(),
    )
    t.set("mottleSize", 0.8 + 0.45 * r.next())
    t.set("minThick", 0.0008)
    t.warps.add(legs_warp(1.0 + 0.03 * r.g(), 0.02))
    t.warps.add(
        length_warp(1.0 + 0.03 * r.g() - (0.05 if juv else 0.0), -0.05, 0.02)
    )
    t.warps.add(
        scale_about_warp(
            HEAD_O,
            (1.0 + 0.03 * r.g())
            * (1.22 if juv else 1.0)
            * (0.96 if temporaria else 1.0),
            0.02,
            0.045,
        )
    )
    t.set("coatWarmth", (1.2 if temporaria else 0.8) * (2.0 * r.next() - 1.0))
    t.set("coatLightness", 0.12 * (2.0 * r.next() - 1.0))
    var green = 2.0 * r.next() - 1.0
    t.set(
        "coatGreen",
        0.6 * green if temporaria else 0.5 * green + (0.3 if male else 0.0),
    )
    t.set("coatSeed", Float64(Int(r.next() * 1e6)))
    return t^


def _eye() -> EyeSpec:
    return EyeSpec(
        EYE_C,
        0.0079,
        0.0,
        1.0,
        0.42,
        0.0013,
        0.0081,
        0.0009,
        0.0006,
        6.0 * pi / 180.0,
        0.0052,
        0.0071,
    )


def frog_eye(t: Traits) -> EyeSpec:
    """Return the frog's left eye: a large bulging globe looking out and
    up, with a wide, nearly round aperture and a thick upper lid.

    Args:
        t: The individual. Every frog has the same eye.

    Returns:
        The eye, head-local.
    """
    return _eye()


def frog_look(t: Traits) -> EyeLook:
    """Return the frog's eye colors: a horizontal bar pupil in a gold or
    bronze iris, and no visible sclera.

    Args:
        t: The individual. The common frog's iris is darker bronze.

    Returns:
        The look.
    """
    if t.variant == COMMON_FROG:
        return EyeLook(
            V3(0.24, 0.12, 0.03),
            mix3(V3(0.44, 0.25, 0.06), V3(0.68, 0.46, 0.16), 0.35),
            V3(0.06, 0.035, 0.015),
            V3(0.05, 0.04, 0.02),
            0.38,
            -2.2,
        )
    return EyeLook(
        V3(0.42, 0.26, 0.05),
        mix3(V3(0.62, 0.4, 0.09), V3(0.9, 0.66, 0.22), 0.35),
        V3(0.1, 0.06, 0.015),
        V3(0.05, 0.04, 0.02),
        0.38,
        -2.2,
    )


def _hl(v: V3) -> V3:
    return v + HEAD_O


def _solve2(a: V3, c: V3, l1: Float64, l2: Float64, pole: V3) -> V3:
    # The knee or elbow of a two-bone chain, bent toward the pole.
    var d = c - a
    var dd = length(d)
    var e1 = normalize(d)
    var e2 = normalize(pole - e1 * dot(pole, e1))
    var cos_a = clamp(
        (l1 * l1 + dd * dd - l2 * l2) / (2.0 * l1 * dd), -1.0, 1.0
    )
    return a + e1 * (cos_a * l1) + e2 * (sqrt(1.0 - cos_a * cos_a) * l1)


def _joints() -> Rig:
    # The sitting frog's joints, left side placed and mirrored.
    var rig = Rig()
    rig.set("tailBase", V3(0.0, 0.021, -0.052))
    rig.set("lumbosacral", V3(0.0, 0.037, -0.03))
    rig.set("lumbarMid", V3(0.0, 0.042, -0.017))
    rig.set("thoraxRear", V3(0.0, 0.045, -0.004))
    rig.set("chestMid", V3(0.0, 0.047, 0.009))
    rig.set("neckBase", V3(0.0, 0.049, 0.018))
    rig.set("neckMid", V3(0.0, 0.0505, 0.023))
    rig.set("occiput", V3(0.0, 0.052, 0.028))
    rig.set("nose", V3(0.0, 0.0505, 0.088))
    rig.set("jawHinge", V3(0.0, 0.0395, 0.03))
    rig.set("jawTip", V3(0.0, 0.0405, 0.086))
    rig.set("scapTopL", V3(0.013, 0.054, 0.012))
    rig.set("shoulderL", V3(0.0175, 0.034, 0.016))
    rig.set("wristL", V3(0.025, 0.0055, 0.011))
    rig.set("mcpL", V3(0.025, 0.0036, 0.0225))
    rig.set("ftoeL", V3(0.025, 0.0011, 0.0395))
    var hip = V3(0.0105, 0.028, -0.044)
    rig.set("hipL", hip)
    # The heel beside the vent, the tarsus and the long foot forward.
    var tt = 4.4 * pi / 180.0
    var hock = V3(0.035, 0.0056 + 0.0377 * sin(tt), hip.z - 0.0175)
    var mtp = V3(0.035, 0.0056, hock.z + 0.0377 * cos(tt))
    rig.set("hockL", hock)
    rig.set("mtpL", mtp)
    rig.set("htoeL", V3(0.035, 0.0012, mtp.z + 0.0606))
    rig.set(
        "kneeL",
        _solve2(hip, hock, 0.064, 0.071, V3(0.12 + SPRAWL * 1.6, 0.0, 1.0)),
    )
    rig.set(
        "elbowL",
        _solve2(
            V3(0.0175, 0.034, 0.016),
            V3(0.025, 0.0055, 0.011),
            0.026,
            0.022,
            V3(0.08 + SPRAWL * 1.6, 0.0, -1.0),
        ),
    )
    var ec = _hl(EYE_C)
    rig.set("eyeBaseL", ec)
    rig.set("eyeTopL", V3(ec.x, ec.y + 0.008, ec.z))
    rig.set("throatBase", V3(0.0, 0.044, 0.036))
    rig.set("throatTip", V3(0.0, 0.03, 0.046))
    rig.set("tongueBase", V3(0.0, 0.0425, 0.079))
    rig.set("tongueTip", V3(0.0, 0.0435, 0.046))
    rig.mirror_joints()
    return rig^


def frog_rig(t: Traits) raises -> Rig:
    """Return the frog's skeleton in bind pose, the sitting frog.

    The standard quadruped bones without a tail or ears; the ilia and
    the urostyle are the pelvis, the tarsus is the metatarsus bone. The
    eyes, the throat and the tongue have their own bones.

    Args:
        t: The individual.

    Returns:
        The rig.

    Raises:
        Error: If a bone names a missing joint.
    """
    var rig = _joints()
    quadruped_bones(rig, 0, ears=False, jaw=True)
    for side in [String("L"), String("R")]:  # pragma: no branch
        _ = rig.add_bone(
            "eye" + side, "eyeBase" + side, "eyeTop" + side, "head"
        )
    _ = rig.add_bone("throat", "throatBase", "throatTip", "head")
    _ = rig.add_bone("tongue", "tongueBase", "tongueTip", "jaw")
    return rig^


def _tympanum(t: Traits) -> Tuple[V3, V3, Float64]:
    # The left tympanum, head-local: its center, outward normal, radius.
    var r = t.get("tympanum", 0.0105 if t.male() else 0.0074) * (
        0.78 if t.variant == COMMON_FROG else 1.0
    )
    return (V3(0.0262, -0.0085, -0.0235), normalize(V3(1.0, 0.12, -0.25)), r)


def _surface_along(m: SdfModel, p: V3, dir: V3) -> V3:
    # Where the ray `p + t dir`, `t` within 2 cm, crosses the body sculpted
    # so far.
    var ids = m.part_list(BODY)
    var lo = -0.02
    var hi = 0.02
    for _ in range(40):  # pragma: no branch
        var mid = 0.5 * (lo + hi)
        if m.eval_list(ids, p + dir * mid) < 0.0:
            lo = mid
        else:
            hi = mid
    return p + dir * (0.5 * (lo + hi))


def _fold_slot(
    mut m: SdfModel,
    jt: V3,
    a: V3,
    b: V3,
    start: Float64,
    len: Float64,
    tag: String,
    bone: BoneId,
) raises:
    # A carved slot in the fold of a joint, so the pressed-together
    # segments keep their skins apart.
    var da = normalize(a - jt)
    var db = normalize(b - jt)
    var bis = normalize(da + db)
    var axis = normalize(cross(da, db))
    var poly: List[Float64] = [0.0, -0.02, len, -0.02, len, 0.02, 0.0, 0.02]
    _ = m.fin(
        tag,
        bone,
        jt + bis * start,
        bis,
        axis,
        poly,
        0.0026,
        round=0.0012,
        k=0.0006,
        carve=True,
    )


def frog_sculpt(mut m: SdfModel, rig: Rig, t: Traits) raises:
    """Sculpt the frog: procedural-animals' `sculptFrog`, primitive for
    primitive.

    Args:
        m: The sculpt to add to.
        rig: The frog's rig in bind pose.
        t: The individual.

    Raises:
        Error: If the rig lacks a joint or a bone, or the sculpt refuses
            a primitive.
    """
    var male = t.male()
    var temporaria = t.variant == COMMON_FROG
    var plump = t.get("plump")

    # TRUNK: the vent low, the sacral hump, a plump belly.
    var body_ax = normalize(V3(0.0, 0.22, 1.0))
    var spine2 = rig.bone("spine2")
    var chest = rig.bone("chest")
    var pelvis = rig.bone("pelvis")
    _ = m.ell(
        "trunk",
        spine2,
        V3(0.0, 0.0375, -0.012),
        V3(0.032 * plump, 0.0205, 0.037),
        axis=body_ax,
        k=0.0,
    )
    _ = m.ell(
        "chest",
        chest,
        V3(0.0, 0.041, 0.012),
        V3(0.026 * plump, 0.0185, 0.02),
        axis=body_ax,
        k=0.012,
    )
    _ = m.ell(
        "shoulders",
        chest,
        V3(0.0, 0.049, 0.015),
        V3(0.024, 0.012, 0.016),
        k=0.012,
    )
    _ = m.ell(
        "belly",
        spine2,
        V3(0.0, 0.027, -0.016),
        V3(0.031 * plump, 0.0135, 0.03),
        axis=normalize(V3(0.0, 0.3, 1.0)),
        k=0.014,
    )
    _ = m.ell(
        "hump",
        pelvis,
        V3(0.0, 0.041, -0.033),
        V3(0.022, 0.0165, 0.017),
        k=0.012,
    )
    _ = m.ell(
        "rump",
        pelvis,
        V3(0.0, 0.027, -0.046),
        V3(0.0175, 0.0155, 0.0135),
        axis=normalize(V3(0.0, 0.5, 1.0)),
        k=0.012,
    )
    _ = m.ell(
        "vent",
        pelvis,
        V3(0.0, 0.016, -0.059),
        V3(0.004, 0.0022, 0.004),
        k=0.002,
        carve=True,
    )

    # HEAD, head-local.
    var h = rig.bone("head")
    var hw = t.get("headWidth")
    _ = m.ell(
        "cranium",
        h,
        _hl(V3(0.0, -0.01, -0.008)),
        V3(0.0268 * hw, 0.0105, 0.03),
        k=0.012,
    )
    _ = m.ell(
        "snout",
        h,
        _hl(V3(0.0, -0.0115, 0.013)),
        V3(0.019 * hw, 0.0088, 0.027),
        k=0.01,
    )
    var tym = _tympanum(t)
    for side in [String("L"), String("R")]:  # pragma: no branch
        var s = 1.0 if side == "L" else -1.0
        # The canthus: a soft ridge from the eye to the nostril.
        _ = m.cone(
            "canthus",
            h,
            _hl(V3(0.0105 * s, -0.0028, 0.006)),
            _hl(V3(0.0052 * s, -0.0045, 0.0305)),
            0.0028,
            0.0018,
            k=0.005,
        )
        # The cheeks and the corners of the jaw: the head is widest here.
        _ = m.ell(
            "cheek",
            h,
            _hl(V3(0.0205 * s * hw, -0.0145, -0.017)),
            V3(0.0095, 0.0092, 0.0145),
            k=0.009,
        )
        _ = m.ell(
            "lipwall",
            h,
            _hl(V3(0.0165 * s * hw, -0.0142, 0.002)),
            V3(0.0075, 0.0048, 0.028),
            axis=normalize(V3(-0.32 * s, 0.0, 1.0)),
            k=0.008,
        )
        _ = m.ell(
            "temple",
            h,
            _hl(V3(0.02 * s * hw, -0.0065, -0.028)),
            V3(0.009, 0.008, 0.011),
            k=0.008,
        )
        # The nostrils: small raised rims with the opening carved.
        _ = m.sphere(
            "naris",
            h,
            _hl(V3(0.0056 * s, -0.0048, 0.0318)),
            0.0019,
            k=0.0025,
        )
        _ = m.sphere(
            "nostril",
            h,
            _hl(V3(0.0058 * s, -0.0035, 0.0322)),
            0.0009,
            k=0.0006,
            carve=True,
        )
        # The tympanum: a flat disc set a little into the side of the head.
        var tc = V3(tym[0].x * s, tym[0].y, tym[0].z)
        var tn = V3(tym[1].x * s, tym[1].y, tym[1].z)
        var ts = _surface_along(m, _hl(tc), tn)
        _ = m.ell(
            "tympanum",
            h,
            ts + tn * (0.0019 - 0.00035),
            V3(tym[2], tym[2], 0.0019),
            axis=tn,
            k=0.0012,
            carve=True,
        )
        # The supratympanic fold: from behind the eye over the tympanum
        # and down behind it to the shoulder.
        var f0 = _hl(V3(0.0142 * s, 0.0012, -0.0095))
        var f1 = _hl(V3(0.0228 * s, -0.001, -0.0245))
        var f2 = _hl(V3(0.0268 * s, -0.0075, -0.037))
        var f3 = V3(0.024 * s, 0.037, 0.018)
        _ = m.cone("stfold", h, f0, f1, 0.0017, 0.0021, k=0.004)
        _ = m.cone("stfold", h, f1, f2, 0.0021, 0.002, k=0.004)
        _ = m.cone("stfold", chest, f2, f3, 0.002, 0.0015, k=0.005)
        # The eyes: bulging lids on their own bones.
        var eb = rig.bone("eye" + side)
        _ = sculpt_eye_socket(
            m,
            _eye(),
            HEAD_O,
            s,
            eb,
            orbit_r=V3(0.0085, 0.006, 0.004),
            orbit_at=V3(0.0, -0.001, 0.007),
            orbit_k=0.003,
        )
        # The fleshy turret the globe sits in.
        var ec = _hl(V3(EYE_C.x * s, EYE_C.y, EYE_C.z))
        _ = m.ell(
            "eyebase",
            eb,
            ec + V3(0.0005 * s, -0.004, -0.0005),
            V3(0.0075, 0.005, 0.0082),
            k=0.006,
        )
    # The mouth: the upper jaw's underside cut flat along the lip line.
    _ = m.ell(
        "palate",
        h,
        _hl(V3(0.0, -0.028, 0.005)),
        V3(0.05, 0.0115, 0.06),
        axis=normalize(V3(0.0, 0.04, 1.0)),
        k=0.0008,
        carve=True,
    )

    # LOWER JAW: rigid, meshed on its own.
    var jw = rig.bone("jaw")
    _ = m.ell(
        "mandible",
        jw,
        _hl(V3(0.0, -0.0185, 0.004)),
        V3(0.0232 * hw, 0.0066, 0.028),
        k=0.0,
        part=JAW,
    )
    _ = m.ell(
        "chin",
        jw,
        _hl(V3(0.0, -0.0188, 0.0255)),
        V3(0.0105, 0.0055, 0.0068),
        k=0.006,
        part=JAW,
    )
    for s in [1.0, -1.0]:  # pragma: no branch
        _ = m.ell(
            "jawcorner",
            jw,
            _hl(V3(0.0195 * s * hw, -0.0188, -0.017)),
            V3(0.0062, 0.0062, 0.0105),
            k=0.006,
            part=JAW,
        )

    # THROAT: the buccal floor and the vocal sac.
    var th = rig.bone("throat")
    _ = m.ell(
        "throat",
        th,
        V3(0.0, 0.0355, 0.036),
        V3(0.0205, 0.0082, 0.019),
        k=0.012,
    )
    _ = m.ell(
        "gular",
        th,
        V3(0.0, 0.0335, 0.022),
        V3(0.0195, 0.0095, 0.012),
        k=0.012,
    )

    # TONGUE: rigid, attached at the front of the jaw.
    var tg = rig.bone("tongue")
    var tb = rig.j("tongueBase")
    var tt = rig.j("tongueTip")
    _ = m.cone(
        "tongue",
        tg,
        tb,
        lerp(tb, tt, 0.82),
        0.0028,
        0.0048,
        k=0.0,
        part=TONGUE,
    )
    _ = m.ell(
        "tonguetip",
        tg,
        lerp(tb, tt, 0.88),
        V3(0.0068, 0.0032, 0.0055),
        k=0.003,
        part=TONGUE,
    )

    # DORSOLATERAL FOLDS of the common frog.
    if temporaria:
        var fold_bones: List[String] = ["head", "chest", "spine3", "spine2"]
        for s in [1.0, -1.0]:  # pragma: no branch
            var pts: List[V3] = [
                _hl(V3(0.0125 * s, 0.0005, -0.012)),
                V3(0.0165 * s, 0.059, 0.013),
                V3(0.0175 * s, 0.0565, -0.008),
                V3(0.0165 * s, 0.054, -0.026),
                V3(0.0135 * s, 0.047, -0.042),
            ]
            for i in range(4):  # pragma: no branch
                _ = m.cone(
                    "dlfold",
                    rig.bone(fold_bones[i]),
                    pts[i],
                    pts[i + 1],
                    0.0016,
                    0.0016,
                    k=0.004,
                )

    # LEGS.
    var arm = (1.18 if male else 1.0) * t.get("armK")
    for side in [String("L"), String("R")]:  # pragma: no branch
        var s = 1.0 if side == "L" else -1.0
        var lat = V3(s, 0.0, 0.0)
        # FRONT: short and upright, with four slender fingers.
        var sh = rig.j("shoulder" + side)
        var e = rig.j("elbow" + side)
        var w = rig.j("wrist" + side)
        var mc = rig.j("mcp" + side)
        var toe = rig.j("ftoe" + side)
        var hum = rig.bone("humerus" + side)
        var rad = rig.bone("radius" + side)
        var fpaw = rig.bone("fpaw" + side)
        _ = ell_y(
            m,
            "armpit",
            hum,
            lerp(sh, e, 0.3) + V3(-0.003 * s, 0.002, 0.002),
            e - sh,
            V3(0.0075, 0.012, 0.0075),
            lateral=lat,
            k=0.01,
        )
        _ = m.cone("upperarm", hum, sh, e, 0.0062 * arm, 0.0048 * arm, k=0.008)
        _ = m.cone("forearm", rad, e, w, 0.0048 * arm, 0.0031, k=0.003)
        _ = ell_y(
            m,
            "forearmmuscle",
            rad,
            lerp(e, w, 0.3),
            w - e,
            V3(0.0046 * arm, 0.0085, 0.0048 * arm),
            lateral=lat,
            k=0.003,
        )
        var dp = normalize(mc - w)
        _ = ell_y(
            m,
            "palm",
            rig.bone("metacarpus" + side),
            lerp(w, mc, 0.55),
            dp,
            V3(0.0045, 0.0068, 0.0022),
            lateral=normalize(cross(dp, V3(0.0, 1.0, 0.0))),
            k=0.003,
        )
        # The fingers fan out from the palm: III longest, forward and in.
        var fdir = normalize(toe - mc)
        var fing_a: List[Float64] = [-0.95, -0.62, -0.3, 0.08]
        var fing_l: List[Float64] = [0.0105, 0.0135, 0.0184, 0.0128]
        for i in range(4):  # pragma: no branch
            var d = normalize(V3(s * sin(fing_a[i]), fdir.y, cos(fing_a[i])))
            var base = mc - d * 0.001
            var tip = base + d * fing_l[i]
            tip = V3(tip.x, 0.0014, tip.z)
            _ = m.cone("finger", fpaw, base, tip, 0.0017, 0.0011, k=0.0015)
            _ = m.sphere("fingertip", fpaw, tip, 0.00135, k=0.001)
            if i == 0 and male:
                # The male's dark nuptial pad on the thumb.
                _ = m.ell(
                    "nuptial",
                    fpaw,
                    lerp(base, tip, 0.3),
                    V3(0.0022, 0.0022, 0.003),
                    axis=d,
                    k=0.002,
                )

        # HIND: a heavy thigh, the tibiofibula, the long tarsus and the
        # long webbed foot.
        var hp = rig.j("hip" + side)
        var kn = rig.j("knee" + side)
        var hk = rig.j("hock" + side)
        var mt = rig.j("mtp" + side)
        var ht = rig.j("htoe" + side)
        var fem = rig.bone("femur" + side)
        var tib = rig.bone("tibia" + side)
        var tar = rig.bone("metatarsus" + side)
        var hpaw = rig.bone("hpaw" + side)
        # The web between the thigh and the body.
        _ = ell_y(
            m,
            "groin",
            fem,
            lerp(hp, kn, 0.22) + V3(-0.002 * s, 0.004, 0.0),
            kn - hp,
            V3(0.0095, 0.016, 0.0095),
            lateral=lat,
            k=0.012,
        )
        _ = m.cone("thigh", fem, hp, kn, 0.0105, 0.0058, k=0.004)
        _ = ell_y(
            m,
            "thighmuscle",
            fem,
            lerp(hp, kn, 0.42) + V3(0.0015 * s, 0.0022, 0.0),
            kn - hp,
            V3(0.0128, 0.026, 0.0118),
            lateral=lat,
            k=0.0025,
        )
        _ = m.sphere("kneecap", tib, kn, 0.0046, k=0.005)
        _ = m.cone("shank", tib, kn, hk, 0.0056, 0.0036, k=0.006)
        _ = ell_y(
            m,
            "calf",
            tib,
            lerp(kn, hk, 0.36) + V3(0.0012 * s, 0.0006, 0.0),
            hk - kn,
            V3(0.0066, 0.0185, 0.0064),
            lateral=lat,
            k=0.006,
        )
        # The folds of the Z-folded leg: narrow slots down to each joint.
        _fold_slot(m, kn, hp, hk, 0.0045, 0.038, "kneefold", tib)
        _fold_slot(m, hk, kn, mt, 0.0035, 0.024, "anklefold", tar)
        _ = m.sphere("heel", tar, hk, 0.0038, k=0.004)
        _ = m.cone("tarsus", tar, hk, mt, 0.0036, 0.0031, k=0.004)
        # The foot: five long toes fanning out, IV longest, webbed to
        # near the tips.
        var fd = normalize(ht - mt)
        var fl = normalize(cross(fd, V3(0.0, 1.0, 0.0)))
        var inward = fl * (-1.0 if dot(fl, V3(s, 0.0, 0.0)) > 0.0 else 1.0)
        var toe_a: List[Float64] = [-0.08, 0.1, 0.28, 0.52, 0.74]
        var toe_l: List[Float64] = [0.021, 0.031, 0.043, 0.07, 0.042]
        var base0 = mt + fd * 0.004
        _ = m.ell(
            "sole",
            hpaw,
            mt + fd * 0.009,
            V3(0.0052, 0.0028, 0.0105),
            axis=fd,
            k=0.003,
        )
        var bases = List[V3]()
        var tips = List[V3]()
        for i in range(5):  # pragma: no branch
            var a = toe_a[i]
            var d = normalize(fd * cos(a) + inward * (-sin(a)))
            var b = base0 + d * 0.004
            var tip = b + d * (toe_l[i] - 0.008)
            tip = V3(tip.x, 0.0017, tip.z)
            bases.append(b)
            tips.append(tip)
            _ = m.cone(
                "toe", hpaw, mt + d * 0.002, tip, 0.0024, 0.0013, k=0.002
            )
            _ = m.sphere("toetip", hpaw, tip, 0.0015, k=0.0008)
        # The web: a thin membrane in the plane of the foot, its margin
        # notched between the toes.
        var o = V3(mt.x, mt.y - 0.0024, mt.z)
        var un = normalize(V3(ht.x, 0.0019, ht.z) - o)
        var v = normalize(cross(V3(0.0, 1.0, 0.0), un))
        var heel = mt + fd * -0.002 - o
        var poly: List[Float64] = [dot(heel, un), dot(heel, v)]
        var web_to: List[Float64] = [0.92, 0.9, 0.86, 0.7, 0.92]
        var pu = List[Float64]()
        var pv = List[Float64]()
        var ang = List[Float64]()
        for i in range(5):  # pragma: no branch
            var q = lerp(bases[i], tips[i], web_to[i]) - o
            pu.append(dot(q, un))
            pv.append(dot(q, v))
            ang.append(atan2(pv[i], pu[i]))
        # Order the toes by their angle, so the outline does not cross.
        var order: List[Int] = [0, 1, 2, 3, 4]
        for i in range(5):  # pragma: no branch
            for j in range(4 - i):
                if ang[order[j]] > ang[order[j + 1]]:
                    var tmp = order[j]
                    order[j] = order[j + 1]
                    order[j + 1] = tmp
        for k in range(5):  # pragma: no branch
            var i = order[k]
            poly.append(pu[i])
            poly.append(pv[i])
            if k < 4:
                var j = order[k + 1]
                poly.append((pu[i] + pu[j]) * 0.5 * 0.8)
                poly.append((pv[i] + pv[j]) * 0.5 * 0.8)
        _ = m.fin("web", hpaw, o, un, v, poly, 0.0014, k=0.0018, thin=True)


def _swatches() -> List[String]:
    return [
        String("head"),
        "lip",
        "back",
        "flank",
        "mottle",
        "belly",
        "throatF",
        "throatM",
        "leg",
        "band",
        "tymp",
        "web",
        "lipline",
        "mask",
        "fold",
        "speckle",
    ]


def _colors(color: Int) -> List[Int]:
    if color == OLIVE:
        return [
            0x77764E, 0x8C8C5C, 0x6A5C3E, 0x8A7C5A, 0x3C3020, 0xE4DEC6,
            0xDCD6BE, 0xCFB844, 0x665640, 0x302619, 0x6B5A3E, 0x5A4C3A,
            0x2A2418, 0x3C3020, 0x8A7C5A, 0x8A7C5A,
        ]  # fmt: skip
    if color == PALE:
        return [
            0x9C9864, 0xB0AC78, 0x92845A, 0xA8986E, 0x5E5236, 0xECE6D0,
            0xE6E0CA, 0xD8C460, 0x8C7C56, 0x564A30, 0x7A6846, 0x7A6C50,
            0x4A4028, 0x5E5236, 0xA8986E, 0xA8986E,
        ]  # fmt: skip
    if color == TEMPORARIA:
        return [
            0x86704E, 0x9C8866, 0x7B6546, 0x957E5E, 0x33251A, 0xE2D6B4,
            0xE6E2D6, 0xC4CCD4, 0x7A6446, 0x33251A, 0x3F2D20, 0x6A5642,
            0x2E2218, 0x36261B, 0xA48C64, 0xB07236,
        ]  # fmt: skip
    return [
        0x6A8640, 0x88A452, 0x5C6238, 0x80845E, 0x33351F, 0xE8E2C8,
        0xE0DAC2, 0xD6BF3C, 0x6E6E44, 0x34321F, 0x6A5838, 0x5A5840,
        0x2A2A18, 0x33351F, 0x80845E, 0x80845E,
    ]  # fmt: skip


def frog_palette(t: Traits) raises -> Palette:
    """Return one frog's palette: its color scheme, warmed, lightened and
    greened by the individual.

    The palette also holds the centers of the two tympana, found on the
    reference sculpt, for the painter.

    Args:
        t: The individual.

    Returns:
        The palette, in linear light.

    Raises:
        Error: If the palette tables differ in length, or the reference
            sculpt fails.
    """
    var names = _swatches()
    var base = palette_of(names, _colors(Int(t.get("color", 0.0))))
    var w = t.get("coatWarmth", 0.0)
    var l = t.get("coatLightness", 0.0)
    var gr = t.get("coatGreen", 0.0)
    var pal = Palette()
    for name in names:  # pragma: no branch
        var c = base.get(name)
        var pale = name == "belly" or name == "throatF" or name == "throatM"
        if not pale:
            c = V3(
                c.x * (1.0 + 0.12 * w + l - 0.1 * gr),
                c.y * (1.0 + 0.03 * w + l + 0.06 * gr),
                c.z * (1.0 - 0.14 * w + l - 0.12 * gr),
            )
        pal.set(name, c)
    # The tympana, where the sculpt set them into the skin.
    var rig = frog_rig(t)
    var m = SdfModel()
    frog_sculpt(m, rig, t)
    # The sculpt has just added the frog's solids.
    for i in range(len(m.prims)):  # pragma: no branch
        if m.tags[m.prims[i].tag.value] == "tympanum":
            var c = m.prims[i].c
            pal.set("tymp" + ("L" if c.x > 0.0 else "R"), c)
    return pal^


def _limb(bone: String) -> Bool:
    return (
        bone.startswith("humerus")
        or bone.startswith("radius")
        or bone.startswith("metacarpus")
        or bone.startswith("fpaw")
        or bone.startswith("femur")
        or bone.startswith("tibia")
        or bone.startswith("metatarsus")
        or bone.startswith("hpaw")
    )


def _bone_ends(bone: String) -> Tuple[String, String]:
    var side = String(bone[byte = bone.byte_length() - 1 :])
    if bone.startswith("femur"):
        return ("hip" + side, "knee" + side)
    if bone.startswith("tibia"):
        return ("knee" + side, "hock" + side)
    if bone.startswith("metatarsus"):
        return ("hock" + side, "mtp" + side)
    if bone.startswith("humerus"):
        return ("shoulder" + side, "elbow" + side)
    return ("elbow" + side, "wrist" + side)


def frog_paint(
    pal: Palette, t: Traits, tag: String, bone: String, s: CoatSample
) -> Paint:
    """Paint one vertex of a frog.

    Wet, glossy skin: a green head and upper lip, an olive to brown back
    with dark mottling, lighter flanks, a cream belly, a pale or (in a
    breeding male bullfrog) yellow throat, legs with dark crossbands, a
    brown tympanum (with a pale ring and a dark center in males), a dark
    lip line and darker webbing. The common frog adds a dark temporal
    mask, pale dorsolateral folds and an orange-speckled belly.

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
    if s.part == TONGUE:
        return Paint(srgb(0xD89A8A), SKIN)
    var male = t.male()
    var temporaria = t.variant == COMMON_FROG
    var h = p - HEAD_O
    var side = 1.0 if p.x >= 0.0 else -1.0
    # The region: 0 trunk, 1 head, 2 lower jaw, 4 throat, 5 eye, 6 limb.
    var region = 0
    if s.part == JAW:
        region = 2
    elif bone.startswith("eye"):
        region = 5
    elif bone == "throat":
        region = 4
    elif bone == "head" or bone.startswith("neck"):
        region = 1
    elif _limb(bone):
        region = 6
    var leg = region == 6
    var up = n.y
    var ventral = max(
        smoothstep(-0.25, -0.6, up) * smoothstep(0.03, 0.015, p.y),
        smoothstep(-0.45, -0.85, up),
    )
    var mark = 1.0
    var pat = 1.0
    var pat_col = pal.get("mottle")
    var pat_i = 0.9
    var col = mix3(
        pal.get("flank"), pal.get("back"), smoothstep(-0.1, 0.55, up)
    )
    col = mix3(col, pal.get("belly"), ventral)
    var mouth = False
    if not leg:
        # The head: green, brighter on the upper lip.
        var head_w = (0.4 if region == 4 else 1.0) * smoothstep(
            -0.05, -0.022, h.z
        )
        var lip_band = smoothstep(-0.012, -0.018, h.y) * smoothstep(
            -0.03, -0.02, h.y
        )
        var hc = mix3(
            pal.get("head"),
            pal.get("lip"),
            lip_band * 0.8 + smoothstep(0.02, 0.035, h.z) * 0.2,
        )
        col = mix3(col, hc, head_w * smoothstep(-0.5, 0.3, up))
    # The throat and the chin's underside.
    var under_throat = region == 4 or region == 2 or (region == 1 and up < -0.3)
    if under_throat:
        var thr = pal.get("throatM") if male else pal.get("throatF")
        var under = smoothstep(0.2, -0.4, up) if region == 4 else smoothstep(
            -0.2, -0.6, up
        )
        col = mix3(col, thr, under)
    if leg:
        # The legs: dark crossbands on the upper (outer) side, pale below.
        var foot = bone.startswith("fpaw") or bone.startswith("hpaw")
        var hand = bone.startswith("metacarpus") or bone.startswith("fpaw")
        var up_l = max(up, 0.9 * n.x * side)
        var outer = smoothstep(-0.3, 0.4, up_l) * (0.7 if foot else 1.0)
        var lc = mix3(
            pal.get("belly"), pal.get("leg"), smoothstep(-0.8, -0.35, up_l)
        )
        if bone.startswith("femur"):
            lc = mix3(
                lc,
                mix3(pal.get("belly"), pal.get("flank"), 0.4),
                smoothstep(-0.2, -0.7, up_l) * 0.6,
            )
        if foot:
            lc = mix3(pal.get("web"), pal.get("leg"), 0.5)
        if hand:
            lc = mix3(lc, pal.get("belly"), 0.25)
        col = lc
        if tag == "web":
            col = mix3(pal.get("web"), pal.get("leg"), 0.2)
        if tag == "nuptial":
            col = mix3(pal.get("band"), pal.get("leg"), 0.3)
        var banded = not foot and not hand
        if banded and outer > 0.25:
            var ends = _bone_ends(bone)
            var joints = _joints()
            var ia = joints.find_joint(ends[0])
            var ib = joints.find_joint(ends[1])
            # A caller may supply a limb name outside the reference rig.
            if min(ia, ib) >= 0:
                var a = joints.joints[ia]
                var b = joints.joints[ib]
                var ax = normalize(b - a)
                var along = dot(p - a, ax)
                var period = 0.0105 if temporaria else 0.0125
                var phase = Float64(ends[0].byte_length() * 7 % 10) * 0.1
                var ph = (
                    along / period + phase + 0.25 * (fbm3(p * 300.0, 2) - 0.5)
                )
                var f = abs(ph - floor(ph) - 0.5)
                var wb = (0.2 if temporaria else 0.17) + 0.05 * (
                    fbm3(p * 120.0, 2) - 0.5
                )
                pat = min(pat, (f - wb) * period + (1.0 - outer) * 0.002)
                pat_col = pal.get("band")
    var on_head = region == 1 or region == 0
    if on_head:
        # The tympanum: a flat brown disc, a pale ring and a dark center
        # in males.
        var tc = pal.get("tymp" + ("L" if side > 0.0 else "R"))
        var dd = length(p - tc)
        var rr = _tympanum(t)[2]
        if dd < rr + 0.002:
            var disc = smoothstep(rr + 0.0012, rr - 0.0004, dd)
            var tcol = pal.get("tymp")
            if male:
                tcol = mix3(
                    tcol,
                    mix3(pal.get("tymp"), pal.get("flank"), 0.6),
                    smoothstep(rr * 0.55, rr * 0.8, dd)
                    * (1.0 - smoothstep(rr * 0.85, rr, dd)),
                )
                tcol = mix3(
                    tcol,
                    mix3(pal.get("tymp"), pal.get("head"), 0.35),
                    smoothstep(rr * 0.3, rr * 0.1, dd),
                )
            col = mix3(col, tcol, disc)
            if abs(dd - rr) < 0.0012:
                mark = min(
                    mark, abs(dd - rr) - 0.0004 + (0.0003 if male else 0.0)
                )
        if tag == "stfold":
            col = mix3(col, mix3(col, pal.get("lip"), 0.4), 0.35)
    # The lip line: dark where the upper and lower jaws meet; the mouth's
    # pink lining deeper in.
    if region == 1:
        var cut = h.y + 0.0158
        if cut < 0.0 and h.z > -0.03:
            mouth = cut < -0.0045
            col = srgb(0xC98A7E) if mouth else pal.get("lipline")
        elif cut < 0.0008 and h.z > -0.03:
            mark = min(mark, cut - 0.0004)
    elif region == 2:
        var top = h.y + 0.0128
        if top > 0.0:
            mouth = top > 0.0045
            col = srgb(0xC98A7E) if mouth else pal.get("lipline")
        else:
            col = mix3(col, pal.get("belly"), smoothstep(-0.3, 0.2, up) * 0.35)
            if top > -0.0012:
                mark = min(mark, -top - 0.0004)
    if region == 5 or region == 1:
        # The fleshy lid a little paler at its rim, a dark line at the
        # aperture.
        var ef = eye_frame_of(_eye(), HEAD_O, side)
        var de = length(p - ef.c)
        if de < 0.0115:
            var cz = dot(normalize(p - ef.c), ef.z)
            col = mix3(col, pal.get("lip"), smoothstep(0.35, 0.58, cz) * 0.35)
            if abs(cz - 0.62) < 0.08:
                mark = min(mark, (abs(cz - 0.62) - 0.04) * 0.01)
    # The nostrils: dark.
    var nos = _hl(V3(0.0058 * side, -0.0035, 0.0322))
    mark = min(mark, length(p - nos) - 0.0013)
    if temporaria:
        var masked = region == 1 or region == 5 or region == 0
        if masked:
            # The dark temporal mask: from behind the eye back and down
            # over the tympanum.
            var hx = abs(h.x)
            var mz = (h.z + 0.004) / -0.042
            var in_mask = hx > 0.012 and mz > -0.1 and mz < 1.15
            if in_mask:
                var yc = mix(-0.002, -0.014, clamp(mz, 0.0, 1.0))
                var half = 0.0065 + 0.003 * sin(pi * clamp(mz, 0.0, 1.0))
                var sd = max(
                    max(abs(h.y - yc) - half, -mz * 0.02),
                    max(
                        (mz - 1.0) * 0.02,
                        (0.2 - dot(n, V3(side, 0.1, 0.0))) * 0.01,
                    ),
                )
                # No band runs on the head or the body, so `pat` is still
                # one here, far above any `sd`.
                pat = sd
                pat_col = pal.get("mask")
                pat_i = 0.95
        if tag == "dlfold":
            col = mix3(col, pal.get("fold"), 0.7)
        if ventral > 0.3 and region == 0:
            var sp = fbm3(p * 700.0, 2)
            col = mix3(
                col,
                pal.get("speckle"),
                smoothstep(0.58, 0.68, sp) * ventral * 0.6,
            )
    # The dark mottling: large on the back, smaller on the flanks and the
    # head, none on the belly; the legs carry crossbands instead.
    var mottled = region != 2 and region != 4 and not leg and n.y > -0.25
    if mottled:
        var back_k = smoothstep(-0.2, 0.6, n.y)
        var rad = (0.0034 if temporaria else 0.0028) * (0.7 + 0.5 * back_k)
        var on_face = region == 1 or region == 5
        if on_face:
            rad *= 0.55 if temporaria else 0.6
        var snout = region == 1 and p.z > HEAD_O.z + 0.02
        if snout:
            rad *= 0.6
        rad *= t.get("mottleSize")
        var cs = rad * 2.0 * (1.35 if temporaria else 1.5)
        var q = p + V3(0.7, 0.3, 1.1) * (0.002 * (fbm3(p * 260.0, 2) - 0.5))
        var cl = cells3(q * (1.0 / cs), Int(t.get("coatSeed", 0.0)) % 7919)
        if cl.id < t.get("mottle", 0.7):
            var sd = cl.nearest * cs - rad * (0.75 + 0.5 * cl.id)
            sd += 0.0022 * (fbm3(p * 420.0, 3) - 0.5)
            if sd < pat:
                pat = sd
                pat_col = pal.get("mottle") if region == 0 else mix3(
                    pal.get("mottle"), pal.get("head"), 0.25
                )
                pat_i = 0.85 if temporaria else 0.6
    # The female bullfrog's gray-mottled throat.
    var gray_throat = (
        not male and not temporaria and (region == 4 or region == 2)
    )
    if gray_throat and up < -0.2:
        var gt = fbm3(p * 260.0, 3)
        col = mix3(
            col,
            mix3(col, V3(0.25, 0.25, 0.2), 0.5),
            smoothstep(0.55, 0.65, gt) * 0.6,
        )
    if not mouth:
        col = mix3(col, pat_col, pat_i * smoothstep(0.0003, -0.0003, pat))
        col = mix3(
            col, V3(0.02, 0.018, 0.01), smoothstep(0.0002, -0.0002, mark)
        )
    if t.juvenile() > 0.0:
        col = mix3(col, mix3(col, pal.get("head"), 0.6), 0.3)
    var cv = fbm3(p * 60.0, 3) - 0.5
    col = V3(
        col.x * (1.0 + 0.16 * cv),
        col.y * (1.0 + 0.13 * cv),
        col.z * (1.0 + 0.1 * cv),
    )
    return Paint(col, SKIN if mouth else WET)
