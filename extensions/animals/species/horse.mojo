# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The horse, Equus caballus: procedural-animals' `species/horse/`.

The reference adult is a 16 hh sport horse, 1.63 m at the withers. Each
leg ends in a cannon, a pastern and a hoof on its own bone. The mane and
the forelock are sculpted as flat sheets of hair laid on the skin, and
the tail as a long tapered volume. Coats are bay, dark bay, chestnut,
black, gray, palomino, dun and buckskin, with seeded white face and leg
markings.
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
from extensions.animals.parts import JAW
from extensions.sdf.sculpt import ell_y
from extensions.animals.kit import (
    EyeSpec,
    eye_frame_of,
    sculpt_eye_socket,
    aperture_tilt_along,
    is_front_limb,
    is_limb,
    pick_weighted,
)
from extensions.animals.noise import cells3, fbm3, vnoise3
from extensions.animals.options import MALE, AnimalOptions, AnimalRandom
from extensions.animals.rig import Rig, tail_chain
from extensions.sdf.field import SdfModel
from extensions.animals.species.hoofed import (
    HeadFrame,
    eye_looking,
    head_ell,
    hoofed_bones,
    lens_distance,
    pitched_head,
)
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
    girth_warp,
    legs_warp,
    length_warp,
    scale_about_warp,
)
from std.math import cos, pi, sin
from extensions.sdf.distance import oriented_ellipsoid_estimate

# Six dock bones and four segments of free-hanging tail hair.
comptime TAIL_SEGS = 10
comptime DOCK_SEGS = 6
# The head's origin: on its axis 0.2 m in front of the poll, level with
# the eyes. The head is pitched 37 degrees nose down in the bind pose.
comptime HEAD_O = V3(0.0, 1.9296369953695903, 1.3597271020094586)
# The finest cell, at the `HERO` tier: the head's cell in the original.
comptime CELL = 0.0051

# The coats, in procedural-animals' order.
comptime BAY = 0
comptime DARK_BAY = 1
comptime CHESTNUT = 2
comptime BLACK = 3
comptime GRAY = 4
comptime PALOMINO = 5
comptime DUN = 6
comptime BUCKSKIN = 7

# The face markings.
comptime FACE_NONE = 0
comptime STAR = 1
comptime STRIPE = 2
comptime BLAZE = 3
comptime SNIP = 4
comptime STAR_SNIP = 5


def _hf() -> HeadFrame:
    return pitched_head(V3(0.0, 2.05, 1.2), 37.0, 0.2)


def horse_variant_names() -> List[String]:
    """Return the horse's coat colors.

    Returns:
        Bay, dark bay, chestnut, black, gray, palomino, dun and buckskin.
    """
    return [
        String("bay"),
        "darkbay",
        "chestnut",
        "black",
        "gray",
        "palomino",
        "dun",
        "buckskin",
    ]


def horse_traits(mut r: AnimalRandom, options: AnimalOptions) raises -> Traits:
    """Draw one horse: procedural-animals' `variation`.

    A male is a gelding two times in three, else a stallion with a heavy
    crest. A foal has long legs, a short body, a big head, a bristly mane
    and a short fluffy tail. The coat color and the white face and leg
    markings are drawn by weight.

    Args:
        r: The individual's stream.
        options: The caller's sex, age and coat.

    Returns:
        The traits.

    Raises:
        Error: If the requested coat is not one of the eight.
    """
    var sex = pick_sex(options.sex, r)
    var age = pick_age(options.age)
    var male = sex == MALE
    var gelding = False
    if male:
        gelding = r.next() < 0.65
    var type_ = r.g()
    var size_g = r.g()
    var coat: Int
    if options.variant.value >= 8:
        raise Error("The horse has no such coat color")
    if options.variant.value >= 0:
        coat = options.variant.value
    else:
        var coats: List[Float64] = [30, 10, 22, 8, 12, 7, 6, 5]
        coat = pick_weighted(r, coats)
    var t = Traits(sex, age, coat)
    var foal = t.juvenile() > 0.0
    t.set(
        "size",
        (1.02 if male else 0.98)
        * (1.0 + 0.045 * size_g)
        * (0.5 if foal else 1.0),
    )
    var faces: List[Float64] = [35, 20, 10, 20, 5, 10]
    t.set("face", Float64(pick_weighted(r, faces)))
    var heights: List[Float64] = [0.0, 0.085, 0.13, 0.24, 0.45]
    var sock_w: List[Float64] = [60, 8, 10, 14, 8]
    var socks = List[Float64]()
    for _ in range(4):  # pragma: no branch
        socks.append(heights[pick_weighted(r, sock_w)])
    if r.next() < 0.3:
        var hind = max(socks[2], socks[3])
        socks[2] = hind
        socks[3] = hind
    for i in range(4):  # pragma: no branch
        t.set("sock" + String(i), socks[i])
    t.set("gelding", 1.0 if gelding else 0.0)
    if male:
        t.set("crest", (0.45 if gelding else 1.0) + 0.15 * r.g())
    else:
        t.set("crest", 0.15 + 0.1 * r.g())
    var flaxen = False
    if coat == CHESTNUT:
        flaxen = r.next() < 0.3
    t.set("flaxen", 1.0 if flaxen else 0.0)
    var gray_level = 0.0
    if coat == GRAY:
        gray_level = 0.05 if foal else 0.15 + 0.75 * r.next()
    t.set("grayLevel", gray_level)
    t.set("maneLen", 0.14 + 0.12 * r.next())
    t.set("maneSide", -1.0 if r.next() < 0.8 else 1.0)
    t.set("coatShade", r.g())
    t.set("coatLightness", 0.06 * r.g())
    t.set("coatSeed", Float64(Int(r.next() * 1e6)))
    t.set("minThick", 0.006)
    t.warps.add(
        legs_warp(
            (1.0 + 0.035 * r.g() - 0.025 * type_) * (1.55 if foal else 1.0),
            0.95,
        )
    )
    t.warps.add(
        length_warp(
            (1.0 + 0.03 * r.g() - 0.015 * type_) * (0.86 if foal else 1.0),
            -0.62,
            0.62,
        )
    )
    var stallion = male and not gelding
    t.warps.add(
        girth_warp(
            (1.0 + 0.05 * type_) * (1.02 if stallion else 1.0), 1.25, -0.7, 0.75
        )
    )
    t.warps.add(
        scale_about_warp(
            HEAD_O, (1.0 + 0.03 * r.g()) * (1.22 if foal else 1.0), 0.2, 0.4
        )
    )
    return t^


def horse_eye(t: Traits) -> EyeSpec:
    """Return the horse's left eye: large, high on the side of the head.

    The globe is about 50 mm across. The eye looks out and 22 degrees
    forward along the nasal line, and its almond follows the nasal line
    with the inner corner a little lower.

    Args:
        t: The individual. Every horse has the same eye.

    Returns:
        The eye, head-local.
    """
    return _eye()


def _eye() -> EyeSpec:
    var hf = _hf()
    var a = 22.0 * pi / 180.0
    var look = normalize(V3(cos(a), 0.0, 0.0) + hf.hz * sin(a))
    var e = eye_looking(
        hf,
        V3(0.092, -0.004, -0.01),
        look,
        0.026,
        0.005,
        0.0026,
        0.0262,
        0.0133,
        -0.0015,
        0.0137,
        0.0182,
    )
    e.tilt = aperture_tilt_along(e, HEAD_O, hf.hz) - 0.12
    return e


def _joints(mut rig: Rig) raises:
    var hf = _hf()
    rig.set("nose", hf.at(V3(0.0, 0.0, 0.4)))
    rig.set("occiput", hf.at(V3(0.0, -0.06, -0.19)))
    rig.set("neckMid", V3(0.0, 1.63, 0.97))
    rig.set("neckBase", V3(0.0, 1.19, 0.74))
    rig.set("chestMid", V3(0.0, 1.4, 0.4))
    rig.set("thoraxRear", V3(0.0, 1.43, 0.02))
    rig.set("lumbarMid", V3(0.0, 1.46, -0.24))
    rig.set("lumbosacral", V3(0.0, 1.47, -0.44))
    rig.set("tailBase", V3(0.0, 1.46, -0.8))
    rig.set("scapTopL", V3(0.1, 1.47, 0.5))
    rig.set("shoulderL", V3(0.165, 1.14, 0.77))
    rig.set("elbowL", V3(0.16, 0.9, 0.6))
    rig.set("wristL", V3(0.13, 0.5, 0.63))
    rig.set("mcpL", V3(0.125, 0.17, 0.64))
    rig.set("fcoffinL", FCOFFIN)
    rig.set("ftoeL", V3(0.125, 0.004, 0.8))
    rig.set("hipL", V3(0.155, 1.23, -0.62))
    rig.set("kneeL", V3(0.185, 0.94, -0.36))
    rig.set("hockL", V3(0.13, 0.55, -0.61))
    rig.set("mtpL", V3(0.12, 0.175, -0.585))
    rig.set("hcoffinL", HCOFFIN)
    rig.set("htoeL", V3(0.12, 0.004, -0.435))
    # Tack landmarks: the saddle base, the rider's seat and the stirrups.
    rig.set("saddle", V3(0.0, 1.625, 0.21))
    rig.set("seat", V3(0.0, 1.745, 0.19))
    rig.set("stirrupL", V3(0.3, 1.02, 0.24))
    rig.set("jawHinge", hf.at(V3(0.0, -0.04, -0.1)))
    rig.set("jawTip", hf.at(V3(0.0, -0.1, 0.39)))
    rig.set("earBaseL", hf.at(EAR_BASE))
    rig.set("earTipL", hf.at(EAR_TIP))


comptime FCOFFIN = V3(0.125, 0.066, 0.713)
comptime HCOFFIN = V3(0.12, 0.068, -0.515)
comptime EAR_BASE = V3(0.058, 0.06, -0.185)
comptime EAR_TIP = V3(0.085, 0.205, -0.225)


def horse_rig(t: Traits) raises -> Rig:
    """Return the horse's skeleton in bind pose.

    Landmarks are from a 16 hh warmblood: point of shoulder 1.14 m, elbow
    0.90, carpus 0.50, fetlock 0.17, stifle 0.90 and hock 0.55. The dock
    droops from the croup and the hair hangs to the hocks.

    Args:
        t: The individual. Every horse has the same reference rig.

    Returns:
        The rig.

    Raises:
        Error: If a bone names a missing joint.
    """
    var rig = Rig()
    _joints(rig)
    var angles: List[Float64] = [
        -25,
        -50,
        -66,
        -76,
        -82,
        -86,
        -88,
        -89,
        -89,
        -89,
    ]
    var lens: List[Float64] = [
        0.085,
        0.08,
        0.075,
        0.07,
        0.065,
        0.06,
        0.12,
        0.12,
        0.12,
        0.12,
    ]
    tail_chain(rig, "tailBase", angles, lens)
    rig.mirror_joints()
    hoofed_bones(rig, TAIL_SEGS)
    return rig^


def _head(mut m: SdfModel, h: BoneId) raises:
    # The head, in head-local coordinates: cranium to the eye sockets.
    var hf = _hf()
    _ = head_ell(
        m, "cranium", h, hf, V3(0, 0.02, -0.1), V3(0.085, 0.075, 0.11), k=0.05
    )
    _ = head_ell(
        m, "poll", h, hf, V3(0, -0.01, -0.17), V3(0.065, 0.065, 0.06), k=0.05
    )
    _ = head_ell(
        m, "forehead", h, hf, V3(0, 0.045, 0.0), V3(0.095, 0.042, 0.12), k=0.04
    )
    # A slightly dished nasal line.
    _ = head_ell(
        m, "face", h, hf, V3(0, 0.008, 0.2), V3(0.056, 0.042, 0.19), k=0.04
    )
    _ = head_ell(
        m,
        "lowerface",
        h,
        hf,
        V3(0, -0.055, 0.21),
        V3(0.052, 0.062, 0.15),
        k=0.05,
    )
    _ = head_ell(
        m, "muzzle", h, hf, V3(0, -0.026, 0.35), V3(0.05, 0.048, 0.06), k=0.04
    )
    _ = head_ell(
        m,
        "upperlip",
        h,
        hf,
        V3(0, -0.066, 0.372),
        V3(0.044, 0.026, 0.046),
        k=0.025,
    )
    var eye = _eye()
    for s in [1.0, -1.0]:  # pragma: no branch
        # The masseter, and the mandible's lower border to the chin.
        _ = head_ell(
            m,
            "cheek",
            h,
            hf,
            V3(0.055 * s, -0.075, 0.07),
            V3(0.048, 0.095, 0.11),
            k=0.05,
        )
        _ = m.cone(
            "mandible",
            h,
            hf.at(V3(0.05 * s, -0.145, 0.07)),
            hf.at(V3(0.028 * s, -0.108, 0.3)),
            0.03,
            0.02,
            k=0.04,
        )
        _ = head_ell(
            m,
            "facialcrest",
            h,
            hf,
            V3(0.075 * s, -0.04, 0.08),
            V3(0.016, 0.018, 0.08),
            k=0.03,
        )
        # The bony orbital ridge over the eye.
        _ = head_ell(
            m,
            "brow",
            h,
            hf,
            V3(0.076 * s, 0.034, -0.008),
            V3(0.03, 0.022, 0.04),
            k=0.03,
        )
        _ = head_ell(
            m,
            "nostrilwing",
            h,
            hf,
            V3(0.036 * s, -0.02, 0.352),
            V3(0.02, 0.026, 0.032),
            k=0.02,
        )
        _ = sculpt_eye_socket(
            m,
            eye,
            HEAD_O,
            s,
            h,
            orbit_r=V3(0.03, 0.022, 0.018),
            orbit_at=V3(0.0, 0.002, 0.03),
            orbit_k=0.012,
        )


def _bone_list(m: SdfModel, h: BoneId) -> List[Int]:
    # The primitives on one bone that are not on the jaw, carvers too.
    var ids = List[Int]()
    # Both callers pass the head, sculpted just before.
    for i in range(len(m.prims)):
        var keep = m.prims[i].bone == h and m.prims[i].part != JAW
        if keep:
            ids.append(i)
    return ids^


def _nostril(m: SdfModel, ids: List[Int], s: Float64) -> Tuple[V3, V3]:
    # Where the nostril opens: the low round opening on the muzzle's skin
    # and the direction up its tail, head-local.
    var n_l = normalize(V3(0.6 * s, 0.05, 0.8))
    var low = _skin_along(m, ids, V3(0.02 * s, -0.03, 0.34), n_l)
    var high = _skin_along(m, ids, V3(0.03 * s, -0.004, 0.33), n_l)
    return (low, normalize(high - low))


def _skin_along(m: SdfModel, ids: List[Int], o: V3, d: V3) -> V3:
    # The head-local point where the ray `o + t d` leaves the head.
    var hf = _hf()
    var lo = 0.0
    var hi = 0.12
    for _ in range(30):  # pragma: no branch
        var t = 0.5 * (lo + hi)
        var inside = m.eval_list(ids, hf.at(o + d * t)) < 0.0
        lo = t if inside else lo
        hi = hi if inside else t
    return o + d * (0.5 * (lo + hi))


def horse_sculpt(mut m: SdfModel, rig: Rig, t: Traits) raises:
    """Sculpt the horse: procedural-animals' `sculptHorse`, primitive for
    primitive.

    Args:
        m: The sculpt to add to.
        rig: The horse's rig in bind pose.
        t: The individual.

    Raises:
        Error: If the rig lacks a joint or a bone, or the sculpt refuses
            a primitive.
    """
    var crest = t.get("crest", 0.3)
    var foal = t.juvenile() > 0.0
    var seed = t.get("coatSeed", 0.0)
    var r = AnimalRandom(9173 + Int(seed), 1, 0)
    var hf = _hf()

    # TORSO: a deep barrel, the sternum 0.88 m above the ground.
    _ = m.ell(
        "ribcage",
        rig.bone("spine3"),
        V3(0, 1.26, 0.14),
        V3(0.285, 0.345, 0.56),
        axis=normalize(V3(0, 0.06, 1)),
        k=0,
    )
    _ = m.ell(
        "girth",
        rig.bone("chest"),
        V3(0, 1.22, 0.46),
        V3(0.24, 0.29, 0.2),
        k=0.08,
    )
    _ = m.ell(
        "abdomen",
        rig.bone("spine2"),
        V3(0, 1.25, -0.16),
        V3(0.29, 0.29, 0.32),
        axis=normalize(V3(0, 0.16, -1)),
        k=0.1,
    )
    _ = m.ell(
        "flank",
        rig.bone("spine1"),
        V3(0, 1.32, -0.38),
        V3(0.26, 0.22, 0.22),
        k=0.1,
    )
    # The withers: the dorsal spines of T3 to T9 between the scapulae.
    _ = m.ell(
        "withers",
        rig.bone("chest"),
        V3(0, 1.5, 0.44),
        V3(0.075, 0.12, 0.22),
        axis=normalize(V3(0, -0.2, 1)),
        k=0.1,
    )
    _ = m.ell(
        "back",
        rig.bone("spine3"),
        V3(0, 1.46, 0.08),
        V3(0.17, 0.085, 0.36),
        k=0.1,
    )
    _ = m.ell(
        "loin",
        rig.bone("spine1"),
        V3(0, 1.48, -0.3),
        V3(0.2, 0.08, 0.22),
        k=0.1,
    )
    var pb = rig.bone("pelvis")
    _ = m.ell("pelvis", pb, V3(0, 1.41, -0.6), V3(0.27, 0.21, 0.26), k=0.08)
    _ = m.ell(
        "croup",
        pb,
        V3(0, 1.5, -0.58),
        V3(0.2, 0.09, 0.27),
        axis=normalize(V3(0, -0.12, 1)),
        k=0.08,
    )
    for s in [1.0, -1.0]:  # pragma: no branch
        _ = m.sphere("hippoint", pb, V3(0.235 * s, 1.44, -0.43), 0.065, k=0.08)
        _ = m.ell(
            "rump", pb, V3(0.13 * s, 1.33, -0.72), V3(0.13, 0.19, 0.12), k=0.08
        )
    # The pectorals: a broad, rounded breast between the forelegs.
    var cb = rig.bone("chest")
    _ = m.ell("brisket", cb, V3(0, 1.08, 0.64), V3(0.17, 0.16, 0.17), k=0.08)
    for s in [1.0, -1.0]:  # pragma: no branch
        _ = m.ell(
            "pectoral",
            cb,
            V3(0.105 * s, 1.07, 0.75),
            V3(0.1, 0.14, 0.09),
            k=0.07,
        )
    if t.male():
        # The sheath between the hind legs.
        _ = m.ell(
            "sheath",
            rig.bone("spine1"),
            V3(0, 0.94, -0.2),
            V3(0.045, 0.055, 0.1),
            axis=normalize(V3(0, 0.3, 1)),
            k=0.05,
        )

    # NECK: flattened side to side, deep at the base, rising to the poll.
    var withers = V3(0, 1.64, 0.5)
    var chest_f = V3(0, 1.15, 0.86)
    var poll_t = hf.at(V3(0, 0, -0.2))
    var latch = hf.at(V3(0, -0.17, 0.07))
    var c_base = lerp(withers, chest_f, 0.5)
    var c_top = lerp(poll_t, latch, 0.5)
    var n_ax = normalize(c_top - c_base)
    var n_up = normalize(V3(0, n_ax.z, -n_ax.y))
    var n1 = rig.bone("neck1")
    var n2 = rig.bone("neck2")
    var neck_t: List[Float64] = [0.12, 0.38, 0.62, 0.84]
    var neck_w: List[Float64] = [0.2, 0.155, 0.12, 0.095]
    var neck_d: List[Float64] = [0.27, 0.215, 0.17, 0.13]
    var neck_l: List[Float64] = [0.2, 0.2, 0.18, 0.14]
    for i in range(4):  # pragma: no branch
        _ = m.ell(
            "neck",
            n1 if i < 2 else n2,
            lerp(c_base, c_top, neck_t[i]),
            V3(neck_w[i], neck_d[i], neck_l[i]),
            axis=n_ax,
            up=n_up,
            k=0.09,
        )
    # The crest: an arch along the top of the neck, heavier in stallions.
    var cd = normalize(poll_t - withers)
    var crest_t: List[Float64] = [0.3, 0.62, 0.86]
    var crest_r: List[Float64] = [0.075, 0.06, 0.05]
    for i in range(3):  # pragma: no branch
        var r0 = crest_r[i]
        _ = m.ell(
            "crest",
            n1 if i == 0 else n2,
            _crest_top(withers, poll_t, n_up, crest_t[i])
            + n_up * -(r0 + 0.012),
            V3(r0 + 0.035 * crest, r0 + 0.025 * crest, 0.2),
            axis=cd,
            up=n_up,
            k=0.08,
        )
    # The underline: trachea and jugular groove, to a narrow throat latch.
    var ud = normalize(latch - chest_f)
    var in_u = normalize(V3(0, ud.z, -ud.y))
    _ = m.cone(
        "throat",
        n1,
        lerp(chest_f, latch, 0.08) + in_u * 0.08,
        lerp(chest_f, latch, 0.55) + in_u * 0.06,
        0.08,
        0.06,
        k=0.08,
    )
    _ = m.cone(
        "throat",
        n2,
        lerp(chest_f, latch, 0.55) + in_u * 0.06,
        hf.at(V3(0, -0.13, -0.03)),
        0.06,
        0.045,
        k=0.07,
    )

    # HEAD, in head-local coordinates.
    var h = rig.bone("head")
    _head(m, h)
    # The nostrils: a large comma each side of the muzzle, the round
    # opening low and the false nostril rising up and out. The carvers
    # sit a measured depth under the skin.
    var muzzle = _bone_list(m, h)
    for s in [1.0, -1.0]:  # pragma: no branch
        var n_l = normalize(V3(0.6 * s, 0.05, 0.8))
        var no = _nostril(m, muzzle, s)
        _ = head_ell(
            m,
            "nostril",
            h,
            hf,
            no[0] - n_l * 0.011,
            V3(0.013, 0.017, 0.028),
            k=0.006,
            axis_l=n_l,
            up_l=no[1],
            carve=True,
        )
        _ = head_ell(
            m,
            "nostril",
            h,
            hf,
            no[0] + no[1] * 0.022 - n_l * 0.012,
            V3(0.0085, 0.014, 0.024),
            k=0.008,
            axis_l=n_l,
            up_l=no[1],
            carve=True,
        )

    # JAW: the lower lip and the chin, so the mouth can open.
    var jw = rig.bone("jaw")
    _ = m.ell(
        "chin",
        jw,
        hf.at(V3(0, -0.104, 0.345)),
        V3(0.036, 0.03, 0.052),
        axis=hf.hz,
        up=hf.hy,
        k=0,
        part=JAW,
    )
    _ = m.ell(
        "lowerlip",
        jw,
        hf.at(V3(0, -0.09, 0.39)),
        V3(0.038, 0.022, 0.034),
        axis=hf.hz,
        up=hf.hy,
        k=0.02,
        part=JAW,
    )
    for s in [1.0, -1.0]:  # pragma: no branch
        _ = m.cone(
            "mandible",
            jw,
            hf.at(V3(0.026 * s, -0.104, 0.29)),
            hf.at(V3(0.018 * s, -0.102, 0.35)),
            0.018,
            0.022,
            k=0.03,
            part=JAW,
        )

    # EARS: long, cupped and pointed.
    for side in [String("L"), String("R")]:  # pragma: no branch
        var s = 1.0 if side == "L" else -1.0
        var base = rig.j("earBase" + side)
        var tip = rig.j("earTip" + side)
        var up = normalize(tip - base)
        var facing = normalize(hf.hz * 0.9 + V3(0.55 * s, 0, 0))
        var lat = normalize(cross(up, facing))
        var eb = rig.bone("ear" + side)
        _ = ell_y(
            m,
            "ear",
            eb,
            lerp(base, tip, 0.42),
            up,
            V3(0.034, 0.083, 0.02),
            lateral=lat,
            k=0.02,
            thin=True,
        )
        _ = ell_y(
            m,
            "eartip",
            eb,
            lerp(base, tip, 0.8),
            up,
            V3(0.019, 0.045, 0.013),
            lateral=lat,
            k=0.02,
            thin=True,
        )
        _ = ell_y(
            m,
            "earinner",
            eb,
            lerp(base, tip, 0.5) + facing * 0.016,
            up,
            V3(0.024, 0.075, 0.014),
            lateral=lat,
            k=0.006,
            carve=True,
            thin=True,
        )
        # The ear's base muscles on the poll.
        _ = m.sphere("earbase", h, base + up * -0.01, 0.035, k=0.035)

    # MANE: a ridge of hair on the crest, and a sheet of hair falling from
    # it down one side of the neck, as flat ellipsoids laid on the skin.
    var mane_side = t.get("maneSide", -1.0)
    var mane_len = 0.05 if foal else t.get("maneLen", 0.2)
    var neck_ids = List[Int]()
    # The body is already sculpted.
    for i in range(len(m.prims)):  # pragma: no branch
        var keep = (
            m.prims[i].part != JAW
            and m.prims[i].bone != h
            and not m.prims[i].carve
        )
        if keep:
            neck_ids.append(i)
    var nl = 22
    for i in range(nl):  # pragma: no branch
        var tt = _t_at(i, nl)
        var lift = n_up * (0.028 * crest * sin(pi * min(1.0, tt * 1.15)))
        var p = _crest_top(withers, poll_t, n_up, tt) + lift
        var p2 = _crest_top(withers, poll_t, n_up, min(1.0, tt + 0.04)) + lift
        # The ridge thins out over the last 15 % toward the poll, where the
        # mane runs into the forelock.
        var to_poll = 1.0 - 0.6 * clamp((tt - 0.82) / 0.15, 0.0, 1.0)
        _ = m.ell(
            "manecrest",
            n1 if tt < 0.45 else n2,
            p + n_up * (-0.01 - 0.008 * (1.0 - to_poll)),
            V3(
                (0.03 + 0.03 * crest) * (0.6 + 0.4 * to_poll),
                (0.045 if foal else 0.028) * to_poll,
                0.06,
            ),
            axis=normalize(p2 - p),
            up=n_up,
            k=0.04,
        )
    if not foal:
        var ns = 16
        var down = normalize(-n_up + V3(0, 0, -0.15))
        for i in range(ns):  # pragma: no branch
            var tt = _t_at(i, ns)
            var lift = n_up * (0.028 * crest * sin(pi * min(1.0, tt * 1.15)))
            var p = _crest_top(withers, poll_t, n_up, tt) + lift
            var spacing = length(
                _crest_top(withers, poll_t, n_up, _t_at(i + 1, ns))
                - _crest_top(withers, poll_t, n_up, tt)
            )
            var along = normalize(
                _crest_top(withers, poll_t, n_up, min(1.0, tt + 0.02))
                - _crest_top(withers, poll_t, n_up, max(0.0, tt - 0.02))
            )
            var ln = (
                mane_len
                * (0.75 + 0.5 * r.next())
                * (0.65 + 0.35 * sin(pi * min(1.0, tt * 1.25)))
            )
            var bone = n1 if tt < 0.45 else n2
            var th = 0.0085
            # The hair leaves the crest over its top: the sheet starts on
            # the crest's far edge.
            var depths: List[Float64] = [0.02, 0.02 + (ln - 0.02) * 0.5, ln]
            var sk = List[V3]()
            for d in depths:  # pragma: no branch
                sk.append(_skin_x(m, neck_ids, mane_side, p + down * d))
            for j in range(2):  # pragma: no branch
                var a0 = sk[j]
                var a1 = sk[j + 1]
                var ax = normalize(a1 - a0)
                var nrm = normalize(cross(ax, along))
                var outward = nrm if nrm.x * mane_side >= 0.0 else -nrm
                _ = m.ell(
                    "mane",
                    bone,
                    lerp(a0, a1, 0.5) + outward * (th * 0.35),
                    V3(spacing * 0.85, th, length(a1 - a0) * 0.58 + 0.01),
                    axis=ax,
                    up=outward,
                    k=0.022,
                )
        # The forelock: a thin lock lying flat from the poll down the
        # forehead, ending above the eyes.
        var head_ids = _bone_list(m, h)
        var count = 7
        var z0 = -0.2
        var z1 = -0.035
        for i in range(count):  # pragma: no branch
            var u = Float64(i) / Float64(count - 1)
            var z = z0 + (z1 - z0) * u
            var zb = z + 0.3 * (z1 - z0) / Float64(count - 1)
            var y = _skin_y(m, head_ids, z)
            var yb = _skin_y(m, head_ids, zb)
            var thick = 0.0085 - 0.0035 * u
            var sway = 0.006 * sin(3.1 * u + seed)
            _ = head_ell(
                m,
                "forelock",
                h,
                hf,
                V3(sway, y - 0.15 * thick, z),
                V3(0.03 - 0.014 * u, thick, 0.034),
                k=0.012,
                axis_l=V3(0, yb - y, zb - z),
                up_l=V3(0, zb - z, -(yb - y)),
            )

    # LEGS.
    for side in [String("L"), String("R")]:  # pragma: no branch
        _foreleg(m, rig, side)
        _hind_leg(m, rig, side)

    # TAIL: the dock, then the hair as one tapered volume to the hocks.
    for i in range(DOCK_SEGS):  # pragma: no branch
        var t0 = Float64(i) / Float64(DOCK_SEGS)
        var t1 = Float64(i + 1) / Float64(DOCK_SEGS)
        _ = m.cone(
            "dock",
            rig.bone("tail" + String(i)),
            rig.j("tail" + String(i)),
            rig.j("tail" + String(i + 1)),
            0.062 - 0.03 * t0,
            0.062 - 0.03 * t1,
            k=0.06 if i == 0 else 0.01,
        )
    var n_hair = DOCK_SEGS if foal else TAIL_SEGS
    for i in range(n_hair):  # pragma: no branch
        var a = rig.j("tail" + String(i))
        if i == 0:
            a = lerp(rig.j("tail0"), rig.j("tail1"), 0.4)
        _ = m.cone(
            "tailhair",
            rig.bone("tail" + String(i)),
            a,
            rig.j("tail" + String(i + 1)),
            _hair_r(i, foal) * (0.8 if i == 0 else 1.0),
            _hair_r(i + 1, foal),
            k=0.03 if i == 0 else 0.015,
        )


def _foreleg(mut m: SdfModel, rig: Rig, side: String) raises:
    var s = 1.0 if side == "L" else -1.0
    var lat = V3(s, 0, 0)
    var sc = rig.j("scapTop" + side)
    var sh = rig.j("shoulder" + side)
    var e = rig.j("elbow" + side)
    var w = rig.j("wrist" + side)
    var mc = rig.j("mcp" + side)
    var c = rig.j("fcoffin" + side)
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
        lerp(sc, sh, 0.45) + on_side(V3(0.07, 0, -0.02), s),
        sh - sc,
        V3(0.08, 0.26, 0.15),
        lateral=lat,
        k=0.1,
    )
    _ = m.sphere(
        "shoulderpoint", hum, sh + on_side(V3(0.02, 0.0, 0.03), s), 0.07, k=0.08
    )
    _ = m.cone("upperarm", hum, sh, e, 0.1, 0.085, k=0.08)
    _ = ell_y(
        m,
        "triceps",
        hum,
        lerp(sh, e, 0.55) + on_side(V3(0.01, 0.02, -0.1), s),
        e - sh,
        V3(0.1, 0.17, 0.12),
        lateral=lat,
        k=0.08,
    )
    _ = m.sphere("olecranon", rad, e + V3(0, 0.02, -0.075), 0.055, k=0.05)
    _ = m.cone("forearm", rad, e + V3(0, 0, -0.01), w, 0.085, 0.047, k=0.05)
    _ = ell_y(
        m,
        "forearmmuscle",
        rad,
        lerp(e, w, 0.22) + on_side(V3(0.008, 0, 0.012), s),
        w - e,
        V3(0.078, 0.16, 0.085),
        lateral=lat,
        k=0.05,
    )
    _ = m.cone(
        "forearmweb",
        rad,
        e + on_side(V3(-0.04, 0.06, -0.02), s),
        lerp(e, w, 0.3) + on_side(V3(-0.02, 0, 0), s),
        0.06,
        0.045,
        k=0.06,
    )
    # The knee (carpus): broad and flat in front, the accessory behind.
    _ = ell_y(
        m,
        "knee",
        meta,
        w + V3(0, 0.0, 0.004),
        V3(0, 1, 0),
        V3(0.05, 0.06, 0.047),
        lateral=lat,
        k=0.025,
    )
    _ = m.sphere("accessory", meta, w + V3(0, 0.03, -0.04), 0.024, k=0.02)
    # The cannon: flat bone in front, flexor tendons behind.
    _ = m.cone(
        "cannon",
        meta,
        w + V3(0, -0.02, 0.0),
        mc + V3(0, 0.02, 0.0),
        0.034,
        0.032,
        k=0.02,
    )
    _ = m.cone(
        "tendon",
        meta,
        w + V3(0, -0.03, -0.03),
        mc + V3(0, 0.03, -0.034),
        0.022,
        0.026,
        k=0.02,
    )
    # The fetlock, ergot, pastern, coronet and hoof.
    _ = ell_y(
        m,
        "fetlock",
        meta,
        mc + V3(0, 0.0, -0.012),
        V3(0, 1, 0.3),
        V3(0.044, 0.05, 0.05),
        lateral=lat,
        k=0.02,
    )
    _ = m.sphere("ergot", fpaw, mc + V3(0, -0.02, -0.052), 0.018, k=0.018)
    _ = m.cone("pastern", fpaw, mc, c, 0.036, 0.037, k=0.02)
    _hoof(m, rig.bone("fhoof" + side), c, toe, 1.0)


def _hind_leg(mut m: SdfModel, rig: Rig, side: String) raises:
    var s = 1.0 if side == "L" else -1.0
    var lat = V3(s, 0, 0)
    var hp = rig.j("hip" + side)
    var kn = rig.j("knee" + side)
    var hk = rig.j("hock" + side)
    var mt = rig.j("mtp" + side)
    var ch = rig.j("hcoffin" + side)
    var tt = rig.j("htoe" + side)
    var fem = rig.bone("femur" + side)
    var tib = rig.bone("tibia" + side)
    var mtar = rig.bone("metatarsus" + side)
    var hpaw = rig.bone("hpaw" + side)
    # The thigh fills the quarter from the point of hip to the stifle.
    _ = ell_y(
        m,
        "thigh",
        fem,
        lerp(hp, kn, 0.42) + on_side(V3(0.04, 0, -0.05), s),
        kn - hp,
        V3(0.1, 0.3, 0.22),
        lateral=lat,
        k=0.1,
    )
    _ = m.cone(
        "thighfront",
        fem,
        on_side(V3(0.2, 1.32, -0.45), s),
        kn + on_side(V3(0.0, 0.06, 0.04), s),
        0.12,
        0.07,
        k=0.1,
    )
    _ = m.cone(
        "hamstring",
        fem,
        on_side(V3(0.12, 1.3, -0.74), s),
        lerp(kn, hk, 0.3) + V3(0, 0, -0.09),
        0.12,
        0.065,
        k=0.08,
    )
    _ = ell_y(
        m,
        "flankfold",
        fem,
        on_side(V3(0.2, 1.03, -0.3), s),
        V3(-0.1, 0.3, 0.12),
        V3(0.05, 0.15, 0.08),
        lateral=lat,
        k=0.1,
    )
    _ = m.sphere(
        "stifle", tib, kn + on_side(V3(0.01, 0.01, 0.03), s), 0.06, k=0.07
    )
    _ = ell_y(
        m,
        "gaskin",
        tib,
        lerp(kn, hk, 0.32) + on_side(V3(0.008, 0, -0.05), s),
        hk - kn,
        V3(0.078, 0.17, 0.095),
        lateral=lat,
        k=0.06,
    )
    _ = m.cone("shin", tib, lerp(kn, hk, 0.1), hk, 0.06, 0.045, k=0.05)
    _ = m.cone(
        "achilles",
        tib,
        lerp(kn, hk, 0.45) + V3(0, 0, -0.08),
        hk + V3(0, 0.07, -0.07),
        0.03,
        0.024,
        k=0.03,
    )
    _ = m.sphere("calcaneus", mtar, hk + V3(0, 0.07, -0.068), 0.033, k=0.025)
    _ = ell_y(
        m,
        "hock",
        mtar,
        hk + V3(0, 0.01, -0.005),
        V3(0, 1, 0.25),
        V3(0.05, 0.075, 0.055),
        lateral=lat,
        k=0.03,
    )
    _ = m.cone(
        "cannon",
        mtar,
        hk + V3(0, -0.04, 0.005),
        mt + V3(0, 0.02, 0.0),
        0.036,
        0.033,
        k=0.02,
    )
    _ = m.cone(
        "tendon",
        mtar,
        hk + V3(0, -0.04, -0.035),
        mt + V3(0, 0.03, -0.035),
        0.022,
        0.026,
        k=0.02,
    )
    _ = ell_y(
        m,
        "fetlock",
        mtar,
        mt + V3(0, 0.0, -0.012),
        V3(0, 1, 0.3),
        V3(0.043, 0.05, 0.05),
        lateral=lat,
        k=0.02,
    )
    _ = m.sphere("ergot", hpaw, mt + V3(0, -0.02, -0.052), 0.018, k=0.018)
    _ = m.cone("pastern", hpaw, mt, ch, 0.035, 0.036, k=0.02)
    _hoof(m, rig.bone("hhoof" + side), ch, tt, 0.93)


def _t_at(i: Int, n: Int) -> Float64:
    return 0.03 + 0.94 * (Float64(i) + 0.5) / Float64(n)


def _crest_top(withers: V3, poll: V3, n_up: V3, t: Float64) -> V3:
    # A point on the arch of the crest, from the withers to the poll.
    return lerp(withers, poll, t) + n_up * (0.045 * sin(pi * t))


def _skin_x(m: SdfModel, ids: List[Int], side: Float64, q: V3) -> V3:
    # The neck's skin on the mane side at the height and depth of `q`.
    var lo = 0.0
    var hi = 0.45
    for _ in range(28):  # pragma: no branch
        var x = 0.5 * (lo + hi)
        var inside = m.eval_list(ids, V3(side * x, q.y, q.z)) < 0.0
        lo = x if inside else lo
        hi = hi if inside else x
    return V3(side * 0.5 * (lo + hi), q.y, q.z)


def _skin_y(m: SdfModel, ids: List[Int], z: Float64) -> Float64:
    # The forehead skin's head-local height on the midline at `z`.
    var hf = _hf()
    var lo = 0.0
    var hi = 0.2
    for _ in range(30):  # pragma: no branch
        var y = 0.5 * (lo + hi)
        var inside = m.eval_list(ids, hf.at(V3(0, y, z))) < 0.0
        lo = y if inside else lo
        hi = hi if inside else y
    return 0.5 * (lo + hi)


def _hair_r(i: Int, foal: Bool) -> Float64:
    # The tail hair's radius at joint `i`: a short fluffy brush on a foal.
    if foal:
        var brush: List[Float64] = [0.06, 0.068, 0.072, 0.07, 0.06, 0.045, 0.03]
        return brush[min(6, i)]
    var t = Float64(i) / Float64(TAIL_SEGS)
    if t < 0.55:
        return 0.066 + 0.018 * (t / 0.55)
    return 0.084 - 0.05 * ((t - 0.55) / 0.45) ** 1.5


def _hoof(mut m: SdfModel, bone: BoneId, c: V3, toe: V3, w: Float64) raises:
    # A truncated cone with its front wall parallel to the pastern, a
    # coronet band on top, the heel bulbs behind, and the sole cut flat.
    var base = V3(c.x, 0.0, (c.z + toe.z) * 0.5 - 0.012)
    var top = c + V3(0, 0.02, -0.012)
    _ = m.cone("hoof", bone, top, base, 0.045 * w, 0.064 * w, k=0.012)
    _ = m.cone(
        "coronet",
        bone,
        c + V3(0, 0.022, -0.018),
        c + V3(0, 0.008, 0.02),
        0.042 * w,
        0.042 * w,
        k=0.015,
    )
    _ = m.sphere("heelbulb", bone, c + V3(0, -0.028, -0.05), 0.03 * w, k=0.02)
    _ = m.ell(
        "sole",
        bone,
        V3(c.x, -0.2 + 0.002, base.z),
        V3(0.2, 0.2, 0.2),
        k=0.004,
        carve=True,
    )


def horse_look(t: Traits) -> EyeLook:
    """Return the horse's eye colors: a dark brown iris, a horizontal bar.

    Args:
        t: The individual. Every horse has the same eyes.

    Returns:
        The look.
    """
    return EyeLook(
        srgb(0x2A170C),
        srgb(0x5C3A20),
        srgb(0x1E1109),
        V3(0.55, 0.5, 0.45),
        0.3,
        -2.5,
    )


def _coat_hexes(coat: Int) -> List[Int]:
    # Body, dorsal, belly, head, points and mane, from reference photos.
    if coat == DARK_BAY:
        return [0x3E2418, 0x2E1B13, 0x5A3421, 0x3A2217, 0x141010, 0x100D0C]
    if coat == CHESTNUT:
        return [0x845231, 0x77492B, 0x93613A, 0x7D4D2E, 0x74452A, 0x70432A]
    if coat == BLACK:
        return [0x1F1B1A, 0x1A1716, 0x2A221E, 0x1F1B1A, 0x131010, 0x100E0D]
    if coat == GRAY:
        return [0x9A9893, 0x8E8C87, 0xB4B2AC, 0xA8A6A0, 0x5A5856, 0xCFCDC7]
    if coat == PALOMINO:
        return [0xD4A95A, 0xC99D50, 0xDCB46A, 0xCFA355, 0xC09450, 0xEFE3C2]
    if coat == DUN:
        return [0xB89A6A, 0xA98C5E, 0xC6AA7C, 0x7A6040, 0x1C1712, 0x16120F]
    if coat == BUCKSKIN:
        return [0xB98A4F, 0xAC7E46, 0xC49A60, 0xA87C45, 0x1A1410, 0x141110]
    return [0x6B3A1F, 0x57301A, 0x7A4527, 0x62351D, 0x17120F, 0x121010]


def horse_palette(t: Traits) raises -> Palette:
    """Return one horse's palette: its coat, shaded, and its landmarks.

    A gray whitens with age toward almost white, keeping darker legs and
    dapples. A chestnut can have a flaxen mane. The palette also keeps
    the nostrils and the left eye's aperture, which the painter reads.

    Args:
        t: The individual.

    Returns:
        The palette, in linear light.

    Raises:
        Error: If the sculpt of the head refuses a primitive.
    """
    var hex = _coat_hexes(t.variant)
    var k = t.get("coatShade", 0.0)
    var l = t.get("coatLightness", 0.0)
    var pal = Palette()
    var tinted: List[String] = [
        String("body"),
        "dorsal",
        "belly",
        "head",
    ]
    for i in range(4):  # pragma: no branch
        var c = srgb(hex[i])
        pal.set(
            tinted[i],
            V3(
                c.x * (1.0 + 0.08 * k + l),
                c.y * (1.0 + l),
                c.z * (1.0 - 0.08 * k + l),
            ),
        )
    pal.set("points", srgb(hex[4]))
    var flaxen = t.get("flaxen", 0.0) > 0.5
    pal.set("mane", srgb(0xCFB37E) if flaxen else srgb(hex[5]))
    if t.variant == GRAY:
        # Grays whiten with age: zero is dark dapple gray, one almost white.
        var g = t.get("grayLevel", 0.4)
        var lift = srgb(0xE4E2DC)
        var amounts: List[Float64] = [0.8, 0.75, 0.8, 0.85]
        for i in range(4):  # pragma: no branch
            pal.set(tinted[i], mix3(pal.get(tinted[i]), lift, g * amounts[i]))
        pal.set("points", mix3(pal.get("points"), lift, g * 0.6))
        pal.set("mane", mix3(pal.get("mane"), lift, g * 0.5))
        pal.set("dapple", mix3(srgb(0xC9C7C1), lift, g * 0.6))
    pal.set("white", srgb(0xF0ECE4))
    pal.set("pink", srgb(0xC9A09A))
    pal.set("muzzle", srgb(0x2C2A2A))
    pal.set("hoof", srgb(0x3A3029))
    pal.set("hoofPale", srgb(0xB8A88A))
    pal.set("mark", srgb(0x241F1D))
    # The landmarks: the left nostril, head-local, and the left eye.
    var head = SdfModel()
    _head(head, BoneId(0))
    var ids = List[Int]()
    # `_head` has just sculpted the head.
    for i in range(len(head.prims)):  # pragma: no branch
        ids.append(i)
    var no = _nostril(head, ids, 1.0)
    pal.set("nostril", no[0])
    pal.set("nostrilUp", no[1])
    var e = _eye()
    var ef = eye_frame_of(e, HEAD_O, 1.0)
    pal.set("eyeC", ef.c + ef.y * e.off)
    pal.set("eyeX", ef.x)
    pal.set("eyeY", ef.y)
    pal.set("eyeZ", ef.z)
    var hf = _hf()
    var base = hf.at(EAR_BASE)
    var up = normalize(hf.at(EAR_TIP) - base)
    var facing = normalize(hf.hz * 0.9 + V3(0.55, 0, 0))
    var lat = normalize(cross(up, facing))
    pal.set("earFace", normalize(cross(lat, up)))
    return pal^


def _face_white(t: Traits, h: V3, n: V3, hf: HeadFrame) -> Float64:
    # The white face marking as a signed distance, head-local: a star on
    # the forehead, a stripe down the face, a blaze, a snip on the muzzle.
    var ax = abs(h.x)
    var high = h.y > -0.07 + 0.12 * smoothstep(0.1, -0.1, h.z)
    var faces_front = dot(n, hf.hy) > -0.2
    var front = (faces_front and high) or h.z > 0.3
    if not front:
        return 1.0
    var face = Int(t.get("face", 0.0))
    var d = 1.0
    var star = face == STAR or face == STAR_SNIP or face == STRIPE
    if star:
        var q = ((ax / 0.028) ** 2 + ((h.z - 0.028) / 0.034) ** 2) ** 0.5
        d = min(d, q * 0.028 - 0.028)
    if face == STRIPE:
        d = min(
            d,
            max(
                ax - 0.014 - 0.006 * smoothstep(0.0, 0.3, h.z),
                max(-0.02 - h.z, h.z - 0.3),
            ),
        )
    if face == BLAZE:
        d = min(
            d,
            max(ax - (0.03 + 0.03 * smoothstep(0.15, 0.4, h.z)), -0.07 - h.z),
        )
    var snip = face == SNIP or face == STAR_SNIP
    if snip:
        var q = ((ax / 0.022) ** 2 + ((h.z - 0.36) / 0.035) ** 2) ** 0.5
        d = min(d, q * 0.022 - 0.022)
    return d


def _fur(c: V3, p: V3) -> V3:
    # Low-frequency color variation and a fine hair grain.
    var cv = fbm3(p * 5.0, 3) - 0.5
    var v = V3(
        c.x * (1.0 + 0.14 * cv), c.y * (1.0 + 0.12 * cv), c.z * (1.0 + 0.1 * cv)
    )
    return grizzle(v, p, 160.0, 0.05)


def _long_hair(c: V3, p: V3, comb: V3) -> V3:
    # Lock-to-lock shade streaks along long hair.
    var along = dot(p, comb)
    var q = p - comb * along
    var st = vnoise3(V3(q.x * 90.0, q.y * 90.0, q.z * 90.0 + along * 3.0))
    var lk = vnoise3(V3(q.x * 24.0 + 7.1, q.y * 24.0, q.z * 24.0 + along * 1.5))
    return c * ((0.75 + 0.5 * st) * (0.82 + 0.36 * lk))


def horse_paint(
    pal: Palette, t: Traits, tag: String, bone: String, s: CoatSample
) -> Paint:
    """Paint one vertex of a horse.

    The body is countershaded from the dorsal shade to a paler belly. Bays,
    duns and buckskins have black points: legs below the knees and hocks,
    mane, tail and ear rims. A dun has a dorsal stripe and faint leg bars,
    a gray rounded dapples. White face markings and socks lie over pink
    skin and pale hooves. The muzzle is dark soft skin, the hooves are
    keratin, and the mane and tail carry lock-to-lock streaks.

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
    var coat = t.variant
    var hf = _hf()
    var jag = (fbm3(p * 60.0, 2) - 0.5) * 0.02
    var black_points = (
        coat == BAY or coat == DARK_BAY or coat == DUN or coat == BUCKSKIN
    )
    var mane_hair = tag == "mane" or tag == "manecrest"
    if mane_hair:
        var side = t.get("maneSide", -1.0)
        return Paint(
            _long_hair(
                pal.get("mane"), p, normalize(V3(side * 0.35, -1, -0.2))
            ),
            FUR,
        )
    if tag == "forelock":
        return Paint(_long_hair(pal.get("mane"), p, hf.hz), FUR)
    if tag == "tailhair":
        return Paint(_long_hair(pal.get("mane"), p, V3(0, -1, 0)), FUR)
    if tag == "dock":
        var c = mix3(
            pal.get("body"),
            pal.get("mane"),
            0.6 + 0.4 * smoothstep(-0.2, 0.6, n.y),
        )
        return Paint(_fur(c, p), FUR)
    if bone.startswith("ear"):
        # Coat color, dark rims and tips on bays, hairy inside.
        var sd = 1.0 if bone == "earL" else -1.0
        var front = dot(V3(n.x * sd, n.y, n.z), pal.get("earFace"))
        var c = pal.get("head")
        if black_points:
            c = mix3(c, pal.get("points"), 0.5)
        if front > 0.3:
            c = mix3(c, srgb(0xB0A090), 0.25)
        return Paint(_fur(c, p), FUR)
    var on_head = bone == "head" or bone == "jaw"
    if on_head:
        return _paint_head(pal, t, s, black_points)
    return _paint_body(pal, t, tag, bone, s, black_points, jag)


def _paint_head(
    pal: Palette, t: Traits, s: CoatSample, black_points: Bool
) -> Paint:
    var p = s.p
    var hf = _hf()
    var h = hf.local(p)
    var jag = (fbm3(p * 60.0, 2) - 0.5) * 0.02
    var wsdf = _face_white(t, h, s.n, hf) + jag
    var white = wsdf < 0.0 and t.variant != GRAY
    var c = pal.get("head")
    # The dark soft muzzle skin, pink under a white snip or blaze.
    var muz = smoothstep(0.25, 0.36, h.z)
    c = mix3(c, pal.get("pink") if white else pal.get("muzzle"), muz * 0.75)
    var dark_muzzle = black_points and h.z > 0.25
    if dark_muzzle:
        c = mix3(c, pal.get("points"), smoothstep(0.25, 0.32, h.z) * 0.6)
    if h.z < -0.13:
        c = mix3(c, pal.get("body"), smoothstep(-0.13, -0.2, h.z))
    # The eye rims: bare dark skin round the aperture.
    var pm = V3(abs(p.x), p.y, p.z)
    var ec = pal.get("eyeC")
    var de = lens_distance(
        pm, ec, pal.get("eyeX"), pal.get("eyeY"), 0.0262, 0.0133
    )
    var near_eye = (
        length(pm - ec) < 0.05 and dot(pm - ec, pal.get("eyeZ")) > -0.01
    )
    var lid = near_eye and abs(de) < 0.0024
    if lid:
        return Paint(pal.get("muzzle"), SKIN)
    var rim = near_eye and abs(de) < 0.006
    if rim:
        c = mix3(c, pal.get("mark"), 0.6)
    # The nostrils: a dark, moist lining.
    var hm = V3(abs(h.x), h.y, h.z)
    var n_l = normalize(V3(0.6, 0.05, 0.8))
    var low = pal.get("nostril")
    var up = pal.get("nostrilUp")
    var dn = min(
        oriented_ellipsoid_estimate(
            hm, low - n_l * 0.011, n_l, up, V3(0.013, 0.017, 0.028)
        ),
        oriented_ellipsoid_estimate(
            hm,
            low + up * 0.022 - n_l * 0.012,
            n_l,
            up,
            V3(0.0085, 0.014, 0.024),
        ),
    )
    if dn < 0.004:
        return Paint(pal.get("muzzle") * 0.6, SKIN)
    if white:
        var w = mix3(pal.get("white"), pal.get("pink"), muz * 0.6)
        c = mix3(c, w, smoothstep(0.003, -0.003, wsdf))
    return Paint(_fur(c, p), FUR)


def _paint_body(
    pal: Palette,
    t: Traits,
    tag: String,
    bone: String,
    s: CoatSample,
    black_points: Bool,
    jag: Float64,
) -> Paint:
    var p = s.p
    var n = s.n
    var coat = t.variant
    var neck = bone == "neck1" or bone == "neck2"
    var leg = 1.0 if is_limb(bone) else 0.0
    var front = is_front_limb(bone)
    var up = clamp(n.y, -1.0, 1.0)
    var side = 1.0 if p.x >= 0.0 else -1.0
    var ventral = (
        smoothstep(0.0, -0.7, n.y)
        * 0.5 if neck else smoothstep(-0.2, -0.8, n.y)
        * smoothstep(1.25, 1.0, p.y)
    )
    ventral = mix(
        ventral,
        smoothstep(0.1, -0.7, n.x * side) * 0.6 * smoothstep(0.5, 0.9, p.y),
        leg,
    )
    var c = mix3(
        pal.get("body"), pal.get("dorsal"), smoothstep(0.3, 0.95, up) * 0.8
    )
    c = mix3(c, pal.get("belly"), ventral)
    var stripe_here = coat == DUN and not neck
    if stripe_here:
        # The dun's dorsal stripe from the mane to the tail.
        var stripe = (
            abs(p.x)
            - 0.022
            - 0.01 * smoothstep(0.3, -0.6, p.z)
            + (1.0 - smoothstep(0.85, 0.97, up)) * 0.1
        )
        c = mix3(c, pal.get("points"), smoothstep(0.004, -0.004, stripe) * 0.85)
    var wsdf = 1.0
    if leg > 0.0:
        # Black points below the knees and hocks.
        var knee = 0.52 if front else 0.6
        if black_points:
            var wob = (
                fbm3(V3(p.x * 20.0, p.y * 8.0, p.z * 20.0), 2) - 0.5
            ) * 0.12
            c = mix3(
                c,
                pal.get("points"),
                smoothstep(knee + 0.18, knee - 0.02, p.y + wob),
            )
        if coat == GRAY:
            c = mix3(c, pal.get("points"), smoothstep(0.6, 0.2, p.y) * 0.8)
        var bars = coat == DUN and p.y > 0.5 and p.y < 0.95
        if bars:
            # The dun's faint zebra bars on the forearms and gaskins.
            var bar = sin(p.y * 70.0)
            c = mix3(
                c,
                pal.get("points"),
                0.22
                * smoothstep(0.82, 0.95, bar)
                * smoothstep(0.95, 0.75, p.y),
            )
        # The socks: white up to a seeded height, with a ragged edge.
        var index = (0 if front else 2) + (0 if bone.endswith("L") else 1)
        var sock = t.get("sock" + String(index), 0.0)
        if sock > 0.0:
            wsdf = p.y - sock + jag * 1.5
        # The chestnuts: horny callosities inside the forearm above the
        # knee and inside the hind cannon below the hock.
        var inner = n.x * side < -0.6
        var cy = 0.62 if bone.startswith("radius") else (
            0.46 if bone.startswith("metatarsus") else -1.0
        )
        var cz = 0.63 if front else -0.61
        var on_nut = (
            inner
            and cy > 0.0
            and ((p.y - cy) / 0.024) ** 2 + ((p.z - cz) / 0.014) ** 2 < 1.0
        )
        if on_nut:
            return Paint(srgb(0x3A302A), KERATIN)
        # The hoof wall below the coronet line, higher at the toe.
        var coffin = FCOFFIN if front else HCOFFIN
        var on_hoof = tag == "hoof" or tag == "heelbulb"
        var wall = on_hoof and p.y < coffin.y + 0.012 + 0.45 * (p.z - coffin.z)
        if wall:
            var hc = pal.get("hoofPale") if wsdf < 0.0 else pal.get("hoof")
            if tag == "heelbulb":
                hc = mix3(hc, pal.get("muzzle"), 0.5)
            return Paint(hc, KERATIN)
    var body = not neck and leg < 0.6
    var dapples = coat == GRAY and ventral < 0.7 and (body or neck)
    if dapples:
        # Light rounded dapples, the darker coat a network between them.
        var cell = cells3(p * 11.0, Int(t.get("coatSeed", 0.0)) % 997)
        var wob = 0.14 * (vnoise3(p * 40.0) - 0.5)
        var weight = 0.75 * (1.0 - leg) * (1.0 - ventral)
        c = mix3(
            c * (1.0 - 0.12 * weight),
            pal.get("dapple"),
            smoothstep(0.5, 0.25, cell.nearest + wob) * weight,
        )
    var white = wsdf < 0.0 and coat != GRAY
    if white:
        c = mix3(c, pal.get("white"), smoothstep(0.003, -0.003, wsdf))
    return Paint(_fur(c, p), FUR)
