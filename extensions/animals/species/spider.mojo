# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The spider: procedural-animals' `species/spider/`.

Two builds share the code. The wolf spider (Lycosidae, reference female
Hogna carolinensis, body 25 mm) is the default. The tarantula
(Theraphosidae, reference female Brachypelma hamorii, body 60 mm) has
three morphs: red-knee, rosy and pinktoe. Each has eight legs of seven
segments, two pedipalps, two chelicerae with fangs and eight simple eyes.

The reference rig and sculpt are in wolf-spider units: the tarantula is
drawn at the wolf spider's scale and its `size` carries the factor of
about 2.15, so both meshes get the same number of cells across a leg.
"""

from extensions.animals.coat import (
    CHITIN,
    EYE,
    FUR,
    KERATIN,
    CoatSample,
    EyeLook,
    Paint,
    Palette,
    mix3,
    srgb,
)
from extensions.sdf.ids import BoneId
from extensions.animals.parts import (
    LIMB,
    TEETH,
)
from extensions.sdf.sculpt import ell_y
from extensions.animals.kit import (
    EyeSpec,
    eye_frame_of,
)
from extensions.animals.noise import fbm3
from extensions.animals.options import (
    FEMALE,
    MALE,
    AnimalOptions,
    AnimalRandom,
    Sex,
)
from extensions.animals.rig import Rig
from extensions.sdf.field import SdfModel
from extensions.animals.traits import Traits, pick_age
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
from std.math import asin, cos, pi, sin, sqrt

# The builds, in procedural-animals' order.
comptime WOLF = 0
comptime TARANTULA = 1

# The tarantula's morphs.
comptime REDKNEE = 0
comptime ROSY = 1
comptime PINKTOE = 2

# The wolf spider's characteristic length, and the tarantula's.
comptime WOLF_UNIT = 0.013
comptime TARANTULA_UNIT = 0.028
# The tarantula's scale against the wolf spider.
comptime TARANTULA_K = TARANTULA_UNIT / WOLF_UNIT
# The head's origin: the wolf spider's `ceph` joint, the boundary of the
# cephalic and thoracic regions.
comptime HEAD_O = V3(0.0, 0.0076, 0.0016)
# The finest cell, at the `HERO` tier: the body region's cell.
comptime CELL = 0.000156

# The leg segments, base to tip.
comptime SEGS = 7


def spider_variant_names() -> List[String]:
    """Return the spider's builds.

    Returns:
        Wolf spider and tarantula.
    """
    return [String("wolf"), "tarantula"]


def _pick_sex(requested: Sex, mut r: AnimalRandom) -> Sex:
    # Six spiders in ten are female. The coin is drawn only when no sex
    # is requested.
    var given = requested == MALE or requested == FEMALE
    if given:
        return requested
    return FEMALE if r.next() < 0.6 else MALE


def spider_traits(mut r: AnimalRandom, options: AnimalOptions) raises -> Traits:
    """Draw one spider: procedural-animals' `variation`.

    Females are larger with a heavy abdomen. Adult males are smaller and
    leggier, with swollen palpal bulbs. Spiderlings are small and
    short-legged. The build is never drawn: a spider is a wolf spider
    unless the caller asks for the tarantula.

    Args:
        r: The individual's stream.
        options: The caller's sex, age and build.

    Returns:
        The traits.

    Raises:
        Error: If the requested build is not one of the two.
    """
    if options.variant.value >= 2:
        raise Error("The spider has no such color variant")
    var variant = TARANTULA if options.variant.value == TARANTULA else WOLF
    var wolf = variant == WOLF
    var sex = _pick_sex(options.sex, r)
    var age = pick_age(options.age)
    var t = Traits(sex, age, variant)
    var juv = t.juvenile() > 0.0
    var male = t.male() and not juv
    var size = (
        ((0.82 if wolf else 0.88) if male else 1.0)
        * (1.0 + 0.08 * r.g())
        * (0.42 if juv else 1.0)
    )
    # The reference is in wolf-spider units: the size carries the scale.
    t.set("size", size * (1.0 if wolf else TARANTULA_K))
    t.set(
        "legK",
        (1.1 if male else 1.0) * (1.0 + 0.04 * r.g()) * (0.9 if juv else 1.0),
    )
    var abd = 0.78
    if not male:
        var g1 = r.g()
        abd = 1.0 + 0.08 * abs(g1) + 0.05 * r.g()
    t.set("abdK", abd * (0.9 if juv else 1.0))
    t.set("palpBulb", 1.0 if male else 0.0)
    t.set("coatWarmth", 0.9 * r.g())
    var male_wolf = male and wolf
    t.set("coatLightness", 0.18 * r.g() + (-0.08 if male_wolf else 0.0))
    var contrast = 1.0
    var gray = 0.0
    if wolf:
        contrast = 0.6 + 0.55 * r.next()
        gray = 0.75 * r.next() ** 1.5
    t.set("patternContrast", contrast)
    t.set("coatGray", gray)
    t.set("coatSeed", Float64(Int(r.next() * 1e6)))
    var morph = REDKNEE
    var bald = 0.0
    if not wolf:
        var m = r.next()
        morph = REDKNEE if m < 0.6 else (ROSY if m < 0.8 else PINKTOE)
        bald = 1.0 if r.next() < 0.3 else 0.0
    t.set("morph", Float64(morph))
    t.set("bald", bald)
    # The thinnest part's least radius per tier, in wolf millimeters, so
    # the coarse meshes keep the tarsi.
    var min_r: List[Float64] = [0.0, 0.0, 0.26, 0.4, 0.58]
    t.set("minR", min_r[options.quality.value])
    return t^


struct _Dims(Movable):
    """One individual's anatomy, in millimeters of its build."""

    var wolf: Bool
    var unit: Float64
    # Meters per millimeter in reference space.
    var q: Float64
    var front: V3
    var ceph: V3
    var ped_a: V3
    var ped_b: V3
    var abd_end: V3
    var spin_tip: V3
    var car_len: Float64
    var car_wid: Float64
    var car_top: Float64
    var car_rear_top: Float64
    var car_bottom: Float64
    var car_head_w: Float64
    var abd_c: V3
    var abd_r: V3
    var chel_base: V3
    var chel_tip: V3
    var chel_fang: V3
    var chel_r0: Float64
    var chel_r1: Float64
    var fang_r: Float64
    var coxa_y: Float64
    var coxa_x: List[Float64]
    var coxa_z: List[Float64]
    var coxa_az: List[Float64]
    var leg: List[Float64]
    var seg: List[Float64]
    var el: List[Float64]
    var leg_r0: List[Float64]
    var leg_r1: List[Float64]
    var hind_r: Float64
    var tip_y: Float64
    var palp_base: V3
    var palp_az: Float64
    var palp_len: Float64
    var palp_seg: List[Float64]
    var palp_el: List[Float64]
    var palp_r0: List[Float64]
    var palp_r1: List[Float64]
    var palp_tip_y: Float64
    var spin_r: Float64
    var palp_bulb: Float64

    def __init__(out self, t: Traits):
        self.wolf = t.variant == WOLF
        var leg_k = t.get("legK")
        var abd_k = t.get("abdK")
        self.palp_bulb = t.get("palpBulb", 0.0)
        var abd_c: V3
        var abd_r: V3
        var abd_end: V3
        var spin_tip: V3
        var leg: List[Float64]
        var palp_len: Float64
        if self.wolf:
            self.unit = WOLF_UNIT
            self.front = V3(0, 7.4, 6.5)
            self.ceph = V3(0, 7.6, 1.6)
            self.ped_a = V3(0, 6.3, -4.5)
            self.ped_b = V3(0, 6.1, -5.7)
            abd_end = V3(0, 5.4, -17.2)
            spin_tip = V3(0, 4.7, -18.5)
            self.car_len = 11.0
            self.car_wid = 8.6
            self.car_top = 9.9
            self.car_rear_top = 7.3
            self.car_bottom = 4.5
            self.car_head_w = 5.2
            abd_c = V3(0, 6.5, -11.4)
            abd_r = V3(3.9, 3.35, 6.1)
            self.chel_base = V3(0.95, 7.0, 6.1)
            self.chel_tip = V3(0.9, 3.8, 7.0)
            self.chel_fang = V3(0.15, 4.25, 6.75)
            self.chel_r0 = 0.95
            self.chel_r1 = 0.72
            self.fang_r = 0.2
            self.coxa_y = 5.1
            self.coxa_x = [2.35, 2.75, 2.75, 2.45]
            self.coxa_z = [3.3, 1.4, -0.6, -2.6]
            self.coxa_az = [30.0, 66.0, 112.0, 150.0]
            leg = [35.0, 33.0, 31.0, 43.0]
            self.seg = [0.08, 0.05, 0.26, 0.12, 0.2, 0.19, 0.1]
            self.el = [-14.0, 4.0, 30.0, -6.0, -28.0, 0.0, -14.0]
            self.leg_r0 = [1.05, 0.84, 0.8, 0.7, 0.63, 0.5, 0.39]
            self.leg_r1 = [0.95, 0.8, 0.68, 0.63, 0.53, 0.4, 0.29]
            self.hind_r = 1.06
            self.tip_y = 0.32
            self.palp_base = V3(1.75, 5.2, 5.4)
            self.palp_az = 14.0
            palp_len = 16.0
            self.palp_seg = [0.12, 0.08, 0.3, 0.15, 0.18, 0.17]
            self.palp_el = [-30.0, -10.0, 15.0, -30.0, 0.0, -50.0]
            self.palp_r0 = [0.62, 0.5, 0.46, 0.42, 0.4, 0.37]
            self.palp_r1 = [0.55, 0.48, 0.42, 0.4, 0.37, 0.28]
            self.palp_tip_y = 0.55
            self.spin_r = 0.45
        else:
            self.unit = TARANTULA_UNIT
            self.front = V3(0, 13.2, 12.8)
            self.ceph = V3(0, 14.2, 3.5)
            self.ped_a = V3(0, 12.0, -11.6)
            self.ped_b = V3(0, 11.8, -13.6)
            abd_end = V3(0, 10.8, -41.5)
            spin_tip = V3(0, 9.2, -46.0)
            self.car_len = 25.0
            self.car_wid = 23.5
            self.car_top = 16.2
            self.car_rear_top = 14.0
            self.car_bottom = 7.4
            self.car_head_w = 13.0
            abd_c = V3(0, 12.4, -27.6)
            abd_r = V3(12.0, 9.6, 14.4)
            self.chel_base = V3(3.0, 12.6, 11.2)
            self.chel_tip = V3(2.9, 9.4, 18.0)
            self.chel_fang = V3(2.6, 4.9, 16.4)
            self.chel_r0 = 3.1
            self.chel_r1 = 2.4
            self.fang_r = 0.75
            self.coxa_y = 8.6
            self.coxa_x = [5.8, 6.7, 6.7, 6.0]
            self.coxa_z = [6.2, 2.0, -2.6, -7.0]
            self.coxa_az = [26.0, 60.0, 114.0, 150.0]
            leg = [65.0, 60.0, 55.0, 72.5]
            self.seg = [0.09, 0.06, 0.25, 0.14, 0.2, 0.16, 0.1]
            self.el = [-10.0, 6.0, 34.0, -4.0, -30.0, 0.0, -13.0]
            self.leg_r0 = [3.0, 2.4, 2.3, 2.05, 1.95, 1.65, 1.45]
            self.leg_r1 = [2.7, 2.3, 2.0, 1.95, 1.75, 1.45, 1.25]
            self.hind_r = 1.04
            self.tip_y = 1.3
            self.palp_base = V3(4.6, 8.4, 10.8)
            self.palp_az = 16.0
            palp_len = 37.0
            self.palp_seg = [0.14, 0.08, 0.28, 0.16, 0.18, 0.16]
            self.palp_el = [-30.0, -10.0, 15.0, -30.0, 0.0, -40.0]
            self.palp_r0 = [2.2, 1.9, 1.8, 1.65, 1.55, 1.45]
            self.palp_r1 = [2.0, 1.8, 1.65, 1.55, 1.45, 1.2]
            self.palp_tip_y = 1.3
            self.spin_r = 1.3
        self.q = 0.001 * WOLF_UNIT / self.unit
        self.leg = List[Float64]()
        for l in leg:  # pragma: no branch
            self.leg.append(l * leg_k)
        self.palp_len = palp_len * (0.5 + 0.5 * leg_k)
        self.abd_r = abd_r * abd_k
        # A bigger abdomen hangs further back from the pedicel.
        var dk = abd_k - 1.0
        self.abd_c = V3(0, abd_c.y + dk * 0.4 * abd_r.y, abd_c.z - dk * abd_r.z)
        self.abd_end = V3(
            0, abd_end.y - dk * 0.3 * abd_r.y, abd_end.z - 2.0 * dk * abd_r.z
        )
        self.spin_tip = V3(
            0, spin_tip.y - dk * 0.3 * abd_r.y, spin_tip.z - 2.0 * dk * abd_r.z
        )

    def f(self) -> Float64:
        """The build's size against the wolf spider."""
        return self.unit / WOLF_UNIT

    def mm(self, v: V3) -> V3:
        """A point in millimeters, in reference meters."""
        return v * self.q


def _plane_dir(phi: Float64, e: Float64, side: Float64) -> V3:
    # A direction in a vertical leg plane: azimuth `phi` from forward
    # toward the leg's side, elevation `e` above horizontal.
    var c = cos(e)
    return V3(sin(phi) * c * side, sin(e), cos(phi) * c)


def _chain(
    base: V3,
    az: Float64,
    el_deg: List[Float64],
    lens: List[Float64],
    free: Int,
    y_tip: Float64,
) -> List[V3]:
    # A planar chain from `base`. The elevation of segment `free` is
    # solved so the tip ends at height `y_tip`: procedural-animals'
    # `solveBindElevations` and `planarChain`.
    # A chain needs an elevation for each segment, and the free one.
    var unsolved = free < 0 or free >= len(lens) or len(el_deg) != len(lens)
    if unsolved:
        return [base]
    var el = List[Float64]()
    # One segment at least, checked above.
    for e in el_deg:  # pragma: no branch
        el.append(e * pi / 180.0)
    var drop = 0.0
    # One segment at least, checked above.
    for k in range(len(lens)):  # pragma: no branch
        if k != free:
            drop += lens[k] * sin(el[k])
    var s = (y_tip - base.y - drop) / lens[free]
    el[free] = asin(clamp(s, -1.0, 1.0))
    var out = List[V3]()
    var p = base
    out.append(p)
    # One segment at least, checked above.
    for k in range(len(lens)):  # pragma: no branch
        p = p + _plane_dir(az, el[k], 1.0) * lens[k]
        out.append(p)
    return out^


def _leg_chain(d: _Dims, i: Int) -> List[V3]:
    # Leg `i` (0 to 3) of the left side, coxa base to claw tip.
    var lens = List[Float64]()
    # The dims tables list every leg segment.
    for f in d.seg:
        lens.append(f * d.leg[i] * d.q)
    var base = d.mm(V3(d.coxa_x[i], d.coxa_y, d.coxa_z[i]))
    return _chain(base, d.coxa_az[i] * pi / 180.0, d.el, lens, 5, d.tip_y * d.q)


def _palp_chain(d: _Dims) -> List[V3]:
    # The left pedipalp, coxa base to tip. Its tibia takes up the height
    # so the tarsus meets the ground slanting forward.
    var lens = List[Float64]()
    # The dims tables list every palp segment.
    for f in d.palp_seg:
        lens.append(f * d.palp_len * d.q)
    return _chain(
        d.mm(d.palp_base),
        d.palp_az * pi / 180.0,
        d.palp_el,
        lens,
        4,
        d.palp_tip_y * d.q,
    )


def _leg_names() -> List[String]:
    return [
        String("coxa"),
        "troch",
        "femur",
        "patella",
        "tibia",
        "meta",
        "tarsus",
        "claw",
    ]


def _palp_names() -> List[String]:
    return [
        String("palpCoxa"),
        "palpTroch",
        "palpFemur",
        "palpPatella",
        "palpTibia",
        "palpTarsus",
        "palpTip",
    ]


def spider_rig(t: Traits) raises -> Rig:
    """Return the spider's skeleton in bind pose.

    The axial bones are the prosoma (the root), the head on it, which
    carries the eyes, the pedicel, the abdomen and the spinnerets. Each
    chelicera carries a fang. Each pedipalp has six segments and each
    leg seven: coxa, trochanter, femur, patella, tibia, metatarsus and
    tarsus. Every bone is named after the joint it starts at. The legs
    stand in their bind pose with the claw tips on the ground.

    Args:
        t: The individual.

    Returns:
        The rig.

    Raises:
        Error: If a bone names a missing joint.
    """
    var d = _Dims(t)
    var rig = Rig()
    rig.set("front", d.mm(d.front))
    rig.set("ceph", d.mm(d.ceph))
    rig.set("pedA", d.mm(d.ped_a))
    rig.set("pedB", d.mm(d.ped_b))
    rig.set("abdEnd", d.mm(d.abd_end))
    rig.set("spinTip", d.mm(d.spin_tip))
    rig.set("cheBaseL", d.mm(d.chel_base))
    rig.set("cheTipL", d.mm(d.chel_tip))
    rig.set("fangTipL", d.mm(d.chel_fang))
    var names = _leg_names()
    for i in range(4):  # pragma: no branch
        var chain = _leg_chain(d, i)
        for k in range(SEGS + 1):  # pragma: no branch
            rig.set(names[k] + String(i + 1) + "L", chain[k])
    var palp = _palp_chain(d)
    var pn = _palp_names()
    for k in range(len(pn)):  # pragma: no branch
        rig.set(pn[k] + "L", palp[k])
    rig.mirror_joints()
    _ = rig.add_bone("prosoma", "pedA", "ceph", "")
    _ = rig.add_bone("head", "ceph", "front", "prosoma")
    _ = rig.add_bone("pedicel", "pedA", "pedB", "prosoma")
    _ = rig.add_bone("abdomen", "pedB", "abdEnd", "pedicel")
    _ = rig.add_bone("spinnerets", "abdEnd", "spinTip", "abdomen")
    for side in [String("L"), String("R")]:  # pragma: no branch
        _ = rig.add_bone(
            "chelicera" + side, "cheBase" + side, "cheTip" + side, "head"
        )
        _ = rig.add_bone(
            "fang" + side, "cheTip" + side, "fangTip" + side, "chelicera" + side
        )
    for side in [String("L"), String("R")]:  # pragma: no branch
        for k in range(len(pn) - 1):  # pragma: no branch
            _ = rig.add_bone(
                pn[k] + side,
                pn[k] + side,
                pn[k + 1] + side,
                "prosoma" if k == 0 else pn[k - 1] + side,
            )
    for side in [String("L"), String("R")]:  # pragma: no branch
        for i in range(1, 5):  # pragma: no branch
            var leg = String(i) + side
            for k in range(SEGS):  # pragma: no branch
                _ = rig.add_bone(
                    names[k] + leg,
                    names[k] + leg,
                    names[k + 1] + leg,
                    "prosoma" if k == 0 else names[k - 1] + leg,
                )
    return rig^


@fieldwise_init
struct _Eye(ImplicitlyCopyable):
    """One simple eye, left side, in millimeters from `ceph`."""

    var c: V3
    var r: Float64
    var yaw: Float64
    var pitch: Float64
    var back: Float64


def _eyes(wolf: Bool) -> List[_Eye]:
    # The principal eye comes first. The wolf spider's eyes are 4-2-2: a
    # straight front row of four small eyes above the chelicerae, two huge
    # posterior medians looking forward, and two posterior laterals on top
    # looking up and back. The tarantula's eight small eyes cluster on a
    # raised ocular tubercle.
    if wolf:
        return [
            _Eye(V3(1.02, 1.2, 4.57), 0.47, 0.14, 0.02, 0.2),
            _Eye(V3(1.78, 1.54, 2.72), 0.3, 2.1, 0.75, 0.14),
            _Eye(V3(0.42, 0.3, 5.26), 0.22, 0.05, -0.05, 0.07),
            _Eye(V3(1.0, 0.3, 5.05), 0.17, 0.55, -0.05, 0.05),
        ]
    return [
        _Eye(V3(0.62, 2.55, 6.1), 0.5, 0.08, 0.5, 0.2),
        _Eye(V3(1.62, 2.05, 6.25), 0.52, 0.6, 0.25, 0.2),
        _Eye(V3(0.85, 2.6, 5.05), 0.3, 0.5, 1.0, 0.12),
        _Eye(V3(1.72, 2.2, 4.75), 0.42, 1.7, 0.45, 0.16),
    ]


def _spec(e: _Eye, q: Float64, shift: V3) -> EyeSpec:
    # The eye spec of one simple eye, from a head origin `shift` away
    # from `ceph`.
    var r = e.r * q
    return EyeSpec(
        e.c * q + shift,
        r,
        e.back * q,
        e.yaw,
        e.pitch,
        0.0,
        r * 1.1,
        r * 0.6,
        0.0,
        0.0,
        r * 0.6,
        r * 0.8,
    )


def spider_eye(t: Traits) -> EyeSpec:
    """Return the spider's principal left eye.

    That is the wolf spider's huge posterior median eye, or the
    tarantula's anterior median eye. The other six eyes are sculpted as
    glossy domes.

    Args:
        t: The individual.

    Returns:
        The eye, from `HEAD_O`.
    """
    var d = _Dims(t)
    return _spec(_eyes(d.wolf)[0], d.q, d.mm(d.ceph) - HEAD_O)


def _min_r(d: _Dims, t: Traits) -> Float64:
    return t.get("minR", 0.0) * d.q * d.f()


def spider_sculpt(mut m: SdfModel, rig: Rig, t: Traits) raises:
    """Sculpt the spider: procedural-animals' `sculptSpider`, primitive
    for primitive.

    The prosoma, pedicel, abdomen, spinnerets, palps and coxae are the
    body. The legs from the trochanter out and the chelicerae are limbs,
    and the fangs are teeth. The principal eyes are the pipeline's
    eyeballs. The other eyes are glossy domes in raised rims.

    Args:
        m: The sculpt to add to.
        rig: The spider's rig in bind pose.
        t: The individual.

    Raises:
        Error: If the rig lacks a joint or a bone, or the sculpt refuses
            a primitive.
    """
    var d = _Dims(t)
    var q = d.q
    var f = d.f()
    var min_r = _min_r(d, t)
    var ho = rig.j("ceph")
    var wolf = d.wolf
    var z0 = rig.j("pedA").z / q
    var z1 = rig.j("front").z / q
    var lc = z1 - z0
    var pro = rig.bone("prosoma")
    var hb = rig.bone("head")

    # PROSOMA: the thoracic dome, the raised cephalic region, the sloping
    # rear, and the sternum below.
    var th_top = d.car_rear_top + (d.car_top - d.car_rear_top) * (
        0.55 if wolf else 0.75
    )
    _ = m.ell(
        "thorax",
        pro,
        d.mm(V3(0, (th_top + d.car_bottom) / 2.0, z0 + 0.42 * lc)),
        d.mm(V3(d.car_wid / 2.0, (th_top - d.car_bottom) / 2.0, 0.41 * lc)),
        k=0.0,
    )
    _ = m.ell(
        "thoraxRear",
        pro,
        d.mm(
            V3(
                0,
                (d.car_rear_top + d.car_bottom) / 2.0 + 0.2 * f,
                z0 + 0.2 * lc,
            )
        ),
        d.mm(
            V3(
                d.car_wid * 0.36,
                (d.car_rear_top - d.car_bottom) / 2.0,
                0.2 * lc,
            )
        ),
        k=0.9 * q * f,
    )
    var ch = (2.3 if wolf else 3.2) * f
    _ = m.ell(
        "cephalic",
        hb,
        d.mm(V3(0, d.car_top - ch, z0 + 0.78 * lc)),
        d.mm(V3(d.car_head_w / 2.0, ch, 0.26 * lc)),
        axis=normalize(V3(0, 0.18 if wolf else 0.05, 1)),
        k=1.2 * q * f,
    )
    # The clypeus: the face between the front eyes and the chelicerae.
    _ = m.ell(
        "clypeus",
        hb,
        rig.j("front") + d.mm(V3(0, -0.2 * f, -0.9 * f)),
        d.mm(V3(d.car_head_w * 0.36, 1.1 * f, 0.9 * f)),
        k=0.8 * q * f,
    )
    _ = m.ell(
        "sternum",
        pro,
        d.mm(V3(0, d.car_bottom + 0.45 * f, z0 + 0.5 * lc)),
        d.mm(V3(d.car_wid * 0.27, 0.7 * f, 0.3 * lc)),
        k=0.8 * q * f,
    )
    # The labium, between the palp coxae.
    _ = m.ell(
        "labium",
        pro,
        d.mm(V3(0, d.car_bottom + 0.6 * f, z0 + 0.86 * lc)),
        d.mm(V3(0.9 * f, 0.55 * f, 0.9 * f)),
        k=0.5 * q * f,
    )
    # The fovea: a short median groove on the thoracic dome.
    _ = m.ell(
        "fovea",
        pro,
        d.mm(V3(0, th_top + 0.02 * f, z0 + 0.36 * lc)),
        d.mm(V3(0.16 * f, 0.3 * f, 0.9 * f)),
        k=0.25 * q * f,
        carve=True,
    )
    if not wolf:
        # The tarantula's low, wide carapace has a raised ocular tubercle.
        _ = m.ell(
            "tubercle",
            hb,
            ho + d.mm(V3(0, 1.7, 5.4)),
            d.mm(V3(2.3, 1.3, 1.9)),
            k=1.1 * q * f,
        )

    # EYES: a raised rim round each lens, cut open by the socket the dome
    # sits in.
    var eyes = _eyes(wolf)
    for e in eyes:  # pragma: no branch
        var spec = _spec(e, q, V3(0, 0, 0))
        for s in [1.0, -1.0]:  # pragma: no branch
            var ef = eye_frame_of(spec, ho, s)
            _ = m.sphere(
                "eyerim",
                hb,
                ef.c + ef.z * (-spec.r * 0.25),
                spec.r * 1.05,
                k=spec.r * 0.6,
            )
            _ = m.sphere(
                "eyesocket",
                hb,
                ef.c + ef.z * (spec.r * 0.1),
                spec.r * 0.98,
                k=spec.r * 0.15,
                carve=True,
            )
    # The six lesser eyes: glossy domes. The pipeline adds the two
    # principal eyeballs.
    for n in range(1, len(eyes)):  # pragma: no branch
        var spec = _spec(eyes[n], q, V3(0, 0, 0))
        for s in [1.0, -1.0]:  # pragma: no branch
            var ef = eye_frame_of(spec, ho, s)
            _ = m.sphere("eyedome", hb, ef.c, spec.r, k=0.0)

    # PEDICEL, ABDOMEN AND SPINNERETS.
    _ = m.cone(
        "pedicel",
        rig.bone("pedicel"),
        rig.j("pedA"),
        rig.j("pedB"),
        (0.75 if wolf else 1.9) * q,
        (0.7 if wolf else 1.8) * q,
        k=0.3 * q * f,
    )
    var ab = rig.bone("abdomen")
    var ac = d.mm(d.abd_c)
    var ar = d.mm(d.abd_r)
    _ = m.ell("abdomen", ab, ac, ar, axis=normalize(V3(0, 0.06, 1)), k=0.0)
    _ = m.ell(
        "abdomenFront",
        ab,
        ac + V3(0, -ar.y * 0.05, ar.z * 0.52),
        V3(ar.x * 0.7, ar.y * 0.72, ar.z * 0.45),
        k=1.0 * q * f,
    )
    _ = m.ell(
        "abdomenRear",
        ab,
        ac + V3(0, -ar.y * 0.12, -ar.z * 0.6),
        V3(ar.x * 0.72, ar.y * 0.72, ar.z * 0.42),
        k=1.2 * q * f,
    )
    # Spinnerets: the wolf spider's three short pairs, and the tarantula's
    # two visible pairs, the hind pair long and finger-like.
    var sb = rig.bone("spinnerets")
    var st = rig.j("abdEnd")
    var sd = normalize(rig.j("spinTip") - st)
    var sl = length(rig.j("spinTip") - st)
    var sr = d.spin_r * q
    for s in [1.0, -1.0]:  # pragma: no branch
        if wolf:
            _ = m.cone(
                "spinneret",
                sb,
                st + d.mm(V3(0.45 * s, -0.25, 0.3)),
                st + sd * (sl * 0.9) + d.mm(V3(0.5 * s, -0.2, 0)),
                sr,
                sr * 0.7,
                k=0.25 * q,
            )
            _ = m.cone(
                "spinneret",
                sb,
                st + d.mm(V3(0.2 * s, -0.6, 0.3)),
                st + sd * (sl * 0.7) + d.mm(V3(0.2 * s, -0.55, 0)),
                sr * 0.8,
                sr * 0.55,
                k=0.25 * q,
            )
        else:
            _ = m.cone(
                "spinneret",
                sb,
                st + d.mm(V3(1.1 * s, -0.4, 0.8)),
                st + sd * (sl * 1.15) + d.mm(V3(1.9 * s, 0.9, 0)),
                sr,
                sr * 0.62,
                k=0.8 * q,
            )
            _ = m.cone(
                "spinneret",
                sb,
                st + d.mm(V3(0.55 * s, -1.2, 0.8)),
                st + sd * (sl * 0.45) + d.mm(V3(0.6 * s, -1.4, 0)),
                sr * 0.6,
                sr * 0.45,
                k=0.6 * q,
            )

    # CHELICERAE AND FANGS.
    for side in [String("L"), String("R")]:  # pragma: no branch
        var s = 1.0 if side == "L" else -1.0
        var b0 = rig.j("cheBase" + side)
        var b1 = rig.j("cheTip" + side)
        var ft = rig.j("fangTip" + side)
        var cb = rig.bone("chelicera" + side)
        var cr0 = d.chel_r0 * q
        var cr1 = d.chel_r1 * q
        var dir = normalize(b1 - b0)
        var cl = length(b1 - b0)
        _ = m.cone(
            "chelicera",
            cb,
            b0,
            b1 + dir * (-cr1 * 0.4),
            cr0,
            cr1,
            k=0.0,
            part=LIMB,
        )
        # The stout basal boss bulging forward (wolf spider), or the long,
        # forward-projecting paturon (tarantula).
        _ = ell_y(
            m,
            "chelicera",
            cb,
            lerp(b0, b1, 0.35)
            + d.mm(V3(0.1 * s * f, 0, (0.35 if wolf else 0.8) * f)),
            dir,
            V3(cr0 * 0.92, cl * 0.4, cr0 * 0.95),
            k=0.5 * q * f,
            part=LIMB,
        )
        # The fang groove: a shallow furrow on the inner face.
        _ = ell_y(
            m,
            "fangGroove",
            cb,
            lerp(b0, b1, 0.8) + d.mm(V3(-0.55 * s * f, 0, 0.1 * f)),
            dir,
            V3(cr1 * 0.35, cl * 0.22, cr1 * 0.4),
            k=0.2 * q * f,
            carve=True,
            part=LIMB,
        )
        # A curved fang: the base, then bending toward the tip.
        var fb = rig.bone("fang" + side)
        var fr = d.fang_r * q
        var fd = normalize(ft - b1)
        var fl = length(ft - b1)
        var bend = normalize(cross(fd, V3(s, 0, 0)))
        var mid = lerp(b1, ft, 0.5) + bend * (fl * 0.12)
        _ = m.cone(
            "fang",
            fb,
            b1 + fd * (-fr * 0.5),
            mid,
            fr,
            fr * 0.62,
            k=0.08 * q * f,
            part=TEETH,
        )
        _ = m.cone(
            "fang",
            fb,
            mid,
            ft,
            fr * 0.62,
            fr * 0.12,
            k=0.08 * q * f,
            part=TEETH,
        )

    # PALPS: part of the body.
    var pn = _palp_names()
    for side in [String("L"), String("R")]:  # pragma: no branch
        for k in range(len(pn) - 1):  # pragma: no branch
            var a = rig.j(pn[k] + side)
            var b = rig.j(pn[k + 1] + side)
            var pb = rig.bone(pn[k] + side)
            _ = m.cone(
                "palpcoxa" if k == 0 else "palp",
                pb,
                a,
                b,
                max(d.palp_r0[k] * q, min_r),
                max(d.palp_r1[k] * q, min_r),
                k=(0.6 if k == 0 else 0.09) * q * f,
            )
            var inner = k > 0 and k < len(pn) - 2
            if inner:
                _ = m.sphere(
                    "knuckle",
                    pb,
                    b,
                    max(d.palp_r1[k] * 1.08 * q, min_r),
                    k=0.08 * q * f,
                )
        if d.palp_bulb > 0.0:
            # The male's swollen palpal bulb: "boxing gloves".
            var a = rig.j("palpTarsus" + side)
            var b = rig.j("palpTip" + side)
            _ = ell_y(
                m,
                "palpbulb",
                rig.bone("palpTarsus" + side),
                lerp(a, b, 0.5),
                b - a,
                d.mm(
                    V3(
                        0.65 * (0.62 * f * d.palp_bulb + 0.3 * f),
                        length(b - a) / q * 0.36,
                        0.65 * (0.7 * f * d.palp_bulb + 0.3 * f),
                    )
                ),
                k=0.2 * q * f,
            )

    # LEGS: the coxa is set into the prosoma between the carapace margin
    # and the sternum. The rest of the leg is a limb, with swollen joint
    # condyles, the knee the biggest.
    var names = _leg_names()
    for side in [String("L"), String("R")]:  # pragma: no branch
        for i in range(1, 5):  # pragma: no branch
            var thick = d.hind_r if i == 4 else (
                (1.0 + d.hind_r) / 2.0 if i == 3 else 1.0
            )
            var leg = String(i) + side
            for k in range(SEGS):  # pragma: no branch
                var a = rig.j(names[k] + leg)
                var b = rig.j(names[k + 1] + leg)
                var bone = rig.bone(names[k] + leg)
                var ra = max(d.leg_r0[k] * thick * q, min_r)
                var rb = max(d.leg_r1[k] * thick * q, min_r)
                if k == 0:
                    _ = m.cone(
                        "coxa",
                        bone,
                        a + normalize(b - a) * (-0.6 * q * f),
                        b,
                        ra,
                        rb,
                        k=0.55 * q * f,
                    )
                    continue
                _ = m.cone(
                    names[k], bone, a, b, ra, rb, k=0.07 * q * f, part=LIMB
                )
                if k < SEGS - 1:
                    _ = m.sphere(
                        "knuckle",
                        bone,
                        b + normalize(b - a) * (-d.leg_r1[k] * 0.25 * q),
                        max(
                            d.leg_r1[k]
                            * thick
                            * (1.12 if k == 2 else 1.06)
                            * q,
                            min_r,
                        ),
                        k=0.07 * q * f,
                        part=LIMB,
                    )
            # The claw tuft: the rounded tip of the tarsus.
            var tip = rig.j("claw" + leg)
            var ta = rig.j("tarsus" + leg)
            _ = m.sphere(
                "claws",
                rig.bone("tarsus" + leg),
                tip + normalize(ta - tip) * (d.leg_r1[6] * 0.3 * q),
                max(d.leg_r1[6] * thick * 1.02 * q, min_r),
                k=0.06 * q * f,
                part=LIMB,
            )


def spider_look(t: Traits) -> EyeLook:
    """Return the spider's eye colors: a glossy black dome with a faint
    amber glint of the tapetum.

    Args:
        t: The individual.

    Returns:
        The look.
    """
    _ = t
    return EyeLook(
        V3(0.02, 0.02, 0.02),
        V3(0.035, 0.032, 0.026),
        V3(0.12, 0.07, 0.022),
        V3(0.02, 0.02, 0.02),
        0.45,
        0.0,
    )


def _swatches() -> List[String]:
    return [
        String("carapace"),
        "stripe",
        "margin",
        "abdomen",
        "heart",
        "chevron",
        "abdSide",
        "leg",
        "legBand",
        "legDark",
        "legRing",
        "chel",
        "chelHair",
        "venter",
        "ocular",
        "fang",
        "palp",
        "spinneret",
        "tarsusTip",
    ]


def _wolf_hexes() -> List[Int]:
    return [
        0x3A2B1F,
        0xA08A6A,
        0x8C7657,
        0x4E3B2A,
        0x261B13,
        0x8E7A5C,
        0x5D4935,
        0x5F4A35,
        0x9A8465,
        0x33261B,
        0x9A8465,
        0x1F1812,
        0x6A4A2C,
        0x1A1512,
        0x0D0B09,
        0x160F0B,
        0x5A4633,
        0x6E5A44,
        0x5F4A35,
    ]


def _tarantula_hexes(morph: Int) -> List[Int]:
    # Red-knee: velvet black, orange knee bands, pale rings and a tan
    # carapace margin. Rosy: pinkish brown. Pinktoe: black with pink tarsi.
    var h: List[Int] = [
        0x17120F,
        0x17120F,
        0xC3884B,
        0x1A1411,
        0x120D0B,
        0x6B3A22,
        0x1C1512,
        0x15110E,
        0xD9651E,
        0x0F0C0A,
        0xE0A068,
        0x120E0C,
        0x2A1D16,
        0x0E0B09,
        0x0A0908,
        0x0E0A08,
        0x16120F,
        0x201813,
        0x15110E,
    ]
    if morph == ROSY:
        h[0] = 0x6E4C40
        h[2] = 0x9A7462
        h[3] = 0x5E4036
        h[5] = 0x8A5A4A
        h[6] = 0x5A3E34
        h[7] = 0x4A3530
        h[8] = 0x86645A
        h[10] = 0x9A7A6C
        h[9] = 0x35261F
        h[12] = 0x6A4A3E
        h[16] = 0x4A3530
        h[18] = 0x4A3530
    elif morph == PINKTOE:
        h[0] = 0x1B191D
        h[2] = 0x2A2630
        h[3] = 0x1C1A1E
        h[5] = 0x3A3036
        h[6] = 0x1C1A1E
        h[7] = 0x1A181C
        h[8] = 0x2C2830
        h[10] = 0x2C2830
        h[9] = 0x121014
        h[18] = 0xE07A7A
        h[16] = 0x1A181C
    return h^


def spider_palette(t: Traits) -> Palette:
    """Return one spider's palette.

    A wolf spider is warmed or cooled, lightened, and grayed from a brown
    Hogna toward a gray Pardosa-like individual. A tarantula wears its
    morph, lightened.

    Args:
        t: The individual.

    Returns:
        The palette, in linear light.
    """
    var names = _swatches()
    var w = t.get("coatWarmth", 0.0)
    var l = t.get("coatLightness", 0.0)
    var out = Palette()
    if t.variant == WOLF:
        var hexes = _wolf_hexes()
        debug_assert(
            len(names) == len(hexes), "A palette needs one color per name"
        )
        var gr = t.get("coatGray", 0.0)
        for i in range(len(names)):  # pragma: no branch
            var c = srgb(hexes[i])
            # The chelicerae, the venter, the eyes and the fangs keep
            # their color.
            var fixed = (
                names[i] == "chel"
                or names[i] == "venter"
                or names[i] == "ocular"
                or names[i] == "fang"
            )
            if not fixed:
                var r = c.x * (1.0 + 0.12 * w + l)
                var g = c.y * (1.0 + 0.03 * w + l)
                var b = c.z * (1.0 - 0.12 * w + l)
                var y = 0.3 * r + 0.55 * g + 0.15 * b
                c = V3(mix(r, y, gr), mix(g, y, gr), mix(b, y * 1.04, gr))
            out.set(names[i], c)
        return out^
    var hexes = _tarantula_hexes(Int(t.get("morph", 0.0)))
    debug_assert(len(names) == len(hexes), "A palette needs one color per name")
    for i in range(len(names)):  # pragma: no branch
        out.set(names[i], srgb(hexes[i]) * (1.0 + l))
    return out^


def _seg_of(name: String) -> Int:
    # The segment index of a leg or palp bone, or -1.
    var segs: List[String] = [
        String("coxa"),
        "troch",
        "femur",
        "patella",
        "tibia",
        "meta",
        "tarsus",
    ]
    var palps: List[String] = [
        String("palpCoxa"),
        "palpTroch",
        "palpFemur",
        "palpPatella",
        "palpTibia",
        "palpTarsus",
    ]
    var palp_seg: List[Int] = [0, 1, 2, 3, 4, 6]
    for k in range(len(palps)):  # pragma: no branch
        if name.startswith(palps[k]):
            return palp_seg[k]
    for k in range(len(segs)):  # pragma: no branch
        if name.startswith(segs[k]):
            return k
    return -1


def _half_w(d: _Dims, z: Float64, z0: Float64, lc: Float64) -> Float64:
    # The carapace's half width along z: a pear, widest behind the middle,
    # with a narrow head.
    var u = (z - z0) / lc
    var w_max = d.car_wid * 0.5 * d.q
    var w_head = d.car_head_w * 0.5 * d.q
    if u < 0.45:
        var a = (0.45 - u) / 0.47
        return w_max * sqrt(max(0.05, 1.0 - a * a))
    return mix(w_max, w_head, smoothstep(0.45, 0.85, u))


def _hair(p: V3, a: V3, axis: V3, mm: Float64) -> Float64:
    # Setae lying along a segment: noise drawn out along its axis, fine
    # across it.
    var side = normalize(cross(axis, V3(0.0, 1.0, 0.0001)))
    var up = cross(side, axis)
    var dp = p - a
    var h = V3(
        dot(dp, side) / (0.09 * mm),
        dot(dp, up) / (0.09 * mm),
        dot(dp, axis) / (0.9 * mm),
    )
    return fbm3(h, 2) - 0.5


def spider_paint(
    pal: Palette, t: Traits, tag: String, bone: String, s: CoatSample
) -> Paint:
    """Paint one vertex of a spider.

    The wolf spider has a dark brown carapace with a pale median band,
    pale submarginal bands and dark striae radiating from the fovea, a
    black ocular area, a dark lanceolate heart mark on the abdomen with
    pale spots and chevrons behind it, banded legs and a black venter.
    The red-knee tarantula is velvet black with orange knee bands, pale
    rings, a tan carapace margin and reddish abdominal setae. The setae
    streak the legs along their length.

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
    var d = _Dims(t)
    var wolf = d.wolf
    var f = d.f()
    var q = d.q
    # A wolf-spider millimeter, and the pattern scale of the original's
    # cheetah-equivalent meters.
    var mmu = 0.001 * f * q / 0.001
    var pk = 0.33 / d.unit * (0.001 / q)
    var contrast = t.get("patternContrast")
    var morph = Int(t.get("morph", 0.0))
    if tag == "eyedome":
        var glint = smoothstep(0.3, 0.9, dot(n, normalize(V3(0.3, 0.8, 0.5))))
        return Paint(
            mix3(V3(0.02, 0.018, 0.016), V3(0.1, 0.06, 0.02), glint * 0.4), EYE
        )
    if tag == "fang":
        return Paint(pal.get("fang"), KERATIN)
    var noise = fbm3(p * (1.0 / (1.6 * mmu)), 3) - 0.5
    var noise_f = fbm3(p * (1.0 / (0.45 * mmu)) + V3(7, 0, 0), 2) - 0.5
    var col: V3
    var surface = CHITIN
    var pat = 1.0
    var pcol = pal.get("stripe")
    var pint = 0.0
    var mk = 1.0
    var hair: Float64
    var seg = _seg_of(bone)
    if bone.startswith("chelicera"):
        # Hair on the front face, bare glossy cuticle near the fang base.
        var side = "L" if bone.endswith("L") else "R"
        var sgn = 1.0 if side == "L" else -1.0
        var b0 = d.mm(d.chel_base)
        var b1 = d.mm(d.chel_tip)
        b0 = V3(b0.x * sgn, b0.y, b0.z)
        b1 = V3(b1.x * sgn, b1.y, b1.z)
        var ax = b1 - b0
        var u = dot(p - b0, normalize(ax)) / length(ax)
        col = mix3(
            pal.get("chel"),
            pal.get("chelHair"),
            clamp(0.5 + noise, 0.0, 1.0)
            * (0.35 if wolf else 0.5)
            * (1.0 - smoothstep(0.6, 0.9, u)),
        )
        hair = _hair(p, b0, normalize(ax), mmu) * (
            1.0 - smoothstep(0.7, 0.95, u)
        )
        if not wolf:
            surface = FUR
    elif seg >= 0:
        # Legs and palps: pale joint bands and a darker underside.
        var palp = bone.startswith("palp")
        var sgn = 1.0 if bone.endswith("L") else -1.0
        var chain: List[V3]
        if palp:
            chain = _palp_chain(d)
        else:
            var digit = String(
                bone[byte = bone.byte_length() - 2 : bone.byte_length() - 1]
            )
            var i = 0
            for c in range(1, 5):  # pragma: no branch
                if digit == String(c):
                    i = c - 1
            chain = _leg_chain(d, i)
        var k = seg if not palp else (5 if seg == 6 else seg)
        var a = chain[k]
        var e = chain[k + 1]
        a = V3(a.x * sgn, a.y, a.z)
        e = V3(e.x * sgn, e.y, e.z)
        var ax = e - a
        var l = length(ax)
        var u = clamp(dot(p - a, ax) / (l * l), 0.0, 1.0)
        var up = n.y
        col = pal.get("palp") if palp else pal.get("leg")
        if seg <= 1:
            col = mix3(pal.get("venter"), col, smoothstep(-0.2, 0.6, up))
        var band_d = 1e9
        var band_col = pal.get("legBand")
        var along = u * l
        var banded = morph == REDKNEE or morph == ROSY
        if wolf:
            if seg == 2:
                band_d = min(
                    abs(along - l * 0.18) - 0.35 * mmu,
                    abs(along - l * 0.62) - 0.4 * mmu,
                )
            elif seg == 3:
                band_d = abs(along - l * 0.5) - l * 0.22
            elif seg == 4:
                band_d = min(
                    abs(along - l * 0.2) - 0.45 * mmu,
                    abs(along - l * 0.72) - 0.4 * mmu,
                )
            elif seg == 5:
                band_d = abs(along - l * 0.12) - 0.3 * mmu
            # Diffuse, mottled banding of the setae, not crisp rings.
            band_d += 0.35 * mmu * noise_f + 0.25 * mmu * noise
        elif banded:
            if seg == 3:
                # The top of the patella.
                band_d = -0.2 * mmu + (0.25 - up) * 1.4 * mmu
            elif seg == 2:
                band_d = (l - along) - 0.12 * l + (0.2 - up) * 1.2 * mmu
            elif seg == 4:
                band_d = (
                    min(l - along - 0.07 * l, along - 0.04 * l)
                    + (0.1 - up) * 0.8 * mmu
                )
                band_col = pal.get("legRing")
            elif seg == 5:
                band_d = (l - along) - 0.06 * l + (0.1 - up) * 0.8 * mmu
                band_col = pal.get("legRing")
            # The "knee" stripes run lengthwise along the patella and the
            # tibia top.
            var knee = seg == 3 or seg == 4
            if knee:
                band_d = min(
                    band_d,
                    abs(dot(normalize(cross(ax, V3(0, 1, 0))), p - a))
                    - 0.4 * mmu
                    + (0.5 - up) * 2.0 * mmu,
                )
        else:
            var toe = seg == 6 and not palp
            if toe:
                col = pal.get("tarsusTip")
        if band_d < 1e8:
            pat = band_d * pk * (0.33 if wolf else 1.0)
            pcol = band_col
            pint = contrast * (0.6 if wolf else 1.0)
        # A darker underside and joint membranes.
        col = mix3(col, pal.get("legDark"), smoothstep(0.1, -0.7, up) * 0.4)
        hair = _hair(p, a, normalize(ax), mmu)
        # Dense setae: matte.
        surface = FUR
    elif _abdominal(bone):
        # The abdomen: a dorsal heart mark and chevrons, a dark venter.
        var c = d.mm(d.abd_c)
        var r = d.mm(d.abd_r)
        var u = (p.z - c.z) / r.z
        var up = n.y
        var dors = smoothstep(-0.1, 0.55, up)
        col = mix3(
            pal.get("venter"),
            mix3(pal.get("abdSide"), pal.get("abdomen"), dors),
            smoothstep(-0.75, -0.2, up),
        )
        if wolf:
            # The lanceolate heart mark: a dark spear along the front half
            # of the midline, pale chevrons over the rear half.
            var hw = mix(0.95, 0.15, clamp((0.95 - u) / 1.0, 0.0, 1.0)) * mmu
            var heart = (abs(p.x) - hw * (1.0 if u > -0.1 else 0.0)) / mmu
            col = mix3(
                col,
                pal.get("heart"),
                smoothstep(0.3, -0.2, heart)
                * dors
                * contrast
                * smoothstep(-0.2, 0.2, u),
            )
            var rim = u > -0.05 and u < 0.95
            if rim:
                mk = min(
                    mk,
                    (abs(abs(p.x) - hw) - 0.08 * mmu)
                    * pk
                    / (1.0 if dors > 0.3 else 1e3),
                )
            # Pairs of pale spots flanking the midline, joined by faint,
            # broken chevrons.
            var spots = 1e9
            var chev = 1e9
            for k in range(4):  # pragma: no branch
                var uz = -0.12 - Float64(k) * 0.2
                var sx = abs(p.x) - r.x * (0.3 - 0.03 * Float64(k))
                var sz = (u - uz) * r.z
                spots = min(
                    spots,
                    sqrt(sx * sx + sz * sz)
                    - 0.32 * mmu * (1.0 - 0.15 * Float64(k)),
                )
                var vz = uz + abs(p.x) / r.x * 0.25
                chev = min(
                    chev,
                    abs(u - vz) * r.z - 0.1 * mmu * (1.0 - 0.2 * Float64(k)),
                )
            chev = max(
                chev,
                max(abs(p.x) - r.x * 0.3, 0.25 * mmu * (noise_f + 0.2)),
            )
            # The pale flank bands framing the dorsum.
            var flank = abs(abs(p.x) / r.x - 0.72) * r.x - 0.35 * mmu
            pat = (
                (
                    min(min(spots, chev), flank + 0.3 * mmu * noise)
                    + 0.2 * mmu * noise_f
                )
                * pk
                * 0.6
            )
            pcol = pal.get("chevron")
            pint = dors * contrast * 0.8 * smoothstep(-0.35, 0.1, up)
            col = V3(
                col.x * (1.0 + 0.3 * noise_f),
                col.y * (1.0 + 0.28 * noise_f),
                col.z * (1.0 + 0.24 * noise_f),
            )
            hair = fbm3(p * (1.0 / (0.12 * mmu)), 2) - 0.5
        else:
            # Long reddish setae over black, strongest on the dorsum, and
            # sometimes a bald patch where the urticating hairs were
            # kicked off.
            pat = (-0.5 * mmu + 0.2 * mmu * noise) * pk
            pcol = pal.get("chevron")
            pint = smoothstep(-0.4, 0.3, up) * (0.4 + 0.3 * noise_f)
            var bald = t.get("bald", 0.0) > 0.5
            if bald:
                var bx = p.x / r.x
                var by = (p.y - c.y - r.y * 0.7) / r.y
                var bz = (p.z - c.z + r.z * 0.35) / r.z
                var bd = sqrt(bx * bx + by * by + bz * bz)
                var bare = 1.0 - smoothstep(0.28, 0.42, bd + 0.05 * noise)
                pint *= 1.0 - bare
                col = mix3(col, V3(0.004, 0.003, 0.003), bare * 0.6)
            hair = _hair(p, c, normalize(V3(0, -0.15 * u, -1.0)), mmu * 2.0)
        surface = FUR
        if bone == "spinnerets":
            col = pal.get("spinneret")
    else:
        # The prosoma: the carapace, the head and the sternum.
        var up = n.y
        var x = p.x
        var z = p.z
        var z0 = d.mm(d.ped_a).z
        var lc = d.mm(d.front).z - z0
        var w = _half_w(d, z, z0, lc)
        var dors = smoothstep(-0.15, 0.35, up)
        col = mix3(
            pal.get("venter"), pal.get("carapace"), smoothstep(-0.55, -0.1, up)
        )
        var u = (z - z0) / lc
        var rel = abs(x) / max(w, 1e-5)
        if wolf:
            # The median band: narrow between the eyes, widest over the
            # thorax, narrowing to the rear.
            var mw = (
                mix(0.5, 0.35, smoothstep(0.72, 0.95, u)) if u
                > 0.72 else mix(0.4, 0.85, smoothstep(0.1, 0.55, u))
            ) * mmu
            var median = abs(x) - mw + 0.12 * mmu * noise_f
            # The submarginal bands along the sides of the carapace.
            var sub1 = abs(rel - 0.8) * w - 0.13 * w + 0.1 * mmu * noise
            var subm = max(
                sub1, max((0.15 - up) * 3.0 * mmu, (u - 0.8) * 8.0 * mmu)
            )
            pat = min(median, subm) * pk
            pint = dors * contrast
            pcol = pal.get("stripe")
            # Dark striae radiating from the fovea.
            var fz = z0 + 0.36 * lc
            var st = 1e9
            for k in range(4):  # pragma: no branch
                var ang = -0.95 + Float64(k) * 0.62 + pi / 2.0
                var dx = sin(ang)
                var dz = cos(ang)
                var qx = abs(x)
                var qz = z - fz
                var along = qx * dx + qz * dz
                var inside = along > 0.4 * mmu and along < w * 0.95
                if inside:
                    st = min(
                        st,
                        abs(qx * dz - qz * dx) - 0.08 * mmu * (1.0 - along / w),
                    )
            if dors > 0.2:
                mk = min(mk, st * pk)
        else:
            # Velvet black with a tan margin.
            pat = (
                max(0.78 - rel, 0.0) * w * 1.0
                - 0.06 * mmu
                + (0.25 - up) * 0.5 * mmu
            ) * pk
            if up < -0.2:
                pat = 1.0
            pcol = pal.get("margin")
            pint = (0.3 if morph == PINKTOE else 1.0) * smoothstep(
                -0.2, 0.2, up
            )
        # The ocular area, and the tarantula's tubercle: bare, black and
        # glossy.
        var ceph = d.mm(d.ceph)
        var eye_d = 1e9
        for e in _eyes(wolf):  # pragma: no branch
            var spec = _spec(e, q, V3(0, 0, 0))
            for sd in [1.0, -1.0]:  # pragma: no branch
                var c = eye_frame_of(spec, ceph, sd).c
                eye_d = min(eye_d, length(p - c) - spec.r * 1.35)
        var reach = 0.5 * mmu * (1.0 if wolf else 0.6)
        if eye_d < reach:
            col = mix3(
                col, pal.get("ocular"), smoothstep(0.5 * mmu, 0.05 * mmu, eye_d)
            )
        hair = (fbm3(p * (1.0 / (0.12 * mmu)), 2) - 0.5) * smoothstep(
            0.05 * mmu, 0.6 * mmu, eye_d
        )
    # Low-frequency color noise.
    col = V3(
        col.x * (1.0 + 0.22 * noise),
        col.y * (1.0 + 0.2 * noise),
        col.z * (1.0 + 0.16 * noise),
    )
    var spot = smoothstep(0.003, -0.003, pat) * max(pint, 0.0)
    col = mix3(col, pcol, clamp(spot, 0.0, 1.0))
    var line = smoothstep(0.002, -0.002, mk)
    col = mix3(col, V3(0.012, 0.009, 0.007), line)
    # The setae: light and dark strands.
    col = col * (1.0 + (0.5 if wolf else 0.7) * hair)
    return Paint(col, surface)


def _abdominal(bone: String) -> Bool:
    return bone == "abdomen" or bone == "pedicel" or bone == "spinnerets"
