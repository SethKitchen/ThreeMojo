# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Domestic cattle, Bos taurus: procedural-animals' `species/cow/`.

The reference adult is a Holstein-Friesian cow, 1.45 m at the withers.
Each foot is cloven: two claws and two dew claws on one hoof bone. The
barrel is big, with prominent hooks and pins, a dewlap, and an udder or
a bull's crest. The breeds are Holstein-Friesian (black and white
piebald patches grown per individual), Hereford (red with a white face),
Angus (black, polled), Jersey (fawn, dark face, dished) and Highland
(shaggy, with long horns).
"""

from extensions.animals.coat import (
    FUR,
    KERATIN,
    SKIN,
    WET,
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
    TONGUE,
    WATTLE,
)
from extensions.sdf.sculpt import ell_y
from extensions.animals.kit import (
    EyeSpec,
    eye_frame_of,
    sculpt_eye_socket,
)
from extensions.animals.noise import fbm3, vnoise3
from extensions.animals.options import (
    FEMALE,
    MALE,
    AnimalOptions,
    AnimalRandom,
)
from extensions.animals.rig import Rig, tail_chain
from extensions.sdf.field import SdfModel
from extensions.animals.species.ungulate import (
    HeadFrame,
    aperture_tilt_along,
    eye_looking,
    head_ell,
    hoofed_bones,
    is_front_limb,
    is_limb,
    lens_distance,
    pick_weighted,
    pitched_head,
)
from extensions.animals.traits import Traits, pick_age
from extensions.sdf.vector import (
    V3,
    clamp,
    cross,
    dot,
    frame_zy,
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
from std.math import cos, pi, sin

# Ten caudal segments to the hocks, and two of switch hair.
comptime TAIL_SEGS = 12
comptime BONE_SEGS = 10
# The head's origin: on its axis 0.17 m in front of the poll, level with
# the eyes. The head is pitched 50 degrees nose down in the bind pose.
comptime HEAD_O = V3(0.0, 1.3297724446697736, 1.2392738936467116)
# The finest cell, at the `HERO` tier: the head's cell in the original.
comptime CELL = 0.0052

# The breeds, in procedural-animals' order.
comptime HOLSTEIN = 0
comptime HEREFORD = 1
comptime ANGUS = 2
comptime JERSEY = 3
comptime HIGHLAND = 4

# The coats within the breeds.
comptime C_HOLSTEIN = 0
comptime C_RED_HOLSTEIN = 1
comptime C_HEREFORD = 2
comptime C_ANGUS = 3
comptime C_RED_ANGUS = 4
comptime C_JERSEY = 5
comptime C_HIGHLAND = 6
comptime C_HIGHLAND_BLACK = 7
comptime C_HIGHLAND_DUN = 8

# The horn styles.
comptime NO_HORNS = 0
comptime LYRE = 1
comptime DOWN = 2
comptime BULL = 3
comptime WIDE = 4

# The Holstein face markings.
comptime F_BLAZE = 0
comptime F_STAR = 1
comptime F_WHITE = 2
comptime F_STRIP = 3
comptime F_NONE = 4

comptime FCOFFIN = V3(0.15, 0.052, 0.705)
comptime HCOFFIN = V3(0.17, 0.052, -0.61)


def _hf() -> HeadFrame:
    return pitched_head(V3(0.0, 1.46, 1.13), 50.0, 0.17)


def cow_variant_names() -> List[String]:
    """Return the cattle breeds.

    Returns:
        Holstein, Hereford, Angus, Jersey and Highland.
    """
    return [String("holstein"), "hereford", "angus", "jersey", "highland"]


def _breed(variant: Int) -> List[Float64]:
    # Withers heights of cows and bulls, dairy, udder range, dewlap, the
    # share with ear tags, and the leg, girth and length factors.
    if variant == HEREFORD:
        return [1.34, 1.5, 0.0, 0.3, 0.45, 0.85, 0.5, 0.9, 1.08, 0.97]
    if variant == ANGUS:
        return [1.3, 1.45, 0.0, 0.3, 0.45, 0.45, 0.5, 0.89, 1.08, 0.96]
    if variant == JERSEY:
        return [1.2, 1.4, 1.0, 0.7, 0.95, 0.35, 0.7, 1.0, 0.94, 0.98]
    if variant == HIGHLAND:
        return [1.12, 1.25, 0.2, 0.25, 0.35, 0.3, 0.25, 0.84, 1.06, 0.95]
    return [1.45, 1.63, 1.0, 0.8, 1.15, 0.35, 0.7, 1.0, 1.0, 1.0]


def cow_traits(mut r: AnimalRandom, options: AnimalOptions) raises -> Traits:
    """Draw one head of cattle: procedural-animals' `variation`.

    The breed is the requested one, a Holstein by default. Seven in ten
    are cows. A bull has a crest, larger horns and a sheath, and some
    bulls wear a nose ring. A calf has long legs, a short body, a big
    head and no horns. Horns, the face marking, the piebald cover, the
    udder, the dewlap and the ear tags vary by breed.

    Args:
        r: The individual's stream.
        options: The caller's sex, age and breed.

    Returns:
        The traits.

    Raises:
        Error: If the requested breed is not one of the five.
    """
    if options.variant.value >= 5:
        raise Error("Cattle have no such breed")
    var variant = options.variant.value if options.variant.value >= 0 else 0
    var b = _breed(variant)
    var sex = options.sex
    var asked = sex == MALE or sex == FEMALE
    if not asked:
        sex = FEMALE if r.next() < 0.7 else MALE
    var t = Traits(sex, pick_age(options.age), variant)
    var calf = t.juvenile() > 0.0
    var male = t.male()
    var bull = 0.0
    if male:
        bull = 0.25 if calf else 0.85 + 0.15 * r.next()
    var frame = r.g()
    t.set(
        "size",
        (b[1] if male else b[0])
        / 1.45
        * (1.0 + 0.035 * frame)
        * (0.5 if calf else 1.0),
    )
    var coat: Int
    if variant == HOLSTEIN:
        coat = C_RED_HOLSTEIN if r.next() < 0.12 else C_HOLSTEIN
    elif variant == HEREFORD:
        coat = C_HEREFORD
    elif variant == ANGUS:
        coat = C_RED_ANGUS if r.next() < 0.15 else C_ANGUS
    elif variant == JERSEY:
        coat = C_JERSEY
    else:
        var shades: List[Float64] = [60.0, 20.0, 20.0]
        coat = C_HIGHLAND + pick_weighted(r, shades)
    t.set("coat", Float64(coat))
    # The horns: [style, length, radius, first angle, last angle, curl].
    var hr = r.next()
    var horns: List[Float64] = [0.0, 0.0, 0.0, 0.0, 0.0, 1.3]
    if not calf:
        horns = _horns(r, variant, male, hr)
    var names: List[String] = [
        String("hornStyle"),
        "hornLen",
        "hornR",
        "hornA0",
        "hornA1",
        "hornCurl",
    ]
    for i in range(6):
        t.set(names[i], horns[i])
    var face = F_NONE
    if variant == HOLSTEIN:
        var faces: List[Float64] = [45.0, 12.0, 15.0, 15.0, 13.0]
        face = pick_weighted(r, faces)
    t.set("face", Float64(face))
    t.set("bull", bull)
    t.set("dairy", b[2])
    var udder = 0.0
    var no_udder = male or calf
    if not no_udder:
        udder = b[3] + (b[4] - b[3]) * r.next()
    t.set("udder", udder)
    t.set("dewlap", b[5] * (1.4 if male else 1.0) * (0.8 + 0.4 * r.next()))
    var peak = 0.0
    if variant == ANGUS:
        peak = 0.6 + 0.4 * r.next()
    t.set("polledPeak", peak)
    t.set("dished", 1.0 if variant == JERSEY else 0.0)
    t.set("shaggy", 1.0 if variant == HIGHLAND else 0.0)
    t.set("earTags", 1.0 if r.next() < (0.85 if calf else b[6]) else 0.0)
    var ring = False
    var may_ring = male and not calf and variant != HIGHLAND
    if may_ring:
        ring = r.next() < 0.5
    t.set("noseRing", 1.0 if ring else 0.0)
    t.set("faceWidth", 0.7 + 0.7 * r.next())
    t.set("blackCover", 0.55 + 0.22 * r.g())
    t.set("patchFreq", 2.1 + 0.7 * r.next())
    var spectacles = False
    if variant == HEREFORD:
        spectacles = r.next() < 0.25
    t.set("spectacles", 1.0 if spectacles else 0.0)
    t.set("switchLen", 0.8 + 0.3 * r.next())
    t.set("coatShade", r.g())
    t.set("coatLightness", 0.06 * r.g())
    t.set("coatSeed", Float64(Int(r.next() * 1e6)))
    t.set("minThick", 0.006)
    var grown_bull = male and not calf
    t.warps.add(
        legs_warp(b[7] * (1.0 + 0.03 * r.g()) * (1.42 if calf else 1.0), 0.72)
    )
    t.warps.add(
        length_warp(
            b[9] * (1.0 + 0.025 * r.g()) * (0.84 if calf else 1.0), -0.7, 0.62
        )
    )
    t.warps.add(
        girth_warp(
            b[8]
            * (1.0 + 0.04 * r.g())
            * (1.04 if grown_bull else 1.0)
            * (0.9 if calf else 1.0),
            1.05,
            -0.85,
            0.75,
        )
    )
    t.warps.add(
        scale_about_warp(
            HEAD_O,
            (1.0 + 0.03 * r.g())
            * (1.3 if calf else 1.0)
            * (1.06 if grown_bull else 1.0)
            * (0.95 if variant == JERSEY else 1.0),
            0.22,
            0.42,
        )
    )
    return t^


def _horns(
    mut r: AnimalRandom, variant: Int, male: Bool, hr: Float64
) -> List[Float64]:
    # Most Holsteins are disbudded, Angus are polled, Herefords grow
    # forward-down horns and Highlanders wide ones.
    var none: List[Float64] = [0.0, 0.0, 0.0, 0.0, 0.0, 1.3]
    if variant == HOLSTEIN:
        if hr >= (0.5 if male else 0.15):
            return none^
        if male:
            return [Float64(BULL), 0.17 + 0.07 * r.next(), 0.042, 12, 60, 1.3]
        return [Float64(LYRE), 0.24 + 0.08 * r.next(), 0.027, 10, 100, 1.3]
    if variant == HEREFORD:
        if hr >= 0.5:
            return none^
        if male:
            return [Float64(DOWN), 0.2 + 0.05 * r.next(), 0.045, 8, 70, 1.3]
        return [Float64(DOWN), 0.26 + 0.07 * r.next(), 0.03, 6, 85, 1.3]
    if variant == JERSEY:
        if hr >= (0.4 if male else 0.2):
            return none^
        if male:
            return [Float64(BULL), 0.16 + 0.05 * r.next(), 0.036, 12, 65, 1.3]
        return [Float64(LYRE), 0.2 + 0.06 * r.next(), 0.023, 10, 105, 1.3]
    if variant == HIGHLAND:
        if male:
            return [Float64(WIDE), 0.4 + 0.08 * r.next(), 0.055, 4, 55, 1.6]
        return [Float64(WIDE), 0.52 + 0.14 * r.next(), 0.04, 4, 85, 1.5]
    return none^


def cow_eye(t: Traits) -> EyeSpec:
    """Return the cow's left eye: set at the edge of the broad forehead.

    The globe is about 34 mm. The eye looks out, 18 degrees forward along
    the nasal line and a little up. In the relaxed carriage its slit is
    about level.

    Args:
        t: The individual. Every cow has the same eye.

    Returns:
        The eye, head-local.
    """
    return _eye()


def _eye() -> EyeSpec:
    var hf = _hf()
    var a = 18.0 * pi / 180.0
    var look = normalize(V3(cos(a), 0.0, 0.0) + hf.hz * sin(a) + hf.hy * 0.12)
    var e = eye_looking(
        hf,
        V3(0.111, 0.004, 0.0),
        look,
        0.02,
        0.004,
        0.0024,
        0.0215,
        0.0094,
        -0.0008,
        0.011,
        0.0146,
    )
    e.tilt = aperture_tilt_along(e, HEAD_O, hf.hz) - 0.85
    return e


def cow_rig(t: Traits) raises -> Rig:
    """Return the cow's skeleton in bind pose.

    Landmarks are from a Holstein-Friesian cow: point of shoulder 1.00 m,
    elbow 0.72, carpus 0.40, fetlock 0.13, stifle 0.80 and hock 0.53. A
    tongue bone rides the jaw. The tail hangs straight down to the hocks.

    Args:
        t: The individual. Every cow has the same reference rig.

    Returns:
        The rig.

    Raises:
        Error: If a bone names a missing joint.
    """
    var hf = _hf()
    var rig = Rig()
    rig.set("nose", hf.at(V3(0, -0.01, 0.37)))
    rig.set("occiput", hf.at(V3(0, -0.035, -0.14)))
    rig.set("neckMid", V3(0, 1.3, 0.9))
    rig.set("neckBase", V3(0, 1.2, 0.64))
    rig.set("chestMid", V3(0, 1.3, 0.34))
    rig.set("thoraxRear", V3(0, 1.33, 0.0))
    rig.set("lumbarMid", V3(0, 1.355, -0.27))
    rig.set("lumbosacral", V3(0, 1.37, -0.5))
    rig.set("tailBase", V3(0, 1.37, -0.88))
    rig.set("scapTopL", V3(0.12, 1.36, 0.42))
    rig.set("shoulderL", V3(0.19, 1.0, 0.74))
    rig.set("elbowL", V3(0.18, 0.72, 0.58))
    rig.set("wristL", V3(0.155, 0.4, 0.63))
    rig.set("mcpL", V3(0.15, 0.13, 0.65))
    rig.set("fcoffinL", FCOFFIN)
    rig.set("ftoeL", V3(0.15, 0.004, 0.785))
    rig.set("hipL", V3(0.2, 1.2, -0.6))
    rig.set("kneeL", V3(0.235, 0.8, -0.4))
    rig.set("hockL", V3(0.17, 0.53, -0.71))
    rig.set("mtpL", V3(0.17, 0.13, -0.665))
    rig.set("hcoffinL", HCOFFIN)
    rig.set("htoeL", V3(0.17, 0.004, -0.53))
    rig.set("jawHinge", hf.at(V3(0, -0.065, -0.075)))
    rig.set("jawTip", hf.at(V3(0, -0.118, 0.335)))
    rig.set("tongueBase", hf.at(V3(0, -0.085, 0.12)))
    rig.set("tongueTip", hf.at(V3(0, -0.09, 0.3)))
    # The ears stick out sideways below the poll, tipped down and back.
    var ear = hf.at(V3(0.085, 0.01, -0.125))
    rig.set("earBaseL", ear)
    rig.set("earTipL", ear + V3(0.2, -0.025, -0.045))
    var pitch: List[Float64] = [
        -38,
        -68,
        -80,
        -85,
        -87,
        -88,
        -89,
        -89,
        -90,
        -90,
        -90,
        -90,
    ]
    var lens: List[Float64] = [
        0.075,
        0.072,
        0.07,
        0.068,
        0.066,
        0.064,
        0.062,
        0.06,
        0.058,
        0.056,
        0.16,
        0.16,
    ]
    tail_chain(rig, "tailBase", pitch, lens)
    rig.mirror_joints()
    hoofed_bones(rig, TAIL_SEGS)
    _ = rig.add_bone("tongue", "tongueBase", "tongueTip", "jaw")
    return rig^


def _sx(v: V3, s: Float64) -> V3:
    return V3(v.x * s, v.y, v.z)


def _horn_radii(t: Traits) -> List[Float64]:
    # The horn's radius at each point of its center line.
    var hr = t.get("hornR", 0.0)
    var rads: List[Float64] = [hr * 1.05]
    for i in range(1, 8):
        var v = Float64(i) / 7.0
        rads.append(max(0.004, hr * (1.0 - 0.86 * v**1.25)))
    return rads^


def _horn_points(t: Traits, s: Float64) -> List[V3]:
    # The horn's center line, from inside the skull to the tip. It curls
    # from out toward its style's second direction: up and forward (lyre),
    # forward and down, short and forward (bull), or out and then up
    # (wide).
    var hf = _hf()
    var style = Int(t.get("hornStyle", 0.0))
    var ln = t.get("hornLen", 0.0)
    var base = hf.at(V3(0.082 * s, 0.035, -0.158))
    var out_dir = V3(s, 0, 0)
    var tw = normalize(V3(0, 0.8, 0.55))
    if style == DOWN:
        tw = normalize(V3(0, -0.55, 0.85))
    elif style == BULL:
        tw = normalize(V3(0, 0.35, 0.95))
    elif style == WIDE:
        tw = normalize(V3(0, 0.95, 0.3))
    var a0 = t.get("hornA0", 12.0) * pi / 180.0
    var a1 = t.get("hornA1", 95.0) * pi / 180.0
    var curl = t.get("hornCurl", 1.3)
    var n = 7
    var pts = List[V3]()
    var p = base + out_dir * -0.03
    pts.append(p)
    for i in range(1, n + 1):
        var u = (Float64(i) - 0.5) / Float64(n)
        var a = a0 + (a1 - a0) * u**curl
        var d = normalize(out_dir * cos(a) + tw * sin(a))
        p = p + d * ((ln + 0.03) / Float64(n))
        pts.append(p)
    return pts^


def cow_sculpt(mut m: SdfModel, rig: Rig, t: Traits) raises:
    """Sculpt the cow: procedural-animals' `sculptCow`, primitive for
    primitive.

    Args:
        m: The sculpt to add to.
        rig: The cow's rig in bind pose.
        t: The individual.

    Raises:
        Error: If the rig lacks a joint or a bone, or the sculpt refuses
            a primitive.
    """
    var calf = t.juvenile() > 0.0
    var dairy = t.get("dairy", 1.0)
    var bull = t.get("bull", 0.0)
    var beef = 1.0 - dairy
    var hf = _hf()

    # TORSO: a deep, wide barrel, deepest behind the ribs. The dairy wedge
    # gets deeper and wider toward the rear.
    var wb = 1.0 + 0.06 * beef + 0.04 * bull
    _ = m.ell(
        "ribcage",
        rig.bone("spine3"),
        V3(0, 1.04, 0.12),
        V3(0.3 * wb, 0.4, 0.56),
        axis=normalize(V3(0, 0.04, 1)),
        k=0,
    )
    var cb = rig.bone("chest")
    var s2 = rig.bone("spine2")
    var s1 = rig.bone("spine1")
    var pb = rig.bone("pelvis")
    _ = m.ell("girth", cb, V3(0, 1.02, 0.44), V3(0.25 * wb, 0.33, 0.24), k=0.1)
    _ = m.ell(
        "abdomen",
        s2,
        V3(0, 1.0, -0.22),
        V3(0.33 * wb, 0.37, 0.36),
        axis=normalize(V3(0, 0.1, -1)),
        k=0.12,
    )
    _ = m.ell("belly", s2, V3(0, 0.84, -0.08), V3(0.27 * wb, 0.2, 0.42), k=0.16)
    _ = m.ell(
        "flank", s1, V3(0, 1.17, -0.45), V3(0.28 * wb, 0.24, 0.24), k=0.12
    )
    # The withers: sharper in dairy cows.
    _ = m.ell(
        "withers",
        cb,
        V3(0, 1.36, 0.4),
        V3(0.085 + 0.03 * beef, 0.1, 0.24),
        axis=normalize(V3(0, -0.12, 1)),
        k=0.1,
    )
    _ = m.ell(
        "back",
        rig.bone("spine3"),
        V3(0, 1.35, 0.04),
        V3(0.17 + 0.05 * beef, 0.08, 0.42),
        k=0.12,
    )
    _ = m.ell(
        "loin",
        s1,
        V3(0, 1.38, -0.28),
        V3(0.21 + 0.04 * beef, 0.07, 0.24),
        k=0.12,
    )
    # The rump runs level from the hooks to the pins.
    _ = m.ell("pelvis", pb, V3(0, 1.25, -0.68), V3(0.25 * wb, 0.2, 0.28), k=0.1)
    _ = m.ell(
        "rump",
        pb,
        V3(0, 1.38, -0.67),
        V3(0.2 + 0.05 * beef, 0.08, 0.28),
        axis=normalize(V3(0, -0.06, 1)),
        k=0.1,
    )
    for s in [1.0, -1.0]:
        _ = m.sphere(
            "hook",
            pb,
            V3(0.27 * s, 1.37 + 0.012 * dairy, -0.46),
            0.055,
            k=0.07 + 0.04 * beef,
        )
        _ = m.sphere(
            "pin", pb, V3(0.095 * s, 1.34, -0.915), 0.05, k=0.07 + 0.03 * beef
        )
        # The quarters: full and round in beef breeds.
        _ = m.ell(
            "quarter",
            pb,
            V3(0.14 * s, 1.2, -0.78),
            V3(0.13 + 0.03 * beef, 0.2, 0.14 + 0.02 * beef),
            k=0.1,
        )
    _ = m.ell("tailhead", pb, V3(0, 1.39, -0.86), V3(0.06, 0.055, 0.08), k=0.06)
    # The brisket between and in front of the forelegs.
    _ = m.ell("brisket", cb, V3(0, 0.83, 0.6), V3(0.17 * wb, 0.17, 0.17), k=0.1)
    for s in [1.0, -1.0]:
        _ = m.ell(
            "pectoral", cb, V3(0.1 * s, 0.86, 0.7), V3(0.1, 0.15, 0.1), k=0.08
        )
    var udder = t.get("udder", 1.0)
    var has_udder = not calf and bull < 0.5 and udder > 0.05
    if has_udder:
        _udder(m, rig, udder)
    if bull >= 0.5:
        # The sheath under the belly, the scrotum between the hind legs.
        _ = m.ell(
            "sheath",
            s2,
            V3(0, 0.66, -0.05),
            V3(0.045, 0.06, 0.14),
            axis=normalize(V3(0, 0.35, 1)),
            k=0.06,
        )
        _ = m.ell("sheath", s2, V3(0, 0.6, 0.08), V3(0.03, 0.04, 0.05), k=0.04)
        if not calf:
            _ = m.ell(
                "scrotum",
                pb,
                V3(0, 0.66, -0.66),
                V3(0.075, 0.13, 0.08),
                axis=normalize(V3(0, 0.1, 1)),
                k=0.05,
            )

    # NECK: thin and long in dairy cows, short and thick in beef breeds,
    # massive with a crest in bulls.
    var nd1 = normalize(rig.j("neckMid") - rig.j("neckBase"))
    var nd2 = normalize(rig.j("occiput") - rig.j("neckMid"))
    var nk = 1.0 + 0.1 * beef + 0.45 * bull
    var n1 = rig.bone("neck1")
    var n2 = rig.bone("neck2")
    _ = m.ell(
        "neck",
        n1,
        V3(0, 1.16 + 0.03 * bull, 0.64),
        V3(0.2 * nk, 0.27 * (1.0 + 0.15 * bull), 0.24),
        axis=nd1,
        up=V3(0, 1, -0.3),
        k=0.12,
    )
    _ = m.ell(
        "neck",
        n1,
        V3(0, 1.25, 0.84),
        V3(0.14 * nk, 0.21 * (1.0 + 0.1 * bull), 0.2),
        axis=nd1,
        up=V3(0, 1, -0.3),
        k=0.1,
    )
    _ = m.ell(
        "neck",
        n2,
        V3(0, 1.31, 1.0),
        V3(0.11 * (1.0 + 0.15 * bull), 0.16, 0.14),
        axis=nd2,
        up=V3(0, 1, -0.2),
        k=0.09,
    )
    # The top of the neck; the bull's crest rises over the shoulders.
    _ = m.ell(
        "crest",
        n1,
        V3(0, 1.37 + 0.07 * bull, 0.72),
        V3(0.08 + 0.12 * bull, 0.07 + 0.11 * bull, 0.3 + 0.04 * bull),
        axis=normalize(V3(0, 0.02, 1)),
        k=0.1 + 0.04 * bull,
    )
    _ = m.ell(
        "crest",
        n2,
        V3(0, 1.41 + 0.02 * bull, 0.98),
        V3(0.06 + 0.04 * bull, 0.05 + 0.03 * bull, 0.14),
        k=0.08,
    )
    if bull > 0.0:
        _ = m.ell(
            "crest",
            cb,
            V3(0, 1.37 + 0.03 * bull, 0.5),
            V3(0.2 * bull + 0.02, 0.13 * bull + 0.01, 0.28),
            k=0.14,
        )
    # The underline: the trachea, then the dewlap, a hanging fold of skin
    # from the throat to the brisket.
    _ = m.cone(
        "throat", n1, V3(0, 1.02, 0.76), V3(0, 1.16, 0.98), 0.09, 0.075, k=0.1
    )
    _ = m.cone(
        "throat",
        n2,
        V3(0, 1.15, 0.98),
        hf.at(V3(0, -0.16, -0.06)),
        0.07,
        0.06,
        k=0.08,
    )
    var dw = t.get("dewlap", 0.5)
    if dw > 0.02:
        var a = V3(0, 0.99, 0.95)
        var b = V3(0, 0.76, 0.66)
        _ = m.ell(
            "dewlap",
            n1,
            lerp(a, b, 0.55) + V3(0, -0.04 * dw, 0.02 * dw),
            V3(0.035 + 0.015 * dw, 0.07 + 0.08 * dw, 0.2),
            axis=normalize(b - a),
            up=normalize(V3(0, 1, 0.9)),
            k=0.07,
        )

    # HEAD, in head-local coordinates.
    var h = rig.bone("head")
    var hb = 1.0 + 0.08 * bull
    _ = head_ell(
        m,
        "poll",
        h,
        hf,
        V3(0, 0.015, -0.14),
        V3(0.095 * hb, 0.055, 0.055),
        k=0.05,
    )
    _ = head_ell(
        m,
        "cranium",
        h,
        hf,
        V3(0, 0.0, -0.06),
        V3(0.1 * hb, 0.075, 0.11),
        k=0.05,
    )
    _ = head_ell(
        m,
        "forehead",
        h,
        hf,
        V3(0, 0.035, 0.0),
        V3(0.104 * hb, 0.04, 0.12),
        k=0.04,
    )
    _ = head_ell(
        m, "face", h, hf, V3(0, 0.01, 0.2), V3(0.08 * hb, 0.045, 0.19), k=0.05
    )
    _ = head_ell(
        m,
        "lowerface",
        h,
        hf,
        V3(0, -0.07, 0.18),
        V3(0.078 * hb, 0.08, 0.17),
        k=0.05,
    )
    _ = head_ell(
        m,
        "muzzle",
        h,
        hf,
        V3(0, -0.04, 0.33),
        V3(0.086 * hb, 0.066, 0.064),
        k=0.05,
    )
    _ = head_ell(
        m,
        "upperlip",
        h,
        hf,
        V3(0, -0.1, 0.345),
        V3(0.068 * hb, 0.032, 0.046),
        k=0.03,
    )
    var peak = t.get("polledPeak", 0.0)
    if peak > 0.0:
        _ = head_ell(
            m,
            "polltop",
            h,
            hf,
            V3(0, 0.05, -0.15),
            V3(0.04, 0.035 + 0.01 * peak, 0.04),
            k=0.04,
        )
    if bull > 0.0:
        # The bull's curly forehead mat.
        _ = head_ell(
            m,
            "forehead",
            h,
            hf,
            V3(0, 0.045, -0.06),
            V3(0.09, 0.03 * bull + 0.01, 0.1),
            k=0.05,
        )
    if t.get("dished", 0.0) > 0.0:
        _ = head_ell(
            m,
            "face",
            h,
            hf,
            V3(0, 0.035, 0.1),
            V3(0.05, 0.02, 0.05),
            k=0.03,
            carve=True,
        )
    var eye = _eye()
    for side in [String("L"), String("R")]:
        var s = 1.0 if side == "L" else -1.0
        # The masseter, and the mandible's lower border to the chin.
        _ = head_ell(
            m,
            "cheek",
            h,
            hf,
            V3(0.06 * s * hb, -0.105, -0.0),
            V3(0.048, 0.1, 0.11),
            k=0.05,
        )
        _ = m.cone(
            "mandible",
            h,
            hf.at(V3(0.052 * s, -0.19, -0.04)),
            hf.at(V3(0.036 * s, -0.135, 0.27)),
            0.036,
            0.024,
            k=0.05,
        )
        # The bony eye arch stands out of the forehead's outline.
        _ = head_ell(
            m,
            "brow",
            h,
            hf,
            V3(0.1 * s, 0.03, -0.006),
            V3(0.03, 0.022, 0.04),
            k=0.03,
        )
        _ = head_ell(
            m,
            "nostrilwing",
            h,
            hf,
            V3(0.055 * s, -0.03, 0.35),
            V3(0.03, 0.035, 0.038),
            k=0.03,
        )
        _ = sculpt_eye_socket(
            m,
            eye,
            HEAD_O,
            s,
            h,
            orbit_r=V3(0.022, 0.016, 0.012),
            orbit_at=V3(0.0, 0.002, 0.022),
            orbit_k=0.01,
        )
        # The nostrils: commas on the front corners of the muzzle plate.
        _ = head_ell(
            m,
            "nostril",
            h,
            hf,
            V3(0.043 * s, -0.035, 0.392),
            V3(0.011, 0.022, 0.02),
            k=0.006,
            axis_l=V3(-0.35 * s, 0.1, 1),
            up_l=V3(0.35 * s, 1, 0),
            carve=True,
        )
        _ = m.sphere(
            "earbase",
            h,
            rig.j("earBase" + side) + V3(-0.012 * s, 0, 0),
            0.032,
            k=0.03,
        )
    # The philtrum groove, and the mouth line under the upper lip.
    _ = head_ell(
        m,
        "philtrum",
        h,
        hf,
        V3(0, -0.07, 0.405),
        V3(0.004, 0.03, 0.012),
        k=0.006,
        carve=True,
    )
    _ = head_ell(
        m,
        "mouthcut",
        h,
        hf,
        V3(0, -0.13, 0.31),
        V3(0.06, 0.012, 0.07),
        k=0.008,
        carve=True,
    )

    # JAW: the lower lip and the chin; the mouth opens and chews sideways.
    var jw = rig.bone("jaw")
    _ = m.ell(
        "chin",
        jw,
        hf.at(V3(0, -0.138, 0.3)),
        V3(0.05, 0.038, 0.06),
        axis=hf.hz,
        up=hf.hy,
        k=0,
        part=JAW,
    )
    _ = m.ell(
        "lowerlip",
        jw,
        hf.at(V3(0, -0.125, 0.345)),
        V3(0.056, 0.026, 0.035),
        axis=hf.hz,
        up=hf.hy,
        k=0.02,
        part=JAW,
    )
    for s in [1.0, -1.0]:
        _ = m.cone(
            "mandible",
            jw,
            hf.at(V3(0.036 * s, -0.14, 0.2)),
            hf.at(V3(0.03 * s, -0.135, 0.3)),
            0.022,
            0.028,
            k=0.03,
            part=JAW,
        )
    # The tongue: its own surface in the mouth.
    var tg = rig.bone("tongue")
    var tb = rig.j("tongueBase")
    var tt = rig.j("tongueTip")
    _ = m.cone("tongue", tg, tb, tt, 0.03, 0.024, k=0.02, part=TONGUE)
    _ = m.ell(
        "tongue",
        tg,
        lerp(tb, tt, 0.7),
        V3(0.036, 0.016, 0.07),
        axis=normalize(tt - tb),
        up=hf.hy,
        k=0.02,
        part=TONGUE,
    )

    # EARS: broad leaves, carried sideways.
    var e_k = 1.1 if calf else 1.0
    for side in [String("L"), String("R")]:
        var base = rig.j("earBase" + side)
        var tip = rig.j("earTip" + side)
        var along = normalize(tip - base)
        # The pinna opens forward and a little down.
        var facing = normalize(V3(0, -0.25, 1))
        var lat = normalize(cross(along, facing))
        var eb = rig.bone("ear" + side)
        _ = ell_y(
            m,
            "ear",
            eb,
            lerp(base, tip, 0.5),
            along,
            V3(0.056 * e_k, 0.108 * e_k, 0.018),
            lateral=lat,
            k=0.02,
            thin=True,
        )
        _ = ell_y(
            m,
            "ear",
            eb,
            lerp(base, tip, 0.15),
            along,
            V3(0.03, 0.05, 0.026),
            lateral=lat,
            k=0.02,
            thin=True,
        )
        _ = ell_y(
            m,
            "earinner",
            eb,
            lerp(base, tip, 0.55) + facing * 0.016,
            along,
            V3(0.042 * e_k, 0.09 * e_k, 0.013),
            lateral=lat,
            k=0.006,
            carve=True,
            thin=True,
        )

    # LEGS.
    var leg_k = 1.0 + 0.08 * beef + 0.1 * bull
    for side in [String("L"), String("R")]:
        _foreleg(m, rig, side, leg_k, bull)
        _hind_leg(m, rig, side, leg_k, beef)

    # TAIL: the tail head, the bony tail, and the switch.
    var tail_k = 0.9 if calf else 1.0
    for i in range(BONE_SEGS):
        var t0 = Float64(i) / Float64(BONE_SEGS)
        var t1 = Float64(i + 1) / Float64(BONE_SEGS)
        _ = m.cone(
            "tail",
            rig.bone("tail" + String(i)),
            rig.j("tail" + String(i)),
            rig.j("tail" + String(i + 1)),
            (0.05 - 0.032 * t0**0.7) * tail_k,
            (0.05 - 0.032 * t1**0.7) * tail_k,
            k=0.06 if i == 0 else 0.01,
        )
    # The switch: a long tassel of hair from the end of the bony tail.
    var sw = t.get("switchLen", 1.0) * (0.4 if calf else 1.0)
    var b9 = rig.j("tail" + String(BONE_SEGS - 1))
    var b10 = rig.j("tail" + String(BONE_SEGS))
    var b11 = rig.j("tail" + String(BONE_SEGS + 1))
    var b12 = rig.j("tail" + String(TAIL_SEGS))
    var sw1 = lerp(b10, b11, min(1.0, sw))
    var sw2 = lerp(b11, b12, clamp(sw, 0.0, 1.0))
    _ = m.cone(
        "switch",
        rig.bone("tail" + String(BONE_SEGS - 1)),
        lerp(b9, b10, 0.3),
        b10,
        0.022,
        0.04,
        k=0.015,
    )
    _ = m.cone(
        "switch",
        rig.bone("tail" + String(BONE_SEGS)),
        b10,
        sw1,
        0.042,
        0.048 * max(0.6, sw),
        k=0.015,
    )
    if sw > 0.5:
        _ = m.cone(
            "switch",
            rig.bone("tail" + String(BONE_SEGS + 1)),
            sw1,
            sw2,
            0.048,
            0.012,
            k=0.015,
        )

    # HORNS: their own surface on the head.
    if t.get("hornStyle", 0.0) > 0.0:
        for s in [1.0, -1.0]:
            var pts = _horn_points(t, s)
            var rads = _horn_radii(t)
            for i in range(len(pts) - 1):
                _ = m.cone(
                    "horn",
                    h,
                    pts[i],
                    pts[i + 1],
                    rads[i],
                    rads[i + 1],
                    k=0.01,
                    part=HORN,
                )
            # The horn's base boss on the poll.
            _ = m.sphere(
                "hornbase",
                h,
                hf.at(V3(0.082 * s, 0.035, -0.158)) + V3(0.006 * s, 0, 0),
                t.get("hornR", 0.03) * 1.05,
                k=0.03,
            )

    # EAR TAGS and the NOSE RING: their own surfaces.
    if t.get("earTags", 0.0) > 0.0:
        for side in [String("L"), String("R")]:
            var eb = rig.bone("ear" + side)
            var q = lerp(
                rig.j("earBase" + side), rig.j("earTip" + side), 0.42
            ) + V3(0, -0.01, 0.02)
            _ = m.cone(
                "eartag",
                eb,
                q + V3(0, 0.012, 0),
                q + V3(0, 0.012, 0.012),
                0.007,
                0.007,
                k=0.002,
                part=APPENDAGE,
            )
            _ = m.ell(
                "eartag",
                eb,
                q + V3(0, -0.028, 0.017),
                # (2.8 mm in the original, meshed there at a 3 mm cell:
                # thickened to stay whole at this sculpt's coarser cell)
                V3(0.028, 0.034, 0.0045),
                axis=normalize(V3(0, 0.1, 1)),
                k=0.004,
                part=APPENDAGE,
                thin=True,
            )
    if t.get("noseRing", 0.0) > 0.0:
        var c = hf.at(V3(0, -0.078, 0.402))
        var n = 14
        for i in range(n):
            _ = m.cone(
                "ring",
                h,
                _ring_at(hf, c, i, n),
                _ring_at(hf, c, i + 1, n),
                0.0042,
                0.0042,
                k=0.001,
                part=WATTLE,
            )


def _ring_at(hf: HeadFrame, c: V3, i: Int, n: Int) -> V3:
    var a = Float64(i) / Float64(n) * pi * 2.0
    return c + hf.hy * (cos(a) * 0.03) + hf.hz * (sin(a) * 0.03 * 0.85)


def _udder(mut m: SdfModel, rig: Rig, k: Float64) raises:
    # Four quarters under the pelvis between the thighs, the rear
    # attachment high between them, the fore udder blending forward into
    # the belly, and four teats. It is its own surface.
    var s1 = rig.bone("spine1")
    var sz = 0.75 + 0.35 * k
    _ = m.ell(
        "udder",
        s1,
        V3(0, 0.73 + 0.04 * (1.0 - k), -0.55),
        V3(0.15 * sz, 0.15 * sz, 0.22 * sz),
        k=0.06,
        part=APPENDAGE,
    )
    _ = m.ell(
        "udder",
        rig.bone("pelvis"),
        V3(0, 0.92, -0.74),
        V3(0.12 * sz, 0.2, 0.1),
        k=0.08,
        part=APPENDAGE,
    )
    _ = m.ell(
        "udder",
        s1,
        V3(0, 0.76, -0.36),
        V3(0.13 * sz, 0.1 * sz, 0.18 * sz),
        k=0.1,
        part=APPENDAGE,
    )
    var bottom = 0.73 + 0.04 * (1.0 - k) - 0.15 * sz
    for s in [1.0, -1.0]:
        # The quarters bulge a little each side of the median groove.
        _ = m.ell(
            "udder",
            s1,
            V3(0.075 * s, bottom + 0.1, -0.62),
            V3(0.085 * sz, 0.1 * sz, 0.12 * sz),
            k=0.05,
            part=APPENDAGE,
        )
        _ = m.ell(
            "udder",
            s1,
            V3(0.07 * s, bottom + 0.1, -0.45),
            V3(0.075 * sz, 0.09 * sz, 0.1 * sz),
            k=0.05,
            part=APPENDAGE,
        )
        for z in [-0.64, -0.44]:
            _ = m.cone(
                "teat",
                s1,
                V3(0.06 * s, bottom + 0.03, z),
                V3(0.062 * s, bottom - 0.05, z + 0.005),
                0.017,
                0.013,
                k=0.02,
                part=APPENDAGE,
            )


def _foreleg(
    mut m: SdfModel, rig: Rig, side: String, leg_k: Float64, bull: Float64
) raises:
    var s = 1.0 if side == "L" else -1.0
    var lat = V3(s, 0, 0)
    var sc = rig.j("scapTop" + side)
    var sh = rig.j("shoulder" + side)
    var e = rig.j("elbow" + side)
    var w = rig.j("wrist" + side)
    var mc = rig.j("mcp" + side)
    var scap = rig.bone("scapula" + side)
    var hum = rig.bone("humerus" + side)
    var rad = rig.bone("radius" + side)
    var meta = rig.bone("metacarpus" + side)
    _ = ell_y(
        m,
        "scapmuscle",
        scap,
        lerp(sc, sh, 0.45) + _sx(V3(0.06, 0, -0.02), s),
        sh - sc,
        V3(0.08 + 0.03 * bull, 0.25, 0.15),
        lateral=lat,
        k=0.12,
    )
    _ = m.sphere(
        "shoulderpoint",
        hum,
        sh + _sx(V3(0.015, 0.0, 0.03), s),
        0.075 * leg_k,
        k=0.09,
    )
    _ = m.cone("upperarm", hum, sh, e, 0.1 * leg_k, 0.085 * leg_k, k=0.09)
    _ = ell_y(
        m,
        "triceps",
        hum,
        lerp(sh, e, 0.55) + _sx(V3(0.01, 0.02, -0.09), s),
        e - sh,
        V3(0.1 * leg_k, 0.17, 0.12),
        lateral=lat,
        k=0.09,
    )
    _ = m.sphere("olecranon", rad, e + V3(0, 0.02, -0.07), 0.055, k=0.05)
    _ = m.cone(
        "forearm",
        rad,
        e + V3(0, 0, -0.01),
        w,
        0.08 * leg_k,
        0.048 * leg_k,
        k=0.05,
    )
    _ = ell_y(
        m,
        "forearmmuscle",
        rad,
        lerp(e, w, 0.25) + _sx(V3(0.008, 0, 0.012), s),
        w - e,
        V3(0.074 * leg_k, 0.14, 0.08 * leg_k),
        lateral=lat,
        k=0.05,
    )
    _ = m.cone(
        "forearmweb",
        rad,
        e + _sx(V3(-0.04, 0.06, -0.02), s),
        lerp(e, w, 0.3) + _sx(V3(-0.02, 0, 0), s),
        0.06,
        0.045,
        k=0.06,
    )
    # The knee (carpus): broad, the accessory carpal bone behind.
    _ = ell_y(
        m,
        "knee",
        meta,
        w + V3(0, 0.0, 0.004),
        V3(0, 1, 0),
        V3(0.053 * leg_k, 0.058, 0.048 * leg_k),
        lateral=lat,
        k=0.025,
    )
    _ = m.sphere("accessory", meta, w + V3(0, 0.03, -0.042), 0.024, k=0.02)
    # The cannon: short, broad and flat in front.
    _ = m.cone(
        "cannon",
        meta,
        w + V3(0, -0.02, 0.0),
        mc + V3(0, 0.02, 0.0),
        0.036 * leg_k,
        0.034 * leg_k,
        k=0.02,
    )
    _ = m.cone(
        "tendon",
        meta,
        w + V3(0, -0.03, -0.028),
        mc + V3(0, 0.03, -0.03),
        0.022 * leg_k,
        0.026 * leg_k,
        k=0.02,
    )
    _ = ell_y(
        m,
        "fetlock",
        meta,
        mc + V3(0, 0.0, -0.01),
        V3(0, 1, 0.3),
        V3(0.048 * leg_k, 0.048, 0.05),
        lateral=lat,
        k=0.02,
    )
    _digits(
        m,
        rig.bone("fpaw" + side),
        rig.bone("fhoof" + side),
        mc,
        rig.j("fcoffin" + side),
        rig.j("ftoe" + side),
        leg_k,
    )


def _hind_leg(
    mut m: SdfModel, rig: Rig, side: String, leg_k: Float64, beef: Float64
) raises:
    var s = 1.0 if side == "L" else -1.0
    var lat = V3(s, 0, 0)
    var hp = rig.j("hip" + side)
    var kn = rig.j("knee" + side)
    var hk = rig.j("hock" + side)
    var mt = rig.j("mtp" + side)
    var fem = rig.bone("femur" + side)
    var tib = rig.bone("tibia" + side)
    var mtar = rig.bone("metatarsus" + side)
    # The thigh: flat and lean in dairy cows, full and round in beef.
    _ = ell_y(
        m,
        "thigh",
        fem,
        lerp(hp, kn, 0.42) + _sx(V3(0.02 + 0.02 * beef, 0, -0.05), s),
        kn - hp,
        V3(0.08 + 0.04 * beef, 0.3, 0.2 + 0.03 * beef),
        lateral=lat,
        k=0.1,
    )
    _ = m.cone(
        "thighfront",
        fem,
        _sx(V3(0.22, 1.25, -0.46), s),
        kn + _sx(V3(0.0, 0.06, 0.04), s),
        0.11,
        0.07,
        k=0.1,
    )
    _ = m.cone(
        "hamstring",
        fem,
        _sx(V3(0.11, 1.26, -0.84), s),
        lerp(kn, hk, 0.3) + V3(0, 0, -0.08),
        0.1 + 0.02 * beef,
        0.06,
        k=0.08,
    )
    _ = ell_y(
        m,
        "flankfold",
        fem,
        _sx(V3(0.22, 0.92, -0.3), s),
        V3(-0.1, 0.3, 0.12),
        V3(0.05, 0.15, 0.08),
        lateral=lat,
        k=0.1,
    )
    _ = m.sphere("stifle", tib, kn + _sx(V3(0.01, 0.01, 0.03), s), 0.06, k=0.07)
    _ = ell_y(
        m,
        "gaskin",
        tib,
        lerp(kn, hk, 0.32) + _sx(V3(0.006, 0, -0.045), s),
        hk - kn,
        V3(0.072 * leg_k, 0.16, 0.09 * leg_k),
        lateral=lat,
        k=0.06,
    )
    _ = m.cone(
        "shin", tib, lerp(kn, hk, 0.1), hk, 0.06 * leg_k, 0.046 * leg_k, k=0.05
    )
    _ = m.cone(
        "achilles",
        tib,
        lerp(kn, hk, 0.45) + V3(0, 0, -0.075),
        hk + V3(0, 0.07, -0.07),
        0.03,
        0.024,
        k=0.03,
    )
    _ = m.sphere("calcaneus", mtar, hk + V3(0, 0.07, -0.066), 0.034, k=0.025)
    _ = ell_y(
        m,
        "hock",
        mtar,
        hk + V3(0, 0.01, -0.005),
        V3(0, 1, 0.25),
        V3(0.052 * leg_k, 0.075, 0.055),
        lateral=lat,
        k=0.03,
    )
    _ = m.cone(
        "cannon",
        mtar,
        hk + V3(0, -0.04, 0.005),
        mt + V3(0, 0.02, 0.0),
        0.036 * leg_k,
        0.033 * leg_k,
        k=0.02,
    )
    _ = m.cone(
        "tendon",
        mtar,
        hk + V3(0, -0.04, -0.034),
        mt + V3(0, 0.03, -0.032),
        0.022 * leg_k,
        0.026 * leg_k,
        k=0.02,
    )
    _ = ell_y(
        m,
        "fetlock",
        mtar,
        mt + V3(0, 0.0, -0.01),
        V3(0, 1, 0.3),
        V3(0.047 * leg_k, 0.048, 0.05),
        lateral=lat,
        k=0.02,
    )
    _digits(
        m,
        rig.bone("hpaw" + side),
        rig.bone("hhoof" + side),
        mt,
        rig.j("hcoffin" + side),
        rig.j("htoe" + side),
        0.97 * leg_k,
    )


def _digits(
    mut m: SdfModel,
    paw: BoneId,
    hoof: BoneId,
    mc: V3,
    c: V3,
    toe: V3,
    w: Float64,
) raises:
    # The cloven hoof: the pastern with two dew claws, then two claws, each
    # a half cone with its front wall parallel to the pastern, heel bulbs
    # behind, the cleft carved between them and the sole cut flat.
    _ = m.cone("pastern", paw, mc, c, 0.038 * w, 0.04 * w, k=0.02)
    for d in [1.0, -1.0]:
        _ = m.ell(
            "dewclaw",
            paw,
            mc + V3(0.022 * d, -0.035, -0.05),
            V3(0.013, 0.017, 0.016),
            axis=normalize(V3(0, -0.5, -1)),
            k=0.012,
        )
    var z_mid = (c.z + toe.z) * 0.5
    var dir = 1.0 if toe.z - c.z >= 0.0 else -1.0
    for d in [1.0, -1.0]:
        var off = 0.026 * d * w
        _ = m.cone(
            "hoof",
            hoof,
            c + V3(off, 0.018, -0.012 * dir),
            V3(c.x + off * 1.1, 0.0, z_mid - 0.004 * dir),
            0.026 * w,
            0.036 * w,
            k=0.012,
        )
        # The toe: the pointed front of each claw.
        _ = m.ell(
            "hoof",
            hoof,
            V3(c.x + off * 0.9, 0.022, toe.z - 0.028 * dir),
            V3(0.024 * w, 0.022, 0.034),
            axis=normalize(V3(0, -0.25, dir)),
            k=0.012,
        )
        _ = m.sphere(
            "heelbulb",
            hoof,
            c + V3(off * 0.9, -0.026, -0.042 * dir),
            0.026 * w,
            k=0.02,
        )
    _ = m.cone(
        "coronet",
        hoof,
        c + V3(0, 0.024, -0.02 * dir),
        c + V3(0, 0.012, 0.02 * dir),
        0.043 * w,
        0.043 * w,
        k=0.015,
    )
    _ = m.ell(
        "cleft",
        hoof,
        V3(c.x, 0.0, toe.z - 0.004 * dir),
        V3(0.005, 0.045, 0.075),
        k=0.004,
        carve=True,
    )
    _ = m.ell(
        "cleft",
        hoof,
        V3(c.x, -0.005, z_mid),
        V3(0.004, 0.03, 0.08),
        k=0.003,
        carve=True,
    )
    _ = m.ell(
        "sole",
        hoof,
        V3(c.x, -0.2 + 0.002, z_mid),
        V3(0.2, 0.2, 0.2),
        k=0.004,
        carve=True,
    )


def cow_look(t: Traits) -> EyeLook:
    """Return the cow's eye colors: a dark brown iris, a horizontal bar.

    Lighter brown fibers ring the pupil, a dark limbus rims the iris, and
    a little white sclera shows at the corners.

    Args:
        t: The individual. Every cow has the same eyes.

    Returns:
        The look.
    """
    return EyeLook(
        srgb(0x2A180D),
        srgb(0x4A2E1C),
        srgb(0x160C06),
        V3(0.72, 0.68, 0.64),
        0.3,
        -2.5,
    )


def _coat_hexes(coat: Int) -> List[Int]:
    # Body, dorsal, belly, head, white, dark muzzle and a dark shade.
    if coat == C_RED_HOLSTEIN:
        return [0x7E2E1C, 0x72291A, 0x8A3824, 0x7A2C1B, 0xF1EFE9, 0x9A6A5A, 0]
    if coat == C_HEREFORD:
        return [0x7E3A20, 0x70321B, 0x8A4428, 0x7E3A20, 0xEFE9DF, 0xD8A090, 0]
    if coat == C_ANGUS:
        return [0x161413, 0x141211, 0x1E1A18, 0x161413, 0x161413, 0x1A1818, 0]
    if coat == C_RED_ANGUS:
        return [0x6A2A18, 0x5E2515, 0x72301C, 0x6A2A18, 0x6A2A18, 0x4A3028, 0]
    if coat == C_JERSEY:
        return [
            0x9A7652,
            0x856444,
            0xAE8C66,
            0x5E4533,
            0xD6C7A8,
            0x1E1A18,
            0x5E4533,
        ]
    if coat == C_HIGHLAND:
        return [0xA0522D, 0x96492A, 0xAE6238, 0xA0522D, 0xA0522D, 0x2A2220, 0]
    if coat == C_HIGHLAND_BLACK:
        return [0x1C1816, 0x181412, 0x241E1A, 0x1C1816, 0x1C1816, 0x1A1616, 0]
    if coat == C_HIGHLAND_DUN:
        return [0xB89A6E, 0xAC8E62, 0xC4A87C, 0xB09268, 0xB89A6E, 0x3A3028, 0]
    return [0x141312, 0x121110, 0x1C1A19, 0x141312, 0xF1EFE9, 0x1E1A1A, 0]


def cow_palette(t: Traits) raises -> Palette:
    """Return one cow's palette: its breed's coat, shaded, and the seeds
    of its piebald patches.

    Args:
        t: The individual.

    Returns:
        The palette, in linear light.

    Raises:
        Error: If a swatch table is short.
    """
    var hex = _coat_hexes(Int(t.get("coat", 0.0)))
    if len(hex) < 7:
        raise Error("A cattle coat needs seven swatches")
    var k = t.get("coatShade", 0.0)
    var l = t.get("coatLightness", 0.0)
    var pal = Palette()
    var tinted: List[String] = [String("body"), "dorsal", "belly", "head"]
    for i in range(4):
        pal.set(tinted[i], _tint(srgb(hex[i]), k, l))
    pal.set("dark", _tint(srgb(hex[6]), k, l))
    pal.set("white", srgb(hex[4]))
    pal.set("muzzleDark", srgb(hex[5]))
    pal.set("pink", srgb(0xD99A8E))
    pal.set("udder", srgb(0xE0B0A0))
    pal.set("hoof", srgb(0x2A2522))
    pal.set("hoofPale", srgb(0x8C8174))
    pal.set("hornBase", srgb(0xD8CBB0))
    pal.set("hornTip", srgb(0x3A3530))
    pal.set("lidDark", srgb(0x3A302B))
    pal.set("lidPink", srgb(0xC8847A))
    pal.set("lidRing", srgb(0x2C2826))
    # The piebald field's offsets, drawn from the coat's own stream.
    var r = AnimalRandom(9311 + Int(t.get("coatSeed", 0.0)), 1, 0)
    var ox = r.next() * 100.0
    var oy = r.next() * 100.0
    var oz = r.next() * 100.0
    pal.set("piedOff", V3(ox, oy, oz))
    # The left eye's aperture.
    var e = _eye()
    var ef = eye_frame_of(e, HEAD_O, 1.0)
    pal.set("eyeBall", ef.c)
    pal.set("eyeC", ef.c + ef.y * e.off)
    pal.set("eyeX", ef.x)
    pal.set("eyeY", ef.y)
    pal.set("eyeZ", ef.z)
    return pal^


def _tint(c: V3, k: Float64, l: Float64) -> V3:
    return V3(
        c.x * (1.0 + 0.08 * k + l),
        c.y * (1.0 + l),
        c.z * (1.0 - 0.08 * k + l),
    )


def _pied(pal: Palette, t: Traits, p: V3) -> Float64:
    # The Holstein's piebald patches: low-frequency noise on the reference
    # skin with ragged, slightly jagged edges. Positive is white.
    var off = pal.get("piedOff")
    var freq = t.get("patchFreq", 2.4)
    var cover = t.get("blackCover", 0.55)
    var f = fbm3(
        V3(
            p.x * freq * 1.35 + off.x,
            p.y * freq + off.y,
            p.z * freq * 0.85 + off.z,
        ),
        3,
    )
    var j = (
        vnoise3(V3(p.x * 26.0 + off.y, p.y * 26.0, p.z * 26.0 + off.z)) - 0.5
    ) * 0.035
    return f + j - (0.5 + (cover - 0.55) * 0.55)


def _face(t: Traits, h: V3) -> Float64:
    # The Holstein's face marking, head-local. Positive is white.
    var ax = abs(h.x)
    var front = h.y + 0.06 - 0.25 * max(0.0, -h.z - 0.05)
    var face = Int(t.get("face", Float64(F_NONE)))
    var w = t.get("faceWidth", 1.0)
    if face == F_BLAZE:
        return min(
            0.04 * w
            + 0.03 * smoothstep(0.2, 0.36, h.z)
            + 0.02 * smoothstep(-0.05, -0.16, h.z)
            - ax,
            min(front, 0.44 - h.z),
        )
    if face == F_STAR:
        return 0.035 * w - (ax * ax + (h.z * 0.6) ** 2) ** 0.5
    if face == F_WHITE:
        return min(
            0.11 - max(0.0, ax - 0.03) * 0.8 - max(0.0, -h.y - 0.05) * 0.8,
            0.45 - h.z,
        )
    if face == F_STRIP:
        return min(min(0.022 * w - ax, front), min(0.3 - h.z, h.z + 0.02))
    return -1.0


def _white(
    pal: Palette,
    t: Traits,
    tag: String,
    bone: String,
    p: V3,
    leg: Float64,
    region: Int,
) -> Float64:
    # Where the white hair is, by breed. Positive is white.
    var breed = t.variant
    var hf = _hf()
    if breed == HOLSTEIN:
        if region == R_EAR:
            return _pied(pal, t, p) - 0.25
        if region == R_HEAD:
            var h = hf.local(p)
            return max(
                _face(t, h) * 8.0,
                _pied(pal, t, p) - 0.3 - 0.25 * smoothstep(-0.1, 0.2, h.z),
            )
        if region == R_SWITCH:
            return 1.0
        var f = _pied(pal, t, p)
        if leg > 0.0:
            # White lower legs, below the knees and hocks.
            var knee = 0.46 if is_front_limb(bone) else 0.58
            f += 0.9 * smoothstep(knee + 0.1, knee - 0.12, p.y)
        # The belly and the udder are mostly white.
        f += 0.55 * smoothstep(0.8, 0.62, p.y) * (1.0 - leg * 0.5)
        if region == R_TAIL:
            # The tail: black at the root, white further down.
            f += 0.5 * smoothstep(1.2, 0.8, p.y)
        return f
    if breed == HEREFORD:
        var off = pal.get("piedOff")
        var jag = (
            fbm3(V3(p.x * 40.0 + off.x, p.y * 40.0, p.z * 40.0), 2) - 0.5
        ) * 0.03
        if region == R_HEAD:
            # A white face; the white runs over the poll. Some have red
            # rings round the eyes, the spectacles.
            var h = hf.local(p)
            var d = -0.02 + (
                max(0.0, (-0.15 - h.z) * 0.5) if h.z < -0.15 else 0.0
            )
            if t.get("spectacles", 0.0) > 0.0:
                var pm = V3(abs(p.x), p.y, p.z)
                d = max(d, 0.03 - length(pm - pal.get("eyeBall")))
            return -(d + jag)
        var red = region == R_EAR or region == R_TAIL
        if red:
            return -1.0
        if region == R_SWITCH:
            return 1.0
        var d = 1.0
        if region == R_NECK:
            # The crest: white along the top of the neck behind the poll.
            d = min(
                d,
                abs(p.x)
                - 0.06
                - 0.06 * smoothstep(0.85, 1.08, p.z)
                + (1.36 - p.y) * 0.6
                + 0.2 * smoothstep(0.85, 0.7, p.z),
            )
        # The underline: belly, brisket, dewlap and throat.
        var line_y = (
            0.7
            + 0.3 * smoothstep(0.45, 0.8, p.z)
            + 0.05 * smoothstep(-0.3, -0.6, p.z)
        )
        if leg < 0.5:
            var wide = max(0.0, abs(p.x) - 0.12) if p.z < 0.5 else 0.0
            d = min(d, (p.y - line_y) + 0.25 * wide)
        if leg > 0.3:
            var wob = (
                fbm3(V3(p.x * 18.0 + off.y, p.y * 9.0, p.z * 18.0), 2) - 0.5
            ) * 0.12
            d = min(d, p.y - (0.3 if is_front_limb(bone) else 0.36) + wob)
        return -(d + jag)
    return -1.0


# The painter's regions.
comptime R_BODY = 0
comptime R_NECK = 1
comptime R_HEAD = 2
comptime R_TAIL = 4
comptime R_EAR = 5
comptime R_SWITCH = 7


def cow_paint(
    pal: Palette, t: Traits, tag: String, bone: String, s: CoatSample
) -> Paint:
    """Paint one vertex of a cow.

    A Holstein is black with seeded white piebald patches, white lower
    legs, belly, udder and switch, and a seeded face marking. A Hereford
    is red with a white face, crest, underline, lower legs and switch. A
    Jersey is fawn, darker over the neck, shoulders, hips and face, with
    a pale ring round its black muzzle. The muzzle plate is bare moist
    skin, pink under white hair. Hooves and horns are keratin, the horns
    pale with dark tips; the udder is bare skin.

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
    if s.part == HORN:
        # A pale waxy base, a dark tip and growth rings.
        var along = clamp(
            (abs(p.x) - 0.082) / max(0.08, t.get("hornLen", 0.2) * 0.85),
            0.0,
            1.0,
        )
        var c = mix3(
            pal.get("hornBase"),
            pal.get("hornTip"),
            smoothstep(0.55, 0.95, along),
        )
        c = mix3(
            c, pal.get("hornBase") * 0.75, 0.25 * smoothstep(0.15, 0.0, along)
        )
        c = c * (0.94 + 0.06 * sin(along * 60.0))
        return Paint(c, KERATIN)
    if s.part == WATTLE:
        return Paint(srgb(0x8A8A86), KERATIN)
    if s.part == TONGUE:
        return Paint(V3(0.3, 0.12, 0.13), SKIN)
    if tag == "eartag":
        return Paint(srgb(0xE8C020), SKIN)
    var udder = tag == "udder" or tag == "teat"
    if udder:
        # Bare pink skin; dark on black breeds.
        var c = pal.get("udder")
        var dark_breed = t.variant == ANGUS or t.variant == HIGHLAND
        if dark_breed:
            c = V3(0.05, 0.04, 0.04)
        elif t.variant == JERSEY:
            c = mix3(pal.get("udder"), pal.get("body"), 0.45)
        return Paint(c, SKIN)
    var leg = 1.0 if is_limb(bone) else 0.0
    var region = R_BODY
    var on_head = bone == "head" or bone == "jaw"
    var on_neck = bone == "neck1" or bone == "neck2"
    if on_head:
        region = R_HEAD
    elif bone.startswith("ear"):
        region = R_EAR
    elif tag == "switch":
        region = R_SWITCH
    elif bone.startswith("tail"):
        region = R_TAIL
    elif on_neck:
        region = R_NECK
    var wf = _white(pal, t, tag, bone, p, leg, region)
    var white = smoothstep(-0.004, 0.004, wf)
    var hoofed = tag == "hoof" or tag == "heelbulb" or tag == "dewclaw"
    if hoofed:
        var coffin = FCOFFIN if is_front_limb(bone) else HCOFFIN
        var wall = tag == "dewclaw" or p.y < coffin.y + 0.016 + 0.35 * (
            p.z - coffin.z
        )
        if wall:
            # Under white hair: slate-horn claws with dark pigment streaks.
            var c = pal.get("hoof")
            if white > 0.5:
                var seed = Float64(Int(t.get("coatSeed", 0.0)) % 97)
                var streak = smoothstep(
                    0.45,
                    0.62,
                    fbm3(V3(p.x * 90.0 + seed, p.y * 6.0, p.z * 90.0), 2),
                )
                c = mix3(
                    pal.get("hoofPale"), pal.get("hoof"), 0.25 + 0.6 * streak
                )
            if tag == "heelbulb":
                c = mix3(c, V3(0.08, 0.06, 0.05), 0.4)
            return Paint(c, KERATIN)
    if region == R_HEAD:
        return _paint_head(pal, t, s, white)
    var c: V3
    var shag = t.variant == HIGHLAND
    if region == R_SWITCH:
        # The switch: white on Holsteins and Herefords, black on Jerseys.
        c = mix3(pal.get("body"), V3(0.02, 0.02, 0.02), 0.2)
        if t.variant == JERSEY:
            c = srgb(0x1A1614)
        c = _long_hair(c, p)
    elif region == R_TAIL:
        c = mix3(pal.get("body"), pal.get("dorsal"), 0.4)
    elif region == R_EAR:
        # The coat's color outside, long pale hair inside the pinna.
        var sd = 1.0 if bone == "earL" else -1.0
        var along = normalize(V3(0.2 * sd, -0.025, -0.045))
        var facing = normalize(V3(0, -0.25, 1))
        var z = normalize(cross(normalize(cross(along, facing)), along))
        c = pal.get("head")
        if dot(n, z) > 0.3:
            c = mix3(c, srgb(0x9A8A80), 0.12)
    else:
        c = _paint_coat(pal, t, region, p, n, leg)
    if shag:
        c = _long_hair(c, p)
    c = mix3(c, pal.get("white"), white)
    return Paint(_fur(c, p), FUR)


def _paint_coat(
    pal: Palette, t: Traits, region: Int, p: V3, n: V3, leg: Float64
) -> V3:
    # The torso, neck and legs: countershaded, the Jersey's darker
    # shoulders, hips and lower legs.
    var up = clamp(n.y, -1.0, 1.0)
    var side = 1.0 if p.x >= 0.0 else -1.0
    var ventral = smoothstep(
        0.0, -0.7, n.y
    ) * 0.5 if region == R_NECK else smoothstep(-0.2, -0.8, n.y) * smoothstep(
        1.1, 0.85, p.y
    )
    ventral = mix(
        ventral,
        smoothstep(0.1, -0.7, n.x * side) * 0.6 * smoothstep(0.4, 0.8, p.y),
        leg,
    )
    var c = mix3(
        pal.get("body"), pal.get("dorsal"), smoothstep(0.3, 0.95, up) * 0.8
    )
    c = mix3(c, pal.get("belly"), ventral)
    if t.variant == JERSEY:
        var dk = (
            0.55 if region
            == R_NECK else 0.25 * smoothstep(0.55, 0.85, p.z)
            + 0.3 * smoothstep(-0.55, -0.85, p.z) * smoothstep(1.0, 1.3, p.y)
        ) * (1.0 + 0.8 * t.get("bull", 0.0))
        c = mix3(c, pal.get("dark"), clamp(dk, 0.0, 0.85) * (1.0 - ventral))
        c = mix3(c, pal.get("dark"), 0.5 * smoothstep(0.5, 0.15, p.y) * leg)
    return c


def _paint_head(
    pal: Palette, t: Traits, s: CoatSample, white: Float64
) -> Paint:
    var p = s.p
    var hf = _hf()
    var h = hf.local(p)
    var c = pal.get("head")
    var jersey = t.variant == JERSEY
    if jersey:
        c = mix3(c, pal.get("body"), 0.25 * smoothstep(0.05, 0.25, h.z))
    # The moist pebbled muzzle plate, pink under white hair.
    var muzzle_white = (
        white > 0.5 if t.variant == HOLSTEIN else t.variant == HEREFORD
    )
    var face_white = t.variant == HOLSTEIN and _face(t, h) > -0.02
    if face_white:
        muzzle_white = True
    var muz = pal.get("pink") if muzzle_white else pal.get("muzzleDark")
    var planum = (
        smoothstep(0.33, 0.36, h.z)
        * smoothstep(-0.115, -0.1, h.y)
        * smoothstep(0.02, 0.0, h.y - 0.02 * (h.z - 0.35))
    )
    var hm = V3(abs(h.x), h.y, h.z)
    var nostril = _nostril_dist(hm)
    if nostril < 0.004:
        return Paint(muz * 0.35, WET)
    if planum > 0.5:
        var pebble = 0.9 + 0.2 * vnoise3(p * 900.0)
        return Paint(muz * pebble, WET)
    # A fringe of short hair in the muzzle's color round the plate.
    var fr = smoothstep(0.29, 0.34, h.z) * smoothstep(-0.13, -0.105, h.y)
    c = mix3(c, muz, fr)
    var lower_lip = s.part == JAW and h.z > 0.33
    if lower_lip:
        c = mix3(c, muz, 0.6)
    if jersey:
        # The Jersey's pale ring round the dark muzzle, mealy eye rings.
        var ring = smoothstep(0.26, 0.3, h.z) * (
            1.0 - smoothstep(0.33, 0.35, h.z)
        )
        c = mix3(c, pal.get("white"), ring * 0.85)
        var de = length(V3(abs(p.x), p.y, p.z) - pal.get("eyeBall"))
        c = mix3(
            c,
            mix3(pal.get("body"), pal.get("white"), 0.5),
            0.6 * smoothstep(0.045, 0.028, de),
        )
    if h.z < -0.14:
        c = mix3(c, pal.get("body"), smoothstep(-0.14, -0.2, h.z) * 0.6)
    c = mix3(c, pal.get("white"), white)
    # The lids: a bare margin, dark gray-brown or pink, lashes above.
    var pm = V3(abs(p.x), p.y, p.z)
    var ec = pal.get("eyeC")
    var de = abs(
        lens_distance(pm, ec, pal.get("eyeX"), pal.get("eyeY"), 0.0215, 0.0094)
    )
    var near_eye = (
        length(pm - ec) < 0.04 and dot(pm - ec, pal.get("eyeZ")) > -0.01
    )
    if near_eye:
        if de < 0.0035:
            return Paint(
                pal.get("lidPink") if white > 0.5 else pal.get("lidDark"), SKIN
            )
        var lid_ring = de < 0.016 and white < 0.5
        if lid_ring:
            c = mix3(c, pal.get("lidRing"), 0.45 * smoothstep(0.016, 0.005, de))
        var lash = de < 0.009 and dot(pm - ec, pal.get("eyeY")) / 0.018 > 0.2
        if lash:
            c = mix3(c, V3(0.6, 0.55, 0.5), 0.3) if white > 0.5 else V3(
                0.012, 0.011, 0.01
            )
    if t.variant == HIGHLAND:
        c = _long_hair(c, p)
    return Paint(_fur(c, p), FUR)


def _nostril_dist(hm: V3) -> Float64:
    # About the distance to the left nostril's carver, head-local.
    var f = frame_zy(V3(-0.35, 0.1, 1), V3(0.35, 1, 0))
    var r = V3(0.011, 0.022, 0.02)
    var d = hm - V3(0.043, -0.035, 0.392)
    var u = V3(dot(d, f.x) / r.x, dot(d, f.y) / r.y, dot(d, f.z) / r.z)
    return (length(u) - 1.0) * 0.011


def _fur(c: V3, p: V3) -> V3:
    # Low-frequency color variation and a fine hair grain.
    var cv = fbm3(p * 5.0, 3) - 0.5
    var v = V3(
        c.x * (1.0 + 0.14 * cv), c.y * (1.0 + 0.12 * cv), c.z * (1.0 + 0.1 * cv)
    )
    return grizzle(v, p, 150.0, 0.06)


def _long_hair(c: V3, p: V3) -> V3:
    # Shade streaks along long hair that hangs down.
    var st = vnoise3(V3(p.x * 90.0, p.y * 3.0, p.z * 90.0))
    return c * (0.8 + 0.4 * st)
