# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The brown bear, Ursus arctos: procedural-animals' `species/bear/`.

A plantigrade, heavy-bodied omnivore with a shoulder hump, a dished
face, small round ears and long fore claws. The reference adult stands
1.0 m at the hump. Its silhouette is mostly coat over fat and muscle, so
the barrel, the hump and the heavy "trousers" are sculpted as volume.
Morphs are Eurasian (45 %), grizzly (30 %) and coastal (25 %), and, on
request only, the American black bear. Each morph draws a coat color.
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
from extensions.sdf.ids import BoneId
from extensions.animals.parts import JAW
from extensions.sdf.sculpt import ell_y
from extensions.animals.kit import (
    EyeSpec,
    eye_frame_of,
    head_local,
    is_limb,
    mirrored_blob,
    aperture_local,
)
from extensions.animals.noise import fbm3, vnoise3
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
from extensions.sdf.distance import almond_distance

comptime TAIL_SEGS = 2
# The head's origin, mid cranium between the eyes and the ears.
comptime HEAD_O = V3(0.0, 0.78, 0.72)
# Where the muzzle starts, head-local. Muzzle length acts ahead of it.
comptime MUZZLE_Z0 = 0.06
# The finest cell, at the `HERO` tier: the head's cell in the original.
comptime CELL = 0.0036
# How far the toe joints sit ahead of the toe pads, at the claw tips.
comptime TOE_F = 0.05
comptime TOE_H = 0.035

# The morphs, in procedural-animals' order.
comptime EURASIAN = 0
comptime GRIZZLY = 1
comptime COASTAL = 2
comptime BLACK = 3

# The coat colors.
comptime DARK = 0
comptime RED = 1
comptime MEDIUM = 2
comptime BLONDE = 3
comptime GRIZZLED = 4
comptime BLACK_COAT = 5

# The palette's swatches, by index into `Palette.colors`.
comptime BACK = 0
comptime FLANK = 1
comptime TIP = 2
comptime HEAD = 3
comptime FACE = 4
comptime MUZZLE = 5
comptime LEG = 6
comptime BELLY = 7
comptime EAR = 8
comptime EAR_RIM = 9
comptime EAR_INNER = 10
comptime CLAW = 11
comptime CLAW_BASE = 12
comptime CLAW_TIP = 13


def bear_variant_names() -> List[String]:
    """Return the bear's morphs.

    Returns:
        Eurasian, grizzly, coastal and black. A random bear is never a
        black bear: it is built only when asked for.
    """
    return [String("eurasian"), "grizzly", "coastal", "black"]


def _pick(weights: List[Float64], draw: Float64) -> Int:
    # The original's `pick`: a draw past the last share is the last entry.
    var x = draw
    for i in range(len(weights)):
        if x < weights[i]:
            return i
        x -= weights[i]
    return len(weights) - 1


def _coat_of(variant: Int, draw: Float64) -> Int:
    # Each morph's coat colors and their shares.
    if variant == GRIZZLY:
        var w: List[Float64] = [0.7, 0.2, 0.1]
        var coats: List[Int] = [GRIZZLED, BLONDE, MEDIUM]
        return coats[_pick(w, draw)]
    if variant == COASTAL:
        var w: List[Float64] = [0.5, 0.3, 0.2]
        var coats: List[Int] = [MEDIUM, BLONDE, DARK]
        return coats[_pick(w, draw)]
    if variant == BLACK:
        return BLACK_COAT
    var w: List[Float64] = [0.55, 0.25, 0.2]
    var coats: List[Int] = [DARK, RED, MEDIUM]
    return coats[_pick(w, draw)]


def _by_variant(
    variant: Int,
    eurasian: Float64,
    grizzly: Float64,
    coastal: Float64,
    black: Float64,
) -> Float64:
    if variant == GRIZZLY:
        return grizzly
    if variant == COASTAL:
        return coastal
    return black if variant == BLACK else eurasian


def bear_traits(mut r: AnimalRandom, options: AnimalOptions) raises -> Traits:
    """Draw one bear: procedural-animals' `variation`.

    Males are much larger, with broader heads, thicker necks and a bigger
    hump. Cubs are 0.45 of the size, with a big domed head, a short
    muzzle, large ears and short legs; a Eurasian cub often wears a pale
    neck collar.

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
    if options.variant.value >= 4:
        raise Error("The bear has no such color variant")
    var xv = r.next()
    var weights: List[Float64] = [0.45, 0.3, 0.25]
    var variant = (
        options.variant.value if options.variant.value
        >= 0 else _pick(weights, xv)
    )
    var coat = _coat_of(variant, r.next())
    var t = Traits(sex, age, variant)
    var juv = t.juvenile()
    var male = t.male()
    var black = 1.0 if variant == BLACK else 0.0
    var v_size = _by_variant(variant, 1.0, 1.02, 1.11, 0.84)
    var size = (
        (1.08 if male else 0.93)
        * v_size
        * (1.0 + 0.04 * r.g())
        * (0.45 if juv > 0.0 else 1.0)
    )
    var legs = 1.0 + 0.03 * r.g() - 0.08 * juv + 0.04 * black
    var head = 1.1 * (1.03 if male else 0.98) * (1.0 + 0.025 * r.g())
    var hump = max(
        0.0,
        _by_variant(variant, 0.9, 1.25, 1.05, 0.0)
        * (1.12 if male else 0.92)
        * (1.0 + 0.15 * r.g())
        * (0.3 if juv > 0.0 else 1.0),
    )
    t.set("size", size)
    t.set("coat", Float64(coat))
    t.set(
        "muzzle",
        (1.0 + 0.04 * r.g())
        * (0.66 if juv > 0.0 else 1.0)
        * (1.04 if black > 0.0 else 1.0),
    )
    t.set(
        "headW",
        1.1
        * (1.07 if male else 0.96)
        * (1.0 + 0.025 * r.g())
        * (1.02 if juv > 0.0 else 1.0)
        * (0.9 if black > 0.0 else 1.0),
    )
    t.set(
        "ear",
        (1.0 + 0.08 * r.g())
        * (1.3 if juv > 0.0 else 1.0)
        * (1.3 if black > 0.0 else 1.0)
        * (0.95 if variant == GRIZZLY else 1.0),
    )
    var dish = _by_variant(variant, 1.0, 1.1, 0.9, 0.15) + 0.12 * r.g()
    t.set(
        "dish",
        max(0.0, min(1.3, dish)) * (0.5 if juv > 0.0 else 1.0),
    )
    t.set("hump", hump)
    t.set(
        "girth",
        (1.04 if male else 0.98)
        * (1.0 + 0.035 * r.g())
        * (0.96 if juv > 0.0 else 1.0)
        * (0.9 if black > 0.0 else 1.0),
    )
    t.set(
        "claw",
        _by_variant(variant, 1.0, 1.15, 1.0, 0.65)
        * (1.0 + 0.1 * r.g())
        * (0.7 if juv > 0.0 else 1.0),
    )
    t.set("tail", 1.0 + 0.1 * r.g())
    t.set("shag", max(0.65, (1.0 + 0.18 * r.g()) * (0.9 if juv > 0.0 else 1.0)))
    var bleach = 0.0
    if black == 0.0:
        bleach = max(0.0, 0.35 + 0.5 * r.g())
    t.set("bleach", bleach)
    var collar = 0.0
    var cub_collar = juv > 0.0 and variant == EURASIAN
    if cub_collar:
        if r.next() < 0.7:
            collar = 0.6 + 0.4 * r.next()
    t.set("collar", collar)
    t.set("coatWarmth", 0.5 * r.g())
    t.set("coatLightness", 0.1 * r.g())
    t.set("coatSeed", Float64(Int(r.next() * 1e6)))
    t.set("minThick", 0.005)
    t.warps.add(legs_warp(legs, 0.5))
    t.warps.add(length_warp(1.0 + 0.03 * r.g() - 0.06 * juv, -0.35, 0.33))
    t.warps.add(
        scale_about_warp(HEAD_O, head * (1.38 if juv > 0.0 else 1.0), 0.13, 0.3)
    )
    return t^


def bear_eye(t: Traits) -> EyeSpec:
    """Return the bear's left eye: small, set forward, with a round pupil.

    Args:
        t: The individual. The eye moves with the head's width.

    Returns:
        The eye, head-local.
    """
    return EyeSpec(
        V3(0.045 * t.get("headW"), 0.03, 0.0698),
        0.014,
        0.003,
        0.36,
        0.06,
        0.0018,
        0.0116,
        0.0049,
        -0.0014,
        10.0 * pi / 180.0,
        0.0086,
        0.0108,
    )


def bear_look(t: Traits) -> EyeLook:
    """Return the bear's eye colors: a dull, dark warm brown.

    Args:
        t: The individual. Every bear has the same eyes.

    Returns:
        The look.
    """
    _ = t.juvenile()
    return EyeLook(
        V3(0.02, 0.012, 0.007),
        V3(0.032, 0.019, 0.011),
        V3(0.012, 0.0075, 0.0045),
        V3(0.06, 0.042, 0.03),
        0.35,
        0.0,
    )


def _hl(t: Traits, v: V3) -> V3:
    # Head-local to reference space, with the muzzle and the head width.
    return head_local(
        HEAD_O, 1.0, MUZZLE_Z0, t.get("muzzle"), t.get("headW"), v
    )


def _hl_rig(t: Traits, v: V3) -> V3:
    return head_local(HEAD_O, 1.0, MUZZLE_Z0, t.get("muzzle"), 1.0, v)


def _ear_joints(t: Traits) -> Tuple[V3, V3]:
    # The left ear's base and tip, on the top corners of the head.
    var ek = t.get("ear")
    var hw = t.get("headW")
    return (
        _hl_rig(t, V3(0.122 * hw, 0.082, -0.05)),
        _hl_rig(
            t,
            V3(0.122 * hw + 0.03 * ek, 0.082 + 0.062 * ek, -0.05 - 0.012 * ek),
        ),
    )


def bear_rig(t: Traits) raises -> Rig:
    """Return the bear's skeleton in bind pose.

    Graviportal, plantigrade limbs: the forelegs stand as near-vertical
    columns under the hump with the palm flat on the ground, the hind
    legs straight-ish with the heel close to the ground. The stubby tail
    hangs down over the rump.

    Args:
        t: The individual.

    Returns:
        The rig.

    Raises:
        Error: If a bone names a missing joint.
    """
    var rig = Rig()
    rig.set("nose", _hl_rig(t, V3(0, -0.012, 0.215)))
    rig.set("occiput", _hl_rig(t, V3(0, 0.025, -0.125)))
    rig.set("neckMid", V3(0, 0.79, 0.49))
    rig.set("neckBase", V3(0, 0.81, 0.35))
    rig.set("chestMid", V3(0, 0.845, 0.14))
    rig.set("thoraxRear", V3(0, 0.835, -0.04))
    rig.set("lumbarMid", V3(0, 0.825, -0.2))
    rig.set("lumbosacral", V3(0, 0.815, -0.34))
    rig.set("tailBase", V3(0, 0.78, -0.48))
    rig.set("scapTopL", V3(0.075, 0.9, 0.2))
    rig.set("shoulderL", V3(0.152, 0.635, 0.38))
    rig.set("elbowL", V3(0.167, 0.38, 0.205))
    rig.set("wristL", V3(0.157, 0.078, 0.275))
    rig.set("mcpL", V3(0.157, 0.034, 0.395))
    rig.set("ftoeL", V3(0.157, 0.012, 0.515))
    rig.set("hipL", V3(0.115, 0.77, -0.32))
    rig.set("kneeL", V3(0.175, 0.4, -0.195))
    rig.set("hockL", V3(0.157, 0.09, -0.41))
    rig.set("mtpL", V3(0.157, 0.034, -0.24))
    rig.set("htoeL", V3(0.157, 0.012, -0.145))
    rig.set("jawHinge", _hl_rig(t, V3(0, -0.045, -0.04)))
    rig.set("jawTip", _hl_rig(t, V3(0, -0.08, 0.172)))
    var ears = _ear_joints(t)
    rig.set("earBaseL", ears[0])
    rig.set("earTipL", ears[1])
    var tk = t.get("tail")
    var angles: List[Float64] = [-40.0, -62.0]
    var lens: List[Float64] = [0.055 * tk, 0.05 * tk]
    tail_chain(rig, "tailBase", angles, lens)
    rig.mirror_joints()
    quadruped_bones(rig, TAIL_SEGS)
    return rig^


def bear_sculpt(mut m: SdfModel, rig: Rig, t: Traits) raises:
    """Sculpt the bear: procedural-animals' `sculptBear`, primitive for
    primitive, with the claws of its `claws.js` as chains of round cones.

    Args:
        m: The sculpt to add to.
        rig: The bear's rig in bind pose.
        t: The individual.

    Raises:
        Error: If the rig lacks a joint or a bone, or the sculpt refuses
            a primitive.
    """
    var juv = t.juvenile()
    var hump = t.get("hump", 1.0)
    var g = t.get("girth", 1.0)
    # The barrel is broad: the torso's lateral radii carry this factor.
    var gw = g * 1.12

    # TORSO: a deep, very broad barrel; the belly hangs low.
    _ = m.ell(
        "ribcage",
        rig.bone("spine3"),
        V3(0, 0.665, 0.06),
        V3(0.235 * gw, 0.22, 0.32),
        axis=normalize(V3(0, 0.05, -1)),
        k=0,
    )
    var b = rig.bone("chest")
    _ = m.ell(
        "brisket",
        b,
        V3(0, 0.58, 0.29),
        V3(0.175 * gw, 0.17, 0.14),
        axis=normalize(V3(0, -0.3, 1)),
        k=0.08,
    )
    _ = m.ell(
        "pectoral", b, V3(0, 0.645, 0.38), V3(0.165 * gw, 0.15, 0.09), k=0.07
    )
    _ = m.ell(
        "withers",
        b,
        V3(0, 0.84, 0.17),
        V3(0.15 * gw, 0.09, 0.18),
        axis=normalize(V3(0, -0.1, 1)),
        k=0.08,
    )
    # The hump: muscle and fat over the shoulder blades.
    if hump > 0.05:
        var ry = 0.03 * hump + 0.035
        _ = m.ell(
            "hump",
            b,
            V3(0, 0.905 + 0.03 * hump - ry, 0.225),
            V3(0.13 * gw * (0.7 + 0.3 * hump), ry, 0.24),
            axis=normalize(V3(0, 0.08, 1)),
            k=0.07,
        )
    _ = m.ell(
        "back",
        rig.bone("spine3"),
        V3(0, 0.82, -0.04),
        V3(0.17 * gw, 0.08, 0.18),
        k=0.08,
    )
    var sp2 = rig.bone("spine2")
    _ = m.ell(
        "abdomen",
        sp2,
        V3(0, 0.655, -0.14),
        V3(0.195 * gw, 0.19, 0.22),
        axis=normalize(V3(0, 0.08, -1)),
        k=0.08,
    )
    _ = m.ell(
        "belly", sp2, V3(0, 0.475, -0.05), V3(0.12 * gw, 0.09, 0.2), k=0.08
    )
    b = rig.bone("spine1")
    _ = m.ell("loin", b, V3(0, 0.81, -0.21), V3(0.17 * gw, 0.08, 0.15), k=0.07)
    _ = m.ell(
        "flank", b, V3(0, 0.665, -0.28), V3(0.19 * gw, 0.17, 0.14), k=0.07
    )
    b = rig.bone("pelvis")
    _ = m.ell(
        "pelvis", b, V3(0, 0.73, -0.4), V3(0.19 * gw, 0.155, 0.15), k=0.07
    )
    _ = m.ell("croup", b, V3(0, 0.82, -0.38), V3(0.15 * gw, 0.07, 0.14), k=0.06)
    _ = m.ell("perineum", b, V3(0, 0.6, -0.45), V3(0.07, 0.07, 0.13), k=0.06)
    for s in [1.0, -1.0]:  # pragma: no branch
        _ = m.ell(
            "rump",
            b,
            V3(0.09 * s * gw, 0.7, -0.5),
            V3(0.105 * gw, 0.14, 0.1),
            k=0.06,
        )

    # NECK: short, as thick as the head, with a ruff of long hair.
    var n1 = rig.bone("neck1")
    var n2 = rig.bone("neck2")
    _ = m.cone(
        "neck",
        n1,
        V3(0, 0.72, 0.32),
        V3(0, 0.775, 0.49),
        0.17 * g,
        0.135,
        k=0.08,
    )
    _ = m.cone(
        "neck", n2, V3(0, 0.775, 0.49), V3(0, 0.785, 0.58), 0.125, 0.1, k=0.07
    )
    _ = m.ell(
        "nape",
        n1,
        V3(0, 0.83, 0.37),
        V3(0.11 * g, 0.06, 0.13),
        axis=normalize(V3(0, 0.25, 1)),
        k=0.07,
    )
    _ = m.ell(
        "throat",
        n2,
        V3(0, 0.67, 0.51),
        V3(0.095, 0.09, 0.1),
        axis=normalize(V3(0, 0.6, 0.8)),
        k=0.08,
    )
    _ = m.ell(
        "ruff",
        n1,
        V3(0, 0.7, 0.42),
        V3(0.15 * g, 0.14, 0.12),
        axis=normalize(V3(0, 0.4, 1)),
        k=0.07,
    )

    _sculpt_head(m, rig, t, juv)
    _sculpt_ears(m, rig, t)
    _sculpt_legs(m, rig)
    _sculpt_claws(m, rig, t)

    # TAIL: a stubby tail, hidden in the rump fur.
    _ = m.cone(
        "tailroot",
        rig.bone("tail0"),
        V3(0, 0.77, -0.46),
        rig.j("tail1"),
        0.045,
        0.035,
        k=0.04,
    )
    for i in range(TAIL_SEGS):  # pragma: no branch
        _ = m.cone(
            "tail",
            rig.bone("tail" + String(i)),
            rig.j("tail" + String(i)),
            rig.j("tail" + String(i + 1)),
            0.035 - 0.01 * Float64(i),
            0.025 - 0.01 * Float64(i),
            k=0.02,
            thin=i == TAIL_SEGS - 1,
        )


def _hrw(hw: Float64, r: V3) -> V3:
    # Radii in head space: the width follows the head.
    return V3(r.x * hw, r.y, r.z)


def _sculpt_head(mut m: SdfModel, rig: Rig, t: Traits, juv: Float64) raises:
    # A long, broad, low-crowned skull; a shallow dish at the stop; a long
    # broad muzzle ending in a big flat-fronted nose pad.
    var hw = t.get("headW")
    var dish = t.get("dish", 1.0)
    var h = rig.bone("head")

    _ = m.ell(
        "cranium",
        h,
        _hl(t, V3(0, 0.028 + 0.014 * juv, -0.04)),
        _hrw(hw, V3(0.094, 0.076 + 0.016 * juv, 0.1)),
        k=0.05,
    )
    _ = m.cone(
        "forehead",
        h,
        _hl(t, V3(0, 0.02 + 0.006 * (1.0 - dish) + 0.008 * juv, 0.045)),
        _hl(t, V3(0, 0.042 + 0.012 * juv, -0.07)),
        0.041 * hw,
        0.068 * hw,
        k=0.05,
    )
    _ = m.ell(
        "crest",
        h,
        _hl(t, V3(0, 0.068 + 0.012 * juv, -0.066)),
        _hrw(hw, V3(0.1, 0.04, 0.075)),
        k=0.05,
    )
    for s in [1.0, -1.0]:  # pragma: no branch
        _ = m.ell(
            "brow",
            h,
            _hl(t, V3(0.042 * s, 0.0475, 0.056)),
            _hrw(hw, V3(0.021, 0.0095, 0.017)),
            k=0.012,
        )
        _ = m.ell(
            "zygomatic",
            h,
            _hl(t, V3(0.079 * s, 0.004, -0.014)),
            _hrw(hw, V3(0.043, 0.043, 0.066)),
            axis=normalize(V3(-0.25 * s, 0, 1)),
            k=0.06,
        )
        _ = m.ell(
            "cheek",
            h,
            _hl(t, V3(0.05 * s, -0.014, 0.035)),
            _hrw(hw, V3(0.036, 0.03, 0.052)),
            k=0.05,
        )
        _ = m.ell(
            "cheekruff",
            h,
            _hl(t, V3(0.076 * s, -0.016, -0.078)),
            _hrw(hw, V3(0.045, 0.056, 0.06)),
            axis=normalize(V3(0.3 * s, 0, 1)),
            k=0.07,
        )
        _ = m.ell(
            "masseter",
            h,
            _hl(t, V3(0.055 * s, -0.03, -0.04)),
            _hrw(hw, V3(0.032, 0.036, 0.048)),
            k=0.06,
        )
        _ = m.ell(
            "lip",
            h,
            _hl(t, V3(0.029 * s, -0.058, 0.112)),
            _hrw(hw, V3(0.018, 0.026, 0.09)),
            axis=normalize(V3(-0.2 * s, 0.06, 1)),
            k=0.02,
        )
        _ = m.ell(
            "lip",
            h,
            _hl(t, V3(0.04 * s, -0.07, 0.035)),
            _hrw(hw, V3(0.017, 0.017, 0.048)),
            axis=normalize(V3(-0.3 * s, 0.14, 1)),
            k=0.018,
        )
        _ = m.ell(
            "whisker",
            h,
            _hl(t, V3(0.022 * s, -0.035, 0.172)),
            _hrw(hw, V3(0.017, 0.019, 0.03)),
            k=0.018,
        )
    _ = m.cone(
        "nasal",
        h,
        _hl(t, V3(0, 0.016 + 0.012 * (1.0 - dish), 0.07)),
        _hl(t, V3(0, -0.008, 0.19)),
        0.038 * hw,
        0.024 * hw,
        k=0.03,
    )
    _ = m.ell(
        "muzzle",
        h,
        _hl(t, V3(0, -0.028, 0.13)),
        _hrw(hw, V3(0.04, 0.048, 0.08)),
        axis=normalize(V3(0, -0.1, 1)),
        k=0.03,
    )
    # The nose pad: a rounded trapezoid of two lobes, flat in front.
    _ = m.ell(
        "nose",
        h,
        _hl(t, V3(0, 0.0078, 0.2105)),
        _hrw(hw, V3(0.0238, 0.0135, 0.0118)),
        axis=normalize(V3(0, -0.12, 1)),
        k=0.006,
    )
    _ = m.ell(
        "nose",
        h,
        _hl(t, V3(0, -0.009, 0.2105)),
        _hrw(hw, V3(0.0218, 0.0125, 0.0115)),
        axis=normalize(V3(0, -0.2, 1)),
        k=0.008,
    )
    _ = m.ell(
        "philtrum",
        h,
        _hl(t, V3(0, -0.049, 0.194)),
        _hrw(hw, V3(0.018, 0.025, 0.013)),
        k=0.014,
    )
    var eye = bear_eye(t)
    for s in [1.0, -1.0]:  # pragma: no branch
        var ef = eye_frame_of(eye, HEAD_O, s)
        _ = ell_y(
            m,
            "orbit",
            h,
            ef.at(-0.002 * s, 0.0, 0.02),
            ef.y,
            V3(0.02, 0.014, 0.012),
            lateral=ef.x,
            k=0.01,
            carve=True,
        )
        _ = m.sphere("eyelid", h, ef.c, eye.r + eye.lid, k=0.006)
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
        # The nostrils: commas at the pad's lower corners.
        _ = m.ell(
            "nostril",
            h,
            _hl(t, V3(0.0135 * s, -0.0138, 0.2172)),
            V3(0.0064, 0.0045, 0.009),
            axis=normalize(V3(0.35 * s, -0.5, 0.8)),
            up=V3(0, 1, 0),
            k=0.002,
            carve=True,
        )
        _ = m.ell(
            "nostril",
            h,
            _hl(t, V3(0.0198 * s, -0.0078, 0.2132)),
            V3(0.0026, 0.0068, 0.0058),
            axis=normalize(V3(0.8 * s, -0.15, 0.6)),
            up=normalize(V3(0.5 * s, 1, 0)),
            k=0.002,
            carve=True,
        )
        # The canines, hidden behind the lips until the mouth opens.
        _ = m.cone(
            "canine",
            h,
            _hl(t, V3(0.019 * s, -0.052, 0.148)),
            _hl(t, V3(0.018 * s, -0.066, 0.146)),
            0.0055,
            0.002,
            k=0.002,
        )
    _ = m.ell(
        "nosegroove",
        h,
        _hl(t, V3(0, -0.0132, 0.2228)),
        V3(0.0021, 0.0056, 0.0032),
        axis=normalize(V3(0, -0.3, 1)),
        k=0.0015,
        carve=True,
    )

    # JAW: its own surface, so the mouth can open; a small receding chin.
    var jw = rig.bone("jaw")
    _ = m.cone(
        "mandible",
        jw,
        _hl(t, V3(0, -0.07, -0.02)),
        _hl(t, V3(0, -0.076, 0.152)),
        0.026,
        0.012,
        k=0,
        part=JAW,
    )
    for s in [1.0, -1.0]:  # pragma: no branch
        _ = m.cone(
            "mandible",
            jw,
            _hl(t, V3(0.05 * s, -0.066, -0.035)),
            _hl(t, V3(0.014 * s, -0.073, 0.152)),
            0.02,
            0.011,
            k=0.025,
            part=JAW,
        )
    _ = m.ell(
        "chin",
        jw,
        _hl(t, V3(0, -0.079, 0.1)),
        _hrw(hw, V3(0.016, 0.01, 0.02)),
        k=0.02,
        part=JAW,
    )
    for s in [1.0, -1.0]:  # pragma: no branch
        _ = m.cone(
            "canine",
            jw,
            _hl(t, V3(0.017 * s, -0.078, 0.155)),
            _hl(t, V3(0.018 * s, -0.068, 0.157)),
            0.005,
            0.0018,
            k=0.002,
            part=JAW,
        )


def _sculpt_ears(mut m: SdfModel, rig: Rig, t: Traits) raises:
    # Small, round, furred ears, set wide on the top corners of the head.
    var ek = t.get("ear")
    for side in [String("L"), String("R")]:  # pragma: no branch
        var s = 1.0 if side == "L" else -1.0
        var base = rig.j("earBase" + side)
        var tip = rig.j("earTip" + side)
        var up = normalize(tip - base)
        var facing = normalize(V3(0.6 * s, 0.05, 1))
        var lat = normalize(cross(up, facing))
        var eb = rig.bone("ear" + side)
        _ = ell_y(
            m,
            "ear",
            eb,
            lerp(base, tip, 0.3),
            up,
            V3(0.045 * ek, 0.043 * ek, 0.012),
            lateral=lat,
            k=0.016,
            thin=True,
        )
        _ = ell_y(
            m,
            "ear",
            eb,
            lerp(base, tip, 0.7),
            up,
            V3(0.045 * ek, 0.029 * ek, 0.0095),
            lateral=lat,
            k=0.016,
            thin=True,
        )
        _ = ell_y(
            m,
            "earinner",
            eb,
            lerp(base, tip, 0.45) + facing * 0.0105,
            up,
            V3(0.026 * ek, 0.03 * ek, 0.0065),
            lateral=lat,
            k=0.006,
            carve=True,
            thin=True,
        )


def _fore_x() -> List[Float64]:
    return [-0.056, -0.028, 0.0, 0.028, 0.056]


def _fore_z() -> List[Float64]:
    return [-0.02, -0.004, 0.002, -0.004, -0.02]


def _hind_x() -> List[Float64]:
    return [-0.048, -0.024, 0.0, 0.024, 0.048]


def _hind_z() -> List[Float64]:
    return [-0.018, -0.004, 0.002, -0.004, -0.016]


def _sculpt_legs(mut m: SdfModel, rig: Rig) raises:
    # Massive columns; broad plantigrade feet with five toes.
    var fx = _fore_x()
    var fz = _fore_z()
    var hx = _hind_x()
    var hz = _hind_z()
    for side in [String("L"), String("R")]:  # pragma: no branch
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
            lerp(sc, sh, 0.5) + on_side(V3(0.02, 0, 0), s),
            sh - sc,
            V3(0.07, 0.17, 0.13),
            lateral=lat,
            k=0.08,
        )
        _ = m.cone("upperarm", hum, sh, e, 0.11, 0.085, k=0.08)
        _ = ell_y(
            m,
            "triceps",
            hum,
            lerp(sh, e, 0.5) + V3(0, 0, -0.06),
            e - sh,
            V3(0.085, 0.15, 0.08),
            lateral=lat,
            k=0.07,
        )
        _ = ell_y(
            m,
            "armpit",
            hum,
            lerp(sh, e, 0.75) + on_side(V3(-0.035, 0.02, 0.02), s),
            e - sh,
            V3(0.06, 0.1, 0.08),
            lateral=lat,
            k=0.08,
        )
        _ = m.sphere("olecranon", rad, e + V3(0, 0.02, -0.035), 0.045, k=0.04)
        _ = m.cone("forearm", rad, e, w, 0.08, 0.056, k=0.04)
        _ = ell_y(
            m,
            "forearmmuscle",
            rad,
            lerp(e, w, 0.3) + on_side(V3(0.008, 0, 0.012), s),
            w - e,
            V3(0.075, 0.13, 0.075),
            lateral=lat,
            k=0.05,
        )
        # The sleeves: the long hair behind the forearm.
        _ = ell_y(
            m,
            "feather",
            rad,
            lerp(e, w, 0.4) + V3(0, 0, -0.045),
            w - e,
            V3(0.055, 0.13, 0.045),
            lateral=lat,
            k=0.04,
        )
        _ = m.sphere("wrist", meta, w + V3(0, -0.002, 0), 0.05, k=0.03)
        var dp = normalize(toe - mc)
        _ = ell_y(
            m,
            "palm",
            meta,
            lerp(w, mc, 0.55) + V3(0, -0.016, 0),
            mc - w,
            V3(0.07, 0.07, 0.027),
            lateral=lat,
            k=0.03,
        )
        _ = m.sphere(
            "carpalpad", meta, w + V3(0, -0.052, -0.02), 0.017, k=0.015
        )
        _ = ell_y(
            m,
            "paw",
            fpaw,
            mc + dp * 0.01 + V3(0, 0.003, 0),
            dp,
            V3(0.075, 0.045, 0.03),
            lateral=lat,
            k=0.022,
        )
        for i in range(5):  # pragma: no branch
            _ = m.sphere(
                "toe",
                fpaw,
                V3(toe.x + fx[i] * s, 0.024, toe.z - TOE_F - 0.012 + fz[i]),
                0.019,
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
            lerp(hp, kn, 0.42) + on_side(V3(0.02, 0, -0.03), s),
            kn - hp,
            V3(0.1, 0.24, 0.16),
            lateral=lat,
            k=0.08,
        )
        _ = m.cone(
            "thighfront",
            fem,
            on_side(V3(0.12, 0.7, -0.22), s),
            kn + on_side(V3(-0.01, 0.07, 0.02), s),
            0.1,
            0.07,
            k=0.08,
        )
        _ = m.cone(
            "hamstring",
            fem,
            on_side(V3(0.13, 0.74, -0.46), s),
            lerp(kn, hk, 0.3) + V3(0, 0, -0.05),
            0.1,
            0.07,
            k=0.07,
        )
        _ = ell_y(
            m,
            "breeches",
            fem,
            lerp(hp, kn, 0.65) + on_side(V3(0.015, -0.02, -0.12), s),
            kn - hp,
            V3(0.075, 0.13, 0.06),
            lateral=lat,
            k=0.05,
        )
        _ = ell_y(
            m,
            "flankfold",
            fem,
            on_side(V3(0.13, 0.56, -0.16), s),
            V3(-0.05, 0.2, 0.12),
            V3(0.05, 0.13, 0.08),
            lateral=lat,
            k=0.08,
        )
        _ = m.sphere(
            "stifle",
            tib,
            kn + on_side(V3(0.005, 0.01, 0.015), s),
            0.055,
            k=0.05,
        )
        _ = m.cone("shin", tib, lerp(kn, hk, 0.05), hk, 0.065, 0.052, k=0.04)
        _ = ell_y(
            m,
            "calf",
            tib,
            lerp(kn, hk, 0.3) + on_side(V3(0.004, 0.01, -0.045), s),
            hk - kn,
            V3(0.065, 0.12, 0.06),
            lateral=lat,
            k=0.05,
        )
        _ = m.sphere(
            "calcaneus", mtar, hk + V3(0, -0.02, -0.035), 0.045, k=0.03
        )
        _ = m.sphere("hock", mtar, hk, 0.056, k=0.03)
        # The long flat sole, the heel on the ground behind the hock.
        var dh = normalize(tt - mt)
        _ = ell_y(
            m,
            "sole",
            mtar,
            lerp(hk, mt, 0.5) + V3(0, -0.006, 0),
            mt - hk,
            V3(0.062, 0.12, 0.032),
            lateral=lat,
            k=0.03,
        )
        _ = ell_y(
            m,
            "paw",
            hpaw,
            mt + dh * 0.012 + V3(0, 0.004, 0),
            dh,
            V3(0.066, 0.042, 0.03),
            lateral=lat,
            k=0.022,
        )
        for i in range(5):  # pragma: no branch
            _ = m.sphere(
                "toe",
                hpaw,
                V3(tt.x + hx[i] * s, 0.022, tt.z - TOE_H - 0.012 + hz[i]),
                0.017,
                k=0.011,
            )


def _drop_of(span: Float64, th0: Float64, th1: Float64) -> Float64:
    # How far an arc of length `span` drops, pitching from `th0` to `th1`.
    if abs(th1 - th0) < 1e-4:
        return span * sin(th0)
    return span * (cos(th0) - cos(th1)) / (th1 - th0)


def _arc_for(span: Float64, drop: Float64, th0: Float64) -> Float64:
    # The claw's tip pitch, chosen so the tip ends `drop` below the root.
    var lo = th0
    var hi = 75.0 * pi / 180.0
    if _drop_of(span, th0, hi) < drop:
        return hi
    if _drop_of(span, th0, lo) > drop:
        return lo
    for _ in range(30):  # pragma: no branch
        var mid = (lo + hi) / 2.0
        var short = _drop_of(span, th0, mid) < drop
        lo = mid if short else lo
        hi = hi if short else mid
    return (lo + hi) / 2.0


def _claw_point(
    root: V3,
    span: Float64,
    th0: Float64,
    th1: Float64,
    yaw: Float64,
    t: Float64,
) -> V3:
    # A point on the claw's center line: an arc pitching from `th0` at
    # the root to `th1` at the tip, turned out by `yaw`.
    var n = 16
    var x = 0.0
    var y = 0.0
    for i in range(n):  # pragma: no branch
        var u = (Float64(i) + 0.5) / Float64(n) * t
        var th = th0 + (th1 - th0) * u
        x += cos(th) * span * t / Float64(n)
        y -= sin(th) * span * t / Float64(n)
    return root + V3(sin(yaw), 0, cos(yaw)) * x + V3(0, y, 0)


def _sculpt_claws(mut m: SdfModel, rig: Rig, t: Traits) raises:
    # The long, curved, non-retractile claws: each a tube along a circular
    # arc in the paw's plane, tapering to a blunt point, its root buried
    # in the toe. The original builds them as their own mesh; here each is
    # a chain of round cones as thick as its section's mean.
    var k = t.get("claw", 1.0)
    var kk = pow(k, 0.75)
    var fore_len: List[Float64] = [0.78, 0.94, 1.0, 0.97, 0.84]
    var hind_len: List[Float64] = [0.8, 0.95, 1.0, 0.97, 0.85]
    var segs = 8
    for side in [String("L"), String("R")]:  # pragma: no branch
        var s = 1.0 if side == "L" else -1.0
        for fore in [True, False]:  # pragma: no branch
            var dx = _fore_x() if fore else _hind_x()
            var dz = _fore_z() if fore else _hind_z()
            var dl = fore_len.copy() if fore else hind_len.copy()
            var dy = 0.024 if fore else 0.022
            var toe = rig.j(("ftoe" if fore else "htoe") + side)
            var back = TOE_F if fore else TOE_H
            var bone: BoneId = rig.bone(("fpaw" if fore else "hpaw") + side)
            for i in range(5):  # pragma: no branch
                var tp = V3(toe.x + dx[i] * s, dy, toe.z - back - 0.012 + dz[i])
                var root = tp + V3(
                    dx[i] * s * 0.08, 0.001, 0.012 if fore else 0.01
                )
                var span = (0.058 if fore else 0.026) * k * dl[i]
                var th0 = (3.0 if fore else 10.0) * pi / 180.0
                var th1 = _arc_for(
                    span, root.y - (0.006 if fore else 0.008), th0
                )
                var yaw = dx[i] * s * 2.4
                var thick = 0.85 + 0.15 * dl[i]
                var h0 = (0.0175 if fore else 0.0125) * kk * thick
                var w0 = (0.012 if fore else 0.009) * kk * thick
                var prev = root
                var prev_r = 0.5 * sqrt(h0 * w0)
                for j in range(1, segs + 1):  # pragma: no branch
                    var tt = 1.0 - pow(1.0 - Float64(j) / Float64(segs), 1.25)
                    var taper = pow(1.0 - tt, 0.6)
                    var a = max(0.0007, w0 * 0.5 * taper)
                    var bb = max(0.0009, h0 * 0.5 * taper)
                    var r = sqrt(a * bb)
                    var q = _claw_point(root, span, th0, th1, yaw, tt)
                    _ = m.cone(
                        "claw",
                        bone,
                        prev,
                        q,
                        prev_r,
                        r,
                        k=0.004 if j == 1 else 0.0,
                    )
                    prev = q
                    prev_r = r


# ---------------------------------------------------------------- COAT


def _swatches() -> List[String]:
    return [
        String("back"),
        "flank",
        "tip",
        "head",
        "face",
        "muzzle",
        "leg",
        "belly",
        "ear",
        "earRim",
        "earInner",
        "claw",
        "clawBase",
        "clawTip",
    ]


def _coat_hexes(coat: Int) -> List[Int]:
    if coat == RED:
        return [
            0x7A4C30,
            0x5E3924,
            0x9A6A48,
            0x7A5236,
            0x846044,
            0x9A7658,
            0x38241A,
            0x3A2518,
            0x4A2E1C,
            0x241810,
            0x2E1F16,
            0x3C3530,
        ]
    if coat == MEDIUM:
        return [
            0x80593A,
            0x6E4B30,
            0xA57B4C,
            0x8A653E,
            0x92704E,
            0x9E7C58,
            0x45301F,
            0x352315,
            0x4E3622,
            0x251A12,
            0x2E2118,
            0x8E8272,
        ]
    if coat == BLONDE:
        return [
            0x96683E,
            0x74522F,
            0xC8965C,
            0x7C5A3C,
            0x846240,
            0xC0A486,
            0x3A2C22,
            0x3E2E22,
            0x5E4632,
            0x2E2218,
            0x3A2C20,
            0xB8AB94,
        ]
    if coat == GRIZZLED:
        return [
            0x7C7064,
            0x5A4E46,
            0x9E9282,
            0x6E5C4E,
            0x7A6858,
            0x8A7866,
            0x302826,
            0x383028,
            0x4A3E34,
            0x241E1A,
            0x2A2420,
            0xCFC2A8,
        ]
    if coat == BLACK_COAT:
        return [
            0x1B1816,
            0x171412,
            0x24201D,
            0x1C1917,
            0x2A2420,
            0x8A6A4A,
            0x121010,
            0x151311,
            0x1A1715,
            0x0F0D0C,
            0x1C1816,
            0x2A2622,
        ]
    return [
        0x5C4029,
        0x4C3422,
        0x76573A,
        0x634833,
        0x6E5540,
        0x86684C,
        0x35251A,
        0x33241A,
        0x3A291D,
        0x1F1610,
        0x2A1E16,
        0x3A3530,
    ]


def _face_desat(coat: Int) -> Float64:
    # How far the head, the face and the muzzle are grayed, per coat.
    if coat == BLONDE:
        return 0.45
    if coat == GRIZZLED:
        return 0.65
    return 0.35 if coat == BLACK_COAT else 0.55


def _agouti(coat: Int) -> V3:
    # The dark band below a pale tip, on the back, the head and the legs.
    if coat == RED:
        return V3(0.12, 0.06, 0.1)
    if coat == MEDIUM:
        return V3(0.1, 0.06, 0.1)
    if coat == BLONDE:
        return V3(0.3, 0.32, 0.1)
    if coat == GRIZZLED:
        return V3(0.6, 0.4, 0.12)
    return V3(0.0, 0.0, 0.0) if coat == BLACK_COAT else V3(0.12, 0.08, 0.1)


def _desat(c: V3, k: Float64) -> V3:
    var y = 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z
    return V3(c.x + (y - c.x) * k, c.y + (y - c.y) * k, c.z + (y - c.z) * k)


def bear_palette(t: Traits) -> Palette:
    """Return one bear's palette: its coat color, warmed and grayed.

    Photos of brown bears read grayer than the swatches, the head more so.
    A cub's coat is washed into a uniform soft natal brown, its legs
    staying darker. The claws are dark horn worn paler toward the tips.

    Args:
        t: The individual.

    Returns:
        The palette, in linear light.
    """
    var coat = Int(t.get("coat", 0.0))
    var names = _swatches()
    var hexes = _coat_hexes(coat)
    debug_assert(
        len(names) == len(hexes) + 2,
        "The bear's palette tables differ in length",
    )
    var k = t.get("coatWarmth", 0.0)
    var l = t.get("coatLightness", 0.0)
    var juv = t.juvenile()
    var cub_k = 0.2 if coat == BLACK_COAT else (
        1.5 if coat == BLONDE else (1.2 if coat == GRIZZLED else 1.0)
    )
    var cub = srgb(0x6A4C34) * cub_k
    var pal = Palette()
    for i in range(len(hexes)):  # pragma: no branch
        var c = srgb(hexes[i])
        if i != CLAW:
            c = V3(
                c.x * (1.0 + 0.1 * k + l),
                c.y * (1.0 + 0.02 * k + l),
                c.z * (1.0 - 0.12 * k + l),
            )
            var face = i == HEAD or i == FACE or i == MUZZLE
            var tan = coat == BLACK_COAT and i == MUZZLE
            var amount = _face_desat(coat) if (face and not tan) else 0.22
            c = _desat(c, amount)
            var keep = 0.55 if (i == LEG or i == EAR_RIM) else (
                0.4 if i == MUZZLE else 0.15
            )
            c = mix3(c, cub, juv * (1.0 - keep))
        pal.set(names[i], c)
    var claw = pal.get("claw")
    pal.set("clawBase", mix3(claw, srgb(0x2A2420), 0.6))
    pal.set("clawTip", mix3(claw, srgb(0xCDBFA6), 0.7))
    return pal^


def _head_local(t: Traits, p: V3) -> V3:
    # A reference point in head-local meters: the head width and the
    # muzzle stretch undone.
    var x = (p.x - HEAD_O.x) / t.get("headW")
    var y = p.y - HEAD_O.y
    var z = p.z - HEAD_O.z
    var mz = t.get("muzzle")
    return V3(x, y, MUZZLE_Z0 + (z - MUZZLE_Z0) / mz if z > MUZZLE_Z0 else z)


def _lock(p: V3, scale: Float64, off: Float64) -> Float64:
    # Locks of guard hair: noise stretched along the hair, which runs back
    # and down over the body.
    var q = V3(
        p.x * scale + off,
        p.y * scale * 0.6 - p.z * 0.2 * scale,
        p.z * scale * 0.3,
    )
    return fbm3(q, 2) - 0.5


@fieldwise_init
struct _Body(ImplicitlyCopyable):
    var col: V3
    var ag: Float64
    var pad: Bool


def _body(
    c: List[V3],
    t: Traits,
    bone: String,
    p: V3,
    n: V3,
    rb: Int,
    nz: Float64,
    nz2: Float64,
) -> _Body:
    # The torso (`rb` 0), the neck (1) and the tail (4), and the legs.
    var ag3 = _agouti(Int(t.get("coat", 0.0)))
    var bleach = t.get("bleach", 0.0)
    var up = n.y
    var dors = smoothstep(-0.15, 0.7, up + 0.3 * nz)
    var col = mix3(c[FLANK], c[BACK], dors)
    var neck_hump = 0.7 * smoothstep(0.0, 0.7, up) if rb == 1 else 0.0
    var hump_w = (
        smoothstep(0.02, 0.3, p.z)
        * smoothstep(0.62, 0.5, p.z)
        * smoothstep(0.2, 0.8, up)
        + neck_hump
    )
    var tip_k = clamp(hump_w * 0.75 + 0.35 * bleach * dors, 0.0, 1.0)
    col = mix3(
        col,
        c[TIP],
        clamp(tip_k * (1.0 + 0.6 * nz2) + 0.15 * nz2 * dors, 0.0, 1.0),
    )
    var ag = mix(ag3.x * 0.6, ag3.x, dors) + 0.15 * clamp(hump_w, 0.0, 1.0)
    var vent = smoothstep(-0.1, -0.7, up) * smoothstep(0.62, 0.45, p.y)
    col = mix3(col, c[BELLY], vent * 0.85)
    ag *= 1.0 - 0.8 * vent
    if rb == 1:
        col = mix3(col, c[FLANK], smoothstep(0.0, -0.6, up) * 0.6)
        var near_head = 1.0 - smoothstep(0.0, 0.25, 0.595 - p.z)
        col = _desat(
            col, 0.5 * _face_desat(Int(t.get("coat", 0.0))) * near_head
        )
    if rb == 4:
        col = mix3(c[FLANK], c[BACK], 0.5)
    var legness = smoothstep(0.62, 0.4, p.y) if is_limb(bone) else 0.0
    var pad = False
    if legness > 0.0:
        var dark = smoothstep(0.62, 0.3, p.y + 0.06 * nz)
        var lc = mix3(col, c[LEG], dark)
        var la = ag3.z
        var foot = (
            bone.startswith("fpaw")
            or bone.startswith("hpaw")
            or bone.startswith("metacarpus")
            or bone.startswith("metatarsus")
        )
        if foot:
            lc = c[LEG]
            la = 0.0
            var front = bone.startswith("fpaw") or bone.startswith("metacarpus")
            var front_pad = p.y < 0.016 and n.y < -0.55
            var hind_pad = p.y < 0.03 and n.y < -0.35
            pad = front_pad if front else hind_pad
        col = mix3(col, lc, legness)
        ag = mix(ag, la + (ag3.x - la) * (1.0 - dark) * 0.6, legness)
    var collar = t.get("collar", 0.0)
    var collared = collar > 0.0 and (rb == 1 or (rb == 0 and p.z > 0.3))
    if collared:
        var zz = (p.z - 0.47 + 0.04 * nz) / 0.06
        var band = exp(-zz * zz) * smoothstep(
            0.2, -0.3, up + 0.4 * smoothstep(0.3, 0.9, abs(n.x))
        )
        col = mix3(col, srgb(0xE8E0CC), clamp(band * collar * 1.3, 0.0, 0.9))
    return _Body(col, ag, pad)


def bear_paint(
    pal: Palette, t: Traits, tag: String, bone: String, s: CoatSample
) -> Paint:
    """Paint one vertex of a bear.

    The brown bear's coat: the back, the hump and the head palest, with
    sun-bleached guard-hair tips; the legs darkest, near black on the
    lower legs and feet; a dark belly; a face a little paler and grayer
    than the crown, a paler muzzle and dark rings round the small eyes;
    dark ears with pale rims; the nose pad, the lips and the soles black;
    and horn-colored claws, dark at the root and paler at the tip. A
    grizzled coat has silver tips; a black bear is black with a tan
    muzzle; a Eurasian cub may wear a pale collar.

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
    if tag == "claw":
        # Dark horn at the root, paler toward the tip.
        var w = smoothstep(0.024, 0.006, p.y)
        return Paint(mix3(c[CLAW_BASE], c[CLAW_TIP], w), KERATIN)
    if tag == "canine":
        return Paint(srgb(0xE4DAC4), KERATIN)
    if tag == "carpalpad":
        return Paint(srgb(0x1C1814), SKIN)
    var coat = Int(t.get("coat", 0.0))
    var ag3 = _agouti(coat)
    var juv = t.juvenile()
    var off = Float64(Int(t.get("coatSeed", 0.0)) % 997)
    var nz = fbm3(V3(p.x * 5.0 + off, p.y * 5.0, p.z * 5.0), 3) - 0.5
    var nz2 = vnoise3(V3(p.x * 30.0 + off, p.y * 30.0, p.z * 30.0)) - 0.5
    var col: V3
    var ag: Float64
    if bone == "head" or bone == "jaw":
        var face = _paint_head(c, t, tag, bone, p, n, nz, nz2, off)
        if face.surface != FUR:
            return face
        col = face.color
        ag = ag3.y * 0.7
    elif bone.startswith("ear"):
        col = _paint_ear(c, t, p, n, off)
        ag = ag3.y * 0.5
    else:
        var neck = bone == "neck1" or bone == "neck2"
        var rb = 4 if bone.startswith("tail") else (1 if neck else 0)
        var body = _body(c, t, bone, p, n, rb, nz, nz2)
        if body.pad:
            return Paint(srgb(0x1C1814), SKIN)
        col = body.col
        ag = body.ag
        # Clumped locks with pale tips.
        col = col * (1.0 + 0.35 * _lock(p, 40.0, 57.0 + off))
    ag *= 1.0 - 0.8 * juv
    var cvh = fbm3(V3(p.x * 3.0 + 5.0 + off, p.y * 3.0, p.z * 3.0), 2) - 0.5
    var sp = 0.2 if coat == GRIZZLED else 0.15
    col = V3(
        col.x * (1.0 + 0.18 * nz + 0.12 * cvh + sp * nz2),
        col.y * (1.0 + 0.16 * nz + 0.1 * cvh + sp * nz2),
        col.z * (1.0 + 0.12 * nz + 0.04 * cvh + sp * nz2),
    )
    # The agouti band: a pale tip over a dark band, as grizzle.
    var tipped = mix3(
        col,
        c[TIP] * 1.25,
        0.5 * ag * smoothstep(0.45, 0.75, fbm3(p * 160.0, 2)),
    )
    return Paint(grizzle(tipped, p, 130.0, 0.1 + 0.3 * ag), FUR)


def _paint_ear(c: List[V3], t: Traits, p: V3, n: V3, off: Float64) -> V3:
    # Furred ears: a pale rim, a pale cup with a dark hollow, a dark back.
    var sd = 1.0 if p.x > 0.0 else -1.0
    var ears = _ear_joints(t)
    var base = on_side(ears[0], sd)
    var tip = on_side(ears[1], sd)
    var up = normalize(tip - base)
    var facing = normalize(V3(0.6 * sd, 0.05, 1))
    var center = lerp(base, tip, 0.4)
    var front = dot(n, facing)
    var ht = clamp(dot(p - base, up) / 0.1, 0.0, 1.0)
    var rv = p - center
    rv = rv - facing * dot(rv, facing)
    var rim = (1.0 - smoothstep(0.25, 0.7, abs(front))) * smoothstep(
        0.2, 0.45, ht
    )
    var cup = smoothstep(0.2, 0.6, front) * (1.0 - rim)
    var pale = mix3(c[TIP], srgb(0xD9C3A2), 0.15)
    var col = mix3(c[HEAD], c[EAR], 0.15)
    col = mix3(col, pale, rim * 0.55)
    var lat = abs(dot(rv, normalize(cross(up, facing))))
    var hollow = (
        cup
        * (1.0 - smoothstep(0.012, 0.026, lat))
        * (1.0 - smoothstep(0.42, 0.7, ht))
        * smoothstep(0.1, 0.28, ht)
    )
    col = mix3(col, mix3(c[HEAD], pale, 0.45), cup * (1.0 - hollow))
    col = mix3(col, c[EAR_INNER], 0.7 * hollow)
    var back = smoothstep(-0.2, -0.6, front) * smoothstep(0.35, 0.7, ht)
    var nzr = vnoise3(V3(p.x * 65.0 + 13.0 + off, p.y * 65.0, p.z * 65.0)) - 0.5
    return mix3(col, pale, 0.3 * back * smoothstep(-0.1, 0.25, nzr))


def _paint_head(
    c: List[V3],
    t: Traits,
    tag: String,
    bone: String,
    p: V3,
    n: V3,
    nz: Float64,
    nz2: Float64,
    off: Float64,
) -> Paint:
    # The head: a grayer face, a paler muzzle, dark rings round the eyes,
    # the cheek ruff in the body's colors, the nose pad, the lips.
    var h = _head_local(t, p)
    var jaw = bone == "jaw"
    var ax = abs(h.x)
    var bleach = t.get("bleach", 0.0)
    var col = c[HEAD]
    var face = smoothstep(-0.02, 0.07, h.z) * (
        1.0 - 0.6 * smoothstep(0.04, 0.085, ax)
    )
    col = mix3(col, c[FACE], face)
    var lat = smoothstep(0.02, 0.05, ax)
    var muzz = smoothstep(0.06, 0.16, h.z) * (
        1.0 - 0.7 * lat * smoothstep(0.2, 0.12, h.z)
    )
    col = mix3(col, c[MUZZLE], 0.7 * muzz)
    # Short tousled hair: a light and dark motley in locks.
    var lock = _lock(p, 140.0, 31.0 + off)
    var mot = 0.7 * lock + 0.3 * (
        vnoise3(V3(p.x * 110.0 + 31.0 + off, p.y * 110.0, p.z * 110.0)) - 0.5
    )
    col = col * (1.0 + 0.45 * mot * (1.0 - 0.4 * muzz))
    var cheek = (
        smoothstep(0.045, 0.09, ax)
        * smoothstep(0.11, 0.0, h.z)
        * smoothstep(0.045, -0.03, h.y)
    )
    col = mix3(col, mix3(c[HEAD], c[FLANK], 0.5), cheek * 0.35)
    var ruff_w = (
        smoothstep(0.13, -0.05, h.z)
        * smoothstep(-0.02, 0.14, ax)
        * smoothstep(0.125, 0.02, h.y)
        * smoothstep(-0.14, -0.06, h.y)
    )
    var ruffed = not jaw and ruff_w > 0.02
    if ruffed:
        var body = _body(c, t, "neck1", p, n, 1, nz, nz2)
        col = mix3(
            col,
            _desat(body.col, 0.5 * _face_desat(Int(t.get("coat", 0.0)))),
            0.7 * smoothstep(0.1, 0.7, ruff_w),
        )
    # Dark rings round the small eyes, and the dark sides of the bridge.
    var de = length(V3(ax - 0.045, h.y - 0.03, h.z - 0.0698))
    var eye_dark = max(
        exp(-(de / 0.03) * (de / 0.03)),
        max(
            0.8
            * mirrored_blob(h, V3(0.036, 0.012, 0.085), V3(0.014, 0.02, 0.026)),
            0.7
            * mirrored_blob(h, V3(0.048, 0.006, 0.066), V3(0.02, 0.016, 0.02)),
        ),
    )
    col = mix3(col, mix3(c[HEAD], c[LEG], 0.8), eye_dark * 0.9)
    if jaw:
        col = mix3(col, mix3(c[FACE], c[BELLY], 0.55), 0.75)
    col = mix3(
        col, c[TIP], bleach * 0.4 * smoothstep(0.2, 0.8, n.y) * (1.0 - muzz)
    )
    var b_side = (
        smoothstep(0.007, 0.016, ax)
        * (1.0 - smoothstep(0.04, 0.055, ax))
        * smoothstep(0.05, 0.064, h.z)
        * (1.0 - smoothstep(0.105, 0.13, h.z))
        * smoothstep(-0.012, 0.004, h.y)
        * (1.0 - smoothstep(0.044, 0.058, h.y))
    )
    col = mix3(col, mix3(c[HEAD], c[LEG], 0.6), 0.4 * b_side * (1.0 - eye_dark))
    # The lid margins: bare black skin round the aperture.
    var lid = _lid_distance(t, p)
    if lid < 0.0018:
        return Paint(srgb(0x0B0908), SKIN)
    col = mix3(col, srgb(0x0B0908), smoothstep(0.0035, 0.0018, lid) * 0.7)
    # The nose pad, its nostrils and the groove between them.
    var pad = tag == "nose" and h.z > 0.19
    if pad:
        var nc = srgb(0x25242A)
        var d1 = length(
            V3(
                (ax - 0.0135) / 0.0064,
                (h.y + 0.0138) / 0.0045,
                (h.z - 0.2172) / 0.009,
            )
        )
        var d2 = length(
            V3(
                (ax - 0.0198) / 0.0026,
                (h.y + 0.0078) / 0.0068,
                (h.z - 0.2132) / 0.0058,
            )
        )
        var nostril = smoothstep(1.7, 1.15, min(d1, d2))
        nc = mix3(nc, srgb(0x040303), nostril)
        var groove = (1.0 - smoothstep(0.0012, 0.003, ax)) * smoothstep(
            -0.002, -0.008, h.y
        )
        nc = mix3(nc, srgb(0x040303), 0.8 * groove)
        return Paint(nc, NOSE)
    var near_pad = not jaw and h.z > 0.17
    if near_pad:
        var along = smoothstep(-0.046, -0.034, h.y) * smoothstep(
            -0.016, -0.026, h.y
        )
        var cleft = (1.0 - smoothstep(0.0015, 0.0045, ax)) * along
        col = mix3(col, srgb(0x2A201A), 0.7 * cleft)
        var under = smoothstep(-0.052, -0.034, h.y) * (
            1.0 - smoothstep(0.006, 0.02, ax)
        )
        col = mix3(col, mix3(c[FACE], c[BELLY], 0.5), 0.6 * under)
    # The lips: the black edge where the upper lip meets the jaw.
    var lip_f = smoothstep(0.0, 0.06, h.z)
    var line: Float64
    if jaw:
        line = smoothstep(0.1, 0.45, n.y) * smoothstep(-0.085, -0.072, h.y)
    else:
        line = (
            smoothstep(-0.25, -0.6, n.y)
            * smoothstep(-0.068, -0.08, h.y)
            * smoothstep(0.1, 0.0, ax - 0.02)
        )
    if line * lip_f > 0.5:
        return Paint(srgb(0x1A1614), SKIN)
    return Paint(col, FUR)


def _lid_distance(t: Traits, p: V3) -> Float64:
    # The distance from a point to the nearer eye's aperture rim, in the
    # aperture's plane, or far when the point is behind the eye.
    var e = bear_eye(t)
    var s = 1.0 if p.x > HEAD_O.x else -1.0
    var ef = eye_frame_of(e, HEAD_O, s)
    var q = aperture_local(e, ef, p)
    var de = abs(almond_distance(q.x, q.y, e.big_r, e.d))
    return de if q.z > -0.3 * e.r else 1.0
