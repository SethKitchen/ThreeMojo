# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The domestic cat, Felis catus: procedural-animals' `species/cat/`.

A small, stocky digitigrade cat with a big round head, huge eyes with
vertical slit pupils, tall ears and a long even tail. The reference
adult shorthair stands 0.245 m at the withers. Coats are mackerel and
classic tabby, ginger, black, tuxedo, calico and gray (blue), drawn from
their own hashed stream; about one cat in six is longhaired. The
whiskers of the original are lines, not solids, and are left out.
"""

from extensions.animals.coat import (
    FUR,
    NOSE,
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
    eye_frame_of,
    is_limb,
    is_front_limb,
    mirrored_blob,
    hashed_stream,
)
from extensions.animals.noise import fbm3, vnoise3
from extensions.animals.options import (
    FEMALE,
    Sex,
    MALE,
    AnimalOptions,
    AnimalRandom,
)
from extensions.animals.rig import Rig, quadruped_bones, tail_chain
from extensions.sdf.field import SdfModel
from extensions.animals.traits import Traits, pick_age, pick_variant
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
from std.math import atan2, cos, exp, pi, sin, sqrt

comptime TAIL_SEGS = 10
# The head's origin: between the eyes, at eye level, just behind them.
comptime HEAD_O = V3(0.0, 0.238, 0.184)
# The finest cell, at the `HERO` tier: the head's cell in the original.
comptime CELL = 0.00102

# The coats, in procedural-animals' order.
comptime MACKEREL = 0
comptime CLASSIC = 1
comptime GINGER = 2
comptime BLACK = 3
comptime TUXEDO = 4
comptime CALICO = 5
comptime GRAY = 6

# The iris colors.
comptime GREEN = 0
comptime HAZEL = 1
comptime GOLD = 2
comptime COPPER = 3
comptime KITTEN = 5
comptime AQUA = 6
comptime DEEP_COPPER = 7

# The tail's root.
comptime TAIL_BASE = V3(0.0, 0.188, -0.172)


def cat_variant_names() -> List[String]:
    """Return the cat's coats.

    Returns:
        Mackerel, classic, ginger, black, tuxedo, calico and gray.
    """
    return [
        String("mackerel"),
        "classic",
        "ginger",
        "black",
        "tuxedo",
        "calico",
        "gray",
    ]


def _hl(v: V3) -> V3:
    return HEAD_O + v


def _mm(x: Float64, y: Float64, z: Float64) -> V3:
    # A head-local point given in millimeters.
    return HEAD_O + V3(x, y, z) * 0.001


def _eye_table(variant: Int) -> List[Float64]:
    # The iris colors' shares by coat: green, hazel, gold, copper.
    if variant == GINGER:
        return [0.0, 0.15, 0.55, 0.3]
    if variant == BLACK:
        return [0.25, 0.0, 0.45, 0.3]
    if variant == TUXEDO:
        return [0.4, 0.2, 0.4, 0.0]
    if variant == CALICO:
        return [0.35, 0.0, 0.45, 0.2]
    if variant == GRAY:
        return [0.0, 0.0, 0.4, 0.6]
    if variant == CLASSIC:
        return [0.4, 0.35, 0.25, 0.0]
    return [0.45, 0.35, 0.2, 0.0]


def _eye_order(variant: Int) -> List[Int]:
    # The order the original lists each coat's iris colors in.
    if variant == GINGER:
        return [GOLD, COPPER, HAZEL]
    if variant == BLACK:
        return [GOLD, COPPER, GREEN]
    if variant == TUXEDO:
        return [GOLD, GREEN, HAZEL]
    if variant == CALICO:
        return [GOLD, GREEN, COPPER]
    if variant == GRAY:
        return [COPPER, GOLD]
    return [GREEN, HAZEL, GOLD]


def cat_traits(mut r: AnimalRandom, options: AnimalOptions) raises -> Traits:
    """Draw one cat: procedural-animals' `variation`.

    Ginger cats are mostly male and calicos female. Toms are 10 to 25 %
    heavier with broad heads and jowls; the blue is mostly the cobby
    British type. Kittens are about 0.55 size with a big head and ears,
    short legs and tail, big paws and blue-gray eyes.

    Args:
        r: The individual's stream.
        options: The caller's sex, age and coat.

    Returns:
        The traits.

    Raises:
        Error: If the requested coat is not one of the seven.
    """
    var m = hashed_stream(options.seed, 0x2C1B3C6D, 0x297A2D39, 0x1B873593)
    for _ in range(3):  # pragma: no branch
        _ = m.next()
    var weights: List[Float64] = [0.22, 0.12, 0.14, 0.14, 0.14, 0.11, 0.13]
    var variant = pick_variant(options.variant.value, weights, m.next())
    var sex_r = r.next()
    var sex: Sex
    if options.sex == MALE or options.sex == FEMALE:
        sex = options.sex
    elif variant == CALICO:
        sex = FEMALE
    elif variant == GINGER:
        sex = MALE if sex_r < 0.8 else FEMALE
    else:
        sex = MALE if sex_r < 0.5 else FEMALE
    var t = Traits(sex, pick_age(options.age), variant)
    var juv = t.juvenile()
    var male = 1.0 if t.male() else 0.0
    var stocky = variant == GRAY
    var longhair = m.next() < 0.18
    var v = hashed_stream(options.seed, 0x5BD1E995, 0x27D4EB2D, 0x165667B1)
    for _ in range(3):  # pragma: no branch
        _ = v.next()
    var vv = List[Float64]()
    for _ in range(10):  # pragma: no branch
        vv.append(v.next())
    var solid = variant == BLACK or variant == GRAY or variant == TUXEDO
    var cob = (0.1 if vv[0] < 0.2 else 0.6 + 0.4 * vv[1]) if stocky else 0.0
    var size = (
        (1.04 if male > 0.0 else 0.955)
        * (1.0 + 0.07 * r.g())
        * (1.0 + 0.035 * cob)
        * (0.56 if juv > 0.0 else 1.0)
    )
    var head = (
        (1.04 if male > 0.0 else 0.985)
        * (1.0 + 0.025 * r.g())
        * (1.28 if juv > 0.0 else 1.0)
        * (1.0 + 0.12 * cob)
    )
    var ear_k = (
        (1.0 + 0.09 * r.g()) * (1.12 if juv > 0.0 else 1.0) * (1.0 - 0.3 * cob)
    )
    var order = _eye_order(variant)
    var shares = _eye_table(variant)
    var eye = order[0]
    var x = m.next()
    var acc = 0.0
    var found = False
    # Every coat lists its iris colors.
    for i in range(len(order)):  # pragma: no branch
        acc += shares[order[i]] if order[i] <= COPPER else 0.0
        var hit = not found and x < acc
        if hit:
            eye = order[i]
            found = True
    var w_r = m.next()
    t.set("size", size)
    t.set("longhair", 1.0 if longhair else 0.0)
    t.set("cob", cob)
    t.set(
        "jowl",
        (1.1 if male > 0.0 else 0.97)
        * (1.0 + 0.1 * cob)
        * (0.92 if juv > 0.0 else 1.0),
    )
    t.set(
        "tail",
        (1.0 + 0.05 * r.g()) * (0.78 if juv > 0.0 else 1.0) * (1.0 - 0.1 * cob),
    )
    t.set("eye", Float64(KITTEN if juv > 0.0 else eye))
    t.set("eyeTone", 2.0 * vv[2] - 1.0)
    t.set("coatWarmth", 0.8 * r.g())
    var l = 0.12 * r.g()
    var dark = variant == BLACK or variant == TUXEDO
    var even = solid or variant == GINGER
    t.set(
        "coatLightness",
        0.2 * vv[3]
        - 0.04 if dark else (0.15 * (2.0 * vv[3] - 1.0) if even else l),
    )
    t.set("coatSeed", Float64(Int(r.next() * 1e6)))
    t.set("stripeP", 1.0 + 0.1 * r.g())
    t.set("stripeW", 1.0 + 0.15 * r.g())
    t.set("stripeC", 0.8 + 0.4 * vv[4])
    t.set(
        "ghost",
        1.3 if juv
        > 0.0 else (0.9 + 0.4 * vv[6] if vv[5] < 0.3 else 0.25 + 0.4 * vv[6]),
    )
    t.set("locketSize", 0.85 + 0.6 * vv[7])
    t.set("limb", 1.0 + 0.12 * cob)
    var classic = False
    if variant == GINGER:
        classic = m.next() < 0.35
    t.set("classic", 1.0 if classic else 0.0)
    var white = 0.0
    if variant == TUXEDO:
        white = 0.3 + 0.3 * w_r
    elif variant == CALICO:
        white = 0.0 if w_r < 0.3 else 0.35 + 0.3 * m.next()
    t.set("white", white)
    t.set("sockF", 0.055 + 0.025 * m.next())
    t.set("sockH", 0.02 + 0.045 * m.next())
    var blaze = 0.0
    if m.next() < 0.4:
        blaze = 0.3 + 0.7 * m.next()
    t.set("blaze", blaze)
    t.set("pinkNose", 1.0 if m.next() < 0.5 else 0.0)
    t.set("tailTip", 1.0 if m.next() < 0.2 else 0.0)
    var locket = False
    if variant == BLACK or variant == GRAY:
        locket = m.next() < 0.35
    t.set("locket", 1.0 if locket else 0.0)
    t.set("minThick", 0.0011)
    t.warps.add(legs_warp(1.0 + 0.05 * r.g() - 0.1 * juv - 0.02 * cob, 0.13))
    t.warps.add(length_warp(0.97 + 0.03 * r.g() - 0.06 * juv, -0.15, 0.08))
    t.warps.add(
        girth_warp(
            1.0 + 0.06 * r.g() + 0.18 * cob + 0.02 * male - 0.03 * juv,
            0.16,
            -0.19,
            0.12,
            0.04,
        )
    )
    t.warps.add(
        scale_about_warp(HEAD_O, head, 0.035, 0.11 if juv > 0.0 else 0.075)
    )
    for s in [1.0, -1.0]:  # pragma: no branch
        t.warps.add(
            scale_about_warp(
                _hl(V3(0.037 * s, 0.041, -0.016)), ear_k, 0.012, 0.03
            )
        )
    if juv > 0.0:
        # Kittens have big paws.
        for paw in [  # pragma: no branch
            V3(0.027, 0.01, 0.053),
            V3(-0.027, 0.01, 0.053),
            V3(0.03, 0.01, -0.161),
            V3(-0.03, 0.01, -0.161),
        ]:
            t.warps.add(scale_about_warp(paw, 1.15, 0.012, 0.028))
    return t^


def cat_eye(t: Traits) -> EyeSpec:
    """Return the cat's left eye: big, facing almost straight ahead, its
    iris filling the fissure.

    Args:
        t: The individual. Every cat has the same eye.

    Returns:
        The eye, head-local.
    """
    _ = t
    return EyeSpec(
        V3(0.0185, 0.0, 0.011),
        0.0105,
        0.0027,
        0.12,
        0.02,
        0.001,
        0.0076,
        0.00185,
        -0.0003,
        9.0 * pi / 180.0,
        0.0063,
        0.0074,
    )


def cat_rig(t: Traits) raises -> Rig:
    """Return the cat's skeleton in bind pose.

    A cat stands on sprung, half-flexed legs: the elbow at the chest
    floor, the heel low, the stifle tucked forward under the flank. The
    tail is carried out behind with a gentle droop and a lifted tip.

    Args:
        t: The individual.

    Returns:
        The rig.

    Raises:
        Error: If a bone names a missing joint.
    """
    var rig = Rig()
    rig.set("nose", _hl(V3(0.0, -0.019, 0.046)))
    rig.set("occiput", _hl(V3(0.0, -0.004, -0.038)))
    rig.set("neckMid", V3(0.0, 0.21, 0.13))
    rig.set("neckBase", V3(0.0, 0.186, 0.102))
    rig.set("chestMid", V3(0.0, 0.19, 0.052))
    rig.set("thoraxRear", V3(0.0, 0.194, -0.012))
    rig.set("lumbarMid", V3(0.0, 0.197, -0.07))
    rig.set("lumbosacral", V3(0.0, 0.195, -0.122))
    rig.set("tailBase", TAIL_BASE)
    rig.set("scapTopL", V3(0.021, 0.221, 0.074))
    rig.set("shoulderL", V3(0.033, 0.166, 0.103))
    rig.set("elbowL", V3(0.03, 0.12, 0.04))
    rig.set("wristL", V3(0.027, 0.037, 0.043))
    rig.set("mcpL", V3(0.027, 0.0125, 0.051))
    rig.set("ftoeL", V3(0.027, 0.005, 0.068))
    rig.set("hipL", V3(0.032, 0.176, -0.134))
    rig.set("kneeL", V3(0.0396, 0.1062, -0.08))
    rig.set("hockL", V3(0.033, 0.058, -0.17))
    rig.set("mtpL", V3(0.03, 0.0125, -0.165))
    rig.set("htoeL", V3(0.03, 0.005, -0.148))
    rig.set("jawHinge", _hl(V3(0.0, -0.019, -0.012)))
    rig.set("jawTip", _hl(V3(0.0, -0.031, 0.03)))
    # The pinna sits on the upper corner of the skull, leaning out.
    rig.set("earBaseL", _hl(V3(0.0275, 0.022, -0.012)))
    rig.set("earTipL", _hl(V3(0.047, 0.061, -0.0195)))
    var tk = t.get("tail")
    var lens = List[Float64]()
    for l in _tail_lens():  # pragma: no branch
        lens.append(l * tk)
    tail_chain(rig, "tailBase", _tail_angles(), lens)
    rig.mirror_joints()
    quadruped_bones(rig, TAIL_SEGS)
    return rig^


def _tail_angles() -> List[Float64]:
    return [-9, -18, -24, -27, -28, -26, -22, -15, -8, 0]


def _tail_lens() -> List[Float64]:
    return [0.033, 0.032, 0.031, 0.03, 0.029, 0.029, 0.028, 0.027, 0.026, 0.025]


def _e3(
    mut m: SdfModel,
    h: BoneId,
    tag: String,
    c: V3,
    r: V3,
    k: Float64,
    axis: V3 = V3(0.0, 0.0, 1.0),
) raises:
    # A head ellipsoid given in head-local millimeters.
    _ = m.ell(tag, h, _mm(c.x, c.y, c.z), r * 0.001, axis=axis, k=k * 0.001)


def _tail_radius(t: Float64, tb: Float64) -> Float64:
    # An even, cylindrical tail, tapering only near the tip.
    var root = 0.0122 - 0.012 * t
    var mid = 0.0104 - 0.0024 * ((t - 0.15) / 0.7)
    var tip = 0.008 - 0.014 * (t - 0.85)
    return tb * (root if t < 0.15 else (mid if t < 0.85 else tip))


@fieldwise_init
struct _EarFrame(ImplicitlyCopyable):
    var base: V3
    var up: V3
    var f: V3
    var across: V3
    var s: Float64
    var h: Float64


def _ear_frame(base: V3, tip: V3, s: Float64) -> _EarFrame:
    # Base, up along the pinna, facing its concave front, and across.
    var up = normalize(tip - base)
    var f = normalize(V3(0.42 * s, 0.05, 1))
    f = normalize(f - up * dot(f, up))
    return _EarFrame(
        base, up, f, normalize(cross(up, f)), s, length(tip - base)
    )


def cat_sculpt(mut m: SdfModel, rig: Rig, t: Traits) raises:
    """Sculpt the cat: procedural-animals' `sculptCat`, primitive for
    primitive.

    A round barrel trunk with a low belly pouch, a short thick neck, a big
    round head with a flat face, puffy whisker pads, huge forward eyes and
    tall thin triangular ears, thick short legs on round paws and a long
    even tail. Longhairs get a sculpted ruff, britches and a plumed tail.

    Args:
        m: The sculpt to add to.
        rig: The cat's rig in bind pose.
        t: The individual.

    Raises:
        Error: If the rig lacks a joint or a bone, or the sculpt refuses
            a primitive.
    """
    var eye = cat_eye(t)
    var lh = t.get("longhair", 0.0) > 0.5

    # TORSO: a round barrel, the chest floor at the elbows.
    _ = m.ell(
        "ribcage",
        rig.bone("spine3"),
        V3(0, 0.169, 0.034),
        V3(0.05, 0.056, 0.074),
        axis=normalize(V3(0, 0.1, -1)),
        k=0,
    )
    var b = rig.bone("chest")
    _ = m.ell(
        "brisket",
        b,
        V3(0, 0.146, 0.082),
        V3(0.031, 0.035, 0.036),
        axis=normalize(V3(0, -0.35, 1)),
        k=0.02,
    )
    _ = m.ell(
        "pectoral", b, V3(0, 0.152, 0.104), V3(0.036, 0.032, 0.025), k=0.017
    )
    _ = m.ell(
        "withers",
        b,
        V3(0, 0.212, 0.07),
        V3(0.022, 0.02, 0.045),
        axis=normalize(V3(0, -0.08, 1)),
        k=0.02,
    )
    _ = m.ell(
        "back",
        rig.bone("spine3"),
        V3(0, 0.213, -0.01),
        V3(0.03, 0.02, 0.058),
        k=0.02,
    )
    _ = m.ell(
        "abdomen",
        rig.bone("spine2"),
        V3(0, 0.163, -0.058),
        V3(0.049, 0.05, 0.07),
        axis=normalize(V3(0, 0.12, -1)),
        k=0.022,
    )
    b = rig.bone("spine1")
    _ = m.ell("loin", b, V3(0, 0.209, -0.085), V3(0.029, 0.02, 0.06), k=0.017)
    _ = m.ell("flank", b, V3(0, 0.168, -0.11), V3(0.042, 0.04, 0.045), k=0.017)
    _ = m.ell(
        "pouch",
        b,
        V3(0, 0.126, -0.098),
        V3(0.027, 0.018, 0.042),
        axis=normalize(V3(0, 0.2, -1)),
        k=0.022,
    )
    b = rig.bone("pelvis")
    _ = m.ell("pelvis", b, V3(0, 0.184, -0.15), V3(0.041, 0.034, 0.045), k=0.02)
    _ = m.ell(
        "croup", b, V3(0, 0.203, -0.146), V3(0.026, 0.017, 0.042), k=0.014
    )
    for s in [1.0, -1.0]:  # pragma: no branch
        _ = m.ell(
            "rump",
            b,
            V3(0.017 * s, 0.168, -0.182),
            V3(0.019, 0.029, 0.021),
            k=0.014,
        )

    # NECK: short, thick, furred.
    var n1 = rig.bone("neck1")
    var n2 = rig.bone("neck2")
    _ = m.cone(
        "neck",
        n1,
        V3(0, 0.178, 0.096),
        V3(0, 0.208, 0.134),
        0.038,
        0.031,
        k=0.02,
    )
    _ = m.cone(
        "neck",
        n2,
        V3(0, 0.208, 0.134),
        _hl(V3(0, -0.008, -0.03)),
        0.031,
        0.027,
        k=0.014,
    )
    _ = m.ell(
        "nape",
        n1,
        V3(0, 0.226, 0.122),
        V3(0.022, 0.012, 0.04),
        axis=normalize(V3(0, 0.3, 1)),
        k=0.014,
    )
    _ = m.ell(
        "throat",
        n1,
        V3(0, 0.172, 0.142),
        V3(0.025, 0.026, 0.03),
        axis=normalize(V3(0, 0.8, 0.6)),
        k=0.017,
    )
    _ = m.ell(
        "throat",
        n2,
        _hl(V3(0, -0.031, -0.022)),
        V3(0.021, 0.013, 0.023),
        k=0.01,
    )
    if lh:
        # The longhair's ruff and the frill under the chin.
        _ = m.ell(
            "ruff",
            n1,
            V3(0, 0.172, 0.126),
            V3(0.037, 0.036, 0.035),
            axis=normalize(V3(0, 0.6, 1)),
            k=0.02,
        )
        _ = m.ell(
            "ruff",
            n2,
            _hl(V3(0, -0.03, -0.028)),
            V3(0.026, 0.017, 0.019),
            k=0.014,
        )

    # HEAD, in head-local millimeters: a round dome, a flat face.
    var h = rig.bone("head")
    var jw = t.get("jowl")
    _e3(m, h, "cranium", V3(0, 7, -19), V3(25, 21.5, 29), 14)
    _e3(m, h, "forehead", V3(0, 12, 3), V3(19, 12, 13.5), 10)
    # The short nose bridge, from the stop to the nose leather.
    _ = m.cone(
        "nasal",
        h,
        _mm(0, -1, 12.5),
        _mm(0, -15.5, 27.5),
        0.007,
        0.0055,
        k=0.007,
    )
    for s in [1.0, -1.0]:  # pragma: no branch
        _e3(m, h, "temple", V3(14 * s, 7, -18), V3(17, 16, 24), 12)
        _e3(m, h, "brow", V3(17 * s, 10, 8.5), V3(11, 5.5, 7.5), 6)
        _e3(m, h, "brow", V3(26 * s, 8, -2), V3(9, 7, 11), 8)
        _e3(m, h, "canthus", V3(26.5 * s, 0.5, 4), V3(8, 9, 10), 8)
        _e3(
            m,
            h,
            "zygomatic",
            V3(25 * s, -5, -4),
            V3(11.5, 8.5, 16),
            10,
            axis=normalize(V3(-0.35 * s, 0, 1)),
        )
        # The cheek: the masseter below the arch, a tom's fat jowls.
        _e3(m, h, "cheek", V3(21 * s * jw, -16, -12), V3(12.5 * jw, 12, 20), 12)
        _e3(m, h, "malar", V3(16 * s, -13, 8.5), V3(11, 8, 8), 8)
        _e3(m, h, "mastoid", V3(19 * s, -12, -31), V3(12, 14, 14), 12)
        # The whisker pads: two round cushions beside the philtrum.
        _e3(m, h, "whisker", V3(8.5 * s, -22.5, 23.5), V3(9.5, 7, 7.5), 5)
        _e3(m, h, "mystacial", V3(13 * s, -22, 13), V3(8, 7, 9), 8)
        _e3(
            m,
            h,
            "lip",
            V3(11 * s, -28.5, 19),
            V3(6.5, 4, 10),
            4,
            axis=normalize(V3(-0.4 * s, -0.1, 1)),
        )
        _e3(
            m,
            h,
            "jowl",
            V3(14 * s, -26, -2),
            V3(9 * jw, 6.5, 14),
            8,
            axis=normalize(V3(-0.38 * s, -0.12, 1)),
        )
        # The full throat below the angle of the jaw.
        var tj = jw - 1.0
        _ = m.ell(
            "throat",
            n2,
            _mm((19 + 20 * tj) * s, -30 - 6 * tj, -17),
            V3(0.0095 + 0.014 * tj, 0.009 + 0.006 * tj, 0.015),
            k=0.012,
        )
        var fk = clamp((jw - 1.0) / 0.19, 0.0, 1.0)
        _ = m.ell(
            "jowlneck",
            n2,
            _mm((19 + 5 * fk) * s, -21, -38),
            V3(0.009 + 0.0035 * fk, 0.014, 0.02),
            k=0.014,
        )
    _e3(m, h, "muzzle", V3(0, -19, 17), V3(15, 10.5, 12), 7)
    _e3(
        m,
        h,
        "nose",
        V3(0, -19, 32.5),
        V3(5.9, 4.3, 3.6),
        3,
        axis=normalize(V3(0, 0.2, 1)),
    )
    _e3(m, h, "philtrum", V3(0, -23.5, 29.5), V3(3.5, 4, 3), 3)
    for s in [1.0, -1.0]:  # pragma: no branch
        # The lids: a thin shell hugging the eyeball, cut open along an
        # almond aperture.
        var ef = eye_frame_of(eye, HEAD_O, s)
        _ = ell_y(
            m,
            "eyelid",
            h,
            ef.c,
            ef.y,
            V3(0.0112, 0.0112, 0.0112),
            lateral=ef.x,
            k=0.0035,
        )
        _ = m.lens(
            "eyesocket",
            h,
            ef.c + ef.y * eye.off,
            ef.x,
            ef.y,
            ef.z,
            eye.big_r + 0.0005,
            eye.d,
            -0.0016,
            0.02,
            k=0.0009,
            carve=True,
        )
        _ = m.sphere(
            "nostril",
            h,
            _mm(2.7 * s, -20.3, 35.3),
            0.0012,
            k=0.0008,
            carve=True,
        )
        # The third eyelid: a pigmented sliver deep in the inner corner.
        _ = m.ell(
            "nictitans",
            h,
            ef.at(-0.0076 * s, -0.0012, 0.0058),
            V3(0.0012, 0.0026, 0.0017),
            axis=ef.z,
            up=ef.y,
            k=0.0005,
        )

    # JAW: a narrow V of two rami meeting at a small tucked chin.
    var jb = rig.bone("jaw")
    _ = m.cone(
        "mandible",
        jb,
        _mm(0, -27, -8),
        _mm(0, -29.6, 17.5),
        0.0047,
        0.0036,
        k=0,
        part=JAW,
    )
    for s in [1.0, -1.0]:  # pragma: no branch
        _ = m.cone(
            "mandible",
            jb,
            _mm(12.5 * s, -23.5, -12),
            _mm(4.5 * s, -29, 18),
            0.004,
            0.003,
            k=0.005,
            part=JAW,
        )
    _ = m.ell(
        "chin",
        jb,
        _mm(0, -29.9, 19),
        V3(0.0046, 0.0031, 0.0042),
        k=0.005,
        part=JAW,
    )
    _ = m.ell(
        "jawfloor",
        jb,
        _mm(0, -29.6, 7),
        V3(0.0145, 0.0037, 0.0135),
        k=0.004,
        part=JAW,
    )

    # EARS: tall triangular pinnae, thin, cupped forward.
    for side in [String("L"), String("R")]:  # pragma: no branch
        var s = 1.0 if side == "L" else -1.0
        var e = _ear_frame(rig.j("earBase" + side), rig.j("earTip" + side), s)
        var eb = rig.bone("ear" + side)
        var hk = e.h
        var w = 0.022
        var outer = 1.0 if dot(e.across, V3(s, 0, 0)) >= 0.0 else -1.0
        var poly: List[Float64] = [
            -w * 0.92 * outer,
            -0.004,
            w * outer,
            -0.004,
            w * 0.55 * outer,
            hk * 0.5,
            w * 0.16 * outer,
            hk * 0.93,
            0.0,
            hk * 1.02,
            -w * 0.14 * outer,
            hk * 0.93,
            -w * 0.5 * outer,
            hk * 0.5,
        ]
        _ = m.fin(
            "ear",
            eb,
            e.base + e.f * -0.0006,
            e.across,
            e.up,
            poly,
            0.0034,
            round=0.0014,
            k=0.004,
            thin=True,
        )
        var eh = hk / 0.0352
        _ = m.ell(
            "earback",
            eb,
            e.base + e.up * (0.009 * eh) + e.f * -0.0035,
            V3(0.0165, 0.013 * eh, 0.0045),
            axis=e.f,
            up=e.up,
            k=0.005,
            thin=True,
        )
        _ = m.ell(
            "earinner",
            eb,
            e.base + e.up * (0.53 * hk) + e.f * 0.0107,
            V3(0.0165, 0.5 * hk, 0.0105),
            axis=e.f,
            up=e.up,
            k=0.0015,
            carve=True,
        )

    # LEGS: thick and short, on round paws.
    var lt = t.get("limb")
    for side in [String("L"), String("R")]:  # pragma: no branch
        var s = 1.0 if side == "L" else -1.0
        _fore_leg(m, rig, side, s, lt)
        _hind_leg(m, rig, side, s, lt, lh)

    # TAIL: even and cylindrical, plumed on a longhair.
    var tb = 1.25 if lh else 1.0
    _ = m.cone(
        "tailroot",
        rig.bone("tail0"),
        V3(0, 0.19, -0.158),
        rig.j("tail1"),
        0.016,
        _tail_radius(0.08, tb),
        k=0.013,
    )
    for i in range(TAIL_SEGS):  # pragma: no branch
        _ = m.cone(
            "tail",
            rig.bone("tail" + String(i)),
            rig.j("tail" + String(i)),
            rig.j("tail" + String(i + 1)),
            _tail_radius(Float64(i) / Float64(TAIL_SEGS), tb),
            _tail_radius(Float64(i + 1) / Float64(TAIL_SEGS), tb),
            k=0,
            thin=i >= TAIL_SEGS - 3,
        )


def _toes() -> List[Float64]:
    return [-0.0105, -0.0036, 0.0036, 0.0105]


def _toes_z() -> List[Float64]:
    return [-0.0038, 0, 0, -0.0038]


def _fore_leg(
    mut m: SdfModel, rig: Rig, side: String, s: Float64, lt: Float64
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
        lerp(sc, sh, 0.5) + on_side(V3(0.003, 0, 0), s),
        sh - sc,
        V3(0.0095, 0.036, 0.022),
        lateral=lat,
        k=0.02,
    )
    _ = m.cone("upperarm", hum, sh, e, 0.0175, 0.0132, k=0.02)
    _ = ell_y(
        m,
        "triceps",
        hum,
        lerp(sh, e, 0.55) + V3(0, 0, -0.01),
        e - sh,
        V3(0.0142, 0.029, 0.0165),
        lateral=lat,
        k=0.017,
    )
    _ = m.sphere("olecranon", rad, e + V3(0, 0.003, -0.009), 0.0072, k=0.007)
    _ = m.cone("forearm", rad, e, w, 0.0126 * lt, 0.0081 * lt, k=0.009)
    _ = ell_y(
        m,
        "forearmmuscle",
        rad,
        lerp(e, w, 0.27) + on_side(V3(0.0015, 0, 0.0015), s),
        w - e,
        V3(0.0124 * lt, 0.026, 0.0134 * lt),
        lateral=lat,
        k=0.01,
    )
    _ = m.sphere("wrist", meta, w + V3(0, 0, -0.0012), 0.0082 * lt, k=0.004)
    _ = m.sphere(
        "carpalpad", meta, w + V3(0, -0.0035, -0.0068), 0.0033, k=0.003
    )
    _ = m.cone("pastern", meta, w, mc, 0.0079 * lt, 0.0078 * lt, k=0.004)
    _ = m.sphere(
        "dewclaw",
        meta,
        lerp(w, mc, 0.3) + on_side(V3(-0.0068, 0, 0.0015), s),
        0.0026,
        k=0.002,
    )
    var dp = normalize(toe - mc)
    _ = ell_y(
        m,
        "paw",
        fpaw,
        mc + dp * 0.0075 + V3(0, -0.0015, 0),
        dp,
        V3(0.0128, 0.0138, 0.0072),
        lateral=lat,
        k=0.005,
    )
    _ = m.sphere("pad", fpaw, mc + V3(0, -0.0068, 0.0028), 0.0054, k=0.003)
    var tx = _toes()
    var tz = _toes_z()
    for i in range(4):  # pragma: no branch
        _ = m.sphere(
            "toe",
            fpaw,
            V3(toe.x + tx[i] * s, 0.0054, toe.z - 0.0042 + tz[i]),
            0.0051,
            k=0.0025,
        )


def _hind_leg(
    mut m: SdfModel, rig: Rig, side: String, s: Float64, lt: Float64, lh: Bool
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
    # Meaty thighs rising into the flank and croup.
    _ = ell_y(
        m,
        "thigh",
        fem,
        lerp(hp, kn, 0.34) + on_side(V3(0.002, 0, -0.012), s),
        kn - hp,
        V3(0.0185, 0.047, 0.037),
        lateral=lat,
        k=0.017,
    )
    _ = m.cone(
        "thighfront",
        fem,
        on_side(V3(0.016, 0.186, -0.098), s),
        kn + on_side(V3(-0.0012, 0.018, 0.0), s),
        0.0138,
        0.009,
        k=0.02,
    )
    _ = m.cone(
        "hamstring",
        fem,
        on_side(V3(0.017, 0.188, -0.186), s),
        lerp(kn, hk, 0.1) + V3(0, 0.006, -0.011),
        0.0158,
        0.0095,
        k=0.013,
    )
    _ = ell_y(
        m,
        "flankfold",
        fem,
        on_side(V3(0.019, 0.14, -0.085), s),
        V3(-0.03, 0.16, 0.1),
        V3(0.0075, 0.028, 0.0135),
        lateral=lat,
        k=0.02,
    )
    _ = m.sphere(
        "stifle",
        tib,
        kn + on_side(V3(0.0007, 0.0027, 0.002), s),
        0.0068,
        k=0.013,
    )
    _ = m.cone(
        "shin",
        tib,
        lerp(kn, hk, 0.06) + on_side(V3(0, 0, 0.0013), s),
        hk,
        0.0095 * lt,
        0.0068 * lt,
        k=0.01,
    )
    _ = ell_y(
        m,
        "calf",
        tib,
        lerp(kn, hk, 0.3) + on_side(V3(0.0007, 0.0035, -0.009), s),
        hk - kn,
        V3(0.0102 * lt, 0.024, 0.0115 * lt),
        lateral=lat,
        k=0.012,
    )
    _ = m.cone(
        "achilles",
        tib,
        lerp(kn, hk, 0.5) + V3(0, 0.0033, -0.0115),
        hk + V3(0, 0.004, -0.0095),
        0.0042,
        0.0038,
        k=0.005,
    )
    _ = m.sphere("calcaneus", mtar, hk + V3(0, 0.004, -0.0085), 0.0052, k=0.004)
    _ = m.sphere("hock", mtar, hk, 0.0072 * lt, k=0.004)
    _ = m.cone("metatarsus", mtar, hk, mt, 0.0071 * lt, 0.007 * lt, k=0.004)
    var dh = normalize(tt - mt)
    _ = ell_y(
        m,
        "paw",
        hpaw,
        mt + dh * 0.007 + V3(0, -0.0015, 0),
        dh,
        V3(0.012, 0.0132, 0.007),
        lateral=lat,
        k=0.005,
    )
    _ = m.sphere("pad", hpaw, mt + V3(0, -0.0068, 0.0026), 0.0051, k=0.003)
    var tx = _toes()
    var tz = _toes_z()
    for i in range(4):  # pragma: no branch
        _ = m.sphere(
            "toe",
            hpaw,
            V3(tt.x + tx[i] * 0.94 * s, 0.0052, tt.z - 0.004 + tz[i]),
            0.0049,
            k=0.0025,
        )
    if lh:
        # The longhair's britches on the back of the thighs.
        _ = ell_y(
            m,
            "britches",
            fem,
            lerp(hp, kn, 0.55) + on_side(V3(0.004, -0.004, -0.027), s),
            kn - hp,
            V3(0.012, 0.03, 0.014),
            lateral=lat,
            k=0.014,
        )


def _iris(eye: Int) -> List[Int]:
    if eye == HAZEL:
        return [0xBFA044, 0xBCB956, 0xE2DD8C, 0x72702E]
    if eye == GOLD:
        return [0xD29C32, 0xD4A236, 0xE8C050, 0x9C7222]
    if eye == COPPER:
        return [0xC2722C, 0xC8742E, 0xE0904A, 0x924C1E]
    if eye == KITTEN:
        return [0x6C8498, 0x8AA2B6, 0xB6C6D4, 0x46586C]
    if eye == AQUA:
        return [0x94A468, 0x7FB09A, 0xB4DCC8, 0x4F7A64]
    if eye == DEEP_COPPER:
        return [0xB0601E, 0xB8621E, 0xD07A36, 0x7A3A14]
    return [0xA6A64C, 0x93BB70, 0xC9E29E, 0x5D7C46]


def _near(eye: Int, warmer: Bool) -> Int:
    # The neighboring iris color an individual's shade leans toward.
    if eye == GREEN:
        return HAZEL if warmer else AQUA
    if eye == HAZEL:
        return GOLD if warmer else GREEN
    if eye == GOLD:
        return COPPER if warmer else HAZEL
    return DEEP_COPPER if warmer else GOLD


def cat_look(t: Traits) -> EyeLook:
    """Return the cat's eye colors: green, hazel, gold or copper with a
    vertical slit pupil, or blue-gray in a kitten.

    Each individual's iris leans toward a neighboring color.

    Args:
        t: The individual.

    Returns:
        The look.
    """
    var eye = Int(t.get("eye", 0.0))
    var base = _iris(eye)
    var tone = t.get("eyeTone", 0.0)
    var c = List[V3]()
    for i in range(4):  # pragma: no branch
        c.append(srgb(base[i]))
    var leans = eye <= COPPER
    if leans:
        var other = _iris(_near(eye, tone > 0.0))
        for i in range(4):  # pragma: no branch
            c[i] = mix3(c[i], srgb(other[i]), 0.45 * abs(tone))
    return EyeLook(c[0], c[1], c[3], V3(0.25, 0.2, 0.16), 0.3, 3.0)


def _swatches() -> List[String]:
    return [
        String("ground"),
        "dorsal",
        "belly",
        "chin",
        "stripe",
        "legGround",
        "white",
        "pad",
        "nose",
        "earInner",
        "nict",
        "orange",
        "orangeDark",
        "black",
        "rust",
    ]


def _hexes(variant: Int, pink: Bool) -> List[Int]:
    # Ground, dorsal, belly, chin, stripe, leg ground, white, pad, nose,
    # ear inner, third eyelid, orange, dark orange, black and rust.
    if variant == GINGER:
        return [
            0xCF8B4C,
            0xC07A3E,
            0xECC79A,
            0xF2DFC4,
            0x9C5028,
            0xD79A5E,
            0xEBE8E2,
            0xC8908A,
            0xC98E88,
            0xE6B0A4,
            0x9C7F7A,
            0xD08A46,
            0xB46E32,
            0x1C1918,
            0x000000,
        ]
    if variant == BLACK:
        return [
            0x28231F,
            0x1F1B19,
            0x2D2825,
            0x2A2522,
            0x100D0C,
            0x28231F,
            0xEBE8E2,
            0x221D1D,
            0x262021,
            0x5A4A4A,
            0x8A7470,
            0xD08A46,
            0xB46E32,
            0x1C1918,
            0x3A2A20,
        ]
    if variant == GRAY:
        return [
            0x7C7E83,
            0x707277,
            0x8A8C91,
            0x8C8E93,
            0x5C5D62,
            0x7F8186,
            0xEBE8E2,
            0x6A6166,
            0x6A6068,
            0x9A8A8E,
            0xB8A8A8,
            0xD08A46,
            0xB46E32,
            0x1C1918,
            0x000000,
        ]
    if variant == TUXEDO:
        return [
            0x1D1A19,
            0x181615,
            0x1F1C1B,
            0x1F1C1B,
            0x100D0C,
            0x1D1A19,
            0xECE9E3,
            0xC8928C if pink else 0x2A2323,
            0xCA918B if pink else 0x262021,
            0x6A5656,
            0x9C7F7A,
            0xD08A46,
            0xB46E32,
            0x1C1918,
            0x33251C,
        ]
    if variant == CALICO:
        return [
            0xEBE8E2,
            0xE6E2DA,
            0xEFECE6,
            0xEFECE6,
            0x1C1918,
            0xEBE8E2,
            0xEBE8E2,
            0xC8928C,
            0xCA918B,
            0xDCAAA0,
            0x9C7F7A,
            0xD08A46,
            0xB46E32,
            0x1C1918,
            0x000000,
        ]
    return [
        0x857A6D,
        0x655A4E,
        0xC4B7A6,
        0xE4DED4,
        0x221B17,
        0x908475,
        0xEBE8E2,
        0x2E2322,
        0xB47268,
        0xBFA196,
        0x9C7F7A,
        0xD08A46,
        0xB46E32,
        0x1C1918,
        0x000000,
    ]


def cat_palette(t: Traits) raises -> Palette:
    """Return one cat's palette: its coat's swatches, warmed and lightened.

    The `look` entry holds the stripes' strength, the agouti strength and
    one for a coat with ghost tabby markings.

    Args:
        t: The individual.

    Returns:
        The palette, in linear light.

    Raises:
        Error: If the palette tables differ in length.
    """
    var v = t.variant
    var names = _swatches()
    var hexes = _hexes(v, t.get("pinkNose", 0.0) > 0.5)
    var k = t.get("coatWarmth", 0.0)
    var l = t.get("coatLightness", 0.0)
    var out = Palette()
    for i in range(len(names)):  # pragma: no branch
        var c = srgb(hexes[i])
        var name = names[i]
        # The coat's own fur takes the individual's warmth and lightness.
        var fur = (
            name == "ground"
            or name == "dorsal"
            or name == "belly"
            or name == "legGround"
            or name == "orange"
            or name == "orangeDark"
        )
        var tone = fur and v != CALICO
        var calico_fur = v == CALICO and name.startswith("orange")
        var stripe = name == "stripe" and v == GINGER
        var chin = name == "chin" and (v == BLACK or v == GRAY or v == TUXEDO)
        var warm = tone or calico_fur or stripe or chin
        if warm:
            c = V3(
                c.x * (1.0 + 0.08 * k + l),
                c.y * (1.0 + 0.02 * k + l),
                c.z * (1.0 - 0.08 * k + l),
            )
        out.set(name, c)
    var tabby = v == MACKEREL or v == CLASSIC
    if tabby:
        out.set("look", V3(1.0, 0.8, 0.0))
    elif v == GINGER:
        out.set("look", V3(0.85, 0.15, 0.0))
    elif v == BLACK:
        out.set("look", V3(0.35, 0.0, 1.0))
    elif v == GRAY:
        out.set("look", V3(0.3, 0.0, 1.0))
    else:
        out.set("look", V3(0.0, 0.0, 0.0))
    return out^


def _tail_at(t: Traits, bone: String, p: V3) -> V3:
    # How far along the tail a point lies, in meters from the root, the
    # tail's length, and the tail's dorsal height direction (y).
    var angles = _tail_angles()
    var lens = _tail_lens()
    var tk = t.get("tail")
    var total = 0.0
    for l in lens:  # pragma: no branch
        total += l * tk
    var seg = 0
    for i in range(TAIL_SEGS):  # pragma: no branch
        if bone == "tail" + String(i):
            seg = i
    var a = TAIL_BASE
    var done = 0.0
    for i in range(seg):
        var ang = angles[i] * pi / 180.0
        a = a + V3(0.0, sin(ang), -cos(ang)) * (lens[i] * tk)
        done += lens[i] * tk
    var ang = angles[seg] * pi / 180.0
    var d = V3(0.0, sin(ang), -cos(ang))
    var u = clamp(dot(p - a, d), 0.0, lens[seg] * tk)
    return V3(done + u, total, cos(ang))


def _axial_points() -> List[V3]:
    return [
        _hl(V3(0.0, -0.019, 0.046)),
        _hl(V3(0.0, -0.004, -0.038)),
        V3(0.0, 0.21, 0.13),
        V3(0.0, 0.186, 0.102),
        V3(0.0, 0.19, 0.052),
        V3(0.0, 0.194, -0.012),
        V3(0.0, 0.197, -0.07),
        V3(0.0, 0.195, -0.122),
        TAIL_BASE,
    ]


@fieldwise_init
struct _Axial(ImplicitlyCopyable):
    # Arc length from the nose, the angle from the dorsal midline (0 on
    # top, pi under the belly), and the arc lengths of the neck base, the
    # chest, the lumbar joint, the lumbosacral joint and the tail base.
    var s: Float64
    var theta: Float64
    var neck_base: Float64
    var chest: Float64
    var lumbar: Float64
    var sacrum: Float64
    var tail: Float64


def _axial(p: V3) -> _Axial:
    var pts = _axial_points()
    var arc = List[Float64]()
    arc.append(0.0)
    for i in range(1, len(pts)):  # pragma: no branch
        arc.append(arc[i - 1] + length(pts[i] - pts[i - 1]))
    var best = 1e9
    var s = 0.0
    var theta = 0.0
    for i in range(len(pts) - 1):  # pragma: no branch
        var a = pts[i]
        var ab = pts[i + 1] - a
        var u = clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0)
        var c = a + ab * u
        var d = length(p - c)
        if d < best:
            best = d
            s = arc[i] + u * length(ab)
            theta = atan2(abs(p.x - c.x), p.y - c.y)
    return _Axial(s, theta, arc[3], arc[4], arc[6], arc[7], arc[8])


struct _Noise(ImplicitlyCopyable):
    # The coat's seeded noise fields.
    var off: Float64

    def __init__(out self, t: Traits):
        var r = AnimalRandom(1337 + Int(t.get("coatSeed", 0.0)), 1, 0)
        self.off = r.next() * 100.0

    def f3(self, p: V3, k: Float64, o: Float64) -> Float64:
        return fbm3(
            V3(
                p.x * k + self.off + o,
                p.y * k - o,
                p.z * k + self.off * 0.5,
            ),
            3,
        )

    def n2(self, a: Float64, b: Float64) -> Float64:
        return vnoise3(V3(a + self.off, b - self.off * 0.7, self.off * 1.3))


def _round(x: Float64) -> Float64:
    return Float64(Int(x + 0.5)) if x >= 0.0 else -Float64(Int(-x + 0.5))


def _dist_line(p: V3, n: V3, pts: List[V3], w: List[Float64]) -> Float64:
    # The distance from a skin point to a polyline with half widths,
    # measured in the skin's tangent plane, negative inside.
    var best = 1e9
    # Its one caller passes six points.
    for i in range(len(pts) - 1):
        var a = pts[i]
        var ab = pts[i + 1] - a
        var u = clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0)
        var d = p - (a + ab * u)
        d = d - n * dot(d, n)
        best = min(best, length(d) - mix(w[i], w[i + 1], u))
    return best


def _line(
    p: V3,
    n: V3,
    s: Float64,
    a: V3,
    b: V3,
    c: V3,
    d: V3,
    e: V3,
    f: V3,
    w: List[Float64],
) -> Float64:
    var pts: List[V3] = [
        _mm(a.x * s, a.y, a.z),
        _mm(b.x * s, b.y, b.z),
        _mm(c.x * s, c.y, c.z),
        _mm(d.x * s, d.y, d.z),
        _mm(e.x * s, e.y, e.z),
        _mm(f.x * s, f.y, f.z),
    ]
    # A line needs a width at each of its points.
    if len(w) < len(pts):
        return 1e9
    var ws = List[Float64]()
    # Six widths at least, checked above.
    for x in w:  # pragma: no branch
        ws.append(x * 0.001)
    return _dist_line(p, n, pts, ws)


def _head_lines(p: V3, n: V3) -> Float64:
    # The tabby's face: the forehead "M" running back over the crown, the
    # bold cheek lines and the line down from the inner eye corner.
    var s = 1.0 if p.x >= HEAD_O.x else -1.0
    var d = _line(
        p,
        n,
        s,
        V3(2.6, 9, 17.5),
        V3(3.2, 17, 12),
        V3(3.6, 23, 3),
        V3(4.2, 27, -10),
        V3(4.8, 27, -25),
        V3(5.2, 22, -40),
        [1.2, 1.6, 1.8, 1.9, 2.0, 1.8],
    )
    d = min(
        d,
        _line(
            p,
            n,
            s,
            V3(7.5, 6, 18),
            V3(9, 12, 15.5),
            V3(10, 19, 9),
            V3(11, 25, -4),
            V3(12, 26, -20),
            V3(12.5, 21, -37),
            [1.1, 1.5, 1.7, 1.8, 1.8, 1.6],
        ),
    )
    d = min(
        d,
        _line(
            p,
            n,
            s,
            V3(12.5, 12, 14.5),
            V3(15, 13, 13),
            V3(18, 14, 11),
            V3(20, 13.5, 9),
            V3(21.5, 13, 7.5),
            V3(23, 12, 6),
            [0.9, 1.0, 1.1, 1.0, 0.8, 0.7],
        ),
    )
    d = min(
        d,
        _line(
            p,
            n,
            s,
            V3(26, 1, 9),
            V3(29, 0.5, 5),
            V3(32, 0, 1),
            V3(37, -4, -10),
            V3(38, -11, -21),
            V3(35, -17, -29),
            [1.3, 1.6, 1.9, 2.1, 1.9, 1.4],
        ),
    )
    d = min(
        d,
        _line(
            p,
            n,
            s,
            V3(22, -11, 12),
            V3(25.5, -13, 8),
            V3(29, -15, 4),
            V3(32, -17, -1.5),
            V3(35, -19, -7),
            V3(36, -24, -17),
            [1.1, 1.4, 1.6, 1.65, 1.7, 1.3],
        ),
    )
    d = min(
        d,
        _line(
            p,
            n,
            s,
            V3(11.5, -4, 19.5),
            V3(11.2, -6.5, 21),
            V3(10.8, -9, 22.5),
            V3(10.4, -11, 23.5),
            V3(10.2, -12, 24),
            V3(10, -13, 24.5),
            [1.0, 0.95, 0.9, 0.75, 0.65, 0.6],
        ),
    )
    d = min(
        d,
        _line(
            p,
            n,
            1.0,
            V3(0, 22, 6),
            V3(0, 25, -2),
            V3(0, 27, -10),
            V3(0, 26, -26),
            V3(0, 24, -34),
            V3(0, 21, -42),
            [0.9, 1.2, 1.5, 1.7, 1.7, 1.6],
        ),
    )
    return d


def cat_paint(
    pal: Palette, t: Traits, tag: String, bone: String, s: CoatSample
) -> Paint:
    """Paint one vertex of a cat.

    Tabbies wear wavy mackerel stripes or the classic bull's-eye and
    butterfly, barred legs, a ringed tail with a dark tip, necklaces and
    the forehead "M". Solid black and blue coats show faint ghost stripes.
    The tuxedo has a white bib, muzzle and socks, the calico white with
    orange and black patches, or a tortoiseshell brindle without white.

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
    var v = t.variant
    var h = p - HEAD_O
    var ax = abs(h.x)
    if tag == "nictitans":
        return Paint(pal.get("nict"), NOSE)
    if tag == "eyesocket":
        return Paint(srgb(0x1A1414), SKIN)
    var head = bone == "head" or bone == "jaw"
    if head:
        # The nose leather: an inverted triangle on the front of the nose.
        var ny_top = -0.015
        var ny_bot = -0.0232
        var nw = 0.0054
        var nh = ny_top - ny_bot
        var d_side = (ax * nh - (h.y - ny_bot) * nw) / sqrt(nh * nh + nw * nw)
        var d_tri = max(d_side, h.y - ny_top + 0.0015 * (ax / nw) ** 2)
        var on_nose = (
            (tag == "nose" or tag == "nostril" or tag == "philtrum")
            and h.z > 0.029
            and n.z > -0.2
            and d_tri < 0.0
        )
        if on_nose:
            return Paint(pal.get("nose"), NOSE)
        # The lip line along the mouth slit.
        var lips = (
            bone == "head"
            and (tag == "lip" or tag == "philtrum" or tag == "whisker")
            and h.y < -0.0285
            and h.z > 0.004
        ) or (bone == "jaw" and h.y > -0.0275 and h.z > 0.006)
        if lips:
            return Paint(srgb(0x2A1E1C), SKIN)
    var pad = (
        (tag == "pad" or tag == "carpalpad" or tag == "toe")
        and n.y < -0.25
        and p.y < 0.012
    )
    if pad:
        return Paint(pal.get("pad"), NOSE)
    var noise = _Noise(t)
    var look = pal.get("look")
    var tabby = v == MACKEREL or v == CLASSIC or v == GINGER
    var ghost = look.z > 0.5
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
        leg = smoothstep(0.15, 0.09, p.y)
    var axl = _axial(p)
    var vt = axl.theta
    var c: V3
    var agouti = look.y
    var vent = 0.0
    var tail_s = 0.0
    var tail_len = 1.0
    if region <= 1:
        if region == 0:
            vent = smoothstep(1.75, 2.45, vt)
            if p.z > 0.07:
                vent = max(
                    vent,
                    smoothstep(0.16, 0.12, p.y)
                    * smoothstep(0.03, 0.012, abs(p.x))
                    * smoothstep(-0.2, 0.4, n.z),
                )
        else:
            vent = smoothstep(1.9, 2.6, vt)
        if leg > 0.0:
            var side = 1.0 if p.x >= 0.0 else -1.0
            var inner = smoothstep(0.1, -0.6, n.x * side)
            var wl = (
                inner * 0.75 * smoothstep(0.04, 0.12, p.y)
                + smoothstep(-0.3, -0.85, n.y) * 0.4
            )
            vent = mix(vent, wl, leg)
        vent = clamp(vent, 0.0, 1.0)
        c = mix3(pal.get("ground"), pal.get("dorsal"), smoothstep(0.9, 0.2, vt))
        c = mix3(c, pal.get("belly"), vent)
        if leg > 0.0:
            var lc = mix3(pal.get("legGround"), pal.get("belly"), vent * 0.8)
            c = mix3(c, lc, leg)
        agouti *= 1.0 - vent * 0.7
    elif region == 4:
        var tf = _tail_at(t, bone, p)
        tail_s = tf.x
        tail_len = tf.y
        vent = smoothstep(0.0, -0.7, n.y) * 0.8
        c = mix3(pal.get("ground"), pal.get("belly"), vent * 0.6)
        c = mix3(c, pal.get("dorsal"), smoothstep(0.3, 0.9, n.y) * 0.5)
    elif region == 5:
        c = _ear(pal, t, p, n)
        agouti = 0.0
    else:
        c = _face(pal, t, p, n, region)
        agouti *= 0.7
    # A small white locket on the chest of some black and blue cats.
    var locket = t.get("locket", 0.0) > 0.5 and region <= 1
    if locket:
        var ls = t.get("locketSize")
        var lk = length(
            V3(
                p.x / (0.015 * ls),
                (p.y - 0.16) / (0.022 * ls),
                (p.z - 0.13) / 0.03,
            )
        ) + 0.35 * (noise.f3(p, 60.0, 4.4) - 0.5)
        var lw = smoothstep(1.0, 0.75, lk) * smoothstep(-0.2, 0.3, n.z)
        c = mix3(c, pal.get("white"), lw)
    # The tabby pattern, or a solid coat's ghost of it.
    var tabby_on = tabby or ghost
    if tabby_on:
        var d = _tabby(t, noise, p, n, region, leg, axl, vent, tail_s, tail_len)
        var pat_i = min(1.0, look.x * t.get("stripeC"))
        if ghost:
            pat_i = min(1.0, look.x * t.get("ghost")) * (
                0.6 + 0.4 * smoothstep(0.4, 0.9, n.y)
            )
        var ink = smoothstep(0.0012, -0.0012, d) * pat_i
        c = mix3(c, pal.get("stripe"), ink)
    if v == TUXEDO or v == CALICO:
        c = _spots(
            pal,
            t,
            noise,
            c,
            p,
            n,
            region,
            leg,
            axl,
            vent,
            tail_s,
            tail_len,
            bone,
        )
    # Low-frequency color variation, and a black coat's rusty cast.
    var cv = fbm3(V3(p.x * 30.0, p.y * 30.0, p.z * 30.0), 3) - 0.5
    var cvh = fbm3(V3(p.x * 12.0 + 5.0, p.y * 12.0, p.z * 12.0), 2) - 0.5
    c = V3(
        c.x * (1.0 + 0.14 * cv + 0.08 * cvh),
        c.y * (1.0 + 0.12 * cv),
        c.z * (1.0 + 0.1 * cv - 0.06 * cvh),
    )
    var rusty = v == BLACK or v == TUXEDO
    if rusty:
        c = mix3(
            c,
            pal.get("rust"),
            clamp(0.25 + 0.5 * cvh, 0.0, 0.5) * smoothstep(0.2, 0.9, n.y) * 0.5,
        )
    # The agouti band: ticked hair, lighter and darker by the strand.
    var tick = vnoise3(V3(p.x * 900.0, p.y * 900.0, p.z * 320.0)) - 0.5
    c = c * (1.0 + 0.5 * agouti * tick)
    return Paint(c, FUR)


def _ear(pal: Palette, t: Traits, p: V3, n: V3) -> V3:
    # The pinna: the back in the coat color, darker toward the tip; the
    # front pink skin through short pale hair, the rim the back's color.
    var s = 1.0 if p.x >= 0.0 else -1.0
    var e = _ear_frame(
        _hl(V3(0.0275 * s, 0.022, -0.012)),
        _hl(V3(0.047 * s, 0.061, -0.0195)),
        s,
    )
    var front = smoothstep(0.05, 0.4, dot(n, e.f))
    var ht = dot(p - e.base, e.up) / e.h
    var u = dot(p - e.base, e.across)
    var hw = 0.022 * (1.0 - 0.8 * clamp(ht, 0.0, 1.0)) + 1e-4
    var edge = abs(u) / hw
    var outer = 1.0 if dot(e.across, V3(s, 0, 0)) >= 0.0 else -1.0
    var medial = smoothstep(0.35, 0.95, -u * outer / hw)
    var back = mix3(
        mix3(pal.get("dorsal"), pal.get("ground"), 0.3),
        pal.get("dorsal"),
        smoothstep(0.5, 1.0, ht) * 0.5,
    )
    var inner = mix3(
        pal.get("earInner"),
        mix3(pal.get("earInner"), pal.get("nose"), 0.3),
        smoothstep(0.65, 0.15, ht) * smoothstep(0.9, 0.3, edge) * 0.7,
    )
    var furnish = medial * smoothstep(0.8, 0.35, ht)
    inner = mix3(inner, pal.get("chin"), 0.12 + 0.45 * furnish)
    var rim = smoothstep(0.8, 1.0, edge) * 0.85
    _ = t
    return mix3(back, mix3(inner, back, rim), front)


def _face(pal: Palette, t: Traits, p: V3, n: V3, region: Int) -> V3:
    # The head and the jaw: a pale muzzle and chin, pale fur round the
    # eyes, a paler cheek below and behind the eye.
    var h = p - HEAD_O
    var c = mix3(
        pal.get("ground"),
        pal.get("dorsal"),
        smoothstep(0.3, 0.9, n.y) * smoothstep(0.0, -0.03, h.z) * 0.5,
    )
    var g1 = mirrored_blob(h, V3(0.009, -0.024, 0.027), V3(0.011, 0.008, 0.012))
    var g2 = mirrored_blob(h, V3(0.0, -0.032, 0.021), V3(0.012, 0.006, 0.012))
    var muzzle = max(g1, g2)
    var e = 0.017 if h.z > -0.004 else 0.022
    var chin_mid = smoothstep(e, e - 0.009, abs(h.x))
    var chin_w = (
        max(
            smoothstep(-0.026, -0.036, h.y) * smoothstep(-0.1, -0.6, n.y),
            0.9 * smoothstep(0.008, 0.017, h.z) if region == 6 else 0.0,
        )
        * chin_mid
    )
    # The pale ring hugging the lid margin.
    var eye = cat_eye(t)
    var d_eye = 1.0
    for s in [1.0, -1.0]:  # pragma: no branch
        var ef = eye_frame_of(eye, HEAD_O, s)
        d_eye = min(d_eye, length(p - ef.c) - 0.0112)
    var tabby = (
        t.variant == MACKEREL or t.variant == CLASSIC or t.variant == GINGER
    )
    var ring = (
        exp(
            -(
                (
                    (d_eye - 0.0015)
                    / (0.0022 + 0.0014 * smoothstep(0.002, -0.006, h.y))
                )
                ** 2
            )
        )
        * 0.26
    )
    c = mix3(
        c,
        pal.get("chin"),
        clamp(
            max(muzzle * 0.9, max(chin_w, ring * (1.0 if tabby else 0.3))),
            0.0,
            1.0,
        ),
    )
    return c


def _tabby(
    t: Traits,
    noise: _Noise,
    p: V3,
    n: V3,
    region: Int,
    leg: Float64,
    axl: _Axial,
    vent_in: Float64,
    tail_s: Float64,
    tail_len: Float64,
) -> Float64:
    # The tabby pattern's signed distance, negative inside a stripe.
    var d = 1.0
    var vt = axl.theta
    var classic = t.variant == CLASSIC or t.get("classic", 0.0) > 0.5
    var p0 = t.get("stripeP") * 0.019
    var wd = 0.0085 * t.get("stripeW")
    var ph_off = (noise.off * 0.617) - Float64(Int(noise.off * 0.617))
    if region <= 1:
        var s = axl.s
        var varc = vt * 0.048
        if not classic:
            # Mackerel: wavy stripes leaning back as they run down,
            # breaking into dashes low on the flank, and a dorsal stripe.
            var wob = 0.9 * (
                noise.f3(V3(s * 1.2, varc, 0.0), 26.0, 1.7) - 0.5
            ) + 0.25 * (noise.n2(s * 90.0, varc * 40.0) - 0.5)
            var ph = (s - axl.neck_base) / p0 + 0.28 * varc / p0 + wob + ph_off
            var k = _round(ph)
            var fi = ph - k
            var ww = wd * (0.8 + 0.5 * noise.n2(k * 3.1, varc * 30.0))
            d = abs(fi) * p0 - ww / 2.0
            var brk = smoothstep(0.045, 0.09, varc) * smoothstep(
                0.4, 0.8, noise.n2(s * 160.0 + k * 7.0, varc * 70.0)
            )
            d += brk * 0.01
            d = min(d, varc - (0.0065 + 0.0025 * noise.n2(s * 60.0, 1.3)))
        else:
            # Classic: three spine lines, the bull's-eye on each flank,
            # the butterfly on the shoulders.
            var spine = min(abs(varc) - 0.0028, abs(varc - 0.0105) - 0.0026)
            var ds = s - (axl.lumbar + 0.01)
            var dv = varc - 0.07
            var th = atan2(dv, ds)
            var rr = (
                sqrt((ds * 0.95) ** 2 + (dv * 1.1) ** 2)
                * (
                    1.0
                    + 0.16 * sin(th + noise.off)
                    + 0.1 * sin(2.0 * th + 1.3 * noise.off)
                    + 0.45 * (noise.f3(p, 32.0, 2.2) - 0.5)
                )
                + 0.0045 * (th / pi)
                + 0.008 * (noise.f3(p, 80.0, 6.1) - 0.5)
            )
            var bull = min(
                rr - 0.02,
                min(abs(rr - 0.045) - 0.0058, abs(rr - 0.07) - 0.0062),
            )
            var fs = s - (axl.chest - 0.005)
            var fv = varc - 0.028
            var rf = sqrt((fs * 1.4) ** 2 + (fv * 1.1) ** 2)
            var fly = min(abs(rf - 0.014) - 0.0035, rf - 0.004)
            var ph = (
                (s - axl.neck_base) / p0
                + 0.6 * (noise.f3(V3(s, varc, 0.0), 30.0, 4.4) - 0.5)
                + ph_off
            )
            var bars = (abs(ph - _round(ph)) * p0 - wd * 0.6) + smoothstep(
                0.07, 0.04, varc
            ) * smoothstep(axl.neck_base + 0.03, axl.neck_base + 0.06, s) * 0.02
            d = min(
                min(spine, bull),
                min(fly, max(bars, 0.0035 * smoothstep(0.092, 0.078, rr))),
            )
        # Behind the hips the bars curl down the thigh by height.
        var rump_w = smoothstep(-0.25, -0.65, n.z) * smoothstep(
            axl.sacrum - 0.012, axl.tail - 0.002, s
        )
        if rump_w > 0.001:
            var ph_r = p.y / (p0 * 0.95) + 0.35 * (
                noise.n2(p.x * 60.0, p.y * 60.0) - 0.5
            )
            d = mix(d, abs(ph_r - _round(ph_r)) * p0 * 0.95 - wd * 0.42, rump_w)
        # A plain spotted belly; necklaces on the throat and chest.
        var vent = smoothstep(1.9, 2.5, vt)
        if s > axl.chest + 0.02:
            d += vent * 0.02
            var spot = vent > 0.5 and noise.n2(p.x * 300.0, p.z * 300.0) > 0.82
            if spot:
                d = min(d, -0.001)
        else:
            var ny = p.y + 0.25 * (p.z - 0.12)
            var neck = min(
                abs(ny - 0.177) - 0.0022,
                min(
                    abs(ny - 0.152) - 0.0025,
                    abs(ny - 0.129)
                    - 0.002
                    + 0.004 * noise.n2(p.x * 200.0, 3.3),
                ),
            )
            var nw = (
                smoothstep(1.2, 2.0, vt)
                * smoothstep(-0.15, 0.4, n.z)
                * smoothstep(axl.chest + 0.02, axl.chest - 0.02, s)
            )
            d += vent * 0.02 * (1.0 - nw)
            d = mix(d, neck, nw)
    elif region == 4:
        # Rings, none at the root, and a dark tip.
        var ring_p = 0.024
        var ph = tail_s / ring_p + 0.25 * (noise.n2(tail_s * 40.0, 2.2) - 0.5)
        var tt = tail_s / tail_len
        d = abs(ph - _round(ph)) * ring_p - 0.0045 * (0.9 + 0.3 * tt)
        d += vent_in * 0.004
        if tail_s < 0.02:
            d = max(d, 0.02 - tail_s)
        d = min(d, (tail_len - 0.038) - tail_s)
    elif region == 2:
        d = _head_lines(p, n)
    if leg > 0.0:
        # Bars on the front and outside of the legs; plain paws.
        var side = 1.0 if p.x >= 0.0 else -1.0
        var outer = smoothstep(-0.5, 0.2, n.x * side + 0.6 * n.z)
        var ph = (
            p.y / 0.019
            + 0.3 * (noise.n2(p.y * 80.0, p.z * 80.0) - 0.5)
            + (0.25 if p.z > 0.0 else -0.25)
        )
        var dl = abs(ph - _round(ph)) * 0.019 - 0.0038
        dl += (1.0 - outer) * 0.012 + smoothstep(0.03, 0.015, p.y) * 0.02
        d = mix(d, dl, leg)
    return d


def _spots(
    pal: Palette,
    t: Traits,
    noise: _Noise,
    c_in: V3,
    p: V3,
    n: V3,
    region: Int,
    leg: Float64,
    axl: _Axial,
    vent: Float64,
    tail_s: Float64,
    tail_len: Float64,
    bone: String,
) -> V3:
    # White spotting: the tuxedo's shirt front, muzzle and socks; the
    # calico's white with orange and black patches.
    var tux = t.variant == TUXEDO
    var w_amt = t.get("white", 0.0)
    var h = p - HEAD_O
    var nz = (noise.f3(p, 18.0, 3.1) - 0.5) * 0.9 + (
        noise.f3(p, 42.0, 7.7) - 0.5
    ) * 0.2
    var w = 0.0
    var vt = axl.theta
    if tux and region <= 1:
        var bx = abs(p.x) + 0.004 * nz
        w = (
            smoothstep(0.086, 0.102, p.z)
            * smoothstep(0.128, 0.142, p.y)
            * smoothstep(0.2 + 0.006 * w_amt, 0.188 + 0.006 * w_amt, p.y)
            * smoothstep(0.03 + 0.016 * w_amt, 0.018 + 0.016 * w_amt, bx)
            * smoothstep(-0.35, 0.1, n.z)
        )
    elif region <= 1:
        var front = smoothstep(axl.chest + 0.04, axl.chest - 0.03, axl.s)
        w = smoothstep(
            2.55 - 0.9 * w_amt - 0.35 * front,
            2.95 - 0.9 * w_amt - 0.35 * front,
            vt,
        )
        var neck_k = smoothstep(
            axl.neck_base + 0.01, axl.neck_base - 0.025, axl.s
        )
        w = max(
            w,
            front
            * smoothstep(
                1.7 - 0.6 * w_amt + 0.55 * neck_k,
                2.2 - 0.6 * w_amt + 0.35 * neck_k,
                vt,
            ),
        )
    elif region == 2 or region == 6:
        # The muzzle, the chin and the lower cheeks, and a blaze.
        var mz = sqrt(
            (h.x / (0.02 + 0.012 * w_amt)) ** 2
            + ((h.y + 0.03) / (0.016 + 0.01 * w_amt)) ** 2
            + ((h.z - 0.03) / 0.03) ** 2
        )
        w = smoothstep(1.2, 0.9, mz)
        if region == 6:
            w = max(w, 0.85)
        w = max(
            w,
            smoothstep(-0.028, -0.036, h.y)
            * smoothstep(-0.1, -0.5, n.y)
            * (smoothstep(0.004, 0.016, h.z) if tux else 1.0),
        )
        var blaze = t.get("blaze", 0.0)
        if blaze > 0.0:
            w = max(
                w,
                smoothstep(
                    0.004 + 0.004 * blaze,
                    0.0015,
                    abs(h.x) - 0.15 * max(0.0, -h.y),
                )
                * smoothstep(0.012 + 0.012 * blaze, 0.0, h.y)
                * smoothstep(0.0, 0.02, h.z),
            )
    elif region == 4:
        var tip = tux and t.get("tailTip", 0.0) > 0.5
        w = smoothstep(0.9, 0.94, tail_s / tail_len) if tip else 0.0
    if leg > 0.0:
        var top = t.get("sockF") if is_front_limb(bone) else t.get("sockH")
        var sock = smoothstep(top + 0.006, top - 0.006, p.y + 0.006 * nz)
        var wl = sock if tux else max(
            sock, vent * smoothstep(0.5, 0.9, w_amt + 0.3)
        )
        w = mix(w, wl, leg)
    w = clamp(w + nz * 0.3 * (0.3 + w_amt), 0.0, 1.5)
    var c = c_in
    if tux:
        return mix3(c, pal.get("white"), smoothstep(0.45, 0.55, w))
    # The calico's orange and black patches.
    var big = noise.f3(p, 16.0, 11.3) - 0.5
    var fine = noise.f3(p, 55.0, 5.1) - 0.5
    var n_o = (big + 0.25 * fine) * 0.03
    var orange = mix3(
        pal.get("orange"),
        pal.get("orangeDark"),
        smoothstep(0.4, 0.8, noise.f3(p, 60.0, 1.1)) * 0.6,
    )
    if w_amt < 0.05:
        # A tortoiseshell: black and orange brindle all over.
        c = mix3(
            pal.get("black"),
            pal.get("orangeDark"),
            smoothstep(0.62, 0.8, noise.f3(p, 140.0, 2.9)) * 0.7,
        )
        var pat = -n_o - 0.003 + 0.004 * (noise.f3(p, 90.0, 8.8) - 0.5) * 3.0
        return mix3(c, orange, smoothstep(0.0008, -0.0008, pat))
    var d_w = (0.5 - w) * 0.018
    c = pal.get("white")
    var pat = max(-d_w, -n_o - 0.0008)
    c = mix3(c, orange, smoothstep(0.0008, -0.0008, pat))
    var mark = max(-d_w, n_o)
    return mix3(c, pal.get("black"), smoothstep(0.0008, -0.0008, mark))
