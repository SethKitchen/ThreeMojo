# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The red fox, Vulpes vulpes: procedural-animals' `species/fox/`.

A small, light, long-legged canid with a narrow pointed muzzle, big
black-backed ears, vertical-slit pupils, black stockings, a white bib
and a huge white-tipped brush. The reference adult stands 0.40 m at the
withers. Morphs are red (70 %), cross (12 %), silver (8 %) and urban
(10 %), drawn from their own hashed stream.
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
    band,
    grizzle,
    mix3,
    palette_of,
    srgb,
)
from extensions.animals.parts import JAW
from extensions.sdf.sculpt import ell_y
from extensions.animals.kit import (
    EyeSpec,
    eye_frame_of,
    head_local,
    is_limb,
    is_front_limb,
    hashed_stream,
    mirrored_ell_bottom,
)
from extensions.animals.noise import fbm3, vnoise3
from extensions.animals.options import AnimalOptions, AnimalRandom
from extensions.animals.rig import Rig, quadruped_bones, tail_chain
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
from extensions.animals.warp import length_warp, legs_warp, scale_about_warp
from std.math import cos, exp, pi, pow, sin
from extensions.sdf.distance import segment_param

comptime TAIL_SEGS = 10
# The head's origin, mid cranium between the eyes and the ears.
comptime HEAD_O = V3(0.0, 0.418, 0.352)
# The head-local scale: landmarks are for a 0.25 m skull.
comptime HS = 0.66
# Where the muzzle starts, head-local. Muzzle length acts ahead of it.
comptime MUZZLE_Z0 = 0.035
# The finest cell, at the `HERO` tier: the jaw's cell in the original.
comptime CELL = 0.00135

# The morphs, in procedural-animals' order.
comptime RED = 0
comptime CROSS = 1
comptime SILVER = 2
comptime URBAN = 3

# The ear, head-local: its base and its direction to the tip.
comptime EAR_BASE = V3(0.046, 0.048, -0.034)
comptime EAR_DIR = V3(0.05, 0.118, -0.006)
# The tail's root.
comptime TAIL_BASE = V3(0.0, 0.336, -0.19)


def fox_variant_names() -> List[String]:
    """Return the fox's color morphs.

    Returns:
        Red, cross, silver and urban.
    """
    return [String("red"), "cross", "silver", "urban"]


def fox_traits(mut r: AnimalRandom, options: AnimalOptions) raises -> Traits:
    """Draw one fox: procedural-animals' `variation`.

    Dog foxes are about 15 % heavier, with a broader head and muzzle and a
    fuller ruff. Kits are about half size, with a big domed head, a short
    muzzle, very big ears, short legs and brush and a woolly sandy coat.

    Args:
        r: The individual's stream.
        options: The caller's sex, age and morph.

    Returns:
        The traits.

    Raises:
        Error: If the requested morph is not one of the four.
    """
    var sex = pick_sex(options.sex, r)
    var age = pick_age(options.age)
    var m = hashed_stream(options.seed, 0x3C6EF372, 0x9E3779B1, 0x5BE0CD19)
    for _ in range(3):
        _ = m.next()
    var weights: List[Float64] = [0.7, 0.12, 0.08, 0.1]
    var variant = pick_variant(options.variant.value, weights, m.next())
    var t = Traits(sex, age, variant)
    var juv = t.juvenile()
    var male = t.male()
    var size = (
        (1.04 if male else 0.96)
        * (1.0 + 0.04 * r.g())
        * (0.55 if juv > 0.0 else 1.0)
    )
    var legs = 1.0 + 0.03 * r.g() - 0.1 * juv
    var head = (1.03 if male else 0.98) * (1.0 + 0.02 * r.g())
    t.set("coatSeed", Float64(Int(r.next() * 1e6)))
    t.set("size", size)
    t.set(
        "muzzle",
        (1.02 if male else 0.99)
        * (1.0 + 0.04 * r.g())
        * (0.7 if juv > 0.0 else 1.0),
    )
    t.set(
        "headW",
        (1.05 if male else 0.98)
        * (1.0 + 0.025 * r.g())
        * (1.06 if juv > 0.0 else 1.0),
    )
    t.set("ear", (1.0 + 0.05 * r.g()) * (1.12 if juv > 0.0 else 1.0))
    t.set("eyeK", 1.18 if juv > 0.0 else 1.0)
    t.set("tail", (1.0 + 0.05 * r.g()) * (0.72 if juv > 0.0 else 1.0))
    t.set("tailBrush", (1.0 + 0.07 * r.g()) * (0.75 if juv > 0.0 else 1.0))
    t.set("ruff", (1.1 if male else 0.9) + 0.12 * r.g() - 0.2 * juv)
    t.set(
        "slim",
        (1.04 if male else 0.97)
        * (1.0 + 0.03 * r.g())
        * (1.08 if juv > 0.0 else 1.0),
    )
    t.set("boneK", 1.12 if juv > 0.0 else 1.0)
    t.set("pawK", 1.15 if juv > 0.0 else 1.0)
    t.set("bib", 1.0 + 0.25 * r.g())
    # Every draw is made whatever the morph: the silver fox's stockings
    # ignore theirs.
    var stockings = max(0.2, 1.0 + 0.45 * r.g())
    t.set("stockings", 1.0 if variant == SILVER else stockings)
    # Most foxes have a white tail tip.
    var plain = m.next() < 0.08 and variant == RED
    t.set("tailTip", 0.0 if plain else 0.75 + 0.5 * m.next())
    t.set("tear", 0.7 + 0.5 * m.next())
    t.set("coatWarmth", 1.3 * r.g())
    t.set("coatLightness", 0.16 * r.g())
    t.set("minThick", 0.0022)
    t.warps.add(legs_warp(legs, 0.25))
    t.warps.add(length_warp(1.0 + 0.03 * r.g() - 0.05 * juv, -0.19, 0.24))
    t.warps.add(
        scale_about_warp(HEAD_O, head * (1.3 if juv > 0.0 else 1.0), 0.05, 0.12)
    )
    if juv > 0.0:
        # Big kit paws.
        for paw in [
            V3(0.028, 0.015, 0.2),
            V3(-0.028, 0.015, 0.2),
            V3(0.033, 0.015, -0.2),
            V3(-0.033, 0.015, -0.2),
        ]:
            t.warps.add(scale_about_warp(paw, 1.18, 0.018, 0.04))
    return t^


def fox_eye(t: Traits) -> EyeSpec:
    """Return the fox's left eye: an oblique almond, set high and close.

    Args:
        t: The individual. Kits have relatively bigger eyes.

    Returns:
        The eye, head-local.
    """
    var k = t.get("eyeK")
    return EyeSpec(
        V3(0.035 * t.get("headW") * HS, 0.022 * HS, 0.035 * HS),
        0.0098 * k,
        0.0021 * k,
        0.2,
        0.05,
        0.0012 * k,
        0.012 * k,
        0.0062 * k,
        -0.0006 * k,
        24.0 * pi / 180.0,
        0.006 * k,
        0.0082 * k,
    )


def _hl(t: Traits, v: V3) -> V3:
    return head_local(HEAD_O, HS, MUZZLE_Z0, t.get("muzzle"), t.get("headW"), v)


def _hr(t: Traits, r: V3) -> V3:
    return V3(r.x * t.get("headW") * HS, r.y * HS, r.z * HS)


def _ear_tip(t: Traits, base: V3) -> V3:
    var ek = t.get("ear")
    return V3(
        base.x + EAR_DIR.x * ek * HS * t.get("headW"),
        base.y + EAR_DIR.y * ek * HS,
        base.z + EAR_DIR.z * ek * HS,
    )


def _tail_angles() -> List[Float64]:
    return [-12, -18, -23, -26, -28, -29, -29, -28, -27, -26]


def _tail_weights() -> List[Float64]:
    return [1.06, 1.06, 1.05, 1.03, 1.01, 0.99, 0.97, 0.95, 0.94, 0.94]


def fox_rig(t: Traits) raises -> Rig:
    """Return the fox's skeleton in bind pose.

    The front is very narrow: the forefeet stand about 6 cm apart. The
    tail is held out behind in a shallow downward curve.

    Args:
        t: The individual.

    Returns:
        The rig.

    Raises:
        Error: If a bone names a missing joint.
    """
    var rig = Rig()
    rig.set("nose", _hl(t, V3(0.0, -0.014, 0.16)))
    rig.set("occiput", _hl(t, V3(0.0, 0.02, -0.095)))
    rig.set("neckMid", V3(0.0, 0.378, 0.27))
    rig.set("neckBase", V3(0.0, 0.335, 0.245))
    rig.set("chestMid", V3(0.0, 0.338, 0.14))
    rig.set("thoraxRear", V3(0.0, 0.345, 0.03))
    rig.set("lumbarMid", V3(0.0, 0.35, -0.065))
    rig.set("lumbosacral", V3(0.0, 0.345, -0.135))
    rig.set("tailBase", TAIL_BASE)
    rig.set("scapTopL", V3(0.022, 0.372, 0.2))
    rig.set("shoulderL", V3(0.038, 0.283, 0.252))
    rig.set("elbowL", V3(0.034, 0.19, 0.184))
    rig.set("wristL", V3(0.029, 0.067, 0.19))
    rig.set("mcpL", V3(0.028, 0.019, 0.197))
    rig.set("ftoeL", V3(0.028, 0.0085, 0.222))
    rig.set("hipL", V3(0.036, 0.3, -0.168))
    rig.set("kneeL", V3(0.046, 0.18, -0.118))
    rig.set("hockL", V3(0.035, 0.078, -0.212))
    rig.set("mtpL", V3(0.033, 0.019, -0.205))
    rig.set("htoeL", V3(0.033, 0.0085, -0.18))
    rig.set("jawHinge", _hl(t, V3(0.0, -0.034, -0.03)))
    rig.set("jawTip", _hl(t, V3(0.0, -0.057, 0.127)))
    var ear = _hl(t, EAR_BASE)
    rig.set("earBaseL", ear)
    rig.set("earTipL", _ear_tip(t, ear))
    var tk = t.get("tail") * 0.4
    var w = _tail_weights()
    var ws = 0.0
    for x in w:
        ws += x
    var lens = List[Float64]()
    for x in w:
        lens.append(x / ws * tk)
    tail_chain(rig, "tailBase", _tail_angles(), lens)
    rig.mirror_joints()
    quadruped_bones(rig, TAIL_SEGS)
    return rig^


def _tail_radius(t: Float64, tb: Float64) -> Float64:
    # The brush: a huge round cylinder, thick almost to the end.
    var root = 0.021 + (0.027 - 0.021) * (t / 0.15)
    var mid = 0.027 + (0.033 - 0.027) * ((t - 0.15) / 0.4)
    var tip = 0.033 - 0.017 * pow(max(t - 0.55, 0.0) / 0.45, 1.8)
    return tb * (root if t < 0.15 else (mid if t < 0.55 else tip))


def fox_sculpt(mut m: SdfModel, rig: Rig, t: Traits) raises:
    """Sculpt the fox: procedural-animals' `sculptFox`, primitive for
    primitive.

    A slim, narrow-chested body with a tucked belly on long thin legs, a
    long narrow muzzle, big erect ears and a huge cylindrical brush. The
    winter coat is partly sculpted as volume: the cheek ruff, the chest
    fluff and the brush.

    Args:
        m: The sculpt to add to.
        rig: The fox's rig in bind pose.
        t: The individual.

    Raises:
        Error: If the rig lacks a joint or a bone, or the sculpt refuses
            a primitive.
    """
    var eye = fox_eye(t)
    var hw = t.get("headW")
    var ruff = t.get("ruff")
    var juv = t.juvenile()
    var slim = t.get("slim")

    # TORSO: a narrow keeled chest, a level back, a tucked belly.
    _ = m.ell(
        "ribcage",
        rig.bone("spine3"),
        V3(0, 0.296, 0.1),
        V3(0.048 * slim, 0.082, 0.125),
        axis=normalize(V3(0, 0.12, -1)),
        k=0,
    )
    var b = rig.bone("chest")
    _ = m.ell(
        "brisket",
        b,
        V3(0, 0.24, 0.185),
        V3(0.031 * slim, 0.042, 0.065),
        axis=normalize(V3(0, -0.35, 1)),
        k=0.035,
    )
    _ = m.ell(
        "pectoral",
        b,
        V3(0, 0.272, 0.25),
        V3(0.034 * slim, 0.042, 0.034),
        k=0.03,
    )
    _ = m.ell(
        "withers",
        b,
        V3(0, 0.372, 0.172),
        V3(0.026 * slim, 0.03, 0.075),
        axis=normalize(V3(0, -0.1, 1)),
        k=0.035,
    )
    _ = m.ell(
        "back",
        rig.bone("spine3"),
        V3(0, 0.37, 0.03),
        V3(0.034 * slim, 0.028, 0.1),
        k=0.035,
    )
    _ = m.ell(
        "abdomen",
        rig.bone("spine2"),
        V3(0, 0.308, -0.045),
        V3(0.04 * slim, 0.05, 0.095),
        axis=normalize(V3(0, 0.3, -1)),
        k=0.04,
    )
    b = rig.bone("spine1")
    _ = m.ell(
        "loin", b, V3(0, 0.362, -0.085), V3(0.031 * slim, 0.027, 0.085), k=0.03
    )
    _ = m.ell(
        "flank", b, V3(0, 0.318, -0.115), V3(0.033 * slim, 0.034, 0.055), k=0.03
    )
    b = rig.bone("pelvis")
    _ = m.ell(
        "pelvis",
        b,
        V3(0, 0.333, -0.17),
        V3(0.036 * slim, 0.046, 0.065),
        k=0.035,
    )
    _ = m.ell(
        "croup", b, V3(0, 0.36, -0.165), V3(0.028 * slim, 0.022, 0.06), k=0.025
    )
    for s in [1.0, -1.0]:
        _ = m.ell(
            "rump",
            b,
            V3(0.022 * s * slim, 0.31, -0.212),
            V3(0.022, 0.038, 0.028),
            k=0.025,
        )
    # Shoulder fluff over the withers.
    _ = m.ell(
        "cape",
        rig.bone("chest"),
        V3(0, 0.362, 0.2),
        V3(0.04 * slim, 0.036, 0.075),
        axis=normalize(V3(0, 0.25, 1)),
        k=0.04,
    )

    # NECK: slim, wrapped in the ruff.
    var n1 = rig.bone("neck1")
    var n2 = rig.bone("neck2")
    _ = m.cone(
        "neck",
        n1,
        V3(0, 0.312, 0.228),
        V3(0, 0.37, 0.278),
        0.043,
        0.035,
        k=0.035,
    )
    _ = m.cone(
        "neck", n2, V3(0, 0.37, 0.278), V3(0, 0.41, 0.315), 0.035, 0.03, k=0.025
    )
    _ = m.ell(
        "nape",
        n1,
        V3(0, 0.4, 0.265),
        V3(0.024, 0.018, 0.058),
        axis=normalize(V3(0, 0.55, 1)),
        k=0.025,
    )
    _ = m.ell(
        "throat",
        n2,
        V3(0, 0.34, 0.31),
        V3(0.025, 0.032, 0.036),
        axis=normalize(V3(0, 0.8, 0.6)),
        k=0.04,
    )
    # The ruff: a fluffy collar, fullest on the white throat and chest.
    var rf = 0.8 + 0.2 * ruff
    _ = m.ell(
        "ruff",
        n1,
        V3(0, 0.335, 0.27),
        V3(0.042 * rf, 0.048 * rf, 0.05),
        axis=normalize(V3(0, 0.6, 1)),
        k=0.045,
    )
    _ = m.ell(
        "ruff",
        n2,
        V3(0, 0.36, 0.312),
        V3(0.028 * rf, 0.026 * rf, 0.03),
        axis=normalize(V3(0, 0.8, 1)),
        k=0.042,
    )

    # HEAD, in head-local coordinates.
    var h = rig.bone("head")
    _ = m.ell(
        "cranium",
        h,
        _hl(t, V3(0, 0.016 + 0.008 * juv, -0.035)),
        _hr(t, V3(0.05 + 0.004 * juv, 0.047 + 0.01 * juv, 0.065)),
        k=0.04,
    )
    _ = m.ell(
        "forehead",
        h,
        _hl(t, V3(0, 0.03 + 0.005 * juv, 0.018)),
        _hr(t, V3(0.033, 0.028, 0.04)),
        axis=normalize(V3(0, -0.3, 1)),
        k=0.025,
    )
    for s in [1.0, -1.0]:
        _ = m.ell(
            "brow",
            h,
            _hl(t, V3(0.029 * s, 0.036, 0.03)),
            _hr(t, V3(0.015, 0.008, 0.014)),
            k=0.012,
        )
        _ = m.ell(
            "zygomatic",
            h,
            _hl(t, V3(0.052 * s, 0.0, -0.004)),
            _hr(t, V3(0.016, 0.022, 0.042)),
            axis=normalize(V3(-0.3 * s, 0, 1)),
            k=0.025,
        )
        _ = m.ell(
            "cheek",
            h,
            _hl(t, V3(0.038 * s, -0.026, -0.004)),
            _hr(t, V3(0.024, 0.027, 0.04)),
            k=0.025,
        )
        # The cheek ruff flares sideways and back below the ears.
        _ = m.ell(
            "cheekruff",
            h,
            _hl(t, V3(0.064 * s, -0.034, -0.035)),
            _hr(t, V3(0.036 * rf, 0.044, 0.05)),
            axis=normalize(V3(0.4 * s, -0.1, 1)),
            k=0.03,
        )
        _ = m.ell(
            "mastoid",
            h,
            _hl(t, V3(0.034 * s, -0.018, -0.064)),
            _hr(t, V3(0.024, 0.03, 0.03)),
            k=0.03,
        )
        _ = m.ell(
            "lip",
            h,
            _hl(t, V3(0.0145 * s, -0.0435, 0.083)),
            _hr(t, V3(0.0088, 0.0118, 0.058)),
            axis=normalize(V3(-0.17 * s, -0.06, 1)),
            k=0.012,
        )
        _ = m.ell(
            "whisker",
            h,
            _hl(t, V3(0.012 * s, -0.026, 0.125)),
            _hr(t, V3(0.0105, 0.011, 0.022)),
            k=0.012,
        )
        # The jowl runs the cheek down over the jaw's side behind the
        # mouth corner.
        _ = m.ell(
            "jowl",
            h,
            _hl(t, V3(0.021 * s, -0.0485, 0.006)),
            _hr(t, V3(0.0105, 0.0095, 0.036)),
            axis=normalize(V3(-0.2 * s, -0.06, 1)),
            k=0.014,
        )
        # The buccal tapers the face's side from the cheek into the lip.
        _ = m.ell(
            "buccal",
            h,
            _hl(t, V3(0.027 * s, -0.036, 0.035)),
            _hr(t, V3(0.011, 0.014, 0.036)),
            axis=normalize(V3(-0.35 * s, -0.05, 1)),
            k=0.014,
        )
    # A long, slender muzzle with a straight bridge.
    _ = m.cone(
        "nasal",
        h,
        _hl(t, V3(0, 0.027, 0.052)),
        _hl(t, V3(0, 0.004, 0.145)),
        0.0125 * hw,
        0.0078 * hw,
        k=0.014,
    )
    _ = m.ell(
        "muzzle",
        h,
        _hl(t, V3(0, -0.018, 0.088)),
        _hr(t, V3(0.02, 0.023, 0.064)),
        axis=normalize(V3(0, -0.12, 1)),
        k=0.016,
    )
    _ = m.ell(
        "nose",
        h,
        _hl(t, V3(0, -0.006, 0.152)),
        _hr(t, V3(0.0135, 0.0105, 0.01)),
        axis=normalize(V3(0, 0.4, 1)),
        k=0.006,
    )
    _ = m.ell(
        "philtrum",
        h,
        _hl(t, V3(0, -0.029, 0.147)),
        _hr(t, V3(0.008, 0.011, 0.008)),
        k=0.007,
    )
    for s in [1.0, -1.0]:
        var ef = eye_frame_of(eye, HEAD_O, s)
        _ = ell_y(
            m,
            "orbit",
            h,
            ef.at(-0.0015 * s, -0.0004, 0.0142),
            ef.y,
            V3(0.0135, 0.0094, 0.0068),
            lateral=ef.x,
            k=0.006,
            carve=True,
        )
        _ = m.sphere("eyelid", h, ef.c, eye.r + eye.lid, k=0.004)
        _ = m.lens(
            "eyesocket",
            h,
            ef.c + ef.y * eye.off,
            ef.x,
            ef.y,
            ef.z,
            eye.big_r,
            eye.d,
            -0.0015,
            0.018,
            k=0.0016,
            carve=True,
        )
        _ = m.sphere(
            "nostril",
            h,
            _hl(t, V3(0.0072 * s, -0.009, 0.161)),
            0.0023,
            k=0.0014,
            carve=True,
        )
        # The upper canine, hidden behind the lip.
        _ = m.cone(
            "canine",
            h,
            _hl(t, V3(0.0085 * s, -0.036, 0.118)),
            _hl(t, V3(0.008 * s, -0.047, 0.116)),
            0.0022,
            0.0007,
            k=0.0014,
        )

    # JAW: its own surface, so the mouth can open.
    var jw = rig.bone("jaw")
    _ = m.cone(
        "mandible",
        jw,
        _hl(t, V3(0, -0.05, -0.015)),
        _hl(t, V3(0, -0.054, 0.108)),
        0.0078,
        0.0038,
        k=0,
        part=JAW,
    )
    for s in [1.0, -1.0]:
        _ = m.cone(
            "mandible",
            jw,
            _hl(t, V3(0.025 * s, -0.044, -0.03)),
            _hl(t, V3(0.004 * s, -0.052, 0.105)),
            0.0058,
            0.0033,
            k=0.013,
            part=JAW,
        )
    _ = m.ell(
        "chin",
        jw,
        _hl(t, V3(0, -0.055, 0.1)),
        _hr(t, V3(0.0085, 0.0068, 0.011)),
        k=0.01,
        part=JAW,
    )

    # EARS: big, erect, triangular, deeply cupped in front.
    var ek = t.get("ear")
    for side in [String("L"), String("R")]:
        var s = 1.0 if side == "L" else -1.0
        var base = rig.j("earBase" + side)
        var tip = rig.j("earTip" + side)
        var up = normalize(tip - base)
        var facing = normalize(V3(0.45 * s, 0.1, 1))
        var lat = normalize(cross(up, facing))
        var eb = rig.bone("ear" + side)
        var w = ek * (1.0 + 0.1 * juv)
        _ = ell_y(
            m,
            "ear",
            eb,
            lerp(base, tip, 0.2),
            up,
            V3(0.034 * w, 0.032 * ek, 0.0068),
            lateral=lat,
            k=0.009,
            thin=True,
        )
        _ = ell_y(
            m,
            "ear",
            eb,
            lerp(base, tip, 0.52),
            up,
            V3(0.023 * w, 0.03 * ek, 0.0048),
            lateral=lat,
            k=0.009,
            thin=True,
        )
        _ = ell_y(
            m,
            "ear",
            eb,
            lerp(base, tip, 0.83),
            up,
            V3(0.009 * w, 0.021 * ek, 0.0034),
            lateral=lat,
            k=0.007,
            thin=True,
        )
        _ = ell_y(
            m,
            "earinner",
            eb,
            lerp(base, tip, 0.34) + facing * 0.0062,
            up,
            V3(0.023 * w, 0.031 * ek, 0.0045),
            lateral=lat,
            k=0.003,
            carve=True,
            thin=True,
        )
        _ = ell_y(
            m,
            "earinner",
            eb,
            lerp(base, tip, 0.66) + facing * 0.0045,
            up,
            V3(0.012 * w, 0.023 * ek, 0.0032),
            lateral=lat,
            k=0.0022,
            carve=True,
            thin=True,
        )

    # LEGS: long and thin, with small neat paws.
    var bk = t.get("boneK")
    var pk = t.get("pawK")
    for side in [String("L"), String("R")]:
        var s = 1.0 if side == "L" else -1.0
        _fore_leg(m, rig, side, s, bk, pk)
        _hind_leg(m, rig, side, s, bk, pk)

    # TAIL: the brush, rounded off at the white tip.
    var tb = t.get("tailBrush")
    _ = m.cone(
        "tailroot",
        rig.bone("tail0"),
        V3(0, 0.342, -0.175),
        rig.j("tail1"),
        0.02,
        _tail_radius(0.1, tb),
        k=0.022,
    )
    for i in range(TAIL_SEGS):
        _ = m.cone(
            "tail",
            rig.bone("tail" + String(i)),
            rig.j("tail" + String(i)),
            rig.j("tail" + String(i + 1)),
            _tail_radius(Float64(i) / Float64(TAIL_SEGS), tb),
            _tail_radius(Float64(i + 1) / Float64(TAIL_SEGS), tb),
            k=0.008,
            thin=i >= TAIL_SEGS - 1,
        )


def _fore_leg(
    mut m: SdfModel,
    rig: Rig,
    side: String,
    s: Float64,
    bk: Float64,
    pk: Float64,
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
        lerp(sc, sh, 0.5) + on_side(V3(0.004, 0, 0), s),
        sh - sc,
        V3(0.014, 0.055, 0.032),
        lateral=lat,
        k=0.035,
    )
    _ = m.cone("upperarm", hum, sh, e, 0.021, 0.015, k=0.035)
    _ = ell_y(
        m,
        "triceps",
        hum,
        lerp(sh, e, 0.55) + V3(0, 0, -0.016),
        e - sh,
        V3(0.016, 0.04, 0.019),
        lateral=lat,
        k=0.028,
    )
    _ = m.sphere("olecranon", rad, e + V3(0, 0.004, -0.012), 0.0095, k=0.011)
    _ = m.cone("forearm", rad, e, w, 0.0155 * bk, 0.0095 * bk, k=0.014)
    _ = ell_y(
        m,
        "forearmmuscle",
        rad,
        lerp(e, w, 0.25) + on_side(V3(0.0015, 0, 0.002), s),
        w - e,
        V3(0.0135, 0.036, 0.0155),
        lateral=lat,
        k=0.016,
    )
    _ = m.sphere("wrist", meta, w + V3(0, 0, -0.0015), 0.0095 * bk, k=0.007)
    _ = m.sphere("carpalpad", meta, w + V3(0, -0.004, -0.0095), 0.0045, k=0.005)
    _ = m.cone("pastern", meta, w, mc, 0.0088 * bk, 0.009 * bk, k=0.007)
    _ = m.sphere(
        "dewclaw",
        meta,
        lerp(w, mc, 0.3) + on_side(V3(-0.008, 0, 0.001), s),
        0.003,
        k=0.003,
    )
    var dp = normalize(toe - mc)
    _ = ell_y(
        m,
        "paw",
        fpaw,
        mc + dp * 0.011 + V3(0, -0.003, 0),
        dp,
        V3(0.0145 * pk, 0.02 * pk, 0.0095),
        lateral=lat,
        k=0.008,
    )
    _ = m.sphere("pad", fpaw, mc + V3(0, -0.0125, 0.006), 0.0065 * pk, k=0.006)
    var toe_x: List[Float64] = [-0.0105, -0.0036, 0.0036, 0.0105]
    var toe_z: List[Float64] = [-0.0055, 0, 0, -0.0055]
    for i in range(4):
        _ = m.sphere(
            "toe",
            fpaw,
            V3(
                toe.x + toe_x[i] * pk * s,
                0.0061 * pk,
                toe.z - 0.0045 + toe_z[i] * pk,
            ),
            0.0058 * pk,
            k=0.004,
        )
    for i in range(4):
        var x = toe.x + toe_x[i] * pk * s * 0.95
        _ = m.cone(
            "claw",
            fpaw,
            V3(x, 0.0055, toe.z + toe_z[i] * pk),
            V3(x, 0.002, toe.z + 0.0055 + toe_z[i] * pk),
            0.0016,
            0.0006,
            k=0.001,
        )


def _hind_leg(
    mut m: SdfModel,
    rig: Rig,
    side: String,
    s: Float64,
    bk: Float64,
    pk: Float64,
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
    # A muscular thigh: the fox's jumping engine.
    _ = ell_y(
        m,
        "thigh",
        fem,
        lerp(hp, kn, 0.4) + on_side(V3(0.002, 0, -0.016), s),
        kn - hp,
        V3(0.022, 0.078, 0.05),
        lateral=lat,
        k=0.03,
    )
    _ = m.cone(
        "thighfront",
        fem,
        on_side(V3(0.021, 0.325, -0.1), s),
        kn + on_side(V3(-0.002, 0.029, 0.0), s),
        0.02,
        0.0125,
        k=0.035,
    )
    _ = m.cone(
        "hamstring",
        fem,
        on_side(V3(0.024, 0.325, -0.212), s),
        lerp(kn, hk, 0.28) + V3(0, 0, -0.016),
        0.024,
        0.0145,
        k=0.024,
    )
    _ = ell_y(
        m,
        "breeches",
        fem,
        lerp(hp, kn, 0.62) + on_side(V3(0.003, -0.005, -0.045), s),
        kn - hp,
        V3(0.016, 0.043, 0.016),
        lateral=lat,
        k=0.02,
    )
    _ = ell_y(
        m,
        "flankfold",
        fem,
        on_side(V3(0.026, 0.26, -0.08), s),
        V3(-0.03, 0.16, 0.1),
        V3(0.0105, 0.043, 0.021),
        lateral=lat,
        k=0.035,
    )
    _ = m.sphere(
        "stifle", tib, kn + on_side(V3(0.001, 0.004, 0.003), s), 0.009, k=0.022
    )
    _ = m.cone(
        "shin",
        tib,
        lerp(kn, hk, 0.06) + on_side(V3(0, 0, 0.002), s),
        hk,
        0.0122 * bk,
        0.0085 * bk,
        k=0.017,
    )
    _ = ell_y(
        m,
        "calf",
        tib,
        lerp(kn, hk, 0.3) + on_side(V3(0.001, 0.005, -0.0145), s),
        hk - kn,
        V3(0.0132, 0.038, 0.016),
        lateral=lat,
        k=0.019,
    )
    _ = m.cone(
        "achilles",
        tib,
        lerp(kn, hk, 0.5) + V3(0, 0.005, -0.018),
        hk + V3(0, 0.006, -0.0155),
        0.0062,
        0.0058,
        k=0.008,
    )
    _ = m.sphere("calcaneus", mtar, hk + V3(0, 0.006, -0.013), 0.0078, k=0.0065)
    _ = m.sphere("hock", mtar, hk, 0.0102 * bk, k=0.0065)
    _ = m.cone("metatarsus", mtar, hk, mt, 0.0088 * bk, 0.0086 * bk, k=0.0065)
    var dh = normalize(tt - mt)
    _ = ell_y(
        m,
        "paw",
        hpaw,
        mt + dh * 0.01 + V3(0, -0.003, 0),
        dh,
        V3(0.013 * pk, 0.0185 * pk, 0.009),
        lateral=lat,
        k=0.008,
    )
    _ = m.sphere("pad", hpaw, mt + V3(0, -0.0125, 0.005), 0.006 * pk, k=0.006)
    var toe_x: List[Float64] = [-0.0105, -0.0036, 0.0036, 0.0105]
    var toe_z: List[Float64] = [-0.0055, 0, 0, -0.0055]
    for i in range(4):
        _ = m.sphere(
            "toe",
            hpaw,
            V3(
                tt.x + toe_x[i] * pk * 0.92 * s,
                0.0058 * pk,
                tt.z - 0.0045 + toe_z[i] * pk,
            ),
            0.0054 * pk,
            k=0.004,
        )
    for i in range(4):
        var x = tt.x + toe_x[i] * pk * 0.88 * s
        _ = m.cone(
            "claw",
            hpaw,
            V3(x, 0.005, tt.z + toe_z[i] * pk),
            V3(x, 0.002, tt.z + 0.005 + toe_z[i] * pk),
            0.0015,
            0.0006,
            k=0.001,
        )


def fox_look(t: Traits) -> EyeLook:
    """Return the fox's eye colors: an amber iris with a vertical slit, or
    blue-gray in a kit.

    Args:
        t: The individual.

    Returns:
        The look.
    """
    var sclera = V3(0.2, 0.15, 0.11)
    if t.juvenile() > 0.0:
        return EyeLook(
            V3(0.1, 0.13, 0.17),
            V3(0.2, 0.25, 0.32),
            V3(0.06, 0.07, 0.09),
            sclera,
            0.35,
            2.6,
        )
    return EyeLook(
        V3(0.5, 0.26, 0.04),
        V3(0.62, 0.32, 0.06),
        V3(0.19, 0.065, 0.012),
        sclera,
        0.35,
        2.6,
    )


def _swatches() -> List[String]:
    return [
        String("back"),
        "flank",
        "lowFlank",
        "head",
        "muzzleTop",
        "shoulder",
        "white",
        "belly",
        "stocking",
        "stockingEdge",
        "earBack",
        "earInner",
        "tail",
        "tailUnder",
        "tailTip",
        "gland",
        "tear",
        "rump",
        "dark",
    ]


def _morph(variant: Int) -> List[Int]:
    if variant == CROSS:
        return [
            0x8A5634,
            0x9C6A44,
            0x8A6448,
            0xA8703E,
            0x7A5234,
            0x8E5A36,
            0xCFC8BC,
            0x3A3430,
            0x151210,
            0x2A2018,
            0x1A1512,
            0xCFC4B2,
            0x6E4A32,
            0x8A6448,
            0xE8E2D8,
            0x2A1C14,
            0x2A1C14,
            0x8A6448,
            0x1E1A18,
        ]
    if variant == SILVER:
        return [
            0x8E8C8A,
            0x7A7876,
            0x2E2C2A,
            0x5E5C5A,
            0x201E1C,
            0x74726F,
            0x5A5856,
            0x1E1C1A,
            0x121010,
            0x181614,
            0x141210,
            0x6A6866,
            0x242220,
            0x1C1A18,
            0xEAE6DE,
            0x141210,
            0x141210,
            0x3A3836,
            0x161412,
        ]
    if variant == URBAN:
        return [
            0x7E4A2E,
            0x96684A,
            0x9A7A62,
            0x9A6440,
            0x8A5A3A,
            0x86522F,
            0xD8D2C8,
            0xA8A098,
            0x1C1712,
            0x3A2A1E,
            0x1E1814,
            0xD6CAB8,
            0x6E4630,
            0x8E6A50,
            0xE0DAD0,
            0x2A1C14,
            0x3A2618,
            0x9A7A62,
            0x2A1C14,
        ]
    return [
        0xB4582A,
        0xC46A32,
        0xC97A42,
        0xCA7236,
        0xB46A34,
        0xC56A32,
        0xECE8E2,
        0xD8D2CA,
        0x19140F,
        0x3A2418,
        0x1E1814,
        0xE6DCCB,
        0xA45A2C,
        0xC08450,
        0xF0EBE2,
        0x3A2618,
        0x3E2A1E,
        0xC98A58,
        0x2A1C14,
    ]


def _agouti(variant: Int) -> List[Float64]:
    # Back, flank, head, leg and tail.
    if variant == CROSS:
        return [0.55, 0.45, 0.15, 0.0, 0.7]
    if variant == SILVER:
        return [0.85, 0.8, 0.6, 0.1, 0.3]
    if variant == URBAN:
        return [0.6, 0.55, 0.15, 0.0, 0.65]
    return [0.35, 0.1, 0.05, 0.0, 0.55]


def fox_palette(t: Traits) raises -> Palette:
    """Return one fox's palette: its morph, warmed and lightened.

    Warmth shifts red against blue, and the white parts stay white. A
    kit's coat is washed into a woolly sandy gray-brown; its face,
    stockings, ears and tail tip stay. The `agouti` and `agouti2` entries
    hold the agouti band's strength: back, flank and head, then leg and
    tail.

    Args:
        t: The individual.

    Returns:
        The palette, in linear light.

    Raises:
        Error: If the palette tables differ in length.
    """
    var names = _swatches()
    var base = palette_of(names, _morph(t.variant))
    var k = t.get("coatWarmth", 0.0)
    var l = t.get("coatLightness", 0.0)
    var juv = t.juvenile()
    var kit = srgb(0x7A6450) * (0.45 if t.variant == SILVER else 1.0)
    var out = Palette()
    for name in names:
        var c = base.get(name)
        var pale = (
            name == "white"
            or name == "belly"
            or name == "earInner"
            or name == "tailTip"
        )
        var wk = 0.25 if pale else 1.0
        c = V3(
            c.x * (1.0 + (0.1 * k + l) * wk),
            c.y * (1.0 + (0.01 * k + l) * wk),
            c.z * (1.0 - (0.12 * k - l) * wk),
        )
        var face = name == "white" or name == "earInner" or name == "tailTip"
        var dark = name.startswith("stocking") or name == "earBack"
        var head = name == "head" or name == "muzzleTop"
        var keep = 0.6 if face else (0.7 if dark else (0.45 if head else 0.15))
        c = mix3(c, kit, juv * (1.0 - keep))
        out.set(name, c)
    var ag = _agouti(t.variant)
    out.set("agouti", V3(ag[0], ag[1], ag[2]))
    out.set("agouti2", V3(ag[3], ag[4], 0.0))
    return out^


def _head_local(t: Traits, p: V3) -> V3:
    var x = (p.x - HEAD_O.x) / t.get("headW") / HS
    var y = (p.y - HEAD_O.y) / HS
    var z = (p.z - HEAD_O.z) / HS
    var mz = t.get("muzzle")
    return V3(x, y, MUZZLE_Z0 + (z - MUZZLE_Z0) / mz if z > MUZZLE_Z0 else z)


def _mouth_line(t: Traits, h: V3) -> Float64:
    # The upper lip's lower rim over a head-local point.
    var mz = t.get("muzzle")
    var lip = mirrored_ell_bottom(
        h, V3(0.0145, -0.0435, 0.083), V3(0.0088, 0.0118, 0.058 / mz)
    )
    var pad = mirrored_ell_bottom(
        h, V3(0.012, -0.026, 0.125), V3(0.0105, 0.011, 0.022 / mz)
    )
    var muzzle = mirrored_ell_bottom(
        h, V3(0.0, -0.018, 0.088), V3(0.02, 0.023, 0.064 / mz)
    )
    var philtrum = mirrored_ell_bottom(
        h, V3(0.0, -0.029, 0.147), V3(0.008, 0.011, 0.008 / mz)
    )
    return min(min(lip, pad), min(muzzle, philtrum))


def _seg_d(h: V3, a: V3, b: V3) -> V3:
    # The distance from a head-local point, mirrored to the left, to a
    # segment, and how far along it the nearest point is.
    var q = V3(abs(h.x), h.y, h.z)
    var u = segment_param(q, a, b)
    return V3(length(q - (a + (b - a) * u)), u, 0.0)


def _tail_at(t: Traits, bone: String, p: V3) -> V3:
    # How far along the tail a point lies, from zero at the root to one at
    # the tip, and the tail's dorsal direction there (y and z).
    var angles = _tail_angles()
    var w = _tail_weights()
    var ws = 0.0
    for x in w:
        ws += x
    var tk = 0.4 * t.get("tail")
    var seg = 0
    for i in range(TAIL_SEGS):
        if bone == "tail" + String(i):
            seg = i
    var a = TAIL_BASE
    var done = 0.0
    for i in range(seg):
        var ang = angles[i] * pi / 180.0
        var l = w[i] / ws
        a = a + V3(0.0, sin(ang), -cos(ang)) * (l * tk)
        done += l
    var ang = angles[seg] * pi / 180.0
    var d = V3(0.0, sin(ang), -cos(ang))
    var l = w[seg] / ws
    var u = clamp(dot(p - a, d) / (l * tk), 0.0, 1.0)
    return V3(done + u * l, cos(ang), sin(ang))


# Reference heights and depths the coat is laid out by.
comptime Y_ELBOW = 0.19
comptime Y_HOCK = 0.078
comptime Y_KNEE = 0.18
comptime Y_BACK = 0.345
comptime Z_SHOULDER = 0.252
comptime Z_HIP = -0.168


def fox_paint(
    pal: Palette, t: Traits, tag: String, bone: String, s: CoatSample
) -> Paint:
    """Paint one vertex of a fox.

    The red fox's pattern: a rufous back, flanks, head and brush, brightest
    on the shoulders; white upper lips, cheeks, chin, throat and bib; a
    pale belly; black stockings up the forelegs to the elbows and over the
    hind feet; black ear backs with white-furred insides; dark tear lines;
    a dark tail-gland spot and a white tail tip. The cross fox wears a dark
    cross over the shoulders and down the spine.

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
    if tag == "nose" or tag == "nostril":
        var hn = _head_local(t, p)
        var on = hn.z > 0.138 and hn.y > -0.022
        if on:
            var c = srgb(0x1A1616) * (0.4 if tag == "nostril" else 1.0)
            return Paint(c, NOSE)
    if tag == "canine":
        return Paint(srgb(0xE8E0CC), KERATIN)
    if tag == "claw":
        return Paint(srgb(0x1E1A16), KERATIN)
    var pad = (tag == "pad" or tag == "carpalpad") and n.y < -0.3
    if pad:
        return Paint(srgb(0x1E1A18), SKIN)
    if tag == "eyesocket":
        return Paint(srgb(0x141010), SKIN)
    var head = bone == "head" or bone == "jaw"
    if head:
        # The black lip line along the mouth slit.
        var h = _head_local(t, p)
        var line = _mouth_line(t, h)
        var near = line < 0.5 and h.z > 0.025
        var upper = near and bone == "head" and h.y < line + 0.002
        var lower = near and bone == "jaw" and h.y > line - 0.0015
        var lips = upper or lower
        if lips:
            return Paint(srgb(0x1E1816), SKIN)
    var juv = t.juvenile()
    var ag = pal.get("agouti")
    var ag2 = pal.get("agouti2")
    var n_off = Float64(Int(t.get("coatSeed", 0.0)) % 997)
    var nz = fbm3(V3(p.x * 12.0 + n_off, p.y * 12.0, p.z * 12.0), 3) - 0.5
    var nz2 = vnoise3(V3(p.x * 70.0 + n_off, p.y * 70.0, p.z * 70.0)) - 0.5
    var c: V3
    var agouti: Float64
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
        leg = smoothstep(0.29, 0.17, p.y)
    if region <= 1:
        c = _body(pal, t, p, n, nz, region, leg, bone)
        var dors = smoothstep(-0.1, 0.7, n.y + 0.3 * nz)
        agouti = mix(ag.y, ag.x, dors) * (1.0 - leg)
        if t.variant == CROSS and region == 0:
            agouti = mix(agouti, 0.3, 0.5 * smoothstep(0.4, 0.8, n.y))
        agouti = mix(agouti, ag2.x, leg)
    elif region == 4:
        # The brush: black-tipped guard hair, a dark gland spot, a paler
        # underside and the white tip.
        var tf = _tail_at(t, bone, p)
        var along = tf.x
        var dors = n.y * tf.y + n.z * tf.z
        var top = smoothstep(-0.45, 0.55, dors + 0.3 * nz)
        c = mix3(pal.get("tailUnder"), pal.get("tail"), top)
        agouti = ag2.y * (0.55 + 0.45 * top) * smoothstep(0.02, 0.2, along)
        var gl = exp(-(((along - 0.14) / 0.05) ** 2)) * smoothstep(
            0.2, 0.75, dors
        )
        c = mix3(c, pal.get("gland"), gl * 0.75)
        var tip_k = t.get("tailTip")
        var tip_start = 1.0 - 0.17 * tip_k
        var dark_band = exp(-(((along - tip_start + 0.06) / 0.07) ** 2))
        c = mix3(c, pal.get("dark"), dark_band * 0.35)
        var tip = (
            smoothstep(
                tip_start - 0.02, tip_start + 0.04, along + 0.035 * nz
            ) if tip_k
            > 0.0 else 0.0
        )
        c = mix3(c, pal.get("tailTip"), tip)
        agouti *= 1.0 - tip
    elif region == 5:
        # Ears: black backs, the black running round the rim; the inside
        # furred white.
        var sgn = 1.0 if p.x >= 0.0 else -1.0
        var base = _hl(t, V3(EAR_BASE.x * sgn, EAR_BASE.y, EAR_BASE.z))
        var tip = _ear_tip(t, V3(base.x * sgn, base.y, base.z))
        tip = V3(tip.x * sgn, tip.y, tip.z)
        var up = normalize(tip - base)
        var facing = normalize(V3(0.45 * sgn, 0.1, 1))
        var lat = normalize(cross(up, facing))
        var front = dot(n, facing)
        var rel = p - base
        var ht = dot(rel, up) / length(tip - base)
        var edge = abs(dot(rel, lat)) / (0.022 * max(0.25, 1.0 - ht))
        if front > 0.25 or tag == "earinner":
            c = mix3(
                pal.get("head"),
                pal.get("earInner"),
                max(
                    smoothstep(0.25, 0.7, front),
                    0.6 if tag == "earinner" else 0.0,
                )
                * (1.0 - smoothstep(0.75, 1.05, edge)),
            )
        else:
            # The back: black, orange at the very base.
            c = mix3(
                pal.get("earBack"),
                pal.get("head"),
                smoothstep(0.12, -0.05, ht) * 0.9,
            )
        agouti = 0.0
    else:
        c = _face(pal, t, p, n, nz, region, tag)
        agouti = ag.z * (1.0 - _white_face(t, p, n, nz, region))
    if juv > 0.0:
        agouti *= 1.0 - 0.8 * juv
    var cvh = fbm3(V3(p.x * 6.0 + 5.0 + n_off, p.y * 6.0, p.z * 6.0), 2) - 0.5
    c = V3(
        c.x * (1.0 + 0.14 * nz + 0.1 * cvh + 0.06 * nz2),
        c.y * (1.0 + 0.12 * nz + 0.06 * nz2),
        c.z * (1.0 + 0.1 * nz - 0.08 * cvh + 0.06 * nz2),
    )
    c = grizzle(c, p, 160.0, 0.08 + 0.3 * agouti)
    return Paint(c, FUR)


def _body(
    pal: Palette,
    t: Traits,
    p: V3,
    n: V3,
    nz: Float64,
    region: Int,
    leg: Float64,
    bone: String,
) -> V3:
    # The torso, the neck and the legs.
    var up = n.y
    var vent: Float64
    if region == 0:
        vent = smoothstep(-0.45, -0.85, n.y)
        var y_bib = Y_ELBOW + 0.13 * t.get("bib")
        if p.z > Z_SHOULDER - 0.05:
            var wob = 0.012 * (
                fbm3(V3(p.x * 40.0, p.y * 40.0, p.z * 40.0), 2) - 0.5
            )
            vent = max(
                vent,
                smoothstep(y_bib, y_bib - 0.035, p.y + wob)
                * smoothstep(0.042, 0.018, abs(p.x))
                * smoothstep(-0.3, 0.35, n.z),
            )
        vent *= smoothstep(Y_BACK - 0.02, Y_BACK - 0.08, p.y)
    else:
        vent = smoothstep(
            0.4, -0.05, n.y + 0.65 * abs(n.x) - 0.45 * max(0.0, n.z)
        )
    if leg > 0.0:
        var side = 1.0 if p.x >= 0.0 else -1.0
        var inner = smoothstep(0.1, -0.6, n.x * side)
        var wl = inner * 0.75 * smoothstep(
            Y_KNEE - 0.01, Y_KNEE + 0.05, p.y
        ) * (0.4 if is_front_limb(bone) else 1.0) + smoothstep(
            -0.3, -0.85, n.y
        ) * 0.4 * smoothstep(
            Y_KNEE - 0.02, Y_KNEE + 0.04, p.y
        )
        vent = mix(vent, wl, leg)
    vent = clamp(vent, 0.0, 1.0)
    var dors = smoothstep(-0.1, 0.7, up + 0.3 * nz)
    var c = mix3(
        pal.get("lowFlank"),
        pal.get("flank"),
        smoothstep(-0.4, 0.2, up + 0.25 * nz),
    )
    c = mix3(c, pal.get("back"), dors * 0.85)
    var cross_fox = t.variant == CROSS
    if region == 0:
        # Brighter shoulders, paler hips and rump.
        var side = 1.0 if p.x >= 0.0 else -1.0
        var sh = exp(-(((p.z - Z_SHOULDER + 0.01) / 0.05) ** 2)) * smoothstep(
            -0.3, 0.3, n.x * side
        )
        c = mix3(c, pal.get("shoulder"), sh * 0.6)
        var rump = (
            smoothstep(Z_HIP + 0.02, Z_HIP - 0.05, p.z)
            * smoothstep(-0.2, -0.8, n.z)
            * smoothstep(Y_BACK + 0.02, Y_BACK - 0.06, p.y)
        )
        c = mix3(c, pal.get("rump"), rump * 0.6)
        if cross_fox:
            # A dark stripe down the spine crossed by one over the
            # shoulders.
            var spine = smoothstep(0.4, 0.8, up + 0.15 * nz) * smoothstep(
                Z_HIP - 0.06, Z_HIP + 0.02, p.z
            )
            var bar = exp(
                -(((p.z - Z_SHOULDER - 0.035 + 0.02 * nz) / 0.05) ** 2)
            ) * smoothstep(Y_ELBOW + 0.02, Y_BACK - 0.04, p.y)
            c = mix3(
                c, pal.get("dark"), clamp(max(spine, bar), 0.0, 1.0) * 0.92
            )
        c = mix3(c, pal.get("belly"), vent)
        # The white bib is whiter than the belly.
        var bib = smoothstep(Z_SHOULDER - 0.06, Z_SHOULDER + 0.01, p.z) * vent
        c = mix3(c, pal.get("white"), bib)
    else:
        c = mix3(c, pal.get("white"), smoothstep(0.2, 0.65, vent + 0.15 * nz))
        if cross_fox:
            c = mix3(c, pal.get("dark"), smoothstep(0.6, 0.95, up) * 0.6)
    if leg > 0.0:
        var front = is_front_limb(bone)
        var side = 1.0 if p.x >= 0.0 else -1.0
        var outer = smoothstep(-0.2, 0.5, n.x * side)
        var lc = mix3(
            c, pal.get("belly"), smoothstep(0.2, 0.7, vent) * (1.0 - outer)
        )
        # The black stockings: forelegs from the paw to the elbow, hind feet
        # to the hock with a dark stripe up the front of the shin.
        var st_k = t.get("stockings")
        var e = 0.012 * nz
        var st: Float64
        if front:
            var top = Y_ELBOW + 0.01 * st_k + 0.02 * smoothstep(-0.2, 0.8, n.z)
            st = smoothstep(top + 0.012, top - 0.012, p.y + e)
            st = max(
                st,
                0.8
                * smoothstep(0.4, 0.85, n.z)
                * smoothstep(Y_ELBOW + 0.075, Y_ELBOW + 0.03, p.y)
                * st_k,
            )
        else:
            var top = Y_HOCK + 0.012 + 0.03 * st_k * smoothstep(0.1, 0.8, n.z)
            st = smoothstep(top + 0.012, top - 0.012, p.y + e)
            st = max(
                st,
                0.85
                * smoothstep(0.35, 0.8, n.z)
                * smoothstep(Y_KNEE - 0.01, Y_HOCK + 0.03, p.y)
                * st_k,
            )
        st = clamp(st, 0.0, 1.0)
        lc = mix3(
            lc,
            mix3(
                pal.get("stockingEdge"),
                pal.get("stocking"),
                smoothstep(0.3, 0.9, st),
            ),
            st,
        )
        var paw = bone.startswith("fpaw") or bone.startswith("hpaw")
        if paw:
            lc = pal.get("stocking")
        c = mix3(c, lc, leg)
    return c


def _white_face(t: Traits, p: V3, n: V3, nz: Float64, region: Int) -> Float64:
    # The white mask: upper lips, the lower muzzle sides, the cheeks, the
    # chin and the throat.
    var h = _head_local(t, p)
    var lip_side = (
        smoothstep(0.035, 0.065, h.z)
        * smoothstep(-0.018, -0.032, h.y - 0.06 * (h.z - 0.1))
        * smoothstep(0.1, 0.5, abs(n.x))
    )
    var cheek = (
        smoothstep(-0.01, -0.03, h.y + 0.25 * (h.z - 0.02) + 0.01 * nz)
        * smoothstep(0.075, 0.02, h.z)
        * smoothstep(0.012, 0.03, abs(h.x))
    )
    var low_face = smoothstep(-0.03, -0.05, h.y) * smoothstep(-0.1, -0.6, n.y)
    var throat = smoothstep(-0.034, -0.055, h.y) * smoothstep(0.08, 0.03, h.z)
    var jaw = 0.85 if region == 6 else 0.0
    return clamp(
        max(max(lip_side, cheek), max(max(low_face, throat), jaw)), 0.0, 1.0
    )


def _face(
    pal: Palette,
    t: Traits,
    p: V3,
    n: V3,
    nz: Float64,
    region: Int,
    tag: String,
) -> V3:
    # The head and the jaw.
    var h = _head_local(t, p)
    var c = pal.get("head")
    var mtop = smoothstep(0.05, 0.1, h.z) * smoothstep(-0.1, 0.5, n.y)
    c = mix3(c, pal.get("muzzleTop"), mtop * 0.6)
    c = mix3(c, pal.get("white"), _white_face(t, p, n, nz, region))
    # The dark tear line: from the inner eye corner toward the upper lip.
    var tl = _seg_d(h, V3(0.025, 0.012, 0.05), V3(0.017, -0.018, 0.085))
    var tear = (
        exp(-((tl.x / (0.0045 + 0.003 * tl.y)) ** 2))
        * t.get("tear")
        * (1.0 - 0.6 * t.juvenile())
    )
    c = mix3(c, pal.get("tear"), tear * 0.85)
    if tag == "eyelid":
        # The lid margin darkens toward the eye.
        c = mix3(c, pal.get("tear"), 0.3)
    return c
