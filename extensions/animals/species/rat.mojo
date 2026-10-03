# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The brown rat, Rattus norvegicus: procedural-animals' `species/rat/`.

A small plantigrade quadruped: a hunched pear-shaped body, a pointed
snout with yellow incisors, dark bulging eyes, thin rounded ears, pink
hands and feet with separate toes, and a long naked tail of ring scales.
The variants are wild (agouti, sometimes the dark urban form), agouti,
dark, albino and hooded. Pups are 0.6 of the size, with a big head and
big eyes, ears and feet.

The whiskers of the original are line geometry, not a solid: they are
left out.
"""

from extensions.animals.coat import (
    FUR,
    KERATIN,
    NOSE,
    SCALES,
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
from extensions.sdf.ids import (
    BoneId,
    SurfacePart,
)
from extensions.animals.parts import (
    JAW,
    TEETH,
)
from extensions.sdf.sculpt import ell_y
from extensions.animals.kit import (
    EyeSpec,
    sculpt_eye_socket,
    is_limb,
    mirrored_blob,
    hashed_stream,
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
from std.math import atan2, cos, pi, pow, sin, sqrt

comptime TAIL_SEGS = 12
# The head-local scale: the head was first measured on a smaller skull.
comptime HK = 1.12
# The torso stands this much higher than the first sculpt.
comptime UP = 0.006
# The head's origin: on the midline, level with the eye centers.
comptime HEAD_O = V3(0.0, 0.066, 0.077)
# The finest cell, at the `HERO` tier: the head's cell in the original.
comptime CELL = 0.00062

# The variants, in procedural-animals' order.
comptime WILD = 0
comptime AGOUTI = 1
comptime DARK = 2
comptime ALBINO = 3
comptime HOODED = 4


def rat_variant_names() -> List[String]:
    """Return the rat's variants.

    Returns:
        Wild, agouti, dark, albino and hooded.
    """
    return [String("wild"), "agouti", "dark", "albino", "hooded"]


def rat_traits(mut r: AnimalRandom, options: AnimalOptions) raises -> Traits:
    """Draw one rat: procedural-animals' `variation`.

    Males are larger, with a broader head and a thicker tail. The coat
    draws from its own stream, hashed from the seed, so consecutive seeds
    do not correlate.

    Args:
        r: The individual's stream.
        options: The caller's sex, age and variant.

    Returns:
        The traits.

    Raises:
        Error: If the requested variant is not one of the five.
    """
    var m = hashed_stream(options.seed, 0x5BD1E995, 0x297A2D39, 0x1B873593)
    for _ in range(3):
        _ = m.next()
    if options.variant.value >= 5:
        raise Error("The rat has no such variant")
    var variant = WILD if options.variant.value < 0 else options.variant.value
    var color = variant
    if variant == WILD:
        color = DARK if m.next() < 0.15 else AGOUTI
    var sex = pick_sex(options.sex, r)
    var t = Traits(sex, pick_age(options.age), variant)
    var juv = t.juvenile()
    var male = 1.0 if t.male() else 0.0
    var fancy = color == ALBINO or color == HOODED
    t.set(
        "size",
        (1.07 if male > 0.0 else 0.965)
        * (1.0 + 0.045 * r.g())
        * (0.6 if juv > 0.0 else 1.0),
    )
    var head = (
        (1.03 if male > 0.0 else 0.99)
        * (1.0 + 0.025 * r.g())
        * (1.22 if juv > 0.0 else 1.0)
    )
    t.set("color", Float64(color))
    t.set("tail", (1.0 + 0.05 * r.g()) * (0.86 if juv > 0.0 else 1.0))
    t.set(
        "tailThick",
        (1.0 + 0.06 * r.g())
        * (1.05 if male > 0.0 else 1.0)
        * (0.9 if juv > 0.0 else 1.0),
    )
    t.set(
        "ear",
        (1.0 + 0.06 * r.g())
        * (1.14 if juv > 0.0 else 1.0)
        * (1.04 if fancy else 1.0),
    )
    t.set("earWidth", 1.0 + 0.05 * r.g())
    t.set("headWidth", (1.05 if male > 0.0 else 1.0) * (1.0 + 0.03 * r.g()))
    t.set(
        "muzzle",
        (1.0 + 0.04 * r.g())
        * (0.86 if juv > 0.0 else 1.0)
        * (0.97 if fancy else 1.0),
    )
    t.set("whisker", (1.0 + 0.06 * r.g()) * (0.8 if juv > 0.0 else 1.0))
    var blaze = 0.0
    if color == HOODED:
        if m.next() < 0.35:
            blaze = 0.7 + 0.5 * m.next()
    t.set("blaze", blaze)
    t.set("coatWarmth", (0.9 if color == AGOUTI else 0.3) * r.g())
    t.set("coatLightness", 0.09 * r.g())
    t.set("coatSeed", Float64(Int(r.next() * 1e6)))
    t.set("minThick", 0.0005)
    t.warps.add(legs_warp(1.0 + 0.035 * r.g() - 0.04 * juv, 0.03))
    t.warps.add(
        length_warp(1.0 + 0.03 * r.g() - 0.07 * juv + 0.01 * male, -0.07, 0.03)
    )
    t.warps.add(
        girth_warp(
            1.0
            + 0.06 * r.g()
            + 0.03 * male
            - 0.04 * juv
            + (0.02 if fancy else 0.0),
            0.05,
            -0.085,
            0.04,
            0.012,
        )
    )
    t.warps.add(scale_about_warp(HEAD_O, head, 0.016, 0.034))
    if juv > 0.0:
        for paw in [
            V3(0.019, 0.003, 0.037),
            V3(-0.019, 0.003, 0.037),
            V3(0.024, 0.003, -0.028),
            V3(-0.024, 0.003, -0.028),
        ]:
            t.warps.add(scale_about_warp(paw, 1.15, 0.006, 0.014))
    return t^


def rat_eye(t: Traits) -> EyeSpec:
    """Return the rat's left eye: dark, bulging and round, set high on
    the side of the head. A pup's is larger.

    Args:
        t: The individual.

    Returns:
        The eye, head-local.
    """
    var k = 1.08 if t.juvenile() > 0.0 else 1.0
    return EyeSpec(
        V3(0.0092 * HK, 0.0008 * HK, 0.0),
        0.0039 * k,
        -0.0002,
        1.05,
        0.14,
        0.00035,
        0.0036 * k,
        0.0003,
        0.0,
        6.0 * pi / 180.0,
        0.0022 * k,
        0.0034 * k,
    )


def _hl(v: V3) -> V3:
    return HEAD_O + v * HK


def _tm(p: V3) -> V3:
    # The torso map: raised by `UP` and shortened behind the withers.
    return V3(
        p.x, p.y + UP, 0.019 + (p.z - 0.019) * 0.92 if p.z < 0.019 else p.z
    )


def _mid(a: V3, c: V3, l1: Float64, l2: Float64, pole: V3) -> V3:
    # The middle joint of a two-bone limb, bending toward `pole`.
    var d = c - a
    var span = min(length(d), (l1 + l2) * 0.999)
    var u = normalize(d)
    var x = (l1 * l1 - l2 * l2 + span * span) / (2.0 * span)
    var h = sqrt(max(0.0, l1 * l1 - x * x))
    var q = normalize(pole - u * dot(pole, u))
    return a + u * x + q * h


def _tail_joints(t: Traits) -> List[V3]:
    # The tail's joints, from its base to its tip: it slopes down from
    # the rump and trails just above the ground.
    var tk = t.get("tail")
    var angles: List[Float64] = [
        -52,
        -45,
        -32,
        -19,
        -10,
        -4,
        -1.5,
        0,
        0,
        0,
        0,
        1,
    ]
    var lens: List[Float64] = [
        0.0145,
        0.0148,
        0.015,
        0.0155,
        0.016,
        0.016,
        0.016,
        0.016,
        0.016,
        0.016,
        0.016,
        0.0155,
    ]
    var p = _tm(V3(0.0, 0.047, -0.087))
    var out: List[V3] = [p]
    for i in range(TAIL_SEGS):
        var a = angles[i] * pi / 180.0
        p = V3(p.x, p.y + sin(a) * lens[i] * tk, p.z - cos(a) * lens[i] * tk)
        out.append(p)
    return out^


def _ear_tip(t: Traits) -> V3:
    var ek = t.get("ear")
    return _hl(
        V3(0.0115 + 0.0085 * ek, 0.009 + 0.0185 * ek, -0.0195 - 0.0045 * ek)
    )


def rat_rig(t: Traits) raises -> Rig:
    """Return the rat's skeleton in bind pose.

    The rat stands crouched: the knee deeply flexed against the belly,
    the whole hind sole flat on the ground, the elbows close to the chest
    floor and the forefeet on their palms. A snout bone carries the nose
    and the whisker pads.

    Args:
        t: The individual.

    Returns:
        The rig.

    Raises:
        Error: If a bone names a missing joint.
    """
    var rig = Rig()
    rig.set("nose", _hl(V3(0.0, -0.0125, 0.0235)))
    rig.set("occiput", _hl(V3(0.0, 0.004, -0.026)))
    rig.set("neckMid", _tm(V3(0.0, 0.058, 0.034)))
    rig.set("neckBase", _tm(V3(0.0, 0.06, 0.019)))
    rig.set("chestMid", _tm(V3(0.0, 0.07, 0.0)))
    rig.set("thoraxRear", _tm(V3(0.0, 0.062, -0.03)))
    rig.set("lumbarMid", _tm(V3(0.0, 0.064, -0.055)))
    rig.set("lumbosacral", _tm(V3(0.0, 0.066, -0.071)))
    rig.set("tailBase", _tm(V3(0.0, 0.047, -0.087)))
    var shoulder = _tm(V3(0.0175, 0.048, 0.033))
    var wrist = V3(0.019, 0.0065, 0.029)
    var hip = _tm(V3(0.018, 0.054, -0.055))
    var hock = V3(0.0235, 0.0062, -0.042)
    rig.set("scapTopL", _tm(V3(0.013, 0.066, 0.008)))
    rig.set("shoulderL", shoulder)
    rig.set("elbowL", _mid(shoulder, wrist, 0.028, 0.029, V3(0.1, 0, -1)))
    rig.set("wristL", wrist)
    rig.set("mcpL", V3(0.019, 0.0042, 0.037))
    rig.set("ftoeL", V3(0.0195, 0.0018, 0.047))
    rig.set("hipL", hip)
    rig.set("kneeL", _mid(hip, hock, 0.036, 0.041, V3(0.12, 0, 1)))
    rig.set("hockL", hock)
    rig.set("mtpL", V3(0.024, 0.0045, -0.015))
    rig.set("htoeL", V3(0.0245, 0.0018, -0.002))
    rig.set("snoutBase", _hl(V3(0.0, -0.009, 0.012)))
    rig.set("jawHinge", _hl(V3(0.0, -0.011, -0.012)))
    rig.set("jawTip", _hl(V3(0.0, -0.0215, 0.0175)))
    rig.set("earBaseL", _hl(V3(0.0115, 0.009, -0.0195)))
    rig.set("earTipL", _ear_tip(t))
    var tk = t.get("tail")
    var angles: List[Float64] = [
        -52,
        -45,
        -32,
        -19,
        -10,
        -4,
        -1.5,
        0,
        0,
        0,
        0,
        1,
    ]
    var lens: List[Float64] = [
        0.0145 * tk,
        0.0148 * tk,
        0.015 * tk,
        0.0155 * tk,
        0.016 * tk,
        0.016 * tk,
        0.016 * tk,
        0.016 * tk,
        0.016 * tk,
        0.016 * tk,
        0.016 * tk,
        0.0155 * tk,
    ]
    tail_chain(rig, "tailBase", angles, lens)
    rig.mirror_joints()
    quadruped_bones(rig, TAIL_SEGS)
    _ = rig.add_bone("snout", "snoutBase", "nose", "head")
    return rig^


def _ear_frame(t: Traits, s: Float64) -> Tuple[V3, V3, V3, V3, Float64]:
    # One ear's base, its up axis, the direction its cup faces, its
    # lateral axis and its length.
    var b0 = _hl(V3(0.0115, 0.009, -0.0195))
    var t0 = _ear_tip(t)
    var base = V3(b0.x * s, b0.y, b0.z)
    var tip = V3(t0.x * s, t0.y, t0.z)
    var up = normalize(tip - base)
    var facing0 = normalize(V3(0.55 * s, 0.05, 0.85))
    var facing = normalize(facing0 - up * dot(facing0, up))
    return (base, up, facing, normalize(cross(up, facing)), length(tip - base))


def _toes(
    mut m: SdfModel,
    bone: BoneId,
    mp: V3,
    tp: V3,
    s: Float64,
    spec: List[List[Float64]],
    claw: Float64,
) raises:
    # Digits fanned from the metapodial head. Each row of `spec` is the
    # yaw in degrees, the length, the radius and, if given, the drop.
    var fwd = normalize(V3(tp.x - mp.x, 0.0, tp.z - mp.z))
    for row in spec:
        var ang = row[0] * pi / 180.0 * s
        var r = row[2]
        var d = normalize(
            V3(
                fwd.x * cos(ang) + fwd.z * sin(ang),
                0.0,
                -fwd.x * sin(ang) + fwd.z * cos(ang),
            )
        )
        var root = V3(
            mp.x + d.x * 0.0012 + sin(ang) * 0.0018,
            mp.y + 0.0003,
            mp.z + d.z * 0.0012,
        )
        var drop = row[3] if len(row) > 3 else r * 0.9
        var tip = V3(root.x + d.x * row[1], drop, root.z + d.z * row[1])
        _ = m.cone("toe", bone, root, tip, r, r * 0.78, k=0.0006)
        _ = m.sphere(
            "pad",
            bone,
            V3(tip.x - d.x * 0.0008, r * 0.85, tip.z - d.z * 0.0008),
            r * 0.95,
            k=0.0005,
        )
        _ = m.cone(
            "claw",
            bone,
            V3(tip.x - d.x * 0.0004, r * 1.05, tip.z - d.z * 0.0004),
            V3(tip.x + d.x * claw, 0.0003, tip.z + d.z * claw),
            r * 0.55,
            0.00015,
            k=0.0003,
        )


def rat_sculpt(mut m: SdfModel, rig: Rig, t: Traits) raises:
    """Sculpt the rat: procedural-animals' `sculptRat`, primitive for
    primitive.

    Args:
        m: The sculpt to add to.
        rig: The rat's rig in bind pose.
        t: The individual.

    Raises:
        Error: If the rig lacks a joint or a bone, or the sculpt refuses
            a primitive.
    """
    # TORSO: pear-shaped, highest over the loins.
    var chest = rig.bone("chest")
    var spine2 = rig.bone("spine2")
    var pelvis = rig.bone("pelvis")
    _ = m.ell(
        "ribcage",
        rig.bone("spine3"),
        _tm(V3(0, 0.048, -0.006)),
        V3(0.0265, 0.022, 0.034 * 0.92),
        axis=normalize(V3(0, 0.25, 1)),
        k=0,
    )
    _ = m.ell(
        "brisket",
        chest,
        _tm(V3(0, 0.037, 0.02)),
        V3(0.018, 0.02, 0.02 * 0.92),
        axis=normalize(V3(0, -0.4, 1)),
        k=0.012,
    )
    _ = m.ell(
        "withers",
        chest,
        _tm(V3(0, 0.056, 0.006)),
        V3(0.019, 0.011, 0.022 * 0.92),
        axis=normalize(V3(0, 0.3, 1)),
        k=0.018,
    )
    _ = m.ell(
        "back",
        spine2,
        _tm(V3(0, 0.052, -0.037)),
        V3(0.029, 0.016, 0.035 * 0.92),
        axis=normalize(V3(0, 0.15, 1)),
        k=0.022,
    )
    _ = m.ell(
        "abdomen",
        spine2,
        _tm(V3(0, 0.045, -0.036)),
        V3(0.031, 0.021, 0.037 * 0.92),
        k=0.022,
    )
    _ = m.ell(
        "loin",
        rig.bone("spine1"),
        _tm(V3(0, 0.055, -0.054)),
        V3(0.029, 0.018, 0.029 * 0.92),
        axis=normalize(V3(0, -0.5, 1)),
        k=0.02,
    )
    _ = m.ell(
        "rump",
        pelvis,
        _tm(V3(0, 0.046, -0.067)),
        V3(0.028, 0.0195, 0.027 * 0.92),
        k=0.02,
    )
    _ = m.ell(
        "rumpback",
        pelvis,
        _tm(V3(0, 0.045, -0.079)),
        V3(0.021, 0.017, 0.018 * 0.92),
        k=0.012,
    )
    if t.male():
        _ = m.ell(
            "scrotum",
            pelvis,
            _tm(V3(0, 0.03, -0.084)),
            V3(0.012, 0.012, 0.011 * 0.92),
            k=0.008,
        )

    # NECK: none visible, the head merges into the shoulders.
    var n1 = rig.bone("neck1")
    _ = m.cone(
        "neck",
        n1,
        _tm(V3(0, 0.047, 0.018)),
        rig.j("neckMid"),
        0.019,
        0.0155,
        k=0.012,
    )
    _ = m.cone(
        "neck",
        rig.bone("neck2"),
        rig.j("neckMid"),
        _hl(V3(0, -0.001, -0.014)),
        0.0155,
        0.0135,
        k=0.01,
    )
    _ = m.ell(
        "throat",
        n1,
        _tm(V3(0, 0.041, 0.037)),
        V3(0.014, 0.012, 0.016 * 0.92),
        k=0.012,
    )

    # HEAD, in head-local coordinates.
    var h = rig.bone("head")
    var hw = t.get("headWidth")
    var mz = t.get("muzzle")
    _ = m.ell(
        "cranium",
        h,
        _hl(V3(0, 0.0005, -0.0125)),
        V3(0.0108 * hw * HK, 0.0098 * HK, 0.0165 * HK),
        k=0.008,
    )
    _ = m.cone(
        "nasal",
        h,
        _hl(V3(0, 0.0015, -0.004)),
        _hz(V3(0, -0.0075, 0.0185), mz),
        0.0082 * hw * HK,
        0.0041 * HK,
        k=0.006,
    )
    for s in [1.0, -1.0]:
        _ = m.ell(
            "cheek",
            h,
            _hl(V3(0.0072 * s * hw, -0.0095, -0.0085)),
            V3(0.0058 * HK, 0.0074 * HK, 0.0105 * HK),
            k=0.007,
        )
        _ = m.ell(
            "brow",
            h,
            _hl(V3(0.0062 * s, 0.0052, 0.0005)),
            V3(0.004 * HK, 0.0028 * HK, 0.0065 * HK),
            k=0.004,
        )
        _ = m.ell(
            "jowl",
            h,
            _hl(V3(0.0058 * s, -0.0135, -0.016)),
            V3(0.0056 * HK, 0.0064 * HK, 0.0085 * HK),
            k=0.007,
        )
    _ = m.ell(
        "muzzle",
        h,
        _hz(V3(0, -0.0098, 0.0095), mz),
        V3(0.0058 * hw * HK, 0.0064 * HK, 0.009 * HK),
        k=0.005,
    )
    var eye = rat_eye(t)
    for s in [1.0, -1.0]:
        _ = sculpt_eye_socket(
            m,
            eye,
            HEAD_O,
            s,
            h,
            orbit_r=V3(0.0036 * HK, 0.003 * HK, 0.0018 * HK),
            orbit_at=V3(0.0, 0.0, 0.0028 * HK),
            orbit_k=0.0014,
        )

    # SNOUT: the pink nose, the whisker pads and the split upper lip.
    var sn = rig.bone("snout")
    for s in [1.0, -1.0]:
        _ = m.ell(
            "whisker",
            sn,
            _hz(V3(0.0037 * s, -0.0124, 0.0148), mz),
            V3(0.0041 * HK, 0.0042 * HK, 0.0062 * HK),
            k=0.003,
        )
        _ = m.sphere(
            "nostril",
            sn,
            _hz(V3(0.0014 * s, -0.0113, 0.0238), mz),
            0.0005 * HK,
            k=0.0005,
            carve=True,
        )
    _ = m.ell(
        "nose",
        sn,
        _hz(V3(0, -0.0112, 0.0222), mz),
        V3(0.0027 * HK, 0.0021 * HK, 0.002 * HK),
        axis=normalize(V3(0, 0.5, 1)),
        k=0.002,
    )
    _ = m.cone(
        "lipcleft",
        sn,
        _hz(V3(0, -0.0142, 0.0222), mz),
        _hz(V3(0, -0.0168, 0.0196), mz),
        0.0004 * HK,
        0.0007 * HK,
        k=0.0006,
        carve=True,
    )

    # JAW: short, set back under the upper lip.
    var jw = rig.bone("jaw")
    _ = m.cone(
        "mandible",
        jw,
        _hl(V3(0, -0.0145, -0.012)),
        _hz(V3(0, -0.0178, 0.0135), mz),
        0.0055 * HK,
        0.0032 * HK,
        k=0,
        part=JAW,
    )
    _ = m.ell(
        "chin",
        jw,
        _hz(V3(0, -0.0188, 0.0128), mz),
        V3(0.0034 * HK, 0.0026 * HK, 0.0036 * HK),
        k=0.002,
        part=JAW,
    )

    # INCISORS: the uppers emerge under the split lip, the lowers behind
    # them.
    for s in [1.0, -1.0]:
        _ = m.cone(
            "incisor",
            h,
            _hz(V3(0.0008 * s, -0.0146, 0.0178), mz),
            _hz(V3(0.0008 * s, -0.0167, 0.0177), mz),
            0.00058 * HK,
            0.0005 * HK,
            k=0,
            part=TEETH,
        )
        _ = m.cone(
            "incisor",
            jw,
            _hz(V3(0.00072 * s, -0.019, 0.0146), mz),
            _hz(V3(0.00072 * s, -0.0172, 0.0164), mz),
            0.0005 * HK,
            0.00043 * HK,
            k=0,
            part=TEETH,
        )

    # EARS: thin, rounded and nearly bare, the cup facing forward and out.
    var ew = t.get("earWidth")
    for side in [String("L"), String("R")]:
        var s = 1.0 if side == "L" else -1.0
        var base = rig.j("earBase" + side)
        var tip = rig.j("earTip" + side)
        var f = _ear_frame(t, s)
        var eb = rig.bone("ear" + side)
        _ = m.cone(
            "earbase",
            eb,
            lerp(base, tip, -0.15),
            lerp(base, tip, 0.18),
            0.0042,
            0.0036,
            k=0.004,
            thin=True,
        )
        _ = ell_y(
            m,
            "ear",
            eb,
            lerp(base, tip, 0.5),
            f[1],
            V3(0.0086 * ew, 0.52 * f[4], 0.0015),
            lateral=f[3],
            k=0.003,
            thin=True,
        )
        _ = ell_y(
            m,
            "earinner",
            eb,
            lerp(base, tip, 0.52) + f[2] * 0.0017,
            f[1],
            V3(0.0073 * ew, 0.45 * f[4], 0.0013),
            lateral=f[3],
            k=0.001,
            carve=True,
            thin=True,
        )

    # LEGS: short slim forelegs on plantigrade hands with four long
    # fingers and a thumb stub; hind legs with the thigh hidden in the
    # body, a slim shank and a long bare sole with five toes.
    var fspec: List[List[Float64]] = [
        [-38, 0.0056, 0.00078],
        [-11, 0.0078, 0.0008],
        [10, 0.0082, 0.0008],
        [34, 0.0068, 0.00076],
    ]
    var hspec: List[List[Float64]] = [
        [-40, 0.0058, 0.00085, 0.0008],
        [-15, 0.0098, 0.0009],
        [2, 0.0108, 0.0009],
        [18, 0.0102, 0.0009],
        [40, 0.0086, 0.00086],
    ]
    for side in [String("L"), String("R")]:
        var s = 1.0 if side == "L" else -1.0
        var lat = V3(s, 0, 0)
        var sc = rig.j("scapTop" + side)
        var sh = rig.j("shoulder" + side)
        var e = rig.j("elbow" + side)
        var w = rig.j("wrist" + side)
        var mc = rig.j("mcp" + side)
        var toe = rig.j("ftoe" + side)
        var hum = rig.bone("humerus" + side)
        var rad = rig.bone("radius" + side)
        var meta = rig.bone("metacarpus" + side)
        _ = ell_y(
            m,
            "scapmuscle",
            rig.bone("scapula" + side),
            lerp(sc, sh, 0.5) + on_side(V3(0.002, 0, 0), s),
            sh - sc,
            V3(0.0065, 0.016, 0.012),
            lateral=lat,
            k=0.01,
        )
        _ = m.cone("upperarm", hum, sh, e, 0.0075, 0.0055, k=0.008)
        _ = ell_y(
            m,
            "triceps",
            hum,
            lerp(sh, e, 0.55) + V3(0, 0, -0.003),
            e - sh,
            V3(0.0055, 0.011, 0.0065),
            lateral=lat,
            k=0.006,
        )
        _ = m.cone("forearm", rad, e, w, 0.0044, 0.0024, k=0.002)
        _ = ell_y(
            m,
            "forearmmuscle",
            rad,
            lerp(e, w, 0.3),
            w - e,
            V3(0.0038, 0.008, 0.0042),
            lateral=lat,
            k=0.002,
        )
        _ = m.sphere("wrist", meta, w, 0.0025, k=0.0015)
        var dp = normalize(mc - w)
        _ = ell_y(
            m,
            "palm",
            meta,
            lerp(w, mc, 0.55) + V3(0, -0.0004, 0),
            dp,
            V3(0.0032, 0.0062, 0.0018),
            lateral=lat,
            k=0.0015,
        )
        _toes(m, rig.bone("fpaw" + side), mc, toe, s, fspec, 0.0017)
        _ = m.sphere(
            "toe",
            meta,
            w + on_side(V3(-0.0026, -0.002, 0.004), s),
            0.0011,
            k=0.0006,
        )

        var hp = rig.j("hip" + side)
        var kn = rig.j("knee" + side)
        var hk = rig.j("hock" + side)
        var mt = rig.j("mtp" + side)
        var tt = rig.j("htoe" + side)
        var fem = rig.bone("femur" + side)
        var tib = rig.bone("tibia" + side)
        var mtar = rig.bone("metatarsus" + side)
        _ = ell_y(
            m,
            "haunch",
            fem,
            lerp(hp, kn, 0.4) + on_side(V3(0.004, 0.002, -0.004), s),
            kn - hp,
            V3(0.013, 0.021, 0.018),
            lateral=lat,
            k=0.012,
        )
        _ = ell_y(
            m,
            "thigh",
            fem,
            lerp(hp, kn, 0.65) + on_side(V3(0.004, -0.002, 0.0), s),
            kn - hp,
            V3(0.009, 0.014, 0.011),
            lateral=lat,
            k=0.008,
        )
        _ = ell_y(
            m,
            "flankfold",
            fem,
            _tm(on_side(V3(0.023, 0.042, -0.03), s)),
            V3(0, 0.3, 0.1),
            V3(0.006, 0.013, 0.011),
            lateral=lat,
            k=0.01,
        )
        _ = m.sphere(
            "stifle", tib, kn + on_side(V3(0.001, 0, 0.001), s), 0.0052, k=0.005
        )
        _ = m.cone("shin", tib, kn, hk, 0.0052, 0.0027, k=0.002)
        _ = ell_y(
            m,
            "calf",
            tib,
            lerp(kn, hk, 0.35) + on_side(V3(0.0008, 0.0015, -0.0022), s),
            hk - kn,
            V3(0.0045, 0.011, 0.0055),
            lateral=lat,
            k=0.002,
        )
        _ = m.sphere(
            "heel", mtar, hk + V3(0, -0.0008, -0.001), 0.0028, k=0.0015
        )
        var dh = normalize(mt - hk)
        _ = ell_y(
            m,
            "sole",
            mtar,
            lerp(hk, mt, 0.55) + V3(0, -0.0006, 0),
            dh,
            V3(0.0034, 0.0148, 0.0019),
            lateral=lat,
            k=0.0015,
        )
        _toes(m, rig.bone("hpaw" + side), mt, tt, s, hspec, 0.0018)

    # TAIL: long, thick at the root, tapering and scaly.
    var thick = t.get("tailThick")
    _ = m.cone(
        "tailroot",
        rig.bone("tail0"),
        lerp(rig.j("tail0"), rig.j("tail1"), -0.3),
        rig.j("tail1"),
        0.0062,
        _tail_r(1, thick),
        k=0.008,
    )
    for i in range(1, TAIL_SEGS):
        var a = rig.j("tail" + String(i))
        var b = rig.j("tail" + String(i + 1))
        var tb = rig.bone("tail" + String(i))
        var ra = _tail_r(i, thick)
        var rb = 0.0008 if i == TAIL_SEGS - 1 else _tail_r(i + 1, thick)
        _ = m.cone("tail", tb, a, b, ra, rb, k=0.0006)
        # A thin core: inflated at the coarse tiers, so the tail never
        # breaks up.
        var d = normalize(b - a)
        _ = m.ell(
            "tailcore",
            tb,
            lerp(a, b, 0.5),
            V3(ra * 0.6, ra * 0.6, length(b - a) * 0.62),
            axis=d,
            up=normalize(cross(d, V3(1, 0, 0))),
            k=0.0006,
            thin=True,
        )


def _tail_r(i: Int, thick: Float64) -> Float64:
    return (
        0.0042
        * pow(1.0 - Float64(i) / (Float64(TAIL_SEGS) + 1.5), 0.85)
        * thick
    )


def _hz(v: V3, mz: Float64) -> V3:
    # A head-local point, the muzzle stretched ahead of 4 mm.
    return _hl(V3(v.x, v.y, 0.004 + (v.z - 0.004) * mz if v.z > 0.004 else v.z))


def rat_look(t: Traits) -> EyeLook:
    """Return the rat's eye colors: a glossy near-black bead, or the
    albino's red eye.

    Args:
        t: The individual.

    Returns:
        The look.
    """
    if Int(t.get("color", 0.0)) == ALBINO:
        return EyeLook(
            V3(0.35, 0.02, 0.03),
            V3(0.45, 0.04, 0.05),
            V3(0.3, 0.05, 0.06),
            V3(0.4, 0.1, 0.1),
            0.52,
            0.0,
        )
    return EyeLook(
        V3(0.006, 0.003, 0.0025),
        V3(0.011, 0.006, 0.005),
        V3(0.004, 0.0025, 0.002),
        V3(0.01, 0.007, 0.006),
        0.62,
        0.0,
    )


def _swatches() -> List[String]:
    return [
        String("back"),
        "flank",
        "low",
        "belly",
        "head",
        "cheek",
        "muzzle",
        "earSkin",
        "earIn",
        "feet",
        "tailTop",
        "tailUnder",
        "nose",
        "claw",
    ]


def _colors(color: Int) -> List[Int]:
    if color == DARK:
        return [
            0x3E3833,
            0x3A3430,
            0x4A433D,
            0x7A746C,
            0x3C3632,
            0x423B36,
            0x4A423C,
            0x6E5A56,
            0x86706A,
            0xB89A92,
            0x36302C,
            0x5A504A,
            0x9A7276,
            0xC8B8A8,
        ]
    if color == ALBINO:
        return [
            0xF0ECE4,
            0xF2EEE6,
            0xF2EEE8,
            0xF5F2EC,
            0xF2EEE6,
            0xF4F0EA,
            0xF4EFE8,
            0xE8B9B0,
            0xEAB4AC,
            0xEBBFB6,
            0xE4B8AE,
            0xE8C2B8,
            0xEAAFAF,
            0xF0E6DC,
        ]
    if color == HOODED:
        return [
            0xF0EDE6,
            0xF0EDE6,
            0xF2EFE8,
            0xF2EFE8,
            0xF0EDE6,
            0xF0EDE6,
            0xF2EEE8,
            0xA88480,
            0xC49A94,
            0xEBBFB6,
            0x8A7872,
            0xD8B4AA,
            0xD89A9A,
            0xF0E6DC,
        ]
    return [
        0x615446,
        0x5A4F45,
        0x756B61,
        0xA39A8C,
        0x605244,
        0x6B5E50,
        0x716558,
        0xA07C6E,
        0xB88C80,
        0xCFAEA2,
        0x4A3E38,
        0x7E6E66,
        0xB9868A,
        0xD8C8B4,
    ]


def rat_palette(t: Traits) raises -> Palette:
    """Return one rat's palette: its color, warmed and lightened.

    The bare skin, the belly and the claws keep their color, as do the
    albino and the hooded rat. A pup's fur is softer and grayer.

    Args:
        t: The individual.

    Returns:
        The palette, in linear light.

    Raises:
        Error: If the palette tables differ in length.
    """
    var color = Int(t.get("color", 0.0))
    var names = _swatches()
    var base = palette_of(names, _colors(color))
    var k = t.get("coatWarmth", 0.0)
    var l = t.get("coatLightness", 0.0)
    var fancy = color == ALBINO or color == HOODED
    var juv = t.juvenile() > 0.0 and not fancy
    var out = Palette()
    for name in names:
        var c = base.get(name)
        var fixed = (
            fancy
            or name == "belly"
            or name == "earSkin"
            or name == "earIn"
            or name == "feet"
            or name == "nose"
            or name == "claw"
            or name == "tailUnder"
        )
        if not fixed:
            c = V3(
                c.x * (1.0 + 0.12 * k + l),
                c.y * (1.0 + 0.03 * k + l),
                c.z * (1.0 - 0.12 * k + l),
            )
        var furry = (
            name == "back"
            or name == "flank"
            or name == "low"
            or name == "head"
            or name == "cheek"
        )
        var gray = juv and furry
        var g = (c.x + c.y + c.z) / 3.0
        c = mix3(c, V3(g, g, g * 1.03), 0.35 if gray else 0.0)
        out.set(name, c)
    out.set("hood", srgb(0x221E1E))
    out.set("tooth", srgb(0xD4A050))
    out.set("toothTip", srgb(0xEED8A8))
    return out^


def _agouti(color: Int) -> Float64:
    var table: List[Float64] = [0.95, 0.95, 0.45, 0.0, 0.0]
    return table[color]


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


def _foot(bone: String) -> Bool:
    return (
        bone.startswith("fpaw")
        or bone.startswith("hpaw")
        or bone.startswith("metacarpus")
        or bone.startswith("metatarsus")
    )


def _hood(t: Traits, p: V3, n: V3, bone: String, region: Int) -> Float64:
    # The hooded pattern: the signed distance, in meters, of the black
    # hood over the head, the neck, the shoulders and the chest, and of
    # the dorsal stripe to the tail root. A blazed rat has a white wedge
    # up the face from the nose.
    var face = region == 2 or region == 5
    if face:
        var blaze = t.get("blaze", 0.0)
        var h = (p - HEAD_O) * (1.0 / HK)
        var blazed = blaze > 0.0 and h.y > -0.02
        if blazed:
            var b = abs(h.x) - (0.0012 + 0.16 * max(0.0, h.z + 0.012)) * blaze
            var front = h.z > -0.014
            # (Behind the eyes the hood keeps a margin: the original's
            # 4 mm left the side of the head on the hood's very edge.)
            return clamp(-b, -0.004, 0.004) * (1.0 if front else -1.0) - (
                0.0 if front else 0.005
            )
        return -0.006
    if region == 4:
        return 0.006
    var d = 0.004 + 0.3 * (p.y - 0.04) + 0.0012 * sin(p.x * 700.0) - p.z
    var foreleg = (
        bone.startswith("radius")
        or bone.startswith("metacarpus")
        or bone.startswith("fpaw")
    )
    if foreleg:
        d = max(d, 0.003)
    if n.y < -0.3:
        d = max(d, -0.002 + (0.03 - p.y) * 0.4)
    var w = (
        0.0085
        * (1.0 + 0.15 * sin(p.z * 180.0))
        * smoothstep(-0.095, -0.075, p.z)
        + 0.002
    )
    var up = smoothstep(0.1, 0.5, n.y)
    var stripe = abs(p.x) - w * up if up > 0.0 else 0.01
    return clamp(min(d, stripe), -0.006, 0.006)


def _tail_paint(pal: Palette, t: Traits, p: V3, n: V3) -> Paint:
    # The naked tail: ring scales across its axis, about 1 mm apart,
    # dark above and paler below, a little paler toward the tip. The
    # rump's fur runs a little way onto its root.
    var joints = _tail_joints(t)
    var best = 1e9

    var total = 0.0
    var at = 0.0
    var dir = V3(0.0, 0.0, -1.0)
    for i in range(TAIL_SEGS):
        var a = joints[i]
        var ab = joints[i + 1] - a
        var seg = length(ab)
        var u = clamp(dot(p - a, ab) / (seg * seg), 0.0, 1.0)
        var dd = length(p - (a + ab * u))
        if dd < best:
            best = dd
            at = total + seg * u
            dir = ab * (1.0 / seg)
        total += seg
    var along = at / total
    var dorsal = normalize(cross(V3(1.0, 0.0, 0.0), dir))
    var top = dot(n, dorsal)
    var c = mix3(
        pal.get("tailUnder"), pal.get("tailTop"), smoothstep(-0.45, 0.35, top)
    )
    c = mix3(c, pal.get("tailUnder"), 0.25 * along)
    if at < 0.009:
        return Paint(
            grizzle(
                mix3(pal.get("flank"), pal.get("tailTop"), 0.4), p, 900.0, 0.2
            ),
            FUR,
        )
    # The scutes: rings across the tail, staggered round it. A real ring
    # is about 1 mm, finer than the mesh: two of them make one band here,
    # so the vertex colors can still show them.
    var pitch = (
        0.0022 * (1.0 - 0.35 * along) * (0.75 if t.juvenile() > 0.0 else 1.0)
    )
    var side = normalize(cross(V3(0.0, 1.0, 0.0), dir))
    var around = (atan2(dot(n, dorsal), dot(n, side)) + pi) / (2.0 * pi)
    var column = Int(around * 10.0)
    var ring = at / pitch + 0.5 * Float64(column % 2)
    var groove = 0.5 + 0.5 * cos(2.0 * pi * ring)
    c = c * (1.0 - 0.3 * groove * groove)
    return Paint(c, SCALES)


def rat_paint(
    pal: Palette, t: Traits, tag: String, bone: String, s: CoatSample
) -> Paint:
    """Paint one vertex of a rat.

    Coarse agouti fur countershaded to a gray-buff belly with a fairly
    sharp flank line, short sleek fur on the face, nearly bare pink-brown
    ears, pink hands and feet with pale claws, the naked tail of ring
    scales, a pink nose and orange-yellow incisors. The hooded rat wears a
    black hood and dorsal stripe on white.

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
    var albino = color == ALBINO
    var hooded = color == HOODED
    var h = (p - HEAD_O) * (1.0 / HK)
    if s.part == TEETH:
        var tip = smoothstep(
            -0.016, -0.019, h.y
        ) if bone == "head" else smoothstep(-0.019, -0.0165, h.y)
        var tc = mix3(
            pal.get("tooth"), pal.get("toothTip"), 0.5 if albino else tip * 0.6
        )
        return Paint(tc, KERATIN)
    if tag == "claw":
        return Paint(pal.get("claw"), KERATIN)
    var region = _region(s.part, bone)
    var ag = _agouti(color)
    var c: V3
    if region == 4:
        var tail = _tail_paint(pal, t, p, n)
        var done = tail.surface == SCALES or not hooded
        if done:
            return tail
        c = tail.color
    elif region == 5:
        var sd = 1.0 if p.x >= 0.0 else -1.0
        var f = _ear_frame(t, sd)
        var center = lerp(f[0], f[0] + f[1] * f[4], 0.5)
        var q = p - center
        var face = normalize(cross(f[3], f[1]))
        var x_axis = normalize(cross(f[1], face))
        var along = dot(q, f[1]) / (0.52 * f[4])
        var across = dot(q, x_axis) / (0.0086 * t.get("earWidth"))
        var rim = 1.0 - (along * along + across * across) ** 0.5
        var inner = smoothstep(0.0, 0.4, dot(n, face)) * smoothstep(
            0.02, 0.12, rim
        )
        c = mix3(pal.get("earSkin"), pal.get("earIn"), inner)
        var root = smoothstep(-0.2, -0.75, along)
        return Paint(mix3(c, pal.get("head"), root), SKIN)
    elif region == 2:
        if tag == "nose":
            var leather = h.z > 0.0205 * t.get("muzzle") and h.y > -0.0145
            if leather:
                return Paint(pal.get("nose"), NOSE)
        if tag == "eyesocket":
            return Paint(srgb(0x1A1210), SKIN)
        var groove = tag == "lipcleft" or tag == "nostril"
        if groove:
            return Paint(pal.get("nose") * 0.4, SKIN)
        c = pal.get("head")
        c = mix3(
            c,
            pal.get("cheek"),
            mirrored_blob(h, V3(0.009, -0.01, -0.006), V3(0.005, 0.006, 0.01)),
        )
        c = mix3(c, pal.get("muzzle"), smoothstep(0.004, 0.018, h.z) * 0.8)
        var chin = 0.7 if s.part == JAW else smoothstep(
            -0.015, -0.019, h.y
        ) * smoothstep(-0.2, -0.7, n.y)
        c = mix3(c, pal.get("belly"), clamp(chin, 0.0, 1.0) * 0.8)
        ag *= 0.75
    else:
        var up = clamp(n.y, -1.0, 1.0)
        c = mix3(pal.get("low"), pal.get("flank"), smoothstep(-0.35, 0.2, up))
        c = mix3(c, pal.get("back"), smoothstep(0.25, 0.85, up))
        var ventral = smoothstep(-0.2, -0.55, n.y) * smoothstep(
            0.045, 0.02, p.y
        )
        var chest = (
            smoothstep(0.0, 0.03, p.z)
            * smoothstep(0.2, 0.6, n.z)
            * smoothstep(0.045, 0.02, p.y)
        )
        c = mix3(
            c,
            pal.get("belly"),
            clamp(
                max(ventral, max(chest * 0.8, smoothstep(0.4, 0.8, -n.y))),
                0.0,
                1.0,
            ),
        )
        ag *= 1.0 - smoothstep(0.1, 0.6, -n.y)
        if is_limb(bone):
            var sd = 1.0 if p.x >= 0.0 else -1.0
            var upper = bone.startswith("scapula") or bone.startswith("humerus")
            var leg = smoothstep(0.05, 0.03, p.y) if upper else 1.0
            var bare = _foot(bone) and p.y < 0.013
            if bare:
                var skin = pal.get("feet")
                # The soles: the bare pads, a little darker.
                var sole = tag == "pad" or n.y < -0.5
                skin = mix3(
                    skin,
                    V3(skin.x * 0.85, skin.y * 0.78, skin.z * 0.78),
                    0.6 if sole else 0.0,
                )
                return Paint(skin, SKIN)
            var lc = mix3(
                pal.get("flank"),
                pal.get("belly"),
                smoothstep(0.0, -0.8, n.x * sd) * 0.6,
            )
            var lower = bone.startswith("radius") or bone.startswith("tibia")
            if lower:
                var sk = smoothstep(0.016, 0.006, p.y)
                lc = mix3(
                    mix3(pal.get("flank"), pal.get("belly"), 0.35),
                    pal.get("feet"),
                    sk * 0.6,
                )
            if bone.startswith("femur"):
                lc = mix3(c, lc, smoothstep(0.035, 0.015, p.y))
            c = mix3(c, lc, leg)
            var distal = lower or _foot(bone)
            ag *= 1.0 - 0.8 * leg * (1.0 if distal else 0.0)
    if hooded:
        var d = _hood(t, p, n, bone, region)
        d += (fbm3(p * 1200.0, 2) - 0.5) * 0.0006
        c = mix3(c, pal.get("hood"), smoothstep(0.0004, -0.0004, d))
    var cv = fbm3(p * 90.0, 3) - 0.5
    c = V3(
        c.x * (1.0 + 0.16 * cv), c.y * (1.0 + 0.13 * cv), c.z * (1.0 + 0.1 * cv)
    )
    c = grizzle(c, p, 1400.0, 0.06 + 0.3 * clamp(ag, 0.0, 1.0))
    return Paint(c, FUR)
