# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The European rabbit, Oryctolagus cuniculus:
procedural-animals' `species/rabbit/`.

The wild agouti rabbit and the common domestic colors. Long hind legs,
long spoon-shaped ears, big lateral eyes and a short scut. The bind pose
stands with the hind legs half extended and the hips raised. Variants
are wild, a random domestic one, agouti domestic, fawn, black, white
(the red-eyed albino), Dutch (pied) and the lop, whose ears hang beside
the cheeks. A kit is a little over half size, with a round head, short
ears and big eyes and feet.
"""

from extensions.animals.coat import (
    FUR,
    NOSE,
    SKIN,
    CoatSample,
    EyeLook,
    Paint,
    Palette,
    grizzle,
    mix3,
    palette_of,
    srgb,
)
from extensions.sdf.ids import SurfacePart
from extensions.animals.parts import JAW
from extensions.sdf.sculpt import ell_y
from extensions.animals.kit import (
    EyeSpec,
    eye_frame_of,
    sculpt_eye_socket,
    is_limb,
    mirrored_blob,
)
from extensions.animals.noise import fbm3
from extensions.animals.options import AnimalOptions, AnimalRandom
from extensions.animals.rig import Rig, quadruped_bones, tail_chain
from extensions.sdf.field import SdfModel
from extensions.animals.traits import Traits, pick_age, pick_sex
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
    length_warp,
    legs_warp,
    scale_about_warp,
)
from std.math import cos, pi, sin
from extensions.sdf.distance import ellipsoid_estimate, round_cone_estimate

comptime TAIL_SEGS = 3
# The head's origin: on the midline, level with the eye centers.
comptime HEAD_O = V3(0.0, 0.219, 0.15)
# The finest cell, at the `HERO` tier: the head's cell in the original.
comptime CELL = 0.0011
# How far the hips and the rear of the body are raised in bind pose.
comptime REAR_LIFT = 0.037
comptime EAR_BASE = V3(0.012, 0.238, 0.122)

# The variants, in procedural-animals' order.
comptime WILD = 0
comptime DOMESTIC = 1
comptime AGOUTI_DOMESTIC = 2
comptime FAWN_VARIANT = 3
comptime BLACK_VARIANT = 4
comptime WHITE_VARIANT = 5
comptime DUTCH = 6
comptime LOP = 7

# The coat colors.
comptime AGOUTI = 0
comptime FAWN = 1
comptime BLACK = 2
comptime WHITE = 3


def rabbit_variant_names() -> List[String]:
    """Return the rabbit's variants.

    Returns:
        Wild, domestic (a random domestic one), agouti domestic, fawn,
        black, white, Dutch and lop.
    """
    return [
        String("wild"),
        "domestic",
        "agouti-domestic",
        "fawn",
        "black",
        "white",
        "dutch",
        "lop",
    ]


def rabbit_traits(mut r: AnimalRandom, options: AnimalOptions) raises -> Traits:
    """Draw one rabbit: procedural-animals' `variation`.

    Domestic rabbits are a little larger and rounder, with shorter ears.
    Kits are 0.58 of the size, with a big round head and short ears.

    Args:
        r: The individual's stream.
        options: The caller's sex, age and variant.

    Returns:
        The traits.

    Raises:
        Error: If the requested variant is not one of the eight.
    """
    var sex = pick_sex(options.sex, r)
    var age = pick_age(options.age)
    if options.variant.value >= 8:
        raise Error("The rabbit has no such variant")
    var variant = WILD if options.variant.value < 0 else options.variant.value
    if variant == DOMESTIC:
        variant = AGOUTI_DOMESTIC + min(5, Int(r.next() * 6.0))
    var domestic = variant != WILD
    var lop = variant == LOP
    # The original builds a table of every variant's color, so both of
    # these draws happen for every rabbit.
    var dutch_draw = r.next()
    var lop_draw = r.next()
    var color = AGOUTI
    if variant == FAWN_VARIANT:
        color = FAWN
    elif variant == BLACK_VARIANT:
        color = BLACK
    elif variant == WHITE_VARIANT:
        color = WHITE
    elif variant == DUTCH:
        color = BLACK if dutch_draw < 0.6 else AGOUTI
    elif lop:
        color = min(3, Int(lop_draw * 4.0))
    var t = Traits(sex, age, variant)
    var juv = t.juvenile() > 0.0
    var male = t.male()
    var size = (
        1.06 + 0.08 * r.g() if domestic else 1.0 + 0.07 * (2.0 * r.next() - 1.0)
    ) * (1.01 if male else 0.99)
    if juv:
        size *= 0.58
    t.set("size", size)
    t.set("color", Float64(color))
    t.set("domestic", 1.0 if domestic else 0.0)
    t.set("lop", 1.0 if lop else 0.0)
    t.set("dutch", 1.0 if variant == DUTCH else 0.0)
    t.set(
        "earLen",
        (0.92 if domestic else 1.0)
        * (1.0 + 0.07 * r.g())
        * (0.78 if juv else 1.0),
    )
    t.set("earWidth", (1.25 if lop else 1.0) * (1.0 + 0.05 * r.g()))
    t.set(
        "headWidth",
        (1.06 if domestic else 1.0)
        * (1.03 if male else 1.0)
        * (1.06 if juv else 1.0),
    )
    t.set("minThick", 0.0011)
    t.warps.add(legs_warp(1.0 + 0.04 * r.g() - (0.04 if juv else 0.0), 0.08))
    t.warps.add(
        length_warp(
            1.0
            + 0.03 * r.g()
            - (0.03 if domestic else 0.0)
            - (0.06 if juv else 0.0),
            -0.12,
            0.07,
        )
    )
    t.warps.add(
        girth_warp(
            1.0 + 0.06 * r.g() + (0.05 if domestic else 0.0), 0.12, -0.15, 0.1
        )
    )
    t.warps.add(
        scale_about_warp(
            HEAD_O,
            (1.02 if male else 0.99)
            * (1.0 + 0.02 * r.g())
            * (1.2 if juv else 1.0)
            * (1.03 if domestic else 1.0),
            0.035,
            0.075,
        )
    )
    t.set("coatWarmth", 1.1 * (2.0 * r.next() - 1.0))
    t.set("coatLightness", 0.12 * (2.0 * r.next() - 1.0))
    t.set("coatSeed", Float64(Int(r.next() * 1e6)))
    return t^


def rabbit_eye(t: Traits) -> EyeSpec:
    """Return the rabbit's left eye: large, lateral and a little raised,
    with a round, nearly lid-free aperture.

    Args:
        t: The individual. Every rabbit has the same eye.

    Returns:
        The eye, head-local.
    """
    return EyeSpec(
        V3(0.0172, 0.001, 0.0015),
        0.0102,
        0.0012,
        1.1,
        0.12,
        0.0011,
        0.0088,
        0.0014,
        0.0,
        8.0 * pi / 180.0,
        0.0058,
        0.0083,
    )


def _rear_w(z: Float64) -> Float64:
    var u = min(1.0, max(0.0, (0.03 - z) / 0.12))
    return u * u * (3.0 - 2.0 * u)


def _rl(p: V3) -> V3:
    # The rear of the body, raised with the hips.
    return V3(p.x, p.y + REAR_LIFT * _rear_w(p.z), p.z)


def _hl(v: V3) -> V3:
    return v + HEAD_O


def _ear_tip(t: Traits) -> V3:
    if t.get("lop", 0.0) > 0.0:
        return V3(0.05, 0.15, 0.136)
    var e = t.get("earLen")
    return EAR_BASE + V3(0.017 * e, 0.087 * e, -0.02 * e)


def rabbit_rig(t: Traits) raises -> Rig:
    """Return the rabbit's skeleton in bind pose.

    The hind legs stand half extended, the hips raised, so neither the
    crouch nor the push-off stretches the skin far. A snout bone carries
    the nose and the whisker pads.

    Args:
        t: The individual.

    Returns:
        The rig.

    Raises:
        Error: If a bone names a missing joint.
    """
    var rig = Rig()
    rig.set("nose", V3(0.0, 0.2, 0.191))
    rig.set("occiput", V3(0.0, 0.23, 0.115))
    rig.set("neckMid", V3(0.0, 0.205, 0.097))
    rig.set("neckBase", V3(0.0, 0.184, 0.076))
    rig.set("chestMid", V3(0.0, 0.17, 0.05))
    rig.set("thoraxRear", V3(0.0, 0.171, -0.003))
    rig.set("lumbarMid", _rl(V3(0.0, 0.163, -0.052)))
    rig.set("lumbosacral", _rl(V3(0.0, 0.135, -0.092)))
    rig.set("tailBase", _rl(V3(0.0, 0.084, -0.146)))
    rig.set("scapTopL", V3(0.024, 0.178, 0.058))
    rig.set("shoulderL", V3(0.036, 0.126, 0.1))
    rig.set("elbowL", V3(0.05, 0.076, 0.064))
    rig.set("wristL", V3(0.045, 0.022, 0.079))
    rig.set("mcpL", V3(0.043, 0.0075, 0.094))
    rig.set("ftoeL", V3(0.043, 0.004, 0.111))
    rig.set("hipL", V3(0.031, 0.125, -0.086))
    rig.set("kneeL", V3(0.05, 0.0762, -0.0277))
    rig.set("hockL", V3(0.044, 0.0234, -0.0981))
    rig.set("mtpL", V3(0.044, 0.0085, -0.048))
    rig.set("htoeL", V3(0.043, 0.0045, -0.02))
    rig.set("snoutBase", V3(0.0, 0.208, 0.174))
    rig.set("jawHinge", V3(0.0, 0.206, 0.13))
    rig.set("jawTip", V3(0.0, 0.185, 0.171))
    rig.set("earBaseL", EAR_BASE)
    rig.set("earTipL", _ear_tip(t))
    var angles: List[Float64] = [-12, -24, -36]
    var lens: List[Float64] = [0.016, 0.016, 0.014]
    tail_chain(rig, "tailBase", angles, lens)
    rig.mirror_joints()
    quadruped_bones(rig, TAIL_SEGS)
    _ = rig.add_bone("snout", "snoutBase", "nose", "head")
    return rig^


def _ear_frame(t: Traits, s: Float64) -> Tuple[V3, V3, V3, V3, Float64]:
    # One ear's base, its up axis, the direction its cup faces, its
    # lateral axis and its length.
    var base = V3(EAR_BASE.x * s, EAR_BASE.y, EAR_BASE.z)
    var tip0 = _ear_tip(t)
    var tip = V3(tip0.x * s, tip0.y, tip0.z)
    var up = normalize(tip - base)
    var facing0 = normalize(V3(-0.3 * s, 0.0, 0.9)) if t.get(
        "lop", 0.0
    ) > 0.0 else normalize(V3(0.75 * s, 0.05, 0.6))
    var facing = normalize(facing0 - up * dot(facing0, up))
    var lat = normalize(cross(up, facing))
    return (base, up, facing, lat, length(tip - base))


def rabbit_sculpt(mut m: SdfModel, rig: Rig, t: Traits) raises:
    """Sculpt the rabbit: procedural-animals' `sculptRabbit`, primitive for
    primitive.

    Args:
        m: The sculpt to add to.
        rig: The rabbit's rig in bind pose.
        t: The individual.

    Raises:
        Error: If the rig lacks a joint or a bone, or the sculpt refuses
            a primitive.
    """
    var doe = not t.male()
    var dom = t.get("domestic", 0.0) > 0.0

    # TORSO: egg-shaped, highest over the loins.
    _ = m.ell(
        "ribcage",
        rig.bone("spine3"),
        V3(0, 0.128, 0.03),
        V3(0.05, 0.054, 0.062),
        axis=normalize(V3(0, 0.35, 1)),
        k=0,
    )
    var chest = rig.bone("chest")
    _ = m.ell(
        "brisket",
        chest,
        V3(0, 0.09, 0.066),
        V3(0.035, 0.054, 0.036),
        axis=normalize(V3(0, -0.5, 1)),
        k=0.03,
    )
    _ = m.ell(
        "withers",
        chest,
        V3(0, 0.167, 0.048),
        V3(0.034, 0.024, 0.042),
        axis=normalize(V3(0, 0.35, 1)),
        k=0.03,
    )
    var spine2 = rig.bone("spine2")
    _ = m.ell(
        "back",
        spine2,
        _rl(V3(0, 0.162, -0.018)),
        V3(0.046, 0.03, 0.06),
        k=0.035,
    )
    _ = m.ell(
        "abdomen",
        spine2,
        _rl(V3(0, 0.082, -0.03)),
        V3(0.05, 0.062, 0.06),
        k=0.035,
    )
    _ = m.ell(
        "loin",
        rig.bone("spine1"),
        _rl(V3(0, 0.153, -0.062)),
        V3(0.05, 0.032, 0.05),
        axis=normalize(V3(0, -0.55, 1)),
        k=0.03,
    )
    var pelvis = rig.bone("pelvis")
    _ = m.ell(
        "rump",
        pelvis,
        _rl(V3(0, 0.092, -0.094)),
        V3(0.044, 0.068, 0.053),
        k=0.035,
    )
    _ = m.ell(
        "rumpback",
        pelvis,
        _rl(V3(0, 0.066, -0.108)),
        V3(0.04, 0.04, 0.04),
        k=0.03,
    )

    # NECK: short, the head sits on the shoulders.
    var n1 = rig.bone("neck1")
    _ = m.cone(
        "neck",
        n1,
        V3(0, 0.155, 0.074),
        rig.j("neckMid"),
        0.036,
        0.03,
        k=0.03,
    )
    _ = m.cone(
        "neck",
        rig.bone("neck2"),
        rig.j("neckMid"),
        _hl(V3(0, 0, -0.02)),
        0.03,
        0.026,
        k=0.025,
    )
    _ = m.ell("throat", n1, V3(0, 0.145, 0.1), V3(0.03, 0.03, 0.03), k=0.03)
    # Domestic does carry a dewlap, a fold of skin under the chin.
    var dewlap = doe and dom
    if dewlap:
        _ = m.ell(
            "dewlap", n1, V3(0, 0.14, 0.114), V3(0.024, 0.02, 0.018), k=0.02
        )

    # HEAD, in head-local coordinates.
    var h = rig.bone("head")
    var hw = t.get("headWidth")
    _ = m.ell(
        "cranium",
        h,
        _hl(V3(0, 0.005, -0.012)),
        V3(0.0245 * hw, 0.024, 0.031),
        k=0.02,
    )
    _ = m.cone(
        "nasal",
        h,
        _hl(V3(0, 0.012, -0.002)),
        _hl(V3(0, -0.009, 0.031)),
        0.0175 * hw,
        0.0128,
        k=0.014,
    )
    for s in [1.0, -1.0]:  # pragma: no branch
        _ = m.ell(
            "cheek",
            h,
            _hl(V3(0.0175 * s * hw, -0.02, -0.006)),
            V3(0.0145, 0.0195, 0.023),
            k=0.016,
        )
        _ = m.ell(
            "brow",
            h,
            _hl(V3(0.0125 * s, 0.013, 0.002)),
            V3(0.009, 0.006, 0.012),
            k=0.01,
        )
        _ = m.ell(
            "jowl",
            h,
            _hl(V3(0.013 * s, -0.031, -0.018)),
            V3(0.013, 0.013, 0.017),
            k=0.016,
        )
    _ = m.ell(
        "muzzle",
        h,
        _hl(V3(0, -0.019, 0.023)),
        V3(0.0168, 0.0158, 0.0158),
        k=0.012,
    )
    var eye = rabbit_eye(t)
    for s in [1.0, -1.0]:  # pragma: no branch
        _ = sculpt_eye_socket(
            m,
            eye,
            HEAD_O,
            s,
            h,
            orbit_r=V3(0.0115, 0.0095, 0.006),
            orbit_at=V3(0.0, 0.0, 0.0095),
            orbit_k=0.004,
        )

    # SNOUT: the nose, the split upper lip and the whisker pads.
    var sn = rig.bone("snout")
    for s in [1.0, -1.0]:  # pragma: no branch
        _ = m.ell(
            "whisker",
            sn,
            _hl(V3(0.0077 * s, -0.026, 0.0315)),
            V3(0.0097, 0.0092, 0.0095),
            k=0.006,
        )
        _ = m.sphere(
            "nostril",
            sn,
            _hl(V3(0.0036 * s, -0.0185, 0.0412)),
            0.0013,
            k=0.0012,
            carve=True,
        )
    _ = m.ell(
        "nose",
        sn,
        _hl(V3(0, -0.0185, 0.0372)),
        V3(0.0064, 0.005, 0.0045),
        axis=normalize(V3(0, 0.45, 1)),
        k=0.004,
    )
    _ = m.cone(
        "lipcleft",
        sn,
        _hl(V3(0, -0.022, 0.0422)),
        _hl(V3(0, -0.034, 0.0378)),
        0.0011,
        0.0013,
        k=0.0015,
        carve=True,
    )

    # JAW: small, set back under the upper lip.
    var jw = rig.bone("jaw")
    _ = m.cone(
        "mandible",
        jw,
        _hl(V3(0, -0.029, -0.012)),
        _hl(V3(0, -0.032, 0.021)),
        0.0105,
        0.006,
        k=0,
        part=JAW,
    )
    _ = m.ell(
        "chin",
        jw,
        _hl(V3(0, -0.0325, 0.019)),
        V3(0.0066, 0.0048, 0.0065),
        k=0.006,
        part=JAW,
    )

    # EARS: long, spoon-shaped and thin, the cup facing out and forward.
    var w = t.get("earWidth")
    for side in [String("L"), String("R")]:  # pragma: no branch
        var s = 1.0 if side == "L" else -1.0
        var base = rig.j("earBase" + side)
        var tip = rig.j("earTip" + side)
        var f = _ear_frame(t, s)
        var up = f[1]
        var facing = f[2]
        var lat = f[3]
        var ear_len = f[4]
        var eb = rig.bone("ear" + side)
        _ = m.cone(
            "earbase",
            eb,
            lerp(base, tip, -0.05),
            lerp(base, tip, 0.2),
            0.009,
            0.0085,
            k=0.012,
            thin=True,
        )
        _ = ell_y(
            m,
            "ear",
            eb,
            lerp(base, tip, 0.52),
            up,
            V3(0.0158 * w, 0.5 * ear_len, 0.0034),
            lateral=lat,
            k=0.01,
            thin=True,
        )
        _ = ell_y(
            m,
            "earinner",
            eb,
            lerp(base, tip, 0.56) + facing * 0.0036,
            up,
            V3(0.012 * w, 0.44 * ear_len, 0.0028),
            lateral=lat,
            k=0.003,
            carve=True,
            thin=True,
        )

    # LEGS: short slim forelegs; long hind legs with a big haunch, a slim
    # shank and a long flat foot.
    for side in [String("L"), String("R")]:  # pragma: no branch
        var s = 1.0 if side == "L" else -1.0
        var lat = V3(s, 0, 0)
        var sc = rig.j("scapTop" + side)
        var sh = rig.j("shoulder" + side)
        var e = rig.j("elbow" + side)
        var wr = rig.j("wrist" + side)
        var mc = rig.j("mcp" + side)
        var toe = rig.j("ftoe" + side)
        var hum = rig.bone("humerus" + side)
        var rad = rig.bone("radius" + side)
        var meta = rig.bone("metacarpus" + side)
        var fpaw = rig.bone("fpaw" + side)
        _ = ell_y(
            m,
            "scapmuscle",
            rig.bone("scapula" + side),
            lerp(sc, sh, 0.5) + on_side(V3(0.004, 0, 0), s),
            sh - sc,
            V3(0.012, 0.038, 0.026),
            lateral=lat,
            k=0.025,
        )
        _ = m.cone("upperarm", hum, sh, e, 0.016, 0.012, k=0.02)
        _ = ell_y(
            m,
            "triceps",
            hum,
            lerp(sh, e, 0.5) + V3(0, 0, -0.008),
            e - sh,
            V3(0.012, 0.028, 0.014),
            lateral=lat,
            k=0.015,
        )
        _ = m.cone("forearm", rad, e, wr, 0.0105, 0.0068, k=0.004)
        _ = ell_y(
            m,
            "forearmmuscle",
            rad,
            lerp(e, wr, 0.28),
            wr - e,
            V3(0.0095, 0.02, 0.0105),
            lateral=lat,
            k=0.004,
        )
        _ = m.sphere("wrist", meta, wr, 0.0072, k=0.005)
        _ = m.cone("pastern", meta, wr, mc, 0.0068, 0.0066, k=0.005)
        var dp = normalize(toe - mc)
        _ = ell_y(
            m,
            "paw",
            fpaw,
            mc + dp * 0.004 + V3(0, -0.0005, 0),
            dp,
            V3(0.0085, 0.0125, 0.0055),
            lateral=lat,
            k=0.005,
        )
        var ftoes: List[V3] = [
            V3(-0.0055, 0, -0.002),
            V3(-0.0019, 0, 0),
            V3(0.0019, 0, 0),
            V3(0.0055, 0, -0.002),
        ]
        for q in ftoes:  # pragma: no branch
            _ = m.sphere(
                "toe",
                fpaw,
                V3(toe.x + q.x * s, 0.004, toe.z - 0.004 + q.z),
                0.0036,
                k=0.003,
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
            "haunch",
            fem,
            lerp(hp, kn, 0.35) + on_side(V3(0.006, 0.002, -0.006), s),
            kn - hp,
            V3(0.026, 0.05, 0.038),
            lateral=lat,
            k=0.03,
        )
        _ = ell_y(
            m,
            "thigh",
            fem,
            lerp(hp, kn, 0.6) + on_side(V3(0.008, 0, 0), s),
            kn - hp,
            V3(0.019, 0.034, 0.026),
            lateral=lat,
            k=0.02,
        )
        _ = ell_y(
            m,
            "flankfold",
            fem,
            _rl(on_side(V3(0.036, 0.07, -0.008), s)),
            V3(0, 0.2, 0.1),
            V3(0.012, 0.028, 0.02),
            lateral=lat,
            k=0.025,
        )
        _ = ell_y(
            m,
            "haunchlow",
            tib,
            lerp(kn, hk, 0.5) + on_side(V3(0.002, 0.012, 0.008), s),
            hk - kn,
            V3(0.02, 0.036, 0.022),
            lateral=lat,
            k=0.008,
        )
        _ = m.sphere(
            "stifle", tib, kn + on_side(V3(0.002, 0, 0.002), s), 0.011, k=0.012
        )
        _ = m.cone("shin", tib, kn, hk, 0.0115, 0.0075, k=0.005)
        _ = ell_y(
            m,
            "calf",
            tib,
            lerp(kn, hk, 0.35) + on_side(V3(0.002, 0.006, -0.002), s),
            hk - kn,
            V3(0.012, 0.03, 0.014),
            lateral=lat,
            k=0.005,
        )
        _ = m.sphere("heel", mtar, hk + V3(0, 0, -0.005), 0.0095, k=0.006)
        _ = m.cone(
            "metatarsus",
            mtar,
            hk + V3(0, -0.002, 0),
            mt,
            0.0088,
            0.0078,
            k=0.006,
        )
        var dh = normalize(tt - mt)
        _ = ell_y(
            m,
            "hpaw",
            hpaw,
            mt + dh * 0.01,
            dh,
            V3(0.0095, 0.0205, 0.0058),
            lateral=lat,
            k=0.006,
        )
        var htoes: List[V3] = [
            V3(-0.0055, 0, -0.003),
            V3(-0.0019, 0, 0),
            V3(0.0019, 0, 0),
            V3(0.0055, 0, -0.003),
        ]
        for q in htoes:  # pragma: no branch
            _ = m.sphere(
                "toe",
                hpaw,
                V3(tt.x + q.x * s, 0.0042, tt.z - 0.003 + q.z),
                0.0038,
                k=0.003,
            )

    # TAIL: the scut, short, a round tuft of fur.
    _ = m.cone(
        "tailroot",
        rig.bone("tail0"),
        rig.j("tail0"),
        rig.j("tail1"),
        0.0095,
        0.0105,
        k=0.008,
    )
    for i in range(1, TAIL_SEGS):  # pragma: no branch
        var fi = Float64(i)
        _ = m.cone(
            "tail",
            rig.bone("tail" + String(i)),
            rig.j("tail" + String(i)),
            rig.j("tail" + String(i + 1)),
            0.011 - 0.002 * fi,
            0.01 - 0.002 * fi,
            k=0.006,
        )
    _ = m.sphere(
        "scut",
        rig.bone("tail1"),
        lerp(rig.j("tail1"), rig.j("tail2"), 0.6) + V3(0, 0, -0.003),
        0.0125,
        k=0.006,
    )


def rabbit_look(t: Traits) -> EyeLook:
    """Return the rabbit's eye colors: a dark brown iris that fills the
    opening, or the albino's pink iris and red pupil.

    Args:
        t: The individual.

    Returns:
        The look.
    """
    if Int(t.get("color", 0.0)) == WHITE:
        return EyeLook(
            V3(0.55, 0.12, 0.14),
            V3(0.75, 0.42, 0.44),
            V3(0.6, 0.3, 0.32),
            V3(0.6, 0.35, 0.35),
            0.42,
            0.0,
        )
    return EyeLook(
        V3(0.02, 0.011, 0.006),
        V3(0.045, 0.024, 0.012),
        V3(0.012, 0.007, 0.004),
        V3(0.03, 0.02, 0.015),
        0.52,
        0.0,
    )


def _swatches() -> List[String]:
    return [
        String("back"),
        "flank",
        "low",
        "nape",
        "face",
        "cheek",
        "eyeRing",
        "earOut",
        "earRim",
        "earIn",
        "chest",
        "belly",
        "tailTop",
        "tailUnder",
        "feet",
        "nose",
        "claw",
    ]


def _colors(color: Int) -> List[Int]:
    if color == FAWN:
        return [
            0xC08A4C,
            0xC8955A,
            0xD6A86C,
            0xD49A58,
            0xCC975C,
            0xD2A066,
            0xE8D0A4,
            0xBC8850,
            0x8A5E32,
            0xD8A898,
            0xD4A46A,
            0xF0E2C8,
            0xB07A40,
            0xF4ECDC,
            0xE0C090,
            0xC89486,
            0xD8CCBC,
        ]
    if color == BLACK:
        return [
            0x2C2826,
            0x302B28,
            0x39332F,
            0x2F2926,
            0x302B28,
            0x332D2A,
            0x39332F,
            0x2C2826,
            0x1C1918,
            0x7A6260,
            0x302B28,
            0x3E3733,
            0x1A1817,
            0x2C2724,
            0x2A2522,
            0x3A2E2C,
            0x2A2624,
        ]
    if color == WHITE:
        return [
            0xECE8E0,
            0xEEEAE2,
            0xF0ECE4,
            0xECE8E0,
            0xEEEAE2,
            0xF0ECE6,
            0xF2EEE8,
            0xE8E2DA,
            0xE4DCD2,
            0xE8B8B0,
            0xF0ECE4,
            0xF4F2EE,
            0xEEEAE2,
            0xF6F4F0,
            0xF0ECE4,
            0xD8A0A0,
            0xECE4DA,
        ]
    return [
        0x7D6C56,
        0x8D7A62,
        0xA4907A,
        0x9C6A42,
        0x937C5E,
        0x9C8A6C,
        0xCFC2A6,
        0x8A7A64,
        0x3B3024,
        0xC9A193,
        0x9A7E5C,
        0xE8E2D6,
        0x3E342A,
        0xF4F2EE,
        0xA8977E,
        0x8E6E62,
        0x6A5C50,
    ]


def rabbit_palette(t: Traits) raises -> Palette:
    """Return one rabbit's palette: its color, warmed and lightened.

    The belly, the scut's underside, the inner ear, the nose and the claws
    keep their color.

    Args:
        t: The individual.

    Returns:
        The palette, in linear light.

    Raises:
        Error: If the palette tables differ in length.
    """
    var names = _swatches()
    var base = palette_of(names, _colors(Int(t.get("color", 0.0))))
    var k = t.get("coatWarmth", 0.0)
    var l = t.get("coatLightness", 0.0)
    var out = Palette()
    for name in names:  # pragma: no branch
        var c = base.get(name)
        var fixed = (
            name == "belly"
            or name == "tailUnder"
            or name == "earIn"
            or name == "nose"
            or name == "claw"
        )
        if not fixed:
            c = V3(
                c.x * (1.0 + 0.16 * k + l),
                c.y * (1.0 + 0.04 * k + l),
                c.z * (1.0 - 0.16 * k + l),
            )
        out.set(name, c)
    out.set("dutchWhite", srgb(0xF2F0EA))
    return out^


def _agouti(color: Int) -> Float64:
    var table: List[Float64] = [1.0, 0.15, 0.0, 0.0]
    return table[color]


def _hind_foot(bone: String) -> Bool:
    return bone.startswith("hpaw") or bone.startswith("metatarsus")


def _dutch(p: V3, bone: String, region: Int) -> Float64:
    # The Dutch pattern: the signed distance, in meters, of the white
    # areas. A blaze widening to the muzzle, a white muzzle, chin and
    # throat, the forequarters in front of a saddle line behind the
    # shoulders, and white hind feet. The ears and the scut keep their
    # color.
    var h = p - HEAD_O
    var colored = region == 5 or region == 4
    if colored:
        return 1.0
    if region == 2:
        var blaze = abs(h.x) - (0.003 + 0.3 * max(0.0, h.z + 0.004))
        return min(blaze, min(0.024 - h.z, h.y + 0.027))
    var d = (-0.02 - 0.25 * (0.12 - p.y) + 0.003 * sin(p.x * 70.0)) - p.z
    if _hind_foot(bone):
        d = min(d, -0.072 - p.z)
    return d


def _region(part: SurfacePart, bone: String) -> Int:
    # 0 torso, 1 neck, 2 head, 4 tail, 5 ear.
    var head = part == JAW or bone == "head" or bone == "snout"
    var neck = bone == "neck1" or bone == "neck2"
    if head:
        return 2
    if bone.startswith("ear"):
        return 5
    if bone.startswith("tail"):
        return 4
    return 1 if neck else 0


def _jaw_dist(h: V3) -> Float64:
    # About the distance from a head-local point to the jaw.
    var chin = ellipsoid_estimate(
        h, V3(0.0, -0.0325, 0.019), V3(0.0066, 0.0048, 0.0065)
    )
    var mand = round_cone_estimate(
        h, V3(0, -0.029, -0.012), V3(0, -0.032, 0.021), 0.0105, 0.006
    )
    return min(chin, mand)


def rabbit_paint(
    pal: Palette, t: Traits, tag: String, bone: String, s: CoatSample
) -> Paint:
    """Paint one vertex of a rabbit.

    Dense agouti fur, countershaded to a white belly, a rufous nape patch
    behind the ears, pale eye rings and lips, ears with a dark rim and a
    pink inner skin, a scut dark on top and white beneath, and furred
    feet. The domestic colors and the Dutch pattern are variants.

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
    var color = Int(t.get("color", 0.0))
    var ag = _agouti(color)
    var h = p - HEAD_O
    var c: V3
    var region = _region(s.part, bone)
    if region == 2:
        if tag == "nose":
            var leather = h.z > 0.0355 and h.y > -0.024
            if leather:
                return Paint(pal.get("nose"), NOSE)
        if tag == "eyesocket":
            return Paint(srgb(0x1C1512), SKIN)
        var groove = tag == "lipcleft" or tag == "nostril"
        if groove:
            return Paint(pal.get("nose") * 0.35, SKIN)
        if s.part != JAW:
            var mouth = _jaw_dist(h) < 0.0006 and h.z > 0.0
            if mouth:
                return Paint(V3(0.3, 0.12, 0.12), SKIN)
        c = pal.get("face")
        c = mix3(
            c,
            pal.get("cheek"),
            mirrored_blob(h, V3(0.017, -0.02, -0.005), V3(0.01, 0.012, 0.02)),
        )
        # The pale eye ring, the "spectacles".
        var ring = 0.0
        var e = rabbit_eye(t)
        for sd in [1.0, -1.0]:  # pragma: no branch
            var ef = eye_frame_of(e, HEAD_O, sd)
            var de = length(p - ef.c) - (e.r + e.lid)
            ring = max(ring, smoothstep(0.0075, 0.002, de))
        c = mix3(c, pal.get("eyeRing"), ring * 0.6)
        var lips = mirrored_blob(
            h, V3(0.006, -0.03, 0.036), V3(0.009, 0.006, 0.014)
        )
        var chin = 0.9 if s.part == JAW else smoothstep(
            -0.028, -0.036, h.y
        ) * smoothstep(-0.2, -0.7, n.y)
        c = mix3(c, pal.get("belly"), clamp(max(lips * 0.7, chin), 0.0, 1.0))
        c = mix3(
            c,
            pal.get("nape"),
            smoothstep(-0.02, -0.04, h.z) * smoothstep(0.0, 0.6, n.y) * 0.6,
        )
        ag *= 0.7
    elif region == 5:
        var sd = 1.0 if p.x >= 0.0 else -1.0
        var f = _ear_frame(t, sd)
        var center = lerp(f[0], f[0] + f[1] * f[4], 0.52)
        var q = p - center
        var x_axis = normalize(cross(f[1], normalize(cross(f[3], f[1]))))
        var face = normalize(cross(f[3], f[1]))
        var along = dot(q, f[1]) / (0.5 * f[4])
        var across = dot(q, x_axis) / (0.0158 * t.get("earWidth"))
        var rim = 1.0 - (along * along + across * across) ** 0.5
        var inner = (
            (0.0 if tag == "earbase" else 1.0)
            * smoothstep(0.1, 0.5, dot(n, face))
            * smoothstep(0.02, 0.12, rim)
        )
        c = mix3(pal.get("earOut"), pal.get("earIn"), inner)
        # A thin dark rim along the upper edge and round the tip.
        var edge = (
            along > 0.1
            and color == AGOUTI
            and rim < 0.035 - 0.1 * (1.0 - smoothstep(0.1, 0.6, along))
        )
        if edge:
            c = mix3(c, pal.get("earRim"), 0.85)
        ag *= 0.5 * (1.0 - inner)
    elif region == 4:
        # The scut: dark on its upper side, bright white beneath.
        var i = 0.0 if bone == "tail0" else (1.0 if bone == "tail1" else 2.0)
        var a = (-12.0 - 12.0 * i) * pi / 180.0
        var dorsal = V3(0.0, cos(a), -sin(a))
        var top = dot(n, dorsal)
        c = mix3(
            pal.get("tailUnder"),
            pal.get("tailTop"),
            smoothstep(-0.1, 0.45, top),
        )
        ag *= 0.3
    else:
        var up = clamp(n.y, -1.0, 1.0)
        c = mix3(pal.get("low"), pal.get("flank"), smoothstep(-0.3, 0.3, up))
        c = mix3(c, pal.get("back"), smoothstep(0.3, 0.9, up))
        c = mix3(
            c,
            pal.get("nape"),
            smoothstep(0.2, 0.7, up)
            * (1.0 if region == 1 else smoothstep(0.06, 0.085, p.z))
            * 0.8,
        )
        var ventral = smoothstep(-0.1, -0.6, n.y) * smoothstep(0.14, 0.07, p.y)
        var chest = (
            smoothstep(0.03, 0.08, p.z)
            * smoothstep(0.1, 0.5, n.z)
            * smoothstep(0.15, 0.08, p.y)
        )
        c = mix3(c, pal.get("chest"), chest * 0.8)
        c = mix3(c, pal.get("belly"), max(ventral, smoothstep(0.35, 0.8, -n.y)))
        ag *= 1.0 - smoothstep(0.2, 0.7, -n.y)
        if is_limb(bone):
            var upper = bone.startswith("scapula") or bone.startswith("humerus")
            var leg = smoothstep(0.15, 0.1, p.y) if upper else 1.0
            var sd = 1.0 if p.x >= 0.0 else -1.0
            var lc = mix3(
                pal.get("flank"),
                pal.get("belly"),
                smoothstep(0.0, -0.8, n.x * sd) * 0.7,
            )
            var foot = (
                bone.startswith("fpaw")
                or bone.startswith("hpaw")
                or bone.startswith("metacarpus")
                or bone.startswith("metatarsus")
            )
            if foot:
                lc = mix3(
                    mix3(pal.get("feet"), pal.get("flank"), 0.35),
                    pal.get("belly"),
                    smoothstep(0.0, -0.7, n.y) * 0.4,
                )
            elif bone.startswith("radius"):
                lc = mix3(pal.get("feet"), pal.get("flank"), 0.5)
            if bone.startswith("femur"):
                lc = mix3(c, lc, smoothstep(0.08, 0.03, p.y))
            c = mix3(c, lc, leg)
            var bare = foot or bone.startswith("radius")
            ag *= 1.0 - 0.6 * leg * (1.0 if bare else 0.0)
    var dutch = t.get("dutch", 0.0) > 0.0
    if dutch:
        var d = _dutch(p, bone, region)
        d += (fbm3(p * 900.0, 2) - 0.5) * 0.004
        c = mix3(c, pal.get("dutchWhite"), smoothstep(0.0008, -0.0008, d))
        ag *= smoothstep(-0.001, 0.001, d)
    var cv = fbm3(p * 40.0, 3) - 0.5
    c = V3(
        c.x * (1.0 + 0.14 * cv),
        c.y * (1.0 + 0.12 * cv),
        c.z * (1.0 + 0.09 * cv),
    )
    c = grizzle(c, p, 700.0, 0.06 + 0.22 * clamp(ag, 0.0, 1.0))
    return Paint(c, FUR)
