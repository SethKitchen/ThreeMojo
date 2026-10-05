# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The domestic sheep, Ovis aries: procedural-animals' `species/sheep/`.

A cloven-hoofed grazer in wool. The reference adult is a white-faced
medium-wool ewe, 0.70 m at the withers without its fleece. The fleece
is a sculpted volume: offset wool solids box the body into a sheep's
silhouette, and a Poisson-disc scatter of small locks breaks its
surface. The face and the legs are clean short hair. Rams of horned
breeds grow spiral horns. The morphs are white-faced, Suffolk, Merino,
black and shorn.
"""

from extensions.animals.coat import (
    FUR,
    KERATIN,
    SKIN,
    CoatSample,
    EyeLook,
    Paint,
    Palette,
    mix3,
    palette_of,
    srgb,
)
from extensions.sdf.ids import (
    BoneId,
    ELLIPSOID,
)
from extensions.animals.parts import (
    HORN,
    JAW,
)
from extensions.sdf.sculpt import ell_y, cone_or_ball
from extensions.animals.kit import (
    EyeSpec,
    eye_frame_of,
    aperture_tilt_along,
    draw_u32,
    imul32,
    is_limb,
    is_front_limb,
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
)
from render.tasks import TaskGroup
from std.collections import Dict
from std.math import asin, atan2, cos, exp, floor, log, pi, pow, sin, sqrt
from std.sys import num_logical_cores

comptime TAIL_SEGS = 6
# The head's origin: on the head's axis 0.07 m in front of the poll,
# level with the eyes. The head is carried 33 degrees nose-down.
comptime HEAD_O = V3(0.0, 0.8568752675489482, 0.5987069397561797)
comptime HEAD_PITCH = 33.0
# The finest cell, at the `HERO` tier: the head's cell in the original.
comptime CELL = 0.0031

# The morphs, in procedural-animals' order.
comptime WHITEFACE = 0
comptime SUFFOLK = 1
comptime MERINO = 2
comptime BLACK = 3
comptime SHORN = 4

# The coats.
comptime C_WHITE = 0
comptime C_SUFFOLK = 1
comptime C_MERINO = 2
comptime C_BLACK = 3
comptime C_BROWN = 4
comptime C_TEXEL = 5

# Ear carriages.
comptime EAR_LATERAL = 0
comptime EAR_DROOP = 1
comptime EAR_SMALL = 2

# The neck's joints in bind pose; they do not depend on the individual.
comptime NECK_MID_J = V3(0.0, 0.715, 0.425)
comptime NECK_BASE_J = V3(0.0, 0.555, 0.285)
comptime EAR_BASE = V3(0.056, 0.006, -0.058)
comptime EAR_BASE_HORNED = V3(0.05, 0.002, -0.066)


def sheep_variant_names() -> List[String]:
    """Return the sheep's morphs.

    Returns:
        White-faced, Suffolk, Merino, black and shorn.
    """
    return [String("whiteface"), "suffolk", "merino", "black", "shorn"]


def _frame() -> HeadFrame:
    return head_frame(HEAD_O, HEAD_PITCH)


def _hl(v: V3) -> V3:
    return _frame().at_chained(v)


def _ear_of(variant: Int) -> Int:
    if variant == SUFFOLK:
        return EAR_DROOP
    if variant == MERINO:
        return EAR_SMALL
    return EAR_LATERAL


def sheep_traits(mut r: AnimalRandom, options: AnimalOptions) raises -> Traits:
    """Draw one sheep: procedural-animals' `variation`.

    The stream is re-mixed through an integer hash, as the original
    does. Rams are heavier and broader with a thick neck, and curled
    horns in horned breeds. Lambs have long legs, a short body, a big
    head and ears, a short tight fleece and a long tail.

    Args:
        r: The individual's stream.
        options: The caller's sex, age and morph.

    Returns:
        The traits.

    Raises:
        Error: If the requested morph is not one of the five.
    """
    var requested = options.variant.value
    if requested >= 5:
        raise Error("The sheep has no such morph")
    var h = draw_u32(r) ^ imul32(options.seed + 0x632BE5AB, 0x9E3779B1)
    h = imul32(h ^ (h >> 16), 0x85EBCA6B)
    h = imul32(h ^ (h >> 13), 0xC2B2AE35)
    h = h ^ (h >> 16)
    var R = stream_of(h)
    for _ in range(3):  # pragma: no branch
        _ = R.next()
    var variant = requested
    if requested < 0:
        variant = pick_weighted(R, [40.0, 24.0, 16.0, 10.0, 10.0])
    var sex = options.sex
    if sex != MALE and sex != FEMALE:
        sex = MALE if R.next() < 0.4 else FEMALE
    var age = options.age
    if age != ADULT and age != JUVENILE:
        age = JUVENILE if R.next() < 0.18 else ADULT
    var t = Traits(sex, age, variant)
    var lamb = age == JUVENILE
    var male = sex == MALE
    var ram = male and not lamb
    var coat: Int
    if variant == SUFFOLK:
        coat = pick_weighted(R, [1.0]) + C_SUFFOLK
    elif variant == MERINO:
        coat = pick_weighted(R, [1.0]) + C_MERINO
    elif variant == BLACK:
        coat = C_BLACK if pick_weighted(R, [75.0, 25.0]) == 0 else C_BROWN
    elif variant == SHORN:
        coat = C_WHITE if pick_weighted(R, [60.0, 40.0]) == 0 else C_TEXEL
    else:
        coat = pick_weighted(R, [1.0]) + C_WHITE
    var f0: List[Float64] = [0.05, 0.04, 0.06, 0.05, 0.004]
    var f1: List[Float64] = [0.12, 0.09, 0.1, 0.12, 0.015]
    var u = 0.5 + 0.5 * R.g()
    var fleece = (
        0.012
        + 0.01 * R.next() if lamb else f0[variant]
        + (f1[variant] - f0[variant]) * u
    )
    fleece = clamp(fleece, 0.0, 0.15)
    var staple = max(0.005, min(0.018, 0.25 * fleece + 0.004)) * (
        1.1 if lamb else 1.0
    )
    t.set("fleece", fleece)
    t.set("staple", staple)
    t.set("wool", fleece - staple if fleece > 0.035 else 0.0)
    var horned: List[Float64] = [0.0, 0.0, 0.95, 0.3, 0.0]
    var turns = 0.0
    var hbase = 0.0
    var r0 = 0.0
    var flare = 0.0
    var ram_horns = False
    if ram:
        ram_horns = R.next() < horned[variant]
    if ram_horns:
        turns = (1.0 if variant == MERINO else 0.75) + 0.35 * R.next()
        hbase = 0.03 + 0.009 * R.next()
        r0 = 0.95 + 0.1 * R.next()
        flare = 0.8 + 0.4 * R.next()
    else:
        var tup = lamb and male
        if tup:
            if R.next() < horned[variant]:
                turns = 0.12 + 0.06 * R.next()
                hbase = 0.012
                r0 = 0.75
                flare = 0.5
    t.set("hornTurns", turns)
    t.set("hornBase", hbase)
    t.set("hornR0", r0)
    t.set("hornFlare", flare)
    var docked_p: List[Float64] = [0.6, 0.65, 0.85, 0.4, 0.7]
    var docked = R.next() < (
        docked_p[variant] * 0.5 if lamb else docked_p[variant]
    )
    t.set(
        "tailLen", 0.06 + 0.04 * R.next() if docked else 0.3 + 0.08 * R.next()
    )
    var bsize: List[Float64] = [1.0, 1.08, 0.94, 0.98, 1.0]
    var size = (
        (1.13 + 0.05 * R.next() if ram else 1.0)
        * (1.0 + 0.045 * R.g())
        * bsize[variant]
        * (0.62 if lamb else 1.0)
    )
    t.set("size", size)
    t.set("coat", Float64(coat))
    t.set("ear", Float64(_ear_of(variant)))
    t.set("earLift", R.next())
    var rlo: List[Float64] = [0.0, 0.7, 0.2, 0.0, 0.0]
    var rhi: List[Float64] = [0.2, 1.0, 0.5, 0.3, 0.2]
    t.set(
        "roman",
        rlo[variant]
        + (rhi[variant] - rlo[variant]) * R.next()
        + (0.2 if ram else 0.0),
    )
    var topknot_p: List[Float64] = [0.25, 0.0, 1.0, 0.15, 0.0]
    var topknot = 0.0
    if R.next() < topknot_p[variant]:
        topknot = 0.4 + 0.6 * R.next()
    t.set("topknot", topknot)
    var merino_adult = variant == MERINO and not lamb
    t.set(
        "folds", (0.7 if ram else 0.4) + 0.3 * R.next() if merino_adult else 0.0
    )
    t.set("muscle", 0.6 + 0.4 * R.next() if coat == C_TEXEL else 0.3 * R.next())
    var ewe = sex == FEMALE and not lamb
    t.set("udder", 0.1 + 0.6 * R.next() if ewe else 0.0)
    t.set("heavy", 0.6 + 0.4 * R.next() if ram else 0.0)
    t.set("hoofStripe", R.next())
    t.set("hornColor", Float64(0x6A5846 if variant == BLACK else 0xB09A78))
    t.set("coatShade", R.g())
    t.set("coatLightness", 0.05 * R.g())
    t.set("coatSeed", Float64(Int(R.next() * 1e6)))
    t.set("minThick", 0.004)
    var head_k = (
        (1.0 + 0.035 * R.g()) * (1.22 if lamb else 1.0) * (1.06 if ram else 1.0)
    )
    t.warps.add(scale_about_warp(HEAD_O, head_k, 0.1, 0.2))
    var blegs: List[Float64] = [1.0, 1.03, 0.97, 1.0, 1.0]
    var legs_k = (
        (1.0 + 0.035 * R.g()) * blegs[variant] * (1.24 if lamb else 1.0)
    )
    t.warps.add(legs_warp(legs_k, 0.36))
    var len_k = (1.0 + 0.035 * R.g()) * (0.84 if lamb else 1.0)
    t.warps.add(length_warp(len_k, -0.4, 0.3))
    var bgirth: List[Float64] = [1.0, 1.03, 1.0, 1.0, 1.0]
    var girth_k = (
        (1.0 + 0.04 * R.g())
        * bgirth[variant]
        * (1.05 if ram else 1.0)
        * (0.9 if lamb else 1.0)
    )
    t.warps.add(girth_warp(girth_k, 0.47, -0.5, 0.36))
    return t^


def sheep_eye(t: Traits) -> EyeSpec:
    """Return the sheep's left eye: a 29 mm globe on the side of the head
    below the brow, its almond along the nasal line.

    Args:
        t: The individual. The eye is the same in every sheep.

    Returns:
        The eye, head-local.
    """
    _ = t
    var f = _frame()
    var a = 38.0 * pi / 180.0
    var dir = normalize(V3(cos(a), 0.0, 0.0) + f.hz * sin(a))
    var e = EyeSpec(
        _hl(V3(0.058, -0.004, 0.013)) - HEAD_O,
        0.0145,
        0.003,
        atan2(dir.x, dir.z),
        asin(dir.y),
        0.0017,
        0.017,
        0.0095,
        -0.0006,
        0.0,
        0.0081,
        0.0112,
    )
    e.tilt = aperture_tilt_along(e, HEAD_O, f.hz) + 0.16
    return e


def _ear_tip(ear: Int, lift: Float64, horned: Bool, base: V3) -> V3:
    # The ear's tip, head-local: carried out to the side, swept back and a
    # little below level.
    var backs: List[Float64] = [46.0, 40.0, 48.0]
    var downs: List[Float64] = [20.0, 28.0, 14.0]
    var lens: List[Float64] = [0.135, 0.152, 0.112]
    var back = (0.35 if horned else 1.0) * backs[ear] * pi / 180.0
    var down = (downs[ear] + 14.0 * (lift - 0.5)) * pi / 180.0
    var w = V3(cos(down) * cos(back), -sin(down), -cos(down) * sin(back))
    var f = _frame()
    var d = V3(w.x, dot(w, f.hy), dot(w, f.hz))
    return base + d * lens[ear]


def _horned(t: Traits) -> Bool:
    return t.get("hornTurns", 0.0) > 0.3


def _tail_spec(tail_len: Float64) -> Tuple[List[Float64], List[Float64]]:
    var w: List[Float64] = [0.2, 0.19, 0.17, 0.16, 0.14, 0.14]
    var lens = List[Float64]()
    for f in w:  # pragma: no branch
        lens.append(f * tail_len)
    if tail_len > 0.15:
        var a: List[Float64] = [-38.0, -64.0, -76.0, -82.0, -86.0, -88.0]
        return (a^, lens^)
    var b: List[Float64] = [-28.0, -45.0, -55.0, -60.0, -62.0, -64.0]
    return (b^, lens^)


def sheep_rig(t: Traits) raises -> Rig:
    """Return the sheep's skeleton in bind pose.

    The hoofed quadruped with an udder bone below the pelvis. The ears are
    carried out to the sides; a horned ram's come out below the horns.
    The tail hangs to the hocks, or is docked to a stump.

    Args:
        t: The individual.

    Returns:
        The rig.

    Raises:
        Error: If a bone names a missing joint.
    """
    var horned = _horned(t)
    var eb = EAR_BASE_HORNED if horned else EAR_BASE
    var rig = Rig()
    rig.set("nose", _hl(V3(0.0, -0.014, 0.195)))
    rig.set("occiput", _hl(V3(0.0, -0.045, -0.1)))
    rig.set("neckMid", NECK_MID_J)
    rig.set("neckBase", NECK_BASE_J)
    rig.set("chestMid", V3(0.0, 0.585, 0.13))
    rig.set("thoraxRear", V3(0.0, 0.61, -0.03))
    rig.set("lumbarMid", V3(0.0, 0.622, -0.17))
    rig.set("lumbosacral", V3(0.0, 0.625, -0.3))
    rig.set("tailBase", V3(0.0, 0.612, -0.47))
    rig.set("scapTopL", V3(0.056, 0.668, 0.21))
    rig.set("shoulderL", V3(0.086, 0.49, 0.305))
    rig.set("elbowL", V3(0.08, 0.345, 0.215))
    rig.set("wristL", V3(0.068, 0.185, 0.232))
    rig.set("mcpL", V3(0.062, 0.064, 0.238))
    rig.set("fcoffinL", V3(0.062, 0.028, 0.258))
    rig.set("ftoeL", V3(0.062, 0.002, 0.3))
    rig.set("hipL", V3(0.076, 0.555, -0.33))
    rig.set("kneeL", V3(0.09, 0.385, -0.215))
    rig.set("hockL", V3(0.064, 0.215, -0.385))
    rig.set("mtpL", V3(0.058, 0.066, -0.365))
    rig.set("hcoffinL", V3(0.058, 0.029, -0.343))
    rig.set("htoeL", V3(0.058, 0.002, -0.3))
    rig.set("jawHinge", _hl(V3(0.0, -0.045, -0.02)))
    rig.set("jawTip", _hl(V3(0.0, -0.064, 0.189)))
    rig.set("earBaseL", _hl(eb))
    rig.set(
        "earTipL",
        _hl(
            _ear_tip(Int(t.get("ear", 0.0)), t.get("earLift", 0.5), horned, eb)
        ),
    )
    rig.set("udderTop", V3(0.0, 0.4, -0.3))
    rig.set("udderBot", V3(0.0, 0.27, -0.29))
    var spec = _tail_spec(t.get("tailLen", 0.34))
    tail_chain(rig, "tailBase", spec[0], spec[1])
    rig.mirror_joints()
    hoofed_bones(rig, TAIL_SEGS)
    _ = rig.add_bone("udder", "udderTop", "udderBot", "pelvis")
    return rig^


@fieldwise_init
struct HornPoint(ImplicitlyCopyable):
    """One station of a horn's center line: where, how thick, how far."""

    var p: V3
    var r: Float64
    var t: Float64


def _horn_path(t: Traits, s: Float64) -> List[HornPoint]:
    # The ram's spiral: from the poll up and back, down behind the ear,
    # forward under it and up again beside the eye, drifting outward.
    var out = List[HornPoint]()
    var turns = t.get("hornTurns", 0.0)
    if not turns > 0.0:
        return out^
    var r0k = t.get("hornR0", 1.0)
    var b0 = _hl(V3(0.04 * s, 0.03, -0.04))
    var c = V3(b0.x, b0.y - 0.048 * r0k, b0.z - 0.05 * r0k)
    var r0 = sqrt((b0.y - c.y) ** 2 + (b0.z - c.z) ** 2)
    var th0 = atan2(b0.y - c.y, b0.z - c.z)
    var b = log(1.45) / (2.0 * pi)
    # Six stations at least.
    var n = max(6, Int(floor(22.0 * turns + 0.5)))
    var flare = t.get("hornFlare", 1.0)
    var base = t.get("hornBase", 0.0)
    for i in range(n + 1):  # pragma: no branch
        var u = Float64(i) / Float64(n)
        var th = th0 + u * turns * 2.0 * pi
        var r = r0 * exp(b * (th - th0))
        var lat = b0.x + s * (
            0.095 * flare * turns * u + 0.03 * sin(pi * min(1.0, u * 2.0))
        )
        var v = V3(lat, c.y + r * sin(th), c.z + r * cos(th))
        out.append(HornPoint(v, base * pow(1.0 - 0.84 * u, 0.9) + 0.0025, u))
    return out^


def _hell(
    mut m: SdfModel,
    h: BoneId,
    tag: String,
    c: V3,
    r: V3,
    k: Float64,
    axis_l: V3 = V3(0.0, 0.0, 0.0),
    up_l: V3 = V3(0.0, 0.0, 0.0),
    carve: Bool = False,
) raises:
    # An ellipsoid in head-local coordinates.
    var f = _frame()
    var axis = normalize(f.dir(axis_l)) if length(axis_l) > 0.0 else f.hz
    var up = normalize(f.dir(up_l)) if length(up_l) > 0.0 else f.hy
    _ = m.ell(tag, h, f.at_chained(c), r, axis=axis, up=up, k=k, carve=carve)


def _top_y(z: Float64, roman: Float64) -> Float64:
    # The dorsal line: straight from the forehead to the top of the nose,
    # plus the Roman arch.
    return (
        0.046
        - 0.194 * z
        + (0.004 + 0.011 * roman)
        * sin(pi * max(0.0, min(1.0, (z + 0.02) / 0.21)))
    )


def _ear_segments() -> List[V3]:
    # Every ear any sheep can carry, as segments from base to tip, left
    # side: the head's mesh keeps a zone round them.
    var out = List[V3]()
    for ear in range(3):  # pragma: no branch
        for lift in [0.0, 0.5, 1.0]:  # pragma: no branch
            for horned in [False, True]:  # pragma: no branch
                var base = EAR_BASE_HORNED if horned else EAR_BASE
                out.append(_hl(base))
                out.append(_hl(_ear_tip(ear, lift, horned, base)))
    return out^


def _neck_s(p: V3, segs: List[V3]) -> Float64:
    # Signed distance past the cut across the upper neck: positive on the
    # head's side. The ears, swept back past the cut, stay on the head.
    var f = _frame()
    var c1 = _hl(V3(0.0, 0.0, -0.078))
    var c2 = V3(0.0, 0.76, 0.5)
    var d2 = normalize(V3(0.0, 0.45, 1.0))
    var s = min(dot(p - c1, f.hz), (p.y - c2.y) * d2.y + (p.z - c2.z) * d2.z)
    var ear_r = 0.038
    if s > ear_r:
        return s
    var dm = 1e9
    var q = V3(abs(p.x), p.y, p.z)
    # Its callers pass `_ear_segments`, a literal list.
    for i in range(len(segs) // 2):
        var a = segs[2 * i]
        var ab = segs[2 * i + 1] - a
        var u = clamp(dot(q - a, ab) / dot(ab, ab), 0.0, 1.0)
        dm = min(dm, length(q - (a + ab * u)))
    return max(s, ear_r - dm)


def _staple_fall(n: V3, p: V3) -> V3:
    # The fall of the staples: away from the head along the body and down,
    # projected onto the surface.
    var chain: List[V3] = [
        _hl(V3(0.0, -0.045, -0.1)),
        NECK_MID_J,
        NECK_BASE_J,
        V3(0.0, 0.585, 0.13),
        V3(0.0, 0.61, -0.03),
        V3(0.0, 0.622, -0.17),
        V3(0.0, 0.625, -0.3),
        V3(0.0, 0.612, -0.47),
    ]
    var ds = List[Float64]()
    var dmin = 1e9
    for i in range(len(chain) - 1):  # pragma: no branch
        var a = chain[i]
        var d = chain[i + 1] - a
        var u = clamp(dot(p - a, d) / dot(d, d), 0.0, 1.0)
        var dd = length(p - a - d * u)
        ds.append(dd)
        dmin = min(dmin, dd)
    var cd = V3(0.0, 0.0, 0.0)
    for i in range(len(chain) - 1):  # pragma: no branch
        var w = exp(-(ds[i] - dmin) / 0.05)
        cd = cd + normalize(chain[i + 1] - chain[i]) * w
    cd = normalize(cd)
    var v = V3(cd.x, cd.y - 1.2, cd.z)
    var k = dot(n, v)
    var tv = v - n * k
    var l = length(tv)
    return tv * (1.0 / l) if l > 1e-6 else V3(0.0, 0.0, -1.0)


def _lock_radius(f: Float64, merino: Bool) -> Float64:
    return min(0.032, 0.01 + 0.2 * f) * (0.75 if merino else 1.0)


def sheep_sculpt(mut m: SdfModel, rig: Rig, t: Traits) raises:
    """Sculpt the sheep: procedural-animals' `sculptSheep`, primitive for
    primitive, with its fleece and its scatter of locks.

    Args:
        m: The sculpt to add to.
        rig: The sheep's rig in bind pose.
        t: The individual.

    Raises:
        Error: If the rig lacks a joint or a bone, or the sculpt refuses
            a primitive.
    """
    var lamb = t.juvenile() > 0.0
    var male = t.male()
    var ram = male and not lamb
    var heavy = t.get("heavy", 0.0)
    var roman = t.get("roman", 0.0)
    var wool_d = t.get("wool", 0.07)
    var merino = t.variant == MERINO
    var f = _frame()

    # TORSO: a deep, broad barrel, a level back, a broad rounded rump.
    var gw = 1.0 + 0.1 * heavy + t.get("muscle", 0.0) * 0.08
    _ = m.ell(
        "ribcage",
        rig.bone("spine3"),
        V3(0, 0.5, 0.07),
        V3(0.152 * gw, 0.19, 0.27),
        axis=normalize(V3(0, 0.06, 1)),
        k=0,
    )
    _ = m.ell(
        "girth",
        rig.bone("chest"),
        V3(0, 0.49, 0.23),
        V3(0.122 * gw, 0.17, 0.12),
        k=0.05,
    )
    _ = m.ell(
        "abdomen",
        rig.bone("spine2"),
        V3(0, 0.485, -0.13),
        V3(0.16 * gw, 0.18, 0.2),
        axis=normalize(V3(0, 0.06, -1)),
        k=0.06,
    )
    _ = m.ell(
        "flank",
        rig.bone("spine1"),
        V3(0, 0.53, -0.26),
        V3(0.14 * gw, 0.13, 0.13),
        k=0.06,
    )
    _ = m.ell(
        "withers",
        rig.bone("chest"),
        V3(0, 0.645, 0.2),
        V3(0.05, 0.05, 0.13),
        axis=normalize(V3(0, -0.1, 1)),
        k=0.07,
    )
    _ = m.ell(
        "back",
        rig.bone("spine3"),
        V3(0, 0.64, 0.0),
        V3(0.11 * gw, 0.05, 0.22),
        k=0.07,
    )
    _ = m.ell(
        "loin",
        rig.bone("spine1"),
        V3(0, 0.645, -0.2),
        V3(0.12 * gw, 0.045, 0.14),
        k=0.07,
    )
    var pel = rig.bone("pelvis")
    _ = m.ell(
        "pelvis", pel, V3(0, 0.56, -0.39), V3(0.13 * gw, 0.12, 0.13), k=0.05
    )
    _ = m.ell(
        "croup",
        pel,
        V3(0, 0.63, -0.38),
        V3(0.105 * gw, 0.045, 0.14),
        axis=normalize(V3(0, -0.1, 1)),
        k=0.05,
    )
    for s in [1.0, -1.0]:  # pragma: no branch
        _ = m.sphere(
            "hippoint", pel, V3(0.1 * s * gw, 0.635, -0.29), 0.022, k=0.05
        )
        _ = m.sphere("pinbone", pel, V3(0.05 * s, 0.61, -0.49), 0.022, k=0.04)
        _ = m.ell(
            "rump",
            pel,
            V3(0.06 * s, 0.51, -0.46),
            V3(0.065 * gw, 0.11, 0.065),
            k=0.06,
        )
    var ch = rig.bone("chest")
    _ = m.ell("brisket", ch, V3(0, 0.395, 0.3), V3(0.075, 0.075, 0.08), k=0.05)
    for s in [1.0, -1.0]:  # pragma: no branch
        _ = m.ell(
            "pectoral",
            ch,
            V3(0.046 * s, 0.4, 0.33),
            V3(0.042, 0.06, 0.04),
            k=0.04,
        )
    var ub = rig.bone("udder")
    var u = t.get("udder", 0.0)
    var ewe = not male and not lamb
    if ewe and u > 0.05:
        for s in [1.0, -1.0]:  # pragma: no branch
            _ = m.ell(
                "udder",
                ub,
                V3(0.026 * s, 0.315 - 0.02 * u, -0.3),
                V3(0.034 + 0.014 * u, 0.04 + 0.02 * u, 0.045 + 0.015 * u),
                k=0.03,
            )
            var a = V3(0.032 * s, 0.285 - 0.035 * u, -0.29)
            var b = a + V3(0.01 * s, -0.022, 0.01)
            _ = m.cone("teat", ub, a, b, 0.008, 0.006, k=0.01)
    if ram:
        _ = m.ell(
            "scrotum",
            ub,
            V3(0, 0.3, -0.34),
            V3(0.045, 0.075, 0.045),
            axis=normalize(V3(0, 0.2, 1)),
            k=0.035,
        )
        _ = m.ell(
            "sheath",
            rig.bone("spine2"),
            V3(0, 0.3, -0.05),
            V3(0.016, 0.02, 0.045),
            axis=normalize(V3(0, 0.3, 1)),
            k=0.03,
        )

    # NECK: short and thick; a ram's is heavier with a crest.
    var nb = rig.j("neckBase")
    var nm = rig.j("neckMid")
    var occ = rig.j("occiput")
    var nd1 = normalize(nm - nb)
    var nd2 = normalize(occ - nm)
    var nk = 1.0 + 0.25 * heavy
    var n1 = rig.bone("neck1")
    var n2 = rig.bone("neck2")
    var nup = V3(0, 1, -0.6)
    _ = m.ell(
        "neck",
        n1,
        V3(0, 0.575, 0.32),
        V3(0.11 * nk, 0.13, 0.11),
        axis=nd1,
        up=nup,
        k=0.05,
    )
    _ = m.ell(
        "neck",
        n1,
        V3(0, 0.67, 0.4),
        V3(0.1 * nk, 0.105 * (1.0 + 0.15 * heavy), 0.095),
        axis=nd1,
        up=nup,
        k=0.05,
    )
    _ = m.ell(
        "neck",
        n2,
        V3(0, 0.76, 0.47),
        V3(0.078 * nk, 0.085 * (1.0 + 0.15 * heavy), 0.08),
        axis=nd2,
        up=nup,
        k=0.04,
    )
    _ = m.ell("neck", n1, V3(0, 0.6, 0.265), V3(0.12 * nk, 0.12, 0.12), k=0.06)
    _ = m.ell(
        "crest",
        n1,
        V3(0, 0.71, 0.37),
        V3(0.055 + 0.02 * heavy, 0.05 + 0.02 * heavy, 0.15),
        axis=normalize(V3(0, 0.65, 0.75)),
        k=0.07,
    )
    _ = m.cone(
        "throat", n1, V3(0, 0.51, 0.38), V3(0, 0.65, 0.455), 0.05, 0.038, k=0.05
    )
    _ = m.cone(
        "throat",
        n2,
        V3(0, 0.63, 0.455),
        _hl(V3(0, -0.07, -0.1)),
        0.03,
        0.022,
        k=0.03,
    )

    # HEAD, head-local: a narrow braincase behind a flat forehead, the
    # orbits under a brow, a long nasal bridge, a blunt deep muzzle.
    var h = rig.bone("head")
    _hell(m, h, "cranium", V3(0, -0.002, -0.042), V3(0.05, 0.04, 0.05), 0.03)
    _hell(m, h, "poll", V3(0, 0.0, -0.068), V3(0.038, 0.032, 0.03), 0.03)
    _hell(m, h, "forehead", V3(0, 0.028, 0.0), V3(0.056, 0.018, 0.05), 0.025)
    for zw in [  # pragma: no branch
        V3(0.035, 0.032, 0),
        V3(0.08, 0.03, 0),
        V3(0.122, 0.028, 0),
        V3(0.158, 0.027, 0),
    ]:
        var z = zw.x
        var ry = 0.017
        var dz = 0.01
        var slope = (_top_y(z + dz, roman) - _top_y(z - dz, roman)) / (2.0 * dz)
        _hell(
            m,
            h,
            "face",
            V3(0, _top_y(z, roman) - ry, z),
            V3(zw.y, ry, 0.038),
            0.022,
            axis_l=V3(0, slope, 1),
        )
    _hell(m, h, "lowerface", V3(0, -0.043, 0.066), V3(0.043, 0.045, 0.08), 0.03)
    _hell(
        m,
        h,
        "muzzle",
        V3(0, -0.024, 0.155),
        V3(0.035 + 0.002 * roman, 0.034, 0.043),
        0.024,
    )
    _hell(
        m,
        h,
        "face",
        V3(0, _top_y(0.186, roman) - 0.019, 0.184),
        V3(0.025, 0.019, 0.016),
        0.018,
        axis_l=V3(0, -0.3, 1),
    )
    _hell(
        m,
        h,
        "intermandible",
        V3(0, -0.092, 0.025),
        V3(0.02, 0.014, 0.06),
        0.018,
    )
    var eye = sheep_eye(t)
    for s in [1.0, -1.0]:  # pragma: no branch
        _hell(
            m,
            h,
            "maxilla",
            V3(0.031 * s, -0.03, 0.078),
            V3(0.022, 0.036, 0.074),
            0.028,
            axis_l=V3(-0.18 * s, 0, 1),
        )
        _ = m.cone(
            "brow",
            h,
            _hl(V3(0.043 * s, 0.013, 0.03)),
            _hl(V3(0.053 * s, 0.011, -0.012)),
            0.006,
            0.005,
            k=0.02,
        )
        _hell(
            m,
            h,
            "orbitrim",
            V3(0.048 * s, -0.012, -0.011),
            V3(0.012, 0.018, 0.014),
            0.016,
        )
        _ = m.cone(
            "facialcrest",
            h,
            _hl(V3(0.05 * s, -0.026, 0.001)),
            _hl(V3(0.038 * s, -0.033, 0.075)),
            0.01,
            0.007,
            k=0.016,
        )
        _hell(
            m,
            h,
            "buccal",
            V3(0.032 * s, -0.058, 0.075),
            V3(0.019, 0.028, 0.062),
            0.03,
        )
        _hell(
            m,
            h,
            "cheek",
            V3(0.043 * s, -0.074, -0.01),
            V3(0.021, 0.052, 0.046),
            0.028,
        )
        _hell(
            m,
            h,
            "jawangle",
            V3(0.035 * s, -0.116, -0.03),
            V3(0.019, 0.032, 0.031),
            0.024,
        )
        _ = m.cone(
            "mandible",
            h,
            _hl(V3(0.034 * s, -0.128, -0.026)),
            _hl(V3(0.024 * s, -0.075, 0.13)),
            0.011,
            0.0095,
            k=0.022,
        )
        _hell(
            m,
            h,
            "nostrilwing",
            V3(0.019 * s, -0.019, 0.177),
            V3(0.012, 0.014, 0.014),
            0.013,
        )
        _hell(
            m,
            h,
            "lipside",
            V3(0.021 * s, -0.045, 0.16),
            V3(0.011, 0.011, 0.025),
            0.015,
            axis_l=V3(-0.14 * s, 0.05, 1),
        )
        _hell(
            m,
            h,
            "upperlip",
            V3(0.013 * s, -0.04, 0.182),
            V3(0.016, 0.0125, 0.018),
            0.012,
        )
        # The eye socket, with a soft lid blend and no orbit carve.
        var ef = eye_frame_of(eye, HEAD_O, s)
        _ = m.sphere("eyelid", h, ef.c, eye.r + eye.lid, k=eye.r * 0.8)
        _ = m.lens(
            "eyesocket",
            h,
            ef.c + ef.y * eye.off,
            ef.x,
            ef.y,
            ef.z,
            eye.big_r,
            eye.d,
            -eye.r * 0.16,
            eye.r * 1.4,
            k=eye.r * 0.18,
            carve=True,
        )
        _hell(
            m,
            h,
            "preorbital",
            V3(0.047 * s, -0.021, 0.047),
            V3(0.004, 0.003, 0.008),
            0.004,
            carve=True,
        )
        _hell(
            m,
            h,
            "nostril",
            V3(0.0105 * s, -0.019, 0.2015),
            V3(0.0014, 0.0078, 0.004),
            0.0015,
            axis_l=V3(0.3 * s, -0.1, 1),
            up_l=V3(-0.64 * s, 0.77, 0),
            carve=True,
        )
    _hell(
        m,
        h,
        "philtrum",
        V3(0, -0.046, 0.2),
        V3(0.0018, 0.006, 0.006),
        0.002,
        carve=True,
    )

    # JAW: the lower lip and the chin.
    var jw = rig.bone("jaw")
    _ = m.ell(
        "chin",
        jw,
        _hl(V3(0, -0.063, 0.158)),
        V3(0.023, 0.019, 0.028),
        axis=f.hz,
        up=f.hy,
        k=0,
        part=JAW,
    )
    _ = m.ell(
        "lowerlip",
        jw,
        _hl(V3(0, -0.053, 0.176)),
        V3(0.021, 0.013, 0.017),
        axis=f.hz,
        up=f.hy,
        k=0.012,
        part=JAW,
    )
    for s in [1.0, -1.0]:  # pragma: no branch
        _ = m.cone(
            "mandible",
            jw,
            _hl(V3(0.02 * s, -0.06, 0.124)),
            _hl(V3(0.018 * s, -0.058, 0.158)),
            0.0085,
            0.012,
            k=0.015,
            part=JAW,
        )

    # EARS: leaves held level out to the sides, the cup facing forward,
    # out and down.
    var ear = Int(t.get("ear", 0.0))
    var ear_w = 0.031 if ear == EAR_DROOP else (
        0.024 if ear == EAR_SMALL else 0.028
    )
    for side in [String("L"), String("R")]:  # pragma: no branch
        var s = 1.0 if side == "L" else -1.0
        var base = rig.j("earBase" + side)
        var tip = rig.j("earTip" + side)
        var up = normalize(tip - base)
        var ln = length(tip - base)
        var facing = _ear_facing(ear, up, s)
        var lat = normalize(cross(up, facing))
        var fc = normalize(cross(lat, up))
        var eb = rig.bone("ear" + side)
        _ = m.cone(
            "earstalk",
            eb,
            base + up * 0.004,
            lerp(base, tip, 0.3),
            0.0115,
            0.0095,
            k=0.01,
            thin=True,
        )
        _ = ell_y(
            m,
            "ear",
            eb,
            lerp(base, tip, 0.53),
            up,
            V3(ear_w, ln * 0.4, 0.0062),
            lateral=lat,
            k=0.016,
            thin=True,
        )
        _ = ell_y(
            m,
            "eartip",
            eb,
            lerp(base, tip, 0.8),
            up,
            V3(ear_w * 0.5, ln * 0.24, 0.0045),
            lateral=lat,
            k=0.014,
            thin=True,
        )
        _ = ell_y(
            m,
            "earinner",
            eb,
            lerp(base, tip, 0.58) + fc * 0.0054,
            up,
            V3(ear_w * 0.7, ln * 0.32, 0.0042),
            lateral=lat,
            k=0.005,
            carve=True,
            thin=True,
        )
        _ = m.sphere("earbase", h, base + up * -0.006, 0.016, k=0.02)

    # HORNS: the ram's spirals, their own rigid surface.
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
            _ = m.sphere(
                "hornboss",
                h,
                _hl(V3(0.036 * s, 0.028, -0.035)),
                min(0.018, t.get("hornBase", 0.0) * 0.6),
                k=0.015,
            )

    # LEGS: fine-boned, with long cannons.
    var lk = 1.0 + 0.1 * heavy
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
            V3(0.024 * lk, 0.095, 0.062),
            lateral=lat,
            k=0.06,
        )
        _ = m.sphere(
            "shoulderpoint", hum, sh + V3(0.008 * s, 0.0, 0.012), 0.027, k=0.04
        )
        _ = m.cone("upperarm", hum, sh, e, 0.038 * lk, 0.033 * lk, k=0.04)
        _ = ell_y(
            m,
            "triceps",
            hum,
            lerp(sh, e, 0.55) + V3(0.005 * s, 0.01, -0.045),
            e - sh,
            V3(0.032 * lk, 0.068, 0.05),
            lateral=lat,
            k=0.05,
        )
        _ = m.sphere("olecranon", rad, e + V3(0, 0.012, -0.032), 0.023, k=0.025)
        _ = m.cone(
            "forearm", rad, e + V3(0, 0, -0.005), w, 0.033 * lk, 0.018, k=0.025
        )
        _ = ell_y(
            m,
            "forearmmuscle",
            rad,
            lerp(e, w, 0.25) + V3(0.004 * s, 0, 0.006),
            w - e,
            V3(0.031 * lk, 0.065, 0.034 * lk),
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
            V3(0.02, 0.025, 0.02),
            lateral=lat,
            k=0.012,
        )
        _ = m.cone(
            "cannon",
            meta,
            w + V3(0, -0.01, 0),
            mc + V3(0, 0.01, 0),
            0.014,
            0.013,
            k=0.01,
        )
        _ = m.cone(
            "tendon",
            meta,
            w + V3(0, -0.015, -0.011),
            mc + V3(0, 0.015, -0.012),
            0.0085,
            0.0105,
            k=0.01,
        )
        _ = ell_y(
            m,
            "fetlock",
            meta,
            mc + V3(0, 0, -0.004),
            V3(0, 1, 0.3),
            V3(0.018, 0.019, 0.02),
            lateral=lat,
            k=0.01,
        )
        var fpaw = rig.bone("fpaw" + side)
        dewclaw_balls(m, fpaw, mc, s, -0.02, 0.0052)
        _ = m.cone("pastern", fpaw, mc, cf, 0.0148, 0.0158, k=0.01)
        _hoof(m, rig.bone("fhoof" + side), cf, toe, 0.97)

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
            lerp(hp, kn, 0.42) + V3(0.022 * s, 0, -0.03),
            kn - hp,
            V3(0.036 * lk, 0.125, 0.095),
            lateral=lat,
            k=0.06,
        )
        _ = m.cone(
            "thighfront",
            fem,
            V3(0.075 * s, 0.585, -0.28),
            kn + V3(0, 0.03, 0.02),
            0.05,
            0.03,
            k=0.05,
        )
        _ = m.cone(
            "hamstring",
            fem,
            V3(0.05 * s, 0.58, -0.47),
            lerp(kn, hk, 0.3) + V3(0, 0, -0.04),
            0.05,
            0.027,
            k=0.04,
        )
        _ = ell_y(
            m,
            "flankfold",
            fem,
            V3(0.095 * s, 0.41, -0.19),
            V3(-0.1, 0.3, 0.12),
            V3(0.025, 0.065, 0.038),
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
            lerp(kn, hk, 0.3) + V3(0.004 * s, 0, -0.022),
            hk - kn,
            V3(0.034 * lk, 0.075, 0.043),
            lateral=lat,
            k=0.03,
        )
        _ = m.cone("shin", tib, lerp(kn, hk, 0.1), hk, 0.026, 0.017, k=0.025)
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
            "calcaneus", mtar, hk + V3(0, 0.027, -0.027), 0.014, k=0.012
        )
        _ = ell_y(
            m,
            "hock",
            mtar,
            hk + V3(0, 0.004, -0.002),
            V3(0, 1, 0.25),
            V3(0.019, 0.029, 0.021),
            lateral=lat,
            k=0.015,
        )
        _ = m.cone(
            "cannon",
            mtar,
            hk + V3(0, -0.016, 0.002),
            mt + V3(0, 0.01, 0),
            0.0145,
            0.013,
            k=0.01,
        )
        _ = m.cone(
            "tendon",
            mtar,
            hk + V3(0, -0.016, -0.012),
            mt + V3(0, 0.015, -0.012),
            0.0085,
            0.0105,
            k=0.01,
        )
        _ = ell_y(
            m,
            "fetlock",
            mtar,
            mt + V3(0, 0, -0.004),
            V3(0, 1, 0.3),
            V3(0.018, 0.019, 0.02),
            lateral=lat,
            k=0.01,
        )
        var hpaw = rig.bone("hpaw" + side)
        dewclaw_balls(m, hpaw, mt, s, -0.02, 0.0052)
        _ = m.cone("pastern", hpaw, mt, chf, 0.0145, 0.0155, k=0.01)
        _hoof(m, rig.bone("hhoof" + side), chf, tt, 0.93)

    # TAIL: thin and hanging.
    for i in range(TAIL_SEGS):  # pragma: no branch
        var t0 = Float64(i) / Float64(TAIL_SEGS)
        var t1 = Float64(i + 1) / Float64(TAIL_SEGS)
        _ = m.cone(
            "tailhead" if i == 0 else "tail",
            rig.bone("tail" + String(i)),
            rig.j("tail" + String(i)),
            rig.j("tail" + String(i + 1)),
            0.026 - 0.014 * t0,
            0.026 - 0.014 * t1,
            k=0.03 if i == 0 else 0.008,
            thin=i >= TAIL_SEGS - 2,
        )

    # FLEECE.
    if wool_d > 0.02:
        _fleece(m, rig, t, wool_d, gw, nk, merino)


def _ear_facing(ear: Int, up: V3, s: Float64) -> V3:
    # The blade turned about its own axis so the cup opens forward, out
    # and down; the Suffolk's hanging ear nearly upright, facing forward.
    var fwd = normalize(V3(-s * up.z, 0.0, abs(up.x)))
    var tilt = (80.0 if ear == EAR_DROOP else 55.0) * pi / 180.0
    return normalize(V3(0.0, -1.0, 0.0) * cos(tilt) + fwd * sin(tilt))


def _fleece(
    mut m: SdfModel,
    rig: Rig,
    t: Traits,
    wf: Float64,
    gw: Float64,
    nk: Float64,
    merino: Bool,
) raises:
    # The wool volume: offsets of the body masses boxed out into the
    # sheep's silhouette, then broken into locks on its surface.
    var fleece = List[Int]()
    var groups = List[Bool]()
    var kf = 0.035 + 0.25 * wf
    var side = 0.155 * gw + wf
    var top = 0.685 + wf * 0.72
    var bot = 0.305 - wf * 0.3
    var cy = (top + bot) / 2.0
    var hh = (top - bot) / 2.0
    var sec_bones: List[String] = [
        String("chest"),
        "spine3",
        "spine2",
        "spine1",
        "pelvis",
    ]
    var sec_z: List[Float64] = [0.2, 0.03, -0.14, -0.28, -0.4]
    var sec_w: List[Float64] = [0.9, 1.0, 1.02, 1.02, 0.98]
    var sec_t: List[Float64] = [0.0, 0.0, 0.0, 0.005, 0.0]
    var sec_b: List[Float64] = [0.02, -0.01, 0.0, 0.03, 0.06]
    var sec_rz: List[Float64] = [
        0.16 + wf * 0.7,
        0.17 + wf * 0.45,
        0.15 + wf * 0.4,
        0.13 + wf * 0.4,
        0.13 + wf * 0.8,
    ]
    for i in range(5):  # pragma: no branch
        var bone = rig.bone(sec_bones[i])
        var hw = side * sec_w[i]
        var tt = top - sec_t[i]
        var bb = bot + sec_b[i]
        var c = (tt + bb) / 2.0
        var hs = (tt - bb) / 2.0
        var z = sec_z[i]
        var rz = sec_rz[i]
        fleece.append(
            m.ell(
                "fleece",
                bone,
                V3(0, c + hs * 0.25, z),
                V3(hw * 0.98, hs * 0.78, rz),
                k=kf,
            )
        )
        fleece.append(
            m.ell(
                "fleece",
                bone,
                V3(0, c - hs * 0.28, z),
                V3(hw, hs * 0.74, rz * 0.96),
                k=kf,
            )
        )
        fleece.append(
            m.ell(
                "fleece",
                bone,
                V3(0, tt - hw * 0.45, z),
                V3(hw * 0.92, hw * 0.46, rz * 0.98),
                k=kf,
            )
        )
        for _ in range(3):  # pragma: no branch
            groups.append(False)
    fleece.append(
        m.ell(
            "fleece",
            rig.bone("chest"),
            V3(0, 0.43, 0.3),
            V3(0.1 + wf * 0.8, 0.13 + wf * 0.6, 0.09 + wf),
            k=kf,
        )
    )
    fleece.append(
        m.ell(
            "woolbelly",
            rig.bone("spine2"),
            V3(0, cy - hh * 0.55, -0.06),
            V3(side * 0.82, hh * 0.45, 0.3 + wf * 0.3),
            k=kf,
        )
    )
    groups.append(False)
    groups.append(False)
    for s in [1.0, -1.0]:  # pragma: no branch
        fleece.append(
            m.ell(
                "fleece",
                rig.bone("pelvis"),
                V3(0.065 * s, 0.5, -0.47),
                V3(0.075 + wf * 0.8, 0.13 + wf * 0.4, 0.075 + wf * 0.95),
                k=kf,
            )
        )
        groups.append(False)
    # The neck: a thick collar of wool; the head comes out of it.
    var nb = rig.j("neckBase")
    var nm = rig.j("neckMid")
    var occ = rig.j("occiput")
    var nf = wf * (1.0 if merino else 0.9)
    var n1 = rig.bone("neck1")
    var n2 = rig.bone("neck2")
    fleece.append(
        m.ell(
            "woolneck",
            n1,
            V3(0, 0.58, 0.33),
            V3(0.09 * nk + nf, 0.11 + nf, 0.1 + nf * 0.6),
            axis=normalize(nm - nb),
            up=V3(0, 1, -0.6),
            k=kf,
        )
    )
    fleece.append(
        m.ell(
            "woolneck",
            n1,
            V3(0, 0.66, 0.39),
            V3(0.07 * nk + nf, 0.085 + nf, 0.078 + nf * 0.32),
            axis=normalize(nm - nb),
            up=V3(0, 1, -0.6),
            k=kf,
        )
    )
    var collar = 0.035 if t.get("hornTurns", 0.0) > 0.0 else 0.0
    var cc = lerp(nm, occ, 0.44 - collar * 4.0)
    fleece.append(
        m.ell(
            "woolneck",
            n2,
            cc + V3(0, -0.012, -0.016),
            V3(0.05 * nk + nf * 0.62, 0.05 + nf * 0.36, 0.048 + nf * 0.26),
            axis=normalize(occ - nm),
            up=V3(0, 1, -0.4),
            k=kf * 0.8,
        )
    )
    var hood_a = lerp(occ, nm, 0.12 + collar * 3.0) + V3(0, -0.058, -0.012)
    var hood_b = lerp(occ, nm, 0.75) + V3(0, -0.02, 0)
    fleece.append(
        m.cone(
            "woolneck",
            n2,
            hood_a,
            hood_b,
            0.048 + nf * 0.3,
            0.058 * nk + nf * 0.6,
            k=kf * 0.6,
        )
    )
    for _ in range(4):  # pragma: no branch
        groups.append(False)
    var f = _frame()
    var tk = t.get("topknot", 0.0)
    if tk > 0.05:
        fleece.append(
            m.ell(
                "woolpoll",
                rig.bone("head"),
                _hl(V3(0, 0.03, -0.055 + 0.015 * tk)),
                V3(
                    0.032 + 0.018 * tk,
                    0.01 + wf * 0.15 * tk,
                    0.028 + 0.022 * tk,
                ),
                axis=f.hz,
                up=f.hy,
                k=0.02,
            )
        )
        groups.append(False)
    if merino:
        for s in [1.0, -1.0]:  # pragma: no branch
            fleece.append(
                m.ell(
                    "woolcheek",
                    rig.bone("head"),
                    _hl(V3(0.036 * s, -0.035, -0.05)),
                    V3(0.03 + wf * 0.25, 0.045, 0.045),
                    axis=f.hz,
                    up=f.hy,
                    k=0.025,
                )
            )
            groups.append(False)
    # The legs: wool over the upper arm, the thigh and the gaskin.
    for side in [String("L"), String("R")]:  # pragma: no branch
        var s = 1.0 if side == "L" else -1.0
        var sh = rig.j("shoulder" + side)
        var e = rig.j("elbow" + side)
        var w = rig.j("wrist" + side)
        var hp = rig.j("hip" + side)
        var kn = rig.j("knee" + side)
        var hk = rig.j("hock" + side)
        var fl = wf * (0.85 if merino else 0.7)
        fleece.append(
            m.ell(
                "woolarm",
                rig.bone("humerus" + side),
                lerp(sh, e, 0.55) + V3(0.008 * s, 0, -0.01),
                V3(0.045 + fl * 0.8, 0.1 + fl * 0.5, 0.06 + fl * 0.7),
                axis=normalize(e - sh),
                up=V3(0, 0, 1),
                k=kf,
            )
        )
        fleece.append(
            m.cone(
                "woolleg",
                rig.bone("radius" + side),
                e + V3(0, 0.01, -0.01),
                lerp(e, w, 0.75 if merino else 0.28),
                0.035 + fl * 0.55,
                0.024 + fl * (0.25 if merino else 0.35),
                k=0.03,
            )
        )
        fleece.append(
            m.ell(
                "woolthigh",
                rig.bone("femur" + side),
                lerp(hp, kn, 0.5) + V3(0.02 * s, -0.01, -0.04),
                V3(0.05 + fl * 0.8, 0.14 + fl * 0.4, 0.1 + fl * 0.8),
                axis=normalize(kn - hp),
                up=V3(0, 0, 1),
                k=kf,
            )
        )
        fleece.append(
            m.cone(
                "woolleg",
                rig.bone("tibia" + side),
                kn + V3(0, 0, -0.03),
                lerp(kn, hk, 0.85 if merino else 0.62) + V3(0, 0, -0.012),
                0.045 + fl * 0.6,
                0.026 + fl * (0.3 if merino else 0.35),
                k=0.03,
            )
        )
        for _ in range(4):  # pragma: no branch
            groups.append(True)
    # The tail's wool.
    var tail_len = t.get("tailLen", 0.34)
    for i in range(TAIL_SEGS):  # pragma: no branch
        var t0 = Float64(i) / Float64(TAIL_SEGS)
        var t1 = Float64(i + 1) / Float64(TAIL_SEGS)
        var ww = min(wf, 0.04) * (0.6 if tail_len > 0.15 else 1.2)
        fleece.append(
            cone_or_ball(
                m,
                "wooltail",
                rig.bone("tail" + String(i)),
                rig.j("tail" + String(i)),
                rig.j("tail" + String(i + 1)),
                0.03 + ww * (1.0 - 0.3 * t0),
                0.03 * (1.0 - 0.35 * t1) + ww * (1.0 - 0.3 * t1),
                k=0.022 if i == 0 else 0.012,
                thin=i >= TAIL_SEGS - 2,
            )
        )
        groups.append(False)
    # The Merino's skin folds: rings of wool round the neck.
    var folds = t.get("folds", 0.0) if merino else 0.0
    if folds > 0.05:
        for i in range(4):  # pragma: no branch
            var u = 0.15 + Float64(i) * 0.22
            var c = lerp(nb, occ, u * 0.8)
            var rr = (0.075 * nk + nf) * (1.02 - 0.2 * u)
            fleece.append(
                m.ell(
                    "fold",
                    n1 if u < 0.45 else n2,
                    c + V3(0, -0.01, 0.01),
                    V3(
                        rr + 0.012 * folds,
                        rr * 1.1 + 0.012 * folds,
                        0.018 + 0.008 * folds,
                    ),
                    axis=normalize(occ - nb),
                    up=V3(0, 1, -0.5),
                    k=0.03,
                )
            )
            groups.append(False)
    # Its caller sculpts a fleece only over 0.02 of wool: enough for locks.
    _locks(m, t, fleece, groups, wf, merino)


def _fgrad(m: SdfModel, list: List[Int], p: V3) -> V3:
    var e = 0.001
    return normalize(
        V3(
            m.eval_list(list, p + V3(e, 0, 0))
            - m.eval_list(list, p - V3(e, 0, 0)),
            m.eval_list(list, p + V3(0, e, 0))
            - m.eval_list(list, p - V3(0, e, 0)),
            m.eval_list(list, p + V3(0, 0, e))
            - m.eval_list(list, p - V3(0, 0, e)),
        )
    )


async def _project_task(
    model: Pointer[SdfModel, MutAnyOrigin],
    fleece: Pointer[List[Int], ImmutAnyOrigin],
    starts: Pointer[List[V3], MutAnyOrigin],
    projected: MutPointer[V3, MutAnyOrigin],
    landed: MutPointer[Bool, MutAnyOrigin],
    first: Int,
    past: Int,
):
    """Project a run of lock tries onto the fleece by Newton steps.

    A try lands when six steps bring it within 3 mm of the surface.
    """
    for attempt in range(first, past):
        var p = starts[][attempt]
        var ok = True
        for it in range(6):  # pragma: no branch
            var d = model[].eval_list(fleece[], p)
            if abs(d) < 3e-4:
                break
            p = p - _fgrad(model[], fleece[], p) * d
            var far = it == 5 and abs(model[].eval_list(fleece[], p)) > 0.003
            if far:
                ok = False
        projected[unsafe_offset=attempt] = p
        landed[unsafe_offset=attempt] = ok


def _cell_key(p: V3, cell: Float64) -> Int:
    var i = Int(floor(p.x / cell)) + 512
    var j = Int(floor(p.y / cell)) + 512
    var k = Int(floor(p.z / cell)) + 512
    return (i * 1024 + j) * 1024 + k


def _locks(
    mut m: SdfModel,
    t: Traits,
    fleece: List[Int],
    groups: List[Bool],
    wf: Float64,
    merino: Bool,
) raises:
    # A Poisson-disc scatter of staple bundles over the fleece surface.
    var R = AnimalRandom(9127 + Int(t.get("coatSeed", 0.0)), 1, 0)
    var rl = _lock_radius(wf, merino)
    var spacing = rl * 1.55
    var segs = _ear_segments()
    var wts = List[Float64]()
    var wsum = 0.0
    # The fleece is the wool's solids: a sheep with locks has some.
    for i in fleece:
        ref q = m.prims[i]
        var w = (
            q.r.x * q.r.y + q.r.y * q.r.z + q.r.x * q.r.z
        ) if q.kind == ELLIPSOID else 0.02
        wts.append(w)
        wsum += w
    var tries = Int(
        floor(min(16000.0, 10.0 * wsum * 4.0 / (spacing * spacing)) + 0.5)
    )
    var grid = Dict[Int, List[Int]]()
    var pts = List[V3]()
    var owners = List[Int]()
    var normals = List[V3]()
    # Thousands of tries: the fleece's area over a lock's. A try's draws
    # do not depend on its projection, so every start is drawn first, in
    # order: the stream and each result are as if drawn and projected in
    # turn.
    var starts = List[V3](capacity=tries)
    for _ in range(tries):
        var x = R.next() * wsum
        var pi_ = 0
        while pi_ < len(fleece) - 1 and x > wts[pi_]:
            x -= wts[pi_]
            pi_ += 1
        ref pr = m.prims[fleece[pi_]]
        var p: V3
        if pr.kind == ELLIPSOID:
            var ux = R.next() * 2.0 - 1.0
            var uy = R.next() * 2.0 - 1.0
            var uz = R.next() * 2.0 - 1.0
            var un = normalize(V3(ux, uy, uz))
            p = (
                pr.c
                + pr.ax * (un.x * pr.r.x)
                + pr.ay * (un.y * pr.r.y)
                + pr.az * (un.z * pr.r.z)
            )
        else:
            var tt = R.next()
            var jx = (R.next() - 0.5) * 0.05
            var jy = (R.next() - 0.5) * 0.05
            var jz = (R.next() - 0.5) * 0.05
            p = pr.c + (pr.b - pr.c) * tt + V3(jx, jy, jz)
        starts.append(p)
    # Each projection onto the fleece is independent: share them out.
    var projected = List[V3](length=tries, fill=V3(0.0, 0.0, 0.0))
    var landed = List[Bool](length=tries, fill=False)
    var tasks = max(1, min(num_logical_cores(), tries))
    var group = TaskGroup()
    for task in range(tasks):  # pragma: no branch
        group.create_task(
            _project_task(
                Pointer(to=m).unsafe_origin_cast[MutAnyOrigin](),
                Pointer(to=fleece).unsafe_origin_cast[ImmutAnyOrigin](),
                Pointer(to=starts).unsafe_origin_cast[MutAnyOrigin](),
                projected.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                landed.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                task * tries // tasks,
                (task + 1) * tries // tasks,
            )
        )
    group.wait()
    _ = len(starts)
    for attempt in range(tries):
        if not landed[attempt]:
            continue
        var p = projected[attempt]
        if _neck_s(p, segs) > -0.03:
            continue
        if p.y < 0.1:
            continue
        var near = False
        var i0 = Int(floor(p.x / spacing))
        var j0 = Int(floor(p.y / spacing))
        var k0 = Int(floor(p.z / spacing))
        for di in range(-1, 2):  # pragma: no branch
            for dj in range(-1, 2):  # pragma: no branch
                for dk in range(-1, 2):  # pragma: no branch
                    var key = (
                        (i0 + di + 512) * 1024 + (j0 + dj + 512)
                    ) * 1024 + (k0 + dk + 512)
                    if key in grid:
                        # A cell's list holds the lock that made it.
                        for q in grid[key]:  # pragma: no branch
                            if length(pts[q] - p) < spacing:
                                near = True
        if near:
            continue
        var kk = _cell_key(p, spacing)
        var lst = grid.pop(kk, List[Int]())
        lst.append(len(pts))
        grid[kk] = lst^
        pts.append(p)
        var best = 0
        var bd = 1e9
        for n in range(len(fleece)):  # pragma: no branch
            var d = m.distance(fleece[n], p)
            if d < bd:
                bd = d
                best = n
        owners.append(best)
        normals.append(_fgrad(m, fleece, p))
    for i in range(len(pts)):
        var n = normals[i]
        var p = pts[i]
        var fall = _staple_fall(n, p)
        var r = (
            rl
            * (0.8 + 0.4 * R.next())
            * (0.35 + 0.65 * smoothstep(-0.03, -0.1, _neck_s(p, segs)))
        )
        var c = p - n * (r * (0.82 + 0.08 * R.next()))
        var owner = fleece[owners[i]]
        var on_leg = groups[owners[i]]
        var bone = m.prims[owner].bone
        _ = m.ell(
            "lockleg" if on_leg else "lock",
            bone,
            c,
            V3(r, r * 0.9, r * (1.3 + 0.35 * R.next())),
            axis=fall,
            up=n,
            k=0.01 + 0.3 * r,
        )


def _hoof(mut m: SdfModel, bone: BoneId, c: V3, toe_j: V3, w: Float64) raises:
    # Two claws with a cleft between them, heel bulbs behind, flat on the
    # ground.
    var zc = (c.z + toe_j.z) * 0.5
    for k in [1.0, -1.0]:  # pragma: no branch
        var x = c.x + 0.0102 * k * w
        var top = V3(x, c.y + 0.008, c.z - 0.004)
        var toe = V3(x - 0.002 * k, 0.006, toe_j.z - 0.004)
        var heel = V3(x, 0.008, c.z - 0.015)
        _ = m.cone("hoof", bone, top, toe, 0.0112 * w, 0.0052 * w, k=0.006)
        _ = m.cone(
            "hoof",
            bone,
            heel,
            V3(toe.x, 0.006, zc + 0.004),
            0.0108 * w,
            0.0088 * w,
            k=0.008,
        )
        _ = m.sphere(
            "heelbulb", bone, V3(x, 0.013, c.z - 0.019), 0.0102 * w, k=0.008
        )
    _ = m.cone(
        "coronet",
        bone,
        c + V3(0, 0.012, -0.01),
        c + V3(0, 0.006, 0.008),
        0.0165 * w,
        0.0165 * w,
        k=0.008,
    )
    _ = m.ell(
        "cleft",
        bone,
        V3(c.x, 0.006, zc + 0.012),
        V3(0.0022, 0.02, 0.028),
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


def sheep_look(t: Traits) -> EyeLook:
    """Return the sheep's eye: a horizontal bar pupil in an amber, darker
    amber-brown or pale golden iris; a lamb's is pale golden.

    Args:
        t: The individual. Its coat seed picks the iris.

    Returns:
        The look.
    """
    var s = Float64(Int(t.get("coatSeed", 0.0)) % 100) / 100.0
    var inner = 0x9C7A34
    var mid = 0xB8913F
    var outer = 0x5E4418
    var pale = t.juvenile() > 0.0 or s >= 0.9
    if pale:
        inner = 0xA88A48
        mid = 0xC8A85A
        outer = 0x6A5020
    elif s >= 0.6:
        inner = 0x6E5020
        mid = 0x8A6A30
        outer = 0x3E2A10
    return EyeLook(
        srgb(inner), srgb(mid), srgb(outer), V3(0.45, 0.38, 0.32), 0.4, -2.6
    )


def _swatches() -> List[String]:
    return [
        String("tip"),
        "clean",
        "crevice",
        "dust",
        "stain",
        "hair",
        "hairShade",
        "muzzle",
        "skin",
        "nose",
        "hoof",
        "earIn",
        "lid",
    ]


def _coat_hexes(coat: Int) -> List[Int]:
    if coat == C_SUFFOLK:
        return [
            0xE9E0CB,
            0xF5F0E4,
            0xA29479,
            0xCDBFA5,
            0xD5C39E,
            0x4E4A4B,
            0x3C3839,
            0x534D4C,
            0x2A2626,
            0x1A1818,
            0x2A2725,
            0x2E2A2A,
            0x4A4542,
        ]
    if coat == C_MERINO:
        return [
            0xD8CBAD,
            0xF0E9D7,
            0x9C8F7A,
            0xC4B89F,
            0xCDBD98,
            0xEBE8E2,
            0xD6D1C8,
            0xE6D2CC,
            0xE8B4A8,
            0xC99A92,
            0xC0AD92,
            0xE8B0A4,
            0xE0C8C0,
        ]
    if coat == C_BLACK:
        return [
            0x5E4C3E,
            0x2F2723,
            0x211A16,
            0x5E4C3E,
            0x4A3C31,
            0x463C3A,
            0x332B29,
            0x4E4440,
            0x2A2424,
            0x1C1817,
            0x2A2624,
            0x3A302C,
            0x3E3532,
        ]
    if coat == C_BROWN:
        return [
            0x7E654C,
            0x4A3A2E,
            0x30251D,
            0x7A624A,
            0x5C4838,
            0x4A3A30,
            0x3A2E26,
            0x55463C,
            0x3A3030,
            0x2A2222,
            0x302A26,
            0x4A3A34,
            0x5A4A40,
        ]
    if coat == C_TEXEL:
        return [
            0xC9AB80,
            0xE7DBC4,
            0x8F7352,
            0xA88A64,
            0xA98A60,
            0xE8E6E2,
            0xD2CEC6,
            0xDCD0CC,
            0xE0A698,
            0x2A2424,
            0x9C8A74,
            0xE0A698,
            0xD8C4BF,
        ]
    return [
        0xDCCDAE,
        0xEEE7D5,
        0xA39886,
        0xCBC1AD,
        0xD3C6A6,
        0xF0EFEC,
        0xDEDBD5,
        0xDCCFCA,
        0xCFB6B0,
        0xA88C8A,
        0x9C8A74,
        0xDCACA2,
        0xD8C4BF,
    ]


def _black_face(coat: Int) -> Bool:
    return coat == C_SUFFOLK or coat == C_BLACK or coat == C_BROWN


def sheep_palette(t: Traits) raises -> Palette:
    """Return one sheep's palette: its coat, shaded.

    Three in four white-faced sheep have a dark, pigmented nose, picked
    by the coat seed as the original picks it.

    Args:
        t: The individual.

    Returns:
        The palette, in linear light.

    Raises:
        Error: If the palette tables differ in length.
    """
    var coat = Int(t.get("coat", 0.0))
    var hexes = _coat_hexes(coat)
    var dark_nose = (imul32(Int(t.get("coatSeed", 0.0)), 0x9E3779B1) >> 28) % 4
    var white_dark_nose = coat == C_WHITE and dark_nose != 0
    if white_dark_nose:
        hexes[9] = 0x5A5251
        hexes[7] = 0xD2CAC6
    var names = _swatches()
    var base = palette_of(names, hexes)
    var k = t.get("coatShade", 0.0)
    var l = t.get("coatLightness", 0.0)
    var out = Palette()
    for name in names:  # pragma: no branch
        var c = base.get(name)
        out.set(
            name,
            V3(
                c.x * (1.0 + 0.05 * k + l),
                c.y * (1.0 + l),
                c.z * (1.0 - 0.06 * k + l),
            ),
        )
    out.set("horn", srgb(Int(t.get("hornColor", 0.0))))
    out.set("hornDark", srgb(0x6E5A42))
    return out^


def _wool_tag(tag: String) -> Bool:
    return (
        tag == "fleece"
        or tag == "woolneck"
        or tag == "woolarm"
        or tag == "woolthigh"
        or tag == "woolbelly"
        or tag == "wooltail"
        or tag == "woolpoll"
        or tag == "woolcheek"
        or tag == "lock"
        or tag == "lockleg"
        or tag == "woolleg"
        or tag == "fold"
    )


def _horn_t(t: Traits, p: V3) -> Float64:
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


def _face_flow(h: V3) -> V3:
    # The face's hair flow: out from the forehead whorl, down to the nose.
    var f = _frame()
    var rel = V3(h.x, (h.y - 0.03) * 0.4, h.z + 0.02 + 0.05)
    var d = normalize(f.hy * (rel.y - 0.03) + f.hz * rel.z + V3(rel.x, 0, 0))
    if h.z < -0.05:
        d = normalize(d + V3(0, -0.6, -0.8))
    return d


def sheep_paint(
    pal: Palette, t: Traits, tag: String, bone: String, s: CoatSample
) -> Paint:
    """Paint one vertex of a sheep.

    The fleece: clean wool inside, weathered tips on the lock crests,
    darker crevices between locks, a dusty backline and a stained britch
    and belly. The clean short-haired face, ears and legs: white, or
    charcoal in the Suffolk and the black morph. Pink skin under white
    hair at the nose, lips and inner ears; ridged keratin horns; striped
    or dark cloven hooves.

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
    var black = _black_face(coat)
    var lamb = t.juvenile() > 0.0
    var f = _frame()
    var h = f.local(p)
    if s.part == HORN:
        var bt = _horn_t(t, p)
        var hc = mix3(
            pal.get("hornDark"), pal.get("horn"), smoothstep(0.0, 0.35, bt)
        )
        hc = mix3(hc, pal.get("horn") * 1.12, smoothstep(0.75, 1.0, bt) * 0.5)
        var hlen = t.get("hornTurns", 1.0) * 0.5 * bt
        var ring = 0.5 + 0.5 * sin(hlen * 2.0 * pi / 0.012)
        hc = hc * (1.0 - 0.14 * ring * (1.0 - smoothstep(0.8, 1.0, bt)))
        hc = hc * (
            0.9 + 0.2 * vnoise3(V3(p.x * 300.0, p.y * 60.0, p.z * 300.0))
        )
        return Paint(hc, KERATIN)
    var region = 0
    if s.part == JAW:
        region = 6
    elif bone.startswith("ear"):
        region = 5
    elif bone.startswith("tail"):
        region = 4
    elif bone == "head":
        region = 2
    elif bone == "neck1" or bone == "neck2":
        region = 1
    var legness = 0.0
    if is_limb(bone):
        var upper = (
            bone.startswith("scapula")
            or bone.startswith("humerus")
            or bone.startswith("femur")
        )
        legness = smoothstep(0.5, 0.36, p.y) if upper else 1.0
    var cv = fbm3(p * 6.0, 3) - 0.5
    var c: V3
    var surface = FUR
    # How woolly, and where on a lock: crest 1, crevice 0.
    var wool = 0.0
    var crest = 0.5
    var fleece_on = t.get("wool", 0.0) > 0.02
    var rl = _lock_radius(t.get("wool", 0.0), t.variant == MERINO)
    var woolly = _wool_tag(tag)
    if region <= 4 and region != 2:
        if fleece_on:
            if woolly:
                wool = 1.0
                var is_lock = tag == "lock" or tag == "lockleg"
                crest = smoothstep(
                    -0.2, 0.9, s.local.y / (0.9 * rl)
                ) if is_lock else 0.3
        else:
            # No region is 3, so the body, the neck and the tail are left.
            var knee_y = 0.3 if is_front_limb(bone) else 0.26
            wool = 1.0 - legness * smoothstep(knee_y + 0.03, knee_y - 0.03, p.y)
            crest = 0.5 + (fbm3(p * 40.0, 2) - 0.5)
    if region == 2 and woolly:
        wool = 1.0
        crest = 0.4 + 0.4 * (fbm3(p * 40.0, 2) - 0.5)
    # The face's edge: the wool starts behind the ears and the jaw.
    var edge = not black and (region == 1 or region == 2)
    if edge:
        var rag = 0.006 * (vnoise3(p * 120.0) - 0.5)
        var y_jaw = -0.14 + 0.387 * (h.z + 0.03)
        var wl = max(
            smoothstep(-0.061, -0.071, h.z + rag),
            smoothstep(-0.006, -0.016, h.y - y_jaw + rag),
        )
        # On the neck and the head `wool` is none or full, and `wl` is one at
        # most, so only bare skin takes the edge's wool.
        if wl > wool:
            crest = 0.5 + (fbm3(p * 40.0, 2) - 0.5)
            wool = wl
    if region <= 1 or region == 4:
        c = mix3(
            pal.get("hair"),
            pal.get("hairShade"),
            smoothstep(0.2, -0.6, n.y) * 0.6,
        )
        # The neck is no limb: its legness is zero, so it shows clean.
        if fleece_on and region == 1:
            c = pal.get("clean")
        var bag = tag == "udder" or tag == "teat"
        if bag:
            var skin = mix3(
                pal.get("skin"), V3(0.1, 0.08, 0.08), 0.3
            ) if black else pal.get("skin")
            return Paint(skin, SKIN)
        if tag == "scrotum":
            c = mix3(c, pal.get("skin"), 0.25)
        var hoofish = tag == "hoof" or tag == "heelbulb" or tag == "dewclaw"
        if hoofish:
            var cz = 0.258 if bone.startswith("f") else -0.343
            var below = p.y < 0.029 + 0.006 + 0.35 * (p.z - cz)
            if tag == "dewclaw" or below:
                var hc = pal.get("hoof")
                if not black:
                    var stripe = smoothstep(
                        0.3, 0.7, vnoise3(V3(p.x * 300.0, 3.1, p.z * 90.0))
                    )
                    hc = mix3(
                        hc,
                        V3(0.06, 0.05, 0.045),
                        stripe * 0.7 * t.get("hoofStripe", 0.5),
                    )
                if tag == "heelbulb":
                    hc = mix3(hc, V3(0.1, 0.08, 0.07), 0.4)
                return Paint(hc, KERATIN)
    elif region == 5:
        c = pal.get("hair")
        var sd = 1.0 if p.x >= 0.0 else -1.0
        var horned = _horned(t)
        var eb = _hl(EAR_BASE_HORNED if horned else EAR_BASE)
        var tip = _hl(
            _ear_tip(
                Int(t.get("ear", 0.0)),
                t.get("earLift", 0.5),
                horned,
                EAR_BASE_HORNED if horned else EAR_BASE,
            )
        )
        var up = normalize(tip - eb)
        up = V3(up.x * sd, up.y, up.z)
        var facing = _ear_facing(Int(t.get("ear", 0.0)), up, sd)
        var front = dot(n, facing)
        var cup = smoothstep(-0.3, 0.0, front) if tag == "earinner" else 0.0
        var inner = max(0.2 * smoothstep(0.35, 0.8, front), cup)
        c = mix3(c, pal.get("earIn"), 0.55 * inner)
    else:
        # The head and the jaw: short, fine, matte hair.
        c = mix3(
            pal.get("hair"),
            pal.get("hairShade"),
            smoothstep(0.1, -0.7, dot(n, f.hy)) * 0.5,
        )
        var muz = smoothstep(0.12, 0.175, h.z)
        c = mix3(c, pal.get("muzzle"), muz * 0.7)
        var e = sheep_eye(t)
        var ef = eye_frame_of(e, HEAD_O, 1.0 if p.x >= 0.0 else -1.0)
        var eye_d = length(p - ef.c)
        c = mix3(c, pal.get("muzzle"), smoothstep(0.024, 0.012, eye_d) * 0.2)
        var tn = vnoise3(p * 160.0) - 0.5
        c = c * (1.0 + 0.16 * tn + 0.08 * (fbm3(p * 30.0, 2) - 0.5))
        # Streaks drawn out along the hair flow: short hair, not rubber.
        var flow = _face_flow(h)
        var al = dot(p, flow)
        var q = p - flow * (al * 0.85)
        var st = vnoise3(q * 230.0 + V3(5.0, 0.0, 9.0)) - 0.5
        c = c * (1.0 + (0.5 if black else 0.22) * st)
        if not black:
            c = c * (
                1.0
                - 0.1
                * smoothstep(0.55, 0.8, fbm3(p * 22.0 + V3(3.0, 0.0, 1.0), 2))
            )
        # The lids: a thin dark margin and a pale rim of lid skin round it.
        if eye_d < 0.019:
            var de = lid_distance(e, ef, p)
            var on_lid = smoothstep(0.0205, 0.0178, eye_d)
            if de < 0.001:
                return Paint(V3(0.03, 0.025, 0.022), SKIN)
            if de < 0.005:
                c = mix3(
                    c, pal.get("lid"), smoothstep(0.005, 0.0025, de) * on_lid
                )
                if de < 0.0024:
                    c = c * 0.6
        var pale_nose = (
            pal.get("nose").x + pal.get("nose").y + pal.get("nose").z > 0.45
        )
        var nose = pal.get("nose")
        if tag == "nostril":
            c = V3(
                nose.x * 0.36, nose.y * 0.22, nose.z * 0.26
            ) if pale_nose else nose * (0.4 if black else 0.28)
            return Paint(c, SKIN)
        # The philtrum: a fine line from between the nostrils to the lip.
        var pl = (
            smoothstep(0.0012, 0.0004, abs(h.x))
            * smoothstep(-0.026, -0.03, h.y)
            * smoothstep(0.19, 0.196, h.z)
            * smoothstep(0.1, 0.4, dot(n, f.hz))
        )
        if tag == "philtrum":
            pl = 1.0
        c = mix3(c, nose * (0.75 if pale_nose else 0.7), pl * 0.85)
        # The small bare nose pad between the slit nostrils.
        var fwd_n = smoothstep(0.15, 0.5, dot(n, f.hz)) * smoothstep(
            0.17, 0.182, h.z
        )
        var dpad = sqrt((h.x / 0.021) ** 2 + ((h.y + 0.017) / 0.014) ** 2)
        var phil = (
            smoothstep(0.006, 0.003, abs(h.x))
            * smoothstep(-0.04, -0.033, h.y)
            * smoothstep(-0.012, -0.02, h.y)
        )
        var mott = vnoise3(p * 260.0)
        var pad = fwd_n * max(smoothstep(1.2 + 0.25 * mott, 0.7, dpad), phil)
        c = mix3(c, nose, pad)
        if not black:
            c = mix3(
                c,
                mix3(nose, c, 0.5),
                muz
                * smoothstep(1.9, 1.1, dpad)
                * smoothstep(0.35, 0.75, mott)
                * 0.5
                * (1.0 - pad),
            )
        # The lips meet in a dark line.
        var lip_col = pal.get("muzzle") * 0.7 if black else mix3(
            pal.get("muzzle"),
            mix3(pal.get("skin"), nose, 0.3),
            0.3,
        )
        var upper_margin = (
            region == 2 and h.z > 0.135 and h.y < -0.047 and h.y > -0.06
        )
        var lower_margin = region == 6 and h.y > -0.058 and h.z > 0.14
        if upper_margin or lower_margin:
            c = mix3(lip_col, V3(0.04, 0.03, 0.03), 0.5)
        if tag == "preorbital":
            c = c * (0.8 if black else 0.75)
        # A black face: the forms that face the sky catch its light.
        if black:
            var sky = smoothstep(
                -0.2, 0.8, dot(n, f.hy) * 0.8 + dot(n, f.hz) * 0.35
            )
            c = c * mix(1.0 + 0.6 * sky, 1.0, smoothstep(0.165, 0.185, h.z))
    # The fleece.
    if wool > 0.01:
        var up = clamp(n.y, -1.0, 1.0)
        var wc = mix3(
            mix3(pal.get("crevice"), pal.get("clean"), 0.62),
            pal.get("clean"),
            smoothstep(0.0, 0.45, crest),
        )
        var dark_fleece = coat == C_BLACK or coat == C_BROWN
        wc = mix3(
            wc,
            pal.get("tip"),
            smoothstep(0.3, 1.0, crest) * (0.35 if dark_fleece else 0.55),
        )
        wc = mix3(
            wc,
            pal.get("dust"),
            smoothstep(0.6, 0.95, up) * 0.22 * smoothstep(0.2, 0.8, crest),
        )
        var low = smoothstep(0.34, 0.2, p.y) * (1.0 - legness * 0.5)
        var britch = smoothstep(-0.35, -0.5, p.z) * smoothstep(0.55, 0.35, p.y)
        wc = mix3(wc, pal.get("stain"), max(low, britch) * 0.3)
        var sn = vnoise3(p * 45.0) - 0.5
        wc = V3(
            wc.x * (1.0 + 0.035 * cv + 0.05 * sn),
            wc.y * (1.0 + 0.03 * cv + 0.05 * sn),
            wc.z * (1.0 + 0.025 * cv + 0.045 * sn),
        )
        # The crimp: a fine, tight curl over the staple tips.
        var crimp = vnoise3(p * 520.0) - 0.5
        wc = wc * (1.0 + 0.12 * crimp)
        c = mix3(c, wc, wool)
    elif region <= 1:
        var tn = vnoise3(p * 160.0) - 0.5
        c = V3(
            c.x * (1.0 + 0.08 * cv + 0.14 * tn),
            c.y * (1.0 + 0.07 * cv + 0.14 * tn),
            c.z * (1.0 + 0.06 * cv + 0.14 * tn),
        )
    _ = lamb
    return Paint(c, surface)
