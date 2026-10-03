# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The lion, Panthera leo: procedural-animals' `species/lion/`.

A heavy, deep-chested digitigrade cat with a massive head and
forequarters. The reference adult stands 1.07 m at the withers. A male
carries a sculpted mane whose extent and darkness grow with age. A
lioness has no mane and a flatter head. Cubs are small and woolly, with
big heads, ears and paws and faint spots. A rare leucistic morph, the
white lion, is cream all over.
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
from extensions.animals.parts import (
    JAW,
    TEETH,
)
from extensions.sdf.sculpt import ell_y
from extensions.animals.kit import (
    EyeSpec,
    eye_frame_of,
    is_limb,
    mirrored_blob,
    aperture_local,
)
from extensions.animals.noise import cells3, fbm3, vnoise3
from extensions.animals.options import AnimalOptions, AnimalRandom
from extensions.animals.rig import Rig, add_sided, quadruped_bones, tail_chain
from extensions.sdf.field import SdfModel
from extensions.animals.traits import Traits, pick_age, pick_sex, pick_variant
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
    length_warp,
    legs_warp,
    scale_about_warp,
)
from std.math import cos, exp, pi, pow, sin, sqrt
from extensions.sdf.distance import almond_distance, rect_distance

comptime TAIL_SEGS = 10
# The head's origin, mid cranium between the eyes and the ears.
comptime HEAD_O = V3(0.0, 0.95, 0.8)
# The head-local scale: landmarks are for a 0.3 m head.
comptime HS = 1.15
# The finest cell, at the `HERO` tier: the head's cell in the original.
comptime CELL = 0.0042
# Face units: the eye separation `E`, the unit across `X`, and the eye
# midpoint's height and depth, all head-local.
comptime FACE_E = 0.112
comptime FACE_X = 0.1
comptime FACE_EY = 0.047
comptime FACE_EZ = 0.05
# The tail's segment pitches, in degrees, and lengths, in meters.
comptime TAIL_BASE = V3(0.0, 0.915, -0.765)

# The morphs, in procedural-animals' order.
comptime TAWNY = 0
comptime WHITE = 1

# The palette's swatches, by index into `Palette.colors`.
comptime DORSAL = 0
comptime FLANK = 1
comptime LOW_FLANK = 2
comptime BELLY = 3
comptime LEG_OUTER = 4
comptime LEG_INNER = 5
comptime FACE = 6
comptime CROWN = 7
comptime MUZZLE = 8
comptime CHIN = 9
comptime EYE_PATCH = 10
comptime EAR_BACK = 11
comptime EAR_INNER = 12
comptime EAR_CUP = 13
comptime EAR_BACK_CENTER = 14
comptime TUFT = 15
comptime TAIL_TIP = 16
comptime PAW = 17
comptime MANE_BLOND = 18
comptime MANE_MID = 19
comptime MANE_DARK = 20
comptime NOSE_PINK = 21
comptime NOSE_DARK = 22
comptime LIP_DARK = 23
comptime NOSTRIL = 24
comptime MOUTH = 25
comptime TONGUE = 26
comptime TOOTH = 27
comptime PAD = 28
comptime TEAR = 29
comptime BROW_MARK = 30
comptime CUB_BODY = 31
comptime CUB_SPOT = 32
comptime WHISKER_DOT = 33
comptime WHITE_BODY = 34

# The outer corner of the left eye, on the eyeball, in face units.
comptime WING_O = V3(0.6617, 0.0394, 0.0594)
# The color of the black marks: lid margins, lip line, nose outline.
comptime MARK = V3(0.012, 0.009, 0.007)


def lion_variant_names() -> List[String]:
    """Return the lion's color morphs.

    Returns:
        Tawny and white.
    """
    return [String("tawny"), "white"]


def _tri(mut r: AnimalRandom) -> Float64:
    # The lion's own `g`: a triangular number in [-1, 1].
    return r.next() + r.next() - 1.0


def _hl(x: Float64, y: Float64, z: Float64) -> V3:
    return V3(HEAD_O.x + x * HS, HEAD_O.y + y * HS, HEAD_O.z + z * HS)


def _fe(x: Float64, y: Float64, z: Float64, hw: Float64 = 1.12) -> V3:
    # A face-unit landmark in reference space.
    return _hl(x * FACE_X * hw, FACE_EY + y * FACE_E, FACE_EZ + z * FACE_E)


def lion_traits(mut r: AnimalRandom, options: AnimalOptions) raises -> Traits:
    """Draw one lion: procedural-animals' `variation`.

    Males are bigger, with a bigger, broader head and a mane that grows
    fuller and darker with age. Cubs are 0.42 of the size, with a big head,
    a short muzzle and big eyes.

    Args:
        r: The individual's stream.
        options: The caller's sex, age and morph.

    Returns:
        The traits.

    Raises:
        Error: If the requested morph is not one of the two.
    """
    var sex = pick_sex(options.sex, r)
    var age = pick_age(options.age)
    var weights: List[Float64] = [0.97, 0.03]
    var variant = pick_variant(options.variant.value, weights, 0.0)
    var draw = r.next()
    if options.variant.value < 0:
        variant = WHITE if draw < 0.03 else TAWNY
    var t = Traits(sex, age, variant)
    var juv = t.juvenile()
    var male = t.male() and juv == 0.0
    var prime = r.next()
    var maneless = r.next() < 0.08
    var mane = 0.0
    if male:
        mane = 0.12
        if not maneless:
            mane = min(1.0, 0.3 + 0.75 * prime * (0.8 + 0.2 * r.next()))
    var mane_dark = 0.0
    if male:
        mane_dark = min(1.0, max(0.0, 0.1 + 0.65 * prime + 0.3 * _tri(r)))
    var size = (
        (1.075 if male else 0.935)
        * (1.0 + 0.06 * _tri(r))
        * (0.42 if juv > 0.0 else 1.0)
    )
    var legs = 1.0 + 0.045 * _tri(r) - 0.08 * juv
    var head = (
        (1.12 if male else 1.07)
        * (1.0 + 0.04 * _tri(r))
        * (1.28 if juv > 0.0 else 1.0)
    )
    t.set("size", size)
    t.set("mane", mane)
    t.set("maneDark", mane_dark)
    var nose_dark = 0.0
    var leg_spots = 1.0
    if juv == 0.0:
        nose_dark = min(1.0, max(0.0, 0.15 + 0.6 * prime + 0.15 * _tri(r)))
        leg_spots = max(0.0, 0.15 + 0.2 * _tri(r))
    t.set("noseDark", nose_dark)
    t.set("legSpots", leg_spots)
    t.set("coatWarmth", 1.1 * _tri(r))
    t.set("coatLightness", 0.25 * _tri(r))
    t.set("coatSeed", Float64(Int(r.next() * 1e6)))
    t.set("minThick", 0.005)
    if juv > 0.0:
        # A cub's short muzzle and big eyes, before the other warps.
        t.warps.add(length_warp(0.7, 0.878, 1.03))
        for s in [1.0, -1.0]:
            var c = eye_frame_of(lion_eye(t), HEAD_O, s).c
            t.warps.add(scale_about_warp(c, 1.15, 0.026, 0.05))
    t.warps.add(legs_warp(legs, 0.55))
    t.warps.add(length_warp(1.0 + 0.07 * _tri(r) - 0.05 * juv, -0.55, 0.4))
    t.warps.add(scale_about_warp(HEAD_O, head, 0.14, 0.32))
    t.set("earDark", 0.55 + 0.45 * r.next())
    t.set("belly", 0.6 + 0.8 * r.next())
    return t^


def lion_eye(t: Traits) -> EyeSpec:
    """Return the lion's left eye: a round pupil and an amber iris.

    A cub's iris fills more of its opening.

    Args:
        t: The individual.

    Returns:
        The eye, head-local.
    """
    var iris = 0.0128 * (1.14 if t.juvenile() > 0.0 else 1.0)
    return EyeSpec(
        V3(0.05 * 1.12 * 1.15, 0.047 * 1.15, 0.05 * 1.15),
        0.0235,
        0.0133,
        0.15,
        0.03,
        0.002,
        0.0225,
        0.0135,
        -0.0035,
        14.0 * pi / 180.0,
        0.019,
        iris,
    )


def lion_look(t: Traits) -> EyeLook:
    """Return the lion's eye colors: amber-gold, or a duller amber-brown
    in a cub.

    Args:
        t: The individual.

    Returns:
        The look.
    """
    if t.juvenile() > 0.0:
        return EyeLook(
            V3(0.22, 0.13, 0.05),
            V3(0.38, 0.24, 0.09),
            V3(0.1, 0.06, 0.025),
            V3(0.1, 0.065, 0.04),
            0.4,
            0.0,
        )
    return EyeLook(
        V3(0.3, 0.16, 0.035),
        V3(0.5, 0.3, 0.075),
        V3(0.13, 0.07, 0.018),
        V3(0.2, 0.15, 0.11),
        0.33,
        0.0,
    )


def lion_rig(t: Traits) raises -> Rig:
    """Return the lion's skeleton in bind pose.

    The rig is the same for every individual: the warps make the
    proportions. Each side has a whisker bone and an upper-lip bone on
    the head, as in the original.

    Args:
        t: The individual.

    Returns:
        The rig.

    Raises:
        Error: If a bone names a missing joint.
    """
    var rig = Rig()
    rig.set("nose", _fe(0, -1.0, 1.2))
    rig.set("occiput", _hl(0, 0.02, -0.135))
    rig.set("neckMid", V3(0, 0.949, 0.575))
    rig.set("neckBase", V3(0, 0.915, 0.4))
    rig.set("chestMid", V3(0, 0.895, 0.22))
    rig.set("thoraxRear", V3(0, 0.915, -0.03))
    rig.set("lumbarMid", V3(0, 0.925, -0.28))
    rig.set("lumbosacral", V3(0, 0.915, -0.52))
    rig.set("tailBase", TAIL_BASE)
    rig.set("scapTopL", V3(0.065, 0.93, 0.29))
    rig.set("shoulderL", V3(0.105, 0.7, 0.43))
    rig.set("elbowL", V3(0.1, 0.46, 0.225))
    rig.set("wristL", V3(0.08, 0.14, 0.27))
    rig.set("mcpL", V3(0.078, 0.05, 0.315))
    rig.set("ftoeL", V3(0.078, 0.024, 0.39))
    rig.set("hipL", V3(0.09, 0.8, -0.6))
    rig.set("kneeL", V3(0.11, 0.46, -0.45))
    rig.set("hockL", V3(0.09, 0.215, -0.66))
    rig.set("mtpL", V3(0.086, 0.05, -0.62))
    rig.set("htoeL", V3(0.086, 0.024, -0.548))
    rig.set("jawHinge", _hl(0, -0.062, -0.04))
    rig.set("jawTip", _fe(0, -1.42, 0.78))
    rig.set("earBaseL", _ear_base())
    rig.set("earTipL", _ear_tip())
    rig.set("whiskerBaseL", _fe(0.34, -1.11, 0.78))
    rig.set("whiskerTipL", _fe(1.3, -1.25, 1.15))
    rig.set("lipBaseL", _fe(0.42, -1.4, 0.3))
    rig.set("lipTipL", _fe(0.52, -1.4, -0.1))
    tail_chain(rig, "tailBase", _tail_angles(), _tail_lens())
    rig.mirror_joints()
    quadruped_bones(rig, TAIL_SEGS)
    add_sided(rig, "whisker{S}", "whiskerBase{S}", "whiskerTip{S}", "head")
    add_sided(rig, "lip{S}", "lipBase{S}", "lipTip{S}", "head")
    return rig^


def _tail_angles() -> List[Float64]:
    return [
        -22.0,
        -34.0,
        -44.0,
        -51.0,
        -56.0,
        -58.0,
        -58.0,
        -55.0,
        -48.0,
        -38.0,
    ]


def _tail_lens() -> List[Float64]:
    return [0.088, 0.088, 0.087, 0.086, 0.085, 0.084, 0.083, 0.082, 0.081, 0.08]


def _ear_base() -> V3:
    return _hl(0.106, 0.1, -0.068)


def _ear_tip() -> V3:
    return _hl(0.152, 0.192, -0.095)


def _tail_radius(t: Float64) -> Float64:
    # A smooth round tail, tapering a little.
    if t < 0.3:
        return 0.05 + (0.034 - 0.05) * (t / 0.3)
    return 0.034 - 0.012 * ((t - 0.3) / 0.7)


def _ear_ramp(t: Float64) -> Float64:
    # Zero at the ear's base, one from its middle up.
    return clamp(t / 0.45, 0.0, 1.0)


def lion_sculpt(mut m: SdfModel, rig: Rig, t: Traits) raises:
    """Sculpt the lion: procedural-animals' `sculptLion`, primitive for
    primitive.

    The male's mane is sculpted volume: a collar, a crest, a bib and a
    face ruff, broken into seeded locks.

    Args:
        m: The sculpt to add to.
        rig: The lion's rig in bind pose.
        t: The individual.

    Raises:
        Error: If the rig lacks a joint or a bone, or the sculpt refuses
            a primitive.
    """
    var mane = t.get("mane", 0.0)
    var juv = t.juvenile()
    var male = 1.0 if (t.male() and juv == 0.0) else 0.0

    # TORSO: a broad, deep chest, a level back and a low belly line.
    _ = m.ell(
        "ribcage",
        rig.bone("spine3"),
        V3(0, 0.745, 0.12),
        V3(0.145, 0.245, 0.33),
        axis=normalize(V3(0, 0.12, -1)),
        k=0,
    )
    var b = rig.bone("chest")
    _ = m.ell(
        "brisket",
        b,
        V3(0, 0.59, 0.3),
        V3(0.1, 0.12, 0.14),
        axis=normalize(V3(0, -0.35, 1)),
        k=0.08,
    )
    _ = m.ell("pectoral", b, V3(0, 0.625, 0.41), V3(0.11, 0.13, 0.1), k=0.07)
    _ = m.ell(
        "withers",
        b,
        V3(0, 0.955, 0.3),
        V3(0.085, 0.08, 0.2),
        axis=normalize(V3(0, -0.08, 1)),
        k=0.08,
    )
    _ = m.ell(
        "back",
        rig.bone("spine3"),
        V3(0, 0.965, 0),
        V3(0.11, 0.07, 0.25),
        k=0.08,
    )
    _ = m.ell(
        "abdomen",
        rig.bone("spine2"),
        V3(0, 0.735, -0.24),
        V3(0.135, 0.215, 0.29),
        axis=normalize(V3(0, 0.18, -1)),
        k=0.09,
    )
    b = rig.bone("spine1")
    _ = m.ell("loin", b, V3(0, 0.955, -0.34), V3(0.105, 0.075, 0.25), k=0.07)
    _ = m.ell("flank", b, V3(0, 0.79, -0.45), V3(0.12, 0.12, 0.14), k=0.07)
    # The loose belly fold in front of the hind legs, small to heavy.
    var bk = t.get("belly", 1.0)
    _ = m.ell(
        "pouch",
        b,
        V3(0, 0.6 + 0.02 * (1.0 - male) + 0.015 * (1.0 - bk), -0.36),
        V3(0.085, (0.07 - 0.015 * (1.0 - male)) * (0.75 + 0.25 * bk), 0.16),
        axis=normalize(V3(0, 0.2, -1)),
        k=0.09,
    )
    b = rig.bone("pelvis")
    _ = m.ell("pelvis", b, V3(0, 0.885, -0.64), V3(0.125, 0.14, 0.19), k=0.08)
    _ = m.ell("croup", b, V3(0, 0.975, -0.63), V3(0.09, 0.06, 0.17), k=0.06)
    # A faint ridge along the spine.
    var spine: List[V3] = [
        V3(0, 1.0, 0.3),
        V3(0, 1.018, 0.08),
        V3(0, 1.012, -0.2),
        V3(0, 1.008, -0.42),
        V3(0, 1.018, -0.6),
    ]
    var spine_bones: List[String] = [
        String("chest"),
        "spine3",
        "spine2",
        "spine1",
    ]
    for i in range(4):
        _ = m.cone(
            "spine",
            rig.bone(spine_bones[i]),
            spine[i],
            spine[i + 1],
            0.024,
            0.024,
            k=0.03,
        )
    for s in [1.0, -1.0]:
        _ = m.ell(
            "ilium",
            b,
            V3(0.08 * s, 0.997, -0.53),
            V3(0.052, 0.048, 0.08),
            k=0.04,
        )
        _ = m.ell(
            "rump",
            b,
            V3(0.07 * s, 0.81, -0.755),
            V3(0.066, 0.11, 0.063),
            k=0.06,
        )

    # NECK: short and thick, thicker in males.
    var nk = 1.0 + 0.12 * male
    var n1 = rig.bone("neck1")
    var n2 = rig.bone("neck2")
    _ = m.cone(
        "neck",
        n1,
        V3(0, 0.8, 0.43),
        V3(0, 0.9, 0.585),
        0.14 * nk,
        0.115 * nk,
        k=0.08,
    )
    _ = m.cone(
        "neck",
        n2,
        V3(0, 0.9, 0.585),
        _hl(0, 0, -0.1),
        0.115 * nk,
        0.1 * nk,
        k=0.06,
    )
    _ = m.ell(
        "nape",
        n1,
        V3(0, 0.95, 0.54),
        V3(0.07, 0.05, 0.15),
        axis=normalize(V3(0, 0.35, 1)),
        k=0.06,
    )
    _ = m.ell(
        "throat",
        n1,
        V3(0, 0.73, 0.57),
        V3(0.085, 0.1, 0.12),
        axis=normalize(V3(0, 0.8, 0.6)),
        k=0.07,
    )
    _ = m.ell(
        "throat", n2, _hl(0, -0.095, -0.075), V3(0.07, 0.055, 0.09), k=0.05
    )

    if mane > 0.0:
        _sculpt_mane(m, rig, t, mane)
    _sculpt_head(m, rig, t, male, juv)
    _sculpt_ears(m, rig, male, juv)
    _sculpt_legs(m, rig, male, juv)

    # TAIL: a smooth round tail ending in the black tuft.
    _ = m.cone(
        "tailroot",
        rig.bone("tail0"),
        V3(0, 0.935, -0.72),
        rig.j("tail1"),
        0.06,
        _tail_radius(0.1),
        k=0.06,
    )
    for i in range(TAIL_SEGS):
        _ = m.cone(
            "tail",
            rig.bone("tail" + String(i)),
            rig.j("tail" + String(i)),
            rig.j("tail" + String(i + 1)),
            _tail_radius(Float64(i) / Float64(TAIL_SEGS)),
            _tail_radius(Float64(i + 1) / Float64(TAIL_SEGS)),
            k=0.015 if i == 0 else 0.0,
            thin=i >= TAIL_SEGS - 2,
        )
    if juv < 0.8:
        var ta = rig.j("tail" + String(TAIL_SEGS - 1))
        var tb = rig.j("tail" + String(TAIL_SEGS))
        var d = normalize(tb - ta)
        var tk = 1.0 - 0.6 * juv
        _ = ell_y(
            m,
            "tuft",
            rig.bone("tail" + String(TAIL_SEGS - 1)),
            tb + d * -0.012,
            d,
            V3(0.038 * tk, 0.075 * tk, 0.038 * tk),
            lateral=normalize(cross(d, V3(0, 1, 0))),
            k=0.03,
            thin=True,
        )


def _sculpt_mane(mut m: SdfModel, rig: Rig, t: Traits, g: Float64) raises:
    # The male's mane: sculpted coat volume, then seeded locks over it.
    var base = List[Int]()
    var n1 = rig.bone("neck1")
    var n2 = rig.bone("neck2")
    var ch = rig.bone("chest")
    var h = rig.bone("head")
    # The collar round the neck, fullest at the sides and the throat.
    base.append(
        m.ell(
            "mane",
            n1,
            V3(0, 0.87, 0.53),
            V3(0.17 + 0.11 * g, 0.2 + 0.1 * g, 0.18 + 0.07 * g),
            axis=normalize(V3(0, 0.55, 1)),
            k=0.13,
        )
    )
    # The crest over the nape and between the shoulders.
    base.append(
        m.ell(
            "mane",
            n2,
            V3(0, 1.0 + 0.07 * g, 0.63),
            V3(0.11 + 0.08 * g, 0.08 + 0.07 * g, 0.17 + 0.05 * g),
            axis=normalize(V3(0, 0.3, 1)),
            k=0.12,
        )
    )
    base.append(
        m.ell(
            "mane",
            ch,
            V3(0, 0.96 + 0.025 * g, 0.38),
            V3(0.13 + 0.08 * g, 0.075 + 0.035 * g, 0.16 + 0.08 * g),
            axis=normalize(V3(0, 0.2, 1)),
            k=0.13,
        )
    )
    # The bib under the throat and down the chest.
    base.append(
        m.ell(
            "mane",
            n1,
            V3(0, 0.7 - 0.02 * g, 0.585),
            V3(0.13 + 0.045 * g, 0.13 + 0.06 * g, 0.1 + 0.05 * g),
            axis=normalize(V3(0, 0.8, 0.35)),
            k=0.09,
        )
    )
    base.append(
        m.ell(
            "mane",
            ch,
            V3(0, 0.63 - 0.03 * g, 0.49),
            V3(0.1 + 0.035 * g, 0.1 + 0.05 * g, 0.075 + 0.03 * g),
            k=0.08,
        )
    )
    # The face ruff behind the cheeks, and the crown behind the ears.
    for s in [1.0, -1.0]:
        base.append(
            m.ell(
                "mane",
                h,
                _hl(0.09 * s, -0.06, -0.175),
                V3(0.05 + 0.055 * g, 0.1 + 0.07 * g, 0.065 + 0.04 * g),
                axis=normalize(V3(0.25 * s, 0, 1)),
                k=0.09,
            )
        )
    base.append(
        m.ell(
            "mane",
            h,
            _hl(0, 0.08 + 0.03 * g, -0.215),
            V3(0.09 + 0.05 * g, 0.05 + 0.05 * g, 0.07 + 0.04 * g),
            k=0.09,
        )
    )
    base.append(
        m.ell(
            "mane",
            h,
            _hl(0, -0.14 - 0.03 * g, -0.08),
            V3(0.08 + 0.045 * g, 0.05 + 0.05 * g, 0.08),
            k=0.07,
        )
    )
    # Locks: each lies along the hair's fall, partly sunk into the volume,
    # on the bone of the part it grows from. None ride the skull.
    var rl = AnimalRandom(4127 + Int(t.get("coatSeed", 0.0)), 1, 0)
    var a0 = V3(0, 0.92, 0.36)
    var a1 = _hl(0, 0, -0.07)
    var fc = _hl(0, -0.03, 0.02)
    var locks = Int(14.0 + 20.0 * g + 0.5)
    for _ in range(locks):
        var u = 0.62 * pow(rl.next(), 0.8)
        var th = (rl.next() * 2.0 - 1.0) * pi * 0.9
        var ax = lerp(a0, a1, u)
        var dir = normalize(V3(sin(th), cos(th), 0.25 * (u - 0.4)))
        var lo = 0.0
        var hi = 0.8
        for _ in range(22):
            var mid = (lo + hi) / 2.0
            var inside = m.eval_list(base, ax + dir * mid) < 0.0
            lo = mid if inside else lo
            hi = hi if inside else mid
        var p = ax + dir * lo
        var e = 0.002
        var f0 = m.eval_list(base, p)
        var n = normalize(
            V3(
                m.eval_list(base, V3(p.x + e, p.y, p.z)) - f0,
                m.eval_list(base, V3(p.x, p.y + e, p.z)) - f0,
                m.eval_list(base, V3(p.x, p.y, p.z + e)) - f0,
            )
        )
        var ruff = clamp((p.z - 0.62) / 0.1, 0.0, 1.0)
        var fl = (
            normalize(V3(0, -0.9, -0.55)) * (1.0 - ruff)
            + normalize(normalize(p - fc) + V3(0, -0.3, -0.4)) * ruff
        )
        fl = fl - n * dot(fl, n)
        if length(fl) < 1e-3:
            continue
        fl = normalize(fl)
        var rt = (0.022 + 0.016 * rl.next()) * (0.75 + 0.45 * g)
        var rlen = rt * (1.8 + 0.9 * rl.next())
        var bone = n1
        var bd = 1e9
        for q in base:
            var dq = m.distance(q, p)
            var closer = dq < bd
            bd = dq if closer else bd
            if closer:
                bone = m.prims[q].bone
        if bone == h:
            continue
        _ = ell_y(
            m,
            "mane",
            bone,
            p + n * (-0.05 * rt) + fl * (0.4 * rlen),
            fl,
            V3(rt, rlen, 0.48 * rt),
            lateral=normalize(cross(fl, n)),
            k=0.03,
        )


def _hr(r: V3, hw: Float64) -> V3:
    return V3(r.x * hw * HS, r.y * HS, r.z * HS)


def _fr(rx: Float64, ry: Float64, rz: Float64, hw: Float64) -> V3:
    # Radii in face units.
    return _hr(V3(rx * FACE_X, ry * FACE_E, rz * FACE_E), hw)


def _sculpt_head(
    mut m: SdfModel, rig: Rig, t: Traits, male: Float64, juv: Float64
) raises:
    # The head as planes with edges: a flat broad skull, a dished
    # forehead between brow ridges, a broad flat-topped bridge, a square
    # muzzle of swollen whisker pads, cheekbones the widest point.
    var h = rig.bone("head")
    var hw = 1.12 + 0.02 * male - 0.04 * juv
    _ = m.ell(
        "cranium",
        h,
        _fe(0, 0.1 + 0.07 * juv, -0.98, hw),
        _fr(0.96 - 0.05 * juv, 0.8 + 0.17 * juv, 1.0, hw),
        k=0.05,
    )
    var lean = 0.72 - 0.25 * juv
    _ = m.ell(
        "forehead",
        h,
        _fe(0, 0.42 + 0.06 * juv, -0.5, hw),
        _fr(0.64, 0.62, 0.3 + 0.06 * juv, hw),
        axis=normalize(V3(0, lean, 1)),
        up=normalize(V3(0, 1, -lean)),
        k=0.055,
    )
    for s in [1.0, -1.0]:
        _ = m.ell(
            "temporal",
            h,
            _fe((0.62 - 0.04 * juv) * s, 0.36 - 0.08 * juv, -0.92, hw),
            _fr(0.38, 0.42, 0.6, hw),
            axis=normalize(V3(-0.3 * s, 0, 1)),
            k=0.05,
        )
    _ = m.ell(
        "facemask",
        h,
        _fe(0, -0.12, -0.36, hw),
        _fr(0.76, 0.5, 0.36, hw),
        k=0.04,
    )
    for s in [1.0, -1.0]:
        _ = m.ell(
            "brow",
            h,
            _fe(0.4 * s, 0.28, -0.12 * juv, hw),
            _fr(0.3, 0.12, 0.2, hw),
            axis=normalize(V3(0.45 * s, 0, 1)),
            up=normalize(V3(0, 1, 0.3)),
            k=0.026,
        )
        _ = m.ell(
            "zygomatic",
            h,
            _fe(0.92 * s, -0.14, -0.66, hw),
            _fr(0.22, 0.2, 0.6, hw),
            axis=normalize(V3(-0.42 * s, 0, 1)),
            k=0.06,
        )
        _ = m.ell(
            "cheek",
            h,
            _fe(0.72 * s, -0.72, -0.66, hw),
            _fr(0.14, 0.5, 0.62, hw),
            axis=normalize(V3(-0.3 * s, -0.2, 1)),
            k=0.035,
        )
        _ = m.ell(
            "lip",
            h,
            _fe(0.38 * s, -1.22, 0.26, hw),
            _fr(0.22, 0.24, 0.56, hw),
            axis=normalize(V3(-0.35 * s, -0.1, 1)),
            k=0.03,
        )
        _ = m.ell(
            "mastoid",
            h,
            _fe(0.54 * s, -0.98, -1.32, hw),
            _fr(0.44, 0.5, 0.46, hw),
            k=0.035,
        )
        _ = m.ell(
            "masseter",
            h,
            _fe(0.78 * s, -0.72, -1.04, hw),
            _fr(0.18, 0.54, 0.56, hw),
            axis=normalize(V3(-0.25 * s, 0, 1)),
            k=0.045,
        )
        _ = m.ell(
            "jowl",
            h,
            _fe(0.56 * s, -1.22, -0.78, hw),
            _fr(0.26, 0.36, 0.54, hw),
            k=0.03,
        )
        _ = m.ell(
            "padside",
            h,
            _fe(0.41 * s, -0.76, 0.3, hw),
            _fr(0.17, 0.4, 0.6, hw),
            axis=normalize(V3(-0.22 * s, -0.12, 1)),
            k=0.05,
        )
        _ = m.ell(
            "infraorbital",
            h,
            _fe(0.5 * s, -0.58, -0.12, hw),
            _fr(0.18, 0.24, 0.22, hw),
            axis=normalize(V3(0.35 * s, -0.3, 1)),
            k=0.04,
        )
        _ = m.ell(
            "whisker",
            h,
            _fe(0.28 * s, -1.16, 0.58, hw),
            _fr(0.3, 0.36, 0.48, hw),
            axis=normalize(V3(0.15 * s, -0.08, 1)),
            k=0.025,
        )
    _ = m.ell(
        "whisker",
        h,
        _fe(0, -1.08, 0.82, hw),
        _fr(0.42, 0.26, 0.18, hw),
        axis=normalize(V3(0, -0.1, 1)),
        k=0.025,
    )
    _ = m.ell(
        "maxilla",
        h,
        _fe(0, -0.68, -0.25, hw),
        _fr(0.5, 0.46, 1.0, hw),
        axis=normalize(V3(0, -0.2, 1)),
        k=0.025,
    )
    _ = m.ell(
        "muzzle",
        h,
        _fe(0, -0.82, 0.4, hw),
        _fr(0.4, 0.38, 0.54, hw),
        axis=normalize(V3(0, -0.15, 1)),
        k=0.04,
    )
    # The nasal bridge: broad and straight from the stop to the leather.
    var top0 = _fe(0, 0.24 - 0.08 * juv, 0.18, hw)
    var top1 = _fe(0, -0.68, 0.98, hw)
    var bd = normalize(top1 - top0)
    var bu = normalize(cross(bd, V3(1, 0, 0)))
    var eh = FACE_E * HS
    _ = m.ell(
        "nasal",
        h,
        lerp(top0, top1, 0.55) + bu * (-0.24 * eh),
        _fr(0.42, 0.24, 0.82, hw),
        axis=bd,
        up=bu,
        k=0.026,
    )
    _ = m.ell(
        "nasal",
        h,
        lerp(top0, top1, 0.86) + bu * (-0.17 * eh),
        _fr(0.39, 0.17, 0.42, hw),
        axis=bd,
        up=bu,
        k=0.03,
    )
    # The nose leather: the bridge's end, and the stem.
    _ = m.ell(
        "nose",
        h,
        top1 + bd * (0.06 * eh) + bu * (-0.105 * eh),
        _fr(0.39, 0.115, 0.17, hw),
        axis=bd,
        up=bu,
        k=0.022,
    )
    _ = m.ell(
        "nose",
        h,
        _fe(0, -1.03, 1.06, hw),
        _fr(0.15, 0.12, 0.08, hw),
        k=0.014,
    )
    var eye = lion_eye(t)
    for s in [1.0, -1.0]:
        var ef = eye_frame_of(eye, HEAD_O, s)
        _ = ell_y(
            m,
            "orbit",
            h,
            ef.at(-0.003 * s, -0.001, 0.029),
            ef.y,
            V3(0.025, 0.018, 0.012),
            lateral=ef.x,
            k=0.012,
            carve=True,
        )
        _ = m.sphere("eyelid", h, ef.c, eye.r + eye.lid, k=0.008)
        _ = m.lens(
            "eyesocket",
            h,
            ef.c + ef.y * eye.off,
            ef.x,
            ef.y,
            ef.z,
            eye.big_r,
            eye.d,
            -0.003,
            0.036,
            k=0.0033,
            carve=True,
        )
        # The nostril: a slit at the leather's lower outer corner.
        _ = m.ell(
            "nostril",
            h,
            _fe(0.22 * s, -0.94, 1.08, hw),
            _fr(0.12, 0.045, 0.08, hw),
            axis=normalize(V3(0.55 * s, -0.2, 1)),
            up=V3(-sin(0.4), s * cos(0.4), 0),
            k=0.005,
            carve=True,
        )
        # The upper canine, hidden inside the upper lip and the jaw.
        _ = m.cone(
            "canine",
            h,
            _fe(0.27 * s, -1.13, 0.645, hw),
            _fe(0.27 * s, -1.45, 0.61, hw),
            0.0076 * HS,
            0.0022 * HS,
            k=0,
            part=TEETH,
            thin=True,
        )
    # The upper lip's edge, deep inside the lip, on the lip bone.
    for side in [String("L"), String("R")]:
        var s = 1.0 if side == "L" else -1.0
        _ = m.ell(
            "lipedge",
            rig.bone("lip" + side),
            _fe(0.43 * s, -1.36, 0.28, hw),
            _fr(0.05, 0.045, 0.42, hw),
            axis=normalize(V3(-0.26 * s, 0, 1)),
            k=0.004,
        )
    _ = m.ell(
        "philtrum",
        h,
        _fe(0, -1.3, 1.1, hw),
        _fr(0.03, 0.16, 0.05, hw),
        k=0.01,
        carve=True,
    )

    # JAW: its own surface, so the mouth can open.
    var jw = rig.bone("jaw")
    var er = FACE_E * HS
    for s in [1.0, -1.0]:
        _ = m.cone(
            "mandible",
            jw,
            _fe(0.4 * s, -1.14, -0.78, hw),
            _fe(0.165 * s, -1.28, 0.55, hw),
            0.18 * er,
            0.125 * er,
            k=0.03,
            part=JAW,
        )
    _ = m.ell(
        "chin",
        jw,
        _fe(0, -1.48, 0.47, hw),
        _fr(0.2, 0.2, 0.19, hw),
        k=0.06,
        part=JAW,
    )
    _ = m.ell(
        "mandible",
        jw,
        _fe(0, -1.46, -0.12, hw),
        _fr(0.22, 0.15, 0.62, hw),
        axis=normalize(V3(0, 0.12, 1)),
        k=0.04,
        part=JAW,
    )
    _ = m.ell(
        "mouth",
        jw,
        _fe(0, -1.13, -0.02, hw),
        _fr(0.24, 0.16, 0.7, hw),
        k=0.015,
        carve=True,
        part=JAW,
    )
    _ = m.ell(
        "tongue",
        jw,
        _fe(0, -1.28, 0.08, hw),
        _fr(0.21, 0.07, 0.56, hw),
        k=0.02,
        part=JAW,
    )
    for s in [1.0, -1.0]:
        _ = m.cone(
            "canine",
            jw,
            _fe(0.2 * s, -1.23, 0.64, hw),
            _fe(0.215 * s, -0.99, 0.68, hw),
            0.0072 * HS,
            0.0022 * HS,
            k=0.003,
            part=JAW,
        )


@fieldwise_init
struct _EarFrame(ImplicitlyCopyable):
    var base: V3
    var up: V3
    var lat: V3
    var facing: V3
    var span: Float64
    var male: Float64
    var s: Float64

    def at(self, t: Float64, l: Float64) -> V3:
        # A point on the pinna: `t` up from the base, `l` outward.
        var ramp = _ear_ramp(t)
        return (
            self.base
            + self.up * (t * self.span + 0.008 * self.male * ramp)
            + self.lat * (self.s * (l + 0.012 * self.male * ramp))
        )


def _sculpt_ears(mut m: SdfModel, rig: Rig, male: Float64, juv: Float64) raises:
    # Short, rounded ears cupped forward, set on the sides of the crown:
    # a stack of discs leaning toward the midline, narrowing to a round
    # tip, with a shallow bowl carved in front.
    for side in [String("L"), String("R")]:
        var s = 1.0 if side == "L" else -1.0
        var base = rig.j("earBase" + side)
        var tip = rig.j("earTip" + side)
        var up = normalize(tip - base)
        var facing = normalize(V3(0.7 * s, 0.05, 1))
        var lat = normalize(cross(up, facing))
        var eb = rig.bone("ear" + side)
        var ek = (1.0 + 0.45 * juv) * (1.0 + 0.15 * male)
        var ew = (1.0 + 1.0 * juv) * (1.1 + 0.6 * male)
        var eh = (1.0 + 0.55 * juv) * (0.94 + 0.22 * male)
        var ca = cos(0.16)
        var sa = sin(0.16)
        var u2 = normalize(up * ca + lat * (-sa * s))
        var l2 = normalize(cross(u2, facing))
        var span = length(tip - base)

        var fr = _EarFrame(base, u2, l2, facing, span, male, s)
        _ = ell_y(
            m,
            "ear",
            eb,
            fr.at(0.26, 0),
            u2,
            V3(0.046 * ek, 0.042 * ek, 0.013),
            lateral=l2,
            k=0.022,
            thin=True,
        )
        _ = ell_y(
            m,
            "ear",
            eb,
            fr.at(0.45, 0.009 * ew),
            u2,
            V3(0.046 * ew, 0.046 * eh, 0.0085),
            lateral=l2,
            k=0.02,
            thin=True,
        )
        _ = ell_y(
            m,
            "ear",
            eb,
            fr.at(0.64, 0.004 * ew),
            u2,
            V3(0.036 * ew, 0.042 * eh, 0.0075),
            lateral=l2,
            k=0.018,
            thin=True,
        )
        _ = ell_y(
            m,
            "ear",
            eb,
            fr.at(0.77, 0),
            u2,
            V3(0.025 * ew, 0.03 * eh, 0.0065),
            lateral=l2,
            k=0.016,
            thin=True,
        )
        _ = ell_y(
            m,
            "earinner",
            eb,
            fr.at(0.54, 0.002 * ew) + facing * 0.0102,
            u2,
            V3(0.028 * ew, 0.04 * eh, 0.005),
            lateral=l2,
            k=0.01,
            carve=True,
            thin=True,
        )


def _sculpt_legs(mut m: SdfModel, rig: Rig, male: Float64, juv: Float64) raises:
    # Thick, muscular forelegs with a massive forearm and big round paws;
    # broad, heavy thighs rising into the flank and the croup.
    var paw_k = 1.0 + 0.1 * juv
    var paw_l = 1.0 + 0.25 * juv
    var toe_x: List[Float64] = [-0.033, -0.011, 0.011, 0.033]
    var toe_z: List[Float64] = [-0.018, 0, 0, -0.018]
    for side in [String("L"), String("R")]:
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
            "scaptop",
            scap,
            lerp(sc, sh, 0.1) + on_side(V3(0.016, 0.03, 0), s),
            sh - sc,
            V3(0.045, 0.08, 0.065),
            lateral=lat,
            k=0.04,
        )
        _ = ell_y(
            m,
            "scapmuscle",
            scap,
            lerp(sc, sh, 0.5) + on_side(V3(0.012, 0, 0), s),
            sh - sc,
            V3(0.042, 0.16, 0.1),
            lateral=lat,
            k=0.09,
        )
        _ = m.cone("upperarm", hum, sh, e, 0.076, 0.063, k=0.09)
        _ = ell_y(
            m,
            "triceps",
            hum,
            lerp(sh, e, 0.55) + V3(0, 0, -0.05),
            e - sh,
            V3(0.061, 0.13, 0.07),
            lateral=lat,
            k=0.07,
        )
        _ = m.sphere("olecranon", rad, e + V3(0, 0.016, -0.045), 0.034, k=0.03)
        _ = m.cone("forearm", rad, e, w, 0.075, 0.047, k=0.04)
        _ = ell_y(
            m,
            "forearmmuscle",
            rad,
            lerp(e, w, 0.28) + on_side(V3(0.006, 0, 0.008), s),
            w - e,
            V3(0.067, 0.13, 0.07),
            lateral=lat,
            k=0.045,
        )
        if male > 0.0:
            _ = ell_y(
                m,
                "elbowtuft",
                rad,
                e + V3(0, -0.02, -0.06),
                V3(0, -1, -0.3),
                V3(0.03, 0.06, 0.03),
                lateral=lat,
                k=0.04,
            )
        _ = m.sphere("wrist", meta, w + V3(0, 0, -0.006), 0.036, k=0.02)
        _ = m.sphere(
            "carpalpad", meta, w + V3(0, -0.018, -0.034), 0.015, k=0.015
        )
        _ = m.cone("pastern", meta, w, mc, 0.036, 0.036 * paw_k, k=0.02)
        _ = m.sphere(
            "dewclaw",
            meta,
            lerp(w, mc, 0.35) + on_side(V3(-0.03, 0, 0.006), s),
            0.011,
            k=0.01,
        )
        var dp = normalize(toe - mc)
        _ = ell_y(
            m,
            "paw",
            fpaw,
            mc + dp * 0.03 + V3(0, -0.008 + 0.005 * juv, 0),
            dp,
            V3(0.051, 0.066 * paw_l, 0.032),
            lateral=lat,
            k=0.022,
        )
        _ = m.sphere(
            "pad",
            fpaw,
            mc + V3(0, -0.025 + 0.004 * juv, 0.02),
            0.02 * paw_k,
            k=0.015,
        )
        for i in range(4):
            _ = m.sphere(
                "toe",
                fpaw,
                V3(
                    toe.x + toe_x[i] * s,
                    0.024 + 0.004 * juv,
                    toe.z - 0.016 * paw_l + toe_z[i] * paw_l,
                ),
                0.02 * paw_k,
                k=0.012,
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
            lerp(hp, kn, 0.4) + on_side(V3(0.008, 0, -0.055), s),
            kn - hp,
            V3(0.076, 0.25, 0.168),
            lateral=lat,
            k=0.08,
        )
        _ = m.cone(
            "thighfront",
            fem,
            on_side(V3(0.072, 0.87, -0.47), s),
            kn + on_side(V3(-0.006, 0.08, 0), s),
            0.068,
            0.042,
            k=0.09,
        )
        _ = m.cone(
            "hamstring",
            fem,
            on_side(V3(0.075, 0.88, -0.8), s),
            lerp(kn, hk, 0.28) + V3(0, 0, -0.045),
            0.08,
            0.05,
            k=0.06,
        )
        _ = ell_y(
            m,
            "flankfold",
            fem,
            on_side(V3(0.092, 0.62, -0.435), s),
            V3(-0.03, 0.16, 0.06),
            V3(0.03, 0.13, 0.05),
            lateral=lat,
            k=0.09,
        )
        _ = m.sphere(
            "stifle",
            tib,
            kn + on_side(V3(0.004, 0.014, 0.004), s),
            0.026,
            k=0.04,
        )
        _ = m.cone(
            "shin",
            tib,
            lerp(kn, hk, 0.06) + on_side(V3(0, 0, 0.006), s),
            hk,
            0.046,
            0.033,
            k=0.045,
        )
        _ = ell_y(
            m,
            "calf",
            tib,
            lerp(kn, hk, 0.3) + on_side(V3(0.004, 0.015, -0.045), s),
            hk - kn,
            V3(0.05, 0.11, 0.055),
            lateral=lat,
            k=0.05,
        )
        _ = m.cone(
            "achilles",
            tib,
            lerp(kn, hk, 0.5) + V3(0, 0.015, -0.055),
            hk + V3(0, 0.02, -0.05),
            0.02,
            0.019,
            k=0.022,
        )
        _ = m.sphere(
            "calcaneus", mtar, hk + V3(0, 0.026, -0.038), 0.02, k=0.018
        )
        _ = m.sphere("hock", mtar, hk, 0.031, k=0.018)
        _ = m.cone("metatarsus", mtar, hk, mt, 0.034, 0.033 * paw_k, k=0.018)
        var dh = normalize(tt - mt)
        _ = ell_y(
            m,
            "paw",
            hpaw,
            mt + dh * 0.03 + V3(0, -0.008 + 0.005 * juv, 0),
            dh,
            V3(0.048, 0.062 * paw_l, 0.03),
            lateral=lat,
            k=0.022,
        )
        _ = m.sphere(
            "pad",
            hpaw,
            mt + V3(0, -0.027 + 0.004 * juv, 0.016),
            0.018 * paw_k,
            k=0.015,
        )
        for i in range(4):
            _ = m.sphere(
                "toe",
                hpaw,
                V3(
                    tt.x + toe_x[i] * 0.9 * s,
                    0.023 + 0.004 * juv,
                    tt.z - 0.016 * paw_l + toe_z[i] * paw_l,
                ),
                0.0185 * paw_k,
                k=0.012,
            )


# ---------------------------------------------------------------- COAT


def _swatches() -> List[String]:
    return [
        String("dorsal"),
        "flank",
        "lowFlank",
        "belly",
        "legOuter",
        "legInner",
        "face",
        "crown",
        "muzzle",
        "chin",
        "eyePatch",
        "earBack",
        "earInner",
        "earCup",
        "earBackCenter",
        "tuft",
        "tailTip",
        "paw",
        "maneBlond",
        "maneMid",
        "maneDark",
        "nosePink",
        "noseDark",
        "lipDark",
        "nostril",
        "mouth",
        "tongue",
        "tooth",
        "pad",
        "tear",
        "browMark",
        "cubBody",
        "cubSpot",
        "whiskerDot",
        "whiteBody",
    ]


def _hexes() -> List[Int]:
    return [
        0x9C8066,
        0xAE9276,
        0xBFA58A,
        0xD8CAB8,
        0xB09478,
        0xD2C1AA,
        0xB39B7E,
        0xA68D71,
        0xF0E8DA,
        0xEFE6D6,
        0xEEE2CE,
        0x1C1410,
        0xD6C6AE,
        0x7A6452,
        0x9A7B5A,
        0x140E0A,
        0x5A3E28,
        0xB89C80,
        0xC6A070,
        0x6B4523,
        0x2A1B10,
        0x9A7A72,
        0x2E2220,
        0x16100E,
        0x140E0D,
        0x4A2426,
        0xA8585C,
        0xE8E0CC,
        0x2E2220,
        0x4A3526,
        0x7A5A40,
        0xBFA27F,
        0x8C6A48,
        0x2A1C14,
        0xEDE4D3,
    ]


def _bare(i: Int) -> Bool:
    # The swatches the warmth, the lightness and the saturation leave alone.
    return (
        i == NOSE_PINK
        or i == NOSE_DARK
        or i == NOSTRIL
        or i == MOUTH
        or i == TONGUE
        or i == TOOTH
        or i == PAD
        or i == TUFT
        or i == EAR_BACK
        or i == MANE_DARK
        or i == TEAR
        or i == LIP_DARK
        or i == WHISKER_DOT
    )


def _white_amount(i: Int) -> Float64:
    # How far the white lion's coat bleaches each swatch toward cream.
    var skin = (
        i == NOSE_PINK
        or i == NOSE_DARK
        or i == NOSTRIL
        or i == MOUTH
        or i == TONGUE
        or i == TOOTH
        or i == PAD
        or i == CUB_SPOT
        or i == LIP_DARK
        or i == WHISKER_DOT
    )
    var dark = i == TUFT or i == EAR_BACK or i == MANE_DARK or i == MANE_MID
    var mark = i == TEAR or i == BROW_MARK
    var head = i == FACE or i == CROWN
    return 0.0 if skin else (
        0.72 if dark else (0.3 if mark else (0.5 if head else 0.85))
    )


def lion_palette(t: Traits) raises -> Palette:
    """Return one lion's palette: the tawny coat, warmed and lightened.

    A cub's body colors fade toward a grayer natal coat. The white lion
    bleaches toward cream but keeps its dark lips and lid margins. The
    nose leather darkens with age.

    Args:
        t: The individual.

    Returns:
        The palette, in linear light.

    Raises:
        Error: If the palette tables differ in length.
    """
    var names = _swatches()
    var hexes = _hexes()
    if len(names) != len(hexes):
        raise Error("The lion's palette tables differ in length")
    var k = t.get("coatWarmth", 0.0)
    var l = t.get("coatLightness", 0.0)
    var juv = t.juvenile()
    var white = t.variant == WHITE
    var cub = srgb(hexes[CUB_BODY])
    var cream = srgb(hexes[WHITE_BODY])
    var pal = Palette()
    for i in range(len(names)):
        var c = srgb(hexes[i])
        if not _bare(i):
            c = V3(
                c.x * (1.0 + 0.18 * k + l),
                c.y * (1.0 + 0.04 * k + l),
                c.z * (1.0 - 0.2 * k + l),
            )
            var y = 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z
            c = V3(
                max(0.0, y + (c.x - y) * 1.15),
                max(0.0, y + (c.y - y) * 1.15),
                max(0.0, y + (c.z - y) * 1.15),
            )
        var natal = (
            i == DORSAL
            or i == FLANK
            or i == LEG_OUTER
            or i == FACE
            or i == CROWN
        )
        if natal:
            c = mix3(c, cub, 0.6 * juv)
        if white:
            c = mix3(c, cream, _white_amount(i))
        pal.set(names[i], c)
    var age = clamp(t.get("noseDark", 0.3), 0.0, 1.0)
    pal.set("nosePink", mix3(srgb(0xB0877C), srgb(0x7C5E58), age))
    if white:
        pal.set("nosePink", srgb(0xB3928A))
        pal.set("noseDark", srgb(0x5E4844))
    return pal^


def _face_of(p: V3, hw: Float64) -> V3:
    # A reference point in face units.
    var hx = (p.x - HEAD_O.x) / hw / HS
    var hy = (p.y - HEAD_O.y) / HS
    var hz = (p.z - HEAD_O.z) / HS
    return V3(hx / FACE_X, (hy - FACE_EY) / FACE_E, (hz - FACE_EZ) / FACE_E)


def _mask_half(y: Float64, male: Bool) -> Float64:
    # The face mask's half width at height `y`, in face units.
    var ys: List[Float64] = [0.7, 0.3, 0.0, -0.3, -0.6, -0.9, -1.2, -1.5, -1.8]
    var ws: List[Float64] = [
        0.74,
        0.8,
        0.78,
        0.71,
        0.64,
        0.6,
        0.57,
        0.5,
        0.44,
    ]
    if not male:
        ys = [0.7, 0.3, 0.0, -0.5, -0.9, -1.2, -1.5, -1.8]
        ws = [0.88, 0.92, 0.92, 0.84, 0.72, 0.64, 0.56, 0.5]
    if y >= ys[0]:
        return ws[0]
    for i in range(1, len(ys)):
        if y >= ys[i]:
            return ws[i] + (ws[i - 1] - ws[i]) * (y - ys[i]) / (
                ys[i - 1] - ys[i]
            )
    return ws[len(ws) - 1]


def _ruff_of(f: V3, male: Bool) -> Float64:
    # Zero on the face, one on the cheek ruff beside and behind it.
    var t = abs(f.x) - _mask_half(f.y, male)
    var side = smoothstep(-0.14, 0.3, t) if male else smoothstep(-0.1, 0.32, t)
    var behind = (
        smoothstep(-0.75, -1.05, f.z)
        * smoothstep(0.35, 0.6, abs(f.x))
        * smoothstep(0.75, 0.45, f.y)
    )
    return max(side, behind)


def _ruff_pale(f: V3, male: Bool) -> Float64:
    var t = abs(f.x) - _mask_half(f.y, male)
    var fade = 1.0 - smoothstep(0.3, 0.65, t) if male else 1.0
    return _ruff_of(f, male) * fade


def _rbox(
    x: Float64, y: Float64, cy: Float64, hx: Float64, hy: Float64, r: Float64
) -> Float64:
    # A rounded box's signed distance in the face plane.
    return rect_distance(abs(x) - hx + r, abs(y - cy) - hy + r) - r


def _smin(a: Float64, b: Float64, k: Float64) -> Float64:
    var h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b + (a - b) * h - k * h * (1.0 - h)


def _tail_along(p: V3) -> Tuple[Float64, V3]:
    # How far along the tail a point lies, zero at its root and one at its
    # tip, and the tail's direction there.
    var angles = _tail_angles()
    var lens = _tail_lens()
    var a = TAIL_BASE
    var run = 0.0
    var total = 0.0
    for i in range(TAIL_SEGS):
        total += lens[i]
    var best = 1e9
    var at = 0.0
    var dir = V3(0, 0, -1)
    for i in range(TAIL_SEGS):
        var ang = angles[i] * pi / 180.0
        var d = V3(0, sin(ang), -cos(ang))
        var b = a + d * lens[i]
        var u = clamp(dot(p - a, d) / lens[i], 0.0, 1.0)
        var gap = length(p - (a + d * (u * lens[i])))
        var closer = gap < best
        best = gap if closer else best
        at = run + u * lens[i] if closer else at
        if closer:
            dir = d
        run += lens[i]
        a = b
    return (at / total, dir)


def _spots(
    p: V3, radius: Float64, seed: Int, ring: Bool, wob: Float64
) -> Float64:
    # Faint spots or rosettes from cell noise: one where a point is inside.
    var cell = 3.4 * radius
    var c = cells3(p * (1.0 / cell), seed)
    var r = radius / cell * (0.8 + 0.4 * c.id) * wob
    var inside = smoothstep(r * 1.1, r * 0.85, c.nearest)
    var hole = smoothstep(r * 0.4, r * 0.55, c.nearest) if (
        ring and c.id < 0.55
    ) else 1.0
    return inside * hole


def _headish(bone: String) -> Bool:
    return (
        bone == "head"
        or bone == "jaw"
        or bone.startswith("lip")
        or bone.startswith("whisker")
    )


def lion_paint(
    pal: Palette, t: Traits, tag: String, bone: String, s: CoatSample
) -> Paint:
    """Paint one vertex of a lion.

    The lion's coat: a darker back over warm flanks and a cream belly,
    white whisker pads, chin and throat, pale crescents round the eyes,
    dark tear marks, black lids, lip line and mouth-corner spots, a
    pink-to-black nose leather outlined in black, black ear backs, a black
    tail tuft and the male's mane, blond at the face and darkening behind.
    Cubs carry faint rosettes; adults keep a trace of spots on the legs.

    Args:
        pal: The individual's palette.
        t: The individual.
        tag: The tag of the solid the vertex lies on.
        bone: The bone that solid rides.
        s: The vertex.

    Returns:
        The paint.
    """
    ref c = pal.colors
    var p = s.p
    var n = s.n
    var juv = t.juvenile()
    var male = t.male() and juv == 0.0
    var white = t.variant == WHITE
    var seed = Int(t.get("coatSeed", 0.0))
    var off = Float64(seed % 997)
    var nz = fbm3(V3(p.x * 5.0 + off, p.y * 5.0, p.z * 5.0), 3) - 0.5
    var nz2 = vnoise3(V3(p.x * 30.0 + off, p.y * 30.0, p.z * 30.0)) - 0.5
    if tag == "canine":
        return Paint(c[TOOTH], KERATIN)
    if tag == "tongue":
        return Paint(c[TONGUE], SKIN)
    if tag == "pad" or tag == "carpalpad":
        return Paint(c[PAD], SKIN)
    var mane_k = t.get("mane", 0.0)
    var mane_dark = t.get("maneDark", 0.0)
    var col: V3
    var ag = 0.0
    var mark = 1.0
    if tag == "mane":
        col = _mane_color(c, p, n, nz, nz2, bone == "head", male, mane_dark)
        ag = 0.25 + 0.3 * mane_dark
    elif _headish(bone):
        var face = _paint_face(c, t, tag, bone, p, n, male, juv, white)
        if face.surface != FUR:
            return face
        col = face.color
        ag = (0.1 if white else 0.26 - 0.1 * juv) * 0.6
    elif bone.startswith("ear"):
        col = _paint_ear(c, t, p, n, male)
    elif bone.startswith("tail"):
        var ta = _tail_along(p)
        var tt = ta[0]
        var d = ta[1]
        var dors = dot(n, normalize(V3(0, -d.z, d.y)))
        col = mix3(
            mix3(c[FLANK], c[BELLY], 0.4),
            c[FLANK],
            smoothstep(-0.7, 0.3, dors + 0.3 * nz),
        )
        col = mix3(col, c[DORSAL], smoothstep(0.3, 0.9, dors) * 0.5)
        col = mix3(col, c[TAIL_TIP], smoothstep(0.6, 0.85, tt) * 0.6)
        var tuft = 1.0 if tag == "tuft" else smoothstep(
            0.86, 0.93, tt + 0.02 * nz
        )
        col = mix3(col, c[TUFT], tuft)
    else:
        col = _paint_body(c, t, bone, p, n, nz, male, mane_k)
        ag = 0.15 * smoothstep(0.2, 0.9, n.y)
    # The male's crown hair: the mane's front over the forehead.
    var crown_hair = male and mane_k > 0.0 and bone == "head" and tag != "mane"
    if crown_hair:
        var f = _face_of(p, 1.14)
        var axc = abs(f.x)
        var hair = (
            0.56
            + 0.1 * axc * axc
            + 0.26
            * (
                fbm3(V3(p.x * 12.0 + 3.3 + off, p.y * 12.0, p.z * 12.0), 2)
                - 0.5
            )
            + 0.22
            * (
                vnoise3(V3(p.x * 30.0 + 1.9 + off, p.y * 30.0, p.z * 30.0))
                - 0.5
            )
        )
        var tc = f.y - hair + 0.8 * max(0.0, -0.3 - f.z)
        var cw = (
            smoothstep(-0.2, 0.3, tc)
            * smoothstep(-0.45, 0.05, n.y + 0.25 * f.z / 1.5)
            * smoothstep(0.35, -0.15, f.z)
        )
        var back = smoothstep(-0.1, -1.1, f.z)
        var ruff_col = mix3(c[CHIN], c[MANE_BLOND], 0.68 + 0.22 * mane_dark)
        var mc = mix3(
            mix3(c[MANE_BLOND], ruff_col, 0.35),
            mix3(c[MANE_MID], c[MANE_DARK], clamp(mane_dark - 0.3, 0.0, 1.0)),
            clamp(0.15 + 0.55 * mane_dark * back + 0.2 * nz, 0.0, 1.0),
        )
        col = mix3(col, mc, cw * smoothstep(0.2, 0.6, mane_k + 0.3))
    # Faint rosettes: a cub's all over, an adult's on the lower legs.
    var spots_k = 1.0 if juv > 0.0 else t.get("legSpots", 0.2)
    var adult_leg = (
        (bone.startswith("radius") or bone.startswith("tibia"))
        and p.y < 0.34
        and p.y > 0.17
    )
    var cub_skin = juv > 0.0 and tag != "mane"
    var spotted = spots_k > 0.01 and (adult_leg or cub_skin)
    if spotted:
        var radius = 0.018 if is_limb(bone) else (
            0.01 if _headish(bone) else 0.024
        )
        radius *= 1.6 if juv > 0.0 else 1.0
        var wob = 1.0 + 0.25 * nz2
        var sp = _spots(p, radius, seed % 251, juv > 0.0, wob)
        var on_head = _headish(bone) and (
            (p.z - HEAD_O.z) / HS > 0.04 or (p.y - HEAD_O.y) / HS < -0.05
        )
        var k = (
            0.55 if _headish(bone) else 0.36
            * (1.0 - 0.85 * smoothstep(0.1, 0.65, n.y))
        ) if juv > 0.0 else 0.22 * spots_k / 0.2
        sp = 0.0 if on_head else sp
        col = mix3(col, c[CUB_SPOT], clamp(sp * k, 0.0, 1.0))
    var cvh = fbm3(V3(p.x * 3.0 + 5.0 + off, p.y * 3.0, p.z * 3.0), 2) - 0.5
    col = V3(
        col.x * (1.0 + 0.12 * nz + 0.08 * cvh + 0.06 * nz2),
        col.y * (1.0 + 0.1 * nz + 0.06 * nz2),
        col.z * (1.0 + 0.08 * nz - 0.06 * cvh + 0.06 * nz2),
    )
    col = grizzle(col, p, 140.0, 0.05 + 0.25 * ag)
    return Paint(mix3(col, MARK, smoothstep(0.0015, -0.0005, mark)), FUR)


def _mane_color(
    c: List[V3],
    p: V3,
    n: V3,
    nz: Float64,
    nz2: Float64,
    face: Bool,
    male: Bool,
    mane_dark: Float64,
) -> V3:
    # Blond at the face ruff, darkening toward the rear and the lower
    # edge, broken into locks that fall back and down.
    var hz = (p.z - HEAD_O.z) / HS
    var back = clamp(
        smoothstep(0.62, 0.3, p.z) * 0.8
        + smoothstep(0.8, 0.55, p.y) * 0.7
        + 0.35 * nz,
        0.0,
        1.0,
    )
    var ruff = smoothstep(-0.02, -0.12, hz) * 0.5 if face else 0.0
    var mc = mix3(
        c[MANE_BLOND],
        c[MANE_MID],
        clamp(
            (0.3 + 1.1 * mane_dark) * back + 0.35 * mane_dark - ruff * 0.3,
            0.0,
            1.0,
        ),
    )
    mc = mix3(
        mc,
        c[MANE_DARK],
        clamp((mane_dark - 0.25) * 1.8 * back + 0.25 * nz2, 0.0, 1.0),
    )
    if face:
        var f = _face_of(p, 1.14)
        var ruff_col = mix3(c[CHIN], c[MANE_BLOND], 0.68 + 0.22 * mane_dark)
        mc = mix3(
            mc,
            ruff_col,
            _ruff_pale(f, male) * smoothstep(-0.35, -0.02, hz) * 0.5,
        )
    # The pale underside under the jaw and the throat.
    var under = smoothstep(0.62, 0.72, p.z) * smoothstep(-0.2, -0.6, n.y)
    mc = mix3(mc, mix3(c[CHIN], c[MANE_BLOND], 0.4), under * 0.6)
    # Locks: streaks that run down and back with the hair.
    var fall = V3(0, -0.85, -0.5)
    var across = V3(0, 0.5, -0.85)
    var q = V3(p.x * 40.0, dot(p, fall) * 6.0, dot(p, across) * 40.0)
    var lock = fbm3(q, 3) - 0.5
    return mc * (1.0 + 1.1 * lock)


def _paint_body(
    c: List[V3],
    t: Traits,
    bone: String,
    p: V3,
    n: V3,
    nz: Float64,
    male: Bool,
    mane_k: Float64,
) -> V3:
    # The torso, the neck and the legs.
    var up = n.y
    var col = mix3(
        c[LOW_FLANK], c[FLANK], smoothstep(-0.35, 0.3, up + 0.15 * nz)
    )
    col = mix3(col, c[DORSAL], smoothstep(0.35, 0.95, up + 0.2 * nz) * 0.85)
    # A faint darker line along the spine.
    col = mix3(
        col,
        c[CROWN],
        smoothstep(0.05, 0.012, abs(p.x))
        * smoothstep(0.88, 0.97, up)
        * smoothstep(0.35, 0.2, p.z)
        * smoothstep(-0.8, -0.68, p.z)
        * 0.55,
    )
    var neck = bone == "neck1" or bone == "neck2"
    var w: Float64
    if neck:
        w = clamp(
            smoothstep(0.1, -0.5, up) * smoothstep(-0.4, 0.3, n.z)
            + smoothstep(0.78, 0.66, p.y) * 0.5,
            0.0,
            1.0,
        )
    else:
        w = smoothstep(-0.25, -0.9, up)
        var chest = (
            smoothstep(0.7, 0.52, p.y)
            * smoothstep(0.1, 0.045, abs(p.x))
            * smoothstep(-0.3, 0.4, n.z)
        )
        w = max(w, chest if p.z > 0.3 else 0.0)
        w *= smoothstep(0.8, 0.62, p.y) * 0.55 + 0.45
    var legness = smoothstep(0.66, 0.42, p.y) if is_limb(bone) else 0.0
    if legness > 0.0:
        var side = 1.0 if p.x >= 0.0 else -1.0
        var inner = smoothstep(0.1, -0.6, n.x * side)
        var wl = (
            inner * 0.75 * smoothstep(0.12, 0.4, p.y)
            + smoothstep(-0.3, -0.85, up) * 0.5
        )
        w = w + (wl - w) * legness
    var maned = male and mane_k > 0.0
    if maned:
        # No pale bib just below a mane: the chest there is mane colored.
        w *= 1.0 - 0.8 * smoothstep(0.3, 0.5, p.z) * smoothstep(0.5, 0.75, p.y)
    w = clamp(w, 0.0, 1.0)
    col = mix3(col, c[BELLY], w)
    if neck:
        # The white of the chin carries on down the upper throat.
        col = mix3(col, c[CHIN], w * smoothstep(0.5, 0.64, p.z) * 0.8)
    if legness > 0.0:
        var lc = mix3(c[LEG_OUTER], c[LEG_INNER], smoothstep(0.1, 0.7, w))
        lc = mix3(lc, col, smoothstep(0.45, 0.65, p.y) * 0.6)
        var paw = bone.startswith("fpaw") or bone.startswith("hpaw")
        if paw:
            lc = c[PAW]
        col = mix3(col, lc, legness)
    var behind_mane = male and mane_k > 0.0 and p.z > 0.25 and not is_limb(bone)
    if behind_mane:
        # The darker hair just behind and below the mane.
        var near = smoothstep(0.3, 0.45, p.z) * (
            1.0 - 0.5 * smoothstep(0.3, -0.5, up)
        )
        var dark = clamp(t.get("maneDark", 0.0), 0.0, 1.0)
        col = mix3(
            col,
            mix3(c[MANE_MID], c[MANE_DARK], clamp(dark * 0.8, 0.0, 1.0)),
            near * 0.45 * clamp(0.35 + dark, 0.0, 1.0),
        )
    return col


def _paint_ear(c: List[V3], t: Traits, p: V3, n: V3, male: Bool) -> V3:
    # A tawny rim round a shallow pale bowl; black backs with a tawny
    # patch low in their middle; tawny at the base.
    var s = 1.0 if p.x > 0.0 else -1.0
    var eb = on_side(_ear_base(), s)
    var et = on_side(_ear_tip(), s)
    var eu = normalize(et - eb)
    var ht = dot(p - eb, eu) / length(et - eb)
    var facing = normalize(V3(0.7 * s, 0.05, 1))
    var front = dot(n, facing)
    var bowl = (
        smoothstep(0.2, 0.55, front)
        * smoothstep(0.12, 0.3, ht)
        * (smoothstep(0.85, 0.6, ht))
    )
    var fc = mix3(c[FACE], c[EAR_INNER], bowl * 0.9)
    var cup = exp(-((ht - 0.3) / 0.16) * ((ht - 0.3) / 0.16))
    var mk = 1.0 if male else 0.0
    fc = mix3(
        fc,
        c[EAR_CUP],
        bowl * cup * smoothstep(0.35, 0.85, front) * 0.42 * (1.0 - 0.7 * mk),
    )
    if male:
        fc = mix3(fc, mix3(c[EAR_CUP], c[MANE_BLOND], 0.5), bowl * 0.75)
    var ear_dark = t.get("earDark", 1.0)
    var bc = mix3(c[EAR_BACK_CENTER], c[EAR_BACK], 0.55 + 0.45 * ear_dark)
    var mid = exp(-((ht - 0.3) / 0.2) * ((ht - 0.3) / 0.2))
    bc = mix3(
        bc, c[EAR_BACK_CENTER], mid * smoothstep(-0.2, -0.75, front) * 0.55
    )
    var back_w = smoothstep(-0.12, -0.48, front) * smoothstep(0.08, 0.22, ht)
    var col = mix3(fc, bc, back_w)
    if male:
        col = mix3(
            col,
            bc,
            smoothstep(0.32, 0.04, front)
            * (1.0 - bowl)
            * smoothstep(0.3, 0.55, ht)
            * (0.35 + 0.45 * ear_dark)
            * (1.0 - back_w),
        )
    return mix3(col, c[CROWN], smoothstep(0.16, 0.04, ht))


def _lid_distance(t: Traits, p: V3) -> Float64:
    # The distance from a point to the nearer eye's aperture rim, in the
    # aperture's plane, or far when the point is behind the eye.
    var e = lion_eye(t)
    var s = 1.0 if p.x > HEAD_O.x else -1.0
    var ef = eye_frame_of(e, HEAD_O, s)
    var q = aperture_local(e, ef, p)
    var de = abs(almond_distance(q.x, q.y, e.big_r, e.d))
    return de if q.z > -0.3 * e.r else 1.0


def _paint_face(
    c: List[V3],
    t: Traits,
    tag: String,
    bone: String,
    p: V3,
    n: V3,
    male: Bool,
    juv: Float64,
    white: Bool,
) -> Paint:
    # The head and the jaw, in face units.
    var hw = 1.12 + (0.02 if male else 0.0) - 0.04 * juv
    var f = _face_of(p, hw)
    var ax = abs(f.x)
    var jaw = bone == "jaw"
    var mane_dark = t.get("maneDark", 0.0)
    var col = mix3(c[FACE], c[CROWN], smoothstep(-0.15, 0.56, f.y) * 0.6)
    var pad_low = smoothstep(-0.84, -1.02, f.y)
    var whisker = (
        0.0 if jaw else mirrored_blob(
            f, V3(0.29, max(f.y, -1.16), 0.78), V3(0.34, 0.26, 0.5)
        )
        * pad_low
    )
    var lip = mirrored_blob(f, V3(0, -1.3, 1.0), V3(0.3, 0.14, 0.24))
    var under_eye = (
        smoothstep(
            0.12,
            0.5,
            mirrored_blob(f, V3(0.47, -0.21, 0.1), V3(0.25, 0.105, 0.45)),
        )
        * 0.95
    )
    var above_eye = (
        smoothstep(
            0.15,
            0.6,
            mirrored_blob(f, V3(0.49, 0.15, 0.1), V3(0.17, 0.055, 0.42)),
        )
        * 0.6
    )
    var chin_g = exp(-(ax / 0.3) * (ax / 0.3))
    var chin_w = (
        0.95
        * chin_g
        * max(
            smoothstep(0.05, 0.5, f.z),
            smoothstep(-0.35, -0.8, n.y) * smoothstep(-0.45, 0.25, f.z),
        ) if jaw else 0.0
    )
    var throat_k = 0.55 if jaw else 0.7 + 0.15 * smoothstep(
        -0.9, 0.1, f.z
    ) * exp(-(ax / 0.4) * (ax / 0.4))
    var throat_w = (
        smoothstep(-1.3, -1.6, f.y) * smoothstep(0.1, -0.55, n.y) * throat_k
    )
    if jaw:
        col = mix3(col, c[MUZZLE], 0.28 + 0.4 * smoothstep(-0.2, 0.3, f.z))
    var w = clamp(
        max(
            max(
                smoothstep(0.06, 0.5, whisker)
                * mix(0.72, 1.0, smoothstep(-0.98, -1.14, f.y)),
                lip,
            ),
            max(max(under_eye, above_eye), max(chin_w, throat_w)),
        ),
        0.0,
        1.0,
    )
    var eye_pale = 0.5 if under_eye + above_eye > whisker else 0.0
    col = mix3(col, mix3(c[MUZZLE], c[EYE_PATCH], eye_pale), w)
    # Dark tear streaks from the inner eye corners down beside the bridge.
    var tq = clamp(-f.y - 0.08, 0.0, 0.45)
    var tx = 0.325 + 0.03 * tq + 0.3 * tq * tq
    var tw = (ax - tx) / (0.075 - 0.055 * tq)
    var tear = (
        exp(-tw * tw)
        * smoothstep(-0.02, -0.12, f.y)
        * smoothstep(-0.62, -0.32, f.y)
        * smoothstep(-0.15, 0.1, f.z)
    )
    col = mix3(col, c[TEAR], tear * (1.0 if white else 0.95))
    col = mix3(
        col,
        c[CROWN],
        mirrored_blob(f, V3(0.45, -0.6, 0.45), V3(0.22, 0.25, 0.4))
        * (1.0 - pad_low)
        * 0.55,
    )
    if not jaw:
        col = mix3(
            col,
            mix3(c[EYE_PATCH], c[FACE], 0.3),
            smoothstep(-0.28, -0.8, f.y)
            * smoothstep(0.36, 0.6, ax)
            * smoothstep(-1.2, -0.6, f.z)
            * (1.0 - whisker)
            * (0.3 if white else 0.35),
        )
    # The dark spots over the eyes and a darker bridge.
    col = mix3(
        col,
        mix3(c[BROW_MARK], c[TEAR], 0.35),
        smoothstep(
            0.08,
            0.55,
            mirrored_blob(f, V3(0.36, 0.29, 0.1), V3(0.085, 0.06, 0.5)),
        )
        * 0.9,
    )
    if male:
        col = mix3(
            col,
            mix3(c[CROWN], c[BROW_MARK], 0.35),
            max(
                mirrored_blob(f, V3(0, 0.35, -0.15), V3(0.42, 0.42, 0.7)),
                mirrored_blob(f, V3(0, -0.35, 0.55), V3(0.2, 0.36, 0.45))
                * (1.0 - pad_low),
            )
            * 0.25,
        )
    # A thin dark furrow up the middle of the forehead.
    col = mix3(
        col,
        c[BROW_MARK],
        exp(-(ax / 0.032) * (ax / 0.032))
        * smoothstep(0.12, 0.3, f.y)
        * smoothstep(0.9, 0.62, f.y)
        * smoothstep(-0.7, -0.4, f.z)
        * (0.8 if white else 0.65),
    )
    col = mix3(
        col,
        c[CROWN],
        mirrored_blob(f, V3(0, -0.3, 0.62), V3(0.2, 0.34, 0.4))
        * (1.0 - pad_low)
        * 0.6,
    )
    var em = FACE_E * HS
    var mark = 1.0
    # The liner's wing: a black line back from the outer eye corner.
    var wing = _wing_distance(V3(ax, f.y, f.z))
    mark = min(mark, (wing[0] - 0.03 * (1.0 - wing[1])) * em)
    # The whisker-base dots: four rows of small black spots on each pad.
    if whisker > 0.15:
        var dd = 1.0
        for row in range(4):
            var dots = 5 if row == 1 or row == 3 else (4 if row == 0 else 6)
            for i in range(dots):
                var x = 0.12 + 0.022 * Float64(row) + 0.058 * Float64(i)
                var y = -0.98 - 0.086 * Float64(row) - 0.1 * (x - 0.13)
                var dx = (ax - x) * FACE_X * hw * HS
                var dy = (f.y - y) * FACE_E * HS
                dd = min(dd, sqrt(dx * dx + dy * dy) - 0.0025)
        col = mix3(col, c[WHISKER_DOT], smoothstep(0.0012, -0.0006, dd) * 0.9)
    # The black spot at the corner of the mouth.
    var corner = V3(ax - 0.55, f.y + 1.37, f.z - 0.1)
    mark = min(mark, length(corner) * em - 0.0055)
    # The cheek ruff: a lioness's sideburns, a male's pale ruff.
    var ruff_col = mix3(
        c[CHIN], c[MANE_BLOND], 0.68 + 0.22 * mane_dark
    ) if male else mix3(c[FACE], c[EYE_PATCH], 0.2)
    var ruff = 0.0 if jaw else _ruff_pale(f, male)
    col = mix3(col, ruff_col, ruff * (0.45 if male else 0.7))
    # The eye rims: black lid margins, a pale crescent under the lower lid.
    var de = _lid_distance(t, p)
    var lm = 1.0 - 0.6 * juv
    var crescent = de < 0.014 and f.y < -0.02
    if crescent:
        col = mix3(
            col,
            c[EYE_PATCH],
            0.8
            * smoothstep(0.003, 0.0048, de)
            * smoothstep(0.0125, 0.0075, de)
            * smoothstep(-0.02, -0.07, f.y),
        )
    var ring = juv > 0.0 and de < 0.02
    if ring:
        col = mix3(
            col,
            c[EYE_PATCH],
            0.45 * smoothstep(0.0025, 0.004, de) * smoothstep(0.02, 0.008, de),
        )
    if de < 0.0024 * lm:
        return Paint(c[LIP_DARK], SKIN)
    mark = min(mark, de - 0.0034 * lm)
    # The nose leather: a broad T outlined in black.
    var y_top = -0.79 - 0.12 * ax * ax
    var bar = max(_rbox(ax, f.y, -0.89, 0.34, 0.105, 0.08), f.y - y_top)
    var stem = _rbox(ax, f.y, -1.05, 0.058, 0.085, 0.05)
    var d_in = -_smin(bar, stem, 0.075)
    var near_nose = (
        not jaw and f.z > 0.72 and ax < 0.62 and f.y > -1.3 and f.y < -0.45
    )
    if near_nose:
        var wr = 0.0015 + 0.0022 * smoothstep(0.03, 0.12, y_top - f.y)
        var dm = d_in * em
        mark = min(mark, abs(dm - wr / 2.0) - wr / 2.0 if dm > 0.0 else -dm)
    var leather = near_nose and d_in > 0.0 and (tag == "nose" or f.z > 0.95)
    if leather:
        var age = t.get("noseDark", 0.3)
        var lc = mix3(
            c[NOSE_PINK], c[NOSE_DARK], clamp(0.02 + 0.7 * age, 0.0, 1.0)
        )
        lc = mix3(
            lc,
            c[NOSE_DARK],
            clamp(
                0.7 * smoothstep(0.07, 0.0, d_in)
                + 0.3 * smoothstep(-0.95, -1.08, f.y),
                0.0,
                1.0,
            ),
        )
        lc = mix3(
            lc,
            mix3(c[NOSE_PINK], c[FACE], 0.15),
            0.35
            * smoothstep(0.03, 0.09, d_in)
            * smoothstep(-0.95, -0.84, f.y)
            * smoothstep(0.3, 0.1, ax)
            * (1.0 - age),
        )
        var nu = (ax - 0.19) * 0.95 + (f.y + 0.93) * 0.31
        var nw = -(ax - 0.19) * 0.31 + (f.y + 0.93) * 0.95
        var dno = sqrt((nu / 0.11) * (nu / 0.11) + (nw / 0.058) * (nw / 0.058))
        lc = mix3(lc, c[NOSTRIL], smoothstep(1.25, 0.85, dno))
        lc = mix3(
            lc,
            c[NOSE_DARK],
            smoothstep(0.03, 0.008, ax) * smoothstep(-0.96, -1.02, f.y) * 0.8,
        )
        return Paint(mix3(lc, MARK, smoothstep(0.0015, -0.0005, mark)), NOSE)
    # The philtrum: a black line from the leather down to the lip.
    var philtrum = not jaw and ax < 0.08 and f.y < -1.1 and f.z > 0.85
    if philtrum:
        mark = min(
            mark,
            ax * em - 0.0016 + 0.004 * smoothstep(-1.33, -1.41, f.y),
        )
    # The lip line: the black underside of the hanging upper lip, and the
    # jaw's rim inside it.
    if not jaw:
        var lip_band = (
            smoothstep(-0.45, -0.75, n.y)
            * smoothstep(-1.4, -1.47, f.y)
            * smoothstep(-0.3, -0.1, f.z)
            * smoothstep(0.7, 0.6, ax)
        )
        if lip_band > 0.5:
            return Paint(c[LIP_DARK], SKIN)
    else:
        var rim = smoothstep(0.35, 0.7, n.y) * smoothstep(-1.45, -1.3, f.y)
        if rim > 0.5:
            return Paint(mix3(c[LIP_DARK], c[MOUTH], 0.3), SKIN)
    col = mix3(col, MARK, smoothstep(0.0015, -0.0005, mark))
    return Paint(col, FUR)


def _wing_distance(f: V3) -> Tuple[Float64, Float64]:
    # The distance in face units from a point to the liner's wing, a
    # segment back and down from the outer eye corner, and where along it.
    var o = WING_O
    var d = V3(0.19, -0.06, -0.12)
    var u = clamp(dot(f - o, d) / dot(d, d), 0.0, 1.0)
    return (length(f - (o + d * u)), u)
