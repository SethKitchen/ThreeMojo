# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The domestic goat, Capra hircus: procedural-animals' `species/goat/`.

A cloven-hoofed browser. The reference adult is a Saanen-type dairy doe,
0.78 m at the withers. It has two claws a foot on a hoof bone, scimitar
horns of keratin on the skull, a beard and wattles, and horizontal bar
pupils in pale amber irises. The breeds are Saanen, Alpine, pied, Nubian
and Boer; each has its own coats, ears, nose and build.
"""

from extensions.animals.coat import (
    FUR,
    KERATIN,
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
    APPENDAGE,
    HORN,
    JAW,
    WATTLE,
)
from extensions.sdf.sculpt import ell_y
from extensions.animals.kit import (
    EyeSpec,
    eye_frame_of,
    sculpt_eye_socket,
    aperture_tilt_along,
    draw_u32,
    is_front_limb,
    imul32,
    is_limb,
    pick_weighted,
    stream_of,
    lid_distance,
)
from extensions.animals.noise import fbm3, vnoise3
from extensions.animals.options import (
    ADULT,
    FEMALE,
    JUVENILE,
    MALE,
    AnimalOptions,
    AnimalRandom,
)
from extensions.animals.rig import Rig, tail_chain
from extensions.sdf.field import SdfModel
from extensions.animals.parts import BODY
from extensions.animals.species.hoofed import (
    HeadFrame,
    head_frame,
    hoofed_bones,
    dewclaw_balls,
)
from extensions.animals.traits import Traits
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
from extensions.animals.warp import (
    girth_warp,
    legs_warp,
    length_warp,
    scale_about_warp,
    shift_warp,
)
from std.math import asin, atan2, cos, exp, floor, pi, pow, sin, sqrt

comptime TAIL_SEGS = 5
# The head's origin: on the head's axis 0.07 m in front of the poll,
# level with the eyes. The head is carried 42 degrees nose-down.
comptime HEAD_O = V3(0.0, 0.9281608575548799, 0.6420201377834176)
comptime HEAD_PITCH = 42.0
# The finest cell, at the `HERO` tier: the head's cell in the original.
comptime CELL = 0.0028
# A kid's face in front of the eyes is this much shorter.
comptime KID_FACE = 0.78

# The breeds, in procedural-animals' order.
comptime SAANEN = 0
comptime ALPINE = 1
comptime PIED = 2
comptime NUBIAN = 3
comptime BOER = 4

# The coats, across all breeds.
comptime C_SAANEN = 0
comptime C_CHAMOISEE = 1
comptime C_COUBLANC = 2
comptime C_TOGGENBURG = 3
comptime C_BRITISHALPINE = 4
comptime C_PIED = 5
comptime C_PIEDBROWN = 6
comptime C_NUBIANRED = 7
comptime C_NUBIANTAN = 8
comptime C_NUBIANBLACK = 9
comptime C_BOER = 10

# Which masks carry a coat's second color.
comptime M_STRIPES = 1
comptime M_FACECENTER = 2
comptime M_DORSAL = 4
comptime M_LEGS = 8
comptime M_BELLY = 16
comptime M_EARS = 32
comptime M_MUZZLE = 64
comptime M_REAR = 128
comptime M_TAILPATCH = 256
comptime M_PATCHES = 512
comptime M_SPOTS = 1024
comptime M_BOERHEAD = 2048

# Bind joints the coat reads (they do not depend on the individual).
comptime NECK_BASE_J = V3(0.0, 0.64, 0.35)
comptime NECK_MID_J = V3(0.0, 0.8, 0.472)


def goat_variant_names() -> List[String]:
    """Return the goat's breeds.

    Returns:
        Saanen, Alpine, pied, Nubian and Boer.
    """
    return [String("saanen"), "alpine", "pied", "nubian", "boer"]


def _frame() -> HeadFrame:
    return head_frame(HEAD_O, HEAD_PITCH)


def _hl(v: V3) -> V3:
    return _frame().at_chained(v)


def _face_z(z: Float64, kid: Bool) -> Float64:
    var short = kid and z > 0.02
    return 0.02 + (z - 0.02) * KID_FACE if short else z


def _un_face_z(z: Float64, kid: Bool) -> Float64:
    var short = kid and z > 0.02
    return 0.02 + (z - 0.02) / KID_FACE if short else z


def _hlk(v: V3, kid: Bool) -> V3:
    return _hl(V3(v.x, v.y, _face_z(v.z, kid)))


def _breed_salt(b: Int) -> Int:
    var salts: List[Int] = [158, 746, 208, 398, 165]
    return salts[b]


def _breed_coats(b: Int) -> List[Int]:
    if b == ALPINE:
        return [C_CHAMOISEE, C_COUBLANC, C_TOGGENBURG, C_BRITISHALPINE]
    if b == PIED:
        return [C_PIED, C_PIEDBROWN]
    if b == NUBIAN:
        return [C_NUBIANRED, C_NUBIANTAN, C_NUBIANBLACK]
    if b == BOER:
        return [C_BOER]
    return [C_SAANEN]


def _breed_coat_weights(b: Int) -> List[Float64]:
    if b == ALPINE:
        return [40.0, 25.0, 20.0, 15.0]
    if b == PIED:
        return [60.0, 40.0]
    if b == NUBIAN:
        return [40.0, 35.0, 25.0]
    return [1.0]


def _lop(b: Int) -> Bool:
    return b == NUBIAN or b == BOER


def _kid_neck(lop: Bool) -> V3:
    var occ = _hl(V3(0.0, -0.045, -0.1))
    return (occ - NECK_BASE_J) * (-0.12 if lop else -0.2)


def goat_traits(mut r: AnimalRandom, options: AnimalOptions) raises -> Traits:
    """Draw one goat: procedural-animals' `variation`.

    The stream is re-mixed with the seed and the breed's salt, as the
    original does, so a seed gives a different animal in every breed.
    Bucks are heavier and broader, with a mane, big horns and a long
    beard. Kids have long legs, a short body and neck, a big head and
    horn buds.

    Args:
        r: The individual's stream.
        options: The caller's sex, age and breed.

    Returns:
        The traits.

    Raises:
        Error: If the requested breed is not one of the five.
    """
    var requested = options.variant.value
    if requested >= 5:
        raise Error("The goat has no such breed")
    var salt = _breed_salt(requested) if requested >= 0 else 0
    var seed = (
        draw_u32(r)
        ^ imul32(options.seed, 0x9E3779B1)
        ^ 0x2545F491
        ^ imul32(salt, 0x85EBCA6B)
    )
    var R = stream_of(seed)
    var variant = requested
    if requested < 0:
        variant = pick_weighted(R, [30.0, 30.0, 20.0, 15.0, 5.0])
    var sex = options.sex
    if sex != MALE and sex != FEMALE:
        sex = MALE if R.next() < 0.45 else FEMALE
    var age = options.age
    if age != ADULT and age != JUVENILE:
        age = JUVENILE if R.next() < 0.15 else ADULT
    var t = Traits(sex, age, variant)
    var kid = age == JUVENILE
    var buck = sex == MALE and not kid
    var coats = _breed_coats(variant)
    var coat = coats[pick_weighted(R, _breed_coat_weights(variant))]
    var polled_p: List[Float64] = [0.4, 0.35, 0.3, 0.5, 0.05]
    var polled = R.next() < polled_p[variant]
    var hlen = 0.0
    var hbase = 0.0
    var hcurve = 0.0
    var hspread = 0.0
    var hup = 0.0
    if not polled:
        if kid:
            hlen = 0.02 + 0.01 * R.next()
            hbase = 0.008
            hcurve = 0.2
            hspread = 0.12
            hup = 0.3
        elif buck:
            hlen = 0.3 + 0.18 * R.next()
            hbase = 0.024 + 0.006 * R.next()
            hcurve = 1.6 + 0.5 * R.next()
            hspread = 0.18 + 0.16 * R.next()
            hup = 0.1 * R.next()
        else:
            hlen = 0.14 + 0.1 * R.next()
            hbase = 0.0125 + 0.0035 * R.next()
            hcurve = 0.9 + 0.45 * R.next()
            hspread = 0.08 + 0.1 * R.next()
            hup = 0.2 * R.next()
    t.set("hornLen", hlen)
    t.set("hornBase", hbase)
    t.set("hornCurve", hcurve)
    t.set("hornSpread", hspread)
    t.set("hornUpright", hup)
    var beard_p = 0.3 if _lop(variant) else 0.65
    var beard = 0.0
    if buck:
        beard = 0.12 + 0.1 * R.next()
    elif not kid:
        if R.next() < beard_p:
            beard = 0.05 + 0.07 * R.next()
    t.set("beard", beard)
    var size = (
        (1.12 if buck else 1.0)
        * (1.0 + 0.045 * R.g())
        * (1.04 if variant == NUBIAN else 1.0)
        * (0.58 if kid else 1.0)
    )
    t.set("size", size)
    t.set("coat", Float64(coat))
    t.set("wattles", 1.0 if R.next() < 0.3 else 0.0)
    t.set("earLift", R.next())
    t.set("lop", 1.0 if _lop(variant) else 0.0)
    var roman: List[Float64] = [0.0, 0.0, 0.15, 1.0, 0.7]
    t.set(
        "roman",
        roman[variant] * (0.75 + 0.25 * R.next()) * (0.35 if kid else 1.0),
    )
    var doe = sex == FEMALE and not kid
    t.set("udder", 0.2 + 0.8 * R.next() if doe else 0.0)
    t.set("heavy", 0.7 + 0.3 * R.next() if buck else 0.0)
    t.set("mane", 0.4 + 0.6 * R.next() if buck else 0.0)
    var shaggy = 0.0
    if variant == ALPINE:
        shaggy = 0.4 if R.next() < 0.25 else 0.0
    t.set("shaggy", shaggy)
    var horn_hex: List[Int] = [0xB4A07C, 0x8A7050, 0x9E8058, 0x7A6248, 0x5E4C3A]
    t.set("hornColor", Float64(horn_hex[variant]))
    t.set("coatShade", R.g())
    t.set("coatLightness", 0.05 * R.g())
    t.set("coatSeed", Float64(Int(R.next() * 1e6)))
    t.set("tierRes", options.quality.resolution())
    t.set("minThick", 0.005)
    var lop = _lop(variant)
    if kid:
        var occ = _hl(V3(0.0, -0.045, -0.1))
        var nb = NECK_BASE_J + (occ - NECK_BASE_J) * 0.15
        t.warps.add(shift_warp(nb, occ, _kid_neck(lop)))
    var hc = HEAD_O + _kid_neck(lop) if kid else HEAD_O
    var head_k = (
        (1.0 + 0.035 * R.g()) * (1.18 if kid else 1.0) * (1.06 if buck else 1.0)
    )
    t.warps.add(scale_about_warp(hc, head_k, 0.1, 0.2))
    var legs: List[Float64] = [1.0, 1.0, 0.98, 1.06, 0.9]
    var legs_k = (1.0 + 0.035 * R.g()) * legs[variant] * (1.18 if kid else 1.0)
    t.warps.add(legs_warp(legs_k, 0.46))
    var len_k = (1.0 + 0.035 * R.g()) * (0.84 if kid else 1.0)
    t.warps.add(length_warp(len_k, -0.32, 0.32))
    var girth: List[Float64] = [1.0, 0.98, 1.02, 0.97, 1.1]
    var girth_k = (
        (1.0 + 0.04 * R.g())
        * girth[variant]
        * (1.06 if buck else 1.0)
        * (0.92 if kid else 1.0)
    )
    t.warps.add(girth_warp(girth_k, 0.56, -0.4, 0.38))
    return t^


def goat_eye(t: Traits) -> EyeSpec:
    """Return the goat's left eye: a 29 mm globe high on the side of the
    head, its almond rolled along the face.

    Args:
        t: The individual. The eye is the same in every goat.

    Returns:
        The eye, head-local.
    """
    _ = t
    var f = _frame()
    var a = 24.0 * pi / 180.0
    var dir = normalize(V3(cos(a), 0.0, 0.0) + f.hz * sin(a))
    var e = EyeSpec(
        _hl(V3(0.057, -0.004, 0.0)) - HEAD_O,
        0.0145,
        0.003,
        atan2(dir.x, dir.z),
        asin(dir.y),
        0.0017,
        0.0132,
        0.0052,
        -0.0006,
        0.0,
        0.0081,
        0.0112,
    )
    e.tilt = aperture_tilt_along(e, HEAD_O, f.hz) - 0.38
    return e


def goat_rig(t: Traits) raises -> Rig:
    """Return the goat's skeleton in bind pose.

    The hoofed quadruped with an udder bone below the pelvis and a beard
    bone below the chin. The ears are erect and lateral in the Swiss
    breeds and long and pendulous in the Nubian and the Boer.

    Args:
        t: The individual.

    Returns:
        The rig.

    Raises:
        Error: If a bone names a missing joint.
    """
    var lop = t.get("lop", 0.0) > 0.5
    var kid = t.juvenile() > 0.0
    var lift = max(0.6, t.get("earLift", 0.5)) if kid else t.get("earLift", 0.5)
    var hq = 0.095 if kid else 0.07
    var rig = Rig()
    rig.set("nose", _hlk(V3(0.0, -0.024, 0.205), kid))
    rig.set("occiput", _hl(V3(0.0, -0.045, -0.1)))
    rig.set("neckMid", NECK_MID_J)
    rig.set("neckBase", NECK_BASE_J)
    rig.set("chestMid", V3(0.0, 0.668, 0.17))
    rig.set("thoraxRear", V3(0.0, 0.692, 0.015))
    rig.set("lumbarMid", V3(0.0, 0.702, -0.1))
    rig.set("lumbosacral", V3(0.0, 0.707, -0.215))
    rig.set("tailBase", V3(0.0, 0.71, -0.4))
    rig.set("scapTopL", V3(0.055, 0.745, 0.265))
    rig.set("shoulderL", V3(0.088, 0.53, 0.372))
    rig.set("elbowL", V3(0.083, 0.405, 0.245))
    rig.set("wristL", V3(0.07, 0.21, 0.252))
    rig.set("mcpL", V3(0.064, 0.07, 0.256))
    rig.set("fcoffinL", V3(0.064, 0.03, 0.279))
    rig.set("ftoeL", V3(0.064, 0.002, 0.323))
    rig.set("hipL", V3(0.078, 0.63, -0.36 + hq))
    rig.set("kneeL", V3(0.093, 0.45, -0.24 + hq))
    rig.set("hockL", V3(0.066, 0.25, -0.44 + hq))
    rig.set("mtpL", V3(0.06, 0.075, -0.442 + hq))
    rig.set("hcoffinL", V3(0.06, 0.031, -0.419 + hq))
    rig.set("htoeL", V3(0.06, 0.002, -0.374 + hq))
    rig.set("jawHinge", _hl(V3(0.0, -0.045, -0.02)))
    rig.set("jawTip", _hlk(V3(0.0, -0.078, 0.185), kid))
    var eb = _hl(V3(0.048, 0.02, -0.07)) if lop else _hl(
        V3(0.048, 0.026, -0.06)
    )
    rig.set("earBaseL", eb)
    var tip: V3
    if lop:
        var le = (0.82 if kid else 1.0) * (0.9 if t.variant == BOER else 1.0)
        tip = eb + V3(0.1 * le, -0.225 * le, -0.05 * le)
    else:
        tip = _hl(
            V3(
                0.2 - 0.02 * lift,
                0.015 - 0.03 + 0.11 * lift,
                -0.02 + 0.02 * lift,
            )
        )
        if kid:
            tip = eb + (tip - eb) * 1.15
    rig.set("earTipL", tip)
    var bt = _hlk(V3(0.0, -0.094, 0.115), kid)
    rig.set("beardTop", bt)
    rig.set("beardTip", bt + V3(0.0, -max(0.03, t.get("beard", 0.0)), -0.01))
    rig.set("udderTop", V3(0.0, 0.44, -0.34 + hq))
    rig.set("udderBot", V3(0.0, 0.3, -0.325 + hq))
    var angles: List[Float64] = [28.0, 42.0, 55.0, 62.0, 66.0]
    var lens: List[Float64] = [0.035, 0.032, 0.03, 0.028, 0.026]
    tail_chain(rig, "tailBase", angles, lens)
    rig.mirror_joints()
    hoofed_bones(rig, TAIL_SEGS)
    _ = rig.add_bone("udder", "udderTop", "udderBot", "pelvis")
    _ = rig.add_bone("beard", "beardTop", "beardTip", "jaw")
    return rig^


@fieldwise_init
struct HornPoint(ImplicitlyCopyable):
    """One station of a horn's center line: where, how thick, how far."""

    var p: V3
    var r: Float64
    var t: Float64


def _horn_cell(t: Traits, res: Float64) -> Float64:
    var b = t.get("hornBase", 0.0)
    return clamp((b if b > 0.0 else 0.012) * 0.13, 0.0025, 0.0039) * min(
        res, 3.0
    )


def _horn_path(t: Traits, s: Float64) -> List[HornPoint]:
    # A scimitar arc from the poll, up and back, sweeping further back and
    # out along its length.
    var out = List[HornPoint]()
    var hlen = t.get("hornLen", 0.0)
    if hlen <= 0.0:
        return out^
    var res = t.get("tierRes", 1.3)
    var tip_cell = _horn_cell(t, 2.25 if res > 3.5 else 2.0)
    var r_min = 0.8 * tip_cell if res >= 1.9 else 0.0
    var f = _frame()
    var up = t.get("hornUpright", 0.0)
    var d0 = normalize(V3(0.0, 0.15 + 0.35 * up, -1.0))
    var v0 = V3(0.0, d0.z, -d0.y)
    var n = max(8, Int(floor(20.0 * min(1.6, hlen / 0.2) + 0.5)))
    var p = _hl(V3(0.021 * s, 0.035, -0.052))
    var ds = hlen / Float64(n)
    var curve = t.get("hornCurve", 0.0)
    var spread = t.get("hornSpread", 0.0)
    var base = t.get("hornBase", 0.0)
    for i in range(n + 1):  # pragma: no branch
        var u = Float64(i) / Float64(n)
        var th = curve * pow(u, 1.15)
        var dl = V3(
            s * (spread * (0.35 + 1.1 * u)),
            d0.y * cos(th) + v0.y * sin(th),
            d0.z * cos(th) + v0.z * sin(th),
        )
        var r = max(r_min, base * pow(1.0 - 0.92 * u, 0.85) + 0.0015)
        out.append(HornPoint(p, r, u))
        p = p + normalize(f.dir(dl)) * ds
    return out^


def _horn_at(pth: List[HornPoint], sarc: Float64, hlen: Float64) -> HornPoint:
    var n = len(pth) - 1
    var u = clamp(sarc / hlen, 0.0, 1.0) * Float64(n)
    var i = min(n - 1, Int(floor(u)))
    var f = u - Float64(i)
    return HornPoint(
        lerp(pth[i].p, pth[i + 1].p, f),
        pth[i].r + (pth[i + 1].r - pth[i].r) * f,
        u / Float64(n),
    )


def _ear_facing(lop: Bool, s: Float64) -> V3:
    if lop:
        return normalize(V3(-0.9 * s, 0.0, 0.0) + _frame().hz * 0.4)
    return normalize(V3(0.25 * s, -0.3, 1.0))


def _hell(
    mut m: SdfModel,
    h: BoneId,
    kid: Bool,
    tag: String,
    c: V3,
    r: V3,
    k: Float64,
    axis_l: V3 = V3(0.0, 0.0, 0.0),
    up_l: V3 = V3(0.0, 0.0, 0.0),
    carve: Bool = False,
) raises:
    # An ellipsoid in head-local coordinates, with a kid's short face.
    var f = _frame()
    var short = kid and c.z > 0.02
    var rr = V3(r.x, r.y, r.z * KID_FACE) if short else r
    var axis = normalize(f.dir(axis_l)) if length(axis_l) > 0.0 else f.hz
    var up = normalize(f.dir(up_l)) if length(up_l) > 0.0 else f.hy
    _ = m.ell(tag, h, _hlk(c, kid), rr, axis=axis, up=up, k=k, carve=carve)


def _back_n(d: V3) -> V3:
    return V3(0.0, d.z, -d.y)


def _fwd_n(d: V3) -> V3:
    return V3(0.0, -d.z, d.y)


def goat_sculpt(mut m: SdfModel, rig: Rig, t: Traits) raises:
    """Sculpt the goat: procedural-animals' `sculptGoat`, primitive for
    primitive.

    Args:
        m: The sculpt to add to.
        rig: The goat's rig in bind pose.
        t: The individual.

    Raises:
        Error: If the rig lacks a joint or a bone, or the sculpt refuses
            a primitive.
    """
    var kid = t.juvenile() > 0.0
    var hq = 0.095 if kid else 0.07
    var male = t.male()
    var buck = male and not kid
    var heavy = t.get("heavy", 0.0)
    var roman = t.get("roman", 0.0)
    var f = _frame()

    # TORSO: a deep barrel, sharp withers, a level back, hip and pin bones.
    var gw = 1.0 + 0.12 * heavy
    _ = m.ell(
        "ribcage",
        rig.bone("spine3"),
        V3(0, 0.585, 0.105),
        V3(0.122 * gw, 0.18, 0.25),
        axis=normalize(V3(0, 0.08, 1)),
        k=0,
    )
    _ = m.ell(
        "girth",
        rig.bone("chest"),
        V3(0, 0.575, 0.28),
        V3(0.1 * gw, 0.15, 0.12),
        k=0.08,
    )
    var doe_adult = not male and not kid
    var milk = (
        t.get("udder", 0.0)
        * (0.7 if t.variant == BOER else 1.0) if doe_adult else 0.0
    )
    var doe = doe_adult and t.variant != BOER
    _ = m.ell(
        "abdomen",
        rig.bone("spine2"),
        V3(0, 0.57 - 0.015 * milk, -0.085),
        V3(0.14 * gw, 0.19 - 0.02 * heavy + 0.02 * milk, 0.165),
        axis=normalize(V3(0, 0.1, -1)),
        k=0.09,
    )
    if doe:
        _ = m.ell(
            "abdomen",
            rig.bone("spine2"),
            V3(0, 0.43 - 0.008 * milk, -0.02),
            V3(0.1, 0.075 + 0.012 * milk, 0.125),
            k=0.08,
        )
    _ = m.ell(
        "flank",
        rig.bone("spine1"),
        V3(0, 0.62, -0.19),
        V3(0.12 * gw, 0.12, 0.11),
        k=0.09,
    )
    _ = m.ell(
        "withers",
        rig.bone("chest"),
        V3(0, 0.735, 0.22),
        V3(0.045, 0.05, 0.15),
        axis=normalize(V3(0, -0.12, 1)),
        k=0.09,
    )
    _ = m.ell(
        "back",
        rig.bone("spine3"),
        V3(0, 0.72, 0.05),
        V3(0.09 * gw, 0.05, 0.2),
        k=0.1,
    )
    _ = m.ell(
        "loin",
        rig.bone("spine1"),
        V3(0, 0.725, -0.13),
        V3(0.1 * gw, 0.045, 0.12),
        k=0.1,
    )
    var pel = rig.bone("pelvis")
    _ = m.ell(
        "pelvis", pel, V3(0, 0.645, -0.3), V3(0.115 * gw, 0.115, 0.105), k=0.05
    )
    _ = m.ell(
        "croup",
        pel,
        V3(0, 0.715, -0.29),
        V3(0.085 * gw, 0.045, 0.11),
        axis=normalize(V3(0, -0.25, 1)),
        k=0.05,
    )
    for s in [1.0, -1.0]:  # pragma: no branch
        _ = m.sphere(
            "hippoint", pel, V3(0.095 * s * gw, 0.715, -0.195), 0.021, k=0.05
        )
        _ = m.sphere("pinbone", pel, V3(0.045 * s, 0.69, -0.362), 0.022, k=0.04)
        _ = m.ell(
            "rump",
            pel,
            V3(0.05 * s, 0.6, -0.335),
            V3(0.055, 0.1, 0.055),
            k=0.06,
        )
    var ch = rig.bone("chest")
    _ = m.ell("brisket", ch, V3(0, 0.482, 0.272), V3(0.075, 0.07, 0.07), k=0.05)
    for s in [1.0, -1.0]:  # pragma: no branch
        _ = m.ell(
            "pectoral",
            ch,
            V3(0.042 * s, 0.475, 0.3),
            V3(0.04, 0.055, 0.026),
            k=0.05,
        )
    _ = m.ell(
        "pectoral", ch, V3(0, 0.525, 0.325), V3(0.075, 0.065, 0.065), k=0.05
    )
    # The udder of an adult doe, or a buck's scrotum: their own surface.
    var ub = rig.bone("udder")
    # Every doe's udder is 0.2 or more.
    var u = t.get("udder", 0.0)
    if doe_adult:
        for s in [1.0, -1.0]:  # pragma: no branch
            _ = m.ell(
                "udder",
                ub,
                V3(0.025 * s, 0.35 - 0.03 * u, -0.338 + hq),
                V3(0.032 + 0.013 * u, 0.047 + 0.03 * u, 0.052 + 0.022 * u),
                k=0.03,
                part=APPENDAGE,
            )
            var a = V3(0.033 * s, 0.315 - 0.055 * u, -0.322 + hq)
            var b = a + V3(0.01 * s, -0.035 - 0.01 * u, 0.013)
            _ = m.cone(
                "teat", ub, a, b, 0.0105, 0.0078, k=0.012, part=APPENDAGE
            )
        _ = m.ell(
            "udder",
            ub,
            V3(0, 0.43, -0.345 + hq),
            V3(0.045, 0.085, 0.072),
            k=0.035,
            part=APPENDAGE,
        )
    if buck:
        var zc = -0.385 + hq
        _ = m.cone(
            "scrotum",
            ub,
            V3(0, 0.575, zc + 0.012),
            V3(0, 0.448, zc - 0.002),
            0.034,
            0.021,
            k=0.02,
            part=APPENDAGE,
        )
        _ = m.ell(
            "scrotum",
            ub,
            V3(0, 0.392, zc - 0.004),
            V3(0.03, 0.05, 0.036),
            k=0.03,
            part=APPENDAGE,
        )
        for s in [1.0, -1.0]:  # pragma: no branch
            _ = m.ell(
                "scrotum",
                ub,
                V3(0.013 * s, 0.375, zc - 0.006),
                V3(0.022, 0.05, 0.04),
                axis=normalize(V3(0, 0.12, 1)),
                k=0.02,
                part=APPENDAGE,
            )
        _ = m.ell(
            "sheath",
            rig.bone("spine2"),
            V3(0, 0.375, -0.02),
            V3(0.017, 0.02, 0.045),
            axis=normalize(V3(0, 0.3, 1)),
            k=0.03,
        )

    # NECK: long and slender; a buck's is thick with a crest.
    var nb = rig.j("neckBase")
    var nm = rig.j("neckMid")
    var occ = rig.j("occiput")
    var nd1 = normalize(nm - nb)
    var nd2 = normalize(occ - nm)
    var nd_m = normalize(nd1 + nd2)
    var nk = 1.0 + 0.3 * heavy
    var n1 = rig.bone("neck1")
    var n2 = rig.bone("neck2")
    var nup = V3(0, 1, -0.6)
    _ = m.ell(
        "neck",
        n1,
        nb + V3(0, 0.008, 0.006),
        V3(0.072 * nk, 0.1, 0.095),
        axis=nd1,
        up=nup,
        k=0.07,
    )
    _ = m.ell(
        "neck",
        n1,
        lerp(nb, nm, 0.72) + V3(0, 0, 0.012),
        V3(0.052 * nk, 0.075 * (1.0 + 0.15 * heavy), 0.1),
        axis=nd1,
        up=nup,
        k=0.07,
    )
    _ = m.ell(
        "neck",
        n2,
        nm + V3(0, 0, 0.018),
        V3(0.047 * nk, 0.064 * (1.0 + 0.15 * heavy), 0.075),
        axis=nd_m,
        up=nup,
        k=0.07,
    )
    _ = m.ell(
        "neck",
        n2,
        lerp(nm, occ, 0.39) + V3(0, 0, 0.028),
        V3(0.042 * nk, 0.052 * (1.0 + 0.15 * heavy), 0.08),
        axis=nd2,
        up=nup,
        k=0.06,
    )
    if heavy > 0.05:
        _ = m.ell(
            "crest",
            n1,
            lerp(nb, nm, 0.9) + _back_n(nd1) * 0.045,
            V3(0.05 + 0.02 * heavy, 0.035 + 0.025 * heavy, 0.13),
            axis=normalize(nd1 + V3(0, 0.1, 0)),
            k=0.07,
        )
    var thr = nm + _fwd_n(nd_m) * 0.07
    _ = m.cone(
        "throat",
        n1,
        nb + nd1 * -0.02 + _fwd_n(nd1) * 0.07,
        thr,
        0.038,
        0.031,
        k=0.045,
    )
    _ = m.cone(
        "throat",
        n2,
        thr + nd_m * -0.01,
        _hl(V3(0, -0.105 + (0.015 if kid else 0.0), -0.06)),
        0.03,
        0.027,
        k=0.04,
    )
    if not kid:
        _ = m.ell(
            "throat",
            n2,
            _hl(V3(0, -0.13, 0.036)),
            V3(0.02, 0.015, 0.022),
            k=0.03,
        )
    if t.get("wattles", 0.0) > 0.5:
        for s in [1.0, -1.0]:  # pragma: no branch
            var a = _hl(V3(0.018 * s, -0.128, -0.068))
            var b = a + V3(0.006 * s, -0.052, -0.006)
            _ = m.cone("wattle", n2, a, b, 0.0065, 0.0095, k=0.008, part=WATTLE)

    # HEAD, head-local: a wedge, the eye high on a deep head, a flat broad
    # forehead to the horn bases, a straight nasal line to a compact nose.
    var h = rig.bone("head")
    var kd = 1.0 if kid else 0.0
    _hell(
        m,
        h,
        kid,
        "cranium",
        V3(0, 0.012 + 0.004 * kd, -0.042),
        V3(0.055, 0.041 + 0.01 * kd, 0.058),
        0.03,
    )
    _hell(
        m, h, kid, "poll", V3(0, -0.014, -0.068), V3(0.035, 0.037, 0.03), 0.03
    )
    var nl = V3(0, -0.29, 1)
    _hell(
        m,
        h,
        kid,
        "forehead",
        V3(0, 0.026, 0.012),
        V3(0.062, 0.018, 0.07),
        0.025,
        axis_l=nl,
    )
    _hell(
        m,
        h,
        kid,
        "face",
        V3(0, -0.004, 0.105),
        V3(0.029, 0.023, 0.095),
        0.025,
        axis_l=nl,
    )
    if roman > 0.05:
        _hell(
            m,
            h,
            kid,
            "face",
            V3(0, 0.013 * roman, 0.105),
            V3(0.022 + 0.004 * roman, 0.016 + 0.012 * roman, 0.07),
            0.03,
            axis_l=nl,
        )
    _hell(
        m,
        h,
        kid,
        "lowerface",
        V3(0, -0.042 + 0.004 * kd, 0.082),
        V3(0.035, 0.043 - 0.006 * kd, 0.088),
        0.03,
    )
    _hell(
        m,
        h,
        kid,
        "muzzle",
        V3(0, -0.032, 0.17),
        V3(0.031 + 0.003 * roman, 0.027, 0.03),
        0.024,
    )
    _hell(
        m,
        h,
        kid,
        "upperlip",
        V3(0, -0.053, 0.181),
        V3(0.025, 0.014, 0.021),
        0.016,
    )
    var eye = goat_eye(t)
    for s in [1.0, -1.0]:  # pragma: no branch
        _hell(
            m,
            h,
            kid,
            "maxilla",
            V3(0.026 * s, -0.03, 0.045),
            V3(0.018, 0.033, 0.065),
            0.03,
            axis_l=V3(0.18 * s, 0, 1),
        )
        if kid:
            _hell(
                m,
                h,
                kid,
                "cheek",
                V3(0.012 * s, -0.055, -0.02),
                V3(0.02, 0.028, 0.03),
                0.03,
            )
        else:
            _hell(
                m,
                h,
                kid,
                "cheek",
                V3(0.035 * s, -0.072, 0.0),
                V3(0.012, 0.056, 0.045),
                0.05,
            )
            _hell(
                m,
                h,
                kid,
                "parotid",
                V3(0.022 * s, -0.072, -0.085),
                V3(0.024, 0.05, 0.05),
                0.035,
            )
        _ = m.cone(
            "mandible",
            h,
            _hlk(
                V3(
                    0.029 * s - 0.004 * s * kd,
                    -0.124 + 0.022 * kd,
                    -0.045 + 0.01 * kd,
                ),
                kid,
            ),
            _hlk(V3(0.013 * s, -0.083, 0.17), kid),
            0.014 - 0.002 * kd,
            0.0085,
            k=0.025 + 0.012 * kd,
        )
        _hell(
            m,
            h,
            kid,
            "buccal",
            V3(0.022 * s, -0.073 + 0.005 * kd, 0.085),
            V3(0.012, 0.019 - 0.004 * kd, 0.07),
            0.025,
            axis_l=V3(-0.14 * s, 0.14, 1),
        )
        _hell(
            m,
            h,
            kid,
            "brow",
            V3(0.048 * s, 0.017, -0.005),
            V3(0.012, 0.008, 0.016),
            0.015,
        )
        _hell(
            m,
            h,
            kid,
            "nostrilwing",
            V3(0.02 * s, -0.026, 0.177),
            V3(0.012, 0.014, 0.014),
            0.013,
        )
        _ = sculpt_eye_socket(
            m,
            eye,
            HEAD_O,
            s,
            h,
            orbit_r=V3(0.016, 0.012, 0.01),
            orbit_at=V3(0.0, 0.001, 0.017),
            orbit_k=0.007,
        )
        _hell(
            m,
            h,
            kid,
            "nostril",
            V3(0.018 * s, -0.026, 0.199),
            V3(0.0026, 0.0105, 0.0065),
            0.0025,
            axis_l=V3(-0.4 * s, 0.15, 1),
            up_l=V3(0.5 * s, 1, 0),
            carve=True,
        )
    _hell(
        m,
        h,
        kid,
        "intermandible",
        V3(0, -0.094 + 0.008 * kd, 0.068 + 0.012 * kd),
        V3(0.018, 0.012 - 0.003 * kd, 0.062 - 0.012 * kd),
        0.02,
        axis_l=V3(0, 0.18, 1),
    )

    # JAW: the lower lip, the chin and the beard's root.
    var jw = rig.bone("jaw")
    _ = m.ell(
        "chin",
        jw,
        _hlk(V3(0, -0.086, 0.168), kid),
        V3(0.017, 0.013, 0.02),
        axis=f.hz,
        up=f.hy,
        k=0,
        part=JAW,
    )
    _ = m.ell(
        "lowerlip",
        jw,
        _hlk(V3(0, -0.071, 0.182), kid),
        V3(0.02, 0.0105, 0.015),
        axis=f.hz,
        up=f.hy,
        k=0.012,
        part=JAW,
    )
    for s in [1.0, -1.0]:  # pragma: no branch
        _ = m.cone(
            "mandible",
            jw,
            _hlk(V3(0.009 * s, -0.085, 0.115), kid),
            _hlk(V3(0.008 * s, -0.084, 0.152), kid),
            0.006,
            0.0065,
            k=0.015,
            part=JAW,
        )
    var beard = t.get("beard", 0.0)
    if beard > 0.01:
        # Three loose locks, the middle one longest.
        var a = _hlk(V3(0, -0.094, 0.12), kid)
        var down = normalize(V3(0, -1, -0.05))
        var bb = rig.bone("beard")
        for j in [-1.0, 0.0, 1.0]:  # pragma: no branch
            var bl = beard * (1.0 if j == 0.0 else 0.78)
            for i in range(4):  # pragma: no branch
                var t0 = Float64(i) / 4.0
                var t1 = Float64(i + 1) / 4.0
                _ = m.cone(
                    "beard",
                    bb,
                    _beard_at(a, down, bl, j, t0),
                    _beard_at(a, down, bl, j, t1),
                    _beard_r(beard, t0),
                    _beard_r(beard, t1),
                    k=0.008,
                    part=APPENDAGE,
                    thin=True,
                )
        _ = m.ell(
            "beard",
            jw,
            _hlk(V3(0, -0.093, 0.13), kid),
            V3(0.019, 0.013, 0.026 * (KID_FACE if kid else 1.0)),
            axis=f.hz,
            up=f.hy,
            k=0.016,
            part=JAW,
        )

    # EARS: a leaf with a rolled base and a cupped front (erect), or a long
    # broad drape with a rolled rim (lop).
    var lop = t.get("lop", 0.0) > 0.5
    for side in [String("L"), String("R")]:  # pragma: no branch
        var s = 1.0 if side == "L" else -1.0
        var base = rig.j("earBase" + side)
        var tip = rig.j("earTip" + side)
        var up = normalize(tip - base)
        var ln = length(tip - base)
        var facing = _ear_facing(lop, s)
        var lat = normalize(cross(up, facing))
        var fc = normalize(cross(lat, up))
        var eb = rig.bone("ear" + side)
        var ek = 0.82 if lop and kid else 1.0
        var wd = 0.05 * (0.88 if kid else 1.0) if lop else 0.029
        if lop:
            var outw = V3(s, 0, 0)
            var fwd = lat if lat.z >= 0.0 else lat * -1.0
            var fwd_f = normalize(fwd + outw * 0.5)
            _ = m.cone(
                "ear",
                eb,
                base + up * 0.004,
                lerp(base, tip, 0.28) + outw * (0.003 * ek),
                0.0115 * ek,
                0.0062 * ek,
                k=0.018 * ek,
                thin=True,
            )
            _ = ell_y(
                m,
                "ear",
                eb,
                lerp(base, tip, 0.44) + fwd * 0.002,
                up,
                V3(wd * 0.84, ln * 0.32, 0.0075 * ek),
                lateral=fwd,
                k=0.016,
                thin=True,
            )
            _ = ell_y(
                m,
                "ear",
                eb,
                lerp(base, tip, 0.69) + outw * (0.0015 * ek),
                up,
                V3(wd, ln * 0.28, 0.0072 * ek),
                lateral=fwd_f,
                k=0.018,
                thin=True,
            )
            _ = ell_y(
                m,
                "eartip",
                eb,
                lerp(base, tip, 0.86) + outw * (0.002 * ek),
                up,
                V3(wd * 0.8, ln * 0.15, 0.0065 * ek),
                lateral=fwd_f,
                k=0.016,
                thin=True,
            )
            _ = m.cone(
                "ear",
                eb,
                lerp(base, tip, 0.14) + fwd * (wd * 0.4),
                lerp(base, tip, 0.64)
                + fwd_f * (wd * 0.86)
                + outw * (0.003 * ek),
                0.003 * ek,
                0.0055 * ek,
                k=0.01 * ek,
                thin=True,
            )
            _ = ell_y(
                m,
                "earinner",
                eb,
                lerp(base, tip, 0.55) + fc * 0.0068,
                up,
                V3(wd * 0.6, ln * 0.28, 0.0052),
                lateral=fwd,
                k=0.004,
                carve=True,
                thin=True,
            )
        else:
            _ = m.cone(
                "ear",
                eb,
                base + up * 0.004,
                lerp(base, tip, 0.27),
                0.011,
                0.0105,
                k=0.014,
                thin=True,
            )
            _ = ell_y(
                m,
                "ear",
                eb,
                lerp(base, tip, 0.44),
                up,
                V3(wd, ln * 0.42, 0.0085),
                lateral=lat,
                k=0.014,
                thin=True,
            )
            _ = ell_y(
                m,
                "eartip",
                eb,
                lerp(base, tip, 0.78),
                up,
                V3(wd * 0.5, ln * 0.24, 0.0065),
                lateral=lat,
                k=0.012,
                thin=True,
            )
            _ = ell_y(
                m,
                "earinner",
                eb,
                lerp(base, tip, 0.6) + fc * 0.0085,
                up,
                V3(wd * 0.66, ln * 0.28, 0.0045),
                lateral=lat,
                k=0.008,
                carve=True,
                thin=True,
            )
        _ = m.sphere("earbase", h, base + up * -0.006, 0.016, k=0.02)

    # HORNS: their own rigid keratin surface on the skull.
    var hlen = t.get("hornLen", 0.0)
    for s in [1.0, -1.0]:  # pragma: no branch
        var pth = _horn_path(t, s)
        for i in range(len(pth) - 1):
            _ = m.cone(
                "horn",
                h,
                pth[i].p,
                pth[i + 1].p,
                pth[i].r,
                pth[i + 1].r,
                k=0.004,
                part=HORN,
            )
        if len(pth) > 0:
            # Flattened sideways at the base: a keel along the front.
            var j = 1
            while j + 1 < len(pth) and length(pth[j].p - pth[0].p) < 0.025:
                j += 1
            var dd = length(pth[j].p - pth[0].p)
            _ = m.ell(
                "horn",
                h,
                lerp(pth[0].p, pth[j].p, 0.5),
                V3(pth[0].r * 0.75, pth[0].r * 1.15, dd * 0.8),
                axis=normalize(pth[j].p - pth[0].p),
                up=f.hz,
                k=0.004,
                part=HORN,
            )
        # Growth ridges round the base half.
        var long_horn = len(pth) > 0 and hlen >= 0.06
        if long_horn:
            var hb = t.get("hornBase", 0.0)
            var spacing = clamp(0.45 * hb, 0.0075, 0.0135)
            var geo = smoothstep(
                2.4, 3.0, spacing / _horn_cell(t, t.get("tierRes", 1.3))
            )
            var s0 = 0.012 + 0.5 * spacing
            var amp = 0.075 if hb > 0.02 else 0.06
            var t_end = 0.62 if hb > 0.02 else 0.5
            var sa = s0
            while geo > 0.01 and sa < t_end * hlen:
                var c = _horn_at(pth, sa, hlen)
                var a = _horn_at(pth, sa - 0.35 * spacing, hlen)
                var b = _horn_at(pth, sa + 0.6 * spacing, hlen)
                var hh = (
                    amp * geo * (1.0 - smoothstep(0.55 * t_end, t_end, c.t))
                )
                if hh >= 0.01:
                    _ = m.cone(
                        "horn",
                        h,
                        a.p,
                        c.p,
                        a.r * (1.0 + 0.15 * hh),
                        c.r * (1.0 + hh),
                        k=0.0015,
                        part=HORN,
                    )
                    _ = m.cone(
                        "horn",
                        h,
                        c.p,
                        b.p,
                        c.r * (1.0 + hh),
                        b.r * (1.0 + 0.1 * hh),
                        k=0.0015,
                        part=HORN,
                    )
                sa += spacing
        if hlen > 0.0:
            _ = m.sphere(
                "hornboss",
                h,
                _hl(V3(0.021 * s, 0.03, -0.05)),
                min(0.016, t.get("hornBase", 0.0) * 0.9),
                k=0.015,
            )

    # MANE: a buck's long hair along the crest and the back.
    # Every buck's mane is 0.4 or more.
    var mn = t.get("mane", 0.0)
    if buck:
        var body = List[Int]()
        # The body is already sculpted.
        for i in range(len(m.prims)):  # pragma: no branch
            var on_body = m.prims[i].part == BODY and not m.prims[i].carve
            if on_body:
                body.append(i)
        var line: List[V3] = [
            _skin(m, body, lerp(nm, occ, 0.75), _back_n(nd2)),
            _skin(m, body, lerp(nm, occ, 0.35), _back_n(nd2)),
            _skin(m, body, lerp(nb, nm, 0.85), _back_n(nd1)),
            _skin(m, body, lerp(nb, nm, 0.4), _back_n(nd1)),
            V3(0, 0.765, 0.2),
            V3(0, 0.745, 0.08),
        ]
        var bones: List[String] = [
            String("neck2"),
            "neck2",
            "neck1",
            "neck1",
            "spine3",
            "spine3",
        ]
        for i in range(len(line)):  # pragma: no branch
            var axis = normalize(line[i] - line[i + 1]) if i + 1 < len(
                line
            ) else V3(0, 0, 1)
            _ = m.ell(
                "mane",
                rig.bone(bones[i]),
                line[i],
                V3(0.028 * mn + 0.01, 0.022 * mn + 0.006, 0.055),
                axis=axis,
                k=0.03,
            )

    # LEGS: slender, with long cannons and cloven hooves.
    var lk = 1.0 + 0.12 * heavy
    for side in [String("L"), String("R")]:  # pragma: no branch
        var s = 1.0 if side == "L" else -1.0
        var lat = V3(s, 0, 0)
        var sc = rig.j("scapTop" + side)
        var sh = rig.j("shoulder" + side)
        var e = rig.j("elbow" + side)
        var w = rig.j("wrist" + side)
        var mc = rig.j("mcp" + side)
        var cf = rig.j("fcoffin" + side)
        var toe = rig.j("ftoe" + side)
        var scap = rig.bone("scapula" + side)
        var hum = rig.bone("humerus" + side)
        var rad = rig.bone("radius" + side)
        var meta = rig.bone("metacarpus" + side)
        _ = ell_y(
            m,
            "scapmuscle",
            scap,
            lerp(sc, sh, 0.45) + V3(0.03 * s, 0, -0.01),
            sh - sc,
            V3(0.022 * lk, 0.1, 0.062),
            lateral=lat,
            k=0.06,
        )
        _ = m.cone(
            "upperarm",
            hum,
            lerp(sh, e, 0.25),
            e,
            0.036 * lk,
            0.032 * lk,
            k=0.04,
        )
        _ = ell_y(
            m,
            "triceps",
            hum,
            lerp(sh, e, 0.55) + V3(0.005 * s, 0.01, -0.045),
            e - sh,
            V3(0.03 * lk, 0.07, 0.048),
            lateral=lat,
            k=0.05,
        )
        _ = m.sphere("olecranon", rad, e + V3(0, 0.012, -0.034), 0.024, k=0.025)
        _ = m.cone(
            "forearm", rad, e + V3(0, 0, -0.005), w, 0.034 * lk, 0.019, k=0.025
        )
        _ = ell_y(
            m,
            "forearmmuscle",
            rad,
            lerp(e, w, 0.25) + V3(0.004 * s, 0, 0.006),
            w - e,
            V3(0.032 * lk, 0.075, 0.035 * lk),
            lateral=lat,
            k=0.025,
        )
        _ = m.cone(
            "forearmweb",
            rad,
            e + V3(-0.02 * s, 0.03, -0.01),
            lerp(e, w, 0.3) + V3(-0.01 * s, 0, 0),
            0.028,
            0.02,
            k=0.03,
        )
        _ = ell_y(
            m,
            "knee",
            meta,
            w + V3(0, 0, 0.002),
            V3(0, 1, 0),
            V3(0.021, 0.026, 0.021),
            lateral=lat,
            k=0.012,
        )
        _ = m.cone(
            "cannon",
            meta,
            w + V3(0, -0.01, 0),
            mc + V3(0, 0.01, 0),
            0.0145,
            0.0135,
            k=0.01,
        )
        _ = m.cone(
            "tendon",
            meta,
            w + V3(0, -0.015, -0.012),
            mc + V3(0, 0.015, -0.013),
            0.009,
            0.011,
            k=0.01,
        )
        _ = ell_y(
            m,
            "fetlock",
            meta,
            mc + V3(0, 0, -0.004),
            V3(0, 1, 0.3),
            V3(0.019, 0.02, 0.021),
            lateral=lat,
            k=0.01,
        )
        var fpaw = rig.bone("fpaw" + side)
        dewclaw_balls(m, fpaw, mc, s, -0.021, 0.0055)
        _ = m.cone("pastern", fpaw, mc, cf, 0.0155, 0.0165, k=0.01)
        _hoof(m, rig.bone("fhoof" + side), cf, toe, 1.0)

        var hp = rig.j("hip" + side)
        var kn = rig.j("knee" + side)
        var hk = rig.j("hock" + side)
        var mt = rig.j("mtp" + side)
        var chf = rig.j("hcoffin" + side)
        var tt = rig.j("htoe" + side)
        var fem = rig.bone("femur" + side)
        var tib = rig.bone("tibia" + side)
        var mtar = rig.bone("metatarsus" + side)
        _ = ell_y(
            m,
            "thigh",
            fem,
            lerp(hp, kn, 0.42) + V3(0.02 * s, 0, -0.025),
            kn - hp,
            V3(0.032 * lk, 0.13, 0.095),
            lateral=lat,
            k=0.06,
        )
        _ = m.cone(
            "thighfront",
            fem,
            V3(0.075 * s, 0.66, -0.3 + hq),
            kn + V3(0, 0.03, 0.02),
            0.048,
            0.03,
            k=0.05,
        )
        _ = m.cone(
            "hamstring",
            fem,
            V3(0.045 * s, 0.64, -0.345),
            lerp(kn, hk, 0.3) + V3(0, 0, -0.04),
            0.045,
            0.026,
            k=0.04,
        )
        _ = ell_y(
            m,
            "flankfold",
            fem,
            V3(0.09 * s, 0.47, -0.2 + hq),
            V3(-0.1, 0.3, 0.12),
            V3(0.024, 0.07, 0.038),
            lateral=lat,
            k=0.05,
        )
        _ = m.sphere(
            "stifle", tib, kn + V3(0.004 * s, 0.005, 0.014), 0.027, k=0.035
        )
        _ = ell_y(
            m,
            "gaskin",
            tib,
            lerp(kn, hk, 0.3) + V3(0.004 * s, 0, -0.024),
            hk - kn,
            V3(0.037 * lk, 0.085, 0.048),
            lateral=lat,
            k=0.03,
        )
        _ = m.cone("shin", tib, lerp(kn, hk, 0.1), hk, 0.026, 0.018, k=0.025)
        _ = m.cone(
            "achilles",
            tib,
            lerp(kn, hk, 0.45) + V3(0, 0, -0.035),
            hk + V3(0, 0.03, -0.03),
            0.012,
            0.01,
            k=0.015,
        )
        _ = m.sphere(
            "calcaneus", mtar, hk + V3(0, 0.028, -0.028), 0.014, k=0.012
        )
        _ = ell_y(
            m,
            "hock",
            mtar,
            hk + V3(0, 0.004, -0.002),
            V3(0, 1, 0.25),
            V3(0.02, 0.03, 0.022),
            lateral=lat,
            k=0.015,
        )
        _ = m.cone(
            "cannon",
            mtar,
            hk + V3(0, -0.016, 0.002),
            mt + V3(0, 0.01, 0),
            0.015,
            0.0135,
            k=0.01,
        )
        _ = m.cone(
            "tendon",
            mtar,
            hk + V3(0, -0.016, -0.013),
            mt + V3(0, 0.015, -0.013),
            0.009,
            0.011,
            k=0.01,
        )
        _ = ell_y(
            m,
            "fetlock",
            mtar,
            mt + V3(0, 0, -0.004),
            V3(0, 1, 0.3),
            V3(0.019, 0.02, 0.021),
            lateral=lat,
            k=0.01,
        )
        var hpaw = rig.bone("hpaw" + side)
        dewclaw_balls(m, hpaw, mt, s, -0.021, 0.0055)
        _ = m.cone("pastern", hpaw, mt, chf, 0.015, 0.016, k=0.01)
        _hoof(m, rig.bone("hhoof" + side), chf, tt, 0.95)

    # TAIL: short, flat and carried up, a brush widening to the tip.
    for i in range(TAIL_SEGS):  # pragma: no branch
        var t0 = Float64(i) / Float64(TAIL_SEGS)
        var t1 = Float64(i + 1) / Float64(TAIL_SEGS)
        var a = rig.j("tail" + String(i))
        var b = rig.j("tail" + String(i + 1))
        var tb = rig.bone("tail" + String(i))
        var w0 = 0.024 - 0.016 * t0
        var w1 = 0.024 - 0.016 * t1
        _ = m.cone(
            "tailhead" if i == 0 else "tail",
            tb,
            a,
            b,
            w0 * 0.72,
            w1 * 0.72,
            k=0.03 if i == 0 else 0.012,
        )
        var d = normalize(b - a)
        var tm = (t0 + t1) * 0.5
        _ = m.ell(
            "tailhair",
            tb,
            lerp(a, b, 0.55),
            V3(0.015 + 0.01 * tm, 0.0095 + 0.002 * tm, length(b - a) * 0.95),
            axis=d,
            up=normalize(cross(d, V3(1, 0, 0))),
            k=0.02,
        )


def _beard_at(a: V3, down: V3, bl: Float64, j: Float64, u: Float64) -> V3:
    return (
        a
        + down * (bl * u)
        + V3(j * (0.006 + 0.008 * u), 0.0, -0.024 * u - 0.004 * abs(j))
    )


def _beard_r(beard: Float64, u: Float64) -> Float64:
    # The original's thin core carries long hair shells; here the lock
    # is the hair's volume, so it is about twice as thick.
    return 2.1 * (0.0045 + 0.0015 * min(1.0, beard / 0.15)) * (1.0 - 0.45 * u)


def _skin(m: SdfModel, body: List[Int], p: V3, d: V3) -> V3:
    # March out from inside the body to its skin, then back 12 mm.
    var u = 0.0
    while u < 0.25 and m.eval_list(body, p + d * u) < 0.0:
        u += 0.002
    return p + d * (u - 0.012)


def _hoof(mut m: SdfModel, bone: BoneId, c: V3, toe_j: V3, w: Float64) raises:
    # Two claws with a cleft between them, the wall parallel to the
    # pastern, heel bulbs behind, flat on the ground.
    var zc = (c.z + toe_j.z) * 0.5
    for k in [1.0, -1.0]:  # pragma: no branch
        var x = c.x + 0.0105 * k * w
        var top = V3(x, c.y + 0.008, c.z - 0.004)
        var toe = V3(x - 0.002 * k, 0.006, toe_j.z - 0.004)
        var heel = V3(x, 0.008, c.z - 0.016)
        _ = m.cone("hoof", bone, top, toe, 0.0115 * w, 0.0055 * w, k=0.006)
        _ = m.cone(
            "hoof",
            bone,
            heel,
            V3(toe.x, 0.006, zc + 0.004),
            0.011 * w,
            0.009 * w,
            k=0.008,
        )
        _ = m.sphere(
            "heelbulb", bone, V3(x, 0.013, c.z - 0.02), 0.0105 * w, k=0.008
        )
    _ = m.cone(
        "coronet",
        bone,
        c + V3(0, 0.012, -0.01),
        c + V3(0, 0.006, 0.008),
        0.017 * w,
        0.017 * w,
        k=0.008,
    )
    _ = m.ell(
        "cleft",
        bone,
        V3(c.x, 0.006, zc + 0.012),
        V3(0.0022, 0.02, 0.03),
        k=0.002,
        carve=True,
    )
    _ = m.ell(
        "sole",
        bone,
        V3(c.x, -0.1 + 0.001, zc),
        V3(0.1, 0.1, 0.1),
        k=0.002,
        carve=True,
    )


def goat_look(t: Traits) -> EyeLook:
    """Return the goat's eye: a horizontal bar pupil in a golden, pale
    yellow, brown-amber or blue iris.

    Args:
        t: The individual. Its coat seed picks the iris.

    Returns:
        The look.
    """
    var s = Float64(Int(t.get("coatSeed", 0.0)) % 100) / 100.0
    var inner = 0xB88F30
    var mid = 0xDCB24A
    var outer = 0x6A4A18
    if s >= 0.96:
        inner = 0x5E7280
        mid = 0xA2BCCB
        outer = 0x3A4650
    elif s >= 0.75:
        inner = 0x74501E
        mid = 0xB08238
        outer = 0x3E2810
    elif s >= 0.45:
        inner = 0xA87F3C
        mid = 0xE8D28A
        outer = 0x7A6030
    return EyeLook(
        srgb(inner), srgb(mid), srgb(outer), V3(0.55, 0.5, 0.45), 0.42, -2.8
    )


def _coat_hexes(coat: Int) -> List[Int]:
    # base, dorsal, belly, head, mark
    if coat == C_CHAMOISEE:
        return [0x906F4E, 0x7E5F40, 0x2A2320, 0x8A6848, 0x221D1B]
    if coat == C_COUBLANC:
        return [0xE2D9C6, 0xD8CEB8, 0xE6DFCF, 0x9A8C7C, 0x1E1C1C]
    if coat == C_TOGGENBURG:
        return [0x8A5A2B, 0x7A4F26, 0x9A6A3A, 0x7E5327, 0xE9E3D6]
    if coat == C_BRITISHALPINE:
        return [0x2D3035, 0x282B2F, 0x323336, 0x2D3035, 0xE9E4D8]
    if coat == C_PIED:
        return [0xEFEBE0, 0xE9E5D8, 0xF3F0E7, 0xEFEBE0, 0x1F1C1B]
    if coat == C_PIEDBROWN:
        return [0xEFEBE0, 0xE9E5D8, 0xF3F0E7, 0xEFEBE0, 0x7A4A26]
    if coat == C_NUBIANRED:
        return [0x7C4A30, 0x6E4129, 0x93613F, 0x7C4A30, 0xE6DDCC]
    if coat == C_NUBIANTAN:
        return [0xB08A5C, 0x9E7B50, 0xC3A174, 0xA98458, 0x2B2420]
    if coat == C_NUBIANBLACK:
        return [0x2A2624, 0x24201F, 0x322D2A, 0x2A2624, 0xD8CBB4]
    if coat == C_BOER:
        return [0xF0EDE6, 0xEBE7DE, 0xF3F1EA, 0xF0EDE6, 0x74391F]
    return [0xEEEBDD, 0xE8E4D4, 0xF3F0E6, 0xEFECE0, 0xEEEBDD]


def _coat_masks(coat: Int) -> Int:
    if coat == C_CHAMOISEE:
        return (
            M_STRIPES
            | M_FACECENTER
            | M_DORSAL
            | M_LEGS
            | M_BELLY
            | M_EARS
            | M_MUZZLE
        )
    if coat == C_COUBLANC:
        return M_REAR | M_STRIPES
    var swiss = coat == C_TOGGENBURG or coat == C_BRITISHALPINE
    if swiss:
        return M_STRIPES | M_LEGS | M_EARS | M_MUZZLE | M_TAILPATCH
    var pied = coat == C_PIED or coat == C_PIEDBROWN
    if pied:
        return M_PATCHES
    var spots = coat == C_NUBIANRED or coat == C_NUBIANBLACK
    if spots:
        return M_SPOTS
    if coat == C_NUBIANTAN:
        return M_DORSAL
    if coat == C_BOER:
        return M_BOERHEAD
    return 0


def _coat_pink(coat: Int) -> Float64:
    if coat == C_SAANEN:
        return 1.0
    var pied = coat == C_PIED or coat == C_PIEDBROWN
    if pied:
        return 0.7
    if coat == C_BOER:
        return 0.4
    return 0.0


def goat_palette(t: Traits) raises -> Palette:
    """Return one goat's palette: its coat, shaded, and its seeded patches.

    Pied goats get four to seven big irregular blotches, most a dark
    hood; Nubians in red or black get ten to nineteen small spots. Their
    centers and radii ride in the palette as `patch` entries.

    Args:
        t: The individual.

    Returns:
        The palette, in linear light.

    Raises:
        Error: Never; the signature matches the other species.
    """
    var coat = Int(t.get("coat", 0.0))
    var hexes = _coat_hexes(coat)
    var k = t.get("coatShade", 0.0)
    var l = t.get("coatLightness", 0.0)
    var out = Palette()
    var names: List[String] = [String("base"), "dorsal", "belly", "head"]
    for i in range(4):  # pragma: no branch
        var c = srgb(hexes[i])
        out.set(
            names[i],
            V3(
                c.x * (1.0 + 0.06 * k + l),
                c.y * (1.0 + l),
                c.z * (1.0 - 0.06 * k + l),
            ),
        )
    out.set("mark", srgb(hexes[4]))
    out.set("horn", srgb(Int(t.get("hornColor", 0.0))))
    out.set("hornDark", srgb(0x5A4A36))
    out.set("skinPink", srgb(0xD9A08A))
    out.set("noseDark", srgb(0x3A302C))
    out.set("hoof", srgb(0x3B3632))
    out.set("hoofPale", srgb(0xC8B394))
    # The patches, from the coat's own stream.
    var masks = _coat_masks(coat)
    var count = 0
    var has_patches = (masks & (M_PATCHES | M_SPOTS)) != 0
    if has_patches:
        var R = AnimalRandom(7331 + Int(t.get("coatSeed", 0.0)), 1, 0)
        var spots = (masks & M_SPOTS) != 0
        var n = 10 + Int(R.next() * 10.0) if spots else 4 + Int(R.next() * 4.0)
        var f = _frame()
        for _ in range(n):  # pragma: no branch
            if spots:
                var c = V3(
                    (R.next() * 2.0 - 1.0) * 0.18,
                    0.55 + R.next() * 0.25,
                    -0.35 + R.next() * 0.55,
                )
                out.set("patch" + String(count), c)
                out.set(
                    "patchr" + String(count),
                    V3(0.02 + 0.03 * R.next(), 0.0, 0.0),
                )
                count += 1
                continue
            var saddle = R.next() < 0.35
            var r = 0.1 + 0.05 * R.next() if saddle else 0.07 + 0.06 * R.next()
            var ez = 0.75 + 0.25 * R.next()
            var ext = r / ez
            var z = mix(-0.44 + ext, 0.14 - ext, R.next())
            var c: V3
            if saddle:
                c = V3(0.0, 0.72 + 0.05 * R.next(), z)
            else:
                var sd = 1.0 if R.next() < 0.5 else -1.0
                var x = sd * (0.11 + 0.04 * R.next())
                c = V3(x, 0.56 + 0.2 * R.next(), z)
            out.set("patch" + String(count), c)
            out.set("patchr" + String(count), V3(r, ez, 0.0))
            count += 1
        if not spots:
            if R.next() < 0.7:
                out.set(
                    "patch" + String(count), f.at_chained(V3(0.0, 0.02, 0.05))
                )
                out.set(
                    "patchr" + String(count),
                    V3(0.1, 0.0, 0.3 + 0.35 * R.next()),
                )
                count += 1
    out.set("patches", V3(Float64(count), 0.0, 0.0))
    return out^


def _neck_u(p: V3) -> Float64:
    # How far along the neck, from its base (0) to its middle (1).
    var ab = NECK_MID_J - NECK_BASE_J
    return dot(p - NECK_BASE_J, ab) / dot(ab, ab)


def _hood_u(p: V3) -> Float64:
    # How far from the neck base toward the occiput, as a fraction.
    var occ = _hl(V3(0.0, -0.045, -0.1))
    var ab = occ - NECK_BASE_J
    return dot(p - NECK_BASE_J, ab) / dot(ab, ab)


def _mark_sd(
    pal: Palette,
    t: Traits,
    masks: Int,
    region: Int,
    tag: String,
    bone: String,
    legness: Float64,
    h: V3,
    p: V3,
    n: V3,
) -> Float64:
    # The breed's second color as a signed distance, inside below zero.
    var face = region == 2 or region == 6
    var head_like = face or region == 5
    var jag = (fbm3(p * 45.0, 2) - 0.5) * (0.005 if head_like else 0.02)
    var d = 1.0
    var ax = abs(h.x)
    if head_like:
        var stripes = (masks & M_STRIPES) != 0 and face
        if stripes:
            var z0 = -0.015
            var z1 = 0.165
            var zc = clamp(h.z, z0, z1)
            var tt = (zc - z0) / (z1 - z0)
            var yc = mix(-0.018, -0.03, tt)
            var rad = sqrt(ax * ax + (h.y - yc) * (h.y - yc))
            var ang = atan2(ax, h.y - yc)
            var ang_c = mix(0.95, 0.72, tt)
            var wa = mix(0.2, 0.26, tt)
            var dz = max(max(z0 - h.z, h.z - z1), 0.0)
            var across = (abs(ang - ang_c) - wa) * rad
            var dd = (
                sqrt(max(across, 0.0) ** 2 + dz * dz) if dz > 0.0 else across
            )
            d = min(d, dd)
        var center = (masks & M_FACECENTER) != 0 and region == 2 and h.y > -0.02
        if center:
            d = min(
                d,
                max(
                    max(
                        ax - 0.016 * (1.0 - 0.35 * clamp(h.z / 0.16, 0.0, 1.0)),
                        -0.03 - h.z,
                    ),
                    h.z - 0.17,
                ),
            )
        var muzzle = (masks & M_MUZZLE) != 0 and face
        if muzzle:
            d = min(d, 0.155 - h.z + (0.01 if h.y > -0.02 else 0.0))
        # Only the Alpine coats mark the ears, and Alpine ears stand.
        var ears = (masks & M_EARS) != 0 and region == 5
        if ears:
            # The outer part of an erect ear.
            var lift = t.get("earLift", 0.5)
            var eb = _hl(V3(0.048, 0.026, -0.06))
            var tip = _hl(
                V3(0.2 - 0.02 * lift, -0.015 + 0.11 * lift, -0.02 + 0.02 * lift)
            )
            var q = V3(abs(p.x), p.y, p.z)
            var ab = tip - eb
            var u = dot(q - eb, ab) / dot(ab, ab)
            d = min(d, (0.62 - u) * 0.06)
        if (masks & M_BOERHEAD) != 0:
            d = min(d, -0.02)
    var boer = (masks & M_BOERHEAD) != 0 and region != 5
    if boer and not head_like:
        # Red-brown head and neck, white body: the border runs round the
        # lower neck.
        var u = _neck_u(p) if region == 1 else -1.0
        var nl = length(NECK_MID_J - NECK_BASE_J)
        d = min(
            d,
            (0.5 - u) * nl + (fbm3(p * 20.0, 2) - 0.5) * 0.05,
        )
    var trunk = region == 0 or region == 1
    if trunk:
        if (masks & M_DORSAL) != 0:
            d = min(
                d,
                abs(p.x)
                - 0.012
                - 0.006 * smoothstep(0.3, -0.4, p.z)
                + (1.0 - smoothstep(0.7, 0.95, n.y)) * 0.05,
            )
        if (masks & M_BELLY) != 0:
            var torso = p.y - 0.43
            var leg = 1.0
            if legness > 0.0:
                var fr = 1.0 if is_front_limb(bone) else -1.0
                leg = p.y - 0.5 + 0.12 * smoothstep(-0.2, 0.7, n.z * fr)
            d = min(d, mix(torso, leg, smoothstep(0.1, 0.6, legness)))
        if (masks & M_REAR) != 0:
            d = min(
                d,
                (p.z + 0.02 + 0.22 * (p.y - 0.6)) * 0.9
                + (fbm3(p * 6.0, 3) - 0.5) * 0.12
                + (vnoise3(p * 90.0) - 0.5) * 0.012,
            )
        if (masks & M_TAILPATCH) != 0:
            var zt = -0.4
            d = min(
                d,
                max(
                    max(
                        p.y - 0.72,
                        sqrt((p.x * 1.1) ** 2 + ((p.y - 0.63) * 0.9) ** 2)
                        - 0.075,
                    ),
                    p.z - (zt + 0.07),
                ),
            )
    if region == 4:
        var rear = (masks & (M_REAR | M_DORSAL)) != 0
        if rear:
            d = -0.01
        if (masks & M_TAILPATCH) != 0:
            d = min(d, -0.01 if n.y < 0.0 else 0.01)
    var leggy = legness > 0.2
    if leggy:
        var fr = is_front_limb(bone)
        var knee_y = 0.3 if fr else 0.34
        if (masks & M_LEGS) != 0:
            d = min(d, p.y - knee_y)
        var rear_leg = (masks & M_REAR) != 0 and not fr
        if rear_leg:
            d = min(d, -0.01)
    var count = Int(pal.get("patches").x)
    var patched = count > 0 and region != 5
    if patched:
        var wob = (fbm3(p * 9.0, 3) - 0.5) * 0.08
        var lobe = (fbm3(p * 4.5 + V3(3.1, 0, 0), 3) - 0.5) * 0.12 + (
            fbm3(p * 28.0, 2) - 0.5
        ) * 0.02
        # Inside `patched`, `count` is positive.
        for i in range(count):  # pragma: no branch
            var c = pal.get("patch" + String(i))
            var q = pal.get("patchr" + String(i))
            if q.z > 0.0:
                # The dark hood over the head and the upper neck.
                var u = 2.0 if head_like else (
                    _hood_u(p) if region == 1 else -1.0
                )
                var nl = length(_hl(V3(0.0, -0.045, -0.1)) - NECK_BASE_J)
                d = min(d, (q.z * 0.6 - u) * nl * 0.8 + wob * 0.6)
                continue
            var ez = q.y if q.y > 0.0 else 0.85
            var dd = (
                sqrt(
                    (p.x - c.x) ** 2
                    + ((p.y - c.y) * 1.1) ** 2
                    + ((p.z - c.z) * ez) ** 2
                )
                - q.x
                + (lobe if q.y > 0.0 else wob)
            )
            d = min(d, dd)
    _ = tag
    return d + jag


def _region(part_horn: Bool, part_jaw: Bool, tag: String, bone: String) -> Int:
    if part_horn:
        return 7
    var jaw = part_jaw or bone == "beard"
    if jaw:
        return 6
    if bone.startswith("ear"):
        return 5
    if bone.startswith("tail"):
        return 4
    var head = bone == "head" or tag == "wattle"
    if head:
        return 2
    var neck = bone == "neck1" or bone == "neck2"
    if neck:
        return 1
    return 0


def _legness(bone: String, p: V3) -> Float64:
    if not is_limb(bone):
        return 0.0
    var upper = (
        bone.startswith("scapula")
        or bone.startswith("humerus")
        or bone.startswith("femur")
    )
    return smoothstep(0.58, 0.42, p.y) if upper else 1.0


def _horn_t(t: Traits, p: V3) -> Float64:
    # How far along the nearer horn, 0 at its base and 1 at its tip.
    var pth = _horn_path(t, 1.0 if p.x >= 0.0 else -1.0)
    var best = 1e9
    var bt = 0.0
    for i in range(len(pth) - 1):
        var a = pth[i].p
        var ab = pth[i + 1].p - a
        var u = clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0)
        var dd = length(p - (a + ab * u))
        if dd < best:
            best = dd
            bt = pth[i].t + (pth[i + 1].t - pth[i].t) * u
    return bt


def _lid_distance(t: Traits, p: V3) -> Float64:
    # The distance to the nearer eye's almond aperture, in its plane.
    var e = goat_eye(t)
    var s = 1.0 if p.x >= 0.0 else -1.0
    var ef = eye_frame_of(e, HEAD_O, s)
    return lid_distance(e, ef, p)


def goat_paint(
    pal: Palette, t: Traits, tag: String, bone: String, s: CoatSample
) -> Paint:
    """Paint one vertex of a goat.

    The breed's coat with countershading, the Swiss face stripes, dark
    points, belly and dorsal stripe, the cou blanc's black hindquarters,
    pied blotches and a hood, Nubian spots and the Boer's red head; pink
    skin under white hair at the nose, lids and udder; ridged keratin
    horns, dark or pale cloven hooves.

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
    var kid = t.juvenile() > 0.0
    var buck = t.male() and not kid
    var coat = Int(t.get("coat", 0.0))
    var masks = _coat_masks(coat)
    var pink = _coat_pink(coat)
    var region = _region(s.part == HORN, s.part == JAW, tag, bone)
    var f = _frame()
    var hloc = f.local(p)
    var h = V3(hloc.x, hloc.y, _un_face_z(hloc.z, kid))
    if region == 7:
        return _paint_horn(pal, t, p)
    var legness = _legness(bone, p)
    var msd = _mark_sd(pal, t, masks, region, tag, bone, legness, h, p, n)
    var white = pink > 0.0 and msd > 0.0
    var mark = pal.get("mark")
    var up = clamp(n.y, -1.0, 1.0)
    var c: V3
    var surface = FUR
    var takes_mark = True
    var long_hair = False
    if region <= 1:
        c = mix3(
            pal.get("base"), pal.get("dorsal"), smoothstep(0.3, 0.95, up) * 0.8
        )
        var ventral: Float64
        if region == 0:
            ventral = smoothstep(-0.2, -0.8, n.y) * smoothstep(0.55, 0.42, p.y)
        else:
            ventral = smoothstep(0.0, -0.7, n.y) * 0.5
        if legness > 0.0:
            var sd = 1.0 if p.x >= 0.0 else -1.0
            ventral = mix(
                ventral,
                smoothstep(0.1, -0.7, n.x * sd)
                * 0.6
                * smoothstep(0.25, 0.45, p.y),
                legness,
            )
        var belly_k = 0.5 if (masks & M_BELLY) != 0 else 1.0
        c = mix3(c, pal.get("belly"), ventral * belly_k)
        var callus = (
            not kid
            and is_front_limb(bone)
            and abs(p.y - 0.21) < 0.022
            and n.z > 0.5
        )
        if callus:
            c = mix3(c, V3(0.08, 0.065, 0.055), 0.5)
        var mane = tag == "mane"
        if mane:
            long_hair = True
        var bag = tag == "udder" or tag == "teat"
        if bag:
            # The udder: fine hair of the coat's color above, bare skin
            # below and on the teats.
            var ut = clamp((0.44 - p.y) / 0.14, 0.0, 1.3)
            var skin = mix3(
                mix3(
                    pal.get("skinPink"),
                    V3(0.03, 0.025, 0.022),
                    0.1 if pink > 0.0 else 0.45,
                ),
                V3(0.8, 0.78, 0.75),
                0.2 if pink > 0.0 else 0.0,
            )
            var border = 0.56 + (fbm3(p * 26.0 + V3(7.7, 0, 0), 2) - 0.5) * 0.24
            var bare = smoothstep(border - 0.04, border + 0.14, ut)
            var in_pat = smoothstep(0.004, -0.004, msd)
            var hair = mix3(c, mark, in_pat)
            var dark_mark = mark.x + mark.y < 0.2
            var skin_c = mix3(
                skin, mark * 1.6, in_pat * (0.75 if dark_mark else 0.0)
            )
            surface = SKIN
            takes_mark = False
            if tag == "teat":
                c = skin_c
            else:
                c = mix3(
                    hair,
                    skin_c,
                    0.3 * smoothstep(0.1, border, ut) + 0.7 * bare,
                )
        var hoofish = tag == "hoof" or tag == "heelbulb" or tag == "dewclaw"
        if hoofish:
            var cz = 0.279 if bone.startswith("f") else (
                -0.419 + (0.095 if kid else 0.07)
            )
            var below = p.y < 0.03 + 0.006 + 0.35 * (p.z - cz)
            if tag == "dewclaw" or below:
                var pale = 0.0
                var pink_hoof = pink > 0.0 and msd > 0.0 and coat != C_BOER
                var light_points = (masks & M_LEGS) != 0 and mark.x > 0.5
                if pink_hoof:
                    pale = 1.0
                elif light_points:
                    pale = 0.7
                c = mix3(pal.get("hoof"), pal.get("hoofPale"), pale)
                if tag == "heelbulb":
                    c = mix3(c, V3(0.1, 0.08, 0.07), 0.4)
                c = c * (
                    0.92
                    + 0.16 * vnoise3(V3(p.x * 300.0, p.y * 40.0, p.z * 300.0))
                )
                return Paint(c, KERATIN)
    elif region == 4:
        c = mix3(pal.get("base"), pal.get("dorsal"), 0.5)
    elif region == 5:
        c = pal.get("head")
        var sd = 1.0 if p.x >= 0.0 else -1.0
        var lop = t.get("lop", 0.0) > 0.5
        var face_dir = _ear_facing(lop, sd)
        var front = dot(n, face_dir)
        var inner = front > 0.3 or tag == "earinner"
        if inner:
            if lop:
                c = mix3(c, pal.get("skinPink"), 0.2) if white else c
            else:
                c = mix3(c, pal.get("skinPink"), 0.35) if white else mix3(
                    c, V3(0.1, 0.08, 0.07), 0.3
                )
    else:
        c = pal.get("head")
        if tag == "beard":
            c = mix3(pal.get("head"), pal.get("base"), 0.3)
            long_hair = True
            takes_mark = (masks & M_BOERHEAD) != 0
        var muz = smoothstep(0.155, 0.185, h.z) * (
            0.0 if tag == "beard" else 1.0
        )
        if muz > 0.0:
            var pink_skin = white or (pink > 0.0 and msd > 0.0)
            c = mix3(
                c,
                pal.get("skinPink") if pink_skin else pal.get("noseDark"),
                muz * 0.45,
            )
        if h.z < -0.08:
            c = mix3(c, pal.get("base"), smoothstep(-0.08, -0.14, h.z))
        # The lids: a thin margin of lid skin round the almond.
        var near_eye = region == 2 and abs(h.x) > 0.035 and h.y > -0.03
        if near_eye:
            var de = _lid_distance(t, p)
            if de < 0.0014:
                c = mix3(
                    pal.get("skinPink"), pal.get("noseDark"), 0.45
                ) if white else V3(0.03, 0.025, 0.022)
                return Paint(c, SKIN)
            if de < 0.0025:
                c = c * 0.55
        # The bare nose pad round the nostrils.
        var nose_col = srgb(0xBCA59F) if white else pal.get("noseDark")
        var pad_in = 1.0 if white else 0.84
        var pad = sqrt((h.x / 0.025) ** 2 + ((h.y + 0.028) / 0.019) ** 2)
        var on_head = region == 2 and tag != "beard"
        if on_head:
            var front = h.z > 0.175 and dot(n, f.hz) > 0.2
            var on_pad = front and pad < pad_in
            if tag == "nostril":
                c = srgb(0x7A5E58) if white else nose_col * 0.35
                return Paint(c, SKIN)
            if on_pad:
                return Paint(nose_col, SKIN)
            var ramp = not white and h.z > 0.165 and pad < 1.3
            if ramp:
                var k = smoothstep(pad_in, 1.3, pad)
                c = mix3(nose_col, mark if msd < 0.0 else c, k)
                takes_mark = False
            # The lips: the upper lip's margin above the lower lip.
            var lip = (
                h.z > 0.155 and h.y < -0.062 and h.y > -0.071 and abs(n.y) < 0.6
            )
            if lip:
                c = srgb(0xA89390) if white else V3(0.03, 0.025, 0.022)
                return Paint(c, SKIN)
        var lower_lip = tag == "lowerlip" and h.y > -0.074
        if lower_lip:
            c = srgb(0xA89390) if white else V3(0.03, 0.025, 0.022)
            return Paint(c, SKIN)
    if takes_mark:
        var in_mark = smoothstep(0.004, -0.004, msd)
        c = mix3(c, mark, in_mark)
    # Low-frequency variation, and lock-to-lock streaks in long hair.
    var cv = fbm3(p * 7.0, 3) - 0.5
    if surface == FUR:
        c = V3(
            c.x * (1.0 + 0.12 * cv),
            c.y * (1.0 + 0.1 * cv),
            c.z * (1.0 + 0.08 * cv),
        )
        var shag = t.get("shaggy", 0.0) > 0.3 and region <= 1
        if long_hair or shag:
            var st = vnoise3(V3(p.x * 160.0, p.y * 40.0, p.z * 160.0))
            c = c * (0.82 + 0.36 * st)
        c = grizzle(c, p, 150.0, 0.07 if buck else 0.05)
    return Paint(c, surface)


def _paint_horn(pal: Palette, t: Traits, p: V3) -> Paint:
    # Dark at the base, lighter toward the polished tip, with transverse
    # growth ridges and grooves, streaky along the horn.
    var bt = _horn_t(t, p)
    var c = mix3(pal.get("hornDark"), pal.get("horn"), smoothstep(0.0, 0.5, bt))
    c = mix3(c, pal.get("horn") * 1.15, smoothstep(0.7, 1.0, bt) * 0.5)
    var hlen = t.get("hornLen", 0.2) * bt
    var ring = pow(0.5 + 0.5 * sin(hlen * 2.0 * pi / 0.009), 3.0)
    c = c * (1.0 - 0.1 * ring * (1.0 - smoothstep(0.5, 0.9, bt)))
    var hb = t.get("hornBase", 0.0)
    var long_horn = t.get("hornLen", 0.0) >= 0.06
    if long_horn:
        var spacing = clamp(0.45 * hb, 0.0075, 0.0135)
        var s0 = 0.012 + 0.5 * spacing
        var t_end = 0.62 if hb > 0.02 else 0.5
        var u = (hlen - s0) / spacing
        var fr = u - floor(u)
        var fade = (1.0 if u > -0.6 else 0.0) * (
            1.0 - smoothstep(0.55 * t_end, t_end + 0.08, bt)
        )
        var groove = exp(-(((fr - 0.66) / 0.11) ** 2))
        var crest = exp(-((min(fr, 1.0 - fr) / 0.12) ** 2))
        var lum = (
            0.2126 * pal.get("horn").x
            + 0.7152 * pal.get("horn").y
            + 0.0722 * pal.get("horn").z
        )
        var dark = 1.0 - smoothstep(0.12, 0.3, lum)
        c = c * (1.0 + fade * (0.06 * crest - mix(0.16, 0.3, dark) * groove))
    c = c * (0.9 + 0.2 * vnoise3(V3(p.x * 300.0, p.y * 300.0, p.z * 300.0)))
    return Paint(c, KERATIN)
