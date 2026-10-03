# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The domestic chicken, Gallus gallus domesticus: procedural-animals'
`species/chicken/`.

A ground bird with burst flight only: hen, rooster and chick. The
reference individual is a 2 kg brown layer hen: hip 0.21 m, back 0.27 m,
crown 0.345 m, 0.42 m from the bill tip to the tail tip. The breeds are
the variants: the brown (red) layer, the white Leghorn, the black
Australorp, the barred Plymouth Rock, the buff Orpington and the
speckled Sussex. A flock is mostly hens, and now and then a chick.

Roosters stand more upright on longer legs, with a longer neck, a tall
comb, long wattles, spurs and two sickle feathers a side. Chicks are a
round ball of down with a big head, short legs and stubby wings.

procedural-animals binds the wings half open and renders the flight
feathers as cards. This port binds them folded, at rest, and sculpts
each flight feather as a flattened ellipsoid and the closed tail as a
fin a side. The folded wing's covert shield and lid are fitted over the
flight-feather stack as the original fits them (its `wingStack.js` and
`coverts.js`).
"""

from extensions.animals.coat import (
    FEATHER,
    FUR,
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
from extensions.animals.parts import (
    JAW,
    WATTLE,
)
from extensions.sdf.sculpt import ell_y
from extensions.animals.kit import (
    EyeSpec,
    eye_frame_of,
    sculpt_eye_socket,
)
from extensions.animals.noise import fbm3
from extensions.animals.options import (
    ANY_AGE,
    ANY_SEX,
    ADULT,
    FEMALE,
    JUVENILE,
    MALE,
    AnimalOptions,
    AnimalRandom,
)
from extensions.animals.rig import Rig
from extensions.sdf.field import SdfModel
from extensions.animals.species.bird_rig import (
    DEG,
    UNSET,
    Feather,
    FeatherFrame,
    WingPose,
    bird_bones,
    card_point,
    covert_card,
    extension,
    feather_fins,
    feather_frame,
    feather_frames,
    feather_joints,
    is_card,
    lerp_pose,
    neck_chain,
    place_toe,
    plume,
    primary,
    rectrix,
    secondary,
    shingle,
    star_union,
    vane_width,
    wing_fk,
    wing_joints,
    wing_normal,
    wing_segment,
)
from extensions.animals.traits import Traits
from extensions.sdf.vector import (
    V3,
    clamp,
    cross,
    dot,
    length,
    lerp,
    mirror,
    mix,
    normalize,
    smoothstep,
)
from extensions.animals.warp import (
    girth_warp,
    legs_warp,
    scale_about_warp,
)
from std.math import asin, cbrt, cos, floor, ceil, pi, pow, sin, sqrt

comptime NECK_SEGS = 4
# The reference hen's head origin, between the eyes. An individual's
# head sits elsewhere: its eye spec carries the difference.
comptime HEAD_O = V3(0.0, 0.328, 0.108)
# The finest cell, at the `HERO` tier: the hen's head cell in the
# original.
comptime CELL = 0.0012
# How far the tail is fanned at rest: the motion data's `fanRest`.
comptime FAN_REST = 0.02

# The breeds, in procedural-animals' order.
comptime RED = 0
comptime LEGHORN = 1
comptime AUSTRALORP = 2
comptime BARRED = 3
comptime BUFF = 4
comptime SPECKLED = 5


def chicken_variant_names() -> List[String]:
    """Return the chicken's breeds.

    Returns:
        Red (a brown layer), Leghorn, Australorp, barred (Plymouth Rock),
        buff (Orpington) and speckled (Sussex).
    """
    return [
        String("red"),
        "leghorn",
        "australorp",
        "barred",
        "buff",
        "speckled",
    ]


def _mass(breed: Int, male: Bool) -> Float64:
    # Body mass in kilograms, hen and cock, from the breed standards.
    var hen: List[Float64] = [2.0, 1.8, 2.6, 2.8, 3.0, 3.0]
    var cock: List[Float64] = [3.0, 2.5, 3.6, 3.6, 3.8, 3.8]
    return cock[breed] if male else hen[breed]


def _fluff(breed: Int) -> Float64:
    # Loose-feathered heavy breeds carry part of their bulk as fluff.
    var f: List[Float64] = [1.0, 0.95, 1.06, 1.05, 1.14, 1.05]
    return f[breed]


def chicken_traits(
    mut r: AnimalRandom, options: AnimalOptions
) raises -> Traits:
    """Draw one chicken: procedural-animals' `variation`.

    The breed, the sex (a third of the flock are roosters) and the age (a
    chick now and then) are drawn first, then the size from the breed's
    mass, then the individual's form: the head, the comb, the wattles,
    the fluff and, for a rooster, the spurs and the sickles.

    Args:
        r: The individual's stream.
        options: The caller's sex, age and breed.

    Returns:
        The traits. The form's numbers are stored by their original
        names, such as `legK` and `combH`.

    Raises:
        Error: If the requested breed is not one of the six.
    """
    if options.variant.value >= 6:
        raise Error("The chicken has no such breed")
    for _ in range(5):
        _ = r.next()
    var r0 = r.next()
    var r1 = r.next()
    var r2 = r.next()
    var breed: Int
    if options.variant.value >= 0:
        breed = options.variant.value
    else:
        var edges: List[Float64] = [0.3, 0.48, 0.63, 0.78, 0.9, 1.0]
        breed = 0
        while breed < 5:
            if r0 < edges[breed]:
                break
            breed += 1
    var sex = options.sex
    if sex == ANY_SEX:
        sex = MALE if r1 < 0.34 else FEMALE
    var age = options.age
    if age == ANY_AGE:
        age = JUVENILE if r2 < 0.08 else ADULT
    var t = Traits(sex, age, breed)
    var juv = t.juvenile() > 0.0
    var male = t.male()
    var m = _mass(breed, male) * (1.0 + 0.1 * r.g())
    var size = 0.3 * (1.0 + 0.06 * r.g()) if juv else cbrt(m / 2.0)
    t.set("size", size)
    var leghorn = breed == LEGHORN
    if juv:
        t.set("chick", 1.0)
        t.set("billK", 0.6)
        t.set("legK", 0.72)
        t.set("femurK", 0.7)
        t.set("tarK", 0.72)
        t.set("hipK", 0.74)
        t.set("neckK", 0.42)
        t.set("headK", 1.75)
        t.set("eyeK", 1.05)
        t.set("toeK", 0.85)
        t.set("toeR", 1.15)
        t.set("wingK", 0.52)
        t.set("priK", 0.25)
        t.set("recK", 0.08)
        t.set("fwK", 0.45)
        t.set("fluff", 1.1)
    else:
        t.set("fluff", _fluff(breed) * (1.0 + 0.03 * r.g()))
        t.set("headK", 1.12)
        if male:
            t.set("legK", 1.07)
            t.set("hipK", 1.06)
            t.set("neckK", 1.14)
            t.set("headK", 1.18)
            t.set("up", 13.0)
            t.set("tailUp", 30.0)
            t.set("spur", 0.8 + 0.4 * abs(r.g()))
            t.set("sickles", (1.08 if leghorn else 1.0) * (1.0 + 0.06 * r.g()))
            t.set("recK", 1.25)
            t.set("comb", 1.45 * (1.12 if leghorn else 1.0))
            t.set(
                "combH",
                2.2 * (1.15 if leghorn else 1.0) * (1.0 + 0.08 * r.g()),
            )
            t.set("wattle", 2.1 * (1.0 + 0.1 * r.g()))
            t.set("earlobe", 1.4)
        else:
            t.set("comb", 1.3 if leghorn else 1.0)
            t.set("combH", (1.9 if leghorn else 1.0) * (1.0 + 0.12 * r.g()))
            t.set("combFlop", 0.9 if leghorn else 0.0)
            t.set("wattle", (1.3 if leghorn else 1.0) * (1.0 + 0.12 * r.g()))
            t.set("earlobe", 1.25 if leghorn else 1.0)
            t.set("spur", 0.0)
            t.set("up", 5.0 if leghorn else 0.0)
    t.set("tone", 1.0 + 0.08 * r.g())
    if not juv:
        t.warps.add(legs_warp(1.0 + 0.035 * r.g(), 0.09))
        t.warps.add(scale_about_warp(_ho(t), 1.0 + 0.03 * r.g(), 0.03, 0.06))
        t.warps.add(girth_warp(1.0 + 0.04 * r.g(), 0.18, -0.12, 0.1, 0.04))
    t.set("coatSeed", Float64(Int(r0 * 1e4)))
    return t^


def _pitch_about(p: V3, c: V3, a: Float64) -> V3:
    var y = p.y - c.y
    var z = p.z - c.z
    var ca = cos(a)
    var sa = sin(a)
    return V3(p.x, c.y + y * ca + z * sa, c.z - y * sa + z * ca)


def _torso(t: Traits, p: V3) -> V3:
    # The reference torso lifted with the hip and pitched up about it: a
    # rooster stands more upright.
    var hip_y = 0.205 * t.get("hipK")
    var up = t.get("up", 0.0) * DEG
    return _pitch_about(
        V3(p.x, p.y + hip_y - 0.205, p.z), V3(0.0, hip_y, -0.028), up
    )


def _tv(t: Traits, v: V3) -> V3:
    return normalize(_torso(t, v) - _torso(t, V3(0.0, 0.0, 0.0)))


def _neck_base(t: Traits) -> V3:
    if t.juvenile() > 0.0:
        return V3(0.0, 0.205 * t.get("hipK") + 0.05, 0.045)
    return _torso(t, V3(0.0, 0.25, 0.07))


def _occiput(t: Traits) -> V3:
    var hk = t.get("headK")
    var nb = _neck_base(t)
    if t.juvenile() > 0.0:
        return V3(0.0, nb.y + 0.042, nb.z + 0.012)
    var nk = t.get("neckK")
    var o0 = V3(0.0, HEAD_O.y - 0.01 * hk, HEAD_O.z - 0.02 * hk)
    return V3(0.0, nb.y + (o0.y - 0.25) * nk, nb.z + (o0.z - 0.07) * nk)


def _ho(t: Traits) -> V3:
    # The individual's head origin: the reference head carried by its
    # neck.
    var hk = t.get("headK")
    var occ = _occiput(t)
    return V3(0.0, occ.y + 0.01 * hk, occ.z + 0.02 * hk)


def _lengths(t: Traits) -> V3:
    var k = t.get("wingK")
    return V3(0.077 * k, 0.07 * k, 0.066 * k)


def _fold(t: Traits) -> WingPose:
    # Folded high on the flank. An upright rooster folds it turned down at
    # the back, off the saddle.
    return WingPose(
        -76.0, 4.0, 76.0 - 2.0 * t.get("up", 0.0), 171.0, 170.0, 0.0, 0.0, 0.0
    )


def _glide(t: Traits) -> WingPose:
    _ = t.juvenile()
    return WingPose(6.0, 4.0, 6.0, 22.0, 12.0, 2.0, 2.0, 0.0)


def _feathers(t: Traits) -> List[Feather]:
    # procedural-animals' `feathersFor`: 10 primaries, 10 secondaries and
    # tertials, 7 rectrices a side held as a steep roof, and a rooster's
    # two sickles a side.
    var pk = t.get("priK")
    var rk = t.get("recK")
    var wk = t.get("fwK")
    var chick = t.juvenile() > 0.0
    var sickles = t.get("sickles", 0.0)
    var out = List[Feather]()
    var p: List[List[Float64]] = [
        [0.06, 0.128, 78, -4],
        [0.16, 0.136, 70, -2.5],
        [0.26, 0.145, 62, -1],
        [0.36, 0.154, 54, 0.5],
        [0.46, 0.163, 46, 2.7],
        [0.56, 0.171, 38, 2.5],
        [0.66, 0.178, 30, 2.3],
        [0.76, 0.18, 22, 2],
        [0.87, 0.172, 14, 1],
        [0.98, 0.15, 6, 0.5],
    ]
    for i in range(10):
        ref q = p[i]
        var f = primary(
            i,
            10,
            q[0],
            q[1] * pk,
            0.036 * wk,
            q[2],
            q[3],
            lift=Float64(9 - i) * 0.0008,
            twist=1.0,
            outer=0.42 if i < 3 else 0.34,
            curve=0.03,
            droop=0.01,
            tip_round=0.5,
            arch=0.03,
        )
        if i < 2:
            # The innermost primary coverts lie under the covert shield.
            f.cov_shift = 0.004
            f.cov_len_k = 0.3
            f.cov_lift = 0.003 if i == 0 and not chick else UNSET
        out.append(f)
    var s: List[List[Float64]] = [
        [0.03, 0.122],
        [0.13, 0.123],
        [0.23, 0.123],
        [0.33, 0.122],
        [0.43, 0.12],
        [0.53, 0.118],
        [0.63, 0.116],
        [0.73, 0.128],
        [0.83, 0.118],
        [0.93, 0.108],
    ]
    var st: List[Float64] = [1, 1, 1, 1, 1, 1, 0.9, 0.7, 0.62, 0.55]
    for i in range(10):
        var ln = s[i][1]
        if chick:
            ln = min(ln, 0.122) * st[i]
        var tertial = i >= 7 and not chick
        out.append(
            secondary(
                i,
                10,
                10,
                s[i][0],
                ln * pk,
                0.046 * wk,
                90.0 + Float64(i) * 3.5,
                163.0 + Float64(i) * 1.2,
                lift=0.008 + Float64(i) * 0.0008,
                twist=1.0,
                outer=0.42,
                tip_round=0.32 if tertial else 0.6,
                arch=0.03,
                base0=0.6 if tertial else 0.3,
                cov_skip=True,
            )
        )
    var rc: List[List[Float64]] = [
        [0.002, 0.13, 3, 12],
        [0.004, 0.128, 7, 6],
        [0.006, 0.125, 12, 0],
        [0.008, 0.12, 17, -6],
        [0.01, 0.113, 22, -12],
        [0.012, 0.105, 27, -18],
        [0.014, 0.096, 32, -24],
    ]
    var n = 9 if sickles > 0.0 else 7
    for i in range(7):
        ref q = rc[i]
        var tw = 80.0 if i == 0 else (
            74.0 if i == 1 else 72.0 - 2.0 * Float64(i)
        )
        var f = rectrix(
            i,
            n,
            q[0] * 1.4 + 0.006 if sickles > 0.0 else q[0],
            q[1] * rk,
            (0.034 if sickles > 0.0 else 0.042) * wk,
            q[2],
            1.0 + Float64(i) * 0.4,
            bend=q[3] + (-6.0 if sickles > 0.0 else 0.0),
            lift=0.0024 - Float64(i) * 0.0003,
            twist=90.0 - Float64(i) if sickles > 0.0 else tw,
            outer=0.44,
            tip_round=0.62,
            arc=55.0 + Float64(i) * 5.0 if sickles > 0.0 else 0.0,
        )
        f.cov_skip = True
        out.append(f)
    if sickles > 0.0:
        # The sickles: long, narrow, arching back and down over the tail.
        out.append(
            rectrix(
                7,
                n,
                0.001,
                0.36 * sickles,
                0.03 * wk,
                2.0,
                0.5,
                bend=30.0,
                lift=0.004,
                twist=90.0,
                outer=0.46,
                droop=0.02,
                tip_round=0.8,
                arc=118.0,
            )
        )
        out.append(
            rectrix(
                8,
                n,
                0.003,
                0.3 * sickles,
                0.026 * wk,
                3.0,
                1.0,
                bend=18.0,
                lift=0.0035,
                twist=90.0,
                outer=0.46,
                droop=0.02,
                tip_round=0.8,
                arc=108.0,
            )
        )
    return out^


def _coverts(t: Traits) -> V3:
    return V3(0.4, 0.5, 0.62 if t.get("sickles", 0.0) > 0.0 else 0.55)


def _joints(t: Traits) raises -> Rig:
    # procedural-animals' `chickenJoints`: the left joints, unmirrored.
    var juv = t.juvenile() > 0.0
    var leg_k = t.get("legK")
    var femur = 0.078 * t.get("femurK", leg_k)
    var tib = 0.118 * leg_k
    var tar = 0.08 * t.get("tarK", leg_k)
    var hip = V3(0.03, 0.205 * t.get("hipK"), -0.028)
    var fa = 32.0 * DEG
    var knee = V3(0.042, hip.y - femur * sin(fa), hip.z + femur * cos(fa))
    var lean = 16.0 * DEG
    var mtp_y = 0.009
    var ankle_y = mtp_y + tar * cos(lean)
    var dy = knee.y - ankle_y
    var dz = sqrt(max(1e-6, tib * tib - dy * dy))
    var ankle = V3(0.034, ankle_y, knee.z - dz)
    var mtp = V3(0.03, mtp_y, ankle.z + tar * sin(lean))
    var rig = Rig()
    var tail_base = _torso(t, V3(0.0, 0.244, -0.128))
    var tail_tip = _torso(t, V3(0.0, 0.262, -0.156))
    var tail_up = t.get("tailUp", 0.0)
    if tail_up > 0.0:
        # A rooster carries the tail higher.
        tail_tip = _pitch_about(tail_tip, tail_base, -tail_up * DEG)
    rig.set("synsacrum", _torso(t, V3(0.0, 0.218, -0.04)))
    rig.set("tailBase", tail_base)
    rig.set("tailTip", tail_tip)
    rig.set("neckBase", _neck_base(t))
    rig.set("shoulderL", _torso(t, V3(0.057, 0.232, 0.052)))
    if juv:
        # A chick: a round body, the tail stub barely out of the down, the
        # shoulder near the ball's surface.
        rig.set("synsacrum", V3(0.0, hip.y + 0.012, -0.03))
        rig.set("tailBase", V3(0.0, hip.y + 0.02, -0.075))
        rig.set("tailTip", V3(0.0, hip.y + 0.03, -0.088))
        rig.set("shoulderL", V3(0.068, hip.y + 0.045, 0.03))
    rig.set("hipL", hip)
    rig.set("kneeL", knee)
    rig.set("ankleL", ankle)
    rig.set("mtpL", mtp)
    var hk = t.get("headK")
    var bk = t.get("billK")
    var ho = _ho(t)
    rig.set("occiput", _occiput(t))
    rig.set(
        "bill",
        V3(0.0, ho.y - 0.007 * hk * bk, ho.z + (0.017 + 0.027 * bk) * hk),
    )
    rig.set("jawHinge", V3(0.0, ho.y - 0.012 * hk, ho.z - 0.007 * hk))
    rig.set(
        "jawTip", V3(0.0, ho.y - 0.012 * hk, ho.z + (0.017 + 0.023 * bk) * hk)
    )
    var tk = t.get("toeK")
    place_toe(rig, 3, 3.0, 0.032 * tk, 0.027 * tk, 0.005, 0.0035)
    place_toe(rig, 2, -24.0, 0.024 * tk, 0.021 * tk, 0.005, 0.0035)
    place_toe(rig, 4, 27.0, 0.026 * tk, 0.022 * tk, 0.005, 0.0035)
    place_toe(rig, 1, -10.0, 0.013 * tk, 0.013 * tk, 0.005, 0.0035, back=True)
    var t0 = normalize(V3(0.0, 1.0, 0.5 if juv else 0.62))
    var t1 = normalize(V3(0.0, 1.0, 0.2 if juv else 0.05))
    neck_chain(rig, NECK_SEGS, t0, t1, 0.42)
    _ = wing_joints(rig, _lengths(t), _fold(t))
    return rig^


def _frames(
    t: Traits, rig: Rig, feathers: List[Feather]
) raises -> List[FeatherFrame]:
    return feather_frames(
        rig, _lengths(t), _fold(t), _fold(t), _glide(t), feathers, FAN_REST
    )


def chicken_rig(t: Traits) raises -> Rig:
    """Return the chicken's skeleton in bind pose, its wings folded.

    Leg bones are from layer osteometry: tibiotarsus 118 mm, femur and
    tarsometatarsus about two thirds of it; wing bones humerus 77, ulna 70
    and hand 66 mm. The femur points forward and down inside the body,
    the drumstick runs down and back to the hock, and the scaled shank
    stands almost upright. The rig adapts to the individual's form.

    Args:
        t: The individual.

    Returns:
        The rig.

    Raises:
        Error: If a bone names a missing joint.
    """
    var rig = _joints(t)
    var feathers = _feathers(t)
    feather_joints(rig, feathers, _frames(t, rig, feathers))
    rig.mirror_joints()
    bird_bones(rig, NECK_SEGS, feathers)
    return rig^


def chicken_eye(t: Traits) -> EyeSpec:
    """Return the chicken's left eye: lateral, big and round, scaled with
    the head.

    The spec is relative to the reference hen's head origin: it carries
    the individual's head offset.

    Args:
        t: The individual.

    Returns:
        The eye, head-local.
    """
    var k = t.get("headK")
    var e = t.get("eyeK")
    var ho = _ho(t)
    return EyeSpec(
        V3(
            0.0122 * k,
            0.0008 * k + ho.y - HEAD_O.y,
            0.0015 * k + ho.z - HEAD_O.z,
        ),
        0.0068 * k * e,
        0.0021 * k * e,
        1.15,
        0.06,
        0.0008 * k,
        0.0049 * k * e,
        0.0003 * k * e,
        0.0,
        0.0,
        0.0045 * k * e,
        0.0047 * k * e,
    )


def chicken_look(t: Traits) -> EyeLook:
    """Return the chicken's eye colors: an orange iris, dark in a chick.

    Args:
        t: The individual.

    Returns:
        The look.
    """
    var sclera = V3(0.02, 0.02, 0.02)
    if t.juvenile() > 0.0:
        return EyeLook(
            srgb(0x201A16), srgb(0x3A2E26), srgb(0x181410), sclera, 0.56, 0.0
        )
    return EyeLook(
        srgb(0xE07A22), srgb(0xEB9A30), srgb(0xC8641C), sclera, 0.37, 0.0
    )


# ---------------------------------------------------------------- the stack


struct _Stack(Movable):
    """The flight-feather stack in the forearm's plan: the highest card
    over the wing's motion, in millimeters on a 1 mm grid
    (procedural-animals' `wingStack`)."""

    var top: List[Float64]

    def __init__(out self):
        self.top = List[Float64](length=_NX * _NY, fill=-1e30)

    def near(self, x: Float64, y: Float64, r: Float64) -> Float64:
        var ix0 = Int(floor(x - _X0 + 0.5))
        var iy0 = Int(floor(y - _Y0 + 0.5))
        var rr = Int(ceil(r))
        var m = -1e30
        for iy in range(iy0 - rr, iy0 + rr + 1):
            for ix in range(ix0 - rr, ix0 + rr + 1):
                var out = ix < 0 or iy < 0 or ix >= _NX or iy >= _NY
                if out:
                    continue
                if (ix - ix0) * (ix - ix0) + (iy - iy0) * (iy - iy0) > rr * rr:
                    continue
                m = max(m, self.top[iy * _NX + ix])
        return m


comptime _X0 = -40.0
comptime _Y0 = -70.0
comptime _NX = 320
comptime _NY = 160


def _tri(mut st: _Stack, a: V3, b: V3, c: V3):
    var x0 = Int(floor(min(a.x, min(b.x, c.x)) - _X0))
    var x1 = Int(ceil(max(a.x, max(b.x, c.x)) - _X0))
    var y0 = Int(floor(min(a.y, min(b.y, c.y)) - _Y0))
    var y1 = Int(ceil(max(a.y, max(b.y, c.y)) - _Y0))
    var den = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
    if abs(den) < 1e-9:
        return
    for iy in range(max(0, y0), min(_NY - 1, y1) + 1):
        for ix in range(max(0, x0), min(_NX - 1, x1) + 1):
            var px = _X0 + Float64(ix)
            var py = _Y0 + Float64(iy)
            var l1 = ((b.y - c.y) * (px - c.x) + (c.x - b.x) * (py - c.y)) / den
            var l2 = ((c.y - a.y) * (px - c.x) + (a.x - c.x) * (py - c.y)) / den
            var l3 = 1.0 - l1 - l2
            var outside = l1 < -0.08 or l2 < -0.08 or l3 < -0.08
            if outside:
                continue
            var h = l1 * a.z + l2 * b.z + l3 * c.z
            var k = iy * _NX + ix
            st.top[k] = max(st.top[k], h)


def _raster(
    mut st: _Stack,
    ff: FeatherFrame,
    f: Feather,
    shape: Feather,
    len_k: Float64,
    width_k: Float64,
    lift: Float64,
    shift: Float64,
    p0: V3,
    x_ax: V3,
    t_ax: V3,
    n_ax: V3,
):
    # One card's top layer, projected into the plan.
    var a = ff.axis
    var n = ff.normal
    var tv = normalize(cross(n, a))
    var ln = f.len * len_k
    var w = f.width * width_k
    var root = ff.root + n * lift + a * shift
    comptime NT = 24
    comptime NC = 6
    var g = List[V3](capacity=(NT + 1) * (NC + 1))
    for i in range(NT + 1):
        var t = Float64(i) / Float64(NT)
        var vw = vane_width(shape, min(t, 0.999), w)
        var cu = shape.curve * ln * t * t
        var dr = shape.droop * ln * t * t
        for j in range(NC + 1):
            var c = -1.0 + 2.0 * Float64(j) / Float64(NC)
            var ww = vw[0] if c < 0.0 else vw[1]
            var p = (
                root
                + a * (t * ln)
                + tv * (cu + c * ww)
                + n * (-dr - abs(c) * ww * shape.arch + 0.00025)
            )
            var q = p - p0
            g.append(
                V3(
                    dot(q, x_ax) * 1000.0,
                    dot(q, t_ax) * 1000.0,
                    dot(q, n_ax) * 1000.0,
                )
            )
    for i in range(NT):
        for j in range(NC):
            var pa = g[i * (NC + 1) + j]
            var pb = g[(i + 1) * (NC + 1) + j]
            var pc = g[(i + 1) * (NC + 1) + j + 1]
            var pd = g[i * (NC + 1) + j + 1]
            _tri(st, pa, pb, pc)
            _tri(st, pa, pc, pd)


def _wing_stack(t: Traits) -> _Stack:
    # The highest card over the wing's motion: folded, half open, spread
    # and over-fanned.
    var st = _Stack()
    var states: List[Float64] = [0.0, 0.15, 0.3, 0.5, 0.7, 0.85, 1.0, 1.2]
    var fold = _fold(t)
    var glide = _glide(t)
    var ls = _lengths(t)
    var feathers = _feathers(t)
    var cov = _coverts(t)
    for e in states:
        var cfg = lerp_pose(fold, glide, min(1.0, e))
        var fr = wing_fk(1.0, ls, cfg)
        var e_h = min(
            1.25,
            extension(cfg.wrist * DEG, fold.wrist * DEG, glide.wrist * DEG)
            + max(0.0, e - 1.0),
        )
        var e_u = min(
            1.2,
            extension(cfg.elbow * DEG, fold.elbow * DEG, glide.elbow * DEG)
            + max(0.0, e - 1.0),
        )
        var p0 = fr.wrist
        var t_ax = normalize(cross(fr.n_u, fr.d_u))
        var x_ax = -fr.d_u
        for f in feathers:
            if f.kind == 0:
                var ff = feather_frame(
                    p0,
                    fr.d_m,
                    fr.n_m,
                    ls.z,
                    1.0,
                    f,
                    f.fold + (f.spread - f.fold) * e_h,
                    False,
                )
                _raster(
                    st, ff, f, f, 1.0, 1.0, 0.0, 0.0, p0, x_ax, t_ax, fr.n_u
                )
                var c = covert_card(f, cov)
                _raster(
                    st,
                    ff,
                    f,
                    c.shape,
                    c.len_k,
                    c.width_k,
                    c.lift,
                    c.shift,
                    p0,
                    x_ax,
                    t_ax,
                    fr.n_u,
                )
            elif f.kind == 1:
                var ff = feather_frame(
                    p0,
                    fr.d_u,
                    fr.n_u,
                    ls.y,
                    1.0,
                    f,
                    f.fold + (f.spread - f.fold) * e_u,
                    True,
                )
                _raster(
                    st, ff, f, f, 1.0, 1.0, 0.0, 0.0, p0, x_ax, t_ax, fr.n_u
                )
    return st^


def _inside(poly: List[Float64], x: Float64, y: Float64) -> Bool:
    var c = False
    var n = len(poly) // 2
    var j = n - 1
    for i in range(n):
        var ax = poly[i * 2]
        var ay = poly[i * 2 + 1]
        var bx = poly[j * 2]
        var by = poly[j * 2 + 1]
        var crosses = (ay > y) != (by > y)
        var cond1 = crosses and x < (bx - ax) * (y - ay) / (by - ay) + ax
        if cond1:
            c = not c
        j = i
    return c


def _box(poly: List[Float64]) -> Tuple[V3, V3]:
    var lo = V3(1e9, 1e9, 0.0)
    var hi = V3(-1e9, -1e9, 0.0)
    for i in range(0, len(poly), 2):
        lo = V3(min(lo.x, poly[i]), min(lo.y, poly[i + 1]), 0.0)
        hi = V3(max(hi.x, poly[i]), max(hi.y, poly[i + 1]), 0.0)
    return (lo, hi)


@fieldwise_init
struct _Shield(Copyable, Movable):
    """The folded wing's covert shield and lid: outlines in the plan, the
    planes their faces are fitted to, their thicknesses and rims."""

    var core: List[Float64]
    var plane: V3
    var t: Float64
    var round: Float64
    var lid: List[Float64]
    var lid_plane: V3
    var lid_t: Float64
    var lid_round: Float64
    var lid_k: Float64


def _shield(t: Traits) -> _Shield:
    # procedural-animals' `shieldLayout`: the shield's top is a plane
    # fitted just above the stack under it; the lid's underside is fitted
    # above the stack, its top running on from the shield's.
    var wk = t.get("wingK")
    var st = _wing_stack(t)
    var core: List[Float64] = [
        -7,
        -6,
        -4,
        -15,
        4,
        -22,
        18,
        -25,
        36,
        -24,
        52,
        -19,
        64,
        -15,
        71,
        -10,
        74,
        -4,
        72,
        1,
        67,
        4,
        60,
        6,
        50,
        7,
        38,
        7.5,
        26,
        7,
        15,
        6,
        6,
        4,
        -3,
        1,
    ]
    for i in range(len(core)):
        core[i] *= wk
    var bx_ = _box(core)
    var need = List[V3]()
    var y = floor(bx_[0].y)
    while y <= ceil(bx_[1].y):
        var x = floor(bx_[0].x)
        while x <= ceil(bx_[1].x):
            if _inside(core, x, y):
                var l = st.near(x, y, 1.2) + 0.45
                if l > -1e29:
                    need.append(V3(x, y, l))
            x += 1.0
        y += 1.0
    var best = V3(0.0, 0.0, 0.0)
    var best_m = 1e300
    var bx = 0.0
    while bx <= 0.3001:
        var by = -0.2
        while by <= 0.2001:
            var a = -1e300
            for q in need:
                a = max(a, q.z - bx * q.x - by * q.y)
            var m = 0.0
            for q in need:
                m += a + bx * q.x + by * q.y - q.z
            if m < best_m:
                best_m = m
                best = V3(a, bx, by)
            by += 0.005
        bx += 0.005
    var t_max = 0.0
    for i in range(0, len(core), 2):
        t_max = max(
            t_max, best.x + best.y * core[i] + best.z * core[i + 1] + 2.0
        )
    var lid: List[Float64] = [
        44,
        -22,
        58,
        -31,
        74,
        -31,
        84,
        -19,
        82,
        -12,
        68,
        -14,
        56,
        -16,
        44,
        -18,
    ]
    for i in range(len(lid)):
        lid[i] *= wk
    var lb = _box(lid)
    var lneed = List[V3]()
    var lpts = List[V3]()
    y = floor(lb[0].y)
    while y <= ceil(lb[1].y):
        var x = floor(lb[0].x)
        while x <= ceil(lb[1].x):
            if _inside(lid, x, y):
                lpts.append(V3(x, y, 0.0))
                var h = st.near(x, y, 1.5)
                if h > -1e29:
                    lneed.append(V3(x, y, h + 0.4))
            x += 1.0
        y += 1.0
    var lt = 5.2 * wk
    var lbest = V3(0.0, 0.0, 0.0)
    var lbest_m = 1e300
    bx = -0.3
    while bx <= 0.3001:
        var by = -0.4
        while by <= 0.4001:
            var a = -1e300
            for q in lneed:
                a = max(a, q.z - bx * q.x - by * q.y)
            var m = 0.0
            for q in lpts:
                var d = (
                    a
                    + bx * q.x
                    + by * q.y
                    + lt
                    - (best.x + best.y * q.x + best.z * q.y)
                )
                m += d * d
            if m < lbest_m:
                lbest_m = m
                lbest = V3(a, bx, by)
            by += 0.01
        bx += 0.01
    return _Shield(
        core^, best, t_max, 3.5, lid^, lbest, lt, 2.4 * wk, 0.008 * wk
    )


@fieldwise_init
struct _Plan(ImplicitlyCopyable):
    """The forearm's plan frame in bind space: the wrist, the plan's x
    toward the elbow, its y toward the trailing edge, and the wing's
    dorsal normal."""

    var wr: V3
    var x: V3
    var y: V3
    var n: V3

    def q(self, x: Float64, y: Float64, h: Float64) -> V3:
        return (
            self.wr
            + self.x * (x * 0.001)
            + self.y * (y * 0.001)
            + self.n * (h * 0.001)
        )


def _plan(rig: Rig, side: String) raises -> _Plan:
    var s = 1.0 if side == "L" else -1.0
    var n = wing_normal(rig, side)
    var wr = rig.j("wrist" + side)
    var d = normalize(wr - rig.j("elbow" + side))
    return _Plan(wr, -d, normalize(cross(n, d)) * s, n)


def _plate(
    mut m: SdfModel,
    rig: Rig,
    side: String,
    poly: List[Float64],
    plane: V3,
    th: Float64,
    rim: Float64,
    k: Float64,
    top: Bool,
) raises:
    # A slab in the plan whose top (or underside) is a fitted plane.
    var f = _plan(rig, side)
    var q0 = f.q(0.0, 0.0, plane.x)
    var u = normalize(f.q(1.0, 0.0, plane.x + plane.y) - q0)
    var v = f.q(0.0, 1.0, plane.x + plane.z) - q0
    v = normalize(v - u * dot(v, u))
    var np = cross(u, v)
    if dot(np, f.n) < 0.0:
        np = -np
    var flat = List[Float64]()
    for i in range(0, len(poly), 2):
        var x = poly[i]
        var y = poly[i + 1]
        var q = f.q(x, y, plane.x + plane.y * x + plane.z * y) - q0
        flat.append(dot(q, u))
        flat.append(dot(q, v))
    var o = q0 + np * (-th / 2.0 if top else th / 2.0)
    _ = m.fin(
        "coverts",
        rig.bone("ulna" + side),
        o,
        u,
        v,
        flat,
        th,
        round=min(th / 2.0, rim),
        k=k,
    )


# ---------------------------------------------------------------- sculpt


def _wing_frame(t: Traits, rig: Rig) raises -> Tuple[V3, V3, V3, V3]:
    # The folded forearm's frame: the wrist, the ulna, its dorsal normal
    # and the trailing direction (left side).
    var fr = wing_fk(1.0, _lengths(t), _fold(t))
    var wr = rig.j("shoulderL") + fr.wrist
    return (wr, fr.d_u, fr.n_u, normalize(cross(fr.n_u, fr.d_u)))


def _flank_ell(
    mut m: SdfModel,
    rig: Rig,
    t: Traits,
    tag: String,
    c: V3,
    r: V3,
    h: Float64,
    k: Float64,
    carve: Bool,
    under: Float64 = 0.0,
) raises:
    # An ellipsoid placed in the folded wing's plan: the original's
    # `flankPad`, `wingBend` and `flankUnderWing`. `c` is in plan mm, `r`
    # the radii along, across and in depth, `h` the height above the
    # wing plane in mm.
    var wk = t.get("wingK")
    var wf = _wing_frame(t, rig)
    var d = wf[1]
    var n = wf[2]
    var tt = wf[3]
    var c0 = (
        wf[0]
        - d * (c.x * 0.001 * wk)
        + tt * (c.y * 0.001 * wk)
        + n * (h * 0.001)
    )
    var rr = V3(r.y * 0.001 * wk, r.z * 0.001, r.x * 0.001 * wk)
    if carve:
        rr = V3(r.y * 0.001 * wk, r.z * 0.001 * wk, r.x * 0.001 * wk)
        c0 = (
            wf[0]
            - d * (c.x * 0.001 * wk)
            + tt * (c.y * 0.001 * wk)
            + n * ((r.z - under) * 0.001 * wk)
        )
    for s in [1.0, -1.0]:
        var cc = c0 if s > 0.0 else mirror(c0)
        var ax = -d if s > 0.0 else mirror(-d)
        var up = n if s > 0.0 else mirror(n)
        _ = m.ell(
            tag, rig.bone("chest"), cc, rr, axis=ax, up=up, k=k, carve=carve
        )


def _wing_pocket(mut m: SdfModel, rig: Rig, t: Traits) raises:
    # The flank under the folded wing carved to a bed just under the
    # folded stack. The original carves one slab per folded card; their
    # union is the stack's underside. Here each row of cards (primaries,
    # their coverts, secondaries) is one slab: the union of its cards'
    # slab outlines in their mean plane, as deep as its lowest card's.
    var ls = _lengths(t)
    var fr = wing_fk(1.0, ls, _fold(t))
    var p0 = rig.j("shoulderL") + fr.wrist
    var cov = _coverts(t)
    for row in range(3):
        var frames = List[FeatherFrame]()
        var shapes = List[Feather]()
        var lens = List[Float64]()
        var widths = List[Float64]()
        for f in _feathers(t):
            var cond2 = row < 2 and f.kind == 0
            var cond3 = row == 2 and f.kind == 1
            if cond2:
                var ff = feather_frame(
                    p0, fr.d_m, fr.n_m, ls.z, 1.0, f, f.fold, False
                )
                if row == 0:
                    frames.append(ff)
                    shapes.append(f)
                    lens.append(f.len)
                    widths.append(f.width)
                else:
                    var c = covert_card(f, cov)
                    var lk = cov.x * (1.0 - 0.25 * Float64(f.i) / 9.0)
                    frames.append(
                        FeatherFrame(
                            ff.root + ff.normal * 0.0022 - ff.axis * 0.004,
                            ff.axis,
                            ff.normal,
                        )
                    )
                    shapes.append(c.shape)
                    lens.append(f.len * lk)
                    widths.append(f.width * 1.05)
            elif cond3:
                frames.append(
                    feather_frame(
                        p0, fr.d_u, fr.n_u, ls.y, 1.0, f, f.fold, True
                    )
                )
                shapes.append(f)
                lens.append(f.len)
                widths.append(f.width)
        _bed(m, rig, frames, shapes, lens, widths)


def _bed(
    mut m: SdfModel,
    rig: Rig,
    frames: List[FeatherFrame],
    shapes: List[Feather],
    lens: List[Float64],
    widths: List[Float64],
) raises:
    comptime G = 0.002
    comptime T = 0.03
    comptime INSET = 0.004
    var o = V3(0.0, 0.0, 0.0)
    var sa = V3(0.0, 0.0, 0.0)
    var sn = V3(0.0, 0.0, 0.0)
    for f in frames:
        o = o + f.root
        sa = sa + f.axis
        sn = sn + f.normal
    o = o * (1.0 / Float64(len(frames)))
    var a = normalize(sa)
    var n = normalize(sn - a * dot(sn, a))
    var tv = cross(n, a)
    var polys = List[List[Float64]]()
    var low = 1e9
    var cx = 0.0
    var cy = 0.0
    var count = 0
    for i in range(len(frames)):
        ref ff = frames[i]
        ref f = shapes[i]
        var ln = lens[i]
        var w = widths[i]
        var ftv = normalize(cross(ff.normal, ff.axis))
        var drop = f.droop * ln + f.arch * w * 0.66 + 0.00025
        low = min(low, dot(ff.root - o, n) - G - drop)
        var front = List[Float64]()
        var back = List[Float64]()
        for j in range(9):
            var tt = 0.04 + 0.96 * Float64(j) / 8.0
            var vw = vane_width(f, min(tt, 0.99), w)
            var cu = f.curve * ln * tt * tt
            var q1 = (
                ff.root
                + ff.axis * (tt * ln)
                + ftv * (cu + max(0.0, vw[1] - INSET))
                - o
            )
            var q2 = (
                ff.root
                + ff.axis * (tt * ln)
                + ftv * (cu - max(0.0, vw[0] - INSET))
                - o
            )
            front.append(dot(q1, a))
            front.append(dot(q1, tv))
            back.append(dot(q2, a))
            back.append(dot(q2, tv))
        var pts = front.copy()
        var j = 8
        while j >= 0:
            pts.append(back[j * 2])
            pts.append(back[j * 2 + 1])
            j -= 1
        for e in range(0, len(pts), 2):
            cx += pts[e]
            cy += pts[e + 1]
            count += 1
        polys.append(pts^)
    var union = star_union(polys, cx / Float64(count), cy / Float64(count), 20)
    var o0 = o + n * (low + T / 2.0)
    for s in [1.0, -1.0]:
        _ = m.fin(
            "wingPocket",
            rig.bone("chest"),
            o0 if s > 0.0 else mirror(o0),
            a if s > 0.0 else mirror(a),
            tv if s > 0.0 else mirror(tv),
            union,
            T,
            round=0.006,
            k=0.008,
            carve=True,
        )


def _e(
    mut m: SdfModel,
    rig: Rig,
    t: Traits,
    bone: String,
    tag: String,
    c: V3,
    r: V3,
    k: Float64,
    axis: V3 = V3(0.0, 0.0, 1.0),
) raises:
    # A torso ellipsoid written for the reference hen, carried through the
    # individual's torso transform.
    _ = m.ell(
        tag,
        rig.bone(bone),
        _torso(t, c),
        r,
        axis=_tv(t, axis),
        up=_tv(t, V3(0.0, 1.0, 0.0)),
        k=k,
    )


def chicken_sculpt(mut m: SdfModel, rig: Rig, t: Traits) raises:
    """Sculpt the chicken: procedural-animals' `sculptChicken`, primitive
    for primitive, then its flight feathers and tail.

    The torso, neck hackles, saddle and fluffy underparts are the body's
    shape. The head has a single comb, wattles and earlobes, the legs
    scaled shanks and, on a rooster, spurs. The folded wing lies in a bed
    carved in the flank, under its covert shield.

    Args:
        m: The sculpt to add to.
        rig: The chicken's rig in bind pose.
        t: The individual.

    Raises:
        Error: If the rig lacks a joint or a bone, or the sculpt refuses
            a primitive.
    """
    var juv = t.juvenile() > 0.0
    var male = t.male() and not juv
    var fl = t.get("fluff")
    var hk = t.get("headK")
    var bk = t.get("billK")
    var ho = _ho(t)
    var wk = t.get("wingK")

    if juv:
        # A chick: a round ball of down.
        var hy = rig.j("hipL").y
        var chest = rig.bone("chest")
        var pelvis = rig.bone("pelvis")
        _ = m.ell(
            "breast",
            chest,
            V3(0.0, hy + 0.03, 0.03),
            V3(0.07, 0.07, 0.07),
            k=0.0,
        )
        _ = m.ell(
            "belly",
            pelvis,
            V3(0.0, hy - 0.005, -0.025),
            V3(0.072, 0.065, 0.08),
            k=0.04,
        )
        _ = m.ell(
            "cushion",
            pelvis,
            V3(0.0, hy + 0.035, -0.06),
            V3(0.055, 0.05, 0.05),
            k=0.04,
        )
        _ = m.ell(
            "uppertail",
            rig.bone("tail"),
            lerp(rig.j("tailBase"), rig.j("tailTip"), 0.6),
            V3(0.02, 0.02, 0.02),
            k=0.03,
        )
        for s in [1.0, -1.0]:
            _ = m.ell(
                "flankfold",
                pelvis,
                V3(0.05 * s, hy - 0.01, -0.02),
                V3(0.03, 0.05, 0.06),
                k=0.035,
            )
            _ = m.ell(
                "scapular",
                chest,
                V3(0.045 * s, hy + 0.045, 0.01),
                V3(0.028, 0.022, 0.045),
                k=0.03,
            )
            _ = m.ell(
                "fluff",
                pelvis,
                V3(0.035 * s, hy - 0.045, -0.035),
                V3(0.03, 0.03, 0.045),
                k=0.03,
            )
        # Its folded wing lies on the ball in a shallow bed.
        # (Its blend is softer than the original's 8 mm: without fur shells
        # the bed's rim showed as a dent.)
        _flank_ell(
            m,
            rig,
            t,
            "flankFlat",
            V3(80.0, 8.0, 0.0),
            V3(140.0, 120.0, 30.0),
            0.0,
            0.02 * wk,
            True,
            2.5,
        )
        _wing_pocket(m, rig, t)
    else:
        # TORSO, feathered.
        _e(
            m,
            rig,
            t,
            "chest",
            "breast",
            V3(0.0, 0.184, 0.06),
            V3(0.066, 0.078, 0.074),
            0.0,
            V3(0.0, 0.3, 1.0),
        )
        _e(
            m,
            rig,
            t,
            "chest",
            "keel",
            V3(0.0, 0.142, 0.036),
            V3(0.054, 0.054, 0.064),
            0.03,
        )
        _e(
            m,
            rig,
            t,
            "chest",
            "mantle",
            V3(0.0, 0.236, -0.012),
            V3(0.064, 0.048, 0.108),
            0.03,
            V3(0.0, 0.03, 1.0),
        )
        _e(
            m,
            rig,
            t,
            "pelvis",
            "belly",
            V3(0.0, 0.136 - 0.006 * (fl - 1.0), -0.055),
            V3(0.064 * fl, 0.066 * fl, 0.086),
            0.035,
        )
        _e(
            m,
            rig,
            t,
            "pelvis",
            "cushion",
            V3(0.0, 0.246, -0.108),
            V3(0.052, 0.052, 0.062),
            0.035,
            V3(0.0, 0.5, -1.0),
        )
        _e(
            m,
            rig,
            t,
            "pelvis",
            "vent",
            V3(0.0, 0.165, -0.128),
            V3(0.052 * fl, 0.062, 0.052),
            0.03,
        )
        _e(
            m,
            rig,
            t,
            "chest",
            "crop",
            V3(0.0, 0.222, 0.092),
            V3(0.034, 0.034, 0.03),
            0.03,
        )
        for s in [1.0, -1.0]:
            _e(
                m,
                rig,
                t,
                "pelvis",
                "flankfold",
                V3(0.048 * s * fl, 0.15, -0.025),
                V3(0.03, 0.058, 0.08),
                0.03,
            )
            _e(
                m,
                rig,
                t,
                "chest",
                "scapular",
                V3(0.04 * s, 0.25, 0.008),
                V3(0.026, 0.018, 0.06),
                0.025,
                V3(0.0, 0.08, 1.0),
            )
            _e(
                m,
                rig,
                t,
                "pelvis",
                "fluff",
                V3(0.034 * s * fl, 0.1, -0.062),
                V3(0.03 * fl, 0.034, 0.058),
                0.03,
            )
        if male:
            # The saddle hackles hang from the back over the wing tips.
            for s in [1.0, -1.0]:
                _e(
                    m,
                    rig,
                    t,
                    "pelvis",
                    "saddle",
                    V3(0.034 * s, 0.22, -0.09),
                    V3(0.028, 0.052, 0.055),
                    0.03,
                    V3(0.0, -0.6, -1.0),
                )
        # The flank under the folded wing: filled out at its front,
        # flattened under it, bedded, and the wing's bend tucked in.
        _flank_ell(
            m,
            rig,
            t,
            "flankPad",
            V3(10.0, 20.0, 0.0),
            V3(45.0, 22.0, 14.0),
            -11.0,
            0.016,
            False,
        )
        _flank_ell(
            m,
            rig,
            t,
            "flankFlat",
            V3(90.0, 22.0, 0.0),
            V3(100.0, 50.0, 30.0),
            0.0,
            0.02 * wk,
            True,
            1.0 + 35.0 * max(0.0, fl - 1.0),
        )
        _wing_pocket(m, rig, t)
        _flank_ell(
            m,
            rig,
            t,
            "wingBend",
            V3(-9.0, -3.0, 0.0),
            V3(19.0, 20.0, 14.0),
            -1.5,
            0.014,
            False,
        )
        # The tail coverts: the base of the roof-shaped tail.
        var tb = rig.j("tailBase")
        var tt = rig.j("tailTip")
        var td = normalize(tt - tb)
        var tail = rig.bone("tail")
        _ = m.ell(
            "uppertail",
            tail,
            lerp(tb, tt, 0.6) + td * 0.012,
            V3(0.024, 0.034, 0.03),
            axis=td,
            k=0.025,
        )
        _ = m.ell(
            "undertail",
            tail,
            lerp(tb, tt, 0.3) + V3(0.0, -0.022, -0.01),
            V3(0.028, 0.03, 0.03),
            k=0.025,
        )

    # NECK, with its hackles.
    var r0 = (0.03 if juv else 0.036) * (1.08 if male else 1.0)
    var r1 = 0.0175 * hk
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
            r0 + (r1 - r0) * pow(u0, 0.75),
            r0 + (r1 - r0) * pow(u1, 0.75),
            k=0.02,
        )
    if not juv:
        # The hackle cape over the shoulders, long and full on roosters.
        var nb = rig.j("neckBase")
        var n1 = rig.j("neck1")
        var n2 = rig.j("neck2")
        _ = m.ell(
            "hackle",
            rig.bone("neck0"),
            lerp(nb, n1, 0.4) + V3(0.0, 0.004, -0.018),
            V3(0.042 * (1.12 if male else 1.0), 0.04, 0.036),
            k=0.025,
        )
        _ = m.ell(
            "hackle",
            rig.bone("neck1"),
            lerp(n1, n2, 0.5) + V3(0.0, 0.0, -0.01),
            V3(0.03 * (1.1 if male else 1.0), 0.03, 0.028),
            k=0.02,
        )
        if male:
            _ = m.ell(
                "hackle",
                rig.bone("neck0"),
                nb + V3(0.0, -0.01, -0.03),
                V3(0.05, 0.04, 0.04),
                k=0.03,
            )

    # HEAD, head-local, scaled with the head.
    var h = rig.bone("head")
    _ = m.ell(
        "cranium",
        h,
        _hl(ho, hk, V3(0.0, 0.003, -0.006)),
        V3(0.0142, 0.0152, 0.02) * hk,
        k=0.01,
    )
    _ = m.ell(
        "crown",
        h,
        _hl(ho, hk, V3(0.0, 0.0095, 0.007)),
        V3(0.0105, 0.0078, 0.016) * hk,
        axis=normalize(V3(0.0, -0.25, 1.0)),
        k=0.008,
    )
    _ = m.ell(
        "nape",
        h,
        _hl(ho, hk, V3(0.0, -0.005, -0.017)),
        V3(0.0135, 0.0165, 0.016) * hk,
        k=0.01,
    )
    _ = m.ell(
        "chin",
        h,
        _hl(ho, hk, V3(0.0, -0.0135, 0.008)),
        V3(0.0085, 0.0085, 0.017) * hk,
        axis=normalize(V3(0.0, 0.2, 1.0)),
        k=0.008,
    )
    var eye = chicken_eye(t)
    for s in [1.0, -1.0]:
        _ = m.ell(
            "face",
            h,
            _hl(ho, hk, V3(0.0074 * s, -0.0058, 0.0075)),
            V3(0.006, 0.0092, 0.013) * hk,
            k=0.007,
        )
        _ = m.ell(
            "brow",
            h,
            _hl(ho, hk, V3(0.0095 * s, 0.0082, 0.003)),
            V3(0.0058, 0.0045, 0.011) * hk,
            k=0.005,
        )
        _ = sculpt_eye_socket(m, eye, HEAD_O, s, h)
    # The upper mandible: stout, triangular in profile; the lores taper the
    # face into it.
    for s in [1.0, -1.0]:
        _ = m.ell(
            "lores",
            h,
            _hl(ho, hk, V3(0.0042 * s, -0.0025, 0.017)),
            V3(0.0048, 0.0078, 0.009) * hk,
            k=0.006,
        )
    var hb = hk * bk
    _ = m.ell(
        "bill",
        h,
        _hb(ho, hk, bk, V3(0.0, -0.0025, 0.027)),
        V3(0.0048, 0.0068, 0.0115) * hb,
        axis=normalize(V3(0.0, -0.16, 1.0)),
        k=0.005,
    )
    _ = m.cone(
        "bill",
        h,
        _hb(ho, hk, bk, V3(0.0, -0.0004, 0.031)),
        _hb(ho, hk, bk, V3(0.0, -0.0072, 0.0452)),
        0.0042 * hb,
        0.0007 * hb,
        k=0.004,
    )
    _ = m.cone(
        "bill",
        h,
        _hb(ho, hk, bk, V3(0.0, -0.006, 0.03)),
        _hb(ho, hk, bk, V3(0.0, -0.0075, 0.043)),
        0.0035 * hb,
        0.0008 * hb,
        k=0.003,
    )
    for s in [1.0, -1.0]:
        _ = m.ell(
            "nostril",
            h,
            _hb(ho, hk, bk, V3(0.0038 * s, 0.0006, 0.0262)),
            V3(0.001, 0.0008, 0.0022) * hb,
            k=0.0006,
            carve=True,
        )
    # The lower mandible: its own surface, so the bill can open.
    var jw = rig.bone("jaw")
    _ = m.ell(
        "mandible",
        jw,
        _hb(ho, hk, bk, V3(0.0, -0.0082, 0.026)),
        V3(0.0052, 0.0028, 0.013) * hb,
        axis=normalize(V3(0.0, 0.05, 1.0)),
        k=0.003,
        part=JAW,
    )
    _ = m.cone(
        "mandible",
        jw,
        _hb(ho, hk, bk, V3(0.0, -0.0082, 0.033)),
        _hb(ho, hk, bk, V3(0.0, -0.0078, 0.0418)),
        0.0034 * hb,
        0.0007 * hb,
        k=0.003,
        part=JAW,
    )

    if not juv:
        # The single comb: a thin serrated blade along the crown, from the
        # bill's base back over the nape.
        var cb = t.get("comb")
        var ch = t.get("combH")
        var z0 = 0.024
        var z1 = -0.016 - 0.012 * (cb - 1.0)
        _ = m.ell(
            "comb",
            h,
            _comb(t, ho, V3(0.0, 0.0165, z0 + (z1 - z0) * 0.45)),
            V3(0.0021 * hk, 0.0075 * sqrt(ch) * hk, 0.024 * cb * hk),
            axis=normalize(V3(0.0, 0.08, 1.0)),
            k=0.004,
            part=WATTLE,
            thin=True,
        )
        # The leader: the blade continues back over the nape.
        _ = m.ell(
            "comb",
            h,
            _comb(t, ho, V3(0.0, 0.018 + 0.004 * ch, z0 + (z1 - z0) * 0.98)),
            V3(0.0019 * hk, 0.0075 * ch * hk, 0.009 * cb * hk),
            axis=normalize(V3(0.0, 0.3, -1.0)),
            k=0.004,
            part=WATTLE,
            thin=True,
        )
        for i in range(5):
            var u = (Float64(i) + 0.5) / 5.0
            var ph = (0.012 + 0.009 * sin(pi * (0.15 + 0.8 * u))) * ch
            var z = z0 + (z1 - z0) * (0.08 + 0.78 * u)
            var tilt = -0.3 + 0.6 * u
            _ = m.ell(
                "comb",
                h,
                _comb(t, ho, V3(0.0, 0.021 + ph * 0.52, z)),
                V3(0.0019 * hk, ph * 0.6 * hk, 0.0036 * cb * hk),
                axis=normalize(V3(0.0, tilt, 1.0)),
                up=normalize(V3(0.0, 1.0, -tilt)),
                k=0.0016,
                part=WATTLE,
                thin=True,
            )
        # The wattles: two rounded lobes under the bill.
        var wl = t.get("wattle")
        for s in [1.0, -1.0]:
            _ = m.ell(
                "wattle",
                h,
                _hl(ho, hk, V3(0.0024 * s, -0.0145 - 0.0068 * wl, 0.0225)),
                V3(0.0022 * hk, 0.0082 * wl * hk, 0.0096 * sqrt(wl) * hk),
                axis=normalize(V3(0.0, 0.15, 1.0)),
                k=0.005,
                part=WATTLE,
                thin=True,
            )
        # The earlobes: flat ovals below and behind the eye.
        var el = t.get("earlobe")
        for s in [1.0, -1.0]:
            _ = m.ell(
                "earlobe",
                h,
                _hl(
                    ho, hk, V3(0.0118 * s, -0.0105 - 0.002 * (el - 1.0), -0.009)
                ),
                V3(0.0024 * hk, 0.0052 * el * hk, 0.0042 * el * hk),
                axis=normalize(V3(0.0, 0.3, 1.0)),
                k=0.0025,
            )

    # LEGS: feathered drumsticks, scaled shanks and toes.
    var toe_r = t.get("toeR")
    var spur = t.get("spur", 0.0)
    for side in [String("L"), String("R")]:
        var s = 1.0 if side == "L" else -1.0
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
            V3(0.026 * fl, 0.046, 0.03 * fl),
            k=0.03,
        )
        _ = m.cone(
            "trousers",
            tib,
            lerp(kn, an, 0.3),
            lerp(kn, an, 0.84),
            0.02 * fl,
            0.0095,
            k=0.014,
        )
        _ = m.cone(
            "shank", tib, lerp(kn, an, 0.78), an, 0.0068, 0.0064, k=0.004
        )
        _ = m.sphere("hock", tar, an + V3(0.0, 0.0, -0.0012), 0.0074, k=0.004)
        _ = m.cone("tarsus", tar, an, mt, 0.0062, 0.0056, k=0.003)
        _ = m.sphere("pad", tar, mt + V3(0.0, -0.0004, 0.001), 0.0052, k=0.003)
        if spur > 0.0:
            # The spur: on the inner rear of the shank, curving up and
            # back.
            var base = lerp(mt, an, 0.3)
            var dir = normalize(V3(-0.45 * s, 0.25, -1.0))
            var tip = base + dir * (0.02 * spur) + V3(0.0, 0.004 * spur, 0.0)
            _ = m.cone(
                "spur",
                tar,
                base + dir * 0.003,
                tip,
                0.0036 * min(1.2, spur + 0.3),
                0.0009,
                k=0.0025,
            )
        for toe in range(1, 5):
            var ts = String(toe)
            var b = rig.j("t" + ts + "m" + side)
            var c = rig.j("t" + ts + "t" + side)
            var tr0 = (0.0038 if toe == 1 else 0.0044) * toe_r
            var ta = rig.bone("toe" + ts + "a" + side)
            var tb = rig.bone("toe" + ts + "b" + side)
            _ = m.cone("toe", ta, mt, b, tr0, 0.0036 * toe_r, k=0.003)
            _ = m.cone(
                "toe",
                tb,
                b,
                lerp(b, c, 0.7),
                0.0036 * toe_r,
                0.0027 * toe_r,
                k=0.0025,
            )
            _ = m.cone(
                "claw",
                tb,
                lerp(b, c, 0.62),
                c + V3(0.0, -0.0012, 0.0),
                0.0021 * toe_r,
                0.0005,
                k=0.0012,
            )

    # WINGS: the arm's flesh hangs below the bones, thin above them, so the
    # coverts lie on its dorsal side.
    var av = 1.4 if juv else 0.8
    var at = 0.75
    var shield = _Shield(
        List[Float64](),
        V3(0.0, 0.0, 0.0),
        0.0,
        0.0,
        List[Float64](),
        V3(0.0, 0.0, 0.0),
        0.0,
        0.0,
        0.0,
    )
    if not juv:
        shield = _shield(t)
    for side in [String("L"), String("R")]:
        var s = 1.0 if side == "L" else -1.0
        var sh = rig.j("shoulder" + side)
        var el = rig.j("elbow" + side)
        var wr = rig.j("wrist" + side)
        var tp = rig.j("handTip" + side)
        var n = wing_normal(rig, side)
        var ulna = rig.bone("ulna" + side)
        var hand = rig.bone("hand" + side)
        var th = 0.012 * wk * at
        wing_segment(
            m,
            s,
            n,
            sh,
            el,
            rig.bone("humerus" + side),
            th,
            0.02 * wk,
            0.005 * wk,
            "arm",
            0.006 if juv else 0.014,
            drop=th * av,
        )
        th = 0.009 * wk * at
        wing_segment(
            m,
            s,
            n,
            el,
            wr,
            ulna,
            th,
            0.018 * wk,
            0.006 * wk,
            "arm",
            0.01,
            drop=th * av,
        )
        th = 0.0065 * wk
        wing_segment(
            m,
            s,
            n,
            wr,
            tp,
            hand,
            th,
            0.016 * wk,
            0.005 * wk,
            "hand",
            0.007,
            drop=th * av,
        )
        # The bend of the wing: one rounded, feathered knob from the
        # patagium to the wrist.
        var pa = lerp(sh, el, 0.3)
        _ = ell_y(
            m,
            "patagium",
            ulna,
            lerp(pa, wr, 0.55) + n * (0.0005 * wk),
            wr - pa,
            V3(0.0085 * wk, length(wr - pa) * 0.62 + 0.004 * wk, 0.0085 * wk),
            lateral=n,
            k=0.009,
        )
        _ = m.sphere("wrist", hand, wr, 0.0085 * wk, k=0.007)
        if not juv:
            # The covert shield, and the lid over its upper rear corner.
            _plate(
                m,
                rig,
                side,
                shield.core,
                shield.plane,
                shield.t * 0.001,
                shield.round * 0.001,
                0.003,
                True,
            )
            _plate(
                m,
                rig,
                side,
                shield.lid,
                shield.lid_plane,
                shield.lid_t * 0.001,
                shield.lid_round * 0.001,
                shield.lid_k,
                False,
            )

    # The flight feathers and the tail.
    var feathers = _feathers(t)
    feather_fins(
        m,
        rig,
        feathers,
        _frames(t, rig, feathers),
        # A chick's pin feathers wear their down: thicker cards.
        0.0045 if juv else 0.0018,
        0.0012,
        coverts=V3(0.0, 0.0, 0.0),
    )


def _hl(ho: V3, hk: Float64, v: V3) -> V3:
    return ho + v * hk


def _hb(ho: V3, hk: Float64, bk: Float64, v: V3) -> V3:
    # The bill, scaled about its base.
    return _hl(ho, hk, V3(v.x * bk, v.y * bk, 0.017 + (v.z - 0.017) * bk))


def _comb(t: Traits, ho: V3, v: V3) -> V3:
    # A large hen's comb flops over to one side: the blade bends about
    # the crown line.
    var flop = t.get("combFlop", 0.0)
    var x = v.x
    var y = v.y
    if flop > 0.0:
        var a = flop * max(0.0, y - 0.012) / 0.03
        x += sin(a) * (y - 0.012) * 0.9
        y = 0.012 + (y - 0.012) * cos(a)
    return _hl(ho, t.get("headK"), V3(x, y, v.z))


# ---------------------------------------------------------------- coat


def chicken_palette(t: Traits) raises -> Palette:
    """Return one chicken's palette: procedural-animals' `palette`, by
    breed and sex, with a chick's down.

    Args:
        t: The individual.

    Returns:
        The palette, in linear light.

    Raises:
        Error: If a swatch is missing.
    """
    var male = t.male()
    var b = t.variant
    var out = Palette()
    var names: List[String] = [
        "body",
        "back",
        "hackle",
        "hackleTip",
        "saddle",
        "bow",
        "breast",
        "fluff",
        "tail",
        "flight",
        "flightEdge",
        "leg",
        "bill",
    ]
    var hexes: List[Int]
    var cond4 = b == RED and male
    if cond4:
        hexes = [
            0x7A2C12,
            0x9C3F16,
            0xC8741E,
            0xE0A040,
            0xC05A18,
            0x6E2410,
            0x1A1410,
            0x2A2420,
            0x10171A,
            0x2A2018,
            0x8A4A22,
            0xD8B04A,
            0xCFAE6A,
        ]
    elif b == RED:
        hexes = [
            0x9C5A2C,
            0x98562A,
            0xB67434,
            0xC4843E,
            0x9C5A2C,
            0x8A4A24,
            0xA4602E,
            0xD6BF98,
            0x4A2A16,
            0x5E3820,
            0xA06C3E,
            0xDCB44A,
            0xD8B876,
        ]
    elif b == LEGHORN:
        hexes = [
            0xEFEDE6,
            0xEFEDE6,
            0xF2F0EA,
            0xF4F2EC,
            0xF1EFE8,
            0xECE9E1,
            0xF0EEE7,
            0xF3F2EE,
            0xEEECE5,
            0xEBE8DF,
            0xF1EFE8,
            0xE6C34A,
            0xE6C86A,
        ]
    elif b == AUSTRALORP:
        hexes = [
            0x141619,
            0x131518,
            0x15171A,
            0x17191C,
            0x141619,
            0x131518,
            0x16181B,
            0x34363A,
            0x101214,
            0x111214,
            0x161719,
            0x2C2E32,
            0x2E2E30,
        ]
    elif b == BARRED:
        hexes = [
            0xDCDCD4,
            0xD8D8D0,
            0xDEDFD8,
            0xE2E2DC,
            0xDCDCD4,
            0xD8D8D0,
            0xDCDCD4,
            0xCACAC2,
            0xCFCFC8,
            0xB8B8B0,
            0xD0D0C8,
            0xE2BF4C,
            0xE0C262,
        ]
    elif b == BUFF:
        hexes = [
            0xCF9A52,
            0xCB944C,
            0xD6A45C,
            0xDCAE66,
            0xD0984E,
            0xC68E48,
            0xD09A54,
            0xE0C08A,
            0xB67E3C,
            0xBD8743,
            0xD2A05A,
            0xE6CFBE,
            0xE0C8A2,
        ]
    else:
        hexes = [
            0x6A2C16,
            0x6A2C16,
            0x7A3518,
            0x8A4020,
            0x6E2E16,
            0x622814,
            0x6E2E16,
            0xB8A088,
            0x1C1614,
            0x3C2014,
            0xE8E2D6,
            0xE3CBBD,
            0xD8C6A0,
        ]
    for i in range(len(names)):
        out.set(names[i], srgb(hexes[i]))
    out.set("comb", srgb(0xC41F2A))
    out.set("wattle", srgb(0xB81D24))
    out.set("face", srgb(0xCC3A42))
    out.set("lobe", srgb(0xECE6DA) if b == LEGHORN else srgb(0xBD2E38))
    # The breed's feather markings: lace, bars, shaft streaks or spangles.
    out.set("mark", srgb(0xC89458))
    out.set("shaft", srgb(0x3A1A0A) if male else srgb(0x4E2612))
    out.set("bar", srgb(0x1C1C1E))
    out.set("spangle", srgb(0xF2EEE6))
    if t.juvenile() > 0.0:
        # Down only: yellow, black or chipmunk-striped, with pale legs and
        # bill and no comb.
        var down: List[Int]
        if b == RED:
            down = [0xD7B77A, 0x8A6238, 0xEEDCA2, 0x6B4726]
        elif b == LEGHORN:
            down = [0xF2E08A, 0xF0DC84, 0xF6EA9E, 0]
        elif b == BUFF:
            down = [0xF0D488, 0xECCE80, 0xF6E4A2, 0]
        elif b == AUSTRALORP:
            down = [0x1A1A1C, 0x161618, 0xD8D0B0, 0]
        elif b == BARRED:
            down = [0x1C1C1E, 0x18181A, 0x5A5A58, 0]
        else:
            down = [0x7A5836, 0x5E3F24, 0xDCC49A, 0x4A2E1A]
        var body = srgb(down[0])
        var back = srgb(down[1])
        out.set("body", body)
        out.set("back", back)
        out.set("fluff", srgb(down[2]))
        out.set("stripe", srgb(down[3]) if down[3] != 0 else back)
        out.set("hackle", body)
        out.set("hackleTip", body)
        out.set("saddle", back)
        out.set("bow", back)
        out.set("breast", srgb(down[2]))
        out.set("tail", back)
        out.set("flight", mix3(back, body, 0.3))
        out.set("flightEdge", body)
        out.set("leg", srgb(0xE9C98A))
        out.set("bill", srgb(0xD9BC8C))
        out.set("spot", srgb(0xF0ECD8))
    var tone = t.get("tone")
    var toned: List[String] = [
        "body",
        "back",
        "hackle",
        "hackleTip",
        "saddle",
        "bow",
        "breast",
        "tail",
        "flight",
    ]
    for name in toned:
        out.set(name, out.get(name) * tone)
    return out^


def _flight_color(
    pal: Palette,
    t: Traits,
    kind: String,
    i: Float64,
    tt: Float64,
    across: Float64,
    top: Bool,
) -> V3:
    # procedural-animals' `chickenFeatherColour`.
    var b = t.variant
    var male = t.male()
    var c = pal.get("flight")
    if kind == "rectrix":
        c = pal.get("tail")
        var cond5 = male and b == RED
        if cond5:
            # A red rooster's black-green tail and sickles.
            c = mix3(c, srgb(0x0E2A22), 0.35)
    var edge = mix3(
        pal.get("body"), pal.get("flightEdge"), 0.2
    ) if b == SPECKLED else pal.get("flightEdge")
    var cond6 = kind == "primary" and across < -0.004
    if cond6:
        c = mix3(c, edge, 0.35)
    var cond7 = kind == "secondary" and top
    if cond7:
        var ac = clamp(abs(across) / 0.02, 0.0, 1.0)
        if i >= 7.0:
            # The tertials on top read as the wing's contour feathers.
            c = mix3(
                mix3(pal.get("bow"), pal.get("flight"), 0.45),
                pal.get("mark") if b == RED and not male else edge,
                0.3 * ac,
            )
        else:
            c = mix3(c, edge, 0.6) if across < 0.0 else mix3(
                c, pal.get("bow"), 0.2
            )
    if kind.endswith("Covert"):
        c = mix3(pal.get("bow"), pal.get("body"), 0.3)
    if b == BARRED:
        # Light vanes with dark bars across them.
        var period = (
            0.0075 if kind == "primary" or kind == "rectrix" else 0.0062
        )
        var ln = 0.15
        var bar = smoothstep(0.15, -0.15, sin(tt * ln / period * 2.0 * pi))
        c = mix3(
            srgb(0xD8D8D0),
            mix3(srgb(0xD8D8D0), srgb(0x1E1E20), 0.66 if male else 0.78),
            bar,
        )
    var cond8 = b == SPECKLED and tt > 0.85
    if cond8:
        c = mix3(c, pal.get("spangle"), smoothstep(0.85, 1.0, tt))
    if not top:
        c = mix3(c, srgb(0x9A948C), 0.15)
    var k = 1.0 + (0.1 if kind == "secondary" else 0.06) * sin(
        i * 12.9898 + tt * 2.1
    )
    return c * k


def chicken_paint(
    pal: Palette, t: Traits, tag: String, bone: String, s: CoatSample
) raises -> Paint:
    """Paint one vertex of a chicken.

    Contour feathers by tract (hackle, back, wing bow, breast, fluff,
    saddle) with the breed's per-feather markings: lacing, bars, shaft
    streaks or spangles. Bare red skin on the face, comb and wattles, red
    or white earlobes, a horn-yellow bill and claws, and scaled shanks and
    toes. A chick is a ball of down, chipmunk-striped on brown breeds.

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
    var juv = t.juvenile() > 0.0
    var male = t.male() and not juv
    var b = t.variant
    var cv = fbm3(p * 30.0 + V3(t.get("coatSeed", 0.0), 0.0, 0.0), 3) - 0.5
    var cond9 = tag == "bill" or tag == "nostril" or tag == "mandible"
    if cond9:
        return Paint(pal.get("bill") * (1.0 + 0.1 * cv), KERATIN)
    if tag == "comb":
        return Paint(pal.get("comb") * (1.0 + 0.12 * cv), SKIN)
    if tag == "wattle":
        return Paint(pal.get("wattle") * (1.0 + 0.12 * cv), SKIN)
    if tag == "earlobe":
        return Paint(pal.get("lobe"), SKIN)
    var cond10 = tag == "eyelid" or tag == "eyesocket"
    if cond10:
        # Bare skin at the lid's margin; the rest of the lid is the face's
        # skin, or a chick's down.
        var e = chicken_eye(t)
        var ef = eye_frame_of(e, HEAD_O, 1.0 if p.x >= 0.0 else -1.0)
        var cz = dot(normalize(p - ef.c), ef.z)
        var ap = asin(min(1.0, e.big_r / (e.r + e.lid)))
        var margin = smoothstep(cos(ap + 0.22), cos(ap + 0.1), cz)
        var ring = srgb(0x3A3230) if juv else mix3(
            pal.get("face"), srgb(0x40181A), 0.5
        )
        var lid = mix3(
            pal.get("body"), pal.get("fluff"), 0.3
        ) if juv else pal.get("face")
        var cond11 = juv and margin < 0.5
        if cond11:
            return Paint(lid * (0.88 + 0.24 * fbm3(p * 1500.0, 2)), FUR)
        return Paint(mix3(lid, ring, margin), SKIN)
    if tag == "claw":
        return Paint(mix3(pal.get("leg"), srgb(0x6A6056), 0.5), KERATIN)
    if tag == "spur":
        return Paint(mix3(pal.get("leg"), srgb(0x5A5048), 0.45), KERATIN)
    var leg = (
        tag == "tarsus"
        or tag == "toe"
        or tag == "pad"
        or tag == "hock"
        or tag == "shank"
    )
    if leg:
        # Large scutes down the front of the shank, small scales behind.
        var front = smoothstep(-0.2, 0.6, n.z) if tag == "tarsus" else 0.5
        var size = mix(0.0022, 0.0042, front)
        var sc = fbm3(V3(p.x / size, p.y / size * 1.6, p.z / size), 1)
        return Paint(pal.get("leg") * (0.82 + 0.3 * sc), SCALES)
    if is_card(tag):
        var cp = card_point(tag, s.local, bone.endswith("R"))
        var fi = _index(bone)
        var c = _flight_color(pal, t, cp.kind, fi, cp.t, cp.across, cp.top)
        var tertial = cp.kind == "secondary" and fi >= 7.0 and cp.top
        if tertial:
            # The tertials read as the wing's contour feathers.
            c = c * shingle(plume(p, 0.012, V3(0.0, -0.4, -1.0)))
        if juv:
            # A chick's wing is down: the top the down of its bed, the
            # underside paler.
            var top_c = mix3(pal.get("back"), pal.get("body"), 0.3)
            c = top_c if cp.top else mix3(top_c, pal.get("fluff"), 0.35)
            return Paint(c * (1.0 + 0.1 * cv), FUR)
        return Paint(c * (1.0 + 0.22 * cv), FEATHER)
    var ho = _ho(t)
    var hk = t.get("headK")
    var hh = (p - ho) * (1.0 / hk)
    var c: V3
    var tract: Int
    var flow = V3(0.0, -0.3, -1.0)
    var size = 0.02
    var cond12 = (
        tag == "arm"
        or tag == "hand"
        or tag == "patagium"
        or tag == "wrist"
        or tag == "coverts"
    )
    if bone == "head":
        var rn = smoothstep(
            0.016, 0.034, sqrt(hh.x * hh.x * 0.36 + hh.y * hh.y + hh.z * hh.z)
        )
        c = mix3(pal.get("hackle"), pal.get("hackleTip"), 0.6)
        size = mix(0.006, 0.014 if male else 0.016, rn)
        flow = V3(hh.x * 10.0, -0.5, -1.0)
        tract = 1
        # Bare facial skin around the eye and the lores.
        var cvh = fbm3(p * 700.0, 2) - 0.5
        var bound = (
            0.0048
            - 60.0 * pow(max(0.0, hh.z - 0.006), 2.0)
            - 40.0 * pow(max(0.0, -0.001 - hh.z), 2.0)
            + 0.0008 * cvh
        )
        var face = (
            not juv
            and hh.z > -0.0095 + 0.0015 * cvh
            and hh.z < 0.03
            and hh.y < bound
            and hh.y > -0.022
            and abs(hh.x) > 0.0024
        )
        if face:
            return Paint(pal.get("face") * (1.0 + 0.12 * cv), SKIN)
        if juv:
            c = mix3(pal.get("body"), pal.get("fluff"), 0.3)
            return Paint(c * (0.85 + 0.3 * fbm3(p * 1500.0, 2)), FUR)
    elif bone.startswith("tibia"):
        c = mix3(pal.get("fluff"), pal.get("body"), 0.4 if juv else 0.55)
        flow = V3(0.0, -1.0, -0.3)
        size = 0.016
        tract = 4
    elif cond12:
        var top = s.local.x > 0.0 or tag == "wrist" or tag == "coverts"
        c = pal.get("bow") if top else mix3(
            pal.get("fluff"), pal.get("body"), 0.5
        )
        var cond13 = not male and top
        if cond13:
            c = mix3(pal.get("bow"), pal.get("back"), 0.4)
        flow = V3(0.0, -0.6, -1.0)
        tract = 2
        if juv:
            var top_c = mix3(pal.get("back"), pal.get("body"), 0.3)
            c = top_c if top else mix3(top_c, pal.get("fluff"), 0.35)
    else:
        var up = n.y
        var dorsal = smoothstep(-0.25, 0.45, up)
        var nb = _neck_base(t)
        var occ = _occiput(t)
        var ny = (p.y - nb.y) / max(1e-3, occ.y - nb.y)
        var syn_z = _syn_z(t)
        var hackle = bone.startswith("neck") or (
            bone == "chest" and ny > -0.25 and p.z > syn_z
        )
        if hackle:
            tract = 1
            c = mix3(
                pal.get("hackle"),
                pal.get("hackleTip"),
                smoothstep(0.2, 1.0, ny) * 0.6,
            )
            size = 0.014 if male else 0.016
            flow = V3(0.0, -1.0, -0.5)
            var cond14 = up < -0.1 and p.z > nb.z
            if cond14:
                c = mix3(c, pal.get("breast"), smoothstep(-0.1, -0.5, up))
                tract = 3
        else:
            c = mix3(pal.get("breast"), pal.get("back"), dorsal)
            size = 0.02 if p.z > 0.02 else 0.024
            tract = 0
            var under = smoothstep(0.2, -0.5, up) * smoothstep(0.175, 0.13, p.y)
            c = mix3(
                c,
                pal.get("fluff"),
                under * (0.4 if male and b == RED else 0.85),
            )
            if under > 0.5:
                tract = 4
            var sw = smoothstep(syn_z + 0.015, syn_z - 0.045, p.z) * smoothstep(
                -0.35, 0.25, up
            )
            if bone == "tail":
                sw = 0.0
                c = mix3(pal.get("tail"), pal.get("saddle"), 0.35)
                tract = 5
            c = mix3(c, pal.get("saddle"), sw)
            var below_cape = bone == "chest" and p.z > syn_z
            if below_cape:
                # The hackle cape's colors fade into the body's below it.
                c = mix3(
                    c,
                    pal.get("hackle"),
                    smoothstep(-0.55, -0.25, ny)
                    * (1.0 - smoothstep(-0.1, -0.5, up)),
                )
            var cond15 = male and sw > 0.5
            if cond15:
                tract = 6
                size = 0.012
            if up < 0.3:
                flow = V3(0.0, -0.7 * (1.0 - up) - 0.2, -1.0)
            if tract == 6:
                flow = V3(0.0, -1.5, -0.6)
        if juv:
            # A chick's down: a soft ball, chipmunk stripes down the back
            # of the brown breeds, a pale belly.
            var hip_y = 0.205 * t.get("hipK")
            var rd = normalize(p - V3(0.0, hip_y + 0.01, -0.01))
            var wr = 1.0 - smoothstep(0.6, 0.95, dot(n, rd))
            var up_j = max(up, mix(up, rd.y, wr))
            c = mix3(
                pal.get("fluff"), pal.get("body"), smoothstep(-0.6, 0.2, up_j)
            )
            c = mix3(
                c,
                pal.get("back"),
                0.7 * smoothstep(0.3, 0.5, smoothstep(-0.25, 0.45, up_j)),
            )
            var striped = b == RED or b == SPECKLED
            var cond16 = striped and dorsal > 0.55
            if cond16:
                var sx = abs(p.x)
                var band = smoothstep(
                    0.012, 0.006, abs(sx - 0.022)
                ) + smoothstep(0.008, 0.003, sx)
                c = mix3(c, pal.get("stripe"), clamp(band, 0.0, 1.0) * 0.85)
            return Paint(c * (0.85 + 0.3 * fbm3(p * 1500.0, 2)), FUR)
    if juv:
        return Paint(c * (1.0 + 0.1 * cv), FUR)
    # The breed's per-feather markings, on contour feathers by tract.
    var pl = plume(p, size * 0.7, flow)
    c = c * shingle(pl)
    var shaft = (b == RED and not male and tract == 1) or (
        male and b == RED and (tract == 1 or tract == 6)
    )
    var cond17 = b == RED and not male
    if shaft:
        # A dark streak down each hackle feather's shaft.
        var st = smoothstep(0.3, 0.1, abs(pl.across)) * smoothstep(
            -0.9, -0.2, pl.along
        )
        c = mix3(c, pal.get("shaft"), st * (0.35 if male else 0.6))
    elif cond17:
        # A pale fringe on the back, wing and body feathers.
        var lace = smoothstep(0.12, 0.02, pl.edge) * smoothstep(
            -0.2, 0.4, pl.along
        )
        c = mix3(c, pal.get("mark"), lace * (0.12 if tract == 4 else 0.25))
    elif b == BARRED:
        # Bars across every feather, black on white.
        var bar = smoothstep(0.2, -0.2, sin(pl.along * 7.0 + pl.id * 6.0))
        c = mix3(
            c,
            pal.get("bar"),
            bar * (0.78 if male else 0.92) * (0.5 if tract == 4 else 1.0),
        )
    elif b == SPECKLED:
        # A white spangle at each feather's tip, behind a dark crescent.
        var tip = V3(pl.along - 0.55, pl.across, 0.0)
        var dd = length(tip)
        var spot = smoothstep(0.32, 0.22, dd)
        var ring = smoothstep(0.5, 0.36, dd) * (1.0 - spot)
        c = mix3(c, srgb(0x1A1210), ring * 0.6)
        c = mix3(
            c, pal.get("spangle"), spot * 0.8 * (0.5 if tract == 4 else 1.0)
        )
    var kv = 0.22
    return Paint(
        V3(
            c.x * (1.0 + kv * cv),
            c.y * (1.0 + kv * cv),
            c.z * (1.0 + kv * 0.8 * cv),
        ),
        FEATHER,
    )


def _index(bone: String) raises -> Float64:
    # A feather bone's index from zero: `sec8L` is 7.
    return Float64(Int(bone[byte = 3 : bone.byte_length() - 1]) - 1)


def _syn_z(t: Traits) -> Float64:
    if t.juvenile() > 0.0:
        return -0.03
    return _torso(t, V3(0.0, 0.218, -0.04)).z
