# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The cheetah, Acinonyx jubatus: procedural-animals' `species/cheetah/`.

A slender, long-legged sprinter with a small head, a deep narrow chest
and a long tail. The reference adult stands 0.76 m at the shoulder. Its
coat is tawny with solid black spots, white underparts, black tear lines
from the eyes to the mouth and a ringed tail with a white tip. Males are
a little heavier, with slightly larger heads. Cubs are smaller, with
bigger heads and paws.
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
from extensions.animals.parts import JAW
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
from extensions.animals.warp import (
    length_warp,
    legs_warp,
    scale_about_warp,
)
from std.math import cos, floor, log, pi, pow, sin
from extensions.sdf.distance import almond_distance

comptime TAIL_SEGS = 10
# The head's origin, between the eyes and the ears.
comptime HEAD_O = V3(0.0, 0.79, 0.6)
# The finest cell, at the `HERO` tier: the head's cell in the original.
comptime CELL = 0.0025
comptime TAIL_BASE = V3(0.0, 0.655, -0.595)

# The palette's swatches, by index into `Palette.colors`.
comptime DORSAL = 0
comptime FLANK = 1
comptime LOW_FLANK = 2
comptime WHITE = 3
comptime CREAM = 4
comptime LEG_OUTER = 5
comptime FACE = 6
comptime MUZZLE = 7
comptime NOSE_LEATHER = 8
comptime BLACK = 9
comptime MOUTH = 10
comptime EAR_INNER = 11

# The spots' color.
comptime SPOT = V3(0.016, 0.0105, 0.0075)


def cheetah_variant_names() -> List[String]:
    """Return the cheetah's color morphs: the one spotted coat.

    Returns:
        Spotted.
    """
    return [String("spotted")]


def cheetah_traits(
    mut r: AnimalRandom, options: AnimalOptions
) raises -> Traits:
    """Draw one cheetah: procedural-animals' `variation`.

    Adults differ a little by sex: males are about 10 % heavier, with
    slightly larger heads. Cubs are smaller, with bigger heads and shorter
    legs.

    Args:
        r: The individual's stream.
        options: The caller's sex, age and morph.

    Returns:
        The traits.

    Raises:
        Error: If the requested morph is not the spotted coat.
    """
    var sex = pick_sex(options.sex, r)
    var age = pick_age(options.age)
    var weights: List[Float64] = [1.0]
    var variant = pick_variant(options.variant.value, weights, 0.0)
    var t = Traits(sex, age, variant)
    var juv = t.juvenile()
    var male = t.male()
    t.set(
        "size",
        (1.02 if male else 0.96)
        * (1.0 + 0.04 * r.g())
        * (0.62 if juv > 0.0 else 1.0),
    )
    t.warps.add(
        legs_warp(1.0 + 0.035 * r.g() - (0.06 if juv > 0.0 else 0.0), 0.5)
    )
    t.warps.add(length_warp(1.0 + 0.03 * r.g(), -0.45, 0.35))
    t.warps.add(
        scale_about_warp(
            HEAD_O,
            (1.03 if male else 0.98)
            * (1.0 + 0.025 * r.g())
            * (1.18 if juv > 0.0 else 1.0),
            0.07,
            0.16,
        )
    )
    t.set("coatWarmth", 0.6 * r.g())
    t.set("coatLightness", 0.05 * r.g())
    t.set("coatSeed", Float64(Int(r.next() * 1e6)))
    return t^


def cheetah_eye(t: Traits) -> EyeSpec:
    """Return the cheetah's left eye: a round pupil and an amber iris,
    hooded by the upper lid.

    Args:
        t: The individual. Every cheetah has the same eye.

    Returns:
        The eye, head-local.
    """
    _ = t.juvenile()
    return EyeSpec(
        V3(0.027, 0.026, 0.024),
        0.0122,
        0.0025,
        0.16,
        0.0,
        0.0014,
        0.014149,
        0.008899,
        -0.0013,
        12.0 * pi / 180.0,
        0.00727,
        0.0098,
    )


def cheetah_look(t: Traits) -> EyeLook:
    """Return the cheetah's eye colors: a deep amber iris.

    Args:
        t: The individual. Every cheetah has the same eyes.

    Returns:
        The look.
    """
    _ = t.juvenile()
    return EyeLook(
        V3(0.2, 0.06, 0.007),
        V3(0.54, 0.2, 0.022),
        V3(0.26, 0.075, 0.009),
        V3(0.2, 0.15, 0.11),
        0.38,
        0.0,
    )


def _tail_angles() -> List[Float64]:
    # A relaxed tail: it droops, then flicks up at the tip.
    return [-22.0, -38.0, -52.0, -60.0, -62.0, -58.0, -48.0, -32.0, -12.0, 10.0]


def _tail_lens() -> List[Float64]:
    return [0.07, 0.074, 0.075, 0.075, 0.074, 0.073, 0.071, 0.069, 0.067, 0.065]


def cheetah_rig(t: Traits) raises -> Rig:
    """Return the cheetah's skeleton in bind pose.

    Proportions come from cheetah limb osteometry: humerus 0.23 m, radius
    0.22 m, femur 0.26 m, tibia 0.255 m, metatarsus 0.13 m. The rig is the
    same for every individual: the warps make the proportions.

    Args:
        t: The individual.

    Returns:
        The rig.

    Raises:
        Error: If a bone names a missing joint.
    """
    _ = t.juvenile()
    var rig = Rig()
    rig.set("nose", V3(0, 0.772, 0.7))
    rig.set("occiput", V3(0, 0.79, 0.525))
    rig.set("neckMid", V3(0, 0.716, 0.45))
    rig.set("neckBase", V3(0, 0.63, 0.34))
    rig.set("chestMid", V3(0, 0.648, 0.16))
    rig.set("thoraxRear", V3(0, 0.668, -0.03))
    rig.set("lumbarMid", V3(0, 0.68, -0.225))
    rig.set("lumbosacral", V3(0, 0.668, -0.41))
    rig.set("tailBase", TAIL_BASE)
    rig.set("scapTopL", V3(0.045, 0.706, 0.286))
    rig.set("shoulderL", V3(0.08, 0.536, 0.386))
    rig.set("elbowL", V3(0.078, 0.346, 0.256))
    rig.set("wristL", V3(0.068, 0.126, 0.276))
    rig.set("mcpL", V3(0.066, 0.038, 0.306))
    rig.set("ftoeL", V3(0.066, 0.016, 0.353))
    rig.set("hipL", V3(0.072, 0.572, -0.46))
    rig.set("kneeL", V3(0.09, 0.34, -0.345))
    rig.set("hockL", V3(0.078, 0.172, -0.54))
    rig.set("mtpL", V3(0.074, 0.038, -0.51))
    rig.set("htoeL", V3(0.074, 0.016, -0.46))
    rig.set("jawHinge", V3(0, 0.755, 0.58))
    rig.set("jawTip", V3(0, 0.73, 0.66))
    rig.set("earBaseL", V3(0.052, 0.83, 0.552))
    rig.set("earTipL", V3(0.08, 0.853, 0.548))
    tail_chain(rig, "tailBase", _tail_angles(), _tail_lens())
    rig.mirror_joints()
    quadruped_bones(rig, TAIL_SEGS)
    return rig^


def _hl(x: Float64, y: Float64, z: Float64) -> V3:
    return V3(HEAD_O.x + x, HEAD_O.y + y, HEAD_O.z + z)


def _tail_radius(t: Float64) -> Float64:
    if t < 0.4:
        return 0.034 + (0.024 - 0.034) * (t / 0.4)
    if t < 0.8:
        return 0.024 + (0.021 - 0.024) * ((t - 0.4) / 0.4)
    return 0.021 - 0.002 * ((t - 0.8) / 0.2)


def cheetah_sculpt(mut m: SdfModel, rig: Rig, t: Traits) raises:
    """Sculpt the cheetah: procedural-animals' `sculptCheetah`, primitive
    for primitive.

    Args:
        m: The sculpt to add to.
        rig: The cheetah's rig in bind pose.
        t: The individual. Every cheetah has the same sculpt.

    Raises:
        Error: If the rig lacks a joint or a bone, or the sculpt refuses
            a primitive.
    """
    var eye = cheetah_eye(t)

    # TORSO
    _ = m.ell(
        "ribcage",
        rig.bone("spine3"),
        V3(0, 0.575, 0.13),
        V3(0.1, 0.18, 0.22),
        axis=normalize(V3(0, 0.15, -1)),
        k=0,
    )
    var b = rig.bone("chest")
    _ = m.ell(
        "brisket",
        b,
        V3(0, 0.478, 0.3),
        V3(0.075, 0.095, 0.1),
        axis=normalize(V3(0, -0.35, 1)),
        k=0.06,
    )
    _ = m.ell("pectoral", b, V3(0, 0.49, 0.35), V3(0.08, 0.08, 0.075), k=0.05)
    _ = m.ell(
        "withers",
        b,
        V3(0, 0.705, 0.24),
        V3(0.055, 0.058, 0.13),
        axis=normalize(V3(0, -0.08, 1)),
        k=0.06,
    )
    _ = m.ell(
        "back", rig.bone("spine3"), V3(0, 0.7, 0), V3(0.07, 0.05, 0.17), k=0.06
    )
    _ = m.ell(
        "abdomen",
        rig.bone("spine2"),
        V3(0, 0.628, -0.17),
        V3(0.076, 0.1, 0.2),
        axis=normalize(V3(0, 0.3, -1)),
        k=0.07,
    )
    b = rig.bone("spine1")
    _ = m.ell("loin", b, V3(0, 0.695, -0.24), V3(0.064, 0.055, 0.19), k=0.05)
    _ = m.ell("flank", b, V3(0, 0.605, -0.31), V3(0.068, 0.07, 0.1), k=0.05)
    b = rig.bone("pelvis")
    _ = m.ell("pelvis", b, V3(0, 0.665, -0.47), V3(0.078, 0.095, 0.135), k=0.06)
    _ = m.ell("croup", b, V3(0, 0.715, -0.46), V3(0.06, 0.045, 0.125), k=0.04)
    for s in [1.0, -1.0]:
        _ = m.ell(
            "rump",
            b,
            V3(0.045 * s, 0.625, -0.575),
            V3(0.044, 0.075, 0.055),
            k=0.04,
        )

    # NECK
    var n1 = rig.bone("neck1")
    var n2 = rig.bone("neck2")
    _ = m.cone(
        "neck", n1, V3(0, 0.61, 0.33), V3(0, 0.705, 0.455), 0.088, 0.064, k=0.06
    )
    _ = m.cone(
        "neck",
        n2,
        V3(0, 0.705, 0.455),
        V3(0, 0.772, 0.53),
        0.064,
        0.052,
        k=0.04,
    )
    _ = m.ell(
        "nape",
        n1,
        V3(0, 0.765, 0.43),
        V3(0.038, 0.028, 0.12),
        axis=normalize(V3(0, 0.35, 1)),
        k=0.04,
    )
    _ = m.ell(
        "throat",
        n1,
        V3(0, 0.655, 0.47),
        V3(0.046, 0.055, 0.09),
        axis=normalize(V3(0, 0.8, 0.6)),
        k=0.05,
    )
    _ = m.ell(
        "throat", n2, _hl(0, -0.054, -0.042), V3(0.035, 0.028, 0.062), k=0.03
    )

    # HEAD, head-local: a small round head with a short muzzle.
    var h = rig.bone("head")
    _ = m.ell(
        "cranium", h, _hl(0, 0.02, -0.03), V3(0.047, 0.046, 0.062), k=0.04
    )
    _ = m.ell(
        "forehead",
        h,
        _hl(0, 0.034, 0.018),
        V3(0.021, 0.03, 0.034),
        axis=normalize(V3(0, -0.6, 1)),
        k=0.02,
    )
    for s in [1.0, -1.0]:
        _ = m.ell(
            "brow",
            h,
            _hl(0.028 * s, 0.042, 0.022),
            V3(0.014, 0.007, 0.012),
            k=0.012,
        )
        _ = m.ell(
            "zygomatic",
            h,
            _hl(0.047 * s, 0.006, -0.002),
            V3(0.013, 0.02, 0.04),
            axis=normalize(V3(-0.35 * s, 0, 1)),
            k=0.025,
        )
        _ = m.ell(
            "cheek",
            h,
            _hl(0.035 * s, -0.027, 0.004),
            V3(0.021, 0.026, 0.036),
            k=0.025,
        )
        _ = m.ell(
            "lip",
            h,
            _hl(0.023 * s, -0.047, 0.05),
            V3(0.011, 0.009, 0.03),
            axis=normalize(V3(-0.45 * s, -0.15, 1)),
            k=0.012,
        )
        _ = m.ell(
            "mastoid",
            h,
            _hl(0.034 * s, -0.02, -0.05),
            V3(0.022, 0.03, 0.03),
            k=0.03,
        )
        _ = m.ell(
            "whisker",
            h,
            _hl(0.0135 * s, -0.037, 0.078),
            V3(0.0145, 0.0135, 0.016),
            k=0.012,
        )
    _ = m.ell(
        "muzzle",
        h,
        _hl(0, -0.022, 0.058),
        V3(0.024, 0.024, 0.032),
        axis=normalize(V3(0, -0.4, 1)),
        k=0.02,
    )
    _ = m.cone(
        "nasal",
        h,
        _hl(0, 0.036, 0.042),
        _hl(0, 0.002, 0.083),
        0.019,
        0.014,
        k=0.015,
    )
    _ = m.ell(
        "nose",
        h,
        _hl(0, -0.012, 0.091),
        V3(0.0142, 0.0086, 0.0082),
        axis=normalize(V3(0, 0.5, 1)),
        k=0.008,
    )
    _ = m.ell(
        "philtrum", h, _hl(0, -0.034, 0.088), V3(0.01, 0.011, 0.008), k=0.01
    )
    for s in [1.0, -1.0]:
        # The lids: a thin shell hugging the eyeball, cut open along an
        # almond aperture, in a soft orbit hollow.
        var ef = eye_frame_of(eye, HEAD_O, s)
        _ = ell_y(
            m,
            "orbit",
            h,
            ef.at(-0.002 * s, -0.0005, 0.019),
            ef.y,
            V3(0.018, 0.0125, 0.009),
            lateral=ef.x,
            k=0.008,
            carve=True,
        )
        _ = m.sphere("eyelid", h, ef.c, eye.r + eye.lid, k=0.005)
        _ = m.lens(
            "eyesocket",
            h,
            ef.c + ef.y * eye.off,
            ef.x,
            ef.y,
            ef.z,
            eye.big_r,
            eye.d,
            -0.002,
            0.024,
            k=0.0022,
            carve=True,
        )
        _ = m.sphere(
            "nostril",
            h,
            _hl(0.0065 * s, -0.015, 0.1),
            0.003,
            k=0.002,
            carve=True,
        )

    # JAW: its own surface, so the mouth can open.
    var jw = rig.bone("jaw")
    _ = m.cone(
        "mandible",
        jw,
        _hl(0, -0.045, -0.012),
        _hl(0, -0.052, 0.044),
        0.018,
        0.012,
        k=0,
        part=JAW,
    )
    for s in [1.0, -1.0]:
        _ = m.cone(
            "mandible",
            jw,
            _hl(0.032 * s, -0.039, -0.028),
            _hl(0.01 * s, -0.051, 0.048),
            0.014,
            0.01,
            k=0.02,
            part=JAW,
        )
    _ = m.ell(
        "chin",
        jw,
        _hl(0, -0.053, 0.05),
        V3(0.015, 0.011, 0.011),
        k=0.015,
        part=JAW,
    )

    # EARS: small and round, set low and wide.
    for side in [String("L"), String("R")]:
        var s = 1.0 if side == "L" else -1.0
        var base = rig.j("earBase" + side)
        var tip = rig.j("earTip" + side)
        var up = normalize(tip - base)
        var facing = normalize(V3(1.0 * s, 0.1, 1))
        var c = lerp(base, tip, 0.3)
        var lat = normalize(cross(up, facing))
        var eb = rig.bone("ear" + side)
        _ = ell_y(
            m,
            "ear",
            eb,
            c,
            up,
            V3(0.0165, 0.0185, 0.0062),
            lateral=lat,
            k=0.012,
        )
        _ = ell_y(
            m,
            "earinner",
            eb,
            c + facing * 0.0068 + up * 0.003,
            up,
            V3(0.0112, 0.0132, 0.0044),
            lateral=lat,
            k=0.003,
            carve=True,
        )

    _sculpt_legs(m, rig)

    # TAIL: long, tapering a little.
    _ = m.cone(
        "tailroot",
        rig.bone("tail0"),
        V3(0, 0.672, -0.545),
        rig.j("tail1"),
        0.05,
        _tail_radius(0.1),
        k=0.04,
    )
    for i in range(TAIL_SEGS):
        _ = m.cone(
            "tail",
            rig.bone("tail" + String(i)),
            rig.j("tail" + String(i)),
            rig.j("tail" + String(i + 1)),
            _tail_radius(Float64(i) / Float64(TAIL_SEGS)),
            _tail_radius(Float64(i + 1) / Float64(TAIL_SEGS)),
            k=0,
        )


def _sculpt_legs(mut m: SdfModel, rig: Rig) raises:
    # Long, lean legs; the thigh a broad teardrop rising into the flank,
    # webbed to the belly by the flank fold.
    var toe_x: List[Float64] = [-0.019, -0.0065, 0.0065, 0.019]
    var toe_z: List[Float64] = [-0.009, 0, 0, -0.009]
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
            "scapmuscle",
            scap,
            lerp(sc, sh, 0.5) + on_side(V3(0.006, 0, 0), s),
            sh - sc,
            V3(0.022, 0.1, 0.055),
            lateral=lat,
            k=0.06,
        )
        _ = m.cone("upperarm", hum, sh, e, 0.037, 0.031, k=0.06)
        _ = ell_y(
            m,
            "triceps",
            hum,
            lerp(sh, e, 0.55) + V3(0, 0, -0.03),
            e - sh,
            V3(0.03, 0.075, 0.036),
            lateral=lat,
            k=0.05,
        )
        _ = m.sphere("olecranon", rad, e + V3(0, 0.01, -0.028), 0.019, k=0.02)
        _ = m.cone("forearm", rad, e, w, 0.032, 0.019, k=0.025)
        _ = ell_y(
            m,
            "forearmmuscle",
            rad,
            lerp(e, w, 0.25) + on_side(V3(0.004, 0, 0.004), s),
            w - e,
            V3(0.03, 0.07, 0.034),
            lateral=lat,
            k=0.03,
        )
        _ = m.sphere("wrist", meta, w + V3(0, 0, -0.004), 0.0195, k=0.012)
        _ = m.sphere("carpalpad", meta, w + V3(0, -0.01, -0.02), 0.009, k=0.01)
        _ = m.cone("pastern", meta, w, mc, 0.018, 0.017, k=0.012)
        _ = m.sphere(
            "dewclaw",
            meta,
            lerp(w, mc, 0.35) + on_side(V3(-0.016, 0, 0.004), s),
            0.007,
            k=0.006,
        )
        var dp = normalize(toe - mc)
        _ = ell_y(
            m,
            "paw",
            fpaw,
            mc + dp * 0.02 + V3(0, -0.006, 0),
            dp,
            V3(0.026, 0.036, 0.018),
            lateral=lat,
            k=0.014,
        )
        _ = m.sphere("pad", fpaw, mc + V3(0, -0.026, 0.012), 0.012, k=0.01)
        for i in range(4):
            _ = m.sphere(
                "toe",
                fpaw,
                V3(toe.x + toe_x[i] * s, 0.0115, toe.z - 0.008 + toe_z[i]),
                0.0105,
                k=0.007,
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
            lerp(hp, kn, 0.4) + on_side(V3(0.004, 0, -0.035), s),
            kn - hp,
            V3(0.041, 0.15, 0.1),
            lateral=lat,
            k=0.05,
        )
        _ = m.cone(
            "thighfront",
            fem,
            on_side(V3(0.04, 0.625, -0.33), s),
            kn + on_side(V3(-0.004, 0.055, 0), s),
            0.04,
            0.025,
            k=0.06,
        )
        _ = m.cone(
            "hamstring",
            fem,
            on_side(V3(0.046, 0.625, -0.595), s),
            lerp(kn, hk, 0.28) + V3(0, 0, -0.028),
            0.045,
            0.028,
            k=0.04,
        )
        _ = ell_y(
            m,
            "flankfold",
            fem,
            on_side(V3(0.05, 0.475, -0.29), s),
            V3(-0.03, 0.16, 0.1),
            V3(0.02, 0.085, 0.04),
            lateral=lat,
            k=0.06,
        )
        _ = m.sphere(
            "stifle",
            tib,
            kn + on_side(V3(0.002, 0.008, 0.006), s),
            0.0175,
            k=0.04,
        )
        _ = m.cone(
            "shin",
            tib,
            lerp(kn, hk, 0.06) + on_side(V3(0, 0, 0.004), s),
            hk,
            0.024,
            0.018,
            k=0.03,
        )
        _ = ell_y(
            m,
            "calf",
            tib,
            lerp(kn, hk, 0.3) + on_side(V3(0.002, 0.01, -0.027), s),
            hk - kn,
            V3(0.025, 0.065, 0.029),
            lateral=lat,
            k=0.035,
        )
        _ = m.cone(
            "achilles",
            tib,
            lerp(kn, hk, 0.5) + V3(0, 0.01, -0.035),
            hk + V3(0, 0.012, -0.03),
            0.012,
            0.011,
            k=0.015,
        )
        _ = m.sphere(
            "calcaneus", mtar, hk + V3(0, 0.012, -0.026), 0.015, k=0.012
        )
        _ = m.sphere("hock", mtar, hk, 0.021, k=0.012)
        _ = m.cone("metatarsus", mtar, hk, mt, 0.018, 0.016, k=0.012)
        var dh = normalize(tt - mt)
        _ = ell_y(
            m,
            "paw",
            hpaw,
            mt + dh * 0.02 + V3(0, -0.006, 0),
            dh,
            V3(0.024, 0.034, 0.017),
            lateral=lat,
            k=0.014,
        )
        _ = m.sphere("pad", hpaw, mt + V3(0, -0.026, 0.01), 0.011, k=0.01)
        for i in range(4):
            _ = m.sphere(
                "toe",
                hpaw,
                V3(tt.x + toe_x[i] * 0.95 * s, 0.011, tt.z - 0.008 + toe_z[i]),
                0.0098,
                k=0.007,
            )


# ---------------------------------------------------------------- COAT


def _swatches() -> List[String]:
    return [
        String("dorsal"),
        "flank",
        "lowFlank",
        "white",
        "cream",
        "legOuter",
        "face",
        "muzzle",
        "nose",
        "black",
        "mouth",
        "earInner",
    ]


def cheetah_palette(t: Traits) raises -> Palette:
    """Return one cheetah's palette: the tawny coat, warmed and lightened.

    The white underparts, the muzzle, the nose, the black and the mouth
    keep their colors.

    Args:
        t: The individual.

    Returns:
        The palette, in linear light.

    Raises:
        Error: If the palette tables differ in length.
    """
    var names = _swatches()
    var hexes: List[Int] = [
        0xAE8558,
        0xC29D72,
        0xD2B690,
        0xEBE5D9,
        0xDCCBAE,
        0xC6A479,
        0xC19668,
        0xEFE9DF,
        0x2C2624,
        0x15110F,
        0x7A3A3A,
        0xCBB699,
    ]
    if len(names) != len(hexes):
        raise Error("The cheetah's palette tables differ in length")
    var k = t.get("coatWarmth", 0.0)
    var l = t.get("coatLightness", 0.0)
    var pal = Palette()
    for i in range(len(names)):
        var c = srgb(hexes[i])
        var tawny = (
            i == DORSAL
            or i == FLANK
            or i == LOW_FLANK
            or i == LEG_OUTER
            or i == FACE
        )
        if tawny:
            c = V3(
                c.x * (1.0 + 0.1 * k + l),
                c.y * (1.0 + 0.02 * k + l),
                c.z * (1.0 - 0.12 * k + l),
            )
        pal.set(names[i], c)
    return pal^


def _tear_points() -> List[V3]:
    # The tear line, head-local: from the inner eye corner to the mouth.
    return [
        V3(0.018, 0.0219, 0.0335),
        V3(0.0191, 0.0111, 0.0357),
        V3(0.0222, 0.0011, 0.0395),
        V3(0.0262, -0.0086, 0.0426),
        V3(0.0285, -0.0198, 0.0441),
        V3(0.0305, -0.028, 0.043),
        V3(0.0335, -0.0355, 0.0425),
        V3(0.0355, -0.0435, 0.0415),
    ]


def _tear_widths() -> List[Float64]:
    return [0.0022, 0.0031, 0.0037, 0.0041, 0.0043, 0.0043, 0.004, 0.0034]


def _tear_distance(h: V3) -> Float64:
    # The distance from a head-local point to the left or right tear line
    # across the face, less the line's half width there. The line lies on
    # the skin, so a point well in front of it or behind it is far.
    var pts = _tear_points()
    var widths = _tear_widths()
    var q = V3(abs(h.x), h.y, 0.0)
    var best = 1e9
    for i in range(len(pts) - 1):
        var a = V3(pts[i].x, pts[i].y, 0.0)
        var b = V3(pts[i + 1].x, pts[i + 1].y, 0.0)
        var ab = b - a
        var u = clamp(dot(q - a, ab) / dot(ab, ab), 0.0, 1.0)
        var depth = abs(h.z - mix(pts[i].z, pts[i + 1].z, u))
        var d = (
            length(q - (a + ab * u))
            - mix(widths[i], widths[i + 1], u)
            + 0.5 * max(0.0, depth - 0.012)
        )
        best = min(best, d)
    return best


def _tail_along(p: V3) -> Tuple[Float64, Float64]:
    # How far along the tail a point lies, in meters from its root, and
    # the tail's whole length.
    var angles = _tail_angles()
    var lens = _tail_lens()
    var a = TAIL_BASE
    var run = 0.0
    var best = 1e9
    var at = 0.0
    for i in range(TAIL_SEGS):
        var ang = angles[i] * pi / 180.0
        var d = V3(0, sin(ang), -cos(ang))
        var u = clamp(dot(p - a, d) / lens[i], 0.0, 1.0)
        var gap = length(p - (a + d * (u * lens[i])))
        var closer = gap < best
        best = gap if closer else best
        at = run + u * lens[i] if closer else at
        run += lens[i]
        a = a + d * lens[i]
    return (at, run)


def _spot_layer(
    p: V3, radius: Float64, seed: Int, wob: Float64, keep: Float64
) -> Float64:
    # One layer of solid round spots from cell noise, a fixed radius. Each
    # spot is kept by a draw of its own against `keep`, so a layer thins
    # out spot by spot rather than fading.
    var cell = 2.7 * radius
    var c = cells3(p * (1.0 / cell), seed)
    var draw = c.id * 7.31 - floor(c.id * 7.31)
    if draw >= keep:
        return 0.0
    var r = (0.78 + 0.44 * c.id) * wob / 2.7 * 1.1
    # A thin gap where two spots meet keeps them apart.
    var apart = smoothstep(0.04, 0.12, c.second - c.nearest)
    return smoothstep(r + 0.04, r - 0.04, c.nearest) * apart


def _spot(p: V3, radius: Float64, seed: Int, wob: Float64) -> Float64:
    # Solid round spots whose size follows `radius`: one inside a spot,
    # zero outside. The size steps through fixed layers, each 1.4 times
    # the last; between two layers the smaller one's spots give way to the
    # bigger one's, so a size that changes over the body does not shear
    # the pattern.
    var level = log(radius / 0.0035) / log(1.4)
    var l0 = floor(level)
    var f = level - l0
    var r0 = 0.0035 * pow(1.4, l0)
    var s0 = Int(l0) * 7 + seed
    var a = _spot_layer(p, r0, s0, wob, 1.0 - f)
    var b = _spot_layer(p, r0 * 1.4, s0 + 7, wob, f)
    return max(a, b)


def cheetah_paint(
    pal: Palette, t: Traits, tag: String, bone: String, s: CoatSample
) -> Paint:
    """Paint one vertex of a cheetah.

    The cheetah's coat: tawny above, paler on the lower flanks and white
    beneath, all covered in solid black spots that shrink on the neck,
    the face and the lower legs and fade on the belly; black tear lines
    from the inner eye corners to the mouth; a white muzzle, chin and
    throat; black lid margins and lip line; black ear backs; and a tail
    whose spots join into black rings toward its white tip.

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
    var seed = Int(t.get("coatSeed", 0.0))
    if tag == "pad" or tag == "carpalpad":
        return Paint(c[BLACK] * 2.0, SKIN)
    var h = p - HEAD_O
    var col: V3
    var mark = 1.0
    var radius = 0.0
    var ventral = 0.0
    if bone == "head" or bone == "jaw":
        var face = _paint_face(c, tag, bone, p, n)
        if face.surface != FUR:
            return face
        col = face.color
        mark = _face_mark(p, n, bone == "jaw")
        var spotless = (h.z > 0.03 and abs(h.x) < 0.02) or (
            h.y < -0.012 and h.z > 0.02
        )
        var front = h.z > 0.05
        var plain = spotless or front or bone == "jaw"
        radius = 0.0 if plain else mix(
            0.0045, 0.006, smoothstep(0.04, -0.06, h.z)
        )
    elif bone.startswith("ear"):
        # A pale front, a black back toward the base and a tawny tip.
        var sd = 1.0 if p.x > 0.0 else -1.0
        var base = V3(0.052 * sd, 0.83, 0.552)
        var tip = V3(0.08 * sd, 0.853, 0.548)
        var up = normalize(tip - base)
        var facing = normalize(V3(1.0 * sd, 0.1, 1))
        var front = dot(n, facing)
        var ht = dot(p - lerp(base, tip, 0.3), up) / 0.02
        col = mix3(c[FACE], c[EAR_INNER], smoothstep(0.35, 0.8, front))
        var back = (ht - 0.25) * 0.01 + (front + 0.6) * 0.01
        mark = back if front <= 0.35 else 1.0
    elif bone.startswith("tail"):
        var along = _tail_along(p)
        var tt = along[0] / along[1]
        ventral = smoothstep(0.0, -0.7, n.y) * 0.8
        col = mix3(c[FLANK], c[WHITE], ventral)
        col = mix3(col, c[WHITE], smoothstep(0.55, 0.9, tt) * 0.55)
        var rings: List[Float64] = [0.61, 0.685, 0.755, 0.82, 0.88, 0.935]
        var rs = 1.0
        for k in range(len(rings)):
            var hw = 0.012 + 0.003 * (Float64(k) / Float64(len(rings)))
            rs = min(rs, abs(along[0] - rings[k] * along[1]) - hw)
        rs += 0.006 * ventral
        var tip = tt > 0.965
        mark = 1.0 if tip else rs
        if tip:
            col = c[WHITE]
        radius = 0.0104 if tt <= 0.58 else 0.0
    else:
        var body = _paint_body(c, bone, p, n)
        col = body[0]
        ventral = body[1]
        radius = body[2]
    var cv = fbm3(p * 9.0, 3) - 0.5
    var cvh = fbm3(V3(p.x * 4.0 + 5.0, p.y * 4.0, p.z * 4.0), 2) - 0.5
    col = V3(
        col.x * (1.0 + 0.16 * cv + 0.1 * cvh),
        col.y * (1.0 + 0.14 * cv),
        col.z * (1.0 + 0.1 * cv - 0.08 * cvh),
    )
    if radius > 0.0:
        var wob = 1.0 + 0.22 * (vnoise3(p * 180.0) - 0.5)
        var spot = _spot(p, radius, seed % 4093, wob)
        var pale = (
            smoothstep(0.45, 0.95, ventral)
            * smoothstep(0.2, 0.06, p.z)
            * (0.0 if is_limb(bone) else 1.0)
        )
        col = mix3(col, SPOT, spot * (1.0 - 0.55 * pale))
    return Paint(mix3(col, SPOT, smoothstep(0.0008, -0.0006, mark)), FUR)


def _paint_body(
    c: List[V3], bone: String, p: V3, n: V3
) -> Tuple[V3, Float64, Float64]:
    # The torso, the neck and the legs: their color, how ventral they
    # are, and their spots' radius.
    var neck = bone == "neck1" or bone == "neck2"
    var limb = is_limb(bone)
    var legness = smoothstep(0.55, 0.38, p.y) if limb else 0.0
    var up = clamp(n.y, -1.0, 1.0)
    var w: Float64
    if neck:
        w = smoothstep(0.15, -0.55, up)
    else:
        w = smoothstep(-0.15, -0.7, up)
        var chest = (
            smoothstep(0.58, 0.46, p.y)
            * smoothstep(0.075, 0.03, abs(p.x))
            * smoothstep(-0.2, 0.4, n.z)
        )
        var front = p.z > 0.22 and p.y < 0.58
        w = max(w, chest if front else 0.0)
        w *= smoothstep(0.6, 0.5, p.y) * 0.6 + 0.4
    if legness > 0.0:
        var side = 1.0 if p.x >= 0.0 else -1.0
        var inner = smoothstep(0.0, -0.7, n.x * side)
        var wl = (
            inner * 0.45 * smoothstep(0.15, 0.45, p.y)
            + smoothstep(-0.3, -0.85, up) * 0.45
        )
        w = w + (wl - w) * legness
    w = clamp(w, 0.0, 1.0)
    var col = mix3(c[LOW_FLANK], c[FLANK], smoothstep(-0.2, 0.4, up))
    col = mix3(col, c[DORSAL], smoothstep(0.55, 0.95, up) * 0.85)
    col = mix3(col, c[WHITE], w)
    if legness > 0.0:
        var lc = mix3(c[LEG_OUTER], c[CREAM], w * 0.8)
        lc = mix3(lc, c[DORSAL], smoothstep(0.6, 1.0, n.y) * 0.3)
        var paw = bone.startswith("fpaw") or bone.startswith("hpaw")
        if paw:
            lc = mix3(lc, c[CREAM], 0.3)
        col = mix3(col, lc, legness)
    # The spots: big on the torso, smaller and paler beneath, small on
    # the neck and smaller down the legs.
    var on_torso = smoothstep(0.3, 0.45, p.z) if neck else 1.0
    on_torso = 1.0 - on_torso if neck else 1.0
    var axial = mix(0.007, 0.0111 * mix(1.0, 0.74, w), on_torso)
    var leg_h = clamp(p.y / 0.55, 0.0, 1.0)
    var lg = mix(0.0035, 0.0099, smoothstep(0.05, 0.55, leg_h))
    var paw_bone = bone.startswith("fpaw") or bone.startswith("hpaw")
    var radius = 0.0 if paw_bone else mix(axial, lg, legness)
    return (col, w, radius)


def _paint_face(c: List[V3], tag: String, bone: String, p: V3, n: V3) -> Paint:
    # The head: tawny, a white muzzle, chin and throat, pale patches
    # under and over the eyes, the nose leather and the mouth.
    var h = p - HEAD_O
    var jaw = bone == "jaw"
    if tag == "nose":
        var leather = h.z > 0.085
        if leather:
            return Paint(c[NOSE_LEATHER], NOSE)
    var whisker = (
        mirrored_blob(h, V3(0.015, -0.035, 0.08), V3(0.02, 0.016, 0.024)) * 0.5
    )
    var moustache = mirrored_blob(
        h, V3(0.017, -0.047, 0.07), V3(0.024, 0.0085, 0.034)
    )
    var lip = mirrored_blob(h, V3(0.0, -0.042, 0.088), V3(0.014, 0.01, 0.016))
    var under_eye = (
        mirrored_blob(h, V3(0.031, 0.009, 0.033), V3(0.011, 0.0075, 0.016))
        * 0.8
    )
    var above_eye = (
        mirrored_blob(h, V3(0.03, 0.044, 0.025), V3(0.012, 0.006, 0.015)) * 0.45
    )
    var chin_w = (
        smoothstep(-0.02, 0.03, h.z) * 0.9 + smoothstep(-0.2, -0.7, n.y) * 0.6
    ) if jaw else 0.0
    var throat_w = (
        smoothstep(-0.045, -0.065, h.y) * smoothstep(-0.3, -0.8, n.y) * 0.9
    )
    var w = clamp(
        max(
            max(max(whisker, moustache), max(lip, under_eye)),
            max(above_eye, max(chin_w, throat_w)),
        ),
        0.0,
        1.0,
    )
    var col = mix3(c[FACE], c[MUZZLE], w)
    # The mouth: the jaw's top and the upper lip's underside.
    if jaw:
        var inside = n.y > 0.45 and h.z < 0.045
        if inside:
            return Paint(c[MOUTH], SKIN)
    if not jaw:
        col = mix3(
            col,
            c[DORSAL],
            smoothstep(-0.04, -0.09, h.z) * smoothstep(0.0, 0.6, n.y) * 0.6,
        )
    return Paint(col, FUR)


def _face_mark(p: V3, n: V3, jaw: Bool) -> Float64:
    # The face's black marks: the tear lines, the lid margins and the lip
    # line. Below zero is black.
    var h = p - HEAD_O
    var mark = 1.0
    var front = h.z > 0.02 and n.z > -0.2
    if front:
        mark = min(mark, _tear_distance(h))
    var e = EyeSpec(
        V3(0.027, 0.026, 0.024),
        0.0122,
        0.0025,
        0.16,
        0.0,
        0.0014,
        0.014149,
        0.008899,
        -0.0013,
        12.0 * pi / 180.0,
        0.00727,
        0.0098,
    )
    var sd = 1.0 if p.x > HEAD_O.x else -1.0
    var ef = eye_frame_of(e, HEAD_O, sd)
    var q = aperture_local(e, ef, p)
    var de = abs(almond_distance(q.x, q.y, e.big_r, e.d))
    var near = de < 0.004 and q.z > -0.4 * e.r
    if near:
        mark = min(mark, de - 0.0021)
    # The lip line where the upper lip meets the jaw.
    var line: Float64
    if jaw:
        line = smoothstep(0.2, 0.5, n.y) * smoothstep(-0.05, -0.045, h.y)
    else:
        line = (
            smoothstep(-0.052, -0.047, h.y)
            * (1.0 - smoothstep(-0.043, -0.039, h.y))
            * smoothstep(-0.1, -0.4, n.y)
        )
    line *= smoothstep(0.0, 0.02, h.z)
    mark = min(mark, 0.004 - 0.008 * line)
    return mark
