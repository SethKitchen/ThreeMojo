# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The teleost fish: procedural-animals' `species/fish/`.

Four body plans share one swimmer rig and one sculpt: the rainbow trout,
the goldfish, the ocellaris clownfish and the bluegill. Every length is a
fraction of the standard length `SL`, read from each variant's outline
table. The body is a dense chain of elliptic sections, the lower jaw is
its own surface, and every fin is a thin membrane.

The original meshes each variant at `SL / 300` times the variant's cell
factor. Here the reference fish is built with `SL` equal to one over that
factor, so one `CELL` serves all four, and the `size` trait scales it to
the variant's real length.
"""

from extensions.animals.coat import (
    SCALES,
    WET,
    CoatSample,
    EyeLook,
    Paint,
    Palette,
    mix3,
    palette_of,
    srgb,
)
from extensions.sdf.ids import BoneId
from extensions.animals.parts import JAW
from extensions.animals.kit import EyeSpec
from extensions.animals.noise import cells3, fbm3
from extensions.animals.options import AnimalOptions, AnimalRandom
from extensions.animals.rig import Rig
from extensions.sdf.field import SdfModel
from extensions.animals.species.swimmer_rig import (
    Profile,
    fan_rays,
    fin_plane_v,
    fin_ray_coords,
    offset_poly,
    sculpt_fin,
    spine_name,
    swimmer_bones,
)
from extensions.animals.traits import Traits, pick_age, pick_sex
from extensions.sdf.vector import (
    V3,
    clamp,
    dot,
    length,
    normalize,
    smoothstep,
)
from extensions.animals.warp import girth_warp, scale_about_warp
from std.math import cos, exp, floor, pi, pow, sin, sqrt

# The fish's head origin moves with the variant, so the eye is placed
# from the reference origin instead.
comptime HEAD_O = V3(0.0, 0.0, 0.0)
# The finest cell, at the `HERO` tier, for the reference fish: SL / 300.
comptime CELL = 1.0 / 300.0
# The lips in front of the mouth cavity, as a fraction of SL.
comptime MOUTH_LIP = 0.022

# The variants, in procedural-animals' order.
comptime TROUT = 0
comptime GOLDFISH = 1
comptime CLOWNFISH = 2
comptime BLUEGILL = 3

# The pectoral fin shapes.
comptime POINTED = 0
comptime ROUNDED = 1
comptime SICKLE = 2


def fish_variant_names() -> List[String]:
    """Return the fish's variants.

    Returns:
        Trout, goldfish, clownfish and bluegill.
    """
    return [String("trout"), "goldfish", "clownfish", "bluegill"]


@fieldwise_init
struct _Median(ImplicitlyCopyable):
    var u0: Float64
    var u1: Float64
    var n: Int
    var a0: Float64
    var a1: Float64
    var l0: Float64
    var l1: Float64
    var notch: Float64
    var spiny: Bool
    var round: Bool


struct _Variant(Movable):
    var sl: Float64
    var cell_k: Float64
    var prof: Profile
    var op: Float64
    var occ: Float64
    var eye_u: Float64
    var eye_h: Float64
    var eye_r: Float64
    var mouth_h: Float64
    var gape: Float64
    var jaw_depth: Float64
    var upturn: Float64
    var ear_flap: Float64
    var dorsal: List[_Median]
    var anal: List[_Median]
    var adipose: Bool
    var ad_u0: Float64
    var ad_u1: Float64
    var ad_h: Float64
    var c_len: Float64
    var c_fork: Float64
    var c_spread: Float64
    var c_n: Int
    var c_pointed: Bool
    var p_u: Float64
    var p_h: Float64
    var p_len: Float64
    var p_n: Int
    var p_sweep: Float64
    var p_droop: Float64
    var p_abduct: Float64
    var p_shape: Int
    var v_u: Float64
    var v_len: Float64
    var v_n: Int
    var v_sweep: Float64
    var v_abduct: Float64
    var spine_segs: Int
    var caudal_segs: Int
    var scale_fade: Float64

    def __init__(out self, rows: List[Float64]):
        self.sl = 0.26
        self.cell_k = 1.0
        self.prof = Profile(rows)
        self.op = 0.235
        self.occ = 0.19
        self.eye_u = 0.072
        self.eye_h = 0.03
        self.eye_r = 0.022
        self.mouth_h = -0.012
        self.gape = 0.105
        self.jaw_depth = 0.03
        self.upturn = 0.0
        self.ear_flap = 0.0
        self.dorsal = List[_Median]()
        self.anal = List[_Median]()
        self.adipose = False
        self.ad_u0 = 0.0
        self.ad_u1 = 0.0
        self.ad_h = 0.0
        self.c_len = 0.23
        self.c_fork = 0.18
        self.c_spread = 37.0
        self.c_n = 19
        self.c_pointed = True
        self.p_u = 0.245
        self.p_h = -0.07
        self.p_len = 0.13
        self.p_n = 12
        self.p_sweep = 38.0
        self.p_droop = 22.0
        self.p_abduct = 28.0
        self.p_shape = POINTED
        self.v_u = 0.5
        self.v_len = 0.105
        self.v_n = 9
        self.v_sweep = 22.0
        self.v_abduct = 25.0
        self.spine_segs = 12
        self.caudal_segs = 3
        self.scale_fade = 0.0


def _variant(key: Int) -> _Variant:
    if key == GOLDFISH:
        var v = _Variant(
            [
                0.012, 0.024, 0.016, 0.016,
                0.035, 0.05, 0.036, 0.034,
                0.07, 0.084, 0.064, 0.056,
                0.11, 0.113, 0.093, 0.074,
                0.17, 0.145, 0.123, 0.088,
                0.24, 0.172, 0.15, 0.097,
                0.33, 0.194, 0.172, 0.101,
                0.43, 0.2, 0.176, 0.097,
                0.53, 0.19, 0.162, 0.09,
                0.63, 0.166, 0.138, 0.078,
                0.73, 0.133, 0.109, 0.062,
                0.82, 0.102, 0.086, 0.046,
                0.9, 0.08, 0.071, 0.034,
                0.96, 0.071, 0.066, 0.028,
                1.0, 0.073, 0.069, 0.024,
            ]
        )  # fmt: skip
        v.sl = 0.125
        v.cell_k = 1.33
        v.op = 0.275
        v.occ = 0.22
        v.eye_u = 0.105
        v.eye_h = 0.046
        v.eye_r = 0.036
        v.mouth_h = -0.008
        v.gape = 0.036
        v.jaw_depth = 0.026
        v.upturn = 0.3
        v.dorsal.append(
            _Median(0.42, 0.77, 16, 108, 150, 0.22, 0.075, 0, False, False)
        )
        v.anal.append(
            _Median(0.72, 0.815, 7, 238, 214, 0.22, 0.12, 0, False, False)
        )
        v.c_len = 0.36
        v.c_fork = 0.45
        v.c_spread = 38.0
        v.c_n = 19
        v.c_pointed = False
        v.p_u = 0.29
        v.p_h = -0.13
        v.p_len = 0.23
        v.p_n = 14
        v.p_sweep = 40.0
        v.p_droop = 26.0
        v.p_abduct = 32.0
        v.p_shape = ROUNDED
        v.v_u = 0.48
        v.v_len = 0.23
        v.v_n = 9
        v.v_sweep = 26.0
        v.v_abduct = 28.0
        v.scale_fade = 0.03
        return v^
    if key == CLOWNFISH:
        var v = _Variant(
            [
                0.012, 0.03, 0.022, 0.018,
                0.035, 0.066, 0.05, 0.04,
                0.07, 0.106, 0.084, 0.06,
                0.12, 0.145, 0.12, 0.08,
                0.2, 0.183, 0.16, 0.097,
                0.3, 0.206, 0.188, 0.103,
                0.4, 0.21, 0.198, 0.1,
                0.5, 0.2, 0.19, 0.094,
                0.6, 0.18, 0.17, 0.084,
                0.7, 0.152, 0.142, 0.07,
                0.8, 0.118, 0.112, 0.055,
                0.9, 0.092, 0.087, 0.04,
                0.96, 0.083, 0.08, 0.033,
                1.0, 0.085, 0.082, 0.029,
            ]
        )  # fmt: skip
        v.sl = 0.068
        v.cell_k = 1.45
        v.op = 0.315
        v.occ = 0.26
        v.eye_u = 0.12
        v.eye_h = 0.055
        v.eye_r = 0.046
        v.mouth_h = -0.02
        v.gape = 0.055
        v.jaw_depth = 0.04
        v.upturn = 0.2
        v.dorsal.append(
            _Median(0.3, 0.55, 10, 100, 128, 0.1, 0.085, 0.15, True, False)
        )
        v.dorsal.append(
            _Median(0.55, 0.88, 15, 112, 158, 0.16, 0.1, 0, False, True)
        )
        v.anal.append(
            _Median(0.62, 0.85, 12, 250, 205, 0.15, 0.1, 0, False, True)
        )
        v.c_len = 0.24
        v.c_fork = -0.08
        v.c_spread = 36.0
        v.c_n = 17
        v.c_pointed = False
        v.p_u = 0.33
        v.p_h = -0.035
        v.p_len = 0.21
        v.p_n = 14
        v.p_sweep = 30.0
        v.p_droop = 10.0
        v.p_abduct = 35.0
        v.p_shape = ROUNDED
        v.v_u = 0.38
        v.v_len = 0.17
        v.v_n = 6
        v.v_sweep = 30.0
        v.v_abduct = 30.0
        v.caudal_segs = 2
        return v^
    if key == BLUEGILL:
        var v = _Variant(
            [
                0.012, 0.03, 0.022, 0.014,
                0.035, 0.072, 0.052, 0.028,
                0.07, 0.12, 0.09, 0.043,
                0.12, 0.168, 0.138, 0.06,
                0.2, 0.218, 0.196, 0.075,
                0.3, 0.254, 0.228, 0.083,
                0.4, 0.262, 0.238, 0.083,
                0.5, 0.25, 0.224, 0.078,
                0.6, 0.222, 0.196, 0.07,
                0.7, 0.178, 0.156, 0.058,
                0.8, 0.124, 0.11, 0.044,
                0.88, 0.087, 0.078, 0.033,
                0.95, 0.07, 0.065, 0.026,
                1.0, 0.07, 0.067, 0.022,
            ]
        )  # fmt: skip
        v.sl = 0.155
        v.cell_k = 1.38
        v.op = 0.315
        v.occ = 0.25
        v.eye_u = 0.118
        v.eye_h = 0.065
        v.eye_r = 0.042
        v.mouth_h = -0.01
        v.gape = 0.05
        v.jaw_depth = 0.035
        v.upturn = 0.25
        v.ear_flap = 0.055
        v.dorsal.append(
            _Median(0.36, 0.6, 10, 104, 125, 0.13, 0.12, 0.25, True, False)
        )
        v.dorsal.append(
            _Median(0.6, 0.88, 12, 112, 160, 0.18, 0.1, 0, False, True)
        )
        v.anal.append(
            _Median(0.6, 0.87, 13, 252, 205, 0.15, 0.1, 0, False, True)
        )
        v.c_len = 0.23
        v.c_fork = 0.1
        v.c_spread = 36.0
        v.c_n = 17
        v.c_pointed = False
        v.p_u = 0.33
        v.p_h = -0.03
        v.p_len = 0.28
        v.p_n = 13
        v.p_sweep = 25.0
        v.p_droop = -12.0
        v.p_abduct = 30.0
        v.p_shape = SICKLE
        v.v_u = 0.36
        v.v_len = 0.15
        v.v_n = 6
        v.v_sweep = 30.0
        v.v_abduct = 30.0
        return v^
    var v = _Variant(
        [
            0.012, 0.016, 0.012, 0.012,
            0.03, 0.028, 0.022, 0.022,
            0.06, 0.0497, 0.0432, 0.034,
            0.1, 0.0691, 0.0648, 0.045,
            0.16, 0.0886, 0.0842, 0.055,
            0.23, 0.1048, 0.1004, 0.062,
            0.32, 0.1188, 0.1145, 0.066,
            0.42, 0.1264, 0.1188, 0.066,
            0.52, 0.121, 0.1112, 0.061,
            0.62, 0.1058, 0.095, 0.053,
            0.72, 0.0864, 0.0756, 0.042,
            0.82, 0.068, 0.0594, 0.031,
            0.9, 0.0572, 0.0508, 0.023,
            0.96, 0.054, 0.0497, 0.018,
            1.0, 0.0562, 0.054, 0.015,
        ]
    )  # fmt: skip
    v.dorsal.append(
        _Median(0.42, 0.565, 12, 118, 150, 0.135, 0.05, 0, False, False)
    )
    v.anal.append(
        _Median(0.675, 0.79, 10, 238, 208, 0.11, 0.045, 0, False, False)
    )
    v.adipose = True
    v.ad_u0 = 0.79
    v.ad_u1 = 0.845
    v.ad_h = 0.03
    return v^


struct _Geo(Movable):
    # The original's `fishGeo`: outline lookups in reference meters and
    # the landmarks.
    var v: _Variant
    var sl: Float64
    var axis_y: Float64
    var z0: Float64
    var tail_len: Float64
    var fin_k: Float64
    var mouth_y: Float64
    var eye_y: Float64
    var eye_r: Float64
    var eye_z: Float64
    var eye_x: Float64
    var head_o: V3

    def __init__(out self, key: Int, tail_k: Float64, fin_k: Float64):
        self.v = _variant(key)
        self.sl = 1.0 / self.v.cell_k
        self.axis_y = (self.v.prof.max_of(2) + 0.04) * self.sl
        self.z0 = 0.42 * self.sl
        self.tail_len = self.v.c_len * tail_k
        self.fin_k = fin_k
        self.mouth_y = self.axis_y + self.v.mouth_h * self.sl
        self.eye_y = self.axis_y + self.v.eye_h * self.sl
        self.eye_r = self.v.eye_r * self.sl
        self.eye_z = self.z0 - self.v.eye_u * self.sl
        self.eye_x = 0.0
        self.head_o = V3(0.0, self.eye_y, self.eye_z)
        self.eye_x = self.surf_x(self.v.eye_u, self.eye_y) - 0.62 * self.eye_r

    def z(self, u: Float64) -> Float64:
        return self.z0 - u * self.sl

    def u(self, z: Float64) -> Float64:
        return (self.z0 - z) / self.sl

    def hw(self, u: Float64) -> Float64:
        return self.v.prof.at(u, 3) * self.sl

    def yc(self, u: Float64) -> Float64:
        return (
            self.axis_y
            + (self.v.prof.at(u, 1) - self.v.prof.at(u, 2)) / 2.0 * self.sl
        )

    def hd(self, u: Float64) -> Float64:
        return (self.v.prof.at(u, 1) + self.v.prof.at(u, 2)) / 2.0 * self.sl

    def surf_x(self, u: Float64, y: Float64) -> Float64:
        var e = (y - self.yc(u)) / max(1e-6, self.hd(u))
        return self.hw(u) * sqrt(max(0.0, 1.0 - e * e))

    def flank(self, u: Float64, e: Float64, s: Float64 = 1.0) -> V3:
        var y = self.yc(u) + e * self.hd(u)
        return V3(s * self.surf_x(u, y), y, self.z(u))

    def pick_parent(self, u: Float64) -> String:
        var n = self.v.spine_segs
        var occ = self.v.occ
        var i = Int(floor((u - occ) / (1.0 - occ) * Float64(n)))
        return spine_name(max(0, min(n - 1, i)))

    def bone_at(self, u: Float64) -> String:
        return String("head") if u < self.v.occ else self.pick_parent(u)


def _geo(t: Traits) -> _Geo:
    return _Geo(t.variant, t.get("tailK"), t.get("finK"))


def _fin_dir(
    sweep: Float64, droop: Float64, abduct: Float64, ventral: Bool = False
) -> V3:
    var d2r = pi / 180.0
    if ventral:
        var back = cos(abduct * d2r)
        var side = sin(abduct * d2r)
        return normalize(
            V3(side * 0.8, -sin((90.0 - droop) * d2r) * 0.55 - 0.25, -back)
        )
    var ab = abduct * d2r
    var dr = droop * d2r
    return normalize(V3(sin(ab), -sin(dr), -cos(ab) * cos(dr)))


def _op_edge_u(op: Float64, e: Float64) -> Float64:
    # The free rear edge of the gill cover, at height `e`.
    return op + 0.003 - 0.045 * min(1.44, e * e)


def _skin_x(g: _Geo, u0: Float64, y: Float64) -> Float64:
    # Where the body's skin is, out along x at `u0` and height `y`: the
    # sections near `u0`, blended as the sculpt blends them.
    var m = SdfModel()
    var sl = g.sl
    var u = 0.012
    try:
        while u <= 1.0001:
            var uu = min(u, 1.0)
            if abs(uu - u0) < 0.08:
                _ = m.ell(
                    "body",
                    BoneId(0),
                    V3(0.0, g.yc(uu), g.z(uu)),
                    V3(g.hw(uu), g.hd(uu), min(0.05, uu * 0.95 + 0.004) * sl),
                    k=0.007 * sl,
                )
            u += 0.018
    except:
        return g.surf_x(u0, y)
    var ids = List[Int]()
    for i in range(len(m.prims)):
        ids.append(i)
    var lo = 0.0
    var hi = g.hw(u0) * 2.0
    var z = g.z(u0)
    for _ in range(40):
        var mid = 0.5 * (lo + hi)
        if m.eval_list(ids, V3(mid, y, z)) < 0.0:
            lo = mid
        else:
            hi = mid
    return 0.5 * (lo + hi)


def fish_traits(mut r: AnimalRandom, options: AnimalOptions) raises -> Traits:
    """Draw one fish: procedural-animals' `variation`.

    Within a variant the draw sets the size, the body depth, the head
    size, a color morph from its own hashed stream, the sex (bluegill
    breeding colors, larger clownfish females), and young fish are
    smaller with bigger heads and eyes.

    Args:
        r: The individual's stream.
        options: The caller's sex, age and variant.

    Returns:
        The traits.

    Raises:
        Error: If the requested variant is not one of the four.
    """
    var variant: Int
    if options.variant.value < 0:
        variant = Int(r.next() * 4.0) % 4
    else:
        if options.variant.value >= 4:
            raise Error("The species has no such color variant")
        variant = options.variant.value
    var sex = pick_sex(options.sex, r)
    var age = pick_age(options.age)
    var t = Traits(sex, age, variant)
    var juv = t.juvenile() > 0.0
    var male = t.male()
    var g = _Geo(variant, 1.0, 1.0)
    var sex_k = 1.0
    if variant == CLOWNFISH:
        sex_k = 0.86 if male else 1.1
    if variant == TROUT:
        sex_k = 1.04 if male else 0.97
    var size = sex_k * (1.0 + 0.1 * r.g()) * (0.45 if juv else 1.0)
    # The morph draws from its own hashed stream, so consecutive seeds
    # do not correlate.
    var a = UInt64((options.seed + 0x632BE5AB) & 0xFFFFFFFF)
    var m_seed = Int(((a * UInt64(0x9E3779B1)) & 0xFFFFFFFF) ^ 0x5BD1E995)
    var mr = AnimalRandom(m_seed, 1, 0)
    for _ in range(4):
        _ = mr.next()
    var morph = 0
    if variant == TROUT:
        morph = _pick(mr.next(), [0.72, 0.28])
    if variant == GOLDFISH:
        morph = _pick(mr.next(), [0.55, 0.17, 0.2, 0.08])
    if variant == CLOWNFISH:
        morph = _pick(mr.next(), [0.9, 0.1])
    var shade_m = mr.next()
    var sl = g.sl
    var female_trout = variant == TROUT and not male
    var depth_k = 1.0 + 0.05 * r.g() + (0.02 if female_trout else 0.0)
    t.set("morph", Float64(morph))
    t.warps.add(girth_warp(depth_k, g.axis_y, g.z(0.95), g.z(0.15), 0.12 * sl))
    t.warps.add(
        scale_about_warp(
            g.head_o,
            (1.0 + 0.035 * r.g()) * (1.14 if juv else 1.0),
            0.12 * sl,
            0.3 * sl,
        )
    )
    t.set("coatShade", 0.6 * r.g())
    var common_goldfish = variant == GOLDFISH and morph == 0
    t.set("hueShift", shade_m if common_goldfish else 0.5)
    t.set("coatSeed", Float64(Int(r.next() * 1e6)))
    var band_k = 1.0
    if variant == TROUT:
        band_k = (0.3 if morph == 1 else 0.8 + 0.25 * r.next()) * (
            1.15 if male else 0.9
        )
    t.set("bandK", band_k)
    var bar_k = 1.0
    if variant == BLUEGILL:
        bar_k = (0.8 if male else 1.1) * (0.8 + 0.4 * r.next())
    t.set("barK", bar_k)
    var edge_k = 1.0
    if variant == CLOWNFISH:
        edge_k = 0.8 + 0.5 * r.next()
    t.set("edgeK", edge_k)
    t.set("spotScale", 0.8 + 0.4 * r.next())
    var long_tail = False
    if variant == GOLDFISH and morph != 0:
        long_tail = r.next() < 0.5
    t.set("tailK", (1.3 if long_tail else 1.0) * (1.0 + 0.06 * r.g()))
    t.set("finK", 1.0 + 0.07 * r.g() + (0.08 if juv else 0.0))
    # The reference fish is SL = 1 / cellK long: `size` makes it real.
    t.set("size", size * g.v.sl * g.v.cell_k)
    t.set("minThick", CELL * 1.15)
    return t^


def _pick(x: Float64, weights: List[Float64]) -> Int:
    var acc = 0.0
    for i in range(len(weights)):
        acc += weights[i]
        if x < acc:
            return i
    return len(weights) - 1


def fish_eye(t: Traits) -> EyeSpec:
    """Return the fish's left eye: lidless, flush with the head, looking
    out to the side.

    Args:
        t: The individual. The eye follows the variant's head.

    Returns:
        The eye, from the reference origin.
    """
    var g = _geo(t)
    var r = g.eye_r
    # The smooth unions of the sections stand proud of the outline table:
    # the eye sits at the real skin, so only a shallow cap shows.
    var x = _skin_x(g, g.v.eye_u, g.eye_y) - 0.62 * r
    return EyeSpec(
        V3(x, g.eye_y, g.eye_z),
        r,
        0.0,
        1.28,
        0.1,
        0.0,
        r,
        0.0,
        0.0,
        0.0,
        r * 0.42,
        r * 0.86,
    )


def fish_look(t: Traits) -> EyeLook:
    """Return the fish's eye colors: each variant's iris and a round pupil.

    Args:
        t: The individual.

    Returns:
        The look.
    """
    var iris: List[Int]
    if t.variant == GOLDFISH:
        iris = [0x3B2A0C, 0xA8781F, 0xD8AE52, 0x2C1E08]
    elif t.variant == CLOWNFISH:
        iris = [0x2A1004, 0xC2561A, 0xEA8A3C, 0x0C0604]
    elif t.variant == BLUEGILL:
        iris = [0x1C0A06, 0x5E2418, 0x8A3C26, 0x120604]
    else:
        iris = [0x3A3522, 0xB7A76E, 0xD8CC98, 0x2A2618]
    return EyeLook(
        srgb(iris[0]),
        mix3(srgb(iris[1]), srgb(iris[2]), 0.35),
        srgb(iris[3]),
        V3(0.05, 0.05, 0.05),
        0.38,
        0.0,
    )


def fish_rig(t: Traits) raises -> Rig:
    """Return the fish's skeleton in bind pose: the swimmer bone set.

    Every landmark comes from the variant's outline table.

    Args:
        t: The individual.

    Returns:
        The rig.

    Raises:
        Error: If a bone names a missing joint.
    """
    var g = _geo(t)
    var sl = g.sl
    var n = g.v.spine_segs
    var m = g.v.caudal_segs
    var rig = Rig()
    rig.set("snout", V3(0.0, g.mouth_y + 0.004 * sl, g.z0))
    for i in range(n + 1):
        var u = g.v.occ + (1.0 - g.v.occ) * Float64(i) / Float64(n)
        rig.set(spine_name(i), V3(0.0, g.yc(u), g.z(u)))
    rig.set("caudal0", rig.j(spine_name(n)))
    var cl = g.tail_len * 0.86
    for j in range(1, m + 1):
        rig.set(
            "caudal" + String(j),
            V3(0.0, g.yc(1.0), g.z(1.0 + cl * Float64(j) / Float64(m))),
        )
    var gape = g.v.gape
    rig.set(
        "jawHinge",
        V3(0.0, g.mouth_y - g.v.jaw_depth * sl * 0.55, g.z(gape + 0.02)),
    )
    rig.set("jawTip", V3(0.0, g.mouth_y - 0.006 * sl, g.z(0.004)))
    rig.set("premaxBase", V3(0.0, g.mouth_y + 0.03 * sl, g.z(gape * 0.85)))
    rig.set("premaxTip", V3(0.0, g.mouth_y + 0.008 * sl, g.z(0.0)))
    var op = g.v.op
    rig.set("opHingeL", g.flank(op - 0.075, 0.5))
    rig.set("opLowL", g.flank(op - 0.1, -0.45))
    rig.set("opEdgeL", g.flank(op, 0.05))
    var pu = g.v.p_u
    var pb = g.flank(pu, (g.v.p_h * sl - (g.yc(pu) - g.axis_y)) / g.hd(pu))
    pb = V3(pb.x + 0.004 * sl, pb.y, pb.z)
    rig.set("pecBaseL", pb)
    rig.set("pecUpL", pb + V3(-0.004 * sl, 0.03 * sl, 0.008 * sl))
    rig.set(
        "pecTipL",
        pb
        + _fin_dir(g.v.p_sweep, g.v.p_droop, g.v.p_abduct)
        * (g.v.p_len * g.fin_k * sl),
    )
    var qu = g.v.v_u
    var px = g.hw(qu) * 0.42
    var py = (
        g.yc(qu) - g.hd(qu) * sqrt(1.0 - pow(px / g.hw(qu), 2.0)) + 0.003 * sl
    )
    var pl = V3(px, py, g.z(qu))
    rig.set("pelBaseL", pl)
    rig.set("pelFrontL", pl + V3(0.02 * sl, -0.004 * sl, 0.004 * sl))
    rig.set(
        "pelTipL",
        pl
        + _fin_dir(
            90.0 - g.v.v_sweep, 90.0 - g.v.v_sweep * 0.2, g.v.v_abduct, True
        )
        * (g.v.v_len * g.fin_k * sl),
    )
    rig.mirror_joints()
    swimmer_bones(
        rig,
        n,
        m,
        g.pick_parent(g.v.p_u),
        g.pick_parent(g.v.v_u),
        upper_jaw=True,
    )
    return rig^


def _median_rays(g: _Geo, d: _Median, dorsal: Bool) -> List[Float64]:
    # The rays of a dorsal or anal fin, in the median plane (z, y).
    var sl = g.sl
    var rays = List[Float64]()
    for i in range(d.n):
        var f = 0.0 if d.n == 1 else Float64(i) / Float64(d.n - 1)
        var u = d.u0 + (d.u1 - d.u0) * f
        var a = (d.a0 + (d.a1 - d.a0) * f) * pi / 180.0
        var l = d.l0 + (d.l1 - d.l0) * f
        var bz = g.z(u)
        var by: Float64
        if dorsal:
            if d.round:
                l *= 0.78 + 0.34 * sin(pi * min(1.0, f * 1.15 + 0.08))
            if d.spiny:
                l *= 1.0 - 0.18 * f * f
            var plain = not d.round and not d.spiny
            if plain:
                l *= 1.0 - 0.12 * pow(f, 0.7) * (1.0 - f) * 2.5
            by = g.yc(u) + g.hd(u) - 0.006 * sl
        else:
            if d.round:
                l *= 0.8 + 0.3 * sin(pi * min(1.0, f * 1.1 + 0.1))
            by = g.yc(u) - g.hd(u) + 0.006 * sl
        rays.append(bz)
        rays.append(by)
        rays.append(bz + cos(a) * l * sl)
        rays.append(by + sin(a) * l * sl)
    return rays^


def _adipose_rays(g: _Geo) -> List[Float64]:
    var sl = g.sl
    var rays = List[Float64]()
    for i in range(6):
        var f = Float64(i) / 5.0
        var u = g.v.ad_u0 + (g.v.ad_u1 - g.v.ad_u0) * f
        var bz = g.z(u)
        var by = g.yc(u) + g.hd(u) - 0.006 * sl
        var l = (
            g.v.ad_h * sl * (0.35 + 0.75 * sin(pi * min(1.0, f * 0.9 + 0.1)))
        )
        var a = (100.0 + 60.0 * f) * pi / 180.0
        rays.append(bz)
        rays.append(by)
        rays.append(bz + cos(a) * l)
        rays.append(by + sin(a) * l)
    return rays^


def _caudal_rays(g: _Geo) -> List[Float64]:
    # Rays fan from the hypural plate. A positive fork shortens the middle
    # rays, a negative one lengthens them.
    var sl = g.sl
    var h1 = g.hd(1.0)
    var yb = g.yc(1.0)
    var zb0 = g.z(1.0)
    var n = g.v.c_n
    var rays = List[Float64]()
    for i in range(n):
        var f = Float64(i) / Float64(n - 1)
        var e = 1.0 - 2.0 * f
        var a = pi + e * g.v.c_spread * pi / 180.0
        var mid = 1.0 - pow(abs(e), 1.3 if g.v.c_pointed else 2.2)
        var l = g.tail_len * sl * (1.0 - g.v.c_fork * mid)
        if not g.v.c_pointed:
            l *= 1.0 - 0.1 * pow(abs(e), 4.0)
        var bz = zb0 + 0.012 * sl
        var by = yb + e * h1 * 0.78
        rays.append(bz)
        rays.append(by)
        rays.append(bz + cos(a) * l)
        rays.append(by - sin(a) * l)
    return rays^


def _pectoral_rays(g: _Geo) -> List[Float64]:
    var sl = g.sl
    var bl = 0.036 * sl
    var big_l = g.v.p_len * g.fin_k * sl
    var n = g.v.p_n
    var lens = List[Float64]()
    for i in range(n):
        var f = 0.0 if n == 1 else Float64(i) / Float64(n - 1)
        var l: Float64
        if g.v.p_shape == POINTED:
            l = (
                big_l
                * (1.0 - 0.55 * pow(f, 1.2))
                * (0.8 + 0.2 * min(1.0, f * 6.0))
            )
        elif g.v.p_shape == SICKLE:
            l = (
                big_l
                * (1.0 - 0.78 * pow(f, 0.8))
                * (0.7 + 0.3 * min(1.0, f * 8.0))
            )
        else:
            l = big_l * (0.72 + 0.3 * sin(pi * min(1.0, f * 1.05 + 0.12)))
        lens.append(l)
    return fan_rays(
        -0.004 * sl,
        bl * 0.55,
        0.002 * sl,
        -bl * 0.45,
        12.0 if g.v.p_shape == SICKLE else 15.0,
        -17.0,
        lens,
    )


def _pelvic_rays(g: _Geo) -> List[Float64]:
    var sl = g.sl
    var bl = 0.026 * sl
    var big_l = g.v.v_len * g.fin_k * sl
    var n = g.v.v_n
    var lens = List[Float64]()
    for i in range(n):
        var f = 0.0 if n == 1 else Float64(i) / Float64(n - 1)
        lens.append(
            big_l
            * (1.0 - 0.45 * pow(f, 1.1))
            * (0.85 + 0.15 * min(1.0, f * 5.0))
        )
    return fan_rays(
        0.002 * sl, bl * 0.5, -0.002 * sl, -bl * 0.5, 18.0, -14.0, lens
    )


def _paired_plane(
    rig: Rig, base: String, aux: String, tip: String
) raises -> Tuple[V3, V3, V3]:
    var b = rig.j(base)
    var u = normalize(rig.j(tip) - b)
    var v = fin_plane_v(u, rig.j(aux) - b)
    return (b, u, v)


def fish_sculpt(mut m: SdfModel, rig: Rig, t: Traits) raises:
    """Sculpt the fish: procedural-animals' `sculptFish`, primitive for
    primitive.

    The body is a chain of elliptic sections. The gill covers are plates
    free along their rear edge, the lower jaw is cut from the same
    sections by two complementary profile prisms, and every fin is a
    membrane.

    Args:
        m: The sculpt to add to.
        rig: The fish's rig in bind pose.
        t: The individual.

    Raises:
        Error: If the rig lacks a joint or a bone, or the sculpt refuses
            a primitive.
    """
    var g = _geo(t)
    var sl = g.sl
    var ft = sl * CELL * g.v.cell_k * 2.9
    var step = 0.018

    # BODY: the sections along the outline table.
    var u = 0.012
    while u <= 1.0001:
        _body_station(m, rig, g, min(u, 1.0))
        u += step
    # The caudal peduncle runs on into the fin base.
    _ = m.ell(
        "body",
        rig.bone("caudal0"),
        V3(0.0, g.yc(1.0), g.z(1.025)),
        V3(g.hw(1.0) * 0.8, g.hd(1.0) * 0.92, 0.035 * sl),
        k=(0.008 * sl),
    )

    # HEAD: the gill covers, the bluegill's ear flap and the upper lip.
    var op = g.v.op
    for side in [String("L"), String("R")]:
        var s = 1.0 if side == "L" else -1.0
        var uc = op - 0.055
        var c = g.flank(uc, 0.02, s)
        var nrm = normalize(V3(s, 0.0, 0.12))
        _ = m.ell(
            "operculum",
            rig.bone("operculum" + side),
            c - nrm * (0.0205 * sl),
            V3(0.0225 * sl, g.hd(uc) * 0.78, 0.062 * sl),
            k=(0.014 * sl),
        )
        if g.v.ear_flap > 0.0:
            var ce = g.flank(op + 0.03, 0.2, s)
            _ = m.ell(
                "earflap",
                rig.bone("operculum" + side),
                ce - V3(s * 0.0035 * sl, 0.0, 0.0),
                V3(
                    0.0065 * sl,
                    g.v.ear_flap * 0.5 * sl,
                    g.v.ear_flap * 0.8 * sl,
                ),
                k=(0.004 * sl),
            )
    _ = m.ell(
        "lip",
        rig.bone("upperJaw"),
        V3(0.0, g.mouth_y + 0.01 * sl, g.z(0.02)),
        V3(g.hw(0.03) * 0.95, 0.012 * sl, 0.022 * sl),
        k=(0.006 * sl),
    )

    # CARVERS: the lower jaw's profile prism cut out of the body.
    var gape = g.v.gape
    var jd = g.v.jaw_depth * sl
    var zs = g.z0 + 0.03 * sl
    var y_low = -0.05 * sl
    var zc = g.z(gape)
    var zh = g.z(gape + 0.03)
    var zb = g.z(gape + 0.075)
    var up = g.v.upturn * 0.012 * sl
    var my = g.mouth_y
    var jaw_poly: List[Float64] = [
        zs,
        my + up,
        (zs + zc) / 2.0,
        my + up * 0.4,
        zc,
        my,
        zh,
        my - jd * 0.55,
        zb,
        y_low,
        zs,
        y_low,
    ]
    var gap = 0.0013 * sl
    var wide = 0.5 * sl
    var head = rig.bone("head")
    var jaw = rig.bone("jaw")
    var o = V3(0.0, 0.0, 0.0)
    var zax = V3(0.0, 0.0, 1.0)
    var yax = V3(0.0, 1.0, 0.0)
    _ = m.fin(
        "mouthcut",
        head,
        o,
        zax,
        yax,
        offset_poly(jaw_poly, gap * 0.5),
        wide,
        round=0.0,
        k=(0.004 * sl),
        carve=True,
    )
    # The mouth cavity starts behind the lips, so a closed mouth shows
    # only the lip line.
    var uf = MOUTH_LIP
    var ub = gape + 0.035
    var cav_c = V3(0.0, my - 0.003 * sl, g.z((uf + ub) / 2.0))
    var cav_r = V3(
        g.hw((uf + ub) / 2.0) * 0.55,
        min(0.024 * sl, jd * 0.45),
        (ub - uf) / 2.0 * sl,
    )
    _ = m.ell("mouth", head, cav_c, cav_r, k=0.003 * sl, carve=True)

    # LOWER JAW: its own surface, the complement of the jaw prism.
    u = 0.012
    while u <= gape + 0.1:
        _jaw_station(m, rig, g, u)
        u += step
    var big = sl
    var rest: List[Float64] = [
        zs,
        my + up,
        zs,
        my + big,
        zb - big,
        my + big,
        zb - big,
        y_low,
        zb,
        y_low,
        zh,
        my - jd * 0.55,
        zc,
        my,
        (zs + zc) / 2.0,
        my + up * 0.4,
    ]
    _ = m.fin(
        "jawcut",
        jaw,
        o,
        zax,
        yax,
        offset_poly(rest, gap * 0.5),
        wide,
        round=0.0,
        k=(0.004 * sl),
        carve=True,
        part=JAW,
    )
    _ = m.ell("mouth", jaw, cav_c, cav_r, k=0.003 * sl, carve=True, part=JAW)

    # MEDIAN FINS: membranes in the x = 0 plane.
    var sink = 0.022 * sl
    for i in range(len(g.v.dorsal)):
        var d = g.v.dorsal[i]
        _ = sculpt_fin(
            m,
            "dorsal" + String(i),
            rig.bone(g.bone_at((d.u0 + d.u1) / 2.0)),
            o,
            zax,
            yax,
            _median_rays(g, d, True),
            ft,
            sink=sink,
            notch=d.notch,
            k=(ft * 1.2),
        )
    for d in g.v.anal:
        _ = sculpt_fin(
            m,
            "anal",
            rig.bone(g.bone_at((d.u0 + d.u1) / 2.0)),
            o,
            zax,
            yax,
            _median_rays(g, d, False),
            ft,
            sink=sink,
            k=(ft * 1.2),
        )
    if g.v.adipose:
        _ = sculpt_fin(
            m,
            "adipose",
            rig.bone(g.bone_at(g.v.ad_u0)),
            o,
            zax,
            yax,
            _adipose_rays(g),
            0.01 * sl,
            sink=sink,
            k=(0.006 * sl),
            round=0.004 * sl,
        )
    _ = sculpt_fin(
        m,
        "caudal",
        rig.bone("caudal0"),
        o,
        zax,
        yax,
        _caudal_rays(g),
        ft,
        sink=0.03 * sl,
        k=(ft * 1.5),
    )

    # PAIRED FINS: each in the plane of its base line and its direction.
    for side in [String("L"), String("R")]:
        var pec = _paired_plane(
            rig, "pecBase" + side, "pecUp" + side, "pecTip" + side
        )
        _ = sculpt_fin(
            m,
            "pectoral",
            rig.bone("pectoral" + side),
            pec[0],
            pec[1],
            pec[2],
            _pectoral_rays(g),
            ft,
            sink=0.006 * sl,
            k=(ft * 0.9),
        )
        var pel = _paired_plane(
            rig, "pelBase" + side, "pelFront" + side, "pelTip" + side
        )
        _ = sculpt_fin(
            m,
            "pelvic",
            rig.bone("pelvic" + side),
            pel[0],
            pel[1],
            pel[2],
            _pelvic_rays(g),
            ft,
            sink=0.006 * sl,
            k=(ft * 0.9),
        )


def _body_station(mut m: SdfModel, rig: Rig, g: _Geo, u: Float64) raises:
    var sl = g.sl
    var rz = min(0.05, u * 0.95 + 0.004) * sl
    _ = m.ell(
        "head" if u < g.v.op else "body",
        rig.bone(g.bone_at(u)),
        V3(0.0, g.yc(u), g.z(u)),
        V3(g.hw(u), g.hd(u), rz),
        k=(0.007 * sl),
    )


def _jaw_station(mut m: SdfModel, rig: Rig, g: _Geo, u: Float64) raises:
    var sl = g.sl
    var rz = min(0.05, u * 0.95 + 0.004) * sl
    _ = m.ell(
        "jaw",
        rig.bone("jaw"),
        V3(0.0, g.yc(u), g.z(u)),
        V3(g.hw(u), g.hd(u), rz),
        k=(0.007 * sl),
        part=JAW,
    )


def _swatches() -> List[String]:
    return [
        String("back"),
        "upper",
        "band",
        "lower",
        "belly",
        "spot",
        "fin",
        "finEdge",
        "head",
        "cheek",
        "gill",
        "ear",
        "breast",
    ]


def _colors(variant: Int) -> List[Int]:
    if variant == GOLDFISH:
        return [
            0xE0691A,
            0xEE8A1E,
            0xEF8E22,
            0xF29A30,
            0xF6B25A,
            0xF4F1EA,
            0xF5A04A,
            0xF6B872,
            0xEE8A1E,
            0xF09A34,
            0x8A2020,
            0x0F0F12,
            0xD9722A,
        ]
    if variant == CLOWNFISH:
        return [
            0xE85A14,
            0xF26B1D,
            0xF26B1D,
            0xF47A28,
            0xF58A38,
            0xF7F7F2,
            0xF07A25,
            0x111111,
            0xF26B1D,
            0xF57D30,
            0x7A1C1C,
            0x0F0F12,
            0xD9722A,
        ]
    if variant == BLUEGILL:
        return [
            0x4A5236,
            0x6E7250,
            0x76784E,
            0x9A8A50,
            0xD8B050,
            0x33362A,
            0x55543C,
            0x4C4A36,
            0x666A48,
            0x4A5AA0,
            0x6E1C1C,
            0x0F0F12,
            0xD9722A,
        ]
    return [
        0x56604A,
        0x80846A,
        0xB66F78,
        0xC2C6BE,
        0xE9E9E2,
        0x1D1D19,
        0x5E5C42,
        0xE8E6DC,
        0x6F7456,
        0xC97884,
        0x7A1C22,
        0x0F0F12,
        0xD9722A,
    ]


def fish_palette(t: Traits) raises -> Palette:
    """Return one fish's palette: its variant's colors, sampled from
    reference photos.

    Args:
        t: The individual.

    Returns:
        The palette, in linear light.

    Raises:
        Error: If the palette tables differ in length.
    """
    return palette_of(_swatches(), _colors(t.variant))


def _clown_bands(g: _Geo, u: Float64, e0: Float64) -> Float64:
    # Three white bands, as a signed distance in meters (< 0 inside).
    var sl = g.sl
    var e = clamp(e0, -1.1, 1.1)
    var b1 = (abs(u - (0.235 - 0.05 * e * e + 0.01 * e)) - 0.045) * sl
    var bulge = exp(-e * e * 4.0)
    var b2 = (
        abs(u - (0.53 + 0.07 * bulge - 0.03)) - (0.05 + 0.012 * bulge)
    ) * sl
    var b3 = (abs(u - 0.905) - 0.035) * sl
    return min(b1, min(b2, b3))


def _spot(p: V3, cell: Float64, radius: Float64, seed: Int) -> Float64:
    # Round spots laid out by cell noise: one in each cell, its size
    # varied. Returns a signed distance in meters, below zero inside.
    var c = cells3(p * (1.0 / cell), seed)
    var r = radius * (0.7 + 0.6 * c.id)
    return c.nearest * cell - r


def _tweak(c: V3, shade: Float64, k: Float64) -> V3:
    return V3(
        c.x * (1.0 + shade * 0.12 * k),
        c.y * (1.0 + shade * 0.08 * k),
        c.z * (1.0 + shade * 0.04 * k),
    )


def fish_paint(
    pal: Palette, t: Traits, tag: String, bone: String, s: CoatSample
) -> Paint:
    """Paint one vertex of a fish.

    The trout is olive above a pink lateral band and a silver belly,
    peppered with black spots on the back and the fins. The goldfish is
    metallic orange, red, white, or patched with white (sarasa). The
    clownfish wears three white bands edged in black, and black fin
    margins. The bluegill has dusky bars, a blue cheek, a black ear flap
    and, in a breeding male, an orange breast. The head in front of the
    gill cover's edge is scaleless wet skin.

    Args:
        pal: The individual's palette.
        t: The individual.
        tag: The tag of the solid the vertex lies on.
        bone: The bone that solid rides.
        s: The vertex.

    Returns:
        The paint.
    """
    var g = _geo(t)
    var sl = g.sl
    var p = s.p
    var n = s.n
    var key = t.variant
    var morph = Int(t.get("morph", 0.0))
    var shade = t.get("coatShade", 0.0)
    var seed = Int(t.get("coatSeed", 0.0)) % 9973
    var noise = fbm3(p * (9.0 / sl), 3) - 0.5
    var u = clamp(g.u(p.z), 0.0, 1.3)
    var uc = min(u, 1.0)
    var e = (p.y - g.yc(uc)) / max(1e-6, g.hd(uc))
    var is_fin = (
        tag.startswith("dorsal")
        or tag == "anal"
        or tag == "caudal"
        or tag == "pectoral"
        or tag == "pelvic"
    )
    if is_fin:
        return _paint_fin(pal, t, g, tag, bone, p, noise)
    var k = 0
    var e1 = (p.y - g.yc(clamp(u, 0.0, 1.0))) / max(
        1e-6, g.hd(clamp(u, 0.0, 1.0))
    )
    # The head, in front of the gill cover's free edge, is scaleless: a
    # soft weight, so its colors fade into the body's.
    var hk = smoothstep(
        0.004, -0.004, u - _op_edge_u(g.v.op, clamp(e1, -1.2, 1.2))
    )
    if hk > 0.5:
        k = 1
    if s.part == JAW:
        k = 6
        hk = 1.0
    if tag == "adipose":
        k = 5
    if tag == "earflap":
        k = 7
    # The lip line: the cut between the upper and the lower jaw.
    var lip_y = g.mouth_y + g.v.upturn * 0.012 * sl * smoothstep(
        g.v.gape, 0.0, u
    )
    var lip_cut = (
        smoothstep(0.004 * sl, 0.0015 * sl, abs(p.y - lip_y))
        * smoothstep(g.v.gape + 0.02, g.v.gape - 0.01, u)
        * smoothstep(0.35, 0.8, abs(n.x) + abs(n.z) * 0.5)
    )
    var upw = smoothstep(-0.2, 0.9, e * 0.8 + n.y * 0.35)
    var low_k = smoothstep(0.2, -0.85, e * 0.85 + n.y * 0.25)
    var c: V3
    if key == TROUT:
        c = mix3(pal.get("lower"), pal.get("upper"), smoothstep(-0.35, 0.3, e))
        c = mix3(c, pal.get("back"), smoothstep(0.35, 0.95, upw))
        c = mix3(c, pal.get("belly"), smoothstep(0.4, 0.95, low_k))
        # The pink lateral band from the gill cover to the tail.
        var band = (
            (1.0 - smoothstep(0.1, 0.34, abs(e - 0.02)))
            * smoothstep(0.16, 0.3, u)
            * t.get("bandK")
        )
        c = mix3(c, pal.get("band"), band * 0.55)
        var cheek = (1.0 - smoothstep(0.2, 0.7, abs(e + 0.1))) * smoothstep(
            0.1, 0.2, u
        )
        var face = mix3(
            mix3(c, pal.get("head"), 0.25),
            pal.get("cheek"),
            cheek * 0.6 * t.get("bandK"),
        )
        c = mix3(c, face, hk)
    elif key == GOLDFISH:
        c = mix3(pal.get("lower"), pal.get("upper"), smoothstep(-0.5, 0.3, e))
        c = mix3(c, pal.get("back"), smoothstep(0.45, 0.95, upw))
        c = mix3(c, pal.get("belly"), smoothstep(0.35, 0.95, low_k))
        if morph == 3:
            c = mix3(
                srgb(0xF1EEE6), srgb(0xF6E7C8), smoothstep(0.3, 0.9, upw) * 0.4
            )
        if morph == 1:
            c = mix3(c, srgb(0xD83414), 0.72)
        if morph == 0:
            var hue = t.get("hueShift", 0.5) - 0.5
            c = mix3(c, srgb(0xF5A834), -hue * 1.1) if hue < 0.0 else mix3(
                c, srgb(0xE85A18), hue * 0.8
            )
    elif key == CLOWNFISH:
        c = mix3(pal.get("lower"), pal.get("upper"), smoothstep(-0.5, 0.2, e))
        c = mix3(c, pal.get("back"), smoothstep(0.5, 1.0, upw) * 0.6)
        c = mix3(c, pal.get("belly"), smoothstep(0.5, 1.0, low_k) * 0.5)
        if morph == 1:
            c = mix3(c, srgb(0x1C120C), 0.85)
    else:
        # Olive back, brassy flanks, an orange or yellow breast, dusky
        # vertical bars and a blue cheek.
        c = mix3(pal.get("lower"), pal.get("upper"), smoothstep(-0.5, 0.25, e))
        c = mix3(c, pal.get("back"), smoothstep(0.4, 0.95, upw))
        var breast = smoothstep(0.1, 0.85, low_k) * (
            1.0 - smoothstep(0.35, 0.6, u)
        )
        c = mix3(
            c,
            pal.get("breast") if t.male() else pal.get("belly"),
            breast * 0.85,
        )
        c = mix3(
            c,
            pal.get("belly"),
            smoothstep(0.55, 1.0, low_k) * (1.0 - breast) * 0.5,
        )
        var bar_ph = (u - 0.3) / 0.105
        var in_bars = u > 0.28 and u < 0.95
        var bar = (
            pow(0.5 + 0.5 * cos(bar_ph * 2.0 * pi), 3.0)
            * smoothstep(-0.7, 0.2, e) if in_bars else 0.0
        )
        c = mix3(c, pal.get("spot"), bar * 0.45 * t.get("barK"))
        if hk > 0.0:
            var streak = 0.5 + 0.5 * sin(
                (p.y - g.axis_y) / sl * 90.0 + u * 30.0
            )
            var zone = (
                (1.0 - smoothstep(0.15, 0.45, abs(e + 0.35)))
                * smoothstep(0.1, 0.18, u)
                * (1.0 - smoothstep(0.28, 0.33, u))
            )
            c = mix3(
                c,
                pal.get("cheek"),
                zone * smoothstep(0.55, 0.85, streak) * 0.5 * hk,
            )
        if k == 7:
            c = pal.get("ear")
        var flap = k == 0 or k == 1
        if flap:
            # The opercular flap: a black lobe at the top rear of the
            # gill cover.
            var fz = (u - (g.v.op + 0.03)) / 0.058
            var fy = (p.y - (g.yc(g.v.op) + 0.2 * g.hd(g.v.op))) / (0.034 * sl)
            var rr = fz * fz + fy * fy
            c = mix3(c, pal.get("ear"), smoothstep(1.25, 0.9, rr))
    # The lips' cut faces, a little darker, toward the mouth's pink.
    c = mix3(c, mix3(c * 0.85, srgb(0xB88A80), 0.3), lip_cut)
    # The gill cover's free edge: a soft shading line.
    var ec = clamp(e, -1.2, 1.2)
    var du = u - _op_edge_u(g.v.op, ec)
    var edge_line = 0.0
    if k == 0 or k == 1:
        edge_line = (
            smoothstep(-0.005, 0.0, du)
            * (1.0 - smoothstep(0.0015, 0.008, du))
            * (1.0 - smoothstep(0.62, 0.9, abs(ec + 0.05)))
        )
    c = c * (1.0 - 0.15 * edge_line)
    c = mix3(c, c * 0.8, 0.25 * (noise + 0.5))
    c = _tweak(c, shade, 1.0)
    # Spots and patches.
    if key == TROUT:
        var spotted = k == 0 or k == 1 or k == 5
        var dens = smoothstep(-0.35, 0.25, e) * (0.0 if u < 0.1 else 1.0)
        if spotted and dens > 0.2:
            var rad = (0.0042 + 0.003 * dens) * sl * t.get("spotScale")
            var d = _spot(p, 0.03 * sl, rad, seed)
            c = mix3(
                c, pal.get("spot"), smoothstep(0.0006 * sl, -0.0006 * sl, d)
            )
    if key == GOLDFISH and morph == 2:
        var patched = k == 0 or k == 1 or k == 6
        if patched:
            var q = p + V3(1.0, 1.0, 1.0) * (
                0.04 * sl * (fbm3(p * (14.0 / sl), 2) - 0.5)
            )
            var d = _spot(q, 0.12 * sl, 0.07 * sl, seed)
            c = mix3(c, pal.get("spot"), smoothstep(0.004 * sl, -0.004 * sl, d))
    if key == CLOWNFISH:
        var bands = _clown_bands(g, u, e)
        c = mix3(
            c, pal.get("spot"), smoothstep(0.0012 * sl, -0.0012 * sl, bands)
        )
        var edge = abs(bands) - 0.012 * sl * t.get("edgeK")
        c = mix3(c, srgb(0x0A0A0B), smoothstep(0.001 * sl, -0.001 * sl, edge))
    var wet = k == 1 or k == 6
    return Paint(c, WET if wet else SCALES)


def _paint_fin(
    pal: Palette,
    t: Traits,
    g: _Geo,
    tag: String,
    bone: String,
    p: V3,
    noise: Float64,
) -> Paint:
    # A fin membrane, painted along its rays.
    var key = t.variant
    var morph = Int(t.get("morph", 0.0))
    var sl = g.sl
    var rays: List[Float64]
    var qu: Float64
    var qv: Float64
    if tag == "pectoral" or tag == "pelvic":
        var side = bone.endswith("L")
        var s = 1.0 if side else -1.0
        var pec = tag == "pectoral"
        var base: V3
        var aux: V3
        var tip: V3
        try:
            var rig = fish_rig(t)
            var sfx = String("L") if side else String("R")
            base = rig.j(("pecBase" if pec else "pelBase") + sfx)
            aux = rig.j(("pecUp" if pec else "pelFront") + sfx)
            tip = rig.j(("pecTip" if pec else "pelTip") + sfx)
        except:
            base = V3(0.0, 0.0, 0.0)
            aux = V3(0.0, s, 0.0)
            tip = V3(0.0, 0.0, -1.0)
        var fu = normalize(tip - base)
        var fv = fin_plane_v(fu, aux - base)
        qu = dot(p - base, fu)
        qv = dot(p - base, fv)
        rays = _pectoral_rays(g) if pec else _pelvic_rays(g)
    else:
        qu = p.z
        qv = p.y
        if tag == "caudal":
            rays = _caudal_rays(g)
        elif tag == "anal":
            rays = _median_rays(g, g.v.anal[0], False)
        elif tag == "dorsal1":
            rays = _median_rays(g, g.v.dorsal[1], True)
        else:
            rays = _median_rays(g, g.v.dorsal[0], True)
    var rc = fin_ray_coords(rays, qu, qv)
    var along = rc.along
    var c = pal.get("fin")
    c = mix3(
        c, mix3(c, pal.get("back"), 0.4), smoothstep(0.5, 0.0, along) * 0.5
    )
    # The fin rays: faint darker lines between the clear membrane.
    var ray_line = abs(rc.phase - floor(rc.phase + 0.5))
    c = c * (0.9 + 0.12 * smoothstep(0.0, 0.35, ray_line))
    if key == TROUT:
        var low_fin = tag == "pelvic" or tag == "anal"
        if low_fin:
            if rc.phase < 1.2:
                c = mix3(c, pal.get("finEdge"), 0.85)
            c = mix3(c, srgb(0xB58A6A), 0.3)
        var spotted = tag.startswith("dorsal") or tag == "caudal"
        if spotted:
            var d = _spot(
                p, 0.03 * sl, 0.0075 * sl, Int(t.get("coatSeed", 0.0)) % 9973
            )
            c = mix3(
                c, pal.get("spot"), smoothstep(0.0006 * sl, -0.0006 * sl, d)
            )
    elif key == GOLDFISH:
        c = mix3(
            pal.get("fin"), pal.get("finEdge"), smoothstep(0.3, 1.0, along)
        )
    elif key == CLOWNFISH:
        # Black margins: the outer band of every fin but the pectorals.
        if tag != "pectoral":
            var margin = 0.13 * t.get("edgeK")
            c = mix3(
                c,
                pal.get("finEdge"),
                smoothstep(1.0 - margin - 0.02, 1.0 - margin + 0.02, along),
            )
        if morph == 1:
            c = mix3(c, srgb(0x2A160C), 0.7)
    else:
        if tag == "dorsal1":
            # The dark blotch at the rear of the soft dorsal fin.
            var ph = rc.phase / max(1.0, Float64(len(rays) // 4 - 1))
            var d = (
                sqrt(
                    pow((ph - 0.88) * 0.55, 2.0)
                    + pow((along - 0.32) * 0.45, 2.0)
                )
                - 0.16
            )
            c = mix3(c, srgb(0x1E1E18), 0.9 * smoothstep(0.01, -0.01, d))
        if tag == "pelvic" or tag == "anal":
            c = mix3(c, srgb(0x3C3A2C), 0.5)
    c = _tweak(c, t.get("coatShade", 0.0), 0.5)
    c = c * (0.94 + 0.12 * noise)
    return Paint(c, SCALES)
